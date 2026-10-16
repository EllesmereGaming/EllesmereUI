if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_LFGZones.lua  (WoW Forever only)
--  Show Player Zones: the zone each player of a Looking For Group listing is
--  in, as the game sends it with the listing (areaName) but never shows it.
--  The leader's follows their level on the result row, every player's follows
--  their role in the listing's tooltip.
-------------------------------------------------------------------------------
local _, module = ...

-- Settings live in EllesmereUIDB.lfgZones; unset keys read these.
--   enabled   Show Player Zones
local F = module.Feature("lfgZones", { enabled = false })

local hooked = false
-- Result row or tooltip player frame -> our zone FontString.
local zoneText = setmetatable({}, { __mode = "k" })

-- The zone a player's info carries, or nil (none sent, or secret).
local function Zone(info)
    local area = info and info.areaName
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

-- The parts after the leader's name on a result row, left to right.
local NAME_LINE = { "DiscordIcon", "Level", "ClassIcon", "NewPlayerFriendlyIcon" }

-- Result row: on the playstyle line, below the group data, up to the row's
-- right edge. Rows without that line: after the last shown part of the name
-- line, short of the group data.
local function UpdateRow(row)
    local zone = F.Enabled() and row.resultID and Zone(C_LFGList.GetSearchResultLeaderInfo(row.resultID))
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

-- Tooltip player frame: after the role icons. Returns its right edge.
local function UpdatePlayer(frame, info)
    local zone = frame:IsShown() and Zone(info)
    if not zone then
        if zoneText[frame] then zoneText[frame]:Hide() end
        return nil
    end
    local after = frame.Level
    for _, icon in ipairs(frame.Roles) do
        if icon:IsShown() then after = icon end
    end
    local fs = ZoneString(frame)
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", after, "RIGHT", 4, 0)
    fs:SetText(zone)
    fs:Show()
    return fs:GetRight()
end

-- The tooltip sizes itself to its rows: widened when a zone runs past it.
local function UpdateTooltip(tip, resultID)
    if not F.Enabled() then
        if zoneText[tip.Leader] then zoneText[tip.Leader]:Hide() end
        for frame in tip.memberPool:EnumerateActive() do
            if zoneText[frame] then zoneText[frame]:Hide() end
        end
        return
    end
    local right = UpdatePlayer(tip.Leader, C_LFGList.GetSearchResultLeaderInfo(resultID)) or 0
    -- Member frames come from a pool: matched to their player by name.
    local byName = {}
    local info = C_LFGList.GetSearchResultInfo(resultID)
    for i = 1, (info and info.numMembers) or 0 do
        local member = C_LFGList.GetSearchResultPlayerInfo(resultID, i)
        local name = member and member.name
        if name and not issecretvalue(name) then byName[name] = member end
    end
    for frame in tip.memberPool:EnumerateActive() do
        local name = frame.Name:GetText()
        local r = UpdatePlayer(frame, name and not issecretvalue(name) and byName[name])
        if r and r > right then right = r end
    end
    local left = tip:GetLeft()
    if left and right - left + 11 > tip:GetWidth() then
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
