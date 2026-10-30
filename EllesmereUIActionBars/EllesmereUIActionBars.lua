if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIActionBars.lua  Custom Action Bars
--  Own secure action bar frames AND buttons (EABButton/ActionBarButtonTemplate),
--  eliminating the taint surface from reusing Blizzard's protected buttons.
--  Stance/Pet bars still reuse Blizzard buttons (own secure handling).
--  Keybinds: SetOverrideBindingClick for all bars. Paging: RegisterStateDriver
--  + _childupdate-eab-page with explicit action attrs.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EllesmereUI and EllesmereUI._ModuleNS and EllesmereUI.NewInternals and EllesmereUI.NewCombatQueue and EllesmereUI.SetFramePoint and EllesmereUI.HideFrame and EllesmereUI._Pool) then EUI_CLIENT_BLOCKED = true; return end -- stale-parent guard: a partially updated install (old parent, new child) goes dormant via the line-1 failsafe instead of erroring (the extra bars move Edit Mode systems through the parent's SetFramePoint, and Blizzard's main bar hides through its HideFrame)
EllesmereUI._ModuleNS[ADDON_NAME] = ns  -- LOD options files read this module ns via the registry
local EAB = EllesmereUI.Lite.NewAddon(ADDON_NAME)
ns.EAB = EAB

function ns.IsMasqueAvailable()
    return LibStub and LibStub("Masque", true) ~= nil
end

function ns.InitializeMasque()
    if ns.MasqueGroup then return true end
    local masque = LibStub and LibStub("Masque", true)
    if not masque then return false end
    ns.MasqueGroup = masque:Group(ADDON_NAME, "Action Bars")
    return ns.MasqueGroup ~= nil
end

-- Released core versions may predate the CVar tracking helper.
-- Prefer tracking when available; otherwise use Blizzard's setter.
local function SetActionBarCVar(name, value, owner)
    if EllesmereUI.SetCVar then
        return EllesmereUI.SetCVar(name, value, owner)
    end
    return C_CVar.SetCVar(name, value)
end

local PP = EllesmereUI.PP

-- CPU-attribution shell pool: the engine bills a handler's whole call tree to the addon
-- whose context CREATED the frame it entered through, so frames born in build/enable
-- code bill the PARENT forever (probe-verified, see EllesmereUI_Ticker.lua). Shells
-- born in this main chunk stamp to ActionBars; runtime code should call ns.TakeShell()
-- instead of CreateFrame for persistent hosts carrying events/scripts. No release, so
-- transient throwaway frames keep using CreateFrame.
do
    local pool = {}
    local n = 40
    for i = 1, n do pool[i] = CreateFrame("Frame") end
    ns.TakeShell = function()
        if n > 0 then
            local f = pool[n]
            pool[n] = nil
            n = n - 1
            return f
        end
        -- Pool exhausted (not expected): frame just bills the parent; bump n if it happens.
        return CreateFrame("Frame")
    end
end

-- "Run once after combat" for every combat-gated deferral in this file. The shell is
-- taken in the main chunk, so drained work bills ActionBars. Keys are per purpose, and
-- sites that defer the same work share a key (e.g. "UpdateKeybinds").
ns.CombatQueue = EllesmereUI.NewCombatQueue(ns.TakeShell())

-- "Hide Count at 0" (Icon Effects): hide a zero charge/stack count via the
-- count fontstring's ALPHA, never its text -- text is co-owned: Blizzard's
-- mixin keeps SPELL_UPDATE_CHARGES registered and rewrites Count with the raw
-- value every charge event, but nothing engine-side touches alpha (same as
-- the CDM twin). Memoized so only real changes write; fails open on SECRET
-- values (combat) so the count shows rather than risk a tainted compare. Off
-- = one profile read + memo compare, zero machinery. (On ns, not a
-- chunk local.)
ns._EABZeroCountAlpha = function(fd, fs, v, action)
    local pdb = EAB.db and EAB.db.profile
    if not (pdb and pdb.hideZeroCount) then
        -- OFF fast path: reads + memo compare only, except healing a leftover hidden
        -- stamp so a button can't stay stuck invisible after a toggle/profile switch.
        -- Profile read IS the gate: a cached flag would go stale across profiles.
        if fd._zeroCountAlpha == 0 then
            fd._zeroCountAlpha = 1
            fs:SetAlpha(1)
        end
        return
    end
    local a = 1
    if action then
        -- Charge spells route EXCLUSIVELY through the count: SetAlpha clamps
        -- to [0,1], so alpha := currentCharges hides at exactly 0 and shows
        -- at 1+ with no comparison needed. Never infer zero charges from an active
        -- cooldown record -- charges banked while the main cooldown runs (e.g. Feint)
        -- would hide a real count. SetAlpha accepts secret numbers
        -- (AllowedWhenTainted), so the same write runs in and out of instanced combat;
        -- a secret count writes through with the memo dirtied, never stored/compared.
        local ci = C_ActionBar.GetActionCharges and C_ActionBar.GetActionCharges(action)
        local mc = ci and ci.maxCharges
        if mc ~= nil and not (issecretvalue and issecretvalue(mc)) and mc > 1 then
            local cc = ci.currentCharges
            -- issecretvalue FIRST, and type() rather than == nil for the missing
            -- case. The count is secret whenever cooldowns are restricted, and
            -- comparing a secret to nil is the operation our own secret rules
            -- forbid -- so ordering the nil "belt" ahead of the guard made the
            -- belt the hazard, and a throw strands the count HIDDEN rather than
            -- protecting it. Same defect and same fix as the CDM counterpart in
            -- EllesmereUICdmHooks (EvalZeroChargeTextFrame).
            if issecretvalue and issecretvalue(cc) then
                fd._zeroCountAlpha = nil
                fs:SetAlpha(cc)
            elseif type(cc) ~= "number" then
                if fd._zeroCountAlpha ~= 1 then
                    fd._zeroCountAlpha = 1
                    fs:SetAlpha(1)
                end
            else
                a = cc > 1 and 1 or cc
                if fd._zeroCountAlpha ~= a then
                    fd._zeroCountAlpha = a
                    fs:SetAlpha(a)
                end
            end
            return
        end
        -- Non-charge: mixin shows GetActionCount for consumables/stackables
        -- (including 0); display string is only the cheap first check.
        -- issecretvalue FIRST: v is GetActionDisplayCount's return, which the
        -- API documents as secret whenever cooldowns are restricted, and
        -- comparing a secret to nil is the operation our own rules forbid --
        -- the same ordering defect this function's charge branch above already
        -- carries a comment about. The nil case needs no test of its own:
        -- nil == 0 is simply false.
        if not (issecretvalue and issecretvalue(v))
           and (v == 0 or v == "0") then
            a = 0
        elseif (IsConsumableAction and IsConsumableAction(action))
            or (IsStackableAction and IsStackableAction(action)) then
            local c = GetActionCount and GetActionCount(action)
            if c ~= nil and not (issecretvalue and issecretvalue(c)) and c == 0 then
                a = 0
            end
        end
    end
    if fd._zeroCountAlpha ~= a then
        fd._zeroCountAlpha = a
        fs:SetAlpha(a)
    end
