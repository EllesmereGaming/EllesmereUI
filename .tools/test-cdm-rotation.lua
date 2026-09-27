-- Run from the repository root with Lua 5.1.
-- Exercise the existing recommendation renderer and the options entry point.
local checks = 0
local function eq(a, b, label)
    assert(a == b, label .. ": expected " .. tostring(b) .. ", got " .. tostring(a))
    checks = checks + 1
end
local function read(path)
    local f = assert(io.open(path)); local s = f:read("*a"); f:close(); return s
end
local profile = { cdmBars = {} }
local cvar, writes, updates = false, 0, 0
function GetCVarBool(name) eq(name, "assistedCombatHighlight", "highlight CVar read"); return cvar end
function SetCVar(name, value)
    eq(name, "assistedCombatHighlight", "only highlight CVar written")
    eq(value, "1", "only opt-in enables Blizzard highlight")
    cvar = true; writes = writes + 1
end
function DB() return profile end
local ns = { UpdateRotationHighlights = function() updates = updates + 1 end }
local source = read("EllesmereUIOptions/EUI_CooldownManager_Options.lua")
local optionSource = assert(source:match('({ type="toggle", text="Show Rotation Helper",.-end %})%);'))
local optionEnv = setmetatable({ ns = ns }, { __index = _G })
local optionLoader = assert(loadstring("return " .. optionSource))
setfenv(optionLoader, optionEnv)
local option = optionLoader()
eq(writes, 0, "opening options changes nothing")
eq(option.getValue(), false, "disabled remains disabled")
option.setValue(true)
eq(option.getValue(), true, "explicit enable")
eq(profile.cdmBars.hideRotationHelper, false, "clear old suppression flag")
eq(writes, 1, "single CVar write on opt-in")
option.setValue(false)
eq(option.getValue(), false, "disable CDM helper")
eq(cvar, true, "disable preserves Blizzard action bar preference")
eq(writes, 1, "disable writes no global CVar")
eq(updates, 2, "settings request renderer refresh")
profile.cdmBars.hideRotationHelper = nil

-- Load just the production rotation block with public display-only mocks.
source = read("EllesmereUICooldownManager/EllesmereUICooldownManager.lua")
local first = assert(source:find("do\nns._rotationGlowedIcons", 1, true))
local last = assert(source:find('-- Show Item Count "Out of Combat" mode:', first, true))
local block = source:sub(first, last - 1)
local frames = {}
local function newFrame()
    local f = { shown = false, scripts = {}, level = 0 }
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown end
    function f:SetScript(name, fn) self.scripts[name] = fn end
    function f:SetFrameLevel(v) self.level = v end
    function f:GetFrameLevel() return self.level end
    function f:GetWidth() return 36 end
    function f:GetHeight() return 36 end
    function f:SetAllPoints() end
    frames[#frames + 1] = f
    return f
end
local icon = newFrame(); icon:Show()
local frameCache = { [icon] = { spellID = 100 } }
local suggestion = 100
local secret = {}
local env = setmetatable({
    ns = ns,
    ECME = { db = { profile = profile } },
    _ecmeFC = frameCache,
    FC = function(f) return frameCache[f] end,
    cdmBarIcons = { main = { icon } },
    CreateFrame = newFrame,
    C_AssistedCombat = { GetNextCastSpell = function() return suggestion end },
    C_Spell = { GetBaseSpell = function(id)
        assert(id > 0, "items must not enter spell resolver")
        return id == 200 and 100 or id
    end },
    issecretvalue = function(value) return value == secret end,
    -- Casting/secure-action APIs deliberately absent.
}, { __index = _G })
local loader = assert(loadstring(block)); setfenv(loader, env); loader()
local dirty = frames[#frames]
local function flush()
    ns.UpdateRotationHighlights()
    eq(dirty.shown, true, "recommendation refresh queued")
    dirty.scripts.OnUpdate(dirty)
    eq(dirty.shown, false, "one-shot refresh stops")
end
flush()
local highlight = frameCache[icon].rotationHighlight
eq(highlight.shown, true, "recommended normal spell highlighted")
suggestion = 200; flush()
eq(highlight.shown, true, "override recommendation matches base icon")
frameCache[icon].spellID = 200; suggestion = 100; flush()
eq(highlight.shown, true, "base recommendation matches override icon")
suggestion = nil; flush()
eq(highlight.shown, false, "no recommendation clears old highlight")
suggestion = secret; flush()
eq(highlight.shown, false, "restricted recommendation is ignored")
suggestion = 100; frameCache[icon].spellID = -13; flush()
eq(highlight.shown, false, "trinkets do not become recommended spells")
frameCache[icon].spellID = 100; icon:Hide(); flush()
eq(highlight.shown, false, "hidden icon is not highlighted")
icon:Show(); flush()
eq(highlight.shown, true, "visible matching icon highlighted again")
frameCache[icon].spellID = 300; flush()
eq(highlight.shown, false, "recycled icon clears stale highlight")
frameCache[icon].spellID = 100; flush()
cvar = false; flush()
eq(highlight.shown, false, "Blizzard highlight disabled clears CDM")
cvar = true; profile.cdmBars.hideRotationHelper = true; flush()
eq(highlight.shown, false, "CDM suppression remains supported")
print("PASS: " .. checks .. " rotation checks")
