-- Stub harness: Unlock Mode's top bar buttons and the accent on its overlays.
--   * the - / + scale buttons take their mouse from the bar's mouse cut alone (never from their
--     greyed state), so a bar hidden by Hover Top Bar or Shift takes no click through them;
--   * Exit, Save & Exit, - and + explain themselves through the bar tooltip, a greyed - / + says
--     why, and an open tooltip follows a click;
--   * mover borders, the Blizzard-owned info overlays and the Save & Exit outline and label follow
--     an accent change through the accent registry (a hovered or selected one on leave).
-- The pieces are cut out of the real files by their first and last lines and run over stubs.
--   lua .tools/tests/test_unlock_topbar_buttons.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local function read(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local s = f:read("*a")
    f:close()
    return (s:gsub("\r\n", "\n"))
end
local function cut(src, first, last)
    local a = assert(src:find(first, 1, true), "first line not found: " .. first)
    local b = assert(src:find(last, a + #first, true), "last line not found after: " .. first)
    return src:sub(a, b - 1)
end

local fails, count = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        if fails <= 14 then print("  FAIL: " .. msg) end
    end
end

local SESSION = read("EUI_UnlockMode_Session.lua")
local MOVERS = read("EUI_UnlockMode_Movers.lua")
local TOOLS = read("EUI_UnlockMode_Tools.lua")

-------------------------------------------------------------------------------
-- Stubs: frames that keep their scripts, mouse and alpha; the bar tooltip
-------------------------------------------------------------------------------
local tipOwner, tipText, tipShows = nil, nil, 0
local function fontString()
    local o = {}
    function o:SetFont() end
    function o:SetPoint() end
    function o:SetWordWrap() end
    function o:SetAlpha() end
    function o:SetText(t) self.text = t end
    function o:SetTextColor(r, g, b, a) self.c = { r, g, b, a } end
    return o
end
local function frame(kind)
    local o = { scripts = {}, hooks = {}, mouse = (kind == "Button"), shown = true, alpha = 1, scale = 1, mouseOver = false }
    function o:SetSize() end
    function o:SetPoint() end
    function o:SetAllPoints() end
    function o:ClearAllPoints() end
    function o:SetHeight() end
    function o:SetFrameStrata() end
    function o:SetFrameLevel(l) self.level = l end
    function o:GetFrameLevel() return self.level or 1 end
    function o:CreateFontString() return fontString() end
    function o:CreateTexture()
        local t = {}
        function t:SetAllPoints() end
        function t:SetColorTexture() end
        return t
    end
    function o:SetScript(n, f) self.scripts[n] = f end
    function o:GetScript(n) return self.scripts[n] end
    function o:HookScript(n, f)
        self.hooks[n] = self.hooks[n] or {}
        table.insert(self.hooks[n], f)
    end
    function o:EnableMouse(v) self.mouse = v and true or false end
    function o:IsMouseEnabled() return self.mouse end
    function o:IsMouseOver() return self.mouseOver end
    function o:SetScale(s) self.scale = s end
    function o:GetScale() return self.scale end
    function o:GetEffectiveScale() return self.scale end
    function o:Show()
        if not self.shown then
            self.shown = true
            for _, h in ipairs(self.hooks.OnShow or {}) do h(self) end
        end
    end
    function o:Hide()
        if self.shown then
            self.shown = false
            for _, h in ipairs(self.hooks.OnHide or {}) do h(self) end
        end
    end
    function o:IsShown() return self.shown end
    function o:SetAlpha(a) self.alpha = a end
    function o:GetAlpha() return self.alpha end
    function o:GetLeft() return 0 end
    function o:GetRight() return 1144 end
    function o:HasFocus() return false end
    return o
end
local function ShowBarTip(owner, tip)
    if type(tip) == "function" then tip = tip() end
    tipOwner, tipText, tipShows = owner, tip, tipShows + 1
end
local function HideTip() tipOwner = nil end
local function same(c, r, g, b, a)
    return c and c[1] == r and c[2] == g and c[3] == b and (a == nil or c[4] == a)
end

-- The real accent registry: RegAccent (EllesmereUI.lua) and the pass that runs its entries
-- (EllesmereUI_UICore.lua). E is the table the cut code registers on; Update(r, g, b) is a change.
local function Registry()
    local regBody = cut(read("EllesmereUI.lua"), "local _accentElements = { _idx = {} }", "\nlocal DARK_BG")
    local updBody = cut(read("EllesmereUI_UICore.lua"), "local function UpdateAccentElements(r, g, b)", "\n--- Internal: apply accent instantly")
    local env = setmetatable({ EllesmereUI = {} }, { __index = _G })
    local chunk = assert(loadstring(regBody .. "\nEllesmereUI.RegAccent = RegAccent\nEllesmereUI._accentElements = _accentElements\n"
        .. "local _gradStart, _gradEnd = {}, {}\n" .. updBody .. "\nreturn UpdateAccentElements", "=the accent registry"))
    setfenv(chunk, env)
    return env.EllesmereUI, chunk()
end

-------------------------------------------------------------------------------
-- 1. the - / + buttons: mouse from the bar's cut alone, tooltips, the click
-------------------------------------------------------------------------------
do
    local scaleBlock = cut(SESSION, "    do\n        local SCALE_MIN", "\n    -- Element filter right of the logo")
    local hoverBlock = cut(SESSION, "    local HOVER_ZONE_H = 60", "\n    UM.hudFrame:Hide()\n    return UM.hudFrame")
    local shift = false
    local cursorX, cursorY = 100, 0   -- far below the bar

    local UIParent = frame("Frame")
    function UIParent:GetHeight() return 1080 end
    local unlockFrame = frame("Frame")
    local hud = frame("Frame")
    hud.mouse = false
    hud._refitOutlines = function() end
    for _, k in ipairs({ "_gridBtn", "_darkOverlayBtn", "_flashBtn", "_magnetBtn", "_coordBtn", "_hoverBtn",
        "_saveBtn", "_filterBox", "_filterIcon", "_filterClear", "_infoBtn" }) do
        hud[k] = frame("Button")
        hud[k]:SetScript("OnLeave", function() end)
    end
    local exitBtn = frame("Button")
    exitBtn:SetScript("OnLeave", function() end)
    hud._exitBtn = exitBtn

    local UM = { hudFrame = hud, unlockFrame = unlockFrame, ShowBarTip = ShowBarTip }
    local EllesmereUI = {
        L = function(s) return s end,
        HideWidgetTooltip = HideTip,
        _WidgetTooltipOwner = function() return tipOwner end,
    }
    local env = setmetatable({
        UIParent = UIParent, EllesmereUIDB = {},
        CreateFrame = function(kind) return frame(kind) end,
        IsShiftKeyDown = function() return shift end,
        GetCursorPosition = function() return cursorX, cursorY end,
        GetMouseFoci = function() return {} end,
    }, { __index = _G })
    local chunk = assert(loadstring("local UM, parent, uiScale, exitBtn, max, min, FONT_PATH, ns, EllesmereUI = ...\n"
        .. "local hoverBarEnabled = false\n" .. scaleBlock .. "\n" .. hoverBlock .. "\n"
        .. "return function(v) hoverBarEnabled = v end\n", "=Session.lua (the scale buttons and the hover fade)"))
    setfenv(chunk, env)
    local setHoverBar = chunk(UM, unlockFrame, 1, exitBtn, math.max, math.min, "font", {}, EllesmereUI)

    local minus, plus = hud._minusBtn, hud._plusBtn
    local function tick(n) for _ = 1, n or 1 do hud.scripts.OnUpdate(hud, 0.1) end end
    -- The element filter's screen fit runs as the bar shows (EUI_UnlockMode_Filter.lua).
    local fitCap = 1.5
    hud:HookScript("OnShow", function() hud._setScaleCap(fitCap) end)

    check(minus._isDisabled == true and plus._isDisabled == false, "at the default 100% the - is not greyed, or the + is")
    -- a session with Hover Top Bar on and the cursor away: the bar fades out, its mouse is cut
    setHoverBar(true)
    tick(10)
    check(hud.alpha == 0, "Hover Top Bar does not hide the bar while the cursor is away")
    check(minus:IsMouseEnabled() == false and plus:IsMouseEnabled() == false, "the hidden bar's - / + still take the mouse")
    -- Unlock Mode closed with the bar hidden and opened again: the screen fit runs on the show
    hud:Hide()
    hud:Show()
    hud:SetAlpha(1)
    tick(1)
    check(hud.alpha == 0 and not minus:IsMouseEnabled(), "a reopen with the bar still hidden gives the greyed - its mouse back")
    -- the cursor reaches the bar: it fades in and every button takes the mouse again
    cursorY = 1080
    tick(2)
    check(hud.alpha > 0 and minus:IsMouseEnabled() and plus:IsMouseEnabled(), "the bar fading in does not give - / + their mouse back")

    -- over a run of frames with Shift going down and up, and the fit greying + on a frame in
    -- the middle of a cut (Shift already held the frame before): mouse on exactly while the bar
    -- is not cut
    setHoverBar(false)
    cursorY = 0
    local bad = 0
    for step = 1, 40 do
        shift = (step % 7 < 3)
        if step == 22 then hud._setScaleCap(1.05) end
        if step == 30 then hud._setScaleCap(1.5) end
        tick(1)
        for _, b in ipairs({ minus, plus }) do
            if b:IsMouseEnabled() == shift then bad = bad + 1 end
        end
    end
    check(bad == 0, "- / + mouse differs from the bar's cut on " .. bad .. " of 80 button frames")
    shift = false
    tick(1)

    -- tooltips: what each button does, why a greyed one is greyed, and the click under the cursor
    minus.scripts.OnEnter(minus)
    check(tipOwner == minus and tipText == "Already at the smallest size.", "the greyed - says " .. tostring(tipText))
    minus.scripts.OnLeave(minus)
    check(tipOwner == nil, "leaving - keeps its tooltip")
    fitCap = 1.15
    hud._setScaleCap(fitCap)
    plus.scripts.OnEnter(plus)
    check(tipOwner == plus and tipText == "Makes this bar bigger.", "the + says " .. tostring(tipText))
    plus.scripts.OnClick(plus)                       -- 100% to 110%: the next step would pass the fit
    check(plus._isDisabled == true, "the + is not greyed at the screen fit's cap")
    check(tipOwner == plus and tipText == "Already at the largest size that fits the screen.",
        "the open tooltip does not follow the click: " .. tostring(tipText))
    check(minus._isDisabled == false, "the - stays greyed above 100%")
    hud._setScaleCap(1.5)
    for _ = 1, 4 do plus.scripts.OnClick(plus) end
    check(plus._isDisabled and tipText == "Already at the largest size.", "the + at 150% says " .. tostring(tipText))
    plus.scripts.OnLeave(plus)
    check(tipOwner == nil, "leaving + keeps its tooltip")
    minus.scripts.OnEnter(minus)
    check(tipText == "Makes this bar smaller.", "the - above 100% says " .. tostring(tipText))
    minus.scripts.OnLeave(minus)
    -- a click with no tooltip open shows none
    local before = tipShows
    minus.scripts.OnClick(minus)
    check(tipShows == before and tipOwner == nil, "a click with no tooltip open shows one")
    -- another control's tooltip is left alone by a scale click
    tipOwner, tipText = exitBtn, "other"
    minus.scripts.OnClick(minus)
    check(tipOwner == exitBtn and tipText == "other", "a scale click replaces another control's tooltip")
    tipOwner = nil
    -- the mouse cut runs every button's OnLeave: an open - tooltip drops with the bar
    minus.scripts.OnEnter(minus)
    shift = true
    tick(1)
    shift = false
    check(tipOwner == nil, "holding Shift leaves the - tooltip up over the hidden bar")
end

-------------------------------------------------------------------------------
-- 2. Exit: its own hover stays, the tooltip rides on it
-------------------------------------------------------------------------------
do
    local block = cut(SESSION, "    local _, exitBrd = EllesmereUI.MakeStyledButton(exitBtn", "    UM.hudFrame._exitBtn = exitBtn")
    local exitBtn = frame("Button")
    local entered, left = 0, 0
    local EllesmereUI = {
        L = function(s) return s end,
        HideWidgetTooltip = HideTip,
        RB_COLOURS = {},
        MakeStyledButton = function(btn)
            btn:SetScript("OnEnter", function() entered = entered + 1 end)
            btn:SetScript("OnLeave", function() left = left + 1 end)
            return nil, {}
        end,
    }
    local chunk = assert(loadstring("local exitBtn, EllesmereUI, UM, ns, BTN_FONT = ...\n" .. block, "=Session.lua (Exit)"))
    chunk(exitBtn, EllesmereUI, { ShowBarTip = ShowBarTip }, {}, 10)
    tipOwner = nil
    exitBtn:GetScript("OnEnter")(exitBtn)
    check(entered == 1, "Exit's own hover no longer runs")
    check(tipOwner == exitBtn and tipText == "Leaves Unlock Mode. With unsaved changes, it asks whether to save them first.",
        "Exit says " .. tostring(tipText))
    -- the bar's mouse cut calls GetScript("OnLeave"): that one call must drop the tooltip
    exitBtn:GetScript("OnLeave")(exitBtn)
    check(left == 1 and tipOwner == nil, "Exit's leave script does not undo the hover and drop the tooltip")
end

-------------------------------------------------------------------------------
-- 3. Save & Exit: its tooltip, and its outline and label on an accent change
-------------------------------------------------------------------------------
do
    local block = cut(SESSION, "    -- Save & Exit button (right side", "\n    ---------------------------------------------------------------\n    --  Banner Scale +/- Buttons")
    local E, Update = Registry()
    local GREEN = { r = 0.1, g = 0.2, b = 0.3 }
    local outline
    E.ELLESMERE_GREEN = GREEN
    E.L = function(s) return s end
    E.lerp = function(a, b, t) return a + (b - a) * t end
    E.HideWidgetTooltip = HideTip
    E.MakeRoundedBorder = function(_, r, g, b, a)
        outline = { c = { r, g, b, a }, writes = 0 }
        function outline:SetColor(r2, g2, b2, a2)
            self.c = { r2, g2, b2, a2 }
            self.writes = self.writes + 1
        end
        return outline
    end
    local hud = frame("Frame")
    hud._outlines = {}
    local made = {}
    local env = setmetatable({
        CreateFrame = function(kind)
            local f = frame(kind)
            local realFS = f.CreateFontString
            function f:CreateFontString() self.fs = realFS(self); return self.fs end
            made[#made + 1] = f
            return f
        end,
    }, { __index = _G })
    local chunk = assert(loadstring("local UM, EllesmereUI, ns, max, FONT_PATH, BANNER_PX_W, EDGE_IN, hoverRightEdge, CHAIN_GAP, btnCenterY, BTN_H, BTN_FONT = ...\n"
        .. block, "=Session.lua (Save & Exit)"))
    setfenv(chunk, env)
    chunk({ hudFrame = hud, ShowBarTip = ShowBarTip }, E, { RequestClose = function() end }, math.max, "font", 1144, 85, 300, 15, 0, 26, 10)
    local btn = hud._saveBtn
    local lbl = btn and btn.fs
    check(btn ~= nil and outline ~= nil and lbl ~= nil, "the Save & Exit block built no button, outline or label")
    if btn and outline and lbl then
        check(hud._outlines[1] == outline, "the Save & Exit outline is not in the bar's refit list")
        check(same(outline.c, 0.1, 0.2, 0.3, 0.7) and same(lbl.c, 0.1, 0.2, 0.3, 0.7), "the button is not built in the accent")
        tipOwner = nil
        btn.scripts.OnEnter(btn)
        check(tipOwner == btn and tipText == "Saves the new positions and leaves Unlock Mode.", "Save & Exit says " .. tostring(tipText))
        btn.scripts.OnLeave(btn)
        check(tipOwner == nil, "leaving Save & Exit keeps its tooltip")
        btn.scripts.OnUpdate(btn, 1)             -- the leave's fade runs out: back at rest
        -- one registry entry, and an accent change repaints the outline and the resting label
        check(#E._accentElements == 1, "the Save & Exit block registered " .. #E._accentElements .. " accent entries")
        GREEN.r, GREEN.g, GREEN.b = 0.9, 0.5, 0.1    -- the shared colour table changes in place
        Update(0.9, 0.5, 0.1)
        check(same(outline.c, 0.9, 0.5, 0.1, 0.7), "the Save & Exit outline keeps the old accent")
        check(same(lbl.c, 0.9, 0.5, 0.1, 0.7), "the resting Save & Exit label keeps the old accent")
        -- hovered: the label keeps its hover strength in the new colour
        btn.scripts.OnEnter(btn)
        btn.scripts.OnUpdate(btn, 1)
        GREEN.r, GREEN.g, GREEN.b = 0.2, 0.9, 0.2
        Update(0.2, 0.9, 0.2)
        check(same(lbl.c, 0.2, 0.9, 0.2, 1), "a hovered Save & Exit label loses its hover strength on an accent change")
        check(same(outline.c, 0.2, 0.9, 0.2, 0.7), "the outline misses an accent change while the button is hovered")
        btn.scripts.OnLeave(btn)
        tipOwner = nil
    end
end

-------------------------------------------------------------------------------
-- 4. mover borders and the Blizzard-owned overlays follow the accent
-------------------------------------------------------------------------------
do
    local ACCENT = { 0.1, 0.2, 0.3 }
    local function GetAccent() return ACCENT[1], ACCENT[2], ACCENT[3] end
    local function Border(r, g, b, a)
        local brd = { c = { r, g, b, a }, writes = 0 }
        function brd:SetColor(r2, g2, b2, a2)
            self.c = { r2, g2, b2, a2 }
            self.writes = self.writes + 1
        end
        return brd
    end

    -- a mover's own method: the captured colour always, the border only while it rests
    local moverBody = cut(MOVERS, "    function mover._applyAccent()", "\n    -- Update the name label color based on anchor state")
    local function Mover(UM)
        local mover, brd = {}, Border(0.1, 0.2, 0.3, 0.6)
        local captured = assert(loadstring("local mover, brd, GetAccent, UM, ar, ag, ab = ...\n" .. moverBody
            .. "\nreturn function() return ar, ag, ab end", "=Movers.lua (a mover's accent)"))(mover, brd, GetAccent, UM, 0.1, 0.2, 0.3)
        return mover, brd, captured
    end
    local UM = {}
    local resting, restBrd, restCap = Mover(UM)
    local selected, selBrd, selCap = Mover(UM)
    local hovered, hovBrd, hovCap = Mover(UM)
    selected._selected = true
    UM.hoveredMover = hovered
    ACCENT = { 0.9, 0.5, 0.1 }
    resting._applyAccent()
    selected._applyAccent()
    hovered._applyAccent()
    check(same(restBrd.c, 0.9, 0.5, 0.1, 0.6), "a resting mover's border keeps the old accent")
    check(selBrd.writes == 0, "a selected mover's border is repainted by an accent change")
    check(hovBrd.writes == 0, "a hovered mover's border is repainted by an accent change")
    local r1, g1, b1 = selCap()
    local r2, g2, b2 = hovCap()
    local r3, g3, b3 = restCap()
    check(r1 == 0.9 and g1 == 0.5 and b1 == 0.1 and r2 == 0.9 and g2 == 0.5 and b2 == 0.1 and r3 == 0.9 and g3 == 0.5 and b3 == 0.1,
        "a mover does not take the new accent for its later repaints (leave, deselect)")

    -- a Blizzard-owned overlay
    ACCENT = { 0.1, 0.2, 0.3 }
    local overlayBody = cut(TOOLS, "local function CreateBlizzOwnedOverlay(def, parent)", "\nlocal function ShowBlizzOwnedOverlays")
    local env = setmetatable({
        CreateFrame = function(kind) return frame(kind) end,
        UIParent = { GetEffectiveScale = function() return 1 end },
        InCombatLockdown = function() return false end,
        EllesmereUI = {
            L = function(s) return s end,
            PrimeFontShadow = function() end,
            MakeBorder = function(_, r, g, b, a) return Border(r, g, b, a) end,
        },
    }, { __index = _G })
    local mk = assert(loadstring("local GetAccent, FONT_PATH, ns = ...\n" .. overlayBody .. "\nreturn CreateBlizzOwnedOverlay", "=Tools.lua (an overlay)"))
    setfenv(mk, env)
    local ov = mk(GetAccent, "font", {})({ label = "Bags" }, frame("Frame"))
    check(type(ov._applyAccent) == "function", "an overlay has no accent method")
    if type(ov._applyAccent) == "function" then
        ACCENT = { 0.9, 0.5, 0.1 }
        ov._applyAccent()
        check(same(ov._brd.c, 0.9, 0.5, 0.1, 0.6), "a resting overlay's border keeps the old accent")
        ov._forceCollapse()
        check(same(ov._brd.c, 0.9, 0.5, 0.1, 0.6), "the next open paints the overlay in the old accent")
        ov.scripts.OnEnter(ov)
        ACCENT = { 0.2, 0.9, 0.2 }
        ov._applyAccent()
        check(same(ov._brd.c, 1, 1, 1), "a hovered overlay loses its hover colour on an accent change")
        ov.scripts.OnLeave(ov)
        check(same(ov._brd.c, 0.2, 0.9, 0.2, 0.6), "a hovered overlay does not take the new accent on leave")
    end

    -- the one registry entry of the Movers part: every mover and overlay, once per change
    local E, Update = Registry()
    local cbBody = cut(MOVERS, "EllesmereUI.RegAccent({ type = \"callback\"", "\nUM.CreateMover = CreateMover")
    local calls = 0
    local function Counted() return { _applyAccent = function() calls = calls + 1 end } end
    local movers = { a = Counted(), b = Counted() }
    local UM2 = { _blizzOwnedOverlays = { Bags = Counted() } }
    local cb = assert(loadstring("local movers, UM = ...\n" .. cbBody, "=Movers.lua (the accent callback)"))
    setfenv(cb, setmetatable({ EllesmereUI = E }, { __index = _G }))
    cb(movers, UM2)
    check(#E._accentElements == 1, "the Movers part registers " .. #E._accentElements .. " accent entries")
    Update(0.5, 0.5, 0.5)
    check(calls == 3, "one accent change reached " .. calls .. " of 3 movers and overlays")
    -- before Unlock Mode was opened there is nothing to walk
    movers.a, movers.b, UM2._blizzOwnedOverlays.Bags = nil, nil, nil
    Update(0.4, 0.4, 0.4)
    check(calls == 3, "an accent change with no mover or overlay built still calls one")
end

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print(("PASS test_unlock_topbar_buttons (%d checks)"):format(count))
