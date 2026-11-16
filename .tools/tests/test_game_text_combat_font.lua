-- Stub harness: Apply to All Game Text and Game Text Scale leave the floating
-- combat text's font objects alone. The text over the player draws with
-- CombatTextFont (on the SystemFont_World family) and the numbers over enemies
-- with DAMAGE_TEXT_FONT, which the pass never writes; both follow the Combat Text
-- Font setting alone, so with that setting on Blizzard Default the two must keep
-- one face. Loads EllesmereUI_Fonts.lua over stubs of font objects and families
-- (an object whose alphabets answer its parent's members, one with members of its
-- own, a plain one) and runs the login pass in both registration orders.
-- The model is this file's reading of the client, not the client.
--   lua .tools/tests/test_game_text_combat_font.lua   (from the repository root)
local FONTS = GT_FONTS or "EllesmereUI_Fonts.lua"

local fails, count = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        print("  FAIL: " .. msg)
    end
end

local function Read(path)
    local fh = assert(io.open(path, "rb"))
    local s = fh:read("*a")
    fh:close()
    return s
end
local SRC = Read(FONTS)

local MEDIA = "Interface\\AddOns\\EllesmereUI\\media\\"
local EXP = MEDIA .. "fonts\\Expressway.TTF"
local POP = MEDIA .. "fonts\\Poppins.ttf"
local FRIZ = "Fonts\\FRIZQT__.TTF"
local CYR = "Fonts\\FRIZQT___CYR.TTF"
local KO, ZHCN, ZHTW = "Fonts\\2002.TTF", "Fonts\\ARKai_T.ttf", "Fonts\\blei00d.TTF"
local ALPHABETS = { "roman", "russian", "korean", "simplifiedchinese", "traditionalchinese" }
local GLYPH = { koKR = KO, zhCN = ZHCN, zhTW = ZHTW, ruRU = CYR }

function wipe(t)
    for k in pairs(t) do t[k] = nil end
    return t
end

-------------------------------------------------------------------------------
--  Game stubs
-------------------------------------------------------------------------------
local REG
local FontMT = {}
FontMT.__index = FontMT
local function NewFont(face, size, flags)
    return setmetatable({ _face = face, _size = size, _flags = flags }, FontMT)
end
function FontMT:GetFont() return self._face, self._size, self._flags end
-- On a family this sets only its own font, never a member.
function FontMT:SetFont(face, size, flags)
    assert(type(face) == "string" and type(size) == "number" and size > 0, "a bad SetFont on a font object")
    self._face, self._size, self._flags = face, size, flags
end
function FontMT:SetShadowColor(r, g, b, a) self._shadow = { r, g, b, a } end
function FontMT:GetShadowColor()
    local s = self._shadow
    if s then return s[1], s[2], s[3], s[4] end
    return 0, 0, 0, 0
end
function FontMT:SetShadowOffset(x, y) self._shadowX, self._shadowY = x, y end
function FontMT:GetShadowOffset() return self._shadowX or 0, self._shadowY or 0 end
function FontMT:SetTextColor(r, g, b, a) self._color = { r, g, b, a } end
function FontMT:GetTextColor()
    local c = self._color
    if c then return c[1], c[2], c[3], c[4] end
    return 1, 1, 1, 1
end
-- Pointing an object at a family: its alphabets then answer that family's members (the owner's
-- in-game dump, 2026-11-13: after SetFontObject(a family of ours) the hotkey font's roman
-- member is no longer the one it shared with NumberFontNormalSmall). What the object keeps of
-- its own colour and shadow is not known, so the model drops both: the caller must put them back.
function FontMT:SetFontObject(font)
    self._members = font._members
    self._face, self._size, self._flags = font:GetFont()
    self._color, self._shadow, self._shadowX, self._shadowY = nil, nil, nil, nil
end
function FontMT:SetJustifyH() end
function FontMT:SetJustifyV() end
function FontMT:GetFontObjectForAlphabet(alphabet)
    if self._members then return self._members[alphabet] end
    return self
end

