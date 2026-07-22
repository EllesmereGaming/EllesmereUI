-------------------------------------------------------------------------------
--  EllesmereUICooldownManager.lua
--  CDM Look Customization and Cooldown Display
--  Mirrors Blizzard CDM bars with custom styling, cooldown swipes,
--  desaturation, active state animations, and per-spec profiles.
--  Does NOT parse secret values works around restricted APIs.
-------------------------------------------------------------------------------
local _, ns = ...

-- EMERGENCY CONFLICT GUARD: Ayije_CDM hooks the exact same Blizzard frames we do.
-- Running both together crashes the client on the loading screen. Detect Ayije_CDM
-- and no-op our entire module so the user can at least log in.
do
    local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    if isLoaded and isLoaded("Ayije_CDM") then
        -- Flag the generic conflict checker to skip its Ayije_CDM entry so
        -- our crash-specific popup (with Disable & Reload) takes priority.
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
            -- Swallow Escape so the user can't dismiss without clicking the button.
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

        local warnFrame = CreateFrame("Frame")
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

-- Snap a value to a whole number of physical pixels at the bar's effective scale.
-- Uses the same approach as the border system: convert to physical pixels,
-- round to nearest integer, convert back.
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
ns.CDM_SHAPE_MASKS   = CDM_SHAPES.masks
ns.CDM_SHAPE_BORDERS = CDM_SHAPES.borders
ns.CDM_SHAPE_ZOOM_DEFAULTS = CDM_SHAPES.zoomDefaults
ns.CDM_SHAPE_EDGE_SCALES = CDM_SHAPES.edgeScales
-- Forward declarations for glow helpers (defined later, used by consolidated helpers)
local StartNativeGlow, StopNativeGlow

-- Keybind cache: built once out-of-combat, looked up per tick
local _cdmKeybindCache       = {}   -- [spellID] -> formatted key string
local _cdmKeybindFromMacro   = {}   -- [key] -> true if the cached bind came from a macro
local _keybindCacheReady     = false  -- true after first successful build
local _keybindDebounceTimer  = nil   -- cancellable timer for debounced keybind updates

-- Combat state tracked via events (InCombatLockdown() can lag behind PLAYER_REGEN_DISABLED)
local _inCombat = false

-- Resting alpha for a bar's icons: the out-of-combat fade value when enabled
-- and out of combat, otherwise the bar's opacity. Callers restoring an icon's
-- alpha go through this so the fade survives cd-state and buff re-renders.
local function EffectiveBarAlpha(barData)
    if barData and barData.oocFadeEnabled and not _inCombat then
        return barData.oocFadeAlpha or 0.5
    end
    return (barData and barData.barOpacity) or 1
end
ns.EffectiveBarAlpha = EffectiveBarAlpha

-- Vehicle/petbattle state proxy. Created once in CDMFinishSetup; drives
-- _CDMApplyVisibility on state change so CDM bars hide while in vehicle UI.
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

-- External frame cache: stores all addon data keyed by Blizzard frame references
-- instead of writing custom keys onto Blizzard's secure frame tables (which taints them).
-- Weak keys so entries are collected when frames are recycled.
local _ecmeFC = setmetatable({}, { __mode = "k" })
local function FC(f) local c = _ecmeFC[f]; if not c then c = {}; _ecmeFC[f] = c end; return c end

-- Separate weak-keyed table for SetFrameClickThrough mouse-state tracking.
-- This recurses into Blizzard pool icons parented to CDM bars, so it must
-- use an external table rather than writing onto the frames directly.
local _cdmMouseState = setmetatable({}, { __mode = "k" })

