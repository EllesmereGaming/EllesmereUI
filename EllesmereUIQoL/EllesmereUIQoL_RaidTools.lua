-------------------------------------------------------------------------------
--  EllesmereUIQoL_RaidTools.lua -- Raid control panels (QoL: Raid Tools page)
--
--  TWO content groups -- Group & Pull (ready/role/convert/disband + the pull
--  timer; plain buttons) and Markers (target row + world row; secure buttons,
--  placeable mid-combat) -- shown either as one combined window (default) or
--  as two independently positioned windows.
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
--  The Toggle Raid Tools keybind works in every active mode, and what it
--  toggles follows Default to Collapsed When Shown: with it ON the key rocks
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
--    "one"     -- the default. Both content groups in the Group & Pull shell,
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
--  One Window Scale (p.scale) covers every form: both shells and the
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
        EllesmereUI.MakeBorder(f, BRD_R, BRD_G, BRD_B, BRD_A, EllesmereUI.PP)
        return
    end
    local ov = CreateFrame("Frame", nil, f)
    ov:SetAllPoints(f)
    ov:SetFrameLevel(f:GetFrameLevel() + 6)
    local tex = ov:CreateTexture(nil, "OVERLAY", nil, 7)
    tex:SetAtlas(BORDER_ATLAS)
    tex:SetAllPoints(ov)
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

local SECTION_KEYS = {}
local SECTION_LABEL = {}
for _, def in ipairs(SECTIONS) do
    SECTION_KEYS[#SECTION_KEYS + 1] = def.key
    SECTION_LABEL[def.key] = def.label
end

local db
local applyPending             -- true when combat blocked an Apply()
local previewOn = false        -- Raid Tools settings page is in front (see ApplyVisibility)
local toggleButton             -- keybind target; also the out-of-combat path
local sections = {}            -- key -> shell frame
local shellTitle = {}          -- key -> title fontstring
local groupHolder, markersHolder   -- plain content holders (see header)
local iconBtn                  -- collapsed-state square
local GROUP_CONTENT_H, MARKERS_CONTENT_H   -- computed at build
local Apply                    -- forward: the event handler closes over it

-- ONE representation of each secure decision, run from both paths.
--
-- The keybind clicks the button, which is the only thing that works during
-- combat. Out of combat the same snippet is run through SecureHandlerExecute
-- instead of being re-implemented in Lua. EllesmereUIRaidFrames.lua does
-- exactly this, for exactly this reason: the driver manager only fires the
-- attribute handlers on value CHANGES, so a reapply with unchanged states
-- would otherwise never run.
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

-- Every fontstring is registered on the OUR-frame that owns it (`_fonts`),
-- and ApplyFonts walks the small fixed owner list -- no module-level registry
-- to keep in sync with frame lifetime. MakeFont (like every options-panel
-- helper) hardcodes the options-panel font; on-screen text has to resolve
-- through GetFontPath instead, or these panels would be the only ones in the
-- suite ignoring the Global Font setting.
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
local pullButtons = {}         -- fixed set of 3; durations are re-labelled live
local convertButton

-- Both marker rows draw Blizzard's own raid target sheet -- the texture the
-- rest of the suite already uses for markers, in nameplates and raid frames.
local MARKER_SHEET = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"

-- The sheet's SYMBOL order (1 Star, 2 Circle, 3 Diamond, 4 Triangle, 5 Moon,
-- 6 Square, 7 Cross, 8 Skull) is NOT the WORLD marker ID order (1 Blue,
-- 2 Green, 3 Purple, 4 Red, 5 Yellow, 6 Orange, 7 Silver, 8 White). Each
-- flare carries its symbol, so the button shows the symbol and this maps it
-- to the flare that actually wears it -- without it, clicking Star (symbol 1)
-- dropped the BLUE flare (world ID 1).
local SYMBOL_TO_WORLD = { 5, 6, 3, 2, 7, 1, 4, 8 }

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
        -- "one" | "two" | "group" | "markers" (see header). The single owner
        -- of window composition; there are no per-panel enable toggles.
        showAs        = "one",
        -- One scale for the whole feature: whichever windows the Show as
        -- choice puts on screen (and the collapsed icon) all wear it.
        scale         = 1,
        -- Three slots is a LAYOUT choice (they fill one row beside Stop), not
        -- a security constraint -- the pull buttons are plain, only the marker
        -- buttons are secure. Growing the count later means growing the panel,
        -- nothing more.
        pullTimes     = { PULL_DEFAULTS[1], PULL_DEFAULTS[2], PULL_DEFAULTS[3] },
        -- Per-section: pos[key] = { point, relPoint, x, y }
        pos           = {},
    },
  },
}

