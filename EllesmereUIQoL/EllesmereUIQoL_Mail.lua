if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIQoL_Mail.lua
--  Small mailbox improvements.
--
--   - Ctrl-click a mail to return it to its sender.
--   - Hovering a mail lists every attachment once it carries more than one, and
--     spells out a subject the row is too narrow to show.
--   - Sending only money with a blank subject fills the subject in with the
--     amount, which the client otherwise makes you type before it lets you send.
--
--  No shift-click shortcut: the retail client already takes a mail's money and
--  attachments on shift-click. Adding our own take on top ran the operation
--  twice, which the server answers with an internal mail database error and
--  which leaves an emptied item mail undeleted.
--
--  Hooking: every hook here is additive (HookScript, and hooksecurefunc on the
--  function that builds the icon button's tooltip and on the money field's
--  change callback), never a replacement of a Blizzard handler, so the default
--  click and the default tooltip always still run. Neither can be undone, so
--  the enabled checks live inside the handlers -- toggling the feature applies
--  at once with nothing to re-hook.
-------------------------------------------------------------------------------

local ROW_PATTERN = "^MailItem%d+$"

local function Cfg()
    if not EllesmereUIDB then return {} end
    EllesmereUIDB.mailImprovements = EllesmereUIDB.mailImprovements or {}
    return EllesmereUIDB.mailImprovements
end

-- The feature is off by default; each of its parts is on, so switching the
-- feature on delivers the whole thing without a second trip to the panel.
local SUB_DEFAULTS = {
    ctrlReturn     = true,
    itemTooltip    = true,
    subjectTooltip = true,
    moneySubject   = true,
}

local function Opt(key)
    local c = Cfg()
    if not c.enabled then return false end
    local v = c[key]
    if v == nil then return SUB_DEFAULTS[key] end
    return v and true or false
end

-------------------------------------------------------------------------------
--  Row helpers
-------------------------------------------------------------------------------

-- Hooks land on the row and on its item button, so resolve whichever was
-- entered back to the named MailItem<N> row that owns the sender/subject text.
-- The button is a direct child of the row, so one hop up is always enough.
local function ResolveRow(frame)
    for _ = 1, 2 do
        if not frame then return nil end
        local name = frame.GetName and frame:GetName()
        if name and name:match(ROW_PATTERN) then return frame, name end
        frame = frame.GetParent and frame:GetParent()
    end
end

local function RowIndex(row, name)
    if row.index then return row.index end
    -- Fallback: the row ordinal offset by the page currently shown.
    local ordinal = tonumber(name:match("^MailItem(%d+)$"))
    if not ordinal then return nil end
    local page = (_G.InboxFrame and _G.InboxFrame.pageNum) or 1
    return ordinal + (page - 1) * (_G.INBOXITEMS_TO_DISPLAY or 7)
end

-- Valid only while the row maps onto a real message; empty rows keep their
-- stale index after the inbox shrinks.
local function LiveIndex(frame)
    local row, name = ResolveRow(frame)
    if not row then return nil end
    local index = RowIndex(row, name)
    if not index or index < 1 then return nil end
    if index > (GetInboxNumItems() or 0) then return nil end
    return index, name
end

local function IsTruncated(fs)
    if not fs then return false end
    if fs.IsTruncated then return fs:IsTruncated() and true or false end
    -- Belt for a client without the widget method: compare the rendered string
    -- against the box it has to fit in.
    local strWidth = fs.GetStringWidth and fs:GetStringWidth()
    local boxWidth = fs.GetWidth and fs:GetWidth()
    return (strWidth and boxWidth and boxWidth > 0 and strWidth > boxWidth) or false
end

-------------------------------------------------------------------------------
--  Click shortcut
-------------------------------------------------------------------------------

local function OnRowClick(frame, button)
    if button ~= "LeftButton" then return end
    if not IsControlKeyDown() then return end
    if not Opt("ctrlReturn") then return end

    local index = LiveIndex(frame)
    if not index then return end

    local wasReturned, _, canReply = select(10, GetInboxHeaderInfo(index))
    if not wasReturned and canReply then
        ReturnInboxItem(index)
    end
