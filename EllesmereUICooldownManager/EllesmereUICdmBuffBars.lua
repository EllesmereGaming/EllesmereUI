--------------------------------------------------------------------------------
--  EllesmereUICdmBuffBars.lua  (v4 rewrite)
--  Tracking Bars: StatusBar reskins driven entirely by Blizzard CDM children.
--  Requires tracked spells to be assigned to a CDM bar so Blizzard computes
--  all active-state, duration, and stack data.  Zero independent aura calls.
--------------------------------------------------------------------------------
local _, ns = ...

local floor   = math.floor
local format  = string.format
local GetTime = GetTime
local pcall   = pcall
local max     = math.max
local abs     = math.abs
local min     = math.min

-- Set once during BuildTrackedBuffBars (ECME.db is not ready at file load)
local ECME

-- Feature-gating flags (rebuilt in BuildTrackedBuffBars, read in tick)
local _anyPandemic  = false
local _anyThreshold = false
local _anyStacks    = false

-- Glow helpers (from main CDM file)
local function StartGlow(...) if ns.StartNativeGlow then return ns.StartNativeGlow(...) end end
local function StopGlow(...)  if ns.StopNativeGlow  then return ns.StopNativeGlow(...)  end end

-- External weak-keyed lookup for Blizzard bar FontString refs.
-- Avoids writing custom properties onto Blizzard StatusBar frames.
local _blizzBarFS = setmetatable({}, { __mode = "k" })
local function BBFS(bar)
    local d = _blizzBarFS[bar]
    if not d then d = {}; _blizzBarFS[bar] = d end
    return d
end

-------------------------------------------------------------------------------
--  Textures
-------------------------------------------------------------------------------
local TBB_TEX_BASE = "Interface\\AddOns\\EllesmereUI\\media\\textures\\"
local TBB_TEXTURES = {
    ["none"]          = nil,
    ["melli"]         = TBB_TEX_BASE .. "melli.tga",
    ["beautiful"]     = TBB_TEX_BASE .. "beautiful.tga",
    ["plating"]       = TBB_TEX_BASE .. "plating.tga",
    ["atrocity"]      = TBB_TEX_BASE .. "atrocity.tga",
    ["divide"]        = TBB_TEX_BASE .. "divide.tga",
    ["glass"]         = TBB_TEX_BASE .. "glass.tga",
    ["fade-right"]    = TBB_TEX_BASE .. "fade-right.tga",
    ["thin-line-top"]    = TBB_TEX_BASE .. "thin-line-top.tga",
    ["thin-line-bottom"] = TBB_TEX_BASE .. "thin-line-bottom.tga",
    ["fade"]          = TBB_TEX_BASE .. "fade.tga",
    ["gradient-lr"]   = TBB_TEX_BASE .. "gradient-lr.tga",
    ["gradient-rl"]   = TBB_TEX_BASE .. "gradient-rl.tga",
    ["gradient-bt"]   = TBB_TEX_BASE .. "gradient-bt.tga",
    ["gradient-tb"]   = TBB_TEX_BASE .. "gradient-tb.tga",
    ["matte"]         = TBB_TEX_BASE .. "matte.tga",
    ["sheer"]         = TBB_TEX_BASE .. "sheer.tga",
}
local TBB_TEXTURE_ORDER = {
    "none", "melli", "atrocity",
    "fade", "fade-right",
    "thin-line-top", "thin-line-bottom",
    "beautiful", "plating",
    "divide", "glass",
    "gradient-lr", "gradient-rl", "gradient-bt", "gradient-tb",
    "matte", "sheer",
}
local TBB_TEXTURE_NAMES = {
    ["none"]        = "None",
    ["melli"]       = "Melli (ElvUI)",
    ["beautiful"]   = "Beautiful",
    ["plating"]     = "Plating",
    ["atrocity"]    = "Atrocity",
    ["divide"]      = "Divide",
    ["glass"]       = "Glass",
    ["fade-right"]  = "Fade Right",
    ["thin-line-top"]    = "Thin Line Top",
    ["thin-line-bottom"] = "Thin Line Bottom",
    ["fade"]        = "Fade",
    ["gradient-lr"] = "Gradient Right",
    ["gradient-rl"] = "Gradient Left",
    ["gradient-bt"] = "Gradient Up",
    ["gradient-tb"] = "Gradient Down",
    ["matte"]       = "Matte",
    ["sheer"]       = "Sheer",
}
ns.TBB_TEXTURES      = TBB_TEXTURES
ns.TBB_TEXTURE_ORDER = TBB_TEXTURE_ORDER
ns.TBB_TEXTURE_NAMES = TBB_TEXTURE_NAMES

-------------------------------------------------------------------------------
--  Shared Helpers
-------------------------------------------------------------------------------
local function FormatTime(remaining)
    if remaining >= 3600 then return format("%dh", floor(remaining / 3600)) end
    if remaining >= 60   then return format("%dm", floor(remaining / 60))   end
    if remaining >= 10   then return format("%d",  floor(remaining))        end
    return format("%.1f", remaining)
end

local CDM_FONT_FALLBACK = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"
local function GetFont()
    return (ns.GetCDMFont and ns.GetCDMFont()) or CDM_FONT_FALLBACK
end
local function GetOutline()
    if EllesmereUI and EllesmereUI.GetFontOutlineFlag then
        return EllesmereUI.GetFontOutlineFlag("cdm")
    end
    return "OUTLINE, SLUG"
end
local function SetFont(fs, size)
    if not (fs and fs.SetFont) then return end
    local useShadow = EllesmereUI and EllesmereUI.GetFontUseShadow and EllesmereUI.GetFontUseShadow("cdm")
    if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(fs, useShadow) end
    fs:SetFont(GetFont(), size, GetOutline())
end

-------------------------------------------------------------------------------
--  Pandemic state via Blizzard hooks
-------------------------------------------------------------------------------
local _pandemicState  = {}   -- frame -> true when in pandemic
local _pandemicHooked = {}   -- frame -> true once hooks are installed
ns._pandemicState = _pandemicState

function ns.HookPandemicState(frame)
    if not frame or _pandemicHooked[frame] then return end
    if not frame.ShowPandemicStateFrame then return end
    _pandemicHooked[frame] = true
    hooksecurefunc(frame, "ShowPandemicStateFrame", function(self)
        _pandemicState[self] = true
        -- Hide Blizzard's PandemicIcon unless "Blizzard Default" (-1).
        -- Custom glow styles (>0) replace it; None (0/false) suppresses it.
        local fc = ns._ecmeFC and ns._ecmeFC[self]
        local bk = fc and fc.barKey
        if bk then
            local bd = ns.barDataByKey and ns.barDataByKey[bk]
            local style = bd and bd.pandemicGlow and bd.pandemicGlowStyle
            if not style or style ~= -1 then
                if self.PandemicIcon then self.PandemicIcon:Hide() end
            end
        end
    end)
    if frame.HidePandemicStateFrame then
        hooksecurefunc(frame, "HidePandemicStateFrame", function(self)
            _pandemicState[self] = nil
        end)
    end
end

local PANDEMIC_THRESHOLD = 0.3
local LIFEBLOOM_SPELL_ID = 33763
local _lbName               -- cached Lifebloom spell name (resolved lazily once)
local _scanLast, _scanResult = 0, false
-- Pandemic fallback for auras Blizzard never flags (currently only Lifebloom).
-- bar._isLifebloom is resolved once and cached on our own frame: the call site
-- skips this call entirely once a bar is known not to be Lifebloom, so
-- non-Lifebloom pandemic-glow bars cost nothing per frame. Only the Lifebloom
-- bar reaches the throttled unit scan below.
local function LifebloomPandemic(bar, blzChild)
    -- Resolve "is this the Lifebloom bar" once and cache it. Spell data can be
    -- late-loading, so leave the flag nil (retry next frame) until both names
    -- resolve.
    if bar._isLifebloom == nil then
        if not _lbName then _lbName = C_Spell.GetSpellName(LIFEBLOOM_SPELL_ID) end
        local sid = ns.GetCanonicalSpellIDForFrame and ns.GetCanonicalSpellIDForFrame(blzChild)
        local sName = sid and C_Spell.GetSpellName(sid)
        if not (_lbName and sName) then return false end
        bar._isLifebloom = (_lbName == sName)
    end
    if not bar._isLifebloom then return false end

    -- Throttle the unit scan to 10/sec; return the cached result if throttled.
    local now = GetTime()
    if (now - _scanLast) < 0.1 then return _scanResult end

    local result = false
    local function check(unit)
        if not UnitExists(unit) then return end
        local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, _lbName, "HELPFUL|PLAYER")
        if not ok or not aura then return end
        local dur, exp = aura.duration, aura.expirationTime
        if not dur or not exp then return end
        local isSec = issecretvalue
        if isSec and (isSec(dur) or isSec(exp)) then return end -- shouldn't be secret, for safety
        if dur <= 0 then return end
        if (exp - now) <= dur * PANDEMIC_THRESHOLD then result = true end
    end

    -- Player first, then the group; stop as soon as one Lifebloom is in pandemic.
    check("player")
    if not result then
        if IsInRaid() then
            for i = 1, GetNumGroupMembers() do
                check("raid" .. i)
                if result then break end
            end
        elseif IsInGroup() then
            for i = 1, GetNumGroupMembers() do
                check("party" .. i)
                if result then break end
            end
        end
    end
    _scanLast, _scanResult = now, result
    return result
end

