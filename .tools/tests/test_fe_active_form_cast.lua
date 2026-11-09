-- Stub harness: the WoW Forever Active Stance icon (hunter aspects, paladin
-- auras). Loads the real EllesmereUIForeverEssentials_ActiveForm.lua under
-- stubs and drives its events: the buff scan out of combat, the player's own
-- cast standing in while aura data is restricted, the rescan once it lifts, and
-- the events it holds only while shown.
--   lua .tools/tests/test_fe_active_form_cast.lua        (from the repository root)
local TARGET = AF_TARGET or "EllesmereUIForeverEssentials/EllesmereUIForeverEssentials_ActiveForm.lua"

local fails, count = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        print("  FAIL: " .. msg)
    end
end

local fh = assert(io.open(TARGET, "rb"))
local SOURCE = fh:read("*a")
fh:close()

-- world state the stubs read
local restricted, auras, secret, scans, scanFilter, refreshes
local settings, visible, apply, frames

local function NewFrame(name)
    local f = { name = name, events = {}, shown = true, scripts = {} }
    function f:RegisterEvent(e) self.events[e] = true end
    function f:RegisterUnitEvent(e, unit) self.events[e] = unit end
    function f:UnregisterAllEvents() self.events = {} end
    function f:SetScript(k, fn) self.scripts[k] = fn end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown end
    function f:CreateTexture()
        local t = { sets = 0 }
        function t:SetTexture(v) self.texture = v; self.sets = self.sets + 1 end
        function t:SetAllPoints() end
        function t:SetTexCoord() end
        f.tex = t
        return t
    end
    setmetatable(f, { __index = function() return function() end end })
    return f
end

local function Load(class)
    restricted, auras, secret, scans, scanFilter, refreshes = false, {}, {}, 0, nil, 0
    settings, visible, apply, frames = { enabled = true }, true, nil, {}
    EUI_CLIENT_BLOCKED = nil
    EllesmereUI = {
        IS_FOREVER = true,
        IsSecret = function(v) return secret[v] == true end,
        AuraKit = { AurasRestricted = function() return restricted end },
        PP = { SnapForES = function(v) return v end },
        ApplyBorderStyle = function() end,
        BorderPx = function() return 1 end,
        EvalVisibility = function() return visible end,
        RegisterVisibilityUpdater = function() end,
        UnregisterVisibilityUpdater = function() end,
    }
    UIParent = { GetEffectiveScale = function() return 1 end }
    UnitClass = function() return class, class end
    CreateFrame = function(_, name)
        local f = NewFrame(name)
        frames[#frames + 1] = f
        return f
    end
    C_UnitAuras = { GetAuraDataByIndex = function(unit, i, filter)
        -- an index scan is a hard error while aura data is restricted
        assert(not restricted, "the buffs were scanned while aura data is restricted")
        if i == 1 then scans = scans + 1 end
        scanFilter = filter
        return auras[i]
    end }
    C_Spell = { GetSpellTexture = function(id) return "spell:" .. tostring(id) end }
    -- the stance bar holds no aspect; every repaint asks it once
    GetNumShapeshiftForms = function() refreshes = refreshes + 1; return 0 end
    GetShapeshiftFormInfo = function() end
    local module = { Feature = function(_, defaults)
        local F = {}
        F.Read = function() return settings end
        F.Get = function(k) local v = settings[k]; if v == nil then v = defaults[k] end; return v end
        F.Enabled = function() return settings.enabled == true end
        F.Cfg = function() end
        F.Place = function() end
        F.Start = function(fn) apply = fn end
        return F
    end }
    assert(loadstring(SOURCE, "=ActiveForm"))("EllesmereUIForeverEssentials", module)
    apply()
    local ev, icon = frames[1], frames[2]
    local function Fire(event, a1, a2, a3) ev.scripts.OnEvent(ev, event, a1, a2, a3) end
    return ev, icon, Fire
end
local function Aura(id, icon, instance) return { spellId = id, icon = icon, auraInstanceID = instance } end

-------------------------------------------------------------------------------
-- 1. A hunter out of combat: the buff scan, own buffs only
-------------------------------------------------------------------------------
local ev, icon, Fire = Load("HUNTER")
check(ev.events.UNIT_AURA == "player", "UNIT_AURA is heard for the player alone")
check(ev.events.UNIT_SPELLCAST_SUCCEEDED == "player", "the cast event is heard for the player alone")
check(ev.events.PLAYER_REGEN_ENABLED == true and ev.events.PLAYER_ENTERING_WORLD == true, "combat end and loading screens are heard")
check(icon.shown == false, "no aspect: hidden")
auras = { Aura(1459, "int", 5), Aura(13165, "hawk", 11) }
Fire("UNIT_AURA", "player", { addedAuras = { { spellId = 13165 } } })
check(icon.shown and icon.tex.texture == "hawk", "an added aspect shows with the aura's own icon")
check(scanFilter == "HELPFUL|PLAYER", "only the player's own buffs are scanned")
local before = scans
Fire("UNIT_AURA", "player", { addedAuras = { { spellId = 1459 } } })
check(scans == before, "an unrelated aura does not rescan")

-------------------------------------------------------------------------------
-- 2. Out of combat the cast event does nothing: the aura path has it. The
--    order aura-first, then the cast, then a cancel must still hide the icon.
-------------------------------------------------------------------------------
auras = { Aura(13163, "monkey", 12) }
Fire("UNIT_AURA", "player", { addedAuras = { { spellId = 13163 } }, removedAuraInstanceIDs = { 11 } })
check(icon.tex.texture == "monkey", "the new aspect shows")
local sets, paints = icon.tex.sets, refreshes
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 13163)
check(icon.tex.sets == sets and refreshes == paints, "a tracked cast out of combat neither paints nor repaints")
check(icon.tex.texture == "monkey", "the aura's own icon stays")
auras = {}
Fire("UNIT_AURA", "player", { removedAuraInstanceIDs = { 12 } })
check(icon.shown == false, "cancelling the aspect after an aura-first cast hides the icon")

