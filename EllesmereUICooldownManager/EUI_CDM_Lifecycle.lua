if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_CDM_Lifecycle.lua
--
--  Unlock Mode registration and the addon object: OnInitialize, OnEnable,
--  first login and CDMFinishSetup.
--  Reads the earlier CDM files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- The main file or an earlier CDM file failed to load.
if not I or I.broken then return end
I.broken = true

local GetTime = GetTime

local DEFAULTS, ECME, RACE_RACIALS = I.DEFAULTS, I.ECME, I.RACE_RACIALS
local ResolveActiveRacial, _myRacials = I.ResolveActiveRacial, I._myRacials
local _myRacialsSet, ComputeLiveSpecKey = I._myRacialsSet, I.ComputeLiveSpecKey
local EnsureMappings, GetStore = I.EnsureMappings, I.GetStore
local SaveCurrentSpecProfile = I.SaveCurrentSpecProfile
local InstallProcGlowHooks, barDataByKey = I.InstallProcGlowHooks, I.barDataByKey
local cdmBarFrames, cdmBarIcons = I.cdmBarFrames, I.cdmBarIcons
local ApplyBarPositionCentered = I.ApplyBarPositionCentered
local ComputeTopRowStride, GetStableCDMBarSize = I.ComputeTopRowStride, I.GetStableCDMBarSize
local LayoutCDMBar, ReserveStride = I.LayoutCDMBar, I.ReserveStride
local FOCUSKICK_BAR_KEY, FOCUSKICK_SOUND_NAMES = I.FOCUSKICK_BAR_KEY, I.FOCUSKICK_SOUND_NAMES
local FOCUSKICK_SOUND_ORDER = I.FOCUSKICK_SOUND_ORDER
local FOCUSKICK_SOUND_PATHS, BuildAllCDMBars = I.FOCUSKICK_SOUND_PATHS, I.BuildAllCDMBars
local UpdateCDMKeybinds, _CDMApplyVisibility = I.UpdateCDMKeybinds, I._CDMApplyVisibility
local CDMFirstLoginCapture = I.CDMFirstLoginCapture
local GetCachedSpecKey, SetCdmInVehicle = I.GetCachedSpecKey, I.SetCdmInVehicle

local RegisterCDMUnlockElements
-- Vehicle/petbattle state proxy: created once in CDMFinishSetup; drives _CDMApplyVisibility so CDM bars hide while in vehicle UI.
local _cdmVehicleProxy = nil
-- Cached player info (set in ECME:OnEnable)
local _playerRace, _playerClass

