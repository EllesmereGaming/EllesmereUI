if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Style_Options.lua
--
--  Global Settings > Style: per-module choice between the EllesmereUI look
--  and two stock looks that keep every EllesmereUI feature: Blizzard Style
--  (the current stock art) and Classic WoW UI (the vanilla art). Each row is
--  a write-through mirror of the module's own profile flags: a Blizzard flag
--  (Action Bars mirrors its existing "Blizzard Style Action Bars" button) and
--  a sibling Classic flag, both default off; a style key is read as classic
--  when the Classic flag is set, else blizzard when the Blizzard flag is set,
--  else eui, and a write sets exactly one of the two. Every flag is
--  reload-gated: the values are written ONLY inside the reload popup's
--  confirm handler, so a cancelled popup leaves the profile untouched and the
--  runtime never sees a half-applied style mid-session. The header's three
--  look cards (the first-install picker's, EllesmereUI_StyleCards.lua) each
--  push their style to every enabled module through the same single prompt.
--
--  EllesmereUI.BlizzStyle is the shared helper set the module options pages
--  use to gate rows that only apply to the EllesmereUI look (Gate) and to
--  show the "<style> is active" banner (Note). Both are build-time decisions:
--  each module latches its style once per session (the flags it read at
--  load), so the rendered look cannot change without a reload. The helpers
--  read that latched value; the Style rows show the profile's flags. Get()
--  answers the shared question -- is a stock look dictating the geometry --
--  and is true for both stock styles; Active() names the one that is.
-------------------------------------------------------------------------------

local GLOBAL_KEY     = "_EUIGlobal"
local PAGE_STYLE     = "Style"
local SECTION_STYLES = "MODULE STYLES"

local function NS(folder) return EllesmereUI._ModuleNS and EllesmereUI._ModuleNS[folder] end

-------------------------------------------------------------------------------
--  Module registry: one entry per styleable surface. get/set read and write
--  the module's own per-profile flag and are nil-safe while the module is
--  disabled (get returns nil, set is a no-op).
-------------------------------------------------------------------------------

local function ABProfile()
    local ns = NS("EllesmereUIActionBars")
    local EAB = ns and ns.EAB
    return EAB and EAB.db and EAB.db.profile
end
local function UFProfile()
    local ns = NS("EllesmereUIUnitFrames")
    return ns and ns.db and ns.db.profile
end
local function PABProfile()
    local p = UFProfile()
    return p and p.playerAuraBars
end
local function NPProfile()
    local ns = NS("EllesmereUINameplates")
    return ns and ns.db and ns.db.profile
end
local function CDMProfile()
    local d = _G._ECME_AceDB
    return d and d.profile
end
local function CastBarProfile()
    local d = _G._ERB_AceDB
    return d and d.profile and d.profile.castBar
end
local function ERBProfile()
    local d = _G._ERB_AceDB
    return d and d.profile
end
local function MinimapProfile()
    local d = _G._EMM_DB
    return d and d.profile and d.profile.minimap
end
local function DMProfile()
    local d = _G._EDM_DB
    return d and d.profile and d.profile.dm
end
local function QTProfile()
    local d = _G._EQT_DB
    return d and d.profile and d.profile.questTracker
end
local function ChatProfile()
    local d = _G._ECHAT_DB
    return d and d.profile and d.profile.chat
end
-- The character sheet has no module profile: its style flags sit on the
-- active profile's ROOT (they follow profile switches, copies and exports;
-- every other character sheet setting stays account-wide). nil while Blizz
-- UI Enhanced is disabled, so Apply to All and the first-install picker
-- leave it alone.
local function CharSheetProfile()
    if not NS("EllesmereUIBlizzardSkin") then return nil end
    return EllesmereUI.GetActiveProfileData and EllesmereUI.GetActiveProfileData()
end
local function FriendsProfile()
    local d = _G._EFR_DB
    return d and d.profile and d.profile.friends
end
local function RFProfile()
    local n = NS("EllesmereUIRaidFrames")
    return n and n.db and n.db.profile
end

-- Profile flags -> style key and back. The Classic flag wins a read when both
-- are set; a write sets exactly one of them (or neither, for eui).
local function StyleKeyOf(p, flag, classicFlag)
    if not p then return "eui" end
    if p[classicFlag] then return "classic" end
    if p[flag] then return "blizzard" end
    return "eui"
end
local function FlagAccessors(profileFn, flag, classicFlag)
    return function()
        return StyleKeyOf(profileFn(), flag, classicFlag)
    end, function(styleKey)
        local p = profileFn()
        if p then
            p[flag]        = (styleKey == "blizzard") or false
            p[classicFlag] = (styleKey == "classic") or false
        end
    end
end

-- The style a module is RENDERING this session: its latched key getter on
-- the module ns ("eui" while the module is not loaded). Action Bars has no
-- latch and passes its profile accessor instead.
local function ActiveFn(folder, fnName)
    return function()
        local n = NS(folder)
        local fn = n and n[fnName]
        local v = fn and fn()
        if v == "blizzard" or v == "classic" then return v end
        return "eui"
    end
end

