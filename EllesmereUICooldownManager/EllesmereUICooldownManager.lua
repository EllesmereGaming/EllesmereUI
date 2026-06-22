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
local _keybindRebuildPending = false
local _keybindCacheReady     = false  -- true after first successful build
local _keybindDebounceTimer  = nil   -- cancellable timer for debounced keybind updates

-- Combat state tracked via events (InCombatLockdown() can lag behind PLAYER_REGEN_DISABLED)
local _inCombat = false

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
-- 40s bar off the player's Sated/Exhaustion debuff edge. Time Spiral / warlock
-- pets stay out (no usable detection).
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
        icon     = 134764,
        itemID   = 211756,
        altItemIDs = { 241304, 241305 },
    },
    {
        key      = "healthstone",
        name     = "Healthstone",
        icon     = 538745,
        itemID   = 5512,
        spellID  = 6262,
        altItemIDs = { 224464 },
        combatLockout = true,
    },
    {
        key      = "demonic_healthstone",
        name     = "Demonic Healthstone",
        itemID   = 224464,
        spellID  = 452930,
        altItemIDs = { 5512 },
        combatLockout = true,
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

-- specProfiles table for the active profile (the live CDM bucket).
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

    ns._pendingApplyOnReanchor = true

    -- Full wipe + rebuild path. talent_reconcile reason triggers the
    -- isFullWipe branch in FullCDMRebuild which: wipes icon arrays, clears
    -- _prevIconRefs / _prevVisibleCount, clears anchor state in
    -- _hookFrameData, clears all FC caches on viewer pool frames, then
    -- runs a direct synchronous CollectAndReanchor. After this returns,
    -- cdmBarIcons is populated with the new spec's icons.
    if ns.FullCDMRebuild then
        ns.FullCDMRebuild("talent_reconcile")
    end

    -- Signal the profile system that CDM's spec rebuild is complete.
    -- This clears _specProfileSwitching and re-applies width/height matches.
    if EllesmereUI and EllesmereUI.OnSpecSwitchComplete then
        EllesmereUI.OnSpecSwitchComplete()
    end
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
    { name = "Custom Shape Glow",    shapeGlow = true },
    { name = "Action Button Glow",   buttonGlow = true },
    { name = "Auto-Cast Shine",      autocast = true },
    { name = "GCD",                  atlas = "RotationHelper_Ants_Flipbook", texPadding = 1.6 },
    { name = "Modern WoW Glow",      atlas = "UI-HUD-ActionBar-Proc-Loop-Flipbook", texPadding = 1.4 },
    { name = "Classic WoW Glow",     texture = "Interface\\SpellActivationOverlay\\IconAlertAnts",
      rows = 5, columns = 5, frames = 25, duration = 0.3, frameW = 48, frameH = 48, texPadding = 1.25 },
}
ns.GLOW_STYLES = GLOW_STYLES

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
    cr = cr or 1; cg = cg or 1; cb = cb or 1

    if entry.shapeGlow then
        -- CDM-specific: read shape mask/border from the icon frame
        local icon = parent
        local ifc2 = _ecmeFC[icon]
        local shape = (ifc2 and ifc2.shapeApplied) and (ifc2 and ifc2.shapeName) or nil
        local maskPath   = shape and CDM_SHAPES.masks[shape]
        local borderPath = shape and CDM_SHAPES.borders[shape]
        _G_Glows.StartShapeGlow(overlay, math.min(pW, pH), cr, cg, cb, 1.20, {
            maskPath   = maskPath,
            borderPath = borderPath,
            shapeMask  = ifc2 and ifc2.shapeMask,
        })
    elseif entry.procedural then
        -- Pixel Glow params. The pandemic glow passes explicit opts; per-button
        -- glows (active-state, CD-ready, bar glows) pass none, so resolve the
        -- owning CD/utility bar's Pixel Glow settings. Falls back to defaults for
        -- action-bar overlays and bars that never set the values.
        local N, th, period
        if opts then
            N = opts.N or 8; th = opts.th or 2; period = opts.period or 4
        else
            local pfc = _ecmeFC[parent]
            local pbd = pfc and pfc.barKey and ns.GetBarData and ns.GetBarData(pfc.barKey)
            N = (pbd and pbd.pixelGlowLines) or 8
            th = (pbd and pbd.pixelGlowThickness) or 2
            period = (pbd and pbd.pixelGlowSpeed) or 4
        end
        local lineLen = math.floor((pW + pH) * (2 / N - 0.1))
        lineLen = math.min(lineLen, math.min(pW, pH))
        if lineLen < 1 then lineLen = 1 end
        _G_Glows.StartProceduralAnts(overlay, N, th, period, lineLen, cr, cg, cb, pW, pH)
    elseif entry.buttonGlow then
        _G_Glows.StartButtonGlow(overlay, pW, cr, cg, cb, nil, pH)
    elseif entry.autocast then
        _G_Glows.StartAutoCastShine(overlay, pW, cr, cg, cb, 1.0, pH)
    else
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
        local ss = (ns.ResolveSpellSettings and ns.ResolveSpellSettings(icon, sid, sd))
            or (sd and sd.spellSettings and sd.spellSettings[sid])
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

