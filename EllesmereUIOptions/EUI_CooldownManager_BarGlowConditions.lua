if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_CooldownManager_BarGlowConditions.lua
--  Bar Glows page rows for the per-glow conditions (runtime:
--  EllesmereUICdmBarGlowConditions.lua). A glow entry on the page reads:
--
--    When (icon) Fingers of Frost is [Active v]  | And [(icon) Brain Freeze v] is [Missing v]  [toggle]
--    At Stacks      (gear) [toggle]              | Glow Type       [Pixel Glow v]
--    Only In Combat [toggle]                     | Hero Talent     [Any v]
--    Glow Color     ...                          | (icon) [Duplicate] [Remove]
--
--  Left of row 1 is the glow's own Glow When (entry.mode). The And toggle is
--  entry.andMode = "and" | nil (its buff and state grey out while off); the
--  second buff and its state are entry.conditions[1]. Each glow starts with a
--  collapse bar (collapsed: buff icon + name only, entry.collapsed); Duplicate
--  inserts a full copy right below.
--  Frames are built with the page; nothing exists until it is opened.
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUICooldownManager"]
if not ns then return end

local function Cond(entry)
    if type(entry.conditions) ~= "table" then entry.conditions = {} end
    if type(entry.conditions[1]) ~= "table" then entry.conditions[1] = {} end
    return entry.conditions[1]
end

local function SpellLabel(sid)
    sid = tonumber(sid)
    if not sid or sid <= 0 then return EllesmereUI.L("Choose Buff"), nil end
    local info = C_Spell.GetSpellInfo(sid)
    return (info and info.name) or ("Spell " .. sid), info and info.iconID
end

-- A spell icon that shows the spell's tooltip on hover.
function ns.BarGlowSpellIcon(parent, size, spellID)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    f:SetFrameLevel(parent:GetFrameLevel() + 3)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints()
    f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local sid = tonumber(spellID)
    local info = sid and sid > 0 and C_Spell.GetSpellInfo(sid)
    if info and info.iconID then f.tex:SetTexture(info.iconID) end
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self)
        if not (sid and sid > 0) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(sid)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return f
end

-------------------------------------------------------------------------------
--  Bar Glows buff menu, shared by the add-glow picker (several buffs, stays
--  open) and the glow's When / And pickers (one buff): tracked buffs, then
--  untracked, then tracked bars. ONE menu frame and a row pool, reused by every
--  open (none is built until the first open).
--    opts.isChecked(spellID) -> bool    box state of a row
--    opts.onClick(sp, refreshChecks)    a row click: call refreshChecks() to
--                                       repaint the boxes, or hide the menu
--    opts.emptyText                     shown when nothing is listed (nil: the
--                                       menu does not open then)
--  Returns the menu frame, or nil when it did not open.
-------------------------------------------------------------------------------
local MENU_W, ITEM_H, MAX_H = 240, 26, 300
local menu, scroll, inner, emptyText, menuOpts, menuAnchor
local rows, divs = {}, {}

local function RefreshChecks()
    local opts = menuOpts
    if not opts then return end
    local ACCENT = EllesmereUI.ELLESMERE_GREEN
    for i = 1, #rows do
        local r = rows[i]
        if r:IsShown() then
            if opts.isChecked(r.sp.spellID) then
                r.fill:Show()
                r.brd:SetColor(ACCENT.r, ACCENT.g, ACCENT.b, 0.8)
            else
                r.fill:Hide()
                r.brd:SetColor(0.224, 0.215, 0.207, 0.6)
            end
        end
    end
end

