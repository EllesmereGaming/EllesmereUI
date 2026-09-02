if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  EllesmereUICdmBuffBars.lua
--  Tracking Bars: StatusBar reskins driven entirely by Blizzard CDM children.
--  Tracked spells must be assigned to a CDM bar so Blizzard computes all
--  active-state, duration and stack data. Zero independent aura calls.
--------------------------------------------------------------------------------
local _, ns = ...

local ceil    = math.ceil
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
-- True while any bar uses a Visibility mode/option, i.e. a state no tick-side aura or
-- cooldown edge can reveal. Gates the dispatcher wake below so profiles that never touch
-- Visibility keep the idle sleeper's original wake set.
local _anyVisCond   = false

-- Glow helpers (from main CDM file)
local function StartGlow(...) if ns.StartNativeGlow then return ns.StartNativeGlow(...) end end
local function StopGlow(...)  if ns.StopNativeGlow  then return ns.StopNativeGlow(...)  end end

-- Weak-keyed external store for Blizzard bar FontString refs: never write custom properties onto Blizzard StatusBar frames (taint).
local _blizzBarFS = setmetatable({}, { __mode = "k" })
local function BBFS(bar)
    local d = _blizzBarFS[bar]
    if not d then d = {}; _blizzBarFS[bar] = d end
    return d
end

-------------------------------------------------------------------------------
--  Textures
-------------------------------------------------------------------------------
local TBB_TEXTURES, TBB_TEXTURE_NAMES, TBB_TEXTURE_ORDER =
    EllesmereUI.BuildBarTextureTables()
ns.TBB_TEXTURES      = TBB_TEXTURES
ns.TBB_TEXTURE_ORDER = TBB_TEXTURE_ORDER
ns.TBB_TEXTURE_NAMES = TBB_TEXTURE_NAMES

-------------------------------------------------------------------------------
--  Shared Helpers
-------------------------------------------------------------------------------
local function FormatTime(remaining)
    -- Whole SECONDS use ceil to match Blizzard's aura timers (16.5s reads "17"); flooring
    -- showed every buff one second low. Minutes/hours stay floor (unverified); sub-10s keeps tenths.
    if remaining >= 3600 then return format("%dh", floor(remaining / 3600)) end
    if remaining >= 60   then return format("%dm", floor(remaining / 60))   end
    if remaining >= 10   then return format("%d",  ceil(remaining))         end
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

local function SetTBBTextColor(fs, cfg, prefix)
    if not fs or not cfg then return end
    local r = cfg[prefix .. "TextR"]
    local g = cfg[prefix .. "TextG"]
    local b = cfg[prefix .. "TextB"]
    local a = cfg[prefix .. "TextA"]
    if r == nil then r = 1 end
    if g == nil then g = 1 end
    if b == nil then b = 1 end
    if a == nil then a = 0.9 end
    fs:SetTextColor(r, g, b, a)
end

-------------------------------------------------------------------------------
--  Pandemic state via Blizzard hooks
-------------------------------------------------------------------------------
local _pandemicState  = {}   -- frame -> true when in pandemic
local _pandemicHooked = {}   -- frame -> true once hooks are installed
ns._pandemicState = _pandemicState
ns._pandemicHooked = _pandemicHooked

-- Hook bodies live at FILE SCOPE on purpose: hooksecurefunc callbacks bill CPU to the
-- addon whose execution context CREATED the closure (same rule as frames); a login-installed
-- inline closure here would bill the PARENT addon ~0.05% per pandemic repaint instead. Born in
-- this file's main chunk, they bill CooldownManager no matter which path installs them.
local function _PandemicShow(self)
    _pandemicState[self] = true
    ns._btDirty = true
    if ns.ArmBuffTicker then ns.ArmBuffTicker() end
    -- Hide Blizzard's PandemicIcon unless "Blizzard Default" (-1). Custom glow styles (>0) replace it; None (0/false) suppresses it.
    local fc = ns._ecmeFC and ns._ecmeFC[self]
    local bk = fc and fc.barKey
    if bk then
        local bd = ns.barDataByKey and ns.barDataByKey[bk]
        local style = bd and bd.pandemicGlow and bd.pandemicGlowStyle
        if not style or style ~= -1 then
            if self.PandemicIcon then self.PandemicIcon:Hide() end
        end
    end
end

local function _PandemicHide(self)
    _pandemicState[self] = nil
    ns._btDirty = true
    if ns.ArmBuffTicker then ns.ArmBuffTicker() end
end

-- Installed LAZILY from the buff tick, per icon, only when that icon's bar uses a
-- custom pandemic style (style ~= -1); idempotent. Default "Blizzard Default" hooks nothing, costs zero.
function ns.HookPandemicState(frame)
    if not frame or _pandemicHooked[frame] then return end
    if not frame.ShowPandemicStateFrame then return end
    _pandemicHooked[frame] = true
    hooksecurefunc(frame, "ShowPandemicStateFrame", _PandemicShow)
    if frame.HidePandemicStateFrame then
        hooksecurefunc(frame, "HidePandemicStateFrame", _PandemicHide)
    end
end

local PANDEMIC_THRESHOLD = 0.3
local LIFEBLOOM_SPELL_ID = 33763
local _lbName               -- cached Lifebloom spell name (resolved lazily once)
local _scanLast, _scanResult = 0, false
-- Pandemic fallback for auras Blizzard never flags (currently only Lifebloom).
-- bar._isLifebloom is cached on our own frame; the call site skips entirely once a
-- bar is known not to be Lifebloom, so only Lifebloom reaches the throttled scan.
local function LifebloomPandemic(bar, blzChild)
    -- Resolve identity once. Spell data can be late-loading, so leave the flag nil (retry next frame) until both names resolve.
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
    onlyInCombat = false,     -- keep the bar hidden entirely while out of combat
    barVisibility = "always", -- CDM-Bars-style visibility mode (always/in_combat/in_raid/.../multi-select)
    visOnlyInstances = false,
    visHideHousing = false,
    visHideMounted = false,
    visHideDragonriding = false,
    visHideNoTarget = false,
    visHideNoEnemy = false,
    grouped   = true,   -- per-bar "Group Tracking Bars" checkbox; checked bars chain + share width/height
    height    = 24,
    width     = 270,
    verticalOrientation = false,
    reverseFill = false,
    fillUp = false,          -- cooldown bars only: fill as the cooldown recovers
    chargeHashLines = false,
    chargeHashLineWidth = 2,
    chargeHashLineR = 0, chargeHashLineG = 0,
    chargeHashLineB = 0, chargeHashLineA = 1,
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
    timerTextR = 1, timerTextG = 1, timerTextB = 1, timerTextA = 0.9,
    showName  = true,
    namePosition = "left",
    nameSize  = 11,
    nameX = 0, nameY = 0,
    nameTextR = 1, nameTextG = 1, nameTextB = 1, nameTextA = 0.9,
    showSpark = true,
    iconDisplay = "none",
    iconSize    = 24,
    iconX = 0, iconY = 0,
    iconBorderSize = 0,
    stacksPosition = "center",
    stacksSize     = 11,
    stacksX = 0, stacksY = 0,
    stacksTextR = 1, stacksTextG = 1, stacksTextB = 1, stacksTextA = 0.9,
    stackThresholdEnabled = false,
    stackThreshold = 5,
    stackThresholdR = 0.8, stackThresholdG = 0.1, stackThresholdB = 0.1, stackThresholdA = 1,
    -- Multi-threshold opt-in: cfg.stackThresholds is created lazily by the options
    -- editor (a table here would leak BY REFERENCE across every bar via AddTrackedBuffBarCore's shallow copy).
    stackThresholdMulti = false,
    stackThresholdMaxEnabled = false,
    stackThresholdMax = 10,
    stackThresholdTicks = "",
    stackThresholdTickR = 1, stackThresholdTickG = 1,
    stackThresholdTickB = 1, stackThresholdTickA = 1,
    stackBasedBar = false,
    pandemicGlow = true,
    pandemicGlowStyle = -1,
    pandemicGlowLines = 8,
    pandemicGlowThickness = 2,
    pandemicGlowSpeed = 4,
}
ns.TBB_DEFAULT_BAR = TBB_DEFAULT_BAR

-------------------------------------------------------------------------------
--  Data Access
-------------------------------------------------------------------------------
function ns.GetTrackedBuffBars()
    -- TBB is spec-specific and per-profile: specProfiles[specKey] under the active profile's bucket.
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
    -- Live migration: single tbb.groupEnabled toggle -> per-bar `grouped` (ENABLED = every
    -- bar checked, DISABLED/never-set = unchecked). TBB is per-spec/per-profile so there is
    -- no SavedVariables pass; this read-time convert is flag-guarded idempotent, and the
    -- legacy boolean is cleared so later per-bar edits are never stomped.
    if not tbb._groupMigrated then
        local checked = (tbb.groupEnabled == true)
        for _, b in ipairs(tbb.bars or {}) do b.grouped = checked end
        tbb.groupEnabled = nil
        tbb._groupMigrated = true
    end
    -- Live migration: width/height are the TOTAL footprint (icon included). Legacy bars
    -- stored the FILL size with the icon square extra on top, so fold that square in once
    -- (rendered pixels are identical: old fill+icon = new total). Read-time, flag-idempotent;
    -- imported old profiles lack the flag and convert on first read.
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
    -- Live migration: pandemicGlowMode derived from a non-default legacy pandemicGlowColor (which was always set).
    if not tbb._pandemicModeMigrated then
        for _, b in ipairs(tbb.bars or {}) do
            if not b.pandemicGlowMode then
                local c = b.pandemicGlowColor
                if c and not (c.r == 1 and c.g == 1 and c.b == 0) then
                    b.pandemicGlowMode = "custom"
                else
                    b.pandemicGlowMode = "default"
                end
            end
        end
        tbb._pandemicModeMigrated = true
    end
    -- Live migration: standalone onlyInCombat=true folds into the new barVisibility mode
    -- dropdown (Visibility -> In Combat) so the effective setting is unchanged. Cleared
    -- after folding in so the Visibility Options checkbox does not show it doubly checked;
    -- hideWhenInactive needs no migration, it already reads/writes the same field the new
    -- Visibility Options checkbox uses.
    if not tbb._visMigrated then
        for _, b in ipairs(tbb.bars or {}) do
            if b.onlyInCombat and (not b.barVisibility or b.barVisibility == "always") then
                b.barVisibility = "in_combat"
                b.onlyInCombat = false
            end
        end
        tbb._visMigrated = true
    end
    return tbb
end

function ns.GetTBBPositions()
    -- Spec-specific, stored alongside trackedBuffBars in the active profile's per-spec bucket.
    local specKey = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
    if not specKey then return {} end
    local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
    if not sp or not sp[specKey] then return {} end
    local prof = sp[specKey]
    if not prof.tbbPositions then prof.tbbPositions = {} end
    return prof.tbbPositions
end

