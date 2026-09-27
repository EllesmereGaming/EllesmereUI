if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIShoppingList.lua
--  A profession shopping list: track recipes (with a number of crafts) and see
--  the reagents they need against what this character has. This file owns the
--  module, its two stores and the event hub; each feature lives in its own
--  file, listed after this one in the TOC, and registers itself here.
--
--  Two stores:
--    * the profile (EllesmereUI.Lite.NewDB): how the window looks and which
--      features are on. Profiles, reset and import/export come with it.
--    * EllesmereUIShoppingListCharDB (SavedVariablesPerCharacter): the list
--      itself. A profile is shared by every character that uses it and travels
--      in exports; a shopping list belongs to one character.
--
--  Off (the default) the module builds no frame, registers no event, installs
--  no hook and starts no timer. Hooks cannot be removed once installed, so a
--  hook body first asks ns.IsOn(feature); switching off mid-session leaves
--  those no-op until the next reload.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EllesmereUI and EllesmereUI._ModuleNS) then EUI_CLIENT_BLOCKED = true; return end -- stale-parent guard: a partially updated install (old parent, new child) goes dormant via the line-1 failsafe instead of erroring
EllesmereUI._ModuleNS[ADDON_NAME] = ns  -- LOD options files read this module ns via the registry

local EUI = EllesmereUI
ns.EUI = EUI
ns.FONT_KEY = "shoppingList"
ns.UNLOCK_KEY = "EUI_ShoppingList"

-------------------------------------------------------------------------------
--  Profile defaults. Sizes and offsets are UIParent units; every number the
--  options page shows goes through PP (physical pixels). Key names follow the
--  Damage Meters page where it has the same control, so the two read alike.
-------------------------------------------------------------------------------
local DEFAULTS = {
    enabled = false, locked = false,
    width = 300, height = 260,
    visibility = "always",
    hideWhenEmpty = true, showWithProfession = true, collapsed = false,
    hideCompleted = false, reagentSort = "missing",
    -- features
    trackButton = true, defaultQty = 1, useBlizzardTrack = true,
    subCrafts = true, autoTrackSubCrafts = false, countWarbandBank = true,
    cooldowns = true, cooldownChat = true, cooldownSound = "none",
    vendorButtons = true, vendorHighlight = true,
    vendorHighlightColor = { r = 0.05, g = 0.82, b = 0.62 },
    buyButton = true, buyConfirmGold = 10, costInHeader = true,
    tooltipLine = true, ahButton = true, toolButtons = true, skillUpColor = true,
    -- title (blank: "Shopping List")
    titleText = "",
    -- header
    hdrHeight = 22, hdrBgAlpha = 1, hdrBgColor = { r = 0.106, g = 0.106, b = 0.106 },
    hdrBottomBorderSize = 0, hdrBottomBorderColor = { r = 0, g = 0, b = 0, a = 1 },
    hdrIconSize = 22, hdrMouseoverIcons = false,
    iconColorUseAccent = false, iconColor = { r = 1, g = 1, b = 1 },
    hdrFontSize = 11, hdrTextUseAccent = true, hdrTextColor = { r = 1, g = 1, b = 1 },
    hdrTextOffX = 0, hdrTextOffY = 0,
    -- window
    windowBorderTexture = "solid", windowBorderSize = 0, windowBorderSizePx = false,
    windowBorderColor = { r = 0, g = 0, b = 0, a = 1 },
    windowBorderIncludeHeader = true, windowBorderBehind = false,
    windowBorderOffsetX = 0, windowBorderOffsetY = 0,
    bgR = 0, bgG = 0, bgB = 0, bgAlpha = 0.75,
    -- bars
    barTexture = "atrocity", barHeight = 18, barSpacing = 2, barFillAlpha = 1,
    colorMode = "accent", barColor = { r = 0.35, g = 0.55, b = 0.8 },  -- "accent" | "custom"
    sectionTextUseAccent = true, sectionTextColor = { r = 1, g = 1, b = 1 },
    iconStyle = "item", iconZoom = 0.06,
    borderTexture = "solid", borderSize = 0, borderSizePx = false,
    borderR = 0, borderG = 0, borderB = 0, borderA = 1,
    borderFollowFill = false,
    showHoverTooltip = true,
    barBgAlpha = 0.045, barBgR = 1, barBgG = 1, barBgB = 1,
    -- bar text
    numberFormat = "slash", qtyFormat = "x",
    leftFontSize = 11, rightFontSize = 11,
    leftTextColor = { r = 1, g = 1, b = 1 }, rightTextColor = { r = 1, g = 1, b = 1 },
    leftTextOffsetX = 0, leftTextOffsetY = 0, rightTextOffsetX = 0, rightTextOffsetY = 0,
}
ns.DEFAULTS = DEFAULTS

