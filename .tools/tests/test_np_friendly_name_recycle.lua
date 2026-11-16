-- Stub harness: Nameplates, friendly name-only plates: a recycled name text never shows
-- another unit's name (EllesmereUINameplatesFriendly.lua, UpdateNameOnlyText).
-- With Subtitle Text, the Name Format or Show Level on, a friendly player's title, guild line
-- and level are composed onto Blizzard's own name FontString, through a hook on its SetText and
-- the unit token remembered for it. Blizzard pools the plates' unit frames, so that FontString
-- can come back on another plate (a pet's) while its remembered token now names another player:
-- the pet then showed that player's name and guild. The composer writes only while the
-- remembered token's plate still holds the FontString; otherwise it forgets the token.
-- Driven here: the real composer and attach, and the real plate-removed hook, over a model of
-- Blizzard's driver (tokens, base plates, pooled unit frames; a removal detaches the unit frame
-- before any hook sees the plate).
--   lua .tools/tests/test_np_friendly_name_recycle.lua        (from the repository root)
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
        if fails <= 14 then print("  FAIL: " .. msg) end
    end
end

local SRC = ReadSource("EllesmereUINameplates/EllesmereUINameplatesFriendly.lua")

-------------------------------------------------------------------------------
-- Blizzard's driver: tokens, base plates, pooled unit frames with a name text
-------------------------------------------------------------------------------
local plates, units, pool = {}, {}, {}
local lookups, hooks = 0, 0
local function NewFS()
    local fs = {}
    function fs:SetText(t) self.text = t end
    function fs:SetFormattedText(fmt, ...) self.text = fmt:format(...) end
    function fs:SetWordWrap() end
    function fs:SetMaxLines(n) self.lines = n end
    return fs
end
-- A plate comes into view: the base plate takes a unit frame from the pool.
local function Add(token, base, unit)
    units[token], plates[token] = unit, base
    base.UnitFrame = table.remove(pool) or { name = NewFS() }
    return base.UnitFrame
end
-- Blizzard writes the unit's own name on the plate's name text (our hook runs after it).
local function BlizzName(token)
    plates[token].UnitFrame.name:SetText(units[token].name)