end

-------------------------------------------------------------------------------
--  Tooltip
-------------------------------------------------------------------------------

-- State lives here rather than on GameTooltip so no Blizzard frame gains a key
-- of ours.
--   openedFor : the frame we opened a tooltip for because Blizzard had none
--               there. A tooltip we opened is ours to close: nobody else will.
--   deco*     : what we last appended, to tell "our lines are already there"
--               from "Blizzard rebuilt the tooltip and they are gone".
local openedFor
local decoFrame, decoIndex, decoLines

local HINT_R, HINT_G, HINT_B = 1, 0.82, 0

local function OnRowLeave(frame)
    if openedFor == frame then
        openedFor = nil
        if GameTooltip:IsOwned(frame) then GameTooltip:Hide() end
    end
    decoFrame = nil
end

local function OnRowEnter(frame)
    local index, name = LiveIndex(frame)
    if not index then return end
    -- Blizzard rebuilds an icon button's tooltip on enter and again every frame
    -- while it is hovered, and each rebuild lands here: only add our lines when
    -- they are not already there.
    if decoFrame == frame and decoIndex == index and GameTooltip:IsShown()
       and GameTooltip:IsOwned(frame) and GameTooltip:NumLines() == decoLines then
        return
    end

    local itemCount, _, wasReturned, _, canReply = select(8, GetInboxHeaderInfo(index))
    local opened = false

    -- Claims the tooltip on the first line we actually have, so a row with
    -- nothing to add is left completely alone. Appends when Blizzard already
    -- owns a tooltip for this frame, otherwise opens one -- never stomps a
    -- tooltip belonging to something else.
    local function Emit(text, isHint)
        if not opened then
            if GameTooltip:IsShown() and GameTooltip:IsOwned(frame) then
                -- A tooltip we opened earlier starts over instead of stacking.
                if openedFor == frame then GameTooltip:ClearLines() end
            else
                GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
                GameTooltip:ClearLines()
                openedFor = frame
            end
            opened = true
        end
        if isHint then
            GameTooltip:AddLine(text, HINT_R, HINT_G, HINT_B, true)
        else
            GameTooltip:AddLine(text, nil, nil, nil, true)
        end
    end

    if Opt("subjectTooltip") then
        local fs = _G[name .. "Subject"]
        local subject = fs and fs:GetText()
        if subject and subject ~= "" and IsTruncated(fs) then
            Emit(subject)
        end
    end

    -- A single attachment is already named by the row's own subject line.
    -- Slots are not guaranteed contiguous, so walk all of them rather than
    -- stopping after itemCount hits.
    if Opt("itemTooltip") and (itemCount or 0) > 1 then
        for i = 1, (_G.ATTACHMENTS_MAX_RECEIVE or 16) do
            local itemName, _, texture, count = GetInboxItem(index, i)
            if itemName then
                local link = GetInboxItemLink(index, i) or itemName
                local icon = texture and ("|T" .. texture .. ":0|t ") or ""
                Emit((count and count > 1)
                    and string.format("%s%s x%d", icon, link, count)
                    or  (icon .. link))
            end
        end
    end

    if Opt("ctrlReturn") and not wasReturned and canReply then
        Emit(EllesmereUI.L("Ctrl-click to return it to sender."), true)
    end

    if opened then
        GameTooltip:Show()
        decoFrame, decoIndex, decoLines = frame, index, GameTooltip:NumLines()
    end
end

-------------------------------------------------------------------------------
--  Money subject
-------------------------------------------------------------------------------

-- The subject we wrote last. Only a blank subject or our own text is ever
-- replaced, so anything the player typed, or the client set from an attached
-- item, is left alone.
local moneySubject

