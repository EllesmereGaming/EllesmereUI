if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIQoL_LootRolls.lua
--  Loot Roll Frame: one compact list in place of Blizzard's group loot roll
--  popups, a row per roll with the item's icon, level and name, its Need,
--  Greed or Transmog and Pass buttons, and a bar for the time left.
--
--  Blizzard opens its popups from START_LOOT_ROLL through its game event
--  router. While the list is on, that one route is closed
--  (GameEvent.UnregisterInternalEvent), so no popup is ever built and
--  GroupLootContainer, a frame of the bottom managed column that also holds
--  the Bonus Roll prompt, is never touched. Opening the route again from here
--  would run Blizzard's popup code under our taint, so turning the list off
--  takes a reload; until then the list keeps showing rolls.
--
--  The bars are engine timers (SetTimerDuration): no Lua per frame. A row
--  leaves on CANCEL_LOOT_ROLL, at once when you roll, or, for a roll that
--  asks to confirm (bind on pickup), when you confirm it.
--
--  Roll results: the loot history (C_LootHistory) updates a drop on every
--  pick and once more when it has a winner. A row is matched to its drop by
--  item link, then shows how many picked each option and, once the roll
--  ends, its winner and who rolled what. While the winner or the roll list
--  is on, a row stays after you roll until the roll ends, then for the
--  result delay; hovering it holds it.
-------------------------------------------------------------------------------
local _, ns = ...

local PP = EllesmereUI.PP
-- The options page pool: the settings preview reads a dress generation from it.
local POOL = EllesmereUI._Pool

local defaults = {
    profile = {
        lootRolls = {
            enabled    = false,
            width      = 500,
            iconSize   = 48,      -- also the row's height
            barHeight  = 14,      -- capped so the buttons above keep 10px
            spacing    = 8,
            grow       = "DOWN",  -- DOWN | UP from the mover
            textSize   = 14,
            barTexture = "none",
            iconZoom   = true,
            iconBorder = true,
            barBorder  = true,
            showIlvl   = true,
            -- custom | accent | quality; the custom colors are used in "custom"
            nameColorMode = "quality",
            nameColor     = { r = 1, g = 1, b = 1 },
            iconBorderColorMode = "custom",
            iconBorderColor     = { r = 0, g = 0, b = 0 },
            barColorMode  = "quality",
            barColor      = { r = 1, g = 1, b = 1 },
            bopColorMode  = "quality",
            bopColor      = { r = 1, g = 0.25, b = 0.25 },
            boeColorMode  = "quality",
            boeColor      = { r = 0.4, g = 0.8, b = 1 },
            showBop       = false,
            showBoe       = true,
            -- Time left: none | icon | barLeft | barRight
            timerPos       = "barRight",
            timerSize      = 12,
            timerFormat    = "mmss",  -- mmss (1:02) | sec (62)
            timerColorMode = "quality",
            timerColor     = { r = 1, g = 1, b = 1 },
            -- Roll results
            showCounts   = true,   -- how many picked each, on its button
            showWinner   = true,   -- the winner on the bar once the roll ends
            winnerPos    = "center", -- left | center | right on the bar
            winnerSize   = 11,     -- its text, and its pick's icon
            showRollList = true,   -- who rolled what, in its own popup
            rollListSize = 12,     -- the popup's text; its icons follow
            tipGrow      = "rightUp", -- popup from the cursor: rightUp | rightDown | leftUp | leftDown
            resultDelay  = 10,     -- seconds a finished roll stays
            pos        = nil,     -- { centerX, centerY } once moved
        },
    },
}
local DEFAULTS = defaults.profile.lootRolls

local db
local function P()
    return db and db.profile and db.profile.lootRolls
end

local function Get(key)
    local p = P()
    local v = p and p[key]
    if v == nil then return DEFAULTS[key] end
    return v
end

local ROLL_PASS = 0
local GAP = 5          -- icon to bar, name to the buttons
local BUTTON_GAP = 4
local MIN_BUTTON = 10  -- the roll buttons sit above the bar, at least this tall
local TICK = 0.25      -- time-left text refresh, only while live rows show it
local SAMPLE_SECONDS = 90  -- a sample's time left is its bar fill of this
local IMMEDIATE = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate or 0
local REMAINING = Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime or 1
local FLAT = "Interface\\Buttons\\WHITE8X8"
local SPARK = "Interface\\CastingBar\\UI-CastingBar-Spark"
local UNKNOWN_ICON = 134400

-- Right to left. Every row shows every button; the ones the roll does not
-- allow are greyed out.
local BUTTONS = {
    { key = "pass",     rollType = 0, atlas = "lootroll-toast-icon-pass",     tip = "PASS",
      file = "Interface\\Buttons\\UI-GroupLoot-Pass" },
    { key = "transmog", rollType = 4, atlas = "lootroll-toast-icon-transmog", tip = "TRANSMOGRIFICATION",
      can = "canTransmog" },
    { key = "greed",    rollType = 2, atlas = "lootroll-toast-icon-greed",    tip = "GREED",
      file = "Interface\\Buttons\\UI-GroupLoot-Coin",
      can = "canGreed", reason = "reasonGreed" },
    { key = "need",     rollType = 1, atlas = "lootroll-toast-icon-need",     tip = "NEED",
      file = "Interface\\Buttons\\UI-GroupLoot-Dice",
      can = "canNeed",  reason = "reasonNeed" },
}
-- WoW Forever has vanilla content: no transmog roll, so no Transmog button.
if EllesmereUI.IS_FOREVER then
    for i = #BUTTONS, 1, -1 do
        if BUTTONS[i].key == "transmog" then table.remove(BUTTONS, i) end
    end
end
-- key -> button; useFile when the client lacks the roll toast art.
local BUTTON_OF = {}
for _, info in ipairs(BUTTONS) do
    info.useFile = info.file and not C_Texture.GetAtlasInfo(info.atlas .. "-up")
    BUTTON_OF[info.key] = info
end

-- Roll kinds in the roll list's order, the history's pick states for each,
-- and how they read. An eligible player yet to pick is "waiting", listed last.
local RANK = { need = 1, greed = 2, transmog = 3, pass = 4, waiting = 5 }
local KIND_OF_STATE = {}
do
    local byName = { NeedMainSpec = "need", NeedOffSpec = "need", Greed = "greed",
        Transmog = "transmog", Pass = "pass", NoRoll = "waiting" }
    for name, value in pairs(Enum.EncounterLootDropRollState or {}) do
        if byName[name] then KIND_OF_STATE[value] = byName[name] end
    end
end
local KIND_OF_ROLLTYPE = {}
for _, info in ipairs(BUTTONS) do KIND_OF_ROLLTYPE[info.rollType] = info.key end
local KIND_LABEL = { need = { "NEED", "Need" }, greed = { "GREED", "Greed" },
    transmog = { "TRANSMOGRIFY", "Transmog" }, pass = { "PASS", "Pass" } }
local KIND_COLOR = { need = { 0.3, 1, 0.3 }, greed = { 1, 0.82, 0 },
    transmog = { 0.85, 0.5, 1 }, pass = { 0.6, 0.6, 0.6 }, waiting = { 0.6, 0.6, 0.6 } }
local WON_MARK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t "
local WAIT_ICON = "|TInterface\\RaidFrame\\ReadyCheck-Waiting:%d:%d|t"

