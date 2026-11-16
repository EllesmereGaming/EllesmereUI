-- Stub harness: the gray power bar background of ordinary enemies (hostile NPCs with
-- no real power) on the target, focus and boss frames, across a login paint, a
-- settings pass and unit swaps.
-- Cuts the real code: ns.UF_PowerShouldGray and the power bar's PostUpdate
-- (EUI_UnitFrames_Power.lua), ApplyPowerBarAlpha (EllesmereUIUnitFrames.lua), the
-- settings pass's per-frame power section (EUI_UnitFrames_Reload.lua) and the
-- engine's PaintPower (EUI_UnitFrames_Text.lua). The pass's closing repaint
-- (ApplyEnemyColors -> Engine.ForceAll) is modelled by one PaintPower call per
-- frame, after the sources are checked for that chain.
--   lua .tools/tests/test_uf_power_gray_reload.lua        (from the repository root)

local function ReadSource(path)
    local f = assert(io.open(path, "rb"), "cannot open " .. path)
    local src = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    return src
end

-- From the line holding first (searched from `from`) through the first last after it.
local function Cut(src, first, last, what, from)
    local s = src:find(first, from or 1, true)
    assert(s, what .. ": start not found")
    s = (src:sub(1, s):match(".*()\n") or 0) + 0
    local _, e = src:find(last, s + #first, true)
    assert(e, what .. ": end not found")
    return src:sub(s + 1, e)
end

local function Count(src, text)
    local n, at = 0, 1
    while true do
        local s, e = src:find(text, at, true)
        if not s then return n end
        n, at = n + 1, e + 1
    end
end

local count, fails = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        print("  FAIL: " .. msg)
    end
end

-------------------------------------------------------------------------------
--  The sources
-------------------------------------------------------------------------------
local PSRC = ReadSource("EllesmereUIUnitFrames/EUI_UnitFrames_Power.lua")
local MSRC = ReadSource("EllesmereUIUnitFrames/EllesmereUIUnitFrames.lua")
local RSRC = ReadSource("EllesmereUIUnitFrames/EUI_UnitFrames_Reload.lua")
local TSRC = ReadSource("EllesmereUIUnitFrames/EUI_UnitFrames_Text.lua")
local CSRC = ReadSource("EllesmereUIUnitFrames/EUI_UnitFrames_ClassPower.lua")
local ESRC = ReadSource("EllesmereUIUnitFrames/EUI_UnitFrames_Engine.lua")

-- 1. One writer of the gray: the power bar's PostUpdate. The settings pass only
--    clears the flag, once, in its per-frame power section.
check(Count(PSRC, "_grayedOut = true") == 1, "Power.lua sets the gray flag in one place")
check(Count(PSRC, "SetColorTexture(0.25, 0.25, 0.25, 1)") == 1, "Power.lua paints the gray in one place")
check(Count(RSRC, "_grayedOut = true") == 0, "the settings pass never sets the gray flag itself")
check(Count(RSRC, "0.25, 0.25, 0.25") == 0, "the settings pass never paints the gray itself")
check(Count(RSRC, "_grayedOut = false") == 1, "the settings pass clears the flag in one place")

-- 2. Neither bar has a ForceUpdate method: the pass calls none on them.
check(Count(RSRC, "frame.Power.ForceUpdate") == 0 and Count(RSRC, "frame.Power:ForceUpdate") == 0,
    "the pass calls no ForceUpdate on the power bar")
check(Count(RSRC, "frame.Health.ForceUpdate") == 0 and Count(RSRC, "frame.Health:ForceUpdate") == 0,
    "the pass calls no ForceUpdate on the health bar")
check(Count(PSRC, "ForceUpdate") == 0, "the power bar file defines no ForceUpdate")

-- 3. The pass ends in ApplyEnemyColors, which repaints every frame, and that
--    repaint runs the power bar's PostUpdate.
local sectionFirst = "                ApplyPowerBarAlpha(frame.Power, UnitToSettingsKey(unit))"
local sectionAt = RSRC:find(sectionFirst, 1, true)
local closeAt = RSRC:find("\n    ApplyEnemyColors()\nend\n", 1, true)
check(sectionAt ~= nil and closeAt ~= nil and closeAt > sectionAt,
    "the pass's last statement is ApplyEnemyColors(), after the per-frame power section")
check(Count(RSRC, "ApplyEnemyColors()") == 1, "the pass calls ApplyEnemyColors once")
local enemyColors = Cut(CSRC, "local function ApplyEnemyColors()", "\nend\n", "ApplyEnemyColors")
check(enemyColors:find("ns.Engine.ForceAll(", 1, true) ~= nil, "ApplyEnemyColors repaints through Engine.ForceAll")
local forceAll = Cut(ESRC, "function Engine.ForceAll(event)", "\nend\n", "Engine.ForceAll")
check(forceAll:find("Engine.RepaintAll(frame", 1, true) ~= nil, "Engine.ForceAll repaints every attached frame")
check(ESRC:find('Engine.SetPainter("power", PaintPower)', 1, true) ~= nil
    or TSRC:find('ns.Engine.SetPainter("power", PaintPower)', 1, true) ~= nil,
    "PaintPower is the engine's power painter")

-------------------------------------------------------------------------------
--  World and mocks
-------------------------------------------------------------------------------
local SECRET = {}
local W = {}             -- unit -> { hostile, player, cls, lvl, base }
local playerLevel = 80
local profile = {}
local db = { profile = profile }

issecretvalue = function(v) return v == SECRET end
UnitExists = function(u) return W[u] ~= nil end
UnitCanAttack = function(_, u) return W[u] ~= nil and W[u].hostile == true end
UnitIsPlayer = function(u) return W[u] ~= nil and W[u].player == true end
UnitClassification = function(u) return W[u] and W[u].cls or "normal" end
UnitLevel = function(u)
    if u == "player" then return playerLevel end
    return W[u] and W[u].lvl or 80
end
UnitClassBase = function(u) return W[u] and W[u].base or "WARRIOR" end
UnitPowerType = function() return 1, "RAGE" end
UnitPowerMax = function() return 0 end
UnitPower = function() return 0 end
UnitIsConnected = function() return true end
Enum = { PowerType = { Mana = 0 } }
EllesmereUI = {
    ResolveUnitPowerColor = function() return 1, 0, 0 end,
    GetPowerBgDarkenFactor = function() return 0.5 end,
    POWER_ENUM_TO_KEY = {},
}

local function MakeTex()
    local t = {}
    function t:SetColorTexture(r, g, b) self.r, self.g, self.b = r, g, b end
    function t:SetAlpha(a) self.a = a end
    return t
end
-- A status bar with the widget methods the cut code calls, and no ForceUpdate.
local function MakePower()
    local p = { bg = MakeTex(), _fill = MakeTex() }
    function p:GetStatusBarTexture() return self._fill end
    function p:SetReverseFill() end
    function p:GetReverseFill() return false end
    function p:SetMinMaxValues() end
    function p:SetValue() end
    function p:SetStatusBarColor() end
    return p
end

local ns = {
    UF_PowerPos = function(s) return s.powerPosition or "below" end,
    AnchorPowerBg = function() end,
    Colors = { power = {} },
    Engine = { ElementOn = function() return true end },
}
local KEY = { player = "player", target = "target", focus = "focus", boss1 = "boss" }
local function GetSettingsForUnit(unit) return profile[KEY[unit]] end
local function UnitToSettingsKey(unit) return KEY[unit] end

-------------------------------------------------------------------------------
--  The real code
-------------------------------------------------------------------------------
assert(loadstring("local ns = ...\n" .. Cut(PSRC, "function ns.UF_PowerShouldGray(u)", "\nend\n", "UF_PowerShouldGray"),
    "=UF_PowerShouldGray"))(ns)

local postUpdateChunk = assert(loadstring("local ns, GetSettingsForUnit, power = ...\n"
    .. Cut(PSRC, "    power.PostUpdate = function(self, u, cur, min, max)", "\n    end\n", "PostUpdate"), "=PostUpdate"))

local ApplyPowerBarAlpha = assert(loadstring("local db, ns = ...\n"
    .. Cut(MSRC, "local function ApplyPowerBarAlpha(power, unitKey)", "\nend\n", "ApplyPowerBarAlpha")
    .. "\nreturn ApplyPowerBarAlpha", "=ApplyPowerBarAlpha"))(db, ns)

local PaintPower = assert(loadstring("local ns = ...\n"
    .. Cut(TSRC, "    local function PaintPower(frame, unit, event)", "\n    end\n", "PaintPower")
    .. "\nreturn PaintPower", "=PaintPower"))(ns)

-- The per-frame power section of the settings pass: from its first
-- ApplyPowerBarAlpha through the second one, which follows SetReverseFill.
local PowerSection = assert(loadstring(
    "local frame, unit, settings, ApplyPowerBarAlpha, UnitToSettingsKey, GetSettingsForUnit, ns, EllesmereUI, ApplyBarGradient = ...\n"
    .. Cut(RSRC, sectionFirst, sectionFirst, "the power section") .. "\n", "=power section"))

-------------------------------------------------------------------------------
--  Session helpers
-------------------------------------------------------------------------------
local function NewSettings(alpha)
    return { powerPosition = "below", customPowerBgAlpha = alpha, customPowerBgColor = { r = 0.1, g = 0.2, b = 0.3 } }
end

-- The power bar as CreatePowerBar leaves it: background in the custom colour at
-- the Background Opacity, the flag clear, PostUpdate installed.
local function NewFrame(unit)
    local power = MakePower()
    local s = GetSettingsForUnit(unit)
    local c = s.customPowerBgColor
    if c then power.bg:SetColorTexture(c.r, c.g, c.b) else power.bg:SetColorTexture(17 / 255, 17 / 255, 17 / 255) end
    ApplyPowerBarAlpha(power, UnitToSettingsKey(unit))
    power._grayedOut = false
    postUpdateChunk(ns, GetSettingsForUnit, power)
    return { Power = power, _euiUnit = unit }
end

-- A full power paint (a unit swap, a show, the pass's closing repaint).
local function Paint(frame) PaintPower(frame, frame._euiUnit, "ForceUpdate") end

-- The settings pass for one frame: the power section, then the closing repaint.
local function SettingsPass(frame, closing)
    local unit = frame._euiUnit
    PowerSection(frame, unit, GetSettingsForUnit(unit), ApplyPowerBarAlpha, UnitToSettingsKey, GetSettingsForUnit,
        ns, EllesmereUI, function() end)
    if closing ~= false then Paint(frame) end
end

local function IsGray(bg) return bg.r == 0.25 and bg.g == 0.25 and bg.b == 0.25 end
local function IsColor(bg, c) return bg.r == c.r and bg.g == c.g and bg.b == c.b end
local MOB = { hostile = true }
local FRIEND = { hostile = false }

-------------------------------------------------------------------------------
--  4. Gray across a session, per frame and Background Opacity
-------------------------------------------------------------------------------
for _, unit in ipairs({ "target", "focus", "boss1" }) do
    for _, alpha in ipairs({ 0, 50, 100 }) do
        local key = KEY[unit]
        profile[key] = NewSettings(alpha)
        local s = profile[key]
        local want = alpha / 100
        for u in pairs(W) do W[u] = nil end
        local f = NewFrame(unit)
        local bg = f.Power.bg
        local tag = unit .. " at opacity " .. alpha .. ": "

        -- Login, then an ordinary enemy.
        W[unit] = MOB
        Paint(f)
        check(IsGray(bg), tag .. "an ordinary enemy grays the background")
        check(bg.a == want, tag .. "the gray keeps the Background Opacity")
        check(f.Power._grayedOut == true, tag .. "the flag is set")

        -- A settings change while it is the unit.
        SettingsPass(f)
        check(IsGray(bg), tag .. "still gray after a settings pass")
        check(bg.a == want, tag .. "the Background Opacity after a settings pass")

        -- The section alone repaints the background and leaves the flag clear for
        -- the closing repaint.
        SettingsPass(f, false)
        check(IsColor(bg, s.customPowerBgColor), tag .. "the power section repaints the custom colour")
        check(bg.a == want, tag .. "the power section applies the Background Opacity")
        check(f.Power._grayedOut == false, tag .. "the power section clears the flag")
        Paint(f)
        check(IsGray(bg) and bg.a == want, tag .. "the next paint grays it again")

        -- The next ordinary enemy, with no other unit in between.
        Paint(f)
        check(IsGray(bg), tag .. "gray on the next ordinary enemy")

        -- A friendly unit, then an ordinary enemy again.
        W[unit] = FRIEND
        Paint(f)
        check(IsColor(bg, s.customPowerBgColor) and bg.a == want, tag .. "a friendly unit gets the custom colour and opacity")
        check(f.Power._grayedOut == false, tag .. "the flag clears on a friendly unit")
        W[unit] = MOB
        Paint(f)
        check(IsGray(bg) and bg.a == want, tag .. "gray again on an ordinary enemy")

        -- A settings pass with no unit, then an ordinary enemy.
        W[unit] = nil
        SettingsPass(f)
        check(not IsGray(bg), tag .. "no gray while there is no unit")
        W[unit] = MOB
        Paint(f)
        check(IsGray(bg) and bg.a == want, tag .. "gray after a pass that ran with no unit")

        -- A new background colour: taken by a friendly unit, never by the gray.
        s.customPowerBgColor = { r = 0.6, g = 0.5, b = 0.4 }
        SettingsPass(f)
        check(IsGray(bg), tag .. "a colour change leaves an ordinary enemy gray")
        W[unit] = FRIEND
        SettingsPass(f)
        check(IsColor(bg, s.customPowerBgColor), tag .. "a colour change reaches a friendly unit")

        -- A new Background Opacity while gray.
        W[unit] = MOB
        Paint(f)
        s.customPowerBgAlpha = 30
        SettingsPass(f)
        check(IsGray(bg) and bg.a == 0.3, tag .. "an opacity change reaches the gray")

        -- No custom colour: the stock dark background.
        s.customPowerBgColor = nil
        W[unit] = FRIEND
        SettingsPass(f)
        check(bg.r == 17 / 255 and bg.g == 17 / 255 and bg.b == 17 / 255, tag .. "no custom colour paints the stock background")
    end
end

-------------------------------------------------------------------------------
--  5. Who is an ordinary enemy (the real ns.UF_PowerShouldGray, through PostUpdate)
-------------------------------------------------------------------------------
do
    profile.target = NewSettings(100)
    profile.player = NewSettings(100)
    local function Grays(unit, world, level)
        for u in pairs(W) do W[u] = nil end
        playerLevel = level or 80
        local f = NewFrame(unit)
        W[unit] = world
        Paint(f)
        playerLevel = 80
        return IsGray(f.Power.bg)
    end
    check(Grays("target", { hostile = true }) == true, "a normal hostile NPC is gray")
    check(Grays("target", { hostile = false }) == false, "a friendly NPC is not gray")
    check(Grays("target", { hostile = true, player = true }) == false, "an enemy player is not gray")
    check(Grays("target", { hostile = true, cls = "worldboss" }) == false, "a world boss is not gray")
    check(Grays("target", { hostile = true, cls = "elite", lvl = -1 }) == false, "a skull-level elite is not gray")
    check(Grays("target", { hostile = true, cls = "rareelite", lvl = 81 }) == false, "an elite above your level is not gray")
    check(Grays("target", { hostile = true, cls = "elite", lvl = 80 }) == true, "an elite at your level is gray")
    check(Grays("target", { hostile = true, cls = "normal", lvl = 83 }) == true, "a non-elite above your level is gray")
    check(Grays("target", { hostile = true, base = "PALADIN" }) == false, "a caster-class NPC is not gray")
    check(Grays("target", { hostile = true, cls = "elite", lvl = SECRET }) == true, "an elite whose level is hidden is gray")
    check(Grays("target", { hostile = true, cls = "elite", lvl = 81 }, SECRET) == true,
        "an elite is gray while your own level is hidden")
    check(Grays("target", { hostile = true, base = SECRET }) == true, "an NPC whose class is hidden is gray")
    check(Grays("player", { hostile = true }) == false, "the player frame is never gray")
end

-------------------------------------------------------------------------------
--  6. A detached power bar is left alone; a power-colored background comes back
-------------------------------------------------------------------------------
do
    for _, pos in ipairs({ "detached_top", "detached_bottom", "none" }) do
        for u in pairs(W) do W[u] = nil end
        profile.target = NewSettings(100)
        profile.target.powerPosition = pos
        local f = NewFrame("target")
        W.target = MOB
        Paint(f)
        check(not IsGray(f.Power.bg) and f.Power._grayedOut == false, "power position " .. pos .. ": no gray")
    end
    for _, pos in ipairs({ "below", "above" }) do
        for u in pairs(W) do W[u] = nil end
        profile.target = NewSettings(100)
        profile.target.powerPosition = pos
        local f = NewFrame("target")
        W.target = MOB
        Paint(f)
        check(IsGray(f.Power.bg), "power position " .. pos .. ": gray")
    end

    for u in pairs(W) do W[u] = nil end
    profile.target = NewSettings(40)
    profile.target.powerBgPowerColored = true
    local f = NewFrame("target")
    local bg = f.Power.bg
    W.target = MOB
    Paint(f)
    check(IsGray(bg) and bg.a == 0.4, "power-colored background: an ordinary enemy is gray at the opacity")
    W.target = FRIEND
    Paint(f)
    check(bg.r == 0.5 and bg.g == 0 and bg.b == 0 and bg.a == 0.4,
        "power-colored background: a friendly unit gets its power colour back at the opacity")

    -- A power colour that cannot be read: the stock background.
    local resolve = EllesmereUI.ResolveUnitPowerColor
    EllesmereUI.ResolveUnitPowerColor = function() return nil end
    W.target = MOB
    Paint(f)
    W.target = FRIEND
    Paint(f)
    check(bg.r == 17 / 255 and bg.g == 17 / 255 and bg.b == 17 / 255,
        "power-colored background with no readable power colour: the stock background")
    EllesmereUI.ResolveUnitPowerColor = resolve

    -- Neither a custom colour nor a power colour: the stock background comes back.
    for u in pairs(W) do W[u] = nil end
    profile.target = NewSettings(100)
    profile.target.customPowerBgColor = nil
    f = NewFrame("target")
    bg = f.Power.bg
    W.target = MOB
    Paint(f)
    check(IsGray(bg), "no custom colour: an ordinary enemy is gray")
    W.target = FRIEND
    Paint(f)
    check(bg.r == 17 / 255 and bg.g == 17 / 255 and bg.b == 17 / 255,
        "no custom colour: a friendly unit gets the stock background back")
end

if fails > 0 then error(fails .. " of " .. count .. " checks failed") end
print("PASS test_uf_power_gray_reload (" .. count .. " checks)")
