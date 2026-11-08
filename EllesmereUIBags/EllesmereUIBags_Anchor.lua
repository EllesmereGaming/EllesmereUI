if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
local ns = select(2, ...)
local I = ns._bagsInternals
if not I then return end

local EUI = EllesmereUI
local BP = I.BP

local UNLOCK_KEY = "EBAG_Anchor"
local ANCHOR_W, ANCHOR_H = 240, 28
local CORNERS = { TOPLEFT = "Top Left", TOPRIGHT = "Top Right", BOTTOMLEFT = "Bottom Left", BOTTOMRIGHT = "Bottom Right" }

local Anchor = { KEY = UNLOCK_KEY }
ns.BagAnchor = Anchor
local frame, element

function Anchor.On() return BP().bagAnchor == true end

function Anchor.Corner()
    local c = BP().bagAnchorCorner
    return CORNERS[c] and c or "BOTTOMRIGHT"
end

function Anchor.ActiveCorner()
    return Anchor.On() and Anchor.Corner() or nil
end

local function IsLeft(c) return c == "TOPLEFT" or c == "BOTTOMLEFT" end
local function IsBottom(c) return c == "BOTTOMLEFT" or c == "BOTTOMRIGHT" end

local function CenterPos(corner, x, y)
    local w, h = UIParent:GetSize()
    local cx = x + (IsLeft(corner) and ANCHOR_W or -ANCHOR_W) / 2
    local cy = y + (IsBottom(corner) and ANCHOR_H or -ANCHOR_H) / 2
    return { point = "CENTER", relPoint = "CENTER", x = cx - w / 2, y = cy - h / 2 }
end

local function DefaultPos()
    local c = Anchor.Corner()
    local w, h = UIParent:GetSize()
    return CenterPos(c, IsLeft(c) and 50 or w - 50, IsBottom(c) and 50 or h - 50)
end

local function SavedPos()
    local p = BP().bagAnchorPos
    if type(p) == "table" and p.point and p.x and p.y then return p end
    return DefaultPos()
end

local function Place()
    if not frame then return end
    local p = SavedPos()
    frame:ClearAllPoints()
    frame:SetPoint(p.point, UIParent, p.relPoint or p.point, p.x, p.y)
    if not EUI._unlockActive and EUI.IsUnlockAnchored and EUI.ReapplyOwnAnchor
        and EUI.IsUnlockAnchored(UNLOCK_KEY) then
        EUI.ReapplyOwnAnchor(UNLOCK_KEY)
    end
end

local function Ensure()
    if frame then return frame end
    frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(ANCHOR_W, ANCHOR_H)
    frame:EnableMouse(false)
    Place()
    return frame
end

local function WindowCorner(corner)
    local l, r, t, b = EUI_Bags:GetLeft(), EUI_Bags:GetRight(), EUI_Bags:GetTop(), EUI_Bags:GetBottom()
    if not l then return nil end
    return IsLeft(corner) and l or r, IsBottom(corner) and b or t
end

local function Capture(corner)
    local x, y = WindowCorner(corner)
    if not x then BP().bagAnchorPos = nil; return end
    local s = EUI_Bags:GetEffectiveScale() / UIParent:GetEffectiveScale()
    x, y = x * s, y * s
    local PP = EUI.PP
    if PP and PP.Snap then x, y = PP.Snap(x), PP.Snap(y) end
    BP().bagAnchorPos = CenterPos(corner, x, y)
end

function Anchor.Pin()
    local c = Anchor.ActiveCorner()
    if not c then return end
    EUI_Bags:ClearAllPoints()
    EUI_Bags:SetPoint(c, Ensure(), c, 0, 0)
end

function Anchor.SaveSpot()
    local c = Anchor.ActiveCorner()
    local x, y = WindowCorner(c or "TOPLEFT")
    if not x then return end
    local PP = EUI.PP
    if PP and PP.Snap then x, y = PP.Snap(x), PP.Snap(y) end
    EUI_Bags:ClearAllPoints()
    if c then
        EUI_Bags:SetPoint(c, UIParent, "BOTTOMLEFT", x, y)
    else
        BP().bagsPosition = { point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = x, y = y }
        EUI_Bags:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    end
end

local function Label()
    return EllesmereUI.Lf("Bag Anchor (%1$s)", EllesmereUI.L(CORNERS[Anchor.Corner()]))
end

local function Relayout()
    if EUI_Bags:IsVisible() then EUI_Bags:RefreshInventory() end
end

function Anchor.SetOn(on)
    if on == Anchor.On() then return end
    if on then
        Capture(Anchor.Corner())
        BP().bagAnchor = true
        Place()
        Anchor.Pin()
    else
        BP().bagAnchor = false
        Anchor.SaveSpot()
    end
    Relayout()
end

function Anchor.SetCorner(corner)
    if not CORNERS[corner] or corner == Anchor.Corner() then return end
    if Anchor.On() then Anchor.Pin() end
    BP().bagAnchorCorner = corner
    if element then
        element.label = Label()
        if EUI.RefreshUnlockElementLabel then EUI.RefreshUnlockElementLabel(UNLOCK_KEY) end
    end
    if Anchor.On() then
        Capture(corner)
        Place()
        Anchor.Pin()
        Relayout()
    end
end

local function Register()
    if not EUI.RegisterUnlockElements then return end
    element = EUI.MakeUnlockElement({
        key      = UNLOCK_KEY,
        label    = Label(),
        group    = "Bags",
        order    = 620,
        noResize = true,
        isHidden = function() return not Anchor.On() end,
        getFrame = function()
            if not Anchor.On() then return nil end
            element.label = Label()
            return Ensure()
        end,
        getSize  = function() return ANCHOR_W, ANCHOR_H end,
        savePos  = function(_, point, relPoint, x, y)
            if not point then return end
            BP().bagAnchorPos = { point = point, relPoint = relPoint or point, x = x, y = y }
            if frame and not EUI._unlockActive then Place() end
        end,
        loadPos  = function()
            if not Anchor.On() then return nil end
            return SavedPos()
        end,
        clearPos = function()
            BP().bagAnchorPos = nil
            Place()
        end,
        applyPos = function()
            if Anchor.On() then Ensure(); Place() end
        end,
    })
    EUI:RegisterUnlockElements({ element }, "EllesmereUIBags")
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    Register()
end)