-- Access decoration data stored externally by EllesmereUICdmHooks.lua
-- Populated at runtime (hooks file loads after this file)
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
    -- Wing Buffet (357214) is available to every Dracthyr class, but
    -- Evokers already have it tracked by Blizzard's CDM category, so
    -- gate the custom-racial entry off for Evokers to avoid duplicate
    -- injection. Tail Swipe (368970) is Evoker-only and also in CDM,
    -- so it is omitted from this list entirely.
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
-- Exposed for the RPT sync: it must recognize the racial slot for ANY race, not
-- just the current character's, so a profile shared across different-race
-- characters syncs the racial slot too (NormalizeRacialAssignments then remaps
-- the stored ID to each character's own racial when the spec builds).
ns.ALL_RACIAL_SPELLS = ALL_RACIAL_SPELLS

local _myRacials = {}
local _myRacialsSet = {}
-- The single racial actually in this character's spellbook. The spell picker
-- shows one generic "Racial" entry that adds this ID; NormalizeRacialAssignments
-- rewrites any other race's stored racial to it, so a shared profile's racial
-- slot follows each character's race automatically.
local _activeRacialSpellID = nil

-- Resolve the in-spellbook racial. Races whose entries are class-variant
-- spell IDs (Blood Fury, Arcane Torrent, Gift of the Naaru) only have one
-- in-book; pick it. Re-run at build time as well as OnEnable, because the
-- spellbook may not be populated yet during early-login OnEnable.
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


-- Custom Aura Bar presets (potions with hardcoded durations).
-- Detection: SPELL_UPDATE_COOLDOWN (spell goes on CD = just used).
-- Display: reverse cooldown swipe for the duration.
-- Bloodlust/Heroism is the exception below: it is debuff-driven (see the TBB
-- tick special-case for popularKey == "bloodlust") rather than cooldown-
-- detected, because the lust buff is cast by others and is secret. It starts a
-- 40s bar off the player's Sated/Exhaustion debuff edge. Time Spiral is likewise
-- event-driven (glow-armed, see the TBB tick special-case for popularKey ==
-- "timespiral"); warlock pets stay out (no usable detection).
local BUFF_BAR_PRESETS = {
    {
        -- Faction label: Horde = Bloodlust (2825), Alliance = Heroism (32182).
        key      = "bloodlust",
        name     = (UnitFactionGroup("player") == "Horde") and "Bloodlust" or "Heroism",
        icon     = (UnitFactionGroup("player") == "Horde")
                       and "Interface\\Icons\\spell_nature_bloodlust"
                       or  "Interface\\Icons\\ability_shaman_heroism",
        spellIDs = { (UnitFactionGroup("player") == "Horde") and 2825 or 32182 },
        duration = 40,
        tbbOnly  = true,  -- not a cooldown-usable preset (kept out of the CD/utility picker)
        customAuraToo = true,  -- but allowed on Custom Auras (icon) bars; debuff-driven 40s window
    },
    {
        -- Time Spiral "Free Move" proc: glow-driven, self-timed 10s window (see
        -- the TBB tick special-case for popularKey == "timespiral"). Like
        -- Bloodlust it is event-armed (a spell-activation glow on the player's
        -- class movement ability), not cooldown-detected.
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

-- Item presets for CD/utility bars (potions that track cooldowns)
local CDM_ITEM_PRESETS = {
    {
        key      = "lights_potential",
        name     = "Light's Potential",
        icon     = 7548911,
        itemID   = 241308,
        altItemIDs = { 245898, 245897, 241309 },
    },
    {
        key      = "potion_recklessness",
        name     = "Potion of Recklessness",
        icon     = 7548916,
        itemID   = 241288,
        altItemIDs = { 241289, 245902, 245903 },
    },
    {
        key      = "silvermoon_health",
        name     = "Silvermoon Health Potion",
        icon     = 7548909,
        itemID   = 241304,
        altItemIDs = { 241305 },
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
                    showCooldownText = true, showItemCount = true, showTooltip = false, showKeybind = false,
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
                    showCooldownText = true, showItemCount = true, showTooltip = false, showKeybind = false,
                    keybindSize = 10, keybindOffsetX = 2, keybindOffsetY = -2, keybindAlign = "left",
                    keybindR = 1, keybindG = 1, keybindB = 1, keybindA = 0.9,
                },
                {
                    key = "buffs", name = "Buffs", enabled = true,
                    barType = "buffs",
                    -- Always Show Buffs (per-bar): show a greyed placeholder icon
                    -- for each inactive tracked buff. desaturateInactiveBuffs is
                    -- the inline cog. Off by default for new installs; the
                    -- migration turns it on for users who had the old global on.
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
                    showCooldownText = true, showItemCount = true, showTooltip = false, showKeybind = false,
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
--  Lives at EllesmereUIDB.spellAssignments. The spell/bar-content data is
--  per-profile: spellAssignments.profiles[name].specProfiles[specKey]. It sits
--  at the top level (NOT inside the profile blob), so it never travels with
--  profile export or module sync, but it IS forked/dropped/moved alongside the
--  profile itself (copy/delete/rename in EllesmereUI_Profiles.lua). The active
--  profile's bucket is resolved live via ns.GetActiveSpecProfiles().
--  Consolidated into a single local table to stay within Lua 5.1's 200 local
--  variable limit for the main chunk.
-------------------------------------------------------------------------------
local SpellStore = {}

function SpellStore.Get()
    if not EllesmereUIDB then EllesmereUIDB = {} end
    if not EllesmereUIDB.spellAssignments then
        EllesmereUIDB.spellAssignments = { profiles = {} }
    end
    return EllesmereUIDB.spellAssignments
end

-- Active profile name for the per-profile spell store. Read live so a profile
-- switch auto-follows on the next CDM rebuild with no repoint step.
function ns.GetActiveProfileName()
    return (EllesmereUIDB and EllesmereUIDB.activeProfile) or "Default"
end

-- Per-profile spell store. Spell/bar-content data is owned by each profile, so
-- copying a profile forks its CDM and deleting a bar never crosses profiles. It
-- lives at spellAssignments.profiles[name].specProfiles -- OUTSIDE the profile
-- blob and the export payload, so module sync and profile export never carry it
-- (both operate on the profile's addons blob, not this store).
--
-- A one-time migration (cdm_per_profile_spell_store_v1) seeds every existing
-- profile from the legacy shared spellAssignments.specProfiles. Until that
-- completes (_perProfileSeeded), fork the legacy data on first access so a
-- profile never reads empty during the early window (e.g. if the migration
-- body errored and is retrying next session).
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

-- Cross-spec "broadcast" set for Tracking Bars: a lookup of bar identities (preset
-- key or custom spellID) the user has pushed to every spec via "Add Bar to All
-- Specs". Lives on the profile bucket OUTSIDE specProfiles, so it persists across
-- spec switches/reloads and forks with the profile (same as specProfiles). Drives
-- the Add/Remove toggle label on the Tracking Bars page.
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

-- Smooth-fill switches for Tracking Bars (Bar Layout > Smooth Bars). ONE
-- setting for ALL bars in EVERY spec: lives on the profile bucket OUTSIDE
-- specProfiles (same home as the broadcast set), so it applies across spec
-- switches and forks with the profile. Keys: buffs / cooldowns; absent
-- buffs reads ENABLED, absent cooldowns reads DISABLED (the defaults).
function ns.GetTBBSmoothSettings()
    local name = ns.GetActiveProfileName()
    ns.GetSpecProfilesForProfile(name)
    local sa = SpellStore.Get()
    local bucket = sa.profiles and sa.profiles[name]
    if not bucket then return nil end
    if not bucket.tbbSmooth then bucket.tbbSmooth = {} end
    return bucket.tbbSmooth
end

-- Active SPELL LAYOUT name. Layouts are a shared, account-wide library
-- (spellAssignments.profiles[name] = the layout buckets) with a SINGLE
-- account-wide active pointer (spellAssignments.activeLayout). Spell layouts are
-- DETACHED from EUI profiles: a profile only changes the active layout if it has
-- an opt-in binding (spellAssignments.profileBindings) applied via
-- ns.ApplyProfileBinding on profile load. Self-heals to a valid layout.
function ns.GetActiveLayoutName()
    local sa = SpellStore.Get()
    if not sa.profiles then sa.profiles = {} end
    local name = sa.activeLayout
    if type(name) ~= "string" or type(sa.profiles[name]) ~= "table" then
        -- Self-heal: prefer a layout named after the current profile (legacy seed
        -- naming), else any existing layout, else the profile name (creates it).
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

-- specProfiles table for the active PROFILE (the live CDM bucket). Spell content
-- is per-EUI-profile and switches with the profile -- no account-wide layout
-- pointer mediates rendering.
function ns.GetActiveSpecProfiles()
    return ns.GetSpecProfilesForProfile(ns.GetActiveProfileName())
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
function ns.GetBarSpellData(barKey)
    local specKey = ns.GetActiveSpecKey()
    if not specKey or specKey == "0" then return nil end
    local sp = SpellStore.GetSpecProfiles()
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
--  Per-spell icon settings live in FAMILY stores on the spec profile (siblings
--  of barSpells), keyed by spellID -- NOT nested under a bar. Moving a spell to
--  another bar in the same family keeps its settings automatically:
--      specProf.spellSettingsCD[sid]   -- cooldown/utility family
--      specProf.spellSettingsBuff[sid] -- buff family
--
--  Two bar-level tiers sit below the per-spell entries ("Apply to Bar"):
--      barSpells[barKey].barSettings   -- this bar, this spec
--      bd.barSpellSettings             -- this bar, EVERY spec (profile-level
--                                         bar definition, so specs with no CDM
--                                         data yet inherit it too)
--
--  Effective value per key: spell entry > barSettings > barSpellSettings >
--  defaults. The renderer resolves the chain via metatable __index links that
--  ResolveSpellSettings re-asserts lazily on every lookup (self-healing across
--  moves / spec swaps / profile swaps; metatables are never serialized).
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
--  Hosted-buff markers
--
--  A buff placed on a CD/utility bar ("hosted") gets its OWN assignedSpells
--  entry, encoded as a negative marker so it can never collide with the same
--  spell's cooldown entry: one spellID can exist in BOTH the Essential/Utility
--  catalog and the Tracked Buffs catalog (e.g. Divine Shield 642). The marker
--  gives the hosted buff an independent slot -- its own position, its own
--  remove/move, its own per-icon settings -- even when the cooldown form of
--  the same spell sits on the same bar.
--
--  Encoding: -(BASE + spellID). BASE sits far below the item-preset range
--  (<= -100, negated itemIDs) and the trinket slots (-13/-14), so every
--  existing negative-id branch keeps working; anything <= -BASE is a marker.
-------------------------------------------------------------------------------
ns.HOSTED_BUFF_MARKER_BASE = 2000000000

-------------------------------------------------------------------------------
--  Equipment-slot entries. A bar entry can store a negated INVENTORY SLOT id
--  (-1..-19) to track whatever item is equipped in that slot -- the trinket
--  slots (-13/-14) have always worked this way; user-added slots (belt -6,
--  cloak -15, ...) reuse the same frame/update machinery. The range is safe:
--  item presets are <= -100 and the custom-item popup rejects IDs below 100,
--  so nothing else can occupy -1..-19.
--
--  Localized display names, keyed by slot id. Slot 18 (obsolete ranged) is
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

-- Decode a hosted-buff marker to its spellID; nil for anything else. Bounded
-- above by CD_CLAIM_MARKER_BASE so a cd-claim marker (below) never misdecodes
-- as a hosted-buff spellID.
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
--  Cd-claim markers: a collided buff (two Blizzard buff-viewer slots sharing
--  one canonical spellID, e.g. Diabolist Demonic Art vs Diabolic Ritual)
--  cannot be told apart by spellID, so a claimed slot is tracked by its
--  cooldownID instead. Same marker-in-assignedSpells pattern as hosted-buff
--  markers above, so add/remove/drag/reorder all work through the existing
--  index-based assignedSpells machinery for free.
--
--  Encoding: -(BASE + cooldownID). BASE sits beyond HOSTED_BUFF_MARKER_BASE
--  (+ the max plausible spellID), so every existing "is this a hosted-buff
--  marker?" check (which bounds itself at HOSTED_BUFF_MARKER_BASE) already
--  excludes cd-claim markers too, with no changes needed at those sites.
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

-- Collect every cd-claim marker in a bar's assignedSpells as a set
-- ({[cdID]=true,...}), or nil if none. Drop-in replacement for reading the
-- old sd.assignedBuffCdIDs side-table directly.
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

-- Family store key for a bar ("spellSettingsBuff" for buff-family bars,
-- "spellSettingsCD" for everything else, including the ghost CD bar).
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

-- Family per-spell store for the ACTIVE spec, resolved from a bar.
function ns.GetSpellSettingsStore(barKeyOrBd, create)
    local specKey = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
    if not specKey or specKey == "0" then return nil end
    local sp = SpellStore.GetSpecProfiles()
    if not sp then return nil end
    local prof = sp[specKey]
    if not prof then
        if not create then return nil end
        prof = { barSpells = {} }
        sp[specKey] = prof
    end
    return ns.GetSpellSettingsStoreForProf(prof, ns.SettingsFamilyKey(barKeyOrBd), create)
end

-- Chain child.__index -> parent (or clear the link when parent is nil).
-- Reused by the renderer + options so every read of a per-spell table falls
-- through to the bar tiers per KEY. Cheap: one getmetatable + compare.
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

-- Bar-tier chain head for a bar: barSettings (chained to the profile-level
-- bd.barSpellSettings) when present, else bd.barSpellSettings, else nil.
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

-- True when any per-icon settings could apply on this bar: the family store
-- has ANY entry (over-approximate -- entries are keyed by spell, not bar) or
-- either bar tier is non-empty. Used to gate "re-resolve appearance" passes.
function ns.BarHasAnySpellSettings(barKey, sd)
    local st = ns.GetSpellSettingsStore(barKey)
    if st and next(st) ~= nil then return true end
    sd = sd or ns.GetBarSpellData(barKey)
    if sd then
        if sd.barSettings and next(sd.barSettings) ~= nil then return true end
        -- Legacy shape safety net (pre-migration data).
        if sd.spellSettings and next(sd.spellSettings) ~= nil then return true end
    end
    local bd = ns.barDataByKey and ns.barDataByKey[barKey]
    if bd and bd.barSpellSettings and next(bd.barSpellSettings) ~= nil then return true end
    return false
end

-- Iterate every SAVED settings block that can hold per-spell setting keys:
-- all specs' family-store entries + per-bar barSettings, plus the active
-- profile's bar-level barSpellSettings. fn(ss) returning true stops the walk.
-- Used by the login gate scans ("does anyone use feature X anywhere").
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
                        -- Legacy shape safety net: pre-migration data that has
                        -- not been transformed yet (should not happen -- the
                        -- migration runs before this addon loads).
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

-- One-time copy of a user CUSTOM spell/buff (customSpellIDs-tagged) plus its
-- per-spell settings onto the SAME bar in other specs of the active profile.
-- Bar definitions are profile-level, so the bar exists in every spec. A target
-- spec that already has the spell on ANY bar is skipped whole (never duplicates
-- within a spec). Custom Active State is NOT copied here -- it lives in the
-- profile-level customActiveStates store and is already shared across specs.
-- Returns the number of specs actually copied to.
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
                    -- pairs()-based DeepCopy takes OWN keys only (no metatable
                    -- __index follow), so this is the spell's own per-spell
                    -- settings -- not values inherited from bar tiers. The copy
                    -- is unchained; the renderer re-chains it to the target bar's
                    -- tiers on first resolve.
                    local store = prof[famKey]
                    if not store then store = {}; prof[famKey] = store end
                    if store[spellID] == nil then
                        store[spellID] = DeepCopy(srcSettings)
                    end
                end
                copied = copied + 1
            end
        end
    end
    return copied
end

-- Set of OTHER specs (this class, active profile) that currently have the spell
-- on ANY bar. Drives the per-spell menu's Copy/Remove label + the Remove picker's
-- pre-check. Excludes the active spec (that's where the menu is opened from).
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

-- Inverse of CopyCustomSpellToSpecs: remove the spell + its per-spell settings
-- from the picked specs (wherever it lives -- scans every bar). Never touches the
-- active spec or the profile-level customActiveState (that stays as long as the
-- spell exists on ANY spec, incl. the current one). Returns the count removed.
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
                    -- Drop the per-spell settings entry (keyed by spellID, so
                    -- clearing both family stores is safe -- only one holds it).
                    if prof.spellSettingsCD then prof.spellSettingsCD[spellID] = nil end
                    if prof.spellSettingsBuff then prof.spellSettingsBuff[spellID] = nil end
                    removed = removed + 1
                end
            end
        end
    end
    return removed
end

-- Custom Active State store. Keyed by spellID at the PROFILE level (shared
-- across every bar and spec in this profile) so a preset's custom active state
-- travels with the spell wherever it is placed -- no re-adding. The settings key
-- matches assignedSpells: positive = racial / custom spell; negative = item /
-- trinket-slot preset. Entry shape: { duration, activeSwipeMode,
-- activeSwipeClassColor, activeSwipeR/G/B/A, activeGlow, glowColor, glowColorR/G/B }.
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

-- Map an icon's identity token to its SETTINGS key. Equipment SLOTS (trinkets
-- -13/-14 and user-added slots) key their per-spell settings by the EQUIPPED
-- item (-itemID) so each item tracks separately -- bar allocation is untouched
-- (still slot-based). Everything else (item presets, racials, custom spells)
-- keys by its own token.
function ns.ResolveCustomActiveKey(frameKey)
    local slot = ns.SlotIDFromKey(frameKey)
    if slot then
        local itemID = GetInventoryItemID("player", slot)
        if itemID then return -itemID end
    end
    return frameKey
end

-- EFFECTIVE Custom Active State for an icon identity token -- READ paths only.
-- Non-slot tokens resolve their own entry directly. Equipment SLOTS (trinkets
-- -13/-14 and user-added slots) resolve the EQUIPPED item's own entry (per-item
-- settings, the key the per-spell menu writes via ResolveCustomActiveKey)
-- chained per-key over the SLOT entry -- the "Apply to Bar" stamp, slot-keyed
-- so ONE bar application covers whatever item is equipped, without minting an
-- entry per item. The chain is re-asserted lazily on every resolve (metatables
-- never serialize), mirroring ResolveSpellSettings. An explicit false own value
-- is render-equivalent to nil but BLOCKS the slot value showing through (the
-- per-item "None" exclusion); nil-off consumers are all falsy-safe, and
-- cdStateEffect consumers normalize false to nil explicitly.
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

-- Does this icon have a custom Cooldown State Effect (preset cd-state)? Used by
-- the appearance refresh so it doesn't clear a preset's _cdStateHidden flag --
-- presets store cdState in customActiveStates, not per-bar spellSettings.
function ns.PresetHasCdState(frame)
    local fc = ns._ecmeFC and ns._ecmeFC[frame]
    if not fc or not fc.spellID then return false end
    local cas = ns.GetEffectiveCustomActiveState(fc.spellID)
    local eff = cas and cas.cdStateEffect
    if eff == false then eff = nil end  -- blocking-false = no effect
    return eff ~= nil
end

-- Max Stacks Glow gate: set ns._cdmAnyMaxStacksGlow once if any saved spell (any
-- spec) has the glow enabled. RefreshCDMIconAppearance then skips its per-icon
-- watch check entirely for anyone who never uses the feature -- 0 cost when off.
-- Monotonic + scanned-once: a runtime enable is handled by the option's setValue,
-- so this only needs to discover already-saved settings at/after login.
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

-- Audio on Buff Gain/Loss gate: set ns._cdmAnyBuffSound once if any saved buff
-- icon (any spec) has a gain OR loss sound chosen. DecorateFrame / RefreshCDMIconAppearance
-- then skip attaching the apply-edge sound hook entirely for anyone who never uses
-- the feature -- 0 cost when off. Same scanned-once + runtime-enable contract as
-- RescanMaxStacksGlowFlag (the option's setValue flips the flag live).
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
-- spec by SEARCHING the saved bar spellSettings -- independent of any per-frame
-- decoration state (_ecmeFC). The first buff gain after login fires its aura alert
-- BEFORE DecorateFrame populates that state, so the sound path must resolve purely
-- from the id (GetCanonicalSpellIDForFrame reads cooldownInfo, so it works while the
-- aura is active). O(bars): spellSettings is keyed by id, so each bar is one index.
-- Mirrors Ayije, which matches alert-time id candidates against its buff registry
-- rather than any frame-decoration state.
function ns.FindBuffSoundKey(sid, field)
    if not sid then return nil end
    local specKey = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
    if not specKey or specKey == "0" then return nil end
    local sp = SpellStore and SpellStore.GetSpecProfiles and SpellStore.GetSpecProfiles()
    local prof = sp and sp[specKey]
    if not prof then return nil end
    -- Per-spell tier: the buff family store (explicit false = user turned an
    -- inherited bar-level sound OFF for this one buff -- treat as silent).
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
-- cd/utility icon (any spec) has a CD-ready sound chosen. The per-frame
-- SetDesaturated edge hook then no-ops entirely for anyone who never uses it.
-- Same monotonic, scanned-once contract as RescanBuffSoundFlag (runtime enables
-- are handled by the option's setValue).
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

-- "Hide CD Text (Charges)" gate: set ns._cdmAnyChargeHideCdText once if any saved
-- spell (any spec) has the toggle enabled, so RefreshCDMIconAppearance skips its
-- per-icon watch check for anyone who never uses the feature. Same monotonic,
-- scanned-once contract as RescanMaxStacksGlowFlag (runtime enables are handled by
-- the option's setValue).
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

-- Custom Item gate: set ns._cdmAnyCustomItem once if any saved bar (any spec)
-- tracks a custom item (an assignedSpells entry <= -100). The buff-bar injection
-- pass is then skipped entirely for anyone who never adds one -- 0 cost when off.
-- Same monotonic, scanned-once contract as the flags above (the picker flips the
-- flag live when an item is added).
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

-- "Show Charges" (custom CD/utility spells) gate. Same monotonic, scanned-once
-- contract as the flags above (the Add Custom Spell popup flips it live). Zero
-- cost in ProcessPresetCooldowns unless a custom spell has opted in.
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


-- Reverse Swipe gate: set ns._cdmAnyReverseSwipe once if any saved spell (any
-- spec) has the per-spell reverseSwipe toggle on. The reverse-apply in
-- RefreshCDMIconAppearance is skipped entirely for anyone who never enables it,
-- so the cooldown keeps its default swipe direction at 0 cost. Monotonic,
-- scanned-once contract identical to the flags above (the options toggle flips
-- the flag live on enable).
-- Also gates hideCDSwipe (Hide CD Swipe): both are monotonic per-spell swipe
-- flags, scanned together in one pass so neither costs anything until used.
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

-- Threshold Text gate: set ns._cdmAnyThresholdText once if any saved spell (any
-- spec) has Threshold Seconds armed -- per-spell family stores, bar tiers, or
-- preset/custom customActiveStates entries. The formatter attach in
-- RefreshCDMIconAppearance (and the fake-active / custom-buff attach sites) is
-- skipped entirely for anyone who never uses the feature. Monotonic,
-- scanned-once contract identical to the flags above (the options setters flip
-- the flag live on enable).
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

-- Custom Icon gate: set ns._cdmAnyCustomIcon once if any saved spell (any
-- spec) has a per-spell replacement icon configured. The re-stamp in
-- DecorateFrame and the RefreshSpellTexture post-hooks are skipped entirely
-- for anyone who never uses the feature -- 0 cost when off. Same monotonic,
-- scanned-once contract as the flags above (the options popup flips the flag
-- live on save). Purely per-spell: customIcon is never written to bar tiers,
-- but ForEachSavedSettingsBlock walks per-spell entries anyway.
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

-------------------------------------------------------------------------------
--  Spec helpers
--
--  Single source of truth: the live game API. We cache the resolved spec key
--  on first read. The cache is never set to nil during normal operation --
--  it transitions atomically from old key to new key inside ProcessSpecChange.
--  InvalidateSpecKey exists only for the early-login wakeFrame (before CDM
--  setup has completed) and is never called during spec change processing.
--
--  Returns nil when the spec API is not ready yet (very early login). All
--  consumers must bail when this returns nil rather than fall back to a
--  stored value, so CDM never builds with a wrong/guessed spec.
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

-- Only used by the early-login wakeFrame before CDM setup has completed.
-- Never called during spec change processing.
function ns.InvalidateSpecKey()
    _cachedSpecKey = nil
end

-- Compute the live spec key from the game API without touching the cache.
-- Returns nil if the API isn't ready yet.
local function ComputeLiveSpecKey()
    local specIndex = GetSpecialization and GetSpecialization()
    if not specIndex or specIndex == 0 then return nil end
    local specID = select(1, C_SpecializationInfo.GetSpecializationInfo(specIndex))
    if not specID or specID == 0 then return nil end
    return tostring(specID)
end
ns.ComputeLiveSpecKey = ComputeLiveSpecKey

-- Kept for any legacy callers that need a per-character identifier.
-- No longer used for spec storage.
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

-- Ghost CD bar: hidden routing sink for CD/utility spells. When the user "removes"
-- a spell from a CD or utility bar, it routes here instead of being deleted.
-- This means every spell in Blizzard's viewer pool always has a route,
-- eliminating the need for allowSet filtering during collection.
local GHOST_CD_BAR_KEY = "__ghost_cd"
MAIN_BAR_KEYS[GHOST_CD_BAR_KEY] = true

-------------------------------------------------------------------------------
--  Resolve the best spellID from a CooldownViewerCooldownInfo struct.
--  Priority: overrideSpellID > first linkedSpellID > spellID.
--  The base spellID field can be a spec aura (e.g. 137007 "Unholy Death
--  Knight") while the real tracked spell lives in linkedSpellIDs.
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
--  Resolve the best spellID from a Blizzard CDM viewer child frame.
--  For buff bars the cooldownInfo struct often contains the wrong spellID
--  (spec aura instead of the actual tracked buff). The child frame itself
--  knows the correct spell via GetAuraSpellID / GetSpellID at runtime.
--  Falls back to ResolveInfoSpellID when the frame methods aren't available.
--  ONLY used in out-of-combat paths (snapshot, dropdown, reconcile).
-------------------------------------------------------------------------------
local function ResolveChildSpellID(child)
    if not child then return nil end
    -- Prefer the aura spellID (most accurate for buff viewers).
    -- Wrap comparisons in pcall: these frame methods can return secret
    -- number values in combat which cannot be compared with > 0.
    if child.GetAuraSpellID then
        local ok, auraID = pcall(child.GetAuraSpellID, child)
        if ok and auraID then
            local cmpOk, gt = pcall(function() return auraID > 0 end)
            if cmpOk and gt then return auraID end
        end
    end
    -- Then try the frame's own spellID
    if child.GetSpellID then
        local ok, fid = pcall(child.GetSpellID, child)
        if ok and fid then
            local cmpOk, gt = pcall(function() return fid > 0 end)
            if cmpOk and gt then return fid end
        end
    end
    -- Fall back to cooldownInfo struct
    local cdID = child.cooldownID or (child.cooldownInfo and child.cooldownInfo.cooldownID)
    if cdID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
        return ResolveInfoSpellID(info)
    end
    return nil
end

-------------------------------------------------------------------------------
--  Build a set of currently known (learned) spellIDs across all CDM categories.
--  Uses GetCooldownViewerCategorySet(cat, false) which returns only learned
--  spells, then resolves each cdID to its base spellID.
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
                    -- Store ALL related spell IDs so reconcile can match
                    -- regardless of whether the bar stores the base ID,
                    -- override ID, or a linked ID.
                    -- Guard override-sourced IDs with IsPlayerSpell: CDM
                    -- info can report a stale overrideSpellID after the
                    -- talent providing it is removed (e.g. Cleave/Whirlwind).
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
    -- Fallback: also check the full CDM category set (cat, true) which
    -- includes ALL spells for the class regardless of talent selection.
    -- Spells that exist in the full set AND pass IsPlayerSpell are known
    -- even if the viewer hasn't updated yet after a talent swap.
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

--- Deep-copy a table (simple values + nested tables, no metatables/functions)
local function DeepCopy(src)
    if type(src) ~= "table" then return src end
    local copy = {}
    for k, v in pairs(src) do copy[k] = DeepCopy(v) end
    return copy
end

--- Save the current spec's non-spell per-spec data.
--- Spell data lives directly in the global store via ns.GetBarSpellData()
-------------------------------------------------------------------------------
--  Cached bar sizes -- purely cosmetic hint for pre-sizing frames on login
--  so anchored elements don't jump. Has zero impact on spell logic or icons.
--  Stored in EllesmereUIDB.cdmCachedBarSizes[charKey][specKey][barKey] = count
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

--- and never needs copying.
local function SaveCurrentSpecProfile()
    local p = ECME.db.profile
    local specKey = ns.GetActiveSpecKey()
    if not specKey or specKey == "0" then return end
    local specProfiles = SpellStore.GetSpecProfiles()
    if not specProfiles[specKey] then specProfiles[specKey] = { barSpells = {} } end
    local prof = specProfiles[specKey]

    -- Bar Glows and Tracked Buff Bars are stored in the active profile's
    -- specProfiles[specKey] bucket. GetBarGlows() and GetTrackedBuffBars()
    -- read/write there directly, so nothing extra to copy here.

    -- Snapshot visible icon counts for pre-sizing on next login
    ns.SaveCachedBarSizes()
end

--- Spec change processing.
---
--- Pattern: don't use a fixed wall-clock delay -- Blizzard's viewer pools
--- repopulate at unpredictable times after a spec swap. Instead, use
--- Spec change processing.
---
--- SPELLS_CHANGED is the sole trigger for spec change rebuilds. It fires
--- for both manual spec swaps and LFG auto-swaps, and guarantees that
--- Blizzard's spell data and viewer pools are fully populated.
---
--- On every SPELLS_CHANGED, CheckSpecChange compares the live spec key
--- (from GetSpecialization) to the cached key. If they differ, the spec
--- changed and ProcessSpecChange runs a full talent_reconcile rebuild.
--- The cached key is swapped atomically BEFORE the rebuild so
--- GetBarSpellData always has a valid key. No nil window.
local function ProcessSpecChange(newSpecKey)
    if not newSpecKey then return end
    ns._spellOrderDirty = true  -- force spell order cache rebuild

    -- Atomic swap: write the new key BEFORE rebuilding so every
    -- GetBarSpellData call during the rebuild reads the correct spec.
    _cachedSpecKey = newSpecKey

    -- Suppress the _ECME_Apply rebuild that the profile system will fire
    -- via RefreshAllAddons. We're about to do a full talent_reconcile
    -- rebuild which is strictly stronger.
    ns._specChangeJustRan = true
    -- Time-box stamp for the justRan consume in _ECME_Apply: the
    -- suppression is only honored while the spec change is recent, so a
    -- flag left armed by a path that never consumed it fails OPEN (an
    -- extra rebuild) instead of silently eating a needed one.
    ns._specChangeAt = GetTime()

    ns._pendingApplyOnReanchor = true

    -- Full wipe + rebuild path. talent_reconcile reason triggers the
    -- isFullWipe branch in FullCDMRebuild which: wipes icon arrays, clears
    -- _prevIconRefs / _prevVisibleCount, clears anchor state in
    -- _hookFrameData, clears all FC caches on viewer pool frames, then
    -- runs a direct synchronous CollectAndReanchor. After this returns,
    -- cdmBarIcons is populated with the new spec's icons.
    -- Hold placeholder injection across this synchronous talent_reconcile pass:
    -- on a spec switch it runs BEFORE the per-spec profile swap, so barDataByKey
    -- still carries the OLD spec's Always-Show / Keep-in-Place flags. Injecting
    -- here would flash placeholders the new spec never asked for. The reanchor
    -- that follows (profile_import for per-spec, or the next buff event) re-injects
    -- correctly from the now-active profile.
    if ns.FullCDMRebuild then
        ns._cdmSpecRebuildStale = true
        ns.FullCDMRebuild("talent_reconcile")
        ns._cdmSpecRebuildStale = false
    end

    -- Signal the profile system that CDM's spec rebuild is complete.
    -- This clears _specProfileSwitching and re-applies width/height matches.
    if EllesmereUI and EllesmereUI.OnSpecSwitchComplete then
        EllesmereUI.OnSpecSwitchComplete()
    end

    -- Refresh the CDM options pages now that _cachedSpecKey is swapped. The
    -- options' own PLAYER_SPECIALIZATION_CHANGED watcher races this swap (that
    -- event can fire before SPELLS_CHANGED), so driving the refresh from here
    -- guarantees the page rebuilds against the new spec instead of leaving the
    -- previous spec's selected bar on screen.
    if ns.OnTBBSpecChanged then ns.OnTBBSpecChanged() end
end
ns.ProcessSpecChange = ProcessSpecChange

-- Compare live spec to cached spec. If different, process the change.
-- Called exclusively from SPELLS_CHANGED. Idempotent: once
-- ProcessSpecChange runs, the cached key matches live and subsequent
-- calls are no-ops.
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
    -- Try EABButton first (EllesmereUIActionBars creates these when Blizzard
    -- buttons are unavailable, e.g. when another addon hides ActionButton1-12)
    local eabSlot = (eabSlotOffsets[bar] or 0) + i
    local btn = _G["EABButton" .. eabSlot]
    -- Fall back to standard Blizzard button names
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
                        slot.__ECMECooldown:SetSwipeTexture("Interface\\Buttons\\WHITE8x8")
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
--  Glow styles are identified by NAME, never by raw index: CDM, Nameplates and
--  the shared engine order their lists differently, so the same integer means a
--  different style on each surface (this silently swapped styles). Each surface
--  also advertises a different subset, so the sync is best-effort: a style a
--  surface can't render is coerced to its nearest supported one, and the coerced
--  value is what gets STORED -- so the dropdown name and the preview image always
--  match what is actually displayed.
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
-- A TBB may STORE a non-renderable style (e.g. -1 default) but DISPLAYS it as
-- Pixel; compare what's shown, not what's stored.
local function PG_TbbEffectiveStyle(dst)
    return (dst.pandemicGlowStyle == 4) and 4 or 1
end

local function PG_GetNPProfile()
    if not EllesmereUIDB or not EllesmereUIDB.profiles then return nil end
    local pName = EllesmereUIDB.activeProfile or "Default"
    local prof = EllesmereUIDB.profiles[pName]
    return prof and prof.addons and prof.addons.EllesmereUINameplates
end

-- Write a canonical payload into a destination, coercing the style through the
-- destination's own name->index resolver (so the stored index is renderable).
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

-- True when dst already displays what PG_Write(dst, payload) would store. When
-- both are off nothing is shown, so leftover style/color is irrelevant.
-- actualStyleFn lets a surface report its EFFECTIVE (displayed) style when that
-- differs from the raw stored value (e.g. rectangle TBBs); defaults to stored.
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

-- Build a payload from a rectangle bar (Tracked Buff Bar): rectangles only
-- render Pixel/Auto-Cast, so report the EFFECTIVE displayed style, not the raw
-- stored one (which may be e.g. -1 "Blizzard Default", shown there as Pixel).
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

-- Apply a canonical payload to all sync surfaces (CDM icon bars, Tracked Buff
-- Bars, Nameplates), best-effort. opts.skipCdmKey / opts.skipNameplates exclude
-- the source surface; opts.skipTbbBar excludes one TBB (its source bar table).
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
        -- No custom shape (none/cropped): the icon is a plain sharp-cornered
        -- square. Fall back to the square glow texture so the pulse hugs the
        -- icon edges instead of filling it with a solid additive block. There
        -- is no live mask object in this state, so the soft square glow texture
        -- alone defines the shape. Skip the shape border overlay -- a plain
        -- square icon keeps its own border, so drawing the square shape border
        -- on top just adds a stray border line.
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
        -- Pixel Glow params. The pandemic glow passes explicit opts; per-button
        -- glows (active-state, CD-ready, bar glows) pass none, so resolve the
        -- owning CD/utility bar's Pixel Glow settings. Falls back to defaults for
        -- action-bar overlays and bars that never set the values.
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
    -- No Show()/Hide() -- overlay is always shown (created in DecorateFrame).
    -- Toggling visibility on a child of a Blizzard viewer frame triggers
    -- Layout hooks and causes position cascades.
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

-- Shown-alpha for cd-state / fake-active restore paths: EffectiveBarAlpha,
-- except 0 while the icon's bar is visibility-hidden. Restores that painted
-- EffectiveBarAlpha directly resurrected icons on bars the visibility
-- engine had hidden (alpha 0): any cooldown/aura flip repainted them
-- visible until the next visibility pass. Overflow-diverted frames follow
-- the bar they are painted on (same rule as the fake-active engine's
-- FrameBaseAlpha, which routes through here).
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
-- Global accessor: apply a spec profile to the live bars (used by profile import).
-- Spell data is read directly from the global store by all consumers; this
-- just needs to trigger a rebuild against the (now-active) spec.
_G._ECME_LoadSpecProfile = function(specKey)
    ns.FullCDMRebuild("profile_import")
end
-- Global accessor: get the current spec key string (e.g. "250"), or nil if
-- the spec API isn't ready yet.
_G._ECME_GetCurrentSpecKey = function()
    return ns.GetActiveSpecKey()
end
-- Global accessor: returns a set of all spellIDs currently in the user's CDM
-- viewer (all categories, displayed + known). Used by profile import to filter
-- out spells the importing user does not have in their CDM.
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

-- Reverse lookup: Blizzard CDM viewer frame name  our bar key
local _blizzViewerToBarKey = {
    EssentialCooldownViewer = "cooldowns",
    UtilityCooldownViewer   = "utility",
    BuffIconCooldownViewer  = "buffs",
}

-- Walk up from a frame to find which Blizzard CDM viewer it belongs to.
-- Also handles reparented frames (hook system) via the _barKey field.
local function GetBarKeyForBlizzChild(frame)
    -- Fast path: reparented frame with barKey set by hook system (external cache) or CDM frame
    local fc = _ecmeFC[frame]
    if (fc and fc.barKey) or frame._barKey then return (fc and fc.barKey) or frame._barKey, frame end
    local current = frame
    while current do
        local parent = current:GetParent()
        if not parent then return nil end
        -- Check if parent is one of our CDM bar containers (external cache or direct)
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

-- Find our icon that mirrors a given Blizzard CDM child.
-- Falls back to spellID + override matching for proc glows on transformed spells.
-- In hook mode, the icon IS the Blizzard child (direct identity check).
local function FindOurIconForBlizzChild(barKey, blizzChild)
    local icons = cdmBarIcons[barKey]
    if not icons then return nil end
    for _, icon in ipairs(icons) do
        local iifc = _ecmeFC[icon]
        local bc = iifc and iifc.blizzChild
        if icon == blizzChild or bc == blizzChild then return icon end
    end
    -- Fallback: match by spellID (covers override spells like HST -> Storm Stream)
    local alertSid = ResolveBlizzChildSpellID(blizzChild)
    if alertSid then
        for _, icon in ipairs(icons) do
            local ifc = _ecmeFC[icon]
            if (ifc and ifc.spellID) == alertSid then return icon end
        end
        -- Check override mapping (base spell <-> override)
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

-- Resolve spellID from a Blizzard CDM child (for IsSpellOverlayed guard and proc glow matching)
ResolveBlizzChildSpellID = function(blizzChild)
    local cdID = blizzChild.cooldownID
    if not cdID and blizzChild.cooldownInfo then
        cdID = blizzChild.cooldownInfo.cooldownID
    end
    if cdID then
        local info = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
            and C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
        if info then return ResolveInfoSpellID(info) end
    end
    return nil
end

-- Resolve unified glow color for a spell. Returns r, g, b or nil if default.
-- Checks ss.glowColor: "class" -> class color, "custom" -> ss.glowColorR/G/B.
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

    -- Per-spell proc glow settings
    local fc = _ecmeFC[icon]
    -- Force Custom Shape Glow (style 2) for custom-shaped icons (any shape but none/cropped)
    local shapeName = (fc and fc.shapeApplied) and fc.shapeName or nil
    local isCustomShape = shapeName and shapeName ~= "none" and shapeName ~= "cropped"
    local style = isCustomShape and 2 or PROC_GLOW_STYLE
    local sid = fc and fc.spellID
    if sid then
        local bk = fc and fc.barKey
        local sd = bk and ns.GetBarSpellData(bk)
        -- Shared resolver: matches the stored key against the frame's FULL
        -- identity set (canon, resolvedSid, baseSpellID, linkedSpellIDs, and
        -- GetBaseSpell) so a setting on the base spell resolves on its talent
        -- "proc into a second ability" override form (e.g. Reap -> base 344862).
        -- The old assignedSpells-only fallback missed this on default Essential/
        -- Utility bars, whose assignedSpells list is empty.
        local ss = ns.ResolveSpellSettings and ns.ResolveSpellSettings(icon, sid, sd, bk)
        if ss then
            -- Custom shapes are locked to Shape Glow: ignore the per-spell glow type
            -- (including "None") so a custom-shaped icon always shows Shape Glow. The
            -- per-spell glow COLOR below still applies.
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

    -- Stop active glow if running (proc takes priority)
    if glow._glowActive then StopNativeGlow(glow) end
    StartNativeGlow(glow, style, cr, cg, cb)
    if fd then fd.procGlowActive = true end
end

local function StopProcGlow(icon)
    local fd = icon and _getFD(icon)
    if not icon or not (fd and fd.procGlowActive) then return end
    local glow = fd and fd.glowOverlay or icon._glowOverlay
    StopNativeGlow(glow)
    if fd then fd.procGlowActive = false end
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

        -- Apply immediately: find our icon and show the proc glow.
        -- No defer needed -- icon mapping is current from the last reanchor.
        local ourIcon = FindOurIconForBlizzChild(barKey, cdmChild)
        if not ourIcon then return end
        ShowProcGlow(ourIcon)
        -- Force icon texture re-evaluation so override textures apply immediately
        FC(ourIcon).lastTex = nil
    end)

    hooksecurefunc(ActionButtonSpellAlertManager, "HideAlert", function(_, frame)
        if not frame then return end
        local barKey, cdmChild = GetBarKeyForBlizzChild(frame)
        if not barKey or not cdmChild then return end
        local ourIcon = FindOurIconForBlizzChild(barKey, cdmChild)
        local fd = ourIcon and _getFD(ourIcon)
        if not ourIcon or not (fd and fd.procGlowActive) then return end

        -- Trust Blizzard's HideAlert: stop our glow immediately.
        -- If Blizzard re-fires ShowAlert during an internal refresh,
        -- the glow restarts naturally on the next frame.
        StopProcGlow(ourIcon)
        -- Force icon texture re-evaluation so the original texture restores immediately
        FC(ourIcon).lastTex = nil
    end)

    _procGlowHooksInstalled = true
end

-- Scan all Blizzard CDM children for already-active proc alerts and apply
-- our proc glow. Called after hooks install and after the 2s reset so we
-- pick up procs that were active before our hooks were in place.
local function ScanExistingProcGlows()
    -- No-op: proc glows are now fully hook-driven. ShowAlert hooks installed
    -- at file load time catch Blizzard's login re-fire. This function kept
    -- as a callable no-op so existing call sites don't error.
end
ns.ScanExistingProcGlows = ScanExistingProcGlows

-- (OnProcGlowEvent removed -- all bars use hook-based proc glows via
-- InstallProcGlowHooks / ActionButtonSpellAlertManager now)
local function OnProcGlowEvent() end
ns.OnProcGlowEvent = OnProcGlowEvent

-- Install proc glow hooks at file-load time (earliest possible).
-- Blizzard re-fires ShowAlert during PLAYER_LOGIN for active procs.
-- Hooks must be in place before that to catch them.
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
    -- Forced crisp outline; the global "Never Show Slug" toggle drops the slug.
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

-- BuffBarCooldownViewer is the Blizzard buff bar strip. We hide it alongside
-- the icon viewer so Blizzard's default buff display is fully suppressed when
-- the user has CDM hiding enabled. Our Tracked Buff Bars replace it.
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

            -- Icon size + spacing: read from child icons.
            -- Blizzard CDM icons have a base size and a per-icon scale driven
            -- by the IconSize percentage slider. Spacing is measured from the
            -- gap between two adjacent visible icons in parent coordinates.
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

            -- Spacing: measure gap between adjacent visible icons
            if #shownIcons >= 2 and data.iconSize then
                -- Sort by left edge so we measure truly adjacent icons
                table.sort(shownIcons, function(a, b)
                    return (a:GetLeft() or 0) < (b:GetLeft() or 0)
                end)
                -- Find the smallest step between any two consecutive sorted icons
                -- GetLeft() returns UIParent-coordinate-space values
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
                    -- bestStep is in UIParent coords; iconSize = cw * cs (visual size in parent-of-icon coords)
                    -- Convert bestStep from UIParent coords to icon-parent coords
                    -- icon-parent coord ? UIParent coord multiplier = frame.effectiveScale / UIParent.effectiveScale
                    -- So to go back: divide by that
                    local frameEff = frame:GetEffectiveScale()
                    local uiEff = UIParent:GetEffectiveScale()
                    local parentStep = bestStep * uiEff / frameEff
                    -- Now parentStep is in frame coords; but iconSize = cw * cs, and positions in frame use cw units
                    -- So step in iconSize units = parentStep * cs
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

            -- Orientation from frame property
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
--  Force Blizzard EditMode CooldownViewer settings
--  Ensures viewers are set to "Always Visible" so Blizzard's hideWhenInactive
--  and visibility modes don't interfere with CDM's frame management.
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
--  EnforceCooldownViewerEditModeSettings (one-shot)
--  Runs ONCE on initialization to set desired Edit Mode settings:
--    - VisibleSetting = Always on ALL viewers
--    - HideWhenInactive = 1 on buff viewers (BuffIcon + BuffBar)
--  SaveLayouts is called at most once, during init. Never at runtime.
--  This prevents tainting Blizzard frame properties (isActive, etc.)
--  which happens when SaveLayouts triggers a layout reapply from addon code.
-------------------------------------------------------------------------------
local _editModePolicyApplied = false
local _suppressPolicyPopup = false
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

    local activeLayout = type(layoutInfo.activeLayout) == "number"
        and layoutInfo.layouts[layoutInfo.activeLayout]
    if not activeLayout or type(activeLayout.systems) ~= "table" then return end

    -- Preset layouts are read-only: SaveLayouts won't persist changes to
    -- them, causing an infinite enforce -> save -> reload loop because the
    -- preset resets on next login. Skip enforcement for presets and warn
    -- the user once per session.
    if numPresets > 0 and type(layoutInfo.activeLayout) == "number" and layoutInfo.activeLayout <= numPresets then
        -- Preset layouts are read-only; we never modify them. Always Show Buffs
        -- no longer requires a layout change (it draws placeholder icons), so
        -- there is nothing to enforce or warn about on a preset layout.
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

    -- Returns changed(bool). A layout stores a CooldownViewer setting ONLY when
    -- it's been changed away from Blizzard's default, so an absent entry means
    -- "running at the default." defaultValue is that default: when it already
    -- equals what we want we leave the entry absent (no change, no forced reload) --
    -- the effective value is already correct. We only add an explicit entry when
    -- the default differs from desired (e.g. BuffIcon HideWhenInactive 0 when
    -- "Always Show Buffs" is on).
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
            -- VisibleSetting=Always on ALL viewers. Default is Always, so an absent
            -- entry is already correct and is left alone.
            if UpsertSetting(sysInfo.settings, visSetting, visAlways, visAlways) then
                changed = true
            end
            -- Both buff viewers keep Blizzard's default HideWhenInactive=1
            -- (inactive entries stay hidden). Always Show Buffs is now drawn by
            -- our own per-bar placeholder icons, NOT by Blizzard's layout, so we
            -- reset any stale HideWhenInactive=0 an older version wrote. New
            -- installs are already at the default, so nothing changes here and
            -- no reload is triggered -- only upgraders get a one-time reset.
            if sysInfo.systemIndex == buffIconIdx or sysInfo.systemIndex == buffBarIdx then
                if UpsertSetting(sysInfo.settings, hideEnum, 1, 1) then
                    changed = true
                end
            end
        end
    end

    _editModePolicyApplied = true
    if not changed then return end

    -- Save the corrected layout. Blizzard won't visually apply this until
    -- the next login/reload, so we force a reload via popup.
    C_EditMode.SaveLayouts(layoutInfo)

    -- Show a forced (non-dismissable) reload popup (suppressed when called
    -- from ReapplyEditModePolicy -- caller shows its own dismissable prompt)
    if _suppressPolicyPopup then return end
    -- First install: the Welcome picker is pending/open and ALWAYS ends in
    -- its own forced ReloadUI, which applies the layout we just saved. A
    -- second forced popup here would stomp the picker and wreck the very
    -- first thing a new user sees -- stay silent and ride that reload.
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
        -- Force: no cancel, no escape, no click-outside dismiss
        local popup = _G["EUIConfirmPopup"]
        if popup then
            -- Hide cancel button
            if popup._cancelBtn then popup._cancelBtn:Hide() end
            -- Center the confirm button
            if popup._confirmBtn then
                popup._confirmBtn:ClearAllPoints()
                popup._confirmBtn:SetPoint("BOTTOM", popup, "BOTTOM", 0, 13)
            end
            -- Block escape key
            popup:SetScript("OnKeyDown", function(self, key)
                self:SetPropagateKeyboardInput(key ~= "ESCAPE")
            end)
            -- Block click-outside dismiss
            if popup._dimmer then
                popup._dimmer:SetScript("OnMouseDown", nil)
            end
        end
    end)
end

--- Re-apply EditMode CDM settings (called when showInactiveBuffIcons changes).
--- Resets the one-shot guard so the enforce function re-evaluates the layout.
--- Suppresses the built-in reload popup (caller shows its own).
function ns.ReapplyEditModePolicy()
    _editModePolicyApplied = false
    _suppressPolicyPopup = true
    EnforceCooldownViewerEditModeSettings()
    _suppressPolicyPopup = false
end

-- One-time per-profile migration: the old GLOBAL Always Show Buffs settings
-- (cdmBars.showInactiveBuffIcons / .desaturateInactiveBuffs) become PER-BAR
-- fields. A profile that had the global ON turns every buff bar ON, so
-- upgraders keep the same look (now via placeholder icons, no reload to toggle).
-- Runs once per profile (flag on cdmBars); re-runs on profile swap to a
-- pre-migration profile because that profile carries no flag.
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

-- One-time per-profile migration: the custom_buff ("Auras") bar type was merged
-- into the buff-family bars. Convert every custom_buff bar to a "buffs" bar in
-- place -- its key, assignedSpells, spellDurations, customSpellIDs, position and
-- all visual settings carry over unchanged. The buff phase now injects its
-- cast-timer custom buffs (the same own-frames the Auras renderer built), so a
-- converted bar looks and behaves identically, just as an extra buff-family bar
-- (its key is custom_*, never "buffs"). Runs once per profile (flag on cdmBars);
-- re-runs on swap to a pre-migration profile because that profile carries no flag.
-- Runs AFTER MigrateAlwaysShowBuffsToPerBar so the old global Always-Show value
-- only lands on original buff bars, not on converted Auras bars.
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
HideBlizzardCDM = function()
    -- Anchor each viewer to our corresponding bar container.
    -- Frames stay parented to viewers (no reparenting = no taint).
    -- The viewer becomes an invisible shell overlapping our container;
    -- CollectAndReanchor re-anchors individual icons within it.
    -- Viewer alpha stays at 1 so child frames inherit visibility.
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
            -- Don't reposition primary viewers (Essential/Utility/BuffIcon) --
            -- individual icon anchoring handles positioning.
            -- BuffBarCooldownViewer is secondary: hide it via alpha since
            -- TBB renders its own bars and we don't hook its Cooldown widgets.
            local isSecondary = (frameName == BLIZZ_CDM_FRAMES_SECONDARY.buffs)
            if isSecondary then
                frame:SetAlpha(0)
                if not InCombatLockdown() then
                    frame:ClearAllPoints()
                    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10000, 10000)
                end
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
            -- Restore original anchor points
            if fc.origPoints then
                frame:ClearAllPoints()
                for _, pt in ipairs(fc.origPoints) do
                    frame:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5])
                end
            end
            -- Restore mouse interaction
            frame:EnableMouse(true)
            if frame.EnableMouseMotion then frame:EnableMouseMotion(true) end
            fc.hidden = false
            fc.restoring = nil
        end
    end
end

-- Restore Blizzard's BuffBarCooldownViewer (the bar-style buff tracking strip)
-- so it reappears when TBB is disabled via "Use Blizzard CDM Bars".
-- Only touches the secondary bar viewer; CDM icon bars are never affected.
local function RestoreBlizzardBuffFrame()
    local frameName = BLIZZ_CDM_FRAMES_SECONDARY.buffs
    if not frameName then return end
    local frame = _G[frameName]
    local fc = frame and _ecmeFC[frame]
    if fc and fc.hidden then
        fc.restoring = true
        if fc.origPoints then
            frame:ClearAllPoints()
            for _, pt in ipairs(fc.origPoints) do
                frame:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5])
            end
        end
        frame:SetAlpha(1)
        -- BuffBarCooldownViewer's default is EnableMouse(false); restoring
        -- it with EnableMouse(true) creates an invisible click-catcher.
        -- Other viewers need mouse for tooltip hover.
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

-- Resolve the frame anchor point for a bar from its growth direction and the
-- optional "anchor first row" pin.
--
-- Without anchorFirstRow this returns the single growth edge (legacy behavior:
-- RIGHT -> LEFT, DOWN -> TOP, ...) so the fixed edge stays put as the bar
-- resizes along its growth axis. The perpendicular axis is left unpinned, i.e.
-- centered -- which is why a horizontal bar re-centers vertically when it grows
-- a second row.
--
-- With anchorFirstRow set, the leading edge on the PERPENDICULAR axis is pinned
-- too, yielding a corner/edge anchor (e.g. TOPLEFT). Icons lay out from the
-- frame's TOPLEFT, so the first row sits at the top (horizontal bars) or the
-- first column at the left (vertical bars); pinning that edge makes extra rows
-- grow away from the first row instead of re-centering the whole bar.
-- Defined as ns.* fields (not file-scope locals) to stay under Lua 5.1's
-- 200-local main-chunk ceiling.
--
-- ignoreFirstRow: resolve the plain growth edge even if the pin is set. Used
-- for unlock-snapped bars, whose saved-edge consumers (ApplyAnchorPosition
-- edge preservation / target follow) only understand single-edge points.
function ns.ResolveGrowAnchorPoint(barData, ignoreFirstRow)
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
    if barData and barData.anchorFirstRow and not ignoreFirstRow then
        if barData.verticalOrientation then
            -- Vertical bar: rows stack along the width axis -> pin LEFT.
            horiz = horiz or "LEFT"
        else
            -- Horizontal bar: rows stack along the height axis -> pin TOP.
            vert = vert or "TOP"
        end
    end
    local pt = (vert or "") .. (horiz or "")
    if pt == "" then
        return "CENTER"
    end
    return pt
end

-- Convert a frame CENTER coord to the coord for anchor point `pt`. An axis with
-- no LEFT/RIGHT (or TOP/BOTTOM) component keeps the center; a zero-extent frame
-- yields a zero offset, so this is safe for empty bars.
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

-- Inverse of CenterToAnchorCoord: recover the frame CENTER coord from a stored
-- anchor-point coord. Round-trips losslessly for edges, corners, and CENTER.
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

local function ApplyBarPositionCentered(frame, pos, barKey)
    if not pos or not pos.point then return end
    local fw = frame:GetWidth() or 0
    local fh = frame:GetHeight() or 0
    local px, py = pos.x or 0, pos.y or 0
    local anchor = pos.point
    local bd = barKey and barDataByKey[barKey]

    -- Corner-capable re-derivation, taken ONLY when the first-row pin is in
    -- play for this bar (or the stored point is a corner left over from when
    -- it was). Recover the frame center from the stored anchor coord, then
    -- re-project it onto the anchor resolved from the bar's CURRENT growth +
    -- first-row settings -- a lossless coordinate round-trip, so the bar does
    -- not move; only the pinned edge/corner changes. Bars that never use the
    -- pin take the legacy conversion below instead, keeping their behavior
    -- unchanged. No persistence: positions are only saved by unlock mode's
    -- Save & Exit.
    local storedIsCorner = (anchor:find("TOP", 1, true) or anchor:find("BOTTOM", 1, true))
        and (anchor:find("LEFT", 1, true) or anchor:find("RIGHT", 1, true))
    if (bd and bd.anchorFirstRow) or storedIsCorner then
        local cx, cy = ns.AnchorCoordToCenter(anchor, px, py, fw, fh)
        anchor = ns.ResolveGrowAnchorPoint(bd)
        px, py = ns.CenterToAnchorCoord(anchor, cx, cy, fw, fh)
    elseif anchor == "CENTER" and barKey then
        -- Runtime conversion: if a non-CENTER-grow bar still has a CENTER
        -- position (legacy data, Blizzard import, or dev migration gap),
        -- convert to edge format for SetPoint so the bar grows from the
        -- correct edge.
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

    -- Snap to physical pixel grid. For CENTER anchor, use SnapCenterForDim
    -- to preserve the +0.5 offset that odd-pixel-dim frames need so their
    -- edges land on whole pixels. For single-edge anchors, the growth-axis
    -- coordinate is an EDGE (whole-pixel snap) but the perpendicular
    -- coordinate is the frame's CENTER on that axis -- parity-aware snap so
    -- an odd-pixel dimension keeps whole-pixel edges there too. Corner
    -- anchors (first-row pin) are edges on BOTH axes.
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

    -- Determine anchor point from grow direction (and the "anchor first row"
    -- pin) so the bar's fixed edge/corner stays put when icon count changes
    -- (spec swaps, combat buff churn, a row spilling in/out).
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

    -- Store relative to UIParent CENTER so offset math is consistent
    p.cdmBarPositions[barKey] = {
        point = pt, relPoint = "CENTER",
        x = (ax - uiW / 2) / scale,
        y = (ay - uiH / 2) / scale,
    }
end

-- Re-persist a bar's saved position in its CURRENT anchor format from live
-- geometry. Needed when the "anchor first row" toggle flips: a stored center /
-- single-edge position can't pin the first-row edge across row changes -- only
-- a stored corner can -- so we recapture the corner from where the bar sits
-- right now. Guarded to free-standing bars (snapped bars are owned by the unlock
-- anchor system, which reads unlockAnchors, not cdmBarPositions).
function ns.RecaptureBarAnchor(barKey)
    local frame = cdmBarFrames[barKey]
    if not frame then return end
    -- anchorTo bars (cursor, party/player frame, ERB, another bar) are
    -- positioned by their anchor, not cdmBarPositions -- saving from live
    -- geometry would overwrite the stored free-standing position with the
    -- anchored/cursor spot.
    local bd = barDataByKey[barKey]
    if bd and bd.anchorTo and bd.anchorTo ~= "none" then return end
    if EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored("CDM_" .. barKey) then return end
    if not frame:GetLeft() then return end
    SaveCDMBarPosition(barKey, frame)
end

-------------------------------------------------------------------------------
--  Helper: get the frame anchor point for a CDM bar.
--  Returns the near-edge center of the frame (the edge that faces away from target).
--  grow RIGHT -> near edge = LEFT, grow LEFT -> RIGHT, grow DOWN -> TOP, grow UP -> BOTTOM
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
        -- Containers never capture mouse motion: the rect spans the bar's
        -- full layout area and a motion-enabled frame with no unit steals
        -- mouseover focus from unit frames underneath. Icon hover is managed
        -- per-icon, gated on the bar's tooltip setting.
        if frame.EnableMouseMotion then frame:EnableMouseMotion(false) end
        frame._barKey = key
        frame._barIndex = barIndex
        cdmBarFrames[key] = frame
        cdmBarIcons[key] = {}
    end

    if not barData.enabled then
        if frame._mouseTrack then
            frame:SetScript("OnUpdate", nil)
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

    -- Scale removed -- all sizing is width/height based now
    if not InCombatLockdown() then frame:SetScale(1) end

    -- Restore configured strata/level (skip if cursor-anchored; that path uses TOOLTIP/9980)
    if not frame._mouseTrack then
        frame:SetFrameStrata(barData.barStrata or "MEDIUM")
        frame:SetFrameLevel(5)
    end

    -- Clear any previous mouse-tracking OnUpdate
    if frame._mouseTrack then
        frame:SetScript("OnUpdate", nil)
        frame._mouseTrack = nil
        -- Restore saved position from before mouse anchor
        if frame._preMousePos and not p.cdmBarPositions[key] then
            p.cdmBarPositions[key] = frame._preMousePos
        end
        frame._preMousePos = nil
        -- Restore saved frame level when leaving cursor anchor
        frame:SetFrameStrata(barData.barStrata or "MEDIUM")
        frame:SetFrameLevel(5)
        -- Restore mouse on frame and all children
        SetFrameClickThrough(frame, false)
        if frame.EnableMouseMotion then frame:EnableMouseMotion(false) end
    end
    frame._mouseGrow = nil

    -- FocusKick bar is exclusively owned by ApplyFocusKickAnchor. Skip the
    -- generic position block entirely so the else-branch default fallback
    -- never snaps the bar to UIParent CENTER 0,0 between a rebuild and the
    -- next nameplate event. Without this, the frame briefly teleports to
    -- screen center when BuildCDMBar runs before ApplyFocusKickAnchor.
    -- Uses the literal key because FOCUSKICK_BAR_KEY is declared later in
    -- this file (~L3076) and would be nil here.
    if key == "focuskick" then
        frame:Show()
        return
    end

    -- Cursor-anchored bar: if already tracking and still configured for
    -- mouse, skip the teardown+rebuild cycle. The OnUpdate is already
    -- running and repositioning correctly; tearing it down causes a
    -- 1-frame blink to BOTTOMLEFT 0,0 on every FullCDMRebuild.
    if frame._mouseTrack and barData.anchorTo == "mouse" then
        frame:Show()
        return
    end

    -- Position
    local anchorKey = barData.anchorTo
    if anchorKey == "mouse" then
        -- Stash saved position so it can be restored when unanchoring
        if p.cdmBarPositions[key] then
            frame._preMousePos = p.cdmBarPositions[key]
        end
        -- Anchor position acts as build direction for mouse cursor tracking
        local anchorPos = barData.anchorPosition or "right"
        local oX = barData.anchorOffsetX or 0
        local oY = barData.anchorOffsetY or 0
        -- Determine SetPoint anchor and 15px directional nudge
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
        -- Elevate to TOOLTIP strata so the bar renders above all UI
        frame:SetFrameStrata("TOOLTIP")
        frame:SetFrameLevel(9980)
        -- Make frame and all children fully click-through while following cursor
        SetFrameClickThrough(frame, true)
        local lastMX, lastMY
        local mouseAssertTick = 0
        frame:ClearAllPoints()
        frame:SetPoint(pointFrom, UIParent, "BOTTOMLEFT", 0, 0)
        frame._mouseTrack = true
        frame._mouseHiddenByPanel = false
        frame:SetScript("OnUpdate", function()
            -- Hide cursor-anchored bar while EUI options panel or unlock mode is open
            local panelOpen = (EllesmereUI._mainFrame and EllesmereUI._mainFrame:IsShown())
                or EllesmereUI._unlockActive
            if panelOpen then
                frame._mouseHiddenByPanel = true
                if frame:GetAlpha() > 0 then frame:SetAlpha(0) end
                -- Reset icon strata while panel is open
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
            -- Visibility-hidden: park the bar offscreen instead of tracking
            -- the cursor. Alpha alone cannot keep the icons invisible -- the
            -- engine re-raises item alpha through paths no hook can see
            -- (SetAlphaFromBoolean, alpha animations) whenever cooldown/aura
            -- state changes, so a hidden bar kept flashing back mid-screen
            -- riding the cursor (same lesson as the unclaimed-frame park in
            -- EllesmereUICdmHooks). Icons are anchored to this container, so
            -- the park carries them along; position is immune to every alpha
            -- path. The lastMX reset forces a re-SetPoint on the first frame
            -- after the visibility engine un-hides the bar.
            -- The GetLeft probe re-asserts the park if anything moved the
            -- container back on-screen while hidden (LayoutCDMBar, a
            -- rebuild, or a stale _mouseParked flag surviving an
            -- unanchor/re-anchor cycle -- teardown never clears it).
            if frame._visHidden then
                if not frame._mouseParked or (frame:GetLeft() or 0) > -9000 then
                    frame._mouseParked = true
                    lastMX, lastMY = nil, nil
                    frame:ClearAllPoints()
                    frame:SetPoint(pointFrom, UIParent, "BOTTOMLEFT", -10000, -10000)
                end
                return
            end
            frame._mouseParked = false
            -- Throttled mouse-through re-assert: the Decorate/Show/Cooldown
            -- path can re-enable mouse on icons mid-session, and an icon
            -- riding the cursor with mouse enabled intermittently kills
            -- [@mouseover] hovercast keys. Cheap no-op when state is clean.
            mouseAssertTick = mouseAssertTick + 1
            if mouseAssertTick >= 30 then
                mouseAssertTick = 0
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
            local s = UIParent:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            cx = floor(cx / s + 0.5)
            cy = floor(cy / s + 0.5)
            if cx ~= lastMX or cy ~= lastMY then
                lastMX, lastMY = cx, cy
                frame:ClearAllPoints()
                frame:SetPoint(pointFrom, UIParent, "BOTTOMLEFT", cx + baseOX, cy + baseOY)
            end
        end)
    elseif anchorKey == "partyframe" then
        -- Anchor to the player's party frame
        local partyFrame = EllesmereUI.FindPlayerPartyFrame()
        if partyFrame then
            frame:ClearAllPoints()
            local side = barData.partyFrameSide or "LEFT"
            local oX = barData.partyFrameOffsetX or 0
            local oY = barData.partyFrameOffsetY or 0
            -- Snap offsets to physical pixel grid
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
            -- No party frame found  fall back to saved position
            local pos = p.cdmBarPositions[key]
            if pos and pos.point then
                ApplyBarPositionCentered(frame, pos, key)
            else
                frame:ClearAllPoints()
                frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
        end
    elseif anchorKey == "playerframe" then
        -- Anchor to the player's unit frame
        local playerFrame = EllesmereUI.FindPlayerUnitFrame()
        if playerFrame then
            frame:ClearAllPoints()
            local side = barData.playerFrameSide or "LEFT"
            local oX = barData.playerFrameOffsetX or 0
            local oY = barData.playerFrameOffsetY or 0
            -- Snap offsets to physical pixel grid
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
            -- No player frame found  fall back to saved position
            local pos = p.cdmBarPositions[key]
            if pos and pos.point then
                ApplyBarPositionCentered(frame, pos, key)
            else
                frame:ClearAllPoints()
                frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
        end
    elseif anchorKey == "erb_castbar" or anchorKey == "erb_powerbar" or anchorKey == "erb_classresource" then
        -- Anchor to EllesmereUI Resource Bars frames
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
            -- Snap offsets to physical pixel grid
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
            -- Circular anchor detected -- fall back to center
            if not ok then
                frame:ClearAllPoints()
                frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
        else
            -- Resource Bars frame not available  fall back to saved position
            local pos = p.cdmBarPositions[key]
            if pos and pos.point then
                ApplyBarPositionCentered(frame, pos, key)
            else
                frame:ClearAllPoints()
                frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
        end
    else
        -- If the bar is unlock-anchored and already positioned, DO NOT touch
        -- its position. The anchor system (ApplyAnchorPosition / PropagateAnchorChain)
        -- is authoritative for unlock-anchored bars. Previously, a rebuild
        -- during combat (or any transient state) could fall into the "no
        -- legacy pos saved" branch below and teleport the bar to a hardcoded
        -- default (e.g. CENTER 0,-275 for cooldowns, CENTER 0,0 for custom
        -- bars). The anchor system would later re-propagate, but if the
        -- anchor target was temporarily unavailable (hidden frame, pre-layout
        -- race, etc.) the re-anchor would bail and the bar would stay stuck
        -- at the hardcoded fallback.
        local unlockKey = "CDM_" .. key
        local anchored = EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored(unlockKey)
        if anchored and frame:GetLeft() then
            -- Unlock-anchored and already has bounds: leave position alone.
        else
            local pos = p.cdmBarPositions[key]
            if pos and pos.point then
                ApplyBarPositionCentered(frame, pos, key)
            elseif not anchored then
                -- Default fallback positions (only for truly un-anchored bars
                -- with no saved position).
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
            -- If anchored but frame has no bounds yet, do not set a fallback
            -- position. ReapplyOwnAnchor runs after BuildAllCDMBars and will
            -- place the frame correctly once the target is available.
        end
    end

    -- Show the frame but respect visibility mode.
    -- Always Show() so layout/children work.
    -- _CDMApplyVisibility is the single authority for alpha/hiding.
    frame:Show()
end

-- Compute stride respecting the custom row-count override (only for numRows == 2).
-- Two MUTUALLY EXCLUSIVE overrides both resolve to an effective TOP-row count:
--   * Custom Top Row Count    -> topRowCount icons on the top row.
--   * Custom Bottom Row Count -> bottomRowCount icons on the bottom row; the top
--     row gets the remainder (the flipped form of the top override).
-- Mutual exclusivity is enforced in options; if both somehow set, top wins.
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
            -- Custom-row mode only uses a second row once BOTH rows are non-empty.
            -- Until then, report ONE effective row so the bar doesn't reserve or
            -- lay out an empty row. The second row appears the moment both rows
            -- hold at least one icon.
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

-- Empty custom bars still need a stable footprint so unlock mode can keep a
-- visible mover and convert drag positions correctly before any icons exist.
local EMPTY_CDM_BAR_SIZE = { 100, 36 }

-- Count the spell entries that contribute real icon slots for this bar.
-- Unlock mode uses this to estimate a footprint before the live frame has
-- been laid out, which is common for freshly created Misc bars.
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
    -- Raw coord values -- see LayoutCDMBar for why we don't pre-snap
    -- with SnapForScale.
    local iW = barData.iconSize or 36
    local iH = iW
    if (barData.iconShape or "none") == "cropped" then
        iH = math.floor((barData.iconSize or 36) * 0.80 + 0.5)
    end
    local sp = barData.spacing or 2
    -- Use the EFFECTIVE row count from ComputeTopRowStride: it collapses to 1
    -- when a custom top-row split has no icons in its second row yet, so the
    -- footprint doesn't reserve an empty second row.
    local stride, rows = ComputeTopRowStride(barData, count)
    if rows < 1 then rows = 1 end
    local grow = barData.growDirection or "CENTER"
    local isH = (grow == "RIGHT" or grow == "LEFT" or grow == "CENTER")
    if isH then
        return stride * iW + (stride - 1) * sp,
               rows * iH + (rows - 1) * sp
    end
    return rows * iW + (rows - 1) * sp,
           stride * iH + (stride - 1) * sp
end

-- Return the authoritative footprint unlock mode should use for a CDM bar.
-- Prefer the live frame when it already has bounds; otherwise derive the size
-- from bar configuration, and fall back to a stable empty-bar placeholder.
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

    -- Buff-family / custom-buff bars have no assigned spells (their icons are
    -- auras added live), so before the first aura the frame is empty and the
    -- spell count is 0. Size from the configured icon dimensions (one icon) so
    -- the empty frame -- and the unlock overlay that mirrors it -- reflect the
    -- icon size, instead of the generic placeholder that otherwise persisted
    -- until a buff was acquired once.
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

    -- Shift-Icons cd-state modes: icons flagged shift-hidden are dropped from
    -- the layout entirely, so later icons close the gap and the bar resizes as
    -- if the icon were removed. Everything below (sizing, match math, slot
    -- positions) derives from this one array, so the filter is the whole
    -- feature. The flag is only ever set by the cd-state evaluators (via
    -- ns.SetCdStateShiftHidden); bars without it pay one field read per icon
    -- and never build the filtered table. Skipped frames keep their last
    -- point at alpha 0 (same as the non-shift hidden modes).
    do
        local filtered
        for i = 1, #icons do
            local sfc = _ecmeFC[icons[i]]
            if sfc and sfc._cdStateShiftHidden then
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
    -- Row count is taken from ComputeTopRowStride's EFFECTIVE rows (effRows,
    -- computed once the icon count is known below), which collapses a custom
    -- top-row split to a single row until its second row is actually populated.
    local isHoriz = (grow == "RIGHT" or grow == "LEFT" or (grow == "CENTER" and not barData.verticalOrientation))
    -- spacing is a raw coord value; the per-frame pixel conversion below
    -- (spacingPx = floor(spacing / onePx + 0.5)) rounds to nearest whole
    -- physical pixel. Do NOT pre-snap with SnapForScale: PP.Scale truncates,
    -- which can lose a pixel at UI scales where PP.mult > 1 (e.g. spacing=2
    -- gets truncated from 2 coord to 1.0667 coord = 1 px instead of 2 px).
    local spacing = barData.spacing or 2

    -- Width/height match: derive iconSize live from the SOURCE bar's
    -- current width on every layout pass. The source bar IS the truth, so
    -- reading it live auto-corrects across spec swaps, source resizes, etc.
    -- Nothing is persisted -- no _matchPhysWidth field, no migration story,
    -- no possibility of cross-spec corruption.
    local extraPixels = 0
    local extraPixelsH = 0
    local widthMatchTarget = EllesmereUI.GetWidthMatchTarget
        and EllesmereUI.GetWidthMatchTarget("CDM_" .. barKey) or nil
    local heightMatchTarget = EllesmereUI.GetHeightMatchTarget
        and EllesmereUI.GetHeightMatchTarget("CDM_" .. barKey) or nil
    local PP = EllesmereUI.PP
    local onePx = PP.mult
    local iconW
    -- Set true ONLY when the width-match math below actually produces an iconW.
    -- Gates the cropped-height-from-matched-width fix so non-matched and
    -- height-matched bars stay byte-identical.
    local widthMatchApplied = false
    -- Set (to the matched cropped height in physical px) ONLY when the
    -- height-match math below succeeds. Lets a cropped height-matched bar's
    -- per-icon height use the matched height the branch already computed,
    -- instead of the stored iconSize, so icons stay in lockstep with the
    -- container's extraPixelsH leftover distribution.
    local heightMatchIconHPx = nil
    -- Width-axis dim (icons spanning the width). Use the effective row count
    -- so a not-yet-populated second row doesn't widen the match math.
    local function CurWidthDim()
        local s, r = ComputeTopRowStride(barData, #icons)
        return isHoriz and s or r
    end
    -- Height-axis dim (icons spanning the height)
    local function CurHeightDim()
        local s, r = ComputeTopRowStride(barData, #icons)
        return isHoriz and r or s
    end
    -- Resolve a width/height match target unlock key to a live frame.
    -- The match DB stores keys like "CDM_cooldowns" or "MainBar"; the
    -- registered unlock element provides a getFrame() callback.
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
        -- Not matched, OR target frame couldn't be read (early in build,
        -- before source bar exists, etc.). Use the user's stored iconSize.
        -- Raw coord value: the per-frame pixel conversion below rounds to
        -- nearest whole physical pixel. Do NOT pre-snap with SnapForScale
        -- (see spacing note above).
        iconW = barData.iconSize or 36
    end

    local iconH = iconW
    local shape = barData.iconShape or "none"
    if shape == "cropped" then
        if widthMatchApplied then
            -- Width-matched: derive cropped height from the MATCHED icon width
            -- so the icon keeps the same ~0.80 aspect ratio as the non-matched
            -- path. Computed in physical pixels to stay on the pixel grid (the
            -- matched iconW is already a clean pixel multiple). This matches the
            -- non-matched path's aspect-ratio intent, not its exact value -- the
            -- non-matched else branch rounds 0.80 in coord space, so the two can
            -- differ by up to 1px at non-perfect UI scales.
            local wPx = math.floor(iconW / onePx + 0.5)
            iconH = math.floor(wPx * 0.80 + 0.5) * onePx
        elseif heightMatchIconHPx then
            -- Height-matched: use the EXACT cropped height the height-match math
            -- already computed (basePhysIconH). Must match that value precisely
            -- so per-icon height stays in lockstep with the container's
            -- extraPixelsH leftover distribution, which was sized around it.
            iconH = heightMatchIconHPx * onePx
        else
            iconH = math.floor((barData.iconSize or 36) * 0.80 + 0.5)
        end
    end

    -- Use ALL icons in the array (not just IsShown). CollectAndReanchor
    -- already filtered to only include frames we claimed. Blizzard may
    -- toggle IsShown independently -- we position everything we own.
    local visibleIcons = icons
    local count = #visibleIcons
    -- Bar sizing uses the actual icon count as the sole authority.
    -- The count==0 early return below preserves the last known size
    -- during brief transitional states (spec swap, pool churn).
    local sizeCount = count
    if count == 0 then
        local curW = frame:GetWidth() or 0
        local curH = frame:GetHeight() or 0
        if curW <= 1 or curH <= 1 then
            local fallbackW, fallbackH = GetStableCDMBarSize(barKey, nil, barData)
            -- Snap to physical pixel grid. EMPTY_CDM_BAR_SIZE is a raw
            -- coord-space placeholder; without snapping, buff-family bars
            -- (which often stay empty) render at non-pixel-aligned heights
            -- like 43.20 px instead of 43 px at non-perfect UI scales.
            fallbackW = SnapForScale(fallbackW, 1)
            fallbackH = SnapForScale(fallbackH, 1)
            frame:SetSize(fallbackW, fallbackH)
            frame._prevLayoutW = fallbackW
            frame._prevLayoutH = fallbackH
        end
        -- Never permanently hide containers on transient count=0. Spec
        -- swaps and viewer pool churn can produce brief 0-count states.
        -- The next reanchor refills the bar. Hiding the container would
        -- require an explicit re-show that nothing guarantees.
        if frame._barBg then frame._barBg:Hide() end
        return
    end

    -- Bar has visible icons -- ensure it is visible (unless visibility is "never")
    -- effRows is the EFFECTIVE row count: 1 when a custom top-row split has no
    -- icons in its second row yet, so the container doesn't grow a blank row.
    local stride, effRows, customTopCount = ComputeTopRowStride(barData, sizeCount)

    -- Container size -- compute everything in integer physical pixels first,
    -- then convert back to coord at the end. Doing the multiplications in
    -- coord space and then snapping loses 1 phys px to floating-point dust:
    -- e.g. 3 * 21.6666... coord rounds via floor to 81 phys instead of 82,
    -- leaving the bottom icon protruding 1 px past the bar frame.
    local PP = EllesmereUI.PP
    local onePx = PP.mult
    local iconWPx  = math.floor(iconW  / onePx + 0.5)
    local iconHPx  = math.floor(iconH  / onePx + 0.5)
    local spacingPx = math.floor(spacing / onePx + 0.5)
    -- Lock iconW / iconH / spacing to exact physical pixel multiples.
    -- Positioning (stepW, stepH) uses these coord values, and the width-
    -- match math uses the iconWPx / spacingPx integers. If coord and
    -- pixel values aren't in lockstep, icons drift sub-pixel as col index
    -- grows -- making spacing "shrink" and the final icon undershoot the
    -- width-match target by 1 px.
    iconW   = iconWPx  * onePx
    iconH   = iconHPx  * onePx
    spacing = spacingPx * onePx

    -- Per-row icon size offset (Number of Rows == 2, non-matched only). One row's
    -- icons take an Icon Scale pixel offset; the other row keeps the base size.
    -- Re-check the match target here (not just the options gate) so a bar that was
    -- matched AFTER the toggle was set stays uniform. Rows are centered against
    -- each other; the larger row defines the bar's growth-axis extent.
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

    local totalWPx, totalHPx
    if perRowActive then
        -- Two rows, independent icon sizes. Top row = customTopCount icons; the
        -- bottom row takes the remainder. The bar spans the LARGER row along the
        -- growth axis and the SUM of both row bands along the perpendicular axis.
        local topN = customTopCount
        local botN = sizeCount - topN
        if isHoriz then
            local topRowW = topN * rowWPx[1] + math.max(0, topN - 1) * spacingPx
            local botRowW = botN * rowWPx[2] + math.max(0, botN - 1) * spacingPx
            totalWPx = math.max(topRowW, botRowW)
            totalHPx = rowHPx[1] + rowHPx[2] + spacingPx
        else
            local topColH = topN * rowHPx[1] + math.max(0, topN - 1) * spacingPx
            local botColH = botN * rowHPx[2] + math.max(0, botN - 1) * spacingPx
            totalHPx = math.max(topColH, botColH)
            totalWPx = rowWPx[1] + rowWPx[2] + spacingPx
        end
    elseif isHoriz then
        totalWPx = stride  * iconWPx + (stride  - 1) * spacingPx + extraPixels
        totalHPx = effRows * iconHPx + (effRows - 1) * spacingPx + extraPixelsH
    else
        totalWPx = effRows * iconWPx + (effRows - 1) * spacingPx + extraPixels
        totalHPx = stride  * iconHPx + (stride  - 1) * spacingPx + extraPixelsH
    end

    -- NOTE: a previous "force even totalWPx for CENTER grow" adjustment
    -- used to live here. It is no longer needed: SnapCenterForDim (used by
    -- ApplyBarPositionCentered for CENTER-anchored frames) places the
    -- frame's center on a half-pixel grid when the dimension is odd, so
    -- both edges still land on whole physical pixels. The old +1 padded
    -- the frame 1 px wider than the actual icon layout (icons+spacing),
    -- leaving an empty pixel strip at the right/bottom that showed up as
    -- the unlock-mode overlay being 1 px bigger than the rightmost icon.

    local totalW = totalWPx * onePx
    local totalH = totalHPx * onePx

    -- Growth-direction edge handling around SetSize.
    -- SetSize is deferred to AFTER icon positioning (below) so that icons
    -- and bar resize both take effect on the same rendered frame. Positioning
    -- icons first is safe: they use computed absolute offsets from TOPLEFT,
    -- not the frame's current dimensions.
    local unlockKey = "CDM_" .. barKey
    -- Freeze buff-family bar size during unlock mode so the mover overlay
    -- stays in sync (overlay doesn't dynamically resize with buff count).
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

    if perRowActive then
        -- Two-row layout with a per-row icon size offset. Each row is laid out at
        -- its own icon size, centered along the growth axis; the perpendicular
        -- axis stacks the two row bands (top then bottom / left then right). No
        -- match extras apply -- the feature is gated off whenever matched.
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
                -- Growth axis = width: center this row within the bar width.
                -- Perpendicular axis = height: top band, then bottom band.
                local rowMainPx = rowN * wPx + math.max(0, rowN - 1) * spacingPx
                local offMainPx = math.floor((totalWPx - rowMainPx) / 2 + 0.5)
                local xPx = offMainPx + idxInRow * (wPx + spacingPx)
                local yPx = (rowIdx == 1) and 0 or (rowHPx[1] + spacingPx)
                anchorX = (xPx * onePx) * iS
                anchorY = -(yPx * onePx) * iS
            else
                -- Growth axis = height: center this row within the bar height.
                -- Perpendicular axis = width: left band, then right band.
                local rowMainPx = rowN * hPx + math.max(0, rowN - 1) * spacingPx
                local offMainPx = math.floor((totalHPx - rowMainPx) / 2 + 0.5)
                local yPx = offMainPx + idxInRow * (hPx + spacingPx)
                local xPx = (rowIdx == 1) and 0 or (rowWPx[1] + spacingPx)
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

    -- Uniform icon size: every row uses the same size. Original layout for all
    -- bars except the 2-row per-row-size case handled above.
    local stepW = iconW + spacing
    local stepH = iconH + spacing

    -- How many icons on the top row
    local topRowCount = customTopCount
    if topRowCount < 0 then topRowCount = 0 end
    local bottomRowCount = #visibleIcons - topRowCount
    if bottomRowCount < 0 then bottomRowCount = 0 end

    -- Compute per-row centering offset (icons fewer than stride get centered)
    local function RowIconCount(row)
        if row == 0 then return topRowCount end
        return bottomRowCount
    end

    -- Elevate icon strata for cursor-anchored bars (icons aren't parented
    -- to the container, so they don't inherit its TOOLTIP strata).
    local isMouseBar = barData.anchorTo == "mouse"

    -- Position each icon: fill bottom-up so bottom rows are full,
    -- top row gets the remainder. Center any row with fewer icons than stride.
    --
    -- The CDM "col" / "row" naming is along the bar's GROWTH axis:
    --   horizontal: col = width-axis position, row = height-axis position
    --   vertical:   col = height-axis position, row = width-axis position
    --
    -- Width-axis extras (extraPixels) expand iconW for the first N icons
    -- along the width axis. Height-axis extras (extraPixelsH) expand iconH
    -- for the first N icons along the height axis. linkedDimensions = only
    -- one match active, but the math handles both for symmetry.
    --   horizontal: col -> width axis, row -> height axis
    --   vertical:   row -> width axis, col -> height axis
    local growthW = isHoriz and extraPixels or extraPixelsH
    local growthH = isHoriz and extraPixelsH or extraPixels
    -- growthW = extras along the GROWTH axis (col index in this loop)
    -- growthH = extras along the PERPENDICULAR axis (row index in this loop)
    -- For horizontal width-match (the common case): growthW = W extras, applied to col.
    -- For vertical height-match: growthW = H extras, applied to col (= vertical pos).
    for i, icon in ipairs(visibleIcons) do
        -- Compensate for Blizzard's per-icon scale so visual size matches.
        local iconScale = icon:GetScale() or 1
        if iconScale < 0.01 then iconScale = 1 end
        local iS = 1 / iconScale

        -- Map sequential index to bottom-up grid position.
        -- Icon 1..topRowCount fill the top row (visual row 0).
        -- Remaining icons fill rows 1..effRows-1 (bottom rows).
        local col, row
        if i <= topRowCount then
            col = i - 1
            row = 0
        else
            local bottomIdx = i - topRowCount - 1
            col = bottomIdx % stride
            row = 1 + math.floor(bottomIdx / stride)
        end

        -- Apply +1 physical pixel to expanded icons. For horizontal bars,
        -- the expansion is on the WIDTH axis (iconW). For vertical bars
        -- where col = height-axis position, the expansion is on the HEIGHT
        -- axis (iconH). This keeps icons square in the perpendicular axis.
        local onePx = PP.mult
        local expandedCol = (growthW > 0 and col < growthW)
        local expandedRow = (growthH > 0 and row < growthH)
        local thisIconW, thisIconH
        if isHoriz then
            thisIconW = expandedCol and (iconW + onePx) or iconW
            thisIconH = expandedRow and (iconH + onePx) or iconH
        else
            -- For vertical: col is the height-axis index, so col-extras expand iconH
            thisIconH = expandedCol and (iconH + onePx) or iconH
            thisIconW = expandedRow and (iconW + onePx) or iconW
        end
        FC(icon).matchExpanded = (expandedCol or expandedRow) or nil
        icon:SetSize(thisIconW * iS, thisIconH * iS)

        -- Cumulative offsets: each prior expanded icon shifts subsequent
        -- icons by 1 physical pixel along the same axis.
        --   extraBefore  = along the growth axis (col index)
        --   extraBeforeR = along the perpendicular axis (row index)
        local extraBefore  = math.min(col, growthW) * onePx
        local extraBeforeR = math.min(row, growthH) * onePx

        if isMouseBar then
            icon:SetFrameStrata("TOOLTIP")
            icon:SetFrameLevel(9980 + i)
        else
            icon:SetFrameStrata(barData.barStrata or "MEDIUM")
            icon:SetFrameLevel(5 + i)
        end
        icon:ClearAllPoints()

        -- Center any row that has fewer icons than stride
        local rowCount = RowIconCount(row)
        local rowHasLess = (rowCount > 0 and rowCount < stride)

        -- Compute offsets as absolute parent-space integers, then divide
        -- by iconScale for SetPoint. No per-position snapping -- dividing
        -- integers by the same constant produces mathematically uniform gaps.
        local posX = col * stepW + extraBefore
        local posY = row * stepH

        -- Resolve anchor params first, then update fd._cdmAnchor BEFORE
        -- the SetPoint call. The SetPoint hook fires AFTER SetPoint and
        -- compares relativeTo against fd._cdmAnchor[2] -- if we update it
        -- after, the hook reads a stale anchor (e.g. the previous bar
        -- this frame was on) and snaps the icon back to the wrong place.
        -- This was the source of the "icon offset by ~50px" bug when
        -- moving a spell from utility to cooldowns.
        -- All growth directions use the same TOPLEFT icon layout.
        -- Growth direction only affects which edge of the FRAME is fixed
        -- during resize (handled by edge preservation). Icon order never
        -- changes with growth direction.
        local anchorPt, anchorRelPt, anchorX, anchorY
        local rowOffset = 0
        if isHoriz then
            if rowHasLess then
                rowOffset = math.floor((stride - rowCount) * stepW / 2 + 0.5)
            end
            anchorPt, anchorRelPt = "TOPLEFT", "TOPLEFT"
            anchorX = (posX + rowOffset) * iS
            anchorY = -(posY + extraBeforeR) * iS
        else
            if rowHasLess then
                rowOffset = math.floor((stride - rowCount) * stepH / 2 + 0.5)
            end
            anchorPt, anchorRelPt = "TOPLEFT", "TOPLEFT"
            anchorX = (row * stepW + extraBeforeR) * iS
            anchorY = -(col * stepH + extraBefore + rowOffset) * iS
        end

        if anchorPt then
            -- Stamp _cdmAnchor BEFORE SetPoint so the hook (which fires
            -- synchronously after SetPoint) sees the new anchor and treats
            -- our own SetPoint as a no-op instead of forcing back to stale.
            local fd = _getFD(icon)
            if fd then
                fd._cdmAnchor = { anchorPt, frame, anchorRelPt, anchorX, anchorY }
            end
            icon:SetPoint(anchorPt, frame, anchorRelPt, anchorX, anchorY)
        end
    end
    end  -- perRowActive vs uniform layout branch

    -- SetSize AFTER icon positioning: ensures bar resize and icon placement
    -- both take effect on the same rendered frame (no 1-frame size mismatch).
    if not skipResize then
        local oldW = frame:GetWidth() or 0
        local oldH = frame:GetHeight() or 0
        -- Pre-resize center in UIParent space, captured BEFORE SetSize (an
        -- edge-pointed frame moves its center when resized). The anchor offset
        -- upkeep below validates against it. Only captured when the upkeep can
        -- actually run (bar has an unlockAnchors entry): measuring a bar whose
        -- rect derives from a restricted tree hard-errors (FocusKick anchored
        -- to a nameplate in a locked instance), and such bars have no entry.
        -- pcall covers the residual case; an unknown center skips the upkeep.
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
        -- Anchor offset maintenance: when a growth-direction bar resizes,
        -- the center shifts by delta/2 but the fixed edge stays put.
        -- Adjust the center-based anchor offset so the relationship stays
        -- consistent on /reload.
        -- This is NOT a position write (positions are only saved by Save & Exit).
        -- Self-validating gate: the compensation is only correct when the bar's
        -- PRE-resize center actually sat at the anchor-derived position (target
        -- center + stored offset on the compensated axis). During a profile
        -- apply the bar still holds the OUTGOING profile's position while
        -- unlockAnchors already carries the INCOMING profile's offsets;
        -- compensating that mismatch corrupts the offsets cumulatively on every
        -- swap. Layout passes can land before, inside, or after any suppression
        -- window, so the position check is the only ordering-proof guard. A
        -- falsely-skipped legit compensation (bar momentarily off its anchor)
        -- costs at most a one-time dw/2 nudge corrected by the next reapply.
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
                -- Width/height-matched bars: the match owns that axis, so the
                -- bar's size never legitimately self-changes there. Any resize
                -- on a matched axis is the match (re)asserting the target's
                -- size -- the saved offset already corresponds to it, and
                -- compensating corrupts the offset (profile swap: the late
                -- width-match apply resizes the bar AT its correct anchor spot
                -- from the outgoing profile's width, dw/2 per swap).
                local wMatched = EllesmereUIDB.unlockWidthMatch and EllesmereUIDB.unlockWidthMatch[unlockKey]
                local hMatched = EllesmereUIDB.unlockHeightMatch and EllesmereUIDB.unlockHeightMatch[unlockKey]
                -- Horizontal growth (LEFT/RIGHT): adjust offsetX on TOP/BOTTOM anchors
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
                -- Vertical growth (UP/DOWN): adjust offsetY on LEFT/RIGHT anchors
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

    -- FocusKick: re-anchor against the focus nameplate after every layout
    -- pass so the bar tracks size/icon-count changes from the options panel.
    if barKey == FOCUSKICK_BAR_KEY and ns.ApplyFocusKickAnchor then
        ns.ApplyFocusKickAnchor()
    end
end

-- Shift-Icons cd-state modes: write the per-frame shift-hidden flag (on the
-- external FC table, never the Blizzard frame) and, ONLY when the value
-- actually changes, relayout that bar so the remaining icons close the gap.
-- Deferred to a clean execution context -- callers run inside SetDesaturated
-- hooks / the Fake-Active poll, where LayoutCDMBar's SetSize/SetPoint could
-- otherwise propagate taint (same pattern as the _visHidden relayout in
-- _CDMApplyVisibility). Coalesced per bar so several icons flipping on the
-- same tick lay out once. Steady-state calls (no change) return immediately.
--
-- Growth-edge preservation is LOCAL to this relayout call: capture the fixed
-- growth edge before LayoutCDMBar and, if the resize moved it, translate the
-- frame back through whatever point it already has (offset-only SetPoint on
-- the existing point/relTo -- no ClearAllPoints, no DB writes, no anchor-
-- system calls). A non-CENTER-grow bar's persistent point normally IS its
-- fixed growth edge, so the measured delta is exactly 0 and the frame is
-- never touched; this only corrects bars whose point is center/corner-based
-- at that moment (anchored bars mid-cascade, first-row corner pins, legacy
-- CENTER positions). Anchored bars still get their normal deferred anchor
-- batch reapply afterwards (OnSizeChanged fired during LayoutCDMBar), which
-- remains authoritative -- identical to a buff-count resize today.
ns._cdShiftLayoutPending = {}
function ns.SetCdStateShiftHidden(fc, shiftHidden)
    shiftHidden = shiftHidden or false
    if (fc._cdStateShiftHidden or false) == shiftHidden then return end
    fc._cdStateShiftHidden = shiftHidden
    -- Overflow-diverted frames render on the target bar, so the gap-close
    -- relayout must hit the bar the frame is actually laid out on. Normally
    -- unreachable for diverted frames (Phase 3b's no-op rule), but there is
    -- a one-reanchor window after a shift effect is first configured.
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

-- (CreateCDMIcon removed -- all bars now use hook-based reparenting of Blizzard CDM frames)

-------------------------------------------------------------------------------
--  Open Blizzard CDM Settings to a specific tab.
--  isBuff=true opens the Auras/Buffs tab; false opens the Spells/CDs tab.
--  Hides EllesmereUI options panel first so the Blizzard UI is visible.
-------------------------------------------------------------------------------
local function OpenBlizzardCDMTab(isBuff)
    -- Just toggle Blizzard's CDM settings panel.
    -- Do NOT call SetCurrentCategories/SetDisplayMode/ClearDisplayCategories
    -- after opening -- those taint the CDM frame pool.
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
--  Single global OnUpdate handler instead of per-icon. Checks which icon
--  (if any) the mouse is over, only when at least one bar has tooltips on.
-------------------------------------------------------------------------------
local _tooltipBars = {}  -- [barKey] = true for bars with tooltips enabled
-- Tooltip OnUpdate removed: Blizzard viewer frames handle their own
-- tooltips via native OnEnter. Custom injected frames (item presets,
-- racials, custom spells) don't need OnUpdate polling -- they get
-- OnEnter/OnLeave scripts installed in DecorateFrame / preset creation.
local _tooltipFrame = CreateFrame("Frame")
_tooltipFrame:Hide()

local function ApplyCDMTooltipState(barKey)
    local bd = barDataByKey[barKey]
    local enabled = bd and bd.showTooltip
    if enabled then
        _tooltipBars[barKey] = true
    else
        _tooltipBars[barKey] = nil
        -- Clear tooltip if it's showing for an icon on this bar
        if _tooltipCurrentIcon then
            local sfc = _ecmeFC[_tooltipCurrentIcon]
            if sfc and sfc.barKey == barKey then
                GameTooltip:Hide()
                _tooltipCurrentIcon = nil
            end
        end
    end
    -- Mouse-motion follows the tooltip setting. A motion-enabled icon with
    -- no unit becomes the mouseover-focus frame and steals hover from unit
    -- frames underneath (raid frame hover highlight and [@mouseover] casts
    -- die wherever a bar overlaps them), so icons may only capture the mouse
    -- when tooltips are actually on. Cursor-anchored bars stay fully mouse-
    -- through (SetFrameClickThrough owns their state); vis-hidden bars stay
    -- inert. Mouse calls on Blizzard CDM frames are blocked in combat.
    if not InCombatLockdown() then
        local frame = cdmBarFrames[barKey]
        local wantHover = (enabled and frame and not frame._mouseTrack
            and not frame._visHidden) and true or false
        local icons = cdmBarIcons[barKey]
        if icons then
            for i = 1, #icons do
                local ic = icons[i]
                if ic and ic.EnableMouseMotion then
                    ic:EnableMouseMotion(wantHover)
                end
            end
        end
    end
    -- Show/hide the global tooltip frame based on whether any bar wants tooltips
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
    -- Per-icon Border override (buff-family bars): size + color only, never
    -- style. ssb is the resolved per-icon settings passed in from
    -- RefreshCDMIconAppearance; nil for cd/utility bars and uncustomized icons,
    -- so this is a no-op unless a buff icon has a per-icon border set. Feeds both
    -- the square (ApplyBorderStyle) and shaped (shapeBorder) paths below.
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

        -- Restore square borders (PP or textured via ApplyBorderStyle)
        -- Border lives on fd.borderFrame (child of icon) to avoid tainting
        -- Blizzard's secure frames. Fall back to PP.GetBorders(icon) for
        -- CDM-owned frames that don't go through DecorateFrame's child wrapper.
        local bdrTarget = (fd and fd.borderFrame) or icon
        if fd and fd.borderFrame or EllesmereUI.PP.GetBorders(icon) then
            local texKey = barData.borderTexture or "solid"
            -- "Show Behind": set the border frame's level before styling so the
            -- textured backdrop inherits it. +13 in front of the icon, level-1 behind.
            if fd and fd.borderFrame then
                fd.borderFrame:SetFrameLevel(barData.borderBehind and math.max(0, icon:GetFrameLevel() - 1) or (icon:GetFrameLevel() + 13))
            end
            EllesmereUI.ApplyBorderStyle(bdrTarget, borderSz, brdR, brdG, brdB, brdA, texKey, barData.borderTextureOffset, barData.borderTextureOffsetY, barData.borderTextureShiftX, barData.borderTextureShiftY, "cdm", barData.borderThickness or "thin", true)
        end

        -- Restore icon texture -- fill the entire frame. The border renders
        -- on top via PP.CreateBorder so no inset is needed.
        if tex then
            tex:ClearAllPoints()
            tex:SetAllPoints(icon)
            local extraCrop = 0
            if ifc.matchExpanded then
                local baseW = barData.iconSize or 36
                extraCrop = (1 - 2 * zoom) / (2 * (baseW + 1))
            end
            if shape == "cropped" then
                -- Cropped applies a heavy vertical TexCoord crop. With default
                -- pixel/texel snapping the cropped image edge can round to a
                -- different physical pixel than the (unsnapped) cooldown swipe,
                -- producing a 1px swipe/icon split on fractional frame positions
                -- at certain effective scales. Disable snapping so the image
                -- renders to its exact rect, matching the swipe. No size change.
                if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(false) end
                if tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(0) end
                tex:SetTexCoord(zoom, 1 - zoom, zoom + 0.10 + extraCrop, 1 - zoom - 0.10 - extraCrop)
            else
                -- Restore default grid snapping for non-cropped shapes so an
                -- icon previously set to cropped stays crisp after switching.
                if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(true) end
                tex:SetTexCoord(zoom, 1 - zoom, zoom + extraCrop, 1 - zoom - extraCrop)
            end
        end

        -- Restore cooldown (full frame so swipe covers the entire icon)
        if cd then
            cd:ClearAllPoints()
            cd:SetAllPoints(icon)
            pcall(cd.SetSwipeTexture, cd, "Interface\\Buttons\\WHITE8x8")
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
-- The CDM "fake active" engine (EllesmereUICdmFakeActive.lua) draws its own
-- saturated icon + swipe on top of a CDM icon during a custom active window.
-- That overlay must copy the underlying icon's custom shape, otherwise a square
-- icon/swipe is drawn over the shaped icon and the mask looks "broken". We reuse
-- the underlying icon's shapeMask -- masking is screen-space and the overlay
-- covers the same region, so one mask masks both. A none/cropped shape clears
-- any mask we previously added and restores a plain square swipe.
function ns.ApplyShapeToOverlay(icon, oIcon, oCd, barData)
    if not icon then return end
    local ifc = FC(icon)
    local mask = ifc.shapeMask
    local shape = ifc.shapeApplied and ifc.shapeName or nil

    -- Drop any mask refs we added before (the shape may have changed / cleared).
    if mask then
        if oIcon then pcall(oIcon.RemoveMaskTexture, oIcon, mask) end
        if oCd then pcall(oCd.RemoveMaskTexture, oCd, mask) end
    end

    local maskTex = shape and CDM_SHAPES.masks[shape]
    if not shape or shape == "none" or shape == "cropped" or not mask or not maskTex then
        -- Square overlay. IconTexture already copied the underlying texcoords.
        if oIcon then oIcon:ClearAllPoints(); oIcon:SetAllPoints(oIcon:GetParent()) end
        if oCd then
            pcall(oCd.SetSwipeTexture, oCd, "Interface\\Buttons\\WHITE8x8")
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
-- The overlay (EllesmereUICdmFakeActive.lua) runs its own Cooldown widget, whose
-- number would otherwise render in Blizzard's default font. Mirror the same
-- Duration Text styling the real icon gets in RefreshCDMIconAppearance: font,
-- size (scale-compensated), colour, centre offset, and the show/hide toggle. ssb
-- is the resolved per-icon settings and falls back to the bar's values (nil is
-- fine). Call AFTER SetCooldown so Blizzard's countdown FontString exists.
function ns.StyleOverlayCooldownText(oCd, barData, ssb, iconScale)
    if not oCd then return end
    iconScale = iconScale or 1
    if iconScale < 0.01 then iconScale = 1 end
    local fontScale = 1 / iconScale
    local showCD = barData and barData.showCooldownText
    if ssb and ssb.showCooldownText ~= nil then showCD = ssb.showCooldownText end
    -- Only Show Numbers (bar setting): the countdown IS the icon on these bars.
    if barData and barData.onlyShowNumbers then showCD = true end
    oCd:SetHideCountdownNumbers(not showCD)
    if not showCD then return end
    local cdFont = GetCDMFont()
    local cdSize = ((ssb and ssb.cooldownFontSize) or (barData and barData.cooldownFontSize) or 12) * fontScale
    local cdR = (ssb and ssb.cooldownTextR) or (barData and barData.cooldownTextR) or 1
    local cdG = (ssb and ssb.cooldownTextG) or (barData and barData.cooldownTextG) or 1
    local cdB = (ssb and ssb.cooldownTextB) or (barData and barData.cooldownTextB) or 1
    local cdX = (ssb and ssb.cooldownTextX) or (barData and barData.cooldownTextX) or 0
    local cdY = (ssb and ssb.cooldownTextY) or (barData and barData.cooldownTextY) or 0
    for _, rgn in pairs({ oCd:GetRegions() }) do
        if rgn and rgn.GetObjectType and rgn:GetObjectType() == "FontString" then
            EllesmereUI.ApplyIconTextFont(rgn, cdFont, cdSize, "cdm")
            rgn:SetTextColor(cdR, cdG, cdB)
            rgn:ClearAllPoints()
            rgn:SetPoint("CENTER", oCd, "CENTER", cdX, cdY)
        end
    end
end

-------------------------------------------------------------------------------
--  Per-spell Threshold Text (engine countdown formatters)
--
--  "Threshold Seconds" arms the feature per spell; below that many seconds
--  remaining the countdown can show one decimal ("2.7") and/or change color.
--  Rendering is a NumericRuleFormatter attached to the icon's Cooldown widget
--  via SetCountdownFormatter: the ENGINE formats the number (no OnUpdate, no
--  per-tick Lua), it covers whatever the widget displays (cooldown, recharge,
--  aura duration, fake-active window), and it evaluates engine-side, so secret
--  durations format fine. The color change rides IN the format string (color
--  escape wrap), so no text-color swapping happens at the threshold edge.
--  Formatters are immutable per config and shared: one instance per distinct
--  (seconds, decimals, color) tuple, attached to any number of cooldowns.
-------------------------------------------------------------------------------
do
    local formatters = {}       -- [signature] = engine formatter object
    local formatterCount = 0
    local unsupported = false   -- API probe failed once -> feature stays inert
    -- Which formatter a cooldown currently has attached, so the refresh pass
    -- only touches widgets it actually manages (the all-off common case is one
    -- weak-table read). Weak keys: pooled frames drop out on their own. State
    -- lives here, never on the frames (many are Blizzard-owned).
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
        -- Larger units. Thresholds sit just above the unit boundary so an
        -- UP-rounded value in (59, 60] routes into the m:ss breakpoint instead
        -- of reading "60" for a moment (same for hours and days).
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

    -- Resolve a settings block's threshold config to a shared formatter, or nil
    -- when the feature is off for it. ss may be a per-spell family entry
    -- (tier-chained), a customActiveStates entry, or nil. Explicit false values
    -- (tier blocking) read as off through the tonumber/== true checks.
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
            -- Live color-picker drags mint a config per tick; cap the lookup so
            -- a long picker session can't grow it unbounded. Attached widgets
            -- keep their instances alive; evicted configs rebuild on demand.
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

    -- Attach or clear the resolved formatter on one Cooldown widget. Only
    -- touches the widget when its managed state changes, and never touches a
    -- widget it never managed.
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

    -- Effective threshold config for a frame's spell: the per-spell family
    -- store (tier-chained) first, then the preset/custom customActiveStates
    -- entry -- the same two homes Reverse Swipe reads. Returns the block that
    -- arms the feature, or nil.
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

-- (UpdateCustomBarIcons removed -- all bars now use hook-based CollectAndReanchor)

-- (UpdateCDMBarIcons removed -- replaced by hook-based CollectAndReanchor)
-- (UpdateAllCDMBars tick loop removed -- replaced by event-driven hooks)

-- Refresh visual properties of existing icons (called when settings change)
-- Styles the custom-spell "Show Charges" count text (created lazily by the
-- CdmHooks ticker) to match the bar's native stack/charge text: same font,
-- size, color, anchor position and X/Y offset. Called at creation time and
-- from every RefreshCDMIconAppearance pass so option changes apply live.
-- With no bar data the defaults resolve to the historical hardcoded look
-- (size 11, bottom-right, +2 nudge).
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
    -- Parent onto the text overlay so it renders above the border, like the
    -- item count text does.
    local fd = _getFD(icon)
    local txOverlay = (fd and fd.textOverlay) or icon._textOverlay
    if txOverlay then fs:SetParent(txOverlay) end
    fs:ClearAllPoints()
    fs:SetPoint(scPoint, txOverlay or icon, scPoint, scX, scY)
end

local function RefreshCDMIconAppearance(barKey)
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
        -- Scale compensation: fonts render at the frame's native scale,
        -- so multiply sizes by 1/scale to match the visual icon size.
        local iconScale = icon:GetScale() or 1
        if iconScale < 0.01 then iconScale = 1 end
        local fontScale = 1 / iconScale
        -- Per-icon override settings (buff-family bars only). Resolve once and
        -- reuse for Buff Glow + Duration Text + Charge/Stack below. nil => inherit
        -- the bar's value. Variant-aware: a setting stored under any spell in the
        -- icon's family (base / talent-override) resolves here -- the options side
        -- keys off the live/canonical id, which may differ from fc.spellID.
        local ssb
        local isBuffFamilyBar = (barData.barType == "buffs" or barKey == "buffs")
        -- Login / refresh coverage for Max Stacks Glow: a charge spell sitting at
        -- max never fires the swipe hook, so register it here too. Gated on the
        -- feature flag (set once by RescanMaxStacksGlowFlag / the option) so anyone
        -- who never enables it pays nothing here -- the call is skipped entirely.
        if ns._cdmAnyMaxStacksGlow and not isBuffFamilyBar and ns.WatchMaxStacksIfEnabled then
            ns.WatchMaxStacksIfEnabled(icon)
        end
        -- Same login/refresh coverage for "Hide CD Text (Charges)": a charge spell
        -- at max shows no recharge text and never fires the swipe hook, so register
        -- it here. Gated on the feature flag so unused = skipped entirely.
        if ns._cdmAnyChargeHideCdText and not isBuffFamilyBar and ns.WatchChargeCdTextIfEnabled then
            ns.WatchChargeCdTextIfEnabled(icon)
        end
        -- Immediately re-assert Hide Recharge Edge / Hide Swipe on charge icons so a
        -- toggle (per-icon or via Apply to Bar) updates a currently-recharging spell
        -- right away instead of waiting for its next recharge to fire the reactive
        -- SetDrawEdge/SetDrawSwipe hooks. Gated + self-skips non-charge frames = 0 cost
        -- unless charge style is actually in use.
        if ns._cdmAnyChargeStyle and not isBuffFamilyBar and ns.ReapplyChargeStyle then
            ns.ReapplyChargeStyle(icon)
        end
        -- Login/refresh coverage for "Audio Effect on CD Ready": register every
        -- cd/utility icon with the sound onto the event-driven watcher
        -- (SPELL_UPDATE_COOLDOWN + SPELL_UPDATE_CHARGES). Both charge and non-charge
        -- spells are handled there; icons without the sound self-skip inside.
        if ns._cdmAnyCdReadySound and not isBuffFamilyBar and ns.WatchCdReadySoundIfEnabled then
            ns.WatchCdReadySoundIfEnabled(icon)
        end
        -- Buff per-spell settings resolve for any BUFF FRAME, not just buff-family
        -- bars: a hosted buff (a real Blizzard buff frame reparented onto a CD/util
        -- bar, flagged fd._isBuffViewerFrame) -- and its inactive placeholder -- must
        -- get the same per-spell resolution so its Buff Glow / Duration Text /
        -- Charge-Stack / Border / Desaturate match the active frame.
        if isBuffFamilyBar or (fd and fd._isBuffViewerFrame) or icon._isPlaceholderFrame then
            -- Per-icon Audio on Buff Gain/Loss: attach the gain+loss sound hooks once,
            -- and only when the feature is in use anywhere (gate = 0 cost otherwise).
            if ns._cdmAnyBuffSound and ns.EnsureBuffSoundHook then ns.EnsureBuffSoundHook(icon) end
            local fcb = _ecmeFC[icon]
            -- Resolve by the DISPLAYED spell first (GetCanonicalSpellIDForFrame --
            -- the same id the options menu writes settings under) rather than
            -- fc.spellID (the cooldownInfo base). For buffs whose cooldownInfo base
            -- is a generic spec spell shared across icons (e.g. Consecration's
            -- standing-in aura -> Prot Paladin 137028), keying off the base both
            -- misses the real buff and lets one icon's setting shadow another's.
            -- Passing canon as the primary id makes settings[canon] the fast-path
            -- hit. Own placeholder/custom frames have no live spell -> fc.spellID.
            local sidb = (ns.GetCanonicalSpellIDForFrame and ns.GetCanonicalSpellIDForFrame(icon))
                or (fcb and fcb.spellID)
            if sidb then
                local sdb = ns.GetBarSpellData(barKey)
                -- Shared resolver: matches the key against the frame's full
                -- identity set (canon first, then resolvedSid / baseSpellID).
                ssb = ns.ResolveSpellSettings and ns.ResolveSpellSettings(icon, sidb, sdb, barKey)
            end
            -- Stash the effective Buff Glow on fd so the BuffTicker hot path reads
            -- it without a per-tick lookup. Only restart the live glow when the
            -- effective value actually changed (no flicker on no-op rebuilds).
            local nT = ssb and ssb.buffGlow           -- nil = inherit, number = override (0 = None)
            -- A false-block (per-spell "Off", or Exclude this spec / bar apply of an
            -- Off value) is render-equivalent to nil: treat it as inherit, never as a
            -- value. Without this fd._bgT would be `false` and the BuffTicker's
            -- `effGlowType > 0` compares a boolean with a number and errors.
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
        -- Update texture -- fill the entire frame. The border renders on
        -- top via PP.CreateBorder so no inset is needed.
        if tex then
            tex:ClearAllPoints()
            tex:SetAllPoints(icon)
            tex:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
        end
        -- Update cooldown (full frame so swipe covers the entire icon). The swipe
        -- and the countdown number both live on the Cooldown widget, so raise the
        -- whole widget ABOVE our border (icon+13) so the number renders on top of
        -- it -- it previously sat below the border and got drawn over (most visible
        -- when the text is offset to an edge). Anchoring the number to cd (below)
        -- keeps the X/Y offset working. Side effect: the dark swipe now sits over
        -- the thin border, lightly tinting it during an active cooldown.
        if cd then
            cd:ClearAllPoints()
            cd:SetAllPoints(icon)
            -- Above the border (icon+13); still below glow (icon+16) / text (icon+23).
            pcall(cd.SetFrameLevel, cd, icon:GetFrameLevel() + 14)
            -- Per-icon Duration Text override (ssb) falls back to the bar's values.
            local showCD = barData.showCooldownText
            if ssb and ssb.showCooldownText ~= nil then showCD = ssb.showCooldownText end
            -- Only Show Numbers (bar setting): the countdown IS the icon, so it
            -- overrides both the bar's Cooldown Text toggle and per-icon offs.
            if barData.onlyShowNumbers then showCD = true end
            cd:SetSwipeColor(0, 0, 0, barData.swipeAlpha or 0.7)
            -- Per-spell Reverse Swipe: flips this icon's swipe direction away from
            -- the bar default (buffs fill up, cooldowns deplete). Entire block is
            -- gated by the session flag, so it is ZERO cost / ZERO behavior change
            -- unless at least one spell has the toggle on -- the cooldown then keeps
            -- DecorateFrame's default. Resolves the frame's CURRENT spell each pass
            -- (so pool reuse + talent overrides stay correct) and re-asserts on every
            -- refresh, so toggling off restores the default. Not a per-tick path.
            if ns._cdmAnyReverseSwipe then
                -- A hosted buff (buff frame on a CD/util bar) uses the BUFF baseline
                -- (fill-up), not the cd baseline, so "Reverse" flips the same way it
                -- would on a real buffs bar.
                local rfBuff = (barData.barType == "buffs" or barKey == "buffs"
                    or barData.barType == "custom_buff" or (fd and fd._isBuffViewerFrame)) or false
                local rfReverse = rfBuff
                local rfFc = _ecmeFC[icon]
                local rfSid = rfFc and rfFc.spellID
                if rfSid then
                    -- Regular per-spell setting (per-bar spellSettings).
                    local rev
                    if ns.ResolveSpellSettings then
                        local rfSs = ns.ResolveSpellSettings(icon, rfSid, ns.GetBarSpellData(barKey))
                        rev = rfSs and rfSs.reverseSwipe
                    end
                    -- Preset / custom cd-utility spell setting (profile customActiveStates;
                    -- trinket slots resolve item-over-slot via the effective view).
                    if not rev and ns.GetEffectiveCustomActiveState then
                        local cas = ns.GetEffectiveCustomActiveState(rfSid)
                        rev = cas and cas.reverseSwipe
                    end
                    if rev then rfReverse = not rfBuff end
                end
                cd:SetReverse(rfReverse)
            end
            -- Per-spell Hide CD Swipe: removes the cooldown swipe entirely for
            -- cd/utility spells (non-charge -- charge spells use "Hide Swipe (Charges)").
            -- Gated by the session flag, so zero cost unless someone enables it. Applied
            -- here for immediate feedback; the SetDrawSwipe hook keeps it off against
            -- Blizzard's re-pushes. Re-asserts (not hide) each pass so toggling off
            -- restores the default swipe -- matching the hook's non-charge force-true.
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
            -- Per-spell Threshold Text: attach the engine countdown formatter
            -- that renders decimals / a color change below the spell's Threshold
            -- Seconds. Gated by the session flag, so zero cost / zero behavior
            -- change unless at least one spell arms it. Resolution order matches
            -- Reverse Swipe above: family store (variant-aware via the frame)
            -- first, then the preset/custom customActiveStates entry.
            if ns._cdmAnyThresholdText and ns.ApplyThresholdFormatter then
                local ttFc = _ecmeFC[icon]
                local ttSid = ttFc and ttFc.spellID
                local tt
                if ttSid and ns.ResolveThresholdTextSettings then
                    tt = ns.ResolveThresholdTextSettings(icon, ttSid, ns.GetBarSpellData(barKey), barKey)
                end
                ns.ApplyThresholdFormatter(cd, tt)
            end
            -- Per-spell "Hide CD Text (Charges)" can additionally hide the recharge
            -- numbers while a charge is in hand; the font block below still styles
            -- the text (using the bar's showCD) so it is ready when numbers return.
            local hideCD = not showCD
            if ns.CdmShouldHideCountdown then hideCD = ns.CdmShouldHideCountdown(icon, hideCD) end
            cd:SetHideCountdownNumbers(hideCD)
            -- Apply cooldown text font directly (old tick loop is gone)
            if showCD then
                local cdFont = GetCDMFont()
                local cdSize = ((ssb and ssb.cooldownFontSize) or barData.cooldownFontSize or 12) * fontScale
                local cdR = (ssb and ssb.cooldownTextR) or barData.cooldownTextR or 1
                local cdG = (ssb and ssb.cooldownTextG) or barData.cooldownTextG or 1
                local cdB = (ssb and ssb.cooldownTextB) or barData.cooldownTextB or 1
                local cdX = (ssb and ssb.cooldownTextX) or barData.cooldownTextX or 0
                local cdY = (ssb and ssb.cooldownTextY) or barData.cooldownTextY or 0
                -- Find Blizzard's countdown text FontString on the Cooldown widget.
                -- Keep it on the Cooldown widget (anchored to cd) so the user's
                -- X/Y offset works -- reparenting it makes Blizzard's engine
                -- re-center and ignore the offset. CENTER anchor also overrides
                -- the engine's stale baseline (raw SetFont vs SetCountdownFont).
                for _, rgn in pairs({ cd:GetRegions() }) do
                    if rgn and rgn.GetObjectType and rgn:GetObjectType() == "FontString" then
                        EllesmereUI.ApplyIconTextFont(rgn, cdFont, cdSize, "cdm")
                        rgn:SetTextColor(cdR, cdG, cdB)
                        rgn:ClearAllPoints()
                        rgn:SetPoint("CENTER", cd, "CENTER", cdX, cdY)
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
        -- Style Blizzard's native stack/charge text elements.
        -- Raise Blizzard's text sub-frames above our border frame (+5)
        -- by bumping their frame level. Safe because these are Blizzard's
        -- own children of the icon, and they follow frame reuse naturally.
        -- Per-icon Charge/Stack override (ssb) falls back to the bar's values.
        local scFont = GetCDMFont()
        local scSize = ((ssb and ssb.stackCountSize) or barData.stackCountSize or 11) * fontScale
        local scR = (ssb and ssb.stackCountR) or barData.stackCountR or 1
        local scG = (ssb and ssb.stackCountG) or barData.stackCountG or 1
        local scB = (ssb and ssb.stackCountB) or barData.stackCountB or 1
        local scX = ((ssb and ssb.stackCountX) or barData.stackCountX or 0) * fontScale
        local scY = ((ssb and ssb.stackCountY) or barData.stackCountY or 0) * fontScale
        -- Stack/charge/item-count text anchor. Default bottom-right keeps the
        -- historical +2 vertical nudge so existing bars stay pixel-identical;
        -- top and center positions sit flush with no baseline nudge.
        local scPoint = (ssb and ssb.stackCountPosition) or barData.stackCountPosition or "bottomright"
        if scPoint == "bottomleft" then scPoint = "BOTTOMLEFT"; scY = scY + 2
        elseif scPoint == "bottom" then scPoint = "BOTTOM"; scY = scY + 2
        elseif scPoint == "topright" then scPoint = "TOPRIGHT"
        elseif scPoint == "top" then scPoint = "TOP"
        elseif scPoint == "topleft" then scPoint = "TOPLEFT"
        elseif scPoint == "center" then scPoint = "CENTER"
        elseif scPoint == "left" then scPoint = "LEFT"
        elseif scPoint == "right" then scPoint = "RIGHT"
        else scPoint = "BOTTOMRIGHT"; scY = scY + 2 end
        local showItemCount = barData.showItemCount ~= false
        if ssb and ssb.showItemCount ~= nil then showItemCount = ssb.showItemCount end
        -- Text must render above borders. Levels are relative to the
        -- icon's own frame level (CdmHooks: border +13, text +23).
        local textLvl = icon:GetFrameLevel() + 23
        -- Applications (buff stacks / aura applications) -- not an item count.
        -- Blizzard manages show/hide based on whether stacks exist; we only
        -- restyle position/font and never gate visibility on showItemCount.
        if icon.Applications then
            pcall(icon.Applications.SetFrameLevel, icon.Applications, textLvl)
            if icon.Applications.Applications then
                local appsFS = icon.Applications.Applications
                SetBlizzCDMFont(appsFS, scFont, scSize, scR, scG, scB)
                appsFS:ClearAllPoints()
                appsFS:SetPoint(scPoint, icon, scPoint, scX, scY)
            end
        end
        -- ChargeCount (spell charges like Sigil/Roll) -- not an item count.
        -- Blizzard manages show/hide based on charge state.
        if icon.ChargeCount then
            pcall(icon.ChargeCount.SetFrameLevel, icon.ChargeCount, textLvl)
            if icon.ChargeCount.Current then
                local chargeFS = icon.ChargeCount.Current
                SetBlizzCDMFont(chargeFS, scFont, scSize, scR, scG, scB)
                chargeFS:ClearAllPoints()
                chargeFS:SetPoint(scPoint, icon, scPoint, scX, scY)
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
        -- Custom-spell "Show Charges" count text (our own lazy fontstring from
        -- the CdmHooks ticker) follows the same stack/charge text settings.
        if icon._castCountText then
            ns.StyleCustomChargeText(icon, barKey)
        end

        -- Update keybind text style
        if kbText then
            EllesmereUI.ApplyIconTextFont(kbText, GetCDMFont(), (barData.keybindSize or 10) * fontScale, "cdm")
            kbText:ClearAllPoints()
            -- Scale-compensate the offset so it's visually consistent
            -- across icons with different Blizzard-assigned scales.
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

        -- Apply custom shape (overrides border/zoom set above). Pass the resolved
        -- per-icon settings so the buff-family Border override (size + color)
        -- applies on the authoritative border render, square or shaped.
        local shape = barData.iconShape or "none"
        ApplyShapeToCDMIcon(icon, shape, barData, ssb)
        -- A restyle just reset this icon's mask + border level out from under any
        -- live fake-active overlay (border size / shape change while the active
        -- window is open). Re-sync the overlay so it re-shapes and re-lifts the
        -- border above itself instead of waiting for the next trigger.
        if ns.FakeActive_OnIconRestyled then ns.FakeActive_OnIconRestyled(icon) end

        -- Reset glow so glow type change takes effect on next tick.
        -- Do NOT reset isActive -- that causes a 1-frame flash where the
        -- ticker sees the transition as "inactive" and un-desaturates the
        -- icon before re-detecting active on the next frame.
        -- Preserve proc glow and active state glow across rebuilds.
        local ifd = _getFD(icon)
        local hadProcGlow = ifd and ifd.procGlowActive
        local hadActiveGlow = ifd and ifd._activeGlowOn
        if hadProcGlow and glowOv then
            -- Stop then restart with per-spell settings
            StopNativeGlow(glowOv)
            if ifd then ifd.procGlowActive = false end
            ShowProcGlow(icon)
        elseif hadActiveGlow then
            -- Don't touch: active glow is managed by the SetSwipeColor hook.
            -- Stopping it here causes a visible blink.
        elseif ifd and ifd._cdStateGlowOn then
            -- cdState glow active: stop it so the desat hook restarts
            -- with the updated style. Also re-evaluate immediately for
            -- off-CD spells (desat hook won't fire for those).
            if glowOv then StopNativeGlow(glowOv) end
            ifd._cdStateGlowOn = false
            local fc = _ecmeFC[icon]
            local sid = fc and fc.spellID
            local bk = fc and fc.barKey
            if sid and bk then
                local sd = ns.GetBarSpellData(bk)
                -- Shared resolver: direct hit + full identity/override matching
                -- against the family store, with bar-tier fallback.
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
                        -- Plain variants glow purely from cooldown state (legacy
                        -- behavior, zero extra reads). Resource Aware variants
                        -- also require usability, except during the loading-screen
                        -- settle window (API untrustworthy; the watched-set pass
                        -- after the window corrects it).
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
                    -- Event-driven re-evaluation: Resource Aware glows always,
                    -- plus plain glows on EUI custom frames (their SetDesaturation
                    -- never fires the SetDesaturated hook that would re-evaluate
                    -- them). Fake-Active-owned frames (PresetHasCdState) excluded.
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

        -- Apply initial cdState effect (hidden/glow) so the state is
        -- correct before the first desat tick and before the visibility
        -- system runs. Idempotent: re-evaluates current CD state.
        local fc = _ecmeFC[icon]
        local csSid = fc and fc.spellID
        local csBk = fc and fc.barKey
        if csSid and csBk and csBk:sub(1, 7) ~= "__ghost" then
            local csSd = ns.GetBarSpellData(csBk)
            -- Shared resolver: direct hit + full identity/override matching
            -- against the family store, with bar-tier fallback.
            local csSs = ns.ResolveSpellSettings and ns.ResolveSpellSettings(icon, csSid, csSd, csBk)
            local cse = csSs and csSs.cdStateEffect
            -- Shift-Icons variants behave exactly like their base hidden mode
            -- plus the layout flag; normalize so the branches below stay as-is.
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
                    local hide = (cse == "hiddenOnCD") == onCD
                    icon:SetAlpha(hide and 0 or IconShownAlpha(fc, barData))
                    if fc then
                        fc._cdStateHidden = hide or false
                        if ns.SetCdStateShiftHidden then
                            ns.SetCdStateShiftHidden(fc, cseShift and hide or false)
                        end
                    end
                elseif cse == "lowerAlphaOnCD" then
                    -- Identical to hiddenOnCD but with a customizable opacity instead
                    -- of 0. Reuse the _cdStateHidden flag as "cd-state owns this alpha"
                    -- so the opacity appliers leave the lowered value alone.
                    -- A visibility-hidden bar stays at 0 in both states.
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
                            -- Plain variants glow purely from cooldown state
                            -- (legacy). Resource Aware variants also require
                            -- usability outside the loading-screen settle window.
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
                    -- Resource Aware glows always watch cooldown events. Plain
                    -- glows normally re-evaluate through the SetDesaturated hook,
                    -- but EUI's custom frames (racial / trinket / potion / custom)
                    -- drive desaturation via SetDesaturation(float), which never
                    -- fires that hook -- without a watch their glow stays lit for
                    -- the whole cooldown. Frames owned by the Fake-Active preset
                    -- path (PresetHasCdState) are excluded; that engine glows them.
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
                -- A preset keeps its hidden state from the Fake-Active engine (its
                -- cdState lives in customActiveStates, not per-bar spellSettings),
                -- so don't clear it here or the icon flashes visible.
                if not (ns.PresetHasCdState and ns.PresetHasCdState(icon)) then
                    fc._cdStateHidden = false
                    icon:SetAlpha(IconShownAlpha(fc, barData))
                    if ns.SetCdStateShiftHidden then ns.SetCdStateShiftHidden(fc, false) end
                end
            end
        end
        -- Only Show Numbers (bar setting): re-hide the icon art AFTER the
        -- passes above re-applied borders/shapes/textures, so the countdown
        -- number is all that remains. One field read when the bar is off;
        -- also restores one-shot right after the bar toggles off.
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
    -- Desired position: directly after the "buffs" default bar and before
    -- any custom bars (skipping ghost bars). Find buffs and target the slot
    -- right after it.
    local bars = p.cdmBars.bars
    local targetIdx
    for i, b in ipairs(bars) do
        if b.key == "buffs" then targetIdx = i + 1; break end
    end
    if not targetIdx then targetIdx = #bars + 1 end
    -- Locate any existing focuskick entry
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
        -- Move it to the desired slot
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
        showCooldownText = true, showItemCount = true, cooldownFontSize = 12,
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

-- Returns the unit token the FocusKick bar tracks: "target" when the user
-- has enabled Show on Target, "focus" otherwise.
local function GetFocusKickUnit()
    local bd = barDataByKey and barDataByKey[FOCUSKICK_BAR_KEY]
    return (bd and bd.focusKickUseTarget) and "target" or "focus"
end
ns.GetFocusKickUnit = GetFocusKickUnit

-- Position the FocusKick bar against the focus target's nameplate.
-- Called whenever the focus changes, a nameplate appears/disappears, or
-- the nameplate moves. The bar's stored nameplateAnchorSide determines
-- which side of the nameplate the bar attaches to (LEFT/RIGHT/TOP/BOTTOM)
-- and stored offsets shift it from that anchor point.
-- Set the bar frame and all of its icons to the given alpha. CDM icons are
-- parented to the Blizzard viewer pool, not the bar frame, so hiding the
-- bar frame alone leaves the icons visible -- per-icon alpha is required.
local function SetFocusKickAlpha(a)
    local frame = cdmBarFrames[FOCUSKICK_BAR_KEY]
    if frame then
        frame:SetAlpha(a)
        if frame.EnableMouseMotion and not InCombatLockdown() then
            -- Container never captures motion (steals hover from frames
            -- underneath); icon hover is owned by the tooltip setting.
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

-- Find the scale-aware anchor frame inside a Blizzard nameplate. The
-- EllesmereUINameplates addon mixes a custom NameplateFrame into a child of
-- the Blizzard plate and applies the user's "Scale Target Nameplate" /
-- "Scale Nameplate On Cast" settings via NameplateFrame:ApplyScale(). The
-- Blizzard plate itself does NOT scale, so anchoring the FocusKick bar to
-- the plate ignores those scale settings. Walk the plate's children to
-- find the mixed-in frame and its visible health bar, which carries the
-- correct scaled bounds. Returns (healthFrame, scaledParent) or nil.
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
    -- Prefer the scaled health bar from our custom NameplateFrame so the
    -- icon tracks Target / Cast scale changes. Fall back to the raw plate
    -- when the nameplates addon isn't loaded or the plate hasn't been
    -- decorated yet.
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

-- Single event proxy. Cheap: just calls ApplyFocusKickAnchor on relevant
-- events. The proxy is created once and persists.
--
-- Range-fade handling: when the focus target walks out of range, Blizzard
-- fades the nameplate alpha without firing NAME_PLATE_UNIT_REMOVED. The bar
-- icons don't inherit plate visibility (they're parented to the Blizzard
-- viewer pool) so we throttle-poll the plate's visibility on OnUpdate and
-- propagate alpha changes to the icons manually. Only ticks when a focus
-- plate exists -- zero work when there is no focus.
local _focusKickProxy
local _focusKickLastPlateVisible
local _focusKickTickAccum = 0
local _FOCUSKICK_TICK_INTERVAL = 0.1
local function EnsureFocusKickProxy()
    if _focusKickProxy then return _focusKickProxy end
    _focusKickProxy = CreateFrame("Frame")
    _focusKickProxy:RegisterEvent("PLAYER_FOCUS_CHANGED")
    _focusKickProxy:RegisterEvent("PLAYER_TARGET_CHANGED")
    _focusKickProxy:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    _focusKickProxy:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    _focusKickProxy:SetScript("OnEvent", function(_, event, unit)
        local fkUnit = GetFocusKickUnit()
        if event == "PLAYER_FOCUS_CHANGED" then
            if fkUnit ~= "focus" then return end
            _focusKickLastPlateVisible = nil
            ApplyFocusKickAnchor()
        elseif event == "PLAYER_TARGET_CHANGED" then
            if fkUnit ~= "target" then return end
            _focusKickLastPlateVisible = nil
            ApplyFocusKickAnchor()
        elseif event == "NAME_PLATE_UNIT_REMOVED" then
            -- Only react when the tracked unit's plate is removed.
            -- Reacting to every plate removal caused the bar to flicker
            -- off during AoE when unrelated mobs died or faded.
            if unit and (unit == fkUnit or UnitIsUnit(unit, fkUnit)) then
                _focusKickLastPlateVisible = nil
                ApplyFocusKickAnchor()
            end
        elseif event == "NAME_PLATE_UNIT_ADDED" then
            if unit and (unit == fkUnit or UnitIsUnit(unit, fkUnit)) then
                _focusKickLastPlateVisible = nil
                ApplyFocusKickAnchor()
            end
        end
    end)
    _focusKickProxy:SetScript("OnUpdate", function(_, elapsed)
        _focusKickTickAccum = _focusKickTickAccum + elapsed
        if _focusKickTickAccum < _FOCUSKICK_TICK_INTERVAL then return end
        _focusKickTickAccum = 0
        -- Cheap reject: no tracked unit -> nothing to watch.
        local fkUnit = GetFocusKickUnit()
        if not UnitExists(fkUnit) then return end
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
    end)
    return _focusKickProxy
end
ns.EnsureFocusKickProxy = EnsureFocusKickProxy

-- Sound dropdown data: built-in EllesmereUI sounds + LibSharedMedia sounds
-- appended at runtime via EllesmereUI.AppendSharedMediaSounds.
local _SOUNDS_DIR = "Interface\\AddOns\\EllesmereUI\\media\\sounds\\"
local FOCUSKICK_SOUND_PATHS = {
    ["none"]      = nil,
    ["airhorn"]   = _SOUNDS_DIR .. "AirHorn.ogg",
    ["banana"]    = _SOUNDS_DIR .. "BananaPeelSlip.ogg",
    ["bikehorn"]  = _SOUNDS_DIR .. "BikeHorn.ogg",
    ["bite"]      = _SOUNDS_DIR .. "Bite.ogg",
    ["boxing"]    = _SOUNDS_DIR .. "BoxingArenaSound.ogg",
    ["catmeow"]   = _SOUNDS_DIR .. "CatMeow.ogg",
    ["catmeow2"]  = _SOUNDS_DIR .. "CatMeow2.ogg",
    ["gunshot"]   = _SOUNDS_DIR .. "FrontalsGunshot.wav",
    ["glass"]     = _SOUNDS_DIR .. "Glass.mp3",
    ["kaching"]   = _SOUNDS_DIR .. "Kaching.ogg",
    ["phone"]     = _SOUNDS_DIR .. "Phone.ogg",
    ["robotblip"] = _SOUNDS_DIR .. "RobotBlip.ogg",
    ["sonar"]     = _SOUNDS_DIR .. "Sonar.ogg",
    ["siren"]     = _SOUNDS_DIR .. "WarningSiren.ogg",
    ["water"]     = _SOUNDS_DIR .. "WaterDrop.ogg",
    ["wilhelm"]   = _SOUNDS_DIR .. "Wilhelm.ogg",
}
local FOCUSKICK_SOUND_NAMES = {
    ["none"]      = "None",
    ["airhorn"]   = "Air Horn",
    ["banana"]    = "Banana Peel Slip",
    ["bikehorn"]  = "Bike Horn",
    ["bite"]      = "Bite",
    ["boxing"]    = "Boxing Arena",
    ["catmeow"]   = "Cat Meow",
    ["catmeow2"]  = "Cat Meow 2",
    ["gunshot"]   = "Frontals Gunshot",
    ["glass"]     = "Glass",
    ["kaching"]   = "Kaching",
    ["phone"]     = "Phone",
    ["robotblip"] = "Robot Blip",
    ["sonar"]     = "Sonar",
    ["siren"]     = "Warning Siren",
    ["water"]     = "Water Drop",
    ["wilhelm"]   = "Wilhelm",
}
local FOCUSKICK_SOUND_ORDER = {
    "none", "airhorn", "banana", "bikehorn", "bite", "boxing", "catmeow",
    "catmeow2", "gunshot", "glass", "kaching", "phone", "robotblip", "sonar",
    "siren", "water", "wilhelm",
}
ns.FOCUSKICK_SOUND_PATHS = FOCUSKICK_SOUND_PATHS
ns.FOCUSKICK_SOUND_NAMES = FOCUSKICK_SOUND_NAMES
ns.FOCUSKICK_SOUND_ORDER = FOCUSKICK_SOUND_ORDER

-- Focus-cast sound trigger. When the focus target starts a cast and the
-- user's selected interrupt is off cooldown, play the configured sound.
-- One single proxy registered with RegisterUnitEvent on "focus" -- the
-- token follows focus changes automatically.
local _focusCastProxy
local function RefreshFocusCastProxyUnit()
    if not _focusCastProxy then return end
    local unit = GetFocusKickUnit()
    _focusCastProxy:UnregisterAllEvents()
    _focusCastProxy:RegisterUnitEvent("UNIT_SPELLCAST_START", unit)
    _focusCastProxy:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", unit)
end
ns.RefreshFocusCastProxyUnit = RefreshFocusCastProxyUnit
local function EnsureFocusCastProxy()
    if _focusCastProxy then return _focusCastProxy end
    _focusCastProxy = CreateFrame("Frame")
    local unit = GetFocusKickUnit()
    _focusCastProxy:RegisterUnitEvent("UNIT_SPELLCAST_START", unit)
    _focusCastProxy:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", unit)
    _focusCastProxy:SetScript("OnEvent", function()
        local bd = barDataByKey and barDataByKey[FOCUSKICK_BAR_KEY]
        if not bd then return end
        local soundKey = bd.focusCastSoundKey or "none"
        if soundKey == "none" then return end
        local spellID = bd.focusKickInterruptSpellID
        -- Auto-fallback: if user hasn't explicitly picked a spell, use the
        -- first positive spell on the bar. The picker exists for users who
        -- want a specific spell when multiple are on the bar.
        if not spellID or spellID <= 0 then
            local sd = ns.GetBarSpellData and ns.GetBarSpellData(FOCUSKICK_BAR_KEY)
            if sd and sd.assignedSpells then
                for _, sid in ipairs(sd.assignedSpells) do
                    if type(sid) == "number" and sid > 0 then
                        spellID = sid
                        break
                    end
                end
            end
        end
        if not spellID or spellID <= 0 then return end

        -- No interruptible check. The kickProtected flag on UnitCastingInfo
        -- and UnitChannelInfo is a secret boolean in Midnight and any
        -- laundering path that returns a value back into Lua produces a
        -- tainted result we cannot branch on. We accept that the sound will
        -- occasionally fire on uninterruptible casts -- the nameplate
        -- shield icon still tells the player visually.

        -- Cooldown check: only play if our interrupt is ready. cdInfo.isActive
        -- is a clean bool -- the duration/startTime fields are secret in
        -- Midnight and can't be compared in Lua, but isActive is safe.
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

-- Per-icon "Audio on Buff Gain / Loss": play a sound when a buff becomes active
-- (gain) or drops (loss). Blizzard's buff cooldown-viewer item frames fire
-- TriggerAuraAppliedAlert on the apply edge and TriggerAuraRemovedAlert on the
-- drop edge, so we hooksecurefunc both (taint-safe post-hook, no polling) and
-- play the matching per-icon sound. The frame's GetSpellID is a SECRET value
-- while the aura is active, so we resolve the clean canonical id via
-- GetCanonicalSpellIDForFrame (the same id the options menu writes the setting
-- under) -- never index a table with the live secret id. Hooked-frame + throttle
-- state live in a do-block, off the Blizzard frame table per the no-custom-props
-- rule. Reuses the FocusKick sound table so the option list stays identical to
-- Focus Cast Sound. The two edges use separate throttle tables so they never
-- suppress each other.
do
    local _soundHooked = setmetatable({}, { __mode = "k" })
    local _soundThrottle = {}            -- [spellID] = last GetTime() (gain dedupe)
    local _soundThrottleLost = {}        -- [spellID] = last GetTime() (loss dedupe)
    local SOUND_MIN_GAP = 0.3
    -- Resolve the per-icon sound for one edge and play it (throttled). `field` is
    -- the spell-setting key ("buffActiveSoundKey" gain / "buffLostSoundKey" loss);
    -- `throttle` is the matching dedupe table. Identical resolution for both edges.
    local function PlayBuffEdgeSound(f, field, throttle)
        -- Loading screen / login settle: buffs re-apply and viewer frames re-show
        -- across a zone/login, firing phantom apply/remove alerts. Drop them.
        if ns._cdmSoundSuppressed and ns._cdmSoundSuppressed() then return end
        local sid = ns.GetCanonicalSpellIDForFrame and ns.GetCanonicalSpellIDForFrame(f)
        if not sid then return end
        -- Preferred: the frame's decorated context (fast; ResolveSpellSettings also
        -- handles variant/override spells). Falls back to an id-only lookup for the
        -- FIRST gain after login, whose alert fires before DecorateFrame populates
        -- _ecmeFC -- keying off that context dropped the very first cue.
        local key
        local fc = _ecmeFC[f]
        local barKey = fc and fc.barKey
        if barKey then
            local sd = ns.GetBarSpellData and ns.GetBarSpellData(barKey)
            local ss = ns.ResolveSpellSettings and ns.ResolveSpellSettings(f, sid, sd, barKey)
            key = ss and ss[field]
        end
        if not key then key = ns.FindBuffSoundKey and ns.FindBuffSoundKey(sid, field) end
        if not key or key == "none" then return end
        local now = GetTime()
        local last = throttle[sid]
        if last and (now - last) < SOUND_MIN_GAP then return end
        throttle[sid] = now
        local path = FOCUSKICK_SOUND_PATHS[key]
        if path then PlaySoundFile(path, "Master") end
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
            PlayBuffEdgeSound(f, "buffActiveSoundKey", _soundThrottle)
        end)
        -- Loss edge: Blizzard fires TriggerAuraRemovedAlert when the buff drops.
        if type(frame.TriggerAuraRemovedAlert) == "function" then
            hooksecurefunc(frame, "TriggerAuraRemovedAlert", function(f)
                PlayBuffEdgeSound(f, "buffLostSoundKey", _soundThrottleLost)
            end)
        end
    end
end

-- "FOCUS" reminder text shown on caster/miniboss nameplates when the
-- player has no focus set. Activated by the FocusKick bar's
-- focusReminderEnabled toggle.
--
-- Performance design:
--   * _focusKickHasFocus is updated only on PLAYER_FOCUS_CHANGED so the
--     hot per-plate path doesn't call UnitExists("focus") each event.
--   * Per-plate font strings live in _focusReminders keyed by token and
--     are reused across show/hide cycles -- never recreated.
--   * Each font string caches its last applied size/text/color/offsets so
--     SetFont / SetText / SetTextColor / SetPoint are skipped when the
--     incoming values are unchanged. SetFont in particular is the most
--     expensive call here.
--   * NAME_PLATE_UNIT_ADDED skips the work entirely when focus is set or
--     the bar setting is off, so no per-plate function-call overhead in
--     the normal "I have a focus" case.
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
    -- Caster NPCs are tagged with class "PALADIN" by Blizzard internally,
    -- so UnitClassBase returns "PALADIN" for them.
    local classBase = UnitClassBase and UnitClassBase(unit)
    if classBase == "PALADIN" then return true end
    local cls = UnitClassification and UnitClassification(unit)
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
        -- IMPORTANT: SetFont must run before SetText. Initialize the font
        -- using the safe helper here so the very first SetText below has a
        -- valid font. (Calling SetText on a font string with no font set
        -- raises "FontString:SetText(): Font not set".)
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

    -- Font: only re-apply if size, font path, or outline changed.
    -- Goes through FRSetFontSafe so the user's global font + outline style
    -- (set under EllesmereUI -> Fonts) drives the look, with fallbacks if
    -- the path is missing or unsupported.
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

    -- Color: accent mode reads the live ELLESMERE_GREEN; custom mode reads
    -- the stored RGB. Re-SetTextColor only if the resolved color changed.
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
    -- Clear all, then re-show for currently visible nameplates.
    -- Iterate unit tokens directly: plate.namePlateUnitToken can be nil
    -- when polled outside of NAME_PLATE_UNIT_ADDED events, so the safer
    -- path is to walk nameplate1..nameplate40 and let UnitExists filter.
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

-- Refresh the cached context flags (instance type + role) and trigger a
-- visual refresh if either flag transitioned. Called on PLAYER_ENTERING_WORLD,
-- ZONE_CHANGED_NEW_AREA, and PLAYER_SPECIALIZATION_CHANGED.
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
    if _focusReminderProxy then return _focusReminderProxy end
    -- Initialize focus + context state once at proxy creation
    _focusKickHasFocus = UnitExists("focus") and true or false
    UpdateFocusKickContext()
    _focusReminderProxy = CreateFrame("Frame")
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


-- Ghost bars: ensure both buff and CD ghost bars exist in the bars array.
-- Called from BuildAllCDMBars before iterating bars.
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
-- Side-effect caches are now owned by EllesmereUICdmHooks.lua.
-- The hooks file writes to ns._tick* tables directly; these locals
-- are populated from ns after the hooks file loads (in CDMFinishSetup).
-- The ns._ecmeFC external frame cache is still owned by this file.
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

-------------------------------------------------------------------------------
--  Tick Hot Path
--
--  The frame created during `CDMFinishSetup` drives this via `OnUpdate`.
--  Although WoW calls that every frame, the function self-throttles to 0.1s and
--  then performs the recurring runtime work:
--  1) wipe per-tick caches
--  2) rescan Blizzard CDM viewer children
--  3) refresh tracked/custom bar icons
--
--  This is the performance-sensitive path that should keep working state in
--  locals/upvalues where practical.
-------------------------------------------------------------------------------
-- UpdateAllCDMBars: REMOVED. All work is now event-driven via hooks in
-- EllesmereUICdmHooks.lua. CollectAndReanchor runs only when Blizzard
-- fires OnCooldownIDSet, OnActiveStateChanged, Layout, or pool events.
-- The following stub exists only so any stale references don't error.
local function UpdateAllCDMBars(dt) end

-------------------------------------------------------------------------------
--  Bar Visibility (always / in combat / never) + Housing
-------------------------------------------------------------------------------

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
            -- FocusKick is owned exclusively by ApplyFocusKickAnchor.
            -- Don't touch its alpha or icons here -- the visibility check
            -- runs on unrelated events (combat enter/exit, vehicle, etc.)
            -- and would clobber the nameplate-driven show/hide state.
            if barData.key == FOCUSKICK_BAR_KEY then
                -- intentionally skipped
            -- Unlock mode: bars must stay visible for dragging
            -- Ghost bar stays hidden even in unlock mode
            elseif unlockActive and not barData.isGhostBar then
                frame:SetAlpha(1)
                -- Container stays motion-through even in unlock mode; drag
                -- handling lives on the unlock overlay frames, not the bar.
                if frame.EnableMouseMotion and not InCombatLockdown() then
                    frame:EnableMouseMotion(false)
                end
                frame._visHidden = false
            else

            local vis = barData.barVisibility or "always"
            local shouldHide = false

            -- Multi-select / dragonriding path: non-nil owns the mode step
            -- (priority 3); the legacy single-mode chain below is untouched.
            local visExt = EllesmereUI.EvalVisibilityExtended
                and EllesmereUI.EvalVisibilityExtended(barData, "barVisibility", visState, EllesmereUI.VIS_CAPS_INCLUSIVE)

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
                -- Hide this bar's icons individually. The viewer may stay
                -- at alpha 1 (other bars need it), so icon alpha must be
                -- managed per-bar. EnableMouse is protected on Blizzard CDM
                -- frames; gate on combat lockdown to avoid ADDON_ACTION_BLOCKED.
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
                -- Bar opacity is applied to icons only, not the frame.
                -- Custom injected icons are parented to the bar frame, so
                -- frame alpha would double-apply with icon alpha.
                frame:SetAlpha(1)
                -- The container never captures mouse motion: its rect spans
                -- the bar's full layout area (mostly empty space on dynamic
                -- bars like buffs), and a motion-enabled frame with no unit
                -- steals mouseover focus from unit frames underneath -- raid
                -- frame hover highlights and [@mouseover] casts died wherever
                -- the bar overlapped them. Icon hover is handled per-icon
                -- below, gated on the bar's tooltip setting.
                if frame.EnableMouseMotion and not InCombatLockdown() then
                    frame:EnableMouseMotion(false)
                end
                frame._visHidden = false
                -- Apply opacity to icons every pass (idempotent, handles
                -- fresh loads where wasHidden is false). EffectiveBarAlpha folds
                -- in the out-of-combat fade when that option is on.
                local visAlpha = EffectiveBarAlpha(barData)
                local icons = cdmBarIcons[barData.key]
                local icCombat2 = InCombatLockdown()
                if icons then
                    for ii = 1, #icons do
                        local ic = icons[ii]
                        if ic then
                            -- EnableMouse/EnableMouseMotion are protected on
                            -- Blizzard CDM frames; skip during combat to avoid
                            -- ADDON_ACTION_BLOCKED when dismounting mid-combat.
                            if not icCombat2 then
                                ic:EnableMouse(false)
                                -- An icon that receives mouse MOTION becomes the
                                -- mouseover-focus frame; with no unit of its own it
                                -- steals focus from whatever unit frame is underneath,
                                -- so [@mouseover] resolves to nothing and the unit
                                -- frame's hover highlight never fires. Icons may only
                                -- capture the mouse when this bar's tooltips are on,
                                -- and never on cursor-tracked bars (those must stay
                                -- fully click-AND-motion-through).
                                if ic.EnableMouseMotion then
                                    ic:EnableMouseMotion((barData.showTooltip and not frame._mouseTrack) and true or false)
                                end
                            end
                            local icfc = _ecmeFC[ic]
                            -- Off-by-default flags tested first: non-users short-circuit
                            -- straight to the original branch (identical code, no added
                            -- work). _missingHidden = hosted "Visibility When Missing:
                            -- Hidden" placeholder (slot reserved, rendered invisible).
                            if (barData.hidePlaceholderIcon or ic._missingHidden) and ic._isPlaceholderFrame then
                                -- Hide Icon: an Always-Show placeholder keeps its reserved
                                -- layout slot but stays fully invisible (icon, border, bg).
                                ic:SetAlpha(0)
                            elseif not (icfc and icfc._cdStateHidden) then
                                ic:SetAlpha(visAlpha)
                            end
                        end
                    end
                end
                if wasHidden then
                    -- Defer to a clean execution context: event handlers
                    -- (PLAYER_TARGET_CHANGED, mount events, etc.) can carry
                    -- taint from the Blizzard dispatch chain. LayoutCDMBar
                    -- calls SetSize/SetPoint which propagates the taint and
                    -- triggers ADDON_ACTION_BLOCKED.
                    local bk = barData.key
                    C_Timer.After(0, function() LayoutCDMBar(bk) end)
                end
            end

            end -- unlockActive else
        end
    end

    -- Viewer alpha: icons are parented to Blizzard viewers and inherit
    -- their alpha. Only hide a viewer if ALL bars that use its icons are
    -- hidden. Otherwise a hidden default bar (e.g. "buffs" set to "never")
    -- would kill icons on visible custom bars that share the same viewer.
    for viewerBarKey, viewerName in pairs(BLIZZ_CDM_FRAMES) do
        local viewer = _G[viewerName]
        if viewer then
            -- Check if ANY bar that routes icons from this viewer is visible
            -- Each bar has independent visibility. The viewer must stay
            -- visible if ANY bar that uses its icons is visible.
            -- Viewer-to-bar mapping: cooldowns/utility bars use
            -- Essential/Utility viewers. Buff bars use BuffIcon viewer.
            -- custom_buff bars use their own frames (not the viewer).
            local anyVisible = false
            for _, barData in ipairs(p.cdmBars.bars) do
                if barData.enabled then
                    local frame = cdmBarFrames[barData.key]
                    if frame and not frame._visHidden then
                        local bk = barData.key
                        -- Does this bar use this viewer's icons?
                        if bk == viewerBarKey then
                            -- Default bar matches its viewer directly
                            anyVisible = true; break
                        end
                        -- Custom bars: check which viewer they route from.
                        -- CD/utility custom bars route from Essential or
                        -- Utility viewer based on their assigned spells.
                        -- Custom buffs bars route from the BuffIcon viewer.
                        -- custom_buff (aura timer) bars use own frames, not viewers.
                        local bt = barData.barType
                        if bt ~= "custom_buff" then
                            if bt == "buffs" and viewerBarKey == "buffs" then
                                anyVisible = true; break
                            elseif bt ~= "buffs" and (viewerBarKey == "cooldowns" or viewerBarKey == "utility") then
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