-- Before OnInitialize (and for a stripped key) reads fall back to DEFAULTS.
local db
function ns.P()
    return db and db.profile or DEFAULTS
end
function ns.Get(key)
    local p = ns.P()
    local v = p[key]
    if v == nil then v = DEFAULTS[key] end
    return v
end
function ns.Set(key, value)
    if db then db.profile[key] = value end
end
function ns.DB() return db end

-------------------------------------------------------------------------------
--  Per-character list. Created on the first write; only reached while the
--  module is on.
-------------------------------------------------------------------------------
local CHAR_VERSION = 1
local function Sub(t, key)
    local v = t[key]
    if type(v) ~= "table" then v = {}; t[key] = v end
    return v
end
function ns.Char()
    local c = EllesmereUIShoppingListCharDB
    if type(c) ~= "table" then
        c = { v = CHAR_VERSION }
        EllesmereUIShoppingListCharDB = c
    end
    Sub(c, "recipes"); Sub(c, "order"); Sub(c, "vendor"); Sub(c, "cooldowns")
    Sub(c, "craftables"); Sub(c, "sources"); Sub(c, "collapsed")
    return c
end

-------------------------------------------------------------------------------
--  Chat feedback; nothing prints in combat unless forced (reminders).
-------------------------------------------------------------------------------
function ns.Say(msg, force)
    if InCombatLockdown() and not force then return end
    EUI.Print(EUI.COLOR_CODES.BRAND .. EUI.L("Shopping List") .. ":|r " .. msg)
end

-------------------------------------------------------------------------------
--  Event hub. Features register their events through Listen/Unlisten; one
--  frame carries them all, an event stays registered while any feature wants
--  it. RegisterEvent throws on an event the client does not have (WoW Forever
--  lacks some retail events), so registration is pcall'd and such an event
--  is simply never delivered.
-------------------------------------------------------------------------------
local hub = CreateFrame("Frame")
local listeners = {}   -- event -> { [owner] = fn }
local unitEvents = { UNIT_SPELLCAST_SUCCEEDED = "player" }

hub:SetScript("OnEvent", function(_, event, ...)
    local set = listeners[event]
    if not set then return end
    for _, fn in pairs(set) do fn(event, ...) end
end)

local function RegisterHubEvent(event)
    local unit = unitEvents[event]
    if unit then return pcall(hub.RegisterUnitEvent, hub, event, unit) end
    return pcall(hub.RegisterEvent, hub, event)
end

function ns.Listen(owner, event, fn)
    local set = listeners[event]
    if not set then
        set = {}
        listeners[event] = set
    end
    local first = next(set) == nil
    set[owner] = fn
    if first then RegisterHubEvent(event) end
end

function ns.Unlisten(owner, event)
    local set = listeners[event]
    if not (set and set[owner]) then return end
    set[owner] = nil
    if next(set) == nil then hub:UnregisterEvent(event) end
end

