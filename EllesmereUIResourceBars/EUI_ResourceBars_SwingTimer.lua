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
-- (remaining time, slot tag).
--
-- Cost on: PLAYER_SWING re-sets the row's C_DurationUtil duration object and
-- arms the bar timer (SetTimerDuration), so the engine animates the fill with
-- no Lua per frame, the way the QoL swing timer ran. A 20 Hz anim ticker runs
-- only while a swing is in flight and does the two things the engine timer
-- cannot: the remaining-time text (no engine formatter is proven to render the
-- bar's %.1f) and the end edge (idle fill, Hide When Idle). Range and the
-- queued attack are event-driven (PLAYER_SWING_RANGE_UPDATE,
-- ACTIONBAR_UPDATE_STATE). An idle row costs nothing: its timer holds a
-- finished duration, which paints a static state.
--
-- Everything is gated on the swing API and the engine timer it feeds: on retail
-- this file returns right below and nothing below exists. Off by default = no
-- frame children, no events, no ticker.

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
-- (mhR/mhG/... ohR/... rR/...), `show` the per-row toggle key, `melee` the rows
-- a queued on-next-swing attack lands on.
local ROWS = {
    { type = SWING.MainHand, key = "mh", tag = "MH", show = "showMH", melee = true },
    { type = SWING.OffHand,  key = "oh", tag = "OH", show = "showOH", melee = true },
    { type = SWING.Ranged,   key = "r",  tag = "R",  show = "showR" },
}

-- On-next-swing attacks per class (base spell IDs; ranks resolve to the same
-- name): Warrior Heroic Strike / Cleave, Druid Maul. While one is queued the
-- melee rows take the queue colour and carry the spell name, so the swing that
-- will consume it is visible. Names resolve once per session and only for a
-- class that has one: ACTIONBAR_UPDATE_STATE storms in combat and is
-- registered only while there are names to compare (the paint is a name
-- compare that touches the rows only on a change).
local QUEUE_SPELLS = {
    WARRIOR = { 78, 845 },
    DRUID   = { 6807 },
}

-- Shell + ticker host at FILE SCOPE (attribution rule, see _erbEventFrame in the
-- main file): the OnEvent and OnLoop work bills ResourceBars. Children stay lazy.
local shell = CreateFrame("Frame", "ERB_SwingTimerFrame", UIParent)
shell:Hide()
local tickFrame = CreateFrame("Frame")

-- built, rows[i] (row frames in ROWS order), byType[swingType] = row, shown (row
-- count on screen), live (rows mid-swing), rangeOn[swingType] = bool, sample
-- (unlock mode preview on), moHooked, unlockHooked, lastH (frame height last laid
-- out), queueNames (resolved on-next-swing spell names), queued (name painted,
-- false = none)
local S = { rows = {}, byType = {}, shown = 0, live = 0, rangeOn = {}, queueNames = {}, queued = false }

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
-- restricted answer is treated as "no information" (no swing, no row, no
-- range verdict). Never infer an interval from restricted data.
local function Plain(v)
    return not (issecretvalue and issecretvalue(v))
end

-- Blizzard's CanSwing: Main Hand always applies; Off Hand / Ranged only while
-- UnitAttackSpeed reports a positive speed for the slot.
local function CanSwing(swingType)
    if swingType == SWING.MainHand then return true end
    local _, oh, ranged = UnitAttackSpeed("player")
    if swingType == SWING.OffHand then return Plain(oh) and type(oh) == "number" and oh > 0 end
    if swingType == SWING.Ranged then return Plain(ranged) and type(ranged) == "number" and ranged > 0 end
    return false
end

-- A row is shown while its slot can swing and its toggle is on.
local function RowWanted(def, cfg)
    return CanSwing(def.type) and (not cfg or cfg[def.show] ~= false)
end

-- Rows the frame would show right now (from the live rows once built, from the
-- weapon slots before). Feeds the unlock mover's size before the first build.
local function ShownCount()
    if S.built then return math.max(S.shown, 1) end
    local cfg = P()
    local n = 0
    for i = 1, #ROWS do if RowWanted(ROWS[i], cfg) then n = n + 1 end end
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
    time:SetText("0.0")
    row._time = time

    row._outOfRange = false
    return row
end

-- Out-of-range look: Blizzard dims the whole row to 0.4 and paints the text
-- red. Unlock mode suppresses the dimming without touching the state.
local function ApplyRangeLook(row, cfg)
    cfg = cfg or P()
    local oor = row._outOfRange and not S.sample
    local alpha = oor and ((cfg and cfg.outOfRangeAlpha) or 0.4) or 1
    row._bg:SetAlpha(alpha)
    row._border:SetAlpha(alpha)
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

-- Idle render: empty (background) by default, full of the fill colour with
-- idleShowFill. Time reads 0.0 like Blizzard's bar. This is also the disarm:
-- the bar timer is re-armed on a finished duration, whose terminal state is
-- static (RemainingTime paints empty, ElapsedTime full: the GCD bar's idle
-- recipe), so the engine has nothing left to animate. The SetValue keeps the
-- value channel coherent with what is drawn.
local function IdleRow(row, cfg)
    if row._live then
        row._live = nil
        S.live = S.live - 1
    end
    row._end = nil
    local full = cfg and cfg.idleShowFill == true
    local obj = row._durObj
    obj:SetTimeFromStart(GetTime() - 1, 1)
    row._bar:SetTimerDuration(obj, IMMEDIATE, full and DIR.ElapsedTime or DIR.RemainingTime)
    row._bar:SetValue(full and 1 or 0)
    row._time:SetText("0.0")
end

-- The fill is the engine's: the row's duration object takes this swing and the
-- bar timer animates it every frame with no Lua, draining (Deplete Fill) or
-- filling exactly as the direction says. The end time stays in Lua only for
-- the ticker's end edge; the duration object is never read.
local function StartRow(row, dur, cfg)
    if type(dur) ~= "number" or dur ~= dur or dur <= 0 or dur == math.huge then return end
    local now = GetTime()
    row._end = now + dur
    row._dur = dur
    if not row._live then
        row._live = true
        S.live = S.live + 1
    end
    local obj = row._durObj
    obj:SetTimeFromStart(now, dur)
    row._bar:SetTimerDuration(obj, IMMEDIATE, cfg.depleteFill and DIR.RemainingTime or DIR.ElapsedTime)
    row._time:SetFormattedText("%.1f", dur)
    ns.STTick.Start()
    if cfg.hideWhenIdle and S.live == 1 and ns.ST_UpdateVisibility then ns.ST_UpdateVisibility() end
end

-- 20 Hz while any row is live, for what the engine timer cannot do: the
-- remaining-time text and the end edge (idle render, Hide When Idle). No
-- SetValue here, the fill is the engine's. Self-stops on the last row going
-- idle.
ns.STTick = EllesmereUI.Tick.NewAnimTicker(tickFrame, function()
    local cfg = P()
    if not (cfg and cfg.enabled and S.built) then return false end
    local now = GetTime()
    local any = false
    for i = 1, #S.rows do
        local row = S.rows[i]
        if row._live then
            local rem = row._end - now
            if rem <= 0 then
                IdleRow(row, cfg)
            else
                if cfg.showTime ~= false then row._time:SetFormattedText("%.1f", rem) end
                any = true
            end
        end
    end
    if not any and cfg.hideWhenIdle and ns.ST_UpdateVisibility then ns.ST_UpdateVisibility() end
    return any
end, 0.05)

-------------------------------------------------------------------------------
--  Layout + look
-------------------------------------------------------------------------------

-- Fill colour: the row's own (or class) colour, or the queue colour on a melee
-- row while an on-next-swing attack is queued.
local function ApplyRowFill(row, cfg)
    local fillTex = row._bar:GetStatusBarTexture()
    local queued = S.queued and row._def.melee
    local fR, fG, fB, fA
    if queued then
        fR, fG, fB, fA = cfg.queueR or 1, cfg.queueG or 0.70, cfg.queueB or 0.20, cfg.queueA or 1
    else
        fR, fG, fB, fA = RowColor(cfg, row._def)
    end
    if cfg.gradientEnabled and not queued then
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
        row._tag:SetText(def.tag .. " - " .. S.queued)
    else
        row._tag:SetText(def.tag)
    end
end

-- Which on-next-swing attack is queued right now, or false. Reads only the
-- names resolved at build; a restricted answer counts as not queued.
local function QueuedName()
    local names = S.queueNames
    if #names == 0 or not (C_Spell and C_Spell.IsCurrentSpell) then return false end
    for i = 1, #names do
        local cur = C_Spell.IsCurrentSpell(names[i])
        if Plain(cur) and cur then return names[i] end
    end
    return false
end

-- Delta paint: touches the melee rows only when the queued name changed.
local function PaintQueue(cfg)
    cfg = cfg or P()
    if not (cfg and S.built) then return end
    local queued = cfg.queueHighlight ~= false and QueuedName() or false
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

-- Stack the applicable rows and size the frame to them. Returns true when the
-- frame height changed (anchored neighbours need a nudge).
local function Layout(cfg)
    local h = cfg.height or 12
    local sp = cfg.rowSpacing or 0
    local w = cfg.width or 220
    local idx = 0
    for i = 1, #S.rows do
        local row = S.rows[i]
        if row:IsShown() then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", shell, "TOPLEFT", 0, -idx * (h + sp))
            row:SetSize(w, h)
            idx = idx + 1
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

    ApplyRowFill(row, cfg)

    -- Leading-edge spark: anchored to the fill texture's moving edge so it
    -- tracks the fill (the GCD bar's horizontal case).
    local spark = row._spark
    if cfg.showSpark then
        local fillTex = bar:GetStatusBarTexture()
        spark:ClearAllPoints()
        spark:SetSize(8, h)
        spark:SetPoint("CENTER", fillTex, "RIGHT", 0, 0)
        spark:Show()
    else
        spark:Hide()
    end

    local size = cfg.textSize or 11
    ns.SetRBFont(row._tag, ns.GetRBFont(), size)
    ns.SetRBFont(row._time, ns.GetRBFont(), size)
    ApplyRowTag(row, cfg)
    if cfg.showLabel ~= false then row._tag:Show() else row._tag:Hide() end
    if cfg.showTime ~= false then row._time:Show() else row._time:Hide() end
    ApplyRangeLook(row, cfg)
end

local function ApplyLook(cfg)
    local w, h = cfg.width or 220, cfg.height or 12
    for i = 1, #S.rows do ApplyRowLook(S.rows[i], cfg, w, h) end
end

-- Show/hide rows to the weapon slots, then re-stack. Also the range-check
-- registration: on for every shown row while the option is on, off otherwise.
local function RefreshRows(cfg)
    cfg = cfg or P()
    if not (cfg and S.built) then return end
    local wantRange = cfg.enabled and cfg.rangeCheck ~= false
    for i = 1, #S.rows do
        local row = S.rows[i]
        local can = RowWanted(row._def, cfg)
        if can then
            row:Show()
        else
            row:Hide()
            if row._live then IdleRow(row, cfg) end
        end
        SetRangeCheck(row._def.type, wantRange and can)
    end
    if Layout(cfg) and EllesmereUI.NotifyElementResized then
        EllesmereUI.NotifyElementResized(UNLOCK_KEY)
    end
    UpdateRangeAll()
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

shell:SetScript("OnEvent", function(self, event, a1, a2, a3)
    local cfg = P()
    if not (cfg and cfg.enabled and S.built) then return end
    if event == "PLAYER_SWING" then
        -- a1 = swingDuration, a2 = swingType
        if not (Plain(a1) and Plain(a2)) then return end
        local row = S.byType[a2]
        if row and row:IsShown() then StartRow(row, a1, cfg) end
        PaintQueue(cfg)
    elseif event == "ACTIONBAR_UPDATE_STATE" then
        PaintQueue(cfg)
    elseif event == "PLAYER_DEAD" then
        for i = 1, #S.rows do
            if S.rows[i]._live then IdleRow(S.rows[i], cfg) end
        end
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
        RefreshRows(cfg)
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
    if cfg.queueHighlight ~= false and #S.queueNames > 0 then
        shell:RegisterEvent("ACTIONBAR_UPDATE_STATE")
    else
        shell:UnregisterEvent("ACTIONBAR_UPDATE_STATE")
    end
end

local function UnregisterEvents()
    if not S.events then return end
    S.events = nil
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
    -- On-next-swing spell names, once per session, for a class that has one.
    local _, classFile = UnitClass("player")
    local queueList = QUEUE_SPELLS[classFile]
    if queueList and C_Spell and C_Spell.GetSpellName then
        for i = 1, #queueList do
            local name = C_Spell.GetSpellName(queueList[i])
            if Plain(name) and name then
                S.queueNames[#S.queueNames + 1] = name
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

-- Off: drop events, range checks and the ticker, and idle every live row (its
-- bar timer is parked on a finished duration); the frame stays shown at alpha 0
-- so anchored neighbours keep a valid rect (SetElementVisibility rule).
local function Teardown()
    if not S.built then return end
    UnregisterEvents()
    local cfg = P()
    for i = 1, #S.rows do
        local row = S.rows[i]
        if row._live then IdleRow(row, cfg) end
        SetRangeCheck(row._def.type, false)
    end
    ns.STTick.Stop()
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
    -- Highlight turned off with an attack queued: the paint below must clear it.
    if cfg.queueHighlight == false then S.queued = false end
    -- Size and stack the rows BEFORE styling them: the textured border is a
    -- BackdropTemplate nine-slice keyed on first setup, and set up on a 0x0
    -- row it never paints (cast/GCD bars size first for the same reason).
    RefreshRows(cfg)
    ApplyPosition(cfg)
    ApplyLook(cfg)
    PaintQueue(cfg)
    -- Every row takes its paint here on every apply, always by re-arming the
    -- bar timer, never by a plain SetValue: a parked timer keeps painting its
    -- terminal state and SetValue does not repaint it (the GCD bar's idle
    -- recipe). Unlock movers up: a full bar with a sample time. A row
    -- mid-swing: its running swing again, in the direction now configured
    -- (unlock exit, a Deplete Fill change). Otherwise the idle render, so a
    -- Show Fill Color When Idle change shows at once, not at the next swing's end.
    for i = 1, #S.rows do
        local row = S.rows[i]
        local obj = row._durObj
        if S.sample then
            obj:SetTimeFromStart(GetTime() - 1, 1)
            row._bar:SetTimerDuration(obj, IMMEDIATE, DIR.ElapsedTime)
            row._bar:SetValue(1)
            row._time:SetText("1.2")
        elseif row._live and row._dur then
            obj:SetTimeFromStart(row._end - row._dur, row._dur)
            row._bar:SetTimerDuration(obj, IMMEDIATE, cfg.depleteFill and DIR.RemainingTime or DIR.ElapsedTime)
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
