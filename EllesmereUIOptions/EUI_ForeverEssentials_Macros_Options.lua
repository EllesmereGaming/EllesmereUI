if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end -- Forever Essentials loads on WoW Forever only
-------------------------------------------------------------------------------
--  EUI_ForeverEssentials_Macros_Options.lua
--  Builds the "Macros" page inside the Forever Essentials module: the Macro
--  Manager. Its Enable Macro Manager row heads the page; while it is on, the
--  content header holds a centered dropdown (Account Macros / Character
--  Macros) over that list's macros as centered icons, and the page below
--  holds the selected macro's settings, its lines and the macro text. The
--  model (builder, parser, spellbook, macro access) is
--  EUI_ForeverEssentials_MacroModel_Options.lua.
--
--  Structural edits rebuild the page (RefreshPage(true)); value edits refresh
--  widgets in place; a macro change repaints the header alone unless the
--  macro being edited changed. The icon grid is built once and re-parented
--  into each header: a list holds up to 120 macros.
-------------------------------------------------------------------------------
if not EllesmereUI._ModuleNS["EllesmereUIForeverEssentials"] then return end  -- module disabled: no options page

local floor, max, min = math.floor, math.max, math.min
local PP         = EllesmereUI.PanelPP
local SolidTex   = EllesmereUI.SolidTex
local MakeFont   = EllesmereUI.MakeFont
local MakeBorder = EllesmereUI.MakeBorder
local MODEL      = EllesmereUI._ModuleNS["EllesmereUIForeverEssentials"]._MacroModel
local B, S, MM   = MODEL.B, MODEL.S, MODEL.MM

local function L(s) return EllesmereUI.L(s) end

local ICONS = "Interface\\AddOns\\EllesmereUI\\media\\icons\\"
local CELL = 46          -- icon grid step (42 icon + 4 gap)
local GRID_ROWS = 3      -- grid rows shown before it scrolls
local TEXT_H = 130       -- macro text block
local LIST_ORDER = { "account", "char" }
local TIP_LEFT = { justify = "LEFT" }   -- tooltips that show macro text

local cur                -- the macro being edited (survives rebuilds)
local mode = "account"   -- the list in the header: account | char
local edCtx = { headers = {} }
local macroGrid, gridList = {}, {}   -- the pooled icon grid and the list it shows
local D = {}             -- widgets of the page on screen
local boxes = {}         -- the text fields of the page on screen (set)
local statusText, statusBad          -- the status line, kept across rebuilds
local builtFor, builtHadRef          -- the editor state the page body was built for
local hdrFrame, hdrDD, hdrValues, hdrY, hdrW   -- the header on screen, painted in place
local snap = { n = {}, i = {}, b = {} }        -- both macro lists as the page last showed them
local evf, pendingEvent, pendingRebuild, textDirty, shown, hiddenAt
local HeaderBuilder, CellClick, CellDrag

local function Rebuild() EllesmereUI:RefreshPage(true) end
local function Refresh() EllesmereUI:RefreshPage() end

local function Accent() return EllesmereUI.ELLESMERE_GREEN end

local function IconPath(icon)
    if type(icon) == "string" and not icon:find("\\", 1, true) then return "Interface\\Icons\\" .. icon end
    return icon or MM.QUESTION
end

-------------------------------------------------------------------------------
--  Shared parts
-------------------------------------------------------------------------------
-- Small icon button (row move / remove glyphs).
local function Glyph(parent, size, file, onClick, tip)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b:SetFrameLevel(parent:GetFrameLevel() + 6)
    local t = b:CreateTexture(nil, "OVERLAY")
    t:SetAllPoints()
    if file then t:SetTexture(ICONS .. file) end
    b.tex = t
    b:SetAlpha(0.5)
    b:SetScript("OnEnter", function(self)
        if self:IsEnabled() then self:SetAlpha(0.9) end
        if tip then EllesmereUI.ShowWidgetTooltip(self, tip) end
    end)
    b:SetScript("OnLeave", function(self)
        self:SetAlpha(self:IsEnabled() and 0.5 or 0.15)
        if tip then EllesmereUI.HideWidgetTooltip() end
    end)
    b:SetScript("OnEnable", function(self) self:SetAlpha(0.5) end)
    b:SetScript("OnDisable", function(self) self:SetAlpha(0.15) end)
    b:SetScript("OnClick", onClick)
    return b
end

-- A scroll inside the page: Shift + wheel scales the panel, and the wheel goes
-- on to the page while there is nothing to scroll.
local function AttachScroll(scroll, child)
    return EllesmereUI.AttachSmoothScrollbar(scroll, {
        step = 60, thumbMin = 20, rightInset = 0, topInset = 2, level = 5,
        trackAlpha = 0.05, thumbAlpha = 0.22, child = child, panelWheel = true, passWheel = true })
end

local function PaintCounter(fs, n)
    fs:SetText(n .. " / " .. MM.MAX_LETTERS)
    if n > MM.MAX_LETTERS then
        fs:SetTextColor(1, 0.35, 0.35, 1)
    elseif n > MM.MAX_LETTERS - 25 then
        local ac = Accent()
        fs:SetTextColor(ac.r, ac.g, ac.b, 1)
    else
        fs:SetTextColor(1, 1, 1, EllesmereUI.TEXT_DIM_A)
    end
end

-- Multi-line macro text box (input popup look). box.onChange(text, user),
-- box.onBlur().
local function TextBox(parent, w, h)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(w, h)
    SolidTex(box, "BACKGROUND", 0, 0, 0, 0.5):SetAllPoints()
    local brd = MakeBorder(box, 1, 1, 1, 0.2, PP)
    local sf = CreateFrame("ScrollFrame", nil, box)
    sf:SetPoint("TOPLEFT", 10, -8)
    sf:SetSize(w - 22, h - 16)
    sf:SetClipsChildren(true)
    local e = CreateFrame("EditBox", nil, sf)
    boxes[e] = true
    e:SetMultiLine(true)
    e:SetAutoFocus(false)
    e:SetFont(EllesmereUI.EXPRESSWAY, 12, "")
    e:SetTextColor(1, 1, 1, 0.9)
    e:SetSpacing(3)
    e:SetSize(w - 26, 20)
    sf:SetScrollChild(e)
    local update = AttachScroll(sf, e)
    e:SetScript("OnSizeChanged", function() update() end)
    e:SetScript("OnEscapePressed", e.ClearFocus)
    e:SetScript("OnCursorChanged", function(_, _, y, _, ch)
        y = -y
        local top, vh = sf:GetVerticalScroll(), sf:GetHeight()
        if y < top then sf:SetVerticalScroll(y) elseif y + ch > top + vh then sf:SetVerticalScroll(y + ch - vh) end
        update()
    end)
    e:SetScript("OnTextChanged", function(self, user)
        if box.onChange then box.onChange(self:GetText(), user) end
    end)
    e:SetScript("OnEditFocusGained", function()
        local ac = Accent()
        brd:SetColor(ac.r, ac.g, ac.b, 0.8)
    end)
    e:SetScript("OnEditFocusLost", function()
        brd:SetColor(1, 1, 1, 0.2)
        if box.onBlur then box.onBlur() end
    end)
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function()
        e:SetFocus()
        e:SetCursorPosition(#(e:GetText() or ""))
    end)
    function box.SetText(_, t) e:SetText(t or "") end
    return box
end