local function BuildMenu()
    menu = CreateFrame("Frame", nil, UIParent)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(300)
    menu:SetClampedToScreen(true)
    menu:SetSize(MENU_W, 10)
    menu:Hide()
    local bg = menu:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_HA)
    EllesmereUI.MakeBorder(menu, 1, 1, 1, EllesmereUI.DD_BRD_A, EllesmereUI.PP)

    scroll = CreateFrame("ScrollFrame", nil, menu)
    scroll:SetPoint("TOPLEFT")
    scroll:SetPoint("BOTTOMRIGHT")
    scroll:SetFrameLevel(menu:GetFrameLevel() + 1)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = menu._maxScroll or 0
        if maxScroll <= 0 then return end
        self:SetVerticalScroll(math.max(0, math.min(maxScroll, self:GetVerticalScroll() - delta * 30)))
    end)
    inner = CreateFrame("Frame", nil, scroll)
    inner:SetWidth(MENU_W)
    scroll:SetScrollChild(inner)

    emptyText = inner:CreateFontString(nil, "OVERLAY")
    emptyText:SetPoint("TOPLEFT", inner, "TOPLEFT", 10, -8)

    -- Closing: a click outside the menu and its anchor, or the options panel hiding.
    menu:SetScript("OnUpdate", function(m)
        if IsMouseButtonDown("LeftButton") and not m:IsMouseOver()
            and not (menuAnchor and menuAnchor:IsMouseOver()) then
            m:Hide()
        end
    end)
    menu:SetScript("OnHide", function() menuOpts, menuAnchor = nil, nil end)
    EllesmereUI:RegisterOnHide(function() menu:Hide() end)
end

local function Row(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, inner)
    r:SetHeight(ITEM_H)
    r:SetFrameLevel(menu:GetFrameLevel() + 2)
    local cb = CreateFrame("Frame", nil, r)
    cb:SetSize(14, 14)
    cb:SetPoint("LEFT", r, "LEFT", 8, 0)
    cb:SetFrameLevel(r:GetFrameLevel() + 1)
    local cbBg = cb:CreateTexture(nil, "BACKGROUND")
    cbBg:SetAllPoints()
    cbBg:SetColorTexture(0.114, 0.106, 0.099, 1)
    r.brd = EllesmereUI.MakeBorder(cb, 0.224, 0.215, 0.207, 0.6, EllesmereUI.PanelPP)
    local ACCENT = EllesmereUI.ELLESMERE_GREEN
    r.fill = cb:CreateTexture(nil, "ARTWORK")
    r.fill:SetSnapToPixelGrid(false)
    r.fill:SetTexelSnappingBias(0)
    r.fill:SetPoint("TOPLEFT", cb, "TOPLEFT", 3, -3)
    r.fill:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", -3, 3)
    r.fill:SetColorTexture(ACCENT.r, ACCENT.g, ACCENT.b, 1)
    r.ico = r:CreateTexture(nil, "ARTWORK")
    r.ico:SetSize(ITEM_H - 4, ITEM_H - 4)
    r.ico:SetPoint("RIGHT", r, "RIGHT", -6, 0)
    r.ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.lbl = r:CreateFontString(nil, "OVERLAY")
    r.lbl:SetPoint("LEFT", cb, "RIGHT", 6, 0)
    r.lbl:SetPoint("RIGHT", r.ico, "LEFT", -4, 0)
    r.lbl:SetJustifyH("LEFT")
    r.lbl:SetWordWrap(false)
    r.lbl:SetMaxLines(1)
    local hl = r:CreateTexture(nil, "ARTWORK", nil, -1)
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0)
    r:SetScript("OnEnter", function()
        r.lbl:SetTextColor(1, 1, 1, 1)
        hl:SetColorTexture(1, 1, 1, EllesmereUI.DD_ITEM_HL_A)
    end)
    r:SetScript("OnLeave", function()
        r.lbl:SetTextColor(EllesmereUI.TEXT_DIM_R, EllesmereUI.TEXT_DIM_G, EllesmereUI.TEXT_DIM_B, EllesmereUI.TEXT_DIM_A)
        hl:SetColorTexture(1, 1, 1, 0)
    end)
    r:SetScript("OnClick", function(self)
        local opts = menuOpts
        if opts then opts.onClick(self.sp, RefreshChecks) end
    end)
    rows[i] = r
    return r
end

