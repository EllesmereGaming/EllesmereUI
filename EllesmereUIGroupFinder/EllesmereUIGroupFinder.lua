if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
-- EllesmereUIGroupFinder.lua: premade group filters, list tweaks and the M+
-- applications bar. Nothing hooks in until it's enabled.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EllesmereUI and EllesmereUI._ModuleNS and EllesmereUI.Lite and EllesmereUI.HELD_BACK_ADDONS and EllesmereUI.SetFontFamily and EllesmereUI.PREVIEW_ROSTER and EllesmereUI.CharData) then EUI_CLIENT_BLOCKED = true; return end -- stale-parent guard: a partially updated install (old parent, new child) goes dormant via the line-1 failsafe instead of erroring (group titles, applicant names and notes take font families through SetFontFamily, and the settings preview names its samples from PREVIEW_ROSTER; its per-character data is in the parent's roster: CharData)
-- Held back from this release (EllesmereUI.HELD_BACK_ADDONS): nothing runs,
-- and with no namespace published the options page never registers.
if EllesmereUI.HELD_BACK_ADDONS[ADDON_NAME] then return end
EllesmereUI._ModuleNS[ADDON_NAME] = ns  -- options file grabs the ns from here

local GF = EllesmereUI.Lite.NewAddon(ADDON_NAME)
-- Work on Blizzard frames that waits for combat to end; inert until a Defer.
ns.CombatQueue = EllesmereUI.NewCombatQueue(CreateFrame("Frame"))

local DEFAULTS = {
    padding          = 12,
    nameColors       = false,
    classTooltip     = true,
    leaderRating     = true,
    leaderCrown      = true,
    missingRoles     = true,
    specIcons        = true,
    iconSize         = 125,
    cancelOldest     = false,
    dungeonAbbr      = false,
    dungeonScore     = false,
}
ns.DEFAULTS = DEFAULTS

local APPS_DEFAULTS = {
    enabled       = false,
    scope         = "character",
    texture       = "none",
    showAccepted  = true,
    showDeclined  = true,
    showDelisted  = true,
    showCancelled = true,
}
ns.APPS_DEFAULTS = APPS_DEFAULTS

local db

local function Profile() return db and db.profile end

-- Account-wide bits live in EllesmereUIDB.<key>, outside profiles.
local function Account(key)
    if not EllesmereUIDB then EllesmereUIDB = {} end
    local t = EllesmereUIDB[key]
    if type(t) ~= "table" then
        t = {}
        EllesmereUIDB[key] = t
    end
    return t
end

-- Account-wide so profile swaps and imports never flip it.
function ns.Enabled()
    local t = EllesmereUIDB and EllesmereUIDB.groupFinder
    return type(t) == "table" and t.enabled == true or false
end

function ns.SetEnabled(v)
    Account("groupFinder").enabled = v and true or false
end

-- True while another premade groups filter that hooks the same panel is loaded:
-- Group Finder can't be turned on then (its page and the login announcement ask).
function ns.Blocked()
    return C_AddOns.IsAddOnLoaded("PremadeGroupsFilter") and true or false
end

-- Read-only defaults until the profile's ready.
local readOnly = { search = setmetatable({}, { __index = DEFAULTS, __newindex = function() end }),
                   apps   = setmetatable({}, { __index = APPS_DEFAULTS, __newindex = function() end }) }

local function Search()
    local p = Profile()
    return p and p.search or readOnly.search
end

-- filters belong to the character, everything else to the profile
local FILTER_KEYS = {}
for _, k in ipairs({ "ratingOn", "ratingValue", "regions", "delves", "delveTiers", "bosses", "raidDiffs",
    "raidPlaystyles", "raidRoles", "partyFit", "notDeclined", "hasLust", "hasBrez", "extraMyClass", "raidMyClass",
    "extraExpr", "extraRolesAny", "roleCounts", "dimPicks" }) do FILTER_KEYS[k] = true end

