if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUICooldownManager.lua
--  CDM Look Customization and Cooldown Display
--  Mirrors Blizzard CDM bars with custom styling, cooldown swipes,
--  desaturation, active state animations, and per-spec profiles.
--  Does NOT parse secret values works around restricted APIs.
-------------------------------------------------------------------------------
local _, ns = ...
if not (EllesmereUI and EllesmereUI._ModuleNS and EllesmereUI.NewCombatQueue) then EUI_CLIENT_BLOCKED = true; return end -- stale-parent guard: a partially updated install (old parent, new child) goes dormant via the line-1 failsafe instead of erroring
EllesmereUI._ModuleNS["EllesmereUICooldownManager"] = ns  -- LOD options files read this module ns via the registry

-- ns[field] = t, the table a chain of split files re-imports main-chunk locals
-- from. broken: true while a part file loads; a file that fails leaves it set
-- and the files behind it return at their first lines. Reading a name the
-- table lacks fails where the part file loads, not later as a nil upvalue.
function ns._NewInternals(field, t)
    t.broken = false
    ns[field] = setmetatable(t, { __index = function(_, k)
        error("ns." .. field .. " has no entry " .. tostring(k), 2)
    end })
end

-- CPU-attribution shell pool: the engine bills a handler's call tree to the addon
-- whose context created the frame, so frames built later under the parent's dispatch
-- would bill the parent forever (see EllesmereUI_Ticker.lua). Pre-created here so they
-- stamp to CooldownManager; use ns.TakeShell() (not CreateFrame) for any frame with
-- events/scripts. No release -- throwaways use CreateFrame directly.
do
    local pool = {}
    local n = 36
    for i = 1, n do pool[i] = CreateFrame("Frame") end
    ns.TakeShell = function()
        if n > 0 then
            local f = pool[n]
            pool[n] = nil
            n = n - 1
            return f
        end
        -- Pool exhausted (not expected): falls back to CreateFrame (bills the parent). Bump n above if this ever happens.
        return CreateFrame("Frame")
    end
end

-- Run-once-after-combat queue (EllesmereUI_Ticker.lua). Frame taken in the main
-- chunk, so drained work bills CooldownManager. Keys are per purpose.
ns.CombatQueue = EllesmereUI.NewCombatQueue(ns.TakeShell())

-- Per-addon border texture defaults (same as Action Bars -- same size system)
EllesmereUI.RegisterBorderDefaults("cdm", EllesmereUI.BORDER_DEFAULTS_BUTTONS)

local ECME = EllesmereUI.Lite.NewAddon("EllesmereUICooldownManager")
ns.ECME = ECME

-- Style flags (Global Settings > Style: EllesmereUI, Blizzard or Classic WoW
-- UI). Reload-gated: each is read from the profile ONCE (first call with a
-- profile present) and latched for the session, so a live profile switch can
-- never flip the look under the one-time art setup below; the profile system
-- prompts for a reload when a switched-to profile carries a different flag.
-- Every call site is a build/restyle path, never a per-tick one.
-- The style this module RENDERS on its icons this session: "eui" | "blizzard" | "classic".
function ns.CdmIconStyle()
    local v = ns._cdmIconStyle
    if v == nil then
        local p = ECME.db and ECME.db.profile
        if not p then return "eui" end
        v = (p.useClassicStyle and "classic") or (p.useBlizzardStyle and "blizzard") or "eui"
        ns._cdmIconStyle = v
        -- The WoW Forever variant of Blizzard Style, latched with it.
        ns._cdmFvIcons = v == "blizzard" and EllesmereUI.IS_FOREVER == true
            and p.useForeverStyle == true
    end
    return v
end
-- Stock-art mode: true for both stock styles (the geometry, gating and chrome they share).
function ns.CdmBlizzIcons() return ns.CdmIconStyle() ~= "eui" end
function ns.CdmClassicIcons() return ns.CdmIconStyle() == "classic" end
-- The style the tracked buff bars render this session, latched the same way.
function ns.CdmBarStyle()
    local v = ns._cdmBarStyle
    if v == nil then
        local p = ECME.db and ECME.db.profile
        if not p then return "eui" end
        v = (p.useClassicStyleBars and "classic") or (p.useBlizzardStyleBars and "blizzard") or "eui"
        ns._cdmBarStyle = v
        ns._cdmFvBars = v == "blizzard" and EllesmereUI.IS_FOREVER == true
            and p.useForeverStyleBars == true
    end
    return v