function ns.ShowBarGlowBuffMenu(anchor, opts)
    if menu then menu:Hide() end
    local tracked, untracked = {}, {}
    if ns.GetAllCDMBuffSpells then tracked, untracked = ns.GetAllCDMBuffSpells() end
    tracked, untracked = tracked or {}, untracked or {}
    local bars = ns.GetTrackedBarSpells and ns.GetTrackedBarSpells() or {}
    if #tracked == 0 and #untracked == 0 and #bars == 0 and not opts.emptyText then return nil end
    if not menu then BuildMenu() end
    menuOpts, menuAnchor = opts, anchor
    menu._btnIdx = nil

    local env = ns._CDMO_OptEnv or {}
    local font = env.FONT_PATH or STANDARD_TEXT_FONT
    local outline = env.GetCDMOptOutline and env.GetCDMOptOutline() or ""
    local n, nd, mH = 0, 0, 4
    local function Add(sp)
        local sid = tonumber(sp.spellID)
        if not sid or sid <= 0 then return end
        n = n + 1
        local r = Row(n)
        r.sp = sp
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
        r:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
        local name, icon = sp.name, sp.icon
        if not (name and icon) then
            local spellName, spellIcon = SpellLabel(sid)
            name, icon = name or spellName, icon or spellIcon
        end
        r.ico:SetTexture(icon)
        r.lbl:SetFont(font, 11, outline)
        r.lbl:SetText(EllesmereUI.L(name))
        r.lbl:SetTextColor(EllesmereUI.TEXT_DIM_R, EllesmereUI.TEXT_DIM_G, EllesmereUI.TEXT_DIM_B, EllesmereUI.TEXT_DIM_A)
        r:Show()
        mH = mH + ITEM_H
    end
    local function Divider()
        nd = nd + 1
        local d = divs[nd]
        if not d then
            d = inner:CreateTexture(nil, "ARTWORK")
            d:SetHeight(1)
            d:SetColorTexture(1, 1, 1, 0.10)
            divs[nd] = d
        end
        d:ClearAllPoints()
        d:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
        d:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
        d:Show()
        mH = mH + 9
    end

    for _, sp in ipairs(tracked) do Add(sp) end
    if #tracked > 0 and #untracked > 0 then Divider() end
    for _, sp in ipairs(untracked) do Add(sp) end
    if #bars > 0 then
        if #tracked > 0 or #untracked > 0 then Divider() end
        for _, sp in ipairs(bars) do Add(sp) end
    end
    for i = n + 1, #rows do rows[i]:Hide() end
    for i = nd + 1, #divs do divs[i]:Hide() end
    if n == 0 then
        emptyText:SetFont(font, 11, outline)
        emptyText:SetTextColor(EllesmereUI.TEXT_DIM_R, EllesmereUI.TEXT_DIM_G, EllesmereUI.TEXT_DIM_B, EllesmereUI.TEXT_DIM_A)
        emptyText:SetText(EllesmereUI.L(opts.emptyText))
        emptyText:Show()
        mH = 30
    else
        emptyText:Hide()
    end
    RefreshChecks()

    local totalH = mH + 4
    inner:SetHeight(totalH)
    menu:SetHeight(math.min(totalH, MAX_H))
    menu._maxScroll = totalH - MAX_H
    scroll:SetVerticalScroll(0)
    menu:ClearAllPoints()
    menu:SetPoint("TOP", anchor, "BOTTOM", 0, -2)
    menu:Show()
    return menu
end

-- Single choice for the When / And rows: closes on a pick.
local function ShowPicker(anchor, currentSid, onPick)
    local cur = tonumber(currentSid)
    ns.ShowBarGlowBuffMenu(anchor, {
        emptyText = "No Cooldown Manager buffs to choose from.",
        isChecked = function(sid) return tonumber(sid) == cur end,
        onClick = function(sp)
            menu:Hide()
            onPick(tonumber(sp.spellID))
        end,
    })
end

-- Active / Missing: the glow's own state (entry.mode) and the And buff's
-- (c.state = "missing" | nil), both standard option dropdowns.
local STATE_VALUES = { ACTIVE = "Active", MISSING = "Missing" }
local STATE_ORDER = { "ACTIVE", "MISSING" }