-- filters both tabs have: the raids tab keeps its own, under raid_<key> (each
-- raid key built once here: the filter pass reads these for every result)
local TAB_KEYS = {}
for _, k in ipairs({ "regions", "partyFit", "notDeclined", "hasLust", "hasBrez", "extraLustMissing",
    "extraBrezMissing", "extraExpr", "extraRolesAny", "roleCounts", "extraSortBy" }) do TAB_KEYS[k] = "raid_" .. k end
local function RaidTab()
    local sp = LFGListFrame and LFGListFrame.SearchPanel
    return sp and sp.categoryID == (GROUP_FINDER_CATEGORY_ID_RAIDS or 3) or false
end

local charDB
local function CharFilters() return charDB and charDB.filters end

local cfg = setmetatable({}, {
    __index = function(_, k)
        local rk = TAB_KEYS[k]
        if rk and RaidTab() then
            if FILTER_KEYS[k] then
                local f = CharFilters()
                return f and f[rk]
            end
            return Search()[rk]
        end
        if FILTER_KEYS[k] then
            local f = CharFilters()
            return f and f[k]
        end
        return Search()[k]
    end,
    __newindex = function(_, k, v)
        local rk = TAB_KEYS[k]
        if rk and RaidTab() then
            if FILTER_KEYS[k] then
                local f = CharFilters()
                if f then f[rk] = v end
                return
            end
            Search()[rk] = v
            return
        end
        if FILTER_KEYS[k] then
            local f = CharFilters()
            if f then f[k] = v end
            return
        end
        Search()[k] = v
    end,
})

function ns.Cfg() return cfg end

-- blizzard's dungeon picks for this character, nil until saved once
function ns.CharBlizzFilter() return charDB and charDB.blizz end
function ns.SetCharBlizzFilter(t) if charDB then charDB.blizz = t end end

-- the results and applicant lists' display settings, in the profile (read-only
-- until the profile's ready)
local ownListRO = setmetatable({}, { __newindex = function() end })
function ns.OwnListDB()
    local p = Profile()
    if not p then return ownListRO end
    local t = p.ownList
    if type(t) ~= "table" then
        t = {}
        p.ownList = t
    end
    return t
end

function ns.AppsCfg()
    local p = Profile()
    return p and p.apps or readOnly.apps
end

function ns.AppCountsStore()
    local t = Account("groupFinderApps")
    if type(t.dungeon) ~= "table" then t.dungeon = {} end
    return t.dungeon
end

function ns.ResetSettings()
    if db then db:ResetProfile() end
    if charDB then wipe(charDB.filters) end
end

function GF:OnInitialize()
    db = EllesmereUI.Lite.NewDB("EllesmereUIGroupFinderDB", { profile = { search = DEFAULTS, apps = APPS_DEFAULTS } })
    if type(EllesmereUIGroupFinderCharDB) ~= "table" then EllesmereUIGroupFinderCharDB = {} end
    charDB = EllesmereUIGroupFinderCharDB
    if type(charDB.filters) ~= "table" then
        -- a character's first login with filters of its own: it starts from a
        -- copy of the profile's, which stay for the characters that log in later
        local filters = {}
        local s = Profile() and Profile().search
        if s then
            for k in pairs(FILTER_KEYS) do
                local v = s[k]
                if type(v) == "table" then v = CopyTable(v) end
                filters[k] = v
            end
        end
        charDB.filters = filters
    end
end

function GF:OnEnable()
    if not ns.Enabled() then return end
    -- PGF hooks the same panel, so we turn ourselves off while it's loaded.
    if ns.Blocked() then
        ns.SetEnabled(false)
        EllesmereUI.Print(EllesmereUI.COLOR_CODES.BRAND .. "EllesmereUI|r "
            .. EllesmereUI.L("Group Finder has been turned off because Premade Groups Filter is loaded."))
        return
    end

    if ns.Apps_Enable then ns.Apps_Enable() end
    local function Start()
        if ns.Search_OnEnable then ns.Search_OnEnable() end
    end
    if C_AddOns.IsAddOnLoaded("Blizzard_GroupFinder") and PVEFrame then
        Start()
        return
    end
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(self, _, name)
        if name == "Blizzard_GroupFinder" then
            self:UnregisterEvent("ADDON_LOADED")
            Start()
        end
    end)
end
