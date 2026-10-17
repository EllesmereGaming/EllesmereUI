if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_AuraBuffReminders_Lifecycle.lua
--
--  The main event frame, OnInitialize, OnEnable, the event handler, the
--  item-use detection and the event registration.
--  Reads the earlier AuraBuff Reminders files through ns._abrInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._abrInternals
-- EllesmereUIAuraBuffReminders.lua or an earlier AuraBuff Reminders file
-- failed to load.
if not I or I.broken then return end
I.broken = true

local floor = math.floor

local CacheInstanceInfo, EABR = I.CacheInstanceInfo, I.EABR
local EnsureGlowModeMigrated, GetPlayerClass = I.EnsureGlowModeMigrated, I.GetPlayerClass
local GetSpecID, InCombat = I.GetSpecID, I.InCombat
local InRealInstancedContent, Known = I.InRealInstancedContent, I.Known
local MarkDungeonPullStarted, Tex = I.MarkDungeonPullStarted, I.Tex
local _ownOnRaidIDs, _preCombatOwnOnRaidCache = I._ownOnRaidIDs, I._preCombatOwnOnRaidCache
local _unitInRange, GetWeaponCategory = I._unitInRange, I.GetWeaponCategory
local SnapshotOwnOnRaidBuffs = I.SnapshotOwnOnRaidBuffs
local SnapshotPlayerAuras, _bagCounts, AURAS = I.SnapshotPlayerAuras, I._bagCounts, I.AURAS
local FLASK_ITEMS, FOOD_ITEMS = I.FLASK_ITEMS, I.FOOD_ITEMS
local InvalidateItemCountCache, PALADIN_RITES = I.InvalidateItemCountCache, I.PALADIN_RITES
local RAID_BUFFS, RebuildBagCounts = I.RAID_BUFFS, I.RebuildBagCounts
local ROGUE_POISONS, SHAMAN_IMBUES = I.ROGUE_POISONS, I.SHAMAN_IMBUES
local SHAMAN_SHIELDS, WARLOCK_PETS = I.SHAMAN_SHIELDS, I.WARLOCK_PETS
local WEAPON_ENCHANT_CHOICES = I.WEAPON_ENCHANT_CHOICES
local WEAPON_ENCHANT_ITEMS, _dismissedUntilLoad = I.WEAPON_ENCHANT_ITEMS, I._dismissedUntilLoad
local defaults, GLOW_VIEW, combatIconPool = I.defaults, I.GLOW_VIEW, I.combatIconPool
local GetStrata, HideCombatIcons = I.GetStrata, I.HideCombatIcons
local HideCursorIcons, ICON_SIZE, iconPool = I.HideCursorIcons, I.ICON_SIZE, I.iconPool
local HideAllIcons, RequestRefresh = I.HideAllIcons, I.RequestRefresh
local ApplyUnlockPos, RegisterUnlockElements = I.ApplyUnlockPos, I.RegisterUnlockElements
local BeaconInit, BeaconRefresh, TrackItemUse = I.BeaconInit, I.BeaconRefresh, I.TrackItemUse
local BeaconCombatEdge, CursorAttachActive = I.BeaconCombatEdge, I.CursorAttachActive
local SetDB, SetIconAnchor, SetCombatAnchor = I.SetDB, I.SetIconAnchor, I.SetCombatAnchor
local SetCursorAnchor, SetPanelOpen = I.SetCursorAnchor, I.SetPanelOpen
local SetInCombat, SetHuntersMarkNeeded = I.SetInCombat, I.SetHuntersMarkNeeded

