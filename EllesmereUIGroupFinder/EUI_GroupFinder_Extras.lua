if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_GroupFinder_Extras.lua - the extra filters and looks:
--  has / missing rows, specific roles, menu icons, group settings columns,
--  region tags, row art, the scrolling strips, the person / raid icons
-------------------------------------------------------------------------------
local FOLDER, ns = ...
if EllesmereUI.HELD_BACK_ADDONS[FOLDER] then return end -- held back (EllesmereUIGroupFinder.lua)
ns.EUI = EllesmereUI

-- runs fn once blizzard's group finder loads
function ns.WhenGroupFinder(fn)
    -- module off: nothing hooks in
    if not ns.Enabled() or ns.Blocked() then return end
    if C_AddOns.IsAddOnLoaded("Blizzard_GroupFinder") and PVEFrame then
        fn()
        return
    end
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(self, _, name)
        if name ~= "Blizzard_GroupFinder" then return end
        self:UnregisterAllEvents()
        fn()
    end)
end
local GFNS = ns

-- specific roles: match all (and) or match any (or)
GFNS.ExtraRolesAny = function()
    local c = GFNS.Cfg and GFNS.Cfg()
    return c and c.extraRolesAny == true or false
end

local CM = ns.EUI
local Secret = EllesmereUI.IsSecret
local HINT_GREY = 0.35  -- the (and) / (or) bit, never takes the accent
-- dim label grey
local DIM_HEX = EllesmereUI.COLOR_CODES.DIM

-- label + grey hint
local function TwoPart(owner, K)
    local main = owner:CreateFontString(nil, "OVERLAY")
    K.Font(main, K.ITEM_FONT)
    main:SetPoint("LEFT", owner, "LEFT", 7, 0)
    local hint = owner:CreateFontString(nil, "OVERLAY")
    K.Font(hint, K.ITEM_FONT)
    hint:SetPoint("LEFT", main, "RIGHT", 3, 0)
    hint:SetTextColor(HINT_GREY, HINT_GREY, HINT_GREY, 1)
    return main, hint
end

local ARROW = "Interface\\AddOns\\" .. FOLDER .. "\\media\\icons\\eui-arrow.png"

-- our dropdowns can hang outside the menu: clicks in them keep it open
local pops = {}
GFNS.ExtraInside = function()
    for _, f in ipairs(pops) do
        if f:IsShown() and f:IsMouseOver() then return true end
    end
    return false
end

local MASK = "Interface\\AddOns\\" .. FOLDER .. "\\media\\masks\\rounded.png"

-- an atlas name, or a spell's texture (cropped to lose its built-in border)
local function PaintIcon(ic, icon)
    if type(icon) == "number" then
        ic:SetTexture(icon)
        ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    else
        ic:SetAtlas(icon)
    end
end

-- rounded icon after the text
local function RoundIcon(parent, icon, after)
    local ic = parent:CreateTexture(nil, "OVERLAY")
    ic:SetSize(12, 12)
    ic:SetPoint("LEFT", after, "RIGHT", 4, 0)
    if icon then PaintIcon(ic, icon) end
    local mask = parent:CreateMaskTexture()
    mask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(ic)
    ic:AddMaskTexture(mask)
    ic.mask = mask
    return ic
end

-- skinned dropdown button: label, grey hint, arrow
local function ArrowButton(owner, K)
    local btn = CreateFrame("Button", nil, owner)
    btn:SetNormalFontObject("GameFontHighlight")
    btn:SetText(" ")
    btn.Arrow = btn:CreateTexture(nil, "OVERLAY")
    btn.Arrow:SetTexture(ARROW)
    btn.Arrow:SetSize(13, 13)  -- how it looks in the settings
    btn.Arrow:SetPoint("CENTER", btn, "RIGHT", -10, 0)
    btn.Label, btn.Hint = TwoPart(btn, K)
    btn.Label:SetTextColor(CM.TEXT_DIM_R, CM.TEXT_DIM_G, CM.TEXT_DIM_B, CM.TEXT_DIM_A)
    -- icon room, made before the skin so it survives
    btn.Icon = RoundIcon(btn, nil, btn.Label)
    btn.IconMask = btn.Icon.mask
    btn.Icon:Hide()
    local skin = CM._ModuleNS and CM._ModuleNS.EllesmereUIBlizzardSkin
    local S = skin and skin.WSkin
    if S and S.Button then
        S.Button(btn, { "Arrow", "Label", "Hint", "Icon", "IconMask" })
    else
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.06, 0.06, 0.06, 0.95)
        CM.MakeBorder(btn, K.ThemeBorder())
        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.1)
    end
    return btn
end


-- under the button, or above it if it'd hang off the menu
local function OpenNear(pop, btn, bounds, pad)
    pad = pad or 0
    pop:ClearAllPoints()
    local bb, mb = btn:GetBottom(), bounds and bounds:GetBottom()
    if bb and mb and (bb - 2 - pop:GetHeight()) * btn:GetEffectiveScale() < mb * bounds:GetEffectiveScale() then
        pop:SetPoint("BOTTOMLEFT", btn, "TOPLEFT", -pad, 2)
        pop:SetPoint("BOTTOMRIGHT", btn, "TOPRIGHT", pad, 2)
    else
        pop:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", -pad, -2)
        pop:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", pad, -2)
    end
    pop:Show()
