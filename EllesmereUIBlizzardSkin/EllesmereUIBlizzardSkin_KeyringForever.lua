if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  Keyring on WoW Forever
--
--  Forever's keyring (bag -1) opens in one of Blizzard's shared container
--  frames (ContainerFrame1..13). This skins whichever one shows it, under its
--  own card and key ("keyring", enable key reskinKeyring): the frame art faded
--  under the shell and border, the portrait removed, the title and close
--  button in the house style, and the key slots as house item slots. The
--  frames are shared, so one that showed the keyring keeps the look when it
--  later shows another bag (only seen while EllesmereUI Bags is off). Forever
--  only. Built at the keyring's first open, so a login builds nothing.
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
        -- Skinned as it opens and once more a frame later, after Blizzard's
        -- own slot update.
        local repaint = WSkin.Debounce(Skin_Keyring)
        hooksecurefunc("ToggleBag", function(id)
            if id ~= KEYRING or not KeyringFrame() then return end
            Skin_Keyring()
            repaint()
        end)
        if KeyringFrame() then Skin_Keyring() end
    end,
})
end  -- Keyring pack do-block