local MODULES = {}
local BY_KEY  = {}
-- onEnable (optional): the style's defaults, run on the profile with the
-- chosen style key the first time the module switches to that stock style
-- (before the reload); a later visit loads the style's saved slot instead
-- (see the per-style slots below).
local function Register(key, folder, display, tooltip, profileFn, flag, classicFlag, activeFnName, onEnable)
    local get, set = FlagAccessors(profileFn, flag, classicFlag)
    local m = { key = key, folder = folder, display = display, tooltip = tooltip, get = get, set = set,
                active = activeFnName and ActiveFn(folder, activeFnName) or get,
                profile = profileFn, onEnable = onEnable }
    MODULES[#MODULES + 1] = m
    BY_KEY[key] = m
end

Register("actionbars",   "EllesmereUIActionBars",      "Action Bars",
    "Blizzard's rounded button art, or the classic square slots, with every EllesmereUI bar feature.",
    ABProfile, "useBlizzardStyle", "useClassicStyle")
Register("unitframes",   "EllesmereUIUnitFrames",      "Unit Frames",
    "Blizzard's frame art, portraits and bar shapes, or the classic frames, with every EllesmereUI frame feature.",
    UFProfile, "useBlizzardStyle", "useClassicStyle", "UF_Style",
    -- Either stock style seeds the "Blizzard" cast fill as the cast bar
    -- texture once per profile, and the player frame's combat indicator in
    -- the style's own icon on the portrait per switch; Classic also seeds
    -- the Plating health bar texture once per profile (the module's own
    -- seed; it also runs at enable for a profile that arrives already
    -- switched).
    function(p, styleKey)
        local uf = NS("EllesmereUIUnitFrames")
        if uf and uf.UF_SeedStock then uf.UF_SeedStock(p, styleKey) end
    end)
Register("playerauras",  "EllesmereUIUnitFrames",      "Player Aura Bars",
    "Blizzard's aura borders on the buffs, debuffs and weapon enchants, with every EllesmereUI bar feature.",
    PABProfile, "useBlizzardStyle", "useClassicStyle", "PAB_Style")
Register("nameplates",   "EllesmereUINameplates",      "Nameplates",
    "Blizzard's health and cast bar art, or the classic flat plates, with every EllesmereUI nameplate feature.",
    NPProfile, "useBlizzardStyle", "useClassicStyle", "NP_Style",
    -- Either stock style seeds the game's own nameplate bar fill on the
    -- health and cast bars once per profile; Classic also seeds the vanilla
    -- cast background and a light uninterruptible grey (the module's own
    -- seeds; they also run at enable for a profile that arrives already
    -- switched).
    function(p, styleKey)
        local np = NS("EllesmereUINameplates")
        if np and np.NP_SeedStock then np.NP_SeedStock(p) end
        if styleKey == "classic" and np and np.NP_SeedClassic then np.NP_SeedClassic(p) end
    end)
Register("cdmicons",     "EllesmereUICooldownManager", "Cooldown Manager Icons",
    "Blizzard's rounded cooldown icons, or the classic square slots, with every EllesmereUI icon feature.",
    CDMProfile, "useBlizzardStyle", "useClassicStyle", "CdmIconStyle")
Register("cdmbars",      "EllesmereUICooldownManager", "Tracked Buff Bars",
    "Blizzard's buff bar art, or the classic cast bar frame, with every EllesmereUI tracked bar feature.",
    CDMProfile, "useBlizzardStyleBars", "useClassicStyleBars", "CdmBarStyle")
Register("castbar",      "EllesmereUIResourceBars",    "Player Cast Bar",
    "Blizzard's cast bar art, or the classic cast bar frame, with every EllesmereUI cast bar feature.",
    CastBarProfile, "useBlizzardStyle", "useClassicStyle", "ERB_CastStyle",
    -- Either stock style seeds the "Blizzard" fill as the bar texture once
    -- per profile (the module's own seed; it also runs at enable for a
    -- profile that arrives already switched).
    function(p)
        local erb = NS("EllesmereUIResourceBars")
        if erb and erb.ERB_SeedStockCast then erb.ERB_SeedStockCast(p) end
    end)
Register("resourcebars", "EllesmereUIResourceBars",    "Resource Bars",
    "The personal resource display's bar frame, or the classic cast bar frame, on the health, power and class resource bars, with every EllesmereUI bar feature.",
    ERBProfile, "useBlizzardStyleBars", "useClassicStyleBars", "ERB_BarsStyle",
    -- Classic WoW UI turns Border Around All on when the shown bars already
    -- sit as one anchored stack, and seeds the "Plating" bar texture, once
    -- per profile (the module's own seed; it also runs at enable for a
    -- profile that arrives already switched).
    function(p, styleKey)
        local erb = NS("EllesmereUIResourceBars")
        if erb and erb.ERB_SeedStockBars then erb.ERB_SeedStockBars(p, styleKey) end
    end)
Register("minimap",      "EllesmereUIMinimap",         "Minimap",
    "Blizzard's round minimap and header, or the classic ring, with every EllesmereUI minimap feature.",
    MinimapProfile, "useBlizzardStyle", "useClassicStyle", "MinimapStyle",
    -- Either stock style, at each switch (the controls stay the user's
    -- afterwards): the Omnium Folio on the ring's bottom right spot (WoW
    -- Forever builds no folio), and the clock inside the map at the top,
    -- 10px down. Classic WoW UI also centres the zone text in the banner's
    -- text slot (its X/Y offsets back to 0).
    function(p, styleKey)
        if not EllesmereUI.IS_FOREVER then p.omniumFolioCorner = "BOTTOMRIGHT" end
        p.clockMode, p.clockPosition, p.clockOffsetY = "inside", "top", -10
        if styleKey == "classic" then p.locationOffsetX, p.locationOffsetY = 0, 0 end
    end)