end

-- arrow button + its list. modes = { label, hint, icon }, get() = index,
-- set(i) on pick, up opens it above the button. caller places it
local function Dropdown(owner, K, modes, Get, Set, up)
    local btn = ArrowButton(owner, K)
    function btn:ShowMode()
        local mode = modes[Get()] or modes[1]
        self.Label:SetText(mode.button or mode.label)
        if mode.button then self.Label:SetTextColor(1, 1, 1, 1)
        else self.Label:SetTextColor(CM.TEXT_DIM_R, CM.TEXT_DIM_G, CM.TEXT_DIM_B, CM.TEXT_DIM_A) end
        self.Hint:SetText(mode.hint or "")
        if mode.icon then
            PaintIcon(self.Icon, mode.icon)
            self.Icon:Show()
        else
            self.Icon:Hide()
        end
    end
    btn:ShowMode()

    local list = CreateFrame("Frame", nil, K.parent or owner)
    list:SetFrameStrata("FULLSCREEN_DIALOG")
    list:SetFrameLevel(330)
    list:SetClampedToScreen(true)
    list:EnableMouse(true)
    local lbg = list:CreateTexture(nil, "BACKGROUND")
    lbg:SetAllPoints()
    lbg:SetColorTexture(0, 0, 0, 1)
    CM.MakeBorder(list, K.ThemeBorder())
    list.items = {}
    for i, mode in ipairs(modes) do
        local it = CreateFrame("Button", nil, list)
        it:SetHeight(K.ITEM_H)
        it:SetPoint("TOPLEFT", list, "TOPLEFT", 1, -(2 + (i - 1) * K.ITEM_H))
        it:SetPoint("TOPRIGHT", list, "TOPRIGHT", -1, -(2 + (i - 1) * K.ITEM_H))
        it.text, it.hint = TwoPart(it, K)
        it.text:SetText(mode.label)
        it.hint:SetText(mode.hint or "")
        if mode.icon then RoundIcon(it, mode.icon, it.text) end
        local ihl = it:CreateTexture(nil, "HIGHLIGHT")
        ihl:SetAllPoints()
        ihl:SetColorTexture(1, 1, 1, CM.DD_ITEM_HL_A or 0.08)
        it:SetScript("OnClick", function()
            Set(i)
            btn:ShowMode()
            list:Hide()
            K.Refilter()
            K.Paint()
        end)
        list.items[i] = it
    end
    list:SetHeight(4 + #modes * K.ITEM_H)
    btn.list = list
    pops[#pops + 1] = list
    K.ClickOff(list, function(self) return self:IsMouseOver() or btn:IsMouseOver() end)
    list:Hide()

    btn:SetScript("OnClick", function()
        if list:IsShown() then list:Hide() return end
        K.Untip()
        -- picked one in the accent color
        local ar, ag, ab = K.Accent()
        for i, it in ipairs(list.items) do
            if i == Get() then it.text:SetTextColor(ar, ag, ab, 1)
            else it.text:SetTextColor(CM.TEXT_DIM_R, CM.TEXT_DIM_G, CM.TEXT_DIM_B, CM.TEXT_DIM_A) end
        end
        list:ClearAllPoints()
        if up then
            list:SetPoint("BOTTOMLEFT", btn, "TOPLEFT", 0, 2)
            list:SetPoint("BOTTOMRIGHT", btn, "TOPRIGHT", 0, 2)
        else
            list:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
            list:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", 0, -2)
        end
        list:Show()
    end)
    btn:SetScript("OnHide", function() list:Hide() end)
    btn:SetScript("OnShow", function(self) self:ShowMode() end)
    btn:SetScript("OnLeave", K.Untip)
    return btn
end

local function Divider(m, y)
    local div = m:CreateTexture(nil, "ARTWORK")
    if ns.GFHairline then ns.GFHairline(div) else div:SetHeight(CM.PP.mult) end
    div:SetColorTexture(1, 1, 1, 0.10)
    div:SetPoint("TOPLEFT", m, "TOPLEFT", 10, -y - 3)
    div:SetPoint("TOPRIGHT", m, "TOPRIGHT", -10, -y - 3)
    return y + 7
end

-------------------------------------------------------------------------------
--  specific roles: a dropdown with match exact / any and the role count rows
-------------------------------------------------------------------------------
local function Block(m, y)
    local f = CreateFrame("Frame", nil, m)
    f:SetPoint("TOPLEFT", m, "TOPLEFT", 0, -y)
    f:SetPoint("TOPRIGHT", m, "TOPRIGHT", 0, -y)
    return f
end

local function PlaceBlock(f, m, y)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", m, "TOPLEFT", 0, -y)
    f:SetPoint("TOPRIGHT", m, "TOPRIGHT", 0, -y)
end

local MATCH = {
    { any = false, label = EllesmereUI.L("Match All"),   hint = "(and)", tip = EllesmereUI.L("Match all of the selected options below.") },
    { any = true,  label = EllesmereUI.L("Match Any"),   hint = "(or)",  tip = EllesmereUI.L("Match any of the selected options below.") },
}

local function CountsOn(c)
    local n = 0
    for _, rule in pairs(type(c.roleCounts) == "table" and c.roleCounts or {}) do
        if type(rule) == "table" and rule.on then n = n + 1 end
    end
    return n
end

GFNS.ExtraRoleCounts = function(m, y, K)
    local sg = Block(m, y)
    sg:SetHeight(K.ITEM_H)
    m.extraSpecGrp = sg
    local btn = ArrowButton(sg, K)
    btn:SetHeight(K.ITEM_H - 2)
    btn:SetPoint("TOPLEFT", sg, "TOPLEFT", 9, -1)
    btn:SetPoint("TOPRIGHT", sg, "TOPRIGHT", -9, -1)
    btn.Label:SetText(EllesmereUI.L("Specific Roles"))

    local pop = CreateFrame("Frame", nil, K.parent or m)
    pop:SetFrameStrata("FULLSCREEN_DIALOG")
    pop:SetFrameLevel(325)
    pop:SetClampedToScreen(true)
    pop:EnableMouse(true)
    local pbg = pop:CreateTexture(nil, "BACKGROUND")
    pbg:SetAllPoints()
    local fr, fg, fb = K.ThemeFill()
    pbg:SetColorTexture(fr, fg, fb, 0.98)
    CM.MakeBorder(pop, K.ThemeBorder())
    pops[#pops + 1] = pop

    -- while open: veil over both columns, eats clicks
    local veil = CreateFrame("Button", nil, K.parent or m)
    veil:SetFrameStrata("FULLSCREEN_DIALOG")
    veil:SetFrameLevel(m:GetFrameLevel() + 8)
    local vt = veil:CreateTexture(nil, "BACKGROUND")
    vt:SetAllPoints()
    vt:SetColorTexture(fr, fg, fb, 0.7)
    veil:Hide()

    local py, toggles = 2, {}
    local function PaintMatch()
        local any = K.Cfg().extraRolesAny == true
        for _, t in ipairs(toggles) do t:SetChecked(t.any == any) end
    end
    for _, mode in ipairs(MATCH) do
        local t = K.MenuItem(pop, py, mode.label, function()
            K.Cfg().extraRolesAny = mode.any or nil
            PaintMatch()
            K.Refilter()
            K.Paint()
        end)
        t.any = mode.any
        local _, cb = t.label:GetPoint(1)
        t.label:ClearAllPoints()
        t.label:SetPoint("LEFT", cb, "RIGHT", 7, 0)
        local hint = t:CreateFontString(nil, "OVERLAY")
        K.Font(hint, K.ITEM_FONT)
        hint:SetPoint("LEFT", t.label, "RIGHT", 3, 0)
        hint:SetTextColor(HINT_GREY, HINT_GREY, HINT_GREY, 1)
        hint:SetText(mode.hint)
        t:HookScript("OnEnter", function(self) K.Tip(self, mode.tip) end)
        t:HookScript("OnLeave", K.Untip)
        toggles[#toggles + 1] = t
        py = py + K.ITEM_H
    end
    py = Divider(pop, py)
    -- count rows go in m.counts so the menu paints them
    m.counts = m.counts or {}
    pop.counts = m.counts
    for _, r in ipairs(K.COUNT_ROLES) do py = K.AddCountRow(pop, py, r.key, r.label) end
    pop:SetHeight(py + 2)
    K.ClickOff(pop, function(self)
        return self:IsMouseOver() or btn:IsMouseOver() or (K.OpListOver and K.OpListOver()) or false
    end)
    pop:Hide()

    -- "(2 active)" so ticked rows aren't forgotten
    local function ShowHint()
        local n = CountsOn(K.Cfg())
        btn.Hint:SetText(n > 0 and EllesmereUI.Lf("(%1$d active)", n) or "")
    end
    local sgLevel = sg:GetFrameLevel()
    pop:HookScript("OnShow", function()
        PaintMatch()
        veil:ClearAllPoints()
        veil:SetPoint("TOPLEFT", m.side or m, "TOPLEFT", 0, 0)
        veil:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT", 0, 0)
        veil:Show()
        sg:SetFrameLevel(veil:GetFrameLevel() + 1)  -- keeps the button lit
    end)
    pop:HookScript("OnHide", function()
        veil:Hide()
        sg:SetFrameLevel(sgLevel)
        ShowHint()
    end)
    btn:SetScript("OnClick", function()
        if pop:IsShown() then pop:Hide() return end
        OpenNear(pop, btn, m)
    end)
    btn:SetScript("OnShow", ShowHint)
    btn:SetScript("OnHide", function() pop:Hide() end)
    ShowHint()
    return y + K.ITEM_H
end

-------------------------------------------------------------------------------
--  raids and delves: squares in one sideways-scrolling line instead of a
--  grid that pushes the list down
-------------------------------------------------------------------------------
local ARROW_W = 14
local ARROW_DIR = "Interface\\AddOns\\EllesmereUI\\media\\icons\\"

local function PlaceStrip(s)
    if not s.list then return end
    local per = s.size + s.gap
    -- whole steps only, stops once the last square is fully in view
    local full = math.max(1, math.floor((s.clipW + s.gap) / per))
    local maxOff = math.max(0, #s.list - full)
    s.offset = math.max(0, math.min(s.offset, maxOff))
    local shift = -s.offset * per
    for i, sq in ipairs(s.squares) do
        local d = s.list[i]
        if d then
            local x = (i - 1) * per + shift
            sq:ClearAllPoints()
            sq:SetPoint("LEFT", s.clip, "LEFT", x, 0)
            -- hidden off-window so they can't be clicked
            sq:SetShown(x + s.size > 0 and x < s.clipW)
        end
    end
    for _, a in ipairs({ { s.left, s.offset > 0 }, { s.right, s.offset < maxOff } }) do
        local b, live = a[1], a[2]
        b.live = live
        b:EnableMouse(live)
        b.tex:SetAlpha(live and 0.8 or 0.2)
    end
end

local function ScrollStrip(s, step)
    s.offset = s.offset + step
    if GFNS.ExtraHideBossPick then GFNS.ExtraHideBossPick() end
    PlaceStrip(s)
    if s.paint then s.paint() end  -- recolor the squares now in view
end

local function StripArrow(s, row, file, step)
    local b = CreateFrame("Button", nil, row)
    b.tex = b:CreateTexture(nil, "OVERLAY")
    b.tex:SetTexture(ARROW_DIR .. file)
    b.tex:SetSize(16, 16)
    b.tex:SetPoint("CENTER")
    b:SetScript("OnClick", function() ScrollStrip(s, step) end)
    b:SetScript("OnEnter", function(self) if self.live then self.tex:SetAlpha(1) end end)
    b:SetScript("OnLeave", function(self) self.tex:SetAlpha(self.live and 0.8 or 0.2) end)
    return b
end

-- one strip. key = the square's data field, fill dresses a square
local function NewStrip(key, fill)
    local s = { offset = 0 }
    return function(list, squares, Make, size, after, show, cols, slots, row, gap, paint)
        s.paint = paint
        if not s.clip then
            s.clip = CreateFrame("Frame", nil, row)
            s.clip:SetClipsChildren(true)
            s.clip:EnableMouseWheel(true)
            s.clip:SetScript("OnMouseWheel", function(_, delta) ScrollStrip(s, delta > 0 and -1 or 1) end)
            s.left = StripArrow(s, row, "eui-arrow-left.png", -1)
            s.right = StripArrow(s, row, "eui-arrow-right.png", 1)
        end
        if not show or #list == 0 or not after then
            for _, sq in ipairs(squares) do sq[key] = nil; sq:Hide() end
            s.clip:Hide(); s.left:Hide(); s.right:Hide()
            s.list = nil
            return 1
        end
        local per = size + gap
        local startX = gap + (slots - cols) * per
        local room = cols * per - gap
        local fits = #list * per - gap <= room
        local vis = fits and #list or math.max(1, math.floor((room - 2 * (ARROW_W + gap) + gap) / per))
        s.clip:ClearAllPoints()
        s.left:ClearAllPoints()
        s.right:ClearAllPoints()
        s.left:SetSize(ARROW_W, size)
        s.right:SetSize(ARROW_W, size)
        if fits then
            s.left:Hide(); s.right:Hide()
            s.clip:SetPoint("LEFT", after, "RIGHT", startX, 0)
        else
            s.left:SetPoint("LEFT", after, "RIGHT", startX, 0)
            s.left:Show()
            s.clip:SetPoint("LEFT", s.left, "RIGHT", gap, 0)
        end
        -- scrolling: runs to the row's right edge
        local clipW = vis * per - gap
        if fits then
            s.clip:SetSize(clipW, size)
        else
            s.right:SetPoint("RIGHT", row, "RIGHT", 4, 0)  -- a touch wider so the last border isn't clipped
            s.right:Show()
            s.clip:SetPoint("RIGHT", s.right, "LEFT", -gap, 0)
            s.clip:SetHeight(size)
            clipW = room + 4 - 2 * (ARROW_W + gap)
        end
        s.clip:Show()
        for i, d in ipairs(list) do
            local sq = squares[i]
            if not sq then sq = Make(); squares[i] = sq end
            if sq:GetParent() ~= s.clip then sq:SetParent(s.clip) end
            sq[key] = d
            fill(sq, d)
            sq:SetSize(size, size)
        end
        for i = #list + 1, #squares do squares[i][key] = nil; squares[i]:Hide() end
        s.list, s.squares, s.size, s.gap, s.clipW = list, squares, size, gap, clipW
        PlaceStrip(s)
        return 1
    end
end

GFNS.ExtraBossStrip = NewStrip("boss", function(sq, d)
    sq.icon:SetTexture(d.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
end)
-- delves: the module dresses its squares
GFNS.ExtraDelveStrip = NewStrip("delve", function(sq, d)
    if GFNS.GFDressDelve then GFNS.GFDressDelve(sq, d) end
end)

-- filters menu spans search box to refresh
GFNS.ExtraWidenMenu = function(m, anchor, gap, right)
    local sp = LFGListFrame and LFGListFrame.SearchPanel
    local left = sp and (sp.SearchBox or sp.BackButton)
    if not (left and left:IsVisible() and left:GetLeft() and anchor:GetLeft()) then return end
    -- split evenly
    if m.side and right and right:GetRight() then
        local total = (right:GetRight() * right:GetEffectiveScale() - left:GetLeft() * left:GetEffectiveScale())
            / m:GetEffectiveScale()
        if total > 100 then m.side:SetWidth(math.floor(total / 2 + 0.5)) end
    end
    local sideW = m.side and m.side:GetWidth() or 0
    local dx = (left:GetLeft() * left:GetEffectiveScale() - anchor:GetLeft() * anchor:GetEffectiveScale())
        / m:GetEffectiveScale() + sideW
    m:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", dx, -gap)
end

-------------------------------------------------------------------------------
--  has / missing rows: bloodlust, battle res and your class
-------------------------------------------------------------------------------
local LUST = { SHAMAN = true, MAGE = true, HUNTER = true, EVOKER = true }
local BREZ = { DRUID = true, DEATHKNIGHT = true, WARLOCK = true, PALADIN = true }

local function MyClass()
    local name, file = UnitClass("player")
    return name, file
end

local CLASS_ROWS = {
    { key = "hasLust", pick = "extraLustMissing", spell = 2825, has = EllesmereUI.L("Has Bloodlust"), missing = EllesmereUI.L("Missing Bloodlust"),
      Tip = function(K) return EllesmereUI.L("Bloodlust"), {
        EllesmereUI.L("A member whose class has one of these spells:"),
        K.ClassLine("SHAMAN", EllesmereUI.L("Bloodlust / Heroism (Shaman)")),
        K.ClassLine("MAGE", EllesmereUI.L("Time Warp (Mage)")),
        K.ClassLine("HUNTER", EllesmereUI.L("Primal Rage (Hunter pet)")),
        K.ClassLine("EVOKER", EllesmereUI.L("Fury of the Aspects (Evoker)")),
        EllesmereUI.L("Drums and other items don't count.") } end },
    { key = "hasBrez", pick = "extraBrezMissing", spell = 20484, has = EllesmereUI.L("Has Battle Res"), missing = EllesmereUI.L("Missing Battle Res"),
      Tip = function(K) return EllesmereUI.L("Battle Res"), {
        EllesmereUI.L("A member whose class has one of these spells:"),
        K.ClassLine("DRUID", EllesmereUI.L("Rebirth (Druid)")),
        K.ClassLine("DEATHKNIGHT", EllesmereUI.L("Raise Ally (Death Knight)")),
        K.ClassLine("WARLOCK", EllesmereUI.L("Soulstone (Warlock)")),
        K.ClassLine("PALADIN", EllesmereUI.L("Intercession (Paladin)")),
        EllesmereUI.L("Engineering and other items don't count.") } end },
    { key = "extraMyClass", pick = "extraMyClassMissing", missingDefault = true,
      raidKey = "raidMyClass", raidPick = "raidMyClassMissing",  -- the raids tab keeps its own
      has = "Has Class", missing = "No Class",  -- class name added at build
      Tip = function(K)
        local name, file = MyClass()
        return EllesmereUI.L("Your Class"), { EllesmereUI.Lf("A member who's your class: %1$s", file and K.ClassLine(file, name) or name or "") }
      end },
}

-- the row's keys on this tab
local function Keys(row, raids)
    if raids and row.raidKey then return row.raidKey, row.raidPick end
    return row.key, row.pick
end

local function Missing(c, row, raids)
    local _, pick = Keys(row, raids)
    local v = c[pick]
    if v == nil then return row.missingDefault == true end
    return v == true
end

GFNS.ExtraClassRows = function(m, y, K)
    for _, k in ipairs({ "extraMyClass", "raidMyClass" }) do
        if K.FLAG_KEYS and not tContains(K.FLAG_KEYS, k) then K.FLAG_KEYS[#K.FLAG_KEYS + 1] = k end
    end
    local raids = K.raids
    m.extraRolesEnd = y
    m.extraItemH = K.ITEM_H
    m.extraK = K
    local roleG, miscG = Block(m, y), Block(m, y + K.ITEM_H)
    m.extraClassGrp, m.extraMiscGrp = roleG, miscG
    local ry, my = 0, 0
    for _, row in ipairs(CLASS_ROWS) do
        local function ShowTip(self)
            if self.list and self.list:IsShown() then return end
            local title, lines = row.Tip(K)
            K.Tip(self, title, unpack(lines))
        end
        local inRoles = row.key == "extraMyClass"
        local key, pick = Keys(row, raids)
        local has, missing = row.has, row.missing
        local hasBtn, missingBtn
        local icon = row.spell and C_Spell.GetSpellTexture(row.spell)
        if inRoles then
            local name, file = MyClass()
            local cls = (name and file) and K.ClassLine(file, name) or name or EllesmereUI.L("Class")
            has, missing = EllesmereUI.L("Has") .. " " .. cls, EllesmereUI.L("No") .. " " .. cls
            -- full alpha so the class color shows, has / no greyed by hand
            hasBtn, missingBtn = DIM_HEX .. EllesmereUI.L("Has") .. "|r " .. cls, DIM_HEX .. EllesmereUI.L("No") .. "|r " .. cls
            icon = file and ("classicon-" .. file:lower())
        end
        local item = K.MenuItem(inRoles and roleG or miscG, inRoles and ry or my, "", function()
            local c = K.Cfg()
            c[key] = (not c[key]) or nil
            K.Refilter()
            K.Paint()
        end)
        m.items["flag_" .. key] = item
        item.label:Hide()
        local btn = Dropdown(item, K, {
            { label = has, button = hasBtn, icon = icon },
            { label = missing, button = missingBtn, icon = icon },
        }, function() return Missing(K.Cfg(), row, raids) and 2 or 1 end,
        function(i)
            -- picking turns the class row on; lust / brez leave the box alone
            local c = K.Cfg()
            c[pick] = (i == 2)
            if inRoles then c[key] = true end
        end)
        btn:SetHeight(K.ITEM_H - 2)
        btn:SetPoint("LEFT", item, "LEFT", 8 + K.CHECK_SZ + 7, 0)
        btn:SetPoint("RIGHT", item, "RIGHT", -8, 0)
        btn:SetScript("OnEnter", ShowTip)
        if inRoles then ry = ry + K.ITEM_H else my = my + K.ITEM_H end
    end
    roleG:SetHeight(ry)
    miscG:SetHeight(my)
    return y + ry + my
end

-- false = drop the group. secret members don't count
GFNS.ExtraClassKeep = function(id, info, c, raids)
    local mineKey = raids and "raidMyClass" or "extraMyClass"
    if not (c.hasLust or c.hasBrez or c[mineKey]) then return true end
    local n = info and info.numMembers
    if type(n) ~= "number" or Secret(n) then return true end
    local _, mine = MyClass()
    local have = { hasLust = false, hasBrez = false, extraMyClass = false }
    for i = 1, n do
        local p = C_LFGList.GetSearchResultPlayerInfo(id, i)
        if p and (Secret(p) or (canaccesstable and not canaccesstable(p))) then p = nil end
        local cls = p and p.classFilename
        if cls and not Secret(cls) then
            if LUST[cls] then have.hasLust = true end
            if BREZ[cls] then have.hasBrez = true end
            if cls == mine then have.extraMyClass = true end
        end
    end
    for _, row in ipairs(CLASS_ROWS) do
        if c[Keys(row, raids)] and have[row.key] == Missing(c, row, raids) then return false end
    end
    return true
end

-------------------------------------------------------------------------------
--  region tags: where the leader plays from (us: region, eu: realm language)
-------------------------------------------------------------------------------
local function TagsOn()
    local c = GFNS.Cfg and GFNS.Cfg()
    return c and c.extraRegionTags ~= false and ns.RegionList() ~= nil
end

local function RegionOf(resultID)
    local info = C_LFGList.GetSearchResultInfo(resultID)
    if not info or Secret(info) or (canaccesstable and not canaccesstable(info)) then return nil end
    local leader = info.leaderName
    if not leader or Secret(leader) then return nil end
    local realm = leader:match("%-(.+)$") or (GetNormalizedRealmName and GetNormalizedRealmName())
    if not realm or Secret(realm) then return nil end
    return ns.RegionOfRealm(realm)
end

local tagOf = setmetatable({}, { __mode = "k" })

-- for our results list: tag, color, flag
function ns.RegionTagOf(resultID)
    if not TagsOn() then return nil end
    local d = ns.RegionInfo(RegionOf(resultID))
    if d then return d.tag, d.r, d.g, d.b, d.flag end
end

-- same tag for an applicant's "name-realm"
function ns.RegionTagOfName(name)
    if not TagsOn() or not name or Secret(name) then return nil end
    local realm = name:match("%-(.+)$") or (GetNormalizedRealmName and GetNormalizedRealmName())
    if not realm or Secret(realm) then return nil end
    local d = ns.RegionInfo(ns.RegionOfRealm(realm))
    if d then return d.tag, d.r, d.g, d.b, d.flag end
end

-- "Relaxed | OCE [flag]" after the playstyle on blizzard's row
local function Parts(entry)
    local p = tagOf[entry]
    if p then return p end
    local f = CreateFrame("Frame", nil, entry)
    f:SetAllPoints(entry)
    f:SetFrameLevel(entry:GetFrameLevel() + 4)
    f:EnableMouse(false)
    p = {
        sep  = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"),
        tag  = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"),
        flag = f:CreateTexture(nil, "OVERLAY"),
    }
    p.sep:SetText("||")  -- escaped pipe draws one |
    p.sep:SetTextColor(0.35, 0.35, 0.35, 1)
    tagOf[entry] = p
    return p
end

-------------------------------------------------------------------------------
--  row art: the instance's art fading across the left half
-------------------------------------------------------------------------------
local function RowArtOn()
    local c = GFNS.Cfg and GFNS.Cfg()
    return c and c.extraRowArt == true
end

-- instance art by map id: keystone background, else the journal's
local ART_CROP = { 0.205, 0.795, 0.25, 0.50 }  -- a strip clear of the art's frame
local artOf = {}
local function Art(mapID)
    if not mapID or Secret(mapID) then return nil end
    local a = artOf[mapID]
    if a ~= nil then return a or nil end
    a = false
    local CMode = C_ChallengeMode
    for _, cm in ipairs(CMode and CMode.GetMapTable and CMode.GetMapTable() or {}) do
        local _, _, _, _, bgTex, mid = CMode.GetMapUIInfo(cm)
        if mid == mapID and bgTex then a = bgTex end
    end
    local CEJ = C_EncounterJournal
    if not a and CEJ and CEJ.GetInstanceForGameMap and EJ_GetInstanceInfo then
        local jid = CEJ.GetInstanceForGameMap(mapID)
        if jid then
            local _, _, bgImage, _, loreImage = EJ_GetInstanceInfo(jid)
            a = loreImage or bgImage or false
        end
    end
    artOf[mapID] = a
    return a or nil
end

local function Activity(resultID)
    local info = C_LFGList.GetSearchResultInfo(resultID)
    if not info or Secret(info) or (canaccesstable and not canaccesstable(info)) then return nil end
    local acts = info.activityIDs
    local act = type(acts) == "table" and not Secret(acts) and acts[1]
    if not act or Secret(act) then return nil end
    local ai = C_LFGList.GetActivityInfoTable(act)
    if not ai or Secret(ai) or (canaccesstable and not canaccesstable(ai)) then return nil end
    return ai
end

local ART_SHARE, ART_ALPHA = 0.5, 0.2  -- half the row, 20% fading out
local FADE_MASK = "Interface\\AddOns\\" .. FOLDER .. "\\media\\masks\\fade.png"

-- for our results list: a group's art (nil when off)
function ns.RowArtFor(resultID)
    if not RowArtOn() then return nil end
    local ai = Activity(resultID)
    return ai and Art(ai.mapID)
end
-- the same for an instance's map id (the settings preview)
function ns.RowArtForMap(mapID)
    if not RowArtOn() then return nil end
    return Art(mapID)
end
ns.ROW_ART = { crop = ART_CROP, share = ART_SHARE, alpha = ART_ALPHA, mask = FADE_MASK }

-- art under blizzard's text, the tag on our overlay above
local function RowArt(entry, p)
    local art = RowArtOn() and entry.resultID
    local ai = art and Activity(entry.resultID)
    art = ai and Art(ai.mapID)
    if not art then
        if p.art then p.art:Hide() end
        return
    end
    if not p.art then
        p.art = entry:CreateTexture(nil, "BACKGROUND", nil, 7)
        p.art:SetAlpha(ART_ALPHA)
        -- curved fade so the art's own frame never shows
        local mask = entry:CreateMaskTexture()
        mask:SetTexture(FADE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(p.art)
        p.art:AddMaskTexture(mask)
    end
    p.art:SetTexture(art)
    p.art:SetTexCoord(unpack(ART_CROP))
    p.art:ClearAllPoints()
    p.art:SetPoint("TOPLEFT", entry, "TOPLEFT", 3, -2)
    p.art:SetPoint("BOTTOMLEFT", entry, "BOTTOMLEFT", 3, 0)
    p.art:SetWidth(math.max(1, math.floor((entry:GetWidth() or 0) * ART_SHARE)))
    p.art:Show()
end

local function TagEntry(entry)
    if not (entry and entry.Playstyle) then return end
    local p = Parts(entry)
    RowArt(entry, p)
    p.sep:Hide(); p.tag:Hide(); p.flag:Hide()
    if not (TagsOn() and entry.resultID) then return end
    local d = ns.RegionInfo(RegionOf(entry.resultID))
    if not d then return end
    local play = entry.Playstyle
    local ok, _, size = pcall(play.GetFont, play)
    if ok and type(size) == "number" and not Secret(size) and size > 0 then
        for _, fs in ipairs({ p.sep, p.tag }) do
            local path, _, flags = fs:GetFont()
            if path then fs:SetFont(path, size, flags or "") end
        end
    else
        size = 10
    end
    local okText, text = pcall(play.GetText, play)
    local hasPlay = okText and type(text) == "string" and not Secret(text) and text ~= ""
    p.tag:ClearAllPoints()
    if hasPlay then
        p.sep:ClearAllPoints()
        p.sep:SetPoint("LEFT", play, "RIGHT", 5, 0)
        p.sep:Show()
        p.tag:SetPoint("LEFT", p.sep, "RIGHT", 5, 0)
    else
        p.tag:SetPoint("LEFT", play, "LEFT", 0, 0)
    end
    p.tag:SetText(d.tag)
    p.tag:SetTextColor(d.r, d.g, d.b, 1)
    p.tag:Show()
    local art = d.flag
    if art then
        p.flag:SetTexture(art)
        p.flag:SetSize(math.floor(size * 4 / 3 + 0.5), size)
        p.flag:ClearAllPoints()
        p.flag:SetPoint("LEFT", p.tag, "RIGHT", 4, 0)
        p.flag:Show()
    end
end

local function RetagRows()
    local sp = LFGListFrame and LFGListFrame.SearchPanel
    local box = sp and sp.ScrollBox
    if box and box.ForEachFrame then box:ForEachFrame(TagEntry) end
    -- our results list too
    if ns.OwnListRefresh then ns.OwnListRefresh() end
end

ns.GFRetagRows = RetagRows  -- for the settings page

if ns.WhenGroupFinder then
    ns.WhenGroupFinder(function()
        if LFGListSearchEntry_Update then hooksecurefunc("LFGListSearchEntry_Update", TagEntry) end
    end)
end

-- results list order (saved as extraSortBy)
ns.SORT_MODES = {
    { key = "default", label = EllesmereUI.L("Default") },
    { key = "high",    label = EllesmereUI.L("Highest Score") },
    { key = "low",     label = EllesmereUI.L("Lowest Score") },
    { key = "big",     label = EllesmereUI.L("Largest Size") },
    { key = "small",   label = EllesmereUI.L("Lowest Size") },
}

-- a menu row: label + dropdown
local function ChoiceItem(col, y, spec, G, up)
    local item = CreateFrame("Frame", nil, col)
    item:SetHeight(G.ITEM_H)
    item:SetPoint("TOPLEFT", col, "TOPLEFT", 1, -y)
    item:SetPoint("TOPRIGHT", col, "TOPRIGHT", -1, -y)
    item.label = item:CreateFontString(nil, "OVERLAY")
    G.Font(item.label, G.ITEM_FONT)
    item.label:SetPoint("LEFT", item, "LEFT", 9, 0)
    item.label:SetTextColor(CM.TEXT_DIM_R, CM.TEXT_DIM_G, CM.TEXT_DIM_B, CM.TEXT_DIM_A)
    item.label:SetText(spec.label)
    local modes = spec.choice
    local function Get()
        local v = G.Cfg()[spec.key]
        for i, mode in ipairs(modes) do if mode.key == v then return i end end
        return 1
    end
    local btn = Dropdown(item, G, modes, Get, function(i) G.Cfg()[spec.key] = modes[i].key end, up)
    btn:SetHeight(G.ITEM_H - 2)
    btn:SetPoint("LEFT", item.label, "RIGHT", 10, 0)
    btn:SetPoint("RIGHT", item, "RIGHT", -8, 0)
    item.btn = btn
    function item:Paint() self.btn:ShowMode() end
    return item
end

-------------------------------------------------------------------------------
--  menu icons: role icons and region flags
-------------------------------------------------------------------------------
local ROLE_DIR = "Interface\\AddOns\\EllesmereUIRaidFrames\\media\\"
-- same art for the results list's open slots
local ROLE_FILE = { TANK = "tank.png", HEALER = "healer.png", DAMAGER = "dps.png" }
function ns.RoleIconTex(role)
    local f = ROLE_FILE[role]
    return f and (ROLE_DIR .. f)
end
local ICONS = {
    role_needsTank   = { ROLE_DIR .. "tank.png",   12, 12 },
    role_needsHealer = { ROLE_DIR .. "healer.png", 12, 12 },
    role_needsDamage = { ROLE_DIR .. "dps.png",    12, 12 },
}
-- the region filter's flags, whichever region you're in
for _, d in ipairs(ns.RegionList() or {}) do
    ICONS["region_" .. d.key] = { d.flag, 13, 10 }
end

-- misc in two columns, lined up with the side panel
local function LayoutMisc(menu, side)
    local roleG, miscG, sg = menu.extraClassGrp, menu.extraMiscGrp, menu.extraSpecGrp
    if not (roleG and miscG and sg and menu.extraRolesEnd) then return end
    local y = menu.extraRolesEnd
    PlaceBlock(sg, menu, y)
    y = y + sg:GetHeight()
    local miscY, rowsY = side and side.extraMiscY, side and side.extraMiscRowsY
    if miscY and rowsY and miscY >= y then
        Divider(menu, miscY)
        y = rowsY
    else
        y = Divider(menu, y)
    end
    PlaceBlock(miscG, menu, y)
    y = y + miscG:GetHeight()
    PlaceBlock(roleG, menu, y)
    y = y + roleG:GetHeight()
    -- sort by under your class, its list opening upwards
    local K = menu.extraK
    if K then
        local row = CreateFrame("Frame", nil, menu)
        row:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", menu, "TOPRIGHT", 0, -y)
        row:SetHeight(K.ITEM_H)
        ChoiceItem(row, 0, { key = "extraSortBy", label = EllesmereUI.L("Sort By"), choice = ns.SORT_MODES }, K, true)
        y = y + K.ITEM_H
    end
    local h = math.max(side and side.extraEndY and (side.extraEndY + 3) or 0, y + 3)
    menu:SetHeight(h)
    if side then side:SetHeight(h) end
end

GFNS.ExtraDecorateMenu = function(menu, side)
    if menu then LayoutMisc(menu, side) end
    for _, owner in ipairs({ menu, side }) do
        local items = owner and owner.items
        if items then
            for key, art in pairs(ICONS) do
                local item = items[key]
                if item and item.label and not item.extraIcon then
                    local _, cb = item.label:GetPoint(1)
                    if cb then
                        local tex = item:CreateTexture(nil, "OVERLAY")
                        tex:SetTexture(art[1])
                        tex:SetSize(art[2], art[3])
                        tex:SetPoint("LEFT", cb, "RIGHT", 6, 0)
                        item.label:ClearAllPoints()
                        item.label:SetPoint("LEFT", tex, "RIGHT", 5, 0)
                        item.label:SetPoint("RIGHT", item, "RIGHT", -4, 0)
                        item.extraIcon = tex
                    end
                end
            end
        end
    end
end

GFNS.ExtraRaidTex = "Interface\\AddOns\\" .. FOLDER .. "\\media\\icons\\eui-raid.png"
