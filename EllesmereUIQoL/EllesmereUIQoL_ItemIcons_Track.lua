if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIQoL_ItemIcons_Track.lua
--  Item Icons upgrade track: the upgradeTrack element (1 to 5 pips tinted
--  with the track's style color) and the optional pip at the start of
--  Blizzard's "Upgrade Level" tooltip line. Retail only: the core never draws
--  the element on WoW Forever, and the tooltip hook is not installed there.
--  Pip art: Media/track_pips_1..5.tga, white pips with a dark rim, on
--  transparent (.tools/track-pips/make_pips.py).
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI
local II = EllesmereUI.ItemIcons

local function Pips(n) return "Interface\\AddOns\\EllesmereUIQoL\\Media\\track_pips_" .. n .. ".tga" end
-- Canonical track key (EllesmereUI.GetUpgradeTrackKey) -> pip image. Explorer,
-- the legacy track, is one pip in its gray style color.
local PIP_FILE = {
    Explorer = Pips(1), Adventurer = Pips(1), Veteran = Pips(2),
    Champion = Pips(3), Hero = Pips(4), Myth = Pips(5),
}

II.RegisterElement("upgradeTrack", {
    kind = "icon",
    Apply = function(item, style, out)
        local key = EllesmereUI.GetUpgradeTrackKey(item.link)
        local file = key and PIP_FILE[key]
        if not file then return false end
        local c = style[key]
        out.texture = file
        out.r, out.g, out.b = c.r, c.g, c.b
        return true
    end,
})

-------------------------------------------------------------------------------
--  Tooltip pip
-------------------------------------------------------------------------------
-- Inline texture: line height, the whole 64 px image, tinted (0-255)
local PIP_MARKUP = "|T%s:0:0:0:0:64:64:0:64:0:64:%d:%d:%d|t %s"
-- Blizzard's item tooltips the pip shows on: hover, compare, chat link and the
-- embedded item tooltips (quest rewards). Other GameTooltips, such as addons'
-- scanning tooltips, keep Blizzard's text
local pipTooltips

local function PipOn() return II.IsEnabled() and II.GetSettings().tooltipTrackPip end

local function Byte(v) return math.floor(v * 255 + 0.5) end

-- The tooltip's item link, found as TooltipUtil.GetDisplayedItem finds it
local function DisplayedLink(data)
    local guid, link = data.guid, data.hyperlink
    if issecretvalue(guid) or issecretvalue(link) then return nil end
    if guid then return C_Item.GetItemLinkByGUID(guid) end
    return link
end

-- Item post-call: rebuilds the "Upgrade Level" line from the item's upgrade
-- info with the pip in front; the tooltip's own text is never read.
-- lineData.lineIndex is the tooltip line the processor added for that data line.
local function AddTooltipPip(tooltip, data)
    if not (pipTooltips[tooltip] and PipOn()) then return end
    if issecretvalue(data.id) then return end
    local upgradeLine = Enum.TooltipDataLineType.ItemUpgradeLevel
    local index
    local lines = data.lines
    for i = 1, #lines do
        local lineType = lines[i].type
        if not issecretvalue(lineType) and lineType == upgradeLine then
            index = lines[i].lineIndex
            break
        end
    end
    if type(index) ~= "number" or issecretvalue(index) then return end
    -- A tooltip anchored under a restricted owner rejects every call; a
    -- pcall'd read is the only probe (as the EUI tooltip skin does)
    local ok, width = pcall(tooltip.GetWidth, tooltip)
    if not ok or issecretvalue(width) or index > tooltip:NumLines() then return end

    local link = DisplayedLink(data)
    if type(link) ~= "string" or link == "" then return end
    local info = C_Item.GetItemUpgradeInfo(link)
    local key = info and EllesmereUI.UPGRADE_TRACK_KEYS[info.trackString or ""]
    local file = key and PIP_FILE[key]
    if not file then return end
    local c = II.GetSettings().styles.upgradeTrack[key]
    local text = ITEM_UPGRADE_TOOLTIP_FORMAT_STRING:format(info.trackString, info.currentLevel, info.maxLevel)
    tooltip:GetLeftLine(index):SetText(PIP_MARKUP:format(file, Byte(c.r), Byte(c.g), Byte(c.b), text))
end

-- Installed on the first apply with Item Icons and the tooltip pip on. A
-- post-call cannot be removed: AddTooltipPip returns at once while either is off.
II.Subscribe(function()
    if pipTooltips or not (II.IsElementAvailable("upgradeTrack") and PipOn()) then return end
    pipTooltips = {
        [GameTooltip] = true, [ShoppingTooltip1] = true, [ShoppingTooltip2] = true,
        [ItemRefTooltip] = true, [ItemRefShoppingTooltip1] = true, [ItemRefShoppingTooltip2] = true,
    }
    -- The GameTooltip inside each ItemTooltip (InternalEmbeddedItemTooltipTemplate)
    for _, host in pairs({ GameTooltip, EmbeddedItemTooltip }) do
        local embedded = host.ItemTooltip and host.ItemTooltip.Tooltip
        if embedded then pipTooltips[embedded] = true end
    end
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, AddTooltipPip)
end)
