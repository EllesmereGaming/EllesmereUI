-------------------------------------------------------------------------------
-- Optional chat host. No frames, events or hooks until explicitly enabled.
-- Placement ownership is shared with the meter module, never inferred from
-- settings/edit-mode visibility. Only disabling the feature releases live meters.
-------------------------------------------------------------------------------
local _, ns = ...
local EUI = EllesmereUI
if not (EUI and ns.EDM) then return end
local Host = {}
Host.__index = Host

local function Selected()
    return GENERAL_CHAT_DOCK and FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
end

local function SaveFrame(f)
    local points = {}
    for i = 1, f:GetNumPoints() do points[i] = { f:GetPoint(i) } end
    return { parent = f:GetParent(), points = points, width = f:GetWidth(), height = f:GetHeight(),
        scale = f:GetScale(), strata = f:GetFrameStrata(), level = f:GetFrameLevel(),
        alpha = f:GetAlpha(), shown = f:IsShown(), clamped = f:IsClampedToScreen() }
end

local function RestoreFrame(f, saved)
    f:SetParent(saved.parent)
    f:SetScale(saved.scale)
    f:SetFrameStrata(saved.strata)
    f:SetFrameLevel(saved.level)
    f:SetClampedToScreen(saved.clamped)
    f:ClearAllPoints()
    for _, point in ipairs(saved.points) do f:SetPoint(unpack(point)) end
    f:SetSize(saved.width, saved.height)
    f:SetAlpha(saved.alpha)
    f:SetShown(saved.shown)
end

function Host:PaintIcon()
    local cfg = self.chat.ECHAT.DB()
    local r, g, b = cfg.iconR or 1, cfg.iconG or 1, cfg.iconB or 1
    if self.active or cfg.iconUseAccent then r, g, b = EUI.GetAccentColor() end
    local alpha = (self.active or self.hovered) and 0.9 or 0.4
    if self.iconR == r and self.iconG == g and self.iconB == b and self.iconAlpha == alpha then return end
    self.iconR, self.iconG, self.iconB, self.iconAlpha = r, g, b, alpha
    for _, line in ipairs(self.button.lines) do line:SetColorTexture(r, g, b, alpha) end
end

function Host:Build()
    self.root = CreateFrame("Frame", nil, UIParent)
    self.root:Hide()
    self.body = CreateFrame("Frame", nil, self.root)
    self.body:EnableMouse(true)
    self.body:EnableMouseWheel(true)
    self.body:SetScript("OnMouseWheel", function() end)
    self.body:Hide()
    self.body:SetScript("OnSizeChanged", function() self:LayoutMeters() end)
    self.parking = CreateFrame("Frame", nil, self.root)
    self.parking:Hide()
    self.waiting = self.body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.waiting:SetPoint("CENTER")
    self.waiting:SetText(EllesmereUI.L("Create Damage Done and Healing Done windows to embed them here."))

    local button = CreateFrame("Button", nil, UIParent)
    self.button = button
    button:SetSize(22, 22)
    button:Hide()
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button.lines = {}
    for i, height in ipairs({ 7, 15, 11 }) do
        local x = 3 + (i - 1) * 6
        for _, edge in ipairs({ {x, 3, 4, 1}, {x, height + 2, 4, 1},
            {x, 3, 1, height}, {x + 3, 3, 1, height} }) do
            local line = button:CreateTexture(nil, "ARTWORK")
            line:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", edge[1], edge[2])
            line:SetSize(edge[3], edge[4])
            line.box = edge
            button.lines[#button.lines + 1] = line
        end
    end
    button:SetScript("OnSizeChanged", function(_, width)
        local scale = width / 22
        for _, line in ipairs(button.lines) do
            local box = line.box
            line:ClearAllPoints()
            line:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", box[1] * scale, box[2] * scale)
            line:SetSize(box[3] * scale, box[4] * scale)
        end
    end)
    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then EUI:ShowModule("EllesmereUIDamageMeters")
        else self:SetActive(not self.active) end
    end)
    button:SetScript("OnEnter", function()
        self.hovered = true
        self:PaintIcon()
        EUI.ShowWidgetTooltip(button, "Meters\nLeft-click: switch chat / meters\nRight-click: Damage Meters settings")
    end)
    button:SetScript("OnLeave", function()
        self.hovered = false
        self:PaintIcon()
        EUI.HideWidgetTooltip()
    end)

    self.events = CreateFrame("Frame")
    self.events:SetScript("OnEvent", function(_, event, mouseButton)
        if event == "GLOBAL_MOUSE_DOWN" then
            if mouseButton ~= "LeftButton" then return end
            -- Hardware-click observation only; native docking/tab scripts stay intact.
            for _, cf in ipairs(GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES) do
                local tab = _G[cf:GetName() .. "Tab"]
                if tab and tab:IsShown() and MouseIsOver(tab) and not MouseIsOver(button) then
                    self:SetActive(false)
                    return
                end
            end
        else
            self:CheckZone()
            self:BindPanel()
        end
    end)
