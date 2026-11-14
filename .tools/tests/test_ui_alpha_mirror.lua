-- Stub harness: the UI alpha mirror helpers of EllesmereUI_SharedHelpers.lua. 3D models ignore every parent's
-- alpha, UIParent's too, so their owners mirror it by hand through these two. Cuts the block and drives:
--   1. UIScaledAlpha: a full UI passes the alpha through, a faded UI scales it, a secret UI alpha passes it
--      (tested before any compare), and a secret alpha passes whole unless the UI is fully faded (then 0);
--   2. OnUIAlphaChanged: UIParent:SetAlpha is hooked only by the first registration, once, and a function
--      registered twice is listed once;
--   3. the listeners run when the UI alpha changes and not when a SetAlpha repeats the last one;
--   4. a secret UI alpha always notifies, and the plain alpha after it notifies too.
--   lua .tools/tests/test_ui_alpha_mirror.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local f = assert(io.open(ROOT .. "/EllesmereUI_SharedHelpers.lua", "rb"))
local SRC = f:read("*a"):gsub("\r\n", "\n")
f:close()
local s = assert(SRC:find("do\n    local listeners, lastAlpha\n", 1, true), "the block's start was not found")
local fnAt = assert(SRC:find("    function EllesmereUI.OnUIAlphaChanged(fn)\n", s, true), "OnUIAlphaChanged not found")
local _, e = SRC:find("\nend\n", fnAt, true)
assert(e, "the block's end was not found")

-- a secret value: any compare or arithmetic on it raises, as in the game
local SECRET = setmetatable({}, {
    __lt = function() error("compared a secret") end,
    __le = function() error("compared a secret") end,
    __mul = function() error("arithmetic on a secret") end,
})
function issecretvalue(v) return v == SECRET end

local uiAlpha, hooks = 1, 0
UIParent = {
    GetAlpha = function() return uiAlpha end,
    SetAlpha = function(self, a) uiAlpha = a end,
}
function hooksecurefunc(t, name, fn)
    assert(t == UIParent and name == "SetAlpha", "hooked something else")
    hooks = hooks + 1
    local orig = t[name]
    t[name] = function(...)
        orig(...)
        fn(...)
    end
end
EllesmereUI = {}
assert(loadstring(SRC:sub(s, e), "=ui alpha block"))()
local Scaled, OnChanged = EllesmereUI.UIScaledAlpha, EllesmereUI.OnUIAlphaChanged

-------------------------------------------------------------------------------
--  1. UIScaledAlpha
-------------------------------------------------------------------------------
assert(hooks == 0, "UIParent:SetAlpha was hooked before anything registered")
assert(Scaled(0.5) == 0.5, "a full UI changed the alpha")
uiAlpha = 0.5
assert(Scaled(0.5) == 0.25 and Scaled(1) == 0.5 and Scaled(0) == 0, "a faded UI did not scale the alpha")
uiAlpha = 0
assert(Scaled(0.8) == 0, "a fully faded UI left a model showing")
uiAlpha = SECRET
assert(Scaled(0.7) == 0.7, "a secret UI alpha did not pass the alpha through")
uiAlpha = 0.5
assert(Scaled(SECRET) == SECRET, "a secret alpha did not pass whole under a part-faded UI")
uiAlpha = 0
assert(Scaled(SECRET) == 0, "a secret alpha stayed up under a fully faded UI")
uiAlpha = 1
assert(Scaled(SECRET) == SECRET, "a secret alpha did not pass whole under a full UI")
assert(hooks == 0, "UIScaledAlpha hooked UIParent")

-------------------------------------------------------------------------------
--  2. registration: one hook, a function listed once
-------------------------------------------------------------------------------
local a, b = 0, 0
local function A() a = a + 1 end
local function B() b = b + 1 end
OnChanged(A)
OnChanged(A)
assert(hooks == 1, "the first registration did not hook UIParent:SetAlpha once: " .. hooks)
UIParent:SetAlpha(0.6)
assert(a == 1, "a function registered twice ran " .. a .. " times")

-------------------------------------------------------------------------------
--  3. a change notifies, a repeat does not
-------------------------------------------------------------------------------
UIParent:SetAlpha(0.6)
UIParent:SetAlpha(0.6)
assert(a == 1, "a repeated alpha ran the listeners again")
UIParent:SetAlpha(0.3)
assert(a == 2, "a new alpha did not run the listeners")
OnChanged(B)
assert(hooks == 1, "a second registration hooked UIParent again")
UIParent:SetAlpha(0)
assert(a == 3 and b == 1, "a change did not reach every listener")
UIParent:SetAlpha(0)
assert(a == 3 and b == 1, "a repeated 0 ran the listeners again")
UIParent:SetAlpha(1)
assert(a == 4 and b == 2, "the fade back in did not run the listeners")

-------------------------------------------------------------------------------
--  4. a secret UI alpha always notifies; so does the plain alpha after it
-------------------------------------------------------------------------------
UIParent:SetAlpha(SECRET)
UIParent:SetAlpha(SECRET)
assert(a == 6 and b == 4, "a secret UI alpha did not notify every time")
UIParent:SetAlpha(1)
assert(a == 7 and b == 5, "the plain alpha after a secret one did not notify (it equals the last plain one)")
UIParent:SetAlpha(1)
assert(a == 7 and b == 5)

print("PASS: the UI alpha mirror helpers scale, hook once, and notify only on a change")