Register("damagemeters", "EllesmereUIDamageMeters",    "Damage Meters",
    "Blizzard's meter window and bar art, or a window in the classic chat tabs' border, with every EllesmereUI meter feature.",
    DMProfile, "useBlizzardStyle", "useClassicStyle", "DMStyle",
    -- The stock panel reads best lighter: the first switch to Blizzard Style
    -- seeds Background Opacity at 0.4 (once per profile; the slider stays
    -- the user's). The first switch to Classic WoW UI runs the module's own
    -- seed (the near-black window, the quarter-black bar track; once per
    -- profile, the module also runs it at login for a profile that arrives
    -- already switched).
    function(p, styleKey)
        if styleKey == "blizzard" and not p.blizzBgAlphaSeeded then
            p.blizzBgAlphaSeeded = true
            p.bgAlpha = 0.4
        elseif styleKey == "classic" then
            local dm = EllesmereUI._ModuleNS and EllesmereUI._ModuleNS.EllesmereUIDamageMeters
            if dm and dm.DMSeedClassic then dm.DMSeedClassic(p) end
        end
    end)
Register("questtracker", "EllesmereUIQuestTracker",    "Quest Tracker",
    "Blizzard's own tracker, with every EllesmereUI tracker feature. Both stock styles look the same here.",
    QTProfile, "useBlizzardStyle", "useClassicStyle", "QT_Style")
Register("chat",         "EllesmereUIChat",            "Chat",
    "Blizzard's own chat window, tabs and input box, or the same window with the classic tab art, with every EllesmereUI chat feature.",
    ChatProfile, "useBlizzardStyle", "useClassicStyle", "ChatStyle")
-- WoW Forever keeps its own character sheet treatment (no row there).
if not EllesmereUI.IS_FOREVER then
-- Raid Frames never loads on WoW Forever (no row there). One row covers raid,
-- party (in its Raid Frames layout), Friendly Boss and Extra Frames. Either
-- stock style's first visit seeds the stock raid fill (the 12.1 flat fill,
-- or Classic's Blizzard Raid Bar), flush spacing, the stock role icons and
-- absorb looks (the module's own seed; it also runs at enable for a profile
-- that arrives already switched).
Register("raidframes",   "EllesmereUIRaidFrames",      "Raid Frames",
    "Blizzard's raid frame edge and highlights, or the classic ones, with every EllesmereUI raid frame feature.",
    RFProfile, "useBlizzardStyle", "useClassicStyle", "RF_Style",
    function(p, styleKey)
        local rf = NS("EllesmereUIRaidFrames")
        if rf and rf.RF_SeedStock then rf.RF_SeedStock(p, styleKey) end
    end)
Register("charsheet",    "EllesmereUIBlizzardSkin",    "Character Sheet",
    "Blizzard's own character sheet with the EllesmereUI stats, slot text and socket panel added; the Calc tab stays with the EllesmereUI look.",
    CharSheetProfile, "charSheetUseBlizzardStyle", "charSheetUseClassicStyle", "CharSheetStyle")
-- The module to enable is Blizz UI Enhanced, not a "Character Sheet" one.
BY_KEY.charsheet.enableName = "Blizz UI Enhanced"
-- The Friends List module never loads on WoW Forever (no row there).
Register("friends",      "EllesmereUIFriends",         "Friends List",
    "Blizzard's own friends window and cards, with the EllesmereUI class icons, class-coloured names and region icons added. Both stock styles look the same here.",
    FriendsProfile, "useBlizzardStyle", "useClassicStyle", "FR_Style")
end

-------------------------------------------------------------------------------
--  Per-style slots. Every setting a style's defaults write (the onEnable
--  seeds above) is kept once per style: switching a module from style A to
--  style B saves those keys into A's slot and loads B's, so each look comes
--  back exactly as it was left, tweaks included. The first visit to a style
--  has no slot: a stock style clears its "seeded" markers and runs its
--  defaults (onEnable), the EllesmereUI look clears the keys back to the
--  install defaults (the reload every switch ends in refills them from the
--  module's defaults). A slot holds these keys only, in the module's own
--  profile table (p._styleSlots), so it follows profile copies and imports.
--  keys: dotted paths into the module's profile table (one level deep);
--  stamps: the markers that make a seed once per profile; seededBy(key):
--  the stamp whose seed writes that key (true = only this build ever writes
--  it, nil = no seed does). A first visit to the EllesmereUI look with no
--  saved slot (a profile from before the slots) clears only the keys whose
--  stamp is set: every other value there is still the user's own.
-------------------------------------------------------------------------------
local SLOT_KEYS = {
    unitframes = {
        stamps = { "stockCastTextureSeeded", "classicTextureSeeded", "stockCombatSeededStyle" },
        keys = function()
            local k = { "castBarTexture", "healthBarTexture",
                        "player.combatIndicatorStyle", "player.combatIndicatorPosition" }
            local uf = NS("EllesmereUIUnitFrames")
            local units = uf and uf.UF_TEXTURE_UNITS
            if units then
                for i = 1, #units do k[#k + 1] = units[i] .. ".healthBarTexture" end
            end
            return k
        end,
        seededBy = function(key)
            if key == "castBarTexture" then return "stockCastTextureSeeded" end
            if key:find("combatIndicator", 1, true) then return "stockCombatSeededStyle" end
            return "classicTextureSeeded"
        end,
    },
    nameplates   = { stamps = { "stockBarTextureSeeded", "classicCastSeeded" },
                     keys = { "healthBarTexture", "castBarTexture",
                              "castBgColor", "castBgAlpha", "castBarUninterruptible" },
                     seededBy = function(key)
                         if key == "healthBarTexture" or key == "castBarTexture" then return "stockBarTextureSeeded" end
                         return "classicCastSeeded"
                     end },
    castbar      = { stamps = { "stockTextureSeeded" }, keys = { "texture" }, prefix = "castBar",
                     seededBy = function() return "stockTextureSeeded" end },
    -- Border Around All (one key set shared by both stock styles) rides the
    -- slots too, so each style keeps its own choice. So does "Choose texture
    -- per bar" (splitTex) with the health and power textures it enables (the
    -- Classic seed writes those). splitTex shares their stamp so a first
    -- EllesmereUI visit with no saved slot clears it with them: one texture,
    -- never the split with empty per-bar keys.
    resourcebars = { stamps = { "general.classicTextureSeeded", "general.borderAllSeeded" },
                     keys = { "general.barTexture", "splitTex", "health.barTexture", "primary.barTexture",
                              "general.classicBorderAll",
                              "general.classicBorderAllSepSize", "general.classicBorderAllSepR",
                              "general.classicBorderAllSepG", "general.classicBorderAllSepB" },
                     seededBy = function(key)
                         if key == "splitTex" or key:find("barTexture", 1, true) then
                             return "general.classicTextureSeeded"
                         end
                         return true
                     end },
    damagemeters = { stamps = { "blizzBgAlphaSeeded", "classicSeeded" },
                     keys = { "bgAlpha", "bgR", "bgG", "bgB", "barTexture",
                              "barBgR", "barBgG", "barBgB", "barBgAlpha", "barBgUseClassColor" },
                     seededBy = function(key)
                         if key == "bgAlpha" then return "blizzBgAlphaSeeded" end
                         return "classicSeeded"
                     end },
    minimap      = { keys = { "omniumFolioCorner", "clockMode", "clockPosition", "clockOffsetY",
                              "locationOffsetX", "locationOffsetY" } },
    -- The Party page's Frame Style and the Party Frames layout's own scale
    -- and spacing ride the slots too, so each stock style keeps its own
    -- (they exist only under a stock style: back to EllesmereUI clears them).
    raidframes   = { stamps = { "stockRaidSeeded" },
                     keys = { "healthBarTexture", "party_healthBarTexture", "cellSpacing", "groupSpacing",
                              "partyCellSpacing", "roleIconStyle", "party_roleIconStyle",
                              "absorbStyle", "party_absorbStyle", "absorbOpacity", "party_absorbOpacity",
                              "absorbGlowLine", "party_absorbGlowLine",
                              "healAbsorbStyle", "party_healAbsorbStyle",
                              "partyFrameStyle", "partyKitScale", "partyKitSpacing",
                              "partyKitDebuffSize", "partyKitDebuffX", "partyKitDebuffY",
                              "partyKitBuffSize", "partyKitBuffX", "partyKitBuffY", "partyKitBuffAnchor" },
                     seededBy = function(key)
                         if key == "partyFrameStyle" or key:find("^partyKit") then return true end
                         return "stockRaidSeeded"
                     end },
}
for key, spec in pairs(SLOT_KEYS) do
    if BY_KEY[key] then BY_KEY[key].slots = spec end
