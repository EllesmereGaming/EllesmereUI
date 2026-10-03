if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  Bag Bar on WoW Forever
--
--  The bag bar's slot buttons (backpack, four bag slots, reagent bag, keyring)
--  in the micro menu pack's cell look: bevel and icon-frame art faded, icon
--  cropped square, a theme background and border, a white hover wash, and a
--  quality-coloured border for a coloured bag. The BagsBar strip art is faded.
--  Alpha and our own child frames only: nothing is hidden, reparented or hooked
--  on show inside the BagsBar tree (Blizzard shows and hides it on the way to
--  protected calls). Forever only (IS_FOREVER is false everywhere else).
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local EllesmereUI = _G.EllesmereUI
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
local WSkin = ns.WSkin
if not (WSkin and WSkin.RegisterWindow) then return end

local Theme = WSkin.Theme
local FFD = setmetatable({}, { __mode = "k" })
local function GetFFD(frame)
    local d = FFD[frame]
    if not d then d = {}; FFD[frame] = d end
    return d
end
local OURS = setmetatable({}, { __mode = "k" })  -- the frames this pack created

local ICON_CROP = 0.08
local CELL_BG_A = 0.45
-- BagsBar container backdrop atlases (the dark strip behind the slots).
local FRAME_ATLASES = { "actionbar-frame", "iconframe-background" }
local BAG_BUTTONS = {
    "MainMenuBarBackpackButton",
    "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot", "CharacterBag3Slot",
    "CharacterReagentBag0Slot", "KeyRingButton",
}

local function BorderPP() return EllesmereUI.PanelPP or EllesmereUI.PP end

-- One-time cell chrome: a box frame of ours with the theme border, the cell
-- background behind the icon, and the highlight turned into a white wash.
local function EnsureChrome(btn)
    local d = GetFFD(btn)
    if d.box then return d end
    local box = CreateFrame("Frame", nil, btn)
    box:SetAllPoints(btn)
    box:EnableMouse(false)
    WSkin.AddBorder(box)
    OURS[box] = true
    d.box = box
    local bg = btn:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetColorTexture(Theme.bgR, Theme.bgG, Theme.bgB, CELL_BG_A)
    bg:SetAllPoints(btn)
    d.bg = bg
    local hl = btn.GetHighlightTexture and btn:GetHighlightTexture()
    if hl and hl.SetColorTexture then
        hl:SetColorTexture(1, 1, 1, 0.1)
        if hl.SetTexCoord then hl:SetTexCoord(0, 1, 0, 1) end
    end
    return d
end

-- The keyring's frame art sits in its child frames (a NineSlice border built
-- after the first pass): fade their textures, walking Blizzard's own frames only.
local function FadeKeyRingArt(f, depth)
    if not f or depth > 4 or (f.IsForbidden and f:IsForbidden()) then return end
    local children = { f:GetChildren() }
    for i = 1, #children do
        local c = children[i]
        if c and not OURS[c] and not WSkin.IsForeignFrame(c, f) then
            local regions = { c:GetRegions() }
            for j = 1, #regions do
                local r = regions[j]
                if r and r.GetObjectType and r:GetObjectType() == "Texture" then r:SetAlpha(0) end
            end
            FadeKeyRingArt(c, depth + 1)
        end
    end
end

-- Per pass: icon crop, bevel art, masks and the border colour (bag quality).
local function PaintBag(btn)
    local d = FFD[btn]
    if not (d and d.box) then return end
    local isKeyRing = (btn == _G.KeyRingButton)
    local icon = btn.icon or (btn.GetName and _G[btn:GetName() .. "IconTexture"])
    local nt = (btn.GetNormalTexture and btn:GetNormalTexture()) or btn.NormalTexture
    if isKeyRing then
        -- Its glyph can live on the NormalTexture, under its own SquareMask.
        local sm = btn.SquareMask
        if sm then
            for _, t in ipairs({ _G.KeyRingButtonIconTexture, nt }) do
                if t and t.RemoveMaskTexture then pcall(t.RemoveMaskTexture, t, sm) end
            end
        end
        FadeKeyRingArt(btn, 1)
        if not (icon and icon.GetTexture and icon:GetTexture()) then icon = nt end
    end
    if icon and icon.SetTexCoord then
        icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
    end
    -- The bevel NormalTexture fades, except while it is the keyring glyph.
    if nt and nt ~= icon then nt:SetAlpha(0) end
    if btn.IconBorder then btn.IconBorder:SetAlpha(0) end
    local regions = { btn:GetRegions() }
    for i = 1, #regions do
        local r = regions[i]
        local kind = r and r.GetObjectType and r:GetObjectType()
        if kind == "MaskTexture" then
            -- pcall: a texture the mask is not on may reject the removal.
            if icon and icon.RemoveMaskTexture then pcall(icon.RemoveMaskTexture, icon, r) end
            if nt and nt ~= icon and nt.RemoveMaskTexture then pcall(nt.RemoveMaskTexture, nt, r) end
        elseif kind == "Texture" then
            local atlas = r.GetAtlas and r:GetAtlas()
            if atlas and atlas:lower():find("iconframe", 1, true) then r:SetAlpha(0) end
        end
    end
    -- A coloured bag (uncommon and up) colours its border; the rest keep the theme border.
    local id = btn.GetID and btn:GetID()
    local itemID = id and id > 0 and GetInventoryItemID("player", id)
    local q = itemID and C_Item.GetItemQualityByID(itemID)
    local r, g, b
    if q and q >= 2 then r, g, b = C_Item.GetItemQualityColor(q) end
    local PP = BorderPP()
    if r then
        PP.SetBorderColor(d.box, r, g, b, 1)
    else
        PP.SetBorderColor(d.box, Theme.brdR, Theme.brdG, Theme.brdB, Theme.brdA)
    end
end

local function FadeFrameArt(frame)
    if not frame then return end
    local regions = { frame:GetRegions() }
    for i = 1, #regions do
        local r = regions[i]
        local atlas = r and r.GetAtlas and r:GetAtlas()
        if atlas then
            local la = atlas:lower()
            for _, want in ipairs(FRAME_ATLASES) do
                if la:find(want, 1, true) then r:SetAlpha(0); break end
            end
        end
    end
end

local function PaintAll()
    for _, name in ipairs(BAG_BUTTONS) do
        local btn = _G[name]
        if btn then PaintBag(btn) end
    end
end

local hooked = false
local function Skin_BagBar()
    FadeFrameArt(_G.BagsBar)
    for _, name in ipairs(BAG_BUTTONS) do
        local btn = _G[name]
        if btn and not btn:IsForbidden() then EnsureChrome(btn) end
    end
    PaintAll()
    if hooked then return end
    hooked = true
    -- Bag changes: quality borders and icon crops follow the equipped bags.
    local f = CreateFrame("Frame")
    f:RegisterEvent("BAG_UPDATE_DELAYED")
    f:SetScript("OnEvent", WSkin.Debounce(PaintAll))
    -- The keyring rebuilds its art in its own texture update (bag updates and
    -- zone-ins): repaint it right after.
    local kr = _G.KeyRingButton
    if kr and kr.UpdateTextures then
        hooksecurefunc(kr, "UpdateTextures", function() PaintBag(kr) end)
    end
end

WSkin.RegisterWindow({
    key = "bagbar",
    apply = Skin_BagBar,
})
