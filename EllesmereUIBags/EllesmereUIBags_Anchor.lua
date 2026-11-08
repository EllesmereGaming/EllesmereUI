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
local bind, bindCorner
local PinTo

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

local function Label()
    return EllesmereUI.Lf("Bag Anchor (%1$s)", EllesmereUI.L(CORNERS[Anchor.Corner()]))
end

local function Linked()
    local db = EllesmereUIDB and EllesmereUIDB.unlockAnchors
    local info = db and db[UNLOCK_KEY]
    return info and info.target and info or nil
end

local function Place(keepLink)
    if not frame then return end
    local p = SavedPos()
    frame:ClearAllPoints()
    frame:SetPoint(p.point, UIParent, p.relPoint or p.point, p.x, p.y)
    local info = Linked()
    if info and not EUI._unlockActive then
        if keepLink and EUI._CaptureAnchorOffsets then
            local ox, oy = EUI._CaptureAnchorOffsets(UNLOCK_KEY, info.target, info.side)
            if ox ~= nil then info.offsetX, info.offsetY = ox, oy end
            local edge = info.edge
            if edge and edge.key and EUI._CaptureScreenEdgeOffset then
                local eo = EUI._CaptureScreenEdgeOffset(UNLOCK_KEY, edge.key, edge.side)
                if eo then edge.offset = eo end
            end
        elseif EUI.ReapplyOwnAnchor then
            EUI.ReapplyOwnAnchor(UNLOCK_KEY)
        end
    end
    if EUI.PropagateAnchorChain then EUI.PropagateAnchorChain(UNLOCK_KEY) end
end

local function Register()
    if not EUI.RegisterUnlockElements then return end
    if not element then
        element = EUI.MakeUnlockElement({
            key      = UNLOCK_KEY,
            label    = Label(),
            group    = "Bags",
            order    = 620,
            noResize = true,
            isHidden = function() return not Anchor.On() end,
            getFrame = function()
                if not Anchor.On() then return nil end
                return frame
            end,
            getSize  = function() return ANCHOR_W, ANCHOR_H end,
            savePos  = function(_, point, relPoint, x, y)
                if not point then return end
                BP().bagAnchorPos = { point = point, relPoint = relPoint or point, x = x, y = y }
                if not EUI._unlockActive then Place() end
                if Anchor.On() and Anchor.pending then
                    Anchor.pending = false
                    PinTo(Anchor.Corner())
                end
            end,
            loadPos  = function()
                if not Anchor.On() then return nil end
                return SavedPos()
            end,
            clearPos = function()
                BP().bagAnchorPos = nil
                Place()
                if Anchor.On() and Anchor.pending then
                    Anchor.pending = false
                    PinTo(Anchor.Corner())
                end
            end,
            applyPos = function()
                if Anchor.On() then Place() end
            end,
        })
    end
    element.label = Label()
    EUI:RegisterUnlockElements({ element }, "EllesmereUIBags")
    if EUI.RefreshUnlockElementLabel then EUI.RefreshUnlockElementLabel(UNLOCK_KEY) end
end

local function Ensure()
    if frame then return frame end
    frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(ANCHOR_W, ANCHOR_H)
    frame:EnableMouse(false)
    Place()
    Register()
    return frame
end

local function Scale() return EUI_Bags:GetEffectiveScale() / UIParent:GetEffectiveScale() end

local function AnchoredRect()
    local s = Scale()
    local w, h = EUI_Bags:GetWidth() * s, EUI_Bags:GetHeight() * s
    if bind == "hold" and frame and frame:GetLeft() then
        local x = IsLeft(bindCorner) and frame:GetLeft() or frame:GetRight()
        local y = IsBottom(bindCorner) and frame:GetBottom() or frame:GetTop()
        return IsLeft(bindCorner) and x or x - w, IsBottom(bindCorner) and y or y - h, w, h
    end
    local l, b = EUI_Bags:GetLeft(), EUI_Bags:GetBottom()
    if not l then return nil end
    return l * s, b * s, w, h
end

