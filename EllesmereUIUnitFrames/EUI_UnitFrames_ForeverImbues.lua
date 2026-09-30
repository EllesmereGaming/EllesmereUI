if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_UnitFrames_ForeverImbues.lua  (WoW Forever only)
--
--  Weapon imbues (Rockbiter, Flametongue, Windfury...) on the Player Aura
--  Bars Buffs bar. On WoW Forever an imbue is its own weapon enchant type
--  (Enum.ItemEnchantType.Imbue) beside the temporary one (oils, stones), and
--  C_PaperDollInfo.GetTemporaryEnchantmentInfo -- the one source the aura
--  container's weapon-enchant cells read -- reports only the temporary one.
--  C_Item.GetWeaponEnchantInfo lists every enchant per weapon, so the imbues
--  are drawn here as cells of the bar's own style (AK.CreateStyledCell),
--  leading the bar where the engine's weapon-enchant cells lead it: the
--  container moves along its growth by the cells shown and its line
--  shortens by as much, so the bar keeps its box. Centered growth has no
--  fixed leading corner: there the cells sit as a line of their own just
--  before the bar (above it, or left of it for vertical growth).
--
--  The Player Aura Bars file calls ns.PAB_FvImbueLayout (ApplyEnchants),
--  ns.PAB_FvImbueSync (SyncEnchantEvents) and ns.PAB_FvImbueCount
--  (BuffAuraMax); all three stay nil on every other client, where this file
--  returns at once.
--
--  Cost: nothing while the Buffs bar's weapon-enchant row is off. On: the
--  weapon events; the bar re-lays only when the number of imbues changes,
--  and the countdown text runs on the engine's duration binding.
-------------------------------------------------------------------------------
local _, ns = ...
local EllesmereUI = _G.EllesmereUI
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
local ET, WS = Enum.ItemEnchantType, Enum.WeaponSlot
if not (ET and ET.Imbue and WS and C_Item and C_Item.GetWeaponEnchantInfo) then return end

local IMBUE = ET.Imbue
local STYLE = "playerAuraBars_buffs" -- the default Buffs bar's style key
-- Weapons in cell order from the bar's corner: the engine's weapon-enchant
-- cells run in reverse slot order, so main hand sits next to the rest.
local WEAPONS = { WS.Ranged, WS.OffHand, WS.MainHand }
local INV = {
    [WS.MainHand] = INVSLOT_MAINHAND or 16,
    [WS.OffHand] = INVSLOT_OFFHAND or 17,
    [WS.Ranged] = INVSLOT_RANGED or 18,
}

local on = false
local shown = {}       -- imbues in cell order: { inv, icon, charges, endTime, total }
local numShown = 0     -- imbues the last scan found
local numLaidFrom = 0  -- numShown the last layout was built from
local numLaid = 0      -- cells the last layout placed (they come off the aura budget)
local track = {}       -- weapon slot -> { id, endTime, total }
local cells = {}       -- cell index -> { f, d, dur, binding, inv }
local events

local function Readable(v)
    return v ~= nil and not issecretvalue(v)
end

-- Fills `shown` from the weapons; returns the count. Equipment data, read on
-- the weapon events and at each layout only.
local function Scan()
    local n, now = 0, GetTime()
    for _, ws in ipairs(WEAPONS) do
        local list = C_Item.GetWeaponEnchantInfo(ws)
        local found
        if type(list) == "table" then
            for _, e in ipairs(list) do
                if Readable(e.hasEnchant) and e.hasEnchant and Readable(e.enchantType)
                    and e.enchantType == IMBUE and Readable(e.timeLeft) and e.timeLeft > 0 then
                    found = e
                    break
                end
            end
        end
        if found then
            local left = found.timeLeft / 1000
            local endTime = now + left
            local t = track[ws]
            if not t then t = {}; track[ws] = t end
            -- A new imbue, or the same one cast again (its end moved out): the
            -- swipe restarts from what is left now.
            if t.id ~= found.enchantID or endTime > (t.endTime or 0) + 1 then
                t.total = left
            end
            t.id, t.endTime = found.enchantID, endTime
            n = n + 1
            local s = shown[n]
            if not s then s = {}; shown[n] = s end
            s.inv = INV[ws]
            local icon = found.enchantIconID
            if not (Readable(icon) and icon ~= 0) then
                icon = GetInventoryItemTexture("player", s.inv) or 134400
            end
            s.icon = icon
            s.charges = Readable(found.charges) and found.charges or 0
            s.endTime, s.total = endTime, t.total
        else
            track[ws] = nil
        end
    end
    numShown = n
    return n
end

local function CellEnter(self)
    local c = self.fvImbue
    local style = EllesmereUI.AuraKit.styles[STYLE]
    if not (c and c.inv) or (style and style.noTooltips) then return end
    if style and style.tooltipCombatHide and InCombatLockdown() then return end
    GameTooltip:SetOwner(self, (style and style.tooltipAnchor == "cursor") and "ANCHOR_CURSOR" or "ANCHOR_BOTTOMLEFT")
    GameTooltip:SetInventoryItem("player", c.inv)
    GameTooltip:Show()
end

local function CellLeave()
    GameTooltip:Hide()
end