end
function ns.CdmBlizzBars() return ns.CdmBarStyle() ~= "eui" end
function ns.CdmClassicBars() return ns.CdmBarStyle() == "classic" end
-- Blizzard's cooldown viewer art: the rounded icon mask, the bevel ring drawn
-- around every icon, and the rounded swipe file the viewer's Cooldown uses.
ns.CDM_BLIZZ_MASK    = "UI-HUD-CoolDownManager-Mask"
ns.CDM_BLIZZ_OVERLAY = "UI-HUD-CoolDownManager-IconOverlay"
ns.CDM_BLIZZ_SWIPE   = "Interface\\HUD\\UI-HUD-CoolDownManager-Icon-Swipe"
-- WoW Forever variant of Blizzard Style on the icons / the tracked buff bars
-- (latched with the style; false off Forever).
function ns.CdmIconsForever()
    if ns._cdmIconStyle == nil then ns.CdmIconStyle() end
    return ns._cdmFvIcons == true
end
function ns.CdmBarsForever()
    if ns._cdmBarStyle == nil then ns.CdmBarStyle() end
    return ns._cdmFvBars == true
end
-- Blizzard Style ring art: tex:SetAtlas(name) on every client but WoW Forever,
-- which draws a name it swapped for its own art from the retail sheet
-- (EllesmereUI.StockAtlas) unless the WoW Forever look renders (`bars` = the
-- tracked buff bars' row).
function ns.CdmStockAtlas(tex, name, bars)
    local fv
    if bars then fv = ns.CdmBarsForever() else fv = ns.CdmIconsForever() end
    if fv then return tex:SetAtlas(name) end
    return EllesmereUI.StockAtlas(tex, name)
end
-- Ring inset as a fraction of the icon size (the viewer anchors its 50px
-- essential icons at -9/+8, i.e. the ring sits proportionally outside the icon).
ns.CDM_BLIZZ_RING_X  = 0.18
ns.CDM_BLIZZ_RING_Y  = 0.16
-- Classic WoW UI icon art: the vanilla action button ring, a plain 66px
-- texture on a 36px button centred one pixel low, sized by the icon it rings.
-- Classic icons are square: no mask, full art, EUI's own square swipe.
ns.CDM_CLASSIC_RING       = "Interface\\Buttons\\UI-Quickslot2"
ns.CDM_CLASSIC_RING_SCALE = 66 / 36
ns.CDM_CLASSIC_RING_Y     = -1 / 36
-- Places a classic ring texture round a w x h icon region.
function ns.CdmPlaceClassicRing(ov, anchor, w, h)
    ov:ClearAllPoints()
    ov:SetSize(w * ns.CDM_CLASSIC_RING_SCALE, h * ns.CDM_CLASSIC_RING_SCALE)
    ov:SetPoint("CENTER", anchor, "CENTER", 0, h * ns.CDM_CLASSIC_RING_Y)
end
-- The swipe file the latched icon style draws: the viewer's rounded swipe
-- under Blizzard Style, EUI's square swipe otherwise.
function ns.CdmSwipeFile()
    if ns.CdmIconStyle() == "blizzard" then return ns.CDM_BLIZZ_SWIPE end
    return "Interface\\AddOns\\EllesmereUI\\media\\white-square.png"
end
-- Creation-time crop for icons on frames we build ourselves (trinkets,
-- placeholders, custom buffs, item presets): the EUI 8% zoom, or the full art
-- under a stock style (RefreshCDMIconAppearance re-applies the same rule).
function ns.CdmOwnIconCrop(tex)
    if ns.CdmBlizzIcons() then
        tex:SetTexCoord(0, 1, 0, 1)
    else
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end

-- Snap to whole physical pixels at the bar's effective scale (same convert-round-convert approach as the border system).
local function SnapForScale(x, barScale)
    if x == 0 then return 0 end
    local PP = EllesmereUI and EllesmereUI.PP
    if PP then return PP.Scale(x) end
    return math.floor(x + 0.5)
end

local floor = math.floor
local GetTime = GetTime

ns.DEFAULT_MAPPING_NAME = "Buff Name (eg: Divine Purpose)"

-------------------------------------------------------------------------------
--  Shape Constants (shared with action bars)
-------------------------------------------------------------------------------
local CDM_SHAPES = {
    masks = EllesmereUI.SHAPE_MASKS,
    borders = EllesmereUI.SHAPE_BORDERS,
    insets = EllesmereUI.SHAPE_INSETS,
    iconExpand = 7,
    iconExpandOffsets = {
        circle = 2, csquare = 4, diamond = 2, hexagon = 4,
        portrait = 2, shield = 2, square = 4,
    },
    zoomDefaults = {
        none = 0.08, cropped = 0.04, square = 0.06, circle = 0.06, csquare = 0.06,
        diamond = 0.06, hexagon = 0.06, portrait = 0.06, shield = 0.06,
    },
    edgeScales = {
        circle = 0.75, csquare = 0.75, diamond = 0.70,
        hexagon = 0.65, portrait = 0.70, shield = 0.65, square = 0.75,
    },
}
ns.CDM_SHAPES        = CDM_SHAPES
ns.CDM_SHAPE_MASKS   = CDM_SHAPES.masks
ns.CDM_SHAPE_BORDERS = CDM_SHAPES.borders
ns.CDM_SHAPE_ZOOM_DEFAULTS = CDM_SHAPES.zoomDefaults
ns.CDM_SHAPE_EDGE_SCALES = CDM_SHAPES.edgeScales
-- Cropped shape, per-bar Adjust Crop (mirrors Nameplates' ns.GetAuraCrop). iconCropPercent is the
-- per-side trim %, 5-25; unset = 10, which yields exactly the classic fixed crop (height factor
-- 0.80, 0.10 texcoord trim per side), so bars that never touch it are unchanged. Only called from
-- "cropped" branches. do/end + ns functions: no new main-chunk locals.
do
    local CROP_DEFAULT_PCT = 10
    local function CropPercent(bd)
        local pct = tonumber(bd and bd.iconCropPercent) or CROP_DEFAULT_PCT
        if pct < 5 then pct = 5 elseif pct > 25 then pct = 25 end
        return pct
    end
    ns.CdmCropPercent = CropPercent
    -- Icon height as a fraction of width.
    function ns.CdmCropFactor(bd) return 1 - 2 * (CropPercent(bd) / 100) end
    -- Vertical texcoord trim per side, added on top of the bar's zoom.
    function ns.CdmCropTrim(bd) return CropPercent(bd) / 100 end
end

-- Keybind cache: built once out-of-combat, looked up per tick
local _cdmKeybindCache       = {}   -- [spellID] -> formatted key string
local _cdmKeybindRank        = {}   -- [key] -> priority rank of the stored bind (lower wins)
local _bonusScanSeen         = {}   -- [bonus bar offset] -> true once scanned this session

-- Combat state tracked via events (InCombatLockdown() can lag behind PLAYER_REGEN_DISABLED)
local _inCombat = false

-- Shared read for other CDM files (Tracking Bars' "Only In Combat" gate). Buffered,
-- not raw InCombatLockdown(): debounced combat-exit so brief OOC blips don't flash a bar away.
function ns.CDMInCombat() return _inCombat end

-- Resting alpha for a bar's icons: oocFadeAlpha when enabled+OOC, else barOpacity.
-- All alpha restores go through this so the fade survives cd-state/buff re-renders.
local function EffectiveBarAlpha(barData)
    if barData and barData.oocFadeEnabled and not _inCombat then
        return barData.oocFadeAlpha or 0.5
    end
    return (barData and barData.barOpacity) or 1
end
ns.EffectiveBarAlpha = EffectiveBarAlpha

-- Placeholders rendered at alpha 0: "Keep Buffs in Same Place"
-- (hidePlaceholderIcon) and a hosted "Visibility When Missing: Hidden" slot
-- (_missingHidden) both keep the reserved layout slot but paint nothing. Alpha
-- 0 stops the art, NOT hit-testing, so such a frame stays a live mouse target
-- and must be excluded from every mouse pass too: it would answer tooltips for
-- an inactive buff and swallow mouseover from whatever sits under the bar
-- (Blizzard hides its own inactive items instead, so those slots hold no frame
-- at all). Single predicate so the alpha passes and the mouse passes can never
-- disagree. Off-by-default flags first: non-users stop at the first field.
local function IsPlaceholderRenderHidden(icon, barData)
    if not icon then return false end
    return ((barData and barData.hidePlaceholderIcon) or icon._missingHidden)
        and icon._isPlaceholderFrame and true or false
end
ns.IsPlaceholderRenderHidden = IsPlaceholderRenderHidden

-- Multi-charge spell tracking
local _multiChargeSpells = {}
local _maxChargeCount    = {}

local _cdmViewerNames = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffIconCooldownViewer",
    "BuffBarCooldownViewer",
}

-- External cache keyed by Blizzard frame ref (never custom keys on Blizzard frame
-- tables -- taints them). Weak-keyed so entries GC when frames are recycled.
local _ecmeFC = setmetatable({}, { __mode = "k" })
local function FC(f) local c = _ecmeFC[f]; if not c then c = {}; _ecmeFC[f] = c end; return c end

-- Separate weak-keyed table for SetFrameClickThrough mouse state: it recurses into
-- Blizzard pool icons parented to CDM bars, so state must live externally, not on the frames.
local _cdmMouseState = setmetatable({}, { __mode = "k" })

-- Decoration data stored externally by EllesmereUICdmHooks.lua (loads later).
local function _getFD(f) return ns._hookFrameData and ns._hookFrameData[f] end



-- Racial ability data
local RACE_RACIALS = {
    Scourge            = { 7744 },
    Tauren             = { 20549 },
    Orc                = { 20572, 33697, 33702 },
    BloodElf           = { 202719, 50613, 25046, 69179, 80483, 155145, 129597, 232633, 28730 },
    Dwarf              = { 20594 },
    Troll              = { 26297 },
    Draenei            = { 28880, 59543, 59545, 121093, 59544, 370626, 59547, 59548, 59542, 416250 },
    NightElf           = { 58984 },
    Human              = { 59752 },
    DarkIronDwarf      = { 265221 },
    Gnome              = { 20589 },
    HighmountainTauren = { 255654 },  -- Bull Rush
    Worgen             = { 68992 },
    Goblin             = { 69070 },
    Pandaren           = { 107079 },
    MagharOrc          = { 274738 },
    LightforgedDraenei = { 255647 },
    VoidElf            = { 256948 },
    KulTiran           = { 287712 },
    ZandalariTroll     = { 291944 },
    Vulpera            = { 312411 },
    Mechagnome         = { 312924 },
    Nightborne         = { 260364 },
    -- Wing Buffet (357214) is all-Dracthyr but Blizzard's CDM already gives it to Evokers,
    -- so notClass avoids duplicate injection; Tail Swipe (368970) is Evoker-only and
    -- already in CDM, so it's omitted entirely.
    Dracthyr           = { { 357214, notClass = "EVOKER" } },
    EarthenDwarf       = { 436344 },
    Haranir            = { 1237885 },  -- Thorn Bloom
}
ns.RACE_RACIALS = RACE_RACIALS

local ALL_RACIAL_SPELLS = {}
for _, racials in pairs(RACE_RACIALS) do
    for _, entry in ipairs(racials) do
        local sid = type(entry) == "table" and entry[1] or entry
        ALL_RACIAL_SPELLS[sid] = true
    end
end
-- RPT sync must recognize the racial slot for ANY race so a profile shared across
-- different-race characters syncs too (NormalizeRacialAssignments remaps the ID at spec build).
ns.ALL_RACIAL_SPELLS = ALL_RACIAL_SPELLS

local _myRacials = {}
local _myRacialsSet = {}
-- The one racial actually in this character's spellbook. The picker's generic "Racial"
-- entry adds this ID; NormalizeRacialAssignments rewrites any other race's stored racial
-- to it, so a shared profile's racial slot follows each character's race automatically.
local _activeRacialSpellID = nil

-- Resolve the in-spellbook racial (class-variant races like Blood Fury/Arcane Torrent/
-- Gift of the Naaru have only one in-book). Re-run at build time too: the spellbook may be unpopulated during early-login OnEnable.
local function ResolveActiveRacial()
    _activeRacialSpellID = nil
    for _, sid in ipairs(_myRacials) do
        local inBook = C_SpellBook and C_SpellBook.IsSpellInSpellBook
            and C_SpellBook.IsSpellInSpellBook(sid)
        if inBook then _activeRacialSpellID = sid; break end
    end
    if not _activeRacialSpellID then _activeRacialSpellID = _myRacials[1] end
    ns._activeRacialSpellID = _activeRacialSpellID
    return _activeRacialSpellID
end


-- Custom Aura Bar presets (potions with hardcoded durations). Detection: SPELL_UPDATE_COOLDOWN
-- (spell just used) drives a reverse swipe for the duration. Exceptions: Bloodlust/Heroism is
-- debuff-driven (TBB special-case "bloodlust") since the lust buff is cast by others and secret --
-- it starts a 40s bar off the player's Sated/Exhaustion debuff edge. Time Spiral is glow-armed
-- (special-case "timespiral"); warlock pets are excluded (no usable detection).
local BUFF_BAR_PRESETS = {
    {
        -- Horde order; ns.RefreshLustPresetFaction flips it for Alliance below.
        -- BOTH ids are listed so the "already on this bar" tests recognise a lust
        -- icon added by the other faction on a shared profile.
        key      = "bloodlust",
        name     = "Bloodlust",
        icon     = "Interface\\Icons\\spell_nature_bloodlust",
        spellIDs = { 2825, 32182 },
        duration = 40,
        tbbOnly  = true,  -- not a cooldown-usable preset (kept out of the CD/utility picker)
        customAuraToo = true,  -- but allowed on Custom Auras (icon) bars; debuff-driven 40s window
    },
    {
        -- Time Spiral "Free Move" proc: self-timed 10s window armed by a spell-activation
        -- glow on the player's class movement ability, not cooldown-detected (TBB special-case "timespiral").
        key      = "timespiral",
        name     = "Time Spiral",
        icon     = 4622479,
        spellIDs = { 374968 },
        duration = 10,
        tbbOnly  = true,       -- not a cooldown-usable preset (kept out of the CD/utility picker)
        customAuraToo = true,  -- but allowed on Custom Auras (icon) bars; glow-driven 10s window
    },
    {
        key      = "lights_potential",
        name     = "Light's Potential",
        icon     = 7548911,
        spellIDs = { 1236616 },
        duration = 30,
    },
    {
        key      = "potion_recklessness",
        name     = "Potion of Recklessness",
        icon     = 7548916,
        spellIDs = { 1236994 },
        duration = 30,
    },
    {
        key      = "liquid_luster",
        name     = "Liquid Luster",
        -- Picker art runtime-resolved (fileID not known statically at authoring
        -- time), mirroring CDM_ITEM_PRESETS' liquid_luster entry below.
        icon     = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(271887)) or 134400,
        spellIDs = { 1295132 },
        duration = 30,
    },
    {
        key      = "invis_potion",
        name     = "Invisibility Potion",
        icon     = 134764,
        spellIDs = { 371125, 431424, 371133, 371134, 1236551 },
        duration = 18,
    },
}
ns.BUFF_BAR_PRESETS = BUFF_BAR_PRESETS

-- Horde casts Bloodlust (2825), Alliance casts Heroism (32182). UnitFactionGroup
-- can read nil this early in a client session, and a wrong read baked into the
-- table would stick for the whole session (a Horde player got the Heroism name,
-- icon and id in the picker), so OnEnable calls this again once the player loads.
function ns.RefreshLustPresetFaction()
    local alliance = UnitFactionGroup("player") == "Alliance"
    local name = alliance and "Heroism" or "Bloodlust"
    local icon = alliance and "Interface\\Icons\\ability_shaman_heroism"
                          or  "Interface\\Icons\\spell_nature_bloodlust"
    ns._lustPresetSpellID = alliance and 32182 or 2825
    for _, p in ipairs(BUFF_BAR_PRESETS) do
        if p.key == "bloodlust" then
            p.name, p.icon = name, icon
            -- This character's id leads: everything that stores a preset takes
            -- spellIDs[1], while the membership tests read the whole list.
            p.spellIDs[1] = ns._lustPresetSpellID
            p.spellIDs[2] = alliance and 2825 or 32182
            break
        end
    end
    -- The Tracking Bar list copies name/icon by value at load (spellIDs is the
    -- same table), and is built after this file, so it is absent on the first call.
    for _, e in ipairs(ns.TBB_POPULAR_BUFFS or {}) do
        if e.key == "bloodlust" then e.name, e.icon = name, icon; break end
    end
end
ns.RefreshLustPresetFaction()

-- A profile shared between a Horde and an Alliance character keeps whichever lust
-- id was stored first, so icon art resolves through here instead of off that id.
function ns.LustPresetIconSpellID(sid)
    if ns.IsLustPresetSpell and ns.IsLustPresetSpell(sid) then
        return ns._lustPresetSpellID or sid
    end
    return sid
end

-- Item presets for CD/utility bars (potions that track cooldowns). displayOrder is a
-- dynamic-display priority list, newest tier first: the icon resolves to the FIRST id
-- with a bag count (that variant's icon/count/tooltip); rank 2 before rank 1, Fleeting
-- before regular at equal rank (cheap pots burn first). swapWith is an ORDERED list of
-- partner preset keys whose displayOrders get appended in order when "Swap Combat
-- Potions When Missing" is on and this family is fully out of bags (Liquid Luster is
-- the deliberate final fallback for the other two).
local CDM_ITEM_PRESETS = {
    {
        key      = "lights_potential",
        name     = "Light's Potential",
        icon     = 7548911,
        itemID   = 241308,
        altItemIDs = { 245898, 245897, 241309 },
        displayOrder = {
            245898,  -- Fleeting Light's Potential r2
            241308,  -- Light's Potential r2
            245897,  -- Fleeting Light's Potential r1
            241309,  -- Light's Potential r1
        },
        swapWith = { "potion_recklessness", "liquid_luster" },
    },
    {
        key      = "potion_recklessness",
        name     = "Potion of Recklessness",
        icon     = 7548916,
        itemID   = 241288,
        altItemIDs = { 241289, 245902, 245903 },
        displayOrder = {
            245902,  -- Fleeting Potion of Recklessness r2
            241288,  -- Potion of Recklessness r2
            245903,  -- Fleeting Potion of Recklessness r1
            241289,  -- Potion of Recklessness r1
        },
        swapWith = { "lights_potential", "liquid_luster" },
    },
    {
        key      = "liquid_luster",
        name     = "Liquid Luster",
        -- Picker art runtime-resolved (fileID not known statically at authoring
        -- time); question-mark fallback is theoretical -- icon lookups are
        -- client-DB-local.
        icon     = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(271887)) or 134400,
        itemID   = 271887,
        altItemIDs = { 274764, 274763, 271886 },
        displayOrder = {
            274764,  -- Fleeting Liquid Luster r2
            271887,  -- Liquid Luster r2
            274763,  -- Fleeting Liquid Luster r1
            271886,  -- Liquid Luster r1
        },
        swapWith = { "potion_recklessness", "lights_potential" },
    },
    {
        key      = "silvermoon_health",
        name     = "Concentrated Health Potion",
        -- Picker-only art (current-tier pot): PotSwap.Ensure paints every resolved
        -- variant from its own item id, so this never overrides a counted variant's
        -- icon. Runtime-resolved because the fileID isn't item-DB-stable across
        -- builds; the old Silvermoon art is the fallback.
        icon     = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(271884)) or 7548909,
        itemID   = 241304,
        altItemIDs = { 241305, 271884, 271883 },
        -- Newest tier leads (r2 before r1), then the Silvermoon pair. itemID must stay
        -- 241304: identity anchor for saved frames + PotSwap.Ensure's primary check, so it can't follow the new tier.
        displayOrder = {
            271884,  -- Concentrated Silvermoon Health Potion r2
            271883,  -- Concentrated Silvermoon Health Potion r1
            241304,  -- Silvermoon Health Potion r2
            241305,  -- Silvermoon Health Potion r1
        },
    },
    {
        key      = "lightfused_mana",
        name     = "Lightfused Mana Potion",
        icon     = 7548907,
        itemID   = 241300,
        altItemIDs = { 245917, 245916, 241301 },
    },
    {
        key      = "invis_potion",
        name     = "Invisibility Potion",
        icon     = 7548917,
        itemID   = 241302,
        altItemIDs = { 241303 },
    },
    {
        key      = "healthstone",
        name     = "Healthstone",
        icon     = 538745,
        itemID   = 5512,
        -- Pact of Gluttony turns self-conjured stones into Demonic Healthstones. Both
        -- share one unique slot, so a warlock holds one or the other and the
        -- primary-then-alts count shows whichever is owned. The lockout stays keyed
        -- to 6262 only: Demonic stones are reusable in combat.
        altItemIDs = { 224464 },
        spellID  = 6262,
        combatLockout = true,
    },
    {
        key      = "demonic_healthstone",
        name     = "Demonic Healthstone",
        itemID   = 224464,
        spellID  = 452930,
    },
}
ns.CDM_ITEM_PRESETS = CDM_ITEM_PRESETS

