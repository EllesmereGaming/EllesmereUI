if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIQoL_RaidTools.lua -- Raid control panels (QoL: Raid Tools page)
--
--  COMPACT BAND is an opt-in layout: one resizable row with eight marker
--  symbols, clear, Ready/Role and pull controls. Target and world actions share
--  each symbol through mouse-button/modifier attributes, so every secure
--  action remains placeable mid-combat without duplicating the row.
--
--  The original Group & Pull and Markers content groups remain available as
--  legacy window modes for existing profiles and low-frequency Convert /
--  Disband access.
--
--  Group & Pull buttons are all created once at build; per-button switches and
--  0-second pull slots decide which ones LayoutGroupContent places (it re-flows
--  the survivors and is the only writer of the group content height).
--
--  SHOW MODE (p.mode) replaces the old shared-visibility system outright:
--
--    "never"  -- the default. NOTHING exists: no frames, no events, no
--                bindings, no unlock rows. True zero cost.
--    "raid"   -- auto-shows in a raid group ([group:raid] state driver).
--    "group"  -- auto-shows in any group ([group] state driver).
--    "always" -- always shown (no driver; the visible attribute just stays
--                true).
--
--  On top of the mode sits ONE unconditional gate: in a raid without leader or
--  assist the whole feature is off the screen, because the server refuses
--  every button on it there. It is raid-only (a party has no assistants) and
--  Lua-side, since no macro conditional can express it -- see AssistSuppressed
--  and RefreshAssistGate.
--
--  The Toggle Raid Tools keybind works in every active mode. Compact Band is
--  already the minimized form, so its key is a plain show/hide. Legacy modes
--  follow Default to Collapsed When Shown: with it ON the key rocks
--  between the collapsed icon and the full windows (the icon is the minimized
--  state, so hiding would be redundant); with it OFF the key is a plain
--  show/hide of the full windows, riding the override on top of the mode's
--  verdict. In the driver modes a TRANSITION reclaims control; in always
--  mode the override holds until the next settings pass.
--
--  COMBAT MODEL -- read this before changing anything here.
--
--  Marker buttons are SecureActionButtonTemplate, built once on first
--  non-never Apply and never re-anchored, re-parented or resized in combat.
--  The window shells are SecureHandlerState frames, which makes THEM
--  protected; that dictates who may change visibility, and when:
--
--    * The STATE DRIVER, the KEYBIND, the collapsed icon's expand click and
--      the collapse buttons all work in combat -- every one is a hardware
--      click or driver transition running the secure "apply" snippet.
--    * LUA does not. Show/Hide AND SetAttribute on a protected frame are
--      blocked in lockdown, so every options-driven change (mode, layout,
--      scale, position) defers behind applyPending and completes on
--      PLAYER_REGEN_ENABLED.
--
--  VISIBILITY STATE -- attributes on each shell and on the collapsed icon,
--  one writer each:
--
--    enabled       -- may this frame ever show. Written by Apply, OOC only.
--    visible       -- the driver's current verdict; false when no driver.
--                     Written by _onstate (and Apply's OOC settle).
--    override      -- "" / "show" / "hide" from the keybind; cleared by
--                     driver transitions and settings passes.
--    expanded      -- windows (true) vs collapsed icon (false). Flipped by
--                     the icon's expand click and the collapse buttons;
--                     re-seeded from startexpanded on driver transitions and
--                     on every keybind "show".
--    startexpanded -- the seed for EVERY show (driver, settings pass,
--                     keybind): NOT Default to Collapsed When Shown. Turning
--                     that toggle off is how the keybind becomes a plain
--                     full-window toggle.
--
--  "apply" folds these into Show/Hide: shells show when visible-and-expanded,
--  the icon shows when visible-and-collapsed. It is the ONLY place any of
--  these frames is shown or hidden.
--
--  SHOW AS (p.showAs) owns the window composition outright -- there are no
--  separate per-panel enable toggles:
--
--    "compact" -- one resizable band in the Group shell. Unlock Mode owns
--                 its position, width and height like any other container.
--    "one"     -- both content groups in the Group & Pull shell,
--                 which grows to fit and retitles to "Raid Tools"; ONE unlock
--                 element positioned by pos.Group. The markers holder
--                 re-parents (OOC) into the shell; holders are plain frames,
--                 so the move is an ordinary SetParent and the secure buttons
--                 never change parents themselves.
--    "two"     -- each content group in its own shell, two unlock elements.
--                 The Markers shell drops its collapse button here: one
--                 collapse control (Group & Pull's) folds the whole feature.
--    "group"   -- only the Group & Pull shell exists on screen.
--    "markers" -- only the Markers shell exists on screen; the collapsed
--                 icon anchors to IT in this mode.
--
--  One Raid Tools Scale (p.scale) covers every form: both shells and the
--  collapsed icon wear the same value, whichever windows the Show as choice
--  puts on screen.
-------------------------------------------------------------------------------
local _, ns = ...

local InCombatLockdown = InCombatLockdown
local UnitIsGroupLeader, UnitIsGroupAssistant = UnitIsGroupLeader, UnitIsGroupAssistant
local IsInRaid, IsInGroup = IsInRaid, IsInGroup
local SetRaidTargetIconTexture = SetRaidTargetIconTexture

-- Layout constants. Content geometry is decided once at build; only scale,
-- and which holders a shell carries, are user-facing.
local PANEL_W      = 236
local PAD          = 10
local TOPBAR_H     = 25    -- the Window Skins title band
local CONTENT_TOP  = TOPBAR_H + 6
local ROW_H        = 22
local ROW_GAP      = 4
-- Marker buttons span the full panel width regardless of this size: the row
-- step is derived from it ((PANEL_W - PAD*2 - MARKER_SZ) / 8), so a smaller
-- icon just breathes more between neighbours.
local MARKER_SZ    = 23
local MARKER_LBL_H = 10
local ICON_SZ      = 30
local COMPACT_H    = 40
local COMPACT_W    = 400
local COMPACT_MIN_W = 365
local COMPACT_MIN_H = 28
local COMPACT_PAD  = 6
local COMPACT_ICON = 28
local COMPACT_GAP  = 4
local COMPACT_DIVIDER_OFFSET = 5
local PULL_SLOTS   = 3
local PULL_DEFAULTS = { 3, 5, 10 }   -- also seeded into DB_DEFAULTS below
ns.PULL_DEFAULTS = PULL_DEFAULTS

-------------------------------------------------------------------------------
--  Window Skins look, replicated
--
--  These panels wear the same dress as the Blizz UI Enhanced window skins:
--  the modern_blizz art cover-fit behind a 0.62 black wash, a 25px black
--  title band, the AdventureMap_TopBorder frame atlas (1px gray fallback),
--  and flat 0.08-gray buttons with a 1px 0.2-gray border and a white 0.1
--  hover. The values are copied from the WSkin engine's Shell/Button recipe
--  ON PURPOSE rather than calling it: WSkin lives in EllesmereUIBlizzardSkin,
--  a sibling child addon the user may not have enabled, and QoL must not
--  depend on it.
-------------------------------------------------------------------------------
local SKIN_BG_TEX  = "Interface\\AddOns\\EllesmereUI\\media\\modern_blizz.png"
-- Cover-fit crop window into the art (same numbers as the WSkin engine).
local BG_ASPECT = 561 / 433
local BASE_L, BASE_R, BASE_T, BASE_B = 0.25, 1, 0, 0.75
local BASE_U, BASE_V = BASE_R - BASE_L, BASE_B - BASE_T
local BORDER_ATLAS = "AdventureMap_TopBorder"
-- Theme grays (WSkin.Theme): button fill / border line.
local BTN_R, BTN_G, BTN_B, BTN_A = 0.08, 0.08, 0.08, 0.92
local BRD_R, BRD_G, BRD_B, BRD_A = 0.2, 0.2, 0.2, 1

-- Shell backdrop: art + wash + title band, and a re-crop function the layout
-- pass calls after any height change so the art never stretches.
local function SkinPanelBg(f)
    local bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetTexture(SKIN_BG_TEX)
    bg:SetAllPoints(f)
    local overlay = f:CreateTexture(nil, "BACKGROUND", nil, -7)
    overlay:SetColorTexture(0, 0, 0, 0.62)
    overlay:SetAllPoints(f)
    local topBar = f:CreateTexture(nil, "BACKGROUND", nil, -5)
    topBar:SetColorTexture(0, 0, 0, 0.5)
    topBar:SetPoint("TOPLEFT")
    topBar:SetPoint("TOPRIGHT")
    topBar:SetHeight(TOPBAR_H)
    f._bgArt = bg
    f._bgOverlay = overlay
    f._titleBar = topBar
    f._bgFit = function()
        local fw, fh = f:GetSize()
        if not fw or fw == 0 or not fh or fh == 0 then return end
        local fa = fw / fh
        if fa > BG_ASPECT then
            local visV = BASE_V * (BG_ASPECT / fa)
            local trimV = (BASE_V - visV) / 2
            bg:SetTexCoord(BASE_L, BASE_R, BASE_T + trimV, BASE_B - trimV)
        else
            local visU = BASE_U * (fa / BG_ASPECT)
            local trimU = (BASE_U - visU) / 2
            bg:SetTexCoord(BASE_L + trimU, BASE_R - trimU, BASE_T, BASE_B)
        end
    end
    f._bgFit()
end

-- Window frame: the atlas border the skins use, 1px gray line if the atlas
-- ever disappears from the client.
local function SkinPanelBorder(f)
    local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(BORDER_ATLAS)
    if not info then
        local fallback = EllesmereUI.MakeBorder(f, BRD_R, BRD_G, BRD_B, BRD_A, EllesmereUI.PP)
        f._windowBorder = fallback and fallback._frame
        return
    end
    local ov = CreateFrame("Frame", nil, f)
    ov:SetAllPoints(f)
    ov:SetFrameLevel(f:GetFrameLevel() + 6)
    local tex = ov:CreateTexture(nil, "OVERLAY", nil, 7)
    tex:SetAtlas(BORDER_ATLAS)
    tex:SetAllPoints(ov)
    f._windowBorder = ov
end

-- Button chrome: flat fill, 1px line, white hover on the HIGHLIGHT layer
-- (Buttons show that layer on mouseover natively, so no scripts).
local function SkinButtonChrome(b)
    local fill = b:CreateTexture(nil, "BACKGROUND")
    fill:SetColorTexture(BTN_R, BTN_G, BTN_B, BTN_A)
    fill:SetAllPoints(b)
    EllesmereUI.MakeBorder(b, BRD_R, BRD_G, BRD_B, BRD_A, EllesmereUI.PP)
    local hover = b:CreateTexture(nil, "HIGHLIGHT")
    hover:SetColorTexture(1, 1, 1, 0.1)
    hover:SetAllPoints(b)
end

-- The collapsed-state button IS this image: no chrome, no border, no inset.
local COLLAPSED_ICON_TEX = "Interface\\AddOns\\EllesmereUI\\media\\icons\\raid-tools.png"

-- Canonical section list. Build order, stack order, DB key set, window titles
-- and unlock-mover labels all derive from this one table.
--
-- `label` reaches EllesmereUI.L as a variable, which the static key extractor
-- cannot see -- the documented arrangement for exactly this case (see the
-- header of .tools/extract-locale-keys.sh); the in-game /euiloc harvester picks
-- them up, the same way every widget label in the suite is already handled.
local SECTIONS = {
    { key = "Group",   label = "Group & Pull" },
    { key = "Markers", label = "Markers" },
}

-- One-window title; reaches L as a variable like the section labels.
local COMBINED_LABEL = "Raid Tools"

-- Prefix for this feature's unlock-mode element keys. Used both to register
-- them and to ask the anchor system about them, so the two cannot drift.
-- These keys persist in saved anchors -- renaming breaks existing links.
local UNLOCK_KEY = "EUI_RaidTools_"
local COMPACT_UNLOCK_KEY = UNLOCK_KEY .. "Compact"

local SECTION_KEYS = {}
local SECTION_LABEL = {}
for _, def in ipairs(SECTIONS) do
    SECTION_KEYS[#SECTION_KEYS + 1] = def.key
    SECTION_LABEL[def.key] = def.label
end

local db
local applyPending             -- true when combat blocked an Apply()
local previewOn = false        -- Raid Tools settings page is in front (see ApplyVisibility)
local lastSuppressed           -- assist gate verdict currently ON SCREEN (see AssistSuppressed)
local toggleButton             -- keybind target; also the out-of-combat path
local sections = {}            -- key -> shell frame
local shellTitle = {}          -- key -> title fontstring
local groupHolder, markersHolder, compactHolder   -- plain content holders (see header)
local iconBtn                  -- collapsed-state square
-- Markers are fixed at build; the Group & Pull height follows the settings and
-- is re-computed by LayoutGroupContent on every Apply.
local GROUP_CONTENT_H, MARKERS_CONTENT_H
local Apply                    -- forward: the event handler closes over it

-- ONE representation of each secure decision, run from both paths.
--
-- The keybind clicks the button, which is the only thing that works during combat. Out
-- of combat the same snippet is run through SecureHandlerExecute instead of being
-- re-implemented in Lua. EllesmereUIRaidFrames.lua does exactly this, for exactly this
-- reason: the driver manager only fires the attribute handlers on value CHANGES, so a
-- reapply with unchanged states would otherwise never run.
local RUN_APPLY = [[ self:RunAttribute("apply") ]]

-- The keybind's job depends on Default to Collapsed When Shown:
--
--   ON  -- the icon IS the minimized state, so hiding would be redundant.
--          The key rocks between the icon and the full windows (collapse /
--          expand); from fully hidden it shows the windows directly, since
--          the press means the tools are wanted NOW.
--   OFF -- a plain show/hide of the full windows.
--
-- The branch is read off the icon's startexpanded (false = collapse mode),
-- so the snippet needs no config attribute of its own.
local TOGGLE_SNIPPET = [[
    local n = self:GetAttribute("count") or 0
    local icon = self:GetFrameRef("icon")
    local anyWin, iconShown = false, false
    for i = 1, n do
        local f = self:GetFrameRef("s" .. i)
        if f and f:IsShown() then anyWin = true end
    end
    if icon and icon:IsShown() then iconShown = true end

    local collapseMode = icon and not icon:GetAttribute("startexpanded")
    if collapseMode then
        if anyWin then
            -- Windows up: collapse to the icon. Visibility is untouched, so
            -- whatever put the windows up (driver or override) keeps the icon
            -- up in their place.
            for i = 1, n do
                local f = self:GetFrameRef("s" .. i)
                if f then
                    f:SetAttribute("expanded", false)
                    f:RunAttribute("apply")
                end
            end
            icon:SetAttribute("expanded", false)
            icon:RunAttribute("apply")
        else
            -- Icon up, or nothing up: expand to the windows. The override
            -- also covers the fully-hidden case (driver currently saying no).
            for i = 1, n do
                local f = self:GetFrameRef("s" .. i)
                if f then
                    f:SetAttribute("override", "show")
                    f:SetAttribute("expanded", true)
                    f:RunAttribute("apply")
                end
            end
            icon:SetAttribute("override", "show")
            icon:SetAttribute("expanded", true)
            icon:RunAttribute("apply")
        end
        return
    end

    local ov
    if anyWin or iconShown then ov = "hide" else ov = "show" end
    for i = 1, n do
        local f = self:GetFrameRef("s" .. i)
        if f then
            f:SetAttribute("override", ov)
            if ov == "show" then
                f:SetAttribute("expanded", f:GetAttribute("startexpanded"))
            end
            f:RunAttribute("apply")
        end
    end
    if icon then
        icon:SetAttribute("override", ov)
        if ov == "show" then
            icon:SetAttribute("expanded", icon:GetAttribute("startexpanded"))
        end
        icon:RunAttribute("apply")
    end
]]

-- Expand (the icon's own click) and collapse (the shells' corner buttons):
-- flip `expanded` everywhere and re-apply. Both run in combat as hardware
-- clicks on secure buttons.
local EXPAND_SNIPPET = [[
    local n = self:GetAttribute("count") or 0
    for i = 1, n do
        local f = self:GetFrameRef("s" .. i)
        if f then
            f:SetAttribute("expanded", true)
            f:RunAttribute("apply")
        end
    end
    self:SetAttribute("expanded", true)
    self:RunAttribute("apply")
]]
local COLLAPSE_SNIPPET = [[
    local n = self:GetAttribute("count") or 0
    for i = 1, n do
        local f = self:GetFrameRef("s" .. i)
        if f then
            f:SetAttribute("expanded", false)
            f:RunAttribute("apply")
        end
    end
    local icon = self:GetFrameRef("icon")
    if icon then
        icon:SetAttribute("expanded", false)
        icon:RunAttribute("apply")
    end
]]

-- Every fontstring is registered on the OUR-frame that owns it (`_fonts`), and
-- ApplyFonts walks the small fixed owner list -- no module-level registry to keep in
-- sync with frame lifetime. MakeFont (like every options-panel helper) hardcodes the
-- options-panel font; on-screen text has to resolve through GetFontPath instead, or
-- these panels would be the only ones in the suite ignoring the Global Font setting.
local FONT_KEY = "extras"      -- QoL's key in EllesmereUI._addonKeyToFolder
local fontOwners = {}          -- filled at build: shells + holders
local function TrackFont(owner, fs, size)
    local t = owner._fonts
    if not t then t = {}; owner._fonts = t end
    t[#t + 1] = { fs = fs, size = size }
    return fs
end
local function ApplyFonts()
    local path = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath(FONT_KEY)
    if not path then return end
    for _, owner in ipairs(fontOwners) do
        local t = owner._fonts
        if t then
            for _, e in ipairs(t) do
                local _, _, flags = e.fs:GetFont()
                e.fs:SetFont(path, e.size, flags or "")
            end
        end
    end
end

local groupButtons = {}        -- plain buttons, enable-gated on assist
local markerButtons = {}       -- secure buttons, dimmed on assist
local pullButtons = {}         -- fixed set of 3; only the ones above 0s show
-- Created once at build; the layout pass decides which reach the screen. Ready
-- Check has no switch by design.
local readyButton, roleButton, convertButton, disbandButton, stopButton
local compactReadyButton, compactPullButton, compactDivider
local compactMarkerButtons = {}
local ShowCompactTip, HideCompactTip

-- Both marker rows draw Blizzard's own raid target sheet -- the texture the
-- rest of the suite already uses for markers, in nameplates and raid frames.
local MARKER_SHEET = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"

-- The sheet's SYMBOL order (1 Star, 2 Circle, 3 Diamond, 4 Triangle, 5 Moon, 6 Square,
-- 7 Cross, 8 Skull) is NOT the WORLD marker ID order (1 Blue, 2 Green, 3 Purple, 4 Red,
-- 5 Yellow, 6 Orange, 7 Silver, 8 White). Each flare carries its symbol, so the button
-- shows the symbol and this maps it to the flare that actually wears it -- without it,
-- clicking Star (symbol 1) dropped the BLUE flare (world ID 1).
local SYMBOL_TO_WORLD = { 5, 6, 3, 2, 7, 1, 4, 8 }
local MARKER_NAME = {
    "Star", "Circle", "Diamond", "Triangle",
    "Moon", "Square", "Cross", "Skull",
}
local COMPACT_MARKER_TIP_ROWS = {
    { "Left Click",          "Toggle target marker" },
    { "Right Click",         "Place world marker" },
    { "Shift + Left Click",  "Clear target marker" },
    { "Shift + Right Click", "Clear world marker" },
}
local COMPACT_CLEAR_TIP_ROWS = {
    { "Left Click",  "Clear target marker" },
    { "Right Click", "Clear all world markers" },
}
-- One slice of the shared EllesmereUIQoLDB profile, the same arrangement
-- BattleRes and Bloodlust use: each QoL feature merges its own defaults into
-- the SAME profile table under its own key.
local DB_DEFAULTS = {
  profile = {
    raidTools = {
        -- "never" | "raid" | "group" | "always" (see header). Never = the
        -- feature does not exist at runtime.
        mode          = "never",
        -- Toggle Raid Tools key ("SHIFT-R" form). Profile-stored and applied
        -- as an override binding, exactly like Action Bars' toggleVisKey.
        toggleKey     = false,
        -- Default to Collapsed When Shown: EVERY show (driver, settings pass,
        -- keybind) starts as the small icon; click it to expand. Turning this
        -- off makes the keybind a plain full-window toggle.
        collapsedIcon = true,
        -- "compact" | "one" | "two" | "group" | "markers" (see header). The single owner
        -- of window composition; there are no per-panel enable toggles.
        showAs        = "one",
        compactWidth  = COMPACT_W,
        compactHeight = COMPACT_H,
        -- One scale for the whole feature: whichever windows the Show as
        -- choice puts on screen (and the collapsed icon) all wear it.
        scale         = 1,
        -- Three slots is a LAYOUT choice (they fill one row beside Stop), not a
        -- security constraint -- the pull buttons are plain, only the marker buttons
        -- are secure. Growing the count later means growing the panel, nothing more.
        -- 0 = slot hidden; all three at 0 removes the pull row, Stop included.
        pullTimes     = { PULL_DEFAULTS[1], PULL_DEFAULTS[2], PULL_DEFAULTS[3] },
        -- Per-button switches (Ready Check has none); hidden buttons close up.
        showRoleCheck = true,
        showConvert   = true,
        showDisband   = true,
        -- Per-section: pos[key] = { point, relPoint, x, y }
        pos           = {},
    },
  },
}

-- Our slice of the shared QoL profile, re-derived on every read -- the same accessor
-- BattleRes and MovementAlert use. Deliberately NOT cached: a profile switch replaces
-- the whole profile table, and a cached pointer would leave the event handler, the
-- slash command and the unlock callbacks writing into an orphaned table.
--
-- A PURE READ, with no `or {}` seeding. Spec Overrides captures a page by
-- swapping the profile tables for read-tracking proxies: reading a table value
-- hands back a NEW proxy, and writing goes through to the real table. So
-- `t.x = t.x or {}` stores a proxy inside the real table, the next call wraps
-- that proxy in another, and reading through the stack overflows the C stack.
-- DB_DEFAULTS already guarantees the slice exists; the seeding was never
-- needed and is actively harmful here.
local function P()
    return db and db.profile and db.profile.raidTools
end

local function Mode()
    local p = P()
    return (p and p.mode) or "never"
end

-- The Show as choice, normalized: any unset/unknown value preserves the
-- original One Window behavior. Compact Band is selected explicitly.
local function ShowAs()
    local p = P()
    local v = p and p.showAs
    if v ~= "compact" and v ~= "one" and v ~= "two"
       and v ~= "group" and v ~= "markers" then v = "one" end
    return v
end
ns.ShowAs = ShowAs

local function CompactWidth()
    local p = P()
    return math.max(COMPACT_MIN_W, (p and p.compactWidth) or COMPACT_W)
end

local function CompactHeight()
    local p = P()
    return math.max(COMPACT_MIN_H, (p and p.compactHeight) or COMPACT_H)
end

local function WindowScale()
    local p = P()
    return (p and p.scale) or 1
end

-------------------------------------------------------------------------------
--  Suite-styled widgets
--
--  Window-skin chrome (SkinPanelBg/Border, SkinButtonChrome) plus the suite
--  font pipeline (GetFontPath via TrackFont), so the panels read as skinned
--  Blizzard windows rather than stock Blizzard UI or the options panel.
-------------------------------------------------------------------------------

-- Enable state without touching the button's own scripts: dimming the whole
-- frame and cutting mouse input is both
-- simpler and immune to a hover re-lighting a disabled control.
local function SetButtonEnabled(b, on)
    b:SetAlpha(on and 1 or 0.35)
    b:EnableMouse(on)
end

-- Action button in the Window Skins style: flat fill, 1px line, white hover,
-- white label (WSkin.Button + WhiteButtonLabel, replicated). `needsLeader`
-- narrows the gate from assist to leader.
local function MakeGroupButton(parent, text, width, onClick, needsLeader)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, ROW_H)
    SkinButtonChrome(b)
    local lbl = TrackFont(parent, EllesmereUI.MakeFont(b, 11, nil, 1, 1, 1), 11)
    lbl:SetPoint("CENTER")
    if text ~= "" then lbl:SetText(EllesmereUI.L(text)) end
    b:SetScript("OnClick", onClick)
    b._lbl = lbl
    b.needsLeader = needsLeader
    groupButtons[#groupButtons + 1] = b
    return b
end

-- Secure marker button. Action attributes are set here, at build, and never
-- touched again -- that is what makes them usable in combat.
--
-- The attribute names are SecureActionButtonTemplate's own contract, so two
-- details are dictated rather than chosen:
--   * slash commands are read from the SLASH_* globals. They are localized --
--     writing "/tm" or "/cwm" as a literal breaks every non-English client,
--     including this one.
--   * the worldmarker type takes `marker` as a STRING, and splits placing from
--     clearing across action1 and action2.
local function MakeMarkerButton(parent, index, kind)
    local b = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
    local compact = kind == "compact" or kind == "compact-clear"
    local size = compact and COMPACT_ICON or MARKER_SZ
    b:SetSize(size, size)
    -- One phase only: the "!" prefix toggles the marker, so firing on both the
    -- down and the up would set it and immediately clear it again. useOnKeyDown
    -- is pinned because left unset it follows the ActionButtonUseKeyDown CVar,
    -- and at 0 the secure handler acts on the up phase we never register --
    -- every marker button goes dead.
    b:RegisterForClicks("AnyDown")
    b:SetAttribute("useOnKeyDown", true)

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    b.icon = icon

    if kind == "compact" then
        local worldID = SYMBOL_TO_WORLD[index]
        -- One symbol, four combat-safe actions. The ordinary clicks perform
        -- the frequent actions; Shift exposes their explicit clear variants.
        b:SetAttribute("type1", "macro")
        b:SetAttribute("macrotext1", (SLASH_TARGET_MARKER1 or "/tm") .. " !" .. index)
        b:SetAttribute("type2", "worldmarker")
        b:SetAttribute("marker2", tostring(worldID))
        b:SetAttribute("action2", "set")
        b:SetAttribute("shift-type1", "macro")
        b:SetAttribute("shift-macrotext1", (SLASH_TARGET_MARKER1 or "/tm") .. " 0")
        b:SetAttribute("shift-type2", "worldmarker")
        b:SetAttribute("shift-marker2", tostring(worldID))
        b:SetAttribute("shift-action2", "clear")
        b._worldID = worldID
    elseif kind == "compact-clear" then
        b:SetAttribute("type1", "macro")
        b:SetAttribute("macrotext1", (SLASH_TARGET_MARKER1 or "/tm") .. " 0")
        b:SetAttribute("type2", "macro")
        b:SetAttribute("macrotext2",
            (SLASH_CLEAR_WORLD_MARKER1 or "/cwm") .. " " .. (ALL or "All"))
    elseif kind == "target" then
        -- Left: toggle this marker on the target. Right: clear it.
        b:SetAttribute("type", "macro")
        if index == 0 then
            b:SetAttribute("macrotext", (SLASH_TARGET_MARKER1 or "/tm") .. " 0")
        else
            b:SetAttribute("macrotext1", (SLASH_TARGET_MARKER1 or "/tm") .. " !" .. index)
            b:SetAttribute("macrotext2", (SLASH_TARGET_MARKER1 or "/tm") .. " 0")
        end
    elseif index == 0 then
        -- Clear-all is a macro, not a worldmarker action: the attribute form
        -- clears one index at a time.
        b:SetAttribute("type", "macro")
        b:SetAttribute("macrotext",
            (SLASH_CLEAR_WORLD_MARKER1 or "/cwm") .. " " .. (ALL or "All"))
    else
        b:SetAttribute("type", "worldmarker")
        -- `index` is the SYMBOL the button shows; the attribute wants the
        -- world-marker ID of the flare carrying that symbol (see the map).
        b:SetAttribute("marker", tostring(SYMBOL_TO_WORLD[index]))
        b:SetAttribute("action1", "set")
        b:SetAttribute("action2", "clear")
    end

    if index == 0 then
        icon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    else
        icon:SetTexture(MARKER_SHEET)
        SetRaidTargetIconTexture(icon, index)
    end

    -- No chrome on the marker grid: the symbols read best bare. Hover is an
    -- opacity lift on the icon itself (80% resting, 100% under the cursor),
    -- and the no-assist dim keeps priority -- a 0.4-dimmed button does not
    -- brighten on hover, so the dim never lies. _baseAlpha is ours to write
    -- (our CreateFrame'd button); RefreshPermissions owns its value.
    icon:SetAlpha(0.8)
    b._baseAlpha = 0.8
    if kind == "compact" then
        local active = b:CreateTexture(nil, "OVERLAY")
        active:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 2, -2)
        active:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, -2)
        active:SetHeight(2)
        local ar, ag, ab = 0.05, 0.82, 0.62
        if EllesmereUI.GetAccentColor then ar, ag, ab = EllesmereUI.GetAccentColor() end
        active:SetColorTexture(ar, ag, ab, 0.95)
        active:Hide()
        b._activeLine = active
    end
    b:SetScript("OnEnter", function(self)
        if (self._baseAlpha or 0.8) >= 0.8 then self.icon:SetAlpha(1) end
        if compact and ShowCompactTip then
            if kind == "compact-clear" then
                ShowCompactTip(self, "Clear Markers", COMPACT_CLEAR_TIP_ROWS)
            else
                ShowCompactTip(self, MARKER_NAME[index] or "Raid Marker",
                    COMPACT_MARKER_TIP_ROWS)
            end
        end
    end)
    b:SetScript("OnLeave", function(self)
        self.icon:SetAlpha(self._baseAlpha or 0.8)
        if compact and HideCompactTip then HideCompactTip(self) end
    end)

    markerButtons[#markerButtons + 1] = b
    return b
end

-------------------------------------------------------------------------------
--  Permission gating
-------------------------------------------------------------------------------

-- Ready check, role check, countdown and markers all require lead or assist.
--
-- Solo counts as permitted. You are the only member, so nothing is being taken from
-- anyone, and the game already no-ops whatever does not apply outside a group -- gating
-- it ourselves would only make the panels dead on a target dummy for no reason.
local function HasAssist()
    if not IsInGroup() then return true end
    return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

local function IsLeader()
    if not IsInGroup() then return true end
    return UnitIsGroupLeader("player")
end

-- In a RAID, every control on the panel needs leader or assist: ready check,
-- role check, the countdown, convert, disband and the marker buttons are all
-- refused by the server without it. So the feature steps off the screen there
-- instead of sitting around fully dimmed.
--
-- Raid only, deliberately. A party has no assistants -- UnitIsGroupAssistant
-- is false for everyone in one -- so the same test would hide the panel from
-- every non-leader in a 5-man, where marking is open to all of them.
--
-- There is no macro conditional for leader/assist, so NO state driver can
-- express this: the gate is Lua's, it lands on the enabled attribute, and a
-- promotion mid-combat is picked up on PLAYER_REGEN_ENABLED like every other
-- Lua-side change (see the combat model in the header).
local function AssistSuppressed()
    if previewOn then return false end   -- configuring the thing beats hiding it
    return IsInRaid() and not HasAssist()
end

-- An optional button's switch, defaulting to shown for an unset profile.
local function ButtonShown(key)
    local p = P()
    return not p or p[key] ~= false
end

-- The pull durations worth a button, in slot order. 0 (and anything below it)
-- means the user turned that slot off.
local function VisiblePullTimes()
    local times = (P() and P().pullTimes) or {}
    local out = {}
    for i = 1, PULL_SLOTS do
        local secs = times[i]
        if secs == nil then secs = PULL_DEFAULTS[i] end
        if secs and secs > 0 then out[#out + 1] = secs end
    end
    return out
end

-- GROUP_ROSTER_UPDATE is one of the chattiest events in a raid -- it bursts on
-- every join, leave and zone-in -- while assist/leader/raid status changes a
-- handful of times a night. Memo the three inputs and bail when none moved.
-- `force` is for callers that have just built or rebuilt the buttons.
local lastAssist, lastLeader, lastRaid
local function RefreshPermissions(force)
    local assist, leader, raid = HasAssist(), IsLeader(), IsInRaid()
    if not force and assist == lastAssist and leader == lastLeader and raid == lastRaid then
        return
    end
    lastAssist, lastLeader, lastRaid = assist, leader, raid

    for _, b in ipairs(groupButtons) do
        local allowed
        if b.needsLeader then allowed = leader else allowed = assist end
        SetButtonEnabled(b, allowed)
    end

    -- Secure buttons: cosmetic only, never Enable/Disable (see header).
    -- 0.8 is the grid's resting opacity (hover lifts to 1); 0.4 is the
    -- no-assist dim, which also suppresses the hover lift.
    for _, b in ipairs(markerButtons) do
        b._baseAlpha = assist and 0.8 or 0.4
        b.icon:SetAlpha(b._baseAlpha)
    end

    if convertButton then
        convertButton._lbl:SetText(raid and EllesmereUI.L("Convert to Party")
                                         or EllesmereUI.L("Convert to Raid"))
    end
end

-------------------------------------------------------------------------------
--  Pull timer
--
--  A pull has to reach the whole raid, not just this client, so the countdown
--  is handed to whichever boss mod is loaded through its published slash
--  handler -- that is the thing that broadcasts the timer to everyone else --
--  and Blizzard's own countdown runs on top for anyone without one.
--
--  Blizzard's countdown travels through chat, so the client refuses it during
--  combat. The boss mod handoff happens first for that reason: it still works
--  there, and losing the in-game countdown is better than losing both.
-------------------------------------------------------------------------------

local function BossModPullHandler()
    return SlashCmdList.BIGWIGSPULL or SlashCmdList.DEADLYBOSSMODSPULL
end

local function ChatLocked()
    return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
       and C_ChatInfo.InChatMessagingLockdown()
end

local function StartPull(secs)
    local handler = BossModPullHandler()
    if handler then handler(tostring(secs)) end
    if ChatLocked() then
        EllesmereUI.Print("|cff0cd29fEllesmereUI:|r " .. EllesmereUI.L("In-game countdown unavailable in combat; the boss mod pull timer still started."))
        return
    end
    C_PartyInfo.DoCountdown(secs)
end

local function StopPull()
    local handler = BossModPullHandler()
    if handler then handler("0") end
    if not ChatLocked() then C_PartyInfo.DoCountdown(0) end
end

-------------------------------------------------------------------------------
--  Group actions
-------------------------------------------------------------------------------

local function DisbandGroup()
    if not IsLeader() then return end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name = GetRaidRosterInfo(i)
            if name and name ~= UnitName("player") then
                C_PartyInfo.UninviteUnit(name)
            end
        end
    else
        for i = 1, GetNumSubgroupMembers() do
            local name = UnitName("party" .. i)
            if name then C_PartyInfo.UninviteUnit(name) end
        end
    end
    C_PartyInfo.LeaveParty()
end

-- The suite's own confirm dialog, not StaticPopup: CONTRIBUTING is explicit
-- that confirmations use ShowConfirmPopup, and it is the one that inherits the
-- panel skin and the scale registry.
local function ConfirmDisband()
    EllesmereUI:ShowConfirmPopup({
        title       = "Disband Group",
        message     = "Disband the group?",
        confirmText = "Disband",
        cancelText  = "Cancel",
        onConfirm   = DisbandGroup,
    })
end

-------------------------------------------------------------------------------
--  Frames (built once, on first non-never Apply -- secure children forbid
--  rebuilding)
-------------------------------------------------------------------------------

-- One secure window shell. Returns the frame; content lives in the plain
-- holders, so the shell owns only chrome (bg, border, title, collapse button)
-- and the visibility state machine.
local function MakeShell(key)
    local f = CreateFrame("Frame", "EllesmereUIRaidTools" .. key, UIParent,
                          "SecureHandlerStateTemplate")
    f:SetWidth(PANEL_W)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:Hide()

    -- The Window Skins dress (see the block above).
    SkinPanelBg(f)
    SkinPanelBorder(f)

    -- Visibility state: see the header. "apply" is the ONLY place this frame
    -- is shown or hidden.
    f:SetAttribute("enabled", true)
    f:SetAttribute("visible", false)
    f:SetAttribute("override", "")
    f:SetAttribute("expanded", true)
    f:SetAttribute("startexpanded", true)
    f:SetAttribute("apply", [[
        if not self:GetAttribute("enabled") then
            self:Hide()
            return
        end
        local ov = self:GetAttribute("override")
        local vis
        if ov == "show" then
            vis = true
        elseif ov == "hide" then
            vis = false
        else
            vis = self:GetAttribute("visible")
        end
        if vis and self:GetAttribute("expanded") then
            self:Show()
        else
            self:Hide()
        end
    ]])
    -- A driver transition is a context change: it reclaims control from any manual
    -- override and re-seeds the collapsed/expanded form. The icon has no state template
    -- of its own (click templates do not dispatch _onstate), so each shell fans the
    -- verdict out to it -- both shells stamping the same values is idempotent.
    f:SetAttribute("_onstate-euirt_vis", [[
        local vis = (newstate == "show")
        self:SetAttribute("visible", vis)
        self:SetAttribute("override", "")
        self:SetAttribute("expanded", self:GetAttribute("startexpanded"))
        self:RunAttribute("apply")
        local icon = self:GetFrameRef("icon")
        if icon then
            icon:SetAttribute("visible", vis)
            icon:SetAttribute("override", "")
            icon:SetAttribute("expanded", self:GetAttribute("startexpanded"))
            icon:RunAttribute("apply")
        end
    ]])

    -- White title, vertically centered in the black band (the skins' title
    -- treatment; the accent stays on interactions, not chrome).
    local fs = TrackFont(f, EllesmereUI.MakeFont(f, 12, nil, 1, 1, 1), 12)
    fs:SetPoint("LEFT", f, "TOPLEFT", PAD, -TOPBAR_H / 2)
    fs:SetText(EllesmereUI.L(SECTION_LABEL[key]))
    shellTitle[key] = fs

    -- Collapse button: small secure corner control riding the title band,
    -- only meaningful (and only shown -- ApplyLayout owns that) while Default
    -- to Collapsed Icon is on. Wears the skins' button chrome.
    local col = CreateFrame("Button", nil, f, "SecureHandlerClickTemplate")
    col:SetSize(14, 14)
    col:SetPoint("RIGHT", f, "TOPRIGHT", -6, -TOPBAR_H / 2)
    col:RegisterForClicks("AnyDown")
    SkinButtonChrome(col)
    local colFs = TrackFont(f, EllesmereUI.MakeFont(col, 14, nil, 1, 1, 1), 14)
    colFs:SetPoint("CENTER", col, "CENTER", 0, 1)
    colFs:SetText("-")
    colFs:SetAlpha(0.7)
    col:SetScript("OnEnter", function() colFs:SetAlpha(1) end)
    col:SetScript("OnLeave", function() colFs:SetAlpha(0.7) end)
    col:SetAttribute("_onclick", COLLAPSE_SNIPPET)
    f._collapseBtn = col

    sections[key] = f
    fontOwners[#fontOwners + 1] = f
    return f
end

-- Places the Group & Pull buttons per the settings and is the ONLY writer of
-- GROUP_CONTENT_H. Plain frames only, run from build and Apply (out of combat);
-- must run BEFORE ApplyLayout, which sizes the shells from that height.
local function LayoutGroupContent()
    if not groupHolder then return end
    local f = groupHolder

    -- Row plan: two action buttons per row in fixed order; hidden buttons close
    -- the gap, a lone button takes the full width.
    local rows, pair = {}, {}
    local function Add(b)
        pair[#pair + 1] = b
        if #pair == 2 then rows[#rows + 1] = pair; pair = {} end
    end
    Add(readyButton)
    if ButtonShown("showRoleCheck") then Add(roleButton) end
    if ButtonShown("showConvert")   then Add(convertButton) end
    if ButtonShown("showDisband")   then Add(disbandButton) end
    if #pair > 0 then rows[#rows + 1] = pair end

    -- Pull row: surviving durations move onto the leading buttons (the click
    -- closure reads b.secs), Stop last; no durations = no row at all.
    local times = VisiblePullTimes()
    if #times > 0 then
        local pull = {}
        for i, secs in ipairs(times) do
            local b = pullButtons[i]
            b.secs = secs
            b._lbl:SetText(tostring(secs))
            pull[i] = b
        end
        pull[#pull + 1] = stopButton
        rows[#rows + 1] = pull
    end

    -- Hide all, then show only what the plan placed.
    for _, b in ipairs(groupButtons) do b:Hide() end

    local y = 0
    for _, row in ipairs(rows) do
        local n = #row
        local w = (PANEL_W - PAD * 2 - ROW_GAP * (n - 1)) / n
        for i, b in ipairs(row) do
            b:SetWidth(w)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + (w + ROW_GAP) * (i - 1), y)
            b:Show()
        end
        y = y - ROW_H - ROW_GAP
    end
    y = y + ROW_GAP   -- the last row's trailing gap is not content

    GROUP_CONTENT_H = -y
    f:SetHeight(GROUP_CONTENT_H)
end

-- Group & Pull content, in its own plain holder so one-window mode can treat
-- it uniformly with the markers holder. Creation only -- the buttons are born
-- unplaced at full-row width, and LayoutGroupContent puts them where the
-- settings say (MakeGroupButton runs labels through L itself).
local function BuildGroupContent()
    groupHolder = CreateFrame("Frame", nil, sections.Group)
    groupHolder:SetWidth(PANEL_W)
    fontOwners[#fontOwners + 1] = groupHolder
    local f = groupHolder
    local full = PANEL_W - PAD * 2

    readyButton = MakeGroupButton(f, "Ready Check", full, function() DoReadyCheck() end)
    roleButton  = MakeGroupButton(f, "Role Check", full, function() InitiateRolePoll() end)

    convertButton = MakeGroupButton(f, "Convert to Raid", full, function()
        if IsInRaid() then C_PartyInfo.ConvertToParty() else C_PartyInfo.ConvertToRaid() end
    end, true)

    disbandButton = MakeGroupButton(f, "Disband", full, function()
        ConfirmDisband()
    end, true)

    for i = 1, PULL_SLOTS do
        -- The pull duration lives on the button and changes at runtime, so
        -- the click reads it through the closure.
        local b
        b = MakeGroupButton(f, "", full, function() StartPull(b.secs) end)
        pullButtons[i] = b
    end
    stopButton = MakeGroupButton(f, "Stop", full, StopPull)

    -- A height right away: BuildAll has callers (the slash command, unlock
    -- mode) that reach the shells without going through Apply.
    LayoutGroupContent()
end

-- Row order matches how they are used: unit markers first, ground markers
-- under them. Labels reach L as variables (see the SECTIONS comment).
local MARKER_ROWS = {
    { kind = "target", label = "Target" },
    { kind = "world",  label = "World"  },
}

local function BuildMarkersContent()
    markersHolder = CreateFrame("Frame", nil, sections.Markers)
    markersHolder:SetWidth(PANEL_W)
    fontOwners[#fontOwners + 1] = markersHolder
    local f = markersHolder
    local y = 0

    -- 8 markers + a clear button per row, evenly spread across the width.
    local step = (PANEL_W - PAD * 2 - MARKER_SZ) / 8
    for r, row in ipairs(MARKER_ROWS) do
        local lbl = TrackFont(f, EllesmereUI.MakeFont(f, 9, nil, 1, 1, 1), 9)
        lbl:SetAlpha(0.55)
        lbl:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
        lbl:SetText(EllesmereUI.L(row.label))
        y = y - MARKER_LBL_H - 2

        for i = 0, 8 do
            local b = MakeMarkerButton(f, i == 8 and 0 or (i + 1), row.kind)
            b:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + step * i, y)
        end
        y = y - MARKER_SZ
        if r < #MARKER_ROWS then y = y - ROW_GAP * 2 end
    end

    MARKERS_CONTENT_H = -y
    f:SetHeight(MARKERS_CONTENT_H)
end

-- Compact Band uses its own holder so the existing window layouts and secure
-- marker buttons keep their original geometry.
-- Its tooltip copies the established Data Bars grammar locally because that
-- child addon is optional: bracketed title, input left and result right.
do
    local tip, owner
    local rows = {}
    local TIP_PAD, TIP_ROW_GAP, TIP_COL_GAP, TIP_FONT_SIZE = 10, 3, 18, 12

    local function SetTipFont(fs)
        local path = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath(FONT_KEY)
        local _, _, flags = fs:GetFont()
        if not path and GameFontNormal then
            local fallbackPath, _, fallbackFlags = GameFontNormal:GetFont()
            path, flags = fallbackPath, fallbackFlags
        end
        if path then fs:SetFont(path, TIP_FONT_SIZE, flags or "") end
    end

    local function EnsureTip()
        if tip then return tip end
        tip = CreateFrame("Frame", "EllesmereUIRaidToolsTip", UIParent)
        tip:SetFrameStrata("TOOLTIP")
        tip:SetFrameLevel(900)
        tip:SetClampedToScreen(true)
        tip:Hide()
        local bg = tip:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.067, 0.067, 0.067, 0.97)
        if EllesmereUI.PP and EllesmereUI.PP.CreateBorder then
            EllesmereUI.PP.CreateBorder(tip, 0, 0, 0, 0.9, 1, "OVERLAY", 7)
        end
        return tip
    end

    local function EnsureRow(i)
        local row = rows[i]
        if not row then
            row = {
                left = tip:CreateFontString(nil, "OVERLAY"),
                right = tip:CreateFontString(nil, "OVERLAY"),
            }
            rows[i] = row
        end
        SetTipFont(row.left)
        SetTipFont(row.right)
        return row
    end

    ShowCompactTip = function(ownerFrame, title, actions)
        EnsureTip()
        owner = ownerFrame
        local count = #actions + 2
        local maxLeft, maxRight, totalH = 0, 0, 0
        for i = 1, count do
            local row = EnsureRow(i)
            row.left:ClearAllPoints()
            row.right:ClearAllPoints()
            row.left:SetWordWrap(false)
            row.right:SetWordWrap(false)
            row.left:SetWidth(0)
            row.right:SetWidth(0)

            if i == 1 then
                row.left:SetText("[" .. EllesmereUI.L(title) .. "]")
                row.right:SetText("")
                row.right:Hide()
                row._h = row.left:GetStringHeight() or TIP_FONT_SIZE
            elseif i == 2 then
                row.left:SetText("")
                row.right:SetText("")
                row.right:Hide()
                row._h = 4
            else
                local action = actions[i - 2]
                row.left:SetText(EllesmereUI.L(action[1]))
                row.right:SetText(EllesmereUI.L(action[2]))
                row.right:Show()
                row._h = math.max(row.left:GetStringHeight() or TIP_FONT_SIZE,
                    row.right:GetStringHeight() or TIP_FONT_SIZE)
            end
            row.left:SetTextColor(1, 1, 1, 1)
            row.right:SetTextColor(1, 1, 1, 1)
            row.left:Show()
            maxLeft = math.max(maxLeft, row.left:GetStringWidth() or 0)
            if row.right:IsShown() then
                maxRight = math.max(maxRight, row.right:GetStringWidth() or 0)
            end
            totalH = totalH + row._h + (i > 1 and TIP_ROW_GAP or 0)
        end
        for i = count + 1, #rows do
            rows[i].left:Hide()
            rows[i].right:Hide()
        end

        local innerW = maxLeft + (maxRight > 0 and TIP_COL_GAP + maxRight or 0)
        tip:SetSize(math.max(60, innerW + TIP_PAD * 2),
            math.max(24, totalH + TIP_PAD * 2))
        local y = -TIP_PAD
        for i = 1, count do
            local row = rows[i]
            row.left:SetPoint("TOPLEFT", tip, "TOPLEFT", TIP_PAD, y)
            if row.right:IsShown() then
                row.right:SetPoint("TOPRIGHT", tip, "TOPRIGHT", -TIP_PAD, y)
            end
            y = y - row._h - TIP_ROW_GAP
        end

        local level = 900
        if GameTooltip and GameTooltip.GetFrameLevel then
            local gameTipLevel = GameTooltip:GetFrameLevel()
            if gameTipLevel then level = math.max(level, gameTipLevel + 10) end
        end
        if tip:GetFrameLevel() < level then tip:SetFrameLevel(level) end
        tip:ClearAllPoints()
        local _, cy = ownerFrame:GetCenter()
        if cy and cy < UIParent:GetHeight() / 2 then
            tip:SetPoint("BOTTOM", ownerFrame, "TOP", 0, 6)
        else
            tip:SetPoint("TOP", ownerFrame, "BOTTOM", 0, -6)
        end
        tip:Show()
    end

    HideCompactTip = function(ownerFrame)
        if not tip or (ownerFrame and owner ~= ownerFrame) then return end
        owner = nil
        tip:Hide()
    end
end

local function MakeCompactActionButton(parent, label, tipBuilder, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(COMPACT_ICON, COMPACT_ICON)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", onClick)
    local fs = TrackFont(parent, EllesmereUI.MakeFont(b, 11, nil, 1, 1, 1), 11)
    fs:SetPoint("CENTER")
    fs:SetText(label)
    fs:SetAlpha(0.8)
    b.label = fs
    b:SetScript("OnEnter", function(self)
        self.label:SetAlpha(1)
        local title, actions = tipBuilder()
        ShowCompactTip(self, title, actions)
    end)
    b:SetScript("OnLeave", function(self)
        self.label:SetAlpha(0.8)
        HideCompactTip(self)
    end)
    groupButtons[#groupButtons + 1] = b
    return b
end

local function CompactPullTime(slot)
    local times = (P() and P().pullTimes) or {}
    local value = times[slot]
    if value == nil then value = PULL_DEFAULTS[slot] end
    return value and value > 0 and value or nil
end

-- Fill the complete marker region instead of leaving a dead elastic gap before
-- the utilities. Skull owns the left edge, Clear owns the right edge beside
-- the divider, and the seven symbols between them share the remaining width.
local function LayoutCompactMarkers()
    if not compactHolder or not sections.Group or #compactMarkerButtons < 2 then return end
    local width = sections.Group:GetWidth()
    if not width or width < COMPACT_MIN_W then return end

    local utilityCount = compactPullButton and compactPullButton:IsShown() and 2 or 1
    local utilityWidth = utilityCount * COMPACT_ICON
        + (utilityCount - 1) * COMPACT_GAP
    local firstLeft = COMPACT_PAD
    local lastLeft = width - COMPACT_PAD - utilityWidth
        - COMPACT_DIVIDER_OFFSET - COMPACT_GAP - COMPACT_ICON
    local stride = (lastLeft - firstLeft) / (#compactMarkerButtons - 1)

    for i, button in ipairs(compactMarkerButtons) do
        button:ClearAllPoints()
        local x = math.floor(firstLeft + (i - 1) * stride + 0.5)
        button:SetPoint("LEFT", compactHolder, "LEFT", x, 0)
    end
end

local function RefreshCompactPullState()
    if not compactPullButton then return end
    local secs = CompactPullTime(3) or CompactPullTime(2) or CompactPullTime(1)
    compactPullButton:SetShown(secs ~= nil)
    if compactReadyButton then
        compactReadyButton:Show()
        compactReadyButton:ClearAllPoints()
        compactReadyButton:SetPoint("RIGHT", compactHolder, "RIGHT", -COMPACT_PAD, 0)
    end
    compactPullButton:ClearAllPoints()
    if secs and compactReadyButton then
        compactPullButton:SetPoint("RIGHT", compactReadyButton, "LEFT", -COMPACT_GAP, 0)
    end
    if compactDivider and compactReadyButton then
        local firstUtility = secs and compactPullButton or compactReadyButton
        compactDivider:ClearAllPoints()
        compactDivider:SetPoint("TOP", firstUtility, "TOPLEFT",
            -COMPACT_DIVIDER_OFFSET, -2)
        compactDivider:SetPoint("BOTTOM", firstUtility, "BOTTOMLEFT",
            -COMPACT_DIVIDER_OFFSET, 2)
    end
    LayoutCompactMarkers()
end

local function RefreshCompactMarkerState()
    for _, b in ipairs(compactMarkerButtons) do
        local active = b._worldID and IsRaidMarkerActive and IsRaidMarkerActive(b._worldID)
        if b.icon.SetDesaturated then b.icon:SetDesaturated(active and true or false) end
        if b._activeLine then b._activeLine:SetShown(active and true or false) end
    end
end

local function BuildCompactContent()
    compactHolder = CreateFrame("Frame", nil, sections.Group)
    compactHolder:SetHeight(COMPACT_H)

    -- Blizzard's marker menus and the supplied references both read
    -- Star -> Skull from left to right, followed by one clear action.
    local markerOrder = { 1, 2, 3, 4, 5, 6, 7, 8 }
    for _, index in ipairs(markerOrder) do
        local b = MakeMarkerButton(compactHolder, index, "compact")
        compactMarkerButtons[#compactMarkerButtons + 1] = b
    end
    local clear = MakeMarkerButton(compactHolder, 0, "compact-clear")
    compactMarkerButtons[#compactMarkerButtons + 1] = clear

    compactReadyButton = MakeCompactActionButton(compactHolder,
        "RC",
        function()
            if ButtonShown("showRoleCheck") then
                return "Ready Check", {
                    { "Left Click", "Ready Check" },
                    { "Right Click", "Role Check" },
                }
            end
            return "Ready Check", {
                { "Left Click", "Ready Check" },
            }
        end,
        function(_, button)
            if button == "RightButton" then
                if ButtonShown("showRoleCheck") then InitiateRolePoll() end
            else
                DoReadyCheck()
            end
        end)

    compactPullButton = MakeCompactActionButton(compactHolder,
        "PT",
        function()
            local a = CompactPullTime(1) or "off"
            local b = CompactPullTime(2) or "off"
            local c = CompactPullTime(3) or "off"
            return "Pull Timer", {
                { "Left Click", "Pull " .. c },
                { "Shift + Left Click", "Pull " .. b },
                { "Ctrl + Left Click", "Pull " .. a },
                { "Right Click", "Stop pull timer" },
            }
        end,
        function(_, button)
            if button == "RightButton" then StopPull(); return end
            local secs
            if IsControlKeyDown() then
                secs = CompactPullTime(1)
            elseif IsShiftKeyDown() then
                secs = CompactPullTime(2)
            else
                secs = CompactPullTime(3) or CompactPullTime(2) or CompactPullTime(1)
            end
            if secs then StartPull(secs) end
        end)

    -- Pull is the inner utility beside the marker region; Ready Check owns the
    -- far-right edge, matching the established scan order from raid action to
    -- group confirmation.
    compactReadyButton:SetPoint("RIGHT", compactHolder, "RIGHT", -COMPACT_PAD, 0)
    compactPullButton:SetPoint("RIGHT", compactReadyButton, "LEFT", -COMPACT_GAP, 0)

    compactDivider = compactHolder:CreateTexture(nil, "ARTWORK")
    compactDivider:SetColorTexture(1, 1, 1, 0.10)
    compactDivider:SetWidth(1)
    compactDivider:SetPoint("TOP", compactPullButton, "TOPLEFT",
        -COMPACT_DIVIDER_OFFSET, -2)
    compactDivider:SetPoint("BOTTOM", compactPullButton, "BOTTOMLEFT",
        -COMPACT_DIVIDER_OFFSET, 2)

    RefreshCompactPullState()
    RefreshCompactMarkerState()
end

-- The collapsed-state square: bg + border + the icon, expanding on click.
-- A click template (not a state template) -- it cannot dispatch _onstate, so
-- the shells fan the driver verdict to it (see MakeShell).
local function BuildCollapsedIcon()
    iconBtn = CreateFrame("Button", "EllesmereUIRaidToolsIcon", UIParent,
                          "SecureHandlerClickTemplate")
    iconBtn:SetSize(ICON_SZ, ICON_SZ)
    iconBtn:SetFrameStrata("MEDIUM")
    iconBtn:SetClampedToScreen(true)
    iconBtn:RegisterForClicks("AnyDown")
    iconBtn:Hide()
    -- Rides the Group shell's saved position with no bookkeeping of its own:
    -- anchoring to a hidden frame is fine, the anchor resolves through its points.
    iconBtn:SetPoint("TOPLEFT", nil, "TOPLEFT", 0, 0)  -- re-pointed at build

    -- The button IS the art: full-bleed image at full opacity, no chrome and
    -- no tooltip.
    local tex = iconBtn:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(iconBtn)
    tex:SetTexture(COLLAPSED_ICON_TEX)

    -- Hover whitens the art by 10%: the SAME image additively at 0.1 on the
    -- native HIGHLIGHT layer (auto shown on mouseover, no scripts). Re-using
    -- the image keeps the lift inside its alpha channel -- a plain white ADD
    -- rect would glow the transparent corners too. Vertex color cannot do
    -- this; it only multiplies downward.
    local hl = iconBtn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(iconBtn)
    hl:SetTexture(COLLAPSED_ICON_TEX)
    hl:SetBlendMode("ADD")
    hl:SetAlpha(0.5)

    iconBtn:SetAttribute("enabled", true)
    iconBtn:SetAttribute("visible", false)
    iconBtn:SetAttribute("override", "")
    iconBtn:SetAttribute("expanded", true)
    iconBtn:SetAttribute("startexpanded", true)
    iconBtn:SetAttribute("apply", [[
        if not self:GetAttribute("enabled") then
            self:Hide()
            return
        end
        local ov = self:GetAttribute("override")
        local vis
        if ov == "show" then
            vis = true
        elseif ov == "hide" then
            vis = false
        else
            vis = self:GetAttribute("visible")
        end
        if vis and not self:GetAttribute("expanded") then
            self:Show()
        else
            self:Hide()
        end
    ]])
    iconBtn:SetAttribute("_onclick", EXPAND_SNIPPET)
end

local function BuildAll()
    if sections.Group then return end
    MakeShell("Group")
    MakeShell("Markers")
    BuildGroupContent()
    BuildMarkersContent()
    BuildCollapsedIcon()
    iconBtn:ClearAllPoints()
    iconBtn:SetPoint("TOPLEFT", sections.Group, "TOPLEFT", 0, 0)

    -- Keybind target. Shown (a hidden button cannot take a CLICK binding) but
    -- 1px, transparent and parked off-screen. It flips everything together
    -- from one computed value, so the pieces can never drift apart.
    toggleButton = CreateFrame("Button", "EllesmereUIRaidToolsToggle", UIParent,
                               "SecureHandlerClickTemplate")
    toggleButton:SetSize(1, 1)
    toggleButton:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -100, -100)
    toggleButton:SetAlpha(0)
    toggleButton:RegisterForClicks("AnyDown")
    toggleButton:SetAttribute("count", #SECTION_KEYS)
    toggleButton:SetAttribute("_onclick", TOGGLE_SNIPPET)

    -- Frame refs: the toggle, the icon and each collapse button all reach the
    -- same set; the shells reach the icon for the _onstate fan-out.
    for i, key in ipairs(SECTION_KEYS) do
        local shell = sections[key]
        toggleButton:SetFrameRef("s" .. i, shell)
        shell:SetFrameRef("icon", iconBtn)
        shell._collapseBtn:SetAttribute("count", #SECTION_KEYS)
        for j, k2 in ipairs(SECTION_KEYS) do
            shell._collapseBtn:SetFrameRef("s" .. j, sections[k2])
        end
        shell._collapseBtn:SetFrameRef("icon", iconBtn)
        iconBtn:SetFrameRef("s" .. i, shell)
    end
    toggleButton:SetFrameRef("icon", iconBtn)
    iconBtn:SetAttribute("count", #SECTION_KEYS)
end

-------------------------------------------------------------------------------
--  Layout / position / mode
-------------------------------------------------------------------------------

-- Menu Grow Direction -> which corner of the primary shell the collapsed
-- icon occupies. The icon is the piece the user parks, so the corner it
-- rides decides which way the windows appear to grow from it on expand:
-- icon at TOPLEFT = windows extend down-right (the original behaviour),
-- icon at BOTTOMLEFT = up-right, and so on.
local ICON_CORNER = {
    downright = "TOPLEFT",
    upright   = "BOTTOMLEFT",
    downleft  = "TOPRIGHT",
    upleft    = "BOTTOMRIGHT",
}

local function ApplyShellMaterial(f, compact)
    if f._bgArt then f._bgArt:SetShown(not compact) end
    if f._titleBar then f._titleBar:SetShown(not compact) end
    if f._bgOverlay then f._bgOverlay:SetColorTexture(0, 0, 0, 0.62) end
    if f._windowBorder then f._windowBorder:SetShown(not compact) end
end

-- Show-as arrangement. OOC only (Apply gates); the holders are plain frames,
-- so the re-parent is an ordinary SetParent.
local function ApplyLayout()
    local p = P()
    local showAs = ShowAs()
    local winGroup, winMarkers = sections.Group, sections.Markers

    local compact = showAs == "compact"
    local collapseUI = not compact and p and p.collapsedIcon ~= false
    winGroup._collapseBtn:SetShown(collapseUI)
    -- Two Windows: only Group & Pull carries the collapse control -- one
    -- button folds the whole feature, and a second on Markers would just be
    -- a duplicate. Markers keeps its own ONLY when it is the lone window.
    winMarkers._collapseBtn:SetShown(collapseUI and showAs ~= "two")

    ApplyShellMaterial(winGroup, compact)
    ApplyShellMaterial(winMarkers, false)
    shellTitle.Group:SetShown(not compact)
    shellTitle.Markers:SetShown(true)
    if compact and not compactHolder then BuildCompactContent() end
    if compactHolder then compactHolder:SetShown(compact) end

    if compact then
        local width = CompactWidth()
        winGroup:SetWidth(width)
        compactHolder:SetParent(winGroup)
        compactHolder:ClearAllPoints()
        compactHolder:SetAllPoints(winGroup)
        groupHolder:SetShown(false)
        markersHolder:SetShown(false)
        winGroup:SetHeight(CompactHeight())
    elseif showAs == "one" then
        winGroup:SetWidth(PANEL_W)
        winMarkers:SetWidth(PANEL_W)
        shellTitle.Group:SetText(EllesmereUI.L(COMBINED_LABEL))
        groupHolder:SetShown(true)
        groupHolder:SetParent(winGroup)
        groupHolder:ClearAllPoints()
        groupHolder:SetPoint("TOPLEFT", winGroup, "TOPLEFT", 0, -CONTENT_TOP)
        markersHolder:SetShown(true)
        markersHolder:SetParent(winGroup)
        markersHolder:ClearAllPoints()
        markersHolder:SetPoint("TOPLEFT", winGroup, "TOPLEFT", 0,
            -CONTENT_TOP - GROUP_CONTENT_H - ROW_GAP * 2)
        winGroup:SetHeight(CONTENT_TOP + GROUP_CONTENT_H + ROW_GAP * 2
            + MARKERS_CONTENT_H + PAD)
    else
        winGroup:SetWidth(PANEL_W)
        winMarkers:SetWidth(PANEL_W)
        -- Every split mode parents each holder to its own shell; which shells
        -- actually SHOW is ApplyVisibility's call (the enabled attribute).
        shellTitle.Group:SetText(EllesmereUI.L(SECTION_LABEL.Group))
        groupHolder:SetParent(winGroup)
        groupHolder:SetShown(true)
        groupHolder:ClearAllPoints()
        groupHolder:SetPoint("TOPLEFT", winGroup, "TOPLEFT", 0, -CONTENT_TOP)
        winGroup:SetHeight(CONTENT_TOP + GROUP_CONTENT_H + PAD)

        markersHolder:SetParent(winMarkers)
        markersHolder:SetShown(true)
        markersHolder:ClearAllPoints()
        markersHolder:SetPoint("TOPLEFT", winMarkers, "TOPLEFT", 0, -CONTENT_TOP)
        winMarkers:SetHeight(CONTENT_TOP + MARKERS_CONTENT_H + PAD)
    end

    -- The collapsed icon rides the shell the mode actually shows: Markers-only anchors
    -- (and scales, see Apply) to the Markers shell, everything else to Group & Pull.
    -- Which CORNER it rides is the Menu Grow Direction setting (see ICON_CORNER above).
    local corner = ICON_CORNER[p and p.growDir] or "TOPLEFT"
    iconBtn:ClearAllPoints()
    iconBtn:SetPoint(corner,
        (showAs == "markers") and winMarkers or winGroup, corner, 0, 0)

    -- Heights just moved: re-crop the backdrop art so it covers instead of
    -- stretches (the skins hook SetHeight for this; our heights only ever
    -- change right here, so a direct call is the whole hook).
    if winGroup._bgFit then winGroup._bgFit() end
    if winMarkers._bgFit then winMarkers._bgFit() end
    RefreshCompactPullState()
    RefreshCompactMarkerState()
end

-- Positions round-trip through unlock mode's CENTER/CENTER convention.
--
-- That pairing is not decoration: for an odd-height frame the stored centre ends in .5,
-- and ApplyCenterPosition subtracts the live half-height so the edges land back on
-- whole pixels. Applying the stored value with a plain SetPoint skips that and leaves
-- the frame a pixel off -- visible only after the snap tool, because a normal drag is
-- converted on the way in and a snapped one is not.
local function DefaultPos(key)
    -- Unpositioned installs park the whole feature in the TOP-LEFT corner of
    -- the screen (a small margin off the edges); two-window mode stacks
    -- Markers under Group & Pull. A saved position always wins over this.
    local MARGIN = 20
    local top = -MARGIN
    if key == "Markers" then
        top = top - (sections.Group:GetHeight() * WindowScale() + ROW_GAP)
    end
    -- Screen-space margin converted into the frame's own scaled units.
    local s = WindowScale()
    return { point = "TOPLEFT", relPoint = "TOPLEFT", x = MARGIN / s, y = top / s }
end

local function ApplySectionPosition(key, unlockKey, posKey)
    local f = sections[key]
    if not f then return end
    if InCombatLockdown() then applyPending = true; return end

    local p = P()
    unlockKey = unlockKey or (UNLOCK_KEY .. key)
    posKey = posKey or key
    local pos = ((p and p.pos) or {})[posKey] or DefaultPos(key)
    if EllesmereUI.ApplyCenterPosition
       and pos.point == "CENTER" and pos.relPoint == "CENTER" then
        -- Skips anchor-linked elements itself, and defers its own combat case for
        -- protected frames. FALSE means it could not resolve a live frame for this key
        -- -- fall through to the plain path, exactly as unlock mode's own caller does.
        if EllesmereUI.ApplyCenterPosition(unlockKey, pos) then return end
    end

    -- Anything not in that convention is a default or a pre-conversion value.
    if EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored(unlockKey) then
        return
    end
    f:ClearAllPoints()
    f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
end

local function ApplyPositions()
    -- While an unlock session is open UNLOCK MODE owns these frames: it moves them live
    -- and only writes the result on Save & Exit. A settings pass landing mid-session
    -- (the options panel hiding/showing flips the preview, and a combat-deferred Apply
    -- completes on PLAYER_REGEN_ENABLED) would drag the window back to the last SAVED
    -- spot -- and because Save & Exit derives the value it stores from the frame's LIVE
    -- bounds, the drag is then written back as the old position and lost for good. Same
    -- guard Action Bars, Aura Reminders and the Cooldown Manager already carry.
    if EllesmereUI._unlockActive then return end

    -- Each shell is positioned only when the Show as choice can put it on screen; One
    -- Window and Only Group & Pull ride pos.Group, Only Markers rides pos.Markers.
    local showAs = ShowAs()
    if showAs == "compact" then
        ApplySectionPosition("Group", COMPACT_UNLOCK_KEY, "Compact")
    elseif showAs ~= "markers" then
        ApplySectionPosition("Group")
    end
    if showAs == "two" or showAs == "markers" then ApplySectionPosition("Markers") end
end

-- The whole replacement for the old shared-visibility machinery: two literal
-- driver strings keyed by mode. [group] is any group; [group:raid] raid only.
local MODE_DRIVERS = {
    raid  = "[group:raid] show; hide",
    group = "[group] show; hide",
}

-- Reached only from Apply, which has already returned if we are in combat.
local function ApplyVisibility()
    local p = P()
    local mode = Mode()
    local driver = MODE_DRIVERS[mode]
    -- The out-of-combat settle for the state a driver will not re-fire
    -- (registering one only fires _onstate on a CHANGE). Always mode has no
    -- driver at all: the settle IS its entire visibility source.
    local visNow = false
    if mode == "raid" then
        visNow = IsInRaid()
    elseif mode == "group" then
        visNow = IsInGroup()
    elseif mode == "always" then
        visNow = true
    end

    -- Which SHELLS may show, straight from Show as: the Group shell is the
    -- window everywhere except Markers-only; the Markers shell exists only in
    -- Two Windows and Markers-only.
    --
    -- The assist gate rides on top of that and takes ALL of them, icon
    -- included -- a raid without assist is a raid where nothing here works.
    local showAs = ShowAs()
    local compact = showAs == "compact"
    local suppressed = AssistSuppressed()
    local shellOn = {
        Group   = showAs ~= "markers" and not suppressed,
        Markers = (showAs == "two" or showAs == "markers") and not suppressed,
    }
    -- One seed for every show (see header): Default to Collapsed When Shown.
    -- With the toggle off the seed is "expanded" and the icon never shows.
    -- The strip is already the minimized form. Its keybind is therefore a
    -- direct show/hide, never a second collapse into a mystery icon.
    local startExpanded = compact or not (p and p.collapsedIcon ~= false)

    -- Settings preview (the TBB-placeholder arrangement): while the Raid
    -- Tools page is in front, the windows are forced shown and FULLY EXPANDED
    -- so every settings change is visible as it lands, and the drivers stay
    -- unregistered so a group transition cannot collapse or hide the thing
    -- being configured mid-edit. Only the LIVE state is forced; the seeds
    -- keep their configured values for when the preview ends.
    local expandedNow = startExpanded
    if previewOn then
        driver = nil
        visNow = true
        expandedNow = true
    end

    for _, key in ipairs(SECTION_KEYS) do
        local f = sections[key]
        local on = shellOn[key] and true or false

        f:SetAttribute("enabled", on)
        f:SetAttribute("visible", visNow)
        f:SetAttribute("override", "")
        f:SetAttribute("startexpanded", startExpanded)
        f:SetAttribute("expanded", expandedNow)

        UnregisterStateDriver(f, "euirt_vis")
        if on and driver then
            RegisterStateDriver(f, "euirt_vis", driver)
        end
    end

    -- The icon represents the whole feature; every Show as choice shows
    -- something, so it is on while the mode is active and the assist gate is
    -- open. With it shut the keybind and the slash command go quiet too --
    -- both run the secure snippets, and those refuse a disabled frame.
    iconBtn:SetAttribute("enabled", not compact and not suppressed)
    iconBtn:SetAttribute("visible", visNow)
    iconBtn:SetAttribute("override", "")
    iconBtn:SetAttribute("startexpanded", startExpanded)
    iconBtn:SetAttribute("expanded", expandedNow)

    -- What is now ON SCREEN, for the roster handler to compare against.
    lastSuppressed = suppressed

    -- Run the snippets rather than re-deciding in Lua: attributes are set
    -- first so "apply" sees them.
    if SecureHandlerExecute then
        for _, key in ipairs(SECTION_KEYS) do
            SecureHandlerExecute(sections[key], RUN_APPLY)
        end
        SecureHandlerExecute(iconBtn, RUN_APPLY)
    end
end

-- Toggle Raid Tools key: profile-stored, applied as an override binding on
-- the secure toggle button -- the exact arrangement Action Bars uses for
-- Toggle Action Bar. Pressing the bound key is a hardware click,
-- so the toggle itself works IN combat; only (re)binding defers.
local function ApplyToggleKeybind()
    if not toggleButton then return end
    ClearOverrideBindings(toggleButton)
    local p = P()
    local k = p and p.toggleKey
    -- The gate takes the binding with it rather than leaving a key that eats
    -- its own keypress: the snippet would refuse a disabled frame, and an
    -- override binding swallows whatever the key does otherwise.
    if k and k ~= "" and Mode() ~= "never" and not AssistSuppressed() then
        SetOverrideBindingClick(toggleButton, false, k, "EllesmereUIRaidToolsToggle")
    end
end

-------------------------------------------------------------------------------
--  Lifecycle
--
--  Nothing exists until the mode first leaves "never": no frames, no events,
--  no bindings, no unlock rows. Apply() is the single entry point.
-------------------------------------------------------------------------------

-- The assist gate is Lua's, so a promotion, a demotion or a raid you join
-- without assist has to bring Apply back around -- no state driver will do it
-- for us. Compared against what ApplyVisibility last put on screen, because
-- GROUP_ROSTER_UPDATE bursts and Apply is not free.
--
-- In combat Apply parks itself behind applyPending, which leaves lastSuppressed
-- untouched: the next roster event re-enters here and parks again, and
-- PLAYER_REGEN_ENABLED finishes the job. That is the module's standard
-- deferral, not an omission.
local function RefreshAssistGate()
    if AssistSuppressed() ~= lastSuppressed then Apply() end
end

-- Events live only while the feature is active (or while a combat-deferred
-- Apply is pending, since PLAYER_REGEN_ENABLED is what completes it). The
-- frame itself is created on first need and reused.
local ev
local function EnsureEvents()
    if not ev then
        ev = CreateFrame("Frame")
        ev:SetScript("OnEvent", function(_, event)
            -- Pending work FIRST, before the mode gate: a switch TO "never" deferred by
            -- combat must complete even though the profile already reads never --
            -- swallowing it here is how panels get stranded on screen.
            if event == "PLAYER_REGEN_ENABLED" and applyPending then
                Apply()
                return
            end
            if Mode() == "never" then return end
            if event == "RAID_TARGET_UPDATE" then
                RefreshCompactMarkerState()
            end
            RefreshPermissions()
            RefreshAssistGate()
        end)
    end
    ev:RegisterEvent("GROUP_ROSTER_UPDATE")
    ev:RegisterEvent("PARTY_LEADER_CHANGED")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    if Mode() ~= "never" and ShowAs() == "compact" then
        ev:RegisterEvent("RAID_TARGET_UPDATE")
    else
        ev:UnregisterEvent("RAID_TARGET_UPDATE")
    end
end
local function DropEvents()
    if ev then ev:UnregisterAllEvents() end
end

-- Unlock-mode movers, registered once, on first activation. getFrame
-- returning nil keeps an element out of unlock mode, which is also how
-- one-window mode collapses the feature to a single element: the Markers
-- entry vanishes and the Group entry moves the combined window via pos.Group.
local unlockRegistered
local function RegisterUnlock()
    if unlockRegistered then return end
    local MK = EllesmereUI.MakeUnlockElement
    if not MK then return end
    unlockRegistered = true

    local elements = {}
    for i, key in ipairs(SECTION_KEYS) do
        local unlockKey = UNLOCK_KEY .. key
        elements[#elements + 1] = MK({
            key      = unlockKey,
            label    = SECTION_LABEL[key],
            group    = "Raid Tools",
            order    = 540 + i,
            noResize = true,
            getFrame = function()
                if Mode() == "never" then return nil end
                -- Nothing to move while the assist gate has the whole feature
                -- off the screen -- same opt-out as the modes below.
                if AssistSuppressed() then return nil end
                -- Offer exactly the shells the Show as choice puts on screen:
                -- One Window / Only Group & Pull = the Group element alone,
                -- Two Windows = both, Only Markers = the Markers element alone.
                local showAs = ShowAs()
                if key == "Group" and (showAs == "compact" or showAs == "markers") then
                    return nil
                end
                if key == "Markers" and showAs ~= "two" and showAs ~= "markers" then return nil end
                BuildAll()
                return sections[key]
            end,
            getSize  = function()
                -- Unlock mode sizes the mover overlay in UIParent units, so
                -- the Window Scale has to be folded in here -- GetWidth is the
                -- frame's own (unscaled) size.
                local s = WindowScale()
                local f = sections[key]
                if f then return f:GetWidth() * s, f:GetHeight() * s end
                return PANEL_W * s, 60 * s
            end,
            savePos = function(_, point, relPoint, x, y)
                if not point then return end
                local p = P(); if not p then return end
                -- Unlock mode hands us two conventions: a normal drag arrives
                -- already converted to CENTER/CENTER, a snapped one arrives
                -- raw. Converting here makes both identical --
                -- ConvertToCenterPos passes an already-CENTER value through
                -- untouched, so the drag path is unaffected.
                if EllesmereUI.ConvertToCenterPos then
                    point, relPoint, x, y =
                        EllesmereUI.ConvertToCenterPos(unlockKey, point, relPoint, x, y)
                end
                -- Direct index, no `p.pos = p.pos or {}` reseed: DB_DEFAULTS
                -- guarantees the table, and under a Spec Overrides capture
                -- proxy the reseed stores a proxy into the real profile (the
                -- hazard the P() comment documents). Writing THROUGH p.pos is
                -- proxy-safe; storing it back is not.
                if not p.pos then return end
                p.pos[key] = { point = point, relPoint = relPoint, x = x, y = y }
                if not EllesmereUI._unlockActive then ApplySectionPosition(key) end
            end,
            loadPos  = function() return ((P() and P().pos) or {})[key] end,
            clearPos = function()
                local p = P(); if p and p.pos then p.pos[key] = nil end
            end,
            applyPos = function()
                -- Compact reuses the Group shell but owns a separate unlock key
                -- and saved position. The global login pass visits every
                -- registered element, including this inactive legacy entry; do
                -- not let its stale Group position overwrite Compact's position.
                if key == "Group" and ShowAs() == "compact" then return end
                ApplySectionPosition(key)
            end,
        })
    end

    elements[#elements + 1] = MK({
        key      = COMPACT_UNLOCK_KEY,
        label    = "Compact Band",
        group    = "Raid Tools",
        order    = 540,
        getFrame = function()
            if Mode() == "never" or AssistSuppressed() or ShowAs() ~= "compact" then
                return nil
            end
            BuildAll()
            return sections.Group
        end,
        getSize = function()
            local f = sections.Group
            if f then return f:GetWidth(), f:GetHeight() end
            return CompactWidth(), CompactHeight()
        end,
        setWidth = function(_, newW)
            local p = P()
            if not (p and newW) then return end
            local PP = EllesmereUI and EllesmereUI.PP
            p.compactWidth = math.max(COMPACT_MIN_W,
                PP and PP.Snap(newW) or math.floor(newW + 0.5))
            if sections.Group then ApplyLayout() end
        end,
        setHeight = function(_, newH)
            local p = P()
            if not (p and newH) then return end
            local PP = EllesmereUI and EllesmereUI.PP
            p.compactHeight = math.max(COMPACT_MIN_H,
                PP and PP.Snap(newH) or math.floor(newH + 0.5))
            if sections.Group then ApplyLayout() end
        end,
        savePos = function(_, point, relPoint, x, y)
            if not point then return end
            local p = P()
            if not (p and p.pos) then return end
            if EllesmereUI.ConvertToCenterPos then
                point, relPoint, x, y = EllesmereUI.ConvertToCenterPos(
                    COMPACT_UNLOCK_KEY, point, relPoint, x, y)
            end
            p.pos.Compact = { point = point, relPoint = relPoint, x = x, y = y }
            if not EllesmereUI._unlockActive then
                ApplySectionPosition("Group", COMPACT_UNLOCK_KEY, "Compact")
            end
        end,
        loadPos = function() return ((P() and P().pos) or {}).Compact end,
        clearPos = function()
            local p = P()
            if p and p.pos then p.pos.Compact = nil end
        end,
        applyPos = function()
            if ShowAs() ~= "compact" then return end
            ApplySectionPosition("Group", COMPACT_UNLOCK_KEY, "Compact")
        end,
    })

    if #elements > 0 then
        EllesmereUI:RegisterUnlockElements(elements, "EllesmereUIQoL")
    end
end

-- Options-page entry point, and the completion target for combat-deferred work. Every
-- path below writes secure attributes, drivers, bindings or geometry on protected
-- frames -- ALL blocked in lockdown, the switch to "never" included (SetAttribute is as
-- protected as Hide). So in combat the whole request is parked behind applyPending,
-- with the REGEN listener guaranteed alive to finish it.
function Apply()
    if InCombatLockdown() then
        applyPending = true
        EnsureEvents()
        return
    end
    applyPending = false

    -- The settings preview builds and shows even on Never: the page being in
    -- front means the user is configuring the thing, and an invisible subject
    -- makes every control feel dead. Preview off restores the true teardown.
    if Mode() == "never" and not previewOn then
        if sections.Group then
            for _, key in ipairs(SECTION_KEYS) do
                local f = sections[key]
                UnregisterStateDriver(f, "euirt_vis")
                f:SetAttribute("enabled", false)
                f:SetAttribute("override", "")
                f:Hide()
            end
            iconBtn:SetAttribute("enabled", false)
            iconBtn:Hide()
            ClearOverrideBindings(toggleButton)
        end
        -- Fully off and nothing pending: no reason to keep hearing roster
        -- spam. Never-activated sessions never created the frame at all.
        DropEvents()
        return
    end

    EnsureEvents()
    RegisterUnlock()
    BuildAll()
    -- Before ApplyLayout: it sizes the shells from GROUP_CONTENT_H, which the
    -- hidden buttons and the 0-second pull slots move.
    LayoutGroupContent()
    ApplyLayout()
    -- One Window Scale for everything the feature draws.
    local scale = WindowScale()
    sections.Group:SetScale(scale)
    sections.Markers:SetScale(scale)
    iconBtn:SetScale(scale)
    ApplyPositions()
    ApplyVisibility()
    ApplyToggleKeybind()
    ApplyFonts()
    RefreshPermissions(true)
end
_G._EUI_RaidTools_Apply = Apply

-- Settings-page preview switch (see ApplyVisibility). A global rather than an
-- ns export on purpose: the QoL page dispatcher in EUI_QoL_Options.lua has no
-- ns capture, and it is the one that must end the preview when another QoL
-- page builds. Same convention as _EUI_RaidTools_Apply.
_G._EUI_RaidTools_Preview = function(on)
    on = on and true or false
    if previewOn == on then return end
    previewOn = on
    Apply()
end

-------------------------------------------------------------------------------
--  Slash command
-------------------------------------------------------------------------------

-- Same snippet as the keybind, entered through SecureHandlerExecute -- which
-- insecure code may only do out of combat, hence the message below. This
-- deliberately does NOT go through toggleButton:Click(): the button is
-- registered for "AnyDown" only, and a bare Click() simulates an up event, so
-- the handler would never fire. The keybind keeps the hardware path because a
-- real click is the only thing that can run the snippet during combat.
local function ToggleOutOfCombat()
    if toggleButton and SecureHandlerExecute then
        SecureHandlerExecute(toggleButton, TOGGLE_SNIPPET)
    end
end

SLASH_EUIRAIDTOOLS1 = "/euiraid"
SlashCmdList["EUIRAIDTOOLS"] = function()
    if Mode() == "never" then
        EllesmereUI.Print("|cff0cd29fEllesmereUI:|r " .. EllesmereUI.L("Raid Tools is disabled in the EllesmereUI options."))
        return
    end
    if InCombatLockdown() then
        EllesmereUI.Print("|cff0cd29fEllesmereUI:|r " .. EllesmereUI.L("Raid Tools cannot be toggled by slash command in combat -- use the keybind."))
        return
    end
    -- The snippet would refuse anyway (enabled is false while the gate is
    -- shut); saying so beats a slash command that looks broken.
    if AssistSuppressed() then
        EllesmereUI.Print("|cff0cd29fEllesmereUI:|r " .. EllesmereUI.L("Raid Tools is hidden in a raid without leader or assist -- none of its buttons work there."))
        return
    end
    BuildAll()
    ToggleOutOfCombat()
end

-------------------------------------------------------------------------------
--  Init -- same shape as the other QoL features: take the shared QoL DB handle
--  on PLAYER_LOGIN, publish it, then start. Apply() is a no-op for anyone on
--  the default "never" mode: no frames, no events, no unlock rows.
-------------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    if not (EllesmereUI and EllesmereUI.Lite and EllesmereUI.Lite.NewDB) then return end
    db = EllesmereUI.Lite.NewDB("EllesmereUIQoLDB", DB_DEFAULTS, true)
    _G._EUI_RaidTools_DB = function() return db end
    Apply()
end)
