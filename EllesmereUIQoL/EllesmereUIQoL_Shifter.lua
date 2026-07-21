-------------------------------------------------------------------------------
--  EllesmereUIQoL_Shifter.lua
--  Shift+drag to permanently reposition Blizzard panels.
--  Ctrl+drag for a temporary move that resets when the panel closes.
-------------------------------------------------------------------------------
local GetFFD = EllesmereUI._GetFFD

-- Temporary positions (per-frame, cleared on hide, not persisted)
local tempPos = {}

-- Temporary scales (per-frame, cleared on hide, not persisted)
local tempScale = {}

-- Every hooked frame, for the scroll-wheel overlay's mouseover targeting
local hookedFrames = {}

-- Frames that loaded during combat and need SetMovable/SetClampedToScreen deferred
local deferredMovable = {}

-- Forward-declare; created in the event-driven initialization section below
local eventFrame

-------------------------------------------------------------------------------
--  Frame registry
-------------------------------------------------------------------------------
local PRELOADED = {
    "CharacterFrame",
    "FriendsFrame",
    "PVEFrame",
    "DressUpFrame",
    "BankFrame",
    "MailFrame",
    "GossipFrame",
    "QuestFrame",
    "MerchantFrame",
    "AddonList",
    "ChatConfigFrame",
    "ItemTextFrame",
    "LFGDungeonReadyDialog",
    "GuildInviteFrame",
    "TabardFrame",
    "GuildRegistrarFrame",
}

local ADDON_FRAMES = {
    ["Blizzard_AchievementUI"]                     = { "AchievementFrame" },
    ["Blizzard_AlliedRacesUI"]                     = { "AlliedRacesFrame" },
    ["Blizzard_ArchaeologyUI"]                     = { "ArchaeologyFrame" },
    ["Blizzard_ArtifactUI"]                        = { "ArtifactFrame" },
    ["Blizzard_AuctionHouseUI"]                    = { "AuctionHouseFrame" },
    ["Blizzard_BlackMarketUI"]                     = { "BlackMarketFrame" },
    ["Blizzard_Calendar"]                          = { "CalendarFrame", "CalendarViewEventFrame" },
    ["Blizzard_ChallengesUI"]                      = { "ChallengesKeystoneFrame" },
    ["Blizzard_ChromieTimeUI"]                     = { "ChromieTimeFrame" },
    ["Blizzard_ClassTalentUI"]                     = { "ClassTalentFrame" },
    ["Blizzard_Collections"]                       = { "CollectionsJournal", "WardrobeFrame" },
    ["Blizzard_Communities"]                       = { "CommunitiesFrame" },
    ["Blizzard_CooldownViewer"]                    = { "CooldownViewerSettings" },
    ["Blizzard_EncounterJournal"]                  = { "EncounterJournal" },
    ["Blizzard_ExpansionLandingPage"]              = { "ExpansionLandingPage" },
    ["Blizzard_FlightMap"]                         = { "FlightMapFrame" },
    ["Blizzard_GenericTraitUI"]                    = { "GenericTraitFrame" },
    ["Blizzard_GuildBankUI"]                       = { "GuildBankFrame" },
    ["Blizzard_GuildControlUI"]                    = { "GuildControlUI" },
    ["Blizzard_InspectUI"]                         = { "InspectFrame" },
    ["Blizzard_ItemInteractionUI"]                 = { "ItemInteractionFrame" },
    ["Blizzard_ItemSocketingUI"]                   = { "ItemSocketingFrame" },
    ["Blizzard_ItemUpgradeUI"]                     = { "ItemUpgradeFrame" },
    ["Blizzard_MacroUI"]                           = { "MacroFrame" },
    ["Blizzard_MajorFactions"]                     = { "MajorFactionRenownFrame" },
    ["Blizzard_PlayerSpells"]                      = { "PlayerSpellsFrame" },
    ["Blizzard_Professions"]                       = { "ProfessionsFrame" },
    ["Blizzard_ProfessionsBook"]                   = { "ProfessionsBookFrame" },
    ["Blizzard_ProfessionsCustomerOrders"]         = { "ProfessionsCustomerOrdersFrame" },
    ["Blizzard_ScrappingMachineUI"]                = { "ScrappingMachineFrame" },
    ["Blizzard_StableUI"]                          = { "StableFrame" },
    ["Blizzard_TokenUI"]                           = { "CurrencyTransferMenu" },
    ["Blizzard_TrainerUI"]                         = { "ClassTrainerFrame" },
    ["Blizzard_TradeSkillUI"]                      = { "TradeSkillFrame" },
    ["Blizzard_Transmog"]                          = { "TransmogFrame" },
    ["Blizzard_WeeklyRewards"]                     = { "WeeklyRewardsFrame" },
    ["Blizzard_WorldMap"]                          = { "WorldMapFrame" },
    -- Midnight Housing
    ["Blizzard_HousingDashboard"]                  = { "HousingDashboardFrame" },
    ["Blizzard_HousingCornerstone"]                = { "HousingCornerstonePurchaseFrame" },
    ["Blizzard_HousingHouseFinder"]                = { "HouseFinderFrame" },
    ["Blizzard_HousingHouseSettings"]              = { "HousingHouseSettingsFrame" },
    ["Blizzard_HousingBulletinBoard"]              = { "HousingBulletinBoardFrame" },
    ["Blizzard_HousingModelPreview"]               = { "HousingModelPreviewFrame" },
    -- Delves
    ["Blizzard_DelvesCompanionConfigurationFrame"] = { "DelvesCompanionConfigurationFrame", "DelvesCompanionAbilityListFrame" },
    ["Blizzard_DelvesDifficultyPicker"]            = { "DelvesDifficultyPickerFrame" },
}

-- For these frames the drag target is a child header element, not the frame
-- itself (avoids fighting model-rotate or interior click regions).
local DRAG_HEADERS = {
    ["WorldMapFrame"] = "WorldMapTitleButton",
}