end

-- Cold-path helper table for module-level behavior that benefits from a
-- shared dispatch surface without adding more direct top-level helpers.
local EAB_VTABLE = {
    ExtraBars = {},
    CooldownFonts = {},
    Hover = {},
    MainBarPageSync = {},
}
ns.EAB_VTABLE = EAB_VTABLE

EAB.VisibilityCompat = EAB.VisibilityCompat or {}


-------------------------------------------------------------------------------
--  Upvalues
-------------------------------------------------------------------------------
local _G = _G
local ipairs, pairs, type, pcall = ipairs, pairs, type, pcall
local abs, ceil, floor, min, max = math.abs, math.ceil, math.floor, math.min, math.max
local wipe, tinsert = wipe, table.insert
local InCombatLockdown = InCombatLockdown
local hooksecurefunc = hooksecurefunc
local C_Timer_After = C_Timer.After

-- External weak-keyed lookup for per-frame state (avoids writing custom
-- properties onto Blizzard-owned frame tables, which causes taint).
-- Stored on ns, not in a file-scope local.
ns._eabFD = setmetatable({}, { __mode = "k" })
function ns.EFD(frame)
    local d = ns._eabFD[frame]
    if not d then d = {}; ns._eabFD[frame] = d end
    return d
end

-- Local alias for hot-path EFD access
local EFD = ns.EFD

-- Empty-slot parks live in EFD(btn).parkA0, so no decision reads a button's
-- alpha (another addon may write a secret one there). nil = our last write was
-- alpha 1, or there was none (default 1). 1 = we wrote alpha 0. 2 = we wrote
-- alpha 0 on a button the secure un-park code can reveal; that code sets alpha 1
-- on every hidden->shown edge, so the button is parked only while hidden. Our
-- own Show() keeps alpha, so each Lua Show site turns a surfaced 2 into 1.
function ns._eabParked(btn)
    local d = ns._eabFD[btn]
    local p = d and d.parkA0
    if p == 2 then return not btn:IsShown() end
    return p == 1
end

-- Record an alpha-0 park on btn, right after the write. afterOwnHide: our
-- out-of-combat Hide() came after the 0, and the secure OnHide re-check can
-- re-show the button at alpha 1 inside that Hide; 2 covers both outcomes.
function ns._eabMarkParked(btn, info, afterOwnHide)
    local revealable = not info.isStance and not info.isPetBar
    EFD(btn).parkA0 = (revealable and (afterOwnHide or not btn:IsShown())) and 2 or 1
end

-- The style Action Bars render: "eui" | "blizzard" | "classic". A LIVE
-- profile read, no latch: the Style page reloads the UI on every change, so
-- build-time gating is safe. "eui" without a profile; both flags set resolves
-- classic. Stock-mode sites ask `~= "eui"`, kit sites ask `== "classic"`.
function ns.AB_Style()
    local p = EAB.db and EAB.db.profile
    if not p then return "eui" end
    return (p.useClassicStyle and "classic") or (p.useBlizzardStyle and "blizzard") or "eui"
end

-- The WoW Forever variant of Blizzard Style (the Forever client only): the
-- bars render Blizzard Style (AB_Style() stays "blizzard", every stock site
-- is unchanged) and the profile's sibling useForeverStyle flag, set together
-- with the Blizzard flag, adds the Forever-only pieces. A LIVE read like
-- AB_Style; false on every other client.
function ns.AB_Forever()
    if EllesmereUI.IS_FOREVER ~= true then return false end
    local p = EAB.db and EAB.db.profile
    if not (p and p.useForeverStyle == true) then return false end
    return ns.AB_Style() == "blizzard"
end

-- WoW Forever's frame and dividers behind a bar (Show Bar Background), under
-- the variant only: the bar's own foreverBarBg. nil reads the bar's default:
-- Action Bar 1 follows the profile-wide foreverHideBarBg (shown unless it is
-- set), every other bar is off.
function ns.AB_ForeverBg(key)
    if not ns.AB_Forever() then return false end
    local p = EAB.db.profile
    local s = p.bars and p.bars[key]
    local v = s and s.foreverBarBg
    if v == nil then v = key == "MainBar" and p.foreverHideBarBg ~= true end
    return v and true or false
end

-- SetAtlas for a stock-look texture: EllesmereUI.StockAtlas (retail art
-- where the Forever client swaps the name), native under the WoW Forever
-- look. Plain SetAtlas on retail.
function ns.AB_StockAtlas(tex, name, ...)
    if ns.AB_Forever() then return tex:SetAtlas(name, ...) end
    return EllesmereUI.StockAtlas(tex, name, ...)
end

-- The button shape the bar LAYOUT sizes for. Stock styles draw no custom
-- shape (ApplyShapesForBar and the options preview skip it), so their
-- buttons take neither the shape expansion nor the Cropped squash, whatever
-- the EllesmereUI-style setting holds. Icon Size itself applies in every
-- style (stock buttons scale their native art to it).
function ns.AB_LayoutShape(s, barKey)
    if barKey and ns.MasqueOwnsBar(barKey) then return "none" end
    if ns.AB_Style() ~= "eui" then return "none" end
    return (s and s.buttonShape) or "none"
end
local RegisterStateDriver = RegisterStateDriver
local RegisterAttributeDriver = RegisterAttributeDriver
local GetBindingKey = GetBindingKey
local NUM_ACTIONBAR_BUTTONS = NUM_ACTIONBAR_BUTTONS or 12

