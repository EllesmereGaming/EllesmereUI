-- Stub harness: the WoW Forever Call Totem Bar keeps its buttons in place
-- while Edit Mode moves Blizzard's bar frame in combat. Loads the real
-- EUI_ResourceBars_CallTotemBar.lua under a small frame model that resolves
-- anchors to rects, then plays Blizzard's passes over it: the bottom bar
-- stack, a layout apply and a bar update, in and out of combat. Sections 6
-- to 11: where the list of totems and its arrow show (above their button in
-- a row, beside it in a column), and an open list following the settings.
--   lua .tools/tests/test_rb_call_totem_bar_combat.lua        (from the repository root)
local TARGET = CT_TARGET or "EllesmereUIResourceBars/EUI_ResourceBars_CallTotemBar.lua"

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

-------------------------------------------------------------------------------
--  Frame model: one anchor and a size give a rect, in screen units
-------------------------------------------------------------------------------
local UI_SCALE, UI_W, UI_H = 0.75, 1600, 900
local POINTS = {
    TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 },
    LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
    BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 },
}

-- world state, rebuilt by Load
local W

local function EffScale(f)
    local s = 1
    while f do s = s * f._scale; f = f._parent end
    return s
end

local function Rect(f)
    if f == W.UIParent then return 0, 0, UI_W * UI_SCALE, UI_H * UI_SCALE end
    local p = f._points[1]
    if not p then return nil end
    local rl, rb, rr, rt = Rect(p.rel)
    if not rl then return nil end
    local s = EffScale(f)
    local fr, fp = POINTS[p.relPoint], POINTS[p.point]
    local ax = rl + (rr - rl) * fr[1] + p.x * s
    local ay = rb + (rt - rb) * fr[2] + p.y * s
    local w, h = f._w * s, f._h * s
    local l, b = ax - w * fp[1], ay - h * fp[2]
    return l, b, l + w, b + h
end

-- A frame our code may not change in combat: a secure button, a frame that
-- holds one, or a frame one of those is anchored to.
local function Restricted(f)
    local set, grew = {}, true
    for _, x in ipairs(W.frames) do if x._protected then set[x] = true end end
    while grew do
        grew = false
        for x in pairs(set) do
            local par = x._parent
            if par and par ~= W.UIParent and not set[par] then set[par] = true; grew = true end
            for _, p in ipairs(x._points) do
                if p.rel ~= W.UIParent and not set[p.rel] then set[p.rel] = true; grew = true end
            end
        end
    end
    return set[f] == true
end

