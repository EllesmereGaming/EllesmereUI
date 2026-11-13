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
-- Result row or tooltip leader frame -> the zone FontString (a region of
-- ours on it: no child frame under Blizzard's rows).
local zoneText = setmetatable({}, { __mode = "k" })

-- The zone of a solo listing's player, or nil (a group, none sent, or secret).
local function Zone(resultID)
    if not resultID then return nil end
    local info = C_LFGList.GetSearchResultInfo(resultID)
    local count = info and info.numMembers
    if count == nil or issecretvalue(count) or count ~= 1 then return nil end
    local leader = C_LFGList.GetSearchResultLeaderInfo(resultID)
    local area = leader and leader.areaName
    if area == nil or issecretvalue(area) or area == "" then return nil end
    return area
end

-- Shows zone on host after the region after, cut to end margin short of
-- limit; no zone hides it. The edges can be secret during a restriction: no
-- cut then.
local function Put(host, zone, after, gap, limit, margin)
    local fs = zoneText[host]
    if not zone then
        if fs then fs:Hide() end
        return
    end
    if not fs then
        fs = host:CreateFontString(nil, "ARTWORK", "GameFontDisableSmallLeft")
        fs:SetWordWrap(false)
        zoneText[host] = fs
    end
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", after, "RIGHT", gap, 0)
    fs:SetText(zone)
    fs:SetWidth(0)
    local left, width = after:GetRight(), fs:GetWidth()
    if left and limit and not (issecretvalue(left) or issecretvalue(limit) or issecretvalue(width)) then
        local room = limit - left - gap - margin
        if width > room then fs:SetWidth(math.max(room, 1)) end
    end
    fs:Show()
end

-- The parts after the player's name on a result row, left to right.
local NAME_LINE = { "DiscordIcon", "Level", "ClassIcon", "NewPlayerFriendlyIcon" }

-- Result row: on the playstyle line, below the group data, up to the row's
-- right edge. Rows without that line: after the last shown part of the name
-- line, short of the group data.
local function UpdateRow(row)
    if not F.Enabled() then return end   -- off: Apply has hidden the zones
    local zone = Zone(row.resultID)
    if not zone then return Put(row) end
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
    Put(row, zone, after, gap, limit, 8)
end

-- Tooltip: after the player's role icons, cut to the tooltip's width.
local function UpdateTooltip(tip, resultID)
    if not F.Enabled() then return end   -- off: Apply has hidden the zones
    local leader = tip.Leader
    local zone = leader:IsShown() and Zone(resultID)
    if not zone then return Put(leader) end
    local after = leader.Level
    for _, icon in ipairs(leader.Roles) do
        if icon:IsShown() then after = icon end
    end
    Put(leader, zone, after, 4, tip:GetRight(), 11)
end

local function Hook()
    hooksecurefunc("LFGBrowseSearchEntry_Update", UpdateRow)
    hooksecurefunc("LFGBrowseSearchEntryTooltip_UpdateAndShow", UpdateTooltip)
end

-- hooksecurefunc cannot be undone: hooked once, the hooks follow the setting.
-- Turning it off hides the zones already drawn.
local function Apply()
    if not F.Enabled() then
        for _, fs in pairs(zoneText) do fs:Hide() end
        return
    end
    if hooked then return end
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