end

function Host:LayoutMeters()
    if not self.enabled then return end
    local width, height = self.body:GetWidth(), self.body:GetHeight()
    if not width or not height or issecretvalue(width) or issecretvalue(height)
        or width <= 8 or height <= 4 then return end
    local meterWidth = (width - 6) / 2
    for i = 1, 2 do
        local w
        if i == 1 then w = self.left else w = self.right end
        if w then
            local f = w.frame
            -- The anchors are installed on adoption; only sizes change here.
            if f:GetWidth() ~= meterWidth or f:GetHeight() ~= height - 2 then
                f:SetSize(meterWidth, height - 2)
                w.FitTitle()
            end
        end
    end
end

function Host:BindPanel()
    if not self.enabled then return end
    local chat, selected = self.chat, Selected()
    if self.active and selected ~= self.selected then self:SetActive(false) end
    local data = selected and EUI._chatCFD(selected)
    local panel = data and data.bg
    if not panel or chat.ECHAT.DB().enabled == false then
        self.root:Hide()
        return
    end
    if self.root:GetParent() ~= panel then
        self.root:SetParent(panel)
        self.root:ClearAllPoints()
        self.root:SetAllPoints(panel)
        self.root:SetFrameLevel(panel:GetFrameLevel() + 20)
    end
    local sidebar = EUI._chatCFD(ChatFrame1).sidebar
    if sidebar and self.button:GetParent() ~= sidebar then chat.ECHAT.ApplySidebarIcons() end
    local cfg = chat.ECHAT.DB()
    local ins = data._bgIns
    local top = 2 + (data._smfTopExtra or 0)
    local bottom = cfg.inputOnTop and 2 or math.max(2, -((ins and ins.b) or -6) - 8)
    if self.top ~= top or self.bottom ~= bottom then
        self.top, self.bottom = top, bottom
        self.body:ClearAllPoints()
        self.body:SetPoint("TOPLEFT", self.root, "TOPLEFT", 1, -top)
        self.body:SetPoint("BOTTOMRIGHT", self.root, "BOTTOMRIGHT", -1, bottom)
    end
    local shown = not chat._chatStackHidden and not chat._chatPassthrough
    if self.root:IsShown() ~= shown then self.root:SetShown(shown) end
    self.body:SetShown(self.active == true)
    self:PaintIcon()
end

function Host:SetActive(on)
    on = on == true and self.enabled == true
    if self.active == on then return end
    self.active = on
    self.selected = on and Selected() or nil
    self.chat.ECHAT.SetMetersView(on and self.selected or nil)
    if on then self.events:RegisterEvent("GLOBAL_MOUSE_DOWN")
    else self.events:UnregisterEvent("GLOBAL_MOUSE_DOWN") end
    self.body:SetShown(on)
    self:BindPanel()
    self:PaintIcon()
    if self.chat.ECHAT.ResetIdleTimer then self.chat.ECHAT.ResetIdleTimer() end
    if on then
        if self.left then self.left.Refresh() end
        if self.right then self.right.Refresh() end
    end
end

function Host:Attach(w, slot)
    if not w or w._chatHost then return end
    local f = w.frame
    local saved = SaveFrame(f)
    saved.resizeGrip = SaveFrame(w.resizeGrip)
    saved.lockBtn = SaveFrame(w.lockBtn)
    saved.bodyAlpha = f._bg:GetAlpha()
    saved.headerAlpha = w.header._hdrBg:GetAlpha()
    self.records[w] = saved
    w._chatHost = self
    w.resizeGrip:SetParent(self.parking)
    w.lockBtn:SetParent(self.parking)
    f._bg:SetAlpha(0)
    w.header._hdrBg:SetAlpha(0)
    f:SetParent(self.body)
    f:SetScale(1)
    f:SetFrameStrata(self.body:GetFrameStrata())
    f:SetFrameLevel(self.body:GetFrameLevel() + 1)
    f:SetClampedToScreen(false)
    f:ClearAllPoints()
    if slot == 1 then f:SetPoint("TOPLEFT", self.body, "TOPLEFT", 1, -1)
    else f:SetPoint("TOPLEFT", self.body, "TOP", 2, -1) end
    f:SetAlpha(1)
    f:Show()
    EUI._unlockRegistrationDirty = true
    return true
