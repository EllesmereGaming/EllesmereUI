local ADDON_NAME, ns = ...
if not ns then return end

local L = EllesmereUI.L
local queue, active, popup = {}, nil, nil
local recent = {}

local function Font(parent, size, r, g, b, a)
    return EllesmereUI.MakeFont(parent, size, nil, r or 1, g or 1, b or 1, a or 1)
end

local function Button(parent, text, width, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, 28)
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.045, 0.055, 0.07, 0.96)
    EllesmereUI.MakeBorder(button, 1, 1, 1, 0.16, EllesmereUI.PP)
    local label = Font(button, 10, 0.88, 0.9, 0.94, 1)
    label:SetPoint("CENTER"); label:SetText(text); button._label = label
    button:SetScript("OnEnter", function() bg:SetColorTexture(0.05, 0.3, 0.25, 0.95) end)
    button:SetScript("OnLeave", function() bg:SetColorTexture(0.045, 0.055, 0.07, 0.96) end)
    button:SetScript("OnClick", onClick)
    return button
end

local function PlainItemText(alert)
    local name = alert.itemName
    if (not name or name == "") and type(alert.itemLink) == "string" then
        name = alert.itemLink:match("|h%[([^%]]+)%]|h") or alert.itemLink:match("%[([^%]]+)%]")
    end
    if not name or name == "" then name = tostring(alert.itemID or "item") end
    return "[" .. name .. "]"
end

local function SanitizeChatText(text)
    -- SendChatMessage rejects hyperlink/color escape sequences supplied by addons.
    -- The popup may still display the real item link; whispers use safe plain text.
    text = tostring(text or "")
    text = text:gsub("|H.-|h(.-)|h", "%1")
        :gsub("|T.-|t", "")
        :gsub("|A.-|a", "")
        :gsub("|c%x%x%x%x%x%x%x%x", "")
        :gsub("|r", "")
        :gsub("|", "")
        :gsub("%c", " ")
    return (text:gsub("%s+", " "):match("^%s*(.-)%s*$"))
end

local function ExpandTemplate(template, alert)
    template = template or ""
    template = template:gsub("{player}", function() return alert.player or "" end)
    template = template:gsub("{item}", function() return PlainItemText(alert) end)
    return SanitizeChatText(template)
end

ns.BuildLootWhisper = ExpandTemplate