local function Register(name, obj)
    _G[name] = obj
    REG[#REG + 1] = name
end

-- A Blizzard family as Fonts.xml makes them.
local function BlizzardFamily(face, size)
    local fam = NewFont(face, size, "")
    fam._members = {
        roman = NewFont(face, size, ""), russian = NewFont(CYR, size, ""), korean = NewFont(KO, size, ""),
        simplifiedchinese = NewFont(ZHCN, size, ""), traditionalchinese = NewFont(ZHTW, size, ""),
    }
    return fam
end

-- What a font string on `obj` draws Latin text with.
local function DrawLatin(obj)
    local m = obj._members and obj._members.roman or obj
    return m._face, m._size
end

local function StubCreateFrame()
    local f = { Hide = function() end }
    function f:CreateFontString()
        return { SetFont = function() return true end, SetFontObject = function() end }
    end
    function f:RegisterEvent() end
    function f:UnregisterEvent() end
    function f:UnregisterAllEvents() end
    function f:SetScript() end
    return f
end

local E
local famCalls, famFail = 0, false   -- CreateFontFamily: how often it ran, and whether it fails
local function Load(fonts, locale)
    famCalls, famFail = 0, false
    REG = {}
    EUI_CLIENT_BLOCKED = nil
    LibStub = nil
    STANDARD_TEXT_FONT = FRIZ
    CombatTextFont, SystemFont_World = nil, nil
    CreateFont = function(name)
        local f = NewFont(FRIZ, 12, "")
        if name then _G[name] = f end
        return f
    end
    CreateFrame = StubCreateFrame
    CreateFontFamily = function(name, members)
        famCalls = famCalls + 1
        if famFail then error("the family could not be made") end
        local fam = NewFont(members[1].file, members[1].height, members[1].flags)
        fam._members = {}
        for _, m in ipairs(members) do fam._members[m.alphabet] = NewFont(m.file, m.height, m.flags) end
        if name then _G[name] = fam end
        return fam
    end
    GetLocale = function() return locale or "enUS" end
    GetFonts = function()
        local out = {}
        for i, n in ipairs(REG) do out[i] = n end
        return out
    end
    C_AddOns = { IsAddOnLoaded = function() return false end }
    EllesmereUIDB = { fonts = fonts }
    EllesmereUI = { MEDIA_PATH = MEDIA, LocaleGlyphFont = function(l) return GLYPH[l] end }
    _G.EllesmereUI = EllesmereUI
    assert(loadstring(SRC, "=EllesmereUI_Fonts.lua"))()
    E = EllesmereUI
end

-- The combat text pair in one of three shapes, and two ordinary objects.
--   shared: CombatTextFont's alphabets answer SystemFont_World's members
--   own:    CombatTextFont has members of its own
--   plain:  CombatTextFont answers itself for every alphabet
local function Build(shape, combatFirst)
    local world = BlizzardFamily(FRIZ, 64)
    local combat
    if shape == "shared" then
        combat = NewFont(FRIZ, 64, "")
        combat._members = world._members
    elseif shape == "own" then
        combat = BlizzardFamily(FRIZ, 64)
    else
        combat = NewFont(FRIZ, 64, "")
    end
    local menu = BlizzardFamily(FRIZ, 12)
    local child = NewFont(FRIZ, 12, "")
    child._members = menu._members
    if combatFirst then
        Register("CombatTextFont", combat)
        Register("SystemFont_World", world)
    end
    Register("SystemFont_Shadow_Med1", menu)
    Register("GameFontNormal", child)
    if not combatFirst then
        Register("SystemFont_World", world)
        Register("CombatTextFont", combat)
    end
    return combat, world, menu, child
end

local function Untouched(obj, what)
    local face, size = DrawLatin(obj)
    check(face == FRIZ and size == 64, what .. ": draws " .. tostring(face) .. " " .. tostring(size))
    check(obj._face == FRIZ and obj._size == 64, what .. ": own font " .. tostring(obj._face) .. " " .. tostring(obj._size))
    if obj._members then
        for _, a in ipairs(ALPHABETS) do
            check(obj._members[a]._size == 64, what .. ": " .. a .. " member size " .. tostring(obj._members[a]._size))
        end
        check(obj._members.russian._face == CYR and obj._members.korean._face == KO,
            what .. ": a member's face changed")
    end
end

-------------------------------------------------------------------------------
--  1. Apply to All Game Text: the combat text objects keep Blizzard's face, the
--     rest of the game text takes the global font
-------------------------------------------------------------------------------
for _, shape in ipairs({ "shared", "own", "plain" }) do
    for _, first in ipairs({ true, false }) do
        local tag = shape .. (first and ", combat text listed first" or ", combat text listed last")
        Load({ global = "Expressway", applyToAllGameText = true })
        local combat, world, menu, child = Build(shape, first)
        E.ApplyGlobalFontToGameText()
        check(STANDARD_TEXT_FONT == EXP, tag .. ": the standard font is not the global font")
        Untouched(combat, tag .. ", CombatTextFont")
        Untouched(world, tag .. ", SystemFont_World")
        check(DrawLatin(menu) == EXP and menu._face == EXP, tag .. ": the menu font did not take the global font")
        check(menu._members.korean._face == KO, tag .. ": the menu font's korean member took a Latin face")
        check(DrawLatin(child) == EXP and child._face == EXP, tag .. ": an object on the menu font's members did not follow")
    end
end

-------------------------------------------------------------------------------
--  2. Game Text Scale alone: the combat text objects keep their size, the rest
--     scales
-------------------------------------------------------------------------------
for _, shape in ipairs({ "shared", "own", "plain" }) do
    Load({ global = "Poppins", gameTextScale = 125 })
    local combat, world, menu, child = Build(shape, false)
    E.ApplyGlobalFontToGameText()
    check(STANDARD_TEXT_FONT == FRIZ, shape .. ": scale alone set the standard font")
    Untouched(combat, shape .. " scale, CombatTextFont")
    Untouched(world, shape .. " scale, SystemFont_World")
    local face, size = DrawLatin(menu)
    check(face == FRIZ and size == 15, shape .. " scale: the menu font did not scale (" .. tostring(size) .. ")")
    check(child._size == 15, shape .. " scale: an object on the menu font's members did not scale")
end

---------------------------------------------------------------------------------------------
--  4. The hotkey font keeps its faces under the face swap (RANGE_INDICATOR needs a
--     glyph most bundled faces lack) and still scales. It shares its members with the
--     family behind the count texts, which must NOT keep Blizzard's face with it: the
--     hotkey font moves onto a family of our own.
-------------------------------------------------------------------------------
local ARIALN = "Fonts\\ARIALN.TTF"
-- shape: "shared" (the client: the hotkey font and the count font answer the family's
-- members), "own" (members of its own) or "plain" (no members).
local function Hotkey(shape, grayFirst, fonts)
    Load(fonts)
    local mono = BlizzardFamily(ARIALN, 12)
    local small = NewFont(ARIALN, 12, "")          -- the count texts' font, on the same family
    small._members = mono._members
    local gray
    if shape == "shared" then
        gray = NewFont(ARIALN, 12, "")
        gray._members = mono._members
    elseif shape == "own" then
        gray = BlizzardFamily(ARIALN, 12)
    else
        gray = NewFont(ARIALN, 12, "")
    end
    gray:SetTextColor(0.6, 0.6, 0.6, 1)
    gray:SetShadowColor(0, 0, 0, 0.5)
    gray:SetShadowOffset(1, -1)
    local other = BlizzardFamily(FRIZ, 12)
    if grayFirst then Register("NumberFontNormalSmallGray", gray) end
    Register("NumberFont_OutlineThick_Mono_Small", mono)
    Register("NumberFontNormalSmall", small)
    Register("GameFontNormal", other)
    if not grayFirst then Register("NumberFontNormalSmallGray", gray) end
    return gray, mono, small, other
end
local SWAP125 = { global = "Expressway", applyToAllGameText = true, gameTextScale = 125 }
for _, shape in ipairs({ "shared", "own", "plain" }) do
    for _, grayFirst in ipairs({ true, false }) do
        local tag = shape .. ", hotkey font listed " .. (grayFirst and "first" or "last")
        local gray, mono, small, other = Hotkey(shape, grayFirst, SWAP125)
        local sharedBefore = gray._members
        E.ApplyGlobalFontToGameText()
        local f, sz = DrawLatin(gray)
        check(f == ARIALN and sz == 15, tag .. ": the hotkey font draws " .. tostring(f) .. " " .. tostring(sz))
        f, sz = DrawLatin(mono)
        check(f == EXP and sz == 15, tag .. ": the family behind the count texts draws " .. tostring(f) .. " " .. tostring(sz))
        f, sz = DrawLatin(small)
        check(f == EXP and sz == 15, tag .. ": the count font draws " .. tostring(f) .. " " .. tostring(sz))
        f, sz = DrawLatin(other)
        check(f == EXP and sz == 15, tag .. ": an ordinary font draws " .. tostring(f) .. " " .. tostring(sz))
        -- its own font too (what GetFont() reads and copies take): Blizzard's face, scaled once
        local ownFace, ownSize = gray:GetFont()
        check(ownFace == ARIALN and ownSize == 15, tag .. ": the hotkey font's own font reads " .. tostring(ownFace) .. " " .. tostring(ownSize))
        local r, g, b = gray:GetTextColor()
        check(r == 0.6 and g == 0.6 and b == 0.6, tag .. ": the hotkey font lost its grey (" .. tostring(r) .. ")")
        local _, _, _, sa = gray:GetShadowColor()
        local sx, sy = gray:GetShadowOffset()
        check(sa == 0.5 and sx == 1 and sy == -1, tag .. ": the hotkey font lost its shadow")
        if shape == "plain" then
            check(famCalls == 0, tag .. ": a family was made for a font object that has no members")
        else
            check(famCalls == 1, tag .. ": " .. famCalls .. " families were made for the hotkey font")
            check(gray._members ~= sharedBefore and gray._members.roman ~= mono._members.roman,
                tag .. ": the hotkey font still draws through the members it had")
            -- every alphabet keeps the face it had, at the scaled size
            local m = gray._members
            check(m.russian._face == CYR and m.korean._face == KO and m.simplifiedchinese._face == ZHCN
                and m.traditionalchinese._face == ZHTW, tag .. ": a member of the hotkey font's family lost its own face")
            check(m.russian._size == 15 and m.korean._size == 15, tag .. ": a member of the hotkey font's family is not scaled once")
            -- ours: a later pass over the game's font list leaves the family and its members alone
            check(E._fontFamilySet[m.roman] == true, tag .. ": the hotkey font's family is not marked as ours")
        end
    end
end

-- the face swap at 100%: the same split, nothing scaled
do
    local gray, mono, small = Hotkey("shared", true, { global = "Expressway", applyToAllGameText = true })
    E.ApplyGlobalFontToGameText()
    local f, sz = DrawLatin(gray)
    check(f == ARIALN and sz == 12, "swap at 100%: the hotkey font draws " .. tostring(f) .. " " .. tostring(sz))
    f, sz = DrawLatin(small)
    check(f == EXP and sz == 12, "swap at 100%: the count font draws " .. tostring(f) .. " " .. tostring(sz))
end

-- a scale alone takes no face away: no family, the members stay shared and scale once
for _, grayFirst in ipairs({ true, false }) do
    local tag = "scale alone, hotkey font listed " .. (grayFirst and "first" or "last")
    local gray, mono, small = Hotkey("shared", grayFirst, { global = "Expressway", gameTextScale = 125 })
    E.ApplyGlobalFontToGameText()
    check(famCalls == 0 and gray._members == mono._members, tag .. ": the hotkey font was moved onto a family of its own")
    local f, sz = DrawLatin(gray)
    check(f == ARIALN and sz == 15, tag .. ": the hotkey font draws " .. tostring(f) .. " " .. tostring(sz))
    f, sz = DrawLatin(small)
    check(f == ARIALN and sz == 15, tag .. ": the count font draws " .. tostring(f) .. " " .. tostring(sz))
end

-- the family cannot be made: no error, and the hotkey font is left to the pass with the rest
-- (it takes the chosen face, as before the fix; the count texts are not held back for it)
do
    local gray, mono, small = Hotkey("shared", true, SWAP125)
    famFail = true
    local okPass, errPass = pcall(E.ApplyGlobalFontToGameText)
    check(okPass, "the family cannot be made: the pass raised " .. tostring(errPass))
    local f, sz = DrawLatin(small)
    check(f == EXP and sz == 15, "the family cannot be made: the count font draws " .. tostring(f) .. " " .. tostring(sz))
    check(gray._members == mono._members, "the family cannot be made: the hotkey font left its members anyway")
    famFail = false
end

-- both settings off: nothing is made for the hotkey font
do
    local gray, mono = Hotkey("shared", true, { global = "Expressway" })
    E.ApplyGlobalFontToGameText()
    check(famCalls == 0 and gray._members == mono._members and DrawLatin(gray) == ARIALN, "both settings off: the hotkey font was touched")
end

------------------------------------------------------------------------------
--  4. The hotkey font keeps its face (RANGE_INDICATOR needs a glyph most bundled
--     faces lack) but still scales, also when it shares its parent's members
-------------------------------------------------------------------------------
local ARIALN = "Fonts\\ARIALN.TTF"
for _, grayFirst in ipairs({ true, false }) do
    local tag = grayFirst and "hotkey font listed first" or "hotkey font listed last"
    Load({ global = "Expressway", applyToAllGameText = true, gameTextScale = 125 })
    local mono = BlizzardFamily(ARIALN, 12)
    local gray = NewFont(ARIALN, 12, "")
    gray._members = mono._members
    local other = BlizzardFamily(FRIZ, 12)
    if grayFirst then Register("NumberFontNormalSmallGray", gray) end
    Register("NumberFont_OutlineThick_Mono_Small", mono)
    Register("GameFontNormal", other)
    if not grayFirst then Register("NumberFontNormalSmallGray", gray) end
    E.ApplyGlobalFontToGameText()
    local f, sz = DrawLatin(gray)
    check(f == ARIALN and sz == 15, tag .. ": the hotkey font draws " .. tostring(f) .. " " .. tostring(sz))
    f, sz = DrawLatin(other)
    check(f == EXP and sz == 15, tag .. ": an ordinary font draws " .. tostring(f) .. " " .. tostring(sz))
end

print(string.format("game text combat font harness: %d checks, %d failed", count, fails))
if fails > 0 then error("game text combat font harness failed") end