end

local function PathGet(t, path)
    local a, b = path:match("^([^.]+)%.(.+)$")
    if not a then return t[path] end
    local s = t[a]
    if type(s) ~= "table" then return nil end
    return s[b]
end
local function PathSet(t, path, v)
    local a, b = path:match("^([^.]+)%.(.+)$")
    if not a then t[path] = v; return end
    local s = t[a]
    if type(s) == "table" then s[b] = v end
end

-- The slot keys a spec or conditional override holds (spec.prefix = the
-- module profile's subtable path, e.g. the cast bar's): nil when none.
local function OverriddenKeys(m, spec, keys)
    local isCap = EllesmereUI.SpecOverrides_IsCaptured
    if not isCap then return nil end
    local pre, list = spec.prefix, nil
    for i = 1, #keys do
        local path = keys[i]
        local a, b = path:match("^([^.]+)%.(.+)$")
        local hit
        if pre then
            if a then hit = isCap(m.folder, pre, a, b) else hit = isCap(m.folder, pre, path) end
        elseif a then
            hit = isCap(m.folder, a, b)
        else
            hit = isCap(m.folder, path)
        end
        if hit then list = list or {}; list[#list + 1] = path end
    end
    return list
end

-- One module to `to`: its slots swap, then its flags. Every Style write goes
-- through here (a row, Apply to All, the first-install picker). A setting a
-- spec or conditional override holds keeps its live value through all of
-- it: the override wins over both a saved slot and a style's defaults.
local function SwitchModuleStyle(m, to)
    local p = m.profile and m.profile()
    local from = m.get()
    if from == to then return end
    local spec = m.slots
    local loaded = false
    local keep, keepVals
    if p and spec then
        local keys = spec.keys
        if type(keys) == "function" then keys = keys() end
        keep = OverriddenKeys(m, spec, keys)
        if keep then
            keepVals = {}
            for i = 1, #keep do keepVals[i] = PathGet(p, keep[i]) end
        end
        local stamps = spec.stamps
        local slots = p._styleSlots
        if type(slots) ~= "table" then slots = {}; p._styleSlots = slots end
        local out = {}
        for i = 1, #keys do out[keys[i]] = PathGet(p, keys[i]) end
        if stamps then
            for i = 1, #stamps do out[stamps[i]] = PathGet(p, stamps[i]) end
        end
        slots[from] = out
        local saved = slots[to]
        if type(saved) == "table" then
            loaded = true
            for i = 1, #keys do PathSet(p, keys[i], saved[keys[i]]) end
            if stamps then
                for i = 1, #stamps do PathSet(p, stamps[i], saved[stamps[i]]) end
            end
        else
            if to == "eui" then
                -- Only what a seed wrote goes back to the install default
                -- (read before the stamps clear below).
                local by = spec.seededBy
                if by then
                    for i = 1, #keys do
                        local st = by(keys[i])
                        if st == true or (st and PathGet(p, st)) then PathSet(p, keys[i], nil) end
                    end
                end
            elseif from ~= "eui" then
                -- From the other stock style: start from the EllesmereUI
                -- look's values, so a first visit gives the same result
                -- whichever look it is reached from. A profile that reached
                -- its first stock style before the slots existed never banked
                -- that look: bank it now as the EllesmereUI first visit would
                -- leave the profile (what a seed wrote goes back to the install
                -- default, read before the stamps clear below), so the return
                -- to EllesmereUI can load it instead of keeping this style's
                -- seeds.
                local base = slots.eui
                if type(base) ~= "table" then
                    base = {}
                    local by = spec.seededBy
                    for i = 1, #keys do
                        local k = keys[i]
                        local st = by and by(k)
                        if not (st == true or (st and PathGet(p, st))) then
                            base[k] = PathGet(p, k)
                        end
                    end
                    slots.eui = base
                end
                for i = 1, #keys do PathSet(p, keys[i], base[keys[i]]) end
            end
            if stamps then
                for i = 1, #stamps do PathSet(p, stamps[i], nil) end
            end
        end
    end
    m.set(to)
    -- A style's defaults run only on its first visit: a loaded slot already
    -- holds what the user had there.
    if p and to ~= "eui" and m.onEnable and not loaded then m.onEnable(p, to) end
    if keep then
        for i = 1, #keep do PathSet(p, keep[i], keepVals[i]) end
    end
end

-- The stock style most loaded modules use ("blizzard" on a tie or none):
-- names the look a font or window record from before the slots belongs to.
local function InferredStockStyle()
    local b, c = 0, 0
    for i = 1, #MODULES do
        local m = MODULES[i]
        if NS(m.folder) ~= nil then
            local k = m.get()
            if k == "blizzard" then b = b + 1 elseif k == "classic" then c = c + 1 end
        end
    end
    return (c > b) and "classic" or "blizzard"
end

-------------------------------------------------------------------------------
--  Shared helpers (EllesmereUI.BlizzStyle)
-------------------------------------------------------------------------------

local BlizzStyle = {}
EllesmereUI.BlizzStyle = BlizzStyle

local STYLE_VALUES = { eui = "EllesmereUI Style", blizzard = "Blizzard Style", classic = "Classic WoW UI" }
local STYLE_ORDER  = { "eui", "blizzard", "classic" }

-- The style the module currently RENDERS (its session latch, not the profile
-- flags): "eui", "blizzard" or "classic". "eui" for unknown keys and for
-- disabled modules.
function BlizzStyle.Active(key)
    local m = BY_KEY[key]
    return m and m.active() or "eui"
end
-- The display name of the rendering style (the requirement text on gated rows).
function BlizzStyle.Label(key)
    return STYLE_VALUES[BlizzStyle.Active(key)] or STYLE_VALUES.eui
end
-- True when a stock look (Blizzard Style or Classic WoW UI) dictates the
-- module's geometry this session: the question every gate asks. False for
-- unknown keys and for disabled modules.
function BlizzStyle.Get(key)
    return BlizzStyle.Active(key) ~= "eui"
end
-- A style chosen for the whole UI at once (the first-install picker, Apply to
-- All) also swaps the global font through per-style slots in the per-profile
-- fonts DB (fonts._styleSlots: `active` = the look whose font is live, plus
-- one { global } per look). First visit to a look: the stock styles take
-- Blizzard Default in place of the install default Expressway, and the
-- EllesmereUI look takes Expressway back from Blizzard Default; any other
-- font stays. Glyph-restricted locales already render the client's own font,
-- so nothing changes there. Both callers reload right after.
-- legacy: the stock look a record from before the slots belongs to, taken
-- before any module flag changes (nil = infer it now).
local function FontSlots(legacy)
    if EllesmereUI.LOCALE_FONT_FALLBACK or not EllesmereUI.GetFontsDB then return nil end
    local db = EllesmereUI.GetFontsDB()
    local s = db._styleSlots
    if type(s) ~= "table" then
        -- A one-way seed from before the slots (fontStockSeeded): the live
        -- font belongs to a stock look, and Expressway was the one it replaced.
        if db.fontStockSeeded then
            s = { active = legacy or InferredStockStyle(), eui = { global = "Expressway" } }
        else
            s = { active = "eui" }
        end
    end
    return db, s
end
local function FontPending(styleKey)
    local db, s = FontSlots()
    return db ~= nil and (s.active or "eui") ~= styleKey
end
local function ApplyWholeUIFont(styleKey, legacy)
    local db, s = FontSlots(legacy)
    if not db then return end
    local from = s.active or "eui"
    if from == styleKey then return end
    s[from] = { global = db.global }
    local saved = s[styleKey]
    if type(saved) == "table" and saved.global then
        db.global = saved.global
    else
        local blizz = EllesmereUI.BLIZZARD_FONT_KEY or "__blizzard"
        local cur = db.global or "Expressway"
        if styleKey ~= "eui" then
            if cur == "Expressway" then db.global = blizz end
        elseif cur == blizz then
            db.global = "Expressway"
        end
    end
    s.active = styleKey
    db._styleSlots = s
    db.fontStockSeeded = nil
    if EllesmereUI.InvalidateFontCache then EllesmereUI.InvalidateFontCache() end
end
-- The same two callers also swap the Blizz UI Enhanced window skins through
-- their own per-style slots (EllesmereUI.SwapWindowSkinStyle: first visit
-- to a stock style = every window but the character sheet's at Blizz
-- Default). A disabled Blizz UI Enhanced module has no swapper and is left
-- alone. The look is the active PROFILE's (profile-root windowSkinLook), so
-- the account's windows swap back to each profile's look on a profile switch
-- (EllesmereUI.ReconcileWindowSkinLook).
local function WholeUIWindowsPending(styleKey)
    local swap = EllesmereUI.SwapWindowSkinStyle
    return swap ~= nil and swap(styleKey, true, InferredStockStyle())
end
local function ApplyWholeUIWindows(styleKey, legacy)
    local swap = EllesmereUI.SwapWindowSkinStyle
    if not swap then return end
    swap(styleKey, false, legacy or InferredStockStyle())
    local prof = EllesmereUI.GetActiveProfileData and EllesmereUI.GetActiveProfileData()
    if prof then prof.windowSkinLook = styleKey end
end

-- Every loaded module to one style at once, no prompt: the first-install
-- style picker (EllesmereUI_StyleChoicePopup.lua) writes the flags and
-- reloads itself. The same writes as Apply to All's confirm; a module with
-- no profile (disabled at the picker) is left alone. Takes a style key
-- (true stands for blizzard, false for eui).
function BlizzStyle.ApplyAll(styleKey)
    if styleKey == true then styleKey = "blizzard" elseif not STYLE_VALUES[styleKey] then styleKey = "eui" end
    local legacy = InferredStockStyle()
    for i = 1, #MODULES do
        local m = MODULES[i]
        if m.profile() then SwitchModuleStyle(m, styleKey) end
    end
    ApplyWholeUIFont(styleKey, legacy)
    ApplyWholeUIWindows(styleKey, legacy)
end

-- The rendered style never changes during a session, so gating a row is a
-- build-time decision: when a stock style is active the row is disabled
-- with the standard requirement tooltip naming it. Returns cfg for inline use.
function BlizzStyle.Gate(key, cfg, keepRow)
    if not cfg or not BlizzStyle.Get(key) then return cfg end
    cfg.disabled        = function() return true end
    cfg.disabledTooltip = BlizzStyle.Label(key)
    cfg.requireState    = "disabled"
    cfg.rawTooltip      = nil
    cfg._blizzGated     = true
    -- keepRow: an inline control hung on this slot (a cog) still works under
    -- the style, so the row must stay on the page even if fully gated.
    cfg._blizzKeepRow   = keepRow or nil
    return cfg
end

-- Classic WoW UI: a bar's Border Size slider, which sizes the vanilla frame
-- round it as a percentage of the frame's full size (EllesmereUI.ClassicFrame.
-- BORDER_DEFAULT when unset). get() returns the stored percentage (nil =
-- default); set(v) stores it (nil for the default) and repaints. opts, when
-- given, carries disabled / disabledTooltip. Returns the slider cfg.
function BlizzStyle.ClassicBorderSizeCfg(get, set, opts)
    local CF = EllesmereUI.ClassicFrame
    local def = (CF and CF.BORDER_DEFAULT) or 60
    return { type = "slider", text = "Border Size", min = 25, max = 100, step = 5,
      tooltip = "Size of the Classic frame around the bar.",
      disabled = opts and opts.disabled,
      disabledTooltip = opts and opts.disabledTooltip,
      getValue = function() return get() or def end,
      setValue = function(v) set((v ~= def) and v or nil) end }