end
-- A plate leaves: the unit frame goes back to the pool, and the base plate keeps none.
local function Remove(token)
    local base = plates[token]
    pool[#pool + 1] = base.UnitFrame
    base.UnitFrame = nil
    units[token] = nil
    return base
end
local function hooksecurefunc(obj, name, fn)
    hooks = hooks + 1
    local orig = obj[name]
    obj[name] = function(...)
        local r = orig(...)
        fn(...)
        return r
    end
end

-- The settings the composer reads.
local mode, nameFormat, showLevel = "guild", nil, false

local Attach, _, nameFSUnits = assert(loadstring(
    "local GetBelowNameMode, ModeHasTitle, ModeHasGuild, GetTitledName, FriendlyNameFormat, FormatFriendlyName, ShowFriendlyLevel, " ..
    "FriendlyLevelText, GetSubTextColor, FP, EnsureNameUnconstrained, EllesmereUI, C_NamePlate, UnitExists, UnitCanAttack, UnitIsPlayer, " ..
    "UnitName, GetGuildInfo, issecretvalue, hooksecurefunc, UnitIsUnit, IsInRaid, UnitInRaid, GetRaidRosterInfo, UnitInParty = ...\n" ..
    -- Name Color's Custom colour, which the composer asks for (none picked here)
    Cut(SRC, "local NameEsc = {}", "-- Name Format (friendlyNameFormat:", "the Custom colour's escape") ..
    -- the group bracket rule the composer reads (Show [] Around Group/Raid; off here)
    Cut(SRC, 'local PARTY_BRACKET_OPEN  = ', "-- The player's name WITH their title as one string", "the bracket rule") ..
    Cut(SRC, 'local nameFSUnits = setmetatable({}, { __mode = "k" })', "-- Sweep all visible friendly player plates", "the composer") ..
    "\nreturn AttachNameOnlyText, UpdateNameOnlyText, nameFSUnits, nameFSText", "=EllesmereUINameplatesFriendly.lua (the composer)"))(
    function() return mode end,
    function(m) return m == "title" or m == "both" end,
    function(m) return m == "guild" or m == "both" end,
    function(u) return units[u] and units[u].titled end,
    function() return nameFormat end,
    function(_, name) return name:sub(1, 3) end,
    function() return showLevel end,
    function(u) return tostring(units[u].level or 60) end,
    function() return 0.8, 0.8, 0.8 end,
    function() return {} end,
    function() end,
    { WithSurname = function(name) return name end },
    { GetNamePlateForUnit = function(u) lookups = lookups + 1; return plates[u] end },
    function(u) return units[u] ~= nil end,
    function(_, u) return units[u].hostile == true end,
    function(u) return units[u].player == true end,
    function(u) return units[u].name end,
    function(u) return units[u].guild end,
    function() return false end,
    hooksecurefunc,
    function() return false end, function() return false end, function() return nil end, function() return nil end, function() return false end)

local function GuildLine(name, guild) return name .. "\n|cffcccccc<" .. guild .. ">|r" end

-------------------------------------------------------------------------------
-- 1. the reported case: a pet on a recycled unit frame keeps its own name
-------------------------------------------------------------------------------
do
    local A, B, C = {}, {}, {}
    local alice = Add("nameplate1", A, { name = "Alice", guild = "Knights", player = true })
    BlizzName("nameplate1")
    Attach(alice.name, "nameplate1")
    check(alice.name.text == GuildLine("Alice", "Knights"), "a friendly player's guild line is not composed: " .. tostring(alice.name.text))
    BlizzName("nameplate1")
    check(alice.name.text == GuildLine("Alice", "Knights"), "Blizzard's own name write is not recomposed")
    Remove("nameplate1")

    -- a pet takes the pooled unit frame under another token (nothing is attached for a pet)
    local pet = Add("nameplate2", B, { name = "Wolf", player = false })
    check(pet == alice, "the model did not recycle the unit frame")
    BlizzName("nameplate2")
    check(pet.name.text == "Wolf", "a pet's name is rewritten while the old token names nobody: " .. tostring(pet.name.text))
    -- the old token now names another player, on a fresh unit frame
    local bob = Add("nameplate1", C, { name = "Bob", guild = "Lions", player = true })
    BlizzName("nameplate1")
    Attach(bob.name, "nameplate1")
    -- Blizzard writes the pet's name again (a name update on the plate)
    BlizzName("nameplate2")
    check(pet.name.text == "Wolf", "the pet's plate shows " .. tostring(pet.name.text):gsub("\n", " / ") .. " (the player its unit frame last served)")
    check(nameFSUnits[pet.name] == nil, "the stale token is still remembered for the pet's name text")
    -- the stale token is gone, so later writes on the pet's text cost no plate lookup
    local n = lookups
    BlizzName("nameplate2")
    BlizzName("nameplate2")
    check(lookups == n, "a name text with no token still looks plates up (" .. (lookups - n) .. ")")
    check(pet.name.text == "Wolf", "the pet's name changed on a later write")
    -- the player on the old token keeps name and guild
    check(bob.name.text == GuildLine("Bob", "Lions"), "the player on the reused token lost the guild line: " .. tostring(bob.name.text))
    BlizzName("nameplate1")
    check(bob.name.text == GuildLine("Bob", "Lions"), "the player on the reused token is not recomposed after Blizzard's write")

    -- the pet leaves and its unit frame serves a player again: attached anew, one hook for its life
    local before = hooks
    Remove("nameplate2")
    local cara = Add("nameplate3", B, { name = "Cara", guild = "Owls", player = true })
    check(cara == pet, "the model did not recycle the unit frame a second time")
    BlizzName("nameplate3")
    Attach(cara.name, "nameplate3")
    check(cara.name.text == GuildLine("Cara", "Owls"), "a recycled name text is not composed for its new player")
    check(hooks == before, "the name text was hooked again (hooks stack)")
end

-------------------------------------------------------------------------------
-- 2. the edges of the guard
-------------------------------------------------------------------------------
do
    -- the remembered token's plate holds no unit frame at this moment
    local D = {}
    local dan = Add("nameplate4", D, { name = "Dan", guild = "Elks", player = true })
    BlizzName("nameplate4")
    Attach(dan.name, "nameplate4")
    D.UnitFrame = nil
    local ok = pcall(dan.name.SetText, dan.name, "Dan")
    check(ok and dan.name.text == "Dan" and nameFSUnits[dan.name] == nil, "a plate with no unit frame: the write errors or keeps the token")

    -- the lookup returns no plate for a token that still names a unit
    local E = {}
    local eve = Add("nameplate5", E, { name = "Eve", guild = "Ants", player = true })
    BlizzName("nameplate5")
    Attach(eve.name, "nameplate5")
    plates["nameplate5"] = nil
    eve.name:SetText("Someone")
    check(eve.name.text == "Someone" and nameFSUnits[eve.name] == nil, "no plate for the token: the stale name was written (" .. tostring(eve.name.text) .. ")")

    -- the same plate and text now serve a hostile player: Blizzard's name stands, with no guild line
    local F = {}
    local fay = Add("nameplate6", F, { name = "Fay", guild = "Bees", player = true })
    BlizzName("nameplate6")
    Attach(fay.name, "nameplate6")
    units["nameplate6"] = { name = "Rival", guild = "Foes", player = true, hostile = true }
    BlizzName("nameplate6")
    check(fay.name.text == "Rival", "a hostile player on the plate got a composed name: " .. tostring(fay.name.text))

    -- the token names nobody: nothing is written
    local G = {}
    local gus = Add("nameplate7", G, { name = "Gus", guild = "Cats", player = true })
    BlizzName("nameplate7")
    Attach(gus.name, "nameplate7")
    units["nameplate7"] = nil
    gus.name:SetText("Later")
    check(gus.name.text == "Later", "a token that names nobody was written through")
end

-------------------------------------------------------------------------------
-- 3. the other composed parts, and nothing at all while every option is off
-------------------------------------------------------------------------------
do
    local H = {}
    local hal = Add("nameplate8", H, { name = "Halvard", guild = "Rams", player = true, titled = "Sergeant Halvard", level = 42 })
    BlizzName("nameplate8")
    mode = "both"
    Attach(hal.name, "nameplate8")
    check(hal.name.text == GuildLine("Sergeant Halvard", "Rams"), "title and guild are not composed: " .. tostring(hal.name.text))
    mode, nameFormat = "none", "first"
    BlizzName("nameplate8")
    check(hal.name.text == "Hal", "the Name Format is not applied: " .. tostring(hal.name.text))
    nameFormat, showLevel = nil, true
    BlizzName("nameplate8")
    check(hal.name.text == "42 | Halvard", "Show Level is not composed: " .. tostring(hal.name.text))
    -- every option off: the hook returns before any plate lookup, and Blizzard's name stands
    showLevel = false
    local n = lookups
    BlizzName("nameplate8")
    check(lookups == n, "with every option off a name write still looks a plate up")
    check(hal.name.text == "Halvard", "with every option off the name is still rewritten: " .. tostring(hal.name.text))
    mode = "guild"
end

-------------------------------------------------------------------------------
-- 4. the plate-removed hook: Blizzard has detached the unit frame by then
-------------------------------------------------------------------------------
do
    local text = Cut(SRC, 'hooksecurefunc(NamePlateDriverFrame, "OnNamePlateRemoved", function(_, unit)', "\n-----", "the removed hook")
    local driver = { OnNamePlateRemoved = function() end }
    local hidden, restored = {}, {}
    local suppressed, modified = {}, {}
    assert(loadstring("local NamePlateDriverFrame, hooksecurefunc, C_NamePlate, HideNPCOverlay, nameOnlyNPCSuppressed, modifiedUFs, RestoreBlizzardUF, nameFSUnits, nameFSText = ...\n" .. text,
        "=EllesmereUINameplatesFriendly.lua (the removed hook)"))(driver, hooksecurefunc,
        { GetNamePlateForUnit = function(u) return plates[u] end },
        function(np) hidden[np] = true end, suppressed, modified, function(u) restored[u] = true end, {}, {})
    -- a plate as Blizzard leaves it: still the token's plate, with no unit frame
    local P = {}
    Add("nameplate9", P, { name = "Imp", player = false })
    suppressed[P], modified["nameplate9"] = true, {}
    Remove("nameplate9")
    local ok, err = pcall(driver.OnNamePlateRemoved, driver, "nameplate9")
    check(ok, "the removed hook errors on a plate with no unit frame: " .. tostring(err))
    check(hidden[P] == true and suppressed[P] == nil and restored["nameplate9"] == true, "the removed hook does not clean its overlay and suppression")
    -- the options preview fires it with a token that is no nameplate (it has a plate of its own)
    hidden = {}
    plates["preview"] = {}
    driver.OnNamePlateRemoved(driver, "preview")
    check(next(hidden) == nil, "the removed hook acts on the preview plate")
    -- no release from here: it would read a unit frame that is already gone
    check(text:find("nameFSUnits", 1, true) == nil and text:find("UnitFrame", 1, true) == nil, "the removed hook still carries a release that can never run")
end

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print(("PASS test_np_friendly_name_recycle (%d checks)"):format(count))
