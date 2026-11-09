-- Stub harness: loads EllesmereUI_Fonts.lua outside the game over stubs that model
-- the engine's font families (exactly five members, one member object per
-- alphabet, one member drawing a whole string by its content, the SetFont pin,
-- font objects pushing only the properties they define) and drives the family
-- helpers, the font object helpers and the two game text passes.
--   lua .tools/tests/test_font_family.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return src
end
local SRC = ReadSource("EllesmereUI_Fonts.lua")

-- The client's per-locale glyph faces, from the real EllesmereUI_Locale.lua.
local GlyphFont
do
    local src = ReadSource("EllesmereUI_Locale.lua")
    local s = assert(src:find("local function GlyphFont%(locale%)"), "GlyphFont not found")
    local e = assert(src:find("\nend", s, true), "GlyphFont has no end")
    GlyphFont = assert(loadstring(src:sub(s, e + 4) .. "\nreturn GlyphFont", "=GlyphFont"))()
end

local MEDIA = "Interface\\AddOns\\EllesmereUI\\media\\"
local EXP = MEDIA .. "fonts\\Expressway.TTF"
local POP = MEDIA .. "fonts\\Poppins.ttf"
local FRIZ = "Fonts\\FRIZQT__.TTF"
local CYR = "Fonts\\FRIZQT___CYR.TTF"
local KO, ZHCN, ZHTW = GlyphFont("koKR"), GlyphFont("zhCN"), GlyphFont("zhTW")
assert(KO and ZHCN and ZHTW and GlyphFont("ruRU") == CYR)
local BAD = "Interface\\AddOns\\Missing\\Gone.ttf"
local SM = "Interface\\AddOns\\SharedMediaFonts\\Fancy.ttf"
local ALPHABETS = { "roman", "russian", "korean", "simplifiedchinese", "traditionalchinese" }
local VALID = {}
for _, a in ipairs(ALPHABETS) do VALID[a] = true end
-- Sample texts as UTF-8 bytes: Latin, Cyrillic, Hangul.
local LATIN, CYRILLIC, HANGUL = "Hello", "\208\159\209\128\208\184\208\178\208\181\209\130", "\234\176\128"

local function Near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-9 end

-------------------------------------------------------------------------------
--  Game stubs
-------------------------------------------------------------------------------
local T, REG, BADFILES

-- Font objects: plain (each alphabet answers the object itself) or a family
-- (each alphabet answers its own member object).
local FontMT = {}
FontMT.__index = FontMT
local function NewFont(face, size, flags)
    return setmetatable({ _face = face, _size = size, _flags = flags }, FontMT)
end
function FontMT:GetFont() return self._face, self._size, self._flags end
-- On a family this sets only the family's own font, never a member, as in game (owner probe 2026-11-07).
function FontMT:SetFont(face, size, flags)
    assert(type(face) == "string" and type(size) == "number" and size > 0, "a bad SetFont on a font object")
    assert(type(flags) == "string", "a font object's SetFont takes flags")
    self._face, self._size, self._flags = face, size, flags
    T.objSetFont = T.objSetFont + 1
end
function FontMT:SetShadowColor(r, g, b, a) self._shadowColor = { r, g, b, a } end
function FontMT:SetShadowOffset(x, y) self._shadowOffset = { x, y } end
function FontMT:SetTextColor(r, g, b, a) self._color = { r, g, b, a or 1 } end
function FontMT:SetJustifyH(j) self._justifyH = j end
function FontMT:SetJustifyV(j) self._justifyV = j end
function FontMT:GetFontObjectForAlphabet(alphabet)
    assert(VALID[alphabet], "unknown alphabet " .. tostring(alphabet))
    if self._members then return self._members[alphabet] end
    return self
end

