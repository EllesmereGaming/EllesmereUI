if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- Blocks\Shared.lua
-- Shared scaffolding for the DataBars block factories. Loads before every other
-- Blocks\*.lua file; each block file lives in its own file and imports helpers
-- from ns.BlockKit.
--
-- Contract (engine calls, see EllesmereUIDataBars.lua):
--   ns.BlockFactories[typeKey] = function(blockCfg, slot, content, barCtx) -> inst
--   inst:Refresh()        re-read settings+state, repaint, re-measure; re-layouts
--                         when the measured auto extent changed
--   inst:Enable()/Disable()  register/unregister events+heartbeat (idempotent)
--   inst:GetAutoLength()  content extent along the bar axis (px); 0 = COLLAPSED
--                         (solver drops it: content gaps in auto, share in even mode)
--   inst:Destroy()        full teardown; secure frames park OOC
--
-- All frames in Blocks\ are OURS (CreateFrame by these files), so SetScript and custom fields
-- are allowed. Only Blizzard frames touched: micro menu containers (via a
-- SecureHandlerStateTemplate hider) and the MicroButtons/ProfessionMicroButton/QuestLogMicroButton (via secure attributes).

local ADDON_NAME, ns = ...

-- Helpers shared by every block file.
local K = {}
ns.BlockKit = K

-- One knob: icon -> content spacing for every icon-bearing block.
local ICON_GAP = 8

-- Bar fill textures for block statusbars (XP/Rep, professions): mirrors the
-- Unit Frames Bar Texture set; SharedMedia appended below + at dropdown build.
-- "none" = flat fill.
local barTextures, barTextureNames, barTextureOrder =
    EllesmereUI.BuildBarTextureTables(true)
ns.barTextures = barTextures
ns.barTextureOrder = barTextureOrder
ns.barTextureNames = barTextureNames

-- Seed SharedMedia statusbar textures once at load so a saved LSM key resolves at login; the parent helper also registers for late LSM packs.
EllesmereUI.AppendSharedMediaTextures(barTextureNames, barTextureOrder, nil, barTextures)


-- Upvalues
local CreateFrame       = CreateFrame
local InCombatLockdown  = InCombatLockdown
local type              = type
local pcall             = pcall
local abs               = math.abs

-------------------------------------------------------------------------------
--  Shared per-instance scaffolding
-------------------------------------------------------------------------------
local function InstKey(barCtx, blockCfg)
    return "EDB" .. barCtx.id .. "_" .. blockCfg.id
end

local function MakeEventFrame(inst, handler)
    local f = CreateFrame("Frame")
    f:SetScript("OnEvent", function(_, event, ...) handler(inst, event, ...) end)
    return f
end

local function RegisterInstEvents(inst)
    if not (inst.eventFrame and inst.events) then return end
    for i = 1, #inst.events do
        pcall(inst.eventFrame.RegisterEvent, inst.eventFrame, inst.events[i])
    end
end

local function UnregisterInstEvents(inst)
    if inst.eventFrame then inst.eventFrame:UnregisterAllEvents() end
end

-- Content sizing baseline: fonts/icons derive from this CONSTANT, never the
-- live bar thickness (Height resizes the BAR only; size comes from Text
-- Scale / Content Scale / per-block fonts). 30 = the thickness they were tuned at.
local CONTENT_BASE = 30

-- Content scale of a block: content frames are SetScale'd as a group, so fit budgets must convert slot pixels into content space (slot / scale).
local function ContentScaleOf(inst)
    local s = ((inst.cfg and inst.cfg.scale) or 100) / 100
    if s <= 0 then return 1 end
    return s
end

-- Horizontal text budget: every block fits into its solver-assigned slot width (sizing is share-based for auto and fixed blocks alike).
local function HBudget(inst, fallback)
    local w = inst.slot and inst.slot:GetWidth()
    if w and w > 8 then return w / ContentScaleOf(inst) end
    return fallback
