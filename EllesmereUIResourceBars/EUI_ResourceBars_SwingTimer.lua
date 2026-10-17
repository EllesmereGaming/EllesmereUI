if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- EUI_ResourceBars_SwingTimer.lua
-- WoW FOREVER ONLY: Swing Timer resource bar.
--
-- Addons lost the combat log in 12.0 (no SWING_DAMAGE / SWING_MISSED), so the
-- classic swing-timer recipe is dead. Forever instead ships a native timer
-- (Blizzard_SwingTimer, AllowLoadGameType camelot) and the API under it:
--   PLAYER_SWING(swingDuration, swingType)          -- one per player swing
--   C_SwingTimer.EnableRangeCheck(swingType, bool)  -- opt in to range edges
--   PLAYER_SWING_RANGE_UPDATE(swingType, isInRange, checksRange)
--   C_SwingTimer.IsTargetWithinSwingRange(swingType) -- nil = no check possible
--   Enum.PlayerSwingType.MainHand | OffHand | Ranged
-- This file mirrors Blizzard's semantics (which rows exist, when a row restarts,
-- how out-of-range reads) on EUI's own frames; it never touches Blizzard's.
--
-- One frame, up to three ROWS (Main Hand / Off Hand / Ranged) stacked top to
-- bottom. A row exists while UnitAttackSpeed reports a speed for its slot
-- (Main Hand always does); the frame shrinks to the rows shown. Each row is a
-- StatusBar in a clip frame with bg, PP border, spark and two FontStrings
-- (remaining time, slot tag). Combine Hands takes the Off Hand row out of the
-- stack: it is laid over the Main Hand row with no bg, border, text or fill of
-- its own, so only its spark shows, riding its own engine-timed fill edge along
-- the Main Hand bar (no Lua per frame there either).
--
-- Cost on: PLAYER_SWING re-sets the row's C_DurationUtil duration object and
-- arms the bar timer (SetTimerDuration), so the engine animates the fill with
-- no Lua per frame, the way the QoL swing timer ran. The remaining-time text is
-- the engine's too: a duration text binding on the same duration object
-- writes it through a tenths formatter. Lua runs at a swing's edges only: its
-- start, and deadlines at its end (idle fill or waiting, Hide When Idle) and,
-- on a Movement Guide row, at Stop by and the last latency (the edges with no
-- event). Range and the
-- Attack State (queued, on, waiting) are event-driven
-- (PLAYER_SWING_RANGE_UPDATE, ACTIONBAR_UPDATE_STATE, the auto attack and
-- auto-repeat edges). A row whose attack is on with no swing running waits
-- (parked full), entered on the end edge or an attack edge and left on the
-- next swing or an attack-stop edge. The Movement Guide's GO and STILL zones
-- are placed once per swing, its smoothing is arithmetic on the swing start,
-- and its aim phase starts on a deadline at Stop by or a stop that ends a
-- held shot, with PLAYER_STARTED/STOPPED_MOVING registered only while a wand
-- or Auto Shot is on with that mode. An idle row costs nothing: its timer holds
-- a finished duration, which paints a static state.
--
-- Everything is gated on the swing API and the engine timer it feeds: on retail
-- this file returns right below and nothing below exists. Off by default = no
-- frame children, no events, no timers.

local _, ns = ...
local EllesmereUI = _G.EllesmereUI

-- The swing API, its enum (SwingTimerDocumentation.lua: 0/1/2) and the bar
-- timer plumbing all come from the Forever client; no fallbacks for any of them.
if not (C_SwingTimer and Enum.PlayerSwingType and C_DurationUtil
    and C_DurationUtil.CreateDuration and Enum.StatusBarTimerDirection
    and Enum.StatusBarInterpolation) then return end
local SWING = Enum.PlayerSwingType
local DIR = Enum.StatusBarTimerDirection
-- A re-arm snaps to the timer's current value: a restart mid-swing must not
-- ease back from the old fill.
local IMMEDIATE = Enum.StatusBarInterpolation.Immediate

local UNLOCK_KEY = "ERB_SwingTimer"
local MO_KEY     = "swing"   -- ERB._moEligible slot for the shared mouseover poll

-- Display order, top to bottom. `key` is the colour-key prefix in the store
-- (mhR/mhG/... ohR/... rR/..., and mhSparkR/... for the spark), `show` the
-- per-row toggle key, `melee` the rows a queued on-next-swing attack lands on.
local ROWS = {
    { type = SWING.MainHand, key = "mh", tag = "MH", show = "showMH", melee = true },
    { type = SWING.OffHand,  key = "oh", tag = "OH", show = "showOH", melee = true },
    { type = SWING.Ranged,   key = "r",  tag = "R",  show = "showR" },
}

-- On-next-swing attacks: EllesmereUI.FOREVER_NEXT_SWING (Warrior Heroic Strike
-- / Cleave, Druid Maul, Hunter Raptor Strike). While one is queued the melee
-- rows take that attack's colour and carry its name, so the swing that will
-- consume it is visible. Colours: `key` is the colour-key prefix in the store
-- (queueR/G/B/A, queueCleaveR/...), r/g/b its fallback; Cleave has its own,
-- every other attack shares "queue". Names resolve once per session and only
-- for a class that has one: ACTIONBAR_UPDATE_STATE storms in combat and is
-- registered only while there are names to compare (the paint touches the rows
-- only when the queued attack changes).
local QUEUE_COLOR  = { key = "queue", r = 1, g = 0.70, b = 0.20 }
local QUEUE_COLORS = { [845] = { key = "queueCleave", r = 0.95, g = 0.35, b = 0.25 } }  -- Cleave

-- Attack State Full, On: while a row's auto attack is on, its fill takes the On
-- colour (melee rows: Auto Attack; Ranged: the auto-repeat shot, Shoot or
-- Auto Shot). The on/off edges are events; START_AUTOREPEAT_SPELL fires on the
-- press, so a shot queued behind a cast already reads as on. AUTO_ATTACK and
-- the action slot scan seed the state the edges missed (enable, /reload
-- mid-attack).
local ACTIVE_COLOR    = { r = 0.047, g = 0.824, b = 0.616 }
local AUTO_ATTACK     = 6603
local MAX_ACTION_SLOT = 180

-- Attack State Full, Waiting: the colour of a waiting row (attack on, no swing
-- running: its timer ran out, the attack started out of range or behind a
-- cast, or moving holds the shot).
local PENDING_COLOR = { r = 0.659, g = 0.502, b = 0.949 }

-- Movement Guide smoothing: swings land around the bar end with network /
-- server jitter, so each swing starts from the expected rhythm moved SMOOTH_GAIN of
-- the way toward its arrival, instead of at the arrival. A swing further than
-- SMOOTH_TOL from the rhythm is a real interruption: start from it as is.
local SMOOTH_TOL  = 0.25
local SMOOTH_GAIN = 0.25

-- Aim: wand Shoot and Auto Shot need the player to stand still for AIM_TIME
-- before a shot (Forever beta patch note). The countdown runs alongside the
-- reported swing, from each stop, so the shot lands at the later of the
-- swing's end and AIM_TIME after the player last stopped moving, never while
-- moving: a stop must be made AIM_TIME plus one latency before the bar's end
-- (Stop by). AIM_CLASS: the classes whose Ranged row is one of the two;
-- AIM_COLOR: STILL's fallback.
local AIM_TIME  = 0.5
local AIM_CLASS = { PRIEST = true, MAGE = true, WARLOCK = true, HUNTER = true }
local AIM_COLOR = { r = 1, g = 0.82, b = 0.25 }

-- Shell at FILE SCOPE (attribution rule, see _erbEventFrame in the main file):
-- the OnEvent work bills ResourceBars. Children stay lazy.
local shell = CreateFrame("Frame", "ERB_SwingTimerFrame", UIParent)
shell:Hide()

