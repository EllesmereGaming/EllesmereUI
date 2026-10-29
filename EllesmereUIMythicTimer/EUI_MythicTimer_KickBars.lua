if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  EUI_MythicTimer_KickBars.lua
--  Kick Tracker (Mythic+ Tools), the bars: one movable group with a row per
--  group member who has an interrupt (you included), in roster order: the
--  interrupt's icon, the member's name on a bar in their class colour over a
--  darkened class colour (or a custom colour), and, while their interrupt is
--  on cooldown, the seconds left on the right with its bar draining to the
--  left as the cooldown runs (full again once it is back). The
--  cooldowns are the kick engine's (ns.KickEngine): from each member's class,
--  spec and talents, your own included.
--
--  The fill is the engine's timer (SetTimerDuration on a duration object: no
--  Lua per frame); only the seconds text is painted, by a 10 Hz ticker that
--  runs while any row is on cooldown and stops itself otherwise. Zero cost
--  while off: no frames are built and nothing registers until the bars are
--  enabled, and the engine runs only while a display subscribes.
--
--  Kicks the engine cannot name: every meter update also brings a gate
--  packet, each member who could have kicked with their interrupt count
--  before and after it (hidden numbers in combat). Each of them gets a layer
--  over their row: the same row on that update's cooldown, inside a clip
--  whose left edge hangs from the fill of a hidden status bar fed the count
--  before as its value and the count after as its maximum. The fill is
--  whole, and the clip empty, unless the count rose; then the clip opens over
--  the whole row. So only the member who kicked shows the kick, and Lua never
--  learns who. Layers are pooled, the newest drawn on top, each with an
--  opaque backing so nothing under it shows through, and released when their
--  cooldown ends, when a sure kick of the member supersedes them, when the
--  member's row goes and on every mode change. A member whose party token
--  changes (the tokens close up when someone leaves) keeps their layers on
--  their new row.
--
--  The options page's header preview is a static sample of the same rows
--  (ns.KTB_PaintSample): built once, kept outside the live pool, styled by the
--  same pass, with a plain fill and text in place of the timer and ticker.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local MTWhere, KE, KD = ns.MTWhere, ns.KickEngine, EllesmereUI.KickData
if not (MTWhere and KE and KD) then return end

local db  -- Lite DB handle, handed over by ns.KTB_OnEnable

local function Cfg()
    local p = db and db.profile
    return p and p.kickTracker
end

local pairs, type = pairs, type
local floor, ceil = math.floor, math.ceil
local tremove, tinsert = table.remove, table.insert
local GetTime = GetTime
local GetRaidTargetIndex, SetRaidTargetIconTexture = GetRaidTargetIndex, SetRaidTargetIconTexture
local PP = EllesmereUI.PP

-- Fonts: module-wide family/outline/shadow (surface key "mythicTimer"), only
-- per-text sizes are settings.
local function SetFSFont(fs, size) EllesmereUI.ApplyModuleFont(fs, nil, size, "mythicTimer") end

local IMMEDIATE = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate or 0
local ELAPSED = Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.ElapsedTime or 0
local REMAINING = Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime or 1
local WHITE = "Interface\\Buttons\\WHITE8x8"

local WHERE_KEY  = "kickbars"
local WHERE_KEYS = MTWhere.NewKeySet(KE.WHERE_LIST)

local DEFAULT_X, DEFAULT_Y = -340, -120
local TICK = 0.1            -- seconds text repaint while a row is on cooldown
local TENTHS_BELOW = 10     -- seconds left shown with a tenth under this
local BG_CLASS_DARK = 0.3   -- the class colour's share in the Dark Class Color background
local BG_CLASS_ALPHA = 0.9
local MARKER_GAP = 3        -- the interrupted mob's raid marker sits this far outside the row
local MARKER_MAX = 24       -- the marker's largest size
local MODE_OFF, MODE_LIVE, MODE_PREVIEW = 0, 1, 2
-- A layer's gate: GATE_SPAN content widths (each GATE_PAD wider) long, so a
-- count that rose by one opens the clip over the whole row up to GATE_SPAN
-- interrupts in a fight; its right end sits GATE_EDGE past the content's.
local GATE_SPAN, GATE_PAD, GATE_EDGE = 100, 4, 2
local GATE_TALL = 24        -- the gate (and so the clip) this much taller than the row, centred
local LAYER_STEP = 3        -- frame levels a layer takes: holder, its bar and icon, its text
local LAYER_DEPTH = 29      -- the deepest layer stack a row draws in order

-- Preview rows: class token, interrupt, name, seconds left on a sample
-- cooldown (0 = ready), the raid marker of the mob kicked.
local PREVIEW = {
    { "WARRIOR", 6552, "Warrior", 0 },
    { "MAGE", 2139, "Mage", 9.1, 8 },
    { "DEATHKNIGHT", 47528, "Death Knight", 0 },
    { "SHAMAN", 57994, "Shaman", 4.4, 7 },
}

-- A sample row's name: its class, in the client's language.
local function SampleName(s)
    local names = LOCALIZED_CLASS_NAMES_MALE
    return (names and names[s[1]]) or s[3]
