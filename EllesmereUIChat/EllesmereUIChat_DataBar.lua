if EUI_CLIENT_BLOCKED then return end
local _, ns = ...
local ECHAT = ns.ECHAT
local EUI = EllesmereUI
local CFD = EUI._chatCFD
local cover, active, busy
local original = {}
local listening, refreshing, queued
local events = CreateFrame("Frame")
local combatQueue = EUI.NewCombatQueue(CreateFrame("Frame"))
local UpdateCover, Configure, RequestRefresh, Restore
local function Enabled()
    local cfg = ECHAT.DB()
    return cfg and cfg.dataBarDock and (not ns.ChatStock() or ns.ChatForever())
end
local function Target()
    local cfg = ECHAT.DB()
    if not cfg or not cfg.dataBarDock or (ns.ChatStock() and not ns.ChatForever()) then return end
    local bars = EUI._ModuleNS.EllesmereUIDataBars
    local bar = bars and bars.GetChatDockBar and bars.GetChatDockBar(cfg.dataBarDockID)
    if not bar or not bar:IsShown() then return end
    local left, bottom, width, height = bar:GetRect()
    if not left or not bottom or not width or not height then return end
    local scale = bar:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return bar, left * scale, bottom * scale, width * scale, height * scale
end
function ECHAT.DataBarDockActive() return Target() ~= nil end

local function Cover()
    if cover then return cover end
    cover = CreateFrame("Frame", nil, UIParent)
    cover:EnableMouse(true)
    local fill = cover:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    fill:SetColorTexture(0.035, 0.035, 0.035, 1)
    cover:Hide()
    return cover
end

function ECHAT.ApplyDataBarInputs()
    local bar, x, y, w, h = Target()
    if not bar then return end
    if InCombatLockdown() then
        combatQueue.Defer("chat-databar", ECHAT.RefreshDataBarDock)
        return
    end
    local panel = Cover()
    panel:ClearAllPoints()
    panel:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
    panel:SetSize(w, h)
    panel:SetFrameStrata(bar:GetFrameStrata())
    panel:SetFrameLevel(bar:GetFrameLevel() + 100)
    for i = 1, 10 do
        local cf = _G["ChatFrame" .. i]
        local eb = _G["ChatFrame" .. i .. "EditBox"]
        if cf and eb and (i == 1 or cf.isDocked) then
            if not original[eb] then
                local points = {}
                for n = 1, eb:GetNumPoints() do points[n] = { eb:GetPoint(n) } end
                original[eb] = { level = eb:GetFrameLevel(), strata = eb:GetFrameStrata(), points = points }
            end
            eb:ClearAllPoints()
            eb:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, 0)
            eb:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -4, 0)
            eb:SetFrameStrata(panel:GetFrameStrata())
            eb:SetFrameLevel(panel:GetFrameLevel() + 1)
            local d = CFD(cf)
            if d.fvIn then d.fvIn:Hide() end
            if d.inputDiv then d.inputDiv:Hide() end
        end
    end
    UpdateCover()
end

function ECHAT.ApplyDataBarDock()
    local bar, x, y, w, h = Target()
    if not bar then return false end
    -- Defer protected geometry changes, retaining the last safe placement.
    if InCombatLockdown() then
        combatQueue.Defer("chat-databar", ECHAT.RefreshDataBarDock)
        return true
    end
    if busy then return true end
    local cf = ChatFrame1
    if not cf or not CFD(cf).anchorGuarded then return false end
    busy = true
    active = true
    local cfg = ECHAT.DB()
    local ins = CFD(cf)._bgIns or { l = -10, r = 10, b = -35 }
    local scale = UIParent:GetEffectiveScale() / cf:GetEffectiveScale()
    local height = cfg.chatSize and cfg.chatSize.h or cf:GetHeight()
    local left = x * scale - (ins.l or 0)
    local bottom = (y + h + 2) * scale - (ins.b or 0)
    local width = w * scale - ((ins.r or 0) - (ins.l or 0))
    if width > 40 then
        -- Numeric anchors avoid adding the protected DataBar to chat's rect chain.
        local p, rel, rp, px, py = cf:GetPoint(1)
        local p2, rel2, rp2, px2, py2 = cf:GetPoint(2)
        if cf:GetNumPoints() ~= 2 or p ~= "BOTTOMLEFT" or rel ~= UIParent
            or rp ~= "BOTTOMLEFT" or px ~= left or py ~= bottom
            or p2 ~= "TOPRIGHT" or rel2 ~= UIParent or rp2 ~= "BOTTOMLEFT"
            or px2 ~= left + width or py2 ~= bottom + height then
            cf:ClearAllPoints()
            cf:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
            cf:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", left + width, bottom + height)
        end
    end
    busy = false
    return true