local anchor, events
local rows = {}        -- live rows, oldest first
local pool = {}
local sampleRows = {}  -- the on-screen preview's samples, kept apart from the live pool
local sampling = false
local suppressed = false
local dropRows = {}    -- "encounterID:lootListID" -> the live row showing that drop
local HISTORY = C_LootHistory and C_LootHistory.GetSortedInfoForDrop and true or false

-- v when it is a readable value of type kind (never a secret one).
local function Plain(v, kind)
    if not issecretvalue(v) and type(v) == kind then return v end
end

-- A finished row stays to show its result while either result is on (and
-- the client keeps a loot history to read it from).
local function Lingers()
    return HISTORY and (Get("showWinner") or Get("showRollList")) and true or false
end

-- Counts or results need the loot history.
local function Tracking()
    return HISTORY and (Get("showCounts") or Lingers())
end

-- The list runs once Blizzard's popups are closed (Suppress, when it is
-- turned on), and after it is turned off until a reload gives them back. A
-- client that cannot close them keeps its popups and no list, never both.
-- WoW Forever's Gamepad interface style has its own roll frame, which the
-- closed route does not reach and a controller drives: the list stays out
-- of its way (never closes the route under it, takes no new rolls), and
-- comes back when the style is left, as the route may already be closed.
local function PadUI()
    return EllesmereUI.PadGamepadUI()
end

local function Active()
    return suppressed
end

-- Showing rolls now: it stands in for Blizzard's popups (its mover too).
local function InUse()
    return suppressed and not PadUI()
end

-------------------------------------------------------------------------------
--  Rows
-------------------------------------------------------------------------------
local barTextures
local function BarTexture()
    barTextures = barTextures or EllesmereUI.BuildBarTextureTables(true)
    return barTextures[Get("barTexture")] or FLAT
end

local function Font(fs, size)
    EllesmereUI.ApplyModuleFont(fs, nil, size, "extras")
end

-- For text with other players' names, which can be in any script.
local function FontFamily(fs, size)
    EllesmereUI.ApplyModuleFontFamily(fs, nil, size, "extras")
end

local function QualityColor(quality)
    if quality and C_Item.GetItemQualityColor then
        local r, g, b = C_Item.GetItemQualityColor(quality)
        if r then return r, g, b end
    end
    return 0.6, 0.6, 0.6
end

-- The color a mode key ("nameColorMode", "barColorMode") picks for an item.
local function ModeColor(modeKey, colorKey, quality)
    local mode = Get(modeKey)
    if mode == "quality" then return QualityColor(quality) end
    if mode == "accent" then return EllesmereUI.GetAccentColor() end
    local c = Get(colorKey)
    return c.r or 1, c.g or 1, c.b or 1
end

local Rolled  -- you picked: the row leaves, or waits for the result

local function ButtonClick(b)
    local d = b.row.data
    if not (d and d.rollID) or d.closed then return end
    local rollType = b.info.rollType
    RollOnLoot(d.rollID, rollType)
    -- Bind on pickup asks first: that pick counts once it is confirmed.
    if rollType == ROLL_PASS or not d.bop then Rolled(d.rollID, b.info.key) end
end

local function ButtonEnter(b)
    local text = _G[b.info.tip] or b.info.tip
    if b.reasonText then text = text .. "\n|cffff4040" .. b.reasonText .. "|r" end
    EllesmereUI.ShowWidgetTooltip(b, text)
end

local function ButtonLeave()
    EllesmereUI.HideWidgetTooltip()
end

-- A Blizzard tooltip string, or its English text where the client lacks it.
local function GS(key, fallback)
    local v = _G[key]
    return type(v) == "string" and v or fallback
end

-- Builds an item tooltip by hand for a sample the client has no data for
-- (see SAMPLES), laid out in Blizzard's order. Standard lines use the
-- client's own strings; the effect text is the sample's.
local function FakeTooltip(tt, d)
    local t = d.tip
    local W, GOLD = 1, 0.82
    tt:SetText(d.name or "", QualityColor(d.quality))
    if t.ilvl then tt:AddLine(GS("ITEM_LEVEL", "Item Level %d"):format(t.ilvl), W, GOLD, 0) end
    if d.bop then tt:AddLine(GS("ITEM_BIND_ON_PICKUP", "Binds when picked up"), W, W, W) end
    if t.unique then tt:AddLine(GS("ITEM_UNIQUE", "Unique"), W, W, W) end
    if t.slot then tt:AddDoubleLine(GS(t.slot[1], t.slot[2]), t.kind or "", W, W, W, W, W, W) end
    local dmg = t.damage
    if dmg then
        tt:AddDoubleLine(GS("DAMAGE_TEMPLATE", "%s - %s Damage"):format(dmg[1], dmg[2]),
            GS("SPEED", "Speed") .. " " .. dmg[3], W, W, W, W, W, W)
        tt:AddLine(GS("DPS_TEMPLATE", "(%s damage per second)"):format(dmg[4]), W, W, W)
    end
    if t.stats then
        for _, s in ipairs(t.stats) do tt:AddLine(s, W, W, W) end
    end
    if t.durability then
        tt:AddLine(GS("DURABILITY_TEMPLATE", "Durability %d / %d"):format(t.durability, t.durability), W, W, W)
    end
    if t.level then tt:AddLine(GS("ITEM_MIN_LEVEL", "Requires Level %d"):format(t.level), W, W, W) end
    if t.effects then
        for _, e in ipairs(t.effects) do
            tt:AddLine(GS(e[1], e[2]) .. " " .. e[3], 0, W, 0, true)
        end
    end
    if t.charges then
        tt:AddLine(GS("ITEM_SPELL_CHARGES", "%d Charges"):format(t.charges), W, W, W)
    end
end

local function KindLabel(kind)
    local l = KIND_LABEL[kind]
    return GS(l[1], l[2])
end

-- A roll button's art inline in text.
local function KindIcon(info, size)
    if info.useFile then return ("|T%s-Up:%d:%d|t"):format(info.file, size, size) end
    return ("|A:%s-up:%d:%d|a"):format(info.atlas, size, size)
end

-- A pick as "<roll> <its button's icon>" (the icon alone without a roll).
-- A player yet to pick shows the ready check's waiting mark.
local function KindText(kind, roll, size)
    if kind == "waiting" then return WAIT_ICON:format(size, size) end
    local info = BUTTON_OF[kind]
    local text = info and KindIcon(info, size) or KindLabel(kind)
    return roll and (roll .. " " .. text) or text
end

local function ClassRGB(class)
    local cc = class and RAID_CLASS_COLORS[class] and EllesmereUI.GetClassColor(class)
    if cc then return cc.r, cc.g, cc.b end
    return 1, 1, 1
end

-- The roll list's own popup, apart from the item tooltip.
local rollTip
local tipFace, tipFlags  -- the tooltip text's own font, its lines resized in it
local function RollTip()
    if not rollTip then
        -- SharedTooltipTemplate: GameTooltipTemplate would join Blizzard's
        -- tooltip data registry and taint it.
        rollTip = CreateFrame("GameTooltip", "EllesmereUILootRollsTip", UIParent, "SharedTooltipTemplate")
        local base = _G.GameTooltipText
        if base then tipFace, _, tipFlags = base:GetFont() end
    end
    return rollTip
end

