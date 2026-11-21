if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Bags_Keyring.lua
--  WoW Forever's Keyring Icon (Bag Top Bar Icons, off by default): a popup in
--  the Show Bags window's style, hanging from the icon, with the keyring's
--  slots (bag -1, which has no place in the bag window). Built on its first
--  open; its events are registered only while it shows.
-------------------------------------------------------------------------------
local ns = select(2, ...)
local I = ns._bagsInternals
if not (ns and ns.GetSelection and I) then return end
local EUI = EllesmereUI
if not EUI.IS_FOREVER then return end
local KEYRING = Enum.BagIndex and Enum.BagIndex.Keyring
if not KEYRING then return end

local SetInsetBorderColor = I.SetInsetBorderColor
local SLOT_SIZE, SPACING = I.SLOT_SIZE, I.SPACING
ns.OnSlotMetrics(function(m) SLOT_SIZE, SPACING = m[1], m[2] end)

local COLUMNS = 4  -- the keyring grows four slots at a time
local win
local slots = {}

-- The keyring reports all its slots; like Blizzard's keyring window, show the
-- highest filled one rounded up to the next multiple of four (a filled
-- fourth slot opens the next row), within what it has.
local function ShownSlots()
    local total = C_Container.GetContainerNumSlots(KEYRING) or 0
    if GetKeyRingSize then return math.min(GetKeyRingSize() or total, total) end
    local last = 0
    for slot = total, 1, -1 do
        if C_Container.GetContainerItemInfo(KEYRING, slot) then last = slot; break end
    end
    return math.min(last - last % 4 + 4, total)
end

local function GetOrCreateSlot(idx)
    if slots[idx] then return slots[idx] end
    -- Never create a secure button during combat (taint).
    if InCombatLockdown() then return nil end
    local slotParent = CreateFrame("Frame", nil, win)
    ns.SizeSlot(slotParent)
    slotParent:SetID(KEYRING)
    local btn = CreateFrame("ItemButton", nil, slotParent, "ContainerFrameItemButtonTemplate")
    ns.PinItemButton(btn, win)
    btn:SetAllPoints(slotParent)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")
    ns.SkinItemButton(btn, { anchorIcon = true, cooldownFont = true })
    btn._emptyBg = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
    btn._emptyBg:SetAllPoints()
    ns.SetSlotBackgroundTexture(btn._emptyBg, true)
    slots[idx] = btn
    return btn
end

local Refresh
local function RefreshAfterCombat() if win and win:IsShown() then Refresh() end end

function Refresh()
    ns.PinItemPool(slots, win, "_pinLevel")
    for _, btn in pairs(slots) do btn:GetParent():Hide() end
    local numSlots = ShownSlots()
    local startX, startY = 10, -10
    local short = false
    for slot = 1, numSlots do
        local btn = GetOrCreateSlot(slot)
        if not btn then
            short = true
        else
            local parent = btn:GetParent()
            btn:SetID(slot)
            local info = C_Container.GetContainerItemInfo(KEYRING, slot)
            btn:Show()
            if info then
                btn._emptyBg:Hide()
                btn.icon:Show()
                ns.SetSlotIcon(btn, info.iconFileID)
                btn:SetItemButtonCount(info.stackCount)
                SetItemButtonDesaturated(btn, info.isLocked)
                local r, g, b = ns.QualityBorderColor(info.quality or 1)
                SetInsetBorderColor(btn, r, g, b, 1)
            else
                btn._emptyBg:Show()
                ns.PaintSlotBackground(btn._emptyBg, 0.35)
                btn:SetItemButtonTexture(nil)
                btn:SetItemButtonCount(0)
                SetItemButtonDesaturated(btn, false)
                btn.icon:Hide()
                SetInsetBorderColor(btn, 0, 0, 0, 0.3)
            end
            if btn._fvSlotBorder then
                if info then
                    ns.SetForeverSlotQuestBorder(btn, ns.GetSlotQuestFlags(KEYRING, slot))
                else
                    ns.SetForeverSlotQuestBorder(btn, false)
                end
            end
            if GameTooltip:IsOwned(btn) then
                if info and btn.UpdateTooltip then btn:UpdateTooltip() else GameTooltip:Hide() end
            end
            local col = (slot - 1) % COLUMNS
            local row = math.floor((slot - 1) / COLUMNS)
            parent:ClearAllPoints()
            parent:SetPoint("TOPLEFT", win, "TOPLEFT",
                startX + col * (SLOT_SIZE + SPACING), startY - row * (SLOT_SIZE + SPACING))
            parent:Show()
        end
    end
    if short then ns.CombatQueue.Defer("bagsKeyring", RefreshAfterCombat) end
    local cols = math.max(math.min(numSlots, COLUMNS), 1)
    local rows = math.max(math.ceil(numSlots / COLUMNS), 1)
    win:SetSize(cols * (SLOT_SIZE + SPACING) + 15, rows * (SLOT_SIZE + SPACING) - SPACING + 20)
end

local function Build()
    win = CreateFrame("Frame", "EUI_BagsKeyringFrame", UIParent)
    win:Hide()
    win:SetToplevel(true)
    win:EnableMouse(true)
    win.bg = win:CreateTexture(nil, "BACKGROUND")
    win.bg:SetAllPoints()
    win.bg:SetColorTexture(0.02, 0.02, 0.02, 0.95)
    if not ns.SkinForeverBagWindow(win, win.bg) and EUI.PanelPP then
        EUI.PanelPP.CreateBorder(win, 0.1, 0.1, 0.1, 1, 1, "OVERLAY", 7)
    end
    EllesmereUI.RegisterEscapeClose(win)

    local events = CreateFrame("Frame")
    events:SetScript("OnEvent", function(_, _, bag)
        if bag == KEYRING then Refresh() end
    end)
    win:SetScript("OnShow", function(self)
        EUI_BagsWindow:Hide()  -- one header popup at a time
        self:SetScale(EUI_Bags:GetScale())  -- Window Scale, as the bag window's other popups
        self:SetFrameStrata(EUI_Bags:GetFrameStrata())
        self:Raise()
        events:RegisterEvent("BAG_UPDATE")
        events:RegisterEvent("ITEM_LOCK_CHANGED")
        Refresh()
    end)
    win:SetScript("OnHide", function()
        events:UnregisterAllEvents()
    end)
    EUI_BagsWindow:HookScript("OnShow", function() win:Hide() end)
    -- Closes with the bags it hangs from (Alt-Z leaves IsShown true)
    EUI_Bags:HookScript("OnHide", function(self)
        if not self:IsShown() then win:Hide() end
    end)
    EUI_Bags._keyringWin = win
end

-- The header icon's click: open or close the popup above anchor.
function ns.ToggleKeyringWindow(anchor)
    if not win then Build() end
    if win:IsShown() then win:Hide(); return end
    win:ClearAllPoints()
    win:SetPoint("BOTTOMRIGHT", anchor, "TOPLEFT", 0, 2)
    win:Show()
end
