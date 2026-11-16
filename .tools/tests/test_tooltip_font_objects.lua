-- Stub harness: Blizzard Skins+' tooltip skin keeps Blizzard's three shared
-- tooltip font objects in step with the sizes its per-line pass gives the
-- tooltip's own lines (GameTooltipHeaderText at the title size, GameTooltipText
-- and GameTooltipTextSmall at the body size, Font Size Scale included), so a
-- line another addon adds after the tooltip shows, which draws from those
-- objects and never meets the per-line pass, comes out at the same size.
-- Runs the real EllesmereUI_Fonts.lua over the stubs of test_font_family.lua
-- (that file up to its first section) with _ttFontSpec cut out of
-- EUI_BlizzardSkin_TooltipSkin.lua by its first and last lines, and checks the
-- sizes after the login passes in both orders, that the objects are written
-- only when the face, the outline or a rounded size changes, and that nothing
-- touches them while Reskin Tooltip is off.
--   lua .tools/tests/test_tooltip_font_objects.lua   (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return src
end

-- the font family harness's stubs: everything above its first section
local FAMILY = ReadSource(".tools/tests/test_font_family.lua")
local STUBS = FAMILY:sub(1, assert(FAMILY:find("--  1. One family per key", 1, true), "the font family harness's first section was renamed") - 1)

local SKIN = ReadSource("EllesmereUIBlizzardSkin/EUI_BlizzardSkin_TooltipSkin.lua"):gsub("\r\n", "\n")
local a = assert(SKIN:find("    local _ttObjSynced = {}\n", 1, true), "the sync's first line not found")
local b = assert(SKIN:find("    local function _ttFonts(tt, startFrom)\n", a, true), "the sync's last line not found")
local SPEC = SKIN:sub(a, b - 1)

-- the wiring: the per-line pass takes its sizes from the same function, and
-- the login pass runs it before any tooltip shows
local fonts = SKIN:sub(b, b + 400)
assert(fonts:find("local fp, ol, titleSize, bodySize = _ttFontSpec()", 1, true), "the per-line pass does not take its sizes from the sync")
local init = assert(SKIN:find("    local function _ttInitVisual()\n", b, true), "the login pass not found")
assert(SKIN:sub(init, init + 300):find("\n        _ttFontSpec()\n", 1, true), "the login pass does not sync the font objects")
-- a module that calls a parent function lists it in its stale-parent guard
local guard = ReadSource("EllesmereUIBlizzardSkin/EllesmereUIBlizzardSkin.lua"):match("\nif not %(EllesmereUI and [^\n]*stale%-parent guard[^\n]*")
assert(guard and guard:find("EllesmereUI.SetFontObjectFace", 1, true), "the stale-parent guard does not list EllesmereUI.SetFontObjectFace")

local BODY = [==[
local function Member(obj, alphabet, face, size, flags, what)
    local m = obj._members and obj._members[alphabet] or obj
    assert(m._face == face, what .. ": " .. alphabet .. " face " .. tostring(m._face))
    assert(Near(m._size, size), what .. ": " .. alphabet .. " size " .. tostring(m._size))
    assert(m._flags == flags, what .. ": " .. alphabet .. " flags " .. tostring(m._flags))
end
local function Sizes(r, k, z)
    return { roman = { FRIZ, r, "" }, russian = { CYR, r, "" }, korean = { KO, k, "" },
        simplifiedchinese = { ZHCN, z, "" }, traditionalchinese = { ZHTW, z, "" } }
end
-- a fresh client with the game's own three objects at their own sizes
-- (body 12, header 14, small 10; the Korean members differ), and the sync
local function Fresh(db)
    local E = Load("enUS", { db = db, loaded = { EllesmereUIBlizzardSkin = true } })
    GameTooltipText = BlizzardFamily("GameTooltipText", Sizes(12, 13, 13))
    GameTooltipHeaderText = BlizzardFamily("GameTooltipHeaderText", Sizes(14, 12, 14))
    GameTooltipTextSmall = BlizzardFamily("GameTooltipTextSmall", Sizes(10, 13, 10))
    local writes = 0
    local real = E.SetFontObjectFace
    E.SetFontObjectFace = function(...) writes = writes + 1; return real(...) end
    local sync = assert(loadstring(SPEC_SRC .. "\nreturn _ttFontSpec", "=_ttFontSpec"))()
    return E, sync, function() local w = writes; writes = 0; return w end
end
local OUT = "OUTLINE, SLUG"

-- A. the login order: the game text pass (Game Text Scale 110), the module
--    font failsafe (our face, the size kept), then the skin's sync
local E, sync, Writes = Fresh({ fonts = { global = "Poppins", outlineMode = "outline", gameTextScale = 110 } })
E.ApplyGlobalFontToGameText()
Member(GameTooltipText, "roman", FRIZ, 13.2, "", "A: Game Text Scale before the skin")
E.ApplyModuleFontFailsafe()
Member(GameTooltipText, "roman", POP, 13.2, OUT, "A: the failsafe keeps the size it finds")
Writes()
local face, outline, title, body = sync()
assert(face == POP and outline == OUT and title == 13 and body == 11, "A: the values the per-line pass gets")
assert(Writes() == 3, "A: the three objects were not written on the first call")
local FACES = { roman = POP, russian = CYR, korean = KO, simplifiedchinese = ZHCN, traditionalchinese = ZHTW }
for alphabet, f in pairs(FACES) do
    Member(GameTooltipText, alphabet, f, 11, OUT, "A: the body object")
    Member(GameTooltipHeaderText, alphabet, f, 13, OUT, "A: the header object")
    Member(GameTooltipTextSmall, alphabet, f, 11, OUT, "A: the small object takes the body size")
end

-- B. written only on a change: the same values write nothing, a scale that
--    rounds to the same sizes writes nothing, a new size, outline or face does
sync(); sync()
assert(Writes() == 0, "B: a repeated call wrote the objects")
EllesmereUIDB.tooltipFontScale = 0.85
sync()
assert(Writes() == 3, "B: a new Font Size Scale did not reach the objects")
Member(GameTooltipText, "roman", POP, 9, OUT, "B: body at 85%")
Member(GameTooltipHeaderText, "roman", POP, 11, OUT, "B: header at 85%")
Member(GameTooltipTextSmall, "roman", POP, 9, OUT, "B: small at 85%")
EllesmereUIDB.tooltipFontScale = 0.86
sync()
assert(Writes() == 0, "B: a scale that rounds to the same sizes wrote the objects")
EllesmereUIDB.tooltipFontScale = 1.5
_, _, title, body = sync()
assert(title == 20 and body == 17 and Writes() == 3, "B: 150%: title " .. tostring(title) .. ", body " .. tostring(body))
Member(GameTooltipHeaderText, "roman", POP, 20, OUT, "B: header at 150%")
-- one size alone moves: 103% to 104% the title (13 to 14, body 11), 104% to
-- 105% the body (11 to 12, title 14)
EllesmereUIDB.tooltipFontScale = 1.03
_, _, title, body = sync()
assert(title == 13 and body == 11, "B: 103%")
Writes()
EllesmereUIDB.tooltipFontScale = 1.04
_, _, title, body = sync()
assert(title == 14 and body == 11 and Writes() == 3, "B: a title size that moved alone did not reach the objects")
Member(GameTooltipHeaderText, "roman", POP, 14, OUT, "B: header at 104%")
EllesmereUIDB.tooltipFontScale = 1.05
_, _, title, body = sync()
assert(title == 14 and body == 12 and Writes() == 3, "B: a body size that moved alone did not reach the objects")
Member(GameTooltipText, "roman", POP, 12, OUT, "B: body at 105%")
Member(GameTooltipTextSmall, "roman", POP, 12, OUT, "B: small at 105%")
EllesmereUIDB.tooltipFontScale = 0.85
sync(); Writes()
EllesmereUIDB.fonts.outlineMode = "none"
E.InvalidateFontCache()
local _, plain = sync()
assert(Writes() == 3 and plain ~= OUT, "B: an outline change did not reach the objects")
Member(GameTooltipText, "roman", POP, 9, plain, "B: the new outline")
EllesmereUIDB.fonts.global = "Expressway"
E.InvalidateFontCache()
face = sync()
assert(Writes() == 3 and face == EXP, "B: a face change did not reach the objects")
Member(GameTooltipText, "roman", EXP, 9, plain, "B: the new face")
Member(GameTooltipText, "korean", KO, 9, plain, "B: the new face leaves the other alphabets' faces")

-- C. the other order: the sync first, then the failsafe: the sizes stay
E, sync, Writes = Fresh({ fonts = { global = "Poppins", outlineMode = "outline" } })
sync()
E.ApplyModuleFontFailsafe()
Member(GameTooltipText, "roman", POP, 11, OUT, "C: the failsafe after the sync")
Member(GameTooltipHeaderText, "roman", POP, 13, OUT, "C: the failsafe after the sync, header")
Member(GameTooltipTextSmall, "roman", POP, 11, OUT, "C: the failsafe after the sync, small")

-- D. Reskin Tooltip off: the skin never runs the sync, and the failsafe
--    leaves the objects alone too: the game's own faces and sizes
E, sync, Writes = Fresh({ customTooltips = false, fonts = { global = "Poppins" } })
E.ApplyModuleFontFailsafe()
Member(GameTooltipText, "roman", FRIZ, 12, "", "D: Reskin Tooltip off")
Member(GameTooltipHeaderText, "roman", FRIZ, 14, "", "D: Reskin Tooltip off, header")
Member(GameTooltipTextSmall, "roman", FRIZ, 10, "", "D: Reskin Tooltip off, small")
assert(Writes() == 0, "D: Reskin Tooltip off wrote the objects")
print("tooltip font objects harness: ok")
]==]

assert(loadstring(STUBS .. "\nlocal SPEC_SRC = " .. string.format("%q", SPEC) .. "\n" .. BODY, "=tooltip-font-objects"))()