-- Our slice of the shared QoL profile, re-derived on every read -- the same
-- accessor BattleRes and MovementAlert use. Deliberately NOT cached: a profile
-- switch replaces the whole profile table, and a cached pointer would leave
-- the event handler, the slash command and the unlock callbacks writing into
-- an orphaned table.
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

-- The Show as choice, normalized: any unset/unknown value reads as "one".
local function ShowAs()
    local p = P()
    local v = p and p.showAs
    if v ~= "two" and v ~= "group" and v ~= "markers" then v = "one" end
    return v
end
ns.ShowAs = ShowAs

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
    b:SetSize(MARKER_SZ, MARKER_SZ)
    -- One phase only: the "!" prefix toggles the marker, so firing on both the
    -- down and the up would set it and immediately clear it again.
    b:RegisterForClicks("AnyDown")

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    b.icon = icon

    if kind == "target" then
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
    b:SetScript("OnEnter", function(self)
        if (self._baseAlpha or 0.8) >= 0.8 then self.icon:SetAlpha(1) end
    end)
    b:SetScript("OnLeave", function(self)
        self.icon:SetAlpha(self._baseAlpha or 0.8)
    end)

    markerButtons[#markerButtons + 1] = b
    return b
end

-------------------------------------------------------------------------------
--  Permission gating
-------------------------------------------------------------------------------

-- Ready check, role check, countdown and markers all require lead or assist.
--
-- Solo counts as permitted. You are the only member, so nothing is being taken
-- from anyone, and the game already no-ops whatever does not apply outside a
-- group -- gating it ourselves would only make the panels dead on a target
-- dummy for no reason.
local function HasAssist()
    if not IsInGroup() then return true end
    return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

local function IsLeader()
    if not IsInGroup() then return true end
    return UnitIsGroupLeader("player")
end

-- Durations are the only pull-timer setting that can change at runtime: the
-- button count is fixed at build, so re-labelling is all it takes.
local function RefreshPullTimes()
    local times = (P() and P().pullTimes) or {}
    for i, b in ipairs(pullButtons) do
        local secs = times[i] or PULL_DEFAULTS[i]
        b.secs = secs
        b._lbl:SetText(tostring(secs))
    end
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
        if b.needsLeader then SetButtonEnabled(b, leader) else SetButtonEnabled(b, assist) end
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
    -- A driver transition is a context change: it reclaims control from any
    -- manual override and re-seeds the collapsed/expanded form. The icon has
    -- no state template of its own (click templates do not dispatch _onstate),
    -- so each shell fans the verdict out to it -- both shells stamping the
    -- same values is idempotent.
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

-- Group & Pull content, in its own plain holder so one-window mode can treat
-- it uniformly with the markers holder.
local function BuildGroupContent()
    groupHolder = CreateFrame("Frame", nil, sections.Group)
    groupHolder:SetWidth(PANEL_W)
    fontOwners[#fontOwners + 1] = groupHolder
    local f = groupHolder
    local y = 0

    -- MakeGroupButton runs labels through L itself.
    local half = (PANEL_W - PAD * 2 - ROW_GAP) / 2
    local ready = MakeGroupButton(f, "Ready Check", half, function() DoReadyCheck() end)
    ready:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)

    local role = MakeGroupButton(f, "Role Check", half, function() InitiateRolePoll() end)
    role:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + half + ROW_GAP, y)
    y = y - ROW_H - ROW_GAP

    convertButton = MakeGroupButton(f, "Convert to Raid", half, function()
        if IsInRaid() then C_PartyInfo.ConvertToParty() else C_PartyInfo.ConvertToRaid() end
    end, true)
    convertButton:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)

    local disband = MakeGroupButton(f, "Disband", half, function()
        ConfirmDisband()
    end, true)
    disband:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + half + ROW_GAP, y)
    y = y - ROW_H - ROW_GAP

    -- Pull timer row: three durations + Stop, sharing the holder's width.
    local w = (PANEL_W - PAD * 2 - PULL_SLOTS * ROW_GAP) / (PULL_SLOTS + 1)
    for i = 1, PULL_SLOTS do
        -- The pull duration lives on the button and changes at runtime, so
        -- the click reads it through the closure.
        local b
        b = MakeGroupButton(f, "", w, function() StartPull(b.secs) end)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + (w + ROW_GAP) * (i - 1), y)
        pullButtons[i] = b
    end
    local cancel = MakeGroupButton(f, "Stop", w, StopPull)
    cancel:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + (w + ROW_GAP) * PULL_SLOTS, y)
    y = y - ROW_H

    GROUP_CONTENT_H = -y
    f:SetHeight(GROUP_CONTENT_H)
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
    -- anchoring to a hidden frame is fine, the anchor resolves through its
    -- points.
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

