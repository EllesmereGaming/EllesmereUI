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

local function SetFont(fs, size) EllesmereUI.ApplyModuleFont(fs, nil, size, "cdm") end

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
-- How much of the aura's remaining time a refresh would carry over: the
-- pandemic window as the client sees it (talents and effects that stretch
-- the cap included). 12.1.5 answers directly; 12.1.0 derives it as Blizzard's
-- own viewer did there (refreshed duration minus base duration). nil when
-- neither API exists or the answer is secret: the caller then uses 30%.
local function CarryOver(unit, auraInstanceID)
    local U = C_UnitAuras
    local ok, carry
    if U.GetRefreshCarryOverDuration then
        ok, carry = pcall(U.GetRefreshCarryOverDuration, unit, auraInstanceID)
    elseif U.GetRefreshExtendedDuration and U.GetAuraBaseDuration then
        local ok1, ext = pcall(U.GetRefreshExtendedDuration, unit, auraInstanceID)
        local ok2, base = pcall(U.GetAuraBaseDuration, unit, auraInstanceID)
        if ok1 and ok2 and ext and base and not issecretvalue(ext) and not issecretvalue(base) then
            ok, carry = true, ext - base
        end
    end
    if ok and carry and not issecretvalue(carry) then return carry end
end
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
        local remaining = exp - now
        -- The carry-over equals the remaining time once inside the window and
        -- the cap before it (a hair of slack for the two clock reads).
        local carry = aura.auraInstanceID and CarryOver(unit, aura.auraInstanceID)
        if carry then
            if carry > 0 and remaining <= carry + 0.05 then result = true end
        elseif remaining <= dur * PANDEMIC_THRESHOLD then
            result = true
        end
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
    chargeHashShade = false,      -- darken the partially recharged charge segment
    chargeHashShadeAlpha = 0.5,   -- darkness of the partial-charge shade (0-1)
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

-- Main-chunk locals the EUI_CDM_BuffBar*.lua files re-import by name; each of
-- them adds what the files behind it need. <name>Setters: every file reading
-- that value keeps its own copy and adds a setter; a place that assigns it
-- calls Set<Name> (built below), which runs them all. ECME is set this way
-- during BuildTrackedBuffBars (ECME.db is not ready at file load).
EllesmereUI.NewInternals(ns, "_buffBarInternals", {
    _blizzBarFS = _blizzBarFS, _classB = _classB, _classG = _classG, _classR = _classR,
    _pandemicState = _pandemicState, BBFS = BBFS, FormatTime = FormatTime,
    LifebloomPandemic = LifebloomPandemic, SetFont = SetFont, SetTBBTextColor = SetTBBTextColor,
    StartGlow = StartGlow, StopGlow = StopGlow, TBB_DEFAULT_BAR = TBB_DEFAULT_BAR,
    TBB_POPULAR_BUFFS = TBB_POPULAR_BUFFS, TBB_TEXTURES = TBB_TEXTURES,
    ecmeSetters = {}, anyPandemicSetters = {}, anyThresholdSetters = {}, anyStacksSetters = {},
    anyVisCondSetters = {}, tickFrameSetters = {}, rebuildPendingSetters = {},
    assignDirtySetters = {}, reflowDirtySetters = {}, restoreNormalFillSetters = {},
}, {
    SetECME = "ecmeSetters", SetAnyPandemic = "anyPandemicSetters",
    SetAnyThreshold = "anyThresholdSetters", SetAnyStacks = "anyStacksSetters",
    SetAnyVisCond = "anyVisCondSetters", SetTickFrame = "tickFrameSetters",
    SetRebuildPending = "rebuildPendingSetters", SetAssignDirty = "assignDirtySetters",
    SetReflowDirty = "reflowDirtySetters", SetRestoreNormalFill = "restoreNormalFillSetters",
})