local function Cell(i, parent)
    local c = cells[i]
    if c then
        if c.f:GetParent() ~= parent then c.f:SetParent(parent) end
        return c
    end
    local AK = EllesmereUI.AuraKit
    -- The weapon-enchant init: Blizzard Style rings these cells like the
    -- engine's own weapon-enchant cells.
    local f, d = AK.CreateStyledCell(parent, STYLE, AK.EnchantCellInit)
    -- Hover shows the weapon's tooltip; clicks pass through (removing an
    -- imbue is a protected call).
    f:EnableMouse(true)
    f:SetMouseClickEnabled(false)
    f:SetScript("OnEnter", CellEnter)
    f:SetScript("OnLeave", CellLeave)
    c = { f = f, d = d }
    if C_DurationUtil and C_DurationUtil.CreateDurationTextBinding then
        c.dur = C_DurationUtil.CreateDuration()
        c.binding = C_DurationUtil.CreateDurationTextBinding()
        c.binding:SetFontString(d.duration)
        c.binding:SetDuration(c.dur)
    end
    f.fvImbue = c
    cells[i] = c
    return c
end

-- Content only (the style pass owns size, border, fonts and anchors).
local function Paint(c, s)
    local AK = EllesmereUI.AuraKit
    local style = AK.styles[STYLE] or {}
    local d = c.d
    c.inv = s.inv
    d.icon:SetTexture(s.icon)
    d.stack:SetText(s.charges > 0 and tostring(s.charges) or "")
    d.cooldown:SetCooldown(s.endTime - s.total, s.total)
    local b = c.binding
    if b then
        c.dur:SetTimeFromEnd(s.endTime, s.total)
        local fmt = AK.GetDurationFormatter(style.durationShowSeconds, style.durationPrecisionThreshold)
        if fmt then b:SetFormatter(fmt) end
        if style.durationUpdateInterval then b:SetUpdateInterval(style.durationUpdateInterval) end
        local tc = style.durationColorCurve and AK.DurationTextColor(style.durationColorCurve)
        if tc then b:SetTextColorCurve(tc.curve, tc.property) else b:ClearTextColorCurve() end
        b:SetEnabled(true)
    end
end

local function HideFrom(first)
    for i = first, #cells do
        local c = cells[i]
        c.f:Hide()
        if c.binding then c.binding:SetEnabled(false) end
    end
end

-- ApplyEnchants, after the container took its normal anchor and line width
-- this pass: places the cells and makes room for them. `layout` is the bar's
-- group layout (element size and spacing), `anchor` the container's point.
function ns.PAB_FvImbueLayout(container, parent, cfg, grid, layout, anchor)
    if not (on and container and parent and cfg and grid and layout and anchor) then return end
    Scan()
    numLaidFrom = numShown
    local n = math.min(numShown, grid.enchSlots or 0)
    local dir = cfg.growDirection or "LEFT"
    local step = layout.elementWidth + layout.elementSpacing
    local lineGap = layout.lineSpacing or layout.elementSpacing
    local dx, dy = 0, 0
    if dir == "LEFT" then dx = -step
    elseif dir == "RIGHT" then dx = step
    elseif dir == "DOWN" then dy = -step
    elseif dir == "UP" then dy = step
    end
    local centered = dx == 0 and dy == 0
    for i = 1, n do
        local c = Cell(i, parent)
        local f = c.f
        f:ClearAllPoints()
        if not centered then
            f:SetPoint(anchor, parent, anchor, (i - 1) * dx, (i - 1) * dy)
        elseif dir == "CENTER_VERTICAL" then
            f:SetPoint("RIGHT", parent, "LEFT", -lineGap, ((n + 1) / 2 - i) * step)
        else
            f:SetPoint("BOTTOM", parent, "TOP", (i - (n + 1) / 2) * step, lineGap)
        end
        Paint(c, shown[i])
        f:Show()
    end
    HideFrom(n + 1)
    numLaid = n
    if n > 0 and not centered then
        container:ClearAllPoints()
        container:SetPoint(anchor, parent, anchor, n * dx, n * dy)
        EllesmereUI.AuraKit.SetContainerRowWidth(container, math.max(step, grid.rowWidth - n * step))
    end
end

-- Cells showing, for the bar's aura budget (BuffAuraMax).
function ns.PAB_FvImbueCount()
    return on and numLaid or 0
end

local function OnEvent()
    if not on then return end
    Scan()
    if numShown ~= numLaidFrom then
        -- A cell came or went: the bar re-lays (and this file with it).
        if ns.PAB_ApplyLiveConfig then ns.PAB_ApplyLiveConfig(true) end
        return
    end
    -- Same cells, new content (a re-cast, a weapon swap between imbued
    -- weapons, charges): repaint in place.
    for i = 1, numLaid do Paint(cells[i], shown[i]) end
end

-- SyncEnchantEvents: the Buffs bar's weapon-enchant row on or off.
function ns.PAB_FvImbueSync(want)
    want = want and true or false
    if want == on then return end
    on = want
    if on then
        if not events then
            events = CreateFrame("Frame")
            events:SetScript("OnEvent", OnEvent)
        end
        events:RegisterEvent("WEAPON_ENCHANT_CHANGED")
        events:RegisterEvent("WEAPON_SLOT_CHANGED")
        events:RegisterEvent("PLAYER_ENTERING_WORLD")
    else
        if events then events:UnregisterAllEvents() end
        HideFrom(1)
        numLaid, numLaidFrom = 0, 0
    end
end
