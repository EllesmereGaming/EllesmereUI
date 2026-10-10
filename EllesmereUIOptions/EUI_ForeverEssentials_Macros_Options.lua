if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end -- Forever Essentials loads on WoW Forever only
-------------------------------------------------------------------------------
--  EUI_ForeverEssentials_Macros_Options.lua
--  Builds the "Macros" page inside the Forever Essentials module: the Macro
--  Manager, laid out like the Action Bars page. The content header holds a
--  centered dropdown (Account Macros / Character Macros / Bulk Macros) over
--  the macros (or, for Bulk Macros, the spells) shown centered as icons; the
--  page below holds the selection's settings, its lines and the macro text.
--  Storage and macro access live in EllesmereUIForeverEssentials_MacroManager.lua.
--
--  The page rebuilds (RefreshPage(true)) on structural edits; value edits
--  only refresh widgets in place. The icon grids are built once and
--  re-parented into each header: a macro list can hold 150 entries.
-------------------------------------------------------------------------------
if not EllesmereUI._ModuleNS["EllesmereUIForeverEssentials"] then return end  -- module disabled: no options page

local floor, max, min = math.floor, math.max, math.min
local PP         = EllesmereUI.PanelPP
local SolidTex   = EllesmereUI.SolidTex
local MakeFont   = EllesmereUI.MakeFont
local MakeBorder = EllesmereUI.MakeBorder

local function L(s) return EllesmereUI.L(s) end

local ICONS = "Interface\\AddOns\\EllesmereUI\\media\\icons\\"
local CELL = 46          -- icon grid step (42 icon + 4 gap)
local GRID_ROWS = 3      -- grid rows shown before it scrolls
local TEXT_H = 130       -- macro text block

local MM, B, S           -- Macro Manager, its builder and spellbook
local fontPath
local cur                -- the macro being edited (survives rebuilds)
local mode = "account"   -- account | char | bulk
local spellTab = "__all"
local edCtx = { headers = {} }
local bkCtx = { headers = {}, template = true }
local macroGrid, spellGrid = {}, {}
local D = {}             -- widgets of the page on screen
local UpdateBulk
local evf, pendingEvent, pendingRebuild, pendingSelect
local shown
local HeaderBuilder

local function Rebuild() EllesmereUI:RefreshPage(true) end
local function Resync() EllesmereUI:RefreshPage() end

local function Accent() return EllesmereUI.ELLESMERE_GREEN end

local function Note(msg)
    EllesmereUI.Print(EllesmereUI.COLOR_CODES.BRAND .. "EllesmereUI:|r " .. msg)
end

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

-- A scroll that hands the wheel to the page while it has nothing to scroll.
local function AttachScroll(scroll, child)
    local update = EllesmereUI.AttachSmoothScrollbar(scroll, {
        step = 60, thumbMin = 20, rightInset = 0, topInset = 2, level = 5,
        trackAlpha = 0.05, thumbAlpha = 0.22, child = child, panelWheel = true })
    local own = scroll:GetScript("OnMouseWheel")
    scroll:SetScript("OnMouseWheel", function(self, d)
        if child:GetHeight() - self:GetHeight() > 0 then return own(self, d) end
        local page = EllesmereUI._scrollFrame
        local fn = page and page:GetScript("OnMouseWheel")
        if fn then fn(page, d) end
    end)
    return update
end

local function PaintCounter(fs, n)
    fs:SetText(n .. " / " .. MM.MAX_BYTES)
    if n > MM.MAX_BYTES then
        fs:SetTextColor(1, 0.35, 0.35, 1)
    elseif n > MM.MAX_BYTES - 25 then
        local ac = Accent()
        fs:SetTextColor(ac.r, ac.g, ac.b, 1)
    else
        fs:SetTextColor(1, 1, 1, EllesmereUI.TEXT_DIM_A)
    end
end

-- Multi-line macro text box (input popup look). box.onChange(text, user),
-- box.onBlur(). A readOnly box keeps its text.
local function TextBox(parent, w, h, readOnly)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(w, h)
    SolidTex(box, "BACKGROUND", 0, 0, 0, 0.5):SetAllPoints()
    local brd = MakeBorder(box, 1, 1, 1, 0.2, PP)
    local sf = CreateFrame("ScrollFrame", nil, box)
    sf:SetPoint("TOPLEFT", 10, -8)
    sf:SetSize(w - 22, h - 16)
    sf:SetClipsChildren(true)
    local e = CreateFrame("EditBox", nil, sf)
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
        if readOnly and user then self:SetText(box.text or "") return end
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
    function box.SetText(_, t) box.text = t or ""; e:SetText(box.text) end
    return box
end

-- Info line, counter and text box as one block of the page.
local function TextBlock(parent, y, readOnly)
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
    local box = TextBox(f, w, TEXT_H - 30, readOnly)
    box:SetPoint("TOPLEFT", 0, -26)
    return box, count, info
end

-------------------------------------------------------------------------------
--  Spell suggestions under a text field (spellbook, plus "{spell}" in the
--  bulk template). list = true completes the last entry of a comma list.
-------------------------------------------------------------------------------
local suggest
local function HideSuggest()
    if suggest then suggest:Hide(); suggest.owner = nil end