-- Live-apply bar opacity to a bar's frame + icons. Skips hidden bars so
-- visibility state is never overridden (hidden stays at alpha 0).
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
                -- Off-by-default flags tested first: non-users short-circuit straight
                -- to the original branch (identical code, no added work).
                -- _missingHidden = hosted "Visibility When Missing: Hidden"
                -- placeholder (slot reserved, rendered invisible).
                if (barData.hidePlaceholderIcon or ic._missingHidden) and ic._isPlaceholderFrame then
                    -- Hide Icon: an Always-Show placeholder keeps its reserved
                    -- layout slot but stays fully invisible (icon, border, bg).
                    ic:SetAlpha(0)
                elseif not (icfc and icfc._cdStateHidden) then
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
--  Build all CDM bars
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
--  Keybind cache for CDM icons
--  Built once out-of-combat by scanning all action bar slots.
--  Stored as { [spellID] = "formatted key" } so icon display is just a lookup.
--  Deferred if called during combat; fires on PLAYER_REGEN_ENABLED instead.
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
--  Keybind cache for CDM icons
--  Resolves binding keys per action slot (main bar paged via the EAB bar's
--  actionpage attribute, else client page APIs). Read-only + text writes on
--  our own frames, so it is safe to run in combat (debounced upstream).
-------------------------------------------------------------------------------

