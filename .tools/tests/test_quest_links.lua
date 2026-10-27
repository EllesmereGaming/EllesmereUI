-- Run from the repository root: lua .tools/tests/test_quest_links.lua
local path = arg[1] or "EllesmereUIQuestTracker/EllesmereUIQuestTracker_QuestLinks.lua"
local tags = { "MENU_QUEST_MAP_LOG_TITLE", "MENU_QUEST_LOG_POPUP_DETAIL_FRAME" }
issecretvalue = function(value) return value == "secret" end

local function RunCase(forever, site)
    local cfg, callbacks, cached = {}, {}, {}
    local popup, hover, registrations, removals = nil, nil, 0, 0
    EllesmereUI = {
        IS_FOREVER = forever,
        L = function(s) return s end,
        ShowInputPopup = function(_, opts) popup = opts end,
    }
    Menu = { ModifyMenu = function(tag, callback)
        assert(not callbacks[tag], "duplicate callback")
        registrations = registrations + 1
        if cached[tag] then callback(cached[tag].owner, cached[tag].root) end
        callbacks[tag] = callback
        return { Unregister = function()
            assert(callbacks[tag] == callback)
            callbacks[tag] = nil
            removals = removals + 1
        end }
    end }
    EventRegistry = { RegisterCallbackWithHandle = function(_, event, func)
        assert(event == "OnQuestBlockHeader.OnEnter" and not hover, "duplicate hover callback")
        registrations = registrations + 1
        hover = func
        return { Unregister = function()
            assert(hover == func)
            hover = nil
            removals = removals + 1
        end }
    end }
    local ns = { EQT = { Cfg = function(key) return cfg[key] end },
        QT_DEFAULTS = { profile = { questTracker = {} } } }
    assert(loadfile(path))("EllesmereUIQuestTracker", ns)
    for key, value in pairs(ns.QT_DEFAULTS.profile.questTracker) do cfg[key] = value end
    assert(cfg.wowheadQuestLinks == false and cfg.wowheadQuestComments == false)
    assert(cfg.wowheadQuestClientLanguage == false)
    GetLocale = function() error("Locale must not be queried unless enabled") end
    ns.EQT.ApplyQuestLinks()
    assert(registrations == 0 and popup == nil, "disabled feature must be inert")
    cfg.wowheadQuestLinks = true
    ns.EQT.ApplyQuestLinks()
    ns.EQT.ApplyQuestLinks()
    assert(registrations == 4) -- three menus and the tracker header hover

    for _, tag in ipairs(tags) do
        local entries = { "Blizzard entry" }
        local root = {
            CreateDivider = function() entries[#entries + 1] = "divider" end,
            CreateButton = function(_, label, click)
                assert(label == "Wowhead Link")
                entries[#entries + 1] = click
            end,
        }
        for _, id in ipairs({ 0, -1, 1.5, "secret", "98025" }) do
            callbacks[tag]({questID = id}, root)
        end
        callbacks[tag]({}, root)
        callbacks[tag](nil, root)
        assert(#entries == 1, "headers and waypoints must be unchanged")
        local owner = {questID = 98025}
        callbacks[tag](owner, root)
        cached[tag] = {owner = owner, root = root}
        local click = entries[3]
        assert(#entries == 3 and entries[1] == "Blizzard entry")
        owner.questID = 249 -- Quest rows are recycled after opening the menu.
        click()
        local base = "https://www.wowhead.com/" .. site .. "quest=98025/"
        assert(popup.initialText == base and popup.selectText and popup.hideCancel)
        cfg.wowheadQuestComments = true
        click()
        assert(popup.initialText == base .. "#comments")
        cfg.wowheadQuestComments = false
        click()
        assert(popup.initialText == base)

        for locale, prefix in pairs({ deDE="de/", ptBR="pt/", esES="es/", esMX="mx/",
            frFR="fr/", itIT="it/", ruRU="ru/", zhTW="tw/", zhCN="cn/",
            koKR="ko/", enUS="", enGB="", unknown="" }) do
            GetLocale = function() return locale end
            cfg.wowheadQuestClientLanguage = true
            for _, comments in ipairs({ false, true }) do
                cfg.wowheadQuestComments = comments
                click()
                assert(popup.initialText == "https://www.wowhead.com/" .. site .. prefix
                    .. "quest=98025/" .. (comments and "#comments" or ""))
            end
            cfg.wowheadQuestClientLanguage = false
            cfg.wowheadQuestComments = false
            click()
            assert(popup.initialText == base)
        end

        -- Disabling/profile changes must remove every callback and gate stale clicks.
        cfg.wowheadQuestLinks = false
        ns.EQT.ApplyQuestLinks()
        ns.EQT.ApplyQuestLinks()
        assert(next(callbacks) == nil and hover == nil and removals == registrations)
        popup = nil
        click()
        assert(popup == nil)
        cfg.wowheadQuestLinks = true
        ns.EQT.ApplyQuestLinks()
        assert(#entries == 3, "cached menu must not acquire a second link")
    end

    -- The tracker's quest menu is owned by the tracker: its quest is the
    -- header the cursor entered, while the cursor is still on it.
    do
        local tag, container = "MENU_QUEST_OBJECTIVE_TRACKER", {}
        local entries = { "Blizzard entry" }
        local root = {
            CreateDivider = function() entries[#entries + 1] = "divider" end,
            CreateButton = function(_, label, click)
                assert(label == "Wowhead Link")
                entries[#entries + 1] = click
            end,
        }
        local over = true
        local header = { IsMouseOver = function() return over end }
        callbacks[tag](container, root)
        assert(#entries == 1, "no hovered header, no link")
        for _, id in ipairs({ 0, -1, 1.5, "secret", "98025" }) do
            hover(1, { id = id, HeaderButton = header }, id, false)
            callbacks[tag](container, root)
        end
        hover(1, { id = 98025 }, 98025, false)
        callbacks[tag](container, root)
        assert(#entries == 1, "bad quest IDs and headerless blocks must be ignored")
        local block = { id = 98025, HeaderButton = header }
        hover(1, block, block.id, false)
        over = false
        callbacks[tag](container, root)
        assert(#entries == 1, "a header the cursor left must not be used")
        over = true
        callbacks[tag](container, root)
        assert(#entries == 3 and entries[1] == "Blizzard entry")
        cached[tag] = { owner = container, root = root }
        block.id = 249 -- Tracker blocks are recycled after opening the menu.
        entries[3]()
        assert(popup.initialText == "https://www.wowhead.com/" .. site .. "quest=98025/")
        cfg.wowheadQuestLinks = false
        ns.EQT.ApplyQuestLinks()
        assert(next(callbacks) == nil and hover == nil and removals == registrations)
        cfg.wowheadQuestLinks = true
        ns.EQT.ApplyQuestLinks()
        assert(#entries == 3, "cached menu must not acquire a second link")
    end
    cfg.wowheadQuestLinks = false
    ns.EQT.ApplyQuestLinks()
    assert(next(callbacks) == nil and hover == nil and registrations == removals)
end

RunCase(true, "forever/") -- WoW Forever links to its own database.
RunCase(false, "")
EUI_CLIENT_BLOCKED = true
local blocked = { EQT = {} }
assert(loadfile(path))("EllesmereUIQuestTracker", blocked)
assert(blocked.EQT.ApplyQuestLinks == nil)
print("PASS: quest log and tracker menus, opt-in, comments, client URLs, disable/re-enable, cached menus, client gate")
