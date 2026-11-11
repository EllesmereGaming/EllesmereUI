-- Stub harness: loads the Unit Frames portrait file outside the game and
-- checks the portrait painter against a unit whose identity the game
-- withholds (an enemy inside an instance). A model refuses such a unit, so
-- the painter must never hand it one: the unit's 2D portrait stands in, and
-- the model comes back with the next unit it can show.
--   lua .tools/tests/test_uf_portrait_identity.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return src
end
local SRC = ReadSource("EllesmereUIUnitFrames/EUI_UnitFrames_Portrait.lua")

-- The widget methods the file calls: a mock answers those, and any other
-- field that was never set reads nil, as on a real frame
local METHODS = {}
for name in SRC:gmatch(":([%a_][%w_]*)%s*%(") do METHODS[name] = true end

-------------------------------------------------------------------------------
--  Game API stubs
-------------------------------------------------------------------------------
local T = {
    hidden = {},        -- unit -> true: the game withholds its identity
    guid = {},          -- unit -> guid
    player = {},        -- unit -> true: a player
    available = true,   -- connected and visible
    setUnit = 0, cleared = 0, qmark = 0, painted2d = 0,
}
local SECRET = {}

local function MakeObj(kind, parent)
    local o = { _kind = kind, _parent = parent, _shown = true, _scripts = {} }
    setmetatable(o, { __index = function(_, k)
        if type(k) ~= "string" or k:sub(1, 1) == "_" then return nil end
        if k == "Show" then return function(self) self._shown = true end end
        if k == "Hide" then return function(self) self._shown = false end end
        if k == "SetShown" then return function(self, v) self._shown = v and true or false end end
        if k == "IsShown" then return function(self) return self._shown end end
        if k == "IsObjectType" then return function(self, t) return self._kind == t end end
        if k == "CreateTexture" then return function(self) return MakeObj("Texture", self) end end
        if k == "CreateMaskTexture" then return function(self) return MakeObj("MaskTexture", self) end end
        if k == "GetFrameLevel" then return function() return 1 end end
        if k == "GetFrameStrata" then return function() return "MEDIUM" end end
        if k == "GetWidth" or k == "GetHeight" then return function() return 46 end end
        if k == "GetAlpha" then return function() return 1 end end
        if k == "GetAttribute" then return function(self, name) return self["_attr_" .. name] end end
        if k == "HookScript" then return function(self, name, fn) self._scripts[name] = fn end end
        -- The model: the game refuses a unit whose identity it withholds
        if k == "SetUnit" then
            return function(self, unit)
                assert(not T.hidden[unit], "a model was handed a unit whose identity is withheld: " .. tostring(unit))
                T.setUnit = T.setUnit + 1
                self._unit = unit
                return true
            end
        end
        if k == "ClearModel" then return function(self) T.cleared = T.cleared + 1; self._unit = nil end end
        if k == "SetModel" then return function(self) T.qmark = T.qmark + 1; self._unit = "?" end end
        if k == "GetModelFileID" then return function(self) return self._unit and 118355 or nil end end
        if METHODS[k] then return function() end end
        return nil
    end })
    return o
end

issecretvalue = function(v) return v == SECRET end
C_Secrets = { ShouldUnitIdentityBeSecret = function(unit) return T.hidden[unit] == true end }
CreateFrame = function(kind, _, parent) return MakeObj(kind, parent) end
UnitExists = function() return true end
UnitIsConnected = function() return T.available end
UnitIsVisible = function() return T.available end
UnitGUID = function(unit) return T.guid[unit] end
UnitIsPlayer = function(unit) return T.player[unit] == true end
UnitClass = function() return "Mage", "MAGE" end
GetRaidTargetIndex = function() return nil end
SetPortraitTexture = function(tex, unit)
    T.painted2d = T.painted2d + 1
    tex._portraitOf = unit
end

EllesmereUI = {
    _Pool = {},
    PP = { Point = function() end, Size = function() end, mult = 1 },
    CLASS_ICON_SPRITE_COORDS = { MAGE = { 0, 0.25, 0, 0.25 } },
    SHAPE_MASKS = {}, SHAPE_BORDERS = {}, SHAPE_INSETS = {},
    UIScaledAlpha = function(a) return a end,
    OnUIAlphaChanged = function() end,
}

local painters = {}
local profile = {}
local db = { profile = profile }
local ns = {
    _internals = {
        frames = {}, dbSetters = {},
        UnsnapTex = function() end,
        GetSettingsForUnit = function(unit) return profile[unit] end,
        UnitToSettingsKey = function(unit) return unit end,
    },
    Engine = {
        SetPainter = function(channel, fn) painters[channel] = fn end,
        ElementOn = function() return true end,
    },
    UF_Blizz = function() return false end,
    UF_DarkThemeOn = function() return false end,
}

local chunk = assert(loadstring(SRC, "=EUI_UnitFrames_Portrait.lua"))
chunk("EllesmereUIUnitFrames", ns)
for _, set in ipairs(ns._internals.dbSetters) do set(db) end
local paint = assert(painters.portrait, "the portrait painter was not registered")
local CreatePortrait = assert(ns._internals.CreatePortrait)

