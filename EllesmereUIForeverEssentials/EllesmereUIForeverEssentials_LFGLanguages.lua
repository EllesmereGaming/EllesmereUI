if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_LFGLanguages.lua  (WoW Forever only)
--  Choose Languages: a submenu in the cog menu of the Looking For Group window,
--  always there (no setting). Each language ticked or unticked there searches
--  again, in the client's language and the ticked ones. None is ticked at the
--  start, so nothing changes until the player ticks one. The window shows the
--  results as its own, and its own search or refresh goes back to the client's
--  language, so Search Ticked Languages, the submenu's first line, repeats the
--  wider search in one click. Nothing runs until the cog menu opens.
--
--  The window's search passes no language, so the client's alone is searched,
--  whatever the saved language filter. C_LFGList.Search takes one call per
--  click: the window's own buttons use theirs, so the search runs from a
--  click of ours, in the menu's official extension point (its tag).
-------------------------------------------------------------------------------
local _, module = ...

-- Settings live in EllesmereUIDB.lfgLanguages:
--   on        { [locale] = true }: languages ticked in the submenu
local F = module.Feature("lfgLanguages", {})

-- The client's language is always searched; the others once ticked.
local function IsWanted(lang)
    if C_LFGList.GetDefaultLanguageSearchFilter()[lang] then return true end
    local on = F.Read().on
    return on and on[lang] or false
end

-- Whether any language is ticked (the client's is never stored).
local function AnyTicked()
    local on = F.Read().on
    return on ~= nil and next(on) ~= nil
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
    c.on = c.on or {}
    c.on[lang] = not c.on[lang] or nil
    SearchLanguages()
end

local function AddMenuEntries(_, root)
    root:CreateDivider()
    local sub = root:CreateButton(EllesmereUI.L("Choose Languages"))
    -- Greyed while nothing is ticked; a tick refreshes the submenu, which asks again.
    local search = sub:CreateButton(EllesmereUI.L("Search Ticked Languages"), SearchLanguages)
    search:SetEnabled(AnyTicked)
    sub:CreateDivider()
    local defaults = C_LFGList.GetDefaultLanguageSearchFilter()
    for _, lang in ipairs(C_LFGList.GetAvailableLanguageSearchFilter()) do
        -- The game's own language names.
        local name = _G["LFG_LIST_LANGUAGE_" .. lang:upper()] or lang
        local box = sub:CreateCheckbox(name, IsWanted, ToggleWanted, lang)
        if defaults[lang] then box:SetEnabled(false) end
    end
end

-- Added once at login; the menu asks for the entries each time it opens.
F.Start(function()
    Menu.ModifyMenu("MENU_LFG_LISTING_SETTINGS", AddMenuEntries)
end)
