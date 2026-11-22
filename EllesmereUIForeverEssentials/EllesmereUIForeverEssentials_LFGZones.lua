if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_LFGZones.lua  (WoW Forever only)
--  Show Solo Player Zones: the zone a player listed on their own in the
--  Looking For Group window is in, as the game sends it with the listing
--  (areaName) but never shows it, on the result row. Groups are left out
--  (the game sends their leader's zone only), and so is the player's own
--  listing. Every value read is tested for secrecy before it is compared.
-------------------------------------------------------------------------------
local _, module = ...
local PlainString = EllesmereUI.PlainString

-- Settings live in EllesmereUIDB.lfgZones; unset keys read these.
--   enabled   Show Solo Player Zones
local F = module.Feature("lfgZones", { enabled = false })

local hooked = false
-- Result row -> the zone FontString (a region of ours on it: no child frame
-- under Blizzard's rows).
local zoneText = setmetatable({}, { __mode = "k" })

-- A result table the game hands over readable, else nil.
local function Readable(t)
    if type(t) ~= "table" or issecretvalue(t) then return nil end
    if canaccesstable and not canaccesstable(t) then return nil end
    return t
end

-- The zone of a solo listing's player, or nil (a group, the player's own
-- listing, none sent, or secret).
local function Zone(resultID)
    if not resultID then return nil end
    local info = Readable(C_LFGList.GetSearchResultInfo(resultID))
    if not info then return nil end
    local count, mine = info.numMembers, info.hasSelf
    if type(count) ~= "number" or issecretvalue(count) or count ~= 1 then return nil end
    if issecretvalue(mine) or mine then return nil end
    local leader = Readable(C_LFGList.GetSearchResultLeaderInfo(resultID))
    if not leader then return nil end
    return PlainString(leader.areaName)
end

-- The parts after the player's name on a result row, left to right.
local NAME_LINE = { "DiscordIcon", "Level", "ClassIcon", "NewPlayerFriendlyIcon" }

-- Result row: on the playstyle line, below the group data, up to the row's
-- right edge. Rows without that line: after the last shown part of the name
-- line, short of the group data.
local function UpdateRow(row)
    if not F.Enabled() then return end   -- off: Apply has hidden the zones
    local zone = Zone(row.resultID)
    if not zone then
        if zoneText[row] then zoneText[row]:Hide() end
        return
    end
    local after, gap, limit
    local playstyle = row.PlaystyleLabel
    if playstyle then
        after, limit = playstyle, row:GetRight()
        gap = PlainString(playstyle:GetText()) and 8 or 0
    else
        after, gap, limit = row.Name, 6, row.DataDisplay:GetLeft()
        for _, key in ipairs(NAME_LINE) do
            local part = row[key]
            if part and part:IsShown() then after = part end
        end
    end
    local fs = zoneText[row]
    if not fs then
        fs = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmallLeft")
        fs:SetWordWrap(false)
        -- The face of the row's level text, which shares this text's font
        -- object (a window skin may have restyled the row before this existed).
        local face, _, flags
        if row.Level then face, _, flags = row.Level:GetFont() end
        if face then
            local _, size = fs:GetFont()
            fs:SetFont(face, size, flags)
        end
        zoneText[row] = fs
    end
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", after, "RIGHT", gap, 0)
    fs:SetText(zone)
    fs:SetWidth(0)
    -- Cut 8px short of limit; the edges can be secret during a restriction:
    -- no cut then.
    local left, width = after:GetRight(), fs:GetWidth()
    if not (issecretvalue(left) or issecretvalue(limit) or issecretvalue(width)) and left and limit then
        local room = limit - left - gap - 8
        if width > room then fs:SetWidth(math.max(room, 1)) end
    end
    fs:Show()
end

local function Hook()
    hooksecurefunc("LFGBrowseSearchEntry_Update", UpdateRow)
end

-- hooksecurefunc cannot be undone: hooked once, the hook follows the setting.
-- Turning it off hides the zones already drawn; turning it on paints the rows
-- on screen at once (the hook only sees rows Blizzard updates later).
local function Apply()
    if not F.Enabled() then
        for _, fs in pairs(zoneText) do fs:Hide() end
        return
    end
    local sb = _G.LFGBrowseFrameScrollBox
    if sb and sb:IsVisible() then
        -- Result rows only: the list's category headers have no group data.
        sb:ForEachFrame(function(row)
            if row.resultID and row.DataDisplay then UpdateRow(row) end
        end)
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
