if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- Nine-point picking lives on movers; gameplay frames receive no mouse hooks.
local _, ns = ...
ns = ns.__euiCoreNS or ns
ns.unlockParts = ns.unlockParts or {}
ns.unlockParts.PointPicker = function(UM)
    local PA = ns.PointAnchors
    local visuals = ns.PointVisuals
    UM.PointVisuals = visuals
    local picker = {}
    UM.PointPicker = picker
    local sourceSet, targetSet, sourcePoint

    local function Enabled()
        return EllesmereUIDB and EllesmereUIDB.unlockPointHandles == true
    end

    local function Reject(mover, message)
        UM.FlashRedBorder(mover)
        UM.RejectH.ShowTooltip(message)
    end

    local function Eligible(mover, source)
        if not mover or not mover:IsShown() or mover._tempHidden then return false end
        local key = mover._barKey
        local elem = UM.registeredElements[key]
        if not elem or EllesmereUI.IsScreenEdgeKey(key) then return false end
        if source then
            if elem.noAnchorTo or elem.ownsPosition or ns.IsMoverPosLocked(key) then return false end
            if elem.isAnchored and elem.isAnchored(key) then return false end
        elseif elem.noAnchorTarget then
            return false
        end
        return PA.Rect(key, UM.GetBarFrame(key)) ~= nil
    end

    local function FrameDependsOn(frame, wanted, seen, depth)
        if frame == wanted then return true end
        if not frame or frame == UIParent or seen[frame] then return false end
        if depth > 30 then return true end
        seen[frame] = true
        local ok, count = pcall(frame.GetNumPoints, frame)
        if not ok or (issecretvalue and issecretvalue(count)) or type(count) ~= "number" then return true end
        for i = 1, count do
            local plain, _, relative = pcall(frame.GetPoint, frame, i)
            if not plain or (issecretvalue and issecretvalue(relative)) then return true end
            if relative and FrameDependsOn(relative, wanted, seen, depth + 1) then return true end
        end
        return false
    end

    local function CanLink(source, target)
        if not Eligible(source, true) or not Eligible(target, false) then return false end
        local childKey, targetKey = source._barKey, target._barKey
        local childFrame = UM.GetBarFrame(childKey)
        if childKey == targetKey or FrameDependsOn(UM.GetBarFrame(targetKey), childFrame, {}, 0) then return false end
        local seen, stack = {}, { targetKey }
        while #stack > 0 do
            local key = table.remove(stack)
            if key == childKey or UM.GetBarFrame(key) == childFrame then return false end
            if not seen[key] then
                seen[key] = true
                local info = UM.GetAnchorInfo(key)
                if info and info.target then stack[#stack + 1] = info.target end
                if info and info.fallback and info.fallback.target then stack[#stack + 1] = info.fallback.target end
                local overrides = EllesmereUI._OverrideAnchorTargets and EllesmereUI._OverrideAnchorTargets(key)
                if overrides then
                    for i = 1, #overrides do stack[#stack + 1] = overrides[i] end
                end
            end
        end
        return true
    end

    local function UpdateDot(button, animate)
        local size = (button.hovered or button.selected) and button.hoverSize or button.idleSize
        local current = button.art:GetWidth()
        if animate and button.animation:IsPlaying() then
            local progress = button.scaleAnimation:GetSmoothProgress()
            current = button.fromSize + (button.toSize - button.fromSize) * progress
        end
        button.animation:Stop()
        visuals.SizeDot(button.art, size)
        visuals.ColorDot(button.art, (button.hovered or button.selected) and 1 or 0.8)
        if animate and math.abs(current - size) > 0.01 then
            button.fromSize, button.toSize = current, size
            button.scaleAnimation:SetScaleFrom(current / size, current / size)
            button.animation:Play()
        end
    end

    local function Choose(set, point)
        if not UM.isUnlocked or InCombatLockdown() or not Enabled() then return end
        local source = UM.pickModeMover
        if set == sourceSet and UM.pickMode == "anchorTo" then
            if not Eligible(source, true) then UM.CancelPickMode(); return end
            sourcePoint = point
            UM.pickMode = "pointAnchor"
            for _, button in ipairs(sourceSet.buttons) do
                button.selected = button.point == point
                UpdateDot(button, false)
                button:SetShown(button.point == point)
                button:EnableMouse(false)
            end
            if source._showPickText then source._showPickText(EllesmereUI.L("Click a point on another element")) end
            return
        end
        if set ~= targetSet or UM.pickMode ~= "pointAnchor" or not sourcePoint then return end
        local target = set.mover
        if not CanLink(source, target) then
            Reject(target, EllesmereUI.L("This point anchor is unavailable or would create a circular anchor"))
            return
        end
        local childKey, targetKey = source._barKey, target._barKey
        local info = { mode = "POINT", target = targetKey, sourcePoint = sourcePoint,
            targetPoint = point, offsetX = 0, offsetY = 0 }
        if not PA.Center(childKey, UM.GetBarFrame(childKey), info, UM.GetBarFrame(targetKey)) then
            Reject(target, EllesmereUI.L("This element's position is not available yet"))
            return
        end
        UM.CancelPickMode()
        UM.SetAnchorInfo(childKey, targetKey, nil, 0, 0)
        local stored = UM.GetAnchorInfo(childKey)
        stored.mode, stored.sourcePoint, stored.targetPoint = "POINT", info.sourcePoint, info.targetPoint
        stored.edge = nil -- An explicit point owns both axes of the new relationship.
        UM.hasChanges = true
        UM.ApplyAnchorPosition(childKey, targetKey)
        if source.RefreshAnchoredText then source:RefreshAnchoredText() end
        UM.DeferMoverSync(source, function(m) m:Sync() end, UM.GetBarFrame(childKey))
        C_Timer.After(0, function() UM.PropagateAnchorChain(childKey) end)
    end

    local function Layout(set)
        local w, h = set:GetSize()
        local px = UM.PP.perfect / set:GetEffectiveScale()
        local hit = math.max(px, math.min(12 * px, w / 3, h / 3))
        local idle, hover = math.min(visuals.idleSize * px, hit), visuals.hoverSize * px
        for _, button in ipairs(set.buttons) do
            button:SetSize(hit, hit)
            if button.idleSize ~= idle or button.hoverSize ~= hover then
                button.idleSize, button.hoverSize = idle, hover
                UpdateDot(button, false)
            end
        end
    end

    local function CreateSet()
        local set = CreateFrame("Frame", nil, UM.unlockFrame)
        set:EnableMouse(false)
        set.buttons = {}
        local labels = {
            TOPLEFT = EllesmereUI.L("Top Left"), TOP = EllesmereUI.L("Top"), TOPRIGHT = EllesmereUI.L("Top Right"),
            LEFT = EllesmereUI.L("Left"), CENTER = EllesmereUI.L("Center"), RIGHT = EllesmereUI.L("Right"),
            BOTTOMLEFT = EllesmereUI.L("Bottom Left"), BOTTOM = EllesmereUI.L("Bottom"), BOTTOMRIGHT = EllesmereUI.L("Bottom Right"),
        }
        for _, point in ipairs(PA.order) do
            local button = CreateFrame("Button", nil, set)
            button.point = point
            button.idleSize, button.hoverSize = visuals.idleSize, visuals.hoverSize
            button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            local art = visuals.CreateDot(button)
            visuals.SizeDot(art, visuals.idleSize)
            art:SetPoint("CENTER", button, "CENTER")
            button.art = art
            visuals.ColorDot(art, 0.8)
            button.dot = art.fill
            button.animation = art:CreateAnimationGroup()
            button.scaleAnimation = button.animation:CreateAnimation("Scale")
            button.scaleAnimation:SetOrigin("CENTER", 0, 0)
            button.scaleAnimation:SetDuration(0.12)
            button.scaleAnimation:SetSmoothing("OUT")
            button.scaleAnimation:SetScaleTo(1, 1)
            button:SetScript("OnEnter", function()
                button.hovered = true
                set.mover._pointHandleHovered = button
                UpdateDot(button, true)
                EllesmereUI.ShowWidgetTooltip(button, labels[point])
            end)
            button:SetScript("OnLeave", function()
                button.hovered = nil
                if set.mover._pointHandleHovered == button then set.mover._pointHandleHovered = nil end
                UpdateDot(button, true)
                EllesmereUI.HideWidgetTooltip()
                local leave = set.mover:GetScript("OnLeave")
                if leave then leave(set.mover) else picker.Leave(set.mover) end
            end)
            button:SetScript("OnHide", function()
                if button.hovered then EllesmereUI.HideWidgetTooltip() end
                if set.mover and set.mover._pointHandleHovered == button then set.mover._pointHandleHovered = nil end
                button.hovered, button.selected = nil, nil
                UpdateDot(button, false)
            end)
            button:SetScript("OnClick", function(_, mouse)
                EllesmereUI.HideWidgetTooltip()
                if mouse == "RightButton" then UM.CancelPickMode() else Choose(set, point) end
            end)
            set.buttons[#set.buttons + 1] = button
        end
        set:SetScript("OnSizeChanged", Layout)
        return set
    end

    local function Show(set, mover)
        if set.mover ~= mover then set:Hide() end
        set.mover = mover
        set:SetParent(mover)
        visuals.RaiseAboveMover(set, mover)
        set:ClearAllPoints()
        set:SetAllPoints(mover)
        Layout(set)
        for _, button in ipairs(set.buttons) do
            -- Bind after the pooled set has bounds, avoiding unresolved corner handles.
            button:ClearAllPoints()
            button:SetPoint("CENTER", set, button.point, 0, 0)
            local selected = set == sourceSet and button.point == sourcePoint
            if button.selected ~= selected then
                button.selected = selected
                UpdateDot(button, false)
            end
            button:SetShown(set ~= sourceSet or not sourcePoint or button.point == sourcePoint)
            button:EnableMouse(set ~= sourceSet or not sourcePoint)
        end
        set:Show()
    end

    function picker.Point(mover, point)
        -- Mover bounds already include visual insets and hover expansion.
        return PA.Point(nil, mover, point)
    end

    function picker.Begin(mover)
        if not Enabled() or not Eligible(mover, true) then return end
        sourceSet = sourceSet or CreateSet()
        sourcePoint = nil
        Show(sourceSet, mover)
    end

    function picker.Enter(mover)
        if UM.pickMode ~= "pointAnchor" or not sourcePoint or mover == UM.pickModeMover then return end
        if not Eligible(mover, false) then
            if targetSet then targetSet:Hide() end
            return
        end
        targetSet = targetSet or CreateSet()
        Show(targetSet, mover)
    end

    function picker.Leave(mover)
        if not targetSet or targetSet.mover ~= mover or not targetSet:IsShown() then return end
        -- Let the next mouse focus settle when crossing onto an edge handle.
        C_Timer.After(0, function()
            if targetSet.mover == mover and not mover:IsMouseOver() and not mover._pointHandleHovered then
                targetSet:Hide()
            end
        end)
    end

    function picker.Refresh(mover)
        if not UM.isUnlocked or not UM.pickMode then return end
        if sourceSet and sourceSet.mover == mover and sourceSet:IsShown() then Show(sourceSet, mover) end
        if targetSet and targetSet.mover == mover and targetSet:IsShown() then Show(targetSet, mover) end
    end

    function picker.BodyClick(mover, button)
        if UM.pickMode ~= "pointAnchor" or button ~= "LeftButton" then return false end
        if mover == UM.pickModeMover then UM.CancelPickMode() end
        return true
    end

    function picker.Cancel()
        if sourceSet and sourceSet:IsShown() then EllesmereUI.HideWidgetTooltip() end
        if sourceSet then sourceSet:Hide() end
        if targetSet then targetSet:Hide() end
        sourcePoint = nil
    end

    function picker.Active()
        return sourceSet and sourceSet:IsShown()
    end

    PA.cancelPicker = function()
        if picker.Active() then UM.CancelPickMode() end
    end
end