-- built, rows[i] (row frames in ROWS order), byType[swingType] = row, shown (rows
-- stacked on screen; a combined off hand takes no slot), live (rows mid-swing),
-- rangeOn[swingType] = bool, sample (unlock mode preview on), moHooked,
-- unlockHooked, lastH (frame height last laid out), queueSpells (this class's
-- on-next-swing attacks: id, colour key + fallback, resolved name), queued (the
-- entry painted, false = none), meleeOn / repeatOn (auto attack / auto-repeat
-- on, from the edges), seeded (both read since the highlight came on), active
-- (the state painted), aimClass (this class's AIM_CLASS),
-- moveEvents / moving (the movement edges registered / the player moving).
-- Per row, _rtt (the latency read for its swing) and, on a guide row, _aimAt
-- (its Stop by point), _aiming and _aimFrom (an aim phase running, and from
-- when).
local S = { rows = {}, byType = {}, shown = 0, live = 0, rangeOn = {}, queueSpells = {}, queued = false,
            meleeOn = false, repeatOn = false, active = { melee = false, ranged = false } }

-------------------------------------------------------------------------------
--  Settings access
-------------------------------------------------------------------------------

local function P()
    local ERB = ns.ERB
    local db = ERB and ERB.db
    local p = db and db.profile
    return p and p.swingTimer or nil
end

-- Secret values throw on comparison and on truth tests: every read from the
-- swing API and from UnitAttackSpeed passes here before it is looked at, and a
-- restricted answer is treated as "no information" (no swing, no range
-- verdict, and a row keeps what was last known about it). Never infer an
-- interval from restricted data.
local function Plain(v)
    return not (issecretvalue and issecretvalue(v))
end

-- Blizzard's CanSwing: Main Hand always applies; Off Hand / Ranged only while
-- UnitAttackSpeed reports a positive speed for the slot. Those speeds are
-- secret while unit stats are restricted (SecretWhenUnitStatsRestricted), and a
-- haste proc's UNIT_ATTACK_SPEED lands right there in combat: that answer is
-- nil ("unknown"), never "no weapon".
local function CanSwing(swingType)
    if swingType == SWING.MainHand then return true end
    local _, oh, ranged = UnitAttackSpeed("player")
    local speed
    if swingType == SWING.OffHand then speed = oh
    elseif swingType == SWING.Ranged then speed = ranged
    else return false end
    if not Plain(speed) then return nil end
    return type(speed) == "number" and speed > 0
end

-- A row is shown while its toggle is on and its slot can swing: the live answer
-- when it is plain, else the last one known for that row (a swing of its type
-- is proof too, see PLAYER_SWING). Nothing known yet reads as no row.
local function RowWanted(def, cfg, row)
    if cfg and cfg[def.show] == false then return false end
    local can = CanSwing(def.type)
    if can == nil then
        can = row and row._canSwing or false
    elseif row then
        row._canSwing = can
    end
    return can
end

-- Rows the frame would stack right now (from the live rows once built, from the
-- weapon slots before). Feeds the unlock mover's size before the first build.
-- A combined off hand rides the Main Hand bar and takes no row (RefreshRows).
local function ShownCount()
    if S.built then return math.max(S.shown, 1) end
    local cfg = P()
    local n = 0
    for i = 1, #ROWS do if RowWanted(ROWS[i], cfg) then n = n + 1 end end
    -- ROWS[1] / ROWS[2] = Main Hand / Off Hand
    if cfg and cfg.combineHands and RowWanted(ROWS[1], cfg) and RowWanted(ROWS[2], cfg) then
        n = n - 1
    end
    return math.max(n, 1)
end

-- Frame size: width x (rows * height + gaps).
local function Size(cfg)
    cfg = cfg or P()
    if not cfg then return 220, 12 end
    local n = ShownCount()
    local h = cfg.height or 12
    local sp = cfg.rowSpacing or 0
    return cfg.width or 220, n * h + (n - 1) * sp
end

local function RowColor(cfg, def)
    if cfg.classColored then
        local cc = ns.CLASS_COLORS and ns.CLASS_COLORS[select(2, UnitClass("player"))]
        if cc then return cc[1], cc[2], cc[3], cfg[def.key .. "A"] or 1 end
    end
    local k = def.key
    return cfg[k .. "R"] or 1, cfg[k .. "G"] or 1, cfg[k .. "B"] or 1, cfg[k .. "A"] or 1
end

-- Spark tint: the row's own spark colour once set, else white. A combined off
-- hand's spark is its whole display: unset, it takes the row's fill colour.
-- unset: the tint it has without a colour of its own.
local function SparkColor(cfg, def, merged, unset)
    local k = def.key .. "Spark"
    local r = not unset and cfg[k .. "R"]
    if r then return r, cfg[k .. "G"] or 1, cfg[k .. "B"] or 1, cfg[k .. "A"] or 1 end
    if merged then return RowColor(cfg, def) end
    return 1, 1, 1, 1
end

-------------------------------------------------------------------------------
--  Countdown text
-------------------------------------------------------------------------------

-- The remaining time in tenths ("1.2"), written by the engine. The first table
-- also leaves the last 0.05s blank, as the text always has (never "0.0"); if
-- the client refuses it, the plain tenths table the Tracking Bars use stands
-- in. nil: no countdown (neither table taken).
local timeFormatter -- false once both tables were refused
local function TimeFormatter()
    if timeFormatter ~= nil then return timeFormatter or nil end
    timeFormatter = false
    if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter and Enum.NumericRuleFormatRounding) then
        return nil
    end
    local Nearest = Enum.NumericRuleFormatRounding.Nearest
    local tables = {
        { { threshold = 0, format = "", rounding = Nearest },
          { threshold = 0.05, format = "%.1f", rounding = Nearest } },
        { { threshold = 0, format = "%.1f", rounding = Nearest } },
    }
    for i = 1, #tables do
        local f = C_StringUtil.CreateNumericRuleFormatter()
        if pcall(f.SetBreakpoints, f, tables[i]) then
            timeFormatter = f
            return f
        end
    end
    return nil
end

-- The Text Cue's Move countdown in tenths ("Move 1.2"). nil: the client
-- refused the format, and the plain countdown stands in.
local cueFormatter -- false once refused
local function CueFormatter()
    if cueFormatter ~= nil then return cueFormatter or nil end
    cueFormatter = false
    if not TimeFormatter() then return nil end
    local f = C_StringUtil.CreateNumericRuleFormatter()
    local rule = { { threshold = 0, format = EllesmereUI.L("Move %.1f"),
        rounding = Enum.NumericRuleFormatRounding.Nearest } }
    if pcall(f.SetBreakpoints, f, rule) then cueFormatter = f end
    return cueFormatter or nil
end

-------------------------------------------------------------------------------
--  Rows
-------------------------------------------------------------------------------

local function BuildRow(def)
    local row = CreateFrame("Frame", nil, shell)
    row._def = def

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    row._bg = bg

    local bdr = CreateFrame("Frame", nil, row)
    bdr:SetAllPoints(row)
    bdr:SetFrameLevel(row:GetFrameLevel() + 5)
    row._border = bdr
    local PP = EllesmereUI and EllesmereUI.PP
    if PP then PP.CreateBorder(bdr, 0, 0, 0, 1, 1) end

    local clip = CreateFrame("Frame", nil, row)
    clip:SetClipsChildren(true)
    row._clip = clip

    local bar = CreateFrame("StatusBar", nil, clip)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    row._bar = bar
    -- One duration object per row, re-set per swing and handed to the bar
    -- timer (the QoL timer's shape); never read back in Lua.
    row._durObj = C_DurationUtil.CreateDuration()

    -- Spark (same texture/approach as the cast and GCD bars)
    local sparkFrame = CreateFrame("Frame", nil, clip)
    sparkFrame:SetAllPoints(bar)
    sparkFrame:SetFrameLevel(bar:GetFrameLevel() + 2)
    local spark = sparkFrame:CreateTexture(nil, "OVERLAY", nil, 1)
    spark:SetTexture(ns.SPARK_TEX)
    spark:SetBlendMode("ADD")
    row._spark = spark
    row._sparkFrame = sparkFrame

    -- Text above the fill; the tag on the left, the countdown on the right.
    local textFrame = CreateFrame("Frame", nil, row)
    textFrame:SetAllPoints(row)
    textFrame:SetFrameLevel(bar:GetFrameLevel() + 3)
    -- Font before any SetText: a FontString with no font errors on SetText
    -- ("Font not set", seen on the Forever client). ApplyRowLook re-sizes it.
    local tag = textFrame:CreateFontString(nil, "OVERLAY")
    ns.SetRBFont(tag, ns.GetRBFont(), 11)
    tag:SetPoint("LEFT", row, "LEFT", 4, 0)
    tag:SetJustifyH("LEFT")
    tag:SetWordWrap(false)
    tag:SetText(def.tag)
    row._tag = tag
    local time = textFrame:CreateFontString(nil, "OVERLAY")
    ns.SetRBFont(time, ns.GetRBFont(), 11)
    time:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    time:SetJustifyH("RIGHT")
    time:SetWordWrap(false)
    time:SetText("")
    row._time = time
    -- The countdown, written engine-side from the row's duration object.
    local fmt = C_DurationUtil.CreateDurationTextBinding and TimeFormatter()
    if fmt then
        local b = C_DurationUtil.CreateDurationTextBinding()
        b:SetFontString(time)
        b:SetDuration(row._durObj)
        b:SetFormatter(fmt)
        b:SetUpdateInterval(0.05)
        b:SetExpiredText("")
        b:SetZeroDurationText("")
        b:SetEnabled(false)
        row._timeBind = b
        row._timeBindOn = false
    end

    row._outOfRange = false
    return row
end

-- Out-of-range look: Blizzard dims the whole row to 0.4 and paints the text
-- red. Unlock mode suppresses the dimming without touching the state. A
-- combined off-hand row keeps no bg or border (alpha, not Hide: a border
-- re-apply shows its frame again); its range dims the clip, i.e. its spark.
local function ApplyRangeLook(row, cfg)
    cfg = cfg or P()
    local oor = row._outOfRange and not S.sample
    local alpha = oor and ((cfg and cfg.outOfRangeAlpha) or 0.4) or 1
    local frameAlpha = row._merged and 0 or alpha
    row._bg:SetAlpha(frameAlpha)
    row._border:SetAlpha(frameAlpha)
    row._clip:SetAlpha(alpha)
    if oor then
        row._tag:SetTextColor(1, 0.1, 0.1, 1)
        row._time:SetTextColor(1, 0.1, 0.1, 1)
    else
        row._tag:SetTextColor(1, 1, 1, 1)
        row._time:SetTextColor(1, 1, 1, 1)
    end
end

local function SetOutOfRange(row, oor)
    oor = oor and true or false
    if row._outOfRange == oor then return end
    row._outOfRange = oor
    ApplyRangeLook(row)
end

-- Range tracking is one engine flag per swing type, and Blizzard's own timer
-- flips it on its edges too (its Edit Mode toggle sends false for the slot), so
-- this never dedupes: every row refresh and every target change re-asserts our
-- answer, and a flip from the other frame can never leave a row undimmed.
-- S.rangeOn is the memo UpdateRangeRow reads, not a send gate.
local function SetRangeCheck(swingType, on)
    on = on and true or false
    S.rangeOn[swingType] = on
    C_SwingTimer.EnableRangeCheck(swingType, on)
end

-- Re-read range for one row from the API (target change, row shown).
local function UpdateRangeRow(row)
    if not S.rangeOn[row._def.type] then
        SetOutOfRange(row, false)
        return
    end
    -- nil = no check could be made (no target, untargetable, no weapon): NOT out of range.
    local inRange = C_SwingTimer.IsTargetWithinSwingRange(row._def.type)
    SetOutOfRange(row, Plain(inRange) and inRange == false)
end

local function UpdateRangeAll()
    for i = 1, #S.rows do
        local row = S.rows[i]
        if row:IsShown() then UpdateRangeRow(row) end
    end
end

-- Spark visibility, set on the row's edges only (swing start, swing end, look
-- apply), never per frame. Show Spark's spark shows only while its row is
-- mid-swing (not while it waits: no edge moves). A combined off-hand
-- row's spark IS the off-hand display: it ignores Show Spark and shows only
-- mid-swing. Unlock movers up show both.
local function UpdateSpark(row, cfg)
    local on
    if row._merged then
        on = row._live or S.sample
    else
        on = cfg and cfg.showSpark and ((row._live and not row._waiting) or S.sample)
    end
    row._spark:SetShown(on and true or false)