-- Who rolled what, Need first, then Greed, Transmog and Pass, under the
-- item's name. False when there is nothing to list.
-- Row popups follow the cursor, growing the way Roll List Growth says. The
-- engine's cursor anchors move them (no Lua per frame) and keep them on
-- screen; they open upward, so a downward one is shifted down by its own
-- height once it is filled (Settle). The gap is wider on the right, where
-- the pointer's arrow is. The icon's popup sits beside the icon.
local TIP_GROW = {
    rightUp   = { "ANCHOR_CURSOR_RIGHT", 24, 6 },
    rightDown = { "ANCHOR_CURSOR_RIGHT", 24, -6, true },
    leftUp    = { "ANCHOR_CURSOR_LEFT", -12, 6 },
    leftDown  = { "ANCHOR_CURSOR_LEFT", -12, -6, true },
}
local tipGrows = {}  -- tooltip -> its TIP_GROW entry (nothing written on GameTooltip)
local function Anchor(tt, owner, atCursor)
    if not atCursor then
        tipGrows[tt] = nil
        tt:SetOwner(owner, "ANCHOR_RIGHT")
        return
    end
    local g = TIP_GROW[Get("tipGrow")] or TIP_GROW.rightUp
    tipGrows[tt] = g
    tt:SetOwner(owner, g[1], g[2], g[3])
end

-- Shows a filled popup; a downward one then drops below the cursor.
local function Settle(tt)
    tt:Show()
    local g = tipGrows[tt]
    if g and g[4] and tt.SetAnchorType then
        tt:SetAnchorType(g[1], g[2], g[3] - tt:GetHeight())
    end
end

-- A popup line's text at the Roll List Size, in the tooltip's own face. A
-- font family, as the lines hold other players' names.
local function SizeLine(fs, size)
    if fs and tipFace then EllesmereUI.SetFontFamily(fs, tipFace, size, tipFlags, true) end
end

local function ShowRollList(d, owner)
    local list = d.rollers
    if not (Get("showRollList") and list and list[1]) then return false end
    local tt = RollTip()
    local size = Get("rollListSize")
    Anchor(tt, owner, true)
    tt:SetText(d.name or "", QualityColor(d.quality))
    for _, e in ipairs(list) do
        local cr, cg, cb = ClassRGB(e.class)
        local c = KIND_COLOR[e.kind]
        local right = KindText(e.kind, e.roll, size + 4)
        tt:AddDoubleLine((e.won and WON_MARK or "") .. e.name, right, cr, cg, cb, c[1], c[2], c[3])
    end
    -- The item name, the title, stays a little larger than the list.
    local name = tt:GetName()
    for i = 1, tt:NumLines() do
        local s = i == 1 and size + 2 or size
        SizeLine(_G[name .. "TextLeft" .. i], s)
        SizeLine(_G[name .. "TextRight" .. i], s)
    end
    Settle(tt)
    return true
end

local function ShowItem(d, owner, atCursor)
    Anchor(GameTooltip, owner, atCursor)
    if d.rollID and not d.closed then
        GameTooltip:SetLootRollItem(d.rollID)
    elseif d.link then
        GameTooltip:SetHyperlink(d.link)
    elseif d.tip then
        FakeTooltip(GameTooltip, d)
    else
        GameTooltip:SetText(d.name or "")
    end
    Settle(GameTooltip)
end

local function HideTips()
    GameTooltip:Hide()
    if rollTip then rollTip:Hide() end
end

-- The icon shows the item; the rest of the row shows the roll list, or
-- nothing when there is none.
local function ShowTip(r, owner)
    local d = r.data
    if not d then return end
    if owner == r.icon then
        if rollTip then rollTip:Hide() end
        ShowItem(d, owner)
    else
        GameTooltip:Hide()
        if not ShowRollList(d, owner) and rollTip then rollTip:Hide() end
    end
end

-- A finished row leaves after the result delay. Hovering it holds the time
-- left (lingerLeft) until the mouse leaves.
local RemoveRow
local function StartLinger(r, secs)
    local d = r.data
    r.lingerEnd = GetTime() + secs
    r.linger = C_Timer.NewTimer(secs, function()
        r.linger = nil
        if r.data == d then RemoveRow(r) end
    end)
end

local function HoldLinger(r)
    if not r.linger then return end
    r.linger:Cancel()
    r.linger = nil
    r.lingerLeft = math.max(0, r.lingerEnd - GetTime())
end

local function ResumeLinger(r)
    local left = r.lingerLeft
    if not left then return end
    r.lingerLeft = nil
    StartLinger(r, math.max(1, left))
end

local function RowEnter(r, owner)
    r.hoverOwner = owner
    HoldLinger(r)
    ShowTip(r, owner)
end

local function RowLeave(r)
    r.hoverOwner = nil
    HideTips()
    ResumeLinger(r)
end

local function IconEnter(icon) RowEnter(icon.row, icon) end
local function IconLeave(icon) RowLeave(icon.row) end

-- A roll button is part of the row: on it, a finished roll still holds.
local function RollButtonEnter(b)
    b.row.onButton = true
    HoldLinger(b.row)
    ButtonEnter(b)
end
local function RollButtonLeave(b)
    b.row.onButton = nil
    ButtonLeave()
    ResumeLinger(b.row)
end

-- The mouse is on the row, its icon or one of its buttons.
local function Hovered(r)
    return r.hoverOwner ~= nil or r.onButton == true
end

local function IconClick(icon)
    local d = icon.row.data
    if d and d.link then HandleModifiedItemClick(d.link) end
end

local function NewRow(parent)
    local r = CreateFrame("Frame", nil, parent)
    -- The whole row shows the item and holds a finished roll, like the icon.
    r:EnableMouse(true)
    r:SetScript("OnEnter", function(self) RowEnter(self, self) end)
    r:SetScript("OnLeave", RowLeave)

    local icon = CreateFrame("Button", nil, r)
    icon.row = r
    icon:SetScript("OnEnter", IconEnter)
    icon:SetScript("OnLeave", IconLeave)
    icon:SetScript("OnClick", IconClick)
    r.icon = icon
    r.iconTex = icon:CreateTexture(nil, "ARTWORK")
    r.iconTex:SetAllPoints()
    r.ilvl = icon:CreateFontString(nil, "OVERLAY")
    r.ilvl:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -2, 2)
    r.count = icon:CreateFontString(nil, "OVERLAY")
    r.count:SetPoint("TOPRIGHT", icon, "TOPRIGHT", -2, -2)
    PP.CreateBorder(icon, 0, 0, 0, 1, 1)

    r.bar = CreateFrame("StatusBar", nil, r)
    r.barBg = r.bar:CreateTexture(nil, "BACKGROUND")
    r.barBg:SetAllPoints()
    r.spark = r.bar:CreateTexture(nil, "OVERLAY")
    r.spark:SetTexture(SPARK)
    r.spark:SetBlendMode("ADD")
    PP.CreateBorder(r.bar, 0, 0, 0, 1, 1)

    r.name = r:CreateFontString(nil, "OVERLAY")
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.bind = r:CreateFontString(nil, "OVERLAY")  -- BoP / BoE
    -- Time left, on a layer above both the icon and the bar.
    r.timerHolder = CreateFrame("Frame", nil, r)
    r.timerHolder:SetAllPoints()
    r.timerHolder:SetFrameLevel(r:GetFrameLevel() + 5)
    r.timer = r.timerHolder:CreateFontString(nil, "OVERLAY")
    -- The winner of a finished roll, on the bar.
    r.result = r.timerHolder:CreateFontString(nil, "OVERLAY")
    r.result:SetJustifyH("LEFT")
    r.result:SetWordWrap(false)

    r.buttons = {}
    for _, info in ipairs(BUTTONS) do
        local b = CreateFrame("Button", nil, r)
        -- Its count sits on the top layer, so it stays bright on a dimmed button.
        b.count = r.timerHolder:CreateFontString(nil, "OVERLAY")
        b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -1)
        -- The roll toast art, else the classic dice, coin and pass textures.
        if info.useFile then
            b:SetNormalTexture(info.file .. "-Up")
            b:SetPushedTexture(info.file .. "-Down")
            b:SetHighlightTexture(info.file .. "-Highlight", "ADD")
        else
            b:SetNormalAtlas(info.atlas .. "-up")
            b:SetPushedAtlas(info.atlas .. "-down")
            b:SetHighlightAtlas(info.atlas .. "-highlight", "ADD")
        end
        b:SetMotionScriptsWhileDisabled(true)
        b.info, b.row = info, r
        b:SetScript("OnClick", ButtonClick)
        b:SetScript("OnEnter", RollButtonEnter)
        b:SetScript("OnLeave", RollButtonLeave)
        r.buttons[info.key] = b
    end
    return r