end

-- Vertical cross-axis width (bar thickness; falls back before slot layout).
local function VSlotW(inst)
    local w = inst.slot and inst.slot:GetWidth()
    if w and w > 2 then return w / ContentScaleOf(inst) end
    return inst.ctx.GetThickness()
end

-- Re-layout only when the measured auto extent actually changed (breaks the
-- Refresh -> layout -> Refresh loop). Only auto-mode bars size from content --
-- the fill block's px is the remainder, so its content never drives layout.
local function MaybeRelayout(inst)
    local b = inst.cfg
    local barCfg = inst.ctx and inst.ctx.cfg
    if not barCfg then return end
    local w = 0
    if inst.GetAutoLength then w = inst:GetAutoLength() or 0 end
    if ns.BarSizingMode(barCfg) ~= "auto" then
        -- Even mode ignores widths, but flipping to/from collapsed (extent 0)
        -- changes the SHARE COUNT -- re-solve so the freed share redistributes.
        local was = inst._lastAuto
        inst._lastAuto = w
        if was ~= nil and ((was <= 0) ~= (w <= 0)) then
            inst.ctx.RequestLayout()
        end
        return
    end
    if barCfg.fillBlockId == b.id then return end
    if inst._lastAuto == nil or abs(w - inst._lastAuto) > 0.5 then
        inst._lastAuto = w
        inst.ctx.RequestLayout()
    end
end

-- Text-only X/Y offset (b.textXOff/b.textYOff): wraps a PRIMARY text FontString's
-- SetPoint so every anchor carries the live cfg offset. Wrap ONLY texts anchored to
-- non-text targets -- chained texts (bagText->goldText, eventText->clockText,
-- infoText->specText) inherit the shift and would double-shift. Safe to shadow (our own FontStrings); re-renders via ns.ReflowBlocks.
local function AttachTextOffset(inst, fs)
    if not fs or fs._edbTxo then return end
    fs._edbTxo = true
    local orig = fs.SetPoint
    fs.SetPoint = function(self, point, a2, a3, a4, a5)
        local c = inst.cfg
        local dx = (c and c.textXOff) or 0
        local dy = (c and c.textYOff) or 0
        if a2 == nil then
            return orig(self, point, dx, dy)
        end
        if type(a2) == "number" then
            return orig(self, point, a2 + dx, (a3 or 0) + dy)
        end
        return orig(self, point, a2, a3 or point, (a4 or 0) + dx, (a5 or 0) + dy)
    end
end

