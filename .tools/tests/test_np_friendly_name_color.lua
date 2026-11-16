-- Stub harness: Nameplates, Name Color (the friendly players' names, in both friendly styles).
-- One pick, friendlyNameColorMode = "class" or "custom", with the Custom colour in
-- friendlyNameColor (white until picked). While no pick is saved each style reads the key it
-- read before the one setting, so no profile changes its look: Name Only the Class Colored
-- Health Bar key (classColorFriendly), the health bar plates Class Colored Names
-- (friendlyNameClassColor).
-- Driven here, all real code cut from the module:
--   the rule and the class colour CVar (EUI_Nameplates_CastState.lua);
--   the health bar plates' painter (PaintFriendlyColors): the name's colour;
--   Name Only: Blizzard draws that name and colours it itself, so a Custom pick is written as a
--     colour escape round the name by the composer (UpdateNameOnlyText), which then runs for a
--     plate with no other composed text too, and stays out of the way with no Custom pick;
--   the settings sync (ns.NP_SyncFriendlyNameFormat): a profile switch that changes the pick
--     or the colour recomposes the names, and one that changes neither does nothing.
--   lua .tools/tests/test_np_friendly_name_color.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return (src:gsub("\r\n", "\n"))
end
local function Cut(src, first, last, what)
    local a = assert(src:find(first, 1, true), what .. ": first line not found")
    local b = assert(src:find(last, a + #first, true), what .. ": last line not found")
    return src:sub(a, b - 1)
end

local fails, count = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        if fails <= 20 then print("  FAIL: " .. msg) end
    end
    return cond
end
local function eq(got, want, msg)
    return check(got == want, msg .. " (got " .. tostring(got) .. ", want " .. tostring(want) .. ")")
end

local SRC = ReadSource("EllesmereUINameplates/EllesmereUINameplatesFriendly.lua")
local CAST = ReadSource("EllesmereUINameplates/EUI_Nameplates_CastState.lua")
local MAIN = ReadSource("EllesmereUINameplates/EllesmereUINameplates.lua")

local profile                                   -- the saved settings (nil: no profile yet)
local function FP() return profile end
local ns = { defaults = { friendlyNameColor = { r = 1, g = 1, b = 1 }, friendlyBarColor = { r = 0.3, g = 0.8, b = 0.4 } } }

-------------------------------------------------------------------------------
-- 1. the rule and the CVar
-------------------------------------------------------------------------------
assert(loadstring("local ns = ...\n" .. Cut(CAST, "function ns.FriendlyNameClass(db, nameOnly)", "\nlocal function SetupAuraCVars()",
    "the name colour rule and its CVar"), "=EUI_Nameplates_CastState.lua"))(ns)
do
    local n = 0
    for _, nameOnly in ipairs({ "nil", true, false }) do
        for _, mode in ipairs({ "nil", "class", "custom" }) do
            for _, ccf in ipairs({ "nil", true, false }) do
                for _, fncc in ipairs({ "nil", true, false }) do
                    local db = {}
                    if nameOnly ~= "nil" then db.friendlyNameOnly = nameOnly end
                    if mode ~= "nil" then db.friendlyNameColorMode = mode end
                    if ccf ~= "nil" then db.classColorFriendly = ccf end
                    if fncc ~= "nil" then db.friendlyNameClassColor = fncc end
                    n = n + 1
                    local what = ("friendlyNameOnly=%s mode=%s classColorFriendly=%s friendlyNameClassColor=%s"):format(
                        tostring(nameOnly), tostring(mode), tostring(ccf), tostring(fncc))
                    local only, plate, cvar
                    if mode == "nil" then
                        -- no pick: each style's older key, and the CVar as it always was
                        only, plate = db.classColorFriendly ~= false, db.friendlyNameClassColor == true
                        cvar = (db.classColorFriendly ~= false or (db.friendlyNameOnly == false and db.friendlyNameClassColor == true)) and 1 or 0
                    else
                        only, plate = mode == "class", mode == "class"
                        cvar = mode == "class" and 1 or 0
                    end
                    eq(ns.FriendlyNameClass(db, true), only, "Name Only's names class colored, " .. what)
                    eq(ns.FriendlyNameClass(db, false), plate, "the health bar plates' names class colored, " .. what)
                    eq(ns.FriendlyNameClassCVar(db), cvar, "the class colour CVar, " .. what)
                end
            end
        end
    end
    eq(n, 81, "the settings the rule was read in")
    check(ns.FriendlyNameClass(nil, true) == true and ns.FriendlyNameClass(nil, false) == false, "the rule with no profile")
    -- a pick that is neither word counts as no pick
    check(ns.FriendlyNameClass({ friendlyNameColorMode = "blue", classColorFriendly = false }, true) == false
        and ns.FriendlyNameClassCVar({ friendlyNameColorMode = true }) == 1, "an unknown pick is not read as no pick")
end

-------------------------------------------------------------------------------
-- 2. the health bar plates: the name's colour
-------------------------------------------------------------------------------
do
    local units = {}                             -- token -> { player, class = { r, g, b } or false }
    local forever = false
    ns.NP_Forever = function() return forever end
    local function NewPlate()
        local plate = { health = {}, name = {} }
        function plate.health:SetStatusBarColor(r, g, b) self.rgb = r .. "," .. g .. "," .. b end
        function plate.name:SetTextColor(r, g, b) self.rgb = r .. "," .. g .. "," .. b end
        return plate
    end
    local Paint = assert(loadstring(
        "local ns, UnitIsPlayer, UnitInParty, UnitInRaid, UnitSelectionColor, ClassRGB, GetFriendlyNPCColor, type = ...\n" ..
        Cut(SRC, "-- Whether a unit is in your party or raid.", "--  Below Name sub text: data + rendering", "the painter") ..
        "\nreturn PaintFriendlyColors", "=EllesmereUINameplatesFriendly.lua (the painter)"))(
        ns,
        function(u) return units[u].player == true end,
        function() return false end, function() return nil end,
        function() return 0.5, 0.5, 1, 1 end,
        function(u)
            local c = units[u].class
            if not c then return false end
            return true, c[1], c[2], c[3]
        end,
        function() return 0, 1, 0 end, type)
    local MAGE = { 0.25, 0.78, 0.92 }
    local function Colors(fp, unit)
        local plate = NewPlate()
        units.u = unit or { player = true, class = MAGE }
        Paint(plate, "u", fp)
        return plate.health.rgb .. " | " .. plate.name.rgb
    end
    local CLASS, WHITE, BAR, NPC = "0.25,0.78,0.92", "1,1,1", "0.3,0.8,0.4", "0,1,0"
    -- no pick: Class Colored Names decides, as before the setting
    eq(Colors({}), CLASS .. " | " .. WHITE, "nothing saved: the bar class colored, the name white")
    eq(Colors({ friendlyNameClassColor = true }), CLASS .. " | " .. CLASS, "Class Colored Names saved on, no pick")
    eq(Colors({ friendlyNameClassColor = false, classColorFriendly = false }), BAR .. " | " .. WHITE, "both older keys off, no pick")
    eq(Colors({ classColorFriendly = false, friendlyNameClassColor = true }), BAR .. " | " .. CLASS, "the bar its own colour, the name class colored")
    -- a pick outranks the older key
    eq(Colors({ friendlyNameColorMode = "class" }), CLASS .. " | " .. CLASS, "Class picked")
    eq(Colors({ friendlyNameColorMode = "class", friendlyNameClassColor = false }), CLASS .. " | " .. CLASS, "Class picked over the older key")
    eq(Colors({ friendlyNameColorMode = "custom", friendlyNameClassColor = true }), CLASS .. " | " .. WHITE, "Custom picked over the older key, no colour picked")
    eq(Colors({ friendlyNameColorMode = "custom", friendlyNameColor = { r = 0.2, g = 0.4, b = 0.6 } }), CLASS .. " | 0.2,0.4,0.6", "Custom picked with a colour")
    eq(Colors({ friendlyNameColorMode = "custom", friendlyNameColor = { r = 0.2, g = 0.4, b = 0.6 }, classColorFriendly = false }),
        BAR .. " | 0.2,0.4,0.6", "Custom picked, the bar its own colour")
    -- the Custom colour is saved but Class is the pick: the class colour
    eq(Colors({ friendlyNameColorMode = "class", friendlyNameColor = { r = 0.2, g = 0.4, b = 0.6 } }), CLASS .. " | " .. CLASS, "Class picked with a Custom colour saved")
    -- the name's colour never moves the bar's
    eq(Colors({ friendlyNameColorMode = "custom", friendlyNameColor = { r = 0, g = 0, b = 0 }, friendlyBarColor = { r = 0.1, g = 0.2, b = 0.3 },
        classColorFriendly = false }), "0.1,0.2,0.3 | 0,0,0", "the bar's own colour beside a Custom name")
    -- a class that does not resolve: with the bar class colored both take the NPC colour; else
    -- the bar its colour and the name the Custom colour
    eq(Colors({ friendlyNameColorMode = "class" }, { player = true, class = false }), NPC .. " | " .. NPC, "an unresolved class under Class Colored Health Bar")
    eq(Colors({ friendlyNameColorMode = "class", classColorFriendly = false, friendlyNameColor = { r = 0.2, g = 0.4, b = 0.6 } },
        { player = true, class = false }), BAR .. " | 0.2,0.4,0.6", "an unresolved class with Class picked falls to the Custom colour")
    -- an NPC takes the NPC colour whatever the pick
    eq(Colors({ friendlyNameColorMode = "custom", friendlyNameColor = { r = 0.2, g = 0.4, b = 0.6 } }, { player = false }), NPC .. " | " .. NPC, "a friendly NPC")
    -- no profile yet
    eq(Colors(nil), CLASS .. " | " .. WHITE, "no profile: the bar class colored, the name white")
end

-------------------------------------------------------------------------------
-- 3. Name Only: the Custom colour as a colour escape round the name
-------------------------------------------------------------------------------
local plates, units = {}, {}
local lookups, formats = 0, 0
local mode, nameFormat, showLevel, brackets = "none", nil, false, false
local function NewFS()
    local fs = { writes = 0 }
    function fs:SetText(t) self.text = t; self.writes = self.writes + 1 end
    function fs:SetFormattedText(fmt, ...) self.text = fmt:format(...); self.writes = self.writes + 1 end
    function fs:SetWordWrap() end
    function fs:SetMaxLines() end
    return fs
end
local function Add(token, unit)
    units[token] = unit
    plates[token] = { UnitFrame = { name = NewFS() } }
    return plates[token].UnitFrame.name
end
local function BlizzName(token) plates[token].UnitFrame.name:SetText(units[token].name) end
local function hooksecurefunc(obj, name, fn)
    local orig = obj[name]
    obj[name] = function(...)
        local r = orig(...)
        fn(...)
        return r
    end
end
local SECRET = {}
local composer = assert(loadstring(
    "local ns, FP, GetBelowNameMode, ModeHasTitle, ModeHasGuild, GetTitledName, FriendlyNameFormat, FormatFriendlyName, ShowFriendlyLevel, " ..
    "FriendlyLevelText, GetSubTextColor, EnsureNameUnconstrained, EllesmereUI, C_NamePlate, UnitExists, UnitCanAttack, UnitIsPlayer, " ..
    "UnitName, GetGuildInfo, issecretvalue, hooksecurefunc, UnitIsUnit, IsInRaid, UnitInRaid, GetRaidRosterInfo, UnitInParty = ...\n" ..
    Cut(SRC, "local NameEsc = {}", "-- Name Format (friendlyNameFormat:", "the Custom colour's escape") ..
    Cut(SRC, 'local PARTY_BRACKET_OPEN  = ', "-- The player's name WITH their title as one string", "the bracket rule") ..
    Cut(SRC, 'local nameFSUnits = setmetatable({}, { __mode = "k" })', "-- Sweep all visible friendly player plates", "the composer") ..
    "\nreturn AttachNameOnlyText, NameEsc, PARTY_BRACKET_OPEN, PARTY_BRACKET_CLOSE", "=EllesmereUINameplatesFriendly.lua (the composer)"))
-- (string.format counted: the escape is built only when the colour changes)
setfenv(composer, setmetatable({ string = setmetatable({ format = function(...) formats = formats + 1; return string.format(...) end },
    { __index = string }) }, { __index = _G }))
local Attach, NameEsc, OPEN, CLOSE = composer(
    ns, FP,
    function() return mode end,
    function(m) return m == "title" or m == "both" end,
    function(m) return m == "guild" or m == "both" end,
    function(u) return units[u] and units[u].titled end,
    function() return nameFormat end,
    function(_, name) return name:sub(1, 3) end,
    function() return showLevel end,
    function(u) return units[u].levelText or tostring(units[u].level or 60) end,
    function() return 0.8, 0.8, 0.8 end,
    function() end,
    { WithSurname = function(name) return name end },
    { GetNamePlateForUnit = function(u) lookups = lookups + 1; return plates[u] end },
    function(u) return units[u] ~= nil end,
    function(_, u) return units[u].hostile == true end,
    function(u) return units[u].player == true end,
    function(u) return units[u].name end,
    function(u) return units[u].guild end,
    function(v) return v == SECRET end,
    hooksecurefunc,
    function(u, other) return other == "player" and units[u].me == true end,
    function() return false end, function() return nil end, function() return nil end,
    function(u) return brackets and units[u].party == true end)
-- (the bracket rule asks the profile for its own switch)
local function Profile(t)
    t = t or {}
    t.friendlyGroupBrackets = brackets or nil
    profile = t
end
local BLUE = "|cff336699"                        -- 0.2, 0.4, 0.6
local CUSTOM = { friendlyNameColorMode = "custom", friendlyNameColor = { r = 0.2, g = 0.4, b = 0.6 } }
local function Copy(t) local c = {}; for k, v in pairs(t) do c[k] = v end; return c end
do
    -- no pick, and Class: the name as Blizzard writes it, and the composer is not even asked
    Profile({})
    local fs = Add("nameplate1", { name = "Alice", player = true })
    BlizzName("nameplate1")
    Attach(fs, "nameplate1")
    eq(fs.text, "Alice", "no pick: the name")
    local l0 = lookups
    BlizzName("nameplate1")
    check(fs.text == "Alice" and lookups == l0, "no pick: Blizzard's own name write runs the composer")
    eq(NameEsc.Get(), nil, "no pick: an escape")
    Profile({ friendlyNameColorMode = "class", friendlyNameColor = { r = 0.2, g = 0.4, b = 0.6 } })
    BlizzName("nameplate1")
    check(fs.text == "Alice" and lookups == l0 and NameEsc.Get() == nil, "Class picked: the name is composed, or wears an escape")
    eq(formats, 0, "escapes built with no Custom pick")

    -- Custom: the escape round the name, with nothing else composed
    Profile(Copy(CUSTOM))
    Attach(fs, "nameplate1")
    eq(fs.text, BLUE .. "Alice|r", "Custom picked: the name")
    -- Blizzard writes its plain name again (a name update, its own recolour): composed again
    BlizzName("nameplate1")
    eq(fs.text, BLUE .. "Alice|r", "Custom picked: Blizzard's own name write is not recomposed")
    check(lookups > l0, "Custom picked: the composer did not run for Blizzard's name write")
    -- the escape is built once per colour, and is the same string until the colour changes
    local e1 = NameEsc.Get()
    BlizzName("nameplate1"); BlizzName("nameplate1")
    check(formats == 1 and rawequal(NameEsc.Get(), e1), "the escape is built again with the colour unchanged (" .. formats .. " built)")
    profile.friendlyNameColor = { r = 0.2, g = 0.4, b = 0.6 }         -- another table, the same colour
    check(NameEsc.Get() == BLUE and formats == 1, "the same colour in another table builds the escape again")
    profile.friendlyNameColor = { r = 1, g = 0, b = 0.5 }
    Attach(fs, "nameplate1")
    check(fs.text == "|cffff0080Alice|r" and formats == 2, "a changed colour: " .. tostring(fs.text) .. ", " .. formats .. " built")
    -- one part of the colour changed is a changed colour (each part by itself)
    for i, c in ipairs({ { r = 0, g = 0, b = 0.5, "|cff000080" }, { r = 0, g = 1, b = 0.5, "|cff00ff80" }, { r = 0, g = 1, b = 0.25, "|cff00ff40" } }) do
        profile.friendlyNameColor = { r = c.r, g = c.g, b = c.b }
        Attach(fs, "nameplate1")
        check(fs.text == c[1] .. "Alice|r" and formats == 2 + i, "a colour with one part changed (" .. c[1] .. "): " .. tostring(fs.text))
    end
    formats = 2
    -- Custom with no colour picked: white, from the defaults
    Profile({ friendlyNameColorMode = "custom" })
    Attach(fs, "nameplate1")
    eq(fs.text, "|cffffffffAlice|r", "Custom picked with no colour")
    -- back to Class: the plain name again (the sweep attaches again)
    Profile({ friendlyNameColorMode = "class" })
    Attach(fs, "nameplate1")
    eq(fs.text, "Alice", "back to Class: the name")
    -- no profile at all
    profile = nil
    eq(NameEsc.Get(), nil, "no profile: an escape")
end
do
    -- the rest of the composed name: each piece closes its own escape
    Profile(Copy(CUSTOM))
    local fs = Add("nameplate2", { name = "Bob", player = true, titled = "Bob the Patient", guild = "Lions", party = true, level = 60 })
    BlizzName("nameplate2")
    -- the title is part of the name
    mode = "title"
    Attach(fs, "nameplate2")
    eq(fs.text, BLUE .. "Bob the Patient|r", "Custom: the titled name")
    -- the guild line keeps its own colour, on its own line
    mode = "guild"
    Attach(fs, "nameplate2")
    eq(fs.text, BLUE .. "Bob|r\n|cffcccccc<Lions>|r", "Custom: the name over its guild line")
    mode = "none"
    -- the level and the divider take the colour too
    showLevel = true
    Attach(fs, "nameplate2")
    eq(fs.text, BLUE .. "60|r" .. BLUE .. " | |r" .. BLUE .. "Bob|r", "Custom: the level, the divider and the name")
    -- a level coloured by difficulty keeps that colour (its own escape closes inside ours)
    units.nameplate2.levelText = "|cffff000063|r"
    Attach(fs, "nameplate2")
    eq(fs.text, BLUE .. "|cffff000063|r|r" .. BLUE .. " | |r" .. BLUE .. "Bob|r", "Custom: a level coloured by difficulty")
    units.nameplate2.levelText = nil
    showLevel = false
    -- the group brackets keep their own colours, outside the name's escape
    brackets = true
    Profile(Copy(CUSTOM))
    Attach(fs, "nameplate2")
    eq(fs.text, OPEN .. BLUE .. "Bob|r" .. CLOSE, "Custom: the name inside the party brackets")
    check(OPEN:find("[", 1, true) and CLOSE:find("]", 1, true) and OPEN:sub(1, 4) == "|cff", "the bracket pieces are not what the test reads them as")
    showLevel = true
    Attach(fs, "nameplate2")
    eq(fs.text, BLUE .. "60|r" .. BLUE .. " | |r" .. OPEN .. BLUE .. "Bob|r" .. CLOSE, "Custom: level, brackets and name")
    showLevel, brackets = false, false
    -- the Name Format's short name is what is wrapped
    Profile(Copy(CUSTOM))
    nameFormat = "first"
    Attach(fs, "nameplate2")
    eq(fs.text, BLUE .. "Bob|r", "Custom: the short name")
    nameFormat = nil
    -- without a pick the same settings compose as they always did
    Profile({})
    showLevel = true
    Attach(fs, "nameplate2")
    eq(fs.text, "60 | Bob", "no pick: the level and the name, no escape")
    showLevel = false
end
do
    -- who never takes it: an NPC or a pet on a friendly plate, a hostile unit, a secret name
    Profile(Copy(CUSTOM))
    local pet = Add("nameplate3", { name = "Wolf", player = false })
    BlizzName("nameplate3")
    Attach(pet, "nameplate3")
    eq(pet.text, "Wolf", "Custom: a pet's name")
    local foe = Add("nameplate4", { name = "Enemy", player = true, hostile = true })
    BlizzName("nameplate4")
    Attach(foe, "nameplate4")
    eq(foe.text, "Enemy", "Custom: a hostile player's name")
    local hidden = Add("nameplate5", { name = SECRET, player = true })
    hidden.text = "as Blizzard wrote it"
    local w0 = hidden.writes
    Attach(hidden, "nameplate5")
    check(hidden.text == "as Blizzard wrote it" and hidden.writes == w0, "Custom: a secret name is written over")
end

-------------------------------------------------------------------------------
-- 4. the settings sync: a changed pick or colour recomposes, an unchanged one does not
-------------------------------------------------------------------------------
do
    local refreshes = 0
    local Stamp = assert(loadstring(
        "local ns, FP, EllesmereUI, issecretvalue, UnitName, wipe = ...\n" ..
        Cut(SRC, "local NameEsc = {}", "-- Name Format (friendlyNameFormat:", "the Custom colour's escape") ..
        Cut(SRC, "local FriendlyNameFormat, FormatFriendlyName, StampFriendlyNames\ndo\n", "\n-- Fill the sub text line (guild only", "the Name Format block") ..
        "\nreturn StampFriendlyNames", "=EllesmereUINameplatesFriendly.lua (the sync)"))(
        ns, FP, { ShortName = function(n) return n end, WithSurname = function(n) return n end, IsNameFormat = function() return false end },
        function() return false end, function() return "Alice" end, function(t) for k in pairs(t) do t[k] = nil end end)
    ns.RefreshFriendlyBelowName = function() refreshes = refreshes + 1; Stamp() end
    local function Sync(t)
        profile = t
        local r0 = refreshes
        ns.NP_SyncFriendlyNameFormat()
        return refreshes - r0
    end
    profile = {}
    ns.NP_SyncFriendlyNameFormat()               -- the first call only records
    eq(refreshes, 0, "repaints by the first sync")
    eq(Sync({}), 0, "repaints by a sync with nothing changed")
    eq(Sync({ friendlyNameColorMode = "custom" }), 1, "repaints by a profile that picks Custom")
    eq(Sync({ friendlyNameColorMode = "custom" }), 0, "repaints by the same pick again")
    eq(Sync({ friendlyNameColorMode = "custom", friendlyNameColor = { r = 1, g = 1, b = 1 } }), 0, "repaints by the default colour written out")
    eq(Sync({ friendlyNameColorMode = "custom", friendlyNameColor = { r = 0.2, g = 0.4, b = 0.6 } }), 1, "repaints by another Custom colour")
    eq(Sync({ friendlyNameColorMode = "class", friendlyNameColor = { r = 0.2, g = 0.4, b = 0.6 } }), 1, "repaints by a profile back on Class")
    -- with no Custom pick the colour and the older keys change nothing Name Only composes
    eq(Sync({ friendlyNameColorMode = "class", friendlyNameColor = { r = 0, g = 0, b = 0 } }), 0, "repaints by a Custom colour under Class")
    eq(Sync({ classColorFriendly = false, friendlyNameClassColor = true }), 0, "repaints by the older keys alone")
    -- the other settings the record holds still repaint
    eq(Sync({ friendlyBelowName = "guild" }), 1, "repaints by a changed Subtitle Text")
end

-------------------------------------------------------------------------------
-- 5. the sources
-------------------------------------------------------------------------------
do
    -- a plate that comes into view under a Custom pick is composed with nothing else on
    check(SRC:find("or ShowFriendlyLevel() or ShowFriendlyGroupBrackets() or NameEsc.Get() then\n                AttachNameOnlyText(nameplate.UnitFrame.name, unit)", 1, true),
        "a plate added under a Custom pick alone is not attached")
    -- the Custom colour has a default (white); the pick has none, so no profile gets one written
    check(MAIN:find("\n    friendlyNameColor = { r = 1, g = 1, b = 1 },\n", 1, true), "the Custom colour's default is not white")
    check(not MAIN:find("friendlyNameColorMode%s*="), "the pick has a default")
    check(MAIN:find("\n    classColorFriendly = true,\n    friendlyNameClassColor = false,\n", 1, true), "an older key's default moved")
    -- the health bar plates read the rule, never the older key by itself
    local painter = Cut(SRC, "local function PaintFriendlyColors(plate, unit, fp)", "ns.NP_PaintFriendlyColors = PaintFriendlyColors", "the painter")
    check(painter:find("local nameClass = ns.FriendlyNameClass(fp, false)", 1, true) and not painter:find("friendlyNameClassColor", 1, true),
        "the painter reads Class Colored Names by itself")
    -- the options write the pick and the colour, never an older key, for the names
    local OPT = ReadSource("EllesmereUIOptions/Nameplates_Options/FriendlyPage_Options.lua")
    local pair = Cut(OPT, "    local nameColorSwatches = {", "\n    -- Show [] Around Group/Raid: the second row of the first row's cog.", "the Name Color pair")
    check(not pair:find("classColorFriendly", 1, true) and not pair:find("friendlyNameClassColor", 1, true), "the Name Color pair writes an older key")
    check(not OPT:find("friendlyNameClassColor", 1, true), "the options page still writes or reads Class Colored Names by itself")
    -- every sender of the names' class colour CVar takes its value from the rule: the login setup, the friendly
    -- system pass and the options page's three writes
    local CVAR = "nameplateUseClassColorForFriendlyPlayerUnitNames"
    for _, src in ipairs({ { SRC, 1, "the friendly runtime" }, { CAST, 1, "the login setup" }, { OPT, 3, "the options page" } }) do
        local sends, ruled = 0, 0
        for line in src[1]:gmatch("[^\n]+") do
            if line:find(CVAR, 1, true) and line:find("SetCVar", 1, true) then
                sends = sends + 1
                if line:find('SetCVar, "' .. CVAR .. '", ns.FriendlyNameClassCVar(', 1, true)
                    or line:find('SetCVar("' .. CVAR .. '", ns.FriendlyNameClassCVar(', 1, true) then
                    ruled = ruled + 1
                end
            end
        end
        eq(sends, src[2], src[3] .. ": writes of the names' class colour CVar")
        eq(ruled, src[2], src[3] .. ": writes of that CVar that take the rule's value")
    end
    -- every language holds the new strings
    for _, code in ipairs({ "deDE", "esES", "frFR", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }) do
        local L = ReadSource("EllesmereUILocales/" .. code .. ".lua")
        for _, key in ipairs({ "Friendly Nameplate Style", "Requires Friendly Nameplate Style set to Name Only or Nameplate",
            "Requires Friendly Nameplate Style set to Nameplate", "Requires Friendly Nameplate Style set to Name Only", "Name Color",
            "Blizzard Default", "Name Only", "Nameplate", "Custom Color", "Class Color" }) do
            local _, n = L:gsub('\nL%["' .. key:gsub("%p", "%%%0") .. '"%]%s*=', "")
            eq(n, 1, code .. ": lines for " .. key)
        end
    end
end

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print(("PASS test_np_friendly_name_color (%d checks)"):format(count))