local function Register(name, obj)
    _G[name] = obj
    REG[#REG + 1] = name
end

local function StubCreateFont(name)
    local f = NewFont(FRIZ, 12, "")
    if name then Register(name, f) end
    return f
end

-- CreateFontFamily: exactly five members, one per alphabet, or it raises.
local function StubCreateFontFamily(name, members)
    T.created = T.created + 1
    if #members ~= 5 then
        error("unexpected number of member fonts (got " .. #members .. ", expected 5)")
    end
    local fam = NewFont(nil, nil, nil)
    fam._members = {}
    for _, m in ipairs(members) do
        assert(VALID[m.alphabet] and not fam._members[m.alphabet], "a bad or repeated alphabet")
        assert(type(m.file) == "string" and type(m.height) == "number" and type(m.flags) == "string",
            "a bad member")
        fam._members[m.alphabet] = NewFont(m.file, m.height, m.flags)
    end
    fam._face, fam._size, fam._flags = members[1].file, members[1].height, members[1].flags
    if name then Register(name, fam) end
    return fam
end

-- A Blizzard family as Fonts.xml makes them (built outside the counters).
local function BlizzardFamily(name, spec)
    local fam = NewFont(spec.roman[1], spec.roman[2], spec.roman[3])
    fam._members = {}
    for _, a in ipairs(ALPHABETS) do
        local s = spec[a]
        fam._members[a] = NewFont(s[1], s[2], s[3])
    end
    if name then Register(name, fam) end
    return fam
end
local function StockSpec()
    return { roman = { FRIZ, 12, "" }, russian = { CYR, 12, "" }, korean = { KO, 11, "" },
        simplifiedchinese = { ZHCN, 13, "" }, traditionalchinese = { ZHTW, 13, "OUTLINE" } }
end

-- Font strings: a plain SetFont pins the face for good; SetFontObject takes only the
-- properties the object defines; Draw answers what the engine draws a text with.
local FSMT = {}
FSMT.__index = FSMT
local function NewFontString(template)
    local fs = setmetatable({ _justifyH = "CENTER", _justifyV = "MIDDLE", _color = { 1, 1, 1, 1 }, _log = {} }, FSMT)
    if template then fs:SetFontObject(template) end
    fs._log = {}
    return fs
end
function FSMT:SetFont(face, size, flags)
    if self._probe then T.probe[face] = (T.probe[face] or 0) + 1 end
    if BADFILES[face] then return false end
    if not self._pin then self._pin = {} end
    self._pin[1], self._pin[2], self._pin[3] = face, size, flags
    return true
end
function FSMT:SetFontObject(obj)
    assert(obj ~= nil, "SetFontObject takes an object")
    T.setFontObject = T.setFontObject + 1
    self._log[#self._log + 1] = "SetFontObject"
    self._obj = obj
    if obj._color then self._color = { obj._color[1], obj._color[2], obj._color[3], obj._color[4] } end
    if obj._justifyH then self._justifyH = obj._justifyH end
    if obj._justifyV then self._justifyV = obj._justifyV end
end
function FSMT:GetFontObject() return self._obj end
function FSMT:GetJustifyH() T.reads = T.reads + 1; return self._justifyH end
function FSMT:GetJustifyV() return self._justifyV end
function FSMT:SetJustifyH(j) self._log[#self._log + 1] = "SetJustifyH"; self._justifyH = j end
function FSMT:SetJustifyV(j) self._log[#self._log + 1] = "SetJustifyV"; self._justifyV = j end
function FSMT:GetTextColor() T.reads = T.reads + 1; return unpack(self._color) end
function FSMT:SetTextColor(r, g, b, a)
    self._log[#self._log + 1] = "SetTextColor"
    self._color = { r, g, b, a or 1 }
end
-- face, size, flags and shadow alpha the engine draws `text` with
function FSMT:Draw(text)
    local obj = self._obj
    local shadow = obj and obj._shadowColor and obj._shadowColor[4] or 0
    if self._pin then return self._pin[1], self._pin[2], self._pin[3], shadow end
    if obj and obj._members then
        local alphabet = "roman"
        if text:find("[\208\209]") then
            alphabet = "russian"
        elseif text:find("[\234-\237]") then
            alphabet = "korean"
        end
        local m = obj._members[alphabet]
        return m._face, m._size, m._flags, shadow
    end
    return obj and obj._face, obj and obj._size, obj and obj._flags, shadow
end

-- Frames: the probe's holder and the login retry's listener. Fire hands an event
-- to every frame registered for it.
local function StubCreateFrame()
    local f = {
        _events = {},
        Hide = function() end,
        CreateFontString = function()
            local fs = NewFontString()
            fs._probe = true
            return fs
        end,
    }
    function f:RegisterEvent(event) self._events[event] = true end
    function f:UnregisterEvent(event) self._events[event] = nil end
    function f:UnregisterAllEvents() wipe(self._events) end
    function f:SetScript(name, fn) self["_" .. name] = fn end
    T.frames[#T.frames + 1] = f
    return f
end

local function Fire(event)
    for _, f in ipairs(T.frames) do
        if f._events[event] and f._OnEvent then f._OnEvent(f, event) end
    end
end

-- How many events the file's frames listen to.
local function Listening()
    local n = 0
    for _, f in ipairs(T.frames) do
        for _ in pairs(f._events) do n = n + 1 end
    end
    return n
end

function wipe(t)
    for k in pairs(t) do t[k] = nil end
    return t
end

-- Loads a fresh copy of the file for one client language.
local function Load(locale, opts)
    opts = opts or {}
    T = { created = 0, objSetFont = 0, setFontObject = 0, reads = 0, probe = {}, frames = {} }
    REG = {}
    BADFILES = { [BAD] = true }
    EUI_CLIENT_BLOCKED = nil
    LibStub = nil
    STANDARD_TEXT_FONT = FRIZ
    CreateFont = StubCreateFont
    CreateFrame = StubCreateFrame
    if opts.noFamilies then
        CreateFontFamily = nil
    elseif opts.failFamilies then
        CreateFontFamily = function()
            T.created = T.created + 1
            error("refused")
        end
    else
        CreateFontFamily = StubCreateFontFamily
    end
    GetLocale = function() return locale end
    GetFonts = function()
        local out = {}
        for i, n in ipairs(REG) do out[i] = n end
        return out
    end
    C_AddOns = { IsAddOnLoaded = function(name) return opts.loaded and opts.loaded[name] or false end }
    EllesmereUIDB = opts.db or {}
    EllesmereUI = { MEDIA_PATH = MEDIA, LocaleGlyphFont = GlyphFont }
    _G.EllesmereUI = EllesmereUI
    assert(loadstring(SRC, "=EllesmereUI_Fonts.lua"))()
    T.objSetFont, T.setFontObject = 0, 0
    return EllesmereUI
end

local function Faces(fam)
    local m = fam._members
    return m.roman._face, m.russian._face, m.korean._face, m.simplifiedchinese._face, m.traditionalchinese._face
end
local function CheckFaces(fam, roman, russian, korean, sc, tc, what)
    local r, c, k, s, t = Faces(fam)
    assert(r == roman, what .. ": roman " .. tostring(r))
    assert(c == russian, what .. ": russian " .. tostring(c))
    assert(k == korean, what .. ": korean " .. tostring(k))
    assert(s == sc, what .. ": simplifiedchinese " .. tostring(s))
    assert(t == tc, what .. ": traditionalchinese " .. tostring(t))
end

-------------------------------------------------------------------------------
--  1. One family per key, built once; a hit builds nothing
-------------------------------------------------------------------------------
local E = Load("enUS")
local fam = E.GetFontFamily(EXP, 12, "", true)
assert(fam and fam._members and T.created == 1, "no family for Expressway")
assert(_G.EUIFontFamily1 == fam, "the family is not named at creation")
assert(E.GetFontFamily(EXP, 12, "", true) == fam and T.created == 1, "a hit built a new family")
assert(E.GetFontFamily(EXP, 12, nil, true) == fam and T.created == 1, "nil flags are not the \"\" key")
local keys = {
    E.GetFontFamily(EXP, 13, "", true), E.GetFontFamily(EXP, 12, "OUTLINE", true),
    E.GetFontFamily(EXP, 12, "", false), E.GetFontFamily(POP, 12, "", true),
}
assert(T.created == 5, "one family per path / size / flags / shadow")
for i = 1, #keys do
    assert(keys[i] and keys[i] ~= fam, "two keys share a family")
    for j = i + 1, #keys do assert(keys[i] ~= keys[j], "two keys share a family") end
end
assert(E.GetFontFamily(EXP, 12, "", false) == keys[3] and E.GetFontFamily(EXP, 12, "", nil) == keys[3],
    "a nil shadow is not the false key")
-- sizes round to a quarter point: a scaled size reuses the nearest family
assert(E.GetFontFamily(EXP, 12.1, "", true) == fam and E.GetFontFamily(EXP, 11.9, "", true) == fam
    and T.created == 5, "a size within an eighth of a point built a family of its own")
local quarter = E.GetFontFamily(EXP, 12.2, "", true)
assert(quarter and quarter ~= fam and quarter._members.roman._size == 12.25 and T.created == 6,
    "a fractional size did not take its quarter point")
-- every member at the key's size and flags
for _, a in ipairs(ALPHABETS) do
    local m = keys[2]._members[a]
    assert(m._size == 12 and m._flags == "OUTLINE", "a member off the key's size or flags: " .. a)
end
-- a hit allocates nothing
local hitFs = NewFontString()
E.SetFontFamily(hitFs, EXP, 12, "", true)
collectgarbage("collect")
collectgarbage("stop")
local before = collectgarbage("count")
for _ = 1, 2000 do
    E.GetFontFamily(EXP, 12, "", true)
    E.GetFontFamily(EXP, 12, nil, true)
    E.SetFontFamily(hitFs, EXP, 12, "", true)
end
local after = collectgarbage("count")
collectgarbage("restart")
assert(after == before, "a cache hit allocated " .. (after - before) .. " KB")
assert(E.GetFontFamily(nil, 12, "", true) == nil and E.GetFontFamily(EXP, nil, "", true) == nil,
    "a family without a path or size")

-------------------------------------------------------------------------------
--  2. Member files per client and path; shadow on the family and members
-------------------------------------------------------------------------------
CheckFaces(fam, EXP, EXP, KO, ZHCN, ZHTW, "enUS Expressway")
CheckFaces(E.GetFontFamily(POP, 12, "", true), POP, CYR, KO, ZHCN, ZHTW, "enUS Poppins")
CheckFaces(E.GetFontFamily(FRIZ, 12, "", true), FRIZ, CYR, KO, ZHCN, ZHTW, "enUS Friz")
CheckFaces(E.GetFontFamily(SM, 12, "", true), SM, CYR, KO, ZHCN, ZHTW, "enUS SharedMedia font")
local lowCyr = "fonts\\frizqt___cyr.ttf"
CheckFaces(E.GetFontFamily(lowCyr, 12, "", true), lowCyr, lowCyr, KO, ZHCN, ZHTW, "enUS Cyrillic Friz, lower case")
local slashCyr = "Fonts/FRIZQT___CYR.TTF"
CheckFaces(E.GetFontFamily(slashCyr, 12, "", true), slashCyr, slashCyr, KO, ZHCN, ZHTW, "enUS Cyrillic Friz, slashes")
local caps = MEDIA .. "fonts\\Expressway CAPS.ttf"
CheckFaces(E.GetFontFamily(caps, 12, "", true), caps, caps, KO, ZHCN, ZHTW, "enUS Expressway CAPS")

local function CheckShadow(obj, on, what)
    local c, o = obj._shadowColor, obj._shadowOffset
    assert(c and o, what .. ": no shadow set")
    if on then
        assert(c[1] == 0 and c[2] == 0 and c[3] == 0 and c[4] == 1 and o[1] == 1 and o[2] == -1, what .. ": no shadow")
    else
        assert(c[4] == 0 and o[1] == 0 and o[2] == 0, what .. ": a shadow")
    end
end
CheckShadow(fam, true, "shadowed family")
CheckShadow(keys[3], false, "plain family")
for _, a in ipairs(ALPHABETS) do
    CheckShadow(fam._members[a], true, "shadowed member " .. a)
    CheckShadow(keys[3]._members[a], false, "plain member " .. a)
    local m = fam._members[a]
    assert(m._color == nil and m._justifyH == nil and E._fontFamilySet[m], "a member defines more than its font")
end
assert(fam._color == nil and fam._justifyH == nil and fam._justifyV == nil,
    "a family defines a text colour or justification")
assert(E._fontFamilySet[fam], "a family is not in the set the passes skip")

E = Load("ruRU")
CheckFaces(E.GetFontFamily(POP, 12, "", false), POP, POP, KO, ZHCN, ZHTW, "ruRU Poppins")
CheckFaces(E.GetFontFamily(FRIZ, 12, "", false), FRIZ, FRIZ, KO, ZHCN, ZHTW, "ruRU Friz")
E = Load("zhCN")
CheckFaces(E.GetFontFamily(EXP, 12, "", false), EXP, EXP, KO, EXP, ZHTW, "zhCN Expressway")
CheckFaces(E.GetFontFamily(ZHCN, 12, "", false), ZHCN, CYR, KO, ZHCN, ZHTW, "zhCN system font")
E = Load("koKR")
CheckFaces(E.GetFontFamily(KO, 12, "", false), KO, CYR, KO, ZHCN, ZHTW, "koKR system font")
CheckFaces(E.GetFontFamily(EXP, 12, "", false), EXP, EXP, EXP, ZHCN, ZHTW, "koKR Expressway")
E = Load("zhTW")
CheckFaces(E.GetFontFamily(ZHTW, 12, "", false), ZHTW, CYR, KO, ZHCN, ZHTW, "zhTW system font")
CheckFaces(E.GetFontFamily(POP, 12, "", false), POP, CYR, KO, ZHCN, POP, "zhTW Poppins")

-------------------------------------------------------------------------------
--  3. SetFontFamily: what a string draws, set once, first switch keeps the
--     string's colour and justification
-------------------------------------------------------------------------------
E = Load("enUS")
local fs = NewFontString()
E.SetFontFamily(fs, POP, 14, "OUTLINE", false)
local face, size, flags, shadow = fs:Draw(LATIN)
assert(face == POP and size == 14 and flags == "OUTLINE" and shadow == 0, "Latin text left the chosen font")
face, size, flags = fs:Draw(CYRILLIC)
assert(face == CYR and size == 14 and flags == "OUTLINE", "Cyrillic text did not take Blizzard's Cyrillic face")
assert(fs:Draw(LATIN .. " " .. CYRILLIC) == CYR, "mixed text is not drawn whole by the russian member")
assert(fs:Draw(HANGUL) == KO, "Korean text did not take Blizzard's Korean face")
local shFs = NewFontString()
E.SetFontFamily(shFs, EXP, 12, "", true)
assert(select(4, shFs:Draw(LATIN)) == 1 and select(4, shFs:Draw(CYRILLIC)) == 1, "the family's shadow does not draw")
assert(shFs:Draw(CYRILLIC) == EXP, "a Cyrillic font's own Cyrillic was replaced")

-- the same family is not set again
T.setFontObject, T.reads = 0, 0
E.SetFontFamily(fs, POP, 14, "OUTLINE", false)
E.SetFontFamily(fs, POP, 14, "OUTLINE", nil)
assert(T.setFontObject == 0 and T.reads == 0, "SetFontObject ran again for the family the string has")
-- a new key switches family to family without reading the string again
E.SetFontFamily(fs, POP, 15, "OUTLINE", false)
assert(T.setFontObject == 1 and T.reads == 0 and fs._obj == E.GetFontFamily(POP, 15, "OUTLINE", false),
    "a family to family switch")

-- first switch from a template: the string's explicit colour and justification stay
local template = StubCreateFont("GameFontTemplateTest")
template:SetTextColor(1, 0.82, 0, 1)
template:SetJustifyH("CENTER")
local tfs = NewFontString(template)
assert(tfs._color[2] == 0.82, "the template's colour did not reach the string")
tfs:SetTextColor(1, 0, 0, 1)
tfs:SetJustifyH("LEFT")
tfs:SetJustifyV("TOP")
tfs._log = {}
T.reads = 0
E.SetFontFamily(tfs, EXP, 12, "", true)
local c = tfs._color
assert(c[1] == 1 and c[2] == 0 and c[3] == 0 and c[4] == 1, "the first switch lost the string's colour")
assert(tfs._justifyH == "LEFT" and tfs._justifyV == "TOP", "the first switch lost the string's justification")
assert(T.reads == 2, "the first switch did not read the string's colour and justification")
assert(tfs._log[1] == "SetFontObject" and tfs._log[2] == "SetJustifyH" and tfs._log[3] == "SetJustifyV"
    and tfs._log[4] == "SetTextColor", "the first switch did not set them back after SetFontObject")
-- a string that took its colour from the template keeps it too
local gfs = NewFontString(template)
E.SetFontFamily(gfs, EXP, 12, "", true)
assert(gfs._color[2] == 0.82 and gfs._justifyH == "CENTER", "a template string lost its colour")
-- a colour getter that returns nothing: nothing is set back (the restore tests the
-- values with type() only, since a getter may hand back secret values)
local nfs = NewFontString(template)
nfs.GetTextColor = function() end
nfs._log = {}
E.SetFontFamily(nfs, EXP, 12, "", true)
for i = 1, #nfs._log do
    assert(nfs._log[i] ~= "SetTextColor", "a string with no colour had one set back")
end
assert(nfs._obj == E.GetFontFamily(EXP, 12, "", true), "a string with no colour did not take its family")

-- the pin: a plain SetFont first keeps its face, whatever comes after (why the family
-- is a string's first font write and every later one goes through SetFontFamily)
local pinned = NewFontString()
pinned:SetFont(POP, 12, "")
E.SetFontFamily(pinned, POP, 12, "", false)
assert(pinned:Draw(CYRILLIC) == POP, "the stub lost the SetFont pin")
local stray = NewFontString()
E.SetFontFamily(stray, POP, 12, "", false)
assert(stray:Draw(CYRILLIC) == CYR)
E.ApplyModuleFont(stray, POP, 12, nil, "")
assert(stray:Draw(CYRILLIC) == POP, "the stub lost the SetFont pin")

-- ApplyModuleFontFamily: ApplyModuleFont's defaults
E = Load("enUS", { db = { fonts = { global = "Poppins", outlineMode = "shadow" } } })
local mfs = NewFontString()
E.ApplyModuleFontFamily(mfs, nil, 12, "unitFrames")
assert(mfs._obj == E.GetFontFamily(POP, 12, "", true), "the module font, no outline, shadow")
E.ApplyModuleFontFamily(mfs, EXP, 11, "unitFrames", "OUTLINE")
assert(mfs._obj == E.GetFontFamily(EXP, 11, "OUTLINE", false), "a given path and flags, no shadow")
EllesmereUIDB.fonts.outlineMode = "outline"
E.InvalidateFontCache()
E.ApplyModuleFontFamily(mfs, nil, 11, "unitFrames")
assert(mfs._obj == E.GetFontFamily(POP, 11, "OUTLINE, SLUG", false), "the module outline")
assert(mfs._pin == nil, "ApplyModuleFontFamily pinned the string")

-------------------------------------------------------------------------------
--  4. No families: today's path; a failed creation is never retried
-------------------------------------------------------------------------------
E = Load("enUS", { noFamilies = true })
assert(E.GetFontFamily(EXP, 12, "", true) == nil and E.GetFontFamily(EXP, 12, "", true) == nil)
local nfs = NewFontString()
E.SetFontFamily(nfs, EXP, 12, "", true)
assert(nfs._obj == _G.EllesmereUIShadowFont and nfs._pin[1] == EXP and nfs._pin[2] == 12 and nfs._pin[3] == "",
    "no families: PrimeFontShadow then SetFont")
E.SetFontFamily(nfs, POP, 13, "OUTLINE", false)
assert(nfs._obj == _G.EllesmereUINoShadowFont and nfs._pin[1] == POP and nfs._pin[3] == "OUTLINE")

E = Load("enUS", { failFamilies = true })
assert(E.GetFontFamily(EXP, 12, "", true) == nil and T.created == 1)
assert(E.GetFontFamily(EXP, 12, "", true) == nil and T.created == 1, "a failed family was tried again")
local ffs = NewFontString()
E.SetFontFamily(ffs, EXP, 12, "", true)
assert(T.created == 1 and ffs._pin[1] == EXP and ffs._obj == _G.EllesmereUIShadowFont)

-------------------------------------------------------------------------------
--  5. A path the client cannot load takes the standard font. Until the loading
--     screen after the first failure ends, a failure is not kept (a fresh game
--     start can fail a file the client has not read yet): each new key tests it
--     again and the login events retest it; from then on it is kept, tested once
-------------------------------------------------------------------------------
E = Load("enUS")
local bad = E.GetFontFamily(BAD, 12, "", false)
CheckFaces(bad, FRIZ, CYR, KO, ZHCN, ZHTW, "missing file")
local bad14 = E.GetFontFamily(BAD, 14, "OUTLINE", true)
E.GetFontFamily(EXP, 12, "", false)
E.GetFontFamily(EXP, 16, "", false)
assert(T.probe[BAD] == 2 and T.probe[EXP] == 1, "before login: a failure is tested per key, a success once")
assert(E._fontPathPending[BAD] and E._fontPathOK[BAD] == nil and E._fontPathOK[EXP] == true,
    "a failure before login was kept, or a success was not")
assert(#E._fontFamPending == 2 and Listening() == 3, "the two families or the three login events are not queued")
Fire("PLAYER_LOGIN")
Fire("PLAYER_ENTERING_WORLD")
assert(T.probe[BAD] == 4 and E._fontPathPending[BAD] and E._fontRetryDone == nil,
    "the login events did not retest the path, or closed the window early")
CheckFaces(bad, FRIZ, CYR, KO, ZHCN, ZHTW, "missing file after the login events")
Fire("LOADING_SCREEN_DISABLED")
assert(T.probe[BAD] == 5 and E._fontPathOK[BAD] == false and E._fontRetryDone == true,
    "the loading screen's end did not settle the path")
assert(next(E._fontPathPending) == nil and #E._fontFamPending == 0 and Listening() == 0,
    "the retry outlived the loading screen")
CheckFaces(bad14, FRIZ, CYR, KO, ZHCN, ZHTW, "missing file, settled")
E.GetFontFamily(BAD, 15, "", false)
assert(T.probe[BAD] == 5, "a path was tested again after the loading screen")
-- a failure after that is kept at once
local LATE = "Interface\\AddOns\\Missing\\Late.ttf"
BADFILES[LATE] = true
E.GetFontFamily(LATE, 12, "", false)
E.GetFontFamily(LATE, 13, "", false)
assert(T.probe[LATE] == 1 and E._fontPathOK[LATE] == false and Listening() == 0,
    "a failure after the loading screen was retested")
E._clientFontPath = "Fonts\\ARIALN.TTF"
CheckFaces(E.GetFontFamily(BAD, 9, "", false), "Fonts\\ARIALN.TTF", CYR, KO, ZHCN, ZHTW, "missing file, client font")
E._clientFontPath = nil

-------------------------------------------------------------------------------
--  5b. A file the client reads only after the first test (a fresh game start)
--      goes into the families built without it at the login event that finds
--      it, member by member and as their own font, so their strings update in
--      place
-------------------------------------------------------------------------------
E = Load("enUS")
BADFILES[EXP] = true
local early = E.GetFontFamily(EXP, 12, "", true)
local early14 = E.GetFontFamily(EXP, 14, "OUTLINE", false)
CheckFaces(early, FRIZ, CYR, KO, ZHCN, ZHTW, "an unread file before login")
assert(early._face == FRIZ, "the fallen-back family's own font")
local efs = NewFontString()
E.SetFontFamily(efs, EXP, 12, "", true)
assert(efs:Draw(LATIN) == FRIZ and efs._obj == early)
BADFILES[EXP] = nil                       -- the client has read the file now
Fire("PLAYER_LOGIN")
CheckFaces(early, EXP, EXP, KO, ZHCN, ZHTW, "the unread file at PLAYER_LOGIN")
CheckFaces(early14, EXP, EXP, KO, ZHCN, ZHTW, "the unread file at PLAYER_LOGIN, second key")
local r14 = early14._members.roman
assert(r14._size == 14 and r14._flags == "OUTLINE", "a patched member lost its size or flags")
assert(early._face == EXP and early._size == 12 and early._flags == "", "the family's own font did not follow")
assert(efs._obj == early and efs:Draw(LATIN) == EXP and efs:Draw(CYRILLIC) == EXP,
    "the string did not take the file in place")
assert(E._fontPathOK[EXP] == true and E._fontPathPending[EXP] == nil and #E._fontFamPending == 0,
    "the loaded path is still pending")
local probes = T.probe[EXP]
CheckFaces(E.GetFontFamily(EXP, 16, "", false), EXP, EXP, KO, ZHCN, ZHTW, "a key built after the retest")
assert(T.probe[EXP] == probes, "a loaded path was tested again")
Fire("PLAYER_ENTERING_WORLD")
assert(Listening() == 3 and E._fontRetryDone == nil, "the window closed before the loading screen's end")
Fire("LOADING_SCREEN_DISABLED")
assert(Listening() == 0 and E._fontRetryDone == true, "the retry did not stand down at the loading screen's end")

-- the client's own CJK alphabet takes the path, a path without Cyrillic leaves the
-- russian member alone, and a file read only by PLAYER_ENTERING_WORLD
E = Load("koKR")
BADFILES[POP] = true
local kf = E.GetFontFamily(POP, 12, "", false)
CheckFaces(kf, FRIZ, CYR, FRIZ, ZHCN, ZHTW, "koKR, an unread file before login")
Fire("PLAYER_LOGIN")
CheckFaces(kf, FRIZ, CYR, FRIZ, ZHCN, ZHTW, "koKR, still unread at PLAYER_LOGIN")
BADFILES[POP] = nil
Fire("PLAYER_ENTERING_WORLD")
CheckFaces(kf, POP, CYR, POP, ZHCN, ZHTW, "koKR, read by PLAYER_ENTERING_WORLD")
Fire("LOADING_SCREEN_DISABLED")
assert(Listening() == 0 and E._fontPathOK[POP] == true, "koKR: the retry did not settle")

-------------------------------------------------------------------------------
--  6. SetFontObjectFace on a Blizzard family and on a plain object; snapshots
-------------------------------------------------------------------------------
local function CheckMember(obj, alphabet, face, size, flags, what)
    local m = obj._members and obj._members[alphabet] or obj
    assert(m._face == face, what .. ": " .. alphabet .. " face " .. tostring(m._face))
    assert(Near(m._size, size), what .. ": " .. alphabet .. " size " .. tostring(m._size))
    assert(m._flags == flags, what .. ": " .. alphabet .. " flags " .. tostring(m._flags))
end

E = Load("enUS")
local blz = BlizzardFamily("SystemFont_FaceTest", StockSpec())
local snap = E.SnapshotFontObject(blz)
E.SetFontObjectFace(blz, POP, nil, nil, 1.5)
CheckMember(blz, "roman", POP, 18, "", "Poppins x1.5")
CheckMember(blz, "russian", CYR, 18, "", "Poppins x1.5")
CheckMember(blz, "korean", KO, 16.5, "", "Poppins x1.5")
CheckMember(blz, "simplifiedchinese", ZHCN, 19.5, "", "Poppins x1.5")
CheckMember(blz, "traditionalchinese", ZHTW, 19.5, "OUTLINE", "Poppins x1.5")
-- the family's own font (what GetFont reads and copies take) follows: the client's alphabet takes the face
local function CheckOwn(obj, face, size, flags, what)
    assert(obj._face == face and Near(obj._size, size) and obj._flags == flags, what .. ": the own font is "
        .. tostring(obj._face) .. " " .. tostring(obj._size) .. " " .. tostring(obj._flags))
end
CheckOwn(blz, POP, 18, "", "Poppins x1.5")
assert(snap.own and snap.own.face == FRIZ and snap.own.size == 12, "the snapshot lacks the own font")
E.RestoreFontObject(blz, snap)
for _, a in ipairs(ALPHABETS) do
    local s = StockSpec()[a]
    CheckMember(blz, a, s[1], s[2], s[3], "restored")
end
CheckOwn(blz, FRIZ, 12, "", "restored")
E.SetFontObjectFace(blz, EXP, nil, nil, nil)
CheckMember(blz, "roman", EXP, 12, "", "Expressway")
CheckMember(blz, "russian", EXP, 12, "", "Expressway")
CheckMember(blz, "korean", KO, 11, "", "Expressway")
CheckOwn(blz, EXP, 12, "", "Expressway")
E.SetFontObjectFace(blz, nil, 10, "OUTLINE", 3)
CheckMember(blz, "roman", EXP, 10, "OUTLINE", "size and flags")
CheckMember(blz, "russian", EXP, 10, "OUTLINE", "size and flags")
CheckMember(blz, "korean", KO, 10, "OUTLINE", "size and flags")
CheckMember(blz, "traditionalchinese", ZHTW, 10, "OUTLINE", "size and flags")
CheckOwn(blz, EXP, 10, "OUTLINE", "size and flags")
E.RestoreFontObject(blz, snap)
CheckMember(blz, "traditionalchinese", ZHTW, 13, "OUTLINE", "restored again")
CheckOwn(blz, FRIZ, 12, "", "restored again")

local plain = StubCreateFont("GameFontPlainFaceTest")
plain:SetFont(FRIZ, 10, "OUTLINE")
local psnap = E.SnapshotFontObject(plain)
assert(psnap.plain and psnap.plain.face == FRIZ, "a plain object's snapshot")
E.SetFontObjectFace(plain, POP, nil, nil, 2)
CheckMember(plain, "roman", POP, 20, "OUTLINE", "plain Poppins x2")
E.SetFontObjectFace(plain, nil, 14, "")
CheckMember(plain, "roman", POP, 14, "", "plain size and flags")
E.RestoreFontObject(plain, psnap)
CheckMember(plain, "roman", FRIZ, 10, "OUTLINE", "plain restored")

-- a member two alphabets share scales once
local shared = NewFont(FRIZ, 12, "")
local hanzi = NewFont(ZHCN, 10, "")
shared._members = { roman = NewFont(FRIZ, 12, ""), russian = NewFont(CYR, 12, ""), korean = hanzi,
    simplifiedchinese = hanzi, traditionalchinese = NewFont(ZHTW, 12, "") }
E.SetFontObjectFace(shared, nil, nil, nil, 2)
assert(hanzi._size == 20, "a shared member scaled twice: " .. hanzi._size)
E.SetFontObjectFace(shared, nil, nil, nil, 2)
assert(hanzi._size == 40, "a second call is a new call")

-- the client's own alphabets take the path
E = Load("zhCN")
blz = BlizzardFamily("SystemFont_FaceTestCN", StockSpec())
E.SetFontObjectFace(blz, POP, nil, nil, nil)
CheckMember(blz, "simplifiedchinese", POP, 13, "", "zhCN")
CheckMember(blz, "russian", CYR, 12, "", "zhCN")
CheckMember(blz, "traditionalchinese", ZHTW, 13, "OUTLINE", "zhCN")
CheckOwn(blz, POP, 12, "", "zhCN")
E = Load("ruRU")
blz = BlizzardFamily("SystemFont_FaceTestRU", StockSpec())
E.SetFontObjectFace(blz, POP, nil, nil, nil)
CheckMember(blz, "russian", POP, 12, "", "ruRU")
CheckMember(blz, "korean", KO, 11, "", "ruRU")
CheckOwn(blz, POP, 12, "", "ruRU")

-------------------------------------------------------------------------------
--  7. The game text passes: our families skipped, Blizzard's member by member
-------------------------------------------------------------------------------
E = Load("enUS", {
    db = { fonts = { global = "Poppins", outlineMode = "outline", applyToAllGameText = true, gameTextScale = 110 } },
    loaded = { EllesmereUIBlizzardSkin = true },
})
local ours = E.GetFontFamily(EXP, 12, "", true)
Register("EUIMemberAlias", ours._members.russian)
blz = BlizzardFamily("SystemFont_PassTest", StockSpec())
-- an object whose alphabets answer its parent's members
local child = NewFont(FRIZ, 12, "")
child._members = blz._members
Register("GameFontChildPassTest", child)
plain = StubCreateFont("GameFontPlainPassTest")
plain:SetFont(FRIZ, 10, "")
E.ApplyGlobalFontToGameText()
assert(STANDARD_TEXT_FONT == POP and E._clientFontPath == FRIZ, "Apply to All Game Text did not set the standard font")
CheckMember(blz, "roman", POP, 13.2, "", "game text pass")
CheckMember(blz, "russian", CYR, 13.2, "", "game text pass")
CheckMember(blz, "korean", KO, 12.1, "", "game text pass")
CheckMember(blz, "traditionalchinese", ZHTW, 14.3, "OUTLINE", "game text pass")
CheckOwn(blz, POP, 13.2, "", "game text pass")
CheckOwn(child, POP, 13.2, "", "game text pass, an object on its parent's members")
CheckMember(plain, "roman", POP, 11, "", "game text pass, plain")
for _, a in ipairs(ALPHABETS) do
    local m = ours._members[a]
    assert(m._size == 12 and m._flags == "", "the game text pass reached our family: " .. a)
end
CheckFaces(ours, EXP, EXP, KO, ZHCN, ZHTW, "our family after the game text pass")

-- scale only: every face kept
E = Load("enUS", { db = { fonts = { global = "Poppins", gameTextScale = 120 } } })
blz = BlizzardFamily("SystemFont_ScaleTest", StockSpec())
E.ApplyGlobalFontToGameText()
assert(STANDARD_TEXT_FONT == FRIZ, "scale alone set the standard font")
CheckMember(blz, "roman", FRIZ, 14.4, "", "scale only")
CheckMember(blz, "korean", KO, 13.2, "", "scale only")
CheckOwn(blz, FRIZ, 14.4, "", "scale only")

-- the module failsafe: face and outline member by member, sizes kept, ours skipped
E = Load("enUS", {
    db = { fonts = { global = "Poppins", outlineMode = "outline" } },
    loaded = { EllesmereUIBlizzardSkin = true },
})
ours = E.GetFontFamily(EXP, 12, "", true)
GameTooltipText = BlizzardFamily(nil, StockSpec())
GameTooltipHeaderText = NewFont(FRIZ, 14, "")
GameTooltipTextSmall = ours
E.ApplyModuleFontFailsafe()
CheckMember(GameTooltipText, "roman", POP, 12, "OUTLINE, SLUG", "failsafe")
CheckMember(GameTooltipText, "russian", CYR, 12, "OUTLINE, SLUG", "failsafe")
CheckMember(GameTooltipText, "korean", KO, 11, "OUTLINE, SLUG", "failsafe")
CheckOwn(GameTooltipText, POP, 12, "OUTLINE, SLUG", "failsafe")
CheckMember(GameTooltipHeaderText, "roman", POP, 14, "OUTLINE, SLUG", "failsafe, plain")
for _, a in ipairs(ALPHABETS) do
    local m = ours._members[a]
    assert(m._flags == "" and m._size == 12, "the failsafe reached our family: " .. a)
end
GameTooltipText, GameTooltipHeaderText, GameTooltipTextSmall = nil, nil, nil

print("font family harness: ok")
