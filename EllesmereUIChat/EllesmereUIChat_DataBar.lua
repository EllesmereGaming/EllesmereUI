if EUI_CLIENT_BLOCKED then return end
local _, ns = ...
local ECHAT = ns.ECHAT
local EUI = EllesmereUI
local CFD = EUI._chatCFD
local cover, active, busy
local original = {}
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
    if not bar or InCombatLockdown() then return end
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
end

function ECHAT.ApplyDataBarDock()
    local bar, x, y, w, h = Target()
    if not bar then return false end
    -- Defer protected geometry changes, retaining the last safe placement.
    if InCombatLockdown() or busy then return true end
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

function ECHAT.RefreshDataBarDock()
    if InCombatLockdown() then return end
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
    ECHAT.ApplyInputPosition()
    ECHAT.ApplyChatPosition()
end

-- Use our own driver, never hook Blizzard edit-box scripts. This also covers
-- the Classic client without ChatFrame EventRegistry callbacks.
local driver = CreateFrame("Frame")
local elapsed, lastBar, lastX, lastY, lastW, lastH = 0
driver:SetScript("OnUpdate", function(_, dt)
    local shown = false
    if cover and Target() then
        for eb in pairs(original) do
            -- Inactive chat boxes can stay logically shown (including boxes
            -- under hidden tabs). Only an actual focused input covers the bar.
            local focused = eb:HasFocus()
            if not (issecretvalue and issecretvalue(focused))
                and focused and eb:IsVisible() then
                shown = true
                break
            end
        end
    end
    if cover then cover:SetShown(shown) end
    elapsed = elapsed + dt
    if elapsed < 0.1 or InCombatLockdown() then return end
    elapsed = 0
    local bar, x, y, w, h = Target()
    if bar then
        ECHAT.ApplyDataBarDock()
        if bar ~= lastBar or x ~= lastX or y ~= lastY or w ~= lastW or h ~= lastH then
            ECHAT.ApplyInputPosition()
        end
    elseif active or next(original) then
        ECHAT.RefreshDataBarDock()
    end
    lastBar, lastX, lastY, lastW, lastH = bar, x, y, w, h
end)
