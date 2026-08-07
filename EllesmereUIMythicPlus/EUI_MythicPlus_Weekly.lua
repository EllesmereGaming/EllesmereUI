-------------------------------------------------------------------------------
--  EUI_MythicPlus_Weekly.lua  --  weekly / season run panel
--
--  A text panel docked beside the Group Finder listing this week's Mythic+
--  runs; hold Shift to read the season's best instead.
--
--  The panel is DOCKED, not free-floating: it parents to UIParent (never to
--  PVEFrame -- re-parenting into a secure frame's tree taints it) and anchors to
--  PVEFrame's top-right corner, so it tracks whatever the player does with the
--  Group Finder window. That is also why it is not an Unlock Mode element: its
--  position is derived from a Blizzard window rather than chosen on screen. Only
--  the dock offset is a setting.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local PANEL_W = 330

local panel, rows
local enabled = false
local frameHooked = false

local function P() return ns.P() end

-------------------------------------------------------------------------------
--  Rows
-------------------------------------------------------------------------------
local function GetRow(index)
    local fs = rows[index]
    if not fs then
        fs = panel:CreateFontString(nil, "OVERLAY")
        fs:SetJustifyH("LEFT")
        rows[index] = fs
    end
    -- Set before any SetText: a FontString with no font raises
    -- "SetText(): Font not set" the moment it is written to.
    ns.SetFont(fs, P().weekly.fontSize or 14)
    return fs
end

local function ClearRows()
    for _, fs in ipairs(rows) do
        fs:SetText("")
        fs:Hide()
        fs:ClearAllPoints()
    end
end

--- Emit one row and return the next index. `extraGap` opens up a section break.
local function EmitRow(index, text, extraGap)
    local fs = GetRow(index)
    fs:ClearAllPoints()
    if index == 1 then
        fs:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    else
        local gap = (P().weekly.rowSpacing or 4) + (extraGap or 0)
        fs:SetPoint("TOPLEFT", rows[index - 1], "BOTTOMLEFT", 0, -gap)
    end
    fs:Show()
    fs:SetText(text)
    return index + 1
end

-------------------------------------------------------------------------------
--  Content
-------------------------------------------------------------------------------
-- Vault reward item levels by keystone level (index 1..10).
--
-- FALLBACK ONLY. The live number comes from Blizzard:
-- C_MythicPlus.GetRewardLevelForDifficultyLevel returns the current weekly
-- (Great Vault) reward level for any key level, so it follows a season rollover
-- with no edit here, and it answers levels past this table's tail correctly
-- instead of flattening everything above 10 onto the last entry.
--
-- The table survives because that API cannot be trusted alone: it answers
-- nothing until C_MythicPlus.RequestMapInfo() data lands (Start below asks for
-- it), and it has a history of reporting the wrong reward level outright.
-- Refresh it each patch cycle alongside EllesmereUI.SEASON_PORTALS -- it is
-- only ever read when the API declines to answer.
local VAULT_ITEM_LEVELS = { 256, 259, 259, 263, 263, 266, 269, 269, 269, 272 }

-- keystone level -> item level, memoized. Only Blizzard's answer is ever
-- stored: caching a fallback would pin it for the session and shut the API out
-- once its data finally lands.
local vaultIlvlCache = {}

local function VaultItemLevel(keyLevel)
    if type(keyLevel) ~= "number" or keyLevel < 1 then return nil end
    local cached = vaultIlvlCache[keyLevel]
    if cached then return cached end

    if C_MythicPlus and C_MythicPlus.GetRewardLevelForDifficultyLevel then
        -- Reads 0 while the map info request is still in flight; that is
        -- "unknown", not a reward level.
        local weekly = C_MythicPlus.GetRewardLevelForDifficultyLevel(keyLevel)
        if type(weekly) == "number" and weekly > 0 then
            vaultIlvlCache[keyLevel] = weekly
            return weekly
        end
    end
    return VAULT_ITEM_LEVELS[math.min(keyLevel, #VAULT_ITEM_LEVELS)]
end

-- Run-history slots that fill a Great Vault row.
local VAULT_SLOTS = { [1] = true, [4] = true, [8] = true }

local function OwnClassText(text)
    return ns.ClassColorText(select(2, UnitClass("player")), text)
end

local function CompletionText(completed, level)
    return (completed and "|cff00ff00" or "|cffff0000") .. (level or "") .. "|r"
end

local function DungeonName(mapID)
    return ns.DungeonName(mapID, P().useAbbreviation ~= false)
end

--- Shared tail for both views: total run count, then one line per dungeon with
--- every level run in it.
local function BuildDungeonStats(runHistory, index)
    local byDungeon, order = {}, {}
    for _, run in ipairs(runHistory) do
        local id = run.mapChallengeModeID
        if not byDungeon[id] then
            byDungeon[id] = {}
            order[#order + 1] = id
        end
        local list = byDungeon[id]
        list[#list + 1] = run
    end
    table.sort(order)

    index = EmitRow(index,
        OwnClassText(EllesmereUI.L("Runs Completed") .. ": ") .. "|cffff8f00" .. #runHistory .. "|r", 10)

    for _, id in ipairs(order) do
        local runs = byDungeon[id]
        local text = DungeonName(id) .. "  |cff9385ffx|r|cff0ffff2" .. #runs .. "|r - "
        for i, run in ipairs(runs) do
            text = text .. CompletionText(run.completed, run.level)
            if i < #runs then text = text .. "|cff9d9d9d.|r" end
        end
        index = EmitRow(index, text)
    end
    return index
end

local function BuildWeeklyView(runHistory)
    ClearRows()
    if #runHistory == 0 then
        EmitRow(1, EllesmereUI.L("No Mythic+ runs this week"))
        return
    end
    table.sort(runHistory, function(a, b)
        if a.level == b.level then return a.mapChallengeModeID < b.mapChallengeModeID end
        return a.level > b.level
    end)

    local maxRows = P().weekly.maxRows or 8
    local index = EmitRow(1, OwnClassText(EllesmereUI.L("Weekly Best")))
    for i, run in ipairs(runHistory) do
        if i > maxRows then break end
        local text = CompletionText(run.completed, run.level) .. " " .. DungeonName(run.mapChallengeModeID)
        if VAULT_SLOTS[i] then
            local ilvl = VaultItemLevel(run.level) or "?"
            text = text .. " |cffa335ee[" .. ilvl .. " " .. EllesmereUI.L("Item Level") .. "]|r"
        end
        index = EmitRow(index, text)
    end
    BuildDungeonStats(runHistory, index)
end

local function BuildSeasonView(runHistory)
    ClearRows()
    if #runHistory == 0 then
        EmitRow(1, EllesmereUI.L("No Mythic+ runs this season"))
        return
    end

    local bestByDungeon = {}
    for _, run in ipairs(runHistory) do
        if run.completed then
            local id = run.mapChallengeModeID
            if not bestByDungeon[id] or run.level > bestByDungeon[id].level then
                bestByDungeon[id] = run
            end
        end
    end
    local best = {}
    for _, run in pairs(bestByDungeon) do best[#best + 1] = run end
    table.sort(best, function(a, b)
        if a.level == b.level then return a.mapChallengeModeID < b.mapChallengeModeID end
        return a.level > b.level
    end)

    local maxRows = P().weekly.maxRows or 8
    local index = EmitRow(1, OwnClassText(EllesmereUI.L("Season Best")))
    for i, run in ipairs(best) do
        if i > maxRows then break end
        index = EmitRow(index,
            "|c" .. ns.LevelColor(run.level) .. run.level .. "|r " .. DungeonName(run.mapChallengeModeID))
    end
    BuildDungeonStats(runHistory, index)
end

-------------------------------------------------------------------------------
--  Panel
-------------------------------------------------------------------------------
local function ApplyAnchor()
    local cfg = P().weekly
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", PVEFrame, "TOPRIGHT", cfg.offsetX or 3, cfg.offsetY or -1)
end

local function ShouldShow()
    return enabled and PVEFrame and PVEFrame:IsShown()
end

local Update  -- forward declaration (the modifier subscription toggles with it)

local function OnModifier()
    Update()
end

local function SyncModifierEvent()
    local cfg = P() and P().weekly
    local want = ShouldShow() and cfg and cfg.useModifierKey ~= false
    ns.SetEvents(OnModifier, { "MODIFIER_STATE_CHANGED" }, want and true or false)
end

function Update()
    if not panel then return end
    SyncModifierEvent()
    if not ShouldShow() then
        panel:Hide()
        return
    end
    ApplyAnchor()
    panel:Show()

    local seasonView = P().weekly.useModifierKey ~= false and IsShiftKeyDown()
    if seasonView then
        BuildSeasonView(C_MythicPlus.GetRunHistory(true, true) or {})
    else
        BuildWeeklyView(C_MythicPlus.GetRunHistory(false, true) or {})
    end
end

local function BuildPanel()
    if panel then return end
    rows = {}
    panel = CreateFrame("Frame", "EllesmereUIMythicPlusWeekly", UIParent)
    panel:SetSize(PANEL_W, 220)
    panel:Hide()
end

local function HookPVEFrame()
    if frameHooked or not PVEFrame then return end
    frameHooked = true
    PVEFrame:HookScript("OnShow", function() Update() end)
    PVEFrame:HookScript("OnHide", function() Update() end)
end

-------------------------------------------------------------------------------
--  Feature
-------------------------------------------------------------------------------
local EVENTS = { "PLAYER_ENTERING_WORLD", "CHALLENGE_MODE_COMPLETED" }

local function OnEvent(event)
    -- A season rollover changes every vault reward level, so drop the memo on
    -- the world transition that must follow one rather than trusting numbers
    -- resolved under the old season.
    if event == "PLAYER_ENTERING_WORLD" then
        wipe(vaultIlvlCache)
    end
    -- Run history lands a moment after the event; one deferred pass settles it.
    C_Timer.After(1, Update)
end

ns.RegisterFeature({
    id = "weekly",

    IsEnabled = function(p)
        return p.weekly.enabled ~= false
    end,

    Start = function()
        BuildPanel()
        HookPVEFrame()
        -- Unlocks the reward-level lookups above (and the rest of C_MythicPlus
        -- alongside them). Asked for here, on first enable, so a disabled panel
        -- still costs the game nothing.
        if C_MythicPlus and C_MythicPlus.RequestMapInfo then
            C_MythicPlus.RequestMapInfo()
        end
    end,

    Apply = function(on)
        enabled = on
        ns.SetEvents(OnEvent, EVENTS, on)
        if on then HookPVEFrame() end
        Update()
    end,
})