end

-- Zones mark the end of a running swing: GO (`lat`: the swing's last world
-- latency, the cast bar's ShowLatencyOverlay recipe; anything started there
-- lands after the swing) on every row, and STILL (`aim`: the AIM_TIME a wand or
-- Auto Shot needs the player still, one latency before GO; be still by its
-- edge) on a guide row in Segments. With Deplete Fill the swing ends on the
-- left under the fill, so a zone draws over it there (front); a filling bar
-- ends on the right and sweeps over a zone below it (back). Each is a
-- back/front texture pair built on first enable and placed once per swing; GO
-- draws over STILL. None on an idle, waiting or combined off-hand row.
local function HideZone(z)
    if z then
        z.back:Hide()
        z.front:Hide()
    end
end

local function HideZones(row)
    local zones = row._zones
    if zones then
        HideZone(zones.lat)
        HideZone(zones.aim)
    end
end

local function StyleZone(row, key, on, texPath, r, g, b, a, backSub, frontSub)
    local zones = row._zones
    local z = zones and zones[key]
    if not on or row._merged then
        HideZone(z)
        return
    end
    if not z then
        if not zones then
            zones = {}
            row._zones = zones
        end
        z = {
            back  = row._clip:CreateTexture(nil, "ARTWORK", nil, backSub),
            front = row._bar:CreateTexture(nil, "OVERLAY", nil, frontSub),
        }
        z.back:Hide()
        z.front:Hide()
        zones[key] = z
    end
    z.back:SetTexture(texPath)
    z.back:SetVertexColor(r, g, b, a)
    z.front:SetTexture(texPath)
    z.front:SetVertexColor(r, g, b, a)
end

-- `deplete`: the phase ends on the left (its fill drains), else on the right.
-- `offset`: seconds the zone sits back from that end (STILL, one latency).
local function PlaceZone(row, z, cfg, secs, dur, deplete, offset)
    if not (secs and secs > 0 and dur and dur > 0) then
        HideZone(z)
        return
    end
    local w = row._clip:GetWidth()
    if not (w and w > 0) then w = cfg.width or 220 end
    local off = (offset and offset > 0) and w * math.min(1, offset / dur) or 0
    local room = w - off
    if room < 1 then
        HideZone(z)
        return
    end
    local zw = w * math.min(1, secs / dur)
    if zw < 1 then zw = 1 elseif zw > room then zw = room end
    local zone = deplete and z.front or z.back
    local other = deplete and z.back or z.front
    other:Hide()
    zone:ClearAllPoints()
    if deplete then
        zone:SetPoint("TOPLEFT", row._clip, "TOPLEFT", off, 0)
        zone:SetPoint("BOTTOMLEFT", row._clip, "BOTTOMLEFT", off, 0)
    else
        zone:SetPoint("TOPRIGHT", row._clip, "TOPRIGHT", -off, 0)
        zone:SetPoint("BOTTOMRIGHT", row._clip, "BOTTOMRIGHT", -off, 0)
    end
    zone:SetWidth(zw)
    zone:Show()
end

-- World latency in seconds (home until world is measured), nil when unknown.
local function NetLatency()
    local _, _, home, world = GetNetStats()
    local ms = (world and world > 0) and world or home
    return ms and ms / 1000
end

-- Attack State: Queued Only (the default) colours a queued on-next-swing
-- attack; Full adds On and Waiting. Movement Guide (Segments or Wind-Up Bar):
-- GO on every row, smoothed swing timing, and on a guide row (the Ranged row of
-- a wand or Auto Shot class) STILL as a segment or as its own phase.
local function QueueOn(cfg) return cfg.attackState ~= "off" end
local function StateFull(cfg) return cfg.attackState == "full" end
local function GuideOn(cfg) return cfg.moveGuide == "segments" or cfg.moveGuide == "windup" end

local function GuideRow(row, cfg)
    return GuideOn(cfg) and S.aimClass and row._def.type == SWING.Ranged
end

local function WindRow(row, cfg)
    return cfg.moveGuide == "windup" and GuideRow(row, cfg)
end

local function StillRow(row, cfg)
    return cfg.moveGuide == "segments" and GuideRow(row, cfg)
end

local function StyleZones(row, cfg, texPath)
    StyleZone(row, "lat", GuideOn(cfg), texPath,
        cfg.latencyR or 0.949, cfg.latencyG or 0.957, cfg.latencyB or 0.969, cfg.latencyA or 0.9, 7, 0)
    local c = AIM_COLOR
    StyleZone(row, "aim", StillRow(row, cfg), texPath,
        cfg.aimR or c.r, cfg.aimG or c.g, cfg.aimB or c.b, cfg.aimA or 0.6, 6, -1)
end

-- Both zones on a swing, from the latency read at its start (_rtt). A Wind-Up
-- row's swing ends at its aim, not at the shot, so its GO waits for the aim
-- phase (PlaceAimLatency).
local function UpdateZones(row, cfg, dur)
    local zones = row._zones
    if not zones then return end
    local lat, aim = zones.lat, zones.aim
    local rtt = row._rtt or NetLatency() or 0
    if lat then
        if GuideOn(cfg) and not row._merged and not WindRow(row, cfg) then
            PlaceZone(row, lat, cfg, rtt, dur, cfg.depleteFill)
        else
            HideZone(lat)
        end
    end
    if aim then
        if StillRow(row, cfg) then
            PlaceZone(row, aim, cfg, AIM_TIME, dur, cfg.depleteFill, rtt)
        else
            HideZone(aim)
        end
    end
end

-- GO at the end of an aim phase, which runs opposite to the swing.
local function PlaceAimLatency(row, cfg, from, to)
    local lat = row._zones and row._zones.lat
    if lat and GuideOn(cfg) and not row._merged then
        PlaceZone(row, lat, cfg, NetLatency(), to - from, not cfg.depleteFill)
    end
end

-- Defined with the look below; the swing edges above it repaint through it.
local ApplyRowFill
-- Defined with the edge helpers below; the idle render already writes through it.
local SyncTimeText

-- The auto attack and auto-repeat edges are tracked while a feature reads them:
-- Attack State Full, or the Movement Guide for a wand or Auto Shot class.
local function TracksAttack(cfg)
    return StateFull(cfg) or (GuideOn(cfg) and S.aimClass) or false
end