-- WoW Forever: the lust, Time Spiral and current-season potion presets have no
-- vanilla counterpart, so both lists drop them here, before any reader (the
-- Tracking Bars copy, the pickers, the item-preset maps) is built from them.
-- A bar or entry saved with one of these keys keeps it and finds no preset.
-- The Healthstone preset tracks the vanilla stones instead: five tiers, each a
-- base stone and two improved-talent stones. The Minor stone stays the primary
-- so entries saved against it keep their identity; the picker art is the
-- client's own stone icon. Vanilla stones are single-use items on a shared
-- item cooldown, so the combat lockout is switched off there: the family's
-- item cooldown drives the swipe for whichever stone is owned.
if EllesmereUI.IS_FOREVER then
    local drop = {
        bloodlust = true, timespiral = true, lights_potential = true,
        potion_recklessness = true, liquid_luster = true, invis_potion = true,
        silvermoon_health = true, lightfused_mana = true, demonic_healthstone = true,
    }
    for _, list in ipairs({ BUFF_BAR_PRESETS, CDM_ITEM_PRESETS }) do
        for i = #list, 1, -1 do
            if drop[list[i].key] then table.remove(list, i) end
        end
    end
    for _, p in ipairs(CDM_ITEM_PRESETS) do
        if p.key == "healthstone" then
            p.icon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(5512)) or 134400
            -- Major, Greater, Healthstone and Lesser tiers, then the improved Minor stones.
            p.altItemIDs = {
                9421, 19012, 19013,
                5510, 19010, 19011,
                5509, 19008, 19009,
                5511, 19006, 19007,
                19004, 19005,
            }
            p.combatLockout = nil
            break
        end
    end