-- Extra drag handles layered ON TOP of the frame body. Used when a
-- mouse-enabled child sits over the frame and would otherwise swallow the
-- drag (e.g. the Achievement frame's floating points header). Values resolve
-- to a child frame: either a global name or a function(frame) -> child.
local EXTRA_DRAG_TARGETS = {
    ["AchievementFrame"] = function(frame) return frame.Header or _G["AchievementFrameHeader"] end,
}

-- Blizzard windows that normally dock beside CharacterFrame (Item Upgrade,
-- Transmog, Item Socketing, Merchant -- covers vendors like the Crest
-- Exchange -- plus Friends, Guild/Communities, and Professions, which
-- normally sit to CharacterFrame's left with CharacterFrame staying put).
-- See the docking hook in HookFrame for why and how.
--
-- PVEFrame is deliberately NOT here: EllesmereUIBlizzardSkin_GroupFinder.lua
-- owns that pairing instead, docking CharacterFrame beside PVEFrame (rather
-- than the reverse) with room-detection that also accounts for third-party
-- companion panels bolted onto PVEFrame (e.g. RaiderIO's Mythic+ panel).
-- Having both mechanisms active fought each other: this one's plain room
-- check has no idea RaiderIO's panel exists, so it could re-dock PVEFrame
-- right back on top of it the moment CharacterFrame got any saved/temp
-- Shifter position at all. PVEFrame being protected already skipped this
-- module's strata/Raise writes too (see the `else` branch below), so
-- dropping it here leaves it entirely to GroupFinder.lua, with nothing lost.
local DOCKING_COMPANIONS = {
    ItemUpgradeFrame = true,
    TransmogFrame = true,
    ItemSocketingFrame = true,
    MerchantFrame = true,
    FriendsFrame = true,
    CommunitiesFrame = true,
    ProfessionsFrame = true,
    ProfessionsBookFrame = true,
    WorldMapFrame = true,
    HousingDashboardFrame = true,
}

-------------------------------------------------------------------------------
--  Position helpers
-------------------------------------------------------------------------------
local function IsEnabled()
    return EllesmereUIDB and EllesmereUIDB.shifterEnabled or false
end

local function GetSavedPos(name)
    local db = EllesmereUIDB
    return db and db.shifterPositions and db.shifterPositions[name]
end

local function SavePos(name, point, relPoint, x, y)
    if not EllesmereUIDB then EllesmereUIDB = {} end
    if not EllesmereUIDB.shifterPositions then
        EllesmereUIDB.shifterPositions = {}
    end
    EllesmereUIDB.shifterPositions[name] = {
        point = point, relPoint = relPoint, x = x, y = y,
    }
    if EllesmereUI.RefreshPage then
        EllesmereUI:RefreshPage(true)
    end
end

local function GetSavedScale(name)
    local db = EllesmereUIDB
    return db and db.shifterScales and db.shifterScales[name]
end

local function SaveScale(name, scale)
    if not EllesmereUIDB then EllesmereUIDB = {} end
    if not EllesmereUIDB.shifterScales then
        EllesmereUIDB.shifterScales = {}
    end
    EllesmereUIDB.shifterScales[name] = scale
end

-------------------------------------------------------------------------------
--  Secure repositioning (for PROTECTED frames)
--
--  A plain frame:SetPoint() / StartMoving() / SetMovable() called from insecure
--  addon code TAINTS the frame's execution. That is invisible on most panels,
--  but PVEFrame parents the LFGList applicant viewer, which does secret-value
--  comparisons in 12.0 -- a tainted tree throws "attempt to compare a secret
--  number" there. So protected frames are NEVER touched with those calls; we
--  run ClearAllPoints/SetPoint inside a SecureHandler restricted-environment
--  snippet instead, which executes securely and never taints the frame.
--  Parented to UIParent so self:GetParent() inside the snippet IS UIParent.
-------------------------------------------------------------------------------
local securePositioner = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
local function SecureSetPoint(frame, point, relPoint, x, y)
    if InCombatLockdown() then return false end
    securePositioner:SetFrameRef("f", frame)
    securePositioner:SetAttribute("p", point)
    securePositioner:SetAttribute("rp", relPoint)
    securePositioner:SetAttribute("x", x)
    securePositioner:SetAttribute("y", y)
    securePositioner:Execute([[
        local f = self:GetFrameRef("f")
        if not f then return end
        f:ClearAllPoints()
        f:SetPoint(self:GetAttribute("p"), self:GetParent(), self:GetAttribute("rp"), self:GetAttribute("x"), self:GetAttribute("y"))
    ]])
    return true
end

local function ApplyPosition(frame, name)
    if InCombatLockdown() and frame:IsProtected() then return end
    local pos = tempPos[frame] or GetSavedPos(name)
    if not pos or not pos.point then return end
    local ffd = GetFFD(frame)
    ffd._shIgnoreSP = true
    if frame:IsProtected() then
        SecureSetPoint(frame, pos.point, pos.relPoint, pos.x, pos.y)
    else
        frame:ClearAllPoints()
        frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    end
    ffd._shIgnoreSP = false
end

-------------------------------------------------------------------------------
--  Scaling (Shift+Scroll = permanent, Ctrl+Scroll = temporary)
--
--  Same protection split as positioning: non-protected frames take a plain
--  SetScale, protected frames are scaled inside the SecureHandler snippet so
--  the write cannot taint by construction. Position offsets are stored in
--  frame-local units, so on a scale change the active offsets are multiplied
--  by oldScale/newScale and re-applied -- the frame stays visually put.
-------------------------------------------------------------------------------
local SCALE_MIN, SCALE_MAX, SCALE_STEP = 0.5, 2, 0.1

local function SecureSetScale(frame, scale)
    if InCombatLockdown() then return false end
    securePositioner:SetFrameRef("f", frame)
    securePositioner:SetAttribute("s", scale)
    securePositioner:Execute([[
        local f = self:GetFrameRef("f")
        if f then f:SetScale(self:GetAttribute("s")) end
    ]])
    return true
end

local function SetShifterScale(frame, scale)
    -- Guard the SetScale reentry hook (below) so our own re-scale never
    -- recurses -- mirrors the _shIgnoreSP guard used for SetPoint.
    local ffd = GetFFD(frame)
    ffd._shIgnoreSS = true
    local ok
    if frame:IsProtected() then
        ok = SecureSetScale(frame, scale)
    else
        frame:SetScale(scale)
        ok = true
    end
    ffd._shIgnoreSS = false
    return ok
end

-- OnShow / init restore: temp > saved > (original, if we scaled it earlier).
local function ApplyScale(frame, name)
    if InCombatLockdown() and frame:IsProtected() then return end
    local ffd = GetFFD(frame)
    local target = tempScale[frame] or GetSavedScale(name)
    if target then
        if ffd._shOrigScale == nil then ffd._shOrigScale = frame:GetScale() end
        ffd._shScaled = true
    else
        if not (ffd._shScaled and ffd._shOrigScale) then return end
        target = ffd._shOrigScale
        ffd._shScaled = nil
    end
    if math.abs(frame:GetScale() - target) < 0.001 then return end
    SetShifterScale(frame, target)
end

local function ApplyScaleStep(frame, name, delta, mode)
    if InCombatLockdown() and frame:IsProtected() then return end
    local ffd = GetFFD(frame)
    if ffd._shOrigScale == nil then ffd._shOrigScale = frame:GetScale() end
    local oldS = frame:GetScale()
    local cur = tempScale[frame] or GetSavedScale(name) or oldS
    local new = math.floor((cur + SCALE_STEP * delta) * 100 + 0.5) / 100
    if new < SCALE_MIN then new = SCALE_MIN elseif new > SCALE_MAX then new = SCALE_MAX end
    if new == cur and math.abs(oldS - new) < 0.005 then return end
    if not SetShifterScale(frame, new) then return end
    ffd._shScaled = true

    -- Keep the frame visually in place: rescale whichever position table is
    -- (or becomes) active, then re-apply it.
    local ratio = oldS / new
    -- With NO stored position, Blizzard's panel manager re-seats the scaled
    -- window on its next layout pass (first tab switch) and it visibly
    -- jumps. Zooming therefore claims the seat like dragging does: capture
    -- the current visual spot (center-based, frame-local units at the NEW
    -- scale) so the pin holds it.
    local function CaptureCenter()
        local fcx, fcy = frame:GetCenter()
        local ucx, ucy = UIParent:GetCenter()
        if not fcx or not ucx then return nil end
        local es = frame:GetEffectiveScale()
        local ues = UIParent:GetEffectiveScale()
        return (fcx * es - ucx * ues) / es, (fcy * es - ucy * ues) / es
    end
    if mode == "save" then
        SaveScale(name, new)
        tempScale[frame] = nil
        local saved = GetSavedPos(name)
        if saved then
            SavePos(name, saved.point, saved.relPoint, saved.x * ratio, saved.y * ratio)
        elseif not tempPos[frame] then
            local cx, cy = CaptureCenter()
            if cx then SavePos(name, "CENTER", "CENTER", cx, cy) end
        end
        if tempPos[frame] then
            tempPos[frame].x = tempPos[frame].x * ratio
            tempPos[frame].y = tempPos[frame].y * ratio
        end
    else
        tempScale[frame] = new
        if tempPos[frame] then
            tempPos[frame].x = tempPos[frame].x * ratio
            tempPos[frame].y = tempPos[frame].y * ratio
        else
            local saved = GetSavedPos(name)
            if saved then
                tempPos[frame] = {
                    point = saved.point, relPoint = saved.relPoint,
                    x = saved.x * ratio, y = saved.y * ratio,
                }
            else
                local cx, cy = CaptureCenter()
                if cx then
                    tempPos[frame] = {
                        point = "CENTER", relPoint = "CENTER", x = cx, y = cy,
                    }
                end
            end
        end
    end
    ApplyPosition(frame, name)
end

-------------------------------------------------------------------------------
--  Scroll-wheel capture overlay
--
--  No Blizzard frame ever gets EnableMouseWheel (input-state writes are the
--  exact call class that tainted PVEFrame). Instead one overlay frame of our
--  own sits over the hovered registered panel while Shift/Ctrl is held and
--  takes the wheel. EnableMouse stays false so clicks (and the existing
--  drag hooks) pass straight through; with no modifier held it is hidden and
--  costs nothing.
-------------------------------------------------------------------------------
local wheelTarget, wheelTargetName
local wheelOverlay = CreateFrame("Frame", nil, UIParent)
wheelOverlay:Hide()
wheelOverlay:EnableMouse(false)
wheelOverlay:EnableMouseWheel(true)
wheelOverlay:SetFrameStrata("TOOLTIP")

local function FindWheelTarget()
    for i = 1, #hookedFrames do
        local e = hookedFrames[i]
        if e.frame:IsVisible() and e.frame:IsMouseOver() then
            return e.frame, e.name
        end
    end
end

local function UpdateWheelOverlay()
    if not (IsEnabled() and (IsShiftKeyDown() or IsControlKeyDown())) then
        wheelTarget, wheelTargetName = nil, nil
        wheelOverlay:Hide()
        return
    end
    local f, name = FindWheelTarget()
    wheelTarget, wheelTargetName = f, name
    wheelOverlay:ClearAllPoints()
    if f then
        wheelOverlay:SetAllPoints(f)
        wheelOverlay:EnableMouseWheel(true)
    else
        -- Parked but shown: the OnUpdate keeps polling so hovering onto a
        -- panel AFTER pressing the modifier still arms the wheel.
        wheelOverlay:SetSize(1, 1)
        wheelOverlay:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -20, -20)
        wheelOverlay:EnableMouseWheel(false)
    end
    wheelOverlay:Show()
end

do
    local acc = 0
    wheelOverlay:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < 0.1 then return end
        acc = 0
        UpdateWheelOverlay()
    end)
end

wheelOverlay:SetScript("OnMouseWheel", function(_, delta)
    local frame, name = wheelTarget, wheelTargetName
    if not frame or not IsEnabled() then return end
    if IsShiftKeyDown() then
        ApplyScaleStep(frame, name, delta, "save")
    elseif IsControlKeyDown() then
        ApplyScaleStep(frame, name, delta, "temp")
    end
end)

-------------------------------------------------------------------------------
--  Cursor-delta drag (for PROTECTED frames)
--
--  We can't StartMoving a protected frame without tainting it, so for those we
--  track the cursor ourselves and reposition the frame live via SecureSetPoint
--  each update. Position is stored center-relative to UIParent (scale-clean).
--  Only one protected frame can be dragged at a time.
-------------------------------------------------------------------------------
local secureDrag = {}  -- { frame, name, mode, cursorX, cursorY, startX, startY, curX, curY }
local secureDragUpdater = CreateFrame("Frame")
secureDragUpdater:Hide()

local function StopSecureDrag()
    secureDragUpdater:Hide()
    local frame = secureDrag.frame
    if not frame then return end
    if secureDrag.curX then
        if secureDrag.mode == "save" then
            SavePos(secureDrag.name, "CENTER", "CENTER", secureDrag.curX, secureDrag.curY)
            tempPos[frame] = nil
        else
            tempPos[frame] = { point = "CENTER", relPoint = "CENTER", x = secureDrag.curX, y = secureDrag.curY }
        end
    end
    secureDrag.frame = nil
end

secureDragUpdater:SetScript("OnUpdate", function()
    local frame = secureDrag.frame
    if not frame then secureDragUpdater:Hide(); return end
    if InCombatLockdown() then StopSecureDrag(); return end
    local cx, cy = GetCursorPosition()
    local es = frame:GetEffectiveScale()
    local ues = UIParent:GetEffectiveScale()
    local ucx, ucy = UIParent:GetCenter()
    local newScreenX = secureDrag.startX + (cx - secureDrag.cursorX)
    local newScreenY = secureDrag.startY + (cy - secureDrag.cursorY)
    -- Keep the frame's center on screen (protected frames skip SetClampedToScreen).
    local sw, sh = GetScreenWidth() * ues, GetScreenHeight() * ues
    if newScreenX < 0 then newScreenX = 0 elseif newScreenX > sw then newScreenX = sw end
    if newScreenY < 0 then newScreenY = 0 elseif newScreenY > sh then newScreenY = sh end
    local x = (newScreenX - ucx * ues) / es
    local y = (newScreenY - ucy * ues) / es
    secureDrag.curX, secureDrag.curY = x, y
    local ffd = GetFFD(frame)
    ffd._shIgnoreSP = true
    SecureSetPoint(frame, "CENTER", "CENTER", x, y)
    ffd._shIgnoreSP = false
end)

local function StartSecureDrag(frame, name, mode)
    local fcx, fcy = frame:GetCenter()
    if not fcx then return end
    local es = frame:GetEffectiveScale()
    secureDrag.frame = frame
    secureDrag.name = name
    secureDrag.mode = mode
    secureDrag.cursorX, secureDrag.cursorY = GetCursorPosition()
    secureDrag.startX, secureDrag.startY = fcx * es, fcy * es
    secureDrag.curX, secureDrag.curY = nil, nil
    secureDragUpdater:Show()
end

-------------------------------------------------------------------------------
--  Companion re-dock on CharacterFrame changes.
--
--  Each DOCKING_COMPANIONS frame only re-evaluates its own docked position
--  when ITS OWN OnShow/SetPoint fires -- never when CharacterFrame itself
--  moves or rescales. So a companion (WorldMap, Guild/Communities, PVEFrame,
--  etc.) that's already open and correctly docked goes stale the moment
--  CharacterFrame is scaled or repositioned afterward, since nothing tells
--  it to re-check. Every companion registers its ShouldDock/DockToCharacter-
--  Frame closures here as it's hooked; CharacterFrame's own SetPoint/SetScale
--  (hooked separately below) walks this list and re-docks anything that
--  should currently be docked, closing that gap.
-------------------------------------------------------------------------------
local dockedCompanions = {}

local function RedockCompanions()
    for i = 1, #dockedCompanions do
        local c = dockedCompanions[i]
        if c.frame:IsShown() and c.shouldDock() then
            if not c.frame:IsProtected() then c.frame:SetFrameStrata("DIALOG") end
            c.dock()
            if not c.frame:IsProtected() then c.frame:Raise() end
        end
    end
end

-------------------------------------------------------------------------------
--  Hook a single frame
-------------------------------------------------------------------------------
local function HookFrame(frame, name)
    local ffd = GetFFD(frame)
    if ffd._shHooked then return end
    ffd._shHooked = true
    hookedFrames[#hookedFrames + 1] = { frame = frame, name = name }

    -- Non-protected frames use the cheap native StartMoving path. Protected
    -- frames are NEVER made movable / SetMovable'd / StartMoving'd / SetPoint'd
    -- by insecure code (it taints them); they drag via the secure cursor-delta
    -- path above. SetMovable is only needed for StartMoving, so protected frames
    -- skip it entirely.
    if not frame:IsProtected() then
        frame:SetMovable(true)
        frame:SetClampedToScreen(true)
    end

    local dragging  -- non-protected only: "save" | "temp" | nil

    local function AttachDrag(dragTarget)
        if not dragTarget or not dragTarget.HookScript then return end
        dragTarget:HookScript("OnMouseDown", function(_, button)
            if not IsEnabled() then return end
            if button ~= "LeftButton" then return end
            if InCombatLockdown() and frame:IsProtected() then return end
            local noShift = EllesmereUIDB and EllesmereUIDB.shifterNoShift
            local mode
            if IsShiftKeyDown() or noShift then
                mode = "save"
            elseif IsControlKeyDown() then
                mode = "temp"
            else
                return
            end
            if frame:IsProtected() then
                StartSecureDrag(frame, name, mode)
            else
                dragging = mode
                frame:StartMoving()
            end
        end)

        dragTarget:HookScript("OnMouseUp", function(_, button)
            if button ~= "LeftButton" then return end
            if frame:IsProtected() then
                if secureDrag.frame == frame then StopSecureDrag() end
                return
            end
            if not dragging then return end
            frame:StopMovingOrSizing()
            frame:SetUserPlaced(false)
            local p, _, rp, x, y = frame:GetPoint(1)
            if p then
                if dragging == "save" then
                    SavePos(name, p, rp, x, y)
                    tempPos[frame] = nil
                else
                    tempPos[frame] = {
                        point = p, relPoint = rp, x = x, y = y,
                    }
                end
            end
            dragging = nil
        end)
    end

    -- Primary drag target (header child or the frame itself)
    local headerName = DRAG_HEADERS[name]
    AttachDrag((headerName and _G[headerName]) or frame)

    -- Extra handles layered on top of the frame body
    local extra = EXTRA_DRAG_TARGETS[name]
    if extra then
        AttachDrag(type(extra) == "function" and extra(frame) or _G[extra])
    end

    frame:HookScript("OnShow", function()
        if not IsEnabled() then return end
        -- Scale first: stored position offsets are frame-local units, so the
        -- pin only lands right once the final scale is in effect.
        ApplyScale(frame, name)
        ApplyPosition(frame, name)
    end)

    frame:HookScript("OnHide", function()
        if not IsEnabled() then return end
        if secureDrag.frame == frame then StopSecureDrag() end
        tempPos[frame] = nil
        tempScale[frame] = nil
    end)

    -- Item Upgrade / Transmog / Item Socketing / Merchant (covers vendors
    -- like the Crest Exchange) dock beside CharacterFrame. Blizzard's own
    -- docking math assumes CharacterFrame sits at its default screen
    -- position; once Shifter has CharacterFrame pinned somewhere else that
    -- math falls apart and the companion ends up wherever Blizzard's now-
    -- wrong calculation put it -- frequently right on top of CharacterFrame's
    -- pinned spot, and since CharacterFrame's skin forces it to "HIGH"
    -- strata while these default to "MEDIUM", it then renders buried
    -- underneath. Docks left by default (matching Blizzard's normal layout),
    -- falling back to whichever side actually has room -- otherwise
    -- SetClampedToScreen just snaps it back onto CharacterFrame regardless of
    -- which side we pick. Only kicks in when the companion has no pin of its
    -- own; an explicit Shift+drag on the companion wins over auto-docking.
    local ShouldDock, DockToCharacterFrame
    if DOCKING_COMPANIONS[name] then
        local defaultStrata = frame:GetFrameStrata()
        ShouldDock = function()
            -- Protected frames (PVEFrame) still dock -- but position-only,
            -- through the SecureSetPoint branch below; their strata/Raise
            -- touches are skipped in the OnShow/OnHide hooks (insecure writes
            -- taint a protected tree -- the PVEFrame SetMovable incident).
            if tempPos[frame] or GetSavedPos(name) then return false end
            local cf = _G.CharacterFrame
            return cf ~= nil and cf:IsShown() and (tempPos[cf] or GetSavedPos("CharacterFrame")) ~= nil
        end
        DockToCharacterFrame = function()
            local cf = _G.CharacterFrame
            local margin = 4
            -- Compare available room in SCREEN-ABSOLUTE units. cf's edges
            -- are in CF's effective-scale space and this frame's width is in
            -- its own; raw mixing picks the wrong side (and mis-places the
            -- protected dock below) the moment either frame is
            -- Shifter-scaled -- which is the headline scenario here.
            local cs = cf:GetEffectiveScale() or 1
            local es = frame:GetEffectiveScale() or 1
            local ues = UIParent:GetEffectiveScale() or 1
            local wAbs = (frame:GetWidth() or 0) * es
            local leftRoom = (cf:GetLeft() or 0) * cs
            local rightRoom = (GetScreenWidth() or 0) * ues - (cf:GetRight() or 0) * cs
            local dockLeft = leftRoom >= wAbs + margin * es or leftRoom >= rightRoom
            if frame:IsProtected() then
                -- Plain SetPoint on a protected frame (e.g. PVEFrame) taints
                -- it -- same reason SecureSetPoint exists for saved/dragged
                -- positions above. SecureSetPoint only anchors relative to
                -- UIParent, so convert the dock target into a UIParent-CENTER
                -- offset, with every coordinate normalized through its own
                -- frame's effective scale (screen-absolute space) before
                -- dividing back into this frame's units.
                if InCombatLockdown() then return end
                local hAbs = (frame:GetHeight() or 0) * es
                local absCenterX
                if dockLeft then
                    absCenterX = leftRoom - margin * es - wAbs / 2
                else
                    absCenterX = (cf:GetRight() or 0) * cs + margin * es + wAbs / 2
                end
                local absCenterY = (cf:GetTop() or 0) * cs - hAbs / 2
                local ucx, ucy = UIParent:GetCenter()
                if ucx and es > 0 then
                    SecureSetPoint(frame, "CENTER", "CENTER",
                        (absCenterX - ucx * ues) / es,
                        (absCenterY - ucy * ues) / es)
                end
            else
                ffd._shIgnoreSP = true
                frame:ClearAllPoints()
                if dockLeft then
                    frame:SetPoint("TOPRIGHT", cf, "TOPLEFT", -margin, 0)
                else
                    frame:SetPoint("TOPLEFT", cf, "TOPRIGHT", margin, 0)
                end
                ffd._shIgnoreSP = false
            end
        end
        frame:HookScript("OnHide", function()
            -- Strata writes are INSECURE: on a protected frame (PVEFrame)
            -- they taint its whole tree, exactly like the SetMovable call
            -- that caused the original secret-value incident. Skip them.
            if not frame:IsProtected() then frame:SetFrameStrata(defaultStrata) end
        end)
        frame:HookScript("OnShow", function()
            if not IsEnabled() then return end
            if ShouldDock() then
                -- The strata raise only matters when the companion OVERLAPS
                -- CharacterFrame -- a docked frame no longer does. Protected
                -- frames therefore get position-only docking; strata and
                -- Raise are insecure writes that would taint their tree.
                if not frame:IsProtected() then frame:SetFrameStrata("DIALOG") end
                DockToCharacterFrame()
                if not frame:IsProtected() then frame:Raise() end
            end
        end)
        dockedCompanions[#dockedCompanions + 1] = { frame = frame, shouldDock = ShouldDock, dock = DockToCharacterFrame }
    elseif name == "CharacterFrame" then
        -- CharacterFrame itself isn't a companion, but every companion's dock
        -- is relative to IT -- so a scale or position change here is exactly
        -- what leaves already-open companions stale (see RedockCompanions).
        hooksecurefunc(frame, "SetPoint", function()
            if IsEnabled() then RedockCompanions() end
        end)
        hooksecurefunc(frame, "SetScale", function()
            if IsEnabled() then RedockCompanions() end
        end)
    else
        -- Any other Shifter-managed window can end up rendered underneath a
        -- Shifter-pinned CharacterFrame purely because CharacterFrame's skin
        -- forces it to "HIGH" strata -- not because it's meant to dock
        -- beside CharacterFrame (unlike DOCKING_COMPANIONS, this never
        -- touches position, just strata). Applies generically to every other
        -- Shifter-hooked frame so newly discovered cases don't need a
        -- hardcoded entry. Protected frames are skipped: SetFrameStrata and
        -- Raise are still INSECURE writes, and on a protected frame they
        -- taint its whole tree (the PVEFrame SetMovable incident) -- those
        -- stay at Blizzard strata, possibly buried but never tainted.
        local defaultStrata = frame:GetFrameStrata()
        frame:HookScript("OnHide", function()
            if not frame:IsProtected() then frame:SetFrameStrata(defaultStrata) end
        end)
        frame:HookScript("OnShow", function()
            if not IsEnabled() then return end
            if frame:IsProtected() then return end
            local cf = _G.CharacterFrame
            if cf and cf:IsShown() and (tempPos[cf] or GetSavedPos("CharacterFrame")) then
                frame:SetFrameStrata("DIALOG")
                frame:Raise()
            end
        end)
    end

    hooksecurefunc(frame, "SetPoint", function()
        if not IsEnabled() then return end
        if ffd._shIgnoreSP then return end
        if secureDrag.frame == frame then return end  -- don't fight an active drag
        if InCombatLockdown() and frame:IsProtected() then return end
        if DockToCharacterFrame and ShouldDock() then
            DockToCharacterFrame()
            return
        end
        if tempPos[frame] or GetSavedPos(name) then
            ApplyPosition(frame, name)
        end
    end)

    -- Re-assert the user's scale whenever Blizzard (or anything) changes it in
    -- place. Some windows rescale themselves on a state change with no
    -- hide/show to fire the OnShow restore -- e.g. the crafting order window
    -- resets its scale when you submit an order, so a scaled window snapped
    -- back. Only re-assert for frames the user has actually scaled; guarded so
    -- our own re-scale can't recurse.
    hooksecurefunc(frame, "SetScale", function()
        if not IsEnabled() then return end
        if ffd._shIgnoreSS then return end
        if InCombatLockdown() and frame:IsProtected() then return end
        if tempScale[frame] or GetSavedScale(name) then
            ApplyScale(frame, name)
        end
    end)

    -- If the frame is already visible, apply saved scale + position now
    if frame:IsVisible() then
        ApplyScale(frame, name)
        ApplyPosition(frame, name)
    end
end

local function TryHook(name)
    local frame = _G[name]
    if frame and frame.HookScript then HookFrame(frame, name) end
end

-------------------------------------------------------------------------------
--  Loot windows via Unlock Mode movers
--
--  The Bonus Roll window and the group loot roll container cannot be made
--  drag-movable: their top-level frames take no mouse input, and Blizzard
--  re-anchors them on every show through the GroupLootContainer docking and
--  the UIParent managed-frame-position system. Instead each gets a mover in
--  Unlock Mode. The mover drags a proxy frame we own; the saved position is
--  pushed onto the Blizzard window with plain ClearAllPoints/SetPoint (the
--  windows are unprotected) and re-applied whenever Blizzard repositions
--  them. ignoreFramePositionManager is the sanctioned per-frame opt-out from
--  the managed position system. Protected or forbidden frames are skipped
--  entirely, and no mouse state is ever touched.
--
--  AlertFrame is the anchor every toast banner stacks up from (loot and
--  currency toasts, achievements, gold, recipes, Trading Post activities).
--  It rides the same enforcement; its own rect is a bare anchor rather than
--  a toast-sized box, so its mover uses a fixed size (fixedSize).
-------------------------------------------------------------------------------
local LOOT_WINDOWS = {
    { name = "BonusRollFrame",     key = "EUI_BonusRoll",   label = "Bonus Roll",   order = 640, defW = 330, defH = 120, defY = 240 },
    { name = "GroupLootContainer", key = "EUI_GroupLoot",   label = "Group Loot",   order = 641, defW = 300, defH = 80,  defY = 340 },
    { name = "AlertFrame",         key = "EUI_AlertToasts", label = "Alert Toasts", order = 642, defW = 300, defH = 100, defY = 160, fixedSize = true },
}

local lootProxies = {}
local lootHooked  = {}

local function LootEnabled()
    return EllesmereUIDB and EllesmereUIDB.shifterLootUnlock or false
end

local function GetLootPos(name)
    local db = EllesmereUIDB
    return db and db.shifterLootPositions and db.shifterLootPositions[name]
end

local function SaveLootPos(name, point, relPoint, x, y)
    if not EllesmereUIDB then EllesmereUIDB = {} end
    if not EllesmereUIDB.shifterLootPositions then
        EllesmereUIDB.shifterLootPositions = {}
    end
    EllesmereUIDB.shifterLootPositions[name] = {
        point = point, relPoint = relPoint, x = x, y = y,
    }
end

-- Returns the live Blizzard frame only when it is safe to reposition.
local function LootFrame(name)
    local frame = _G[name]
    if not frame or not frame.HookScript then return nil end
    if frame.IsForbidden and frame:IsForbidden() then return nil end
    if frame:IsProtected() then return nil end
    return frame
end

local function ApplyLootPos(name)
    if not LootEnabled() then return end
    local pos = GetLootPos(name)
    if not pos then return end
    local frame = LootFrame(name)
    if not frame then return end
    local ffd = GetFFD(frame)
    if ffd._shLootIgnoreSP then return end
    ffd._shLootIgnoreSP = true
    frame.ignoreFramePositionManager = true
    frame:ClearAllPoints()
    frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    ffd._shLootIgnoreSP = false
end

local function HookLootWindow(name)
    if lootHooked[name] then return end
    local frame = LootFrame(name)
    if not frame then return end
    lootHooked[name] = true
    hooksecurefunc(frame, "SetPoint", function()
        if GetFFD(frame)._shLootIgnoreSP then return end
        ApplyLootPos(name)
    end)
    frame:HookScript("OnShow", function()
        ApplyLootPos(name)
    end)
end

-- Hidden rect-only ghost the unlock mover attaches to; never visible.
local function EnsureLootProxy(info)
    local proxy = lootProxies[info.name]
    if proxy then return proxy end
    proxy = CreateFrame("Frame", nil, UIParent)
    proxy:Hide()
    proxy:SetSize(info.defW, info.defH)
    local pos = GetLootPos(info.name)
    if pos then
        proxy:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        proxy:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, info.defY)
    end
    lootProxies[info.name] = proxy
    return proxy
end

local function InitLootWindows()
    for i = 1, #LOOT_WINDOWS do
        local name = LOOT_WINDOWS[i].name
        HookLootWindow(name)
        local frame = LootFrame(name)
        if frame and frame:IsVisible() then
            ApplyLootPos(name)
        end
    end
end

local function RegisterLootUnlockElements()
    local MK = EllesmereUI.MakeUnlockElement
    if not MK or not EllesmereUI.RegisterUnlockElements then return end
    local elements = {}
    for i = 1, #LOOT_WINDOWS do
        local info = LOOT_WINDOWS[i]
        elements[#elements + 1] = MK({
            key   = info.key,
            label = info.label,
            group = "Quality of Life",
            order = info.order,
            noResize          = true,
            noAnchorTarget    = true,
            noAnchorTo        = true,
            noSizeMatchTarget = true,
            -- Loot movers position hidden proxies, so their overlays linger
            -- until the user turns them off: brown tint + reminder subtitle
            -- to tell them apart from live-frame movers.
            moverBg  = { r = 0.165, g = 0.11, b = 0.055 },
            subtitle = "Disable Loot unlock mode overlays in Shifter once done positioning",
            isHidden = function()
                if not LootEnabled() or not _G[info.name] then return true end
                -- "Hide Unlock Mode Overlays": the movers stay out of unlock
                -- mode but saved positions keep applying (the SetPoint/OnShow
                -- enforcement never depends on the movers existing).
                return EllesmereUIDB and EllesmereUIDB.shifterLootHideOverlays or false
            end,
            getFrame = function()
                return EnsureLootProxy(info)
            end,
            getSize = function()
                if info.fixedSize then return info.defW, info.defH end
                local frame = _G[info.name]
                local w = frame and frame.GetWidth and frame:GetWidth() or 0
                local h = frame and frame.GetHeight and frame:GetHeight() or 0
                if not w or w < 20 then w = info.defW end
                if not h or h < 20 then h = info.defH end
                return w, h
            end,
            savePos = function(_, point, relPoint, x, y)
                SaveLootPos(info.name, point, relPoint, x, y)
                local proxy = EnsureLootProxy(info)
                proxy:ClearAllPoints()
                proxy:SetPoint(point, UIParent, relPoint, x, y)
                HookLootWindow(info.name)
                ApplyLootPos(info.name)
            end,
            loadPos = function()
                local pos = GetLootPos(info.name)
                if pos then
                    return { point = pos.point, relPoint = pos.relPoint, x = pos.x, y = pos.y }
                end
                return nil
            end,
            clearPos = function()
                if EllesmereUIDB and EllesmereUIDB.shifterLootPositions then
                    EllesmereUIDB.shifterLootPositions[info.name] = nil
                end
                local proxy = lootProxies[info.name]
                if proxy then
                    proxy:ClearAllPoints()
                    proxy:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, info.defY)
                end
                local frame = LootFrame(info.name)
                if frame then frame.ignoreFramePositionManager = nil end
            end,
            applyPos = function()
                local pos = GetLootPos(info.name)
                local proxy = EnsureLootProxy(info)
                proxy:ClearAllPoints()
                if pos then
                    proxy:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
                else
                    proxy:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, info.defY)
                end
                ApplyLootPos(info.name)
            end,
        })
    end
    EllesmereUI:RegisterUnlockElements(elements, "EllesmereUIQoL")
