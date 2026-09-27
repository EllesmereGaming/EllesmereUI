if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIShoppingList_Tooltip.lua
--  "Shopping List: 6 / 10" on the tooltip of any item the list needs (a
--  tracked reagent or vendor item), with the green check once you have enough.
--
--  Through TooltipDataProcessor, guarded the way EUI's own item hooks are: a
--  client without it gets no tooltip line (the old OnTooltipSetItem script is
--  gone on both clients, so there is no fallback). The post-call is installed
--  the first time the feature turns on and does nothing while it is off.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local EUI = ns.EUI
local Get = ns.Get

local installed = false

local function Line(tooltip, data)
    if not ns.IsOn("tooltip") then return end
    if not (data and data.id) or issecretvalue(data.id) then return end
    if not (tooltip and tooltip.AddDoubleLine) then return end
    local itemID = data.id
    local reagent, vendor = ns.needByItem[itemID], ns.vendorNeed and ns.vendorNeed[itemID]
    if not (reagent or vendor) then return end
    local need = (reagent and reagent.need or 0) + (vendor and vendor.need or 0)
    -- The same bags count for both; a live read, the list may be a frame behind.
    local have = ns.CountItem(itemID)
    if reagent and reagent.alts then
        for _, id in ipairs(reagent.alts) do have = have + ns.CountItem(id) end
    end
    local text = ns.FormatCount(have, need)
    if have >= need then text = ns.CHECK .. " " .. text end
    tooltip:AddDoubleLine(EUI.L("Shopping List"), text, 1, 0.82, 0, 1, 1, 1)
    tooltip:Show()
end

ns.RegisterFeature({
    key = "tooltip",
    isOn = function() return Get("tooltipLine") end,
    enable = function()
        if installed then return end
        if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
            installed = true
            TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, Line)
        end
    end,
})
