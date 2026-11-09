-- Stub harness: Bags Pins per Character. Cuts the pin accessor from the main
-- Bags file and the option's row from the Bags options file, runs both under
-- stubs, and scans the module for pin reads that go round the accessor.
--   lua .tools/tests/test_bags_pins_per_character.lua        (from the repository root)
local MAIN = PINS_MAIN or "EllesmereUIBags/EllesmereUIBags.lua"
local OPTIONS = PINS_OPTIONS or "EllesmereUIOptions/EUI_Bags_Options.lua"
local PROFILES = PINS_PROFILES or "EllesmereUI_Profiles.lua"
local TOC = "EllesmereUIBags/EllesmereUIBags.toc"

local fails, count = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        print("  FAIL: " .. msg)
    end
end
local function Read(path)
    local fh = assert(io.open(path, "rb"), "cannot open " .. path)
    local text = fh:read("*a")
    fh:close()
    return (text:gsub("\r\n", "\n"))
end
local function Count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-------------------------------------------------------------------------------
-- The accessor, cut from the main file. It reads the character key through
-- BagsCharKey, handed in here.
-------------------------------------------------------------------------------
local main = Read(MAIN)
local a0 = assert(main:find("local function PinnedItems(create)", 1, true), "accessor not found")
local a1 = assert(main:find("ns.PinnedItems = PinnedItems", a0, true), "accessor export not found")
local curKey = "Tester - Realm"
local chunk = assert(loadstring("local BagsCharKey = ...\n" .. main:sub(a0, a1 - 1) .. "\nreturn PinnedItems"))
local PinnedItems = chunk(function() return curKey end)
check(main:find("PinnedItems = PinnedItems,", a1, true) ~= nil, "the accessor is handed to the part files")

-- 1. no account table: nothing to read or write, and none is made
EllesmereUIDB = nil
check(PinnedItems() == nil and PinnedItems(true) == nil, "no account table: nil")
check(EllesmereUIDB == nil, "no account table: none made")

-- 2. the default (the switch unset) is per character
EllesmereUIDB = { bagPinnedItems = { [6948] = 1, ["a:1"] = 999 } }
local shared = EllesmereUIDB.bagPinnedItems
check(PinnedItems() == shared, "unset: a character reads the shared pins before its first pin action")
check(EllesmereUIDB.bagPinnedByChar == nil, "unset: reads make no roster")
local own = PinnedItems(true)
check(own ~= shared and own[6948] == 1 and own["a:1"] == 999, "unset: the first pin action copies the shared pins")
check(EllesmereUIDB.bagPinnedByChar["Tester - Realm"] == own, "the copy is filed under the character's key")
own["b:2"] = 1
own[6948] = nil
check(shared[6948] == 1 and shared["b:2"] == nil and Count(shared) == 2, "the shared pins are not written while on")
check(PinnedItems() == own and PinnedItems(true) == own, "the character now reads and writes its own pins")

-- 3. another character starts from the shared pins, not from the first one's
curKey = "Alt - Realm"
check(PinnedItems() == shared, "a second character still reads the shared pins")
local alt = PinnedItems(true)
check(alt ~= own and alt ~= shared and alt[6948] == 1 and alt["b:2"] == nil, "a second character gets its own copy")
check(Count(EllesmereUIDB.bagPinnedByChar) == 2, "two characters, two entries")

-- 4. off: everyone on the shared pins, the copies kept
EllesmereUIDB.bagPinsPerCharacter = false
check(PinnedItems() == shared and PinnedItems(true) == shared, "off: shared pins for reads and writes")
shared["c:3"] = 1
check(EllesmereUIDB.bagPinnedByChar["Tester - Realm"] == own and own["c:3"] == nil, "off: the copies stay as they were")
-- back on: each character has its own set again, as it left it
EllesmereUIDB.bagPinsPerCharacter = nil
check(PinnedItems() == alt, "on again: the character's own pins are back")
curKey = "Tester - Realm"
check(PinnedItems() == own and own["b:2"] == 1, "on again: the first character's too")
-- a build that stored true for on reads as on
EllesmereUIDB.bagPinsPerCharacter = true
check(PinnedItems() == own, "a stored true reads as on")
EllesmereUIDB.bagPinsPerCharacter = nil

