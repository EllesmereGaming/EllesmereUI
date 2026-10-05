if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_ActionBars_ExtraBars.lua
--
--  Blizzard movable frames (Extra Action Button, Encounter Bar), the holders
--  for the Micro Menu and Bag Bar, and the extra bars setup. Loads after
--  EUI_ActionBars_DataBars.lua and reads the main file through ns only.
-------------------------------------------------------------------------------
local _, ns = ...

local _G = _G
local ipairs, pairs, type, pcall = ipairs, pairs, type, pcall
local max = math.max
local wipe = wipe
local InCombatLockdown = InCombatLockdown
local hooksecurefunc = hooksecurefunc
local C_Timer_After = C_Timer.After
local GetBindingKey = GetBindingKey

local EAB, EAB_VTABLE, EXTRA_BARS = ns.EAB, ns.EAB_VTABLE, ns.EXTRA_BARS
local ForceCooldownPaint = ns.ForceCooldownPaint
local I = ns._internals
local BLIZZ_MOVABLE_OVERLAY, FormatHotkeyText, SafeEnableMouse = I.BLIZZ_MOVABLE_OVERLAY, I.FormatHotkeyText, I.SafeEnableMouse
local SetupDataBars, _quickKeybindState = I.SetupDataBars, I._quickKeybindState
local blizzMovableHolders, extraBarHolders, hoverStates = I.blizzMovableHolders, I.extraBarHolders, I.hoverStates
local AttachExtraBarHoverHooks -- assigned below, published as ns.AttachExtraBarHoverHooks