end

-------------------------------------------------------------------------------
--  Blizzard Top Bar Event Text (UIWidgetTopCenterContainerFrame) via an
--  Unlock Mode mover -- the loot-window recipe (hidden proxy + mover +
--  ignoreFramePositionManager + SetPoint/OnShow re-assert, no mouse state
--  ever touched) with ONE substitution: every position write on the live
--  frame runs through SecureSetPoint. The container hosts encounter and
--  scenario status-bar widgets whose Blizzard code compares SECRET values in
--  instanced combat; an insecure ClearAllPoints/SetPoint would taint that
--  tree and throw "attempt to compare a secret number" (the PVEFrame
--  lesson). The plain-SetPoint shortcut the loot windows use is safe there
--  only because their subtrees never touch secrets.
--
--  SecureSetPoint bails in combat, and Blizzard re-anchors this container
--  exactly then (widgets spawn mid-fight) -- missed re-asserts set a dirty
--  flag and re-apply on PLAYER_REGEN_ENABLED.
-------------------------------------------------------------------------------
local TOPBAR_NAME = "UIWidgetTopCenterContainerFrame"
local TOPBAR_KEY, TOPBAR_LABEL = "EUI_TopBarEventText", "Top Bar Event Text"
local TOPBAR_DEFW, TOPBAR_DEFH, TOPBAR_DEFY = 400, 60, -120