end

--------------------------------------------------------------------------------
--  State
--------------------------------------------------------------------------------
local container             -- anchor frame the unlock mover drags; built lazily
local rows = {}             -- holder pool, by slot
local shown = 0             -- rows in use
local sampleRows = {}       -- the options header's sample rows, by slot: built once, never in rows
local SAMPLE_ROWS = 3       -- sample rows painted by default (the first PREVIEW entries)
local rowOf = {}            -- unit -> holder while its row is shown
local markerOf = {}         -- unit -> raid marker index of the mob the member interrupted last (nil = none)
local markerGuid = {}       -- unit -> the member's GUID at that kick: a new occupant of the slot shows no old marker
local curMode = MODE_OFF
local previewOn = false
local styleGen = 0          -- bumped by every settings write; a row restyles when its stamp differs
local ticker                -- the seconds text ticker, nil while idle
local unlockDone = false
local layersOf = {}         -- unit -> its live layers, oldest first (one list per unit, kept)
local freeLayers = {}       -- released layers, ready for reuse
local movedLayers = {}      -- RelayLayers' scratch: layers following their member to a new token

--------------------------------------------------------------------------------
--  Container + position (unlock interchange = raw UIParent-logical center
--  delta, the Cast Bars contract).
--------------------------------------------------------------------------------
local function ApplyContainerPosition()
    if not container then return end
    local cfg = Cfg()
    local pos = cfg and cfg.barPos
    container:ClearAllPoints()
    if pos and pos.centerX and pos.centerY then
        container:SetPoint("CENTER", UIParent, "CENTER", pos.centerX, pos.centerY)
    else
        container:SetPoint("CENTER", UIParent, "CENTER", DEFAULT_X, DEFAULT_Y)
    end
end

local function EnsureContainer()
    if container then return container end
    container = CreateFrame("Frame", nil, UIParent)
    container:SetSize(200, 22)
    container:Hide()
    ApplyContainerPosition()
    return container
end

--------------------------------------------------------------------------------
--  Rows: holder > bg + icon + StatusBar fill + text. Built once per slot,
--  restyled by StyleRow. A live row hangs from the container; a sample row
--  from the options host handed in.
--------------------------------------------------------------------------------
local function BuildRow(parent)
    local holder = CreateFrame("Frame", nil, parent or EnsureContainer())
    holder:Hide()

    holder.bg = holder:CreateTexture(nil, "BACKGROUND")
    holder.bg:SetAllPoints(holder)

    holder.iconFrame = CreateFrame("Frame", nil, holder)
    holder.icon = holder.iconFrame:CreateTexture(nil, "ARTWORK")
    holder.icon:SetAllPoints(holder.iconFrame)
    holder.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    holder.sb = CreateFrame("StatusBar", nil, holder)
    -- A StatusBar has no texture object until one is set.
    holder.sb:SetStatusBarTexture(WHITE)
    holder.sb:SetMinMaxValues(0, 1)
    holder.sb:SetValue(1)

    -- Text rides a child frame so it draws above the fill and the border.
    holder.textFrame = CreateFrame("Frame", nil, holder.sb)
    holder.textFrame:SetAllPoints(holder.sb)

    -- Fonts applied at build as well as in StyleRow: SetText on a fontless
    -- FontString errors.
    holder.name = holder.textFrame:CreateFontString(nil, "OVERLAY")
    holder.name:SetJustifyH("LEFT")
    holder.name:SetWordWrap(false)
    holder.name:SetMaxLines(1)
    SetFSFont(holder.name, 11)
    holder.timer = holder.textFrame:CreateFontString(nil, "OVERLAY")
    holder.timer:SetJustifyH("RIGHT")
    holder.timer:SetWordWrap(false)
    holder.timer:SetMaxLines(1)
    SetFSFont(holder.timer, 11)

    -- The interrupted mob's raid marker, outside the row.
    holder.marker = holder:CreateTexture(nil, "ARTWORK")
    holder.marker:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    holder.marker:Hide()

    -- The fill's timer: the engine animates the bar from it.
    holder.dur = C_DurationUtil.CreateDuration()
    return holder
end

local function Row(i)
    local h = rows[i]
    if not h then
        h = BuildRow()
        rows[i] = h
    end
    return h
end