end

-------------------------------------------------------------------------------
--  Defaults
-------------------------------------------------------------------------------
local DEFAULTS = {
    global = {},
    profile = {
        -- Style flags (Global Settings > Style). All default OFF and are
        -- reload-gated. Blizzard Style: icons keep Blizzard's rounded mask,
        -- overlay ring and swipe art; tracked buff bars use Blizzard's bar
        -- art. Classic WoW UI: square icons in the vanilla action button
        -- ring; tracked buff bars in the vanilla cast bar frame. Every EUI
        -- feature keeps working; only the EUI-look settings are disabled.
        useBlizzardStyle     = false,
        useBlizzardStyleBars = false,
        useClassicStyle      = false,
        useClassicStyleBars  = false,
        -- Bar Glows (per-spec)
        spec            = {},
        activeSpecKey   = "0",
        -- Independent display of Blizzard's current recommendation (opt-in).
        rotationAssistIcon = {
            enabled = false, onlyInCombat = false, iconSize = 48,
            showGCD = false,
            showKeybind = false, keybindSize = 14,
            keybindOffsetX = 2, keybindOffsetY = -2,
            keybindR = 1, keybindG = 1, keybindB = 1, keybindA = 0.9,
        },
        -- CDM Bars (our replacement for Blizzard CDM)
        cdmBars = {
            enabled = true,
            hideBlizzard = true,
            hideBuffsWhenInactive = true,
            showInactiveBuffIcons = false,
            desaturateInactiveBuffs = true,
            -- Keep keybind text identical across action bar swaps (stealth,
            -- druid forms, skyriding). ON by default: the defaults merge
            -- seeds it into existing profiles at login, and an explicit
            -- false (user turned it off) survives the logout default-strip.
            stableKeybinds = true,
            -- Suppress every CDM glow while out of combat (global, all bars).
            -- Off by default: opt-in, and off means the gate in StartNativeGlow
            -- is a single boolean test that never fires.
            glowsOnlyInCombat = false,
            -- Rotation Assist uses Blizzard's native highlight until the user
            -- explicitly opts into a custom style.
            rotationAssistStyle = "blizzard",
            rotationAssistColorMode = "default",
            rotationAssistColorR = 1,
            rotationAssistColorG = 0,
            rotationAssistColorB = 0,
            rotationAssistThickness = 3,
            rotationAssistOutset = 1,
            -- The 3 default bars (match Blizzard CDM)
            bars = {
                {
                    key = "cooldowns", name = "Cooldowns", enabled = true,
                    barType = "cooldowns",
                    iconSize = 42, numRows = 1, spacing = 2,
                    borderSize = 1, borderR = 0, borderG = 0, borderB = 0, borderA = 1,
                    borderClassColor = false, borderTexture = "solid",
                    bgR = 0.08, bgG = 0.08, bgB = 0.08, bgA = 0.6,
                    iconZoom = 0.08, iconShape = "none",
                    verticalOrientation = false, barBgEnabled = false,                    barBgR = 0, barBgG = 0, barBgB = 0,
                    borderThickness = "thin",
                    anchorTo = "none", anchorPosition = "left",
                    anchorOffsetX = 0, anchorOffsetY = 0,
                    barVisibility = "always", housingHideEnabled = true,
                    visHideHousing = true, visOnlyInstances = false,
                    visHideMounted = false, visHideNoTarget = false, visHideNoEnemy = false,
                    showCooldownText = true, cooldownTextPosition = "center",
                    showItemCount = true, showTooltip = false, showKeybind = false,
                    keybindSize = 10, keybindOffsetX = 2, keybindOffsetY = -2, keybindAlign = "left",
                    keybindR = 1, keybindG = 1, keybindB = 1, keybindA = 0.9,
                },
                {
                    key = "utility", name = "Utility", enabled = true,
                    barType = "utility",
                    iconSize = 36, numRows = 1, spacing = 2,
                    borderSize = 1, borderR = 0, borderG = 0, borderB = 0, borderA = 1,
                    borderClassColor = false, borderTexture = "solid",
                    bgR = 0.08, bgG = 0.08, bgB = 0.08, bgA = 0.6,
                    iconZoom = 0.08, iconShape = "none",
                    verticalOrientation = false, barBgEnabled = false,                    barBgR = 0, barBgG = 0, barBgB = 0,
                    borderThickness = "thin",
                    anchorTo = "none", anchorPosition = "left",
                    anchorOffsetX = 0, anchorOffsetY = 0,
                    barVisibility = "always", housingHideEnabled = true,
                    visHideHousing = true, visOnlyInstances = false,
                    visHideMounted = false, visHideNoTarget = false, visHideNoEnemy = false,
                    showCooldownText = true, cooldownTextPosition = "center",
                    showItemCount = true, showTooltip = false, showKeybind = false,
                    keybindSize = 10, keybindOffsetX = 2, keybindOffsetY = -2, keybindAlign = "left",
                    keybindR = 1, keybindG = 1, keybindB = 1, keybindA = 0.9,
                },
                {
                    key = "buffs", name = "Buffs", enabled = true,
                    barType = "buffs",
                    -- Always Show Buffs (per-bar): greyed placeholder icon for each
                    -- inactive tracked buff; desaturateInactiveBuffs is the inline cog.
                    showInactiveBuffIcons = false, desaturateInactiveBuffs = true,
                    hidePlaceholderIcon = false,
                    iconSize = 32, numRows = 1, spacing = 2,
                    borderSize = 1, borderR = 0, borderG = 0, borderB = 0, borderA = 1,
                    borderClassColor = false, borderTexture = "solid",
                    bgR = 0.08, bgG = 0.08, bgB = 0.08, bgA = 0.6,
                    iconZoom = 0.08, iconShape = "none",
                    verticalOrientation = false, barBgEnabled = false,                    barBgR = 0, barBgG = 0, barBgB = 0,
                    borderThickness = "thin",
                    anchorTo = "none", anchorPosition = "left",
                    anchorOffsetX = 0, anchorOffsetY = 0,
                    barVisibility = "always", housingHideEnabled = true,
                    visHideHousing = true, visOnlyInstances = false,
                    visHideMounted = false, visHideNoTarget = false, visHideNoEnemy = false,
                    showCooldownText = true, cooldownTextPosition = "center",
                    showItemCount = true, showTooltip = false, showKeybind = false,
                    keybindSize = 10, keybindOffsetX = 2, keybindOffsetY = -2, keybindAlign = "left",
                    keybindR = 1, keybindG = 1, keybindB = 1, keybindA = 0.9,
                },
            },
        },
        -- Saved positions for CDM bars (keyed by bar key)
        cdmBarPositions = {},
    },
}