local topBarProxy
local topBarHooked = false
local topBarDirty  = false
local topBarRegen

local function TopBarEnabled()
    return EllesmereUIDB and EllesmereUIDB.shifterTopBarUnlock or false
end

local function GetTopBarPos()
    return EllesmereUIDB and EllesmereUIDB.shifterTopBarPos
end

local function SaveTopBarPos(point, relPoint, x, y)
    if not EllesmereUIDB then EllesmereUIDB = {} end
    EllesmereUIDB.shifterTopBarPos = { point = point, relPoint = relPoint, x = x, y = y }
end

-- Returns the live Blizzard frame only when it is safe to reposition.
local function TopBarFrame()
    local frame = _G[TOPBAR_NAME]
    if not frame or not frame.HookScript then return nil end
    if frame.IsForbidden and frame:IsForbidden() then return nil end
    if frame:IsProtected() then return nil end
    return frame
end

local function ApplyTopBarPos()
    if not TopBarEnabled() then return end
    local pos = GetTopBarPos()
    if not pos then return end
    local frame = TopBarFrame()
    if not frame then return end
    local ffd = GetFFD(frame)
    if ffd._shTopBarIgnoreSP then return end
    ffd._shTopBarIgnoreSP = true
    frame.ignoreFramePositionManager = true
    -- SECURE write only (see block comment); false = in combat, defer.
    if not SecureSetPoint(frame, pos.point, pos.relPoint, pos.x, pos.y) then
        topBarDirty = true
    end
    ffd._shTopBarIgnoreSP = false
