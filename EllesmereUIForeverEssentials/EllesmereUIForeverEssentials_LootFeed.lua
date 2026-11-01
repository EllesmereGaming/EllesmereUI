if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_LootFeed.lua  (WoW Forever only)
--  A stack of short-lived rows for what the player gains: looted items, money,
--  reputation, currencies and skill ups. Each row fades out after a while; a
--  repeat gain of the same thing adds to its row instead of opening another.
--  The Gold per Hour Tracker pins one row that adds up the session's loot.
--  Chat lines are matched against the client's own localized format strings,
--  so this works in every client language.
-------------------------------------------------------------------------------
local _, module = ...
-- The options page pool's table (made by the core, filled in place when the
-- options addon loads): the settings preview reads a dress generation from
-- it at call time.
local POOL = EllesmereUI._Pool

local FADE_IN = 0.35
local FADE_OUT = 0.8
local SLIDE = 24 -- px a new row glides in from the left
local CALLOUT_GAP = 6 -- Icon Tray: space between the name row and the tiles
local MONEY_ICON = "Interface\\Icons\\INV_Misc_Coin_02"
local REP_ICON = "Interface\\Icons\\INV_Misc_Note_02"
local SKILL_ICON = "Interface\\Icons\\INV_Misc_Book_08"
local RATE_FLOOR = 60 -- seconds: the shortest session the hourly rate divides by
local RATE_TICK = 60 -- seconds between repaints of the hourly rate

-- Settings live in EllesmereUIDB.lootFeed; unset keys read these.
local DEFAULTS = {
    enabled = false,
    items = true, money = true, reputation = true, currency = true, skills = true,
    minQuality = 0, showIlvl = true, showPrice = true,
    tracker = false, auctionPrices = false,
    -- BOX: bordered rows, BAR: accent bar on a fading background, TRAY: icon
    -- tiles with a name row, TOAST: framed plates.
    style = "BAR",
    width = 300, rowHeight = 36, spacing = 2, maxRows = 6, duration = 5, grow = "UP",
    textSize = 13, barWidth = 3,
    bgTexture = "none", bgR = 0.05, bgG = 0.05, bgB = 0.05, bgA = 0.3,
    borderSize = 1, borderR = 0, borderG = 0, borderB = 0, qualityBorder = true,
    -- An unset borderTexture keeps the original pixel borders.
    borderBehind = false, separator = false,
}
local F = module.Feature("lootFeed", DEFAULTS,
    { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -320, y = 260 })
local Get, Cfg, Enabled = F.Get, F.Cfg, F.Enabled

local anchor, events
local active = {} -- shown rows, newest first
local pool = {}
-- A row set: the frame its rows are laid out in, its rows (newest first) and
-- the Icon Tray name row. The live feed and the options preview are one each.
local feed = { rows = active }

-- v when it is a readable value of type kind (never a secret one).
local function Plain(v, kind)
    if not issecretvalue(v) and type(v) == kind then return v end
end