-- Show-as arrangement. OOC only (Apply gates); the holders are plain frames,
-- so the re-parent is an ordinary SetParent.
local function ApplyLayout()
    local p = P()
    local showAs = ShowAs()
    local winGroup, winMarkers = sections.Group, sections.Markers

    local collapseUI = p and p.collapsedIcon ~= false
    winGroup._collapseBtn:SetShown(collapseUI)
    -- Two Windows: only Group & Pull carries the collapse control -- one
    -- button folds the whole feature, and a second on Markers would just be
    -- a duplicate. Markers keeps its own ONLY when it is the lone window.
    winMarkers._collapseBtn:SetShown(collapseUI and showAs ~= "two")

    if showAs == "one" then
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

    -- The collapsed icon rides the shell the mode actually shows: Markers-only
    -- anchors (and scales, see Apply) to the Markers shell, everything else to
    -- Group & Pull.
    iconBtn:ClearAllPoints()
    iconBtn:SetPoint("TOPLEFT",
        (showAs == "markers") and winMarkers or winGroup, "TOPLEFT", 0, 0)

    -- Heights just moved: re-crop the backdrop art so it covers instead of
    -- stretches (the skins hook SetHeight for this; our heights only ever
    -- change right here, so a direct call is the whole hook).
    if winGroup._bgFit then winGroup._bgFit() end
    if winMarkers._bgFit then winMarkers._bgFit() end
end

-- Positions round-trip through unlock mode's CENTER/CENTER convention.
--
-- That pairing is not decoration: for an odd-height frame the stored centre
-- ends in .5, and ApplyCenterPosition subtracts the live half-height so the
-- edges land back on whole pixels. Applying the stored value with a plain
-- SetPoint skips that and leaves the frame a pixel off -- visible only after
-- the snap tool, because a normal drag is converted on the way in and a
-- snapped one is not.
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

local function ApplySectionPosition(key)
    local f = sections[key]
    if not f then return end
    if InCombatLockdown() then applyPending = true; return end

    local pos = ((P() and P().pos) or {})[key] or DefaultPos(key)
    if EllesmereUI.ApplyCenterPosition
       and pos.point == "CENTER" and pos.relPoint == "CENTER" then
        -- Skips anchor-linked elements itself, and defers its own combat case
        -- for protected frames. FALSE means it could not resolve a live frame
        -- for this key -- fall through to the plain path, exactly as unlock
        -- mode's own caller does.
        if EllesmereUI.ApplyCenterPosition(UNLOCK_KEY .. key, pos) then return end
    end

    -- Anything not in that convention is a default or a pre-conversion value.
    if EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored(UNLOCK_KEY .. key) then
        return
    end
    f:ClearAllPoints()
    f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
end