end

local function HookTopBar()
    if topBarHooked then return end
    local frame = TopBarFrame()
    if not frame then return end
    topBarHooked = true
    hooksecurefunc(frame, "SetPoint", function()
        if GetFFD(frame)._shTopBarIgnoreSP then return end
        ApplyTopBarPos()
    end)
    frame:HookScript("OnShow", function()
        ApplyTopBarPos()
    end)
    topBarRegen = CreateFrame("Frame")
    topBarRegen:RegisterEvent("PLAYER_REGEN_ENABLED")
    topBarRegen:SetScript("OnEvent", function()
        if topBarDirty then
            topBarDirty = false
            ApplyTopBarPos()
        end
    end)
end

-- Hidden rect-only ghost the unlock mover attaches to; never visible.
local function EnsureTopBarProxy()
    if topBarProxy then return topBarProxy end
    topBarProxy = CreateFrame("Frame", nil, UIParent)
    topBarProxy:Hide()
    topBarProxy:SetSize(TOPBAR_DEFW, TOPBAR_DEFH)
    local pos = GetTopBarPos()
    if pos then
        topBarProxy:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        topBarProxy:SetPoint("TOP", UIParent, "TOP", 0, TOPBAR_DEFY)
    end
    return topBarProxy
end

local function RegisterTopBarUnlockElement()
    local MK = EllesmereUI.MakeUnlockElement
    if not MK or not EllesmereUI.RegisterUnlockElements then return end
    EllesmereUI:RegisterUnlockElements({
        MK({
            key   = TOPBAR_KEY,
            label = TOPBAR_LABEL,
            group = "Quality of Life",
            order = 643,
            noResize          = true,
            noAnchorTarget    = true,
            noAnchorTo        = true,
            noSizeMatchTarget = true,
            moverBg  = { r = 0.165, g = 0.11, b = 0.055 },
            subtitle = "Disable the Top Bar Event Text overlay in Shifter once done positioning",
            isHidden = function()
                if not TopBarEnabled() or not _G[TOPBAR_NAME] then return true end
                -- "Hide Unlock Mode Overlay": mover stays out of unlock mode
                -- but the saved position keeps applying (the SetPoint/OnShow
                -- enforcement never depends on the mover existing).
                return EllesmereUIDB and EllesmereUIDB.shifterTopBarHideOverlay or false
            end,
            getFrame = EnsureTopBarProxy,
            -- Bare/dynamic rect (empty without widgets): fixed mover box.
            getSize = function()
                return TOPBAR_DEFW, TOPBAR_DEFH
            end,
            savePos = function(_, point, relPoint, x, y)
                SaveTopBarPos(point, relPoint, x, y)
                local proxy = EnsureTopBarProxy()
                proxy:ClearAllPoints()
                proxy:SetPoint(point, UIParent, relPoint, x, y)
                HookTopBar()
                ApplyTopBarPos()
            end,
            loadPos = function()
                local pos = GetTopBarPos()
                if pos then
                    return { point = pos.point, relPoint = pos.relPoint, x = pos.x, y = pos.y }
                end
                return nil
            end,
            clearPos = function()
                if EllesmereUIDB then EllesmereUIDB.shifterTopBarPos = nil end
                local proxy = topBarProxy
                if proxy then
                    proxy:ClearAllPoints()
                    proxy:SetPoint("TOP", UIParent, "TOP", 0, TOPBAR_DEFY)
                end
                local frame = TopBarFrame()
                if frame then frame.ignoreFramePositionManager = nil end
            end,
            applyPos = function()
                local pos = GetTopBarPos()
                local proxy = EnsureTopBarProxy()
                proxy:ClearAllPoints()
                if pos then
                    proxy:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
                else
                    proxy:SetPoint("TOP", UIParent, "TOP", 0, TOPBAR_DEFY)
                end
                ApplyTopBarPos()
            end,
        }),
    }, "EllesmereUIQoL")
