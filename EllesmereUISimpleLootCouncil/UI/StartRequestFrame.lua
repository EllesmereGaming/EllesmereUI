if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end



SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text
addon.UI = addon.UI or {}
local Panel = {}
addon.UI.StartRequestFrame = Panel
local frame, list, prompt, shownRequest
local ROW_HEIGHT = 28
local VISIBLE_ROWS = 8
local WIDTH = 460

local function Build()
    local S, P, Tbl = addon.Style, addon.Pixel, addon.UI.Table
    frame = S.Window("SimpleLootCouncilStartRequestFrame", "startRequest", WIDTH, 400,
        T["Start loot session?"])
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    local content = frame.Content
    local width = WIDTH - S.size.PAD * 2
    local y = 0
    prompt = S.Label(content, S.fontBody, "LEFT")
    P.Point(prompt, "TOPLEFT", 0, -y)
    P.Point(prompt, "TOPRIGHT", 0, -y)
    P.Size(prompt, nil, ROW_HEIGHT)
    y = y + ROW_HEIGHT + S.size.GAP
    list = Tbl.Create(content, {
        {key="icon", title="", width=S.size.ICON_SM + S.size.ITEM_GAP + 4,
            render=function(cell, item)
                if not cell.Icon then
                    cell.Icon = S.ItemIcon(cell, S.size.ICON_SM)
                    P.Point(cell.Icon, "LEFT", 2, 0)
                    cell.Icon:EnableMouse(false)
                end
                cell.Text:SetText("")
                cell.Icon:SetItem(item.link)
            end},
        {key="link", title=T["Proposed items"], width=width-S.size.ICON_SM-S.size.ITEM_GAP-4,
            render=function(cell, item) cell.Text:SetText(item.link or "?") end},
    }, VISIBLE_ROWS, ROW_HEIGHT)
    P.Point(list, "TOPLEFT", 0, -y)
    list.onEnter = function(row, item)
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        S.SetTooltipItem(item.link)
        GameTooltip:Show()
    end
    list.onLeave = function() GameTooltip:Hide() end
    list.onClick = function(_, item) S.ItemModifiedClick(item.link) end
    y = y + list.headerHeight + VISIBLE_ROWS * ROW_HEIGHT + S.size.GAP
    local hint = S.Label(content, S.fontSmall, "LEFT")
    P.Point(hint, "TOPLEFT", 0, -y)
    P.Point(hint, "TOPRIGHT", 0, -y)
    P.Size(hint, nil, ROW_HEIGHT)
    hint:SetText(T["Yes adds these to your queue and starts the run. No leaves your queue as it is."])
    y = y + ROW_HEIGHT + S.size.SECTION
    local no = S.Button(content, T["No"])
    P.Point(no, "TOPRIGHT", 0, -y)
    no:SetScript("OnClick", function() addon.StartRequest:Resolve(shownRequest, false) end)
    local yes = S.Button(content, T["Yes"], {primary=true})
    P.Point(yes, "RIGHT", no, "LEFT", -S.size.GAP, 0)
    yes:SetScript("OnClick", function() addon.StartRequest:Resolve(shownRequest, true) end)
    y = y + S.size.BTN_H
    P.Size(frame, WIDTH, frame.HeaderHeight + S.size.PAD * 2 + y)
    frame:HookScript("OnHide", function()
        GameTooltip:Hide()
        local request = shownRequest
        shownRequest = nil
        if not request then return end


        addon.AutoClose:AfterHide(function(swept)
            if swept then
                Panel:Refresh()
            else
                addon.StartRequest:Resolve(request, false)
            end
        end)
    end)
end

function Panel:Refresh()
    local request = addon.StartRequest:GetPending()
    if not request then
        shownRequest = nil
        if frame then frame:Hide() end
        return
    end
    if not frame then Build() end
    local newRequest = shownRequest ~= request
    shownRequest = request
    local who = Ambiguate(request.who, "short")
    prompt:SetText(#request.items > 0
        and addon.Locale.Format(addon.Locale.Plural{
            one = "%s requests a loot session with %d proposed item.",
            other = "%s requests a loot session with %d proposed items.",
        }, #request.items, who, #request.items)
        or addon.Locale.Format(T["%s requests a loot session on your queued items."],
            who))
    addon.UI.Table.SetData(list, request.items, not newRequest)
    if newRequest then frame:RestorePosition() end
    frame:Show()
end

function Panel:Init()
    addon.Callbacks:Register("StartRequestChanged", function() Panel:Refresh() end)
end
