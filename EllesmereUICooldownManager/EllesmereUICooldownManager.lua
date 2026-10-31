if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUICooldownManager.lua
--  CDM Look Customization and Cooldown Display
--  Mirrors Blizzard CDM bars with custom styling, cooldown swipes,
--  desaturation, active state animations, and per-spec profiles.
--  Does NOT parse secret values works around restricted APIs.
-------------------------------------------------------------------------------
local _, ns = ...
if not (EllesmereUI and EllesmereUI._ModuleNS and EllesmereUI.NewInternals and EllesmereUI.NewCombatQueue and EllesmereUI.SetFramePlacer and EllesmereUI._Pool and EllesmereUI.NewFrameData) then EUI_CLIENT_BLOCKED = true; return end -- stale-parent guard: a partially updated install (old parent, new child) goes dormant via the line-1 failsafe instead of erroring (the loot roll placement uses the parent's frame placer, the hooks file its frame-data constructor)
EllesmereUI._ModuleNS["EllesmereUICooldownManager"] = ns  -- LOD options files read this module ns via the registry

-- CPU-attribution shell pool: the engine bills a handler's call tree to the addon
-- whose context created the frame, so frames built later under the parent's dispatch
-- would bill the parent forever (see EllesmereUI_Ticker.lua). Pre-created here so they
-- stamp to CooldownManager; use ns.TakeShell() (not CreateFrame) for any frame with
-- events/scripts. No release -- throwaways use CreateFrame directly.
do
    local pool = {}
    local n = 47 -- keep above every shell this module takes, with spare
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
-- WoW Forever's races learn other racials: Every Man for Himself (59752),
-- Shadowmeld 58984 and Berserking 26297 do not exist there. Each Forever ID
-- goes FIRST (the in-spellbook pick and the fallback); the retail IDs stay
-- listed, so a profile brought over from retail still remaps its Racial slot.
-- Forever's second racials (Perception, Elune's Light, Shatter Curse, Rapid
-- Regeneration, Cannibalize, Eureka!, Walk on Air) stay ordinary spells: the
-- CDM keeps one Racial slot and strips every other listed racial from bars.
if EllesmereUI.IS_FOREVER then
    table.insert(RACE_RACIALS.Human, 1, 1259718)       -- Will to Survive
    table.insert(RACE_RACIALS.NightElf, 1, 20580)      -- Shadowmeld
    table.insert(RACE_RACIALS.Troll, 1, 20554)         -- Berserking (every class)
    -- Each Skyborne variant learns one of the two.
    RACE_RACIALS.Skyborne = { 1259705, 1259686 }       -- Read Ley Line, Skysight
end
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