-------------------------------------------------------------------------------
--  Chat line matching
-------------------------------------------------------------------------------
-- A Blizzard format string as a Lua pattern with one capture per %s / %d.
-- swap marks a format that puts its second argument first (%2$d before %1$s);
-- the formats read here have at most two.
local function Compile(fmt, anchored)
    local parts, i, first = {}, 1, nil
    while true do
        local s, e, pos, kind = fmt:find("%%(%d?)%$?([sd])", i)
        parts[#parts + 1] = (fmt:sub(i, s and s - 1):gsub("[%^%$%(%)%.%[%]%*%+%-%?%%]", "%%%0"))
        if not s then break end
        first = first or tonumber(pos)
        parts[#parts + 1] = kind == "d" and "(%d+)" or "(.-)"
        i = e + 1
    end
    local p = table.concat(parts)
    return { pat = anchored and "^" .. p .. "$" or p, swap = first == 2 }
end

-- The captures of text against the global format string key, in argument
-- order: the whole line, or anywhere in it when loose. Compiled once per key;
-- a key the client lacks never matches.
local compiled = {}
local function Match(key, text, loose)
    local c = compiled[key]
    if c == nil then
        local fmt = _G[key]
        c = type(fmt) == "string" and fmt ~= "" and Compile(fmt, not loose) or false
        compiled[key] = c
    end
    if not c then return end
    local a, b = text:match(c.pat)
    if c.swap then return b, a end
    return a, b
end

-------------------------------------------------------------------------------
--  Rows
-------------------------------------------------------------------------------
local function StyleFont(fs, size)
    EllesmereUI.ApplyModuleFont(fs, nil, size, "essentials")
end

-- Toast plates draw a frame 1 px outside the row, so they need more space.
local function Gap()
    return Get("spacing") + (Get("style") == "TOAST" and 2 or 0)
end

-- Space the pinned tracker row takes at the anchor end of the feed.
local function Pin()
    if not Get("tracker") then return 0 end
    return Get("rowHeight") + (Get("style") == "TRAY" and CALLOUT_GAP or Gap())
end

-- Icon Tray: tiles per line and lines needed for n tiles.
local function TrayGrid(n)
    local gap = Get("spacing")
    local step = Get("rowHeight") + gap
    local cols = math.max(1, math.floor((Get("width") + gap) / step))
    return cols, math.ceil(n / cols)
end

-- Height of a set with n rows (Max Rows when nil) plus the tracker row.
local function AnchorHeight(n)
    local h = Get("rowHeight")
    local pin = Pin()
    n = n or Get("maxRows")
    if Get("style") == "TRAY" then
        local _, lines = TrayGrid(n)
        local gap = Get("spacing")
        return pin + h + CALLOUT_GAP + lines * (h + gap) - gap
    end
    local gap = Gap()
    return pin + n * (h + gap) - gap
end

local function Accent()
    local c = EllesmereUI.ELLESMERE_GREEN
    if c then return c.r, c.g, c.b end
    return 0.05, 0.82, 0.62
end

-- Gradient end colours, refilled for each paint (SetGradient copies them).
local gradFrom, gradTo = CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0)

local backgroundTextures
local function SetBackgroundTexture(tex)
    local key = Get("bgTexture")
    if key == "none" then
        tex:SetColorTexture(1, 1, 1, 1)
        return
    end
    if not backgroundTextures then backgroundTextures = EllesmereUI.BuildBarTextureTables() end
    tex:SetTexture(EllesmereUI.ResolveTexturePath(backgroundTextures, key, "Interface\\Buttons\\WHITE8x8"))
    tex:SetVertexColor(1, 1, 1, 1)
end

-- Solid, or a two-colour fade to transparent (BAR).
local function PaintBackground(tex, fade)
    local r, g, b, a = Get("bgR"), Get("bgG"), Get("bgB"), Get("bgA")
    SetBackgroundTexture(tex)
    gradFrom:SetRGBA(r, g, b, a)
    gradTo:SetRGBA(r, g, b, fade and 0 or a)
    tex:SetGradient("HORIZONTAL", gradFrom, gradTo)
end

-- Item rows take their quality colour when quality colouring is on;
-- everything else the accent (BAR, the Icon Tray name row) or the border colour.
local function RowColor(d, accent)
    if d.border and Get("qualityBorder") then return d.border.r, d.border.g, d.border.b end
    if accent then return Accent() end
    return Get("borderR"), Get("borderG"), Get("borderB")
end

local TOAST_GOLD = { 0.69, 0.54, 0.23 }
local TOAST_EDGE = { 0.35, 0.27, 0.14 } -- icon frame of rows without a quality
local TOAST_TOP = { 0.19, 0.14, 0.09 }
local TOAST_BOTTOM = { 0.055, 0.04, 0.024 }

-- TOAST: a black 1 px frame around the gold one, with a gold stud at each
-- end. Made the first time a row is drawn as a toast.
local function ToastChrome(r)
    if r.outer then return r.outer end
    local o = CreateFrame("Frame", nil, r)
    o:SetPoint("TOPLEFT", -1, 1)
    o:SetPoint("BOTTOMRIGHT", 1, -1)
    EllesmereUI.PP.CreateBorder(o, 0, 0, 0, 1, 1, "OVERLAY", 1)
    for _, side in ipairs({ "LEFT", "RIGHT" }) do
        local edge = o:CreateTexture(nil, "OVERLAY", nil, 3)
        edge:SetColorTexture(0, 0, 0, 1)
        edge:SetSize(8, 8)
        edge:SetRotation(math.rad(45))
        edge:SetPoint("CENTER", o, side)
        local stud = o:CreateTexture(nil, "OVERLAY", nil, 4)
        stud:SetColorTexture(0.85, 0.70, 0.34, 1)
        stud:SetSize(6, 6)
        stud:SetRotation(math.rad(45))
        stud:SetPoint("CENTER", edge)
    end
    r.outer = o
    return o
end

-- The tracker row is never a tile: the Icon Tray draws it as an accent bar.
local function RowStyle(r)
    local style = Get("style")
    return r.pinned and style == "TRAY" and "BAR" or style
end

local function LayoutSeparator(sep)
    EllesmereUI.PlaceBorderDividerV(sep.tex, sep, sep.right, true, sep.key, sep.size, sep.px, sep:GetEffectiveScale())
end

local function StyleSeparator(r, style, size, tex, px)
    local sep = r.separator
    local callout = style == "CALLOUT"
    if (style ~= "BOX" and not callout) or not Get("separator") or size <= 0
            or (callout and Get("barWidth") <= 0) or not EllesmereUI.GetBorderCompanion(tex, "sepV") then
        if sep then sep:Hide(); EllesmereUI.RegisterPxReapply(sep, nil) end
        return
    end
    if not sep then
        sep = CreateFrame("Frame", nil, r)
        sep.tex = sep:CreateTexture(nil, "OVERLAY")
        r.separator = sep
    end
    sep:ClearAllPoints()
    sep:SetAllPoints(callout and r.bar or r.icon)
    sep:SetFrameLevel(r:GetFrameLevel() + 3)
    sep.key, sep.size, sep.px, sep.right = tex, size, px, callout
    sep.tex:SetVertexColor(RowColor(r.data, false))
    LayoutSeparator(sep)
    sep:Show()
    EllesmereUI.RegisterPxReapply(sep, px and LayoutSeparator or nil)
end

local function StyleBorder(r, style)
    local PP = EllesmereUI.PP
    local size, tex, host = Get("borderSize"), Get("borderTexture"), r.lootBorder
    local px = tex and EllesmereUI.BorderPx(Get("borderSizePx"), size, tex)
    -- The white Pixels artwork takes the item's quality colour without a baked-in tint.
    if tex == "pixels-textured" and r.data.border and Get("qualityBorder") then tex = "pixels" end
    if Get("separator") or r.separator then StyleSeparator(r, style, size, tex, px) end
    if size <= 0 or ((style == "BAR" or style == "CALLOUT") and not tex) then
        PP.HideBorder(r)
        if host then EllesmereUI.HideBorderStyle(host); host:Hide() end
        return
    end
    local br, bg, bb
    if style == "TOAST" then
        br, bg, bb = TOAST_GOLD[1], TOAST_GOLD[2], TOAST_GOLD[3]
    else
        br, bg, bb = RowColor(r.data, false)
    end
    if not tex or style == "TOAST" then
        if host then EllesmereUI.HideBorderStyle(host); host:Hide() end
        PP.UpdateBorder(r, size, br, bg, bb, 1)
        PP.ShowBorder(r)
        return
    end
    PP.HideBorder(r)
    if not host then
        host = CreateFrame("Frame", nil, r)
        r.lootBorder = host
    end
    host:ClearAllPoints()
    host:SetAllPoints(style == "BAR" and r.icon or r)
    host:SetFrameLevel(Get("borderBehind") and math.max(0, r:GetFrameLevel() - 1) or r:GetFrameLevel() + 1)
    EllesmereUI.ApplyBorderStyle(host, size, br, bg, bb, 1, tex,
        Get("borderTextureOffset"), Get("borderTextureOffsetY"), Get("borderTextureShiftX"), Get("borderTextureShiftY"),
        nil, nil, nil, px)
end

local function StyleRow(r)
    local h, size, style = Get("rowHeight"), Get("textSize"), RowStyle(r)
    local tray, bar, toast = style == "TRAY", style == "BAR", style == "TOAST"
    r:SetSize(tray and h or Get("width"), h)
    r.icon:ClearAllPoints()
    if bar then
        local bw = Get("barWidth")
        r.bar:SetWidth(math.max(bw, 1))
        r.bar:SetShown(bw > 0)
        r.icon:SetSize(h - 8, h - 8)
        r.icon:SetPoint("LEFT", bw > 0 and bw + 5 or 4, 0)
    elseif toast then
        r.bar:Hide()
        r.icon:SetSize(h - 10, h - 10)
        r.icon:SetPoint("LEFT", 6, 0)
    else
        r.bar:Hide()
        r.icon:SetSize(h, h)
        r.icon:SetPoint("LEFT")
    end
    -- Legacy BAR icon: 1 px black; TOAST: 2 px quality colour (set by Fill).
    local edge = toast and 2 or 1
    r.iconBg:ClearAllPoints()
    r.iconBg:SetPoint("TOPLEFT", r.icon, "TOPLEFT", -edge, edge)
    r.iconBg:SetPoint("BOTTOMRIGHT", r.icon, "BOTTOMRIGHT", edge, -edge)
    if bar then r.iconBg:SetColorTexture(0, 0, 0, 1) end
    r.iconBg:SetShown((bar and not Get("borderTexture")) or toast)
    if toast then
        ToastChrome(r):SetShown(Get("borderSize") > 0)
        local a = Get("bgA")
        SetBackgroundTexture(r.bg)
        gradFrom:SetRGBA(TOAST_BOTTOM[1], TOAST_BOTTOM[2], TOAST_BOTTOM[3], a)
        gradTo:SetRGBA(TOAST_TOP[1], TOAST_TOP[2], TOAST_TOP[3], a)
        r.bg:SetGradient("VERTICAL", gradFrom, gradTo)
    else
        if r.outer then r.outer:Hide() end
        if not tray then PaintBackground(r.bg, bar) end
    end
    r.bg:SetShown(not tray)
    r.name:SetShown(not tray)
    r.value:SetShown(not tray)
    r.badge:SetShown(tray)
    -- Second line: game gold on toasts, a quiet grey on bars.
    if toast then
        r.sub:SetTextColor(1, 0.82, 0)
    elseif bar then
        r.sub:SetTextColor(0.7, 0.7, 0.7)
    else
        r.sub:SetTextColor(1, 1, 1)
    end
    StyleFont(r.name, size)
    StyleFont(r.value, size)
    StyleFont(r.sub, size - 2)
    StyleFont(r.badge, size - 1)
    r.fade.alpha:SetStartDelay(Get("duration"))
end

local function Text(r)
    local fs = r:CreateFontString(nil, "OVERLAY")
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

-- Icon Tray: the newest gain's name row above the tiles (on top with grow
-- Down). It is a child of that gain's tile, so it fades with it.
local function ShowCallout(set)
    local c = set.callout
    if not c then
        c = CreateFrame("Frame", nil, set.frame)
        c.bg = c:CreateTexture(nil, "BACKGROUND")
        c.bg:SetAllPoints()
        c.bar = c:CreateTexture(nil, "ARTWORK")
        c.bar:SetPoint("TOPRIGHT")
        c.bar:SetPoint("BOTTOMRIGHT")
        c.name, c.sub, c.value = Text(c), Text(c), Text(c)
        c.value:SetJustifyH("RIGHT")
        set.callout = c
    end
    local r = set.rows[1]
    local d = r.data
    local h, bw, size = Get("rowHeight"), Get("barWidth"), Get("textSize")
    local pin = Pin()
    c:SetParent(r)
    c:SetSize(Get("width"), h)
    c:ClearAllPoints()
    if Get("grow") == "UP" then
        local _, lines = TrayGrid(#set.rows)
        local gap = Get("spacing")
        c:SetPoint("BOTTOMRIGHT", set.frame, "BOTTOMRIGHT", 0, pin + lines * (h + gap) - gap + CALLOUT_GAP)
    else
        c:SetPoint("TOPRIGHT", set.frame, "TOPRIGHT", 0, -pin)
    end
    PaintBackground(c.bg, false)
    c.bar:SetWidth(math.max(bw, 1))
    c.bar:SetShown(bw > 0)
    c.bar:SetColorTexture(RowColor(d, true))
    if Get("borderTexture") or c.lootBorder then
        c.data = d
        StyleBorder(c, "CALLOUT")
    end
    StyleFont(c.name, size)
    StyleFont(c.value, size)
    StyleFont(c.sub, size - 2)
    c.name:SetText(d.text)
    c.value:SetText(d.value or "")
    c.sub:SetText(d.sub or "")
    c.sub:SetShown(d.sub ~= nil)
    c.name:ClearAllPoints()
    c.sub:ClearAllPoints()
    c.value:ClearAllPoints()
    local right = -(bw + 8)
    if d.sub then
        -- Name across the top, progress and value below it.
        c.name:SetPoint("BOTTOMLEFT", c, "LEFT", 8, 1)
        c.name:SetPoint("RIGHT", c, "RIGHT", right, 0)
        c.value:SetPoint("TOPRIGHT", c, "RIGHT", right, -1)
        c.sub:SetPoint("TOPLEFT", c, "LEFT", 8, -1)
        c.sub:SetPoint("RIGHT", c.value, "LEFT", -8, 0)
    else
        c.value:SetPoint("RIGHT", c, "RIGHT", right, 0)
        c.name:SetPoint("LEFT", c, "LEFT", 8, 0)
        c.name:SetPoint("RIGHT", c.value, "LEFT", -8, 0)
    end
    c:Show()
end

local function Layout(set)
    set = set or feed
    local frame = set.frame
    local up = Get("grow") == "UP"
    local tray = Get("style") == "TRAY"
    local step = Get("rowHeight") + (tray and Get("spacing") or Gap())
    local cols = TrayGrid(1)
    local below = Get("rowHeight") + CALLOUT_GAP -- grow Down: tiles start under the name row
    local pin = Pin() -- the rows start past the tracker row
    for i, r in ipairs(set.rows) do
        r:ClearAllPoints()
        if tray then
            local col, line = (i - 1) % cols, math.floor((i - 1) / cols)
            if up then
                r:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -col * step, pin + line * step)
            else
                r:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -col * step, -(pin + below + line * step))
            end
        elseif up then
            r:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, pin + (i - 1) * step)
        else
            r:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(pin + (i - 1) * step))
        end
    end
    if tray and set.rows[1] then
        ShowCallout(set)
    elseif set.callout then
        set.callout:Hide()
    end
