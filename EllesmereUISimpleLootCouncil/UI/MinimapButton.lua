if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end if (select(2, ...)).slcInert then return end




SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text

local UI = addon.UI or {}
addon.UI = UI

local MinimapButton = {}
UI.MinimapButton = MinimapButton

local S, P
local button, tip

local BUTTON_SIZE = 26
local TIP_PAD, TIP_GAP = 8, 2
local DEFAULT_ANGLE = 215
local ART = "Interface\\AddOns\\EllesmereUISimpleLootCouncil\\art\\minimap"

local function Settings()
    local db = addon.db
    if type(db.minimap) ~= "table" then db.minimap = { hide = false, angle = DEFAULT_ANGLE } end
    return db.minimap
end







local function Docked()
    return button:GetParent() ~= Minimap
end

local function Place()
    if Docked() then return end
    local angle = math.rad(Settings().angle or DEFAULT_ANGLE)
    local half = Minimap:GetWidth() / 2
    local x, y = math.cos(angle), math.sin(angle)
    local radius = half + 10
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    if shape == "SQUARE" then

        x = math.max(-half, math.min(half, x * radius * 1.4142))
        y = math.max(-half, math.min(half, y * radius * 1.4142))
    else
        x, y = x * radius, y * radius
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function DragUpdate()
    local mx, my = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    if not (mx and my and cx and cy) then return end
    Settings().angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
    Place()
end





local function CanOpenCouncil()
    local session = addon.Session
    if not (session and session:IsRunning()) then return false end
    return addon.PlayerIsMasterLooter() or addon.Council:Contains(addon.Player:GetFullName("player"))
end


local function MiddleAction()
    if CanOpenCouncil() then return "council" end
    if addon.Session and addon.Session:MayStage() then return "queue" end
end

local function TipText()
    local key = S.ColorStart(S.color.accentPale)
    local function Action(click, sentence)
        return addon.Locale.Format(sentence, key .. click .. "|r")
    end
    local lines = {
        S.Colorize(S.color.accent, "SimpleLootCouncil"),
        "",
        Action(T["Left click"], T["%s to open the options panel."]),
        Action(T["Right click"], T["%s to open the loot history."]),
    }
    local middle = MiddleAction()
    if middle then
        lines[#lines + 1] = middle == "council"
            and Action(T["Middle click"], T["%s to open the loot council."])
            or Action(T["Middle click"], T["%s to open the loot queue."])
    end
    lines[#lines + 1] = Action("/slc minimap", T["%s to hide this button."])
    return table.concat(lines, "\n")
end

local function BuildTip()
    tip = CreateFrame("Frame", nil, UIParent)
    tip:SetFrameStrata("TOOLTIP")
    tip:Hide()
    S.Fill(tip, S.color.card)
    S.Border(tip, S.color.windowEdge)
    tip.Text = S.Label(tip, S.fontBody, "LEFT", 6)
    tip.Text:SetTextColor(unpack(S.color.text))
    P.Point(tip.Text, "TOPLEFT", tip, "TOPLEFT", TIP_PAD, -TIP_PAD)
end

local function ShowTip()
    if not tip then BuildTip() end

    S.MatchScale(tip)
    tip.Text:SetText(TipText())
    local w, h = tip.Text:GetUnboundedStringWidth(), tip.Text:GetStringHeight()
    if type(w) ~= "number" or type(h) ~= "number" then return end
    tip.Text:SetWidth(math.ceil(w) + 2)
    P.Size(tip, math.ceil(w) + 2 + 2 * TIP_PAD, math.ceil(h) + 2 * TIP_PAD)


    local x, y = button:GetCenter()
    local gap = TIP_GAP * P.Hairline(tip)
    local below = y and y > UIParent:GetHeight() / 2
    local right = x and x > UIParent:GetWidth() / 2
    local from = (below and "TOP" or "BOTTOM") .. (right and "RIGHT" or "LEFT")
    local to = (below and "BOTTOM" or "TOP") .. (right and "RIGHT" or "LEFT")
    tip:ClearAllPoints()
    tip:SetPoint(from, button, to, 0, below and -gap or gap)
    tip:Show()
end

local function HideTip()
    if tip then tip:Hide() end
end





local function OnClick(_, mouse)
    HideTip()
    if mouse == "MiddleButton" then
        local middle = MiddleAction()
        if middle == "council" then UI.MLFrame:Toggle()
        elseif middle == "queue" then UI.QueueFrame:Toggle() end
    elseif mouse == "RightButton" then
        UI.HistoryFrame:Toggle()
    else
        UI.Options:Toggle()
    end
end

local function Build()
    button = CreateFrame("Button", "SimpleLootCouncilMinimapButton", Minimap)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    button:SetClampedToScreen(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    button:RegisterForDrag("LeftButton")


    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(button)
    icon:SetTexture(ART)
    icon:SetVertexColor(0.85, 0.85, 0.85)
    button.icon = icon

    button:SetScript("OnEnter", function(self)
        if self.dragging then return end
        icon:SetVertexColor(1, 1, 1)
        ShowTip()
    end)
    button:SetScript("OnLeave", function()
        icon:SetVertexColor(0.85, 0.85, 0.85)
        HideTip()
    end)
    button:SetScript("OnHide", HideTip)
    button:SetScript("OnClick", OnClick)
    button:SetScript("OnDragStart", function(self)
        if Docked() then return end
        self.dragging = true
        HideTip()
        self:SetScript("OnUpdate", DragUpdate)
    end)
    button:SetScript("OnDragStop", function(self)
        self.dragging = nil
        self:SetScript("OnUpdate", nil)
    end)
    Place()
end


function MinimapButton:Refresh()
    if not Minimap then return end
    if Settings().hide then
        if button then button:Hide() end
        return
    end
    if not button then Build() end
    Place()
    button:Show()
end

function MinimapButton:IsShown()
    return not Settings().hide
end

function MinimapButton:SetShown(shown)
    Settings().hide = not shown
    self:Refresh()
end

function MinimapButton:Init()
    S = addon.Style
    P = addon.Pixel
    self:Refresh()
end
