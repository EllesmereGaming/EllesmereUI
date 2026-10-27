if EUI_CLIENT_BLOCKED then return end
local _, ns = ...
local EQT = ns.EQT

ns.QT_DEFAULTS.profile.questTracker.wowheadQuestLinks = false
ns.QT_DEFAULTS.profile.questTracker.wowheadQuestComments = false
ns.QT_DEFAULTS.profile.questTracker.wowheadQuestClientLanguage = false

local site = EllesmereUI.IS_FOREVER and "forever/" or ""
-- Wowhead's path for each client language it has (English takes none).
local WOWHEAD_LANG = { deDE = "de/", ptBR = "pt/", esES = "es/", esMX = "mx/", frFR = "fr/",
    itIT = "it/", ruRU = "ru/", zhTW = "tw/", zhCN = "cn/", koKR = "ko/" }
local logHandle, detailHandle, trackerHandle, hoverHandle, addedMenus
local hoverBlock -- the tracker quest block whose header the cursor entered last

local function AddLinkButton(questID, root)
    if not EQT.Cfg("wowheadQuestLinks") or addedMenus[root] then return end
    if issecretvalue(questID) or type(questID) ~= "number"
        or questID <= 0 or questID ~= math.floor(questID) then return end
    -- ModifyMenu also visits its last generated description when registered.
    addedMenus[root] = true
    local questPath = "quest=" .. string.format("%.0f", questID) .. "/"
    root:CreateDivider()
    root:CreateButton(EllesmereUI.L("Wowhead Link"), function()
        if not EQT.Cfg("wowheadQuestLinks") then return end
        local lang = EQT.Cfg("wowheadQuestClientLanguage") and WOWHEAD_LANG[GetLocale()] or ""
        -- The popup translates its own texts.
        EllesmereUI:ShowInputPopup({
            title = "Wowhead Link",
            message = "Press Ctrl+C to copy, then paste the link into your browser.",
            initialText = "https://www.wowhead.com/" .. site .. lang .. questPath
                .. (EQT.Cfg("wowheadQuestComments") and "#comments" or ""),
            maxLetters = 256,
            confirmText = "Close",
            hideCancel = true,
            selectText = true,
        })
    end)
end

-- Quest rows and the quest-details popup both own their questID. Waypoints
-- share the log menu tag but have no questID.
local function AddQuestLink(owner, root)
    AddLinkButton(owner and owner.questID, root)
end

-- The tracker's quest menu is owned by the tracker, not the quest. It opens
-- from a click on a quest's header, which Blizzard reports as the cursor
-- enters it, so the quest is that header's while the cursor is still on it.
local function OnQuestHeaderEnter(_, block) hoverBlock = block end
local function AddTrackerLink(_, root)
    local header = hoverBlock and hoverBlock.HeaderButton
    if header and header:IsMouseOver() then AddLinkButton(hoverBlock.id, root) end
end

function EQT.ApplyQuestLinks()
    if not EQT.Cfg("wowheadQuestLinks") then
        if not logHandle then return end
        logHandle:Unregister(); detailHandle:Unregister()
        trackerHandle:Unregister(); hoverHandle:Unregister()
        logHandle, detailHandle, trackerHandle, hoverHandle, hoverBlock = nil, nil, nil, nil, nil
        return
    end
    if logHandle then return end
    if not addedMenus then addedMenus = setmetatable({}, { __mode = "k" }) end
    logHandle = Menu.ModifyMenu("MENU_QUEST_MAP_LOG_TITLE", AddQuestLink)
    detailHandle = Menu.ModifyMenu("MENU_QUEST_LOG_POPUP_DETAIL_FRAME", AddQuestLink)
    trackerHandle = Menu.ModifyMenu("MENU_QUEST_OBJECTIVE_TRACKER", AddTrackerLink)
    hoverHandle = EventRegistry:RegisterCallbackWithHandle("OnQuestBlockHeader.OnEnter", OnQuestHeaderEnter)
end
