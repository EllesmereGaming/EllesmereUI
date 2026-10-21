if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIQoL_ItemIcons_FramesExchange.lua
--  Item Icons frame adapters for the windows whose items have no bag
--  location: guild bank, loot window, group loot rolls, mail (inbox, open
--  mail, send mail), trade (both sides) and quest rewards. Each paints right
--  after Blizzard's own update of its buttons, from the item link and the
--  window's count, and hides the Blizzard count and crafting pip the layout
--  replaces. Hooks go in on a frame's first Enable, once the Blizzard addon
--  that owns it has loaded (II.RegisterLazyFrame), and return at once while
--  the frame is released. An item whose ID is known before its link fills in
--  when its data arrives (II.WaitForItem). Contracts:
--  EllesmereUIQoL_ItemIcons.lua.
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI
local II = EllesmereUI.ItemIcons
local Paint, Clear, HideNative, RestoreNative = II.Paint, II.Clear, II.HideNative, II.RestoreNative
local IsManaged, WaitForItem = II.IsFrameEnabled, II.WaitForItem

local ctx = {}
local lootFacts, tradeFacts = {}, {}

-- Starts ctx for one button. No link: no item, or not an item
local function SetItem(link, count)
    ctx.link, ctx.count = link, count
    ctx.anchor, ctx.alpha, ctx.facts = nil, nil, nil
end

-- Draws the layout from ctx and hides Blizzard's count and crafting pip under
-- it; a button without an item gets them back
local function Show(button, frameKey, count)
    local pip = button.ProfessionQualityOverlay
    if ctx.link then
        Paint(button, ctx, frameKey)
        HideNative(count, frameKey)
        HideNative(pip, frameKey)
    else
        Clear(button)
        RestoreNative(count)
        RestoreNative(pip)
    end
end

-------------------------------------------------------------------------------
--  Guild bank (load on demand). GuildBankFrame:Update fills the shown tab,
--  UpdateFiltered redoes the search dimming
-------------------------------------------------------------------------------
local bankButtons = {}

local function PaintGuildBank()
    if not IsManaged("guildbank") then return end
    local f = GuildBankFrame
    if f.mode ~= "bank" or not f:IsVisible() then return end
    local tab = GetCurrentGuildBankTab()
    for i = 1, #bankButtons do
        local button = bankButtons[i]
        local slot = button:GetID()
        local _, count, _, filtered = GetGuildBankItemInfo(tab, slot)
        SetItem(GetGuildBankItemLink(tab, slot), count)
        if filtered then ctx.alpha = II.DIM_ALPHA end
        Show(button, "guildbank", button.Count)
    end
end