-- Proc glow color: hardcoded gold (#ffc923)
local PROC_GLOW_COLOR = { 1.0, 0.788, 0.137 }

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
        local cr, cg, cb = PROC_GLOW_COLOR[1], PROC_GLOW_COLOR[2], PROC_GLOW_COLOR[3]
        ShowProcGlow(ourIcon, cr, cg, cb)
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
local function ApplyBarPositionCentered(frame, pos, barKey)
    if not pos or not pos.point then return end
    local px, py = pos.x or 0, pos.y or 0
    local anchor = pos.point

    -- Runtime conversion: if a non-CENTER-grow bar still has a CENTER position
    -- (legacy data, Blizzard import, or dev migration gap), convert to edge
    -- format for SetPoint so the bar grows from the correct edge.
    -- No persistence: positions are only saved by unlock mode's Save & Exit.
    if anchor == "CENTER" and barKey then
        local bd = barDataByKey[barKey]
        local grow = bd and bd.growDirection or "CENTER"
        if grow ~= "CENTER" then
            local fw = frame:GetWidth() or 0
            local fh = frame:GetHeight() or 0
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
    -- edges land on whole pixels. For edge anchors (LEFT/RIGHT/TOP/BOTTOM),
    -- the offset already represents an edge position and SnapForES is correct.
    local PPa = EllesmereUI and EllesmereUI.PP
    if PPa then
        local es = frame:GetEffectiveScale()
        if anchor == "CENTER" and PPa.SnapCenterForDim then
            local fw = frame:GetWidth() or 0
            local fh = frame:GetHeight() or 0
            px = PPa.SnapCenterForDim(px, fw, es)
            py = PPa.SnapCenterForDim(py, fh, es)
        elseif PPa.SnapForES then
            px = PPa.SnapForES(px, es)
            py = PPa.SnapForES(py, es)
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

    -- Determine anchor point from grow direction so the bar's fixed edge
    -- stays put when icon count changes (spec swaps, combat buff churn).
    local bd = barDataByKey[barKey]
    local grow = bd and bd.growDirection or "CENTER"
    local pt
    if grow == "RIGHT" then pt = "LEFT"
    elseif grow == "LEFT"  then pt = "RIGHT"
    elseif grow == "DOWN"  then pt = "TOP"
    elseif grow == "UP"    then pt = "BOTTOM"
    elseif grow == "CENTER" then pt = "CENTER"
    else                        pt = "CENTER"
    end

    local ax, ay
    if pt == "LEFT" then
        local lx = frame:GetLeft()
        if not lx then return end
        local cy = select(2, frame:GetCenter())
        if not cy then return end
        ax = lx * ratio
        ay = cy * ratio
    elseif pt == "RIGHT" then
        local rx = frame:GetRight()
        if not rx then return end
        local cy = select(2, frame:GetCenter())
        if not cy then return end
        ax = rx * ratio
        ay = cy * ratio
    elseif pt == "TOP" then
        local cx = frame:GetCenter()
        if not cx then return end
        local ty = frame:GetTop()
        if not ty then return end
        ax = cx * ratio
        ay = ty * ratio
    elseif pt == "BOTTOM" then
        local cx = frame:GetCenter()
        if not cx then return end
        local by = frame:GetBottom()
        if not by then return end
        ax = cx * ratio
        ay = by * ratio
    elseif pt == "CENTER" then
        local cx, cy = frame:GetCenter()
        if not cx or not cy then return end
        ax = cx * ratio
        ay = cy * ratio
    end

    -- Store relative to UIParent CENTER so offset math is consistent
    p.cdmBarPositions[barKey] = {
        point = pt, relPoint = "CENTER",
        x = (ax - uiW / 2) / scale,
        y = (ay - uiH / 2) / scale,
    }
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
        frame:SetFrameStrata("MEDIUM")
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

    -- Restore default strata/level (skip if cursor-anchored; that path uses TOOLTIP/9980)
    if not frame._mouseTrack then
        frame:SetFrameStrata("MEDIUM")
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
        frame:SetFrameStrata("MEDIUM")
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
                            icons[ii]:SetFrameStrata("MEDIUM")
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

-- Compute stride respecting topRowCount override (only for numRows == 2)
local function ComputeTopRowStride(barData, count)
    local numRows = barData.numRows or 1
    if numRows < 1 then numRows = 1 end
    if numRows == 2 and barData.customTopRowEnabled and barData.topRowCount and barData.topRowCount > 0 then
        local topCount = math.min(barData.topRowCount, count)
        local bottomCount = count - topCount
        -- Custom top-row mode only spills into a second row once the icon count
        -- actually exceeds the top-row count. Until then, report ONE effective
        -- row so the bar doesn't reserve space for (or lay out) an empty second
        -- row. The second row appears the moment a bottom-row icon exists.
        if bottomCount <= 0 then
            return topCount, 1, topCount
        end
        return math.max(topCount, bottomCount), numRows, topCount
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
    local totalWPx, totalHPx
    if isHoriz then
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
            icon:SetFrameStrata("MEDIUM")
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

    -- SetSize AFTER icon positioning: ensures bar resize and icon placement
    -- both take effect on the same rendered frame (no 1-frame size mismatch).
    if not skipResize then
        local oldW = frame:GetWidth() or 0
        local oldH = frame:GetHeight() or 0
        EllesmereUI._layoutBarResizing = unlockKey
        pcall(frame.SetSize, frame, totalW, totalH)
        EllesmereUI._layoutBarResizing = nil
        -- Anchor offset maintenance: when a growth-direction bar resizes,
        -- the center shifts by delta/2 but the fixed edge stays put.
        -- Adjust the center-based anchor offset so the relationship stays
        -- consistent on /reload.
        -- This is NOT a position write (positions are only saved by Save & Exit).
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
                -- Horizontal growth (LEFT/RIGHT): adjust offsetX on TOP/BOTTOM anchors
                local dw = totalW - oldW
                if math.abs(dw) > 0.1 and (side == "TOP" or side == "BOTTOM") then
                    if grow == "RIGHT" then
                        ai.offsetX = ai.offsetX + dw / 2
                    elseif grow == "LEFT" then
                        ai.offsetX = ai.offsetX - dw / 2
                    end
                    if PPo and uiES then ai.offsetX = PPo.SnapForES(ai.offsetX, uiES) end
                end
                -- Vertical growth (UP/DOWN): adjust offsetY on LEFT/RIGHT anchors
                local dh = totalH - oldH
                if math.abs(dh) > 0.1 and (side == "LEFT" or side == "RIGHT") then
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
ApplyShapeToCDMIcon = function(icon, shape, barData)
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
            EllesmereUI.ApplyBorderStyle(bdrTarget, borderSz, brdR, brdG, brdB, brdA, texKey, barData.borderTextureOffset, barData.borderTextureOffsetY, barData.borderTextureShiftX, barData.borderTextureShiftY, "cdm", barData.borderThickness or "thin")
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
                tex:SetTexCoord(zoom, 1 - zoom, zoom + 0.10 + extraCrop, 1 - zoom - 0.10 - extraCrop)
            else
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

-- (UpdateCustomBarIcons removed -- all bars now use hook-based CollectAndReanchor)

-- (UpdateCDMBarIcons removed -- replaced by hook-based CollectAndReanchor)
-- (UpdateAllCDMBars tick loop removed -- replaced by event-driven hooks)

-- Refresh visual properties of existing icons (called when settings change)
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
        if isBuffFamilyBar then
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
                if sdb and sdb.spellSettings then
                    -- Shared resolver: matches the key against the frame's full
                    -- identity set (canon first, then resolvedSid / baseSpellID).
                    ssb = (ns.ResolveSpellSettings and ns.ResolveSpellSettings(icon, sidb, sdb))
                        or sdb.spellSettings[sidb]
                end
            end
            -- Stash the effective Buff Glow on fd so the BuffTicker hot path reads
            -- it without a per-tick lookup. Only restart the live glow when the
            -- effective value actually changed (no flicker on no-op rebuilds).
            local nT = ssb and ssb.buffGlow           -- nil = inherit, number = override (0 = None)
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
            cd:SetSwipeColor(0, 0, 0, barData.swipeAlpha or 0.7)
            cd:SetHideCountdownNumbers(not showCD)
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
            EllesmereUI.ApplyBorderStyle(bdrTgt, borderSize, barData.borderR or 0, barData.borderG or 0, barData.borderB or 0, barData.borderA or 1, textureKey, barData.borderTextureOffset, barData.borderTextureOffsetY, barData.borderTextureShiftX, barData.borderTextureShiftY, "cdm", barData.borderThickness or "thin")
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
        local scX = (ssb and ssb.stackCountX) or barData.stackCountX or 0
        local scY = (ssb and ssb.stackCountY) or barData.stackCountY or 0
        -- Stack/charge/item-count text anchor. Default bottom-right keeps the
        -- historical +2 vertical nudge so existing bars stay pixel-identical;
        -- top and center positions sit flush with no baseline nudge.
        local scPoint = (ssb and ssb.stackCountPosition) or barData.stackCountPosition or "bottomright"
        if scPoint == "bottomleft" then scPoint = "BOTTOMLEFT"; scY = scY + 2
        elseif scPoint == "topright" then scPoint = "TOPRIGHT"
        elseif scPoint == "topleft" then scPoint = "TOPLEFT"
        elseif scPoint == "center" then scPoint = "CENTER"
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

        -- Apply custom shape (overrides border/zoom set above)
        local shape = barData.iconShape or "none"
        ApplyShapeToCDMIcon(icon, shape, barData)

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
            ShowProcGlow(icon, PROC_GLOW_COLOR[1], PROC_GLOW_COLOR[2], PROC_GLOW_COLOR[3])
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
                local ss = sd and sd.spellSettings and sd.spellSettings[sid]
                if not ss and sd and sd.spellSettings and sd.assignedSpells
                   and C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                    for _, asid in ipairs(sd.assignedSpells) do
                        if asid and asid > 0 and asid ~= sid
                           and sd.spellSettings[asid] then
                            if C_SpellBook.FindSpellOverrideByID(asid) == sid then
                                ss = sd.spellSettings[asid]
                                break
                            end
                        end
                    end
                end
                local cse = ss and ss.cdStateEffect
                if (cse == "pixelGlowReady" or cse == "buttonGlowReady") and glowOv then
                    local glowLive = sid
                    if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                        glowLive = C_SpellBook.FindSpellOverrideByID(sid) or sid
                    end
                    local cseInfo = C_Spell.GetSpellCooldown(glowLive)
                    if cseInfo and (not cseInfo.isActive or cseInfo.isOnGCD) then
                        local gr, gg, gb = ResolveGlowColor(ss)
                        StartNativeGlow(glowOv, cse == "pixelGlowReady" and 1 or 3, gr or 1, gg or 1, gb or 1)
                        ifd._cdStateGlowOn = true
                    end
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
            local csSs = csSd and csSd.spellSettings and csSd.spellSettings[csSid]
            if not csSs and csSd and csSd.spellSettings and csSd.assignedSpells
               and C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                for _, asid in ipairs(csSd.assignedSpells) do
                    if asid and asid > 0 and asid ~= csSid
                       and csSd.spellSettings[asid] then
                        if C_SpellBook.FindSpellOverrideByID(asid) == csSid then
                            csSs = csSd.spellSettings[asid]
                            break
                        end
                    end
                end
            end
            local cse = csSs and csSs.cdStateEffect
            if cse then
                local csLive = csSid
                if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                    csLive = C_SpellBook.FindSpellOverrideByID(csSid) or csSid
                end
                local cseInfo = C_Spell.GetSpellCooldown(csLive)
                local onCD = cseInfo and cseInfo.isActive and not cseInfo.isOnGCD
                if cse == "hiddenOnCD" or cse == "hiddenReady" then
                    local hide = (cse == "hiddenOnCD") == onCD
                    icon:SetAlpha(hide and 0 or (barData.barOpacity or 1))
                    if fc then fc._cdStateHidden = hide or false end
                else
                    -- Clear stale hidden state when switching to a glow effect
                    if fc and fc._cdStateHidden then
                        fc._cdStateHidden = false
                        icon:SetAlpha(barData.barOpacity or 1)
                    end
                    if not ifd or not ifd._cdStateGlowOn then
                        if (cse == "pixelGlowReady" or cse == "buttonGlowReady")
                           and not onCD and glowOv then
                            local gr, gg, gb = ResolveGlowColor(csSs)
                            StartNativeGlow(glowOv, cse == "pixelGlowReady" and 1 or 3, gr or 1, gg or 1, gb or 1)
                            if ifd then ifd._cdStateGlowOn = true end
                        end
                    end
                end
            elseif fc and fc._cdStateHidden then
                fc._cdStateHidden = false
                icon:SetAlpha(barData.barOpacity or 1)
            end
        end
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
    ["none"]     = nil,
    ["airhorn"]  = _SOUNDS_DIR .. "AirHorn.ogg",
    ["banana"]   = _SOUNDS_DIR .. "BananaPeelSlip.ogg",
    ["bikehorn"] = _SOUNDS_DIR .. "BikeHorn.ogg",
    ["boxing"]   = _SOUNDS_DIR .. "BoxingArenaSound.ogg",
    ["water"]    = _SOUNDS_DIR .. "WaterDrop.ogg",
}
local FOCUSKICK_SOUND_NAMES = {
    ["none"]     = "None",
    ["airhorn"]  = "Air Horn",
    ["banana"]   = "Banana Peel Slip",
    ["bikehorn"] = "Bike Horn",
    ["boxing"]   = "Boxing Arena",
    ["water"]    = "Water Drop",
}
local FOCUSKICK_SOUND_ORDER = {
    "none", "airhorn", "banana", "bikehorn", "boxing", "water",
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

            -- Priority 1: vehicle always hides
            if inVehicle then
                shouldHide = true
            -- Priority 2: visibility options (checkbox dropdown)
            elseif EllesmereUI.CheckVisibilityOptions(barData) then
                shouldHide = true
            -- Priority 3: visibility mode dropdown
            elseif vis == "never" then
                shouldHide = true
            elseif vis == "in_combat" then
                shouldHide = not inCombat
            elseif vis == "out_of_combat" then
                shouldHide = inCombat
            elseif vis == "in_raid" then
                shouldHide = not inRaid
            elseif vis == "in_party" then
                shouldHide = not (inParty or inRaid)
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
                -- fresh loads where wasHidden is false).
                local visAlpha = barData.barOpacity or 1
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
                            if not (icfc and icfc._cdStateHidden) then
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
    local a = barData.barOpacity or 1
    local icons = cdmBarIcons[barKey]
    if icons then
        for i = 1, #icons do
            local ic = icons[i]
            if ic then
                local icfc = _ecmeFC[ic]
                if not (icfc and icfc._cdStateHidden) then
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
--  Reads HotKey text directly from action button frames -- the same source
--  the action bar itself uses, so it's always correct regardless of bar addon.
--  Deferred if called during combat; fires on PLAYER_REGEN_ENABLED instead.
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
                    local btn = _G["ActionButton" .. i]
                    if btn and btn.action then slot = btn.action end
                end
                local slotType, id = GetActionInfo(slot)
                local spellID
                local fromMacro = false
                if slotType == "spell" then
                    spellID = id
                elseif slotType == "macro" and id then
                    local macroSpell = GetMacroSpell(id)
                    spellID = macroSpell or (id > 0 and id) or nil
                    fromMacro = true
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