--------------------------------------------------------------------------------
--  Style pass: sizes, texture, colors, fonts, text layout. Once per settings
--  generation per row.
--------------------------------------------------------------------------------
local function StyleRow(holder, cfg)
    local w = cfg.barWidth or 200
    local h = cfg.barHeight or 22
    holder:SetSize(w, h)

    local showIcon = cfg.barShowIcon ~= false
    local iconOnRight = showIcon and cfg.barIconOnRight == true
    holder.iconFrame:ClearAllPoints()
    if iconOnRight then
        holder.iconFrame:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, 0)
        holder.iconFrame:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0)
    else
        holder.iconFrame:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
        holder.iconFrame:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0)
    end
    holder.iconFrame:SetWidth(showIcon and h or 0.001)
    holder.iconFrame:SetShown(showIcon)

    holder.sb:ClearAllPoints()
    if iconOnRight then
        holder.sb:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
        holder.sb:SetPoint("BOTTOMRIGHT", holder.iconFrame, "BOTTOMLEFT", 0, 0)
    else
        holder.sb:SetPoint("TOPLEFT", holder.iconFrame, "TOPRIGHT", 0, 0)
        holder.sb:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0)
    end

    local texPath = EllesmereUI.ResolveTexturePath(ns.barTextures, cfg.texture or "none", WHITE) or WHITE
    holder.sb:SetStatusBarTexture(texPath)
    PP.DisablePixelSnap(holder.sb:GetStatusBarTexture())

    -- Solid black border on the holder; size 0 removes it. The slider stores
    -- coordinate units, PP borders take physical pixels.
    local bsz = cfg.barBorderSize
    if bsz == nil then bsz = 0 end
    bsz = PP.ToPixels(bsz)
    if bsz > 0 then
        if not holder.border then
            -- Kept: a layer sets its frame level with the rest of its row.
            holder.border = PP.CreateBorder(holder, 0, 0, 0, 1, bsz, "OVERLAY", 7) or true
        else
            PP.UpdateBorder(holder, bsz)
        end
        PP.ShowBorder(holder)
    elseif holder.border then
        PP.HideBorder(holder)
    end

    SetFSFont(holder.name, cfg.barNameSize or 11)
    SetFSFont(holder.timer, cfg.barTimerSize or 11)
    local showTimer = cfg.barShowTimer ~= false
    local timerReserve = showTimer and ((cfg.barTimerSize or 11) * 2.4) or 0
    holder.name:ClearAllPoints()
    holder.name:SetPoint("LEFT", holder.sb, "LEFT", 4, 0)
    local nameWidth = (showIcon and (w - h) or w) - 8 - timerReserve
    if nameWidth < 1 then nameWidth = 1 end
    holder.name:SetWidth(nameWidth)
    holder.timer:ClearAllPoints()
    holder.timer:SetPoint("RIGHT", holder.sb, "RIGHT", -3, 0)
    holder.name:SetShown(cfg.barShowName ~= false)
    holder.timer:SetShown(showTimer)

    -- The raid marker beside the row, at the end away from the icon.
    local msz = h - 4
    if msz < 8 then msz = 8 elseif msz > MARKER_MAX then msz = MARKER_MAX end
    holder.marker:SetSize(msz, msz)
    holder.marker:ClearAllPoints()
    if iconOnRight then
        holder.marker:SetPoint("RIGHT", holder, "LEFT", -MARKER_GAP, 0)
    else
        holder.marker:SetPoint("LEFT", holder, "RIGHT", MARKER_GAP, 0)
    end
    holder.showMarker = cfg.barShowMarker ~= false
    -- How far the row reaches past its right edge (a layer's gate ends there).
    holder.rightReach = iconOnRight and 0 or (MARKER_GAP + msz)

    holder.styleGen = styleGen
end

-- The row's slot in the group, from the anchor frame (the container unless
-- a sample host is given).
local function PositionRow(holder, slot, cfg, anchor)
    anchor = anchor or container
    holder:ClearAllPoints()
    local off = (slot - 1) * ((cfg.barHeight or 22) + (cfg.barSpacing or 2))
    if cfg.barGrowUp then
        holder:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, off)
    else
        holder:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -off)
    end
end

--------------------------------------------------------------------------------
--  Paint
--------------------------------------------------------------------------------
-- The member: their interrupt's icon, name and class colour, the row's
-- background a darkened class colour or the custom colour. cls plain. A
-- layer's row also has its backing: the background's colour made opaque.
local function PaintMember(holder, cfg, cls, kick, name)
    local tex = kick and C_Spell.GetSpellTexture(kick)
    if tex then holder.icon:SetTexture(tex) else holder.icon:SetTexture(WHITE) end
    holder.name:SetText(name or "")
    local c = cls and C_ClassColor.GetClassColor(cls)
    local r, g, b = 0.6, 0.6, 0.6
    if c then r, g, b = c:GetRGB() end
    holder.sb:SetStatusBarColor(r, g, b)
    local br, bgr, bb, ba
    if cfg.barBgMode == "custom" then
        local bg = cfg.barBgColor
        if bg then br, bgr, bb, ba = bg.r, bg.g, bg.b, bg.a or 0.45
        else br, bgr, bb, ba = 0, 0, 0, 0.45 end
    else
        br, bgr, bb, ba = r * BG_CLASS_DARK, g * BG_CLASS_DARK, b * BG_CLASS_DARK, BG_CLASS_ALPHA
    end
    holder.bg:SetColorTexture(br, bgr, bb, ba)
    if holder.cover then holder.cover:SetColorTexture(br, bgr, bb, 1) end
end

local ArmTicker

