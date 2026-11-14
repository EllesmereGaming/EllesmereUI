-- Stub harness: the hover tooltip of the options panel's shared dropdowns.
-- One helper pair in EllesmereUIOptions/EllesmereUI_Widgets.lua (ShowDropdownTip / HideDropdownTip)
-- serves every shared dropdown: BuildDropdownControl's (WireLazyDropdown before the first open,
-- WireDropdownScripts after) and the three checkbox dropdowns.
--   * a value cut off with "..." shows in full on hover and when the list closes under the cursor;
--   * a button's own tooltip (_ttText with _ttOpts) shows as it is, and with a cut value the
--     value stands above it (the own text translated first, since the joined text is no key);
--   * nothing shows while the list is open, a click hides it, a leave hides it;
--   * a secret truncation answer never shows the value;
--   * the four pages that used to hook a tooltip onto a checkbox dropdown set it as the button's
--     own tooltip instead.
-- The real helpers and wiring are cut from the widget base file and the real checkbox dropdown
-- file is loaded whole, over frame stubs that keep scripts, shown state and text.
--   lua .tools/tests/test_dropdown_tip.lua   (from the repository root)
local BASE = "EllesmereUIOptions/EllesmereUI_Widgets.lua"
local WIDGET = "EllesmereUIOptions/EllesmereUI_Widgets_CheckboxDropdowns.lua"

local fails, count = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        if fails <= 14 then print("  FAIL: " .. msg) end
    end
end

local function Read(path)
    local fh = assert(io.open(path, "rb"))
    local s = fh:read("*a"):gsub("\r\n", "\n")
    fh:close()
    if s:sub(1, 3) == "\239\187\191" then s = s:sub(4) end
    return s
end
local function Cut(src, first, stop)
    local a = assert(src:find(first, 1, true), "first line not found: " .. first)
    local b = assert(src:find(stop, a, true), "last line not found after: " .. first)
    return src:sub(a, b - 1)
end

-------------------------------------------------------------------------------
--  Frame stubs
-------------------------------------------------------------------------------
local Noop = function() end
local Zero = function() return 0 end
local One = function() return 1 end
local False = function() return false end
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
    return setmetatable({ _kind = kind, _parent = parent, _shown = true, _scripts = {}, _fontStrings = {} }, ObjMT)
end

-------------------------------------------------------------------------------
--  The world
-------------------------------------------------------------------------------
local tips = {} -- every tooltip call, in order: { "show", anchor, text, opts } / { "hide" }
local secret = false

function wipe(t) for k in pairs(t) do t[k] = nil end return t end
strlower, strfind = string.lower, string.find
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function IsMouseButtonDown() return false end
function GetCursorPosition() return 0, 0 end
function issecretvalue() return secret end
UIParent = NewObj("Frame")

-- A catalog with one translated tooltip: the own text must be translated before it is joined.
local CATALOG = { ["Own text"] = "Eigener Text" }
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
    L = function(s) return CATALOG[s] or s end,
    Lf = function(s, ...) return s:format(...) end,
    MakeRoundedBorder = function() return NewObj("Border") end,
    MakeDropdownArrow = function() return NewObj("Texture") end,
    OverlayParent = function() return UIParent end,
    GetPopupScale = One,
    ShowWidgetTooltip = function(anchor, text, opts)
        if type(text) == "function" then text = text() end
        tips[#tips + 1] = { "show", anchor, text, opts }
    end,
    HideWidgetTooltip = function() tips[#tips + 1] = { "hide" } end,
}, { __index = function(_, k)
    -- Every other helper does nothing and answers nil; fields stay nil.
    if type(k) == "string" and k:match("^%u") then return Noop end
end })

-- The real helpers and the real dropdown wiring, cut from the widget base file.
local WSRC = Read(BASE)
local chunk = "local EllesmereUI = ...\n"
    .. "local ShowWidgetTooltip, HideWidgetTooltip = EllesmereUI.ShowWidgetTooltip, EllesmereUI.HideWidgetTooltip\n"
    .. Cut(WSRC, "local function ShowDropdownTip(", "-- Wire OnEnter/OnLeave/OnClick/OnShow/OnHide")
    .. Cut(WSRC, "local function WireDropdownScripts(", "-- Pre-built colour arrays")
    .. Cut(WSRC, "local function WireLazyDropdown(", "-- Fully wired dropdown control")
    .. "\nreturn ShowDropdownTip, HideDropdownTip, WireDropdownScripts, WireLazyDropdown\n"
local ShowTip, HideTip, WireScripts, WireLazy = assert(loadstring(chunk, "=Widgets (the dropdown tooltip and wiring)"))(EUI)
EUI._widgetInternals = { ShowDropdownTip = ShowTip, HideDropdownTip = HideTip }
check(WSRC:find("    ShowDropdownTip = ShowDropdownTip,\n    HideDropdownTip = HideDropdownTip,\n", 1, true) ~= nil,
    "the widget base file does not hand the two helpers to its part files (_widgetInternals)")
