-- Stub harness: the M+ Portals flyout closes on a click outside it.
-- Cuts the flyout builder from EllesmereUI.lua and its two openers with their
-- click handlers (the Minimap's M+ Portals button, the Chat sidebar icon) and
-- plays mouse presses over a model of frames, visibility and the global mouse
-- press event.
--   a left press anywhere else closes it, out of combat; a press on the flyout
--     (a portal, a hearthstone, its background) or with another button does not
--   a press on the button that toggles it is that button's own click, which
--     closes it and does not open it again
--   the press is heard by the flyout itself, and only while it shows
--   a flyout that shows again with its parent (the whole UI hidden and shown,
--     the chat panel's host) keeps the same rules
-- Every sequence runs with the global press event told before the frame under
-- the cursor takes the press, and after.
-- The model is this file's reading of the client, not the client.
--   lua .tools/tests/test_portal_flyout_click_away.lua   (from the repository root)
local CORE = PF_CORE or "EllesmereUI.lua"
local MINIMAP = PF_MINIMAP or "EllesmereUIMinimap/EUI_Minimap_Indicators.lua"
local CHAT = PF_CHAT or "EllesmereUIChat/EUI_Chat_Sidebar.lua"
local CHATSKIN = PF_CHATSKIN or "EllesmereUIChat/EUI_Chat_Skin.lua"

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

-- The text from `from` to the first `to` after it (after `mid`, when given), all included.
local function Cut(src, what, from, to, mid)
    local a = assert(src:find(from, 1, true), what .. ": start not found")
    local m = a
    if mid then m = assert(src:find(mid, a, true), what .. ": middle not found") end
    local b, e = src:find(to, m, true)
    assert(b, what .. ": end not found")
    return src:sub(a, e)
end

local BuildCore = assert(loadstring("local EllesmereUI = ...\n"
    .. Cut(Read(CORE), "flyout builder", "function EllesmereUI.CreatePortalFlyout(opts)", "\nend\n")
    .. "return EllesmereUI.CreatePortalFlyout\n", "=PortalFlyout"))

-- The Minimap's opener and the button whose click calls it.
local BuildMinimap = assert(loadstring(
    "local EllesmereUI, EBS, MO_Evaluate, GetInteractableBtnSize, GetFFD, GetCustomTooltipScale = ...\n"
    .. "local _portalFlyout\nlocal function SetPortalFlyout(v) _portalFlyout = v end\n"
    .. Cut(Read(MINIMAP), "minimap opener", "local function ToggleMinimapPortalFlyout(anchorBtn)", "\nend\n",
        "local function CreatePortalBtn(parent)")
    .. "return CreatePortalBtn, function() return _portalFlyout end\n", "=MinimapOpener"))

-- The Chat sidebar's opener, and the click handler its icon gets.
local BuildChat = assert(loadstring("local ECHAT, EUI, GetFont, BG_R, BG_G, BG_B = ...\nlocal _portalFlyout\n"
    .. Cut(Read(CHAT), "chat opener", "function ECHAT.TogglePortalFlyout(anchorBtn)", "\nend\n")
    .. "return function() return _portalFlyout end\n", "=ChatOpener"))
local DressChatIcon = assert(loadstring("local ECHAT, portalBtn = ...\n"
    .. Cut(Read(CHATSKIN), "chat icon click", 'portalBtn:SetScript("OnClick", function(self)', "end)") .. "\n",
    "=ChatIcon"))

-------------------------------------------------------------------------------
--  The world
-------------------------------------------------------------------------------
local W
local Noop = function() end

-- A widget method this model has no use for does nothing; a plain field reads nil.
local function Index(class)
    return function(_, k)
        local v = class[k]
        if v ~= nil then return v end
        if type(k) == "string" and k:find("^%u") then return Noop end
    end
end

local Region = {}
local RegionMT = { __index = Index(Region) }
function Region:Show() self._shown = true end
function Region:Hide() self._shown = false end
function Region:SetShown(v) self._shown = v and true or false end
function Region:IsShown() return self._shown end

local Frame = {}
local FrameMT = { __index = Index(Frame) }

local function Visible(f)
    while f do
        if not f._shown then return false end
        f = f._parent
    end
    return true
end

local function Run(f, script, ...)
    local list = f._scripts[script]
    if not list then return end
    local copy = { unpack(list) }
    for i = 1, #copy do copy[i](f, ...) end
end

local function Subtree(f, out)
    out[#out + 1] = f
    for _, c in ipairs(f._children) do Subtree(c, out) end
    return out
end

-- Runs `change`, then OnShow / OnHide on every frame under `f` whose visibility it flipped.
local function Flip(f, change)
    local nodes, was = Subtree(f, {}), {}
    for i, n in ipairs(nodes) do was[i] = Visible(n) end
    change()
    for i, n in ipairs(nodes) do
        local now = Visible(n)
        if now ~= was[i] then Run(n, now and "OnShow" or "OnHide") end
    end
end

-- A frame with secure children is protected: addon code cannot show, hide, move or
-- scale it in combat (the client refuses the call and reports a blocked action).
local function Refused(f)
    if f._protected and W.combat then
        W.blocked = W.blocked + 1
        return true
    end
end

local function SetShown(f, v)
    if Refused(f) or f._shown == v then return end
    Flip(f, function() f._shown = v end)
end

function Frame:Show() SetShown(self, true) end
function Frame:Hide() SetShown(self, false) end
function Frame:SetShown(v) SetShown(self, v and true or false) end
function Frame:IsShown() return self._shown end
function Frame:IsVisible() return Visible(self) end
function Frame:GetParent() return self._parent end
function Frame:SetParent(p)
    if Refused(self) or self._parent == p then return end
    Flip(self, function()
        local old = self._parent
        if old then
            for i, c in ipairs(old._children) do
                if c == self then table.remove(old._children, i) break end
            end
        end
        self._parent = p
        if p then p._children[#p._children + 1] = self end
    end)
end
-- SetScript drops what was hooked before it; HookScript runs after what is there.
function Frame:SetScript(k, fn) self._scripts[k] = fn and { fn } or nil end
function Frame:HookScript(k, fn)
    local list = self._scripts[k]
    if not list then list = {}; self._scripts[k] = list end
    list[#list + 1] = fn
end
function Frame:GetScript(k) local list = self._scripts[k]; return list and list[1] end
function Frame:RegisterEvent(e) self._events[e] = true end
function Frame:RegisterUnitEvent(e, unit) self._events[e] = unit end
function Frame:UnregisterEvent(e) self._events[e] = nil end
function Frame:UnregisterAllEvents() for e in pairs(self._events) do self._events[e] = nil end end
-- The cursor is inside the frame's rect, whether or not the frame shows: on the
-- frame itself, on one of its descendants, or on the flyout's own background.
function Frame:IsMouseOver()
    local at = W.at
    if at == self then return true end
    if at == "flyoutbg" then return self._name ~= nil and self._name:find("PortalFlyout$") ~= nil end
    local f = type(at) == "table" and at._parent
    while f do
        if f == self then return true end
        f = f._parent
    end
    return false
end
function Frame:GetEffectiveScale() return 1 end
function Frame:GetTop() return 500 end
function Frame:GetBottom() return 474 end
function Frame:GetLeft() return 800 end
function Frame:GetRight() return 826 end
function Frame:GetFrameLevel() return self._level or 1 end
function Frame:SetFrameLevel(l) self._level = l end
function Frame:CreateTexture() return setmetatable({ _shown = true }, RegionMT) end
function Frame:CreateFontString() return setmetatable({ _shown = true }, RegionMT) end
function Frame:SetAttribute(k, v)
    if W.combat then W.blocked = W.blocked + 1 return end
    self._attrs[k] = v
end
function Frame:SetPoint(...) if not Refused(self) then self._points[#self._points + 1] = { ... } end end
function Frame:ClearAllPoints() if not Refused(self) then self._points = {} end end
function Frame:SetScale(s) if not Refused(self) then self._scale = s end end

local function NewFrame(kind, name, parent, template)
    local f = setmetatable({ _kind = kind, _name = name, _parent = parent, _shown = true, _children = {},
        _scripts = {}, _events = {}, _attrs = {}, _points = {} }, FrameMT)
    if parent then parent._children[#parent._children + 1] = f end
    if template and template:find("SecureActionButtonTemplate", 1, true) then
        f._secure = true
        local p = f
        while p and p._parent do p._protected = true; p = p._parent end
    end
    W.frames[#W.frames + 1] = f
    return f
end

local function Fire(event, ...)
    local list = {}
    for _, f in ipairs(W.frames) do
        if f._events[event] then list[#list + 1] = f end
    end
    local first = ...
    for _, f in ipairs(list) do
        local reg = f._events[event]
        if reg == true or (reg and reg == first) then Run(f, "OnEvent", event, ...) end
    end
end

local function Listeners(event)
    local out = {}
    for _, f in ipairs(W.frames) do
        if f._events[event] then out[#out + 1] = f end
    end
    return out
end

local function Named(name)
    for _, f in ipairs(W.frames) do
        if f._name == name then return f end
    end
    error("no frame named " .. name)
end

-- The frame that takes a click at the cursor: a visible button there.
local function Receiver()
    local at = W.at
    if type(at) == "table" and at._kind == "Button" and Visible(at) then return at end
end

local function Move(at) W.at = at end

-- The secure buttons act on the press too; a plain button clicks on a left release.
local function Press(at, button)
    button = button or "LeftButton"
    W.at, W.button = at, button
    local function Global() Fire("GLOBAL_MOUSE_DOWN", button) end
    local function Local()
        local r = Receiver()
        W.down = r
        if r and r._secure then
            W.clicks[r] = (W.clicks[r] or 0) + 1
            Run(r, "PostClick", button, true)
        end
    end
    if W.globalFirst then Global(); Local() else Local(); Global() end
end

local function Release()
    local r = W.down
    W.down = nil
    Fire("GLOBAL_MOUSE_UP", W.button)
    if r and r == Receiver() then
        if r._secure then
            Run(r, "PostClick", W.button, false)
        elseif W.button == "LeftButton" then
            Run(r, "OnClick", W.button, false)
        end
    end
end

local function Click(at, button) Press(at, button); Release() end

local function Load(kind, globalFirst)
    W = { kind = kind, globalFirst = globalFirst, combat = false, at = "world", frames = {}, clicks = {}, ffd = {},
        blocked = 0, built = 0, mo = 0, housing = 0, otherClicks = 0 }
    CreateFrame = NewFrame
    UIParent = NewFrame("Frame", "UIParent")
    -- With no frame under it, the cursor is on the game world, which it never leaves.
    W.world = { IsMouseOver = function() return true end, IsVisible = function() return true end }
    GetMouseFoci = function() return { Receiver() or W.world } end
    InCombatLockdown = function() return W.combat end
    C_Spell = {
        GetSpellInfo = function(id) return { iconID = id, name = "Spell " .. id } end,
        GetSpellCooldown = function() return { startTime = 0, duration = 0 } end,
    }
    IsPlayerSpell = function() return true end
    PlayerHasToy = function() return false end
    C_Container = { GetItemCooldown = function() return 0, 0 end }
    C_ToyBox = { GetToyInfo = function() return 1, "Toy" end }
    HousingFramesUtil = { ToggleHousingDashboard = function() W.housing = W.housing + 1 end }
    GameTooltip = setmetatable({}, { __index = function() return Noop end })
    EllesmereUI = nil

    local E = {
        SEASON_PORTALS = {},
        L = function(s) return s end,
        ResolveHearthSlot = function() return "item", 6948, "tex" end,
        ResolveDalaranSlot = function() return "spell", 1001, "tex" end,
        ResolveHousingSlot = function() return "housing", nil, "tex" end,
        PadNative = function() return false end,
        RaiseGamePadCursor = Noop,
        RegisterEscapeClose = Noop,
        GetFontPath = function() return "Fonts\\FRIZQT__.TTF" end,
        SlugFlag = function(s) return s end,
        ShowWidgetTooltip = Noop,
        HideWidgetTooltip = Noop,
    }
    for i = 1, 8 do E.SEASON_PORTALS[i] = { spellID = 9000 + i, short = "D" .. i } end
    local Create = BuildCore(E)
    E.CreatePortalFlyout = function(opts)
        W.built = W.built + 1
        return Create(opts)
    end

    W.other = NewFrame("Button", nil, UIParent)
    W.other:SetScript("OnClick", function() W.otherClicks = W.otherClicks + 1 end)

    if kind == "minimap" then
        W.prefix = "EUIMinimap"
        local EBS = { db = { profile = { minimap = {} } },
            _Grow = { Dir = function() return "left" end, TT = function() return "ANCHOR_LEFT" end } }
        local CreatePortalBtn, Flyout = BuildMinimap(E, EBS, function() W.mo = W.mo + 1 end,
            function() return 26 end,
            function(f)
                local d = W.ffd[f]
                if not d then d = {}; W.ffd[f] = d end
                return d
            end,
            function() return 1 end)
        W.toggleHost = NewFrame("Frame", nil, UIParent)   -- the button row
        W.toggle = CreatePortalBtn(W.toggleHost)
        W.toggle2 = CreatePortalBtn(W.toggleHost)
        W.Flyout = Flyout
        W.root = UIParent                                 -- the whole UI, hidden and shown
    else
        W.prefix = "EUIChat"
        W.root = NewFrame("Frame", nil, UIParent)         -- the chat panel's host
        W.toggleHost = NewFrame("Frame", nil, W.root)     -- the sidebar
        local ECHAT = { DB = function() return { sidebarRight = false } end }
        function ECHAT.HostPopup(f)
            if f:GetParent() ~= W.root then f:SetParent(W.root) end
        end
        W.Flyout = BuildChat(ECHAT, E, function() return "font" end, 0, 0, 0)
        W.toggle = NewFrame("Button", nil, W.toggleHost)
        DressChatIcon(ECHAT, W.toggle)
        W.toggle2 = NewFrame("Button", nil, W.toggleHost)
        DressChatIcon(ECHAT, W.toggle2)
    end
end

local function Open()
    local f = W.Flyout()
    return f ~= nil and f:IsVisible()
end

local function Heard() return #Listeners("GLOBAL_MOUSE_DOWN") end

-------------------------------------------------------------------------------
--  The rules, for each opener and each order of the press
-------------------------------------------------------------------------------
local function Rules(kind, globalFirst)
    local tag = kind .. (globalFirst and ": " or " (frame first): ")
    Load(kind, globalFirst)

    -- 1. Built on first use; the flyout itself listens, and only while it shows
    check(W.Flyout() == nil and W.built == 0 and Heard() == 0, tag .. "nothing is built or listening before the first open")
    Click(W.toggle)
    local f = W.Flyout()
    check(Open() and W.built == 1, tag .. "a click on its button opens the flyout")
    local heard = Listeners("GLOBAL_MOUSE_DOWN")
    check(#heard == 1 and heard[1] == f, tag .. "while it shows, the flyout itself hears the press and nothing else does")
    check(f._toggle == W.toggle, tag .. "the opener names the clicked button as its toggle")

    -- 2. A left press anywhere else closes it
    Press("world")
    check(not Open(), tag .. "a left press outside closes it")
    check(Heard() == 0, tag .. "and nothing listens once it is closed")
    Release()
    check(not Open() and not f:IsShown(), tag .. "the release changes nothing")
    if kind == "minimap" then
        check(W.mo == 2, tag .. "the mouseover row is evaluated again on open and on close")
    end
    Click(W.toggle)
    check(Open() and Heard() == 1, tag .. "the next click on its button opens it again")
    Click(W.other)
    check(not Open() and W.otherClicks == 1, tag .. "a click on another frame closes it and still reaches that frame")

    -- 3. Other mouse buttons and presses on the flyout leave it open
    Click(W.toggle)
    Click("world", "RightButton")
    check(Open(), tag .. "a right press outside leaves it open")
    Click("world", "MiddleButton")
    check(Open(), tag .. "a middle press outside leaves it open")
    local portal = Named(W.prefix .. "Portal3")
    Click(portal)
    check(Open() and W.clicks[portal] == 1, tag .. "a press on a portal leaves it open and reaches the portal")
    Click("flyoutbg")
    check(Open(), tag .. "a press on the flyout's own background leaves it open")
    local hearth = Named(W.prefix .. "Hearth1")
    Click(hearth)
    check(Open() and W.clicks[hearth] == 1, tag .. "a press on a hearthstone leaves it open and reaches the button")
    Click(Named(W.prefix .. "Hearth3"))
    check(not Open() and W.housing == 1 and Heard() == 0, tag .. "the housing button still closes it itself")

    -- 4. Its own button: the press is the button's, whose click closes it
    Click(W.toggle)
    Press(W.toggle)
    check(Open(), tag .. "a press on its button is left to the button")
    Release()
    check(not Open() and Heard() == 0, tag .. "whose click closes it, and it is not opened again")
    Click(W.toggle)
    Press(W.toggle); Move("world"); Release()
    check(Open(), tag .. "a press on its button released elsewhere (a drag) leaves it open")
    Click("world")
    check(not Open(), tag .. "and the next press outside closes it")

    -- 5. Another button that toggles it
    Click(W.toggle)
    Click(W.toggle2)
    check(Open() and f._toggle == W.toggle2, tag .. "a click on another button that toggles it opens it for that button")
    Click(W.toggle2)
    check(not Open(), tag .. "whose next click closes it")
    Click(W.toggle)
    check(Open() and f._toggle == W.toggle, tag .. "and the first button is named again on its own open")

    -- 6. Combat: nothing is hidden from the press (the flyout is protected), and combat start closes it
    W.combat = true
    Click("world")
    check(Open() and W.blocked == 0, tag .. "in combat a press outside hides nothing")
    W.combat = false
    Fire("PLAYER_REGEN_DISABLED")
    W.combat = true
    check(not Open() and Heard() == 0, tag .. "combat start closes it as before")
    Click(W.toggle)
    check(not Open() and W.blocked == 0, tag .. "and its button opens nothing in combat")
    W.combat = false

    -- 7. Hidden with its parent and shown again, the cursor elsewhere by then
    Click(W.toggle)
    W.root:Hide()
    check(not Open() and f:IsShown() and Heard() == 0, tag .. "hidden with its parent, it stops listening")
    Move("world")
    W.root:Show()
    check(Open() and Heard() == 1, tag .. "shown again with its parent, it listens again")
    Click("world")
    check(not Open() and not f:IsShown(), tag .. "and a left press outside closes it")
    Click(W.toggle)
    W.root:Hide(); Move("world"); W.root:Show()
    Press(W.toggle)
    check(Open(), tag .. "after that, a press on its button is still the button's")
    Release()
    check(not Open(), tag .. "whose click closes it")

    -- 8. Its button hidden: a press where the button would be closes it
    Click(W.toggle)
    W.toggleHost:Hide()
    Press(W.toggle)
    check(not Open(), tag .. "a press where its hidden button would be closes it")
    Release()
    W.toggleHost:Show()

    -- 9. The flyout's other events beside the press
    Click(W.toggle)
    Fire("UNIT_SPELLCAST_START", "player", "cast", portal.spellID)
    check(portal._castHL:IsShown(), tag .. "a portal cast lights its button")
    Click("flyoutbg")
    check(Open() and portal._castHL:IsShown(), tag .. "a press on the flyout leaves the cast highlight alone")
    Fire("UNIT_SPELLCAST_STOP", "player", "cast", portal.spellID)
    check(not portal._castHL:IsShown(), tag .. "the cast's end clears it")
    Click("world")
    check(not Open(), tag .. "and a left press outside closes it")

    -- 10. Nothing piles up
    local frames, shows, hides = #W.frames, #f._scripts.OnShow, #f._scripts.OnHide
    for _ = 1, 5 do
        Click(W.toggle)
        Click("world")
    end
    check(W.built == 1 and #W.frames == frames, tag .. "opening and closing builds nothing new")
    check(#f._scripts.OnShow == shows and #f._scripts.OnHide == hides, tag .. "and hooks nothing new")
    check(not Open() and Heard() == 0, tag .. "closed, it hears nothing")
    check(W.blocked == 0, tag .. "no blocked action in the whole run")
end

Rules("minimap", true)
Rules("minimap", false)
Rules("chat", true)
Rules("chat", false)

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print("PASS test_portal_flyout_click_away (" .. count .. " checks)")