local function ApplyPositions()
    -- While an unlock session is open UNLOCK MODE owns these frames: it moves
    -- them live and only writes the result on Save & Exit. A settings pass
    -- landing mid-session (the options panel hiding/showing flips the preview,
    -- and a combat-deferred Apply completes on PLAYER_REGEN_ENABLED) would drag
    -- the window back to the last SAVED spot -- and because Save & Exit derives
    -- the value it stores from the frame's LIVE bounds, the drag is then
    -- written back as the old position and lost for good. Same guard Action
    -- Bars, Aura Reminders and the Cooldown Manager already carry.
    if EllesmereUI._unlockActive then return end

    -- Each shell is positioned only when the Show as choice can put it on
    -- screen; One Window and Only Group & Pull ride pos.Group, Only Markers
    -- rides pos.Markers.
    local showAs = ShowAs()
    if showAs ~= "markers" then ApplySectionPosition("Group") end
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
    local showAs = ShowAs()
    local shellOn = {
        Group   = showAs ~= "markers",
        Markers = showAs == "two" or showAs == "markers",
    }
    -- One seed for every show (see header): Default to Collapsed When Shown.
    -- With the toggle off the seed is "expanded" and the icon never shows.
    local startExpanded = not (p and p.collapsedIcon ~= false)

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
    -- something, so it is simply on while the mode is active.
    iconBtn:SetAttribute("enabled", true)
    iconBtn:SetAttribute("visible", visNow)
    iconBtn:SetAttribute("override", "")
    iconBtn:SetAttribute("startexpanded", startExpanded)
    iconBtn:SetAttribute("expanded", expandedNow)

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
-- Toggle Action Bar Visibility. Pressing the bound key is a hardware click,
-- so the toggle itself works IN combat; only (re)binding defers.
local function ApplyToggleKeybind()
    if not toggleButton then return end
    ClearOverrideBindings(toggleButton)
    local p = P()
    local k = p and p.toggleKey
    if k and k ~= "" and Mode() ~= "never" then
        SetOverrideBindingClick(toggleButton, false, k, "EllesmereUIRaidToolsToggle")
    end
end

-------------------------------------------------------------------------------
--  Lifecycle
--
--  Nothing exists until the mode first leaves "never": no frames, no events,
--  no bindings, no unlock rows. Apply() is the single entry point.
-------------------------------------------------------------------------------

-- Events live only while the feature is active (or while a combat-deferred
-- Apply is pending, since PLAYER_REGEN_ENABLED is what completes it). The
-- frame itself is created on first need and reused.
local ev
local function EnsureEvents()
    if not ev then
        ev = CreateFrame("Frame")
        ev:SetScript("OnEvent", function(_, event)
            -- Pending work FIRST, before the mode gate: a switch TO "never"
            -- deferred by combat must complete even though the profile
            -- already reads never -- swallowing it here is how panels get
            -- stranded on screen.
            if event == "PLAYER_REGEN_ENABLED" and applyPending then
                Apply()
                return
            end
            if Mode() == "never" then return end
            RefreshPermissions()
        end)
    end
    ev:RegisterEvent("GROUP_ROSTER_UPDATE")
    ev:RegisterEvent("PARTY_LEADER_CHANGED")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
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
        elements[#elements + 1] = MK({
            key      = UNLOCK_KEY .. key,
            label    = SECTION_LABEL[key],
            group    = "Raid Tools",
            order    = 540 + i,
            noResize = true,
            getFrame = function()
                if Mode() == "never" then return nil end
                -- Offer exactly the shells the Show as choice puts on screen:
                -- One Window / Only Group & Pull = the Group element alone,
                -- Two Windows = both, Only Markers = the Markers element alone.
                local showAs = ShowAs()
                if key == "Group" and showAs == "markers" then return nil end
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
                        EllesmereUI.ConvertToCenterPos(UNLOCK_KEY .. key, point, relPoint, x, y)
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
            applyPos = function() ApplySectionPosition(key) end,
        })
    end
    if #elements > 0 then
        EllesmereUI:RegisterUnlockElements(elements, "EllesmereUIQoL")
    end
end

-- Options-page entry point, and the completion target for combat-deferred
-- work. Every path below writes secure attributes, drivers, bindings or
-- geometry on protected frames -- ALL blocked in lockdown, the switch to
-- "never" included (SetAttribute is as protected as Hide). So in combat the
-- whole request is parked behind applyPending, with the REGEN listener
-- guaranteed alive to finish it.
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
    RefreshPullTimes()
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
