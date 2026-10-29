if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_LFGZones.lua  (WoW Forever only)
--  Show Solo Player Zones: the zone a player listed on their own in the
--  Looking For Group window is in, as the game sends it with the listing
--  (areaName) but never shows it: on the result row and in the listing's
--  tooltip. Groups are left out (the game sends their leader's zone only).
-------------------------------------------------------------------------------
local _, module = ...

-- Settings live in EllesmereUIDB.lfgZones; unset keys read these.
--   enabled   Show Solo Player Zones
local F = module.Feature("lfgZones", { enabled = false })

local hooked = false
-- Result row or tooltip leader frame -> our zone FontString.
local zoneText = setmetatable({}, { __mode = "k" })

-- The zone of a solo listing's player, or nil (a group, none sent, or secret).
local function Zone(resultID)
    if not (F.Enabled() and resultID) then return nil end
    local info = C_LFGList.GetSearchResultInfo(resultID)
    local count = info and info.numMembers
    if count == nil or issecretvalue(count) or count ~= 1 then return nil end
    local leader = C_LFGList.GetSearchResultLeaderInfo(resultID)
    local area = leader and leader.areaName
    if area == nil or issecretvalue(area) or area == "" then return nil end
    return area
end

local function ZoneString(frame)
    local fs = zoneText[frame]
    if not fs then
        fs = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmallLeft")
        fs:SetWordWrap(false)
        zoneText[frame] = fs
    end
    return fs
end

-- The parts after the player's name on a result row, left to right.
local NAME_LINE = { "DiscordIcon", "Level", "ClassIcon", "NewPlayerFriendlyIcon" }

-- Result row: on the playstyle line, below the group data, up to the row's
-- right edge. Rows without that line: after the last shown part of the name
-- line, short of the group data.
local function UpdateRow(row)
    local zone = Zone(row.resultID)
    if not zone then
        if zoneText[row] then zoneText[row]:Hide() end
        return
    end
    local after, gap, limit
    local playstyle = row.PlaystyleLabel
    if playstyle then
        after, limit = playstyle, row:GetRight()
        local text = playstyle:GetText()
        gap = (text and text ~= "") and 8 or 0
    else
        after, gap, limit = row.Name, 6, row.DataDisplay:GetLeft()
        for _, key in ipairs(NAME_LINE) do
            local part = row[key]
            if part and part:IsShown() then after = part end
        end
    end
    local fs = ZoneString(row)
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", after, "RIGHT", gap, 0)
    fs:SetText(zone)
    fs:SetWidth(0)
    local left = after:GetRight()
    if left and limit and fs:GetWidth() > limit - left - gap - 8 then
        fs:SetWidth(math.max(limit - left - gap - 8, 1))
    end
    fs:Show()
end

-- Tooltip: after the player's role icons. The tooltip sizes itself to its
-- rows, so it is widened when the zone runs past it.
local function UpdateTooltip(tip, resultID)
    local leader = tip.Leader
    local zone = leader:IsShown() and Zone(resultID)
    if not zone then
        if zoneText[leader] then zoneText[leader]:Hide() end
        return
    end
    local after = leader.Level
    for _, icon in ipairs(leader.Roles) do
        if icon:IsShown() then after = icon end
    end
    local fs = ZoneString(leader)
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", after, "RIGHT", 4, 0)
    fs:SetText(zone)
    fs:Show()
    local left, right = tip:GetLeft(), fs:GetRight()
    if left and right and right - left + 11 > tip:GetWidth() then
        tip:SetWidth(right - left + 11)
    end
end

local function Hook()
    hooksecurefunc("LFGBrowseSearchEntry_Update", UpdateRow)
    hooksecurefunc("LFGBrowseSearchEntryTooltip_UpdateAndShow", UpdateTooltip)
end

-- hooksecurefunc cannot be undone: hooked once, the hooks follow the setting.
local function Apply()
    if hooked or not F.Enabled() then return end
    hooked = true
    EventUtil.ContinueOnAddOnLoaded("Blizzard_GroupFinder_VanillaStyle", Hook)
end

-- Options-page entry points.
EllesmereUI._LFGZones = {
    Get = F.Get,
    Cfg = F.Cfg,
    Apply = Apply,
}

F.Start(Apply)