-- 5. identity not readable yet: reads fall back to the shared pins, a write gets nil
curKey = nil
check(PinnedItems() == shared, "no key: reads the shared pins")
check(PinnedItems(true) == nil, "no key: a pin action gets no table")
check(Count(EllesmereUIDB.bagPinnedByChar) == 2, "no key: no entry made")

-- 6. no shared pins yet: the first pin action starts an empty set of its own
EllesmereUIDB = {}
curKey = "Fresh - Realm"
check(PinnedItems() == nil and EllesmereUIDB.bagPinnedByChar == nil, "fresh: a read returns nil and makes nothing")
local fresh = PinnedItems(true)
check(type(fresh) == "table" and Count(fresh) == 0, "fresh: an empty set of its own")
check(EllesmereUIDB.bagPinnedItems == nil, "fresh: the shared table is not made while on")
-- off with no shared pins: the first pin action makes the shared table
EllesmereUIDB = { bagPinsPerCharacter = false }
check(PinnedItems() == nil, "off, fresh: a read returns nil")
local made = PinnedItems(true)
check(type(made) == "table" and made == EllesmereUIDB.bagPinnedItems, "off, fresh: a pin action makes the shared table")
check(EllesmereUIDB.bagPinnedByChar == nil, "off: no roster")

-- 7. a damaged roster value does not break it
EllesmereUIDB = { bagPinnedByChar = "x" }
check(PinnedItems() == nil, "damaged roster: a read returns the shared pins (none)")
check(type(PinnedItems(true)) == "table" and type(EllesmereUIDB.bagPinnedByChar) == "table", "damaged roster: replaced on a pin action")
EllesmereUIDB = { bagPinnedByChar = { ["Fresh - Realm"] = 5 }, bagPinnedItems = { [1] = 1 } }
check(PinnedItems() == EllesmereUIDB.bagPinnedItems, "damaged entry: a read returns the shared pins")
check(type(PinnedItems(true)) == "table" and EllesmereUIDB.bagPinnedByChar["Fresh - Realm"][1] == 1, "damaged entry: replaced by a copy")