end

function Host:Retire(w)
    local saved = self.records[w]
    if saved then
        -- Retired controls belong with their discarded window, not in the
        -- long-lived parking frame used by the next profile's meters.
        RestoreFrame(w.resizeGrip, saved.resizeGrip)
        RestoreFrame(w.lockBtn, saved.lockBtn)
    end
    self.records[w] = nil
    w._chatHost = nil
    if self.left == w then self.left = nil end
    if self.right == w then self.right = nil end
end

function Host:SyncWindows()
    for _, w in ipairs(ns._windows) do
        if not self.left and w ~= self.right and w.curDMType == Enum.DamageMeterType.DamageDone then self.left = w end
        if not self.right and w ~= self.left and w.curDMType == Enum.DamageMeterType.HealingDone then self.right = w end
    end
    local attachedLeft = self:Attach(self.left, 1)
    local attachedRight = self:Attach(self.right, 2)
    -- Mouseover visibility caches its predicate; ownership changes invalidate it.
    if (attachedLeft or attachedRight) and EUI.RequestVisibilityUpdate then EUI.RequestVisibilityUpdate() end
    self:LayoutMeters()
    self.waiting:SetShown(not self.left and not self.right)
end

function Host:CheckZone()
    local inside, kind = IsInInstance()
    local _, _, _, _, _, _, _, id = GetInstanceInfo()
    if self.zoneKind == kind and self.zoneID == id then return end
    local wasInstance = self.zoneKind == "party" or self.zoneKind == "raid"
    self.zoneKind, self.zoneID = kind, id
    local cfg = ns.EDM.DB()
    if inside and ((kind == "party" and cfg.chatEmbedAutoDungeon) or (kind == "raid" and cfg.chatEmbedAutoRaid)) then
        self:SetActive(true)
    elseif wasInstance and kind ~= "party" and kind ~= "raid" and cfg.chatEmbedReturnOnExit then
        self:SetActive(false)
    end
end

function Host:Enable()
    self.enabled = true
    self.chat._metersSidebarButton = self.button
    self.chat._onMetersHostChanged = function() self:BindPanel() end
    self.chat._onMetersStyleChanged = function()
        local size = 22 * (self.chat.ECHAT.DB().sidebarIconScale or 1)
        self.button:SetSize(size, size)
        self:PaintIcon()
    end
    self.chat._onMetersSelectionChanged = function(selected)
        if self.active and selected ~= self.selected then self:SetActive(false) end
        self:BindPanel()
    end
    self.events:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    self.chat.ECHAT.ApplySidebarIcons()
    self:BindPanel()
    self:SyncWindows()
    self:CheckZone()
end

function Host:Disable()
    self:SetActive(false)
    self.enabled = false
    self.events:UnregisterAllEvents()
    self.chat._metersSidebarButton = nil
    self.chat._onMetersHostChanged = nil
    self.chat._onMetersStyleChanged = nil
    self.chat._onMetersSelectionChanged = nil
    self.chat.ECHAT.ApplySidebarIcons()
    self.button:Hide()
    self.root:Hide()
    for w, saved in pairs(self.records) do
        w._chatHost = nil
        RestoreFrame(w.frame, saved)
        RestoreFrame(w.resizeGrip, saved.resizeGrip)
        RestoreFrame(w.lockBtn, saved.lockBtn)
        w.frame._bg:SetAlpha(saved.bodyAlpha)
        w.header._hdrBg:SetAlpha(saved.headerAlpha)
        w.ApplyPosition()
        w.UpdateVisibility()
        w.FitTitle()
        w.Refresh()
        self.records[w] = nil
    end
    self.left, self.right, self.zoneKind, self.zoneID = nil, nil, nil, nil
    EUI._unlockRegistrationDirty = true
    if EUI.RequestVisibilityUpdate then EUI.RequestVisibilityUpdate() end
end

function ns.ApplyChatMeters()
    local host = ns._chatMeters
    if not ns.EDM.DB().chatEmbedEnabled then
        if host and host.enabled then host:Disable() end
        return
    end
    local chat = EUI._ModuleNS.EllesmereUIChat
    if not (chat and chat.ECHAT.SetMetersView) then return end
    if not host then
        host = setmetatable({ chat = chat, records = {} }, Host)
        ns._chatMeters = host
        host:Build()
    end
    if not host.enabled then host:Enable()
    else host:BindPanel(); host:SyncWindows() end
end
