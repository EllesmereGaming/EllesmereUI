if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  Pet Stable on WoW Forever
--
--  Forever's stable is PetStableFrame (the load-on-demand Blizzard_StableUI
--  addon, Camelot build): a portrait window with the selected pet's model, its
--  happiness and XP bar, three slot buttons (current pet + two stabled), the
--  slot purchase row and the player's money. This skins it under its own card
--  and key ("stable", enable key reskinStable): the frame art, dividers and
--  footer faded under the shell and border, the portrait removed, the model
--  well bordered, the XP bar flattened to the house bar fill, the slots as
--  house item slots, and the purchase button flattened. Forever only.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local EllesmereUI = _G.EllesmereUI
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
local WSkin = ns.WSkin
if not (WSkin and WSkin.RegisterWindow and WSkin.Shell) then return end

do
local _, GetFFD = EllesmereUI.NewFrameData()

local SLOTS = { "PetStableCurrentPet", "PetStableStabledPet1", "PetStableStabledPet2" }
-- Slot state art Blizzard toggles with SetShown; alpha keeps them gone.
local SLOT_ART = { "currentGlow", "unlockedBackground", "currentBackground", "lockedBackground" }

local function SkinSlot(btn)
    if not btn or btn:IsForbidden() then return end
    for _, k in ipairs(SLOT_ART) do
        local t = btn[k]
        if t and t.SetAlpha then t:SetAlpha(0) end
    end
    WSkin.ItemButton(btn)
    local d = GetFFD(btn)
    if d.done then return end
    d.done = true
    local pt = btn.GetPushedTexture and btn:GetPushedTexture()
    if pt then pt:SetAlpha(0) end
    local ct = btn.GetCheckedTexture and btn:GetCheckedTexture()
    local icon = btn.icon or _G[btn:GetName() .. "IconTexture"]
    if ct and icon then
        ct:SetColorTexture(1, 1, 1, 0.15)
        ct:ClearAllPoints()
        ct:SetAllPoints(icon)
    end
    if btn.Text then WSkin.Font(btn.Text) end
end

-- The XP bar is a masked atlas fill over a rounded track: drop both for a
-- flat fill in the house bar color on a dark plate the fill's height.
local function PaintXPFill(bar)
    if bar and bar.Fill then bar.Fill:SetColorTexture(WSkin.BarFillColor()) end
end

local function SkinXPBar(bar)
    if not bar or bar:IsForbidden() or not (bar.Fill and bar.FillArea) then return end
    local d = GetFFD(bar)
    if not d.done then
        d.done = true
        WSkin.FadeRegions(bar, { [bar.Fill] = true })
        if bar.Mask then bar.Fill:RemoveMaskTexture(bar.Mask) end
        local plate = bar:CreateTexture(nil, "BACKGROUND", nil, -7)
        plate:SetColorTexture(0, 0, 0, 0.5)
        plate:SetPoint("LEFT", bar.FillArea, "LEFT")
        plate:SetPoint("RIGHT", bar.FillArea, "RIGHT")
        plate:SetPoint("TOP", bar.Fill, "TOP")
        plate:SetPoint("BOTTOM", bar.Fill, "BOTTOM")
        WSkin.BorderRegion(bar, plate)
        WSkin.OnLooksChanged(function() PaintXPFill(bar) end)
    end
    PaintXPFill(bar)
    if bar.Text then WSkin.Font(bar.Text); WSkin.White(bar.Text) end
end

local function SkinModelScene(scene)
    if not scene or scene:IsForbidden() then return end
    if scene.Background then scene.Background:SetAlpha(0) end
    if scene.Inset then WSkin.Inset(scene.Inset) end
    local shadow = scene.PetModelSceneShadow
    if shadow then WSkin.FadeRegions(shadow); shadow:SetAlpha(0) end
    local d = GetFFD(scene)
    if d.done then return end
    d.done = true
    local shade = scene:CreateTexture(nil, "BACKGROUND", nil, -8)
    shade:SetColorTexture(0, 0, 0, 0.25)
    shade:SetAllPoints(scene)
    WSkin.AddBorder(scene)
end

local Skin_Stable = WSkin.WindowCallback("stable", function()
    local f = _G.PetStableFrame
    if not f then return end
    WSkin.Shell("stable", f, { bottomBar = 30 })
    WSkin.RemovePortrait(f)
    WSkin.CommonChrome(f, "PetStableFrame", true)
    if _G.PetStableFrameBg then _G.PetStableFrameBg:SetAlpha(0) end
    for _, k in ipairs({ "TopDividerFrame", "BottomDividerFrame" }) do
        local div = f[k]
        if div and div.horzDivider then div.horzDivider:SetAlpha(0) end
    end
    local title = (f.TitleContainer and f.TitleContainer.TitleText) or _G.PetStableFrameTitleText
    if title then WSkin.Font(title); WSkin.White(title) end
    local level = _G.PetStableLevelText
    if level then WSkin.Font(level); WSkin.White(level) end
    for _, n in ipairs({ "PetStableLoyaltyText", "PetStableSlotText", "PetStableCostLabel" }) do
        if _G[n] then WSkin.Font(_G[n]) end
    end
    if f.GamepadSlotCostText then WSkin.Font(f.GamepadSlotCostText) end

    SkinModelScene(f.modelScene)
    SkinXPBar(f.expBar)
    for _, n in ipairs(SLOTS) do SkinSlot(_G[n]) end

    if f.purchaseButton then
        WSkin.Button(f.purchaseButton)
        WSkin.StateButtonLabel(f.purchaseButton)
    end
    local money = _G.PetStableMoneyFrame
    if money and money.Border then
        WSkin.FadeRegions(money.Border)
        WSkin.Register(money.Border, true)
    end
end)

WSkin.RegisterWindow({
    key = "stable",
    apply = function()
        Skin_Stable()
        local f = _G.PetStableFrame
        if f then WSkin.HookShow(f, WSkin.Debounce(Skin_Stable)) end
    end,
    addons = { Blizzard_StableUI = true },
})
end  -- Pet Stable pack do-block
