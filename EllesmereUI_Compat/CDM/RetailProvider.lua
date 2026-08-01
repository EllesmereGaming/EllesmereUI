local addonName, ns = ...
local EUICompat = _G.EUICompat

if EUICompat.IsWotLK then return end

local RetailProvider = setmetatable({}, { __index = EUICompat.CDM.ProviderBase })
RetailProvider.__index = RetailProvider

function RetailProvider:New()
    local p = EUICompat.CDM.ProviderBase.New(self)
    setmetatable(p, RetailProvider)
    return p
end

-- Fallback to the native API for Retail for now, mapping the categories
local CatMap = {
    [1] = EUICompat.CDM_CATEGORY_ESSENTIAL,
    [2] = EUICompat.CDM_CATEGORY_UTILITY,
    [3] = EUICompat.CDM_CATEGORY_BUFF_ICON,
    [4] = EUICompat.CDM_CATEGORY_BUFF_BAR,
}
local RevCatMap = {
    [EUICompat.CDM_CATEGORY_ESSENTIAL] = 1,
    [EUICompat.CDM_CATEGORY_UTILITY]   = 2,
    [EUICompat.CDM_CATEGORY_BUFF_ICON] = 3,
    [EUICompat.CDM_CATEGORY_BUFF_BAR]  = 4,
}

-- Wrapping C_CooldownViewer for now just to pass through so we can refactor EUI code
function RetailProvider:GetEntries(category, includeUnknown)
    if not C_CooldownViewer or not C_CooldownViewer.GetCooldownViewerCategorySet then return {} end
    local retailCat = RevCatMap[category] or category
    local ids = C_CooldownViewer.GetCooldownViewerCategorySet(retailCat, includeUnknown) or {}

    local entries = {}
    for i, id in ipairs(ids) do
        local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(id)
        if info then
            -- Create a fake "definition" that matches what WotLK will use
            table.insert(entries, {
                cooldownID = id,
                category = category,
                spellID = info.spellID,
                overrideSpellID = info.overrideSpellID,
                iconSpellID = info.overrideSpellID or info.spellID,
            })
        end
    end
    return entries
end

function RetailProvider:GetEntry(cooldownID)
    if not C_CooldownViewer or not C_CooldownViewer.GetCooldownViewerCooldownInfo then return nil end
    local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)
    if info then
        return {
            cooldownID = cooldownID,
            spellID = info.spellID,
            overrideSpellID = info.overrideSpellID,
            iconSpellID = info.overrideSpellID or info.spellID,
        }
    end
    return nil
end

-- Retail will still mostly use its frames natively for runtime state,
-- but this stub allows standardizing API access.
function RetailProvider:GetRuntimeState(cooldownID)
    return {
        cooldownID = cooldownID,
    }
end

EUICompat.CDM.RetailProvider = RetailProvider

EUICompat.CDM.ActiveProvider = RetailProvider:New()
