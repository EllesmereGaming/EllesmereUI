-- Stub harness: the Action Bars pressed look for natively routed keys
-- (EUI_ActionBars_Pushed.lua, EAB:HookPushedFlash). Cuts the real block out of
-- the file and drives its hooks: ActionButtonDown / MultiActionButtonDown show
-- the pushed texture, a poll hides it once IsKeyDown reads the key released,
-- and ActionButtonUp / MultiActionButtonUp hide it on the binding's own key-up.
-- IsKeyDown reads no non-ASCII key name (the section sign, umlauts: website bug
-- #194), so such a key stays lit until its key-up instead of blinking one frame.
--   lua .tools/tests/test_ab_pushed_flash.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return (src:gsub("\r\n", "\n"))
end
local SRC = ReadSource("EllesmereUIActionBars/EUI_ActionBars_Pushed.lua")
local a = assert(SRC:find("\ndo\n    local _pushedHooked = false", 1, true), "pushed-flash block missing")
local e = assert(SRC:find("\nend\n", a + 1, true), "end of the pushed-flash block missing")
local BLOCK = SRC:sub(a + 1, e + 4)

local SECTION = "\194\167"     -- the section sign, as the client names that key
local O_UMLAUT = "\195\150"

local function NewTexture()
    local t = { shown = false }
    function t:Show() self.shown = true end
    function t:Hide() self.shown = false end
    return t
end

local function Build(block)
    local T = { hooks = {}, binds = {}, down = {}, pushedType = 2 }
    local poll = { shown = false, scripts = {} }
    function poll:SetScript(name, fn) self.scripts[name] = fn end
    function poll:Show() self.shown = true end
    function poll:Hide() self.shown = false end
    local ns = { TakeShell = function() return poll end, AB_Style = function() return "eui" end }
    local EAB = { db = { profile = setmetatable({}, { __index = function(_, k)
        if k == "pushedTextureType" then return T.pushedType end
    end }) } }
    local allButtons = {}
    local function hooksecurefunc(name, fn) T.hooks[name] = fn end
    local function GetBindingKey(cmd) return T.binds[cmd] end
    -- The client's IsKeyDown: false for a key name it cannot read.
    local function IsKeyDown(key) return not key:find("[\128-\255]") and T.down[key] == true end
    local chunk = assert(loadstring(
        "local EAB, ns, allButtons, GetBindingKey, hooksecurefunc, IsKeyDown, MultiActionButtonDown, MultiActionButtonUp = ...\n"
        .. block, "=EUI_ActionBars_Pushed.lua"))
    chunk(EAB, ns, allButtons, GetBindingKey, hooksecurefunc, IsKeyDown, function() end, function() end)
    EAB:HookPushedFlash()
    T.poll, T.allButtons = poll, allButtons
    function T.Button(slot, cmd, key)
        local btn = { commandName = cmd, PushedTexture = NewTexture() }
        allButtons[slot] = btn
        T.binds[cmd] = key
        return btn
    end
    function T.Frames(n)
        for _ = 1, n do
            if poll.shown then poll.scripts.OnUpdate(poll, 0.016) end
        end
    end
    return T
end

local function Scenarios(T)
    -- 1. The section sign on bar 1: lit while held, off on its key-up.
    local b1 = T.Button(1, "ACTIONBUTTON1", SECTION)
    T.hooks.ActionButtonDown(1)
    assert(b1.PushedTexture.shown and T.poll.shown, "the section-sign press shows nothing")
    T.Frames(5)
    assert(b1.PushedTexture.shown, "the section-sign key blinked off while held")
    T.hooks.ActionButtonUp(1)
    assert(not b1.PushedTexture.shown, "the section-sign key stayed lit after its key-up")
    T.Frames(1)
    assert(not T.poll.shown, "the poll kept running with nothing lit")

    -- 2. A modified umlaut on a multibar (MultiBarLeft = page 4: slot 39).
    local b39 = T.Button(39, "MULTIACTIONBAR4BUTTON3", "SHIFT-" .. O_UMLAUT)
    T.hooks.MultiActionButtonDown("MultiBarLeft", 3)
    T.Frames(3)
    assert(b39.PushedTexture.shown, "the umlaut key blinked off while held")
    T.hooks.MultiActionButtonUp("MultiBarLeft", 3)
    assert(not b39.PushedTexture.shown, "the umlaut key stayed lit after its key-up")
    T.hooks.MultiActionButtonUp("NotABar", 3)

    -- 3. An ordinary key: the poll clears it, the later key-up changes nothing,
    --    and the next press still lights and clears (no double count).
    local b2 = T.Button(2, "ACTIONBUTTON2", "1")
    T.down["1"] = true
    T.hooks.ActionButtonDown(2)
    T.Frames(3)
    assert(b2.PushedTexture.shown, "an ordinary key went dark while held")
    T.down["1"] = false
    T.Frames(1)
    assert(not b2.PushedTexture.shown, "an ordinary key stayed lit after release")
    T.hooks.ActionButtonUp(2)
    local b3 = T.Button(3, "ACTIONBUTTON3", "2")
    T.down["2"] = true
    T.hooks.ActionButtonDown(3)
    T.Frames(1)
    T.down["2"] = false
    T.Frames(1)
    assert(not b3.PushedTexture.shown, "after a key-up of a cleared key the next press stayed lit")
    assert(not T.poll.shown, "the poll kept running after the last key went dark")

    -- 4. A key-up for a slot that was never pressed, and the pushed style None.
    T.hooks.ActionButtonUp(7)
    T.pushedType = 6
    local b4 = T.Button(4, "ACTIONBUTTON4", SECTION)
    T.hooks.ActionButtonDown(4)
    assert(not b4.PushedTexture.shown, "the None pushed style showed a press")
end

Scenarios(Build(BLOCK))

-------------------------------------------------------------------------------
--  Mutants: each must break a scenario
-------------------------------------------------------------------------------
local function Swap(text, from, to)
    local s, f = text:find(from, 1, true)
    assert(s, "mutant text not found: " .. from)
    return text:sub(1, s - 1) .. to .. text:sub(f + 1)
end
local MUTANTS = {
    { "a non-ASCII key reads released", [==[ or keys[i]:find("[\128-\255]")]==], "" },
    { "no ActionButtonUp hook", 'hooksecurefunc("ActionButtonUp", function(id) HidePushedForSlot(id) end)', "" },
    { "no MultiActionButtonUp hook", 'hooksecurefunc("MultiActionButtonUp",', 'hooksecurefunc("MultiActionButtonUp_unused",' },
    { "a key-up of a cleared key counts again",
      "if not (btn and _activePushed[btn]) then return end", "if not btn then return end" },
}
for _, m in ipairs(MUTANTS) do
    local ok = pcall(function() Scenarios(Build(Swap(BLOCK, m[2], m[3]))) end)
    assert(not ok, "mutant survived: " .. m[1])
end

print(("PASS: pressed look on section-sign, umlaut and ordinary keys, %d mutants killed"):format(#MUTANTS))
