if EUI_CLIENT_BLOCKED then return end
local EUI = EllesmereUI
if EUI.IS_FOREVER then return end

local enabled, installed = false, false
local qualities

local function OnUpgradeLine(tooltip, fallback)
    if not enabled or tooltip:IsForbidden() or tooltip:IsProtected() then return end
    local processing = tooltip:GetProcessingTooltipInfo()
    if not canaccessallvalues(processing) or not processing then return end
    local data = processing.tooltipData
    if not canaccessallvalues(data) or not data then return end
    -- Appended item data must not annotate the primary item's tooltip twice.
    if tooltip:GetPrimaryTooltipData() ~= data then return end
    if not canaccessallvalues(data.guid, data.hyperlink, data.overrideItemLevel) then return end
    -- Preview overrides can differ from the hyperlink's actual item level.
    if data.overrideItemLevel and data.overrideItemLevel > 0 then return end
    local link = data.hyperlink
    if data.guid and data.guid ~= "" then link = C_Item.GetItemLinkByGUID(data.guid) end
    if not canaccessallvalues(link) or type(link) ~= "string" or link == "" then return end

    local calc = EUIUpgCalc
    if not calc or not calc.GetItemUpgradeRange then return end
    if fallback then
        if not calc:GetAscendantBonus(link) or not canaccessallvalues(data.lines) or not data.lines then return end
        for _, line in ipairs(data.lines) do
            if not canaccessallvalues(line) then return end
            if not canaccessallvalues(line.type) then return end
            if line.type == Enum.TooltipDataLineType.ItemUpgradeLevel then return end
        end
    end
    local info = C_Item.GetItemUpgradeInfo(link)
    if not canaccessallvalues(info) then return end
    local rank, maxRank, cap, name
    if info then rank, maxRank, cap, name = info.currentLevel, info.maxLevel, info.maxItemLevel, info.trackString end
    if not canaccessallvalues(rank, maxRank, cap, name) then return end

    local level = C_Item.GetDetailedItemLevelInfo(link)
    if not canaccessallvalues(level) then return end

    local key = EUI.UPGRADE_TRACK_KEYS[name or ""]
    -- shortcut: leave unmatched seasons/tracks unchanged; update shared calculator data for new seasons.
    local minLevel, maxLevel, displayRank, displayMax, ascendant = calc:GetItemUpgradeRange(link, key, rank, maxRank, level, cap)
    if not minLevel then return end
    key = key or (ascendant and ascendant.track)
    if not name or name == "" then name = EUI.L(key) end
    local quality = qualities[key]
    if not quality then return end
    local r, g, b = C_Item.GetItemQualityColor(quality)
    local text = EllesmereUI.Lf("%d/%d %s |cffffffff(%d-%d)|r", displayRank, displayMax, name, minLevel, maxLevel)
    if displayRank < displayMax then
        local currency = C_CurrencyInfo.GetCurrencyInfo(calc.Data.tracks[key].currID)
        if canaccessallvalues(currency) and currency
            and canaccessallvalues(currency.name, currency.iconFileID) and currency.name then
            local crest = currency.name
            if currency.iconFileID then
                crest = CreateSimpleTextureMarkup(currency.iconFileID, 14, 14) .. " " .. crest
            end
            tooltip:AddDoubleLine(text, crest, r, g, b, 1, 1, 1)
            return true
        end
    end
    tooltip:AddLine(text, r, g, b)
    return true
end

-- Login, option changes and profile swaps share this lazy registration path.
function EUI._applyUpgradeTooltips()
    enabled = EUI.QoLExtrasGet("upgradeTooltips") == true
    -- Blizzard exposes no removal API; disabling leaves only the enabled guard.
    if enabled and not installed then
        installed = true
        qualities = {
            Explorer = Enum.ItemQuality.Poor, Adventurer = Enum.ItemQuality.Common,
            Veteran = Enum.ItemQuality.Uncommon, Champion = Enum.ItemQuality.Rare,
            Hero = Enum.ItemQuality.Epic, Myth = Enum.ItemQuality.Legendary,
        }
        -- Consume only the upgrade line; do not mutate Blizzard's tooltip data or font strings.
        TooltipDataProcessor.AddLinePreCall(Enum.TooltipDataLineType.ItemUpgradeLevel, function(tooltip)
            return OnUpgradeLine(tooltip)
        end)
        -- Terminal upgrades may omit the native upgrade line entirely.
        TooltipDataProcessor.AddLinePostCall(Enum.TooltipDataLineType.ItemLevel, function(tooltip)
            OnUpgradeLine(tooltip, true)
        end)
    end
end
