if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_LFGLanguages.lua  (WoW Forever only)
--  Search Other Languages: a Choose Languages submenu in the cog menu of the
--  Looking For Group window. Each language ticked or unticked there searches
--  again, in the languages ticked (all by default), not only the client's. The
--  window shows the results as its own.
--
--  The window's search passes no language, so the client's alone is searched,
--  whatever the saved language filter. C_LFGList.Search takes one call per
--  click: the window's own buttons use theirs, so the search runs from a
--  click of ours, in the menu's official extension point (its tag).
-------------------------------------------------------------------------------
local _, module = ...

-- Settings live in EllesmereUIDB.lfgLanguages; unset keys read these.
--   enabled   Search Other Languages
--   off       { [locale] = true }: languages turned off in the submenu
local F = module.Feature("lfgLanguages", { enabled = false })

local added = false

-- The client's language is always searched; the others unless turned off.
local function IsWanted(lang)
    if C_LFGList.GetDefaultLanguageSearchFilter()[lang] then return true end
    local off = F.Read().off
    return not (off and off[lang])
end

-- The window's search (LFGBrowse_DoSearch), with the wanted languages.
local function SearchLanguages()
    local browse = LFGBrowseFrame
    if not browse or browse.searching then return end
    local categoryID = browse.CategoryDropdown:GetValue()
    if not categoryID or categoryID <= 0 then return end
    local activityIDs = browse.ActivityDropdown.selectedValues
    if not activityIDs or #activityIDs == 0 then
        activityIDs = LFGUtil_GetFilteredActivities(categoryID)
    end
    local languages = {}
    for _, lang in ipairs(C_LFGList.GetAvailableLanguageSearchFilter()) do
        if IsWanted(lang) then languages[lang] = true end
    end
    C_LFGList.Search(categoryID, 0, 0, languages, false, nil, activityIDs)
end

-- A tick is a click: it searches again at once.
local function ToggleWanted(lang)
    local c = F.Cfg()
    c.off = c.off or {}
    c.off[lang] = not c.off[lang] or nil
    SearchLanguages()
end

local function AddMenuEntries(_, root)
    if not F.Enabled() then return end
    root:CreateDivider()
    local sub = root:CreateButton(EllesmereUI.L("Choose Languages"))
    local defaults = C_LFGList.GetDefaultLanguageSearchFilter()
    for _, lang in ipairs(C_LFGList.GetAvailableLanguageSearchFilter()) do
        -- The game's own language names.
        local name = _G["LFG_LIST_LANGUAGE_" .. lang:upper()] or lang
        local box = sub:CreateCheckbox(name, IsWanted, ToggleWanted, lang)
        if defaults[lang] then box:SetEnabled(false) end
    end
end

-- Menu.ModifyMenu cannot be undone: added once, its entries follow the setting.
local function Apply()
    if added or not F.Enabled() then return end
    if not (C_LFGList and Menu and Menu.ModifyMenu) then return end
    added = true
    Menu.ModifyMenu("MENU_LFG_LISTING_SETTINGS", AddMenuEntries)
end

-- Options-page entry points.
EllesmereUI._LFGLanguages = {
    Get = F.Get,
    Cfg = F.Cfg,
    Apply = Apply,
}

F.Start(Apply)
