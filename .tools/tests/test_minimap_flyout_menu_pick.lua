-- Stub harness: the Minimap's Addon Buttons flyout and a grouped button's own
-- right-click menu. The flyout closes on a left press outside it; a button's
-- menu is a frame of its own outside the flyout, the game closes a menu once
-- its owner is no longer visible, and a menu entry acts on the release. So a
-- flyout that hid on the press over an entry took the menu with it and the
-- choice never ran. While any menu is open the flyout stays.
-- Loads EUI_Minimap_Flyout.lua over frame stubs, builds the flyout through
-- I.BuildFlyoutContents and drives its click-away with a model of the game's
-- menu manager (closed by a mouse press outside it, and from its own update
-- once its owner is not visible; an entry picks on release) and of an
-- old-style dropdown list (closed by a press outside it, no owner check).
-- The game's order of the mouse-down event and the two updates is not known,
-- so every case runs in all four orders.
--   lua .tools/tests/test_minimap_flyout_menu_pick.lua   (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return src
end

-------------------------------------------------------------------------------
--  Frame stubs
-------------------------------------------------------------------------------
local MOUSE = { over = {}, focus = nil, leftDown = false }
local Frame = {}
Frame.__index = Frame
local function NewFrame(kind, name, parent)
    local f = setmetatable({ kind = kind, name = name, parent = parent, shown = true, scripts = {}, hooks = {} }, Frame)
    if name then _G[name] = f end
    return f
end
function Frame:GetParent() return self.parent end
function Frame:SetParent(p) self.parent = p end
function Frame:IsShown() return self.shown end
function Frame:IsVisible()
    if not self.shown then return false end
    if self.parent then return self.parent:IsVisible() end
    return true
end
function Frame:_fire(name, ...)
    local s = self.scripts[name]
    if s then s(self, ...) end
    local h = self.hooks[name]
    if h then for i = 1, #h do h[i](self, ...) end end
end
function Frame:Show() if self.shown then return end self.shown = true; self:_fire("OnShow") end
function Frame:Hide() if not self.shown then return end self.shown = false; self:_fire("OnHide") end
function Frame:SetScript(name, fn) self.scripts[name] = fn end
function Frame:GetScript(name) return self.scripts[name] end
function Frame:HookScript(name, fn)
    self.hooks[name] = self.hooks[name] or {}
    table.insert(self.hooks[name], fn)
end
function Frame:HasScript() return true end
function Frame:IsMouseOver() return MOUSE.over[self] == true end
function Frame:IsForbidden() return false end
function Frame:GetFrameLevel() return 1 end
local noop = function() end
for _, m in ipairs({ "SetFrameStrata", "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor",
    "SetClampedToScreen", "SetSize", "ClearAllPoints", "SetPoint", "SetAlpha", "SetFrameLevel" }) do
    Frame[m] = noop
end

UIParent = NewFrame("Frame", "UIParent")
WorldFrame = NewFrame("Frame", "WorldFrame")
function CreateFrame(kind, name, parent) return NewFrame(kind, name, parent) end
function IsMouseButtonDown(b) return b == "LeftButton" and MOUSE.leftDown end
function GetMouseFoci() return { MOUSE.focus } end
function InCombatLockdown() return false end
EllesmereUI = { OverlayParent = function() return UIParent end, TrackOverlay = noop }

-------------------------------------------------------------------------------
--  The menus: the game's menu manager, and an old-style list by its global name
-------------------------------------------------------------------------------
local menu      -- the open menu: { owner, frame, entry }
local legacy    -- the open old-style list: { list, entry }
local chose, why
local function CloseMenu(reason)
    if menu then why = reason; menu.frame:Hide(); menu = nil end
end
local manager = { IsAnyMenuOpen = function() return menu ~= nil end }
local MENU_API = { GetManager = function() return manager end }
Menu = MENU_API
local function OpenMenu(owner)
    local frame = NewFrame("Frame", nil, UIParent)
    menu = { owner = owner, frame = frame, entry = NewFrame("Button", nil, frame) }
    return menu.entry
end
local function OpenLegacy(name)
    local list = _G[name] or NewFrame("Button", name, UIParent)
    list.shown = true
    legacy = { list = list, entry = NewFrame("Button", nil, list) }
    return legacy.entry
end
local function Within(f, root)
    while f do if f == root then return true end f = f.parent end
    return false
end
local function GlobalMouseDown()
    if menu and not Within(MOUSE.focus, menu.frame) then CloseMenu("a press outside it") end
    if legacy and not Within(MOUSE.focus, legacy.list) then legacy.list:Hide(); legacy = nil end
end
local function Release()
    if menu and MOUSE.focus == menu.entry then chose = "menu"; CloseMenu("its entry was picked") end
    if legacy and MOUSE.focus == legacy.entry then chose = "legacy"; legacy.list:Hide(); legacy = nil end
end

-------------------------------------------------------------------------------
--  Load the file and build the flyout
-------------------------------------------------------------------------------
local ffd = {}
local EBS = { db = { profile = { minimap = {} } }, _MinimapBlizz = function() return false end }
local I = {
    _addonVisible = {}, cachedAddonButtons = {}, EG = { r = 1, g = 1, b = 1 }, EBS = EBS,
    flyoutOwnedFrames = {}, GetFFD = function(f) ffd[f] = ffd[f] or {} return ffd[f] end,
    QueueApplyAll = noop, moEvaluateSetters = {}, flyoutToggleSetters = {}, flyoutPanelSetters = {},
}
local panel
I.SetFlyoutPanel = function(v) panel = v for _, s in ipairs(I.flyoutPanelSetters) do s(v) end end
I.SetFlyoutToggle = function(v) for _, s in ipairs(I.flyoutToggleSetters) do s(v) end end
assert(loadstring(ReadSource("EllesmereUIMinimap/EUI_Minimap_Flyout.lua"), "=EUI_Minimap_Flyout.lua"))("EllesmereUIMinimap", { _internals = I })
assert(I.broken == false, "the flyout file did not load to its end")
I.BuildFlyoutContents()
assert(panel and not panel:IsShown(), "the flyout does not start hidden")
assert(panel.scripts.OnUpdate == nil, "a hidden flyout runs an update")
assert(type(EBS._AnyDropdownOpen) == "function", "the menu check is gone")
local button = NewFrame("Button", nil, panel)   -- an addon button kept inside the flyout

-------------------------------------------------------------------------------
--  One press: the frames it is held for, then the release
-------------------------------------------------------------------------------
local function Tick(menuFirst)
    local function PanelUpdate() local s = panel.scripts.OnUpdate if s then s(panel, 0.016) end end
    local function MenuUpdate()
        if menu and menu.owner and not menu.owner:IsVisible() then CloseMenu("its owner is not visible") end
    end
    if menuFirst then MenuUpdate() PanelUpdate() else PanelUpdate() MenuUpdate() end
end
local function Press(focus, frames, eventFirst, menuFirst)
    MOUSE.focus, MOUSE.leftDown = focus, true
    if eventFirst then GlobalMouseDown() Tick(menuFirst) else Tick(menuFirst) GlobalMouseDown() end
    for _ = 2, frames do Tick(menuFirst) end
    MOUSE.leftDown = false
    Release()
    Tick(menuFirst)
end
local function Reset()
    panel:Hide() panel:Show()
    menu, legacy, chose, why = nil, nil, nil, nil
    MOUSE.over = {}
    for _, name in ipairs({ "DropDownList1", "L_DropDownList1" }) do if _G[name] then _G[name].shown = false end end
end

local n = 0
local function check(cond, msg)
    n = n + 1
    assert(cond, msg)
end

for _, eventFirst in ipairs({ true, false }) do
    for _, menuFirst in ipairs({ true, false }) do
        local tag = ("[mouse-down event %s, the menu's update %s] "):format(eventFirst and "first" or "after", menuFirst and "first" or "after")

        -- 1. a grouped button's menu: press an entry, hold, release: the choice runs
        Reset()
        local entry = OpenMenu(button)
        Press(entry, 5, eventFirst, menuFirst)
        check(chose == "menu", tag .. "the menu choice did not run (the menu closed because " .. tostring(why) .. ")")
        check(panel:IsShown(), tag .. "the flyout closed under a press on its button's menu")

        -- 2. the same menu open and a press on the world, held: the menu closes,
        --    and the flyout with it on the same press
        Reset()
        OpenMenu(button)
        Press(WorldFrame, 5, eventFirst, menuFirst)
        check(menu == nil and chose == nil, tag .. "a press on the world left the menu open")
        check(not panel:IsShown(), tag .. "a held press on the world left the flyout open")

        -- 3. no menu open: a press on the world closes the flyout, as before
        Reset()
        Press(WorldFrame, 3, eventFirst, menuFirst)
        check(not panel:IsShown(), tag .. "with no menu open a press on the world left the flyout open")
        check(panel.scripts.OnUpdate == nil, tag .. "the closed flyout still runs its update")

        -- 4. the flyout keeps its own rules while a press is inside it or on its toggle
        Reset()
        MOUSE.over[panel] = true
        Press(button, 3, eventFirst, menuFirst)
        check(panel:IsShown(), tag .. "a press on a button inside the flyout closed it")
        -- a gap between its buttons: the pointer is over the flyout, the focus is not one of its children
        Reset()
        MOUSE.over[panel] = true
        Press(WorldFrame, 3, eventFirst, menuFirst)
        check(panel:IsShown(), tag .. "a press on the flyout's own area closed it")
        -- a child that reaches outside the flyout's box (a button's own flyout or tooltip-like child)
        Reset()
        Press(button, 3, eventFirst, menuFirst)
        check(panel:IsShown(), tag .. "a press on a child outside the flyout's box closed it")

        -- 5. an old-style list (the game's and a dropdown library's): its choice
        --    runs and the flyout stays open under it
        for _, name in ipairs({ "DropDownList1", "L_DropDownList1" }) do
            Reset()
            local le = OpenLegacy(name)
            check(EBS._AnyDropdownOpen() == true, tag .. name .. " shown does not count as a menu")
            Press(le, 5, eventFirst, menuFirst)
            check(chose == "legacy", tag .. name .. ": the choice did not run")
            check(panel:IsShown(), tag .. name .. ": the flyout closed under the list")
            check(EBS._AnyDropdownOpen() == false, tag .. name .. " hidden still counts as a menu")
        end
    end
end

-- 6. the menu check alone: nothing open, the manager's answer, a client with
--    no menu system or no old-style list at all (nothing raises)
Reset()
check(EBS._AnyDropdownOpen() == false, "nothing open counts as a menu")
OpenMenu(button)
check(EBS._AnyDropdownOpen() == true, "an open menu does not count")
menu = nil
Menu = nil
DropDownList1, L_DropDownList1 = nil, nil
check(EBS._AnyDropdownOpen() == false, "no menu system and no list: the check did not answer no")
Menu = { GetManager = function() return nil end }
check(EBS._AnyDropdownOpen() == false, "a client without a menu manager raised or answered yes")
Menu = { GetManager = function() return {} end }
check(EBS._AnyDropdownOpen() == false, "a manager without the open-menu call raised or answered yes")
Menu = MENU_API
-- and without the menu system a world press still closes the flyout
Menu = nil
Reset()
Press(WorldFrame, 3, true, true)
check(not panel:IsShown(), "no menu system: a press on the world left the flyout open")
Menu = MENU_API

print(("minimap flyout menu pick harness: %d checks, ok"):format(n))
