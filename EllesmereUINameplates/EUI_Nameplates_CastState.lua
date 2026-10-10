if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Nameplates_CastState.lua
--
--  Non-target opacity, the hover effect, the kick watcher, cast notifications
--  and the aura CVars.
--  Reads the earlier nameplate files through ns and ns._npInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._npInternals
-- EllesmereUINameplates.lua or an earlier nameplate file failed to load.
if not I or I.broken then return end
I.broken = true

local pairs, type = pairs, type
local UnitIsUnit, UnitCanAttack = UnitIsUnit, UnitCanAttack
local C_NamePlate = C_NamePlate
local NamePlateConstants, Enum = NamePlateConstants, Enum

local defaults, GetHealthBarWidth = I.defaults, I.GetHealthBarWidth
local ApplyOverlayGeometry, OverlayBgAlpha = I.ApplyOverlayGeometry, I.OverlayBgAlpha
local GetActiveKickSpell = I.GetActiveKickSpell

local p
I.profileSetters[#I.profileSetters + 1] = function(v) p = v end

-------------------------------------------------------------------------------
--  Non-Target Opacity: while the player has a target, every skinned plate that is not the
--  target, focus or player fades to nonTargetAlpha (0-100). 100 = OFF: every hook below
--  reduces to one numeric compare. Out-of-range alpha composes into the same root multiplier.
--  Alpha rides the plate ROOT (our own frame, parented to the Blizzard nameplate), so
--  Blizzard's own occlusion fade still multiplies in.
-------------------------------------------------------------------------------
ns._ntAlpha = 1   -- cached 0..1 from the profile; 1 = inert
ns._ntKeepFocus = true   -- cached "Keep Focus Full Opacity" (default on)
ns._oorAlpha = 1  -- cached out-of-range alpha; 1 = inert

-- Applies the correct root alpha to ONE plate. Value-guarded via _ntCurAlpha so redundant
-- SetAlpha calls are skipped and pooled frames reset cheaply (nil = never faded).
function ns.NT_Apply(plate)
    local unit = plate.unit
    if not unit then return end
    local a = 1
    local nt = ns._ntAlpha
    if nt < 1 and UnitExists("target")
       and not UnitIsUnit(unit, "target")
       and not (ns._ntKeepFocus and UnitIsUnit(unit, "focus"))
       and not UnitIsUnit(unit, "player") then
        a = nt
    end
    a = a * (plate._oorCurAlpha or 1)
    if (plate._ntCurAlpha or 1) ~= a then
        plate._ntCurAlpha = a
        plate:SetAlpha(a)
    end
end

function ns.NT_ApplyAll()
    for _, plate in pairs(ns.plates) do
        ns.NT_Apply(plate)
    end
end

-- Re-derives the cached opacity from the profile and reapplies every plate (un-fades at
-- slider=100). Called from the options slider, OnInitialize, and RefreshAllSettings.
function ns.NT_RefreshSetting()
    local v = tonumber(p and p.nonTargetAlpha) or 100
    if v < 0 then v = 0 elseif v > 100 then v = 100 end
    ns._ntAlpha = v / 100
    ns._ntKeepFocus = not (p and p.nonTargetKeepFocus == false)
    ns.NT_ApplyAll()
end

function ns.HideHoverEffect(plate)
    if not plate then return end
    if plate.highlight then plate.highlight:Hide() end
    if plate.hoverClipFill then plate.hoverClipFill:Hide() end
    if plate.hoverClipBg then plate.hoverClipBg:Hide() end
    plate._ovHoverShown = nil
end

function ns.ShowHoverEffect(plate)
    if not plate or not plate.health then return end
    -- Highlight channel gate (the Hover Effect dropdown's Highlight box): off
    -- = both the flat wash and the Hover Texture overlay stay hidden; the
    -- extra channels render independently via ns.ApplyHoverExtras.
    if not ns.GetHoverGlowHighlight() then
        ns.HideHoverEffect(plate)
        return
    end
    local db2 = p or defaults
    local hoverTex = db2.hoverOverlayTexture or defaults.hoverOverlayTexture
    local hc = db2.hoverColor or defaults.hoverColor
    local ha = db2.hoverAlpha or defaults.hoverAlpha
    if hoverTex ~= "none" then
        if ns._hoverOverlayTexName ~= hoverTex then
            ns._hoverOverlayTexName = hoverTex
            ns._hoverOverlayTexPath = ns.ResolveOverlayTexPath(hoverTex)
        end
        local texPath = ns._hoverOverlayTexPath
        local bgAlpha = OverlayBgAlpha(db2.hoverOverlayFullBgAlpha, ha)
        ns.EnsureHoverOverlay(plate)
        if not plate._ovHoverShown or plate._ovHoverTex ~= texPath
            or plate._ovHoverAlpha ~= ha or plate._ovHoverBgAlpha ~= bgAlpha
            or plate._ovHoverR ~= hc.r or plate._ovHoverG ~= hc.g or plate._ovHoverB ~= hc.b then
            plate._ovHoverShown = true
            plate._ovHoverTex, plate._ovHoverAlpha = texPath, ha
            plate._ovHoverBgAlpha = bgAlpha
            plate._ovHoverR, plate._ovHoverG, plate._ovHoverB = hc.r, hc.g, hc.b
            ApplyOverlayGeometry(plate.hoverOverlayFill, plate.hoverOverlayBg, plate.health, ns.OVERLAY_STRIPE_KEYS[hoverTex] == true)
            plate.hoverOverlayFill:SetTexture(texPath)
            plate.hoverOverlayFill:SetAlpha(ha)
            plate.hoverOverlayFill:SetVertexColor(hc.r, hc.g, hc.b)
            plate.hoverOverlayBg:SetTexture(texPath)
            plate.hoverOverlayBg:SetAlpha(bgAlpha)
            plate.hoverOverlayBg:SetVertexColor(hc.r, hc.g, hc.b)
        end
        if plate.highlight then plate.highlight:Hide() end
        plate.hoverClipFill:Show()
        plate.hoverClipBg:Show()
        return
    end
    if plate.hoverClipFill then plate.hoverClipFill:Hide() end
    if plate.hoverClipBg then plate.hoverClipBg:Hide() end
    plate._ovHoverShown = nil
    if plate.highlight then
        plate.highlight:SetColorTexture(hc.r, hc.g, hc.b, ha)
        plate.highlight:Show()
    end
end

-- Recolor the mouseover highlight on every live plate (enemy + friendly).
function ns.RefreshHoverEffect()
    local c = (p and p.hoverColor) or defaults.hoverColor
    local a = (p and p.hoverAlpha) or defaults.hoverAlpha
    for _, plate in pairs(ns.plates) do
        if plate.highlight then
            plate.highlight:SetColorTexture(c.r, c.g, c.b, a)
        end
        if plate == ns._currentMouseoverPlate then
            ns.ShowHoverEffect(plate)
            ns.ApplyHoverExtras(plate)
        else
            ns.HideHoverEffect(plate)
            ns.ClearHoverExtras(plate)
        end
    end
    for _, plate in pairs(ns.friendlyPlates or {}) do
        if plate.highlight then
            plate.highlight:SetColorTexture(c.r, c.g, c.b, a)
        end
        if plate == ns._currentMouseoverPlate then
            ns.ShowHoverEffect(plate)
            ns.ApplyHoverExtras(plate)
        else
            ns.HideHoverEffect(plate)
            ns.ClearHoverExtras(plate)
        end
    end
end

local kickWatcher = CreateFrame("Frame")
local activeCastCount = 0
-- PERF: set of plates currently casting, so kick/color updates iterate only the
-- 1-3 casting plates instead of all 20+ in the scene. On ns (200-local pressure).
ns._castingPlates = {}
kickWatcher:SetScript("OnEvent", function(self, event)
    if event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_USABLE" then
        -- No per-event cast-info re-reads or geometry: cast identity (protection/channel
        -- flags) is cached by UpdateKickTick at setup and by INTERRUPTIBLE handlers on
        -- mid-cast flips, so cooldown events only refresh marker value + alpha. A hidden tick
        -- means re-setup from cache (kick learned mid-cast, late CD info, toggle on).
        for plate in pairs(ns._castingPlates) do
            if plate.isCasting and plate.unit and type(plate._kickProtected) ~= "nil" then
                plate:ApplyCastColor(plate._kickProtected)
                if not plate.kickPositioner:IsShown() then
                    plate:UpdateKickTick(plate._kickProtected, plate._kickIsChannel, plate._kickIsEmpowered)
                else
                    plate:RefreshKickTick()
                end
            end
        end
    end
end)
local _castColorTicker
local function NotifyCastStarted(plate)
    if plate then
        ns._castingPlates[plate] = true
        -- Arm the 10Hz cast-timer ticker (engine-slept between fires; self-stops at cast end)
        -- and paint ONCE synchronously, or the ticker's first fire alone leaves text blank 0.1s.
        if plate.cast and plate.cast._timerTicker then
            if plate.cast._timerTick then plate.cast._timerTick(true) end
            plate.cast._timerTicker.Start()
        end
    end
    activeCastCount = activeCastCount + 1
    if activeCastCount == 1 then
        kickWatcher:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        kickWatcher:RegisterEvent("SPELL_UPDATE_USABLE")
        if GetActiveKickSpell() and not _castColorTicker then
            _castColorTicker = C_Timer.NewTicker(0.2, function()
                for pl in pairs(ns._castingPlates) do
                    -- type() is the safe existence check: _kickProtected holds a possibly-SECRET
                    -- boolean, and == nil would evaluate it
                    if pl.isCasting and pl.unit and type(pl._kickProtected) ~= "nil" then
                        pl:ApplyCastColor(pl._kickProtected)
                    end
                end
            end)
        end
    end
end
local function NotifyCastEnded(plate)
    if plate then ns._castingPlates[plate] = nil end
    activeCastCount = activeCastCount - 1
    if activeCastCount <= 0 then
        activeCastCount = 0
        wipe(ns._castingPlates)
        kickWatcher:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
        kickWatcher:UnregisterEvent("SPELL_UPDATE_USABLE")
        if _castColorTicker then
            _castColorTicker:Cancel()
            _castColorTicker = nil
        end
    end
end

-- PERF: cached target/focus plate refs, so a target/focus change updates only
-- the old + new plate instead of iterating all. On ns (200-local pressure).
ns._cachedTargetPlate = nil
ns._cachedFocusPlate  = nil

-- Value (1/0) of the class-colour CVar for the friendly player names Blizzard draws.
-- Name-only mode follows Class Colored Health Bar (its White / Class swatches). In
-- full-plate mode Blizzard draws only the protected instance plates, and Class
-- Colored Names turns it on as well so those names match ours.
function ns.FriendlyNameClassCVar(db)
    local on = db.classColorFriendly ~= false
        or (db.friendlyNameOnly == false and db.friendlyNameClassColor == true)
    return on and 1 or 0
end

local function SetupAuraCVars()
    if NamePlateConstants and Enum then
        local npcCVar = NamePlateConstants.ENEMY_NPC_AURA_DISPLAY_CVAR
        local npcEnum = Enum.NamePlateEnemyNpcAuraDisplay
        if npcCVar and npcEnum then
            if npcEnum.Debuffs then EllesmereUI.SetCVarBitfield(npcCVar, npcEnum.Debuffs, true, "EllesmereUINameplates") end
            if npcEnum.CrowdControl then EllesmereUI.SetCVarBitfield(npcCVar, npcEnum.CrowdControl, true, "EllesmereUINameplates") end
        end
        local plyCVar = NamePlateConstants.ENEMY_PLAYER_AURA_DISPLAY_CVAR
        local plyEnum = Enum.NamePlateEnemyPlayerAuraDisplay
        if plyCVar and plyEnum then
            if plyEnum.Debuffs then EllesmereUI.SetCVarBitfield(plyCVar, plyEnum.Debuffs, true, "EllesmereUINameplates") end
            if plyEnum.LossOfControl then EllesmereUI.SetCVarBitfield(plyCVar, plyEnum.LossOfControl, true, "EllesmereUINameplates") end
        end
    end
    do
        local db = p or defaults
        local nameOnly = (db.friendlyNameOnly ~= false)
        local showPlayers = (db.showFriendlyPlayers ~= false)
        local showNPCs = (db.showFriendlyNPCs == true)
        -- Friendly player CVars are written ONLY while EUI manages friendly player nameplates;
        -- with "Show EUI Friendly Player Nameplates" off we relinquish them entirely to
        -- Blizzard's own settings. Friendly NPC and enemy pet CVars are always managed.
        if showPlayers then
            EllesmereUI.SetCVar("nameplateShowOnlyNameForFriendlyPlayerUnits", nameOnly and 1 or 0, "EllesmereUINameplates")
            EllesmereUI.SetCVar("UnitNameFriendlyPlayerName", 1, "EllesmereUINameplates")
            -- Visibility is NOT re-asserted: nameplateShowFriends/nameplateShowFriendlyPlayers
            -- persist across sessions, so forcing them each login would re-show plates the user
            -- deliberately hid. The one-time seed below covers a first install only.
            if EllesmereUIDB and not EllesmereUIDB.friendlyPlateVisSeeded then
                EllesmereUIDB.friendlyPlateVisSeeded = true
                -- Fresh install only: an existing install is stamped WITHOUT forcing, so a
                -- user who already hid friendly plates keeps that.
                if EllesmereUI._firstInstallPending and ns.ForceFriendlyPlayerCVarsOn then
                    ns.ForceFriendlyPlayerCVarsOn()
                end
            end
        end
        EllesmereUI.SetCVar("nameplateShowFriendlyNPCs", showNPCs and 1 or 0, "EllesmereUINameplates")
        EllesmereUI.SetCVar("nameplateShowFriendlyNpcs", showNPCs and 1 or 0, "EllesmereUINameplates")
        EllesmereUI.SetCVar("nameplateShowEnemyPets", (db.showEnemyPets == true) and 1 or 0, "EllesmereUINameplates")
        if showPlayers then
            EllesmereUI.SetCVar("ShowClassColorInFriendlyNameplate", (db.classColorFriendly ~= false) and 1 or 0, "EllesmereUINameplates")
        end
        EllesmereUI.SetCVar("ShowClassColorInNameplate", 1, "EllesmereUINameplates")
        EllesmereUI.SetCVar("nameplateSize", 3, "EllesmereUINameplates")
        EllesmereUI.SetCVar("nameplateShowAll", 1, "EllesmereUINameplates")
        EllesmereUI.SetCVar("nameplateMinScale", 1, "EllesmereUINameplates")
        EllesmereUI.SetCVar("nameplateOverlapH", 1, "EllesmereUINameplates")
        -- nameplateOverlapV is deliberately left alone: it's the user's own vertical-spacing
        -- cvar (Blizzard default 1.10). Our "Stacked Nameplate Spacing" slider layers extra
        -- spacing on top via the stacking-bounds frame.
        EllesmereUI.SetCVar("nameplateMaxAlpha", 1, "EllesmereUINameplates")
        EllesmereUI.SetCVar("nameplateMaxAlphaDistance", 40, "EllesmereUINameplates")
        EllesmereUI.SetCVar("nameplateMinAlpha", 0.6, "EllesmereUINameplates")
        EllesmereUI.SetCVar("nameplateMinAlphaDistance", -100000, "EllesmereUINameplates")
        EllesmereUI.SetCVar("nameplateMaxDistance", 60, "EllesmereUINameplates")
        EllesmereUI.SetCVar("nameplateMaxScale", 1, "EllesmereUINameplates")
        -- Neutralize Blizzard's selected-target scaling: the EUI plate is a child of the base
        -- nameplate, so Blizzard's scaling shows through our own SetScale (min/max pinned to 1
        -- for the same reason). Pinned to 1, "Scale Target Nameplate" is the sole authority.
        EllesmereUI.SetCVar("nameplateSelectedScale", 1, "EllesmereUINameplates")
        EllesmereUI.SetCVar("nameplateTargetBehindMaxDistance", 30, "EllesmereUINameplates")
        EllesmereUI.SetCVar("clampTargetNameplateToScreen", 1, "EllesmereUINameplates")
        if showPlayers then
            EllesmereUI.SetCVar("nameplateUseClassColorForFriendlyPlayerUnitNames", ns.FriendlyNameClassCVar(db), "EllesmereUINameplates")
        end
    end
    -- Hide realm names on friendly nameplates inside instances
    if NamePlateFriendlyFrameOptions and TextureLoadingGroupMixin then
        if NamePlateFriendlyFrameOptions.updateNameUsesGetUnitName then
            local wrapper = { textures = NamePlateFriendlyFrameOptions }
            NamePlateFriendlyFrameOptions.updateNameUsesGetUnitName = 0
            TextureLoadingGroupMixin.RemoveTexture(wrapper, "updateNameUsesGetUnitName")
        end
    end
    -- Apply stacking state via the Midnight bitfield CVar.
    ns.RefreshStackingMotion()
    local function ApplyNamePlateClickArea()
        if InCombatLockdown() then return end
        local db = p or defaults
        local sx = (db.hitboxScaleX or 100) / 100
        if C_NamePlate and C_NamePlate.SetNamePlateSize then
            C_NamePlate.SetNamePlateSize(GetHealthBarWidth() * sx, ns.NP_HitboxHeight(db))
        end
        if C_NamePlateManager and C_NamePlateManager.SetNamePlateHitTestInsets and Enum and Enum.NamePlateType then
            C_NamePlateManager.SetNamePlateHitTestInsets(Enum.NamePlateType.Enemy, -10000, -10000, -10000, -10000)
            C_NamePlateManager.SetNamePlateHitTestInsets(Enum.NamePlateType.Friendly, -10000, -10000, -10000, -10000)
        end
    end
    ApplyNamePlateClickArea()
    -- Prevent Blizzard resetting nameplate sizes on display changes (jitter).
    if NamePlateDriverFrame then
        NamePlateDriverFrame:UnregisterEvent("DISPLAY_SIZE_CHANGED")
        NamePlateDriverFrame:UnregisterEvent("CVAR_UPDATE")
        hooksecurefunc(NamePlateDriverFrame, "UpdateNamePlateOptions", ApplyNamePlateClickArea)
        -- Suppress Blizzard class resource bar setup on our nameplates
        if NamePlateDriverFrame.SetupClassNameplateBars then
            hooksecurefunc(NamePlateDriverFrame, "SetupClassNameplateBars", function(self)
                if self.classNamePlatePowerBar then
                    self.classNamePlatePowerBar:Hide()
                    self.classNamePlatePowerBar:UnregisterAllEvents()
                end
                if self.classNamePlateMechanicFrame then
                    self.classNamePlateMechanicFrame:Hide()
                    self.classNamePlateMechanicFrame:UnregisterAllEvents()
                end
                if self.classNamePlateAlternatePowerBar then
                    self.classNamePlateAlternatePowerBar:Hide()
                    self.classNamePlateAlternatePowerBar:UnregisterAllEvents()
                end
            end)
        end
        -- Suppress the Blizzard UnitFrame before our NAME_PLATE_UNIT_ADDED fires
        -- so its initial layout pass never affects nameplate bounds. Any other
        -- unit gets back what an earlier enemy parked on this pooled UnitFrame.
        hooksecurefunc(NamePlateDriverFrame, "OnNamePlateAdded", function(_, addedUnit)
            if not addedUnit or addedUnit == "preview" then return end
            local np = C_NamePlate.GetNamePlateForUnit(addedUnit)
            if not np then return end
            if ns.NP_HideBehindCameraIcon then ns.NP_HideBehindCameraIcon(np.UnitFrame) end
            if UnitCanAttack("player", addedUnit) then
                ns.HideBlizzardFrame(np, addedUnit)
            else
                ns.NP_ReclaimBlizzardFrame(np.UnitFrame)
            end
        end)
    end
    ns.ApplyNamePlateClickArea = ApplyNamePlateClickArea
end

I.NotifyCastEnded, I.NotifyCastStarted = NotifyCastEnded, NotifyCastStarted
I.SetupAuraCVars = SetupAuraCVars
I.broken = false