-------------------------------------------------------------------------------
--  Register CDM bars with unlock mode
-------------------------------------------------------------------------------
RegisterCDMUnlockElements = function()
    if not EllesmereUI or not EllesmereUI.RegisterUnlockElements then return end
    local MK = EllesmereUI.MakeUnlockElement

    -- Build a lookup of which bars are anchored to which parent
    local anchorChildren = {}  -- parentKey -> { childKey1, childKey2, ... }
    for _, barData in ipairs(ECME.db.profile.cdmBars.bars) do
        local anchorKey = barData.anchorTo
        if anchorKey and anchorKey ~= "none" and anchorKey ~= "partyframe" and anchorKey ~= "playerframe" then
            if not anchorChildren[anchorKey] then anchorChildren[anchorKey] = {} end
            anchorChildren[anchorKey][#anchorChildren[anchorKey] + 1] = barData.key
        end
    end

    local elements = {}
    for _, barData in ipairs(ECME.db.profile.cdmBars.bars) do
        local key = barData.key
        local frame = cdmBarFrames[key]
        -- FocusKick is pinned to the focus nameplate, so it has no mover.
        if frame and barData.enabled and not barData.isGhostBar and key ~= FOCUSKICK_BAR_KEY then
            -- Skip bars anchored to party frame, player frame, or mouse cursor
            local isPartyAnchored = barData.anchorTo == "partyframe"
            local isPlayerFrameAnchored = barData.anchorTo == "playerframe"
            local isMouseAnchored = barData.anchorTo == "mouse"
            if not isPartyAnchored and not isPlayerFrameAnchored and not isMouseAnchored then
            local bd = barDataByKey[key]
            -- Additional Bar Offset: the unlock-anchored side folds through the
            -- shared _anchorExtraOffset registry (both ApplyAnchorPosition
            -- placement branches consume it). Registered for EVERY eligible bar
            -- and resolved LIVE: the value can change without this pass running
            -- (spec-override writes land raw in the bar table), so a
            -- register-only-while-nonzero getter went missing exactly when a
            -- spec's override turned the offset on. Zero reads as 0,0; it also
            -- returns 0 during unlock mode: movers show and save the BASE.
            local hasAddOffset = (barData.addOffsetX or 0) ~= 0 or (barData.addOffsetY or 0) ~= 0
            do
                local xoff = EllesmereUI._anchorExtraOffset
                if not xoff then
                    xoff = {}
                    EllesmereUI._anchorExtraOffset = xoff
                end
                xoff["CDM_" .. key] = function()
                    local bd3 = barDataByKey[key]
                    if not bd3 or EllesmereUI._unlockActive then return 0, 0 end
                    return bd3.addOffsetX or 0, bd3.addOffsetY or 0
                end
            end
            -- Collect linked unlock element keys (children anchored to this bar)
            local linked = nil
            if anchorChildren[key] then
                linked = {}
                for _, childKey in ipairs(anchorChildren[key]) do
                    linked[#linked + 1] = "CDM_" .. childKey
                end
            end

            -- Buff-type bars can't be anchor targets (their icon count changes dynamically with auras, causing cascading position shifts).
            local isBuff = ns.IsBarBuffFamily(barData)
            local isDynamic = isBuff or (barData.barType == "custom_buff")
            elements[#elements + 1] = MK({
                key = "CDM_" .. key,
                label = "CDM: " .. barData.name,
                group = "Cooldown Manager",
                order = 600,
                -- Additional Bar Offset marker: distinct warm mover tint +
                -- explanatory tooltip while an offset is set (nil otherwise --
                -- the mover renders exactly as before).
                moverBg = hasAddOffset and { r = 0.32, g = 0.19, b = 0.05 } or nil,
                -- Tooltip resolves live (nil = inert) so an override-written
                -- offset still explains itself even when the tint was
                -- registered without one.
                moverTooltip = function()
                    local bd3 = barDataByKey[key]
                    local ox = (bd3 and bd3.addOffsetX) or 0
                    local oy = (bd3 and bd3.addOffsetY) or 0
                    if ox == 0 and oy == 0 then return nil end
                    -- Stored in coordinate units; the options sliders show
                    -- physical pixels, so report the same unit here.
                    local toPx = EllesmereUI.PP.ToPixels
                    ox, oy = toPx(ox), toPx(oy)
                    return EllesmereUI.Lf(
                        "This bar has an Additional Bar Offset (X %1$s, Y %2$s) set in its options. Unlock mode shows the base position; the offset re-applies when you exit.",
                        ox, oy)
                end,
                linkedKeys = linked,
                noAnchorTarget = isDynamic,
                noResize = isDynamic,
                -- Outside reach of the bar's textured icon border for size matching
                -- (nil for dynamic bars, stock looks, custom shapes, solid borders).
                getMatchPad = function() return ns.CdmBarMatchPad(key) end,
                isHidden = function()
                    -- If this bar key is no longer in the current profile's barDataByKey, it is a stale registration from a previous profile and should not get a mover.
                    return not barDataByKey[key]
                end,
                getFrame = function() return cdmBarFrames[key] end,
                getSize = function()
                    local f = cdmBarFrames[key]
                    local bd2 = barDataByKey[key]
                    return GetStableCDMBarSize(key, f, bd2)
                end,
                linkedDimensions = true,
                setWidth = function(_, newW)
                    -- iconSize is derived live in LayoutCDMBar from the source bar's current width;
                    -- setWidth just triggers a re-layout. Nothing is persisted -- the source bar IS the truth. Wipe legacy cache fields so they can't poison anything.
                    local bd2 = barDataByKey[key]
                    if not bd2 then return end
                    bd2._matchPhysWidth = nil
                    bd2._matchPhysHeight = nil
                    bd2._matchIconPhys = nil
                    bd2._matchStride = nil
                    bd2._matchExtraPixels = nil
                    bd2._matchExtraPixelsH = nil
                    bd2._matchStrideH = nil
                    LayoutCDMBar(key)
                end,
                setHeight = function(_, newH)
                    -- See setWidth -- live-derive in LayoutCDMBar.
                    local bd2 = barDataByKey[key]
                    if not bd2 then return end
                    bd2._matchPhysWidth = nil
                    bd2._matchPhysHeight = nil
                    bd2._matchIconPhys = nil
                    bd2._matchStride = nil
                    bd2._matchExtraPixels = nil
                    bd2._matchExtraPixelsH = nil
                    bd2._matchStrideH = nil
                    LayoutCDMBar(key)
                end,
                savePos = function(_, point, relPoint, x, y)
                    local p = ECME.db.profile
                    local storePoint, storeX, storeY = point, x, y
                    local bd2 = barDataByKey[key]
                    local grow = bd2 and bd2.growDirection
                    local frame = cdmBarFrames[key]
                    -- Store at the growth edge (and, when "anchor first row" is on, the first-row
                    -- corner) so SetSize grows naturally from the fixed edge/corner with no
                    -- post-resize re-anchoring. Unlock mode always provides CENTER coords; convert
                    -- to the resolved anchor, skipping any axis with no extent yet (empty bar).
                    -- Snapped bars always store the plain growth edge: the anchor system's saved-edge consumers only understand single-edge points, so a corner would silently break edge preservation and target follow for them.
                    local isSnapped = EllesmereUI.IsUnlockAnchored
                        and EllesmereUI.IsUnlockAnchored("CDM_" .. key)
                    local resolved = ns.ResolveGrowAnchorPoint(bd2, isSnapped)
                    if resolved ~= "CENTER" and frame then
                        local fw = frame:GetWidth() or 0
                        local fh = frame:GetHeight() or 0
                        local needW = resolved:find("LEFT", 1, true) or resolved:find("RIGHT", 1, true)
                        local needH = resolved:find("TOP", 1, true) or resolved:find("BOTTOM", 1, true)
                        if (not needW or fw > 0) and (not needH or fh > 0) then
                            storePoint = resolved
                            storeX, storeY = ns.CenterToAnchorCoord(resolved, x, y, fw, fh)
                        end
                    end
                    -- Phase 2 follow baseline: capture the anchor target's center (UIParent space) at
                    -- save time so ApplyAnchorPosition can later shift the absolute saved edge by the
                    -- target's displacement. Only for growth bars; nil for unanchored/CENTER bars ->
                    -- follow stays off (pure absolute pin). require-re-save: existing bars pick this up only when next dragged + Save & Exit.
                    local tgtx, tgty
                    local tgtL, tgtR, tgtT, tgtB
                    if grow and grow ~= "CENTER" and EllesmereUI.GetAnchorTargetCenterUI then
                        tgtx, tgty = EllesmereUI.GetAnchorTargetCenterUI("CDM_" .. key)
                        -- Corner-follow baseline: the target's edges at save time, captured ONLY when
                        -- anchored to another CDM bar. Lets ApplyAnchorPosition hold a perpendicular (corner) bar against the target edge when the target's width/height changes. nil otherwise -> corner follow stays off.
                        if EllesmereUI.GetAnchorTargetEdgesUI then
                            tgtL, tgtR, tgtT, tgtB = EllesmereUI.GetAnchorTargetEdgesUI("CDM_" .. key)
                        end
                    end
                    p.cdmBarPositions[key] = { point = storePoint, relPoint = relPoint, x = storeX, y = storeY,
                        tgtx = tgtx, tgty = tgty, tgtL = tgtL, tgtR = tgtR, tgtT = tgtT, tgtB = tgtB }
                    -- Skip rebuild when called from anchor propagation or while unlock mode is active (unlock mode owns positioning then).
                    if not EllesmereUI._propagatingSave and not EllesmereUI._unlockActive then
                        BuildAllCDMBars()
                    end
                end,
                loadPos = function()
                    local pos = ECME.db.profile.cdmBarPositions[key]
                    if not pos or not pos.point then return pos end
                    -- Convert edge/corner-stored positions back to CENTER for the unlock mode system (it always works with CENTER coords).
                    local pt = pos.point
                    if pt ~= "CENTER" and pt ~= "" then
                        local frame = cdmBarFrames[key]
                        if frame then
                            local fw = frame:GetWidth() or 0
                            local fh = frame:GetHeight() or 0
                            local cx, cy = ns.AnchorCoordToCenter(pt, pos.x or 0, pos.y or 0, fw, fh)
                            return { point = "CENTER", relPoint = pos.relPoint, x = cx, y = cy }
                        end
                    end
                    return pos
                end,
                clearPos = function()
                    ECME.db.profile.cdmBarPositions[key] = nil
                end,
                applyPos = function()
                    -- While the authoritative reanchor pass is still pending (login window, or the
                    -- instant inside a spec-swap reconcile) the CDM pipeline owns layout and applies
                    -- saved positions itself; a rebuild here only races it against a still-churning engine pool. The flag is consumed deterministically by CollectAndReanchor.
                    if ns._pendingApplyOnReanchor then return end
                    -- Mid-transition guard: when the live spec key disagrees with the cached key, a
                    -- rebuild here can only construct the OLD spec's layout against the NEW spec's
                    -- already-repopulating engine pool (the pre-swap window before SPELLS_CHANGED lands). The talent_reconcile that follows is the only correct builder for that state.
                    local liveKey = ComputeLiveSpecKey()
                    if liveKey and liveKey ~= GetCachedSpecKey() then return end
                    -- Same-burst coalescing: position passes (ApplySavedPositions et al) call EVERY
                    -- CDM element's applyPosition back-to-back, and each call rebuilt ALL bars -- an
                    -- 11+ deep same-frame rebuild storm. The first call rebuilds synchronously (Save & Exit's sequencing depends on that); the rest of the burst no-ops until the next frame.
                    if ns._applyPosCoalesced then return end
                    ns._applyPosCoalesced = true
                    C_Timer.After(0, function() ns._applyPosCoalesced = nil end)
                    BuildAllCDMBars()
                end,
                isAnchored = function()
                    local bd2 = barDataByKey[key]
                    if not bd2 or not bd2.anchorTo then return false end
                    local a = bd2.anchorTo
                    -- Only valid anchor types: mouse, partyframe, playerframe, erb_*
                    if a == "mouse" or a == "partyframe" or a == "playerframe" then return true end
                    if a:sub(1, 4) == "erb_" then return true end
                    return false
                end,
            })
            end -- not isPartyAnchored
        end
    end

    if #elements > 0 then
        EllesmereUI:RegisterUnlockElements(elements, "EllesmereUICooldownManager")
    end
    -- Expose for ApplyAnchorPosition's growth-direction edge read. Width-independent: stores edge anchor directly (LEFT/RIGHT/TOP).
    EllesmereUI._cdmBarPositions = ECME.db.profile.cdmBarPositions
end

-- "Additional Bar Offset" unlock lifecycle: rides the shared shift-provider
-- list (EUI_UnlockMode.lua; direct or-preserve push, never an API call). dir
-- is inert -- anchored bars receive the offset through _anchorExtraOffset, not
-- the shift path. enter (unlock entry + combat resume, before positions are
-- snapshotted) re-builds so UN-anchored offset bars land at their true saved
-- positions (_unlockActive is already set, the offset helper returns 0);
-- restore (unlock exit) re-builds to re-apply the offset and re-runs the
-- anchors of unlock-anchored offset bars (the build deliberately leaves those
-- positions alone). Everything self-gates on a nonzero offset existing, so a
-- profile that never touches the setting schedules ZERO work. do-block: this
-- file is at the 200-local cap, nothing here may persist a file-scope local.
do
    local function AnyBarHasAddOffset()
        local p = ECME and ECME.db and ECME.db.profile
        local bars = p and p.cdmBars and p.cdmBars.bars
        if not bars then return false end
        for i = 1, #bars do
            local bd = bars[i]
            if bd.enabled and ((bd.addOffsetX or 0) ~= 0 or (bd.addOffsetY or 0) ~= 0) then
                return true
            end
        end
        return false
    end
    EllesmereUI._anchorShiftProviders = EllesmereUI._anchorShiftProviders or {}
    table.insert(EllesmereUI._anchorShiftProviders, {
        dir = function() return 0 end,
        wants = AnyBarHasAddOffset,
        enter = function()
            -- Reposition ONLY the offset bars, never a full rebuild: a rebuild
            -- re-applies saved positions to EVERY un-anchored bar, which would
            -- revert un-saved mover drags on the combat-resume path
            -- (audit-caught). _unlockActive is already true here, so the
            -- offset helper reads 0 and each bar lands at its BASE position
            -- for the snapshot. Unlock-ANCHORED offset bars are stripped by
            -- the wants-gated anchor reapply that follows; module-anchored
            -- bars have no movers and snapshot nothing.
            local p = ECME and ECME.db and ECME.db.profile
            local bars = p and p.cdmBars and p.cdmBars.bars
            if not bars then return end
            for i = 1, #bars do
                local bd = bars[i]
                if bd.enabled and ((bd.addOffsetX or 0) ~= 0 or (bd.addOffsetY or 0) ~= 0)
                    and (bd.anchorTo or "none") == "none"
                    and not (EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored("CDM_" .. bd.key)) then
                    local frame = cdmBarFrames[bd.key]
                    local pos = p.cdmBarPositions and p.cdmBarPositions[bd.key]
                    if frame and pos and pos.point then
                        ApplyBarPositionCentered(frame, pos, bd.key)
                    end
                end
            end
        end,
        restore = function()
            if not AnyBarHasAddOffset() then return end
            BuildAllCDMBars()
            if EllesmereUI.PropagateAnchorChain and EllesmereUI.IsUnlockAnchored then
                local p = ECME and ECME.db and ECME.db.profile
                local bars = p and p.cdmBars and p.cdmBars.bars
                if bars then
                    for i = 1, #bars do
                        local bd = bars[i]
                        if bd.enabled and ((bd.addOffsetX or 0) ~= 0 or (bd.addOffsetY or 0) ~= 0)
                            and EllesmereUI.IsUnlockAnchored("CDM_" .. bd.key) then
                            EllesmereUI.PropagateAnchorChain("CDM_" .. bd.key)
                        end
                    end
                end
            end
        end,
    })
end
ns.RegisterCDMUnlockElements = RegisterCDMUnlockElements
_G._ECME_RegisterUnlock = RegisterCDMUnlockElements

-- Positions-only re-apply for every enabled bar (no rebuild): un-anchored
-- bars from their saved position (Additional Bar Offset folded by
-- ApplyBarPositionCentered), unlock-anchored bars through the anchor chain
-- (offset folded by the _anchorExtraOffset getter). Module-anchored bars
-- (party/player/ERB) are placed inside BuildCDMBar and are left to the next
-- build. Used when a settings write lands but the follow-up rebuild is
-- deliberately suppressed (spec-override values written right after a spec
-- change), so the bar still moves to its new offset. On ns: 200-local cap.
ns.CDMReapplyBarPositions = function()
    local p = ECME and ECME.db and ECME.db.profile
    local bars = p and p.cdmBars and p.cdmBars.bars
    -- Never inside unlock mode: movers own positions there and a re-place
    -- from saved coords would revert un-saved drags.
    if not bars or InCombatLockdown() or EllesmereUI._unlockActive then return end
    for i = 1, #bars do
        local bd = bars[i]
        if bd.enabled and (bd.anchorTo or "none") == "none" then
            local ukey = "CDM_" .. bd.key
            if EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored(ukey) then
                if EllesmereUI.PropagateAnchorChain then EllesmereUI.PropagateAnchorChain(ukey) end
            else
                local frame = cdmBarFrames[bd.key]
                local pos = p.cdmBarPositions and p.cdmBarPositions[bd.key]
                if frame and pos and pos.point then
                    ApplyBarPositionCentered(frame, pos, bd.key)
                end
            end
        end
    end
end

-- RequestUpdate delegates to ns.RequestUpdate (defined in EllesmereUICdmBarGlows.lua). Falls back to no-op if bar glows module hasn't loaded yet.
local function RequestUpdate()
    if ns.RequestUpdate then ns.RequestUpdate() end
end


-------------------------------------------------------------------------------
--  Bootstrap / Addon Enable
--
--  `OnInitialize` runs once per addon load to create SavedVariables hooks and
--  expose options callbacks. `OnEnable` runs once per login/reload session to
--  load spec state, initialize helper modules, and choose between first-login
--  capture and the normal `CDMFinishSetup` path.
-------------------------------------------------------------------------------
function ECME:OnInitialize()
    self.db = EllesmereUI.Lite.NewDB("EllesmereUICooldownManagerDB", DEFAULTS, true)
    local settings = self.db.sv.cdmCommandSettings
    if not settings then
        settings = { blizzardCDMCommand = "/cd", blizzardCDMCommandEnabled = true }
        self.db.sv.cdmCommandSettings = settings
    end
    ns.RegisterBlizzardCDMCommand()

    -- Save spec profile before StripDefaults runs on logout
    EllesmereUI.Lite.RegisterPreLogout(function()
        local specKey = ns.GetActiveSpecKey()
        if specKey and specKey ~= "0" then
            SaveCurrentSpecProfile()
        end
    end)

    -- Check if we need first-login capture (per-install flag on SV root)
    self._needsCapture = not self.db.sv._capturedOnce_CDM

    -- Expose for options
    _G._ECME_AceDB = self.db
    -- First read of the glow gate: without it the cached value stays nil until
    -- the first PLAYER_ENTERING_WORLD and only works because nil is falsy.
    ns.RefreshGlowCombatGate()
    _G._ECME_Apply = function()
        ns.RefreshRotationAssistIcon()
        -- Profile switches land here, so the cached glow gate is re-read before
        -- the rebuild restarts any glow under the new profile's setting.
        ns.RefreshGlowCombatGate()
        if ns._skipNextApplyRebuild then
            ns._skipNextApplyRebuild = false
        elseif ns._specChangeJustRan then
            ns._specChangeJustRan = false
            -- The flag suppresses the profile system's follow-up rebuild right after a spec change
            -- -- but same-profile swaps never run that follow-up, leaving the flag armed until some LATER apply consumed it and silently skipped a rebuild the caller needed. Only honor the suppression while the spec change is recent.
            if not (ns._specChangeAt and (GetTime() - ns._specChangeAt) < 3) then
                ns.FullCDMRebuild("apply")
            elseif ns.CDMReapplyBarPositions then
                -- Suppressed rebuild: the caller may still have written bar
                -- settings (spec-override values land AFTER the reconcile), so
                -- re-place the bars from the now-current settings.
                ns.CDMReapplyBarPositions()
            end
        else
            ns.FullCDMRebuild("apply")
        end
        if ns.UpdateCustomBuffAuraTracking then ns.UpdateCustomBuffAuraTracking() end
        if ns.UpdateCustomBuffBars then ns.UpdateCustomBuffBars() end
        -- A profile that switches the gate off has to release the glows the old
        -- profile suppressed: the edge-driven ones (proc, cd ready) have no
        -- ticker to bring them back on their own.
        ns.CDMGlowCombatSync()
    end

    -- Append SharedMedia textures to TBB runtime tables
    if EllesmereUI.AppendSharedMediaTextures and ns.TBB_TEXTURE_NAMES then
        EllesmereUI.AppendSharedMediaTextures(
            ns.TBB_TEXTURE_NAMES,
            ns.TBB_TEXTURE_ORDER,
            nil,
            ns.TBB_TEXTURES
        )
    end
end

-- Tracks whether CDMFinishSetup has already run for this session. Set when the spec resolves and
-- we kick off the build, prevents double-init if multiple wakeup events fire (PLAYER_LOGIN + first PLAYER_SPECIALIZATION_CHANGED).
local _cdmSetupStarted = false

function ECME:OnEnable()
    -- Cache player race/class for trinket/racial/potion tracking
    _playerRace = select(2, UnitRace("player"))
    _playerClass = select(2, UnitClass("player"))
    ns._playerRace = _playerRace
    ns._playerClass = _playerClass
    ns._myRacialsSet = _myRacialsSet
    ns.RefreshLustPresetFaction()

    -- Build cached racial spell list for this character (used for render-time substitution)
    table.wipe(_myRacials)
    table.wipe(_myRacialsSet)
    local racialList = _playerRace and RACE_RACIALS[_playerRace]
    if racialList then
        for _, entry in ipairs(racialList) do
            local sid = type(entry) == "table" and entry[1] or entry
            local reqClass = type(entry) == "table" and entry.class or nil
            local excludeClass = type(entry) == "table" and entry.notClass or nil
            local classOk = (not reqClass or reqClass == _playerClass)
                and (not excludeClass or excludeClass ~= _playerClass)
            if classOk then
                _myRacials[#_myRacials + 1] = sid
                _myRacialsSet[sid] = true
            end
        end
    end

    -- Resolve the in-spellbook racial (the generic "Racial" picker slot maps to this ID). Re-resolved at build time too (spellbook may be empty here).
    ResolveActiveRacial()

    -- Blizzard overlays persisted hide/recategorize overrides onto its settings provider
    -- only after its own three-event wait completes (CooldownViewerSettings.lua OnLoad:
    -- VARIABLES_LOADED + PLAYER_ENTERING_WORLD + COOLDOWN_VIEWER_DATA_LOADED), registered
    -- at OnLoad -- far earlier than this deferred OnEnable (dispatched from a C_Timer past
    -- PLAYER_LOGIN, by which point VARIABLES_LOADED has already fired once and will not
    -- fire again this session). Re-registering that same wait here would silently never
    -- complete, so check the real downstream signal instead: the data provider only
    -- exposes a layoutManager once Blizzard's own Init has run. Reading merged categories
    -- before that finishes sees static defaults only and silently misses persisted
    -- hide/recategorize overrides.
    local function CheckCDMDataLoaded()
        if ns._cdmDataLoaded then return true end
        if not (CooldownViewerSettings and CooldownViewerSettings.GetDataProvider) then return false end
        local ok, provider = pcall(CooldownViewerSettings.GetDataProvider, CooldownViewerSettings)
        if not ok or not provider or not provider.GetLayoutManager then return false end
        local ok2, layoutManager = pcall(provider.GetLayoutManager, provider)
        if ok2 and layoutManager then
            ns._cdmDataLoaded = true
            return true
        end
        return false
    end

    if not CheckCDMDataLoaded() then
        local dataWakeFrame = ns.TakeShell()
        dataWakeFrame:RegisterEvent("COOLDOWN_VIEWER_DATA_LOADED")
        dataWakeFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        dataWakeFrame:SetScript("OnEvent", function(self)
            if CheckCDMDataLoaded() then
                self:UnregisterAllEvents()
                self:SetScript("OnEvent", nil)
                -- SetupViewerHooks' own 0.2/1/3/6s reanchor retries can all fire before
                -- Blizzard's data actually becomes ready on a slow login and never try
                -- again. Catch up now.
                if ns.QueueReanchor then ns.QueueReanchor() end
            end
        end)
    end

    -- NO spec-swap drop-pass guard lives here, deliberately (a PSC-edge
    -- unlatch was built and REMOVED same day): the destructive pass rode
    -- SPELLS_CHANGED, which can dispatch before PLAYER_SPECIALIZATION_CHANGED,
    -- and the latch probe only proves the layout manager EXISTS -- neither
    -- edge can prove the catalog serves the NEW spec. The fix is upstream:
    -- the swap-path rebuild tail requests no drop pass at all (see the
    -- reanchor tail in CdmHooks). Removal sync = settled-state triggers only.

    -- Enable CDM cooldown viewer (keep Blizzard CDM running in background so we can read its children even while hidden)
    pcall(EllesmereUI.SetCVar, "cooldownViewerEnabled", "1", "EllesmereUICooldownManager")

    -- Spec-gated build: only run CDMFinishSetup once a real spec key exists from the live API; if
    -- the API isn't ready, defer until it is. Wait until the truth is known, then build once -- never guess the spec and repair later.
    local function TryBuildCDM()
        if _cdmSetupStarted then return end
        if not ns.GetActiveSpecKey() then return end -- spec API not ready yet
        _cdmSetupStarted = true
        EnsureMappings(GetStore())
        if self._needsCapture then
            -- Capture Blizzard's Edit Mode layout once it has applied positions (at/after
            -- PLAYER_ENTERING_WORLD). OnEnable/TryBuildCDM run deferred past the login PEW (the
            -- Lite enable-flush dispatches OnEnable from a C_Timer past PLAYER_LOGIN -- Edit Mode
            -- taint fix -- and a spec-change wakeup can defer further), so on a fresh install the
            -- login PEW has already fired and a plain RegisterEvent would wait for the next zone
            -- change, leaving the tracker unbuilt all session. Keep the event as a backstop and, since we're already in-world with Edit Mode applied, capture now; the _needsCapture guard keeps both paths idempotent.
            self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnCDMFirstLogin")
            if IsLoggedIn() then
                C_Timer.After(0, function()
                    if self._needsCapture then self:OnCDMFirstLogin() end
                end)
            end
        else
            self:CDMFinishSetup()
        end
    end

    -- Try immediately. If the spec API is already populated (most reloads), this builds in-place and we're done.
    TryBuildCDM()

    -- If the immediate try didn't fire, wake up on the events that signal spec data is now
    -- available and try again. The handler is idempotent via _cdmSetupStarted so multiple wakeups are harmless.
    if not _cdmSetupStarted then
        local wakeFrame = ns.TakeShell()
        wakeFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        wakeFrame:RegisterEvent("PLAYER_LOGIN")
        wakeFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        wakeFrame:SetScript("OnEvent", function(self)
            ns.InvalidateSpecKey()
            TryBuildCDM()
            if _cdmSetupStarted then
                self:UnregisterAllEvents()
                self:SetScript("OnEvent", nil)
            end
        end)
    end

    -- Proc glow hooks: install immediately + retry. Hooks must be in place before Blizzard re-fires ShowAlert at PLAYER_LOGIN for active procs.
    InstallProcGlowHooks()
    C_Timer.After(0.5, InstallProcGlowHooks)

    -- Initialize Bar Glows overlay system
    if ns.InitBarGlows then ns.InitBarGlows() end

    ns.RefreshRotationAssistIcon()

end

function ECME:OnCDMFirstLogin()
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    -- A profile import can stamp the capture flag mid-session (imported data is a chosen layout).
    -- Honor the stamp here so a still-pending capture never overwrites the imported profile; just finish the deferred setup.
    if not self.db.sv._capturedOnce_CDM then
        CDMFirstLoginCapture()
    end
    self._needsCapture = false
    self:CDMFinishSetup()
end

-- Architecture: assignedSpells is pure user intent and is never mutated based on "is this spell
-- currently known". Talent/spec/reload events rebuild the cdID route map and reanchor -- the route
-- map is the source of truth for which Blizzard frame renders on which bar. Spells whose backing
-- frame is temporarily absent (pet dismissed, choice-node talent swapped away) simply don't render until the frame returns; their assigned slot is preserved.

function ECME:CDMFinishSetup()

    -- This is the one-time construction hub for a normal login/reload enable: preload unlock
    -- helpers, build the initial bar set, spin up the periodic tick frame, then schedule any
    -- deferred reconciliation/rebuild passes needed once Blizzard's viewer children and layout have
    -- settled. Run the unlock-core body early so anchor/propagation functions (ApplyAnchorPosition,
    -- PropagateWidthMatch, etc.) are available for the initial build pass -- NOT EnsureLoaded,
    -- which would pull the LoadOnDemand options addon into every login. CDM SavedVariables are ready by this point.
    EllesmereUI:EnsureUnlockCore()

    -- Pre-size CDM bar frames using cached icon counts from last session. Purely cosmetic: gives
    -- anchored elements correct dimensions to compute against before the real spell data populates. BuildAllCDMBars below overwrites everything with real data.
    do
        local p = ECME.db and ECME.db.profile
        if p and p.cdmBars and p.cdmBars.enabled and EllesmereUIDB then

            local charKey = ns.GetCharKey()
            local specKey = ns.GetActiveSpecKey()
            local cache = EllesmereUIDB.cdmCachedBarSizes
            local counts = cache and cache[charKey] and cache[charKey][specKey]
            if counts then
                for i, barData in ipairs(p.cdmBars.bars) do
                    if barData.enabled then
                        local cachedCount = counts[barData.key]
                        if cachedCount and cachedCount > 0 then
                            local key = barData.key
                            local frame = cdmBarFrames[key]
                            if not frame then
                                frame = CreateFrame("Frame", "ECME_CDMBar_" .. key, UIParent)
                                frame:SetFrameStrata(barData.barStrata or "MEDIUM")
                                frame:SetFrameLevel(5)
                                if frame.SetSnapToPixelGrid then frame:SetSnapToPixelGrid(false) end
                                if frame.SetTexelSnappingBias then frame:SetTexelSnappingBias(0) end
                                if frame.EnableMouseClicks then frame:EnableMouseClicks(false) end
                                -- Containers never capture mouse motion (see BuildCDMBar creation block).
                                if frame.EnableMouseMotion then frame:EnableMouseMotion(false) end
                                frame._barKey = key
                                frame._barIndex = i
                                cdmBarFrames[key] = frame
                                cdmBarIcons[key] = {}
                            end
                            -- Raw coord values -- see LayoutCDMBar for why we don't pre-snap with SnapForScale (PP.Scale truncation loses a pixel at UI scales with PP.mult > 1).
                            local iconW = barData.iconSize or 36
                            local iconH = iconW
                            if (barData.iconShape or "none") == "cropped" then
                                iconH = math.floor((barData.iconSize or 36) * ns.CdmCropFactor(barData) + 0.5)
                            end
                            local spacing = barData.spacing or 2
                            local grow = barData.growDirection or "CENTER"
                            -- Effective row count: collapses to 1 when a custom top-row split has no icons in its second row yet.
                            local stride, numRows = ComputeTopRowStride(barData, cachedCount)
                            if numRows < 1 then numRows = 1 end
                            -- Minimum Bar Size reserves extra growth-axis slots (no-op when unset); without it a bar under its minimum pre-sizes too small and visibly snaps once real data lands.
                            local resStride = ReserveStride(barData, stride)
                            local isHoriz = (grow == "RIGHT" or grow == "LEFT" or (grow == "CENTER" and not barData.verticalOrientation))
                            -- Compute total in integer phys px to avoid PP.Scale floor losing 1 px to floating-point dust on the multiply.
                            local PPpc = EllesmereUI and EllesmereUI.PP
                            local onePxPc = PPpc and PPpc.mult or 1
                            local iconWPx   = math.floor(iconW   / onePxPc + 0.5)
                            local iconHPx   = math.floor(iconH   / onePxPc + 0.5)
                            local spacingPx = math.floor(spacing / onePxPc + 0.5)
                            local totalWPx, totalHPx
                            if isHoriz then
                                totalWPx = resStride * iconWPx + (resStride - 1) * spacingPx
                                totalHPx = numRows   * iconHPx + (numRows   - 1) * spacingPx
                            else
                                totalWPx = numRows   * iconWPx + (numRows   - 1) * spacingPx
                                totalHPx = resStride * iconHPx + (resStride - 1) * spacingPx
                            end
                            local totalW = totalWPx * onePxPc
                            local totalH = totalHPx * onePxPc
                            frame:SetSize(totalW, totalH)
                            frame._prevLayoutW = totalW
                            frame._prevLayoutH = totalH
                            local pos = p.cdmBarPositions and p.cdmBarPositions[key]
                            if pos and pos.point then
                                frame:ClearAllPoints()
                                frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
                            end
                            frame:Show()
                        end
                    end
                end
            end
        end
    end

    -- (Migration moved to CollectAndReanchor: it must run after the viewer pools are populated, which only happens after the first successful reanchor.)

    ns.FullCDMRebuild("init")

    -- Initialize Tracking Bars GetTrackedBuffBars auto-initializes empty bars if none exist. No
    -- validation/removal: TBB bars can track any buff (procs, external buffs, food, etc.) not just
    -- CDM viewer spells. Bars with no active aura simply stay hidden at runtime. Nil-guarded so the TBB file can be bisect-disabled wholesale.
    if ns.GetTrackedBuffBars then ns.GetTrackedBuffBars() end

    -- (BuildTrackedBuffBars not called here -- FullCDMRebuild("init") above already called it.
    -- M1 cleanups also deleted: AddSpellToBar's variant-aware dedup prevents duplicate spell entries at insert time.)

    -- Hook Blizzard CDM viewer pools (route map already built by FullCDMRebuild)
    ns.SetupViewerHooks()

    -- FocusKick family (anchor proxy + plate watcher, reminder text, cast sound): demand-gated -- an EMPTY kick bar installs nothing at all.
    ns.RefreshFocusKickProxies()
    -- ...and again after every loading screen. Demand-gating makes arming a one-shot, so any pass
    -- that runs before the spell store resolves leaves the cast-sound proxy unbuilt until something
    -- unrelated rebuilds the bars (a spec change, or opening the options). That is the reported
    -- "sound stops working after I port" and it never recovers on its own. The refresh is cheap and idempotent: it early-returns when the bar is empty and re-registers the same events when it is not.
    do
        local fkRearm = CreateFrame("Frame")
        fkRearm:RegisterEvent("PLAYER_ENTERING_WORLD")
        fkRearm:SetScript("OnEvent", function()
            C_Timer.After(2, function()
                if ns.RefreshFocusKickProxies then ns.RefreshFocusKickProxies() end
            end)
        end)
    end
    -- SharedMedia sounds feed the options dropdowns; append regardless.
    EllesmereUI.AppendSharedMediaSounds(
        FOCUSKICK_SOUND_PATHS,
        FOCUSKICK_SOUND_NAMES,
        FOCUSKICK_SOUND_ORDER
    )

    -- One-time vehicle/petbattle proxy. Drives _CDMApplyVisibility on state change so CDM bars hide while the vehicle UI or pet battle UI is active.
    if not _cdmVehicleProxy then
        _cdmVehicleProxy = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
        _cdmVehicleProxy:SetAttribute("_onstate-cdmvehicle", [[
            self:CallMethod("OnVehicleStateChanged", newstate)
        ]])
        _cdmVehicleProxy.OnVehicleStateChanged = function(_, state)
            SetCdmInVehicle(state == "hide")
            _CDMApplyVisibility()
        end
        RegisterStateDriver(_cdmVehicleProxy, "cdmvehicle", "[vehicleui][petbattle] hide; show")
    end


    -- Edit mode close: no forced rebuild needed. The reanchor naturally skips inactive buff frames with hideWhenInactive (ghost frames from Edit Mode) and alpha-0s them as unclaimed. Normal hooks handle the rest.

    -- Register UNIT_AURA tracking if custom buff bars have spells
    if ns.UpdateCustomBuffAuraTracking then ns.UpdateCustomBuffAuraTracking() end

    -- Deferred keybind update: wait 3s so Blizzard's hotkey update cycle has fully run before we read HotKey text from button frames
    C_Timer.After(3, UpdateCDMKeybinds)

    -- (Tick frame removed -- all CDM updates are now event-driven via hooks. CollectAndReanchor runs only when Blizzard fires lifecycle hooks.)

    -- Register with unlock mode. Both default+custom CDM bars and TBB elements register synchronously here so anchor data is available before CollectAndReanchor runs.
    RegisterCDMUnlockElements()
    if ns.RegisterTBBUnlockElements then ns.RegisterTBBUnlockElements() end

    -- CDM is the authoritative trigger for the final layout pass when it is enabled. Set a flag so
    -- the next CollectAndReanchor that completes (after icons are populated and bar sizes are correct) will fire ApplyAllWidthHeightMatches + _applySavedPositions in the right order.
    --
    -- Why CDM owns this:
    --   1. CDM bars are the slowest thing to settle -- they depend on Blizzard CDM viewer pools being populated, which is async.
    --   2. ApplyAllWidthHeightMatches reads source bar widths and propagates them; if CDM bars are still being built when this runs, the sizes are transient/wrong.
    --   3. _applySavedPositions iterates registered elements and applies anchors; if CDM bars haven't registered yet (or their target ERB bars haven't), anchors silently drop and the bar lands at its CENTER/CENTER fallback (= screen center).
    ns._pendingApplyOnReanchor = true
end

I.RequestUpdate = RequestUpdate
I.broken = false
