-------------------------------------------------------------------------------
--  EllesmereUIMythicPlus.lua  --  Mythic+ toolkit for EllesmereUI
--
--  One addon, five independent features: the Group Finder dungeon-icon score
--  overlay, the weekly/season run panel docked to that window, one-click
--  teleport buttons with an optional party announce, a party keystone list and
--  an in-dungeon keystone banner. Every feature builds itself on first enable
--  and holds no events, frames or hooks while it is off.
--
--  Season data is deliberately NOT duplicated here. The current season's
--  challenge maps come from C_ChallengeMode.GetMapTable(), and abbreviations
--  plus teleport spells resolve out of EllesmereUI.SEASON_PORTALS by matching
--  the localized dungeon name -- the same single season list _Keys.lua and
--  _TeleportPrompt.lua read. Refreshing that one list each patch cycle is all
--  the season maintenance this module needs.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local EMP = EllesmereUI.Lite.NewAddon(ADDON_NAME)
ns.EMP = EMP

-- Key in EllesmereUI._addonKeyToFolder; drives the per-module font override.
ns.FONT_KEY = "mythicPlus"

-------------------------------------------------------------------------------
--  Database defaults
-------------------------------------------------------------------------------
local DB_DEFAULTS = {
    profile = {
        enabled         = true,
        useAbbreviation = true,

        score = {
            enabled           = true,
            hideBlizzardLevel = true,
            nameShown  = true, nameSize  = 16, nameX  = 0, nameY  =  22,
            levelShown = true, levelSize = 20, levelX = 0, levelY =   0,
            scoreShown = true, scoreSize = 20, scoreX = 0, scoreY = -22,
        },

        weekly = {
            enabled        = true,
            useModifierKey = true,
            fontSize       = 14,
            rowSpacing     = 4,
            maxRows        = 8,
            offsetX        = 3,
            offsetY        = -1,
        },

        teleport = {
            enabled  = true,
            -- OFF by default: this is the only feature in the suite that speaks
            -- to other players, and nobody should start broadcasting to their
            -- group because they installed an addon.
            announce = false,
            -- Empty means "follow the active locale's default", so the announce
            -- text keeps tracking the client language. Only a real user edit is
            -- ever stored.
            template = "",
        },

        keystoneList = {
            enabled    = true,
            iconSize   = 42,
            fontSize   = 12,
            rowSpacing = 4,
        },

        centerBanner = {
            enabled    = true,
            fontSize   = 18,
            rowSpacing = 6,
        },
    },
}

local db
function ns.P()
    return db and db.profile
end

-------------------------------------------------------------------------------
--  Shared event fan-out
--
--  ONE event frame, created in this file's main chunk so every handler's call
--  tree bills this addon rather than the parent (see the CPU-attribution note
--  in EllesmereUI_Lite.lua). Features subscribe when they turn on and
--  unsubscribe when they turn off; an event with no subscribers left is
--  unregistered outright, so a disabled feature really does receive nothing.
-------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local eventSubs = {}   -- event -> dense array of callbacks

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local subs = eventSubs[event]
    if not subs then return end
    -- A handler routinely unsubscribes from inside its own dispatch (the weekly
    -- panel drops MODIFIER_STATE_CHANGED the moment the Group Finder closes), so
    -- the walk must not cache the length. table.remove shifts the tail down, so
    -- a slot whose callback removed itself now holds the NEXT callback and has
    -- to be re-tested rather than stepped over.
    local i = 1
    while true do
        local fn = subs[i]
        if not fn then break end
        fn(event, ...)
        if subs[i] == fn then i = i + 1 end
    end
end)

