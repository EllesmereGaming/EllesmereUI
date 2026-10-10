if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Nameplates_Events.lua
--
--  The cast event dispatcher, the plate manager, the pending and enemy watchers
--  and the faction frame.
--  Reads the earlier nameplate files through ns and ns._npInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._npInternals
-- EllesmereUINameplates.lua or an earlier nameplate file failed to load.
if not I or I.broken then return end
I.broken = true

local pairs = pairs
local UnitIsUnit, UnitCanAttack = UnitIsUnit, UnitCanAttack
local C_NamePlate = C_NamePlate

local _npYOffsetState, defaults = I._npYOffsetState, I.defaults
local GetCastBarHeight, GetFocusCastHeight = I.GetCastBarHeight, I.GetFocusCastHeight
local frameCache, questMobCache = I.frameCache, I.questMobCache
local RefreshThreatCache, NameplateFrame = I.RefreshThreatCache, I.NameplateFrame

local p
I.profileSetters[#I.profileSetters + 1] = function(v) p = v end

-------------------------------------------------------------------------------
--  Centralized cast event dispatcher: registers all 13 SPELLCAST events ONCE globally instead
--  of 13 RegisterUnitEvent calls per plate, then looks up ns.plates[unit] (O(1) hash) and
--  dispatches to the plate's handler.
--  Cast-identity caching: the full UpdateCast path caches _kickProtected/_kickIsChannel/
--  _kickIsEmpowered on the plate, so the SPELL_UPDATE_COOLDOWN/USABLE watcher never re-reads
--  cast info per event (it re-pins the kick-tick value pair via RefreshKickTick). Cache
--  maintenance: INTERRUPTIBLE/NOT_INTERRUPTIBLE -> KickProtectionChanged re-reads and stores
--  protection, refreshes color+tick+overlay; DELAYED/CHANNEL_UPDATE/EMPOWER_UPDATE ->
--  _kickGeoDirty (next UpdateCast re-derives geometry from cached identity);
--  START/CHANNEL_START/EMPOWER_START -> _castDirtyFull = full setup; ClearUnit and mid-cast
--  token swaps (UpdateHealthValues) tear down and invalidate all cast caches.
-------------------------------------------------------------------------------
do
    local castDispatcher = CreateFrame("Frame")
    castDispatcher:RegisterEvent("UNIT_SPELLCAST_START")
    castDispatcher:RegisterEvent("UNIT_SPELLCAST_DELAYED")
    castDispatcher:RegisterEvent("UNIT_SPELLCAST_STOP")
    castDispatcher:RegisterEvent("UNIT_SPELLCAST_FAILED")
    castDispatcher:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
    castDispatcher:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
    castDispatcher:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")
    castDispatcher:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
    castDispatcher:RegisterEvent("UNIT_SPELLCAST_EMPOWER_START")
    castDispatcher:RegisterEvent("UNIT_SPELLCAST_EMPOWER_UPDATE")
    castDispatcher:RegisterEvent("UNIT_SPELLCAST_EMPOWER_STOP")
    castDispatcher:RegisterEvent("UNIT_SPELLCAST_INTERRUPTIBLE")
    castDispatcher:RegisterEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE")
    castDispatcher:SetScript("OnEvent", function(_, event, unit, ...)
        local plate = ns.plates[unit]
        if not plate then return end
        local handler = plate[event]
        if handler then handler(plate, unit, ...) end
    end)
    ns._castDispatcher = castDispatcher
end

local manager = CreateFrame("Frame")
manager:RegisterEvent("NAME_PLATE_UNIT_ADDED")
manager:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
manager:RegisterEvent("PLAYER_TARGET_CHANGED")
manager:RegisterEvent("PLAYER_FOCUS_CHANGED")
manager:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
manager:RegisterEvent("RAID_TARGET_UPDATE")
manager:RegisterEvent("PLAYER_REGEN_DISABLED")
manager:RegisterEvent("PLAYER_REGEN_ENABLED")
manager:RegisterEvent("DISPLAY_SIZE_CHANGED")
manager:RegisterEvent("UI_SCALE_CHANGED")

local pendingUnits = {}
ns.pendingUnits = pendingUnits
-- Mouseover-highlight state lives on ns (unified enemy+friendly monitor below).

-- Per-unit event watchers for pending friendly units: per-unit frames avoid the
-- global UNIT_FLAGS firehose.
local pendingWatchers = {}
-- Forward declarations so the two watcher creators can reference each other
local CreatePendingWatcher, CreateEnemyWatcher

-- Watches a friendly/pending unit for becoming attackable (e.g. duel start)
local enemyWatchers = {}
CreatePendingWatcher = function(unit, nameplate)
    local watcher = CreateFrame("Frame")
    watcher:RegisterUnitEvent("UNIT_FLAGS", unit)
    watcher:RegisterUnitEvent("UNIT_NAME_UPDATE", unit)
    watcher:SetScript("OnEvent", function(self, event, u)
        if not UnitCanAttack("player", u) then return end
        -- Unit became attackable promote to enemy plate
        self:UnregisterAllEvents()
        pendingWatchers[u] = nil
        pendingUnits[u] = nil
        local currentPlate = C_NamePlate.GetNamePlateForUnit(u)
        -- Name-only friendly NPCs are suppressed via a nameplate-keyed name
        -- overlay, not the friendlyPlates[] pool the calls below clean up.
        -- Tear it down here or the old friendly name text is left rendering
        -- on top of the new enemy plate/bar.
        if ns.RemoveFriendlyNPCOverlayForUnit then
            ns.RemoveFriendlyNPCOverlayForUnit(u, currentPlate)
        end
        -- Remove friendly plate WITHOUT restoring Blizzard UF (we'll suppress it as enemy)
        if ns.RemoveFriendlyPlateNoRestore then
            ns.RemoveFriendlyPlateNoRestore(u)
        elseif ns.RemoveFriendlyPlate then
            ns.RemoveFriendlyPlate(u)
        end
        if currentPlate then
            local plate = frameCache:Acquire()
            if not plate._mixedIn then
                Mixin(plate, NameplateFrame)
                plate._mixedIn = true
            end
            ns.plates[u] = plate
            plate:SetUnit(u, currentPlate)
        end
        -- Watch for the reverse transition (enemy friendly, e.g. duel end)
        enemyWatchers[u] = CreateEnemyWatcher(u)
    end)
    return watcher
end

-- Watches a promoted-enemy unit for becoming friendly again (e.g. duel end)
CreateEnemyWatcher = function(unit)
    local watcher = CreateFrame("Frame")
    watcher:RegisterUnitEvent("UNIT_FLAGS", unit)
    watcher:SetScript("OnEvent", function(self, event, u)
        if UnitCanAttack("player", u) then return end
        -- Unit became friendly again tear down enemy plate, restore to pending
        self:UnregisterAllEvents()
        enemyWatchers[u] = nil
        local plate = ns.plates[u]
        if plate then
            if ns._ClearMouseoverPlate then ns._ClearMouseoverPlate(plate) end
            -- Same cached-ref release as NAME_PLATE_UNIT_REMOVED.
            if ns._cachedTargetPlate == plate then ns._cachedTargetPlate = nil end
            if ns._cachedFocusPlate  == plate then ns._cachedFocusPlate  = nil end
            plate:ClearUnit()
            frameCache:Release(plate)
            ns.plates[u] = nil
        end
        -- Re-add as pending friendly
        local currentPlate = C_NamePlate.GetNamePlateForUnit(u)
        if currentPlate then
            pendingUnits[u] = currentPlate
            pendingWatchers[u] = CreatePendingWatcher(u, currentPlate)
            if ns.TryAddFriendlyPlate then ns.TryAddFriendlyPlate(u) end
        end
    end)
    return watcher
end

-- Single shared UNIT_FACTION handler avoids N watchers each registering the global event;
-- dispatches to the correct watcher's OnEvent handler. Only active in the open world.
local factionFrame = CreateFrame("Frame")
local factionFrameActive = false

local function UpdateFactionFrameForZone()
    local _, instanceType = IsInInstance()
    local shouldBeActive = (instanceType == "none" or instanceType == nil)
    if shouldBeActive and not factionFrameActive then
        factionFrame:RegisterEvent("UNIT_FACTION")
        factionFrameActive = true
    elseif not shouldBeActive and factionFrameActive then
        factionFrame:UnregisterEvent("UNIT_FACTION")
        factionFrameActive = false
    end
end

-- Options setter of Show Threat Colors: re-derive the flag and repaint every plate's
-- colors once (the zone / role path below without its quest-cache wipe).
function ns.NP_ApplyThreatColorMode()
    ns.NP_RefreshThreatColorFlag()
    for _, plate in pairs(ns.plates) do
        plate:UpdateHealthColor()
    end
end

local function RefreshThreatContextAndPlateColors()
    RefreshThreatCache()
    -- Unit tokens are recycled across zone/instance transitions; clear any
    -- stale quest-mob decisions that were made under a different context.
    wipe(questMobCache)
    wipe(ns._questObjText)
    for _, plate in pairs(ns.plates) do
        plate:UpdateHealthColor()
    end
end

factionFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
factionFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
factionFrame:RegisterEvent("PLAYER_DIFFICULTY_CHANGED")
factionFrame:RegisterEvent("ROLE_CHANGED_INFORM")
factionFrame:RegisterEvent("PLAYER_ROLES_ASSIGNED")
factionFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
-- The cached tank-role verdict is spec-derived for the player (effective
-- role), so the player's own spec swap must refresh it; the event also fires
-- for other units' spec updates, which change nothing here.
factionFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
factionFrame:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_SPECIALIZATION_CHANGED" then
        -- Never fall through: the dispatch below keys watchers by unit token,
        -- and this event's unit args are not faction-watcher units.
        if unit == "player" then RefreshThreatContextAndPlateColors() end
        return
    end
    if event == "PLAYER_ENTERING_WORLD"
    or event == "ZONE_CHANGED_NEW_AREA"
    or event == "PLAYER_DIFFICULTY_CHANGED"
    or event == "ROLE_CHANGED_INFORM"
    or event == "PLAYER_ROLES_ASSIGNED"
    or event == "GROUP_ROSTER_UPDATE" then
        RefreshThreatContextAndPlateColors()
        if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
            UpdateFactionFrameForZone()
        end
        if event == "PLAYER_ENTERING_WORLD" then
            -- Initial PEW can fire before difficulty/instance data settles.
            C_Timer.After(0.6, function()
                RefreshThreatContextAndPlateColors()
                UpdateFactionFrameForZone()
            end)
        end
        return
    end
    -- UNIT_FACTION dispatch
    if pendingWatchers[unit] then
        local w = pendingWatchers[unit]
        w:GetScript("OnEvent")(w, "UNIT_FACTION", unit)
    elseif enemyWatchers[unit] then
        local w = enemyWatchers[unit]
        w:GetScript("OnEvent")(w, "UNIT_FACTION", unit)
    end
    -- Tap state changes arrive here, not on any per-plate event. WoW
    -- Forever's level box follows too: whether a unit can be attacked picks
    -- its level's colour, and the player's own faction moves every one.
    local plate = ns.plates[unit]
    if plate then
        plate:UpdateHealthColor()
        if plate._fvLevelBox then ns.NP_UpdateForeverLevel(plate) end
    else
        -- A friendly full plate's faction badge: PvP flag and faction changes.
        local fp = ns.friendlyPlates[unit]
        if fp then
            ns.NP_FriendlyFactionRefresh(fp)
            if fp._fvLevelBox then ns.NP_UpdateForeverLevel(fp) end
        elseif unit == "player" and ns._npFvLevelArmed then
            ns.NP_ForeverSweepLevels()
        end
    end
end)
-- Unified mouseover monitor (enemy + friendly). UPDATE_MOUSEOVER_UNIT fires when a mouseover
-- STARTS but never when it clears, so a single shared 0.1s ticker (alive only while a mouseover
-- exists) watches for the mouse leaving. A held mouse button transiently drops the mouseover
-- unit, so in that case we wait for GLOBAL_MOUSE_UP (handled on `manager`) and re-check.
function ns._EnsureMouseoverTicker()
    if ns._mouseoverTicker then return end
    ns._mouseoverTicker = C_Timer.NewTicker(0.1, function()
        if not UnitExists("mouseover") then
            if ns._mouseoverTicker then ns._mouseoverTicker:Cancel(); ns._mouseoverTicker = nil end
            ns._UpdateMouseover()
            if IsMouseButtonDown() then manager:RegisterEvent("GLOBAL_MOUSE_UP") end
        end
    end)
end

-- Drop the highlight tracking if `plate` is the one currently highlighted.
-- Called from both enemy and friendly plate removal.
function ns._ClearMouseoverPlate(plate)
    if ns._currentMouseoverPlate == plate then
        ns._currentMouseoverPlate = nil
        if ns._mouseoverTicker then ns._mouseoverTicker:Cancel(); ns._mouseoverTicker = nil end
    end
    -- Pooled enemy frames recycle without re-running ApplyBorder, so a
    -- hover-sized border is restored here before its flag is dropped.
    if plate._hoverBorderSized then
        plate._hoverBorderSized = nil
        if plate.ApplyBorder then plate:ApplyBorder() end
    end
    plate._hoverFxOn = nil
end

function ns._UpdateMouseover()
    local cur = ns._currentMouseoverPlate
    if cur then
        ns.HideHoverEffect(cur)
        ns.ClearHoverExtras(cur)
        ns._currentMouseoverPlate = nil
    end
    if not UnitExists("mouseover") then return end
    local found
    for _, plate in pairs(ns.plates) do
        if plate.unit and UnitIsUnit(plate.unit, "mouseover") then found = plate; break end
    end
    if not found and ns.friendlyPlates then
        for _, plate in pairs(ns.friendlyPlates) do
            if plate.unit and UnitIsUnit(plate.unit, "mouseover") then found = plate; break end
        end
    end
    if found then
        ns.ShowHoverEffect(found)
        ns.ApplyHoverExtras(found)
        ns._currentMouseoverPlate = found
    end
    ns._EnsureMouseoverTicker()
end
-- Baseline lift for friendly plates, applied to BOTH distance settings: Name Distance
-- (name-only) and the friendly plate cog's Distance slider (full plate). Name-only needs it
-- because the friendly module collapses Blizzard's two-point name anchor onto the UnitFrame
-- centre (so long names stop truncating and the guild line has room), landing the name this
-- far below Blizzard's own anchor; the full plate carries the same lift so switching modes
-- does not jump. On ns (local cap).
ns.FRIENDLY_Y_BASE = 26

-- Refresh Y-offset on all visible friendly name-only plates
function ns.RefreshFriendlyNameOnlyOffset()
    local db = p or defaults
    local nameOnly = (db.friendlyNameOnly ~= false)
    local yOff = nameOnly and ((db.friendlyNameOnlyYOffset or 0) + ns.FRIENDLY_Y_BASE) or 0
    for unit, nameplate in pairs(pendingUnits) do
        if nameplate.UnitFrame then
            local uf = nameplate.UnitFrame
            if yOff ~= 0 then
                uf:SetPoint("TOPLEFT", nameplate, "TOPLEFT", 0, yOff)
                uf:SetPoint("BOTTOMRIGHT", nameplate, "BOTTOMRIGHT", 0, yOff)
                _npYOffsetState[nameplate] = true
            elseif _npYOffsetState[nameplate] then
                uf:SetPoint("TOPLEFT", nameplate, "TOPLEFT", 0, 0)
                uf:SetPoint("BOTTOMRIGHT", nameplate, "BOTTOMRIGHT", 0, 0)
                _npYOffsetState[nameplate] = nil
            end
        end
    end
end

manager:SetScript("OnEvent", function(self, event, unit)
    if event == "NAME_PLATE_UNIT_ADDED" then
        local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
        if not nameplate then return end
        if not UnitCanAttack("player", unit) then
            pendingUnits[unit] = nameplate
            pendingWatchers[unit] = CreatePendingWatcher(unit, nameplate)
            if ns.TryAddFriendlyPlate then ns.TryAddFriendlyPlate(unit) end
            -- Color NPC names green in name-only mode
            if ns.TryColorFriendlyNPCName then ns.TryColorFriendlyNPCName(unit, nameplate) end
            -- Hide NPC health bars in name-only mode (show name only)
            if ns.TrySuppressNPCHealthBar then ns.TrySuppressNPCHealthBar(unit, nameplate) end
            -- Ensure the Blizzard UF is visible for name-only friendly plates. UnitFrames are
            -- pooled; children an earlier enemy parked already came back in the
            -- OnNamePlateAdded hook (ns.NP_ReclaimBlizzardFrame).
            local db = p or defaults
            if db.friendlyNameOnly ~= false then
                local uf = nameplate.UnitFrame
                if uf then
                    -- Restore alpha in case the recycled UF was suppressed
                    if uf:GetAlpha() < 0.01 then
                        uf:SetAlpha(1)
                    end
                    -- Restore name FontString if it was moved offscreen
                    if uf.name and uf.name:GetParent() ~= uf then
                        uf.name:SetParent(uf)
                    end
                    -- Ensure UF is parented to the nameplate (not hidden frame)
                    if uf:GetParent() ~= nameplate then
                        uf:SetParent(nameplate)
                        uf:SetAlpha(1)
                        uf:Show()
                    end
                end
                -- Apply Y-offset (+ the name-only baseline lift; see
                -- ns.FRIENDLY_Y_BASE)
                local yOff = (db.friendlyNameOnlyYOffset or 0) + ns.FRIENDLY_Y_BASE
                if yOff ~= 0 and nameplate.UnitFrame then
                    nameplate.UnitFrame:SetPoint("TOPLEFT", nameplate, "TOPLEFT", 0, yOff)
                    nameplate.UnitFrame:SetPoint("BOTTOMRIGHT", nameplate, "BOTTOMRIGHT", 0, yOff)
                    _npYOffsetState[nameplate] = true
                end
                -- Font is applied globally via SystemFont_NamePlate override
            end
            return
        end
        pendingUnits[unit] = nil
        local plate = frameCache:Acquire()
        if not plate._mixedIn then
            Mixin(plate, NameplateFrame)
            plate._mixedIn = true
        end
        ns.plates[unit] = plate
        plate:SetUnit(unit, nameplate)
        -- If this plate is the current target, update the cached ref so class power pips
        -- track it immediately: no PLAYER_TARGET_CHANGED fires on recycle for the same target.
        if UnitIsUnit(unit, "target") then
            ns._cachedTargetPlate = plate
        end
        if UnitIsUnit(unit, "focus") then
            ns._cachedFocusPlate = plate
        end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        questMobCache[unit] = nil
        ns._questObjText[unit] = nil
        -- The driver has already released this base's UnitFrame (base.UnitFrame is nil
        -- here); its parked pieces come back on the next acquire (ns.NP_ReclaimBlizzardFrame).
        local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
        -- Restore NPC name color if we tinted it
        if nameplate and ns.RestoreFriendlyNPCNameColor then
            ns.RestoreFriendlyNPCNameColor(nameplate)
        end
        -- Restore NPC health bar if we suppressed it
        if nameplate and ns.RestoreNPCHealthBar then
            ns.RestoreNPCHealthBar(nameplate)
        end
        -- Drop the name-only Y-offset flag only: the pool release clears the UnitFrame's
        -- anchors and the next acquire re-anchors it (SetAllPoints).
        if nameplate then
            _npYOffsetState[nameplate] = nil
        end
        pendingUnits[unit] = nil
        if pendingWatchers[unit] then
            pendingWatchers[unit]:UnregisterAllEvents()
            pendingWatchers[unit] = nil
        end
        if enemyWatchers[unit] then
            enemyWatchers[unit]:UnregisterAllEvents()
            enemyWatchers[unit] = nil
        end
        local plate = ns.plates[unit]
        if plate then
            if ns._ClearMouseoverPlate then ns._ClearMouseoverPlate(plate) end
            -- Clear cached refs before release
            if ns._cachedTargetPlate == plate then ns._cachedTargetPlate = nil end
            if ns._cachedFocusPlate  == plate then ns._cachedFocusPlate  = nil end
            plate:ClearUnit()
            frameCache:Release(plate)
            ns.plates[unit] = nil
        end
        if ns.RemoveFriendlyPlate then ns.RemoveFriendlyPlate(unit) end
    elseif event == "PLAYER_TARGET_CHANGED" then
        -- PERF: only update old + new target plates instead of iterating all
        local oldTarget = ns._cachedTargetPlate
        ns._cachedTargetPlate = nil
        -- Find new target plate
        for _, plate in pairs(ns.plates) do
            if plate.unit and UnitIsUnit(plate.unit, "target") then
                ns._cachedTargetPlate = plate
                break
            end
        end
        if oldTarget and oldTarget.unit then
            oldTarget:ApplyTarget()
            oldTarget:UpdateHealthColor()
        end
        if ns._cachedTargetPlate and ns._cachedTargetPlate ~= oldTarget then
            ns._cachedTargetPlate:ApplyTarget()
            ns._cachedTargetPlate:UpdateHealthColor()
        end
        -- Non-Target Opacity: gaining/losing a target flips every plate's fade state, so this
        -- is the one full-iteration site. Zero cost while off (single compare).
        if ns._ntAlpha < 1 then ns.NT_ApplyAll() end
    elseif event == "PLAYER_FOCUS_CHANGED" then
        -- PERF: only update old + new focus plates instead of iterating all
        local oldFocus = ns._cachedFocusPlate
        ns._cachedFocusPlate = nil
        local focusPct = GetFocusCastHeight()
        -- Find new focus plate
        for _, plate in pairs(ns.plates) do
            if plate.unit and UnitIsUnit(plate.unit, "focus") then
                ns._cachedFocusPlate = plate
                break
            end
        end
        local function UpdateFocusPlate(plate)
            if not plate or not plate.unit then return end
            plate:UpdateHealthColor()
            -- Blizzard Style: the focus ring follows the focus, not just the target.
            if ns.NP_Style() == "blizzard" then ns.NP_ApplyBlizzSelection(plate) end
            if focusPct ~= 100 then
                local castH = GetCastBarHeight()
                if UnitIsUnit(plate.unit, "focus") then
                    castH = math.floor(castH * focusPct / 100 + 0.5)
                end
                ns.LayoutCastBar(plate, ns.GetHealthBarWidth(), castH)
                ns.LayoutCastIcon(plate, castH)
                ns.NP_SetSparkHeight(plate, castH)
                plate.kickMarker:SetHeight(castH)
            end
        end
        UpdateFocusPlate(oldFocus)
        if ns._cachedFocusPlate and ns._cachedFocusPlate ~= oldFocus then
            UpdateFocusPlate(ns._cachedFocusPlate)
        end
        -- Non-Target Opacity: only the old and new focus plates change
        -- fade state on a focus swap.
        if ns._ntAlpha < 1 then
            if oldFocus then ns.NT_Apply(oldFocus) end
            if ns._cachedFocusPlate and ns._cachedFocusPlate ~= oldFocus then
                ns.NT_Apply(ns._cachedFocusPlate)
            end
        end
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        ns._UpdateMouseover()
    elseif event == "GLOBAL_MOUSE_UP" then
        self:UnregisterEvent("GLOBAL_MOUSE_UP")
        ns._UpdateMouseover()
    elseif event == "RAID_TARGET_UPDATE" then
        for _, plate in pairs(ns.plates) do
            plate:UpdateRaidIcon()
            if p and p.nameRaidMarkerEnabled == true then plate:RefreshNamePosition(true) end
            -- A marker appearing/clearing in a side slot changes the side extents the target
            -- arrows sit outside of, so re-run arrow positioning (no-op without arrows), then
            -- reanchor the container-bearing sides -- same order as the target-swap path.
            ns.PositionArrowsOutsideAuras(plate)
            if ns.NPC_ReanchorArrows then ns.NPC_ReanchorArrows(plate) end
        end
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        for _, plate in pairs(ns.plates) do
            plate:UpdateHealthColor()
        end
    elseif event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then
        if ns.ApplyNamePlateClickArea then
            ns.ApplyNamePlateClickArea()
        end
    end
end)

I.broken = false
