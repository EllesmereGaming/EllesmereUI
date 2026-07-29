-------------------------------------------------------------------------------
--  EllesmereUIQoL_RaidTools.lua  —  Raid control panels (QoL: Raid Tools page)
--
--  Each category is its OWN top-level window with its own saved position, so
--  the pieces can go where each is actually used -- target markers under the
--  raid frames, the rest along a screen edge. They are laid out stacked by
--  default, which reads as one panel until you move something; unlock mode's
--  anchor-linking drags several as a unit.
--
--  COMBAT MODEL -- read this before changing anything here.
--
--  Raid markers have to be placeable mid-pull, so every marker button is a
--  SecureActionButtonTemplate built once at load and never re-anchored,
--  re-parented or resized afterwards. Two consequences shape the whole file:
--
--    * Section visibility runs through a secure snippet ("apply") driven by a
--      state driver -- NOT by Lua Show/Hide. Hiding a frame that owns
--      protected children is blocked in combat, which is exactly when a raid
--      leader needs the markers.
--    * Anything that moves or resizes a section is deferred out of combat.
--
--  Every section carries two independent visibility inputs: the state driver
--  compiled from the suite's shared visibility set (EllesmereUI_Visibility.lua
--  -- combat, group and skyriding axes, the same grammar Action Bars and Unit
--  Frames use) and the user's manual toggle. "apply" ORs them, so the keybind
--  still hides what the driver put up, and shows what it left down. The toggle
--  drives all sections together -- they are one tool, not four.
--
--  Marker buttons are never disabled when the player lacks assist: disabling a
--  protected button in combat is its own can of worms, and the game already
--  no-ops the marker call. They are dimmed instead -- purely cosmetic. The
--  plain (non-secure) group buttons are enable-gated normally.
-------------------------------------------------------------------------------
local _, ns = ...

local InCombatLockdown = InCombatLockdown
local UnitIsGroupLeader, UnitIsGroupAssistant = UnitIsGroupLeader, UnitIsGroupAssistant
local IsInRaid, IsInGroup = IsInRaid, IsInGroup
local SetRaidTargetIconTexture = SetRaidTargetIconTexture

-- Layout constants. Sections are fixed-size: a secure child cannot be resized
-- in combat, so geometry is decided once and only scale is user-facing. One
-- shared width keeps them aligned while stacked.
local PANEL_W     = 236
local PAD         = 10
local TITLE_H     = 18
local ROW_H       = 22
local ROW_GAP     = 4
local MARKER_SZ   = 24
local PULL_SLOTS  = 3
local PULL_DEFAULTS = { 3, 5, 10 }   -- also seeded into DB_DEFAULTS below
ns.PULL_DEFAULTS = PULL_DEFAULTS

-- Canonical section list. Build order, stack order, DB key set, window titles,
-- unlock-mover labels and the options rows all derive from this one table, so
-- adding or renaming a panel is a single edit plus a builder in BuildAll.
--
-- `label` reaches EllesmereUI.L as a variable, which the static key extractor
-- cannot see -- the documented arrangement for exactly this case (see the
-- header of .tools/extract-locale-keys.sh); the in-game /euiloc harvester picks
-- them up, the same way every widget label in the suite is already handled.
local SECTIONS = {
    { key = "Group",         label = "Group",
      tip = "Ready check, role check, convert and disband." },
    { key = "Pull",          label = "Pull Timer",
      tip = "Hands the countdown to your boss mod, then runs Blizzard's own." },
    { key = "TargetMarkers", label = "Target Markers",
      tip = "The eight raid symbols, placed on your target." },
    { key = "WorldMarkers",  label = "World Markers",
      tip = "The eight coloured ground flares." },
}
ns.SECTIONS = SECTIONS

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
local toggleButton             -- keybind target; also the out-of-combat path
local sections = {}            -- key -> frame