end

-- Size, layout, font and look from the settings.
local function StyleRow(r)
    local w, h = Get("width"), Get("iconSize")
    r:SetSize(w, h)

    r.icon:ClearAllPoints()
    r.icon:SetPoint("TOPLEFT")
    r.icon:SetSize(h, h)
    local z = Get("iconZoom") and 0.08 or 0
    r.iconTex:SetTexCoord(z, 1 - z, z, 1 - z)

    local barH = math.max(2, math.min(Get("barHeight"), h - MIN_BUTTON - 4))
    local tex = BarTexture()
    r.bar:ClearAllPoints()
    r.bar:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", GAP, 0)
    r.bar:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
    r.bar:SetHeight(barH)
    r.bar:SetStatusBarTexture(tex)
    r.barBg:SetTexture(tex)
    r.spark:ClearAllPoints()
    r.spark:SetPoint("CENTER", r.bar:GetStatusBarTexture(), "RIGHT", 0, 0)
    r.spark:SetSize(barH * 2, barH * 2.5)

    if Get("iconBorder") then PP.ShowBorder(r.icon) else PP.HideBorder(r.icon) end
    if Get("barBorder") then PP.ShowBorder(r.bar) else PP.HideBorder(r.bar) end
    r.ilvl:SetShown(Get("showIlvl") and true or false)

    local size = Get("textSize")
    local small = math.max(8, math.floor(size * 0.8 + 0.5))
    Font(r.name, size)
    Font(r.bind, size)
    Font(r.ilvl, small)
    Font(r.count, small)

    local bs = math.max(MIN_BUTTON, math.min(28, h - barH - 4))
    local prev
    for _, info in ipairs(BUTTONS) do
        local b = r.buttons[info.key]
        b:SetSize(bs, bs)
        b:ClearAllPoints()
        if prev then
            b:SetPoint("RIGHT", prev, "LEFT", -BUTTON_GAP, 0)
        else
            b:SetPoint("BOTTOMRIGHT", r.bar, "TOPRIGHT", 0, 2)
        end
        prev = b
    end
    r.bind:ClearAllPoints()
    r.bind:SetPoint("RIGHT", r.buttons.need, "LEFT", -GAP, 0)

    local pos = Get("timerPos")
    r.timer:ClearAllPoints()
    if pos == "icon" then
        r.timer:SetPoint("CENTER", r.icon, "CENTER", 0, 0)
    elseif pos == "barLeft" then
        r.timer:SetPoint("LEFT", r.bar, "LEFT", 3, 0)
    else
        r.timer:SetPoint("RIGHT", r.bar, "RIGHT", -3, 0)
    end
    Font(r.timer, Get("timerSize"))
    r.timer:SetShown(pos ~= "none")
    r.nameY = 2 + bs / 2

    -- The winner at the bar's left, center or right: one anchor point each (a
    -- text spanning the bar does not redraw on a justify change alone).
    FontFamily(r.result, Get("winnerSize"))
    local wpos = Get("winnerPos")
    r.result:ClearAllPoints()
    if wpos == "center" then
        r.result:SetJustifyH("CENTER")
        r.result:SetPoint("CENTER", r.bar, "CENTER", 0, 0)
    elseif wpos == "right" then
        r.result:SetJustifyH("RIGHT")
        r.result:SetPoint("RIGHT", r.bar, "RIGHT", -3, 0)
    else
        r.result:SetJustifyH("LEFT")
        r.result:SetPoint("LEFT", r.bar, "LEFT", 3, 0)
    end

    local counts = Get("showCounts") and true or false
    for _, b in pairs(r.buttons) do
        Font(b.count, small)
        b.count:SetShown(counts)
    end
end

-- lit: drawn bright (default: when it can be clicked); a closed roll lights
-- only your pick.
local function SetButton(b, can, reason, lit)
    can = can and true or false
    if lit == nil then lit = can end
    b:Show()
    b:SetEnabled(can)
    b:SetAlpha(lit and 1 or 0.35)
    b:GetNormalTexture():SetDesaturated(not lit)
    b.reasonText = (not lit and reason and _G["LOOT_ROLL_INELIGIBLE_REASON" .. reason]) or nil
end

-- The finished roll's line: the winner and their roll, or that all passed.
local function ResultText(d, size)
    local w = d.winner
    if w then
        local text = EllesmereUI.HexColor(ClassRGB(w.class)) .. w.name .. "|r"
        if w.kind and w.kind ~= "waiting" then
            local c = KIND_COLOR[w.kind]
            text = text .. "  " .. EllesmereUI.HexColor(c[1], c[2], c[3])
                .. KindText(w.kind, w.roll, size) .. "|r"
        end
        return WON_MARK .. text
    end
    if d.allPassed then return EllesmereUI.L("Everyone passed") end
    return ""
end

