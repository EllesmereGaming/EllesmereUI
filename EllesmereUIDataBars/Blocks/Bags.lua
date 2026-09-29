if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- Blocks\Bags.lua
-- Bag space block factory.

local ADDON_NAME, ns = ...
local L = ns.L
local MEDIA = ns.MEDIA
local K = ns.BlockKit

-- Upvalues
local CreateFrame = CreateFrame
local C_Container = C_Container
local floor       = math.floor
local max         = math.max
local min         = math.min

local ICON_GAP             = K.ICON_GAP
local CONTENT_BASE         = K.CONTENT_BASE
local InstKey              = K.InstKey
local MakeEventFrame       = K.MakeEventFrame
local RegisterInstEvents   = K.RegisterInstEvents
local UnregisterInstEvents = K.UnregisterInstEvents
local HBudget              = K.HBudget
local VSlotW               = K.VSlotW
local MaybeRelayout        = K.MaybeRelayout
local AttachTextOffset     = K.AttachTextOffset
local BlockColorOf         = K.BlockColorOf
local IconColorOf          = K.IconColorOf

-- Backpack + four bag slots; the reagent bag is opt-in per block.
local LAST_BAG    = NUM_BAG_SLOTS or 4
local REAGENT_BAG = Enum.BagIndex.ReagentBag