-- The row's attack is on right now (melee rows: Auto Attack; Ranged: the
-- auto-repeat shot).
local function AttackOn(def)
    if def.melee then return S.meleeOn == true end
    return S.repeatOn == true
end

-- A row not mid-swing waits (parks full) while its attack is on, under Attack
-- State Full or on a guide row (a held shot). A hidden row (no weapon in the
-- slot) never waits: it would count as live and hold the bar up under Hide
-- When Idle.
local function ShouldWait(row, cfg)
    return row:IsShown() and not row._merged and AttackOn(row._def)
        and (StateFull(cfg) or GuideRow(row, cfg)) and true or false
end

-- Idle render: empty (background) by default, full of the fill colour with
-- idleShowFill. The time text is blank (no "0.0"). This is also the disarm:
-- the bar timer is re-armed on a finished duration, whose terminal state is
-- static (RemainingTime paints empty, ElapsedTime full: the GCD bar's idle
-- recipe), so the engine has nothing left to animate. The SetValue keeps the
-- value channel coherent with what is drawn.
local function IdleRow(row, cfg)
    if row._waiting or row._aiming then
        row._waiting, row._aiming = nil, nil
        if cfg then ApplyRowFill(row, cfg) end
    end
    row._aimAt = nil
    if row._live then
        row._live = nil
        S.live = S.live - 1
        UpdateSpark(row, cfg)
    end
    row._end = nil
    local full = cfg and cfg.idleShowFill == true
    local obj = row._durObj
    obj:SetTimeFromStart(GetTime() - 1, 1)
    row._bar:SetTimerDuration(obj, IMMEDIATE, full and DIR.ElapsedTime or DIR.RemainingTime)
    row._bar:SetValue(full and 1 or 0)
    SyncTimeText(row, cfg)
    row._time:SetText("")
    HideZones(row)
end

-- Defined below the waiting state; ArmEdges schedules it at a swing's edges.
local EndEdge

-- A deadline that fires a frame early still counts as its edge: the countdown
-- already reads blank in a swing's last 0.05s.
local END_SLACK = 0.05

-- The deadlines a running row needs: its end; on a guide row Stop by (a
-- Wind-Up row's aim phase, the Text Cue's Still) and, with the Text Cue, the
-- last latency (Go). Each runs EndEdge, which acts only on what is due, so a
-- stale or repeated one does nothing.
local function ArmEdges(row, cfg)
    local e = row._end
    if not e then return end
    local now = GetTime()
    C_Timer.After(math.max(e - now, 0), EndEdge)
    if not GuideRow(row, cfg) then return end
    local a = row._aimAt
    if a and not row._aiming and (cfg.moveCue or WindRow(row, cfg)) then
        C_Timer.After(math.max(a - now, 0), EndEdge)
    end
    if cfg.moveCue then
        local go = e - (row._rtt or 0)
        if go > now then C_Timer.After(go - now, EndEdge) end
    end
end

-- The Text Cue's Move countdown: a second binding on the row's time text, on a
-- duration object that ends at Stop by, reading Still once it runs out. nil
-- when the client refused the format.
local function CueBind(row)
    if row._cueBind then return row._cueBind end
    local fmt = row._timeBind and CueFormatter()
    if not fmt then return nil end
    row._cueObj = C_DurationUtil.CreateDuration()
    local b = C_DurationUtil.CreateDurationTextBinding()
    b:SetFontString(row._time)
    b:SetDuration(row._cueObj)
    b:SetFormatter(fmt)
    b:SetUpdateInterval(0.05)
    b:SetExpiredText(EllesmereUI.L("Still"))
    b:SetZeroDurationText(EllesmereUI.L("Still"))
    b:SetEnabled(false)
    row._cueBind, row._cueBindOn = b, false
    return b
end

-- The time text. Mid-swing the engine writes it: the swing's countdown, or with
-- the Text Cue on a guide row the seconds left to move until Stop by, then
-- Still and, in the swing's last latency, Go. Every other state writes its own
-- text with both bindings off. Runs at each edge and on a settings pass.
function SyncTimeText(row, cfg)
    local b = row._timeBind
    if not b then return end
    local phase
    if cfg and cfg.showTime ~= false and not row._merged and row._live and not row._waiting and not S.sample then
        phase = "swing"
        if cfg.moveCue and GuideRow(row, cfg) then
            local now = GetTime()
            if row._end and row._end - now <= (row._rtt or 0) + END_SLACK then
                phase = "go"
            elseif row._aiming or not (row._aimAt and row._start) or now >= row._aimAt - END_SLACK then
                phase = "still"
            elseif CueBind(row) then
                phase = "move"
            end
        end
    end
    local swingOn = phase == "swing"
    if swingOn then
        -- A Wind-Up row's bar runs only to Stop by; its countdown still runs to
        -- the shot, on a duration object of its own.
        local target = row._durObj
        if not row._aiming and row._start and row._end and WindRow(row, cfg) then
            local so = row._swingObj
            if not so then
                so = C_DurationUtil.CreateDuration()
                row._swingObj = so
            end
            so:SetTimeFromStart(row._start, row._end - row._start)
            target = so
        end
        if target ~= row._bindObj then
            row._bindObj = target
            b:SetDuration(target)
        end
    end
    if swingOn ~= row._timeBindOn then
        row._timeBindOn = swingOn
        b:SetEnabled(swingOn)
    end
    local cb = row._cueBind
    local moveOn = phase == "move"
    if moveOn then row._cueObj:SetTimeFromStart(row._start, math.max(row._aimAt - row._start, 0.01)) end
    if cb and moveOn ~= row._cueBindOn then
        row._cueBindOn = moveOn
        cb:SetEnabled(moveOn)
    end
    if swingOn then
        b:UpdateFontString()
    elseif moveOn then
        cb:UpdateFontString()
    elseif phase == "still" then
        row._time:SetText(EllesmereUI.L("Still"))
    elseif phase == "go" then
        row._time:SetText(EllesmereUI.L("Go"))
    end
end

-- The fill and the countdown are the engine's: the row's duration object takes
-- this swing, the bar timer animates it every frame with no Lua, draining
-- (Deplete Fill) or filling exactly as the direction says, and the countdown
-- binding writes its remaining time. The end time stays in Lua only for the
-- end edge's deadline; the duration object is never read in Lua. _due (when the
-- next swing is expected) outlives the idle render, so a swing that lands just
-- after the end edge still smooths against it (Movement Guide only). _rtt is
-- the latency read for this swing. A guide row's _aimAt is its Stop by point:
-- AIM_TIME plus one latency before the shot. A Wind-Up row's bar is the reload
-- only, up to _aimAt; a deadline there starts the aim phase.
local function StartRow(row, dur, cfg)
    if type(dur) ~= "number" or dur ~= dur or dur <= 0 or dur == math.huge then return end
    local now = GetTime()
    local start = now
    local due = row._due
    if GuideOn(cfg) and due then
        local late = now - due
        if late > -SMOOTH_TOL and late < SMOOTH_TOL then start = due + late * SMOOTH_GAIN end
    end
    row._end = start + dur
    row._due = row._end
    row._dur = dur
    row._start = start
    row._rtt = NetLatency() or 0
    local wind = WindRow(row, cfg)
    row._aimAt = GuideRow(row, cfg) and (row._end - AIM_TIME - row._rtt) or nil
    if row._waiting or row._aiming then
        row._waiting, row._aiming = nil, nil
        ApplyRowFill(row, cfg)
        UpdateSpark(row, cfg)
    end
    if not row._live then
        row._live = true
        S.live = S.live + 1
        UpdateSpark(row, cfg)
    end
    local obj = row._durObj
    obj:SetTimeFromStart(start, wind and math.max(row._aimAt - start, 0.01) or dur)
    row._bar:SetTimerDuration(obj, IMMEDIATE, cfg.depleteFill and DIR.RemainingTime or DIR.ElapsedTime)
    UpdateZones(row, cfg, dur)
    ArmEdges(row, cfg)
    SyncTimeText(row, cfg)
    if cfg.hideWhenIdle and S.live == 1 and ns.ST_UpdateVisibility then ns.ST_UpdateVisibility() end
end

-- Waiting (attack on, no swing running): parked full, in the Waiting colour
-- under Attack State Full, else the row's own. Entered from a finished swing or
-- from idle (a guide row also from a shot held by moving); the row counts as
-- live (Hide When Idle keeps it) but has no deadline. The next swing
-- (StartRow), an attack-stop edge (IdleRow) or a stop that restarts the aim
-- (EnterAim) ends it, never a timer.
local function EnterWaiting(row, cfg)
    row._waiting = true
    row._aiming = nil
    row._end = nil
    if not row._live then
        row._live = true
        S.live = S.live + 1
    end
    local obj = row._durObj
    obj:SetTimeFromStart(GetTime() - 1, 1)
    row._bar:SetTimerDuration(obj, IMMEDIATE, DIR.ElapsedTime)
    row._bar:SetValue(1)
    SyncTimeText(row, cfg)
    row._time:SetText((cfg.moveCue and cfg.showTime ~= false and GuideRow(row, cfg))
        and EllesmereUI.L("Still") or "")
    HideZones(row)
    UpdateSpark(row, cfg)
    ApplyRowFill(row, cfg)