end

-- A slot's gate state: nil = blank (no control: nil, spacer, empty label),
-- true = gated for the active style (a multiSwatch counts when every swatch
-- is), false = a live control.
local function SlotGated(cfg)
    if not cfg then return nil end
    local t = cfg.type
    if t == "spacer" or (t == "label" and (cfg.text == nil or cfg.text == "")) then return nil end
    if cfg._blizzGated then return true end
    if t == "multiSwatch" and cfg.swatches then
        local n = #cfg.swatches
        for i = 1, n do
            if not cfg.swatches[i]._blizzGated then return false end
        end
        return n > 0
    end
    return false
end

-- A row whose every control is gated for the active style is not shown at
-- all: the widget factory builds it (callers still hang cogs and sync icons
-- on its regions) but hides it and gives it no height. Blank slots do not
-- count; one live control keeps the row, its gated neighbour disabled.
function BlizzStyle.RowHidden(a, b, c)
    if (a and a._blizzKeepRow) or (b and b._blizzKeepRow) or (c and c._blizzKeepRow) then return false end
    local ga, gb, gc = SlotGated(a), SlotGated(b), SlotGated(c)
    if ga == false or gb == false or gc == false then return false end
    return (ga or gb or gc) and true or false
end

-- Inline widget (swatch, cog) with no disabled state of its own: dims it and
-- blocks clicks with the standard requirement tooltip while a stock style is
-- active for the module. No-op otherwise, so existing pages are untouched.
function BlizzStyle.BlockInline(key, widget, dimAlpha)
    if not widget or not BlizzStyle.Get(key) then return false end
    widget:SetAlpha(dimAlpha or 0.3)
    local block = CreateFrame("Frame", nil, widget)
    block:SetAllPoints()
    block:SetFrameLevel(widget:GetFrameLevel() + 10)
    block:EnableMouse(true)
    local label = BlizzStyle.Label(key)
    block:SetScript("OnEnter", function()
        EllesmereUI.ShowWidgetTooltip(widget, EllesmereUI.DisabledTooltip(label, "disabled"))
    end)
    block:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
    return true