-- Info line, counter and text box as one block of the page.
local function TextBlock(parent, y)
    local pad = EllesmereUI.CONTENT_PAD
    local w = parent:GetWidth() - pad * 2
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w, TEXT_H)
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", pad, y)
    local info = MakeFont(f, 11, nil, 1, 1, 1, EllesmereUI.TEXT_DIM_A)
    info:SetPoint("TOPLEFT", 0, -8)
    local count = MakeFont(f, 11, nil, 1, 1, 1, EllesmereUI.TEXT_DIM_A)
    count:SetPoint("TOPRIGHT", 0, -8)
    info:SetPoint("RIGHT", count, "LEFT", -12, 0)
    info:SetJustifyH("LEFT")
    info:SetWordWrap(false)
    local box = TextBox(f, w, TEXT_H - 30)
    box:SetPoint("TOPLEFT", 0, -26)
    return box, count, info
end

-- Icon cell of the macro grid. Its scripts read the cell when they run: c.m
-- (the macro it shows) or c.newCell (the "+" cell).
local function NewCell(parent)
    local c = CreateFrame("Button", nil, parent)
    c:SetSize(CELL - 4, CELL - 4)
    c:SetFrameLevel(parent:GetFrameLevel() + 1)
    c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    c:RegisterForDrag("LeftButton")
    SolidTex(c, "BACKGROUND", 0, 0, 0, 0.5):SetAllPoints()
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetPoint("TOPLEFT", 1, -1)
    c.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    c.plus = MakeFont(c, 22, nil, 1, 1, 1, 0.45)
    c.plus:SetPoint("CENTER", 0, 1)
    c.plus:SetText("+")
    c.name = c:CreateFontString(nil, "OVERLAY")
    c.name:SetFont(EllesmereUI.EXPRESSWAY, 9, "OUTLINE")
    c.name:SetPoint("BOTTOMLEFT", 2, 3)
    c.name:SetPoint("BOTTOMRIGHT", -2, 3)
    c.name:SetJustifyH("CENTER")
    c.name:SetWordWrap(false)
    c.brd = MakeBorder(c, 0, 0, 0, 1, PP)
    function c.Paint(hover)
        if c.selected then
            local ac = Accent()
            c.brd:SetColor(ac.r, ac.g, ac.b, 1)
        elseif hover then
            c.brd:SetColor(1, 1, 1, 0.5)
        else
            c.brd:SetColor(0, 0, 0, 1)
        end
    end
    c:SetScript("OnEnter", function(self)
        self.Paint(true)
        local m = self.m
        local tip = m and (m.name .. "\n\n" .. m.body) or (self.newCell and EllesmereUI.L("New Macro"))
        if tip then EllesmereUI.ShowWidgetTooltip(self, tip, TIP_LEFT) end
    end)
    c:SetScript("OnLeave", function(self)
        self.Paint(false)
        EllesmereUI.HideWidgetTooltip()
    end)
    c:SetScript("OnClick", CellClick)
    c:SetScript("OnDragStart", CellDrag)
    return c
end

-------------------------------------------------------------------------------
--  Spell suggestions under a text field: the spellbook through the shared
--  context menu, picked on the press (the field loses its focus on a mouse
--  down outside it). The list closes with the field's focus, so the menu runs
--  no click-outside poll. list = true completes the last entry of a comma list.
-------------------------------------------------------------------------------
local SUGGEST_OPTS = { below = true, scaleToAnchor = true, pickOnDown = true, noPoll = true }
local suggestPool, suggestShown = {}, {}   -- pooled items; the ones on screen
local suggestPick, suggestOwner

local function SuggestItem(i)
    local it = suggestPool[i]
    if not it then
        it = { noLoc = true }
        it.onClick = function() if suggestPick then suggestPick(it.text) end end
        suggestPool[i] = it
    end
    return it
end

local function HideSuggest()
    if suggestOwner and EllesmereUI.ContextMenuOwner() == suggestOwner then EllesmereUI.CloseContextMenu() end
    suggestOwner = nil
end