-- Row 1 of a glow, two columns:
--   left:  When Fingers of Frost Is                               [Active v]
--   right: And [(icon) Brain Freeze v] is [Missing v]                [toggle]
-- The left column is a standard dropdown row (the glow's own Glow When); the
-- right is a standard toggle row labelled "And"; while it is off the buff
-- picker and its state grey out. Returns the new y.
function ns.BuildBarGlowWhenRow(W, parent, y, entry, onChange)
    local c = Cond(entry)
    local Paint  -- forward: the toggle repaints the right column
    local sid = tonumber(entry.spellID) or 0
    local ownName = (sid > 0) and SpellLabel(sid) or "buff"

    local row, h = W:DualRow(parent, y,
        { type = "dropdown", text = EllesmereUI.Lf("When %1$s Is", ownName),
          values = STATE_VALUES, order = STATE_ORDER,
          getValue = function() return entry.mode == "MISSING" and "MISSING" or "ACTIVE" end,
          setValue = function(v)
              entry.mode = v
              if onChange then onChange() end
              EllesmereUI:RefreshPage()
          end },
        { type = "toggle", text = "And",
          tooltip = "Also require a second buff to be active (or missing) for this glow. For an \"or\", add another glow to the same button.",
          getValue = function() return entry.andMode == "and" end,
          setValue = function(v)
              entry.andMode = v and "and" or nil
              if Paint then Paint() end
              if onChange then onChange() end
          end })
    y = y - h
    if EllesmereUI._prebuilding then return y end

    local left, right = row._leftRegion, row._rightRegion
    local lRef = left and left._label
    local rRef = right and right._label
    local font, size = STANDARD_TEXT_FONT, 13
    if lRef and lRef.GetFont then
        local f, s = lRef:GetFont()
        if f then font, size = f, s or size end
    end
    local r, g, b = 1, 1, 1
    if lRef and lRef.GetTextColor then r, g, b = lRef:GetTextColor() end
    local CTL_H = 30   -- the options dropdown height (Glow Type)
    local function Word(host, text)
        local fs = host:CreateFontString(nil, "OVERLAY")
        fs:SetFont(font, size, "")
        fs:SetTextColor(r, g, b, 1)
        fs:SetText(text)
        return fs
    end

    -- Right column: after the "And" label, before the toggle -----------------
    local rx = CreateFrame("Frame", nil, right or row)
    rx:SetAllPoints()
    rx:SetFrameLevel((right or row):GetFrameLevel() + 2)
    -- The And buff: a standard dropdown face whose click opens the shared buff
    -- menu (Paint writes its label and icon).
    local buffBtn, buffLbl = EllesmereUI.BuildDropdownControl(rx, 170, rx:GetFrameLevel() + 3,
        { _ = "", _noLoc = true }, { "_" }, function() return "_" end, function() end)
    buffBtn.icon = buffBtn:CreateTexture(nil, "ARTWORK")
    buffBtn.icon:SetSize(CTL_H - 6, CTL_H - 6)
    buffBtn.icon:SetPoint("LEFT", buffBtn, "LEFT", 3, 0)
    buffBtn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if rRef then
        buffBtn:SetPoint("LEFT", rRef, "RIGHT", 10, 0)
    else
        buffBtn:SetPoint("LEFT", rx, "LEFT", 60, 0)
    end
    local isWord = Word(rx, EllesmereUI.L("is"))
    isWord:SetPoint("LEFT", buffBtn, "RIGHT", 8, 0)
    local stateDrop = EllesmereUI.BuildDropdownControl(rx, 96, rx:GetFrameLevel() + 3,
        STATE_VALUES, STATE_ORDER,
        function() return c.state == "missing" and "MISSING" or "ACTIVE" end,
        function(v)
            c.state = (v == "MISSING") and "missing" or nil
            Paint()
            if onChange then onChange() end
        end)
    stateDrop:SetPoint("LEFT", isWord, "RIGHT", 8, 0)

    Paint = function()
        local name, icon = SpellLabel(c.spellID)
        buffLbl:SetText(name)
        -- Only the label's LEFT point moves; its RIGHT stays on the arrow.
        if icon then
            buffBtn.icon:SetTexture(icon)
            buffBtn.icon:Show()
            buffLbl:SetPoint("LEFT", buffBtn.icon, "RIGHT", 6, 0)
        else
            buffBtn.icon:Hide()
            buffLbl:SetPoint("LEFT", buffBtn, "LEFT", 12, 0)
        end
        stateDrop._refreshLabel()
        local on = entry.andMode == "and"
        for _, part in ipairs({ buffBtn, isWord, stateDrop }) do
            part:SetAlpha(on and 1 or 0.3)
            if part.EnableMouse then part:EnableMouse(on) end
        end
        -- The "And" label greys with them (the switch itself stays live).
        if rRef then rRef:SetAlpha(on and 1 or 0.3) end
    end

    buffBtn:SetScript("OnClick", function(self)
        ShowPicker(self, c.spellID, function(sid)
            c.spellID = sid
            Paint()
            if onChange then onChange() end
        end)
    end)
    Paint()
    return y
end

-- The Only In Combat toggle's row config.
function ns.BarGlowCombatCfg(entry, onChange)
    return { type = "toggle", text = "Only In Combat",
        getValue = function() return entry.onlyInCombat == true end,
        setValue = function(v)
            entry.onlyInCombat = v or nil
            if onChange then onChange() end
        end }
end

-- Only In Combat | Hero Talent (the current spec's hero trees; glows are
-- saved per spec). Retail only: WoW Forever has no hero talents, so the page
-- pairs Only In Combat with Glow Color there instead. Returns the new y.
function ns.BuildBarGlowCombatRow(W, parent, y, entry, onChange)
    local combatCfg = ns.BarGlowCombatCfg(entry, onChange)
    local heroValues, heroOrder = { any = EllesmereUI.L("Any") }, { "any" }
    for _, t in ipairs(ns.BarGlowHeroTrees and ns.BarGlowHeroTrees() or {}) do
        local key = tostring(t.id)
        heroValues[key] = t.name
        heroOrder[#heroOrder + 1] = key
    end
    local cur = tonumber(entry.heroTree)
    if cur and not heroValues[tostring(cur)] then
        heroValues[tostring(cur)] = "Hero Tree " .. cur
        heroOrder[#heroOrder + 1] = tostring(cur)
    end
    local _, h = W:DualRow(parent, y,
        combatCfg,
        { type = "dropdown", text = "Hero Talent",
          tooltip = "Only use this glow while the chosen hero talent tree is active. Any: always.",
          values = heroValues, order = heroOrder,
          getValue = function()
              local t = tonumber(entry.heroTree)
              return t and tostring(t) or "any"
          end,
          setValue = function(v)
              entry.heroTree = (v ~= "any") and tonumber(v) or nil
              if onChange then onChange() end
          end })
    return y - h
end

-- "Duplicate" left of a glow's Remove button: inserts a full copy of the glow
-- (buff, style, colour, stacks, And condition, hero talent) right below it, so
-- variants of the same buff (e.g. one per hero tree) start from the original.
-- Returns the button so the buff icon can sit to its left.
function ns.BarGlowDuplicateButton(region, removeBtn, buffList, index, onDone)
    if EllesmereUI._prebuilding or not (region and removeBtn and buffList) then return nil end
    local PP = EllesmereUI.PanelPP or EllesmereUI.PP
    local b = CreateFrame("Button", nil, region)
    PP.Size(b, 110, removeBtn:GetHeight())
    b:SetFrameLevel(removeBtn:GetFrameLevel())
    b:SetPoint("RIGHT", removeBtn, "LEFT", -8, 0)
    EllesmereUI.MakeStyledButton(b, EllesmereUI.L("Duplicate"), 13, EllesmereUI.RB_COLOURS, function()
        local src = buffList[index]
        if type(src) ~= "table" then return end
        local copy = CopyTable(src)
        copy.collapsed = nil   -- the copy opens expanded
        table.insert(buffList, index + 1, copy)
        if onDone then onDone() end
    end)
    return b
end

-- Bar Glows button preview: the CDM bar's live icon width as it appears on
-- screen (covers width/height match and the UI scale), converted into the
-- preview panel's scale. nil when no icon is laid out yet (the page then uses
-- the stored iconSize).
function ns.BarGlowPreviewIconSize(icons, previewParent)
    if type(icons) ~= "table" then return nil end
    local ps = previewParent and previewParent.GetEffectiveScale and previewParent:GetEffectiveScale()
    for i = 1, #icons do
        local f = icons[i]
        if f and f.GetWidth then
            local w = f:GetWidth()
            if w and not (issecretvalue and issecretvalue(w)) and w > 1 then
                local es = f:GetEffectiveScale()
                if es and ps and ps > 0 then w = w * es / ps end
                return math.floor(w + 0.5)
            end
        end
    end
    return nil
end

-- Collapse bar across the top of each glow, the same height either way: the
-- arrow, the buff icon and its name. Expanded: a down arrow above the glow's
-- rows. Collapsed (entry.collapsed = true, saved): a right arrow, and the rows
-- are skipped. A click flips it and rebuilds the page. The hidden search pre-build
-- and an active search always build every row. Returns the new y and whether
-- the caller should build the rows.
local ARROW_DOWN  = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-arrow-down3.png"
local ARROW_RIGHT = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-arrow-right.png"

function ns.BuildBarGlowHeader(parent, y, entry, aIdx)
    if EllesmereUI._prebuilding or EllesmereUI._lessCommonSearchActive then return y, true end
    local collapsed = entry.collapsed == true
    if aIdx > 1 then y = y - 8 end
    local H = 38
    local pad = EllesmereUI.CONTENT_PAD or 20
    local bar = CreateFrame("Button", nil, parent)
    bar:SetPoint("TOPLEFT", parent, "TOPLEFT", pad, y)
    bar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -pad, y)
    bar:SetHeight(H)
    bar:SetFrameLevel(parent:GetFrameLevel() + 5)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 0.04)

    -- The arrow drawn three times, 1px apart, for a bolder stroke than the icon art.
    local arrows = {}
    for i, off in ipairs({ { 0, 0 }, { 1, 0 }, { 0, -1 } }) do
        local t = bar:CreateTexture(nil, "OVERLAY")
        t:SetSize(16, 16)
        t:SetTexture(collapsed and ARROW_RIGHT or ARROW_DOWN)
        t:SetPoint("LEFT", bar, "LEFT", 10 + off[1], off[2])
        arrows[i] = t
    end
    local arrow = arrows[1]
    local function PaintArrow(r, g, b, a)
        for _, t in ipairs(arrows) do t:SetVertexColor(r, g, b); t:SetAlpha(a) end
    end
    PaintArrow(1, 1, 1, 0.7)

    local ico = ns.BarGlowSpellIcon(bar, 26, entry.spellID)
    ico:SetPoint("LEFT", arrow, "RIGHT", 11, 0)
    local title = EllesmereUI.MakeFont(bar, 13, nil, 1, 1, 1)
    title:SetPoint("LEFT", ico, "RIGHT", 10, 0)
    title:SetText((SpellLabel(entry.spellID)))

    local EG = EllesmereUI.ELLESMERE_GREEN
    bar:SetScript("OnEnter", function()
        bg:SetColorTexture(1, 1, 1, 0.08)
        PaintArrow(EG.r, EG.g, EG.b, 1)
        title:SetTextColor(EG.r, EG.g, EG.b)
    end)
    bar:SetScript("OnLeave", function()
        bg:SetColorTexture(1, 1, 1, 0.04)
        PaintArrow(1, 1, 1, 0.7)
        title:SetTextColor(1, 1, 1)
    end)
    bar:SetScript("OnClick", function()
        entry.collapsed = (not collapsed) and true or nil
        EllesmereUI:RefreshPage(true)
    end)
    return y - H - (collapsed and 0 or 4), not collapsed
end