end

-- Aim phase: the half second a wand or Auto Shot needs the player still, plus
-- one latency, as its own fill from `from` to the predicted shot `to`, in the
-- Still colour: a Wind-Up row's every swing from Stop by, and any guide row's
-- restart after a held shot. It runs opposite to the swing so the two join
-- (Deplete Fill: the reload drains, the aim fills), with GO at its end.
local function EnterAim(row, cfg, from, to)
    row._waiting = nil
    row._aiming = true
    row._aimFrom = from
    row._end = to
    if not row._live then
        row._live = true
        S.live = S.live + 1
    end
    local obj = row._durObj
    obj:SetTimeFromStart(from, to - from)
    row._bar:SetTimerDuration(obj, IMMEDIATE, cfg.depleteFill and DIR.ElapsedTime or DIR.RemainingTime)
    HideZones(row)
    PlaceAimLatency(row, cfg, from, to)
    UpdateSpark(row, cfg)
    ApplyRowFill(row, cfg)
    ArmEdges(row, cfg)
    SyncTimeText(row, cfg)
end

-- The edges, run by the deadlines ArmEdges schedules: a Wind-Up row's reload
-- done at Stop by starts its aim phase, each row whose swing is over goes idle
-- or waits while its attack is on, a running row's time text takes its next
-- step (the Text Cue's Still and Go), and Hide When Idle hides the bar once no
-- swing runs. No SetValue here, the fill is the engine's.
function EndEdge()
    local cfg = P()
    if not (cfg and cfg.enabled and S.built) then return end
    local now = GetTime()
    local running = false
    for i = 1, #S.rows do
        local row = S.rows[i]
        -- Wind-Up reload done at Stop by: the aim phase, held while moving, none
        -- once the shot is off (no shot is coming). Segments keeps its bar.
        if row._live and not row._waiting and row._aimAt and not row._aiming and now >= row._aimAt - END_SLACK
            and WindRow(row, cfg) then
            if not AttackOn(row._def) then
                IdleRow(row, cfg)
            elseif S.moving then
                EnterWaiting(row, cfg)
            else
                EnterAim(row, cfg, row._aimAt, row._end)
            end
        end
        if row._live and not row._waiting then
            if row._end - now <= END_SLACK then
                if ShouldWait(row, cfg) then EnterWaiting(row, cfg) else IdleRow(row, cfg) end
            else
                running = true
                SyncTimeText(row, cfg)
            end
        end
    end
    if not running and cfg.hideWhenIdle and ns.ST_UpdateVisibility then ns.ST_UpdateVisibility() end
end

-------------------------------------------------------------------------------
--  Layout + look
-------------------------------------------------------------------------------

-- Fill colour: the row's own (or class) colour; the On colour while its auto
-- attack is on (Attack State Full); the queued attack's own colour on a melee
-- row while an on-next-swing attack is queued (not with Attack State Off); the
-- Still colour (opaque) in an aim phase; the Waiting colour while the row waits
-- under Attack State Full (each wins over the ones before). A combined
-- off-hand row paints no fill: its bar keeps running under its spark, unseen.
function ApplyRowFill(row, cfg)
    local fillTex = row._bar:GetStatusBarTexture()
    if row._merged then
        ns.ApplyBarFlat(fillTex, 0, 0, 0, 0)
        return
    end
    local def = row._def
    local pend = row._waiting and StateFull(cfg)
    local aim = not pend and row._aiming
    local q = not (pend or aim) and def.melee and S.queued
    local act = not (pend or aim or q) and S.active[def.melee and "melee" or "ranged"]
    local fR, fG, fB, fA
    if pend then
        local c = PENDING_COLOR
        fR, fG, fB, fA = cfg.pendingR or c.r, cfg.pendingG or c.g, cfg.pendingB or c.b, cfg.pendingA or 1
    elseif aim then
        local c = AIM_COLOR
        fR, fG, fB, fA = cfg.aimR or c.r, cfg.aimG or c.g, cfg.aimB or c.b, 1
    elseif q then
        local k = q.key
        fR, fG, fB, fA = cfg[k .. "R"] or q.r, cfg[k .. "G"] or q.g, cfg[k .. "B"] or q.b, cfg[k .. "A"] or 1
    elseif act then
        local c = ACTIVE_COLOR
        fR, fG, fB, fA = cfg.activeR or c.r, cfg.activeG or c.g, cfg.activeB or c.b, cfg.activeA or 1
    else
        fR, fG, fB, fA = RowColor(cfg, def)
    end
    if cfg.gradientEnabled and not (pend or aim or q or act) then
        ns.ApplyBarGradient(fillTex, cfg.gradientDir or "HORIZONTAL", fR, fG, fB, fA,
            cfg.gradientR, cfg.gradientG, cfg.gradientB, cfg.gradientA)
    else
        ns.ApplyBarFlat(fillTex, fR, fG, fB, fA)
    end
end

-- Slot tag, with the queued attack's name on the melee rows while one is queued.
local function ApplyRowTag(row, cfg)
    local def = row._def
    if S.queued and def.melee then
        row._tag:SetText(def.tag .. " - " .. S.queued.name)
    else
        row._tag:SetText(def.tag)
    end
end

-- Which on-next-swing attack is queued right now (its S.queueSpells entry), or
-- false. Reads only the names resolved at build; a restricted answer counts as
-- not queued.
local function QueuedSpell()
    local list = S.queueSpells
    if #list == 0 or not (C_Spell and C_Spell.IsCurrentSpell) then return false end
    for i = 1, #list do
        local cur = C_Spell.IsCurrentSpell(list[i].name)
        if Plain(cur) and cur then return list[i] end
    end
    return false
end

-- Delta paint: touches the melee rows only when the queued attack changed.
local function PaintQueue(cfg)
    cfg = cfg or P()
    if not (cfg and S.built) then return end
    local queued = QueueOn(cfg) and QueuedSpell() or false
    if queued == S.queued then return end
    S.queued = queued
    for i = 1, #S.rows do
        local row = S.rows[i]
        if row._def.melee then
            ApplyRowFill(row, cfg)
            ApplyRowTag(row, cfg)
        end
    end
end

-- One-shot read of both states, for the edges this frame was not listening
-- to: the action bars' own auto-repeat test, and Auto Attack as the current
-- spell. The edges keep them current from here.
local function SeedActive()
    S.seeded = true
    local rep = false
    local isRep = C_ActionBar and C_ActionBar.IsAutoRepeatAction
    if isRep then
        for slot = 1, MAX_ACTION_SLOT do
            local v = isRep(slot)
            if Plain(v) and v then rep = true; break end
        end
    end
    S.repeatOn = rep
    local cur = C_Spell and C_Spell.IsCurrentSpell and C_Spell.IsCurrentSpell(AUTO_ATTACK)
    S.meleeOn = (Plain(cur) and cur) and true or false
end

-- Delta paint: touches only the rows whose active state flipped.
local function PaintActive(cfg)
    cfg = cfg or P()
    if not (cfg and S.built) then return end
    local on = StateFull(cfg)
    local melee = on and S.meleeOn == true
    local ranged = on and S.repeatOn == true
    local A = S.active
    local dMelee, dRanged = melee ~= A.melee, ranged ~= A.ranged
    if not (dMelee or dRanged) then return end
    A.melee, A.ranged = melee, ranged
    for i = 1, #S.rows do
        local row = S.rows[i]
        if (row._def.melee and dMelee) or (not row._def.melee and dRanged) then
            ApplyRowFill(row, cfg)
        end
    end
end

-- Matches every row not mid-swing to its attack: waiting while it is on, idle
-- once it stops. Runs on the attack edges, after a loading screen and when the
-- weapon rows change; a row mid-swing is left to its end edge.
local function SyncWaiting(cfg)
    local changed = false
    for i = 1, #S.rows do
        local row = S.rows[i]
        if not (row._live and not row._waiting) then
            if ShouldWait(row, cfg) then
                if not row._waiting then
                    EnterWaiting(row, cfg)
                    changed = true
                end
            elseif row._waiting then
                IdleRow(row, cfg)
                changed = true
            end
        end
    end
    if changed and cfg.hideWhenIdle and ns.ST_UpdateVisibility then ns.ST_UpdateVisibility() end
end

-- Stack the applicable rows and size the frame to them; a combined off-hand
-- row is laid over the Main Hand row instead of taking a slot. Returns true
-- when the frame height changed (anchored neighbours need a nudge).
local function Layout(cfg)
    local h = cfg.height or 12
    local sp = cfg.rowSpacing or 0
    local w = cfg.width or 220
    local idx = 0
    for i = 1, #S.rows do
        local row = S.rows[i]
        if row:IsShown() then
            row:ClearAllPoints()
            if row._merged then
                row:SetAllPoints(S.byType[SWING.MainHand])
            else
                row:SetPoint("TOPLEFT", shell, "TOPLEFT", 0, -idx * (h + sp))
                row:SetSize(w, h)
                idx = idx + 1
            end
        end
    end
    S.shown = idx
    local n = math.max(idx, 1)
    local totalH = n * h + (n - 1) * sp
    shell:SetSize(w, totalH)
    local changed = S.lastH ~= nil and S.lastH ~= totalH
    S.lastH = totalH
    return changed
end

local function ApplyRowLook(row, cfg, w, h)
    row._restyle = nil
    local PP = EllesmereUI.PP
    local bs = cfg.borderSize or 0
    local bdr = row._border
    local pl = row:GetFrameLevel()
    bdr:SetFrameLevel(cfg.borderBehind and math.max(0, pl - 1) or (pl + 5))
    -- Lost-rect recovery, see the cast bar border in the main file.
    if not bdr:GetLeft() then bdr:SetAllPoints(row) end
    EllesmereUI.ApplyBorderStyle(bdr, bs,
        cfg.borderR or 0, cfg.borderG or 0, cfg.borderB or 0, cfg.borderA or 1,
        cfg.borderTexture or "solid", cfg.borderTextureOffset, cfg.borderTextureOffsetY,
        cfg.borderTextureShiftX, cfg.borderTextureShiftY, "resourcebars", bs,
        nil, EllesmereUI.BorderPx(cfg.borderSizePx, bs, cfg.borderTexture or "solid"))

    -- Clip + bar layout. The 1px inset keeps the fill from bleeding past the
    -- border; with no border there is nothing to clip to, so skip it.
    local clip, bar = row._clip, row._bar
    local inset = (bs > 0 and PP and PP.mult) or 0
    clip:ClearAllPoints()
    clip:SetPoint("TOPLEFT", row, "TOPLEFT", inset, -inset)
    clip:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -inset, inset)
    clip:SetFrameLevel(pl + 1)
    bar:ClearAllPoints()
    bar:SetAllPoints(clip)

    local texPath = EllesmereUI.ResolveTexturePath(_G._ERB_BarTextures, cfg.texture, "Interface\\Buttons\\WHITE8x8")
    bar:SetStatusBarTexture(texPath)
    bar:SetOrientation("HORIZONTAL")
    bar:SetRotatesTexture(false)
    bar:SetReverseFill(false)
    row._bg:SetTexture(nil)
    row._bg:SetColorTexture(cfg.bgR or 0, cfg.bgG or 0, cfg.bgB or 0, cfg.bgA or 0.7)
    StyleZones(row, cfg, texPath)

    ApplyRowFill(row, cfg)

    -- Leading-edge spark: anchored to the fill texture's moving edge so it
    -- tracks the fill (the GCD bar's horizontal case). On a combined off-hand
    -- row it is the whole display. An overhang reaches past the bar's top and
    -- bottom: the spark leaves the bar's clip (and the rounded body) for a clip
    -- of its own, built on first use, that still cuts it at the bar's ends.
    local spark, sparkFrame = row._spark, row._sparkFrame
    local over = cfg.sparkOverhang or 0
    if over > 0 then
        local sc = row._sparkClip
        if not sc then
            sc = CreateFrame("Frame", nil, row)
            sc:SetClipsChildren(true)
            row._sparkClip = sc
        end
        sc:ClearAllPoints()
        sc:SetPoint("TOPLEFT", clip, "TOPLEFT", 0, over)
        sc:SetPoint("BOTTOMRIGHT", clip, "BOTTOMRIGHT", 0, -over)
        sc:SetFrameLevel(bar:GetFrameLevel() + 1)
        sparkFrame:SetParent(sc)
    else
        sparkFrame:SetParent(clip)
    end
    sparkFrame:SetFrameLevel(bar:GetFrameLevel() + 2)
    spark:ClearAllPoints()
    spark:SetSize(cfg.sparkWidth or 8, h + 2 * over)
    spark:SetPoint("CENTER", bar:GetStatusBarTexture(), "RIGHT", 0, 0)
    spark:SetVertexColor(SparkColor(cfg, row._def, row._merged))
    UpdateSpark(row, cfg)

    local size = cfg.textSize or 11
    ns.SetRBFont(row._tag, ns.GetRBFont(), size)
    ns.SetRBFont(row._time, ns.GetRBFont(), size)
    -- Label on the left, time on the right, each with its own offsets.
    row._tag:ClearAllPoints()
    row._tag:SetPoint("LEFT", row, "LEFT", 4 + (cfg.labelX or 0), cfg.labelY or 0)
    row._time:ClearAllPoints()
    row._time:SetPoint("RIGHT", row, "RIGHT", -4 + (cfg.timeX or 0), cfg.timeY or 0)
    ApplyRowTag(row, cfg)
    -- A combined off-hand row shows no text; the Main Hand row keeps its own.
    local merged = row._merged
    if cfg.showLabel ~= false and not merged then row._tag:Show() else row._tag:Hide() end
    if cfg.showTime ~= false and not merged then row._time:Show() else row._time:Hide() end
    ApplyRangeLook(row, cfg)
    -- Rounded corners (EllesmereUI_RoundedCorners.lua; nothing at radius 0).
    -- A combined off-hand row is only a spark over the Main Hand row: no fill.
    local radius = cfg.cornerRadius or 0
    if radius > 0 then
        EllesmereUI.RoundCorners(row, radius, {
            roots = { clip }, textures = { row._bg },
            border = not merged and bdr or nil, clip = clip,
            style = cfg.borderTexture or "solid", corners = cfg.cornerMask,
        })
    else
        EllesmereUI.RoundCorners(row, 0)
    end
end

local function ApplyLook(cfg)
    local w, h = cfg.width or 220, cfg.height or 12
    for i = 1, #S.rows do ApplyRowLook(S.rows[i], cfg, w, h) end
end

-- Restyles the rows RefreshRows marked (see there).
local function RestyleMarked(cfg)
    local w, h = cfg.width or 220, cfg.height or 12
    for i = 1, #S.rows do
        local row = S.rows[i]
        if row._restyle then ApplyRowLook(row, cfg, w, h) end
    end
end

-- Show/hide rows to the weapon slots, then re-stack. Also the range-check
-- registration: on for every shown row while the option is on, off otherwise
-- (a combined off hand keeps its own: it still needs its swings, and its range
-- dims its spark). Combine Hands merges the Off Hand row only while the Main
-- Hand row is shown too (ROWS puts Main Hand first). Marks the rows whose
-- merge flipped or that just came back (styled while hidden at 0x0, their
-- textured border never painted) and returns true when any was marked:
-- ST_Apply restyles every row once the frame is placed, the events restyle
-- just those (RestyleMarked), so an off hand equipped or dropped mid-session
-- takes the right look without an options apply.
local function RefreshRows(cfg)
    cfg = cfg or P()
    if not (cfg and S.built) then return end
    local wantRange = cfg.enabled and cfg.rangeCheck ~= false
    local mhShown, marked = false, false
    for i = 1, #S.rows do
        local row = S.rows[i]
        local def = row._def
        local can = RowWanted(def, cfg, row)
        if can then
            if not row:IsShown() then
                row._restyle = true
                marked = true
            end
            row:Show()
        else
            row:Hide()
            if row._live then IdleRow(row, cfg) end
        end
        if def.type == SWING.MainHand then mhShown = can end
        local merged = (def.type == SWING.OffHand and can and mhShown and cfg.combineHands) and true or nil
        if merged ~= row._merged then
            row._merged = merged
            row._restyle = true
            marked = true
        end
        SetRangeCheck(def.type, wantRange and can)
    end
    if Layout(cfg) and EllesmereUI.NotifyElementResized then
        EllesmereUI.NotifyElementResized(UNLOCK_KEY)
    end
    UpdateRangeAll()
    return marked
end

-- Position: the unlock anchor chain first, then a saved unlock position, then
-- the CENTER offsets. Same three-way split as the GCD bar.
local function ApplyPosition(cfg)
    local w, h = Size(cfg)
    shell:SetSize(w, h)
    if EllesmereUI._TryOverrideAnchor and EllesmereUI._TryOverrideAnchor(UNLOCK_KEY, shell) then
        return
    end
    if EllesmereUI._unlockActive then return end
    local pos = cfg.unlockPos
    if pos and pos.point then
        local anchored = EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored(UNLOCK_KEY)
        if anchored and shell:GetLeft() then return end
        local rp = pos.relPoint or pos.point
        local sx, sy = ns.SnapXY(pos.x or 0, pos.y or 0, shell, pos)
        shell:ClearAllPoints()
        shell:SetPoint(pos.point, UIParent, rp, sx, sy)
    else
        shell:ClearAllPoints()
        shell:SetPoint("CENTER", UIParent, "CENTER", cfg.anchorX or 0, cfg.anchorY or 0)
    end
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------

-- The movement edges a guide row holds and restarts its aim on, only while an
-- aim can run: the Movement Guide on, a wand or Auto Shot class, and the shot on.
-- Registering reads where the player is now (GetUnitSpeed, restricted = still).
local function ApplyMoveEvents(cfg)
    if not S.events then return end
    if S.aimClass and GuideOn(cfg) and S.repeatOn then
        if not S.moveEvents then
            S.moveEvents = true
            shell:RegisterEvent("PLAYER_STARTED_MOVING")
            shell:RegisterEvent("PLAYER_STOPPED_MOVING")
            local speed = GetUnitSpeed("player")
            S.moving = (Plain(speed) and speed > 0) and true or false
        end
    elseif S.moveEvents then
        S.moveEvents = nil
        shell:UnregisterEvent("PLAYER_STARTED_MOVING")
        shell:UnregisterEvent("PLAYER_STOPPED_MOVING")
        S.moving = false
    end
end

shell:SetScript("OnEvent", function(self, event, a1, a2, a3)
    local cfg = P()
    if not (cfg and cfg.enabled and S.built) then return end
    if event == "PLAYER_SWING" then
        -- a1 = swingDuration, a2 = swingType
        if not (Plain(a1) and Plain(a2)) then return end
        local row = S.byType[a2]
        if row then
            -- A swing proves its slot can swing: a row hidden only because its
            -- speed read was restricted comes back with it.
            if not row:IsShown() and not row._canSwing and cfg[row._def.show] ~= false then
                row._canSwing = true
                if RefreshRows(cfg) then RestyleMarked(cfg) end
            end
            if row:IsShown() then StartRow(row, a1, cfg) end
        end
        PaintQueue(cfg)
    elseif event == "ACTIONBAR_UPDATE_STATE" then
        PaintQueue(cfg)
    elseif event == "START_AUTOREPEAT_SPELL" or event == "STOP_AUTOREPEAT_SPELL" then
        S.repeatOn = event == "START_AUTOREPEAT_SPELL"
        if not S.repeatOn then
            -- No shot is coming: an aim in progress ends with it.
            local row = S.byType[SWING.Ranged]
            if row and row._aiming then IdleRow(row, cfg) end
        end
        ApplyMoveEvents(cfg)
        SyncWaiting(cfg)
        PaintActive(cfg)
    elseif event == "PLAYER_STARTED_MOVING" then
        -- Moving holds the shot: an aim in progress stops and waits.
        S.moving = true
        local row = S.byType[SWING.Ranged]
        if row and row._aiming then EnterWaiting(row, cfg) end
    elseif event == "PLAYER_STOPPED_MOVING" then
        -- Standing still again: a shot held, or stopped for only after Stop by,
        -- fires AIM_TIME from now plus the round trip (the stop reaches the
        -- server, the swing comes back). Both guide styles show it as an aim.
        S.moving = false
        local row = S.byType[SWING.Ranged]
        if row and row._live and GuideRow(row, cfg) and AttackOn(row._def) then
            local now = GetTime()
            if row._waiting or (row._aimAt and not row._aiming and now >= row._aimAt) then
                local shot = now + AIM_TIME + (NetLatency() or 0)
                if row._end and row._end > shot then shot = row._end end
                EnterAim(row, cfg, now, shot)
                row._due = shot
            end
        end
    elseif event == "PLAYER_ENTER_COMBAT" or event == "PLAYER_LEAVE_COMBAT" then
        S.meleeOn = event == "PLAYER_ENTER_COMBAT"
        SyncWaiting(cfg)
        PaintActive(cfg)
    elseif event == "PLAYER_DEAD" then
        for i = 1, #S.rows do
            if S.rows[i]._live then IdleRow(S.rows[i], cfg) end
        end
        S.meleeOn, S.repeatOn = false, false
        ApplyMoveEvents(cfg)
        PaintActive(cfg)
    elseif event == "PLAYER_SWING_RANGE_UPDATE" then
        -- a1 = swingType, a2 = isInRange, a3 = checksRange
        if not (Plain(a1) and Plain(a2) and Plain(a3)) then return end
        local row = S.byType[a1]
        if row then SetOutOfRange(row, a3 == true and a2 == false) end
    elseif event == "PLAYER_TARGET_CHANGED" then
        -- Re-assert the range flags before the re-read (see SetRangeCheck).
        local wantRange = cfg.rangeCheck ~= false
        for i = 1, #S.rows do
            local row = S.rows[i]
            SetRangeCheck(row._def.type, wantRange and row:IsShown())
        end
        UpdateRangeAll()
    else
        -- WEAPON_SLOT_CHANGED / UNIT_ATTACK_SPEED / PLAYER_ENTERING_WORLD
        if RefreshRows(cfg) then RestyleMarked(cfg) end
        if TracksAttack(cfg) then
            -- A loading screen can end an attack without its edge reaching us.
            if event == "PLAYER_ENTERING_WORLD" then
                SeedActive()
                ApplyMoveEvents(cfg)
            end
            -- A row the weapon change just showed takes its attack's state.
            SyncWaiting(cfg)
            PaintActive(cfg)
        end
    end
end)

local function RegisterEvents()
    if S.events then return end
    S.events = true
    shell:RegisterEvent("PLAYER_SWING")
    shell:RegisterEvent("PLAYER_SWING_RANGE_UPDATE")
    shell:RegisterEvent("PLAYER_TARGET_CHANGED")
    shell:RegisterEvent("WEAPON_SLOT_CHANGED")
    shell:RegisterEvent("PLAYER_ENTERING_WORLD")
    shell:RegisterEvent("PLAYER_DEAD")
    shell:RegisterUnitEvent("UNIT_ATTACK_SPEED", "player")
end

-- The queue paint's event is registered only while the highlight is on (it is
-- the one chatty event here).
local function ApplyQueueEvents(cfg)
    if not S.events then return end
    if QueueOn(cfg) and #S.queueSpells > 0 then
        shell:RegisterEvent("ACTIONBAR_UPDATE_STATE")
    else
        shell:UnregisterEvent("ACTIONBAR_UPDATE_STATE")
    end