-------------------------------------------------------------------------------
--  Per-spec unlock-link views (anchor / width-match / height-match entries)
--
--  Unlock links are stored account-globally by element key, but TBB keys by
--  BAR INDEX ("TBB_1") while bar lists are per-spec -- a raw global entry
--  would glue bar 1 of every spec to one link. Fix: each (profile, spec)
--  keeps its own copy of the TBB child-role entries in a bucket next to
--  tbbPositions. The global stores hold exactly ONE spec's entries -- the
--  "owner", stamped in EllesmereUIDB._tbbLinkOwner -- maintained by
--  SyncTBBUnlockLinks: owner==active banks live->bucket (live stores are
--  that spec's working truth); owner~=active banks the old owner then swaps
--  the active spec's bucket in; force (profile restore replaced the stores
--  wholesale) swaps in only, NEVER banks -- live entries no longer belong to
--  the stamped owner. A spec's first-ever view seeds from live entries,
--  keeping only slots with a bar on that spec.
--
--  Entries where a TBB bar is the TARGET stay under the child's key
--  untouched ("follow whatever bar 1 is on this spec"); the fallback-anchor
--  system covers an empty slot.
-------------------------------------------------------------------------------
do
    local function CopyEntry(v)
        if type(v) ~= "table" then return v end
        local t = {}
        for k, x in pairs(v) do
            t[k] = type(x) == "table" and CopyEntry(x) or x
        end
        return t
    end

    local function LiveStores(create)
        local db = EllesmereUIDB
        if not db then return nil end
        if create then
            db.unlockAnchors     = db.unlockAnchors     or {}
            db.unlockWidthMatch  = db.unlockWidthMatch  or {}
            db.unlockHeightMatch = db.unlockHeightMatch or {}
        end
        return db.unlockAnchors, db.unlockWidthMatch, db.unlockHeightMatch
    end

    local function Bucket(profileName, specKey, create)
        if not profileName or not specKey then return nil end
        local sp = ns.GetSpecProfilesForProfile and ns.GetSpecProfilesForProfile(profileName)
        if not sp then return nil end
        local prof = sp[specKey]
        if not prof then
            if not create then return nil end
            prof = { barSpells = {} }
            sp[specKey] = prof
        end
        if not prof.tbbUnlockLinks and create then
            prof.tbbUnlockLinks = { anchors = {}, wm = {}, hm = {} }
        end
        return prof.tbbUnlockLinks
    end

    -- Copy a live store's TBB child entries into a bucket table (slot-keyed).
    local function BankOne(store, dest)
        wipe(dest)
        if not store then return end
        for k, v in pairs(store) do
            if type(k) == "string" then
                local slot = k:match("^TBB_(%d+)$")
                if slot then dest[slot] = CopyEntry(v) end
            end
        end
    end

    local function Bank(profileName, specKey)
        local b = Bucket(profileName, specKey, true)
        if not b then return end
        local an, wm, hm = LiveStores(false)
        BankOne(an, b.anchors)
        BankOne(wm, b.wm)
        BankOne(hm, b.hm)
    end

    -- Replace a live store's TBB child entries with a bucket table's.
    local function SwapOne(store, src)
        local kill
        for k in pairs(store) do
            if type(k) == "string" and k:match("^TBB_%d+$") then
                kill = kill or {}
                kill[#kill + 1] = k
            end
        end
        if kill then
            for _, k in ipairs(kill) do store[k] = nil end
        end
        for slot, v in pairs(src) do
            store["TBB_" .. slot] = CopyEntry(v)
        end
    end

    local function SwapIn(profileName, specKey)
        local an, wm, hm = LiveStores(true)
        if not an then return end
        local b = Bucket(profileName, specKey, false)
        if not b then
            b = Bucket(profileName, specKey, true)
            if not b then return end
            -- First view for this spec: seed from live entries, keeping only slots that have a bar here.
            BankOne(an, b.anchors)
            BankOne(wm, b.wm)
            BankOne(hm, b.hm)
            local t = ns.GetTrackedBuffBars and ns.GetTrackedBuffBars()
            local bars = (t and t.bars) or {}
            local sets = { b.anchors, b.wm, b.hm }
            for i = 1, 3 do
                local set, drop = sets[i], nil
                for slot in pairs(set) do
                    if not bars[tonumber(slot)] then
                        drop = drop or {}
                        drop[#drop + 1] = slot
                    end
                end
                if drop then
                    for _, slot in ipairs(drop) do set[slot] = nil end
                end
            end
        end
        SwapOne(an, b.anchors)
        SwapOne(wm, b.wm)
        SwapOne(hm, b.hm)
        -- Modules memoize views over the anchor DB (extent watch etc.).
        EllesmereUI._anchorLinksStamp = (EllesmereUI._anchorLinksStamp or 0) + 1
    end

    function ns.SyncTBBUnlockLinks(force)
        if not EllesmereUIDB then return end
        local profName = ns.GetActiveProfileName and ns.GetActiveProfileName()
        local specKey  = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
        if not profName or not specKey then return end
        local own  = EllesmereUIDB._tbbLinkOwner
        local same = own and own.profile == profName and own.spec == specKey
        if force then
            SwapIn(profName, specKey)
        elseif same then
            Bank(profName, specKey)
            return
        else
            if own then Bank(own.profile, own.spec) end
            SwapIn(profName, specKey)
        end
        EllesmereUIDB._tbbLinkOwner = { profile = profName, spec = specKey }
    end

    -- Called by profile-restore choke points right after they replace the live unlock
    -- stores wholesale from an unlockLayout snapshot: the snapshot's TBB entries are stale
    -- copies of whichever spec last saved unlock mode, so the active spec's own entries are re-asserted here.
    EllesmereUI._TBBRestoreUnlockLinks = function()
        ns.SyncTBBUnlockLinks(true)
    end
end

-- Create a new bar config (no rebuild). `targetGid`: nil = follow the last
-- bar's group (quick-add default), 0 = independent, N = that group. Style
-- comes from the group's style source so the bar lands looking like its
-- group; independent bars copy the last bar. Spell identity and stack fields
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

    -- Style priority: 1) preset on a bar already in the target group, 2) the target
    -- group's current look (style source bar), 3) a preset on any bar of this spec
    -- else any saved preset, 4) the last bar's look (legacy inherit), 5) defaults.
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

    -- Base from pure defaults (spell identity, enable state and stack-threshold numbers
    -- start fresh), then dress it: the style key set is the authoritative visual copy.
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
    newBar.trackType = nil
    newBar.enabled = true
    ns.TBBSetBarGroup(newBar, gid)
    bars[#bars + 1] = newBar
    tbb.selectedBar = #bars

    -- Vertical bars read better side by side: when a vertical bar FOUNDS a group whose grow direction was never chosen, default it to RIGHT rather than the global DOWN.
    if gid ~= 0 and newBar.verticalOrientation and ns.TBBGroupedCount(gid) <= 1 then
        local g = tbb.groups and tbb.groups[tostring(gid)]
        local hasStored = (g and g.grow) or (gid == 1 and tbb.groupGrowDirection)
        if not hasStored then
            ns.TBBSetGroupGrow(gid, "RIGHT")
        end
    end

    -- Auto-position adjacent to the previous bar; matters only for independent bars (grouped bars chain off their group anchor).
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
                    -- Step sideways by the previous bar's on-screen width (width/height are always VISUAL dimensions).
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
    -- Positions are keyed by bar index: re-key so bars after the removed index keep their coordinates.
    local pos = ns.GetTBBPositions()
    for j = idx, oldCount - 1 do
        pos[tostring(j)] = pos[tostring(j + 1)]
    end
    pos[tostring(oldCount)] = nil
    -- Re-key element-anchor / size-match links the same way (TBB_3 -> TBB_2) so anchors
    -- keep tracking the same visual bar; links pointing AT the deleted bar are severed.
    if EllesmereUI and EllesmereUI.ShiftIndexedAnchorKeys then
        EllesmereUI.ShiftIndexedAnchorKeys("TBB_", idx, oldCount)
    end
    if tbb.selectedBar > #tbb.bars then tbb.selectedBar = max(1, #tbb.bars) end
    ns.BuildTrackedBuffBars()
end

-- Stable identity for the broadcast toggle and the single source of truth for whether a
-- bar can broadcast across specs: only when it targets a spec-agnostic buff -- a preset
-- (popularKey, keyed "p:<key>") or a custom buff ID (keyed "s:<spellID>"). A Blizzard
-- CDM tracked spell is spec/class- specific and must NEVER be broadcastable; it's told
-- apart from a custom buff by having NO customDuration (custom-buff popup always sets
-- one, CDM picker clears it). Freshly-added empty bars return nil.
function ns.TBBBroadcastKey(cfg)
    if type(cfg) ~= "table" then return nil end
    if cfg.popularKey and cfg.popularKey ~= "" then return "p:" .. cfg.popularKey end
    if cfg.spellID and cfg.spellID > 0
       and type(cfg.customDuration) == "number" and cfg.customDuration > 0 then
        return "s:" .. tostring(cfg.spellID)
    end
    return nil
end

-- Broadcastable only when TBBBroadcastKey yields an identity (preset or custom buff); Blizzard CDM spells and empty bars are excluded.
function ns.IsTrackedBuffBarBroadcastable(cfg)
    return ns.TBBBroadcastKey(cfg) ~= nil
end

-- True when the bar's buff is marked broadcast to all specs (button reads "Remove Bar from All Specs"). Read from the persistent per-profile set.
function ns.IsTrackedBuffBarBroadcast(cfg)
    local key = ns.TBBBroadcastKey(cfg)
    if not key then return false end
    local set = ns.GetActiveTBBBroadcastSet and ns.GetActiveTBBBroadcastSet()
    return set ~= nil and set[key] == true
end

-- Copy a configured bar (preset or custom buff) into every OTHER spec of the player's
-- class; config and position are deep-copied so it appears identically everywhere.
-- Specs already holding it are skipped, so repeated clicks never pile up duplicates.
-- Returns the number of specs added to.
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
            -- A cooldown-tracking bar is never the same bar as a buff bar for the same spell: track types must match first.
            if (b.trackType or "buff") == (srcBar.trackType or "buff") then
                if srcBar.popularKey and srcBar.popularKey ~= "" then
                    if b.popularKey == srcBar.popularKey then return true end
                elseif (not b.popularKey or b.popularKey == "")
                       and b.spellID and b.spellID == srcBar.spellID then
                    return true
                end
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
                    -- Join the target spec's group only when its bars all live in ONE
                    -- group (mirrors quick-add); otherwise start independent so its layout
                    -- stays undisturbed. Empty spec starts the bar in group 1.
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

    -- Mark broadcast so the button flips to "Remove..." in every spec; set even when added == 0 (all specs already held it).
    local set = ns.GetActiveTBBBroadcastSet and ns.GetActiveTBBBroadcastSet()
    if set then
        local key = ns.TBBBroadcastKey(srcBar)
        if key then set[key] = true end
    end

    return added
end

-- Inverse of AddBarToAllSpecs: remove the bar's buff from every OTHER spec and clear the
-- broadcast flag. The CURRENT spec's bar is left untouched. Returns specs removed from.
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
        -- Track types must match: a broadcast buff bar for spell X must NEVER delete a cooldown-tracking bar for the same spell.
        if (b.trackType or "buff") ~= (srcBar.trackType or "buff") then
            return false
        end
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
                    -- Rebuild excluding matches, re-keying positions so compacted indices and
                    -- tbbPositions stay aligned (plain table.remove would strand stale indices).
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
-- Assignment memo gate: cfg->frame pairing changes only on viewer pool composition
-- edges (aura events, pool Acquire, rebuilds, spec/cache invalidation); the tick
-- reuses the last pairing until dirtied. Starts dirty so the first tick always pairs.
local _tbbAssignDirty = true
local _tbbAssignedFor

-- Group reflow gate: ReflowGroup's inputs are the visible member sequence plus the
-- group's grow direction and spacing. Bar frames dirty this from their OnShow/OnHide,
-- the group setting writers, rebuilds and wakes dirty it directly, and the tick
-- reflows only while it is set instead of re-walking every bar every 16 ms.
local _tbbReflowDirty = true
local function _MarkTBBReflowDirty() _tbbReflowDirty = true end

-- Smooth-fill switch memo for the tick: GetTBBSmoothSettings walks the profile store,
-- and its result can only change with the active profile name or the live spec-profile bucket, both re-read per tick without a call.
local _tickSm, _tickSmProf, _tickSmSp

-- TBB idle sleeper: UpdateTrackedBuffBarTimers counts consecutive dead ticks (no
-- active/fallback aura, self-timed window, running cooldown, or placeholder preview);
-- after ~2s it parks the tick frame (OnUpdate stops) and this frame listens for the
-- cheap edges that revive it. Lust from other players and the Time Spiral glow arm
-- outside these events, so their arm sites call Wake directly instead.
local _tbbWake = CreateFrame("Frame")
_tbbWake._idleTicks = 0
function _tbbWake.Sleep()
    if tbbTickFrame then tbbTickFrame:Hide() end
    -- NEVER register SPELL_UPDATE_COOLDOWN here: it fires steadily at idle and would defeat
    -- the sleep. A tracked cooldown can only START via a player cast (item/shapeshift
    -- included), covered by the cast event; a RUNNING cooldown keeps the tick awake by liveness.
    _tbbWake:RegisterUnitEvent("UNIT_AURA", "player")
    _tbbWake:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    _tbbWake:RegisterEvent("PLAYER_REGEN_DISABLED")
end
function _tbbWake.Wake()
    _tbbWake:UnregisterAllEvents()
    -- Stay subscribed to the aura edge while AWAKE: pool composition changes only on a
    -- player aura event or a pool Acquire (hooked separately), retiring the assignment memo.
    _tbbWake:RegisterUnitEvent("UNIT_AURA", "player")
    _tbbWake._idleTicks = 0
    _tbbAssignDirty = true
    _tbbReflowDirty = true
    if _tbbWake._enabled and tbbTickFrame then tbbTickFrame:Show() end
end
-- UNIT_AURA fires steadily in group content and every false wake buys ~0.5s of full
-- ticking, so this probe answers "could any bar be live?" WITHOUT waking: an active
-- viewer frame, or a live player aura for a fallback-class config. Casts and combat
-- entry skip the probe (rare at idle; the legitimate start edges the probe can't see).
function _tbbWake.Probe()
    if ns._tbbPlaceholderMode then return true end
    local viewer = _G["BuffBarCooldownViewer"]
    if viewer and viewer.itemFramePool then
        for frame in viewer.itemFramePool:EnumerateActive() do
            if frame.IsActive and frame:IsActive() then return true end
        end
    end
    if not (ECME and ECME.db) then return true end
    local tbb = ns.GetTrackedBuffBars and ns.GetTrackedBuffBars()
    local bars = tbb and tbb.bars
    if bars and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        for _, cfg in ipairs(bars) do
            if cfg.enabled ~= false and not cfg.spellIDs and not cfg.popularKey
               and cfg.trackType ~= "cooldown"
               and cfg.spellID and cfg.spellID > 0 then
                if C_UnitAuras.GetPlayerAuraBySpellID(cfg.spellID)
                   or (cfg.baseSpellID and cfg.baseSpellID > 0
                       and C_UnitAuras.GetPlayerAuraBySpellID(cfg.baseSpellID)) then
                    return true
                end
            end
        end
    end
    return false
end
function _tbbWake.OnEvent(_, event)
    -- Awake: this is the composition edge that retires the assignment memo. Mark and let the next tick re-pair; no probe, no state change.
    if tbbTickFrame and tbbTickFrame:IsShown() then
        _tbbAssignDirty = true
        return
    end
    if event == "UNIT_AURA" and not _tbbWake.Probe() then return end
    _tbbWake.Wake()
end
_tbbWake:SetScript("OnEvent", _tbbWake.OnEvent)
ns.WakeTBBTick = _tbbWake.Wake

-- The Visibility edges (mount, shapeshift, gliding, target, group, zone, combat) are exactly
-- the set the shared dispatcher already owns, so subscribe there instead of re-registering
-- them on the sleeper. Without this a parked tick never learns that a Visibility condition
-- flipped: a bar hidden while mounted stays hidden past the dismount until some unrelated
-- aura or cast happens to wake it, and the dragonriding modes never fire at all because
-- takeoff/landing is not in the sleeper's wake set.
if EllesmereUI.RegisterVisibilityUpdater then
    EllesmereUI.RegisterVisibilityUpdater(function()
        -- Only a parked tick needs the nudge; an awake one re-evaluates every frame anyway.
        if _anyVisCond and _tbbWake._enabled
           and tbbTickFrame and not tbbTickFrame:IsShown() then
            _tbbWake.Wake()
        end
    end)
end

function ns.GetTBBFrame(idx) return tbbFrames[idx] end

-------------------------------------------------------------------------------
--  Bar grouping helpers (multi-group)
--  Membership: per-bar numeric cfg.groupId (0 = independent). Legacy bars carry only
--  the boolean cfg.grouped, read as a VIEW (true/default = group 1, false =
--  independent); writes set groupId and mirror the boolean for older-version export
--  compat. Groups chain in index order: the first ENABLED member is the anchor (owns
--  position/mover), later members chain to it sharing its width/height.
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

-- Smallest positive group id not currently in use (fills holes left by dissolved groups so group names stay compact).
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

-- Per-group settings live in tbb.groups[tostring(gid)]. Group 1 VIEWS the legacy keys
-- (tbb.groupGrowDirection/groupSpacing) for zero-migration old-config compat; group-1
-- writes keep those keys synced for old-version imports. gid->string memo below avoids a
-- tostring allocation in the per-tick reflow.
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

-- Internal reads take the tbb table directly so the per-tick reflow does not re-resolve the active spec profile per group.
local function GroupGrowOf(tbb, gid)
    local g = TBBGroupStore(tbb, gid, false)
    if g and g.globalKey then
        -- Global group: shared value from the profile registry. A stale key (entry deleted) falls through to the local values.
        local e = ns.TBBGlobalGroup and ns.TBBGlobalGroup(g.globalKey)
        if e then return e.grow or "DOWN" end
    end
    if g and g.grow then return g.grow end
    if gid == 1 and tbb.groupGrowDirection then return tbb.groupGrowDirection end
    return "DOWN"
end

local function GroupSpacingOf(tbb, gid)
    local g = TBBGroupStore(tbb, gid, false)
    if g and g.globalKey then
        local e = ns.TBBGlobalGroup and ns.TBBGlobalGroup(g.globalKey)
        if e and e.spacing ~= nil then return e.spacing end
    end
    if g and g.spacing ~= nil then return g.spacing end
    if gid == 1 and tbb.groupSpacing ~= nil then return tbb.groupSpacing end
    return 2
end

function ns.TBBGroupGrow(gid)
    return GroupGrowOf(ns.GetTrackedBuffBars(), gid)
end

function ns.TBBSetGroupGrow(gid, v)
    local t = ns.GetTrackedBuffBars()
    local gkey = ns.TBBGroupGlobalKey and ns.TBBGroupGlobalKey(gid)
    if gkey then
        local e = ns.TBBGlobalGroup(gkey)
        if e then e.grow = v; _tbbReflowDirty = true end
        return
    end
    TBBGroupStore(t, gid, true).grow = v
    if gid == 1 then t.groupGrowDirection = v end
    _tbbReflowDirty = true
end

function ns.TBBGroupSpacing(gid)
    return GroupSpacingOf(ns.GetTrackedBuffBars(), gid)
end

function ns.TBBSetGroupSpacing(gid, v)
    local t = ns.GetTrackedBuffBars()
    local gkey = ns.TBBGroupGlobalKey and ns.TBBGroupGlobalKey(gid)
    if gkey then
        local e = ns.TBBGlobalGroup(gkey)
        if e then e.spacing = v; _tbbReflowDirty = true end
        return
    end
    TBBGroupStore(t, gid, true).spacing = v
    if gid == 1 then t.groupSpacing = v end
    _tbbReflowDirty = true
end

-- Clear a group's stored settings when its id is (re)claimed for a brand-new group, so a dissolved group's leftovers do not leak into it.
function ns.TBBResetGroupSettings(gid)
    local t = ns.GetTrackedBuffBars()
    if t.groups then t.groups[_gidKeys[gid]] = nil end
    _tbbReflowDirty = true
end

-- Optional user-given group name (Group Settings input). Empty/absent = nil, callers fall back to the default "Group N" label.
function ns.TBBGroupName(gid)
    local t = ns.GetTrackedBuffBars()
    local g = TBBGroupStore(t, gid, false)
    if g and g.globalKey then
        local e = ns.TBBGlobalGroup and ns.TBBGlobalGroup(g.globalKey)
        if e and type(e.name) == "string" and e.name ~= "" then return e.name end
    end
    local n = g and g.name
    if type(n) == "string" and n ~= "" then return n end
    return nil
end

function ns.TBBSetGroupName(gid, name)
    local t = ns.GetTrackedBuffBars()
    local gkey = ns.TBBGroupGlobalKey and ns.TBBGroupGlobalKey(gid)
    if gkey then
        -- Shared name lives in the registry and is never blanked: movers and dropdown rows on other specs need a concrete label.
        local e = ns.TBBGlobalGroup(gkey)
        if e then
            if type(name) == "string" and name ~= "" then
                e.name = name
            end
        end
        return
    end
    if type(name) ~= "string" or name == "" then
        local g = TBBGroupStore(t, gid, false)
        if g then g.name = nil end
    else
        TBBGroupStore(t, gid, true).name = name
    end
end

-------------------------------------------------------------------------------
--  Global groups: a PROFILE-scoped registry shared by every spec. A per-spec group
--  opts in by stamping groups[gid].globalKey; its name/grow/spacing/position then
--  resolve through the registry entry (including the unlock mover, keyed stably as
--  "TBBG_<gkey>"), so every spec linked to the key shares one identity. Membership
--  stays per-spec: a spec with no bars on the key has no frames and a hidden mover.
--  Keys are monotonic and NEVER reused (reuse would resurrect stale unlock anchor
--  links). Zero migration: a group without a globalKey stamp is purely local.
-------------------------------------------------------------------------------
do
    local function TBBGlobalDB(create)
        if not (ECME and ECME.db) then ECME = ns.ECME end
        local p = ECME and ECME.db and ECME.db.profile
        if not p then return nil end
        if not p.tbbGlobalGroups and create then p.tbbGlobalGroups = {} end
        return p.tbbGlobalGroups, p
    end

    function ns.GetTBBGlobalGroups()
        return TBBGlobalDB(false)
    end

    function ns.TBBGlobalGroup(gkey)
        local reg = TBBGlobalDB(false)
        return reg and gkey and reg[gkey] or nil
    end

    -- The globalKey a per-spec group is linked to (nil = local group). A stale stamp whose registry entry was deleted reads as local.
    function ns.TBBGroupGlobalKey(gid)
        local g = TBBGroupStore(ns.GetTrackedBuffBars(), gid, false)
        local gkey = g and g.globalKey
        if gkey and ns.TBBGlobalGroup(gkey) then return gkey end
        return nil
    end

    -- Local gid linked to a global group on the ACTIVE spec (nil if none).
    function ns.TBBLocalGidForGlobal(gkey)
        local t = ns.GetTrackedBuffBars()
        if not t.groups then return nil end
        for k, g in pairs(t.groups) do
            if g.globalKey == gkey then return tonumber(k) end
        end
        return nil
    end

    -- Find-or-create the active spec's local group for a global group. The id must dodge
    -- BOTH gids used by bars and gids held by memberless global links (TBBNextGroupID only
    -- scans bars; reusing a linked gid here would wipe another global group's link).
    function ns.TBBEnsureLocalGroupForGlobal(gkey)
        if not ns.TBBGlobalGroup(gkey) then return nil end
        local gid = ns.TBBLocalGidForGlobal(gkey)
        if gid then return gid end
        local t = ns.GetTrackedBuffBars()
        local used = {}
        for _, c in ipairs(t.bars or {}) do
            used[ns.TBBBarGroupID(c)] = true
        end
        if t.groups then
            for k, g in pairs(t.groups) do
                if g.globalKey then
                    local kn = tonumber(k)
                    if kn then used[kn] = true end
                end
            end
        end
        gid = 1
        while used[gid] do gid = gid + 1 end
        ns.TBBResetGroupSettings(gid)
        TBBGroupStore(t, gid, true).globalKey = gkey
        return gid
    end

    -- Sorted registry keys (stable ordering for dropdown rows / movers).
    function ns.TBBGlobalGroupKeys()
        local reg = TBBGlobalDB(false)
        local list = {}
        if reg then
            for k in pairs(reg) do list[#list + 1] = k end
            table.sort(list, function(a, b)
                return (tonumber(a:match("%d+")) or 0) < (tonumber(b:match("%d+")) or 0)
            end)
        end
        return list
    end

    -- "Shift Elements If No Bars" (entry.shiftNoBar = "Up"/"Down", nil = None;
    -- entry.shiftNoBarExtraY tunes the magnitude). Stand-in frame for a global
    -- group on memberless specs, created ONLY while the option is set (None =
    -- byte-identical legacy behavior: nil getFrame, anchors dormant/fallback):
    -- a bare script-free frame holding the group's slot -- registry position,
    -- last-stamped anchor-bar size -- so anchored elements keep resolvable
    -- bounds and the shift has a magnitude when no member bar frame exists.
    -- Renders nothing and costs nothing (no events, no OnUpdate). Re-positioned
    -- every build; the IsUnlockAnchored guard leaves it alone when the anchor
    -- system owns the TBBG_ key (same guard as the bar placement below).
    local tbbStandins = {}
    function ns.TBBEnsureStandin(gk)
        local entry = ns.TBBGlobalGroup(gk)
        if not entry then return nil end
        local f = tbbStandins[gk]
        if not f then
            f = CreateFrame("Frame", nil, UIParent)
            tbbStandins[gk] = f
        end
        local PPl = EllesmereUI and EllesmereUI.PP
        local sn = PPl and PPl.Snap or function(v) return v end
        f:SetSize(sn(entry.width or 270), sn(entry.height or 24))
        -- SetPoint ONLY on an actual position change (signature-stamped): this
        -- runs from getFrame, and the unlock machinery hooksecurefuncs SetPoint
        -- on resolved frames -- an unconditional re-point per resolve fed the
        -- move-check timer a fresh SetPoint every frame, forever (audit-caught).
        -- getFrame must never mutate what it merely resolves.
        local anchored = EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored("TBBG_" .. gk)
        if anchored and f:GetLeft() then return f end
        local pos = entry.pos
        local sig
        if pos and pos.point then
            sig = pos.point .. "|" .. (pos.relPoint or pos.point) .. "|"
                .. (pos.x or 0) .. "|" .. (pos.y or 0)
        else
            sig = "default"
        end
        if f._posSig ~= sig then
            f._posSig = sig
            f:ClearAllPoints()
            if pos and pos.point then
                f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
            else
                f:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
            end
        end
        return f
    end
    -- Read-only lookup (no create): lets getFrame keep resolving a stand-in
    -- built earlier this session after the option flips to None, so the flip's
    -- cascade can land anchored children back at the true slot instead of
    -- stranding them shifted. A fresh session with the option off never creates
    -- one, preserving the legacy nil-frame behavior.
    function ns.TBBStandinFrame(gk)
        return tbbStandins[gk]
    end

    -- Whether ANY spec profile links this global key. A fully-orphaned entry
    -- (every spec detached; the registry keeps it for re-attachment) must stop
    -- shifting -- with no linked spec, no group settings page can reach the
    -- option to clear it (audit-caught). Bounded scan: specs x groups, only
    -- reached when the option is set and the ACTIVE spec is memberless.
    local function TBBGlobalLinkedAnywhere(gkey)
        local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
        if not sp then return false end
        for _, prof in pairs(sp) do
            local tbb = prof.trackedBuffBars
            local groups = tbb and tbb.groups
            if groups then
                for _, g in pairs(groups) do
                    if g.globalKey == gkey then return true end
                end
            end
        end
        return false
    end

    -- Direction the shift WOULD apply for one registry entry (ignores unlock
    -- state): 0 while the active spec has an enabled member bar (the real
    -- anchor frame covers the slot), the option is off, or no spec links the
    -- entry at all; else +1/-1.
    local function TBBShiftDirFor(entry, gk)
        local mode = entry and entry.shiftNoBar
        if mode ~= "Up" and mode ~= "Down" then return 0 end
        local gid = ns.TBBLocalGidForGlobal(gk)
        if gid and ns.TBBGroupAnchorIndex(gid) then return 0 end
        if not TBBGlobalLinkedAnywhere(gk) then return 0 end
        return (mode == "Up") and 1 or -1
    end
    ns.TBBShiftDirFor = TBBShiftDirFor

    -- Seeded into the shared shift-provider list (EUI_UnlockMode.lua dispatches
    -- EllesmereUI._GetAnchorTargetShiftDir over it; ResourceBars seeds the
    -- ERB_* keys the same way). Direct or-preserve push, NEVER an API call:
    -- registration must carry zero load-order coupling. Elements anchored to a
    -- shifting TBBG_ key move into the empty slot by the stand-in's height +
    -- Extra Y -- visual-only, never written to saved positions; 0 while unlock
    -- mode is active so movers capture true positions.
    EllesmereUI._anchorShiftProviders = EllesmereUI._anchorShiftProviders or {}
    table.insert(EllesmereUI._anchorShiftProviders, {
        dir = function(targetKey)
            if EllesmereUI._unlockActive then return 0 end
            if type(targetKey) ~= "string" or targetKey:sub(1, 5) ~= "TBBG_" then return 0 end
            local gk = targetKey:sub(6)
            local entry = ns.TBBGlobalGroup(gk)
            local dir = TBBShiftDirFor(entry, gk)
            if dir == 0 then return 0 end
            return dir, entry.shiftNoBarExtraY or 0
        end,
        wants = function()
            local reg = TBBGlobalDB(false)
            if not reg then return false end
            for gk, entry in pairs(reg) do
                if TBBShiftDirFor(entry, gk) ~= 0 then return true end
            end
            return false
        end,
        restore = function()
            if not EllesmereUI.PropagateAnchorChain then return end
            local reg = TBBGlobalDB(false)
            if not reg then return end
            for gk, entry in pairs(reg) do
                if TBBShiftDirFor(entry, gk) ~= 0 then
                    EllesmereUI.PropagateAnchorChain("TBBG_" .. gk)
                end
            end
        end,
    })

    -- Opt in: seed the registry from the group's current per-spec settings and anchor
    -- position. Detach: materialize shared values back into the per-spec store so nothing
    -- moves; the registry entry persists for other specs (full removal is TBBDeleteGlobalGroup).
    function ns.TBBSetGroupGlobal(gid, on)
        local t = ns.GetTrackedBuffBars()
        local g = TBBGroupStore(t, gid, true)
        if on then
            if g.globalKey and ns.TBBGlobalGroup(g.globalKey) then return end
            local reg, p = TBBGlobalDB(true)
            if not reg then return end
            local id = (p.tbbGlobalGroupNextId or 0) + 1
            p.tbbGlobalGroupNextId = id
            local gkey = "g" .. id
            local L = EllesmereUI and EllesmereUI.L
            local entry = {
                name    = ns.TBBGroupName(gid) or ((L and L("Group") or "Group") .. " " .. gid),
                grow    = GroupGrowOf(t, gid),
                spacing = GroupSpacingOf(t, gid),
            }
            local ai = ns.TBBGroupAnchorIndex(gid)
            local pos = ai and ns.GetTBBPositions()[tostring(ai)]
            if pos and pos.point then
                entry.pos = { point = pos.point, relPoint = pos.relPoint, x = pos.x, y = pos.y }
            end
            reg[gkey] = entry
            g.globalKey = gkey
        else
            local gkey = g.globalKey
            g.globalKey = nil
            local entry = gkey and ns.TBBGlobalGroup(gkey)
            if entry then
                g.name = entry.name
                g.grow = entry.grow
                g.spacing = entry.spacing
                if gid == 1 then
                    t.groupGrowDirection = entry.grow
                    t.groupSpacing = entry.spacing
                end
                _tbbReflowDirty = true
                if entry.pos then
                    local posDB = ns.GetTBBPositions()
                    for j, c in ipairs(t.bars or {}) do
                        if ns.TBBBarGroupID(c) == gid then
                            posDB[tostring(j)] = { point = entry.pos.point, relPoint = entry.pos.relPoint, x = entry.pos.x, y = entry.pos.y }
                        end
                    end
                end
            end
        end
    end

    -- Growth-edge extent: when an element anchors to the side of a tracking bar group
    -- that MATCHES the group's growth direction (TOP of an upward-growing group, LEFT
    -- of a leftward one), the anchor edge follows the outermost VISIBLE member instead
    -- of the static anchor bar, so it rides the stack as bars appear/fade. Every other
    -- side/target combo is untouched: the provider returns nil and the anchor system
    -- uses the frame's own bounds.
    local GROW_TO_SIDE = { UP = "TOP", DOWN = "BOTTOM", LEFT = "LEFT", RIGHT = "RIGHT" }

    -- Resolve an anchor target key to a group id IF the anchored side matches that group's growth direction (nil otherwise).
    function ns.TBBExtentGidForTarget(targetKey, side)
        if type(targetKey) ~= "string" or not side then return nil end
        local gid
        local gkey = targetKey:match("^TBBG_(.+)$")
        if gkey then
            gid = ns.TBBLocalGidForGlobal(gkey)
        else
            local idx = tonumber(targetKey:match("^TBB_(%d+)$"))
            if not idx then return nil end
            local t = ns.GetTrackedBuffBars()
            local c = t.bars and t.bars[idx]
            gid = c and ns.TBBBarGroupID(c) or 0
            if gid == 0 or idx ~= ns.TBBGroupAnchorIndex(gid) then return nil end
        end
        if not gid then return nil end
        local grow = (ns.TBBGroupGrow(gid) or "DOWN"):upper()
        if GROW_TO_SIDE[grow] ~= side then return nil end
        return gid
    end

    -- Anchor-system hook: outermost visible member edge in UIParent space, or nil to use
    -- the target frame's own bounds. Inert while unlock mode or the placeholder preview owns positions.
    function EllesmereUI._GetAnchorTargetExtent(targetKey, side)
        if EllesmereUI._unlockActive or ns._tbbPlaceholderMode then return nil end
        local gid = ns.TBBExtentGidForTarget(targetKey, side)
        if not gid then return nil end
        local t = ns.GetTrackedBuffBars()
        local uiS = UIParent:GetEffectiveScale()
        local best
        for i, c in ipairs(t.bars or {}) do
            if c.enabled ~= false and ns.TBBBarGroupID(c) == gid then
                local f = tbbFrames[i]
                if f and f:IsShown() and f:GetLeft() then
                    local fS = f:GetEffectiveScale() / uiS
                    local v
                    if side == "TOP" then
                        v = (f:GetTop() or 0) * fS
                    elseif side == "BOTTOM" then
                        v = (f:GetBottom() or 0) * fS
                    elseif side == "LEFT" then
                        v = (f:GetLeft() or 0) * fS
                    else
                        v = (f:GetRight() or 0) * fS
                    end
                    if not best then
                        best = v
                    elseif side == "TOP" or side == "RIGHT" then
                        if v > best then best = v end
                    elseif v < best then
                        best = v
                    end
                end
            end
        end
        return best
    end

    -- gid -> anchored unlock key needing extent updates. Memo invalidation: the unlock
    -- module bumps _anchorLinksStamp on link changes; RegisterTBBUnlockElements nils the
    -- memo on every build (grow/membership/spec changes).
    local function RebuildExtentWatch()
        local w = {}
        local anchors = EllesmereUIDB and EllesmereUIDB.unlockAnchors
        if anchors then
            for _, info in pairs(anchors) do
                if info.target then
                    local gid = ns.TBBExtentGidForTarget(info.target, info.side)
                    if gid then w[gid] = info.target end
                end
                local fb = info.fallback
                if fb and fb.target then
                    local gid = ns.TBBExtentGidForTarget(fb.target, fb.side)
                    if gid then w[gid] = fb.target end
                end
            end
        end
        return w
    end

    local function TBBExtentWatchKey(gid)
        if not gid or gid == 0 then return nil end
        local stamp = EllesmereUI._anchorLinksStamp or 0
        local w = ns._tbbExtentWatch
        if not w or ns._tbbExtentWatchStamp ~= stamp then
            w = RebuildExtentWatch()
            ns._tbbExtentWatch = w
            ns._tbbExtentWatchStamp = stamp
        end
        return w[gid]
    end

    -- Called by the reflow only when a group's visible footprint actually changed
    -- (change-gated there, NOT per-tick). Queues batched anchor propagation for the unlock key.
    function ns._NotifyTBBExtentChanged(gid)
        local key = TBBExtentWatchKey(gid)
        if not key then return end
        if EllesmereUI.PropagateAnchorChain then
            EllesmereUI.PropagateAnchorChain(key, "all")
        end
    end

    -- Remove a global group everywhere: every spec's linked group detaches with the shared
    -- values materialized locally (bars keep their positions), then the registry entry is deleted.
    function ns.TBBDeleteGlobalGroup(gkey)
        local reg = TBBGlobalDB(false)
        local entry = reg and reg[gkey]
        if not entry then return end
        local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
        if sp then
            for _, prof in pairs(sp) do
                local tbb = prof.trackedBuffBars
                if tbb and tbb.groups then
                    for k, g in pairs(tbb.groups) do
                        if g.globalKey == gkey then
                            g.globalKey = nil
                            g.name = entry.name
                            g.grow = entry.grow
                            g.spacing = entry.spacing
                            if k == "1" then
                                tbb.groupGrowDirection = entry.grow
                                tbb.groupSpacing = entry.spacing
                            end
                            _tbbReflowDirty = true
                            if entry.pos then
                                if not prof.tbbPositions then prof.tbbPositions = {} end
                                local kn = tonumber(k)
                                for j, c in ipairs(tbb.bars or {}) do
                                    if ns.TBBBarGroupID(c) == kn then
                                        prof.tbbPositions[tostring(j)] = { point = entry.pos.point, relPoint = entry.pos.relPoint, x = entry.pos.x, y = entry.pos.y }
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        reg[gkey] = nil
        -- Retire the group's shift stand-in with it: a leftover frame would keep
        -- resolving through getFrame's session fallback and glue anchored
        -- elements to the deleted group's last position (audit-caught).
        local sf = tbbStandins[gkey]
        if sf then
            sf:Hide()
            tbbStandins[gkey] = nil
        end
    end
end

-- "Auto-Add New to This Group": the flagged group receives a bar for every spell newly
-- appearing in Blizzard's Tracked Bars section. At most ONE group holds the flag; enabling it clears the others.
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

-- The group flagged for auto-add (or nil). Smallest id wins if a stale table somehow carries more than one flag.
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

-- Index of a group's anchor = its first enabled member (or nil if none). gid nil = group 1 (legacy callers).
function ns.TBBGroupAnchorIndex(gid)
    gid = gid or 1
    local t = ns.GetTrackedBuffBars()
    for i, c in ipairs(t.bars or {}) do
        if c.enabled ~= false and ns.TBBBarGroupID(c) == gid then return i end
    end
    return nil
end

-- Member count: with gid, counts that group's bars (regardless of enabled); without, counts bars in ANY group (drives options disabled gates).
function ns.TBBGroupedCount(gid)
    local t = ns.GetTrackedBuffBars()
    local n = 0
    for _, c in ipairs(t.bars or {}) do
        local g = ns.TBBBarGroupID(c)
        if (gid and g == gid) or (not gid and g ~= 0) then n = n + 1 end
    end
    return n
end

-- Groups are orientation-uniform (shared width/height only make sense if every member
-- reads dimensions the same way). The group's FIRST member defines the orientation; a
-- disagreeing member (preset on one bar, cross-spec copy, import) is coerced, swapping
-- its stored dims so on-screen proportions carry over. Runs every rebuild; the options
-- Vertical Orientation toggle flips the whole group explicitly so deliberate flips
-- never fight it.
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
--  A bar's "style" = every visual key EXCEPT tracked spell identity, enable state,
--  group membership, and stack-threshold/stack-based-fill keys (spell-specific;
--  matches AddTrackedBuffBar's reset set) -- a copied style must never carry
--  threshold numbers.
-------------------------------------------------------------------------------
local TBB_STYLE_KEYS = {
    "height", "width", "verticalOrientation", "reverseFill", "fillUp",
    "chargeHashLines", "chargeHashLineWidth",
    "chargeHashLineR", "chargeHashLineG", "chargeHashLineB", "chargeHashLineA",
    "texture", "strata",
    "fillColorMode", "fillR", "fillG", "fillB", "fillA",
    "bgR", "bgG", "bgB", "bgA",
    "gradientEnabled", "gradientR", "gradientG", "gradientB", "gradientA", "gradientDir",
    "opacity", "hideWhenInactive", "onlyInCombat",
    -- Visibility rides along because the onlyInCombat toggle it replaced already did: a new
    -- bar inheriting a neighbour's style, or one joining a group, kept that gate before.
    "barVisibility", "visibilityModes", "visibilityMatch",
    -- The option lanes themselves are appended from the shared list below.
    "showTimer", "timerPosition", "timerSize", "timerX", "timerY",
    "timerTextR", "timerTextG", "timerTextB", "timerTextA",
    "timerDecimals", "timerDecimalThreshold",
    "showName", "namePosition", "nameSize", "nameX", "nameY",
    "nameTextR", "nameTextG", "nameTextB", "nameTextA",
    "showSpark",
    "iconDisplay", "iconSize", "iconX", "iconY", "iconBorderSize",
    "stacksPosition", "stacksSize", "stacksX", "stacksY",
    "stacksTextR", "stacksTextG", "stacksTextB", "stacksTextA",
    "borderSize", "borderTexture", "borderR", "borderG", "borderB",
    "borderTextureOffset", "borderTextureOffsetY",
    "borderTextureShiftX", "borderTextureShiftY", "borderBehind",
    "pandemicGlow", "pandemicGlowStyle", "pandemicGlowColor",
    "pandemicGlowLines", "pandemicGlowThickness", "pandemicGlowSpeed",
}
-- Appended rather than spelled out: a lane added to the shared list is copied with the
-- rest of the style instead of silently staying behind on the source bar.
if EllesmereUI.VIS_OPT_KEYS then
    for i = 1, #EllesmereUI.VIS_OPT_KEYS do
        TBB_STYLE_KEYS[#TBB_STYLE_KEYS + 1] = EllesmereUI.VIS_OPT_KEYS[i]
    end
end
ns.TBB_STYLE_KEYS = TBB_STYLE_KEYS

-- Copy src's visual style onto dst, key-exact (including nil) so both bars resolve defaults
-- identically. Table values (glow color) are deep-copied so the two never share a mutable table.
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

-- The bar whose style represents a group: its anchor, or (all members disabled) its first member.
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
--  Style presets (PROFILE-scoped: persist across specs, travel with profile
--  export). Entry = { name, style = {<TBB_STYLE_KEYS values>} }. A bar
--  remembers the preset last applied to it (cfg.stylePresetName) so new bars
--  can resolve a preset by association.
-------------------------------------------------------------------------------
function ns.GetTBBStylePresets()
    if not (ECME and ECME.db) then ECME = ns.ECME end
    local p = ECME and ECME.db and ECME.db.profile
    if not p then return nil end
    if not p.tbbStylePresets then p.tbbStylePresets = {} end
    -- Same icon-footprint fold as GetTrackedBuffBars: legacy presets stored the FILL size rather than the icon-inclusive total.
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

-- Save (or overwrite) a preset from a bar's current style, and associate the source bar with it.
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

-- Delete a saved preset. Bar associations (cfg.stylePresetName) are left in place and go inert: FindTBBStylePreset returns nil for a missing name.
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

-- Rename a preset, carrying bar associations (across every spec of the active profile) and the UI selection pointer with it.
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

-- New-bar resolution: the preset associated with a bar already in the target group (nil if none).
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

-- New-bar fallback: a preset associated with any bar of this spec, else any saved preset (nil when none are saved).
function ns.ResolveTBBFallbackPreset(tbb)
    local presets = ns.GetTBBStylePresets()
    if not presets or #presets == 0 then return nil end
    for _, c in ipairs(tbb.bars or {}) do
        local pr = ns.FindTBBStylePreset(c.stylePresetName)
        if pr then return pr end
    end
    return presets[1]
end


-- Runtime reflow for grouped Tracking Bars: BuildTrackedBuffBars creates the static
-- group chain, but the tick decides which bars are visible, so only visible grouped
-- members are reflowed to leave no holes when a buff is inactive/hidden -- e.g. with
-- configured order Buff 1/2/3 and only 2/3 active, Buff 2 sits at the group anchor.
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

    -- Collect this group's enabled + visible bars in saved hierarchy order. A bar with
    -- hideWhenInactive=false is visible so it keeps its slot (shows inactive bars). Entry
    -- tables are pooled and reused across ticks: zero allocation in this every-16ms path.
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
        -- Group fully collapsed: anchored elements fall back to the anchor bar's own (hidden but resolvable) bounds. Notify once.
        if st.lastCount ~= 0 and ns._NotifyTBBExtentChanged then
            ns._NotifyTBBExtentChanged(gid)
        end
        st.lastCount = 0
        return
    end

    -- Re-anchor only when the visible member sequence or the grow/spacing tuple changes. Compared element-wise so no string is allocated per tick.
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
        -- Configured anchor buff is inactive/hidden: pin the first VISIBLE member onto the
        -- anchor frame's slot so it takes the group origin. The anchor frame keeps whatever
        -- position BuildTrackedBuffBars/the unlock system gave it (element anchoring included).
        first:ClearAllPoints()
        first:SetPoint("TOPLEFT", anchorFrame, "TOPLEFT", 0, 0)
    end
    -- else the first visible bar IS the anchor: NEVER touch its point. BuildTrackedBuffBars
    -- and the unlock system already position it and honor IsUnlockAnchored, so re-deriving
    -- from tbbPositions would clobber an element-anchored group (stale coord/screen center).

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

    -- Only reached when the visible sequence/grow/spacing actually changed: let elements anchored to the group's growth side re-read the moving edge.
    if ns._NotifyTBBExtentChanged then
        ns._NotifyTBBExtentChanged(gid)
    end
end

local function ReflowVisibleGroupedTBBars(tbb, bars)
    if not (tbb and bars and tbbFrames) then return end
    -- Never fight edit-preview (placeholder) or unlock-mode dragging: there BuildTrackedBuffBars and the unlock system own bar positions.
    if ns._tbbPlaceholderMode or EllesmereUI._unlockActive then return end
    -- Reflow each present group once; the done-set is reused across ticks so this pass allocates nothing.
    _tbbReflowDirty = false
    wipe(_tbbReflowDone)
    for _, cfg in ipairs(bars) do
        local gid = ns.TBBBarGroupID(cfg)
        if gid ~= 0 and not _tbbReflowDone[gid] then
            _tbbReflowDone[gid] = true
            ReflowGroup(tbb, gid, bars)
        end
    end
end

-- Fan a width/height change from a grouped bar to every sibling in the SAME group:
-- write each sibling's LOGICAL cfg.width/cfg.height (NOT icon-inclusive total) and
-- resize its frame with its OWN icon math. Used by options sliders, unlock
-- drag-resize and size-MATCH; re-entrancy guarded so a sibling write cannot recurse.
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
                -- width/height are the total footprint (icon included), so the frame takes the value directly.
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

-- No-ops kept because options/main file may still reference them.
ns.RefreshTBBResolvedIDs = function() end
ns.RefreshBuffBarGating  = function() end

-------------------------------------------------------------------------------
--  Frame Creation
-------------------------------------------------------------------------------
local function CreateTrackedBuffBarFrame(parent, idx)
    local wrapFrame = CreateFrame("Frame", "ECME_TBBWrap" .. idx, parent)
    -- MEDIUM strata at level 100 by default (cfg.strata can move the whole bar via
    -- ApplyTrackedBuffBarSettings); level 100 keeps it above overlapping buff-icon
    -- displays (MEDIUM, low levels). Internal level order: strips +6 < glow +7 < text +8.
    wrapFrame:SetFrameStrata("MEDIUM")
    wrapFrame:SetFrameLevel(100)
    -- Visibility is a group reflow input: every Show/Hide edge, whichever path drives it, dirties the reflow.
    wrapFrame:SetScript("OnShow", _MarkTBBReflowDirty)
    wrapFrame:SetScript("OnHide", _MarkTBBReflowDirty)

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

    -- Spark on a dedicated overlay above the (gradient) fill and threshold overlays
    -- so it always draws OVER both; ApplyTrackedBuffBarSettings owns the final level
    -- (this value only holds until the first apply). Clipped to the bar so it never
    -- spills past the ends. SnapToPixelGrid off so it tracks the smoothly-interpolated
    -- fill edge at sub-pixel precision instead of jumping a pixel at a grid line.
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

    -- Text overlay: parented to wrapFrame (not bar) so bar's SetClipsChildren can't
    -- chop text when font size exceeds bar height. Level sits above the border (bar+5
    -- in ApplySettings, PP strips at +6) and the pandemic glow overlay (wrapFrame+7 =
    -- bar+6), so timer/name/stacks render on top of both; keyed off bar so they track together.
    local textOverlay = CreateFrame("Frame", nil, wrapFrame)
    textOverlay:SetAllPoints(bar)
    textOverlay:SetFrameLevel(bar:GetFrameLevel() + 7)
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

    -- Pandemic glow overlay above the border, whose PP strips draw at +6
    -- (border frame +5 plus the +1 the strip container adds), so a thick border
    -- cannot bury the edge-hugging glow.
    local panGlow = CreateFrame("Frame", nil, wrapFrame)
    panGlow:SetAllPoints(wrapFrame)
    panGlow:SetFrameLevel(wrapFrame:GetFrameLevel() + 7)
    panGlow:SetAlpha(0)
    panGlow:EnableMouse(false)
    wrapFrame._pandemicGlowOverlay = panGlow

    wrapFrame:Hide()
    return wrapFrame
end

-------------------------------------------------------------------------------
--  Threshold Overlays (stacked StatusBars, secret-safe)
--
--  bar._stackCount may be a secret number, so it can NEVER be compared or sorted in
--  Lua. Each threshold gets its own StatusBar with range (value-1, value): SetValue
--  compares in the C layer, and the overlay snaps 0 -> full as the count crosses it.
--  With several thresholds every crossed overlay is full at once, so "highest
--  crossed wins" must be draw order, not an if: overlay i is parented to overlay i-1
--  (a child renders above its parent) and the list stays sorted ascending, so the
--  highest crossed threshold paints last. Frame levels stay pinned at sb+2, leaving
--  the tick overlay (sb+3) and charge hash lines (sb+4) on top.
-------------------------------------------------------------------------------
local function EnsureTBBThresholdOverlay(bar, i)
    local pool = bar._threshOverlays
    if not pool then pool = {}; bar._threshOverlays = pool end
    if pool[i] then return pool[i] end
    local sb = bar._bar
    if not sb then return nil end
    local overlay = CreateFrame("StatusBar", nil, pool[i - 1] or sb)
    overlay:SetAllPoints(sb:GetStatusBarTexture())
    overlay:SetFrameLevel(sb:GetFrameLevel() + 2)
    overlay:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    overlay:SetMinMaxValues(0, 1)
    overlay:SetValue(0)
    overlay:Hide()
    pool[i] = overlay
    return overlay
end

local function HideTBBThresholdOverlaysFrom(bar, first)
    local pool = bar._threshOverlays
    if not pool then return end
    for i = first, #pool do
        if pool[i] then pool[i]:Hide() end
    end
end

-- Multi-threshold list only when opted in and non-empty; nil means the legacy single-threshold keys own the rendering.
local function TBBMultiThresholdList(cfg)
    if not cfg.stackThresholdMulti then return nil end
    local list = cfg.stackThresholds
    if not list or #list == 0 then return nil end
    return list
end

local function ApplyTBBThresholdOverlay(overlay, sb, texPath, orient, reverse, i, r, g, b, a, value)
    overlay:SetStatusBarTexture(texPath)
    overlay:SetOrientation(orient)
    overlay:SetReverseFill(reverse)
    local tex = overlay:GetStatusBarTexture()
    tex:SetVertexColor(r, g, b, a)
    tex:SetDrawLayer("ARTWORK", i)
    overlay:ClearAllPoints()
    overlay:SetAllPoints(sb:GetStatusBarTexture())
    overlay:SetMinMaxValues(value - 1, value)
    overlay:SetValue(0)
    overlay:Show()
end

local function SetupTBBThresholdOverlay(bar, cfg)
    if not cfg.stackThresholdEnabled
       or (cfg.trackType == "cooldown" and cfg.chargeHashLines == true) then
        HideTBBThresholdOverlaysFrom(bar, 1)
        return
    end
    local sb = bar._bar
    if not sb then return end
    local texPath = EllesmereUI.ResolveTexturePath(TBB_TEXTURES, cfg.texture or "none", "Interface\\Buttons\\WHITE8x8")
    local orient  = cfg.verticalOrientation and "VERTICAL" or "HORIZONTAL"
    local reverse = cfg.reverseFill and true or false

    local n = 0
    local list = TBBMultiThresholdList(cfg)
    if list then
        -- Sorted ascending by the options editor, so index order is draw order.
        for i = 1, #list do
            local t = list[i]
            local overlay = EnsureTBBThresholdOverlay(bar, i)
            if not overlay then break end
            ApplyTBBThresholdOverlay(overlay, sb, texPath, orient, reverse, i,
                t.r or 0.8, t.g or 0.1, t.b or 0.1, t.a or 1, t.value or 5)
            n = i
        end
    else
        local overlay = EnsureTBBThresholdOverlay(bar, 1)
        if overlay then
            ApplyTBBThresholdOverlay(overlay, sb, texPath, orient, reverse, 1,
                cfg.stackThresholdR or 0.8, cfg.stackThresholdG or 0.1,
                cfg.stackThresholdB or 0.1, cfg.stackThresholdA or 1,
                cfg.stackThreshold or 5)
            n = 1
        end
    end
    HideTBBThresholdOverlaysFrom(bar, n + 1)
end

local function FeedTBBThresholdOverlay(bar)
    local pool = bar._threshOverlays
    if not pool then return end
    local v = bar._stackCount or 0
    for i = 1, #pool do
        local overlay = pool[i]
        if overlay and overlay:IsShown() then overlay:SetValue(v) end
    end
end

-------------------------------------------------------------------------------
--  Tick Marks
-------------------------------------------------------------------------------
-- Cooldown state must follow the SAVED spell, not the transient override
-- returned for an icon while a proc is active. The base fallback only handles
-- a saved talent override that is no longer learned.
local function StableCooldownSpellID(cfg)
    local sid = cfg and cfg.spellID
    if type(sid) ~= "number" or sid <= 0 then return nil end
    local base = cfg.baseSpellID
    if type(base) == "number" and base > 0 and IsPlayerSpell
       and not IsPlayerSpell(sid) and IsPlayerSpell(base) then
        return base
    end
    return sid
end

local function GetTBBMaxCharges(cfg)
    if not cfg or cfg.trackType ~= "cooldown" then return nil end
    local sid = StableCooldownSpellID(cfg)
    local ch = sid and C_Spell and C_Spell.GetSpellCharges
        and C_Spell.GetSpellCharges(sid)
    local maxCharges = ch and ch.maxCharges
    if issecretvalue and issecretvalue(maxCharges) then return nil end
    if type(maxCharges) == "number" and maxCharges > 1 then
        return math.floor(maxCharges + 0.5)
    end
    return nil
end
ns.GetTBBMaxCharges = GetTBBMaxCharges

-- "all" (any case, anywhere in the list) puts a tick between every stack: N
-- stacks give N-1 interior divisions, the same convention as the charge hash
-- lines below. Numbers listed alongside it are redundant and ignored.
local function ParseTickValues(str, maxStacks)
    if not str or str == "" then return nil end
    local vals = {}
    for s in str:gmatch("[^,]+") do
        local tok = s:match("^%s*(.-)%s*$")
        if tok:lower() == "all" then
            local m = maxStacks and math.floor(maxStacks) or 0
            if m < 2 then return nil end
            local out = {}
            for i = 1, m - 1 do out[i] = i end
            return out
        end
        local n = tonumber(tok)
        if n and n > 0 then vals[#vals + 1] = n end
    end
    return #vals > 0 and vals or nil
end

local function ApplyTBBTickMarks(sb, cfg, tickCache, isVert, tickParent)
    local maxStacks = cfg.stackThresholdMax or 10
    local vals = ParseTickValues(cfg.stackThresholdTicks, maxStacks)
    if tickCache then
        for i = 1, #tickCache do tickCache[i]:Hide() end
    end
    -- Ticks are governed by Max Stacks alone (the options input unlocks with it); Enable Stack Threshold only drives the recolor overlay, not ticks.
    if (cfg.trackType == "cooldown" and cfg.chargeHashLines == true)
       or not cfg.stackThresholdMaxEnabled
       or not vals or maxStacks < 1 or not tickCache then return end

    local PP = EllesmereUI and EllesmereUI.PP
    local parent = tickParent or sb
    while #tickCache < #vals do
        local t = parent:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetSnapToPixelGrid(false)
        t:SetTexelSnappingBias(0)
        tickCache[#tickCache + 1] = t
    end

    -- Legacy bars carry no tick-color fields: fall back to white so their ticks render unchanged.
    local tickR = cfg.stackThresholdTickR or 1
    local tickG = cfg.stackThresholdTickG or 1
    local tickB = cfg.stackThresholdTickB or 1
    local tickA = cfg.stackThresholdTickA
    if tickA == nil then tickA = 1 end

    local onePx = PP and PP.Scale(1) or 1
    local barW, barH = sb:GetWidth(), sb:GetHeight()
    -- Ticks measure stack fractions from the fill's ORIGIN, so they mirror when Reverse Fill moves the origin to the other end.
    local reverse = cfg.reverseFill and true or false
    for i, v in ipairs(vals) do
        if v <= maxStacks then
            local t = tickCache[i]
            local frac = v / maxStacks
            t:SetColorTexture(tickR, tickG, tickB, tickA)
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

-- Charge separators are fixed geometry over the full StatusBar: N charges give
-- N-1 separators. Equal divisions do not move when Reverse Fill changes the
-- recovery origin; vertical bars just rotate the marks.
local function ApplyTBBChargeHashLines(bar, cfg, maxCharges)
    if not bar or not cfg then return end
    local sb = bar._bar
    if not sb then return end

    local ticks = bar._chargeHashTicks
    if cfg.chargeHashLines ~= true or cfg.trackType ~= "cooldown"
       or type(maxCharges) ~= "number" or maxCharges <= 1 then
        if ticks then
            for i = 1, #ticks do ticks[i]:Hide() end
        end
        bar._chargeHashLineCacheValid = nil
        if bar._chargeHashOverlay then bar._chargeHashOverlay:Hide() end
        return
    end

    local barW, barH = sb:GetWidth(), sb:GetHeight()
    if not barW or not barH or barW <= 0 or barH <= 0 then
        if ticks then
            for i = 1, #ticks do ticks[i]:Hide() end
        end
        if bar._chargeHashOverlay then bar._chargeHashOverlay:Hide() end
        bar._chargeHashLineCacheValid = nil
        return
    end

    local width = tonumber(cfg.chargeHashLineWidth) or 2
    width = math.max(1, math.min(10, math.floor(width + 0.5)))
    local lineR = cfg.chargeHashLineR or 0
    local lineG = cfg.chargeHashLineG or 0
    local lineB = cfg.chargeHashLineB or 0
    local lineA = cfg.chargeHashLineA
    if lineA == nil then lineA = 1 end
    local isVert = cfg.verticalOrientation and true or false
    local effectiveScale = sb:GetEffectiveScale() or 1
    -- Also runs from the shared timer tick, so the cache stays SCALAR: synthesized table/string keys would allocate even on a cache hit.
    if bar._chargeHashLineCacheValid
       and bar._chargeHashLineMaxCharges == maxCharges
       and bar._chargeHashLineWidth == width
       and bar._chargeHashLineVertical == isVert
       and bar._chargeHashLineBarW == barW
       and bar._chargeHashLineBarH == barH
       and bar._chargeHashLineScale == effectiveScale
       and bar._chargeHashLineR == lineR
       and bar._chargeHashLineG == lineG
       and bar._chargeHashLineB == lineB
       and bar._chargeHashLineA == lineA
       and bar._chargeHashOverlay and bar._chargeHashOverlay:IsShown() then
        return
    end

    if ticks then
        for i = 1, #ticks do ticks[i]:Hide() end
    end

    if not bar._chargeHashOverlay then
        local overlay = CreateFrame("Frame", nil, sb)
        overlay:SetAllPoints(sb)
        overlay:SetFrameLevel(sb:GetFrameLevel() + 5)
        bar._chargeHashOverlay = overlay
    end
    bar._chargeHashOverlay:Show()
    if not ticks then
        ticks = {}
        bar._chargeHashTicks = ticks
    end

    while #ticks < maxCharges - 1 do
        local tick = bar._chargeHashOverlay:CreateTexture(nil, "OVERLAY", nil, 7)
        tick:SetSnapToPixelGrid(false)
        tick:SetTexelSnappingBias(0)
        ticks[#ticks + 1] = tick
    end

    local PP = EllesmereUI and EllesmereUI.PP
    local lineWidth = PP and PP.Scale(width) or width
    for i = 1, maxCharges - 1 do
        local tick = ticks[i]
        local frac = i / maxCharges
        tick:SetColorTexture(lineR, lineG, lineB, lineA)
        tick:ClearAllPoints()
        if isVert then
            local offset = PP and PP.Scale(barH * frac) or (barH * frac)
            tick:SetSize(barW, lineWidth)
            tick:SetPoint("CENTER", sb, "BOTTOM", 0, offset)
        else
            local offset = PP and PP.Scale(barW * frac) or (barW * frac)
            tick:SetSize(lineWidth, barH)
            tick:SetPoint("CENTER", sb, "LEFT", offset, 0)
        end
        tick:Show()
    end
    for i = maxCharges, #ticks do ticks[i]:Hide() end
    bar._chargeHashLineCacheValid = true
    bar._chargeHashLineMaxCharges = maxCharges
    bar._chargeHashLineWidth = width
    bar._chargeHashLineVertical = isVert
    bar._chargeHashLineBarW = barW
    bar._chargeHashLineBarH = barH
    bar._chargeHashLineScale = effectiveScale
    bar._chargeHashLineR = lineR
    bar._chargeHashLineG = lineG
    bar._chargeHashLineB = lineB
    bar._chargeHashLineA = lineA
end
-- Exported for the options popout preview: its bars have no timer tick to re-drive width-gated geometry once the fill's anchor-derived size resolves.
ns.ApplyTBBChargeHashLines = ApplyTBBChargeHashLines

local function AnchorTBBSparkState(bar, anchor, isVert, reverse, flushToEdge)
    local sb, spark = bar and bar._bar, bar and bar._spark
    if not sb or not spark or not anchor then return end
    isVert = isVert and true or false
    reverse = reverse and true or false
    flushToEdge = flushToEdge and true or false
    local barW, barH = sb:GetWidth(), sb:GetHeight()
    if bar._sparkAnchorTarget == anchor
       and bar._sparkAnchorVertical == isVert
       and bar._sparkAnchorReverse == reverse
       and bar._sparkAnchorFlush == flushToEdge
       and bar._sparkAnchorBarW == barW
       and bar._sparkAnchorBarH == barH then
        return
    end
    if isVert then
        spark:SetSize(barW, 8)
        spark:SetTexCoord(0, 1, 1, 1, 0, 0, 1, 0)
    else
        spark:SetSize(8, barH)
        spark:SetTexCoord(0, 0, 0, 1, 1, 0, 1, 1)
    end
    spark:ClearAllPoints()
    if isVert then
        spark:SetPoint("CENTER", anchor, reverse and "BOTTOM" or "TOP", 0, 0)
    else
        spark:SetPoint("CENTER", anchor,
            reverse and "LEFT" or "RIGHT",
            flushToEdge and 0 or (reverse and 1 or -1), 0)
    end
    bar._sparkAnchorTarget = anchor
    bar._sparkAnchorVertical = isVert
    bar._sparkAnchorReverse = reverse
    bar._sparkAnchorFlush = flushToEdge
    bar._sparkAnchorBarW = barW
    bar._sparkAnchorBarH = barH
end

local function AnchorTBBSpark(bar, cfg, anchor, flushToEdge)
    if not cfg then return end
    AnchorTBBSparkState(bar, anchor, cfg.verticalOrientation,
        cfg.reverseFill, flushToEdge)
end

-- Defined with the charge renderer below. ApplySettings calls it whenever a
-- pooled bar frame is restyled so stale composite geometry cannot leak into a
-- different bar after deletion, reordering or a tracking-type change.
local _restoreTBBNormalFill

-------------------------------------------------------------------------------
--  Apply Visual Settings
-------------------------------------------------------------------------------
local function ApplyTrackedBuffBarSettings(bar, cfg)
    if not bar or not cfg then return end
    local sb = bar._bar
    if not sb then return end
    if _restoreTBBNormalFill then _restoreTBBNormalFill(bar, cfg) end

    -- User-selectable strata for the whole bar (options setter keeps grouped bars
    -- uniform). A parent strata change COLLAPSES child frame levels, so the wrap
    -- level and the constructor's internal ladder are re-asserted whenever strata
    -- actually changes; the change guard keeps the common repaint path free of it.
    local strata = cfg.strata or "MEDIUM"
    if bar._lastStrata ~= strata then
        bar._lastStrata = strata
        bar:SetFrameStrata(strata)
        bar:SetFrameLevel(100)
        local base = bar:GetFrameLevel()
        sb:SetFrameLevel(base + 1)
        if bar._gradClip then bar._gradClip:SetFrameLevel(sb:GetFrameLevel() + 1) end
        if bar._chargeHashFillClip then bar._chargeHashFillClip:SetFrameLevel(sb:GetFrameLevel() + 1) end
        if bar._threshOverlays then
            for i = 1, #bar._threshOverlays do
                local ov = bar._threshOverlays[i]
                if ov then ov:SetFrameLevel(sb:GetFrameLevel() + 2) end
            end
        end
        -- Spark sits one level ABOVE the threshold overlays: at equal level it
        -- loses the tie to them (created lazily, so they win) and vanishes the
        -- moment a threshold is crossed. Ticks and charge hash lines shift up
        -- in step to keep their order.
        if bar._sparkOverlay then bar._sparkOverlay:SetFrameLevel(sb:GetFrameLevel() + 3) end
        -- Tick overlay MUST be re-asserted here too: SetFrameStrata collapses descendant levels, so otherwise ticks land at a default level.
        if bar._tickOverlay then bar._tickOverlay:SetFrameLevel(sb:GetFrameLevel() + 4) end
        if bar._chargeHashOverlay then bar._chargeHashOverlay:SetFrameLevel(sb:GetFrameLevel() + 5) end
        -- Border at base+6, not +5: tick marks sit at sb+4 (= base+5), which
        -- would TIE the border cross-subtree, and the lazily-created tick overlay wins
        -- ties, putting ticks ON TOP of the border. One level up keeps the border above
        -- ticks; charge hash lines tie it and win via later creation, as intended.
        if bar._barBorder then bar._barBorder:SetFrameLevel(base + 6) end
        if bar._pandemicGlowOverlay then bar._pandemicGlowOverlay:SetFrameLevel(base + 7) end
        if bar._textOverlay then bar._textOverlay:SetFrameLevel(sb:GetFrameLevel() + 7) end
    end

    -- width/height are always VISUAL dimensions describing the bar's TOTAL footprint,
    -- icon included: the wrap is exactly width x height and a shown icon carves its
    -- square out of the fill. Horizontal: width=long side, height=short side.
    -- Vertical: width=short side, height=long side.
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
    local fillTex = sb:GetStatusBarTexture()
    bar._cachedOurFillTex = fillTex

    -- Fill color
    local fR = cfg.fillR or _classR
    local fG = cfg.fillG or _classG
    local fB = cfg.fillB or _classB
    local fA = cfg.fillA or 1
    fillTex:SetVertexColor(fR, fG, fB, fA)
    bar._baseFillR, bar._baseFillG, bar._baseFillB, bar._baseFillA = fR, fG, fB, fA

    -- Background
    if bar._bg then
        bar._bg:SetColorTexture(cfg.bgR or 0, cfg.bgG or 0, cfg.bgB or 0, cfg.bgA or 0.4)
    end

    -- Gradient
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

    SetTBBTextColor(bar._timerText, cfg, "timer")
    SetTBBTextColor(bar._nameText, cfg, "name")
    SetTBBTextColor(bar._stacksText, cfg, "stacks")

    -- Timer text. Vertical bars honor the same position choices as horizontal: left/right sit OUTSIDE the (thin) bar, top/bottom above/below it, center inside.
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

    -- Spark anchors to the MOVING edge of the fill. With Reverse Fill the fill anchors at the far end and the near edge moves, so the spark side flips.
    bar._lastReverse = cfg.reverseFill and true or false
    if cfg.showSpark then
        local sparkAnchor = (bar._gradientActive and bar._gradClip) or fillTex
        AnchorTBBSpark(bar, cfg, sparkAnchor)
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
        -- Text width + wrap mode (icon's square is not text space). Wrap on: 2 lines within
        -- the text area. Off (default): one line truncated with an ellipsis at 85% of fill width.
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
        -- Border container is a child of the bar: +6 draws in front of the fill AND above
        -- the tick marks at sb+4 (=bar+5, which would tie and lose to the lazily-created
        -- tick overlay); "Show Behind" uses level-1. Set BEFORE ApplyBorderStyle so the textured backdrop inherits it.
        local baseLvl = bar:GetFrameLevel()
        bar._barBorder:SetFrameLevel(cfg.borderBehind and math.max(0, baseLvl - 1) or (baseLvl + 6))
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
        to:SetFrameLevel(sb:GetFrameLevel() + 4)
        bar._tickOverlay = to
    end
    ApplyTBBTickMarks(sb, cfg, bar._threshTicks, isVert, bar._tickOverlay)
    ApplyTBBChargeHashLines(bar, cfg, GetTBBMaxCharges(cfg))
    bar._ticksDirty = true
end

-- Exposed for the options popout preview: preview bars are built and skinned by the SAME code as live bars, so the preview cannot drift from rendering.
ns.CreateTBBBarFrame  = CreateTrackedBuffBarFrame
ns.ApplyTBBBarSettings = ApplyTrackedBuffBarSettings

-------------------------------------------------------------------------------
--  CDM Child Lookup
--  Iterates the BuffBarCooldownViewer pool directly (tiny, 3-5 frames).
--  Matches by cooldownID first (cached on cfg), then by spell ID variants from
--  cooldownInfo. No external caches, no stale data in combat.
-------------------------------------------------------------------------------
-- cfg -> base-spell id seen once, awaiting a confirming second pass before the
-- permanent cfg.baseSpellID write (a pool frame mid-reuse can echo another
-- slot's ids for one pass). Separate table: frame-adjacent state must never
-- ride the config into SavedVariables.
local _tbbBaseCapturePending = {}

local function MatchesSID(info, sid)
    -- cooldownInfo id fields can read SECRET in restricted content, and a
    -- secret on either side of == hard-errors: every compare is gated. sid is
    -- the caller's cfg-side id (plain by contract).
    local isSec = issecretvalue
    if not (isSec and isSec(info.overrideSpellID)) and info.overrideSpellID == sid then return true end
    if not (isSec and isSec(info.spellID)) and info.spellID == sid then return true end
    if info.linkedSpellIDs then
        for _, lid in ipairs(info.linkedSpellIDs) do
            if not (isSec and isSec(lid)) and lid == sid then return true end
        end
    end
    return false
end

local function MatchFrameToConfig(frame, cfg)
    -- Cooldown-tracking bars are self-driven and never bind a viewer frame.
    if cfg.trackType == "cooldown" then return false end
    local cdID = frame.cooldownID
    if not cdID then return false end
    local gci = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
    if not gci then return false end
    local info = gci(cdID)
    if not info then return false end
    -- Self-healing base capture for hero-talent override spells. A bar saved
    -- for the OVERRIDE form, matched while talented, sees the override in
    -- info.overrideSpellID and the BASE form in info.spellID. Record the base
    -- on the config so the bar keeps matching once the talent is removed:
    -- cooldownInfo carries the override id ONLY while talented, so without the
    -- stored base the bar goes dark when untalented (the cast becomes the base
    -- spell). Also backfills bars saved without a pick-time baseSpellID.
    local isSec = issecretvalue
    if cfg.spellID and cfg.spellID > 0 and not cfg.baseSpellID
       and not (isSec and isSec(info.overrideSpellID))
       and not (isSec and isSec(info.spellID))
       and info.overrideSpellID == cfg.spellID
       and info.spellID and info.spellID > 0 and info.spellID ~= cfg.spellID then
        -- Two matching reads on separate passes before committing: the write is
        -- permanent (SavedVariables), so a single transient echo from a frame
        -- mid-reuse must never corrupt the config's identity.
        if _tbbBaseCapturePending[cfg] == info.spellID then
            cfg.baseSpellID = info.spellID
            _tbbBaseCapturePending[cfg] = nil
        else
            _tbbBaseCapturePending[cfg] = info.spellID
        end
    end
    -- Fast path: match via cooldownInfo struct fields.
    if cfg.spellIDs then
        for _, sid in ipairs(cfg.spellIDs) do
            if MatchesSID(info, sid) then return true end
        end
    elseif cfg.spellID and cfg.spellID > 0 then
        if MatchesSID(info, cfg.spellID) then return true end
        -- Talent-override fallback: a bar saved for the override form also tracks its base, so it keeps showing after the talent is removed.
        if cfg.baseSpellID and cfg.baseSpellID > 0 and MatchesSID(info, cfg.baseSpellID) then
            return true
        end
    else
        return false
    end
    -- Fallback: the frame's canonical spell ID. Buff bar frames expose the actual aura
    -- variant via GetAuraSpellID, which may not appear in the cooldownInfo struct (e.g. Eclipse Solar/Lunar).
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
-- Frame cache lives in its own table, NEVER on the config (which is in SavedVariables): frame refs must not leak into serialization.
local _findChildCache = {}

-- Sticky cfg->frame bindings for the one-to-one assignment pass below (cfg table -> last
-- paired Blizzard frame). Separate table for the same serialization reason; dropped on cache invalidation.
local _tbbStickyFrame = {}
-- cooldownID each sticky frame carried when bound: the secret-trust branch can
-- only trust a binding while the pooled frame still serves the same cooldown
-- slot (Blizzard reuses frame objects fast in combat). cooldownID stays a
-- plain readable number in secret windows (the clean-sid cache keys on it).
local _tbbStickyCdID = {}

function ns.InvalidateTBBFrameCache()
    _findChildGeneration = _findChildGeneration + 1
    wipe(_findChildCache)
    wipe(_tbbStickyFrame)
    wipe(_tbbStickyCdID)
    wipe(_tbbBaseCapturePending)
    -- Every structural edge funnels here (pool Acquire, spec swap, rebuilds), so the assignment memo retires with the caches.
    _tbbAssignDirty = true
end

local function FindChild(cfg)
    -- Fast path: cached result from a previous match (hit or miss).
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
--  Required for multi-variant spells like Eclipse: Solar and Lunar share one
--  cooldownInfo (linkedSpellIDs lists both), so per-config FindChild() greedily
--  binds BOTH to whichever frame enumerates first ("Lunar twice, Solar never", and
--  the mirror case). Frame-driven matches the icon viewer: decorate one display per
--  Blizzard child rather than matching a stored spell back to an ambiguous frame.
--
--  Three passes, each only over still-unconsumed frames:
--    1. Sticky   -- reuse last tick's binding. Frame OBJECT identity never goes secret,
--       so a pairing locked out of combat survives GetAuraSpellID turning secret
--       mid-fight; revalidated against a clean read when one exists (self-heals a
--       recycled pool frame), trusted blindly while secret.
--    2. Exact    -- per-frame canonical id == the config's spell (clean reads pair
--       frameSolar->cfgSolar, frameLunar->cfgLunar); locks the sticky binding for future ticks.
--    3. Fallback -- cooldownInfo/linkedSpellIDs struct match for configs still unpaired
--       (combat, no prior sticky binding); consumption still guarantees no two configs land on the same frame.
--
--  Returns a cfg->frame map (a REUSED module table; copy it to retain it).
-------------------------------------------------------------------------------
local _tbbAssignment   = {}
local _tbbFrameScratch = {}
local _tbbConsumed     = {}
local _tbbFrameSID     = {}  -- frame -> canonical spell id, computed once per call
local _tbbFrameMember  = {}  -- frame -> live linked-family member, computed once per call

local function CfgWantsSID(cfg, sid)
    -- Cooldown-tracking bars NEVER match buff-viewer frames or buff coverage.
    if cfg.trackType == "cooldown" then return false end
    if not sid then return false end
    -- Tick paths feed raw aura/struct ids (icon, coverage): a secret survives
    -- the nil check and hard-errors on ==. Narrow matcher: secret = not
    -- provably ours.
    if issecretvalue and issecretvalue(sid) then return false end
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

-- Name FAMILY of a display name: the part before the first colon, lowered
-- ("Diabolic Ritual: Overlord" -> "diabolic ritual"; a name without a colon
-- is its own family). Disambiguates collided viewer slots whose aura names
-- share a canonical spellID but not a prefix. nil for empty/unreadable.
local function TbbNameFamily(name)
    if type(name) ~= "string" or name == "" then return nil end
    local i = name:find(":", 1, true)
    -- zhCN/zhTW labels separate variants with the fullwidth colon (U+FF1A;
    -- decimal byte escapes -- Lua 5.1 has no hex escapes).
    local j = name:find("\239\188\154", 1, true)
    if j and (not i or j < i) then i = j end
    local fam = i and name:sub(1, i - 1) or name
    fam = fam:gsub("^%s+", ""):gsub("%s+$", ""):lower()
    if fam == "" then return nil end
    return fam
end

-- Live aura name family of a pool frame; nil when no clean aura read exists
-- (secret in restricted content, no bound instance) -- callers fall back to
-- first-match. Aura reads are the ONLY name source: never the frame's label.
local function TbbFrameNameFamily(frame)
    local iid = frame.auraInstanceID
    if not iid or (issecretvalue and issecretvalue(iid)) then return nil end
    local unit = frame.auraDataUnit
    if not unit then return nil end
    local ok, ad = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, iid)
    if not ok or not ad then return nil end
    local nm = ad.name
    if nm == nil or (issecretvalue and issecretvalue(nm)) then return nil end
    return TbbNameFamily(nm)
end

-- Which member of a LINKED FAMILY a buff slot is mirroring right now. Blizzard
-- binds ONE cooldownID to whichever of its linkedSpellIDs is on the player and
-- publishes the answer as cooldownInfo.linkedSpellID, maintained on the aura
-- edges (CooldownViewerItemMixin:NeedsAddedAuraUpdate / OnUnitAuraRemovedEvent),
-- so Roll the Bones cycles a single slot through every outcome and the hint
-- follows. Needed because GetSpellID()/GetAuraSpellID() read secret while the
-- slot is active, leaving the canonical resolver to answer from the clean-read
-- memo keyed on cooldownID, which still names the member that was up at the last
-- CLEAN read: the previous outcome keeps the frame and mirrors the new outcome's
-- timer while the new outcome draws a second bar off the per-spell aura fallback.
local function TbbLinkedMemberSID(frame)
    local info = frame.cooldownInfo
    if not info then
        local fnGetInfo = frame.GetCooldownInfo
        if type(fnGetInfo) ~= "function" then return nil end
        info = fnGetInfo(frame)
    end
    local linked = info and info.linkedSpellIDs
    if type(linked) ~= "table" or #linked < 2 then return nil end
    -- Set from the added aura's spellId, so it can be secret in restricted content.
    local sid = info.linkedSpellID
    if type(sid) ~= "number" or (issecretvalue and issecretvalue(sid)) then return nil end
    return sid
end

-- Per-config name families for label/binding compatibility: cfg.name (the
-- picker's display name) plus the resolved spellID/baseSpellID names.
-- Weak-keyed memo; every input is re-checked on hit so options edits
-- self-invalidate, and entries with unloaded spell data retry until resolved
-- (same class as the deferred name fill).
local _tbbCfgFamilies = setmetatable({}, { __mode = "k" })

local function TbbCfgFamilies(cfg)
    local e = _tbbCfgFamilies[cfg]
    if e and not e.retry and e.nm == cfg.name and e.sid == cfg.spellID
       and e.bsid == cfg.baseSpellID then
        return e
    end
    if not e then e = {}; _tbbCfgFamilies[cfg] = e end
    e.nm, e.sid, e.bsid = cfg.name, cfg.spellID, cfg.baseSpellID
    e.retry = nil
    e.f1 = TbbNameFamily(cfg.name)
    e.f2, e.f3 = nil, nil
    if cfg.spellID and cfg.spellID > 0 then
        local si = C_Spell.GetSpellInfo(cfg.spellID)
        if si and si.name then e.f2 = TbbNameFamily(si.name) else e.retry = true end
    end
    if cfg.baseSpellID and cfg.baseSpellID > 0 then
        local si = C_Spell.GetSpellInfo(cfg.baseSpellID)
        if si and si.name then e.f3 = TbbNameFamily(si.name) else e.retry = true end
    end
    return e
end

-- Two families are compatible when equal or one extends the other ("eclipse"
-- vs "eclipse (solar)") -- variant naming keeps the base name as a prefix,
-- while different abilities ("spirit walk" vs "spirit wolf") never do.
local function TbbFamiliesCompatible(a, b)
    if not a or not b then return false end
    if a == b then return true end
    return a:find(b, 1, true) == 1 or b:find(a, 1, true) == 1
end

-- fam vs ANY of the config's known families. openOnUnknown decides the
-- verdict when either side is unknowable (the label gate fails OPEN to
-- today's behavior; variant evidence fails CLOSED).
local function TbbCfgFamilyMatch(cfg, fam, openOnUnknown)
    local e = TbbCfgFamilies(cfg)
    local f1, f2, f3 = e.f1, e.f2, e.f3
    if fam == nil or not (f1 or f2 or f3) then return openOnUnknown end
    return TbbFamiliesCompatible(fam, f1) or TbbFamiliesCompatible(fam, f2)
        or TbbFamiliesCompatible(fam, f3)
end

-- cooldownID -> definite "variant-labeled slot" verdict, session-long (cdIDs
-- are stable per session; verdicts only come from fully readable inputs). A
-- slot is variant-labeled when its linked forms resolve to MORE THAN ONE
-- distinct display string (Diabolist ritual trios, Eclipse Solar/Lunar) --
-- the only case where a SECRET label can say something the config name
-- cannot. Field 2026-08: a hidden pool frame can render another slot's text
-- persistently after re-acquire, so unproven slots never paint secret labels.
local _tbbVariantSlot = {}

local function TbbSlotVariantLabeled(bar, cdID)
    if type(cdID) ~= "number" or (issecretvalue and issecretvalue(cdID)) then
        return false
    end
    local known = _tbbVariantSlot[cdID]
    if known ~= nil then return known end
    -- In combat one indefinite probe is pinned per binding (secret linked ids
    -- would otherwise re-derive at 60Hz); out of combat retries until the
    -- verdict is definite (spell data load is the only wait).
    if bar._varProbeCd == cdID and InCombatLockdown() then
        return bar._varProbeVal or false
    end
    local verdict, complete = false, false
    if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local ok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cdID)
        if ok and info then
            local isSec = issecretvalue
            local lids = info.linkedSpellIDs
            if not lids or #lids == 0 then
                -- No linked forms at all: definitively single-labeled.
                _tbbVariantSlot[cdID] = false
                return false
            end
            complete = true
            local baseNm
            local bsid = info.spellID
            if bsid and not (isSec and isSec(bsid)) then
                local si = C_Spell.GetSpellInfo(bsid)
                local nm = si and si.name
                if nm and not (isSec and isSec(nm)) then baseNm = nm:lower() end
            end
            if not baseNm then complete = false end
            local firstNm
            for k = 1, #lids do
                local lid = lids[k]
                local nm
                if type(lid) == "number" and not (isSec and isSec(lid)) then
                    local si = C_Spell.GetSpellInfo(lid)
                    nm = si and si.name
                    if nm and (isSec and isSec(nm)) then nm = nil end
                end
                if not nm then
                    complete = false
                else
                    nm = nm:lower()
                    if baseNm and nm ~= baseNm then verdict = true; break end
                    if firstNm == nil then
                        firstNm = nm
                    elseif nm ~= firstNm then
                        verdict = true; break
                    end
                end
            end
        end
    end
    if verdict or complete then
        _tbbVariantSlot[cdID] = verdict
    else
        bar._varProbeCd, bar._varProbeVal = cdID, verdict
    end
    return verdict
end

-- Pass-3 candidate veto: a fuzzy struct match (linked-group membership) can
-- be a mechanically different neighbor -- Blizzard links Spirit Walk into the
-- Spirit Wolf slot's group, and with Spirit Walk's own frame inactive the
-- neighbor is the UNIQUE match (field 2026-08). A READABLE live aura name
-- that is family-incompatible with the config rejects the candidate;
-- secret/unreadable fails open so variant slots stay bindable in combat.
local function TbbFuzzyNameOK(cfg, frame)
    local fam = TbbFrameNameFamily(frame)
    if not fam then return true end
    return TbbCfgFamilyMatch(cfg, fam, true)
end

local function AssignFramesToConfigs(bars)
    local assignment = _tbbAssignment
    -- Memo: pairing moves only on composition edges (player aura events, pool
    -- Acquire, cache invalidation, rebuilds -- all set the dirty flag), so the
    -- ~60Hz tick reuses the last map instead of re-enumerating the pool and
    -- re-resolving canonical ids every frame. Bars-table identity check is the
    -- belt for spec swaps that replace the table without hitting an invalidation site.
    if not _tbbAssignDirty and _tbbAssignedFor == bars then
        return assignment
    end
    _tbbAssignDirty = false
    _tbbAssignedFor = bars
    wipe(assignment)
    if not bars then return assignment end

    local viewer = _G["BuffBarCooldownViewer"]
    if not viewer or not viewer.itemFramePool then return assignment end

    -- Snapshot the active pool once (EnumerateActive consumes the enumeration) and
    -- resolve each frame's canonical spell id ONCE -- otherwise the passes below
    -- re-query it O(configs x frames) per tick, each call pcalling live frame APIs.
    -- Caching also gives every pass a consistent within-tick view of frame identity.
    local GetCanonical = ns.GetCanonicalSpellIDForFrame
    local frames = _tbbFrameScratch
    wipe(frames)
    wipe(_tbbFrameSID)
    wipe(_tbbFrameMember)
    for frame in viewer.itemFramePool:EnumerateActive() do
        frames[#frames + 1] = frame
        _tbbFrameSID[frame] = GetCanonical and GetCanonical(frame) or nil
        if frame.IsActive and frame:IsActive() then
            _tbbFrameMember[frame] = TbbLinkedMemberSID(frame)
        end
    end

    -- The family hint overrides the canonical memo only where (1) some enabled
    -- bar actually WANTS the member: a single bar tracking the family under
    -- its base/shared id must keep its per-slot memo, or the flip releases a
    -- working binding for nothing (claim-style gate; also keeps shared-id
    -- configs like Diabolist's on their memos if a variant stamp ever reads
    -- clean), and (2) it is UNIQUE among the active slots: collided slots each
    -- list the whole family (Eclipse Solar and Lunar, both up), so an added
    -- aura stamps the same member on BOTH and only their per-slot memos still
    -- tell them apart.
    for i = 1, #frames do
        local m = _tbbFrameMember[frames[i]]
        if m then
            local wanted = false
            for _, c in ipairs(bars) do
                if CfgWantsSID(c, m) then wanted = true; break end
            end
            local unique = wanted
            if unique then
                for j = 1, #frames do
                    if j ~= i and _tbbFrameMember[frames[j]] == m then unique = false; break end
                end
            end
            if unique then _tbbFrameSID[frames[i]] = m end
        end
    end

    local consumed = _tbbConsumed
    wipe(consumed)

    -- Pass 1: sticky.
    for _, cfg in ipairs(bars) do
        local bound = _tbbStickyFrame[cfg]
        -- A bar converted to cooldown tracking must release its old viewer-frame binding
        -- immediately: the secret-trust branch below never calls CfgWantsSID, so otherwise it would keep consuming the frame.
        if bound and cfg.trackType == "cooldown" then
            _tbbStickyFrame[cfg] = nil
            bound = nil
        end
        if bound and not consumed[bound] and FrameIsActive(frames, bound) then
            local sid = _tbbFrameSID[bound]
            if sid then
                -- Clean read available: keep only if still the right variant AND
                -- (collided slots) still the right name family -- a crossed
                -- pairing must release here or pass 2 can never re-pair it.
                local keep = CfgWantsSID(cfg, sid)
                if keep then
                    local want = TbbNameFamily(cfg.name)
                    if want then
                        local fam = TbbFrameNameFamily(bound)
                        if fam and fam ~= want then keep = false end
                    end
                end
                if keep then
                    assignment[cfg]      = bound
                    consumed[bound]      = true
                    _tbbStickyCdID[cfg]  = bound.cooldownID
                else
                    _tbbStickyFrame[cfg] = nil
                    _tbbStickyCdID[cfg]  = nil
                end
            elseif bound.cooldownID == _tbbStickyCdID[cfg] then
                -- Secret/combat, but the frame still serves the cooldown slot it
                -- was bound under: trust the binding locked in earlier.
                assignment[cfg] = bound
                consumed[bound] = true
            else
                -- Same frame object, different cooldown slot (pool reused it
                -- mid-secret-window) -- a stale binding here is exactly the
                -- wrong-name/wrong-icon report; drop it rather than guess.
                _tbbStickyFrame[cfg] = nil
                _tbbStickyCdID[cfg]  = nil
            end
        end
    end

    -- Pass 2: exact per-frame identity. COLLIDED slots (two viewer slots
    -- sharing one canonical spellID -- Diabolist Demonic Art vs Diabolic
    -- Ritual, where Blizzard hands the Art slot the Ritual's id) fit two
    -- configs identically by sid, and a first-match pairing crosses them
    -- ("Diabolic Ritual" bar bound to the Art frame, faithfully naming
    -- Overlord). Tie-break by NAME FAMILY: the config keeps the picker's
    -- display name and the two slots' aura names differ by prefix, so among
    -- sid-matching frames the one whose live aura name shares the config
    -- name's prefix wins; unique matches take the fast path unchanged.
    for _, cfg in ipairs(bars) do
        if not assignment[cfg] then
            local pick
            local want = TbbNameFamily(cfg.name)
            for i = 1, #frames do
                local frame = frames[i]
                if not consumed[frame] then
                    local sid = _tbbFrameSID[frame]
                    if sid and CfgWantsSID(cfg, sid) then
                        if not want then pick = frame; break end
                        local fam = TbbFrameNameFamily(frame)
                        if fam == want then pick = frame; break end
                        -- Family unreadable/other: remember the first, keep looking
                        -- for a frame that actually names this config's family.
                        if not pick then pick = frame end
                    end
                end
            end
            if pick then
                assignment[cfg]      = pick
                consumed[pick]       = true
                _tbbStickyFrame[cfg] = pick
                _tbbStickyCdID[cfg]  = pick.cooldownID
            end
        end
    end

    -- Pass 3: cooldownInfo/linkedSpellIDs struct fallback. NEVER sticky a fuzzy
    -- match: let a later clean read re-pair it exactly in pass 2. Binds only
    -- when the match is unique BOTH ways (one frame fits this cfg, and no other
    -- unassigned cfg fits that frame) -- shared linkedSpellIDs data makes fuzzy
    -- matches ambiguous, and a guessed pairing is worse than a blank bar.
    for _, cfg in ipairs(bars) do
        if not assignment[cfg] then
            local candidate, matches = nil, 0
            for i = 1, #frames do
                local frame = frames[i]
                if not consumed[frame] and MatchFrameToConfig(frame, cfg)
                   and TbbFuzzyNameOK(cfg, frame) then
                    matches = matches + 1
                    candidate = frame
                end
            end
            if matches == 1 then
                local cfgMatches = 0
                for _, other in ipairs(bars) do
                    if not assignment[other] and MatchFrameToConfig(candidate, other)
                       and TbbFuzzyNameOK(other, candidate) then
                        cfgMatches = cfgMatches + 1
                    end
                end
                if cfgMatches == 1 then
                    assignment[cfg]     = candidate
                    consumed[candidate] = true
                end
            end
        end
    end

    return assignment
end
ns.AssignTBBFramesToConfigs = AssignFramesToConfigs

--- Frame-based check: is a spellID present in BuffBarCooldownViewer? Iterates the tiny pool
--- (~3-5 frames), matching via MatchesSID across all fields (overrideSpellID, spellID, linkedSpellIDs).
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

--- Enumerate all spells in BuffBarCooldownViewer ("Tracked Bars") as {spellID, cdID, name,
--- icon} sorted by layoutIndex then name. Source of truth for the TBB spell picker: TBB IS
--- our display of these bars, so the picker enumerates THIS pool, never the Tracked Buffs icon viewer.
function ns.GetTrackedBarSpells(includeUntalented)
    local result = {}
    local GetCanonical = ns.GetCanonicalSpellIDForFrame
    local seen = {}

    -- Display name plus subtext (e.g. "Solar", "Lunar") to disambiguate spells sharing a base name like Eclipse.
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
                        -- Live pool members are always learned; catalog entries appended below may not be.
                        isKnown     = true,
                    }
                end
            end
        end
    end

    -- Tracked-but-untalented bar spells have no live BuffBar frame, so pull them from the
    -- settings catalog (TrackedBar category). Picker-only (includeUntalented); auto-add and
    -- section checks stay live-only. Provider down/names missing -> nothing appended. Dedup
    -- by canonical sid, same as the live-pool dedup above.
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
                            -- No live frame -> no layoutIndex; sort after live entries, keeping catalog order among themselves.
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
--  Auto-add: opt-in per group ("Auto-Add New to This Group"). While a group holds
--  the flag, any spell newly appearing in Blizzard's Tracked Bars section gets a
--  bar in that group; turning the flag ON populates a bar for every currently
--  tracked spell. Deleted bars stay deleted -- their spells remain in the
--  tbb.autoSeen ledger; only the populate-on-enable pass ignores it ("give me everything").
-------------------------------------------------------------------------------
local function SpellCoveredByBars(bars, sp)
    -- Variant/override coverage: a bar saved for one form covers the whole linked set
    -- (base/override/aura variants share a cooldownInfo), so an Eclipse Solar bar is not
    -- duplicated when Lunar's frame appears under a talent-swapped id.
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

-- Shared guards for both auto-add passes. Returns the tbb table, or nil when the pass must not run right now.
local function AutoAddReady()
    if not (ECME and ECME.db) then ECME = ns.ECME end
    if not (ECME and ECME.db) then return nil end
    local p = ECME.db.profile
    if p.cdmBars and p.cdmBars.useBlizzardBuffBars then return nil end
    if InCombatLockdown() then return nil end
    return ns.GetTrackedBuffBars()
end

-- Worker: create a bar in `gid` for every tracked spell not covered by an existing bar.
-- `ignoreSeen` = full populate (enable pass); otherwise only never-seen spells count, so deleted bars stay deleted.
local function AutoAddTrackedToGroup(tbb, gid, ignoreSeen)
    local tracked = ns.GetTrackedBarSpells and ns.GetTrackedBarSpells() or {}
    -- An empty list also means "viewer not populated yet" (login order): nothing to act on either way.
    if #tracked == 0 then return 0 end
    -- Postpone while any pool frame's spell identity is unresolved (login spell-data races):
    -- acting on a partial list could later mis-read a long-tracked spell as "new".
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
                -- Base-form capture for talent-override spells (same as the picker): keeps the bar matching once the talent is removed.
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

-- Incremental pass: bars for spells newly appearing in the Tracked Bars section, routed to
-- the flagged group. Returns bars added (configs only; callers rebuild); no-op unless a group opted in.
function ns.EnsureTBBAutoBars()
    local tbb = AutoAddReady()
    if not tbb then return 0 end
    local gid = ns.TBBAutoAddGroupID()
    if not gid then return 0 end
    return AutoAddTrackedToGroup(tbb, gid, false)
end

-- Full populate for the moment "Auto-Add New to This Group" is switched ON: one bar per tracked spell not already covered somewhere, ledger ignored.
function ns.PopulateTBBAutoAddGroup(gid)
    if not gid or gid == 0 then return 0 end
    local tbb = AutoAddReady()
    if not tbb then return 0 end
    return AutoAddTrackedToGroup(tbb, gid, true)
end

-- Debounced entry point for the buff-bar viewer pool hooks: a spell dragged into Blizzard's
-- Tracked Bars section acquires a new pool frame and lands here. Combat acquires are skipped
-- (tracked-set edits happen out of combat; mid-fight acquires are just known auras activating).
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

--- Frame-based check: is a spellID present in Essential or Utility viewers? Same pattern as IsSpellInBuffBarViewer but for CD/Utility bars.
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
-- Applications count for a Blizzard child, avoiding the aura-instance query where
-- possible: the child's auraDataCached table reads without erroring on every client,
-- its applications field is plain on live and secret under the 12.1 combat
-- restriction, and both feed StatusBar:SetValue/FontString:SetText natively. The
-- instance-id query is the fallback for an unpopulated cache and HARD-ERRORS on 12.1
-- restricted units, hence the pcall and the secret-iid guard.
local function ReadStackApplications(blzChild)
    local ad = blzChild.auraDataCached
    if ad and ad.applications then return ad.applications end
    local auraInstID = blzChild.auraInstanceID
    local auraUnit = blzChild.auraDataUnit
    if auraInstID and auraUnit and not issecretvalue(auraInstID) then
        local ok, d = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, auraUnit, auraInstID)
        if ok and d and d.applications then return d.applications end
    end
    return nil
end

local function UpdateStacks(bar, blzChild, cfg)
    -- Stack-based fill needs a live count even when Blizzard renders no Applications text
    -- (hidden at 1 stack), plus a restricted marker so the fill site fails open instead of an empty bar.
    local stackFill = cfg and cfg.stackBasedBar and cfg.trackType ~= "cooldown"
        and cfg.stackThresholdMaxEnabled
    bar._stackUnreadable = nil
    if stackFill and blzChild then
        -- Stack-based bar: skip the Blizzard text mirror (blank below 2 stacks) and drive
        -- fill/text from the aura data. This helper only runs for active frames, so the aura is
        -- up and a readable count floors at 1; a secret count passes through to SetValue/SetText untouched.
        local apps = ReadStackApplications(blzChild)
        if apps then
            if not issecretvalue(apps) and apps < 1 then apps = 1 end
            bar._stackCount = apps
            if bar._stacksText then
                if bar._stacksHidden then
                    bar._stacksText:Hide()
                else
                    bar._stacksText:SetText(apps)
                    bar._stacksText:Show()
                end
            end
        else
            -- No cached aura table and no readable instance id: count is unknowable, so the fill site fails open.
            bar._stackCount = 0
            bar._stackUnreadable = true
            if bar._stacksText then bar._stacksText:Hide() end
        end
        return
    end
    -- Read stacks from blzChild.Icon.Applications FontString.
    if blzChild and blzChild.Icon and blzChild.Icon.Applications then
        -- NEVER compare the text (it may be secret); SetText takes it natively.
        local ok, txt = pcall(blzChild.Icon.Applications.GetText, blzChild.Icon.Applications)
        if ok and txt then
            -- _stacksHidden (Stacks Position: None) gates every writer lane:
            -- this helper runs for EVERY active bar once ANY bar wants stacks
            -- (_anyStacks is a global gate), so an unguarded show here painted
            -- stacks onto bars that disabled them.
            if bar._stacksText and not bar._stacksHidden then
                bar._stacksText:SetText(txt)
                bar._stacksText:Show()
            elseif bar._stacksText then
                bar._stacksText:Hide()
            end
            -- Stack count for the threshold overlay: applications can be a secret number we
            -- cannot compare, but the overlay consumes it via SetValue (FeedTBBThresholdOverlay), which accepts secrets.
            bar._stackCount = ReadStackApplications(blzChild) or 0
            return
        end
    end
    -- Fallback: top-level Applications (BuffIcon children)
    if blzChild and blzChild.Applications and blzChild.Applications:IsShown() then
        local appsText = blzChild.Applications.Applications
        if appsText then
            local ok, txt = pcall(appsText.GetText, appsText)
            if ok and txt and (issecretvalue(txt) or txt ~= "") then
                if bar._stacksText and not bar._stacksHidden then
                    bar._stacksText:SetText(txt)
                    bar._stacksText:Show()
                end
                bar._stackCount = ReadStackApplications(blzChild) or 0
                return
            end
        end
    end
    -- No stacks text
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

--- Start or update the pandemic glow on a bar. Caller checks the threshold and drives alpha from the tick (smooth fade on remaining%).
local function UpdatePandemic(bar, cfg)
    -- Glow always wraps the whole bar: the overlay covers the entire wrapFrame footprint, so an enabled icon is included rather than glowed alone.
    local glowTarget = bar._pandemicGlowOverlay

    local style = cfg.pandemicGlowStyle or 1
    -- Only pixel glow (1) and autocast (4) render on the bar rectangle
    if style ~= 1 and style ~= 4 then style = 1 end

    -- Start/restart glow on style or target change
    if not bar._pandemicGlowActive or bar._pandemicGlowStyleIdx ~= style
       or bar._pandemicGlowTarget ~= glowTarget then
        if bar._pandemicGlowActive and bar._pandemicGlowTarget
           and bar._pandemicGlowTarget ~= glowTarget then
            StopGlow(bar._pandemicGlowTarget)
        end
        local c
        if cfg.pandemicGlowMode == "class" then
            c = EllesmereUI.GetClassColor(EllesmereUI._playerClass)
        elseif cfg.pandemicGlowMode == "custom" then
            c = cfg.pandemicGlowColor
        end
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
        StartGlow(glowTarget, style, c and c.r, c and c.g, c and c.b, glowOpts)
        bar._pandemicGlowActive   = true
        bar._pandemicGlowStyleIdx = style
        bar._pandemicGlowTarget   = glowTarget
    end

end

-------------------------------------------------------------------------------
--  Blizzard Bar FontString Discovery: finds the name/timer FontStrings on a Blizzard
--  Bar StatusBar and caches the refs externally (zero alloc after the first call).
-------------------------------------------------------------------------------
local function GetBlizzBarFontStrings(blizzBar)
    if not blizzBar then return nil, nil end
    local cached = _blizzBarFS[blizzBar]
    if cached and cached.nameFS then
        return cached.nameFS, cached.timerFS
    end
    -- Discover by iterating regions. The StatusBar has exactly 2 FontStrings: 1st = spell name, 2nd = timer text.
    local nameFS, timerFS
    local fsIdx = 0
    for _, rgn in pairs({ blizzBar:GetRegions() }) do
        if rgn:GetObjectType() == "FontString" then
            fsIdx = fsIdx + 1
            if fsIdx == 1 then nameFS = rgn end
            if fsIdx == 2 then timerFS = rgn end
        end
    end
    -- External cache (false = "searched, not found"), never on the Blizzard frame
    local d = BBFS(blizzBar)
    d.nameFS  = nameFS or false
    d.timerFS = timerFS or false
    return nameFS, timerFS
end

-------------------------------------------------------------------------------
--  EffectiveIconSpellID
--  Which spell id's ICON represents a config right now. cfg.spellID is the pick-time
--  form; talents can override it to a different form with a different icon
--  (C_Spell.GetOverrideSpell), and a bar saved for an override form loses that form
--  when untalented (only its base stays known). Icon FALLBACK paths only -- a bound
--  Blizzard frame or live aura data wins when available.
-------------------------------------------------------------------------------
local function EffectiveIconSpellID(cfg)
    local sid = cfg.spellID
    if not sid or sid <= 0 then return nil end
    -- Saved form currently overridden by a talent: show the override's icon.
    if C_Spell and C_Spell.GetOverrideSpell then
        local ov = C_Spell.GetOverrideSpell(sid)
        if type(ov) == "number" and ov > 0 and ov ~= sid then return ov end
    end
    -- Saved the override form, now untalented: the saved form is no longer known but its captured base is, so show the base form's icon.
    if cfg.baseSpellID and cfg.baseSpellID > 0 and IsPlayerSpell
       and not IsPlayerSpell(sid) and IsPlayerSpell(cfg.baseSpellID) then
        return cfg.baseSpellID
    end
    return sid
end

-- Cooldown-bar spell resolution. Charge Hash Lines needs a STABLE identity (segment math
-- breaks if the tracked id flips to a proc override mid-recharge), so bars with that toggle
-- resolve via StableCooldownSpellID; every other cooldown bar follows overrides via EffectiveIconSpellID.
local function CooldownBarSpellID(cfg)
    if cfg and cfg.chargeHashLines == true then
        return StableCooldownSpellID(cfg)
    end
    return EffectiveIconSpellID(cfg)
end

-- Mirror the 12.1 engine-written decimal timer string (hidden FS on the aura slot
-- button; see EllesmereUICdmTbbDecimals.lua) onto the bar's timer FS. SECRET RULES:
-- the slot button's IsShown() is a SECRET BOOLEAN (aura presence) -- never test it in
-- Lua, route through engine-side SetAlphaFromBoolean (present->1, gone->0) so a stale
-- string can never be visible on a filter miss. The engine string may itself be
-- secret: nil-check via type tag only, SetText accepts secret strings. Returns true
-- only when a string was written AND the alpha gate applied (failure degrades
-- precision, never accuracy); bar._tbbAlphaGated tracks the gate so the fallback
-- path never inherits a stuck alpha-0 FS.
local function MirrorEngineTimer(bar, cfg)
    local engBtn = bar._tbbEngineText
    if not engBtn then return false end
    local out = bar._timerText
    local engFS = bar._tbbEngineFS
    local wrote = false
    if cfg.showTimer and out and engFS then
        local ok, txt = pcall(engFS.GetText, engFS)
        if ok and type(txt) ~= "nil" then
            wrote = (pcall(out.SetText, out, txt))
        end
    end
    -- Alpha gate is best-effort: every call site has already established aura presence
    -- (viewer isActive/a live aura read), so a missing setter must not disable the mirror itself.
    if wrote and out.SetAlphaFromBoolean then
        pcall(out.SetAlphaFromBoolean, out, engBtn:IsShown(), 1, 0)
        bar._tbbAlphaGated = true
    elseif bar._tbbAlphaGated then
        if out then out:SetAlpha(1) end
        bar._tbbAlphaGated = nil
    end
    return wrote
end

--- Does a TBB config have a matching frame in BuffBarCooldownViewer? Uses FindChild
--- (frame-based MatchFrameToConfig) rather than spell-ID cache lookups, so it is robust against ID mismatches.
local function IsTrackedInCDM(cfg)
    return FindChild(cfg) ~= nil
end

-------------------------------------------------------------------------------
--  Bloodlust / Heroism duration bar (debuff-driven, self-timed)
--  The lust buff is cast by others and is secret, so it can't be mirrored from a
--  Blizzard buff-bar child. Watch ONLY the player's Sated/Exhaustion debuff
--  (player-only UNIT_AURA, NEVER a global scan) and start a 40s bar on its rising
--  edge. No login/reload reconstruction: reloading mid-lust gives no bar (debuff
--  was not just acquired). Matching preset: popularKey == "bloodlust".
-------------------------------------------------------------------------------
local SATED_DEBUFFS = { 57723, 57724, 80354, 95809, 160455, 264689, 390435 }
local _lustExpiry   = 0
local _satedPresent = false
local _satedSince                 -- GetTime() of the rise this listener armed on (nil = unknown age)
local _lustZoneGuard = 0          -- suppress rising edges until this time (set on zone-in)
local _lustListenerActive = false -- baseline _satedPresent only on (re)enable, not every rebuild
local _lustListener

local function _playerHasSated()
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return false end
    for i = 1, #SATED_DEBUFFS do
        -- Querying a KNOWN spellID returns the aura even when its fields are secret in
        -- combat, so the edge is detected mid-fight; the (possibly secret) spellID is never read back.
        if C_UnitAuras.GetPlayerAuraBySpellID(SATED_DEBUFFS[i]) then return true end
    end
    return false
end

-- Toggle the player-only Sated listener. Registered only while a lust bar exists; baselines _satedPresent on enable so it fires only on NEW edges.
local function _ensureLustListener(enable)
    if enable then
        if not _lustListener then
            _lustListener = ns.TakeShell()
            _lustListener:SetScript("OnEvent", function(_, event, _, updateInfo)
                if event == "PLAYER_ENTERING_WORLD" then
                    -- Zone/login aura refresh: re-baseline WITHOUT arming and suppress edges
                    -- briefly. An already-carried Sated debuff (zoning out of a dungeon) must
                    -- never read as a fresh cast and pop a phantom 40s bar in the open world.
                    _satedPresent = _playerHasSated()
                    _satedSince = nil
                    _lustZoneGuard = GetTime() + 1.5
                    return
                end
                if event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" then
                    -- Death strips the lockout debuff, so the 590s pin below has to be
                    -- released here: a wipe followed by a fresh lust would otherwise be
                    -- swallowed for the rest of the window the pin was stamped for.
                    _satedPresent = _playerHasSated()
                    _satedSince = nil
                    return
                end
                -- Nothing but death lifts the lockout early (handled above), so a rise
                -- this listener armed on pins the debuff for the next 590s: skip the
                -- (allocating) aura probe until it can possibly have dropped.
                if _satedPresent and _satedSince and GetTime() < _satedSince + 590 then return end
                local present = _playerHasSated()
                -- Arm ONLY on a genuine incremental application: not a full
                -- aura refresh (zone/login resends every aura), and not inside
                -- the post-zone grace window. The UNIT_AURA payload and its
                -- fields can be SECRET in combat, and boolean use of a secret
                -- errors, so a secret payload is treated as incremental (full
                -- refreshes come from zone/login, covered by the zone guard).
                local isFull = false
                if updateInfo and not issecretvalue(updateInfo) then
                    local v = updateInfo.isFullUpdate
                    if not issecretvalue(v) and v then isFull = true end
                end
                if present and not _satedPresent and not isFull
                    and GetTime() >= _lustZoneGuard then
                    _lustExpiry = GetTime() + 40  -- rising edge: lust just went out
                    _satedSince = GetTime()
                    _tbbWake.Wake()  -- lust can come from other players: no local cast/aura edge is guaranteed
                    -- Drive Custom Auras (icon) lust displays sharing this edge.
                    if ns.SignalLustCast then ns.SignalLustCast() end
                end
                _satedPresent = present
                if not present then _satedSince = nil end
            end)
        end
        -- Baseline ONLY on the OFF->ON transition. Re-baselining on every BuildTrackedBuffBars
        -- (fires during zone changes, sometimes while the aura table is momentarily empty)
        -- could set _satedPresent=false and make the debuff's return look like a cast.
        if not _lustListenerActive then
            _satedPresent = _playerHasSated()
            _satedSince = nil
            _lustListener:RegisterUnitEvent("UNIT_AURA", "player")
            _lustListener:RegisterEvent("PLAYER_ENTERING_WORLD")
            _lustListener:RegisterEvent("PLAYER_DEAD")
            _lustListener:RegisterEvent("PLAYER_ALIVE")
            _lustListenerActive = true
        end
    elseif _lustListener and _lustListenerActive then
        _lustListener:UnregisterAllEvents()
        _lustListenerActive = false
    end
end

-- Arm the shared Sated listener if EITHER a Tracking Bar lust bar OR a Custom Auras (icon)
-- lust display is enabled. Authoritative (scans the DB), safe to call from any rebuild/toggle path.
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
    -- Sibling preset listeners refresh from the same change sites: every add/remove/rebuild path already calls UpdateLustListener.
    if ns.UpdateTimeSpiralListener then ns.UpdateTimeSpiralListener() end
    if ns.UpdatePotionCastListener then ns.UpdatePotionCastListener() end
    if ns.UpdateCooldownCastListener then ns.UpdateCooldownCastListener() end
end

-- Profile-wide smooth-fill switches (Bar Layout > Smooth Bars), resolved ONCE per tick by
-- UpdateTrackedBuffBarTimers for every fill site below. buffs = buff mirrors + self-timed
-- presets (lust/time spiral/potions); cooldowns = trackType=="cooldown" bars; off = values
-- snap (no easing). Defaults: buffs ON, cooldowns OFF (absent keys read that way).
local _smoothBuffs, _smoothCooldowns = true, false

-- Self-driven display for an event-armed, self-timed preset bar (Bloodlust 40s, Time Spiral
-- 10s): fill+timer come from our own countdown, not a Blizzard frame (name/icon are set in
-- BuildTrackedBuffBars). `expiry` = GetTime() the window ends at; `duration` = full window length.
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
        -- Smooth fill is baseline for tracking bars: they move one direction at a known rate
        -- (unlike a health bar, no sudden jump needs instant read), so interpolation only
        -- removes judder. The wasShown gate snaps a fresh appearance instead of animating from a stale value.
        local smooth = _smoothBuffs and wasShown and Enum and Enum.StatusBarInterpolation
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
    return true  -- window active: keep the tick awake
end
local function UpdateLustBar(bar, cfg)
    return _UpdateSelfTimedBar(bar, cfg, _lustExpiry, 40)
end

-------------------------------------------------------------------------------
--  Time Spiral "Free Move" preset (popularKey == "timespiral")
--  Mirrors Bloodlust, but armed off Blizzard's spell-activation glow on the player's
--  class movement ability (free-cast proc) instead of an aura: a whitelisted
--  glow-SHOW starts a self-timed 10s window; like Bloodlust, only a fresh glow arms
--  it, no login/reload reconstruction. Talent-aware suppression drops glows firing on
--  a movement ability for unrelated reasons (DH Inertia/Dash of Chaos, Warlock Soulburn).
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
-- Talent-gated abilities that ALSO glow a movement ability for reasons unrelated to the proc.
-- While the talent is known, casting one suppresses the glow that follows for a short window.
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

-- Toggle the glow listener; registered only while an enabled Time Spiral bar or Custom Auras (icon) display exists. Glow-event spellIDs are never secret.
local function _ensureTimeSpiralListener(enable)
    if enable then
        if not _ts.frame then
            _ts.frame = ns.TakeShell()
            _ts.frame:SetScript("OnEvent", function(_, event, ...)
                if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
                    local sid = ...
                    if not TIME_SPIRAL_TRIGGERS[sid] then return end
                    if GetTime() < _ts.suppressUntil then return end
                    _ts.expiry = GetTime() + TIME_SPIRAL_DURATION  -- free move just granted
                    _tbbWake.Wake()  -- glow edge is outside the sleeper's wake events
                    -- Drive Custom Auras (icon) displays sharing this edge.
                    if ns.SignalTimeSpiralCast then ns.SignalTimeSpiralCast() end
                elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
                    local sid = ...
                    if not TIME_SPIRAL_TRIGGERS[sid] then return end
                    -- Proc consumed or expired: end the window now so bar/icon disappear with
                    -- the glow rather than riding out the full 10s. Guarded on an active window
                    -- so an unrelated trigger's hide cannot fire spuriously.
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

-- Arm the glow listener if EITHER a Time Spiral Tracking Bar OR a Custom Auras (icon) Time Spiral display is enabled. Authoritative (scans the DB).
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
--  Self-cast potion presets (Light's Potential, Potion of Recklessness, Invisibility
--  Potion). NEVER aura-tracked: a hardcoded window starts the moment the potion's
--  spell is cast, matching the CDM buff-bar/Fake-Active potions. Same self-timed model
--  as Bloodlust/Time Spiral -- only a fresh cast arms it, so a reload mid-buff shows
--  nothing until next use. Built from BUFF_BAR_PRESETS: every non-tbbOnly preset
--  (bloodlust/timespiral are tbbOnly, event-driven above) is cast-timed.
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
            _potionFrame = ns.TakeShell()
            -- UNIT_SPELLCAST_SUCCEEDED (player): same edge the CDM buff-bar potions fire on. arg4 = cast spellID (never secret).
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

-- Arm the cast listener only while an enabled potion-preset Tracking Bar exists. Refreshed
-- from the same change sites as the other preset listeners (fanned out from UpdateLustListener).
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

-- True when v is a plain, readable number. A secret value fails BEFORE any type/comparison touches it; nil and non-numbers fail too.
local function _tbbCleanNum(v)
    if issecretvalue and issecretvalue(v) then return false end
    return type(v) == "number"
end

-------------------------------------------------------------------------------
--  Charge hash fill
--  currentCharges is secret in combat, so addon Lua cannot compute (currentCharges +
--  next-recharge progress) / maxCharges. Two invisible native StatusBars supply the
--  geometry instead: one takes Blizzard's charge count directly, one animates exactly
--  one charge-wide segment from the duration object. A single full-size texture is
--  clipped to their combined edge, so the player still sees one continuous bar
--  honoring the texture, gradient, spark, orientation and reverse-fill settings.
-------------------------------------------------------------------------------
local function _ensureTBBChargeHashFill(bar)
    if bar._chargeHashCountBar then return end
    local sb = bar._bar
    if not sb then return end

    local countBar = CreateFrame("StatusBar", nil, sb)
    countBar:SetAllPoints(sb)
    countBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    local countTexture = countBar:GetStatusBarTexture()
    countTexture:SetSnapToPixelGrid(false)
    countTexture:SetTexelSnappingBias(0)
    countBar:SetAlpha(0)
    countBar:EnableMouse(false)
    bar._chargeHashCountBar = countBar
    bar._chargeHashCountTexture = countTexture

    local progressBar = CreateFrame("StatusBar", nil, sb)
    progressBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    local progressTexture = progressBar:GetStatusBarTexture()
    progressTexture:SetSnapToPixelGrid(false)
    progressTexture:SetTexelSnappingBias(0)
    progressBar:SetAlpha(0)
    progressBar:EnableMouse(false)
    bar._chargeHashProgressBar = progressBar
    bar._chargeHashProgressTexture = progressTexture

    local clip = CreateFrame("Frame", nil, sb)
    clip:SetClipsChildren(true)
    clip:SetFrameLevel(sb:GetFrameLevel() + 1)
    clip:Hide()
    bar._chargeHashFillClip = clip

    local fill = clip:CreateTexture(nil, "ARTWORK", nil, 1)
    fill:SetPoint("TOPLEFT", sb, "TOPLEFT", 0, 0)
    fill:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", 0, 0)
    fill:SetSnapToPixelGrid(false)
    fill:SetTexelSnappingBias(0)
    bar._chargeHashFillTexture = fill
end

local function _styleTBBChargeHashFill(bar, cfg)
    local fill = bar._chargeHashFillTexture
    if not fill then return end
    local texPath = bar._lastTexPath or "Interface\\Buttons\\WHITE8x8"
    local fR, fG = bar._baseFillR or _classR, bar._baseFillG or _classG
    local fB, fA = bar._baseFillB or _classB, bar._baseFillA or 1
    local gradientEnabled = cfg.gradientEnabled and true or false
    local gradientDir = cfg.gradientDir or "HORIZONTAL"
    local gR, gG = cfg.gradientR or 0.20, cfg.gradientG or 0.20
    local gB, gA = cfg.gradientB or 0.80, cfg.gradientA or 1
    -- SCALAR style signature: unchanged active bars take this branch without allocating a temporary table/key string every tick.
    if bar._chargeHashFillStyleValid
       and bar._chargeHashFillStyleTexPath == texPath
       and bar._chargeHashFillStyleGradient == gradientEnabled
       and bar._chargeHashFillStyleDirection == gradientDir
       and bar._chargeHashFillStyleR == fR
       and bar._chargeHashFillStyleG == fG
       and bar._chargeHashFillStyleB == fB
       and bar._chargeHashFillStyleA == fA
       and bar._chargeHashFillStyleGradientR == gR
       and bar._chargeHashFillStyleGradientG == gG
       and bar._chargeHashFillStyleGradientB == gB
       and bar._chargeHashFillStyleGradientA == gA then
        return
    end

    fill:SetTexture(texPath)
    fill:ClearAllPoints()
    if gradientEnabled then
        -- Gradients stay mapped across the full bar and are revealed by the moving clip, matching the stock gradient path.
        fill:SetPoint("TOPLEFT", bar._bar, "TOPLEFT", 0, 0)
        fill:SetPoint("BOTTOMRIGHT", bar._bar, "BOTTOMRIGHT", 0, 0)
        fill:SetVertexColor(1, 1, 1, 1)
        local c1 = bar._chargeHashGradientColor1
        local c2 = bar._chargeHashGradientColor2
        if not c1 then
            c1 = CreateColor(fR, fG, fB, fA)
            c2 = CreateColor(gR, gG, gB, gA)
            bar._chargeHashGradientColor1 = c1
            bar._chargeHashGradientColor2 = c2
        else
            c1.r, c1.g, c1.b, c1.a = fR, fG, fB, fA
            c2.r, c2.g, c2.b, c2.a = gR, gG, gB, gA
        end
        fill:SetGradient(gradientDir, c1, c2)
    else
        -- Plain/patterned StatusBar textures stretch with the visible fill.
        fill:SetAllPoints(bar._chargeHashFillClip)
        fill:SetVertexColor(fR, fG, fB, fA)
    end
    bar._chargeHashFillStyleValid = true
    bar._chargeHashFillStyleTexPath = texPath
    bar._chargeHashFillStyleGradient = gradientEnabled
    bar._chargeHashFillStyleDirection = gradientDir
    bar._chargeHashFillStyleR = fR
    bar._chargeHashFillStyleG = fG
    bar._chargeHashFillStyleB = fB
    bar._chargeHashFillStyleA = fA
    bar._chargeHashFillStyleGradientR = gR
    bar._chargeHashFillStyleGradientG = gG
    bar._chargeHashFillStyleGradientB = gB
    bar._chargeHashFillStyleGradientA = gA
end

_restoreTBBNormalFill = function(bar, cfg)
    if not bar._chargeHashFillActive then return end
    if bar._chargeHashFillClip then bar._chargeHashFillClip:Hide() end
    if bar._chargeHashCountBar then bar._chargeHashCountBar:Hide() end
    if bar._chargeHashProgressBar then bar._chargeHashProgressBar:Hide() end

    local sb = bar._bar
    local fillTex = bar._cachedOurFillTex
    if not fillTex and sb then
        fillTex = sb:GetStatusBarTexture()
        bar._cachedOurFillTex = fillTex
    end
    if fillTex then fillTex:SetAlpha(1) end
    if bar._gradientActive and bar._gradClip then bar._gradClip:Show() end
    if cfg.showSpark and fillTex then
        AnchorTBBSpark(bar, cfg, (bar._gradientActive and bar._gradClip) or fillTex)
    end

    bar._chargeHashFillActive = nil
    bar._chargeHashDuration = nil
    -- The stock bar timer is not re-armed while its texture is hidden, so a mid-recharge exit from hash mode must force the original path to refresh.
    bar._cdNeedSet = true
end

local function _updateTBBChargeHashFill(bar, cfg, maxCharges, currentCharges,
        durObj, remaining, duration, wasShown)
    if cfg.chargeHashLines ~= true or type(maxCharges) ~= "number"
       or maxCharges <= 1 then
        return false
    end
    local secretCount = issecretvalue and issecretvalue(currentCharges)
    if not secretCount and type(currentCharges) ~= "number" then return false end
    if not durObj and not (_tbbCleanNum(remaining) and _tbbCleanNum(duration)
       and duration > 0) then
        return false
    end

    _ensureTBBChargeHashFill(bar)
    local sb = bar._bar
    local countBar = bar._chargeHashCountBar
    local progressBar = bar._chargeHashProgressBar
    local countTexture = bar._chargeHashCountTexture
    local progressTexture = bar._chargeHashProgressTexture
    local clip = bar._chargeHashFillClip
    if not sb or not countBar or not progressBar or not countTexture
       or not progressTexture or not clip then return false end

    local isVert = cfg.verticalOrientation and true or false
    local reverse = cfg.reverseFill and true or false
    local orientation = isVert and "VERTICAL" or "HORIZONTAL"
    local barW, barH = sb:GetWidth(), sb:GetHeight()
    -- Direct scalar comparisons name every geometry invalidator while keeping the steady-state update allocation-free.
    if not bar._chargeHashFillGeometryValid
       or bar._chargeHashFillMaxCharges ~= maxCharges
       or bar._chargeHashFillVertical ~= isVert
       or bar._chargeHashFillReverse ~= reverse
       or bar._chargeHashFillBarW ~= barW
       or bar._chargeHashFillBarH ~= barH then
        countBar:SetOrientation(orientation)
        countBar:SetReverseFill(reverse)
        countBar:SetMinMaxValues(0, maxCharges)

        progressBar:ClearAllPoints()
        progressBar:SetOrientation(orientation)
        progressBar:SetReverseFill(reverse)
        progressBar:SetMinMaxValues(0, 1)
        if isVert then
            progressBar:SetHeight(barH / maxCharges)
            if reverse then
                progressBar:SetPoint("TOPLEFT", countTexture, "BOTTOMLEFT", 0, 0)
                progressBar:SetPoint("TOPRIGHT", countTexture, "BOTTOMRIGHT", 0, 0)
            else
                progressBar:SetPoint("BOTTOMLEFT", countTexture, "TOPLEFT", 0, 0)
                progressBar:SetPoint("BOTTOMRIGHT", countTexture, "TOPRIGHT", 0, 0)
            end
        else
            progressBar:SetWidth(barW / maxCharges)
            if reverse then
                progressBar:SetPoint("TOPRIGHT", countTexture, "TOPLEFT", 0, 0)
                progressBar:SetPoint("BOTTOMRIGHT", countTexture, "BOTTOMLEFT", 0, 0)
            else
                progressBar:SetPoint("TOPLEFT", countTexture, "TOPRIGHT", 0, 0)
                progressBar:SetPoint("BOTTOMLEFT", countTexture, "BOTTOMRIGHT", 0, 0)
            end
        end

        clip:ClearAllPoints()
        if isVert then
            if reverse then
                clip:SetPoint("TOPRIGHT", sb, "TOPRIGHT", 0, 0)
                clip:SetPoint("BOTTOMLEFT", progressTexture, "BOTTOMLEFT", 0, 0)
            else
                clip:SetPoint("BOTTOMLEFT", sb, "BOTTOMLEFT", 0, 0)
                clip:SetPoint("TOPRIGHT", progressTexture, "TOPRIGHT", 0, 0)
            end
        else
            if reverse then
                clip:SetPoint("TOPLEFT", progressTexture, "TOPLEFT", 0, 0)
                clip:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", 0, 0)
            else
                clip:SetPoint("TOPLEFT", sb, "TOPLEFT", 0, 0)
                clip:SetPoint("BOTTOMRIGHT", progressTexture, "BOTTOMRIGHT", 0, 0)
            end
        end
        bar._chargeHashFillGeometryValid = true
        bar._chargeHashFillMaxCharges = maxCharges
        bar._chargeHashFillVertical = isVert
        bar._chargeHashFillReverse = reverse
        bar._chargeHashFillBarW = barW
        bar._chargeHashFillBarH = barH
    end

    -- SetValue is a supported secret sink: NEVER inspect or compute with the live count in Lua.
    countBar:SetValue(currentCharges)

    if durObj and progressBar.SetTimerDuration and Enum
       and Enum.StatusBarTimerDirection then
        if bar._cdNeedSet or bar._chargeHashDuration ~= durObj or not wasShown then
            local interp = Enum.StatusBarInterpolation
                and Enum.StatusBarInterpolation.Immediate
            progressBar:SetTimerDuration(durObj, interp,
                Enum.StatusBarTimerDirection.ElapsedTime)
            bar._chargeHashDuration = durObj
        end
    else
        -- Compatibility fallback for clients that expose only clean timing.
        progressBar:SetValue(1 - (remaining / duration))
        bar._chargeHashDuration = nil
    end

    _styleTBBChargeHashFill(bar, cfg)
    local activating = not bar._chargeHashFillActive
    if activating then
        countBar:Show()
        progressBar:Show()
        local fillTex = bar._cachedOurFillTex
        if not fillTex then
            fillTex = sb:GetStatusBarTexture()
            bar._cachedOurFillTex = fillTex
        end
        if fillTex then fillTex:SetAlpha(0) end
        if bar._gradClip then bar._gradClip:Hide() end
        clip:Show()
    end
    if cfg.showSpark and bar._spark then
        -- Anchor to the native progress TEXTURE, not the intermediate clip frame: its moving
        -- edge is the exact visible fill boundary, and skipping the frame's pixel rounding
        -- keeps the spark joined to that edge in both normal and reverse fill.
        AnchorTBBSpark(bar, cfg, progressTexture, true)
        if not bar._spark:IsShown() then bar._spark:Show() end
    end
    bar._chargeHashFillActive = true
    bar._cdNeedSet = nil
    return true
end

-------------------------------------------------------------------------------
--  Cooldown-bar cast mirror. In combat the cooldown APIs keep isActive readable but
--  turn startTime/duration SECRET, which would drop every on-cooldown bar into the
--  shown-full fail-open for the whole fight. So each tracked spell keeps a local
--  { start, dur } mirror of clean numbers: synced from every clean read (out of
--  combat, incl. mid-cooldown) and armed from the player's own cast edge in combat
--  (UNIT_SPELLCAST_SUCCEEDED's spellID arg is never secret). The tick falls back to
--  the mirror when the API turns secret; isActive stays readable, so the bar still
--  ends/hides exactly when the real cooldown does even if the mirror drifts (CDR, resets).
-------------------------------------------------------------------------------
local _cdCast = {}       -- [sid] = { start, dur } live local cooldown mirror
local _cdDurCache = {}   -- [sid] = last clean cooldown/recharge duration seen
local _cdWatch = {}      -- [watched sid] = canonical sid to key the mirror by
local _cdFrame
local _cdActive = false
-- Cooldown-state generation: bumped by SPELL_UPDATE_COOLDOWN/CHARGES/player casts. Bars
-- re-fetch + re-arm their engine duration handle only when this moves; a cached handle keeps
-- ticking down on its own, and only a CDR/reset-adjusted cooldown needs a fresh fetch.
local _cdGen = 0

-- Static base cooldown (ms) as the arm-time seed before any clean read. The API lives
-- ONLY at the global (client-verified: no C_Spell form exists); static data, never secret,
-- but validated anyway since the seed feeds arithmetic.
local function _cdBaseDuration(sid)
    if not GetSpellBaseCooldown then return nil end
    local ms = GetSpellBaseCooldown(sid)
    if _tbbCleanNum(ms) and ms > 0 then return ms / 1000 end
    return nil
end

local function _ensureCooldownCastListener(enable)
    if enable then
        if not _cdFrame then
            _cdFrame = ns.TakeShell()
            _cdFrame:SetScript("OnEvent", function(_, event, _, _, castSid)
                _cdGen = _cdGen + 1
                if event ~= "UNIT_SPELLCAST_SUCCEEDED" then return end
                local spellID = castSid
                if not spellID then return end
                local canon = _cdWatch[spellID]
                if not canon and C_Spell and C_Spell.GetBaseSpell then
                    -- Cast can fire with the override form while the bar watches the base.
                    local base = C_Spell.GetBaseSpell(spellID)
                    if type(base) == "number" then canon = _cdWatch[base] end
                end
                if not canon then return end
                local now = GetTime()
                -- Charge spells: maxCharges is static and stays readable, and the cast just consumed one charge.
                local ch = C_Spell.GetSpellCharges
                    and C_Spell.GetSpellCharges(canon)
                local maxCh = ch and ch.maxCharges
                if not (_tbbCleanNum(maxCh) and maxCh > 1) then maxCh = nil end
                -- NEVER overwrite an unexpired mirror: a plain spell cannot be cast while on
                -- cooldown, and a charge spell cast while already recharging does NOT restart the next charge; only the count drops.
                local m = _cdCast[canon]
                if m and m.dur and (m.start + m.dur) > now then
                    if maxCh and m.charges and m.charges > 0 then
                        m.charges = m.charges - 1
                    end
                    return
                end
                local dur = _cdDurCache[canon] or _cdBaseDuration(canon)
                if dur then
                    if not m then m = {}; _cdCast[canon] = m end
                    m.start = now
                    m.dur = dur
                    if maxCh then
                        -- Cast from full: the first recharge starts now.
                        m.charges = maxCh - 1
                        m.maxCh = maxCh
                    else
                        m.charges = nil
                        m.maxCh = nil
                    end
                end
            end)
        end
        if not _cdActive then
            _cdFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
            _cdFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
            _cdFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
            _cdActive = true
        end
    elseif _cdFrame and _cdActive then
        _cdFrame:UnregisterAllEvents()
        _cdActive = false
    end
end

-- Authoritative (scans the DB): rebuild the watched-spell map and arm the cast listener only
-- while an enabled cooldown-tracking bar exists. Refreshed from the same sites as the other preset listeners.
function ns.UpdateCooldownCastListener()
    wipe(_cdWatch)
    local any = false
    local tbb = ns.GetTrackedBuffBars and ns.GetTrackedBuffBars()
    if tbb and tbb.bars then
        for _, cfg in ipairs(tbb.bars) do
            if cfg.enabled ~= false and cfg.trackType == "cooldown" then
                local canon = CooldownBarSpellID(cfg)
                if canon then
                    any = true
                    -- Every form the cast event could fire with maps to the canonical id the tick keys the mirror by.
                    _cdWatch[canon] = canon
                    if cfg.spellID and cfg.spellID > 0 then
                        _cdWatch[cfg.spellID] = canon
                    end
                    if cfg.baseSpellID and cfg.baseSpellID > 0 then
                        _cdWatch[cfg.baseSpellID] = canon
                    end
                    -- Seed the duration cache NOW: build paths run out of combat where these
                    -- reads are clean. In combat the same reads can be secret and a fresh
                    -- session has no clean tick read yet, so without a seed the combat cast
                    -- could never arm the mirror. Never overwrites a live clean read.
                    if not _cdDurCache[canon] then
                        local seed
                        local ch = C_Spell.GetSpellCharges
                            and C_Spell.GetSpellCharges(canon)
                        local rd = ch and ch.cooldownDuration
                        if _tbbCleanNum(rd) and rd > 0 then seed = rd end
                        if not seed then seed = _cdBaseDuration(canon) end
                        _cdDurCache[canon] = seed
                    end
                end
            end
        end
    end
    _ensureCooldownCastListener(any)
end

-------------------------------------------------------------------------------
--  Cooldown-tracking bar (cfg.trackType == "cooldown"): the stock fill drains with the
--  spell's remaining cooldown. cfg.fillUp inverts that, filling as the cooldown
--  recovers -- it changes only WHICH WAY the value travels, and every fill source
--  below honours it. Reverse Fill is a different thing entirely and composes with
--  it: that mirrors the bar's geometry and never touches the value. Charge Hash
--  Lines instead fill one section per recovered charge while the timer stays the
--  NEXT charge's cooldown, and already fill upward by construction, so fillUp is a
--  no-op there. Stacks text = current charges. Ready (off cooldown/GCD-only/max
--  charges/unknown) counts as INACTIVE for hideWhenInactive; a shown-but-ready bar
--  renders full with no timer, in either direction.
--
--  FILL SOURCE ORDER (each honours cfg.fillUp):
--  1. Engine duration handle (GetSpellCooldownDuration/GetSpellChargeDuration +
--     SetTimerDuration): engine animates the drain and tracks CDR/resets live,
--     secret-proof by construction; timer text reads the handle's remaining (secret
--     in combat, which SetFormattedText accepts).
--  2. Clean API numbers (out of combat): exact pretty timer text, keeps the cast mirror synced.
--  3. Cast mirror (no duration-object API, or secret reads with no handle): clean local
--     dead-reckoning, blind to in-combat CDR, hence last.
--  4. Fail-open: shown-full bar, no text. Secrecy loses precision, never errors.
-------------------------------------------------------------------------------
local function _UpdateCooldownBar(bar, cfg)
    local sid = CooldownBarSpellID(cfg)

    -- remaining/duration: CLEAN numbers only (nil = ready or secret). wantHandle:
    -- which engine duration handle drives the fill ("charge"/"cd"). timingSecret: raw
    -- numbers unreadable, bar NEEDS the handle (or falls back to the mirror). charges:
    -- CLEAN count for logic/overlays; chargesDisplay: maybe-secret count that ONLY
    -- flows into SetFormattedText; hasCharges: clean flag so no secret is ever branched on.
    local remaining, duration, unreadable, wantHandle, timingSecret
    local charges, chargesDisplay, hasCharges
    local maxCharges, chargeCountValue
    if sid then
        local ch = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(sid)
        local maxCh = ch and ch.maxCharges
        if _tbbCleanNum(maxCh) and maxCh > 1 then
            maxCharges = math.floor(maxCh + 0.5)
            -- Charge spell: the bar tracks the next charge's recharge. The recharge-active
            -- flag is the same CLEAN combat signal Max Stacks Glow uses: false only at max
            -- charges, and readable while the count/timing fields are secret.
            local chActive = ch.isActive
            if issecretvalue and issecretvalue(chActive) then
                unreadable = true
            elseif not chActive then
                -- At max charges: ready, and the count is KNOWN without ever touching the secret currentCharges field.
                charges = maxCh
                chargesDisplay = maxCh
                chargeCountValue = maxCh
                hasCharges = true
            else
                -- Recharging (below max).
                wantHandle = "charge"
                local cur = ch.currentCharges
                if _tbbCleanNum(cur) then
                    charges = cur
                end
                chargesDisplay = cur
                chargeCountValue = cur
                hasCharges = true
                local st, du = ch.cooldownStartTime, ch.cooldownDuration
                if _tbbCleanNum(st) and _tbbCleanNum(du) and du > 0 then
                    duration = du
                    remaining = st + du - GetTime()
                    -- Clean read: keep the fallback mirror exact.
                    _cdDurCache[sid] = du
                    local m = _cdCast[sid]
                    if not m then m = {}; _cdCast[sid] = m end
                    m.start = st
                    m.dur = du
                    if charges then m.charges = charges end
                    m.maxCh = maxCh
                else
                    timingSecret = true
                end
            end
        else
            local cd = C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(sid)
            if cd then
                local act, gcd = cd.isActive, cd.isOnGCD
                local isSec = issecretvalue
                if isSec and (isSec(act) or isSec(gcd)) then
                    unreadable = true
                elseif act and not gcd then
                    -- Real cooldown running; a GCD-only spin never drives the bar.
                    wantHandle = "cd"
                    local st, du = cd.startTime, cd.duration
                    if _tbbCleanNum(st) and _tbbCleanNum(du) and du > 0 then
                        duration = du
                        remaining = st + du - GetTime()
                        -- Clean read: keep the fallback mirror exact.
                        _cdDurCache[sid] = du
                        local m = _cdCast[sid]
                        if not m then m = {}; _cdCast[sid] = m end
                        m.start = st
                        m.dur = du
                    else
                        timingSecret = true
                    end
                end
            end
        end
    end
    -- Resolve the engine duration handle (preferred fill source). Fetch+re-arm ONLY when
    -- cooldown state may have changed: the generation bumps on SPELL_UPDATE_COOLDOWN/CHARGES/
    -- player casts, plus a 1s revalidate for eventless adjustments; between those the CACHED
    -- handle serves every tick, ticking down on its own.
    local durObj
    if wantHandle then
        durObj = bar._cdDurObj
        local now = GetTime()
        if durObj == nil
           or bar._cdArmGen ~= _cdGen
           or bar._cdArmSid ~= sid
           or bar._cdArmKind ~= wantHandle
           or now - (bar._cdArmTime or 0) > 1 then
            local fetch
            if wantHandle == "charge" then
                if C_Spell.GetSpellChargeDuration then
                    fetch = C_Spell.GetSpellChargeDuration(sid)
                end
            else
                if C_Spell.GetSpellCooldownDuration then
                    fetch = C_Spell.GetSpellCooldownDuration(sid)
                end
            end
            durObj = fetch
            bar._cdDurObj = fetch
            bar._cdArmGen = _cdGen
            bar._cdArmSid = sid
            bar._cdArmKind = wantHandle
            bar._cdArmTime = now
            -- The bar timer must be re-set from the fresh handle.
            bar._cdNeedSet = fetch ~= nil
        end
    else
        bar._cdDurObj = nil
    end
    if timingSecret and not durObj then unreadable = true end

    -- Combat-secrecy fallback: timing went secret but the cast mirror holds clean local
    -- numbers, so drive the drain from those instead of shown-full fail-open (expired/absent mirror keeps the fail-open).
    if unreadable and sid then
        local m = _cdCast[sid]
        if m and m.dur then
            local now = GetTime()
            local rem = m.start + m.dur - now
            -- Charge model: an expiry means one charge finished and the next recharge began
            -- at that exact moment, so advance in place. The clean at-max flag above already
            -- ends the bar when the spell truly tops off; still recharging here means the
            -- model ran ahead, so hold one below max and keep draining.
            if m.maxCh and m.charges then
                local guard = m.maxCh + 1
                while rem <= 0 and guard > 0 do
                    m.charges = m.charges + 1
                    if m.charges >= m.maxCh then m.charges = m.maxCh - 1 end
                    m.start = m.start + m.dur
                    if m.start > now then m.start = now end
                    rem = m.start + m.dur - now
                    guard = guard - 1
                end
            end
            if rem > 0 then
                remaining = rem
                duration = m.dur
                unreadable = nil
                if m.charges then
                    charges = m.charges
                    chargesDisplay = m.charges
                    hasCharges = true
                end
            end
        end
    end

    if remaining and remaining <= 0 then remaining = nil; duration = nil end

    -- Clean ready: drop the mirror so a stale window can never resurrect. A live duration
    -- handle means ON cooldown with secret timing (not ready), so the mirror stays in that case.
    if sid and not unreadable and remaining == nil and not durObj then
        _cdCast[sid] = nil
    end

    local onCooldown = (remaining ~= nil) or (durObj ~= nil) or unreadable

    local hashChargeMode = cfg.chargeHashLines == true
        and type(maxCharges) == "number" and maxCharges > 1
    if bar._bar then
        ApplyTBBChargeHashLines(bar, cfg, maxCharges)
    end

    -- No pandemic concept for cooldowns: clear stale glow from a re-purposed bar frame.
    if bar._pandemicGlowActive then ClearPandemic(bar) end

    if not onCooldown and cfg.hideWhenInactive ~= false then
        -- Ready = inactive: hide, matching the buff inactive branch.
        _restoreTBBNormalFill(bar, cfg)
        bar._stackCount = 0
        if bar._stacksText then bar._stacksText:Hide() end
        bar._nameSet = nil
        if bar:IsShown() then bar:Hide() end
        return
    end

    local wasShown = bar:IsShown()
    if not wasShown then bar:Show() end
    local sb = bar._bar
    if sb then
        local timerDir = Enum and Enum.StatusBarTimerDirection
        local hashFillActive = hashChargeMode and _updateTBBChargeHashFill(
            bar, cfg, maxCharges, chargeCountValue,
            durObj, remaining, duration, wasShown)
        if hashFillActive then
            -- The composite's invisible native bars own the recovery geometry; the visible clipped texture and spark were updated above.
        elseif durObj and sb.SetTimerDuration and timerDir then
            _restoreTBBNormalFill(bar, cfg)
            -- Engine-driven fill: the handle tracks CDR and resets live with no numbers ever
            -- read. The bar timer is re-set only when a fresh handle was fetched
            -- (event/revalidate), the bar just appeared, or the requested direction changed --
            -- the engine animates in between. Fill Up asks the engine for ElapsedTime instead
            -- of RemainingTime, the same constant the charge-hash recovery bar uses. The
            -- direction term matters because toggling the option restyles a LIVE bar in
            -- place: with only the fetch/show terms the engine would keep animating the old
            -- direction until the next handle fetch.
            local wantDir = cfg.fillUp and timerDir.ElapsedTime
                or timerDir.RemainingTime
            if bar._cdNeedSet or not wasShown or bar._cdFillDir ~= wantDir then
                sb:SetMinMaxValues(0, 1)
                local interpE = Enum.StatusBarInterpolation
                local interp
                if interpE then
                    if wasShown and _smoothCooldowns then
                        interp = interpE.ExponentialEaseOut
                    else
                        interp = interpE.None
                    end
                end
                sb:SetTimerDuration(durObj, interp, wantDir)
                -- Snap whenever the bar was not already animating THIS
                -- direction. First show is the original case (the
                -- empty-to-full sweep-in). The direction term adds two more:
                -- arriving from the ready state, which parks the bar full and
                -- clears _cdFillDir, and a mid-cooldown toggle. Both leave the
                -- bar sitting at the opposite end, and with smooth cooldowns
                -- on, easing from there plays a visible backwards sweep at the
                -- exact moment the spell was cast.
                if (not wasShown or bar._cdFillDir ~= wantDir)
                    and sb.SetToTargetValue then
                    sb:SetToTargetValue()
                end
                bar._cdNeedSet = nil
                bar._cdFillDir = wantDir
            end
            if cfg.showSpark and bar._spark then bar._spark:Show() end
        elseif remaining then
            _restoreTBBNormalFill(bar, cfg)
            sb:SetMinMaxValues(0, duration)
            -- Both operands are clean numbers on this branch, and a
            -- non-positive remaining was normalised away above, so Fill Up
            -- can simply mirror the fraction in Lua.
            local fillVal = cfg.fillUp and (duration - remaining) or remaining
            -- Smooth fill is baseline (see UpdateLustBar note).
            local smooth = _smoothCooldowns and wasShown and Enum
                and Enum.StatusBarInterpolation
                and Enum.StatusBarInterpolation.ExponentialEaseOut
            if smooth then
                sb:SetValue(fillVal, smooth)
            else
                sb:SetValue(fillVal)
            end
            -- Plain SetValue cancels the running bar timer, so the cached
            -- engine direction is stale the moment this branch runs.
            bar._cdFillDir = nil
            if cfg.showSpark and bar._spark then bar._spark:Show() end
        else
            _restoreTBBNormalFill(bar, cfg)
            -- Ready (kept on screen) or unreadable fail-open: full bar in either direction.
            -- Plain SetValue also cancels any running bar timer.
            sb:SetMinMaxValues(0, 1)
            sb:SetValue(1)
            bar._cdFillDir = nil
            if bar._spark then bar._spark:Hide() end
        end
    end

    -- Timer: remaining cooldown, hidden when ready/unreadable. Clean numbers get the pretty
    -- format; a secret remaining from the duration handle goes through SetFormattedText
    -- (accepts secrets). Hash mode shows tenths, stock mode whole seconds.
    if bar._timerText then
        if remaining and cfg.showTimer then
            if hashChargeMode then
                bar._timerText:SetFormattedText("%.1f", remaining)
            elseif remaining < 10 then
                bar._timerText:SetText(string.format("%.1f", remaining))
            else
                bar._timerText:SetText(FormatTime(remaining))
            end
            bar._timerText:Show()
        elseif cfg.showTimer and durObj and durObj.GetRemainingDuration then
            local rem = durObj:GetRemainingDuration()
            if (issecretvalue and issecretvalue(rem)) or type(rem) == "number" then
                bar._timerText:SetFormattedText(hashChargeMode and "%.1f" or "%.0f", rem)
                bar._timerText:Show()
            else
                bar._timerText:Hide()
            end
        else
            bar._timerText:Hide()
        end
    end

    -- Charges reuse the stacks text and the threshold overlay feed. The text setter accepts
    -- a SECRET live count; overlays need clean numbers, so a secret count zeroes them instead of freezing a stale value.
    if hasCharges then
        bar._stackCount = charges or 0
        if bar._stacksText then
            if (cfg.stacksPosition or "center") ~= "none" then
                bar._stacksText:SetFormattedText("%d", chargesDisplay)
                bar._stacksText:Show()
            else
                bar._stacksText:Hide()
            end
        end
    else
        bar._stackCount = 0
        if bar._stacksText then bar._stacksText:Hide() end
    end

    -- Threshold feed (gated): runs in both arms so a charge count that becomes unreadable zeroes the overlay instead of freezing its last value.
    if _anyThreshold and cfg.stackThresholdEnabled then
        FeedTBBThresholdOverlay(bar)
    end

    -- Deferred tick marks (same consume as the buff mirror branch).
    if bar._ticksDirty and sb then
        local bw = sb:GetWidth()
        if bw and bw > 0 then
            ApplyTBBTickMarks(sb, cfg, bar._threshTicks,
                cfg.verticalOrientation, bar._tickOverlay)
            bar._ticksDirty = nil
        end
    end
end

-------------------------------------------------------------------------------
--  "Only In Combat" gate
--  Combat state comes from the main module's event-tracked flag (debounced combat
--  exit, so a mob dying between pulls does not flash every bar away).
--  InCombatLockdown() is only the fallback for a load order that has not published
--  the shared read yet.
-------------------------------------------------------------------------------
local function TBBInCombat()
    if ns.CDMInCombat then return ns.CDMInCombat() end
    return InCombatLockdown() and true or false
end

-- Park a bar the combat gate hides. Drops the same transient render state the inactive
-- branches drop, so the next in-combat show re-resolves icon/name/fill from scratch instead of mirroring a stale frame.
local function HideTBBBarForCombat(bar)
    -- Already parked: nothing to tear down, and clearing _nameSet here would make the
    -- deferred name-fill pass re-resolve the spell every frame for the whole time out of combat.
    if not bar:IsShown() then return end
    if bar._pandemicGlowActive then ClearPandemic(bar) end
    if bar._stacksText then bar._stacksText:Hide() end
    bar._stackCount = 0
    bar._cachedBlizzFillTex   = nil
    bar._cachedOurFillTex     = nil
    bar._cachedBlizzIconTex   = nil
    bar._cachedBlizzIconOwner = nil
    bar._lastIconSID = nil
    bar._nameSet     = nil
    bar:Hide()
end

-------------------------------------------------------------------------------
--  "Visibility" gate (CDM-Bars-style mode + options, TBB-scoped)
--  Mirrors _CDMApplyVisibility's priority-2/3 checks (EllesmereUICooldownManager.lua),
--  but folded into TBB's own tick since TBB bars are not native CDM bars.
--  Zero cost for bars without a condition: the tick consults the gate only
--  for bars flagged at build (bar._tbbVisCond) and fills the shared state
--  table ONCE per pass (TBBFillVisState) when any bar carries a condition.
-------------------------------------------------------------------------------
local _tbbVisState = {}

local function TBBFillVisState()
    local inRaid = IsInRaid and IsInRaid() or false
    _tbbVisState.inCombat = TBBInCombat()
    _tbbVisState.inRaid = inRaid
    _tbbVisState.inParty = not inRaid and (IsInGroup and IsInGroup() or false)
end

local function TBBVisibilityHides(cfg)
    if EllesmereUI.CheckVisibilityOptions and EllesmereUI.CheckVisibilityOptions(cfg) then
        return true
    end

    local vis = cfg.barVisibility or "always"
    local visExt = EllesmereUI.EvalVisibilityExtended
        and EllesmereUI.EvalVisibilityExtended(cfg, "barVisibility", _tbbVisState, EllesmereUI.VIS_CAPS_DEFAULT)
    if visExt ~= nil then return not visExt end
    if vis == "never" then return true end
    if vis == "in_combat" then return not _tbbVisState.inCombat end
    if vis == "out_of_combat" then return _tbbVisState.inCombat end
    if vis == "in_raid" then return not _tbbVisState.inRaid end
    if vis == "in_party" then return not _tbbVisState.inParty end
    if vis == "solo" then return _tbbVisState.inRaid or _tbbVisState.inParty end
    return false
end

-- Does this bar rely on a Visibility mode or option? Mirrors what TBBVisibilityHides reads,
-- minus hideWhenInactive/onlyInCombat, which flip on the aura and combat edges the sleeper
-- already wakes on. Option keys come from the shared list so a new one is covered here too.
local function TBBUsesVisCondition(cfg)
    if not cfg then return false end
    local vis = cfg.barVisibility
    if vis and vis ~= "always" then return true end
    local vm = cfg.visibilityModes
    if type(vm) == "table" and next(vm) then return true end
    local keys = EllesmereUI.VIS_OPT_KEYS
    if keys then
        for i = 1, #keys do
            if cfg[keys[i]] then return true end
        end
    end
    return false
end

-------------------------------------------------------------------------------
--  Main Tick: UpdateTrackedBuffBarTimers
--  Direct reskin of Blizzard's BuffBarCooldownViewer StatusBars: reads
--  min/max/value from Blizzard's Bar, zero duration computation.
-------------------------------------------------------------------------------
function ns.UpdateTrackedBuffBarTimers()
    if not ECME or not ECME.db then return end
    local tbb = ns.GetTrackedBuffBars()
    local bars = tbb.bars
    if not bars then return end

    -- Liveness for the idle sleeper: set by any branch below that is actually animating or tracking something this tick.
    local tickLive = false

    -- Profile-wide smooth-fill switches, resolved once per tick for every fill site (absent buffs key = enabled; absent cooldowns key = OFF).
    local sm
    do
        local pn = EllesmereUIDB and EllesmereUIDB.activeProfile
        local sp = ns._cachedSpecProfiles
        if _tickSm and pn == _tickSmProf and sp == _tickSmSp then
            sm = _tickSm
        else
            sm = ns.GetTBBSmoothSettings and ns.GetTBBSmoothSettings()
            _tickSm, _tickSmProf, _tickSmSp = sm, pn, sp
        end
    end
    if sm then
        _smoothBuffs = sm.buffs ~= false
        _smoothCooldowns = sm.cooldowns == true
    else
        _smoothBuffs, _smoothCooldowns = true, false
    end

    -- Self-heal placeholder mode when the user navigates away from Tracking Bars
    if ns._tbbPlaceholderMode then
        local am = EllesmereUI and EllesmereUI.GetActiveModule and EllesmereUI:GetActiveModule()
        local ap = EllesmereUI and EllesmereUI.GetActivePage and EllesmereUI:GetActivePage()
        if am ~= "EllesmereUICooldownManager" or ap ~= "Tracking Bars" then
            ns._tbbPlaceholderMode = false
            if ns.HideTBBPlaceholders then ns.HideTBBPlaceholders() end
            -- Auras may have moved while the preview was up: re-pair on the first real mirror tick.
            _tbbAssignDirty = true
        end
    end


    -- Pair configs to Blizzard frames ONE-TO-ONE up front, consuming each frame once, so two
    -- configs sharing a cooldownInfo (Eclipse Solar+Lunar) cannot both mirror the same frame and show twice.
    local assignment = AssignFramesToConfigs(bars)

    -- Visibility gate inputs, once per pass, only when some bar has a condition.
    if _anyVisCond then TBBFillVisState() end

    for i, cfg in ipairs(bars) do
        local bar = tbbFrames[i]
        if not bar or not bar._tbbReady then
            -- skip
        elseif ns._tbbPlaceholderMode then
            tickLive = true
            if not bar:IsShown() then bar:Show() end
        elseif cfg.enabled == false then
            bar:Hide()
        elseif bar._tbbVisCond and TBBVisibilityHides(cfg) then
            HideTBBBarForCombat(bar)
        elseif cfg.onlyInCombat and not TBBInCombat() then
            -- "Only In Combat": out of combat the bar is gone regardless of aura/cooldown state, and regardless of Hide When Inactive.
            HideTBBBarForCombat(bar)
        elseif cfg.popularKey == "bloodlust" then
            -- Self-driven 40s lust bar; no Blizzard frame to mirror.
            if UpdateLustBar(bar, cfg) then tickLive = true end
        elseif cfg.popularKey == "timespiral" then
            -- Self-driven 10s Time Spiral "Free Move" bar; glow-armed, no frame.
            if _UpdateSelfTimedBar(bar, cfg, _ts.expiry, TIME_SPIRAL_DURATION) then tickLive = true end
        elseif cfg.popularKey and _potionDur[cfg.popularKey] then
            -- Self-cast potion preset: hardcoded window off the spell-cast edge; no aura tracking, no Blizzard frame to mirror.
            if _UpdateSelfTimedBar(bar, cfg, _potionExpiry[cfg.popularKey] or 0,
                _potionDur[cfg.popularKey]) then tickLive = true end
        elseif cfg.trackType == "cooldown" then
            -- Spell-cooldown tracking: self-driven, no Blizzard frame/aura.
            _UpdateCooldownBar(bar, cfg)
            -- Live while an engine handle drives the fill OR the bar is on screen: covers the
            -- secret-timing mirror drain and always-shown bars, both needing per-tick updates.
            if bar._cdDurObj or bar:IsShown() then tickLive = true end
        else
            local blzChild = assignment[cfg]
            if blzChild then ns.HookPandemicState(blzChild) end

            -- Active state MUST come from the CooldownViewer item's IsActive() (real
            -- aura state: expirationTime > now, or infinite auras), NEVER IsShown(): a
            -- buff-bar item stays SHOWN while inactive unless the user enabled
            -- Blizzard's "Hide When Inactive" edit-mode option (off by default), which
            -- would leave our bar visible 100% of the time. Fall back to IsShown() only
            -- if IsActive is absent.
            local isActive = false
            if blzChild then
                if blzChild.IsActive then
                    isActive = blzChild:IsActive() and true or false
                elseif blzChild.IsShown then
                    isActive = blzChild:IsShown() or false
                end
            end

            -- Blizzard viewer bind-miss / not-tracked-at-all fallback: covers (1) the
            -- buff-bar viewer failing to bind a freshly applied aura (auraInstanceID
            -- never set, IsActive stuck false until another bar's activation forces a
            -- refresh) and (2) a spell absent from every CooldownViewer category
            -- (blzChild permanently nil, e.g. a hero-talent proc CDM never registers).
            -- Either way, when the player demonstrably carries the aura (known-spellID
            -- player-aura query, no scanning), drive the bar from the aura data --
            -- reads only, our own frames only, NEVER pokes the Blizzard frame.
            local fbAura
            if not isActive and not cfg.spellIDs
               and cfg.spellID and cfg.spellID > 0
               and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
                fbAura = C_UnitAuras.GetPlayerAuraBySpellID(cfg.spellID)
                if not fbAura and cfg.baseSpellID and cfg.baseSpellID > 0 then
                    fbAura = C_UnitAuras.GetPlayerAuraBySpellID(cfg.baseSpellID)
                end
                -- Fallback driving means the viewer has not bound this aura yet, and
                -- Blizzard's late-bind can land WITHOUT a fresh player aura event. Keep
                -- the memo dirty while any fallback is live so the next tick re-pairs
                -- the moment the frame appears (restoring stacks/pandemic from mirror).
                if fbAura then _tbbAssignDirty = true end
            end
            if isActive or fbAura then tickLive = true end

            -- Read Blizzard's StatusBar (the data source for fill/timer)
            local blizzBar = blzChild and blzChild.Bar

            if isActive then
                local wasShown = bar:IsShown()
                if not wasShown then bar:Show() end
                local sb = bar._bar

                -- Stacks (gated)
                if _anyStacks then UpdateStacks(bar, blzChild, cfg) end

                if blizzBar then
                    -- Mirror Blizzard's bar onto ours. Secret values pass natively to widget
                    -- setters (NEVER compared in Lua). Smooth fill is baseline (see UpdateLustBar note).
                    local smooth = _smoothBuffs and wasShown and Enum
                        and Enum.StatusBarInterpolation
                        and Enum.StatusBarInterpolation.ExponentialEaseOut
                    if cfg.stackBasedBar and cfg.trackType ~= "cooldown"
                       and cfg.stackThresholdMaxEnabled then
                        -- Stack-based fill: current stacks over the user's Max Stacks instead
                        -- of the time mirror. An unreadable count (no cached aura data, no
                        -- readable instance id) fails open to a full bar, like every unreadable fill here.
                        if bar._stackUnreadable then
                            sb:SetMinMaxValues(0, 1)
                            sb:SetValue(1)
                        else
                            sb:SetMinMaxValues(0, cfg.stackThresholdMax or 10)
                            if smooth then
                                sb:SetValue(bar._stackCount or 0, smooth)
                            else
                                sb:SetValue(bar._stackCount or 0)
                            end
                        end
                    elseif smooth then
                        sb:SetMinMaxValues(blizzBar:GetMinMaxValues())
                        sb:SetValue(blizzBar:GetValue(), smooth)
                    else
                        sb:SetMinMaxValues(blizzBar:GetMinMaxValues())
                        sb:SetValue(blizzBar:GetValue())
                    end
                    if cfg.showSpark and bar._spark then bar._spark:Show() end

                    -- Auto fill color from Blizzard's bar texture
                    if (cfg.fillColorMode or "auto") == "auto" then
                        -- Cache texture refs: GetStatusBarTexture() allocates userdata per call.
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

                    -- Name resolution ladder:
                    --  1. Blizzard's rendered label FontString on the BOUND
                    --     frame -- the only channel carrying live variant
                    --     names (Diabolist probe 2026-08-16: on the active
                    --     ritual frame every id AND the aura-instance read are
                    --     secret even out of combat; only the label knows
                    --     which ritual is up). FIELD-PROVEN 2026-08: a hidden
                    --     pool frame's label can ALSO hold another slot's
                    --     readable text persistently after re-acquire (binding
                    --     right, label lying -- SotR as "Consecration", Bone
                    --     Shield as "Blood Draw"), so the label is trusted
                    --     only inside the config's name family: readable text
                    --     must be family-compatible, and secret text paints
                    --     only on slots whose linked forms provably render
                    --     distinct names. Secrets pass straight to SetText
                    --     (never compared or stored).
                    --  2. Live aura data, when readable and provably this bar's
                    --     family (exact config ids or the bound slot's
                    --     cooldownInfo override/spellID/linkedSpellIDs).
                    --  3. The configured spell's name (deterministic).
                    if bar._nameText and bar._nameText:IsShown() then
                        local nameStr
                        -- auraInstanceID may itself be SECRET on the active frame
                        -- (probe-confirmed): type() reads the tag without touching
                        -- the value -- the taint-safe presence test for secrets.
                        -- SLOT CHECK (the Wardead class, 2+ bars in one group in
                        -- combat): cooldownID stays a plain readable number in
                        -- secret windows, so a pooled frame moved to another slot
                        -- since binding is caught before its label is read (the
                        -- sticky pass applies the identical test on its own
                        -- schedule); a mismatch skips the label and falls through.
                        if blzChild and blzChild:IsShown() and blizzBar
                           and type(blzChild.auraInstanceID) ~= "nil"
                           and (_tbbStickyCdID[cfg] == nil
                                or blzChild.cooldownID == _tbbStickyCdID[cfg]) then
                            local blizzNameFS = GetBlizzBarFontStrings(blizzBar)
                            if blizzNameFS then
                                local ok, txt = pcall(blizzNameFS.GetText, blizzNameFS)
                                if ok and txt ~= nil then
                                    if issecretvalue and issecretvalue(txt) then
                                        if TbbSlotVariantLabeled(bar, blzChild.cooldownID) then
                                            nameStr = txt
                                        end
                                    elseif txt ~= "" then
                                        -- Family gate memoized on (cfg, cfg.name,
                                        -- text): the verdict only moves when the
                                        -- rendered string or the config does.
                                        if bar._labelGateCfg ~= cfg
                                           or bar._labelGateNm ~= cfg.name
                                           or bar._labelGateTxt ~= txt then
                                            bar._labelGateCfg = cfg
                                            bar._labelGateNm  = cfg.name
                                            bar._labelGateTxt = txt
                                            bar._labelGateOk  = TbbCfgFamilyMatch(
                                                cfg, TbbNameFamily(txt), true)
                                        end
                                        if bar._labelGateOk then nameStr = txt end
                                    end
                                end
                            end
                        end
                        if not nameStr and blzChild and blzChild.auraInstanceID and blzChild.auraDataUnit
                           and not (issecretvalue and issecretvalue(blzChild.auraInstanceID)) then
                            local ok, ad = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID,
                                blzChild.auraDataUnit, blzChild.auraInstanceID)
                            if ok and ad and ad.name and not (issecretvalue and issecretvalue(ad.name)) then
                                local sid = ad.spellId
                                if sid ~= nil and not (issecretvalue and issecretvalue(sid)) then
                                    local mine = CfgWantsSID(cfg, sid)
                                    if not mine and blzChild.cooldownID
                                       and not (issecretvalue and issecretvalue(blzChild.cooldownID))
                                       and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
                                        local ok2, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, blzChild.cooldownID)
                                        if ok2 and info then
                                            local ok3, m = pcall(MatchesSID, info, sid)
                                            mine = ok3 and m
                                        end
                                    end
                                    if mine then nameStr = ad.name end
                                end
                            end
                        end
                        if not nameStr and cfg.spellID and cfg.spellID > 0 then
                            local spInfo = C_Spell.GetSpellInfo(cfg.spellID)
                            if spInfo then
                                nameStr = spInfo.name
                            elseif C_Spell.RequestLoadSpellData then
                                C_Spell.RequestLoadSpellData(cfg.spellID)
                            end
                        end
                        if not nameStr and cfg.baseSpellID and cfg.baseSpellID > 0 then
                            local spInfo = C_Spell.GetSpellInfo(cfg.baseSpellID)
                            if spInfo then nameStr = spInfo.name end
                        end
                        if nameStr then
                            bar._nameText:SetText(nameStr)
                            bar._nameSet = true
                        end
                    end
                    -- Timer: engine-bound decimal mirror first (the engine formats the secret
                    -- remaining time into a hidden FS we copy). Fallback: passthrough from
                    -- Blizzard's FontString every frame (it changes constantly).
                    if MirrorEngineTimer(bar, cfg) then
                        bar._timerText:Show()
                    else
                        local _, blizzTimerFS = GetBlizzBarFontStrings(blizzBar)
                        if cfg.showTimer and bar._timerText and blizzTimerFS then
                            bar._timerText:SetText(blizzTimerFS:GetText())
                            bar._timerText:Show()
                        elseif bar._timerText then
                            bar._timerText:Hide()
                        end
                    end

                    -- Icon source priority: 1) Blizzard's icon texture on the bound
                    -- frame (SetBarContent already resolved the override/variant form,
                    -- so mirroring the file can never disagree with Blizzard's own CDM;
                    -- mirrored every tick like the fill color, passes through even when
                    -- secret since SetTexture accepts secrets); 2) live aura data
                    -- (frames without an icon region), so dynamic buffs (Roll the
                    -- Bones) show the rolled buff; 3) effective config spell
                    -- (override-resolved saved id). Every non-config write clears
                    -- _lastIconSID so the config fallback can't skip its SetTexture
                    -- against a stale cache and strand another source's icon.
                    if bar._icon and bar._icon:IsShown() then
                        local gotIcon = false
                        if bar._cachedBlizzIconOwner ~= blzChild then
                            local iconRegion = blzChild.Icon
                            bar._cachedBlizzIconTex = (iconRegion and iconRegion.Icon) or false
                            bar._cachedBlizzIconOwner = blzChild
                        end
                        local blzIconTex = bar._cachedBlizzIconTex
                        if blzIconTex then
                            local file = blzIconTex:GetTexture()
                            if file then
                                bar._icon._tex:SetTexture(file)
                                bar._lastIconSID = nil
                                gotIcon = true
                            end
                        end
                        if not gotIcon and blzChild.auraInstanceID and blzChild.auraDataUnit then
                            local ok, ad = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID,
                                blzChild.auraDataUnit, blzChild.auraInstanceID)
                            -- Instance ids recycle onto other buffs; only trust a match.
                            if ok and ad and ad.icon and CfgWantsSID(cfg, ad.spellId) then
                                bar._icon._tex:SetTexture(ad.icon)
                                bar._lastIconSID = nil
                                gotIcon = true
                            end
                        end
                        if not gotIcon then
                            local iconSID = EffectiveIconSpellID(cfg)
                            if iconSID and iconSID ~= bar._lastIconSID then
                                local spInfo = C_Spell.GetSpellInfo(iconSID)
                                if spInfo and spInfo.iconID then
                                    bar._icon._tex:SetTexture(spInfo.iconID)
                                    bar._lastIconSID = iconSID
                                end
                            end
                        end
                    end

                    -- Pandemic glow: the ShowPandemicStateFrame hook sets _pandemicState.
                    -- Requires the user to enable pandemic alerts in Blizzard CDM settings.
                    if _anyPandemic and cfg.pandemicGlow then
                        local inPandemic = blzChild and _pandemicState[blzChild]
                        -- Fallback for auras Blizzard never pandemic-flags (currently only
                        -- Lifebloom). bar._isLifebloom is cached after the first resolve, so a
                        -- bar known not to be Lifebloom costs one table read and skips.
                        if not inPandemic and blzChild and bar._isLifebloom ~= false then
                            inPandemic = LifebloomPandemic(bar, blzChild)
                        end
                        -- TBBs always show OUR glow (Blizzard Default included): the native
                        -- PandemicIcon lives on the hidden blzChild frame, not our visible TBB bar.
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
                -- Bind-miss fallback: self-drive fill/timer from the live aura until
                -- Blizzard's frame catches up; isActive then resumes the normal mirror path seamlessly.
                local wasShown = bar:IsShown()
                if not wasShown then bar:Show() end
                local sb = bar._bar
                local dur = fbAura.duration
                local exp = fbAura.expirationTime
                local isSec = issecretvalue
                local clean = dur and exp and not (isSec and (isSec(dur) or isSec(exp)))
                -- Stack-based fill works in fallback mode too: fill and stacks text come from
                -- the live aura's applications (plain or secret; SetValue/SetText accept both) while the timer keeps tracking remaining time.
                local fbStackFill = cfg.stackBasedBar
                    and cfg.trackType ~= "cooldown"
                    and cfg.stackThresholdMaxEnabled
                if sb and fbStackFill then
                    local apps = fbAura.applications
                    -- The aura is up, so a readable count floors at 1 even when applications reads 0/nil (non-stacking aura).
                    if not apps or (not (isSec and isSec(apps)) and apps < 1) then
                        apps = 1
                    end
                    sb:SetMinMaxValues(0, cfg.stackThresholdMax or 10)
                    local smooth = _smoothBuffs and wasShown and Enum
                        and Enum.StatusBarInterpolation
                        and Enum.StatusBarInterpolation.ExponentialEaseOut
                    if smooth then
                        sb:SetValue(apps, smooth)
                    else
                        sb:SetValue(apps)
                    end
                    bar._stackCount = apps
                    if bar._stacksText and not bar._stacksHidden then
                        bar._stacksText:SetText(apps)
                        bar._stacksText:Show()
                    elseif bar._stacksText then
                        bar._stacksText:Hide()
                    end
                    -- Timer text: same handling as the duration fill below.
                    if clean and dur > 0 then
                        if cfg.showTimer and bar._timerText then
                            local remaining = exp - GetTime()
                            if remaining < 0 then remaining = 0 end
                            if not MirrorEngineTimer(bar, cfg) then
                                bar._timerText:SetText(FormatTime(remaining))
                            end
                            bar._timerText:Show()
                        elseif bar._timerText then
                            bar._timerText:Hide()
                        end
                    elseif bar._timerText then
                        bar._timerText:SetShown(MirrorEngineTimer(bar, cfg))
                    end
                    if cfg.showSpark and bar._spark then bar._spark:Show() end
                elseif sb then
                    if clean and dur > 0 then
                        local remaining = exp - GetTime()
                        if remaining < 0 then remaining = 0 end
                        sb:SetMinMaxValues(0, dur)
                        local smooth = _smoothBuffs and wasShown and Enum
                            and Enum.StatusBarInterpolation
                            and Enum.StatusBarInterpolation.ExponentialEaseOut
                        if smooth then
                            sb:SetValue(remaining, smooth)
                        else
                            sb:SetValue(remaining)
                        end
                        if cfg.showTimer and bar._timerText then
                            -- Engine-bound decimal mirror first; the clean local format is the fallback.
                            if not MirrorEngineTimer(bar, cfg) then
                                bar._timerText:SetText(FormatTime(remaining))
                            end
                            bar._timerText:Show()
                        elseif bar._timerText then
                            bar._timerText:Hide()
                        end
                    else
                        -- Duration unreadable (secret) or infinite aura: show a full bar with no countdown.
                        sb:SetMinMaxValues(0, 1)
                        sb:SetValue(1)
                        if bar._timerText then
                            -- The engine-bound decimal mirror can render the secret remaining
                            -- time we cannot; otherwise no readable time -> no text.
                            bar._timerText:SetShown(MirrorEngineTimer(bar, cfg))
                        end
                    end
                    if cfg.showSpark and bar._spark then bar._spark:Show() end
                end
                -- Icon/name from the aura data itself: fires when the frame mirror is
                -- unavailable, and for override/variant spells the build-time saved-form
                -- icon can be the wrong form, so the live aura is the truth. Icon passes
                -- through even when secret (SetTexture accepts secrets); name applies
                -- only on a clean read (font strings need a plain string).
                if bar._icon and bar._icon:IsShown() and fbAura.icon then
                    bar._icon._tex:SetTexture(fbAura.icon)
                    bar._lastIconSID = nil
                end
                local fbName = fbAura.name
                if bar._nameText and bar._nameText:IsShown() and fbName
                   and not (isSec and isSec(fbName)) then
                    bar._nameText:SetText(fbName)
                    bar._nameSet = true
                end
                -- Extras stay quiet in fallback mode: no Blizzard child to read stacks/pandemic from. Skipped when the stack fill drove them.
                if not (sb and fbStackFill) then
                    if bar._stacksText then bar._stacksText:Hide() end
                    bar._stackCount = 0
                end
                if bar._pandemicGlowActive then ClearPandemic(bar) end
            else
                -- Inactive: clear transient state
                bar._cachedBlizzFillTex = nil
                bar._cachedOurFillTex = nil
                bar._cachedBlizzIconTex = nil
                bar._cachedBlizzIconOwner = nil
                bar._lastIconSID = nil
                if _anyPandemic and bar._pandemicGlowActive then ClearPandemic(bar) end
                if bar._stacksText then bar._stacksText:Hide() end
                bar._stackCount = 0
                if cfg.hideWhenInactive == false then
                    -- "Hide When Inactive" off: keep the bar on screen as an empty idle bar (name visible, no fill/timer/spark).
                    if not bar:IsShown() then bar:Show() end
                    local sb = bar._bar
                    if sb then sb:SetMinMaxValues(0, 1); sb:SetValue(0) end
                    if bar._timerText then bar._timerText:Hide() end
                    if bar._spark then bar._spark:Hide() end
                elseif bar:IsShown() then
                    -- Clear the name latch on the hide EDGE only: clearing it every hidden
                    -- tick would make the deferred name fill call C_Spell.GetSpellInfo every tick for every hidden bar.
                    bar._nameSet = nil
                    bar:Hide()
                end
            end
        end
    end

    -- Re-pack visible grouped Tracking Bars after the active/inactive pass so hidden buffs do not reserve a slot in the group.
    if _tbbReflowDirty then ReflowVisibleGroupedTBBars(tbb, bars) end

    -- Deferred name fill: retry each tick when BuildTrackedBuffBars could not resolve the spell name (spell data not loaded yet).
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

    -- Normal-fill spark maintenance (hash-fill sparks are anchored by their own renderer).
    -- Both paths use AnchorTBBSparkState's scalar signature, so unchanged anchors do no native layout work and allocate nothing.
    for _, bar in ipairs(tbbFrames) do
        -- bar:IsShown() gate: a child spark's own shown flag stays latched true after its
        -- parent bar Hides, so without this the loop would keep anchoring sparks of hidden bars every tick forever.
        if bar and bar:IsShown() and bar._spark and bar._spark:IsShown() and bar._bar then
            if not bar._chargeHashFillActive then
                local anchor = (bar._gradientActive and bar._gradClip)
                    or bar._cachedOurFillTex
                if not anchor then
                    anchor = bar._bar:GetStatusBarTexture()
                    bar._cachedOurFillTex = anchor
                end
                if anchor then
                    AnchorTBBSparkState(bar, anchor, bar._lastVertical,
                        bar._lastReverse, false)
                end
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

    -- Idle sleeper: after ~0.5s of ticks with nothing live, park the OnUpdate entirely and
    -- let the wake listeners re-arm it. The settle window lets smooth fills and the opacity
    -- lerp converge (both ease within ~0.35s) before updates stop, and stays short so wake bursts remain cheap.
    if tickLive then
        _tbbWake._idleTicks = 0
    elseif tbbTickFrame and tbbTickFrame:IsShown() then
        local n = _tbbWake._idleTicks + 1
        _tbbWake._idleTicks = n
        if n >= 30 then _tbbWake.Sleep() end
    end
end

-------------------------------------------------------------------------------
--  Build / Rebuild All Tracking Bars
-------------------------------------------------------------------------------
function ns.BuildTrackedBuffBars()
    ECME = ns.ECME
    if not ECME or not ECME.db then return end
    -- No InCombatLockdown guard needed: TBB frames are ours (UIParent), not secure Blizzard frames, so positioning in combat is safe.
    _tbbRebuildPending = false
    _tbbReflowDirty = true

    -- Per-spec unlock-link views: the global anchor/match stores must hold THIS spec's TBB entries before any anchored-state below is read.
    ns.SyncTBBUnlockLinks()

    local p = ECME.db.profile

    -- NEVER auto-swap width/height per build: the Vertical Orientation toggle already swaps
    -- dimensions, and a per-build swap fights slider input and makes resizes erratic.
    do
        local tbb = ns.GetTrackedBuffBars()
        local bars = tbb and tbb.bars
        if bars then
        end
    end

    -- "Use Blizzard CDM Bars": hide all TBB frames and bail
    if p.cdmBars and p.cdmBars.useBlizzardBuffBars then
        for i = 1, #tbbFrames do
            if tbbFrames[i] then tbbFrames[i]:Hide() end
        end
        _tbbWake._enabled = false
        _tbbWake:UnregisterAllEvents()
        if tbbTickFrame then tbbTickFrame:Hide() end
        return
    end

    -- Pre-populate bars for spells newly added to Blizzard's Tracked Bars section BEFORE reading the bar list, so this rebuild picks them up.
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
    _anyVisCond   = false

    local anyEnabled = false
    local anyLust = false  -- any enabled bloodlust bar -> needs the Sated listener
    local lastBarByGroup = {}  -- gid -> previous enabled member frame (chain tail)
    for i, cfg in ipairs(bars) do
        -- Update gating flags
        if cfg.pandemicGlow                             then _anyPandemic  = true end
        if cfg.stackThresholdEnabled                    then _anyThreshold = true; _anyStacks = true end
        if (cfg.stacksPosition or "center") ~= "none"  then _anyStacks    = true end
        if cfg.stackBasedBar and cfg.trackType ~= "cooldown"
           and cfg.stackThresholdMaxEnabled             then _anyStacks    = true end
        local visCond = TBBUsesVisCondition(cfg)
        if visCond                                      then _anyVisCond   = true end

        if not tbbFrames[i] then
            tbbFrames[i] = CreateTrackedBuffBarFrame(UIParent, i)
        end
        local bar = tbbFrames[i]
        -- Per-bar gate flag for the tick (our frame; the tick never re-derives it).
        bar._tbbVisCond = visCond or nil

        if cfg.enabled == false then
            bar:Hide()
        else
            anyEnabled = true
            if cfg.popularKey == "bloodlust" then anyLust = true end
            ApplyTrackedBuffBarSettings(bar, cfg)

            -- Icon texture: preset icon, else the EFFECTIVE (override-resolved) form of the
            -- saved spell, never the raw saved id -- a bar saved for a base form seeds the
            -- talented override's icon and vice versa. The live tick re-derives from the
            -- bound frame/aura and overwrites this seed whenever better data exists.
            if bar._icon and bar._icon._tex then
                local iconID
                if cfg.popularKey then
                    for _, pe in ipairs(TBB_POPULAR_BUFFS) do
                        if pe.key == cfg.popularKey then iconID = pe.icon; break end
                    end
                end
                if not iconID then
                    local effSID = EffectiveIconSpellID(cfg)
                    if effSID then
                        local spInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(effSID)
                        if spInfo then iconID = spInfo.iconID end
                    end
                end
                if iconID then bar._icon._tex:SetTexture(iconID) end
                -- Rebuilds can re-pair bar index <-> config (add/remove shifts indices), so
                -- reset per-bar icon source state and let the next tick re-derive instead of trusting stale caches.
                bar._lastIconSID = nil
                bar._cachedBlizzIconTex = nil
                bar._cachedBlizzIconOwner = nil
            end

            -- Name text
            local namePos2 = cfg.namePosition or ((cfg.showName ~= false) and "left" or "none")
            if namePos2 ~= "none" and bar._nameText then
                local displayName = cfg.name
                -- Preset bars take the live label the same way the icon does above:
                -- the copy saved at pick time can name the other faction's lust.
                if cfg.popularKey then
                    for _, pe in ipairs(TBB_POPULAR_BUFFS) do
                        if pe.key == cfg.popularKey then
                            displayName = pe.name or displayName
                            break
                        end
                    end
                end
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

            -- Saved position / grouping. A group's FIRST enabled member takes the independent
            -- branch (its own saved pos) and becomes the group anchor; later members chain to
            -- the previous member using the group's grow/spacing. Independent bars (gid 0) always take the independent branch.
            local gid = ns.TBBBarGroupID(cfg)
            local prevInGroup = gid ~= 0 and lastBarByGroup[gid] or nil
            if prevInGroup then
                -- Grouped: position relative to the previous member
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
                -- Independent positioning (group anchors and ungrouped bars). A global group's
                -- anchor reads the shared registry position and its anchored-ness through the group's stable TBBG_ key.
                local gkeyPos = gid ~= 0 and ns.TBBGroupGlobalKey and ns.TBBGroupGlobalKey(gid) or nil
                local posKey = tostring(i)
                local pos, unlockKey
                if gkeyPos then
                    local entry = ns.TBBGlobalGroup(gkeyPos)
                    pos = entry and entry.pos
                    unlockKey = "TBBG_" .. gkeyPos
                    -- Stamp the anchor bar's size onto the registry entry so the
                    -- "Shift Elements If No Bars" stand-in (memberless specs)
                    -- holds the slot at the size the group last rendered. Gated
                    -- on the option so None profiles see zero new writes; a
                    -- never-stamped entry's stand-in uses the bar defaults.
                    if entry and (entry.shiftNoBar == "Up" or entry.shiftNoBar == "Down") then
                        entry.width = cfg.width or 270
                        entry.height = cfg.height or 24
                    end
                else
                    pos = _tbbPos[posKey]
                    unlockKey = "TBB_" .. posKey
                end
                if pos and pos.point then
                    local anchored = EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored(unlockKey)
                    if not anchored or not bar:GetLeft() then
                        bar:ClearAllPoints()
                        if pos.scale then pcall(function() bar:SetScale(pos.scale) end) end
                        bar:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
                    end
                else
                    local anchored = EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored(unlockKey)
                    if not anchored or not bar:GetLeft() then
                        bar:ClearAllPoints()
                        bar:SetPoint("CENTER", UIParent, "CENTER", 0, 200 - (i - 1) * ((cfg.height or 24) + 4))
                    end
                end
            end

            if gid ~= 0 then lastBarByGroup[gid] = bar end
            bar._tbbReady    = true
            bar._isPassive   = nil
            bar._stackCount  = 0
            bar._isLifebloom = nil  -- re-resolve Lifebloom identity after rebuild
            bar:Hide()  -- tick shows it when active
        end
    end

    -- Tick frame: every frame while anything is live (bar fill+spark need smooth updates);
    -- the idle sleeper in UpdateTrackedBuffBarTimers parks it when nothing is.
    _tbbWake._enabled = anyEnabled and true or false
    if anyEnabled then
        if not tbbTickFrame then
            tbbTickFrame = ns.TakeShell()
            local tbbAccum = 0
            tbbTickFrame:SetScript("OnUpdate", function(self, elapsed)
                tbbAccum = tbbAccum + elapsed
                if tbbAccum < 0.016 then return end
                self._lastDt = tbbAccum
                tbbAccum = 0
                ns.UpdateTrackedBuffBarTimers()
            end)
        end
        _tbbWake.Wake()
    else
        _tbbWake:UnregisterAllEvents()
        if tbbTickFrame then tbbTickFrame:Hide() end
    end

    -- Start/stop the player-only Sated-debuff listener that drives the lust displays. Goes
    -- through the arbiter so a Custom Auras (icon) lust display keeps the listener armed even when no Tracking Bar lust bar exists.
    ns.UpdateLustListener()

    -- "Shift Elements If No Bars" (global groups): position each opted-in
    -- group's stand-in, and on an empty<->populated EDGE re-cascade the group's
    -- anchor chain so anchored elements pick up (or drop) the shift. The flip
    -- changes neither the stand-in's size nor its position (both come from the
    -- registry), so neither OnSizeChanged nor a move hook fires -- the cascade
    -- must be explicit, exactly like ResourceBars' BuildBars tail. Edge-gated
    -- via the per-key memo so a None-everywhere profile schedules ZERO anchor
    -- work here; unlock entry/exit manage the shift themselves.
    do
        local reg = ns.GetTBBGlobalGroups and ns.GetTBBGlobalGroups()
        if reg then
            for gk, entry in pairs(reg) do
                -- Also keep maintaining a stand-in that already exists with the
                -- option back at None (session fallback, see TBBStandinFrame):
                -- it must track registry-pos edits from other specs instead of
                -- freezing anchored children on a phantom (audit-caught).
                if entry.shiftNoBar == "Up" or entry.shiftNoBar == "Down"
                    or (ns.TBBStandinFrame and ns.TBBStandinFrame(gk)) then
                    ns.TBBEnsureStandin(gk)
                end
                if not EllesmereUI._unlockActive and EllesmereUI.PropagateAnchorChain then
                    -- dir: 0 = covered (members present or option off), +/-1 =
                    -- shifting. Unset memo reads as 0, so the first build with
                    -- nothing to shift schedules nothing (ERB memo parity).
                    local dir = ns.TBBShiftDirFor(entry, gk)
                    local memo = ns._tbbShiftDirMemo
                    if not memo then
                        memo = {}
                        ns._tbbShiftDirMemo = memo
                    end
                    if dir ~= (memo[gk] or 0) then
                        memo[gk] = dir
                        EllesmereUI.PropagateAnchorChain("TBBG_" .. gk)
                    end
                end
            end
        end
    end

    -- Unlock mode
    if ns.RegisterTBBUnlockElements then ns.RegisterTBBUnlockElements() end

    -- 12.1 engine-driven decimal timer text (nil on 12.0: module self-gates)
    if ns.TBBDecimals_Sync then ns.TBBDecimals_Sync() end
end

-------------------------------------------------------------------------------
--  Unlock Mode Registration
-------------------------------------------------------------------------------
function ns.RegisterTBBUnlockElements()
    if not EllesmereUI or not EllesmereUI.RegisterUnlockElements then return end
    if not ECME or not ECME.db then return end
    -- Per-spec unlock-link views: this path can run on spec change before a TBB build (CDM
    -- setup registers synchronously so anchor data is ready for CollectAndReanchor), so sync the link stores here too.
    ns.SyncTBBUnlockLinks()
    local MK = EllesmereUI.MakeUnlockElement
    -- Never call UnregisterUnlockElement for TBB keys -- it triggers PruneStaleLinks which
    -- destroys saved anchor data in unlockAnchors. Instead, just overwrite registrations;
    -- the isHidden callback handles hiding movers for bars that don't exist in the current spec.
    local tbb = ns.GetTrackedBuffBars()
    local bars = (tbb and tbb.bars) or {}

    -- Membership/grow/spec may have changed: growth-edge extent watch re-derives lazily on next use.
    ns._tbbExtentWatch = nil

    -- Each group's anchor (first enabled member) owns that group's mover; the other members hide theirs. Computed per build so it tracks group edits.
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
                -- Tracking bars may size-MATCH to other elements (allowMatchSource), but other
                -- elements may NOT match to them (noSizeMatchTarget): a tracking bar's size is
                -- driven by its own CDM sliders/dynamic content, so it should never be a sizing reference.
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
                    -- Global group: the stable TBBG_ mover owns the whole group -- every member's own mover hides, anchor included.
                    if ns.TBBGroupGlobalKey and ns.TBBGroupGlobalKey(gid) then return true end
                    -- Grouped bars: only the group's anchor shows a mover (moves the
                    -- whole group); hide every other member, enabled OR disabled (a
                    -- disabled member re-enables straight into the chain, so its own
                    -- mover would be a phantom). No member enabled -> anchor nil, all hidden.
                    return idx ~= ns.TBBGroupAnchorIndex(gid)
                end,
                -- Grouped non-anchor members are positioned by the relative SetPoint
                -- chain in BuildTrackedBuffBars; report them as addon-owned so the
                -- generic anchor system never repositions them (a cascade/override
                -- SetPoint would sever the chain, e.g. in combat via a stale per-member
                -- link). A group ANCHOR returns false (stays element-anchorable).
                -- Global-group members are ALL addon-owned (anchor included): its
                -- position comes from the registry via BuildTrackedBuffBars, and the
                -- TBBG_ element carries the group's anchorable identity instead.
                isAnchored = function()
                    local t = ns.GetTrackedBuffBars()
                    local b = t and t.bars
                    local c = b and b[idx]
                    local gid = c and ns.TBBBarGroupID(c) or 0
                    if gid == 0 then return false end
                    if ns.TBBGroupGlobalKey and ns.TBBGroupGlobalKey(gid) then return true end
                    return idx ~= ns.TBBGroupAnchorIndex(gid)
                end,
                getFrame = function()
                    -- Never expose a stale frame when the current spec has fewer bars: anchors
                    -- involving this key stay dormant (children hold position) instead of gluing to a hidden frame at another spec's coordinates.
                    local t = ns.GetTrackedBuffBars()
                    local b = t and t.bars
                    if not b or idx > #b then return nil end
                    return tbbFrames[idx]
                end,
                getSize  = function()
                    -- width/height ARE the total footprint (icon included), so matching reads the stored dims directly.
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
                    -- Persist during unlock (manual) AND match propagation, so a width match TO
                    -- another element survives the next BuildTrackedBuffBars instead of reverting to the slider value.
                    if EllesmereUI._unlockActive or EllesmereUI._propagatingMatch then
                        c.width = w
                        -- Grouped bars share width: fan this out to the rest of the group
                        -- (covers unlock drag-resize AND a width-MATCH on the group anchor, both routing through here).
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
                    -- A group is dragged via its anchor's mover, but the saved position is
                    -- keyed by the anchor's INDEX. If the anchor later changes (first
                    -- member leaves the group or is disabled) the new anchor would read a
                    -- stale coordinate and teleport. Mirror the group origin into every
                    -- member's key so whichever bar becomes the anchor reads it correctly.
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

    -- Global groups: one stable mover per registry entry, registered even when the
    -- active spec has no member bars (never unregister -- links must survive;
    -- isHidden/getFrame nil keep empty groups inert). The mover reads/writes the shared
    -- registry position, so one drag places the group for every spec.
    local reg = ns.GetTBBGlobalGroups and ns.GetTBBGlobalGroups()
    if reg then
        -- Alias map: the anchor bar's frame carries the move/resize hooks under its per-bar
        -- TBB_ key; children anchored to the group's stable TBBG_ key need those notifications
        -- too. Rebuilt each registration pass (anchor index shifts on edits/deletes).
        local aliases = EllesmereUI._unlockKeyAliases
        if not aliases then
            aliases = {}
            EllesmereUI._unlockKeyAliases = aliases
        end
        for k, v in pairs(aliases) do
            if type(v) == "string" and v:find("^TBBG_") then aliases[k] = nil end
        end
        for gkey, entry in pairs(reg) do
            local gk = gkey
            local lgid = ns.TBBLocalGidForGlobal(gk)
            local anchorIdx = lgid and ns.TBBGroupAnchorIndex(lgid)
            if anchorIdx then
                aliases["TBB_" .. anchorIdx] = "TBBG_" .. gk
            end
            elements[#elements + 1] = MK({
                key   = "TBBG_" .. gk,
                label = EllesmereUI.Lf("Tracking Bars: %1$s", entry.name or gk),
                group = "Cooldown Manager",
                order = 651,
                noResize = true,
                allowMatchSource  = true,
                noSizeMatchTarget = true,
                isHidden = function()
                    local gid = ns.TBBLocalGidForGlobal(gk)
                    return not gid or not ns.TBBGroupAnchorIndex(gid)
                end,
                isAnchored = function() return false end,
                getFrame = function()
                    local gid = ns.TBBLocalGidForGlobal(gk)
                    local ai = gid and ns.TBBGroupAnchorIndex(gid)
                    if ai then return tbbFrames[ai] end
                    -- No member bars on the active spec. With "Shift Elements If
                    -- No Bars" set, the opt-in stand-in holds the group's slot so
                    -- anchored elements keep position (and shift into it); with
                    -- it off (None), nil keeps legacy behavior -- anchors stay
                    -- dormant (or take their stored fallback) instead of gluing
                    -- to a stale frame. A stand-in built earlier this session
                    -- keeps resolving after a None flip (see TBBStandinFrame).
                    local e = ns.TBBGlobalGroup(gk)
                    if e and (e.shiftNoBar == "Up" or e.shiftNoBar == "Down") then
                        return ns.TBBEnsureStandin(gk)
                    end
                    return ns.TBBStandinFrame and ns.TBBStandinFrame(gk) or nil
                end,
                getSize = function()
                    local gid = ns.TBBLocalGidForGlobal(gk)
                    local ai = gid and ns.TBBGroupAnchorIndex(gid)
                    local t = ns.GetTrackedBuffBars()
                    local c = ai and t.bars and t.bars[ai]
                    local PPg = EllesmereUI and EllesmereUI.PP
                    local sn = PPg and PPg.Snap or function(v) return v end
                    if c then
                        return sn(c.width or 270), sn(c.height or 24)
                    end
                    -- Memberless spec: the registry's last-stamped anchor size
                    -- (what the stand-in renders at), else the defaults.
                    local e = ns.TBBGlobalGroup(gk)
                    if e and e.width then
                        return sn(e.width), sn(e.height or 24)
                    end
                    return 270, 24
                end,
                setWidth = function(_, w)
                    local gid = ns.TBBLocalGidForGlobal(gk)
                    local ai = gid and ns.TBBGroupAnchorIndex(gid)
                    local t = ns.GetTrackedBuffBars()
                    local c = ai and t.bars and t.bars[ai]
                    local PPt = EllesmereUI and EllesmereUI.PP
                    w = PPt and PPt.Snap(w) or math.floor(w + 0.5)
                    if c then
                        local f = tbbFrames[ai]
                        if EllesmereUI._unlockActive or EllesmereUI._propagatingMatch then
                            c.width = w
                            ns.PropagateTBBGroupSize(ai, "width", w)
                        end
                        if f then f:SetWidth(w) end
                        return
                    end
                    -- Memberless spec, STRICTLY gated on "Shift Elements If No
                    -- Bars" being Up/Down (the stand-in feature): a width match
                    -- landing here must still persist (the registry stamp is
                    -- what the stand-in renders from) and resize the frame, so
                    -- its size-changed hook reaches anchored children -- an
                    -- edge-preserve follower has to track the matched width
                    -- even while the group has no bars (field report). With the
                    -- option off this stays the legacy hard no-op: no write,
                    -- no resize.
                    local e = ns.TBBGlobalGroup(gk)
                    if not (e and (e.shiftNoBar == "Up" or e.shiftNoBar == "Down")) then return end
                    if EllesmereUI._unlockActive or EllesmereUI._propagatingMatch then
                        e.width = w
                    end
                    local sf = ns.TBBStandinFrame and ns.TBBStandinFrame(gk)
                    if sf then sf:SetWidth(w) end
                end,
                setHeight = function(_, h)
                    local gid = ns.TBBLocalGidForGlobal(gk)
                    local ai = gid and ns.TBBGroupAnchorIndex(gid)
                    local t = ns.GetTrackedBuffBars()
                    local c = ai and t.bars and t.bars[ai]
                    local PPt = EllesmereUI and EllesmereUI.PP
                    h = PPt and PPt.Snap(h) or math.floor(h + 0.5)
                    if c then
                        local f = tbbFrames[ai]
                        if EllesmereUI._unlockActive or EllesmereUI._propagatingMatch then
                            c.height = h
                            ns.PropagateTBBGroupSize(ai, "height", h)
                        end
                        if f then f:SetHeight(h) end
                        return
                    end
                    -- Memberless stand-in: same strict option gate as setWidth
                    -- (option off = legacy hard no-op). Height also feeds the
                    -- shift magnitude (target height), so anchored children
                    -- re-shift to the matched size.
                    local e = ns.TBBGlobalGroup(gk)
                    if not (e and (e.shiftNoBar == "Up" or e.shiftNoBar == "Down")) then return end
                    if EllesmereUI._unlockActive or EllesmereUI._propagatingMatch then
                        e.height = h
                    end
                    local sf = ns.TBBStandinFrame and ns.TBBStandinFrame(gk)
                    if sf then sf:SetHeight(h) end
                end,
                savePos = function(_, point, relPoint, x, y)
                    local e = ns.TBBGlobalGroup(gk)
                    if not e then return end
                    e.pos = { point = point, relPoint = relPoint, x = x, y = y }
                    if not EllesmereUI._unlockActive then
                        ns.BuildTrackedBuffBars()
                    end
                end,
                loadPos = function()
                    local e = ns.TBBGlobalGroup(gk)
                    return e and e.pos
                end,
                clearPos = function()
                    local e = ns.TBBGlobalGroup(gk)
                    if e then e.pos = nil end
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

    -- Fallback anchors: bars/groups may have appeared or vanished for this spec -- let
    -- opted-in children re-evaluate (no-op when nobody opted in, or before the unlock module has loaded).
    if EllesmereUI.NotifyFallbackTargetsChanged then
        EllesmereUI.NotifyFallbackTargetsChanged()
    end
end
_G._ECME_RegisterTBBUnlock = ns.RegisterTBBUnlockElements
