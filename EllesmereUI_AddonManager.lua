if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_AddonManager.lua
--
--  Addon Manager. The profile says which addons are on by default and, per
--  character, which ones differ (an override). The manager shows both and
--  brings this character's addons in line with them.
--
--  Storage (active profile root):
--    profile.addonManager = {
--        defaults = { [addon] = true|false },   -- every character; absent = not managed
--        chars    = { ["Name - Realm"] = { class = classFile,
--                                          overrides = { [addon] = true|false } } },
--        menu     = true,                       -- the game menu's AddOns button opens it
--        quiet    = true,                       -- no offer to apply at login
--        usage    = true,                       -- the page shows CPU and memory
--        categories = { "Name", ... },          -- the categories made here
--        catOf    = { [addon] = "Name" | false }, -- where an addon was put by hand
--                                                 -- (false: uncategorized); absent = the
--                                                 -- category its own .toc declares
--    }
--  What a character wants for an addon is its override, else the default, else
--  whatever the game has for it.
--
--  The game keeps one enabled state per character and applies a change at the
--  next reload. Applying stages the differences for THIS character with
--  C_AddOns.EnableAddOn / DisableAddOn, as the game's own AddOn list does,
--  saves them and reloads; a reload has to be asked for from a click
--  (EllesmereUI.RequestReload). Another character is brought in line when it
--  logs in: one offer per login, and only while something differs.
--  EllesmereUI itself is never switched off from here.
--
--  Nothing runs until the manager has been opened once: the profile has no
--  addonManager table before that, and the login check then has nothing to do.
-------------------------------------------------------------------------------
local AM = {}
EllesmereUI.AddonManager = AM

local CORE = "EllesmereUI"   -- the framework: every other module depends on it
local NONE = Enum.AddOnEnableState.None

-------------------------------------------------------------------------------
--  Data
-------------------------------------------------------------------------------
local function Store(create)
    local prof = EllesmereUI.GetActiveProfileData()
    if not prof then return nil end
    local s = prof.addonManager
    if not s then
        if not create then return nil end
        s = {}
        prof.addonManager = s
    end
    s.defaults = s.defaults or {}
    s.chars = s.chars or {}
    s.categories = s.categories or {}
    s.catOf = s.catOf or {}
    return s
end

local function CharKey()
    return UnitName("player") .. " - " .. GetRealmName()
end

-- This character in the store, with the class its name is coloured by.
local function Remember(s)
    local key = CharKey()
    local c = s.chars[key]
    if not c then
        c = {}
        s.chars[key] = c
    end
    c.overrides = c.overrides or {}
    c.class = select(2, UnitClass("player"))
    return c
end