end

-- Banner row under a section header: explains why rows are disabled and
-- links back to the Style page. Adds nothing (returns y unchanged) while
-- the module renders the EllesmereUI look, so existing pages are untouched.
function BlizzStyle.Note(parent, y, key)
    local m = BY_KEY[key]
    -- The latched rendering state, like Gate: a profile whose flags differ
    -- from the running look (reload declined) must not banner live rows.
    if not m or m.active() == "eui" then return y end
    local ROW_H = 40
    -- The search prebuild only indexes rows: same y advance, no frames.
    if EllesmereUI._prebuilding then return y - ROW_H end
    local PP = EllesmereUI.PanelPP
    local row = CreateFrame("Frame", nil, parent)
    PP.Size(row, parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2, ROW_H)
    PP.Point(row, "TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD, y)
    row._skipRowDivider = true
    if EllesmereUI.RowBg then EllesmereUI.RowBg(row, parent) end

    local lbl = EllesmereUI.MakeFont(row, 12, nil, 1, 1, 1)
    lbl:SetAlpha(0.6)
    lbl:SetPoint("LEFT", row, "LEFT", 20, 0)
    lbl:SetPoint("RIGHT", row, "RIGHT", -160, 0)
    lbl:SetJustifyH("LEFT")
    lbl:SetWordWrap(false)
    lbl:SetText(EllesmereUI.Lf("%1$s is active. Settings that only apply to the EllesmereUI look are hidden.", EllesmereUI.L(BlizzStyle.Label(key))))

    local btn = CreateFrame("Button", nil, row)
    PP.Size(btn, 122, 26)
    btn:SetPoint("RIGHT", row, "RIGHT", -20, 0)
    btn:SetFrameLevel(row:GetFrameLevel() + 2)
    local display = m.display
    EllesmereUI.MakeStyledButton(btn, "Open Style", 11, EllesmereUI.WB_COLOURS, function()
        EllesmereUI:NavigateToElementSettings(GLOBAL_KEY, PAGE_STYLE, SECTION_STYLES, nil, display)
    end)
    return y - ROW_H
end

-- Reload prompt: the flags are written only on confirm, right before the
-- reload, so cancelling (button, escape or click-outside) changes nothing.
-- `changes` lists { m = module, key = styleKey } pairs: one for a row's
-- dropdown, every differing module for Apply to All (one prompt for the batch).
-- `wholeUIStyle` (Apply to All only) also applies the matching global font
-- and window skins, either of which alone is reason enough to prompt.
local function PromptStyleChanges(changes, wholeUIStyle)
    if #changes == 0 and not (wholeUIStyle and (FontPending(wholeUIStyle)
        or WholeUIWindowsPending(wholeUIStyle))) then return end
    EllesmereUI:ShowConfirmPopup({
        title       = "Reload Required",
        message     = "Changing the style requires a UI reload to apply.",
        confirmText = "Reload Now",
        cancelText  = "Cancel",
        reload      = true,
        onConfirm   = function()
            -- Close any editing-as session first, as a profile switch does:
            -- these writes then land on the profile itself, where an open
            -- session's logout sweep would have turned them into overrides
            -- for the group being edited.
            if EllesmereUI.SpecOverrides_CloseEditSessions then
                EllesmereUI.SpecOverrides_CloseEditSessions()
            end
            local legacy = wholeUIStyle and InferredStockStyle()
            for i = 1, #changes do
                SwitchModuleStyle(changes[i].m, changes[i].key)
            end
            if wholeUIStyle then
                ApplyWholeUIFont(wholeUIStyle, legacy)
                ApplyWholeUIWindows(wholeUIStyle, legacy)
            end
        end,
    })