-- ONE representation of each secure decision, run from both paths.
--
-- The keybind clicks the button, which is the only thing that works during
-- combat. Out of combat the same snippet is run through SecureHandlerExecute
-- instead of being re-implemented in Lua. EllesmereUIRaidFrames.lua:6985 does
-- exactly this, for exactly this reason: the driver manager only fires the
-- attribute handlers on value CHANGES, so a reapply with unchanged states
-- would otherwise never run.
local RUN_APPLY = [[ self:RunAttribute("apply") ]]
local TOGGLE_SNIPPET = [[
    local n = self:GetAttribute("count") or 0
    local first = self:GetFrameRef("s1")
    if not first then return end
    local newval = not first:GetAttribute("manual")
    for i = 1, n do
        local f = self:GetFrameRef("s" .. i)
        if f then
            f:SetAttribute("manual", newval)
            f:RunAttribute("apply")
        end
    end
]]
-- Every fontstring we draw, so the user's font can be re-applied on demand.
-- MakeFont (and MakeStyledButton's label) hardcode the options-panel font;
-- on-screen text has to resolve through GetFontPath instead, or these panels
-- would be the only ones in the suite ignoring the Global Font setting.
local FONT_KEY = "extras"      -- QoL's key in EllesmereUI._addonKeyToFolder
local fontStrings = {}
local function TrackFont(fs, size)
    fontStrings[#fontStrings + 1] = { fs = fs, size = size }
    return fs
end
local function ApplyFonts()
    local path = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath(FONT_KEY)
    if not path then return end
    for _, e in ipairs(fontStrings) do
        local _, _, flags = e.fs:GetFont()
        e.fs:SetFont(path, e.size, flags or "")
    end
end

local groupButtons = {}        -- plain buttons, enable-gated on assist
local markerButtons = {}       -- secure buttons, dimmed on assist
local pullButtons = {}         -- fixed set of 3; durations are re-labelled live
local convertButton

-- Both marker rows draw Blizzard's own raid target sheet -- the texture the
-- rest of the suite already uses for markers, in nameplates and raid frames.
-- Marker N is the same symbol whether it lands on a unit or on the ground, so
-- there is nothing to tell apart by colour: the two rows are separate windows
-- carrying their own titles.
local MARKER_SHEET = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"

-- One slice of the shared EllesmereUIQoLDB profile, the same arrangement
-- BattleRes and Bloodlust use: each QoL feature merges its own defaults into
-- the SAME profile table under its own key.
local DB_DEFAULTS = {
  profile = {
    raidTools = {
        enabled       = false,
        -- Per-panel, so each can be sized for where it sits: markers small in a
        -- corner, group buttons large under the raid frames.
        scales        = { Group = 1, Pull = 1, TargetMarkers = 1, WorldMarkers = 1 },
        -- The suite's shared multi-select visibility set (EllesmereUI_Visibility
        -- .lua): same grammar, same axes and the same compiler Action Bars and
        -- Unit Frames drive their secure state drivers with.
        visibilityModes = { in_raid = true },
        -- Exactly three, always. The count is baked into the layout: changing
        -- it would mean rebuilding secure siblings, so only the durations are
        -- user-facing.
        pullTimes     = { PULL_DEFAULTS[1], PULL_DEFAULTS[2], PULL_DEFAULTS[3] },
        -- Per-section: pos[key] = { point, relPoint, x, y }
        pos           = {},
        -- Which panels exist at all. Sub-parts of an already-opt-in module, so
        -- they all start on; unchecking one removes it entirely.
        sections      = { Group = true, Pull = true, TargetMarkers = true, WorldMarkers = true },
    },
  },
}

-- Our slice of the shared QoL profile, re-derived on every read -- the same
-- accessor BattleRes and MovementAlert use. Deliberately NOT cached: a profile
-- switch replaces the whole profile table, and a cached pointer would leave
-- the event handler, the slash command and the five unlock callbacks writing
-- into an orphaned table.
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

-- Default on, so a profile written before this option existed keeps all four.
local function SectionEnabled(key)
    local s = P() and P().sections
    return s == nil or s[key] ~= false
end
ns.SectionEnabled = SectionEnabled

local function SectionScale(key)
    local s = P() and P().scales
    return (s and s[key]) or 1
end
ns.SectionScale = SectionScale

-------------------------------------------------------------------------------
--  Suite-styled widgets
--
--  Everything visual goes through the suite's own primitives -- MakeStyledButton,
--  MakeBorder, GetFontPath, GetAccentColor -- so the panels inherit the user's
--  font and accent colour instead of looking like stock Blizzard UI.
-------------------------------------------------------------------------------

-- Enable state without touching the button's own scripts: MakeStyledButton owns
-- OnEnter/OnLeave, so dimming the whole frame and cutting mouse input is both
-- simpler and immune to a hover re-lighting a disabled control.
local function SetButtonEnabled(b, on)
    b:SetAlpha(on and 1 or 0.35)
    b:EnableMouse(on)
end

-- Action button in the suite style. `needsLeader` narrows the gate from assist
-- to leader. Text is passed raw: MakeStyledButton localizes it itself.
local function MakeGroupButton(parent, text, width, onClick, needsLeader)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, ROW_H)
    local _, _, lbl = EllesmereUI.MakeStyledButton(b, text, 11,
        EllesmereUI.RB_COLOURS, onClick)
    b._lbl = TrackFont(lbl, 11)
    b.needsLeader = needsLeader
    groupButtons[#groupButtons + 1] = b
    return b
end

-- Secure marker button. Attributes are set here, at load, and never touched
-- again -- that is what makes them usable in combat.
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
        b:SetAttribute("marker", tostring(index))
        b:SetAttribute("action1", "set")
        b:SetAttribute("action2", "clear")
    end

    if index == 0 then
        icon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    else
        icon:SetTexture(MARKER_SHEET)
        SetRaidTargetIconTexture(icon, index)
    end

    -- Accent-lit hover, matching the suite's other icon grids. Adding scripts
    -- to a secure button is fine; only its attributes are combat-sensitive.
    local brd = EllesmereUI.MakeBorder(b, 1, 1, 1, 0.12, EllesmereUI.PP)
    local ar, ag, ab = EllesmereUI.GetAccentColor()
    b:SetScript("OnEnter", function() brd:SetColor(ar, ag, ab, 0.9) end)
    b:SetScript("OnLeave", function() brd:SetColor(1, 1, 1, 0.12) end)

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
-- button count is fixed, so re-labelling is all it takes.
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

    -- Secure buttons: cosmetic only, never Enable/Disable (see header). Alpha
    -- alone, since desaturating a vertex-tinted disc would do nothing.
    for _, b in ipairs(markerButtons) do
        b.icon:SetAlpha(assist and 1 or 0.4)
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
--  Section frames (built once, at load -- secure children forbid rebuilding)
-------------------------------------------------------------------------------

-- One secure, independently positioned window. Returns the frame and the y at
-- which its content starts.
local function MakeSection(key)
    local f = CreateFrame("Frame", "EllesmereUIRaidTools" .. key, UIParent,
                          "SecureHandlerStateTemplate")
    f:SetWidth(PANEL_W)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:Hide()

    -- Same flat dark surface + 1px border the suite's own panels use.
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.067, 0.067, 0.067, 0.95)
    EllesmereUI.MakeBorder(f, 1, 1, 1, EllesmereUI.DD_BRD_A, EllesmereUI.PP)

    -- Visibility: the ONLY place a section is shown or hidden. Both inputs are
    -- plain attributes so the snippet stays trivially auditable.
    f:SetAttribute("manual", false)
    f:SetAttribute("visible", false)
    f:SetAttribute("autoshow", false)  -- ApplyVisibility owns this
    f:SetAttribute("enabled", true)
    f:SetAttribute("apply", [[
        -- An unchecked panel never shows, whatever the driver or the toggle say.
        if not self:GetAttribute("enabled") then
            self:Hide()
            return
        end
        local auto = self:GetAttribute("autoshow") and self:GetAttribute("visible")
        if auto or self:GetAttribute("manual") then
            self:Show()
        else
            self:Hide()
        end
    ]])
    f:SetAttribute("_onstate-euirt_vis", [[
        self:SetAttribute("visible", newstate == "show")
        self:RunAttribute("apply")
    ]])

    local ar, ag, ab = EllesmereUI.GetAccentColor()
    local fs = TrackFont(EllesmereUI.MakeFont(f, 12, nil, ar, ag, ab), 12)
    fs:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -PAD)
    fs:SetText(EllesmereUI.L(SECTION_LABEL[key]))

    sections[key] = f
    return f, -PAD - TITLE_H
