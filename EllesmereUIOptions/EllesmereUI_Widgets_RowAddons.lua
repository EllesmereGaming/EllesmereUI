if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_Widgets_RowAddons.lua
--  Row add-ons: inline toggle, cog and button, the row-label and button
--  menus, the less-common expander, inline swatches, the section gates and
--  the cursor anchor row. Reads BuildCogPopup and BuildColorSwatch, so it
--  loads after EllesmereUI_Widgets_CogPopup.lua.
--  DEFERRED: body runs on first EllesmereUI:EnsureLoaded() call, not at load.
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI
EllesmereUI._deferredInits[#EllesmereUI._deferredInits + 1] = function()
-- Options page pool (EllesmereUI_FramePool.lua): frames made here on a pool
-- host are reset and dressed again by the next build instead of made anew;
-- elsewhere this is CreateFrame.
local CreateFrame = EllesmereUI._Pool.CreateFrame
local PP = EllesmereUI.PanelPP
local RegisterWidgetRefresh = EllesmereUI.RegisterWidgetRefresh
local MakeStyledButton = EllesmereUI.MakeStyledButton
local WB_COLOURS = EllesmereUI.WB_COLOURS
local ShowWidgetTooltip = EllesmereUI.ShowWidgetTooltip
local HideWidgetTooltip = EllesmereUI.HideWidgetTooltip
local ResolveDisabledTip = EllesmereUI.ResolveDisabledTip
local BuildToggleControl = EllesmereUI.BuildToggleControl
local BuildColorSwatch = EllesmereUI.BuildColorSwatch
local BuildCogPopup = EllesmereUI.BuildCogPopup
local BuildDropdownMenu = EllesmereUI.BuildDropdownMenu
local WireDropdownScripts = EllesmereUI.WireDropdownScripts

-- Inline toggle: a small toggle placed inline inside a DualRow half-region,
-- chaining left of the control (slider/dropdown) like the sync icon / cog. Used
-- to gate the row's control (e.g. enable/disable the duration text). The toggle
-- itself is never disabled. opts: region, getValue, setValue, onToggle, sizeRatio.
local function BuildInlineToggle(opts)
    local region = opts.region
    if not region then return nil end
    local toggle, _, tgSnap = BuildToggleControl(region, region:GetFrameLevel() + 5,
        opts.getValue,
        function(v)
            if opts.setValue then opts.setValue(v) end
            if opts.onToggle then opts.onToggle(v) end
        end,
        { sizeRatio = opts.sizeRatio or 0.8 })
    toggle:ClearAllPoints()
    toggle:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
    region._lastInline = toggle
    RegisterWidgetRefresh(tgSnap)
    return toggle
end

-- Glyph buttons a page builds itself (the eye preview toggles) set their alpha
-- through SetGlyphAlpha(btn, a) with the plain glyph values (0.15 disabled,
-- 0.4 idle, 0.7 hovered). They show as the cogs' dots below do: 0.55 idle /
-- 0.75 hovered, 0.15 disabled, and linearly between (the Raid & Party Frames
-- eye's 0.6 while its preview is on).
function EllesmereUI.SetGlyphAlpha(btn, a)
    btn._glyphA = a
    btn:SetAlpha(a <= 0.15 and a or math.min(1, 0.55 + (a - 0.4) * 2 / 3))
end

-- Inline cogs draw a vertical ellipsis with an accent notification dot above
-- it. The dot shows on a cog never opened once the user edits its setting, and
-- stays until the panel closes or the cog is opened (an opened cog never shows
-- it again), never while the cog or its setting is disabled; the edit that
-- shows it pulses it. A cog is known by its module, page, section, row label
-- and popup title (so a row repeated per unit or bar has one dot), hashed to
-- five characters; the opened ones are one string, EllesmereUIDB.cogSeen (in
-- no export; /euiresethint clears it).
-- Cog notice: every widget write reaches EllesmereUI._CogWriteNotice(frame)
-- through EllesmereUI._NotifySettingWrite; it lights the dot, and the first
-- change ever to a setting with a cog puts a tip above that cog
-- (EllesmereUIDB.inlineCogTipSeen, cleared by /euiresethint): Okay or a click
-- on a cog dismisses it for good. Once a dot is up, a write to its setting
-- costs one check.
local CogDot = {
    -- Geometry in shares of the cog's height (30, a dropdown's): dots 4 across
    -- and 6.5 apart, the notification dot 7 across with its centre 8 left of
    -- and 3.5 above the top dot's.
    DOT = 4 / 30, STEP = 6.5 / 30, NOTE = 7 / 30, NX = 8 / 30, NY = 3.5 / 30,
    -- Ids: a rolling hash under the largest prime below 2^30, written as five
    -- characters of a 64-character set.
    MOD = 1073741789,
    CHARS = { string.byte("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_", 1, 64) },
    live = setmetatable({}, { __mode = "k" }),   -- the cogs built, for Mark
    -- This panel session, emptied when the panel closes: the ids whose setting
    -- was edited, and the ids whose dot is up since an edit showed it.
    edited = {}, up = {},
}
local cogTip, cogTipCog, cogTipInScroll, cogTipScrollHooked

local function CogTipSeen()
    return EllesmereUIDB and EllesmereUIDB.inlineCogTipSeen
end

-- The cog being built: module, page, section, row label and popup title.
function CogDot.Key(rgn, opts)
    local row = rgn:GetParent()
    local content = row and row:GetParent()
    local sec = content and content._currentSection
    local cfg, title = rgn._cfg, opts.title
    local label = cfg and cfg.text or rgn._labelText
    return (EllesmereUI._buildingModule or EllesmereUI:GetActiveModule() or "") .. "\31"
        .. (EllesmereUI._buildingPage or EllesmereUI:GetActivePage() or "") .. "\31"
        .. (sec and sec._sectionName or "") .. "\31"
        .. (type(label) == "string" and label or "") .. "\31"
        .. (type(title) == "string" and title or "")
end

function CogDot.Id(s)
    local h, mod = 0, CogDot.MOD
    for i = 1, #s do h = (h * 31 + s:byte(i)) % mod end
    local c = CogDot.CHARS
    local a = h % 64; h = (h - a) / 64
    local b = h % 64; h = (h - b) / 64
    local d = h % 64; h = (h - d) / 64
    local e = h % 64; h = (h - e) / 64
    return string.char(c[a + 1], c[b + 1], c[d + 1], c[e + 1], c[h + 1])
end

-- The opened cogs as a set, read from the saved string once a session.
function CogDot.Seen()
    local set = CogDot.set
    if set then return set end
    set = {}
    local str = EllesmereUIDB and EllesmereUIDB.cogSeen
    if type(str) == "string" then
        for i = 1, #str - 4, 5 do set[str:sub(i, i + 4)] = true end
    end
    CogDot.set = set
    return set
end

-- A cog opened for the first time: its id joins the saved string, and every
-- built cog with that id (the same row on another unit or bar) loses its dot.
function CogDot.Mark(id)
    local set = CogDot.Seen()
    if set[id] then return end
    set[id] = true
    if EllesmereUIDB then
        local str = EllesmereUIDB.cogSeen
        EllesmereUIDB.cogSeen = (type(str) == "string" and str or "") .. id
    end
    for b in pairs(CogDot.live) do
        if b._euiCogId == id then
            b._euiCogPulse:Stop()
            b._euiCogNote:Hide()
        end
    end
end

-- Whole pixels from a share of the cog's height, taken of the rounded pixel
-- height (the memo's key) so every cog of one pixel size gets the same dots:
-- of the unrounded height, a share on a half pixel (the step and the
-- notification dot's offsets at 30 pixels) rounds either way with the float
-- error a cog's effective scale carries.
function CogDot.Px(v) return math.floor(v + 0.5) end

-- The dots in whole pixels on the cog's pixel layer: the middle one centred,
-- the others a step above and below, the notification dot (and the pulse ring
-- under it) up and left of the top one.
function CogDot.Fit(L, k)
    local w, h = L.parent:GetSize()
    local wp, hp = math.floor(w * k + 0.5), math.floor(h * k + 0.5)
    if wp == L.wp and hp == L.hp then return end
    L.wp, L.hp = wp, hp
    local Px = CogDot.Px
    local d = math.max(2, Px(hp * CogDot.DOT))
    local step = math.max(d + 1, Px(hp * CogDot.STEP))
    local n = math.max(3, Px(hp * CogDot.NOTE))
    local x, y = math.floor((wp - d) / 2), math.floor((hp - d) / 2)
    local layer = L._frame
    for i = 1, 3 do
        local t = L[i]
        EllesmereUI.SetCircleArt(t, d)
        t:SetSize(d, d)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", layer, "TOPLEFT", x, (2 - i) * step - y)
    end
    -- Its outer edge reaches as far past the column's left edge as the same
    -- spot to the right would past its right edge, so the rounding mirrors.
    -- Kept inside the button, which a small cog's rounded sizes can leave.
    local reach = Px((d - n) / 2 + hp * CogDot.NX) + n - d
    local nx = math.max(0, x - reach)
    local ny = math.max(0, Px(y - step + (d - n) / 2 - hp * CogDot.NY))
    local note, ring = L.note, L.ring
    EllesmereUI.SetCircleArt(note, n)
    note:SetSize(n, n)
    note:ClearAllPoints()
    note:SetPoint("TOPLEFT", layer, "TOPLEFT", nx, -ny)
    EllesmereUI.SetCircleArt(ring, n)
    ring:SetSize(n, n)
    ring:ClearAllPoints()
    ring:SetPoint("CENTER", note, "CENTER")
end

-- The pulse: a ring of the dot's colour grows from it and fades, three times.
function CogDot.PulseLoop(ag)
    local n = (ag._euiLoops or 0) + 1
    ag._euiLoops = n
    if n >= 3 then ag:Stop() end
end

function CogDot.Pulse(cog)
    local ag = cog._euiCogPulse
    ag._euiLoops = 0
    ag:Play()
end

-- An edit to the setting of a cog never opened: its dot shows here and on the
-- cog's twins until the panel closes, and every dot this edit brings up on
-- screen pulses.
function CogDot.Edited(id)
    if CogDot.Seen()[id] then return end
    CogDot.edited[id] = true
    local up
    for b in pairs(CogDot.live) do
        if b._euiCogId == id and b._euiCogState then
            b._euiCogState()
            if b._euiCogNote:IsShown() and b:IsVisible() then
                up = true
                CogDot.Pulse(b)
            end
        end
    end
    CogDot.up[id] = up
end

-- The panel closed (not hidden with the UI, which leaves it shown): this
-- session's dots go.
function CogDot.PanelClosed()
    if EllesmereUI:IsShown() or not next(CogDot.edited) then return end
    local edited = CogDot.edited
    for b in pairs(CogDot.live) do
        if edited[b._euiCogId] then
            b._euiCogPulse:Stop()
            b._euiCogNote:Hide()
        end
    end
    wipe(edited)
    wipe(CogDot.up)
end
EllesmereUI:RegisterOnHide(CogDot.PanelClosed)

local function HideCogTip()
    cogTipCog = nil
    if cogTip then cogTip:Hide() end
end

local function CogTipDone()
    HideCogTip()
    if EllesmereUIDB then EllesmereUIDB.inlineCogTipSeen = true end
end

-- A cog that hides (page switch, panel close, its page built again) takes its
-- tip with it, unseen: the next change shows it again. A pulse stops with it.
local function CogHidden(self)
    if self == cogTipCog then HideCogTip() end
    self._euiCogPulse:Stop()
end

local function InScrollArea(f)
    local sf = EllesmereUI._scrollFrame
    while f do
        if f == sf then return true end
        f = f:GetParent()
    end
    return false
end

-- For a cog in the scrolled content, the tip shows only while the cog's
-- centre is inside the scroll area: scrolled out it hides, back in it shows.
local function CogTipScroll()
    if not (cogTipCog and cogTipInScroll) then return end
    local sf = EllesmereUI._scrollFrame
    local _, cy = cogTipCog:GetCenter()
    local top, bottom = sf:GetTop(), sf:GetBottom()
    if cy and top and bottom and cy <= top and cy >= bottom then
        if not cogTip:IsShown() then EllesmereUI.ShowTipCallout(cogTip) end
    elseif cogTip:IsShown() then
        cogTip:Hide()
    end
end

local function ShowCogTip(cog)
    if cogTip and cogTipCog == cog and cogTip:IsShown() then return end
    if not cogTip then
        -- The panel tips' metrics (the Raid & Party Frames eye tip's), on the
        -- panel body: it rides the panel scale and hides with the panel.
        cogTip = EllesmereUI.BuildTipCallout(EllesmereUI._panelBody, {
            width = 250, arrow = "bottom",
            -- "icon": a third of the inline cogs wear the directions or resize glyph.
            text = EllesmereUI.L("This setting has more options.\nClick this icon to see them."),
            fontSize = 10, textTop = 12, textInset = 24, spacing = 4, bgAlpha = 0.95,
            btnW = 70, btnH = 22, btnBottom = 10, btnFontSize = 10,
            onOkay = CogTipDone,
        })
    end
    cogTipCog = cog
    cogTipInScroll = InScrollArea(cog)
    if cogTipInScroll and not cogTipScrollHooked then
        cogTipScrollHooked = true
        EllesmereUI._scrollFrame:HookScript("OnVerticalScroll", CogTipScroll)
    end
    cogTip:ClearAllPoints()
    cogTip:SetPoint("BOTTOM", cog, "TOP", 0, 14)
    if not cogTip:IsShown() then EllesmereUI.ShowTipCallout(cogTip) end
end

-- frame: the widget that wrote (or its region); the cog is the one its DualRow
-- half (frame or one of its two parents) registered (a page the setter built
-- again holds a new cog of the same id, which CogDot.Edited finds). A disabled
-- cog is left alone; the tip goes to a visible one.
function EllesmereUI._CogWriteNotice(frame)
    if type(frame) ~= "table" or EllesmereUI._prebuilding then return end
    local cog
    for _ = 1, 3 do
        cog = frame._euiCog
        if cog or not frame.GetParent then break end
        frame = frame:GetParent()
        if not frame then return end
    end
    if not cog then return end
    local id, off = cog._euiCogId, cog._euiCogOff
    if off and off() then
        -- The edit turned its own cog off: the one that turns it back on
        -- brings the dot up again, with its pulse.
        CogDot.up[id] = nil
        return
    end
    if not CogDot.up[id] then CogDot.Edited(id) end
    if not CogTipSeen() and cog:IsVisible() then ShowCogTip(cog) end
end

-- Inline cog button on a DualRow half-region, left of its control (or of the last inline item). Returns cogBtn, showFn; nil during the search prebuild.
-- opts: BuildCogPopup's own opts (title, rows, captureRegion, minWidth, ...) or show(btn) + optional isOpen(btn) for a custom popup; size (the height: 30, a
--   dropdown's; the button is 0.8 as wide), gap (8), anchorTo,
--   relPoint (the anchor's side the cog's right edge sits on, LEFT; a host that is not a DualRow half passes anchorTo = itself, relPoint = "RIGHT", gap = 0),
--   chain (default true: anchors to and becomes region._lastInline), tip, disabled + disabledTooltip/rawTooltip/requireState (as ResolveDisabledTip; default: the host control's).
-- Every inline cog draws the vertical ellipsis with its accent notification dot (CogDot above): white dots at 0.55, 0.75 hovered or while its popup is open,
--   0.15 disabled (the button at 0.3). Disabled blocks the click and shows the requirement tooltip. A button that paints its own states, opts.paint(btn, off, hot),
--   draws opts.icon bare instead, 26 square and with no dot (the unlock jump).
-- A cog with a dot is the one its region's writes light (the cog notice above; the last such cog built on the region).
-- opts.quiet: a cog whose rows are not for most users; its region's writes never light its dot or bring the cog tip up.
local function BuildInlineCog(rgn, opts)
    if EllesmereUI._prebuilding then return end
    -- A disabled cog with no tooltip of its own explains itself with its host control's requirement.
    local tipSrc = (opts.disabled and not opts.disabledTooltip) and rgn._cfg or opts
    if opts.disabled and not (tipSrc and tipSrc.disabledTooltip) and EllesmereUI.IsDevModeActive() then
        error("BuildInlineCog: disabled needs a disabledTooltip", 2)
    end
    local show = opts.show or select(2, BuildCogPopup(opts))
    local paint = opts.paint
    local h = opts.size or (paint and 26 or 30)
    local btn = CreateFrame("Button", nil, rgn)
    btn:SetSize(paint and h or math.floor(h * 0.8 + 0.5), h)
    PP.Point(btn, "RIGHT", opts.anchorTo or (opts.chain ~= false and rgn._lastInline) or rgn._control or rgn, opts.relPoint or "LEFT", -(opts.gap or 8), 0)
    if opts.chain ~= false then rgn._lastInline = btn end
    btn:SetFrameLevel(rgn:GetFrameLevel() + 5)
    local tex, L, note, id, hostCfg
    if paint then
        tex = btn:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(opts.icon)
        tex:SetAllPoints()
        btn._icon = tex
    else
        -- The three dots, the notification dot and its pulse ring: white and
        -- accent art on a pixel layer, placed in whole pixels (CogDot.Fit).
        L = EllesmereUI.MakePixelLayer(btn, CogDot.Fit)
        local layer = L._frame
        L[1] = layer:CreateTexture(nil, "ARTWORK")
        L[2] = layer:CreateTexture(nil, "ARTWORK")
        L[3] = layer:CreateTexture(nil, "ARTWORK")
        local ring = layer:CreateTexture(nil, "OVERLAY")
        note = layer:CreateTexture(nil, "OVERLAY", nil, 1)
        L.note, L.ring = note, ring
        local r, g, b = EllesmereUI.GetAccentColor()
        note:SetVertexColor(r, g, b, 1)
        ring:SetVertexColor(r, g, b, 1)
        ring:SetAlpha(0)
        -- Keyed by the textures: the page pool forgets the entries when it resets them.
        EllesmereUI.RegAccent({ type = "vertex", obj = note })
        EllesmereUI.RegAccent({ type = "vertex", obj = ring })
        local pulse = ring:CreateAnimationGroup()
        local grow = pulse:CreateAnimation("Scale")
        grow:SetScaleFrom(1, 1)
        grow:SetScaleTo(2.6, 2.6)
        grow:SetOrigin("CENTER", 0, 0)
        grow:SetDuration(0.9)
        grow:SetSmoothing("OUT")
        local fade = pulse:CreateAnimation("Alpha")
        fade:SetFromAlpha(0.7)
        fade:SetToAlpha(0)
        fade:SetDuration(0.9)
        fade:SetSmoothing("OUT")
        pulse:SetLooping("REPEAT")
        pulse:SetScript("OnLoop", CogDot.PulseLoop)
        L:Fit()
        id = CogDot.Id(CogDot.Key(rgn, opts))
        hostCfg = rgn._cfg
        btn._euiCogId, btn._euiCogNote, btn._euiCogPulse = id, note, pulse
        CogDot.live[btn] = true
        -- The cog notice: the region's writes light this cog, unless it is a quiet one.
        btn._euiCogOff = opts.disabled
        if not opts.quiet then rgn._euiCog = btn end
        btn:SetScript("OnHide", CogHidden)
    end

    local block
    if opts.disabled then
        block = CreateFrame("Frame", nil, btn)
        block:SetAllPoints()
        block:SetFrameLevel(btn:GetFrameLevel() + 10)
        block:EnableMouse(true)
        block:SetScript("OnEnter", function()
            local tip = tipSrc and ResolveDisabledTip(tipSrc)
            if tip then ShowWidgetTooltip(btn, tip) end
        end)
        block:SetScript("OnLeave", function() HideWidgetTooltip() end)
    end
    -- hover: the enter / leave scripts say which edge they are (a rect test at
    -- the moment of the event can disagree with the hit test on an edge);
    -- a refresh pass asks the rect.
    local function State(hover)
        local off = opts.disabled and opts.disabled()
        local pf = type(show) == "table" and show._popupFrame
        local open = (opts.isOpen and opts.isOpen(btn)) or (pf and pf:IsShown() and pf._owner == btn)
        local hot = open
        if not hot then
            if hover == nil then hot = btn:IsMouseOver() else hot = hover end
        end
        -- opts.paint(btn, off, hot) paints the states itself (the unlock jump).
        -- The dots: 0.55 idle, 0.75 hovered or open, 0.15 disabled through the
        -- button's 0.3. The notification dot once its setting was edited this
        -- panel session, until the cog is first opened, never while the cog or
        -- the setting it sits on is disabled.
        if paint then paint(btn, off, hot)
        else
            btn:SetAlpha(off and 0.3 or 1)
            local a = off and 0.5 or (hot and 0.75 or 0.55)
            L[1]:SetAlpha(a)
            L[2]:SetAlpha(a)
            L[3]:SetAlpha(a)
            local dot = CogDot.edited[id] == true and not (off or CogDot.Seen()[id]
                or (hostCfg and hostCfg.disabled and hostCfg.disabled()))
            note:SetShown(dot)
            if not dot then btn._euiCogPulse:Stop() end
        end
        if block then block:SetShown(off and true or false) end
    end
    btn._euiCogState = State
    -- opts.paint reads the accent (the unlock jump), so it repaints on accent changes.
    -- Keyed by the texture: the page pool forgets the entry when it resets it.
    if paint then EllesmereUI.RegAccent({ type = "callback", obj = tex, fn = function() State() end }) end

    btn:SetScript("OnEnter", function(self)
        State(true)
        if opts.tip then ShowWidgetTooltip(self, opts.tip) end
    end)
    btn:SetScript("OnLeave", function()
        State(false)
        if opts.tip then HideWidgetTooltip() end
    end)
    btn:SetScript("OnClick", function(self)
        -- A cog clicked while the cog tip is up: the tip has done its job.
        -- Opened once, its dot is gone for good.
        if not paint then
            if cogTipCog then CogTipDone() end
            CogDot.Mark(id)
        end
        show(self)
    end)
    State()
    -- A refresh re-reads the disabled states: the cog's own and, for the dot,
    -- its setting's.
    if opts.disabled or (hostCfg and hostCfg.disabled) then RegisterWidgetRefresh(State) end
    return btn, show
end

-- Inline text button on a DualRow half-region, left of its last inline item or
-- control (or at the half's right edge when it has neither, e.g. a label half).
-- opts: width (110), height (24), gap (8), chain (default true: becomes
-- region._lastInline), tip (a string, or a function returning one: the hover
-- tooltip while enabled), disabled + disabledTooltip/rawTooltip/requireState
-- (as ResolveDisabledTip): greyed, click-blocked, without hover colours and
-- explaining itself on hover while disabled, re-checked with the page's
-- widgets. Returns the button; nil during the search prebuild.
function EllesmereUI.BuildInlineButton(rgn, text, onClick, opts)
    if EllesmereUI._prebuilding then return end
    opts = opts or {}
    local btn = CreateFrame("Button", nil, rgn)
    PP.Size(btn, opts.width or 110, opts.height or 24)
    local anchor = (opts.chain ~= false and rgn._lastInline) or rgn._control
    if anchor then
        PP.Point(btn, "RIGHT", anchor, "LEFT", -(opts.gap or 8), 0)
    else
        PP.Point(btn, "RIGHT", rgn, "RIGHT", -20, 0)
    end
    if opts.chain ~= false then rgn._lastInline = btn end
    btn:SetFrameLevel(rgn:GetFrameLevel() + 5)
    MakeStyledButton(btn, text, 11, WB_COLOURS, onClick)
    local tip, disabled = opts.tip, opts.disabled
    if not (tip or disabled) then return btn end
    -- The styled button's hover scripts paint its hover colours; these wrap
    -- them so a disabled button keeps its resting colours.
    local hoverOn, hoverOff = btn:GetScript("OnEnter"), btn:GetScript("OnLeave")
    -- A state with no text hides the other state's tooltip (a flip replays this).
    local function OnEnter(self)
        if disabled and disabled() then
            hoverOff(self)
            local t = ResolveDisabledTip(opts)
            if t then ShowWidgetTooltip(self, t) else HideWidgetTooltip() end
            return
        end
        hoverOn(self)
        local t = tip
        if type(t) == "function" then t = t() end
        if t then ShowWidgetTooltip(self, t) else HideWidgetTooltip() end
    end
    btn:SetScript("OnEnter", OnEnter)
    btn:SetScript("OnLeave", function(self)
        hoverOff(self)
        HideWidgetTooltip()
    end)
    if disabled then
        -- Motion scripts keep running while disabled, so hover explains the lock.
        btn:SetMotionScriptsWhileDisabled(true)
        local shownOff
        local function State()
            local off = disabled() and true or false
            if off == shownOff then return end
            local flipped = shownOff ~= nil
            shownOff = off
            btn:SetEnabled(not off)
            btn:SetAlpha(off and 0.35 or 1)
            -- A flip while it holds the mouse repaints and re-explains for the
            -- new state (a menu open over it keeps the focus instead).
            if flipped and GetMouseFoci()[1] == btn then OnEnter(btn) end
        end
        State()
        RegisterWidgetRefresh(State)
    end
    return btn
end

-- Opens Unlock Mode from an options row with the element `key` selected and
-- its mover flashed once the movers have faded in: the sidebar entry's path
-- (the active module and page become the return target the exit reopens; the
-- panel stays shown, since the open animation reads its size and shrinks and
-- hides it itself, and Spec Overrides stashes its editing session only while
-- the panel still shows) plus the auto-select key and the flash flag the end
-- of the open animation reads. In combat nothing changes and the red chat line
-- explains. Returns whether the open was requested.
function EllesmereUI.OpenUnlockModeAt(key)
    if InCombatLockdown() then
        EllesmereUI.PrintError("Cannot enter Unlock Mode during combat.")
        return false
    end
    -- Installed by the unlock core's init, so a live check rather than a dead guard.
    if not EllesmereUI._openUnlockMode then return false end
    EllesmereUI._unlockReturnModule = EllesmereUI:GetActiveModule()
    EllesmereUI._unlockReturnPage = EllesmereUI:GetActivePage()
    EllesmereUI._unlockAutoSelectKey = key
    EllesmereUI._unlockAutoSelectFlash = true
    C_Timer.After(0, EllesmereUI._openUnlockMode)
    return true
end

-- "Move in Unlock Mode" inline button on a DualRow half-region: an inline cog
-- (BuildInlineCog's placement, chain, alphas, tooltip and disabled block) that
-- wears the unlocked-lock glyph and whose click is OpenUnlockModeAt(opts.key).
-- opts: key (the unlock element to select: a string, or a function returning
-- it at the click, for a page whose selector picks the element), tooltip
-- ("Move in Unlock Mode"), disabled + disabledTooltip/rawTooltip/requireState,
-- size, gap, anchorTo, relPoint, chain (as BuildInlineCog). Returns the
-- button; nil during the search prebuild.
-- The glyph in the accent: 70% at rest, full while hovered, 20% while
-- disabled (owner 2026-10-23).
local function UnlockJumpPaint(btn, off, hot)
    btn:SetAlpha(off and 0.2 or (hot and 1 or 0.7))
    local r, g, b = EllesmereUI.GetAccentColor()
    btn._icon:SetVertexColor(r, g, b)
end

function EllesmereUI.BuildUnlockJump(rgn, opts)
    if EllesmereUI._prebuilding then return end
    local key = opts.key
    local btn = BuildInlineCog(rgn, {
        icon = EllesmereUI.UNLOCK_ICON,
        tip = opts.tooltip or "Move in Unlock Mode",
        show = function()
            local k = key
            if type(k) == "function" then k = k() end
            if k then EllesmereUI.OpenUnlockModeAt(k) end
        end,
        disabled = opts.disabled, disabledTooltip = opts.disabledTooltip,
        rawTooltip = opts.rawTooltip, requireState = opts.requireState,
        size = opts.size, gap = opts.gap, anchorTo = opts.anchorTo,
        relPoint = opts.relPoint, chain = opts.chain,
        paint = UnlockJumpPaint,
    })
    -- The glyph's art is square (30x30), so the cog icon's own fill of the
    -- button is its fit; drawn unsnapped, since it lands between texel sizes.
    local icon = btn._icon
    if icon.SetSnapToPixelGrid then icon:SetSnapToPixelGrid(false); icon:SetTexelSnappingBias(0) end
    return btn
end

-- "Move in Unlock Mode" on a section header (W:SectionHeader's frame): the
-- same glyph button, right after the title. One per movable element, on the
-- first section of that element's settings (owner 2026-10-21): a page whose
-- selector picks the element (an action bar, a unit frame, a CDM bar) passes
-- a key FUNCTION that reads the selection, so the click highlights that one.
-- opts: key (string or function), tooltip, disabled + disabledTooltip/
-- rawTooltip/requireState (the element's own enable, where it has one), size
-- (20). Returns the button; nil during the search prebuild or without a
-- titled header.
function EllesmereUI.BuildSectionUnlockJump(hdr, opts)
    if EllesmereUI._prebuilding then return end
    local label = hdr and hdr._label
    if not label then return end
    local size = opts.size or 20
    local btn = EllesmereUI.BuildUnlockJump(hdr, {
        key = opts.key, tooltip = opts.tooltip,
        disabled = opts.disabled, disabledTooltip = opts.disabledTooltip,
        rawTooltip = opts.rawTooltip, requireState = opts.requireState,
        size = size, chain = false, anchorTo = label, relPoint = "RIGHT", gap = 0,
    })
    btn:ClearAllPoints()
    PP.Point(btn, "LEFT", label, "RIGHT", 3, 0)
    return btn
end

-------------------------------------------------------------------------------
--  Row-Label and Button Menus
--  The standard dropdown list opened from something that is not a dropdown
--  control: a DualRow half's own label (BuildRowLabelMenu) or a button
--  (AttachButtonMenu). The list is built on first open, takes the standard
--  open/close behaviour and closes when its button hides. A pick writes its
--  caption into a hidden stand-in, never over the label or the button's text.
-------------------------------------------------------------------------------
local ROW_MENU_ARROW = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-arrow-down3.png"
-- WireDropdownScripts paints a dropdown button's border and background; these
-- buttons keep their own look.
local NO_PAINT = { SetColor = function() end, SetColorTexture = function() end }
local function NoSelection() return nil end

-- The accent, or a darker white when the accent itself is near white.
local function RowMenuLitColor()
    local ac = EllesmereUI.ELLESMERE_GREEN
    if ac.r > 0.9 and ac.g > 0.9 and ac.b > 0.9 then return 0.72, 0.72, 0.72 end
    return ac.r, ac.g, ac.b
end

-- A button over the half's label, with a chevron after the label: label and
-- chevron white at rest, in the accent while hovered or while the list is open.
-- opts: order, values, getValue(), setValue(v), itemDisabled(v) (nil, true or a
--   tooltip string, as BuildDropdownMenu's disabledValuesFn), tooltip (on hover
--   while the list is closed), menuWidth (170); optional locked() + lockTip() +
--   rawLockTip (as ResolveDisabledTip's rawTooltip): while locked the chevron
--   hides, clicks do nothing and hover explains the lock, re-checked with the
--   page's widgets. Never touches region._lastInline or region._control.
-- Returns the button; nil during the search prebuild.
local function BuildRowLabelMenu(rgn, opts)
    if EllesmereUI._prebuilding then return end
    local label = rgn._label
    if not label then return end
    local locked = opts.locked
    local lockCfg = locked and { disabledTooltip = opts.lockTip, rawTooltip = opts.rawLockTip }
    local btn = CreateFrame("Button", nil, rgn)
    btn:SetFrameLevel(rgn:GetFrameLevel() + 12)
    local arrow = btn:CreateTexture(nil, "ARTWORK")
    arrow:SetTexture(ROW_MENU_ARROW)
    arrow:SetSize(17, 17)
    arrow:SetPoint("LEFT", label, "LEFT", math.ceil(label:GetStringWidth()) + 6, -1)
    -- The label clamp (QueueLabelClamp) keeps room for it and moves it with a cut label.
    rgn._labelArrow = arrow
    btn:SetPoint("TOPLEFT", label, "TOPLEFT", -4, 5)
    btn:SetPoint("BOTTOMRIGHT", arrow, "BOTTOMRIGHT", 2, -2)
    local menu
    local function Lit(on)
        if on then
            local r, g, b = RowMenuLitColor()
            arrow:SetVertexColor(r, g, b)
            label:SetTextColor(r, g, b)
        else
            arrow:SetVertexColor(1, 1, 1)
            label:SetTextColor(EllesmereUI.TEXT_WHITE_R, EllesmereUI.TEXT_WHITE_G, EllesmereUI.TEXT_WHITE_B)
        end
    end
    local function OnEnter()
        if locked and locked() then
            local tip = ResolveDisabledTip(lockCfg)
            if tip then ShowWidgetTooltip(btn, tip) end
            return
        end
        Lit(true)
        if opts.tooltip and not (menu and menu:IsShown()) then ShowWidgetTooltip(btn, opts.tooltip) end
    end
    local function OnLeave()
        if not (menu and menu:IsShown()) then Lit(false) end
        HideWidgetTooltip()
    end
    btn:SetScript("OnEnter", OnEnter)
    btn:SetScript("OnLeave", OnLeave)
    local proxyLbl = EllesmereUI.MakeFont(btn, 12, nil, 1, 1, 1)
    proxyLbl:Hide()
    local function EnsureMenu()
        if menu then return menu end
        local m, _, refresh = BuildDropdownMenu(btn, opts.menuWidth or 170, opts.order, opts.values,
            opts.getValue or NoSelection, opts.setValue, proxyLbl, "regular", opts.itemDisabled)
        menu = m
        -- The wiring takes the button's hover scripts: its own run again after.
        WireDropdownScripts(btn, proxyLbl, NO_PAINT, NO_PAINT, menu, refresh, EllesmereUI.RD_DD_COLOURS, true)
        btn:HookScript("OnEnter", OnEnter)
        btn:HookScript("OnLeave", OnLeave)
        menu:HookScript("OnShow", function() Lit(true) end)
        menu:HookScript("OnHide", function() Lit(btn:IsMouseOver()) end)
        return menu
    end
    btn:SetScript("OnClick", function()
        if locked and locked() then return end
        HideWidgetTooltip()
        local m = EnsureMenu()
        if m:IsShown() then m:Hide() else m:Show() end
    end)
    btn:HookScript("OnHide", function() if menu then menu:Hide() end end)
    Lit(false)
    if locked then
        -- Disabled while locked, still hovered to explain the lock.
        btn:SetMotionScriptsWhileDisabled(true)
        local function SyncLock()
            local off = locked() and true or false
            arrow:SetShown(not off)
            btn:SetEnabled(not off)
        end
        SyncLock()
        RegisterWidgetRefresh(SyncLock)
    end
    return btn
end

-- The list hangs off the button, as wide as the button unless opts.width says
-- otherwise; the button keeps its own hover look, held while the list shows.
-- opts: width, order, values, getValue() (default: nothing selected),
--   setValue(v), itemDisabled(v) (as BuildRowLabelMenu). Returns the toggle the
--   button's click calls; nil during the search prebuild.
local function AttachButtonMenu(btn, opts)
    if EllesmereUI._prebuilding then return end
    local enter, leave = btn:GetScript("OnEnter"), btn:GetScript("OnLeave")
    local proxyLbl = EllesmereUI.MakeFont(btn, 12, nil, 1, 1, 1)
    proxyLbl:Hide()
    local menu
    local function EnsureMenu()
        if menu then return menu end
        local m, _, refresh = BuildDropdownMenu(btn, opts.width or btn:GetWidth(), opts.order, opts.values,
            opts.getValue or NoSelection, opts.setValue, proxyLbl, "regular", opts.itemDisabled)
        menu = m
        WireDropdownScripts(btn, proxyLbl, NO_PAINT, NO_PAINT, menu, refresh, EllesmereUI.RD_DD_COLOURS, true)
        if enter then btn:HookScript("OnEnter", enter) end
        if leave then
            btn:HookScript("OnLeave", function(self) if not menu:IsShown() then leave(self) end end)
            menu:HookScript("OnHide", function() if not btn:IsMouseOver() then leave(btn) end end)
        end
        return menu
    end
    btn:HookScript("OnHide", function() if menu then menu:Hide() end end)
    return function()
        local m = EnsureMenu()
        if m:IsShown() then m:Hide() else m:Show() end
    end
end

-------------------------------------------------------------------------------
--  Less-Common Settings Expander
--  Centralized collapse link for rarely-customized option rows. Page builders wrap those rows in:
--      local expanded
--      expanded, y = EllesmereUI.BuildLessCommonExpander(parent, y,
--          "rfIndicators", "Show Less Common Indicator Options")
--      if expanded then
--          ... build the less-common rows ...
--      end
--      y = EllesmereUI.FinishLessCommonExpander(parent, y,
--          "rfIndicators", "Show Less Common Indicator Options")
--  Sections start collapsed; expansion is session-only per sectionKey (never saved). Clicking the link forces
--  RefreshPage(true) to re-run the page builder -- the no-arg fast path only re-reads values and would never
--  reveal the collapsed rows.
-------------------------------------------------------------------------------
local LESS_COMMON_ARROW_DOWN = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-arrow-down3.png"
local LESS_COMMON_ARROW_UP   = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-arrow-up3.png"

-- Shared link renderer for both expander states. The link always sits at the BOTTOM of its section: collapsed it
-- renders where the hidden rows would start (via BuildLessCommonExpander), expanded it renders below the
-- revealed rows (via FinishLessCommonExpander). Expanded state flips it into the collapse form: up arrows and a
-- "Hide ..." label -- the Hide key is derived from the ENGLISH label before localization so both variants are proper L() lookup keys.
local function BuildLessCommonLink(parent, y, sectionKey, label, expanded)
    local ARROW_SZ, ARROW_GAP = 12, 6
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(22)
    btn:SetPoint("TOP", parent, "TOP", 0, y - 12)
    btn:SetFrameLevel(parent:GetFrameLevel() + 5)

    local arrowTex = expanded and LESS_COMMON_ARROW_UP or LESS_COMMON_ARROW_DOWN
    local text = expanded and (label:gsub("^Show", "Hide", 1)) or label

    local fs = EllesmereUI.MakeFont(btn, 13, nil, 1, 1, 1)
    fs:SetPoint("LEFT", btn, "LEFT", ARROW_SZ + ARROW_GAP, 0)
    fs:SetText(EllesmereUI.L(text))
    fs:SetAlpha(0.7)

    local leftArrow = btn:CreateTexture(nil, "OVERLAY")
    leftArrow:SetSize(ARROW_SZ, ARROW_SZ)
    leftArrow:SetTexture(arrowTex)
    leftArrow:SetPoint("RIGHT", fs, "LEFT", -ARROW_GAP, 0)
    leftArrow:SetAlpha(0.7)

    local rightArrow = btn:CreateTexture(nil, "OVERLAY")
    rightArrow:SetSize(ARROW_SZ, ARROW_SZ)
    rightArrow:SetTexture(arrowTex)
    rightArrow:SetPoint("LEFT", fs, "RIGHT", ARROW_GAP, 0)
    rightArrow:SetAlpha(0.7)

    btn:SetWidth(math.max((fs:GetStringWidth() or 0) + 2 * (ARROW_SZ + ARROW_GAP) + 8, 120))

    local EG = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }
    btn:SetScript("OnEnter", function()
        fs:SetTextColor(EG.r, EG.g, EG.b); fs:SetAlpha(1)
        leftArrow:SetVertexColor(EG.r, EG.g, EG.b); leftArrow:SetAlpha(1)
        rightArrow:SetVertexColor(EG.r, EG.g, EG.b); rightArrow:SetAlpha(1)
    end)
    btn:SetScript("OnLeave", function()
        fs:SetTextColor(1, 1, 1); fs:SetAlpha(0.7)
        leftArrow:SetVertexColor(1, 1, 1); leftArrow:SetAlpha(0.7)
        rightArrow:SetVertexColor(1, 1, 1); rightArrow:SetAlpha(0.7)
    end)
    btn:SetScript("OnClick", function()
        local sess = EllesmereUI._lessCommonExpanded
        if not sess then sess = {}; EllesmereUI._lessCommonExpanded = sess end
        sess[sectionKey] = (not expanded) and true or nil
        EllesmereUI:RefreshPage(true)
    end)

    return y - 40
end

local function BuildLessCommonExpander(parent, y, sectionKey, label)
    -- Hidden search pre-build: always build the wrapped rows so they register in the global search index; no link (the page is never shown).
    if EllesmereUI._prebuilding then return true, y end
    -- This page reads the search flag: a search transition rebuilds it (SetLessCommonSearchActive).
    EllesmereUI._passReadSearchFlag = true
    -- Active search (either box): sections render force-expanded with NO link line at all; clearing the search collapses them back. Transient flag -- the session Show/Hide state below is untouched and restores afterwards (see SetLessCommonSearchActive).
    if EllesmereUI._lessCommonSearchActive then return true, y end
    local sess = EllesmereUI._lessCommonExpanded
    if not sess then sess = {}; EllesmereUI._lessCommonExpanded = sess end
    -- Expanded: render nothing here -- the caller builds the rows, then FinishLessCommonExpander places the "Hide ..." link below them.
    if sess[sectionKey] then return true, y end
    return false, BuildLessCommonLink(parent, y, sectionKey, label, false)
end

-- Call after the wrapped rows (safe to call unconditionally: no-ops while the section is collapsed, during the search pre-build or during an active search).
local function FinishLessCommonExpander(parent, y, sectionKey, label)
    if EllesmereUI._prebuilding then return y end
    EllesmereUI._passReadSearchFlag = true
    if EllesmereUI._lessCommonSearchActive then return y end
    local sess = EllesmereUI._lessCommonExpanded
    if not (sess and sess[sectionKey]) then return y end
    return BuildLessCommonLink(parent, y, sectionKey, label, true)
end

-- Search-driven expansion (both the sidebar global box and the top-bar module box call this with query ~= ""). While active, every less-common section renders expanded with no link; on clear, sections fall back to their session Show/Hide state. Idempotent -- only transitions act, and only on the pages whose last build read the flag (the expanders above, Bar Glows): those go (or are marked for a rebuild), and the active one is rebuilt in place, unless a page switch is clearing the box (the page being left is rebuilt on its next visit).
local function SetLessCommonSearchActive(active)
    active = active and true or false
    if (EllesmereUI._lessCommonSearchActive or false) == active then return end
    EllesmereUI._lessCommonSearchActive = active
    if EllesmereUI._InvalidateSearchSensitive() and not EllesmereUI._selectingPage then
        EllesmereUI:RefreshPage(true)
    end
end

-- A colour scale across a swatch: stops = { { r, g, b }, ... }, drawn left to
-- right in equal steps over its fill (for a swatch that picks a scale, such as
-- the meters' value gradient).
local function PaintSwatchGradient(swatch, stops)
    local steps = #stops - 1
    local w = swatch:GetWidth()
    for i = 1, steps do
        local from, to = stops[i], stops[i + 1]
        local seg = swatch:CreateTexture(nil, "ARTWORK", nil, 1)
        seg:SetPoint("TOPLEFT", swatch, "TOPLEFT", w * (i - 1) / steps, 0)
        seg:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMLEFT", w * i / steps, 0)
        seg:SetColorTexture(1, 1, 1, 1)
        seg:SetGradient("HORIZONTAL", CreateColor(from[1], from[2], from[3], 1), CreateColor(to[1], to[2], to[3], 1))
    end
end

-------------------------------------------------------------------------------
--  BuildInlineSwatches(region, swatches, opts)
--  Inline form of the multiSwatch half: builds the same swatch list (tooltip, hasAlpha, getValue/setValue,
--  onClick override, per-swatch disabled+disabledTooltip, refreshAlpha, gradient) to the LEFT of the region's
--  control, so a slider (or any control half) can host its color swatches on the same row. Chains from
--  region._lastInline: a slot's cog is built first and the swatches land left of it. opts.disabled/opts.disabledTooltip
--  mirror the row-level disabled state of the multiSwatch form.
--  opts.size: the swatch size (nil = 20, the inline swatch size; BuildColorSwatch's own 24 is a swatch half's).
--  sc.gradient: colour stops shown across the swatch in place of its colour (PaintSwatchGradient).
-------------------------------------------------------------------------------
local function BuildInlineSwatches(region, swatches, opts)
    -- Hidden search pre-build: swatches index nothing and the pre-built page is never shown, so none are built (its regions are stand-ins with no frame to build on).
    if EllesmereUI._prebuilding then return end
    opts = opts or {}
    local level = region:GetFrameLevel() + 3
    local anchorTo = region._lastInline or region._control
    for i = #swatches, 1, -1 do
        local sc = swatches[i]
        local swatch, updateSwatch = BuildColorSwatch(region, level, sc.getValue, sc.setValue, sc.hasAlpha, opts.size or 20)
        PP.Point(swatch, "RIGHT", anchorTo, "LEFT", -8, 0)
        anchorTo = swatch
        region._lastInline = swatch
        if sc.gradient then PaintSwatchGradient(swatch, sc.gradient) end
        if sc.onClick then
            swatch._eabOrigClick = swatch:GetScript("OnClick")
            swatch:SetScript("OnClick", sc.onClick)
        end
        local function SwatchEffectiveDisabled()
            if opts.disabled and opts.disabled() then return true end
            if sc.disabled ~= nil then
                if type(sc.disabled) == "function" then return sc.disabled() end
                return sc.disabled
            end
            return false
        end
        if opts.disabled or sc.disabled then
            local swatchBlock = CreateFrame("Frame", nil, swatch)
            swatchBlock:SetAllPoints()
            swatchBlock:SetFrameLevel(swatch:GetFrameLevel() + 10)
            swatchBlock:EnableMouse(true)
            swatchBlock:SetScript("OnEnter", function()
                local src = (sc.disabledTooltip ~= nil) and sc or opts
                local tip = ResolveDisabledTip(src)
                if tip then ShowWidgetTooltip(swatch, tip) end
            end)
            swatchBlock:SetScript("OnLeave", function() HideWidgetTooltip() end)
            local function UpdateSwatchDisabled()
                if SwatchEffectiveDisabled() then
                    swatch:SetAlpha(0.3)
                    swatchBlock:Show()
                else
                    swatch:SetAlpha(1)
                    swatchBlock:Hide()
                end
            end
            UpdateSwatchDisabled()
            RegisterWidgetRefresh(UpdateSwatchDisabled)
        end
        if sc.tooltip then
            swatch:HookScript("OnEnter", function() ShowWidgetTooltip(swatch, sc.tooltip) end)
            swatch:HookScript("OnLeave", function() HideWidgetTooltip() end)
        end
        if sc.refreshAlpha then
            local _sw, _ra = swatch, sc.refreshAlpha
            local function UpdateAlpha()
                if SwatchEffectiveDisabled() then return end
                _sw:SetAlpha(_ra())
            end
            UpdateAlpha()
            RegisterWidgetRefresh(UpdateAlpha)
        end
        RegisterWidgetRefresh(function() updateSwatch() end)
    end
end
EllesmereUI.BuildInlineSwatches = BuildInlineSwatches

-------------------------------------------------------------------------------
--  BuildFillColorSwatches(region, opts)
--  The inline swatches of a Fill Color dropdown half that offers Custom Color and Custom Dynamic
--  Colors: one Custom Color swatch (live in "custom", dimmed and blocked with a tooltip in the
--  other flat modes) and the three gradient-stop swatches (100% | 50% | 0%, left to right), which
--  take its place in "customDynamic". Chains from region._lastInline like the other inline items.
--  opts.mode() -> the dropdown's value; opts.getCustom() -> r, g, b; opts.setCustom(r, g, b);
--  opts.keys = { key100, key50, key0 }; opts.getStop(key) -> the saved colour table or nil (a
--  missing stop shows its default); opts.setStop(key, r, g, b). Nothing in the search pre-build.
-------------------------------------------------------------------------------
local FILL_STOPS = {
    { def = { r = 0, g = 1, b = 0 }, tip = "Health bar color at full (100%) health" },
    { def = { r = 0xEC/255, g = 0xEC/255, b = 0x32/255 }, tip = "Health bar color at half (50%) health" },
    { def = { r = 0xE3/255, g = 0x30/255, b = 0x30/255 }, tip = "Health bar color at empty (0%) health" },
}
local function BuildFillColorSwatches(region, opts)
    if EllesmereUI._prebuilding then return end
    local level = region:GetFrameLevel() + 3
    local anchor = region._lastInline or region._control
    local custom, updateCustom = BuildColorSwatch(region, level, function()
        local r, g, b = opts.getCustom()
        return r, g, b, 1
    end, opts.setCustom, false, 20)
    PP.Point(custom, "RIGHT", anchor, "LEFT", -8, 0)
    region._lastInline = custom
    local block = CreateFrame("Frame", nil, custom)
    block:SetAllPoints()
    block:SetFrameLevel(custom:GetFrameLevel() + 10)
    block:EnableMouse(true)
    block:SetScript("OnEnter", function() ShowWidgetTooltip(custom, "Only available with Custom fill color") end)
    block:SetScript("OnLeave", function() HideWidgetTooltip() end)

    -- Built right to left, so they read 100% | 50% | 0%.
    local stops, updaters = {}, {}
    local prev = anchor
    for i = 3, 1, -1 do
        local stop, key = FILL_STOPS[i], opts.keys[i]
        local sw, update = BuildColorSwatch(region, level, function()
            local c = opts.getStop(key) or stop.def
            return c.r, c.g, c.b, 1
        end, function(r, g, b) opts.setStop(key, r, g, b) end, false, 18)
        PP.Point(sw, "RIGHT", prev, "LEFT", (prev == anchor) and -8 or -6, 0)
        sw:HookScript("OnEnter", function() ShowWidgetTooltip(sw, stop.tip) end)
        sw:HookScript("OnLeave", function() HideWidgetTooltip() end)
        stops[i], updaters[i], prev = sw, update, sw
    end

    local function Update()
        local mode = opts.mode()
        local dynamic = mode == "customDynamic"
        custom:SetShown(not dynamic)
        if not dynamic then
            local live = mode == "custom"
            custom:SetAlpha(live and 1 or 0.3)
            block:SetShown(not live)
            updateCustom()
        end
        for i = 1, 3 do
            stops[i]:SetShown(dynamic)
            if dynamic then updaters[i]() end
        end
    end
    RegisterWidgetRefresh(Update)
    Update()
end
EllesmereUI.BuildFillColorSwatches = BuildFillColorSwatches

-------------------------------------------------------------------------------
--  Hidden-While-Disabled Section Gate
--  For sections whose master toggle HIDES the dependent rows instead of graying them: the page builder simply
--  skips building those rows while the toggle is off, and the toggle's setValue is wrapped with this so flipping it re-runs the page builder to reveal/hide them:
--      { type="toggle", text="Enable Top Name Bar",
--        getValue=...,
--        setValue=EllesmereUI.SectionToggleSetValue(function(v)
--            SSet("tnbEnabled", v); ApplyAll()
--        end) }
-------------------------------------------------------------------------------
local function SectionToggleSetValue(fn)
    return function(v)
        fn(v)
        EllesmereUI:RefreshPage(true)
    end
end

-------------------------------------------------------------------------------
--  Dependent-Row Visibility
--  Row-level version of the section gate: one setting's value hides entire dependent rows instead of graying
--  them. The builder skips the dependent rows behind a plain predicate check, and the TRIGGER setting's setValue
--  is wrapped with this so the page rebuilds only when the predicate actually flips -- ordinary value changes keep whatever refresh the inner setValue already does, with no rebuild flash:
--      -- trigger dropdown:
--      setValue = EllesmereUI.DependentSetValue(
--          function() return SVal("healAbsorbTextMode", "none") ~= "none" end,
--          function(v) SSet("healAbsorbTextMode", v); EllesmereUI:RefreshPage() end),
--
--      -- dependent row below (skip building while hidden):
--      if SVal("healAbsorbTextMode", "none") ~= "none" then
--          ... build the dependent row(s) ...
--      end
-------------------------------------------------------------------------------
local function DependentSetValue(pred, fn)
    return function(v)
        local before = pred() and true or false
        fn(v)
        if (pred() and true or false) ~= before then
            EllesmereUI:RefreshPage(true)
        end
    end
end

EllesmereUI.BuildInlineToggle    = BuildInlineToggle
EllesmereUI.BuildInlineCog       = BuildInlineCog
EllesmereUI.BuildRowLabelMenu    = BuildRowLabelMenu
EllesmereUI.AttachButtonMenu     = AttachButtonMenu
EllesmereUI.BuildLessCommonExpander   = BuildLessCommonExpander
EllesmereUI.FinishLessCommonExpander  = FinishLessCommonExpander
EllesmereUI.SetLessCommonSearchActive = SetLessCommonSearchActive
EllesmereUI.SectionToggleSetValue     = SectionToggleSetValue
EllesmereUI.DependentSetValue         = DependentSetValue

-------------------------------------------------------------------------------
--  BuildCursorAnchorRow
--  Shared "Anchor to Cursor" row used by CDM, Resource Bars, and any future section that supports cursor anchoring.
--  opts:
--    W           = widget factory (the W: table from options page)
--    parent      = parent frame
--    getData     = function() -> settings table with anchorTo, anchorPosition, anchorOffsetX, anchorOffsetY
--    onApply     = function() -> rebuild/refresh after value change
--    disabledFn  = (optional) function() -> true when the whole row is disabled
--    disabledTip = (optional) tooltip string for disabled state
--  Returns: row, height (same as W:DualRow)
-------------------------------------------------------------------------------
local function BuildCursorAnchorRow(opts)
    local W          = opts.W
    local parent     = opts.parent
    local getData    = opts.getData
    local onApply    = opts.onApply

    local row, h = W:DualRow(parent, opts.y,
        { type = "toggle", text = "Anchor to Cursor",
          disabled = opts.disabledFn,
          disabledTooltip = opts.disabledTip,
          getValue = function() return getData().anchorTo == "mouse" end,
          setValue = function(v)
              local old = getData().anchorTo
              local new = v and "mouse" or "none"
              getData().anchorTo = new
              -- Cursor anchor requires a reload to take effect cleanly (Blizzard viewer Layout fights icon positions on live switch).
              local changed = (old == "mouse") ~= (new == "mouse")
              if changed then
                  EllesmereUI:ShowConfirmPopup({
                      title = "Reload Required",
                      message = "Changing cursor anchor requires a UI reload to take effect.",
                      confirmText = "Reload Now",
                      cancelText = "Later",
                      reload    = true,
                  })
              else
                  onApply()
              end
              EllesmereUI:RefreshPage(true)
          end },
        { type = "dropdown", text = "Cursor Position",
          values = { left = "Left", right = "Right", top = "Top", bottom = "Bottom" },
          order = { "left", "right", "top", "bottom" },
          disabled = function()
              if opts.disabledFn and opts.disabledFn() then return true end
              return getData().anchorTo ~= "mouse"
          end,
          disabledTooltip = "Anchor to Cursor",
          getValue = function() return getData().anchorPosition or "right" end,
          setValue = function(v)
              getData().anchorPosition = v
              onApply()
          end })

    -- "(Applies on Window Close)" subtitle
    do
        local suffix = row._leftRegion:CreateFontString(nil, "OVERLAY")
        suffix:SetFont(EllesmereUI.EXPRESSWAY, 11, "")
        suffix:SetTextColor(1, 1, 1, 0.35)
        suffix:SetText(EllesmereUI.L("(Applies on Window Close)"))
        local anchorLabel
        local regions = { row._leftRegion:GetRegions() }
        for i = 1, #regions do
            local reg = regions[i]
            if reg and reg.GetText and EllesmereUI.EnKey(reg:GetText()) == "Anchor to Cursor" then
                anchorLabel = reg; break
            end
        end
        if anchorLabel then
            suffix:SetPoint("LEFT", anchorLabel, "RIGHT", 5, 0)
        else
            suffix:SetPoint("LEFT", row._leftRegion, "LEFT", 120, 0)
        end
    end

    -- Inline cog: X + Y offsets
    BuildInlineCog(row._rightRegion, {
        title = "Cursor Offset",
        rows = {
            { type = "slider", label = "X Offset", min = -125, max = 125, step = 1,
              get = function() return getData().anchorOffsetX or 0 end,
              set = function(v) getData().anchorOffsetX = v; onApply() end },
            { type = "slider", label = "Y Offset", min = -125, max = 125, step = 1,
              get = function() return getData().anchorOffsetY or 0 end,
              set = function(v) getData().anchorOffsetY = v; onApply() end },
        },
    })

    return row, h
end
EllesmereUI.BuildCursorAnchorRow = BuildCursorAnchorRow

end  -- end deferred init