local function ShowNext()
    active = table.remove(queue, 1)
    if not active then if popup then popup:Hide() end return end
    if not popup then
        popup = CreateFrame("Frame", "EllesmereUILootTrackerLootAlert", UIParent, "BackdropTemplate")
        popup:SetSize(470, 174)
        popup:SetPoint("TOP", UIParent, "TOP", 0, -145)
        popup:SetFrameStrata("DIALOG"); popup:SetClampedToScreen(true)
        popup:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8X8" })
        popup:SetBackdropColor(0.018, 0.024, 0.032, 0.98)
        EllesmereUI.MakeBorder(popup, 0.05, 0.82, 0.62, 0.72, EllesmereUI.PP)

        popup.title = Font(popup, 12, 0.05, 0.82, 0.62, 1)
        popup.title:SetPoint("TOPLEFT", popup, "TOPLEFT", 14, -12)
        popup.iconButton = CreateFrame("Button", nil, popup)
        popup.iconButton:SetSize(42, 42); popup.iconButton:SetPoint("TOPLEFT", popup, "TOPLEFT", 14, -38)
        popup.icon = popup.iconButton:CreateTexture(nil, "ARTWORK")
        popup.icon:SetAllPoints(); popup.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        popup.item = Font(popup, 11, 0.78, 0.35, 1, 1)
        popup.item:SetPoint("TOPLEFT", popup.iconButton, "TOPRIGHT", 10, -2)
        popup.item:SetPoint("RIGHT", popup, "RIGHT", -14, 0); popup.item:SetJustifyH("LEFT")
        popup.owner = Font(popup, 9, 0.62, 0.65, 0.7, 1)
        popup.owner:SetPoint("BOTTOMLEFT", popup.iconButton, "BOTTOMRIGHT", 10, 3)

        popup.edit = CreateFrame("EditBox", nil, popup)
        popup.edit:SetPoint("TOPLEFT", popup, "TOPLEFT", 14, -88)
        popup.edit:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -14, -88)
        popup.edit:SetHeight(30); popup.edit:SetAutoFocus(false)
        popup.edit:SetFont((EllesmereUI.GetFontPath and EllesmereUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF", 10, "")
        popup.edit:SetTextColor(0.9, 0.92, 0.95, 1); popup.edit:SetTextInsets(7, 7, 0, 0)
        local editBG = popup.edit:CreateTexture(nil, "BACKGROUND")
        editBG:SetAllPoints(); editBG:SetColorTexture(0.01, 0.014, 0.02, 0.96)
        EllesmereUI.MakeBorder(popup.edit, 1, 1, 1, 0.13, EllesmereUI.PP)
        popup.edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

        popup.whisper = Button(popup, L("Whisper for trade"), 160, function()
            if active and active.player and popup.edit:GetText() ~= "" then
                SendChatMessage(popup.edit:GetText(), "WHISPER", nil, active.player)
            end
            ShowNext()
        end)
        popup.whisper:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -14, 12)
        popup.dismiss = Button(popup, L("Dismiss"), 100, ShowNext)
        popup.dismiss:SetPoint("RIGHT", popup.whisper, "LEFT", -8, 0)
        popup.iconButton:SetScript("OnEnter", function(self)
            if not active then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(active.itemLink)
            GameTooltip:Show()
        end)
        popup.iconButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    popup.title:SetText(L("Wishlist item looted"))
    popup.icon:SetTexture(active.icon or C_Item.GetItemIconByID(active.itemID))
    popup.item:SetText(active.itemLink or active.itemName)
    popup.owner:SetText(EllesmereUI.Lf("Looted by %s", active.player))
    popup.edit:SetText(ExpandTemplate(ns.GetProfile().whisperTemplate, active))
    popup:Show()
end

function ns.QueueLootAlert(alert)
    if not alert or not alert.player or not alert.itemID then return end
    queue[#queue + 1] = alert
    while #queue > 5 do table.remove(queue, 1) end
    if not active then ShowNext() end
end

local function EscapePattern(text)
    return (text:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"))
end

local function PlayerFromFormat(message, formatString)
    if type(formatString) ~= "string" then return nil end
    local firstStart, firstEnd = formatString:find("%%s")
    if not firstStart then return nil end
    local secondStart = formatString:find("%%s", firstEnd + 1)
    if not secondStart then return nil end
    local prefix = formatString:sub(1, firstStart - 1)
    local middle = formatString:sub(firstEnd + 1, secondStart - 1)
    return message:match("^" .. EscapePattern(prefix) .. "(.-)" .. EscapePattern(middle))
end

local function ResolveLooter(message, sender, alternateSender)
    if issecretvalue and issecretvalue(sender) then sender = nil end
    if issecretvalue and issecretvalue(alternateSender) then alternateSender = nil end
    local player = alternateSender and alternateSender ~= "" and alternateSender or sender
    if not player or player == "" then
        player = PlayerFromFormat(message, LOOT_ITEM)
            or PlayerFromFormat(message, LOOT_ITEM_MULTIPLE)
            or PlayerFromFormat(message, LOOT_ITEM_PUSHED)
            or PlayerFromFormat(message, LOOT_ITEM_PUSHED_MULTIPLE)
    end
    if not player or player == "" then return nil end
    player = player:gsub("|T.-|t", "")
    return Ambiguate and Ambiguate(player, "none") or player
end

local function OnChatLoot(message, sender, ...)
    if ns.GetProfile().lootWhisperPopup == false or not IsInGroup() then return end
    if type(message) ~= "string" or (issecretvalue and issecretvalue(message)) then return end
    local itemLink = message:match("(|c%x+|Hitem:.-|h.-|h|r)") or message:match("(|Hitem:.-|h.-|h)")
    if not itemLink then return end
    local itemID = C_Item.GetItemInfoInstant(itemLink)
    if not itemID or (issecretvalue and issecretvalue(itemID)) then return end
    local level = C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(itemLink)
    if issecretvalue and issecretvalue(level) then level = nil else level = tonumber(level) end
    local goal
    for _, candidate in ipairs(ns.GetGoals(nil, false)) do
        if candidate.itemID == itemID and candidate.state == "open"
            and (not level or level <= 0 or level >= (candidate.minItemLevel or 0))
            and (not goal or candidate.priority > goal.priority
                or (candidate.priority == goal.priority
                    and (candidate.minItemLevel or 0) > (goal.minItemLevel or 0))) then
            goal = candidate
        end
    end
    if not goal then return end

    local alternateSender = select(3, ...)
    local senderGUID = select(10, ...)
    if senderGUID and not (issecretvalue and issecretvalue(senderGUID)) and senderGUID == UnitGUID("player") then return end
    local player = ResolveLooter(message, sender, alternateSender)
    if not player then return end
    local playerShort = Ambiguate and Ambiguate(UnitName("player") or "", "none") or UnitName("player")
    if player == playerShort then return end

    local lineID = select(9, ...)
    local key = tostring(lineID or "") .. ":" .. player .. ":" .. itemID
    local now = GetTime()
    if recent[key] and now - recent[key] < 30 then return end
    recent[key] = now
    ns.QueueLootAlert({
        player=player, itemID=itemID, itemLink=itemLink,
        itemName=C_Item.GetItemNameByID(itemID), icon=C_Item.GetItemIconByID(itemID),
        goal=goal,
    })
end

local events = CreateFrame("Frame")
events:RegisterEvent("CHAT_MSG_LOOT")
events:SetScript("OnEvent", function(_, _, ...) OnChatLoot(...) end)