-------------------------------------------------------------------------------
-- 3. In combat (aura data restricted): the player's own cast stands in
-------------------------------------------------------------------------------
auras = { Aura(13165, "hawk", 21) }
Fire("UNIT_AURA", "player", { addedAuras = { { spellId = 13165 } } })
check(icon.tex.texture == "hawk", "hawk before the fight")
restricted = true
before = scans
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-2", 5118)
check(icon.shown and icon.tex.texture == "spell:5118", "a tracked cast in combat shows that spell's icon")
check(scans == before, "no buff scan while restricted")
-- an untracked cast (a hunter's shots fire this event all fight) costs no repaint
paints = refreshes
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-3", 75)
check(refreshes == paints and icon.tex.texture == "spell:5118", "an untracked cast in combat repaints nothing")
-- a spell id the game keeps secret is never looked up
secret[13163] = true
paints = refreshes
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-4", 13163)
check(refreshes == paints and icon.tex.texture == "spell:5118", "a secret spell id is ignored")
secret[13163] = nil
-- a nil spell id is ignored too
check(pcall(Fire, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-5", nil), "a cast with no spell id does not error")
check(icon.tex.texture == "spell:5118", "and changes nothing")
-- an aura event in combat keeps the stand-in (the scan cannot run)
Fire("UNIT_AURA", "player", { isFullUpdate = true })
check(icon.tex.texture == "spell:5118" and scans == before, "an aura event in combat keeps the cast's icon")

-------------------------------------------------------------------------------
-- 4. The restriction lifts: the scan reruns at the first repaint, whatever it is
-------------------------------------------------------------------------------
-- (a) combat end with the aspect up: the aura's own icon and instance take over
restricted = false
auras = { Aura(5118, "cheetah", 22) }
Fire("PLAYER_REGEN_ENABLED")
check(icon.tex.texture == "cheetah", "combat end rescans to the aura's own icon")
auras = {}
Fire("UNIT_AURA", "player", { removedAuraInstanceIDs = { 22 } })
check(icon.shown == false, "its removal out of combat hides the icon")
-- (b) the aspect dropped during the fight (no cast): the first unrestricted
--     repaint of any kind catches up, because the cast marked the scan stale
auras = { Aura(13165, "hawk", 23) }
Fire("UNIT_AURA", "player", { addedAuras = { { spellId = 13165 } } })
restricted = true
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-6", 5118)
check(icon.tex.texture == "spell:5118", "second fight: the cast shows")
restricted = false
auras = {}
Fire("UPDATE_SHAPESHIFT_FORM")
check(icon.shown == false, "the first unrestricted repaint rescans after a cast in combat")
-- (c) a fight with no cast at all: combat end and a loading screen rescan by
--     themselves, since a restricted stretch may have hidden a change
auras = { Aura(13165, "hawk", 24) }
Fire("UNIT_AURA", "player", { addedAuras = { { spellId = 13165 } } })
check(icon.tex.texture == "hawk", "third fight: hawk before it")
restricted = true
auras = {}
restricted = false
Fire("PLAYER_REGEN_ENABLED")
check(icon.shown == false, "combat end rescans with no cast in the fight")
auras = { Aura(13163, "monkey", 25) }
Fire("PLAYER_ENTERING_WORLD")
check(icon.shown and icon.tex.texture == "monkey", "a loading screen rescans")

-------------------------------------------------------------------------------
-- 5. Hidden or off: no events at all
-------------------------------------------------------------------------------
visible = false
apply()
check(next(ev.events) == nil and icon.shown == false, "hidden by its visibility setting: no events, no icon")
visible = true
apply()
check(ev.events.UNIT_SPELLCAST_SUCCEEDED == "player", "shown again: the events are back")
settings.enabled = false
apply()
check(next(ev.events) == nil and icon.shown == false, "turned off: no events, no icon")

-------------------------------------------------------------------------------
-- 6. A paladin aura cast in combat; a warrior hears no cast or aura event
-------------------------------------------------------------------------------
ev, icon, Fire = Load("PALADIN")
restricted = true
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-7", 19746)
check(icon.shown and icon.tex.texture == "spell:19746", "a paladin aura cast in combat shows")
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-8", 13165)
check(icon.tex.texture == "spell:19746", "another class's aspect is not tracked")
ev = Load("WARRIOR")
check(ev.events.UNIT_SPELLCAST_SUCCEEDED == nil and ev.events.UNIT_AURA == nil, "a warrior registers no cast or aura event")
check(ev.events.UPDATE_SHAPESHIFT_FORM == true, "a warrior follows the stance bar")
ev = Load("MAGE")
check(next(ev.events) == nil, "an unsupported class registers nothing")

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print("PASS test_fe_active_form_cast (" .. count .. " checks)")
