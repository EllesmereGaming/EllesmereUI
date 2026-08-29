if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUICooldownManager.lua
--  CDM Look Customization and Cooldown Display
--  Mirrors Blizzard CDM bars with custom styling, cooldown swipes,
--  desaturation, active state animations, and per-spec profiles.
--  Does NOT parse secret values works around restricted APIs.
-------------------------------------------------------------------------------
local _, ns = ...
if not (EllesmereUI and EllesmereUI._ModuleNS) then EUI_CLIENT_BLOCKED = true; return end -- stale-parent guard: a partially updated install (old parent, new child) goes dormant via the line-1 failsafe instead of erroring
EllesmereUI._ModuleNS["EllesmereUICooldownManager"] = ns  -- LOD options files read this module ns via the registry

-- CPU-attribution shell pool: the engine bills a handler's call tree to the addon
-- whose context created the frame, so frames built later under the parent's dispatch
-- would bill the parent forever (see EllesmereUI_Ticker.lua). Pre-created here so they
-- stamp to CooldownManager; use ns.TakeShell() (not CreateFrame) for any frame with
-- events/scripts. No release -- throwaways use CreateFrame directly.
do
    local pool = {}
    local n = 32
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

-- EMERGENCY CONFLICT GUARD: the addon detected below hooks the same Blizzard
-- frames we do; running both crashes the client on the loading screen. Detect
-- and no-op our entire module so the user can at least log in.
do
    local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    if isLoaded and isLoaded("Ayije_CDM") then
        -- Skip the generic conflict checker so our Disable & Reload popup takes priority.
        _G._EUI_ECME_HandledAyijeCDM = true
        local function ShowCrashPopup()
            if not EllesmereUI then return end
            local POPUP_W, POPUP_H = 420, 180
            local EG   = EllesmereUI.ELLESMERE_GREEN or { r = 0.047, g = 0.824, b = 0.624 }
            local FONT = EllesmereUI.EXPRESSWAY or STANDARD_TEXT_FONT

            local dimmer = CreateFrame("Frame", nil, UIParent)
            dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
            dimmer:SetFrameLevel(150)
            dimmer:SetAllPoints(UIParent)
            dimmer:EnableMouse(true)        -- swallow all clicks
            dimmer:EnableMouseWheel(true)
            dimmer:SetScript("OnMouseWheel", function() end)
            dimmer:SetScript("OnMouseDown", function() end) -- no click-outside dismiss
            local dimTex = dimmer:CreateTexture(nil, "BACKGROUND")
            dimTex:SetAllPoints()
            dimTex:SetColorTexture(0, 0, 0, 0.45)

            local popup = CreateFrame("Frame", nil, dimmer)
            popup:SetSize(POPUP_W, POPUP_H)
            popup:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
            popup:SetFrameStrata("FULLSCREEN_DIALOG")
            popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)
            popup:EnableMouse(true)
            popup:EnableKeyboard(true)
            -- Swallow Escape: dismissal requires the button.
            popup:SetScript("OnKeyDown", function(self) self:SetPropagateKeyboardInput(false) end)

            local bg = popup:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.06, 0.08, 0.10, 1)
            if EllesmereUI.MakeBorder and EllesmereUI.PanelPP then
                EllesmereUI.MakeBorder(popup, 1, 1, 1, 0.15, EllesmereUI.PanelPP)
            end

            local title = popup:CreateFontString(nil, "OVERLAY")
            title:SetFont(FONT, 16, EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag("cdm") or "")
            title:SetTextColor(1, 1, 1)
            title:SetPoint("TOP", popup, "TOP", 0, -20)
            title:SetText("CDM Addon Conflict")

            local msg = popup:CreateFontString(nil, "OVERLAY")
            msg:SetFont(FONT, 12, EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag("cdm") or "")
            msg:SetTextColor(1, 1, 1, 0.75)
            msg:SetPoint("TOP", title, "BOTTOM", 0, -14)
            msg:SetWidth(POPUP_W - 60)
            msg:SetJustifyH("CENTER")
            msg:SetWordWrap(true)
            msg:SetSpacing(4)
            msg:SetText("Ayije_CDM and EllesmereUI's Cooldown Manager cannot both be loaded at the same time. Disable EllesmereUI's CDM for now, you can choose to disable/enable one or the other after reloading.")

            local BTN_W, BTN_H = 170, 29
            local btn = CreateFrame("Button", nil, popup)
            btn:SetSize(BTN_W + 2, BTN_H + 2)
            btn:SetPoint("BOTTOM", popup, "BOTTOM", 0, 14)
            btn:SetFrameLevel(popup:GetFrameLevel() + 2)
            local btnBrd = btn:CreateTexture(nil, "BACKGROUND")
            btnBrd:SetAllPoints()
            btnBrd:SetColorTexture(EG.r, EG.g, EG.b, 0.9)
            local btnBg = btn:CreateTexture(nil, "BORDER")
            btnBg:SetPoint("TOPLEFT", 1, -1)
            btnBg:SetPoint("BOTTOMRIGHT", -1, 1)
            btnBg:SetColorTexture(0.06, 0.08, 0.10, 0.92)
            local btnLbl = btn:CreateFontString(nil, "OVERLAY")
            btnLbl:SetFont(FONT, 12, EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag("cdm") or "")
            btnLbl:SetTextColor(EG.r, EG.g, EG.b, 0.9)
            btnLbl:SetPoint("CENTER")
            btnLbl:SetText("Disable & Reload")
            btn:SetScript("OnEnter", function()
                btnBrd:SetColorTexture(EG.r, EG.g, EG.b, 1)
                btnLbl:SetTextColor(EG.r, EG.g, EG.b, 1)
            end)
            btn:SetScript("OnLeave", function()
                btnBrd:SetColorTexture(EG.r, EG.g, EG.b, 0.9)
                btnLbl:SetTextColor(EG.r, EG.g, EG.b, 0.9)
            end)
            btn:SetScript("OnClick", function()
                local disable = C_AddOns and C_AddOns.DisableAddOn or DisableAddOn
                if disable then disable("EllesmereUICooldownManager") end
                ReloadUI()
            end)
        end

        local warnFrame = ns.TakeShell()
        warnFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        warnFrame:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            C_Timer.After(1, ShowCrashPopup)
        end)
        -- Stub ECME so any other file that reads ns.ECME doesn't nil-error.
        ns.ECME = setmetatable({}, { __index = function() return function() end end })
        return
    end
end

-- Per-addon border texture defaults (same as Action Bars -- same size system)
do
    local ALL_SIZES = { "none", "thin", "normal", "heavy", "strong" }
    local function AllSizes(ox, oy, sx, sy)
        local t = {}
        for _, k in ipairs(ALL_SIZES) do t[k] = { offsetX = ox, offsetY = oy, shiftX = sx, shiftY = sy } end
        return t
    end
    EllesmereUI.RegisterBorderDefaults("cdm", {
        ["glow"] = {
            defaultSize = "normal",
            sizes = AllSizes(0, 0, 0, 0),
        },
        ["blizz"] = {
            defaultSize = "heavy",
            sizes = {
                none   = { offsetX = 0, offsetY = 0, shiftX = 0, shiftY = 0 },
                thin   = { offsetX = 2, offsetY = 1, shiftX = 0, shiftY = 0 },
                normal = { offsetX = 3, offsetY = 2, shiftX = 0, shiftY = 0 },
                heavy  = { offsetX = 4, offsetY = 2, shiftX = 1, shiftY = 0 },
                strong = { offsetX = 4, offsetY = 2, shiftX = 2, shiftY = 0 },
            },
        },
        ["dialog"] = {
            defaultSize = "normal",
            sizes = AllSizes(4, 4, 0, 0),
        },
        ["sm:Blizzard Achievement Wood"] = {
            defaultSize = "thin",
            sizes = AllSizes(1, 1, 0, 0),
        },
    })
end

local ECME = EllesmereUI.Lite.NewAddon("EllesmereUICooldownManager")
ns.ECME = ECME

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
    masks = {
        circle   = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\circle_mask.tga",
        csquare  = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\csquare_mask.tga",
        diamond  = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\diamond_mask.tga",
        hexagon  = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\hexagon_mask.tga",
        portrait = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\portrait_mask.tga",
        shield   = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\shield_mask.tga",
        square   = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\square_mask.tga",
    },
    borders = {
        circle   = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\circle_border.tga",
        csquare  = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\csquare_border.tga",
        diamond  = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\diamond_border.tga",
        hexagon  = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\hexagon_border.tga",
        portrait = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\portrait_border.tga",
        shield   = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\shield_border.tga",
        square   = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\square_border.tga",
    },
    insets = {
        circle = 17, csquare = 17, diamond = 14,
        hexagon = 17, portrait = 17, shield = 13, square = 17,
    },
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
-- Forward declarations for glow helpers (defined later, used by consolidated helpers)
local StartNativeGlow, StopNativeGlow

-- Keybind cache: built once out-of-combat, looked up per tick
local _cdmKeybindCache       = {}   -- [spellID] -> formatted key string
local _cdmKeybindRank        = {}   -- [key] -> priority rank of the stored bind (lower wins)
local _keybindCacheReady     = false  -- true after first successful build
local _keybindDebounceTimer  = nil   -- cancellable timer for debounced keybind updates
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

-- Vehicle/petbattle state proxy: created once in CDMFinishSetup; drives _CDMApplyVisibility so CDM bars hide while in vehicle UI.
local _cdmVehicleProxy = nil
local _cdmInVehicle    = false

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


local BuildAllCDMBars
local RegisterCDMUnlockElements

-------------------------------------------------------------------------------
--  Defaults
-------------------------------------------------------------------------------
local DEFAULTS = {
    global = {},
    profile = {
        -- CDM Look
        reskinBorders   = true,
        -- Bar Glows (per-spec)
        spec            = {},
        activeSpecKey   = "0",
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

-------------------------------------------------------------------------------
--  Dedicated spell assignment store helpers
--  Lives at EllesmereUIDB.spellAssignments; spell/bar data is per-profile at
--  spellAssignments.profiles[name].specProfiles[specKey]. Top-level (not inside
--  the profile blob) so it never travels with profile export/module sync, but
--  IS forked/dropped/renamed with the profile (EllesmereUI_Profiles.lua). Active
--  bucket resolves live via ns.GetActiveSpecProfiles(). One local table (Lua 5.1's 200-local cap).
-------------------------------------------------------------------------------
local SpellStore = {}

function SpellStore.Get()
    if not EllesmereUIDB then EllesmereUIDB = {} end
    if not EllesmereUIDB.spellAssignments then
        EllesmereUIDB.spellAssignments = { profiles = {} }
    end
    return EllesmereUIDB.spellAssignments
end

-- Active profile name for the per-profile spell store; read live so a profile switch auto-follows the next CDM rebuild, no repoint step.
function ns.GetActiveProfileName()
    return (EllesmereUIDB and EllesmereUIDB.activeProfile) or "Default"
end

-- Per-profile spell store: copying a profile forks its CDM; deleting a bar never crosses
-- profiles. Until the seeding migration (cdm_per_profile_spell_store_v1) completes (_perProfileSeeded),
-- fork the legacy shared spellAssignments.specProfiles on first access so a profile never reads empty mid-migration.
function ns.GetSpecProfilesForProfile(profileName)
    local sa = SpellStore.Get()
    if not sa.profiles then sa.profiles = {} end
    local bucket = sa.profiles[profileName]
    if not bucket then
        bucket = { specProfiles = {} }
        if not sa._perProfileSeeded and type(sa.specProfiles) == "table" and next(sa.specProfiles) then
            local DeepCopy = EllesmereUI.Lite and EllesmereUI.Lite.DeepCopy
            if DeepCopy then bucket.specProfiles = DeepCopy(sa.specProfiles) end
        end
        sa.profiles[profileName] = bucket
    end
    if not bucket.specProfiles then bucket.specProfiles = {} end
    return bucket.specProfiles
end

-- Cross-spec broadcast set for Tracking Bars: bar identities (preset key/custom spellID)
-- pushed to every spec via "Add Bar to All Specs". Lives on the profile bucket OUTSIDE
-- specProfiles (survives spec switches/reloads, forks with profile); drives the Add/Remove toggle label.
function ns.GetActiveTBBBroadcastSet()
    local name = ns.GetActiveProfileName()
    -- Ensure the bucket exists (with legacy seeding) via the canonical accessor.
    ns.GetSpecProfilesForProfile(name)
    local sa = SpellStore.Get()
    local bucket = sa.profiles and sa.profiles[name]
    if not bucket then return {} end
    if not bucket.tbbBroadcast then bucket.tbbBroadcast = {} end
    return bucket.tbbBroadcast
end

-- Smooth-fill switches for Tracking Bars (Bar Layout > Smooth Bars). ONE setting for ALL
-- bars in EVERY spec: profile bucket OUTSIDE specProfiles (same home as the broadcast set).
-- Keys buffs/cooldowns; absent buffs reads ENABLED, absent cooldowns reads DISABLED (defaults).
function ns.GetTBBSmoothSettings()
    local name = ns.GetActiveProfileName()
    ns.GetSpecProfilesForProfile(name)
    local sa = SpellStore.Get()
    local bucket = sa.profiles and sa.profiles[name]
    if not bucket then return nil end
    if not bucket.tbbSmooth then bucket.tbbSmooth = {} end
    return bucket.tbbSmooth
end

-- Active SPELL LAYOUT name. Layouts are an account-wide library (spellAssignments.profiles[name])
-- with a SINGLE account-wide active pointer (spellAssignments.activeLayout), DETACHED from EUI
-- profiles: a profile only changes the active layout via an opt-in binding
-- (spellAssignments.profileBindings) applied by ns.ApplyProfileBinding on profile load. Self-heals to a valid layout.
function ns.GetActiveLayoutName()
    local sa = SpellStore.Get()
    if not sa.profiles then sa.profiles = {} end
    local name = sa.activeLayout
    if type(name) ~= "string" or type(sa.profiles[name]) ~= "table" then
        -- Self-heal: prefer a layout named after the current profile, else any existing layout, else the profile name (creates it).
        local cur = (EllesmereUIDB and EllesmereUIDB.activeProfile) or "Default"
        name = nil
        if type(sa.profiles[cur]) == "table" then
            name = cur
        else
            for n, v in pairs(sa.profiles) do
                if type(v) == "table" then name = n; break end
            end
        end
        name = name or cur
        sa.activeLayout = name
    end
    return name
end

-- specProfiles for the active PROFILE (the live CDM bucket): spell content is per-EUI-profile,
-- no account-wide layout pointer mediates rendering. Combat-hot and CACHED (re-deriving cost
-- ~20ms/min of combat CPU): invalidated by the spec-key cache lifecycle (ProcessSpecChange /
-- InvalidateSpecKey) plus BuildAllCDMBars' head as belt -- every profile apply, import, layout
-- switch and options rebuild passes through one of those.
function ns.GetActiveSpecProfiles()
    local sp = ns._cachedSpecProfiles
    if sp then return sp end
    sp = ns.GetSpecProfilesForProfile(ns.GetActiveProfileName())
    ns._cachedSpecProfiles = sp
    return sp
end

function SpellStore.GetSpecProfiles()
    return ns.GetActiveSpecProfiles()
end

-- (SpellStore.GetBarGlows removed -- Bar Glows disabled pending rewrite)

-------------------------------------------------------------------------------
--  Direct spell data accessor (single source of truth)
--  Returns the spell table for a bar key under the current spec, creating
--  it if needed. All spell reads/writes go through this -- no copies.
-------------------------------------------------------------------------------
-- Reference memo for combat-hot store fetches (this + the per-spell settings stores below).
-- LIVE validity: records the specProfiles ROOT table + specKey, re-checked every call, so
-- profile applies/imports/spec swaps (which change one of those two) can't be missed. Cached
-- values are TABLE REFERENCES (options edits stay visible); nil is never cached (self-heals
-- next call). Belt: BuildAllCDMBars' head drops the memo for structural ops (delete/reset) that replace an inner table.
function ns.GetBarSpellData(barKey)
    local specKey = ns.GetActiveSpecKey()
    if not specKey or specKey == "0" then return nil end
    local sp = SpellStore.GetSpecProfiles()
    local memo = ns._cdmStoreMemo
    if memo and memo.root == sp and memo.spec == specKey then
        local hit = memo.sd[barKey]
        if hit then return hit end
    else
        memo = { root = sp, spec = specKey, sd = {} }
        ns._cdmStoreMemo = memo
    end
    local prof = sp[specKey]
    if not prof then
        prof = { barSpells = {} }
        sp[specKey] = prof
    end
    if not prof.barSpells then prof.barSpells = {} end
    local bs = prof.barSpells[barKey]
    if not bs then
        bs = {}
        prof.barSpells[barKey] = bs
    end
    memo.sd[barKey] = bs
    return bs
end

-- Variant that accepts an explicit specKey (for validation, migration, etc.)
function ns.GetBarSpellDataForSpec(barKey, specKey)
    if not specKey or specKey == "0" then return nil end
    local sp = SpellStore.GetSpecProfiles()
    local prof = sp[specKey]
    if not prof then return nil end
    if not prof.barSpells then return nil end
    local bs = prof.barSpells[barKey]
    if not bs then return nil end
    return bs
end

-------------------------------------------------------------------------------
--  Tiered per-spell settings stores
--
--  Per-spell icon settings live in FAMILY stores on the spec profile (siblings of
--  barSpells), keyed by spellID -- NOT nested under a bar, so moving a spell within
--  its family keeps its settings:
--      specProf.spellSettingsCD[sid]   -- cooldown/utility family
--      specProf.spellSettingsBuff[sid] -- buff family
--  Bar-level tiers below the per-spell entries ("Apply to Bar"):
--      barSpells[barKey].barSettings   -- this bar, this spec
--      bd.barSpellSettings             -- this bar, EVERY spec (profile-level bar
--                                         def; specs with no CDM data yet inherit it)
--  Effective value per key: spell entry > barSettings > barSpellSettings > defaults,
--  via metatable __index links ResolveSpellSettings re-asserts lazily on every lookup
--  (self-heals across moves/spec swaps/profile swaps; metatables never serialize).
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
--  Hosted-buff markers
--
--  A buff placed on a CD/utility bar ("hosted") gets its own assignedSpells entry,
--  encoded as a negative marker so it never collides with the same spell's cooldown
--  entry (one spellID can be in BOTH the Essential/Utility and Tracked Buffs catalogs,
--  e.g. Divine Shield 642). The marker is an independent slot -- own position,
--  remove/move, per-icon settings -- even when the cooldown form is on the same bar.
--
--  Encoding: -(BASE + spellID). BASE sits far below the item-preset range (<= -100,
--  negated itemIDs) and the trinket slots (-13/-14), so existing negative-id branches
--  keep working; anything <= -BASE is a marker.
-------------------------------------------------------------------------------
ns.HOSTED_BUFF_MARKER_BASE = 2000000000

-------------------------------------------------------------------------------
--  Equipment-slot entries: a bar entry can store a negated INVENTORY SLOT id (-1..-19)
--  to track whatever item is equipped there; trinket slots (-13/-14) and user-added slots
--  (belt -6, cloak -15, ...) share the same frame/update machinery. Range is safe: item
--  presets are <= -100 and the custom-item popup rejects IDs below 100, so nothing else
--  occupies -1..-19. INV_SLOT_NAMES is keyed by slot id; slot 18 (obsolete ranged) is
--  deliberately absent -- SlotIDFromKey treats absence as "not a slot".
-------------------------------------------------------------------------------
ns.INV_SLOT_NAMES = {
    [1] = HEADSLOT,   [2] = NECKSLOT,      [3] = SHOULDERSLOT, [4] = SHIRTSLOT,
    [5] = CHESTSLOT,  [6] = WAISTSLOT,     [7] = LEGSSLOT,     [8] = FEETSLOT,
    [9] = WRISTSLOT,  [10] = HANDSSLOT,    [11] = FINGER0SLOT, [12] = FINGER1SLOT,
    [13] = TRINKET0SLOT, [14] = TRINKET1SLOT, [15] = BACKSLOT,
    [16] = MAINHANDSLOT, [17] = SECONDARYHANDSLOT, [19] = TABARDSLOT,
}

-- Decode an equipment-slot entry to its inventory slot id; nil for anything else.
function ns.SlotIDFromKey(key)
    if type(key) == "number" and key < 0 and ns.INV_SLOT_NAMES[-key] then
        return -key
    end
    return nil
end

function ns.HostedBuffMarker(spellID)
    return -(ns.HOSTED_BUFF_MARKER_BASE + spellID)
end

-- Decode a hosted-buff marker to its spellID; nil otherwise. Bounded by CD_CLAIM_MARKER_BASE so a cd-claim marker never misdecodes as a spellID.
function ns.HostedBuffMarkerToSpell(id)
    if type(id) == "number" and id <= -ns.HOSTED_BUFF_MARKER_BASE
       and id > -ns.CD_CLAIM_MARKER_BASE then
        return -id - ns.HOSTED_BUFF_MARKER_BASE
    end
    return nil
end

-- True when the list already holds the hosted marker for spellID.
function ns.ListHasHostedMarker(list, spellID)
    if not list then return false end
    local marker = -(ns.HOSTED_BUFF_MARKER_BASE + spellID)
    for i = 1, #list do
        if list[i] == marker then return true end
    end
    return false
end

-------------------------------------------------------------------------------
--  Cd-claim markers: a collided buff (two Blizzard buff-viewer slots sharing one canonical
--  spellID, e.g. Diabolist Demonic Art vs Diabolic Ritual) can't be told apart by spellID, so
--  a claimed slot is tracked by its cooldownID instead, using the same marker-in-assignedSpells
--  pattern as hosted-buff markers (add/remove/drag/reorder reuse the existing machinery).
--
--  Encoding: -(BASE + cooldownID). BASE sits beyond HOSTED_BUFF_MARKER_BASE (+ max plausible
--  spellID), so every hosted-buff-marker check (bounded at HOSTED_BUFF_MARKER_BASE) already excludes cd-claim markers.
-------------------------------------------------------------------------------
ns.CD_CLAIM_MARKER_BASE = 3000000000

function ns.CdClaimMarker(cdID)
    return -(ns.CD_CLAIM_MARKER_BASE + cdID)
end

-- Decode a cd-claim marker to its cooldownID; nil for anything else.
function ns.CdClaimMarkerToCdID(id)
    if type(id) == "number" and id <= -ns.CD_CLAIM_MARKER_BASE then
        return -id - ns.CD_CLAIM_MARKER_BASE
    end
    return nil
end

-- Every cd-claim marker in a bar's assignedSpells as a set ({[cdID]=true,...}), or nil if none.
function ns.CollectCdClaimSet(sd)
    if not sd or not sd.assignedSpells then return nil end
    local set
    for _, id in ipairs(sd.assignedSpells) do
        local cd = ns.CdClaimMarkerToCdID(id)
        if cd then
            set = set or {}
            set[cd] = true
        end
    end
    return set
end

-- Family store key for a bar ("spellSettingsBuff" for buff-family bars, "spellSettingsCD" for everything else, including the ghost CD bar).
function ns.SettingsFamilyKey(barKeyOrBd)
    if ns.IsBarBuffFamily and ns.IsBarBuffFamily(barKeyOrBd) then
        return "spellSettingsBuff"
    end
    return "spellSettingsCD"
end

-- Family per-spell store for an explicit spec profile table.
function ns.GetSpellSettingsStoreForProf(prof, famKey, create)
    if not prof then return nil end
    local st = prof[famKey]
    if not st and create then st = {}; prof[famKey] = st end
    return st
end

-- Family per-spell store for the ACTIVE spec, resolved from a bar. Same live-validity
-- reference memo as GetBarSpellData: keyed by family under the shared memo, nil never
-- cached, and create=true refreshes the entry so a first-write store is immediately visible to readers.
function ns.GetSpellSettingsStore(barKeyOrBd, create)
    local specKey = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
    if not specKey or specKey == "0" then return nil end
    local sp = SpellStore.GetSpecProfiles()
    if not sp then return nil end
    local famKey = ns.SettingsFamilyKey(barKeyOrBd)
    local memo = ns._cdmStoreMemo
    if memo and memo.root == sp and memo.spec == specKey then
        if not create then
            local hit = memo[famKey]
            if hit then return hit end
        end
    else
        memo = { root = sp, spec = specKey, sd = {} }
        ns._cdmStoreMemo = memo
    end
    local prof = sp[specKey]
    if not prof then
        if not create then return nil end
        prof = { barSpells = {} }
        sp[specKey] = prof
    end
    local st = ns.GetSpellSettingsStoreForProf(prof, famKey, create)
    if st then memo[famKey] = st end
    return st
end

-- Chain child.__index -> parent (or clear the link when parent is nil), so every read of a
-- per-spell table falls through to the bar tiers per KEY. Cheap: one getmetatable + compare.
function ns.ChainSettings(child, parent)
    if not child then return end
    local mt = getmetatable(child)
    if parent then
        if not mt then
            setmetatable(child, { __index = parent })
        elseif mt.__index ~= parent then
            mt.__index = parent
        end
    elseif mt and mt.__index ~= nil then
        mt.__index = nil
    end
end

-- Bar-tier chain head for a bar: barSettings (chained to the profile-level bd.barSpellSettings) when present, else bd.barSpellSettings, else nil.
function ns.GetBarTierSettings(sd, barKey)
    local bd = barKey and ns.barDataByKey and ns.barDataByKey[barKey]
    local abs = bd and bd.barSpellSettings
    local bs = sd and sd.barSettings
    if bs then
        ns.ChainSettings(bs, abs)
        return bs
    end
    return abs
end

-- True when any per-icon settings could apply on this bar: family store has ANY entry
-- (over-approximate -- keyed by spell, not bar) or either bar tier is non-empty. Gates "re-resolve appearance" passes.
function ns.BarHasAnySpellSettings(barKey, sd)
    local st = ns.GetSpellSettingsStore(barKey)
    if st and next(st) ~= nil then return true end
    sd = sd or ns.GetBarSpellData(barKey)
    if sd then
        if sd.barSettings and next(sd.barSettings) ~= nil then return true end
        -- Legacy shape safety net (pre-migration data; should not happen since migration runs before this addon loads).
        if sd.spellSettings and next(sd.spellSettings) ~= nil then return true end
    end
    local bd = ns.barDataByKey and ns.barDataByKey[barKey]
    if bd and bd.barSpellSettings and next(bd.barSpellSettings) ~= nil then return true end
    return false
end

-- Iterate every SAVED settings block that can hold per-spell setting keys: all specs'
-- family-store entries + per-bar barSettings, plus the active profile's bar-level
-- barSpellSettings. fn(ss) returning true stops the walk. Used by login gate scans ("does anyone use feature X anywhere").
function ns.ForEachSavedSettingsBlock(fn)
    if not EllesmereUIDB then return false end
    local sp = SpellStore and SpellStore.GetSpecProfiles and SpellStore.GetSpecProfiles()
    if sp then
        for _, prof in pairs(sp) do
            if type(prof) == "table" then
                local stCD = prof.spellSettingsCD
                if type(stCD) == "table" then
                    for _, ss in pairs(stCD) do
                        if type(ss) == "table" and fn(ss) then return true end
                    end
                end
                local stBuff = prof.spellSettingsBuff
                if type(stBuff) == "table" then
                    for _, ss in pairs(stBuff) do
                        if type(ss) == "table" and fn(ss) then return true end
                    end
                end
                local barSpells = prof.barSpells
                if type(barSpells) == "table" then
                    for _, bs in pairs(barSpells) do
                        local bset = type(bs) == "table" and bs.barSettings
                        if type(bset) == "table" and fn(bset) then return true end
                        -- Legacy shape safety net (pre-migration data; should not happen since migration runs before this addon loads).
                        local ssAll = type(bs) == "table" and bs.spellSettings
                        if type(ssAll) == "table" then
                            for _, ss in pairs(ssAll) do
                                if type(ss) == "table" and fn(ss) then return true end
                            end
                        end
                    end
                end
            end
        end
    end
    local p = ECME and ECME.db and ECME.db.profile
    local bars = p and p.cdmBars and p.cdmBars.bars
    if type(bars) == "table" then
        for _, bd in ipairs(bars) do
            local abs = type(bd) == "table" and bd.barSpellSettings
            if type(abs) == "table" and fn(abs) then return true end
        end
    end
    return false
end

-- One-time copy of a user CUSTOM spell/buff (customSpellIDs-tagged) plus its per-spell settings
-- onto the SAME bar in other specs of the active profile (bar defs are profile-level, so the bar
-- exists in every spec). A target spec that already has the spell on ANY bar is skipped whole
-- (never duplicates within a spec). Custom Active State is NOT copied: it lives in the
-- profile-level customActiveStates store, already shared across specs. Returns the count copied to.
function ns.CopyCustomSpellToSpecs(barKey, spellID, specKeys)
    if not barKey or type(spellID) ~= "number" or spellID == 0 then return 0 end
    if type(specKeys) ~= "table" then return 0 end
    local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
    if not sp then return 0 end
    local curKey = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
    local famKey = ns.SettingsFamilyKey(barKey)
    local DeepCopy = EllesmereUI.Lite and EllesmereUI.Lite.DeepCopy

    -- Source metadata from the ACTIVE spec (the bar the menu was opened on).
    local srcSd = ns.GetBarSpellData(barKey)
    local dur = srcSd and srcSd.spellDurations and srcSd.spellDurations[spellID]
    local srcStore = ns.GetSpellSettingsStore(barKey)
    local srcSettings = srcStore and srcStore[spellID]

    local copied = 0
    for key, on in pairs(specKeys) do
        if on and key ~= curKey and key ~= "0" then
            local prof = sp[key]
            if not prof then prof = { barSpells = {} }; sp[key] = prof end
            if not prof.barSpells then prof.barSpells = {} end
            -- Present anywhere in this spec? Skip the whole spec.
            local exists = false
            for _, bs in pairs(prof.barSpells) do
                if type(bs) == "table" and type(bs.assignedSpells) == "table" then
                    for _, id in ipairs(bs.assignedSpells) do
                        if id == spellID then exists = true; break end
                    end
                end
                if exists then break end
            end
            if not exists then
                local bs = prof.barSpells[barKey]
                if not bs then bs = {}; prof.barSpells[barKey] = bs end
                if not bs.assignedSpells then bs.assignedSpells = {} end
                bs.assignedSpells[#bs.assignedSpells + 1] = spellID
                if not bs.customSpellIDs then bs.customSpellIDs = {} end
                bs.customSpellIDs[spellID] = true
                if dur and dur > 0 then
                    if not bs.spellDurations then bs.spellDurations = {} end
                    bs.spellDurations[spellID] = dur
                end
                if type(srcSettings) == "table" and DeepCopy then
                    -- pairs()-based DeepCopy takes OWN keys only (no __index follow): own
                    -- settings, not bar-tier inherits. Copy is unchained; renderer re-chains on first resolve.
                    local store = prof[famKey]
                    if not store then store = {}; prof[famKey] = store end
                    if store[spellID] == nil then
                        store[spellID] = DeepCopy(srcSettings)
                        -- New entry (belt: one integer bump on a user click).
                        ns._cdmResGen = ns._cdmResGen + 1
                    end
                end
                copied = copied + 1
            end
        end
    end
    return copied
end

-- Set of OTHER specs (this class, active profile) with the spell on ANY bar. Drives the
-- per-spell menu's Copy/Remove label + the Remove picker's pre-check. Excludes the active spec.
function ns.SpecsWithCustomSpell(spellID)
    local out = {}
    if type(spellID) ~= "number" or spellID == 0 then return out end
    local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
    if not sp then return out end
    local curKey = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
    for key, prof in pairs(sp) do
        if key ~= curKey and key ~= "0" and type(prof) == "table"
           and type(prof.barSpells) == "table" then
            local found = false
            for _, bs in pairs(prof.barSpells) do
                if type(bs) == "table" and type(bs.assignedSpells) == "table" then
                    for _, id in ipairs(bs.assignedSpells) do
                        if id == spellID then found = true; break end
                    end
                end
                if found then break end
            end
            if found then out[key] = true end
        end
    end
    return out
end

-- Inverse of CopyCustomSpellToSpecs: remove the spell + its per-spell settings from the picked
-- specs (scans every bar). Never touches the active spec or the profile-level customActiveState
-- (that stays while the spell exists on ANY spec, incl. the current one). Returns the count removed.
function ns.RemoveCustomSpellFromSpecs(spellID, specKeys)
    if type(spellID) ~= "number" or spellID == 0 then return 0 end
    if type(specKeys) ~= "table" then return 0 end
    local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
    if not sp then return 0 end
    local curKey = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
    local removed = 0
    for key, on in pairs(specKeys) do
        if on and key ~= curKey and key ~= "0" then
            local prof = sp[key]
            if type(prof) == "table" and type(prof.barSpells) == "table" then
                local didRemove = false
                for _, bs in pairs(prof.barSpells) do
                    if type(bs) == "table" and type(bs.assignedSpells) == "table" then
                        local hitHere = false
                        for i = #bs.assignedSpells, 1, -1 do
                            if bs.assignedSpells[i] == spellID then
                                table.remove(bs.assignedSpells, i)
                                hitHere = true; didRemove = true
                            end
                        end
                        -- Clean the per-id metadata on the bar it lived on.
                        if hitHere then
                            if bs.customSpellIDs then bs.customSpellIDs[spellID] = nil end
                            if bs.spellDurations then bs.spellDurations[spellID] = nil end
                            if bs.customSpellDurations then bs.customSpellDurations[spellID] = nil end
                            if bs.customSpellGroups then
                                for variantID, primaryID in pairs(bs.customSpellGroups) do
                                    if primaryID == spellID or variantID == spellID then
                                        bs.customSpellGroups[variantID] = nil
                                    end
                                end
                            end
                        end
                    end
                end
                if didRemove then
                    -- Drop the per-spell settings entry (keyed by spellID, so clearing both family stores is safe -- only one holds it).
                    if prof.spellSettingsCD then prof.spellSettingsCD[spellID] = nil end
                    if prof.spellSettingsBuff then prof.spellSettingsBuff[spellID] = nil end
                    -- Entry deletion (belt: non-active specs by contract).
                    ns._cdmResGen = ns._cdmResGen + 1
                    removed = removed + 1
                end
            end
        end
    end
    return removed
end

-- Custom Active State store, keyed by spellID at the PROFILE level (shared across every
-- bar and spec) so state travels with the spell wherever placed. Key matches assignedSpells:
-- positive = racial/custom spell, negative = item/trinket-slot preset. Entry shape: { duration,
-- activeSwipeMode, activeSwipeClassColor, activeSwipeR/G/B/A, activeGlow, glowColor, glowColorR/G/B }.
function ns.GetCustomActiveStates()
    local p = ECME and ECME.db and ECME.db.profile
    if not p then return nil end
    if not p.customActiveStates then p.customActiveStates = {} end
    return p.customActiveStates
end

-- Read (or, with create=true, lazily create) the entry for one spell key.
function ns.GetCustomActiveState(spellID, create)
    local store = ns.GetCustomActiveStates()
    if not store then return nil end
    local e = store[spellID]
    if not e and create then e = {}; store[spellID] = e end
    return e
end

-- Map an icon's identity token to its SETTINGS key. Equipment SLOTS key their per-spell
-- settings by the EQUIPPED item (-itemID) so each item tracks separately; bar allocation
-- stays slot-based. Everything else (item presets, racials, custom spells) keys by its own token.
function ns.ResolveCustomActiveKey(frameKey)
    local slot = ns.SlotIDFromKey(frameKey)
    if slot then
        local itemID = GetInventoryItemID("player", slot)
        if itemID then return -itemID end
    end
    return frameKey
end

-- EFFECTIVE Custom Active State for an icon token -- READ paths only. Non-slot tokens
-- resolve their own entry. Equipment SLOTS resolve the EQUIPPED item's entry (per-item,
-- written via ResolveCustomActiveKey), chained per-key over the SLOT entry -- the "Apply to
-- Bar" stamp -- so one bar application covers whatever is equipped without an entry per item.
-- Chain re-asserted lazily every resolve (metatables never serialize), mirroring
-- ResolveSpellSettings. An explicit false own value renders like nil but BLOCKS the slot
-- value from showing through (per-item "None"); cdStateEffect consumers normalize false to nil.
function ns.GetEffectiveCustomActiveState(frameKey)
    local store = ns.GetCustomActiveStates()
    if not store then return nil end
    local slot = ns.SlotIDFromKey(frameKey)
    if slot then
        local slotE = store[frameKey]
        local itemID = GetInventoryItemID("player", slot)
        local itemE = itemID and store[-itemID] or nil
        if itemE then
            ns.ChainSettings(itemE, slotE)
            return itemE
        end
        return slotE
    end
    return store[frameKey]
end

-- Does this icon have a custom Cooldown State Effect (preset cd-state)? Appearance refresh
-- uses this so it doesn't clear a preset's _cdStateHidden flag: presets store cdState in customActiveStates, not per-bar spellSettings.
function ns.PresetHasCdState(frame)
    local fc = ns._ecmeFC and ns._ecmeFC[frame]
    if not fc or not fc.spellID then return false end
    -- Only frames WE inject can own a custom active state -- same gate the
    -- Fake-Active engine applies before honoring one. Without it an orphaned
    -- profile-level entry both hid a plain tracked spell and stopped the
    -- appearance refresh from ever clearing the flag it set.
    if ns.CdmIsInjectedFrame and not ns.CdmIsInjectedFrame(frame) then return false end
    local cas = ns.GetEffectiveCustomActiveState(fc.spellID)
    local eff = cas and cas.cdStateEffect
    if eff == false then eff = nil end  -- blocking-false = no effect
    return eff ~= nil
end

-- Max Stacks Glow gate: set ns._cdmAnyMaxStacksGlow once if any saved spell (any spec) has
-- the glow enabled, so RefreshCDMIconAppearance skips its per-icon watch check entirely for
-- non-users -- 0 cost when off. Monotonic + scanned-once: runtime enables come from the option's setValue, so this only discovers already-saved settings at/after login.
function ns.RescanMaxStacksGlowFlag()
    if ns._cdmAnyMaxStacksGlow or ns._maxStacksFlagScanned then return end
    if not EllesmereUIDB then return end
    ns._maxStacksFlagScanned = true
    ns.ForEachSavedSettingsBlock(function(ss)
        if ss.maxStacksGlow and ss.maxStacksGlow > 0 then
            ns._cdmAnyMaxStacksGlow = true
            return true
        end
    end)
end

-- Audio on Buff Gain/Loss gate: set ns._cdmAnyBuffSound once if any saved buff icon (any spec)
-- has a gain OR loss sound chosen, so DecorateFrame/RefreshCDMIconAppearance skip attaching the
-- apply-edge sound hook for non-users. Same scanned-once + runtime-enable contract as RescanMaxStacksGlowFlag.
function ns.RescanBuffSoundFlag()
    if ns._cdmAnyBuffSound or ns._buffSoundFlagScanned then return end
    if not EllesmereUIDB then return end
    ns._buffSoundFlagScanned = true
    ns.ForEachSavedSettingsBlock(function(ss)
        if (ss.buffActiveSoundKey and ss.buffActiveSoundKey ~= "none")
            or (ss.buffLostSoundKey and ss.buffLostSoundKey ~= "none") then
            ns._cdmAnyBuffSound = true
            return true
        end
    end)
end

-- Resolve the configured buff gain/loss sound key for a spell id in the CURRENT
-- spec by SEARCHING saved bar spellSettings -- independent of per-frame
-- decoration state (_ecmeFC): the first buff gain after login fires its aura
-- alert BEFORE DecorateFrame populates that state, so this must resolve purely
-- from the id. O(bars): spellSettings is keyed by id.
function ns.FindBuffSoundKey(sid, field)
    if not sid then return nil end
    local specKey = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
    if not specKey or specKey == "0" then return nil end
    local sp = SpellStore and SpellStore.GetSpecProfiles and SpellStore.GetSpecProfiles()
    local prof = sp and sp[specKey]
    if not prof then return nil end
    -- Per-spell tier: buff family store (explicit false = inherited bar-level
    -- sound turned OFF for this one buff -- treat as silent).
    local st = prof.spellSettingsBuff
    local own = st and st[sid]
    if own then
        local v = rawget(own, field)
        if v ~= nil then
            if v and v ~= "none" then return v end
            return nil
        end
    end
    -- Bar tier: the buff bar this spell renders on. Extra buff bars claim
    -- their spells via assignedSpells; everything else lives on "buffs".
    local homeKey = "buffs"
    local barSpells = prof.barSpells
    if barSpells then
        for barKey, bs in pairs(barSpells) do
            if barKey ~= "buffs" and ns.IsBarBuffFamily and ns.IsBarBuffFamily(barKey)
               and type(bs.assignedSpells) == "table" then
                for _, asid in ipairs(bs.assignedSpells) do
                    if asid == sid then homeKey = barKey; break end
                end
            end
        end
    end
    local bsHome = barSpells and barSpells[homeKey]
    local tier = ns.GetBarTierSettings(bsHome, homeKey)
    local key = tier and tier[field]
    if key and key ~= "none" then return key end
    return nil
end

-- Audio Effect on CD Ready gate: set ns._cdmAnyCdReadySound once if any saved
-- cd/utility icon (any spec) has a CD-ready sound chosen, so the per-frame
-- SetDesaturated edge hook no-ops entirely for non-users. Same monotonic,
-- scanned-once contract as RescanBuffSoundFlag.
function ns.RescanCdReadySoundFlag()
    if ns._cdmAnyCdReadySound or ns._cdReadySoundFlagScanned then return end
    if not EllesmereUIDB then return end
    ns._cdReadySoundFlagScanned = true
    ns.ForEachSavedSettingsBlock(function(ss)
        if ss.cdReadySoundKey and ss.cdReadySoundKey ~= "none" then
            ns._cdmAnyCdReadySound = true
            return true
        end
    end)
end

-- "Hide CD Text (Charges)" gate: set ns._cdmAnyChargeHideCdText once if any saved spell
-- (any spec) has the toggle on; RefreshCDMIconAppearance then skips its per-icon watch
-- check for non-users. Same contract as RescanMaxStacksGlowFlag.
function ns.RescanChargeCdTextFlag()
    if ns._cdmAnyChargeHideCdText or ns._chargeCdTextFlagScanned then return end
    if not EllesmereUIDB then return end
    ns._chargeCdTextFlagScanned = true
    ns.ForEachSavedSettingsBlock(function(ss)
        if ss.chargeHideCdText then
            ns._cdmAnyChargeHideCdText = true
            return true
        end
    end)
end

-- "Hide Charge Text" gate: set ns._cdmAnyHideChargeText once if any saved spell
-- (any spec) has the toggle on. The appearance pass consults it to reach
-- WatchZeroChargeTextIfEnabled for users of neither the bar-level zero-charge
-- feature nor an active watch -- without it the per-spell hide never runs.
-- Same monotonic, scanned-once contract as RescanChargeCdTextFlag.
function ns.RescanHideChargeTextFlag()
    if ns._cdmAnyHideChargeText or ns._hideChargeTextFlagScanned then return end
    if not EllesmereUIDB then return end
    ns._hideChargeTextFlagScanned = true
    ns.ForEachSavedSettingsBlock(function(ss)
        if ss.hideChargeText then
            ns._cdmAnyHideChargeText = true
            return true
        end
    end)
end

-- Per-spell Suppress GCD gate: the entry-B re-arm and the preset-frame GCD
-- swipe pass resolve per-spell settings only behind this flag. Same
-- monotonic, scanned-once contract as RescanChargeCdTextFlag.
function ns.RescanSuppressGcdFlag()
    if ns._cdmAnySuppressGcd or ns._suppressGcdFlagScanned then return end
    if not EllesmereUIDB then return end
    ns._suppressGcdFlagScanned = true
    ns.ForEachSavedSettingsBlock(function(ss)
        if ss.suppressGCD then
            ns._cdmAnySuppressGcd = true
            return true
        end
    end)
end

-- Charge style gate: set ns._cdmAnyChargeStyle once if any saved spell (any spec)
-- has Hide Swipe (Charges) or Hide Recharge Edge enabled. Same monotonic,
-- scanned-once contract as RescanChargeCdTextFlag.
--
-- This flag is the one charge gate that had no priming pass: it was set only from
-- inside the SetSwipeColor hook, i.e. not until the first cooldown re-push after
-- login, which is already after the rebuild has run RefreshCDMIconAppearance. So
-- the rebuild's ReapplyChargeStyle was skipped, and ApplyCdmChargeStyle itself
-- gates its whole Hide Swipe / Hide Recharge Edge block on the flag -- meaning a
-- charge spell already recharging at login kept its swipe until something pushed
-- its cooldown again. Priming here closes that window; the reactive hooks then
-- carry it as before.
function ns.RescanChargeStyleFlag()
    if ns._cdmAnyChargeStyle or ns._chargeStyleFlagScanned then return end
    if not EllesmereUIDB then return end
    ns._chargeStyleFlagScanned = true
    ns.ForEachSavedSettingsBlock(function(ss)
        if ss.chargeHideSwipe or ss.hideRechargeEdge then
            ns._cdmAnyChargeStyle = true
            return true
        end
    end)
end

-- Custom Item gate: set ns._cdmAnyCustomItem once if any saved bar (any spec) tracks a custom
-- item (assignedSpells entry <= -100); the buff-bar injection pass is skipped entirely for non-users. Same contract as the flags above.
function ns.RescanCustomItemFlag()
    if ns._cdmAnyCustomItem or ns._customItemFlagScanned then return end
    local sp = SpellStore and SpellStore.GetSpecProfiles and SpellStore.GetSpecProfiles()
    if not sp then return end
    ns._customItemFlagScanned = true
    for _, prof in pairs(sp) do
        local barSpells = prof and prof.barSpells
        if barSpells then
            for _, bs in pairs(barSpells) do
                local assigned = bs and bs.assignedSpells
                if assigned then
                    for _, sid in ipairs(assigned) do
                        -- Hosted-buff markers are also <= -100; they are not items.
                        if type(sid) == "number" and sid <= -100
                           and sid > -ns.HOSTED_BUFF_MARKER_BASE then
                            ns._cdmAnyCustomItem = true
                            return
                        end
                    end
                end
            end
        end
    end
end

-- "Show Charges" (custom CD/utility spells) gate. Same contract as the flags above; zero cost in ProcessPresetCooldowns unless a custom spell opted in.
function ns.RescanCustomForceCountFlag()
    if ns._cdmAnyCustomForceCount or ns._customForceCountScanned then return end
    local sp = SpellStore and SpellStore.GetSpecProfiles and SpellStore.GetSpecProfiles()
    if not sp then return end
    ns._customForceCountScanned = true
    for _, prof in pairs(sp) do
        local barSpells = prof and prof.barSpells
        if barSpells then
            for _, bs in pairs(barSpells) do
                if bs and type(bs.customSpellForceCount) == "table" and next(bs.customSpellForceCount) then
                    ns._cdmAnyCustomForceCount = true
                    return
                end
            end
        end
    end
end


-- Reverse Swipe gate: set ns._cdmAnyReverseSwipe once if any saved spell (any spec) has
-- per-spell reverseSwipe on; the reverse-apply in RefreshCDMIconAppearance is skipped for
-- non-users. Also gates hideCDSwipe -- both monotonic per-spell swipe flags scanned in one pass, costing nothing until used.
function ns.RescanReverseSwipeFlag()
    if ns._reverseSwipeFlagScanned then return end
    if ns._cdmAnyReverseSwipe and ns._cdmAnyHideCDSwipe then return end
    if not EllesmereUIDB then return end
    ns._reverseSwipeFlagScanned = true
    -- Regular per-spell settings (family stores + bar tiers, every spec).
    ns.ForEachSavedSettingsBlock(function(ss)
        if ss.reverseSwipe then ns._cdmAnyReverseSwipe = true end
        if ss.hideCDSwipe then ns._cdmAnyHideCDSwipe = true end
    end)
    -- Preset / custom cd-utility spells (profile-level customActiveStates).
    local cas = ns.GetCustomActiveStates and ns.GetCustomActiveStates()
    if cas then
        for _, e in pairs(cas) do
            if e then
                if e.reverseSwipe then ns._cdmAnyReverseSwipe = true end
                if e.hideCDSwipe then ns._cdmAnyHideCDSwipe = true end
            end
        end
    end
end

-- Threshold Text gate: set ns._cdmAnyThresholdText once if any saved spell (any spec) has
-- Threshold Seconds armed -- per-spell family stores, bar tiers, or preset/custom
-- customActiveStates entries. Skips the formatter attach in RefreshCDMIconAppearance (and the fake-active/custom-buff attach sites) for non-users. Same monotonic, scanned-once contract.
function ns.RescanThresholdTextFlag()
    if ns._cdmAnyThresholdText or ns._thresholdTextFlagScanned then return end
    if not EllesmereUIDB then return end
    ns._thresholdTextFlagScanned = true
    ns.ForEachSavedSettingsBlock(function(ss)
        if (tonumber(ss.thresholdSeconds) or 0) > 0 then
            ns._cdmAnyThresholdText = true
            return true
        end
    end)
    if not ns._cdmAnyThresholdText then
        local cas = ns.GetCustomActiveStates and ns.GetCustomActiveStates()
        if cas then
            for _, e in pairs(cas) do
                if type(e) == "table" and (tonumber(e.thresholdSeconds) or 0) > 0 then
                    ns._cdmAnyThresholdText = true
                    break
                end
            end
        end
    end
end

-- Custom Icon gate: set ns._cdmAnyCustomIcon once if any saved spell (any spec) has a
-- per-spell replacement icon. Skips the DecorateFrame re-stamp and the RefreshSpellTexture
-- post-hooks for non-users. Same monotonic, scanned-once contract; customIcon is never written to bar tiers.
function ns.RescanCustomIconFlag()
    if ns._cdmAnyCustomIcon or ns._customIconFlagScanned then return end
    if not EllesmereUIDB then return end
    ns._customIconFlagScanned = true
    ns.ForEachSavedSettingsBlock(function(ss)
        if type(ss.customIcon) == "number" and ss.customIcon > 0 then
            ns._cdmAnyCustomIcon = true
            return true
        end
    end)
end

-- Active State Glow gate: set ns._cdmAnyActiveGlow once if any saved spell (any spec) has
-- per-spell activeGlow set. Skips the buff ticker's active-glow integrity pass (safety net
-- that lights the glow when Blizzard skips the SetSwipeColor call that normally drives it) for non-users. Same monotonic, scanned-once contract.
function ns.RescanActiveGlowFlag()
    if ns._cdmAnyActiveGlow or ns._activeGlowFlagScanned then return end
    if not EllesmereUIDB then return end
    ns._activeGlowFlagScanned = true
    ns.ForEachSavedSettingsBlock(function(ss)
        if (tonumber(ss.activeGlow) or 0) > 0 then
            ns._cdmAnyActiveGlow = true
            return true
        end
    end)
end

-------------------------------------------------------------------------------
--  Spec helpers
--
--  Single source of truth: the live game API, cached on first read. Never nil during
--  normal operation -- transitions atomically old->new key inside ProcessSpecChange.
--  InvalidateSpecKey is for the early-login wakeFrame ONLY (before CDM setup completes),
--  never during spec change processing.
--
--  Returns nil when the spec API isn't ready (very early login); consumers MUST bail on nil rather than fall back to a stored value, so CDM never builds with a wrong/guessed spec.
-------------------------------------------------------------------------------
local _cachedSpecKey = nil

function ns.GetActiveSpecKey()
    if _cachedSpecKey then return _cachedSpecKey end
    local specIndex = GetSpecialization and GetSpecialization()
    if not specIndex or specIndex == 0 then return nil end
    local specID = select(1, C_SpecializationInfo.GetSpecializationInfo(specIndex))
    if not specID or specID == 0 then return nil end
    _cachedSpecKey = tostring(specID)
    return _cachedSpecKey
end

-- Early-login wakeFrame use only (before CDM setup completes); never called during spec change processing.
function ns.InvalidateSpecKey()
    _cachedSpecKey = nil
    ns._cachedSpecProfiles = nil
    ns._cdmStoreMemo = nil
end

-- Live spec key from the game API without touching the cache; nil if not ready.
local function ComputeLiveSpecKey()
    local specIndex = GetSpecialization and GetSpecialization()
    if not specIndex or specIndex == 0 then return nil end
    local specID = select(1, C_SpecializationInfo.GetSpecializationInfo(specIndex))
    if not specID or specID == 0 then return nil end
    return tostring(specID)
end
ns.ComputeLiveSpecKey = ComputeLiveSpecKey

-- Per-character identifier for legacy callers; no longer used for spec storage.
function ns.GetCharKey()
    local name = UnitName("player") or "Unknown"
    local realm = GetRealmName() or "Unknown"
    return name .. "-" .. realm
end

local function EnsureSpec(profile, key)
    profile.spec[key] = profile.spec[key] or { mappings = {}, selectedMapping = 1 }
    return profile.spec[key]
end

local function GetStore()
    local p = ECME.db.profile
    local specKey = ns.GetActiveSpecKey()
    return EnsureSpec(p, specKey)
end

local function EnsureMappings(store)
    if not store.mappings then store.mappings = {} end
    if #store.mappings == 0 then
        store.mappings[1] = {
            enabled = false, name = ns.DEFAULT_MAPPING_NAME,
            actionBar = 1, actionButton = 1, cdmSlot = 1,
            hideFromCDM = false, mode = "ACTIVE",
            glowStyle = 1, glowColor = { r = 1, g = 0.82, b = 0.1 },
        }
    end
    store.selectedMapping = tonumber(store.selectedMapping) or 1
    if store.selectedMapping < 1 then store.selectedMapping = 1 end
    if store.selectedMapping > #store.mappings then store.selectedMapping = #store.mappings end
    for _, m in ipairs(store.mappings) do
        if m.enabled == nil then m.enabled = true end
        if m.hideFromCDM == nil then m.hideFromCDM = false end
        if m.mode ~= "MISSING" then m.mode = "ACTIVE" end
        m.glowStyle = tonumber(m.glowStyle) or 1
        if not m.glowColor then m.glowColor = { r = 1, g = 0.82, b = 0.1 } end
        m.name = tostring(m.name or "")
        if type(m.actionBar) ~= "string" or not ns.CDM_BAR_ROOTS[m.actionBar] then
            m.actionBar = tonumber(m.actionBar) or 1
        end
        m.actionButton = tonumber(m.actionButton) or 1
        m.cdmSlot = tonumber(m.cdmSlot) or 1
    end
end

-- Expose for options
ns.GetStore = GetStore
ns.EnsureMappings = EnsureMappings

-------------------------------------------------------------------------------
--  Per-Spec Profile Helpers
--  Saves/restores spell lists, bar glows, and buff bars per specialization.
--  Bar structure, settings, and positions are shared across all specs.
-------------------------------------------------------------------------------
local MAIN_BAR_KEYS = { cooldowns = true, utility = true, buffs = true }

-- Ghost CD bar: hidden routing sink for CD/utility spells. "Removing" a spell routes it
-- here instead of deleting it, so every spell in Blizzard's viewer pool always has a route -- no allowSet filtering needed during collection.
local GHOST_CD_BAR_KEY = "__ghost_cd"
MAIN_BAR_KEYS[GHOST_CD_BAR_KEY] = true

-------------------------------------------------------------------------------
--  Resolve the best spellID from a CooldownViewerCooldownInfo struct.
--  Priority: overrideSpellID > first linkedSpellID > spellID. The base spellID field
--  can be a spec aura (e.g. 137007 "Unholy Death Knight") while the real tracked spell lives in linkedSpellIDs.
-------------------------------------------------------------------------------
local function ResolveInfoSpellID(info)
    if not info then return nil end
    local sid
    if info.overrideSpellID and info.overrideSpellID > 0 then
        sid = info.overrideSpellID
    else
        local linked = info.linkedSpellIDs
        if linked then
            for i = 1, #linked do
                if linked[i] and linked[i] > 0 then sid = linked[i]; break end
            end
        end
        if not sid and info.spellID and info.spellID > 0 then sid = info.spellID end
    end
    return sid
end

-------------------------------------------------------------------------------
--  Resolve the best spellID from a Blizzard CDM viewer child frame. For buff bars
--  cooldownInfo often holds the wrong spellID (spec aura, not the tracked buff); the
--  child frame knows the correct one via GetAuraSpellID/GetSpellID at runtime. Falls back
--  to ResolveInfoSpellID when those are unavailable. ONLY used in out-of-combat paths (snapshot, dropdown, reconcile).
-------------------------------------------------------------------------------
local function ResolveChildSpellID(child)
    if not child then return nil end
    -- Prefer the aura spellID (most accurate for buff viewers). Comparisons are pcall-wrapped:
    -- these methods can return SECRET numbers in combat, which cannot be compared with > 0.
    if child.GetAuraSpellID then
        local ok, auraID = pcall(child.GetAuraSpellID, child)
        if ok and auraID then
            local cmpOk, gt = pcall(function() return auraID > 0 end)
            if cmpOk and gt then return auraID end
        end
    end
    if child.GetSpellID then
        local ok, fid = pcall(child.GetSpellID, child)
        if ok and fid then
            local cmpOk, gt = pcall(function() return fid > 0 end)
            if cmpOk and gt then return fid end
        end
    end
    local cdID = child.cooldownID or (child.cooldownInfo and child.cooldownInfo.cooldownID)
    if cdID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
        return ResolveInfoSpellID(info)
    end
    return nil
end

-------------------------------------------------------------------------------
--  Set of currently known (learned) spellIDs across all CDM categories, via
--  GetCooldownViewerCategorySet(cat, false) (learned only), resolving each cdID to its base spellID.
-------------------------------------------------------------------------------
local function BuildAvailableSpellPool()
    local known = {}
    if not C_CooldownViewer or not C_CooldownViewer.GetCooldownViewerCategorySet then return known end
    for cat = 0, 3 do
        local knownIDs = C_CooldownViewer.GetCooldownViewerCategorySet(cat, false)
        if knownIDs then
            for _, cdID in ipairs(knownIDs) do
                local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
                if info then
                    local primarySid = ResolveInfoSpellID(info)
                    -- Store ALL related spell IDs so reconcile matches whether the bar stores
                    -- the base, override or a linked ID. Guard override-sourced IDs with
                    -- IsPlayerSpell: CDM info can report a stale overrideSpellID after the talent providing it is removed (e.g. Cleave/Whirlwind).
                    local staleOverride = info.overrideSpellID
                        and info.overrideSpellID > 0
                        and IsPlayerSpell
                        and not IsPlayerSpell(info.overrideSpellID)
                    if primarySid and primarySid > 0 then
                        if not (staleOverride and primarySid == info.overrideSpellID) then
                            known[primarySid] = true
                        end
                    end
                    if info.spellID and info.spellID > 0 then
                        known[info.spellID] = true
                    end
                    if info.overrideSpellID and info.overrideSpellID > 0
                       and not staleOverride then
                        known[info.overrideSpellID] = true
                    end
                    if info.linkedSpellIDs then
                        for _, lsid in ipairs(info.linkedSpellIDs) do
                            if lsid and lsid > 0 then
                                known[lsid] = true
                            end
                        end
                    end
                end
            end
        end
    end
    -- Fallback: the full CDM category set (cat, true) covers ALL class spells regardless of
    -- talents. Anything in it that passes IsPlayerSpell is known even if the viewer hasn't updated yet after a talent swap.
    local _IsPlayerSpell = IsPlayerSpell
    if _IsPlayerSpell then
        for cat = 0, 3 do
            local allIDs = C_CooldownViewer.GetCooldownViewerCategorySet(cat, true)
            if allIDs then
                for _, cdID in ipairs(allIDs) do
                    local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
                    if info then
                        local sid = ResolveInfoSpellID(info)
                        if sid and sid > 0 and not known[sid] and _IsPlayerSpell(sid) then
                            known[sid] = true
                        end
                        if info.spellID and info.spellID > 0 and not known[info.spellID] and _IsPlayerSpell(info.spellID) then
                            known[info.spellID] = true
                        end
                        if info.overrideSpellID and info.overrideSpellID > 0 and not known[info.overrideSpellID] and _IsPlayerSpell(info.overrideSpellID) then
                            known[info.overrideSpellID] = true
                        end
                    end
                end
            end
        end
    end
    return known
end

local DeepCopy = EllesmereUI.Lite.DeepCopy

-------------------------------------------------------------------------------
--  Cached bar sizes -- cosmetic hint for pre-sizing frames on login so anchored
--  elements don't jump. Zero impact on spell logic or icons. Stored at
--  EllesmereUIDB.cdmCachedBarSizes[charKey][specKey][barKey] = count
-------------------------------------------------------------------------------
function ns.SaveCachedBarSizes()
    if not EllesmereUIDB then return end
    local charKey = ns.GetCharKey()
    local specKey = ns.GetActiveSpecKey()
    if not specKey or specKey == "0" then return end
    if not EllesmereUIDB.cdmCachedBarSizes then EllesmereUIDB.cdmCachedBarSizes = {} end
    if not EllesmereUIDB.cdmCachedBarSizes[charKey] then EllesmereUIDB.cdmCachedBarSizes[charKey] = {} end
    local frames = ns.cdmBarFrames
    local iconsByKey = ns.cdmBarIcons
    if not frames or not iconsByKey then return end
    local counts = {}
    for key, frame in pairs(frames) do
        local icons = iconsByKey[key]
        if icons then
            local vis = 0
            for _, icon in ipairs(icons) do
                if icon:IsShown() then vis = vis + 1 end
            end
            if vis > 0 then counts[key] = vis end
        end
    end
    EllesmereUIDB.cdmCachedBarSizes[charKey][specKey] = counts
end

--- Save the current spec's non-spell per-spec data. Spell data lives directly in the global store via ns.GetBarSpellData() and never needs copying.
local function SaveCurrentSpecProfile()
    local p = ECME.db.profile
    local specKey = ns.GetActiveSpecKey()
    if not specKey or specKey == "0" then return end
    local specProfiles = SpellStore.GetSpecProfiles()
    if not specProfiles[specKey] then specProfiles[specKey] = { barSpells = {} } end
    local prof = specProfiles[specKey]

    -- Bar Glows and Tracked Buff Bars live in specProfiles[specKey]; GetBarGlows()/GetTrackedBuffBars() read/write there directly, so nothing extra to copy here.

    -- Snapshot visible icon counts for pre-sizing on next login
    ns.SaveCachedBarSizes()
end

--- Spec change processing. NEVER a fixed wall-clock delay: Blizzard's viewer pools repopulate
--- at unpredictable times after a spec swap. SPELLS_CHANGED is the sole trigger -- fires for
--- manual and LFG auto-swaps and guarantees spell data/viewer pools are fully populated.
--- CheckSpecChange compares the live spec key to the cached one on every SPELLS_CHANGED and runs
--- a full talent_reconcile rebuild on a difference. The cached key swaps atomically BEFORE the rebuild so GetBarSpellData always has a valid key. No nil window.
local function ProcessSpecChange(newSpecKey)
    if not newSpecKey then return end
    ns._spellOrderDirty = true  -- force spell order cache rebuild

    -- Atomic swap: write the new key BEFORE rebuilding so every GetBarSpellData call during the rebuild reads the correct spec.
    _cachedSpecKey = newSpecKey
    ns._cachedSpecProfiles = nil
    ns._cdmStoreMemo = nil

    -- Suppress the _ECME_Apply rebuild the profile system fires via RefreshAllAddons: the talent_reconcile rebuild below is strictly stronger.
    ns._specChangeJustRan = true
    -- Time-box stamp for the justRan consume in _ECME_Apply: suppression is honored only while
    -- the spec change is recent, so a flag left armed by a non-consuming path fails OPEN (extra rebuild) instead of eating a needed one.
    ns._specChangeAt = GetTime()

    ns._pendingApplyOnReanchor = true

    -- Full wipe + rebuild: talent_reconcile takes FullCDMRebuild's isFullWipe branch (wipes
    -- icon arrays, _prevIconRefs/_prevVisibleCount, anchor state in _hookFrameData, all FC
    -- caches on viewer pool frames, then a direct synchronous CollectAndReanchor); cdmBarIcons
    -- holds the new spec's icons after this returns. Placeholder injection is HELD across the
    -- synchronous pass: on a spec switch it runs BEFORE the per-spec profile swap, so
    -- barDataByKey still carries the OLD spec's Always-Show/Keep-in-Place flags and injecting
    -- would flash placeholders the new spec never asked for. The following reanchor (profile_import, or the next buff event) re-injects correctly from the active profile.
    if ns.FullCDMRebuild then
        ns._cdmSpecRebuildStale = true
        ns.FullCDMRebuild("talent_reconcile")
        ns._cdmSpecRebuildStale = false
    end

    -- Signal the profile system that CDM's spec rebuild is complete: clears _specProfileSwitching and re-applies width/height matches.
    if EllesmereUI and EllesmereUI.OnSpecSwitchComplete then
        EllesmereUI.OnSpecSwitchComplete()
    end

    -- Refresh the CDM options pages now that _cachedSpecKey is swapped: their own
    -- PLAYER_SPECIALIZATION_CHANGED watcher can fire before SPELLS_CHANGED, so driving it
    -- here guarantees they rebuild against the new spec instead of keeping the old spec's selected bar.
    if ns.OnTBBSpecChanged then ns.OnTBBSpecChanged() end
end
ns.ProcessSpecChange = ProcessSpecChange

-- Compare live spec to cached; if different, process the change. Called exclusively from
-- SPELLS_CHANGED. Idempotent: after ProcessSpecChange the cached key matches live and subsequent calls are no-ops.
local function CheckSpecChange()
    local liveKey = ComputeLiveSpecKey()
    if liveKey and liveKey ~= _cachedSpecKey then
        ProcessSpecChange(liveKey)
    end
end
ns.CheckSpecChange = CheckSpecChange

-------------------------------------------------------------------------------
--  CDM Bar Roots
-------------------------------------------------------------------------------
ns.CDM_BAR_ROOTS = {
    CDM_COOLDOWN = "EssentialCooldownViewer",
    CDM_UTILITY  = "UtilityCooldownViewer",
}

-------------------------------------------------------------------------------
--  Action Button Lookup (supports Blizzard and popular bar addons)
-------------------------------------------------------------------------------
local blizzBarNames = {
    [1] = "ActionButton",
    [2] = "MultiBarBottomLeftButton",
    [3] = "MultiBarBottomRightButton",
    [4] = "MultiBarRightButton",
    [5] = "MultiBarLeftButton",
    [6] = "MultiBar5Button",
    [7] = "MultiBar6Button",
    [8] = "MultiBar7Button",
}

-- EAB slot offsets match BAR_SLOT_OFFSETS in EllesmereUIActionBars.lua
local eabSlotOffsets = { 0, 60, 48, 24, 36, 144, 156, 168 }

local actionButtonCache = {}

local function GetActionButton(bar, i)
    bar = bar or 1
    local cacheKey = bar * 100 + i
    if actionButtonCache[cacheKey] then return actionButtonCache[cacheKey] end
    -- EABButton first (EllesmereUIActionBars creates these when Blizzard buttons are unavailable, e.g. another addon hid ActionButton1-12), then Blizzard.
    local eabSlot = (eabSlotOffsets[bar] or 0) + i
    local btn = _G["EABButton" .. eabSlot]
    if not btn then
        local prefix = blizzBarNames[bar]
        btn = prefix and _G[prefix .. i]
    end
    if btn then actionButtonCache[cacheKey] = btn end
    return btn
end

-------------------------------------------------------------------------------
--  CDM Slot Helpers
-------------------------------------------------------------------------------
local function FindCooldown(frame)
    if not frame then return end
    local cd = frame.cooldown or frame.Cooldown
    if cd then return cd end
    for i = 1, frame:GetNumChildren() do
        local child = select(i, frame:GetChildren())
        if child and child.GetObjectType and child:GetObjectType() == "Cooldown" then
            return child
        end
    end
end

local function SlotSortComparator(a, b)
    local ax, ay = a:GetCenter()
    local bx, by = b:GetCenter()
    ax, ay, bx, by = ax or 0, ay or 0, bx or 0, by or 0
    if math.abs(ay - by) > 2 then return ay > by end
    return ax < bx
end

local cachedSlots, cacheTime = nil, 0

local function GetSortedSlots(forceRefresh)
    local now = GetTime()
    if not forceRefresh and cachedSlots and (now - cacheTime) < 0.5 then
        return cachedSlots
    end
    local root = _G.BuffIconCooldownViewer
    if not root or not root.GetChildren then cachedSlots = nil; return nil end
    local slots = {}
    for i = 1, root:GetNumChildren() do
        local c = select(i, root:GetChildren())
        if c and c.GetCenter and FindCooldown(c) then
            slots[#slots + 1] = c
        end
    end
    if #slots == 0 then cachedSlots = nil; return nil end
    table.sort(slots, SlotSortComparator)
    cachedSlots = slots
    cacheTime = now
    return slots
end

local function GetAllCDMSlots(root)
    if not root or not root.GetChildren then return {} end
    local slots = {}
    for i = 1, root:GetNumChildren() do
        local c = select(i, root:GetChildren())
        if c and c.GetWidth and c:GetWidth() > 5 then
            slots[#slots + 1] = c
        end
    end
    return slots
end

local function GetCDMBarButton(barKey, slotIndex)
    local rootName = ns.CDM_BAR_ROOTS[barKey]
    if not rootName then return nil end
    local root = _G[rootName]
    if not root or not root.GetChildren then return nil end
    local slots = {}
    for i = 1, root:GetNumChildren() do
        local c = select(i, root:GetChildren())
        if c and c.GetWidth and c:GetWidth() > 5 then
            slots[#slots + 1] = c
        end
    end
    if #slots == 0 then return nil end
    table.sort(slots, SlotSortComparator)
    return slots[slotIndex]
end

local function GetTargetButton(actionBar, actionButtonIndex)
    if type(actionBar) == "string" and ns.CDM_BAR_ROOTS[actionBar] then
        return GetCDMBarButton(actionBar, actionButtonIndex)
    end
    return GetActionButton(tonumber(actionBar) or 1, actionButtonIndex)
end

-------------------------------------------------------------------------------
--  CDM Look: Border Reskinning
-------------------------------------------------------------------------------
local cdmBorderFrames = {}

local function GetOrCreateCDMBorder(slot)
    local function SafeEq(a, b)
        return a == b
    end

    if cdmBorderFrames[slot] then return cdmBorderFrames[slot] end

    slot.__ECMEHidden   = slot.__ECMEHidden or {}
    slot.__ECMEIcon     = slot.__ECMEIcon or nil
    slot.__ECMECooldown = slot.__ECMECooldown or nil

    if not slot.__ECMEScanned then
        slot.__ECMEHidden = {}
        slot.__ECMEIcon = nil
        slot.__ECMECooldown = nil

        for ri = 1, slot:GetNumRegions() do
            local region = select(ri, slot:GetRegions())
            if region and region.GetObjectType then
                local objType = region:GetObjectType()
                if objType == "MaskTexture" then
                    slot.__ECMEHidden[#slot.__ECMEHidden + 1] = region
                elseif objType == "Texture" then
                    local ok, rawLayer = pcall(region.GetDrawLayer, region)
                    if ok and rawLayer ~= nil then
                        local okB, isBorder   = pcall(SafeEq, rawLayer, "BORDER")
                        local okO, isOverlay  = pcall(SafeEq, rawLayer, "OVERLAY")
                        local okA, isArtwork  = pcall(SafeEq, rawLayer, "ARTWORK")
                        local okG, isBG       = pcall(SafeEq, rawLayer, "BACKGROUND")
                        if (okB and isBorder) or (okO and isOverlay) then
                            slot.__ECMEHidden[#slot.__ECMEHidden + 1] = region
                        elseif not slot.__ECMEIcon and ((okA and isArtwork) or (okG and isBG)) then
                            slot.__ECMEIcon = region
                        end
                    end
                end
            end
        end

        for ci = 1, slot:GetNumChildren() do
            local child = select(ci, slot:GetChildren())
            if child and child.GetObjectType then
                local objType = child:GetObjectType()
                if objType == "MaskTexture" then
                    slot.__ECMEHidden[#slot.__ECMEHidden + 1] = child
                elseif objType == "Cooldown" then
                    slot.__ECMECooldown = child
                    for k = 1, child:GetNumChildren() do
                        local cdChild = select(k, child:GetChildren())
                        if cdChild and cdChild.GetObjectType and cdChild:GetObjectType() == "MaskTexture" then
                            slot.__ECMEHidden[#slot.__ECMEHidden + 1] = cdChild
                        end
                    end
                    for k = 1, child:GetNumRegions() do
                        local cdRegion = select(k, child:GetRegions())
                        if cdRegion and cdRegion.GetObjectType and cdRegion:GetObjectType() == "MaskTexture" then
                            slot.__ECMEHidden[#slot.__ECMEHidden + 1] = cdRegion
                        end
                    end
                end
            end
        end
        slot.__ECMEScanned = true
    end

    local iconSize = slot.__ECMEIcon and slot.__ECMEIcon:GetWidth() or slot:GetWidth() or 35
    local edgeSize = iconSize < 35 and 2 or 1

    local border = CreateFrame("Frame", nil, slot)
    if slot.__ECMEIcon then border:SetAllPoints(slot.__ECMEIcon) else border:SetAllPoints() end
    border:SetFrameLevel(slot:GetFrameLevel() + 5)
    EllesmereUI.PP.CreateBorder(border, 0, 0, 0, 1, edgeSize)

    cdmBorderFrames[slot] = border
    return border
end

local CDM_ROOT_NAMES = {
    "BuffIconCooldownViewer", "BuffBarCooldownViewer",
    "EssentialCooldownViewer", "UtilityCooldownViewer",
}

local function UpdateAllCDMBorders()
    local reskin = ECME.db and ECME.db.profile.reskinBorders
    local crop = 0.06

    for _, rootName in ipairs(CDM_ROOT_NAMES) do
        local root = _G[rootName]
        if root then
            for _, slot in ipairs(GetAllCDMSlots(root)) do
                local border = GetOrCreateCDMBorder(slot)
                if reskin then
                    border:Show()
                    if slot.__ECMEIcon then slot.__ECMEIcon:SetTexCoord(crop, 1 - crop, crop, 1 - crop) end
                    if slot.__ECMECooldown then
                        slot.__ECMECooldown:SetSwipeTexture("Interface\\AddOns\\EllesmereUI\\media\\white-square.png")
                    end
                    for _, h in ipairs(slot.__ECMEHidden) do
                        if h and h.Hide then h:Hide() end
                    end
                else
                    border:Hide()
                    if slot.__ECMEIcon then slot.__ECMEIcon:SetTexCoord(0, 1, 0, 1) end
                    if slot.__ECMECooldown then
                        slot.__ECMECooldown:SetSwipeTexture("Interface\\Cooldown\\cooldown-bling")
                    end
                    for _, h in ipairs(slot.__ECMEHidden) do
                        if h and h.Show then h:Show() end
                    end
                end
            end
        end
    end
end
ns.UpdateAllCDMBorders = UpdateAllCDMBorders

-------------------------------------------------------------------------------
--  Native Glow System -- engines provided by shared EllesmereUI_Glows.lua
--  CDM keeps its own GLOW_STYLES (different scale values) and Start/Stop
--  wrappers that handle CDM-specific shape glow (icon masks/borders).
-------------------------------------------------------------------------------
local _G_Glows = EllesmereUI.Glows
local GLOW_STYLES = {
    { name = "Pixel Glow",           procedural = true },
    { name = "Shape Glow",           shapeGlow = true },
    { name = "Action Button Glow",   buttonGlow = true },
    { name = "Auto-Cast Shine",      autocast = true },
    { name = "GCD",                  atlas = "RotationHelper_Ants_Flipbook", texPadding = 1.6 },
    { name = "Modern WoW Glow",      atlas = "UI-HUD-ActionBar-Proc-Loop-Flipbook", texPadding = 1.4 },
    { name = "Classic WoW Glow",     texture = "Interface\\SpellActivationOverlay\\IconAlertAnts",
      rows = 5, columns = 5, frames = 25, duration = 0.3, frameW = 48, frameH = 48, texPadding = 1.25 },
}
ns.GLOW_STYLES = GLOW_STYLES

-------------------------------------------------------------------------------
--  Cross-surface Pandemic Glow sync (CDM bars + Nameplates) -- BEST EFFORT
--  Glow styles are identified by NAME, never raw index: CDM, Nameplates and the shared
--  engine order their lists differently, so the same integer means a different style per
--  surface. Each surface advertises a different subset; an unrenderable style is coerced
--  to the nearest supported one and the COERCED value is stored, so dropdown name and preview always match what's displayed.
--    - CDM icon bars  : full set + "Blizzard Default" (-1 = Blizzard's own glow)
--    - Nameplate icons: same set MINUS "Blizzard Default" (no native glow there)
-------------------------------------------------------------------------------
local PG_BLIZZ_NAME = "Blizzard Default"

-- CDM icon-bar style index <-> canonical name
local function PG_CdmNameFromIndex(idx)
    if idx == -1 then return PG_BLIZZ_NAME end
    local e = GLOW_STYLES[idx]
    return (e and e.name) or "Pixel Glow"
end
local function PG_CdmIndexFromName(name)
    if name == PG_BLIZZ_NAME then return -1 end
    for i = 1, #GLOW_STYLES do
        if GLOW_STYLES[i].name == name then return i end
    end
    return 1  -- Pixel Glow
end

-- Nameplate style index <-> canonical name (no Blizzard Default; coerce to Pixel)
local function PG_NameplateNameFromIndex(idx)
    local list = EllesmereUI.NameplatePandemicGlowStyles
    local e = list and list[idx]
    return (e and e.name) or "Pixel Glow"
end
local function PG_NameplateIndexFromName(name)
    local list = EllesmereUI.NameplatePandemicGlowStyles
    if name and name ~= PG_BLIZZ_NAME and list then
        for i = 1, #list do
            if list[i].name == name then return i end
        end
    end
    return 1  -- Pixel Glow (covers Blizzard Default / anything unsupported)
end

-- Tracked Buff Bars render as rectangles: only Pixel(1)/Auto-Cast(4) work there.
local function PG_TbbIndexFromName(name)
    return (name == "Auto-Cast Shine") and 4 or 1
end
-- A TBB may STORE a non-renderable style (e.g. -1 default) but DISPLAYS it as Pixel; compare what's shown, not what's stored.
local function PG_TbbEffectiveStyle(dst)
    return (dst.pandemicGlowStyle == 4) and 4 or 1
end

local function PG_GetNPProfile()
    if not EllesmereUIDB or not EllesmereUIDB.profiles then return nil end
    local pName = EllesmereUIDB.activeProfile or "Default"
    local prof = EllesmereUIDB.profiles[pName]
    return prof and prof.addons and prof.addons.EllesmereUINameplates
end

-- Write a canonical payload into a destination, coercing the style through the destination's own name->index resolver (so the stored index is renderable).
local function PG_Write(dst, payload, indexFromName)
    dst.pandemicGlow          = payload.on
    dst.pandemicGlowStyle     = indexFromName(payload.styleName or "Pixel Glow")
    dst.pandemicGlowColor     = payload.color and CopyTable(payload.color) or nil
    dst.pandemicGlowLines     = payload.lines
    dst.pandemicGlowThickness = payload.thickness
    dst.pandemicGlowSpeed     = payload.speed
    dst.pandemicGlowBackground = payload.background and true or nil
    dst.pandemicGlowBackgroundColor = payload.backgroundColor and CopyTable(payload.backgroundColor) or nil
end

-- True when dst already displays what PG_Write(dst, payload) would store (when both are off
-- nothing is shown, so leftover style/color is irrelevant). actualStyleFn lets a surface report
-- its EFFECTIVE (displayed) style when that differs from the raw stored value (e.g. rectangle TBBs); defaults to stored.
local function PG_Matches(dst, payload, indexFromName, actualStyleFn)
    if (dst.pandemicGlow or false) ~= (payload.on or false) then return false end
    if not payload.on then return true end
    local actual = actualStyleFn and actualStyleFn(dst) or (dst.pandemicGlowStyle or 1)
    if actual ~= indexFromName(payload.styleName or "Pixel Glow") then return false end
    local dc = dst.pandemicGlowColor or {}
    local pc = payload.color or {}
    if (dc.r or 1) ~= (pc.r or 1) or (dc.g or 1) ~= (pc.g or 1) or (dc.b or 0) ~= (pc.b or 0) then return false end
    if (dst.pandemicGlowLines or 8) ~= (payload.lines or 8) then return false end
    if (dst.pandemicGlowThickness or 2) ~= (payload.thickness or 2) then return false end
    if (dst.pandemicGlowSpeed or 4) ~= (payload.speed or 4) then return false end
    if (dst.pandemicGlowBackground == true) ~= (payload.background == true) then return false end
    if payload.background then
        local dc = dst.pandemicGlowBackgroundColor or {}
        local pc = payload.backgroundColor or {}
        if (dc.r or 0) ~= (pc.r or 0) or (dc.g or 0) ~= (pc.g or 0) or (dc.b or 0) ~= (pc.b or 0) then return false end
    end
    return true
end

-- Build a canonical payload from a CDM icon bar.
function EllesmereUI.PandemicPayloadFromCdmBar(bd)
    return {
        on        = bd.pandemicGlow == true,
        styleName = PG_CdmNameFromIndex(bd.pandemicGlowStyle or 1),
        color     = bd.pandemicGlowColor,
        lines     = bd.pandemicGlowLines,
        thickness = bd.pandemicGlowThickness,
        speed     = bd.pandemicGlowSpeed,
        background = bd.pandemicGlowBackground == true,
        backgroundColor = bd.pandemicGlowBackgroundColor,
    }
end

-- Payload from a rectangle bar (Tracked Buff Bar): rectangles only render Pixel/Auto-Cast, so
-- report the EFFECTIVE displayed style, not the raw stored one (which may be e.g. -1 "Blizzard Default", shown there as Pixel).
function EllesmereUI.PandemicPayloadFromRectBar(bd)
    return {
        on        = bd.pandemicGlow == true,
        styleName = (bd.pandemicGlowStyle == 4) and "Auto-Cast Shine" or "Pixel Glow",
        color     = bd.pandemicGlowColor,
        lines     = bd.pandemicGlowLines,
        thickness = bd.pandemicGlowThickness,
        speed     = bd.pandemicGlowSpeed,
        background = bd.pandemicGlowBackground == true,
        backgroundColor = bd.pandemicGlowBackgroundColor,
    }
end

-- Build a payload from the nameplate profile.
function EllesmereUI.PandemicPayloadFromNameplate(np)
    return {
        on        = np.pandemicGlow == true,
        styleName = PG_NameplateNameFromIndex(np.pandemicGlowStyle or 1),
        color     = np.pandemicGlowColor,
        lines     = np.pandemicGlowLines,
        thickness = np.pandemicGlowThickness,
        speed     = np.pandemicGlowSpeed,
        background = np.pandemicGlowBackground == true,
        backgroundColor = np.pandemicGlowBackgroundColor,
    }
end

-- Apply a canonical payload to all sync surfaces (CDM icon bars, Tracked Buff Bars,
-- Nameplates), best-effort. opts.skipCdmKey/opts.skipNameplates exclude the source surface; opts.skipTbbBar excludes one TBB (its source bar table).
function EllesmereUI.ApplyPandemicGlowToAll(payload, opts)
    opts = opts or {}
    if not opts.skipNameplates then
        local np = PG_GetNPProfile()
        if np and EllesmereUI.NameplatePandemicGlowStyles then
            PG_Write(np, payload, PG_NameplateIndexFromName)
        end
    end
    local p = ECME.db and ECME.db.profile
    if p and p.cdmBars and p.cdmBars.bars then
        for _, b in ipairs(p.cdmBars.bars) do
            if b.key ~= opts.skipCdmKey and not b.isGhostBar and b.barType ~= "custom_buff" then
                PG_Write(b, payload, PG_CdmIndexFromName)
            end
        end
    end
    -- Tracked Buff Bars (active spec) -- rectangles, so style coerces to Pixel/Auto-Cast.
    local tbb = ns.GetTrackedBuffBars and ns.GetTrackedBuffBars()
    if tbb and tbb.bars then
        for _, b in ipairs(tbb.bars) do
            if b ~= opts.skipTbbBar then
                PG_Write(b, payload, PG_TbbIndexFromName)
            end
        end
    end
    if ns.BuildAllCDMBars then ns.BuildAllCDMBars() end
    if ns.BuildTrackedBuffBars then ns.BuildTrackedBuffBars() end
    if _G._ENP_RefreshAllSettings then _G._ENP_RefreshAllSettings() end
end

-- True when every (non-skipped) surface already matches the payload.
function EllesmereUI.IsPandemicGlowSyncedToAll(payload, opts)
    opts = opts or {}
    if not opts.skipNameplates then
        local np = PG_GetNPProfile()
        if np and EllesmereUI.NameplatePandemicGlowStyles
           and not PG_Matches(np, payload, PG_NameplateIndexFromName) then
            return false
        end
    end
    local p = ECME.db and ECME.db.profile
    if p and p.cdmBars and p.cdmBars.bars then
        for _, b in ipairs(p.cdmBars.bars) do
            if b.key ~= opts.skipCdmKey and not b.isGhostBar and b.barType ~= "custom_buff"
               and not PG_Matches(b, payload, PG_CdmIndexFromName) then
                return false
            end
        end
    end
    local tbb = ns.GetTrackedBuffBars and ns.GetTrackedBuffBars()
    if tbb and tbb.bars then
        for _, b in ipairs(tbb.bars) do
            if b ~= opts.skipTbbBar
               and not PG_Matches(b, payload, PG_TbbIndexFromName, PG_TbbEffectiveStyle) then
                return false
            end
        end
    end
    return true
end

StartNativeGlow = function(overlay, style, cr, cg, cb, opts)
    if not overlay then return end
    local styleIdx = tonumber(style) or 1
    if styleIdx < 1 or styleIdx > #GLOW_STYLES then styleIdx = 1 end
    local entry = GLOW_STYLES[styleIdx]

    _G_Glows.StopAllGlows(overlay)

    local parent = overlay:GetParent()
    if not parent then return end
    local pW, pH = parent:GetWidth(), parent:GetHeight()
    if pW < 5 then pW = 36 end
    if pH < 5 then pH = 36 end
    local noColor = (cr == nil)
    if noColor then cr, cg, cb = 1.0, 0.788, 0.137 end
    cr = cr or 1; cg = cg or 1; cb = cb or 1

    if entry.shapeGlow then
        -- CDM-specific: read shape mask/border from the icon frame
        local icon = parent
        local ifc2 = _ecmeFC[icon]
        local shape = (ifc2 and ifc2.shapeApplied) and (ifc2 and ifc2.shapeName) or nil
        local shapeMask = ifc2 and ifc2.shapeMask
        -- No custom shape (none/cropped) = sharp-cornered square: use the square glow texture so
        -- the pulse hugs the icon edges instead of filling a solid additive block (no live mask
        -- object here, so the texture alone defines the shape). Skip the shape border overlay -- the icon keeps its own border, so it would just add a stray line.
        local noShape = not shape
        if noShape then shape = "square"; shapeMask = nil end
        local maskPath   = CDM_SHAPES.masks[shape]
        local borderPath = (not noShape) and CDM_SHAPES.borders[shape] or nil
        _G_Glows.StartShapeGlow(overlay, math.min(pW, pH), cr, cg, cb, 1.20, {
            maskPath   = maskPath,
            borderPath = borderPath,
            shapeMask  = shapeMask,
        })
    elseif entry.procedural then
        -- Pixel Glow params. Pandemic glow passes explicit opts; per-button glows (active-state,
        -- CD-ready, bar glows) pass none, so resolve the owning CD/utility bar's settings, defaulting for action-bar overlays and bars that never set the values.
        local N, th, period, bgR, bgG, bgB, bgA
        if opts then
            N = opts.N or 8; th = opts.th or 2; period = opts.period or 4
            if opts.bg then
                bgR, bgG, bgB, bgA = opts.bg.r or 0, opts.bg.g or 0, opts.bg.b or 0, opts.bg.a or 1
            end
        else
            local pfc = _ecmeFC[parent]
            local pbd = pfc and pfc.barKey and ns.GetBarData and ns.GetBarData(pfc.barKey)
            N = (pbd and pbd.pixelGlowLines) or 8
            th = (pbd and pbd.pixelGlowThickness) or 2
            period = (pbd and pbd.pixelGlowSpeed) or 4
            if pbd and pbd.pixelGlowBackground then
                bgR, bgG, bgB, bgA = pbd.pixelGlowBackgroundR or 0, pbd.pixelGlowBackgroundG or 0, pbd.pixelGlowBackgroundB or 0, 1
            end
        end
        local lineLen = math.floor((pW + pH) * (2 / N - 0.1))
        lineLen = math.min(lineLen, math.min(pW, pH))
        if lineLen < 1 then lineLen = 1 end
        _G_Glows.StartProceduralAnts(overlay, N, th, period, lineLen, cr, cg, cb, pW, pH, bgR, bgG, bgB, bgA)
    elseif entry.buttonGlow then
        _G_Glows.StartButtonGlow(overlay, pW, cr, cg, cb, nil, pH)
    elseif entry.autocast then
        _G_Glows.StartAutoCastShine(overlay, pW, cr, cg, cb, 1.0, pH)
    else
        if noColor then cr, cg, cb = nil, nil, nil end
        _G_Glows.StartFlipBookGlow(overlay, pW, entry, cr, cg, cb, pH)
    end

    overlay._glowActive = true
    overlay:SetAlpha(1)
    -- NEVER Show()/Hide() -- the overlay is always shown (created in DecorateFrame).
    -- Toggling visibility on a child of a Blizzard viewer frame triggers Layout hooks and causes position cascades.
end

StopNativeGlow = function(overlay)
    if not overlay then return end
    _G_Glows.StopAllGlows(overlay)
    overlay._glowActive = false
    overlay:SetAlpha(0)
    -- No Hide() -- just alpha 0. Same reason as above.
end
ns.StartNativeGlow = StartNativeGlow
ns.StopNativeGlow = StopNativeGlow

-- Our bar frames (keyed by bar key)
local cdmBarFrames = {}
-- Icon frames per bar (keyed by bar key, array of icon frames)
local cdmBarIcons = {}
-- Fast barData lookup by key (rebuilt in BuildAllCDMBars, avoids linear scan per tick)
local barDataByKey = {}

-- Claim generation: bumped at the end of every CollectAndReanchor pass and at BuildAllCDMBars'
-- head, i.e. whenever the cdmBarIcons claim set can change. The proc-alert child map below rebuilds lazily against it.
ns._cdmClaimGen = 0
-- Resolution generation: bumped whenever spell resolution INPUTS change (SPELLS_CHANGED
-- talent/spec churn, live SPELL_OVERRIDE_UPDATED flips, rebuilds). cooldownID-keyed resolution memos key their validity on it.
ns._cdmResGen = 0

-- Shown-alpha for cd-state/fake-active restore paths: EffectiveBarAlpha, except 0 while the
-- icon's bar is visibility-hidden -- painting EffectiveBarAlpha directly would resurrect icons
-- on visibility-hidden bars (any cooldown/aura flip shows them until the next visibility pass).
-- Overflow-diverted frames follow the bar they are painted on (same rule as the fake-active engine's FrameBaseAlpha, which routes through here).
local function IconShownAlpha(fc, barData)
    local bk = fc and (fc._overflowLayoutBar or fc.barKey)
    local bf = bk and cdmBarFrames[bk]
    if bf and bf._visHidden then return 0 end
    return EffectiveBarAlpha(barData or (bk and barDataByKey[bk]))
end
ns.IconShownAlpha = IconShownAlpha

-- Expose our CDM bar frames so the glow system can reference them
ns.GetCDMBarFrame = function(barKey)
    return cdmBarFrames[barKey]
end
-- Global accessor for cross-addon frame lookups
_G._ECME_GetBarFrame = function(barKey)
    return cdmBarFrames[barKey]
end
-- Global accessor: apply a spec profile to the live bars (profile import). All consumers
-- read spell data from the global store, so this only needs to trigger a rebuild against the (now-active) spec.
_G._ECME_LoadSpecProfile = function(specKey)
    ns.FullCDMRebuild("profile_import")
end
-- Global accessor: get the current spec key string (e.g. "250"), or nil if the spec API isn't ready yet.
_G._ECME_GetCurrentSpecKey = function()
    return ns.GetActiveSpecKey()
end
-- Global accessor: set of all spellIDs in the user's CDM viewer (all categories, displayed + known). Profile import uses it to filter out spells the importing user does not have.
_G._ECME_GetCDMSpellSet = function()
    return BuildAvailableSpellPool()
end
ns.GetCDMBarIcons = function(barKey)
    return cdmBarIcons[barKey]
end

-------------------------------------------------------------------------------
--  Proc Glow System: hooks Blizzard's SpellAlertManager to show proc glows
--  on our CDM icons when Blizzard fires ShowAlert/HideAlert on CDM children.
--  Custom bars use SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE events instead.
-------------------------------------------------------------------------------
local PROC_GLOW_STYLE = 6  -- "Modern WoW Glow" flipbook

-- Reverse lookup: Blizzard CDM viewer frame name -> our bar key
local _blizzViewerToBarKey = {
    EssentialCooldownViewer = "cooldowns",
    UtilityCooldownViewer   = "utility",
    BuffIconCooldownViewer  = "buffs",
}

-- Walk up from a frame to find which Blizzard CDM viewer it belongs to; also handles reparented frames (hook system) via the _barKey field.
local function GetBarKeyForBlizzChild(frame)
    -- Fast path: barKey set by the hook system (external cache) or CDM frame
    local fc = _ecmeFC[frame]
    if (fc and fc.barKey) or frame._barKey then return (fc and fc.barKey) or frame._barKey, frame end
    local current = frame
    while current do
        local parent = current:GetParent()
        if not parent then return nil end
        -- Parent one of our CDM bar containers? (external cache or direct)
        local pfc = _ecmeFC[parent]
        if (pfc and pfc.barKey) or parent._barKey then return (pfc and pfc.barKey) or parent._barKey, current end
        local name = parent.GetName and parent:GetName()
        if name and _blizzViewerToBarKey[name] then
            return _blizzViewerToBarKey[name], current
        end
        current = parent
    end
    return nil
end

local ResolveBlizzChildSpellID  -- forward-declare (defined below)

-- Find our icon mirroring a given Blizzard CDM child. In hook mode the icon IS the Blizzard
-- child (identity check); falls back to spellID + override matching for proc glows on transformed spells.
local function FindOurIconForBlizzChild(barKey, blizzChild)
    -- O(1) common case: in hook mode our "icon" IS the claimed Blizzard child. Membership map
    -- (child -> claimed barKey) rebuilt lazily whenever the claim generation moves; between passes
    -- the claim set is stable. Weak keys so released viewer children never pin. A miss falls through to the scans below, so staleness can only cost the fast path, never invent a claim.
    local m = ns._cdmChildClaimMap
    if not m or m.gen ~= ns._cdmClaimGen then
        m = setmetatable({ gen = ns._cdmClaimGen }, { __mode = "k" })
        for bk, list in pairs(cdmBarIcons) do
            for i = 1, #list do m[list[i]] = bk end
        end
        ns._cdmChildClaimMap = m
    end
    if m[blizzChild] == barKey then return blizzChild end
    local icons = cdmBarIcons[barKey]
    if not icons then return nil end
    for _, icon in ipairs(icons) do
        local iifc = _ecmeFC[icon]
        local bc = iifc and iifc.blizzChild
        if icon == blizzChild or bc == blizzChild then return icon end
    end
    -- Fallback: match by spellID (covers override spells like HST -> Storm Stream)
    local alertSid, alertBase = ResolveBlizzChildSpellID(blizzChild)
    if alertSid then
        for _, icon in ipairs(icons) do
            local ifc = _ecmeFC[icon]
            local isid = ifc and ifc.spellID
            -- Second compare: the alert child's cooldownInfo carries its BASE id, so an icon
            -- assigned the base of a transformed spell matches on a plain field compare -- no per-icon API translation.
            if isid == alertSid or (alertBase and isid == alertBase) then return icon end
        end
        -- Override mapping (base <-> override). Last resort: only reachable when the icon's assigned id and the alert's base id differ yet still override-resolve to the alert spell.
        for _, icon in ipairs(icons) do
            local ifc = _ecmeFC[icon]
            local iconSid = ifc and ifc.spellID
            if iconSid and C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                local ovr = C_SpellBook.FindSpellOverrideByID(iconSid)
                if ovr and ovr == alertSid then return icon end
            end
        end
    end
    return nil
end

-- Resolve spellID from a Blizzard CDM child (IsSpellOverlayed guard, proc glow matching).
-- Returns (resolvedSid, baseSid). cooldownID-keyed memo: the cdID -> spell mapping only moves
-- on resolution edges (talent churn, live override flips), all of which bump ns._cdmResGen and
-- drop the memo wholesale, so the per-alert API round-trip collapses to a hash hit. Stored false = resolved to nothing (distinct from never-resolved).
ResolveBlizzChildSpellID = function(blizzChild)
    local cdID = blizzChild.cooldownID
    if not cdID and blizzChild.cooldownInfo then
        cdID = blizzChild.cooldownInfo.cooldownID
    end
    if type(cdID) ~= "number" then return nil end
    local m = ns._cdidSidMemo
    if not m or m.gen ~= ns._cdmResGen then
        m = { gen = ns._cdmResGen }
        ns._cdidSidMemo = m
    end
    local hit = m[cdID]
    if hit ~= nil then
        if hit == false then return nil end
        return hit[1], hit[2]
    end
    local info = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
        and C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
    if info then
        local sid = ResolveInfoSpellID(info)
        if sid then
            local entry = { sid, info.spellID }
            m[cdID] = entry
            return sid, info.spellID
        end
    end
    m[cdID] = false
    return nil
end

-- Unified glow color for a spell: r,g,b or nil for default. ss.glowColor "class" -> class color, "custom" -> ss.glowColorR/G/B.
local function ResolveGlowColor(ss)
    if not ss or not ss.glowColor then return nil end
    if ss.glowColor == "class" then
        local _, ct = UnitClass("player")
        if ct then
            local cc = RAID_CLASS_COLORS[ct]
            if cc then return cc.r, cc.g, cc.b end
        end
    elseif ss.glowColor == "custom" and ss.glowColorR ~= nil then
        return ss.glowColorR, ss.glowColorG or 0.788, ss.glowColorB or 0.137
    end
    return nil
end

ns.ResolveGlowColor = ResolveGlowColor

-- Show proc glow on one of our icons. Uses per-spell settings if available.
local function ShowProcGlow(icon, cr, cg, cb)
    if not icon then return end
    local fd = _getFD(icon)
    local glow = fd and fd.glowOverlay or icon._glowOverlay
    if not glow then return end
    if fd and fd.procGlowActive then return end

    local fc = _ecmeFC[icon]
    -- Force Shape Glow (style 2) for custom-shaped icons (any but none/cropped)
    local shapeName = (fc and fc.shapeApplied) and fc.shapeName or nil
    local isCustomShape = shapeName and shapeName ~= "none" and shapeName ~= "cropped"
    local style = isCustomShape and 2 or PROC_GLOW_STYLE
    local sid = fc and fc.spellID
    if sid then
        local bk = fc and fc.barKey
        local sd = bk and ns.GetBarSpellData(bk)
        -- Shared resolver: matches the stored key against the frame's FULL identity set
        -- (canon, resolvedSid, baseSpellID, linkedSpellIDs, GetBaseSpell) so a
        -- base-spell setting resolves on its talent "proc into a second ability"
        -- override form (e.g. Reap -> base 344862). assignedSpells-only matching misses
        -- this on default Essential/Utility bars, whose assignedSpells list is empty.
        local ss = ns.ResolveSpellSettings and ns.ResolveSpellSettings(icon, sid, sd, bk)
        if ss then
            -- Custom shapes are locked to Shape Glow: ignore the per-spell glow
            -- type (incl. "None"). The per-spell glow COLOR below still applies.
            if not isCustomShape then
                if ss.procGlow == 0 then return end -- proc glow disabled
                if ss.procGlow and ss.procGlow > 0 then style = ss.procGlow end
            end
            -- Unified glow color takes priority over per-type settings
            local ur, ug, ub = ResolveGlowColor(ss)
            if ur then
                cr, cg, cb = ur, ug, ub
            elseif ss.procGlowClassColor then
                local _, ct = UnitClass("player")
                if ct then
                    local cc = RAID_CLASS_COLORS[ct]
                    if cc then cr, cg, cb = cc.r, cc.g, cc.b end
                end
            elseif ss.procGlowR ~= nil then
                cr, cg, cb = ss.procGlowR, ss.procGlowG or 0.788, ss.procGlowB or 0.137
            end
        end
    end

    -- Stop active glow if running (proc takes priority). The CD-state memo MUST follow
    -- the VISUAL: leaving _cdStateGlowOn true makes later re-evaluations skip the
    -- restart ("already on"), so a consumed proc kills the Resource Aware glow until
    -- usability flips off and on again (e.g. Shadowburn + Fiendish Cruelty). Proc
    -- priority is enforced by the procGlowActive gates on the start sites.
    if glow._glowActive then StopNativeGlow(glow) end
    if fd then fd._cdStateGlowOn = false end
    StartNativeGlow(glow, style, cr, cg, cb)
    if fd then fd.procGlowActive = true end
end

local function StopProcGlow(icon)
    local fd = icon and _getFD(icon)
    if not icon or not (fd and fd.procGlowActive) then return end
    local glow = fd and fd.glowOverlay or icon._glowOverlay
    StopNativeGlow(glow)
    if fd then fd.procGlowActive = false end
    -- The proc stomped any CD-state glow on this shared overlay; re-evaluate on the next frame
    -- so a Resource Aware ready-glow comes straight back instead of waiting for the next
    -- cooldown/power edge. Gated on _cdGlowBoundSid: only icons that actually ran a CD-state glow path carry it, so pure proc-glow users never wake the flush frame.
    if fd._cdGlowBoundSid and ns.QueueCDGlowResourceCheck then
        ns.QueueCDGlowResourceCheck()
    end
end

-- Install hooks on ActionButtonSpellAlertManager (called once during init)
local _procGlowHooksInstalled = false
local function InstallProcGlowHooks()
    if _procGlowHooksInstalled then return end
    if not ActionButtonSpellAlertManager then return end

    hooksecurefunc(ActionButtonSpellAlertManager, "ShowAlert", function(_, frame)
        if not frame then return end
        local barKey, cdmChild = GetBarKeyForBlizzChild(frame)
        if not barKey or not cdmChild then return end

        -- Hide Blizzard's built-in SpellActivationAlert on the CDM child
        if cdmChild.SpellActivationAlert then
            cdmChild.SpellActivationAlert:SetAlpha(0)
            cdmChild.SpellActivationAlert:Hide()
        end

        -- Apply immediately: no defer needed, icon mapping is current from the last reanchor.
        local ourIcon = FindOurIconForBlizzChild(barKey, cdmChild)
        if not ourIcon then return end
        ShowProcGlow(ourIcon)
        -- Force texture re-evaluation so override textures apply immediately
        FC(ourIcon).lastTex = nil
    end)

    hooksecurefunc(ActionButtonSpellAlertManager, "HideAlert", function(_, frame)
        if not frame then return end
        local barKey, cdmChild = GetBarKeyForBlizzChild(frame)
        if not barKey or not cdmChild then return end
        local ourIcon = FindOurIconForBlizzChild(barKey, cdmChild)
        local fd = ourIcon and _getFD(ourIcon)
        if not ourIcon or not (fd and fd.procGlowActive) then return end

        -- Trust Blizzard's HideAlert: stop immediately. A re-fired ShowAlert during an internal refresh restarts the glow next frame.
        StopProcGlow(ourIcon)
        -- Force texture re-evaluation so the original texture restores
        FC(ourIcon).lastTex = nil
    end)

    _procGlowHooksInstalled = true
end

-- No-ops kept so existing call sites don't error: proc glows are fully hook-driven for every bar, and the ShowAlert hooks installed at file load catch Blizzard's login re-fire.
local function ScanExistingProcGlows()
end
ns.ScanExistingProcGlows = ScanExistingProcGlows

local function OnProcGlowEvent() end
ns.OnProcGlowEvent = OnProcGlowEvent

-- Install at file-load time: Blizzard re-fires ShowAlert during PLAYER_LOGIN for active procs, and the hooks MUST precede that.
InstallProcGlowHooks()


-------------------------------------------------------------------------------
--  CDM Bars: Our replacement for Blizzard's Cooldown Manager
--  Captures Blizzard positions on first login, then creates our own bars.
-------------------------------------------------------------------------------
local CDM_FONT_FALLBACK = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"
local function GetCDMFont()
    if EllesmereUI and EllesmereUI.GetFontPath then
        return EllesmereUI.GetFontPath("cdm")
    end
    return CDM_FONT_FALLBACK
end
local function GetCDMOutline()
    -- Forced crisp outline; global "Never Show Slug" toggle drops the slug.
    if EllesmereUI and EllesmereUI.SlugFlag then return EllesmereUI.SlugFlag("OUTLINE, SLUG") end
    return "OUTLINE, SLUG"
end
local function SetBlizzCDMFont(fs, font, size, r, g, b)
    if not (fs and fs.SetFont) then return end
    EllesmereUI.ApplyIconTextFont(fs, font, size, "cdm")
    if r then fs:SetTextColor(r, g, b) end
end

-- Blizzard CDM frame names
local BLIZZ_CDM_FRAMES = {
    cooldowns = "EssentialCooldownViewer",
    utility   = "UtilityCooldownViewer",
    buffs     = "BuffIconCooldownViewer",
}

-- BuffBarCooldownViewer is Blizzard's buff bar strip, hidden alongside the icon viewer so
-- the default buff display is fully suppressed when CDM hiding is on. Our Tracked Buff Bars replace it.
local BLIZZ_CDM_FRAMES_SECONDARY = {
    buffs = "BuffBarCooldownViewer",
}

-- CDM category numbers per bar key (for C_CooldownViewer API)
local CDM_BAR_CATEGORIES = {
    cooldowns = { 0, 1 },    -- Essential + Utility
    utility   = { 0, 1 },    -- Essential + Utility
    buffs     = { 2, 3 },    -- Tracked Buff + Tracked Debuff
}

-- Maximum number of custom bars a user can create
local MAX_CUSTOM_BARS = 20

-- Cached player info (set once at PLAYER_LOGIN)
local _playerRace, _playerClass

-- Forward declarations
local BuildCDMBar, LayoutCDMBar, HideBlizzardCDM, RestoreBlizzardCDM
local CaptureCDMPositions, ApplyCDMBarPosition, ApplyShapeToCDMIcon
local _CDMApplyVisibility

-------------------------------------------------------------------------------
--  Capture Blizzard CDM positions (first login only)
-------------------------------------------------------------------------------
CaptureCDMPositions = function()
    local captured = {}
    local uiW, uiH = UIParent:GetSize()
    local uiScale = UIParent:GetEffectiveScale()

    for barKey, frameName in pairs(BLIZZ_CDM_FRAMES) do
        local frame = _G[frameName]
        if frame then
            local data = {}

            -- Read the frame's scale (used to adjust icon size capture)
            local frameScale = frame:GetScale()
            if not frameScale or frameScale < 0.1 then frameScale = 1 end

            -- Icon size + spacing from child icons. Blizzard CDM icons have a base size plus a
            -- per-icon scale driven by the IconSize percentage slider; spacing is the gap between two adjacent visible icons in parent coordinates.
            local childCount = frame:GetNumChildren()
            local numDistinctY = {}
            local shownIcons = {}
            for ci = 1, childCount do
                local child = select(ci, frame:GetChildren())
                if child and child.Icon then
                    local cw = child:GetWidth()
                    local cs = child:GetScale()
                    if cw and cw > 1 and not data.iconSize then
                        local visual = cw * (cs or 1)
                        data.iconSize = math.floor(visual + 0.5)
                    end
                    -- Collect shown icons for spacing measurement
                    if child:IsShown() then
                        shownIcons[#shownIcons + 1] = child
                        -- Track distinct Y positions for row counting
                        if child:GetPoint(1) then
                            local _, _, _, _, cy = child:GetPoint(1)
                            if cy then
                                numDistinctY[math.floor(cy + 0.5)] = true
                            end
                        end
                    end
                end
            end

            if #shownIcons >= 2 and data.iconSize then
                -- Sort by left edge so we measure truly adjacent icons
                table.sort(shownIcons, function(a, b)
                    return (a:GetLeft() or 0) < (b:GetLeft() or 0)
                end)
                -- Smallest step between consecutive sorted icons. GetLeft() returns UIParent-coordinate-space values.
                local bestStep = nil
                for si = 1, #shownIcons - 1 do
                    local aLeft = shownIcons[si]:GetLeft()
                    local bLeft = shownIcons[si + 1]:GetLeft()
                    if aLeft and bLeft then
                        local dist = bLeft - aLeft
                        if dist > 0 and (not bestStep or dist < bestStep) then
                            bestStep = dist
                        end
                    end
                end
                if bestStep then
                    -- bestStep is UIParent coords; the icon-parent -> UIParent multiplier is
                    -- frame.effectiveScale / UIParent.effectiveScale, so divide for frame coords.
                    -- Frame positions use cw units while iconSize = cw * cs (visual), so multiply by cs for the step in iconSize units.
                    local frameEff = frame:GetEffectiveScale()
                    local uiEff = UIParent:GetEffectiveScale()
                    local parentStep = bestStep * uiEff / frameEff
                    local cs = shownIcons[1]:GetScale() or 1
                    local stepInIconUnits = parentStep * cs
                    local gap = stepInIconUnits - data.iconSize
                    if gap < 0 then gap = 0 end
                    data.spacing = math.floor(gap + 0.5)
                end
            end

            -- Rows: count distinct Y positions among visible icon children
            local rowCount = 0
            for _ in pairs(numDistinctY) do rowCount = rowCount + 1 end
            if rowCount >= 1 then
                data.numRows = rowCount
            end

            if frame.isHorizontal ~= nil then
                data.isHorizontal = frame.isHorizontal
            end

            -- Position (center-based, in UIParent coordinates)
            if frame:GetPoint(1) then
                local cx, cy = frame:GetCenter()
                if cx and cy then
                    local bScale = frame:GetEffectiveScale()
                    cx = cx * bScale / uiScale
                    cy = cy * bScale / uiScale
                    data.point = "CENTER"
                    data.relPoint = "CENTER"
                    data.x = cx - (uiW / 2)
                    data.y = cy - (uiH / 2)
                end
            end

            captured[barKey] = data
        end
    end

    return captured
end

-------------------------------------------------------------------------------
--  EnforceCooldownViewerEditModeSettings (one-shot)
--  Runs ONCE on init to force Edit Mode settings so Blizzard's hideWhenInactive/visibility
--  modes can't interfere with CDM's frame management:
--    - VisibleSetting = Always on ALL viewers
--    - HideWhenInactive = 1 on buff viewers (BuffIcon + BuffBar)
--  SaveLayouts is called at most once, during init, NEVER at runtime: a SaveLayouts-triggered layout reapply from addon code taints Blizzard frame properties (isActive, etc.).
-------------------------------------------------------------------------------
local _editModePolicyApplied = false

-- Shown when our automatic save did NOT take (see the loop breaker below). Dismissable, and
-- deliberately repeats every login until the layout is correct: going quiet would leave CDM
-- misbehaving unexplained. CDM must be OFF while the user follows the steps -- this addon hides
-- Blizzard's cooldown viewers, and a hidden system cannot be selected in Edit Mode; the confirm
-- button does that step (same disable+reload idiom as the conflict guard at the top of this file). Step 6 lives in the text because once CDM is disabled nothing of ours runs to remind them to re-enable it.
local function ShowManualEditModeFixPopup()
    C_Timer.After(0, function()
        if not (EllesmereUI and EllesmereUI.ShowConfirmPopup) then return end
        EllesmereUI:ShowConfirmPopup({
            title = "Edit Mode Needs a Manual Fix",
            message = "EllesmereUI could not save this change to your Edit Mode layout, so it has to be set by hand. The Cooldown Manager has to be off while you do it, because it hides Blizzard's cooldown viewers and a hidden viewer cannot be selected in Edit Mode.\n\n"
                .. "1. Disable EllesmereUI Cooldown Manager (button below).\n"
                .. "2. Open Edit Mode from the Game Menu.\n"
                .. "3. Select each Cooldown Manager viewer and set Visibility to Always.\n"
                .. "4. On Tracked Buffs and Tracked Bars, tick Hide When Inactive.\n"
                .. "5. Save the layout and leave Edit Mode.\n"
                .. "6. Re-enable EllesmereUI Cooldown Manager.",
            disclaimer = "This will keep appearing each login until the layout is correct.",
            confirmText = "Disable CDM & Reload",
            cancelText = "Not Now",
            onConfirm = function()
                local disable = C_AddOns and C_AddOns.DisableAddOn or DisableAddOn
                if disable then disable("EllesmereUICooldownManager") end
                ReloadUI()
            end,
        })
    end)
end

local function EnforceCooldownViewerEditModeSettings()
    if _editModePolicyApplied then return end
    if not (C_EditMode and C_EditMode.GetLayouts and C_EditMode.SaveLayouts
            and Enum and Enum.EditModeSystem and Enum.EditModeSystem.CooldownViewer
            and Enum.EditModeCooldownViewerSetting and Enum.CooldownViewerVisibleSetting
            and Enum.EditModeCooldownViewerSystemIndices) then
        return
    end

    local layoutInfo = C_EditMode.GetLayouts()
    if type(layoutInfo) ~= "table" or type(layoutInfo.layouts) ~= "table" then return end

    -- Merge preset layouts so activeLayout index resolves correctly
    local numPresets = 0
    if EditModePresetLayoutManager and EditModePresetLayoutManager.GetCopyOfPresetLayouts then
        local presets = EditModePresetLayoutManager:GetCopyOfPresetLayouts()
        if type(presets) == "table" then
            numPresets = #presets
            tAppendAll(presets, layoutInfo.layouts)
            layoutInfo.layouts = presets
        end
    end

    -- Presets unresolved: activeLayout counts them, so without the merge it picks the WRONG
    -- layout below and the save hands the client a list its own index no longer fits.
    if numPresets == 0 then return end

    local activeLayout = type(layoutInfo.activeLayout) == "number"
        and layoutInfo.layouts[layoutInfo.activeLayout]
    if not activeLayout or type(activeLayout.systems) ~= "table" then return end

    -- Preset layouts are read-only: SaveLayouts won't persist changes to them, which would
    -- loop enforce -> save -> reload forever (the preset resets next login). Skip enforcement for presets.
    if numPresets > 0 and type(layoutInfo.activeLayout) == "number" and layoutInfo.activeLayout <= numPresets then
        -- Nothing to enforce on a preset: Always Show Buffs needs no layout change (it draws placeholder icons).
        _editModePolicyApplied = true
        return
    end

    local changed = false
    local cooldownSystem = Enum.EditModeSystem.CooldownViewer
    local visSetting  = Enum.EditModeCooldownViewerSetting.VisibleSetting
    local visAlways   = Enum.CooldownViewerVisibleSetting.Always
    local hideEnum    = Enum.EditModeCooldownViewerSetting.HideWhenInactive
    local buffIconIdx = Enum.EditModeCooldownViewerSystemIndices.BuffIcon
    local buffBarIdx  = Enum.EditModeCooldownViewerSystemIndices.BuffBar

    -- Returns changed(bool). A layout stores a CooldownViewer setting ONLY when changed away
    -- from Blizzard's default, so an absent entry means "at the default" (defaultValue). When
    -- that already equals what we want, leave the entry absent (no change, no forced reload); only add an explicit entry when default differs from desired.
    local function UpsertSetting(settings, settingEnum, desiredValue, defaultValue)
        for _, s in ipairs(settings) do
            if s.setting == settingEnum then
                if s.value ~= desiredValue then
                    s.value = desiredValue
                    return true
                end
                return false
            end
        end
        -- Absent: at the Blizzard default. Nothing to do if that already matches.
        if desiredValue == defaultValue then
            return false
        end
        settings[#settings + 1] = { setting = settingEnum, value = desiredValue }
        return true
    end

    for _, sysInfo in ipairs(activeLayout.systems) do
        if sysInfo.system == cooldownSystem and type(sysInfo.settings) == "table" then
            -- VisibleSetting=Always on ALL viewers. That IS the default, so an absent entry is already correct and is left alone.
            if UpsertSetting(sysInfo.settings, visSetting, visAlways, visAlways) then
                changed = true
            end
            -- Both buff viewers keep Blizzard's default HideWhenInactive=1 (inactive entries
            -- stay hidden): Always Show Buffs is drawn by our own per-bar placeholder icons, NOT
            -- Blizzard's layout, so any stale HideWhenInactive=0 is reset. New installs are already at the default (no change, no reload).
            if sysInfo.systemIndex == buffIconIdx or sysInfo.systemIndex == buffBarIdx then
                if UpsertSetting(sysInfo.settings, hideEnum, 1, 1) then
                    changed = true
                end
            end
        end
    end

    _editModePolicyApplied = true
    if not changed then
        -- Settled: the layout already carries what we want, so a previous save DID stick.
        -- Re-arm the loop breaker so a genuine future change (new layout, manual edit) still prompts.
        if EllesmereUIDB then EllesmereUIDB.cdmEditModeSavePending = nil end
        return
    end

    -- Save the corrected layout. Blizzard won't visually apply it until the next login/reload, so force a reload via popup.
    C_EditMode.SaveLayouts(layoutInfo)

    -- LOOP BREAKER: a forced reload only makes sense if the save persisted. If this exact
    -- correction was saved in a PREVIOUS session and the delta is STILL here, the save did not
    -- stick, so re-offering the same non-dismissable reload would trap the user every login.
    -- The forced reload is offered at most once per unresolved correction; after that the user
    -- gets manual instructions every login until the layout comes back clean. Flag clears itself
    -- in the not-changed branch above, so a working user pays nothing. Backstop, NOT the cure -- it stops the loop without knowing why the save failed.
    local savedLastSession = EllesmereUIDB and EllesmereUIDB.cdmEditModeSavePending
    if EllesmereUIDB then EllesmereUIDB.cdmEditModeSavePending = true end
    if savedLastSession then
        ShowManualEditModeFixPopup()
        return
    end

    -- Forced (non-dismissable) reload popup. On first install the Welcome picker is
    -- pending/open and ALWAYS ends in its own forced ReloadUI, which applies the layout we
    -- just saved -- a second forced popup would stomp the picker, so stay silent and ride that reload.
    if EllesmereUI and EllesmereUI._firstInstallPending then return end
    C_Timer.After(0, function()
        if not EllesmereUI or not EllesmereUI.ShowConfirmPopup then
            ReloadUI()
            return
        end
        EllesmereUI:ShowConfirmPopup({
            title = "Edit Mode Update",
            message = "EllesmereUI has updated your CDM Edit Mode settings to ensure cooldown tracking works correctly.\n\nA UI reload is required for the changes to take effect.",
            confirmText = "Reload UI",
            onConfirm = function() ReloadUI() end,
        })
        -- Force: no cancel, no escape, no click-outside dismiss.
        local popup = _G["EUIConfirmPopup"]
        if popup then
            if popup._cancelBtn then popup._cancelBtn:Hide() end
            if popup._confirmBtn then
                popup._confirmBtn:ClearAllPoints()
                popup._confirmBtn:SetPoint("BOTTOM", popup, "BOTTOM", 0, 13)
            end
            popup:SetScript("OnKeyDown", function(self, key)
                self:SetPropagateKeyboardInput(key ~= "ESCAPE")
            end)
            if popup._dimmer then
                popup._dimmer:SetScript("OnMouseDown", nil)
            end
        end
    end)
end

-- One-time per-profile migration: the GLOBAL Always Show Buffs settings (cdmBars.showInactiveBuffIcons/
-- .desaturateInactiveBuffs) become PER-BAR fields; a profile with the global ON turns every buff bar ON.
-- Runs once per profile (flag on cdmBars); re-runs on swap to a pre-migration profile, which carries no flag.
function ns.MigrateAlwaysShowBuffsToPerBar()
    local p = ECME.db and ECME.db.profile
    if not p or not p.cdmBars or p.cdmBars._asbPerBarMigrated then return end
    p.cdmBars._asbPerBarMigrated = true
    local oldOn = p.cdmBars.showInactiveBuffIcons
    local oldDesat = p.cdmBars.desaturateInactiveBuffs
    if oldOn == nil and oldDesat == nil then return end
    if type(p.cdmBars.bars) ~= "table" then return end
    for _, bd in ipairs(p.cdmBars.bars) do
        if bd.barType == "buffs" then
            if oldOn ~= nil then bd.showInactiveBuffIcons = oldOn and true or false end
            if oldDesat ~= nil then bd.desaturateInactiveBuffs = oldDesat end
        end
    end
end

-- One-time per-profile migration: the custom_buff ("Auras") bar type merged into the buff
-- family. Converts every custom_buff bar to "buffs" in place -- key, assignedSpells,
-- spellDurations, customSpellIDs, position and all visual settings carry over unchanged. The
-- buff phase injects the same cast-timer custom buffs, so a converted bar behaves as an extra
-- buff-family bar (its key stays custom_*, never "buffs"). Same once-per-profile contract as
-- above. MUST run AFTER MigrateAlwaysShowBuffsToPerBar so the old global Always-Show value only lands on original buff bars, not converted Auras bars.
function ns.MigrateCustomBuffBarsToBuffBars()
    local p = ECME.db and ECME.db.profile
    if not p or not p.cdmBars or p.cdmBars._customBuffMergedV1 then return end
    p.cdmBars._customBuffMergedV1 = true
    if type(p.cdmBars.bars) ~= "table" then return end
    for _, bd in ipairs(p.cdmBars.bars) do
        if bd.barType == "custom_buff" then
            bd.barType = "buffs"
        end
    end
end

-------------------------------------------------------------------------------
--  Hide / Restore Blizzard CDM
-------------------------------------------------------------------------------

-- Suppress the secondary buff-bar viewer (BuffBarCooldownViewer).
--
-- Parked offscreen, NEVER Hidden: TBB mirrors min/max/value straight off Blizzard's Bar frames
-- and a hidden viewer stops updating them. The park, not the alpha, is what holds -- Blizzard's
-- hide-when-inactive fade animates the viewer's alpha back to 1 whenever a tracked buff goes
-- active, through a path no hook can see (same lesson as the unclaimed-frame park in
-- CollectAndReanchor). So once anything re-anchors the viewer to its Edit Mode position (layout
-- apply, SaveLayouts, zone-in), the next buff proc in combat draws Blizzard's bars over ours. The SetPoint hook makes the park self-healing, mirroring the unclaimed CD/utility pool frames' hook.
function ns.ParkSecondaryBuffViewer(frame)
    if not frame then return end
    local fc = FC(frame)
    frame:SetAlpha(0)
    if InCombatLockdown() then
        -- Flushed on PLAYER_REGEN_ENABLED.
        ns._secondaryParkPending = true
    else
        ns._secondaryParkPending = nil
        fc.parkGuard = true
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10000, 10000)
        fc.parkGuard = nil
    end
    if not fc.parkHooked then
        fc.parkHooked = true
        -- Deferred by a frame: Blizzard re-anchors this viewer inside its Edit Mode layout pass,
        -- which goes on to move protected systems (action bars); re-parking inline would carry
        -- our taint into the rest of that pass. The delay also coalesces ClearAllPoints + SetPoint bursts into one park, and a single frame of a stray bar is invisible.
        local function QueueRepark(self, method)
            local c = _ecmeFC[self]
            if not c or not c.hidden or c.parkGuard or c.restoring or c.parkQueued then return end
            c.parkQueued = true
            C_Timer.After(0, function()
                c.parkQueued = nil
                if c.hidden and not c.restoring then ns.ParkSecondaryBuffViewer(self) end
            end)
        end
        hooksecurefunc(frame, "SetPoint", function(self) QueueRepark(self, "SetPoint") end)
        -- SetPoint is not the only way off the park: SetAllPoints and SetParent strand the
        -- viewer on screen without ever calling it, and nothing heals that until an unrelated SetPoint happens to fire.
        hooksecurefunc(frame, "SetAllPoints", function(self) QueueRepark(self, "SetAllPoints") end)
        hooksecurefunc(frame, "SetParent", function(self) QueueRepark(self, "SetParent") end)
    end
end

-- Park integrity check, edge-driven via ns._parkEdges below.
--
-- The hooks above cover the movers we can see; a scale change, a mover that swaps anchors
-- through an unhooked path, or the one-frame gap the deferred re-park leaves open all put
-- Blizzard's bars back on screen. This closes the loop from the other end: read where the
-- viewer actually IS and re-park. Position ONLY -- alpha is deliberately not checked, since
-- Blizzard's hide-when-inactive fade animates it back to 1 through a path no hook sees and re-asserting would fight that animation while the frame is offscreen anyway.
function ns.CheckSecondaryBuffViewerPark()
    local frame = _G[BLIZZ_CDM_FRAMES_SECONDARY.buffs]
    if not frame then return end
    local fc = _ecmeFC[frame]
    if not fc or not fc.hidden or fc.restoring or fc.parkQueued then return end
    local pt, rel, relPt, x, y
    -- Indexing past the last point errors; an unanchored viewer counts as drifted and falls through to the re-park.
    if frame:GetNumPoints() > 0 then pt, rel, relPt, x, y = frame:GetPoint(1) end
    -- Tolerant compare: GetPoint round-trips through UI scale, so the stored -10000/10000 can
    -- read back with float drift, and a parent-anchored point can report its relative frame as
    -- nil. Exact equality fails every pass on scaled UIs, re-parking forever. Anywhere far offscreen top-left IS parked.
    if pt == "TOPLEFT" and (rel == UIParent or rel == nil) and relPt == "TOPLEFT"
       and x and x < -9990 and y and y > 9990 then
        return
    end
    -- In combat this re-asserts alpha 0 and defers the park itself; the frame is protected, so alpha is the only lever until PLAYER_REGEN_ENABLED.
    ns.ParkSecondaryBuffViewer(frame)
end

-- Park integrity for visibility-hidden cursor bars (edge-driven via ns._parkEdges below).
-- Their glue shells sleep while hidden, so a mover that strands one on-screen is healed here instead of by a per-frame OnUpdate. A parked bar costs two reads.
function ns._CheckCursorParks()
    for _, frame in pairs(cdmBarFrames) do
        if frame and frame._mouseTrack and frame._visHidden
           and (frame:GetLeft() or 0) > -9000 then
            frame._mouseParked = true
            frame:ClearAllPoints()
            frame:SetPoint(frame._mousePoint or "LEFT", UIParent, "BOTTOMLEFT", -10000, -10000)
        end
    end
end

-- Edge-driven park integrity (NO polling patrols): hookable movers self-heal via the
-- QueueRepark hooksecurefuncs, LayoutCDMBar guards hidden cursor bars directly, and these are
-- the remaining un-hookable edges (scale changes and Edit Mode layout passes re-anchor Blizzard frames through paths no hook sees). A stale park beyond these is a missing edge to add here -- never a patrol.
ns._parkEdges = CreateFrame("Frame")
ns._parkEdges:RegisterEvent("UI_SCALE_CHANGED")
ns._parkEdges:RegisterEvent("DISPLAY_SIZE_CHANGED")
ns._parkEdges:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
ns._parkEdges:RegisterEvent("PLAYER_ENTERING_WORLD")
ns._parkEdges:SetScript("OnEvent", function()
    if ns.CheckSecondaryBuffViewerPark then ns.CheckSecondaryBuffViewerPark() end
    if ns._CheckCursorParks then ns._CheckCursorParks() end
end)

HideBlizzardCDM = function()
    -- Anchor each viewer to our corresponding bar container. Frames stay parented to viewers
    -- (no reparenting = no taint); the viewer becomes an invisible shell overlapping our
    -- container and CollectAndReanchor re-anchors individual icons within it. Viewer alpha stays at 1 so child frames inherit visibility.
    local viewerToBar = {
        [BLIZZ_CDM_FRAMES.cooldowns] = "cooldowns",
        [BLIZZ_CDM_FRAMES.utility]   = "utility",
        [BLIZZ_CDM_FRAMES.buffs]     = "buffs",
    }
    local allFrameNames = {}
    for _, fn in pairs(BLIZZ_CDM_FRAMES) do allFrameNames[#allFrameNames + 1] = fn end
    for _, fn in pairs(BLIZZ_CDM_FRAMES_SECONDARY) do allFrameNames[#allFrameNames + 1] = fn end
    for _, frameName in ipairs(allFrameNames) do
        local frame = _G[frameName]
        if frame then
            local fc = FC(frame)
            if not fc.hidden then
                fc.origPoints = {}
                for i = 1, frame:GetNumPoints() do
                    fc.origPoints[i] = { frame:GetPoint(i) }
                end
                fc.hidden = true
            end
            -- NEVER reposition primary viewers (Essential/Utility/BuffIcon): individual icon
            -- anchoring handles that. The secondary BuffBarCooldownViewer gets alpha + offscreen park, since TBB renders its own bars and we don't hook its Cooldown widgets.
            local isSecondary = (frameName == BLIZZ_CDM_FRAMES_SECONDARY.buffs)
            if isSecondary then
                ns.ParkSecondaryBuffViewer(frame)
            end
            if not InCombatLockdown() then
                frame:EnableMouse(false)
                if frame.EnableMouseMotion then frame:EnableMouseMotion(false) end
            end
        end
    end
end

RestoreBlizzardCDM = function()
    local allFrameNames = {}
    for _, fn in pairs(BLIZZ_CDM_FRAMES) do allFrameNames[#allFrameNames + 1] = fn end
    for _, fn in pairs(BLIZZ_CDM_FRAMES_SECONDARY) do allFrameNames[#allFrameNames + 1] = fn end
    for _, frameName in ipairs(allFrameNames) do
        local frame = _G[frameName]
        local fc = frame and _ecmeFC[frame]
        if fc and fc.hidden then
            fc.restoring = true
            ns._secondaryParkPending = nil
            if fc.origPoints then
                frame:ClearAllPoints()
                for _, pt in ipairs(fc.origPoints) do
                    frame:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5])
                end
            end
            -- The secondary viewer is the only alpha-suppressed one, and its Blizzard default is EnableMouse(false) -- restoring it true leaves an invisible click-catcher.
            if frameName == BLIZZ_CDM_FRAMES_SECONDARY.buffs then
                frame:SetAlpha(1)
            else
                frame:EnableMouse(true)
                if frame.EnableMouseMotion then frame:EnableMouseMotion(true) end
            end
            fc.hidden = false
            fc.restoring = nil
        end
    end
end

-- Restore Blizzard's BuffBarCooldownViewer (bar-style buff tracking strip) when TBB is
-- disabled via "Use Blizzard CDM Bars". Touches ONLY the secondary bar viewer; CDM icon bars are never affected.
local function RestoreBlizzardBuffFrame()
    local frameName = BLIZZ_CDM_FRAMES_SECONDARY.buffs
    if not frameName then return end
    local frame = _G[frameName]
    local fc = frame and _ecmeFC[frame]
    if fc and fc.hidden then
        fc.restoring = true
        ns._secondaryParkPending = nil
        if fc.origPoints then
            frame:ClearAllPoints()
            for _, pt in ipairs(fc.origPoints) do
                frame:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5])
            end
        end
        frame:SetAlpha(1)
        -- BuffBarCooldownViewer's default is EnableMouse(false); EnableMouse(true) would create an invisible click-catcher. Other viewers need mouse for tooltip hover.
        if frameName ~= "BuffBarCooldownViewer" then
            frame:EnableMouse(true)
            if frame.EnableMouseMotion then frame:EnableMouseMotion(true) end
        end
        fc.hidden = false
        fc.restoring = nil
    end
end

-------------------------------------------------------------------------------
--  CDM Bar Position Helpers
-------------------------------------------------------------------------------

-- Resolve the frame anchor point for a bar from its growth direction and optional row growth direction.
--
-- Without rowGrowDirection: the single growth edge (RIGHT -> LEFT, DOWN -> TOP, ...) so the
-- fixed edge stays put as the bar resizes along its growth axis; the perpendicular axis stays
-- unpinned (centered), which is why a horizontal bar re-centers vertically when it grows a
-- second row. rowGrowDirection applies the same growth->opposite-edge mapping to the
-- PERPENDICULAR axis, yielding a corner/edge anchor (e.g. TOPLEFT): horizontal bars take "DOWN"
-- (pin TOP) or "UP" (pin BOTTOM); vertical bars take "RIGHT" (pin LEFT) or "LEFT" (pin RIGHT);
-- nil keeps centered growth. Icons lay out from the frame's TOPLEFT, so "UP"/"LEFT" also need
-- LayoutCDMBar's visual row reversal to keep the pinned row's icons from jumping when a row
-- spills in/out. ns.* fields rather than file-scope locals: Lua 5.1's 200-local main-chunk ceiling.
--
-- ignoreRowGrow: resolve the plain growth edge even when a row growth direction is set -- for
-- unlock-snapped bars, whose saved-edge consumers (ApplyAnchorPosition edge preservation/target follow) only understand single-edge points.
function ns.ResolveGrowAnchorPoint(barData, ignoreRowGrow)
    local grow = (barData and barData.growDirection) or "CENTER"
    local horiz, vert  -- "LEFT"/"RIGHT" and "TOP"/"BOTTOM" components
    if grow == "RIGHT" then
        horiz = "LEFT"
    elseif grow == "LEFT" then
        horiz = "RIGHT"
    elseif grow == "DOWN" then
        vert = "TOP"
    elseif grow == "UP" then
        vert = "BOTTOM"
    end
    local rowGrow = barData and barData.rowGrowDirection
    if rowGrow and not ignoreRowGrow then
        -- Same opposite-edge mapping applied to the perpendicular axis. The orientation guards keep a value left stale by an orientation flip from clobbering the main-axis component.
        if barData.verticalOrientation then
            if rowGrow == "RIGHT" then
                horiz = horiz or "LEFT"
            elseif rowGrow == "LEFT" then
                horiz = horiz or "RIGHT"
            end
        else
            if rowGrow == "DOWN" then
                vert = vert or "TOP"
            elseif rowGrow == "UP" then
                vert = vert or "BOTTOM"
            end
        end
    end
    local pt = (vert or "") .. (horiz or "")
    if pt == "" then
        return "CENTER"
    end
    return pt
end

-- Convert a frame CENTER coord to the coord for anchor point `pt`. An axis with no LEFT/RIGHT
-- (or TOP/BOTTOM) component keeps the center; a zero-extent frame yields a zero offset, so this is safe for empty bars.
function ns.CenterToAnchorCoord(pt, x, y, fw, fh)
    local sx, sy = x, y
    if pt:find("LEFT", 1, true) then
        sx = x - fw / 2
    elseif pt:find("RIGHT", 1, true) then
        sx = x + fw / 2
    end
    if pt:find("TOP", 1, true) then
        sy = y + fh / 2
    elseif pt:find("BOTTOM", 1, true) then
        sy = y - fh / 2
    end
    return sx, sy
end

-- Inverse of CenterToAnchorCoord: recover the frame CENTER coord from a stored anchor-point coord. Round-trips losslessly for edges, corners, and CENTER.
function ns.AnchorCoordToCenter(pt, sx, sy, fw, fh)
    local x, y = sx, sy
    if pt:find("LEFT", 1, true) then
        x = sx + fw / 2
    elseif pt:find("RIGHT", 1, true) then
        x = sx - fw / 2
    end
    if pt:find("TOP", 1, true) then
        y = sy - fh / 2
    elseif pt:find("BOTTOM", 1, true) then
        y = sy + fh / 2
    end
    return x, y
end

-- "Additional Bar Offset" (bd.addOffsetX/Y; ADDITIONAL BAR OFFSET options
-- section): a render-only displacement stacked on top of whatever positioned
-- the bar -- saved position, module anchor (party/player/ERB), or the shared
-- unlock anchor system (which folds it through _anchorExtraOffset instead of
-- this helper). Suppressed while unlock mode is active so movers show and save
-- TRUE positions; the shift-provider lifecycle hooks strip it on unlock entry
-- and re-apply it on exit. nil/0 = zero work and zero movement (purely
-- additive feature). On ns: this file is at the 200-local cap.
ns.CDMAddOffset = function(bd)
    if not bd then return 0, 0 end
    local ox = bd.addOffsetX or 0
    local oy = bd.addOffsetY or 0
    if ox == 0 and oy == 0 then return 0, 0 end
    if EllesmereUI._unlockActive then return 0, 0 end
    return ox, oy
end

local function ApplyBarPositionCentered(frame, pos, barKey)
    if not pos or not pos.point then return end
    local fw = frame:GetWidth() or 0
    local fh = frame:GetHeight() or 0
    local px, py = pos.x or 0, pos.y or 0
    local anchor = pos.point
    local bd = barKey and barDataByKey[barKey]

    -- Corner-capable re-derivation, taken ONLY when a row growth direction is in play (or the
    -- stored point is a leftover corner): recover the frame center from the stored anchor coord,
    -- then re-project onto the anchor resolved from the bar's CURRENT growth + row growth.
    -- Lossless round-trip -- the bar does not move, only the pinned edge/corner changes. Bars without a row growth direction take the conversion below. No persistence: positions are only saved by unlock mode's Save & Exit.
    local storedIsCorner = (anchor:find("TOP", 1, true) or anchor:find("BOTTOM", 1, true))
        and (anchor:find("LEFT", 1, true) or anchor:find("RIGHT", 1, true))
    if (bd and bd.rowGrowDirection) or storedIsCorner then
        local cx, cy = ns.AnchorCoordToCenter(anchor, px, py, fw, fh)
        anchor = ns.ResolveGrowAnchorPoint(bd)
        px, py = ns.CenterToAnchorCoord(anchor, cx, cy, fw, fh)
    elseif anchor == "CENTER" and barKey then
        -- Runtime conversion: a non-CENTER-grow bar with a CENTER position (legacy data,
        -- Blizzard import) converts to edge format for SetPoint so it grows from the correct edge.
        local grow = bd and bd.growDirection or "CENTER"
        if grow ~= "CENTER" then
            if grow == "RIGHT" and fw > 0 then
                anchor = "LEFT"; px = px - fw / 2
            elseif grow == "LEFT" and fw > 0 then
                anchor = "RIGHT"; px = px + fw / 2
            elseif grow == "DOWN" and fh > 0 then
                anchor = "TOP"; py = py + fh / 2
            elseif grow == "UP" and fh > 0 then
                anchor = "BOTTOM"; py = py - fh / 2
            end
        end
    end

    -- Additional Bar Offset: applied PRE-snap so the sum lands on the pixel
    -- grid; a zero offset is a guaranteed no-op.
    local aox, aoy = ns.CDMAddOffset(bd)
    px, py = px + aox, py + aoy

    -- Snap to physical pixel grid. CENTER anchor: SnapCenterForDim preserves the +0.5 offset
    -- odd-pixel-dim frames need for whole-pixel edges. Single-edge anchors: the growth-axis
    -- coord is an EDGE (whole-pixel snap) but the perpendicular coord is the frame's CENTER on
    -- that axis -- parity-aware snap keeps whole-pixel edges there too. Corner anchors (row growth pin) are edges on BOTH axes.
    local PPa = EllesmereUI and EllesmereUI.PP
    if PPa then
        local es = frame:GetEffectiveScale()
        if anchor == "CENTER" and PPa.SnapCenterForDim then
            px = PPa.SnapCenterForDim(px, fw, es)
            py = PPa.SnapCenterForDim(py, fh, es)
        elseif PPa.SnapForES then
            if PPa.SnapCenterForDim and (anchor == "LEFT" or anchor == "RIGHT") then
                px = PPa.SnapForES(px, es)
                py = PPa.SnapCenterForDim(py, fh, es)
            elseif PPa.SnapCenterForDim and (anchor == "TOP" or anchor == "BOTTOM") then
                px = PPa.SnapCenterForDim(px, fw, es)
                py = PPa.SnapForES(py, es)
            else
                px = PPa.SnapForES(px, es)
                py = PPa.SnapForES(py, es)
            end
        end
    end

    frame:ClearAllPoints()
    frame:SetPoint(anchor, UIParent, pos.relPoint or anchor, px, py)
end

local function SaveCDMBarPosition(barKey, frame)
    if not frame then return end
    local p = ECME.db.profile
    local scale = frame:GetScale() or 1
    local uiScale = UIParent:GetEffectiveScale()
    local fScale = frame:GetEffectiveScale()
    local uiW, uiH = UIParent:GetSize()
    local ratio = fScale / uiScale

    -- Anchor point from grow + row growth direction, so the bar's fixed edge/corner stays put when icon count changes (spec swaps, combat buff churn, a row spilling in/out).
    local bd = barDataByKey[barKey]
    local pt = ns.ResolveGrowAnchorPoint(bd)

    -- Read each axis from the matching frame edge (corner points pin both).
    local cx, cy = frame:GetCenter()
    if not cx or not cy then return end
    local ax, ay
    if pt:find("LEFT", 1, true) then
        local lx = frame:GetLeft()
        if not lx then return end
        ax = lx * ratio
    elseif pt:find("RIGHT", 1, true) then
        local rx = frame:GetRight()
        if not rx then return end
        ax = rx * ratio
    else
        ax = cx * ratio
    end
    if pt:find("TOP", 1, true) then
        local ty = frame:GetTop()
        if not ty then return end
        ay = ty * ratio
    elseif pt:find("BOTTOM", 1, true) then
        local by = frame:GetBottom()
        if not by then return end
        ay = by * ratio
    else
        ay = cy * ratio
    end

    -- Store relative to UIParent CENTER so offset math is consistent.
    -- Additional Bar Offset: live geometry includes the render-only offset
    -- while out of unlock mode -- subtract it so the SAVED position is always
    -- the BASE (else the Row Growth recapture bakes it in and the bar drifts
    -- by one offset per edit). In unlock mode both terms are already base:
    -- the frame carries no offset and CDMAddOffset returns 0.
    local aox, aoy = ns.CDMAddOffset(bd)
    p.cdmBarPositions[barKey] = {
        point = pt, relPoint = "CENTER",
        x = (ax - uiW / 2) / scale - aox,
        y = (ay - uiH / 2) / scale - aoy,
    }
end

-- Re-persist a bar's saved position in its CURRENT anchor format from live geometry. Needed
-- when the row growth direction changes: a stored center/single-edge position can't pin the
-- row edge across row changes (only a stored corner can), so recapture the corner from where
-- the bar sits now. Free-standing bars only -- snapped bars are owned by the unlock anchor system, which reads unlockAnchors, not cdmBarPositions.
function ns.RecaptureBarAnchor(barKey)
    local frame = cdmBarFrames[barKey]
    if not frame then return end
    -- anchorTo bars (cursor, party/player frame, ERB, another bar) are positioned by their
    -- anchor, not cdmBarPositions -- saving live geometry would overwrite the free-standing position with the anchored spot.
    local bd = barDataByKey[barKey]
    if bd and bd.anchorTo and bd.anchorTo ~= "none" then return end
    if EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored("CDM_" .. barKey) then return end
    if not frame:GetLeft() then return end
    SaveCDMBarPosition(barKey, frame)
end

-------------------------------------------------------------------------------
--  Frame anchor point for a CDM bar: the near-edge center (the edge facing away
--  from the target). RIGHT -> LEFT, LEFT -> RIGHT, DOWN -> TOP, UP -> BOTTOM.
-------------------------------------------------------------------------------
local function CDMFrameAnchorPoint(anchorSide, grow, centered)

    if grow == "RIGHT" then return "LEFT"   end
    if grow == "LEFT"  then return "RIGHT"  end
    if grow == "DOWN"  then return "TOP"    end
    if grow == "UP"    then return "BOTTOM" end
    if grow == "CENTER" then return "CENTER" end
    return "CENTER"
end

-------------------------------------------------------------------------------
--  Recursive click-through helper -- disables/restores mouse on a frame tree
-------------------------------------------------------------------------------
local function SetFrameClickThrough(frame, clickThrough)
    if not frame then return end
    if clickThrough then
        if _cdmMouseState[frame] == nil then
            _cdmMouseState[frame] = frame:IsMouseEnabled()
        end
        frame:EnableMouse(false)
        if frame.EnableMouseClicks then frame:EnableMouseClicks(false) end
        if frame.EnableMouseMotion then frame:EnableMouseMotion(false) end
    else
        if _cdmMouseState[frame] ~= nil then
            frame:EnableMouse(_cdmMouseState[frame])
            _cdmMouseState[frame] = nil
        end
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        SetFrameClickThrough(child, clickThrough)
    end
end

-------------------------------------------------------------------------------
--  Build a single CDM bar frame
-------------------------------------------------------------------------------
BuildCDMBar = function(barIndex)
    local p = ECME.db.profile
    local bars = p.cdmBars.bars
    local barData = bars[barIndex]
    if not barData then return end

    local key = barData.key
    local frame = cdmBarFrames[key]

    if not frame then
        frame = CreateFrame("Frame", "ECME_CDMBar_" .. key, UIParent)
        -- Per-bar Bar Strata (Extras); MEDIUM = the historical hardcoded value.
        frame:SetFrameStrata(barData.barStrata or "MEDIUM")
        frame:SetFrameLevel(5)
        if frame.SetSnapToPixelGrid then frame:SetSnapToPixelGrid(false) end
        if frame.SetTexelSnappingBias then frame:SetTexelSnappingBias(0) end
        if frame.EnableMouseClicks then frame:EnableMouseClicks(false) end
        -- Containers NEVER capture mouse motion: the rect spans the bar's full layout area and a
        -- motion-enabled frame with no unit steals mouseover focus from unit frames underneath. Hover is managed per-icon, gated on the bar's tooltip setting.
        if frame.EnableMouseMotion then frame:EnableMouseMotion(false) end
        frame._barKey = key
        frame._barIndex = barIndex
        cdmBarFrames[key] = frame
        cdmBarIcons[key] = {}
    end

    if not barData.enabled then
        if frame._mouseTrack then
            frame:SetScript("OnUpdate", nil)
            if EllesmereUI.Mouse then
                EllesmereUI.Mouse.UnsubscribeFrame("cdmCursor:" .. tostring(key))
                EllesmereUI.Mouse.UnsubscribeTick("cdmCursor:" .. tostring(key) .. ":watch")
            end
            frame._mouseResume = nil
            frame._mouseTrack = nil
            if frame._preMousePos and not p.cdmBarPositions[key] then
                p.cdmBarPositions[key] = frame._preMousePos
            end
            frame._preMousePos = nil
            SetFrameClickThrough(frame, false)
            if frame.EnableMouseMotion then frame:EnableMouseMotion(false) end
        end
        EllesmereUI.SetElementVisibility(frame, false)
        return
    end

    -- All sizing is width/height based; scale stays 1.
    if not InCombatLockdown() then frame:SetScale(1) end

    -- Restore configured strata/level (cursor-anchored uses TOOLTIP/9980)
    if not frame._mouseTrack then
        frame:SetFrameStrata(barData.barStrata or "MEDIUM")
        frame:SetFrameLevel(5)
    end

    -- Clear any previous mouse-tracking subscriptions
    if frame._mouseTrack then
        frame:SetScript("OnUpdate", nil)
        if EllesmereUI.Mouse then
            EllesmereUI.Mouse.UnsubscribeFrame("cdmCursor:" .. tostring(key))
            EllesmereUI.Mouse.UnsubscribeTick("cdmCursor:" .. tostring(key) .. ":watch")
        end
        frame._mouseResume = nil
        frame._mouseTrack = nil
        -- Restore position/strata/mouse from before the cursor anchor
        if frame._preMousePos and not p.cdmBarPositions[key] then
            p.cdmBarPositions[key] = frame._preMousePos
        end
        frame._preMousePos = nil
        frame:SetFrameStrata(barData.barStrata or "MEDIUM")
        frame:SetFrameLevel(5)
        SetFrameClickThrough(frame, false)
        if frame.EnableMouseMotion then frame:EnableMouseMotion(false) end
    end
    frame._mouseGrow = nil

    -- FocusKick bar is exclusively owned by ApplyFocusKickAnchor: skipping the generic position
    -- block keeps the else-branch default from snapping it to UIParent CENTER 0,0 between a rebuild and the next nameplate event. Literal key: FOCUSKICK_BAR_KEY is declared later and would be nil here.
    if key == "focuskick" then
        frame:Show()
        return
    end

    -- Cursor-anchored bar already tracking and still configured for mouse: skip the
    -- teardown+rebuild cycle. It is already repositioning correctly, and tearing it down blinks to BOTTOMLEFT 0,0 on every FullCDMRebuild.
    if frame._mouseTrack and barData.anchorTo == "mouse" then
        frame:Show()
        return
    end

    -- Position
    local anchorKey = barData.anchorTo
    if anchorKey == "mouse" then
        -- Stash saved position for restore on unanchor
        if p.cdmBarPositions[key] then
            frame._preMousePos = p.cdmBarPositions[key]
        end
        -- Anchor position acts as build direction for cursor tracking
        local anchorPos = barData.anchorPosition or "right"
        local oX = barData.anchorOffsetX or 0
        local oY = barData.anchorOffsetY or 0
        -- SetPoint anchor + 15px directional nudge
        local pointFrom, baseOX, baseOY, forceGrow
        if anchorPos == "left" then
            pointFrom = "RIGHT"; forceGrow = "LEFT"
            baseOX = -15 + oX; baseOY = oY
        elseif anchorPos == "right" then
            pointFrom = "LEFT"; forceGrow = "RIGHT"
            baseOX = 15 + oX; baseOY = oY
        elseif anchorPos == "top" then
            pointFrom = "BOTTOM"; forceGrow = "UP"
            baseOX = oX; baseOY = 15 + oY
        elseif anchorPos == "bottom" then
            pointFrom = "TOP"; forceGrow = "DOWN"
            baseOX = oX; baseOY = -15 + oY
        else
            pointFrom = "LEFT"; forceGrow = "RIGHT"
            baseOX = 15 + oX; baseOY = oY
        end
        frame._mouseGrow = forceGrow
        frame._mousePoint = pointFrom  -- park/heal sites outside this closure need it
        -- TOOLTIP strata so the bar renders above all UI; fully click-through (frame + children) while following the cursor.
        frame:SetFrameStrata("TOOLTIP")
        frame:SetFrameLevel(9980)
        SetFrameClickThrough(frame, true)
        local lastMX, lastMY
        frame:ClearAllPoints()
        frame:SetPoint(pointFrom, UIParent, "BOTTOMLEFT", 0, 0)
        frame._mouseTrack = true
        frame._mouseHiddenByPanel = false
        -- Cursor glue rides the suite Mouse service (EllesmereUI_Mouse.lua): per render frame
        -- while the cursor MOVES (position must track raw -- easing/deferral shows cadence
        -- stepping), parked by the service while still or mouselooking, re-armed within one 20 Hz
        -- watch interval of the first moved pixel. The 0.15s CursorWatch below owns panel/unlock/visibility state, so the glue body is position-only.
        local glueKey = "cdmCursor:" .. tostring(key)
        local Mouse = EllesmereUI.Mouse
        local glueActive = false
        local function CursorGlue(cx, cy)
            if cx ~= lastMX or cy ~= lastMY then
                local firstMove = lastMX == nil
                lastMX, lastMY = cx, cy
                local s = UIParent:GetEffectiveScale()
                if firstMove then frame:ClearAllPoints() end
                frame:SetPoint(pointFrom, UIParent, "BOTTOMLEFT",
                    floor(cx / s + 0.5) + baseOX, floor(cy / s + 0.5) + baseOY)
            end
        end
        frame._mouseResume = function()
            lastMX, lastMY = nil, nil
            frame._mouseParked = false
            glueActive = true
            Mouse.SubscribeFrame(glueKey, CursorGlue, true)
        end
        local function GlueOff()
            if glueActive then
                glueActive = false
                Mouse.UnsubscribeFrame(glueKey)
            end
        end
        local function CursorWatch()
            -- Hide while the EUI options panel or unlock mode is open
            local panelOpen = (EllesmereUI._mainFrame and EllesmereUI._mainFrame:IsShown())
                or EllesmereUI._unlockActive
            if panelOpen then
                GlueOff()
                frame._mouseHiddenByPanel = true
                if frame:GetAlpha() > 0 then frame:SetAlpha(0) end
                local icons = cdmBarIcons[key]
                if icons then
                    for ii = 1, #icons do
                        if icons[ii] and icons[ii]:GetFrameStrata() == "TOOLTIP" then
                            icons[ii]:SetFrameStrata(barData.barStrata or "MEDIUM")
                            icons[ii]:SetFrameLevel(5 + ii)
                        end
                    end
                end
                return
            elseif frame._mouseHiddenByPanel then
                -- Panel just closed: restore visibility and icon strata
                frame._mouseHiddenByPanel = false
                local icons = cdmBarIcons[key]
                if icons then
                    for ii = 1, #icons do
                        if icons[ii] then
                            icons[ii]:SetFrameStrata("TOOLTIP")
                            icons[ii]:SetFrameLevel(9980 + ii)
                        end
                    end
                end
                _CDMApplyVisibility()
            end
            -- Visibility-hidden: park the bar offscreen instead of tracking the cursor. Alpha
            -- alone CANNOT keep icons invisible -- the engine re-raises item alpha through paths
            -- no hook sees (SetAlphaFromBoolean, alpha animations) on cooldown/aura state changes,
            -- so a hidden bar flashes back mid-screen riding the cursor (same lesson as the
            -- unclaimed-frame park in EllesmereUICdmHooks). Icons anchor to this container so the park carries them, immune to every alpha path. Movers-while-parked heal via ns._parkEdges + the LayoutCDMBar guard -- no patrol.
            if frame._visHidden then
                GlueOff()
                if not frame._mouseParked or (frame:GetLeft() or 0) > -9000 then
                    frame._mouseParked = true
                    lastMX, lastMY = nil, nil
                    frame:ClearAllPoints()
                    frame:SetPoint(pointFrom, UIParent, "BOTTOMLEFT", -10000, -10000)
                end
                return
            end
            -- Visible and unobstructed: ensure the glue rides the service (covers the visibility show edge and setup re-runs; resume snaps to the cursor via the lastMX reset).
            if frame._mouseParked or not glueActive then
                frame._mouseResume()
            end
            -- Mouse-through re-assert: the Decorate/Show/Cooldown path can re-enable mouse on
            -- icons mid-session, and an icon riding the cursor with mouse enabled intermittently
            -- kills [@mouseover] hovercast keys. MUST live here (0.15s, motion-independent) not in the glue: cooldown repaints re-enable mouse with the cursor perfectly still. Cheap no-op when state is clean.
            local icons = cdmBarIcons[key]
            if icons then
                for ii = 1, #icons do
                    local ic = icons[ii]
                    if ic then
                        if ic:IsMouseEnabled() then ic:EnableMouse(false) end
                        if ic.IsMouseMotionEnabled and ic:IsMouseMotionEnabled() then
                            ic:EnableMouseMotion(false)
                        end
                    end
                end
            end
        end
        Mouse.SubscribeTick(glueKey .. ":watch", 0.15, CursorWatch)
        CursorWatch()
    elseif anchorKey == "partyframe" then
        local partyFrame = EllesmereUI.FindPlayerPartyFrame()
        if partyFrame then
            frame:ClearAllPoints()
            local side = barData.partyFrameSide or "LEFT"
            local oX = barData.partyFrameOffsetX or 0
            local oY = barData.partyFrameOffsetY or 0
            do -- Additional Bar Offset stacks on the anchor's own offsets
                local aox, aoy = ns.CDMAddOffset(barData)
                oX, oY = oX + aox, oY + aoy
            end
            local PPa = EllesmereUI and EllesmereUI.PP
            if PPa and PPa.SnapForES then
                local es = frame:GetEffectiveScale()
                oX = PPa.SnapForES(oX, es)
                oY = PPa.SnapForES(oY, es)
            end
            local grow = barData.growDirection or "CENTER"
            local centered = barData.growCentered ~= false
            local fp = CDMFrameAnchorPoint(side, grow, centered)
            frame._anchorSide = side:upper()
            if side == "LEFT" then
                frame:SetPoint(fp, partyFrame, "LEFT", oX, oY)
            elseif side == "RIGHT" then
                frame:SetPoint(fp, partyFrame, "RIGHT", oX, oY)
            elseif side == "TOP" then
                frame:SetPoint(fp, partyFrame, "TOP", oX, oY)
            elseif side == "BOTTOM" then
                frame:SetPoint(fp, partyFrame, "BOTTOM", oX, oY)
            end
        else
            -- No party frame: fall back to saved position
            local pos = p.cdmBarPositions[key]
            if pos and pos.point then
                ApplyBarPositionCentered(frame, pos, key)
            else
                frame:ClearAllPoints()
                frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
        end
    elseif anchorKey == "playerframe" then
        local playerFrame = EllesmereUI.FindPlayerUnitFrame()
        if playerFrame then
            frame:ClearAllPoints()
            local side = barData.playerFrameSide or "LEFT"
            local oX = barData.playerFrameOffsetX or 0
            local oY = barData.playerFrameOffsetY or 0
            do -- Additional Bar Offset stacks on the anchor's own offsets
                local aox, aoy = ns.CDMAddOffset(barData)
                oX, oY = oX + aox, oY + aoy
            end
            local PPa = EllesmereUI and EllesmereUI.PP
            if PPa and PPa.SnapForES then
                local es = frame:GetEffectiveScale()
                oX = PPa.SnapForES(oX, es)
                oY = PPa.SnapForES(oY, es)
            end
            local grow = barData.growDirection or "CENTER"
            local centered = barData.growCentered ~= false
            local fp = CDMFrameAnchorPoint(side, grow, centered)
            frame._anchorSide = side:upper()
            if side == "LEFT" then
                frame:SetPoint(fp, playerFrame, "LEFT", oX, oY)
            elseif side == "RIGHT" then
                frame:SetPoint(fp, playerFrame, "RIGHT", oX, oY)
            elseif side == "TOP" then
                frame:SetPoint(fp, playerFrame, "TOP", oX, oY)
            elseif side == "BOTTOM" then
                frame:SetPoint(fp, playerFrame, "BOTTOM", oX, oY)
            end
        else
            -- No player frame: fall back to saved position
            local pos = p.cdmBarPositions[key]
            if pos and pos.point then
                ApplyBarPositionCentered(frame, pos, key)
            else
                frame:ClearAllPoints()
                frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
        end
    elseif anchorKey == "erb_castbar" or anchorKey == "erb_powerbar" or anchorKey == "erb_classresource" then
        -- Anchor to Resource Bars frames
        local erbFrameNames = {
            erb_castbar = "ERB_CastBarFrame",
            erb_powerbar = "ERB_PrimaryBar",
            erb_classresource = "ERB_SecondaryFrame",
        }
        local erbFrame = _G[erbFrameNames[anchorKey]]
        if erbFrame then
            local anchorPos = barData.anchorPosition or "left"
            frame:ClearAllPoints()
            local gap = barData.spacing or 2
            local oX = barData.anchorOffsetX or 0
            local oY = barData.anchorOffsetY or 0
            do -- Additional Bar Offset stacks on the anchor's own offsets
                local aox, aoy = ns.CDMAddOffset(barData)
                oX, oY = oX + aox, oY + aoy
            end
            local PPa = EllesmereUI and EllesmereUI.PP
            if PPa and PPa.SnapForES then
                local es = frame:GetEffectiveScale()
                gap = PPa.SnapForES(gap, es)
                oX = PPa.SnapForES(oX, es)
                oY = PPa.SnapForES(oY, es)
            end
            local grow = barData.growDirection or "CENTER"
            local centered = barData.growCentered ~= false
            local fp = CDMFrameAnchorPoint(anchorPos:upper(), grow, centered)
            frame._anchorSide = anchorPos:upper()
            local ok
            if anchorPos == "left" then
                ok = pcall(frame.SetPoint, frame, fp, erbFrame, "LEFT", -gap + oX, oY)
            elseif anchorPos == "right" then
                ok = pcall(frame.SetPoint, frame, fp, erbFrame, "RIGHT", gap + oX, oY)
            elseif anchorPos == "top" then
                ok = pcall(frame.SetPoint, frame, fp, erbFrame, "TOP", oX, gap + oY)
            elseif anchorPos == "bottom" then
                ok = pcall(frame.SetPoint, frame, fp, erbFrame, "BOTTOM", oX, -gap + oY)
            end
            -- Circular anchor: fall back to center
            if not ok then
                frame:ClearAllPoints()
                frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
        else
            -- ERB frame unavailable: fall back to saved position
            local pos = p.cdmBarPositions[key]
            if pos and pos.point then
                ApplyBarPositionCentered(frame, pos, key)
            else
                frame:ClearAllPoints()
                frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
        end
    else
        -- Unlock-anchored and already positioned: DO NOT touch the position. ApplyAnchorPosition/
        -- PropagateAnchorChain are authoritative there. A rebuild falling into the "no saved pos"
        -- branch below would teleport the bar to a hardcoded default (e.g. CENTER 0,-275), and if
        -- the anchor target is temporarily unavailable (hidden frame, pre-layout race) the later re-anchor bails and the bar stays stuck at that fallback.
        local unlockKey = "CDM_" .. key
        local anchored = EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored(unlockKey)
        if anchored and frame:GetLeft() then
            -- Unlock-anchored and already has bounds: leave position alone.
        else
            local pos = p.cdmBarPositions[key]
            if pos and pos.point then
                ApplyBarPositionCentered(frame, pos, key)
            elseif not anchored then
                -- Defaults: only for truly un-anchored bars with no saved pos.
                frame:ClearAllPoints()
                if key == "cooldowns" then
                    frame:SetPoint("CENTER", UIParent, "CENTER", 0, -275)
                elseif key == "utility" then
                    frame:SetPoint("CENTER", UIParent, "CENTER", 0, -320)
                elseif key == "buffs" then
                    frame:SetPoint("CENTER", UIParent, "CENTER", 0, -365)
                else
                    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
                end
            end
            -- Anchored with no bounds yet: NO fallback position. ReapplyOwnAnchor runs
            -- after BuildAllCDMBars and places the frame once the target is available.
        end
    end

    -- Always Show() so layout/children work; _CDMApplyVisibility is the single
    -- authority for alpha/hiding.
    frame:Show()
end

-- True when this bar renders data rows in REVERSED visual order: row growth "UP" (horizontal)/
-- "LEFT" (vertical) pins the trailing edge (BOTTOM/RIGHT), so the base (first data) row hugs it
-- and extra rows grow away. Shared by the layout and the options preview so both agree. ns.* field: 200-local cap.
function ns.CDMRowsReversed(barData)
    if not barData then return false end
    local grow = barData.growDirection or "CENTER"
    local isHoriz = (grow == "RIGHT" or grow == "LEFT"
        or (grow == "CENTER" and not barData.verticalOrientation))
    if isHoriz then return barData.rowGrowDirection == "UP" end
    return barData.rowGrowDirection == "LEFT"
end

-- Stride respecting the custom row-count override (numRows == 2 only). Two MUTUALLY EXCLUSIVE
-- overrides both resolve to the BASE row count -- the first DATA row: it fills first and is the
-- row a Row Growth pin keeps in place (on top normally, bottom/right when the visual row order is reversed):
--   * Custom Base Row Count -> topRowCount icons on the base row.
--   * Custom Bottom Row Count (UI removed) -> bottomRowCount icons on the second row; the base row gets the remainder.
-- Mutual exclusivity is enforced in options; if both are set, base wins.
local function ComputeTopRowStride(barData, count)
    local numRows = barData.numRows or 1
    if numRows < 1 then numRows = 1 end
    if numRows == 2 then
        local topCount
        if barData.customTopRowEnabled and barData.topRowCount and barData.topRowCount > 0 then
            topCount = math.min(barData.topRowCount, count)
        elseif barData.customBottomRowEnabled and barData.bottomRowCount and barData.bottomRowCount > 0 then
            topCount = count - math.min(barData.bottomRowCount, count)
        end
        if topCount then
            if topCount < 0 then topCount = 0 end
            local bottomCount = count - topCount
            -- Custom-row mode uses a second row only once BOTH rows are non-empty; until then report ONE effective row so the bar doesn't reserve or lay out an empty row.
            if bottomCount <= 0 or topCount <= 0 then
                return count, 1, count
            end
            return math.max(topCount, bottomCount), numRows, topCount
        end
    end
    local stride = math.ceil(count / numRows)
    local topCount = count - (numRows - 1) * stride
    if topCount < 0 then topCount = 0 end
    return stride, numRows, topCount
end

-- Minimum Bar Size, counted in icon slots along the GROWTH axis. That axis is ALWAYS the `stride`
-- term of the size formulas (width on horizontal bars, height on vertical), so one rule covers both
-- orientations. Returns the stride the CONTAINER reserves; the LAYOUT stride is never replaced --
-- grid wrapping (col = idx % stride) and per-row centering keep using the real icon count, and the
-- reserved surplus becomes a single centering offset. nil/0 (the default) is a straight passthrough.
local function ReserveStride(barData, stride)
    local minN = barData.minSizeIcons
    if minN and minN > stride then return minN end
    return stride
end

-- Empty custom bars still need a stable footprint so unlock mode can keep a visible mover and convert drag positions correctly before any icons exist.
local EMPTY_CDM_BAR_SIZE = { 100, 36 }

-- Count spell entries contributing real icon slots. Unlock mode uses this to estimate a footprint before the live frame has been laid out (common for freshly created Misc bars).
local function CountCDMBarSpells(barKey)
    local count = 0
    local sd = ns.GetBarSpellData(barKey)
    if not sd or not sd.assignedSpells then return 0 end
    for _, sid in ipairs(sd.assignedSpells) do
        if sid and sid ~= 0 then count = count + 1 end
    end
    return count
end

local function ComputeCDMBarSize(barData, count)
    -- Raw coord values -- see LayoutCDMBar for why we never pre-snap here.
    local iW = barData.iconSize or 36
    local iH = iW
    if (barData.iconShape or "none") == "cropped" then
        iH = math.floor((barData.iconSize or 36) * 0.80 + 0.5)
    end
    local sp = barData.spacing or 2
    -- EFFECTIVE row count from ComputeTopRowStride: collapses to 1 while a
    -- custom top-row split's second row is empty, so no empty row is reserved.
    local stride, rows = ComputeTopRowStride(barData, count)
    if rows < 1 then rows = 1 end
    -- Minimum Bar Size reserves extra growth-axis slots (no-op when unset). Unlike LayoutCDMBar
    -- there is no match gate here: this is the pre-layout footprint estimate, and a matched bar's live frame rect (checked first by GetStableCDMBarSize) always wins over it.
    local resStride = ReserveStride(barData, stride)
    local grow = barData.growDirection or "CENTER"
    local isH = (grow == "RIGHT" or grow == "LEFT" or grow == "CENTER")
    if isH then
        return resStride * iW + (resStride - 1) * sp,
               rows * iH + (rows - 1) * sp
    end
    return rows * iW + (rows - 1) * sp,
           resStride * iH + (resStride - 1) * sp
end

-- Authoritative footprint for unlock mode: live frame when it has bounds, else derived from bar config, else the stable empty-bar placeholder.
local function GetStableCDMBarSize(barKey, frame, barData)
    if frame then
        local w, h = frame:GetWidth() or 0, frame:GetHeight() or 0
        if w > 1 and h > 1 then
            return w, h
        end
    end

    local count = CountCDMBarSpells(barKey)
    if barData and count > 0 then
        return ComputeCDMBarSize(barData, count)
    end

    -- Buff-family/custom-buff bars have no assigned spells (icons are auras added live), so
    -- before the first aura count is 0. Size from one icon's configured dimensions so the empty frame -- and the unlock overlay mirroring it -- reflect icon size, not the generic placeholder.
    if barData and ((ns.IsBarBuffFamily and ns.IsBarBuffFamily(barData)) or barData.barType == "custom_buff") then
        return ComputeCDMBarSize(barData, 1)
    end

    return EMPTY_CDM_BAR_SIZE[1], EMPTY_CDM_BAR_SIZE[2]
end

-------------------------------------------------------------------------------
--  Layout icons within a CDM bar
-------------------------------------------------------------------------------
LayoutCDMBar = function(barKey)
    local frame = cdmBarFrames[barKey]
    local icons = cdmBarIcons[barKey]
    if not frame or not icons then return end

    local barData = barDataByKey[barKey]
    if not barData or not barData.enabled then return end

    -- A visibility-hidden cursor bar must NEVER be laid back on-screen: its glue is parked and
    -- cannot re-glue it. Park here instead; the visibility show edge re-runs LayoutCDMBar via its deferred call.
    if frame._mouseTrack and frame._visHidden then
        frame._mouseParked = true
        frame:ClearAllPoints()
        frame:SetPoint(frame._mousePoint or "LEFT", UIParent, "BOTTOMLEFT", -10000, -10000)
        return
    end

    -- Shift-Icons cd-state modes: shift-hidden icons are dropped from the layout entirely, so
    -- later icons close the gap and the bar resizes as if the icon were removed. Everything
    -- below (sizing, match math, slot positions) derives from this one array, so the filter IS
    -- the whole feature. Flags set by the cd-state evaluators (ns.SetCdStateShiftHidden) and by
    -- the buff route's Show When Missing active-hide (_missingActiveHidden);
    -- bars without either pay one field read per icon and never build the filtered table. Skipped frames keep their last point at alpha 0.
    do
        local filtered
        for i = 1, #icons do
            local sfc = _ecmeFC[icons[i]]
            if sfc and (sfc._cdStateShiftHidden or sfc._missingActiveHidden) then
                if not filtered then
                    filtered = {}
                    for j = 1, i - 1 do filtered[j] = icons[j] end
                end
            elseif filtered then
                filtered[#filtered + 1] = icons[i]
            end
        end
        if filtered then icons = filtered end
    end

    local grow = frame._mouseGrow or barData.growDirection or "CENTER"
    -- Row count comes from ComputeTopRowStride's EFFECTIVE rows (effRows, below), which
    -- collapses a custom top-row split to one row until its second row is populated.
    local isHoriz = (grow == "RIGHT" or grow == "LEFT" or (grow == "CENTER" and not barData.verticalOrientation))
    -- spacing is a raw coord value; the per-frame conversion below (spacingPx = floor(spacing /
    -- onePx + 0.5)) rounds to nearest whole physical pixel. Do NOT pre-snap with SnapForScale:
    -- PP.Scale truncates and can lose a pixel where PP.mult > 1 (spacing=2 -> 1.0667 coord = 1 px instead of 2).
    local spacing = barData.spacing or 2

    -- Width/height match: derive iconSize live from the SOURCE bar's current width on every
    -- layout pass. The source bar IS the truth, so reading it live auto-corrects across spec swaps, source resizes, etc. NOTHING is persisted, so cross-spec corruption is impossible.
    local extraPixels = 0
    local extraPixelsH = 0
    local widthMatchTarget = EllesmereUI.GetWidthMatchTarget
        and EllesmereUI.GetWidthMatchTarget("CDM_" .. barKey) or nil
    local heightMatchTarget = EllesmereUI.GetHeightMatchTarget
        and EllesmereUI.GetHeightMatchTarget("CDM_" .. barKey) or nil
    local PP = EllesmereUI.PP
    local onePx = PP.mult
    local iconW
    -- True ONLY when the width-match math below produces an iconW. Gates the cropped-height-from-matched-width path so non-matched and height-matched bars stay byte-identical.
    local widthMatchApplied = false
    -- Matched cropped height in physical px, set ONLY when the height-match math succeeds: a
    -- cropped height-matched bar's per-icon height then uses that (not the stored iconSize), staying in lockstep with the container's extraPixelsH leftover distribution.
    local heightMatchIconHPx = nil
    -- Width-axis dim (icons spanning the width). Effective row count, so a not-yet-populated second row doesn't widen the match math.
    local function CurWidthDim()
        local s, r = ComputeTopRowStride(barData, #icons)
        return isHoriz and s or r
    end
    -- Height-axis dim (icons spanning the height)
    local function CurHeightDim()
        local s, r = ComputeTopRowStride(barData, #icons)
        return isHoriz and r or s
    end
    -- Resolve a width/height match target unlock key to a live frame. The match DB stores keys like "CDM_cooldowns" or "MainBar"; the registered unlock element provides a getFrame() callback.
    local function GetMatchTargetFrame(targetKey)
        if not targetKey then return nil end
        local elems = EllesmereUI._unlockRegisteredElements
        local elem = elems and elems[targetKey]
        if elem and elem.getFrame then return elem.getFrame(targetKey) end
        return nil
    end
    if widthMatchTarget and #icons > 0 then
        local targetFrame = GetMatchTargetFrame(widthMatchTarget)
        local targetW = targetFrame and targetFrame:GetWidth() or 0
        local curDim = CurWidthDim()
        if targetW > 1 and curDim and curDim > 0 then
            local physTarget = math.floor(targetW / onePx + 0.5)
            local physSp = math.floor(spacing / onePx + 0.5)
            local rawPhysIcon = (physTarget - (curDim - 1) * physSp) / curDim
            if rawPhysIcon < 8 then rawPhysIcon = 8 end
            local basePhysIcon = math.floor(rawPhysIcon)
            iconW = basePhysIcon * onePx
            widthMatchApplied = true
            local idealPhys = curDim * basePhysIcon + (curDim - 1) * physSp
            local extra = physTarget - idealPhys
            if extra > 0 and extra <= curDim then extraPixels = extra end
        end
    elseif heightMatchTarget and #icons > 0 then
        local targetFrame = GetMatchTargetFrame(heightMatchTarget)
        local targetH = targetFrame and targetFrame:GetHeight() or 0
        local curDim = CurHeightDim()
        if targetH > 1 and curDim and curDim > 0 then
            local shape = barData.iconShape or "none"
            local cropFactor = (shape == "cropped") and 0.80 or 1.0
            local physTarget = math.floor(targetH / onePx + 0.5)
            local physSp = math.floor(spacing / onePx + 0.5)
            local rawPhysIcon = (physTarget - (curDim - 1) * physSp) / curDim / cropFactor
            if rawPhysIcon < 8 then rawPhysIcon = 8 end
            local basePhysIcon = math.floor(rawPhysIcon)
            iconW = basePhysIcon * onePx
            local basePhysIconH = math.floor(basePhysIcon * cropFactor)
            heightMatchIconHPx = basePhysIconH
            local idealPhys = curDim * basePhysIconH + (curDim - 1) * physSp
            local extra = physTarget - idealPhys
            if extra > 0 and extra <= curDim then extraPixelsH = extra end
        end
    end
    if not iconW then
        -- Not matched, or the target frame couldn't be read (early build, before the source bar
        -- exists): use the stored iconSize, a raw coord value rounded to whole physical px below. Do NOT pre-snap (see spacing).
        iconW = barData.iconSize or 36
    end

    local iconH = iconW
    local shape = barData.iconShape or "none"
    if shape == "cropped" then
        if widthMatchApplied then
            -- Width-matched: cropped height from the MATCHED icon width, so the icon keeps the
            -- same ~0.80 aspect as the non-matched path. Computed in physical px to stay on the
            -- pixel grid (matched iconW is already a clean pixel multiple). Aspect intent, not exact value: the non-matched branch rounds 0.80 in coord space, so the two can differ 1px at non-perfect scales.
            local wPx = math.floor(iconW / onePx + 0.5)
            iconH = math.floor(wPx * 0.80 + 0.5) * onePx
        elseif heightMatchIconHPx then
            -- Height-matched: the EXACT basePhysIconH the height-match math computed. MUST match precisely so per-icon height stays in lockstep with the container's extraPixelsH distribution.
            iconH = heightMatchIconHPx * onePx
        else
            iconH = math.floor((barData.iconSize or 36) * 0.80 + 0.5)
        end
    end

    -- ALL icons in the array, not just IsShown: CollectAndReanchor already filtered to frames we claimed, and Blizzard toggles IsShown independently -- we position everything we own.
    local visibleIcons = icons
    local count = #visibleIcons
    -- Icon count is the sole sizing authority. The count==0 early return below preserves the last known size during transients (spec swap, pool churn).
    local sizeCount = count
    if count == 0 then
        -- The bar's rect stays deliberately stale here (transient
        -- protection), so tell the aura-custom tail the TRUE content extent
        -- is zero and let it re-anchor (it centers on the bar's position
        -- instead of appending to the frozen edge).
        frame._acLiveW, frame._acLiveH = 0, 0
        if ns._AuraCustomPoke then ns._AuraCustomPoke(barKey) end
        local curW = frame:GetWidth() or 0
        local curH = frame:GetHeight() or 0
        if curW <= 1 or curH <= 1 then
            local fallbackW, fallbackH = GetStableCDMBarSize(barKey, nil, barData)
            -- EMPTY_CDM_BAR_SIZE is a raw coord-space placeholder; without snapping, often-empty buff-family bars render at non-pixel-aligned heights (43.20 px vs 43) at non-perfect UI scales.
            fallbackW = SnapForScale(fallbackW, 1)
            fallbackH = SnapForScale(fallbackH, 1)
            frame:SetSize(fallbackW, fallbackH)
            frame._prevLayoutW = fallbackW
            frame._prevLayoutH = fallbackH
        end
        -- NEVER permanently hide containers on a transient count=0 (spec swaps, viewer pool churn): the next reanchor refills the bar, and hiding would need an explicit re-show that nothing guarantees.
        if frame._barBg then frame._barBg:Hide() end
        return
    end

    -- effRows is the EFFECTIVE row count: 1 while a custom top-row split's second row is empty, so the container never grows a blank row.
    local stride, effRows, customTopCount = ComputeTopRowStride(barData, sizeCount)

    -- Container size: compute in integer physical pixels, convert to coord at the end. Multiplying
    -- in coord space then snapping loses 1 phys px to float dust (3 * 21.6666... floors to 81 instead of 82), leaving the bottom icon protruding past the bar frame.
    local PP = EllesmereUI.PP
    local onePx = PP.mult
    local iconWPx  = math.floor(iconW  / onePx + 0.5)
    local iconHPx  = math.floor(iconH  / onePx + 0.5)
    local spacingPx = math.floor(spacing / onePx + 0.5)
    -- Lock iconW/iconH/spacing to exact physical pixel multiples. Positioning (stepW, stepH) uses
    -- these coord values while the width-match math uses the iconWPx/spacingPx integers; out of
    -- lockstep, icons drift sub-pixel as col index grows -- spacing appears to "shrink" and the final icon undershoots the width-match target by 1 px.
    iconW   = iconWPx  * onePx
    iconH   = iconHPx  * onePx
    spacing = spacingPx * onePx

    -- Per-row icon size offset (Number of Rows == 2, non-matched only): one row takes an Icon
    -- Scale pixel offset, the other keeps the base size. The match target is re-checked here (not
    -- just at the options gate) so a bar matched AFTER the toggle stays uniform. Rows are centered against each other; the larger row defines the bar's growth-axis extent.
    local perRowActive = false
    local rowWPx = { iconWPx, iconWPx }   -- [1] = top row, [2] = bottom row
    local rowHPx = { iconHPx, iconHPx }
    if effRows == 2 and not widthMatchTarget and not heightMatchTarget
       and customTopCount > 0 and (sizeCount - customTopCount) > 0
       and (barData.customTopRowSizeEnabled or barData.customBottomRowSizeEnabled) then
        local base = barData.iconSize or 36
        local function RowSizePx(sz)
            if sz < 16 then sz = 16 end          -- clamp to the Icon Scale minimum
            local wpx = math.floor(sz / onePx + 0.5)
            local hCoord = (shape == "cropped") and math.floor(sz * 0.80 + 0.5) or sz
            local hpx = math.floor(hCoord / onePx + 0.5)
            return wpx, hpx
        end
        if barData.customTopRowSizeEnabled then
            rowWPx[1], rowHPx[1] = RowSizePx(base + (barData.topRowSizeOffset or 0))
        else
            rowWPx[2], rowHPx[2] = RowSizePx(base + (barData.bottomRowSizeOffset or 0))
        end
        perRowActive = true
    end

    -- Minimum Bar Size: reserve growth-axis room for at least minSizeIcons icon slots so a bar that
    -- loses icons (spec/talent swap, shift-hidden cooldowns) keeps its footprint -- everything
    -- matching its width or anchored to its edges then stays put, and the icons still present are
    -- centered in the surplus. SKIPPED while the GROWTH axis is match-owned: that axis measures
    -- exactly what the match target dictates and padding it would overshoot. A match on the
    -- PERPENDICULAR axis is fine -- the growth axis still varies with icon count there.
    local growMatched
    if isHoriz then growMatched = widthMatchTarget else growMatched = heightMatchTarget end
    local resStride = growMatched and stride or ReserveStride(barData, stride)
    -- What resStride real icons measure at the BASE icon size, spacing included. Integer physical px like every other term here, so both bar edges stay on the pixel grid.
    local reservedPx = 0
    if resStride > stride then
        local basePx = isHoriz and iconWPx or iconHPx
        reservedPx = resStride * basePx + (resStride - 1) * spacingPx
    end
    -- Offset that centers the real icon block inside the surplus (uniform layout only; the per-row branch centers each row inside the total already).
    local padOffsetPx = 0

    local totalWPx, totalHPx
    if perRowActive then
        -- Two rows, independent icon sizes. Top row = customTopCount icons, the bottom takes the
        -- remainder. The bar spans the LARGER row along the growth axis and the SUM of both bands along the perpendicular axis.
        local topN = customTopCount
        local botN = sizeCount - topN
        if isHoriz then
            local topRowW = topN * rowWPx[1] + math.max(0, topN - 1) * spacingPx
            local botRowW = botN * rowWPx[2] + math.max(0, botN - 1) * spacingPx
            totalWPx = math.max(topRowW, botRowW)
            -- No pad offset needed: both rows are centered against totalWPx below, so growing it IS the centering.
            if reservedPx > totalWPx then totalWPx = reservedPx end
            totalHPx = rowHPx[1] + rowHPx[2] + spacingPx
        else
            local topColH = topN * rowHPx[1] + math.max(0, topN - 1) * spacingPx
            local botColH = botN * rowHPx[2] + math.max(0, botN - 1) * spacingPx
            totalHPx = math.max(topColH, botColH)
            if reservedPx > totalHPx then totalHPx = reservedPx end
            totalWPx = rowWPx[1] + rowWPx[2] + spacingPx
        end
    elseif isHoriz then
        totalWPx = stride  * iconWPx + (stride  - 1) * spacingPx + extraPixels
        totalHPx = effRows * iconHPx + (effRows - 1) * spacingPx + extraPixelsH
        if reservedPx > totalWPx then
            padOffsetPx = math.floor((reservedPx - totalWPx) / 2 + 0.5)
            totalWPx = reservedPx
        end
    else
        totalWPx = effRows * iconWPx + (effRows - 1) * spacingPx + extraPixels
        totalHPx = stride  * iconHPx + (stride  - 1) * spacingPx + extraPixelsH
        if reservedPx > totalHPx then
            padOffsetPx = math.floor((reservedPx - totalHPx) / 2 + 0.5)
            totalHPx = reservedPx
        end
    end

    -- Do NOT force an even totalWPx for CENTER grow: SnapCenterForDim (used by ApplyBarPositionCentered
    -- for CENTER-anchored frames) puts the center on a half-pixel grid for odd dimensions, so both
    -- edges already land on whole physical pixels. A forced +1 pads the frame 1 px wider than the icon layout -- visible as the unlock overlay overhanging the last icon.

    local totalW = totalWPx * onePx
    local totalH = totalHPx * onePx
    frame._acLiveW, frame._acLiveH = totalW, totalH
    -- Poke the aura-custom tail EVERY pass: an empty->occupied transition
    -- can land on the SAME total size (1 buff returning to a 1-wide stale
    -- rect), which fires no size/point event -- the tail would stay in its
    -- empty-centered mode underneath the returning real icon.
    if ns._AuraCustomPoke then ns._AuraCustomPoke(barKey) end

    -- SetSize is deferred to AFTER icon positioning (below) so icons and bar resize land on the
    -- same rendered frame. Positioning first is safe: icons use absolute offsets from TOPLEFT, not the frame's current dimensions.
    local unlockKey = "CDM_" .. barKey
    -- Freeze buff-family bar size during unlock mode so the mover overlay stays in sync (it doesn't dynamically resize with buff count).
    local skipResize = EllesmereUI._unlockActive and ns.IsBarBuffFamily(barData)


    -- Bar background
    if barData.barBgEnabled then
        if not frame._barBg then
            frame._barBg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        end
        frame._barBg:ClearAllPoints()
        frame._barBg:SetPoint("TOPLEFT", 0, 0)
        frame._barBg:SetPoint("BOTTOMRIGHT", 0, 0)
        frame._barBg:SetColorTexture(barData.barBgR or 0, barData.barBgG or 0, barData.barBgB or 0, barData.barBgA or 0.5)
        frame._barBg:Show()
    elseif frame._barBg then
        frame._barBg:Hide()
    end

    -- Row growth "UP" (horizontal)/"LEFT" (vertical): reverse the VISUAL row order so the base
    -- (first data) row hugs the pinned trailing edge (BOTTOM/RIGHT) and extra rows grow away.
    -- Data-row semantics (fill order, per-row centering, icon counts, per-row sizes) are untouched
    -- -- only the perpendicular-axis offset flips. "DOWN"/"RIGHT" need no reversal: the TOPLEFT layout already keeps the pinned leading edge's row still.
    local rowsReversed = ns.CDMRowsReversed(barData)

    if perRowActive then
        -- Two-row layout with a per-row icon size offset: each row laid out at its own icon size,
        -- centered along the growth axis; the perpendicular axis stacks the two bands. No match extras -- gated off when matched.
        local isMouseBar = barData.anchorTo == "mouse"
        local topN = customTopCount
        for i, icon in ipairs(visibleIcons) do
            local iconScale = icon:GetScale() or 1
            if iconScale < 0.01 then iconScale = 1 end
            local iS = 1 / iconScale

            local rowIdx   = (i <= topN) and 1 or 2        -- 1 = top, 2 = bottom
            local idxInRow = (rowIdx == 1) and (i - 1) or (i - topN - 1)
            local rowN     = (rowIdx == 1) and topN or (sizeCount - topN)
            local wPx, hPx = rowWPx[rowIdx], rowHPx[rowIdx]

            FC(icon).matchExpanded = nil
            icon:SetSize(wPx * onePx * iS, hPx * onePx * iS)

            if isMouseBar then
                icon:SetFrameStrata("TOOLTIP")
                icon:SetFrameLevel(9980 + i)
            else
                icon:SetFrameStrata(barData.barStrata or "MEDIUM")
                icon:SetFrameLevel(5 + i)
            end
            icon:ClearAllPoints()

            local anchorX, anchorY
            if isHoriz then
                -- Growth axis = width (center the row within the bar width);
                -- perpendicular = height (top band, then bottom band).
                local rowMainPx = rowN * wPx + math.max(0, rowN - 1) * spacingPx
                local offMainPx = math.floor((totalWPx - rowMainPx) / 2 + 0.5)
                local xPx = offMainPx + idxInRow * (wPx + spacingPx)
                -- Reversed when rows grow upward: rowIdx 2 on top, 1 below.
                local yPx
                if rowsReversed then
                    yPx = (rowIdx == 2) and 0 or (rowHPx[2] + spacingPx)
                else
                    yPx = (rowIdx == 1) and 0 or (rowHPx[1] + spacingPx)
                end
                anchorX = (xPx * onePx) * iS
                anchorY = -(yPx * onePx) * iS
            else
                -- Growth axis = height (center the row within the bar height);
                -- perpendicular = width (left band, then right band).
                local rowMainPx = rowN * hPx + math.max(0, rowN - 1) * spacingPx
                local offMainPx = math.floor((totalHPx - rowMainPx) / 2 + 0.5)
                local yPx = offMainPx + idxInRow * (hPx + spacingPx)
                -- Reversed when columns grow leftward: rowIdx 2 at the left.
                local xPx
                if rowsReversed then
                    xPx = (rowIdx == 2) and 0 or (rowWPx[2] + spacingPx)
                else
                    xPx = (rowIdx == 1) and 0 or (rowWPx[1] + spacingPx)
                end
                anchorX = (xPx * onePx) * iS
                anchorY = -(yPx * onePx) * iS
            end

            local fd = _getFD(icon)
            if fd then
                fd._cdmAnchor = { "TOPLEFT", frame, "TOPLEFT", anchorX, anchorY }
            end
            icon:SetPoint("TOPLEFT", frame, "TOPLEFT", anchorX, anchorY)
        end
    else

    -- Uniform icon size: every bar except the 2-row per-row-size case above.
    local stepW = iconW + spacing
    local stepH = iconH + spacing
    -- Minimum Bar Size surplus in coord space: shifts the whole icon block along the GROWTH axis so it sits centered in the reserved footprint. 0 whenever the reservation is off or already filled.
    local padOffset = padOffsetPx * onePx

    local topRowCount = customTopCount
    if topRowCount < 0 then topRowCount = 0 end
    local bottomRowCount = #visibleIcons - topRowCount
    if bottomRowCount < 0 then bottomRowCount = 0 end

    -- Per-row centering: rows with fewer icons than stride get centered.
    local function RowIconCount(row)
        if row == 0 then return topRowCount end
        return bottomRowCount
    end

    -- Cursor-anchored bars need explicit icon strata: icons aren't parented to
    -- the container, so they don't inherit its TOOLTIP strata.
    local isMouseBar = barData.anchorTo == "mouse"

    -- Position each icon: fill bottom-up so bottom rows are full and the top row gets the
    -- remainder. "col"/"row" run along the bar's GROWTH axis -- horizontal: col = width-axis,
    -- row = height-axis; vertical: swapped. extraPixels expand iconW along the width axis for the
    -- first N icons; extraPixelsH expand iconH along the height axis. Only one match can be active, but the math handles both for symmetry.
    -- growthW = extras along the GROWTH axis (col index); growthH = extras along
    -- the PERPENDICULAR axis (row index).
    local growthW = isHoriz and extraPixels or extraPixelsH
    local growthH = isHoriz and extraPixelsH or extraPixels
    for i, icon in ipairs(visibleIcons) do
        -- Compensate for Blizzard's per-icon scale so visual size matches.
        local iconScale = icon:GetScale() or 1
        if iconScale < 0.01 then iconScale = 1 end
        local iS = 1 / iconScale

        -- Sequential index -> bottom-up grid position. Icons 1..topRowCount fill the top row (visual row 0); the rest fill rows 1..effRows-1.
        local col, row
        if i <= topRowCount then
            col = i - 1
            row = 0
        else
            local bottomIdx = i - topRowCount - 1
            col = bottomIdx % stride
            row = 1 + math.floor(bottomIdx / stride)
        end
        -- Visual row == data row unless row growth reverses the visual order (data row 0 renders on the pinned trailing edge). Data-row logic below (RowIconCount, expansion flags) keeps `row`.
        local vRow = rowsReversed and (effRows - 1 - row) or row

        -- +1 physical pixel on expanded icons: horizontal bars expand the WIDTH axis (iconW),
        -- vertical bars (col = height-axis) expand HEIGHT (iconH). Keeps icons square on the perpendicular axis.
        local onePx = PP.mult
        local expandedCol = (growthW > 0 and col < growthW)
        local expandedRow = (growthH > 0 and row < growthH)
        local thisIconW, thisIconH
        if isHoriz then
            thisIconW = expandedCol and (iconW + onePx) or iconW
            thisIconH = expandedRow and (iconH + onePx) or iconH
        else
            -- Vertical: col is the height-axis index, so col-extras expand iconH
            thisIconH = expandedCol and (iconH + onePx) or iconH
            thisIconW = expandedRow and (iconW + onePx) or iconW
        end
        FC(icon).matchExpanded = (expandedCol or expandedRow) or nil
        icon:SetSize(thisIconW * iS, thisIconH * iS)

        -- Cumulative offsets: each prior expanded icon shifts later icons by 1 physical pixel on
        -- the same axis (extraBefore = growth axis/col; extraBeforeR = perpendicular axis/row).
        -- extraBeforeR counts expanded rows VISUALLY before this one: expanded rows are data rows
        -- < growthH, so normal order has min(row, growthH) above, and reversed order has data rows in (row, effRows-1] above, of which max(0, min(growthH, effRows) - row - 1) are expanded.
        local extraBefore  = math.min(col, growthW) * onePx
        local extraBeforeR
        if rowsReversed then
            extraBeforeR = math.max(0, math.min(growthH, effRows) - row - 1) * onePx
        else
            extraBeforeR = math.min(row, growthH) * onePx
        end

        if isMouseBar then
            icon:SetFrameStrata("TOOLTIP")
            icon:SetFrameLevel(9980 + i)
        else
            icon:SetFrameStrata(barData.barStrata or "MEDIUM")
            icon:SetFrameLevel(5 + i)
        end
        icon:ClearAllPoints()

        local rowCount = RowIconCount(row)
        local rowHasLess = (rowCount > 0 and rowCount < stride)

        -- Offsets as absolute parent-space integers, divided by iconScale for SetPoint. NO per-position snapping: dividing integers by the same constant produces mathematically uniform gaps.
        local posX = col * stepW + extraBefore
        local posY = vRow * stepH

        -- Resolve anchor params first, then stamp fd._cdmAnchor BEFORE SetPoint: the SetPoint hook
        -- fires AFTER SetPoint and compares relativeTo against fd._cdmAnchor[2]; updated after, it
        -- reads a stale anchor (the previous bar) and snaps the icon ~50px wrong when moving a
        -- spell between bars. All growth directions use the same TOPLEFT icon layout; growth only affects which FRAME edge stays fixed during resize, never icon order.
        local anchorPt, anchorRelPt, anchorX, anchorY
        local rowOffset = 0
        if isHoriz then
            if rowHasLess then
                rowOffset = math.floor((stride - rowCount) * stepW / 2 + 0.5)
            end
            anchorPt, anchorRelPt = "TOPLEFT", "TOPLEFT"
            anchorX = (posX + rowOffset + padOffset) * iS
            anchorY = -(posY + extraBeforeR) * iS
        else
            if rowHasLess then
                rowOffset = math.floor((stride - rowCount) * stepH / 2 + 0.5)
            end
            anchorPt, anchorRelPt = "TOPLEFT", "TOPLEFT"
            anchorX = (vRow * stepW + extraBeforeR) * iS
            anchorY = -(col * stepH + extraBefore + rowOffset + padOffset) * iS
        end

        if anchorPt then
            -- Stamp BEFORE SetPoint so the synchronous hook sees the new anchor and treats our own SetPoint as a no-op.
            local fd = _getFD(icon)
            if fd then
                fd._cdmAnchor = { anchorPt, frame, anchorRelPt, anchorX, anchorY }
            end
            icon:SetPoint(anchorPt, frame, anchorRelPt, anchorX, anchorY)
        end
    end
    end  -- perRowActive vs uniform layout branch

    -- SetSize AFTER icon positioning: bar resize and icon placement land on the same rendered frame (no 1-frame size mismatch).
    if not skipResize then
        local oldW = frame:GetWidth() or 0
        local oldH = frame:GetHeight() or 0
        -- Pre-resize center in UIParent space, captured BEFORE SetSize (an edge-pointed frame
        -- moves its center when resized); the anchor offset upkeep below validates against it.
        -- Captured only when that upkeep can run (bar has an unlockAnchors entry): measuring a bar
        -- whose rect derives from a restricted tree HARD-ERRORS (FocusKick anchored to a nameplate
        -- in a locked instance), and such bars have no entry. pcall covers the residual case; an unknown center skips the upkeep.
        local oldCX, oldCY
        if EllesmereUIDB and EllesmereUIDB.unlockAnchors
           and EllesmereUIDB.unlockAnchors[unlockKey] then
            local ok, c1, c2 = pcall(frame.GetCenter, frame)
            if ok and c1 and c2 then
                local r = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
                oldCX, oldCY = c1 * r, c2 * r
            end
        end
        EllesmereUI._layoutBarResizing = unlockKey
        pcall(frame.SetSize, frame, totalW, totalH)
        EllesmereUI._layoutBarResizing = nil
        -- Anchor offset maintenance: a growth-direction resize shifts the center by delta/2 while
        -- the fixed edge stays put, so adjust the center-based anchor offset to keep the
        -- relationship on /reload. NOT a position write (positions save only via Save & Exit).
        -- Self-validating gate: the compensation is only correct when the PRE-resize center
        -- actually sat at the anchor-derived position (target center + stored offset on that
        -- axis). During a profile apply the bar still holds the OUTGOING profile's position while
        -- unlockAnchors carries the INCOMING offsets -- compensating that corrupts offsets
        -- cumulatively per swap, and layout passes can land before/inside/after any suppression
        -- window, so the position check is the only ordering-proof guard. A falsely skipped compensation costs at most one dw/2 nudge, fixed by the next reapply.
        local grow = barData.growDirection
        if grow and grow ~= "CENTER"
           and not EllesmereUI._unlockActive
           and not EllesmereUI._abAnchorSuppressed
           and (oldW >= 1 or oldH >= 1) then
            local adb = EllesmereUIDB and EllesmereUIDB.unlockAnchors
            local ai = adb and adb[unlockKey]
            if ai then
                local side = ai.side
                local PPo = EllesmereUI and EllesmereUI.PP
                local uiES = PPo and UIParent:GetEffectiveScale()
                local tCX, tCY
                if EllesmereUI.GetAnchorTargetCenterUI then
                    tCX, tCY = EllesmereUI.GetAnchorTargetCenterUI(unlockKey)
                end
                local TOL = 2  -- UI px; pixel-snap noise stays well under 1
                -- Width/height-matched bars: the match owns that axis, so the bar never
                -- legitimately self-resizes there. Any resize on a matched axis is the match
                -- (re)asserting the target's size -- the saved offset already corresponds to it, and compensating corrupts the offset by dw/2 per profile swap.
                local wMatched = EllesmereUIDB.unlockWidthMatch and EllesmereUIDB.unlockWidthMatch[unlockKey]
                local hMatched = EllesmereUIDB.unlockHeightMatch and EllesmereUIDB.unlockHeightMatch[unlockKey]
                -- Horizontal growth: adjust offsetX on TOP/BOTTOM anchors
                local dw = totalW - oldW
                if math.abs(dw) > 0.1 and (side == "TOP" or side == "BOTTOM")
                   and not wMatched
                   and oldCX and tCX
                   and math.abs(oldCX - (tCX + (ai.offsetX or 0))) <= TOL then
                    if grow == "RIGHT" then
                        ai.offsetX = ai.offsetX + dw / 2
                    elseif grow == "LEFT" then
                        ai.offsetX = ai.offsetX - dw / 2
                    end
                    if PPo and uiES then ai.offsetX = PPo.SnapForES(ai.offsetX, uiES) end
                end
                -- Vertical growth: adjust offsetY on LEFT/RIGHT anchors
                local dh = totalH - oldH
                if math.abs(dh) > 0.1 and (side == "LEFT" or side == "RIGHT")
                   and not hMatched
                   and oldCY and tCY
                   and math.abs(oldCY - (tCY + (ai.offsetY or 0))) <= TOL then
                    if grow == "DOWN" then
                        ai.offsetY = ai.offsetY - dh / 2
                    elseif grow == "UP" then
                        ai.offsetY = ai.offsetY + dh / 2
                    end
                    if PPo and uiES then ai.offsetY = PPo.SnapForES(ai.offsetY, uiES) end
                end
            end
        end
    end

    -- FocusKick: re-anchor against the focus nameplate after every layout pass so the bar tracks size/icon-count changes from the options panel.
    if barKey == FOCUSKICK_BAR_KEY and ns.ApplyFocusKickAnchor then
        ns.ApplyFocusKickAnchor()
    end
end

-- Shift-Icons cd-state modes: write the per-frame shift-hidden flag (on the external FC table,
-- NEVER the Blizzard frame) and, ONLY on a value change, relayout that bar so remaining icons
-- close the gap. Deferred to a clean execution context: callers run inside SetDesaturated hooks/
-- the Fake-Active poll, where LayoutCDMBar's SetSize/SetPoint could propagate taint (same pattern
-- as the _visHidden relayout in _CDMApplyVisibility). Coalesced per bar; steady-state calls return immediately.
--
-- Growth-edge preservation is LOCAL to this relayout call: capture the fixed growth edge before
-- LayoutCDMBar and, if the resize moved it, translate the frame back through whatever point it
-- already has (offset-only SetPoint on the existing point/relTo -- no ClearAllPoints, no DB
-- writes, no anchor-system calls). A non-CENTER-grow bar's persistent point normally IS its fixed
-- growth edge (delta 0, frame untouched); this only corrects bars whose point is center/corner-
-- based at that moment (anchored bars mid-cascade, first-row corner pins, legacy CENTER
-- positions). Anchored bars still get their deferred anchor batch reapply afterwards (OnSizeChanged fired during LayoutCDMBar), which remains authoritative.
ns._cdShiftLayoutPending = {}
function ns.SetCdStateShiftHidden(fc, shiftHidden)
    shiftHidden = shiftHidden or false
    if (fc._cdStateShiftHidden or false) == shiftHidden then return end
    fc._cdStateShiftHidden = shiftHidden
    -- Overflow-diverted frames render on the target bar, so the gap-close relayout must hit the
    -- bar the frame is actually laid out on. Normally unreachable for diverted frames (Phase 3b's no-op rule), but a one-reanchor window exists after a shift effect is first configured.
    local bk = fc._overflowLayoutBar or fc.barKey
    if not bk or ns._cdShiftLayoutPending[bk] then return end
    ns._cdShiftLayoutPending[bk] = true
    C_Timer.After(0, function()
        ns._cdShiftLayoutPending[bk] = nil
        local frame = cdmBarFrames[bk]
        local bd = barDataByKey[bk]
        local grow = bd and bd.growDirection or "CENTER"
        local fixedEdge
        if frame and grow ~= "CENTER"
           and not frame._mouseTrack and bk ~= ns.FOCUSKICK_BAR_KEY
           and not EllesmereUI._unlockActive
           and frame:GetNumPoints() == 1 then
            if grow == "LEFT" then fixedEdge = frame:GetRight()
            elseif grow == "RIGHT" then fixedEdge = frame:GetLeft()
            elseif grow == "UP" then fixedEdge = frame:GetBottom()
            elseif grow == "DOWN" then fixedEdge = frame:GetTop() end
        end
        LayoutCDMBar(bk)
        if fixedEdge then
            local newEdge
            if grow == "LEFT" then newEdge = frame:GetRight()
            elseif grow == "RIGHT" then newEdge = frame:GetLeft()
            elseif grow == "UP" then newEdge = frame:GetBottom()
            else newEdge = frame:GetTop() end
            local d = newEdge and (newEdge - fixedEdge)
            if d and (d > 0.25 or d < -0.25) then
                local point, relTo, relPoint, x, y = frame:GetPoint(1)
                if point then
                    if grow == "LEFT" or grow == "RIGHT" then
                        x = (x or 0) - d
                    else
                        y = (y or 0) - d
                    end
                    frame:SetPoint(point, relTo or frame:GetParent(), relPoint, x, y)
                end
            end
        end
    end)
end

-------------------------------------------------------------------------------
--  Toggle Blizzard CDM Settings. Hides the EllesmereUI options panel first so
--  the Blizzard UI is visible. NEVER call SetCurrentCategories /
--  SetDisplayMode / ClearDisplayCategories after opening -- those taint the
--  CDM frame pool (so isBuff cannot actually select a tab).
-------------------------------------------------------------------------------
local function OpenBlizzardCDMTab(isBuff)
    if not CooldownViewerSettings then return end
    if EllesmereUI._mainFrame and EllesmereUI._mainFrame:IsShown() then
        EllesmereUI._mainFrame:Hide()
    end
    if CooldownViewerSettings:IsShown() then
        CooldownViewerSettings:Hide()
    else
        CooldownViewerSettings:Show()
    end
end
ns.OpenBlizzardCDMTab = OpenBlizzardCDMTab

-------------------------------------------------------------------------------
--  CDM Tooltip System
--  No OnUpdate polling: Blizzard viewer frames handle their own tooltips via
--  native OnEnter; custom injected frames (item presets, racials, custom
--  spells) get OnEnter/OnLeave scripts in DecorateFrame / preset creation.
-------------------------------------------------------------------------------
local _tooltipBars = {}  -- [barKey] = true for bars with tooltips enabled
local _tooltipFrame = CreateFrame("Frame")
_tooltipFrame:Hide()

local function ApplyCDMTooltipState(barKey)
    local bd = barDataByKey[barKey]
    local enabled = bd and bd.showTooltip
    if enabled then
        _tooltipBars[barKey] = true
    else
        _tooltipBars[barKey] = nil
        -- Clear a tooltip showing for an icon on this bar
        if _tooltipCurrentIcon then
            local sfc = _ecmeFC[_tooltipCurrentIcon]
            if sfc and sfc.barKey == barKey then
                GameTooltip:Hide()
                _tooltipCurrentIcon = nil
            end
        end
    end
    -- Mouse-motion follows the tooltip setting. A motion-enabled icon with no unit becomes the
    -- mouseover-focus frame and steals hover from unit frames underneath (raid frame hover
    -- highlight and [@mouseover] casts die wherever a bar overlaps them), so icons may ONLY
    -- capture the mouse when tooltips are on. Cursor-anchored bars stay fully mouse-through
    -- (SetFrameClickThrough owns their state); vis-hidden bars stay inert. Mouse calls on Blizzard CDM frames are blocked in combat.
    if not InCombatLockdown() then
        local frame = cdmBarFrames[barKey]
        local wantHover = (enabled and frame and not frame._mouseTrack
            and not frame._visHidden) and true or false
        local icons = cdmBarIcons[barKey]
        if icons then
            for i = 1, #icons do
                local ic = icons[i]
                if ic and ic.EnableMouseMotion then
                    -- Invisible placeholders are excluded even with tooltips on: an
                    -- alpha-0 slot has no art to hover, so capturing here would only
                    -- take mouseover away from whatever the bar sits over.
                    ic:EnableMouseMotion(wantHover and not IsPlaceholderRenderHidden(ic, bd))
                end
            end
        end
    end
    -- Global tooltip frame follows whether ANY bar wants tooltips
    if next(_tooltipBars) then
        _tooltipFrame:Show()
    else
        _tooltipFrame:Hide()
    end
end
ns.ApplyCDMTooltipState = ApplyCDMTooltipState

-------------------------------------------------------------------------------
--  Apply custom shape to a CDM icon
-------------------------------------------------------------------------------
ApplyShapeToCDMIcon = function(icon, shape, barData, ssb)
    if not icon then return end
    local fd = _getFD(icon)
    local tex = fd and fd.tex or icon._tex
    local cd = fd and fd.cooldown or icon._cooldown
    local bg = fd and fd.bg or icon._bg
    local zoom = barData.iconZoom or 0.08
    local borderSz = barData.borderSize or 1
    local brdR = barData.borderR or 0
    local brdG = barData.borderG or 0
    local brdB = barData.borderB or 0
    local brdA = barData.borderA or 1
    if barData.borderClassColor then
        local cc = _playerClass and RAID_CLASS_COLORS[_playerClass]
        if cc then brdR, brdG, brdB = cc.r, cc.g, cc.b end
    end
    -- Per-icon Border override (buff-family bars): size + color only, NEVER style. ssb is the
    -- resolved per-icon settings from RefreshCDMIconAppearance; nil for cd/utility bars and
    -- uncustomized icons, so this no-ops unless a buff icon has a per-icon border. Feeds both the square (ApplyBorderStyle) and shaped (shapeBorder) paths below.
    if ssb then
        if ssb.borderSize ~= nil then borderSz = ssb.borderSize end
        if ssb.borderR ~= nil then brdR = ssb.borderR end
        if ssb.borderG ~= nil then brdG = ssb.borderG end
        if ssb.borderB ~= nil then brdB = ssb.borderB end
    end

    local ifc = FC(icon)
    if shape == "none" or shape == "cropped" or not shape then
        -- Remove shape mask if previously applied
        if ifc.shapeMask then
            local mask = ifc.shapeMask
            if tex then pcall(tex.RemoveMaskTexture, tex, mask) end
            if bg then pcall(bg.RemoveMaskTexture, bg, mask) end
            if cd then pcall(cd.RemoveMaskTexture, cd, mask) end
            mask:SetTexture(nil); mask:ClearAllPoints(); mask:SetSize(0.001, 0.001); mask:Hide()
        end
        if ifc.shapeBorder then ifc.shapeBorder:Hide() end
        ifc.shapeApplied = nil
        ifc.shapeName = nil

        -- Restore square borders (PP or textured via ApplyBorderStyle). The border lives on
        -- fd.borderFrame (child of icon) so Blizzard's secure frames are never tainted; PP.GetBorders(icon) is the fallback for CDM-owned frames that skip DecorateFrame's child wrapper.
        local bdrTarget = (fd and fd.borderFrame) or icon
        if fd and fd.borderFrame or EllesmereUI.PP.GetBorders(icon) then
            local texKey = barData.borderTexture or "solid"
            -- "Show Behind": set the border frame's level BEFORE styling so the
            -- textured backdrop inherits it. +13 = in front, level-1 = behind.
            if fd and fd.borderFrame then
                fd.borderFrame:SetFrameLevel(barData.borderBehind and math.max(0, icon:GetFrameLevel() - 1) or (icon:GetFrameLevel() + 13))
            end
            EllesmereUI.ApplyBorderStyle(bdrTarget, borderSz, brdR, brdG, brdB, brdA, texKey, barData.borderTextureOffset, barData.borderTextureOffsetY, barData.borderTextureShiftX, barData.borderTextureShiftY, "cdm", barData.borderThickness or "thin", true)
        end

        -- Restore icon texture, filling the entire frame: PP.CreateBorder renders the border on top, so no inset is needed.
        if tex then
            tex:ClearAllPoints()
            tex:SetAllPoints(icon)
            local extraCrop = 0
            if ifc.matchExpanded then
                local baseW = barData.iconSize or 36
                extraCrop = (1 - 2 * zoom) / (2 * (baseW + 1))
            end
            if shape == "cropped" then
                -- Cropped applies a heavy vertical TexCoord crop. With default pixel/texel
                -- snapping the cropped image edge can round to a different physical pixel than
                -- the unsnapped cooldown swipe (1px swipe/icon split at some effective scales), so snapping is disabled to render the exact rect. No size change.
                if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(false) end
                if tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(0) end
                tex:SetTexCoord(zoom, 1 - zoom, zoom + 0.10 + extraCrop, 1 - zoom - 0.10 - extraCrop)
            else
                -- Restore default grid snapping so an icon switched away from cropped stays crisp.
                if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(true) end
                tex:SetTexCoord(zoom, 1 - zoom, zoom + extraCrop, 1 - zoom - extraCrop)
            end
        end

        -- Restore cooldown: full frame so the swipe covers the entire icon
        if cd then
            cd:ClearAllPoints()
            cd:SetAllPoints(icon)
            pcall(cd.SetSwipeTexture, cd, "Interface\\AddOns\\EllesmereUI\\media\\white-square.png")
            if cd.SetUseCircularEdge then pcall(cd.SetUseCircularEdge, cd, false) end
        end

        -- Restore background
        if bg then
            bg:ClearAllPoints(); bg:SetAllPoints()
        end
        return
    end

    -- Custom shape
    local maskTex = CDM_SHAPES.masks[shape]
    if not maskTex then return end

    if not ifc.shapeMask then
        ifc.shapeMask = icon:CreateMaskTexture()
    end
    local mask = ifc.shapeMask
    mask:SetTexture(maskTex, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:Show()

    -- Remove existing mask refs before re-adding
    if tex then pcall(tex.RemoveMaskTexture, tex, mask) end
    if bg then pcall(bg.RemoveMaskTexture, bg, mask) end
    if cd then pcall(cd.RemoveMaskTexture, cd, mask) end
    if icon.OutOfRange then pcall(icon.OutOfRange.RemoveMaskTexture, icon.OutOfRange, mask) end

    -- Apply mask to icon texture, background, and OutOfRange overlay
    if tex then tex:AddMaskTexture(mask) end
    if bg then bg:AddMaskTexture(mask) end
    if icon.OutOfRange then
        local oor = icon.OutOfRange
        pcall(oor.RemoveMaskTexture, oor, mask)
        pcall(oor.AddMaskTexture, oor, mask)
    end

    -- Expand icon beyond frame for shape
    local shapeOffset = CDM_SHAPES.iconExpandOffsets[shape] or 0
    local shapeDefault = CDM_SHAPES.zoomDefaults[shape] or 0.06
    local iconExp = CDM_SHAPES.iconExpand + shapeOffset + ((zoom - shapeDefault) * 200)
    if iconExp < 0 then iconExp = 0 end
    local halfIE = iconExp / 2
    if tex then
        tex:ClearAllPoints()
        EllesmereUI.PP.Point(tex, "TOPLEFT", icon, "TOPLEFT", -halfIE, halfIE)
        EllesmereUI.PP.Point(tex, "BOTTOMRIGHT", icon, "BOTTOMRIGHT", halfIE, -halfIE)
    end

    -- Mask position (inset for border)
    mask:ClearAllPoints()
    if borderSz >= 1 then
        EllesmereUI.PP.Point(mask, "TOPLEFT", icon, "TOPLEFT", 1, -1)
        EllesmereUI.PP.Point(mask, "BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
    else
        mask:SetAllPoints(icon)
    end

    -- Expand texcoords for shape
    local insetPx = CDM_SHAPES.insets[shape] or 17
    local visRatio = (128 - 2 * insetPx) / 128
    local expand = ((1 / visRatio) - 1) * 0.5
    if tex then tex:SetTexCoord(-expand, 1 + expand, -expand, 1 + expand) end

    -- Hide square borders (both PP and textured)
    local bdrTarget2 = (fd and fd.borderFrame) or icon
    if fd and fd.borderFrame or EllesmereUI.PP.GetBorders(icon) then
        EllesmereUI.PP.HideBorder(bdrTarget2)
        if EllesmereUI._bdBorderData then
            local bdFrame = EllesmereUI._bdBorderData[bdrTarget2]
            if bdFrame then bdFrame:Hide() end
        end
    end

    -- Shape border texture (on a dedicated frame above the cooldown swipe)
    if not ifc.shapeBorderFrame then
        local sbf = CreateFrame("Frame", nil, icon)
        sbf:SetAllPoints(icon)
        sbf:SetFrameLevel(icon:GetFrameLevel() + 2)
        ifc.shapeBorderFrame = sbf
    end
    ifc.shapeBorderFrame:SetFrameLevel(icon:GetFrameLevel() + 2)
    if not ifc.shapeBorder then
        ifc.shapeBorder = ifc.shapeBorderFrame:CreateTexture(nil, "OVERLAY", nil, 6)
    end
    local borderTex = ifc.shapeBorder
    borderTex:ClearAllPoints()
    borderTex:SetAllPoints(icon)
    if borderSz > 0 and CDM_SHAPES.borders[shape] then
        borderTex:SetTexture(CDM_SHAPES.borders[shape])
        borderTex:SetVertexColor(brdR, brdG, brdB, brdA)
        borderTex:SetSnapToPixelGrid(false)
        borderTex:SetTexelSnappingBias(0)
        borderTex:Show()
    else
        borderTex:Hide()
    end

    -- Apply mask to cooldown so swipe follows shape
    if cd then
        cd:ClearAllPoints()
        cd:SetAllPoints(icon)
        pcall(cd.AddMaskTexture, cd, mask)
        if cd.SetSwipeTexture then
            pcall(cd.SetSwipeTexture, cd, maskTex)
        end
        local useCircular = (shape ~= "square" and shape ~= "csquare")
        if cd.SetUseCircularEdge then pcall(cd.SetUseCircularEdge, cd, useCircular) end
        local edgeScale = CDM_SHAPES.edgeScales[shape] or 0.60
        if cd.SetEdgeScale then pcall(cd.SetEdgeScale, cd, edgeScale) end
    end

    -- Restore background to full icon
    if bg then
        bg:ClearAllPoints(); bg:SetAllPoints()
    end

    ifc.shapeApplied = true
    ifc.shapeName = shape
end
ns.ApplyShapeToCDMIcon = ApplyShapeToCDMIcon

-------------------------------------------------------------------------------
--  Mirror an icon's custom shape onto a fake-active overlay's own icon + swipe
-------------------------------------------------------------------------------
-- The CDM "fake active" engine (EllesmereUICdmFakeActive.lua) draws its own saturated icon +
-- swipe over a CDM icon during a custom active window. The overlay MUST copy the underlying
-- icon's custom shape or a square icon/swipe is drawn over the shaped icon and the mask looks
-- broken. Reuses the underlying shapeMask: masking is screen-space and the overlay covers the same region, so one mask serves both. A none/cropped shape clears any mask we added and restores a plain square swipe.
function ns.ApplyShapeToOverlay(icon, oIcon, oCd, barData)
    if not icon then return end
    local ifc = FC(icon)
    local mask = ifc.shapeMask
    local shape = ifc.shapeApplied and ifc.shapeName or nil

    -- Drop mask refs we added before (the shape may have changed / cleared).
    if mask then
        if oIcon then pcall(oIcon.RemoveMaskTexture, oIcon, mask) end
        if oCd then pcall(oCd.RemoveMaskTexture, oCd, mask) end
    end

    local maskTex = shape and CDM_SHAPES.masks[shape]
    if not shape or shape == "none" or shape == "cropped" or not mask or not maskTex then
        -- Square overlay. IconTexture already copied the underlying texcoords.
        if oIcon then oIcon:ClearAllPoints(); oIcon:SetAllPoints(oIcon:GetParent()) end
        if oCd then
            pcall(oCd.SetSwipeTexture, oCd, "Interface\\AddOns\\EllesmereUI\\media\\white-square.png")
            if oCd.SetUseCircularEdge then pcall(oCd.SetUseCircularEdge, oCd, false) end
        end
        return
    end

    local zoom = (barData and barData.iconZoom) or 0.08

    -- Match the underlying tex geometry: point-expand + texcoord-expand.
    local shapeOffset  = CDM_SHAPES.iconExpandOffsets[shape] or 0
    local shapeDefault = CDM_SHAPES.zoomDefaults[shape] or 0.06
    local iconExp = CDM_SHAPES.iconExpand + shapeOffset + ((zoom - shapeDefault) * 200)
    if iconExp < 0 then iconExp = 0 end
    local halfIE = iconExp / 2
    if oIcon then
        oIcon:ClearAllPoints()
        EllesmereUI.PP.Point(oIcon, "TOPLEFT", icon, "TOPLEFT", -halfIE, halfIE)
        EllesmereUI.PP.Point(oIcon, "BOTTOMRIGHT", icon, "BOTTOMRIGHT", halfIE, -halfIE)
        local insetPx = CDM_SHAPES.insets[shape] or 17
        local visRatio = (128 - 2 * insetPx) / 128
        local expand = ((1 / visRatio) - 1) * 0.5
        oIcon:SetTexCoord(-expand, 1 + expand, -expand, 1 + expand)
        oIcon:AddMaskTexture(mask)
    end
    if oCd then
        oCd:ClearAllPoints()
        oCd:SetAllPoints(icon)
        pcall(oCd.AddMaskTexture, oCd, mask)
        if oCd.SetSwipeTexture then pcall(oCd.SetSwipeTexture, oCd, maskTex) end
        local useCircular = (shape ~= "square" and shape ~= "csquare")
        if oCd.SetUseCircularEdge then pcall(oCd.SetUseCircularEdge, oCd, useCircular) end
        local edgeScale = CDM_SHAPES.edgeScales[shape] or 0.60
        if oCd.SetEdgeScale then pcall(oCd.SetEdgeScale, oCd, edgeScale) end
    end
end

-------------------------------------------------------------------------------
--  Style a fake-active overlay's own countdown number to match Duration Text
-------------------------------------------------------------------------------
local COOLDOWN_TEXT_POINTS = {
    center = { "CENTER", "CENTER", "CENTER" },
    top = { "BOTTOM", "TOP", "CENTER" },
    bottom = { "TOP", "BOTTOM", "CENTER" },
    left = { "RIGHT", "LEFT", "RIGHT" },
    right = { "LEFT", "RIGHT", "LEFT" },
}

function ns.AnchorCooldownText(text, owner, position, x, y)
    local points = COOLDOWN_TEXT_POINTS[position] or COOLDOWN_TEXT_POINTS.center
    text:ClearAllPoints()
    text:SetPoint(points[1], owner, points[2], x or 0, y or 0)
    text:SetJustifyH(points[3])
end

-- Does this bar show Duration Text? The options row treats the key as ON
-- unless it is explicitly false, so every renderer must too: read bare, a bar
-- whose key was never written (imported profile, RPT sync, a strip the login
-- merge did not refill) shows the toggle ON and draws no numbers.
function ns.CdmDurationTextOn(bd)
    return bd ~= nil and bd.showCooldownText ~= false
end

-- Stack/charge/item-count text anchor. Bottom-anchored positions keep the
-- historical +2 nudge so existing bars stay pixel-identical. Shared with the
-- custom-aura renderer (EllesmereUICdmHooks) so both land on the same anchor.
function ns.CdmStackAnchorPoint(position, y)
    y = y or 0
    if position == "bottomleft" then return "BOTTOMLEFT", y + 2 end
    if position == "bottom" then return "BOTTOM", y + 2 end
    if position == "topright" then return "TOPRIGHT", y end
    if position == "top" then return "TOP", y end
    if position == "topleft" then return "TOPLEFT", y end
    if position == "center" then return "CENTER", y end
    if position == "left" then return "LEFT", y end
    if position == "right" then return "RIGHT", y end
    return "BOTTOMRIGHT", y + 2
end

-- The overlay (EllesmereUICdmFakeActive.lua) runs its own Cooldown widget whose
-- number would otherwise use Blizzard's default font. Mirrors the Duration Text
-- styling the real icon gets in RefreshCDMIconAppearance: font, size
-- (scale-compensated), colour, position, offset, show/hide. ssb is the resolved
-- per-icon settings, falling back to the bar's (nil is fine). Call AFTER
-- SetCooldown so Blizzard's countdown FontString exists.
function ns.StyleOverlayCooldownText(oCd, barData, ssb, iconScale)
    if not oCd then return end
    iconScale = iconScale or 1
    if iconScale < 0.01 then iconScale = 1 end
    local fontScale = 1 / iconScale
    local showCD = ns.CdmDurationTextOn(barData)
    if ssb and ssb.showCooldownText ~= nil then showCD = ssb.showCooldownText end
    oCd:SetHideCountdownNumbers(not showCD)
    if not showCD then return end
    local cdFont = GetCDMFont()
    local cdSize = ((ssb and ssb.cooldownFontSize) or (barData and barData.cooldownFontSize) or 12) * fontScale
    local cdR = (ssb and ssb.cooldownTextR) or (barData and barData.cooldownTextR) or 1
    local cdG = (ssb and ssb.cooldownTextG) or (barData and barData.cooldownTextG) or 1
    local cdB = (ssb and ssb.cooldownTextB) or (barData and barData.cooldownTextB) or 1
    local cdPosition = (ssb and ssb.cooldownTextPosition)
        or (barData and barData.cooldownTextPosition) or "center"
    local cdX = (ssb and ssb.cooldownTextX) or (barData and barData.cooldownTextX) or 0
    local cdY = (ssb and ssb.cooldownTextY) or (barData and barData.cooldownTextY) or 0
    for _, rgn in pairs({ oCd:GetRegions() }) do
        if rgn and rgn.GetObjectType and rgn:GetObjectType() == "FontString" then
            EllesmereUI.ApplyIconTextFont(rgn, cdFont, cdSize, "cdm")
            rgn:SetTextColor(cdR, cdG, cdB)
            ns.AnchorCooldownText(rgn, oCd, cdPosition, cdX, cdY)
        end
    end
end

-------------------------------------------------------------------------------
--  Per-spell Threshold Text (engine countdown formatters)
--
--  "Threshold Seconds" arms the feature per spell; below that many seconds
--  remaining the countdown can show one decimal ("2.7") and/or change color.
--  Rendered by a NumericRuleFormatter attached to the icon's Cooldown widget via
--  SetCountdownFormatter: the ENGINE formats the number (no OnUpdate, no
--  per-tick Lua), it covers whatever the widget displays (cooldown, recharge,
--  aura duration, fake-active window), and it evaluates engine-side so SECRET
--  durations format fine. The color change rides IN the format string (color
--  escape wrap), so no text-color swapping at the threshold edge. Formatters are
--  immutable per config and shared: one instance per distinct (seconds,
--  decimals, color) tuple, attached to any number of cooldowns.
-------------------------------------------------------------------------------
do
    local formatters = {}       -- [signature] = engine formatter object
    local formatterCount = 0
    local unsupported = false   -- API probe failed once -> feature stays inert
    -- Which formatter a cooldown currently has attached, so the refresh pass only touches widgets
    -- it manages (the all-off case is one weak-table read). Weak keys: pooled frames drop out on their own. State lives HERE, never on the frames (many are Blizzard-owned).
    local attached = setmetatable({}, { __mode = "k" })

    local function BuildFormatter(seconds, dec, col, r, g, b)
        if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter
            and Enum.NumericRuleFormatRounding) then
            return nil
        end
        local Up = Enum.NumericRuleFormatRounding.Up
        local Nearest = Enum.NumericRuleFormatRounding.Nearest
        local function Wrap(fmt)
            if not col then return fmt end
            return CreateColor(r, g, b, 1):WrapTextInColorCode(fmt)
        end
        local points = {}
        if dec then
            -- One decimal below the threshold, whole seconds above it.
            points[#points + 1] = { threshold = 0, format = Wrap("%.1f"), rounding = Nearest }
        else
            -- Color-only: same whole-second text, wrapped below the threshold.
            points[#points + 1] = { threshold = 0, format = Wrap("%d"), rounding = Up, step = 1 }
        end
        points[#points + 1] = { threshold = seconds, format = "%d", rounding = Up, step = 1 }
        -- Larger units. Thresholds sit just above the unit boundary so an UP-rounded value in
        -- (59, 60] routes into the m:ss breakpoint rather than reading "60" for a moment (same for hours and days).
        points[#points + 1] = {
            threshold = 59.0001, format = "%d:%02d", rounding = Up, step = 1,
            components = { { div = 60 }, { mod = 60 } },
        }
        points[#points + 1] = {
            threshold = 3599.0001, format = "%dh", rounding = Up, step = 1,
            components = { { div = 3600 } },
        }
        points[#points + 1] = {
            threshold = 86399.0001, format = "%dd", rounding = Up, step = 1,
            components = { { div = 86400 } },
        }
        local f = C_StringUtil.CreateNumericRuleFormatter()
        local ok = pcall(f.SetBreakpoints, f, points)
        if not ok then return nil end
        return f
    end

    -- Resolve a settings block's threshold config to a shared formatter, or nil when off. ss may
    -- be a per-spell family entry (tier-chained), a customActiveStates entry, or nil. Explicit false (tier blocking) reads as off through the tonumber/== true checks.
    local function FormatterFor(ss)
        if not ss then return nil end
        local seconds = tonumber(ss.thresholdSeconds) or 0
        if seconds <= 0 then return nil end
        if seconds > 59 then seconds = 59 end
        local dec = ss.thresholdDecimals == true
        local col = ss.thresholdColorEnabled == true
        if not (dec or col) then return nil end
        local r, g, b = 1, 0.2, 0.2
        if col then
            r = ss.thresholdColorR or 1
            g = ss.thresholdColorG or 0.2
            b = ss.thresholdColorB or 0.2
        end
        local sig = string.format("%d|%s|%s", seconds, dec and "1" or "0",
            col and string.format("%.3f,%.3f,%.3f", r, g, b) or "0")
        local f = formatters[sig]
        if f == nil and not unsupported then
            -- Live color-picker drags mint a config per tick, so cap the lookup. Attached widgets keep their instances alive; evicted configs rebuild on demand.
            if formatterCount > 64 then
                formatters = {}
                formatterCount = 0
            end
            f = BuildFormatter(seconds, dec, col, r, g, b)
            if f then
                formatters[sig] = f
                formatterCount = formatterCount + 1
            else
                unsupported = true
            end
        end
        return f
    end

    -- Attach or clear the resolved formatter on one Cooldown widget. Touches the widget only on a managed-state change, and never one it never managed.
    function ns.ApplyThresholdFormatter(cd, ss)
        if not (cd and cd.SetCountdownFormatter) then return end
        local f = FormatterFor(ss)
        if f then
            if attached[cd] ~= f then
                attached[cd] = f
                cd:SetCountdownFormatter(f)
            end
        elseif attached[cd] then
            attached[cd] = nil
            cd:SetCountdownFormatter(nil)
        end
    end

    -- Effective threshold config for a frame's spell: per-spell family store (tier-chained) first,
    -- then the preset/custom customActiveStates entry -- the same two homes Reverse Swipe reads. Returns the arming block, or nil.
    function ns.ResolveThresholdTextSettings(frame, sid, sd, barKey)
        if not sid then return nil end
        local ss
        if ns.ResolveSpellSettings then
            ss = ns.ResolveSpellSettings(frame, sid, sd, barKey)
        end
        if ss and (tonumber(ss.thresholdSeconds) or 0) > 0 then return ss end
        if ns.GetEffectiveCustomActiveState then
            local cas = ns.GetEffectiveCustomActiveState(sid)
            if cas and (tonumber(cas.thresholdSeconds) or 0) > 0 then return cas end
        end
        return nil
    end
end

-- Styles the custom-spell "Show Charges" count text (created lazily by the CdmHooks ticker) to
-- match the bar's native stack/charge text: font, size, color, anchor position and X/Y offset.
-- Called at creation and from every RefreshCDMIconAppearance pass so option changes apply live. With no bar data the defaults resolve to size 11, bottom-right, +2 nudge.
function ns.StyleCustomChargeText(icon, barKey)
    local fs = icon and icon._castCountText
    if not fs then return end
    local barData = (barKey and barDataByKey[barKey]) or {}
    -- Fonts render at the frame's native scale; compensate like the main pass.
    local iconScale = icon:GetScale() or 1
    if iconScale < 0.01 then iconScale = 1 end
    local scSize = (barData.stackCountSize or 11) / iconScale
    local scX = (barData.stackCountX or 0) / iconScale
    local scY = (barData.stackCountY or 0) / iconScale
    local scPoint = barData.stackCountPosition or "bottomright"
    if scPoint == "bottomleft" then scPoint = "BOTTOMLEFT"; scY = scY + 2
    elseif scPoint == "bottom" then scPoint = "BOTTOM"; scY = scY + 2
    elseif scPoint == "topright" then scPoint = "TOPRIGHT"
    elseif scPoint == "top" then scPoint = "TOP"
    elseif scPoint == "topleft" then scPoint = "TOPLEFT"
    elseif scPoint == "center" then scPoint = "CENTER"
    elseif scPoint == "left" then scPoint = "LEFT"
    elseif scPoint == "right" then scPoint = "RIGHT"
    else scPoint = "BOTTOMRIGHT"; scY = scY + 2 end
    SetBlizzCDMFont(fs, GetCDMFont(), scSize,
        barData.stackCountR or 1, barData.stackCountG or 1, barData.stackCountB or 1)
    -- Parent onto the text overlay so it renders above the border.
    local fd = _getFD(icon)
    local txOverlay = (fd and fd.textOverlay) or icon._textOverlay
    if txOverlay then fs:SetParent(txOverlay) end
    fs:ClearAllPoints()
    fs:SetPoint(scPoint, txOverlay or icon, scPoint, scX, scY)
end

-- Refresh visual properties of existing icons (called when settings change)
local function RefreshCDMIconAppearance(barKey)
    -- Custom auras render in their own engine container, so their style is
    -- re-applied here rather than in the icon loop -- and before the early-outs
    -- below, since a bar can hold custom auras and no icons of its own.
    if ns.RefreshAuraCustomStyle then ns.RefreshAuraCustomStyle(barKey) end
    local icons = cdmBarIcons[barKey]
    if not icons then return end

    local barData = barDataByKey[barKey]
    if not barData then return end

    local borderSize = barData.borderSize or 1
    local zoom = barData.iconZoom or 0.08

    for _, icon in ipairs(icons) do
        local fd = _getFD(icon)
        local tex = fd and fd.tex or icon._tex
        local cd = fd and fd.cooldown or icon._cooldown
        local bg = fd and fd.bg or icon._bg
        local glowOv = fd and fd.glowOverlay or icon._glowOverlay
        local kbText = fd and fd.keybindText or icon._keybindText
        local txOverlay = fd and fd.textOverlay or icon._textOverlay
        -- Scale compensation: fonts render at the frame's native scale, so multiply sizes by 1/scale to match the visual icon size.
        local iconScale = icon:GetScale() or 1
        if iconScale < 0.01 then iconScale = 1 end
        local fontScale = 1 / iconScale
        -- Per-icon override settings (buff-family bars only). Resolved once and reused for Buff
        -- Glow + Duration Text + Charge/Stack below; nil = inherit the bar's value. Variant-aware:
        -- a setting stored under any spell in the icon's family (base/talent-override) resolves here -- options keys off the live/canonical id, which may differ from fc.spellID.
        local ssb
        -- Canonical id for buff-family icons, hoisted so the Threshold Text block below can
        -- reuse it instead of re-walking GetCanonicalSpellIDForFrame a second time this pass.
        local sidb
        local isBuffFamilyBar = (barData.barType == "buffs" or barKey == "buffs")
        -- Login/refresh coverage for Max Stacks Glow: a charge spell at max never fires the swipe hook, so register here too. Gated on the feature flag so non-users skip the call entirely.
        if ns._cdmAnyMaxStacksGlow and not isBuffFamilyBar and ns.WatchMaxStacksIfEnabled then
            ns.WatchMaxStacksIfEnabled(icon)
        end
        -- Same for "Hide CD Text (Charges)": a charge spell at max shows no recharge text and never fires the swipe hook. Same feature-flag gate.
        if ns._cdmAnyChargeHideCdText and not isBuffFamilyBar and ns.WatchChargeCdTextIfEnabled then
            ns.WatchChargeCdTextIfEnabled(icon)
        end
        -- "Hide Text at 0 Stacks" (bar-level): enroll/refresh on the same login + settings-change
        -- pass. Gated on the bar's key plus a next() probe so turning it OFF still reaches the unwatch/restore path; both empty = skipped entirely.
        if not isBuffFamilyBar and ns.WatchZeroChargeTextIfEnabled
           and (barData.hideZeroChargeText or ns._cdmAnyHideChargeText
                or next(ns._zeroChargeTextWatch or {}) ~= nil) then
            ns.WatchZeroChargeTextIfEnabled(icon)
        end
        -- Re-assert Hide Recharge Edge/Hide Swipe on charge icons so a toggle updates a
        -- currently-recharging spell immediately instead of waiting for the next recharge to fire the reactive SetDrawEdge/SetDrawSwipe hooks. Gated + self-skips non-charge frames = 0 cost unless in use.
        if ns._cdmAnyChargeStyle and not isBuffFamilyBar and ns.ReapplyChargeStyle then
            ns.ReapplyChargeStyle(icon)
        end
        -- "Audio Effect on CD Ready": register cd/utility icons with the sound onto the event-driven
        -- watcher (SPELL_UPDATE_COOLDOWN + SPELL_UPDATE_CHARGES; charge and non-charge both handled there). Icons without the sound self-skip inside.
        if ns._cdmAnyCdReadySound and not isBuffFamilyBar and ns.WatchCdReadySoundIfEnabled then
            ns.WatchCdReadySoundIfEnabled(icon)
        end
        -- Buff per-spell settings resolve for any BUFF FRAME, not just buff-family bars: a hosted
        -- buff (real Blizzard buff frame reparented onto a CD/util bar, flagged fd._isBuffViewerFrame)
        -- and its inactive placeholder need the same resolution so their Buff Glow/Duration Text/Charge-Stack/Border/Desaturate match the active frame.
        if isBuffFamilyBar or (fd and fd._isBuffViewerFrame) or icon._isPlaceholderFrame then
            -- Per-icon Audio on Buff Gain/Loss: attach the gain+loss hooks once, only when the feature is in use anywhere.
            if ns._cdmAnyBuffSound and ns.EnsureBuffSoundHook then ns.EnsureBuffSoundHook(icon) end
            local fcb = _ecmeFC[icon]
            -- Resolve by the DISPLAYED spell first (GetCanonicalSpellIDForFrame, the id the options
            -- menu writes settings under) rather than fc.spellID (the cooldownInfo base). For buffs
            -- whose base is a generic spec spell shared across icons (Consecration's standing-in
            -- aura -> Prot Paladin 137028), keying off the base misses the real buff AND lets one
            -- icon's setting shadow another's. canon as primary makes settings[canon] the fast path. Own placeholder/custom frames have no live spell -> fc.spellID.
            sidb = (ns.GetCanonicalSpellIDForFrame and ns.GetCanonicalSpellIDForFrame(icon))
                or (fcb and fcb.spellID)
            if sidb then
                local sdb = ns.GetBarSpellData(barKey)
                -- Shared resolver: matches the key against the frame's full identity set (canon first, then resolvedSid/baseSpellID).
                ssb = ns.ResolveSpellSettings and ns.ResolveSpellSettings(icon, sidb, sdb, barKey)
            end
            -- Stash the effective Buff Glow on fd so the BuffTicker hot path reads it without a
            -- per-tick lookup. Only restart the live glow when the effective value actually changed (no flicker on no-op rebuilds).
            local nT = ssb and ssb.buffGlow           -- nil = inherit, number = override (0 = None)
            -- A false-block (per-spell "Off", or Exclude this spec/bar apply of an Off value) is
            -- render-equivalent to nil: treat it as inherit, never as a value. Without this fd._bgT would be `false` and the BuffTicker's `effGlowType > 0` compares a boolean with a number and errors.
            if nT == false then nT = nil end
            local nColor = ssb and ssb.buffGlowColor  -- nil / "class" / "custom"
            local nR, nG, nB
            if nColor == "custom" and ssb then
                nR, nG, nB = ssb.buffGlowColorR, ssb.buffGlowColorG, ssb.buffGlowColorB
            end
            if fd then
                if fd._bgT ~= nT or fd._bgColor ~= nColor
                   or fd._bgR ~= nR or fd._bgG ~= nG or fd._bgB ~= nB then
                    fd._bgT = nT; fd._bgColor = nColor; fd._bgR = nR; fd._bgG = nG; fd._bgB = nB
                    if fd.buffGlowActive and fd.buffGlowOverlay then
                        StopNativeGlow(fd.buffGlowOverlay)
                        fd.buffGlowActive = false
                    end
                end
                -- Per-icon Desaturate Inactive override, read by the BuffTicker.
                fd._desatOverride = (ssb and ssb.desatInactive) or nil
            end
        end
        -- Update texture -- fill the entire frame. The border renders on top via PP.CreateBorder so no inset is needed.
        if tex then
            tex:ClearAllPoints()
            tex:SetAllPoints(icon)
            tex:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
        end
        -- Update cooldown (full frame so swipe covers the entire icon). The swipe and the countdown
        -- number both live on the Cooldown widget, so raise the whole widget ABOVE our border
        -- (icon+13) or the border draws over the number (most visible with edge-offset text);
        -- anchoring the number to cd (below) keeps the X/Y offset working. Side effect: the dark swipe lightly tints the thin border while active.
        if cd then
            cd:ClearAllPoints()
            cd:SetAllPoints(icon)
            -- Above the border (icon+13); still below glow (icon+16) / text (icon+23).
            pcall(cd.SetFrameLevel, cd, icon:GetFrameLevel() + 14)
            -- Per-icon Duration Text override (ssb) falls back to the bar's values. Only Show
            -- Numbers no longer forces this on: hiding the duration (bar toggle or per-icon) under it leaves just the stack count.
            local showCD = ns.CdmDurationTextOn(barData)
            if ssb and ssb.showCooldownText ~= nil then showCD = ssb.showCooldownText end
            cd:SetSwipeColor(0, 0, 0, barData.swipeAlpha or 0.7)
            -- Per-spell Reverse Swipe: flips this icon's swipe direction away from the bar default
            -- (buffs fill up, cooldowns deplete). Entire block is gated by the session flag, so it
            -- is ZERO cost/ZERO behavior change unless at least one spell has the toggle on -- the
            -- cooldown then keeps DecorateFrame's default. Resolves the frame's CURRENT spell each
            -- pass (so pool reuse + talent overrides stay correct) and re-asserts on every refresh, so toggling off restores the default. Not a per-tick path.
            if ns._cdmAnyReverseSwipe then
                -- A hosted buff (buff frame on a CD/util bar) uses the BUFF baseline (fill-up), not the cd baseline, so "Reverse" flips the same way it would on a real buffs bar.
                local rfFc = _ecmeFC[icon]
                -- "Fills like a buff" must agree with the claim loops in
                -- EllesmereUICdmHooks (DecorateFrame's isBuff, the CD claim
                -- pass's wantRev): a hosted buff and its placeholder fill UP
                -- even on a CD/util bar. This pass writes the widget directly,
                -- so it must also stamp fd._revKind below -- the claim-pass
                -- repairs are gated on that memo.
                local rfBuff = (barData.barType == "buffs" or barKey == "buffs"
                    or barData.barType == "custom_buff"
                    or (rfFc and rfFc.isHostedBuff)
                    or (fd and fd._isBuffViewerFrame)
                    or icon._isPlaceholderFrame) and true or false
                -- Shared with the decoration + claim re-asserts (ns.EffectiveReverseSwipe),
                -- so every writer of this widget pushes the same value.
                local rfReverse = rfBuff
                if ns.EffectiveReverseSwipe then
                    rfReverse = ns.EffectiveReverseSwipe(icon, barKey, rfBuff)
                end
                cd:SetReverse(rfReverse)
                -- Keep the kind memo equal to what is RENDERED, so the
                -- kind-gated re-asserts in the claim loops stay sound.
                if fd then fd._revKind = rfReverse end
            end
            -- Per-spell Hide CD Swipe: removes the cooldown swipe entirely for cd/utility spells
            -- (non-charge -- charge spells use "Hide Swipe (Charges)"). Gated by the session flag,
            -- so zero cost unless someone enables it. Applied here for immediate feedback; the
            -- SetDrawSwipe hook keeps it off against Blizzard's re-pushes. Re-asserts (not hide) each pass so toggling off restores the default swipe -- matching the hook's non-charge force-true.
            if ns._cdmAnyHideCDSwipe and cd.SetDrawSwipe then
                local isCharge = type(icon.HasVisualDataSource_Charges) == "function"
                    and icon:HasVisualDataSource_Charges()
                if not isCharge then
                    local hsFc = _ecmeFC[icon]
                    local hsSid = hsFc and hsFc.spellID
                    local hideSw
                    if hsSid then
                        if ns.ResolveSpellSettings then
                            local hsSs = ns.ResolveSpellSettings(icon, hsSid, ns.GetBarSpellData(barKey))
                            hideSw = hsSs and hsSs.hideCDSwipe
                        end
                        if not hideSw and ns.GetEffectiveCustomActiveState then
                            local casH = ns.GetEffectiveCustomActiveState(hsSid)
                            hideSw = casH and casH.hideCDSwipe
                        end
                    end
                    local fd = ns._hookFrameData and ns._hookFrameData[icon]
                    if fd then fd._isProcessingOverride = true end
                    cd:SetDrawSwipe(not hideSw)
                    if fd then fd._isProcessingOverride = false end
                end
            end
            -- Per-spell Threshold Text: attach the engine countdown formatter that renders
            -- decimals/a color change below the spell's Threshold Seconds. Gated by the session
            -- flag, so zero cost/zero behavior change unless at least one spell arms it. Resolution
            -- order matches Reverse Swipe above: family store (variant-aware via the frame) first, then the preset/custom customActiveStates entry.
            -- sid resolves canon-first like sidb above -- fc.spellID alone is the cooldownInfo
            -- BASE, which for a hosted buff/debuff can be a generic id shared across icons (or
            -- simply not the id the options menu wrote the entry under), so it misses the armed
            -- per-spell entry entirely. Reuse sidb when the buff block above already computed it.
            if ns._cdmAnyThresholdText and ns.ApplyThresholdFormatter then
                local ttFc = _ecmeFC[icon]
                local ttSid = sidb
                    or (ns.GetCanonicalSpellIDForFrame and ns.GetCanonicalSpellIDForFrame(icon))
                    or (ttFc and ttFc.spellID)
                local tt
                if ttSid and ns.ResolveThresholdTextSettings then
                    tt = ns.ResolveThresholdTextSettings(icon, ttSid, ns.GetBarSpellData(barKey), barKey)
                end
                ns.ApplyThresholdFormatter(cd, tt)
            end
            -- Per-spell "Hide CD Text (Charges)" can additionally hide the recharge numbers while
            -- a charge is in hand; the font block below still styles the text (using the bar's showCD) so it is ready when numbers return.
            local hideCD = not showCD
            if ns.CdmShouldHideCountdown then hideCD = ns.CdmShouldHideCountdown(icon, hideCD) end
            cd:SetHideCountdownNumbers(hideCD)
            -- Apply cooldown text font directly.
            if showCD then
                local cdFont = GetCDMFont()
                local cdSize = ((ssb and ssb.cooldownFontSize) or barData.cooldownFontSize or 12) * fontScale
                local cdR = (ssb and ssb.cooldownTextR) or barData.cooldownTextR or 1
                local cdG = (ssb and ssb.cooldownTextG) or barData.cooldownTextG or 1
                local cdB = (ssb and ssb.cooldownTextB) or barData.cooldownTextB or 1
                local cdPosition = (ssb and ssb.cooldownTextPosition)
                    or barData.cooldownTextPosition or "center"
                local cdX = (ssb and ssb.cooldownTextX) or barData.cooldownTextX or 0
                local cdY = (ssb and ssb.cooldownTextY) or barData.cooldownTextY or 0
                -- Find Blizzard's countdown FontString on the Cooldown widget. Keep it ON the
                -- widget (anchored to cd) so the user's position and X/Y offset work -- REPARENTING
                -- it makes Blizzard's engine re-center and ignore both. Setting our own anchor also
                -- overrides the engine's stale baseline (raw SetFont vs SetCountdownFont); off-center anchors are where a missed or stomped anchor first becomes visible.
                for _, rgn in pairs({ cd:GetRegions() }) do
                    if rgn and rgn.GetObjectType and rgn:GetObjectType() == "FontString" then
                        EllesmereUI.ApplyIconTextFont(rgn, cdFont, cdSize, "cdm")
                        rgn:SetTextColor(cdR, cdG, cdB)
                        ns.AnchorCooldownText(rgn, cd, cdPosition, cdX, cdY)
                    end
                end
            end
        end
        -- Update border (PP or textured via ApplyBorderStyle)
        local bdrTgt = (fd and fd.borderFrame) or icon
        if fd and fd.borderFrame or EllesmereUI.PP.GetBorders(icon) then
            local textureKey = barData.borderTexture or "solid"
            EllesmereUI.ApplyBorderStyle(bdrTgt, borderSize, barData.borderR or 0, barData.borderG or 0, barData.borderB or 0, barData.borderA or 1, textureKey, barData.borderTextureOffset, barData.borderTextureOffsetY, barData.borderTextureShiftX, barData.borderTextureShiftY, "cdm", barData.borderThickness or "thin", true)
        end
        -- Update background
        if bg then
            bg:SetColorTexture(barData.bgR or 0.08, barData.bgG or 0.08, barData.bgB or 0.08, barData.bgA or 0.6)
        end
        -- Style Blizzard's native stack/charge text elements: raise their sub-frames above our
        -- border frame by bumping frame level (safe -- they are Blizzard's own children of the icon and follow frame reuse). Per-icon Charge/Stack override (ssb) falls back to the bar's values.
        local scFont = GetCDMFont()
        local scSize = ((ssb and ssb.stackCountSize) or barData.stackCountSize or 11) * fontScale
        local scR = (ssb and ssb.stackCountR) or barData.stackCountR or 1
        local scG = (ssb and ssb.stackCountG) or barData.stackCountG or 1
        local scB = (ssb and ssb.stackCountB) or barData.stackCountB or 1
        local scX = ((ssb and ssb.stackCountX) or barData.stackCountX or 0) * fontScale
        local scY = ((ssb and ssb.stackCountY) or barData.stackCountY or 0) * fontScale
        -- Stack/charge/item-count text anchor. Default bottom-right keeps the historical +2 vertical nudge so existing bars stay pixel-identical; top and center positions sit flush with no baseline nudge.
        local scPoint
        scPoint, scY = ns.CdmStackAnchorPoint(
            (ssb and ssb.stackCountPosition) or barData.stackCountPosition or "bottomright", scY)
        local showItemCount = barData.showItemCount ~= false
        if ssb and ssb.showItemCount ~= nil then showItemCount = ssb.showItemCount end
        -- Show Item Count "Out of Combat" mode: bar-level combat gate applied on top of the
        -- resolved per-spell value. Combat edges re-run this restyle for OOC bars (ns.RefreshItemCountOOCBars), so the gate only ever reads the event-tracked combat flag.
        if showItemCount and barData.itemCountOOC and _inCombat then
            showItemCount = false
        end
        -- Show Charge/Stack Text (buff-family bars; per-spell override wins):
        -- hides both counter lanes via ALPHA -- Blizzard re-shows these
        -- fontstrings on state pushes, so Hide() cannot stick. Alpha is safe
        -- to own HERE only because buff frames never enroll in the cd/utility
        -- zero-charge / Hide Charge Text alpha channel (CdmHooks); non-buff
        -- bars never write (csAlpha nil), so that channel keeps single
        -- ownership of its counters.
        local csAlpha
        if barData.barType == "buffs" or barData.barType == "custom_buff" then
            local showCS = barData.showChargeStackText ~= false
            if ssb and ssb.showChargeStackText ~= nil then showCS = ssb.showChargeStackText end
            csAlpha = showCS and 1 or 0
        end
        -- Text must render above borders. Levels are relative to the icon's own frame level (CdmHooks: border +13, text +23).
        local textLvl = icon:GetFrameLevel() + 23
        -- Applications (buff stacks/aura applications) -- not an item count. Blizzard manages show/hide based on whether stacks exist; we only restyle position/font and never gate visibility on showItemCount.
        if icon.Applications then
            pcall(icon.Applications.SetFrameLevel, icon.Applications, textLvl)
            if icon.Applications.Applications then
                local appsFS = icon.Applications.Applications
                SetBlizzCDMFont(appsFS, scFont, scSize, scR, scG, scB)
                appsFS:ClearAllPoints()
                appsFS:SetPoint(scPoint, icon, scPoint, scX, scY)
                if csAlpha then appsFS:SetAlpha(csAlpha) end
            end
        end
        -- ChargeCount (spell charges like Sigil/Roll) -- not an item count. Blizzard manages show/hide based on charge state.
        if icon.ChargeCount then
            pcall(icon.ChargeCount.SetFrameLevel, icon.ChargeCount, textLvl)
            if icon.ChargeCount.Current then
                local chargeFS = icon.ChargeCount.Current
                SetBlizzCDMFont(chargeFS, scFont, scSize, scR, scG, scB)
                chargeFS:ClearAllPoints()
                chargeFS:SetPoint(scPoint, icon, scPoint, scX, scY)
                if csAlpha then chargeFS:SetAlpha(csAlpha) end
            end
        end
        -- Item count text (potions/healthstones) -- our own frame, safe to reparent
        if icon._itemCountText then
            if txOverlay then icon._itemCountText:SetParent(txOverlay) end
            SetBlizzCDMFont(icon._itemCountText, scFont, scSize, scR, scG, scB)
            icon._itemCountText:ClearAllPoints()
            icon._itemCountText:SetPoint(scPoint, txOverlay or icon, scPoint, scX, scY)
            if showItemCount then icon._itemCountText:Show() else icon._itemCountText:Hide() end
        end
        -- Custom-spell "Show Charges" count text (our own lazy fontstring from the CdmHooks ticker) follows the same stack/charge text settings.
        if icon._castCountText then
            ns.StyleCustomChargeText(icon, barKey)
        end

        -- Update keybind text style
        if kbText then
            EllesmereUI.ApplyIconTextFont(kbText, GetCDMFont(), (barData.keybindSize or 10) * fontScale, "cdm")
            kbText:ClearAllPoints()
            -- Scale-compensate the offset so it's visually consistent across icons with different Blizzard-assigned scales.
            local kbX = (barData.keybindOffsetX or 2) * fontScale
            local kbY = (barData.keybindOffsetY or -2) * fontScale
            -- "right" alignment: anchor top-right and grow left (offset mirrored).
            if barData.keybindAlign == "right" then
                kbText:SetJustifyH("RIGHT")
                kbText:SetPoint("TOPRIGHT", txOverlay, "TOPRIGHT", -kbX, kbY)
            else
                kbText:SetJustifyH("LEFT")
                kbText:SetPoint("TOPLEFT", txOverlay, "TOPLEFT", kbX, kbY)
            end
            kbText:SetTextColor(barData.keybindR or 1, barData.keybindG or 1, barData.keybindB or 1, barData.keybindA or 0.9)
        end

        -- Apply custom shape (overrides border/zoom set above). Pass the resolved per-icon
        -- settings so the buff-family Border override (size + color) applies on the authoritative border render, square or shaped.
        local shape = barData.iconShape or "none"
        ApplyShapeToCDMIcon(icon, shape, barData, ssb)
        -- A restyle just reset this icon's mask + border level out from under any live fake-active
        -- overlay (border size/shape change while the active window is open). Re-sync the overlay so it re-shapes and re-lifts the border above itself instead of waiting for the next trigger.
        if ns.FakeActive_OnIconRestyled then ns.FakeActive_OnIconRestyled(icon) end

        -- Reset glow so glow type change takes effect on next tick. Do NOT reset isActive -- that
        -- causes a 1-frame flash where the ticker sees the transition as "inactive" and un-desaturates
        -- the icon before re-detecting active on the next frame. Preserve proc glow and active state glow across rebuilds.
        local ifd = _getFD(icon)
        local hadProcGlow = ifd and ifd.procGlowActive
        local hadActiveGlow = ifd and ifd._activeGlowOn
        if hadProcGlow and glowOv then
            -- Stop then restart with per-spell settings
            StopNativeGlow(glowOv)
            if ifd then ifd.procGlowActive = false end
            ShowProcGlow(icon)
        elseif hadActiveGlow then
            -- Don't touch: active glow is managed by the SetSwipeColor hook. Stopping it here causes a visible blink.
        elseif ifd and ifd._cdStateGlowOn then
            -- cdState glow active: stop it so the desat hook restarts with the updated style. Also re-evaluate immediately for off-CD spells (desat hook won't fire for those).
            if glowOv then StopNativeGlow(glowOv) end
            ifd._cdStateGlowOn = false
            local fc = _ecmeFC[icon]
            local sid = fc and fc.spellID
            local bk = fc and fc.barKey
            if sid and bk then
                local sd = ns.GetBarSpellData(bk)
                -- Shared resolver: direct hit + full identity/override matching against the family store, with bar-tier fallback.
                local ss = ns.ResolveSpellSettings and ns.ResolveSpellSettings(icon, sid, sd, bk)
                local cse = ss and ss.cdStateEffect
                if (cse == "pixelGlowReady" or cse == "buttonGlowReady"
                    or cse == "pixelGlowReadyUsable" or cse == "buttonGlowReadyUsable") and glowOv then
                    local glowUsable = (cse == "pixelGlowReadyUsable" or cse == "buttonGlowReadyUsable")
                    local glowLive = sid
                    if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                        glowLive = C_SpellBook.FindSpellOverrideByID(sid) or sid
                    end
                    local cseInfo = C_Spell.GetSpellCooldown(glowLive)
                    if cseInfo and (not cseInfo.isActive or cseInfo.isOnGCD) then
                        -- Plain variants glow purely from cooldown state (legacy behavior, zero
                        -- extra reads). Resource Aware variants also require usability, except during the loading-screen settle window (API untrustworthy; the watched-set pass after the window corrects it).
                        local isUsable = true
                        if glowUsable then
                            if ns._cdmSoundSuppressed and ns._cdmSoundSuppressed() then
                                isUsable = true
                            else
                                isUsable = C_Spell.IsSpellUsable and C_Spell.IsSpellUsable(glowLive)
                            end
                        end
                        if isUsable == true then
                            local gr, gg, gb = ResolveGlowColor(ss)
                            local isPixel = (cse == "pixelGlowReady" or cse == "pixelGlowReadyUsable")
                            StartNativeGlow(glowOv, isPixel and 1 or 3, gr or 1, gg or 1, gb or 1)
                            ifd._cdStateGlowOn = true
                        end
                    end
                    -- Event-driven re-evaluation: Resource Aware glows always, plus plain glows on
                    -- EUI custom frames (their SetDesaturation never fires the SetDesaturated hook that would re-evaluate them). Fake-Active-owned frames (PresetHasCdState) excluded.
                    local watchGlow = glowUsable
                    if not watchGlow
                        and (icon._isRacialFrame or icon._isTrinketFrame or icon._isPresetFrame
                             or icon._isItemPresetFrame or icon._isCustomSpellFrame)
                        and not (ns.PresetHasCdState and ns.PresetHasCdState(icon)) then
                        watchGlow = true
                    end
                    if watchGlow and ns.CDGlowWatch then ns.CDGlowWatch(icon) end
                end
            end
        elseif glowOv then
            StopNativeGlow(glowOv)
            if ifd then ifd.procGlowActive = false end
        end

        -- Apply initial cdState effect (hidden/glow) so the state is correct before the first desat tick and before the visibility system runs. Idempotent: re-evaluates current CD state.
        local fc = _ecmeFC[icon]
        local csSid = fc and fc.spellID
        local csBk = fc and fc.barKey
        if csSid and csBk and csBk:sub(1, 7) ~= "__ghost" then
            local csSd = ns.GetBarSpellData(csBk)
            -- Shared resolver: direct hit + full identity/override matching
            -- against the family store, with bar-tier fallback.
            local csSs = ns.ResolveSpellSettings and ns.ResolveSpellSettings(icon, csSid, csSd, csBk)
            local cse = csSs and csSs.cdStateEffect
            -- Shift-Icons variants behave exactly like their base hidden mode plus the layout flag; normalize so the branches below stay as-is.
            local cseShift = (cse == "hiddenOnCDShift" or cse == "hiddenReadyShift")
            if cse == "hiddenOnCDShift" then cse = "hiddenOnCD"
            elseif cse == "hiddenReadyShift" then cse = "hiddenReady" end
            if cse then
                local csLive = csSid
                if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                    csLive = C_SpellBook.FindSpellOverrideByID(csSid) or csSid
                end
                local cseInfo = C_Spell.GetSpellCooldown(csLive)
                local onCD = cseInfo and cseInfo.isActive and not cseInfo.isOnGCD
                if cse == "hiddenOnCD" or cse == "hiddenReady" then
                    local hide
                    if cse == "hiddenOnCD" then
                        hide = onCD and true or false
                    else
                        -- Hidden (CD Ready): on a charge spell "ready" means AT MAX charges, so the icon keeps tracking the recharge instead of vanishing with a charge still down (ns.CdmCdStateReady).
                        hide = ns.CdmCdStateReady(csLive, onCD, csSs.chargeHideUntilSpent)
                        -- The refill-to-max edge fires no visual hook, so register the SPELL_UPDATE_CHARGES watch that re-hides the icon when it tops off. Self-skips non-charge spells.
                        ns.WatchCdStateChargeIfEnabled(icon)
                    end
                    icon:SetAlpha(hide and 0 or IconShownAlpha(fc, barData))
                    if fc then
                        fc._cdStateHidden = hide or false
                        if ns.SetCdStateShiftHidden then
                            ns.SetCdStateShiftHidden(fc, cseShift and hide or false)
                        end
                    end
                elseif cse == "lowerAlphaOnCD" then
                    -- Identical to hiddenOnCD but with a customizable opacity instead of 0. Reuse
                    -- the _cdStateHidden flag as "cd-state owns this alpha" so the opacity appliers leave the lowered value alone. A visibility-hidden bar stays at 0 in both states.
                    local csBase = IconShownAlpha(fc, barData)
                    icon:SetAlpha(csBase == 0 and 0
                        or (onCD and (csSs.cdStateLowerAlpha or 0.5) or csBase))
                    if fc then
                        fc._cdStateHidden = onCD or false
                        if ns.SetCdStateShiftHidden then ns.SetCdStateShiftHidden(fc, false) end
                    end
                else
                    -- Clear stale hidden state when switching to a glow effect
                    if fc and fc._cdStateHidden then
                        fc._cdStateHidden = false
                        icon:SetAlpha(IconShownAlpha(fc, barData))
                    end
                    if fc and ns.SetCdStateShiftHidden then
                        ns.SetCdStateShiftHidden(fc, false)
                    end
                    if not ifd or not ifd._cdStateGlowOn then
                        if (cse == "pixelGlowReady" or cse == "buttonGlowReady"
                            or cse == "pixelGlowReadyUsable" or cse == "buttonGlowReadyUsable")
                           and not onCD and glowOv then
                            -- Plain variants glow purely from cooldown state (legacy). Resource Aware variants also require usability outside the loading-screen settle window.
                            local isUsable = true
                            if cse == "pixelGlowReadyUsable" or cse == "buttonGlowReadyUsable" then
                                if ns._cdmSoundSuppressed and ns._cdmSoundSuppressed() then
                                    isUsable = true
                                else
                                    isUsable = C_Spell.IsSpellUsable and C_Spell.IsSpellUsable(csLive)
                                end
                            end
                            if isUsable == true then
                                local gr, gg, gb = ResolveGlowColor(csSs)
                                local isPixel = (cse == "pixelGlowReady" or cse == "pixelGlowReadyUsable")
                                StartNativeGlow(glowOv, isPixel and 1 or 3, gr or 1, gg or 1, gb or 1)
                                if ifd then ifd._cdStateGlowOn = true end
                            end
                        end
                    end
                    -- Resource Aware glows always watch cooldown events. Plain glows normally
                    -- re-evaluate through the SetDesaturated hook, but EUI's custom frames
                    -- (racial/trinket/potion/custom) drive desaturation via SetDesaturation(float),
                    -- which never fires that hook -- without a watch their glow stays lit for the
                    -- whole cooldown. Frames owned by the Fake-Active preset path (PresetHasCdState) are excluded; that engine glows them.
                    local watchGlow = cse == "pixelGlowReadyUsable" or cse == "buttonGlowReadyUsable"
                    if not watchGlow and (cse == "pixelGlowReady" or cse == "buttonGlowReady")
                        and (icon._isRacialFrame or icon._isTrinketFrame or icon._isPresetFrame
                             or icon._isItemPresetFrame or icon._isCustomSpellFrame)
                        and not (ns.PresetHasCdState and ns.PresetHasCdState(icon)) then
                        watchGlow = true
                    end
                    if watchGlow and glowOv and ns.CDGlowWatch then
                        ns.CDGlowWatch(icon)
                    end
                end
            elseif fc and (fc._cdStateHidden or fc._cdStateShiftHidden) then
                -- A preset keeps its hidden state from the Fake-Active engine (its cdState lives in customActiveStates, not per-bar spellSettings), so don't clear it here or the icon flashes visible.
                if not (ns.PresetHasCdState and ns.PresetHasCdState(icon)) then
                    fc._cdStateHidden = false
                    icon:SetAlpha(IconShownAlpha(fc, barData))
                    if ns.SetCdStateShiftHidden then ns.SetCdStateShiftHidden(fc, false) end
                end
            end
        end
        -- Only Show Numbers (bar setting): re-hide the icon art AFTER the passes above re-applied
        -- borders/shapes/textures, so the countdown number is all that remains. One field read when the bar is off; also restores one-shot right after the bar toggles off.
        if ns.ApplyOnlyNumbers then ns.ApplyOnlyNumbers(icon, fd, barData) end
    end
end
ns.RefreshCDMIconAppearance = RefreshCDMIconAppearance

-- FocusKick bar: a special CD bar pinned to the focus target's nameplate.
-- Internally it is just another custom cooldowns bar so every existing code
-- path treats it identically. Three behavior overrides handled elsewhere:
--   1. Visibility forced to "always" in _CDMApplyVisibility
--   2. Skipped in RegisterCDMUnlockElements
--   3. Position driven by ApplyFocusKickAnchor (nameplate hook)
local FOCUSKICK_BAR_KEY = "focuskick"
ns.FOCUSKICK_BAR_KEY = FOCUSKICK_BAR_KEY
local function EnsureFocusKickBar()
    local p = ECME.db and ECME.db.profile
    if not p or not p.cdmBars or not p.cdmBars.bars then return end
    -- Desired position: directly after the "buffs" default bar and before any custom bars (skipping ghost bars).
    local bars = p.cdmBars.bars
    local targetIdx
    for i, b in ipairs(bars) do
        if b.key == "buffs" then targetIdx = i + 1; break end
    end
    if not targetIdx then targetIdx = #bars + 1 end
    local existingIdx
    for i, b in ipairs(bars) do
        if b.key == FOCUSKICK_BAR_KEY then existingIdx = i; break end
    end
    if existingIdx then
        -- Backfill suppressGCD on existing FocusKick bars (default to on)
        if bars[existingIdx].suppressGCD == nil then
            bars[existingIdx].suppressGCD = true
        end
        if existingIdx == targetIdx or existingIdx == targetIdx - 1 then
            -- Already in the right spot relative to "buffs"
            return
        end
        local entry = table.remove(bars, existingIdx)
        if existingIdx < targetIdx then targetIdx = targetIdx - 1 end
        table.insert(bars, targetIdx, entry)
        return
    end
    table.insert(bars, targetIdx, {
        key = FOCUSKICK_BAR_KEY,
        name = "FocusKick",
        barType = "cooldowns",
        enabled = true,
        iconSize = 28, numRows = 1, spacing = 2,
        borderSize = 1, borderR = 0, borderG = 0, borderB = 0, borderA = 1,
        borderClassColor = false, borderTexture = "solid", borderThickness = "thin",
        bgR = 0.08, bgG = 0.08, bgB = 0.08, bgA = 0.6,
        iconZoom = 0.08, iconShape = "none",
        verticalOrientation = false, barBgEnabled = false,
        barBgR = 0, barBgG = 0, barBgB = 0,
        showCooldownText = true, cooldownTextPosition = "center",
        showItemCount = true, cooldownFontSize = 12,
        showCharges = true, chargeFontSize = 11,
        desaturateOnCD = true, swipeAlpha = 0.7,
        suppressGCD = true,
        activeStateAnim = "blizzard",
        anchorTo = "none", anchorPosition = "left",
        anchorOffsetX = 0, anchorOffsetY = 0,
        barVisibility = "always",
        showStackCount = false, stackCountSize = 11, stackCountPosition = "bottomright",
        outOfRangeOverlay = false,
        pandemicGlow = false,
        -- FocusKick-specific: nameplate side + offsets
        nameplateAnchorSide = "LEFT",
        nameplateOffsetX = 0,
        nameplateOffsetY = 0,
        -- FocusKick-specific: "FOCUS" reminder text on caster/miniboss plates
        focusReminderEnabled = false,
        focusReminderUseAccent = true,
        focusReminderR = 1, focusReminderG = 1, focusReminderB = 1,
        focusReminderSize = 26,
        focusReminderOffsetX = 0,
        focusReminderOffsetY = 0,
        -- FocusKick-specific: show on target instead of focus
        focusKickUseTarget = false,
        -- FocusKick-specific: focus-cast sound trigger
        focusCastSoundKey = "none",
        focusKickInterruptSpellID = nil,
        growDirection = "RIGHT",
    })
    local sd = ns.GetBarSpellData(FOCUSKICK_BAR_KEY)
    if sd then sd.assignedSpells = {} end
end
ns.EnsureFocusKickBar = EnsureFocusKickBar

-- Returns the unit token the FocusKick bar tracks: "target" when the user has enabled Show on Target, "focus" otherwise.
local function GetFocusKickUnit()
    local bd = barDataByKey and barDataByKey[FOCUSKICK_BAR_KEY]
    return (bd and bd.focusKickUseTarget) and "target" or "focus"
end
ns.GetFocusKickUnit = GetFocusKickUnit

-- Set the bar frame and all of its icons to the given alpha. CDM icons are parented to the
-- Blizzard viewer pool, not the bar frame, so hiding the bar frame alone leaves the icons visible -- per-icon alpha is required.
local function SetFocusKickAlpha(a)
    local frame = cdmBarFrames[FOCUSKICK_BAR_KEY]
    if frame then
        frame:SetAlpha(a)
        if frame.EnableMouseMotion and not InCombatLockdown() then
            -- Container never captures motion (steals hover from frames underneath); icon hover is owned by the tooltip setting.
            frame:EnableMouseMotion(false)
        end
        frame._visHidden = (a == 0)
    end
    local icons = cdmBarIcons and cdmBarIcons[FOCUSKICK_BAR_KEY]
    if icons then
        for i = 1, #icons do
            if icons[i] then icons[i]:SetAlpha(a) end
        end
    end
end

-- Find the scale-aware anchor frame inside a Blizzard nameplate. The EllesmereUINameplates
-- addon mixes a custom NameplateFrame into a child of the plate and applies "Scale Target
-- Nameplate"/"Scale Nameplate On Cast" via NameplateFrame:ApplyScale(); the Blizzard plate itself
-- does NOT scale, so anchoring to the plate ignores those settings. Walk the plate's children for the mixed-in frame's visible health bar (correct scaled bounds). Returns (healthFrame, scaledParent) or nil.
local function GetScaledPlateHealth(plate)
    if not plate then return nil end
    local children = { plate:GetChildren() }
    for i = 1, #children do
        local c = children[i]
        if c and c._mixedIn and c.health then
            return c.health, c
        end
    end
    return nil
end

-- Position the FocusKick bar against the tracked unit's nameplate. Called on focus/target change,
-- nameplate add/remove, and nameplate moves. The stored nameplateAnchorSide picks the plate side (LEFT/RIGHT/TOP/BOTTOM); stored offsets shift from that anchor point.
local function ApplyFocusKickAnchor()
    local frame = cdmBarFrames[FOCUSKICK_BAR_KEY]
    if not frame then return end
    local p = ECME.db and ECME.db.profile
    local bd = p and barDataByKey and barDataByKey[FOCUSKICK_BAR_KEY]
    if not bd then return end
    local fkUnit = GetFocusKickUnit()
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(fkUnit)
    if not plate then
        SetFocusKickAlpha(0)
        return
    end
    -- Prefer the scaled health bar from our custom NameplateFrame so the icon tracks Target/Cast
    -- scale changes. Fall back to the raw plate when the nameplates addon isn't loaded or the plate hasn't been decorated yet.
    local anchorFrame = GetScaledPlateHealth(plate) or plate
    local side = bd.nameplateAnchorSide or "LEFT"
    local ox = bd.nameplateOffsetX or 0
    local oy = bd.nameplateOffsetY or 0
    frame:ClearAllPoints()
    if side == "LEFT" then
        frame:SetPoint("RIGHT", anchorFrame, "LEFT", ox, oy)
    elseif side == "RIGHT" then
        frame:SetPoint("LEFT", anchorFrame, "RIGHT", ox, oy)
    elseif side == "TOP" then
        frame:SetPoint("BOTTOM", anchorFrame, "TOP", ox, oy)
    elseif side == "BOTTOM" then
        frame:SetPoint("TOP", anchorFrame, "BOTTOM", ox, oy)
    else
        frame:SetPoint("CENTER", anchorFrame, "CENTER", ox, oy)
    end
    SetFocusKickAlpha(1)
end
ns.ApplyFocusKickAnchor = ApplyFocusKickAnchor

-- Single event proxy, created once and persistent; just calls ApplyFocusKickAnchor on relevant
-- events. Range-fade handling: when the tracked unit walks out of range, Blizzard fades the
-- nameplate alpha without firing NAME_PLATE_UNIT_REMOVED. The bar icons don't inherit plate
-- visibility (parented to the Blizzard viewer pool), so throttle-poll the plate's visibility and propagate alpha to the icons manually -- only while a tracked plate exists; zero work otherwise.
local _focusKickProxy
local _focusKickLastPlateVisible
local _FOCUSKICK_TICK_INTERVAL = 0.1
local function EnsureFocusKickProxy()
    if _focusKickProxy then
        -- Re-apply/re-activate paths must restore the event set (a demand-gate teardown
        -- unregisters it; RegisterEvent is idempotent) and re-arm the watcher: a focus can already exist with no event forthcoming (settings apply, /reload with focus).
        _focusKickProxy:RegisterEvent("PLAYER_FOCUS_CHANGED")
        _focusKickProxy:RegisterEvent("PLAYER_TARGET_CHANGED")
        _focusKickProxy:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        _focusKickProxy:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
        if _focusKickProxy._arm then _focusKickProxy._arm() end
        return _focusKickProxy
    end
    _focusKickProxy = ns.TakeShell()
    _focusKickProxy:RegisterEvent("PLAYER_FOCUS_CHANGED")
    _focusKickProxy:RegisterEvent("PLAYER_TARGET_CHANGED")
    _focusKickProxy:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    _focusKickProxy:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    _focusKickProxy:SetScript("OnEvent", function(self, event, unit)
        local fkUnit = GetFocusKickUnit()
        if event == "PLAYER_FOCUS_CHANGED" then
            if fkUnit ~= "focus" then return end
            _focusKickLastPlateVisible = nil
            ApplyFocusKickAnchor()
            if self._arm then self._arm() end
        elseif event == "PLAYER_TARGET_CHANGED" then
            if fkUnit ~= "target" then return end
            _focusKickLastPlateVisible = nil
            ApplyFocusKickAnchor()
            if self._arm then self._arm() end
        elseif event == "NAME_PLATE_UNIT_REMOVED" then
            -- Only react when the tracked unit's plate is removed. Reacting to every plate removal caused the bar to flicker off during AoE when unrelated mobs died or faded.
            if unit and (unit == fkUnit or UnitIsUnit(unit, fkUnit)) then
                _focusKickLastPlateVisible = nil
                ApplyFocusKickAnchor()
            end
        elseif event == "NAME_PLATE_UNIT_ADDED" then
            if unit and (unit == fkUnit or UnitIsUnit(unit, fkUnit)) then
                _focusKickLastPlateVisible = nil
                ApplyFocusKickAnchor()
                if self._arm then self._arm() end
            end
        end
    end)
    -- Plate fade/occlusion has no event, so watching the tracked unit's plate visibility needs a
    -- poll -- but ONLY while a tracked unit exists, on a self-stopping anim ticker (the C engine
    -- sleeps between 0.1s fires) rather than a per-render-frame OnUpdate. The ticker stops itself the moment the unit is gone; the proxy's own events (focus/target changed, plate added) and EnsureFocusKickProxy re-arm it.
    local fkTicker
    local function FocusKickTick()
        local fkUnit = GetFocusKickUnit()
        if not UnitExists(fkUnit) then return false end
        local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit
            and C_NamePlate.GetNamePlateForUnit(fkUnit)
        local visibleNow
        if plate then
            local alpha = plate:GetEffectiveAlpha() or 0
            visibleNow = plate:IsVisible() and alpha > 0.01
        else
            visibleNow = false
        end
        if visibleNow ~= _focusKickLastPlateVisible then
            _focusKickLastPlateVisible = visibleNow
            SetFocusKickAlpha(visibleNow and 1 or 0)
        end
        return true
    end
    _focusKickProxy._arm = function()
        if not fkTicker then
            fkTicker = EllesmereUI.Tick.NewAnimTicker(_focusKickProxy,
                FocusKickTick, _FOCUSKICK_TICK_INTERVAL)
        end
        fkTicker.Start()
    end
    _focusKickProxy._stop = function()
        if fkTicker then fkTicker.Stop() end
    end
    _focusKickProxy._arm()
    return _focusKickProxy
end
ns.EnsureFocusKickProxy = EnsureFocusKickProxy

-- Sound dropdown data: built-in EllesmereUI sounds + LibSharedMedia sounds appended at runtime via EllesmereUI.AppendSharedMediaSounds.
local FOCUSKICK_SOUND_PATHS, FOCUSKICK_SOUND_NAMES, FOCUSKICK_SOUND_ORDER =
    EllesmereUI.BuildAlertSoundTables()
ns.FOCUSKICK_SOUND_PATHS = FOCUSKICK_SOUND_PATHS
ns.FOCUSKICK_SOUND_NAMES = FOCUSKICK_SOUND_NAMES
ns.FOCUSKICK_SOUND_ORDER = FOCUSKICK_SOUND_ORDER

-- Focus-cast sound trigger. When the focus target starts a cast and the user's selected interrupt
-- is off cooldown, play the configured sound. One single proxy registered with RegisterUnitEvent on "focus" -- the token follows focus changes automatically.
local _focusCastProxy
local function RefreshFocusCastProxyUnit()
    if not _focusCastProxy then
        -- No proxy to re-point: the bar had no assigned spell at the last arming (RefreshFocusKickProxies
        -- only builds on its hasContent branch, and its ONLY callers are setup and the tail of
        -- BuildAllCDMBars). Adding a spell in the options writes assignedSpells without re-arming
        -- anything, which left the sound dead on a fully populated bar -- so run the full refresh here instead of returning, letting this path create the proxy.
        if ns.RefreshFocusKickProxies then ns.RefreshFocusKickProxies() end
        return
    end
    local unit = GetFocusKickUnit()
    _focusCastProxy:UnregisterAllEvents()
    _focusCastProxy:RegisterUnitEvent("UNIT_SPELLCAST_START", unit)
    _focusCastProxy:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", unit)
end
ns.RefreshFocusCastProxyUnit = RefreshFocusCastProxyUnit

function ns.IsSpellInPlayerBook(id)
    if IsPlayerSpell and IsPlayerSpell(id) then return true end
    if C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook
        and C_SpellBook.IsSpellKnownOrInSpellBook(id) then
        return true
    end
    return false
end

-- Returns the id of the stored interrupt in the form this character can actually cast, or nil.
-- Validate on READ and never write: focusKickInterruptSpellID is profile-level while the spellbook
-- behind it is per-spec, so the id stays correct for the spec that set it -- clearing it here would
-- destroy that spec's setting the first time the player logged in on another one. Asks the
-- SPELLBOOK, never a class/spec table (a hardcoded list goes stale on a patch). Pet-bank interrupts
-- (a Warlock's Axe Toss, a Hunter's pet kick) are legitimate picks IsPlayerSpell cannot see, so
-- check both banks. Returning the resolved id (not a boolean) is the point: a talent swap moves an
-- interrupt between base and override forms while the stored id stays put; answering "known" but leaving the caller the un-castable form would feed the readiness gate an id that is never on cooldown.
function ns.ResolveCastableInterrupt(sid)
    if type(sid) ~= "number" or sid <= 0 then return nil end
    local knownInBook = ns.IsSpellInPlayerBook
    if knownInBook(sid) then return sid end
    -- Talented into a replacement, stored id is the base form.
    if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
        local ovr = C_SpellBook.FindSpellOverrideByID(sid)
        if ovr and ovr > 0 and ovr ~= sid and knownInBook(ovr) then return ovr end
    end
    -- Talented back out, stored id is the replacement form.
    if C_Spell and C_Spell.GetBaseSpell then
        local base = C_Spell.GetBaseSpell(sid)
        if base and base > 0 and base ~= sid and knownInBook(base) then return base end
    end
    -- Pet bank last: it has no override/base indirection to walk.
    if C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook
        and Enum and Enum.SpellBookSpellBank
        and C_SpellBook.IsSpellKnownOrInSpellBook(sid, Enum.SpellBookSpellBank.Pet) then
        return sid
    end
    return nil
end

local function EnsureFocusCastProxy()
    if _focusCastProxy then
        -- Demand-gate re-activation: re-register (idempotent; re-applying RegisterUnitEvent also picks up a changed kick-unit setting).
        local unit = GetFocusKickUnit()
        _focusCastProxy:RegisterUnitEvent("UNIT_SPELLCAST_START", unit)
        _focusCastProxy:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", unit)
        return _focusCastProxy
    end
    _focusCastProxy = ns.TakeShell()
    local unit = GetFocusKickUnit()
    _focusCastProxy:RegisterUnitEvent("UNIT_SPELLCAST_START", unit)
    _focusCastProxy:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", unit)
    _focusCastProxy:SetScript("OnEvent", function()
        local bd = barDataByKey and barDataByKey[FOCUSKICK_BAR_KEY]
        if not bd then return end
        local soundKey = bd.focusCastSoundKey or "none"
        if soundKey == "none" then return end
        local spellID = bd.focusKickInterruptSpellID
        -- An explicit pick is only trusted while this character can cast it: a stale profile-level
        -- id sails through the cooldown gate below forever (a spell you do not know is never on
        -- cooldown), so a Holy Paladin inheriting a Ret's Rebuke would be pinged on every focus
        -- cast. Deliberately checked HERE and not at arming time: arming runs during loading
        -- screens, when the spellbook reads empty for reasons unrelated to spec, and folding "not
        -- loaded yet" into "cannot cast it" silently unregisters a working proxy. This handler only runs on a live cast, by which point the spellbook is settled.
        if spellID then spellID = ns.ResolveCastableInterrupt(spellID) end
        -- Auto-fallback: with no explicit pick, use the first CASTABLE positive spell on the bar
        -- (the picker exists for users who want a specific one). The bar's own list needs the same
        -- castability check -- not because it crosses specs (assignedSpells is per-spec) but
        -- because it can hold spells this spec no longer has: "Include CDM Spell Layout" imports
        -- write another character's layout into these spec keys wholesale, and talent changes strand entries the same way. Either way, an uncastable interrupt reads as permanently ready below.
        if not spellID or spellID <= 0 then
            local sd = ns.GetBarSpellData and ns.GetBarSpellData(FOCUSKICK_BAR_KEY)
            if sd and sd.assignedSpells then
                for _, sid in ipairs(sd.assignedSpells) do
                    if type(sid) == "number" and sid > 0 then
                        local castable = ns.ResolveCastableInterrupt(sid)
                        if castable then
                            spellID = castable
                            break
                        end
                    end
                end
            end
        end
        if not spellID or spellID <= 0 then return end

        -- No interruptible check. The kickProtected flag on UnitCastingInfo and UnitChannelInfo is
        -- a secret boolean in Midnight and any laundering path that returns a value back into Lua
        -- produces a tainted result we cannot branch on. We accept that the sound will occasionally fire on uninterruptible casts -- the nameplate shield icon still tells the player visually.

        -- Cooldown check: only play if our interrupt is ready. cdInfo.isActive is a clean bool --
        -- the duration/startTime fields are secret in Midnight and can't be compared in Lua, but isActive is safe.
        if C_Spell and C_Spell.GetSpellCooldown then
            local cdInfo = C_Spell.GetSpellCooldown(spellID)
            if cdInfo and cdInfo.isActive then return end
        end
        local path = FOCUSKICK_SOUND_PATHS[soundKey]
        if not path then return end
        PlaySoundFile(path, "Master")
    end)
    return _focusCastProxy
end
ns.EnsureFocusCastProxy = EnsureFocusCastProxy

-- Per-icon "Audio on Buff Gain/Loss": play a sound when a buff becomes active (gain) or drops
-- (loss). Blizzard's buff viewer item frames fire TriggerAuraAppliedAlert on the apply edge and
-- TriggerAuraRemovedAlert on the drop edge, so hooksecurefunc both (taint-safe post-hook, no
-- polling). The frame's GetSpellID is a SECRET value while the aura is active, so resolve the
-- clean canonical id via GetCanonicalSpellIDForFrame (the same id the options menu writes the
-- setting under) -- never index a table with the live secret id. Hooked-frame + throttle state
-- live in a do-block, off the Blizzard frame table per the no-custom-props rule. Reuses the
-- FocusKick sound table (option list identical to Focus Cast Sound). Edges are COALESCED to
-- the end of the frame rather than played on the spot: some auras are reapplied by REPLACING
-- the instance instead of refreshing it, and Blizzard checks its removed-alert triggers before
-- the item frames adopt the new instance, so the drop edge fires while the buff is still up.
-- Death and Decay does this on every entry into the circle, cueing a loss at the moment the
-- buff was GAINED. Both alerts for a replacement fire inside the SAME CooldownViewerMixin
-- :OnUnitAura call -- confirmed live to be indistinguishable from a genuine same-tick
-- drop+reproc (e.g. Prismatic Bolt consumed by a cast and reprocced by Salvo), so only the
-- loss cue is cancelled on a pair. A real gain always plays, even on a replacement, rather
-- than silently eating the reported case with no way to tell the two apart.
do
    local _soundHooked = setmetatable({}, { __mode = "k" })
    -- Edges seen this frame: [spellID] = sound key, or false for "edge happened,
    -- configured silent". A silent edge MUST still be recorded or a replacement
    -- whose gain has no sound (the usual setup -- loss cue only) never pairs.
    local _pendGain = {}
    local _pendLoss = {}
    local _flushQueued = false
    local _pendStamp = 0                 -- GetTime() of the frame the pending edges belong to
    -- Overlap guard, NOT an edge filter: two cues for the same spell and edge closer
    -- together than this would talk over each other. Replacements are cancelled by the
    -- pairing above, so this no longer hides them.
    local _soundThrottle = {}            -- [spellID] = last GetTime() (gain)
    local _soundThrottleLost = {}        -- [spellID] = last GetTime() (loss)
    local SOUND_MIN_GAP = 0.3

    -- Per-spell tier then bar tier, for one setting key. nil = silent.
    local function PickBuffSoundKey(ss, sid, field)
        local k = ss and ss[field]
        if not k then k = ns.FindBuffSoundKey and ns.FindBuffSoundKey(sid, field) end
        if not k or k == "none" then return nil end
        return k
    end

    local function PlayThrottled(key, sid, throttle)
        if not key then return end
        local now = GetTime()
        local last = throttle[sid]
        if last and (now - last) < SOUND_MIN_GAP then return end
        throttle[sid] = now
        local path = FOCUSKICK_SOUND_PATHS[key]
        if path then PlaySoundFile(path, "Master") end
    end

    local function FlushBuffEdges()
        _flushQueued = false
        -- Still inside the frame these edges were recorded in (the timer can tick
        -- after some of the frame's aura events but before the rest): a later edge
        -- could still pair with them, so decide next frame instead.
        if GetTime() == _pendStamp then
            _flushQueued = true
            C_Timer.After(0, FlushBuffEdges)
            return
        end
        -- Entries are cleared BEFORE playing so a throw inside PlaySoundFile cannot
        -- strand one and have it cancel an unrelated edge on a later flush.
        for sid, key in pairs(_pendLoss) do
            -- Paired with a gain this frame = replacement: the loss cue is spurious
            -- (the buff never really left). The gain may still be real (e.g. a proc
            -- landing the same tick a cast consumes the old stack), so it is left for
            -- the gain loop below instead of being cancelled here too.
            local paired = _pendGain[sid] ~= nil
            _pendLoss[sid] = nil
            if not paired then PlayThrottled(key, sid, _soundThrottleLost) end
        end
        for sid, key in pairs(_pendGain) do
            _pendGain[sid] = nil
            PlayThrottled(key, sid, _soundThrottle)
        end
    end

    -- Record one edge for the end-of-frame flush. gainEdge picks the side.
    local function RecordBuffEdge(f, gainEdge)
        -- Loading screen / login settle: buffs re-apply and viewer frames re-show
        -- across a zone/login, firing phantom apply/remove alerts. Drop them.
        if ns._cdmSoundSuppressed and ns._cdmSoundSuppressed() then return end
        local sid = ns.GetCanonicalSpellIDForFrame and ns.GetCanonicalSpellIDForFrame(f)
        if not sid then return end
        -- Preferred: the frame's decorated context (fast; ResolveSpellSettings also
        -- handles variant/override spells). Falls back to an id-only lookup for the
        -- FIRST gain after login, whose alert fires before DecorateFrame populates
        -- _ecmeFC -- keying off that context dropped the very first cue.
        local ss
        local fc = _ecmeFC[f]
        local barKey = fc and fc.barKey
        if barKey then
            local sd = ns.GetBarSpellData and ns.GetBarSpellData(barKey)
            ss = ns.ResolveSpellSettings and ns.ResolveSpellSettings(f, sid, sd, barKey)
        end
        -- A silent edge still has to be recorded so it can cancel its partner, but only
        -- when the OTHER edge has a cue -- so the second lookup runs only on that path.
        local key = PickBuffSoundKey(ss, sid, gainEdge and "buffActiveSoundKey" or "buffLostSoundKey")
        if not key and not PickBuffSoundKey(ss, sid, gainEdge and "buffLostSoundKey" or "buffActiveSoundKey") then
            return
        end
        -- A new frame closes the previous batch: pairing must never reach across the
        -- boundary, or a real drop and an unrelated real gain a frame later cancel out.
        local now = GetTime()
        if now ~= _pendStamp then
            FlushBuffEdges()
            _pendStamp = now
        end
        if gainEdge then
            _pendGain[sid] = key or false
        else
            _pendLoss[sid] = key or false
        end
        if not _flushQueued then
            _flushQueued = true
            C_Timer.After(0, FlushBuffEdges)
        end
    end

    function ns.EnsureBuffSoundHook(frame)
        if not frame or _soundHooked[frame] then return end
        -- Own placeholder/custom frames (and anything that isn't a Blizzard buff
        -- viewer item) have no aura alert -- mark hooked so we never retry.
        if type(frame.TriggerAuraAppliedAlert) ~= "function" then
            _soundHooked[frame] = true
            return
        end
        _soundHooked[frame] = true
        hooksecurefunc(frame, "TriggerAuraAppliedAlert", function(f)
            RecordBuffEdge(f, true)
        end)
        -- Loss edge: Blizzard fires TriggerAuraRemovedAlert when the buff drops.
        if type(frame.TriggerAuraRemovedAlert) == "function" then
            hooksecurefunc(frame, "TriggerAuraRemovedAlert", function(f)
                RecordBuffEdge(f, false)
            end)
        end
    end
end

-- "FOCUS" reminder text shown on caster/miniboss nameplates when the player
-- has no focus set. Activated by the FocusKick bar's focusReminderEnabled.
-- Performance design:
--   * _focusKickHasFocus updates only on PLAYER_FOCUS_CHANGED so the hot
--     per-plate path never calls UnitExists("focus").
--   * Per-plate font strings live in _focusReminders keyed by token and are
--     reused across show/hide cycles -- never recreated.
--   * Each font string caches its last applied size/text/color/offsets so
--     SetFont / SetText / SetTextColor / SetPoint are skipped when unchanged
--     (SetFont is the most expensive call here).
--   * NAME_PLATE_UNIT_ADDED skips the work entirely when focus is set or the
--     bar setting is off -- no per-plate overhead in the normal case.
local _focusReminders = {}        -- nameplate token -> font string (with _holder/_lastX cache)
local _focusReminderProxy
local _focusKickHasFocus = false
-- Context flags updated only on world/zone/spec events. Cached so the
-- per-nameplate hot path is one local read instead of repeated API calls.
local _focusKickInDungeon = false
local _focusKickNoKick    = false
local _FOCUS_TEXT = "F O C U S"
local _FR_FALLBACK_FONT = "Fonts/FRIZQT__.TTF"

-- Mirror of the Quest Tracker font handling pattern: tolerate nil/OTF
-- paths, fall back to FRIZQT, and (if SetFont still fails) try alternate
-- separators / Blizzard's default font.
local function FRSafeFont(p)
    if not p or p == "" then return _FR_FALLBACK_FONT end
    local ext = p:match("%.(%a+)$")
    if ext and ext:lower() == "otf" then return _FR_FALLBACK_FONT end
    return p
end
local function FRGlobalFont()
    if EllesmereUI and EllesmereUI.GetFontPath then
        return FRSafeFont(EllesmereUI.GetFontPath("cdm"))
    end
    return _FR_FALLBACK_FONT
end
local function FROutlineFlag()
    if EllesmereUI and EllesmereUI.GetFontOutlineFlag then
        local f = EllesmereUI.GetFontOutlineFlag("cdm")
        if f and f ~= "" then return f end
    end
    return "NONE"
end
local function FRSetFontSafe(fs, path, size, flags)
    if not fs then return end
    local safe = FRSafeFont(path)
    size = size or 11
    if flags == "NONE" then flags = "" end
    flags = flags or ""
    local curPath, curSize, curFlags = fs:GetFont()
    if curPath == safe and curSize == size and (curFlags or "") == flags then return end
    fs:SetFont(safe, size, flags)
    if not fs:GetFont() then fs:SetFont("Fonts/FRIZQT__.TTF", size, flags) end
    if not fs:GetFont() then fs:SetFont("Fonts\\FRIZQT__.TTF", size, flags) end
    if not fs:GetFont() then
        local gf = GameFontNormal and GameFontNormal:GetFont()
        if gf then fs:SetFont(gf, size, flags) end
    end
end
local function FRApplyFontShadow(fs)
    if not fs then return end
    local useShadow = (EllesmereUI and EllesmereUI.GetFontUseShadow and EllesmereUI.GetFontUseShadow("cdm")) and true or false
    -- Font is set by FRSetFontSafe before this call; capture and restore it so
    -- priming the shadow FontObject does not change the typeface.
    local _pf, _ps, _pfl = fs:GetFont()
    if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(fs, useShadow) end
    if _pf then fs:SetFont(_pf, _ps, _pfl) end
end

local function GetFocusKickBarData()
    return barDataByKey and barDataByKey[FOCUSKICK_BAR_KEY]
end
local function FocusReminderUnitMatches(unit)
    if not unit then return false end
    -- Caster = the unit actually has a mana pool (12.1 moved caster marking
    -- off the old internal "PALADIN" class tag; same lane as the nameplate
    -- caster color). Second arg is the typed PowerType enum NUMBER, not the
    -- localized MANA global; the return carries no secrecy flag, so it is
    -- safe to branch on directly even on protected-content nameplates.
    if UnitHasPowerType and Enum and Enum.PowerType
        and UnitHasPowerType(unit, Enum.PowerType.Mana) then
        return true
    end
    -- Elite fallback: identity reads here DO return secrets in protected
    -- content; a secret can vouch nothing, so the signal is dropped, never
    -- compared -- this arm quietly stands down there while the mana arm
    -- above keeps carrying the feature.
    local cls = UnitClassification and UnitClassification(unit)
    if issecretvalue and issecretvalue(cls) then cls = nil end
    if cls == "elite" or cls == "rareelite" or cls == "worldboss" then
        local lvl = UnitLevel(unit)
        local plvl = UnitLevel("player")
        local lvlClean = lvl and not (issecretvalue and issecretvalue(lvl))
        local plvlClean = plvl and not (issecretvalue and issecretvalue(plvl))
        if lvlClean and (lvl == -1 or (plvlClean and lvl >= plvl + 1)) then return true end
    end
    return false
end
local function HideFocusReminder(token)
    local fs = _focusReminders[token]
    if fs and fs:IsShown() then fs:Hide() end
end
local function HideAllFocusReminders()
    for _, fs in pairs(_focusReminders) do
        if fs and fs:IsShown() then fs:Hide() end
    end
end
local function ShowFocusReminder(token)
    -- Cheap rejects first
    if _focusKickHasFocus then HideFocusReminder(token); return end
    if not _focusKickInDungeon then HideFocusReminder(token); return end
    if _focusKickNoKick then HideFocusReminder(token); return end
    local bd = GetFocusKickBarData()
    if not bd or bd.focusReminderEnabled ~= true then
        HideFocusReminder(token); return
    end
    if not FocusReminderUnitMatches(token) then
        HideFocusReminder(token); return
    end
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(token)
    if not plate then HideFocusReminder(token); return end

    local fs = _focusReminders[token]
    if not fs then
        local holder = CreateFrame("Frame", nil, plate)
        holder:SetSize(1, 1)
        holder:SetFrameStrata("HIGH")
        holder:SetFrameLevel(plate:GetFrameLevel() + 10)
        fs = holder:CreateFontString(nil, "OVERLAY")
        fs._holder = holder
        fs:SetPoint("CENTER", holder, "CENTER", 0, 0)
        -- IMPORTANT: SetFont must run before SetText. Initialize the font using the safe helper
        -- here so the very first SetText below has a valid font. (Calling SetText on a font string with no font set raises "FontString:SetText(): Font not set".)
        FRSetFontSafe(fs, FRGlobalFont(), bd.focusReminderSize or 26, FROutlineFlag())
        FRApplyFontShadow(fs)
        fs:SetText(_FOCUS_TEXT)
        fs._lastText = _FOCUS_TEXT
        _focusReminders[token] = fs
    end

    -- Reparent only when the plate frame for this token actually changed
    if fs._holder:GetParent() ~= plate then
        fs._holder:SetParent(plate)
        fs._lastOX, fs._lastOY = nil, nil  -- force point reapply on parent change
    end

    -- Anchor: only re-SetPoint if X or Y changed
    local ox = bd.focusReminderOffsetX or 0
    local oy = (bd.focusReminderOffsetY or 0) - 15  -- internal -15 baseline
    if fs._lastOX ~= ox or fs._lastOY ~= oy then
        fs._holder:ClearAllPoints()
        fs._holder:SetPoint("TOP", plate, "BOTTOM", ox, oy)
        fs._lastOX, fs._lastOY = ox, oy
    end

    -- Font: re-apply only if size, font path, or outline changed. Goes through FRSetFontSafe so
    -- the user's global font + outline (EllesmereUI -> Fonts) drives the look, with fallbacks for missing/unsupported paths.
    local size = bd.focusReminderSize or 26
    local fontPath = FRGlobalFont()
    local outline = FROutlineFlag()
    if fs._lastSize ~= size or fs._lastFontPath ~= fontPath or fs._lastOutline ~= outline then
        FRSetFontSafe(fs, fontPath, size, outline)
        FRApplyFontShadow(fs)
        fs._lastSize = size
        fs._lastFontPath = fontPath
        fs._lastOutline = outline
    end

    -- Color: accent mode reads the live ELLESMERE_GREEN; custom mode reads the stored RGB. Re-SetTextColor only if the resolved color changed.
    local r, g, b
    if bd.focusReminderUseAccent then
        local eg = EllesmereUI.ELLESMERE_GREEN
        r = (eg and eg.r) or 0.047
        g = (eg and eg.g) or 0.824
        b = (eg and eg.b) or 0.624
    else
        r = bd.focusReminderR or 1
        g = bd.focusReminderG or 1
        b = bd.focusReminderB or 1
    end
    if fs._lastR ~= r or fs._lastG ~= g or fs._lastB ~= b then
        fs:SetTextColor(r, g, b)
        fs._lastR, fs._lastG, fs._lastB = r, g, b
    end

    if not fs:IsShown() then fs:Show() end
end

local function RefreshFocusReminders()
    -- Clear all, then re-show for currently visible nameplates. Iterate unit tokens directly:
    -- plate.namePlateUnitToken can be nil when polled outside of NAME_PLATE_UNIT_ADDED events, so the safer path is to walk nameplate1..nameplate40 and let UnitExists filter.
    HideAllFocusReminders()
    if _focusKickHasFocus then return end
    if not _focusKickInDungeon then return end
    if _focusKickNoKick then return end
    local bd = GetFocusKickBarData()
    if not bd or bd.focusReminderEnabled ~= true then return end
    for i = 1, 40 do
        local token = "nameplate" .. i
        if UnitExists(token) then
            ShowFocusReminder(token)
        end
    end
end
ns.RefreshFocusReminders = RefreshFocusReminders
_G._ECME_RefreshFocusReminders = RefreshFocusReminders

-- Refresh the cached context flags (instance type + role) and trigger a visual refresh if either
-- flag transitioned. Called on PLAYER_ENTERING_WORLD, ZONE_CHANGED_NEW_AREA, and PLAYER_SPECIALIZATION_CHANGED.
-- Healer specs that have no kick (Resto Shaman has Wind Shear, so excluded)
local _HEALER_NO_KICK = {
    [65]  = true, -- Holy Paladin
    [256] = true, -- Discipline Priest
    [257] = true, -- Holy Priest
    [105] = true, -- Restoration Druid
    [270] = true, -- Mistweaver Monk
    [1468] = true, -- Preservation Evoker
}

local function UpdateFocusKickContext()
    local _, instanceType = IsInInstance()
    local nowInDungeon = (instanceType == "party")
    local specID = GetSpecializationInfo and GetSpecialization
        and GetSpecialization() and GetSpecializationInfo(GetSpecialization())
    local nowNoKick = specID and _HEALER_NO_KICK[specID] or false
    local changed = (nowInDungeon ~= _focusKickInDungeon) or (nowNoKick ~= _focusKickNoKick)
    _focusKickInDungeon = nowInDungeon
    _focusKickNoKick    = nowNoKick
    if changed then
        RefreshFocusReminders()
    end
end
ns.UpdateFocusKickContext = UpdateFocusKickContext

local function EnsureFocusReminderProxy()
    if _focusReminderProxy then
        -- Demand-gate re-activation: restore the event set (idempotent) and re-seed the state the creation path seeds.
        _focusReminderProxy:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        _focusReminderProxy:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
        _focusReminderProxy:RegisterEvent("PLAYER_FOCUS_CHANGED")
        _focusReminderProxy:RegisterEvent("PLAYER_ENTERING_WORLD")
        _focusReminderProxy:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        _focusReminderProxy:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        _focusKickHasFocus = UnitExists("focus") and true or false
        UpdateFocusKickContext()
        return _focusReminderProxy
    end
    -- Initialize focus + context state once at proxy creation
    _focusKickHasFocus = UnitExists("focus") and true or false
    UpdateFocusKickContext()
    _focusReminderProxy = ns.TakeShell()
    _focusReminderProxy:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    _focusReminderProxy:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    _focusReminderProxy:RegisterEvent("PLAYER_FOCUS_CHANGED")
    _focusReminderProxy:RegisterEvent("PLAYER_ENTERING_WORLD")
    _focusReminderProxy:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    _focusReminderProxy:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    _focusReminderProxy:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_FOCUS_CHANGED" then
            local hadFocus = _focusKickHasFocus
            _focusKickHasFocus = UnitExists("focus") and true or false
            if hadFocus ~= _focusKickHasFocus then
                RefreshFocusReminders()
            end
        elseif event == "PLAYER_ENTERING_WORLD"
            or event == "ZONE_CHANGED_NEW_AREA"
            or event == "PLAYER_SPECIALIZATION_CHANGED" then
            UpdateFocusKickContext()
        elseif event == "NAME_PLATE_UNIT_ADDED" then
            if _focusKickHasFocus then return end
            if not _focusKickInDungeon then return end
            if _focusKickIsHealer then return end
            ShowFocusReminder(unit)
        elseif event == "NAME_PLATE_UNIT_REMOVED" then
            HideFocusReminder(unit)
        end
    end)
    return _focusReminderProxy
end
ns.EnsureFocusReminderProxy = EnsureFocusReminderProxy

-- Demand gate for the whole FocusKick feature family (anchor proxy + plate watcher, reminder
-- text, cast sound). An EMPTY kick bar -- no positive spell assigned, or the bar disabled --
-- means the feature does not exist at runtime: no events registered anywhere, no ticker, zero
-- cost. Called from setup and from the tail of every BuildAllCDMBars, so assigning the first kick spell (or removing the last) flips the family on/off live.
function ns.RefreshFocusKickProxies()
    local bd = barDataByKey and barDataByKey[FOCUSKICK_BAR_KEY]
    local hasContent = false
    -- "No spell data available" is NOT the same as "the bar is empty": GetBarSpellData returns nil
    -- while the active spec key is unresolved, which is exactly the loading-screen state. Treating
    -- that as empty ran the teardown below and UNREGISTERED a perfectly good proxy (sound dying after a port/zone until something rebuilt the bars). With the store not ready, leave the proxy exactly as it is; the next rebuild arms it.
    local storeReady, soundWanted = true, false
    if bd and bd.enabled ~= false then
        local sd = ns.GetBarSpellData and ns.GetBarSpellData(FOCUSKICK_BAR_KEY)
        if not sd then storeReady = false end
        local spells = sd and sd.assignedSpells
        if spells then
            for _, sid in ipairs(spells) do
                if type(sid) == "number" and sid > 0 then
                    hasContent = true
                    break
                end
            end
        end
        -- The cast SOUND has a weaker requirement than the rest of the family: its handler needs a
        -- configured sound plus an interrupt id for the readiness check, and the bar's assigned
        -- spells are only the FALLBACK source for that id -- an explicit focusKickInterruptSpellID
        -- satisfies it alone. Gating the sound on hasContent made a legitimate setup impossible: the focus-cast sound WITHOUT the kick icon.
        local sk = bd.focusCastSoundKey
        if sk and sk ~= "none" then
            local pick = bd.focusKickInterruptSpellID
            soundWanted = (type(pick) == "number" and pick > 0) or hasContent
        end
    end

    if not hasContent and not storeReady then
        -- Spell store unresolved: hold the current state rather than tearing down something that
        -- may still be correct, and COME BACK -- arming is otherwise a one-shot (its only callers
        -- are setup and the tail of BuildAllCDMBars), so a login/zone where the spec key has not
        -- resolved yet would leave the proxy unbuilt all session on a fully populated bar. An explicit interrupt spell id lives on the bar data, not the spell store, so the sound can arm right now; only the bar-content dependent parts have to wait.
        if soundWanted then EnsureFocusCastProxy() end
        -- One pending retry at a time, self-cancelling.
        if not ns._fkRearmPending then
            ns._fkRearmPending = true
            C_Timer.After(2, function()
                ns._fkRearmPending = nil
                if ns.RefreshFocusKickProxies then ns.RefreshFocusKickProxies() end
            end)
        end
        return
    end
    -- Icon-bearing parts of the family keep the original bar-content gate.
    if hasContent then
        EnsureFocusKickProxy()
        ApplyFocusKickAnchor()
        EnsureFocusReminderProxy()
        RefreshFocusReminders()
    else
        if _focusKickProxy then
            _focusKickProxy:UnregisterAllEvents()
            if _focusKickProxy._stop then _focusKickProxy._stop() end
            SetFocusKickAlpha(0)
        end
        if _focusReminderProxy then
            _focusReminderProxy:UnregisterAllEvents()
            HideAllFocusReminders()
        end
    end

    if soundWanted then
        EnsureFocusCastProxy()
    elseif _focusCastProxy then
        _focusCastProxy:UnregisterAllEvents()
    end
end


-- Ghost bars: ensure both buff and CD ghost bars exist in the bars array. Called from BuildAllCDMBars before iterating bars.
ns.GHOST_CD_BAR_KEY = GHOST_CD_BAR_KEY
local function EnsureGhostBars()
    local p = ECME.db and ECME.db.profile
    if not p or not p.cdmBars or not p.cdmBars.bars then return end
    local hasCD = false
    for _, b in ipairs(p.cdmBars.bars) do
        if b.key == GHOST_CD_BAR_KEY then hasCD = true end
    end
    if not hasCD then
        p.cdmBars.bars[#p.cdmBars.bars + 1] = {
            key = GHOST_CD_BAR_KEY,
            name = "Hidden CDs",
            barType = "cooldowns",
            isGhostBar = true,
            enabled = true,
            barVisibility = "never",
            iconSize = 1,
            spacing = 0,
            numRows = 1,
            growDirection = "RIGHT",
        }
    end
end
ns.EnsureGhostBars = EnsureGhostBars

-- Exports for extracted files (EllesmereUICdmHooks.lua, EllesmereUICdmSpellPicker.lua)
ns.MAIN_BAR_KEYS = MAIN_BAR_KEYS
ns.GetCDMFont = GetCDMFont
ns.ResolveInfoSpellID = ResolveInfoSpellID
ns.ResolveChildSpellID = ResolveChildSpellID
ns.ComputeTopRowStride = ComputeTopRowStride
-- Side-effect caches are now owned by EllesmereUICdmHooks.lua. The hooks file writes to ns._tick*
-- tables directly; these locals are populated from ns after the hooks file loads (in CDMFinishSetup). The ns._ecmeFC external frame cache is still owned by this file.
ns._ecmeFC = _ecmeFC
ns.FC = FC

-- Hook-based CDM Backend loaded from EllesmereUICdmHooks.lua
local BuildCustomBarSpellSet -- forward declare (defined below)

-------------------------------------------------------------------------------
--  Build a set of all spellIDs assigned to custom bars.
--  Used to prevent custom bar spells from leaking onto main bars during
--  snapshot or reconcile.
-------------------------------------------------------------------------------
BuildCustomBarSpellSet = function()
    local set = {}
    local p = ECME.db and ECME.db.profile
    if not p or not p.cdmBars or not p.cdmBars.bars then return set end
    for _, bd in ipairs(p.cdmBars.bars) do
        if not MAIN_BAR_KEYS[bd.key] then
            local sd = ns.GetBarSpellData(bd.key)
            if sd and sd.assignedSpells then
                for _, sid in ipairs(sd.assignedSpells) do
                    if sid and sid > 0 then set[sid] = true end
                end
            end
        end
    end
    return set
end
ns.BuildCustomBarSpellSet = BuildCustomBarSpellSet

-- (SnapshotBlizzardCDM / UpdateTrackedBarIcons removed -- replaced by hook-based CollectAndReanchor)

-- UpdateAllCDMBars: REMOVED. All recurring work is event-driven via hooks in EllesmereUICdmHooks.lua
-- -- CollectAndReanchor runs only when Blizzard fires OnCooldownIDSet, OnActiveStateChanged, Layout, or pool events. The stub exists only so any stale references don't error.
local function UpdateAllCDMBars(dt) end

-------------------------------------------------------------------------------
--  Bar Visibility (always / in combat / never) + Housing
-------------------------------------------------------------------------------

-- Does this cd/utility bar draw any frame out of the BuffIcon viewer? True for a
-- hosted buff (spellID-keyed) and for a cd-claimed collided buff slot. Called
-- only for the BuffIcon viewer's vote below, so bars pay nothing in the common
-- case where nothing is hosted. On ns, not a file local: this file sits at
-- Lua's 200-local cap.
function ns.BarUsesBuffViewer(barKey)
    local sd = ns.GetBarSpellData and ns.GetBarSpellData(barKey)
    if not sd then return false end
    if sd.hostedBuffSpellIDs and next(sd.hostedBuffSpellIDs) then return true end
    return (ns.CollectCdClaimSet and ns.CollectCdClaimSet(sd)) and true or false
end

_CDMApplyVisibility = function()
    local p = ECME.db and ECME.db.profile
    if not p then return end
    local inCombat = _inCombat
    -- Full vehicle UI: hide all bars
    local inVehicle = _cdmInVehicle
    -- Group state for mode checks
    local inRaid = IsInRaid and IsInRaid() or false
    local inParty = not inRaid and (IsInGroup and IsInGroup() or false)

    -- One state table per pass for the multi-select visibility engine
    local visState = { inCombat = inCombat, inRaid = inRaid, inParty = inParty }

    local unlockActive = EllesmereUI._unlockActive

    for _, barData in ipairs(p.cdmBars.bars) do
        local frame = cdmBarFrames[barData.key]
        if frame then
            -- FocusKick is owned exclusively by ApplyFocusKickAnchor. Don't touch its alpha or
            -- icons here -- the visibility check runs on unrelated events (combat enter/exit, vehicle, etc.) and would clobber the nameplate-driven show/hide state.
            if barData.key == FOCUSKICK_BAR_KEY then
                -- intentionally skipped
            -- Unlock mode: bars must stay visible for dragging
            -- Ghost bar stays hidden even in unlock mode
            elseif unlockActive and not barData.isGhostBar then
                frame:SetAlpha(1)
                -- Container stays motion-through even in unlock mode; drag handling lives on the unlock overlay frames, not the bar.
                if frame.EnableMouseMotion and not InCombatLockdown() then
                    frame:EnableMouseMotion(false)
                end
                frame._visHidden = false
            else

            local vis = barData.barVisibility or "always"
            local shouldHide = false

            -- Multi-select/dragonriding path: non-nil owns the mode step (priority 3); the legacy single-mode chain below is untouched.
            local visExt = EllesmereUI.EvalVisibilityExtended
                and EllesmereUI.EvalVisibilityExtended(barData, "barVisibility", visState, EllesmereUI.VIS_CAPS_DEFAULT)

            -- Priority 1: vehicle always hides
            if inVehicle then
                shouldHide = true
            -- Priority 2: visibility options (checkbox dropdown)
            elseif EllesmereUI.CheckVisibilityOptions(barData) then
                shouldHide = true
            -- Priority 3: visibility mode (multi-select or dragonriding scalar)
            elseif visExt ~= nil then
                shouldHide = not visExt
            elseif vis == "never" then
                shouldHide = true
            elseif vis == "in_combat" then
                shouldHide = not inCombat
            elseif vis == "out_of_combat" then
                shouldHide = inCombat
            elseif vis == "in_raid" then
                shouldHide = not inRaid
            elseif vis == "in_party" then
                shouldHide = not inParty
            elseif vis == "solo" then
                shouldHide = inRaid or inParty
            end

            if shouldHide then
                frame:SetAlpha(0)
                if frame.EnableMouseMotion and not InCombatLockdown() then frame:EnableMouseMotion(false) end
                frame._visHidden = true
                -- Cursor bars: park immediately on the hide edge. The glue shell self-sleeps on its next frame, so this is the one guaranteed park before it stops watching.
                if frame._mouseTrack and (frame:GetLeft() or 0) > -9000 then
                    frame._mouseParked = true
                    frame:ClearAllPoints()
                    frame:SetPoint(frame._mousePoint or "LEFT", UIParent, "BOTTOMLEFT", -10000, -10000)
                end
                -- Hide this bar's icons individually. The viewer may stay at alpha 1 (other bars
                -- need it), so icon alpha must be managed per-bar. EnableMouse is protected on Blizzard CDM frames; gate on combat lockdown to avoid ADDON_ACTION_BLOCKED.
                local icons = cdmBarIcons[barData.key]
                local icCombat = InCombatLockdown()
                if icons then
                    for ii = 1, #icons do
                        local ic = icons[ii]
                        if ic then
                            ic:SetAlpha(0)
                            if not icCombat then ic:EnableMouse(false) end
                        end
                    end
                end
            else
                local wasHidden = frame._visHidden
                -- Bar opacity is applied to icons only, not the frame. Custom injected icons are parented to the bar frame, so frame alpha would double-apply with icon alpha.
                frame:SetAlpha(1)
                -- The container never captures mouse motion: its rect spans the bar's full layout
                -- area, and a motion-enabled frame with no unit steals mouseover focus from unit frames underneath (hover highlights + [@mouseover] casts die under the bar). Icon hover is per-icon below, gated on the tooltip setting.
                if frame.EnableMouseMotion and not InCombatLockdown() then
                    frame:EnableMouseMotion(false)
                end
                frame._visHidden = false
                -- Cursor bars: resume the glue subscription the vis-hidden watch released; the resume snaps to the cursor immediately instead of waiting for the next 0.15s watch fire.
                if frame._mouseTrack and frame._mouseResume then
                    frame._mouseResume()
                end
                -- Apply opacity to icons every pass (idempotent, handles fresh loads where wasHidden is false). EffectiveBarAlpha folds in the out-of-combat fade when that option is on.
                local visAlpha = EffectiveBarAlpha(barData)
                local icons = cdmBarIcons[barData.key]
                local icCombat2 = InCombatLockdown()
                if icons then
                    for ii = 1, #icons do
                        local ic = icons[ii]
                        if ic then
                            local phHidden = IsPlaceholderRenderHidden(ic, barData)
                            -- EnableMouse/EnableMouseMotion are protected on Blizzard CDM frames; skip during combat to avoid ADDON_ACTION_BLOCKED when dismounting mid-combat.
                            if not icCombat2 then
                                ic:EnableMouse(false)
                                -- Same mouseover-stealing rule as the container above: icons may only
                                -- capture mouse motion when this bar's tooltips are on, and never on cursor-tracked bars (those must stay fully click-AND-motion-through).
                                -- An invisible placeholder never captures: there is nothing drawn to hover.
                                if ic.EnableMouseMotion then
                                    ic:EnableMouseMotion((barData.showTooltip and not frame._mouseTrack and not phHidden) and true or false)
                                end
                            end
                            local icfc = _ecmeFC[ic]
                            if phHidden then
                                -- Hide Icon: an Always-Show placeholder keeps its reserved layout slot but stays fully invisible (icon, border, bg).
                                ic:SetAlpha(0)
                            elseif not (icfc and (icfc._cdStateHidden or icfc._missingActiveHidden)) then
                                ic:SetAlpha(visAlpha)
                            end
                        end
                    end
                end
                if wasHidden then
                    -- Defer to a clean execution context: event handlers (PLAYER_TARGET_CHANGED, mount
                    -- events, etc.) can carry taint from the Blizzard dispatch chain. LayoutCDMBar calls SetSize/SetPoint which propagates the taint and triggers ADDON_ACTION_BLOCKED.
                    local bk = barData.key
                    C_Timer.After(0, function() LayoutCDMBar(bk) end)
                end
            end

            end -- unlockActive else
        end
    end

    -- Viewer alpha: icons are parented to Blizzard viewers and inherit their alpha. Only hide a
    -- viewer if ALL bars that use its icons are hidden. Otherwise a hidden default bar (e.g. "buffs" set to "never") would kill icons on visible custom bars that share the same viewer.
    for viewerBarKey, viewerName in pairs(BLIZZ_CDM_FRAMES) do
        local viewer = _G[viewerName]
        if viewer then
            -- The viewer must stay visible if ANY bar that uses its icons is visible (each bar has
            -- independent visibility). Mapping: cooldowns/utility bars use the Essential/Utility viewers; buff bars use the BuffIcon viewer; custom_buff (aura timer) bars use their own frames, not a viewer.
            local anyVisible = false
            for _, barData in ipairs(p.cdmBars.bars) do
                if barData.enabled then
                    local frame = cdmBarFrames[barData.key]
                    if frame and not frame._visHidden then
                        local bk = barData.key
                        if bk == viewerBarKey then
                            anyVisible = true; break
                        end
                        local bt = barData.barType
                        if bt ~= "custom_buff" then
                            if bt == "buffs" and viewerBarKey == "buffs" then
                                anyVisible = true; break
                            elseif bt ~= "buffs" and (viewerBarKey == "cooldowns" or viewerBarKey == "utility") then
                                anyVisible = true; break
                            -- A HOSTED buff renders on a cd/utility bar but its frame
                            -- still comes out of the BuffIcon viewer pool and is never
                            -- reparented, so it inherits that viewer's alpha. Without
                            -- this vote a visible cd/utility bar hosting a buff went
                            -- dark the moment the buffs bar was hidden: the aura-down
                            -- placeholder (our own frame, parented to UIParent) kept
                            -- rendering while the live buff did not.
                            elseif bt ~= "buffs" and viewerBarKey == "buffs"
                                   and ns.BarUsesBuffViewer(barData.key) then
                                anyVisible = true; break
                            end
                        end
                    end
                end
            end
            viewer:SetAlpha(anyVisible and 1 or 0)
        end
    end
end
ns.CDMApplyVisibility = _CDMApplyVisibility
_G._ECME_ApplyVisibility = _CDMApplyVisibility

-- Live-apply bar opacity to a bar's frame + icons. Skips hidden bars so visibility state is never overridden (hidden stays at alpha 0).
local function ApplyBarOpacity(barKey)
    local frame = cdmBarFrames[barKey]
    if not frame or frame._visHidden then return end
    local barData = barDataByKey[barKey]
    if not barData then return end
    if barKey == FOCUSKICK_BAR_KEY then return end
    local a = EffectiveBarAlpha(barData)
    local icons = cdmBarIcons[barKey]
    if icons then
        for i = 1, #icons do
            local ic = icons[i]
            if ic then
                local icfc = _ecmeFC[ic]
                if IsPlaceholderRenderHidden(ic, barData) then
                    -- Hide Icon: an Always-Show placeholder keeps its reserved
                    -- layout slot but stays fully invisible (icon, border, bg).
                    ic:SetAlpha(0)
                elseif not (icfc and (icfc._cdStateHidden or icfc._missingActiveHidden)) then
                    ic:SetAlpha(a)
                end
            end
        end
    end
end
ns.ApplyBarOpacity = ApplyBarOpacity

-- Helper to get barData by key
function GetBarData(barKey)
    return barDataByKey[barKey]
end
ns.GetBarData = GetBarData



-------------------------------------------------------------------------------
--  Keybind cache for CDM icons
--  Resolves binding keys per action slot. In Stable mode, the main bar is
--  scanned across home page + bonus pages (forms/stealth/skyriding), so the
--  cache does not follow bar swaps and a key only changes when the player
--  moves the ability or rebinds it. Manually-paged pages 2-6 are excluded --
--  their contents aren't reliably something the player set up on purpose.
--  Read-only + text writes on our own frames, so it is safe to run in combat
--  (debounced upstream).
-------------------------------------------------------------------------------

-- Forward-declared: everything else in this section lives inside the do-block
-- below so its locals are freed again. This file is at the Lua 5.1 200-local
-- ceiling for the main chunk, and the multi-page scan needs several helpers.
local UpdateCDMKeybinds
do

-- Action bar slot -> binding name map, with the priority tier each source
-- feeds into _SetKeybind (lower wins). These bars have fixed slots and never
-- page, so they outrank every main-bar page: if a spell sits on both, the
-- dedicated bar's key is the one that always works.
-- The main bar (ACTIONBUTTON1-12) is not listed here -- it needs per-page slot
-- math and is scanned separately below.
local _barBindingDefs = {
    { prefix = "MULTIACTIONBAR1BUTTON", startSlot = 61,  tier = 1 },  -- bar 2 bottom left
    { prefix = "MULTIACTIONBAR2BUTTON", startSlot = 49,  tier = 2 },  -- bar 3 bottom right
    { prefix = "MULTIACTIONBAR3BUTTON", startSlot = 25,  tier = 3 },  -- bar 4 right
    { prefix = "MULTIACTIONBAR4BUTTON", startSlot = 37,  tier = 4 },  -- bar 5 left
    { prefix = "MULTIACTIONBAR5BUTTON", startSlot = 145, tier = 5 },  -- bar 6
    { prefix = "MULTIACTIONBAR6BUTTON", startSlot = 157, tier = 6 },  -- bar 7
    { prefix = "MULTIACTIONBAR7BUTTON", startSlot = 169, tier = 7 },  -- bar 8
    -- EUI bars 9/10 have no native binding command: their keys are routed
    -- through the button with SetOverrideBindingClick against the custom
    -- commands declared in the Action Bars module's Bindings.xml. Because that
    -- route always reads the button's live "action" attr, resolve the slot from
    -- the button when it exists and only fall back to the base page slot when
    -- the Action Bars module is not loaded (handled where this def is consumed).
    { prefix = "EUI_BAR9_BUTTON",       startSlot = 13,  tier = 8, eabButton = true },  -- bar 9  (action page 2)
    { prefix = "EUI_BAR10_BUTTON",      startSlot = 109, tier = 9, eabButton = true },  -- bar 10 (action page 10)
}

-- Main-bar tiers. Page 1 is the "home" state and outranks the form/stealth/
-- skyriding bonus pages.
--
-- Pages 2-6 (manual paging, e.g. Shift+MouseWheel -- a stock WoW binding, not
-- an EAB-specific feature) are deliberately NOT scanned. Unlike page 1 and the
-- bonus pages, nothing guarantees their contents are something the player
-- actually curated: WoW keeps whatever was last placed there (leftovers from
-- a previous bar addon, a default-populated slot, an accidental scroll) and
-- GetActionInfo returns it regardless. Root-caused 2026-08-07: a tracked,
-- genuinely unbound Utility spell showed a phantom "CR" key because slot 11
-- of page 6 -- never intentionally used -- happened to hold something under
-- the ACTIONBUTTON11 binding. Since the tracked spell had no other entry,
-- that stray page-6 read became its only (wrong) answer. Multibars and bonus
-- pages don't have this problem: multibars are explicit EAB bar assignments,
-- and bonus pages are gated by real, meaningful game state (stealth/form/
-- skyriding), not "whatever a stray scroll last revealed."
-- Tiers 8-9 are taken by EUI_BAR9_BUTTON/EUI_BAR10_BUTTON above (also
-- non-main-bar, so they outrank the main bar the same way).
local _TIER_MAINBAR_HOME  = 10   -- page 1        -> slots 1-12
local _TIER_MAINBAR_BONUS = 11   -- pages 7-11    -> slots 73-132  (+ pg - 7)
-- A macro-sourced bind is always outranked by a direct one, whatever the bar.
local _RANK_MACRO_PENALTY = 100

-- Whether this rebuild runs in stable mode. Latched once per rebuild rather
-- than re-read per slot, and gates BOTH halves of the feature: the multi-page
-- main bar scan and the macro body scan. With the option off, every path below
-- must behave exactly as it did before the feature existed.
local _stableMode = false

local function FormatKeybindKey(key)
    if not key or key == "" then return nil end
    -- Gamepad binds resolve to glyph markup (no atlas name matches a substitution
    -- below); keyboard binds keep the raw tokens the substitutions are written against.
    local resolved = GetBindingText(key, 1)
    if resolved and resolved:find("|A:", 1, true) then
        key = resolved
    end
    key = key:gsub("SHIFT%-", "S")
    key = key:gsub("CTRL%-",  "C")
    key = key:gsub("ALT%-",   "A")
    key = key:gsub("META%-",  "M")  -- Mac Command key (CMD-E -> ME)
    key = key:gsub("Mouse Button ", "M")
    key = key:gsub("MOUSEWHEELUP",   "MwU")
    key = key:gsub("MOUSEWHEELDOWN", "MwD")
    key = key:gsub("CAPSLOCK", "Caps")
    key = key:gsub("NUMPADDECIMAL",  "N.")
    key = key:gsub("NUMPADPLUS",     "N+")
    key = key:gsub("NUMPADMINUS",    "N-")
    key = key:gsub("NUMPADMULTIPLY", "N*")
    key = key:gsub("NUMPADDIVIDE",   "N/")
    key = key:gsub("NUMPAD",         "N")
    key = key:gsub("BUTTON",         "M")
    return key ~= "" and key or nil
end

-- Store a keybind under a cache key, best-rank-wins. The rank encodes both
-- which bar/page the bind came from (see the tier constants above) and
-- macro-deprioritization: a direct (non-macro) bind always beats a macro one,
-- whatever bar each sits on, so a user who has both a macro and the real spell
-- bound sees the real spell's key. Equal rank keeps the first writer, which
-- preserves scan order within a single bar.
local function _SetKeybind(cacheKey, formatted, rank)
    if not formatted then return end
    local cur = _cdmKeybindRank[cacheKey]
    if cur == nil or rank < cur then
        _cdmKeybindCache[cacheKey] = formatted
        _cdmKeybindRank[cacheKey] = rank
    end
end

-- Cache a spell under every id an icon might present it as: the id itself,
-- its name, and its override/base partners. A nil id is a no-op -- callers
-- hand through whatever GetActionInfo/GetMacroSpell returned, and writing a
-- nil cache key would be a hard error.
local function _SetSpellKeybind(spellID, formatted, rank)
    if not spellID then return end
    _SetKeybind(spellID, formatted, rank)
    local name = C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
    if name then _SetKeybind(name, formatted, rank) end
    local ovr = C_Spell.GetOverrideSpell and C_Spell.GetOverrideSpell(spellID)
    if ovr and ovr ~= spellID then _SetKeybind(ovr, formatted, rank) end
    local base = C_Spell.GetBaseSpell and C_Spell.GetBaseSpell(spellID)
    if base and base ~= spellID then _SetKeybind(base, formatted, rank) end
end

-- Macro commands whose arguments are a list of cast/use targets. English only:
-- localized aliases (/zauber, ...) exist but the English commands work on every
-- client and are what the overwhelming majority of macros use.
local _MACRO_CAST_CMDS = {
    cast = true, castsequence = true, castrandom = true,
    use = true, userandom = true,
}

-- One target token out of a macro's cast list.
local function _RegisterMacroTarget(token, formatted, rank)
    -- Drop a leading castsequence reset clause ("reset=combat/5 Spell").
    token = token:gsub("^reset=%S*%s*", "")
    if token == "" then return end
    -- "item:NNNN" is macro-only shorthand for targeting an itemID directly. It
    -- is NOT a valid GetItemInfoInstant input (that wants a bare itemID, item
    -- name, or a full item link) -- pull the numeric ID out ourselves instead
    -- of handing the literal "item:NNNN" string to it.
    local itemID = token:match("^item:(%d+)")
    if itemID then
        _SetKeybind(-tonumber(itemID), formatted, rank)
        return
    end
    local sid = token:match("^spell:(%d+)")
    if sid then
        _SetSpellKeybind(tonumber(sid), formatted, rank)
        return
    end
    -- A bare number is ambiguous in macro syntax (inventory slot vs itemID),
    -- so it is left alone rather than guessed at.
    if tonumber(token) then return end
    -- Leftover bracket means the body had an unbalanced [condition] that the
    -- %b[] strip could not remove. Whatever is left is not a usable name.
    if token:find("[%[%]]") then return end
    -- Store the raw name too: ApplyCachedKeybinds falls back to a name lookup,
    -- which still hits when the spell itself cannot be resolved right now.
    _SetKeybind(token, formatted, rank)
    local id = C_Spell.GetSpellIDForSpellIdentifier and C_Spell.GetSpellIDForSpellIdentifier(token)
    if id then
        _SetSpellKeybind(id, formatted, rank)
    else
        local iid = C_Item and C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(token)
        if iid then _SetKeybind(-iid, formatted, rank) end
    end
end

-- Register every branch of a macro body, not just the one that is live now.
--
-- This is the second half of the bar-swap problem, and it is independent of
-- paging: Blizzard's own resolution (GetMacroSpell, and the "smart" macro
-- subType) evaluates the macro's conditionals against the CURRENT state. So
--     #showtooltip Shadow Dance
--     /cast [bonusbar:1] Backstab; Shadow Dance
-- reports Shadow Dance while unstealthed and Backstab while stealthed -- and
-- Shadow Dance loses its key the moment the rogue stealths, with the action
-- slot itself never changing. Parsing the body registers both branches, so
-- the key sticks to whichever one the CDM icon happens to show.
local function _RegisterMacroTargets(body, formatted, rank)
    for line in body:gmatch("[^\r\n]+") do
        local cmd, args = line:match("^%s*/(%a+)!?%s*(.*)$")
        if cmd and args ~= "" and _MACRO_CAST_CMDS[cmd:lower()] then
            -- Each ";"-separated clause is one conditional branch; a
            -- castsequence packs several targets into one clause via ",".
            for clause in args:gmatch("[^;]+") do
                -- Drop the [condition] groups -- every branch counts here.
                clause = clause:gsub("%b[]", "")
                for token in clause:gmatch("[^,]+") do
                    token = token:match("^%s*!?%s*(.-)%s*$")
                    if token and token ~= "" then
                        _RegisterMacroTarget(token, formatted, rank)
                    end
                end
            end
        end
    end
end

-- Legacy fallback for a macro that GetMacroSpell could not resolve: pull the
-- first /use target out of the body and register it as an item. Kept verbatim
-- so the option-off path stays byte-for-byte the pre-feature behaviour; the
-- stable path uses the full body scan above instead.
local function _RegisterLegacyMacroItem(macroIndex, formatted, rank)
    local body = GetMacroBody and GetMacroBody(macroIndex)
    local target = body and body:match("/use!?%s+([^\r\n]+)")
    if not target then return end
    target = target:gsub("^%[.-%]%s*", ""):match("^%s*(.-)%s*$")
    local itemID = target:match("^item:(%d+)")
    itemID = itemID and tonumber(itemID)
    if not itemID and not tonumber(target) then
        itemID = C_Item and C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(target)
    end
    if itemID then _SetKeybind(-itemID, formatted, rank) end
end

-- Resolve one action slot under one binding key into cache entries, at the
-- given priority tier. Pure lookups plus writes into the two cache tables.
local function _ResolveSlotBinding(slot, key, tier)
    local formatted = FormatKeybindKey(key)
    if not formatted then return end
    local macroRank = tier + _RANK_MACRO_PENALTY
    local slotType, id, subType = GetActionInfo(slot)
    if slotType == "spell" then
        _SetSpellKeybind(id, formatted, tier)
    elseif slotType == "macro" then
        -- "Smart" single-spell macro: Blizzard already resolved it, and `id`
        -- here IS the spellID, not a macro index -- passing it to
        -- GetMacroSpell would look up the wrong thing.
        if subType == "spell" then
            _SetSpellKeybind(id, formatted, macroRank)
            -- Legacy took Blizzard's single answer as final. Stable mode falls
            -- through to the body scan, which is the whole point: that answer
            -- is state-dependent and hides the other branches.
            if not _stableMode then return end
        end
        -- For everything else `id` from GetActionInfo is NOT a reliable
        -- identifier -- resolve the real macro index via its name instead
        -- (same workaround EllesmereUICdmHooks.lua's SlotSpellID already uses).
        local macroName = GetActionText(slot)
        local macroIndex = macroName and GetMacroIndexByName(macroName)
        if macroIndex and macroIndex > 0 then
            local live = GetMacroSpell(macroIndex)
            if live then _SetSpellKeybind(live, formatted, macroRank) end
            if _stableMode then
                local body = GetMacroBody and GetMacroBody(macroIndex)
                if body then _RegisterMacroTargets(body, formatted, macroRank) end
            elseif not live then
                _RegisterLegacyMacroItem(macroIndex, formatted, macroRank)
            end
        end
    elseif slotType == "item" and id then
        -- Store under negated itemID (-id) to match the FC convention for
        -- item presets/trinkets.
        _SetKeybind(-id, formatted, tier)
    end
end

-- Stable scan: resolve ACTIONBUTTONn against the pages that reliably reflect
-- something the player actually set up -- home page plus the bonus pages
-- (forms, stealth, stances, skyriding), not the page that happens to be
-- active right now. That makes the cache independent of bar swaps, so a
-- keybind only ever changes when the player actually moves the ability or
-- rebinds the key.
--
-- Deliberately excluded: manually-paged pages 2-6 (see the tier comment
-- above) and the vehicle/override/temp-shapeshift pages. The latter's
-- contents are server-pushed and transient rather than a layout the player
-- configured, and their page indices can overlap the slot ranges of action
-- bars 6-8 (145-180), which are already scanned via _barBindingDefs.
local function _ScanMainBarStable(i, key)
    _ResolveSlotBinding(i, key, _TIER_MAINBAR_HOME)
    -- Bonus bars 1-5 (forms, stealth, stances, skyriding) = pages 7-11.
    for pg = 7, 11 do
        _ResolveSlotBinding(i + (pg - 1) * 12, key, _TIER_MAINBAR_BONUS + pg - 7)
    end
end

-- Legacy scan: resolve ACTIONBUTTONn against the currently active page only.
-- Prefer the EAB main bar's actionpage attribute (set by its secure page
-- handler, covers override/vehicle pages too). Without it (Action Bars module
-- disabled), derive the page from the client: bonus bars (forms) map to pages
-- 7+, but only when page 1 is otherwise active -- a manual page beats the
-- form/skyriding swap, same priority order the engine itself uses.
local function _ScanMainBarLive(i, key)
    local mbf = _G["EABBar_MainBar"]
    local pg = mbf and tonumber(mbf:GetAttribute("actionpage"))
    if not pg then
        local bonus = GetBonusBarOffset and GetBonusBarOffset() or 0
        local page = (GetActionBarPage and GetActionBarPage()) or 1
        if bonus > 0 and page == 1 then
            pg = 6 + bonus
        else
            pg = page
        end
    end
    _ResolveSlotBinding(i + (pg - 1) * 12, key, _TIER_MAINBAR_HOME)
end

-- Global toggle for the stable scan. Default ON via DEFAULTS; the strict
-- == true read means a pre-merge call (key not seeded yet) falls back to
-- the legacy live-page scan for that pass.
local function StableKeybindsEnabled()
    local p = ECME.db and ECME.db.profile
    return (p and p.cdmBars and p.cdmBars.stableKeybinds) == true
end
ns.CDMStableKeybindsEnabled = StableKeybindsEnabled

local function RebuildKeybindCache()
    wipe(_cdmKeybindCache)
    wipe(_cdmKeybindRank)
    -- Latch the mode for this whole rebuild so the multi-page scan and the
    -- macro body scan can never disagree about it mid-pass.
    _stableMode = StableKeybindsEnabled()
    for _, def in ipairs(_barBindingDefs) do
        for i = 1, 12 do
            local key = GetBindingKey(def.prefix .. i)
            if key then
                local slot = def.startSlot + i - 1
                if def.eabButton then
                    -- EUI bars 9/10 have no native binding command: their keys
                    -- are routed through the button with SetOverrideBindingClick
                    -- against the custom commands declared in the Action Bars
                    -- module's Bindings.xml. That route always reads the
                    -- button's live "action" attr, so resolve the slot from the
                    -- button when it exists (custom paging) and only fall back
                    -- to the base page slot when the Action Bars module isn't
                    -- loaded.
                    local btn = _G["EABButton" .. slot]
                    local live = btn and tonumber(btn:GetAttribute("action"))
                    if live then slot = live end
                end
                _ResolveSlotBinding(slot, key, def.tier)
            end
        end
    end
    local scanMainBar = _stableMode and _ScanMainBarStable or _ScanMainBarLive
    for i = 1, 12 do
        local key = GetBindingKey("ACTIONBUTTON" .. i)
        if key then scanMainBar(i, key) end
    end
end

-- Apply the current cache to all visible CDM icon keybind texts
local function ApplyCachedKeybinds()
    for barKey, icons in pairs(cdmBarIcons) do
        local bd = barDataByKey[barKey]
        for _, icon in ipairs(icons) do
            local ifd = _getFD(icon)
            local kbText = ifd and ifd.keybindText or icon._keybindText
            if kbText then
                local ifc = _ecmeFC[icon]
                local sid = ifc and ifc.spellID
                if bd and bd.showKeybind and sid then
                    local key = _cdmKeybindCache[sid]
                    if not key then
                        local ovr = C_Spell.GetOverrideSpell and C_Spell.GetOverrideSpell(sid)
                        if ovr and ovr ~= sid then key = _cdmKeybindCache[ovr] end
                    end
                    if not key then
                        local base = C_Spell.GetBaseSpell and C_Spell.GetBaseSpell(sid)
                        if base and base ~= sid then key = _cdmKeybindCache[base] end
                    end
                    local name = sid > 0 and C_Spell.GetSpellName and C_Spell.GetSpellName(sid)
                    if not key and name then key = _cdmKeybindCache[name] end
                    -- Item presets: the resolved display variant first (pot presets may be showing another rank/Fleeting/the swapped-in partner pot), then the static alt ids.
                    if not key and icon._isItemPresetFrame and icon._displayItemID then
                        key = _cdmKeybindCache[-icon._displayItemID]
                    end
                    -- Item presets: check alt item IDs (user may have a different rank of the same potion on their bar).
                    if not key and icon._isItemPresetFrame and icon._presetData and icon._presetData.altItemIDs then
                        for _, altID in ipairs(icon._presetData.altItemIDs) do
                            key = _cdmKeybindCache[-altID]
                            if key then break end
                        end
                    end
                    -- Trinkets: check by equipped item's action slot
                    if not key and icon._isTrinketFrame and icon._trinketSlot then
                        local itemID = GetInventoryItemID("player", icon._trinketSlot)
                        if itemID then key = _cdmKeybindCache[-itemID] end
                    end
                    if key then
                        kbText:SetText(key)
                        kbText:Show()
                    else
                        kbText:Hide()
                    end
                else
                    kbText:Hide()
                end
            end
        end
    end
end

UpdateCDMKeybinds = function()
    RebuildKeybindCache()
    _keybindCacheReady = true
    -- Defer apply by one frame so the Blizzard tick has populated FC(icon).spellID
    C_Timer.After(0, ApplyCachedKeybinds)
end
ns.UpdateCDMKeybinds = UpdateCDMKeybinds
-- Expose apply-only for the tick loop (new spellID assigned to an icon mid-session)
ns.ApplyCachedKeybinds = ApplyCachedKeybinds
ns.CDMKeybindCache = _cdmKeybindCache

end -- keybind cache block

BuildAllCDMBars = function()
    ns._spellOrderDirty = true  -- force spell order cache rebuild
    -- Belt for the active-store cache: every profile apply, import, layout switch and options rebuild passes through here.
    ns._cachedSpecProfiles = nil
    ns._cdmStoreMemo = nil
    -- Structural edges: claims and resolution inputs both change across a rebuild, so retire the proc-alert claim map and cdID resolution memo.
    ns._cdmClaimGen = ns._cdmClaimGen + 1
    ns._cdmResGen = ns._cdmResGen + 1
    -- Hard guard: never build with an unknown spec. CDMFinishSetup is gated on GetActiveSpecKey() at OnEnable, so this is a defense in depth for any other path that calls BuildAllCDMBars too early.
    if not ns.GetActiveSpecKey() then return end

    -- Mark CDM as rebuilding so width/height match propagation gates off (it would otherwise read
    -- transient bar widths sized for the previous spec's icon count and bake them into
    -- _matchPhysWidth on dependent bars). Cleared at the end of CollectAndReanchor when _pendingApplyOnReanchor fires the authoritative ApplyAllWidthHeightMatches pass.
    if EllesmereUI then EllesmereUI._cdmRebuilding = true end

    -- Ensure ghost bars exist before iterating bars
    EnsureGhostBars()
    EnsureFocusKickBar()
    ns.RescanMaxStacksGlowFlag()  -- set the Max Stacks Glow gate (once) before refresh
    ns.RescanChargeCdTextFlag()   -- set the Hide CD Text (Charges) gate (once) before refresh
    ns.RescanHideChargeTextFlag() -- set the Hide Charge Text gate (once) before refresh
    ns.RescanSuppressGcdFlag()    -- set the per-spell Suppress GCD gate (once) before refresh
    ns.RescanChargeStyleFlag()    -- set the Hide Swipe (Charges) gate (once) before refresh
    ns.RescanBuffSoundFlag()      -- set the Audio on Buff Gain/Loss gate (once) before refresh
    ns.RescanCdReadySoundFlag()   -- set the Audio Effect on CD Ready gate (once) before refresh
    ns.RescanCustomItemFlag()     -- set the custom-item buff-injection gate (once)
    ns.RescanCustomForceCountFlag() -- set the "Show Charges" custom-spell gate (once)
    ns.RescanReverseSwipeFlag()   -- set the Reverse Swipe gate (once) before refresh
    ns.RescanThresholdTextFlag()  -- set the Threshold Text gate (once) before refresh
    ns.RescanCustomIconFlag()     -- set the per-spell Custom Icon gate (once) before refresh
    ns.RescanActiveGlowFlag()     -- set the Active State Glow gate (once) before refresh

    local p = ECME.db.profile

    -- Heal ghost bar entries: an override write to a numeric bar path whose bar no longer existed
    -- (profile import, or a deleted bar with a stored override still referencing its index) used to
    -- auto-create a skeleton table (e.g. { barVisibility = "always" }) with no key. Every keyed
    -- consumer (spell data, racial normalize, unlock snapshots) then errors on the nil key. The override writer no longer fabricates numeric containers; this prunes profiles that already carry ghosts.
    if type(p.cdmBars.bars) == "table" then
        for i = #p.cdmBars.bars, 1, -1 do
            local bd = p.cdmBars.bars[i]
            if type(bd) ~= "table" or not bd.key then
                table.remove(p.cdmBars.bars, i)
            end
        end
    end

    if not p.cdmBars.enabled then
        -- Restore Blizzard CDM if we're disabled
        RestoreBlizzardCDM()
        for key, frame in pairs(cdmBarFrames) do
            EllesmereUI.SetElementVisibility(frame, false)
        end
        return
    end

    -- Migrate the old global Always Show Buffs settings to per-bar before anything reads them (placeholder injection/desaturate ticker).
    if ns.MigrateAlwaysShowBuffsToPerBar then ns.MigrateAlwaysShowBuffsToPerBar() end
    -- Then merge legacy custom_buff (Auras) bars into the buff-family bars.
    if ns.MigrateCustomBuffBarsToBuffBars then ns.MigrateCustomBuffBarsToBuffBars() end

    -- Force Blizzard's EditMode CooldownViewer to "Always Visible" so hideWhenInactive and other viewer settings don't fight with CDM.
    EnforceCooldownViewerEditModeSettings()

    -- Hide Blizzard CDM
    if p.cdmBars.hideBlizzard then
        HideBlizzardCDM()
    end

    -- If user wants Blizzard's tracking bars instead of TBB, restore the secondary
    -- BuffBarCooldownViewer that HideBlizzardCDM moved offscreen. This only affects the bar-style buff viewer; CDM icon bars are untouched.
    if p.cdmBars.useBlizzardBuffBars and p.cdmBars.hideBlizzard then
        RestoreBlizzardBuffFrame()
    end


    -- Build each bar and populate fast lookup
    local hookActive = ns.IsViewerHooked and ns.IsViewerHooked()
    wipe(barDataByKey)
    ns._cdmAnyOverflowCfg = nil
    for i, barData in ipairs(p.cdmBars.bars) do
        barDataByKey[barData.key] = barData
        -- Live migration: buffGlowMode replaced buffGlowClassColor + "buffGlowR set" nil checks
        if not barData.buffGlowMode then
            if barData.buffGlowClassColor then
                barData.buffGlowMode = "class"
            elseif barData.buffGlowR ~= nil then
                barData.buffGlowMode = "custom"
            else
                barData.buffGlowMode = "default"
            end
        end
        -- Live migration: pandemicGlowMode replaced pandemicGlowColor always being set
        if not barData.pandemicGlowMode then
            local c = barData.pandemicGlowColor
            if c and not (c.r == 1 and c.g == 1 and c.b == 0) then
                barData.pandemicGlowMode = "custom"
            else
                barData.pandemicGlowMode = "default"
            end
        end
        -- Max Icons overflow: cheap session gate. Validity of the target is checked at reanchor time (Phase 3b); this only answers "is it worth looking" so the feature is two nil-checks when unused.
        if not ns._cdmAnyOverflowCfg and barData.enabled
           and barData.maxIcons and barData.maxIcons > 0
           and barData.overflowTarget then
            ns._cdmAnyOverflowCfg = true
        end
        BuildCDMBar(i)
        local frame = cdmBarFrames[barData.key]
        if frame then frame._prevVisibleCount = nil end
        if hookActive and BLIZZ_CDM_FRAMES[barData.key] then
            -- Hooked default bar: skip icon state reset and layout. CollectAndReanchor will repopulate from viewer pools.
        else
            RefreshCDMIconAppearance(barData.key)
            -- Reset cached icon state so textures re-evaluate after a character switch
            local icons = cdmBarIcons[barData.key]
            if icons then
                for _, icon in ipairs(icons) do
                    local iifc = FC(icon)
                    iifc.lastTex = nil; iifc.lastDesat = nil; iifc.blizzChild = nil
                    iifc.spellID = nil
                end
            end
            LayoutCDMBar(barData.key)
            ApplyCDMTooltipState(barData.key)
        end
    end
    -- Resync the key-press-mirror fast enable-flag with the rebuilt bar list, so OnPress O(1)-gates instead of looping every bar per press (covers profile and spec swaps, not just the options toggle).
    if ns.RefreshCdmPressMirrorFlag then ns.RefreshCdmPressMirrorFlag() end
    -- Custom-aura containers re-evaluate here: icon size, shape, spacing and
    -- growth change the engine flow, which needs a rebuild rather than a
    -- restyle, and a hooked default bar skips RefreshCDMIconAppearance above.
    if ns.UpdateCustomBuffAuraTracking then ns.UpdateCustomBuffAuraTracking() end
    -- When hooks are active, queue a reanchor to repopulate default bars. The queued
    -- CollectAndReanchor will lift _cdmRebuilding when it finishes; if no reanchor is queued (hooks not yet installed) we must clear the flag here ourselves so width matching can run again.
    if hookActive and ns.QueueReanchor then
        ns.QueueReanchor()
    else
        if EllesmereUI then EllesmereUI._cdmRebuilding = nil end
    end
    -- Re-apply saved positions now that LayoutCDMBar has set correct frame sizes. Positions are
    -- stored using the edge anchor directly (LEFT for RIGHT-grow, etc.), so SetPoint places the frame at its fixed edge and subsequent SetSize calls grow naturally from that edge.
    for _, barData in ipairs(p.cdmBars.bars) do
        if barData.enabled then
            local ak = barData.anchorTo
            if not ak or ak == "none" then
                local frame = cdmBarFrames[barData.key]
                local pos = p.cdmBarPositions[barData.key]
                if frame and pos and pos.point then
                    local unlockKey = "CDM_" .. barData.key
                    local anchored = EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored(unlockKey)
                    if not anchored or not frame:GetLeft() then
                        ApplyBarPositionCentered(frame, pos, barData.key)
                    end
                end
            end
        end
    end
    -- Second pass: reapply unlock-mode anchors now that ALL bars are positioned and sized. The
    -- first pass (inside LayoutCDMBar) may have run ReapplyOwnAnchor before the target bar was repositioned (e.g. cooldowns processed before utility). This corrects that.
    if EllesmereUI.ReapplyOwnAnchor then
        for _, barData in ipairs(p.cdmBars.bars) do
            EllesmereUI.ReapplyOwnAnchor("CDM_" .. barData.key)
        end
    end
    UpdateCDMKeybinds()

    -- Apply visibility (hides bars set to "in combat only", "never", etc; handles unlock-mode override and viewer alpha sync). Single authority.
    _CDMApplyVisibility()

    -- Batch-apply pending cooldown font styling (single deferred call, no per-icon closures)
    C_Timer.After(0, function()
        for _, icons in pairs(cdmBarIcons) do
            for _, icon in ipairs(icons) do
                local ifc = _ecmeFC[icon]
                local pendFP = ifc and ifc.pendingFontPath
                if pendFP then
                    local ifd = _getFD(icon)
                    local cd = ifd and ifd.cooldown or icon._cooldown
                    if cd then
                        local fontPath, fontSize = pendFP, ifc.pendingFontSize
                        local fR = ifc.pendingFontR
                        local fG = ifc.pendingFontG
                        local fB = ifc.pendingFontB
                        for ri = 1, cd:GetNumRegions() do
                            local region = select(ri, cd:GetRegions())
                            if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                                SetBlizzCDMFont(region, fontPath, fontSize, fR, fG, fB)
                                break
                            end
                        end
                        ifc.pendingFontPath = nil; ifc.pendingFontSize = nil
                        ifc.pendingFontR = nil; ifc.pendingFontG = nil; ifc.pendingFontB = nil
                    end
                end
            end
        end
    end)

    -- Every full rebuild re-evaluates the FocusKick demand gate, so assigning the first kick spell (or removing the last) flips the feature family on/off live.
    if ns.RefreshFocusKickProxies then ns.RefreshFocusKickProxies() end
end

-- Expose for options
ns.BuildAllCDMBars = BuildAllCDMBars
ns.cdmBarFrames = cdmBarFrames
ns.cdmBarIcons = cdmBarIcons
ns.barDataByKey = barDataByKey
ns.SaveCDMBarPosition = SaveCDMBarPosition
ns.LayoutCDMBar = LayoutCDMBar
ns.BLIZZ_CDM_FRAMES = BLIZZ_CDM_FRAMES
ns.CDM_BAR_CATEGORIES = CDM_BAR_CATEGORIES
ns.MAX_CUSTOM_BARS = MAX_CUSTOM_BARS
ns.FindPlayerPartyFrame = EllesmereUI.FindPlayerPartyFrame

-- Expose LayoutCDMBar globally so unlock mode can trigger rebuilds
EllesmereUI.LayoutCDMBar = LayoutCDMBar
ns.FindPlayerUnitFrame = EllesmereUI.FindPlayerUnitFrame
ns.RestoreBlizzardCDM = RestoreBlizzardCDM
ns.HideBlizzardCDM = HideBlizzardCDM

-------------------------------------------------------------------------------
--  FullCDMRebuild
--  The ONE function for "something changed". Treats every call the same:
--  wipe all caches, clear stale frames, rebuild bars, rebuild TBB,
--  reanchor, reapply visibility, update keybinds. Identical result to
--  a fresh login. Use this for spec switch, talent change, zone
--  transition, profile import, equipment change, etc.
--  For cosmetic-only changes (icon size, fonts, glows) call
--  BuildAllCDMBars() directly.
-------------------------------------------------------------------------------
local _rebuildGen = 0

-- Rewrite stored racial spell IDs on CD/utility bars to this character's active racial: a shared
-- profile keeps whichever race's racial each character added, so collapse them to a single
-- "Racial" slot that follows each character's race without re-adding. Operates on the active
-- spec's lists (other specs normalize when they next become active). No-op on buff bars and when
-- no active racial resolves. Family-global: across ALL non-buff bars the racial ends up on at most
-- ONE bar. If the active racial is already placed, keep it where it sits and strip every other racial (foreign leftovers AND stray duplicates); if no active racial is present, promote the first foreign racial in place so the slot still appears for this character.
function ns.NormalizeRacialAssignments()
    -- Re-resolve now: at build time the spellbook is reliably populated, so the variant pick (Blood Fury/Arcane Torrent/Gift of the Naaru) is correct even if OnEnable ran before the spellbook loaded.
    local active = ResolveActiveRacial()
    if not active or active <= 0 then return end
    local p = ECME.db and ECME.db.profile
    if not (p and p.cdmBars and p.cdmBars.bars) then return end

    -- Gather the non-buff bars' assigned lists once (in bar order), keeping
    -- each list's bar key so the keeper choice below can tell default bars
    -- from explicit custom placements.
    local lists, listBarKeys = {}, {}
    for _, b in ipairs(p.cdmBars.bars) do
        local isBuff = (b.barType == "custom_buff")
            or (ns.IsBarBuffFamily and ns.IsBarBuffFamily(b))
        -- b.key guard: a ghost bar (keyless skeleton from a stale override write) would index barSpells with nil and error.
        if not isBuff and b.key then
            local sd = ns.GetBarSpellData(b.key)
            if sd and sd.assignedSpells then
                lists[#lists + 1] = sd.assignedSpells
                listBarKeys[#lists] = b.key
            end
        end
    end

    -- Is the active racial already placed on a bar (this character's pick)?
    local activePresent = false
    for _, list in ipairs(lists) do
        for _, sid in ipairs(list) do
            if sid == active then activePresent = true; break end
        end
        if activePresent then break end
    end

    -- Keeper choice: prefer the copy on a CUSTOM bar. Lists iterate in bar
    -- order with the default bars first, so the old first-found-wins rule kept
    -- the Essential/Utility copy of a dual-state and DELETED the user's custom
    -- placement -- the 12.1 native-racial "reset to Essential/Utility" report
    -- (Blizzard's CDM now tracks racials, so a materialized default-bar copy
    -- can coexist with the user's). A custom-bar copy is always an explicit
    -- act; a default-bar copy can be a materialized spillover.
    local keeperList
    if activePresent then
        for li, list in ipairs(lists) do
            local bk = listBarKeys[li]
            if bk ~= "cooldowns" and bk ~= "utility" then
                for _, sid in ipairs(list) do
                    if sid == active then keeperList = list; break end
                end
            end
            if keeperList then break end
        end
    end

    -- Single pass across every bar: keep exactly one racial slot total.
    local kept = false
    for _, list in ipairs(lists) do
        for i = #list, 1, -1 do
            local sid = list[i]
            if sid and sid > 0 and ALL_RACIAL_SPELLS[sid] then
                if sid == active and activePresent and not kept
                   and (not keeperList or list == keeperList) then
                    -- Keep the current character's own racial where it sits
                    -- (the custom-bar copy when one exists, see keeperList).
                    kept = true
                elseif not activePresent and not kept then
                    -- No active racial anywhere: promote this foreign one.
                    list[i] = active
                    kept = true
                    ns._spellOrderDirty = true
                else
                    -- Any further racial (foreign or duplicate) is removed.
                    table.remove(list, i)
                    ns._spellOrderDirty = true
                end
            end
        end
    end
end

function ns.FullCDMRebuild(reason)
    _rebuildGen = _rebuildGen + 1
    ns._spellOrderDirty = true  -- force spell order cache rebuild
    -- Full-wipe reasons: clear per-frame caches and run a direct reanchor.
    -- Used for talent change and any path where spell IDs behind
    -- cooldownIDs may have changed (so cached resolvedSid is stale).
    local isFullWipe = (reason == "talent_reconcile")

    -- 1. Wipe all caches
    if ns.MarkCDMSpellCacheDirty then ns.MarkCDMSpellCacheDirty() end
    if ns.InvalidateTBBFrameCache then ns.InvalidateTBBFrameCache() end

    -- 2. Clear old preset frames (trinkets, racials, custom spells)
    if ns._presetFrames then
        for _, f in pairs(ns._presetFrames) do
            f:Hide()
            f:ClearAllPoints()
        end
        -- Deliberately NOT wiped: this map is the identity/REUSE registry the
        -- create-only frame sites key by. Wiping it orphaned every preset frame OBJECT
        -- (WoW frames are unreclaimable) and rebuilt the whole population on the next
        -- inject -- a frame-object leak on EVERY talent/spec/profile rebuild. Stale
        -- keys are harmless: the drain iterates the shown-set (_pcActive in CdmHooks),
        -- not this map, and re-injected keys REUSE their frame with a full re-arm on
        -- the Show edge -- the same reuse path every reanchor already runs.
    end

    -- Default bars need no assignedSpells pre-population: the route map's
    -- diversion-set model routes everything in the viewer category to the
    -- default bar by spillover, so empty assignedSpells just means "show
    -- whatever Blizzard's viewer has" -- exactly the desired behavior.

    -- 2b. Normalize racial slots to this character's race BEFORE the route
    -- map and bar build read assignedSpells.
    if ns.NormalizeRacialAssignments then ns.NormalizeRacialAssignments() end

    -- 3. Rebuild route maps (must happen before BuildAllCDMBars)
    if ns.RebuildSpellRouteMap then ns.RebuildSpellRouteMap() end

    -- 4. Rebuild all bar frames
    BuildAllCDMBars()

    -- 5. Rebuild tracked buff bars
    if ns.BuildTrackedBuffBars then ns.BuildTrackedBuffBars() end

    -- 6. Full-wipe path: wipe per-frame caches + icon arrays + anchor
    -- state, then reanchor directly. Used by talent_reconcile when spell
    -- IDs behind cooldownIDs may have changed.
    --
    -- Non-full-wipe reasons don't need an explicit reanchor here: the
    -- BuildAllCDMBars call above already queued a reanchor when hooks
    -- are active. The throttled queue dedupes naturally.
    if isFullWipe then
        -- Wipe all icon arrays
        for bk, icons in pairs(cdmBarIcons) do
            for i = 1, #icons do icons[i] = nil end
        end
        -- Clear change detection so layout runs fresh
        for bk, frame in pairs(cdmBarFrames) do
            if frame then
                frame._prevIconRefs = nil
                frame._prevVisibleCount = nil
            end
        end
        -- Clear all stale anchors so SetPoint hook doesn't fight
        if ns._hookFrameData then
            for _, efd in pairs(ns._hookFrameData) do
                efd._cdmAnchor = nil
            end
        end
        -- Clear all FC caches so ResolveFrameSpellID re-reads from API.
        -- Spells behind cooldownIDs change on spec swap; stale caches
        -- would return the old spec's spell IDs.
        for _, vname in ipairs(_cdmViewerNames) do
            local vf = _G[vname]
            if vf and vf.itemFramePool and vf.itemFramePool.EnumerateActive then
                for ch in vf.itemFramePool:EnumerateActive() do
                    local chfc = _ecmeFC[ch]
                    if chfc then
                        chfc.resolvedSid = nil
                        chfc.baseSpellID = nil
                        chfc.overrideSid = nil
                        chfc.cachedCdID = nil
                        chfc.isChargeSpell = nil
                        chfc.maxCharges = nil
                        chfc.sortOrder = nil
                        -- NOT chfc.barKey: CollectAndReanchor reads it as
                        -- "we have claimed this frame before" and refuses to
                        -- park it while identification is transiently failing.
                        -- Clearing it here would hand the next pass a frame it
                        -- cannot identify AND cannot vouch for.
                    end
                end
            end
        end
        -- A memo wipe is the START of a fresh transient-failure window, so
        -- hand the reanchor below a full retry budget instead of whatever an
        -- earlier transition left behind. Matters for cooldowns that are new
        -- to the spec being swapped TO: those have no barKey to vouch for
        -- them, so the budget is all they have.
        ns._cdmUnresolvedRetries = 0
        -- Cancel the reanchor BuildAllCDMBars queued -- we run our own direct one
        -- immediately below. Without this, the queued reanchor would fire ~200ms later
        -- and run the entire reanchor pipeline a second time.
        if ns.ClearQueuedReanchor then ns.ClearQueuedReanchor() end
        -- Direct reanchor for the freshly-wiped state
        if ns.CollectAndReanchor then ns.CollectAndReanchor() end
    end

    -- 7. Glows
    if ns.RequestBarGlowUpdate then ns.RequestBarGlowUpdate() end
    -- Re-evaluate CD ready glow state now that all frames are fully decorated.
    -- Decoration paths may have started glows during the loading-screen settle
    -- window (login/reload); this queued pass corrects them once the API is
    -- trustworthy again. No-ops instantly when no icon uses a ready-glow effect.
    if ns.QueueCDGlowResourceCheck then ns.QueueCDGlowResourceCheck() end
end

function ns.GetRebuildGen()
    return _rebuildGen
end

-- Interactive Preview Helpers loaded from EllesmereUICdmSpellPicker.lua

-------------------------------------------------------------------------------
--  CDM Bar: First Login Capture
-------------------------------------------------------------------------------
local function CDMFirstLoginCapture()
    local p = ECME.db.profile
    local captured = CaptureCDMPositions()

    for _, barData in ipairs(p.cdmBars.bars) do
        local cap = captured[barData.key]
        if cap then
            -- Icon size: visual size from child icon (base width * child scale).
            if cap.iconSize then
                barData.iconSize = cap.iconSize
            end
            -- Spacing (icon padding from Edit Mode setting)
            if cap.spacing then
                barData.spacing = cap.spacing
            end
            -- Rows (counted from distinct Y positions of visible icons)
            if cap.numRows then
                barData.numRows = cap.numRows
            end
            if cap.isHorizontal ~= nil then
                if not cap.isHorizontal then barData.growDirection = "DOWN" end
                barData.verticalOrientation = not cap.isHorizontal
            end
            -- Position: no scale division needed (scale is always 1)
            if cap.point then
                p.cdmBarPositions[barData.key] = {
                    point = cap.point, relPoint = cap.relPoint,
                    x = cap.x, y = cap.y,
                }
            end
        end
    end

    ECME.db.sv._capturedOnce_CDM = true
end

--- Re-seed assignedSpells from live cdmBarIcons. Appends any positive spell IDs present on the
--- live bars but missing from assignedSpells. Called after CollectAndReanchor so the preview stays in sync with what the player actually sees on their CDM bars.
function ns.ReseedAssignedSpellsFromLiveIcons(cdUtilOnly)
    local p = ECME and ECME.db and ECME.db.profile
    if not p or not p.cdmBars then return end

    -- Both-state guards (mirror EnsureAssignedSpells). This appends live-icon spells back into
    -- assignedSpells; without these it could re-materialize a spell that is currently HIDDEN
    -- (ghosted) or already OWNED by another bar, recreating a both-state. The sole caller
    -- (RepopulateFromBlizzard) pre-wipes the ghost and Blizzard-sourced assignments, so these are normally no-ops -- but they keep Reseed safe regardless of caller or ordering.
    local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
    local sk = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
    local aprof = sp and sk and sp[sk]
    -- Skip entirely while an imported layout is pending its first-load ghosting: its tracked
    -- spells spill onto default bars until the migration ghosts them, and materializing those spills would defeat the import-authoritative hide.
    if aprof and aprof._importGhostMode then return end

    -- Unlike every other assignedSpells mutation site (the picker's add/remove/move calls,
    -- BuildAllCDMBars), this one never marked the cached render-order map (spellOrder,
    -- CdmHooks.lua ~7000) dirty -- so a spell this pass just materialized had no key in the
    -- STALE cache, fell through every OrderKeyFor match probe, and rendered via the raw
    -- layoutIndex spillover fallback (the same imprecise path #1211/#1420 already fixed once)
    -- instead of the position it was just given. Field-confirmed: Cobra Shot's assignedSpells
    -- entry was correct and it still rendered first. Set once, only when something actually inserted.
    local didInsert = false

    -- Spell -> owning bar (variant-aware), built once. A live icon whose stored owner is a DIFFERENT bar is a transient spillover we must not materialize.
    local ownerOf
    -- One-racial-total invariant (see NormalizeRacialAssignments): while ANY
    -- racial-family entry is placed on any bar, the racial slot is spoken for.
    -- Materializing a second racial slot here (a live racial icon transiting a
    -- default bar during the login route-not-ready window) creates the
    -- dual-state the normalize dedupe then resolves -- which historically
    -- deleted the user's custom placement.
    local anyRacialOwned = false
    if aprof and aprof.barSpells and ns.StoreVariantValue then
        for k, bsd in pairs(aprof.barSpells) do
            if k ~= GHOST_CD_BAR_KEY
               and type(bsd) == "table" and type(bsd.assignedSpells) == "table" then
                for _, csid in ipairs(bsd.assignedSpells) do
                    if type(csid) == "number" and csid > 0 then
                        ownerOf = ownerOf or {}
                        ns.StoreVariantValue(ownerOf, csid, k, false)
                        if ALL_RACIAL_SPELLS[csid] then anyRacialOwned = true end
                    end
                end
            end
        end
    end

    local ghostSd = ns.GetBarSpellData and ns.GetBarSpellData(GHOST_CD_BAR_KEY)
    local ghostList = ghostSd and ghostSd.assignedSpells
    local FindVar = ns.FindVariantIndexInList

    -- Cd-claimed collided-buff slots (cd-claim markers in assignedSpells, see ns.CdClaimMarker)
    -- are tracked by COOLDOWN ID, not by the shared spellID. Materializing such an icon's shared
    -- spellID here would, at the next route rebuild, drag the UNCLAIMED twin onto the claiming bar
    -- too -- defeating the claim's one-slot-only contract. Built once; stays nil (guard inert, zero cost) unless a collided claim exists anywhere.
    local claimedCd
    if aprof and aprof.barSpells then
        for _, bsd in pairs(aprof.barSpells) do
            local bsdClaims = type(bsd) == "table" and ns.CollectCdClaimSet(bsd)
            if bsdClaims then
                for cdID in pairs(bsdClaims) do
                    claimedCd = claimedCd or {}
                    claimedCd[cdID] = true
                end
            end
        end
    end

    for _, barData in ipairs(p.cdmBars.bars) do
        -- cdUtilOnly (the automatic reseed path): buff-family bars are picker-authoritative --
        -- materializing live buff icons would reintroduce the secret-ID drift duplicate-slot bug
        -- the options materializer's skip exists to prevent. The manual Repopulate flow passes nothing and keeps its full sweep.
        if not barData.isGhostBar
           and barData.key ~= "buffs"
           and (barData.barType == "cooldowns" or barData.barType == "utility"
                or (barData.barType == "buffs" and not cdUtilOnly)
                or MAIN_BAR_KEYS[barData.key]) then
            local sd = ns.GetBarSpellData(barData.key)
            local icons = ns.cdmBarIcons and ns.cdmBarIcons[barData.key]
            if sd and icons then
                if not sd.assignedSpells then sd.assignedSpells = {} end
                -- Insert each missing spell right after its left neighbour in the live icon order
                -- (already Blizzard-layout order from CollectAndReanchor) instead of appending, so
                -- the seeded list matches what the player sees and a re-talented cooldown returns
                -- to its slot, not the tail. Presence is VARIANT-AWARE and the cursor is a
                -- POSITION, not an id: an exact-match set misses a stored entry when the live icon
                -- reports a different variant form (fc.spellID can be the talent override, e.g.
                -- Mongoose Bite 259387, while the slot holds the base Raptor Strike 186270 the
                -- options normalize pass wrote). Each reload then re-inserts the live form at
                -- Blizzard's position and the next normalize dedupes in its favor -- permanently snapping the user's saved order back to Blizzard order. A by-value cursor lookup fails the same way and dumps inserts at slot 1.
                local insertPos = nil
                for _, icon in ipairs(icons) do
                    local fc = ns._ecmeFC and ns._ecmeFC[icon]
                    local sid = fc and fc.spellID
                    -- Skip hosted-buff frames and their placeholders: their bar membership is the
                    -- hosted MARKER entry, and their positive spellID would materialize the same
                    -- spell's COOLDOWN form. But DO advance the cursor over their marker: on a mixed
                    -- bar a spell re-inserted after a buff must land after the buff's marker, not squeezed back next to the previous CD spell.
                    local fdRS = ns._hookFrameData and ns._hookFrameData[icon]
                    if (fc and fc.isHostedBuff) or icon._isPlaceholderFrame
                       or (fdRS and fdRS._isBuffViewerFrame) then
                        local hSid = fc and fc.spellID
                        if type(hSid) == "number" and hSid > 0
                           and ns.HostedBuffMarkerToSpell
                           and not (fc and fc._overflowLayoutBar) then
                            for i = 1, #sd.assignedSpells do
                                local dec = ns.HostedBuffMarkerToSpell(sd.assignedSpells[i])
                                if dec and (dec == hSid
                                    or (ns.IsVariantOf and ns.IsVariantOf(dec, hSid))) then
                                    -- Forward-only: never drag the cursor backward.
                                    if not insertPos or i > insertPos then insertPos = i end
                                    break
                                end
                            end
                        end
                        sid = nil
                    end
                    -- Skip overflow-diverted icons: they render on this bar only for the session but belong to their source bar's assignedSpells (mirrors the EnsureAssignedSpells skip).
                    if sid and fc and fc._overflowLayoutBar then
                        sid = nil
                    end
                    -- Skip cd-claimed collided-buff icons: their membership is the cooldownID claim, never a spellID slot (mirrors the hosted-buff membership rule above).
                    if sid and claimedCd and icon.cooldownID
                       and claimedCd[icon.cooldownID] then
                        sid = nil
                    end
                    if type(sid) == "number" and sid ~= 0 then
                        -- FindVar handles negatives by exact scan internally, and variant matching is a strict superset of exact equality for stored positives -- no exact fallback needed.
                        local at = FindVar and FindVar(sd.assignedSpells, sid)
                        if at then
                            -- Already has a slot (any variant form, or a custom trinket/item marker): advance the cursor so the next NEW spell lands after it, matching on-screen order.
                            insertPos = at
                        elseif sid > 0 then
                            -- Never materialize a hidden (ghosted) spell, or a spell a DIFFERENT bar already owns (variant-aware).
                            local owner = ownerOf and ns.ResolveVariantValue
                                          and ns.ResolveVariantValue(ownerOf, sid)
                            local ghosted = ghostList and FindVar and FindVar(ghostList, sid)
                            -- Racial-family guard: never mint a second racial slot
                            -- while one is placed anywhere (anyRacialOwned above).
                            local racialBlocked = anyRacialOwned and ALL_RACIAL_SPELLS[sid]
                            if not ghosted and not racialBlocked and not (owner and owner ~= barData.key) then
                                -- Store the BASE form, matching what the options normalize pass writes -- otherwise this pass persists the talent-override form and the two writers diverge (exports could ship either).
                                -- Only trust that substitution when Blizzard's OWN cooldownInfo already
                                -- recorded a base/display split for THIS icon (fc.baseSpellID ~= fc.resolvedSid,
                                -- e.g. a Wither slot whose base is Immolate). GetBaseSpell can also tie
                                -- together spells with no override relationship at all -- field-confirmed
                                -- for Cobra Shot -> Arcane Shot, and #842 saw the same API do it to SV Kill
                                -- Command -- and substituting on that spurious tie stores an id the live
                                -- spell never actually shares a slot with, orphaning it as a permanent spillover.
                                local nsid = sid
                                if C_Spell and C_Spell.GetBaseSpell
                                   and fc.baseSpellID and fc.resolvedSid
                                   and fc.baseSpellID ~= fc.resolvedSid then
                                    local b = C_Spell.GetBaseSpell(sid)
                                    if b and b > 0 then nsid = b end
                                end
                                local pos = insertPos and (insertPos + 1) or 1
                                table.insert(sd.assignedSpells, pos, nsid)
                                insertPos = pos
                                didInsert = true
                            end
                        end
                    end
                end
            end
        end
    end
    if didInsert then ns._spellOrderDirty = true end
end

-- Parent-facing bridge for the automatic/export-time reconcile: cd and utility bars only
-- (buff-family excluded -- picker-authoritative). The export path nil-checks this, so a disabled CDM child is a clean no-op.
EllesmereUI.CDMReconcileActiveSpecSpells = function()
    ns.ReseedAssignedSpellsFromLiveIcons(true)
    -- Export serializes immediately after this bridge: erase any item rows
    -- the reseed just mirrored so exports can never ship them.
    if ns.PruneEquipmentBuffRows then ns.PruneEquipmentBuffRows() end
end

-- Shared PLAYER_REGEN_ENABLED waiter for the automatic keep/drop pass below.
-- Deliberately its OWN frame, not the module's big shared event handler
-- further down this file -- that frame's registration set is static and
-- must not churn. Registers the event ONLY while a pass is pending and
-- unregisters itself the instant it fires, so an idle session where no pass
-- is ever deferred carries zero event traffic from this path.
local _cdmRegenWaiter
local function ArmCDMDropRegenWaiter()
    ns._cdmDropPending = true
    if not _cdmRegenWaiter then
        _cdmRegenWaiter = CreateFrame("Frame")
        _cdmRegenWaiter:Hide()
        _cdmRegenWaiter:SetScript("OnEvent", function(self)
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            ns._cdmDropPending = false
            if ns.RequestCDMDropPass then ns.RequestCDMDropPass("regen") end
        end)
    end
    if not _cdmRegenWaiter:IsEventRegistered("PLAYER_REGEN_ENABLED") then
        _cdmRegenWaiter:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
end

--- ns.ReconcileAssignedSpellDrops(barKey): single resident implementation of
--- the 3-way keep/drop pass (formerly inline in the options panel's
--- EnsureAssignedSpells). Interactive options edits call this directly;
--- the automatic triggers (once-per-spec reseed, settings close) arrive
--- through ns.RequestCDMDropPass below. Every guard fails OPEN to keep-all:
--- no profile, no migration, mid-import, data not yet loaded, provider
--- unreachable, or combat all return the bar's spell data unchanged rather
--- than risk dropping a legitimately-owned entry.
function ns.ReconcileAssignedSpellDrops(barKey)
    local sd = ns.GetBarSpellData(barKey)
    if not sd then return sd end

    local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
    local sk = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
    local aprof = sp and sk and sp[sk]
    if not aprof or not aprof._barFilterModelV6 then return sd end
    -- aprof._importGhostMode is the options panel's "importPending" (same
    -- field, EUI_CooldownManager_Options.lua ~6367-6373): a mid-import pass
    -- would mark spilled tracked spells "assigned" and permanently defeat
    -- import-authoritative ghosting, so the whole pass no-ops instead.
    if aprof._importGhostMode then return sd end
    if not ns._cdmDataLoaded then return sd end

    -- GHOST BAR EXEMPTION (field 2026-08-13, hunter Scare Beast classified
    -- keep=false in a reconcile dry-run): the ghost store holds spells the user DELIBERATELY removed --
    -- not-shown by definition, often uncatalogued -- and dropping a ghost entry
    -- erases the removal decision, so the spell re-materializes onto the visible
    -- bar. The classification ladder must never see this pseudo-bar.
    if barKey == GHOST_CD_BAR_KEY then return sd end
    local bd = barDataByKey[barKey]
    if ns.IsBarBuffFamily and ns.IsBarBuffFamily(bd or barKey) then
        -- Buff-family drop needs the persisted variant-alias ledger so a
        -- dual-tracked spell's currently-absent half never sinks its present
        -- half; ns.ReconcileBuffFamilyDrops (EllesmereUICooldownManager.lua)
        -- is the single implementation, gated on that ledger. Fails open to
        -- the unmodified sd if the ledger-gated pass isn't available.
        return (ns.ReconcileBuffFamilyDrops and ns.ReconcileBuffFamilyDrops(barKey)) or sd
    end
    local bt = bd and bd.barType
    if not (bt == "cooldowns" or bt == "utility") then return sd end

    if InCombatLockdown() then
        ArmCDMDropRegenWaiter()
        return sd
    end

    if not sd.assignedSpells or #sd.assignedSpells == 0 then return sd end
    if not ns.EnumerateCDMViewerSpells then return sd end

    local NormalizeToBase = ns.NormalizeToBase
    local ResolveToLive   = ns.ResolveToLive

    local displayed
    for _, e in ipairs(ns.EnumerateCDMViewerSpells(false)) do
        local sid = e.sid
        if type(sid) == "number" and sid > 0 then
            displayed = displayed or {}
            displayed[sid] = true
            displayed[NormalizeToBase(sid)] = true
            local ov = ResolveToLive(sid)
            if ov then displayed[ov] = true end
        end
    end
    if not (displayed and next(displayed)) then return sd end

    -- Blizzard's tracked-cooldown catalog (talent-independent, arrangement-
    -- aware, and category-0/1/5/7-aware once the picker's category-set
    -- constants land) is the source untalented spells were materialized
    -- from; lets the keep test below also drop an untalented spell the user
    -- removed from tracking, invisible to `displayed` since untalented
    -- spells never get a live frame. nil provider -> untalented entries kept.
    local catalogSet
    if ns.EnumerateCDMSettingsCatalog then
        local cat = ns.EnumerateCDMSettingsCatalog(ns.CDM_ICON_CD_CATS)
        if cat then
            catalogSet = {}
            local gci = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
            local function AddCatalogVariant(v)
                if type(v) == "number"
                   and not (issecretvalue and issecretvalue(v))
                   and v > 0 then
                    catalogSet[v] = true
                end
            end
            -- Per-category live-set lookup for the hidden/removed check below
            -- (ns.CDMEntryHiddenOrRemoved), built once per category the first
            -- time it's seen this pass and reused for every entry in it --
            -- never refetched per id. Cats 0/1 hidden entries already read as
            -- HiddenActive/HiddenPassive and never reach this loop (excluded
            -- by EnumerateCDMSettingsCatalog's own wantSet test); self-mapping
            -- cats 5/7 keep their category when hidden/removed, so THEY need
            -- this extra check to stop a removed entry holding rank forever.
            local liveSetByCat = {}
            for _, ce in ipairs(cat) do
                local info = gci and ce.cdID and gci(ce.cdID)
                local skip = false
                if ns.CDMEntryHiddenOrRemoved then
                    local lsl = liveSetByCat[ce.category]
                    if lsl == nil and ns.CDMBuildLiveCategorySetLookup then
                        lsl = ns.CDMBuildLiveCategorySetLookup(ce.category) or false
                        liveSetByCat[ce.category] = lsl
                    end
                    local verdict = ns.CDMEntryHiddenOrRemoved(ce.cdID, nil, info, lsl)
                    if verdict == "hidden" or verdict == "removed" then skip = true end
                end
                if not skip then
                    local s = ce.sid
                    if type(s) == "number" and s > 0 then
                        catalogSet[s] = true
                        catalogSet[NormalizeToBase(s)] = true
                        local ov = ResolveToLive(s)
                        if ov then catalogSet[ov] = true end
                    end
                    -- Also index every id the entry itself links (spellID/
                    -- overrideSpellID/linkedSpellIDs): a stored BASE id only
                    -- matches the catalog through the entry's own linked set
                    -- once the override talent is dropped and the spellbook
                    -- link goes with it.
                    if info then
                        AddCatalogVariant(info.spellID)
                        AddCatalogVariant(info.overrideSpellID)
                        if info.linkedSpellIDs then
                            for _, lid in ipairs(info.linkedSpellIDs) do
                                AddCatalogVariant(lid)
                            end
                        end
                    end
                end
            end
        end
    end

    local custom  = sd.customSpellIDs
    local racials = _myRacialsSet
    local cdurs   = sd.customSpellDurations
    local sdurs   = sd.spellDurations
    local groups  = sd.customSpellGroups
    local hosted  = sd.hostedBuffSpellIDs
    -- Marker-present set: a hosted buff's PLAIN entry (its cooldown form)
    -- must not borrow the hosted exemption below once its own MARKER entry
    -- exists -- untracking the cooldown should drop it like any other
    -- cooldown while the hosted buff stays.
    local hostedMarkerFor
    if hosted then
        for _, mid in ipairs(sd.assignedSpells) do
            local mSid = ns.HostedBuffMarkerToSpell and ns.HostedBuffMarkerToSpell(mid)
            if mSid then
                hostedMarkerFor = hostedMarkerFor or {}
                hostedMarkerFor[mSid] = true
            end
        end
    end

    local writeIdx = 1
    for readIdx = 1, #sd.assignedSpells do
        local id = sd.assignedSpells[readIdx]
        local keep = true
        -- A HOSTED buff is a real buff (never in the Essential/Utility
        -- viewer), so the "owned but not displayed -> drop" test below
        -- would wrongly delete it; always keep, like a custom spell ID/racial.
        if type(id) == "number" and id > 0
           and not (custom and custom[id])
           and not (racials and racials[id])
           and not (cdurs and cdurs[id])
           and not (sdurs and sdurs[id])
           and not (groups and groups[id])
           and not (hosted and hosted[id]
                    and not (hostedMarkerFor and hostedMarkerFor[id])) then
            -- Plain Blizzard cooldown. Keep if still displayed OR if the
            -- player no longer HAS the spell (talented out): a talented-out
            -- cooldown must hold its rank so it returns to the SAME slot
            -- when re-talented. Only a spell still OWNED but removed from
            -- Blizzard's CDM tracking (gone from the catalog too) is
            -- genuinely user-cleared -> drop.
            local shown = displayed[id] or displayed[NormalizeToBase(id)]
                          or displayed[ResolveToLive(id)]
            -- IsPlayerSpell is guarded (nil in some contexts): if
            -- unavailable, `have` is falsy so the spell is treated as
            -- untalented (kept unless the catalog says otherwise).
            local have = IsPlayerSpell and (IsPlayerSpell(id)
                         or IsPlayerSpell(NormalizeToBase(id))
                         or IsPlayerSpell(ResolveToLive(id)))
            if shown then
                keep = true
            elseif catalogSet
                   and (catalogSet[id] or catalogSet[NormalizeToBase(id)]
                        or catalogSet[ResolveToLive(id)]) then
                -- Still tracked in Blizzard's catalog, just not displayed:
                -- untalented, conditionally pooled, or a BASE id whose
                -- tracked cooldown is a talent override the player dropped.
                -- Hold rank.
                keep = true
            elseif have then
                -- Owned but no longer tracked: the user cleared it from
                -- Blizzard's CDM tracking -> drop.
                keep = false
            elseif catalogSet then
                -- Untalented: it only reached the preview by being
                -- materialized from the settings catalog, so it must also
                -- LEAVE when removed from tracking -> drop.
                keep = false
            else
                -- Untalented with no catalog signal (provider down): hold
                -- rank as the safe fallback so a transient gap never wipes
                -- an untalented assignment.
                keep = true
            end
        end
        if keep then
            sd.assignedSpells[writeIdx] = id
            writeIdx = writeIdx + 1
        end
    end
    for i = writeIdx, #sd.assignedSpells do sd.assignedSpells[i] = nil end

    -- Normalize the hosted-buff representation: a hosted buff owns a MARKER
    -- entry; a plain entry of the same id means the COOLDOWN form. Resolve
    -- each flagged id here, where displayed/catalog sets can tell the forms apart.
    if sd.hostedBuffSpellIDs and ns.HostedBuffMarker then
        local list = sd.assignedSpells
        local ghostSd = ns.GetBarSpellData and ns.GetBarSpellData(GHOST_CD_BAR_KEY)
        local ghostList = ghostSd and ghostSd.assignedSpells
        local FindVar = ns.FindVariantIndexInList
        -- Plain entries claimed by OTHER visible bars (variant-aware): if
        -- the cooldown form lives elsewhere, a plain entry here is a
        -- resurrected artifact of the old shared-id model.
        local claimed
        do
            local bsAll = aprof.barSpells
            if bsAll and ns.StoreVariantValue then
                for k, bsd in pairs(bsAll) do
                    if k ~= barKey and k ~= GHOST_CD_BAR_KEY
                       and type(bsd) == "table" and type(bsd.assignedSpells) == "table" then
                        for _, sid in ipairs(bsd.assignedSpells) do
                            if type(sid) == "number" and sid > 0 then
                                claimed = claimed or {}
                                ns.StoreVariantValue(claimed, sid, true, false)
                            end
                        end
                    end
                end
            end
        end
        for hsid in pairs(sd.hostedBuffSpellIDs) do
            if type(hsid) == "number" and hsid > 0 then
                local marker = ns.HostedBuffMarker(hsid)
                local markerIdx, plainIdx
                for i = 1, #list do
                    local v = list[i]
                    if v == marker then markerIdx = i
                    elseif v == hsid then plainIdx = i end
                end
                if plainIdx then
                    local isCdForm = (displayed[hsid]
                        or displayed[NormalizeToBase(hsid)]
                        or displayed[ResolveToLive(hsid)]
                        or (catalogSet and (catalogSet[hsid]
                            or catalogSet[NormalizeToBase(hsid)]
                            or catalogSet[ResolveToLive(hsid)]))) and true or false
                    if isCdForm and ghostList and FindVar and FindVar(ghostList, hsid) then
                        isCdForm = false
                    end
                    if isCdForm and claimed and ns.ResolveVariantValue
                       and ns.ResolveVariantValue(claimed, hsid) then
                        isCdForm = false
                    end
                    if markerIdx then
                        if not isCdForm then
                            table.remove(list, plainIdx)
                            ns._spellOrderDirty = true
                        end
                    elseif isCdForm then
                        table.insert(list, plainIdx + 1, marker)
                        ns._spellOrderDirty = true
                    else
                        list[plainIdx] = marker
                        ns._spellOrderDirty = true
                    end
                end
            end
        end
    end

    return sd
end

--- ns.RequestCDMDropPass(reason): fan-out entry point for the AUTOMATIC
--- triggers (once-per-spec reseed, settings close). Bails immediately while
--- the module/spec isn't ready to reconcile (zero cost while disabled);
--- coalesces concurrent requests behind the single pending flag; defers out
--- of combat via the shared regen waiter above. Interactive options edits
--- bypass this and call ns.ReconcileAssignedSpellDrops directly.
function ns.RequestCDMDropPass(reason)
    local p = ECME and ECME.db and ECME.db.profile
    if not p or not p.cdmBars then return end

    local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
    local sk = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
    local aprof = sp and sk and sp[sk]
    if not aprof or not aprof._barFilterModelV6 then return end

    if ns._cdmDropPending then return end -- already scheduled, coalesce

    if InCombatLockdown() then
        ArmCDMDropRegenWaiter()
        return
    end

    -- Every reconcilable bar, not just the two default keys: custom CD/utility
    -- bars carry the same barTypes, and buff-family bars route internally to the
    -- ledger-gated pass (vouched-only, safe to automate). The ghost store is
    -- exempted inside the pass; skipped here too to spare the call.
    for barKey, bd in pairs(barDataByKey) do
        if barKey ~= GHOST_CD_BAR_KEY then
            local bt = bd and bd.barType
            if bt == "cooldowns" or bt == "utility"
               or (ns.IsBarBuffFamily and ns.IsBarBuffFamily(bd or barKey)) then
                ns.ReconcileAssignedSpellDrops(barKey)
            end
        end
    end
    -- Items are preset-lane-only: whatever intake lane just ran (reseed,
    -- spillover, materializer) may have mirrored a native equipment entry
    -- into a store -- the same pass class erases it, so item rows can never
    -- persist. Tracking an item in Blizzard's CDM becomes a store no-op.
    if ns.PruneEquipmentBuffRows then ns.PruneEquipmentBuffRows() end
end

-------------------------------------------------------------------------------
--  Midnight hidden-channel reader (categories 0-8)
--  Blizzard folds both default-hide and user-hide into `category` for cats
--  0-3 (HiddenActive/HiddenPassive), but cats 5-8 self-map onto their OWN
--  category when hidden -- there is no separate isHidden field for them, so a
--  plain category read can never reveal a 5-8 hide; membership in the live
--  category set and isKnown carry that signal instead. GroupBuff (cat 4) is a
--  third, separate system: hidden spellIDs live in a flat array on the active
--  layout. Every provider read here is pcall-degraded: a down/errored read
--  always classifies as visible, so the drop pass this feeds never over-drops
--  on a bad read.
-------------------------------------------------------------------------------

-- Reject secret-tainted/non-positive numbers before they key a table or get compared.
local function _IsUsableSID(id)
    if type(id) ~= "number" then return false end
    if issecretvalue and issecretvalue(id) then return false end
    return id > 0 and id == math.floor(id)
end

-- Reads the ALREADY-BUILT display table, never the provider getters: those run
-- CheckBuildDisplayData, which rebuilds Blizzard's shared tables (and writes the
-- active layout) on OUR stack whenever the provider is dirty -- the HUD viewer
-- drops its OnDataChanged rebuild while hidden, so a post-match read used to
-- taint the viewer until reload. A dirty provider returns nil (not the previous
-- build): callers treat nil as "not ready" and fall back to keep-all/live-pool.
function ns.CDMGetProviderDisplayData(provider)
    if type(provider) ~= "table" or type(provider.GetDisplayData) ~= "function" then
        return nil, nil
    end
    if type(provider.IsDirty) == "function" then
        local okD, dirty = pcall(provider.IsDirty, provider)
        if not okD or dirty then return nil, nil end
    end
    local ok, displayData = pcall(provider.GetDisplayData, provider)
    if not ok or type(displayData) ~= "table" then return nil, nil end
    local ordered = displayData.orderedCooldownIDs
    local infoByID = displayData.cooldownInfoByID
    if type(ordered) ~= "table" or type(infoByID) ~= "table" then return nil, nil end
    return ordered, infoByID
end

-- Active BLIZZARD CDM layout id (the user's "preset"), not to be confused with
-- ns.GetActiveLayoutName (EUI's own account-wide spell-layout system). Used to
-- scope the automatic-reseed session gate by layout as well as spec: a spell
-- only tracked on a preset the user switches to LATER in the session was
-- invisible at the first reseed and must still get its own materialize pass.
function ns.GetActiveCDMLayoutID()
    if not (CooldownViewerSettings and CooldownViewerSettings.GetLayoutManager) then return nil end
    local okLM, layoutManager = pcall(CooldownViewerSettings.GetLayoutManager, CooldownViewerSettings)
    if not okLM or not layoutManager or not layoutManager.GetActiveLayoutID then return nil end
    local okID, layoutID = pcall(layoutManager.GetActiveLayoutID, layoutManager)
    if not okID then return nil end
    return layoutID
end

-- GroupBuff (category 4) hidden check: getter-only on the layout manager, never
-- WriteHiddenGroupBuffsToLayout. No active layout yet (fresh install, never
-- customized) is not "nothing hidden" evidence -- treated as unreachable and kept
-- visible, same as every other fail-open path in this file.
function ns.CDMIsGroupBuffSpellHidden(spellID)
    if not _IsUsableSID(spellID) then return false end
    if not (CooldownViewerSettings and CooldownViewerSettings.GetLayoutManager) then return false end
    local okLM, layoutManager = pcall(CooldownViewerSettings.GetLayoutManager, CooldownViewerSettings)
    if not okLM or not layoutManager then return false end
    local accessOnly = (Enum and Enum.CDMLayoutMode and Enum.CDMLayoutMode.AccessOnly) or false
    local okLayout, layout = pcall(layoutManager.GetActiveLayout, layoutManager, accessOnly)
    if not okLayout or not layout then return false end
    local okList, hiddenList = pcall(CooldownManagerLayout_GetHiddenGroupBuffs, layout)
    if not okList or type(hiddenList) ~= "table" then return false end
    for i = 1, #hiddenList do
        if hiddenList[i] == spellID then return true end
    end
    return false
end

-- Per-category "still a live member of this category" lookup for the cats-5-8 removal
-- signal below. allowUnlearned=true so this is the category's full membership universe,
-- not narrowed to currently-known spells (isKnown is a separate, independent signal in
-- CDMEntryHiddenOrRemoved). Build ONCE per category per pass and reuse for every id in
-- it -- never per id (mirrors Blizzard's own tInvert-on-GetCooldownViewerCategorySet
-- idiom). Returns nil (never an empty table) on failure so a caller checking
-- lookup[id] can tell "couldn't build" from "confirmed empty" -- collapsing the two
-- would make a dead provider read as "everything in this category is gone".
function ns.CDMBuildLiveCategorySetLookup(category)
    if type(category) ~= "number" then return nil end
    if not (C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet) then return nil end
    local ok, ids = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, category, true)
    if not ok or type(ids) ~= "table" then return nil end
    local lookup = {}
    for i = 1, #ids do
        local id = ids[i]
        if _IsUsableSID(id) then lookup[id] = true end
    end
    return lookup
end

-- Classifies one cooldownID against the hidden channel. Returns "hidden", "removed", or
-- nil (visible/keep -- also the result for any missing latch/provider/category match).
-- mergedInfo/rawInfo may be pre-fetched by the caller to batch a scan; liveSetLookup is
-- this id's category lookup from CDMBuildLiveCategorySetLookup above.
function ns.CDMEntryHiddenOrRemoved(cdID, mergedInfo, rawInfo, liveSetLookup)
    if not _IsUsableSID(cdID) then return nil end
    if not ns._cdmDataLoaded then return nil end -- pre-load reads see only static defaults

    local evc = Enum and Enum.CooldownViewerCategory
    local hiddenActive = evc and evc.HiddenActive or -1
    local hiddenPassive = evc and evc.HiddenPassive or -2

    if mergedInfo == nil then
        local provider = CooldownViewerSettings and CooldownViewerSettings.GetDataProvider
                          and CooldownViewerSettings:GetDataProvider()
        if provider then
            local _, infoByID = ns.CDMGetProviderDisplayData(provider)
            if infoByID then mergedInfo = infoByID[cdID] end
        end
    end

    -- Cats 0-3: default-hide and user-hide both fold into `category` -- complete on their
    -- own. A 5-8 entry that took the rare two-hop drag into Hidden also lands here.
    if mergedInfo and (mergedInfo.category == hiddenActive or mergedInfo.category == hiddenPassive) then
        return "hidden"
    end

    local cat = mergedInfo and mergedInfo.category
    local groupBuff = evc and evc.GroupBuff or 4
    local spec5 = evc and evc.SpecAgnosticEssential or 5
    local spec6 = evc and evc.SpecAgnosticTracked or 6
    local equip7 = evc and evc.EquipSlotEssential or 7
    local equip8 = evc and evc.EquipSlotTracked or 8

    -- Only cats 4-8 need the raw (unreconciled) struct below; a mergedInfo hit already
    -- resolved to 0-3 is fully answered (visible) without another provider call.
    if cat == nil or cat == groupBuff or cat == spec5 or cat == spec6 or cat == equip7 or cat == equip8 then
        if rawInfo == nil and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
            local ok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cdID)
            if ok then rawInfo = info end
        end
        if cat == nil then cat = rawInfo and rawInfo.category end
    end

    if type(cat) ~= "number" then return nil end -- nothing to classify against: keep

    if cat == groupBuff then
        local sid = (mergedInfo and mergedInfo.spellID) or (rawInfo and rawInfo.spellID)
        if ns.CDMIsGroupBuffSpellHidden(sid) then return "hidden" end
        return nil
    end

    if cat ~= spec5 and cat ~= spec6 and cat ~= equip7 and cat ~= equip8 then
        return nil -- cats 0-3 already resolved above; nothing further indicates hidden/removed
    end
    if rawInfo == nil then return nil end -- provider down: keep

    -- HideByDefault must NOT convict here. Blizzard's own provider proves the
    -- flag is a DEFAULT DISPOSITION, not live state: their CheckBuildDisplayData
    -- remaps HideByDefault entries into the Hidden pseudo-categories for cats
    -- 0-3, but for the self-mapping cats the remap is a deliberate no-op -- a
    -- user-tracked entry KEEPS the flag forever (the un-hide lives elsewhere in
    -- the layout). Convicting on it dropped every default-hidden-but-tracked
    -- SpecAgnostic entry on the first automatic pass (field 2026-08-13: shaman
    -- Gust of Wind). Until a proven per-entry user-hidden read exists for cats
    -- 5-8, the flag contributes nothing: keep. Worst case a genuinely hidden
    -- 5-8 entry lingers until manual removal -- the pre-fix status quo, and
    -- the correct failure direction.

    -- An EMPTY lookup must never judge: GetCooldownViewerCategorySet can return
    -- an empty table for a category it does not serve, indistinguishable from a
    -- real "no members" -- and treating that as removal dropped EVERY
    -- SpecAgnostic entry on the first automatic pass (field 2026-08-13: shaman
    -- Gust of Wind vanished from store/preview/picker while the live bar kept
    -- rendering via frames-as-truth). Same zero-values disease as
    -- GetPlayerAuraBySpellID: an API answering "nothing" for what it cannot
    -- see. Only a POPULATED live set may testify that this id fell out of it.
    if liveSetLookup and next(liveSetLookup) and liveSetLookup[cdID] == nil then
        return "removed" -- dropped out of the category's live set (unequipped/spec lost)
    end

    if rawInfo.isKnown == false then
        return "removed" -- cats 5-8 ONLY; 0-3 rank-holding depends on unknown-but-cataloged survival
    end

    return nil
end

-------------------------------------------------------------------------------
--  Buff-family assigned-spell reconcile
--
--  Drops a stored buff-family id only once every member of its LEARNED variant-
--  alias family (ns.GetBuffVariantAliases / ns.LearnBuffVariantAlias, populated
--  from linkedSpellIDs while each form is live) is absent from the current
--  buff-category catalog AND not displayed. UN-LEARNED ids are VOUCHED-ONLY
--  exempt: the ledger must know the id before absence may convict (never-
--  learned = keep unconditionally, the June-ban tradeoff).
--  This is what makes a dual-tracked spell (one stored id, a different id on
--  every live frame) survivable once the pairing has been observed even a
--  single time on this spec -- see the ban comment on
--  ns.SyncExtraBuffBarsWithViewer (EllesmereUICdmHooks.lua) for why a
--  presence-only prune is unsafe without it. Reuses `_IsUsableSID` from the
--  hidden-channel reader above (single file-scope copy) and the shared
--  `ArmCDMDropRegenWaiter` from ns.ReconcileAssignedSpellDrops's block
--  (single resident implementation, RS3) rather than redefining either.
-------------------------------------------------------------------------------

-- Buff-family present-set: every non-hidden, non-removed spellID/overrideSpellID/
-- linkedSpellIDs member currently catalogued under TrackedBuff/TrackedBar/GroupBuff,
-- plus SpecAgnosticTracked/EquipSlotTracked as a safety superset (membership there can
-- only widen KEEP, never enable a new DROP), plus every live displayed buff-icon
-- spellID. READ-only against the settings provider; nil (provider unhealthy, caller
-- keeps all) if the provider/category APIs are unreachable or no entry is found.
local function BuildBuffFamilyPresentSet()
    local settings = _G.CooldownViewerSettings
    if not settings or type(settings.GetDataProvider) ~= "function" then return nil end
    local okP, provider = pcall(settings.GetDataProvider, settings)
    if not okP or type(provider) ~= "table" then return nil end
    -- Read the already-built display table, never the getters that would
    -- build it (see ns.CDMGetProviderDisplayData).
    local ordered, infoByID = ns.CDMGetProviderDisplayData(provider)
    if not ordered then return nil end
    local gci = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
    if not gci then return nil end
    local evc = Enum and Enum.CooldownViewerCategory
    if not evc then return nil end

    local wantCats = {
        [evc.TrackedBuff or 2] = true, [evc.TrackedBar or 3] = true,
        [evc.GroupBuff or 4] = true, [evc.SpecAgnosticTracked or 6] = true,
        [evc.EquipSlotTracked or 8] = true,
    }

    -- Per-category live set: built once per category and reused for every id in that
    -- category, via the shared hidden-channel builder (pcall-safe, id-gated) so this
    -- present-set can never drift from the drop pass's own category reads.
    local liveSetByCat = {}
    if ns.CDMBuildLiveCategorySetLookup then
        for cat in pairs(wantCats) do
            liveSetByCat[cat] = ns.CDMBuildLiveCategorySetLookup(cat)
        end
    end

    local present, sawEntry = {}, false
    for _, cdID in ipairs(ordered) do
        local mergedInfo = _IsUsableSID(cdID) and infoByID[cdID]
        local category = type(mergedInfo) == "table" and mergedInfo.category
        if category ~= nil and wantCats[category] then
            sawEntry = true
            local rawInfo = gci(cdID)
            -- "hidden"/"removed" entries contribute nothing (absent-or-hidden = absent).
            -- A nil verdict (visible, or the hidden-channel reader not yet available)
            -- means included -- this can only ever widen the present-set, never shrink it.
            local verdict = ns.CDMEntryHiddenOrRemoved
                and ns.CDMEntryHiddenOrRemoved(cdID, mergedInfo, rawInfo, liveSetByCat[category])
            if verdict == nil and rawInfo then
                if _IsUsableSID(rawInfo.spellID) then present[rawInfo.spellID] = true end
                if _IsUsableSID(rawInfo.overrideSpellID) then present[rawInfo.overrideSpellID] = true end
                if type(rawInfo.linkedSpellIDs) == "table" then
                    for _, lsid in ipairs(rawInfo.linkedSpellIDs) do
                        if _IsUsableSID(lsid) then present[lsid] = true end
                    end
                end
            end
        end
    end
    if not sawEntry then return nil end

    -- Union live displayed buff-icon frame ids: shown always means keep, regardless of
    -- catalog/hidden-channel state.
    if ns.EnumerateCDMViewerSpells then
        for _, e in ipairs(ns.EnumerateCDMViewerSpells(true)) do
            if _IsUsableSID(e.sid) then present[e.sid] = true end
        end
    end
    return present
end

-- Entry point for the buff-family branch of the assigned-spell reconcile. Self-contained
-- (own guards, own health gate) so it stays correct regardless of caller. Reached today via
-- ns.ReconcileAssignedSpellDrops's buff-family branch (RS3, above), which any caller passing
-- a buff-family barKey exercises -- including the interactive options call sites. Extending
-- the automatic scheduler (ns.RequestCDMDropPass) to also iterate buff-family bar keys on
-- the reseed/settings-close/regen edges is a natural follow-up, not required for this
-- function to be reachable.
function ns.ReconcileBuffFamilyDrops(barKey)
    local p = ECME and ECME.db and ECME.db.profile
    if not p or not p.cdmBars then return nil end
    if not (ns.IsBarBuffFamily and ns.IsBarBuffFamily(barKey)) then return nil end
    local sd = ns.GetBarSpellData and ns.GetBarSpellData(barKey)
    if not sd or not sd.assignedSpells or #sd.assignedSpells == 0 then return sd end

    local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
    local sk = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
    local prof = sp and sk and sp[sk]
    if not prof or not prof._barFilterModelV6 or prof._importGhostMode then return sd end
    -- Data-loaded latch: unset until VARIABLES_LOADED + PLAYER_ENTERING_WORLD +
    -- COOLDOWN_VIEWER_DATA_LOADED have all fired, so this never drops against static
    -- defaults before persisted hide/recategorize overrides are merged in.
    if not ns._cdmDataLoaded then return sd end
    if InCombatLockdown() then
        -- Shared regen waiter (defined with ns.ReconcileAssignedSpellDrops /
        -- ns.RequestCDMDropPass, RS3/RS4 above): arms the PLAYER_REGEN_ENABLED
        -- listener that clears ns._cdmDropPending and re-requests a pass. Bare-setting
        -- the flag without arming the waiter would permanently disable every future
        -- automatic pass this session (cd/utility included) since nothing would ever clear it.
        ArmCDMDropRegenWaiter()
        return sd
    end

    local present = BuildBuffFamilyPresentSet()
    if not present then return sd end -- provider unhealthy: fail open, keep everything

    local ledger = prof.buffVariantAliases
    local custom  = sd.customSpellIDs
    local racials = ns._myRacialsSet
    local cdurs   = sd.customSpellDurations
    local sdurs   = sd.spellDurations
    local groups  = sd.customSpellGroups
    local hosted  = sd.hostedBuffSpellIDs

    local dropped = false
    local writeIdx = 1
    for readIdx = 1, #sd.assignedSpells do
        local id = sd.assignedSpells[readIdx]
        local keep = true
        if type(id) == "number" and id > 0
           and not (custom and custom[id])
           and not (racials and racials[id])
           and not (cdurs and cdurs[id])
           and not (sdurs and sdurs[id])
           and not (groups and groups[id])
           and not (hosted and hosted[id]) then
            -- Ledger closure: BFS over the persisted adjacency sets, seeded with the
            -- stored id AND its base/override forms (a stored base id whose live form
            -- was the one observed must still find its family).
            local seedBase = ns.NormalizeToBase and ns.NormalizeToBase(id) or id
            local seedLive = ns.ResolveToLive and ns.ResolveToLive(id) or id
            local ledgerClosure = { [id] = true, [seedBase] = true, [seedLive] = true }
            -- VOUCHED-ONLY (the June dual-tracked ban, reaffirmed 2026-08-13): the
            -- ledger must be able to TESTIFY about this id before absence may convict.
            -- A never-learned id (single-form buffs never enter the ledger; dual-
            -- tracked families before their first live observation) is KEPT
            -- unconditionally -- it lingers as a removable preview entry, the
            -- accepted June tradeoff. Family-of-one drop semantics silently
            -- resurrected the Vengeance Meta data-loss class and are FORBIDDEN.
            local vouched = false
            if ledger and (ledger[id] or ledger[seedBase] or ledger[seedLive]) then
                vouched = true
            end
            if ledger then
                local frontier, n = {}, 0
                for s0 in pairs(ledgerClosure) do n = n + 1; frontier[n] = s0 end
                while n > 0 do
                    local nf, nn = nil, 0
                    for i = 1, n do
                        local partners = ledger[frontier[i]]
                        if partners then
                            for partner in pairs(partners) do
                                if _IsUsableSID(partner) and not ledgerClosure[partner] then
                                    ledgerClosure[partner] = true
                                    nn = nn + 1
                                    nf = nf or {}
                                    nf[nn] = partner
                                end
                            end
                        end
                    end
                    frontier, n = nf, nn
                end
            end
            -- Union every closure member's base/override variants (StoreVariantValue-
            -- style expansion) so a talent swap on any family member still resolves.
            local family = {}
            for member in pairs(ledgerClosure) do
                if ns.StoreVariantValue then
                    ns.StoreVariantValue(family, member, true, false)
                else
                    family[member] = true
                end
            end
            local anyPresent = false
            for member in pairs(family) do
                if present[member] then anyPresent = true; break end
            end
            if vouched and not anyPresent then
                keep = false
                dropped = true
            end
        end
        if keep then
            sd.assignedSpells[writeIdx] = id
            writeIdx = writeIdx + 1
        end
    end
    for i = writeIdx, #sd.assignedSpells do sd.assignedSpells[i] = nil end
    if dropped then ns._spellOrderDirty = true end
    return sd
end

--- Repopulate all main bars from Blizzard CDM for the current spec.
--- Wipes ONLY Blizzard-sourced entries (positive spell IDs that the CDM
--- viewer owns) from assignedSpells/removedSpells, then rebuilds route
--- maps and reanchors. Preserves user-added entries:
---   * Negative IDs (trinket slots -13/-14, item presets <= -100)
---   * Custom spell IDs (entries in sd.customSpellIDs)
---   * Racial spells (entries in _myRacialsSet)
function ns.RepopulateFromBlizzard()
    local p = ECME.db and ECME.db.profile
    if not p or not p.cdmBars then return end
    local specKey = ns.GetActiveSpecKey()
    if not specKey or specKey == "0" then return end

    -- A spell ID is "user-added" (preserved across repopulate) if it's a negative preset marker, a custom spell ID added via the picker, or a racial belonging to this character.
    local function IsUserAdded(sd, id)
        if type(id) ~= "number" or id == 0 then return false end
        if id < 0 then return true end
        if sd.customSpellIDs and sd.customSpellIDs[id] then return true end
        if _myRacialsSet and _myRacialsSet[id] then return true end
        -- A positive id carrying a stored duration is one of OUR injected preset/custom buffs
        -- (Bloodlust/Heroism, potions, Time Spiral, custom buff IDs). Blizzard-tracked buffs are
        -- never written into assignedSpells with a duration, so this can only be a user-added entry -- preserve it. Presets predate the customSpellIDs flag, so the flag alone is not enough.
        if sd.spellDurations and (sd.spellDurations[id] or 0) > 0 then return true end
        return false
    end

    -- Filter a list in place: keep only entries IsUserAdded returns true for.
    local function FilterListPreservingUserAdded(sd, list)
        if type(list) ~= "table" then return end
        local writeIdx = 1
        for readIdx = 1, #list do
            local id = list[readIdx]
            if IsUserAdded(sd, id) then
                list[writeIdx] = id
                writeIdx = writeIdx + 1
            end
        end
        for i = writeIdx, #list do list[i] = nil end
    end

    -- Filter a set in place (keys = spell IDs): drop keys that aren't user-added.
    local function FilterSetPreservingUserAdded(sd, set)
        if type(set) ~= "table" then return end
        for id in pairs(set) do
            if not IsUserAdded(sd, id) then set[id] = nil end
        end
    end

    -- Filter Blizzard entries off all CD/utility bars (main + custom). Skip ghost, custom_buff,
    -- and default buff bar. The default buff bar (key == "buffs") has no assignedSpells to filter -- Blizzard's viewer is the authority. Extra buff bars ARE filtered for user assignments.
    for _, barData in ipairs(p.cdmBars.bars) do
        if not barData.isGhostBar
           and barData.key ~= "buffs"
           and (barData.barType == "cooldowns" or barData.barType == "utility"
                or barData.barType == "buffs"
                or MAIN_BAR_KEYS[barData.key]) then
            local sd = ns.GetBarSpellData(barData.key)
            if sd then
                FilterListPreservingUserAdded(sd, sd.assignedSpells)
                FilterSetPreservingUserAdded(sd, sd.removedSpells)
                -- spellSettings is per-spell config (font color, etc.) -- preserve entirely so user-added customs keep their styling.
            end
        end
    end

    -- Ghost bars hold Blizzard-owned spells the user explicitly hid. Filter the same way so user-added presets that may have been routed here (rare edge case) are preserved.
    local ghostSD = ns.GetBarSpellData(GHOST_CD_BAR_KEY)
    if ghostSD then
        FilterListPreservingUserAdded(ghostSD, ghostSD.assignedSpells)
        FilterSetPreservingUserAdded(ghostSD, ghostSD.removedSpells)
    end
    -- Ghost buff bar removed: buff visibility managed by Blizzard CDM.

    local buffSD = ns.GetBarSpellData("buffs")
    if buffSD then
        buffSD.buffDisplayOrder = nil
        buffSD._buffDisplayOrderUserModified = nil
    end
    ns._spellOrderDirty = true
    ns._cdmBuffOrderDirty = true  -- re-seed from Blizzard order on next reanchor

    -- Under the diversion-set model, "repopulate from Blizzard" is just "wipe diversions and let the route map's spillover show everything from the viewer" -- the wipes above are all that is needed.

    ns.FullCDMRebuild("repopulate")
    if ns.CollectAndReanchor then ns.CollectAndReanchor() end

    ns.ReseedAssignedSpellsFromLiveIcons()

    C_Timer.After(1, function()
        local sk = ns.GetActiveSpecKey()
        if sk and sk ~= "0" then
            SaveCurrentSpecProfile()
        end
    end)
end

-------------------------------------------------------------------------------
--  Register CDM bars with unlock mode
-------------------------------------------------------------------------------
RegisterCDMUnlockElements = function()
    if not EllesmereUI or not EllesmereUI.RegisterUnlockElements then return end
    local MK = EllesmereUI.MakeUnlockElement

    -- Build a lookup of which bars are anchored to which parent
    local anchorChildren = {}  -- parentKey -> { childKey1, childKey2, ... }
    for _, barData in ipairs(ECME.db.profile.cdmBars.bars) do
        local anchorKey = barData.anchorTo
        if anchorKey and anchorKey ~= "none" and anchorKey ~= "partyframe" and anchorKey ~= "playerframe" then
            if not anchorChildren[anchorKey] then anchorChildren[anchorKey] = {} end
            anchorChildren[anchorKey][#anchorChildren[anchorKey] + 1] = barData.key
        end
    end

    local elements = {}
    for _, barData in ipairs(ECME.db.profile.cdmBars.bars) do
        local key = barData.key
        local frame = cdmBarFrames[key]
        -- FocusKick is pinned to the focus nameplate, so it has no mover.
        if frame and barData.enabled and not barData.isGhostBar and key ~= FOCUSKICK_BAR_KEY then
            -- Skip bars anchored to party frame, player frame, or mouse cursor
            local isPartyAnchored = barData.anchorTo == "partyframe"
            local isPlayerFrameAnchored = barData.anchorTo == "playerframe"
            local isMouseAnchored = barData.anchorTo == "mouse"
            if not isPartyAnchored and not isPlayerFrameAnchored and not isMouseAnchored then
            local bd = barDataByKey[key]
            -- Additional Bar Offset: the unlock-anchored side folds through the
            -- shared _anchorExtraOffset registry (both ApplyAnchorPosition
            -- placement branches consume it). Registered for EVERY eligible bar
            -- and resolved LIVE: the value can change without this pass running
            -- (spec-override writes land raw in the bar table), so a
            -- register-only-while-nonzero getter went missing exactly when a
            -- spec's override turned the offset on. Zero reads as 0,0; it also
            -- returns 0 during unlock mode: movers show and save the BASE.
            local hasAddOffset = (barData.addOffsetX or 0) ~= 0 or (barData.addOffsetY or 0) ~= 0
            do
                local xoff = EllesmereUI._anchorExtraOffset
                if not xoff then
                    xoff = {}
                    EllesmereUI._anchorExtraOffset = xoff
                end
                xoff["CDM_" .. key] = function()
                    local bd3 = barDataByKey[key]
                    if not bd3 or EllesmereUI._unlockActive then return 0, 0 end
                    return bd3.addOffsetX or 0, bd3.addOffsetY or 0
                end
            end
            -- Collect linked unlock element keys (children anchored to this bar)
            local linked = nil
            if anchorChildren[key] then
                linked = {}
                for _, childKey in ipairs(anchorChildren[key]) do
                    linked[#linked + 1] = "CDM_" .. childKey
                end
            end

            -- Buff-type bars can't be anchor targets (their icon count changes dynamically with auras, causing cascading position shifts).
            local isBuff = ns.IsBarBuffFamily(barData)
            local isDynamic = isBuff or (barData.barType == "custom_buff")
            elements[#elements + 1] = MK({
                key = "CDM_" .. key,
                label = "CDM: " .. barData.name,
                group = "Cooldown Manager",
                order = 600,
                -- Additional Bar Offset marker: distinct warm mover tint +
                -- explanatory tooltip while an offset is set (nil otherwise --
                -- the mover renders exactly as before).
                moverBg = hasAddOffset and { r = 0.32, g = 0.19, b = 0.05 } or nil,
                -- Tooltip resolves live (nil = inert) so an override-written
                -- offset still explains itself even when the tint was
                -- registered without one.
                moverTooltip = function()
                    local bd3 = barDataByKey[key]
                    local ox = (bd3 and bd3.addOffsetX) or 0
                    local oy = (bd3 and bd3.addOffsetY) or 0
                    if ox == 0 and oy == 0 then return nil end
                    -- Stored in coordinate units; the options sliders show
                    -- physical pixels, so report the same unit here.
                    local toPx = EllesmereUI.PP.ToPixels
                    ox, oy = toPx(ox), toPx(oy)
                    return EllesmereUI.Lf(
                        "This bar has an Additional Bar Offset (X %1$s, Y %2$s) set in its options. Unlock mode shows the base position; the offset re-applies when you exit.",
                        ox, oy)
                end,
                linkedKeys = linked,
                noAnchorTarget = isDynamic,
                noResize = isDynamic,
                isHidden = function()
                    -- If this bar key is no longer in the current profile's barDataByKey, it is a stale registration from a previous profile and should not get a mover.
                    return not barDataByKey[key]
                end,
                getFrame = function() return cdmBarFrames[key] end,
                getSize = function()
                    local f = cdmBarFrames[key]
                    local bd2 = barDataByKey[key]
                    return GetStableCDMBarSize(key, f, bd2)
                end,
                linkedDimensions = true,
                setWidth = function(_, newW)
                    -- iconSize is derived live in LayoutCDMBar from the source bar's current width;
                    -- setWidth just triggers a re-layout. Nothing is persisted -- the source bar IS the truth. Wipe legacy cache fields so they can't poison anything.
                    local bd2 = barDataByKey[key]
                    if not bd2 then return end
                    bd2._matchPhysWidth = nil
                    bd2._matchPhysHeight = nil
                    bd2._matchIconPhys = nil
                    bd2._matchStride = nil
                    bd2._matchExtraPixels = nil
                    bd2._matchExtraPixelsH = nil
                    bd2._matchStrideH = nil
                    LayoutCDMBar(key)
                end,
                setHeight = function(_, newH)
                    -- See setWidth -- live-derive in LayoutCDMBar.
                    local bd2 = barDataByKey[key]
                    if not bd2 then return end
                    bd2._matchPhysWidth = nil
                    bd2._matchPhysHeight = nil
                    bd2._matchIconPhys = nil
                    bd2._matchStride = nil
                    bd2._matchExtraPixels = nil
                    bd2._matchExtraPixelsH = nil
                    bd2._matchStrideH = nil
                    LayoutCDMBar(key)
                end,
                savePos = function(_, point, relPoint, x, y)
                    local p = ECME.db.profile
                    local storePoint, storeX, storeY = point, x, y
                    local bd2 = barDataByKey[key]
                    local grow = bd2 and bd2.growDirection
                    local frame = cdmBarFrames[key]
                    -- Store at the growth edge (and, when "anchor first row" is on, the first-row
                    -- corner) so SetSize grows naturally from the fixed edge/corner with no
                    -- post-resize re-anchoring. Unlock mode always provides CENTER coords; convert
                    -- to the resolved anchor, skipping any axis with no extent yet (empty bar).
                    -- Snapped bars always store the plain growth edge: the anchor system's saved-edge consumers only understand single-edge points, so a corner would silently break edge preservation and target follow for them.
                    local isSnapped = EllesmereUI.IsUnlockAnchored
                        and EllesmereUI.IsUnlockAnchored("CDM_" .. key)
                    local resolved = ns.ResolveGrowAnchorPoint(bd2, isSnapped)
                    if resolved ~= "CENTER" and frame then
                        local fw = frame:GetWidth() or 0
                        local fh = frame:GetHeight() or 0
                        local needW = resolved:find("LEFT", 1, true) or resolved:find("RIGHT", 1, true)
                        local needH = resolved:find("TOP", 1, true) or resolved:find("BOTTOM", 1, true)
                        if (not needW or fw > 0) and (not needH or fh > 0) then
                            storePoint = resolved
                            storeX, storeY = ns.CenterToAnchorCoord(resolved, x, y, fw, fh)
                        end
                    end
                    -- Phase 2 follow baseline: capture the anchor target's center (UIParent space) at
                    -- save time so ApplyAnchorPosition can later shift the absolute saved edge by the
                    -- target's displacement. Only for growth bars; nil for unanchored/CENTER bars ->
                    -- follow stays off (pure absolute pin). require-re-save: existing bars pick this up only when next dragged + Save & Exit.
                    local tgtx, tgty
                    local tgtL, tgtR, tgtT, tgtB
                    if grow and grow ~= "CENTER" and EllesmereUI.GetAnchorTargetCenterUI then
                        tgtx, tgty = EllesmereUI.GetAnchorTargetCenterUI("CDM_" .. key)
                        -- Corner-follow baseline: the target's edges at save time, captured ONLY when
                        -- anchored to another CDM bar. Lets ApplyAnchorPosition hold a perpendicular (corner) bar against the target edge when the target's width/height changes. nil otherwise -> corner follow stays off.
                        if EllesmereUI.GetAnchorTargetEdgesUI then
                            tgtL, tgtR, tgtT, tgtB = EllesmereUI.GetAnchorTargetEdgesUI("CDM_" .. key)
                        end
                    end
                    p.cdmBarPositions[key] = { point = storePoint, relPoint = relPoint, x = storeX, y = storeY,
                        tgtx = tgtx, tgty = tgty, tgtL = tgtL, tgtR = tgtR, tgtT = tgtT, tgtB = tgtB }
                    -- Skip rebuild when called from anchor propagation or while unlock mode is active (unlock mode owns positioning then).
                    if not EllesmereUI._propagatingSave and not EllesmereUI._unlockActive then
                        BuildAllCDMBars()
                    end
                end,
                loadPos = function()
                    local pos = ECME.db.profile.cdmBarPositions[key]
                    if not pos or not pos.point then return pos end
                    -- Convert edge/corner-stored positions back to CENTER for the unlock mode system (it always works with CENTER coords).
                    local pt = pos.point
                    if pt ~= "CENTER" and pt ~= "" then
                        local frame = cdmBarFrames[key]
                        if frame then
                            local fw = frame:GetWidth() or 0
                            local fh = frame:GetHeight() or 0
                            local cx, cy = ns.AnchorCoordToCenter(pt, pos.x or 0, pos.y or 0, fw, fh)
                            return { point = "CENTER", relPoint = pos.relPoint, x = cx, y = cy }
                        end
                    end
                    return pos
                end,
                clearPos = function()
                    ECME.db.profile.cdmBarPositions[key] = nil
                end,
                applyPos = function()
                    -- While the authoritative reanchor pass is still pending (login window, or the
                    -- instant inside a spec-swap reconcile) the CDM pipeline owns layout and applies
                    -- saved positions itself; a rebuild here only races it against a still-churning engine pool. The flag is consumed deterministically by CollectAndReanchor.
                    if ns._pendingApplyOnReanchor then return end
                    -- Mid-transition guard: when the live spec key disagrees with the cached key, a
                    -- rebuild here can only construct the OLD spec's layout against the NEW spec's
                    -- already-repopulating engine pool (the pre-swap window before SPELLS_CHANGED lands). The talent_reconcile that follows is the only correct builder for that state.
                    local liveKey = ComputeLiveSpecKey()
                    if liveKey and liveKey ~= _cachedSpecKey then return end
                    -- Same-burst coalescing: position passes (ApplySavedPositions et al) call EVERY
                    -- CDM element's applyPosition back-to-back, and each call rebuilt ALL bars -- an
                    -- 11+ deep same-frame rebuild storm. The first call rebuilds synchronously (Save & Exit's sequencing depends on that); the rest of the burst no-ops until the next frame.
                    if ns._applyPosCoalesced then return end
                    ns._applyPosCoalesced = true
                    C_Timer.After(0, function() ns._applyPosCoalesced = nil end)
                    BuildAllCDMBars()
                end,
                isAnchored = function()
                    local bd2 = barDataByKey[key]
                    if not bd2 or not bd2.anchorTo then return false end
                    local a = bd2.anchorTo
                    -- Only valid anchor types: mouse, partyframe, playerframe, erb_*
                    if a == "mouse" or a == "partyframe" or a == "playerframe" then return true end
                    if a:sub(1, 4) == "erb_" then return true end
                    return false
                end,
            })
            end -- not isPartyAnchored
        end
    end

    if #elements > 0 then
        EllesmereUI:RegisterUnlockElements(elements, "EllesmereUICooldownManager")
    end
    -- Expose for ApplyAnchorPosition's growth-direction edge read. Width-independent: stores edge anchor directly (LEFT/RIGHT/TOP).
    EllesmereUI._cdmBarPositions = ECME.db.profile.cdmBarPositions
end

-- "Additional Bar Offset" unlock lifecycle: rides the shared shift-provider
-- list (EUI_UnlockMode.lua; direct or-preserve push, never an API call). dir
-- is inert -- anchored bars receive the offset through _anchorExtraOffset, not
-- the shift path. enter (unlock entry + combat resume, before positions are
-- snapshotted) re-builds so UN-anchored offset bars land at their true saved
-- positions (_unlockActive is already set, the offset helper returns 0);
-- restore (unlock exit) re-builds to re-apply the offset and re-runs the
-- anchors of unlock-anchored offset bars (the build deliberately leaves those
-- positions alone). Everything self-gates on a nonzero offset existing, so a
-- profile that never touches the setting schedules ZERO work. do-block: this
-- file is at the 200-local cap, nothing here may persist a file-scope local.
do
    local function AnyBarHasAddOffset()
        local p = ECME and ECME.db and ECME.db.profile
        local bars = p and p.cdmBars and p.cdmBars.bars
        if not bars then return false end
        for i = 1, #bars do
            local bd = bars[i]
            if bd.enabled and ((bd.addOffsetX or 0) ~= 0 or (bd.addOffsetY or 0) ~= 0) then
                return true
            end
        end
        return false
    end
    EllesmereUI._anchorShiftProviders = EllesmereUI._anchorShiftProviders or {}
    table.insert(EllesmereUI._anchorShiftProviders, {
        dir = function() return 0 end,
        wants = AnyBarHasAddOffset,
        enter = function()
            -- Reposition ONLY the offset bars, never a full rebuild: a rebuild
            -- re-applies saved positions to EVERY un-anchored bar, which would
            -- revert un-saved mover drags on the combat-resume path
            -- (audit-caught). _unlockActive is already true here, so the
            -- offset helper reads 0 and each bar lands at its BASE position
            -- for the snapshot. Unlock-ANCHORED offset bars are stripped by
            -- the wants-gated anchor reapply that follows; module-anchored
            -- bars have no movers and snapshot nothing.
            local p = ECME and ECME.db and ECME.db.profile
            local bars = p and p.cdmBars and p.cdmBars.bars
            if not bars then return end
            for i = 1, #bars do
                local bd = bars[i]
                if bd.enabled and ((bd.addOffsetX or 0) ~= 0 or (bd.addOffsetY or 0) ~= 0)
                    and (bd.anchorTo or "none") == "none"
                    and not (EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored("CDM_" .. bd.key)) then
                    local frame = cdmBarFrames[bd.key]
                    local pos = p.cdmBarPositions and p.cdmBarPositions[bd.key]
                    if frame and pos and pos.point then
                        ApplyBarPositionCentered(frame, pos, bd.key)
                    end
                end
            end
        end,
        restore = function()
            if not AnyBarHasAddOffset() then return end
            BuildAllCDMBars()
            if EllesmereUI.PropagateAnchorChain and EllesmereUI.IsUnlockAnchored then
                local p = ECME and ECME.db and ECME.db.profile
                local bars = p and p.cdmBars and p.cdmBars.bars
                if bars then
                    for i = 1, #bars do
                        local bd = bars[i]
                        if bd.enabled and ((bd.addOffsetX or 0) ~= 0 or (bd.addOffsetY or 0) ~= 0)
                            and EllesmereUI.IsUnlockAnchored("CDM_" .. bd.key) then
                            EllesmereUI.PropagateAnchorChain("CDM_" .. bd.key)
                        end
                    end
                end
            end
        end,
    })
end
ns.RegisterCDMUnlockElements = RegisterCDMUnlockElements
_G._ECME_RegisterUnlock = RegisterCDMUnlockElements

-- Positions-only re-apply for every enabled bar (no rebuild): un-anchored
-- bars from their saved position (Additional Bar Offset folded by
-- ApplyBarPositionCentered), unlock-anchored bars through the anchor chain
-- (offset folded by the _anchorExtraOffset getter). Module-anchored bars
-- (party/player/ERB) are placed inside BuildCDMBar and are left to the next
-- build. Used when a settings write lands but the follow-up rebuild is
-- deliberately suppressed (spec-override values written right after a spec
-- change), so the bar still moves to its new offset. On ns: 200-local cap.
ns.CDMReapplyBarPositions = function()
    local p = ECME and ECME.db and ECME.db.profile
    local bars = p and p.cdmBars and p.cdmBars.bars
    -- Never inside unlock mode: movers own positions there and a re-place
    -- from saved coords would revert un-saved drags.
    if not bars or InCombatLockdown() or EllesmereUI._unlockActive then return end
    for i = 1, #bars do
        local bd = bars[i]
        if bd.enabled and (bd.anchorTo or "none") == "none" then
            local ukey = "CDM_" .. bd.key
            if EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored(ukey) then
                if EllesmereUI.PropagateAnchorChain then EllesmereUI.PropagateAnchorChain(ukey) end
            else
                local frame = cdmBarFrames[bd.key]
                local pos = p.cdmBarPositions and p.cdmBarPositions[bd.key]
                if frame and pos and pos.point then
                    ApplyBarPositionCentered(frame, pos, bd.key)
                end
            end
        end
    end
end

-- RequestUpdate delegates to ns.RequestUpdate (defined in EllesmereUICdmBarGlows.lua). Falls back to no-op if bar glows module hasn't loaded yet.
local function RequestUpdate()
    if ns.RequestUpdate then ns.RequestUpdate() end
end


-------------------------------------------------------------------------------
--  Bootstrap / Addon Enable
--
--  `OnInitialize` runs once per addon load to create SavedVariables hooks and
--  expose options callbacks. `OnEnable` runs once per login/reload session to
--  load spec state, initialize helper modules, and choose between first-login
--  capture and the normal `CDMFinishSetup` path.
-------------------------------------------------------------------------------
function ECME:OnInitialize()
    self.db = EllesmereUI.Lite.NewDB("EllesmereUICooldownManagerDB", DEFAULTS, true)

    -- Save spec profile before StripDefaults runs on logout
    EllesmereUI.Lite.RegisterPreLogout(function()
        local specKey = ns.GetActiveSpecKey()
        if specKey and specKey ~= "0" then
            SaveCurrentSpecProfile()
        end
    end)

    -- Check if we need first-login capture (per-install flag on SV root)
    self._needsCapture = not self.db.sv._capturedOnce_CDM

    -- Expose for options
    _G._ECME_AceDB = self.db
    _G._ECME_Apply = function()
        if ns._skipNextApplyRebuild then
            ns._skipNextApplyRebuild = false
        elseif ns._specChangeJustRan then
            ns._specChangeJustRan = false
            -- The flag suppresses the profile system's follow-up rebuild right after a spec change
            -- -- but same-profile swaps never run that follow-up, leaving the flag armed until some LATER apply consumed it and silently skipped a rebuild the caller needed. Only honor the suppression while the spec change is recent.
            if not (ns._specChangeAt and (GetTime() - ns._specChangeAt) < 3) then
                ns.FullCDMRebuild("apply")
            elseif ns.CDMReapplyBarPositions then
                -- Suppressed rebuild: the caller may still have written bar
                -- settings (spec-override values land AFTER the reconcile), so
                -- re-place the bars from the now-current settings.
                ns.CDMReapplyBarPositions()
            end
        else
            ns.FullCDMRebuild("apply")
        end
        if ns.UpdateCustomBuffAuraTracking then ns.UpdateCustomBuffAuraTracking() end
        if ns.UpdateCustomBuffBars then ns.UpdateCustomBuffBars() end
    end

    -- Append SharedMedia textures to TBB runtime tables
    if EllesmereUI.AppendSharedMediaTextures and ns.TBB_TEXTURE_NAMES then
        EllesmereUI.AppendSharedMediaTextures(
            ns.TBB_TEXTURE_NAMES,
            ns.TBB_TEXTURE_ORDER,
            nil,
            ns.TBB_TEXTURES
        )
    end
end

-- Tracks whether CDMFinishSetup has already run for this session. Set when the spec resolves and
-- we kick off the build, prevents double-init if multiple wakeup events fire (PLAYER_LOGIN + first PLAYER_SPECIALIZATION_CHANGED).
local _cdmSetupStarted = false

function ECME:OnEnable()
    -- Cache player race/class for trinket/racial/potion tracking
    _playerRace = select(2, UnitRace("player"))
    _playerClass = select(2, UnitClass("player"))
    ns._playerRace = _playerRace
    ns._playerClass = _playerClass
    ns._myRacialsSet = _myRacialsSet
    ns.RefreshLustPresetFaction()

    -- Build cached racial spell list for this character (used for render-time substitution)
    table.wipe(_myRacials)
    table.wipe(_myRacialsSet)
    local racialList = _playerRace and RACE_RACIALS[_playerRace]
    if racialList then
        for _, entry in ipairs(racialList) do
            local sid = type(entry) == "table" and entry[1] or entry
            local reqClass = type(entry) == "table" and entry.class or nil
            local excludeClass = type(entry) == "table" and entry.notClass or nil
            local classOk = (not reqClass or reqClass == _playerClass)
                and (not excludeClass or excludeClass ~= _playerClass)
            if classOk then
                _myRacials[#_myRacials + 1] = sid
                _myRacialsSet[sid] = true
            end
        end
    end

    -- Resolve the in-spellbook racial (the generic "Racial" picker slot maps to this ID). Re-resolved at build time too (spellbook may be empty here).
    ResolveActiveRacial()

    -- Blizzard overlays persisted hide/recategorize overrides onto its settings provider
    -- only after its own three-event wait completes (CooldownViewerSettings.lua OnLoad:
    -- VARIABLES_LOADED + PLAYER_ENTERING_WORLD + COOLDOWN_VIEWER_DATA_LOADED), registered
    -- at OnLoad -- far earlier than this deferred OnEnable (dispatched from a C_Timer past
    -- PLAYER_LOGIN, by which point VARIABLES_LOADED has already fired once and will not
    -- fire again this session). Re-registering that same wait here would silently never
    -- complete, so check the real downstream signal instead: the data provider only
    -- exposes a layoutManager once Blizzard's own Init has run. Reading merged categories
    -- before that finishes sees static defaults only and silently misses persisted
    -- hide/recategorize overrides.
    local function CheckCDMDataLoaded()
        if ns._cdmDataLoaded then return true end
        if not (CooldownViewerSettings and CooldownViewerSettings.GetDataProvider) then return false end
        local ok, provider = pcall(CooldownViewerSettings.GetDataProvider, CooldownViewerSettings)
        if not ok or not provider or not provider.GetLayoutManager then return false end
        local ok2, layoutManager = pcall(provider.GetLayoutManager, provider)
        if ok2 and layoutManager then
            ns._cdmDataLoaded = true
            return true
        end
        return false
    end

    if not CheckCDMDataLoaded() then
        local dataWakeFrame = ns.TakeShell()
        dataWakeFrame:RegisterEvent("COOLDOWN_VIEWER_DATA_LOADED")
        dataWakeFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        dataWakeFrame:SetScript("OnEvent", function(self)
            if CheckCDMDataLoaded() then
                self:UnregisterAllEvents()
                self:SetScript("OnEvent", nil)
                -- SetupViewerHooks' own 0.2/1/3/6s reanchor retries can all fire before
                -- Blizzard's data actually becomes ready on a slow login and never try
                -- again. Catch up now.
                if ns.QueueReanchor then ns.QueueReanchor() end
            end
        end)
    end

    -- NO spec-swap drop-pass guard lives here, deliberately (a PSC-edge
    -- unlatch was built and REMOVED same day): the destructive pass rode
    -- SPELLS_CHANGED, which can dispatch before PLAYER_SPECIALIZATION_CHANGED,
    -- and the latch probe only proves the layout manager EXISTS -- neither
    -- edge can prove the catalog serves the NEW spec. The fix is upstream:
    -- the swap-path rebuild tail requests no drop pass at all (see the
    -- reanchor tail in CdmHooks). Removal sync = settled-state triggers only.

    -- Enable CDM cooldown viewer (keep Blizzard CDM running in background so we can read its children even while hidden)
    if C_CVar and C_CVar.SetCVar then
        pcall(C_CVar.SetCVar, "cooldownViewerEnabled", "1")
    end

    -- Spec-gated build: only run CDMFinishSetup once a real spec key exists from the live API; if
    -- the API isn't ready, defer until it is. Wait until the truth is known, then build once -- never guess the spec and repair later.
    local function TryBuildCDM()
        if _cdmSetupStarted then return end
        if not ns.GetActiveSpecKey() then return end -- spec API not ready yet
        _cdmSetupStarted = true
        EnsureMappings(GetStore())
        if self._needsCapture then
            -- Capture Blizzard's Edit Mode layout once it has applied positions (at/after
            -- PLAYER_ENTERING_WORLD). OnEnable/TryBuildCDM run deferred past the login PEW (the
            -- Lite enable-flush dispatches OnEnable from a C_Timer past PLAYER_LOGIN -- Edit Mode
            -- taint fix -- and a spec-change wakeup can defer further), so on a fresh install the
            -- login PEW has already fired and a plain RegisterEvent would wait for the next zone
            -- change, leaving the tracker unbuilt all session. Keep the event as a backstop and, since we're already in-world with Edit Mode applied, capture now; the _needsCapture guard keeps both paths idempotent.
            self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnCDMFirstLogin")
            if IsLoggedIn() then
                C_Timer.After(0, function()
                    if self._needsCapture then self:OnCDMFirstLogin() end
                end)
            end
        else
            self:CDMFinishSetup()
        end
    end

    -- Try immediately. If the spec API is already populated (most reloads), this builds in-place and we're done.
    TryBuildCDM()

    -- If the immediate try didn't fire, wake up on the events that signal spec data is now
    -- available and try again. The handler is idempotent via _cdmSetupStarted so multiple wakeups are harmless.
    if not _cdmSetupStarted then
        local wakeFrame = ns.TakeShell()
        wakeFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        wakeFrame:RegisterEvent("PLAYER_LOGIN")
        wakeFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        wakeFrame:SetScript("OnEvent", function(self)
            ns.InvalidateSpecKey()
            TryBuildCDM()
            if _cdmSetupStarted then
                self:UnregisterAllEvents()
                self:SetScript("OnEvent", nil)
            end
        end)
    end

    -- Proc glow hooks: install immediately + retry. Hooks must be in place before Blizzard re-fires ShowAlert at PLAYER_LOGIN for active procs.
    InstallProcGlowHooks()
    C_Timer.After(0.5, InstallProcGlowHooks)

    -- Initialize Bar Glows overlay system
    if ns.InitBarGlows then ns.InitBarGlows() end

end

function ECME:OnCDMFirstLogin()
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    -- A profile import can stamp the capture flag mid-session (imported data is a chosen layout).
    -- Honor the stamp here so a still-pending capture never overwrites the imported profile; just finish the deferred setup.
    if not self.db.sv._capturedOnce_CDM then
        CDMFirstLoginCapture()
    end
    self._needsCapture = false
    self:CDMFinishSetup()
end

-- Architecture: assignedSpells is pure user intent and is never mutated based on "is this spell
-- currently known". Talent/spec/reload events rebuild the cdID route map and reanchor -- the route
-- map is the source of truth for which Blizzard frame renders on which bar. Spells whose backing
-- frame is temporarily absent (pet dismissed, choice-node talent swapped away) simply don't render until the frame returns; their assigned slot is preserved.

function ECME:CDMFinishSetup()

    -- This is the one-time construction hub for a normal login/reload enable: preload unlock
    -- helpers, build the initial bar set, spin up the periodic tick frame, then schedule any
    -- deferred reconciliation/rebuild passes needed once Blizzard's viewer children and layout have
    -- settled. Run the unlock-core body early so anchor/propagation functions (ApplyAnchorPosition,
    -- PropagateWidthMatch, etc.) are available for the initial build pass -- NOT EnsureLoaded,
    -- which would pull the LoadOnDemand options addon into every login. CDM SavedVariables are ready by this point.
    EllesmereUI:EnsureUnlockCore()

    -- Pre-size CDM bar frames using cached icon counts from last session. Purely cosmetic: gives
    -- anchored elements correct dimensions to compute against before the real spell data populates. BuildAllCDMBars below overwrites everything with real data.
    do
        local p = ECME.db and ECME.db.profile
        if p and p.cdmBars and p.cdmBars.enabled and EllesmereUIDB then

            local charKey = ns.GetCharKey()
            local specKey = ns.GetActiveSpecKey()
            local cache = EllesmereUIDB.cdmCachedBarSizes
            local counts = cache and cache[charKey] and cache[charKey][specKey]
            if counts then
                for i, barData in ipairs(p.cdmBars.bars) do
                    if barData.enabled then
                        local cachedCount = counts[barData.key]
                        if cachedCount and cachedCount > 0 then
                            local key = barData.key
                            local frame = cdmBarFrames[key]
                            if not frame then
                                frame = CreateFrame("Frame", "ECME_CDMBar_" .. key, UIParent)
                                frame:SetFrameStrata(barData.barStrata or "MEDIUM")
                                frame:SetFrameLevel(5)
                                if frame.SetSnapToPixelGrid then frame:SetSnapToPixelGrid(false) end
                                if frame.SetTexelSnappingBias then frame:SetTexelSnappingBias(0) end
                                if frame.EnableMouseClicks then frame:EnableMouseClicks(false) end
                                -- Containers never capture mouse motion (see BuildCDMBar creation block).
                                if frame.EnableMouseMotion then frame:EnableMouseMotion(false) end
                                frame._barKey = key
                                frame._barIndex = i
                                cdmBarFrames[key] = frame
                                cdmBarIcons[key] = {}
                            end
                            -- Raw coord values -- see LayoutCDMBar for why we don't pre-snap with SnapForScale (PP.Scale truncation loses a pixel at UI scales with PP.mult > 1).
                            local iconW = barData.iconSize or 36
                            local iconH = iconW
                            if (barData.iconShape or "none") == "cropped" then
                                iconH = math.floor((barData.iconSize or 36) * 0.80 + 0.5)
                            end
                            local spacing = barData.spacing or 2
                            local grow = barData.growDirection or "CENTER"
                            -- Effective row count: collapses to 1 when a custom top-row split has no icons in its second row yet.
                            local stride, numRows = ComputeTopRowStride(barData, cachedCount)
                            if numRows < 1 then numRows = 1 end
                            -- Minimum Bar Size reserves extra growth-axis slots (no-op when unset); without it a bar under its minimum pre-sizes too small and visibly snaps once real data lands.
                            local resStride = ReserveStride(barData, stride)
                            local isHoriz = (grow == "RIGHT" or grow == "LEFT" or (grow == "CENTER" and not barData.verticalOrientation))
                            -- Compute total in integer phys px to avoid PP.Scale floor losing 1 px to floating-point dust on the multiply.
                            local PPpc = EllesmereUI and EllesmereUI.PP
                            local onePxPc = PPpc and PPpc.mult or 1
                            local iconWPx   = math.floor(iconW   / onePxPc + 0.5)
                            local iconHPx   = math.floor(iconH   / onePxPc + 0.5)
                            local spacingPx = math.floor(spacing / onePxPc + 0.5)
                            local totalWPx, totalHPx
                            if isHoriz then
                                totalWPx = resStride * iconWPx + (resStride - 1) * spacingPx
                                totalHPx = numRows   * iconHPx + (numRows   - 1) * spacingPx
                            else
                                totalWPx = numRows   * iconWPx + (numRows   - 1) * spacingPx
                                totalHPx = resStride * iconHPx + (resStride - 1) * spacingPx
                            end
                            local totalW = totalWPx * onePxPc
                            local totalH = totalHPx * onePxPc
                            frame:SetSize(totalW, totalH)
                            frame._prevLayoutW = totalW
                            frame._prevLayoutH = totalH
                            local pos = p.cdmBarPositions and p.cdmBarPositions[key]
                            if pos and pos.point then
                                frame:ClearAllPoints()
                                frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
                            end
                            frame:Show()
                        end
                    end
                end
            end
        end
    end

    -- (Migration moved to CollectAndReanchor: it must run after the viewer pools are populated, which only happens after the first successful reanchor.)

    ns.FullCDMRebuild("init")

    -- Initialize Tracking Bars GetTrackedBuffBars auto-initializes empty bars if none exist. No
    -- validation/removal: TBB bars can track any buff (procs, external buffs, food, etc.) not just
    -- CDM viewer spells. Bars with no active aura simply stay hidden at runtime. Nil-guarded so the TBB file can be bisect-disabled wholesale.
    if ns.GetTrackedBuffBars then ns.GetTrackedBuffBars() end

    -- (BuildTrackedBuffBars not called here -- FullCDMRebuild("init") above already called it.
    -- M1 cleanups also deleted: AddSpellToBar's variant-aware dedup prevents duplicate spell entries at insert time.)

    -- Hook Blizzard CDM viewer pools (route map already built by FullCDMRebuild)
    ns.SetupViewerHooks()

    -- FocusKick family (anchor proxy + plate watcher, reminder text, cast sound): demand-gated -- an EMPTY kick bar installs nothing at all.
    ns.RefreshFocusKickProxies()
    -- ...and again after every loading screen. Demand-gating makes arming a one-shot, so any pass
    -- that runs before the spell store resolves leaves the cast-sound proxy unbuilt until something
    -- unrelated rebuilds the bars (a spec change, or opening the options). That is the reported
    -- "sound stops working after I port" and it never recovers on its own. The refresh is cheap and idempotent: it early-returns when the bar is empty and re-registers the same events when it is not.
    do
        local fkRearm = CreateFrame("Frame")
        fkRearm:RegisterEvent("PLAYER_ENTERING_WORLD")
        fkRearm:SetScript("OnEvent", function()
            C_Timer.After(2, function()
                if ns.RefreshFocusKickProxies then ns.RefreshFocusKickProxies() end
            end)
        end)
    end
    -- SharedMedia sounds feed the options dropdowns; append regardless.
    if EllesmereUI.AppendSharedMediaSounds then
        EllesmereUI.AppendSharedMediaSounds(
            FOCUSKICK_SOUND_PATHS,
            FOCUSKICK_SOUND_NAMES,
            FOCUSKICK_SOUND_ORDER
        )
    end

    -- One-time vehicle/petbattle proxy. Drives _CDMApplyVisibility on state change so CDM bars hide while the vehicle UI or pet battle UI is active.
    if not _cdmVehicleProxy then
        _cdmVehicleProxy = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
        _cdmVehicleProxy:SetAttribute("_onstate-cdmvehicle", [[
            self:CallMethod("OnVehicleStateChanged", newstate)
        ]])
        _cdmVehicleProxy.OnVehicleStateChanged = function(_, state)
            _cdmInVehicle = (state == "hide")
            _CDMApplyVisibility()
        end
        RegisterStateDriver(_cdmVehicleProxy, "cdmvehicle", "[vehicleui][petbattle] hide; show")
    end


    -- Edit mode close: no forced rebuild needed. The reanchor naturally skips inactive buff frames with hideWhenInactive (ghost frames from Edit Mode) and alpha-0s them as unclaimed. Normal hooks handle the rest.

    -- Register UNIT_AURA tracking if custom buff bars have spells
    if ns.UpdateCustomBuffAuraTracking then ns.UpdateCustomBuffAuraTracking() end

    -- Deferred keybind update: wait 3s so Blizzard's hotkey update cycle has fully run before we read HotKey text from button frames
    C_Timer.After(3, UpdateCDMKeybinds)

    -- (Tick frame removed -- all CDM updates are now event-driven via hooks. CollectAndReanchor runs only when Blizzard fires lifecycle hooks.)

    -- Register with unlock mode. Both default+custom CDM bars and TBB elements register synchronously here so anchor data is available before CollectAndReanchor runs.
    RegisterCDMUnlockElements()
    if ns.RegisterTBBUnlockElements then ns.RegisterTBBUnlockElements() end

    -- CDM is the authoritative trigger for the final layout pass when it is enabled. Set a flag so
    -- the next CollectAndReanchor that completes (after icons are populated and bar sizes are correct) will fire ApplyAllWidthHeightMatches + _applySavedPositions in the right order.
    --
    -- Why CDM owns this:
    --   1. CDM bars are the slowest thing to settle -- they depend on Blizzard CDM viewer pools being populated, which is async.
    --   2. ApplyAllWidthHeightMatches reads source bar widths and propagates them; if CDM bars are still being built when this runs, the sizes are transient/wrong.
    --   3. _applySavedPositions iterates registered elements and applies anchors; if CDM bars haven't registered yet (or their target ERB bars haven't), anchors silently drop and the bar lands at its CENTER/CENTER fallback (= screen center).
    ns._pendingApplyOnReanchor = true
end

-------------------------------------------------------------------------------
--  Rotation Helper Integration (Blizzard C_AssistedCombat)
--  Highlights the currently suggested spell on its CDM icon using Blizzard's
--  native ActionBarButtonAssistedCombatHighlightTemplate -- same shine as the
--  stock action bars. Gated purely by Blizzard's "assistedCombatHighlight"
--  CVar; we don't carry a second toggle of our own.
-------------------------------------------------------------------------------
ns._rotationGlowedIcons = {}
ns._rotationHookInstalled = false
ns._rotationInCombat = false

local ROT_GLOW_RATIO = 0.33

local function _rotCVarOn()
    -- User can force-hide via our own toggle, overriding Blizzard's CVar
    local p = ECME.db and ECME.db.profile
    if p and p.cdmBars and p.cdmBars.hideRotationHelper then return false end
    return GetCVarBool and GetCVarBool("assistedCombatHighlight")
end

local function _rotCreateHighlight(icon)
    local ok, hf = pcall(CreateFrame, "Frame", nil, icon, "ActionBarButtonAssistedCombatHighlightTemplate")
    if not ok or not hf then return nil end
    hf:SetAllPoints()
    -- Sit above everything on the icon: Blizzard's cooldown swipe, our border frame, our glowOverlay (+6), and any proc alert frames. +15 clears them all with margin.
    hf:SetFrameLevel(icon:GetFrameLevel() + 15)
    hf:Hide()
    if hf.Flipbook and hf.Flipbook.Anim then
        hf.Flipbook.Anim:Play()
        hf.Flipbook.Anim:Stop()
    end
    return hf
end

local function _rotHide(icon)
    local rfc = icon and _ecmeFC[icon]
    local hf = rfc and rfc.rotationHighlight
    if not hf then return end
    if hf.Flipbook and hf.Flipbook.Anim then hf.Flipbook.Anim:Stop() end
    hf:Hide()
end

local function _rotShow(icon)
    if not icon then return end
    local rfc = FC(icon)
    local hf = rfc.rotationHighlight
    if not hf then
        hf = _rotCreateHighlight(icon)
        if not hf then return end
        rfc.rotationHighlight = hf
    end
    if hf.Flipbook then
        local w = icon:GetWidth() or 36
        local h = icon:GetHeight() or 36
        local ox = w * ROT_GLOW_RATIO
        local oy = h * ROT_GLOW_RATIO
        hf.Flipbook:ClearAllPoints()
        hf.Flipbook:SetPoint("TOPLEFT", icon, "TOPLEFT", -ox, oy)
        hf.Flipbook:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", ox, -oy)
    end
    hf:Show()
    if hf.Flipbook and hf.Flipbook.Anim then
        hf.Flipbook.Anim:Play()
        if not ns._rotationInCombat then hf.Flipbook.Anim:Stop() end
    end
end

local function UpdateRotationHighlights()
    if not _rotCVarOn() then
        for icon in pairs(ns._rotationGlowedIcons) do
            _rotHide(icon)
            ns._rotationGlowedIcons[icon] = nil
        end
        return
    end

    local suggestedSpell = C_AssistedCombat and C_AssistedCombat.GetNextCastSpell and C_AssistedCombat.GetNextCastSpell()

    local newSet = {}
    if suggestedSpell then
        -- A CDM icon and GetNextCastSpell can each hold EITHER the base or an override spell id
        -- (e.g. Maul <-> Raze), and which side is which varies by spec. Compare on base ids in BOTH
        -- directions so "icon=base, suggested=override" and "icon=override, suggested=base" both match. Strictly a superset of exact-id match, so anything that highlighted before still does.
        local GetBaseSpell = C_Spell and C_Spell.GetBaseSpell
        local suggestedBase = (GetBaseSpell and GetBaseSpell(suggestedSpell)) or suggestedSpell
        for _, icons in pairs(cdmBarIcons) do
            for _, icon in ipairs(icons) do
                local ifc = _ecmeFC[icon]
                local sid = ifc and ifc.spellID
                if sid and icon:IsShown() then
                    -- Direct/base match first (cheap); only resolve the icon's own base if those
                    -- miss, to keep the common path light. sid > 0: item/trinket icons store -itemID/-13/-14, which must not be fed to GetBaseSpell.
                    local match = (sid == suggestedSpell) or (sid == suggestedBase)
                    if not match and GetBaseSpell and sid > 0 then
                        match = GetBaseSpell(sid) == suggestedBase
                    end
                    if match then
                        _rotShow(icon)
                        newSet[icon] = true
                    end
                end
            end
        end
    end

    for icon in pairs(ns._rotationGlowedIcons) do
        if not newSet[icon] then _rotHide(icon) end
    end
    ns._rotationGlowedIcons = newSet
end
ns.UpdateRotationHighlights = UpdateRotationHighlights

-- One-frame defer after a bar rebuild: icon frames may have just been recycled or re-shown, so we want to re-run the match after the layout settles (dirty-frame pattern).
local _rotDirty = CreateFrame("Frame")
_rotDirty:Hide()
_rotDirty:SetScript("OnUpdate", function(self)
    self:Hide()
    UpdateRotationHighlights()
end)

local function _rotSyncCombat()
    local inCombat = InCombatLockdown() or UnitAffectingCombat("player")
    ns._rotationInCombat = inCombat and true or false
    for icon in pairs(ns._rotationGlowedIcons) do
        local rfc2 = icon and _ecmeFC[icon]
        local hf = rfc2 and rfc2.rotationHighlight
        if hf and hf:IsShown() and hf.Flipbook and hf.Flipbook.Anim then
            if ns._rotationInCombat then
                if not hf.Flipbook.Anim:IsPlaying() then hf.Flipbook.Anim:Play() end
            else
                if hf.Flipbook.Anim:IsPlaying() then hf.Flipbook.Anim:Stop() end
            end
        end
    end
end
ns._syncRotationCombatState = _rotSyncCombat

local function InstallRotationHook()
    if ns._rotationHookInstalled then return end
    ns._rotationHookInstalled = true

    _rotSyncCombat()

    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("AssistedCombatManager.OnAssistedHighlightSpellChange", function()
            UpdateRotationHighlights()
        end, "ECME_CDM_RotationHelper")
        -- Clear highlights if the user flips Blizzard's CVar off at runtime.
        EventRegistry:RegisterCallback("AssistedCombatManager.OnSetUseAssistedHighlight", function()
            UpdateRotationHighlights()
        end, "ECME_CDM_RotationHelper_CVar")
    end

    if AssistedCombatManager and AssistedCombatManager.UpdateAllAssistedHighlightFramesForSpell then
        hooksecurefunc(AssistedCombatManager, "UpdateAllAssistedHighlightFramesForSpell", function()
            UpdateRotationHighlights()
        end)
    end

    -- Re-run after bar rebuilds so the shine follows icon recycling.
    if ns.CollectAndReanchor then
        hooksecurefunc(ns, "CollectAndReanchor", function() _rotDirty:Show() end)
    end

    UpdateRotationHighlights()
end

-- Show Item Count "Out of Combat" mode: re-run the icon restyle for bars using it whenever combat starts or ends (the gate inside the restyle reads the event-tracked combat flag). No-ops instantly when no bar uses the mode.
function ns.RefreshItemCountOOCBars()
    local p = ECME.db and ECME.db.profile
    local bars = p and p.cdmBars and p.cdmBars.bars
    if not bars or not ns.RefreshCDMIconAppearance then return end
    for _, bd in ipairs(bars) do
        if bd.itemCountOOC and bd.key then
            ns.RefreshCDMIconAppearance(bd.key)
        end
    end
end

-------------------------------------------------------------------------------
--  Event-Driven Runtime Maintenance
--
--  This frame owns the non-tick triggers: login/world transitions, spec swaps,
--  talent changes, roster updates, binding changes, proc-glow signals, and
--  combat/visibility state. Most heavy work is deferred into rebuild helpers
--  rather than performed inline in the event callback.
-------------------------------------------------------------------------------
-- Event frame
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("SPELLS_CHANGED")
-- Live override flips (proc-based hero-talent transforms): resolution memos
-- derived from override state go stale the moment this fires.
eventFrame:RegisterEvent("COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
eventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
eventFrame:RegisterEvent("UPDATE_BINDINGS")
eventFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
eventFrame:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
eventFrame:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
eventFrame:RegisterEvent("UPDATE_OVERRIDE_ACTIONBAR")
eventFrame:RegisterEvent("UPDATE_VEHICLE_ACTIONBAR")
-- Hero talent / loadout change events
eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
eventFrame:RegisterEvent("PLAYER_PVP_TALENT_UPDATE")
eventFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
-- Viewer data landing after our init: the injection phase keys on live
-- Blizzard frames (frames as truth), so a build that ran before the viewer
-- populated may have injected a custom racial frame the native viewer now
-- covers. One debounced rebuild re-evaluates; fires rarely (login, and
-- Blizzard-side data refreshes).
eventFrame:RegisterEvent("COOLDOWN_VIEWER_DATA_LOADED")
-- Cinematic/cutscene end: Blizzard restores hidden frames, so re-hide ours
eventFrame:RegisterEvent("CINEMATIC_STOP")
eventFrame:RegisterEvent("STOP_MOVIE")
-- Equipment changes: trinket/weapon swaps update trinket frames and reanchor
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
-- Visibility option events: mounted, target, instance zone changes
eventFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
-- Dragonriding visibility modes: capability edge (mount/dismount/zone) plus
-- the airborne edge (takeoff/landing while staying mounted; probed at load
-- in EllesmereUI_Visibility.lua -- absent = the checklist items lock).
eventFrame:RegisterEvent("PLAYER_CAN_GLIDE_CHANGED")
if EllesmereUI._hasGlidingEvent then
    eventFrame:RegisterEvent("PLAYER_IS_GLIDING_CHANGED")
end
-- Druid travel/flight/aquatic form needs an explicit re-check for the
-- visHideMounted option. PLAYER_MOUNT_DISPLAY_CHANGED only fires for real
-- mounts, and the viewer hooks rebuild icon content on shapeshift but
-- don't re-run bar-level visibility. Only register for druids -- non-druid
-- classes have no mount-like shapeshift forms, and druid combat shifts
-- (Bear/Cat) would otherwise trigger unnecessary visibility recomputes.
local _, _playerClassCDM = UnitClass("player")
if _playerClassCDM == "DRUID" then
    eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
end

-- Debounce token for talent-change rebuilds: rapid talent clicks collapse
-- into a single deferred rebuild rather than firing once per click.
local _talentRebuildToken = 0

local function ScheduleTalentRebuild()
    _talentRebuildToken = _talentRebuildToken + 1
    local token = _talentRebuildToken
    C_Timer.After(0.5, function()
        if token ~= _talentRebuildToken then return end  -- superseded
        -- Wipe per-spell caches that may reference stale override IDs or stale charge
        -- data from spells that changed with the talent swap. Also wipe the persisted
        -- DB entries so CacheMultiChargeSpell re-detects from live API rather than
        -- reading a stale false entry. Skip during combat: actual talent changes are
        -- combat-locked, so these events only fire mid-combat from hero talent procs
        -- (e.g. Celestial Infusion). Wiping here would clear charge data for all spells
        -- with no way to re-detect it until the next out-of-combat cache rebuild.
        if not InCombatLockdown() then
            wipe(_multiChargeSpells)
            wipe(_maxChargeCount)
            local db = ECME.db
            if db and db.sv and db.sv.multiChargeSpells then
                wipe(db.sv.multiChargeSpells)
            end
        end
        -- Rebuild the cdID route map against the new talent set. The stored
        -- assignedSpells is left untouched (it's pure user intent); the route map is
        -- the live source of truth for which frame renders on which bar. A full CDM
        -- rebuild + reanchor below picks up the new routing.
        if ns.RebuildSpellRouteMap then ns.RebuildSpellRouteMap() end
        -- The placeholder icon bridge reads the spellbook, and a talent swap is
        -- exactly what changes which form a name resolves to.
        if ns.WipeCdmBookNameCache then ns.WipeCdmBookNameCache() end
        -- Clear cached viewer child info so the next tick re-reads from API
        -- (overrideSpellID may have changed with the new talent set)
        for _, vname in ipairs(_cdmViewerNames) do
            local vf = _G[vname]
            if vf and vf:GetNumChildren() > 0 then
                local children = { vf:GetChildren() }
                for ci = 1, #children do
                    local ch = children[ci]
                    if ch then
                        local chfc = _ecmeFC[ch]
                        if chfc then
                            chfc.resolvedSid = nil
                            chfc.baseSpellID = nil
                            chfc.overrideSid = nil
                            chfc.cachedCdID = nil
                            chfc.isChargeSpell = nil
                            chfc.maxCharges = nil
                        end
                    end
                end
            end
        end
        ns._cdmUnresolvedRetries = 0  -- fresh window; see FullCDMRebuild
        -- Rebuild keybind cache (talent swap may change action slot contents)
        UpdateCDMKeybinds()
        -- Invalidate TBB frame cache + spell caches, then reanchor so
        -- overlays re-evaluate against the new viewer pool state.
        if ns.InvalidateTBBFrameCache then ns.InvalidateTBBFrameCache() end
        if ns.MarkCDMSpellCacheDirty then ns.MarkCDMSpellCacheDirty() end
        if ns.QueueReanchor then ns.QueueReanchor() end
    end)
end

local _rosterRebuildPending = false
local function ScheduleRosterRebuild()
    -- Roster changes (promote, join, leave) don't change spells or bar
    -- routing. Only party frame anchoring needs a refresh. A full
    -- BuildAllCDMBars was causing massive single-frame CPU spikes.
    if EllesmereUI and EllesmereUI.InvalidateFrameCache then
        EllesmereUI.InvalidateFrameCache()
    end
    if InCombatLockdown() then
        _rosterRebuildPending = true
        return
    end
    -- Lightweight: just reanchor bars that depend on party frames
    if ns.QueueReanchor then ns.QueueReanchor() end
end

eventFrame:SetScript("OnEvent", function(_, event, unit, updateInfo, arg3)
    if not ECME.db then return end
    if event == "PLAYER_LOGOUT" then
        ns.SaveCachedBarSizes()
        return
    end
    if event == "COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED" then
        -- Bump-only: painting is driven by the cooldown/desat hooks, which re-resolve on their next fire. No repaint request from here.
        ns._cdmResGen = ns._cdmResGen + 1
        return
    end
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        return
    end
    if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" or event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
        OnProcGlowEvent(event, unit)  -- unit = spellID (first arg after event)
        return
    end
    if event == "UPDATE_BINDINGS" or event == "ACTIONBAR_SLOT_CHANGED"
       or event == "ACTIONBAR_PAGE_CHANGED" or event == "UPDATE_BONUS_ACTIONBAR"
       or event == "UPDATE_OVERRIDE_ACTIONBAR" or event == "UPDATE_VEHICLE_ACTIONBAR" then
        -- A page/bonus/override/vehicle swap only changes which page is
        -- active, not the contents of the slots the stable scan reads -- so it
        -- cannot change the cache. Drop it, and with it the rebuild storm a
        -- stealthing rogue or shapeshifting druid used to cause. Only
        -- UPDATE_BINDINGS and ACTIONBAR_SLOT_CHANGED are real edits.
        --
        -- Exception, as insurance: let the first sighting of each bonus bar
        -- through, in case that form's slots (73-132) are only populated when
        -- the player first shifts into it rather than at login.
        if event ~= "UPDATE_BINDINGS" and event ~= "ACTIONBAR_SLOT_CHANGED"
           and ns.CDMStableKeybindsEnabled and ns.CDMStableKeybindsEnabled() then
            local firstSighting = false
            if event == "UPDATE_BONUS_ACTIONBAR" then
                local offset = GetBonusBarOffset and GetBonusBarOffset() or 0
                if offset > 0 and not _bonusScanSeen[offset] then
                    _bonusScanSeen[offset] = true
                    firstSighting = true
                end
            end
            if not firstSighting then return end
        end
        -- Debounce: one-button rotation addons fire ACTIONBAR_SLOT_CHANGED on every GCD. Cancel the previous timer so rapid-fire events coalesce into a single update 0.5s after the last event.
        if _keybindDebounceTimer then _keybindDebounceTimer:Cancel() end
        _keybindDebounceTimer = C_Timer.NewTimer(0.5, function()
            _keybindDebounceTimer = nil
            UpdateCDMKeybinds()
        end)
        return
    end
    if event == "COOLDOWN_VIEWER_DATA_LOADED" then
        -- Native viewer data arrived (usually after login init): re-evaluate the
        -- frames-as-truth injection decisions against the now-live frame set.
        -- Rides the same debounced rebuild as talent changes; the reanchor sweep
        -- hides any injected racial frame the native viewer now covers. The spell
        -- picker's learned-set cache refreshes too (category sets just changed),
        -- and the reseed session stamps clear so base-bar materialization re-runs
        -- against the COMPLETE icon set (an init-time reseed may have seen a
        -- partial viewer; the racial-family guard keeps the re-run from minting
        -- a second racial slot).
        if ns.MarkCDMSpellCacheDirty then ns.MarkCDMSpellCacheDirty() end
        if ns._reseededSpecsSession then wipe(ns._reseededSpecsSession) end
        ScheduleTalentRebuild()
        return
    end
    if event == "TRAIT_CONFIG_UPDATED" or event == "PLAYER_TALENT_UPDATE" or event == "ACTIVE_TALENT_GROUP_CHANGED"
        or event == "PLAYER_PVP_TALENT_UPDATE" then
        -- Hero talent, loadout, or PvP talent context change -- debounced rebuild. PvP talents
        -- (de)activating on arena enter/exit makes Blizzard re-evaluate the viewer's tracked
        -- cooldown set; without a rebuild the new pool frames are never re-claimed and the
        -- unclaimed-frame cleanup blanks them (arena-exit empty-CDM bug). The spell set may have changed: let the post-rebuild reanchor re-run the automatic base-bar materialization for this spec.
        if ns._reseededSpecsSession then wipe(ns._reseededSpecsSession) end
        -- Drop the spellbook name map NOW, not only in the debounced rebuild. It answers "which
        -- form does the player have", which is exactly what just changed, and anything repainting
        -- inside the debounce window would otherwise resolve against the pre-swap book. The rebuild
        -- wipes it again, which still matters: this early rebuild can read a book the client has not finished updating, and that second wipe corrects it.
        if ns.WipeCdmBookNameCache then ns.WipeCdmBookNameCache() end
        ScheduleTalentRebuild()
        return
    end
    if event == "GROUP_ROSTER_UPDATE" then
        ScheduleRosterRebuild()
        _CDMApplyVisibility()
        return
    end
    if event == "CINEMATIC_STOP" or event == "STOP_MOVIE" then
        -- Blizzard restores frame positions/alpha after cinematics end. Re-hide immediately so the Blizzard CDM doesn't reappear.
        local p = ECME.db and ECME.db.profile
        if p and p.cdmBars and p.cdmBars.hideBlizzard then
            C_Timer.After(0, function()
                HideBlizzardCDM()
                if p.cdmBars.useBlizzardBuffBars then
                    RestoreBlizzardBuffFrame()
                end
            end)
        end
        return
    end
    if event == "PLAYER_EQUIPMENT_CHANGED" then
        if InCombatLockdown() then return end
        BuildAllCDMBars()
        if ns.QueueReanchor then ns.QueueReanchor() end
        return
    end
    if event == "PLAYER_TARGET_CHANGED" then
        _CDMApplyVisibility()
        return
    end
    if event == "PLAYER_MOUNT_DISPLAY_CHANGED"
        or event == "PLAYER_CAN_GLIDE_CHANGED"
        or event == "PLAYER_IS_GLIDING_CHANGED" then
        -- Defer to a clean execution context: the event handler chain can carry taint from other
        -- addons, which propagates into LayoutCDMBar when a bar transitions from hidden to visible (visHideMounted). The dragonriding edges take the same deferred path for the same reason (mid-flight unhide runs LayoutCDMBar).
        C_Timer.After(0, _CDMApplyVisibility)
        return
    end
    if event == "UPDATE_SHAPESHIFT_FORM" then
        -- Bail fast if no bar actually uses visHideMounted: druids shift constantly in combat (Bear/Cat) and we don't want to re-run the visibility pipeline for nothing.
        local p = ECME.db and ECME.db.profile
        local bars = p and p.cdmBars and p.cdmBars.bars
        if not bars then return end
        local anyMountedOpt = false
        for _, bd in ipairs(bars) do
            if bd.visHideMounted then anyMountedOpt = true; break end
        end
        if not anyMountedOpt then return end
        -- Defer one frame: the Travel Form aura is applied slightly after UPDATE_SHAPESHIFT_FORM fires, so IsPlayerMountedLike's aura check would miss it on the immediate pass.
        C_Timer.After(0, _CDMApplyVisibility)
        return
    end
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" or event == "ZONE_CHANGED_NEW_AREA" then
        if ns._syncRotationCombatState then ns._syncRotationCombatState() end
        if event == "PLAYER_REGEN_DISABLED" then
            _inCombat = true
            _CDMApplyVisibility()
            ns.RefreshItemCountOOCBars()
        elseif event == "PLAYER_REGEN_ENABLED" then
            -- Buffer combat exit: brief out-of-combat blips (mob dies, re-aggro) shouldn't flash visibility changes.
            C_Timer.After(0.1, function()
                if not InCombatLockdown() then
                    _inCombat = false
                    _CDMApplyVisibility()
                    ns.RefreshItemCountOOCBars()
                end
            end)
        else
            -- Zone transition: re-apply visibility (mounted state etc. may have changed). No rebuild or reanchor -- SPELLS_CHANGED handles the rebuild if the spec changed.
            _CDMApplyVisibility()
        end
        -- Flush deferred TBB rebuild that was queued during combat
        if event == "PLAYER_REGEN_ENABLED" and ns.IsTBBRebuildPending and ns.IsTBBRebuildPending() then
            if ns.BuildTrackedBuffBars then ns.BuildTrackedBuffBars() end
        end
        -- Flush a secondary buff-viewer park that was blocked during combat
        if event == "PLAYER_REGEN_ENABLED" and ns._secondaryParkPending then
            ns._secondaryParkPending = nil
            local sv = _G[BLIZZ_CDM_FRAMES_SECONDARY.buffs]
            local svc = sv and _ecmeFC[sv]
            if svc and svc.hidden then ns.ParkSecondaryBuffViewer(sv) end
        end
        -- Flush deferred roster reanchor that was blocked during combat
        if event == "PLAYER_REGEN_ENABLED" and _rosterRebuildPending then
            _rosterRebuildPending = false
            if ns.QueueReanchor then ns.QueueReanchor() end
        end
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        _inCombat = InCombatLockdown and InCombatLockdown() or false
        -- PvP instance transition backstop: entering or leaving a PvP instance rebuilds viewer pools (PvP talents activate/deactivate). Rebuild + reanchor so the new pool frames are claimed.
        local _, instType = IsInInstance()
        local wasPvP = ns._cdmWasInPvP
        local isPvP = (instType == "arena" or instType == "pvp")
        if wasPvP and not isPvP then
            ScheduleTalentRebuild()
        end
        ns._cdmWasInPvP = isPvP or nil
        if isPvP and not wasPvP then
            if ns.QueueReanchor then ns.QueueReanchor() end
        end
        -- Install rotation helper hook after CDM frames have been built
        C_Timer.After(1, function()
            InstallRotationHook()
        end)
        -- Safety: re-apply visibility after loading screen settles. Two passes to catch both fast and late viewer pool rebuilds.
        C_Timer.After(1.5, _CDMApplyVisibility)
        C_Timer.After(3, _CDMApplyVisibility)
    end
    if event == "SPELLS_CHANGED" then
        CheckSpecChange()
        ns._spellsReadyForApply = true
        -- Spell data churn invalidates cooldownID resolution memos.
        ns._cdmResGen = ns._cdmResGen + 1
        -- Engine spell data changed (spec-swap churn tail, druid form swap, talent/spell overrides).
        -- The variant-expanded diversion maps and the memoized cdID->bar routes were derived from
        -- the PREVIOUS spell state; a route resolved mid-churn against transitional cooldown info
        -- is cached until the next map rebuild and pins a ghosted/custom spell onto the wrong
        -- visible bar. Re-derive from current truth and re-claim -- the LAST fire of any churn
        -- burst always leaves the final state correct, with no settle timers. (CheckSpecChange's reconcile also rebuilds the map, but a same-key fire means the data changed again after that rebuild.)
        if ns.RebuildSpellRouteMap then ns.RebuildSpellRouteMap() end
        -- The tracked-buff catalog can change in the same churn, and the login-pass reconcile may
        -- have consumed its dirty flag against a still-empty viewer pool (the flag is cleared
        -- before the call and an empty catalog no-ops). Re-arm so the queued reanchor reconciles the buff display order against the populated catalog.
        ns._cdmBuffOrderDirty = true
        if ns.QueueReanchor then ns.QueueReanchor() end
        return
    end
    if event == "PLAYER_SPECIALIZATION_CHANGED" and unit == "player" then
        -- Non-rebuild work only. The actual spec change rebuild is driven by SPELLS_CHANGED above
        -- (which fires for both manual and auto swaps). This handler just invalidates caches that need immediate clearing.
        if EllesmereUI and EllesmereUI.InvalidateFrameCache then
            EllesmereUI.InvalidateFrameCache()
        end
    end
    RequestUpdate()
end)

-------------------------------------------------------------------------------
--  Slash commands
-------------------------------------------------------------------------------
SLASH_ECME1 = "/ecme"
SLASH_ECME2 = "/cdmeffects"
SLASH_ECME3 = "/ecdm"
SlashCmdList.ECME = function(msg)
    if InCombatLockdown and InCombatLockdown() then return end
    if EllesmereUI and EllesmereUI.ShowModule then
        EllesmereUI:ShowModule("EllesmereUICooldownManager")
    end
end


