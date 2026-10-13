if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIBags_QuickActions.lua
--  Quick Actions (Bag Top Bar Icons, off by default): the header icon toggles a
--  mode that dims every bag item but the ones a known spell works on, marked
--  with its icon; a click casts it. Alt-click does the same outside the mode.
--
--  Taint: one SecureActionButtonTemplate button of our own (type "spell" with
--  target-bag / target-slot), moved, set and shown out of combat only over the
--  hovered slot, hidden on PLAYER_REGEN_DISABLED. Slots only get OnEnter /
--  OnLeave hooks; marks live on btn._textOverlay.
-------------------------------------------------------------------------------
local ns = select(2, ...)
if not (ns and ns.GetSelection) then return end

local EUI = EllesmereUI
local _emptyP = {}
local function BP() return (EUI._bagsDB and EUI._bagsDB.profile) or _emptyP end

-- Milling and Prospecting are profession salvage recipes, not item-targeted spells.
local DISENCHANT, PICK_LOCK, COMPREHEND = 13262, 1804, 1296017
local IC_WEAPON, IC_ARMOR, IC_MISC = Enum.ItemClass.Weapon, Enum.ItemClass.Armor, Enum.ItemClass.Miscellaneous
local ARMOR_COSMETIC = Enum.ItemArmorSubclass.Cosmetic
local FIRST_BAG, LAST_BAG = Enum.BagIndex.Backpack, Enum.BagIndex.ReagentBag  -- not the bank
local SHADE_ALPHA = 0.7
local ICON_ATLAS = "cursor_cast_64"

-- WoW Forever's Comprehension scrolls (the items requiring that Mage skill)
local SCROLLS = {
    [211780] = true, [211784] = true, [211785] = true, [211786] = true, [211787] = true,
    [211853] = true, [211854] = true, [211855] = true, [213543] = true, [213544] = true,
    [213545] = true, [213546] = true, [213547] = true, [281015] = true, [281016] = true,
    [281017] = true, [281018] = true,
}

local enabled     -- the Quick Actions Icon is on (true or nil)
local active      -- the mode is on (true or nil)
local hovered     -- the bag slot under the mouse while Alt is watched
local castBtn     -- the secure button, built on its first use
local events      -- combat and Alt watch, each registered only while needed
local hideHooked
local tipCache = {}  -- item link -> tooltip verdict, kept while the mode is on
local slots  = setmetatable({}, { __mode = "k" })  -- slot button -> { bag, slot, spell }
local marks  = setmetatable({}, { __mode = "k" })  -- slot button -> { shade, spell }
local hooked = setmetatable({}, { __mode = "k" })
local SetActive, StopHover, TryAlt  -- defined below

local function Known(spellID) return C_SpellBook.IsSpellKnown(spellID) end

-- Whether the bag item's tooltip has a line reading exactly text.
local function TooltipHas(bag, slot, text)
    local tip = C_TooltipInfo.GetBagItem(bag, slot)
    if not (tip and tip.lines) then return false end
    for _, line in ipairs(tip.lines) do
        if line.leftText == text then return true end
    end
    return false
end

-- TooltipHas for a line that never changes for a given item, cached while the
-- mode paints every slot.
local function ItemTooltipHas(bag, slot, link, text)
    if not (link and active) then return TooltipHas(bag, slot, text) end
    local v = tipCache[link]
    if v == nil then
        v = TooltipHas(bag, slot, text)
        tipCache[link] = v
    end
    return v
end

-- The spell the player can cast on this bag item, or nil. Equipment set gear
-- is never offered to Disenchant.
local function SpellFor(bag, slot, info)
    local itemID = info.itemID
    if EUI.IS_FOREVER and SCROLLS[itemID] then
        return Known(COMPREHEND) and COMPREHEND or nil
    end
    local _, _, _, _, _, classID, subID = C_Item.GetItemInfoInstant(itemID)
    if classID == IC_WEAPON or classID == IC_ARMOR then
        local q = info.quality or 0
        if q >= 2 and q <= 4 and not (classID == IC_ARMOR and subID == ARMOR_COSMETIC)
            and Known(DISENCHANT)
            and not C_Container.GetContainerItemEquipmentSetInfo(bag, slot)
            and not ItemTooltipHas(bag, slot, info.hyperlink, ITEM_DISENCHANT_NOT_DISENCHANTABLE) then
            return DISENCHANT
        end
    elseif (classID == IC_MISC or info.hasLoot) and Known(PICK_LOCK)
        and TooltipHas(bag, slot, LOCKED) then  -- read each time: unlocking changes it
        return PICK_LOCK
    end
end

-------------------------------------------------------------------------------
--  The secure cast button
-------------------------------------------------------------------------------
local function HideCast()
    if castBtn and not InCombatLockdown() then
        if GameTooltip:IsOwned(castBtn) then GameTooltip:Hide() end
        castBtn:Hide()
        castBtn:ClearAllPoints()
        castBtn.owner = nil
    end
