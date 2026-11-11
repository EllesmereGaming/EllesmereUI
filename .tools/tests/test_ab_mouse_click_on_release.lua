-- Stub harness: Cast Actions on Key Down applies to keys alone. A mouse click
-- on an action button acts on the release, as on Blizzard's bars, so a press
-- that becomes a drag never casts.
-- Cuts the action buttons' OnClick wrap (its header and both snippets) from
-- EUI_ActionBars_Secure.lua and ApplyClickRegistration from
-- EUI_ActionBars_Keybinds.lua, and plays presses through a model of the secure
-- click wrapper (Wrapped_Click in SecureHandlers.lua) and of the edge choice
-- of SecureActionButton_OnClick (SecureTemplates.lua), the OnClick our buttons
-- take from SecureActionButtonTemplate, called with no isKeyPress and no
-- isSecureAction, so the useOnKeyDown attribute decides the edge.
--   a mouse press casts nothing, bars locked or unlocked, pickup modifier held
--     or not; a click without a drag casts once, on the release; a drag casts
--     nothing (and picks the action up only where Blizzard's drag does)
--   a keybind press (the button not under the mouse) casts on its configured
--     edge, a flip a drag left behind included
--   a key pressed while the cursor rests on its own button reads as a mouse
--     click and acts on the release (the known limit of the rect test)
--   a hold-and-release spell still starts on the press
--   a player whose useOnKeyDown is false is never forced back to true
--   the wrap reads no lock state and no modifier, and its header is the button
--   Cast Actions on Key Down turned off after a drag (Keybinds.lua's
--     ApplyClickRegistration) stays off on the button the drag started from
-- The snippets run with only the names the restricted environment gives them.
-- The model is this file's reading of the client, not the client.
--   lua .tools/tests/test_ab_mouse_click_on_release.lua   (from the repository root)
local SECURE = AB_SECURE or "EllesmereUIActionBars/EUI_ActionBars_Secure.lua"
local KEYBINDS = AB_KEYBINDS or "EllesmereUIActionBars/EUI_ActionBars_Keybinds.lua"

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
    local s = fh:read("*a"):gsub("\r\n", "\n")
    fh:close()
    return s
end

-------------------------------------------------------------------------------
--  The cut code
-------------------------------------------------------------------------------
local secureSrc = Read(SECURE)
local WRAP_OPEN = 'SecureHandlerWrapScript(btn, "OnClick", '
local a = assert(secureSrc:find(WRAP_OPEN, 1, true), "OnClick wrap not found")
local hs = a + #WRAP_OPEN
local he = assert(secureSrc:find(", [[", hs, true), "wrap header not found")
local HEADER = secureSrc:sub(hs, he - 1)
local ps = he + #", [["
local pe = assert(secureSrc:find("]], [[", ps, true), "pre-body end not found")
local PRE = secureSrc:sub(ps, pe - 1)
local qs = pe + #"]], [["
local qe = assert(secureSrc:find("]])", qs, true), "post-body end not found")
local POST = secureSrc:sub(qs, qe - 1)

local keybindsSrc = Read(KEYBINDS)
local ks = assert(keybindsSrc:find("local function ApplyClickRegistration()", 1, true), "ApplyClickRegistration not found")
local ke = assert(keybindsSrc:find("\nend\n", ks, true), "ApplyClickRegistration end not found")
local ApplyBody = keybindsSrc:sub(ks, ke + #"\nend\n" - 1)

-------------------------------------------------------------------------------
--  The world
-------------------------------------------------------------------------------
local W
local function Reset()
    W = {
        cvarKeyDown = true,     -- ActionButtonUseKeyDown
        locked = true,          -- Blizzard's lockActionBars setting
        shift = false,          -- the PICKUPACTION modifier
        underMouse = false,
        casts = {},             -- edges an action fired on, in order
        pickups = 0,
    }
end
Reset()

local btn = { name = "EABButton1", attrs = {} }
function btn:GetAttribute(k) return self.attrs[k] end
function btn:SetAttribute(k, v) self.attrs[k] = v end

-- The restricted handle of the button: the snippets see only these methods.
local btnHandle = {}
function btnHandle:GetAttribute(k)
    if type(k) ~= "string" or k:match("^_") then return nil end
    return btn.attrs[k]
end
function btnHandle:SetAttribute(k, v) btn.attrs[k] = v end
function btnHandle:IsUnderMouse() return W.underMouse end

check(HEADER == "btn", "the wrap's header is the button itself (header: " .. tostring(HEADER) .. ")")
check(PRE:find("eab-barslocked", 1, true) == nil, "the pre-body reads no lock state")
check(PRE:find("IsModifiedClick", 1, true) == nil, "the pre-body reads no modifier")
check(PRE:find("control", 1, true) == nil, "the pre-body needs no header frame")

local function Snippet(body, sig, label)
    local fn = assert(loadstring("return function(" .. sig .. ")\n" .. body .. "\nend", "=" .. label))
    -- the restricted environment: no globals of ours, the header as control
    local env = { control = btnHandle }
    setfenv(fn, env)
    local inner = fn()
    setfenv(inner, env)
    return inner
end
local PreFn = Snippet(PRE, "self,button,down", "OnClickPre")
local PostFn = Snippet(POST, "self,message,button,down", "OnClickPost")

-- SecureActionButton_OnClick's edge choice for a click with no isKeyPress and
-- no isSecureAction (an addon button's OnClick from SecureActionButtonTemplate).
local function NativeOnClick(down)
    local uokd = btn.attrs.useOnKeyDown
    if uokd == nil then uokd = W.cvarKeyDown end
    uokd = uokd or btn.attrs.pressAndHoldAction and true or false
    local clickAction = (down and uokd) or (not down and not uokd)
    if clickAction then W.casts[#W.casts + 1] = down and "down" or "up" end
end

-- Wrapped_Click: the pre-body runs (a protected button is always eligible),
-- then the original handler, then the post-body when the pre returned a message.
local downMessages = 0
local function Click(down)
    local ok, newbutton, message = pcall(PreFn, btnHandle, "LeftButton", down)
    check(ok, "the pre-body runs with the restricted names alone: " .. tostring(newbutton))
    if not ok then return end
    if newbutton == false then return end
    if down and message ~= nil then downMessages = downMessages + 1 end
    NativeOnClick(down)
    if message ~= nil then
        local ok2, err = pcall(PostFn, btnHandle, message, "LeftButton", down)
        check(ok2, "the post-body runs with the restricted names alone: " .. tostring(err))
    end
end

-- Blizzard's OnDragStart (ActionBarActionButtonMixin:OnDragStart).
local function DragStart()
    if not W.locked or W.shift then W.pickups = W.pickups + 1 end
end

-- ApplyClickRegistration from Keybinds.lua, over one bar holding this button.
local ApplyClickRegistration = assert(loadstring(
    "local GetCVarBool, ipairs, BAR_CONFIG, barButtons = ...\n"
    .. ApplyBody .. "\nreturn ApplyClickRegistration\n", "=ApplyClickRegistration"))(
    function(key)
        if key == "ActionButtonUseKeyDown" then return W.cvarKeyDown end
    end,
    ipairs,
    { { key = "MainBar" }, { key = "StanceBar", isStance = true }, { key = "PetBar", isPetBar = true } },
    { MainBar = { btn } })

local function Session(locked, keyDownAttr, shift)
    Reset()
    W.locked = locked
    W.shift = shift and true or false
    btn.attrs = { useOnKeyDown = keyDownAttr }
    downMessages = 0
end

-- One gesture: a mouse press (drag or release) or a keybind press and release.
local function MousePress(drag)
    W.underMouse = true
    Click(true)
    if drag then
        DragStart()       -- a drag takes the release: no up click arrives
    else
        Click(false)
    end
    W.underMouse = false
end
-- hovered: the cursor rests on the button while its key is pressed.
local function KeyPress(hovered)
    W.underMouse = hovered and true or false
    Click(true)
    Click(false)
    W.underMouse = false
end
local function Casts() return table.concat(W.casts, ",") end
local function ClearLog() W.casts = {}; W.pickups = 0 end

-------------------------------------------------------------------------------
--  The rules
-------------------------------------------------------------------------------
-- Key down on: a mouse click acts on the release whatever the lock and the
-- pickup modifier say; a drag never casts.
local function MouseRules(tag, locked, shift, dragPicksUp)
    Session(locked, true, shift)
    W.underMouse = true
    Click(true)
    check(Casts() == "", tag .. ": the press itself casts nothing (cast on: " .. Casts() .. ")")
    Session(locked, true, shift)
    MousePress(false)
    check(Casts() == "up", tag .. ": a click without a drag casts once, on the release (cast on: " .. Casts() .. ")")
    check(btn.attrs.useOnKeyDown == true and not btn.attrs.eabPickupFlipped,
        tag .. ": after the click the button is back on key down")
    check(downMessages == 0, tag .. ": the pre-body never returns a message on a press")
    ClearLog()
    MousePress(true)
    check(Casts() == "", tag .. ": a drag casts nothing (cast on: " .. Casts() .. ")")
    check(W.pickups == (dragPicksUp and 1 or 0), tag .. ": the drag picks up only where Blizzard's drag does")
    ClearLog()
    W.shift = false
    KeyPress()
    check(Casts() == "down", tag .. ": a keybind press casts on the press (cast on: " .. Casts() .. ")")
end
MouseRules("locked bars", true, false, false)
MouseRules("locked bars, pickup modifier", true, true, true)
MouseRules("unlocked bars", false, false, true)
MouseRules("unlocked bars, pickup modifier", false, true, true)

-- A drag leaves its flip behind; the next press heals it before the native handler.
Session(true, true)
MousePress(true)
check(btn.attrs.eabPickupFlipped == true and btn.attrs.useOnKeyDown == false, "a drag leaves the flip for the next press")
ClearLog()
KeyPress()
check(Casts() == "down", "a keybind press after a drag casts on the press (cast on: " .. Casts() .. ")")
check(btn.attrs.useOnKeyDown == true and not btn.attrs.eabPickupFlipped, "the stale flip is healed")
Session(true, true)
MousePress(true)
ClearLog()
MousePress(false)
check(Casts() == "up", "a click after a drag casts once, on the release (cast on: " .. Casts() .. ")")
check(btn.attrs.useOnKeyDown == true and not btn.attrs.eabPickupFlipped, "and the button is back on key down")

-- The rect test's known limit: a key pressed while the cursor rests on its own button.
Session(true, true)
KeyPress(true)
check(Casts() == "up", "a key pressed with the cursor on its button acts once, on the release (cast on: " .. Casts() .. ")")
check(btn.attrs.useOnKeyDown == true and not btn.attrs.eabPickupFlipped, "and leaves the button on key down")

-- A hold-and-release spell: pressAndHoldAction decides its edge, so the press still starts it.
Session(true, true)
btn.attrs.pressAndHoldAction = true
MousePress(false)
check(Casts() == "down", "a hold-and-release spell still starts on the mouse press (cast on: " .. Casts() .. ")")
check(btn.attrs.useOnKeyDown == true and not btn.attrs.eabPickupFlipped, "and its click restores key down")

-- A player with key down off: nothing is forced back to true.
Session(false, false)
MousePress(false)
check(Casts() == "up", "key down off: a click casts on the release")
check(btn.attrs.useOnKeyDown == false and not btn.attrs.eabPickupFlipped, "key down off: useOnKeyDown stays false, no flip")
ClearLog()
MousePress(true)
check(Casts() == "" and W.pickups == 1, "key down off, unlocked: a drag casts nothing")
ClearLog()
KeyPress()
check(Casts() == "up" and btn.attrs.useOnKeyDown == false, "key down off: a keybind acts on the release")

-- Cast Actions on Key Down turned off after a drag left its flip behind.
local function KeyDownOffAfterDrag(tag, locked, shift)
    Session(locked, true, shift)
    MousePress(true)
    W.shift = false
    check(Casts() == "", tag .. ": the drag casts nothing")
    W.cvarKeyDown = false
    ApplyClickRegistration()
    check(btn.attrs.useOnKeyDown == false, tag .. ": turning key down off writes false")
    ClearLog()
    MousePress(false)
    check(Casts() == "up", tag .. ": the next click casts on the release (cast on: " .. Casts() .. ")")
    check(btn.attrs.useOnKeyDown == false, tag .. ": and leaves key down off")
    ClearLog()
    KeyPress()
    check(Casts() == "up", tag .. ": a keybind acts on the release (cast on: " .. Casts() .. ")")
    check(btn.attrs.useOnKeyDown == false, tag .. ": key down stays off throughout")
    W.cvarKeyDown = true
    ApplyClickRegistration()
    check(btn.attrs.useOnKeyDown == true and not btn.attrs.eabPickupFlipped, tag .. ": turning it on again writes true")
end
KeyDownOffAfterDrag("drag on locked bars", true, false)
KeyDownOffAfterDrag("shift-drag on locked bars", true, true)
KeyDownOffAfterDrag("drag on unlocked bars", false, false)

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print("PASS test_ab_mouse_click_on_release (" .. count .. " checks)")