end

local function BuildGroupSection()
    local f, y = MakeSection("Group")

    -- Button labels are passed raw: MakeStyledButton runs them through L itself.
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

    f:SetHeight(-(y - ROW_H) + PAD)
end

local function BuildPullSection()
    local f, y = MakeSection("Pull")

    local w = (PANEL_W - PAD * 2 - PULL_SLOTS * ROW_GAP) / (PULL_SLOTS + 1)
    for i = 1, PULL_SLOTS do
        -- MakeStyledButton's OnClick takes no arguments, so the button is
        -- reached through the closure rather than through self.
        local b
        b = MakeGroupButton(f, "", w, function() StartPull(b.secs) end)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + (w + ROW_GAP) * (i - 1), y)
        pullButtons[i] = b
    end
    local cancel = MakeGroupButton(f, "Stop", w, StopPull)
    cancel:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + (w + ROW_GAP) * PULL_SLOTS, y)

    f:SetHeight(-(y - ROW_H) + PAD)
end

local function BuildMarkerSection(key, kind)
    local f, y = MakeSection(key)

    -- 8 markers + a clear button, evenly spread across the shared width.
    local step = (PANEL_W - PAD * 2 - MARKER_SZ) / 8
    for i = 0, 8 do
        local b = MakeMarkerButton(f, i == 8 and 0 or (i + 1), kind)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + step * i, y)
    end

    f:SetHeight(-(y - MARKER_SZ) + PAD)