end

local function AttachSuggest(box, onPick, template, list)
    local function Token()
        local t = box:GetText() or ""
        if list then t = t:match("([^,]*)$") or "" end
        return strtrim(t)
    end
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
        if not suggest then
            suggest = CreateFrame("Frame", nil, UIParent)
            suggest:SetFrameStrata("FULLSCREEN_DIALOG")
            suggest:SetClampedToScreen(true)
            SolidTex(suggest, "BACKGROUND", 0.067, 0.067, 0.067, 0.97):SetAllPoints()
            MakeBorder(suggest, 1, 1, 1, 0.18)
            suggest.rows = {}
            suggest:Hide()
        end
        local q = Token():lower()
        local items = {}
        if template and ("{spell}"):find(q, 1, true) then
            items[1] = { name = "{spell}", label = "{spell}  " .. EllesmereUI.L("(the spell of each macro)") }
        end
        for _, s in ipairs(S.Sorted()) do
            if q == "" or s.name:lower():find(q, 1, true) then
                items[#items + 1] = { name = s.name, label = s.name, icon = s.icon }
                if #items >= 10 then break end
            end
        end
        if #items == 0 or (#items == 1 and items[1].name:lower() == q) then HideSuggest() return end
        for i, it in ipairs(items) do
            local r = suggest.rows[i]
            if not r then
                r = CreateFrame("Button", nil, suggest)
                r:SetHeight(24)
                r.hl = SolidTex(r, "BACKGROUND", 1, 1, 1, 0)
                r.hl:SetAllPoints()
                r.icon = r:CreateTexture(nil, "ARTWORK")
                r.icon:SetSize(16, 16)
                r.icon:SetPoint("LEFT", 8, 0)
                r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                r.label = MakeFont(r, 12, nil, 1, 1, 1, 0.8)
                r.label:SetPoint("LEFT", 30, 0)
                r.label:SetPoint("RIGHT", -8, 0)
                r.label:SetJustifyH("LEFT")
                r.label:SetWordWrap(false)
                r:SetScript("OnEnter", function(self)
                    local ac = Accent()
                    self.hl:SetColorTexture(1, 1, 1, EllesmereUI.DD_ITEM_HL_A)
                    self.label:SetTextColor(ac.r, ac.g, ac.b, 1)
                end)
                r:SetScript("OnLeave", function(self)
                    self.hl:SetColorTexture(1, 1, 1, 0)
                    self.label:SetTextColor(1, 1, 1, 0.8)
                end)
                suggest.rows[i] = r
            end
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 1, -1 - (i - 1) * 24)
            r:SetPoint("RIGHT", suggest, "RIGHT", -1, 0)
            r.icon:SetTexture(it.icon or MM.QUESTION)
            r.label:SetText(it.label)
            -- Mouse down: picks before the field can lose focus.
            r:SetScript("OnMouseDown", function() Pick(it.name) end)
            r:Show()
        end
        for i = #items + 1, #suggest.rows do suggest.rows[i]:Hide() end
        suggest.first = items[1].name
        suggest.owner = box
        suggest:SetScale(box:GetEffectiveScale() / UIParent:GetEffectiveScale())
        suggest:SetSize(max(box:GetWidth(), 220), #items * 24 + 2)
        suggest:ClearAllPoints()
        suggest:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -2)
        suggest:Show()
    end
    box:HookScript("OnTextChanged", function(_, user) if user then Show() end end)
    box:HookScript("OnEditFocusGained", Show)
    box:HookScript("OnEditFocusLost", function() if suggest and suggest.owner == box then HideSuggest() end end)
    box:HookScript("OnTabPressed", function()
        if suggest and suggest.owner == box and suggest:IsShown() then Pick(suggest.first) end
    end)
end

-------------------------------------------------------------------------------
--  Icon picker (popup shell)
-------------------------------------------------------------------------------
local picker