end
local function PromptStyleChange(m, styleKey)
    if m.get() == styleKey then return end
    PromptStyleChanges({ { m = m, key = styleKey } })
end
-- Apply to All's batch for `styleKey`: every loaded module whose flag differs
-- (disabled modules have no profile to write; matching ones need no reload).
local function StyleChangesFor(styleKey)
    local changes = {}
    for i = 1, #MODULES do
        local m = MODULES[i]
        if NS(m.folder) ~= nil and m.get() ~= styleKey then
            changes[#changes + 1] = { m = m, key = styleKey }
        end
    end
    return changes
end

-------------------------------------------------------------------------------
--  Page builder (dispatched from the Global Settings module registration)
-------------------------------------------------------------------------------

local function StyleRowCfg(m)
    local loaded = NS(m.folder) ~= nil
    return {
        type = "dropdown", text = m.display, tooltip = m.tooltip,
        values = STYLE_VALUES, order = STYLE_ORDER,
        -- Reload-gated and per-profile: never captured into spec overrides.
        noCapture = true,
        getValue = function() return m.get() end,
        setValue = function(v) PromptStyleChange(m, v) end,
        disabled = function() return not loaded end,
        disabledTooltip = function()
            return EllesmereUI.Lf("Enable %1$s to change its style.", EllesmereUI.L(m.enableName or m.display))
        end,
        rawTooltip = true,
    }
end

function _G._EUI_BuildStylePage(pageName, parent, yOffset)
    local W = EllesmereUI.Widgets
    local PP = EllesmereUI.PanelPP
    local y = yOffset
    local _, h

    parent._showRowDivider = true

    -- Header: the first-install picker's three look cards
    -- (EllesmereUI_StyleCards.lua), each one Apply to All for its look
    -- through the single reload prompt. The card for the look every loaded
    -- module already uses is marked IN USE, and its button stays live only
    -- while that look still has a font or window-skin change to apply.
    -- Sized host + single TOPLEFT point per the search framework's geometry
    -- contract; the search prebuild only needs the y advance.
    local CARDS_TOP = 140
    local HERO_H = CARDS_TOP + (EllesmereUI.STYLE_CARD_H or 296) + 4
    local hasHero = EllesmereUI.BuildStyleCards ~= nil
    if hasHero and not EllesmereUI._prebuilding then
        local FONT = EllesmereUI._font or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf"
        local EG = EllesmereUI.ELLESMERE_GREEN
        local host = CreateFrame("Frame", nil, parent)
        PP.Size(host, parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2, HERO_H)
        host:SetPoint("TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD, y - 20)

        local eyebrow = host:CreateFontString(nil, "OVERLAY")
        eyebrow:SetFont(FONT, 13, "")
        eyebrow:SetTextColor(EG.r, EG.g, EG.b, 0.9)
        PP.Point(eyebrow, "TOP", host, "TOP", 0, -4)
        eyebrow:SetText(EllesmereUI.L("CHOOSE YOUR LOOK"))

        local title = host:CreateFontString(nil, "OVERLAY")
        title:SetFont(FONT, 25, "")
        title:SetTextColor(1, 1, 1, 1)
        PP.Point(title, "TOP", eyebrow, "BOTTOM", 0, -6)
        title:SetText(EllesmereUI.L("Your UI, Restyled in Seconds"))

        local desc = host:CreateFontString(nil, "OVERLAY")
        desc:SetFont(FONT, 14, "")
        desc:SetTextColor(1, 1, 1, 0.5)
        desc:SetWidth(620)
        desc:SetJustifyH("CENTER")
        desc:SetWordWrap(true)
        PP.Point(desc, "TOP", title, "BOTTOM", 0, -10)
        desc:SetText(EllesmereUI.L("Your setup and every EllesmereUI feature carry over; only the look changes. Apply a style to every module in one click, or set each module below. Changing a style reloads the UI."))

        local cards = EllesmereUI.BuildStyleCards(host, -CARDS_TOP, {
            buttonText = "Apply to All",
            onPick = function(styleKey)
                PromptStyleChanges(StyleChangesFor(styleKey), styleKey)
            end,
        })
        if cards then
            local function RefreshCards()
                local loaded = 0
                for i = 1, #MODULES do
                    if NS(MODULES[i].folder) ~= nil then loaded = loaded + 1 end
                end
                for key, handle in pairs(cards) do
                    local differ = 0
                    for i = 1, #MODULES do
                        local m = MODULES[i]
                        if NS(m.folder) ~= nil and m.get() ~= key then differ = differ + 1 end
                    end
                    local inUse = loaded > 0 and differ == 0
                    local pickable = differ > 0 or FontPending(key)
                        or WholeUIWindowsPending(key)
                    -- "In Use" only on the card that is; with no styleable
                    -- module loaded a card with nothing to apply just dims.
                    handle:SetState(inUse, pickable, (inUse and not pickable) and "In Use" or nil)
                end
            end
            RefreshCards()
            -- Re-run on every page refresh and cached-page restore: a font or
            -- window skin set elsewhere changes what a card has to apply.
            EllesmereUI.RegisterWidgetRefresh(RefreshCards)
        end
    end
    y = y - 20 - (hasHero and (HERO_H + 20) or 0)

    _, h = W:SectionHeader(parent, SECTION_STYLES, y);  y = y - h

    local i = 1
    while i <= #MODULES do
        local left = StyleRowCfg(MODULES[i])
        local rightM = MODULES[i + 1]
        local right = rightM and StyleRowCfg(rightM) or { type = "label", text = "" }
        _, h = W:DualRow(parent, y, left, right);  y = y - h
        i = i + 2
    end

    -- Framework contract: return the positive total content height.
    return math.abs(y)
end