-- Low space text color default (soft red, matches durability's low tint).
local LOW_R, LOW_G, LOW_B = 1, 0.35, 0.35
ns.BAGS_LOW_COLOR = { LOW_R, LOW_G, LOW_B }

-------------------------------------------------------------------------------
--  BAGS (free / used slot counts)
-------------------------------------------------------------------------------
ns.BlockFactories.bags = function(blockCfg, slot, content, barCtx)
    local inst = { cfg = blockCfg, slot = slot, content = content, ctx = barCtx }
    inst.key = InstKey(barCtx, blockCfg)
    -- BAG_UPDATE_DELAYED: one event per batch of bag changes, not one per bag.
    inst.events = { "BAG_UPDATE_DELAYED", "PLAYER_ENTERING_WORLD" }

    local BAG_TEX = MEDIA .. "lootbag.png"
    local mouseOver = false

    local function D() return blockCfg.settings or {} end
    local function BC() return barCtx.cfg end

    local button = CreateFrame("Button", nil, content)
    button:SetAllPoints()
    button:EnableMouse(true)
    button:RegisterForClicks("AnyUp")

    local icon = button:CreateTexture(nil, "OVERLAY")
    icon:SetTexture(BAG_TEX)
    local bagText = button:CreateFontString(nil, "OVERLAY")
    AttachTextOffset(inst, bagText)

    local function IncludeBag(bag)
        return bag ~= REAGENT_BAG or D().reagent == true
    end

    -- Returns free, total across the counted bags. Only general-purpose bags
    -- (family 0, as Blizzard's own free-space checks count): a quiver, soul
    -- bag or profession bag cannot take ordinary loot.
    local function Count()
        local free, total = 0, 0
        for bag = 0, LAST_BAG do
            local nFree, family = C_Container.GetContainerNumFreeSlots(bag)
            if not family or family == 0 then
                total = total + (C_Container.GetContainerNumSlots(bag) or 0)
                free = free + (nFree or 0)
            end
        end
        if IncludeBag(REAGENT_BAG) then
            total = total + (C_Container.GetContainerNumSlots(REAGENT_BAG) or 0)
            free = free + (C_Container.GetContainerNumFreeSlots(REAGENT_BAG) or 0)
        end
        return free, total
    end

    -- The counts on screen, from whichever path painted last (an event, a
    -- hover, a settings change): the event gate compares against these.
    local lastFree, lastTotal

    function inst:Refresh()
        local s = D()
        local barCfg = BC()
        local barH = barCtx.GetThickness()
        local fontSize = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))
        local isSide = barCtx.IsVertical()

        local free, total = Count()
        lastFree, lastTotal = free, total
        local mode = s.value or "free"
        local text
        if mode == "used" then
            text = tostring(total - free)
        elseif mode == "usedTotal" then
            text = (total - free) .. "/" .. total
        elseif mode == "freeTotal" then
            text = free .. "/" .. total
        else
            text = tostring(free)
        end

        local iconSz = 0
        -- +4: matches the gold block's bag icon.
        if s.showIcon ~= false then
            iconSz = fontSize + 4
            icon:Show()
        else
            icon:Hide()
        end

        ns.SetFont(bagText, fontSize, barCfg)
        icon:SetVertexColor(IconColorOf(blockCfg))
        local low = s.lowThreshold or 0
        if mouseOver then
            bagText:SetTextColor(ns.GetAccent())
        elseif low > 0 and free < low then
            local c = s.lowColor
            if c then
                bagText:SetTextColor(c.r or LOW_R, c.g or LOW_G, c.b or LOW_B)
            else
                bagText:SetTextColor(LOW_R, LOW_G, LOW_B)
            end
        else
            bagText:SetTextColor(BlockColorOf(blockCfg))
        end

        if isSide then
            local slotW = VSlotW(inst)
            local innerW = max(24, slotW - 8)
            bagText:SetText(text)
            local totalH = 8
            if iconSz > 0 then
                icon:SetSize(iconSz, iconSz)
                icon:ClearAllPoints()
                icon:SetPoint("TOP", button, "TOP", 0, -4)
                totalH = totalH + iconSz + 2
            end
            ns.SetWrappedText(bagText, innerW, "CENTER")
            bagText:ClearAllPoints()
            if iconSz > 0 then
                bagText:SetPoint("TOP", icon, "BOTTOM", 0, -2)
            else
                bagText:SetPoint("TOP", button, "TOP", 0, -4)
            end
            totalH = totalH + ns.SnapToPixelGrid(bagText:GetStringHeight()) + 4
            totalH = max(totalH, barH)
            content:SetSize(slotW, totalH)
            button:SetSize(slotW, totalH)
        else
            local slotW = HBudget(inst, 120)
            ns.ResetInlineText(bagText, "LEFT")
            bagText:SetText(text)
            if iconSz > 0 then
                icon:SetSize(iconSz, iconSz)
                icon:ClearAllPoints()
                icon:SetPoint("LEFT", button, "LEFT", 0, 0)
            end
            bagText:ClearAllPoints()
            local xOff = 0
            if iconSz > 0 then xOff = iconSz + ICON_GAP - 2 end
            bagText:SetPoint("LEFT", button, "LEFT", xOff, 0)
            local tw = ns.SnapToPixelGrid(bagText:GetStringWidth())
            local totalW = min(slotW, xOff + tw + 4)
            content:SetSize(max(totalW, 10), barH)
            button:SetSize(max(totalW, 10), barH)
        end

        MaybeRelayout(inst)
    end

    local function AddBagRow(bag)
        local n = C_Container.GetContainerNumSlots(bag) or 0
        if n <= 0 then return end
        local used = n - (C_Container.GetContainerNumFreeSlots(bag) or 0)
        ns.Tip_AddDouble(C_Container.GetBagName(bag) or ("#" .. bag), used .. "/" .. n,
            0.6, 0.6, 0.6, 1, 1, 1)
    end

    local function ShowBagsTooltip()
        local ar, ag, ab = ns.GetAccent()
        local free, total = Count()
        ns.Tip_Begin(button)
        ns.Tip_AddLine(L["BAGS"], 1, 1, 1)
        ns.Tip_AddLine(" ")
        for bag = 0, LAST_BAG do AddBagRow(bag) end
        if IncludeBag(REAGENT_BAG) then AddBagRow(REAGENT_BAG) end
        ns.Tip_AddLine(" ")
        ns.Tip_AddDouble(L["FREE"], free .. "/" .. total, 1, 1, 1, 1, 1, 1)
        ns.Tip_AddLine(" ")
        ns.Tip_AddDouble(L["LEFT_CLICK"], L["OPEN_BAGS"], 1, 1, 1, ar, ag, ab)
        ns.Tip_Show()
    end

    button:SetScript("OnEnter", function()
        mouseOver = true
        inst:Refresh()
        ShowBagsTooltip()
    end)
    button:SetScript("OnLeave", function()
        mouseOver = false
        ns.Tip_Hide(button)
        inst:Refresh()
    end)
    button:SetScript("OnClick", function(_, mb)
        if mb == "LeftButton" then ToggleAllBags() end
    end)

    -- Most bag batches (a potion, stacking, sorting) leave the counts on
    -- screen unchanged, and those skip the repaint.
    inst.eventFrame = MakeEventFrame(inst, function(self, event)
        if event == "BAG_UPDATE_DELAYED" then
            local free, total = Count()
            if free == lastFree and total == lastTotal then return end
        end
        self:Refresh()
    end)

    function inst:Enable()
        lastFree, lastTotal = nil, nil
        content:Show()
        RegisterInstEvents(self)
    end

    function inst:Disable()
        UnregisterInstEvents(self)
        content:Hide()
    end

    function inst:GetAutoLength()
        if barCtx.IsVertical() then
            return max(content:GetHeight() or 40, 30)
        end
        return max(content:GetWidth() or 40, 24)
    end

    function inst:Destroy()
        self._dead = true
        UnregisterInstEvents(self)
        content:Hide()
    end

    return inst
end