-- Paints r.data onto the row. Texts are set here, after StyleRow gave them a font.
local function Fill(r)
    local d = r.data
    r.iconTex:SetTexture(d.icon or UNKNOWN_ICON)
    PP.SetBorderColor(r.icon, ModeColor("iconBorderColorMode", "iconBorderColor", d.quality))
    local br, bg, bb = ModeColor("barColorMode", "barColor", d.quality)
    r.bar:SetStatusBarColor(br, bg, bb, 1)
    r.barBg:SetVertexColor(br, bg, bb, 0.25)

    r.name:SetText(d.name or "")
    r.name:SetTextColor(ModeColor("nameColorMode", "nameColor", d.quality))
    r.ilvl:SetText(d.ilvl and tostring(d.ilvl) or "")
    r.count:SetText((d.count and d.count > 1) and tostring(d.count) or "")

    r.timer:SetTextColor(ModeColor("timerColorMode", "timerColor", d.quality))

    local showBop = d.bop and Get("showBop")
    local showBoe = not d.bop and d.boe and Get("showBoe")
    local bound = showBop or showBoe
    if showBop then
        r.bind:SetText(EllesmereUI.L("BoP"))
        r.bind:SetTextColor(ModeColor("bopColorMode", "bopColor", d.quality))
    elseif showBoe then
        r.bind:SetText(EllesmereUI.L("BoE"))
        r.bind:SetTextColor(ModeColor("boeColorMode", "boeColor", d.quality))
    end
    r.bind:SetShown(bound and true or false)
    r.name:ClearAllPoints()
    r.name:SetPoint("LEFT", r.bar, "TOPLEFT", 0, r.nameY or 14)
    r.name:SetPoint("RIGHT", bound and r.bind or r.buttons.need, "LEFT", -GAP, 0)

    local counts = d.counts
    for _, info in ipairs(BUTTONS) do
        local b = r.buttons[info.key]
        if d.closed then
            SetButton(b, false, nil, d.choice == info.key)
        else
            SetButton(b, not info.can or d[info.can], info.reason and d[info.reason])
        end
        local n = counts and counts[info.key] or 0
        b.count:SetText(n > 0 and tostring(n) or "")
    end
    r.result:SetText((d.done and Get("showWinner")) and ResultText(d, Get("winnerSize")) or "")
end

local function FormatTime(sec)
    if Get("timerFormat") == "sec" then return tostring(sec) end
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

-- Repaints a live row's time left when its whole second changes.
local function TimerText(r)
    if not r.endTime then return end
    local sec = math.max(0, math.ceil(r.endTime - GetTime()))
    if sec == r.timerSec then return end
    r.timerSec = sec
    r.timer:SetText(FormatTime(sec))
end

-- A static bar: the samples on screen and in the settings preview, whose
-- time left is the fill's share of SAMPLE_SECONDS (none without a fill).
local function StillBar(r, fill)
    r.bar:SetMinMaxValues(0, 1)
    r.bar:SetValue(fill or 1)
    r.endTime, r.timerSec = nil, nil
    r.timer:SetText((fill and fill > 0) and FormatTime(math.floor(fill * SAMPLE_SECONDS + 0.5)) or "")
end

-- A finished roll's bar: empty, no time left. A plain SetValue does not take
-- the fill back from an armed timer, so an expired one empties it.
local function EndBar(r)
    if r.dur and r.bar.SetTimerDuration then
        r.endTime, r.timerSec = nil, nil
        r.timer:SetText("")
        r.dur:SetTimeFromStart(GetTime() - 1, 1)
        r.bar:SetTimerDuration(r.dur, IMMEDIATE, REMAINING)
    else
        StillBar(r, 0)
    end
end

local function ArmTimer(r)
    local d = r.data
    local left = (GetLootRollTimeLeft(d.rollID) or 0) / 1000
    local total = (d.rollTime or 0) / 1000
    if total <= 0 then
        total = ((C_Loot and C_Loot.GetLootRollDuration and C_Loot.GetLootRollDuration(d.rollID)) or 0) / 1000
    end
    if total < left then total = left end
    if total <= 0 or not r.bar.SetTimerDuration then
        -- A reused row may still hold an armed timer, which SetValue cannot
        -- override: arm one that stays full instead.
        if r.dur and r.bar.SetTimerDuration then
            r.dur:SetTimeFromStart(GetTime(), 1e9)
            r.bar:SetTimerDuration(r.dur, IMMEDIATE, REMAINING)
        end
        return StillBar(r)
    end
    r.endTime, r.timerSec = GetTime() + left, nil
    TimerText(r)
    r.dur = r.dur or C_DurationUtil.CreateDuration()
    r.dur:SetTimeFromStart(GetTime() - (total - left), total)
    r.bar:SetTimerDuration(r.dur, IMMEDIATE, REMAINING)
end

-------------------------------------------------------------------------------
--  Roll data
-------------------------------------------------------------------------------
local function ItemLevel(link)
    if link and C_Item.IsEquippableItem(link) then
        return C_Item.GetDetailedItemLevelInfo(link)
    end
end

-- True for bind on equip; nil while the item is not cached yet.
local BIND_ON_EQUIP = (Enum.ItemBind and Enum.ItemBind.OnEquip) or 2
local function BindOnEquip(link)
    if not link then return false end
    local name, _, _, _, _, _, _, _, _, _, _, _, _, bindType = C_Item.GetItemInfo(link)
    if not name then return nil end
    return bindType == BIND_ON_EQUIP
end

local function RollData(rollID, rollTime)
    local texture, name, count, quality, bop, canNeed, canGreed, _, reasonNeed, reasonGreed,
        _, _, canTransmog = GetLootRollItemInfo(rollID)
    if not name then return end
    local link = GetLootRollItemLink(rollID)
    return {
        rollID = rollID, rollTime = rollTime, link = link,
        icon = texture, name = name, count = count, quality = quality, bop = bop,
        canNeed = canNeed, canGreed = canGreed, canTransmog = canTransmog,
        reasonNeed = reasonNeed, reasonGreed = reasonGreed,
        ilvl = ItemLevel(link),
        boe = not bop and BindOnEquip(link),
    }
end

-------------------------------------------------------------------------------
--  Roll results
-------------------------------------------------------------------------------
-- Counts the picks and sorts them: Need, Greed, Transmog, Pass, the highest
-- roll first in each; those yet to pick last.
local function SetRollers(d, list, winnerName)
    local counts = { need = 0, greed = 0, transmog = 0, pass = 0, waiting = 0 }
    for _, e in ipairs(list) do
        counts[e.kind] = counts[e.kind] + 1
        e.won = winnerName ~= nil and e.name == winnerName
    end
    table.sort(list, function(a, b)
        if a.kind ~= b.kind then return RANK[a.kind] < RANK[b.kind] end
        if (a.roll or 0) ~= (b.roll or 0) then return (a.roll or 0) > (b.roll or 0) end
        return a.name < b.name
    end)
    d.counts, d.rollers = counts, list
end

-- One player's entry in a history drop; kind is "waiting" until they pick.
local function Roller(info)
    return {
        name = Plain(info.playerName, "string") or "?",
        class = Plain(info.playerClass, "string"),
        kind = KIND_OF_STATE[Plain(info.state, "number") or -1],
        roll = Plain(info.roll, "number"),
    }
end

local function Finished(drop)
    return type(drop.winner) == "table" or Plain(drop.allPassed, "boolean") == true
end