-- The marker of the mob the member interrupted: beside the row while that
-- kick's cooldown runs and the setting allows. Inside a dungeon the index is
-- hidden; it is drawn all the same, since SetRaidTargetIconTexture is the
-- engine's SetSpriteSheetCell, which takes a secret cell. type() is the one
-- test a hidden value allows.
local function PaintMarker(holder)
    local idx = holder.showMarker and holder.readyAt and holder.markerIdx
    if type(idx) == "number" then
        SetRaidTargetIconTexture(holder.marker, idx)
        holder.marker:Show()
    else
        holder.marker:Hide()
    end
end

-- The row's cooldown: the fill is the time left, full at the kick and
-- draining to the left until start + dur; the seconds text follows from the
-- ticker. Nothing or an ended cooldown: full (an already-ended span read as
-- elapsed time is 100%), no text.
local function PaintCd(holder, start, dur)
    local now = GetTime()
    if start and dur and start + dur > now then
        holder.dur:SetTimeFromStart(start, dur)
        holder.sb:SetTimerDuration(holder.dur, IMMEDIATE, REMAINING)
        holder.readyAt = start + dur
        ArmTicker()
    else
        holder.dur:SetTimeFromStart(now - 1, 0.5)
        holder.sb:SetTimerDuration(holder.dur, IMMEDIATE, ELAPSED)
        holder.readyAt = nil
        holder.timer:SetText("")
        holder.timeShown = nil
        -- The kick's marker ends with its cooldown.
        holder.markerIdx = nil
        if holder.unit then markerOf[holder.unit] = nil end
    end
    PaintMarker(holder)
end

-- Seconds left: a tenth under TENTHS_BELOW, whole seconds (rounded up) above.
-- The text is set only when what it reads changes (timeShown: the tenths
-- shown, or minus the whole seconds); every other clear of the text drops it.
local function PaintTime(holder, remaining)
    if remaining < TENTHS_BELOW then
        local q = floor(remaining * 10 + 0.5)
        if holder.timeShown ~= q then
            holder.timeShown = q
            holder.timer:SetFormattedText("%.1f", q / 10)
        end
    else
        local s = ceil(remaining)
        if holder.timeShown ~= -s then
            holder.timeShown = -s
            holder.timer:SetFormattedText("%d", s)
        end
    end
end

--------------------------------------------------------------------------------
--  Layers: a kick the engine could not name, over the row of each member who
--  could have landed it, shown only where that member's count rose. A layer
--  is root > gate (a hidden StatusBar) + clip > a full row, built once and
--  pooled. The row is fixed over its member's row; only the clip's left edge
--  moves, with the gate's fill. Nothing is ever read back from a gate, a clip
--  or anything anchored to them.
--------------------------------------------------------------------------------
local function NewLayer()
    local L = CreateFrame("Frame", nil, EnsureContainer())
    L:Hide()
    L:EnableMouse(false)
    -- The gate draws nothing; the clip and the row are not its children, so
    -- they keep their alpha. Its fill does not snap to the pixel grid.
    local gate = CreateFrame("StatusBar", nil, L)
    gate:EnableMouse(false)
    gate:SetStatusBarTexture(WHITE)
    gate:SetAlpha(0)
    local fill = gate:GetStatusBarTexture()
    fill:SetVertexColor(0, 0, 0, 0)
    if fill.SetSnapToPixelGrid then
        fill:SetSnapToPixelGrid(false)
        fill:SetTexelSnappingBias(0)
    end
    local clip = CreateFrame("Frame", nil, L)
    clip:SetClipsChildren(true)
    clip:EnableMouse(false)
    local row = BuildRow(clip)
    -- Opaque backing under the background: neither the member's own row nor
    -- an older layer under this one shows through it.
    row.cover = row:CreateTexture(nil, "BACKGROUND", nil, -8)
    row.cover:SetAllPoints(row)
    row:Show()
    L.gate, L.fill, L.clip, L.row = gate, fill, clip, row
    return L
end

-- The counts handed to the gate (the count before as its value, after as
-- its maximum), then the clip hung from the fill again, so the clip never
-- waits for a layout the engine does not run for a fill that moved: its left
-- edge on the fill's right edge, its right edge the gate's.
local function FeedLayer(L)
    local gate, fill, clip = L.gate, L.fill, L.clip
    gate:SetMinMaxValues(0, L.after)
    gate:SetValue(L.before)
    clip:ClearAllPoints()
    clip:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
    clip:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT", 0, 0)
    clip:SetPoint("TOPRIGHT", gate, "TOPRIGHT", 0, 0)
    clip:SetPoint("BOTTOMRIGHT", gate, "BOTTOMRIGHT", 0, 0)
    L.feed = nil
end

-- Frame levels from `base`: above the member's own row, and each layer above
-- the ones before it on that row.
local function LayerLevels(L, base)
    L:SetFrameLevel(base)
    L.gate:SetFrameLevel(base)
    L.clip:SetFrameLevel(base)
    local row = L.row
    row:SetFrameLevel(base)
    row.iconFrame:SetFrameLevel(base + 1)
    row.sb:SetFrameLevel(base + 1)
    if type(row.border) == "table" then row.border:SetFrameLevel(base + 1) end
    row.textFrame:SetFrameLevel(base + 2)
end