-- A title without colour codes and textures, trimmed.
local function Plain(text)
    text = (text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Every addon the game lists, by title: { index, name, title, notes, lod, group,
-- category, on = enabled for this character, loaded, loadable, reason, locked }.
-- reason is why the game will not load it (a key of the game's ADDON_<reason>
-- strings). group is the addon a
-- sub-addon is listed under (its own name when it stands alone); category is
-- where the player put it, else the one its .toc declares, else nil.
function AM.List()
    local out, guid = {}, UnitGUID("player")
    local s = Store()
    for i = 1, C_AddOns.GetNumAddOns() do
        local name, title, notes = C_AddOns.GetAddOnInfo(i)
        if name then
            local category = C_AddOns.GetAddOnMetadata(i, "Category")
            local put = s and s.catOf[name]
            if put ~= nil then category = put or nil end
            local loadable, reason = C_AddOns.IsAddOnLoadable(i, UnitName("player"))
            out[#out + 1] = {
                index = i, name = name, notes = notes,
                title = Plain(title ~= "" and title or name),
                lod = C_AddOns.IsAddOnLoadOnDemand(i),
                group = C_AddOns.GetAddOnMetadata(i, "Group") or name,
                category = (category and category ~= "") and Plain(category) or nil,
                on = C_AddOns.GetAddOnEnableState(i, guid) > NONE,
                loaded = C_AddOns.IsAddOnLoaded(i),
                loadable = loadable, reason = reason,
                locked = name == CORE,
            }
        end
    end
    table.sort(out, function(a, b)
        local x, y = a.title:lower(), b.title:lower()
        if x ~= y then return x < y end
        return a.name < b.name
    end)
    return out
end

-- What the profile wants for an addon on a character: true, false, or nil (not managed).
function AM.Wanted(name, charKey)
    local s = Store()
    if not s then return nil end
    local c = s.chars[charKey]
    local o = c and c.overrides and c.overrides[name]
    if o ~= nil then return o end
    return s.defaults[name]
end

-- The addons a character's profile keeps on need what they depend on, or the
-- game would not load them: { [addon] = the addon that needs it }.
function AM.Needed(charKey)
    local needed = {}
    local function Need(name, by)
        for _, dep in ipairs({ C_AddOns.GetAddOnDependencies(name) }) do
            if not needed[dep] then
                needed[dep] = by
                Need(dep, by)
            end
        end
    end
    for i = 1, C_AddOns.GetNumAddOns() do
        local name = C_AddOns.GetAddOnInfo(i)
        if name and AM.Wanted(name, charKey) == true then Need(name, name) end
    end
    return needed
end

-- The changes this character needs: { { name, on }, ... }. What an addon that
-- stays on depends on is switched on as well, whatever the profile says of it.
function AM.Pending()
    local out = {}
    if not Store() then return out end
    local key, guid = CharKey(), UnitGUID("player")
    local needed = AM.Needed(key)
    for i = 1, C_AddOns.GetNumAddOns() do
        local name = C_AddOns.GetAddOnInfo(i)
        if name and name ~= CORE then
            local want = AM.Wanted(name, key)
            if needed[name] then want = true end
            if want ~= nil and want ~= (C_AddOns.GetAddOnEnableState(i, guid) > NONE) then
                out[#out + 1] = { name = name, on = want }
            end
        end
    end
    return out
end

-- Stages and saves this character's changes; they apply at the reload that follows.
function AM.ApplyNative()
    local guid = UnitGUID("player")
    local list = AM.Pending()
    for _, p in ipairs(list) do
        if p.on then
            C_AddOns.EnableAddOn(p.name, guid)
        else
            C_AddOns.DisableAddOn(p.name, guid)
        end
    end
    C_AddOns.SaveAddOns()
    return #list
end

function AM.SetDefault(name, value)
    Store(true).defaults[name] = value
end

function AM.SetOverride(charKey, name, value)
    local s = Store(true)
    local c = s.chars[charKey]
    if not c then
        c = { overrides = {} }
        s.chars[charKey] = c
    end
    c.overrides = c.overrides or {}
    c.overrides[name] = value
end

-- A whole list of addons at once: value is true, false, or nil to stop managing
-- them (the core addon is left alone).
function AM.SetDefaults(addons, value)
    local d = Store(true).defaults
    for _, a in ipairs(addons) do
        if a.name ~= CORE then d[a.name] = value end
    end
end

function AM.SetOverrides(charKey, addons, value)
    for _, a in ipairs(addons) do
        if a.name ~= CORE then AM.SetOverride(charKey, a.name, value) end
    end
end

-- Every addon's state on this character becomes the default.
function AM.DefaultsFromThisCharacter()
    local s, guid = Store(true), UnitGUID("player")
    wipe(s.defaults)
    for i = 1, C_AddOns.GetNumAddOns() do
        local name = C_AddOns.GetAddOnInfo(i)
        if name and name ~= CORE then
            s.defaults[name] = C_AddOns.GetAddOnEnableState(i, guid) > NONE
        end
    end
end

-- The rows to show, in order: { kind = "category", key, name, count, folded,
-- user, addons = every addon it holds, sub-addons included } and { kind = "addon", addon, depth, sub, members }. Like the game's
-- own list, a sub-addon sits under the addon its group names (members: that
-- addon and its sub-addons) and a category folds the addons it holds; those
-- without one close the list under "Uncategorized" (key ""). A search lists
-- the matches alone. query is lower case.
function AM.Tree(list, folded, query)
    local out = {}
    if query ~= "" then
        for _, a in ipairs(list) do
            if a.title:lower():find(query, 1, true) or a.name:lower():find(query, 1, true) then
                out[#out + 1] = { kind = "addon", addon = a, depth = 0 }
            end
        end
        return out
    end
    local byName, kids, roots = {}, {}, {}
    for _, a in ipairs(list) do byName[a.name] = a end
    for _, a in ipairs(list) do
        local parent = byName[a.group]
        if parent and parent ~= a and parent.group == parent.name then
            kids[parent.name] = kids[parent.name] or {}
            table.insert(kids[parent.name], a)
        else
            roots[#roots + 1] = a
        end
    end
    local cats, order, loose = {}, {}, {}
    for _, a in ipairs(roots) do
        local c = a.category
        if c then
            if not cats[c] then
                cats[c] = {}
                order[#order + 1] = c
            end
            table.insert(cats[c], a)
        else
            loose[#loose + 1] = a
        end
    end
    -- The categories made here show even while they hold nothing.
    local s = Store()
    local made = {}
    for _, c in ipairs(s and s.categories or {}) do
        made[c] = true
        if not cats[c] then
            cats[c] = {}
            order[#order + 1] = c
        end
    end
    table.sort(order, function(x, y) return x:lower() < y:lower() end)
    local function Add(a, depth)
        local sub = kids[a.name]
        local entry = { kind = "addon", addon = a, depth = depth }
        if sub then
            entry.members = { a }
            for _, c in ipairs(sub) do entry.members[#entry.members + 1] = c end
        end
        out[#out + 1] = entry
        for _, c in ipairs(sub or {}) do
            out[#out + 1] = { kind = "addon", addon = c, depth = depth + 1, sub = true }
        end
    end
    local function Category(key, name, members, user)
        local n, all = 0, {}
        for _, a in ipairs(members) do
            all[#all + 1] = a
            for _, c in ipairs(kids[a.name] or {}) do all[#all + 1] = c end
        end
        n = #all
        local isFolded = folded[key] == true
        out[#out + 1] = { kind = "category", key = key, name = name, count = n,
                          folded = isFolded, user = user, addons = all }
        if not isFolded then
            for _, a in ipairs(members) do Add(a, 1) end
        end
    end
    for _, c in ipairs(order) do Category(c, c, cats[c], made[c]) end
    if #loose > 0 then Category("", EllesmereUI.L("Uncategorized"), loose) end
    return out
end

-- Every category there is, declared by an addon or made here, by name.
function AM.Categories()
    local seen, out = {}, {}
    local s = Store()
    for _, a in ipairs(AM.List()) do
        if a.category and not seen[a.category] then
            seen[a.category] = true
            out[#out + 1] = a.category
        end
    end
    for _, c in ipairs(s and s.categories or {}) do
        if not seen[c] then
            seen[c] = true
            out[#out + 1] = c
        end
    end
    table.sort(out, function(x, y) return x:lower() < y:lower() end)
    return out
end

-- Makes a category; false when the name is empty or taken.
function AM.AddCategory(name)
    name = Plain(name or "")
    if name == "" then return false end
    for _, c in ipairs(AM.Categories()) do
        if c:lower() == name:lower() then return false end
    end
    table.insert(Store(true).categories, name)
    return true
end

-- Removes a category made here; what was put in it goes back to the category
-- its .toc declares.
function AM.RemoveCategory(name)
    local s = Store(true)
    for i, c in ipairs(s.categories) do
        if c == name then table.remove(s.categories, i) break end
    end
    for addon, c in pairs(s.catOf) do
        if c == name then s.catOf[addon] = nil end
    end
end

-- Puts an addon in a category: a name, false for uncategorized, nil to leave
-- it to what its .toc declares.
function AM.SetCategory(addon, value)
    Store(true).catOf[addon] = value
end

-- What an addon costs this session: the share of the game's script time as a
-- percentage (nil while the game's profiler is off or the addon is not loaded),
-- and its memory in KB. The memory figures are refreshed at most every 15 seconds.
function AM.Cpu(name)
    if not (C_AddOnProfiler and C_AddOnProfiler.IsEnabled()) then return nil end
    local metric = Enum.AddOnProfilerMetric.SessionAverageTime
    local mine = C_AddOnProfiler.GetAddOnMetric(name, metric)
    local total = C_AddOnProfiler.GetApplicationMetric(metric)
                - C_AddOnProfiler.GetOverallMetric(metric) + mine
    if total <= 0 then return nil end
    return mine / total * 100
end

local lastMemory = 0
function AM.RefreshMemory(force)
    local now = GetTime()
    if not force and now - lastMemory < 15 then return end
    lastMemory = now
    UpdateAddOnMemoryUsage()
end

function AM.Memory(name)
    return GetAddOnMemoryUsage(name)
end

-- The characters the profile knows, this one first.
function AM.Characters()
    local s, me = Store(), CharKey()
    local out, seen = { me }, { [me] = true }
    if s then
        local keys = {}
        for key in pairs(s.chars) do
            if not seen[key] then keys[#keys + 1] = key end
        end
        table.sort(keys)
        for _, key in ipairs(keys) do out[#out + 1] = key end
    end
    return out
end

-------------------------------------------------------------------------------
--  The game menu's AddOns button
--  The menu shows the game's AddOn list (ShowUIPanel(AddonList)). With the
--  option on, a hook on that frame's OnShow stands it aside and opens the
--  manager instead, and the game menu is closed; out of combat only, so the
--  game's list always stays reachable in combat. Nothing of Blizzard's is written.
-------------------------------------------------------------------------------
local hooked, bypass = false, false

function AM.HookMenu()
    if hooked then return end
    hooked = true
    EventUtil.ContinueOnAddOnLoaded("Blizzard_AddOnList", function()
        _G.AddonList:HookScript("OnShow", function(self)
            local s = Store()
            if not (s and s.menu) then return end
            if bypass then
                bypass = false
                return
            end
            if InCombatLockdown() then return end
            HideUIPanel(self)
            AM.Open()
            -- Hiding the list can bring the game menu it replaced back.
            local menu = _G.GameMenuFrame
            local function CloseMenu()
                if menu and menu:IsShown() and not InCombatLockdown() then HideUIPanel(menu) end
            end
            CloseMenu()
            C_Timer.After(0, CloseMenu)
        end)
    end)
end

function AM.ShowBlizzardList()
    bypass = true
    ShowUIPanel(_G.AddonList)
end

-------------------------------------------------------------------------------
--  Login: bring this character in line, once
-------------------------------------------------------------------------------
local function Offer()
    local s = Store()
    if not s or s.quiet or InCombatLockdown() then return end
    local n = #AM.Pending()
    if n == 0 then return end
    EllesmereUI:ShowConfirmPopup({
        title = EllesmereUI.L("Addon Manager"),
        message = EllesmereUI.Lf("Your addons on this character differ from your profile (%d). Apply the changes and reload?", n),
        confirmText = EllesmereUI.L("Apply and Reload"),
        cancelText = EllesmereUI.L("Later"),
        reload = true,
        onConfirm = AM.ApplyNative,
    })
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    local s = Store()
    if not s then return end
    Remember(s)
    if s.menu then AM.HookMenu() end
    -- The profile may change at login (a spec's profile): look once it has settled.
    C_Timer.After(3, Offer)
end)

-------------------------------------------------------------------------------
--  The page
--  The manager is a page of the options window (EUI_AddonManager_Options.lua,
--  module AM.KEY); this opens the window on it.
-------------------------------------------------------------------------------
AM.KEY = "EllesmereUIAddonManager"
AM.Store, AM.CharKey = Store, CharKey

function AM.Open()
    Remember(Store(true))
    EllesmereUI:Show()
    -- The very first open of the session builds the options a frame later.
    if EllesmereUI._openPending then
        C_Timer.After(0.1, function() EllesmereUI:SelectModule(AM.KEY) end)
    else
        EllesmereUI:SelectModule(AM.KEY)
    end
end

SLASH_EUIADDONS1 = "/euiaddons"
SlashCmdList["EUIADDONS"] = function() AM.Open() end