-------------------------------------------------------------------------------
-- The option's row (the Pinned Items Options cog): on unless turned off, only
-- the off state stored, the bags repainted on a change.
-------------------------------------------------------------------------------
local options = Read(OPTIONS)
local r0 = assert(options:find('{ type="toggle", label="Pins per Character",', 1, true), "option row not found")
local r1 = assert(options:find("\n                          end },", r0, true), "option row end not found")
local rowText = options:sub(r0, r1 + #"\n                          end }" - 1)
local refreshed = 0
EUI_Bags = { RefreshInventory = function() refreshed = refreshed + 1 end }
local row = assert(loadstring("return " .. rowText))()
check(type(row.tooltip) == "string" and row.tooltip ~= "", "the row has a tooltip")
EllesmereUIDB = {}
check(row.get() == true, "option: on by default")
row.set(false)
check(EllesmereUIDB.bagPinsPerCharacter == false and row.get() == false, "option: off is stored as false")
check(refreshed == 1, "option: the bags repaint on a change")
row.set(true)
check(EllesmereUIDB.bagPinsPerCharacter == nil and row.get() == true, "option: on clears the key")
check(refreshed == 2, "option: the bags repaint when turned back on")
EllesmereUIDB.bagPinsPerCharacter = true
check(row.get() == true, "option: a stored true reads as on")
-- the row and the accessor agree
EllesmereUIDB = { bagPinnedItems = { [7] = 1 }, bagPinnedByChar = { ["Fresh - Realm"] = { [8] = 1 } } }
check(PinnedItems()[8] == 1, "on: the character's own pins")
row.set(false)
check(PinnedItems()[7] == 1 and PinnedItems()[8] == nil, "turned off in the options: the shared pins")
row.set(true)
check(PinnedItems()[8] == 1, "turned on again: its own pins")
-- no account table: the row neither errors nor makes one
EllesmereUIDB = nil
check(row.get() == true, "option without an account table reads on")
row.set(false)
check(EllesmereUIDB == nil, "option without an account table writes nothing")

-- the module reset clears the switch and every character's pins
local reset0 = assert(options:find("onReset = function()", 1, true), "reset not found")
local resetText = options:sub(reset0, reset0 + 2500)
check(resetText:find("EllesmereUIDB.bagPinnedItems = nil", 1, true) ~= nil, "reset clears the shared pins")
check(resetText:find("EllesmereUIDB.bagPinnedByChar = nil", 1, true) ~= nil, "reset clears every character's pins")
check(resetText:find("EllesmereUIDB.bagPinsPerCharacter = nil", 1, true) ~= nil, "reset puts the switch back to its default")

-------------------------------------------------------------------------------
-- A full-account export leaves the per-character pins out (a character
-- roster); the switch and the shared pins travel.
-------------------------------------------------------------------------------
local profiles = Read(PROFILES)
local x0 = assert(profiles:find("local FULL_EXPORT_EXCLUDED = {", 1, true), "export exclusions not found")
local x1 = assert(profiles:find("\n}", x0, true), "export exclusions end not found")
local excluded = profiles:sub(x0, x1)
check(excluded:find("%f[%w]bagPinnedByChar%s*=%s*true") ~= nil, "per-character pins are left out of a full export")
check(excluded:find("%f[%w]bagPinsPerCharacter%f[%W]") == nil, "the switch travels with a full export")
check(excluded:find("%f[%w]bagPinnedItems%f[%W]") == nil, "the shared pins travel with a full export")

-------------------------------------------------------------------------------
-- No file of the module reads or writes the shared table round the accessor:
-- the accessor, the first-open seed and the reset are its only users.
-------------------------------------------------------------------------------
local files = {}
for line in Read(TOC):gmatch("[^\n]+") do
    local name = line:match("^([%w_]+%.lua)")
    if name then files[#files + 1] = "EllesmereUIBags/" .. name end
end
check(#files > 10, "the module's files are listed (" .. #files .. ")")
local ALLOWED = { ["EllesmereUIBags/EllesmereUIBags.lua"] = true, ["EllesmereUIBags/EUI_Bags_Start.lua"] = true }
local users = 0
for _, path in ipairs(files) do
    local text = (PINS_SCAN and PINS_SCAN[path] and Read(PINS_SCAN[path])) or Read(path)
    if path == "EllesmereUIBags/EllesmereUIBags.lua" then text = main end
    local direct = text:find("bagPinnedItems", 1, true) ~= nil
    if direct and not ALLOWED[path] then
        check(false, path .. " touches bagPinnedItems round the accessor")
    end
    if text:find("PinnedItems(", 1, true) and path ~= "EllesmereUIBags/EllesmereUIBags.lua" then users = users + 1 end
end
check(users >= 5, "the pin sites go through the accessor (" .. users .. " files)")
-- in the main file, the shared table is touched inside the accessor alone
do
    local outside = main:sub(1, a0 - 1) .. main:sub(a1)
    local stripped = outside:gsub("%-%-[^\n]*", "")
    check(stripped:find("bagPinnedItems", 1, true) == nil, "the main file touches bagPinnedItems inside the accessor only")
end
-- the options file: the reset alone
do
    local n = 0
    for _ in options:gmatch("bagPinnedItems") do n = n + 1 end
    check(n == 1, "the options file touches bagPinnedItems in the reset only (" .. n .. ")")
end

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print("PASS test_bags_pins_per_character (" .. count .. " checks)")