end

-- Exposed for the options toggle (mid-session enable without /reload)
function EllesmereUI._InitShifterTopBar()
    HookTopBar()
    local frame = TopBarFrame()
    if frame and frame:IsVisible() then
        ApplyTopBarPos()
    end
end

-- Exposed for the options toggle. Releases the container back to Blizzard's
-- position management; existing hooks go dormant via the TopBarEnabled gate.
function EllesmereUI._DisableShifterTopBar()
    local frame = TopBarFrame()
    if frame then frame.ignoreFramePositionManager = nil end
end

-------------------------------------------------------------------------------
--  Event-driven initialization
-------------------------------------------------------------------------------
local pendingAddons = {}
eventFrame = CreateFrame("Frame")

local function InitShifter()
    for i = 1, #PRELOADED do
        TryHook(PRELOADED[i])
    end
    for addon, frames in pairs(ADDON_FRAMES) do
        if C_AddOns.IsAddOnLoaded(addon) then
            for i = 1, #frames do TryHook(frames[i]) end
        else
            pendingAddons[addon] = frames
        end
    end
    if next(pendingAddons) then
        eventFrame:RegisterEvent("ADDON_LOADED")
    end
    -- Scroll-wheel scaling: arm the capture overlay on modifier presses.
    eventFrame:RegisterEvent("MODIFIER_STATE_CHANGED")