_G.EllesmereUI = EUI
assert(loadstring(Read(WIDGET), "=CheckboxDropdowns"))()

local function Count(kind)
    local n = 0
    for i = 1, #tips do if tips[i][1] == kind then n = n + 1 end end
    return n
end
local function Last()
    for i = #tips, 1, -1 do if tips[i][1] == "show" then return tips[i] end end
    return {}
end
local function SetCut(fs, v) fs.IsTruncated = function() return v end end
local function SetMouse(f, v) f.IsMouseOver = function() return v end end

-------------------------------------------------------------------------------
--  The five shared dropdown paths, each as { name, button, label, open menu }
-------------------------------------------------------------------------------
local function VisOpts()
    local dd = EUI.BuildVisOptsCBDropdown(NewObj("Frame"), 170, 5,
        { { key = "a", label = "Item Level" }, { key = "b", label = "Upgrade Track" }, { key = "c", label = "Third" } },
        function(k) return k ~= "c" end, function() end)
    return dd, dd._fontStrings[1], function() return dd._ddMenu end
end
local function Reorder()
    local dd = EUI.BuildReorderCBDropdown(NewObj("Frame"), 170, 5,
        { { key = "a", label = "Alpha Long" }, { key = "b", label = "Beta Long" } },
        function() return true end, function() end, {})
    return dd, dd._fontStrings[1], function() return dd._ddMenu end
end
local function Slider()
    local dd = EUI.BuildSliderDropdown(NewObj("Frame"), 170, 5,
        { { label = "First Amount", min = 0, max = 10, get = function() return 5 end, set = function() end },
          { label = "Second", min = 0, max = 10, get = function() return 0 end, set = function() end } }, {})
    return dd, dd._fontStrings[1], function() return dd._kept and dd._kept.sliderMenu end
end
local COLOURS = {}
for i = 1, 24 do COLOURS[i] = 1 end
local function Lazy()
    local btn = NewObj("Button")
    local lbl = NewObj("FontString", btn)
    lbl._text = "Always, Hide When Inactive"
    local menu
    WireLazy(btn, lbl, NewObj("Texture"), NewObj("Texture"), COLOURS, function()
        menu = NewObj("Frame")
        menu._shown = false
        return menu, function() end
    end)
    return btn, lbl, function() return menu end
end
-- The same dropdown after its list was opened and closed once: WireDropdownScripts' own scripts.
local function Wired()
    local btn, lbl, menu = Lazy()
    btn._scripts.OnClick(btn)
    menu():Hide()
    return btn, lbl, menu
end