local function Guard(f, method)
    if W.inCombat and not W.blizz and Restricted(f) then
        W.violations[#W.violations + 1] = f._name .. ":" .. method
    end
end

local function Texture()
    local t = { _alpha = 1 }
    function t:SetAlpha(a) self._alpha = a end
    function t:GetAlpha() return self._alpha end
    function t:SetTexCoord() end
    function t:RemoveMaskTexture() end
    function t:AddMaskTexture() end
    return t
end

local function NewFrame(name, parent)
    local f = {
        _name = name or ("frame" .. (#W.frames + 1)), _parent = parent, _scale = 1, _w = 0, _h = 0,
        _points = {}, _shown = true, _mouse = false, _strata = "MEDIUM", _level = 1,
    }
    W.frames[#W.frames + 1] = f
    if name then _G[name] = f end
    function f:GetName() return name end
    function f:GetParent() return self._parent end
    function f:SetPoint(point, rel, relPoint, x, y)
        Guard(self, "SetPoint")
        if type(rel) == "string" then rel = _G[rel] end
        assert(POINTS[point] and POINTS[relPoint] and type(rel) == "table", "bad SetPoint on " .. self._name)
        local entry = { point = point, rel = rel, relPoint = relPoint, x = x or 0, y = y or 0 }
        for i, p in ipairs(self._points) do
            if p.point == point then self._points[i] = entry; return end
        end
        self._points[#self._points + 1] = entry
    end
    function f:ClearAllPoints()
        Guard(self, "ClearAllPoints")
        self._points = {}
        self._clears = (self._clears or 0) + 1
    end
    function f:SetAllPoints() end
    function f:GetNumPoints() return #self._points end
    function f:GetPoint(i)
        local p = self._points[i or 1]
        if p then return p.point, p.rel, p.relPoint, p.x, p.y end
    end
    function f:SetSize(w, h) Guard(self, "SetSize"); self._w, self._h = w, h end
    function f:GetSize() return self._w, self._h end
    function f:GetWidth() return self._w end
    function f:GetHeight() return self._h end
    function f:SetScale(s) Guard(self, "SetScale"); self._scale = s end
    function f:GetScale() return self._scale end
    function f:Show() Guard(self, "Show"); self._shown = true end
    function f:Hide() Guard(self, "Hide"); self._shown = false end
    function f:SetShown(v) if v then self:Show() else self:Hide() end end
    function f:IsShown() return self._shown end
    function f:EnableMouse(v) Guard(self, "EnableMouse"); self._mouse = v and true or false end
    function f:IsMouseEnabled() return self._mouse end
    function f:SetAlpha(a) self._alpha = a end
    function f:GetAlpha() return self._alpha or 1 end
    function f:SetFrameStrata(s) Guard(self, "SetFrameStrata"); self._strata = s end
    function f:GetFrameStrata() return self._strata end
    function f:SetFrameLevel(l) self._level = l end
    function f:GetFrameLevel() return self._level end
    function f:GetLeft() local l = Rect(self); return l and l / EffScale(self) end
    function f:GetTop() local _, _, _, t = Rect(self); return t and t / EffScale(self) end
    function f:GetNormalTexture() return self._normal end
    function f:HookScript() end
    return f
end

local function Button(name, parent, secure)
    local b = NewFrame(name, parent)
    b._protected = secure
    b._w, b._h = 30, 30
    b._normal, b.icon, b.overlayTex = Texture(), Texture(), Texture()
    local cd = {}
    function cd:SetHideCountdownNumbers() end
    function cd:SetCountdownFont() end
    b.cooldown = cd
    return b
end

-------------------------------------------------------------------------------
--  The world: Blizzard's bar as its XML builds it, and Blizzard's own passes
-------------------------------------------------------------------------------
local function Blizz(fn, ...)
    local was = W.blizz
    W.blizz = true
    fn(...)
    W.blizz = was
end

local function Load(cfg, world)
    -- listed: the totems the toggled button has to list (0: Blizzard opens nothing)
    W = { frames = {}, violations = {}, queue = {}, inCombat = false, blizz = false, editMode = 0, listed = 4 }
    for k, v in pairs(world) do W[k] = v end
    EUI_CLIENT_BLOCKED = nil
    ERB_CallTotemBarFrame = nil

    local UIParent = NewFrame("UIParent")
    UIParent._scale = UI_SCALE
    W.UIParent = UIParent
    local main = NewFrame("MainActionBar", UIParent)
    main._w, main._h = 500, 40
    main:SetPoint("BOTTOM", UIParent, "BOTTOM", -200, 4)

    local bar = NewFrame("MultiCastActionBarFrame", UIParent)
    bar._w, bar._h, bar._mouse, bar._shown = 230, 38, true, false
    bar.numActiveSlots = 0
    bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 0)
    local sel = NewFrame(nil, bar)
    sel._mouse = true
    bar.Selection = sel
    -- Edit Mode's overrides over the saved methods (OnSystemLoad)
    bar.SetPointBase, bar.ClearAllPointsBase, bar.SetScaleBase = bar.SetPoint, bar.ClearAllPoints, bar.SetScale
    local function Override(base, label)
        return function(self, ...)
            if not W.blizz then W.violations[#W.violations + 1] = "Edit Mode override called: " .. label end
            return base(self, ...)
        end
    end
    bar.SetPoint = Override(bar.SetPointBase, "SetPoint")
    bar.ClearAllPoints = Override(bar.ClearAllPointsBase, "ClearAllPoints")
    bar.SetScale = Override(bar.SetScaleBase, "SetScale")
    bar.systemInfo = {
        isInDefaultPosition = true,
        anchorInfo = { point = "BOTTOM", relativeTo = "UIParent", relativePoint = "BOTTOM", offsetX = 0, offsetY = 0 },
    }

    local SUMMON = Button("MultiCastSummonSpellButton", bar, true)
    SUMMON:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 3, 3)
    _G.MultiCastSummonSpellButtonHighlight = Texture()
    local SLOT, PAGE, ACT = {}, {}, {}
    for i = 1, 4 do
        SLOT[i] = Button("MultiCastSlotButton" .. i, bar, false)
        if i == 1 then
            SLOT[i]:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 36, 3)
        else
            SLOT[i]:SetPoint("LEFT", SLOT[i - 1], "RIGHT", 8, 0)
        end
    end
    for p = 1, 3 do
        PAGE[p] = NewFrame("MultiCastActionPage" .. p, bar)
        PAGE[p]._w, PAGE[p]._h, PAGE[p]._shown = 144, 30, p == 1
        PAGE[p]:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 36, 3)
        for k = 1, 4 do
            local i = (p - 1) * 4 + k
            ACT[i] = Button("MultiCastActionButton" .. i, PAGE[p], true)
            if k == 1 then
                ACT[i]:SetPoint("LEFT", PAGE[p], "LEFT", 0, 0)
            else
                ACT[i]:SetPoint("LEFT", ACT[i - 1], "RIGHT", 8, 0)
            end
        end
    end
    local RECALL = Button("MultiCastRecallSpellButton", bar, true)
    RECALL:SetPoint("LEFT", ACT[4], "RIGHT", 8, 0)
    _G.MultiCastRecallSpellButtonHighlight = Texture()
    W.bar, W.SUMMON, W.SLOT, W.PAGE, W.ACT, W.RECALL = bar, SUMMON, SLOT, PAGE, ACT, RECALL

    -- Blizzard's bar update: shown slots and buttons, then the first slot by
    -- its BOTTOMLEFT and Totemic Recall by its LEFT (no ClearAllPoints).
    function MultiCastActionBarFrame_Update(self)
        self.numActiveSlots = W.active
        for i = 1, 4 do SLOT[i]:SetShown(i <= W.active) end
        for i = 1, 12 do ACT[i]:SetShown(((i - 1) % 4) + 1 <= W.active) end
        self:SetShown(W.active > 0)
        if not self:IsShown() then return end
        local x = W.summon and (SUMMON:GetWidth() + 8 + 3) or 3
        for p = 1, 3 do PAGE[p]:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", x, 3) end
        SLOT[1]:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", x, 3)
        SUMMON:SetShown(W.summon)
        if W.recall then RECALL:SetPoint("LEFT", SLOT[W.active], "RIGHT", 8, 0) end
        RECALL:SetShown(W.recall)
    end
    -- Blizzard's list of totems (the flyout) and its arrow, as the XML builds
    -- them: plain frames of the bar, hidden, on one anchor each.
    local flyout = NewFrame("MultiCastFlyoutFrame", bar)
    flyout._w, flyout._h, flyout._shown = 32, 30, false
    flyout:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
    local arrow = NewFrame("MultiCastFlyoutFrameOpenButton", bar)
    arrow._w, arrow._h, arrow._shown = 28, 18, false
    arrow:SetPoint("BOTTOM", bar, "TOP", 0, 0)
    W.flyout, W.arrow = flyout, arrow
    -- The arrow: handed to the hovered button and hung above it, its point
    -- added on every show (no ClearAllPoints).
    function MultiCastFlyoutFrameOpenButton_Show(self, kind, parent)
        self.type, self.parent = kind, parent
        self._parent = parent
        self:SetPoint("BOTTOM", parent, "TOP", 0, 0)
        self:Show()
    end
    -- The list: a toggle on its own button closes it (its OnHide forgets the
    -- button); any other toggle, when that button has totems to list, sizes
    -- it, hangs it above the button (no ClearAllPoints) and shows it (its
    -- OnShow hides the arrow).
    function MultiCastFlyoutFrame_ToggleFlyout(self, kind, parent)
        if self:IsShown() and self.parent == parent then
            self:Hide()
            self.type, self.parent = nil, nil
        elseif W.listed > 0 then
            self.type, self.parent = kind, parent
            self._h = 20 + 26 * W.listed
            self:SetPoint("BOTTOM", parent, "TOP", 0, 0)
            self:Show()
            arrow:Hide()
        end
    end

    -- Edit Mode: the bottom bar stack moves a shown bar that counts as being
    -- at its default spot; a layout apply resets the anchor, then stacks.
    local mgr = {}
    function mgr:UpdateBottomActionBarPositions()
        if bar:IsShown() and bar.systemInfo.isInDefaultPosition then
            bar:ClearAllPoints()
            bar:SetPoint("BOTTOMLEFT", main, "BOTTOMLEFT", 30, 77.6)
        end
    end
    EditModeManagerFrame = mgr
    function bar:ApplySystemAnchor()
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
        mgr:UpdateBottomActionBarPositions()
    end
    function bar:BreakFrameSnap() end

    C_EditMode = {
        GetLayouts = function() W.editMode = W.editMode + 1; return { layouts = {}, activeLayout = 1 } end,
        SaveLayouts = function() W.editMode = W.editMode + 1 end,
    }

    function hooksecurefunc(a, b, c)
        local tbl, name, fn
        if type(a) == "table" then tbl, name, fn = a, b, c else tbl, name, fn = _G, a, b end
        local orig = tbl[name]
        assert(type(orig) == "function", "hooksecurefunc on a missing function: " .. tostring(name))
        tbl[name] = function(...)
            orig(...)
            local was = W.blizz
            W.blizz = false
            fn(...)
            W.blizz = was
        end
    end
    function InCombatLockdown() return W.inCombat end
    function issecretvalue() return false end
    function wipe(t) for k in pairs(t) do t[k] = nil end return t end
    function UnitClass() return "Shaman", "SHAMAN" end
    function GetCVarBool() return true end
    function CreateFont() return { SetFont = function() end } end
    function CreateFrame(_, name, parent) return NewFrame(name, parent) end
    EllesmereUI = {
        IS_FOREVER = true,
        PP = { Snap = function(v) return v end },
        ClearFramePoints = function(f) (f.ClearAllPointsBase or f.ClearAllPoints)(f) end,
        SetFramePoint = function(f, ...) (f.SetPointBase or f.SetPoint)(f, ...) end,
        SetFrameScale = function(f, s) (f.SetScaleBase or f.SetScale)(f, s) end,
        ApplyBorderStyle = function() end,
        BorderPx = function() return 1 end,
        GetFontOutlineFlag = function() return "OUTLINE" end,
        IsUnlockAnchored = function() return false end,
    }
    local ns = {
        ERB = { db = { profile = { callTotemBar = cfg } } },
        CombatQueue = { Defer = function(key, fn) W.queue[key] = fn end },
        GetRBFont = function() return "font" end,
        SnapXY = function(x, y) return x, y end,
    }
    W.ns = ns
    assert(loadstring(SOURCE, "=CallTotemBar"))("EllesmereUIResourceBars", ns)
    assert(ns.CT_Apply, "the module did not load")

    -- login: Blizzard's first bar update and layout apply, then ours
    Blizz(MultiCastActionBarFrame_Update, bar)
    Blizz(bar.ApplySystemAnchor, bar)
    ns.CT_Apply()
    return ns
end

local function EnterCombat() W.inCombat = true end
local function LeaveCombat()
    W.inCombat = false
    local q = W.queue
    W.queue = {}
    for _, fn in pairs(q) do fn() end
end

-------------------------------------------------------------------------------
--  What the settings ask for
-------------------------------------------------------------------------------
local function Shown()
    local list = {}
    if W.summon then list[#list + 1] = W.SUMMON end
    for i = 1, W.active do list[#list + 1] = W.SLOT[i] end
    if W.recall then list[#list + 1] = W.RECALL end
    return list
end

local function near(a, b) return a and b and math.abs(a - b) < 1e-6 end

-- Every shown button where the settings put it: a row or a column from the
-- holder's top-left corner, each totem button on its element slot.
local function Placed(cfg, label)
    local holder = _G.ERB_CallTotemBarFrame
    local hl, _, _, ht = Rect(holder)
    local size = (cfg.iconSize or 30) * UI_SCALE
    local pitch = ((cfg.iconSize or 30) + (cfg.spacing or 2)) * UI_SCALE
    local vertical = cfg.orientation == "VERTICAL"
    local ok = true
    for i, b in ipairs(Shown()) do
        local l, bot, r, t = Rect(b)
        local wantL = hl + (vertical and 0 or (i - 1) * pitch)
        local wantT = ht - (vertical and (i - 1) * pitch or 0)
        if not (near(l, wantL) and near(t, wantT) and near(r - l, size) and near(t - bot, size)) then
            ok = false
            print(("    %s: %s at %s,%s (want %s,%s)"):format(label, b._name, tostring(l), tostring(t), wantL, wantT))
        end
        if #b._points ~= 1 then ok = false; print("    " .. b._name .. " has " .. #b._points .. " anchors") end
    end
    for i = 1, 12 do
        local k = ((i - 1) % 4) + 1
        if k <= W.active then
            local al, ab, ar, at = Rect(W.ACT[i])
            local sl, sb, sr, st = Rect(W.SLOT[k])
            if not (near(al, sl) and near(ab, sb) and near(ar, sr) and near(at, st)) then
                ok = false
                print(("    %s: totem button %d is off its slot"):format(label, i))
            end
        end
    end
    return ok
end

-- Only the totem buttons (the secure ones a click casts) and the buttons
-- Blizzard's update leaves alone.
local function TotemsPlaced(cfg)
    local holder = _G.ERB_CallTotemBarFrame
    local hl, _, _, ht = Rect(holder)
    local pitch = ((cfg.iconSize or 30) + (cfg.spacing or 2)) * UI_SCALE
    local vertical = cfg.orientation == "VERTICAL"
    local first = W.summon and 1 or 0
    for i = 1, 12 do
        local k = ((i - 1) % 4) + 1
        if k <= W.active then
            local l, _, _, t = Rect(W.ACT[i])
            local idx = first + k - 1
            if not (near(l, hl + (vertical and 0 or idx * pitch)) and near(t, ht - (vertical and idx * pitch or 0))) then
                return false
            end
        end
    end
    return true
end

local function BarAtHolder()
    local bl, _, _, bt = Rect(W.bar)
    local hl, _, _, ht = Rect(_G.ERB_CallTotemBarFrame)
    return near(bl, hl) and near(bt, ht)
end

local CONFIGS = {
    { name = "row", cfg = { enabled = true, iconSize = 30, spacing = 2 } },
    { name = "large row", cfg = { enabled = true, iconSize = 45, spacing = 0 } },
    { name = "column", cfg = { enabled = true, iconSize = 24, spacing = 5, orientation = "VERTICAL" } },
}
local WORLDS = {
    { name = "all six", w = { summon = true, active = 4, recall = true } },
    { name = "no Call of the Elements", w = { summon = false, active = 2, recall = true } },
    { name = "one slot, no recall", w = { summon = true, active = 1, recall = false } },
    { name = "three slots", w = { summon = true, active = 3, recall = true } },
}

-------------------------------------------------------------------------------
-- 1. Out of combat: the layout the settings ask for, the bar on the holder
-------------------------------------------------------------------------------
for _, c in ipairs(CONFIGS) do
    for _, w in ipairs(WORLDS) do
        local label = c.name .. " / " .. w.name
        Load(c.cfg, w.w)
        check(Placed(c.cfg, label), label .. ": every button is where the settings put it")
        check(BarAtHolder(), label .. ": the bar's top-left corner is the holder's")
        -- Blizzard's update re-anchors the first slot and Totemic Recall: ours follows at once
        Blizz(MultiCastActionBarFrame_Update, W.bar)
        check(Placed(c.cfg, label), label .. ": a bar update out of combat is laid out again")
        -- the stack pass out of combat is answered by the re-pin
        Blizz(EditModeManagerFrame.UpdateBottomActionBarPositions, EditModeManagerFrame)
        check(BarAtHolder() and Placed(c.cfg, label), label .. ": a stack pass out of combat is re-pinned")
        check(#W.violations == 0, label .. ": no Edit Mode override and no combat write (" .. tostring(W.violations[1]) .. ")")
    end
end

-------------------------------------------------------------------------------
-- 2. In combat: Edit Mode's bottom bar stack moves the bar frame. The buttons
--    stay, and nothing of ours touches a protected frame until regen.
-------------------------------------------------------------------------------
for _, c in ipairs(CONFIGS) do
    for _, w in ipairs(WORLDS) do
        local label = c.name .. " / " .. w.name
        Load(c.cfg, w.w)
        EnterCombat()
        Blizz(EditModeManagerFrame.UpdateBottomActionBarPositions, EditModeManagerFrame)
        check(not BarAtHolder(), label .. ": the stack moved the bar frame (the pass is modelled)")
        check(Placed(c.cfg, label), label .. ": the buttons stay through a combat stack pass")
        check(#W.violations == 0, label .. ": nothing of ours writes in combat (" .. tostring(W.violations[1]) .. ")")
        check(W.queue.CTRefresh ~= nil, label .. ": the re-pin waits for regen")
        -- a layout apply in combat (a level-up): top-left of the screen, then the stack
        Blizz(W.bar.ApplySystemAnchor, W.bar)
        check(Placed(c.cfg, label), label .. ": the buttons stay through a combat layout apply")
        check(#W.violations == 0, label .. ": still nothing of ours in combat (" .. tostring(W.violations[1]) .. ")")
        LeaveCombat()
        check(BarAtHolder() and Placed(c.cfg, label), label .. ": regen puts the bar back on the holder")
    end
end

-------------------------------------------------------------------------------
-- 3. A Blizzard bar update in combat while the bar frame is away: the first
--    slot and Totemic Recall go where Blizzard puts them (one anchor each),
--    and every totem button stays where a click expects it.
-------------------------------------------------------------------------------
for _, c in ipairs(CONFIGS) do
    local label = c.name
    Load(c.cfg, WORLDS[1].w)
    EnterCombat()
    Blizz(EditModeManagerFrame.UpdateBottomActionBarPositions, EditModeManagerFrame)
    Blizz(MultiCastActionBarFrame_Update, W.bar)
    check(#W.SLOT[1]._points == 1 and W.SLOT[1]._points[1].rel == W.bar, label .. ": Blizzard's first slot anchor replaced ours, no second anchor")
    check(#W.RECALL._points == 1 and W.RECALL._points[1].rel == W.SLOT[4], label .. ": Blizzard's Totemic Recall anchor replaced ours, no second anchor")
    check(TotemsPlaced(c.cfg), label .. ": the totem buttons stay through a combat bar update")
    local l, _, _, t = Rect(W.SUMMON)
    local hl, _, _, ht = Rect(_G.ERB_CallTotemBarFrame)
    check(near(l, hl) and near(t, ht), label .. ": Call of the Elements stays too")
    check(#W.violations == 0, label .. ": nothing of ours in combat (" .. tostring(W.violations[1]) .. ")")
    LeaveCombat()
    check(BarAtHolder() and Placed(c.cfg, label), label .. ": regen lays everything out again")
end

-------------------------------------------------------------------------------
-- 4. The bar frame's own mouse: off while the bar is ours, back on hand-back,
--    never written in combat. The Edit Mode store is never read or written.
-------------------------------------------------------------------------------
do
    local cfg = { enabled = true, iconSize = 30, spacing = 2 }
    local ns = Load(cfg, WORLDS[1].w)
    check(W.bar:IsMouseEnabled() == false, "the bar frame takes no mouse while it is ours")
    check(W.bar.Selection:IsMouseEnabled() == false, "its Edit Mode selection takes none either")
    -- turned off in combat: the hand-back waits, the bar stays ours and pinned
    EnterCombat()
    cfg.enabled = false
    ns.CT_Apply()
    check(#W.violations == 0, "turning it off in combat writes nothing (" .. tostring(W.violations[1]) .. ")")
    check(W.bar:IsMouseEnabled() == false and _G.ERB_CallTotemBarFrame:IsShown(), "the hand-back waits for regen")
    LeaveCombat()
    check(W.bar:IsMouseEnabled() == true, "the hand-back puts the bar frame's mouse back")
    check(W.bar.Selection:IsMouseEnabled() == true, "and its selection's")
    check(_G.ERB_CallTotemBarFrame:IsShown() == false, "the holder hides")
    local onHolder
    for _, f in ipairs(W.frames) do
        for _, p in ipairs(f._points) do
            if p.rel == _G.ERB_CallTotemBarFrame then onHolder = f._name end
        end
    end
    check(onHolder == nil, "nothing hangs from the holder after the hand-back (" .. tostring(onHolder) .. ")")
    check(W.SLOT[1]._points[1].rel == W.bar and W.ACT[1]._points[1].rel == W.PAGE[1]
        and W.RECALL._points[1].rel == W.SLOT[4], "the buttons are back on Blizzard's own anchors")
    check(W.bar._scale == 1 and W.bar._w == 230 and W.bar._h == 38, "the bar has its own scale and size back")
    -- on again: ours again, the mouse off again
    cfg.enabled = true
    ns.CT_Apply()
    check(W.bar:IsMouseEnabled() == false and Placed(cfg, "on again"), "turned on again: laid out, the mouse off")
    cfg.enabled = false
    ns.CT_Apply()
    check(W.bar:IsMouseEnabled() == true, "and handed back with the mouse it had")
    check(W.editMode == 0, "the Edit Mode layouts are never read or saved")
    check(#W.violations == 0, "no Edit Mode override and no combat write overall (" .. tostring(W.violations[1]) .. ")")
end

-------------------------------------------------------------------------------
-- 5. The hand-back puts back the mouse state its own takeover found
-------------------------------------------------------------------------------
do
    local cfg = { enabled = false, iconSize = 30, spacing = 2 }
    local ns = Load(cfg, WORLDS[1].w)
    check(_G.ERB_CallTotemBarFrame == nil and W.bar:IsMouseEnabled() == true, "off: nothing built, the bar untouched")
    cfg.enabled = true
    ns.CT_Apply()
    cfg.enabled = false
    ns.CT_Apply()
    check(W.bar:IsMouseEnabled() == true, "found on: put back on")
    -- found off the next time: off is what goes back
    W.bar._mouse = false
    cfg.enabled = true
    ns.CT_Apply()
    cfg.enabled = false
    ns.CT_Apply()
    check(W.bar:IsMouseEnabled() == false, "found off: put back off")
end

-------------------------------------------------------------------------------
--  The list of totems (Blizzard's flyout) and its arrow
-------------------------------------------------------------------------------
-- The mouse on a button (Blizzard shows the arrow there) and a click on the
-- arrow (Blizzard toggles the button's list). kind: "slot", or "page" for
-- Call of the Elements.
local function Hover(btn, kind) Blizz(MultiCastFlyoutFrameOpenButton_Show, W.arrow, kind or "slot", btn) end
local function Toggle(btn, kind) Blizz(MultiCastFlyoutFrame_ToggleFlyout, W.flyout, kind or "slot", btn) end
local function Kind(btn) return btn == W.SUMMON and "page" or "slot" end

-- Where the open list sits against its button, on its one anchor: "above"
-- (Blizzard's own spot, centred on the button's top edge), "right" or "left"
-- (beside it, 2 of the bar's units away, their bottom edges level), else nil.
local function ListSide(btn)
    local f = W.flyout
    if not f:IsShown() or #f._points ~= 1 then return nil end
    local l, b, r = Rect(f)
    local bl, bb, br, bt = Rect(btn)
    local gap = 2 * EffScale(f)
    if near(b, bt) and near((l + r) / 2, (bl + br) / 2) then return "above" end
    if near(l, br + gap) and near(b, bb) then return "right" end
    if near(r, bl - gap) and near(b, bb) then return "left" end
    return nil
end

-- The same for the arrow: "above", or "right" / "left" (against the button's
-- side, their middles level).
local function ArrowSide(btn)
    local a = W.arrow
    if not a:IsShown() or #a._points ~= 1 or a:GetParent() ~= btn then return nil end
    local l, b, r, t = Rect(a)
    local bl, bb, br, bt = Rect(btn)
    if near(b, bt) and near((l + r) / 2, (bl + br) / 2) then return "above" end
    if near(l, br) and near((b + t) / 2, (bb + bt) / 2) then return "right" end
    if near(r, bl) and near((b + t) / 2, (bb + bt) / 2) then return "left" end
    return nil
end

-- The first shown button of the bar a rect lies over (nil: none); with no
-- rect, the list's own.
local function ListCovers(l, b, r, t)
    if not l then l, b, r, t = Rect(W.flyout) end
    for _, g in ipairs(Shown()) do
        local gl, gb, gr, gt = Rect(g)
        if l < gr - 1e-6 and gl < r - 1e-6 and b < gt - 1e-6 and gb < t - 1e-6 then return g._name end
    end
    return nil
end

-- The rect the list would have on Blizzard's own anchor, above btn.
local function AboveRect(btn)
    local f = W.flyout
    local keep = f._points
    f._points = { { point = "BOTTOM", rel = btn, relPoint = "TOP", x = 0, y = 0 } }
    local l, b, r, t = Rect(f)
    f._points = keep
    return l, b, r, t
end

local function Clears(f) return f._clears or 0 end

local function Column(direction)
    return { enabled = true, iconSize = 24, spacing = 5, orientation = "VERTICAL", flyoutDirection = direction }
end

-------------------------------------------------------------------------------
-- 6. A column: the list of totems opens beside its button, on the Flyout
--    Direction side, and the arrow shows there. Above the button, Blizzard's
--    own spot, it would lie over the buttons above.
-------------------------------------------------------------------------------
for _, d in ipairs({ { false, "right" }, { "RIGHT", "right" }, { "LEFT", "left" } }) do
    for _, w in ipairs(WORLDS) do
        local cfg = Column(d[1] or nil)
        local label = "column, Flyout Direction " .. tostring(d[1] or "unset") .. " / " .. w.name
        Load(cfg, w.w)
        local list = Shown()
        for i, btn in ipairs(list) do
            if btn ~= W.RECALL then
                local at = label .. ", button " .. i
                Hover(btn, Kind(btn))
                check(ArrowSide(btn) == d[2], at .. ": the arrow shows on the " .. d[2] .. " (" .. tostring(ArrowSide(btn)) .. ")")
                Toggle(btn, Kind(btn))
                check(ListSide(btn) == d[2], at .. ": the list opens on the " .. d[2] .. " (" .. tostring(ListSide(btn)) .. ")")
                check(ListCovers() == nil, at .. ": the open list lies over no button (" .. tostring(ListCovers()) .. ")")
                check(not W.arrow:IsShown(), at .. ": the open list hides the arrow")
                if i > 1 then
                    check(ListCovers(AboveRect(btn)) ~= nil, at .. ": above its button the list would lie over one (the trouble is modelled)")
                end
                Toggle(btn, Kind(btn))
                check(not W.flyout:IsShown() and W.flyout.parent == nil, at .. ": a second click closes the list")
            end
        end
        -- from one button's list straight to the next button's
        if list[2] and list[2] ~= W.RECALL then
            Toggle(list[1], Kind(list[1]))
            Toggle(list[2], Kind(list[2]))
            check(W.flyout.parent == list[2] and ListSide(list[2]) == d[2], label .. ": the next button's list opens beside that button, on one anchor")
            check(ListCovers() == nil, label .. ": and lies over no button")
        end
        check(#W.violations == 0, label .. ": no Edit Mode override and no combat write (" .. tostring(W.violations[1]) .. ")")
    end
end

-------------------------------------------------------------------------------
-- 7. A row: the list and the arrow stay where Blizzard puts them, above the
--    button, and nothing of ours re-anchors either.
-------------------------------------------------------------------------------
for _, c in ipairs({ CONFIGS[1], CONFIGS[2],
                     { name = "row, Flyout Direction Left", cfg = { enabled = true, iconSize = 30, spacing = 2, flyoutDirection = "LEFT" } },
                     { name = "row by name, Flyout Direction Right", cfg = { enabled = true, iconSize = 30, spacing = 2, orientation = "HORIZONTAL", flyoutDirection = "RIGHT" } } }) do
    Load(c.cfg, WORLDS[1].w)
    for i, btn in ipairs(Shown()) do
        if btn ~= W.RECALL then
            local at = c.name .. ", button " .. i
            Hover(btn, Kind(btn))
            check(ArrowSide(btn) == "above", at .. ": the arrow is above (" .. tostring(ArrowSide(btn)) .. ")")
            Toggle(btn, Kind(btn))
            check(ListSide(btn) == "above", at .. ": the list is above (" .. tostring(ListSide(btn)) .. ")")
            check(ListCovers() == nil, at .. ": and lies over no button")
            Toggle(btn, Kind(btn))
        end
    end
    check(Clears(W.flyout) == 0 and Clears(W.arrow) == 0, c.name .. ": nothing of ours re-anchors the list or the arrow")
end

-------------------------------------------------------------------------------
-- 8. In combat: neither the list nor the arrow is secure, so both take their
--    side there too, also while Edit Mode has the bar frame somewhere else.
-------------------------------------------------------------------------------
for _, d in ipairs({ { "RIGHT", "right" }, { "LEFT", "left" } }) do
    local cfg = Column(d[1])
    local label = "combat, Flyout Direction " .. d[1]
    Load(cfg, WORLDS[1].w)
    EnterCombat()
    Blizz(EditModeManagerFrame.UpdateBottomActionBarPositions, EditModeManagerFrame)
    check(not BarAtHolder(), label .. ": the stack moved the bar frame")
    for i, btn in ipairs(Shown()) do
        if btn ~= W.RECALL then
            local at = label .. ", button " .. i
            Hover(btn, Kind(btn))
            check(ArrowSide(btn) == d[2], at .. ": the arrow shows on the " .. d[2])
            Toggle(btn, Kind(btn))
            check(ListSide(btn) == d[2] and ListCovers() == nil, at .. ": the list opens on the " .. d[2] .. ", over no button")
            Toggle(btn, Kind(btn))
        end
    end
    check(#W.violations == 0, label .. ": nothing of ours writes to a protected frame (" .. tostring(W.violations[1]) .. ")")
    LeaveCombat()
    check(BarAtHolder() and Placed(cfg, label), label .. ": regen lays the bar out again")
end

-------------------------------------------------------------------------------
-- 9. A list that is open when a setting changes takes its new place at once:
--    Flyout Direction, the orientation, and the hand-back.
-------------------------------------------------------------------------------
do
    local cfg = Column(nil)
    local ns = Load(cfg, WORLDS[1].w)
    local btn = W.SLOT[2]
    Toggle(btn)
    check(ListSide(btn) == "right", "an open list: beside its slot, on the right")

    -- Flyout Direction, as its options row changes it
    check(type(ns.CT_PlaceFlyout) == "function", "the options can ask for an open list to be placed")
    local place = ns.CT_PlaceFlyout or function() end
    cfg.flyoutDirection = "LEFT"
    place()
    check(ListSide(btn) == "left", "Flyout Direction Left moves the open list to the left (" .. tostring(ListSide(btn)) .. ")")
    cfg.flyoutDirection = "RIGHT"
    place()
    check(ListSide(btn) == "right", "and Right moves it back (" .. tostring(ListSide(btn)) .. ")")
    place()
    check(ListSide(btn) == "right", "asked again with nothing changed: it stays")

    -- the bar becomes a row: the list goes above its slot
    cfg.orientation = "HORIZONTAL"
    ns.CT_Apply()
    check(Placed(cfg, "column to row"), "column to row: the buttons are a row")
    check(ListSide(btn) == "above", "column to row: the open list goes above its slot (" .. tostring(ListSide(btn)) .. ")")
    check(ListCovers() == nil, "column to row: it lies over no button (" .. tostring(ListCovers()) .. ")")
    -- and a column again
    cfg.orientation = "VERTICAL"
    ns.CT_Apply()
    check(Placed(cfg, "row to column"), "row to column: the buttons are a column")
    check(ListSide(btn) == "right", "row to column: the open list goes beside its slot (" .. tostring(ListSide(btn)) .. ")")
    check(ListCovers() == nil, "row to column: it lies over no button (" .. tostring(ListCovers()) .. ")")

    -- in combat the apply waits for regen, and the open list with it
    EnterCombat()
    cfg.orientation = "HORIZONTAL"
    ns.CT_Apply()
    check(ListSide(btn) == "right" and #W.violations == 0, "in combat the orientation waits: the list stays beside its slot")
    LeaveCombat()
    check(Placed(cfg, "regen") and ListSide(btn) == "above", "regen: a row, the open list above its slot (" .. tostring(ListSide(btn)) .. ")")
    cfg.orientation = "VERTICAL"
    ns.CT_Apply()
    check(ListSide(btn) == "right", "a column again: beside its slot")

    -- the hand-back with the list open: Blizzard's own anchor at once
    cfg.enabled = false
    ns.CT_Apply()
    local p = W.flyout._points[1]
    check(ListSide(btn) == "above", "turned off with the list open: it goes above its slot (" .. tostring(ListSide(btn)) .. ")")
    check(#W.flyout._points == 1 and p.point == "BOTTOM" and p.rel == btn and p.relPoint == "TOP" and p.x == 0 and p.y == 0,
        "turned off with the list open: on Blizzard's own anchor")
    check(W.SLOT[1]._points[1].rel == W.bar, "and the buttons are back on Blizzard's anchors")
    check(#W.violations == 0, "no Edit Mode override and no combat write (" .. tostring(W.violations[1]) .. ")")
end

-- a closed list, and a row's list that was never moved, are left alone
do
    local cfg = Column("LEFT")
    local ns = Load(cfg, WORLDS[1].w)
    local place = ns.CT_PlaceFlyout or function() end
    local points = W.flyout._points
    place()
    ns.CT_Apply()
    check(W.flyout._points == points and Clears(W.flyout) == 0, "a closed list is not touched by a settings pass")
    check(not W.flyout:IsShown(), "and stays closed")

    cfg = { enabled = true, iconSize = 30, spacing = 2, flyoutDirection = "LEFT" }
    ns = Load(cfg, WORLDS[1].w)
    place = ns.CT_PlaceFlyout or function() end
    Toggle(W.SLOT[3])
    place()
    ns.CT_Apply()
    cfg.flyoutDirection = "RIGHT"
    place()
    check(ListSide(W.SLOT[3]) == "above" and Clears(W.flyout) == 0, "a row's open list stays on Blizzard's anchor through settings passes")
end

-- the arrow after a column became a row: its next show is above its button
-- again, whatever Flyout Direction says, and then it is left to Blizzard
do
    local cfg = Column("LEFT")
    local ns = Load(cfg, WORLDS[1].w)
    local btn = W.SLOT[2]
    Hover(btn)
    check(ArrowSide(btn) == "left", "a column: the arrow shows beside its slot")
    cfg.orientation = "HORIZONTAL"
    ns.CT_Apply()
    Hover(btn)
    check(ArrowSide(btn) == "above", "column to row: the arrow's next show is above its slot (" .. tostring(ArrowSide(btn)) .. ")")
    local clears = Clears(W.arrow)
    Hover(W.SLOT[3])
    check(ArrowSide(W.SLOT[3]) == "above" and Clears(W.arrow) == clears, "column to row: from then on the arrow is left to Blizzard")
end

-------------------------------------------------------------------------------
-- 10. Off: nothing of ours touches the list or the arrow. On, a column, both
--     go beside the button; off again with the list closed, the next show of
--     each is Blizzard's own on one anchor, and then they are left alone.
-------------------------------------------------------------------------------
do
    local cfg = Column("LEFT")
    cfg.enabled = false
    local ns = Load(cfg, WORLDS[1].w)
    local btn = W.SLOT[2]
    Hover(btn)
    check(ArrowSide(btn) == "above", "off: the arrow is where Blizzard puts it")
    Toggle(btn)
    check(ListSide(btn) == "above", "off: the list is where Blizzard puts it")
    Toggle(btn)
    check(Clears(W.flyout) == 0 and Clears(W.arrow) == 0, "off: nothing of ours re-anchors either")

    cfg.enabled = true
    ns.CT_Apply()
    Hover(btn)
    check(ArrowSide(btn) == "left", "on: the arrow shows beside the slot")
    Toggle(btn)
    check(ListSide(btn) == "left", "on: the list opens beside the slot")
    Toggle(btn)

    cfg.enabled = false
    ns.CT_Apply()
    check(not W.flyout:IsShown(), "off again: the closed list stays closed")
    Hover(btn)
    check(ArrowSide(btn) == "above", "off again: the arrow's next show is above its slot, on one anchor (" .. tostring(ArrowSide(btn)) .. ")")
    Toggle(btn)
    check(ListSide(btn) == "above", "off again: the list's next open is above its slot, on one anchor (" .. tostring(ListSide(btn)) .. ")")
    Toggle(btn)
    local fc, ac = Clears(W.flyout), Clears(W.arrow)
    Hover(btn)
    Toggle(btn)
    Toggle(btn)
    Hover(W.SLOT[3])
    Toggle(W.SLOT[3])
    check(Clears(W.flyout) == fc and Clears(W.arrow) == ac, "and from then on both are left to Blizzard")
    check(ListSide(W.SLOT[3]) == "above", "the list still opens above its slot")
    check(#W.violations == 0, "no Edit Mode override and no combat write (" .. tostring(W.violations[1]) .. ")")
end

-------------------------------------------------------------------------------
-- 11. A button with no totems to list: Blizzard opens nothing and nothing of
--     ours moves. An open list stays with its own button.
-------------------------------------------------------------------------------
do
    local cfg = Column(nil)
    Load(cfg, WORLDS[1].w)
    W.listed = 0
    Toggle(W.SLOT[1])
    check(not W.flyout:IsShown() and Clears(W.flyout) == 0, "nothing to list: no list, nothing re-anchored")
    W.listed = 4
    Toggle(W.SLOT[1])
    check(ListSide(W.SLOT[1]) == "right", "totems to list: the list opens beside its slot")
    local clears = Clears(W.flyout)
    W.listed = 0
    Toggle(W.SLOT[3])
    check(W.flyout:IsShown() and W.flyout.parent == W.SLOT[1] and ListSide(W.SLOT[1]) == "right" and Clears(W.flyout) == clears,
        "another button with nothing to list: the open list stays with its own slot")
end

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print("PASS test_rb_call_totem_bar_combat (" .. count .. " checks)")