local function Capture(c)
    local l, b, w, h = AnchoredRect()
    if not l then BP().bagAnchorPos = nil; return end
    local x, y = IsLeft(c) and l or l + w, IsBottom(c) and b or b + h
    local PP = EUI.PP
    if PP and PP.Snap then x, y = PP.Snap(x), PP.Snap(y) end
    BP().bagAnchorPos = CenterPos(c, x, y)
end

function PinTo(c)
    EUI_Bags:ClearAllPoints()
    EUI_Bags:SetPoint(c, Ensure(), c, 0, 0)
    bind, bindCorner = "pin", c
end

local function HoldAt(c)
    local l, r, t, b = EUI_Bags:GetLeft(), EUI_Bags:GetRight(), EUI_Bags:GetTop(), EUI_Bags:GetBottom()
    if not l then return end
    local x, y = IsLeft(c) and l or r, IsBottom(c) and b or t
    local PP = EUI.PP
    if PP and PP.Snap then x, y = PP.Snap(x), PP.Snap(y) end
    EUI_Bags:ClearAllPoints()
    EUI_Bags:SetPoint(c, UIParent, "BOTTOMLEFT", x, y)
    bind, bindCorner = "hold", c
end

local function ApplyLegacy()
    local pos = BP().bagsPosition
    EUI_Bags:ClearAllPoints()
    if pos then
        EUI_Bags:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
    else
        EUI_Bags:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -50, 50)
    end
    bind, bindCorner = nil, nil
end

function Anchor.SaveSpot()
    local c = Anchor.ActiveCorner()
    if c then HoldAt(c); return end
    local x, y = EUI_Bags:GetLeft(), EUI_Bags:GetTop()
    if not x then return end
    local PP = EUI.PP
    if PP and PP.Snap then x, y = PP.Snap(x), PP.Snap(y) end
    BP().bagsPosition = { point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = x, y = y }
    EUI_Bags:ClearAllPoints()
    EUI_Bags:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    bind, bindCorner = nil, nil
end

local function Reconcile()
    Anchor.pending = false
    local c = Anchor.ActiveCorner()
    if not c then
        if bind then Anchor.SaveSpot() end
        return
    end
    if bind and bindCorner == c then return end
    local held = bind == "hold"
    Capture(c)
    Ensure()
    Place(Linked() ~= nil)
    if held then HoldAt(c) else PinTo(c) end
end

local function Changed()
    if EUI_Bags._gripCfg then Reconcile() else Anchor.pending = true end
    if Anchor.On() then Ensure() end
    if element then Register() end
    if EUI_Bags:IsVisible() then EUI_Bags:RefreshInventory() end
end

function Anchor.Start()
    if Anchor.On() then PinTo(Anchor.Corner()) else Register() end
end

function Anchor.Pin()
    local c = Anchor.ActiveCorner()
    if not c or Anchor.pending then return end
    PinTo(c)
end

function Anchor.Laid()
    if Anchor.pending then Reconcile() end
end

function Anchor.SetOn(on)
    if on == Anchor.On() then return end
    BP().bagAnchor = on and true or false
    Changed()
end

function Anchor.SetCorner(corner)
    if not CORNERS[corner] or corner == Anchor.Corner() then return end
    BP().bagAnchorCorner = corner
    Changed()
end

function Anchor.ProfileApplied()
    Anchor.pending = false
    if Anchor.On() then
        Ensure()
        Place()
        PinTo(Anchor.Corner())
    elseif bind then
        ApplyLegacy()
    end
    if element then Register() end
end

function Anchor.Room()
    local c, s = bindCorner, Scale()
    local f, k = frame, 1
    if bind == "hold" then f, k = EUI_Bags, s end
    if not (bind and f and f:GetLeft()) then return nil end
    local x = (IsLeft(c) and f:GetLeft() or f:GetRight()) * k
    local y = (IsBottom(c) and f:GetBottom() or f:GetTop()) * k
    local w, h = UIParent:GetSize()
    return (IsLeft(c) and w - x or x) / s, (IsBottom(c) and h - y or y) / s
end