end

Restore = function()
    for eb, saved in pairs(original) do
        eb:ClearAllPoints()
        for _, point in ipairs(saved.points) do eb:SetPoint(unpack(point)) end
        eb:SetFrameStrata(saved.strata)
        eb:SetFrameLevel(saved.level)
    end
    wipe(original)
    if cover then cover:Hide() end
    for i = 1, 10 do
        local cf = _G["ChatFrame" .. i]
        local d = cf and CFD(cf)
        if d and d.fvIn then d.fvIn:Show() end
    end
    active = false
end

UpdateCover = function(excluded, gained)
    if not cover then return end
    local shown = false
    if listening and Target() then
        for eb in pairs(original) do
            if eb ~= excluded then
                local focused = eb:HasFocus()
                if eb == gained or (not (issecretvalue and issecretvalue(focused))
                    and focused and eb:IsVisible()) then
                    shown = true
                    break
                end
            end
        end
    end
    cover:SetShown(shown)
end

local function FocusGained(_, eb) UpdateCover(nil, eb) end
local function FocusLost(_, eb) UpdateCover(eb) end
local function InputShown() RequestRefresh() end
local callbacks = {
    ["ChatFrame.OnEditBoxFocusGained"] = FocusGained,
    ["ChatFrame.OnEditBoxFocusLost"] = FocusLost,
    ["ChatFrame.OnEditBoxHide"] = FocusLost,
    ["ChatFrame.OnEditBoxShow"] = InputShown,
}

RequestRefresh = function(id)
    if not listening then return end
    local cfg = ECHAT.DB()
    if id and id ~= cfg.dataBarDockID then return end
    if queued then return end
    queued = true
    -- One deferred pass for this notification, after frame geometry settles.
    C_Timer.After(0, function()
        queued = nil
        if listening then ECHAT.RefreshDataBarDock() end
    end)
end

Configure = function()
    local enabled = Enabled() and true or false
    local bars = EUI._ModuleNS.EllesmereUIDataBars
    if bars then bars.ChatDockChanged = enabled and RequestRefresh or nil end
    if enabled == listening then return end
    listening = enabled
    if enabled then
        for event, fn in pairs(callbacks) do
            EventRegistry:RegisterCallback(event, fn, events)
        end
        events:SetScript("OnEvent", function() RequestRefresh() end)
        events:RegisterEvent("PLAYER_ENTERING_WORLD")
        events:RegisterEvent("UI_SCALE_CHANGED")
        events:RegisterEvent("DISPLAY_SIZE_CHANGED")
        events:RegisterEvent("ADDON_LOADED")
    else
        for event in pairs(callbacks) do EventRegistry:UnregisterCallback(event, events) end
        events:UnregisterAllEvents()
        events:SetScript("OnEvent", nil)
        if cover then cover:Hide() end
    end
end

function ECHAT.ConfigureDataBarDock()
    Configure()
    if not Target() and (active or next(original)) then
        if InCombatLockdown() then
            combatQueue.Defer("chat-databar", ECHAT.RefreshDataBarDock)
        else
            Restore()
        end
    end
end

function ECHAT.RefreshDataBarDock()
    Configure()
    if refreshing then return end
    if InCombatLockdown() then
        combatQueue.Defer("chat-databar", ECHAT.RefreshDataBarDock)
        UpdateCover()
        return
    end
    refreshing = true
    if active or next(original) then Restore() end
    ECHAT.ApplyInputPosition()
    ECHAT.ApplyChatPosition()
    UpdateCover()
    refreshing = false
end