end

-- The auto attack and auto-repeat edges, only while something reads them
-- (TracksAttack).
local function ApplyActiveEvents(cfg)
    if not S.events then return end
    if TracksAttack(cfg) then
        shell:RegisterEvent("START_AUTOREPEAT_SPELL")
        shell:RegisterEvent("STOP_AUTOREPEAT_SPELL")
        shell:RegisterEvent("PLAYER_ENTER_COMBAT")
        shell:RegisterEvent("PLAYER_LEAVE_COMBAT")
    else
        shell:UnregisterEvent("START_AUTOREPEAT_SPELL")
        shell:UnregisterEvent("STOP_AUTOREPEAT_SPELL")
        shell:UnregisterEvent("PLAYER_ENTER_COMBAT")
        shell:UnregisterEvent("PLAYER_LEAVE_COMBAT")
    end
end

local function UnregisterEvents()
    if not S.events then return end
    S.events = nil
    S.moveEvents, S.moving = nil, false
    shell:UnregisterAllEvents()
end

-------------------------------------------------------------------------------
--  Build / apply
-------------------------------------------------------------------------------

local function EnsureBuilt()
    if S.built then return end
    S.built = true
    shell:SetFrameLevel(15)
    for i = 1, #ROWS do
        local row = BuildRow(ROWS[i])
        S.rows[i] = row
        S.byType[ROWS[i].type] = row
    end
    local _, classFile = UnitClass("player")
    S.aimClass = AIM_CLASS[classFile]
    -- On-next-swing spell names, once per session, for a class that has one.
    local ids = EllesmereUI.FOREVER_NEXT_SWING and EllesmereUI.FOREVER_NEXT_SWING[classFile]
    if ids and C_Spell and C_Spell.GetSpellName then
        for i = 1, #ids do
            local name = C_Spell.GetSpellName(ids[i])
            if Plain(name) and name then
                local c = QUEUE_COLORS[ids[i]] or QUEUE_COLOR
                S.queueSpells[#S.queueSpells + 1] = { id = ids[i], key = c.key, r = c.r, g = c.g, b = c.b, name = name }
            end
        end
    end
    -- Mouseover hover-reveal: same plain-table proxy the class/power/health bars
    -- register, gated on the eligibility flag ST_UpdateVisibility maintains.
    if not S.moHooked and EllesmereUI.RegisterMouseoverTarget then
        S.moHooked = true
        local proxy = {}
        proxy.GetRect = function() return shell:GetRect() end
        proxy.GetEffectiveScale = function() return shell:GetEffectiveScale() end
        proxy.SetAlpha = function() end
        proxy.EnableMouse = function() end
        proxy.Show = function() EllesmereUI.SetElementVisibility(shell, true) end
        proxy.Hide = function() EllesmereUI.SetElementVisibility(shell, false) end
        EllesmereUI.RegisterMouseoverTarget(proxy, function()
            local ERB = ns.ERB
            return ERB and ERB._moEligible and ERB._moEligible[MO_KEY] or false
        end)
    end
end

-- Off: drop events and range checks, and idle every live row (its bar timer is
-- parked on a finished duration, its countdown off; a pending end-edge deadline
-- finds the timer off and does nothing); the frame stays shown at alpha 0
-- so anchored neighbours keep a valid rect (SetElementVisibility rule).
local function Teardown()
    if not S.built then return end
    UnregisterEvents()
    S.seeded = nil  -- the edges stop here: re-read on the next enable
    local cfg = P()
    for i = 1, #S.rows do
        local row = S.rows[i]
        if row._live then IdleRow(row, cfg) end
        SetRangeCheck(row._def.type, false)
    end
    local ERB = ns.ERB
    if ERB and ERB._moEligible then ERB._moEligible[MO_KEY] = false end
    EllesmereUI.SetElementVisibility(shell, false)
end

-- Visibility pass: runs from the main file's UpdateVisibility on every edge it
-- sees (combat, target, group, zone, custom conditional) and from the swing
-- edges hideWhenIdle cares about.
function ns.ST_UpdateVisibility()
    if not S.built then return end
    local cfg = P()
    local ERB = ns.ERB
    if not (cfg and cfg.enabled and ERB) then return end
    local vis
    if EllesmereUI._unlockActive then
        vis = true
    else
        vis = not ERB._inVehicle and ns.ShouldShowBar(cfg)
        if vis and cfg.hideWhenIdle and S.live == 0 then vis = false end
    end
    ERB._moEligible = ERB._moEligible or {}
    ERB._moEligible[MO_KEY] = (vis == "mouseover")
    EllesmereUI.SetElementVisibility(shell, vis == true)
end

-- The colour a row's spark paints (by colour key), for the options swatch;
-- unset = true gives the tint it has without a colour of its own.
function ns.ST_SparkColor(key, unset)
    local cfg = P()
    if not cfg then return 1, 1, 1, 1 end
    for i = 1, #ROWS do
        if ROWS[i].key == key then
            local row = S.rows[i]
            return SparkColor(cfg, ROWS[i], row and row._merged, unset)
        end
    end
    return 1, 1, 1, 1
end

function ns.ST_Apply()
    local cfg = P()
    if not cfg or not cfg.enabled then
        Teardown()
        return
    end
    EnsureBuilt()
    shell:SetFrameStrata(cfg.frameStrata or "MEDIUM")
    shell:Show()
    RegisterEvents()
    ApplyQueueEvents(cfg)
    ApplyActiveEvents(cfg)
    -- Highlight turned off with an attack queued: the paint below must clear it.
    if not QueueOn(cfg) then S.queued = false end
    -- Attack state: read once per enable, kept by the edges while on.
    if not TracksAttack(cfg) then
        S.seeded = nil
    elseif not S.seeded then
        SeedActive()
    end
    ApplyMoveEvents(cfg)
    -- Size and stack the rows BEFORE styling them: the textured border is a
    -- BackdropTemplate nine-slice keyed on first setup, and set up on a 0x0
    -- row it never paints (cast/GCD bars size first for the same reason).
    RefreshRows(cfg)
    ApplyPosition(cfg)
    ApplyLook(cfg)
    PaintQueue(cfg)
    PaintActive(cfg)
    -- Every row takes its paint here on every apply, always by re-arming the
    -- bar timer, never by a plain SetValue: a parked timer keeps painting its
    -- terminal state and SetValue does not repaint it (the GCD bar's idle
    -- recipe). Unlock movers up: a full bar with a sample time. A row
    -- mid-swing: its running swing (or Wind-Up reload / aim phase) again, in
    -- the direction now configured (unlock exit, a Deplete Fill or Movement
    -- Guide change). A row whose attack is on: parked
    -- full (waiting), also when the option just came on mid-attack. Otherwise
    -- the idle render, so a Show Fill Color When Idle change shows at once, not
    -- at the next swing's end.
    for i = 1, #S.rows do
        local row = S.rows[i]
        local obj = row._durObj
        if S.sample then
            -- A combined off hand parks empty, so its spark shows at the far
            -- end from a full Main Hand bar's.
            local oh = row._merged
            obj:SetTimeFromStart(GetTime() - 1, 1)
            row._bar:SetTimerDuration(obj, IMMEDIATE, oh and DIR.RemainingTime or DIR.ElapsedTime)
            row._bar:SetValue(oh and 0 or 1)
            SyncTimeText(row, cfg)
            row._time:SetText("1.2")
            UpdateZones(row, cfg, row._dur or 2)
        elseif row._live and not row._waiting and row._dur then
            local guide, wind = GuideRow(row, cfg), WindRow(row, cfg)
            if not guide and (row._aiming or row._aimAt) then
                -- Movement Guide turned off mid-swing: back to one plain swing.
                row._aiming, row._aimAt = nil, nil
                ApplyRowFill(row, cfg)
            end
            if row._aiming then
                obj:SetTimeFromStart(row._aimFrom, row._end - row._aimFrom)
                row._bar:SetTimerDuration(obj, IMMEDIATE, cfg.depleteFill and DIR.ElapsedTime or DIR.RemainingTime)
                HideZones(row)
                PlaceAimLatency(row, cfg, row._aimFrom, row._end)
            else
                local start = row._end - row._dur
                row._start = start
                if guide then row._aimAt = row._end - AIM_TIME - (row._rtt or 0) end
                obj:SetTimeFromStart(start, wind and math.max(row._aimAt - start, 0.01) or row._dur)
                row._bar:SetTimerDuration(obj, IMMEDIATE, cfg.depleteFill and DIR.RemainingTime or DIR.ElapsedTime)
                UpdateZones(row, cfg, row._dur)
            end
            ArmEdges(row, cfg)
            SyncTimeText(row, cfg)
        elseif ShouldWait(row, cfg) then
            EnterWaiting(row, cfg)
        else
            IdleRow(row, cfg)
        end
    end
    ns.ST_UpdateVisibility()
end

-------------------------------------------------------------------------------
--  Unlock element
-------------------------------------------------------------------------------

function ns.ST_MakeUnlockElement(MK, Rebuild)
    if not MK then return nil end
    local PP = EllesmereUI.PP

    if not S.unlockHooked and EllesmereUI.RegisterUnlockModeListener then
        S.unlockHooked = true
        EllesmereUI:RegisterUnlockModeListener(UNLOCK_KEY, function(active)
            -- Sample fill while the movers are up so an idle bar has something
            -- to drag; ST_Apply restores the real state on exit.
            S.sample = active and true or nil
            if ns.ST_Apply then ns.ST_Apply() end
        end)
    end

    local function save(key, point, relPoint, x, y)
        if not point then return end
        local cfg = P(); if not cfg then return end
        cfg.unlockPos = { point = point, relPoint = relPoint or point, x = x, y = y }
        if not EllesmereUI._unlockActive and S.built then
            shell:ClearAllPoints()
            shell:SetPoint(point, UIParent, relPoint or point, x, y)
        end
    end
    local function load()
        local cfg = P()
        local pos = cfg and cfg.unlockPos
        if not pos then return nil end
        return { point = pos.point, relPoint = pos.relPoint or pos.point, x = pos.x, y = pos.y }
    end
    local function clear()
        local cfg = P(); if not cfg then return end
        cfg.unlockPos = nil
        cfg.anchorX = 0; cfg.anchorY = -130
    end
    local function apply()
        local cfg = P()
        local pos = cfg and cfg.unlockPos
        if not (pos and S.built) then return end
        local sx, sy = ns.SnapXY(pos.x, pos.y, shell, pos)
        shell:ClearAllPoints()
        shell:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, sx, sy)
    end

    return MK({
        key = UNLOCK_KEY, label = "Swing Timer", group = "Resource Bars", order = 508,
        getFrame = function() return S.built and shell or nil end,
        isHidden = function() local cfg = P(); return not (cfg and cfg.enabled) end,
        getSize  = function() return Size(P()) end,
        -- The rows' textured border outside the stack: every row spans the full
        -- width and the outer rows' edges are the stack's, so one row's reach.
        getMatchPad = function() return ns.ERB_EuiBorderPad(P()) end,
        setWidth = function(_, w)
            local cfg = P(); if not cfg then return end
            cfg.width = PP.Snap(math.max(w, 10))
            Rebuild()
        end,
        -- The mover resizes the whole stack; the per-row height is what is stored.
        setHeight = function(_, h)
            local cfg = P(); if not cfg then return end
            local n = ShownCount()
            local sp = cfg.rowSpacing or 0
            cfg.height = PP.Snap(math.max((h - (n - 1) * sp) / n, 4))
            Rebuild()
        end,
        savePos = save, loadPos = load, clearPos = clear, applyPos = apply,
    })
end