-- Main-chunk locals the EUI_CDM_*.lua files re-import by name.
-- inCombatSetters: a file that reads _inCombat keeps its own local and adds a
-- setter here; the event frame writes through SetInCombat, which runs them all.
ns._NewInternals("_internals", {
    _bonusScanSeen = _bonusScanSeen, _cdmKeybindCache = _cdmKeybindCache,
    _cdmKeybindRank = _cdmKeybindRank, _cdmMouseState = _cdmMouseState,
    _cdmViewerNames = _cdmViewerNames, _ecmeFC = _ecmeFC, _getFD = _getFD,
    _maxChargeCount = _maxChargeCount, _multiChargeSpells = _multiChargeSpells,
    _myRacials = _myRacials, _myRacialsSet = _myRacialsSet,
    ALL_RACIAL_SPELLS = ALL_RACIAL_SPELLS, CDM_SHAPES = CDM_SHAPES, DEFAULTS = DEFAULTS,
    ECME = ECME, EffectiveBarAlpha = EffectiveBarAlpha, FC = FC,
    IsPlaceholderRenderHidden = IsPlaceholderRenderHidden, RACE_RACIALS = RACE_RACIALS,
    ResolveActiveRacial = ResolveActiveRacial, SnapForScale = SnapForScale,
    inCombatSetters = { function(v) _inCombat = v end },
    SetInCombat = function(v)
        local list = ns._internals.inCombatSetters
        for i = 1, #list do list[i](v) end
    end,
})
