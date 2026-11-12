-- Stub harness: the shared checkbox dropdown (BuildVisOptsCBDropdown), its
-- refresh function's opt-in re-read of a dynamic list.
-- Runs the real widget file (EllesmereUIOptions/EllesmereUI_Widgets_CheckboxDropdowns.lua)
-- over frame stubs that keep scripts, shown state and text.
--   the refresh function with no argument never reads a dynamic list again
--     (a page refresh calls it that way); refresh(true) reads it again while
--     the menu is closed, so the summary names an entry added outside the
--     menu (a spell ID typed into a popup), and leaves an open menu's list
--     alone
--   only the boolean true asks for it; a static list takes refresh(true) as a
--     plain refresh
--   the pinned top actions are as they were: no hover text of their own, a
--     locked one explains itself and takes no click, a click hides the menu
--     and then runs the action
--   lua .tools/tests/test_cb_dropdown_refresh_reread.lua   (from the repository root)
local WIDGET = CBX_WIDGET or "EllesmereUIOptions/EllesmereUI_Widgets_CheckboxDropdowns.lua"

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
    if s:sub(1, 3) == "\239\187\191" then s = s:sub(4) end
    return s
end

-------------------------------------------------------------------------------
--  Frame stubs
-------------------------------------------------------------------------------
local Noop = function() end
local Zero = function() return 0 end
local One = function() return 1 end
local False = function() return false end
local all = {}
local NewObj

local M = {}
function M:SetScript(name, fn) self._scripts[name] = fn end
function M:GetScript(name) return self._scripts[name] end
function M:HookScript(name, fn)
    local old = self._scripts[name]
    self._scripts[name] = old and function(...) old(...); fn(...) end or fn
end
function M:Show()
    if self._shown then return end
    self._shown = true
    if self._scripts.OnShow then self._scripts.OnShow(self) end
end
function M:Hide()
    if not self._shown then return end
    self._shown = false
    if self._scripts.OnHide then self._scripts.OnHide(self) end