local function LayerBase(R, depth)
    if depth > LAYER_DEPTH then depth = LAYER_DEPTH end
    return R:GetFrameLevel() + LAYER_STEP + LAYER_STEP * depth
end

-- The layer over row holder R, `depth` layers up its member's stack: the row
-- styled and laid exactly over R; the gate GATE_SPAN content widths long,
-- GATE_TALL taller than the row, its right end GATE_EDGE past the content's
-- (the marker's far edge when the marker sits on the right). A count that
-- rose shortens the fill by at least one content width, so the clip opens
-- over all of it; one that did not leaves the fill whole and the clip empty.
local function PlaceLayer(L, R, cfg, depth)
    local row = L.row
    if row.styleGen ~= styleGen then StyleRow(row, cfg) end
    local w = cfg.barWidth or 200
    local h = cfg.barHeight or 22
    L:ClearAllPoints()
    L:SetAllPoints(R)
    row:ClearAllPoints()
    row:SetAllPoints(R)
    local gate = L.gate
    gate:SetSize(GATE_SPAN * (w + MARKER_GAP + MARKER_MAX + GATE_PAD), h + GATE_TALL)
    gate:ClearAllPoints()
    gate:SetPoint("RIGHT", R, "RIGHT", (row.rightReach or 0) + GATE_EDGE, 0)
    LayerLevels(L, LayerBase(R, depth))
end

-- Back to the pool: hidden, its timer ended and its text and marker cleared
-- (its row has no unit, so no member's marker is touched), the gate whole.
local function FreeLayer(L)
    L:Hide()
    PaintCd(L.row, nil, nil)
    L.gate:SetMinMaxValues(0, 1)
    L.gate:SetValue(1)
    L.t, L.unit, L.guid, L.before, L.after, L.feed = nil, nil, nil, nil, nil, nil
    freeLayers[#freeLayers + 1] = L
end

-- The member's layers levelled again by their place in the stack (after
-- some of them left it).
local function RelevelUnit(unit)
    local list, R = layersOf[unit], rowOf[unit]
    if not (list and R) then return end
    for i = 1, #list do LayerLevels(list[i], LayerBase(R, i - 1)) end
end

-- Releases the member's layers that started at or before `upto` (all of
-- them with nil).
local function ReleaseUnit(unit, upto)
    local list = layersOf[unit]
    if not list or #list == 0 then return end
    local removed = false
    for i = #list, 1, -1 do
        local L = list[i]
        if upto == nil or L.t <= upto then
            FreeLayer(L)
            tremove(list, i)
            removed = true
        end
    end
    if removed then RelevelUnit(unit) end
end

local function ReleaseAllLayers()
    for _, list in pairs(layersOf) do
        for i = #list, 1, -1 do
            FreeLayer(list[i])
            list[i] = nil
        end
    end
end

-- The ticker's pass over the layers: an ended cooldown releases its layer, a
-- running one paints its seconds, a layer fed since the last pass is fed once
-- more. Returns whether any layer is left.
local function TickLayers(now)
    local any = false
    for unit, list in pairs(layersOf) do
        local removed = false
        for i = #list, 1, -1 do
            local L = list[i]
            local readyAt = L.row.readyAt
            if not readyAt or readyAt <= now then
                FreeLayer(L)
                tremove(list, i)
                removed = true
            else
                any = true
                if L.feed then FeedLayer(L) end
                PaintTime(L.row, readyAt - now)
            end
        end
        if removed then RelevelUnit(unit) end
    end
    return any
end

local function PaintTicks()
    local now = GetTime()
    local any = false
    for i = 1, shown do
        local holder = rows[i]
        local readyAt = holder.readyAt
        if readyAt then
            local remaining = readyAt - now
            if remaining <= 0 then
                PaintCd(holder, nil, nil)
            else
                any = true
                PaintTime(holder, remaining)
            end
        end
    end
    if TickLayers(now) then any = true end
    if not any and ticker then
        ticker:Cancel()
        ticker = nil
    end
end

ArmTicker = function()
    if ticker then return end
    ticker = C_Timer.NewTicker(TICK, PaintTicks)
    PaintTicks()
end

local function StopTicker()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
end

--------------------------------------------------------------------------------
--  Layout: a row per member with an interrupt (preview: the samples), in
--  roster order; extra rows hide; the container takes the group's size.
--------------------------------------------------------------------------------
local function UseRow(i, cfg, cls, kick, name, start, dur, unit, marker)
    local holder = Row(i)
    if holder.styleGen ~= styleGen then StyleRow(holder, cfg) end
    PositionRow(holder, i, cfg)
    holder.unit, holder.markerIdx = unit, marker
    PaintMember(holder, cfg, cls, kick, name)
    PaintCd(holder, start, dur)
    holder:Show()
    return holder
end

-- The group unit that holds `guid` now and has a row, or nil.
local function UnitWithRow(guid)
    local units = KE.GROUP_UNITS
    for i = 1, #units do
        local u = units[i]
        local m = rowOf[u] and KE.Member(u)
        if m and m.guid == guid then return u end
    end
    return nil
end

-- Every live layer over its member's row again (the rows were just laid
-- out): restyled on a new settings generation, its member painted again,
-- fed again (its gate may have changed size or row, which moves the fill's
-- edge) and once more on the ticker's next pass. A layer whose slot now
-- holds someone else follows its member to the token they hold now (the
-- party tokens close up when someone leaves), in its place by its kick's
-- time; one whose member has no row now goes. The moves are collected
-- first, so no list is created while the lists are walked.
local function RelayLayers(cfg)
    for unit, list in pairs(layersOf) do
        if #list > 0 then
            local R = rowOf[unit]
            local m = R and KE.Member(unit)
            local guid = m and m.guid
            for i = #list, 1, -1 do
                local L = list[i]
                if not guid or L.guid ~= guid then
                    tremove(list, i)
                    local to = L.guid and UnitWithRow(L.guid)
                    if to then
                        L.unit = to
                        movedLayers[#movedLayers + 1] = L
                    else
                        FreeLayer(L)
                    end
                end
            end
        end
    end
    for i = 1, #movedLayers do
        local L = movedLayers[i]
        movedLayers[i] = nil
        local list = layersOf[L.unit]
        if not list then
            list = {}
            layersOf[L.unit] = list
        end
        local at = #list + 1
        while at > 1 and list[at - 1].t > L.t do at = at - 1 end
        tinsert(list, at, L)
    end
    for unit, list in pairs(layersOf) do
        if #list > 0 then
            local R, m = rowOf[unit], KE.Member(unit)
            local name = UnitName(unit)
            for i = 1, #list do
                local L = list[i]
                PlaceLayer(L, R, cfg, i - 1)
                PaintMember(L.row, cfg, m.class, m.kick, name)
                PaintMarker(L.row)
                FeedLayer(L)
                L.feed = true
            end
        end
    end
end

local function Layout()
    local cfg = Cfg()
    if not cfg then return end
    EnsureContainer()
    local n = 0
    for u in pairs(rowOf) do rowOf[u] = nil end
    if curMode == MODE_PREVIEW then
        local now = GetTime()
        for i = 1, #PREVIEW do
            local s = PREVIEW[i]
            local left = s[4]
            local _, cd = KD.Cooldown(s[2])
            local start = left > 0 and (now - (cd - left)) or nil
            n = n + 1
            UseRow(n, cfg, s[1], s[2], SampleName(s), start, left > 0 and cd or nil, nil, s[5])
        end
    elseif curMode == MODE_LIVE then
        local units = KE.GROUP_UNITS
        local includeSelf = cfg.barIncludeSelf ~= false
        for i = 1, #units do
            local unit = units[i]
            local m = KE.Member(unit)
            if m and m.guid and m.kick and (includeSelf or unit ~= "player") then
                local start, dur = KE.Cooldown(unit)
                -- The marker belongs to the member who kicked, not the slot.
                local marker = markerOf[unit]
                if type(marker) == "number" and markerGuid[unit] ~= m.guid then
                    marker = nil
                    markerOf[unit] = nil
                end
                n = n + 1
                rowOf[unit] = UseRow(n, cfg, m.class, m.kick, UnitName(unit), start, dur, unit, marker)
            end
        end
    end
    for i = n + 1, #rows do
        rows[i]:Hide()
        rows[i].readyAt, rows[i].unit, rows[i].markerIdx = nil, nil, nil
        rows[i].marker:Hide()
    end
    shown = n
    RelayLayers(cfg)
    local h = cfg.barHeight or 22
    local sp = cfg.barSpacing or 2
    local rowsN = n > 0 and n or 1
    container:SetSize(cfg.barWidth or 200, rowsN * h + (rowsN - 1) * sp)
    container:SetShown(n > 0 or curMode == MODE_PREVIEW)
end

--------------------------------------------------------------------------------
--  Engine handlers
--------------------------------------------------------------------------------
-- A cooldown with a start is a sure kick of the member: it supersedes their
-- layers up to it. A cleared one ends all of them.
local function OnCooldown(unit, start, dur)
    if curMode ~= MODE_LIVE then return end
    ReleaseUnit(unit, start and (start + 0.01) or nil)
    local holder = rowOf[unit]
    if holder then PaintCd(holder, start, dur) end
end

local function OnRoster()
    if curMode == MODE_LIVE then Layout() end
end

-- A placed kick: the mob's raid marker rides the kicker's row while that
-- kick's cooldown runs (the cooldown event lands before or after this one).
-- Read at the kick, since the plate may be gone a moment later. In a dungeon
-- the index is hidden (type() still says number): it is kept as it is and
-- only ever handed to the engine, never compared.
local function OnKick(plateUnit, kicker)
    if curMode ~= MODE_LIVE or not kicker then return end
    local idx = plateUnit and GetRaidTargetIndex(plateUnit)
    if type(idx) ~= "number" then idx = nil end
    local m = KE.Member(kicker)
    markerOf[kicker] = idx
    markerGuid[kicker] = m and m.guid or nil
    local holder = rowOf[kicker]
    if holder then
        holder.markerIdx = idx
        PaintMarker(holder)
    end
end

-- The engine's gate packet for the meter update at t: a layer over the row of
-- each member in `units`, on their cooldown from t, fed their count before
-- and after it (hidden numbers, only ever handed to the gate), so it shows
-- only where the count rose. The marker is the first plate's kicked in that
-- update (hidden in a dungeon: kept as it is, handed to the engine only);
-- `platesOnly` adds it to the layers already made for t. The engine's
-- tables are read here and never kept.
local function OnGate(t, units, before, after, plates, platesOnly)
    if curMode ~= MODE_LIVE then return end
    local plate = plates and plates[1]
    local idx = plate and GetRaidTargetIndex(plate)
    if type(idx) ~= "number" then idx = nil end
    if platesOnly then
        if type(idx) ~= "number" then return end
        for _, list in pairs(layersOf) do
            for i = 1, #list do
                local L = list[i]
                if L.t == t then
                    L.row.markerIdx = idx
                    PaintMarker(L.row)
                end
            end
        end
        return
    end
    local cfg = Cfg()
    if not cfg then return end
    local now = GetTime()
    for i = 1, #units do
        local u = units[i]
        local R = rowOf[u]
        local dur = R and KE.KickDuration(u)
        local m = dur and KE.Member(u)
        local b, a = before[u], after[u]
        if m and m.guid and t + dur > now and b ~= nil and a ~= nil then
            local list = layersOf[u]
            if not list then
                list = {}
                layersOf[u] = list
            end
            local L = tremove(freeLayers) or NewLayer()
            list[#list + 1] = L
            L.t, L.unit, L.guid, L.before, L.after = t, u, m.guid, b, a
            PlaceLayer(L, R, cfg, #list - 1)
            PaintMember(L.row, cfg, m.class, m.kick, UnitName(u))
            L.row.unit, L.row.markerIdx = nil, idx
            FeedLayer(L)
            PaintCd(L.row, t, dur)
            L:Show()
            -- Fed once more on the ticker's next pass, as the marker rails are.
            L.feed = true
        end
    end
end

local HANDLERS = { kick = OnKick, cooldown = OnCooldown, roster = OnRoster, gate = OnGate }

--------------------------------------------------------------------------------
--  Modes
--------------------------------------------------------------------------------
local function SetMode(mode)
    if mode == curMode then return end
    if curMode == MODE_LIVE then KE.Unsubscribe(WHERE_KEY) end
    curMode = mode
    ReleaseAllLayers()
    for u in pairs(rowOf) do rowOf[u] = nil end
    for u in pairs(markerOf) do markerOf[u] = nil end
    for u in pairs(markerGuid) do markerGuid[u] = nil end
    if mode == MODE_OFF then
        StopTicker()
        for i = 1, #rows do
            rows[i]:Hide()
            rows[i].readyAt = nil
        end
        shown = 0
        if container then container:Hide() end
        return
    end
    if mode == MODE_LIVE then KE.Subscribe(WHERE_KEY, HANDLERS) end
    Layout()
end

local function Enabled(cfg)
    return cfg and cfg.enabled == true and cfg.showBars ~= false
end

-- The preview owns the display while it runs: it ignores the Where to Show
-- filter and the engine. Leaving it re-applies the filter.
local function SyncState()
    local cfg = Cfg()
    if not Enabled(cfg) then
        previewOn = false
        SetMode(MODE_OFF)
        return
    end
    if previewOn then
        SetMode(MODE_PREVIEW)
        return
    end
    if KE.Allowed() and MTWhere.Shows(cfg.whereToShow, WHERE_KEYS) then
        SetMode(MODE_LIVE)
    else
        SetMode(MODE_OFF)
    end
end

-- A loading screen ends the layers, as the engine ends its cooldowns there
-- (its cooldown callback repaints the rows). A mode change released them
-- already, with its own layout.
local function OnWhere(event)
    local was = curMode
    SyncState()
    if event == "PLAYER_ENTERING_WORLD" and curMode ~= MODE_OFF and curMode == was then
        ReleaseAllLayers()
    end
end

--------------------------------------------------------------------------------
--  Unlock mode: one group element. Registered once at init; the mover is
--  hidden while the bars are off.
--------------------------------------------------------------------------------
local function GroupSize(cfg)
    local h = cfg and cfg.barHeight or 22
    local sp = cfg and cfg.barSpacing or 2
    local n = shown > 0 and shown or 1
    return (cfg and cfg.barWidth) or 200, n * h + (n - 1) * sp
end

local function RegisterUnlock()
    if unlockDone then return end
    unlockDone = true
    local MK = EllesmereUI.MakeUnlockElement
    EllesmereUI:RegisterUnlockElements({
        MK({
            key   = "EMT_KickBars",
            label = "Kick Tracker Bars",
            group = "Mythic+",
            order = 522,
            -- Sized by the options sliders (no drag-resize handle); the group
            -- can size-match another element and be matched to.
            noResize = true,
            allowMatchSource = true,
            isHidden = function()
                return not Enabled(Cfg())
            end,
            getFrame = function()
                return EnsureContainer()
            end,
            getSize = function()
                return GroupSize(Cfg())
            end,
            setWidth = function(_, w)
                local cfg = Cfg()
                if not cfg then return end
                cfg.barWidth = floor(w + 0.5)
                ns.KTB_Refresh()
            end,
            setHeight = function(_, h)
                local cfg = Cfg()
                if not cfg then return end
                -- The group's height: a row's share of it.
                local n = shown > 0 and shown or 1
                local sp = cfg.barSpacing or 2
                cfg.barHeight = floor((h - (n - 1) * sp) / n + 0.5)
                if cfg.barHeight < 6 then cfg.barHeight = 6 end
                ns.KTB_Refresh()
            end,
            savePos = function(_, _, _, x, y)
                -- Unlock mode hands over CENTER/CENTER coords; on Cancel the
                -- frame still sits at the dragged spot, so never read the
                -- live position.
                local cfg = Cfg()
                if not (cfg and x and y) then return end
                cfg.barPos = { centerX = x, centerY = y }
                if not EllesmereUI._unlockActive then ApplyContainerPosition() end
            end,
            loadPos = function()
                local cfg = Cfg()
                local pos = cfg and cfg.barPos
                if not (pos and pos.centerX and pos.centerY) then return nil end
                return { point = "CENTER", relPoint = "CENTER", x = pos.centerX, y = pos.centerY }
            end,
            clearPos = function()
                local cfg = Cfg()
                if cfg then cfg.barPos = nil end
            end,
            applyPos = function()
                ApplyContainerPosition()
            end,
        }),
    }, "EllesmereUIMythicTimer")

    EllesmereUI:RegisterUnlockModeListener("EMT_KickBars", function(unlockActive)
        if not Enabled(Cfg()) then return end
        -- Sample rows while placing; back to live content on exit.
        ns.KTB_SetPreview(unlockActive == true)
        if not EllesmereUI.IsUnlockAnchored("EMT_KickBars") then ApplyContainerPosition() end
    end)
end

--------------------------------------------------------------------------------
--  Public surface
--------------------------------------------------------------------------------
-- ns.KT_Refresh (the nameplate icon file) calls this after every Kick Tracker
-- settings write and on the module's profile apply.
function ns.KTB_Refresh()
    local cfg = Cfg()
    if not Enabled(cfg) then
        MTWhere.Unsubscribe(WHERE_KEY)
        previewOn = false
        SetMode(MODE_OFF)
        return
    end
    styleGen = styleGen + 1
    MTWhere.Subscribe(WHERE_KEY, OnWhere)
    ApplyContainerPosition()
    SyncState()
    if curMode ~= MODE_OFF then Layout() end
end

-- Unlock mode's sample rows. Works only while the bars are enabled.
function ns.KTB_SetPreview(on)
    previewOn = on == true
    ns.KTB_Refresh()
end

function ns.KTB_IsPreview()
    return previewOn
end

-- The options header's sample: the first `n` PREVIEW rows (SAMPLE_ROWS by
-- default) hung from `host` at its TOPLEFT, styled by the live pass at the
-- current settings whatever the enable state, each cooldown a plain fill and
-- a fixed seconds text (never the timer fill or the ticker, so these rows cost
-- nothing while the header is hidden). Returns the group's width and height
-- in the host's units, or nil with no settings to paint from. The sample rows
-- are built once and kept out of `rows`, so the live layout, the ticker and
-- the modes never see them.
function ns.KTB_PaintSample(host, n)
    local cfg = Cfg()
    if not cfg then return nil end
    n = n or SAMPLE_ROWS
    if n > #PREVIEW then n = #PREVIEW end
    local now = GetTime()
    for i = 1, n do
        local holder = sampleRows[i]
        if not holder then
            holder = BuildRow(host)
            sampleRows[i] = holder
        end
        holder:SetParent(host)
        holder.styleGen = nil
        StyleRow(holder, cfg)
        PositionRow(holder, i, cfg, host)
        local s = PREVIEW[i]
        PaintMember(holder, cfg, s[1], s[2], SampleName(s))
        -- The cooldown as a still: the fill at its share, the text at the
        -- sample's seconds; readyAt stands in for "on cooldown" (PaintMarker).
        local left = s[4]
        local _, cd = KD.Cooldown(s[2])
        holder.sb:SetMinMaxValues(0, 1)
        if left > 0 and cd and cd > 0 then
            holder.sb:SetValue(left / cd)
            PaintTime(holder, left)
            holder.readyAt = now + left
        else
            holder.sb:SetValue(1)
            holder.timer:SetText("")
            holder.timeShown = nil
            holder.readyAt = nil
        end
        holder.markerIdx = s[5]
        PaintMarker(holder)
        holder.unit = nil
        holder:Show()
    end
    for i = n + 1, #sampleRows do
        sampleRows[i]:Hide()
    end
    local h = cfg.barHeight or 22
    local sp = cfg.barSpacing or 2
    return cfg.barWidth or 200, n * h + (n - 1) * sp
end

-- Called from ns.KT_OnEnable with the Lite DB.
function ns.KTB_OnEnable(database)
    db = database
    if not db then return end
    RegisterUnlock()
    ns.KTB_Refresh()
end
