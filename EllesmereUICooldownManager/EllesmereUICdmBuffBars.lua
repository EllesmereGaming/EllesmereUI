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

function ns.AddTrackedBuffBar()
    local tbb = ns.GetTrackedBuffBars()
    local source = (#tbb.bars > 0) and tbb.bars[#tbb.bars] or TBB_DEFAULT_BAR
    -- Copy settings from last bar (reset spell-specific + stack fields)
    local RESET_KEYS = {
        stacksPosition = true, stacksSize = true, stacksX = true, stacksY = true,
        stackThresholdEnabled = true, stackThreshold = true,
        stackThresholdR = true, stackThresholdG = true, stackThresholdB = true, stackThresholdA = true,
        stackThresholdMaxEnabled = true, stackThresholdMax = true, stackThresholdTicks = true,
    }
    local newBar = {}
    for k, v in pairs(TBB_DEFAULT_BAR) do
        newBar[k] = RESET_KEYS[k] and v or ((source[k] ~= nil) and source[k] or v)
    end
    newBar.spellID = 0
    newBar.name = "Bar " .. (#tbb.bars + 1)
    newBar.popularKey = nil
    newBar.spellIDs = nil
    newBar.baseSpellID = nil
    -- A new bar joins the group only if EVERY existing bar is already checked,
    -- otherwise it starts unchecked (independent). Vacuously true for the 1st bar.
    local allGrouped = true
    for _, b in ipairs(tbb.bars) do
        if not ns.TBBBarGrouped(b) then allGrouped = false; break end
    end
    newBar.grouped = allGrouped
    tbb.bars[#tbb.bars + 1] = newBar
    tbb.selectedBar = #tbb.bars

    -- Auto-position adjacent to previous bar
    local p = ECME and ECME.db and ECME.db.profile
    if p then
        local _tbbPos = ns.GetTBBPositions()
        local prevIdx = #tbb.bars - 1
        if prevIdx >= 1 then
            local prevPos = _tbbPos[tostring(prevIdx)]
            local prevCfg = tbb.bars[prevIdx]
            if prevPos and prevPos.point then
                local px, py = prevPos.x or 0, prevPos.y or 0
                if newBar.verticalOrientation then
                    local barW = (prevCfg and prevCfg.height or 24) + 4
                    _tbbPos[tostring(#tbb.bars)] = {
                        point = prevPos.point, relPoint = prevPos.relPoint or prevPos.point,
                        x = px + barW, y = py,
                    }
                else
                    local barH = (prevCfg and prevCfg.height or 24) + 4
                    _tbbPos[tostring(#tbb.bars)] = {
                        point = prevPos.point, relPoint = prevPos.relPoint or prevPos.point,
                        x = px, y = py + barH,
                    }
                end
            end
        end
    end

    ns.BuildTrackedBuffBars()
    return #tbb.bars
end

function ns.RemoveTrackedBuffBar(idx)
    local tbb = ns.GetTrackedBuffBars()
    if idx < 1 or idx > #tbb.bars then return end
    table.remove(tbb.bars, idx)
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
                    -- Match the normal "add bar" rule: join the target spec's
                    -- group only if every existing bar there is already grouped,
                    -- otherwise start independent (so we never disturb its layout).
                    local allGrouped = true
                    for _, b in ipairs(tbb.bars) do
                        if not ns.TBBBarGrouped(b) then allGrouped = false; break end
                    end
                    newBar.grouped = allGrouped
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
--  Per-bar grouping helpers
--  A bar is "grouped" (checked) when cfg.grouped ~= false (default checked).
--  All checked bars form ONE group in index order: the first ENABLED checked
--  bar is the group anchor (owns the position/mover), later checked bars chain
--  to it and share its width/height. Unchecked bars are fully independent.
-------------------------------------------------------------------------------
function ns.TBBBarGrouped(cfg)
    return cfg ~= nil and cfg.grouped ~= false
end

-- Index of the group anchor = first enabled, checked bar (or nil if none).
function ns.TBBGroupAnchorIndex()
    local t = ns.GetTrackedBuffBars()
    for i, c in ipairs(t.bars or {}) do
        if c.enabled ~= false and ns.TBBBarGrouped(c) then return i end
    end
    return nil
end

-- Count of checked bars (regardless of enabled) -- drives the grow/spacing gate.
function ns.TBBGroupedCount()
    local t = ns.GetTrackedBuffBars()
    local n = 0
    for _, c in ipairs(t.bars or {}) do
        if ns.TBBBarGrouped(c) then n = n + 1 end
    end
    return n
end


-- Runtime reflow for grouped Tracking Bars.
-- BuildTrackedBuffBars creates the static group chain, but the tick decides
-- which bars are currently visible. Reflow only the visible grouped members so
-- inactive hidden buffs do not leave holes in the chain:
--   configured order: Buff 1, Buff 2, Buff 3
--   active:           Buff 2, Buff 3        -> Buff 2 sits at group anchor
--   active:           Buff 1, Buff 2, Buff 3 -> Buff 1 sits at group anchor,
--                                              Buff 2/3 move after it
local _tbbReflow = { visible = {}, lastIdx = {}, lastCount = 0, lastGrow = nil, lastSpacing = nil }
local function ReflowVisibleGroupedTBBars(tbb, bars)
    if not (tbb and bars and tbbFrames) then return end
    -- Don't fight edit-preview (placeholder) or unlock-mode dragging: in those
    -- modes BuildTrackedBuffBars and the unlock system own bar positions.
    if ns._tbbPlaceholderMode or EllesmereUI._unlockActive then return end

    local anchorIdx = ns.TBBGroupAnchorIndex and ns.TBBGroupAnchorIndex()
    if not anchorIdx then return end

    local growDir = ((tbb.groupGrowDirection or "DOWN"):upper())
    local spacing = tbb.groupSpacing or 2

    -- Collect enabled + checked + currently visible bars in saved hierarchy
    -- order. A bar with hideWhenInactive=false is visible and therefore keeps its
    -- slot, which matches the user's choice to show inactive bars. Entry tables
    -- are pooled and reused across ticks to avoid per-frame allocation in this
    -- hot (every-16ms) path.
    local visible = _tbbReflow.visible
    local count = 0
    for i, cfg in ipairs(bars) do
        local f = tbbFrames[i]
        if cfg and cfg.enabled ~= false and ns.TBBBarGrouped(cfg)
           and f and f._tbbReady and f:IsShown() then
            count = count + 1
            local e = visible[count]
            if not e then e = {}; visible[count] = e end
            e.idx = i; e.frame = f
        end
    end

    if count == 0 then
        _tbbReflow.lastCount = 0
        return
    end

    -- Re-anchor only when the visible member sequence or the grow/spacing tuple
    -- changes. Compared element-wise so no string is allocated each tick.
    local lastIdx = _tbbReflow.lastIdx
    local changed = count ~= _tbbReflow.lastCount
        or growDir ~= _tbbReflow.lastGrow or spacing ~= _tbbReflow.lastSpacing
    if not changed then
        for n = 1, count do
            if visible[n].idx ~= lastIdx[n] then changed = true; break end
        end
    end
    if not changed then return end
    _tbbReflow.lastCount   = count
    _tbbReflow.lastGrow    = growDir
    _tbbReflow.lastSpacing = spacing
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

-- Fan a width/height change from a grouped bar out to every other grouped bar:
-- write each sibling's LOGICAL cfg.width/cfg.height (NOT the icon-inclusive total)
-- and resize its frame using that sibling's OWN icon math. Used by the options
-- sliders, unlock drag-resize, and size-MATCH (so width-matching the group anchor
-- matches the whole group). Re-entrancy guarded so a sibling write can't recurse.
local _tbbGroupSizing = false
function ns.PropagateTBBGroupSize(srcIdx, dim, value)
    if _tbbGroupSizing then return end
    local t = ns.GetTrackedBuffBars()
    local bars = t.bars
    if not bars then return end
    local src = bars[srcIdx]
    if not (src and ns.TBBBarGrouped(src)) then return end
    _tbbGroupSizing = true
    for i, c in ipairs(bars) do
        if i ~= srcIdx and ns.TBBBarGrouped(c) then
            c[dim] = value
            local f = tbbFrames[i]
            if f then
                local hasIcon = (c.iconDisplay or "none") ~= "none"
                local isVert = c.verticalOrientation
                if dim == "width" then
                    f:SetWidth(hasIcon and not isVert and (value + (c.height or 24)) or value)
                else
                    f:SetHeight(hasIcon and isVert and (value + (c.width or 270)) or value)
                end
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
    for i, v in ipairs(vals) do
        if v <= maxStacks then
            local t = tickCache[i]
            local frac = v / maxStacks
            t:ClearAllPoints()
            if isVert then
                local off = PP and PP.Scale(barH * frac) or (barH * frac)
                t:SetSize(barW, onePx)
                t:SetPoint("BOTTOMLEFT", sb, "BOTTOMLEFT", 0, off)
            else
                local off = PP and PP.Scale(barW * frac) or (barW * frac)
                t:SetSize(onePx, barH)
                t:SetPoint("TOPLEFT", sb, "TOPLEFT", off, 0)
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

    -- width/height are always visual dimensions (what you see on screen).
    -- Horizontal: width = long side, height = short side.
    -- Vertical: width = short side, height = long side.
    local PPt = EllesmereUI and EllesmereUI.PP
    local snap = PPt and PPt.Snap or function(v) return v end
    local w = snap(cfg.width or 200)
    local h = snap(cfg.height or 24)
    local isVert = cfg.verticalOrientation
    bar._lastVertical = isVert
    local iconMode = cfg.iconDisplay or "none"
    local hasIcon = iconMode ~= "none"
    local iSize = isVert and w or h

    -- Size wrapFrame: always width x height as stored, snapped to pixel grid
    if isVert then
        bar:SetSize(w, hasIcon and (h + iSize) or h)
    else
        bar:SetSize(hasIcon and (w + iSize) or w, h)
    end

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

    -- Timer text
    local timerPos = cfg.timerPosition or (cfg.showTimer and "right" or "none")
    if timerPos ~= "none" then
        bar._timerText:Show()
        SetFont(bar._timerText, cfg.timerSize or 11)
        bar._timerText:ClearAllPoints()
        local tX, tY = cfg.timerX or 0, cfg.timerY or 0
        if isVert then
            bar._timerText:SetPoint("TOP", sb, "TOP", tX, -8 + tY)
            bar._timerText:SetJustifyH("CENTER")
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

    -- Spark
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
            bar._spark:SetPoint("CENTER", sparkAnchor, "TOP", 0, 0)
        else
            -- 1px left so the spark sits over the fill edge, not past it.
            bar._spark:SetPoint("CENTER", sparkAnchor, "RIGHT", -1, 0)
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
        bar._nameText:SetWidth(w - 12 - (cfg.showTimer and 50 or 0))
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
function ns.GetTrackedBarSpells()
    local result = {}
    local viewer = _G["BuffBarCooldownViewer"]
    if not viewer or not viewer.itemFramePool then return result end
    local GetCanonical = ns.GetCanonicalSpellIDForFrame

    local seen = {}
    for frame in viewer.itemFramePool:EnumerateActive() do
        if frame:IsShown() or frame.cooldownInfo then
            local sid = GetCanonical and GetCanonical(frame)
            if sid and sid > 0 and not seen[sid] then
                seen[sid] = true
                local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(sid)
                -- Append subtext (e.g. "Solar", "Lunar") to disambiguate
                -- spells that share a base name like Eclipse.
                if name and C_Spell.GetSpellSubtext then
                    local sub = C_Spell.GetSpellSubtext(sid)
                    if sub and sub ~= "" then
                        name = name .. " (" .. sub .. ")"
                    end
                end
                local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid)
                result[#result + 1] = {
                    spellID     = sid,
                    cdID        = frame.cooldownID,
                    name        = name or ("Spell " .. sid),
                    icon        = icon,
                    layoutIndex = frame.layoutIndex or 0,
                }
            end
        end
    end

    table.sort(result, function(a, b)
        if a.layoutIndex ~= b.layoutIndex then return a.layoutIndex < b.layoutIndex end
        return (a.name or "") < (b.name or "")
    end)
    return result
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
    -- Sibling preset listener, refreshed from the same buff/TBB change sites
    -- (every add/remove/rebuild path already calls UpdateLustListener).
    if ns.UpdateTimeSpiralListener then ns.UpdateTimeSpiralListener() end
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
                    bar._lastVertical and "TOP" or "RIGHT",
                    bar._lastVertical and 0 or -1, 0)
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

    local tbb = ns.GetTrackedBuffBars()
    local bars = tbb.bars
    local _tbbPos = ns.GetTBBPositions()
    if _tbbReflow then _tbbReflow.lastCount = 0 end

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
    local lastGroupedBar  -- tracks previous enabled bar for grouped anchoring
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

            -- Saved position / grouping. Only CHECKED (cfg.grouped) bars chain;
            -- the first checked bar takes the independent branch (its own saved
            -- pos) and becomes the anchor, later checked bars chain to it.
            -- Unchecked bars always fall to the independent branch.
            local barGrouped = ns.TBBBarGrouped(cfg)
            if barGrouped and lastGroupedBar then
                -- Grouped: position relative to previous grouped bar
                local growDir = (tbb.groupGrowDirection or "DOWN"):upper()
                local spacing = tbb.groupSpacing or 2
                bar:ClearAllPoints()
                if growDir == "DOWN" then
                    bar:SetPoint("TOP", lastGroupedBar, "BOTTOM", 0, -spacing)
                elseif growDir == "UP" then
                    bar:SetPoint("BOTTOM", lastGroupedBar, "TOP", 0, spacing)
                elseif growDir == "RIGHT" then
                    bar:SetPoint("LEFT", lastGroupedBar, "RIGHT", spacing, 0)
                elseif growDir == "LEFT" then
                    bar:SetPoint("RIGHT", lastGroupedBar, "LEFT", -spacing, 0)
                end
            else
                -- Independent positioning (bar 1 always, or grouping disabled)
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

            if barGrouped then lastGroupedBar = bar end
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

    -- Group anchor (first enabled checked bar) owns the group mover; the other
    -- checked members hide theirs. Computed per build so it tracks checkbox edits.
    local anchorIdx = ns.TBBGroupAnchorIndex()
    local groupedCount = ns.TBBGroupedCount()
    local elements = {}
    for i, cfg in ipairs(bars) do
        local idx = i
        local posKey = tostring(idx)
        local bar = tbbFrames[idx]
        if bar then
            elements[#elements + 1] = MK({
                key   = "TBB_" .. posKey,
                label = (idx == anchorIdx and groupedCount >= 2)
                    and "Tracking Bar Group"
                    or ("Tracking Bar: " .. (cfg.name or ("Bar " .. idx))),
                group = "Cooldown Manager",
                order = 650,
                noAnchorTarget = true,
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
                    -- Unchecked bars always show their own mover.
                    if not ns.TBBBarGrouped(c) then return false end
                    -- Checked bars: only the group anchor shows a mover (it moves
                    -- the whole group). Hide every other checked member -- enabled
                    -- OR disabled (a disabled member re-enables straight into the
                    -- chain, so its own mover would be a phantom). When no checked
                    -- bar is enabled the anchor is nil and all are hidden.
                    return idx ~= ns.TBBGroupAnchorIndex()
                end,
                -- Grouped non-anchor members are positioned by the relative
                -- SetPoint chain in BuildTrackedBuffBars. Report them as
                -- addon-owned so the generic anchor system never repositions
                -- them -- otherwise a cascade/override SetPoint severs the chain
                -- (e.g. in combat via a stale per-member anchor link). The group
                -- ANCHOR returns false, so it stays fully element-anchorable.
                isAnchored = function()
                    local t = ns.GetTrackedBuffBars()
                    local b = t and t.bars
                    local c = b and b[idx]
                    if not c or not ns.TBBBarGrouped(c) then return false end
                    return idx ~= ns.TBBGroupAnchorIndex()
                end,
                getFrame = function() return tbbFrames[idx] end,
                getSize  = function()
                    -- Return total frame size (including icon) so width-
                    -- matching reads the actual rendered dimensions.
                    local t = ns.GetTrackedBuffBars()
                    local c = t.bars and t.bars[idx]
                    local PPg = EllesmereUI and EllesmereUI.PP
                    local sn = PPg and PPg.Snap or function(v) return v end
                    if c then
                        local w = sn(c.width or 270)
                        local h = sn(c.height or 24)
                        local hasIcon = (c.iconDisplay or "none") ~= "none"
                        local isVert = c.verticalOrientation
                        if hasIcon then
                            if isVert then h = h + w else w = w + h end
                        end
                        return w, h
                    end
                    return 270, 24
                end,
                setWidth = function(_, w)
                    local t = ns.GetTrackedBuffBars()
                    local c = t.bars and t.bars[idx]
                    if not c then return end
                    local iconMode = c.iconDisplay or "none"
                    local hasIcon = iconMode ~= "none"
                    local isVert = c.verticalOrientation
                    if hasIcon and not isVert then
                        w = w - (c.height or 24)
                    end
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
                    if f then
                        local totalW = hasIcon and not isVert and (w + (c.height or 24)) or w
                        f:SetWidth(totalW)
                    end
                end,
                setHeight = function(_, h)
                    local t = ns.GetTrackedBuffBars()
                    local c = t.bars and t.bars[idx]
                    if not c then return end
                    local iconMode = c.iconDisplay or "none"
                    local hasIcon = iconMode ~= "none"
                    local isVert = c.verticalOrientation
                    if hasIcon and isVert then
                        h = h - (c.width or 200)
                    end
                    local PPt = EllesmereUI and EllesmereUI.PP
                    h = PPt and PPt.Snap(h) or math.floor(h + 0.5)
                    local f = tbbFrames[idx]
                    -- Persist during unlock AND match propagation (see setWidth).
                    if EllesmereUI._unlockActive or EllesmereUI._propagatingMatch then
                        c.height = h
                        ns.PropagateTBBGroupSize(idx, "height", h)
                    end
                    if f then
                        local totalH = hasIcon and isVert and (h + (c.width or 200)) or h
                        f:SetHeight(totalH)
                    end
                end,
                savePos = function(_, point, relPoint, x, y)
                    local pos = ns.GetTBBPositions()
                    pos[posKey] = { point = point, relPoint = relPoint, x = x, y = y }
                    -- The group is dragged via the anchor's mover, but its saved
                    -- position is keyed by the anchor's INDEX. If the anchor later
                    -- changes (the first checked bar is unchecked or disabled) the
                    -- new anchor would read a stale per-index coordinate and the
                    -- group would teleport. Mirror the group origin into every
                    -- checked member's key so whichever bar becomes the anchor
                    -- reads the current position.
                    if idx == ns.TBBGroupAnchorIndex() and ns.TBBGroupedCount() >= 2 then
                        local t = ns.GetTrackedBuffBars()
                        for j, c in ipairs(t.bars or {}) do
                            if j ~= idx and ns.TBBBarGrouped(c) then
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

