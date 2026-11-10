if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Minimap button: a standard round minimap button (the one every addon
--  wears: the tracking ring over a dark disc, the glyph in it) on the map's
--  edge, lit in the accent with the unread count while whispers wait.
--
--    Left-click         open / close the Message Center (the newest unread first)
--    Shift-left-click   Message History
--    Right-click        settings
--    Drag               slide it round the map's edge (kept per profile)
--
--  It is a child of the Minimap, named, as addon buttons are, so a minimap
--  manager treats it like the rest: EllesmereUI's Minimap places it with the
--  other addon buttons and dresses it in the active style (Blizzard Style,
--  Classic WoW UI, WoW Forever rings) -- on its button row, never hidden in
--  the grouped-buttons flyout (KeepOnRow). While a manager holds it, the manager places it; we only
--  place it round the map's edge when nothing else does.
-------------------------------------------------------------------------------
local _, addonNS = ...
local ns = addonNS.Whispers

local BUTTON_NAME = "EllesmereUIMessagingMapButton"
local DEFAULT_ANGLE = 200
local ICON_ALPHA, ICON_HOVER_ALPHA = 0.85, 1
local button
local dragging = false

-- The map's outline per shape (GetMinimapShape): for each quadrant (1 = top
-- right, 2 = top left, 3 = bottom right, 4 = bottom left) whether that corner
-- is round (the button follows the circle) or square (it runs along the
-- edges). The table every minimap button library uses.
local SHAPES = {
    ["ROUND"] = { true, true, true, true },
    ["SQUARE"] = { false, false, false, false },
    ["CORNER-TOPLEFT"] = { false, false, false, true },
    ["CORNER-TOPRIGHT"] = { false, false, true, false },
    ["CORNER-BOTTOMLEFT"] = { false, true, false, false },
    ["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
    ["SIDE-LEFT"] = { false, true, false, true },
    ["SIDE-RIGHT"] = { true, false, true, false },
    ["SIDE-TOP"] = { false, false, true, true },
    ["SIDE-BOTTOM"] = { true, true, false, false },
    ["TRICORNER-TOPLEFT"] = { false, true, true, true },
    ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
    ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
    ["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

-- A minimap manager holds the button: EllesmereUI's Minimap collected it
-- (into its flyout, or onto its button row), or moved it off the map
local function Managed()
    if not button then return false end
    if button:GetParent() ~= Minimap then return true end
    local collected = _G._EBS_CachedAddonButtons
    if type(collected) == "table" then
        for _, b in ipairs(collected) do
            if b == button then return true end
        end
    end
    return false
end

-- On the map's edge at `angle` degrees (0 = right, counter-clockwise)
local function Place(angle)
    if not button or Managed() then return end
    angle = angle or ns.settings.minimap.angle or DEFAULT_ANGLE
    local rad = math.rad(angle)
    local x, y, q = math.cos(rad), math.sin(rad), 1
    if x < 0 then q = q + 1 end
    if y > 0 then q = q + 2 end
    local shape = (GetMinimapShape and GetMinimapShape()) or "ROUND"
    local quad = SHAPES[shape] or SHAPES.ROUND
    local w = Minimap:GetWidth() / 2 + 5
    local h = Minimap:GetHeight() / 2 + 5
    if quad[q] then
        x, y = x * w, y * h
    else
        local dw = math.sqrt(2 * w * w) - 10
        local dh = math.sqrt(2 * h * h) - 10
        x = math.max(-w, math.min(x * dw, w))
        y = math.max(-h, math.min(y * dh, h))
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function Update()
    if not button then return end
    local unread = ns.TotalUnread()
    local hover = button:IsMouseOver()
    if unread > 0 then
        local r, g, b = ns.Accent()
        button.icon:SetVertexColor(r, g, b, 1)
        button.count:SetText(unread > 99 and "99+" or unread)
        button.count:SetTextColor(r, g, b, 1)
        button.count:Show()
    else
        button.icon:SetVertexColor(1, 1, 1, hover and ICON_HOVER_ALPHA or ICON_ALPHA)
        button.count:Hide()
    end
end

-- Shown while the addon and the setting are on; only a change of that is
-- applied, so a manager that hides it (grouped away) is not fought
local wantShown
local function SyncVisibility()
    if not button then return end
    local want = (ns.settings.enabled and ns.settings.minimap.show) and true or false
    if want == wantShown then return end
    wantShown = want
    button:SetShown(want)
end

local function Tooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    local r, g, b = ns.Accent()
    GameTooltip:AddLine("Message Center", r, g, b)
    local any = false
    for _, convo in ipairs(ns.order) do
        if convo.unread > 0 then
            GameTooltip:AddDoubleLine(convo.display or "?", convo.unread, 1, 1, 1, r, g, b)
            any = true
        end
    end
    if not any then GameTooltip:AddLine("No unread whispers", 0.6, 0.6, 0.6) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cffffffffClick|r open / close the Message Center", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("|cffffffffShift-click|r Message History", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("|cffffffffRight-click|r settings", 0.7, 0.7, 0.7)
    if not Managed() then GameTooltip:AddLine("|cffffffffDrag|r move round the map", 0.7, 0.7, 0.7) end
    GameTooltip:Show()
end

-- While dragged: the angle from the map's centre to the cursor
local function OnDragUpdate()
    local mx, my = Minimap:GetCenter()
    if not mx then return end
    local scale = Minimap:GetEffectiveScale()
    local px, py = GetCursorPosition()
    px, py = px / scale, py / scale
    local angle = math.deg(math.atan2(py - my, px - mx)) % 360
    ns.settings.minimap.angle = angle
    Place(angle)
end

local function Build()
    if button or not Minimap then return end
    -- The standard minimap button: 31px, the tracking ring (53px, from the
    -- top left) over a dark disc, the glyph centred, the round highlight
    button = CreateFrame("Button", BUTTON_NAME, Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFixedFrameStrata(true)
    button:SetFrameLevel(8)
    button:SetFixedFrameLevel(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture(136477) -- Interface\Minimap\UI-Minimap-ZoomButton-Highlight

    local overlay = button:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetTexture(136430) -- Interface\Minimap\MiniMap-TrackingBorder
    overlay:SetPoint("TOPLEFT")
    button.overlay = overlay

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetTexture(136467) -- Interface\Minimap\UI-Minimap-Background
    background:SetPoint("TOPLEFT", 7, -5)
    button.background = background

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetTexture(ns.MEDIA .. "whisper.png")
    button.icon:SetSize(16, 16)
    button.icon:SetPoint("CENTER", background, "CENTER")

    button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    button.count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)

    button:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then
            ns.OpenSettings()
        elseif IsShiftKeyDown() then
            ns.ToggleHistory()
        else
            ns.ToggleWindow()
        end
    end)
    button:SetScript("OnEnter", function(self)
        Update()
        if not dragging then Tooltip(self) end
    end)
    button:SetScript("OnLeave", function() Update() GameTooltip:Hide() end)

    -- Drag slides it round the edge (a manager moves it its own way)
    button:SetScript("OnDragStart", function(self)
        if Managed() then return end
        dragging = true
        GameTooltip:Hide()
        self:LockHighlight()
        self:SetScript("OnUpdate", OnDragUpdate)
    end)
    button:SetScript("OnDragStop", function(self)
        if not dragging then return end
        dragging = false
        self:SetScript("OnUpdate", nil)
        self:UnlockHighlight()
    end)

    -- The map's size or shape can change (EllesmereUI's minimap settings)
    Minimap:HookScript("OnSizeChanged", function() Place() end)

    Place()
    Update()
end

-- Always in view: EllesmereUI's Minimap would gather the button into its
-- addon-button flyout with the rest. Its "ungrouped" list keeps a button on
-- the button row by the map instead (dressed in the active style), so ours
-- is put on that list, at the end of the row, at every login (a regroup in
-- the Minimap settings lasts until then). True when it was added.
local function KeepOnRow()
    local db = _G._EMM_DB
    local mp = db and db.profile and db.profile.minimap
    if type(mp) ~= "table" then return false end
    if type(mp.ungroupedButtons) ~= "table" then mp.ungroupedButtons = {} end
    local ug = mp.ungroupedButtons
    if ug[BUTTON_NAME] then return false end
    local last = 0
    for _, order in pairs(ug) do
        if type(order) == "number" and order > last then last = order end
    end
    ug[BUTTON_NAME] = last + 1
    return true
end

do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function()
        if not (button and ns.settings and ns.settings.enabled and ns.settings.minimap.show) then return end
        -- the Minimap lays its buttons out a frame after this event: set
        -- the flag before that pass; a later add (a profile switch) rebuilds
        if KeepOnRow() and _G._EMM_FullRebuildMinimap then
            C_Timer.After(0, _G._EMM_FullRebuildMinimap)
        end
    end)
end

function ns.ApplyMinimapButton()
    -- the old free placement (a spot over the map) is gone: the edge angle
    ns.settings.minimap.point = nil
    if ns.settings.minimap.show then
        Build()
        if KeepOnRow() and _G._EMM_FullRebuildMinimap then
            C_Timer.After(0, _G._EMM_FullRebuildMinimap)
        end
    end
    Place()
    SyncVisibility()
    Update()
end

ns.On("Ready", ns.ApplyMinimapButton)
ns.On("SettingsChanged", ns.ApplyMinimapButton)
ns.On("UnreadChanged", Update)
ns.On("ConvoClosed", Update)
