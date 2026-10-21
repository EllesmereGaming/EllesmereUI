if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_ActionBars_ExtraBars.lua
--
--  Blizzard movable frames (the Extra Action Button), the holders for the
--  Micro Menu and Bag Bar, and the extra bars setup. Loads after
--  EUI_ActionBars_DataBars.lua and reads the main file through ns only.
-------------------------------------------------------------------------------
local _, ns = ...

local _G = _G
local ipairs, type = ipairs, type
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
--  Blizzard Movable Frames (Extra Action Button): a non-secure holder frame
--  that ExtraAbilityContainer is reparented into, kept out of Blizzard's
--  bottom managed column so unlock mode can place it freely. The Encounter
--  Bar stays Blizzard's (Edit Mode owns its position).
--  Overlay sizes are hardcoded (don't affect actual Blizzard frame rendering).
-------------------------------------------------------------------------------
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

    -- Reparent all managed frames into the holder, centered. Safe to call
    -- multiple times. In combat the move waits for combat to end, queued
    -- once per bar however many asks; until then a container Blizzard
    -- parented into its bottom managed column is laid out in its own slot.
    local reparentKey = "BlizzMovableReparent" .. barKey
    local function ReparentIntoHolder()
        if InCombatLockdown() then
            ns.CombatQueue.Defer(reparentKey, ReparentIntoHolder)
            return
        end
        for _, f in ipairs(extraFrames) do
            f:SetParent(holder)
            -- ExtraAbilityContainer is an Edit Mode system: base methods only.
            EllesmereUI.ClearFramePoints(f)
            EllesmereUI.SetFramePoint(f, "CENTER", holder, "CENTER", 0, 0)
        end
    end

    -- Extra Action Button: disable the container's layout-driven repositioning and
    -- reparent it into our holder. Keep OnShow/OnHide cleared on the container so
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

        -- CLAUDE.md exception to the never-SetScript rule: these handlers are
        -- cleared, never hooked. The OnShow parents the container into the
        -- bottom managed column, also in combat when an extra or zone ability
        -- appears, and the re-park waits for combat to end (the extra button
        -- makes the container protected); our holder's Show/Hide would also
        -- run both handlers inside our call, tainting the column's
        -- managed-frame state. A cleared handler runs no code.
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
            EllesmereUI.ClearFramePoints(container)
            EllesmereUI.SetFramePoint(container, "CENTER", holder, "CENTER", 0, 0)
        end
        RepositionExtraContainer()

        -- Re-reparent when Edit Mode tries to reposition the container.
        if ExtraAbilityContainer.ApplySystemAnchor then
            hooksecurefunc(ExtraAbilityContainer, "ApplySystemAnchor", function()
                local _, relFrame = ExtraAbilityContainer:GetPoint()
                if relFrame ~= holder then
                    RepositionExtraContainer()
                end
                -- Do NOT write to BottomManagedFrameContainer.showingFrames here.
                -- Writing into that Blizzard-owned table from this insecure hook
                -- taints the managed-frame-position system; a later in-combat layout
                -- pass (e.g. leaving a queued/follower instance while in combat) then
                -- blocks the protected ClearAllPoints on the managed containers
                -- (ADDON_ACTION_BLOCKED naming this addon). The container stays out
                -- of Blizzard's layout without it: its OnShow is cleared above, and
                -- the SetParent hook below moves it back into the holder whenever
                -- Blizzard parents it into the column (in combat, once combat ends).
            end)
        end

        -- Re-reparent if the container shows outside the holder. (Its OnShow
        -- script is cleared above; this method hook still fires on Show.)
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

-- Re-disable mouse on ExtraActionBarFrame after every combat: Blizzard's
-- secure code re-enables mouse on protected frames during combat.
local _blizzMovableCombatFrame = CreateFrame("Frame")
_blizzMovableCombatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
_blizzMovableCombatFrame:SetScript("OnEvent", function()
    if InCombatLockdown() then return end
    if ExtraActionBarFrame and ExtraActionBarFrame:IsMouseEnabled() then
        ExtraActionBarFrame:EnableMouse(false)
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
-- queue eye sits at a minimap spot and is never captured: the one the
-- minimap's spot helper gives while it answers (on the ring where Blizzard's
-- Forever layout puts it while the minimap draws that ring, or diagonally
-- off the map's bottom-left corner under Forever Square), else Blizzard's
-- Forever layout anchor on the map. Anchored to the map, so a move carries
-- it; the minimap's apply pass calls the relayout below on a resize, and a
-- button row starting at the ring's bottom-left reads the predicate to start
-- past the eye. An unlock-mode drag saves a position, which wins until the
-- look changes (every switch to the variant clears it). Once per profile,
-- while the spot helper answers, a spot saved before the variant placed the
-- eye (a login capture) gives way; the stamp is set as soon as nothing is
-- saved, so every later spot is the player's own.
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

-- Blizzard Style on the WoW Forever client: that client frames the micro menu
-- (MicroMenu.BackgroundArt and BorderArt) and the bag bar (the BagsBar frame
-- and strip atlases), which the retail look has none of, so they fade, as the
-- Blizzard Skins+ cards fade them when they skin these bars. Alpha only on
-- Blizzard's own textures: nothing is hidden, reparented, hooked or written
-- as a key in that tree. Run with each bar's follow pass (setup, Edit Mode
-- re-anchors and resizes); the bag bar's art is found once. The WoW Forever
-- look keeps the art.
local FV_BAG_ART = { "actionbar-frame", "iconframe-background" }
local fvBagArt
local function FadeForeverBarArt(barKey)
    if not (EllesmereUI.IS_FOREVER and ns.AB_Style() == "blizzard" and not ns.AB_Forever()) then return end
    if barKey == "MicroBar" then
        local mm = _G.MicroMenu
        if mm and mm.BackgroundArt then mm.BackgroundArt:SetAlpha(0) end
        if mm and mm.BorderArt then mm.BorderArt:SetAlpha(0) end
        return
    end
    local bar = _G.BagsBar
    if not bar then return end
    if not fvBagArt then
        fvBagArt = {}
        local regions = { bar:GetRegions() }
        for i = 1, #regions do
            local r = regions[i]
            local atlas = r.GetAtlas and r:GetAtlas()
            if atlas then
                local la = atlas:lower()
                for j = 1, #FV_BAG_ART do
                    if la:find(FV_BAG_ART[j], 1, true) then fvBagArt[#fvBagArt + 1] = r; break end
                end
            end
        end
    end
    for i = 1, #fvBagArt do fvBagArt[i]:SetAlpha(0) end
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
            FadeForeverBarArt(barKey)
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
    -- (mouseover/combat hide) doesn't affect the eye. Hook UpdatePosition to
    -- prevent snap-back.
    if barKey == "QueueStatus" then
        SafeEnableMouse(holder, false)

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
            EllesmereUI.ClearFramePoints(blizzFrame)
            EllesmereUI.SetFramePoint(blizzFrame, "CENTER", holder, "CENTER", 0, 0)
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

    -- Setup Blizzard movable frames (Extra Action Button)
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


ns.AttachExtraBarHoverHooks = AttachExtraBarHoverHooks -- called by EUI_ActionBars_Fade.lua