-- A unit frame with its portrait built by the file itself
local function NewFrame(unit, settings)
    profile[unit] = settings
    local frame = MakeObj("Button")
    frame._euiUnit, frame._euiBaseUnit = unit, unit
    frame.Health = MakeObj("StatusBar", frame)
    frame.Portrait = CreatePortrait(frame, "right", 46, unit)
    return frame, frame.Portrait.backdrop
end

local function Target(frame, guid, opts)
    opts = opts or {}
    local unit = frame._euiUnit
    T.guid[unit] = guid
    T.hidden[unit] = opts.hidden or nil
    T.player[unit] = opts.player or nil
    T.available = opts.available ~= false
    paint(frame, unit, "PLAYER_TARGET_CHANGED")
end

-------------------------------------------------------------------------------
-- 1. a 3D portrait: a readable unit takes the model
-------------------------------------------------------------------------------
local frame, bd = NewFrame("target", { portraitMode = "3d", portraitMirror = true })
local model, tex2D = bd._3d, bd._2d
assert(frame.Portrait == model and model:IsObjectType("PlayerModel"), "3D mode did not build the model")
Target(frame, "Creature-1")
assert(T.setUnit == 1 and model._unit == "target" and model:IsShown() and not tex2D:IsShown(),
    "a readable unit did not take the model")

-- 2. a unit whose identity is withheld: no model call, its 2D portrait stands in
local before = T.setUnit
Target(frame, "Creature-2", { hidden = true })
assert(T.setUnit == before, "the model was set for a withheld unit")
assert(not model:IsShown() and model._unit == nil, "the model stayed up for a withheld unit")
assert(tex2D:IsShown() and tex2D._portraitOf == "target", "the 2D portrait did not stand in")
assert(frame.Portrait == model, "the frame's portrait object changed")

-- 3. the same withheld unit again: a plain guid that did not change repaints
--    nothing; a secret guid always repaints, still with no model call
local painted = T.painted2d
paint(frame, "target", "UNIT_PORTRAIT_UPDATE")
assert(T.painted2d == painted + 1, "a portrait update did not repaint the stand-in")
T.guid.target = SECRET
paint(frame, "target", "PLAYER_TARGET_CHANGED")
paint(frame, "target", "Show")
assert(T.setUnit == before and tex2D:IsShown() and not model:IsShown(), "a secret guid brought the model back")

-- 4. the next readable unit: the model is back, the stand-in is gone
Target(frame, "Creature-3")
assert(T.setUnit == before + 1 and model:IsShown() and model._unit == "target" and not tex2D:IsShown(),
    "the model did not come back for a readable unit")

-- 5. a withheld unit that is not available keeps the question mark model
local marks = T.qmark
Target(frame, "Creature-4", { hidden = true, available = false })
assert(T.qmark == marks + 1 and model:IsShown() and not tex2D:IsShown(), "an unavailable unit lost its question mark")
assert(T.setUnit == before + 1)

-------------------------------------------------------------------------------
-- 6. a 2D portrait with Mirror Portrait: the mirror lookup loads the unit
--    into a hidden model, which a withheld unit must never reach
-------------------------------------------------------------------------------
local frame2, bd2 = NewFrame("focus", { portraitMode = "2d", portraitMirror = true })
assert(frame2.Portrait == bd2._2d, "2D mode did not take the texture")
local set = T.setUnit
Target(frame2, "Creature-5", { hidden = true })
assert(T.setUnit == set, "the mirror lookup set a model for a withheld unit")
assert(bd2._2d:IsShown() and bd2._2d._portraitOf == "focus")
-- a readable unit still runs the lookup
Target(frame2, "Creature-6")
assert(T.setUnit == set + 1, "the mirror lookup no longer runs for a readable unit")

-------------------------------------------------------------------------------
-- 7. class art with a 3D picture for non-players: a withheld non-player gets
--    the 2D stand-in, and a player takes the class art back
-------------------------------------------------------------------------------
local frame3, bd3 = NewFrame("boss1", { portraitMode = "class", portraitNonPlayerOn = true, portraitNonPlayer = "3d" })
assert(frame3.Portrait == bd3._class, "class mode did not take the class texture")
set = T.setUnit
Target(frame3, "Creature-7", { hidden = true })
assert(T.setUnit == set, "the class fallback set a model for a withheld unit")
assert(frame3.Portrait == bd3._3d and not bd3._3d:IsShown() and bd3._2d:IsShown() and not bd3._class:IsShown(),
    "a withheld non-player on class art did not get the 2D stand-in")
Target(frame3, "Player-1", { player = true })
assert(frame3.Portrait == bd3._class and bd3._class:IsShown() and not bd3._2d:IsShown() and not bd3._3d:IsShown(),
    "a player did not take the class art back")
Target(frame3, "Creature-8")
assert(T.setUnit == set + 1 and bd3._3d:IsShown() and not bd3._2d:IsShown() and not bd3._class:IsShown(),
    "a readable non-player on class art did not take the model")

print(("model sets: %d, clears: %d, 2D paints: %d, question marks: %d"):format(T.setUnit, T.cleared, T.painted2d, T.qmark))
print("unit frames portrait identity harness: ok")