local db
I.dbSetters[#I.dbSetters + 1] = function(v) db = v end
local iconAnchor
I.iconAnchorSetters[#I.iconAnchorSetters + 1] = function(v) iconAnchor = v end
local combatAnchor
I.combatAnchorSetters[#I.combatAnchorSetters + 1] = function(v) combatAnchor = v end
local cursorAnchor
I.cursorAnchorSetters[#I.cursorAnchorSetters + 1] = function(v) cursorAnchor = v end

local _encounterSnapshotTime = nil
local _needGroupAura = false
local _isEvokerOwnOnRaid = false
local _groupAuraBroadActive = false
local _groupAuraDirty = false
local pendingOOCRefresh = false

-------------------------------------------------------------------------------
--  MAIN EVENT FRAME (forward-declared so OnEnable can reference it)
-------------------------------------------------------------------------------
local mainFrame = CreateFrame("Frame")

-- Toggles broad vs player-only UNIT_AURA registration; file-scope so OnEnable and the event handler can both use it.
local function _setBroad(on)
    if on and not _groupAuraBroadActive then
        mainFrame:RegisterEvent("UNIT_AURA")
        _groupAuraBroadActive = true
    elseif not on and _groupAuraBroadActive then
        mainFrame:UnregisterEvent("UNIT_AURA")
        mainFrame:RegisterUnitEvent("UNIT_AURA", "player")
        _groupAuraBroadActive = false
    end
end

-- Whether group-wide UNIT_AURA stays registered through combat: the Evoker
-- own-cast cache, the targeted own-aura tracker and the provider view
-- ("others missing") read group aura changes mid-fight. One predicate for the
-- pull edge and the registration pass so the two cannot drift.
function EABR.KeepGroupAuraInCombat()
    if _isEvokerOwnOnRaid or EABR._trackOwnOtherAuraID ~= nil then return true end
    local rbSW = db and db.profile.raidBuffs and db.profile.raidBuffs.showWhen
    if not (EABR._needsProviderCoverage and rbSW) then return false end
    return rbSW.othersMissing ~= false
end

-------------------------------------------------------------------------------
--  Lifecycle: OnInitialize (fires at ADDON_LOADED time). Creates the DB early so EABR is in _dbRegistry before PreSeedSpecProfile.
-------------------------------------------------------------------------------
function EABR:OnInitialize()
    SetDB(EllesmereUI.Lite.NewDB("EllesmereUIAuraBuffRemindersDB", defaults, true))

    ---------------------------------------------------------------------------
    --  Legacy visibility-model migration. Keyed off LEGACY field presence
    --  (the DB layer has already merged the new defaults, so nil checks on
    --  the new keys cannot detect an old profile); fresh installs carry no
    --  legacy keys and every block no-ops.
    ---------------------------------------------------------------------------
    local p = db.profile
    local co = p and p.consumables
    -- Old single Augment Rune dropdown -> the dormant per-item "Show In"
    -- tier set (kept for the future per-item conditions cog).
    if co and co.runeDisplayMode ~= nil then
        co.showIn = co.showIn or {}
        co.showIn.augment_rune = co.runeDisplayMode
        co.runeDisplayMode = nil
    end
    -- Old tiered "Show In" strings -> per-difficulty override sets. Absent
    -- category = on, so only unchecked difficulties store false ("all" =
    -- cleared entirely).
    if co and co.showIn then
        local function tierToSet(tier)
            if tier == "heroic_mythic" then
                return { d_normal=false, r_normal=false, r_lfr=false }
            elseif tier == "mythic" then
                return { d_normal=false, d_heroic=false, r_lfr=false, r_normal=false, r_heroic=false }
            end
            return nil  -- "all" or unknown => every difficulty on
        end
        for k, v in pairs(co.showIn) do
            if type(v) == "string" then
                co.showIn[k] = tierToSet(v)
            end
        end
    end
    -- Per-spell/open-world/others-missing model -> per-section "Where to
    -- Show" + "Show When". Open-world masters map to the open_world bucket;
    -- everything else is retired.
    local rb = p and p.raidBuffs
    if rb and (rb.showOthersMissing ~= nil or rb.showNonInstanced ~= nil) then
        rb.showWhen = { othersMissing = (rb.showOthersMissing ~= false), iAmMissing = false }
        rb.whereToShow = { open_world = (rb.showNonInstanced == true) }
        rb.showOthersMissing, rb.showNonInstanced = nil, nil
    end
    local au = p and p.auras
    if au and au.showNonInstanced ~= nil then
        au.whereToShow = { open_world = (au.showNonInstanced ~= false) }
        au.showNonInstanced = nil
    end
    if co and co.showSpecialsNonInstanced ~= nil then
        co.specialsWhereToShow = { open_world = (co.showSpecialsNonInstanced ~= false) }
        co.showSpecialsNonInstanced = nil
    end
    -- Old party/raid consumable thresholds -> the global timing pair.
    local disp = p and p.display
    if disp then
        if disp.showUnderDurationDungeon ~= nil or disp.showUnderDurationRaid ~= nil then
            if disp.showUnder == nil then disp.showUnder = disp.showUnderDurationRaid or 5 end
            if disp.showUnderMPlus == nil then disp.showUnderMPlus = disp.showUnderDurationDungeon or 40 end
            disp.showUnderDurationDungeon = nil
            disp.showUnderDurationRaid = nil
        end
        if disp.showUnder == nil then disp.showUnder = 5 end
        if disp.showUnderMPlus == nil then disp.showUnderMPlus = 40 end
    end
    -- Retired per-section scale keys (display scale is the one knob).
    if rb then rb.scale = nil end
    if au then au.scale = nil end
    if co then co.scale = nil end

    -- Migrates the login-active profile eagerly; profiles activated later are covered by the read-path call in ResolveGlowTint.
    EnsureGlowModeMigrated(db.profile.display)
end

-------------------------------------------------------------------------------
--  Lifecycle: OnEnable (fires at PLAYER_LOGIN time, after PreSeedSpecProfile). All UI creation and event wiring that depends on db being ready.
-------------------------------------------------------------------------------
function EABR:OnEnable()
    -- Expose globals for options
    _G._EABR_AceDB = db

    -- Talent reminder migration handled by EllesmereUIABR_TalentReminders.lua

    _G._EABR_RequestRefresh = RequestRefresh
    _G._EABR_ApplyIconBorder = EABR.ApplyIconBorder
    _G._EABR_ApplyAllIconBorders = EABR.ApplyAllIconBorders
    _G._EABR_HideAllIcons = HideAllIcons
    _G._EABR_GLOW_VIEW = GLOW_VIEW
    _G._EABR_EnsureGlowModeMigrated = EnsureGlowModeMigrated
    _G._EABR_RegisterUnlock = RegisterUnlockElements
    _G._EABR_ApplyUnlockPos = ApplyUnlockPos
    _G._EABR_RAID_BUFFS = RAID_BUFFS
    _G._EABR_AURAS = AURAS
    _G._EABR_ROGUE_POISONS = ROGUE_POISONS
    _G._EABR_PALADIN_RITES = PALADIN_RITES
    _G._EABR_SHAMAN_IMBUES = SHAMAN_IMBUES
    _G._EABR_SHAMAN_SHIELDS = SHAMAN_SHIELDS
    _G._EABR_WARLOCK_PETS = WARLOCK_PETS
    _G._EABR_WEAPON_ENCHANT_ITEMS = WEAPON_ENCHANT_ITEMS
    _G._EABR_Tex = Tex
    _G._EABR_Known = Known
    _G._EABR_ICON_SIZE = ICON_SIZE
    _G._EABR_FLASK_ITEMS = FLASK_ITEMS
    _G._EABR_FOOD_ITEMS = FOOD_ITEMS
    _G._EABR_FLASK_BUFF_ID_SET = I.FLASK_BUFF_ID_SET
    _G._EABR_RUNE_BUFF_IDS = I.RUNE_BUFF_IDS
    _G._EABR_WEAPON_ENCHANT_CHOICES = WEAPON_ENCHANT_CHOICES
    -- _EABR_TALENT_REMINDER_ZONES set by EllesmereUIABR_TalentReminders.lua

    local STRATA_VALUES = EllesmereUI.FRAME_STRATA_LABELS
    local STRATA_ORDER = EllesmereUI.FRAME_STRATA_ORDER_FULL
    _G._EABR_STRATA_VALUES = STRATA_VALUES
    _G._EABR_STRATA_ORDER = STRATA_ORDER

    SetIconAnchor(CreateFrame("Frame", "EABR_Anchor", UIParent))
    iconAnchor:SetSize(1, 1)
    iconAnchor:SetFrameStrata(GetStrata())
    iconAnchor:EnableMouse(false)
    ApplyUnlockPos()

    -- Combat anchor: non-secure, follows iconAnchor position; parented to UIParent so Show/Hide is never blocked by combat lockdown.
    SetCombatAnchor(CreateFrame("Frame", "EABR_CombatAnchor", UIParent))
    combatAnchor:SetSize(1, 1)
    combatAnchor:SetFrameStrata(GetStrata())
    combatAnchor:SetFrameLevel(110)
    combatAnchor:EnableMouse(false)
    combatAnchor:SetAllPoints(iconAnchor)
    combatAnchor:Show()
    EllesmereUI.SetElementVisibility(combatAnchor, false)

    -- Cursor anchor: tracks cursor position via OnUpdate (same as CDM).
    SetCursorAnchor(CreateFrame("Frame", "EABR_CursorAnchor", UIParent))
    cursorAnchor:SetSize(1, 1)
    cursorAnchor:SetFrameStrata("TOOLTIP")
    cursorAnchor:SetFrameLevel(9980)
    cursorAnchor:EnableMouse(false)
    cursorAnchor:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    do
        -- Cursor glue on the suite's shared cursor service (Tier A motionOnly: fires per render frame while the cursor MOVES, parked at rest). Subscription follows the frame's own OnShow/OnHide; OnShow snaps once via M.Get() so a cursor that moved while hidden never shows stale.
        local lastMX, lastMY
        local function GlueBody(rawX, rawY)
            local s = UIParent:GetEffectiveScale()
            local cx = floor(rawX / s + 0.5)
            local cy = floor(rawY / s + 0.5)
            if cx ~= lastMX or cy ~= lastMY then
                lastMX, lastMY = cx, cy
                cursorAnchor:ClearAllPoints()
                cursorAnchor:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy + 60)
            end
        end
        cursorAnchor:SetScript("OnShow", function()
            local M = EllesmereUI.Mouse
            if M then
                GlueBody(M.Get())
                M.SubscribeFrame("abrCursor", GlueBody, true)
            end
        end)
        cursorAnchor:SetScript("OnHide", function()
            local M = EllesmereUI.Mouse
            if M then M.UnsubscribeFrame("abrCursor") end
        end)
    end
    -- Starts hidden: OnUpdate only runs while :IsShown(), saving CPU when no cursor-attached reminders are active.
    cursorAnchor:Hide()
    EllesmereUI.SetElementVisibility(cursorAnchor, false)

    -- Talent reminder anchor created by EllesmereUIABR_TalentReminders.lua (independent of iconAnchor so parent alpha doesn't hide it).

    local function ApplyStrata()
        local strata = GetStrata()
        iconAnchor:SetFrameStrata(strata)
        combatAnchor:SetFrameStrata(strata)
        for _, btn in pairs(iconPool) do btn:SetFrameStrata(strata) end
        for _, f in pairs(combatIconPool) do f:SetFrameStrata(strata) end
        if EABR._providerCastBtn and not InCombatLockdown() then
            EABR._providerCastBtn:SetFrameStrata(strata)
        end
        EABR.ApplyAllIconBorders()
    end
    _G._EABR_ApplyStrata = ApplyStrata

    -- Hook EUI panel show/hide
    if EllesmereUI then
        EllesmereUI:RegisterOnShow(function()
            SetPanelOpen(true); HideAllIcons(); BeaconRefresh()
        end)
        EllesmereUI:RegisterOnHide(function()
            SetPanelOpen(false); RequestRefresh(); BeaconRefresh()
        end)
    end

    -- Group spec intel over addon comms (LibSpecialization): the lib
    -- handles all transmission itself (request on group join, broadcast on
    -- spec change, chat-lockdown deferral); we only consume its callback.
    -- Never call its request functions -- registration is the whole
    -- integration. Cache writes fire one coalesced refresh on CHANGE only,
    -- so the join burst (one callback per responding member) costs table
    -- writes plus a single refresh.
    do
        local LS = LibStub and LibStub("LibSpecialization", true)
        if LS then
            LS.RegisterGroup(EABR, function(specID, _, _, playerName)
                if type(specID) == "number" and type(playerName) == "string" then
                    if EABR._groupSpecs[playerName] ~= specID then
                        EABR._groupSpecs[playerName] = specID
                        RequestRefresh()
                    end
                end
            end)
        end
    end

    EABR.ScanEatingState()
    EABR.SyncProviderCastSpell()
    RequestRefresh()
    if not EABR.FOREVER then BeaconInit() end  -- retail Holy Paladin beacons only
    C_Timer.After(0.5, RegisterUnlockElements)

    -- Registers broad UNIT_AURA only when the class needs group aura tracking AND only OOC: it fires 100+/sec in a raid, but in-combat CollectRaidBuffs only checks the player's own auras (PlayerHasAuraByID), so group events are pure waste. Evoker keeps broad in combat for ownOnRaid cache updates but skips RequestRefresh on group events (handler below).
    local function UpdateGroupAuraRegistration()
        -- WoW Forever keeps the player-only UNIT_AURA from file scope,
        -- whichever caller (loading screen, profile, spec override, options)
        -- runs this pass: its one group reader, Raid Buffs, has its own watch,
        -- synced by every refresh (EABR.FvSyncGroupWatch).
        if EABR.FOREVER then return end
        local playerClass = GetPlayerClass()
        local moonkinOn = playerClass == "DRUID"
            and db.profile.auras.enabled.moonkin_form == true
            and db.profile.display.remindersEnabled ~= false
            and GetSpecID() == 102 and Known(24858)
        if moonkinOn then
            mainFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
            mainFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
        else
            mainFrame:UnregisterEvent("UPDATE_SHAPESHIFT_FORM")
            mainFrame:UnregisterEvent("UPDATE_SHAPESHIFT_FORMS")
        end
        _needGroupAura = false
        _isEvokerOwnOnRaid = false
        EABR._needsProviderCoverage = false
        EABR._needsGroupAuraRefresh = false
        -- Only the own-cast group checks re-evaluate on roster changes: a
        -- provider's coverage already follows the joiner's UNIT_AURA.
        EABR._rosterRefresh = false
        -- One gate controls the targeted own-aura cache. Do not pay its cost
        -- unless the relevant reminder can actually be used/shown.
        local prevTrackID = EABR._trackOwnOtherAuraID
        EABR._trackOwnOtherAuraID = nil
        local co = db.profile.consumables
        local au = db.profile.auras
        if playerClass == "SHAMAN" and Known(383010)
           and co and co.enabled and co.enabled.es_ally == true
           and (IsInGroup() or IsInRaid()) then
            EABR._trackOwnOtherAuraID = 974
        elseif playerClass == "EVOKER" and Known(369459)
           and au and au.enabled and au.enabled.som ~= false
           and InRealInstancedContent() and (IsInGroup() or IsInRaid()) then
            EABR._trackOwnOtherAuraID = 369459
        end
        local trackID = EABR._trackOwnOtherAuraID
        if prevTrackID and prevTrackID ~= trackID then
            -- State kept while untracked goes stale: the old id reads as
            -- unknown (suppressed) until a scan proves it again.
            local wasKnown = EABR._ownOtherAuraCache[prevTrackID] ~= nil
            EABR._ownOtherAuraCache[prevTrackID] = nil
            EABR._ownOtherAuraTargetGUID[prevTrackID] = nil
            EABR._ownOtherAuraDuration[prevTrackID] = nil
            EABR._ownOtherAuraExpiration[prevTrackID] = nil
            if wasKnown then RequestRefresh() end
        end
        if trackID then
            _needGroupAura = true
            EABR._rosterRefresh = true
        end
        for _, buff in ipairs(RAID_BUFFS) do
            if buff.class == playerClass then
                _needGroupAura = true
                EABR._needsProviderCoverage = true
                EABR._needsGroupAuraRefresh = true
                break
            end
        end
        for _, aura in ipairs(AURAS) do
            if aura.class == playerClass and aura.key ~= "som"
                and (aura.check == "ownOnRaid" or aura.check == "ownGroupOrSelf")
                and db.profile.auras.enabled[aura.key] ~= false then
                _needGroupAura = true
                EABR._rosterRefresh = true
                EABR._needsGroupAuraRefresh = true
                if playerClass == "EVOKER" and aura.check == "ownOnRaid" and aura.key ~= "som" then
                    _isEvokerOwnOnRaid = true
                end
                break
            end
        end
        if _needGroupAura then
            mainFrame:RegisterEvent("GROUP_JOINED")
            mainFrame:RegisterEvent("GROUP_LEFT")
            -- Start broad if OOC; in combat only while a group reader needs it
            -- (the same predicate as the pull edge).
            if InCombat() and not EABR.KeepGroupAuraInCombat() then
                _setBroad(false)
            else
                _setBroad(true)
            end
        else
            _setBroad(false)
            mainFrame:UnregisterEvent("GROUP_JOINED")
            mainFrame:UnregisterEvent("GROUP_LEFT")
        end
        -- Tracking just turned on: seed the cache (the scan is OOC-only;
        -- combat end rescans otherwise).
        if trackID and trackID ~= prevTrackID then EABR.RescanOwnOtherAuras() end
    end
    _G._EABR_UpdateGroupAuraRegistration = UpdateGroupAuraRegistration
    -- Also seeds the targeted-aura cache when tracking turns on. A no-op on
    -- WoW Forever, which keeps the player-only UNIT_AURA from file scope.
    UpdateGroupAuraRegistration()

    -- Register spellcast tracking for Hunters (combat reminder for Hunter's Mark)
    if not EABR.FOREVER and (GetPlayerClass() == "HUNTER" or GetPlayerClass() == "EVOKER") then
        mainFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    end

    -- WoW Forever's Raid Buffs watch tracks its own range (EABR.FvSyncGroupWatch).
    if EABR.FOREVER then return end

    ---------------------------------------------------------------------------
    --  Range updates: UNIT_IN_RANGE_UPDATE mirrors the raid frames' range path, so range changes retrigger group-buff evaluation without polling.
    ---------------------------------------------------------------------------
    local _lastRangeSet = {}   -- [unitToken] = true/false (last known in-range state)

    -- Pre-build unit token strings to avoid per-poll allocations
    local _raidTokens = {}
    local _partyTokens = {}
    for i = 1, 40 do _raidTokens[i] = "raid" .. i end
    for i = 1, 4 do _partyTokens[i] = "party" .. i end

    local rangeFrame = CreateFrame("Frame")
    local _rangeTrackers = {}
    local function _checkUnit(u)
        if not UnitExists(u) then
            if _lastRangeSet[u] ~= nil then
                _lastRangeSet[u] = nil
                return true
            end
            return false
        end
        local state = _unitInRange(u)
        if _lastRangeSet[u] ~= state then
            _lastRangeSet[u] = state
            return true
        end
        return false
    end

    local function _checkAllRangeUnits()
        local changed = false
        if IsInRaid() then
            for i = 1, GetNumGroupMembers() do
                if _checkUnit(_raidTokens[i]) then changed = true end
            end
        elseif IsInGroup() then
            for i = 1, GetNumSubgroupMembers() do
                if _checkUnit(_partyTokens[i]) then changed = true end
            end
        end
        return changed
    end

    local function _onRangeEvent(_, event, unit)
        if event == "UNIT_PHASE" then
            if _checkAllRangeUnits() then RequestRefresh() end
        elseif unit and _checkUnit(unit) then
            RequestRefresh()
        end
    end

    local function _clearRangeTrackers()
        for _, tracker in pairs(_rangeTrackers) do
            tracker:UnregisterAllEvents()
        end
    end

    local function _trackRangeUnit(unit)
        if UnitIsUnit(unit, "player") then return end
        local tracker = _rangeTrackers[unit]
        if not tracker then
            tracker = CreateFrame("Frame")
            tracker:SetScript("OnEvent", _onRangeEvent)
            _rangeTrackers[unit] = tracker
        end
        tracker:RegisterUnitEvent("UNIT_IN_RANGE_UPDATE", unit)
        tracker:RegisterUnitEvent("UNIT_CONNECTION", unit)
    end

    local function _rebuildRangeTracking()
        _clearRangeTrackers()
        wipe(_lastRangeSet)
        if IsInRaid() then
            for i = 1, GetNumGroupMembers() do _trackRangeUnit(_raidTokens[i]) end
        elseif IsInGroup() then
            for i = 1, GetNumSubgroupMembers() do _trackRangeUnit(_partyTokens[i]) end
        end
        if _checkAllRangeUnits() then RequestRefresh() end
    end

    rangeFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    rangeFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    rangeFrame:RegisterEvent("UNIT_PHASE")
    rangeFrame:SetScript("OnEvent", function(_, event)
        if event == "UNIT_PHASE" then
            _onRangeEvent(nil, event)
        else
            _rebuildRangeTracking()
        end
    end)
    _rebuildRangeTracking()
end

-- Combat start with the buffs on the cursor (Only on Cursor in Combat turns
-- that on here): the buff you provide moves from its secure button to the
-- cursor, so the button parks now, while moving it and its mouse is still
-- allowed. In combat it could only fade, and would stay clickable where it sat.
local function ParkProviderForCursor()
    if db and CursorAttachActive(db.profile.display) then EABR.ParkProviderCastButton() end
end

-------------------------------------------------------------------------------
--  MAIN EVENT HANDLER (OnEvent script for runtime events)
-------------------------------------------------------------------------------
mainFrame:SetScript("OnEvent", function(_, e, arg1, arg2, arg3)
    if e == "ENCOUNTER_START" then
        SnapshotPlayerAuras()
        if _isEvokerOwnOnRaid then SnapshotOwnOnRaidBuffs() end
        _encounterSnapshotTime = GetTime()
        -- Marks combat immediately: ENCOUNTER_START fires before InCombatLockdown() returns true but aura APIs are already restricted; without this, non-whitelisted buffs flash "missing" for ~1s.
        SetInCombat(true)
        ParkProviderForCursor()
        BeaconCombatEdge()
        RequestRefresh()
        return
    end

    if e == "PLAYER_REGEN_DISABLED" then
        -- First pull of this dungeon visit: the elevated pre-key/pre-pull
        -- threshold (EABR.GetShowUnderMinutes' showUnderMPlus) is over.
        -- WoW Forever has no pre-key window, none of retail's broad group aura
        -- registration (its Raid Buffs keep their own watch) and no Hunter's
        -- Mark reminder: the whole retail pull bookkeeping is skipped.
        if not EABR.FOREVER then
        MarkDungeonPullStarted()
        -- Drops broad UNIT_AURA in combat unless a group reader needs it (EABR.KeepGroupAuraInCombat).
        if _needGroupAura and not EABR.KeepGroupAuraInCombat() then _setBroad(false) end
        -- Only flag Hunter's Mark needed if the target doesn't already have it
        SetHuntersMarkNeeded(true)
        if C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID
            and UnitExists("target") and C_UnitAuras.GetUnitAuraBySpellID("target", 257284) then
            SetHuntersMarkNeeded(false)
        end
        end -- not FOREVER
        -- Hide secure buttons before lockdown. ENCOUNTER_START may already have
        -- set our combat flag, so HideAllIcons guards on InCombatLockdown itself.
        HideAllIcons()
        HideCursorIcons()
        -- Re-snapshots only if ENCOUNTER_START didn't just do it (fires ms before REGEN_DISABLED, producing a cleaner snapshot since the aura API is fully available pre-lockdown).
        -- Must snapshot before marking combat, or the group-buff lookup treats itself as restricted and reports nothing found.
        if not _encounterSnapshotTime or (GetTime() - _encounterSnapshotTime) > 1 then
            SnapshotPlayerAuras()
            if _isEvokerOwnOnRaid then SnapshotOwnOnRaidBuffs() end
        end
        SetInCombat(true)
        _encounterSnapshotTime = nil
        ParkProviderForCursor()
        BeaconCombatEdge()
        RequestRefresh()
        return
    end

    -- A fast encounter reset can end without a player combat transition, so
    -- clear ENCOUNTER_START's synthetic flag when lockdown is already gone.
    if e == "PLAYER_REGEN_ENABLED" or (e == "ENCOUNTER_END" and not InCombatLockdown()) then
        SetInCombat(false)
        -- Restore broad UNIT_AURA for OOC group buff tracking
        if _needGroupAura then _setBroad(true) end
        -- Leaving combat: clean up combat icons, do full OOC refresh with secure buttons
        SetHuntersMarkNeeded(false)
        HideCombatIcons()
        HideCursorIcons()
        BeaconCombatEdge()
        pendingOOCRefresh = false
        EABR.RescanOwnOtherAuras()
        RequestRefresh()
        return
    end

    if e == "UNIT_SPELLCAST_SUCCEEDED" then
        -- arg1 = unit ("player"), arg2 = castGUID, arg3 = spellID
        if arg3 == 257284 then
            SetHuntersMarkNeeded(false)
            RequestRefresh()
        elseif arg3 == 369459 and EABR._trackOwnOtherAuraID == 369459 then
            -- Cast success is an immediate fallback; UNIT_AURA will subsequently
            -- attach the concrete target GUID/auraInstanceID via HELPFUL|PLAYER.
            EABR.SetOwnOtherAuraState(369459, true)
        end
        return
    end

    if e == "PLAYER_DEAD" then
        -- Inky Blackness (and other buffs) drop on death; refresh so aura-based reminders re-evaluate and reappear once lost.
        RequestRefresh()
        return
    end

    if e == "PLAYER_ENTERING_WORLD" then
        wipe(_dismissedUntilLoad)
        -- Preserve the last known targeted-aura state across loading screens;
        -- nil is unknown and readers suppress until the delayed rescan resolves it.
        -- WoW Forever has no targeted own-aura tracking (its Raid Buffs keep
        -- their own group watch).
        if not EABR.FOREVER then
            C_Timer.After(0.5, function()
                CacheInstanceInfo()
                EABR.ReevaluateOwnOtherAuraTracking()
            end)
        end
        EABR.ScanEatingState()
        if not InCombatLockdown() then EABR.SyncProviderCastSpell() end
        -- GetInstanceInfo() can return stale data on the first frame after a loading screen (e.g. still
        -- reporting the previous zone on delve entry), which would show a reminder that "Where to Show"
        -- disables for the new location. Skip the immediate refresh and wait for the corrected one.
        C_Timer.After(0.5, RequestRefresh)
        return
    end

    if e == "UNIT_AURA" then
        -- arg1 = unit token. Player aura changes always refresh; group member changes only matter for Evoker ownOnRaid cache updates and OOC raid buff checks (broad UNIT_AURA is only registered for classes needing group tracking).
        if arg1 == "player" then
            if not EABR.FOREVER then EABR.UpdateEatingState(arg2) end  -- eating channel feeds the retail food reminder only
            local isEvoker = GetPlayerClass() == "EVOKER"
            if isEvoker and InCombat() and IsInGroup() then
                for _, id in ipairs(_ownOnRaidIDs) do
                    if EABR._OwnCastOn("player", id) then
                        _preCombatOwnOnRaidCache[id] = true
                    end
                end
            end
            RequestRefresh()
        else
            -- Group member aura change (fast unit-type check via first byte). Broad UNIT_AURA stays registered in combat for Evoker ownOnRaid / provider-view coverage tracking; coalesces group events into one deferred refresh.
            if arg1 and (arg1:match("^party%d+$") or arg1:match("^raid%d+$")) then
                if EABR._trackOwnOtherAuraID then
                    EABR.UpdateOwnOtherAuraForUnit(arg1)
                end
                if _isEvokerOwnOnRaid and InCombat() and IsInGroup() then
                    for _, id in ipairs(_ownOnRaidIDs) do
                        if not _preCombatOwnOnRaidCache[id] and EABR._OwnCastOn(arg1, id) then
                            _preCombatOwnOnRaidCache[id] = true
                        end
                    end
                end
                -- The targeted tracker refreshes only when its own cached
                -- state changes. Do not rebuild the whole reminder list for
                -- unrelated group aura traffic when that tracker is the sole
                -- reason broad UNIT_AURA is registered.
                if EABR._needsGroupAuraRefresh and not _groupAuraDirty then
                    _groupAuraDirty = true
                    C_Timer.After(0.3, function()
                        _groupAuraDirty = false
                        RequestRefresh()
                    end)
                end
            end
        end
        return
    end

    if e == "UNIT_ENTERED_VEHICLE" or e == "UNIT_EXITED_VEHICLE" then
        if arg1 == "player" then RequestRefresh() end
        return
    end

    -- Roster changes do not touch player buffs/consumables; only the receiver
    -- view (class presence) and the own-cast group checks re-evaluate here.
    if e == "GROUP_ROSTER_UPDATE" then
        EABR.ReevaluateOwnOtherAuraTracking()
        local rbSW = db and db.profile.raidBuffs and db.profile.raidBuffs.showWhen
        if EABR._rosterRefresh or (rbSW and rbSW.iAmMissing == true) then RequestRefresh() end
        return
    end

    -- Bag CONTENT changes (BAG_UPDATE/_DELAYED) alter item counts/resolution, so re-scan. BAG_UPDATE_COOLDOWN
    -- is intentionally NOT registered: it fires ~1/sec from cooldown ticks, changes nothing reminder-relevant, and would refresh every second and bust the resolved-item cache.
    if e == "BAG_UPDATE_DELAYED" or e == "BAG_UPDATE" then
        InvalidateItemCountCache()
    end

    -- Equipped-weapon changes alter weapon-enchant resolution (weapon type -> which enchant item/slots show). Item counts are unchanged, so only the resolved cache needs rebuilding.
    if e == "UNIT_INVENTORY_CHANGED" then
        -- UNIT_INVENTORY_CHANGED also fires for temp enchants, procs, durability, etc.; only the WEAPON TYPE feeds resolution, so re-resolves only when the category changed (vs the last-resolved cat).
        local R = EABR._resolved
        if GetWeaponCategory(16) ~= R.we[16].cat or GetWeaponCategory(17) ~= R.we[17].cat then
            R.dirty = true
        end
    end

    -- Dismount: the pet comes back a moment AFTER the mount display drops, so the "Pet" reminder would flash in that gap. Grace-window it, and schedule the refresh that closes the window (nothing else fires when the pet is genuinely absent, which would latch the reminder off).
    if e == "PLAYER_MOUNT_DISPLAY_CHANGED" and not IsMounted() then
        EABR._petRemountGrace = GetTime() + 2
        C_Timer.After(2.1, RequestRefresh)
    end

    -- Talent/spec changes affect group aura tracking and form availability.
    if e == "PLAYER_TALENT_UPDATE" or e == "TRAIT_CONFIG_UPDATED"
       or e == "PLAYER_SPECIALIZATION_CHANGED" then
        EABR.ReevaluateOwnOtherAuraTracking()
    end

    -- WoW Forever (its only registration): a new rank joins the custom spells'
    -- rank families on the next pass (EABR.ForeverFamily).
    if e == "LEARNED_SPELL_IN_SKILL_LINE" then EABR._fvFamDirty = true end

    -- All other events: just refresh
    RequestRefresh()
end)

-- Item use tracking: _bagCounts (built by RebuildBagCounts, shared with the consumable item-count cache) is the
-- single source of truth for bag contents. On BAG_UPDATE_DELAYED, rebuilds ONCE and diffs against the previous snapshot to detect dropped (used) items -- no second bag walk.
local _prevBagCounts = {}

local function DetectUsedItem()
    if not db then return end
    RebuildBagCounts()
    for itemID, oldCount in pairs(_prevBagCounts) do
        if (_bagCounts[itemID] or 0) < oldCount then
            TrackItemUse(itemID)
        end
    end
    wipe(_prevBagCounts)
    for k, v in pairs(_bagCounts) do _prevBagCounts[k] = v end
end

-- Item-use tracking serves the consumable pickers; WoW Forever has no consumable reminders.
if not EABR.FOREVER then
    local f = CreateFrame("Frame")
    f:RegisterEvent("BAG_UPDATE_DELAYED")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(_, ev)
        if ev == "PLAYER_LOGIN" then
            C_Timer.After(1, function()
                RebuildBagCounts()
                wipe(_prevBagCounts)
                for k, v in pairs(_bagCounts) do _prevBagCounts[k] = v end
            end)
        elseif ev == "BAG_UPDATE_DELAYED" then
            DetectUsedItem()
        end
    end)
end

if EABR.FOREVER then
    -- WoW Forever: only what its sections need -- combat edges, zone changes,
    -- the player's own aura changes, vehicles, the death states, the rested
    -- state's edges and newly learned spells (a rank joins the custom spells'
    -- families, a raid buff becomes castable). Raid Buffs adds its group
    -- events itself (EABR.FvSyncGroupWatch).
    mainFrame:RegisterEvent("PLAYER_UPDATE_RESTING")
    mainFrame:RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE")
    mainFrame:RegisterEvent("ENCOUNTER_START")
    mainFrame:RegisterEvent("ENCOUNTER_END")
    mainFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    mainFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    mainFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    mainFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    mainFrame:RegisterUnitEvent("UNIT_AURA", "player")
    mainFrame:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
    mainFrame:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
    mainFrame:RegisterEvent("PLAYER_DEAD")
    mainFrame:RegisterEvent("PLAYER_ALIVE")
    mainFrame:RegisterEvent("PLAYER_UNGHOST")
else
mainFrame:RegisterEvent("ENCOUNTER_START")
mainFrame:RegisterEvent("ENCOUNTER_END")
mainFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
mainFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
mainFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
mainFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
mainFrame:RegisterEvent("SPELLS_CHANGED")
mainFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
mainFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
mainFrame:RegisterEvent("PLAYER_LEVEL_CHANGED")
mainFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
mainFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
mainFrame:RegisterUnitEvent("UNIT_AURA", "player")
mainFrame:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
mainFrame:RegisterEvent("CHALLENGE_MODE_START")
mainFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
mainFrame:RegisterEvent("CHALLENGE_MODE_RESET")
mainFrame:RegisterEvent("BAG_UPDATE_DELAYED")
mainFrame:RegisterEvent("WEAPON_ENCHANT_CHANGED")
mainFrame:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
mainFrame:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
mainFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
mainFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
mainFrame:RegisterEvent("PLAYER_DEAD")
mainFrame:RegisterEvent("PLAYER_ALIVE")
mainFrame:RegisterEvent("PLAYER_UNGHOST")
mainFrame:RegisterEvent("BAG_UPDATE")
mainFrame:RegisterUnitEvent("UNIT_PET", "player")
-- UNIT_PET fires on pet summon/dismiss, NOT stance changes. Pet on Passive reacts to the pet's command state via the pet action bar -- PET_BAR_UPDATE is that event; without it the reminder only re-evaluated on reload.
mainFrame:RegisterEvent("PET_BAR_UPDATE")
end

I.broken = false