end

local function OnEvent(_, event)
    if event == "MODIFIER_STATE_CHANGED" then
        if IsAltKeyDown() then TryAlt() elseif not active then HideCast() end
    elseif active then  -- PLAYER_REGEN_DISABLED fires before the lockdown
        SetActive(false)
    else
        HideCast()
        StopHover()
    end
end

-- Combat is watched while the mode is on or a slot is hovered, Alt only then.
local function SyncEvents()
    if not events then
        if not (active or hovered) then return end
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", OnEvent)
    end
    if active or hovered then
        events:RegisterEvent("PLAYER_REGEN_DISABLED")
    else
        events:UnregisterEvent("PLAYER_REGEN_DISABLED")
    end
    if hovered then
        events:RegisterEvent("MODIFIER_STATE_CHANGED")
    else
        events:UnregisterEvent("MODIFIER_STATE_CHANGED")
    end
end

function StopHover()
    if not hovered then return end
    hovered = nil
    SyncEvents()
end

local function CastOnEnter(self)
    if not self.owner then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetBagItem(self.bag, self.slot)
    local r, g, b = EUI.GetAccentColor()
    GameTooltip:AddLine(EllesmereUI.Lf("Click: %s", C_Spell.GetSpellName(self.spell) or ""), r, g, b)
    GameTooltip:Show()
end

local function CastOnLeave()
    GameTooltip:Hide()
    HideCast()
    if hovered and not hovered:IsMouseOver() then StopHover() end
end

local function BuildCast()
    castBtn = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
    castBtn:RegisterForClicks("LeftButtonUp", "LeftButtonDown", "RightButtonUp", "RightButtonDown")
    castBtn:SetAttribute("type", "spell")
    -- Above the bag window: at the slot's own strata the slot keeps the mouse.
    castBtn:SetFrameStrata("TOOLTIP")
    local hl = castBtn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.15)
    castBtn:SetScript("OnEnter", CastOnEnter)
    castBtn:SetScript("OnLeave", CastOnLeave)
    castBtn:Hide()
end

local function ShowCast(btn, spell, bag, slot)
    if not castBtn then BuildCast() end
    castBtn:ClearAllPoints()
    castBtn:SetAllPoints(btn)
    castBtn:SetAttribute("spell", spell)
    castBtn:SetAttribute("target-bag", bag)
    castBtn:SetAttribute("target-slot", slot)
    castBtn.owner, castBtn.spell, castBtn.bag, castBtn.slot = btn, spell, bag, slot
    castBtn:Show()
end

-- Alt held over the hovered slot: the cast button goes over it when a spell fits.
function TryAlt()
    if not hovered or InCombatLockdown() or not IsAltKeyDown() then return end
    if not hovered:IsMouseOver() then StopHover(); return end
    local s = slots[hovered]
    local info = s and C_Container.GetContainerItemInfo(s.bag, s.slot)
    local spell = info and info.itemID and SpellFor(s.bag, s.slot, info)
    if spell then ShowCast(hovered, spell, s.bag, s.slot) end
end

local function OnSlotEnter(btn)
    local s = enabled and slots[btn]
    if not s or InCombatLockdown() then return end
    if active then
        if s.spell then ShowCast(btn, s.spell, s.bag, s.slot) end
    else
        hovered = btn
        SyncEvents()
        TryAlt()
    end
end

local function OnSlotLeave(btn)
    -- The cast button over the slot takes the mouse: still on it.
    if hovered == btn and not (castBtn and castBtn.owner == btn) then StopHover() end
end

-------------------------------------------------------------------------------
--  The painter (EUI_Bags.RunItemOverlays), registered while the icon is on
-------------------------------------------------------------------------------
-- The spell icon in a corner, or a shade over the item.
local function Marks(btn)
    local m = marks[btn]
    if m then return m end
    local host = btn._textOverlay
    m = {}
    m.shade = host:CreateTexture(nil, "OVERLAY", nil, 6)
    m.shade:SetAllPoints(host)
    m.shade:SetColorTexture(0, 0, 0, SHADE_ALPHA)
    m.spell = host:CreateTexture(nil, "OVERLAY", nil, 7)
    -- The item's top-right quarter: 16 px on a grid slot, smaller on a List
    -- row's icon, which it would otherwise cover.
    m.spell:SetPoint("TOPRIGHT", host, "TOPRIGHT", -1, -1)
    m.spell:SetPoint("BOTTOMLEFT", host, "CENTER")
    m.spell:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    marks[btn] = m
    return m
end

local function HideMarks(btn)
    local m = marks[btn]
    if m then m.shade:Hide(); m.spell:Hide() end