-- A history drop onto a row's data: every eligible player and their pick,
-- your own, and the result.
local function ReadDrop(d, drop)
    local list = {}
    if type(drop.rollInfos) == "table" then
        for _, info in ipairs(drop.rollInfos) do
            local e = Roller(info)
            if e.kind then
                list[#list + 1] = e
                if e.kind ~= "waiting" and Plain(info.isSelf, "boolean") and not d.choice then
                    d.choice = e.kind
                end
            end
        end
    end
    d.winner = type(drop.winner) == "table" and Roller(drop.winner) or nil
    d.allPassed = Plain(drop.allPassed, "boolean") == true
    d.done = d.winner ~= nil or d.allPassed
    SetRollers(d, list, d.winner and d.winner.name)
end

local function ItemID(link)
    return link and link:match("item:(%d+)")
end

-- One sample per quality, Artifact down to Uncommon, with a mix of button
-- states and bind labels. The quality is fixed here: Martin Fury (17) is grey
-- in today's client. The client never sends some names (Martin Fury on both
-- clients, Corrupted Ashbringer on Forever), so those are given, with an
-- icon for when the client lacks the item and a tooltip built by hand
-- (FakeTooltip): Martin Fury as first made, Corrupted Ashbringer from Naxx.
-- rolls are made-up players' picks ({ name, class, kind, roll }), "waiting"
-- for one yet to pick; a done sample shows a finished roll, its top pick the
-- winner.
local SAMPLES = {
    { id = 17,    quality = 6, bop = true, canNeed = true, canGreed = true, name = "Martin Fury",
      rolls = { { "Aelric", "WARRIOR", "need" }, { "Brenna", "PRIEST", "greed" },
                { "Corvin", "MAGE", "pass" }, { "Dagny", "ROGUE", "need" },
                { "Fenrick", "PALADIN", "waiting" } },
      tip = {
          unique = true,
          slot = { "INVTYPE_BODY", "Shirt" },
          effects = {
              { "ITEM_SPELL_TRIGGER_ONUSE", "Use:", "Instantly kills all enemies within 30 yards." },
          },
          charges = 100,
      } },
    { id = 21176, quality = 5, bop = true, canNeed = true, canGreed = true,  -- Black Qiraji Resonating Crystal
      rolls = { { "Fenrick", "PALADIN", "need" }, { "Aelric", "WARRIOR", "need" }, { "Brenna", "PRIEST", "need" },
                { "Corvin", "MAGE", "waiting" }, { "Dagny", "ROGUE", "waiting" } } },
    { id = 22691, quality = 4, bop = true, canNeed = true, canTransmog = true,
      name = "Corrupted Ashbringer", icon = "Interface\\Icons\\INV_Sword_48",
      rolls = { { "Corvin", "MAGE", "transmog" }, { "Dagny", "ROGUE", "greed" },
                { "Aelric", "WARRIOR", "waiting" } },
      tip = {
          ilvl = 86,
          unique = true,
          slot = { "INVTYPE_2HWEAPON", "Two-Hand" },
          kind = "Sword",
          damage = { 259, 389, "3.60", "90.0" },
          stats = { "-25 Stamina" },
          durability = 120,
          level = 60,
          effects = {
              { "ITEM_SPELL_TRIGGER_ONEQUIP", "Equip:", "Improves your chance to get a critical strike by 2%." },
              { "ITEM_SPELL_TRIGGER_ONEQUIP", "Equip:", "Improves your chance to hit by 1%." },
              { "ITEM_SPELL_TRIGGER_ONPROC", "Chance on hit:", "Steals 185 to 215 life from target enemy." },
          },
      } },
    { id = 17705, quality = 3, boe = true, canGreed = true, reasonNeed = 1,  -- Thrash Blade
      rolls = { { "Aelric", "WARRIOR", "waiting" }, { "Brenna", "PRIEST", "waiting" },
                { "Corvin", "MAGE", "waiting" }, { "Dagny", "ROGUE", "waiting" } } },
    { id = 15211, quality = 2, boe = true, canNeed = true, canGreed = true, canTransmog = true,  -- Militant Shortsword
      done = true, choice = "greed",
      rolls = { { "Brenna", "PRIEST", "greed", 73 }, { "Aelric", "WARRIOR", "greed", 41 },
                { "Corvin", "MAGE", "transmog", 88 }, { "Dagny", "ROGUE", "pass" } } },
}
-- WoW Forever characters carry a surname: the sample players get one there.
local SAMPLE_SURNAMES = { Aelric = "Stonebrook", Brenna = "Ashford", Corvin = "Vale",
    Dagny = "Holt", Fenrick = "Marsh" }
local function SampleName(first)
    local join = EllesmereUI.WithSurname
    return join and join(first, SAMPLE_SURNAMES[first], true) or first
end
local SamplesLoaded  -- repaints the samples once an uncached sample item loads
local sampleRequested = {}

local function SampleData()
    local list = {}
    for i, s in ipairs(SAMPLES) do
        local d = { fill = 1 - i * 0.15 }
        for k, v in pairs(s) do d[k] = v end
        local name, link = C_Item.GetItemInfo(s.id)
        if name then
            d.name, d.link = s.name or name, link
            d.ilvl = ItemLevel(link)
        elseif not sampleRequested[s.id] then
            sampleRequested[s.id] = true
            Item:CreateFromItemID(s.id):ContinueOnItemLoad(function()
                if SamplesLoaded then SamplesLoaded() end
            end)
        end
        d.icon = select(5, C_Item.GetItemInfoInstant(s.id)) or s.icon
        d.ilvl = d.ilvl or (s.tip and s.tip.ilvl)
        d.name = d.name or EllesmereUI.L("Sample Item")
        if s.rolls then
            local picks = {}
            for _, e in ipairs(s.rolls) do
                -- No Transmog on Forever.
                if BUTTON_OF[e[3]] or e[3] == "waiting" then
                    picks[#picks + 1] = { name = SampleName(e[1]), class = e[2], kind = e[3], roll = e[4] }
                end
            end
            SetRollers(d, picks)
        end
        if s.done then
            local top = d.rollers and d.rollers[1]
            if top and top.kind ~= "pass" and top.kind ~= "waiting" then
                top.won, d.winner = true, top
            else
                d.allPassed = true
            end
            d.closed, d.fill = true, 0
        end
        list[i] = d
    end
    return list
end

-------------------------------------------------------------------------------
--  The list
-------------------------------------------------------------------------------
local function PlaceRow(r, i, step, up)
    r:ClearAllPoints()
    if up then
        r:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, (i - 1) * step)
    else
        r:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -(i - 1) * step)
    end
end

-- Time left on the live rows. Runs only while a row still counting down
-- shows it (a finished one waiting out its result has no time left).
local ticker
local function Tick()
    for _, r in ipairs(rows) do TimerText(r) end
end
local function UpdateTicker()
    local want = false
    if Get("timerPos") ~= "none" then
        for _, r in ipairs(rows) do
            if r.endTime then want = true; break end
        end
    end
    if want and not ticker then
        ticker = C_Timer.NewTicker(TICK, Tick)
    elseif not want and ticker then
        ticker:Cancel()
        ticker = nil
    end
end

local function Layout()
    if not anchor then return end
    local step = Get("iconSize") + Get("spacing")
    local up = Get("grow") == "UP"
    local n = 0
    for _, r in ipairs(rows) do
        n = n + 1
        PlaceRow(r, n, step, up)
    end
    if sampling then
        for _, r in ipairs(sampleRows) do
            n = n + 1
            PlaceRow(r, n, step, up)
        end
    end
    anchor:SetShown(n > 0)
    UpdateTicker()
end

local function ApplyPosition()
    if not anchor then return end
    local p = P()
    local pos = p and p.pos
    local cx = (pos and pos.centerX) or 0
    local cy = (pos and pos.centerY) or 250
    if PP.SnapCenterForDim then
        cx = PP.SnapCenterForDim(cx, anchor:GetWidth())
        cy = PP.SnapCenterForDim(cy, anchor:GetHeight())
    end
    anchor:ClearAllPoints()
    anchor:SetPoint("CENTER", UIParent, "CENTER", cx, cy)
end