-------------------------------------------------------------------------------
--  Features. A feature is { key, isOn = fn, events = { EVENT = fn },
--  enable = fn, disable = fn }. ns.Apply switches each one to match
--  "module enabled and feature toggle on"; its events come and go with it.
-------------------------------------------------------------------------------
local features = {}
local featureOn = {}
ns.features = features

function ns.RegisterFeature(f)
    features[#features + 1] = f
end

-- A hook body's gate: the module is on and so is this feature.
function ns.IsOn(key)
    return featureOn[key] == true
end

local function SetFeature(f, on)
    if (featureOn[f.key] == true) == on then return end
    featureOn[f.key] = on or nil
    if on then
        if f.events then
            for event, fn in pairs(f.events) do ns.Listen(f.key, event, fn) end
        end
        if f.enable then f.enable() end
    else
        if f.events then
            for event in pairs(f.events) do ns.Unlisten(f.key, event) end
        end
        if f.disable then f.disable() end
    end
end

-------------------------------------------------------------------------------
--  Change pipeline: anything that changes the list or the counts calls
--  ns.Invalidate(); one pass per frame recomputes and repaints.
-------------------------------------------------------------------------------
local pending = false
local changeCallbacks = {}
function ns.OnChanged(fn) changeCallbacks[#changeCallbacks + 1] = fn end

local function RunChanged()
    pending = false
    if not ns.active then return end
    if ns.Recompute then ns.Recompute() end
    for i = 1, #changeCallbacks do changeCallbacks[i]() end
end

function ns.Invalidate()
    if pending or not ns.active then return end
    pending = true
    C_Timer.After(0, RunChanged)
end

-------------------------------------------------------------------------------
--  Apply: module on/off, then every feature.
-------------------------------------------------------------------------------
function ns.Apply()
    ns.active = ns.Get("enabled") == true
    for i = 1, #features do
        local f = features[i]
        SetFeature(f, ns.active and (not f.isOn or f.isOn()))
    end
    if ns.ApplyWindow then ns.ApplyWindow() end
    if ns.active then ns.Invalidate() end
end

-- Style-only changes (the options page): repaint without re-running features.
function ns.ApplyStyle()
    if ns.RestyleWindow then ns.RestyleWindow() end
end

ns.addon = EUI.Lite.NewAddon(ADDON_NAME)

function ns.addon:OnInitialize()
    db = EUI.Lite.NewDB("EllesmereUIShoppingListDB", { profile = DEFAULTS })
end

function ns.addon:OnEnable()
    ns.Apply()
    if ns.RegisterUnlock then ns.RegisterUnlock() end
end

-- Options-page and reset entry points.
EUI._ShoppingList = {
    Get = ns.Get, Set = ns.Set,
    Apply = ns.Apply, ApplyStyle = ns.ApplyStyle,
}
-- A profile swap, import or sync repoints db.profile; the refresh steps
-- (EllesmereUI_Profiles.lua) re-run Apply through this.
_G._ESL_Apply = ns.Apply

-------------------------------------------------------------------------------
--  /eslist
-------------------------------------------------------------------------------
local slashCommands = {}
ns.slashCommands = slashCommands
slashCommands.show = function()
    ns.Set("enabled", true)
    ns.Apply()
    EUI:RefreshPage()
end
slashCommands.hide = function()
    ns.Set("enabled", false)
    ns.Apply()
    EUI:RefreshPage()
end
slashCommands.reset = function()
    ns.Set("position", nil)
    ns.Set("width", DEFAULTS.width)
    ns.Set("height", DEFAULTS.height)
    ns.Apply()
end

SLASH_ELLESMEREUISHOPPINGLIST1 = "/eslist"
SlashCmdList.ELLESMEREUISHOPPINGLIST = function(input)
    local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    local fn = slashCommands[cmd]
    if fn then
        fn(rest)
        return
    end
    local names = {}
    for name in pairs(slashCommands) do names[#names + 1] = name end
    table.sort(names)
    ns.Say("/eslist " .. table.concat(names, ", "))
end