-------------------------------------------------------------------------------
--  Bar configuration
-------------------------------------------------------------------------------
local BAR_CONFIG = {
    -- nativeMainBar: MainBar buttons keep native IDs (1-12), action via
    -- CalculateAction path 1; the bar's _onstate-page handler sets actionpage
    -- from the restricted env for form/vehicle/override paging. Keys flow via
    -- Blizzard's native ActionButtonDown/Up -> GetActionButtonForID -> _G["ActionButton"..id].
    { key = "MainBar",   label = "Action Bar 1 (Main)", barID = 1,  count = 12, blizzBtnPrefix = "ActionButton",              blizzFrame = "MainMenuBar", nativeMainBar = true },
    -- nativeActionPage: the Blizzard actionpage for this bar's slot range.
    -- Buttons keep native IDs; action = ID + (page-1)*12 (CalculateAction path
    -- 1). Keys flow via native MultiActionButtonDown/Up so UseAction gets
    -- isKeyPress=true (required for press-and-hold casting).
    { key = "Bar2",      label = "Action Bar 2",        barID = 2,  count = 12, blizzBtnPrefix = "MultiBarBottomLeftButton",   blizzFrame = "MultiBarBottomLeft",  nativeActionPage = 6 },
    { key = "Bar3",      label = "Action Bar 3",        barID = 3,  count = 12, blizzBtnPrefix = "MultiBarBottomRightButton",  blizzFrame = "MultiBarBottomRight", nativeActionPage = 5 },
    { key = "Bar4",      label = "Action Bar 4",        barID = 4,  count = 12, blizzBtnPrefix = "MultiBarRightButton",        blizzFrame = "MultiBarRight",       nativeActionPage = 3 },
    { key = "Bar5",      label = "Action Bar 5",        barID = 5,  count = 12, blizzBtnPrefix = "MultiBarLeftButton",         blizzFrame = "MultiBarLeft",        nativeActionPage = 4 },
    { key = "Bar6",      label = "Action Bar 6",        barID = 6,  count = 12, blizzBtnPrefix = "MultiBar5Button",          blizzFrame = "MultiBar5",           nativeActionPage = 13 },
    { key = "Bar7",      label = "Action Bar 7",        barID = 7,  count = 12, blizzBtnPrefix = "MultiBar6Button",          blizzFrame = "MultiBar6",           nativeActionPage = 14 },
    { key = "Bar8",      label = "Action Bar 8",        barID = 8,  count = 12, blizzBtnPrefix = "MultiBar7Button",          blizzFrame = "MultiBar7",           nativeActionPage = 15 },
    -- Bar9/Bar10: extra bars with NO native Blizzard frame; our own
    -- EABButton<slot> buttons, paged like Bars 2-8 via explicit-action +
    -- _childupdate-eab-page. customPage = the action page the slots live on:
    -- Bar9 = page 2 (slots 13-24, so converts' existing spells stay placed),
    -- Bar10 = page 10 (slots 109-120). Neither page has a Blizzard binding
    -- command, so keys route via SetOverrideBindingClick through the
    -- EUI_BAR9/10_BUTTON commands in Bindings.xml.
    { key = "Bar9",      label = "Action Bar 9",        barID = 0,  count = 12, customPage = 2 },
    { key = "Bar10",     label = "Action Bar 10",       barID = 0,  count = 12, customPage = 10 },
    { key = "StanceBar", label = "Stance Bar",          barID = 0,  count = 10, blizzBtnPrefix = "StanceButton",               blizzFrame = "StanceBar", isStance = true },
    { key = "PetBar",    label = "Pet Bar",             barID = 0,  count = 10, blizzBtnPrefix = "PetActionButton",            blizzFrame = "PetActionBar", isPetBar = true },
}

-- Aliases for the options file (which references these field names)
for _, info in ipairs(BAR_CONFIG) do
    info.buttonPrefix = info.blizzBtnPrefix
    info.frameName    = info.blizzFrame
    info.fallbackFrame = nil
end

local EXTRA_BARS = {
    { key = "MicroBar", label = "Micro Menu Bar", frameName = "MicroMenuContainer", hoverFrame = "MicroMenu", visibilityOnly = true, blizzOwnedVisibility = true },
    { key = "BagBar",   label = "Bag Bar",        frameName = "BagsBar", visibilityOnly = true, blizzOwnedVisibility = true },
    { key = "QueueStatus", label = "Queue Status", frameName = "QueueStatusButton", visibilityOnly = true, blizzOwnedVisibility = true, noManagedVisibility = true },
    { key = "XPBar",    label = "XP Bar",         visibilityOnly = true, isDataBar = true },
    { key = "RepBar",   label = "Reputation Bar",  visibilityOnly = true, isDataBar = true },
    { key = "FavorBar", label = "House Favor Bar", visibilityOnly = true, isDataBar = true },
    { key = "ExtraActionButton", label = "Extra Action Button", visibilityOnly = true, isBlizzardMovable = true },
    { key = "EncounterBar",      label = "Encounter Bar",         visibilityOnly = true, isBlizzardMovable = true },
}
-- WoW Forever has no extra action bar (no binding, no Edit Mode system for
-- it): no holder, mover or visibility row there, and its container is left
-- to Blizzard.
if EllesmereUI.IS_FOREVER then
    for i = #EXTRA_BARS, 1, -1 do
        if EXTRA_BARS[i].key == "ExtraActionButton" then table.remove(EXTRA_BARS, i) end
    end
end

local ALL_BARS = {}
for _, info in ipairs(BAR_CONFIG) do ALL_BARS[#ALL_BARS + 1] = info end
for _, info in ipairs(EXTRA_BARS) do ALL_BARS[#ALL_BARS + 1] = info end

local BAR_LOOKUP = {}
for _, info in ipairs(BAR_CONFIG) do BAR_LOOKUP[info.key] = info end
for _, info in ipairs(EXTRA_BARS) do BAR_LOOKUP[info.key] = info end

local function LatchMasqueBarOwnership()
    local latched = {}
    local bars = EAB and EAB.db and EAB.db.profile and EAB.db.profile.bars
    if bars then
        for _, info in ipairs(BAR_CONFIG) do
            if not info.isStance and not info.isPetBar then
                local settings = bars[info.key]
                latched[info.key] = settings and settings.masqueEnabled == true or false
            end
        end
    end
    ns._masqueBarsLatched = latched
end

function ns.MasqueOwnsBar(key)
    local info = BAR_LOOKUP[key]
    if not (ns.MasqueGroup and info) then return false end
    if info.isStance or info.isPetBar then return false end
    local latched = ns._masqueBarsLatched
    return latched and latched[key] == true or false
end

-- Expose AB bar keys immediately so unlock mode's ApplyAnchorPosition can gate
-- edge logic to CDM/AB without waiting for deferred RegisterWithUnlockMode.
if not EllesmereUI._abBarKeys then EllesmereUI._abBarKeys = {} end
for _, info in ipairs(BAR_CONFIG) do EllesmereUI._abBarKeys[info.key] = true end

local BAR_DROPDOWN_VALUES = {}
local BAR_DROPDOWN_ORDER = {}
do
    local _DROPDOWN_EXCLUDE = { ExtraActionButton = true, EncounterBar = true, QueueStatus = true }
    for _, info in ipairs(ALL_BARS) do
        if not _DROPDOWN_EXCLUDE[info.key] then
            BAR_DROPDOWN_VALUES[info.key] = info.label
            BAR_DROPDOWN_ORDER[#BAR_DROPDOWN_ORDER + 1] = info.key
        end
    end
end

local VISIBILITY_ONLY = {}
for _, info in ipairs(EXTRA_BARS) do
    VISIBILITY_ONLY[info.key] = true
end

local DATA_BAR = {}
for _, info in ipairs(EXTRA_BARS) do
    if info.isDataBar then DATA_BAR[info.key] = true end
end

ns.BAR_DROPDOWN_VALUES = BAR_DROPDOWN_VALUES
ns.BAR_DROPDOWN_ORDER  = BAR_DROPDOWN_ORDER
ns.VISIBILITY_ONLY     = VISIBILITY_ONLY
ns.DATA_BAR            = DATA_BAR
ns.BAR_LOOKUP          = BAR_LOOKUP
ns.ALL_BARS            = ALL_BARS
ns.EXTRA_BARS          = EXTRA_BARS

function EAB.VisibilityCompat.ApplyMode(settings, mode)
    if not settings then return "always" end

    mode = mode or "always"
    settings.barVisibility = mode
    settings.alwaysHidden = (mode == "never")

    local wasMouseover = settings.mouseoverEnabled
    settings.mouseoverEnabled = (mode == "mouseover")
    if mode == "mouseover" then
        if not settings._savedBarAlpha then
            settings._savedBarAlpha = settings.mouseoverAlpha or 1
        end
        settings.mouseoverAlpha = 0
    elseif wasMouseover and settings._savedBarAlpha then
        settings.mouseoverAlpha = settings._savedBarAlpha
        settings._savedBarAlpha = nil
    end

    settings.combatHideEnabled = (mode == "out_of_combat")
    settings.combatShowEnabled = (mode == "in_combat")
    return mode
end

function EAB.VisibilityCompat.Normalize(settings)
    if not settings then return "always" end
    if settings.barVisibility then
        return EAB.VisibilityCompat.ApplyMode(settings, settings.barVisibility)
    end
    if settings.alwaysHidden then
        return EAB.VisibilityCompat.ApplyMode(settings, "never")
    end
    if settings.mouseoverEnabled then
        return EAB.VisibilityCompat.ApplyMode(settings, "mouseover")
    end
    if settings.combatShowEnabled then
        return EAB.VisibilityCompat.ApplyMode(settings, "in_combat")
    end
    if settings.combatHideEnabled then
        return EAB.VisibilityCompat.ApplyMode(settings, "out_of_combat")
    end
    return EAB.VisibilityCompat.ApplyMode(settings, "always")
end

-- Effective Never for runtime gates: an applied Visibility override replaces the
-- saved mode, so a Never bar with an Always override is NOT hidden, and
-- an Always bar with a Never override is. Raw alwaysHidden/barVisibility reads stay
-- correct only where the SHARED value is meant (sync copies, the setter itself).
function EAB.VisibilityCompat.IsNever(s)
    if not s then return false end
    local ov = EllesmereUI.VisOverrideValue(s)
    if ov then return ov == "never" end
    return (s.alwaysHidden or s.barVisibility == "never") and true or false
end

function EAB.VisibilityCompat.Copy(dst, src, dstNoGroupModes)
    if not dst or not src then return end

    local mode = EAB.VisibilityCompat.Normalize(src)
    EAB.VisibilityCompat.ApplyMode(dst, mode)

    if mode == "mouseover" then
        dst._savedBarAlpha = src._savedBarAlpha or src.mouseoverAlpha or 1
        dst.mouseoverAlpha = 0
    else
        dst.mouseoverAlpha = src.mouseoverAlpha
        dst._savedBarAlpha = nil
    end

    -- Show During Drag / Show When Spellbook Is Open travel with the copy
    -- (inert unless target mode is Never).
    dst.dragShow = src.dragShow
    dst.spellbookShow = src.spellbookShow

    -- Multi-select set travels with the copy (after ApplyMode, so scalar/set stay
    -- consistent). Group-axis items are stripped for targets that can't express them
    -- (Pet Bar); the stripped selection re-normalizes through the shared setter,
    -- routing the scalar back through ApplyMode to keep the legacy booleans synced.
    if EllesmereUI and EllesmereUI.VisCopySelection then
        EllesmereUI.VisCopySelection(dst, src, "barVisibility",
            dstNoGroupModes and EllesmereUI.VIS_CAPS_NO_GROUP or nil,
            EAB.VisibilityCompat.ApplyMode)
    else
        dst.visibilityModes = nil
        dst.visibilityMatch = src.visibilityMatch or nil
    end
end

-------------------------------------------------------------------------------
--  Media paths
-------------------------------------------------------------------------------
local MEDIA_DIR = "Interface\\AddOns\\EllesmereUIActionBars\\Media\\"
local FONT_PATH = (EllesmereUI.GetFontPath("actionBars"))
    or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"
local HIGHLIGHT_TEXTURES = {
    MEDIA_DIR .. "highlight-2.png",
    MEDIA_DIR .. "highlight-3.png",
    MEDIA_DIR .. "highlight-4.png",
}
ns.HIGHLIGHT_TEXTURES = HIGHLIGHT_TEXTURES

local SHAPE_MASKS = EllesmereUI.SHAPE_MASKS
local SHAPE_BORDERS = EllesmereUI.SHAPE_BORDERS
local SHAPE_INSETS = EllesmereUI.SHAPE_INSETS
local SHAPE_ZOOM_DEFAULTS = {
    none = 5.5, cropped = 2, square = 6.0, circle = 6.0, csquare = 6.0,
    diamond = 6.0, hexagon = 6.0, portrait = 6.0, shield = 6.0,
}
ns.SHAPE_ZOOM_DEFAULTS = SHAPE_ZOOM_DEFAULTS
ns.SHAPE_MASKS   = SHAPE_MASKS
ns.SHAPE_BORDERS = SHAPE_BORDERS

local SHAPE_BTN_EXPAND  = 10
local SHAPE_ICON_EXPAND = 7
ns.SHAPE_BTN_EXPAND  = SHAPE_BTN_EXPAND
ns.SHAPE_ICON_EXPAND = SHAPE_ICON_EXPAND

local SHAPE_ICON_EXPAND_OFFSETS = {
    circle = 2, csquare = 4, diamond = 2, hexagon = 4,
    portrait = 2, shield = 2, square = 4,
}
ns.SHAPE_ICON_EXPAND_OFFSETS = SHAPE_ICON_EXPAND_OFFSETS
ns.SHAPE_INSETS = SHAPE_INSETS

-- Per-shape edge scale so the circular edge path stays inside the mask.
local SHAPE_EDGE_SCALES = {
    circle = 0.75, csquare = 0.75, diamond = 0.70,
    hexagon = 0.65, portrait = 0.70, shield = 0.65, square = 0.75,
}

-- Border thickness mapping
ns.BORDER_THICKNESS = {
    none   = { regular = 0, shape = 0 },
    thin   = { regular = 1, shape = 0 },
    normal = { regular = 2, shape = 0 },
    heavy  = { regular = 3, shape = 0 },
    strong = { regular = 4, shape = 7 },
}
ns.BORDER_THICKNESS_ORDER  = { "none", "thin", "normal", "heavy", "strong" }
ns.BORDER_THICKNESS_LABELS = { none="None", thin="Thin", normal="Normal", heavy="Heavy", strong="Strong" }
ns.BORDER_THICKNESS_DEFAULT_REGULAR = "thin"
ns.BORDER_THICKNESS_DEFAULT_SHAPE   = "strong"

-- Per-addon border texture defaults (central registry)
EllesmereUI.RegisterBorderDefaults("actionbars", EllesmereUI.BORDER_DEFAULTS_BUTTONS)

-------------------------------------------------------------------------------
--  Defaults
-------------------------------------------------------------------------------
local defaults = {
    profile = {
        squareIcons = true,
        iconZoom = 5.5,
        selectedBar = "MainBar",
        cooldownEdgeSize = 2.1,
        cooldownEdgeColor = { r = 0.973, g = 0.839, b = 0.604, a = 1 },
        cooldownEdgeUseClassColor = false,
        pushedTextureType = 2,
        pushedUseClassColor = false,
        pushedCustomColor = { r = 0.973, g = 0.839, b = 0.604, a = 1 },
        pushedBorderSize = 4,
        highlightTextureType = 2,
        highlightUseClassColor = false,
        highlightCustomColor = { r = 0.973, g = 0.839, b = 0.604, a = 1 },
        highlightBorderSize = 4,
        -- Match Bar Border: on bars with a textured Border Style, a press
        -- (pushed Border type), a hover (highlight Border type) or the active
        -- spell lights up a tinted copy of the button's own border instead of
        -- the flat lines or the checked fill. Off = today's look.
        pushedBorderMatchBar = false,
        highlightBorderMatchBar = false,
        castHighlightBorder = false,
        showCastHighlight = true,
        -- Show the recharge countdown on charge spells while a charge is
        -- still banked (mirrors "Show numbers for cooldowns" CVar onto the
        -- recharge timer). Off = Blizzard default (number only at 0 charges).
        showChargeRechargeNumbers = true,
        desaturateOnCooldown = false,
        -- 100 = disabled (zero cost); below 100 dims the icon to that opacity
        -- while on a real cooldown, same detection as Desaturate on Cooldown.
        alphaWhenOnCD = 100,
        -- Cooldown swipe colour+opacity; defaults mirror Blizzard (black, 80%)
        -- so applying them is a no-op until customized.
        cdSwipeColor = { r = 0, g = 0, b = 0 },
        cdSwipeAlpha = 80,
        procGlowType = 1,
        procGlowColor = { r = 1, g = 0.776, b = 0.376 },
        procGlowUseClassColor = false,
        procGlowEnabled = false,
        -- Assisted Highlight ring: extra pixels per side beyond the button
        -- footprint. 0 = Blizzard's size (art sits exactly on the button).
        -- Positive pushes the blue swirl outward so it reads apart from a proc
        -- glow on the same edge; negative pulls it inward.
        assistGlowOutset = 0,
        -- How the Assisted Highlight is drawn: 1 = Blizzard's glow ring only
        -- (default, unchanged behavior), 2 = flat tint over the whole button
        -- instead, 3 = both. The overlay leaves the button edge free for the
        -- proc glow, which is the point of offering it.
        assistGlowStyle = 1,
        -- On Cropped bars, size the glow ring to the button's rectangle
        -- instead of scaling the square art by width. Off = today's ring.
        assistGlowFitCropped = false,
        assistGlowOverlayColor = { r = 0.15, g = 0.5, b = 1 },
        assistGlowOverlayAlpha = 30,
        useBlizzardStyle = false,
        useClassicStyle = false,
        showBlizzIconBg = false,
        blizzIconBgAlpha = 1,
        -- Flat color background behind every button icon; defaults keep the
        -- legacy look (0.15 gray at 50%) so nothing changes until customized.
        slotBgColor = { r = 0.15, g = 0.15, b = 0.15 },
        slotBgOpacity = 50,
        hideCastingAnimations = true,
        mouseoverShowAll = false,
        barPositions = {},
        bars = {},
    },
}

for _, info in ipairs(BAR_CONFIG) do
    defaults.profile.bars[info.key] = {
        enabled = true,
        borderEnabled = true,
        borderColor = { r = 0, g = 0, b = 0, a = 1 },
        borderSize = 1,
        borderClassColor = false,
        borderTexture = "solid",
        borderThickness = "thin",
        borderBehind = false,
        -- Textured border drawn above proc glows, the assisted highlight and
        -- the cooldown swipe. Show Behind wins over it.
        borderAboveEffects = false,
        buttonPadding = 2,
        buttonWidth = 0,
        buttonHeight = 0,
        mouseoverEnabled = false,
        mouseoverAlpha = 1,
        combatShowEnabled = false,
        combatHideEnabled = false,
        housingHideEnabled = false,
        barVisibility = "always",
        dragShow = false,
        -- Hide Bar When Using Gamepad: off by default; inert until a
        -- controller is connected with gamepad support enabled.
        gamepadHideBar = false,
        visHideHousing = false,
        visOnlyInstances = false,
        visHideMounted = false,
        visHideNoTarget = false,
        visHideNoEnemy = false,
        hideKeybind = false,
        keybindFontSize = 12,
        keybindFontColor = { r = 1, g = 1, b = 1 },
        hideMacroText = false,
        macroFontSize = 12,
        macroFontColor = { r = 1, g = 1, b = 1 },
        countFontSize = 12,
        countFontColor = { r = 1, g = 1, b = 1 },
        alwaysHidden = false,
        mouseoverSpeed = 0.15,
        clickThrough = false,
        overrideNumIcons = nil,
        overrideNumRows  = nil,
        growDirection    = "up",
        -- Legacy flag, superseded by iconOrder. iconOrder has no default:
        -- nil means "derive from reverseIconOrder" so old profiles keep layout.
        reverseIconOrder = false,
        alwaysShowButtons = true,
        showPagingArrows = false,
        skipVisiblePagingBars = false,
        pagingArrowsRight = false,
        paging = {},
        -- Auto-paging opt-outs (MainBar only; see BuildPagingConditions).
        disableFormPaging = false,
        disableSkyridingPaging = false,
        bgEnabled = false,
        bgColor = { r = 0, g = 0, b = 0, a = 0.5 },
        bgBorderColor = { r = 0, g = 0, b = 0, a = 1 },
        bgBorderTexture = "solid",
        bgBorderBehind = false,
        bgBorderSize = 1,
        bgBorderThickness = "none",
        bgMultiplierX = 1,
        bgMultiplierY = 1,
        bgExpandDirectionX = "right",
        bgExpandDirectionY = "up",
        outOfRangeColoring = false,
        outOfRangeColor = { r = 0.8, g = 0.1, b = 0.1 },
        masqueEnabled = false,
        buttonShape = "none",
        shapeBorderEnabled = true,
        shapeBorderColor = { r = 0, g = 0, b = 0, a = 1 },
        shapeBorderSize = 7,
        shapeBorderClassColor = nil,
        iconZoom = nil,
        keybindOffsetX = 0,
        keybindOffsetY = 0,
        macroOffsetX = 0,
        macroOffsetY = 0,
        countOffsetX = 0,
        countOffsetY = 0,
        -- Text anchors: nil or false keeps the stock placement (keybind top-right,
        -- charges bottom-right, macro name bottom-center). Any value from
        -- EAB.TEXT_ANCHOR_ORDER pins the text to that button corner/edge and
        -- justifies it the same way, so multi-digit text grows away from it.
        keybindAnchor = nil,
        countAnchor = nil,
        macroAnchor = nil,
        cooldownFontSize = 12,
        cooldownTextXOffset = 0,
        cooldownTextYOffset = 0,
        cooldownTextColor = { r = 1, g = 1, b = 1 },
        disableTooltips = false,
        showRankIcon = false,
        orientation = "horizontal",
        numIcons = 12,
        numRows = 1,
        targetWidth = 0,
        targetHeight = 0,
        -- End caps (the End Caps checklist and its cog) and WoW Forever's bar
        -- background, per bar. nil reads the bar's default (ns.AB_CapsSides,
        -- ns.AB_CapsVal, ns.AB_ForeverBg): Action Bar 1 falls back to the
        -- profile-wide keys, every other bar starts without them. The micro
        -- menu and bag bar read the same endCap* keys; the profile keys
        -- endCapSpanLeft / endCapSpanRight (written only by the first-install
        -- capture, in no defaults table) move bar 1's defaults to another bar.
        endCapLeft = nil,
        endCapRight = nil,
        endCapArt = nil,
        endCapScale = nil,
        endCapOffsetX = nil,
        endCapOffsetY = nil,
        foreverBarBg = nil,
    }
end

-- Bar9/Bar10 default to Hidden visibility (what the Visibility dropdown's
-- Hidden option sets) so they never show until the user picks another mode.
for _, k in ipairs({ "Bar9", "Bar10" }) do
    local b = defaults.profile.bars[k]
    if b then
        b.barVisibility = "never"
        b.alwaysHidden  = true
    end
end

for _, info in ipairs(EXTRA_BARS) do
    defaults.profile.bars[info.key] = {
        mouseoverEnabled = false,
        mouseoverAlpha = 1,
        combatShowEnabled = false,
        combatHideEnabled = false,
        housingHideEnabled = false,
        alwaysHidden = false,
        mouseoverSpeed = 0.15,
        clickThrough = false,
    }
    if info.isDataBar then
        local d = defaults.profile.bars[info.key]
        d.width = 400
        d.height = 18
        d.orientation = "HORIZONTAL"
        d.clickThrough = true  -- default on for data bars
        -- Custom Border (opt-in): off keeps the built-in 1px black line. The
        -- style keys below are what the option starts from (solid, thin, black)
        -- and render that same line. Offsets, shifts and borderThicknessPx have
        -- no default (nil = the style's own).
        d.customBorder = false
        d.borderTexture = "solid"
        d.borderThickness = "thin"
        d.borderColor = { r = 0, g = 0, b = 0, a = 1 }
        d.borderBehind = false
    end
end
-- House Favor bar ships opt-in: hidden until the user turns it on.
if defaults.profile.bars.FavorBar then
    defaults.profile.bars.FavorBar.alwaysHidden = true
end

-- Blizzard data bar override (let Blizzard control XP + Rep via Edit Mode). WoW
-- Forever keeps Blizzard's own bars by default (the per-client default rule).
defaults.profile.useBlizzardDataBars = (EllesmereUI.IS_FOREVER == true)
-- Show Equipped Item Color (Icon Effects): on by default on WoW Forever only.
defaults.profile.showEquippedBorder = (EllesmereUI.IS_FOREVER == true)
-- Stock vehicle / override bar suppression. Opt-in, and inert until switched
-- on: no frame, no events and no hook exist while it is false.
defaults.profile.hideBlizzardVehicleBar = false

ns.defaults = defaults

-------------------------------------------------------------------------------
--  Utility helpers
-------------------------------------------------------------------------------
local function SafeEnableMouse(frame, enable)
    if not frame then return end
    if frame.IsProtected and frame:IsProtected() and InCombatLockdown() then return end
    if frame.SetMouseClickEnabled then
        frame:SetMouseClickEnabled(enable)
        frame:SetMouseMotionEnabled(enable)
    else
        frame:EnableMouse(enable)
    end
end

-- Like SafeEnableMouse but only mouse motion (OnEnter/OnLeave); keeps
-- click-through so clicks pass to frames behind.
local function SafeEnableMouseMotionOnly(frame, enable)
    if not frame then return end
    if frame.IsProtected and frame:IsProtected() and InCombatLockdown() then return end
    if frame.SetMouseClickEnabled then
        frame:SetMouseClickEnabled(false)
        frame:SetMouseMotionEnabled(enable)
    else
        frame:EnableMouse(enable)
    end
end

-- The alpha THIS addon last wrote to each fade target (bar frames, data bar
-- and extra bar holders, MicroMenuContainer, BagsBar). Fades start from here,
-- never from GetAlpha: another addon may write a secret alpha onto these
-- frames, and math on that read throws. A side table, not a frame field: two
-- targets are Blizzard frames. No entry = never written by us = the default 1.
-- Every alpha write to a fade target goes through the fader, StopFade(frame,
-- alpha), or a record beside its SetAlpha.
local _fadeAlpha = {}

-- The micro menu's and bag bar's end caps ride our own follower frame, not
-- the Blizzard frame, so every alpha written to that Blizzard frame is copied
-- onto their cap layer: ns._abFadeTwin[blizzFrame] = cap layer (weak keys),
-- set only while that bar shows caps (ns.AB_ExtraCaps); nil otherwise.
function ns.AB_FadeTwin(frame, a)
    local tw = ns._abFadeTwin
    local h = tw and tw[frame]
    if h then h:SetAlpha(a) end
end

-- The one fader for every fade target: a shared OnUpdate queue.
-- AnimationGroups spread taint on Blizzard frames and cost 0.7-4ms to start
-- on secure bar frames.
local _extraFadeQueue = {}
local _extraFadeFrame = CreateFrame("Frame")

local function _ExtraFadeOnUpdate(_, elapsed)
    local anyActive = false
    local tw = ns._abFadeTwin
    for frame, info in pairs(_extraFadeQueue) do
        info.elapsed = info.elapsed + elapsed
        local t = info.elapsed / info.duration
        local a
        if t >= 1 then
            a = info.toAlpha
            frame:SetAlpha(a)
            _fadeAlpha[frame] = a
            _extraFadeQueue[frame] = nil
        else
            -- Smooth in/out easing
            local e = t < 0.5 and (2 * t * t) or (1 - (-2 * t + 2)^2 / 2)
            a = info.fromAlpha + (info.toAlpha - info.fromAlpha) * e
            frame:SetAlpha(a)
            _fadeAlpha[frame] = a
            anyActive = true
        end
        if tw then
            local h = tw[frame]
            if h then h:SetAlpha(a) end
        end
    end
    if not anyActive then
        _extraFadeFrame:SetScript("OnUpdate", nil)
    end
end

-- Drag visibility state (file-scope so ApplyAll can reset strata on spec change)
local _dragState = { visible = false, strataCache = {} }

-- Grid show/hide state (show empty slots during spell drag)
local _gridState = { shown = false, visPending = false, spellsPending = false,
    want = nil, settlePending = false, showFns = {}, hideFns = {} }

-- Grid edges arrive in pairs from scripted cursor use: every
-- PickupContainerItem fires ACTIONBAR_SHOWGRID and every place fires
-- ACTIONBAR_HIDEGRID, hundreds of pairs per frame during a bag sort, and
-- applying each edge re-walked every bar and flipped mouseover bars between
-- alpha 1 and 0 (the visible blinking). Settle instead: a pair that nets back
-- to the applied state (_gridState.shown, owned by the appliers) costs
-- nothing, a real drag still surfaces the grid 50ms later. Appliers register
-- into showFns/hideFns at their own definition sites.
function ns.EABQueueGrid(show)
    _gridState.want = show
    if _gridState.settlePending then return end
    _gridState.settlePending = true
    C_Timer_After(0.05, function()
        _gridState.settlePending = false
        local want = _gridState.want
        if want == _gridState.shown then return end
        local list = want and _gridState.showFns or _gridState.hideFns
        for i = 1, #list do list[i]() end
    end)
end
local _quickKeybindState = { open = false, closePending = false, art = {}, FinishClose = nil }

local function ShouldQuickKeybindSurfaceBar(s)
    if not _quickKeybindState.open or not s or s.enabled == false then
        return false
    end

    -- Surfaces bars hidden by transient runtime rules, but explicit "Never" wins.
    -- Hide Bar When Using Gamepad is not a Never: its verdict (EAB._padHide) is
    -- off while this mode is open, so a controller player can bind those bars.
    return not EAB.VisibilityCompat.IsNever(s)
end

local function FadeTo(frame, toAlpha, duration)
    duration = duration or 0.1
    local cur = _fadeAlpha[frame] or 1
    if abs(cur - toAlpha) < 0.01 then
        frame:SetAlpha(toAlpha)
        _fadeAlpha[frame] = toAlpha
        ns.AB_FadeTwin(frame, toAlpha)
        return
    end
    local existing = _extraFadeQueue[frame]
    if existing and existing.toAlpha == toAlpha then return end
    _extraFadeQueue[frame] = {
        fromAlpha = cur,
        toAlpha   = toAlpha,
        duration  = duration,
        elapsed   = 0,
    }
    _extraFadeFrame:SetScript("OnUpdate", _ExtraFadeOnUpdate)
end

-- Stop a running fade. With an alpha, also paint and record it: the one path
-- for a direct write that must win over a fade.
local function StopFade(frame, alpha)
    _extraFadeQueue[frame] = nil
    if alpha then
        frame:SetAlpha(alpha)
        _fadeAlpha[frame] = alpha
        ns.AB_FadeTwin(frame, alpha)
    end
end

-- Unlock mode blanks a bar for one frame around a resize (0, then 1) and
-- reports both writes here, so a later fade still starts where the frame
-- really is. Frames this addon never wrote stay untracked.
function EllesmereUI._EABNoteAlpha(frame, a)
    if _fadeAlpha[frame] ~= nil then _fadeAlpha[frame] = a end
end

-- Resolve borderThickness dropdown to actual pixel values. The ONE size source
-- for a bar's square border: every paint path (bar borders, the shape repaint,
-- the flyout, the keybind-mode restore) takes both results from here. Second
-- result: the exact size from borderThicknessPx (EllesmereUI.BorderPx) while it
-- still pairs with this step and the bar's texture, else nil = the legacy path.
-- A custom shape's ring is on/off only: no exact size there.
local function ResolveBorderThickness(s)
    local thickness = s.borderThickness or "thin"
    local entry = ns.BORDER_THICKNESS[thickness]
    if not entry then entry = ns.BORDER_THICKNESS["thin"] end
    local shape = s.buttonShape or "none"
    if shape ~= "none" and shape ~= "cropped" then
        if thickness == "thin" and s.shapeBorderSize and s.shapeBorderSize ~= entry.shape then
            return s.shapeBorderSize, nil
        end
        return entry.shape, nil
    else
        local sz = entry.regular
        return sz, EllesmereUI.BorderPx(s.borderThicknessPx, sz, s.borderTexture)
    end
end
ns.ResolveBorderThickness = ResolveBorderThickness

-- Condense keybind text (CTRL-2 C2, Mouse Button 4 M4, etc.)
local function FormatHotkeyText(text)
    if not text or text == "" then return "" end
    -- Gamepad binds resolve to glyph markup (no atlas name matches a substitution
    -- below); keyboard binds keep the raw tokens the substitutions are written against.
    local resolved = GetBindingText(text, 1)
    if resolved and resolved:find("|A:", 1, true) then
        text = resolved
    end
    text = text:gsub("CTRL%-", "C")
    text = text:gsub("ALT%-", "A")
    text = text:gsub("SHIFT%-", "S")
    text = text:gsub("META%-", "M")  -- Mac Command key (CMD-E -> ME)
    text = text:gsub("Mouse Button ", "M")
    text = text:gsub("MOUSEWHEELUP", "MwU")
    text = text:gsub("MOUSEWHEELDOWN", "MwD")
    text = text:gsub("CAPSLOCK", "Caps")
    -- Specific NUMPAD keys must be handled before the generic NUMPAD prefix,
    -- or the prefix replacement makes them unmatchable (N. showed as NDECIMAL).
    text = text:gsub("NUMPADDECIMAL", "N.")
    text = text:gsub("NUMPADPLUS", "N+")
    text = text:gsub("NUMPADMINUS", "N-")
    text = text:gsub("NUMPADMULTIPLY", "N*")
    text = text:gsub("NUMPADDIVIDE", "N/")
    text = text:gsub("NUMPAD", "N")
    text = text:gsub("BUTTON", "M")
    return text
end

-- Check if a button has an action assigned
local function ButtonHasAction(btn, prefix)
    if not btn then return false end
    if btn.HasAction then
        local ok, has = pcall(btn.HasAction, btn)
        if ok then return has end
    end
    return btn.icon and btn.icon:IsShown() and btn.icon:GetTexture() ~= nil
end
ns.ButtonHasAction = ButtonHasAction

-- An empty slot for the hide-empty rule (Always Show Buttons off). A pet slot
-- counts as empty only while a pet bar is out: with no pet the [pet] driver
-- already hides the whole bar, and a pet button hidden out of combat cannot be
-- shown again until combat ends (the buttons are secure), so a pet called in
-- combat would bring back an empty bar.
function ns.AB_EmptySlot(btn, info)
    if info.isPetBar and not PetHasActionBar() then return false end
    return not ButtonHasAction(btn, info.blizzBtnPrefix)
end

-- Force-paint a Blizzard-native button's cooldown swipe/text from current action state.
-- The stock cooldown broadcasters are killed at load, so buttons we don't rebuild
-- (OverrideActionBarButton1-6, ExtraActionButton1) would show no swipe/number for an
-- already-active cooldown until the next broadcast. Reads the slot via
-- GetAttribute("action"), never btn.action (protected -- reading it in combat taints).
-- Clears when no active duration resolves so a stale swipe is never left behind.
local function ForceCooldownPaint(btn)
    if not btn then return end
    local cd = btn.cooldown
    local action = btn:GetAttribute("action")
    if cd and action and HasAction(action) and C_ActionBar and C_ActionBar.GetActionCooldown then
        local cdInfo = C_ActionBar.GetActionCooldown(action)
        local durObj = cdInfo and cdInfo.isActive and C_ActionBar.GetActionCooldownDuration
            and C_ActionBar.GetActionCooldownDuration(action)
        if durObj then
            cd:SetCooldownFromDurationObject(durObj)
        else
            cd:Clear()
        end
    end
end
ns.ForceCooldownPaint = ForceCooldownPaint

-- Paint the One Button Assist button's cooldown from the SUGGESTED spell rather
-- than from its action slot. That button draws two things from two sources: the
-- icon is the suggestion sampled on the assist ticker, while the slot's own
-- cooldown mirrors whatever the engine is suggesting at the instant it is read.
-- The suggestion moves faster than the 5 Hz tick, so consecutive reads land on
-- different abilities and the swipe flips on and off under a still icon.
-- spellID nil means no suggestion, where RepaintAssistIcons falls the icon back
-- to the slot's own texture, so the swipe follows it there. isActive is
-- NeverSecret and the duration object carries the timing: no secret is read.
-- On ns, not a local.
ns.PaintAssistCooldown = function(btn, spellID)
    if not spellID then return ForceCooldownPaint(btn) end
    local cd = btn and btn.cooldown
    if not cd then return end
    local info = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(spellID)
    local durObj = info and info.isActive and C_Spell.GetSpellCooldownDuration
        and C_Spell.GetSpellCooldownDuration(spellID)
    if durObj then
        cd:SetCooldownFromDurationObject(durObj)
    else
        cd:Clear()
    end
end

-- Stock bar frames to disable. Each entry carries flags for how to handle it:
--   retainEvents  = true  -> do NOT unregister events (needed for override state)
local STOCK_BAR_DISPOSAL = {
    { name = "MainActionBar",       retainEvents = true },
    { name = "MainMenuBar" },
    { name = "MultiBarBottomLeft" },
    { name = "MultiBarBottomRight" },
    { name = "MultiBarRight" },
    { name = "MultiBarLeft" },
    { name = "MultiBar5" },
    { name = "MultiBar6" },
    { name = "MultiBar7" },
    { name = "StanceBar" },
    { name = "PetActionBar" },
}

-- Main-chunk locals the other EUI_ActionBars_*.lua files re-import by name.
-- Each of those files adds the entry points the files behind it need (bottom
-- of that file).
-- The three ...Setters lists: a file that keeps one of these values registers
-- a setter here; the place that assigns it writes through SetSecureRefsReady,
-- SetPagingFrame or SetIsApplyingAll, built below, which runs them all.
EllesmereUI.NewInternals(ns, "_internals", {
    BAR_CONFIG = BAR_CONFIG, _fadeAlpha = _fadeAlpha, _quickKeybindState = _quickKeybindState,
    FormatHotkeyText = FormatHotkeyText, StopFade = StopFade, SafeEnableMouse = SafeEnableMouse,
    SafeEnableMouseMotionOnly = SafeEnableMouseMotionOnly,
    ShouldQuickKeybindSurfaceBar = ShouldQuickKeybindSurfaceBar, FONT_PATH = FONT_PATH,
    _gridState = _gridState, NUM_ACTIONBAR_BUTTONS = NUM_ACTIONBAR_BUTTONS,
    SHAPE_EDGE_SCALES = SHAPE_EDGE_SCALES, STOCK_BAR_DISPOSAL = STOCK_BAR_DISPOSAL, BAR_LOOKUP = BAR_LOOKUP,
    SHAPE_BTN_EXPAND = SHAPE_BTN_EXPAND, ALL_BARS = ALL_BARS, FadeTo = FadeTo, EXTRA_BARS = EXTRA_BARS,
    _dragState = _dragState,
    SetActionBarCVar = SetActionBarCVar, LatchMasqueBarOwnership = LatchMasqueBarOwnership,
    secureRefsReadySetters = {}, pagingFrameSetters = {}, isApplyingAllSetters = {},
}, {
    SetSecureRefsReady = "secureRefsReadySetters",
    SetPagingFrame = "pagingFrameSetters",
    SetIsApplyingAll = "isApplyingAllSetters",
})
