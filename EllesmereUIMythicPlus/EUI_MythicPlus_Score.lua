-------------------------------------------------------------------------------
--  EUI_MythicPlus_Score.lua  --  dungeon score overlay
--
--  Draws dungeon name, best keystone level and season score straight onto each
--  Blizzard dungeon icon in the Group Finder's Mythic+ tab.
--
--  Taint discipline: the icons belong to Blizzard_ChallengesUI, so no field is
--  ever written onto one -- our FontStrings and hook flag live in the weak-keyed
--  side table below. Blizzard's own "highest level" text is claimed by ALPHA,
--  never Hide(), so releasing it is a pure restore. Hooks are HookScript /
--  hooksecurefunc only, and because a hook can never be removed, the handler
--  body early-outs while the feature is off instead.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local FFD = setmetatable({}, { __mode = "k" })
local function GetFFD(frame)
    local d = FFD[frame]
    if not d then d = {}; FFD[frame] = d end
    return d
end

local enabled = false
local challengesHooked = false

-------------------------------------------------------------------------------
--  Rendering
-------------------------------------------------------------------------------
local function BestRunForMap(mapID)
    local inTime, overtime = C_MythicPlus.GetSeasonBestForMap(mapID)
    local level, isOvertime = 0, false
    if inTime or overtime then
        -- Prefer the in-time run whenever it scored at least as well; an
        -- overtime best is dimmed so a depleted key reads differently.
        local useInTime = (inTime and not overtime)
            or (inTime and overtime and inTime.dungeonScore >= overtime.dungeonScore)
        local best = useInTime and inTime or overtime
        level = best.level or 0
        isOvertime = not useInTime
    end
    local totalScore = select(2, C_MythicPlus.GetSeasonBestAffixScoreInfoForMap(mapID)) or 0
    return level, totalScore, isOvertime
end

local function GetLine(icon, key, size)
    local d = GetFFD(icon)
    d.lines = d.lines or {}
    local fs = d.lines[key]
    if not fs then
        fs = icon:CreateFontString(nil, "OVERLAY")
        fs:SetJustifyH("CENTER")
        fs:SetJustifyV("MIDDLE")
        d.lines[key] = fs
    end
    ns.SetFont(fs, size)
    return fs
end

local function PlaceLine(fs, icon, x, y, shown)
    fs:ClearAllPoints()
    fs:SetPoint("CENTER", icon, "CENTER", x or 0, y or 0)
    fs:SetShown(shown ~= false)
end

--- Restore an icon to its untouched state: our text hidden, Blizzard's own
--- level text back to full alpha.
local function ReleaseIcon(icon)
    local d = FFD[icon]
    if d and d.lines then
        for _, fs in pairs(d.lines) do fs:Hide() end
    end
    if icon.HighestLevel then icon.HighestLevel:SetAlpha(1) end
end

local function RefreshIcon(icon)
    if not enabled then return ReleaseIcon(icon) end
    local p = ns.P()
    if not p then return end
    local mapID = icon.mapID
    if not mapID or not ns.IsSeasonMap(mapID) then return ReleaseIcon(icon) end

    local cfg = p.score
    if icon.HighestLevel then
        icon.HighestLevel:SetAlpha(cfg.hideBlizzardLevel ~= false and 0 or 1)
    end

    local level, totalScore, overtime = BestRunForMap(mapID)
    local name = ns.DungeonName(mapID, p.useAbbreviation ~= false)

    local nameFS  = GetLine(icon, "name",  cfg.nameSize  or 16)
    local levelFS = GetLine(icon, "level", cfg.levelSize or 20)
    local scoreFS = GetLine(icon, "score", cfg.scoreSize or 20)

    PlaceLine(nameFS,  icon, cfg.nameX,  cfg.nameY,  cfg.nameShown)
    PlaceLine(levelFS, icon, cfg.levelX, cfg.levelY, cfg.levelShown)
    PlaceLine(scoreFS, icon, cfg.scoreX, cfg.scoreY, cfg.scoreShown)

    nameFS:SetText("|cffffd700" .. name .. "|r")
    levelFS:SetText("|c" .. ns.LevelColor(level, overtime) .. level .. "|r")
    scoreFS:SetText("|c" .. ns.ScoreColor(totalScore) .. totalScore .. "|r")
end

-------------------------------------------------------------------------------
--  Hooks
-------------------------------------------------------------------------------
local function HookIcon(icon)
    local d = GetFFD(icon)
    if not d.hooked then
        d.hooked = true
        if type(icon.SetUp) == "function" then
            hooksecurefunc(icon, "SetUp", RefreshIcon)
        end
        icon:HookScript("OnShow", RefreshIcon)
    end
    RefreshIcon(icon)
end

local function RefreshAllIcons()
    local cf = _G.ChallengesFrame
    if not cf or not cf.DungeonIcons then return end
    for _, icon in ipairs(cf.DungeonIcons) do
        if enabled then HookIcon(icon) else ReleaseIcon(icon) end
    end
end

local function TryHookChallengesFrame()
    local cf = _G.ChallengesFrame
    if not cf then return end
    if not challengesHooked then
        challengesHooked = true
        if type(cf.Update) == "function" then
            hooksecurefunc(cf, "Update", RefreshAllIcons)
        end
        cf:HookScript("OnShow", RefreshAllIcons)
    end
    RefreshAllIcons()
end

-- Blizzard_ChallengesUI is load-on-demand and we never force it: the player
-- cannot see a dungeon icon before the game itself has loaded that addon, so
-- waiting for its ADDON_LOADED costs nothing and saves the load at login.
local EVENTS = { "ADDON_LOADED", "CHALLENGE_MODE_COMPLETED" }

local function OnEvent(event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= "Blizzard_ChallengesUI" then return end
        TryHookChallengesFrame()
    else
        RefreshAllIcons()
    end
end

-------------------------------------------------------------------------------
--  Feature
-------------------------------------------------------------------------------
ns.RegisterFeature({
    id = "score",

    IsEnabled = function(p)
        return p.score.enabled ~= false
    end,

    Start = function()
        TryHookChallengesFrame()
    end,

    Apply = function(on)
        enabled = on
        ns.SetEvents(OnEvent, EVENTS, on)
        if on then TryHookChallengesFrame() end
        RefreshAllIcons()
    end,
})