end

eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        if IsEnabled() then InitShifter() end
        RegisterLootUnlockElements()
        if LootEnabled() then InitLootWindows() end
        RegisterTopBarUnlockElement()
        if TopBarEnabled() then EllesmereUI._InitShifterTopBar() end
    elseif event == "ADDON_LOADED" then
        local frames = pendingAddons[arg1]
        if frames then
            pendingAddons[arg1] = nil
            for i = 1, #frames do TryHook(frames[i]) end
            if not next(pendingAddons) then
                self:UnregisterEvent("ADDON_LOADED")
            end
        end
    elseif event == "MODIFIER_STATE_CHANGED" then
        UpdateWheelOverlay()
    elseif event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        for i = 1, #deferredMovable do
            local f = deferredMovable[i]
            f:SetMovable(true)
            f:SetClampedToScreen(true)
        end
        wipe(deferredMovable)
    end
end)

-- Exposed for the options toggle (mid-session enable without /reload)
function EllesmereUI._InitShifter()
    InitShifter()
end

-- Exposed for the options toggle (mid-session disable). Stops the modifier
-- key listener and parks the wheel overlay; re-enable re-runs InitShifter,
-- which registers the event again. Frame hooks are irreversible and stay
-- installed, but every hook body bails first-line while disabled.
function EllesmereUI._ShutdownShifter()
    eventFrame:UnregisterEvent("MODIFIER_STATE_CHANGED")
    UpdateWheelOverlay()
end

-- Exposed for the options reset button (positions AND zoom)
function EllesmereUI._ResetShifterPositions()
    if EllesmereUIDB then
        EllesmereUIDB.shifterPositions = nil
        EllesmereUIDB.shifterLootPositions = nil
        EllesmereUIDB.shifterTopBarPos = nil
        EllesmereUIDB.shifterScales = nil
    end
    wipe(tempPos)
    wipe(tempScale)
end

-- Exposed for the options toggle (mid-session enable without /reload)
function EllesmereUI._InitShifterLootWindows()
    InitLootWindows()
end

-- Exposed for the options toggle. Releases the loot windows back to
-- Blizzard's position management; existing hooks go dormant via the
-- LootEnabled gate.
function EllesmereUI._DisableShifterLootWindows()
    for i = 1, #LOOT_WINDOWS do
        local frame = LootFrame(LOOT_WINDOWS[i].name)
        if frame then frame.ignoreFramePositionManager = nil end
    end
end