local function IconList()
    local list, seen = { MM.QUESTION }, { [MM.QUESTION] = true }
    for _, s in ipairs(S.List()) do
        if s.icon and not seen[s.icon] then seen[s.icon] = true; list[#list + 1] = s.icon end
    end
    local pool = {}
    GetLooseMacroIcons(pool)
    GetLooseMacroItemIcons(pool)
    GetMacroIcons(pool)
    GetMacroItemIcons(pool)
    for _, icon in ipairs(pool) do
        if not seen[icon] then seen[icon] = true; list[#list + 1] = icon end
    end
    return list
end

local function OpenPicker(onPick)
    local COLS, ROWS, SIZE = 10, 6, 40
    if not picker then
        local p = {}
        local function Close() p.dimmer:Hide() end
        p.dimmer, p.popup = EllesmereUI.BuildPopupShell("EUIMacroIconPicker", {
            w = COLS * SIZE + 40, h = ROWS * SIZE + 132, bump = 1, onEscape = Close, onDimmerDown = Close,
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
            local b = CreateFrame("Button", nil, popup)
            b:SetSize(SIZE - 4, SIZE - 4)
            b:SetPoint("TOPLEFT", 20 + ((i - 1) % COLS) * SIZE, -70 - floor((i - 1) / COLS) * SIZE)
            b:SetFrameLevel(popup:GetFrameLevel() + 2)
            b.icon = b:CreateTexture(nil, "ARTWORK")
            b.icon:SetAllPoints()
            b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            b.brd = MakeBorder(b, 0, 0, 0, 0.6)
            b:SetScript("OnEnter", function(self) local ac = Accent() self.brd:SetColor(ac.r, ac.g, ac.b, 1) end)
            b:SetScript("OnLeave", function(self) self.brd:SetColor(0, 0, 0, 0.6) end)
            b:SetScript("OnClick", function(self)
                Close()
                if p.onPick then p.onPick(self.value) end
            end)
            p.buttons[i] = b
        end
        function p.Update()
            for i, b in ipairs(p.buttons) do
                local icon = p.list[p.offset + i]
                b.value = icon
                if icon then b.icon:SetTexture(IconPath(icon)); b:Show() else b:Hide() end
            end
        end
        popup:EnableMouseWheel(true)
        popup:SetScript("OnMouseWheel", function(_, d)
            local maxOff = max(0, math.ceil(#p.list / COLS) * COLS - COLS * ROWS)
            p.offset = min(maxOff, max(0, p.offset - d * COLS))
            p.Update()
        end)
        local cancel = EllesmereUI.MakePopupButton(popup, "BOTTOM", popup, "BOTTOM", 0, 18,
            1, 1, 1, 0.75, 1, 1, 1, 1, 1, 1, 1, 0.25, 1, 1, 1, 0.5)
        cancel._lbl:SetText(EllesmereUI.L("Cancel"))
        cancel:SetScript("OnClick", Close)
        picker = p
    end
    picker.list = IconList()
    picker.offset = 0
    picker.onPick = onPick
    picker.Update()
    picker.dimmer:Show()
end

-------------------------------------------------------------------------------
--  Dropdown value tables
-------------------------------------------------------------------------------
-- Line types in one flyout per group; onSelect(kind).
local function KindValues(onSelect)
    local values, order = { __pick = "Choose a type" }, {}
    for gi, g in ipairs(B.GROUPS) do
        local sv, so = {}, {}
        for _, key in ipairs(g.keys) do
            sv[key] = B.KIND[key].label
            so[#so + 1] = key
        end
        local gk = "group" .. gi
        values[gk] = { text = g.label, subnav = { values = sv, order = so, onSelect = onSelect } }
        order[#order + 1] = gk
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

-------------------------------------------------------------------------------
--  Line editor, shared by both views.
--  ctx: model, template, open (the expanded line), headers, onChange(structural, clean)
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

-- A line as one row: its code, then move, on/off and remove; a click opens it.
local function LineHeader(body, y, ctx, i, l)
    local W = EllesmereUI.Widgets
    local lines = ctx.model.lines
    local open = ctx.open == l
    local row, h = W:DualRow(body, y, { type = "label", text = LineCode(i, l) })
    local rgn = row._leftRegion
    local label = rgn._label
    label:SetFont(fontPath, 13, "")
    label:SetAlpha(l.on == false and 0.4 or 1)
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
    local tg, _, snap = EllesmereUI.BuildToggleControl(rgn, rgn:GetFrameLevel() + 6,
        function() return l.on ~= false end,
        function(v)
            l.on = v
            label:SetAlpha(v and 1 or 0.4)
            ctx.onChange(false)
        end)
    tg:SetPoint("RIGHT", del, "LEFT", -14, 0)
    snap()
    tg:HookScript("OnEnter", function(self)
        EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.L("Switched-off lines stay in the editor but are left out of the macro."))
    end)
    tg:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
    local function Move(d)
        local j = i + d
        lines[i], lines[j] = lines[j], lines[i]
        ctx.onChange(true)
    end
    local down = Glyph(rgn, 18, "eui-arrow-down3.png", function() Move(1) end, EllesmereUI.L("Move down"))
    down:SetPoint("RIGHT", tg, "LEFT", -14, 0)
    down:SetEnabled(i < #lines)
    local up = Glyph(rgn, 18, "eui-arrow-up3.png", function() Move(-1) end, EllesmereUI.L("Move up"))
    up:SetPoint("RIGHT", down, "LEFT", -2, 0)
    up:SetEnabled(i > 1)
    label:SetPoint("RIGHT", up, "LEFT", -12, 0)

    local hit = CreateFrame("Button", nil, row)
    hit:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    hit:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -150, 0)
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
local function PostCell(rgn, cfg, ctx)
    if not cfg or EllesmereUI._prebuilding then return end
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
        AttachSuggest(rgn._control, cfg.setValue, ctx.template, cfg._suggest == "list")
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
local function EmitCells(body, y, cells, ctx)
    local W = EllesmereUI.Widgets
    for i = 1, #cells, 2 do
        local a, b = cells[i], cells[i + 1]
        local row, h = W:DualRow(body, y, a, b or EllesmereUI.BlankRowCfg())
        PostCell(row._leftRegion, a, ctx)
        PostCell(row._rightRegion, b, ctx)
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
        getValue = get, setValue = set, _suggest = opts.suggest, _maxLetters = opts.maxLetters,
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
        local cv, co = ListValues(B.CHANNELS)
        Add(Dropdown("Channel", cv, co, function() return l.chan end, function(c) l.chan = c; Changed() end))
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
        v.conds, v.params = v.conds or {}, v.params or {}
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
            local tv, to = ListValues(B.TARGETS, "none")
            Add(Dropdown("Target", tv, to,
                function() return v.target ~= "" and v.target or "none" end,
                function(t) v.target = t == "none" and "" or t; Changed() end))
            local sv, so = ListValues(B.Stances(), "any")
            Add(Dropdown("Stance", sv, so,
                function() return v.stance ~= "" and v.stance or "any" end,
                function(s) v.stance = s == "any" and "" or s; Changed() end,
                "Numbers follow your stance bar; 0 = no stance or normal form."))
            -- Checking a condition with a value adds its value row: the page
            -- rebuilds once the menu closes.
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
    return EmitCells(body, y, cells, ctx)
end

local function BuildLines(body, y, ctx)
    local W = EllesmereUI.Widgets
    local _, h = W:SectionHeader(body, "LINES", y);  y = y - h
    local kv, ko = KindValues(function(k)
        local l = B.NewLine(k)
        if ctx.template and (k == "cast" or k == "use") then l.variants[1].arg = "{spell}" end
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
    return {
        index = nil, perChar = perChar and true or false,
        name = "", icon = MM.QUESTION,
        model = B.New(), text = "#showtooltip",
        dirty = false, nameTouched = false,
    }
end

local function StateOf(m)
    local s = NewState(m.perChar)
    s.index, s.name, s.text = m.index, m.name, m.body
    s.savedName, s.savedChar = m.name, m.perChar
    s.icon = MM.PickedIcon(m.index, m.icon)
    s.nameTouched = true
    local meta = MM.Meta(m.name, m.perChar)
    -- The stored model also keeps switched-off lines.
    if meta and meta.model and meta.body == m.body and B.Build(meta.model) == m.body then
        s.model = B.Substitute(meta.model)
    else
        s.model = B.Parse(m.body)
    end
    return s
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

local function Open(state)
    cur = state
    edCtx.open = nil
    Rebuild()
end

local function SetStatus(text, bad)
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
    if D.count then PaintCounter(D.count, #cur.text) end
end

local function Save()
    local name = strtrim(cur.name or "")
    if name == "" then name = MM.Truncate(B.FirstSpell(cur.model) or "", MM.MAX_NAME) end
    if name == "" then SetStatus(EllesmereUI.L("Please enter a name."), true) return end
    if #cur.text > MM.MAX_BYTES then
        SetStatus(EllesmereUI.Lf("Too long: %1$d / %2$d characters.", #cur.text, MM.MAX_BYTES), true)
        return
    end
    if strtrim(cur.text) == "" then SetStatus(EllesmereUI.L("The macro is empty."), true) return end
    local oldName, oldChar = cur.index and cur.savedName, cur.index and cur.savedChar
    local ok, err = MM.Save(cur.index, name, cur.icon, cur.text, cur.perChar)
    if not ok then
        SetStatus(EllesmereUI.L("Error:") .. " " .. tostring(err), true)
        return
    end
    if oldName and (oldName ~= name or oldChar ~= cur.perChar) then MM.SetMeta(oldName, oldChar, nil) end
    MM.SetMeta(name, cur.perChar, { model = B.Substitute(cur.model), body = cur.text })
    cur.name, cur.dirty = name, false
    cur.justSaved = true
    pendingSelect = { name = name, perChar = cur.perChar }
end

local function DeleteMacro(name, perChar)
    EllesmereUI:ShowConfirmPopup({
        title = EllesmereUI.L("Delete Macro"),
        message = EllesmereUI.Lf("Delete the macro \"%s\"?", name),
        confirmText = EllesmereUI.L("Delete"),
        cancelText = EllesmereUI.L("Cancel"),
        onConfirm = function()
            local m = not InCombatLockdown() and MM.Find(name, perChar)
            if not m then return end
            MM.Delete(m.index)
            MM.SetMeta(name, perChar, nil)
            if cur.index and cur.savedName == name and cur.savedChar == perChar then
                cur = NewState(perChar)
            end
        end,
    })
end

-- Account <-> character: the macro is created again in the other list.
local function MoveScope(name, fromChar)
    local toChar = not fromChar
    EllesmereUI:ShowConfirmPopup({
        title = EllesmereUI.L("Move Macro"),
        message = (toChar and EllesmereUI.Lf("Move \"%s\" to this character?", name)
            or EllesmereUI.Lf("Move \"%s\" to the account?", name))
            .. "\n" .. EllesmereUI.L("Action bar buttons with this macro have to be placed again."),
        confirmText = EllesmereUI.L("Move"),
        cancelText = EllesmereUI.L("Cancel"),
        onConfirm = function()
            local m = MM.Find(name, fromChar)
            if not m then return end
            local meta = MM.Meta(name, fromChar)
            local ok, err = MM.Save(m.index, name, MM.PickedIcon(m.index, m.icon), m.body, toChar)
            if not ok then Note(EllesmereUI.L("Error:") .. " " .. tostring(err)) return end
            MM.SetMeta(name, fromChar, nil)
            MM.SetMeta(name, toChar, meta and B.Substitute(meta))
            if cur.index and cur.savedName == name and cur.savedChar == fromChar then
                cur.perChar = toChar
                pendingSelect = { name = name, perChar = toChar }
            end
        end,
    })
end

-------------------------------------------------------------------------------
--  Icon grids in the content header, centered row by row like the action
--  bar preview. Cells are pooled; the grid re-parents into each header.
-------------------------------------------------------------------------------
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
        if self.tip then EllesmereUI.ShowWidgetTooltip(self, self.tip, { justify = "LEFT" }) end
    end)
    c:SetScript("OnLeave", function(self)
        self.Paint(false)
        EllesmereUI.HideWidgetTooltip()
    end)
    return c
end

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
    g.count, g.bind = count, bind
    g.frame:Show()
    g.update()
    return h
end

local function RebindGrid(g)
    for i = 1, g.count or 0 do g.bind(g.cells[i], i) end
end

local function BulkSettings() return MM.DB().bulk end
local function BulkSelected() return MM.CharDB().bulkSelected end
local function BulkName(spell) return MM.Truncate((BulkSettings().prefix or "") .. spell, MM.MAX_NAME) end

local function SelectedSpells()
    local out, sel = {}, BulkSelected()
    for _, s in ipairs(S.List()) do
        if sel[s.name] then out[#out + 1] = s end
    end
    return out
end

local function ShownSpells()
    local out = {}
    for _, s in ipairs(S.List()) do
        if spellTab == "__all" or s.tab == spellTab then out[#out + 1] = s end
    end
    return out
end

local function MacroMenu(anchor, m)
    EllesmereUI.ShowContextMenu(anchor, {
        { text = m.perChar and "Move to Account" or "Move to Character", onClick = function() MoveScope(m.name, m.perChar) end },
        { text = "Pick Up", onClick = function() if not InCombatLockdown() then PickupMacro(m.index) end end },
        "---",
        { text = "Delete", onClick = function() DeleteMacro(m.name, m.perChar) end },
    })
end

local function LayoutMacros(hdr, y, w)
    local perChar = mode == "char"
    local list = MM.List(perChar)
    local full = MM.Free(perChar) <= 0
    local count = #list + (full and 0 or 1)
    return LayoutGrid(macroGrid, hdr, y, w, count, function(c, i)
        local m = list[i]
        c.m = m
        c.icon:SetShown(m ~= nil)
        c.plus:SetShown(m == nil)
        c.name:SetText(m and m.name or "")
        c.icon:SetDesaturated(false)
        c.icon:SetAlpha(1)
        if m then
            c.icon:SetTexture(IconPath(m.icon))
            c.selected = cur.index == m.index
            c.tip = m.name .. "\n\n" .. m.body
        else
            c.selected = cur.index == nil and cur.perChar == perChar
            c.tip = EllesmereUI.L("New Macro")
        end
        c.Paint(false)
        c:SetScript("OnDragStart", function(self)
            if not self.m or InCombatLockdown() then return end
            EllesmereUI.HideWidgetTooltip()
            PickupMacro(self.m.index)
        end)
        c:SetScript("OnClick", function(self, btn)
            local mm = self.m
            if btn == "RightButton" then
                if mm then MacroMenu(self, mm) end
                return
            end
            if mm and cur.index == mm.index then return end
            if not mm and not cur.index and cur.perChar == perChar then return end
            Guard(function() Open(mm and StateOf(mm) or NewState(perChar)) end)
        end)
    end)
end

local function LayoutSpells(hdr, y, w)
    local list = ShownSpells()
    return LayoutGrid(spellGrid, hdr, y, w, #list, function(c, i)
        local s = list[i]
        local on = BulkSelected()[s.name] == true
        c.icon:Show()
        c.plus:Hide()
        c.name:SetText("")
        c.icon:SetTexture(s.icon)
        c.icon:SetDesaturated(not on)
        c.icon:SetAlpha(on and 1 or 0.45)
        c.selected = on
        c.tip = s.name .. "\n" .. (on and EllesmereUI.L("Picked. Click to remove.") or EllesmereUI.L("Click to pick."))
        c.Paint(false)
        c:SetScript("OnDragStart", nil)
        c:SetScript("OnClick", function(self)
            local sel = BulkSelected()
            sel[s.name] = not sel[s.name] or nil
            RebindGrid(spellGrid)
            self.Paint(true)
            if UpdateBulk then UpdateBulk() end
        end)
    end)
end

-- Centered list dropdown over the centered icons (the Action Bars header).
HeaderBuilder = function(hdr, hdrW)
    local pad = EllesmereUI.CONTENT_PAD
    local fy = -20
    local DD_H = 34
    local a, c = MM.Counts()
    local values = {
        _noLoc = true,
        account = EllesmereUI.L("Account Macros") .. "  (" .. a .. "/" .. MM.MAX_ACCOUNT .. ")",
        char = EllesmereUI.L("Character Macros") .. "  (" .. c .. "/" .. MM.MAX_CHAR .. ")",
        bulk = EllesmereUI.L("Bulk Macros"),
    }
    local dd = EllesmereUI.BuildDropdownControl(hdr, 350, hdr:GetFrameLevel() + 5, values,
        { "account", "char", "bulk" },
        function() return mode end,
        function(v)
            if v == mode then return end
            mode = v
            -- Changing lists starts a new macro unless one is being edited.
            if v ~= "bulk" and not cur.dirty and cur.perChar ~= (v == "char") then cur = NewState(v == "char") end
            edCtx.open, bkCtx.open = nil, nil
            EllesmereUI:InvalidateContentHeaderCache()
            Rebuild()
        end)
    PP.Point(dd, "TOP", hdr, "TOP", 0, fy)
    dd:SetHeight(DD_H)
    fy = fy - DD_H - 12
    if macroGrid.frame then macroGrid.frame:Hide() end
    if spellGrid.frame then spellGrid.frame:Hide() end
    local gh
    if mode == "bulk" then gh = LayoutSpells(hdr, fy, hdrW - pad * 2)
    else gh = LayoutMacros(hdr, fy, hdrW - pad * 2) end
    fy = fy - gh - 14
    return math.abs(fy)
end
_G._EUI_MacrosHeaderBuilder = HeaderBuilder

-------------------------------------------------------------------------------
--  Events: while the page is shown
-------------------------------------------------------------------------------
local function OnMacrosChanged()
    if cur then
        local key = pendingSelect or (cur.index and { name = cur.savedName or cur.name, perChar = cur.savedChar })
        if key then
            local m = MM.Find(key.name, key.perChar)
            cur.index = m and m.index or nil
            if cur.index then cur.perChar = key.perChar end
        end
        -- A saved or moved macro shows in its list.
        if pendingSelect and cur.index and mode ~= "bulk" then mode = cur.perChar and "char" or "account" end
        pendingSelect = nil
        if cur.index then cur.savedName, cur.savedChar = cur.name, cur.perChar end
    end
    Rebuild()
end

local function OnEvent(_, event)
    if event == "GLOBAL_MOUSE_UP" then
        evf:UnregisterEvent("GLOBAL_MOUSE_UP")
        -- Next frame: after the click that ended the text edit has landed.
        C_Timer.After(0, function()
            if pendingRebuild then pendingRebuild = nil; Rebuild() end
        end)
        return
    end
    if event == "SPELLS_CHANGED" then
        local before = #S.List()
        S.Invalidate()
        if mode ~= "bulk" or #S.List() == before then return end
    end
    -- Bursts (one UPDATE_MACROS per macro of a bulk run) settle in one rebuild.
    if pendingEvent then return end
    pendingEvent = true
    C_Timer.After(0, function()
        pendingEvent = nil
        if shown then OnMacrosChanged() end
    end)
end

-- After typing in the macro text: rebuild the lines once the click is done.
local function RebuildAfterClick()
    if IsMouseButtonDown() then
        pendingRebuild = true
        evf:RegisterEvent("GLOBAL_MOUSE_UP")
    else
        Rebuild()
    end
end

local function WatchEvents(parent)
    if not evf then
        evf = CreateFrame("Frame")
        evf:SetScript("OnEvent", OnEvent)
    end
    local host = CreateFrame("Frame", nil, parent)
    host:SetSize(1, 1)
    host:SetPoint("TOPLEFT")
    host:SetScript("OnShow", function()
        shown = true
        evf:RegisterEvent("UPDATE_MACROS")
        evf:RegisterEvent("SPELLS_CHANGED")
    end)
    host:SetScript("OnHide", function()
        shown = nil
        evf:UnregisterAllEvents()
        pendingRebuild = nil
        HideSuggest()
        if picker then picker.dimmer:Hide() end
    end)
    host:GetScript("OnShow")()
end

-------------------------------------------------------------------------------
--  Page bodies
-------------------------------------------------------------------------------
local function BuildMacroBody(parent, y)
    local W = EllesmereUI.Widgets
    local _, h
    if not cur then cur = NewState(mode == "char") end

    local function Dirty()
        cur.dirty = true
        SetStatus(EllesmereUI.L("Unsaved changes"))
    end
    edCtx.model = cur.model
    edCtx.template = false
    edCtx.onChange = function(structural, clean)
        if not clean then
            Dirty()
            if not cur.nameTouched and not cur.index then
                cur.name = MM.Truncate(B.FirstSpell(cur.model) or "", MM.MAX_NAME)
            end
        end
        UpdateMacroText()
        if structural then Rebuild() return end
        UpdateHeaders(edCtx)
        Resync()
    end

    _, h = W:SectionHeader(parent, "MACRO", y);  y = y - h
    y = EmitCells(parent, y, {
        Input("Name", function() return cur.name end, function(t)
            t = MM.Truncate(strtrim(t or ""), MM.MAX_NAME)
            if t == cur.name then return end
            cur.name, cur.nameTouched = t, true
            Dirty()
        end, { width = 170, ph = "Max. 16 characters", maxLetters = MM.MAX_NAME }),
        Dropdown("Saved For", { account = "Account", char = "Character" }, { "account", "char" },
            function() return cur.perChar and "char" or "account" end,
            function(v) cur.perChar = v == "char"; Dirty() end,
            "Account macros exist on all your characters, character macros only on this one."),
        { type = "labeledButton", text = "Icon", buttonText = "Choose Icon", width = 130,
          onClick = function()
              OpenPicker(function(icon)
                  cur.icon = icon or MM.QUESTION
                  Dirty()
                  Resync()
              end)
          end,
          _icon = function() return cur.icon end },
        { type = "toggle", text = "Show Spell Tooltip", tooltip = "#showtooltip: the button shows the spell's icon and tooltip.",
          getValue = function() return cur.model.tooltip end,
          setValue = function(v) cur.model.tooltip = v; edCtx.onChange(false) end },
        Input("Tooltip Spell", function() return cur.model.tooltipSpell end,
            function(t) cur.model.tooltipSpell = t; edCtx.onChange(false) end,
            { ph = "Empty = automatic", suggest = true,
              disabled = function() return not cur.model.tooltip end, disabledTooltip = "Show Spell Tooltip" }),
    }, edCtx)

    _, h = W:Spacer(parent, y, 20);  y = y - h
    y = BuildLines(parent, y, edCtx)

    _, h = W:Spacer(parent, y, 20);  y = y - h
    _, h = W:SectionHeader(parent, "MACRO TEXT", y);  y = y - h
    local box, count, info = TextBlock(parent, y, false)
    y = y - TEXT_H
    D.text, D.count, D.info = box, count, info
    box:SetText(cur.text)
    PaintCounter(count, #cur.text)
    if cur.justSaved then
        cur.justSaved = nil
        SetStatus(EllesmereUI.L("Saved."))
    elseif cur.dirty then
        SetStatus(EllesmereUI.L("Unsaved changes"))
    end
    local textEdited
    box.onChange = function(text, user)
        if not user then return end
        cur.text = text
        cur.model = B.Parse(text)
        textEdited = true
        Dirty()
        PaintCounter(count, #text)
    end
    box.onBlur = function()
        if not textEdited then return end
        textEdited = false
        edCtx.open = nil
        RebuildAfterClick()
    end

    local notSaved = { disabled = true, tooltip = EllesmereUI.L("Save the macro first.") }
    _, h = W:WideTripleButton(parent, "Save", "Pick Up", "Delete", y,
        Save,
        function() if cur.index and not InCombatLockdown() then PickupMacro(cur.index) end end,
        function() if cur.index then DeleteMacro(cur.savedName or cur.name, cur.savedChar) end end,
        nil, cur.index == nil and { [2] = notSaved, [3] = notSaved } or nil);  y = y - h
    return y
end

local function BulkModel()
    local cdb = MM.CharDB()
    local model = cdb.bulkModel
    if not (model and model.lines) then
        model = B.New()
        model.lines[1] = B.NewLine("cast", "{spell}")
        cdb.bulkModel = model
    end
    return model
end

local function RunBulk()
    if MM.Blocked() then return end
    local st, model = BulkSettings(), BulkModel()
    local perChar = st.perChar and true or false
    local created, updated, skipped, failed = 0, 0, 0, 0
    for _, s in ipairs(SelectedSpells()) do
        local name = BulkName(s.name)
        local body = B.Build(model, s.name)
        local icon = st.spellIcon and s.icon or MM.QUESTION
        local ex = MM.Find(name, perChar)
        if #body > MM.MAX_BYTES then
            failed = failed + 1
        elseif ex and not st.overwrite then
            skipped = skipped + 1
        elseif MM.Save(ex and ex.index, name, icon, body, perChar) then
            if ex then updated = updated + 1 else created = created + 1 end
            MM.SetMeta(name, perChar, { model = B.Substitute(model, s.name), body = body })
        else
            failed = failed + 1
        end
    end
    local msg = EllesmereUI.Lf("Macros: %1$d created, %2$d updated, %3$d skipped.", created, updated, skipped)
    if failed > 0 then
        msg = msg .. " |cffff5959" .. EllesmereUI.Lf("%d failed (too long or no free slot).", failed) .. "|r"
    end
    Note(msg)
end

local function BuildBulkBody(parent, y)
    local W = EllesmereUI.Widgets
    local _, h
    local model = BulkModel()

    bkCtx.model = model
    bkCtx.onChange = function(structural)
        if structural then Rebuild() return end
        UpdateBulk()
        UpdateHeaders(bkCtx)
        Resync()
    end

    local function Relayout()
        EllesmereUI:InvalidateContentHeaderCache()
        EllesmereUI:SetContentHeader(HeaderBuilder)
    end

    _, h = W:SectionHeader(parent, "SETTINGS", y);  y = y - h
    local tabValues, tabOrder = { _noLoc = true, __all = L("All Spells") }, { "__all" }
    for _, s in ipairs(S.List()) do
        local tab = s.tab or "?"
        if not tabValues[tab] then tabValues[tab] = tab; tabOrder[#tabOrder + 1] = tab end
    end
    if not tabValues[spellTab] then spellTab = "__all" end
    y = EmitCells(parent, y, {
        Dropdown("Spellbook Tab", tabValues, tabOrder, function() return spellTab end,
            function(v) spellTab = v; Relayout() end, "Which spells the icons above show."),
        Input("Name Prefix", function() return BulkSettings().prefix end,
            function(t) BulkSettings().prefix = t; UpdateBulk() end,
            { width = 120, ph = "e.g. SA ", maxLetters = 8,
              tip = "Put in front of every macro name (macro names hold 16 characters)." }),
        Dropdown("Save As", { account = "Account", char = "Character" }, { "account", "char" },
            function() return BulkSettings().perChar and "char" or "account" end,
            function(v) BulkSettings().perChar = v == "char"; UpdateBulk() end),
        { type = "toggle", text = "Update Existing Macros", tooltip = "Macros with the same name are updated instead of skipped.",
          getValue = function() return BulkSettings().overwrite end,
          setValue = function(v) BulkSettings().overwrite = v; UpdateBulk() end },
        { type = "toggle", text = "Use the Spell's Icon",
          tooltip = "Off: the question mark icon follows the spell via #showtooltip. On: the spell's icon is saved for good.",
          getValue = function() return BulkSettings().spellIcon end,
          setValue = function(v) BulkSettings().spellIcon = v end },
    }, bkCtx)
    _, h = W:WideDualButton(parent, "Pick All Shown", "Clear Picks", y,
        function()
            for _, s in ipairs(ShownSpells()) do BulkSelected()[s.name] = true end
            RebindGrid(spellGrid)
            UpdateBulk()
        end,
        function()
            wipe(BulkSelected())
            RebindGrid(spellGrid)
            UpdateBulk()
        end);  y = y - h

    _, h = W:Spacer(parent, y, 20);  y = y - h
    y = BuildLines(parent, y, bkCtx)

    _, h = W:Spacer(parent, y, 20);  y = y - h
    _, h = W:SectionHeader(parent, "PREVIEW", y);  y = y - h
    local box, count, info = TextBlock(parent, y, true)
    y = y - TEXT_H
    _, h = W:WideButton(parent, "Create Macros", y, RunBulk);  y = y - h

    UpdateBulk = function()
        local spells = SelectedSpells()
        local s = spells[1]
        local text = B.Build(model, s and s.name or EllesmereUI.L("Spell name"))
        box:SetText(text)
        PaintCounter(count, #text)
        local st = BulkSettings()
        local existing = {}
        for _, m in ipairs(MM.List(st.perChar)) do existing[m.name] = true end
        local new, upd, skip = 0, 0, 0
        for _, sp in ipairs(spells) do
            if existing[BulkName(sp.name)] then
                if st.overwrite then upd = upd + 1 else skip = skip + 1 end
            else
                new = new + 1
            end
        end
        local free = MM.Free(st.perChar)
        local txt = EllesmereUI.Lf("%1$d picked: %2$d new, %3$d updated, %4$d skipped. Free macro slots: %5$d",
            #spells, new, upd, skip, free)
        if new > free then txt = txt .. "  |cffff5959" .. EllesmereUI.Lf("(%d won't fit)", new - free) .. "|r" end
        if s then txt = txt .. "  " .. EllesmereUI.Lf("Preview for %s.", s.name) end
        info:SetText(txt)
    end
    UpdateBulk()
    return y
end

-------------------------------------------------------------------------------
--  Page entry point
-------------------------------------------------------------------------------
local function Prepare()
    MM = EllesmereUI._MacroManager
    if not MM then return false end
    B, S = MM.Builder, MM.Builder.Spells
    fontPath = EllesmereUI.GetFontPath("essentials") or EllesmereUI.EXPRESSWAY
    return true
end

_G._EUI_BuildForeverMacrosPage = function(pageName, parent, yOffset)
    if EllesmereUI._prebuilding or not Prepare() then return 0 end
    if not MM.Enabled() then
        local sf = EllesmereUI._scrollFrame
        local height = floor((sf and sf:GetHeight() or 680) - 36)
        local cover = CreateFrame("Frame", nil, parent)
        cover:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset + 6)
        cover:SetSize(parent:GetWidth(), height)
        local _, btn = EllesmereUI.BuildActivationOverlay(cover, {
            fontPath = fontPath, width = parent:GetWidth(),
            title = EllesmereUI.L("Macro Manager"),
            text = EllesmereUI.L("Build macros by click: a line editor with every option, live macro text and bulk creation for many spells at once."),
            buttonLabel = EllesmereUI.L("Enable Macro Manager"),
        })
        btn:SetScript("OnClick", function()
            MM.Cfg().enabled = true
            MM.Apply()
            EllesmereUI:InvalidateModulePageCache("EllesmereUIForeverEssentials")
            Rebuild()
        end)
        return height
    end

    if not cur then cur = NewState(mode == "char") end
    wipe(D)
    UpdateBulk = nil
    WatchEvents(parent)
    parent._showRowDivider = true
    EllesmereUI:SetContentHeader(HeaderBuilder)

    local y
    if mode == "bulk" then y = BuildBulkBody(parent, yOffset) else y = BuildMacroBody(parent, yOffset) end
    return math.abs(y)
end
