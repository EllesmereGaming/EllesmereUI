if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIQoL_ItemIcons_Track.lua
--  Item Icons upgrade track: the upgradeTrack element and the optional icon at
--  the start of Blizzard's "Upgrade Level" tooltip line. Both draw Blizzard's
--  profession quality icon of the track's tier, desaturated and tinted with the
--  track's style color. Retail only: the core never draws the element on WoW
--  Forever, and the tooltip hook is not installed there.
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI
local II = EllesmereUI.ItemIcons

local function Tier(n) return "Professions-ChatIcon-Quality-Tier" .. n end
-- Canonical track key (EllesmereUI.GetUpgradeTrackKey) -> quality icon. The
-- icons have five tiers: Hero and Myth share the top one, told apart by color.
local TRACK_ATLAS = {
    Explorer = Tier(1), Adventurer = Tier(2), Veteran = Tier(3),
    Champion = Tier(4), Hero = Tier(5), Myth = Tier(5),
}

II.RegisterElement("upgradeTrack", {
    kind = "icon",
    Apply = function(item, style, out)
        local key = EllesmereUI.GetUpgradeTrackKey(item.link)
        local atlas = key and TRACK_ATLAS[key]
        if not atlas then return false end
        local c = style[key]
        out.atlas, out.desaturate = atlas, true
        out.r, out.g, out.b = c.r, c.g, c.b
        return true
    end,
})

-------------------------------------------------------------------------------
--  Tooltip icon
-------------------------------------------------------------------------------
-- Inline markup cannot desaturate, so the line starts with a transparent
-- spacer, and a texture drawn like the element sits over its left part. The
-- spacer is ICON_GAP px wider than the icon, a gap before the text. The line
-- box makes room for descenders: ICON_RAISE (of the font size) lifts the icon
-- to the middle of the capitals.
local SPACER = "Interface\\AddOns\\EllesmereUI\\media\\textures\\blank.tga"
local ICON_GAP, ICON_RAISE = 3, 0.1
-- Blizzard's item tooltips the icon shows on: hover, compare, chat link and the
-- embedded item tooltips (quest rewards). Other GameTooltips, such as addons'
-- scanning tooltips, keep Blizzard's text
local iconTooltips
local icons = {}  -- tooltip -> its icon texture

local function IconOn() return II.IsEnabled() and II.GetSettings().tooltipTrackPip end

local function HideIcon(tooltip) icons[tooltip]:Hide() end

-- The tooltip's icon, built on first use and hidden whenever the tooltip clears
local function Icon(tooltip)
    local icon = icons[tooltip]
    if not icon then
        icon = tooltip:CreateTexture(nil, "OVERLAY")
        icons[tooltip] = icon
        tooltip:HookScript("OnTooltipCleared", HideIcon)
    end
    return icon
end

-- Item post-call: rebuilds the "Upgrade Level" line from the item's upgrade
-- info with the icon in front; the tooltip's own text is never read.
-- lineData.lineIndex is the tooltip line the processor added for that data line.
local function AddTooltipIcon(tooltip, data)
    if not (iconTooltips[tooltip] and IconOn()) then return end
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

    local link = II.TooltipItemLink(data)
    if type(link) ~= "string" or link == "" then return end
    local info = C_Item.GetItemUpgradeInfo(link)
    local key = info and EllesmereUI.UPGRADE_TRACK_KEYS[info.trackString or ""]
    local atlas = key and TRACK_ATLAS[key]
    if not atlas then return end
    local line = tooltip:GetLeftLine(index)
    -- Sized to the line's text, as wide as the atlas's aspect
    local _, fontSize = line:GetFont()
    fontSize = fontSize or 12
    local h = math.floor(fontSize + 0.5) + 2
    local size = C_Texture.GetAtlasInfo(atlas)
    local w = math.floor(h * size.width / size.height + 0.5)
    local text = ITEM_UPGRADE_TOOLTIP_FORMAT_STRING:format(info.trackString, info.currentLevel, info.maxLevel)
    line:SetText(("|T%s:%d:%d|t %s"):format(SPACER, h, w + ICON_GAP, text))

    local c = II.GetSettings().styles.upgradeTrack[key]
    local icon = Icon(tooltip)
    icon:SetAtlas(atlas)
    icon:SetDesaturated(true)
    icon:SetVertexColor(c.r, c.g, c.b)
    icon:SetSize(w, h)
    icon:ClearAllPoints()
    icon:SetPoint("LEFT", line, "LEFT", 0, math.floor(fontSize * ICON_RAISE + 0.5))
    icon:Show()
end

-- Installed on the first apply with Item Icons and the tooltip icon on. A
-- post-call cannot be removed: AddTooltipIcon returns at once while either is off.
II.Subscribe(function()
    if iconTooltips or not (II.IsElementAvailable("upgradeTrack") and IconOn()) then return end
    iconTooltips = {
        [GameTooltip] = true, [ShoppingTooltip1] = true, [ShoppingTooltip2] = true,
        [ItemRefTooltip] = true, [ItemRefShoppingTooltip1] = true, [ItemRefShoppingTooltip2] = true,
    }
    -- The GameTooltip inside each ItemTooltip (InternalEmbeddedItemTooltipTemplate)
    for _, host in pairs({ GameTooltip, EmbeddedItemTooltip }) do
        local embedded = host.ItemTooltip and host.ItemTooltip.Tooltip
        if embedded then iconTooltips[embedded] = true end
    end
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, AddTooltipIcon)
end)
