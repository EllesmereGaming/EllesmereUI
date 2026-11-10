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
function FontMT:SetShadowColor() end
function FontMT:SetShadowOffset() end
function FontMT:SetTextColor() end
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
local function Load(fonts, locale)
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

-------------------------------------------------------------------------------
--  3. Both settings on, a client without the combat text objects, a Poppins pick
-------------------------------------------------------------------------------
Load({ global = "Poppins", applyToAllGameText = true, gameTextScale = 110 })
local combat, world, menu = Build("shared", true)
E.ApplyGlobalFontToGameText()
Untouched(combat, "both settings, CombatTextFont")
Untouched(world, "both settings, SystemFont_World")
local face, size = DrawLatin(menu)
check(face == POP and math.abs(size - 13.2) < 1e-9, "both settings: the menu font is " .. tostring(face) .. " " .. tostring(size))

Load({ global = "Expressway", applyToAllGameText = true })
REG = {}
local lone = BlizzardFamily(FRIZ, 12)
Register("SystemFont_Shadow_Med1", lone)
local ok, err = pcall(E.ApplyGlobalFontToGameText)
check(ok, "no combat text objects: the pass raised " .. tostring(err))
check(DrawLatin(lone) == EXP, "no combat text objects: the pass stopped short")

-- the pass is still free while both settings are off
Load({ global = "Expressway" })
combat, world, menu = Build("shared", true)
E.ApplyGlobalFontToGameText()
check(STANDARD_TEXT_FONT == FRIZ and DrawLatin(menu) == FRIZ and menu._size == 12, "the pass ran with both settings off")

print(string.format("game text combat font harness: %d checks, %d failed", count, fails))
if fails > 0 then error("game text combat font harness failed") end