II.RegisterLazyFrame("guildbank", "Blizzard_GuildBankUI", function()
    local f = GuildBankFrame
    for _, column in ipairs(f.Columns) do
        for _, button in ipairs(column.Buttons) do bankButtons[#bankButtons + 1] = button end
    end
    hooksecurefunc(f, "Update", PaintGuildBank)
    hooksecurefunc(f, "UpdateFiltered", PaintGuildBank)
end, PaintGuildBank)

-------------------------------------------------------------------------------
--  Loot window. Its ScrollBox initializes each row (OnInitializedFrame), and
--  LOOT_SLOT_CHANGED initializes a row again in place
-------------------------------------------------------------------------------
local function PaintLootRow(row)
    local button = row.Item  -- rows of empty slots have none
    if not button then return end
    local slot = row:GetSlotIndex()
    local link
    if GetLootSlotType(slot) == Enum.LootSlotType.Item then link = GetLootSlotLink(slot) end
    SetItem(link)
    -- Blizzard's bang marks a quest starter (the questMarker element), its
    -- border any other quest item
    local mark = row.IconQuestTexture
    if link then
        local _, _, quantity, _, _, _, _, questID, isActive = GetLootSlotInfo(slot)
        local starter = questID ~= nil and not isActive
        ctx.count = quantity
        lootFacts.questStarter = starter
        ctx.facts = lootFacts
        if starter then HideNative(mark, "loot") else RestoreNative(mark) end
    else
        RestoreNative(mark)
    end
    Show(button, "loot", button.Count)
end

local function PaintLoot()
    if IsManaged("loot") and LootFrame:IsShown() then LootFrame.ScrollBox:ForEachFrame(PaintLootRow) end
end

II.RegisterLazyFrame("loot", "Blizzard_UIPanels_Game", function()
    ScrollUtil.AddInitializedFrameCallback(LootFrame.ScrollBox, function(_, row)
        if IsManaged("loot") then PaintLootRow(row) end
    end)
    LootFrame:HookScript("OnEvent", function(_, event)
        if event == "LOOT_SLOT_CHANGED" then PaintLoot() end
    end)
end, PaintLoot)

-------------------------------------------------------------------------------
--  Group loot rolls. GroupLootFrame_OnShow fills a roll frame's item. WoW
--  Forever's gamepad UI lists rolls in GamepadGroupLootRollFrame instead: its
--  ScrollBox initializes every row it shows, reused ones included
-------------------------------------------------------------------------------
local rollFrames = {}
local gamepadRolls  -- GamepadGroupLootRollFrame, WoW Forever only

local function PaintRoll(frame)
    if not IsManaged("grouploot") then return end
    local id, button = frame.rollID, frame.IconFrame
    local link, count
    if id then
        link = GetLootRollItemLink(id)
        count = select(3, GetLootRollItemInfo(id))
    end
    SetItem(link, count)
    Show(button, "grouploot", button.Count)
end

local function PaintRolls()
    for i = 1, #rollFrames do
        local frame = rollFrames[i]
        if frame:IsShown() then PaintRoll(frame) end
    end
    if gamepadRolls and gamepadRolls:IsShown() then gamepadRolls.ScrollBox:ForEachFrame(PaintRoll) end
end

II.RegisterLazyFrame("grouploot", "Blizzard_UIPanels_Game", function()
    local i, frame = 1, _G.GroupLootFrame1
    while frame do
        rollFrames[i] = frame
        frame:HookScript("OnShow", PaintRoll)
        i = i + 1
        frame = _G["GroupLootFrame" .. i]
    end
    gamepadRolls = _G.GamepadGroupLootRollFrame
    if gamepadRolls then
        ScrollUtil.AddInitializedFrameCallback(gamepadRolls.ScrollBox, function(_, row) PaintRoll(row) end)
    end
end, PaintRolls)

-------------------------------------------------------------------------------
--  Mail: inbox rows (their first attachment, as Blizzard draws them), the
--  open mail's attachments and the outgoing ones. Retail 12.1.5 updates the
--  first two through InboxFrame_Update and OpenMailFrame_UpdateButtonPositions,
--  WoW Forever through the same frames' Update and UpdateButtonPositions
--  methods (InboxMixin, OpenMailMixin)
-------------------------------------------------------------------------------
local inboxButtons, inboxCounts = {}, {}

local function PaintInbox()
    if not IsManaged("mail") then return end
    for i = 1, #inboxButtons do
        local button = inboxButtons[i]
        local count, link
        if button:IsShown() then count, link = select(14, GetInboxHeaderInfo(button.index)) end
        SetItem(link, count)
        Show(button, "mail", inboxCounts[i])
    end
end

local function PaintOpenMail()
    if not IsManaged("mail") then return end
    local mail = InboxFrame.openMailID
    local buttons = OpenMailFrame.OpenMailAttachments
    for i = 1, ATTACHMENTS_MAX_RECEIVE do
        local link, count
        if mail and mail > 0 and HasInboxItem(mail, i) then
            local _, id, _, n, _, _, isCurrency = GetInboxItem(mail, i)
            if not isCurrency then
                link, count = GetInboxItemLink(mail, i), n
                if not link then WaitForItem(id, "mail") end
            end
        end
        SetItem(link, count)
        local button = buttons[i]
        Show(button, "mail", button.Count)
    end
end

-- An outgoing attachment's link. Blizzard's UI reads none, so it comes from
-- the item's tooltip data, resolved as TooltipUtil.GetDisplayedItem does
local function SendMailLink(i)
    local data = C_TooltipInfo.GetSendMailItem(i)
    if not data then return nil end
    local guid = data.guid
    if guid and not issecretvalue(guid) then return C_Item.GetItemLinkByGUID(guid) end
    return data.hyperlink
end

local function PaintSendMail()
    if not IsManaged("mail") then return end
    local buttons = SendMailFrame.SendMailAttachments
    for i = 1, ATTACHMENTS_MAX_SEND do
        local link, count
        if HasSendMailItem(i) then link, count = SendMailLink(i), select(4, GetSendMailItem(i)) end
        SetItem(link, count)
        local button = buttons[i]
        Show(button, "mail", button.Count)
    end
end

local function PaintMail()
    if InboxFrame:IsVisible() then PaintInbox() end
    if OpenMailFrame:IsShown() then PaintOpenMail() end
    if SendMailFrame:IsVisible() then PaintSendMail() end
end

II.RegisterLazyFrame("mail", "Blizzard_MailFrame", function()
    for i = 1, INBOXITEMS_TO_DISPLAY do
        inboxButtons[i] = _G["MailItem" .. i .. "Button"]
        inboxCounts[i] = _G["MailItem" .. i .. "ButtonCount"]
    end
    if InboxFrame.Update then
        hooksecurefunc(InboxFrame, "Update", PaintInbox)
    else
        hooksecurefunc("InboxFrame_Update", PaintInbox)
    end
    if OpenMailFrame.UpdateButtonPositions then
        hooksecurefunc(OpenMailFrame, "UpdateButtonPositions", PaintOpenMail)
    else
        hooksecurefunc("OpenMailFrame_UpdateButtonPositions", PaintOpenMail)
    end
    hooksecurefunc("SendMailFrame_Update", PaintSendMail)
end, PaintMail)

-------------------------------------------------------------------------------
--  Trade. TradeFrame_UpdatePlayerItem and TradeFrame_UpdateTargetItem each
--  fill one slot
-------------------------------------------------------------------------------
local playerTrade, targetTrade = {}, {}

local function PaintTradePlayer(id)
    if not IsManaged("trade") then return end
    local _, _, count, _, _, _, isBound, itemID = GetTradePlayerItemInfo(id)
    local link = GetTradePlayerItemLink(id)
    if not link then WaitForItem(itemID, "trade") end
    SetItem(link, count)
    tradeFacts.isBound = isBound
    ctx.facts = tradeFacts
    local button = playerTrade[id]
    Show(button, "trade", button.Count)
end

local function PaintTradeTarget(id)
    if not IsManaged("trade") then return end
    local _, _, count, _, _, _, itemID = GetTradeTargetItemInfo(id)
    local link = GetTradeTargetItemLink(id)
    if not link then WaitForItem(itemID, "trade") end
    SetItem(link, count)
    -- The API has no bound state for the other side: an offered item counts
    -- as unbound, as Blizzard draws it; the slot that is not traded may hold
    -- a bound one
    if id == TRADE_ENCHANT_SLOT then
        tradeFacts.isBound = true
        ctx.facts = tradeFacts
    end
    local button = targetTrade[id]
    Show(button, "trade", button.Count)
end

local function PaintTrade()
    if not TradeFrame:IsShown() then return end
    for i = 1, MAX_TRADE_ITEMS do
        PaintTradePlayer(i)
        PaintTradeTarget(i)
    end
end

II.RegisterLazyFrame("trade", "Blizzard_UIPanels_Game", function()
    for i = 1, MAX_TRADE_ITEMS do
        playerTrade[i] = _G["TradePlayerItem" .. i .. "ItemButton"]
        targetTrade[i] = _G["TradeRecipientItem" .. i .. "ItemButton"]
    end
    hooksecurefunc("TradeFrame_UpdatePlayerItem", PaintTradePlayer)
    hooksecurefunc("TradeFrame_UpdateTargetItem", PaintTradeTarget)
end, PaintTrade)

-------------------------------------------------------------------------------
--  Quest rewards: quest window, quest log and map details. The templates of
--  QuestInfo_Display hold their own reference to QuestInfo_ShowRewards, so
--  Display is hooked as well as the global (QUEST_ITEM_UPDATE calls that)
-------------------------------------------------------------------------------
-- A reward item's ID, read as QuestInfo_ShowRewardAsItemCommon reads it
local function RewardItemID(button, questLog)
    local id = button:GetID()
    if not questLog then return (select(6, GetQuestItemInfo(button.type, id))) end
    if button.type == "choice" then return (select(6, GetQuestLogChoiceInfo(id))) end
    return (select(6, GetQuestLogRewardInfo(id)))
end

local function PaintRewards()
    if not IsManaged("questrewards") then return end
    local rewards = QuestInfoFrame.rewardsFrame
    if not (rewards and rewards:IsShown()) then return end
    local questLog, buttons = QuestInfoFrame.questLog, rewards.RewardButtons
    for i = 1, #buttons do
        local button = buttons[i]
        if button:IsShown() then
            local link
            if button.objectType == "item" then
                if questLog then
                    link = GetQuestLogItemLink(button.type, button:GetID())
                else
                    link = GetQuestItemLink(button.type, button:GetID())
                end
                -- Not cached yet: Blizzard sets the button again once it loads,
                -- without a call the hooks see
                if not link then WaitForItem(RewardItemID(button, questLog), "questrewards") end
            end
            -- The count Blizzard set once the item's data loaded
            SetItem(link, GetItemButtonCount(button))
            ctx.anchor = button.Icon
            Show(button, "questrewards", button.Count)
        end
    end
end

-- Only a template that lays out rewards parents the rewards frame to it
local function OnQuestInfoDisplay(_, parent)
    if not IsManaged("questrewards") then return end
    local rewards = QuestInfoFrame.rewardsFrame
    if rewards and rewards:GetParent() == parent then PaintRewards() end
end

local function RefreshRewards()
    local rewards = QuestInfoFrame.rewardsFrame
    if rewards and rewards:IsVisible() then PaintRewards() end
end

II.RegisterLazyFrame("questrewards", "Blizzard_UIPanels_Game", function()
    hooksecurefunc("QuestInfo_Display", OnQuestInfoDisplay)
    hooksecurefunc("QuestInfo_ShowRewards", PaintRewards)
end, RefreshRewards)