local function AttachSuggest(box, onPick, list)
    local function Pick(name)
        HideSuggest()
        local t = name
        if list then
            local head = (box:GetText() or ""):match("^(.*,)") or ""
            t = (head ~= "" and (head .. " ") or "") .. name
        end
        box:SetText(t)
        onPick(t)
        box:ClearFocus()
    end
    local function Show()
        local q = box:GetText() or ""
        if list then q = q:match("([^,]*)$") or "" end
        q = strtrim(q):lower()
        wipe(suggestShown)
        for _, s in ipairs(S.Sorted()) do
            if q == "" or s.lname:find(q, 1, true) then
                local it = SuggestItem(#suggestShown + 1)
                it.text, it.icon = s.name, s.icon or MM.QUESTION
                suggestShown[#suggestShown + 1] = it
                if #suggestShown >= 10 then break end
            end
        end
        if #suggestShown == 0 or (#suggestShown == 1 and suggestShown[1].text:lower() == q) then
            HideSuggest()
            return
        end
        suggestPick, suggestOwner = Pick, box
        SUGGEST_OPTS.minWidth = max(box:GetWidth(), 220)
        EllesmereUI.CloseContextMenu()   -- a second call from the same anchor would close it
        EllesmereUI.ShowContextMenu(box, suggestShown, SUGGEST_OPTS)
    end
    box:HookScript("OnTextChanged", function(_, user) if user then Show() end end)
    box:HookScript("OnEditFocusGained", Show)
    -- A plain mouse down drops the box's focus before a row of the list gets
    -- that press (a modified click keeps the focus), so the list closes a frame
    -- later: a pick on it still lands, a press anywhere else still closes it.
    local function CloseIfUnfocused()
        if suggestOwner == box and not box:HasFocus() then HideSuggest() end
    end
    box:HookScript("OnEditFocusLost", function()
        if EllesmereUI.ContextMenuOwner() == box then C_Timer.After(0, CloseIfUnfocused) end
    end)
    box:HookScript("OnTabPressed", function()
        if EllesmereUI.ContextMenuOwner() == box and suggestShown[1] then Pick(suggestShown[1].text) end
    end)
end

-------------------------------------------------------------------------------
--  Icon picker (popup shell): "?" first, then this open's spellbook icons,
--  then every macro icon the game offers, read once per session (repeats
--  allowed, as in Blizzard's own list). Never Blizzard's
--  IconDataProviderMixin: driven from here it would write the file state
--  Blizzard's macro window shares and force a full collect.
-------------------------------------------------------------------------------
local picker, baseIcons

local function PickerIcon(i)
    if i == 1 then return MM.QUESTION end
    local spells = picker.spells
    if i - 1 <= #spells then return spells[i - 1] end
    return baseIcons[i - 1 - #spells]
end

local function PickerClick(self)
    local onPick = picker.onPick
    picker.Close()
    if onPick then onPick(self.value) end
end

local function OpenPicker(onPick)
    local COLS, ROWS, SIZE = 10, 6, 40
    if not picker then
        local p = {}
        function p.Close()
            p.dimmer:Hide()
            p.spells, p.onPick = nil, nil   -- the spell list lives only while it is open
        end
        p.dimmer, p.popup = EllesmereUI.BuildPopupShell("EUIMacroIconPicker", {
            w = COLS * SIZE + 40, h = ROWS * SIZE + 132, bump = 1, onEscape = p.Close, onDimmerDown = p.Close,
        })
        local popup = p.popup
        local title = MakeFont(popup, 16, "", 1, 1, 1)
        title:SetPoint("TOP", popup, "TOP", 0, -20)
        title:SetText(EllesmereUI.L("Choose Icon"))
        local sub = MakeFont(popup, 12, nil, 1, 1, 1, EllesmereUI.TEXT_DIM_A)
        sub:SetPoint("TOP", title, "BOTTOM", 0, -8)
        sub:SetText(EllesmereUI.L("The question mark shows the spell's icon (with #showtooltip)."))
        p.buttons = {}
        for i = 1, COLS * ROWS do
            local b = NewCell(popup)
            b:SetSize(SIZE - 4, SIZE - 4)
            b:SetFrameLevel(popup:GetFrameLevel() + 2)   -- above the scroll frame below
            b:SetPoint("TOPLEFT", 20 + ((i - 1) % COLS) * SIZE, -70 - floor((i - 1) / COLS) * SIZE)
            -- Left clicks only, and no drag: a drag would swallow the click.
            b:RegisterForClicks("LeftButtonUp")
            b:RegisterForDrag()
            b.plus:Hide()
            b:SetScript("OnClick", PickerClick)
            p.buttons[i] = b
        end
        -- The shared scroll bar on an empty scroll frame under the grid: its
        -- child is as tall as every icon row, and the scroll value picks the
        -- first row the grid shows (the grid itself stays put).
        local sf = CreateFrame("ScrollFrame", nil, popup)
        sf:SetFrameLevel(popup:GetFrameLevel() + 1)
        sf:SetPoint("TOPLEFT", popup, "TOPLEFT", 20, -70)
        sf:SetSize(COLS * SIZE + 12, ROWS * SIZE)
        p.child = CreateFrame("Frame", nil, sf)
        p.child:SetSize(COLS * SIZE, ROWS * SIZE)
        sf:SetScrollChild(p.child)
        p.updateThumb, p.scrollTo = EllesmereUI.AttachSmoothScrollbar(sf, {
            step = SIZE, child = p.child,
            onScroll = function(v)
                local off = floor(v / SIZE + 0.5) * COLS
                if off ~= p.offset then
                    p.offset = off
                    p.Update()
                end
            end,
        })
        function p.Update()
            for i, b in ipairs(p.buttons) do
                local icon = PickerIcon(p.offset + i)
                b.value = icon
                if icon then
                    b.icon:SetTexture(IconPath(icon))
                    b.selected = icon == p.current
                    b.Paint(false)
                    b:Show()
                else
                    b:Hide()
                end
            end
        end
        p.cancel = EllesmereUI.MakePopupButton(popup, "BOTTOM", popup, "BOTTOM", 0, 18,
            1, 1, 1, 0.75, 1, 1, 1, 1, 1, 1, 1, 0.25, 1, 1, 1, 0.5)
        p.cancel._lbl:SetText(EllesmereUI.L("Cancel"))
        p.cancel:SetScript("OnClick", p.Close)
        picker = p
    end
    if not baseIcons then
        baseIcons = {}
        GetLooseMacroIcons(baseIcons)
        GetLooseMacroItemIcons(baseIcons)
        GetMacroIcons(baseIcons)
        GetMacroItemIcons(baseIcons)
    end
    local spells, seen = {}, {}
    for _, s in ipairs(S.List()) do
        if s.icon and not seen[s.icon] then seen[s.icon] = true; spells[#spells + 1] = s.icon end
    end
    picker.spells, picker.offset, picker.onPick, picker.current = spells, 0, onPick, cur.icon
    picker.cancel._resetAnim()
    picker.Update()
    picker.dimmer:Show()
    -- The bar's range: one row per COLS icons, back at the top on every open.
    picker.child:SetHeight(math.ceil((1 + #spells + #baseIcons) / COLS) * SIZE)
    picker.scrollTo(0)
    picker.updateThumb()
end

-------------------------------------------------------------------------------
--  Dropdown value tables
-------------------------------------------------------------------------------
-- Line types in one flyout per group (the { group } rows of B.KINDS). The
-- groups' lists are built once; onSelect(kind) belongs to each menu. A hidden
-- kind is in its group's values but not its order: a line read as one shows
-- its label, and the menu never offers it.
local kindGroups
local function KindValues(onSelect)
    if not kindGroups then
        kindGroups = {}
        local g
        for _, k in ipairs(B.KINDS) do
            if k.group then
                g = { key = "group" .. (#kindGroups + 1), text = k.group, values = {}, order = {} }
                kindGroups[#kindGroups + 1] = g
            else
                g.values[k.key] = k.label
                if not k.hidden then g.order[#g.order + 1] = k.key end
            end
        end
    end
    local values, order = { __pick = "Choose a type" }, {}
    for i, g in ipairs(kindGroups) do
        values[g.key] = { text = g.text, subnav = { values = g.values, order = g.order, onSelect = onSelect } }
        order[i] = g.key
    end
    return values, order
end

-- { { value, label } } -> values, order; sentinel stands in for an empty value.
local function ListValues(list, sentinel)
    local values, order = {}, {}
    for _, it in ipairs(list) do
        local k = it.value == "" and sentinel or it.value
        values[k] = it.label
        order[#order + 1] = k
    end
    return values, order
end

-- Channel and target lists once; stances once per page build.
local chanV, chanO, targV, targO, stanceV, stanceO

-------------------------------------------------------------------------------
--  Line editor.
--  ctx: model, open (the expanded line), headers, onChange(structural, clean)
-------------------------------------------------------------------------------
-- Two lanes per condition, as the Show / Hide menus: [cond] left, [nocond]
-- right. Conditions with a value follow under their own header ("p:" keys).
local COND_ITEMS
local function CondItems()
    if not COND_ITEMS then
        COND_ITEMS = { { isHeader = true, label = "Condition", rightLabel = "Not" } }
        for _, d in ipairs(B.CONDS) do
            COND_ITEMS[#COND_ITEMS + 1] = { key = d.key, label = d.label, dual = true,
                tooltip = "[" .. d.key .. "] / [no" .. d.key .. "]  " .. L(d.tip) }
        end
        COND_ITEMS[#COND_ITEMS + 1] = { isHeader = true, label = "With a Value", rightLabel = "Not" }
        for _, p in ipairs(B.PARAMS) do
            COND_ITEMS[#COND_ITEMS + 1] = { key = "p:" .. p.key, label = p.label, dual = true,
                tooltip = "[" .. p.key .. ":...]  " .. L(p.tip) }
        end
    end
    return COND_ITEMS
end

local function FindParam(v, key)
    for j, prm in ipairs(v.params) do
        if prm.key == key then return prm, j end
    end
end

-- Multi-select value: "a/b" holds every picked option.
local function HasValue(value, opt)
    for part in (value or ""):gmatch("[^/]+") do
        if part == opt then return true end
    end
end

local function LineCode(i, l)
    local code = B.LineText(l)
    if code == "" then code = EllesmereUI.L("(empty line)") end
    return i .. ".  " .. code
end

local function SetKind(l, kind)
    local K = B.KIND[kind]
    l.kind = kind
    if not K.multi then
        while #l.variants > 1 do table.remove(l.variants) end
    end
    if not K.arg then
        for _, v in ipairs(l.variants) do v.arg = "" end
    end
    if kind == "targetmarker" and not (l.variants[1].arg or ""):match("^[0-8]$") then
        l.variants[1].arg = "8"
    end
end

-- A line as one row: its code, then move and remove; a click opens it.
local function LineHeader(body, y, ctx, i, l)
    local W = EllesmereUI.Widgets
    local lines = ctx.model.lines
    local open = ctx.open == l
    local row, h = W:DualRow(body, y, { type = "label", text = LineCode(i, l) })
    local rgn = row._leftRegion
    local label = rgn._label
    label:SetFont(EllesmereUI.EXPRESSWAY, 13, "")
    ctx.headers[#ctx.headers + 1] = { fs = label, i = i, l = l }
    if open then
        local ac = Accent()
        local bar = row:CreateTexture(nil, "ARTWORK", nil, 2)
        bar:SetColorTexture(ac.r, ac.g, ac.b, 1)
        bar:SetPoint("TOPLEFT")
        bar:SetPoint("BOTTOMLEFT")
        bar:SetWidth(2)
    end

    local del = Glyph(rgn, 16, nil, function()
        table.remove(lines, i)
        if open then ctx.open = nil end
        ctx.onChange(true)
    end, EllesmereUI.L("Remove line"))
    EllesmereUI.SetDeleteIcon(del.tex)
    del:SetPoint("RIGHT", rgn, "RIGHT", -20, 0)
    local function Move(d)
        local j = i + d
        lines[i], lines[j] = lines[j], lines[i]
        ctx.onChange(true)
    end
    local down = Glyph(rgn, 18, "eui-arrow-down3.png", function() Move(1) end, EllesmereUI.L("Move down"))
    down:SetPoint("RIGHT", del, "LEFT", -14, 0)
    down:SetEnabled(i < #lines)
    local up = Glyph(rgn, 18, "eui-arrow-up3.png", function() Move(-1) end, EllesmereUI.L("Move up"))
    up:SetPoint("RIGHT", down, "LEFT", -2, 0)
    up:SetEnabled(i > 1)
    label:SetPoint("RIGHT", up, "LEFT", -12, 0)

    local hit = CreateFrame("Button", nil, row)
    hit:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    hit:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -100, 0)
    hit:SetFrameLevel(rgn:GetFrameLevel() + 3)
    local hl = SolidTex(hit, "BACKGROUND", 1, 1, 1, 0)
    hl:SetAllPoints(row)
    local K = B.KIND[l.kind] or B.KIND.raw
    hit:SetScript("OnEnter", function(self)
        hl:SetColorTexture(1, 1, 1, 0.03)
        EllesmereUI.ShowWidgetTooltip(self, L(K.label) .. "\n" .. L(K.desc) .. "\n\n"
            .. (open and EllesmereUI.L("Click to close.") or EllesmereUI.L("Click to edit.")))
    end)
    hit:SetScript("OnLeave", function()
        hl:SetColorTexture(1, 1, 1, 0)
        EllesmereUI.HideWidgetTooltip()
    end)
    hit:SetScript("OnClick", function()
        ctx.open = (not open) and l or nil
        ctx.onChange(true, true)
    end)
    return y - h
end

-- What a DualRow cannot build itself: checkbox dropdowns, suggestions, inline buttons.
local function PostCell(rgn, cfg)
    if not cfg then return end
    if cfg.type == "input" and rgn._control then boxes[rgn._control] = true end
    if cfg._cb then
        if rgn._control then rgn._control:Hide() end
        local cb = cfg._cb
        local dd, refresh = EllesmereUI.BuildVisOptsCBDropdown(rgn, 170, rgn:GetFrameLevel() + 2, cb.items,
            cb.get, cb.set, nil, 14, nil, nil, cb.onClosed, { noAllLabel = true })
        PP.Point(dd, "RIGHT", rgn, "RIGHT", -20, 0)
        rgn._control = dd
        EllesmereUI.RegisterWidgetRefresh(refresh)
    end
    if cfg._suggest and rgn._control then
        AttachSuggest(rgn._control, cfg.setValue, cfg._suggest == "list")
    end
    if cfg._maxLetters and rgn._control then rgn._control:SetMaxLetters(cfg._maxLetters) end
    if cfg._remove then
        EllesmereUI.BuildInlineButton(rgn, EllesmereUI.L("Remove"), cfg._remove, { width = 80 })
    end
    if cfg._icon and rgn._control then
        local tex = rgn:CreateTexture(nil, "ARTWORK")
        tex:SetSize(28, 28)
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        PP.Point(tex, "RIGHT", rgn._control, "LEFT", -10, 0)
        tex:SetTexture(IconPath(cfg._icon()))
        EllesmereUI.RegisterWidgetRefresh(function() tex:SetTexture(IconPath(cfg._icon())) end)
    end
end

-- Cells two per row, filled left to right.
local function EmitCells(body, y, cells)
    local W = EllesmereUI.Widgets
    for i = 1, #cells, 2 do
        local a, b = cells[i], cells[i + 1]
        local row, h = W:DualRow(body, y, a, b or EllesmereUI.BlankRowCfg())
        PostCell(row._leftRegion, a)
        PostCell(row._rightRegion, b)
        y = y - h
    end
    return y
end

local function Input(text, get, set, opts)
    opts = opts or {}
    return {
        type = "input", text = text, inputStyle = "popup", inputWidth = opts.width or 200,
        placeholder = opts.ph, tooltip = opts.tip,
        disabled = opts.disabled, disabledTooltip = opts.disabledTooltip,
        getValue = get,
        -- Every focus loss commits: an unchanged text is no edit.
        setValue = function(t) if t ~= (get() or "") then set(t) end end,
        _suggest = opts.suggest, _maxLetters = opts.maxLetters,
    }
end

local function Dropdown(text, values, order, get, set, tip)
    return { type = "dropdown", text = text, values = values, order = order,
        getValue = get, setValue = set, tooltip = tip }
end

-- Raid markers 1-8 with their icons, 0 clears.
local MARKER_ICONS = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
local MARKER_ORDER = { "1", "2", "3", "4", "5", "6", "7", "8", "0" }
local markerValues
local function MarkerValues()
    if not markerValues then
        markerValues = { _noLoc = true, ["0"] = EllesmereUI.L("Clear Marker") }
        for i = 1, 8 do markerValues[tostring(i)] = _G["RAID_TARGET_" .. i] end
        markerValues._menuOpts = {
            icon = function(key)
                local i = tonumber(key)
                if not i or i < 1 then return nil end
                local l, t = ((i - 1) % 4) * 0.25, floor((i - 1) / 4) * 0.25
                return MARKER_ICONS, l, l + 0.25, t, t + 0.25
            end,
        }
    end
    return markerValues
end

-- The settings of one line (and of each of its variants).
local function LineRows(body, y, ctx, l)
    local K = B.KIND[l.kind] or B.KIND.raw
    local cells = {}
    local function Add(c) cells[#cells + 1] = c end
    local function Changed() ctx.onChange(false) end
    local v1 = l.variants[1]

    local kv, ko = KindValues(function(k) SetKind(l, k); ctx.onChange(true) end)
    Add(Dropdown("Type", kv, ko, function() return l.kind end, function() end, K.desc))

    if K.key == "chat" then
        Add(Input("Message", function() return v1.arg end, function(t) v1.arg = t; Changed() end, { ph = K.ph }))
        if not chanV then chanV, chanO = ListValues(B.CHANNELS) end
        Add(Dropdown("Channel", chanV, chanO, function() return l.chan end, function(c) l.chan = c; Changed() end))
    elseif K.arg == "spells" then
        Add(Input("Spells", function() return v1.arg end, function(t) v1.arg = t; Changed() end,
            { ph = K.ph or "Spell1, Spell2, Spell3", suggest = "list" }))
        if K.reset then
            Add(Input("Reset", function() return l.reset end, function(t) l.reset = t; Changed() end, {
                ph = "target/combat/8",
                tip = "When the sequence starts over: target (target change), combat (leaving combat), shift/ctrl/alt or seconds. Separate several with /." }))
        end
    end

    local count = K.conds and (K.multi and #l.variants or 1)
        or ((K.arg and K.arg ~= "spells" and K.key ~= "chat") and 1 or 0)
    for k = 1, count do
        local v = l.variants[k]
        if k > 1 then
            Add({ type = "label", text = EllesmereUI.Lf("Else: Variant %d", k),
                tooltip = "Variants are checked top to bottom: the first one whose conditions match is used. A variant without conditions is the fallback.",
                _remove = function() table.remove(l.variants, k); ctx.onChange(true) end })
        end
        if K.key == "targetmarker" then
            Add(Dropdown("Marker", MarkerValues(), MARKER_ORDER, function() return v.arg end,
                function(m) v.arg = m; Changed() end))
        elseif K.arg and K.arg ~= "spells" and K.key ~= "chat" then
            local text = K.arg == "spell" and "Spell" or (K.arg == "unit" and "Unit or Name" or "Text")
            Add(Input(text, function() return v.arg end, function(t) v.arg = t; Changed() end,
                { ph = K.ph, suggest = K.arg == "spell" or nil }))
        end
        if K.conds then
            if not targV then targV, targO = ListValues(B.TARGETS, "none") end
            Add(Dropdown("Target", targV, targO,
                function() return v.target ~= "" and v.target or "none" end,
                function(t) v.target = t == "none" and "" or t; Changed() end))
            if not stanceV then stanceV, stanceO = ListValues(B.Stances(), "any") end
            Add(Dropdown("Stance", stanceV, stanceO,
                function() return v.stance ~= "" and v.stance or "any" end,
                function(s) v.stance = s == "any" and "" or s; Changed() end,
                "Numbers follow your stance bar; 0 = no stance or normal form."))
            -- Checking a condition with a value adds its value row, and Not
            -- renames it ("not ..."): the page rebuilds once the menu closes.
            local addedRows
            local cond = Dropdown("Conditions", { _p = "" }, { "_p" }, function() return "_p" end, function() end,
                "The line only runs while the left ones are true and the right (Not) ones are false.")
            cond._cb = {
                items = CondItems(),
                get = function(key, neg)
                    local pk = key:match("^p:(.+)$")
                    if pk then
                        local prm = FindParam(v, pk)
                        return prm ~= nil and (prm.no == true) == (neg == true)
                    end
                    return v.conds[key] == (neg and 2 or 1)
                end,
                set = function(key, on, neg)
                    local pk = key:match("^p:(.+)$")
                    if pk then
                        local prm, j = FindParam(v, pk)
                        if on then
                            if not prm then
                                prm = B.NewParam(pk)
                                v.params[#v.params + 1] = prm
                                addedRows = true
                            end
                            if (prm.no == true) ~= (neg == true) then addedRows = true end
                            prm.no = neg == true
                        elseif prm and (prm.no == true) == (neg == true) then
                            table.remove(v.params, j)
                            addedRows = true
                        end
                    else
                        local mark = neg and 2 or 1
                        if on then v.conds[key] = mark elseif v.conds[key] == mark then v.conds[key] = nil end
                    end
                    Changed()
                end,
                onClosed = function()
                    if addedRows then addedRows = nil; ctx.onChange(true) end
                end,
            }
            Add(cond)

            -- One value row per condition with a value.
            for _, prm in ipairs(v.params) do
                local P = B.PARAM[prm.key] or {}
                local text = (prm.no and (L("not") .. " ") or "") .. L(P.label or prm.key)
                local function SetVal(t) prm.value = t; Changed() end
                if P.options then
                    local opts = P.options()
                    local items = {}
                    for i, o in ipairs(opts) do items[i] = { key = o.value, label = o.label } end
                    local cell = Dropdown(text, { _p = "" }, { "_p" }, function() return "_p" end, function() end, P.tip)
                    cell._cb = {
                        items = items,
                        get = function(key) return HasValue(prm.value, key) end,
                        set = function(key, on)
                            local out = {}
                            for _, o in ipairs(opts) do
                                local keep = o.value == key and on or (o.value ~= key and HasValue(prm.value, o.value))
                                if keep then out[#out + 1] = o.value end
                            end
                            SetVal(table.concat(out, "/"))
                        end,
                    }
                    Add(cell)
                elseif P.spell then
                    Add(Input(text, function() return prm.value end, SetVal,
                        { suggest = true, tip = P.tip, ph = "Spell (several: Spell1/Spell2)" }))
                else
                    Add(Input(text, function() return prm.value end, SetVal, { ph = P.text, tip = P.tip }))
                end
            end
        end
    end
    if K.multi then
        Add({ type = "button", text = "+ Add Else Variant", width = 200, onClick = function()
            local last = l.variants[#l.variants]
            l.variants[#l.variants + 1] = B.NewVariant(last and last.arg or "")
            ctx.onChange(true)
        end })
    end
    return EmitCells(body, y, cells)
end

local function BuildLines(body, y, ctx)
    local W = EllesmereUI.Widgets
    local _, h = W:SectionHeader(body, "LINES", y);  y = y - h
    local kv, ko = KindValues(function(k)
        local l = B.NewLine(k)
        table.insert(ctx.model.lines, l)
        ctx.open = l
        ctx.onChange(true)
    end)
    _, h = W:DualRow(body, y,
        Dropdown("Add Line", kv, ko, function() return "__pick" end, function() end,
            "Adds a line to the macro. Lines run top to bottom."),
        EllesmereUI.BlankRowCfg());  y = y - h
    wipe(ctx.headers)
    local found = false
    for i, l in ipairs(ctx.model.lines) do
        y = LineHeader(body, y, ctx, i, l)
        if ctx.open == l then
            found = true
            y = LineRows(body, y, ctx, l)
        end
    end
    if not found then ctx.open = nil end
    return y
end

-- Header code labels follow value edits without a rebuild.
local function UpdateHeaders(ctx)
    for _, hd in ipairs(ctx.headers) do hd.fs:SetText(LineCode(hd.i, hd.l)) end
end

-------------------------------------------------------------------------------
--  Editor state
-------------------------------------------------------------------------------
local function NewState(perChar)
    return { perChar = perChar and true or false, name = "", icon = MM.QUESTION,
        model = B.New(), text = "#showtooltip", dirty = false, nameTouched = false }
end

-- m: a macro entry; it becomes the editor's ref, the identity every write checks.
local function StateOf(m)
    return { ref = m, perChar = m.perChar, name = m.name, icon = MM.StoredIcon(m.index),
        model = B.Parse(m.body), text = m.body, dirty = false, nameTouched = true }
end

-- The page's text field with the keyboard focus commits now, to the macro it
-- was typed for: a click with a modifier held keeps the focus, so its commit
-- would otherwise land on whatever the editor holds next. Only while the page
-- is on screen (a rebuild under way commits nothing), and only the page's own
-- fields: a focused frame of the game or another addon is never touched.
local function FlushField()
    if not shown then return end
    local f = GetCurrentKeyBoardFocus()
    if f and boxes[f] then f:ClearFocus() end
end

-- Another macro in the editor: a value typed for the last one commits to it
-- first; then no open line, no status and no unread typed text remain.
local function SetCur(state)
    FlushField()
    cur, statusText, statusBad, edCtx.open, textDirty = state, nil, nil, nil, nil
end

local function Guard(fn)
    if cur and cur.dirty then
        EllesmereUI:ShowConfirmPopup({
            title = EllesmereUI.L("Unsaved Changes"),
            message = EllesmereUI.L("Discard your unsaved changes to this macro?"),
            confirmText = EllesmereUI.L("Discard"),
            cancelText = EllesmereUI.L("Cancel"),
            onConfirm = fn,
        })
    else
        fn()
    end
end

local function SetStatus(text, bad)
    statusText, statusBad = text, bad
    if not D.info then return end
    if bad then
        D.info:SetTextColor(1, 0.35, 0.35, 1)
    else
        local ac = Accent()
        D.info:SetTextColor(ac.r, ac.g, ac.b, 1)
    end
    D.info:SetText(text or "")
end

local function UpdateMacroText()
    cur.text = B.Build(cur.model)
    if D.text then D.text:SetText(cur.text) end
    if D.count then PaintCounter(D.count, strlenutf8(cur.text)) end
end

local function Dirty()
    cur.dirty = true
    SetStatus(EllesmereUI.L("Unsaved changes"))
end

local function RebuildIfPending()
    if shown and pendingRebuild then
        pendingRebuild = nil
        Rebuild()
    end
end

-- The lines are built again once the click under way is done, never from
-- inside a blur (the page may be mid-teardown).
local function RebuildAfterClick()
    pendingRebuild = true
    if IsMouseButtonDown() then
        evf:RegisterEvent("GLOBAL_MOUSE_UP")
    else
        C_Timer.After(0, RebuildIfPending)
    end
end

-- Typed macro text read into lines: on blur, at Save, on hide and before any
-- other edit (a modifier-held click keeps the text box focused, so it can
-- reach a control with the text unread). Returns true when it read.
local function ReadText()
    if not textDirty then return false end
    textDirty = nil
    cur.model = B.Parse(cur.text)
    edCtx.open = nil
    RebuildAfterClick()
    return true
end

-- A click on lines built before the text was read: refused, and said.
local function RefuseClick()
    SetStatus(EllesmereUI.L("The lines were rebuilt from the macro text. Click again."), true)
end

-- A setting of the macro changed. structural: the lines are built again;
-- clean: nothing to save (a line opened or closed).
local function ApplyEdit(structural, clean)
    if ReadText() then RefuseClick() return end
    if not clean then
        Dirty()
        if not cur.nameTouched and not cur.ref then cur.name = MM.CleanName(B.FirstSpell(cur.model)) end
    end
    UpdateMacroText()
    if structural then Rebuild() return end
    UpdateHeaders(edCtx)
    Refresh()
end

-- The lines' widgets hold the line tables they were built with: until the
-- lines are built again after a text edit, their clicks are refused.
edCtx.onChange = function(structural, clean)
    if pendingRebuild then RefuseClick() return end
    ApplyEdit(structural, clean)
end

-------------------------------------------------------------------------------
--  The macro grid in the content header, centered row by row like the action
--  bar preview. Cells are pooled; the grid re-parents into each header.
-------------------------------------------------------------------------------
-- Places count cells centered in rows of w; bind(cell, i) fills each one.
-- Returns the grid's height.
local function LayoutGrid(g, hdr, y, w, count, bind)
    if not g.frame then
        local f = CreateFrame("Frame", nil, hdr)
        local scroll = CreateFrame("ScrollFrame", nil, f)
        scroll:SetAllPoints()
        scroll:SetClipsChildren(true)
        local child = CreateFrame("Frame", nil, scroll)
        child:SetSize(10, 10)
        scroll:SetScrollChild(child)
        g.frame, g.child, g.cells = f, child, {}
        g.update = AttachScroll(scroll, child)
    end
    g.frame:SetParent(hdr)
    local perRow = max(1, floor((w + 4) / CELL))
    local rows = math.ceil(count / perRow)
    local h = max(1, min(rows, GRID_ROWS)) * CELL
    g.frame:ClearAllPoints()
    g.frame:SetPoint("TOP", hdr, "TOP", 0, y)
    g.frame:SetSize(w, h)
    g.child:SetSize(w, rows * CELL)
    for i = 1, count do
        local cell = g.cells[i]
        if not cell then
            cell = NewCell(g.child)
            g.cells[i] = cell
        end
        local row = floor((i - 1) / perRow)
        local inRow = min(perRow, count - row * perRow)
        local x = floor((w - inRow * CELL) / 2) + ((i - 1) % perRow) * CELL + 2
        cell:ClearAllPoints()
        cell:SetPoint("TOPLEFT", g.child, "TOPLEFT", x, -row * CELL - 2)
        bind(cell, i)
        cell:Show()
    end
    for i = count + 1, #g.cells do g.cells[i]:Hide() end
    g.frame:Show()
    g.update()
    return h
end

-- Fills cell i of the macro grid from gridList; past the list is the "+" cell.
local function BindMacroCell(c, i)
    local m = gridList[i]
    c.m, c.newCell = m, m == nil
    c.icon:SetShown(m ~= nil)
    c.plus:SetShown(m == nil)
    c.name:SetText(m and m.name or "")
    if m then
        c.icon:SetTexture(IconPath(m.icon))
        c.selected = cur.ref ~= nil and cur.ref.index == m.index
    else
        c.selected = not cur.ref and cur.perChar == (mode == "char")
    end
    c.Paint(false)
end

-- The header's list in place: the counts, the grid, and the snapshot a
-- re-show compares with. Returns the header's height.
local function PaintHeader()
    local a, c = GetNumMacros()
    hdrValues.account = EllesmereUI.L("Account Macros") .. "  (" .. a .. "/" .. MM.MAX_ACCOUNT .. ")"
    hdrValues.char = EllesmereUI.L("Character Macros") .. "  (" .. c .. "/" .. MM.MAX_CHAR .. ")"
    hdrDD._invalidateMenu()   -- the menu is built again from the new labels on its next open
    local perChar = mode == "char"
    gridList = MM.List(perChar)
    local count = #gridList + (MM.Free(perChar) > 0 and 1 or 0)
    local gh = LayoutGrid(macroGrid, hdrFrame, hdrY, hdrW, count, BindMacroCell)
    MM.Diff(snap, true)
    return math.abs(hdrY - gh - 14)
end

-------------------------------------------------------------------------------
--  Following the game
-------------------------------------------------------------------------------
-- The editor's macro after a macro change, ours or from elsewhere. A clean
-- editor follows the game: the macro's icon, its text edited elsewhere (found
-- by its name), or a new macro once it is gone. A dirty one keeps its edits;
-- its Save finds the macro again or refuses.
local function Follow()
    local ref = cur.ref
    if not ref then return end
    local i = MM.Resolve(ref)
    if cur.dirty then return end
    if i then
        cur.icon = MM.StoredIcon(i)
        return
    end
    -- A value typed but not committed yet belongs to this macro: it lands
    -- first, and the editor then keeps it.
    FlushField()
    if cur.dirty then return end
    i = MM.Resolve(ref, true)
    SetCur(i and StateOf(MM.Entry(i)) or NewState(cur.perChar))
end

-- A macro change while shown: the header repaints in place; the body is built
-- again only when the editor changed or a new macro got its slot.
local function OnMacrosChanged()
    Follow()
    if cur ~= builtFor or (cur.ref ~= nil) ~= builtHadRef then Rebuild() return end
    if hdrDD and hdrDD:IsVisible() then EllesmereUI:SetContentHeaderHeightSilent(PaintHeader()) end
    Refresh()
end

local function ResyncNow()
    pendingEvent = nil
    if shown then OnMacrosChanged() end
end

-- Bursts (several macros changed at once) settle in one pass on the next frame.
local function RequestResync()
    if pendingEvent then return end
    pendingEvent = true
    C_Timer.After(0, ResyncNow)
end

-------------------------------------------------------------------------------
--  Macro actions: each write finds its macro again first, or refuses
-------------------------------------------------------------------------------
-- Whether m is the macro the editor holds.
local function IsCur(m)
    local i = MM.Resolve(m)
    return i ~= nil and cur.ref ~= nil and MM.Resolve(cur.ref) == i
end

local function PickupRef(m)
    local ok, err = MM.Pickup(m)
    if not ok then SetStatus(err, true) end
end

local function Save()
    FlushField() -- a field typed in but not committed (a click with a modifier held keeps its focus)
    ReadText()   -- text typed but not read yet: read now, and the lines follow
    local name = MM.CleanName(cur.name)
    if name == "" then name = MM.CleanName(B.FirstSpell(cur.model)) end
    local bad = MM.Check(name, cur.text)
    if bad then SetStatus(bad, true) return end
    local function Commit()
        -- A saved macro keeps the icon it has unless one was picked here: it
        -- may have been changed elsewhere since the editor read it.
        local icon = (cur.iconSet or not cur.ref) and cur.icon or nil
        local m, err = MM.Save(cur.ref, name, icon, cur.text, cur.perChar)
        if not m then SetStatus(err, true) return end
        mode = m.perChar and "char" or "account"   -- a saved macro shows in its list
        if m.body == cur.text then
            cur.ref, cur.perChar, cur.name, cur.dirty, cur.iconSet = m, m.perChar, m.name, false, nil
            SetStatus(EllesmereUI.L("Saved."))
        else
            SetCur(StateOf(m))                     -- the game kept another text: show it
            SetStatus(EllesmereUI.L("Saved, but the game changed the text: this is what it kept."), true)
        end
        RequestResync()
    end
    -- Two macros of one name are allowed, but a key bound by name finds the first.
    if (not cur.ref or name ~= cur.ref.name) and MM.NameTaken(name, cur.perChar) then
        EllesmereUI:ShowConfirmPopup({
            title = EllesmereUI.L("Name Taken"),
            message = EllesmereUI.Lf("Another macro in this list is already named %s. Save anyway?", name),
            confirmText = EllesmereUI.L("Save"),
            cancelText = EllesmereUI.L("Cancel"),
            onConfirm = Commit,
        })
        return
    end
    Commit()
end

local function DeleteMacro(m)
    EllesmereUI:ShowConfirmPopup({
        title = EllesmereUI.L("Delete Macro"),
        message = EllesmereUI.Lf("Delete the macro %s?", m.name),
        confirmText = EllesmereUI.L("Delete"),
        cancelText = EllesmereUI.L("Cancel"),
        onConfirm = function()
            local isCur = IsCur(m)
            local ok, err = MM.Delete(m)
            if not ok then SetStatus(err, true) return end
            if isCur then SetCur(NewState(m.perChar)) end
            RequestResync()
        end,
    })
end

-- Account <-> character: the macro is made again in the other list.
local function MoveScope(m)
    local toChar = not m.perChar
    local message = (toChar and EllesmereUI.Lf("Move %s to this character?", m.name)
        or EllesmereUI.Lf("Move %s to the account?", m.name))
        .. "\n" .. EllesmereUI.L("Action bar buttons with this macro have to be placed again.")
    -- As at Save: a key bound by name finds the first of two macros of one name.
    if MM.NameTaken(m.name, toChar) then
        message = message .. "\n" .. EllesmereUI.Lf("Another macro in that list is already named %s.", m.name)
    end
    EllesmereUI:ShowConfirmPopup({
        title = EllesmereUI.L("Move Macro"),
        message = message,
        confirmText = EllesmereUI.L("Move"),
        cancelText = EllesmereUI.L("Cancel"),
        onConfirm = function()
            local isCur = IsCur(m)
            local moved, err = MM.Save(m, m.name, nil, m.body, toChar)
            if not moved then SetStatus(err, true) return end
            if isCur then
                cur.ref, cur.perChar = moved, moved.perChar
                mode = toChar and "char" or "account"   -- the editor's macro shows in its list
            end
            RequestResync()
        end,
    })
end

local menuOwner   -- the cell whose right-click menu opened last

local function MacroMenu(anchor, m)
    menuOwner = anchor
    EllesmereUI.ShowContextMenu(anchor, {
        { text = m.perChar and "Move to Account" or "Move to Character", onClick = function() MoveScope(m) end },
        { text = "Pick Up", onClick = function() PickupRef(m) end },
        "---",
        { text = "Delete", onClick = function() DeleteMacro(m) end },
    })
end

CellClick = function(self, btn)
    local m = self.m
    if btn == "RightButton" then
        if m then MacroMenu(self, m) end
        return
    end
    local perChar = mode == "char"
    if m and cur.ref and cur.ref.index == m.index then return end   -- open already
    if not m and not cur.ref and cur.perChar == perChar then return end
    FlushField()   -- a value typed but not committed lands first, so Guard sees it
    Guard(function()
        SetCur(m and StateOf(m) or NewState(perChar))
        Rebuild()
    end)
end

CellDrag = function(self)
    if not self.m then return end
    EllesmereUI.HideWidgetTooltip()
    PickupRef(self.m)
end

-- Centered list dropdown over the centered icons (the Action Bars header).
HeaderBuilder = function(hdr, width)
    hdrFrame, hdrY, hdrW = hdr, -20 - 34 - 12, width - EllesmereUI.CONTENT_PAD * 2
    hdrValues = { _noLoc = true }
    hdrDD = EllesmereUI.BuildDropdownControl(hdr, 350, hdr:GetFrameLevel() + 5, hdrValues, LIST_ORDER,
        function() return mode end,
        function(v)
            if v == mode then return end
            FlushField()   -- a value typed but not committed lands first: the editor may be dirty then
            mode = v
            -- Another list starts a new macro unless one is being edited.
            if not cur.dirty and cur.perChar ~= (v == "char") then SetCur(NewState(v == "char")) end
            Rebuild()
        end)
    PP.Point(hdrDD, "TOP", hdr, "TOP", 0, -20)
    hdrDD:SetHeight(34)
    return PaintHeader()
end
_G._EUI_MacrosHeaderBuilder = HeaderBuilder

-------------------------------------------------------------------------------
--  Events: while the page is shown
-------------------------------------------------------------------------------
local function OnEvent(self, event)
    if event == "GLOBAL_MOUSE_UP" then
        self:UnregisterEvent("GLOBAL_MOUSE_UP")
        C_Timer.After(0, RebuildIfPending)   -- next frame: after the click that ended the text edit
    elseif event == "SPELLS_CHANGED" then
        S.Invalidate()                        -- read again where it is next used
    else
        RequestResync()                       -- UPDATE_MACROS
    end
end

-- The icon picker and a cell's right-click menu close with the page once it
-- stays hidden: a rebuild hides and shows it again at once, so a popup the
-- click under way opened stays.
local function ClosePopupsIfHidden()
    if shown then return end
    if picker then picker.Close() end
    if menuOwner and EllesmereUI.ContextMenuOwner() == menuOwner then EllesmereUI.CloseContextMenu() end
end

-- One event frame, re-parented into each build of the page: its show and hide
-- are the page's, so the events are registered only while the page is shown.
local function WatchEvents(parent)
    if not evf then
        evf = CreateFrame("Frame")
        evf._searchIgnore = true  -- the inline search never hides it
        evf:SetScript("OnEvent", OnEvent)
        evf:SetScript("OnShow", function(self)
            shown = true
            self:RegisterEvent("UPDATE_MACROS")
            self:RegisterEvent("SPELLS_CHANGED")
            -- Hidden in this same frame: a rebuild, which has just read both.
            if GetTime() == hiddenAt then return end
            -- Shown again: spells and macros may have changed while hidden.
            S.Invalidate()
            if pendingRebuild then
                C_Timer.After(0, RebuildIfPending)
            elseif MM.Diff(snap) then
                RequestResync()
            end
        end)
        evf:SetScript("OnHide", function(self)
            shown, hiddenAt = nil, GetTime()
            -- Text typed but not read into lines yet: read it now; the lines are
            -- built on the next show.
            ReadText()
            self:UnregisterAllEvents()
            HideSuggest()
            if (picker and picker.dimmer:IsShown())
                or (menuOwner and EllesmereUI.ContextMenuOwner() == menuOwner) then
                C_Timer.After(0, ClosePopupsIfHidden)
            end
        end)
    end
    evf:Hide()
    evf:SetParent(parent)
    evf:Show()
end

-------------------------------------------------------------------------------
--  Page body
-------------------------------------------------------------------------------
local function BuildMacroBody(parent, y, enable)
    local W = EllesmereUI.Widgets
    local _, h
    edCtx.model = cur.model
    y = EmitCells(parent, y, {
        enable,
        Input("Name", function() return cur.name end, function(t)
            t = MM.CleanName(t)
            if t == cur.name then return end
            cur.name, cur.nameTouched = t, true
            Dirty()
        end, { width = 170, ph = "Max. 16 characters", maxLetters = MM.MAX_NAME }),
        { type = "dropdown", text = "Saved For", values = { account = "Account", char = "Character" },
          order = LIST_ORDER,
          tooltip = "Account macros exist on all your characters, character macros only on this one.",
          getValue = function() return cur.perChar and "char" or "account" end,
          setValue = function(v) cur.perChar = v == "char"; Dirty() end,
          -- A saved macro moves through Move, which warns that its bar buttons go.
          disabled = function() return cur.ref ~= nil end, rawTooltip = true,
          disabledTooltip = "A saved macro changes lists through Move in its right-click menu." },
        { type = "labeledButton", text = "Icon", buttonText = "Choose Icon", width = 130,
          onClick = function()
              OpenPicker(function(icon)
                  cur.icon, cur.iconSet = icon or MM.QUESTION, true
                  Dirty()
                  Refresh()
              end)
          end,
          _icon = function() return cur.icon end },
        { type = "toggle", text = "Show Spell Tooltip", tooltip = "#showtooltip: the button shows the spell's icon and tooltip.",
          getValue = function() return cur.model.tooltip end,
          setValue = function(v) cur.model.tooltip = v; ApplyEdit(false) end },
        Input("Tooltip Spell", function() return cur.model.tooltipSpell end,
            function(t) cur.model.tooltipSpell = t; ApplyEdit(false) end,
            { ph = "Empty = automatic", suggest = true,
              disabled = function() return not cur.model.tooltip end, disabledTooltip = "Show Spell Tooltip" }),
    })

    _, h = W:Spacer(parent, y, 20);  y = y - h
    -- The LINES rows show live macro text: kept out of the search index (the
    -- flag is restored even when a row errors).
    local prev = EllesmereUI._searchIndexSuppress
    EllesmereUI._searchIndexSuppress = true
    local ok, ny = pcall(BuildLines, parent, y, edCtx)
    EllesmereUI._searchIndexSuppress = prev
    if not ok then error(ny, 0) end
    y = ny

    _, h = W:Spacer(parent, y, 20);  y = y - h
    _, h = W:SectionHeader(parent, "MACRO TEXT", y);  y = y - h
    local box, count, info = TextBlock(parent, y)
    y = y - TEXT_H
    D.text, D.count, D.info = box, count, info
    box:SetText(cur.text)
    PaintCounter(count, strlenutf8(cur.text))
    SetStatus(statusText, statusBad)
    -- Typing is read into lines on blur (and at Save), not per keystroke.
    box.onChange = function(text, user)
        if not user then return end
        cur.text, textDirty = text, true
        Dirty()
        PaintCounter(count, strlenutf8(text))
    end
    box.onBlur = ReadText

    local notSaved = { disabled = true, tooltip = EllesmereUI.L("Save the macro first.") }
    -- Deleting the open macro leaves no ref until the body is built again.
    _, h = W:WideTripleButton(parent, "Save", "Pick Up", "Delete", y,
        Save,
        function() if cur.ref then PickupRef(cur.ref) end end,
        function() if cur.ref then DeleteMacro(cur.ref) end end,
        nil, not cur.ref and { [2] = notSaved, [3] = notSaved } or nil);  y = y - h
    builtFor, builtHadRef = cur, cur.ref ~= nil
    return y
end

-------------------------------------------------------------------------------
--  Page entry point
-------------------------------------------------------------------------------
_G._EUI_BuildForeverMacrosPage = function(pageName, parent, yOffset)
    local W = EllesmereUI.Widgets
    local KIT = EllesmereUI._MacroManager
    local y = yOffset
    local _, h
    parent._showRowDivider = true
    _, h = W:SectionHeader(parent, "MACRO", y);  y = y - h
    local enable = { type = "toggle", text = "Enable Macro Manager",
        tooltip = "Edit your macros by click: a line editor with every option and the live macro text. /euimacros opens this page.",
        getValue = KIT.Enabled,
        setValue = function(v)
            KIT.Cfg().enabled = v
            if v then
                KIT.Apply()
            else
                -- The header cached while it was on must not come back over the bare page.
                EllesmereUI:InvalidateContentHeaderCache()
            end
            Rebuild()
        end }
    -- Off, and in the search pre-build: the switch alone.
    if EllesmereUI._prebuilding or not KIT.Enabled() then
        _, h = W:DualRow(parent, y, enable, EllesmereUI.BlankRowCfg());  y = y - h
        return math.abs(y)
    end
    if not cur then cur = NewState(mode == "char") end
    Follow()
    pendingRebuild = nil      -- this build is the one a text edit asked for
    wipe(boxes)
    wipe(D)
    stanceV, stanceO = nil, nil   -- forms can be learned between builds
    EllesmereUI:SetContentHeader(HeaderBuilder)
    y = BuildMacroBody(parent, y, enable)
    WatchEvents(parent)       -- after the header: a re-show compares with what it painted
    return math.abs(y)
end
