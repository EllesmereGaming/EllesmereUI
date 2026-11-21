if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  Keyring on WoW Forever
--
--  Forever's keyring (bag -1) opens in one of Blizzard's shared container
--  frames (ContainerFrame1..13). This skins whichever one shows it, under its
--  own card and key ("keyring", enable key reskinKeyring): the frame art faded
--  under the shell and border, the portrait removed, the title and close
--  button in the house style, and the key slots as house item slots. The
--  frames are shared and a skin stays for the session, so a frame that showed
--  the keyring would show the next ordinary bag in that look. The keyring is
--  therefore skinned only while EllesmereUI Bags keeps every other Blizzard
--  bag frame parked (BagsParked): with that module off, or stood down, the
--  keyring stays Blizzard's like the bags beside it. Forever only. Built at
--  the keyring's first open, so a login builds nothing.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local EllesmereUI = _G.EllesmereUI
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
local WSkin = ns.WSkin
if not (WSkin and WSkin.RegisterWindow and WSkin.Shell) then return end

do
local KEYRING = Enum.BagIndex and Enum.BagIndex.Keyring
if not KEYRING then return end

local function KeyringFrame()
    return ContainerFrameUtil_GetShownFrameForID and ContainerFrameUtil_GetShownFrameForID(KEYRING)
end

-- EllesmereUI Bags' namespace (nil while that module is off), and whether its
-- takeover holds Blizzard's other bag frames this session.
local function BagsModule()
    return EllesmereUI._ModuleNS and EllesmereUI._ModuleNS.EllesmereUIBags
end
local function BagsParked()
    local bags = BagsModule()
    return bags ~= nil and bags.BlizzardBagsParked == true
end

local function SkinItems(f)
    local items = f.Items
    if items then
        for _, btn in ipairs(items) do WSkin.ItemButton(btn) end
        return
    end
    local name = f:GetName()
    if not name then return end
    local i = 1
    local btn = _G[name .. "Item" .. i]
    while btn do
        WSkin.ItemButton(btn)
        i = i + 1
        btn = _G[name .. "Item" .. i]
    end
end

local Skin_Keyring = WSkin.WindowCallback("keyring", function()
    local f = KeyringFrame()
    if not f or f:IsForbidden() then return end
    WSkin.Shell("keyring", f)
    WSkin.RemovePortrait(f)
    if f.NineSlice then WSkin.FadeNineSlice(f.NineSlice) end
    WSkin.FadeKeyedArt(f)
    -- A flat-panel Bg is a frame of its own
    local bg = f.Bg
    if bg and bg.GetRegions and not bg:IsObjectType("Texture") then
        WSkin.FadeRegions(bg)
        WSkin.Register(bg, true)
    end
    if f.PortraitButton then
        WSkin.FadeRegions(f.PortraitButton)
        WSkin.Register(f.PortraitButton, true)
    end
    local name = f:GetName()
    WSkin.CommonChrome(f, name, true)
    local title = (f.TitleContainer and f.TitleContainer.TitleText) or f.TitleText
        or (name and _G[name .. "Name"])
    if title then WSkin.Font(title); WSkin.White(title) end
    SkinItems(f)
end)

WSkin.RegisterWindow({
    key = "keyring",
    apply = function()
        -- Without the Bags module the keyring is never skinned: nothing is hooked.
        if not BagsModule() then return end
        -- Skinned as it opens and once more a frame later, after Blizzard's
        -- own slot update.
        local repaint = WSkin.Debounce(Skin_Keyring)
        hooksecurefunc("ToggleBag", function(id)
            if id ~= KEYRING or not BagsParked() or not KeyringFrame() then return end
            Skin_Keyring()
            repaint()
        end)
        if BagsParked() and KeyringFrame() then Skin_Keyring() end
    end,
})
end  -- Keyring pack do-block