-------------------------------------------------------------------------------
--  Blizzard Movable Frames (Extra Action Button, Encounter Bar): creates
--  non-secure holder frames, reparents Blizzard frames into them, and
--  disables Blizzard's layout management so we can reposition freely.
--  Overlay sizes are hardcoded (don't affect actual Blizzard frame rendering).
-------------------------------------------------------------------------------
local _blizzMovablePendingOOC = {} -- deferred reparents for when combat ends

-- Silence a frame's layout participation and mouse interaction permanently.
-- Does NOT nil OnShow/OnHide -- those drive child frame visibility.
-- Only kills the OnUpdate repositioning loop and layout system membership.
local function DisableLayoutFrame(f)
    if not f then return end
    f.ignoreInLayout = true
    f.ignoreFramePositionManager = true
    f.IsLayoutFrame = nil
    if f.SetIsLayoutFrame then pcall(f.SetIsLayoutFrame, f, false) end
    f:SetScript("OnUpdate", nil)
    f.OnUpdate = nil
    f:EnableMouse(false)
end

local function SetupBlizzardMovableFrame(barKey)
    local holder = CreateFrame("Frame", "EllesmereEAB_" .. barKey, UIParent)
    holder:SetClampedToScreen(true)
    holder:EnableMouse(false)
    blizzMovableHolders[barKey] = holder

    local ov = BLIZZ_MOVABLE_OVERLAY[barKey]
    holder:SetSize(ov and ov.w or 50, ov and ov.h or 50)

    -- Identify which Blizzard frames to manage for this bar key.
    -- extraFrames = all frames that get reparented into the holder.
    local primaryFrame   -- the frame we read position from before reparenting
    local extraFrames = {}

    if barKey == "ExtraActionButton" then
        -- ExtraAbilityContainer is the layout container Blizzard's Edit Mode
        -- positions. It parents ExtraActionBarFrame and ZoneAbilityFrame.
        -- We take ownership of the whole container.
        if ExtraAbilityContainer then
            primaryFrame = ExtraAbilityContainer
            extraFrames[#extraFrames + 1] = ExtraAbilityContainer
        end
        -- ExtraActionBarFrame mouse is disabled in the container setup below.
    elseif barKey == "EncounterBar" then
        -- PlayerPowerBarAlt is the classic encounter power bar.
        -- UIWidgetPowerBarContainerFrame is used by newer mechanics.
        if PlayerPowerBarAlt then
            primaryFrame = PlayerPowerBarAlt
            extraFrames[#extraFrames + 1] = PlayerPowerBarAlt
        end
        if UIWidgetPowerBarContainerFrame then
            if not primaryFrame then primaryFrame = UIWidgetPowerBarContainerFrame end
            extraFrames[#extraFrames + 1] = UIWidgetPowerBarContainerFrame
        end
    end

    if #extraFrames == 0 then
        holder:Hide()
        return
    end

    -- Restore saved position BEFORE reparenting so we can still read the
    -- original Blizzard-placed position if no save exists yet.
    local pos = EAB.db.profile.barPositions[barKey]
    if pos and pos.point then
        holder:ClearAllPoints()
        holder:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
    else
        -- Try to capture Blizzard's current Edit Mode position immediately.
        -- If the frame has no valid bounds yet, defer via OnUpdate.
        local src = primaryFrame
        local function TryCapturePosition(self)
            local bL, bT = src:GetLeft(), src:GetTop()
            local bR, bB = src:GetRight(), src:GetBottom()
            if bL and bT and bR and bB and (bR - bL) > 1 then
                local bS = src:GetEffectiveScale()
                local uS = UIParent:GetEffectiveScale()
                local uiW, uiH = UIParent:GetSize()
                local cx = (bL + bR) * 0.5 * bS / uS - uiW / 2
                local cy = (bT + bB) * 0.5 * bS / uS - uiH / 2
                EAB.db.profile.barPositions[barKey] = { point = "CENTER", relPoint = "CENTER", x = cx, y = cy }
                holder:ClearAllPoints()
                holder:SetPoint("CENTER", UIParent, "CENTER", cx, cy)
                if self then self:SetScript("OnUpdate", nil) end
                return true
            end
            return false
        end
        if not TryCapturePosition(nil) then
            holder:ClearAllPoints()
            holder:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
            local attempts = 0
            local captureFrame = CreateFrame("Frame")
            captureFrame:SetScript("OnUpdate", function(self)
                attempts = attempts + 1
                if TryCapturePosition(self) or attempts > 300 then
                    self:SetScript("OnUpdate", nil)
                end
            end)
        end
    end

    -- Reparent all managed frames into the holder, centered.
    -- Safe to call multiple times; guards against combat lockdown.
    local function ReparentIntoHolder()
        if InCombatLockdown() then
            _blizzMovablePendingOOC[barKey] = true
            return
        end
        for _, f in ipairs(extraFrames) do
            f.ignoreInLayout = true
            f.ignoreFramePositionManager = true
            if f.SetIsLayoutFrame then pcall(f.SetIsLayoutFrame, f, false) end
            f:SetParent(holder)
            f:ClearAllPoints()
            f:SetPoint("CENTER", holder, "CENTER", 0, 0)
        end
    end

    -- Extra Action Button: disable the container's layout-driven repositioning and
    -- reparent it into our holder. Keep OnShow/OnHide nil'd on the container so
    -- Blizzard's layout code cannot fire, but leave the child frames
    -- (ExtraActionBarFrame, ZoneAbilityFrame) untouched so they show and hide normally.
    if barKey == "ExtraActionButton" and ExtraAbilityContainer then
        -- Hide the Edit Mode selection overlay so it doesn't appear in
        -- Blizzard's Edit Mode (we own this frame's position via unlock).
        local eacSel = ExtraAbilityContainer.Selection
        if eacSel then
            eacSel:SetAlpha(0)
            eacSel:EnableMouse(false)
            if not EllesmereUI._GetFFD(eacSel).showHooked then
                EllesmereUI._GetFFD(eacSel).showHooked = true
                hooksecurefunc(eacSel, "Show", function(self)
                    self:SetAlpha(0)
                    self:EnableMouse(false)
                end)
            end
        end

        -- Disable mouse on ExtraActionBarFrame so it cannot absorb clicks
        -- when no extra action bar is active.
        if ExtraActionBarFrame and not InCombatLockdown() and ExtraActionBarFrame:IsMouseEnabled() then
            ExtraActionBarFrame:EnableMouse(false)
        end

        -- Nil container OnShow/OnHide so Blizzard's layout code
        -- (UpdateManagedFramePositions) cannot fire when the container shows.
        ExtraAbilityContainer:SetScript("OnShow", nil)
        ExtraAbilityContainer:SetScript("OnHide", nil)

        -- Refresh ExtraActionButton1's keybind text and cooldown swipe. The
        -- broadcaster kill at load prevents Blizzard's UPDATE_BINDINGS and cooldown
        -- updates from reaching this button, so we drive both here. UpdateAction runs
        -- first; the keybind is set after so Blizzard's own UpdateHotkeys (which hides
        -- the key when GetBindingKey is momentarily nil) can't clobber our text.
        -- Unlike the cooldown -- which recovers via the ACTIONBAR_UPDATE_COOLDOWN
        -- dispatcher -- the keybind has no such fallback, so every path that can
        -- reveal the button refreshes it.
        local function RefreshExtraActionButton()
            local eab1 = ExtraActionButton1
            if not eab1 then return end
            -- Cooldown-only refresh below; avoids passing secret cooldown values through a tainted call.
            local hk = eab1.HotKey
            if hk then
                local key1 = GetBindingKey("EXTRAACTIONBUTTON1")
                if key1 then
                    hk:SetText(FormatHotkeyText(key1))
                    hk:Show()
                end
            end
            ForceCooldownPaint(eab1)
            -- Re-evaluate the broadcaster need now: this container Show/AddFrame
            -- refresh is a reliable delve-entry signal (the button's own OnShow
            -- doesn't fire then), and RefreshBroadcaster reads the button's
            -- actual visibility to decide.
            if ns.RefreshBroadcaster then
                ns.RefreshBroadcaster()
            end
        end

        -- Hook AddFrame so newly added ability buttons stay clickable, and
        -- refresh the extra action button. When the container is already shown
        -- (e.g. a zone ability is active) and the extra action button then
        -- becomes active, that fires AddFrame but not the container's Show hook,
        -- so this is the only refresh signal for that path. Deferred one frame so
        -- Blizzard has finished assigning the button's action before we read it.
        if ExtraAbilityContainer.AddFrame then
            hooksecurefunc(ExtraAbilityContainer, "AddFrame", function(_, frame)
                if frame and frame.EnableMouse and not InCombatLockdown() then
                    frame:EnableMouse(true)
                end
                C_Timer_After(0, RefreshExtraActionButton)
            end)
        end

        -- Reposition the container into our holder.
        local function RepositionExtraContainer()
            if InCombatLockdown() then return end
            local container = ExtraAbilityContainer
            container:SetParent(holder)
            if container.ClearAllPointsBase then
                container:ClearAllPointsBase()
                container:SetPointBase("CENTER", holder)
            else
                container:ClearAllPoints()
                container:SetPoint("CENTER", holder)
            end
        end
        RepositionExtraContainer()

        -- Re-reparent when Edit Mode tries to reposition the container.
        if ExtraAbilityContainer.ApplySystemAnchor then
            hooksecurefunc(ExtraAbilityContainer, "ApplySystemAnchor", function()
                local _, relFrame = ExtraAbilityContainer:GetPoint()
                if relFrame ~= holder then
                    RepositionExtraContainer()
                end
                -- Do NOT write to UIParentBottomManagedFrameContainer.showingFrames
                -- here. Writing into that Blizzard-owned table from this insecure hook
                -- taints the managed-frame-position system; a later in-combat layout
                -- pass (e.g. leaving a queued/follower instance while in combat) then
                -- blocks the protected ClearAllPoints on the managed containers
                -- (ADDON_ACTION_BLOCKED naming this addon). ExtraAbilityContainer
                -- already carries ignoreFramePositionManager and ignoreInLayout, so
                -- Blizzard excludes it from layout without us touching showingFrames.
            end)
        end

        -- Re-reparent after Blizzard's OnShow repositions the container.
        -- (We nil'd the script, but hooksecurefunc still fires on Show.)
        hooksecurefunc(ExtraAbilityContainer, "Show", function()
            if ExtraAbilityContainer:GetParent() ~= holder then
                RepositionExtraContainer()
            end
            RefreshExtraActionButton()
        end)

        -- Quick-reload catch-up: if the button is already showing, its
        -- Show/AddFrame fired before this deferred setup registered the
        -- hooks above, so we missed them. Refresh now so the keybind isn't
        -- left blank until the next show -- the cooldown recovers on its own
        -- via the dispatcher, the keybind has no such fallback.
        if ExtraActionButton1 and ExtraActionButton1:IsShown() then
            RefreshExtraActionButton()
        end
    end

    -- Encounter Bar: reparent into holder, mark as user-placed so Blizzard's position
    -- manager leaves it alone, and hook setup functions to re-reparent. SetPoint hooks
    -- intercept any Blizzard repositioning (EditMode, layout passes, encounter setup)
    -- and force the frame back to the holder.
    if barKey == "EncounterBar" then
        -- Hook SetPoint on encounter frames: if anything positions them away
        -- from our holder, force them back. The hook fires after the
        -- original SetPoint so the second call (ours) sees relativeTo ==
        -- holder and exits cleanly with no recursion.
        local function HookEncounterSetPoint(frame)
            hooksecurefunc(frame, "SetPoint", function(self, _, relativeTo)
                if relativeTo ~= holder then
                    self:ClearAllPoints()
                    self:SetPoint("CENTER", holder, "CENTER", 0, 0)
                end
            end)
        end

        local ppb = PlayerPowerBarAlt
        if ppb then
            ppb:SetMovable(true)
            ppb:SetUserPlaced(true)
            ppb:SetDontSavePosition(true)

            ppb:ClearAllPoints()
            ppb:SetParent(holder)
            ppb:SetPoint("CENTER", holder)

            HookEncounterSetPoint(ppb)

            if type(ppb.SetupPlayerPowerBarPosition) == "function" then
                hooksecurefunc(ppb, "SetupPlayerPowerBarPosition", function(bar)
                    if bar:GetParent() ~= holder then
                        ReparentIntoHolder()
                    end
                end)
            end

            if type(UnitPowerBarAlt_SetUp) == "function" then
                hooksecurefunc("UnitPowerBarAlt_SetUp", function(bar)
                    if bar.isPlayerBar and bar:GetParent() ~= holder then
                        ReparentIntoHolder()
                    end
                end)
            end

            ppb:HookScript("OnSizeChanged", function(self)
                local w, h = self:GetSize()
                if w > 1 and h > 1 then holder:SetSize(w, h) end
            end)
        end

        local uwb = UIWidgetPowerBarContainerFrame
        if uwb then
            DisableLayoutFrame(uwb)
            -- Kill the container's Layout method so Blizzard's widget
            -- system can't reposition it when children are added/removed.
            if uwb.Layout then uwb.Layout = function() end end
            if uwb.MarkDirty then uwb.MarkDirty = function() end end
            HookEncounterSetPoint(uwb)
            uwb:HookScript("OnSizeChanged", function(self)
                local w, h = self:GetSize()
                if w > 1 and h > 1 then
                    local hw, hh = holder:GetSize()
                    holder:SetSize(max(hw, w), max(hh, h))
                end
            end)
        end

        -- Re-anchor on Show: Blizzard may reposition encounter frames while hidden
        -- (zone change, encounter setup), and our SetPoint hook only catches explicit
        -- SetPoint calls, not inherited position from a pre-show layout pass.
        for _, f in ipairs(extraFrames) do
            f:HookScript("OnShow", function(self)
                if self:GetParent() ~= holder then
                    ReparentIntoHolder()
                else
                    self:ClearAllPoints()
                    self:SetPoint("CENTER", holder, "CENTER", 0, 0)
                end
            end)
        end
    end

    -- Initial reparent.
    ReparentIntoHolder()

    -- Hook SetParent on every managed frame so we re-reparent immediately if
    -- Blizzard or another addon steals the frame back.
    for _, f in ipairs(extraFrames) do
        hooksecurefunc(f, "SetParent", function(self, newParent)
            if newParent ~= holder then
                ReparentIntoHolder()
            end
        end)
    end

    -- Apply visibility settings
    local s = EAB.db.profile.bars[barKey]
    if s and s.alwaysHidden then holder:Hide() end

    return holder
end

-- Deferred reparent handler: fires when combat ends.
local _blizzMovableCombatFrame = CreateFrame("Frame")
_blizzMovableCombatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
_blizzMovableCombatFrame:SetScript("OnEvent", function()
    if InCombatLockdown() then return end
    for barKey in pairs(_blizzMovablePendingOOC) do
        local holder = blizzMovableHolders[barKey] or extraBarHolders[barKey]
        if not holder then
            for _, info in ipairs(EXTRA_BARS) do
                if info.key == barKey then
                    holder = extraBarHolders[barKey]
                    break
                end
            end
        end
        if barKey == "ExtraActionButton" and holder and ExtraAbilityContainer then
            ExtraAbilityContainer.ignoreInLayout = true
            ExtraAbilityContainer.ignoreFramePositionManager = true
            if ExtraAbilityContainer.SetIsLayoutFrame then
                pcall(ExtraAbilityContainer.SetIsLayoutFrame, ExtraAbilityContainer, false)
            end
            ExtraAbilityContainer:SetParent(holder)
            ExtraAbilityContainer:ClearAllPoints()
            ExtraAbilityContainer:SetPoint("CENTER", holder, "CENTER", 0, 0)
        elseif barKey == "EncounterBar" and holder then
            for _, f in ipairs({ PlayerPowerBarAlt, UIWidgetPowerBarContainerFrame }) do
                if f then
                    f.ignoreInLayout = true
                    f.ignoreFramePositionManager = true
                    if f.SetIsLayoutFrame then pcall(f.SetIsLayoutFrame, f, false) end
                    f:SetParent(holder)
                    f:ClearAllPoints()
                    f:SetPoint("CENTER", holder, "CENTER", 0, 0)
                end
            end
        elseif holder then
            for _, info in ipairs(EXTRA_BARS) do
                if info.key == barKey and info.frameName then
                    local f = _G[info.frameName]
                    if f then
                        f.ignoreInLayout = true
                        if f.SetIsLayoutFrame then pcall(f.SetIsLayoutFrame, f, false) end
                        f:SetParent(holder)
                        f:ClearAllPoints()
                        f:SetPoint("CENTER", holder, "CENTER", 0, 0)
                    end
                    break
                end
            end
        end
    end
    wipe(_blizzMovablePendingOOC)

    -- Re-disable mouse on ExtraActionBarFrame after combat ends.
    -- Blizzard's secure code re-enables mouse on protected frames during combat.
    if ExtraActionBarFrame and ExtraActionBarFrame:IsMouseEnabled() then
        ExtraActionBarFrame:EnableMouse(false)
    end
end)


-- Revert UserPlaced on logout so Blizzard doesn't persist our stale position.
local _blizzMovableLogoutFrame = CreateFrame("Frame")
_blizzMovableLogoutFrame:RegisterEvent("PLAYER_LOGOUT")
_blizzMovableLogoutFrame:SetScript("OnEvent", function()
    if PlayerPowerBarAlt and PlayerPowerBarAlt:IsMovable() then
        PlayerPowerBarAlt:SetUserPlaced(false)
    end
end)

local function SetupBlizzardMovableFrames()
    for _, info in ipairs(EXTRA_BARS) do
        if info.isBlizzardMovable then
            -- EncounterBar: position fully owned by Blizzard Edit Mode.
            if info.key == "EncounterBar" then
                -- no-op: let Blizzard own position entirely
            else
                SetupBlizzardMovableFrame(info.key)
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Extra Bar Holders (MicroBar, BagBar) positioning via holder frames.
--  Reparents Blizzard frames into holder frames so unlock mode can position them.
-------------------------------------------------------------------------------
AttachExtraBarHoverHooks = function(info)
    -- Position-only Blizzard-owned bars (the QueueStatus eye) never get mouseover
    -- fade hooks -- EUI controls only their position now, not visibility. Without
    -- this, a stale "mouseover" setting would fade the eye to alpha 0 on leave.
    if info.noManagedVisibility then return end
    -- Idempotent: only attach once per bar key
    if hoverStates[info.key] then return end

    local blizzFrame = _G[info.frameName]
    if not blizzFrame then return end
    local holder = extraBarHolders[info.key]
    local hoverFrame = info.hoverFrame and _G[info.hoverFrame]

    -- Fade the Blizzard frame directly rather than the holder.
    -- The holder is for positioning only; fading it can be overridden by
    -- Blizzard's own layout code calling SetAlpha on the child frame.
    local fadeTarget = blizzFrame
    local hoverRoot = hoverFrame or blizzFrame

    local state = EAB_VTABLE.Hover.GetState(info.key, fadeTarget)

    local function IsChildOfHoverRoot(frame)
        while frame do
            if frame == hoverRoot then
                return true
            end
            frame = frame.GetParent and frame:GetParent() or nil
        end
        return false
    end

    local function IsHoverRootActive()
        local foci = GetMouseFoci()
        if foci then
            for _, focus in ipairs(foci) do
                if focus and IsChildOfHoverRoot(focus) then
                    return true
                end
            end
        end

        return hoverRoot:IsMouseOver()
    end

    local OnEnter, OnLeave = EAB_VTABLE.Hover.BuildHandlers(info.key, state, {
        canEnter = function()
            return IsHoverRootActive()
        end,
        isStillHovered = function()
            return IsHoverRootActive()
        end,
        markHoveredWhileActive = true,
    })

    hoverRoot:HookScript("OnEnter", OnEnter)
    hoverRoot:HookScript("OnLeave", OnLeave)

    -- Recurse into child frames to hook all interactive buttons, including
    -- those nested inside sub-containers (e.g. MicroMenu inside MicroMenuContainer).
    local function HookChildren(parent, depth)
        depth = depth or 0
        if depth > 3 then return end
        for _, child in ipairs({ parent:GetChildren() }) do
            if child:IsObjectType("Button") or child:IsObjectType("CheckButton") or child:IsObjectType("ItemButton") then
                child:HookScript("OnEnter", OnEnter)
                child:HookScript("OnLeave", OnLeave)
            else
                -- Recurse into non-button containers
                HookChildren(child, depth + 1)
            end
        end
    end
    HookChildren(hoverRoot)
end

-- WoW Forever: while the variant renders and no eye position is saved, the
-- queue eye sits at its stock minimap spot and is never captured: on the
-- ring where Blizzard's Forever layout puts it while the minimap draws that
-- ring (its spot helper answers), else at that layout's anchor on the map.
-- Anchored to the map, so a move carries it; the minimap's apply pass calls
-- the relayout below on a resize, and its button row reads the predicate to
-- start past the eye. An unlock-mode drag saves a position, which wins until
-- the look changes (every switch to the variant clears it). Once per
-- profile, while the ring is drawn, a spot saved before the variant placed
-- the eye (a login capture) gives way; the stamp is set as soon as nothing
-- is saved, so every later spot is the player's own.
function ns.AB_ForeverEyeParked()
    if not ns.AB_Forever() then return false end
    local p = EAB.db.profile
    local qs = p.barPositions.QueueStatus
    if not p.foreverEyeRingSeeded then
        if not (qs and qs.point) then
            p.foreverEyeRingSeeded = true
        else
            local mm = EllesmereUI._ModuleNS.EllesmereUIMinimap
            if mm and mm.MinimapQueueEyeSpot() then
                p.foreverEyeRingSeeded = true
                p.barPositions.QueueStatus = nil
                qs = nil
            end
        end
    end
    return not (qs and qs.point)
end
-- Places the holder there; true when parked.
function ns.AB_ForeverEyePark(holder)
    if not (holder and ns.AB_ForeverEyeParked()) then return false end
    local mm = EllesmereUI._ModuleNS.EllesmereUIMinimap
    local map, x, y
    if mm then map, x, y = mm.MinimapQueueEyeSpot() end
    holder:ClearAllPoints()
    if map then
        holder:SetPoint("CENTER", map, "CENTER", x, y)
    else
        -- Blizzard's stock spot, which scales with the minimap's Edit Mode size.
        local ms = (MinimapCluster and MinimapCluster.GetEditModeScale and MinimapCluster:GetEditModeScale()) or 1
        holder:SetPoint("CENTER", Minimap, "CENTER", -68 * ms, -68 * ms)
    end
    return true
end
function ns.AB_ForeverEyeRelayout()
    ns.AB_ForeverEyePark(extraBarHolders.QueueStatus)
end

local function SetupExtraBarHolder(barKey, frameName, barInfo)
    local blizzFrame = _G[frameName]
    if not blizzFrame then return end

    local holder = CreateFrame("Frame", "EllesmereEAB_" .. barKey, UIParent)
    holder:SetClampedToScreen(true)
    extraBarHolders[barKey] = holder

    -- Size the holder to match the Blizzard frame
    local w, h = blizzFrame:GetWidth(), blizzFrame:GetHeight()
    if w and w > 1 and h and h > 1 then
        holder:SetSize(w, h)
    else
        holder:SetSize(200, 40)
    end

    -- MicroBar/BagBar: position fully owned by Blizzard Edit Mode.
    -- Don't save or restore positions -- passive-follow handles it.
    -- Early return skips all position capture/restore code below.
    if barKey == "MicroBar" or barKey == "BagBar" then
        EAB.db.profile.barPositions[barKey] = nil
        local function SyncFollow()
            local fw, fh = blizzFrame:GetWidth(), blizzFrame:GetHeight()
            if fw and fw > 1 and fh and fh > 1 then
                -- In our own units: Edit Mode's Size setting scales the frame.
                local k = blizzFrame:GetEffectiveScale() / holder:GetEffectiveScale()
                holder:SetSize(fw * k, fh * k)
            end
            holder:ClearAllPoints()
            holder:SetPoint("CENTER", blizzFrame, "CENTER", 0, 0)
            -- The bar's end caps follow the frame's size and orientation.
            ns.AB_ExtraCaps(barKey)
        end
        SyncFollow()
        blizzFrame:HookScript("OnSizeChanged", function() SyncFollow() end)
        if blizzFrame.ApplySystemAnchor then
            hooksecurefunc(blizzFrame, "ApplySystemAnchor", function()
                C_Timer_After(0, SyncFollow)
            end)
        end
        -- A Size change only rescales the frame (no size event).
        if blizzFrame.UpdateSystemSettingSize then
            hooksecurefunc(blizzFrame, "UpdateSystemSettingSize", function()
                C_Timer_After(0, SyncFollow)
            end)
        end
        return holder
    end

    -- Restore saved position or capture current Blizzard position
    local pos = EAB.db.profile.barPositions[barKey]
    if barKey == "QueueStatus" and ns.AB_ForeverEyePark(holder) then
        -- WoW Forever: at its stock spot on the minimap (never captured).
    elseif pos and pos.point then
        holder:ClearAllPoints()
        holder:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
    else
        local bL, bT = blizzFrame:GetLeft(), blizzFrame:GetTop()
        local bR, bB = blizzFrame:GetRight(), blizzFrame:GetBottom()
        if bL and bT and bR and bB and (bR - bL) > 1 then
            local bS = blizzFrame:GetEffectiveScale()
            local uiS = UIParent:GetEffectiveScale()
            local uiW, uiH = UIParent:GetSize()
            local cx = (bL + bR) * 0.5 * bS / uiS - uiW / 2
            local cy = (bT + bB) * 0.5 * bS / uiS - uiH / 2
            EAB.db.profile.barPositions[barKey] = {
                point = "CENTER", relPoint = "CENTER", x = cx, y = cy,
            }
            holder:ClearAllPoints()
            holder:SetPoint("CENTER", UIParent, "CENTER", cx, cy)
        else
            -- Defer capture
            holder:ClearAllPoints()
            holder:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
            local attempts = 0
            local captureFrame = CreateFrame("Frame")
            captureFrame:SetScript("OnUpdate", function(self)
                attempts = attempts + 1
                local cL, cT = blizzFrame:GetLeft(), blizzFrame:GetTop()
                local cR, cB = blizzFrame:GetRight(), blizzFrame:GetBottom()
                if cL and cT and cR and cB and (cR - cL) > 1 then
                    local cS = blizzFrame:GetEffectiveScale()
                    local uS = UIParent:GetEffectiveScale()
                    local uiW, uiH = UIParent:GetSize()
                    local ccx = (cL + cR) * 0.5 * cS / uS - uiW / 2
                    local ccy = (cT + cB) * 0.5 * cS / uS - uiH / 2
                    EAB.db.profile.barPositions[barKey] = {
                        point = "CENTER", relPoint = "CENTER", x = ccx, y = ccy,
                    }
                    holder:ClearAllPoints()
                    holder:SetPoint("CENTER", UIParent, "CENTER", ccx, ccy)
                    self:SetScript("OnUpdate", nil)
                elseif attempts > 300 then
                    self:SetScript("OnUpdate", nil)
                end
            end)
        end
    end

    -- QueueStatusButton: reparent to UIParent so micro menu visibility
    -- (mouseover/combat hide) doesn't affect the eye. Remove from layout
    -- so micro menu doesn't shift. Hook UpdatePosition to prevent snap-back.
    if barKey == "QueueStatus" then
        SafeEnableMouse(holder, false)

        -- Remove from MicroMenuContainer layout flow (no micro menu shift)
        blizzFrame.ignoreInLayout = true
        if blizzFrame.SetIsLayoutFrame then
            blizzFrame:SetIsLayoutFrame(false)
        end
        blizzFrame.IsLayoutFrame = nil

        -- Reparent to UIParent (independent of micro menu visibility)
        local function EnsureQueueParent()
            if blizzFrame:GetParent() ~= UIParent and not InCombatLockdown() then
                blizzFrame:SetParent(UIParent)
                if MicroMenuContainer and MicroMenuContainer.Layout then
                    C_Timer_After(0, function()
                        if MicroMenuContainer and MicroMenuContainer.Layout then
                            MicroMenuContainer:Layout()
                        end
                    end)
                end
            end
        end
        EnsureQueueParent()

        local function SyncQueueHolderSize()
            local fw, fh = blizzFrame:GetWidth(), blizzFrame:GetHeight()
            if fw and fw > 1 and fh and fh > 1 then
                holder:SetSize(fw, fh)
            end
        end

        -- On WoW Forever the eye is an Edit Mode system whose SetPoint and
        -- ClearAllPoints are Blizzard overrides that flag Edit Mode's anchor
        -- pass (tainted from here); the saved base methods move it cleanly.
        local function RepositionQueue()
            local clear = blizzFrame.ClearAllPointsBase or blizzFrame.ClearAllPoints
            local setPt = blizzFrame.SetPointBase or blizzFrame.SetPoint
            clear(blizzFrame)
            setPt(blizzFrame, "CENTER", holder, "CENTER", 0, 0)
        end

        RepositionQueue()
        SyncQueueHolderSize()
        blizzFrame:HookScript("OnSizeChanged", SyncQueueHolderSize)

        -- Prevent Blizzard from snapping the eye back or reparenting away
        local _upGuard = false
        local function Repin()
            if _upGuard then return end
            _upGuard = true
            RepositionQueue()
            EnsureQueueParent()
            _upGuard = false
        end
        if type(blizzFrame.UpdatePosition) == "function" then
            hooksecurefunc(blizzFrame, "UpdatePosition", Repin)
        end
        -- WoW Forever: the eye is an Edit Mode system with no UpdatePosition.
        -- Blizzard re-anchors it through UpdateDefaultAnchor (its own layout
        -- apply, the micro menu's anchor, drag and settings) and, through a
        -- callback that holds the unhooked function, on a Minimap size change.
        if EllesmereUI.IS_FOREVER then
            if type(blizzFrame.UpdateDefaultAnchor) == "function" then
                hooksecurefunc(blizzFrame, "UpdateDefaultAnchor", Repin)
            end
            if MinimapCluster and type(MinimapCluster.SetEditModeScale) == "function" then
                hooksecurefunc(MinimapCluster, "SetEditModeScale", function()
                    ns.AB_ForeverEyeRelayout()
                    Repin()
                end)
            end
        end

        -- Recover from external Hide() calls (other addons, stale state).
        -- When Blizzard updates the queue display, re-check parent and
        -- force Show() if the player is actually in a queue.
        if type(blizzFrame.UpdateDisplay) == "function" then
            hooksecurefunc(blizzFrame, "UpdateDisplay", function()
                EnsureQueueParent()
            end)
        end

        -- Safety net: on LFG_UPDATE, re-parent and let Blizzard show the eye
        local queueWatcher = ns.TakeShell()
        queueWatcher:RegisterEvent("LFG_UPDATE")
        queueWatcher:RegisterEvent("LFG_QUEUE_STATUS_UPDATE")
        queueWatcher:RegisterEvent("LFG_ROLE_CHECK_UPDATE")
        queueWatcher:RegisterEvent("LFG_PROPOSAL_UPDATE")
        queueWatcher:SetScript("OnEvent", function()
            EnsureQueueParent()
            RepositionQueue()
        end)

        return holder
    end
    -- All current extra bars (MicroBar, BagBar, QueueStatus) return above;
    -- nothing reaches here.
end

local function SetupExtraBarHolders()
    for _, info in ipairs(EXTRA_BARS) do
        if not info.isDataBar and not info.isBlizzardMovable and info.frameName then
            SetupExtraBarHolder(info.key, info.frameName, info)
        end
    end
end

local function RegisterExtraBarsWithUnlockMode()
    if not EllesmereUI or not EllesmereUI.RegisterUnlockElements then return end
    local MK = EllesmereUI.MakeUnlockElement
    local elements = {}
    local orderBase = 350
    for idx, info in ipairs(EXTRA_BARS) do
        if not info.isDataBar and not info.isBlizzardMovable and info.frameName then
            local bk = info.key
            -- MicroBar, BagBar: position fully owned by Blizzard Edit Mode.
            -- Skip unlock registration entirely.
            if bk == "MicroBar" or bk == "BagBar" then
                -- no-op: visibility-only holder, no unlock mover
            else
            local isBlizzOwned = (bk == "QueueStatus")
            elements[#elements + 1] = MK({
                key   = bk,
                label = info.label,
                group = "Action Bars",
                order = orderBase + idx,
                noResize = true,
                noAnchorTo = isBlizzOwned,
                noAnchorTarget = isBlizzOwned,
                isHidden = function()
                    local s = EAB.db.profile.bars[bk]
                    if not s then return false end
                    local ov = EAB._visOverride and EAB._visOverride[bk]
                    if ov then return ov == "never" end
                    return s.alwaysHidden
                end,
                getFrame = function() return extraBarHolders[bk] end,
                getSize = function()
                    local holder = extraBarHolders[bk]
                    if holder then return holder:GetWidth(), holder:GetHeight() end
                    return 200, 40
                end,
                savePos = function(_, point, relPoint, x, y)
                    if point and x and y then
                        EAB.db.profile.barPositions[bk] = {
                            point = point, relPoint = relPoint or point, x = x, y = y,
                        }
                    end
                    if not EllesmereUI._unlockActive then
                        local holder = extraBarHolders[bk]
                        if holder and point and x and y then
                            holder:ClearAllPoints()
                            holder:SetPoint(point, UIParent, relPoint or point, x, y)
                        end
                    end
                end,
                loadPos = function()
                    local pos = EAB.db.profile.barPositions[bk]
                    if not pos then return nil end
                    return { point = pos.point, relPoint = pos.relPoint or pos.point, x = pos.x, y = pos.y }
                end,
                clearPos = function()
                    EAB.db.profile.barPositions[bk] = nil
                end,
                applyPos = function()
                    local pos = EAB.db.profile.barPositions[bk]
                    local holder = extraBarHolders[bk]
                    if not holder then return end
                    -- MicroBar/BagBar: Blizzard owns position, never move
                    if bk == "MicroBar" or bk == "BagBar" then return end
                    holder:ClearAllPoints()
                    if pos and pos.point then
                        holder:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
                    elseif not (bk == "QueueStatus" and ns.AB_ForeverEyePark(holder)) then
                        holder:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
                    end
                end,
            })
            end -- else (not MicroBar/BagBar)
        end
    end
    EllesmereUI:RegisterUnlockElements(elements, "EllesmereUIActionBars")
end


-------------------------------------------------------------------------------
--  Extra Bars (MicroBar, BagBar) visibility-only management
--  These use Blizzard's existing frames, we just manage visibility.
-------------------------------------------------------------------------------
local function SetupExtraBars()
    if not EAB.db then return end

    -- Setup Blizzard movable frames (Extra Action Button, Encounter Bar)
    SetupBlizzardMovableFrames()

    -- Setup extra bar holders (MicroBar, BagBar) for visibility/mouseover
    SetupExtraBarHolders()

    for _, info in ipairs(EXTRA_BARS) do
        if not info.isDataBar and not info.isBlizzardMovable then
            local blizzFrame = _G[info.frameName]
            if blizzFrame then
                local s = EAB.db.profile.bars[info.key]
                if s then
                    local holder = extraBarHolders[info.key]
                    if s.alwaysHidden and not info.blizzOwnedVisibility then
                        blizzFrame:Hide()
                        if holder then holder:Hide() end
                    end
                    AttachExtraBarHoverHooks(info)
                end
            end
        end  -- not isDataBar/isBlizzardMovable
    end

    _quickKeybindState.art.ForEachSpecialButton(_quickKeybindState.art.InitializeButton)

    -- Register extra bars with unlock mode
    if EllesmereUI and EllesmereUI.RegisterUnlockElements then
        RegisterExtraBarsWithUnlockMode()
    else
        C_Timer_After(1, function()
            if EllesmereUI and EllesmereUI.RegisterUnlockElements then
                RegisterExtraBarsWithUnlockMode()
            end
        end)
    end

    -- Setup data bars (XP, Rep)
    SetupDataBars()

    -- Apply correct initial alpha now that holders exist.
    -- RefreshMouseover ran at OnEnable before holders were created, so
    -- bars with mouseoverEnabled never got their alpha set to 0.
    EAB:RefreshMouseover()
end

-- Setup extra bars after a short delay to ensure frames exist
local extraBarFrame = CreateFrame("Frame")
extraBarFrame:RegisterEvent("PLAYER_LOGIN")
extraBarFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    C_Timer_After(0.5, SetupExtraBars)
end)


ns.AttachExtraBarHoverHooks = AttachExtraBarHoverHooks -- called by the main file
