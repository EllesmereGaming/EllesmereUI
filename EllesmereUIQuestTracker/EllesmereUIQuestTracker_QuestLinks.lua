if EUI_CLIENT_BLOCKED then return end
local _, ns = ...
local EQT = ns.EQT

ns.QT_DEFAULTS.profile.questTracker.wowheadQuestLinks = false
ns.QT_DEFAULTS.profile.questTracker.wowheadQuestComments = false
ns.QT_DEFAULTS.profile.questTracker.wowheadQuestClientLanguage = false

local site = EllesmereUI.IS_FOREVER and "forever/"
    or (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE and "" or "classic/")
local logHandle, detailHandle, addedMenus
local function AddQuestLink(owner, root)
    if not EQT.Cfg("wowheadQuestLinks") or addedMenus[root] then return end
    -- Quest rows and the quest-details popup both own their questID. Waypoints
    -- share the log menu tag but have no questID.
    local questID = owner and owner.questID
    if issecretvalue(questID) or type(questID) ~= "number"
        or questID <= 0 or questID ~= math.floor(questID) then return end
    -- ModifyMenu also visits its last generated description when registered.
    addedMenus[root] = true
    local questPath = "quest=" .. string.format("%.0f", questID) .. "/"
    root:CreateDivider()
    root:CreateButton(EllesmereUI.L("Wowhead Link"), function()
        if not EQT.Cfg("wowheadQuestLinks") then return end
        local locale = ""
        if EQT.Cfg("wowheadQuestClientLanguage") then
            locale = ({ deDE="de/", ptBR="pt/", esES="es/", esMX="mx/",
                frFR="fr/", itIT="it/", ruRU="ru/", zhTW="tw/", zhCN="cn/",
                koKR="ko/" })[GetLocale()] or ""
        end
        EllesmereUI:ShowInputPopup({
            title = EllesmereUI.L("Wowhead Link"),
            message = EllesmereUI.L("Press Ctrl+C to copy, then paste the link into your browser."),
            initialText = "https://www.wowhead.com/" .. site .. locale .. questPath
                .. (EQT.Cfg("wowheadQuestComments") and "#comments" or ""),
            maxLetters = 256,
            confirmText = EllesmereUI.L("Close"),
            cancelText = EllesmereUI.L("Cancel"),
        })
        EllesmereUI._inputPopup._editBox:HighlightText()
    end)
end

function EQT.ApplyQuestLinks()
    if not EQT.Cfg("wowheadQuestLinks") then
        if logHandle then logHandle:Unregister(); logHandle = nil end
        if detailHandle then detailHandle:Unregister(); detailHandle = nil end
        return
    end
    if logHandle then return end
    if not addedMenus then addedMenus = setmetatable({}, { __mode = "k" }) end
    logHandle = Menu.ModifyMenu("MENU_QUEST_MAP_LOG_TITLE", AddQuestLink)
    detailHandle = Menu.ModifyMenu("MENU_QUEST_LOG_POPUP_DETAIL_FRAME", AddQuestLink)
end