end
function M:SetShown(v) if v then self:Show() else self:Hide() end end
function M:IsShown() return self._shown end
function M:IsVisible() return self._shown end
function M:SetText(t) self._text = t end
function M:GetText() return self._text or "" end
function M:SetHeight(h) self._h = h end
function M:GetHeight() return self._h or 0 end
function M:SetFrameLevel(l) self._level = l end
function M:GetFrameLevel() return self._level or 1 end
function M:CreateTexture() return NewObj("Texture", self) end
function M:CreateFontString()
    local fs = NewObj("FontString", self)
    self._fontStrings[#self._fontStrings + 1] = fs
    return fs
end
function M:CreateAnimationGroup() return NewObj("AnimationGroup", self) end
function M:CreateAnimation() return NewObj("Animation", self) end
M.GetEffectiveScale, M.GetScale, M.IsMouseOver = One, One, False

-- Any other widget method: a getter answers 0, a test answers false, the rest
-- do nothing. Fields (lower case or underscored keys) stay nil until written.
local ObjMT = { __index = function(_, k)
    local m = M[k]
    if m then return m end
    if type(k) ~= "string" or not k:match("^%u") then return nil end
    if k:sub(1, 3) == "Get" then return Zero end
    if k:sub(1, 2) == "Is" then return False end
    return Noop
end }
NewObj = function(kind, parent)
    local o = setmetatable({ _kind = kind, _parent = parent, _shown = true, _scripts = {}, _fontStrings = {} }, ObjMT)
    all[#all + 1] = o
    return o
end

-------------------------------------------------------------------------------
--  The world
-------------------------------------------------------------------------------
local tips = {} -- every tooltip call, in order: { "show", anchor, text } / { "hide" }

function wipe(t) for k in pairs(t) do t[k] = nil end return t end
strlower, strfind = string.lower, string.find
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function IsMouseButtonDown() return false end
function GetCursorPosition() return 0, 0 end
UIParent = NewObj("Frame")

local PP = setmetatable({}, { __index = function() return Noop end })
local EUI = setmetatable({
    _Pool = {
        CreateFrame = function(kind, _, parent) return NewObj(kind, parent) end,
        Kept = function(owner, key, kind, parent)
            owner._kept = owner._kept or {}
            owner._kept[key] = owner._kept[key] or NewObj(kind, parent)
            return owner._kept[key]
        end,
        Gen = function() return 1 end,
    },
    PanelPP = PP,
    ELLESMERE_GREEN = { r = 0, g = 1, b = 0 },
    L = function(s) return s end,
    Lf = function(s, ...) return s:format(...) end,
    MakeRoundedBorder = function() return NewObj("Border") end,
    MakeDropdownArrow = function() return NewObj("Texture") end,
    OverlayParent = function() return UIParent end,
    GetPopupScale = One,
    ShowWidgetTooltip = function(anchor, text)
        if type(text) == "function" then text = text() end
        tips[#tips + 1] = { "show", anchor, text }
    end,
    HideWidgetTooltip = function() tips[#tips + 1] = { "hide" } end,
}, { __index = function(_, k)
    -- Every other helper does nothing and answers nil; fields stay nil.
    if type(k) == "string" and k:match("^%u") then return Noop end
end })
_G.EllesmereUI = EUI
assert(loadstring(Read(WIDGET), "=CheckboxDropdowns"))()

-- The row a menu built for the top action with this label.
local function ActionRow(label)
    local found
    for i = 1, #all do
        local o = all[i]
        if o._kind == "Button" and rawget(o, "_lbl") and o._lbl._text == label and o._shown
            and o._scripts.OnClick and not rawget(o, "_updateCheck") then
            found = o
        end
    end
    return assert(found, "no top action row labelled " .. label)
end
local function Shows()
    local n = 0
    for i = 1, #tips do if tips[i][1] == "show" then n = n + 1 end end
    return n
end

-------------------------------------------------------------------------------
--  A dynamic list with two top actions
-------------------------------------------------------------------------------
local clicks, order = {}, {}
local locked = true
local picked = { a = true }
local reads = 0
local extra -- a row added outside the menu
local function Items()
    reads = reads + 1
    local t = {
        { isTopAction = true, label = "Plain Action", onClick = function()
            clicks[#clicks + 1] = "plain"
            order[#order + 1] = "click"
        end },
        { isTopAction = true, label = "Locked Action",
            lockedFn = function() return locked end, lockedTooltip = "Needs something first.",
            onClick = function() clicks[#clicks + 1] = "locked" end },
        { isHeader = true, label = "Rows" },
        { key = "a", label = "Alpha" },
        { key = "b", label = "Beta" },
    }
    if extra then t[#t + 1] = { key = extra, label = "Gamma" } end
    return t
end

local host = NewObj("Frame")
local dd, refresh = EUI.BuildVisOptsCBDropdown(host, 190, 5, Items,
    function(k) return picked[k] and true or false end,
    function(k, v) picked[k] = v and true or nil end,
    nil, 10, true)
local label = dd._fontStrings[1]
check(label ~= nil and label._text == "Alpha", "the closed dropdown names its checked row (reads " .. tostring(label and label._text) .. ")")

-------------------------------------------------------------------------------
--  refresh(true): a dynamic list read again while the menu is closed
-------------------------------------------------------------------------------
local r0 = reads
extra, picked.c = "c", true
refresh()
check(reads == r0, "a plain refresh never reads a dynamic list again")
check(label._text == "Alpha", "so its summary still shows the list it last read (reads " .. tostring(label._text) .. ")")
refresh(true)
check(reads == r0 + 1, "refresh(true) reads the list again, once")
check(label._text == "Alpha, Gamma", "and the summary names the entry added outside the menu (reads " .. tostring(label._text) .. ")")
refresh("yes")
refresh(1)
check(reads == r0 + 1, "only the boolean true asks for the re-read")

-- An open menu keeps the list it was laid out from.
dd._scripts.OnClick(dd)
local menu = dd._ddMenu
check(menu ~= nil and menu:IsShown(), "a click opens the menu")
r0 = reads
refresh(true)
check(reads == r0, "refresh(true) leaves an open menu's list alone")

-------------------------------------------------------------------------------
--  Top actions, as they were
-------------------------------------------------------------------------------
local plain, lockedRow = ActionRow("Plain Action"), ActionRow("Locked Action")
tips = {}
plain._scripts.OnEnter(plain)
check(Shows() == 0, "a top action shows no hover text of its own")
plain._scripts.OnLeave(plain)

tips = {}
lockedRow._scripts.OnEnter(lockedRow)
check(Shows() == 1 and tips[1][3] == "Needs something first.", "a locked top action explains itself")
lockedRow._scripts.OnLeave(lockedRow)
lockedRow._scripts.OnClick(lockedRow)
check(#clicks == 0 and menu:IsShown(), "and takes no click")
locked = false
tips = {}
lockedRow._scripts.OnEnter(lockedRow)
check(Shows() == 0, "once unlocked it shows nothing on hover")
lockedRow._scripts.OnLeave(lockedRow)

menu:HookScript("OnHide", function() order[#order + 1] = "menu hidden" end)
plain._scripts.OnClick(plain)
check(order[1] == "menu hidden" and order[2] == "click" and #order == 2,
    "a click hides the menu, then runs the action (" .. table.concat(order, ", ") .. ")")
check(not menu:IsShown() and clicks[#clicks] == "plain", "the menu is closed and the action ran")

-- Closed again: the re-read works as before the menu was ever opened.
r0 = reads
refresh(true)
check(reads == r0 + 1, "refresh(true) reads again once the menu is closed")

-- A static list has nothing to read again.
local sPicked = { x = true }
local sdd, sRefresh = EUI.BuildVisOptsCBDropdown(NewObj("Frame"), 190, 5,
    { { key = "x", label = "Only" }, { key = "y", label = "Other" } },
    function(k) return sPicked[k] and true or false end,
    function(k, v) sPicked[k] = v and true or nil end)
sPicked.y, sPicked.x = true, nil
sRefresh(true)
check(sdd._fontStrings[1]._text == "Other", "a static list takes refresh(true) as a plain refresh (reads "
    .. tostring(sdd._fontStrings[1]._text) .. ")")

print(string.format("%d checks, %d failed", count, fails))
if fails > 0 then error(fails .. " check(s) failed") end