-- The potion and healthstone ids of the presets below: the shared consumables
-- catalogue (EllesmereUI_BuffPresets.lua), never copied here.
local CON = EllesmereUI.CONSUMABLES

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
        spellIDs = CON.lights_potential.spellIDs,
        duration = 30,
    },
    {
        key      = "potion_recklessness",
        name     = "Potion of Recklessness",
        icon     = 7548916,
        spellIDs = CON.potion_recklessness.spellIDs,
        duration = 30,
    },
    {
        key      = "liquid_luster",
        name     = "Liquid Luster",
        -- Picker art runtime-resolved (fileID not known statically at authoring
        -- time), mirroring CDM_ITEM_PRESETS' liquid_luster entry below.
        icon     = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(271887)) or 134400,
        spellIDs = CON.liquid_luster.spellIDs,
        duration = 30,
    },
    {
        key      = "invis_potion",
        name     = "Invisibility Potion",
        icon     = 134764,
        spellIDs = CON.invis_potion.spellIDs,
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
-- before regular at equal rank (cheap pots burn first).
-- The three combat potions are ONE picker entry, Combat Potion: potFamily names each
-- family (familyName is its row in the icon's Combat Potion Icon menu, which orders
-- the families and says whether a family out of bags swaps to the next; PotSwap in
-- EUI_CDM_HookPresetCooldowns.lua), potDefaultOrder is the order an icon saved under
-- that family's key starts with (its own family first, as the old swap chains ran),
-- and the two legacy entries stay resolvable for bars saved with their keys without
-- being offered again. nativeCategory is the spell category of Blizzard's own Cooldown
-- Manager row for the item (Combat Potion 4, Health Potion 30, Healthstone 1711,
-- Demonic Healthstone 2566, Blizzard's own table): that row renders under this
-- preset's key (EUI_CDM_HookResolve.lua, NativeItemKeyFor).
local CDM_ITEM_PRESETS = {
    {
        key      = "lights_potential",
        name     = "Combat Potion",
        familyName = "Light's Potential",
        icon     = 7548911,
        itemID   = CON.lights_potential.itemID,
        altItemIDs = CON.lights_potential.altItemIDs,
        displayOrder = CON.lights_potential.displayOrder,
        potFamily = "light",
        potDefaultOrder = { "light", "reck", "luster" },
        nativeCategory = 4,
    },
    {
        key      = "potion_recklessness",
        name     = "Combat Potion",
        familyName = "Potion of Recklessness",
        icon     = 7548916,
        itemID   = CON.potion_recklessness.itemID,
        altItemIDs = CON.potion_recklessness.altItemIDs,
        displayOrder = CON.potion_recklessness.displayOrder,
        potFamily = "reck",
        potDefaultOrder = { "reck", "light", "luster" },
        nativeCategory = 4,
        legacy = true,
    },
    {
        key      = "liquid_luster",
        name     = "Combat Potion",
        familyName = "Liquid Luster",
        -- Family art runtime-resolved (fileID not known statically at authoring
        -- time); question-mark fallback is theoretical -- icon lookups are
        -- client-DB-local.
        icon     = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(271887)) or 134400,
        itemID   = CON.liquid_luster.itemID,
        altItemIDs = CON.liquid_luster.altItemIDs,
        displayOrder = CON.liquid_luster.displayOrder,
        potFamily = "luster",
        potDefaultOrder = { "luster", "reck", "light" },
        nativeCategory = 4,
        legacy = true,
    },
    {
        key      = "silvermoon_health",
        name     = "Concentrated Health Potion",
        -- Picker-only art (current-tier pot): PotSwap.Ensure paints every resolved
        -- variant from its own item id, so this never overrides a counted variant's
        -- icon. Runtime-resolved because the fileID isn't item-DB-stable across
        -- builds; the old Silvermoon art is the fallback.
        icon     = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(271884)) or 7548909,
        -- itemID (241304) is the identity anchor for saved frames and PotSwap.Ensure's
        -- primary check, so it never follows the newer tier that leads the display.
        itemID   = CON.silvermoon_health.itemID,
        altItemIDs = CON.silvermoon_health.altItemIDs,
        displayOrder = CON.silvermoon_health.displayOrder,
        nativeCategory = 30,
    },
    {
        key      = "lightfused_mana",
        name     = "Lightfused Mana Potion",
        icon     = 7548907,
        itemID   = CON.lightfused_mana.itemID,
        altItemIDs = CON.lightfused_mana.altItemIDs,
    },
    {
        key      = "invis_potion",
        name     = "Invisibility Potion",
        icon     = 7548917,
        itemID   = CON.invis_potion.itemID,
        altItemIDs = CON.invis_potion.altItemIDs,
    },
    {
        key      = "healthstone",
        name     = "Healthstone",
        icon     = 538745,
        itemID   = CON.healthstone.itemID,
        -- Pact of Gluttony turns self-conjured stones into Demonic Healthstones. Both
        -- share one unique slot, so a warlock holds one or the other and the
        -- primary-then-alts count shows whichever is owned. The lockout stays keyed
        -- to 6262 only: Demonic stones are reusable in combat.
        altItemIDs = CON.healthstone.altItemIDs,
        spellID  = CON.healthstone.spellIDs[1],
        combatLockout = true,
        nativeCategory = 1711,
    },
    {
        key      = "demonic_healthstone",
        name     = "Demonic Healthstone",
        itemID   = CON.demonic_healthstone.itemID,
        spellID  = CON.demonic_healthstone.spellIDs[1],
        nativeCategory = 2566,
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
            p.altItemIDs = EllesmereUI.FOREVER_HEALTHSTONES
            p.combatLockout = nil
            break
        end
    end
end

-- Built after the WoW Forever drop, so they describe the presets this client offers.
do
    -- The combat potion families in their canonical order (the Combat Potion Icon
    -- menu's rows), each with its preset; empty on WoW Forever, which has none.
    local families = {}
    -- Blizzard's own item rows: spell category -> the entry keys (-itemID) such a
    -- row can render under, the first the one it takes while no bar lists any.
    local nativeKeys = {}
    -- The item preset an entry key (-itemID, the preset's primary item) stands for;
    -- nil for a Custom Item ID or anything else.
    local byKey = {}
    for _, p in ipairs(CDM_ITEM_PRESETS) do
        if p.potFamily then
            families[#families + 1] = { key = p.potFamily, name = p.familyName, preset = p }
        end
        local cat = p.nativeCategory
        if cat then
            local list = nativeKeys[cat]
            if not list then list = {}; nativeKeys[cat] = list end
            list[#list + 1] = -p.itemID
        end
        byKey[-p.itemID] = p
    end
    ns.COMBAT_POTION_FAMILIES = families
    ns.CDM_NATIVE_ITEM_KEYS = nativeKeys
    function ns.ItemPresetForKey(key) return byKey[key] end
end

-------------------------------------------------------------------------------
--  Defaults
-------------------------------------------------------------------------------
local DEFAULTS = {
    global = {},
    profile = {
        -- TTS preferences apply to this Cooldown Manager profile. Existing
        -- users keep the previous default voice and volume.
        ttsVoiceID           = 0,
        ttsVolume            = 100,
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
-- broken: true while a part file loads; a file that fails leaves it set and
-- the files behind it return at their first lines (same for the Hooks and
-- Buff Bars tables).
EllesmereUI.NewInternals(ns, "_internals", {
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
}, { SetInCombat = "inCombatSetters" })