--- Subscribe or unsubscribe one callback across a list of events.
-- Idempotent in both directions, so a feature can call it on every Apply
-- without tracking its own registration state.
function ns.SetEvents(fn, events, enabled)
    for _, event in ipairs(events) do
        local subs = eventSubs[event]
        local at
        if subs then
            for i = 1, #subs do
                if subs[i] == fn then at = i; break end
            end
        end
        if enabled then
            if not subs then subs = {}; eventSubs[event] = subs end
            if not at then
                subs[#subs + 1] = fn
                if #subs == 1 then eventFrame:RegisterEvent(event) end
            end
        elseif at then
            table.remove(subs, at)
            if #subs == 0 then
                eventSubs[event] = nil
                eventFrame:UnregisterEvent(event)
            end
        end
    end
end

-- Self-disarming OnUpdate driver for this addon. The frame is born in this
-- main chunk, so every tick bills EllesmereUIMythicPlus (EllesmereUI_Ticker.lua).
ns.Drv = EllesmereUI.Tick and EllesmereUI.Tick.NewDriver(CreateFrame("Frame"))

-------------------------------------------------------------------------------
--  Fonts
-------------------------------------------------------------------------------
function ns.GetFont(size)
    local path = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath(ns.FONT_KEY))
              or "Fonts\\FRIZQT__.TTF"
    local flag = (EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag(ns.FONT_KEY))
              or ""
    return path, size or 12, flag
end

--- Apply the module font at `size` to a FontString, priming the shadow so
--- unoutlined text stays readable over the dungeon art.
function ns.SetFont(fs, size)
    local path, sz, flag = ns.GetFont(size)
    if EllesmereUI.PrimeFontShadow then
        EllesmereUI.PrimeFontShadow(fs, flag == "")
    end
    fs:SetFont(path, sz, flag)
end

-------------------------------------------------------------------------------
--  Colors
--
--  Keystone levels and dungeon scores are tinted with the item-quality ramp:
--  every two key levels moves one quality step, and +15 and above jumps a
--  further step so the top brackets stay distinguishable.
-------------------------------------------------------------------------------
local LEVEL_COLORS = {
    [0] = "ffffffff",
    [1] = "ff1eff00",
    [2] = "ff0070dd",
    [3] = "ffa335ee",
    [4] = "ffff8000",
    [5] = "ffe6cc80",
    [6] = "fff46fc8",
}
local OVERTIME_COLOR = "ffa3a3a3"

local SCORE_RANGES = {
    { minScore = 455, index = 6 },
    { minScore = 410, index = 5 },
    { minScore = 380, index = 4 },
    { minScore = 320, index = 3 },
    { minScore = 230, index = 2 },
    { minScore = 155, index = 1 },
    { minScore = 0,   index = 0 },
}

function ns.LevelColor(level, overtime)
    if overtime then return OVERTIME_COLOR end
    if not level or level <= 0 then return LEVEL_COLORS[0] end
    local bump = level >= 15 and 1 or 0
    local idx = math.min(math.floor((math.max(level, 2) - 2) / 2), 5) + bump
    return LEVEL_COLORS[idx] or LEVEL_COLORS[0]
end

function ns.ScoreColor(score)
    if not score or score == 0 then return LEVEL_COLORS[0] end
    for _, range in ipairs(SCORE_RANGES) do
        if score >= range.minScore then
            return LEVEL_COLORS[range.index] or LEVEL_COLORS[0]
        end
    end
    return LEVEL_COLORS[0]
end

