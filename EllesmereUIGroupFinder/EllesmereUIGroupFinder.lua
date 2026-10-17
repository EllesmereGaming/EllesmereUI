if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
-- EllesmereUIGroupFinder.lua: premade group filters, list tweaks and the M+
-- applications bar. Nothing hooks in until it's enabled.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EllesmereUI and EllesmereUI._ModuleNS and EllesmereUI.Lite and EllesmereUI.HELD_BACK_ADDONS) then EUI_CLIENT_BLOCKED = true; return end -- stale-parent guard: a partially updated install (old parent, new child) goes dormant via the line-1 failsafe instead of erroring
-- Held back from this release (EllesmereUI.HELD_BACK_ADDONS): nothing runs,
-- and with no namespace published the options page never registers.
if EllesmereUI.HELD_BACK_ADDONS[ADDON_NAME] then return end
EllesmereUI._ModuleNS[ADDON_NAME] = ns  -- options file grabs the ns from here

local GF = EllesmereUI.Lite.NewAddon(ADDON_NAME)
-- Work on Blizzard frames that waits for combat to end; inert until a Defer.
ns.CombatQueue = EllesmereUI.NewCombatQueue(CreateFrame("Frame"))

local DEFAULTS = {
    padding          = 12,
    nameColors       = true,
    classTooltip     = true,
    leaderRating     = true,
    leaderCrown      = true,
    missingRoles     = true,
    specIcons        = true,
    iconSize         = 125,
    cancelOldest     = false,
    dungeonAbbr      = false,
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

function ns.Cfg()
    local p = Profile()
    return p and p.search or readOnly.search
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
end

function GF:OnInitialize()
    db = EllesmereUI.Lite.NewDB("EllesmereUIGroupFinderDB", { profile = { search = DEFAULTS, apps = APPS_DEFAULTS } })
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