end

-- Keeps each bag item's place (and, in the mode, its spell and marks).
local function Paint(btn, data)
    local bag, info = data.bag, data.info
    local inBags = bag and bag >= FIRST_BAG and bag <= LAST_BAG
    local s
    if inBags and info and info.itemID then
        s = slots[btn] or {}
        s.bag, s.slot = bag, data.slot
        s.spell = active and SpellFor(bag, data.slot, info) or nil
        slots[btn] = s
        if not hooked[btn] then
            hooked[btn] = true
            btn:HookScript("OnEnter", OnSlotEnter)
            btn:HookScript("OnLeave", OnSlotLeave)
        end
    else
        slots[btn] = nil
    end
    if active and inBags then  -- the bank keeps its look
        local m = Marks(btn)
        local spell = s and s.spell
        if spell then m.spell:SetTexture(C_Spell.GetSpellTexture(spell)) end
        m.spell:SetShown(spell ~= nil)
        m.shade:SetShown(spell == nil)
    else
        HideMarks(btn)
    end
    -- The item under the cast button changed: look again.
    if castBtn and castBtn.owner == btn and not InCombatLockdown() then
        HideCast()
        if btn:IsMouseOver() then OnSlotEnter(btn) end
    end
end

-------------------------------------------------------------------------------
--  The mode and its header icon
-------------------------------------------------------------------------------
local function SyncIconLook()
    local b = EUI_Bags._quickBtn
    if not b then return end
    if active then
        b.icon:SetVertexColor(EUI.GetAccentColor())
    else
        b.icon:SetVertexColor(1, 1, 1)
    end
end

function SetActive(on)
    on = on and true or false
    if on == (active or false) or (on and InCombatLockdown()) then return end
    active = on or nil
    StopHover()
    HideCast()
    if on then
        EUI_Bags:RefreshInventory()  -- only the bag window: the bank keeps its look
    else
        for btn in pairs(marks) do HideMarks(btn) end
        wipe(tipCache)
    end
    SyncEvents()
    SyncIconLook()
end

local function BuildIcon()
    local b = CreateFrame("Button", nil, EUI_Bags._bagsBtn:GetParent())
    b:SetSize(22, 22)
    b.icon = b:CreateTexture(nil, "OVERLAY")
    b.icon:SetAtlas(ICON_ATLAS)
    b.icon:SetSize(18, 18)
    b.icon:SetPoint("CENTER")
    b.icon:SetAlpha(0.9)
    -- The spells by the client's own names (only WoW Forever's Mages
    -- comprehend scrolls).
    local names = {}
    for _, id in ipairs(EUI.IS_FOREVER and { DISENCHANT, PICK_LOCK, COMPREHEND } or { DISENCHANT, PICK_LOCK }) do
        names[#names + 1] = C_Spell.GetSpellName(id)
    end
    local tip = EllesmereUI.Lf("Highlights the items your spells can work on (%s). Click a matching item while this mode is on, or Alt-click it. Out of combat only.", table.concat(names, ", "))
    b:SetScript("OnEnter", function(self)
        self.icon:SetAlpha(1)
        EUI.ShowWidgetTooltip(self, active and EllesmereUI.L("Leave Quick Actions.") or tip)
    end)
    b:SetScript("OnLeave", function(self)
        self.icon:SetAlpha(0.9)
        EUI.HideWidgetTooltip()
    end)
    b:SetScript("OnClick", function()
        EUI.HideWidgetTooltip()
        SetActive(not active)
    end)
    EUI_Bags._quickBtn = b
end

local function SyncEnabled(on)
    if on == (enabled or false) then return end
    enabled = on or nil
    if on then
        if not hideHooked then
            hideHooked = true
            EUI_Bags:HookScript("OnHide", function()
                SetActive(false)
                HideCast()
                StopHover()
            end)
        end
        EUI_Bags.RegisterItemOverlayIcon("EUI_QuickActions", Paint)
        if EUI_Bags:IsShown() then EUI_Bags:RefreshInventory() end
    else
        SetActive(false)
        EUI_Bags.UnregisterItemOverlayIcon("EUI_QuickActions")
        StopHover()
        HideCast()
        wipe(slots)
    end
end

-- Called by EUI_Bags:SyncHeaderIcons: places the icon left of prev while the
-- Quick Actions Icon is on, and returns it then.
function ns.SyncQuickActionsIcon(prev, gap)
    local on = BP().bagShowQuickIcon == true
    SyncEnabled(on)
    if on and not EUI_Bags._quickBtn then BuildIcon() end
    local b = EUI_Bags._quickBtn
    if not b then return nil end
    b:ClearAllPoints()
    b:SetPoint("RIGHT", prev, "LEFT", -gap, 0)
    b:SetShown(on)
    return on and b or nil
end