end

-- Stacked defaults: the sections read as one panel until the user moves one.
-- Unchecked panels are skipped so the default stack stays tight instead of
-- leaving a hole. Sections the user has already placed keep their saved pos.
local function DefaultPos(key)
    local top = 160
    for _, k in ipairs(SECTION_KEYS) do
        if k == key then break end
        if SectionEnabled(k) then
            top = top - (sections[k]:GetHeight() * SectionScale(k) + ROW_GAP)
        end
    end
    -- The running total above is in screen space, but SetPoint offsets live in
    -- the frame's OWN scaled units -- so divide back out, or a rescaled panel
    -- lands somewhere else entirely.
    local s = SectionScale(key)
    return { point = "TOP", relPoint = "CENTER", x = 300 / s, y = top / s }
end

local function BuildAll()
    if sections.Group then return end
    BuildGroupSection()
    BuildPullSection()
    BuildMarkerSection("TargetMarkers", "target")
    BuildMarkerSection("WorldMarkers",  "world")

    -- Keybind target. Shown (a hidden button cannot take a CLICK binding) but
    -- 1px, transparent and parked off-screen. It flips every section together
    -- from one computed value, so they can never drift apart.
    toggleButton = CreateFrame("Button", "EllesmereUIRaidToolsToggle", UIParent,
                               "SecureHandlerClickTemplate")
    toggleButton:SetSize(1, 1)
    toggleButton:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -100, -100)
    toggleButton:SetAlpha(0)
    toggleButton:RegisterForClicks("AnyDown")
    for i, key in ipairs(SECTION_KEYS) do
        toggleButton:SetFrameRef("s" .. i, sections[key])
    end
    toggleButton:SetAttribute("count", #SECTION_KEYS)
    toggleButton:SetAttribute("_onclick", TOGGLE_SNIPPET)
end

-------------------------------------------------------------------------------
--  Position / state driver
-------------------------------------------------------------------------------

-- Positions round-trip through unlock mode's CENTER/CENTER convention.
--
-- That pairing is not decoration: for an odd-height frame the stored centre
-- ends in .5, and ApplyCenterPosition subtracts the live half-height so the
-- edges land back on whole pixels. Applying the stored value with a plain
-- SetPoint skips that and leaves the frame a pixel off -- visible only after
-- the snap tool, because a normal drag is converted on the way in and a
-- snapped one is not.
local function ApplySectionPosition(key)
    local f = sections[key]
    if not f then return end
    if InCombatLockdown() then applyPending = true; return end

    local pos = ((P() and P().pos) or {})[key] or DefaultPos(key)
    if EllesmereUI.ApplyCenterPosition
       and pos.point == "CENTER" and pos.relPoint == "CENTER" then
        -- Also skips anchor-linked elements itself, and defers its own combat
        -- case for protected frames.
        EllesmereUI.ApplyCenterPosition(UNLOCK_KEY .. key, pos)
        return
    end

    -- Anything not in that convention is a default or a pre-conversion value.
    if EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored(UNLOCK_KEY .. key) then
        return
    end
    f:ClearAllPoints()
    f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
end

local function ApplyPositions()
    for _, key in ipairs(SECTION_KEYS) do ApplySectionPosition(key) end
end

-- Visibility is the suite's shared multi-select set, not a local rule. The two
-- forms this module needs both come from EllesmereUI_Visibility.lua:
--
--   BuildVisibilityDriverString -> the macro conditional compiled for the
--       secure state driver (the only form that works during combat). Same
--       compiler Action Bars and Unit Frames drive their drivers with.
--   EvalVisibilityModes         -> the same set evaluated right now, needed
--       because re-registering a driver does NOT re-fire _onstate when the
--       recomputed state equals the stored one, so after a settings change the
--       snippet may never run and something has to decide.
--
--       The module-facing EvalVisibilityExtended is deliberately NOT used: it
--       returns nil for a single checked item, which the engine stores in the
--       legacy scalar rather than in visibilityModes -- the most common case
--       here. ResolveVisModes below turns that scalar back into a set, then
--       the axis kernel evaluates it.
--
-- partyIncludesRaid=false keeps In Party and In Raid Group disjoint (the suite
-- default, shared by every secure-driver module). noMouseover drops the hover
-- item from the list: hover reveal needs the Lua poll the insecure modules run,
-- and offering a checkbox that does nothing is worse than not offering it.
-- Skyriding is NOT flagged luaDragonriding -- our driver compiles it, so the
-- items must not be locked behind the Lua gliding-event gate.
local VIS_CAPS = { partyIncludesRaid = false, noMouseover = true }
local VIS_KEY  = "visibility"
-- Exported so the options row renders exactly the caps the driver compiles;
-- two literals in two files is how the checklist ends up offering items the
-- driver silently ignores.
ns.VIS_CAPS = VIS_CAPS
ns.VIS_KEY  = VIS_KEY

-- The engine stores a SINGLE checked item in the legacy scalar instead of in
-- visibilityModes ("one checked item behaves exactly like the legacy single
-- mode"), so GetActiveVisibilityModes returns nil for it -- and for Always and
-- Never alike. Resolving that scalar is deliberately left to each module.
-- Returns a modes table (empty = unconditional show) or nil for "no driver".
local function ResolveVisModes()
    local p = P()
    if not p then return nil end
    local vm = EllesmereUI.GetActiveVisibilityModes(p, VIS_KEY)
    if vm then return vm end
    local scalar = p[VIS_KEY]
    -- An empty set has no constraint on any axis, which the compiler turns
    -- into a bare "show" -- exactly what Always means.
    if scalar == "always" then return {} end
    if scalar and EllesmereUI.VIS_CONDITION_KEYS[scalar] then return { [scalar] = true } end
    return nil  -- "never", unset, or a mode this module cannot express
end

-- Reached only from Apply, which has already returned if we are in combat.
local function ApplyVisibility()

    local vm = ResolveVisModes()
    local driver = vm and EllesmereUI.BuildVisibilityDriverString("", vm) or nil
    local autoNow = false
    if vm then
        local inRaid = IsInRaid()
        autoNow = EllesmereUI.EvalVisibilityModes(vm, {
            inCombat = InCombatLockdown(),
            inRaid   = inRaid,
            inParty  = IsInGroup() and not inRaid,
        }, VIS_CAPS) ~= false
    end

    for _, key in ipairs(SECTION_KEYS) do
        local f = sections[key]
        local on = SectionEnabled(key)

        f:SetAttribute("enabled", on)
        f:SetAttribute("autoshow", driver ~= nil)
        f:SetAttribute("visible", autoNow)

        UnregisterStateDriver(f, "euirt_vis")
        if on and driver then
            RegisterStateDriver(f, "euirt_vis", driver)
        end

        -- Run the snippet rather than re-deciding in Lua: re-registering the
        -- driver does not re-fire _onstate when the state is unchanged, which
        -- is exactly the case when a panel is re-checked without the context
        -- having moved. Attributes are set first so "apply" sees them.
        if SecureHandlerExecute then
            SecureHandlerExecute(f, RUN_APPLY)
        end
    end
end

-- Options-page entry point. Geometry and driver changes are combat-deferred;
-- the options page cannot be open in combat anyway, but a profile switch can.
local function Apply()
    local p = P()
    if not p or not p.enabled then
        if sections.Group and not InCombatLockdown() then
            for _, key in ipairs(SECTION_KEYS) do
                local f = sections[key]
                UnregisterStateDriver(f, "euirt_vis")
                f:SetAttribute("autoshow", false)
                f:SetAttribute("manual", false)
                f:Hide()
            end
        end
        return
    end
    if InCombatLockdown() then
        -- Combat blocks every geometry and driver call below; remember that so
        -- PLAYER_REGEN_ENABLED knows there is real work waiting instead of
        -- redoing the whole startup path after every trash pack.
        applyPending = true
        return
    end
    applyPending = false

    BuildAll()
    for _, key in ipairs(SECTION_KEYS) do
        sections[key]:SetScale(SectionScale(key))
    end
    ApplyPositions()
    ApplyVisibility()
    ApplyFonts()
    RefreshPullTimes()
    RefreshPermissions(true)
end
_G._EUI_RaidTools_Apply = Apply

-------------------------------------------------------------------------------
--  Slash command
-------------------------------------------------------------------------------

-- Out of combat nothing is protected, so the sections are driven straight from
-- Lua. This deliberately does NOT go through toggleButton:Click(): that button
-- is registered for "AnyDown" only, and a bare Click() simulates an up event,
-- so the handler would never fire. The keybind keeps the secure path because a
-- hardware click is the only thing that can do this during combat.
local function ToggleOutOfCombat()
    if toggleButton and SecureHandlerExecute then
        SecureHandlerExecute(toggleButton, TOGGLE_SNIPPET)
    end
end

SLASH_EUIRAIDTOOLS1 = "/euiraid"
SlashCmdList["EUIRAIDTOOLS"] = function()
    local p = P()
    if not p or not p.enabled then
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
--  Lifecycle
-------------------------------------------------------------------------------

local function Boot()
    -- Events and unlock registration are unconditional: the feature can be
    -- enabled from the options page mid-session, and requiring a reload for
    -- that would be a poor trade for a few frame registrations.
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("GROUP_ROSTER_UPDATE")
    ev:RegisterEvent("PARTY_LEADER_CHANGED")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:SetScript("OnEvent", function(_, event)
        local p = P()
    if not p or not p.enabled then return end
        if event == "PLAYER_REGEN_ENABLED" and applyPending then
            Apply()
        else
            RefreshPermissions()
        end
    end)

    Apply()

    local MK = EllesmereUI.MakeUnlockElement
    do
        if not MK then return end
        local elements = {}
        for i, key in ipairs(SECTION_KEYS) do
            elements[#elements + 1] = MK({
                key      = UNLOCK_KEY .. key,
                label    = SECTION_LABEL[key],
                group    = "Raid Tools",
                order    = 540 + i,
                noResize = true,
                getFrame = function()
                    -- An unchecked panel is not offered for positioning.
                    local p = P()
                    if not p or not p.enabled or not SectionEnabled(key) then return nil end
                    BuildAll()
                    return sections[key]
                end,
                getSize  = function()
                    local f = sections[key]
                    if f then return f:GetWidth(), f:GetHeight() end
                    return PANEL_W, 60
                end,
                savePos = function(_, point, relPoint, x, y)
                    if not point then return end
                    local p = P(); if not p then return end
                    -- Unlock mode hands us two conventions: a normal drag
                    -- arrives already converted to CENTER/CENTER, a snapped one
                    -- arrives raw. Converting here makes both identical --
                    -- ConvertToCenterPos passes an already-CENTER value through
                    -- untouched, so the drag path is unaffected.
                    if EllesmereUI.ConvertToCenterPos then
                        point, relPoint, x, y =
                            EllesmereUI.ConvertToCenterPos(UNLOCK_KEY .. key, point, relPoint, x, y)
                    end
                    p.pos = p.pos or {}
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
end

-------------------------------------------------------------------------------
--  Init -- same shape as the other QoL features: take the shared QoL DB handle
--  on PLAYER_LOGIN, publish it, then start.
-------------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    if not (EllesmereUI and EllesmereUI.Lite and EllesmereUI.Lite.NewDB) then return end
    db = EllesmereUI.Lite.NewDB("EllesmereUIQoLDB", DB_DEFAULTS, true)
    _G._EUI_RaidTools_DB = function() return db end
    Boot()
end)

_G.BINDING_HEADER_EUI_RAIDTOOLS = "EllesmereUI Raid Tools"
_G["BINDING_NAME_CLICK EllesmereUIRaidToolsToggle:LeftButton"] = "Toggle Raid Tools"