-- Public entry point: rebuild cache then apply. Defers if in combat.
local function UpdateCDMKeybinds()
    if _inCombat then
        _keybindRebuildPending = true
        return
    end
    _keybindRebuildPending = false
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

    local p = ECME.db.profile

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
    for i, barData in ipairs(p.cdmBars.bars) do
        barDataByKey[barData.key] = barData
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
        if not isBuff then
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
function ns.ReseedAssignedSpellsFromLiveIcons()
    local p = ECME and ECME.db and ECME.db.profile
    if not p or not p.cdmBars then return end
    for _, barData in ipairs(p.cdmBars.bars) do
        if not barData.isGhostBar
           and barData.key ~= "buffs"
           and (barData.barType == "cooldowns" or barData.barType == "utility"
                or barData.barType == "buffs"
                or MAIN_BAR_KEYS[barData.key]) then
            local sd = ns.GetBarSpellData(barData.key)
            local icons = ns.cdmBarIcons and ns.cdmBarIcons[barData.key]
            if sd and icons then
                if not sd.assignedSpells then sd.assignedSpells = {} end
                local seen = {}
                for _, existing in ipairs(sd.assignedSpells) do
                    seen[existing] = true
                end
                for _, icon in ipairs(icons) do
                    local fc = ns._ecmeFC and ns._ecmeFC[icon]
                    local sid = fc and fc.spellID
                    if type(sid) == "number" and sid > 0 and not seen[sid] then
                        sd.assignedSpells[#sd.assignedSpells + 1] = sid
                        seen[sid] = true
                    end
                end
            end
        end
    end
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
                    if grow and grow ~= "CENTER" and frame then
                        local fw = frame:GetWidth() or 0
                        local fh = frame:GetHeight() or 0
                        if grow == "RIGHT" and fw > 0 then
                            storePoint = "LEFT"
                            storeX = x - fw / 2
                        elseif grow == "LEFT" and fw > 0 then
                            storePoint = "RIGHT"
                            storeX = x + fw / 2
                        elseif grow == "DOWN" and fh > 0 then
                            storePoint = "TOP"
                            storeY = y + fh / 2
                        elseif grow == "UP" and fh > 0 then
                            storePoint = "BOTTOM"
                            storeY = y - fh / 2
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
                    -- Convert edge-stored positions back to CENTER for the
                    -- unlock mode system (it always works with CENTER coords).
                    local pt = pos.point
                    if pt == "LEFT" or pt == "RIGHT" or pt == "TOP" or pt == "BOTTOM" then
                        local frame = cdmBarFrames[key]
                        if frame then
                            local fw = frame:GetWidth() or 0
                            local fh = frame:GetHeight() or 0
                            local cx, cy = pos.x or 0, pos.y or 0
                            if pt == "LEFT" then
                                cx = cx + fw / 2
                            elseif pt == "RIGHT" then
                                cx = cx - fw / 2
                            elseif pt == "TOP" then
                                cy = cy - fh / 2
                            elseif pt == "BOTTOM" then
                                cy = cy + fh / 2
                            end
                            return { point = "CENTER", relPoint = pos.relPoint, x = cx, y = cy }
                        end
                    end
                    return pos
                end,
                clearPos = function()
                    ECME.db.profile.cdmBarPositions[key] = nil
                end,
                applyPos = function()
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
                                frame:SetFrameStrata("MEDIUM")
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
        for _, icons in pairs(cdmBarIcons) do
            for _, icon in ipairs(icons) do
                local ifc = _ecmeFC[icon]
                local sid = ifc and ifc.spellID
                if sid and sid == suggestedSpell and icon:IsShown() then
                    _rotShow(icon)
                    newSet[icon] = true
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
    if event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
        -- Defer to a clean execution context: the event handler chain can
        -- carry taint from other addons, which propagates into LayoutCDMBar
        -- when a bar transitions from hidden to visible (visHideMounted).
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
        -- Flush deferred keybind rebuild that was blocked during combat
        if event == "PLAYER_REGEN_ENABLED" and _keybindRebuildPending then
            UpdateCDMKeybinds()
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
        -- Arena exit backstop: leaving an arena reverts PvP talents and
        -- spell overrides, and Blizzard re-evaluates the viewer's tracked
        -- cooldown set. If PLAYER_PVP_TALENT_UPDATE did not fire across the
        -- zone-out, nothing re-claims the new pool frames and the
        -- unclaimed-frame cleanup blanks them (arena-exit empty-CDM bug).
        -- Schedule the same debounced rebuild a talent change gets; the
        -- token debounce collapses this with the event-driven trigger when
        -- both fire, so at most one rebuild runs.
        local _, instType = IsInInstance()
        if ns._cdmWasInArena and instType ~= "arena" then
            ScheduleTalentRebuild()
        end
        ns._cdmWasInArena = (instType == "arena") or nil
        -- Install rotation helper hook after CDM frames have been built
        C_Timer.After(1, function()
            InstallRotationHook()
        end)
        -- Safety: re-apply visibility after rebuild settles. Blizzard may
        -- hide/re-show CDM viewers during loading screens (PvP scoreboard,
        -- barbershop) and the timing race can leave viewer alpha at 0.
        C_Timer.After(1.5, _CDMApplyVisibility)
    end
    if event == "SPELLS_CHANGED" then
        CheckSpecChange()
        if not ns._spellsReadyForApply then
            ns._spellsReadyForApply = true
            if ns._pendingApplyOnReanchor and ns.QueueReanchor then
                ns.QueueReanchor()
            end
        end
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
                for i = 1, math.min(count, 6) do
                    local icon = icons[i]
                    local fc = fcCache and fcCache[icon]
                    local sid = (fc and fc.spellID) or 0
                    local name = sid and sid > 0 and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(sid) or "?"
                    preview[i] = tostring(sid) .. ":" .. tostring(name)
                end
                if count > 6 then preview[#preview + 1] = "..." end
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

    -- 5. Raw frame walk: for each frame in Essential and Utility, dump
    --    cdID, GetSpellID, info.spellID, info.overrideSpellID, canonical
    P(ACCENT .. "--- Raw viewer pool walk ---" .. OFF)
    local gci = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
    for _, vName in ipairs({ "EssentialCooldownViewer", "UtilityCooldownViewer" }) do
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
                P(string.format("  [%s#%d] cdID=%s frameSID=%s info.sID=%s info.ovrSID=%s canon=%s (%s) shown=%s",
                    vName, count, tostring(cdID), tostring(frameSid),
                    tostring(infoSpellID), tostring(infoOverride),
                    tostring(canonical), tostring(canonName), tostring(frame:IsShown())))
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