local function CreateAnchor()
    if anchor then return end
    anchor = CreateFrame("Frame", "EllesmereUILootRolls", UIParent)
    anchor:SetFrameStrata("HIGH")
    anchor:SetClampedToScreen(true)
    anchor:SetSize(Get("width"), Get("iconSize"))
    anchor:Hide()
    ApplyPosition()
end

local function Release(r)
    local d = r.data
    if d and d.dropKey and dropRows[d.dropKey] == r then dropRows[d.dropKey] = nil end
    if r.linger then r.linger:Cancel() end
    if r.wait then r.wait:Cancel() end
    if r.hoverOwner then HideTips() end
    r:Hide()
    r.data, r.endTime, r.linger, r.wait, r.lingerLeft, r.hoverOwner, r.onButton = nil, nil, nil, nil, nil, nil, nil
    pool[#pool + 1] = r
end

RemoveRow = function(r)
    for i, row in ipairs(rows) do
        if row == r then
            table.remove(rows, i)
            Release(r)
            Layout()
            return
        end
    end
end

local function RowOf(rollID)
    for _, r in ipairs(rows) do
        if r.data and r.data.rollID == rollID then return r end
    end
end

local function ClearRows()
    while rows[1] do Release(table.remove(rows)) end
    Layout()
end

-- The roll is over: the result shows for the result delay, held while hovered.
local function Finish(r)
    local d = r.data
    d.closed = true
    if r.wait then r.wait:Cancel(); r.wait = nil end
    EndBar(r)
    UpdateTicker()
    Fill(r)
    if r.linger then return end
    local delay = Get("resultDelay")
    if Hovered(r) then
        r.lingerLeft = math.max(r.lingerLeft or 0, delay)
    else
        StartLinger(r, delay)
    end
end

-- Out of your hands (you rolled, or the roll closed for you): the row leaves,
-- or waits for the result. A result that never comes (no history drop) lets
-- it go a little after the roll's time runs out.
local function Close(r, kind)
    local d = r.data
    if kind then d.choice = kind end
    if not Lingers() then return RemoveRow(r) end
    if d.done then return Finish(r) end
    d.closed = true
    Fill(r)
    if r.hoverOwner then ShowTip(r, r.hoverOwner) end
    if not r.wait then
        local left = r.endTime and math.max(0, r.endTime - GetTime()) or 0
        r.wait = C_Timer.NewTimer(left + 5, function()
            r.wait = nil
            if r.data ~= d or d.done then return end
            -- Hovered: it goes a moment after the mouse leaves.
            if Hovered(r) then r.lingerLeft = 1 else RemoveRow(r) end
        end)
    end
end

Rolled = function(rollID, kind)
    local r = RowOf(rollID)
    if r then Close(r, kind) end
end

-- A history drop's latest picks onto its row; a finished one ends the roll.
local function ShowDrop(r, drop)
    local d = r.data
    ReadDrop(d, drop)
    if d.done and Lingers() then
        Finish(r)
    else
        Fill(r)
    end
    if r.hoverOwner then ShowTip(r, r.hoverOwner) end
end

local function BindDrop(r, key)
    r.data.dropKey = key
    dropRows[key] = r
end

-- Binds this item's unclaimed drops in one encounter to its unclaimed rows,
-- in order: the lowest lootListID to the oldest row. The rolls start in the
-- order the drops were made, so two copies of an item keep their own results.
local function PairItem(encounterID, id)
    if not (id and C_LootHistory.GetSortedDropsForEncounter) then return end
    local free = {}
    for _, drop in ipairs(C_LootHistory.GetSortedDropsForEncounter(encounterID) or {}) do
        -- WoW Forever names the field lootListKey.
        local listID = Plain(drop.lootListID or drop.lootListKey, "number")
        local dropLink = listID and Plain(drop.itemHyperlink, "string")
        if dropLink and not dropRows[encounterID .. ":" .. listID] and not Finished(drop)
            and ItemID(dropLink) == id then
            free[#free + 1] = { listID = listID, drop = drop }
        end
    end
    if not free[1] then return end
    table.sort(free, function(a, b) return a.listID < b.listID end)
    local i = 1
    for _, r in ipairs(rows) do
        local f = free[i]
        if not f then return end
        local d = r.data
        if d and not d.dropKey and ItemID(d.link) == id then
            BindDrop(r, encounterID .. ":" .. f.listID)
            ShowDrop(r, f.drop)
            i = i + 1
        end
    end
end

local function OnDrop(encounterID, lootListID)
    if not rows[1] then return end
    encounterID, lootListID = Plain(encounterID, "number"), Plain(lootListID, "number")
    if not (encounterID and lootListID) then return end
    local drop = C_LootHistory.GetSortedInfoForDrop(encounterID, lootListID)
    if not drop then return end
    local key = encounterID .. ":" .. lootListID
    if not dropRows[key] then
        -- A finished drop nobody holds is an older one of the same item.
        if Finished(drop) then return end
        PairItem(encounterID, ItemID(Plain(drop.itemHyperlink, "string")))
    end
    local r = dropRows[key]
    if r then ShowDrop(r, drop) end
end

-- A new roll's drop may already be in the history, picks and all.
local function FindDrop(r)
    local id = ItemID(r.data.link)
    if not (id and C_LootHistory and C_LootHistory.GetAllEncounterInfos) then return end
    for _, enc in ipairs(C_LootHistory.GetAllEncounterInfos() or {}) do
        local encounterID = Plain(enc.encounterID, "number")
        if encounterID then PairItem(encounterID, id) end
        if not r.data or r.data.dropKey then return end
    end
end

local function AddRoll(rollID, rollTime)
    for _, r in ipairs(rows) do
        if r.data and r.data.rollID == rollID then return end
    end
    local d = RollData(rollID, rollTime)
    if not d then return end
    CreateAnchor()
    local r = table.remove(pool) or NewRow(anchor)
    r.data = d
    StyleRow(r)
    Fill(r)
    ArmTimer(r)
    r:Show()
    rows[#rows + 1] = r
    Layout()
    if Tracking() then FindDrop(r) end
    -- An item the client has not cached yet gets its level and bind label
    -- once it loads.
    if d.link and (not d.ilvl or d.boe == nil) then
        Item:CreateFromItemLink(d.link):ContinueOnItemLoad(function()
            if r.data ~= d then return end
            d.ilvl = ItemLevel(d.link)
            if d.boe == nil then d.boe = BindOnEquip(d.link) end
            Fill(r)
        end)
    end
end

local function OnEvent(_, event, a1, a2)
    if event == "START_LOOT_ROLL" then
        -- The style can change mid-session: its own frame has the roll.
        if not PadUI() then AddRoll(a1, a2) end
    elseif event == "CANCEL_LOOT_ROLL" then
        Rolled(a1)
    elseif event == "CANCEL_ALL_LOOT_ROLLS" then
        ClearRows()
    elseif event == "LOOT_HISTORY_UPDATE_DROP" then
        OnDrop(a1, a2)
    end
end

-- The on-screen preview, switched by the Loot page's eye: the sample items in
-- the real frame, after any live rolls.
local function ShowSamples(on)
    sampling = (on and InUse()) and true or false
    if sampling then
        CreateAnchor()
        for i, d in ipairs(SampleData()) do
            local r = sampleRows[i]
            if not r then
                r = NewRow(anchor)
                sampleRows[i] = r
            end
            r.data = d
            StyleRow(r)
            Fill(r)
            StillBar(r, d.fill)
            r:Show()
        end
    else
        for _, r in ipairs(sampleRows) do r:Hide() end
    end
    Layout()
end

-------------------------------------------------------------------------------
--  Options preview: the same rows with the sample items, drawn in the options
--  content header. Built when the Loot page first opens; listens to nothing.
-------------------------------------------------------------------------------
local preview

local RefreshPreview = function(force)
    local v = preview
    if not (v and (force or v.view:IsVisible())) then return end
    local samples = SampleData()
    local h, gap = Get("iconSize"), Get("spacing")
    for i, d in ipairs(samples) do
        local r = v.rows[i]
        if not r then
            r = NewRow(v.frame)
            v.rows[i] = r
        end
        r.data = d
        StyleRow(r)
        Fill(r)
        StillBar(r, d.fill)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", v.frame, "TOPLEFT", 0, -(i - 1) * (h + gap))
        r:Show()
    end
    local w = Get("width")
    local total = #samples * (h + gap) - gap
    local pw = v.view:GetParent():GetWidth()
    local available = (pw > 0 and pw) or v.availableWidth or w + 40
    local scale = math.min(1, math.max(100, available - 40) / w)
    v.frame:SetSize(w, total)
    v.frame:SetScale(scale)
    v.previewHeight = total * scale + 30
    v.view:SetHeight(v.previewHeight)
    if v.onHeightChanged then v.onHeightChanged(v.previewHeight) end
end

-- parent -> the dress its size hook was made for (see the Loot Feed preview):
-- a kept header root loses the hook on each new dress, so it hooks again.
local hookedParents = {}
local function CreateSettingsPreview(parent, availableWidth, onHeightChanged)
    local v = preview
    if not v then
        v = { rows = {} }
        v.view = CreateFrame("Frame", nil, parent)
        v.frame = CreateFrame("Frame", nil, v.view)
        v.frame:SetPoint("CENTER")
        v.view:SetScript("OnShow", function() RefreshPreview() end)
        preview = v
    end
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

-------------------------------------------------------------------------------
--  Apply
-------------------------------------------------------------------------------
local function ApplyStyle()
    RefreshPreview()
    if not anchor then return end
    anchor:SetSize(Get("width"), Get("iconSize"))
    for _, r in ipairs(rows) do
        StyleRow(r)
        Fill(r)
        r.timerSec = nil  -- the format may have changed
        TimerText(r)
    end
    if sampling then ShowSamples(true) end
    ApplyPosition()
    Layout()
end

-- Closes Blizzard's popup route for the rest of the session.
local function Suppress()
    if suppressed then return end
    local ge = _G.GameEvent
    if ge and type(ge.UnregisterInternalEvent) == "function" then
        ge.UnregisterInternalEvent("START_LOOT_ROLL")
        suppressed = true
    end
end

local confirmHooked = false
local function Apply()
    if not db then return end
    if Get("enabled") and not PadUI() then Suppress() end
    -- Once the route is closed the events stay, under the Gamepad style too
    -- (OnEvent leaves new rolls to its frame): rolls must reach the list
    -- again when the style is left.
    if Active() then
        CreateAnchor()
        if not events then
            events = CreateFrame("Frame")
            events:SetScript("OnEvent", OnEvent)
        end
        events:RegisterEvent("START_LOOT_ROLL")
        events:RegisterEvent("CANCEL_LOOT_ROLL")
        events:RegisterEvent("CANCEL_ALL_LOOT_ROLLS")
        if Tracking() and HISTORY then
            events:RegisterEvent("LOOT_HISTORY_UPDATE_DROP")
            -- Results just turned on: the rolls already up find their drops.
            for _, r in ipairs(rows) do
                if r.data and not r.data.dropKey then FindDrop(r) end
            end
        else
            events:UnregisterEvent("LOOT_HISTORY_UPDATE_DROP")
        end
        if not confirmHooked and type(ConfirmLootRoll) == "function" then
            confirmHooked = true
            hooksecurefunc("ConfirmLootRoll", function(rollID, rollType)
                if Active() then Rolled(rollID, KIND_OF_ROLLTYPE[rollType]) end
            end)
        end
    else
        if events then events:UnregisterAllEvents() end
        ClearRows()
        ShowSamples(false)
    end
    ApplyStyle()
end

-- A profile swap re-applies it (EllesmereUI_Profiles.lua).
_G._EUI_LootRolls_Apply = Apply

-- QoL Reset: the list's settings back to their defaults.
function _G._EUI_LootRolls_Reset()
    local prof = db and db.profile
    if not prof then return end
    prof.lootRolls = {}
    EllesmereUI.Lite.DeepMergeDefaults(prof, defaults.profile)
    Apply()
end

-------------------------------------------------------------------------------
--  Unlock Mode
-------------------------------------------------------------------------------
local function AfterResize()
    ApplyStyle()
    if EllesmereUI._unlockActive and EllesmereUI.RepositionBarToMover then
        EllesmereUI.RepositionBarToMover("EUI_LootRolls")
    end
end

local function RegisterUnlock()
    local MK = EllesmereUI.MakeUnlockElement
    if not (MK and EllesmereUI.RegisterUnlockElements) then return end
    local loadPos, clearPos = ns.CenterPosFns(P)
    EllesmereUI:RegisterUnlockElements({
        MK({
            key   = "EUI_LootRolls",
            label = "Loot Rolls",
            group = "Quality of Life",
            order = 645,
            -- The mover is the first row; the list grows from it.
            noAnchorTarget = true,
            isHidden = function() return not InUse() end,
            getFrame = function()
                CreateAnchor()
                return anchor
            end,
            getSize = function() return Get("width"), Get("iconSize") end,
            setWidth = function(_, w)
                local p = P(); if not p then return end
                p.width = math.max(200, math.min(800, PP.Snap(w)))
                AfterResize()
            end,
            setHeight = function(_, h)
                local p = P(); if not p then return end
                p.iconSize = math.max(24, math.min(64, PP.Snap(h)))
                AfterResize()
            end,
            savePos = function(_, _, _, x, y)
                local p = P(); if not p then return end
                p.pos = { centerX = x, centerY = y }
            end,
            loadPos = loadPos,
            clearPos = clearPos,
            applyPos = ApplyPosition,
        }),
    })
    -- Unlock Mode shows the mover alone.
    if EllesmereUI.RegisterUnlockModeListener then
        EllesmereUI:RegisterUnlockModeListener("EUI_LootRolls", function(active)
            if active and sampling then ShowSamples(false) end
        end)
    end
end

SamplesLoaded = function()
    RefreshPreview()
    if sampling then ShowSamples(true) end
end

-- Options-page entry points.
EllesmereUI._LootRolls = {
    Get = Get,
    Cfg = P,
    Apply = Apply,
    ApplyStyle = ApplyStyle,
    Suppressed = function() return suppressed end,
    InUse = InUse,
    CreateSettingsPreview = CreateSettingsPreview,
    RefreshPreview = function() RefreshPreview() end,
    ShowSamples = ShowSamples,
    SamplesShown = function() return sampling end,
}

-------------------------------------------------------------------------------
--  Init
-------------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    if not (EllesmereUI.Lite and EllesmereUI.Lite.NewDB) then return end
    db = EllesmereUI.Lite.NewDB("EllesmereUIQoLDB", defaults, true)
    Apply()
    RegisterUnlock()
end)