-- "[1g 23s 45c]": the highest coin present and every coin below it. The coin
-- symbols come from the client, so they are already in the player's language.
local function MoneyText(copper)
    local gold   = math.floor(copper / 10000)
    local silver = math.floor(copper / 100) % 100
    local rest   = copper % 100
    if gold > 0 then
        return string.format("[%d%s %d%s %d%s]", gold, GOLD_AMOUNT_SYMBOL,
            silver, SILVER_AMOUNT_SYMBOL, rest, COPPER_AMOUNT_SYMBOL)
    elseif silver > 0 then
        return string.format("[%d%s %d%s]", silver, SILVER_AMOUNT_SYMBOL,
            rest, COPPER_AMOUNT_SYMBOL)
    end
    return string.format("[%d%s]", rest, COPPER_AMOUNT_SYMBOL)
end

-- Runs after the client each time the amount in the Send Mail money field
-- changes. Writing the subject re-runs the client's own send check, so the
-- Send button enables itself.
local function OnMoneyChanged()
    if not Opt("moneySubject") then return end
    local current = SendMailSubjectEditBox:GetText()
    if current ~= "" and current ~= moneySubject then return end
    local copper = MoneyInputFrame_GetCopper(SendMailMoney)
    local text = copper > 0 and MoneyText(copper) or ""
    if text ~= current then SendMailSubjectEditBox:SetText(text) end
    moneySubject = text ~= "" and text or nil
end

-------------------------------------------------------------------------------
--  Wiring
-------------------------------------------------------------------------------

local hooked = false

local function HookWidget(widget, withEnter)
    if not (widget and widget.HasScript) then return end
    if widget:HasScript("OnClick") then widget:HookScript("OnClick", OnRowClick) end
    if withEnter and widget:HasScript("OnEnter") then widget:HookScript("OnEnter", OnRowEnter) end
    if widget:HasScript("OnLeave") then widget:HookScript("OnLeave", OnRowLeave) end
end

local function EnsureHooks()
    if hooked then return end
    if not _G.MailItem1 then return end   -- Blizzard_MailFrame not built yet
    for i = 1, (_G.INBOXITEMS_TO_DISPLAY or 7) do
        local row = _G["MailItem" .. i]
        if row then
            HookWidget(row, true)
            HookWidget(row.Button, false)   -- its enter is covered by the hook below
        end
    end
    -- The icon button's tooltip is built by this function: on enter, on
    -- MAIL_INBOX_UPDATE and every frame while hovered (the button's OnUpdate).
    -- Hooking the function rather than the script puts our lines back after
    -- each rebuild.
    hooksecurefunc("InboxFrameItem_OnEnter", OnRowEnter)
    -- The money field hands every change to a callback the client stored when
    -- the frame loaded, so it is that field that gets hooked, not the function.
    hooksecurefunc(SendMailMoney, "onValueChangedFunc", OnMoneyChanged)
    hooked = true
end

local INTERACTION_MAIL = Enum.PlayerInteractionType.MailInfo
local mailFrame = CreateFrame("Frame")

-- Nothing is hooked until the feature is actually switched on, so a player who
-- leaves it off pays for one frame and one PLAYER_LOGIN. The mailbox event is
-- dropped again the moment the rows are hooked, since hooks are permanent and
-- the handlers gate themselves on the setting from then on.
local eventsRegistered = false
local function SyncEventRegistration()
    local want = (Cfg().enabled == true) and not hooked
    if want == eventsRegistered then return end
    eventsRegistered = want
    if want then
        mailFrame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
    else
        mailFrame:UnregisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
    end
end

-- Called by the options toggle. Switching the feature on while standing at the
-- mailbox hooks the rows there and then, rather than on the next visit.
_G._EUI_Mail_Check = function()
    if Cfg().enabled == true and _G.MailFrame and _G.MailFrame:IsShown() then
        EnsureHooks()
    end
    SyncEventRegistration()
end

-- SavedVariables are not readable at file scope, so the setting can only be
-- consulted from PLAYER_LOGIN onwards.
mailFrame:RegisterEvent("PLAYER_LOGIN")
mailFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        SyncEventRegistration()
        return
    end
    if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" and arg1 ~= INTERACTION_MAIL then
        return
    end
    EnsureHooks()
    SyncEventRegistration()
end)