end

local function Unlist(r)
    for i = #active, 1, -1 do
        if active[i] == r then table.remove(active, i) end
    end
end

local function Release(r)
    Unlist(r)
    r.show:Stop()
    r.fade:Stop()
    r:Hide()
    r.key, r.data = nil, nil
    pool[#pool + 1] = r
    Layout()
end

-- Starts the wait-then-fade-out, unless the row is still fading in (its
-- end starts it) or hovered (leaving starts it).
-- Preview rows never fade.
local function ArmFade(r)
    if r.preview or r.show:IsPlaying() then return end
    r.fade:Stop()
    r:SetAlpha(1)
    if not r:IsMouseOver() then r.fade:Play() end
end

-- Hover shows the item tooltip and holds the fade. Icon Tray tiles show no
-- text, so for them the tooltip carries it.
local function RowEnter(r)
    if not r.show:IsPlaying() then
        r.fade:Stop()
        r:SetAlpha(1)
    end
    local d = r.data
    if not d then return end
    if d.link then
        GameTooltip:SetOwner(r, "ANCHOR_LEFT")
        GameTooltip:SetHyperlink(d.link)
        GameTooltip:Show()
    elseif Get("style") == "TRAY" then
        local text = d.text
        if d.sub then text = text .. "\n" .. EllesmereUI.COLOR_CODES.DIM .. d.sub .. "|r" end
        if d.value then text = text .. "\n" .. d.value end
        r.tip = true
        EllesmereUI.ShowWidgetTooltip(r, text, { anchor = "left" })
    end
end

local function RowLeave(r)
    if GameTooltip:IsOwned(r) then GameTooltip:Hide() end
    if r.tip then
        r.tip = nil
        EllesmereUI.HideWidgetTooltip()
    end
    ArmFade(r)
end

local function ShowDone(g) ArmFade(g:GetParent()) end
local function FadeDone(g) Release(g:GetParent()) end

-- One animation of group g: step order, seconds, easing.
local function Anim(g, kind, order, secs, smoothing)
    local a = g:CreateAnimation(kind)
    a:SetOrder(order)
    a:SetDuration(secs)
    if smoothing then a:SetSmoothing(smoothing) end
    return a
end

local function NewRow(parent)
    local r = CreateFrame("Frame", nil, parent or anchor)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bar = r:CreateTexture(nil, "ARTWORK")
    r.bar:SetPoint("TOPLEFT")
    r.bar:SetPoint("BOTTOMLEFT")
    r.icon = r:CreateTexture(nil, "ARTWORK", nil, 1)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- trim the icon frame
    r.iconBg = r:CreateTexture(nil, "ARTWORK")
    r.badge = r:CreateFontString(nil, "OVERLAY")
    r.badge:SetPoint("BOTTOMRIGHT", -2, 2)
    r.name, r.sub, r.value = Text(r), Text(r), Text(r)
    r.value:SetJustifyH("RIGHT")
    r.value:SetPoint("RIGHT", -6, 0)
    r.sub:SetPoint("TOPLEFT", r.icon, "RIGHT", 6, -1)
    r.sub:SetPoint("RIGHT", r.value, "LEFT", -8, 0)
    EllesmereUI.PP.CreateBorder(r, 0, 0, 0, 1, 1, "OVERLAY", 2)
    -- Hover only: clicks pass through.
    r:EnableMouseMotion(true)
    r:SetScript("OnEnter", RowEnter)
    r:SetScript("OnLeave", RowLeave)
    -- Fade in while gliding in: a zero-length jump left, then the way back.
    r.show = r:CreateAnimationGroup()
    Anim(r.show, "Translation", 1, 0):SetOffset(-SLIDE, 0)
    Anim(r.show, "Translation", 2, FADE_IN, "OUT"):SetOffset(SLIDE, 0)
    local appear = Anim(r.show, "Alpha", 2, FADE_IN, "OUT")
    appear:SetFromAlpha(0)
    appear:SetToAlpha(1)
    r.show:SetScript("OnFinished", ShowDone)
    -- Wait (the start delay, set by StyleRow), fade out, free the row.
    r.fade = r:CreateAnimationGroup()
    r.fade.alpha = Anim(r.fade, "Alpha", 1, FADE_OUT, "IN_OUT")
    r.fade.alpha:SetFromAlpha(1)
    r.fade.alpha:SetToAlpha(0)
    r.fade:SetScript("OnFinished", FadeDone)
    return r
end

-- Fills a row from its data: icon, text (first line), sub (second line,
-- optional), value (right side, optional), badge (Icon Tray tile text),
-- border (quality colour, optional). Box rows keep their one-line form
-- (flat) and show no quest line.
local function Fill(r)
    local d, style = r.data, RowStyle(r)
    local text, sub, value = d.text, d.sub or d.questSub, d.value
    if style == "BOX" then
        sub = not d.flat and d.sub or nil
        if d.flat then text, value = d.flat, nil end
    elseif style == "TRAY" then
        sub = nil
    end
    r.icon:SetTexture(d.icon)
    r.name:SetText(text)
    r.sub:SetText(sub or "")
    r.sub:SetShown(sub ~= nil)
    r.value:SetText(value or "")
    r.badge:SetText(d.badge or "")
    r.name:ClearAllPoints()
    r.name:SetPoint("RIGHT", r.value, "LEFT", -8, 0)
    if sub then
        r.name:SetPoint("BOTTOMLEFT", r.icon, "RIGHT", 6, 1)
    else
        r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    end
    if style == "BAR" then r.bar:SetColorTexture(RowColor(d, true)) end
    if style == "TOAST" then
        if d.border and Get("qualityBorder") then
            r.iconBg:SetColorTexture(d.border.r, d.border.g, d.border.b, 1)
        else
            r.iconBg:SetColorTexture(TOAST_EDGE[1], TOAST_EDGE[2], TOAST_EDGE[3], 1)
        end
    end
    StyleBorder(r, style)
end

local function FindRow(key)
    for _, r in ipairs(active) do
        if r.key == key then return r end
    end
end

-- While the options preview collects its samples, the Show functions add
-- their rows to this list (newest first) instead of the feed.
local collect

-- amount plus what the row showing key already adds up to.
local function Total(key, amount)
    if collect then return amount end
    local r = FindRow(key)
    return amount + (r and r.data.amount or 0)
end

-- Shows data under key: the row already showing key is refilled, moved to the
-- front and its fade restarted; otherwise a row is taken (the oldest one when
-- all maxRows are in use) and fades in.
local function Push(key, data)
    local r = FindRow(key)
    local fresh = not r
    if r then
        Unlist(r)
    else
        while #active >= Get("maxRows") do Release(active[#active]) end
        r = table.remove(pool) or NewRow()
        StyleRow(r)
    end
    table.insert(active, 1, r)
    r.key, r.data = key, data
    Fill(r)
    Layout()
    if fresh then
        r.fade:Stop()
        r:SetAlpha(0)
        r:Show()
        r.show:Play()
    else
        ArmFade(r)
    end
end

local function Emit(key, data)
    if collect then
        collect[#collect + 1] = data
    else
        Push(key, data)
    end
end

-------------------------------------------------------------------------------
--  Sources
-------------------------------------------------------------------------------
local function Money(copper)
    return C_CurrencyInfo.GetCoinTextureString(copper, Get("textSize"))
end

-- The largest coin only, for an Icon Tray badge.
local function ShortMoney(copper)
    local unit = copper >= 10000 and 10000 or copper >= 100 and 100 or 1
    return Money(copper - copper % unit)
end

-------------------------------------------------------------------------------
--  Gold per Hour Tracker: looted coin plus the value of looted items, since
--  the first loot of the session (a reload starts a new one). One pinned row
--  shows the hourly rate, the total and the session's length; Ctrl + Click on
--  its Reset Session button clears it.
-------------------------------------------------------------------------------
local session = { coin = 0, items = 0 } -- copper; start: GetTime() of the first loot
local summary, clock

-- 23m, 1h 5m: started minutes, so a session that has begun never reads 0m
local function Duration(seconds)
    local minutes = math.ceil(seconds / 60)
    if minutes < 60 then return string.format(EllesmereUI.L("%dm"), minutes) end
    return string.format(EllesmereUI.L("%dh %dm"), math.floor(minutes / 60), minutes % 60)
end

-- The hourly rate leads; the session's total and length follow, dimmed.
-- elapsed: seconds since the first loot (0 before it).
local function PaintSummary(r, total, elapsed)
    local d = r.data
    d.text = EllesmereUI.Lf("%s / hr", Money(math.floor(total / math.max(elapsed, RATE_FLOOR) * 3600)))
    d.sub = EllesmereUI.Lf("%s in %s", Money(total), Duration(elapsed))
    Fill(r)
end

local function FillSummary()
    PaintSummary(summary, session.coin + session.items, session.start and GetTime() - session.start or 0)
end

-- The rate falls while nothing is looted, so the row is repainted once a
-- minute while it is on screen with a running session.
local function SyncClock()
    local run = session.start and summary and summary:IsVisible()
    if run and not clock then
        clock = C_Timer.NewTicker(RATE_TICK, FillSummary)
    elseif not run and clock then
        clock:Cancel()
        clock = nil
    end
end

local function Earn(kind, copper)
    session.start = session.start or GetTime()
    session[kind] = session[kind] + copper
    if summary then FillSummary() end
    SyncClock()
end

-- What Auctionator last saw the item listed for, when that addon is loaded
-- and has a price.
local function AuctionPrice(link)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    local get = api and api.GetAuctionPriceByItemLink
    if not get then return end
    local ok, price = pcall(get, "EllesmereUI", link)
    if ok and type(price) == "number" and price > 0 then return price end
end

-- What one of the item counts for: nothing for a quest-bound item, the vendor
-- price for one that binds when picked up (it cannot be auctioned) and for
-- every item with Use Auctionator Prices off.
local function ItemValue(link, sellPrice, bindType)
    if bindType == Enum.ItemBind.Quest then return 0 end
    if bindType == Enum.ItemBind.OnAcquire then return sellPrice or 0 end
    return Get("auctionPrices") and AuctionPrice(link) or sellPrice or 0
end

local RESET_DIM = 0.7

local function ResetEnter(b)
    b.tip = true
    EllesmereUI.ShowWidgetTooltip(b, EllesmereUI.L("Ctrl + Click to reset the session"), { anchor = "left" })
end

local function ResetLeave(b)
    if not b.tip then return end
    b.tip = nil
    EllesmereUI.HideWidgetTooltip()
end

-- The button takes the mouse only while Ctrl is held (and lights up), so the
-- row never blocks a click or a camera drag. Only a change of Ctrl (not Shift
-- or Alt) repaints it.
local function ResetArm(b)
    local on = IsControlKeyDown()
    if on == b.armed then return end
    b.armed = on
    local c = on and 1 or RESET_DIM
    b:EnableMouse(on)
    b.text:SetTextColor(c, c, c)
    if not on then ResetLeave(b) end
end

-- The button shows and hides with the row: Ctrl is watched, and the minute
-- clock runs, only while the row is on screen.
local function ResetShow(b)
    b:RegisterEvent("MODIFIER_STATE_CHANGED")
    ResetArm(b)
    if summary and session.start then FillSummary() end
    SyncClock()
end

local function ResetHide(b)
    b:UnregisterEvent("MODIFIER_STATE_CHANGED")
    ResetLeave(b)
    SyncClock()
end

local function ResetClick()
    if not IsControlKeyDown() then return end
    session.coin, session.items, session.start = 0, 0, nil
    FillSummary()
    SyncClock()
end

-- The Reset Session button ends the second line. The row takes no mouse. With
-- a parent it is the options preview's sample, whose button never does either.
local function NewSummary(parent)
    local r = NewRow(parent)
    r.pinned = true
    r.data = { icon = MONEY_ICON }
    local reset = CreateFrame("Button", nil, r)
    reset:SetPoint("TOPRIGHT", r, "RIGHT", -6, -1)
    reset.text = Text(reset)
    reset.text:SetPoint("RIGHT")
    reset.text:SetTextColor(RESET_DIM, RESET_DIM, RESET_DIM)
    r:SetScript("OnEnter", nil)
    r:SetScript("OnLeave", nil)
    r:EnableMouse(false)
    reset:EnableMouse(false)
    if not parent then
        reset:SetScript("OnEnter", ResetEnter)
        reset:SetScript("OnLeave", ResetLeave)
        reset:SetScript("OnClick", ResetClick)
        reset:SetScript("OnEvent", ResetArm)
        reset:SetScript("OnShow", ResetShow)
        reset:SetScript("OnHide", ResetHide)
        ResetShow(reset)
    end
    r.reset = reset
    r.sub:ClearAllPoints()
    r.sub:SetPoint("TOPLEFT", r.icon, "RIGHT", 6, -1)
    r.sub:SetPoint("RIGHT", reset, "LEFT", -8, 0)
    return r
end

-- Styles a tracker row and pins it to the anchor end of its set.
local function PlaceSummary(r)
    StyleRow(r)
    -- One text size: the second line is set apart by its tone alone.
    local reset, size = r.reset, Get("textSize")
    StyleFont(r.sub, size)
    r.sub:SetTextColor(RESET_DIM, RESET_DIM, RESET_DIM)
    StyleFont(reset.text, size)
    reset.text:SetText(EllesmereUI.L("Reset Session"))
    reset:SetSize(reset.text:GetStringWidth(), reset.text:GetStringHeight())
    r:ClearAllPoints()
    r:SetPoint(Get("grow") == "UP" and "BOTTOMLEFT" or "TOPLEFT")
    r:Show()
end

-- Built the first time the tracker is on.
local function UpdateSummary()
    if not Get("tracker") then
        if summary then summary:Hide() end
        SyncClock()
        return
    end
    summary = summary or NewSummary()
    PlaceSummary(summary)
    FillSummary()
    SyncClock()
end

-- looted: a real loot line (not a preview sample). earned: one the tracker
-- counts (looted or won, not bought or a quest reward), even when item rows
-- are off or the item is below Minimum Quality.
local function ShowItem(link, count, retried, looted, earned)
    local name, _, quality, itemLevel, _, _, _, _, _, icon, sellPrice, classID, _, bindType = C_Item.GetItemInfo(link)
    if not name then
        -- Not cached yet: try again once the client has it. Only once: the
        -- client also calls back when the item fails to load.
        if not retried then
            Item:CreateFromItemLink(link):ContinueOnItemLoad(function() ShowItem(link, count, true, looted, earned) end)
        end
        return
    end
    local each -- what one counts for, priced only when the tracker or the row needs it
    if looted then
        if earned and Get("tracker") then
            each = ItemValue(link, sellPrice, bindType)
            Earn("items", each * count)
        end
        if not Get("items") then return end
    end
    if (quality or 0) < Get("minQuality") then return end
    local key = "item:" .. link
    count = Total(key, count)
    local color = ITEM_QUALITY_COLORS[quality or 1] or ITEM_QUALITY_COLORS[1]
    local text = color.hex .. name .. "|r"
    if count > 1 then text = count .. "x " .. text end
    local sub, questSub
    if Get("showIlvl") and (classID == Enum.ItemClass.Weapon or classID == Enum.ItemClass.Armor) then
        local ilvl = C_Item.GetDetailedItemLevelInfo(link) or itemLevel
        if ilvl and ilvl > 0 then sub = EllesmereUI.Lf("ilvl: %d", ilvl) end
    elseif classID == Enum.ItemClass.Questitem and ITEM_BIND_QUEST then
        questSub = "|cffffd100" .. ITEM_BIND_QUEST .. "|r"
    end
    -- The row shows the tracker's price; the plain vendor one with Use Auctionator Prices off.
    local value
    if Get("showPrice") then
        local price = Get("auctionPrices") and (each or ItemValue(link, sellPrice, bindType)) or sellPrice or 0
        if price > 0 then value = Money(price * count) end
    end
    Emit(key, { icon = icon, text = text, sub = sub, questSub = questSub, value = value, border = color, link = link,
        amount = count, badge = count > 1 and count or nil })
end

local function ShowMoney(copper)
    copper = Total("money", copper)
    Emit("money", { icon = MONEY_ICON, text = EllesmereUI.L("Money"), value = Money(copper), amount = copper,
        badge = ShortMoney(copper) })
end

-- A faction's or skill line's data by name. ids keeps the id a scan of the
-- (expanded) list found, so later lookups go straight to it.
local factionIDs, skillIDs = {}, {}
local function Lookup(ids, name, byID, count, byIndex, idKey)
    local id = ids[name]
    if id then return byID(id) end
    for i = 1, count() do
        local d = byIndex(i)
        if d and d.name == name then
            ids[name] = d[idKey]
            return d
        end
    end
end

-- With the progress within the current standing.
local function ShowReputation(faction, delta)
    local key = "rep:" .. faction
    delta = Total(key, delta)
    local change = (delta >= 0 and "|cff00ff00+" or "|cffff4040") .. delta .. "|r"
    local flat = change .. " " .. faction
    local d = Lookup(factionIDs, faction, C_Reputation.GetFactionDataByID, C_Reputation.GetNumFactions,
        C_Reputation.GetFactionDataByIndex, "factionID")
    local progress
    if d then
        progress = string.format("%s / %s", BreakUpLargeNumbers(d.currentStanding - d.currentReactionThreshold),
            BreakUpLargeNumbers(d.nextReactionThreshold - d.currentReactionThreshold))
        flat = flat .. " (" .. progress .. ")"
    end
    Emit(key, { icon = REP_ICON, text = faction, sub = progress, value = change, flat = flat, badge = change,
        amount = delta })
end

-- With the total held, red at the cap.
local function ShowCurrency(id, change)
    local info = C_CurrencyInfo.GetCurrencyInfo(id)
    if not (info and info.name) then return end
    local key = "currency:" .. id
    change = Total(key, change)
    local total = BreakUpLargeNumbers(info.quantity)
    if info.maxQuantity > 0 then
        total = total .. " / " .. BreakUpLargeNumbers(info.maxQuantity)
        if info.quantity >= info.maxQuantity then total = "|cffff4040" .. total .. "|r" end
    end
    local text = change .. "x " .. info.name
    Emit(key, { icon = info.iconFileID, text = text, sub = total, flat = text .. " (" .. total .. ")", badge = change,
        amount = change })
end

local function ShowSkill(skill, rank)
    local d = Lookup(skillIDs, skill, C_SkillInfo.GetSkillLineInfoByID, C_SkillInfo.GetNumSkillLines,
        C_SkillInfo.GetSkillLineInfo, "skillID")
    local max = d and d.maxRank > 0 and (" / " .. d.maxRank) or ""
    Emit("skill:" .. skill, { icon = SKILL_ICON, text = skill, value = rank .. max, badge = rank,
        flat = skill .. " " .. EllesmereUI.COLOR_CODES.WHITE .. rank .. max .. "|r" })
end

-- Own loot only: the *_SELF lines, the multiple-item formats (link and count)
-- first, since the single-item ones match their lines too. The flag: the
-- tracker counts it (a pushed item, bought or a quest reward, shows but is no
-- gain).
local ITEM_KEYS = {
    { "LOOT_ITEM_SELF_MULTIPLE", true }, { "LOOT_ITEM_SELF", true },
    { "LOOT_ITEM_PUSHED_SELF_MULTIPLE", false }, { "LOOT_ITEM_PUSHED_SELF", false },
    { "LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE", true }, { "LOOT_ITEM_BONUS_ROLL_SELF", true },
}

local function OnLoot(text)
    for _, k in ipairs(ITEM_KEYS) do
        local link, count = Match(k[1], text)
        if link then
            if link:find("|Hitem:", 1, true) then ShowItem(link, tonumber(count) or 1, nil, true, k[2]) end
            return
        end
    end
end

-- Money lines spell out each coin with the client's own "%d Gold" etc.
local COIN_KEYS = { GOLD_AMOUNT = 10000, SILVER_AMOUNT = 100, COPPER_AMOUNT = 1 }
local function OnMoney(text)
    local copper = 0
    for key, mult in pairs(COIN_KEYS) do
        local n = Match(key, text, true)
        if n then copper = copper + tonumber(n) * mult end
    end
    if copper <= 0 then return end
    if Get("tracker") then Earn("coin", copper) end
    if Get("money") then ShowMoney(copper) end
end

local function OnFaction(text)
    local faction, amount = Match("FACTION_STANDING_INCREASED", text)
    if faction then return ShowReputation(faction, tonumber(amount)) end
    faction, amount = Match("FACTION_STANDING_DECREASED", text)
    if faction then return ShowReputation(faction, -tonumber(amount)) end
end

local function OnSkill(text)
    local skill, rank = Match("SKILL_RANK_UP", text)
    if skill then ShowSkill(skill, tonumber(rank)) end
end

-- tracked: the tracker counts these, so it listens while their rows are off.
local CHAT_EVENTS = {
    CHAT_MSG_LOOT = { setting = "items", handler = OnLoot, tracked = true },
    CHAT_MSG_MONEY = { setting = "money", handler = OnMoney, tracked = true },
    CHAT_MSG_COMBAT_FACTION_CHANGE = { setting = "reputation", handler = OnFaction },
    CHAT_MSG_SKILL = { setting = "skills", handler = OnSkill },
}

local function OnEvent(_, event, ...)
    local chat = CHAT_EVENTS[event]
    if chat then
        local text = Plain((...), "string")
        if text then chat.handler(text) end
    elseif event == "CURRENCY_DISPLAY_UPDATE" then
        local id, _, change = ...
        id, change = Plain(id, "number"), Plain(change, "number")
        if id and change and change > 0 then ShowCurrency(id, change) end
    end
end

-------------------------------------------------------------------------------
--  Setup
-------------------------------------------------------------------------------
local RefreshPreview

local function ApplyStyle()
    RefreshPreview()
    if not anchor then return end
    anchor:SetSize(Get("width"), AnchorHeight())
    -- Pooled rows are styled when Push takes them.
    for _, r in ipairs(active) do
        StyleRow(r)
        Fill(r)
    end
    while #active > Get("maxRows") do Release(active[#active]) end
    UpdateSummary()
    Layout()
end

local function CreateAnchor()
    if anchor then return end
    anchor = CreateFrame("Frame", nil, UIParent)
    anchor:SetFrameStrata("MEDIUM")
    feed.frame = anchor
    ApplyStyle()
    F.Place(anchor)
end

local function ClearRows()
    while active[1] do Release(active[1]) end
end

local function Apply()
    if events then events:UnregisterAllEvents() end
    if not Enabled() then
        ClearRows()
        if summary then summary:Hide() end
        SyncClock()
        return
    end
    CreateAnchor()
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", OnEvent)
    end
    for event, chat in pairs(CHAT_EVENTS) do
        if Get(chat.setting) or (chat.tracked and Get("tracker")) then events:RegisterEvent(event) end
    end
    if Get("currency") then events:RegisterEvent("CURRENCY_DISPLAY_UPDATE") end
end

-- A sample of every enabled source: the player's capital for reputation and
-- classic items of three qualities (item id / count pairs). The rows fade like
-- real ones.
local PREVIEW_ITEMS = { 19019, 1, 4306, 5, 14047, 12 }
local function Preview()
    if not Enabled() then return end
    CreateAnchor()
    ClearRows()
    if Get("skills") then ShowSkill(EllesmereUI.L("Swords"), 42) end
    if Get("reputation") then
        local capital = C_Reputation.GetFactionDataByID(UnitFactionGroup("player") == "Horde" and 76 or 72)
        if capital then ShowReputation(capital.name, 250) end
    end
    if Get("money") then ShowMoney(12345) end
    if Get("items") then
        for i = 1, #PREVIEW_ITEMS, 2 do ShowItem("item:" .. PREVIEW_ITEMS[i], PREVIEW_ITEMS[i + 1]) end
    end
end

-------------------------------------------------------------------------------
--  Options preview: the same rows with a sample of every enabled source,
--  drawn in the options content header. Built when the Loot page first
--  opens; it never fades and listens to no events.
-------------------------------------------------------------------------------
local preview -- row set plus its view and every row frame made so far

local SAMPLE_TOTAL, SAMPLE_TIME = 61400, 1200 -- the sample tracker row: copper, seconds

local requested = {} -- preview items asked of the client, once each

-- The Preview samples, newest first, as data. An item the client has not
-- cached yet is asked for once a session and redraws the preview when its
-- load ends; the client also calls back when the load fails, so asking again
-- from the redraw would never stop.
local function PreviewSamples()
    local list, items = {}, Get("items")
    collect = list
    if items then
        for i = 1, #PREVIEW_ITEMS, 2 do
            local link = "item:" .. PREVIEW_ITEMS[i]
            if C_Item.GetItemInfo(link) then ShowItem(link, PREVIEW_ITEMS[i + 1]) end
        end
    end
    if Get("money") then ShowMoney(12345) end
    if Get("reputation") then
        local capital = C_Reputation.GetFactionDataByID(UnitFactionGroup("player") == "Horde" and 76 or 72)
        if capital then ShowReputation(capital.name, 250) end
    end
    if Get("skills") then ShowSkill(EllesmereUI.L("Swords"), 42) end
    collect = nil
    -- Asked for once the samples are in: the callback can run right away.
    if items then
        for i = 1, #PREVIEW_ITEMS, 2 do
            local id = PREVIEW_ITEMS[i]
            if not requested[id] and not C_Item.GetItemInfo(id) then
                requested[id] = true
                Item:CreateFromItemID(id):ContinueOnItemLoad(function() RefreshPreview() end)
            end
        end
    end
    return list
end

-- force: draw while the header is still being built (not shown yet).
RefreshPreview = function(force)
    local v = preview
    if not (v and (force or v.view:IsVisible())) then return end
    local samples = PreviewSamples()
    local n = math.min(#samples, Get("maxRows"))
    for i = 1, n do
        local r = v.all[i]
        if not r then
            r = NewRow(v.frame)
            r.preview = true
            v.all[i] = r
        end
        r.data = samples[i]
        StyleRow(r)
        Fill(r)
        r:SetAlpha(1)
        r:Show()
        v.rows[i] = r
    end
    for i = n + 1, #v.all do
        v.all[i]:Hide()
        v.rows[i] = nil
    end
    if Get("tracker") then
        v.summary = v.summary or NewSummary(v.frame)
        PlaceSummary(v.summary)
        PaintSummary(v.summary, SAMPLE_TOTAL, SAMPLE_TIME)
    elseif v.summary then
        v.summary:Hide()
    end
    local w = Get("width")
    local h = n > 0 and AnchorHeight(n) or Get("rowHeight")
    local pw = v.view:GetParent():GetWidth()
    local available = (pw > 0 and pw) or v.availableWidth or w + 40
    local scale = math.min(1, math.max(100, available - 40) / w)
    v.frame:SetSize(w, h)
    v.frame:SetScale(scale)
    Layout(v)
    v.previewHeight = h * scale + 30
    v.view:SetHeight(v.previewHeight)
    if v.onHeightChanged then v.onHeightChanged(v.previewHeight) end
end

-- parent -> the dress its size hook was made for: the options page pool
-- (EllesmereUI_FramePool.lua) resets a kept header root before each build,
-- which drops the hook, so a new dress (Pool.Gen) hooks again; a plain frame
-- (no Gen) is hooked once.
local hookedParents = {}
local function CreateSettingsPreview(parent, availableWidth, onHeightChanged)
    local v = preview
    if not v then
        v = { rows = {}, all = {} }
        v.view = CreateFrame("Frame", nil, parent)
        v.frame = CreateFrame("Frame", nil, v.view)
        v.frame:SetPoint("CENTER")
        v.view:SetScript("OnShow", function() RefreshPreview() end)
        preview = v
    end
    -- Frames outlive a page rebuild, so the view is reused.
    v.availableWidth, v.onHeightChanged = availableWidth, onHeightChanged
    v.view:SetParent(parent)
    v.view:ClearAllPoints()
    v.view:SetPoint("TOPLEFT")
    v.view:SetPoint("TOPRIGHT")
    local dress = POOL.Gen and POOL.Gen(parent) or true
    if hookedParents[parent] ~= dress then
        hookedParents[parent] = dress
        local lastWidth
        parent:HookScript("OnSizeChanged", function(_, width)
            if width == lastWidth then return end
            lastWidth = width
            if v.view:GetParent() == parent then RefreshPreview() end
        end)
    end
    v.view:Show()
    RefreshPreview(true)
    return v
end

-- Options-page entry points.
EllesmereUI._LootFeed = {
    Get = Get,
    Cfg = Cfg,
    Apply = Apply,
    ApplyStyle = ApplyStyle,
    ApplyPosition = function() F.Place(anchor) end,
    Preview = Preview,
    CreateSettingsPreview = CreateSettingsPreview,
    RefreshPreview = function() RefreshPreview() end,
}

F.Start(Apply, {
    key = "EUI_LootFeed", label = "Loot Feed", order = 732, minWidth = 150,
    frame = function(build)
        if build then CreateAnchor() end
        return anchor
    end,
    -- Follows Max Rows and Row Height.
    height = AnchorHeight,
    applyStyle = ApplyStyle,
})