-- Per-block content color (options Color row: Custom/Class/Accent; default
-- white). Colors TEXT and vertex-tints ICONS, not status-bar fills;
-- state-driven colors (hover accent, travel red) win at their call site.
local function BlockColorOf(b)
    if b.useDynamicColor then
        -- Opt-in state-driven text mode (the Text Color row's 4th swatch).
        return ns.BlockTextDynamic(b.type)
    end
    if b.useClassColor then
        local _, classFile = UnitClass("player")
        local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
        if cc then return cc.r, cc.g, cc.b end
    elseif b.useAccentColor then
        return ns.GetAccent()
    end
    local c = b.color
    if c then return c.r or 1, c.g or 1, c.b or 1 end
    return 1, 1, 1
end

-- Zone coloring by the current PvP ruleset; identical to the minimap module's GetZoneReactionColor so bar location text and minimap zone text agree.
local function ZoneReactionColor()
    local pvpType = C_PvP and C_PvP.GetZonePVPInfo and C_PvP.GetZonePVPInfo()
    if pvpType == "friendly" then
        return 0.05, 0.85, 0.03
    elseif pvpType == "sanctuary" then
        return 0.035, 0.58, 0.84
    elseif pvpType == "arena" or pvpType == "hostile" or pvpType == "combat" then
        return 0.84, 0.03, 0.03
    end
    return 0.9, 0.85, 0.05
end

-- SEASON UPDATE: replace the ids when the crest set rotates; the tints are the
-- item-quality colors the crest art itself uses and only move if Blizzard
-- restyles them. Keep in sync with EllesmereUIQoL/EUI_UpgradeCalc.lua's
-- Data.tracks, which tracks the same currencies for the upgrade planner (that
-- addon can be disabled, so DataBars carries its own copy rather than reaching
-- across for it). Names and icons come live from C_CurrencyInfo, so only the
-- ids and tints are hardcoded. The keys are TIER slots, not ids: a season swap
-- edits the ids here and every player's crest checklist still applies.
local CRESTS = {
    { key = "t1", id = 3442, hex = "1EFF00", r = 0.118, g = 1,     b = 0     },
    { key = "t2", id = 3443, hex = "0070DD", r = 0,     g = 0.439, b = 0.867 },
    { key = "t3", id = 3444, hex = "A335EE", r = 0.639, g = 0.208, b = 0.933 },
    { key = "t4", id = 3445, hex = "FF8000", r = 1,     g = 0.502, b = 0     },
    { key = "t5", id = 3446, hex = "FFD100", r = 1,     g = 0.820, b = 0     },
}
ns.CRESTS = CRESTS
-- Currency id set: the crest block's CURRENCY_DISPLAY_UPDATE handler drops
-- events that name some other currency (payload currencyType; nil = bulk).
do
    local ids = {}
    for i = 1, #CRESTS do ids[CRESTS[i].id] = true end
    ns.CREST_IDS = ids
end

-- SEASON UPDATE: rank-1 item level of each upgrade track, highest first;
-- mirrors Data.tracks[*].ranks[1] in EllesmereUIQoL/EUI_UpgradeCalc.lua. Feeds
-- the item level block's "Band" text swatch, which tints the number with the
-- crest color of the track its gear sits in.
local ILVL_BANDS = {
    { 272, 5 }, { 259, 4 }, { 246, 3 }, { 233, 2 }, { 220, 1 },
}
-- Equipped item level, written by the ilvl block's Refresh; read by the band
-- tint below (and its swatch preview) exactly like K.lastDurabilityPct.
K.lastAvgIlvl = nil

-- Themed per-block icon defaults (Icon Color row's "Default" swatch): spec ->
-- live class color; professions -> live accent (matches their skill-bar fill,
-- so no separate Default swatch there); durability -> DYNAMIC red->green tint
-- from its sampler (swatch "Dynamic").
local ICON_DEFAULTS = {
    gold        = { 0.886, 0.675, 0.478 },  -- E2AC7A
    bags        = { 0.886, 0.675, 0.478 },  -- E2AC7A, same bag art as gold
    travel      = { 0.596, 0.804, 0.961 },  -- 98CDF5
    currency    = { 0.886, 0.675, 0.478 },  -- E2AC7A
    greatvault  = { 0.569, 0.502, 1 },  -- 9180FF
    audio       = { 1, 1, 1 },
    -- Map-marker red, not the soft module red (salmon at 65% sat; blooms as pure FF0000 at icon size).
    -- Plain stored default: unlike the text beside it, the pin never follows the zone.
    location    = { 0.918, 0.263, 0.208 },  -- EA4335
    -- Map-marker yellow, distinct from gold's peachy E2AC7A at a glance.
    coords      = { 0.961, 0.784, 0.259 },  -- F5C842
    ilvl        = { 1, 1, 1 },
}
-- NOTE: no `crests` entry, and the block is deliberately absent from the
-- options page's ICON_COLOR_BLOCKS. Its icons are inline |T|t escapes inside
-- one FontString (variable segment count, per-crest tinting), and inline
-- textures cannot be vertex-tinted -- the crest art is meant to read by its own
-- tier color anyway.

-- Lowest equipped-durability percent, written by the durability block's sampler; read by the dynamic tint below (and its swatch preview).
K.lastDurabilityPct = nil
function ns.BlockIconDefault(bType)
    if bType == "spec" then
        local _, classFile = UnitClass("player")
        local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
        if cc then return cc.r, cc.g, cc.b end
        return 1, 1, 1
    end
    if bType == "profession" or bType == "profession2" then
        return ns.GetAccent()
    end
    if bType == "durability" then
        -- White(100%) fades to soft red(1,.35,.35) over 20..100; <=20% is fully red.
        local pct = K.lastDurabilityPct or 100
        local t = (pct - 20) * (100 / 80)
        if t < 0 then t = 0 elseif t > 100 then t = 100 end
        local gb = 0.35 + 0.65 * (t / 100)
        return 1, gb, gb
    end
    local d = ICON_DEFAULTS[bType]
    if d then return d[1], d[2], d[3] end
    return 1, 1, 1
end

-- Per-block STATE-DRIVEN TEXT color (Text Color row's 4th swatch). Fallback is
-- BlockIconDefault (same source as the icon; durability tints both from its
-- red->green gradient). Override: location's zone name follows the PvP
-- ruleset, its map pin stays user-owned.
local TEXT_DYNAMIC = {
    location = ZoneReactionColor,
    coords   = ZoneReactionColor,
    -- Item level "Band": the crest color of the upgrade track the equipped
    -- gear sits in. Below the lowest track it stays white.
    ilvl     = function()
        local lvl = K.lastAvgIlvl
        if not lvl then return 1, 1, 1 end
        for i = 1, #ILVL_BANDS do
            local band = ILVL_BANDS[i]
            if lvl >= band[1] then
                local c = CRESTS[band[2]]
                return c.r, c.g, c.b
            end
        end
        return 1, 1, 1
    end,
}
function ns.BlockTextDynamic(bType)
    local fn = TEXT_DYNAMIC[bType]
    if fn then return fn() end
    return ns.BlockIconDefault(bType)
end

-- Per-block ICON color (Icon Color row: Custom/Class/Accent/Default). Nothing stored = the themed default above; state-driven colors win at their sites.
local function IconColorOf(b)
    if b.useIconDefaultColor then
        -- Explicit Default mode: the stored custom color stays stashed.
        return ns.BlockIconDefault(b.type)
    end
    if b.useIconClassColor then
        local _, classFile = UnitClass("player")
        local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
        if cc then return cc.r, cc.g, cc.b end
    elseif b.useIconAccentColor then
        return ns.GetAccent()
    end
    local c = b.iconColor
    if c then return c.r or 1, c.g or 1, c.b or 1 end
    return ns.BlockIconDefault(b.type)
end

-- Retire a secure frame: hide + reparent to the engine park frame, deferred to OOC when needed (alpha-hidden immediately in combat).
local function ParkSecureFrame(f, key)
    if not f then return end
    if InCombatLockdown() then
        f:SetAlpha(0)
        ns.DeferUntilOOC("edbkill:" .. key, function()
            f:Hide()
            f:SetParent(ns._park)
        end)
    else
        f:Hide()
        f:SetParent(ns._park)
    end
end

K.ICON_GAP             = ICON_GAP
K.CONTENT_BASE         = CONTENT_BASE
K.CRESTS               = CRESTS
K.InstKey              = InstKey
K.MakeEventFrame       = MakeEventFrame
K.RegisterInstEvents   = RegisterInstEvents
K.UnregisterInstEvents = UnregisterInstEvents
K.HBudget              = HBudget
K.VSlotW               = VSlotW
K.MaybeRelayout        = MaybeRelayout
K.AttachTextOffset     = AttachTextOffset
K.BlockColorOf         = BlockColorOf
K.ZoneReactionColor    = ZoneReactionColor
K.IconColorOf          = IconColorOf
K.ParkSecureFrame      = ParkSecureFrame