-- Action bar slot -> binding name map. Non-bar-1 entries listed first so that
-- if a spell appears on multiple bars, the more specific bar wins over bar 1.
local _barBindingDefs = {
    { prefix = "MULTIACTIONBAR1BUTTON", startSlot = 61  },  -- bar 2 bottom left
    { prefix = "MULTIACTIONBAR2BUTTON", startSlot = 49  },  -- bar 3 bottom right
    { prefix = "MULTIACTIONBAR3BUTTON", startSlot = 25  },  -- bar 4 right
    { prefix = "MULTIACTIONBAR4BUTTON", startSlot = 37  },  -- bar 5 left
    { prefix = "MULTIACTIONBAR5BUTTON", startSlot = 145 },  -- bar 6
    { prefix = "MULTIACTIONBAR6BUTTON", startSlot = 157 },  -- bar 7
    { prefix = "MULTIACTIONBAR7BUTTON", startSlot = 169 },  -- bar 8
    { prefix = "ACTIONBUTTON",          startSlot = 1   },  -- bar 1 (last = lowest priority)
}

local function FormatKeybindKey(key)
    if not key or key == "" then return nil end
    key = key:gsub("SHIFT%-", "S")
    key = key:gsub("CTRL%-",  "C")
    key = key:gsub("ALT%-",   "A")
    key = key:gsub("Mouse Button ", "M")
    key = key:gsub("MOUSEWHEELUP",   "MwU")
    key = key:gsub("MOUSEWHEELDOWN", "MwD")
    key = key:gsub("NUMPADDECIMAL",  "N.")
    key = key:gsub("NUMPADPLUS",     "N+")
    key = key:gsub("NUMPADMINUS",    "N-")
    key = key:gsub("NUMPADMULTIPLY", "N*")
    key = key:gsub("NUMPADDIVIDE",   "N/")
    key = key:gsub("NUMPAD",         "N")
    key = key:gsub("BUTTON",         "M")
    return key ~= "" and key or nil