-------------------------------------------------------------------------------
--  Popular Buffs (derived from BUFF_BAR_PRESETS, with compat alias)
-------------------------------------------------------------------------------
local TBB_POPULAR_BUFFS = {}
do
    local presets = ns.BUFF_BAR_PRESETS
    if presets then
        for _, p in ipairs(presets) do
            local entry = {}
            for k, v in pairs(p) do entry[k] = v end
            entry.customDuration = p.duration  -- compat alias
            TBB_POPULAR_BUFFS[#TBB_POPULAR_BUFFS + 1] = entry
        end
    end
end
ns.TBB_POPULAR_BUFFS = TBB_POPULAR_BUFFS

-------------------------------------------------------------------------------
--  Default Bar Config
-------------------------------------------------------------------------------
local _classR, _classG, _classB = 0.05, 0.82, 0.62
do
    local _, ct = UnitClass("player")
    if ct then
        local cc = RAID_CLASS_COLORS[ct]
        if cc then _classR, _classG, _classB = cc.r, cc.g, cc.b end
    end
end

local TBB_DEFAULT_BAR = {
    spellID   = 0,
    name      = "New Bar",
    enabled   = true,
    hideWhenInactive = true,  -- hide the bar unless the tracked aura is active
    grouped   = true,   -- per-bar "Group Tracking Bars" checkbox; checked bars chain + share width/height
    height    = 24,
    width     = 270,
    verticalOrientation = false,
    reverseFill = false,
    texture   = "none",
    fillR = _classR, fillG = _classG, fillB = _classB, fillA = 1,
    bgR = 0, bgG = 0, bgB = 0, bgA = 0.4,
    gradientEnabled = false,
    gradientR = 0.20, gradientG = 0.20, gradientB = 0.80, gradientA = 1,
    gradientDir = "HORIZONTAL",
    opacity   = 1.0,
    showTimer = true,
    timerPosition = "right",
    timerSize = 11,
    timerX = 0, timerY = 0,
    showName  = true,
    namePosition = "left",
    nameSize  = 11,
    nameX = 0, nameY = 0,
    showSpark = true,
    iconDisplay = "none",
    iconSize    = 24,
    iconX = 0, iconY = 0,
    iconBorderSize = 0,
    stacksPosition = "center",
    stacksSize     = 11,
    stacksX = 0, stacksY = 0,
    stackThresholdEnabled = false,
    stackThreshold = 5,
    stackThresholdR = 0.8, stackThresholdG = 0.1, stackThresholdB = 0.1, stackThresholdA = 1,
    stackThresholdMaxEnabled = false,
    stackThresholdMax = 10,
    stackThresholdTicks = "",
    pandemicGlow = true,
    pandemicGlowStyle = -1,
    pandemicGlowColor = { r = 1, g = 1, b = 0 },
    pandemicGlowLines = 8,
    pandemicGlowThickness = 2,
    pandemicGlowSpeed = 4,
}
ns.TBB_DEFAULT_BAR = TBB_DEFAULT_BAR

-------------------------------------------------------------------------------
--  Data Access
-------------------------------------------------------------------------------
function ns.GetTrackedBuffBars()
    -- TBB is spec-specific and per-profile: specProfiles[specKey] under the
    -- active profile's bucket (ns.GetActiveSpecProfiles).
    local specKey = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
    if not specKey then return { selectedBar = 1, bars = {} } end
    local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
    if not sp then return { selectedBar = 1, bars = {} } end
    if not sp[specKey] then sp[specKey] = { barSpells = {} } end
    local prof = sp[specKey]
    if not prof.trackedBuffBars then
        prof.trackedBuffBars = { selectedBar = 1, bars = {} }
    end
    local tbb = prof.trackedBuffBars
    -- Live migration: the old single "Group Tracking Bars" toggle (tbb.groupEnabled)
    -- becomes a per-bar `grouped` checkbox. Convert once per spec table: toggle
    -- ENABLED -> every bar checked; toggle DISABLED or never-set -> every bar
    -- unchecked. TBB config is per-spec/per-profile so there is no SavedVariables
    -- migration pass; this read-time convert is idempotent (guarded by the flag,
    -- then the legacy boolean is cleared so later per-bar edits are never stomped).
    if not tbb._groupMigrated then
        local checked = (tbb.groupEnabled == true)
        for _, b in ipairs(tbb.bars or {}) do b.grouped = checked end
        tbb.groupEnabled = nil
        tbb._groupMigrated = true
    end
    -- Live migration: width/height are now the TOTAL footprint (icon
    -- included). Bars saved before this stored the FILL size and rendered the
    -- icon square as extra on top, so fold that square into the stored dims
    -- once -- the rendered pixels are identical before and after (old fill +
    -- icon = new total). Read-time convert (per-spec data, no SavedVariables
    -- pass), idempotent via the flag; imported old profiles lack the flag and
    -- convert on first read.
    if not tbb._iconTotalMigrated then
        for _, b in ipairs(tbb.bars or {}) do
            if (b.iconDisplay or "none") ~= "none" then
                if b.verticalOrientation then
                    b.height = (b.height or 24) + (b.width or 270)
                else
                    b.width = (b.width or 270) + (b.height or 24)
                end
            end
        end
        tbb._iconTotalMigrated = true
    end
    return tbb
end

function ns.GetTBBPositions()
    -- TBB positions are spec-specific, stored alongside trackedBuffBars in the
    -- active profile's per-spec bucket.
    local specKey = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
    if not specKey then return {} end
    local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
    if not sp or not sp[specKey] then return {} end
    local prof = sp[specKey]
    if not prof.tbbPositions then prof.tbbPositions = {} end
    return prof.tbbPositions
end

-- Create a new bar config (no rebuild). `targetGid` picks its group: nil =
-- follow the last bar's group (quick-add default), 0 = independent, N = that
-- group. The new bar's style comes from its group's style source, so a bar
-- added to a group lands looking exactly like the group; independent bars
-- copy the last bar (legacy behavior). Spell identity and the stack fields
-- always start fresh.
local function AddTrackedBuffBarCore(tbb, targetGid)
    local bars = tbb.bars
    local gid
    if targetGid ~= nil then
        gid = targetGid
    elseif #bars > 0 then
        gid = ns.TBBBarGroupID(bars[#bars])
    else
        gid = 1
    end

    -- Style resolution, in priority order:
    --   1. a preset associated with a bar already in the target group
    --   2. the target group's current look (its style source bar)
    --   3. a preset associated with any bar of this spec, else any saved preset
    --   4. the last bar's look (legacy inherit)
    --   5. plain defaults
    local preset, styleSrc
    if gid ~= 0 and ns.ResolveTBBGroupPreset then
        preset = ns.ResolveTBBGroupPreset(tbb, gid)
    end
    if not preset and gid ~= 0 and ns.TBBGroupStyleSource then
        styleSrc = ns.TBBGroupStyleSource(gid)
    end
    if not preset and not styleSrc and ns.ResolveTBBFallbackPreset then
        preset = ns.ResolveTBBFallbackPreset(tbb)
    end
    if not preset and not styleSrc and #bars > 0 then
        styleSrc = bars[#bars]
    end

    -- Base from pure defaults (spell identity, enable state and the
    -- stack-threshold numbers always start fresh), then dress it: the style
    -- key set is the authoritative visual copy.
    local newBar = {}
    for k, v in pairs(TBB_DEFAULT_BAR) do newBar[k] = v end
    if preset then
        ns.ApplyTBBStylePresetToCfg(preset, newBar)
    elseif styleSrc then
        ns.CopyTBBStyle(styleSrc, newBar)
    end
    newBar.spellID = 0
    newBar.name = "Bar " .. (#bars + 1)
    newBar.popularKey = nil
    newBar.spellIDs = nil
    newBar.baseSpellID = nil
    newBar.customDuration = nil
    newBar.glowBased = nil
    newBar.enabled = true
    ns.TBBSetBarGroup(newBar, gid)
    bars[#bars + 1] = newBar
    tbb.selectedBar = #bars

    -- A group of vertical bars reads better side by side: when a vertical bar
    -- FOUNDS a group whose grow direction was never chosen, default it to
    -- RIGHT instead of the global DOWN.
    if gid ~= 0 and newBar.verticalOrientation and ns.TBBGroupedCount(gid) <= 1 then
        local g = tbb.groups and tbb.groups[tostring(gid)]
        local hasStored = (g and g.grow) or (gid == 1 and tbb.groupGrowDirection)
        if not hasStored then
            ns.TBBSetGroupGrow(gid, "RIGHT")
        end
    end

    -- Auto-position adjacent to previous bar (matters for independent bars;
    -- grouped bars chain off their group anchor anyway)
    local p = ECME and ECME.db and ECME.db.profile
    if p then
        local _tbbPos = ns.GetTBBPositions()
        local prevIdx = #bars - 1
        if prevIdx >= 1 then
            local prevPos = _tbbPos[tostring(prevIdx)]
            local prevCfg = bars[prevIdx]
            if prevPos and prevPos.point then
                local px, py = prevPos.x or 0, prevPos.y or 0
                if newBar.verticalOrientation then
                    -- Step sideways by the previous bar's on-screen width
                    -- (width/height are always visual dimensions).
                    local barW = (prevCfg and prevCfg.width or 24) + 4
                    _tbbPos[tostring(#bars)] = {
                        point = prevPos.point, relPoint = prevPos.relPoint or prevPos.point,
                        x = px + barW, y = py,
                    }
                else
                    local barH = (prevCfg and prevCfg.height or 24) + 4
                    _tbbPos[tostring(#bars)] = {
                        point = prevPos.point, relPoint = prevPos.relPoint or prevPos.point,
                        x = px, y = py + barH,
                    }
                end
            end
        end
    end

    return #bars
end

function ns.AddTrackedBuffBar(targetGid)
    local tbb = ns.GetTrackedBuffBars()
    local idx = AddTrackedBuffBarCore(tbb, targetGid)
    ns.BuildTrackedBuffBars()
    return idx
end

function ns.RemoveTrackedBuffBar(idx)
    local tbb = ns.GetTrackedBuffBars()
    if idx < 1 or idx > #tbb.bars then return end
    local oldCount = #tbb.bars
    table.remove(tbb.bars, idx)
    -- Re-key saved positions so bars after the removed index keep their
    -- coordinates (positions are keyed by bar index).
    local pos = ns.GetTBBPositions()
    for j = idx, oldCount - 1 do
        pos[tostring(j)] = pos[tostring(j + 1)]
    end
    pos[tostring(oldCount)] = nil
    -- Re-key element-anchor / size-match links the same way (TBB_3 -> TBB_2
    -- etc.) so anchors keep tracking the same visual bar; links pointing AT
    -- the deleted bar are severed.
    if EllesmereUI and EllesmereUI.ShiftIndexedAnchorKeys then
        EllesmereUI.ShiftIndexedAnchorKeys("TBB_", idx, oldCount)
    end
    if tbb.selectedBar > #tbb.bars then tbb.selectedBar = max(1, #tbb.bars) end
    ns.BuildTrackedBuffBars()
end

-- Stable identity for the broadcast toggle, AND the single source of truth for
-- whether a bar can be broadcast across specs. A bar is broadcastable only when it
-- points at a spec-agnostic buff:
--   * a preset (popularKey)            -- curated, cross-spec; keyed "p:<key>"
--   * a custom buff ID (user-entered)  -- spec-agnostic;       keyed "s:<spellID>"
-- A Blizzard CDM tracked spell (picked from the live cooldown viewer list) is
-- spec/class-specific and must NEVER be broadcastable. It is told apart from a
-- custom buff by having NO customDuration: the custom-buff popup always stores a
-- duration, while the CDM picker clears it. Freshly-added empty bars return nil.
function ns.TBBBroadcastKey(cfg)
    if type(cfg) ~= "table" then return nil end
    if cfg.popularKey and cfg.popularKey ~= "" then return "p:" .. cfg.popularKey end
    if cfg.spellID and cfg.spellID > 0
       and type(cfg.customDuration) == "number" and cfg.customDuration > 0 then
        return "s:" .. tostring(cfg.spellID)
    end
    return nil
end

-- A bar can be broadcast across specs only when TBBBroadcastKey yields an identity
-- (preset or custom buff). Blizzard CDM spells and empty bars are excluded.
function ns.IsTrackedBuffBarBroadcastable(cfg)
    return ns.TBBBroadcastKey(cfg) ~= nil
end

-- True when the selected bar's buff is currently marked as broadcast to all specs
-- (so the button shows "Remove Bar from All Specs"). Read from the persistent
-- per-profile set.
function ns.IsTrackedBuffBarBroadcast(cfg)
    local key = ns.TBBBroadcastKey(cfg)
    if not key then return false end
    local set = ns.GetActiveTBBBroadcastSet and ns.GetActiveTBBBroadcastSet()
    return set ~= nil and set[key] == true
end

-- Copy a configured bar (preset or custom buff) into every OTHER spec of the
-- player's current class. The bar config and its screen position are deep-copied
-- so it appears identically across specs. Specs that already hold the same
-- preset/custom buff are skipped, so repeated clicks never pile up duplicates.
-- Returns the number of specs the bar was added to.
function ns.AddBarToAllSpecs(srcIdx)
    local DeepCopy = EllesmereUI.Lite and EllesmereUI.Lite.DeepCopy
    if not DeepCopy then return 0 end
    local activeKey = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
    if not activeKey then return 0 end

    local srcTbb = ns.GetTrackedBuffBars()
    local srcBar = srcTbb and srcTbb.bars and srcTbb.bars[srcIdx]
    if not ns.IsTrackedBuffBarBroadcastable(srcBar) then return 0 end

    local srcPos = ns.GetTBBPositions()[tostring(srcIdx)]

    local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
    if not sp then return 0 end

    local function HasSameBar(bars)
        for _, b in ipairs(bars) do
            if srcBar.popularKey and srcBar.popularKey ~= "" then
                if b.popularKey == srcBar.popularKey then return true end
            elseif (not b.popularKey or b.popularKey == "")
                   and b.spellID and b.spellID == srcBar.spellID then
                return true
            end
        end
        return false
    end

    local added = 0
    local numSpecs = GetNumSpecializations and GetNumSpecializations() or 0
    for i = 1, numSpecs do
        local specID = GetSpecializationInfo(i)
        if specID then
            local key = tostring(specID)
            if key ~= activeKey then
                if not sp[key] then sp[key] = { barSpells = {} } end
                local prof = sp[key]
                if not prof.trackedBuffBars then
                    prof.trackedBuffBars = { selectedBar = 1, bars = {} }
                end
                local tbb = prof.trackedBuffBars
                if not HasSameBar(tbb.bars) then
                    local newBar = DeepCopy(srcBar)
                    -- Join the target spec's group only when its existing bars
                    -- all live in ONE group (mirror of the quick-add rule);
                    -- otherwise start independent so we never disturb its
                    -- layout. An empty spec starts the bar in group 1.
                    local gid
                    if #tbb.bars == 0 then
                        gid = 1
                    else
                        gid = ns.TBBBarGroupID(tbb.bars[1])
                        for j = 2, #tbb.bars do
                            if ns.TBBBarGroupID(tbb.bars[j]) ~= gid then gid = 0; break end
                        end
                    end
                    ns.TBBSetBarGroup(newBar, gid)
                    local newIdx = #tbb.bars + 1
                    tbb.bars[newIdx] = newBar
                    if srcPos then
                        if not prof.tbbPositions then prof.tbbPositions = {} end
                        prof.tbbPositions[tostring(newIdx)] = DeepCopy(srcPos)
                    end
                    added = added + 1
                end
            end
        end
    end

    -- Mark this buff as broadcast so the button flips to "Remove..." in every
    -- spec (set even when added == 0, i.e. all specs already held it).
    local set = ns.GetActiveTBBBroadcastSet and ns.GetActiveTBBBroadcastSet()
    if set then
        local key = ns.TBBBroadcastKey(srcBar)
        if key then set[key] = true end
    end

    return added
end

-- Inverse of AddBarToAllSpecs: remove the selected bar's buff from every OTHER
-- spec of the player's class and clear its broadcast flag. The bar in the CURRENT
-- spec is left untouched -- the user keeps editing it here. Returns the number of
-- specs a bar was removed from.
function ns.RemoveBarFromAllSpecs(srcIdx)
    local activeKey = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
    if not activeKey then return 0 end

    local srcTbb = ns.GetTrackedBuffBars()
    local srcBar = srcTbb and srcTbb.bars and srcTbb.bars[srcIdx]
    local broadcastKey = ns.TBBBroadcastKey(srcBar)
    if not broadcastKey then return 0 end

    local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
    if not sp then return 0 end

    local function Matches(b)
        if srcBar.popularKey and srcBar.popularKey ~= "" then
            return b.popularKey == srcBar.popularKey
        else
            return (not b.popularKey or b.popularKey == "")
                   and b.spellID and b.spellID == srcBar.spellID
        end
    end

    local removed = 0
    local numSpecs = GetNumSpecializations and GetNumSpecializations() or 0
    for i = 1, numSpecs do
        local specID = GetSpecializationInfo(i)
        if specID then
            local specKey = tostring(specID)
            if specKey ~= activeKey then
                local prof = sp[specKey]
                local tbb = prof and prof.trackedBuffBars
                if tbb and tbb.bars and #tbb.bars > 0 then
                    -- Rebuild the bar list excluding matches, re-keying positions
                    -- so compacted indices and tbbPositions stay aligned (plain
                    -- table.remove would leave positions keyed by stale indices).
                    local oldPos = prof.tbbPositions or {}
                    local newBars, newPos = {}, {}
                    local didRemove = false
                    for j, b in ipairs(tbb.bars) do
                        if Matches(b) then
                            didRemove = true
                        else
                            newBars[#newBars + 1] = b
                            local p = oldPos[tostring(j)]
                            if p then newPos[tostring(#newBars)] = p end
                        end
                    end
                    if didRemove then
                        tbb.bars = newBars
                        prof.tbbPositions = newPos
                        if tbb.selectedBar and tbb.selectedBar > #newBars then
                            tbb.selectedBar = math.max(1, #newBars)
                        end
                        removed = removed + 1
                    end
                end
            end
        end
    end

    -- Clear the broadcast flag so the button flips back to "Add...".
    local set = ns.GetActiveTBBBroadcastSet and ns.GetActiveTBBBroadcastSet()
    if set then set[broadcastKey] = nil end

    return removed
end

-------------------------------------------------------------------------------
--  Frame Table & State
-------------------------------------------------------------------------------
local tbbFrames  = {}
local tbbTickFrame
local _tbbRebuildPending = false

function ns.GetTBBFrame(idx) return tbbFrames[idx] end

-------------------------------------------------------------------------------
--  Bar grouping helpers (multi-group)
--  Group membership is a per-bar numeric id (cfg.groupId; 0 = independent).
--  Bars saved before multi-group support only carry the legacy boolean
--  cfg.grouped, which is read as a VIEW: grouped (default true) = group 1,
--  unchecked = independent. Writes set groupId and mirror the legacy boolean
--  so exported profiles stay readable by older versions. Each group chains in
--  index order: its first ENABLED member is the group anchor (owns the
--  position/mover), later members chain to it and share its width/height.
-------------------------------------------------------------------------------
function ns.TBBBarGroupID(cfg)
    if not cfg then return 0 end
    if cfg.groupId ~= nil then return cfg.groupId end
    return (cfg.grouped ~= false) and 1 or 0
end

function ns.TBBSetBarGroup(cfg, gid)
    if not cfg then return end
    gid = gid or 0
    cfg.groupId = gid
    -- Legacy mirror: older versions only know one group ("checked" bars).
    cfg.grouped = (gid ~= 0)
end

function ns.TBBBarGrouped(cfg)
    return ns.TBBBarGroupID(cfg) ~= 0
end

-- Sorted list of group ids currently used by at least one bar.
function ns.TBBGroupIDsInUse()
    local t = ns.GetTrackedBuffBars()
    local seen, list = {}, {}
    for _, c in ipairs(t.bars or {}) do
        local gid = ns.TBBBarGroupID(c)
        if gid ~= 0 and not seen[gid] then
            seen[gid] = true
            list[#list + 1] = gid
        end
    end
    table.sort(list)
    return list
end

-- Smallest positive group id not currently in use (fills holes left by
-- dissolved groups so group names stay compact).
function ns.TBBNextGroupID()
    local t = ns.GetTrackedBuffBars()
    local used = {}
    for _, c in ipairs(t.bars or {}) do
        used[ns.TBBBarGroupID(c)] = true
    end
    local gid = 1
    while used[gid] do gid = gid + 1 end
    return gid
end

-- Per-group settings live in tbb.groups[tostring(gid)]. Group 1 VIEWS the
-- legacy group-level keys (tbb.groupGrowDirection / tbb.groupSpacing) so
-- pre-multi-group configs keep their exact layout with zero migration; writes
-- for group 1 keep the legacy keys in sync for old-version imports.
-- gid -> string key memo: avoids a tostring allocation in the per-tick reflow.
local _gidKeys = setmetatable({}, { __index = function(t, gid)
    local s = tostring(gid); rawset(t, gid, s); return s
end })

local function TBBGroupStore(tbb, gid, create)
    if not tbb.groups then
        if not create then return nil end
        tbb.groups = {}
    end
    local k = _gidKeys[gid]
    local g = tbb.groups[k]
    if not g and create then g = {}; tbb.groups[k] = g end
    return g
end

-- Internal reads take the tbb table directly so the per-tick reflow doesn't
-- re-resolve the active spec profile per group.
local function GroupGrowOf(tbb, gid)
    local g = TBBGroupStore(tbb, gid, false)
    if g and g.grow then return g.grow end
    if gid == 1 and tbb.groupGrowDirection then return tbb.groupGrowDirection end
    return "DOWN"
end

local function GroupSpacingOf(tbb, gid)
    local g = TBBGroupStore(tbb, gid, false)
    if g and g.spacing ~= nil then return g.spacing end
    if gid == 1 and tbb.groupSpacing ~= nil then return tbb.groupSpacing end
    return 2
end

function ns.TBBGroupGrow(gid)
    return GroupGrowOf(ns.GetTrackedBuffBars(), gid)
end

function ns.TBBSetGroupGrow(gid, v)
    local t = ns.GetTrackedBuffBars()
    TBBGroupStore(t, gid, true).grow = v
    if gid == 1 then t.groupGrowDirection = v end
end

function ns.TBBGroupSpacing(gid)
    return GroupSpacingOf(ns.GetTrackedBuffBars(), gid)
end

function ns.TBBSetGroupSpacing(gid, v)
    local t = ns.GetTrackedBuffBars()
    TBBGroupStore(t, gid, true).spacing = v
    if gid == 1 then t.groupSpacing = v end
end

-- Clear a group's stored settings. Used when a group id is (re)claimed for a
-- brand-new group, so settings left behind by a dissolved group of the same
-- id don't leak into it.
function ns.TBBResetGroupSettings(gid)
    local t = ns.GetTrackedBuffBars()
    if t.groups then t.groups[_gidKeys[gid]] = nil end
end

-- Optional user-given group name (Group Settings input). Empty/absent = nil;
-- callers fall back to the default "Group N" label.
function ns.TBBGroupName(gid)
    local t = ns.GetTrackedBuffBars()
    local g = TBBGroupStore(t, gid, false)
    local n = g and g.name
    if type(n) == "string" and n ~= "" then return n end
    return nil
end

function ns.TBBSetGroupName(gid, name)
    local t = ns.GetTrackedBuffBars()
    if type(name) ~= "string" or name == "" then
        local g = TBBGroupStore(t, gid, false)
        if g then g.name = nil end
    else
        TBBGroupStore(t, gid, true).name = name
    end
end

-- "Auto-Add New to This Group": the flagged group receives a bar for every
-- spell newly appearing in Blizzard's Tracked Bars section. At most ONE group
-- holds the flag -- enabling it clears the others.
function ns.TBBGroupAutoAdd(gid)
    local t = ns.GetTrackedBuffBars()
    local g = TBBGroupStore(t, gid, false)
    return g ~= nil and g.autoAdd == true
end

function ns.TBBSetGroupAutoAdd(gid, v)
    local t = ns.GetTrackedBuffBars()
    if v then
        if t.groups then
            for _, g in pairs(t.groups) do g.autoAdd = nil end
        end
        TBBGroupStore(t, gid, true).autoAdd = true
    else
        local g = TBBGroupStore(t, gid, false)
        if g then g.autoAdd = nil end
    end
end

-- The group currently flagged for auto-add (or nil). Smallest id wins if a
-- stale table somehow carries more than one flag.
function ns.TBBAutoAddGroupID()
    local t = ns.GetTrackedBuffBars()
    if not t.groups then return nil end
    local best
    for k, g in pairs(t.groups) do
        if g.autoAdd == true then
            local gid = tonumber(k)
            if gid and (not best or gid < best) then best = gid end
        end
    end
    return best
end

-- Index of a group's anchor = its first enabled member (or nil if none).
-- gid nil = group 1 (legacy callers).
function ns.TBBGroupAnchorIndex(gid)
    gid = gid or 1
    local t = ns.GetTrackedBuffBars()
    for i, c in ipairs(t.bars or {}) do
        if c.enabled ~= false and ns.TBBBarGroupID(c) == gid then return i end
    end
    return nil
end

-- Member count: with gid, counts that group's bars (regardless of enabled);
-- without, counts bars in ANY group (drives options disabled gates).
function ns.TBBGroupedCount(gid)
    local t = ns.GetTrackedBuffBars()
    local n = 0
    for _, c in ipairs(t.bars or {}) do
        local g = ns.TBBBarGroupID(c)
        if (gid and g == gid) or (not gid and g ~= 0) then n = n + 1 end
    end
    return n
end

-- Groups are orientation-uniform: shared width/height only make sense when
-- every member reads the dimensions the same way. The group's FIRST member
-- defines the orientation; any member that disagrees (a preset applied to a
-- single bar, a cross-spec copy, legacy/imported data) is coerced, swapping
-- its stored dims so its on-screen proportions carry over. Runs on every
-- rebuild, so the invariant holds no matter which path mutated the configs.
-- (The options Vertical Orientation toggle flips the whole group explicitly,
-- so deliberate flips never fight this.)
function ns.EnforceTBBGroupOrientation(tbb)
    tbb = tbb or ns.GetTrackedBuffBars()
    local firstOrient = {}
    for _, cfg in ipairs(tbb.bars or {}) do
        local gid = ns.TBBBarGroupID(cfg)
        if gid ~= 0 then
            local want = firstOrient[gid]
            local mine = cfg.verticalOrientation and true or false
            if want == nil then
                firstOrient[gid] = mine
            elseif mine ~= want then
                cfg.width, cfg.height = (cfg.height or 24), (cfg.width or 270)
                cfg.verticalOrientation = want
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Style copy
--  The "style" of a bar is every visual key -- everything except the tracked
--  spell identity, enable state, group membership and the stack-threshold
--  numbers (those are spell-specific, matching AddTrackedBuffBar's reset set).
-------------------------------------------------------------------------------
local TBB_STYLE_KEYS = {
    "height", "width", "verticalOrientation", "reverseFill", "texture",
    "fillColorMode", "fillR", "fillG", "fillB", "fillA",
    "bgR", "bgG", "bgB", "bgA",
    "gradientEnabled", "gradientR", "gradientG", "gradientB", "gradientA", "gradientDir",
    "opacity", "hideWhenInactive",
    "showTimer", "timerPosition", "timerSize", "timerX", "timerY",
    "showName", "namePosition", "nameSize", "nameX", "nameY",
    "showSpark",
    "iconDisplay", "iconSize", "iconX", "iconY", "iconBorderSize",
    "stacksPosition", "stacksSize", "stacksX", "stacksY",
    "borderSize", "borderTexture", "borderR", "borderG", "borderB",
    "borderTextureOffset", "borderTextureOffsetY",
    "borderTextureShiftX", "borderTextureShiftY", "borderBehind",
    "pandemicGlow", "pandemicGlowStyle", "pandemicGlowColor",
    "pandemicGlowLines", "pandemicGlowThickness", "pandemicGlowSpeed",
}
ns.TBB_STYLE_KEYS = TBB_STYLE_KEYS

-- Copy src's visual style onto dst, key-exact (including nil) so both bars
-- resolve defaults identically. Table values (glow color) are copied so the
-- two bars never share a mutable table.
function ns.CopyTBBStyle(src, dst)
    if not src or not dst or src == dst then return end
    for _, k in ipairs(TBB_STYLE_KEYS) do
        local v = src[k]
        if type(v) == "table" then
            local copy = {}
            for tk, tv in pairs(v) do copy[tk] = tv end
            v = copy
        end
        dst[k] = v
    end
end

-- The bar whose style represents a group: its anchor, or (all members
-- disabled) its first member.
function ns.TBBGroupStyleSource(gid)
    if not gid or gid == 0 then return nil end
    local t = ns.GetTrackedBuffBars()
    local ai = ns.TBBGroupAnchorIndex(gid)
    if ai then return t.bars[ai] end
    for _, c in ipairs(t.bars or {}) do
        if ns.TBBBarGroupID(c) == gid then return c end
    end
    return nil
end

-------------------------------------------------------------------------------
--  Style presets (PROFILE-scoped: persist across specs and travel with the
--  profile export). Each entry = { name, style = {<TBB_STYLE_KEYS values>} }.
--  A bar remembers the preset last applied to it (cfg.stylePresetName) so
--  new bars can resolve a preset by association.
-------------------------------------------------------------------------------
function ns.GetTBBStylePresets()
    if not (ECME and ECME.db) then ECME = ns.ECME end
    local p = ECME and ECME.db and ECME.db.profile
    if not p then return nil end
    if not p.tbbStylePresets then p.tbbStylePresets = {} end
    -- Same icon-footprint fold as GetTrackedBuffBars: presets saved before
    -- width/height became the icon-inclusive total snapshot the FILL size.
    if not p._tbbPresetIconTotal then
        for _, pr in ipairs(p.tbbStylePresets) do
            local s = pr.style
            if s and (s.iconDisplay or "none") ~= "none" then
                if s.verticalOrientation then
                    s.height = (s.height or 24) + (s.width or 270)
                else
                    s.width = (s.width or 270) + (s.height or 24)
                end
            end
        end
        p._tbbPresetIconTotal = true
    end
    return p.tbbStylePresets
end

function ns.FindTBBStylePreset(name)
    if not name or name == "" then return nil end
    local presets = ns.GetTBBStylePresets()
    if not presets then return nil end
    for _, pr in ipairs(presets) do
        if pr.name == name then return pr end
    end
    return nil
end

-- Save (or overwrite) a preset from a bar's current style, and associate the
-- source bar with it.
function ns.SaveTBBStylePreset(name, srcCfg)
    if not name or name == "" or not srcCfg then return nil end
    local presets = ns.GetTBBStylePresets()
    if not presets then return nil end
    local style = {}
    ns.CopyTBBStyle(srcCfg, style)
    local pr = ns.FindTBBStylePreset(name)
    if pr then
        pr.style = style
    else
        pr = { name = name, style = style }
        presets[#presets + 1] = pr
    end
    srcCfg.stylePresetName = name
    return pr
end

function ns.ApplyTBBStylePresetToCfg(preset, cfg)
    if not preset or not preset.style or not cfg then return end
    ns.CopyTBBStyle(preset.style, cfg)
    cfg.stylePresetName = preset.name
end

-- Delete a saved preset. Bar associations (cfg.stylePresetName) are left in
-- place: FindTBBStylePreset returns nil for a missing name, so they are inert.
function ns.DeleteTBBStylePreset(name)
    if not name or name == "" then return false end
    local presets = ns.GetTBBStylePresets()
    if not presets then return false end
    for i, pr in ipairs(presets) do
        if pr.name == name then
            table.remove(presets, i)
            local p = ECME and ECME.db and ECME.db.profile
            if p and p.tbbSelectedStylePreset == name then
                p.tbbSelectedStylePreset = nil
            end
            return true
        end
    end
    return false
end

-- Rename a saved preset, carrying the bar associations (across every spec of
-- the active profile) and the UI selection pointer along with it.
function ns.RenameTBBStylePreset(oldName, newName)
    if not oldName or oldName == "" or not newName or newName == "" then return false end
    if oldName == newName or ns.FindTBBStylePreset(newName) then return false end
    local pr = ns.FindTBBStylePreset(oldName)
    if not pr then return false end
    pr.name = newName
    local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
    if sp then
        for _, prof in pairs(sp) do
            local bars = type(prof) == "table" and prof.trackedBuffBars
                and prof.trackedBuffBars.bars
            if bars then
                for _, c in ipairs(bars) do
                    if c.stylePresetName == oldName then c.stylePresetName = newName end
                end
            end
        end
    end
    local p = ECME and ECME.db and ECME.db.profile
    if p and p.tbbSelectedStylePreset == oldName then
        p.tbbSelectedStylePreset = newName
    end
    return true
end

-- New-bar resolution: the preset associated with a bar already in the target
-- group (nil if none).
function ns.ResolveTBBGroupPreset(tbb, gid)
    if not gid or gid == 0 then return nil end
    for _, c in ipairs(tbb.bars or {}) do
        if ns.TBBBarGroupID(c) == gid then
            local pr = ns.FindTBBStylePreset(c.stylePresetName)
            if pr then return pr end
        end
    end
    return nil
end

-- New-bar fallback: a preset associated with any bar of this spec, else any
-- saved preset (nil when none are saved).
function ns.ResolveTBBFallbackPreset(tbb)
    local presets = ns.GetTBBStylePresets()
    if not presets or #presets == 0 then return nil end
    for _, c in ipairs(tbb.bars or {}) do
        local pr = ns.FindTBBStylePreset(c.stylePresetName)
        if pr then return pr end
    end
    return presets[1]
end


-- Runtime reflow for grouped Tracking Bars.
-- BuildTrackedBuffBars creates the static group chain, but the tick decides
-- which bars are currently visible. Reflow only the visible grouped members so
-- inactive hidden buffs do not leave holes in the chain:
--   configured order: Buff 1, Buff 2, Buff 3
--   active:           Buff 2, Buff 3        -> Buff 2 sits at group anchor
--   active:           Buff 1, Buff 2, Buff 3 -> Buff 1 sits at group anchor,
--                                              Buff 2/3 move after it
local _tbbReflowStates = {}   -- gid -> pooled per-group reflow state
local function GetReflowState(gid)
    local st = _tbbReflowStates[gid]
    if not st then
        st = { visible = {}, lastIdx = {}, lastCount = 0, lastGrow = nil, lastSpacing = nil }
        _tbbReflowStates[gid] = st
    end
    return st
end
local function ResetReflowStates()
    for _, st in pairs(_tbbReflowStates) do st.lastCount = -1 end
end
local _tbbReflowDone = {}     -- reused per-tick "group handled" set

local function ReflowGroup(tbb, gid, bars)
    local st = GetReflowState(gid)

    local anchorIdx
    for i, c in ipairs(bars) do
        if c.enabled ~= false and ns.TBBBarGroupID(c) == gid then anchorIdx = i; break end
    end
    if not anchorIdx then return end

    local growDir = (GroupGrowOf(tbb, gid) or "DOWN"):upper()
    local spacing = GroupSpacingOf(tbb, gid) or 2

    -- Collect this group's enabled + currently visible bars in saved hierarchy
    -- order. A bar with hideWhenInactive=false is visible and therefore keeps its
    -- slot, which matches the user's choice to show inactive bars. Entry tables
    -- are pooled and reused across ticks to avoid per-frame allocation in this
    -- hot (every-16ms) path.
    local visible = st.visible
    local count = 0
    for i, cfg in ipairs(bars) do
        local f = tbbFrames[i]
        if cfg and cfg.enabled ~= false and ns.TBBBarGroupID(cfg) == gid
           and f and f._tbbReady and f:IsShown() then
            count = count + 1
            local e = visible[count]
            if not e then e = {}; visible[count] = e end
            e.idx = i; e.frame = f
        end
    end

    if count == 0 then
        st.lastCount = 0
        return
    end

    -- Re-anchor only when the visible member sequence or the grow/spacing tuple
    -- changes. Compared element-wise so no string is allocated each tick.
    local lastIdx = st.lastIdx
    local changed = count ~= st.lastCount
        or growDir ~= st.lastGrow or spacing ~= st.lastSpacing
    if not changed then
        for n = 1, count do
            if visible[n].idx ~= lastIdx[n] then changed = true; break end
        end
    end
    if not changed then return end
    st.lastCount   = count
    st.lastGrow    = growDir
    st.lastSpacing = spacing
    for n = 1, count do lastIdx[n] = visible[n].idx end

    local first = visible[1].frame
    local anchorFrame = tbbFrames[anchorIdx]

    if anchorFrame and anchorFrame ~= first then
        -- The configured anchor buff is inactive/hidden: pin the first VISIBLE
        -- member onto the anchor frame's slot so it takes the group origin. The
        -- anchor frame keeps whatever position BuildTrackedBuffBars / the unlock
        -- system gave it (including element anchoring), so this preserves it.
        first:ClearAllPoints()
        first:SetPoint("TOPLEFT", anchorFrame, "TOPLEFT", 0, 0)
    end
    -- else: the first visible bar IS the anchor -- leave its point untouched.
    -- BuildTrackedBuffBars and the unlock system already position it and honor
    -- IsUnlockAnchored, so re-deriving from tbbPositions here would clobber an
    -- element-anchored group (yanking it to a stale coord or screen center).

    local prev = first
    for n = 2, count do
        local f = visible[n].frame
        f:ClearAllPoints()
        if growDir == "DOWN" then
            f:SetPoint("TOP", prev, "BOTTOM", 0, -spacing)
        elseif growDir == "UP" then
            f:SetPoint("BOTTOM", prev, "TOP", 0, spacing)
        elseif growDir == "RIGHT" then
            f:SetPoint("LEFT", prev, "RIGHT", spacing, 0)
        elseif growDir == "LEFT" then
            f:SetPoint("RIGHT", prev, "LEFT", -spacing, 0)
        else
            f:SetPoint("TOP", prev, "BOTTOM", 0, -spacing)
        end
        prev = f
    end
end

local function ReflowVisibleGroupedTBBars(tbb, bars)
    if not (tbb and bars and tbbFrames) then return end
    -- Don't fight edit-preview (placeholder) or unlock-mode dragging: in those
    -- modes BuildTrackedBuffBars and the unlock system own bar positions.
    if ns._tbbPlaceholderMode or EllesmereUI._unlockActive then return end
    -- Reflow each group present, once. The done-set is reused across ticks so
    -- this pass allocates nothing.
    wipe(_tbbReflowDone)
    for _, cfg in ipairs(bars) do
        local gid = ns.TBBBarGroupID(cfg)
        if gid ~= 0 and not _tbbReflowDone[gid] then
            _tbbReflowDone[gid] = true
            ReflowGroup(tbb, gid, bars)
        end
    end
end

-- Fan a width/height change from a grouped bar out to every other bar in the
-- SAME group: write each sibling's LOGICAL cfg.width/cfg.height (NOT the
-- icon-inclusive total) and resize its frame using that sibling's OWN icon
-- math. Used by the options sliders, unlock drag-resize, and size-MATCH (so
-- width-matching the group anchor matches the whole group). Re-entrancy
-- guarded so a sibling write can't recurse.
local _tbbGroupSizing = false
function ns.PropagateTBBGroupSize(srcIdx, dim, value)
    if _tbbGroupSizing then return end
    local t = ns.GetTrackedBuffBars()
    local bars = t.bars
    if not bars then return end
    local src = bars[srcIdx]
    local srcGid = src and ns.TBBBarGroupID(src) or 0
    if srcGid == 0 then return end
    _tbbGroupSizing = true
    for i, c in ipairs(bars) do
        if i ~= srcIdx and ns.TBBBarGroupID(c) == srcGid then
            c[dim] = value
            local f = tbbFrames[i]
            if f then
                -- width/height are the total footprint (icon included), so
                -- the frame takes the value directly.
                if dim == "width" then f:SetWidth(value) else f:SetHeight(value) end
            end
        end
    end
    _tbbGroupSizing = false
end

function ns.HasBuffBars()
    if not ECME or not ECME.db then return false end
    local tbb = ns.GetTrackedBuffBars()
    return tbb and tbb.bars and #tbb.bars > 0
end

function ns.IsTBBRebuildPending() return _tbbRebuildPending end

-- No-ops for removed functionality (options/main file may reference these)
ns.RefreshTBBResolvedIDs = function() end
ns.RefreshBuffBarGating  = function() end

-------------------------------------------------------------------------------
--  Frame Creation
-------------------------------------------------------------------------------
local function CreateTrackedBuffBarFrame(parent, idx)
    local wrapFrame = CreateFrame("Frame", "ECME_TBBWrap" .. idx, parent)
    wrapFrame:SetFrameStrata("MEDIUM")
    wrapFrame:SetFrameLevel(10)

    local bar = CreateFrame("StatusBar", "ECME_TBB" .. idx, wrapFrame)
    if bar.EnableMouseClicks then bar:EnableMouseClicks(false) end
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0.65)
    bar:SetClipsChildren(true)
    wrapFrame._bar = bar

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.4)
    wrapFrame._bg = bg

    -- Spark on a dedicated overlay frame one level above the (gradient) fill so
    -- it always draws OVER the fill, still clipped to the bar so it never spills
    -- past the ends. SnapToPixelGrid off so it tracks the smoothly-interpolated
    -- fill edge at sub-pixel precision instead of jumping a pixel as the edge
    -- crosses a grid line.
    local sparkOverlay = CreateFrame("Frame", nil, bar)
    sparkOverlay:SetAllPoints(bar)
    sparkOverlay:SetClipsChildren(true)
    sparkOverlay:SetFrameLevel(bar:GetFrameLevel() + 2)
    wrapFrame._sparkOverlay = sparkOverlay
    local spark = sparkOverlay:CreateTexture(nil, "OVERLAY", nil, 7)
    spark:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\cast_spark.tga")
    spark:SetBlendMode("ADD")
    spark:SetSnapToPixelGrid(false)
    spark:SetTexelSnappingBias(0)
    spark:Hide()
    wrapFrame._spark = spark

    -- Gradient clip frame (created lazily in ApplySettings)
    wrapFrame._gradClip = nil
    wrapFrame._gradTex  = nil

    -- Text overlay: parented to wrapFrame (not bar) so bar's SetClipsChildren
    -- doesn't chop text when font size exceeds bar height. Level sits ABOVE the
    -- border (set to bar +5 in ApplySettings) and the pandemic glow (wrapFrame
    -- +6) so the timer/name/stacks text renders on top of the border instead of
    -- beneath it. Keyed off bar (like the border) so the two track together.
    local textOverlay = CreateFrame("Frame", nil, wrapFrame)
    textOverlay:SetAllPoints(bar)
    textOverlay:SetFrameLevel(bar:GetFrameLevel() + 6)
    wrapFrame._textOverlay = textOverlay

    -- Timer text
    local timerText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFont(timerText, 11)
    timerText:SetTextColor(1, 1, 1, 0.9)
    timerText:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    timerText:SetJustifyH("RIGHT")
    wrapFrame._timerText = timerText

    -- Name text
    local nameText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFont(nameText, 11)
    nameText:SetTextColor(1, 1, 1, 0.9)
    nameText:SetPoint("LEFT", bar, "LEFT", 4, 0)
    nameText:SetJustifyH("LEFT")
    wrapFrame._nameText = nameText

    -- Stacks text
    local stacksText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFont(stacksText, 11)
    stacksText:SetTextColor(1, 1, 1, 0.9)
    stacksText:SetPoint("CENTER", bar, "CENTER", 0, 0)
    stacksText:Hide()
    wrapFrame._stacksText = stacksText

    -- Icon
    local icon = CreateFrame("Frame", nil, wrapFrame)
    icon:SetSize(24, 24)
    icon:Hide()
    local iconTex = icon:CreateTexture(nil, "ARTWORK")
    iconTex:SetAllPoints()
    iconTex:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    icon._tex = iconTex
    wrapFrame._icon = icon

    -- Border container
    local bdrContainer = CreateFrame("Frame", nil, wrapFrame)
    bdrContainer:SetAllPoints(wrapFrame)
    bdrContainer:SetFrameLevel(wrapFrame:GetFrameLevel() + 5)
    bdrContainer:Hide()
    wrapFrame._barBorder = bdrContainer

    -- Pandemic glow overlay
    local panGlow = CreateFrame("Frame", nil, wrapFrame)
    panGlow:SetAllPoints(wrapFrame)
    panGlow:SetFrameLevel(wrapFrame:GetFrameLevel() + 6)
    panGlow:SetAlpha(0)
    panGlow:EnableMouse(false)
    wrapFrame._pandemicGlowOverlay = panGlow

    wrapFrame:Hide()
    return wrapFrame
end

-------------------------------------------------------------------------------
--  Threshold Overlay (stacked StatusBar, secret-safe)
-------------------------------------------------------------------------------
local function EnsureTBBThresholdOverlay(bar)
    if bar._threshOverlay then return bar._threshOverlay end
    local sb = bar._bar
    if not sb then return nil end
    local overlay = CreateFrame("StatusBar", nil, sb)
    overlay:SetAllPoints(sb:GetStatusBarTexture())
    overlay:SetFrameLevel(sb:GetFrameLevel() + 2)
    overlay:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    overlay:SetMinMaxValues(0, 1)
    overlay:SetValue(0)
    overlay:Hide()
    bar._threshOverlay = overlay
    return overlay
end

local function SetupTBBThresholdOverlay(bar, cfg)
    if not cfg.stackThresholdEnabled then
        if bar._threshOverlay then bar._threshOverlay:Hide() end
        return
    end
    local overlay = EnsureTBBThresholdOverlay(bar)
    if not overlay then return end
    local texPath = EllesmereUI.ResolveTexturePath(TBB_TEXTURES, cfg.texture or "none", "Interface\\Buttons\\WHITE8x8")
    overlay:SetStatusBarTexture(texPath)
    overlay:SetOrientation(cfg.verticalOrientation and "VERTICAL" or "HORIZONTAL")
    overlay:SetReverseFill(cfg.reverseFill and true or false)
    overlay:GetStatusBarTexture():SetVertexColor(
        cfg.stackThresholdR or 0.8, cfg.stackThresholdG or 0.1,
        cfg.stackThresholdB or 0.1, cfg.stackThresholdA or 1)
    overlay:ClearAllPoints()
    overlay:SetAllPoints(bar._bar:GetStatusBarTexture())
    local threshold = cfg.stackThreshold or 5
    overlay:SetMinMaxValues(threshold - 1, threshold)
    overlay:SetValue(0)
    overlay:Show()
end

local function FeedTBBThresholdOverlay(bar)
    local overlay = bar._threshOverlay
    if not overlay or not overlay:IsShown() then return end
    overlay:SetValue(bar._stackCount or 0)
end

-------------------------------------------------------------------------------
--  Tick Marks
-------------------------------------------------------------------------------
local function ParseTickValues(str)
    if not str or str == "" then return nil end
    local vals = {}
    for s in str:gmatch("[^,]+") do
        local n = tonumber(s:match("^%s*(.-)%s*$"))
        if n and n > 0 then vals[#vals + 1] = n end
    end
    return #vals > 0 and vals or nil
end

local function ApplyTBBTickMarks(sb, cfg, tickCache, isVert, tickParent)
    local maxStacks = cfg.stackThresholdMax or 10
    local vals = ParseTickValues(cfg.stackThresholdTicks)
    if tickCache then
        for i = 1, #tickCache do tickCache[i]:Hide() end
    end
    if not cfg.stackThresholdEnabled or not cfg.stackThresholdMaxEnabled
       or not vals or maxStacks < 1 or not tickCache then return end

    local PP = EllesmereUI and EllesmereUI.PP
    local parent = tickParent or sb
    while #tickCache < #vals do
        local t = parent:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetColorTexture(1, 1, 1, 1)
        t:SetSnapToPixelGrid(false)
        t:SetTexelSnappingBias(0)
        tickCache[#tickCache + 1] = t
    end

    local onePx = PP and PP.Scale(1) or 1
    local barW, barH = sb:GetWidth(), sb:GetHeight()
    -- Ticks measure stack fractions from the fill's ORIGIN, so they mirror
    -- when Reverse Fill moves the origin to the other end.
    local reverse = cfg.reverseFill and true or false
    for i, v in ipairs(vals) do
        if v <= maxStacks then
            local t = tickCache[i]
            local frac = v / maxStacks
            t:ClearAllPoints()
            if isVert then
                local off = PP and PP.Scale(barH * frac) or (barH * frac)
                t:SetSize(barW, onePx)
                if reverse then
                    t:SetPoint("TOPLEFT", sb, "TOPLEFT", 0, -off)
                else
                    t:SetPoint("BOTTOMLEFT", sb, "BOTTOMLEFT", 0, off)
                end
            else
                local off = PP and PP.Scale(barW * frac) or (barW * frac)
                t:SetSize(onePx, barH)
                if reverse then
                    t:SetPoint("TOPRIGHT", sb, "TOPRIGHT", -off, 0)
                else
                    t:SetPoint("TOPLEFT", sb, "TOPLEFT", off, 0)
                end
            end
            t:Show()
        end
    end
end
ns.ApplyTBBTickMarks = ApplyTBBTickMarks

-------------------------------------------------------------------------------
--  Apply Visual Settings
-------------------------------------------------------------------------------
local function ApplyTrackedBuffBarSettings(bar, cfg)
    if not bar or not cfg then return end
    local sb = bar._bar
    if not sb then return end

    -- width/height are always visual dimensions (what you see on screen) and
    -- describe the bar's TOTAL footprint, icon included: the wrap is exactly
    -- width x height, and a shown icon carves its square out of the fill.
    -- Horizontal: width = long side, height = short side.
    -- Vertical: width = short side, height = long side.
    local PPt = EllesmereUI and EllesmereUI.PP
    local snap = PPt and PPt.Snap or function(v) return v end
    local w = snap(cfg.width or 270)
    local h = snap(cfg.height or 24)
    local isVert = cfg.verticalOrientation
    bar._lastVertical = isVert
    local iconMode = cfg.iconDisplay or "none"
    local hasIcon = iconMode ~= "none"
    local iSize = isVert and w or h
    if hasIcon then
        -- Never let the icon square consume the whole footprint
        local long = isVert and h or w
        if iSize > long - 1 then iSize = max(1, long - 1) end
    end

    bar:SetSize(w, h)

    -- Position StatusBar inside wrapFrame
    sb:ClearAllPoints()
    if hasIcon then
        if isVert then
            if iconMode == "left" then
                -- Left = Top for vertical
                sb:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, -iSize)
                sb:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
            else
                -- Right = Bottom for vertical
                sb:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
                sb:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, iSize)
            end
        else
            if iconMode == "left" then
                sb:SetPoint("TOPLEFT", bar, "TOPLEFT", iSize, 0)
                sb:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
            else
                sb:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
                sb:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -iSize, 0)
            end
        end
    else
        sb:SetAllPoints(bar)
    end

    -- Orientation and fill direction
    sb:SetOrientation(isVert and "VERTICAL" or "HORIZONTAL")
    sb:SetReverseFill(cfg.reverseFill and true or false)

    -- Texture
    local texPath = EllesmereUI.ResolveTexturePath(TBB_TEXTURES, cfg.texture or "none", "Interface\\Buttons\\WHITE8x8")
    if bar._lastTexPath ~= texPath then
        sb:SetStatusBarTexture(texPath)
        bar._lastTexPath = texPath
    end

    -- Fill color
    local fR = cfg.fillR or _classR
    local fG = cfg.fillG or _classG
    local fB = cfg.fillB or _classB
    local fA = cfg.fillA or 1
    sb:GetStatusBarTexture():SetVertexColor(fR, fG, fB, fA)
    bar._baseFillR, bar._baseFillG, bar._baseFillB, bar._baseFillA = fR, fG, fB, fA

    -- Background
    if bar._bg then
        bar._bg:SetColorTexture(cfg.bgR or 0, cfg.bgG or 0, cfg.bgB or 0, cfg.bgA or 0.4)
    end

    -- Gradient
    local fillTex = sb:GetStatusBarTexture()
    if cfg.gradientEnabled then
        local dir = cfg.gradientDir or "HORIZONTAL"
        fillTex:SetVertexColor(1, 1, 1, 0)
        if not bar._gradClip then
            local clip = CreateFrame("Frame", nil, sb)
            clip:SetClipsChildren(true)
            clip:SetFrameLevel(sb:GetFrameLevel() + 1)
            local tex = clip:CreateTexture(nil, "ARTWORK", nil, 1)
            tex:SetPoint("TOPLEFT", sb, "TOPLEFT", 0, 0)
            tex:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", 0, 0)
            bar._gradClip = clip
            bar._gradTex  = tex
        end
        bar._gradClip:ClearAllPoints()
        bar._gradClip:SetAllPoints(fillTex)
        bar._gradTex:SetTexture(texPath)
        bar._gradTex:SetVertexColor(1, 1, 1, 1)
        bar._gradTex:SetGradient(dir,
            CreateColor(fR, fG, fB, fA),
            CreateColor(cfg.gradientR or 0.20, cfg.gradientG or 0.20, cfg.gradientB or 0.80, cfg.gradientA or 1))
        bar._gradClip:Show()
        bar._gradientActive = true
    else
        if bar._gradClip then bar._gradClip:Hide() end
        bar._gradientActive = nil
        fillTex:SetVertexColor(fR, fG, fB, fA)
    end

    -- Opacity
    bar._opacityTarget = cfg.opacity or 1.0
    if not bar._tbbReady then bar:SetAlpha(bar._opacityTarget) end

    -- Timer text. Vertical bars honor the same position choices as horizontal
    -- ones: left/right sit OUTSIDE the (thin) bar, top/bottom sit above/below
    -- it, center stays inside.
    local timerPos = cfg.timerPosition or (cfg.showTimer and "right" or "none")
    if timerPos ~= "none" then
        bar._timerText:Show()
        SetFont(bar._timerText, cfg.timerSize or 11)
        bar._timerText:ClearAllPoints()
        local tX, tY = cfg.timerX or 0, cfg.timerY or 0
        if isVert and timerPos == "center" then
            bar._timerText:SetPoint("CENTER", sb, "CENTER", tX, tY)
            bar._timerText:SetJustifyH("CENTER")
        elseif isVert and timerPos == "top" then
            bar._timerText:SetPoint("BOTTOM", sb, "TOP", tX, 5 + tY)
            bar._timerText:SetJustifyH("CENTER")
        elseif isVert and timerPos == "bottom" then
            bar._timerText:SetPoint("TOP", sb, "BOTTOM", tX, -5 + tY)
            bar._timerText:SetJustifyH("CENTER")
        elseif isVert and timerPos == "left" then
            bar._timerText:SetPoint("RIGHT", sb, "LEFT", -5 + tX, tY)
            bar._timerText:SetJustifyH("RIGHT")
        elseif isVert then
            bar._timerText:SetPoint("LEFT", sb, "RIGHT", 5 + tX, tY)
            bar._timerText:SetJustifyH("LEFT")
        elseif timerPos == "center" then
            bar._timerText:SetPoint("CENTER", sb, "CENTER", tX, tY)
            bar._timerText:SetJustifyH("CENTER")
        elseif timerPos == "top" then
            bar._timerText:SetPoint("BOTTOM", sb, "TOP", tX, 5 + tY)
            bar._timerText:SetJustifyH("CENTER")
        elseif timerPos == "bottom" then
            bar._timerText:SetPoint("TOP", sb, "BOTTOM", tX, -5 + tY)
            bar._timerText:SetJustifyH("CENTER")
        elseif timerPos == "left" then
            bar._timerText:SetPoint("LEFT", sb, "LEFT", 5 + tX, tY)
            bar._timerText:SetJustifyH("LEFT")
        else
            bar._timerText:SetPoint("RIGHT", sb, "RIGHT", -5 + tX, tY)
            bar._timerText:SetJustifyH("RIGHT")
        end
    else
        bar._timerText:Hide()
    end

    -- Spark: anchored to the MOVING edge of the fill. With Reverse Fill the
    -- fill anchors at the far end and the near edge moves, so the spark side
    -- flips with it.
    bar._lastReverse = cfg.reverseFill and true or false
    if cfg.showSpark then
        local sparkAnchor = (bar._gradientActive and bar._gradClip) or fillTex
        if isVert then
            bar._spark:SetSize(w, 8)
            bar._spark:SetTexCoord(0, 1, 1, 1, 0, 0, 1, 0)
        else
            bar._spark:SetSize(8, h)
            bar._spark:SetTexCoord(0, 0, 0, 1, 1, 0, 1, 1)
        end
        bar._spark:ClearAllPoints()
        if isVert then
            bar._spark:SetPoint("CENTER", sparkAnchor, cfg.reverseFill and "BOTTOM" or "TOP", 0, 0)
        else
            -- 1px inward so the spark sits over the fill edge, not past it.
            bar._spark:SetPoint("CENTER", sparkAnchor,
                cfg.reverseFill and "LEFT" or "RIGHT",
                cfg.reverseFill and 1 or -1, 0)
        end
        bar._spark:Show()
    else
        bar._spark:Hide()
    end

    -- Name text
    local namePos = cfg.namePosition or ((cfg.showName ~= false) and "left" or "none")
    if namePos ~= "none" and not isVert then
        bar._nameText:Show()
        SetFont(bar._nameText, cfg.nameSize or 11)
        bar._nameText:ClearAllPoints()
        local nX, nY = cfg.nameX or 0, cfg.nameY or 0
        if namePos == "center" then
            bar._nameText:SetPoint("CENTER", sb, "CENTER", nX, nY)
            bar._nameText:SetJustifyH("CENTER")
        elseif namePos == "top" then
            bar._nameText:SetPoint("BOTTOM", sb, "TOP", nX, 5 + nY)
            bar._nameText:SetJustifyH("CENTER")
        elseif namePos == "bottom" then
            bar._nameText:SetPoint("TOP", sb, "BOTTOM", nX, -5 + nY)
            bar._nameText:SetJustifyH("CENTER")
        elseif namePos == "right" then
            bar._nameText:SetPoint("RIGHT", sb, "RIGHT", -5 + nX, nY)
            bar._nameText:SetJustifyH("RIGHT")
        else
            bar._nameText:SetPoint("LEFT", sb, "LEFT", 5 + nX, nY)
            bar._nameText:SetJustifyH("LEFT")
        end
        -- Text width + wrap mode (the icon's square is not text space). Wrap on:
        -- legacy behaviour, wraps to 2 lines within the text area. Off (default):
        -- a single line truncated with an ellipsis at 85% of the fill width.
        local fillW = hasIcon and (w - iSize) or w
        if cfg.nameWrap then
            bar._nameText:SetWordWrap(true)
            bar._nameText:SetMaxLines(2)
            bar._nameText:SetWidth(fillW - 12 - (cfg.showTimer and 50 or 0))
        else
            bar._nameText:SetWordWrap(false)
            bar._nameText:SetMaxLines(1)
            bar._nameText:SetWidth(fillW * 0.85)
        end
    else
        bar._nameText:Hide()
    end

    -- Icon
    if hasIcon and bar._icon then
        bar._icon:SetSize(iSize, iSize)
        bar._icon:ClearAllPoints()
        if isVert then
            if iconMode == "left" then
                bar._icon:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
            else
                bar._icon:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
            end
        else
            if iconMode == "left" then
                bar._icon:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
            else
                bar._icon:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
            end
        end
        bar._icon:Show()
    elseif bar._icon then
        bar._icon:Hide()
    end

    -- Stacks text positioning
    if bar._stacksText then
        local sPos = cfg.stacksPosition or "center"
        if sPos == "none" then
            bar._stacksText:Hide()
            bar._stacksHidden = true
        else
            bar._stacksHidden = nil
            SetFont(bar._stacksText, cfg.stacksSize or 11)
            bar._stacksText:ClearAllPoints()
            local sX, sY = cfg.stacksX or 0, cfg.stacksY or 0
            if sPos == "top" then
                bar._stacksText:SetPoint("BOTTOM", sb, "TOP", sX, 5 + sY)
            elseif sPos == "bottom" then
                bar._stacksText:SetPoint("TOP", sb, "BOTTOM", sX, -5 + sY)
            elseif sPos == "left" then
                bar._stacksText:SetPoint("LEFT", sb, "LEFT", 5 + sX, sY)
            elseif sPos == "right" then
                bar._stacksText:SetPoint("RIGHT", sb, "RIGHT", -5 + sX, sY)
            else
                bar._stacksText:SetPoint("CENTER", sb, "CENTER", sX, sY)
            end
        end
    end

    -- Border (PP or textured via ApplyBorderStyle)
    if bar._barBorder then
        bar._barBorder:SetAllPoints(bar)
        local bSz = cfg.borderSize or 0
        local textureKey = cfg.borderTexture or "solid"
        -- "Show Behind": border container is a child of the bar; +5 draws in
        -- front of the fill, level-1 draws behind it. Set before ApplyBorderStyle
        -- so the textured backdrop frame inherits the correct level.
        local baseLvl = bar:GetFrameLevel()
        bar._barBorder:SetFrameLevel(cfg.borderBehind and math.max(0, baseLvl - 1) or (baseLvl + 5))
        EllesmereUI.ApplyBorderStyle(bar._barBorder, bSz,
            cfg.borderR or 0, cfg.borderG or 0, cfg.borderB or 0, 1,
            textureKey, cfg.borderTextureOffset, cfg.borderTextureOffsetY,
            cfg.borderTextureShiftX, cfg.borderTextureShiftY,
            "resourcebars", bSz)
    end

    -- Threshold overlay + tick marks
    SetupTBBThresholdOverlay(bar, cfg)
    if not bar._threshTicks then bar._threshTicks = {} end
    if not bar._tickOverlay then
        local to = CreateFrame("Frame", nil, sb)
        to:SetAllPoints(sb)
        to:SetFrameLevel(sb:GetFrameLevel() + 3)
        bar._tickOverlay = to
    end
    ApplyTBBTickMarks(sb, cfg, bar._threshTicks, isVert, bar._tickOverlay)
    bar._ticksDirty = true
end

-- Exposed for the options popout preview: preview bars are constructed and
-- skinned by the exact same code as the live bars, so the preview can never
-- drift from the real rendering.
ns.CreateTBBBarFrame  = CreateTrackedBuffBarFrame
ns.ApplyTBBBarSettings = ApplyTrackedBuffBarSettings

-------------------------------------------------------------------------------
--  CDM Child Lookup
--  Iterates BuffBarCooldownViewer pool directly (pool is tiny, 3-5 frames).
--  Matches by cooldownID first (cached on cfg), then by spell ID variants
--  from cooldownInfo. No external caches, no stale data in combat.
-------------------------------------------------------------------------------
local function MatchesSID(info, sid)
    if info.overrideSpellID == sid then return true end
    if info.spellID == sid then return true end
    if info.linkedSpellIDs then
        for _, lid in ipairs(info.linkedSpellIDs) do
            if lid == sid then return true end
        end
    end
    return false
end

local function MatchFrameToConfig(frame, cfg)
    local cdID = frame.cooldownID
    if not cdID then return false end
    local gci = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
    if not gci then return false end
    local info = gci(cdID)
    if not info then return false end
    -- Self-healing base capture for hero-talent override spells. When a bar was
    -- saved for the OVERRIDE form (e.g. Death Charge) and is currently matched
    -- while talented, the frame reports the override in info.overrideSpellID and
    -- the BASE form (Death's Advance) in info.spellID. Record that base on the
    -- config so the bar keeps matching once the talent is removed: cooldownInfo
    -- only carries the override id WHILE talented, so without the stored base the
    -- bar would go dark when untalented (cast becomes the base spell). This
    -- backfills bars created before baseSpellID was captured at pick time.
    if cfg.spellID and cfg.spellID > 0 and not cfg.baseSpellID
       and info.overrideSpellID == cfg.spellID
       and info.spellID and info.spellID > 0 and info.spellID ~= cfg.spellID then
        cfg.baseSpellID = info.spellID
    end
    -- Fast path: match via cooldownInfo struct fields.
    if cfg.spellIDs then
        for _, sid in ipairs(cfg.spellIDs) do
            if MatchesSID(info, sid) then return true end
        end
    elseif cfg.spellID and cfg.spellID > 0 then
        if MatchesSID(info, cfg.spellID) then return true end
        -- Talent-override fallback: a bar saved for the override form also
        -- tracks its base form, so it keeps showing after the talent is removed.
        if cfg.baseSpellID and cfg.baseSpellID > 0 and MatchesSID(info, cfg.baseSpellID) then
            return true
        end
    else
        return false
    end
    -- Fallback: compare against the frame's canonical spell ID. Buff bar
    -- frames expose the actual aura variant via GetAuraSpellID which may
    -- not appear in the cooldownInfo struct (e.g. Eclipse Solar/Lunar).
    local GetCanonical = ns.GetCanonicalSpellIDForFrame
    if GetCanonical then
        local frameSID = GetCanonical(frame)
        if frameSID then
            if cfg.spellIDs then
                for _, sid in ipairs(cfg.spellIDs) do
                    if frameSID == sid then return true end
                end
            elseif cfg.spellID and cfg.spellID > 0 then
                if frameSID == cfg.spellID then return true end
                if cfg.baseSpellID and frameSID == cfg.baseSpellID then return true end
            end
        end
    end
    return false
end

local _findChildGeneration = 0
-- Frame cache lives in a separate table, never on the config (which is in
-- SavedVariables). Prevents frame references from leaking into serialization.
local _findChildCache = {}

-- Sticky cfg->frame bindings for the one-to-one assignment pass below. Keyed by
-- cfg table, value is the Blizzard frame last paired to it. Lives in its own
-- table (never on cfg, which is in SavedVariables) so frame refs don't leak into
-- serialization. Dropped on cache invalidation (spec swap, pool rebuild).
local _tbbStickyFrame = {}

function ns.InvalidateTBBFrameCache()
    _findChildGeneration = _findChildGeneration + 1
    wipe(_findChildCache)
    wipe(_tbbStickyFrame)
end

local function FindChild(cfg)
    -- Fast path: cached result from previous match (hit or miss).
    local cached = _findChildCache[cfg]
    if cached and cached.gen == _findChildGeneration then
        if cached.frame and cached.frame.cooldownID == cached.cdID then
            return cached.frame
        end
    end
    -- Full scan: iterate BuffBarCooldownViewer pool (TBB's own viewer).
    local entry = { gen = _findChildGeneration, frame = nil, cdID = nil }
    _findChildCache[cfg] = entry
    local viewer = _G["BuffBarCooldownViewer"]
    if viewer and viewer.itemFramePool then
        for frame in viewer.itemFramePool:EnumerateActive() do
            if MatchFrameToConfig(frame, cfg) then
                entry.frame = frame
                entry.cdID = frame.cooldownID
                return frame
            end
        end
    end
    return nil
end
ns.FindTBBChild = FindChild

-------------------------------------------------------------------------------
--  AssignFramesToConfigs
--
--  Pairs each tracked-bar config to AT MOST ONE BuffBarCooldownViewer frame,
--  consuming every frame once so two configs can never mirror the same frame.
--  This is the fix for multi-variant spells like Eclipse: Solar and Lunar
--  expose sibling frames that SHARE one cooldownInfo (linkedSpellIDs lists both
--  variants), so per-config FindChild() greedily binds BOTH configs to whichever
--  frame enumerates first -- "Lunar shows twice, Solar never" (and the mirror,
--  double Solar). Going frame-driven mirrors how the icon viewer works: it
--  decorates one display per Blizzard child instead of matching a stored spell
--  back to an ambiguous frame.
--
--  Three passes, each only over still-unconsumed frames:
--    1. Sticky  -- reuse last tick's binding. The frame OBJECT identity never
--                  goes secret, so a pairing locked in out of combat stays put
--                  when GetAuraSpellID turns secret mid-fight. Revalidated
--                  against a clean read when one is available (self-heals a
--                  recycled pool frame); trusted blindly only while secret.
--    2. Exact   -- per-frame canonical id == the config's spell (clean reads
--                  pair frameSolar->cfgSolar, frameLunar->cfgLunar). Locks the
--                  sticky binding for future ticks.
--    3. Fallback-- cooldownInfo/linkedSpellIDs struct match for configs still
--                  unpaired (combat with no prior sticky binding). Consumption
--                  still guarantees no two configs land on the same frame.
--
--  Returns a cfg->frame map (a reused module table; copy if you must retain it).
-------------------------------------------------------------------------------
local _tbbAssignment   = {}
local _tbbFrameScratch = {}
local _tbbConsumed     = {}
local _tbbFrameSID     = {}  -- frame -> canonical spell id, computed once per call

local function CfgWantsSID(cfg, sid)
    if not sid then return false end
    if cfg.spellIDs then
        for _, s in ipairs(cfg.spellIDs) do if s == sid then return true end end
        return false
    end
    if cfg.spellID and cfg.spellID > 0 then
        if sid == cfg.spellID then return true end
        if cfg.baseSpellID and cfg.baseSpellID > 0 and sid == cfg.baseSpellID then return true end
    end
    return false
end

local function FrameIsActive(frames, target)
    for i = 1, #frames do if frames[i] == target then return true end end
    return false
end

local function AssignFramesToConfigs(bars)
    local assignment = _tbbAssignment
    wipe(assignment)
    if not bars then return assignment end

    local viewer = _G["BuffBarCooldownViewer"]
    if not viewer or not viewer.itemFramePool then return assignment end

    -- Snapshot the active pool once (enumeration is consumed by EnumerateActive)
    -- and resolve each frame's canonical spell id ONCE here -- the passes below
    -- would otherwise re-query it O(configs x frames) per tick, and each call
    -- pcalls live WoW frame APIs. Caching also gives every pass a consistent
    -- within-tick view of each frame's identity.
    local GetCanonical = ns.GetCanonicalSpellIDForFrame
    local frames = _tbbFrameScratch
    wipe(frames)
    wipe(_tbbFrameSID)
    for frame in viewer.itemFramePool:EnumerateActive() do
        frames[#frames + 1] = frame
        _tbbFrameSID[frame] = GetCanonical and GetCanonical(frame) or nil
    end

    local consumed = _tbbConsumed
    wipe(consumed)

    -- Pass 1: sticky.
    for _, cfg in ipairs(bars) do
        local bound = _tbbStickyFrame[cfg]
        if bound and not consumed[bound] and FrameIsActive(frames, bound) then
            local sid = _tbbFrameSID[bound]
            if sid then
                -- Clean read available: keep only if still the right variant.
                if CfgWantsSID(cfg, sid) then
                    assignment[cfg]   = bound
                    consumed[bound]   = true
                else
                    _tbbStickyFrame[cfg] = nil
                end
            else
                -- Secret/combat: trust the binding locked in earlier.
                assignment[cfg] = bound
                consumed[bound] = true
            end
        end
    end

    -- Pass 2: exact per-frame identity.
    for _, cfg in ipairs(bars) do
        if not assignment[cfg] then
            for i = 1, #frames do
                local frame = frames[i]
                if not consumed[frame] then
                    local sid = _tbbFrameSID[frame]
                    if sid and CfgWantsSID(cfg, sid) then
                        assignment[cfg]      = frame
                        consumed[frame]      = true
                        _tbbStickyFrame[cfg] = frame
                        break
                    end
                end
            end
        end
    end

    -- Pass 3: cooldownInfo/linkedSpellIDs struct fallback. Do NOT sticky a fuzzy
    -- match -- let a later clean read re-pair it exactly in pass 2.
    for _, cfg in ipairs(bars) do
        if not assignment[cfg] then
            for i = 1, #frames do
                local frame = frames[i]
                if not consumed[frame] and MatchFrameToConfig(frame, cfg) then
                    assignment[cfg] = frame
                    consumed[frame] = true
                    break
                end
            end
        end
    end

    return assignment
end
ns.AssignTBBFramesToConfigs = AssignFramesToConfigs

--- Frame-based check: is a spellID present in BuffBarCooldownViewer?
--- Iterates the tiny pool (~3-5 frames) and uses MatchesSID for robust
--- multi-field matching (overrideSpellID, spellID, linkedSpellIDs).
function ns.IsSpellInBuffBarViewer(spellID)
    if not spellID or spellID <= 0 then return false end
    local viewer = _G["BuffBarCooldownViewer"]
    if not viewer or not viewer.itemFramePool then return false end
    local gci = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
    if not gci then return false end
    local GetCanonical = ns.GetCanonicalSpellIDForFrame
    for frame in viewer.itemFramePool:EnumerateActive() do
        local cdID = frame.cooldownID
        if cdID then
            local info = gci(cdID)
            if info and MatchesSID(info, spellID) then
                return true
            end
            -- Fallback: check frame's canonical spell ID (aura variants).
            if GetCanonical then
                local frameSID = GetCanonical(frame)
                if frameSID == spellID then return true end
            end
        end
    end
    return false
end

--- Enumerate all spells currently in BuffBarCooldownViewer (Blizzard's
--- "Tracked Bars" section). Returns an array of {spellID, cdID, name, icon}
--- entries sorted by layoutIndex then spellID. This is the source of truth
--- for the TBB spell picker -- TBB IS our display of these bars, so the
--- picker must enumerate THIS pool and not the Tracked Buffs icon viewer.
function ns.GetTrackedBarSpells(includeUntalented)
    local result = {}
    local GetCanonical = ns.GetCanonicalSpellIDForFrame
    local seen = {}

    -- Resolve a display name, appending subtext (e.g. "Solar", "Lunar") to
    -- disambiguate spells that share a base name like Eclipse.
    local function ResolveName(sid)
        local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(sid)
        if name and C_Spell.GetSpellSubtext then
            local sub = C_Spell.GetSpellSubtext(sid)
            if sub and sub ~= "" then name = name .. " (" .. sub .. ")" end
        end
        return name
    end

    local viewer = _G["BuffBarCooldownViewer"]
    if viewer and viewer.itemFramePool then
        for frame in viewer.itemFramePool:EnumerateActive() do
            if frame:IsShown() or frame.cooldownInfo then
                local sid = GetCanonical and GetCanonical(frame)
                if sid and sid > 0 and not seen[sid] then
                    seen[sid] = true
                    local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid)
                    result[#result + 1] = {
                        spellID     = sid,
                        cdID        = frame.cooldownID,
                        name        = ResolveName(sid) or ("Spell " .. sid),
                        icon        = icon,
                        layoutIndex = frame.layoutIndex or 0,
                        -- Live pool members are always learned. Catalog entries
                        -- appended below may not be.
                        isKnown     = true,
                    }
                end
            end
        end
    end

    -- Tracked-but-untalented bar spells have no live BuffBar frame, so pull them
    -- from the settings catalog (TrackedBar category). Picker-only
    -- (includeUntalented); auto-add and section checks stay live-only. Provider
    -- down or names missing -> nothing appended (identical to old behavior).
    -- Dedup by canonical sid, matching the live-pool dedup above.
    if includeUntalented and ns.EnumerateCDMSettingsCatalog then
        local evc = Enum and Enum.CooldownViewerCategory
        local barCat = evc and (evc.TrackedBar or 3)
        local catalog = barCat and ns.EnumerateCDMSettingsCatalog({ [barCat] = true })
        if catalog then
            local extra = 0
            for _, ce in ipairs(catalog) do
                if ce.sid and ce.sid > 0 and not seen[ce.sid] then
                    seen[ce.sid] = true
                    local nm = ResolveName(ce.sid)
                    if nm then
                        local known = (IsPlayerSpell and IsPlayerSpell(ce.sid)) and true or false
                        local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(ce.sid)
                        extra = extra + 1
                        result[#result + 1] = {
                            spellID     = ce.sid,
                            cdID        = ce.cdID,
                            name        = nm,
                            icon        = icon,
                            -- No live frame -> no layoutIndex; sort after live
                            -- entries, keeping catalog order among themselves.
                            layoutIndex = 100000 + extra,
                            isKnown     = known,
                        }
                    end
                end
            end
        end
    end

    table.sort(result, function(a, b)
        if a.layoutIndex ~= b.layoutIndex then return a.layoutIndex < b.layoutIndex end
        return (a.name or "") < (b.name or "")
    end)
    return result
end

-------------------------------------------------------------------------------
--  Auto-add: opt-in per group ("Auto-Add New to This Group"). While a group
--  holds the flag, any spell newly appearing in Blizzard's Tracked Bars
--  section gets a bar created in that group; turning the flag ON populates a
--  bar for every currently tracked spell. Bars the user deletes stay deleted:
--  their spells remain in the tbb.autoSeen ledger (only the populate-on-enable
--  pass ignores the ledger, since turning it on means "give me everything").
-------------------------------------------------------------------------------
local function SpellCoveredByBars(bars, sp)
    -- Variant/override coverage: a bar saved for one form of a spell covers
    -- the whole linked set (base/override/aura variants share a cooldownInfo),
    -- so an Eclipse Solar bar is not duplicated when Lunar's frame appears
    -- under a talent-swapped id.
    local info
    if sp.cdID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        info = C_CooldownViewer.GetCooldownViewerCooldownInfo(sp.cdID)
    end
    for _, cfg in ipairs(bars) do
        if CfgWantsSID(cfg, sp.spellID) then return true end
        if info then
            if CfgWantsSID(cfg, info.spellID) then return true end
            if CfgWantsSID(cfg, info.overrideSpellID) then return true end
            if info.linkedSpellIDs then
                for _, lid in ipairs(info.linkedSpellIDs) do
                    if CfgWantsSID(cfg, lid) then return true end
                end
            end
        end
    end
    return false
end

-- Shared guards for both auto-add passes. Returns the tbb table, or nil when
-- the pass must not run right now.
local function AutoAddReady()
    if not (ECME and ECME.db) then ECME = ns.ECME end
    if not (ECME and ECME.db) then return nil end
    local p = ECME.db.profile
    if p.cdmBars and p.cdmBars.useBlizzardBuffBars then return nil end
    if InCombatLockdown() then return nil end
    return ns.GetTrackedBuffBars()
end

-- Worker: create a bar in `gid` for every tracked spell not covered by any
-- existing bar. `ignoreSeen` = full populate (the enable pass); otherwise
-- only never-seen spells are considered, so deleted bars stay deleted.
local function AutoAddTrackedToGroup(tbb, gid, ignoreSeen)
    local tracked = ns.GetTrackedBarSpells and ns.GetTrackedBarSpells() or {}
    -- An empty list also means "viewer not populated yet" (login order):
    -- nothing to act on either way.
    if #tracked == 0 then return 0 end
    -- Postpone while any pool frame's spell identity is still unresolved
    -- (login spell-data races): acting on a partial list could mis-read a
    -- long-tracked spell as "new" later.
    do
        local viewer = _G["BuffBarCooldownViewer"]
        local GetCanonical = ns.GetCanonicalSpellIDForFrame
        if viewer and viewer.itemFramePool and GetCanonical then
            for frame in viewer.itemFramePool:EnumerateActive() do
                if (frame:IsShown() or frame.cooldownInfo) and not GetCanonical(frame) then
                    return 0
                end
            end
        end
    end
    tbb.autoSeen = tbb.autoSeen or {}
    local added = 0
    for _, sp in ipairs(tracked) do
        if ignoreSeen or not tbb.autoSeen[sp.spellID] then
            tbb.autoSeen[sp.spellID] = true
            if not SpellCoveredByBars(tbb.bars, sp) then
                local idx = AddTrackedBuffBarCore(tbb, gid)
                local nb = tbb.bars[idx]
                nb.spellID = sp.spellID
                nb.name = sp.name
                -- Base-form capture for talent-override spells (same as the
                -- picker): keeps the bar matching once the talent is removed.
                if sp.cdID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
                    local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(sp.cdID)
                    if info and info.spellID and info.spellID > 0 and info.spellID ~= sp.spellID then
                        nb.baseSpellID = info.spellID
                    end
                end
                added = added + 1
            end
        end
    end
    return added
end

-- Incremental pass: bars for spells newly appearing in the Tracked Bars
-- section, routed to the flagged group. Returns the number of bars added
-- (configs only -- callers rebuild). No-op unless a group opted in.
function ns.EnsureTBBAutoBars()
    local tbb = AutoAddReady()
    if not tbb then return 0 end
    local gid = ns.TBBAutoAddGroupID()
    if not gid then return 0 end
    return AutoAddTrackedToGroup(tbb, gid, false)
end

-- Full populate for the moment "Auto-Add New to This Group" is switched ON:
-- one bar per tracked spell not already covered somewhere, ledger ignored.
function ns.PopulateTBBAutoAddGroup(gid)
    if not gid or gid == 0 then return 0 end
    local tbb = AutoAddReady()
    if not tbb then return 0 end
    return AutoAddTrackedToGroup(tbb, gid, true)
end

-- Debounced entry point for the buff-bar viewer pool hooks: a spell dragged
-- into Blizzard's Tracked Bars section acquires a new pool frame, which lands
-- here. Combat acquires are skipped (tracked-set edits happen out of combat;
-- mid-fight acquires are just known auras activating).
local _tbbAutoAddQueued = false
function ns.QueueTBBAutoAdd()
    if _tbbAutoAddQueued then return end
    if InCombatLockdown() then return end
    _tbbAutoAddQueued = true
    C_Timer.After(1.0, function()
        _tbbAutoAddQueued = false
        if ns.EnsureTBBAutoBars() > 0 then
            ns.BuildTrackedBuffBars()
            if ns.OnTBBBarsAutoAdded then ns.OnTBBBarsAutoAdded() end
        end
    end)
end

--- Frame-based check: is a spellID present in Essential or Utility viewers?
--- Same pattern as IsSpellInBuffBarViewer but for CD/Utility bars.
function ns.IsSpellInCDUtilViewer(spellID)
    if not spellID or spellID <= 0 then return false end
    local gci = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
    if not gci then return false end
    local viewers = { "EssentialCooldownViewer", "UtilityCooldownViewer" }
    for _, vName in ipairs(viewers) do
        local viewer = _G[vName]
        if viewer and viewer.itemFramePool then
            for frame in viewer.itemFramePool:EnumerateActive() do
                local cdID = frame.cooldownID
                if cdID then
                    local info = gci(cdID)
                    if info and MatchesSID(info, spellID) then
                        return true
                    end
                end
            end
        end
    end
    return false
end

-------------------------------------------------------------------------------
--  Stacks Helper (reads Blizzard child Applications frame)
-------------------------------------------------------------------------------
local function UpdateStacks(bar, blzChild, cfg)
    -- Read stacks from blzChild.Icon.Applications FontString.
    if blzChild and blzChild.Icon and blzChild.Icon.Applications then
        -- Pass the text straight through without comparing (it may be tainted).
        -- SetText accepts secret strings natively.
        local ok, txt = pcall(blzChild.Icon.Applications.GetText, blzChild.Icon.Applications)
        if ok and txt then
            bar._stacksText:SetText(txt)
            bar._stacksText:Show()
            -- Stack count for threshold overlay: read from aura data via the
            -- Blizzard child's auraInstanceID. The applications field is a
            -- secret number so we can't compare it directly, but StatusBar
            -- SetValue accepts secret numbers natively. Feed it straight to
            -- the threshold overlay (FeedTBBThresholdOverlay uses SetValue).
            local auraInstID = blzChild.auraInstanceID
            local auraUnit = blzChild.auraDataUnit
            if auraInstID and auraUnit then
                local ad = C_UnitAuras.GetAuraDataByAuraInstanceID(auraUnit, auraInstID)
                if ad and ad.applications then
                    bar._stackCount = ad.applications  -- secret number, fed to SetValue
                else
                    bar._stackCount = 0
                end
            else
                bar._stackCount = 0
            end
            return
        end
    end
    -- Fallback: top-level Applications (BuffIcon children)
    if blzChild and blzChild.Applications and blzChild.Applications:IsShown() then
        local appsText = blzChild.Applications.Applications
        if appsText then
            local ok, txt = pcall(appsText.GetText, appsText)
            if ok and txt and txt ~= "" then
                if bar._stacksText and not bar._stacksHidden then
                    bar._stacksText:SetText(txt)
                    bar._stacksText:Show()
                end
                local auraInstID = blzChild.auraInstanceID
                local auraUnit = blzChild.auraDataUnit
                if auraInstID and auraUnit then
                    local ad = C_UnitAuras.GetAuraDataByAuraInstanceID(auraUnit, auraInstID)
                    if ad and ad.applications then
                        bar._stackCount = ad.applications
                    else
                        bar._stackCount = 0
                    end
                else
                    bar._stackCount = 0
                end
                return
            end
        end
    end
    -- No stacks
    if bar._stacksText then bar._stacksText:Hide() end
    bar._stackCount = 0
end

-------------------------------------------------------------------------------
--  Pandemic Glow Helpers
-------------------------------------------------------------------------------
local function ClearPandemic(bar)
    if bar._pandemicGlowTarget then StopGlow(bar._pandemicGlowTarget) end
    bar._pandemicGlowActive   = false
    bar._pandemicGlowStyleIdx = nil
    bar._pandemicGlowTarget   = nil
end

--- Start or update the pandemic glow effect on a bar.
--- Called when the bar is in the pandemic window (caller checks the threshold).
--- Alpha is driven by the caller from the tick (smooth fade based on remaining%).
local function UpdatePandemic(bar, cfg)
    -- Glow target: icon overlay if icon shown, else bar overlay
    local glowTarget
    if bar._icon and bar._icon:IsShown() then
        if not bar._icon._pandemicOverlay then
            local ov = CreateFrame("Frame", nil, bar._icon)
            ov:SetAllPoints(bar._icon)
            ov:SetFrameLevel(bar._icon:GetFrameLevel() + 2)
            ov:SetAlpha(0)
            ov:EnableMouse(false)
            bar._icon._pandemicOverlay = ov
        end
        glowTarget = bar._icon._pandemicOverlay
    else
        glowTarget = bar._pandemicGlowOverlay
    end

    local style = cfg.pandemicGlowStyle or 1
    -- Bars (no icon): only pixel glow (1) and autocast (4) render on rectangles
    -- Icons: all styles allowed
    if not (bar._icon and bar._icon:IsShown()) then
        if style ~= 1 and style ~= 4 then style = 1 end
    end

    -- Start/restart glow on style or target change
    if not bar._pandemicGlowActive or bar._pandemicGlowStyleIdx ~= style
       or bar._pandemicGlowTarget ~= glowTarget then
        if bar._pandemicGlowActive and bar._pandemicGlowTarget
           and bar._pandemicGlowTarget ~= glowTarget then
            StopGlow(bar._pandemicGlowTarget)
        end
        local c = cfg.pandemicGlowColor or { r = 1, g = 1, b = 0 }
        local glowOpts = (style == 1) and {
            N      = cfg.pandemicGlowLines or 8,
            th     = cfg.pandemicGlowThickness or 2,
            period = cfg.pandemicGlowSpeed or 4,
            bg     = cfg.pandemicGlowBackground and {
                r = (cfg.pandemicGlowBackgroundColor and cfg.pandemicGlowBackgroundColor.r) or 0,
                g = (cfg.pandemicGlowBackgroundColor and cfg.pandemicGlowBackgroundColor.g) or 0,
                b = (cfg.pandemicGlowBackgroundColor and cfg.pandemicGlowBackgroundColor.b) or 0,
            } or nil,
        } or nil
        StartGlow(glowTarget, style, c.r or 1, c.g or 1, c.b or 0, glowOpts)
        bar._pandemicGlowActive   = true
        bar._pandemicGlowStyleIdx = style
        bar._pandemicGlowTarget   = glowTarget
    end

    -- Alpha is set by the caller (tick function) for smooth fade
end

-------------------------------------------------------------------------------
--  Blizzard Bar FontString Discovery
--  Finds the name and timer FontStrings on a Blizzard Bar StatusBar.
--  Caches references on the frame for subsequent ticks (zero alloc after first).
-------------------------------------------------------------------------------
local function GetBlizzBarFontStrings(blizzBar)
    if not blizzBar then return nil, nil end
    -- Return cached refs if already discovered (and found)
    local cached = _blizzBarFS[blizzBar]
    if cached and cached.nameFS then
        return cached.nameFS, cached.timerFS
    end
    -- Discover by iterating regions. The StatusBar has 2 FontStrings:
    -- 1st FontString = spell name, 2nd FontString = timer text.
    -- (Debug showed them as overall region [3] and [4] but only 2 are FontStrings.)
    local nameFS, timerFS
    local fsIdx = 0
    for _, rgn in pairs({ blizzBar:GetRegions() }) do
        if rgn:GetObjectType() == "FontString" then
            fsIdx = fsIdx + 1
            if fsIdx == 1 then nameFS = rgn end
            if fsIdx == 2 then timerFS = rgn end
        end
    end
    -- Cache via external table (use false as sentinel for "searched but not found")
    local d = BBFS(blizzBar)
    d.nameFS  = nameFS or false
    d.timerFS = timerFS or false
    return nameFS, timerFS
end

--- Check if a TBB config has a matching frame in BuffBarCooldownViewer.
--- Uses FindChild (frame-based matching via MatchFrameToConfig) instead
--- of spell-ID cache lookups. Robust against ID mismatches.
local function IsTrackedInCDM(cfg)
    return FindChild(cfg) ~= nil
end

-------------------------------------------------------------------------------
--  Bloodlust / Heroism duration bar (debuff-driven, self-timed)
--  The lust buff is cast by others and is secret, so it can't be mirrored from
--  a Blizzard buff-bar child. Instead we watch ONLY the player's Sated /
--  Exhaustion debuff (player-only UNIT_AURA, never a global aura scan) and start
--  a 40s bar on its rising edge -- the instant lust goes out. No login/reload
--  reconstruction: if you reload mid-lust, no bar (the debuff was not just
--  acquired). The matching preset uses popularKey == "bloodlust".
-------------------------------------------------------------------------------
local SATED_DEBUFFS = { 57723, 57724, 80354, 95809, 160455, 264689, 390435, 428628 }
local _lustExpiry   = 0
local _satedPresent = false
local _lustZoneGuard = 0          -- suppress rising edges until this time (set on zone-in)
local _lustListenerActive = false -- baseline _satedPresent only on (re)enable, not every rebuild
local _lustListener

local function _playerHasSated()
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return false end
    for i = 1, #SATED_DEBUFFS do
        -- Querying a KNOWN spellID returns the aura even when its fields are
        -- secret in combat, so the edge is detected mid-fight. We never read
        -- the (possibly secret) spellID back -- we already know it.
        if C_UnitAuras.GetPlayerAuraBySpellID(SATED_DEBUFFS[i]) then return true end
    end
    return false
end

-- Toggle the player-only Sated listener. Registered only while a lust bar
-- exists; baselines _satedPresent on enable so it fires only on NEW edges.
local function _ensureLustListener(enable)
    if enable then
        if not _lustListener then
            _lustListener = CreateFrame("Frame")
            _lustListener:SetScript("OnEvent", function(_, event, _, updateInfo)
                if event == "PLAYER_ENTERING_WORLD" then
                    -- Zone/login aura refresh: re-baseline WITHOUT arming and
                    -- suppress edges briefly. A Sated debuff we already carry
                    -- (e.g. zoning out of a dungeon) must never read as a fresh
                    -- cast and pop a phantom 40s bar in the open world.
                    _satedPresent = _playerHasSated()
                    _lustZoneGuard = GetTime() + 1.5
                    return
                end
                local present = _playerHasSated()
                -- Arm ONLY on a genuine incremental application: not a full aura
                -- refresh (zone/login resends every aura), and not inside the
                -- post-zone grace window.
                local isFull = updateInfo and updateInfo.isFullUpdate
                if present and not _satedPresent and not isFull
                    and GetTime() >= _lustZoneGuard then
                    _lustExpiry = GetTime() + 40  -- rising edge: lust just went out
                    -- Drive any Custom Auras (icon) lust display sharing this edge.
                    if ns.SignalLustCast then ns.SignalLustCast() end
                end
                _satedPresent = present
            end)
        end
        -- Baseline only on the OFF->ON transition. Re-baselining on every
        -- BuildTrackedBuffBars (which fires during zone changes, sometimes while
        -- the aura table is momentarily empty) could set _satedPresent=false and
        -- let the debuff's reappearance look like a fresh cast.
        if not _lustListenerActive then
            _satedPresent = _playerHasSated()
            _lustListener:RegisterUnitEvent("UNIT_AURA", "player")
            _lustListener:RegisterEvent("PLAYER_ENTERING_WORLD")
            _lustListenerActive = true
        end
    elseif _lustListener and _lustListenerActive then
        _lustListener:UnregisterAllEvents()
        _lustListenerActive = false
    end
end

-- Arm the shared Sated listener if EITHER a Tracking Bar lust bar OR a Custom
-- Auras (icon) lust display is enabled. Authoritative (scans the DB), so it is
-- safe to call from any rebuild/toggle path.
function ns.UpdateLustListener()
    local any = false
    local tbb = ns.GetTrackedBuffBars and ns.GetTrackedBuffBars()
    if tbb and tbb.bars then
        for _, cfg in ipairs(tbb.bars) do
            if cfg.enabled ~= false and cfg.popularKey == "bloodlust" then any = true; break end
        end
    end
    if not any and ns.AnyCustomAuraLust then any = ns.AnyCustomAuraLust() end
    _ensureLustListener(any)
    -- Sibling preset listeners, refreshed from the same buff/TBB change sites
    -- (every add/remove/rebuild path already calls UpdateLustListener).
    if ns.UpdateTimeSpiralListener then ns.UpdateTimeSpiralListener() end
    if ns.UpdatePotionCastListener then ns.UpdatePotionCastListener() end
end

-- Self-driven display for an event-armed, self-timed preset bar (Bloodlust 40s,
-- Time Spiral 10s): fill + timer come from our own countdown, not a Blizzard
-- frame. Name/icon are set in BuildTrackedBuffBars. `expiry` is the GetTime()
-- the window ends at; `duration` is the full window length (the bar's max).
local function _UpdateSelfTimedBar(bar, cfg, expiry, duration)
    local remaining = expiry - GetTime()
    if remaining <= 0 then
        if bar:IsShown() then bar:Hide() end
        return
    end
    local wasShown = bar:IsShown()
    if not wasShown then bar:Show() end
    local sb = bar._bar
    if sb then
        sb:SetMinMaxValues(0, duration)
        -- Smooth fill is baseline for tracking bars: they move in one direction
        -- at a known rate (no sudden jumps to read instantly, unlike a health
        -- bar), so interpolation only removes judder. wasShown snaps a fresh
        -- appearance instead of animating from a stale value.
        local smooth = wasShown and Enum and Enum.StatusBarInterpolation
            and Enum.StatusBarInterpolation.ExponentialEaseOut
        if smooth then
            sb:SetValue(remaining, smooth)
        else
            sb:SetValue(remaining)
        end
        if cfg.showSpark and bar._spark then bar._spark:Show() end
    end
    if cfg.showTimer and bar._timerText then
        if remaining < 10 then
            bar._timerText:SetText(string.format("%.1f", remaining))
        else
            bar._timerText:SetText(string.format("%d", remaining))
        end
        bar._timerText:Show()
    elseif bar._timerText then
        bar._timerText:Hide()
    end
end
local function UpdateLustBar(bar, cfg)
    _UpdateSelfTimedBar(bar, cfg, _lustExpiry, 40)
end

-------------------------------------------------------------------------------
--  Time Spiral "Free Move" preset (popularKey == "timespiral")
--  Mirrors Bloodlust, but armed off Blizzard's spell-activation glow on the
--  player's class movement ability -- the Time Spiral free-cast proc -- instead
--  of an aura. A whitelisted glow-SHOW starts a self-timed 10s window. Like
--  Bloodlust there is NO login/reload reconstruction: only a fresh glow arms it.
--  Talent-aware suppression drops glows that fire on a movement ability for
--  unrelated reasons (DH Inertia / Dash of Chaos, Warlock Soulburn).
-------------------------------------------------------------------------------
local TIME_SPIRAL_DURATION = 10
-- Per-class movement abilities that glow when Time Spiral grants a free cast.
local TIME_SPIRAL_TRIGGERS = {
    [48265] = true,   -- Death's Advance
    [195072] = true,  -- Fel Rush
    [189110] = true,  -- Infernal Strike
    [1850] = true,    -- Dash
    [252216] = true,  -- Tiger Dash
    [358267] = true,  -- Hover
    [186257] = true,  -- Aspect of the Cheetah
    [1953] = true,    -- Blink
    [212653] = true,  -- Shimmer
    [361138] = true,  -- Roll
    [119085] = true,  -- Chi Torpedo
    [190784] = true,  -- Divine Steed
    [73325] = true,   -- Leap of Faith
    [2983] = true,    -- Sprint
    [192063] = true,  -- Gust of Wind
    [58875] = true,   -- Spirit Walk
    [79206] = true,   -- Spiritwalker's Grace
    [48020] = true,   -- Demonic Circle: Teleport
    [6544] = true,    -- Heroic Leap
}
-- Talent-gated abilities that ALSO glow a movement ability for reasons unrelated
-- to the Time Spiral proc. While the talent is known, a cast of one suppresses
-- the glow that follows for a short window.
local TIME_SPIRAL_GLOW_FILTERS = {
    { talent = 427640, spells = { 198793, 370965, 195072 } },  -- DH Inertia
    { talent = 427794, spells = { 195072 } },                  -- DH Dash of Chaos
    { talent = 385899, spells = { 385899 } },                  -- Warlock Soulburn
}
-- State grouped in one table to stay clear of the file's local budget.
local _ts = { expiry = 0, suppressUntil = 0, suppress = {}, active = false, frame = nil }

local function _rebuildTimeSpiralSuppress()
    wipe(_ts.suppress)
    local known = C_SpellBook and C_SpellBook.IsSpellKnown
    if not known then return end
    for _, e in ipairs(TIME_SPIRAL_GLOW_FILTERS) do
        if known(e.talent) then
            for _, sid in ipairs(e.spells) do _ts.suppress[sid] = true end
        end
    end
end

-- Toggle the glow listener. Registered only while an enabled Time Spiral bar or
-- Custom Auras (icon) display exists. Glow-event spellIDs are clean (not secret).
local function _ensureTimeSpiralListener(enable)
    if enable then
        if not _ts.frame then
            _ts.frame = CreateFrame("Frame")
            _ts.frame:SetScript("OnEvent", function(_, event, ...)
                if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
                    local sid = ...
                    if not TIME_SPIRAL_TRIGGERS[sid] then return end
                    if GetTime() < _ts.suppressUntil then return end
                    _ts.expiry = GetTime() + TIME_SPIRAL_DURATION  -- free move just granted
                    -- Drive any Custom Auras (icon) display sharing this edge.
                    if ns.SignalTimeSpiralCast then ns.SignalTimeSpiralCast() end
                elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
                    local sid = ...
                    if not TIME_SPIRAL_TRIGGERS[sid] then return end
                    -- Proc consumed (you used the free move) or the buff expired:
                    -- end the window now so the bar / icon disappear with the glow
                    -- instead of riding out the full 10s. Guarded on an active
                    -- window so an unrelated trigger's hide can't spuriously fire.
                    if _ts.expiry > GetTime() then
                        _ts.expiry = 0
                        if ns.SignalTimeSpiralEnd then ns.SignalTimeSpiralEnd() end
                    end
                elseif event == "UNIT_SPELLCAST_SENT" then
                    -- (unit, target, castGUID, spellID); arg4 is the spellID.
                    local _, _, _, sid = ...
                    if sid and _ts.suppress[sid] then
                        _ts.suppressUntil = GetTime() + 1.5
                    end
                elseif event == "TRAIT_CONFIG_UPDATED" or event == "PLAYER_ENTERING_WORLD" then
                    _rebuildTimeSpiralSuppress()
                end
            end)
        end
        if not _ts.active then
            _rebuildTimeSpiralSuppress()
            _ts.frame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
            _ts.frame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
            _ts.frame:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
            _ts.frame:RegisterEvent("TRAIT_CONFIG_UPDATED")
            _ts.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
            _ts.active = true
        end
    elseif _ts.frame and _ts.active then
        _ts.frame:UnregisterAllEvents()
        _ts.active = false
    end
end

-- Arm the glow listener if EITHER a Time Spiral Tracking Bar OR a Custom Auras
-- (icon) Time Spiral display is enabled. Authoritative (scans the DB).
function ns.UpdateTimeSpiralListener()
    local any = false
    local tbb = ns.GetTrackedBuffBars and ns.GetTrackedBuffBars()
    if tbb and tbb.bars then
        for _, cfg in ipairs(tbb.bars) do
            if cfg.enabled ~= false and cfg.popularKey == "timespiral" then any = true; break end
        end
    end
    if not any and ns.AnyCustomAuraTimeSpiral then any = ns.AnyCustomAuraTimeSpiral() end
    _ensureTimeSpiralListener(any)
end

-------------------------------------------------------------------------------
--  Self-cast potion presets (Light's Potential, Potion of Recklessness,
--  Invisibility Potion). NO aura tracking: a hardcoded window starts the moment
--  the potion's spell is cast, exactly like the CDM buff-bar / Fake-Active
--  potions. Mirrors the Bloodlust/Time Spiral self-timed model -- only a fresh
--  cast arms it, so a reload mid-buff shows nothing until the next use.
--  Built from BUFF_BAR_PRESETS: every preset that is NOT a tbbOnly special
--  (bloodlust/timespiral are event-driven and handled above) is cast-timed.
-------------------------------------------------------------------------------
local _potionDur = {}       -- [popularKey] = hardcoded window seconds
local _potionTrigger = {}   -- [castSpellID] = popularKey
do
    local presets = ns.BUFF_BAR_PRESETS
    if presets then
        for _, p in ipairs(presets) do
            if not p.tbbOnly and p.spellIDs and p.duration then
                _potionDur[p.key] = p.duration
                for _, sid in ipairs(p.spellIDs) do
                    if type(sid) == "number" and sid > 0 then _potionTrigger[sid] = p.key end
                end
            end
        end
    end
end
local _potionExpiry = {}    -- [popularKey] = GetTime() the window ends at
local _potionFrame
local _potionActive = false

local function _ensurePotionCastListener(enable)
    if enable then
        if not _potionFrame then
            _potionFrame = CreateFrame("Frame")
            -- UNIT_SPELLCAST_SUCCEEDED (player): the same edge the CDM buff-bar
            -- potions fire on. arg4 is the cast spellID (clean, never secret).
            _potionFrame:SetScript("OnEvent", function(_, _, _, _, spellID)
                local key = spellID and _potionTrigger[spellID]
                if not key then return end
                _potionExpiry[key] = GetTime() + (_potionDur[key] or 30)
            end)
        end
        if not _potionActive then
            _potionFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
            _potionActive = true
        end
    elseif _potionFrame and _potionActive then
        _potionFrame:UnregisterAllEvents()
        _potionActive = false
    end
end

-- Arm the cast listener only while an enabled potion-preset Tracking Bar exists.
-- Refreshed from the same change sites as the other preset listeners (fanned
-- out from UpdateLustListener).
function ns.UpdatePotionCastListener()
    local any = false
    local tbb = ns.GetTrackedBuffBars and ns.GetTrackedBuffBars()
    if tbb and tbb.bars then
        for _, cfg in ipairs(tbb.bars) do
            if cfg.enabled ~= false and cfg.popularKey and _potionDur[cfg.popularKey] then
                any = true; break
            end
        end
    end
    _ensurePotionCastListener(any)
end

-------------------------------------------------------------------------------
--  Main Tick: UpdateTrackedBuffBarTimers
--  Direct reskin of Blizzard's BuffBarCooldownViewer StatusBars.
--  Reads min/max/value from Blizzard's Bar -- zero duration computation.
-------------------------------------------------------------------------------
function ns.UpdateTrackedBuffBarTimers()
    if not ECME or not ECME.db then return end
    local MS, MD = ns._MemSnap, ns._MemDelta
    if MS then MS("TBBTick") end
    local tbb = ns.GetTrackedBuffBars()
    local bars = tbb.bars
    if not bars then if MD then MD("TBBTick") end return end

    -- Self-heal placeholder mode when user navigates away from CDM Tracking Bars
    if ns._tbbPlaceholderMode then
        local am = EllesmereUI and EllesmereUI.GetActiveModule and EllesmereUI:GetActiveModule()
        local ap = EllesmereUI and EllesmereUI.GetActivePage and EllesmereUI:GetActivePage()
        if am ~= "EllesmereUICooldownManager" or ap ~= "Tracking Bars" then
            ns._tbbPlaceholderMode = false
            if ns.HideTBBPlaceholders then ns.HideTBBPlaceholders() end
        end
    end


    -- Pair configs to Blizzard frames ONE-TO-ONE up front, consuming each frame
    -- once. Prevents two configs (e.g. Eclipse Solar + Lunar, which share a
    -- cooldownInfo) from both mirroring the same frame and showing twice.
    local assignment = AssignFramesToConfigs(bars)

    for i, cfg in ipairs(bars) do
        local bar = tbbFrames[i]
        if not bar or not bar._tbbReady then
            -- skip
        elseif ns._tbbPlaceholderMode then
            if not bar:IsShown() then bar:Show() end
        elseif cfg.enabled == false then
            bar:Hide()
        elseif cfg.popularKey == "bloodlust" then
            -- Self-driven 40s lust bar; no Blizzard frame to mirror.
            UpdateLustBar(bar, cfg)
        elseif cfg.popularKey == "timespiral" then
            -- Self-driven 10s Time Spiral "Free Move" bar; glow-armed, no frame.
            _UpdateSelfTimedBar(bar, cfg, _ts.expiry, TIME_SPIRAL_DURATION)
        elseif cfg.popularKey and _potionDur[cfg.popularKey] then
            -- Self-cast potion preset: hardcoded window off the spell-cast edge,
            -- no aura tracking / no Blizzard frame to mirror.
            _UpdateSelfTimedBar(bar, cfg, _potionExpiry[cfg.popularKey] or 0,
                _potionDur[cfg.popularKey])
        else
            local blzChild = assignment[cfg]
            if blzChild then ns.HookPandemicState(blzChild) end

            -- Active state must come from the CooldownViewer item's IsActive()
            -- (real aura state: expirationTime > now, or infinite auras), NOT
            -- IsShown(). A buff-bar item stays SHOWN even while inactive unless
            -- the user enabled Blizzard's "Hide When Inactive" edit-mode option
            -- (off by default), so IsShown() would make our mirrored bar visible
            -- 100% of the time. Fall back to IsShown() only if IsActive is absent.
            local isActive = false
            if blzChild then
                if blzChild.IsActive then
                    isActive = blzChild:IsActive() and true or false
                elseif blzChild.IsShown then
                    isActive = blzChild:IsShown() or false
                end
            end

            -- Blizzard viewer bind-miss fallback. The buff-bar viewer sometimes
            -- fails to bind a freshly applied aura to its frame (observed live:
            -- Avenging Wrath aura up, frame's auraInstanceID never set, IsActive
            -- stuck false until ANOTHER bar's activation forces a viewer
            -- refresh). When the assigned frame reads inactive but the player
            -- demonstrably carries the aura (known-spellID player-aura query,
            -- no scanning), drive the bar from the aura data directly. Reads
            -- only; our own frames only -- never pokes the Blizzard frame.
            local fbAura
            if not isActive and blzChild and not cfg.spellIDs
               and cfg.spellID and cfg.spellID > 0
               and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
                fbAura = C_UnitAuras.GetPlayerAuraBySpellID(cfg.spellID)
                if not fbAura and cfg.baseSpellID and cfg.baseSpellID > 0 then
                    fbAura = C_UnitAuras.GetPlayerAuraBySpellID(cfg.baseSpellID)
                end
            end

            -- Read Blizzard's StatusBar (the data source for fill/timer)
            local blizzBar = blzChild and blzChild.Bar

            if isActive then
                local wasShown = bar:IsShown()
                if not wasShown then bar:Show() end
                local sb = bar._bar

                -- Stacks (gated)
                if _anyStacks then UpdateStacks(bar, blzChild, cfg) end

                if blizzBar then
                    -- Mirror Blizzard's bar onto ours. Secret values pass
                    -- through natively to widget setters -- no Lua comparison.
                    sb:SetMinMaxValues(blizzBar:GetMinMaxValues())
                    -- Smooth fill is baseline (see UpdateLustBar note).
                    local smooth = wasShown and Enum and Enum.StatusBarInterpolation
                        and Enum.StatusBarInterpolation.ExponentialEaseOut
                    if smooth then
                        sb:SetValue(blizzBar:GetValue(), smooth)
                    else
                        sb:SetValue(blizzBar:GetValue())
                    end
                    if cfg.showSpark and bar._spark then bar._spark:Show() end

                    -- Auto fill color from Blizzard's bar texture
                    if (cfg.fillColorMode or "auto") == "auto" then
                        -- Cache texture references to avoid GetStatusBarTexture()
                        -- userdata allocation per tick
                        local blizzFillTex = bar._cachedBlizzFillTex
                        if not blizzFillTex then
                            blizzFillTex = blizzBar:GetStatusBarTexture()
                            bar._cachedBlizzFillTex = blizzFillTex
                        end
                        if blizzFillTex then
                            local br, bg, bb, ba = blizzFillTex:GetVertexColor()
                            if br then
                                if bar._gradientActive and bar._gradTex then
                                    local c1 = bar._gradColor1 or CreateColor(0,0,0,1)
                                    local c2 = bar._gradColor2 or CreateColor(0,0,0,1)
                                    bar._gradColor1 = c1
                                    bar._gradColor2 = c2
                                    c1.r, c1.g, c1.b, c1.a = br, bg, bb, ba or 1
                                    c2.r, c2.g, c2.b, c2.a = cfg.gradientR or 0.20, cfg.gradientG or 0.20, cfg.gradientB or 0.80, cfg.gradientA or 1
                                    bar._gradTex:SetGradient(cfg.gradientDir or "HORIZONTAL", c1, c2)
                                else
                                    local ourFillTex = bar._cachedOurFillTex
                                    if not ourFillTex then
                                        ourFillTex = sb:GetStatusBarTexture()
                                        bar._cachedOurFillTex = ourFillTex
                                    end
                                    if ourFillTex then ourFillTex:SetVertexColor(br, bg, bb, ba or 1) end
                                end
                            end
                        end
                    end

                    -- Name: read from aura data (same source as icon) so the
                    -- name always matches the actual buff, not the Blizzard
                    -- frame's font string which can be stale after pool
                    -- recycling. Falls back to C_Spell for the config spell ID.
                    if bar._nameText and bar._nameText:IsShown() then
                        local nameStr
                        if blzChild and blzChild.auraInstanceID and blzChild.auraDataUnit then
                            local ok, ad = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID,
                                blzChild.auraDataUnit, blzChild.auraInstanceID)
                            if ok and ad and ad.name then nameStr = ad.name end
                        end
                        if not nameStr then
                            local blizzNameFS = GetBlizzBarFontStrings(blizzBar)
                            if blizzNameFS then
                                local ok, txt = pcall(blizzNameFS.GetText, blizzNameFS)
                                if ok and txt then nameStr = txt end
                            end
                        end
                        if not nameStr and cfg.spellID and cfg.spellID > 0 then
                            local spInfo = C_Spell.GetSpellInfo(cfg.spellID)
                            if spInfo then nameStr = spInfo.name end
                        end
                        if nameStr then
                            bar._nameText:SetText(nameStr)
                            bar._nameSet = true
                        end
                    end
                    -- Timer: passthrough from Blizzard's FontString (changes constantly)
                    local _, blizzTimerFS = GetBlizzBarFontStrings(blizzBar)
                    -- Timer: passthrough every frame (changes constantly)
                    if cfg.showTimer and bar._timerText and blizzTimerFS then
                        bar._timerText:SetText(blizzTimerFS:GetText())
                        bar._timerText:Show()
                    elseif bar._timerText then
                        bar._timerText:Hide()
                    end

                    -- Icon: read from the live aura data so dynamic buffs
                    -- (Roll the Bones) show the actual rolled buff icon.
                    -- Fall back to cfg.spellID for non-dynamic buffs.
                    if bar._icon and bar._icon:IsShown() then
                        local gotIcon = false
                        if blzChild and blzChild.auraInstanceID and blzChild.auraDataUnit then
                            local ok, ad = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID,
                                blzChild.auraDataUnit, blzChild.auraInstanceID)
                            if ok and ad and ad.icon then
                                bar._icon._tex:SetTexture(ad.icon)
                                gotIcon = true
                            end
                        end
                        if not gotIcon then
                            local iconSID = cfg.spellID
                            if iconSID and iconSID > 0 and iconSID ~= bar._lastIconSID then
                                local spInfo = C_Spell.GetSpellInfo(iconSID)
                                if spInfo and spInfo.iconID then
                                    bar._icon._tex:SetTexture(spInfo.iconID)
                                    bar._lastIconSID = iconSID
                                end
                            end
                        end
                    end

                    -- Pandemic glow: Blizzard's ShowPandemicStateFrame
                    -- hook sets _pandemicState. User must configure
                    -- pandemic alerts in Blizzard CDM settings.
                    if _anyPandemic and cfg.pandemicGlow then
                        local inPandemic = blzChild and _pandemicState[blzChild]
                        -- Fallback for auras Blizzard never pandemic-flags
                        -- (currently only Lifebloom). bar._isLifebloom is cached
                        -- after the first resolve, so once a bar is known not to
                        -- be Lifebloom this is a single table read and skips.
                        if not inPandemic and blzChild and bar._isLifebloom ~= false then
                            inPandemic = LifebloomPandemic(bar, blzChild)
                        end
                        -- TBBs always show our glow (including Blizzard Default)
                        -- because Blizzard's native PandemicIcon is on the
                        -- hidden blzChild frame, not our visible TBB bar.
                        if inPandemic then
                            if not bar._pandemicGlowActive then UpdatePandemic(bar, cfg) end
                            if bar._pandemicGlowTarget then bar._pandemicGlowTarget:SetAlpha(1) end
                        elseif bar._pandemicGlowActive then
                            ClearPandemic(bar)
                        end
                    elseif bar._pandemicGlowActive then
                        ClearPandemic(bar)
                    end
                else
                    -- Active aura but no Blizzard bar data: show full bar
                    sb:SetMinMaxValues(0, 1)
                    sb:SetValue(1)
                    if bar._timerText then bar._timerText:Hide() end
                    if bar._spark then bar._spark:Hide() end
                    if bar._pandemicGlowActive then ClearPandemic(bar) end
                end

                -- Threshold feed (gated)
                if _anyThreshold and cfg.stackThresholdEnabled then
                    FeedTBBThresholdOverlay(bar)
                end

                -- Deferred tick marks
                if bar._ticksDirty and sb then
                    local bw = sb:GetWidth()
                    if bw and bw > 0 then
                        ApplyTBBTickMarks(sb, cfg, bar._threshTicks,
                            cfg.verticalOrientation, bar._tickOverlay)
                        bar._ticksDirty = nil
                    end
                end
            elseif fbAura then
                -- Bind-miss fallback: self-drive fill/timer from the live aura
                -- until Blizzard's frame catches up (isActive then resumes the
                -- normal mirror path seamlessly).
                local wasShown = bar:IsShown()
                if not wasShown then bar:Show() end
                local sb = bar._bar
                local dur = fbAura.duration
                local exp = fbAura.expirationTime
                local isSec = issecretvalue
                local clean = dur and exp and not (isSec and (isSec(dur) or isSec(exp)))
                if sb then
                    if clean and dur > 0 then
                        local remaining = exp - GetTime()
                        if remaining < 0 then remaining = 0 end
                        sb:SetMinMaxValues(0, dur)
                        local smooth = wasShown and Enum and Enum.StatusBarInterpolation
                            and Enum.StatusBarInterpolation.ExponentialEaseOut
                        if smooth then
                            sb:SetValue(remaining, smooth)
                        else
                            sb:SetValue(remaining)
                        end
                        if cfg.showTimer and bar._timerText then
                            bar._timerText:SetText(FormatTime(remaining))
                            bar._timerText:Show()
                        elseif bar._timerText then
                            bar._timerText:Hide()
                        end
                    else
                        -- Duration unreadable (secret) or infinite aura: show a
                        -- full bar with no countdown.
                        sb:SetMinMaxValues(0, 1)
                        sb:SetValue(1)
                        if bar._timerText then bar._timerText:Hide() end
                    end
                    if cfg.showSpark and bar._spark then bar._spark:Show() end
                end
                -- Keep the extras quiet in fallback mode: no Blizzard child to
                -- read stacks/pandemic state from.
                if bar._stacksText then bar._stacksText:Hide() end
                bar._stackCount = 0
                if bar._pandemicGlowActive then ClearPandemic(bar) end
            else
                -- Inactive: clear transient state
                bar._cachedBlizzFillTex = nil
                bar._cachedOurFillTex = nil
                if _anyPandemic and bar._pandemicGlowActive then ClearPandemic(bar) end
                if bar._stacksText then bar._stacksText:Hide() end
                bar._stackCount = 0
                if cfg.hideWhenInactive == false then
                    -- "Hide When Inactive" off: keep the bar on screen as an
                    -- empty idle bar (name visible, no fill / timer / spark).
                    if not bar:IsShown() then bar:Show() end
                    local sb = bar._bar
                    if sb then sb:SetMinMaxValues(0, 1); sb:SetValue(0) end
                    if bar._timerText then bar._timerText:Hide() end
                    if bar._spark then bar._spark:Hide() end
                else
                    bar._nameSet = nil
                    if bar:IsShown() then bar:Hide() end
                end
            end
        end
    end

    -- Re-pack visible grouped Tracking Bars after the active/inactive pass so
    -- hidden buffs do not reserve a slot in the group.
    ReflowVisibleGroupedTBBars(tbb, bars)

    -- Deferred name fill: if BuildTrackedBuffBars couldn't resolve the spell
    -- name (data not loaded yet), retry here each tick until it succeeds.
    for i, cfg in ipairs(bars) do
        local bar = tbbFrames[i]
        if bar and bar._nameText and not bar._nameSet and cfg.spellID and cfg.spellID > 0 then
            local si = C_Spell.GetSpellInfo(cfg.spellID)
            if si and si.name then
                bar._nameText:SetText(si.name)
                bar._nameSet = true
            end
        end
    end

    -- Spark re-anchor: use cached texture ref to avoid GetStatusBarTexture() alloc.
    -- SetPoint on an already-anchored spark to the same anchor is a no-op internally.
    for _, bar in ipairs(tbbFrames) do
        if bar and bar._spark and bar._spark:IsShown() and bar._bar then
            local anchor = (bar._gradientActive and bar._gradClip) or bar._cachedOurFillTex
            if not anchor then
                anchor = bar._bar:GetStatusBarTexture()
                bar._cachedOurFillTex = anchor
            end
            if anchor then
                bar._spark:SetPoint("CENTER", anchor,
                    bar._lastVertical and (bar._lastReverse and "BOTTOM" or "TOP")
                        or (bar._lastReverse and "LEFT" or "RIGHT"),
                    bar._lastVertical and 0 or (bar._lastReverse and 1 or -1), 0)
            end
        end
    end

    -- Smooth opacity lerp
    local dt = tbbTickFrame and tbbTickFrame._lastDt or 0.016
    local lerpSpeed = dt * 8
    for _, f in ipairs(tbbFrames) do
        if f and f._opacityTarget then
            local cur = f:GetAlpha()
            local tgt = f._opacityTarget
            if abs(cur - tgt) > 0.005 then
                f:SetAlpha(cur + (tgt - cur) * min(1, lerpSpeed))
            elseif cur ~= tgt then
                f:SetAlpha(tgt)
            end
        end
    end
    if ns._MemDelta then ns._MemDelta("TBBTick") end
end

-------------------------------------------------------------------------------
--  Build / Rebuild All Tracking Bars
-------------------------------------------------------------------------------
function ns.BuildTrackedBuffBars()
    ECME = ns.ECME
    if not ECME or not ECME.db then return end
    -- No InCombatLockdown guard needed: TBB frames are our own (UIParent),
    -- not secure Blizzard frames, so positioning in combat is safe.
    _tbbRebuildPending = false

    local p = ECME.db.profile

    -- Migration: fix swapped width/height from unlock mode resize bug.
    -- Horizontal bars should be wider than tall; vertical bars taller than wide.
    do
        local tbb = ns.GetTrackedBuffBars()
        local bars = tbb and tbb.bars
        if bars then
            -- Width/height auto-swap removed: the Vertical Orientation
            -- toggle already swaps dimensions on toggle (options line 2756).
            -- The per-build swap fought slider input, making resizes erratic.
        end
    end

    -- If user chose "Use Blizzard CDM Bars", hide all TBB frames and bail
    if p.cdmBars and p.cdmBars.useBlizzardBuffBars then
        for i = 1, #tbbFrames do
            if tbbFrames[i] then tbbFrames[i]:Hide() end
        end
        if tbbTickFrame then tbbTickFrame:Hide() end
        return
    end

    -- Pre-populate bars for spells newly added to Blizzard's Tracked Bars
    -- section BEFORE reading the bar list, so this rebuild picks them up.
    ns.EnsureTBBAutoBars()

    local tbb = ns.GetTrackedBuffBars()
    -- Hold the per-group orientation invariant before reading any configs
    ns.EnforceTBBGroupOrientation(tbb)
    local bars = tbb.bars
    local _tbbPos = ns.GetTBBPositions()
    ResetReflowStates()

    -- Hide bars beyond current count
    for i = #bars + 1, #tbbFrames do
        if tbbFrames[i] then tbbFrames[i]:Hide() end
    end

    -- Reset feature-gating flags
    _anyPandemic  = false
    _anyThreshold = false
    _anyStacks    = false

    local anyEnabled = false
    local anyLust = false  -- any enabled bloodlust bar -> needs the Sated listener
    local lastBarByGroup = {}  -- gid -> previous enabled member frame (chain tail)
    for i, cfg in ipairs(bars) do
        -- Update gating flags
        if cfg.pandemicGlow                             then _anyPandemic  = true end
        if cfg.stackThresholdEnabled                    then _anyThreshold = true; _anyStacks = true end
        if (cfg.stacksPosition or "center") ~= "none"  then _anyStacks    = true end

        if not tbbFrames[i] then
            tbbFrames[i] = CreateTrackedBuffBarFrame(UIParent, i)
        end
        local bar = tbbFrames[i]

        if cfg.enabled == false then
            bar:Hide()
        else
            anyEnabled = true
            if cfg.popularKey == "bloodlust" then anyLust = true end
            ApplyTrackedBuffBarSettings(bar, cfg)

            -- Icon texture
            if bar._icon and bar._icon._tex then
                local iconID
                if cfg.popularKey then
                    for _, pe in ipairs(TBB_POPULAR_BUFFS) do
                        if pe.key == cfg.popularKey then iconID = pe.icon; break end
                    end
                end
                if not iconID and cfg.spellID and cfg.spellID > 0 then
                    local spInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(cfg.spellID)
                    if spInfo then iconID = spInfo.iconID end
                end
                if iconID then bar._icon._tex:SetTexture(iconID) end
            end

            -- Name text
            local namePos2 = cfg.namePosition or ((cfg.showName ~= false) and "left" or "none")
            if namePos2 ~= "none" and bar._nameText then
                local displayName = cfg.name
                if (not displayName or displayName == "") and cfg.spellID and cfg.spellID > 0 then
                    local spInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(cfg.spellID)
                    displayName = spInfo and spInfo.name
                    if not displayName and C_Spell.RequestLoadSpellData then
                        C_Spell.RequestLoadSpellData(cfg.spellID)
                    end
                end
                bar._nameText:SetText(displayName or "")
                bar._nameSet = displayName and displayName ~= "" or false
            end

            -- Saved position / grouping. A group's FIRST enabled member takes
            -- the independent branch (its own saved pos) and becomes that
            -- group's anchor; later members of the same group chain to the
            -- previous member using the group's grow/spacing. Independent
            -- bars (gid 0) always take the independent branch.
            local gid = ns.TBBBarGroupID(cfg)
            local prevInGroup = gid ~= 0 and lastBarByGroup[gid] or nil
            if prevInGroup then
                -- Grouped: position relative to previous member of this group
                local growDir = (GroupGrowOf(tbb, gid) or "DOWN"):upper()
                local spacing = GroupSpacingOf(tbb, gid) or 2
                bar:ClearAllPoints()
                if growDir == "UP" then
                    bar:SetPoint("BOTTOM", prevInGroup, "TOP", 0, spacing)
                elseif growDir == "RIGHT" then
                    bar:SetPoint("LEFT", prevInGroup, "RIGHT", spacing, 0)
                elseif growDir == "LEFT" then
                    bar:SetPoint("RIGHT", prevInGroup, "LEFT", -spacing, 0)
                else
                    bar:SetPoint("TOP", prevInGroup, "BOTTOM", 0, -spacing)
                end
            else
                -- Independent positioning (group anchors and ungrouped bars)
                local posKey = tostring(i)
                local pos = _tbbPos[posKey]
                if pos and pos.point then
                    local unlockKey = "TBB_" .. posKey
                    local anchored = EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored(unlockKey)
                    if not anchored or not bar:GetLeft() then
                        bar:ClearAllPoints()
                        if pos.scale then pcall(function() bar:SetScale(pos.scale) end) end
                        bar:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
                    end
                else
                    bar:ClearAllPoints()
                    bar:SetPoint("CENTER", UIParent, "CENTER", 0, 200 - (i - 1) * ((cfg.height or 24) + 4))
                end
            end

            if gid ~= 0 then lastBarByGroup[gid] = bar end
            bar._tbbReady    = true
            bar._isPassive   = nil
            bar._stackCount  = 0
            bar._isLifebloom = nil  -- re-resolve Lifebloom identity after a rebuild
            bar:Hide()  -- tick will show when active
        end
    end

    -- Tick frame (every frame -- bar fill + spark need smooth updates)
    if anyEnabled then
        if not tbbTickFrame then
            tbbTickFrame = CreateFrame("Frame")
            local tbbAccum = 0
            tbbTickFrame:SetScript("OnUpdate", function(self, elapsed)
                tbbAccum = tbbAccum + elapsed
                if tbbAccum < 0.016 then return end
                self._lastDt = tbbAccum
                tbbAccum = 0
                ns.UpdateTrackedBuffBarTimers()
            end)
        end
        tbbTickFrame:Show()
    elseif tbbTickFrame then
        tbbTickFrame:Hide()
    end

    -- Start/stop the player-only Sated-debuff listener that drives the lust
    -- displays. Goes through the arbiter so a Custom Auras (icon) lust display
    -- keeps the listener armed even when no Tracking Bar lust bar exists.
    ns.UpdateLustListener()

    -- Unlock mode
    if ns.RegisterTBBUnlockElements then ns.RegisterTBBUnlockElements() end
end

-------------------------------------------------------------------------------
--  Unlock Mode Registration
-------------------------------------------------------------------------------
function ns.RegisterTBBUnlockElements()
    if not EllesmereUI or not EllesmereUI.RegisterUnlockElements then return end
    if not ECME or not ECME.db then return end
    local MK = EllesmereUI.MakeUnlockElement
    -- Never call UnregisterUnlockElement for TBB keys -- it triggers
    -- PruneStaleLinks which destroys saved anchor data in unlockAnchors.
    -- Instead, just overwrite registrations. The isHidden callback handles
    -- hiding movers for bars that don't exist in the current spec.
    local tbb = ns.GetTrackedBuffBars()
    local bars = tbb and tbb.bars
    if not bars or #bars == 0 then return end

    -- Each group's anchor (first enabled member) owns that group's mover; the
    -- other members hide theirs. Computed per build so it tracks group edits.
    local elements = {}
    for i, cfg in ipairs(bars) do
        local idx = i
        local posKey = tostring(idx)
        local bar = tbbFrames[idx]
        local barGid = ns.TBBBarGroupID(cfg)
        local isGroupMover = barGid ~= 0
            and idx == ns.TBBGroupAnchorIndex(barGid)
            and ns.TBBGroupedCount(barGid) >= 2
        if bar then
            elements[#elements + 1] = MK({
                key   = "TBB_" .. posKey,
                label = isGroupMover
                    and (ns.TBBGroupName(barGid) or EllesmereUI.Lf("Tracking Bar Group %d", barGid))
                    or EllesmereUI.Lf("Tracking Bar: %s", cfg.name or EllesmereUI.Lf("Bar %d", idx)),
                group = "Cooldown Manager",
                order = 650,
                noResize = true,
                -- Tracking bars may size-MATCH to other elements (allowMatchSource),
                -- but other elements may NOT match to them (noSizeMatchTarget): a
                -- tracking bar's size is driven by its own CDM sliders / dynamic
                -- content, so it should never be used as a sizing reference.
                allowMatchSource  = true,
                noSizeMatchTarget = true,
                isHidden = function()
                    local t = ns.GetTrackedBuffBars()
                    local b = t and t.bars
                    if not b or idx > #b then return true end
                    local c = b[idx]
                    -- Independent bars always show their own mover.
                    local gid = ns.TBBBarGroupID(c)
                    if gid == 0 then return false end
                    -- Grouped bars: only the group's anchor shows a mover (it
                    -- moves the whole group). Hide every other member -- enabled
                    -- OR disabled (a disabled member re-enables straight into the
                    -- chain, so its own mover would be a phantom). When no member
                    -- is enabled the anchor is nil and all are hidden.
                    return idx ~= ns.TBBGroupAnchorIndex(gid)
                end,
                -- Grouped non-anchor members are positioned by the relative
                -- SetPoint chain in BuildTrackedBuffBars. Report them as
                -- addon-owned so the generic anchor system never repositions
                -- them -- otherwise a cascade/override SetPoint severs the chain
                -- (e.g. in combat via a stale per-member anchor link). A group
                -- ANCHOR returns false, so it stays fully element-anchorable.
                isAnchored = function()
                    local t = ns.GetTrackedBuffBars()
                    local b = t and t.bars
                    local c = b and b[idx]
                    local gid = c and ns.TBBBarGroupID(c) or 0
                    if gid == 0 then return false end
                    return idx ~= ns.TBBGroupAnchorIndex(gid)
                end,
                getFrame = function()
                    -- Never expose a stale frame when the current spec has
                    -- fewer bars: anchors involving this key stay dormant
                    -- (children hold position) instead of gluing to a hidden
                    -- frame left at another spec's coordinates.
                    local t = ns.GetTrackedBuffBars()
                    local b = t and t.bars
                    if not b or idx > #b then return nil end
                    return tbbFrames[idx]
                end,
                getSize  = function()
                    -- width/height ARE the total footprint (icon included),
                    -- so matching reads the stored dims directly.
                    local t = ns.GetTrackedBuffBars()
                    local c = t.bars and t.bars[idx]
                    local PPg = EllesmereUI and EllesmereUI.PP
                    local sn = PPg and PPg.Snap or function(v) return v end
                    if c then
                        return sn(c.width or 270), sn(c.height or 24)
                    end
                    return 270, 24
                end,
                setWidth = function(_, w)
                    local t = ns.GetTrackedBuffBars()
                    local c = t.bars and t.bars[idx]
                    if not c then return end
                    local f = tbbFrames[idx]
                    local PPt = EllesmereUI and EllesmereUI.PP
                    w = PPt and PPt.Snap(w) or math.floor(w + 0.5)
                    -- Persist during unlock (manual) AND during match propagation,
                    -- so a width match TO another element survives the next
                    -- BuildTrackedBuffBars instead of reverting to the slider value.
                    if EllesmereUI._unlockActive or EllesmereUI._propagatingMatch then
                        c.width = w
                        -- Grouped bars share width: fan this out to the rest of the
                        -- group (covers unlock drag-resize AND a width-MATCH on the
                        -- group anchor, both of which route through here).
                        ns.PropagateTBBGroupSize(idx, "width", w)
                    end
                    if f then f:SetWidth(w) end
                end,
                setHeight = function(_, h)
                    local t = ns.GetTrackedBuffBars()
                    local c = t.bars and t.bars[idx]
                    if not c then return end
                    local PPt = EllesmereUI and EllesmereUI.PP
                    h = PPt and PPt.Snap(h) or math.floor(h + 0.5)
                    local f = tbbFrames[idx]
                    -- Persist during unlock AND match propagation (see setWidth).
                    if EllesmereUI._unlockActive or EllesmereUI._propagatingMatch then
                        c.height = h
                        ns.PropagateTBBGroupSize(idx, "height", h)
                    end
                    if f then f:SetHeight(h) end
                end,
                savePos = function(_, point, relPoint, x, y)
                    local pos = ns.GetTBBPositions()
                    pos[posKey] = { point = point, relPoint = relPoint, x = x, y = y }
                    -- A group is dragged via its anchor's mover, but the saved
                    -- position is keyed by the anchor's INDEX. If the anchor later
                    -- changes (the first member leaves the group or is disabled)
                    -- the new anchor would read a stale per-index coordinate and
                    -- the group would teleport. Mirror the group origin into every
                    -- member's key so whichever bar becomes the anchor reads the
                    -- current position.
                    local t = ns.GetTrackedBuffBars()
                    local c0 = t.bars and t.bars[idx]
                    local gid = c0 and ns.TBBBarGroupID(c0) or 0
                    if gid ~= 0 and idx == ns.TBBGroupAnchorIndex(gid)
                        and ns.TBBGroupedCount(gid) >= 2 then
                        for j, c in ipairs(t.bars or {}) do
                            if j ~= idx and ns.TBBBarGroupID(c) == gid then
                                pos[tostring(j)] = { point = point, relPoint = relPoint, x = x, y = y }
                            end
                        end
                    end
                    if not EllesmereUI._unlockActive then
                        local f = tbbFrames[idx]
                        if f then
                            f:ClearAllPoints()
                            f:SetPoint(point, UIParent, relPoint or point, x, y)
                        end
                        ns.BuildTrackedBuffBars()
                    end
                end,
                loadPos = function()
                    local pos = ns.GetTBBPositions()
                    return pos[posKey]
                end,
                clearPos = function()
                    local pos = ns.GetTBBPositions()
                    pos[posKey] = nil
                end,
                applyPos = function()
                    ns.BuildTrackedBuffBars()
                end,
            })
        end
    end

    if #elements > 0 then
        EllesmereUI:RegisterUnlockElements(elements, "EllesmereUICooldownManager")
    end
end
_G._ECME_RegisterTBBUnlock = ns.RegisterTBBUnlockElements