local PATHS = {
    { "the checkbox dropdown", VisOpts }, { "the reorder dropdown", Reorder }, { "the slider dropdown", Slider },
    { "a row dropdown before its first open", Lazy }, { "a row dropdown after its first open", Wired },
}
local OPTS = { width = 300 }
for _, path in ipairs(PATHS) do
    local name = path[1]
    -- 1. a value that fits, no tooltip of its own: nothing at all
    do
        local dd, lbl = path[2]()
        SetMouse(dd, true)
        SetCut(lbl, false)
        tips = {}
        dd._scripts.OnEnter(dd)
        dd._scripts.OnLeave(dd)
        check(Count("show") == 0 and Count("hide") == 0, name .. ": a value that fits shows or hides a tooltip")
    end
    -- 2. a cut value: in full on hover, hidden on leave and on a click, back after a close under the cursor
    do
        local dd, lbl, menu = path[2]()
        local full = lbl:GetText()
        SetMouse(dd, true)
        SetCut(lbl, true)
        tips = {}
        dd._scripts.OnEnter(dd)
        check(Count("show") == 1 and Last()[3] == full and Last()[2] == dd, name .. ": a cut value shows " .. tostring(Last()[3]))
        dd._scripts.OnLeave(dd)
        check(Count("hide") == 1, name .. ": leaving does not hide the cut value")
        tips = {}
        dd._scripts.OnEnter(dd)
        dd._scripts.OnClick(dd)
        check(tips[2] and tips[2][1] == "hide" and menu() and menu():IsShown(), name .. ": a click does not hide the tooltip and open the list")
        local n = Count("show")
        dd._scripts.OnLeave(dd)
        dd._scripts.OnEnter(dd)
        check(Count("show") == n, name .. ": a tooltip shows while the list is open")
        menu():Hide()
        check(Count("show") == n + 1 and Last()[3] == full, name .. ": the list closing under the cursor does not show the value again")
        dd._scripts.OnLeave(dd)
        tips = {}
        dd._scripts.OnClick(dd)
        SetMouse(dd, false)
        menu():Hide()
        check(Count("show") == 0, name .. ": a close with the cursor away shows a tooltip")
    end
    -- 3. a tooltip of the button's own, the value fits: the own tooltip with its options
    do
        local dd, lbl, menu = path[2]()
        dd._ttText, dd._ttOpts = "Own text", OPTS
        SetMouse(dd, true)
        SetCut(lbl, false)
        tips = {}
        dd._scripts.OnEnter(dd)
        check(Count("show") == 1 and Last()[3] == "Own text" and Last()[4] == OPTS, name .. ": the button's own tooltip shows as " .. tostring(Last()[3]))
        dd._scripts.OnLeave(dd)
        check(Count("hide") == 1, name .. ": leaving does not hide the own tooltip")
        tips = {}
        dd._scripts.OnEnter(dd)
        dd._scripts.OnClick(dd)
        check(Count("hide") >= 1 and menu():IsShown(), name .. ": a click leaves the own tooltip over the open list")
        local n = Count("show")
        dd._scripts.OnLeave(dd)
        dd._scripts.OnEnter(dd)
        check(Count("show") == n, name .. ": the own tooltip shows while the list is open")
        menu():Hide()
        check(Count("show") == n + 1 and Last()[3] == "Own text" and Last()[4] == OPTS, name .. ": the close under the cursor does not bring the own tooltip back")
        dd._scripts.OnLeave(dd)
    end
    -- 4. both: the full value above the own tooltip, the own text translated first
    do
        local dd, lbl, menu = path[2]()
        local full = lbl:GetText()
        dd._ttText, dd._ttOpts = "Own text", OPTS
        SetMouse(dd, true)
        SetCut(lbl, true)
        tips = {}
        dd._scripts.OnEnter(dd)
        check(Count("show") == 1 and Last()[3] == full .. "\nEigener Text", name .. ": a cut value with an own tooltip shows " .. tostring(Last()[3]))
        check(Last()[4] == OPTS, name .. ": the joined tooltip loses the own tooltip's options")
        dd._scripts.OnLeave(dd)
        check(Count("hide") >= 1, name .. ": leaving does not hide the joined tooltip")
        tips = {}
        dd._scripts.OnClick(dd)
        menu():Hide()
        check(Last()[3] == full .. "\nEigener Text", name .. ": the close under the cursor shows " .. tostring(Last()[3]))
        dd._scripts.OnLeave(dd)
        -- the own tooltip as a function (text that changes) is resolved before the join
        dd._ttText = function() return "Own text" end
        tips = {}
        dd._scripts.OnEnter(dd)
        check(Last()[3] == full .. "\nEigener Text", name .. ": an own tooltip given as a function joins as " .. tostring(Last()[3]))
        dd._scripts.OnLeave(dd)
    end
    -- 5. a truncation answer the game keeps secret is never read: the value does not show
    do
        local dd, lbl = path[2]()
        SetMouse(dd, true)
        SetCut(lbl, true)
        secret = true
        tips = {}
        dd._scripts.OnEnter(dd)
        check(Count("show") == 0, name .. ": a secret answer shows the value")
        dd._scripts.OnLeave(dd)
        dd._ttText = "Own text"
        tips = {}
        dd._scripts.OnEnter(dd)
        check(Count("show") == 1 and Last()[3] == "Own text", name .. ": a secret answer hides the own tooltip, or joins the value")
        dd._scripts.OnLeave(dd)
        secret = false
    end
end

-------------------------------------------------------------------------------
--  The four pages: the tooltip is the button's own, no hand hook
-------------------------------------------------------------------------------
local PAGES = {
    { "EllesmereUIOptions/Nameplates_Options/GeneralPage_Options.lua",
      'cbDD._ttText = "Choose which nameplates stack vertically instead of overlapping."' },
    { "EllesmereUIOptions/Nameplates_Options/ColorsPage_Options.lua",
      'cbDD._ttText = "Chooses which parts of the nameplate show the threat colors; with Health Bar off, the bar keeps its Enemy Types color."' },
    { "EllesmereUIOptions/EUI_Quickdraw_Options.lua",
      'cbDD._ttText = EllesmereUI.L("Choose the specs this action menu works in.")' },
    { "EllesmereUIOptions/ActionBars_Options/XPBarPage_Options.lua", "cbDD._ttText = SLOT_TIP" },
}
for _, page in ipairs(PAGES) do
    local src = Read(page[1])
    check(src:find(page[2], 1, true) ~= nil, page[1] .. ": the checkbox dropdown's tooltip is not set as its own")
    check(src:find('cbDD:HookScript("OnEnter"', 1, true) == nil and src:find('cbDD:HookScript("OnLeave"', 1, true) == nil,
        page[1] .. ": a tooltip is still hooked onto the checkbox dropdown by hand")
end

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print(("PASS test_dropdown_tip (%d checks)"):format(count))