end

-- Store a keybind under a cache key with macro-deprioritization: a direct
-- (non-macro) bind always wins. If nothing is cached yet we store it; if a
-- macro bind was stored earlier and this one is a direct spell bind, it
-- overrides the macro. Macro binds never overwrite an existing entry. This
-- lets a user who has both a macro and the real spell bound see the real
-- spell's key.
local function _SetKeybind(cacheKey, formatted, fromMacro)
    if not formatted then return end
    if _cdmKeybindCache[cacheKey] == nil then
        _cdmKeybindCache[cacheKey] = formatted
        _cdmKeybindFromMacro[cacheKey] = fromMacro or nil
    elseif _cdmKeybindFromMacro[cacheKey] and not fromMacro then
        _cdmKeybindCache[cacheKey] = formatted
        _cdmKeybindFromMacro[cacheKey] = nil
    end
end

local function RebuildKeybindCache()
    wipe(_cdmKeybindCache)
    wipe(_cdmKeybindFromMacro)
    for _, def in ipairs(_barBindingDefs) do
        for i = 1, 12 do
            local bindName = def.prefix .. i
            local key = GetBindingKey(bindName)
            if key then
                local slot = def.startSlot + i - 1
                if def.prefix == "ACTIONBUTTON" then
                    -- Main bar pages with forms/vehicles. Prefer the EAB main
                    -- bar's actionpage attribute (set by its secure page
                    -- handler, covers override/vehicle pages too). Without it
                    -- (Action Bars module disabled), derive the page from the
                    -- client: bonus bars (forms) map to pages 7+, else the
                    -- manually selected page.
                    local mbf = _G["EABBar_MainBar"]
                    local pg = mbf and tonumber(mbf:GetAttribute("actionpage"))
                    if not pg then
                        local bonus = GetBonusBarOffset and GetBonusBarOffset() or 0
                        if bonus > 0 then
                            pg = 6 + bonus
                        else
                            pg = (GetActionBarPage and GetActionBarPage()) or 1
                        end
                    end
                    slot = i + (pg - 1) * 12
                end
                local slotType, id, subType = GetActionInfo(slot)
                local spellID
                local fromMacro = false
                if slotType == "spell" then
                    spellID = id
                elseif slotType == "macro" then
                    fromMacro = true
                    if subType == "spell" then
                        -- "Smart" single-spell macro: Blizzard already
                        -- resolved it, and `id` here IS the spellID, not a
                        -- macro index -- passing it to GetMacroSpell would
                        -- look up the wrong thing.
                        spellID = id
                    else
                        -- Everything else (single-item, mount/companion,
                        -- multi-line/conditional...): `id` from GetActionInfo
                        -- is NOT a reliable identifier here. Resolve the real
                        -- macro index via its name instead (same workaround
                        -- EllesmereUICdmHooks.lua's SlotSpellID already uses).
                        local macroName = GetActionText(slot)
                        local macroIndex = macroName and GetMacroIndexByName(macroName)
                        if macroIndex and macroIndex > 0 then
                            spellID = GetMacroSpell(macroIndex)
                            if not spellID then
                                -- Not a spell-shaped macro: pull the first
                                -- /use target out of the macro body and
                                -- resolve it as an item instead.
                                local body = GetMacroBody and GetMacroBody(macroIndex)
                                local target = body and body:match("/use!?%s+([^\r\n]+)")
                                if target then
                                    target = target:gsub("^%[.-%]%s*", ""):match("^%s*(.-)%s*$")
                                    -- "item:NNNN" is macro-only shorthand for
                                    -- targeting an itemID directly. It is NOT
                                    -- a valid GetItemInfoInstant input (that
                                    -- wants a bare itemID, item name, or a
                                    -- full item link) -- pull the numeric ID
                                    -- out ourselves instead of handing the
                                    -- literal "item:NNNN" string to it.
                                    local itemID = target:match("^item:(%d+)")
                                    itemID = itemID and tonumber(itemID)
                                    if not itemID and not tonumber(target) then
                                        itemID = C_Item and C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(target)
                                    end
                                    if itemID then
                                        _SetKeybind(-itemID, FormatKeybindKey(key), true)
                                    end
                                end
                            end
                        end
                    end
                elseif slotType == "item" and id then
                    -- Store under negated itemID (-id) to match the FC
                    -- convention for item presets/trinkets.
                    _SetKeybind(-id, FormatKeybindKey(key), false)
                end
                if spellID then
                    local formatted = FormatKeybindKey(key)
                    _SetKeybind(spellID, formatted, fromMacro)
                    local name = C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
                    if name then _SetKeybind(name, formatted, fromMacro) end
                    local ovr = C_Spell.GetOverrideSpell and C_Spell.GetOverrideSpell(spellID)
                    if ovr and ovr ~= spellID then _SetKeybind(ovr, formatted, fromMacro) end
                    local base = C_Spell.GetBaseSpell and C_Spell.GetBaseSpell(spellID)
                    if base and base ~= spellID then _SetKeybind(base, formatted, fromMacro) end
                end
            end
        end
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
                    -- Item presets: check alt item IDs (user may have a
                    -- different rank of the same potion on their bar).
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

local function UpdateCDMKeybinds()
    RebuildKeybindCache()
    _keybindCacheReady = true
    -- Defer apply by one frame so the Blizzard tick has populated FC(icon).spellID
    C_Timer.After(0, ApplyCachedKeybinds)
end
ns.UpdateCDMKeybinds = UpdateCDMKeybinds
-- Expose apply-only for the tick loop (new spellID assigned to an icon mid-session)
ns.ApplyCachedKeybinds = ApplyCachedKeybinds
ns.CDMKeybindCache = _cdmKeybindCache

BuildAllCDMBars = function()
    ns._spellOrderDirty = true  -- force spell order cache rebuild
    -- Hard guard: never build with an unknown spec. CDMFinishSetup is
    -- gated on GetActiveSpecKey() at OnEnable, so this is a defense in
    -- depth for any other path that calls BuildAllCDMBars too early.
    if not ns.GetActiveSpecKey() then return end

    -- Mark CDM as rebuilding so width/height match propagation gates off
    -- (it would otherwise read transient bar widths sized for the previous
    -- spec's icon count and bake them into _matchPhysWidth on dependent
    -- bars). Cleared at the end of CollectAndReanchor when _pendingApplyOnReanchor
    -- fires the authoritative ApplyAllWidthHeightMatches pass.
    if EllesmereUI then EllesmereUI._cdmRebuilding = true end

    -- Ensure ghost bars exist before iterating bars
    EnsureGhostBars()
    EnsureFocusKickBar()
    ns.RescanMaxStacksGlowFlag()  -- set the Max Stacks Glow gate (once) before refresh
    ns.RescanChargeCdTextFlag()   -- set the Hide CD Text (Charges) gate (once) before refresh
    ns.RescanBuffSoundFlag()      -- set the Audio on Buff Gain/Loss gate (once) before refresh
    ns.RescanCdReadySoundFlag()   -- set the Audio Effect on CD Ready gate (once) before refresh
    ns.RescanCustomItemFlag()     -- set the custom-item buff-injection gate (once)
    ns.RescanCustomForceCountFlag() -- set the "Show Charges" custom-spell gate (once)
    ns.RescanReverseSwipeFlag()   -- set the Reverse Swipe gate (once) before refresh
    ns.RescanThresholdTextFlag()  -- set the Threshold Text gate (once) before refresh
    ns.RescanCustomIconFlag()     -- set the per-spell Custom Icon gate (once) before refresh

    local p = ECME.db.profile

    -- Heal ghost bar entries: an override write to a numeric bar path whose
    -- bar no longer existed (profile import, or a deleted bar with a stored
    -- override still referencing its index) used to auto-create a skeleton
    -- table (e.g. { barVisibility = "always" }) with no key. Every keyed
    -- consumer (spell data, racial normalize, unlock snapshots) then errors
    -- on the nil key. The override writer no longer fabricates numeric
    -- containers; this prunes profiles that already carry ghosts.
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

    -- Migrate the old global Always Show Buffs settings to per-bar before
    -- anything reads them (placeholder injection / desaturate ticker).
    if ns.MigrateAlwaysShowBuffsToPerBar then ns.MigrateAlwaysShowBuffsToPerBar() end
    -- Then merge legacy custom_buff (Auras) bars into the buff-family bars.
    if ns.MigrateCustomBuffBarsToBuffBars then ns.MigrateCustomBuffBarsToBuffBars() end

    -- Force Blizzard's EditMode CooldownViewer to "Always Visible" so
    -- hideWhenInactive and other viewer settings don't fight with CDM.
    EnforceCooldownViewerEditModeSettings()

    -- Hide Blizzard CDM
    if p.cdmBars.hideBlizzard then
        HideBlizzardCDM()
    end

    -- If user wants Blizzard's tracking bars instead of TBB, restore the
    -- secondary BuffBarCooldownViewer that HideBlizzardCDM moved offscreen.
    -- This only affects the bar-style buff viewer; CDM icon bars are untouched.
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
        -- Max Icons overflow: cheap session gate. Validity of the target is
        -- checked at reanchor time (Phase 3b); this only answers "is it
        -- worth looking" so the feature is two nil-checks when unused.
        if not ns._cdmAnyOverflowCfg and barData.enabled
           and barData.maxIcons and barData.maxIcons > 0
           and barData.overflowTarget then
            ns._cdmAnyOverflowCfg = true
        end
        BuildCDMBar(i)
        local frame = cdmBarFrames[barData.key]
        if frame then frame._prevVisibleCount = nil end
        if hookActive and BLIZZ_CDM_FRAMES[barData.key] then
            -- Hooked default bar: skip icon state reset and layout.
            -- CollectAndReanchor will repopulate from viewer pools.
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
    -- Resync the key-press-mirror fast enable-flag with the rebuilt bar list, so
    -- OnPress O(1)-gates instead of looping every bar per press (covers profile
    -- and spec swaps, not just the options toggle).
    if ns.RefreshCdmPressMirrorFlag then ns.RefreshCdmPressMirrorFlag() end
    -- When hooks are active, queue a reanchor to repopulate default bars.
    -- The queued CollectAndReanchor will lift _cdmRebuilding when it
    -- finishes; if no reanchor is queued (hooks not yet installed) we
    -- must clear the flag here ourselves so width matching can run again.
    if hookActive and ns.QueueReanchor then
        ns.QueueReanchor()
    else
        if EllesmereUI then EllesmereUI._cdmRebuilding = nil end
    end
    -- Re-apply saved positions now that LayoutCDMBar has set correct frame
    -- sizes. Positions are stored using the edge anchor directly (LEFT for
    -- RIGHT-grow, etc.), so SetPoint places the frame at its fixed edge and
    -- subsequent SetSize calls grow naturally from that edge.
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
    -- Second pass: reapply unlock-mode anchors now that ALL bars are
    -- positioned and sized.  The first pass (inside LayoutCDMBar) may
    -- have run ReapplyOwnAnchor before the target bar was repositioned
    -- (e.g. cooldowns processed before utility).  This corrects that.
    if EllesmereUI.ReapplyOwnAnchor then
        for _, barData in ipairs(p.cdmBars.bars) do
            EllesmereUI.ReapplyOwnAnchor("CDM_" .. barData.key)
        end
    end
    UpdateCDMKeybinds()

    -- Apply visibility (hides bars set to "in combat only", "never", etc;
    -- handles unlock-mode override and viewer alpha sync). Single authority.
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

-- Rewrite stored racial spell IDs on CD/utility bars to this character's
-- active racial. A shared profile keeps whichever race's racial each character
-- added; this collapses them to a single "Racial" slot that follows each
-- character's race without re-adding it. Operates on the active spec's
-- assigned lists (other specs normalize when they next become active and
-- rebuild). No-op on buff bars and when no active racial resolves.
--
-- Family-global: across ALL non-buff bars the racial ends up on at most ONE
-- bar. If the active racial is already placed (the current character's own
-- pick), it is kept where it sits and every other racial -- foreign racials
-- left behind by other characters AND stray duplicates -- is stripped. If no
-- active racial is present, the first foreign racial is promoted in place so
-- the slot still appears for this character.
function ns.NormalizeRacialAssignments()
    -- Re-resolve now: at build time the spellbook is reliably populated, so
    -- the variant pick (Blood Fury / Arcane Torrent / Gift of the Naaru) is
    -- correct even if OnEnable ran before the spellbook loaded.
    local active = ResolveActiveRacial()
    if not active or active <= 0 then return end
    local p = ECME.db and ECME.db.profile
    if not (p and p.cdmBars and p.cdmBars.bars) then return end

    -- Gather the non-buff bars' assigned lists once (in bar order).
    local lists = {}
    for _, b in ipairs(p.cdmBars.bars) do
        local isBuff = (b.barType == "custom_buff")
            or (ns.IsBarBuffFamily and ns.IsBarBuffFamily(b))
        -- b.key guard: a ghost bar (keyless skeleton from a stale override
        -- write) would index barSpells with nil and error.
        if not isBuff and b.key then
            local sd = ns.GetBarSpellData(b.key)
            if sd and sd.assignedSpells then lists[#lists + 1] = sd.assignedSpells end
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

    -- Single pass across every bar: keep exactly one racial slot total.
    local kept = false
    for _, list in ipairs(lists) do
        for i = #list, 1, -1 do
            local sid = list[i]
            if sid and sid > 0 and ALL_RACIAL_SPELLS[sid] then
                if sid == active and activePresent and not kept then
                    -- Keep the current character's own racial where it sits.
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
        wipe(ns._presetFrames)
    end

    -- (Site #8 init snapshot deleted: default bars no longer need
    -- assignedSpells pre-populated. The route map's diversion-set model
    -- routes everything in the viewer category to the default bar by
    -- spillover, so empty assignedSpells just means "show whatever
    -- Blizzard's viewer has" -- exactly the desired behavior.)

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
                    end
                end
            end
        end
        -- Cancel the reanchor BuildAllCDMBars queued -- we run our own
        -- direct one immediately below. Without this, the queued reanchor
        -- would fire ~200ms later and run the entire reanchor pipeline
        -- a second time.
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
            -- Orientation
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

--- Re-seed assignedSpells from live cdmBarIcons. Appends any positive
--- spell IDs present on the live bars but missing from assignedSpells.
--- Called after CollectAndReanchor so the preview stays in sync with
--- what the player actually sees on their CDM bars.
function ns.ReseedAssignedSpellsFromLiveIcons(cdUtilOnly)
    local p = ECME and ECME.db and ECME.db.profile
    if not p or not p.cdmBars then return end

    -- Both-state guards (mirror EnsureAssignedSpells). This appends live-icon
    -- spells back into assignedSpells; without these it could re-materialize a
    -- spell that is currently HIDDEN (ghosted) or already OWNED by another bar,
    -- recreating a both-state. The sole caller (RepopulateFromBlizzard) pre-wipes
    -- the ghost and Blizzard-sourced assignments, so these are normally no-ops --
    -- but they keep Reseed safe regardless of caller or ordering.
    local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
    local sk = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
    local aprof = sp and sk and sp[sk]
    -- Skip entirely while an imported layout is pending its first-load ghosting:
    -- its tracked spells spill onto default bars until the migration ghosts them,
    -- and materializing those spills would defeat the import-authoritative hide.
    if aprof and aprof._importGhostMode then return end

    -- Spell -> owning bar (variant-aware), built once. A live icon whose stored
    -- owner is a DIFFERENT bar is a transient spillover we must not materialize.
    local ownerOf
    if aprof and aprof.barSpells and ns.StoreVariantValue then
        for k, bsd in pairs(aprof.barSpells) do
            if k ~= GHOST_CD_BAR_KEY
               and type(bsd) == "table" and type(bsd.assignedSpells) == "table" then
                for _, csid in ipairs(bsd.assignedSpells) do
                    if type(csid) == "number" and csid > 0 then
                        ownerOf = ownerOf or {}
                        ns.StoreVariantValue(ownerOf, csid, k, false)
                    end
                end
            end
        end
    end

    local ghostSd = ns.GetBarSpellData and ns.GetBarSpellData(GHOST_CD_BAR_KEY)
    local ghostList = ghostSd and ghostSd.assignedSpells
    local FindVar = ns.FindVariantIndexInList

    -- Cd-claimed collided-buff slots (cd-claim markers in assignedSpells,
    -- see ns.CdClaimMarker) are tracked by COOLDOWN ID, not by the shared
    -- spellID. Materializing such an icon's shared spellID here would, at
    -- the next route rebuild, drag the UNCLAIMED twin onto the claiming bar
    -- too -- defeating the claim's one-slot-only contract. Built once;
    -- stays nil (guard inert, zero cost) unless a collided claim exists
    -- anywhere.
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
        -- cdUtilOnly (the automatic reseed path): buff-family bars are
        -- picker-authoritative -- materializing live buff icons would
        -- reintroduce the secret-ID drift duplicate-slot bug the options
        -- materializer's skip exists to prevent. The manual Repopulate
        -- flow passes nothing and keeps its full sweep.
        if not barData.isGhostBar
           and barData.key ~= "buffs"
           and (barData.barType == "cooldowns" or barData.barType == "utility"
                or (barData.barType == "buffs" and not cdUtilOnly)
                or MAIN_BAR_KEYS[barData.key]) then
            local sd = ns.GetBarSpellData(barData.key)
            local icons = ns.cdmBarIcons and ns.cdmBarIcons[barData.key]
            if sd and icons then
                if not sd.assignedSpells then sd.assignedSpells = {} end
                -- Insert each missing spell right after its left neighbour in the
                -- live icon order (which CollectAndReanchor has already placed in
                -- Blizzard-layout order), instead of appending at the end. This keeps
                -- the seeded list matching what the player sees so re-talenting a
                -- cooldown restores it to its Blizzard-CDM slot rather than the tail.
                --
                -- Presence is VARIANT-AWARE and the cursor is a POSITION, not an id.
                -- The old exact-match seen set missed a stored entry when the live
                -- icon reported a different variant form (fc.spellID can be the
                -- talent override, e.g. Mongoose Bite 259387, while the stored slot
                -- holds the base Raptor Strike 186270 the options normalize pass
                -- wrote). Every reload then re-inserted the live form at Blizzard's
                -- position, the order map ranked the frame by that copy, and the
                -- next options normalize deduped in favor of it -- permanently
                -- snapping the user's saved order back to Blizzard order (the
                -- Raptor Strike / Kill Command swap, 8.4.9). The by-value cursor
                -- lookup failed the same way and dumped inserts at slot 1.
                local insertPos = nil
                for _, icon in ipairs(icons) do
                    local fc = ns._ecmeFC and ns._ecmeFC[icon]
                    local sid = fc and fc.spellID
                    -- Skip hosted-buff frames and their placeholders: their bar
                    -- membership is the hosted MARKER entry, and their positive
                    -- spellID would materialize the same spell's COOLDOWN form.
                    -- But DO advance the cursor over their marker: on a mixed
                    -- bar (spells + hosted buffs) a spell re-inserted after a
                    -- buff must land after the buff's marker, not squeezed back
                    -- next to the previous CD spell (reported: Shift snapping
                    -- to right after Voidray, jumping its three buffs).
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
                    -- Skip overflow-diverted icons: they render on this bar
                    -- only for the session but belong to their source bar's
                    -- assignedSpells (mirrors the EnsureAssignedSpells skip).
                    if sid and fc and fc._overflowLayoutBar then
                        sid = nil
                    end
                    -- Skip cd-claimed collided-buff icons: their membership
                    -- is the cooldownID claim, never a spellID slot (mirrors
                    -- the hosted-buff membership rule above).
                    if sid and claimedCd and icon.cooldownID
                       and claimedCd[icon.cooldownID] then
                        sid = nil
                    end
                    if type(sid) == "number" and sid ~= 0 then
                        -- FindVar handles negatives by exact scan internally, and
                        -- variant matching is a strict superset of exact equality
                        -- for stored positives -- no exact fallback needed.
                        local at = FindVar and FindVar(sd.assignedSpells, sid)
                        if at then
                            -- Already has a slot (any variant form, or a custom
                            -- trinket/item marker): advance the cursor so the next
                            -- NEW spell lands after it, matching on-screen order.
                            insertPos = at
                        elseif sid > 0 then
                            -- Never materialize a hidden (ghosted) spell, or a spell a
                            -- DIFFERENT bar already owns (variant-aware).
                            local owner = ownerOf and ns.ResolveVariantValue
                                          and ns.ResolveVariantValue(ownerOf, sid)
                            local ghosted = ghostList and FindVar and FindVar(ghostList, sid)
                            if not ghosted and not (owner and owner ~= barData.key) then
                                -- Store the BASE form, matching what the options
                                -- normalize pass writes -- otherwise this pass
                                -- persists the talent-override form and the two
                                -- writers diverge (exports could ship either).
                                local nsid = sid
                                if C_Spell and C_Spell.GetBaseSpell then
                                    local b = C_Spell.GetBaseSpell(sid)
                                    if b and b > 0 then nsid = b end
                                end
                                local pos = insertPos and (insertPos + 1) or 1
                                table.insert(sd.assignedSpells, pos, nsid)
                                insertPos = pos
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Parent-facing bridge for the automatic / export-time reconcile: cd and
-- utility bars only (buff-family excluded -- picker-authoritative). The
-- export path nil-checks this, so a disabled CDM child is a clean no-op.
EllesmereUI.CDMReconcileActiveSpecSpells = function()
    ns.ReseedAssignedSpellsFromLiveIcons(true)
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

    -- A spell ID is "user-added" (preserved across repopulate) if it's a
    -- negative preset marker, a custom spell ID added via the picker, or a
    -- racial belonging to this character.
    local function IsUserAdded(sd, id)
        if type(id) ~= "number" or id == 0 then return false end
        if id < 0 then return true end
        if sd.customSpellIDs and sd.customSpellIDs[id] then return true end
        if _myRacialsSet and _myRacialsSet[id] then return true end
        -- A positive id carrying a stored duration is one of OUR injected
        -- preset/custom buffs (Bloodlust/Heroism, potions, Time Spiral, custom
        -- buff IDs). Blizzard-tracked buffs are never written into assignedSpells
        -- with a duration, so this can only be a user-added entry -- preserve it.
        -- Presets predate the customSpellIDs flag, so the flag alone is not enough.
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

    -- Filter Blizzard entries off all CD/utility bars (main + custom).
    -- Skip ghost, custom_buff, and default buff bar. The default buff bar
    -- (key == "buffs") has no assignedSpells to filter -- Blizzard's viewer
    -- is the authority. Extra buff bars ARE filtered for user assignments.
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
                -- spellSettings is per-spell config (font color, etc.) -- preserve
                -- entirely so user-added customs keep their styling.
            end
        end
    end

    -- Ghost bars hold Blizzard-owned spells the user explicitly hid.
    -- Filter the same way so user-added presets that may have been routed
    -- here (rare edge case) are preserved.
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

    -- (Site #10 re-snapshot deleted: under the new model, "repopulate from
    -- Blizzard" is just "wipe diversions and let the route map's spillover
    -- show everything from the viewer." The wipes above already cleared
    -- assignedSpells / removedSpells / spellSettings and the ghost CD bar
    -- -- nothing else needed.)

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
            -- Collect linked unlock element keys (children anchored to this bar)
            local linked = nil
            if anchorChildren[key] then
                linked = {}
                for _, childKey in ipairs(anchorChildren[key]) do
                    linked[#linked + 1] = "CDM_" .. childKey
                end
            end

            -- Buff-type bars can't be anchor targets (their icon count changes
            -- dynamically with auras, causing cascading position shifts).
            local isBuff = ns.IsBarBuffFamily(barData)
            local isDynamic = isBuff or (barData.barType == "custom_buff")
            elements[#elements + 1] = MK({
                key = "CDM_" .. key,
                label = "CDM: " .. barData.name,
                group = "Cooldown Manager",
                order = 600,
                linkedKeys = linked,
                noAnchorTarget = isDynamic,
                noResize = isDynamic,
                isHidden = function()
                    -- If this bar key is no longer in the current profile's
                    -- barDataByKey, it is a stale registration from a previous
                    -- profile and should not get a mover.
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
                    -- iconSize is derived live in LayoutCDMBar from the
                    -- source bar's current width. setWidth just triggers a
                    -- re-layout. Nothing is persisted -- no iconSize, no
                    -- _matchPhysWidth, no cache. The source bar IS the truth.
                    -- Wipe any legacy cache fields left over from previous
                    -- versions so they can't poison anything.
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
                    -- Store the position using the growth-edge anchor directly.
                    -- The unlock mode always provides CENTER coords; for non-CENTER
                    -- grow bars, convert to edge so the frame can be anchored at
                    -- its fixed edge (SetSize then grows naturally from that edge
                    -- without any post-resize re-anchoring).
                    local storePoint, storeX, storeY = point, x, y
                    local bd2 = barDataByKey[key]
                    local grow = bd2 and bd2.growDirection
                    local frame = cdmBarFrames[key]
                    -- Store at the growth edge (and, when "anchor first row" is
                    -- on, the first-row corner) so SetSize grows naturally from
                    -- the fixed edge/corner. Unlock mode always provides CENTER
                    -- coords; convert to the resolved anchor. Skip a conversion
                    -- on any axis with no extent yet (empty bar).
                    -- Snapped bars always store the plain growth edge: the
                    -- anchor system's saved-edge consumers only understand
                    -- single-edge points, so a corner would silently break
                    -- edge preservation and target follow for them.
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
                    -- Phase 2 follow baseline: capture the anchor target's center
                    -- (UIParent space) at save time so ApplyAnchorPosition can later
                    -- shift the absolute saved edge by the target's displacement.
                    -- Only for growth bars; nil for unanchored/CENTER bars -> follow
                    -- stays off (pure absolute pin). require-re-save: existing bars
                    -- pick this up only when next dragged + Save & Exit.
                    local tgtx, tgty
                    local tgtL, tgtR, tgtT, tgtB
                    if grow and grow ~= "CENTER" and EllesmereUI.GetAnchorTargetCenterUI then
                        tgtx, tgty = EllesmereUI.GetAnchorTargetCenterUI("CDM_" .. key)
                        -- Corner-follow baseline: the target's edges at save time,
                        -- captured ONLY when anchored to another CDM bar. Lets
                        -- ApplyAnchorPosition hold a perpendicular (corner) bar
                        -- against the target edge when the target's width/height
                        -- changes. nil otherwise -> corner follow stays off.
                        if EllesmereUI.GetAnchorTargetEdgesUI then
                            tgtL, tgtR, tgtT, tgtB = EllesmereUI.GetAnchorTargetEdgesUI("CDM_" .. key)
                        end
                    end
                    p.cdmBarPositions[key] = { point = storePoint, relPoint = relPoint, x = storeX, y = storeY,
                        tgtx = tgtx, tgty = tgty, tgtL = tgtL, tgtR = tgtR, tgtT = tgtT, tgtB = tgtB }
                    -- Skip rebuild when called from anchor propagation or while
                    -- unlock mode is active (unlock mode owns positioning then).
                    if not EllesmereUI._propagatingSave and not EllesmereUI._unlockActive then
                        BuildAllCDMBars()
                    end
                end,
                loadPos = function()
                    local pos = ECME.db.profile.cdmBarPositions[key]
                    if not pos or not pos.point then return pos end
                    -- Convert edge/corner-stored positions back to CENTER for the
                    -- unlock mode system (it always works with CENTER coords).
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
                    -- While the authoritative reanchor pass is still pending
                    -- (login window, or the instant inside a spec-swap
                    -- reconcile) the CDM pipeline owns layout and applies
                    -- saved positions itself; a rebuild here only races it
                    -- against a still-churning engine pool. The flag is
                    -- consumed deterministically by CollectAndReanchor.
                    if ns._pendingApplyOnReanchor then return end
                    -- Mid-transition guard: when the live spec key disagrees
                    -- with the cached key, a rebuild here can only construct
                    -- the OLD spec's layout against the NEW spec's already-
                    -- repopulating engine pool (the pre-swap window before
                    -- SPELLS_CHANGED lands). The talent_reconcile that
                    -- follows is the only correct builder for that state.
                    local liveKey = ComputeLiveSpecKey()
                    if liveKey and liveKey ~= _cachedSpecKey then return end
                    -- Same-burst coalescing: position passes (ApplySavedPositions
                    -- et al) call EVERY CDM element's applyPosition back-to-back,
                    -- and each call rebuilt ALL bars -- an 11+ deep same-frame
                    -- rebuild storm. The first call rebuilds synchronously
                    -- (Save & Exit's sequencing depends on that); the rest of
                    -- the burst no-ops until the next frame.
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
    -- Expose for ApplyAnchorPosition's growth-direction edge read.
    -- Width-independent: stores edge anchor directly (LEFT/RIGHT/TOP).
    EllesmereUI._cdmBarPositions = ECME.db.profile.cdmBarPositions
end
ns.RegisterCDMUnlockElements = RegisterCDMUnlockElements
_G._ECME_RegisterUnlock = RegisterCDMUnlockElements

-- RequestUpdate delegates to ns.RequestUpdate (defined in EllesmereUICdmBarGlows.lua).
-- Falls back to no-op if bar glows module hasn't loaded yet.
local function RequestUpdate()
    if ns.RequestUpdate then ns.RequestUpdate() end
end


-------------------------------------------------------------------------------
--  Initialization
-------------------------------------------------------------------------------
-- (SetActiveSpec removed -- ns.GetActiveSpecKey reads live API directly)

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
            -- The flag suppresses the profile system's follow-up rebuild
            -- right after a spec change -- but same-profile swaps never run
            -- that follow-up, leaving the flag armed until some LATER apply
            -- consumed it and silently skipped a rebuild the caller needed.
            -- Only honor the suppression while the spec change is recent.
            if not (ns._specChangeAt and (GetTime() - ns._specChangeAt) < 3) then
                ns.FullCDMRebuild("apply")
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

-- Tracks whether CDMFinishSetup has already run for this session.
-- Set when the spec resolves and we kick off the build, prevents double-init
-- if multiple wakeup events fire (PLAYER_LOGIN + first PLAYER_SPECIALIZATION_CHANGED).
local _cdmSetupStarted = false

function ECME:OnEnable()
    -- Cache player race/class for trinket/racial/potion tracking
    _playerRace = select(2, UnitRace("player"))
    _playerClass = select(2, UnitClass("player"))
    ns._playerRace = _playerRace
    ns._playerClass = _playerClass
    ns._myRacialsSet = _myRacialsSet

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

    -- Resolve the in-spellbook racial (the generic "Racial" picker slot maps
    -- to this ID). Re-resolved at build time too (spellbook may be empty here).
    ResolveActiveRacial()


    -- Enable CDM cooldown viewer (keep Blizzard CDM running in background
    -- so we can read its children even while hidden)
    if C_CVar and C_CVar.SetCVar then
        pcall(C_CVar.SetCVar, "cooldownViewerEnabled", "1")
    end

    -- Spec-gated build: only run CDMFinishSetup once we have a real spec key
    -- from the live API. If the API isn't ready yet, defer until it is. This
    -- replaces the old "guess the spec, validate later, repair if wrong"
    -- model with "wait until the truth is known, then build once."
    local function TryBuildCDM()
        if _cdmSetupStarted then return end
        if not ns.GetActiveSpecKey() then return end -- spec API not ready yet
        _cdmSetupStarted = true
        EnsureMappings(GetStore())
        if self._needsCapture then
            -- Defer one more step so Edit Mode has applied positions
            self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnCDMFirstLogin")
        else
            self:CDMFinishSetup()
        end
    end

    -- Try immediately. If the spec API is already populated (most reloads),
    -- this builds in-place and we're done.
    TryBuildCDM()

    -- If the immediate try didn't fire, wake up on the events that signal
    -- spec data is now available and try again. The handler is idempotent
    -- via _cdmSetupStarted so multiple wakeups are harmless.
    if not _cdmSetupStarted then
        local wakeFrame = CreateFrame("Frame")
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

    -- Proc glow hooks: install immediately + retry. Hooks must be in place
    -- before Blizzard re-fires ShowAlert at PLAYER_LOGIN for active procs.
    InstallProcGlowHooks()
    C_Timer.After(0.5, InstallProcGlowHooks)

    -- Initialize Bar Glows overlay system
    if ns.InitBarGlows then ns.InitBarGlows() end

end

function ECME:OnCDMFirstLogin()
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    CDMFirstLoginCapture()
    self._needsCapture = false
    self:CDMFinishSetup()
end

-- (ForcePopulateBlizzardViewers removed -- replaced by viewer hooks)

-- (TalentAwareReconcile / ReconcileSpellList / ns.RequestTalentReconcile /
-- ns.IsReconcileReady / RECONCILE state removed. Under the new model
-- assignedSpells is pure user intent and is never mutated based on "is
-- this spell currently known." Talent/spec/reload events rebuild the
-- cdID route map and reanchor instead -- the route map is the source of
-- truth for which Blizzard frame renders on which bar. Spells whose
-- backing frame is temporarily absent (pet dismissed, choice-node talent
-- swapped away) simply don't render until the frame returns; their
-- assigned slot is preserved for that return.)

-- (ReconcileMainBarSpells / ForceResnapshotMainBars / StartResnapshotRetry
-- removed -- CollectAndReanchor auto-snapshots and hooks handle everything)

-- (One-time per-spec validation removed -- the old corruption recovery
-- was a workaround for cross-viewer spell assignment, which the unified
-- assignedSpells + diversion-set route map model no longer permits.)

function ECME:CDMFinishSetup()

    -- This is the one-time construction hub for a normal login/reload enable:
    -- preload unlock helpers, build the initial bar set, spin up the periodic
    -- tick frame, then schedule any deferred reconciliation/rebuild passes
    -- needed once Blizzard's viewer children and layout have settled.
    -- Load the full unlock mode body early so anchor/propagation functions
    -- (ApplyAnchorPosition, PropagateWidthMatch, etc.) are available for
    -- the initial build pass. CDM SavedVariables are ready by this point.
    EllesmereUI:EnsureLoaded()

    -- Pre-size CDM bar frames using cached icon counts from last session.
    -- Purely cosmetic: gives anchored elements correct dimensions to compute
    -- against before the real spell data populates. BuildAllCDMBars below
    -- overwrites everything with real data.
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
                                -- Containers never capture mouse motion (see
                                -- BuildCDMBar creation block).
                                if frame.EnableMouseMotion then frame:EnableMouseMotion(false) end
                                frame._barKey = key
                                frame._barIndex = i
                                cdmBarFrames[key] = frame
                                cdmBarIcons[key] = {}
                            end
                            -- Raw coord values -- see LayoutCDMBar for why
                            -- we don't pre-snap with SnapForScale (PP.Scale
                            -- truncation loses a pixel at UI scales with
                            -- PP.mult > 1).
                            local iconW = barData.iconSize or 36
                            local iconH = iconW
                            if (barData.iconShape or "none") == "cropped" then
                                iconH = math.floor((barData.iconSize or 36) * 0.80 + 0.5)
                            end
                            local spacing = barData.spacing or 2
                            local grow = barData.growDirection or "CENTER"
                            -- Effective row count: collapses to 1 when a custom
                            -- top-row split has no icons in its second row yet.
                            local stride, numRows = ComputeTopRowStride(barData, cachedCount)
                            if numRows < 1 then numRows = 1 end
                            local isHoriz = (grow == "RIGHT" or grow == "LEFT" or (grow == "CENTER" and not barData.verticalOrientation))
                            -- Compute total in integer phys px to avoid PP.Scale floor
                            -- losing 1 px to floating-point dust on the multiply.
                            local PPpc = EllesmereUI and EllesmereUI.PP
                            local onePxPc = PPpc and PPpc.mult or 1
                            local iconWPx   = math.floor(iconW   / onePxPc + 0.5)
                            local iconHPx   = math.floor(iconH   / onePxPc + 0.5)
                            local spacingPx = math.floor(spacing / onePxPc + 0.5)
                            local totalWPx, totalHPx
                            if isHoriz then
                                totalWPx = stride  * iconWPx + (stride  - 1) * spacingPx
                                totalHPx = numRows * iconHPx + (numRows - 1) * spacingPx
                            else
                                totalWPx = numRows * iconWPx + (numRows - 1) * spacingPx
                                totalHPx = stride  * iconHPx + (stride  - 1) * spacingPx
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

    -- (Migration moved to CollectAndReanchor: it must run after the
    -- viewer pools are populated, which only happens after the first
    -- successful reanchor.)

    ns.FullCDMRebuild("init")

    -- Initialize Tracking Bars
    -- GetTrackedBuffBars auto-initializes empty bars if none exist.
    -- No validation/removal: TBB bars can track any buff (procs,
    -- external buffs, food, etc.) not just CDM viewer spells.
    -- Bars with no active aura simply stay hidden at runtime.
    ns.GetTrackedBuffBars()

    -- (BuildTrackedBuffBars not called here -- FullCDMRebuild("init") above
    -- already called it. M1 cleanups also deleted: AddSpellToBar's variant-
    -- aware dedup prevents duplicate spell entries at insert time.)

    -- Hook Blizzard CDM viewer pools (route map already built by FullCDMRebuild)
    ns.SetupViewerHooks()

    -- FocusKick: install nameplate event proxy + initial position
    EnsureFocusKickProxy()
    ApplyFocusKickAnchor()
    -- FocusKick: install Focus Reminder text proxy + initial pass
    EnsureFocusReminderProxy()
    RefreshFocusReminders()
    -- FocusKick: install focus cast sound proxy + append SharedMedia sounds
    EnsureFocusCastProxy()
    if EllesmereUI.AppendSharedMediaSounds then
        EllesmereUI.AppendSharedMediaSounds(
            FOCUSKICK_SOUND_PATHS,
            FOCUSKICK_SOUND_NAMES,
            FOCUSKICK_SOUND_ORDER
        )
    end

    -- One-time vehicle/petbattle proxy. Drives _CDMApplyVisibility on state
    -- change so CDM bars hide while the vehicle UI or pet battle UI is active.
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


    -- Edit mode close: no forced rebuild needed. The reanchor naturally skips
    -- inactive buff frames with hideWhenInactive (ghost frames from Edit Mode)
    -- and alpha-0s them as unclaimed. Normal hooks handle the rest.

    -- Register UNIT_AURA tracking if custom buff bars have spells
    if ns.UpdateCustomBuffAuraTracking then ns.UpdateCustomBuffAuraTracking() end

    -- Deferred keybind update: wait 3s so Blizzard's hotkey update cycle
    -- has fully run before we read HotKey text from button frames
    C_Timer.After(3, UpdateCDMKeybinds)

    -- (Tick frame removed -- all CDM updates are now event-driven via hooks.
    -- CollectAndReanchor runs only when Blizzard fires lifecycle hooks.)

    -- Register with unlock mode. Both default+custom CDM bars and TBB
    -- elements register synchronously here so anchor data is available
    -- before CollectAndReanchor runs.
    RegisterCDMUnlockElements()
    if ns.RegisterTBBUnlockElements then ns.RegisterTBBUnlockElements() end

    -- CDM is the authoritative trigger for the final layout pass when it is
    -- enabled. Set a flag so the next CollectAndReanchor that completes
    -- (after icons are populated and bar sizes are correct) will fire
    -- ApplyAllWidthHeightMatches + _applySavedPositions in the right order.
    --
    -- Why CDM owns this:
    --   1. CDM bars are the slowest thing to settle -- they depend on
    --      Blizzard CDM viewer pools being populated, which is async.
    --   2. ApplyAllWidthHeightMatches reads source bar widths and propagates
    --      them. If CDM bars are still being built when this runs, the
    --      sizes are transient/wrong.
    --   3. _applySavedPositions iterates registered elements and applies
    --      anchors. If CDM bars haven't registered yet (or their target
    --      ERB bars haven't), anchors silently drop and the bar lands at
    --      its CENTER/CENTER fallback (= screen center).
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
    -- Sit above everything on the icon: Blizzard's cooldown swipe, our border
    -- frame, our glowOverlay (+6), and any proc alert frames. +15 clears them
    -- all with margin.
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
        -- A CDM icon and GetNextCastSpell can each hold EITHER the base or an
        -- override spell id (e.g. Maul <-> Raze), and which side is which
        -- varies by spec. The old code only resolved the suggestion's base and
        -- compared it to the stored id, so it matched "icon=base, suggested=
        -- override" but missed the reverse ("icon=override, suggested=base"),
        -- leaving those icons un-highlighted. Compare on base ids in BOTH
        -- directions. This is strictly a superset of the old exact-id match, so
        -- anything that highlighted before still does.
        local GetBaseSpell = C_Spell and C_Spell.GetBaseSpell
        local suggestedBase = (GetBaseSpell and GetBaseSpell(suggestedSpell)) or suggestedSpell
        for _, icons in pairs(cdmBarIcons) do
            for _, icon in ipairs(icons) do
                local ifc = _ecmeFC[icon]
                local sid = ifc and ifc.spellID
                if sid and icon:IsShown() then
                    -- Direct/base match first (cheap); only resolve the icon's
                    -- own base if those miss, to keep the common path light.
                    -- sid > 0: item/trinket icons store -itemID / -13 / -14,
                    -- which must not be fed to GetBaseSpell.
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

-- One-frame defer after a bar rebuild: icon frames may have just been
-- recycled or re-shown, so we want to re-run the match after the layout
-- settles (dirty-frame pattern).
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
        -- Wipe per-spell caches that may reference stale override IDs or
        -- stale charge data from spells that changed with the talent swap.
        -- Also wipe the persisted DB entries so CacheMultiChargeSpell
        -- re-detects from live API rather than reading a stale false entry.
        -- Skip during combat: actual talent changes are combat-locked, so these
        -- events only fire mid-combat from hero talent procs (e.g. Celestial
        -- Infusion). Wiping here would clear charge data for all spells with no
        -- way to re-detect it until the next out-of-combat cache rebuild.
        if not InCombatLockdown() then
            wipe(_multiChargeSpells)
            wipe(_maxChargeCount)
            local db = ECME.db
            if db and db.sv and db.sv.multiChargeSpells then
                wipe(db.sv.multiChargeSpells)
            end
        end
        -- Rebuild the cdID route map against the new talent set. The
        -- stored assignedSpells is left untouched (it's pure user intent);
        -- the route map is the live source of truth for which frame
        -- renders on which bar. A full CDM rebuild + reanchor below picks
        -- up the new routing.
        if ns.RebuildSpellRouteMap then ns.RebuildSpellRouteMap() end
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
        -- Debounce: one-button rotation addons fire ACTIONBAR_SLOT_CHANGED
        -- on every GCD. Cancel the previous timer so rapid-fire events
        -- coalesce into a single update 0.5s after the last event.
        if _keybindDebounceTimer then _keybindDebounceTimer:Cancel() end
        _keybindDebounceTimer = C_Timer.NewTimer(0.5, function()
            _keybindDebounceTimer = nil
            UpdateCDMKeybinds()
        end)
        return
    end
    if event == "TRAIT_CONFIG_UPDATED" or event == "PLAYER_TALENT_UPDATE" or event == "ACTIVE_TALENT_GROUP_CHANGED"
        or event == "PLAYER_PVP_TALENT_UPDATE" then
        -- Hero talent, loadout, or PvP talent context change -- debounced
        -- rebuild. PvP talents (de)activating on arena enter/exit makes
        -- Blizzard re-evaluate the viewer's tracked cooldown set; without a
        -- rebuild the new pool frames are never re-claimed and the
        -- unclaimed-frame cleanup blanks them (arena-exit empty-CDM bug).
        -- The spell set may have changed: let the post-rebuild reanchor
        -- re-run the automatic base-bar materialization for this spec.
        if ns._reseededSpecsSession then wipe(ns._reseededSpecsSession) end
        ScheduleTalentRebuild()
        return
    end
    if event == "GROUP_ROSTER_UPDATE" then
        ScheduleRosterRebuild()
        _CDMApplyVisibility()
        return
    end
    if event == "CINEMATIC_STOP" or event == "STOP_MOVIE" then
        -- Blizzard restores frame positions/alpha after cinematics end.
        -- Re-hide immediately so the Blizzard CDM doesn't reappear.
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
        -- Defer to a clean execution context: the event handler chain can
        -- carry taint from other addons, which propagates into LayoutCDMBar
        -- when a bar transitions from hidden to visible (visHideMounted).
        -- The dragonriding edges take the same deferred path for the same
        -- reason (mid-flight unhide runs LayoutCDMBar).
        C_Timer.After(0, _CDMApplyVisibility)
        return
    end
    if event == "UPDATE_SHAPESHIFT_FORM" then
        -- Bail fast if no bar actually uses visHideMounted: druids shift
        -- constantly in combat (Bear/Cat) and we don't want to re-run the
        -- visibility pipeline for nothing.
        local p = ECME.db and ECME.db.profile
        local bars = p and p.cdmBars and p.cdmBars.bars
        if not bars then return end
        local anyMountedOpt = false
        for _, bd in ipairs(bars) do
            if bd.visHideMounted then anyMountedOpt = true; break end
        end
        if not anyMountedOpt then return end
        -- Defer one frame: the Travel Form aura is applied slightly after
        -- UPDATE_SHAPESHIFT_FORM fires, so IsPlayerMountedLike's aura check
        -- would miss it on the immediate pass.
        C_Timer.After(0, _CDMApplyVisibility)
        return
    end
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" or event == "ZONE_CHANGED_NEW_AREA" then
        if ns._syncRotationCombatState then ns._syncRotationCombatState() end
        if event == "PLAYER_REGEN_DISABLED" then
            _inCombat = true
            _CDMApplyVisibility()
        elseif event == "PLAYER_REGEN_ENABLED" then
            -- Buffer combat exit: brief out-of-combat blips (mob dies,
            -- re-aggro) shouldn't flash visibility changes.
            C_Timer.After(0.1, function()
                if not InCombatLockdown() then
                    _inCombat = false
                    _CDMApplyVisibility()
                end
            end)
        else
            -- Zone transition: re-apply visibility (mounted state etc. may
            -- have changed). No rebuild or reanchor -- if the spec changed,
            -- SPELLS_CHANGED handles the rebuild if the spec changed.
            _CDMApplyVisibility()
        end
        -- Flush deferred TBB rebuild that was queued during combat
        if event == "PLAYER_REGEN_ENABLED" and ns.IsTBBRebuildPending and ns.IsTBBRebuildPending() then
            if ns.BuildTrackedBuffBars then ns.BuildTrackedBuffBars() end
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
        -- PvP instance transition backstop: entering or leaving a PvP
        -- instance rebuilds viewer pools (PvP talents activate/deactivate).
        -- Rebuild + reanchor so the new pool frames are claimed.
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
        -- Safety: re-apply visibility after loading screen settles.
        -- Two passes to catch both fast and late viewer pool rebuilds.
        C_Timer.After(1.5, _CDMApplyVisibility)
        C_Timer.After(3, _CDMApplyVisibility)
    end
    if event == "SPELLS_CHANGED" then
        CheckSpecChange()
        ns._spellsReadyForApply = true
        -- Engine spell data changed (spec-swap churn tail, druid form swap,
        -- talent/spell overrides). The variant-expanded diversion maps and
        -- the memoized cdID->bar routes were derived from the PREVIOUS
        -- spell state; a route resolved mid-churn against transitional
        -- cooldown info is cached until the next map rebuild and pins a
        -- ghosted/custom spell onto the wrong visible bar. Re-derive from
        -- current truth and re-claim -- the LAST fire of any churn burst
        -- always leaves the final state correct, with no settle timers.
        -- (CheckSpecChange's reconcile also rebuilds the map, but a
        -- same-key fire means the data changed again after that rebuild.)
        if ns.RebuildSpellRouteMap then ns.RebuildSpellRouteMap() end
        -- The tracked-buff catalog can change in the same churn, and the
        -- login-pass reconcile may have consumed its dirty flag against a
        -- still-empty viewer pool (the flag is cleared before the call and
        -- an empty catalog no-ops). Re-arm so the queued reanchor
        -- reconciles the buff display order against the populated catalog.
        ns._cdmBuffOrderDirty = true
        if ns.QueueReanchor then ns.QueueReanchor() end
        return
    end
    if event == "PLAYER_SPECIALIZATION_CHANGED" and unit == "player" then
        -- Non-rebuild work only. The actual spec change rebuild is
        -- driven by SPELLS_CHANGED above (which fires for both manual
        -- and auto swaps). This handler just invalidates caches that
        -- need immediate clearing.
        if EllesmereUI and EllesmereUI.InvalidateFrameCache then
            EllesmereUI.InvalidateFrameCache()
        end
    end
    RequestUpdate()
end)

-------------------------------------------------------------------------------
--  Slash commands
-------------------------------------------------------------------------------
-- DEBUG: /cdmwatchbuffs to trace everything touching the buff bar

SLASH_ECME1 = "/ecme"
SLASH_ECME2 = "/cdmeffects"
SLASH_ECME3 = "/ecdm"
SlashCmdList.ECME = function(msg)
    if InCombatLockdown and InCombatLockdown() then return end
    if EllesmereUI and EllesmereUI.ShowModule then
        EllesmereUI:ShowModule("EllesmereUICooldownManager")
    end
end

-------------------------------------------------------------------------------
-- /cdmdbg -- snapshot of the CDM routing pipeline at a given moment.
-- Dumps:
--   1. Stored assignedSpells per bar (default + custom + ghost)
--   2. _cdidRouteMap aggregated by target bar (which cooldownIDs route where)
--   3. Currently visible cdmBarIcons per bar (what the user actually sees)
-- Used to debug "preview shows X spells but the bar shows Y icons" type
-- mismatches between the stored data, the route map, and the render output.
-------------------------------------------------------------------------------
SLASH_CDMDBG1 = "/cdmdbg"
SlashCmdList.CDMDBG = function()
    local ACCENT = "|cff0cd29f"
    local DIM    = "|cff7f7f7f"
    local OFF    = "|r"
    local function P(s) print(ACCENT .. "[CDM]" .. OFF .. " " .. s) end

    local p = ECME.db and ECME.db.profile
    if not p or not p.cdmBars then P("no profile") return end

    local specKey = ns.GetActiveSpecKey()
    P("=== CDM DEBUG SNAPSHOT (spec " .. tostring(specKey) .. ") ===")

    -- 1. Stored assignedSpells per bar
    P(ACCENT .. "--- Stored assignedSpells ---" .. OFF)
    for _, bd in ipairs(p.cdmBars.bars) do
        if bd.enabled then
            local sd = ns.GetBarSpellData(bd.key)
            local list = sd and sd.assignedSpells
            local count = list and #list or 0
            local kind
            if bd.isGhostBar then kind = "ghost"
            elseif bd.key == "cooldowns" or bd.key == "utility" or bd.key == "buffs" then kind = "default"
            elseif bd.barType == "custom_buff" then kind = "custom_buff"
            else kind = "custom" end
            local label = string.format("[%s] %s (%d)", kind, bd.key, count)
            if count > 0 then
                local preview = {}
                for i = 1, math.min(count, 6) do
                    local sid = list[i]
                    local name = sid and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(sid) or "?"
                    preview[i] = tostring(sid) .. ":" .. tostring(name)
                end
                if count > 6 then preview[#preview + 1] = "..." end
                P(label .. "  " .. DIM .. table.concat(preview, ", ") .. OFF)
            else
                P(label .. "  " .. DIM .. "(empty)" .. OFF)
            end
        end
    end

    -- 2. Route map aggregated
    P(ACCENT .. "--- _cdidRouteMap aggregated by target ---" .. OFF)
    local rm = ns._cdidRouteMap
    if rm then
        local byBar = {}
        local total = 0
        for cdID, barKey in pairs(rm) do
            if not byBar[barKey] then byBar[barKey] = {} end
            byBar[barKey][#byBar[barKey] + 1] = cdID
            total = total + 1
        end
        P("total routed cdIDs: " .. total)
        for barKey, cdIDs in pairs(byBar) do
            P(string.format("  -> %s : %d cdIDs", barKey, #cdIDs))
        end
    else
        P("(no _cdidRouteMap)")
    end

    -- 3. Currently visible icons per bar
    P(ACCENT .. "--- cdmBarIcons (what's actually rendered) ---" .. OFF)
    if ns.cdmBarIcons then
        for barKey, icons in pairs(ns.cdmBarIcons) do
            local count = #icons
            if count > 0 then
                local preview = {}
                local fcCache = ns._ecmeFC
                for i = 1, count do
                    local icon = icons[i]
                    local fc = fcCache and fcCache[icon]
                    local sid = (fc and fc.spellID) or 0
                    local name = sid and sid > 0 and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(sid) or "?"
                    local vis = (icon and icon.IsShown and icon:IsShown()) and "" or "(hidden)"
                    preview[i] = tostring(sid) .. ":" .. tostring(name) .. vis
                end
                P(string.format("[%s] %d icons  %s%s%s", barKey, count, DIM, table.concat(preview, ", "), OFF))
            end
        end
    end

    -- 4. What EnumerateCDMViewerSpells returns RIGHT NOW
    P(ACCENT .. "--- EnumerateCDMViewerSpells (CD/util pools) ---" .. OFF)
    if ns.EnumerateCDMViewerSpells then
        local entries = ns.EnumerateCDMViewerSpells(false)
        P("count: " .. #entries)
        for i, e in ipairs(entries) do
            local name = e.sid and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(e.sid) or "?"
            P(string.format("  [%d] sid=%d cdID=%s viewer=%s name=%s",
                i, e.sid, tostring(e.cdID), tostring(e.viewerName), tostring(name)))
        end
    end

    -- 5. Raw frame walk: for each frame in Essential/Utility/Buff pools, dump
    --    cdID, GetSpellID, info.spellID, info.overrideSpellID, canonical,
    --    plus the stale-frame verdict fields: whether the cdID is in the
    --    engine's CURRENT learned cooldown set, whether the frame still
    --    carries cooldownInfo (the IsFrameIncluded trigger for hidden
    --    frames), and which bar our claim cache has it on.
    P(ACCENT .. "--- Raw viewer pool walk ---" .. OFF)
    local gci = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
    -- Engine truth for the CURRENT spec/form state: the union of every
    -- category's learned cooldownIDs. A pool frame whose cdID is NOT in
    -- this set is a leftover from a previous spec/form state.
    local learnedSet = {}
    if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet
       and Enum and Enum.CooldownViewerCategory then
        for _, cat in pairs(Enum.CooldownViewerCategory) do
            local ok, ids = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, cat, false)
            if ok and type(ids) == "table" then
                for _, id in ipairs(ids) do learnedSet[id] = true end
            end
        end
    end
    for _, vName in ipairs({ "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer" }) do
        local v = _G[vName]
        local count = 0
        if v and v.itemFramePool and v.itemFramePool.EnumerateActive then
            for frame in v.itemFramePool:EnumerateActive() do
                count = count + 1
                local cdID = frame.cooldownID
                local frameSid = (type(frame.GetSpellID) == "function") and frame:GetSpellID() or nil
                local infoSpellID, infoOverride = nil, nil
                if cdID and gci then
                    local info = gci(cdID)
                    if info then
                        infoSpellID = info.spellID
                        infoOverride = info.overrideSpellID
                    end
                end
                local canonical = ns.GetCanonicalSpellIDForFrame and ns.GetCanonicalSpellIDForFrame(frame) or nil
                local canonName = canonical and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(canonical) or "?"
                local fc = ns._ecmeFC and ns._ecmeFC[frame]
                -- Render state: effective alpha (secret-guarded) + what the
                -- frame's first point anchors to (our bar container name via
                -- reverse lookup, else the region's own name).
                local alpha = frame:GetAlpha()
                if issecretvalue and issecretvalue(alpha) then alpha = -1 end
                local _, relTo = frame:GetPoint(1)
                local relName = nil
                if relTo then
                    for bk2, bf2 in pairs(cdmBarFrames) do
                        if bf2 == relTo then relName = "EUIbar:" .. bk2 break end
                    end
                    if not relName then
                        relName = (relTo.GetName and relTo:GetName()) or "?"
                    end
                end
                P(string.format("  [%s#%d] cdID=%s frameSID=%s info.sID=%s info.ovrSID=%s canon=%s (%s) shown=%s cdInfo=%s inSet=%s bar=%s alpha=%.2f ptTo=%s",
                    vName, count, tostring(cdID), tostring(frameSid),
                    tostring(infoSpellID), tostring(infoOverride),
                    tostring(canonical), tostring(canonName), tostring(frame:IsShown()),
                    tostring(frame.cooldownInfo ~= nil),
                    tostring(cdID ~= nil and learnedSet[cdID] == true),
                    tostring(fc and fc.barKey), alpha, tostring(relName)))
            end
        end
        P(string.format("[%s] active count: %d", vName, count))
    end

    -- 6. Variant family + migration simulation for Beacon of Light (53563)
    P(ACCENT .. "--- Beacon of Light variant family ---" .. OFF)
    local beaconID = 53563
    local function ShowVariant(label, sid)
        if not sid then return end
        local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(sid) or "?"
        P(string.format("  %s: %d (%s)", label, sid, tostring(name)))
    end
    ShowVariant("self", beaconID)
    if C_Spell and C_Spell.GetBaseSpell then
        ShowVariant("base", C_Spell.GetBaseSpell(beaconID))
    end
    if C_Spell and C_Spell.GetOverrideSpell then
        ShowVariant("override", C_Spell.GetOverrideSpell(beaconID))
    end

    -- Reverse: what other spells have 53563 in their family?
    P(ACCENT .. "--- Reverse variant lookups (does X resolve to Beacon?) ---" .. OFF)
    local function CheckSpell(sid)
        if not sid or sid <= 0 then return end
        local base, override = nil, nil
        if C_Spell and C_Spell.GetBaseSpell then base = C_Spell.GetBaseSpell(sid) end
        if C_Spell and C_Spell.GetOverrideSpell then override = C_Spell.GetOverrideSpell(sid) end
        if base == beaconID or override == beaconID then
            local name = C_Spell.GetSpellName(sid) or "?"
            P(string.format("  %d (%s) -> base=%s override=%s", sid, name, tostring(base), tostring(override)))
        end
    end
    -- Check all currently assigned spells in cooldowns + utility + ghost
    local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
    local sk = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
    local prof = sp and sk and sp[sk]
    if prof and prof.barSpells then
        for barKey, bs in pairs(prof.barSpells) do
            if bs and bs.assignedSpells then
                for _, sid in ipairs(bs.assignedSpells) do
                    CheckSpell(sid)
                end
            end
        end
    end

    -- 7. Run the migration's exact lookup logic against Beacon of Light
    P(ACCENT .. "--- Migration lookup simulation for Beacon of Light ---" .. OFF)
    if prof and ns.StoreVariantValue and ns.ResolveVariantValue then
        local assignedSet = {}
        for barKey, bs in pairs(prof.barSpells) do
            -- mimic the migration's "real CD/util bars" filter
            if barKey == "cooldowns" or barKey == "utility" then
                if bs and bs.assignedSpells then
                    for _, sid in ipairs(bs.assignedSpells) do
                        ns.StoreVariantValue(assignedSet, sid, true, false)
                    end
                end
            end
        end
        local existingGhost = {}
        local ghostBs = prof.barSpells.__ghost_cd
        if ghostBs and ghostBs.assignedSpells then
            for _, sid in ipairs(ghostBs.assignedSpells) do
                ns.StoreVariantValue(existingGhost, sid, true, false)
            end
        end
        local isAssigned = ns.ResolveVariantValue(assignedSet, beaconID)
        local isGhosted  = ns.ResolveVariantValue(existingGhost, beaconID)
        P(string.format("  isAssigned(53563)=%s  isGhosted(53563)=%s",
            tostring(isAssigned), tostring(isGhosted)))
        -- Also dump assignedSet keys to see if 53563 is keyed in there
        local assignedKeys = {}
        for k in pairs(assignedSet) do assignedKeys[#assignedKeys+1] = k end
        table.sort(assignedKeys)
        P("  assignedSet keys: " .. table.concat(assignedKeys, ", "))
        local ghostKeys = {}
        for k in pairs(existingGhost) do ghostKeys[#ghostKeys+1] = k end
        table.sort(ghostKeys)
        P("  existingGhost keys: " .. table.concat(ghostKeys, ", "))
    end

    P("=== END SNAPSHOT ===")
end

-------------------------------------------------------------------------------
-- /euiorder -- focused talent-swap order probe (TEMP DEBUG). For each CD/util
-- bar, dumps the stored assignedSpells order and the rendered order with each
-- icon's sortOrder. sortOrder 99999 (= [end]) means the spell wasn't found in
-- assignedSpells and got sorted to the end (spillover). Run before/after a
-- talent swap to see whether a re-talented spell keeps its slot.
-------------------------------------------------------------------------------
SLASH_EUIORDER1 = "/euiorder"
SlashCmdList.EUIORDER = function()
    local ACCENT = "|cff0cd29f"; local DIM = "|cff7f7f7f"; local BAD = "|cffff5555"; local OFF = "|r"
    local function P(s) print(ACCENT .. "[Order]" .. OFF .. " " .. s) end
    local function NM(sid)
        if type(sid) ~= "number" or sid <= 0 then return tostring(sid) end
        local n = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(sid)
        return sid .. ":" .. tostring(n or "?")
    end
    local p = ECME.db and ECME.db.profile
    if not p or not p.cdmBars then P("no profile") return end
    for _, bd in ipairs(p.cdmBars.bars) do
        if bd.enabled and not bd.isGhostBar
           and bd.barType ~= "buffs" and bd.barType ~= "custom_buff" and bd.key ~= "buffs" then
            local sd = ns.GetBarSpellData(bd.key)
            local list = sd and sd.assignedSpells
            local parts = {}
            if list then for i, sid in ipairs(list) do parts[i] = i .. ")" .. NM(sid) end end
            P(ACCENT .. bd.key .. OFF .. " assigned(" .. (list and #list or 0) .. "): "
                .. (next(parts) and table.concat(parts, "  ") or (DIM .. "(empty)" .. OFF)))
            local icons = ns.cdmBarIcons and ns.cdmBarIcons[bd.key]
            local rparts = {}
            if icons then
                for i = 1, #icons do
                    local fc = ns._ecmeFC and ns._ecmeFC[icons[i]]
                    local sid = fc and fc.spellID
                    local so = fc and fc.sortOrder
                    rparts[i] = i .. ")" .. NM(sid) .. ":so=" .. tostring(so) .. ((so == 99999) and (BAD .. "[end]" .. OFF) or "")
                end
            end
            P("   rendered(" .. (icons and #icons or 0) .. "): "
                .. (next(rparts) and table.concat(rparts, "  ") or (DIM .. "(none)" .. OFF)))
            -- Per-icon identity probes: every id the OrderKeyFor chain can match
            -- against the spellOrder map, so a wrong sortOrder can be traced to
            -- the exact colliding/missing probe.
            if icons then
                local fso = C_SpellBook and C_SpellBook.FindSpellOverrideByID
                for i = 1, #icons do
                    local frame = icons[i]
                    local fc = ns._ecmeFC and ns._ecmeFC[frame]
                    local sid = fc and fc.spellID
                    local ovr = (fso and type(sid) == "number" and sid > 0) and fso(sid) or nil
                    local gbase = (C_Spell and C_Spell.GetBaseSpell and type(sid) == "number" and sid > 0)
                        and C_Spell.GetBaseSpell(sid) or nil
                    local canon = ns.GetCanonicalSpellIDForFrame and ns.GetCanonicalSpellIDForFrame(frame) or nil
                    local linked = ""
                    if fc and fc.linkedSpellIDs then
                        local lp = {}
                        for _, lid in ipairs(fc.linkedSpellIDs) do lp[#lp + 1] = tostring(lid) end
                        linked = table.concat(lp, "/")
                    end
                    P(string.format("   probe %d) sid=%s base=%s fOvr=%s gBase=%s canon=%s rsv=%s linked=[%s] cdID=%s LI=%s so=%s",
                        i, tostring(sid), tostring(fc and fc.baseSpellID), tostring(ovr),
                        tostring(gbase), tostring(canon), tostring(fc and fc.resolvedSid), linked,
                        tostring(frame.cooldownID), tostring(frame.layoutIndex),
                        tostring(fc and fc.sortOrder)))
                end
            end
            -- The bar's cached spellOrder map (id -> assignedSpells idx). Two ids
            -- landing on the same idx, or a rendered sid absent here, IS the bug.
            local container = cdmBarFrames[bd.key]
            local om = container and container._cachedSpellOrder
            if om and next(om) then
                local entries = {}
                for id, idx in pairs(om) do entries[#entries + 1] = { id = id, idx = idx } end
                table.sort(entries, function(a, b)
                    if a.idx ~= b.idx then return a.idx < b.idx end
                    return a.id < b.id
                end)
                local mp = {}
                for _, e in ipairs(entries) do mp[#mp + 1] = e.idx .. "<-" .. NM(e.id) end
                P("   orderMap: " .. DIM .. table.concat(mp, "  ") .. OFF)
            else
                P("   orderMap: " .. DIM .. "(empty/stale)" .. OFF)
            end
        end
    end
end

-------------------------------------------------------------------------------
-- /cdmbuffid -- default buffs bar identity-collapse probe.
--
-- Adding drag-to-reorder to the DEFAULT buffs bar hinges on ONE question: for
-- each buff, does the id the PREVIEW + per-icon SETTINGS use (canonical /
-- GetSpellID-derived, == slot._previewSpellID / ResolveBuffSettingsKey) collapse
-- to the same number as the id the SEED + SORT use (fc.spellID, which the layout
-- writes as baseSpellID or spellID and which EnsureBarOrderSeeded persists)? If
-- a transform/override buff derives two different ids, a drag in the options
-- preview targets a different entry than the one the render path orders -- a
-- silent wrong-icon reorder. The probe also reports whether the preview slot
-- indices line up with the rendered-icon indices (they won't when inactive
-- tracked buffs exist -- the default-bar index-space mismatch).
--
-- Run on a spec with active transform/override buffs (e.g. Holy Paladin) and
-- read the OK / DIVERGE and ALIGNED / MISALIGNED verdicts.
-------------------------------------------------------------------------------
SLASH_CDMBUFFID1 = "/cdmbuffid"
SLASH_CDMBUFFID2 = "/cdmbid"
SlashCmdList.CDMBUFFID = function()
    local ACCENT = "|cff0cd29f"
    local DIM    = "|cff7f7f7f"
    local BAD    = "|cffff5555"
    local GOOD   = "|cff55ff55"
    local OFF    = "|r"
    local function P(s) print(ACCENT .. "[CDMBUFFID]" .. OFF .. " " .. s) end

    -- Live buff GetSpellID is a secret value while the aura is active; guard
    -- every numeric so the probe never compares or prints a secret.
    local function IsSecret(v) return issecretvalue and issecretvalue(v) end
    local function SN(v)
        if v == nil then return "nil" end
        if IsSecret(v) then return "<secret>" end
        return tostring(v)
    end
    local function NM(sid)
        if not sid or IsSecret(sid) or type(sid) ~= "number" or sid <= 0 then return "?" end
        return (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(sid)) or "?"
    end

    local specKey = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
    P("=== DEFAULT BUFFS BAR ID PROBE (spec " .. tostring(specKey) .. ") ===")

    -- A. Stored order state for the buffs bar (what reorder would manipulate).
    local sd = ns.GetBarSpellData and ns.GetBarSpellData("buffs")
    local assigned = sd and sd.assignedSpells
    P(ACCENT .. "--- stored assignedSpells (\"buffs\") ---" .. OFF)
    if assigned and #assigned > 0 then
        for i, sid in ipairs(assigned) do
            P(string.format("  [%d] %s (%s)", i, SN(sid), NM(sid)))
        end
    else
        P("  " .. DIM .. "(empty -- not yet seeded; reorder seeds from rendered icons)" .. OFF)
    end

    -- B. Preview source: viewer enumeration (active + inactive). This is the
    --    order + id space the options grid is built from. e.sid == the id the
    --    preview slot and per-icon settings key off.
    local enumByCdID    = {}   -- cdID -> enum index
    local enumSidByCdID = {}   -- cdID -> canonical sid
    local enumCount     = 0
    P(ACCENT .. "--- EnumerateCDMViewerSpells(true) [preview + settings id = e.sid] ---" .. OFF)
    if ns.EnumerateCDMViewerSpells then
        local entries = ns.EnumerateCDMViewerSpells(true)
        P("  count: " .. #entries)
        for i, e in ipairs(entries) do
            if e.cdID ~= nil then
                enumByCdID[e.cdID]    = i
                enumSidByCdID[e.cdID] = e.sid
                enumCount = enumCount + 1
            end
            P(string.format("  [%d] sid=%s cdID=%s name=%s",
                i, SN(e.sid), SN(e.cdID), NM(e.sid)))
        end
    end

    -- C. Live rendered icons: walk cdmBarIcons["buffs"] in render order and
    --    compare SEED/SORT id (fc.spellID) vs PREVIEW/SETTINGS id (canonical),
    --    and render order vs preview-enum order.
    P(ACCENT .. "--- live cdmBarIcons[\"buffs\"] [seed + sort id = fc.spellID] ---" .. OFF)
    local gci      = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
    local fcCache  = ns._ecmeFC
    local icons    = ns.cdmBarIcons and ns.cdmBarIcons["buffs"]
    local nDiverge, nTotal = 0, 0
    local lastEnumIdx, orderAligned = 0, true
    if icons and #icons > 0 then
        for j = 1, #icons do
            local frame = icons[j]
            if frame then
                nTotal = nTotal + 1
                local fc      = fcCache and fcCache[frame]
                local fcSpell = fc and fc.spellID
                local fcBase  = fc and fc.baseSpellID
                local cdID    = frame.cooldownID
                local canon   = ns.GetCanonicalSpellIDForFrame and ns.GetCanonicalSpellIDForFrame(frame)
                local enumIdx = (cdID ~= nil) and enumByCdID[cdID] or nil

                -- id-collapse verdict: seed/sort (fcSpell) vs preview/settings (canon)
                local verdict
                if IsSecret(fcSpell) or IsSecret(canon) then
                    verdict = BAD .. "SECRET" .. OFF; nDiverge = nDiverge + 1
                elseif type(fcSpell) == "number" and type(canon) == "number" and fcSpell == canon then
                    verdict = GOOD .. "OK" .. OFF
                else
                    verdict = BAD .. "DIVERGE" .. OFF; nDiverge = nDiverge + 1
                end

                -- raw cooldownInfo for context (helps explain a divergence)
                local infoSpell, infoOvr
                if cdID ~= nil and gci then
                    local info = gci(cdID)
                    if info then infoSpell = info.spellID; infoOvr = info.overrideSpellID end
                end

                -- order-alignment: render order should follow preview-enum order
                local enumTag
                if enumIdx then
                    if enumIdx < lastEnumIdx then orderAligned = false end
                    lastEnumIdx = enumIdx
                    enumTag = "enumIdx=" .. enumIdx
                else
                    enumTag = BAD .. "no-enum(custom/injected?)" .. OFF
                end

                local shown = frame.IsShown and frame:IsShown()
                P(string.format("  render#%d %s  fc.spellID=%s fc.base=%s canon=%s | cdID=%s info.sID=%s info.ovr=%s | %s shown=%s name=%s",
                    j, verdict, SN(fcSpell), SN(fcBase), SN(canon),
                    SN(cdID), SN(infoSpell), SN(infoOvr), enumTag, tostring(shown), NM(canon)))
            end
        end
    else
        P("  " .. DIM .. "(no live buff icons -- be on a spec with buffs currently up)" .. OFF)
    end

    -- D. Conclusion.
    P(ACCENT .. "--- verdict ---" .. OFF)
    P(string.format("  rendered icons=%d  diverge=%d  preview entries=%d", nTotal, nDiverge, enumCount))
    if nTotal == 0 then
        P("  " .. DIM .. "inconclusive: no rendered buffs to sample" .. OFF)
    elseif nDiverge == 0 then
        P("  " .. GOOD .. "id-collapse: ALL buffs agree (seed/sort == preview/settings). Default-bar reorder is safe with the simple approach." .. OFF)
    else
        P("  " .. BAD .. string.format("id-collapse: %d buff(s) DIVERGE -- those need a canonical-id reconcile before drag is trustworthy on the default bar.", nDiverge) .. OFF)
    end
    if nTotal > 0 then
        if enumCount > nTotal then
            P("  " .. BAD .. string.format("index-space: preview shows %d entries but only %d render -> preview slot index != assignedSpells index. Default-bar drag must map by spellID, not raw slot index.", enumCount, nTotal) .. OFF)
        else
            P("  " .. GOOD .. "index-space: preview entry count == rendered count (no inactive stragglers right now)." .. OFF)
        end
        P("  render-order vs preview-order: " .. (orderAligned and (GOOD .. "ALIGNED" .. OFF) or (BAD .. "MISALIGNED" .. OFF)))
    end

    -- E. Display-order match simulation (stable-key format: "c"..cooldownID for
    --    Blizzard buffs, "s"..spellID for customs). A MISS means that buff sorts
    --    to the END -- the "reorder messes up while active" symptom. With the
    --    cooldownID fix, a buff's active frame and its placeholder share one key,
    --    so every buff should HIT regardless of proc state.
    P(ACCENT .. "--- buffDisplayOrder match (stable-key sort simulation) ---" .. OFF)
    local sdBuf2 = ns.GetBarSpellData and ns.GetBarSpellData("buffs")
    local order = sdBuf2 and sdBuf2.buffDisplayOrder
    if not order or #order == 0 then
        P("  " .. DIM .. "(buffDisplayOrder empty -- reorder the default bar once first, then re-run)" .. OFF)
    elseif type(order[1]) == "number" then
        P("  " .. DIM .. "(stale numeric format -- open CDM options once to re-seed, then re-run)" .. OFF)
    else
        local gci2 = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
        local orderIdx = {}
        for i, key in ipairs(order) do
            if orderIdx[key] == nil then orderIdx[key] = i end
            local nm, pfx, num = "?", string.sub(key, 1, 1), tonumber(string.sub(key, 2))
            if pfx == "s" then
                nm = NM(num)
            elseif pfx == "c" and num and gci2 then
                local info = gci2(num)
                nm = (info and info.spellID) and NM(info.spellID) or "?"
            end
            P(string.format("  stored[%d] = %s (%s)", i, key, nm))
        end
        if icons then
            local nMiss = 0
            for j = 1, #icons do
                local frame = icons[j]
                if frame then
                    local fc = fcCache and fcCache[frame]
                    local fcSpell = fc and fc.spellID
                    local cd = frame.cooldownID
                    local key
                    if type(cd) == "number" then key = "c" .. cd
                    elseif fcSpell then key = "s" .. fcSpell end
                    local hit = key and orderIdx[key]
                    local tag
                    if hit then
                        tag = GOOD .. "HIT@" .. hit .. OFF
                    else
                        tag = BAD .. "MISS->end" .. OFF
                        nMiss = nMiss + 1
                    end
                    P(string.format("  render#%d %s  key=%s cdID=%s fc.spellID=%s",
                        j, tag, tostring(key), SN(cd), SN(fcSpell)))
                end
            end
            if nMiss > 0 then
                P("  " .. BAD .. string.format("%d live buff(s) MISS -> jump to end. Order key still not stable.", nMiss) .. OFF)
            else
                P("  " .. GOOD .. "all live buffs match the stored order (stable across active/inactive)." .. OFF)
            end
        end
    end
    P("=== END PROBE ===")
end