--- "|cffRRGGBBtext|r" using a unit's or classID's class color.
function ns.ClassColorText(classFile, text)
    local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if not c then return text end
    return string.format("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, text)
end

function ns.ClassFileFromID(classID)
    if not classID or not GetClassInfo then return nil end
    return (select(2, GetClassInfo(classID)))
end

-------------------------------------------------------------------------------
--  Season data
--
--  Built lazily and only cached once every current-season map resolves a name:
--  an early call with partially-loaded map data retries on the next use instead
--  of freezing an incomplete table.
-------------------------------------------------------------------------------
local seasonMapIDs      -- ordered array of challenge mapIDs
local seasonInfo        -- mapID -> { abbr = "WRS", spellIDs = { id, ... } }
local seasonByName      -- localized instance name -> mapID

local function BuildSeasonData()
    if seasonInfo then return true end
    if not (C_ChallengeMode and C_ChallengeMode.GetMapTable and C_ChallengeMode.GetMapUIInfo) then
        return false
    end
    local maps = C_ChallengeMode.GetMapTable()
    if not maps or #maps == 0 then return false end

    -- Lowercase dungeon name -> SEASON_PORTALS entry (short name + teleports).
    local portalByName = {}
    for _, entry in ipairs(EllesmereUI.SEASON_PORTALS or {}) do
        for _, name in ipairs(entry.names or {}) do
            portalByName[name] = entry
        end
    end

    local ids, info, byName = {}, {}, {}
    for _, mapID in ipairs(maps) do
        local name = C_ChallengeMode.GetMapUIInfo(mapID)
        if not name then return false end
        ids[#ids + 1] = mapID
        byName[name] = mapID

        local portal = portalByName[name:lower()]
        local spellIDs
        if portal and portal.spellID then
            spellIDs = { portal.spellID }
            for _, alt in ipairs(portal.altSpellIDs or {}) do
                spellIDs[#spellIDs + 1] = alt
            end
        end
        info[mapID] = { abbr = portal and portal.short, spellIDs = spellIDs }
    end

    seasonMapIDs, seasonInfo, seasonByName = ids, info, byName
    return true
end
ns.BuildSeasonData = BuildSeasonData

function ns.SeasonMapIDs()
    if not BuildSeasonData() then return nil end
    return seasonMapIDs
end

function ns.IsSeasonMap(mapID)
    if not mapID or not BuildSeasonData() then return false end
    return seasonInfo[mapID] ~= nil
end

function ns.MapIDFromName(instanceName)
    if not instanceName or not BuildSeasonData() then return nil end
    return seasonByName[instanceName]
end

--- Teleport spell ids for a dungeon, best-known first. nil when the current
--- SEASON_PORTALS list has no entry for that dungeon.
function ns.TeleportSpells(mapID)
    if not mapID or not BuildSeasonData() then return nil end
    local info = seasonInfo[mapID]
    return info and info.spellIDs
end

--- Short abbreviation when the user asked for it and the season list has one,
--- otherwise the localized full dungeon name.
function ns.DungeonName(mapID, useAbbreviation)
    if useAbbreviation and BuildSeasonData() then
        local info = seasonInfo[mapID]
        if info and info.abbr then return info.abbr end
    end
    if C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
        local name = C_ChallengeMode.GetMapUIInfo(mapID)
        if name then return name end
    end
    return EllesmereUI.L("Unknown")
end

--- Dungeon icon texture for a keystone row, with a generic key as fallback.
local FALLBACK_KEY_ICON = [[Interface\Icons\INV_Misc_Key_14]]
function ns.DungeonIcon(mapID)
    if mapID and mapID ~= 0 and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
        local _, _, _, texture = C_ChallengeMode.GetMapUIInfo(mapID)
        if texture and texture ~= 0 then return texture end
    end
    return FALLBACK_KEY_ICON
end

-------------------------------------------------------------------------------
--  Feature registry
--
--  Every feature file registers one table here. Start() runs once, the first
--  time the feature is enabled (that is what keeps a disabled feature at zero
--  cost); Apply(on) then runs on every settings change with the resolved
--  on/off state so a started feature can hide and unhook itself again.
-------------------------------------------------------------------------------
ns.features = {}

function ns.RegisterFeature(feature)
    ns.features[#ns.features + 1] = feature
end

local function ApplyAll()
    local p = ns.P()
    if not p then return end
    local moduleOn = p.enabled ~= false
    for _, feature in ipairs(ns.features) do
        local on = moduleOn and feature.IsEnabled(p)
        if on and not feature._started then
            feature._started = true
            feature.Start()
        end
        if feature._started then
            feature.Apply(on)
        end
    end
end
ns.Apply = ApplyAll
_G._EMP_Apply = ApplyAll

-- Unlock-element registration is MODULE level, not per feature: the keystone
-- list and banner share one registration call, and hanging it off either
-- feature's table would silently drop the other element if that feature were
-- ever reordered or removed.
local unlockHooks = {}

function ns.RegisterUnlockHook(fn)
    unlockHooks[#unlockHooks + 1] = fn
end

--- Re-register every unlock element. Called by the profile system after a
--- profile apply, where the outgoing profile's registrations are stale.
local function RegisterUnlock()
    for _, fn in ipairs(unlockHooks) do
        fn()
    end
end
ns.RegisterUnlock = RegisterUnlock
_G._EMP_RegisterUnlock = RegisterUnlock

-------------------------------------------------------------------------------
--  Lifecycle
-------------------------------------------------------------------------------
function EMP:OnInitialize()
    db = EllesmereUI.Lite.NewDB("EllesmereUIMythicPlusDB", DB_DEFAULTS)
    ns.db = db
    _G._EMP_DB = db
end

function EMP:OnEnable()
    ApplyAll()
    RegisterUnlock()
end
