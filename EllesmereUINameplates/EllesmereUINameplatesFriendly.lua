if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
local addon, ns = ...

if not ns then return end

local GetFont = ns.GetFont
local GetNPUseShadow = ns.GetNPUseShadow
local SetFSFont = ns.SetFSFont
local GetFriendlyHealthBarHeight = ns.GetFriendlyHealthBarHeight
local GetFriendlyHealthBarWidth = ns.GetFriendlyHealthBarWidth

-- Profile alias: reads from the centralized store via ns.db
local function FP()
    return ns.db and ns.db.profile
end

-- Show Health Percent's side of a friendly health bar (friendlyHealthTextPos:
-- "left" or "center"; anything else, unset included, is the right). Shared
-- with the options samples.
local HP_TEXT_SIDE = { left = { "LEFT", 2 }, center = { "CENTER", 0 } }
function ns.NP_PlaceFriendlyHealthText(fs, health, pos)
    local side = HP_TEXT_SIDE[pos]
    fs:ClearAllPoints()
    if side then
        fs:SetPoint(side[1], health, side[1], side[2], 0)
    else
        fs:SetPoint("RIGHT", health, "RIGHT", -2, 0)
    end
end
-- A plate's own text, placed again only when the side changed (a plate keeps
-- the side it was last placed on in _hpSide; false = the right).
local function SyncHealthTextSide(plate)
    local fp = FP()
    local pos = fp and fp.friendlyHealthTextPos or false
    if plate._hpSide == pos then return end
    plate._hpSide = pos
    ns.NP_PlaceFriendlyHealthText(plate.hpText, plate.health, pos)
end

local pairs, ipairs = pairs, ipairs
local UnitHealth, UnitHealthMax = UnitHealth, UnitHealthMax
local UnitName, UnitIsUnit = UnitName, UnitIsUnit
local UnitCanAttack, UnitIsPlayer = UnitCanAttack, UnitIsPlayer
local UnitInParty, UnitInRaid, UnitSelectionColor = UnitInParty, UnitInRaid, UnitSelectionColor
local UnitClass, UnitIsDeadOrGhost = UnitClass, UnitIsDeadOrGhost
local UnitExists, UnitHealthPercent = UnitExists, UnitHealthPercent
local GetRaidTargetIndex, SetRaidTargetIconTexture = GetRaidTargetIndex, SetRaidTargetIconTexture
local C_NamePlate = C_NamePlate
local Enum = Enum

-------------------------------------------------------------------------------
--  State
-------------------------------------------------------------------------------
local friendlyEnabled = false
local friendlyPlates = {}
ns.friendlyPlates = friendlyPlates
local _cachedFriendlyTargetPlate = nil

local FRIENDLY_PLATE_Y_OFFSET = -18

local function IsInFollowerDungeon()
    if C_LFGInfo and C_LFGInfo.IsInLFGFollowerDungeon and C_LFGInfo.IsInLFGFollowerDungeon() then
        return true
    end
    -- Delves (difficultyID 208) also have follower NPCs
    local _, _, difficultyID = GetInstanceInfo()
    if difficultyID == 208 then
        return true
    end
    return false
end

local function IsFriendlyEnabled()
    if IsInFollowerDungeon() then return false end
    local fp = FP()
    if not fp or fp.showFriendlyPlayers == false then return false end
    return not ns.FriendlyNameOnlyNow(fp)
end

local function IsNameOnlyMode()
    if IsInFollowerDungeon() then return false end
    local fp = FP()
    if not fp then return false end
    if fp.showFriendlyPlayers == false then return false end
    return ns.FriendlyNameOnlyNow(fp)
end

local function IsFriendlyNPCEnabled()
    local fp = FP()
    return fp and (fp.showFriendlyNPCs == true)
end

-- Per-unit gate for friendly NPC nameplates. Respects Blizzard's native interactable filter:
-- important NPCs (vendors, quest givers, innkeepers, flight masters) always show;
-- non-interactive flavor NPCs (town guards, ambient citizens) only show when clicked on (targeted)
-- or hovered over (matching default Blizzard behavior).
local function IsFriendlyNPCShownForUnit(unit)
    if not IsFriendlyNPCEnabled() then return false end
    if not unit or not UnitExists(unit) then return false end

    -- WoW Forever names NPCs by force (nameplateForceShowUnitName, its default),
    -- so Blizzard's own frame is the one that knows whether this NPC is named at
    -- all. #3069's fix: without it the friendly NPC plates vanished there.
    if GetCVarBool("nameplateForceShowUnitName") then
        local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
        local uf = nameplate and nameplate.UnitFrame
        if uf and not uf:IsForbidden() then return uf:ShouldShowName() end
    end

    -- If targeted or mouseovered, always show
    if UnitIsUnit(unit, "target") or UnitIsUnit(unit, "mouseover") then
        return true
    end

    -- Respect Blizzard's native interactable filter:
    -- UnitShouldDisplayName returns true for interactable NPCs (vendors, quest givers, innkeepers, etc.)
    -- and false for non-interactable guards / ambient NPCs.
    if UnitShouldDisplayName and not UnitShouldDisplayName(unit) then
        return false
    end

    return true
end

local function ShowNPCTitles()
    local fp = FP()
    return fp and (fp.showNPCTitles ~= false)
end

-- A pet's owner line always shows: Blizzard puts no owner line under a pet, so
-- this is ours to give, and it is the whole point of the pet's subtitle row.

-- The subtitle, the pet test and the group roster the entity colours read live
-- together, in EUI_Nameplates_AlliedColors.lua.
local GetCachedNPCTitle = ns.Allied.GetCachedNPCTitle
local IsPetUnit = ns.Allied.IsPet
local UpdateRecentGroupMembers = ns.Allied.UpdateRecentGroupMembers

-- Friendly NPC color: #00ff00
local NPC_COLOR_R, NPC_COLOR_G, NPC_COLOR_B = 0, 1, 0

-- Bar & name color for full-plate friendly NPCs. User-customizable via the inline
-- swatch on "Show Friendly NPC Nameplates"; defaults to the green NPC_COLOR. Only used
-- in full-plate mode -- name-only NPCs have their own colors in the NPC cog.
local function GetFriendlyNPCColor()
    local fp = FP()
    local c = fp and fp.friendlyNPCColor
    if c then return c.r, c.g, c.b end
    return NPC_COLOR_R, NPC_COLOR_G, NPC_COLOR_B
end

-- User-configurable size for the full-plate friendly name text (players AND
-- NPCs in health-bar mode -- not name-only). Defaults to 12.
local function GetFriendlyNameTextSize()
    local fp = FP()
    return (fp and fp.friendlyNameTextSize) or 12
end

-------------------------------------------------------------------------------
--  Friendly name-only font override
--  When name-only mode is active we replace the system nameplate fonts with
--  our own (Expressway) so Blizzard renders friendly names in our style.
--  Both objects are font families: they change member by member
--  (SetFontObjectFace), so the members for the scripts our font lacks keep
--  Blizzard's Cyrillic, Korean and Chinese faces. Each member's original font
--  is saved once and restored when switching to health-bar mode.
-------------------------------------------------------------------------------
local origNamePlateFont, origNamePlateOutlined
local fontOverrideApplied = false

local function SaveOriginalFonts()
    if not origNamePlateFont then
        origNamePlateFont = EllesmereUI.SnapshotFontObject(SystemFont_NamePlate)
    end
    if not origNamePlateOutlined then
        origNamePlateOutlined = EllesmereUI.SnapshotFontObject(SystemFont_NamePlate_Outlined)
    end
end

-- The outline flags a snapshot read (a family's roman member, or a plain object).
local function SnapFlags(snap)
    local s = snap and (snap.plain or snap.roman)
    return s and s.flags
end

-- User-configurable size for friendly name-only player names. The names render
-- through Blizzard's shared SystemFont_NamePlate object (per-instance SetFont is
-- blocked on name-only plates), so this size is applied to the font object.
local function GetFriendlyNameSize()
    local fp = FP()
    return (fp and fp.friendlyNameSize) or 15
end

-------------------------------------------------------------------------------
--  Subtitle Text (player title / guild name)
--  One shared setting drives both friendly modes. The TITLE is inline with
--  the name (one string via UnitPVPName): full plates set it on their own
--  name FontString, name-only mode writes Blizzard's. The GUILD is a line
--  below: full plates use subText1 (between name and bar), name-only mode a
--  pooled overlay hung under Blizzard's name FontString. Implementations
--  live after the NPC overlay section; this is the shared state plus
--  forward declarations.
-------------------------------------------------------------------------------
-- Name-only mode needs no widgets of its own: the title AND the guild line
-- both ride Blizzard's name FontString (see the composition section below).

-- "none" | "title" | "guild" | "both"
local function GetBelowNameMode()
    local fp = FP()
    return (fp and fp.friendlyBelowName) or "none"
end

-- User-configurable size for the Below Name sub text (one setting shared by
-- both friendly modes). Defaults to 12.
local function GetSubTextSize()
    local fp = FP()
    return (fp and fp.friendlyBelowNameSize) or 12
end

-- One sub text's family, for the line it currently holds: the guild line's size
-- comes from ApplySubtitleFont's bulk pass, and a pooled plate can carry the
-- line in turn -- so the family is set per paint (SetFontFamily is memoized on
-- the FontObject, so a repeat is cheap).
local function SetPlateSubTextFont(fs, size)
    EllesmereUI.SetFontFamily(fs, GetFont(), size, (EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG", false)
end

-- The guild sub texts (full-plate subText1) take one font family for the
-- subtitle font, size and outline (a guild name is other players' writing).
-- Every built sub text is listed once, at its build, so a size / font / slug
-- change re-applies the family to each of them (pooled plates included) and
-- nothing is looked up per plate. The memo is the family's whole key.
local subTexts = {}   -- every built subText1, in build order (pooled plates are never freed)
local _sfFile, _sfSize, _sfFlags
local function ApplySubtitleFont()
    local file = GetFont()
    local size = GetSubTextSize()
    local flags = (EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG"
    if file == _sfFile and size == _sfSize and flags == _sfFlags then return end
    _sfFile, _sfSize, _sfFlags = file, size, flags
    for i = 1, #subTexts do
        EllesmereUI.SetFontFamily(subTexts[i], file, size, flags, false)
    end
end

local _ffFile, _ffSize
local function ApplyFriendlyFontOverride(force)
    SaveOriginalFonts()
    local font = GetFont()
    local size = GetFriendlyNameSize()
    -- Blizzard never rewrites the shared font OBJECTS (its plate setup only
    -- SetFontObjects the name strings onto them), so once they carry our
    -- file + size they keep it: an unchanged pair means nothing to restore
    -- or re-apply. Every SetFont on these objects relayouts every plate
    -- name, so this stamp is what keeps plate-add bursts free.
    -- `force` bypasses the stamp: on RESTRICTED friendly-player plates
    -- (instanced content) the per-string SetTextHeight re-stamp is denied,
    -- and this relayout is the only lever that clears Blizzard's per-instance
    -- height, so the deferred re-apply forces it there (once per burst).
    if not force and fontOverrideApplied and font == _ffFile and size == _ffSize then return end
    -- Restore to known-good originals first, so a member the new font does not
    -- take (a script it lacks) is back on Blizzard's own face.
    if fontOverrideApplied then
        EllesmereUI.RestoreFontObject(SystemFont_NamePlate, origNamePlateFont)
        EllesmereUI.RestoreFontObject(SystemFont_NamePlate_Outlined, origNamePlateOutlined)
        fontOverrideApplied = false
    end
    -- Blizzard picks the name's font object by Nameplate Style: Modern/Block
    -- anchor the name inside the bar and use _Outlined (stock NORMAL outline),
    -- Classic anchors it above and uses the plain object (stock SLUG only), so
    -- Classic-style users got name-only player names with no outline at all.
    -- Friendly names are always outlined (the full plates force it), so the
    -- one thing added here is OUTLINE where the object's own flags lack one.
    -- Everything else the object carries (SLUG, an outline already present)
    -- stays exactly as read, so already-outlined names render unchanged.
    -- The flags are the saved originals' (every member of these objects has
    -- the same), which is what the objects carry after the restore above.
    local function WithOutline(flags)
        flags = flags or ""
        if flags:find("OUTLINE", 1, true) then return flags end
        if flags == "" then return "OUTLINE" end
        return flags .. ", OUTLINE"
    end
    -- Our font, size and outline on every member that takes the font (the
    -- scripts it draws); the other members keep Blizzard's faces at our size.
    EllesmereUI.SetFontObjectFace(SystemFont_NamePlate, font, size, WithOutline(SnapFlags(origNamePlateFont)), nil)
    EllesmereUI.SetFontObjectFace(SystemFont_NamePlate_Outlined, font, size, WithOutline(SnapFlags(origNamePlateOutlined)), nil)
    _ffFile, _ffSize = font, size
    fontOverrideApplied = true
end

local function RestoreFriendlyFontOverride()
    if not fontOverrideApplied then return end
    fontOverrideApplied = false
    EllesmereUI.RestoreFontObject(SystemFont_NamePlate, origNamePlateFont)
    EllesmereUI.RestoreFontObject(SystemFont_NamePlate_Outlined, origNamePlateOutlined)
end

-- Name-only fonts are applied globally via the SystemFont_NamePlate override above.
--
-- Friendly name-only names must NEVER truncate. Blizzard anchors that name
-- FontString on BOTH its left and right edges, and a two-point anchor FIXES
-- the width -- SetWidth is a no-op against it (probe: pts=2, w=128 while the
-- string measured 274). So the fix collapses it to a single CENTER anchor
-- and drops any width box, letting it auto-size to the text.
--
-- Perf shape: no polling. The state IS the live point count, so the delta probe
-- (GetNumPoints, cheap and allowed inside the restricted 12.1 plate tree) runs first
-- and every already-collapsed FontString early-outs -- the steady state costs one C
-- call. Hooks are permanent but installed once per pooled FontString (bounded, ~plate
-- count) and their handlers are file-scope, so no closure is allocated per plate.
-- Blizzard re-anchoring is self-correcting: its first SetPoint leaves one point
-- (skipped), the second trips the probe and we collapse again. SECRET-VALUE RULE for
-- this block: inside the nameplate tree GetWidth (and GetPoint) return SECRET
-- numbers, and ANY comparison on one throws. So the only geometry read here is
-- GetNumPoints -- a plain count that stays readable -- and nothing else is measured,
-- compared, or carried over. The writes (ClearAllPoints / SetPoint / SetWidth) are
-- display sinks and are always safe.
local hookedNameFonts = {}  -- nameFS -> true (permanent hooks, applied once)
local _nameFixGuard = false
local ReanchorAllPlayerNames   -- forward decl (defined with the sweep helpers)

local function FixNameSizing(nameFS)
    if _nameFixGuard then return end
    _nameFixGuard = true
    local okp, pts = pcall(nameFS.GetNumPoints, nameFS)
    if okp and (pts or 0) >= 2 then
        -- Collapse the pair onto the parent's centre. No offset is read from the old
        -- points, so a plate whose name sat off-centre vertically is re-centred. Only
        -- runs while actually two-point, so this is a one-shot.
        local parent = nameFS:GetParent()
        if parent then
            nameFS:ClearAllPoints()
            nameFS:SetPoint("CENTER", parent, "CENTER", 0, 0)
        end
    end
    -- 0 on BOTH axes = auto-size to the text. Height matters as much as
    -- width here: Blizzard sizes this FontString for a single line, and a fixed height
    -- leaves the guild's second line nowhere to draw -- the composed string is present
    -- and correct on the widget but only its first line renders.
    nameFS:SetWidth(0)
    nameFS:SetHeight(0)
    _nameFixGuard = false
end

-- Width/size hook body: no reads and no comparisons at all (the incoming
-- values can themselves be secret), just an idempotent re-clear on both
-- axes. Deliberately does NOT touch anchors -- re-anchoring from inside
-- Blizzard's own anchor pass re-enters UpdateAnchors.
local function _OnNameWidthChanged(self)
    if _nameFixGuard then return end
    if not IsNameOnlyMode() then return end
    _nameFixGuard = true
    self:SetWidth(0)
    self:SetHeight(0)
    _nameFixGuard = false
end

-- Blizzard's ApplyFrameOptions stamps a PER-INSTANCE height on the name
-- FontString (name:SetTextHeight(healthBarFontHeight)), which beats the shared
-- SystemFont_NamePlate size, so the font-object override alone is lost on every
-- plate setup. Re-assert the configured height per FontString, and again whenever
-- Blizzard re-stamps it. Guarded because our own write re-enters the hook.
local _nameHeightGuard = false
local function ApplyNameTextHeight(nameFS)
    if _nameHeightGuard then return end
    if not (nameFS and nameFS.SetTextHeight) then return end
    if not IsNameOnlyMode() then return end
    _nameHeightGuard = true
    pcall(nameFS.SetTextHeight, nameFS, GetFriendlyNameSize())
    _nameHeightGuard = false
end

local function EnsureNameUnconstrained(nameFS)
    if not nameFS then return end
    FixNameSizing(nameFS)
    ApplyNameTextHeight(nameFS)
    if hookedNameFonts[nameFS] then return end
    hookedNameFonts[nameFS] = true
    hooksecurefunc(nameFS, "SetWidth", _OnNameWidthChanged)
    if nameFS.SetSize then hooksecurefunc(nameFS, "SetSize", _OnNameWidthChanged) end
    if nameFS.SetTextHeight then hooksecurefunc(nameFS, "SetTextHeight", ApplyNameTextHeight) end
end

-- Exposed so the options panel can live-apply a new friendly name-only size.
-- Re-running the override re-reads GetFriendlyNameSize and resizes the shared
-- font object; the name FontStrings inherit it on the next render.
function ns.RefreshFriendlyNameSize()
    if IsNameOnlyMode() then
        ApplyFriendlyFontOverride()
        -- Blizzard's per-instance name height overrides the font object, so the
        -- visible plates need the new size stamped on directly.
        if ReanchorAllPlayerNames then ReanchorAllPlayerNames() end
        -- The guild line hangs half a name-height below the plate centre, so
        -- a new name size moves it (ns lookup: defined later in this file).
        if ns.RefreshFriendlyBelowName then ns.RefreshFriendlyBelowName() end
    end
end

-- Re-assert the name-only font size after Blizzard touches nameplate fonts.
-- The size lives on the shared SystemFont_NamePlate object, which Blizzard resets
-- to its default during per-plate setup (new plates / camera revealing plates) and
-- on UpdateNamePlateOptions (CVar / display / options changes). Without re-applying,
-- newly shown or re-shown name-only plates revert to the default size. Deferred to
-- the next frame (after Blizzard's setup finishes) and debounced to batch bursts.
-- Touches font objects only -- no CVar writes -- so it can never feed back into
-- UpdateNamePlateOptions.
local _nameSizeReapplyPending = false
local _nameSizeReapplyForce = false
local function ScheduleNameSizeReapply(force)
    if force then _nameSizeReapplyForce = true end
    if _nameSizeReapplyPending or not IsNameOnlyMode() then return end
    _nameSizeReapplyPending = true
    C_Timer.After(0, function()
        _nameSizeReapplyPending = false
        local forced = _nameSizeReapplyForce
        _nameSizeReapplyForce = false
        if not IsNameOnlyMode() then return end
        ApplyFriendlyFontOverride(forced)
        -- Blizzard's own ApplyFrameOptions pass re-anchors the name (that is
        -- what fires this), so re-collapse it here rather than from a
        -- SetPoint hook, which would re-enter UpdateAnchors mid-pass. Rides
        -- the existing debounce, so a burst costs one sweep.
        if ReanchorAllPlayerNames then ReanchorAllPlayerNames() end
    end)
end

-------------------------------------------------------------------------------
--  Name-only NPC overlay
--  In name-only mode, Blizzard's name FontString is restricted and can't be
--  resized.  Instead of trying to modify it, we fully suppress the Blizzard
--  UnitFrame (reparent to hidden frame) and render our own name FontString
--  on the nameplate.  This gives us full control over width, color, and font.
-------------------------------------------------------------------------------
local npcOverlays = {}        -- nameplate -> overlay frame
local npcOverlayPool = {}     -- recycled overlay frames
local suppressedNPCPlates = {}  -- nameplate -> true (Blizzard's UnitFrame is parked for it)
local unitToNameplate = setmetatable({}, { __mode = "v" })

-- Filled further down, where the suppression and the name-only text live: the
-- overlay here is what calls into them.
local SuppressBlizzardUF, RestoreNPCNameplate, IsParked, HideNameOnlySub
local nameFSUnits, nameFSText

-- The plate's own unit token: namePlateUnitToken first, then the pooled
-- UnitFrame's, then the token the add hook recorded. nil once the plate lets
-- go of its unit.
local function GetNamePlateUnitToken(nameplate)
    if not nameplate then return nil end
    local u = nameplate.namePlateUnitToken
    if u and UnitExists(u) then return u end
    if nameplate.UnitFrame and nameplate.UnitFrame.unit and UnitExists(nameplate.UnitFrame.unit) then
        return nameplate.UnitFrame.unit
    end
    for unitToken, plate in pairs(unitToNameplate) do
        if plate == nameplate and UnitExists(unitToken) then
            return unitToken
        end
    end
    return nil
end


local NPC_TITLE_FONT_SIZE = 10

local function AcquireOverlay()
    local overlay = table.remove(npcOverlayPool)
    if overlay then return overlay end
    overlay = CreateFrame("Frame", nil, UIParent)
    overlay:SetSize(1, 1)
    overlay.name = overlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(overlay.name, 9, "")
    overlay.name:SetPoint("CENTER", overlay, "CENTER", 0, 0)
    -- The shadow rides the font family SetFSFont gives it (a font object).
    if overlay.name.SetSnapToPixelGrid then
        overlay.name:SetSnapToPixelGrid(false)
    end
    if overlay.name.SetTexelSnappingBias then
        overlay.name:SetTexelSnappingBias(0)
    end
    -- Title FontString (below name)
    overlay.title = overlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(overlay.title, 9, "")
    overlay.title:SetPoint("TOP", overlay.name, "BOTTOM", 0, -1)
    -- The shadow rides the font family SetFSFont gives it (a font object).
    if overlay.title.SetSnapToPixelGrid then
        overlay.title:SetSnapToPixelGrid(false)
    end
    if overlay.title.SetTexelSnappingBias then
        overlay.title:SetTexelSnappingBias(0)
    end
    overlay.title:Hide()
    return overlay
end

local function ShowNPCRaidMarker()
    local fp = FP()
    return fp and fp.showNPCRaidMarker ~= false
end

-- SuppressNPCNameplate hides Blizzard's RaidTargetFrame with the UnitFrame, so
-- the overlay draws its own marker. An NPC name-only plate has no bar geometry, so
-- the marker goes where Blizzard puts one on a name-only player plate: centred
-- above the name, a couple of pixels clear of it. The Raid Marker slot's own X/Y
-- nudges still apply, so a slot tweaked on the Display page moves this marker too,
-- and a slot of "none" turns the element off. Like the friendly plates' marker, it
-- stays hidden while Show Raid Marker is off.
local function UpdateOverlayRaidIcon(overlay)
    local pos = ns.GetRaidMarkerPos()
    local idx
    if ShowNPCRaidMarker() and pos ~= "none" then
        idx = GetRaidTargetIndex(overlay.unit)
    end
    -- type() is taint-safe: "nil" / "number" without reading a secret index
    if type(idx) == "nil" then
        if overlay.raid then overlay.raid:Hide() end
        return
    end
    if not overlay.raid then
        overlay.raid = overlay:CreateTexture(nil, "OVERLAY")
        overlay.raid:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    end
    SetRaidTargetIconTexture(overlay.raid, idx)
    local sz = ns.GetRaidMarkerSize()
    local xOff, yOff = ns.GetAuraSlotOffsets("raidMarker")
    overlay.raid:SetSize(sz, sz)
    overlay.raid:ClearAllPoints()
    overlay.raid:SetPoint("BOTTOM", overlay.name, "TOP", xOff, 2 + yOff)
    overlay.raid:Show()
end

-- A Raid Marker slot move repaints the bars; the overlay's marker follows on
-- the same RefreshPage pass, so the two never disagree.
if EllesmereUI.RegisterWidgetRefresh then
    EllesmereUI.RegisterWidgetRefresh(function()
        if next(npcOverlays) == nil then return end
        for _, overlay in pairs(npcOverlays) do
            if overlay.unit then UpdateOverlayRaidIcon(overlay) end
        end
    end)
end

local NPC_OVERLAY_FONT_SIZE = 13
local NPC_OVERLAY_Y_OFFSET = 5  -- positive = lower on screen (closer to character)
local NPC_OVERLAY_WIDTH = 126   -- word-wrap width

-- User-configurable size for friendly NPC and pet name-only overlay text.
local function GetOverlayNameSize(overlay)
    local fp = FP()
    if overlay.isPet then
        return (fp and fp.friendlyPetNameSize) or NPC_OVERLAY_FONT_SIZE
    end
    return (fp and fp.friendlyNPCNameSize) or NPC_OVERLAY_FONT_SIZE
end

local function GetNPCTitleSize(overlay)
    local fp = FP()
    if overlay.isPet then
        -- Owner Text Uses Its Own Size off: the owner line takes the pet name's
        -- size, the way a name's second line does.
        if not (fp and fp.friendlyPetOwnerOwnSize) then
            return (fp and fp.friendlyPetNameSize) or NPC_OVERLAY_FONT_SIZE
        end
        return (fp and fp.friendlyPetTitleSize) or NPC_TITLE_FONT_SIZE
    end
    return (fp and fp.friendlyNPCTitleSize) or NPC_TITLE_FONT_SIZE
end

-- Font and color for both overlay lines. Shared by the first paint and by the
-- option rows, which re-style live overlays rather than rebuilding them. Both
-- lines are font families (AcquireOverlay's first font is one), so every font
-- write here goes through SetFontFamily too.
local function ApplyOverlayStyle(overlay, unit)
    -- The user's own nameplate outline choice, as the plates that Blizzard and
    -- EUI draw take it; the overlay is no place to force one.
    local font, outline, shadow = GetFont(), ns.GetNPOutline(), GetNPUseShadow()
    EllesmereUI.SetFontFamily(overlay.name, font, GetOverlayNameSize(overlay), outline, shadow)
    local nr, ng, nb = ns.Allied.GetNameColor(unit)
    overlay.name:SetTextColor(nr, ng, nb)
    if overlay.name.SetSnapToPixelGrid then
        overlay.name:SetSnapToPixelGrid(false)
    end
    if overlay.name.SetTexelSnappingBias then
        overlay.name:SetTexelSnappingBias(0)
    end
    EllesmereUI.SetFontFamily(overlay.title, font, GetNPCTitleSize(overlay), outline, shadow)
    -- A pet's owner line takes its own colour (or the pet's name colour when it is
    -- set to match); an NPC's subtitle takes the NPC Title Color pair, or the name
    -- colour above it when it is set to match.
    if overlay.isPet then
        overlay.title:SetTextColor(ns.Allied.GetPetOwnerColor(unit))
    else
        overlay.title:SetTextColor(ns.Allied.GetTitleColor(unit, nr, ng, nb))
    end
end

-- The Friendly NPC Name Format (friendlyNPCNameFormat; unset = the whole
-- name).
local function FormatNPCName(name)
    local fp = FP()
    local mode = fp and fp.friendlyNPCNameFormat
    if not mode then return name end
    return EllesmereUI.ShortName(name, mode)
end

-- The line under the overlay's name: an NPC's subtitle (Show NPC Titles) or a
-- pet's owner, which always shows. null-safe on the unit's own kind.
local function SetOverlayTitle(overlay, unit)
    local show = overlay.isPet or ShowNPCTitles()
    if show and unit then
        local titleText = GetCachedNPCTitle(unit)
        if titleText then
            overlay.title:SetText("<" .. titleText .. ">")
            overlay.title:Show()
            return
        end
    end
    overlay.title:Hide()
end

-- UNIT_NAME_UPDATE: the server sent the name after the plate came up.
-- UNIT_FLAGS / UNIT_FACTION: the unit changed side, so its colour did.
local function OnOverlayEvent(self, event)
    local unit = self.unit
    if not unit then return end
    if event == "UNIT_NAME_UPDATE" then
        self.name:SetText(FormatNPCName(UnitName(unit) or ""))
    elseif event == "UNIT_FLAGS" or event == "UNIT_FACTION" then
        ApplyOverlayStyle(self, unit)
    end
end

-- Point the plate's overlay at a unit and paint it. A plate reused for another
-- NPC keeps its overlay frame but takes the new unit's name, colour, events and
-- marker: only the properties are re-read, never rebuilt.
local function ShowNPCOverlay(nameplate, unit)
    local overlay = npcOverlays[nameplate]
    if overlay and overlay.unit == unit then
        overlay:Show()
        ApplyOverlayStyle(overlay, unit)
        -- The line under the name answers a switch that can change under us (Show
        -- NPC Titles, Show Owner Name), so a repeated show re-reads it too.
        SetOverlayTitle(overlay, unit)
        -- The marker is the reason a filtered NPC can be on screen at all, so a
        -- repeated show re-anchors it rather than leaving a stale one.
        UpdateOverlayRaidIcon(overlay)
        return
    end
    if not overlay then
        overlay = AcquireOverlay()
        npcOverlays[nameplate] = overlay
        -- One line, auto-width: a name-only plate never ellipsizes.
        overlay.name:SetWidth(0)
        overlay.name:SetWordWrap(false)
        overlay.name:SetNonSpaceWrap(false)
        overlay.name:SetMaxLines(1)
        overlay:SetScript("OnEvent", OnOverlayEvent)
    end
    overlay.unit = unit
    overlay.isPet = IsPetUnit(unit)
    if overlay:GetParent() ~= nameplate then
        overlay:SetParent(nameplate)
        overlay:ClearAllPoints()
        overlay:SetPoint("CENTER", nameplate, "CENTER", 0, -NPC_OVERLAY_Y_OFFSET)
        overlay:SetFrameLevel(nameplate:GetFrameLevel() + 5)
    end
    overlay:Show()
    overlay.name:SetText(FormatNPCName(UnitName(unit) or ""))
    ApplyOverlayStyle(overlay, unit)
    SetOverlayTitle(overlay, unit)
    overlay:UnregisterAllEvents()
    UpdateOverlayRaidIcon(overlay)
    -- RAID_TARGET_UPDATE is not registered here: one sweep in the friendly
    -- settings path re-decides every marked plate, which is also what makes a
    -- newly marked NPC appear at all (see ns.RefreshMarkedNPCOverlays).
    if unit:find("^nameplate") then
        overlay:RegisterUnitEvent("UNIT_NAME_UPDATE", unit)
        overlay:RegisterUnitEvent("UNIT_FLAGS", unit)
        overlay:RegisterUnitEvent("UNIT_FACTION", unit)
    end
end

local function HideNPCOverlay(nameplate)
    local overlay = npcOverlays[nameplate]
    if not overlay then return end
    overlay:UnregisterAllEvents()
    overlay:Hide()
    overlay.name:SetText("")
    overlay.title:Hide()
    overlay.title:SetText("")
    if overlay.raid then overlay.raid:Hide() end
    overlay:SetParent(UIParent)
    overlay:ClearAllPoints()
    overlay.unit = nil
    npcOverlays[nameplate] = nil
    table.insert(npcOverlayPool, overlay)
end

-- Drop our name from a plate and hand Blizzard's frame back. A no-op for a plate
-- we never took.
local function ReleaseNPCOverlay(nameplate, unit)
    if suppressedNPCPlates[nameplate] then
        RestoreNPCNameplate(nameplate, unit)
    else
        HideNPCOverlay(nameplate)
    end
end

-- Whether the unit wears a raid marker. type() is taint-safe: a secret index
-- reads as "not a number", never a comparison that could throw.
local function HasRaidMarker(unit)
    if not unit or not GetRaidTargetIndex then return false end
    return type(GetRaidTargetIndex(unit)) == "number"
end

-- Whether a raid marker can put a plate up on its own: Always Show Marked NPCs,
-- off by default, so a mark never brings up a plate the user's toggle turned off.
local function MarkedNPCShown(unit)
    local fp = FP()
    return fp ~= nil and fp.friendlyShowMarkedNPCs == true and HasRaidMarker(unit)
end

-- Whether this base's plate is ours to take: a pet rides its own nameplate
-- toggle, a friendly or neutral NPC its nameplate toggle -- plus, while Show
-- Marked NPCs is on, any NPC the player has marked (naming it and drawing its
-- marker). Holding the plate and naming it are separate decisions (PlateNamed
-- below): a plate we hold but do not name stays parked and invisible, which is
-- the whole point of Name Only -- the NPC keeps its plate, and that plate shows
-- neither a health bar nor a name Blizzard's own NPC-names filter would have
-- hidden.
local function PlateClaimed(unit)
    local fp = FP()
    if not fp then return false end
    if IsPetUnit(unit) then return fp.showFriendlyPets == true end
    return fp.showFriendlyNPCs == true or MarkedNPCShown(unit)
end

-- Whether our name goes on the plate we hold. A pet always takes its name (that
-- is what its nameplate toggle is for); an NPC follows Blizzard's own filter,
-- which is what lifts while the unit is hovered or targeted (see
-- IsFriendlyNPCShownForUnit) -- and, while Always Show Marked NPCs is on, a
-- marked NPC is named whatever that filter says.
local function PlateNamed(unit)
    if IsPetUnit(unit) then return true end
    return IsFriendlyNPCShownForUnit(unit) or MarkedNPCShown(unit)
end

-- Whether a plate stays ours: a hostile plate we already parked keeps its name
-- (an NPC that turned on us under it), everything else answers the toggles above.
local function PlateKept(unit)
    return (UnitCanAttack("player", unit) and true or false) or PlateClaimed(unit)
end

-- The one place a friendly non-player plate is taken over: park Blizzard's
-- UnitFrame (keeping its interact icon) and put our name on the plate, or hand
-- the plate back untouched when nothing here wants it.
--   A plate we hold (PlateClaimed) stays parked whether or not it carries a name
--   (PlateNamed): Name Only means no health bar, so an NPC whose name Blizzard's
--   filter hides keeps an invisible plate rather than getting its bar back. Only
--   when no toggle wants the plate at all is it handed back. A hostile plate is
--   the enemy system's unless we already parked it.
local function RefreshNPCOverlay(nameplate, unit)
    if not nameplate or not unit then return end
    if not IsNameOnlyMode() or UnitIsPlayer(unit) then return end
    -- "Ours" means the park is in place right now, not that we once parked this
    -- base: the driver hands a stale park back on the base's next add (see the
    -- OnNamePlateAdded hook), so a claim with no park behind it is dropped here,
    -- and the plate is taken again below.
    local owned = suppressedNPCPlates[nameplate] == true and IsParked(nameplate.UnitFrame)
    if not owned then suppressedNPCPlates[nameplate] = nil end
    -- An attackable unit's plate is the enemy nameplate system's, and its
    -- UnitFrame has to stay where Blizzard put it: parking it hides every
    -- plate's content (IsVisible flips) and breaks stack picking between
    -- overlapping plates. Enemy pets included -- Show Enemy Pet Nameplates is
    -- Blizzard's CVar, not ours to overlay. Only a plate we already parked
    -- keeps a name here, for an NPC that turned on us under it.
    local hostile = UnitCanAttack("player", unit) and true or false
    if hostile and not owned then return end
    local claimed = hostile or PlateClaimed(unit)
    if not claimed then
        -- Nothing here wants this plate at all: hand it back rather than leave it
        -- parked with nobody asking for it (its nameplate toggle went off).
        ReleaseNPCOverlay(nameplate, unit)
        return
    end
    if not owned then
        -- The park can refuse (an attackable unit, or one EUI already draws an
        -- enemy plate for). Then the plate is not ours: no overlay either -- and
        -- no leftover one from the unit this base held before.
        if not SuppressBlizzardUF(unit, nameplate) then
            HideNPCOverlay(nameplate)
            return
        end
        -- Blizzard's name on this plate is gone: forget anything composed onto it,
        -- its guild line included -- that line is ours and would otherwise show
        -- the last friendly player's guild under this NPC's name. Cleared before
        -- the park is verified, so a rejected claim cannot leave it behind either.
        local nfs = nameplate.UnitFrame and nameplate.UnitFrame.name
        if nfs then
            nameFSUnits[nfs], nameFSText[nfs] = nil, nil
            HideNameOnlySub(nfs)
        end
        -- Bookkeeping is not proof: in combat Blizzard can refuse a write to a
        -- protected frame, and a park that did not take leaves Blizzard's own
        -- plate on screen. Painting our name over it as well is the one thing
        -- this must never do, so the frame is asked what it actually is: parented
        -- to the hidden holder, or alpha 0 (either one hides it). GetAlpha is read
        -- through pcall -- a secret answer must never be compared.
        local uf = nameplate.UnitFrame
        local hidden
        if uf then
            if uf:GetParent() == hiddenFrame then
                hidden = true
            elseif uf.GetAlpha then
                local ok, a = pcall(uf.GetAlpha, uf)
                hidden = ok and a == 0
            end
        end
        if not hidden then
            RestoreNPCNameplate(nameplate, unit)
            HideNPCOverlay(nameplate)
            return
        end
        suppressedNPCPlates[nameplate] = true
    end
    -- The plate is ours: our name goes on it only while PlateNamed says so, and
    -- the rest of the time the parked plate stays empty (Name Only, no bar).
    if hostile or PlateNamed(unit) then
        ShowNPCOverlay(nameplate, unit)
    else
        HideNPCOverlay(nameplate)
    end
end

-- Re-style live overlays in place: a slider drag or a swatch change must not
-- rebuild every overlay, which would re-read each unit's tooltip for the title.
function ns.RefreshNPCOverlayStyle()
    for _, overlay in pairs(npcOverlays) do
        if overlay.unit then ApplyOverlayStyle(overlay, overlay.unit) end
    end
end

-- Refresh all visible NPC overlays (Show NPC Titles, the title colour, Show
-- Raid Marker): re-decide each plate, then re-point each overlay at the unit it
-- already holds, which re-reads the title and re-registers the events without
-- pooling the frame.
local function RefreshAllNPCOverlays()
    for nameplate, overlay in pairs(npcOverlays) do
        local unit = overlay.unit
        if unit then
            -- An overlay whose plate moved on while it lingered keeps no name, and
            -- one whose unit is no longer shown goes with it. The moved-on base
            -- takes no unit: its own frame answers for whatever holds it now.
            if GetNamePlateUnitToken(nameplate) == unit and PlateKept(unit) then
                overlay.unit = nil
                ShowNPCOverlay(nameplate, unit)
            else
                ReleaseNPCOverlay(nameplate, nil)
            end
        end
    end
end
ns.RefreshAllNPCOverlays = RefreshAllNPCOverlays

-- Hand back every plate we hold that nothing wants any more (its nameplate toggle
-- went off, or it stopped being a friendly non-player's), leaving the rest alone.
-- The held set is the authority here, not the overlays: a plate we hold without
-- naming has no overlay to be found by, and leaving it parked would hide an NPC
-- plate nobody asked us to touch.
local function ReleaseUnclaimedNPCOverlays()
    for nameplate in pairs(suppressedNPCPlates) do
        local unit = GetNamePlateUnitToken(nameplate)
        if not (unit and PlateKept(unit)) then
            RestoreNPCNameplate(nameplate, unit)
        end
    end
end

-- A raid marker going on or off re-decides the plates it can affect: while Show
-- Marked NPCs is on, a marked NPC is shown -- name and marker -- even with its
-- nameplate toggle off and Blizzard's own filter against it; a plate we already
-- hold takes the new marker either way. RAID_TARGET_UPDATE is a user action, so
-- this sweep costs nothing while markers are left alone.
function ns.RefreshMarkedNPCOverlays()
    if not IsNameOnlyMode() then return end
    local plates = C_NamePlate.GetNamePlates()
    if not plates then return end
    local fp = FP()
    local showMarked = fp ~= nil and fp.friendlyShowMarkedNPCs == true
    for _, nameplate in ipairs(plates) do
        local unit = GetNamePlateUnitToken(nameplate)
        -- Attackable plates are the enemy system's, and a friendly player's name
        -- is not painted here.
        if unit and not UnitIsPlayer(unit) and not UnitCanAttack("player", unit) then
            if suppressedNPCPlates[nameplate] or (showMarked and HasRaidMarker(unit)) then
                RefreshNPCOverlay(nameplate, unit)
            end
        end
    end
end

-- Whether anything here can paint at all: the Name Only style plus one of the
-- two nameplate toggles. Cheap enough for the hover and target paths to ask
-- before walking anything.
function ns.FriendlyOverlayActive()
    if not IsNameOnlyMode() then return false end
    local fp = FP()
    return fp ~= nil and (fp.showFriendlyNPCs == true or fp.showFriendlyPets == true)
end

-- The plate the target or the cursor was on at the last pass. The plate we stop
-- pointing at is re-decided by name even when it carries none of our overlays:
-- a filtered NPC is ours only while it is hovered or targeted, so this is where
-- an untarget hands it back.
local lastPointedPlate

-- A target or mouseover change moves the plates it decides for: the two tokens
-- it changed, the plate it just left, and the plates already carrying an overlay
-- (their unit may have become, or stopped being, one the game names).
local function OnTargetChangedNPCOverlays()
    if not ns.FriendlyOverlayActive() then return end
    for nameplate, overlay in pairs(npcOverlays) do
        local unit = overlay.unit
        if unit and UnitExists(unit) and GetNamePlateUnitToken(nameplate) == unit then
            RefreshNPCOverlay(nameplate, unit)
        else
            -- The base let go of that unit: its own frame answers for whatever
            -- holds it now.
            ReleaseNPCOverlay(nameplate, nil)
        end
    end
    local function Check(unitToken)
        if not UnitExists(unitToken) or UnitIsPlayer(unitToken) then return end
        if UnitCanAttack("player", unitToken) then return end
        local plate = C_NamePlate.GetNamePlateForUnit(unitToken)
        if not plate or npcOverlays[plate] then return end
        -- The plate's own token, never "target"/"mouseover": a park record keyed
        -- by a token that changes meaning cannot be released reliably.
        local token = GetNamePlateUnitToken(plate)
        if token then RefreshNPCOverlay(plate, token) end
    end
    Check("target")
    Check("mouseover")
    -- The plate just left: the unit may have stopped being one we name (a
    -- filtered NPC we untargeted), so it is re-decided here whether or not it
    -- carries an overlay of ours.
    local pointed = (UnitExists("target") and C_NamePlate.GetNamePlateForUnit("target"))
        or (UnitExists("mouseover") and C_NamePlate.GetNamePlateForUnit("mouseover"))
    local prev = lastPointedPlate
    lastPointedPlate = pointed
    if prev and prev ~= pointed then
        local pu = GetNamePlateUnitToken(prev)
        if pu then
            RefreshNPCOverlay(prev, pu)
        else
            -- The base let go of its unit: give it back rather than leave it parked.
            ReleaseNPCOverlay(prev, nil)
        end
    end
end
ns.OnTargetChangedNPCOverlays = OnTargetChangedNPCOverlays

-- A base that let go of its unit keeps no overlay. NAME_PLATE_UNIT_REMOVED cannot
-- look the base up once the driver has cleared it (GetNamePlateForUnit(unit) is
-- already nil), so the live overlays are swept instead. Bounded by the overlays in
-- use, and a no-op for a base we never took.
function ns.ReleaseOrphanNPCOverlays()
    for nameplate in pairs(npcOverlays) do
        if not GetNamePlateUnitToken(nameplate) then ReleaseNPCOverlay(nameplate, nil) end
    end
end

-- Whether a unit is in your party or raid. The raid index reads secret where the
-- unit's identity is withheld, so only its type is asked.
local function InMyGroup(unit)
    return UnitInParty(unit) or type(UnitInRaid(unit)) == "number"
end

-------------------------------------------------------------------------------
--  Class colours: the friendly bar, the name and the guild line
-------------------------------------------------------------------------------
-- The unit's class colour on the suite palette (custom class colours and Class
-- Color Darken). Returns ok, r, g, b. A redacted class token takes the
-- restricted-unit palette, else Blizzard's class colour; those r/g/b may be
-- secret, so they only ever reach a setter. plainOnly refuses a redacted token
-- instead, for callers that need numbers they can do arithmetic on.
local function ClassRGB(unit, plainOnly)
    local _, tok = UnitClass(unit)
    if issecretvalue(tok) then
        if plainOnly then return false end
        local ok, r, g, b = EllesmereUI.GetClassColorForRestrictedUnit(unit, tok)
        if ok then return true, r, g, b end
        local c = C_ClassColor.GetClassColor(tok)
        if c then return true, c:GetRGB() end
        return false
    end
    if not tok then return false end
    local c = EllesmereUI.GetClassColor(tok)
    return true, c.r, c.g, c.b
end

-- Paints one full plate's bar and name. Players: the bar takes the class colour
-- (Class Colored Health Bar) or friendlyBarColor, the name the class colour or
-- the Custom colour (Name Color); with Class Colored Health Bar on, a class that
-- does not resolve paints both in the NPC colour. NPCs take the NPC colour. One
-- UnitClass read at most. Under the WoW Forever style a member of your party or
-- raid takes the stock plate's group tint in place of friendlyBarColor; the plate
-- remembers it (_grpTint), so a roster change repaints only the bars it moved
-- (ns.NP_FriendlyGroupWatch).
local function PaintFriendlyColors(plate, unit, fp)
    if plate._grpTint then plate._grpTint = nil end
    if UnitIsPlayer(unit) then
        local useClass = not fp or fp.classColorFriendly ~= false
        local nameClass = ns.FriendlyNameClass(fp, false)
        local ok, r, g, b
        if useClass or nameClass then ok, r, g, b = ClassRGB(unit) end
        if ok or not useClass then
            if useClass then
                plate.health:SetStatusBarColor(r, g, b)
            elseif ns.NP_Forever() and InMyGroup(unit) then
                -- The engine's selection tint: the lighter blue the stock plate
                -- shows for group members.
                plate.health:SetStatusBarColor(UnitSelectionColor(unit, true))
                plate._grpTint = true
            else
                local bc = (fp and fp.friendlyBarColor) or ns.defaults.friendlyBarColor
                plate.health:SetStatusBarColor(bc.r, bc.g, bc.b)
            end
            if nameClass and ok then
                plate.name:SetTextColor(r, g, b)
            else
                local nc = (fp and fp.friendlyNameColor) or ns.defaults.friendlyNameColor
                plate.name:SetTextColor(nc.r, nc.g, nc.b)
            end
            return
        end
    end
    local nr, ng, nb = GetFriendlyNPCColor()
    plate.health:SetStatusBarColor(nr, ng, nb)
    plate.name:SetTextColor(nr, ng, nb)
end
ns.NP_PaintFriendlyColors = PaintFriendlyColors   -- the options page's player sample

-------------------------------------------------------------------------------
--  Below Name sub text: data + rendering (shared by both friendly modes)
-------------------------------------------------------------------------------
local SUB_TEXT_R, SUB_TEXT_G, SUB_TEXT_B = 0.8, 0.8, 0.8

-- Effective sub text color: the player's own name colour when Match Player Name
-- Color is picked (a target highlight, else the name's class or custom colour),
-- else class color when Class Colored is picked, else the custom color.
local function GetSubTextColor(unit)
    local fp = FP()
    if fp and fp.friendlyBelowNameMatchNameColor then
        local r, g, b = ns.Allied.GetOverrideColor(unit, fp)
        if r then return r, g, b end
        -- The name's own colour, by the style in use (Class Color or Custom).
        if ns.FriendlyNameClass(fp, IsNameOnlyMode()) then
            local ok, cr, cg, cb = ClassRGB(unit, true)
            if ok then return cr, cg, cb end
        end
        local c = fp.friendlyNameColor or (ns.defaults and ns.defaults.friendlyNameColor)
        if c then return c.r, c.g, c.b end
        return 1, 1, 1
    end
    if fp and fp.friendlyBelowNameClassColor then
        local ok, r, g, b = ClassRGB(unit, true)
        if ok then return r, g, b end
    end
    local c = fp and fp.friendlyBelowNameColor
    if c then return c.r or SUB_TEXT_R, c.g or SUB_TEXT_G, c.b or SUB_TEXT_B end
    return SUB_TEXT_R, SUB_TEXT_G, SUB_TEXT_B
end

local function ModeHasTitle(mode) return mode == "title" or mode == "both" end
local function ModeHasGuild(mode) return mode == "guild" or mode == "both" end
-- Show Level (friendlyShowLevel, default off): a friendly PLAYER's level ahead
-- of the name, "60 | Name", in both friendly modes.
local function ShowFriendlyLevel()
    local fp = FP()
    return fp and fp.friendlyShowLevel == true
end
-- Color Level by Difficulty (friendlyLevelDiffColor, default off): the level
-- in its difficulty colour against yours, as Blizzard's level box draws it.
local function FriendlyLevelDiffColor()
    local fp = FP()
    return fp and fp.friendlyShowLevel == true and fp.friendlyLevelDiffColor == true
end
-- The level part of a friendly player's name: plain, or difficulty-coloured
-- while that option is on. A secret or unreadable level stays a plain "??".
local function FriendlyLevelText(unit)
    return ns.GetUnitLevelText(unit, FriendlyLevelDiffColor() and "diffAll" or nil)
end

-- Show [] Around Group/Raid (friendlyGroupBrackets, default off): wraps a
-- friendly group member's name in standard party-blue (#aaaaff) or
-- raid-orange (#ff7f00) square brackets, with the player's own raid
-- subgroup taking the party color. Each name remembers the bracket it was
-- painted with, so a roster change repaints only the names it moved
-- (ns.NP_FriendlyGroupWatch).
local PARTY_BRACKET_OPEN  = "|cffaaaaff[|r"
local PARTY_BRACKET_CLOSE = "|cffaaaaff]|r"
local RAID_BRACKET_OPEN   = "|cffff7f00[|r"
local RAID_BRACKET_CLOSE  = "|cffff7f00]|r"

local function ShowFriendlyGroupBrackets()
    local fp = FP()
    return fp and fp.friendlyGroupBrackets == true
end

-- The bracket a unit's name takes: "party", "raid", or nil outside your group
-- (and for yourself). A raid index or subgroup that reads secret is never
-- compared or truth-tested (its type is asked first): the party test decides then.
local function GetUnitGroupBracketKind(unit)
    if not unit or UnitIsUnit(unit, "player") then return nil end
    if IsInRaid() then
        local rIdx = UnitInRaid(unit)
        if type(rIdx) == "number" and not issecretvalue(rIdx) then
            local pIdx = UnitInRaid("player")
            if type(pIdx) == "number" and not issecretvalue(pIdx) then
                local _, _, uSub = GetRaidRosterInfo(rIdx)
                local _, _, pSub = GetRaidRosterInfo(pIdx)
                if type(uSub) == "number" and type(pSub) == "number" and not (issecretvalue(uSub) or issecretvalue(pSub)) then
                    return (uSub == pSub) and "party" or "raid"
                end
            end
            if UnitInParty(unit) then
                return "party"
            end
            return "raid"
        end
    end
    if UnitInParty(unit) then
        return "party"
    end
    return nil
end


-- The player's name WITH their title as one string ("Sergeant Bob" / "Bob
-- the Patient") -- UnitPVPName returns exactly that, so the title renders
-- inline with the name instead of on its own line. Returns nil when there
-- is no titled form to use (no API, no name yet, or a secret value: secrets
-- cannot be compared, and the plain-name fallback covers them).
local function GetTitledName(unit)
    if not UnitPVPName then return nil end
    local titled = UnitPVPName(unit)
    if not titled then return nil end
    if issecretvalue and issecretvalue(titled) then return nil end
    return titled
end

-- Status Tags: Blizzard's own nameplates print no away or busy tag, so one here
-- is ours to give. Each is its own choice (friendlyStatusTagAFK, Do Not Disturb
-- friendlyStatusTagDND), both off. Read by the compose paths below and by the
-- event pass that arms the flags listener.
local function ShowStatusTag()
    local fp = FP()
    return fp ~= nil and (fp.friendlyStatusTagAFK == true or fp.friendlyStatusTagDND == true)
end

-- Blizzard's own away/busy tag, as its tooltip and unit frames print it
-- (localized, angle brackets included). Returns " <AFK>" / " <DND>", or nil.
-- UnitIsAFK / UnitIsDND can hand back a secret value under combat taint, and a
-- secret cannot be branched on, so the tag is left off there rather than being
-- compared -- the honest answer is that this client will not say.
local AFK_TAG = CHAT_FLAG_AFK or "<AFK>"
local DND_TAG = CHAT_FLAG_DND or "<DND>"
local function PlayerStatusTag(unit)
    local fp = FP()
    if not (fp and unit) then return nil end
    if fp.friendlyStatusTagAFK == true and UnitIsAFK then
        local afk = UnitIsAFK(unit)
        if issecretvalue and issecretvalue(afk) then return nil end
        if afk then return " " .. AFK_TAG end
    end
    if fp.friendlyStatusTagDND == true and UnitIsDND then
        local dnd = UnitIsDND(unit)
        if issecretvalue and issecretvalue(dnd) then return nil end
        if dnd then return " " .. DND_TAG end
    end
    return nil
end

-- Name Color in Name Only mode. Blizzard colours its own name text: the class
-- colour by its CVar, else a colour of its own. A Custom pick is written as a
-- colour escape round the name, which outranks that colour; nil while the pick
-- is not Custom (unset included: Blizzard's own colour stands). The escape is
-- built again only when the colour changes.
local NameEsc = {}
function NameEsc.Get()
    local fp = FP()
    if not fp or fp.friendlyNameColorMode ~= "custom" then return nil end
    local c = fp.friendlyNameColor or ns.defaults.friendlyNameColor
    if c.r ~= NameEsc.r or c.g ~= NameEsc.g or c.b ~= NameEsc.b then
        NameEsc.r, NameEsc.g, NameEsc.b = c.r, c.g, c.b
        NameEsc.str = string.format("|cff%02x%02x%02x",
            math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5))
    end
    return NameEsc.str
end

-- The colour a friendly player's name-only text is written in, as an escape:
-- a target highlight (friend, guild, group, ...) wins over Name Color's Custom
-- pick. nil leaves Blizzard's own colour (the class colour by its CVar).
local function NameOnlyEsc(unit)
    local r, g, b = ns.Allied.GetOverrideColor(unit)
    if r then return ns.Allied.HexEsc(r, g, b) end
    return NameEsc.Get()
end
-- Name Format (friendlyNameFormat: "first", "last", "abbr" or a Character
-- Count; unset = Full Name): a friendly PLAYER's name, in both friendly
-- modes (callers pass players only).
--   FormatFriendlyName(unit, name, mayHaveTitle): a secret name passes through
--   whole (ShortName caches the short forms). With a Subtitle Text mode that
--   shows the title, the name may carry one: the character name inside it
--   (matched as whole words: the full name, else the first name alone) is
--   swapped for its short form and the title stays; a name it cannot find shows
--   whole. Results are cached per character and string (wiped at 256 per mode).
--   StampFriendlyNames(): records the settings the live names show (every full
--   repaint, and login); ns.NP_SyncFriendlyNameFormat repaints only when the
--   Name Format or the Subtitle Text settings differ from that record.
local FriendlyNameFormat, FormatFriendlyName, StampFriendlyNames
do
    local short, WithSurname = EllesmereUI.ShortName, EllesmereUI.WithSurname
    local titledShort = { first = {}, last = {}, abbr = {} }   -- [mode][full name][string] = result
    local titledCount = { first = 0, last = 0, abbr = 0 }
    -- A mode's cache; a Character Count gets its own on first use.
    local function TitledCache(mode)
        local cache = titledShort[mode]
        if not cache and EllesmereUI.IsNameFormat(mode) then
            cache = {}
            titledShort[mode], titledCount[mode] = cache, 0
        end
        return cache
    end
    FriendlyNameFormat = function()
        local fp = FP()
        return fp and fp.friendlyNameFormat
    end
    -- A byte of a name: a letter, a digit, or part of a multi-byte character.
    local function NameByte(b)
        return b and (b >= 128 or (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122))
    end
    -- Where `part` sits in `text` as whole words (no name byte either side), or nil.
    local function FindWords(text, part)
        local i, j = string.find(text, part, 1, true)
        while i do
            if not NameByte(text:byte(i - 1)) and not NameByte(text:byte(j + 1)) then return i, j end
            i, j = string.find(text, part, i + 1, true)
        end
    end
    FormatFriendlyName = function(unit, name, mayHaveTitle)
        local mode = FriendlyNameFormat()
        local cache = mode and TitledCache(mode)
        if not cache then return name end
        if not mayHaveTitle then return short(name, mode) end
        if issecretvalue(name) or type(name) ~= "string" then return name end
        local first, surname = UnitName(unit)
        if issecretvalue(first) or type(first) ~= "string" or first == "" then return name end
        local full = WithSurname(first, surname)
        local row = cache[full]
        local s = row and row[name]
        if s then return s end
        local i, j = FindWords(name, full)
        if not i and full ~= first then
            -- The first name alone, unless the surname shows too (a form this
            -- does not know: shown whole).
            i, j = FindWords(name, first)
            if i and FindWords(name, surname) then i = nil end
        end
        s = i and (name:sub(1, i - 1) .. short(full, mode) .. name:sub(j + 1)) or name
        if titledCount[mode] >= 256 then wipe(cache); titledCount[mode] = 0; row = nil end
        if not row then row = {}; cache[full] = row end
        row[name] = s
        titledCount[mode] = titledCount[mode] + 1
        return s
    end
    local aFormat, aNpcFormat, aMode, aBrackets, aMatch, aLevel, aDiff, aGroupBrackets, aNameEsc, aTagAFK, aTagDND, stamped
    StampFriendlyNames = function()
        local fp = FP()
        if not fp then return end
        aFormat, aMode = fp.friendlyNameFormat, fp.friendlyBelowName or "none"
        -- An NPC's name takes its own format, on the name-only overlay.
        aNpcFormat = fp.friendlyNPCNameFormat
        aBrackets, stamped = fp.friendlyBelowNameGuildBrackets ~= false, true
        aMatch = fp.friendlyBelowNameMatchNameColor == true
        aLevel, aDiff = fp.friendlyShowLevel == true, fp.friendlyLevelDiffColor == true
        aGroupBrackets = fp.friendlyGroupBrackets == true
        aTagAFK, aTagDND = fp.friendlyStatusTagAFK == true, fp.friendlyStatusTagDND == true
        aNameEsc = NameEsc.Get()
    end
    -- The Name Format options rows and every settings re-read (ns.RefreshAllSettings:
    -- profile switches, Spec Overrides). Before the first record it only records.
    function ns.NP_SyncFriendlyNameFormat()
        local fp = FP()
        if not fp then return end
        if not stamped then StampFriendlyNames(); return end
        if fp.friendlyNameFormat == aFormat and (fp.friendlyBelowName or "none") == aMode
            and fp.friendlyNPCNameFormat == aNpcFormat
            and (fp.friendlyBelowNameGuildBrackets ~= false) == aBrackets
            and (fp.friendlyBelowNameMatchNameColor == true) == aMatch
            and (fp.friendlyShowLevel == true) == aLevel
            and (fp.friendlyLevelDiffColor == true) == aDiff
            and (fp.friendlyGroupBrackets == true) == aGroupBrackets
            and (fp.friendlyStatusTagAFK == true) == aTagAFK
            and (fp.friendlyStatusTagDND == true) == aTagDND
            and NameEsc.Get() == aNameEsc then
            return
        end
        ns.RefreshFriendlyBelowName()
    end
end

-- Fill the sub text line (guild only -- the title rides the name itself)
-- and return how many lines got content. The guild name can be a secret
-- string: it is only truth-tested and rendered through SetFormattedText
-- (display sinks accept secrets), never concatenated or compared.
local function ApplySubText(fs, unit)
    local guild
    if ModeHasGuild(GetBelowNameMode()) then
        guild = GetGuildInfo and GetGuildInfo(unit)
    end
    if not guild then
        fs:SetText("")
        return 0
    end
    -- "<GuildName>" by default; the Subtitle Text cog can drop the brackets.
    local fp = FP()
    fs:SetFormattedText((not fp or fp.friendlyBelowNameGuildBrackets ~= false) and "<%s>" or "%s", guild)
    local r, g, b = GetSubTextColor(unit)
    fs:SetTextColor(r, g, b)
    return 1
end

-------------------------------------------------------------------------------
--  Name-only mode: EVERYTHING rides Blizzard's own name FontString
--
--  Blizzard renders the name here, so the title is folded in inline (via
--  UnitPVPName) and the guild is appended as a SECOND LINE of that same
--  string. One region means the guild can never drift from the name: there
--  is no second widget to position, so there is nothing to fall out of sync
--  on a moving (mounted) plate. A separate overlay frame was tried first and
--  jittered ~1px per frame against the name no matter how it was anchored or
--  pixel-snapped; this removes the failure mode instead of compensating.
--
--  Cost of the approach: one FontString means ONE font size, so the guild
--  line renders at the name's size here (its colour still applies, via an
--  inline colour escape). The Guild Text Size setting governs full-plate
--  mode, which draws its own separate FontString. Show Guild Line as Its Own
--  Text (off by default) opts into the separate widget instead, which can take
--  Guild Text Size at the cost of a position to keep in sync.
--
--  The unit token and last-written text for a Blizzard name FontString ride
--  external weak-keyed tables -- never custom keys on the Blizzard widget.
-------------------------------------------------------------------------------
nameFSUnits = setmetatable({}, { __mode = "k" })   -- nameFS -> unit token
nameFSText  = setmetatable({}, { __mode = "k" })   -- nameFS -> { name=, guild= }
local hookedNameText = {}   -- nameFS -> true (permanent hooks, applied once)
-- UnitFrames we hooked for the unit's own events: keyed weakly here, never
-- stamped on Blizzard's frame (a field there taints it).
local hookedUFEvents = setmetatable({}, { __mode = "k" })
local _titledNameGuard = false

-- The guild line under a Name Only name is a text of its own, never a second
-- line of Blizzard's name string: that string carries one font at one size, so
-- a guild line inside it could not take Guild Text Size. One font string per
-- name, weak-keyed by the name it hangs under (pooled name strings are never
-- freed), anchored to the name's bottom and hidden while there is no guild.
local nameOnlySubs = setmetatable({}, { __mode = "k" })   -- nameFS -> guild font string
local function NameOnlySub(nameFS)
    local fs = nameOnlySubs[nameFS]
    if fs then return fs end
    local parent = nameFS:GetParent() or UIParent
    fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetJustifyH("CENTER")
    fs:SetWordWrap(false)
    fs:SetMaxLines(1)
    -- Relative to the name, so Blizzard re-anchoring the name carries the line.
    fs:SetPoint("TOP", nameFS, "BOTTOM", 0, -1)
    fs:Hide()
    nameOnlySubs[nameFS] = fs
    return fs
end

HideNameOnlySub = function(nameFS)
    local fs = nameOnlySubs[nameFS]
    if not fs then return end
    fs:SetText("")
    fs:Hide()
end

-- Every name-only guild line off: the system stops painting these plates (the
-- style changed, or the plates are hidden), and a line left standing under
-- Blizzard's own name would be orphaned.
local function ClearAllNameOnlySubs()
    for nameFS in pairs(nameOnlySubs) do
        HideNameOnlySub(nameFS)
        nameFSText[nameFS] = nil
    end
end

-- Write (or clear) the guild line: its own font family at Guild Text Size, the
-- guild colour, the <brackets> the setting asks for.
local function WriteNameOnlySub(nameFS, unit, guild)
    if not guild then
        HideNameOnlySub(nameFS)
        return
    end
    local fs = NameOnlySub(nameFS)
    EllesmereUI.SetFontFamily(fs, GetFont(), GetSubTextSize(),
        (EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG", GetNPUseShadow())
    local r, g, b = GetSubTextColor(unit)
    local fp = FP()
    local body = (not fp or fp.friendlyBelowNameGuildBrackets ~= false) and "<%s>" or "%s"
    -- The guild is only ever a SetFormattedText argument (display sinks accept
    -- secrets); the brackets and the colour are our own values.
    fs:SetFormattedText(body, guild)
    fs:SetTextColor(r, g, b, 1)
    fs:Show()
end

-- Compose and write the full name-only string: name (+ inline title) plus an
-- optional guild line below it. Also the restore path -- with the Subtitle Text
-- setting off this resolves to the plain single-line name.
local function UpdateNameOnlyText(nameFS)
    local unit = nameFSUnits[nameFS]
    if not unit or not UnitExists(unit) then
        HideNameOnlySub(nameFS)
        nameFSText[nameFS] = nil
        return
    end
    -- Blizzard pools the plates' unit frames, so this FontString can come back on another
    -- plate (a pet's, an NPC's) while the token it was attached for now names a different
    -- plate. Write only while that token's plate still holds this FontString; otherwise
    -- forget the token and leave Blizzard's own name.
    local np = C_NamePlate.GetNamePlateForUnit(unit)
    if not (np and np.UnitFrame and np.UnitFrame.name == nameFS) then
        nameFSUnits[nameFS], nameFSText[nameFS] = nil, nil
        HideNameOnlySub(nameFS)
        return
    end
    -- This composition is for players: NPC plates ride the overlay above.
    local isPlayer = UnitIsPlayer(unit)
    if not isPlayer then
        HideNameOnlySub(nameFS)
        nameFSText[nameFS] = nil
        return
    end
    -- Nameplate tokens are recycled: a plate reused for an enemy keeps our
    -- hook and a stale friendly token, so never write on a hostile unit
    -- (Blizzard's own name write is already correct there).
    if UnitCanAttack("player", unit) then
        HideNameOnlySub(nameFS)
        nameFSText[nameFS] = nil
        return
    end
    local mode = GetBelowNameMode()

    local want
    if ModeHasTitle(mode) and isPlayer then want = GetTitledName(unit) end
    if not want then want = EllesmereUI.WithSurname(UnitName(unit)) end
    if not want or (issecretvalue and issecretvalue(want)) then return end
    -- The friendly Name Format, while one is saved (players only).
    if isPlayer and FriendlyNameFormat() then
        want = FormatFriendlyName(unit, want, ModeHasTitle(mode))
    end
    -- Blizzard's away/busy tag, on the name itself so it takes the name's colour
    -- and rides inside the group brackets. Off unless Status Tags asks for
    -- it (PlayerStatusTag answers nil then).
    if isPlayer then
        local tag = PlayerStatusTag(unit)
        if tag then want = want .. tag end
    end
    -- The name's colour: a target highlight (friend, guild, group, ...) first,
    -- else Name Color's Custom pick. Round the name, inside the group brackets,
    -- which keep their own colours.
    local esc = isPlayer and NameOnlyEsc(unit) or nil
    if esc then want = esc .. want .. "|r" end
    local gKind
    if isPlayer and ShowFriendlyGroupBrackets() then
        gKind = GetUnitGroupBracketKind(unit)
        if gKind == "party" then
            want = PARTY_BRACKET_OPEN .. want .. PARTY_BRACKET_CLOSE
        elseif gKind == "raid" then
            want = RAID_BRACKET_OPEN .. want .. RAID_BRACKET_CLOSE
        end
    end
    if isPlayer and ShowFriendlyLevel() then
        if esc then
            -- The level and the divider take the colour too; each piece closes its
            -- own escape, so a level coloured by difficulty keeps that colour.
            want = esc .. FriendlyLevelText(unit) .. "|r" .. esc .. " | |r" .. want
        else
            want = FriendlyLevelText(unit) .. " | " .. want
        end
    end

    local guild
    if ModeHasGuild(mode) and isPlayer then
        guild = GetGuildInfo and GetGuildInfo(unit)
    end

    -- Dedupe key. A secret guild cannot be compared, so it collapses to a
    -- plain "present" marker: a guild RENAME then rides the next respawn
    -- rather than the next hook fire, which is a fair trade for never
    -- touching a secret with ==.
    local guildKey = guild
    if guildKey ~= nil and issecretvalue and issecretvalue(guildKey) then guildKey = true end
    local st = nameFSText[nameFS]
    if st and st.name == want and st.guild == guildKey then return end
    if not st then st = {}; nameFSText[nameFS] = st end
    -- st.grp is the roster watcher's record of the bracket this name wears: a
    -- player who leaves the group has a different (nil) kind and is recomposed.
    st.name, st.guild, st.grp = want, guildKey, gKind

    _titledNameGuard = true
    nameFS:SetMaxLines(1)
    nameFS:SetText(want)
    _titledNameGuard = false
    -- The guild line is a text of its own at Guild Text Size; nil clears it.
    WriteNameOnlySub(nameFS, unit, guild)
end

-- Whether this plate's name can differ from the plain name Blizzard writes:
-- a subtitle, a name format, a level, brackets, a name colour, a target
-- highlight, or the away/busy tag while a Status Tag is on. Cheapest test
-- first; the hook asks this on every SetText.
local function NeedsNameOnlyTextUpdate(unit)
    if GetBelowNameMode() ~= "none" or FriendlyNameFormat() or ShowFriendlyLevel() or ShowFriendlyGroupBrackets() then
        return true
    end
    local fp = FP()
    if not fp then return false end
    if NameEsc.Get() then return true end
    if not (unit ~= nil and UnitIsPlayer(unit)) then return false end
    -- An away or busy player's name carries the tag, which only we write: on an
    -- otherwise untouched plate that is the one reason to compose at all.
    if PlayerStatusTag(unit) then return true end
    return ns.Allied.HasPlayerOverride(fp)
end

-- Register a plate's name FontString and (once) hook its SetText so our
-- composition survives Blizzard's own name updates. The hook body is a
-- field read or two while Subtitle Text and the Name Format are both off.
local function AttachNameOnlyText(nameFS, unit)
    if not unit or not UnitIsPlayer(unit) then return end
    -- Pair the width clear with the (longer) text write: a titled name must
    -- never hit a leftover constraint and ellipsize.
    EnsureNameUnconstrained(nameFS)
    nameFSUnits[nameFS] = unit
    if not hookedNameText[nameFS] then
        hookedNameText[nameFS] = true
        hooksecurefunc(nameFS, "SetText", function(self)
            if _titledNameGuard then return end
            local u = nameFSUnits[self]
            if not u or not UnitExists(u) or not UnitIsPlayer(u) then
                -- Blizzard pools these FontStrings, so this one now draws a
                -- plate that is no longer a friendly player's (an NPC's, a pet's,
                -- an enemy's). The guild line under it is OURS, and nothing else
                -- clears it: left alone it shows a nearby player's guild under
                -- whatever that plate holds now. Forget the pairing and clear it.
                nameFSUnits[self], nameFSText[self] = nil, nil
                HideNameOnlySub(self)
                return
            end
            if not NeedsNameOnlyTextUpdate(u) then
                -- Nothing of ours belongs on this name: a line left from the
                -- plate's last occupant is stale, so take it down.
                HideNameOnlySub(self)
                return
            end
            -- Blizzard just overwrote the composed string with its own plain
            -- name; drop the dedupe so the recompose actually runs.
            nameFSText[self] = nil
            UpdateNameOnlyText(self)
        end)
    end
    -- Late unit data (a PvP flag, a faction flip) arrives as the unit's own
    -- events, and the plate's UnitFrame is their only listener: the recompose
    -- rides its OnEvent instead of a timer retry on the add.
    local np = C_NamePlate.GetNamePlateForUnit(unit)
    local uf = np and np.UnitFrame
    if uf and not hookedUFEvents[uf] and not uf:IsForbidden() then
        hookedUFEvents[uf] = true
        uf:HookScript("OnEvent", function(self, event)
            if event ~= "UNIT_FACTION" then return end
            local fs = self.name
            local u = fs and nameFSUnits[fs]
            if not u then return end
            nameFSText[fs] = nil
            UpdateNameOnlyText(fs)
        end)
    end
    UpdateNameOnlyText(nameFS)
end

-- The nameplate token of the friendly plate showing an event's unit, nil with
-- none. GetNamePlateForUnit refuses group tokens ("party1", "raid12",
-- "raidpet3": the client raises), so a group token is matched against the live
-- friendly plates (ns.pendingUnits, the few on screen) with UnitIsUnit, whose
-- answer is tested for secrecy before it is used; any other token ("target",
-- "mouseover", a nameplate token) is one call to the API.
local function FriendlyPlateToken(eventUnit)
    if type(eventUnit) ~= "string" then return nil end
    if eventUnit:find("^party") or eventUnit:find("^raid") then
        local pending = ns.pendingUnits
        if not pending then return nil end
        for tok in pairs(pending) do
            local same = UnitIsUnit(tok, eventUnit)
            if not issecretvalue(same) and same then return tok end
        end
        return nil
    end
    local np = C_NamePlate.GetNamePlateForUnit(eventUnit)
    return np and GetNamePlateUnitToken(np) or nil
end

-- A unit's away or busy flag changed (PLAYER_FLAGS_CHANGED): the tag is part of
-- the name we compose, so that unit's plates redraw -- in either friendly style,
-- Name Only included. The event names the token the client tracks ("target",
-- "party1") while our plates are keyed by their nameplate token, and
-- FriendlyPlateToken bridges the two. Cheap by construction: the name-only side
-- dedupes on the composed string and a bar plate compares the tag before running
-- its name pass, so a flag that changes nothing visible costs one compare.
local function RefreshStatusTags(eventUnit)
    if not eventUnit then return end
    local token = FriendlyPlateToken(eventUnit) or eventUnit
    if not token then return end
    local swept
    for nameFS, u in pairs(nameFSUnits) do
        if u == token or u == eventUnit then
            swept = swept or {}
            swept[#swept + 1] = nameFS
        end
    end
    if swept then
        for i = 1, #swept do
            local nameFS = swept[i]
            nameFSText[nameFS] = nil
            UpdateNameOnlyText(nameFS)
        end
    elseif IsNameOnlyMode() then
        -- A plate we were not composing (nothing on it needed us) is attached now,
        -- because its name carries the tag: that is what makes the marker appear
        -- on an otherwise untouched plate without a reload or a target change.
        local pending = ns.pendingUnits
        local plate = pending and pending[token]
        local uf = plate and plate.UnitFrame
        if uf and uf.name and UnitIsPlayer(token) and not UnitCanAttack("player", token)
            and NeedsNameOnlyTextUpdate(token) then
            nameFSText[uf.name] = nil
            AttachNameOnlyText(uf.name, token)
        end
    end
    for u, bar in pairs(friendlyPlates) do
        if (u == token or u == eventUnit) and bar.unit
            and PlayerStatusTag(bar.unit) ~= bar._statusTag then
            bar:UpdateName()
        end
    end
end

-- One unit's guild name arrived or changed (PLAYER_GUILD_UPDATE carries the
-- token): repaint that unit's plate alone, in either friendly style. The
-- client's token ("party1", "target") is bridged to the plate's own token by
-- FriendlyPlateToken, so no walk over every plate for a non-group token.
local function RepaintUnitGuild(eventUnit)
    if not eventUnit then return end
    local token = FriendlyPlateToken(eventUnit)
    local np = token and ns.pendingUnits and ns.pendingUnits[token]
    if not np then return end
    local plate = friendlyPlates[token]
    if plate then plate:UpdateName() end
    local fs = np.UnitFrame and np.UnitFrame.name
    if fs and nameFSUnits[fs] then
        nameFSText[fs] = nil
        UpdateNameOnlyText(fs)
    end
end

-- Sweep all visible friendly player plates and recompose their name text per the
-- current settings (mode off included -- the composition resolves back to the plain
-- name, undoing anything we previously wrote). Iterates ns.pendingUnits -- the main
-- file's live unit -> nameplate registry for friendly plates, maintained by its
-- NAME_PLATE_UNIT_ADDED/REMOVED handlers (the name-only Y-offset feature sweeps it the
-- same way). C_NamePlate.GetNamePlates does not return friendly player plates, so it
-- cannot drive this sweep.
local function SweepPlayerSubText()
    if not IsNameOnlyMode() then return end
    local pending = ns.pendingUnits
    if not pending then return end
    for unit, nameplate in pairs(pending) do
        if UnitIsPlayer(unit) and not UnitIsUnit(unit, "player") and not UnitCanAttack("player", unit) then
            local uf = nameplate.UnitFrame
            if uf and uf.name then
                -- Settings changed under us, so drop the dedupe first.
                nameFSText[uf.name] = nil
                AttachNameOnlyText(uf.name, unit)
            end
        end
    end
end

-- Re-collapse every visible friendly player name after Blizzard re-anchors
-- them (UpdateNamePlateOptions / ApplyFrameOptions). Assigns the forward
-- local declared with FixNameSizing. Each call is a GetNumPoints probe per
-- plate and writes only where the two-point anchor came back.
function ReanchorAllPlayerNames()
    local pending = ns.pendingUnits
    if not pending then return end
    for unit, nameplate in pairs(pending) do
        if UnitIsPlayer(unit) and not UnitCanAttack("player", unit) and not UnitIsUnit(unit, "player") then
            local uf = nameplate.UnitFrame
            if uf and uf.name then
                FixNameSizing(uf.name)
                ApplyNameTextHeight(uf.name)
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Hidden frame -- Blizzard sub-frames reparented here become invisible
--  and stop receiving layout updates.  This suppresses the default frames.
-------------------------------------------------------------------------------
local hiddenFrame = CreateFrame("Frame")
hiddenFrame:Hide()

-------------------------------------------------------------------------------
--  Blizzard UnitFrame suppression via NamePlateDriverFrame hooks
--  Hook OnNamePlateAdded/Removed on the
--  NamePlateDriverFrame so suppression happens BEFORE any addon event fires.
--  This eliminates the flash of Blizzard nameplates.
-------------------------------------------------------------------------------
local hookedUFs = {}   -- UnitFrame -> true  (hooks are permanent, only applied once)
-- The parked frames: uf -> record, and unit -> the same record, so a frame can
-- be handed back by either (Blizzard clears a plate's unit before any addon
-- sees NAME_PLATE_UNIT_REMOVED). A record outlives its park only for the frame
-- that owns it, which is weak-keyed.
local suppressedUFs = setmetatable({}, { __mode = "k" })
local suppressedByUnit = {}

-- Whether this UnitFrame is parked for us right now. A park can be handed back
-- behind a caller's back (the driver's next add on a base releases a stale one),
-- so a plate's claim on it is never proof on its own.
IsParked = function(uf)
    return uf ~= nil and suppressedUFs[uf] ~= nil
end

local function UnparkBlizzardUF(rec, parent)
    local uf = rec and rec.uf
    if not uf then return end
    if suppressedUFs[uf] == rec then suppressedUFs[uf] = nil end
    if rec.unit and suppressedByUnit[rec.unit] == rec then suppressedByUnit[rec.unit] = nil end
    -- Restore UnitFrame back to its nameplate parent
    uf:SetParent(parent or rec.nameplate)
    if uf.WidgetContainer then
        uf.WidgetContainer:SetParent(uf)
    end
    if uf.SoftTargetFrame then
        uf.SoftTargetFrame:SetParent(uf)
    end
    uf:SetAlpha(1)
    uf:Show()
end

-- Hand a parked UnitFrame back, by unit (its plate may already be cleared) or
-- by the plate in front of us. `nameplate` wins as the frame's new parent: a
-- pooled frame can reach the next plate before the last one released it.
local function RestoreBlizzardUF(unit, nameplate)
    local rec = unit and suppressedByUnit[unit]
    if not rec and nameplate and nameplate.UnitFrame then rec = suppressedUFs[nameplate.UnitFrame] end
    UnparkBlizzardUF(rec, nameplate)
end

SuppressBlizzardUF = function(unit, nameplate)
    local uf = nameplate and nameplate.UnitFrame
    if not uf then return false end
    -- Never take a frame that draws an enemy's plate. Two ways to know one: EUI
    -- has a plate of its own on the unit, and the unit is hostile. Its plates
    -- need the UnitFrame to stay on the nameplate at alpha 0 (see
    -- HideBlizzardFrame in EUI_Nameplates_Plate.lua) -- reparenting it, or
    -- setting alpha 1 as an unpark does, puts Blizzard's whole plate back on top
    -- of EUI's: two bars, two names, Blizzard's auras, and a stack that collapses.
    if unit and UnitCanAttack("player", unit) then return false end
    if unit and ns.plates and ns.plates[unit] then return false end

    -- A pooled UnitFrame can arrive still parked: its last plate let go of it
    -- before the park was released. That park is dead, so release it first.
    local rec = suppressedUFs[uf]
    if rec and rec.nameplate ~= nameplate then
        UnparkBlizzardUF(rec)
        rec = nil
    end

    -- Hand back what an enemy plate parked on this pooled UnitFrame first: the
    -- enemy reclaim hook runs after this one and would otherwise pull the
    -- WidgetContainer back under the hidden UnitFrame.
    ns.NP_ReclaimBlizzardFrame(uf)

    uf:SetAlpha(0)

    -- Reparent the entire UnitFrame to the hidden frame. This makes everything
    -- invisible. We do NOT unregister events because we need Blizzard's UF to stay
    -- functional for when we restore it (e.g. toggling back to name-only mode).
    if uf:GetParent() ~= hiddenFrame then
        uf:SetParent(hiddenFrame)
    end
    -- Keep UI widgets (progress gauges on untargetable objectives) visible, as the
    -- enemy plate does.
    if uf.WidgetContainer then
        uf.WidgetContainer:SetParent(nameplate)
    end
    -- Keep the soft-target interact icon visible too, as the enemy plate does:
    -- world objects (herbs, ore, mailboxes) land here as non-attackable
    -- non-players, and their icon lives on this UnitFrame.
    if uf.SoftTargetFrame then
        uf.SoftTargetFrame:SetParent(nameplate)
    end

    if not rec then rec = {} end
    rec.uf, rec.nameplate, rec.unit = uf, nameplate, unit
    suppressedUFs[uf] = rec
    if unit then suppressedByUnit[unit] = rec end

    -- Permanent SetAlpha, Show and SetParent hooks (once per UF instance), so a
    -- Blizzard update or a target change cannot bring a parked frame back --
    -- including in combat, which is the case that matters: a friendly NPC that
    -- enters combat has its plate re-shown by Blizzard's own refresh, and that
    -- is exactly when an alpha-0 frame must go straight back. So the hooks do
    -- not bail on IsForbidden: the enemy plates' own hook re-asserts alpha 0 the
    -- same way, and these frames are not secure-only (Blizzard writes to them
    -- from insecure code throughout, which is what these hooks intercept).
    if not hookedUFs[uf] then
        hookedUFs[uf] = true
        local locked = false
        hooksecurefunc(uf, "SetAlpha", function(self)
            if locked then return end
            if suppressedUFs[self] then
                locked = true
                self:SetAlpha(0)
                locked = false
            end
        end)
        hooksecurefunc(uf, "Show", function(self)
            if locked then return end
            if suppressedUFs[self] then
                locked = true
                if self:GetParent() ~= hiddenFrame then
                    self:SetParent(hiddenFrame)
                end
                self:SetAlpha(0)
                locked = false
            end
        end)
        hooksecurefunc(uf, "SetParent", function(self, newParent)
            if locked then return end
            if suppressedUFs[self] and newParent ~= hiddenFrame then
                locked = true
                self:SetParent(hiddenFrame)
                self:SetAlpha(0)
                locked = false
            end
        end)
    end
    return true
end

-------------------------------------------------------------------------------
--  Name-only NPC suppression: the plate itself is handled by RefreshNPCOverlay
--  above (which parks Blizzard's UnitFrame and puts our name on the plate).
-------------------------------------------------------------------------------
RestoreNPCNameplate = function(nameplate, unit)
    if not suppressedNPCPlates[nameplate] then return end
    suppressedNPCPlates[nameplate] = nil
    HideNPCOverlay(nameplate)
    RestoreBlizzardUF(unit, nameplate)
end

-- Name-only friendly NPCs never touch friendlyPlates[] -- they're suppressed
-- purely via RefreshNPCOverlay/npcOverlays, keyed by nameplate rather than
-- unit. RemoveFriendlyPlate/RemoveFriendlyPlateNoRestore only clean up the
-- full-plate pool, so when such an NPC is promoted to an enemy plate (e.g.
-- becomes attackable) the orphaned name overlay is left rendering on top of
-- the new enemy bar. Called from the friendly->enemy promotion watcher
-- BEFORE the enemy plate spawns: the park is handed back here so the enemy
-- side's HideBlizzardFrame (which does not reparent, it only alphas and parks
-- children) inherits a frame that is on its nameplate rather than ours.
function ns.RemoveFriendlyNPCOverlayForUnit(unit, nameplate)
    nameplate = nameplate or (unit and C_NamePlate.GetNamePlateForUnit(unit))
    if not nameplate or not suppressedNPCPlates[nameplate] then return end
    suppressedNPCPlates[nameplate] = nil
    HideNPCOverlay(nameplate)
    RestoreBlizzardUF(unit, nameplate)
end

-------------------------------------------------------------------------------
--  NamePlateDriverFrame hooks -- suppress Blizzard UFs at the earliest moment
--  These fire synchronously inside Blizzard's nameplate creation, BEFORE
--  NAME_PLATE_UNIT_ADDED reaches any addon event handler.
-------------------------------------------------------------------------------
hooksecurefunc(NamePlateDriverFrame, "OnNamePlateAdded", function(_, unit)
    if not unit or unit == "preview" then return end
    if UnitCanAttack("player", unit) then return end
    if UnitIsUnit(unit, "player") then return end

    local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
    if nameplate then unitToNameplate[unit] = nameplate end

    -- A pooled UnitFrame can arrive still parked for the unit that last held
    -- it, if that plate let go before the park was handed back. Release it
    -- first: a plate Blizzard is drawing must never be left invisible, and
    -- the paths below park it again if it is still ours.
    if nameplate and nameplate.UnitFrame and suppressedUFs[nameplate.UnitFrame] then
        RestoreBlizzardUF(nil, nameplate)
    end

    -- Re-assert the name-only font size for this newly added / camera-revealed
    -- plate -- Blizzard's per-plate setup resets the shared font object to default.
    -- No-op outside name-only mode. Forced in instanced content for PLAYER plates
    -- only: those are the restricted ones where the per-string re-stamp cannot
    -- take, and the forced path relayouts every plate name four times, so a
    -- pet / NPC add must not pay it.
    ScheduleNameSizeReapply(IsInInstance() and UnitIsPlayer(unit))

    -- Health-bar mode: full UF suppression for players (and NPCs if enabled)
    if IsFriendlyEnabled() then
        -- Suppress Blizzard's default plate for players and ALL enabled friendly
        -- NPCs. The custom plate itself is gated per-NPC in TryAddFriendlyPlate, so
        -- filtered NPCs end up suppressed with no plate = hidden.
        if not UnitIsPlayer(unit) and not IsFriendlyNPCEnabled() then return end
        if nameplate then
            SuppressBlizzardUF(unit, nameplate)
        end
        return
    end

    -- Name-only mode: hand every friendly non-player plate to RefreshNPCOverlay,
    -- which parks Blizzard's UnitFrame (keeping its interact icon) and draws
    -- our name, or leaves the plate to Blizzard when nothing here wants it.
    if IsNameOnlyMode() and not UnitIsPlayer(unit) then
        RefreshNPCOverlay(nameplate, unit)
    end

    -- Name-only mode (players): remove Blizzard's width constraint on the
    -- name FontString so long names are never truncated with "...".
    if IsNameOnlyMode() and UnitIsPlayer(unit) then
        if nameplate and nameplate.UnitFrame and nameplate.UnitFrame.name then
            -- Name-only player plates render ONLY the name, but Blizzard's
            -- CompactUnitFrame keeps its full ~47-event surface live behind
            -- every one of them (incl. UNIT_AURA and UPDATE_MOUSEOVER_UNIT).
            -- Kill it; keep the name channel plus the soft-target trio. Self-
            -- healing: the driver's secure SetUnit re-registers everything on
            -- the plate's next occupant, and the name-only mode toggle writes
            -- nameplate CVars, which trigger the driver's own full re-setup.
            local uf = nameplate.UnitFrame
            if not uf:IsForbidden() then
                uf:UnregisterAllEvents()
                uf:RegisterUnitEvent("UNIT_NAME_UPDATE", unit)
                uf:RegisterUnitEvent("UNIT_FACTION", unit)
                uf:RegisterUnitEvent("UNIT_FLAGS", unit)
                uf:RegisterEvent("PLAYER_TARGET_CHANGED")
                uf:RegisterEvent("PLAYER_SOFT_FRIEND_CHANGED")
                uf:RegisterEvent("PLAYER_SOFT_ENEMY_CHANGED")
                -- Blizzard's RaidTargetFrame is the marker display on this path and
                -- its OnUnitSet drives it from this event alone; without it the marker
                -- froze until the plate was re-acquired.
                uf:RegisterEvent("RAID_TARGET_UPDATE")
            end
            EnsureNameUnconstrained(nameplate.UnitFrame.name)
            -- Subtitle Text (inline title + guild line), the Name Format, a
            -- level, brackets, Name Color's Custom colour and the target
            -- highlights, all composed onto this same FontString.
            if NeedsNameOnlyTextUpdate(unit) then
                AttachNameOnlyText(nameplate.UnitFrame.name, unit)
            end
        end
    end
end)

hooksecurefunc(NamePlateDriverFrame, "OnNamePlateRemoved", function(_, unit)
    -- Guard: Blizzard settings panel can fire this with "preview" which is not a valid unit
    if not unit or not unit:find("^nameplate") then return end
    -- Blizzard has already detached the plate's UnitFrame by now (its name
    -- FontString went back to the pool with it), so the token the add hook
    -- recorded is what still finds the plate.
    local nameplate = unitToNameplate[unit] or C_NamePlate.GetNamePlateForUnit(unit)
    unitToNameplate[unit] = nil
    if nameplate then
        HideNPCOverlay(nameplate)
        suppressedNPCPlates[nameplate] = nil
    end
    RestoreBlizzardUF(unit, nameplate)
end)

-------------------------------------------------------------------------------
--  Frame pool for custom friendly plates
-------------------------------------------------------------------------------
local friendlyFrameCache = CreateFramePool("Frame", UIParent, nil, nil, false, function(plate)
    plate:SetFlattensRenderLayers(true)

    plate.health = CreateFrame("StatusBar", nil, plate)
    plate.health:SetFrameLevel(10)
    plate.health:SetPoint("CENTER", 0, FRIENDLY_PLATE_Y_OFFSET)
    plate.health:SetSize(GetFriendlyHealthBarWidth(), GetFriendlyHealthBarHeight())
    plate.health:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")

    plate.healthBG = plate.health:CreateTexture(nil, "BACKGROUND")
    plate.healthBG:SetAllPoints()
    plate.healthBG:SetColorTexture(0.12, 0.12, 0.12, 1.0)

    -- Border: pixel-perfect PP.CreateBorder mirroring the enemy nameplate border
    -- exactly. Reads the same enemy border settings (showBorder, borderSize,
    -- borderColor) so friendly plates always match whatever border the user has
    -- configured for enemy plates. Lives on a child container at health level + 1 so it
    -- renders above the mouseover highlight (OVERLAY sublevel 6) and the health fill.
    local PP = EllesmereUI and EllesmereUI.PP
    if PP and PP.CreateBorder then
        local cr, cg, cb = ns.GetBorderColor()
        -- The classic plate's fixed 1px edge, else the friendly profile's own size.
        local sz = ns.NP_Classic() and 1 or ((FP() and FP().borderSize) or ns.defaults.borderSize)
        PP.CreateBorder(plate.health, cr, cg, cb, 1, sz, "OVERLAY", 7, true)  -- scaleGuard: NP frame
        if not ns.IsBorderEnabled() or ns.NP_Classic() then PP.HideBorder(plate.health) end
    end

    function plate:ApplyBorder()
        if not PP then return end
        if ns.NP_Classic() then
            -- Classic WoW UI: the vanilla border art replaces every EUI border.
            PP.HideBorder(plate.health)
            ns.HideCustomBorder(plate)
            ns.NP_ApplyClassicHealthArt(plate, GetFriendlyHealthBarHeight())
            ns.NP_ApplyRounding(plate)
            return
        end
        if ns.IsCustomBorderEnabled() then
            -- Custom border mirrors the enemy custom-border settings 1:1.
            PP.HideBorder(plate.health)
            ns.ApplyCustomBorderStyle(plate)
        else
            ns.HideCustomBorder(plate)
            if ns.IsBorderEnabled() then
                PP.SetBorderSize(plate.health, ns.NP_Classic() and 1 or ((FP() and FP().borderSize) or ns.defaults.borderSize))
                PP.ShowBorder(plate.health)
            else
                PP.HideBorder(plate.health)
            end
        end
        -- WoW Forever: the level box right of the bar, as on the enemy plates.
        if ns._npForever then ns.NP_ApplyForeverLevelBox(plate, GetFriendlyHealthBarHeight()) end
        ns.NP_ApplyRounding(plate)
    end
    function plate:ApplyBorderColor()
        if not PP then return end
        if ns.IsCustomBorderEnabled() then
            ns.ApplyCustomBorderColor(plate)
        else
            local cr, cg, cb = ns.GetBorderColor()
            ns.NP_BasicBorderColor(plate, cr, cg, cb, 1)
        end
    end

    local GLOW_TEX = "Interface\\AddOns\\EllesmereUINameplates\\Media\\background.png"
    local GLOW_MARGIN = 0.48
    local GLOW_CORNER = 12
    local GLOW_EXTEND = 6
    plate.glowFrame = CreateFrame("Frame", nil, plate)
    plate.glowFrame:SetFrameStrata("BACKGROUND")
    plate.glowFrame:SetFrameLevel(1)
    plate.glowFrame:SetPoint("TOPLEFT", plate.health, "TOPLEFT", -GLOW_EXTEND, GLOW_EXTEND)
    plate.glowFrame:SetPoint("BOTTOMRIGHT", plate.health, "BOTTOMRIGHT", GLOW_EXTEND, -GLOW_EXTEND)

    local function CreateGlowTex()
        local t = plate.glowFrame:CreateTexture(nil, "BACKGROUND")
        t:SetTexture(GLOW_TEX)
        t:SetVertexColor(0.4117, 0.6667, 1.0, 1.0)
        t:SetBlendMode("ADD")
        return t
    end

    plate.glowTL = CreateGlowTex()
    plate.glowTL:SetSize(GLOW_CORNER, GLOW_CORNER)
    plate.glowTL:SetPoint("TOPLEFT")
    plate.glowTL:SetTexCoord(0, GLOW_MARGIN, 0, GLOW_MARGIN)
    plate.glowTR = CreateGlowTex()
    plate.glowTR:SetSize(GLOW_CORNER, GLOW_CORNER)
    plate.glowTR:SetPoint("TOPRIGHT")
    plate.glowTR:SetTexCoord(1 - GLOW_MARGIN, 1, 0, GLOW_MARGIN)
    plate.glowBL = CreateGlowTex()
    plate.glowBL:SetSize(GLOW_CORNER, GLOW_CORNER)
    plate.glowBL:SetPoint("BOTTOMLEFT")
    plate.glowBL:SetTexCoord(0, GLOW_MARGIN, 1 - GLOW_MARGIN, 1)
    plate.glowBR = CreateGlowTex()
    plate.glowBR:SetSize(GLOW_CORNER, GLOW_CORNER)
    plate.glowBR:SetPoint("BOTTOMRIGHT")
    plate.glowBR:SetTexCoord(1 - GLOW_MARGIN, 1, 1 - GLOW_MARGIN, 1)
    plate.glowTop = CreateGlowTex()
    plate.glowTop:SetHeight(GLOW_CORNER)
    plate.glowTop:SetPoint("TOPLEFT", plate.glowTL, "TOPRIGHT")
    plate.glowTop:SetPoint("TOPRIGHT", plate.glowTR, "TOPLEFT")
    plate.glowTop:SetTexCoord(GLOW_MARGIN, 1 - GLOW_MARGIN, 0, GLOW_MARGIN)
    plate.glowBottom = CreateGlowTex()
    plate.glowBottom:SetHeight(GLOW_CORNER)
    plate.glowBottom:SetPoint("BOTTOMLEFT", plate.glowBL, "BOTTOMRIGHT")
    plate.glowBottom:SetPoint("BOTTOMRIGHT", plate.glowBR, "BOTTOMLEFT")
    plate.glowBottom:SetTexCoord(GLOW_MARGIN, 1 - GLOW_MARGIN, 1 - GLOW_MARGIN, 1)
    plate.glowLeft = CreateGlowTex()
    plate.glowLeft:SetWidth(GLOW_CORNER)
    plate.glowLeft:SetPoint("TOPLEFT", plate.glowTL, "BOTTOMLEFT")
    plate.glowLeft:SetPoint("BOTTOMLEFT", plate.glowBL, "TOPLEFT")
    plate.glowLeft:SetTexCoord(0, GLOW_MARGIN, GLOW_MARGIN, 1 - GLOW_MARGIN)
    plate.glowRight = CreateGlowTex()
    plate.glowRight:SetWidth(GLOW_CORNER)
    plate.glowRight:SetPoint("TOPRIGHT", plate.glowTR, "BOTTOMRIGHT")
    plate.glowRight:SetPoint("BOTTOMRIGHT", plate.glowBR, "TOPRIGHT")
    plate.glowRight:SetTexCoord(1 - GLOW_MARGIN, 1, GLOW_MARGIN, 1 - GLOW_MARGIN)
    plate.glow = plate.glowFrame
    plate.glowFrame:Hide()

    plate.hpText = plate.health:CreateFontString(nil, "OVERLAY")
    -- Forced crisp outline; SetFSFont applies the global "Never Show Slug" gate.
    SetFSFont(plate.hpText, 10, "OUTLINE, SLUG")
    SyncHealthTextSide(plate)
    -- Blizzard Style: above the deselected overlay / ring (OVERLAY 4/5).
    if ns.NP_Style and ns.NP_Style() == "blizzard" then plate.hpText:SetDrawLayer("OVERLAY", 7) end

    -- Blizzard Style: under the stock ring / deselected overlay (OVERLAY 4/5);
    -- the EUI and classic looks keep it at 6.
    plate.highlight = plate.health:CreateTexture(nil, "OVERLAY", nil, (ns.NP_Style and ns.NP_Style() == "blizzard") and 1 or 6)
    plate.highlight:SetAllPoints()
    local _hc = (FP() and FP().hoverColor) or ns.defaults.hoverColor
    local _ha = (FP() and FP().hoverAlpha) or ns.defaults.hoverAlpha
    plate.highlight:SetColorTexture(_hc.r, _hc.g, _hc.b, _ha)
    plate.highlight:Hide()

    plate.name = plate:CreateFontString(nil, "OVERLAY")
    SetFSFont(plate.name, GetFriendlyNameTextSize(), "OUTLINE, SLUG")
    plate.name:SetPoint("BOTTOM", plate.health, "TOP", 0, 4)
    plate.name:SetWordWrap(false)
    plate.name:SetMaxLines(1)

    -- Below Name sub text (player title / guild). Populated by UpdateSubText;
    -- empty FontStrings render nothing. The name's anchor lifts to make room
    -- when lines are present, so these always sit between name and bar.
    -- Listed for ApplySubtitleFont, which re-applies the subtitle family on
    -- a size / font / slug change; its first font is the current one.
    plate.subText1 = plate:CreateFontString(nil, "OVERLAY")
    ApplySubtitleFont()
    subTexts[#subTexts + 1] = plate.subText1
    EllesmereUI.SetFontFamily(plate.subText1, _sfFile, _sfSize, _sfFlags, false)
    -- Anchored in UpdateSubText against the HEALTH BAR with the same computed number
    -- that positions the name -- never against the name's own rect, which re-derives
    -- from text metrics every render and jitters on a moving plate.
    plate.subText1:SetTextColor(SUB_TEXT_R, SUB_TEXT_G, SUB_TEXT_B)
    plate.subText1:SetWordWrap(false)
    plate.subText1:SetMaxLines(1)

    -- Fully-anchored rects, NOT single point + size: inside the 12.1
    -- restricted plate subtree, point+size regions render DISPLACED. The
    -- name's LEFT/RIGHT relPoint supplies both the edge x and the vertical
    -- center line; the symmetric +/-8 pair renders 16 tall, centered --
    -- identical geometry to the old single-point form on live.
    local _aSt = ns.ResolveTargetArrowStyle(FP())
    plate.leftArrow = plate:CreateTexture(nil, "OVERLAY")
    plate.leftArrow:SetTexture(ns.TARGET_ARROW_DIR .. _aSt.l .. ".png")
    plate.leftArrow:SetWidth(_aSt.w)
    plate._arrowW = _aSt.w
    plate.leftArrow:SetPoint("TOP", plate.name, "LEFT", -(2 + _aSt.w / 2), 8)
    plate.leftArrow:SetPoint("BOTTOM", plate.name, "LEFT", -(2 + _aSt.w / 2), -8)
    plate.leftArrow:Hide()
    plate.rightArrow = plate:CreateTexture(nil, "OVERLAY")
    plate.rightArrow:SetTexture(ns.TARGET_ARROW_DIR .. _aSt.r .. ".png")
    plate.rightArrow:SetWidth(_aSt.w)
    plate.rightArrow:SetPoint("TOP", plate.name, "RIGHT", 2 + _aSt.w / 2, 8)
    plate.rightArrow:SetPoint("BOTTOM", plate.name, "RIGHT", 2 + _aSt.w / 2, -8)
    plate.rightArrow:Hide()

    plate.raidFrame = CreateFrame("Frame", nil, plate)
    plate.raidFrame:SetSize(24, 24)
    plate.raidFrame:SetPoint("BOTTOMRIGHT", plate.health, "TOPRIGHT", 2, 2)
    plate.raidFrame:Hide()
    plate.raid = plate.raidFrame:CreateTexture(nil, "ARTWORK")
    plate.raid:SetPoint("TOPLEFT", 1, -1)
    plate.raid:SetPoint("BOTTOMRIGHT", -1, 1)
    plate.raid:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    plate.raid:SetTexCoord(0, 1, 0, 1)

    if CreateUnitHealPredictionCalculator then
        plate.hpCalculator = CreateUnitHealPredictionCalculator()
        if plate.hpCalculator.SetMaximumHealthMode then
            plate.hpCalculator:SetMaximumHealthMode(Enum.UnitMaximumHealthMode.Default)
        end
    end

    plate:SetScript("OnEvent", function(self, event, ...)
        local handler = self[event]
        if handler then handler(self, ...) end
    end)
end)

-------------------------------------------------------------------------------
--  FriendlyFrame mixin
-------------------------------------------------------------------------------
local FriendlyFrame = {}

-- Seat a raid marker (frame or texture) in the Raid Marker element's slot, with
-- the slot's own X/Y nudges: the friendly plate's marker and the options
-- sample's come from here, so the two cannot drift apart.
function ns.NP_PlaceFriendlyRaidMarker(marker, anchor, pos)
    local sz = ns.GetRaidMarkerSize()
    local xOff, yOff = ns.GetAuraSlotOffsets("raidMarker")
    marker:SetSize(sz, sz)
    marker:ClearAllPoints()
    if pos == "top" then
        marker:SetPoint("BOTTOM", anchor, "TOP", xOff, ns.GetDebuffYOffset() + yOff)
    elseif pos == "left" then
        -- Classic WoW UI: gap off the border art (sized by the friendly bar's
        -- own height), not the bare bar edge.
        marker:SetPoint("RIGHT", anchor, "LEFT", -(ns.GetSideAuraXOffset() + ns.NP_ClassicSide("left", GetFriendlyHealthBarHeight())) + xOff, yOff)
    elseif pos == "right" then
        marker:SetPoint("LEFT", anchor, "RIGHT", ns.GetSideAuraXOffset() + ns.NP_ClassicSide("right", GetFriendlyHealthBarHeight()) + xOff, yOff)
    elseif pos == "topleft" then
        -- Flush with the nameplate's left edge (PP borders inset -> bar corner is
        -- the outer edge; offset 0 = flush). Matches the enemy plate convention.
        marker:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", xOff, yOff)
    elseif pos == "topright" then
        marker:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", xOff, yOff)
    end
end

function FriendlyFrame:SetUnit(unit, nameplate)
    self.unit = unit
    self.nameplate = nameplate
    self:SetParent(nameplate)
    self:ClearAllPoints()
    -- Single center anchor to prevent pixel shimmer when nameplate bounces.
    -- Distance rides the shared friendly baseline lift so full plates and
    -- name-only names sit at the same height (see ns.FRIENDLY_Y_BASE).
    local yOff = ((FP() and FP().friendlyPlateYOffset) or 0) + (ns.FRIENDLY_Y_BASE or 0)
    self:SetPoint("CENTER", nameplate, "CENTER", 0, yOff)
    self:SetSize(1, 1)
    self:SetFrameLevel(nameplate:GetFrameLevel() + 1)
    self:Show()

    -- (Classic WoW UI: the border art is seated by ApplyBorder below.)
    self.health:SetSize(GetFriendlyHealthBarWidth(), GetFriendlyHealthBarHeight())

    -- Suppress Blizzard UF via reparenting (immediate, no OnUpdate needed)
    SuppressBlizzardUF(unit, nameplate)

    self:RegisterUnitEvent("UNIT_HEALTH", unit)
    self:RegisterUnitEvent("UNIT_NAME_UPDATE", unit)
    -- (AFK / DND needs no registration here: ArmStatusTagEvents' frame redraws the
    -- name for both friendly styles from one place.)

    PaintFriendlyColors(self, unit, FP())

    -- A pooled plate may have been released while the side changed.
    SyncHealthTextSide(self)
    self:UpdateHealth()
    self:UpdateName()
    self:UpdateRaidIcon()
    ns.NP_FriendlyFactionRefresh(self)
    -- Re-apply the enemy border settings every spawn: a pooled plate may have
    -- been released while the user changed the border size/color/toggle.
    if self.ApplyBorder then self:ApplyBorder() end
    if self.ApplyBorderColor then self:ApplyBorderColor() end
    -- The base border is back: a recycled plate's target/hover border flags are stale.
    -- ApplyTarget runs after the pair so a plate that spawns as your target keeps the
    -- Target Border Effects instead of losing them to the base repaint.
    self._targetBorderSized, self._fxBorderTinted = nil, nil
    self:ApplyTarget()
    if ns.ApplyHealthBarTexture then ns.ApplyHealthBarTexture(self) end
end

function FriendlyFrame:ClearUnit()
    self:UnregisterAllEvents()
    self.name:SetText("")
    -- Clear sub text only if any was drawn (_subOff 4/nil = already empty).
    -- _subOff itself survives the pool round-trip: the next UpdateSubText
    -- compares against the freshly computed offset, so a stale anchor can
    -- never leak while the feature-off path stays zero-write.
    if self._subOff and self._subOff ~= 4 then
        self.subText1:SetText("")
    end
    -- Restore Blizzard UF before clearing our reference
    if self.unit then RestoreBlizzardUF(self.unit) end
    -- The tag belonged to the unit leaving, so the next occupant recomputes it.
    self._statusTag = nil
    -- Its faction badge lives on the nameplate, not on this frame.
    ns.NP_FriendlyFactionHide(self)
    self.unit = nil
    self.nameplate = nil
    self.glow:Hide()
    if ns.HideHoverEffect then ns.HideHoverEffect(self) else self.highlight:Hide() end
    self.raidFrame:Hide()
    self.leftArrow:Hide()
    self.rightArrow:Hide()
    self:Hide()
    self:SetParent(UIParent)
    self:ClearAllPoints()
end

function FriendlyFrame:UpdateHealth()
    local unit = self.unit
    if not unit then return end
    if self.hpCalculator and self.hpCalculator.GetMaximumHealth then
        UnitGetDetailedHealPrediction(unit, nil, self.hpCalculator)
        self.hpCalculator:SetMaximumHealthMode(Enum.UnitMaximumHealthMode.Default)
        local maxHP = self.hpCalculator:GetMaximumHealth()
        self.health:SetMinMaxValues(0, maxHP)
        self.health:SetValue(self.hpCalculator:GetCurrentHealth())
    else
        self.health:SetMinMaxValues(0, UnitHealthMax(unit))
        self.health:SetValue(UnitHealth(unit))
    end
    if UnitIsDeadOrGhost(unit) then
        self.hpText:SetText("0%")
    elseif UnitHealthPercent then
        local fp = FP()
        if fp and fp.friendlyHideHealthText then
            self.hpText:SetText("")
        else
            self.hpText:SetFormattedText("%d%%", UnitHealthPercent(unit, true, CurveConstants.ScaleTo100))
        end
    else
        self.hpText:SetText("")
    end
end

function FriendlyFrame:UpdateName()
    local unit = self.unit
    if not unit then return end
    -- Title (when the Subtitle Text mode includes it) rides the name as ONE
    -- string via UnitPVPName; everything else shows the plain name. The Name
    -- Format then shortens a player's name. The player test runs only while a
    -- title or a saved format needs it.
    local hasTitle = ModeHasTitle(GetBelowNameMode())
    local fmt = FriendlyNameFormat()
    local showLevel = ShowFriendlyLevel()
    local showGroup = ShowFriendlyGroupBrackets()
    local isPlayer = (hasTitle or fmt or showLevel or showGroup) and UnitIsPlayer(unit)
    local unitName
    if hasTitle and isPlayer then
        unitName = GetTitledName(unit)
    end
    if not unitName then unitName = EllesmereUI.WithSurname(UnitName(unit)) end
    if fmt and isPlayer and unitName then
        unitName = FormatFriendlyName(unit, unitName, hasTitle)
    end
    -- Blizzard's away/busy tag, on the same text and colour as the name. A secret
    -- name cannot be concatenated, so it is left without one.
    local tag
    if unitName and UnitIsPlayer(unit) and not (issecretvalue and issecretvalue(unitName)) then
        tag = PlayerStatusTag(unit)
        if tag then unitName = unitName .. tag end
    end
    self._statusTag = tag
    local gKind = (showGroup and isPlayer) and GetUnitGroupBracketKind(unit) or nil
    self._grpKind = gKind
    local bOpen  = (gKind == "party" and PARTY_BRACKET_OPEN)  or (gKind == "raid" and RAID_BRACKET_OPEN)  or ""
    local bClose = (gKind == "party" and PARTY_BRACKET_CLOSE) or (gKind == "raid" and RAID_BRACKET_CLOSE) or ""
    if showLevel and isPlayer and unitName then
        -- The name may be secret: only ever a display argument.
        self.name:SetFormattedText("%s | " .. bOpen .. "%s" .. bClose, FriendlyLevelText(unit), unitName)
    elseif gKind and unitName then
        self.name:SetFormattedText(bOpen .. "%s" .. bClose, unitName)
    else
        self.name:SetText(unitName or "")
    end
    self:UpdateSubText()
end

-- Below Name sub text: a player's guild line (the title is inline on the name).
-- The name normally hangs 4px above the bar (the pool initializer's base
-- anchor); a populated line reserves extra room under it so it fits between the
-- name and the bar. The name anchor is memoized on the COMPUTED offset (a pure
-- function of line count and line size, its only two inputs), so it
-- self-invalidates on size and mode changes and survives pool round-trips.
-- _subOff == 4 means base anchor + empty text, which is the zero-write fast
-- path while the feature is off.
function FriendlyFrame:UpdateSubText()
    local unit = self.unit
    if not unit then return end
    local lines = 0
    local size = 0
    if ModeHasGuild(GetBelowNameMode()) and UnitIsPlayer(unit) then
        -- The font is ApplySubtitleFont's (set at build and on a change); only
        -- the content and the name-lift offset are per-plate.
        size = GetSubTextSize()
        SetPlateSubTextFont(self.subText1, size)
        lines = ApplySubText(self.subText1, unit)
    elseif self._subOff == 4 then
        return   -- no guild line drawn: nothing to do
    else
        self.subText1:SetText("")
    end
    local off = 4 + lines * (size + 2)
    if off ~= self._subOff then
        self._subOff = off
        -- Both texts hang off the HEALTH BAR (a frame) with computed numbers:
        -- the name's bottom sits at off, so the line's top sits 1px
        -- under it. Chaining the line off the name's rect instead is what
        -- made it jitter on moving plates.
        self.name:SetPoint("BOTTOM", self.health, "TOP", 0, off)
        self.subText1:ClearAllPoints()
        self.subText1:SetPoint("TOP", self.health, "TOP", 0, off - 1)
    end
end

function FriendlyFrame:UpdateRaidIcon()
    if not self.unit then return end
    local pos = ns.GetRaidMarkerPos()
    if pos == "none" then self.raidFrame:Hide(); return end
    local idx = GetRaidTargetIndex and GetRaidTargetIndex(self.unit)
    -- type() is taint-safe: "nil" / "number" without reading a secret index
    if type(idx) == "nil" then self.raidFrame:Hide(); return end
    SetRaidTargetIconTexture(self.raid, idx)
    ns.NP_PlaceFriendlyRaidMarker(self.raidFrame, self.health, pos)
    self.raidFrame:Show()
end

function FriendlyFrame:ApplyTarget()
    if not self.unit then return end
    local isTarget = UnitIsUnit(self.unit, "target")
    self.glow:SetShown(isTarget)
    local fp = FP()
    local showArrows = isTarget and fp and fp.showTargetArrows
    if showArrows then
        local st = ns.ResolveTargetArrowStyle(fp)
        self.leftArrow:SetTexture(ns.TARGET_ARROW_DIR .. st.l .. ".png")
        self.rightArrow:SetTexture(ns.TARGET_ARROW_DIR .. st.r .. ".png")
        local acr, acg, acb = ns.GetTargetArrowColor(fp)
        self.leftArrow:SetVertexColor(acr, acg, acb)
        self.rightArrow:SetVertexColor(acr, acg, acb)
        self.leftArrow:SetSize(st.w, 16)
        self.rightArrow:SetSize(st.w, 16)
        self._arrowW = st.w
    end
    self.leftArrow:SetShown(showArrows or false)
    self.rightArrow:SetShown(showArrows or false)
    -- Blizzard Style: stock selection ring / deselected overlay on friendly plates too.
    if ns.NP_Style and ns.NP_Style() == "blizzard" then ns.NP_ApplyBlizzSelection(self) end
    -- Target Border Effects (friendlyTargetBorderFx, default off): the enemy plate's
    -- target Border Size and Border Color channels, restored on untarget. The hover
    -- effect's target-wins checks (ApplyHoverExtras) read _isTarget and
    -- _targetBorderSized as on enemy plates; _isTarget is cached only while this
    -- feature styles the plate; otherwise hover drives a friendly target's border. Off, only
    -- a plate these flags mark is repainted (the hover Border Color restore included).
    local fx = fp and fp.friendlyTargetBorderFx and isTarget or nil
    self._isTarget = fx
    if fx or self._targetBorderSized or self._fxBorderTinted then
        local PP = EllesmereUI.PP
        local tbsz
        if fx and ns.GetTargetGlowBorderSize() then tbsz = ns.GetTargetBorderSizeValue() end
        if tbsz then
            if ns.IsCustomBorderEnabled() then
                ns.ApplyCustomBorderStyle(self, tbsz)
            elseif ns.IsBorderEnabled() then
                PP.SetBorderSize(self.health, tbsz)
            end
            self._targetBorderSized = true
        elseif self._targetBorderSized then
            self._targetBorderSized = nil
            self:ApplyBorder()
        end
        -- Colour after size: a rebuilt custom border takes the tint right after. A tint only.
        if fx and ns.GetTargetGlowBorderColor() then
            local bc = ns.GetTargetBorderColor()
            if ns.IsCustomBorderEnabled() then
                if not self._customBorder then ns.ApplyCustomBorderStyle(self) end
                EllesmereUI.SetBorderStyleColor(self._customBorder, bc.r, bc.g, bc.b, 1)
            else
                ns.NP_BasicBorderColor(self, bc.r, bc.g, bc.b, 1)
            end
            self._fxBorderTinted = true
        elseif self._fxBorderTinted then
            self._fxBorderTinted = nil
            self:ApplyBorderColor()
        end
    end
end

function FriendlyFrame:UNIT_HEALTH()  self:UpdateHealth() end
function FriendlyFrame:UNIT_NAME_UPDATE()  self:UpdateName() end

-------------------------------------------------------------------------------
--  Friendly event manager (target, mouseover, raid icons)
--  Only registered when friendly plates are active -- zero CPU when disabled.
-------------------------------------------------------------------------------
local friendlyManager = CreateFrame("Frame")
local friendlyManagerRegistered = false

local RegisterFriendlyManager   -- forward declaration
local UnregisterFriendlyManager -- forward declaration

-------------------------------------------------------------------------------
--  Away / busy tag events
--  PLAYER_FLAGS_CHANGED is armed in BOTH friendly styles, since the tag rides
--  either style's name, and only while a Status Tag is on: the tag is the
--  one reader, so nothing here is registered while it is off. This is a frame
--  of its own because the health-bar manager above is only registered in that
--  style, while Name Only composes the name through Blizzard's own FontString.
--  Armed from ns.UpdateFriendlyNameplateSystem. A global UNIT_FLAGS is not
--  needed (and is far too broad): the client reports a player's flag with
--  PLAYER_FLAGS_CHANGED.
-------------------------------------------------------------------------------
local statusManager = CreateFrame("Frame")
local statusManagerArmed = false

local function ArmStatusTagEvents(on)
    on = on and true or false
    if on == statusManagerArmed then return end
    statusManagerArmed = on
    if on then
        statusManager:RegisterEvent("PLAYER_FLAGS_CHANGED")
    else
        statusManager:UnregisterAllEvents()
    end
end

statusManager:SetScript("OnEvent", function(_, _, unit)
    RefreshStatusTags(unit)
end)

-------------------------------------------------------------------------------
--  Add / Remove helpers
-------------------------------------------------------------------------------
local function ClearAllFriendlyPlates()
    for unit, plate in pairs(friendlyPlates) do
        plate:ClearUnit()
        friendlyFrameCache:Release(plate)
        friendlyPlates[unit] = nil
    end
end

local function TryAddFriendlyPlate(unit)
    -- Auto-enable on first call if DB says we should be active but the
    -- runtime flag hasn't been set yet (happens when NAME_PLATE_UNIT_ADDED
    -- fires before PLAYER_LOGIN).
    if not friendlyEnabled then
        if IsFriendlyEnabled() then
            friendlyEnabled = true
            RegisterFriendlyManager()
        else
            return
        end
    end
    if UnitCanAttack("player", unit) then return end
    if UnitIsUnit(unit, "player") then return end
    -- Skip non-player units unless friendly NPC plates are enabled (and the unit
    -- isn't filtered out by Blizzard's "NPC Names" setting).
    if not UnitIsPlayer(unit) and not IsFriendlyNPCShownForUnit(unit) then return end
    local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
    if not nameplate then return end
    if friendlyPlates[unit] then return end

    local plate = friendlyFrameCache:Acquire()
    if not plate._mixedIn then
        Mixin(plate, FriendlyFrame)
        plate._mixedIn = true
    end
    friendlyPlates[unit] = plate
    plate:SetUnit(unit, nameplate)
end
ns.TryAddFriendlyPlate = TryAddFriendlyPlate

function ns.RemoveFriendlyPlate(unit)
    local plate = friendlyPlates[unit]
    if not plate then return end
    if ns._ClearMouseoverPlate then ns._ClearMouseoverPlate(plate) end
    if _cachedFriendlyTargetPlate == plate then _cachedFriendlyTargetPlate = nil end
    plate:ClearUnit()
    friendlyFrameCache:Release(plate)
    friendlyPlates[unit] = nil
end

-- Same as RemoveFriendlyPlate but does NOT restore the Blizzard UF.
-- Used when promoting friendly -> enemy so the Blizzard UF stays suppressed
-- until HideBlizzardFrame takes over in the enemy plate's SetUnit.
function ns.RemoveFriendlyPlateNoRestore(unit)
    local plate = friendlyPlates[unit]
    if not plate then return end
    if ns._ClearMouseoverPlate then ns._ClearMouseoverPlate(plate) end
    if _cachedFriendlyTargetPlate == plate then _cachedFriendlyTargetPlate = nil end
    -- Clean up our plate without restoring Blizzard UF
    plate:UnregisterAllEvents()
    plate.name:SetText("")
    if plate._subOff and plate._subOff ~= 4 then
        plate.subText1:SetText("")
    end
    -- Hand the park record over so the friendly suppression hooks stop
    -- interfering (the enemy plate takes the frame's suppression from here).
    local rec = suppressedByUnit[unit]
    if rec then suppressedByUnit[unit] = nil end
    if rec and suppressedUFs[rec.uf] == rec then suppressedUFs[rec.uf] = nil end
    -- Promoted to an enemy plate, which draws its own faction badge.
    ns.NP_FriendlyFactionHide(plate)
    plate.unit = nil
    plate._statusTag = nil
    plate.nameplate = nil
    plate.glow:Hide()
    if ns.HideHoverEffect then ns.HideHoverEffect(plate) else plate.highlight:Hide() end
    plate.raidFrame:Hide()
    plate.leftArrow:Hide()
    plate.rightArrow:Hide()
    plate:Hide()
    plate:SetParent(UIParent)
    plate:ClearAllPoints()
    friendlyFrameCache:Release(plate)
    friendlyPlates[unit] = nil
end

-------------------------------------------------------------------------------
--  Friendly event manager function definitions
-------------------------------------------------------------------------------
function RegisterFriendlyManager()
    if friendlyManagerRegistered then return end
    friendlyManager:RegisterEvent("PLAYER_TARGET_CHANGED")
    friendlyManager:RegisterEvent("RAID_TARGET_UPDATE")
    -- Someone went away or busy: ns.ArmStatusTagEvents' frame owns those events
    -- in both friendly styles, so the name text is redrawn there.
    friendlyManagerRegistered = true
end

function UnregisterFriendlyManager()
    if not friendlyManagerRegistered then return end
    friendlyManager:UnregisterAllEvents()
    friendlyManagerRegistered = false
end

friendlyManager:SetScript("OnEvent", function(self, event, unit)
    if event == "PLAYER_TARGET_CHANGED" then
        -- PERF: only update old + new target instead of iterating all
        local oldTarget = _cachedFriendlyTargetPlate
        _cachedFriendlyTargetPlate = nil
        for _, plate in pairs(friendlyPlates) do
            if plate.unit and UnitIsUnit(plate.unit, "target") then
                _cachedFriendlyTargetPlate = plate
                break
            end
        end
        if oldTarget and oldTarget.unit then oldTarget:ApplyTarget() end
        if _cachedFriendlyTargetPlate and _cachedFriendlyTargetPlate ~= oldTarget then
            _cachedFriendlyTargetPlate:ApplyTarget()
        end
    elseif event == "RAID_TARGET_UPDATE" then
        for _, plate in pairs(friendlyPlates) do plate:UpdateRaidIcon() end
    end
end)

-------------------------------------------------------------------------------
--  Live refresh of friendly plate Y offset
-------------------------------------------------------------------------------
function ns.RefreshFriendlyPlateYOffset()
    -- Same baseline lift as the spawn path (see ns.FRIENDLY_Y_BASE).
    local yOff = ((FP() and FP().friendlyPlateYOffset) or 0) + (ns.FRIENDLY_Y_BASE or 0)
    for _, plate in pairs(friendlyPlates) do
        if plate.nameplate then
            plate:ClearAllPoints()
            plate:SetPoint("CENTER", plate.nameplate, "CENTER", 0, yOff)
        end
    end
end

-------------------------------------------------------------------------------
--  Live refresh of friendly plate size (height / width)
-------------------------------------------------------------------------------
function ns.RefreshFriendlyPlateSize()
    local h = GetFriendlyHealthBarHeight()
    local w = GetFriendlyHealthBarWidth()
    -- Classic WoW UI: the vanilla border scales with the bar, so it re-seats
    -- with every size change (the seat memoizes, so an unchanged size is free).
    local classic = ns.NP_Classic()
    local forever = ns.NP_Forever()
    for _, plate in pairs(friendlyPlates) do
        plate.health:SetSize(w, h)
        if classic then
            ns.NP_ApplyClassicHealthArt(plate, h)
            -- A side raid marker gaps off the border, which moved with it.
            plate:UpdateRaidIcon()
        elseif forever then
            -- WoW Forever: the level box follows the bar's height.
            ns.NP_ApplyForeverLevelBox(plate, h)
        end
    end
end

-- WoW Forever's Show Level Box flipped (ns.RefreshAllSettings): each shown
-- friendly plate gains or parks its box, and a side raid marker re-gaps off
-- the bar. A pooled plate catches up through its next ApplyBorder.
function ns.NP_ForeverFriendlyBoxes()
    local h = GetFriendlyHealthBarHeight()
    for _, plate in pairs(friendlyPlates) do
        ns.NP_ApplyForeverLevelBox(plate, h)
        plate:UpdateRaidIcon()
    end
end

function ns.RefreshFriendlyHealthText()
    for _, plate in pairs(friendlyPlates) do
        SyncHealthTextSide(plate)
        plate:UpdateHealth()
    end
end

-- A profile or override flip of the health percent's side reaches the live
-- plates (one compare each while it is unchanged).
function ns.NP_SyncFriendlyHealthTextSide()
    for _, plate in pairs(friendlyPlates) do
        SyncHealthTextSide(plate)
    end
end

-- Repaints every live full plate's bar and name (colour settings, the class
-- palette, profile switches), the same way the spawn path paints them.
-- paletteChanged: the class palette moved, so a Class Colored guild line
-- (either friendly mode) is repainted too.
function ns.RefreshFriendlyColors(paletteChanged)
    -- Class Colored Health Bar decides whether the group tint can show
    ns.NP_FriendlyGroupWatch()
    local fp = FP()
    for unit, plate in pairs(friendlyPlates) do
        PaintFriendlyColors(plate, unit, fp)
    end
    if paletteChanged and fp and fp.friendlyBelowNameClassColor then
        ns.RefreshFriendlyBelowName()
    end
end

-- Re-apply the full-plate friendly name text size to all live plates so the
-- slider updates without a /reload. The name carries an explicit outline flag.
function ns.RefreshFriendlyNameTextSize()
    local size = GetFriendlyNameTextSize()
    for _, plate in pairs(friendlyPlates) do
        if plate.name then SetFSFont(plate.name, size, "OUTLINE, SLUG") end
    end
end

-- Show Level: a friendly player's level-up repaints that plate's name, and
-- with Color Level by Difficulty your own level-up repaints them all (the
-- colours rank against your level). The event frame registers only while
-- Show Level is on (armed from the settings refresh and the system pass), so
-- it costs nothing while it is off.
do
    local levelEv, armed
    local function RepaintUnit(unit)
        local plate = friendlyPlates[unit]
        if plate then plate:UpdateName(); return end
        local nameplate = ns.pendingUnits and ns.pendingUnits[unit]
        local uf = nameplate and nameplate.UnitFrame
        if uf and uf.name and nameFSUnits[uf.name] == unit then
            nameFSText[uf.name] = nil
            UpdateNameOnlyText(uf.name)
        end
    end
    function ns.NP_FriendlyLevelWatch()
        local want = (ShowFriendlyLevel() and (FriendlyLevelDiffColor() and 2 or 1)) or 0
        if want == (armed or 0) then return end
        armed = want
        if levelEv then levelEv:UnregisterAllEvents() end
        if want == 0 then return end
        if not levelEv then
            levelEv = CreateFrame("Frame")
            levelEv:SetScript("OnEvent", function(_, event, unit)
                if event == "PLAYER_LEVEL_CHANGED" then
                    for u in pairs(friendlyPlates) do RepaintUnit(u) end
                    local pending = ns.pendingUnits
                    if pending then
                        for u in pairs(pending) do
                            if not friendlyPlates[u] then RepaintUnit(u) end
                        end
                    end
                    return
                end
                if not unit or not unit:find("^nameplate") then return end
                RepaintUnit(unit)
            end)
        end
        levelEv:RegisterEvent("UNIT_LEVEL")
        if want == 2 then levelEv:RegisterEvent("PLAYER_LEVEL_CHANGED") end
    end
end

-- A roster change (a member joining or leaving, a raid subgroup move) can change a
-- name's bracket (Show [] Around Group/Raid) and, under the WoW Forever style with
-- Class Colored Health Bar off, a bar's group tint. GROUP_ROSTER_UPDATE comes in
-- bursts, so the event only shows a hidden frame; one pass on the next frame
-- repaints the names whose bracket changed and the bars whose tint changed, and
-- leaves every other plate alone. The event is registered only while one of the
-- two can show: `armed` is 1 for the brackets plus 2 for the tint.
-- The tint also follows the member's PvP flag (lighter blue off, lighter green on),
-- and the flag moves without a roster change: while the tint can show, UNIT_FACTION
-- marks the tinted plate it names, and the same next-frame pass repaints it. A pass
-- with only such marks repaints the marked plates alone; the whole roster is read
-- again only after a roster event.
do
    local groupEv, armed
    local rosterDirty = false
    local factionDirty = {}
    local function Flush(self)
        self:Hide()
        local brackets, tint = armed == 1 or armed == 3, armed >= 2
        local fp = tint and FP()
        if not rosterDirty then
            if tint then
                for unit in pairs(factionDirty) do
                    local plate = friendlyPlates[unit]
                    if plate then PaintFriendlyColors(plate, unit, fp) end
                end
            end
            wipe(factionDirty)
            return
        end
        rosterDirty = false
        for unit, plate in pairs(friendlyPlates) do
            if brackets then
                local kind = UnitIsPlayer(unit) and GetUnitGroupBracketKind(unit) or nil
                if kind ~= plate._grpKind then plate:UpdateName() end
            end
            if tint and (factionDirty[unit]
                or ((UnitIsPlayer(unit) and InMyGroup(unit)) and true or false) ~= (plate._grpTint == true)) then
                PaintFriendlyColors(plate, unit, fp)
            end
        end
        wipe(factionDirty)
        if not brackets then return end
        local pending = ns.pendingUnits
        if not pending then return end
        for unit, nameplate in pairs(pending) do
            local uf = nameplate.UnitFrame
            local fs = uf and uf.name
            if fs and nameFSUnits[fs] == unit then
                local st = nameFSText[fs]
                if (st and st.grp or nil) ~= GetUnitGroupBracketKind(unit) then
                    UpdateNameOnlyText(fs)
                end
            end
        end
    end
    function ns.NP_FriendlyGroupWatch()
        local want = ShowFriendlyGroupBrackets() and 1 or 0
        local fp = FP()
        if fp and fp.classColorFriendly == false and ns.NP_Forever() then want = want + 2 end
        local was = armed or 0
        if want == was then return end
        armed = want
        if want == 0 then
            groupEv:UnregisterAllEvents()
            groupEv:Hide()
            rosterDirty = false
            wipe(factionDirty)
            return
        end
        if not groupEv then
            groupEv = CreateFrame("Frame")
            groupEv:Hide()
            groupEv:SetScript("OnEvent", function(self, event, unit)
                if event == "UNIT_FACTION" then
                    -- only a tinted full plate can go stale
                    local plate = unit and friendlyPlates[unit]
                    if not (plate and plate._grpTint) then return end
                    factionDirty[unit] = true
                else
                    rosterDirty = true
                end
                self:Show()
            end)
            groupEv:SetScript("OnUpdate", Flush)
        end
        -- the PvP flag event follows the tint alone, registered or dropped only when that changes
        if (want >= 2) ~= (was >= 2) then
            if want >= 2 then
                groupEv:RegisterEvent("UNIT_FACTION")
            else
                groupEv:UnregisterEvent("UNIT_FACTION")
                wipe(factionDirty)
            end
        end
        -- already listening: a pass that is waiting for its frame runs with the new set
        if was ~= 0 then return end
        groupEv:RegisterEvent("GROUP_ROSTER_UPDATE")
    end
end

-- Live-apply a Subtitle Text setting change (mode / size / color) from the
-- options panel, in whichever friendly mode is active.
function ns.RefreshFriendlyBelowName()
    -- Size / font / slug: the subtitle family on every built sub text.
    ApplySubtitleFont()
    ns.NP_FriendlyLevelWatch()
    ns.NP_FriendlyGroupWatch()
    -- Full-plate mode: repaint the name (the title is part of it now) plus
    -- the guild line and name lift on live plates.
    for _, plate in pairs(friendlyPlates) do
        plate:UpdateName()
    end
    -- Name-only mode: recompose the name text on visible player plates
    -- (self-gated; a no-op outside name-only mode).
    SweepPlayerSubText()
    -- The names now show these settings (the Name Format sync's record).
    StampFriendlyNames()
end

-------------------------------------------------------------------------------
--  Friendly nameplate click-through
--  Make friendly nameplates (players AND NPCs) non-clickable so their names
--  never intercept mouse input or cause accidental friendly targeting. We do
--  NOT resize the plate (which would distort visuals) -- instead we shrink the
--  click hit-test rectangle to nothing via a large positive inset on every
--  edge. Turned off, the friendly insets are the sizing pass's again
--  (ns.RefreshHitboxSize, which calls back here while the option is on).
--  The hit-test API is protected in combat, so we gate on InCombatLockdown and
--  retry once on combat end through the module combat queue, which costs
--  nothing while no change is pending.
-------------------------------------------------------------------------------
local CLICK_THROUGH_INSET = 10000
local clickThroughApplied = false

local function ApplyFriendlyClickThrough()
    if not (C_NamePlateManager and C_NamePlateManager.SetNamePlateHitTestInsets
            and Enum and Enum.NamePlateType) then
        return
    end
    local fp = FP()
    local on = fp and fp.friendlyClickThrough == true
    -- Never applied and feature is off: leave Blizzard's hit rect untouched.
    if not on and not clickThroughApplied then return end
    if InCombatLockdown() then
        ns.CombatQueue.Defer("FriendlyClickThrough", ApplyFriendlyClickThrough)
        return
    end
    if not on then
        -- The flag first: the sizing pass ends by calling this function.
        clickThroughApplied = false
        ns.RefreshHitboxSize()
        return
    end
    local inset = CLICK_THROUGH_INSET
    C_NamePlateManager.SetNamePlateHitTestInsets(Enum.NamePlateType.Friendly, inset, inset, inset, inset)
    clickThroughApplied = true
end
ns.UpdateFriendlyClickThrough = ApplyFriendlyClickThrough

-------------------------------------------------------------------------------
--  Friendly player visibility CVars
--
--  nameplateShowFriends / nameplateShowFriendlyPlayers PERSIST across sessions
--  on Blizzard's side, so re-asserting them on every login can only ever
--  override the user -- anyone who deliberately hid friendly nameplates in
--  Blizzard's own Nameplate settings got them back every session. EUI now
--  forces them ON only at moments of explicit intent: the first install, and
--  the two picks that mean "I want friendly plates" (Friendly Nameplate Style
--  taken off Blizzard Default, or set to Name Only). Every other path reads
--  the CVars and leaves them alone.
--
--  The CVar was renamed along the way: current clients register
--  nameplateShowFriendlyPlayers, older ones nameplateShowFriends, and reading
--  a name the client does not register just gives nil. Writes go to both (the
--  dead one is a harmless no-op), but the READ has to come from whichever is
--  live -- a nil read used to be recorded as "the user had them hidden" and
--  then handed back as 0 on the way out of a follower dungeon, which is what
--  left friendly nameplates switched off after a delve.
-------------------------------------------------------------------------------
local FRIENDLY_VIS_CVARS = { "nameplateShowFriendlyPlayers", "nameplateShowFriends" }
local _liveVisCVar   -- resolved lazily; nil until a name reads back

--- The visibility CVar this client actually registers, or nil if neither
--- answers yet. Resolved on first successful read and cached, so it never runs
--- before the CVar system is up and costs nothing afterwards.
local function LiveFriendlyVisCVar()
    if _liveVisCVar then return _liveVisCVar end
    if not GetCVar then return nil end
    for i = 1, #FRIENDLY_VIS_CVARS do
        local ok, v = pcall(GetCVar, FRIENDLY_VIS_CVARS[i])
        if ok and v ~= nil then
            _liveVisCVar = FRIENDLY_VIS_CVARS[i]
            return _liveVisCVar
        end
    end
    return nil
end

--- Force friendly player plates visible. Also drops any pending follower
--- dungeon capture: an explicit "show them" must not be undone later by a
--- restore that was queued before the user changed their mind.
function ns.ForceFriendlyPlayerCVarsOn()
    for i = 1, #FRIENDLY_VIS_CVARS do
        pcall(EllesmereUI.SetCVar, FRIENDLY_VIS_CVARS[i], 1, "EllesmereUINameplates")
    end
    if EllesmereUIDB then EllesmereUIDB.friendlyPlateVisSaved = nil end
end

--- Follower dungeons force friendly plates off, so we have to remember what
--- the user actually had and hand exactly that back on exit -- assuming "on"
--- is what re-showed plates for people who had hidden them. Persisted rather
--- than runtime-only because the player can log out inside the dungeon, and a
--- lost capture would strand their preference off.
--- Returns true once there is a capture on file to hand back later.
local function CaptureFriendlyVis()
    if not EllesmereUIDB then return false end
    if EllesmereUIDB.friendlyPlateVisSaved ~= nil then return true end
    local cvar = LiveFriendlyVisCVar()
    if not cvar then return false end   -- can't read it: don't guess, don't hide
    local cur = GetCVar(cvar)
    EllesmereUIDB.friendlyPlateVisSaved = (cur == "1" or cur == 1) and 1 or 0
    return true
end

local function RestoreFriendlyVis()
    if not EllesmereUIDB then return end
    local saved = EllesmereUIDB.friendlyPlateVisSaved
    if saved == nil then return end   -- nothing of ours to undo: leave them alone
    EllesmereUIDB.friendlyPlateVisSaved = nil
    for i = 1, #FRIENDLY_VIS_CVARS do
        pcall(EllesmereUI.ReleaseCVar, FRIENDLY_VIS_CVARS[i], saved, "EllesmereUINameplates")
    end
end

-------------------------------------------------------------------------------
--  System enable / disable  (called from toggle setValue and on login)
-------------------------------------------------------------------------------
-- The bootstrap frame below; the pass arms two of its events only while they
-- can paint (see TargetEventsWanted / GuildLineInUse).
local initFrame

-- The guild line under a friendly name: the Name Only text and the health bar
-- plate both draw it, so the event that fills it in late is armed while either
-- style can show it.
local function GuildLineInUse()
    if not ModeHasGuild(GetBelowNameMode()) then return false end
    return IsNameOnlyMode() or IsFriendlyEnabled()
end

-- The target and mouseover events here answer the away/busy tag alone, armed
-- only while it can paint. The NPC overlay's target and hover passes run from
-- the nameplate manager in EUI_Nameplates_Events.lua, which hears both events
-- anyway (and the hover's end, which has no event).
local function TargetEventsWanted()
    return ShowStatusTag()
end

-- Arms the three event surfaces this file owns beyond the plate managers: the
-- away/busy flags listener, and the bootstrap frame's target/hover and roster
-- events. Compares and profile reads while nothing changes, so any settings
-- pass (option, profile, override) can call it.
local targetEventsArmed, guildEventArmed = false, false
function ns.RefreshFriendlyTagWatch()
    local fp = FP()
    local shown = fp ~= nil and fp.showFriendlyPlayers ~= false
    ArmStatusTagEvents(shown and (IsNameOnlyMode() or IsFriendlyEnabled()) and ShowStatusTag())
    if not initFrame then return end
    local targets = TargetEventsWanted()
    if targets ~= targetEventsArmed then
        targetEventsArmed = targets
        if targets then
            initFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
            initFrame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
        else
            initFrame:UnregisterEvent("PLAYER_TARGET_CHANGED")
            initFrame:UnregisterEvent("UPDATE_MOUSEOVER_UNIT")
        end
    end
    -- The guild line resolves per unit, not on a roster sweep.
    local guild = GuildLineInUse()
    if guild ~= guildEventArmed then
        guildEventArmed = guild
        if guild then
            initFrame:RegisterEvent("PLAYER_GUILD_UPDATE")
        else
            initFrame:UnregisterEvent("PLAYER_GUILD_UPDATE")
        end
    end
end

function ns.UpdateFriendlyNameplateSystem()
    local shouldEnable = IsFriendlyEnabled()       -- health-bar mode
    local nameOnly     = IsNameOnlyMode()           -- name-only mode

    -- Re-derive the subtitle font (login profile load, profile switches,
    -- slug toggles). Value-memoized, near-free when unchanged.
    ApplySubtitleFont()
    ns.NP_FriendlyLevelWatch()
    ns.NP_FriendlyGroupWatch()

    -- In follower dungeons, force-hide friendly nameplates via CVars. In instances
    -- (dungeons/raids/scenarios/arenas/PvP), force-hide friendly NPC nameplates
    -- because GetNamePlateForUnit returns nil for protected frames and our
    -- suppression can't run. SetCVar for nameplate CVars is protected in combat; skip
    -- to avoid taint and re-run the pass on PLAYER_REGEN_ENABLED so nothing is lost.
    -- Friendly player CVars are only touched when the user has EUI managing friendly
    -- player nameplates. When disabled we leave those CVars alone so Blizzard's own
    -- Nameplate settings own them. Friendly NPC CVars are always managed because they
    -- have their own EUI toggle. The pet and minion CVars are NOT written here: the
    -- client defaults them on, so writing them on every login or zone-in would hide
    -- minion plates for nearly everyone. They follow the two pet toggles instead
    -- (ns.ApplyPetCVars).
    if not InCombatLockdown() then
        local fp = FP()
        local euiManagesPlayers = fp and (fp.showFriendlyPlayers ~= false)
        local _, iType = GetInstanceInfo()
        local inInstance = (iType == "party" or iType == "raid" or iType == "scenario" or iType == "arena" or iType == "pvp")
        if IsInFollowerDungeon() then
            -- Only hide them once the pre-change value is safely on file.
            -- Hiding without a capture has no matching restore, so the plates
            -- would never come back.
            if euiManagesPlayers and CaptureFriendlyVis() then
                pcall(EllesmereUI.HoldCVar, "nameplateShowFriendlyPlayers", 0, "EllesmereUINameplates")
                pcall(EllesmereUI.HoldCVar, "nameplateShowFriends", 0, "EllesmereUINameplates")
            end
            pcall(EllesmereUI.SetCVar, "nameplateShowFriendlyNPCs", 0, "EllesmereUINameplates")
            pcall(EllesmereUI.SetCVar, "nameplateShowFriendlyNpcs", 0, "EllesmereUINameplates")
        elseif inInstance then
            -- NPC plates only: force off in instances since our frame
            -- suppression doesn't work on protected nameplate frames.
            -- Player visibility is not forced here, but a capture taken in a
            -- follower dungeon still has to be handed back: zoning straight
            -- from a delve into a dungeon never touches the open-world branch
            -- below, and the plates would stay hidden for the whole run.
            if euiManagesPlayers then
                RestoreFriendlyVis()
                -- Name-only is presentation, not visibility, so it is asserted here as
                -- well as in the open-world branch. Leaving it out let the health bars
                -- return on zone-in and stay for the whole instance, since nothing else
                -- rewrites this CVar until the player is back outside.
                -- Name Only in Instances turns the Nameplate style's plates into
                -- names here; the open-world branch hands the style back on exit.
                pcall(EllesmereUI.SetCVar, "nameplateShowOnlyNameForFriendlyPlayerUnits",
                    ns.FriendlyNameOnlyNow(fp) and 1 or 0, "EllesmereUINameplates")
            end
            pcall(EllesmereUI.SetCVar, "nameplateShowFriendlyNPCs", 0, "EllesmereUINameplates")
            pcall(EllesmereUI.SetCVar, "nameplateShowFriendlyNpcs", 0, "EllesmereUINameplates")
        else
            -- Restore user's preferred friendly CVar state
            if fp then
                local showNPCs = (fp.showFriendlyNPCs == true)
                if euiManagesPlayers then
                    local nameOnlyVal = (fp.friendlyNameOnly ~= false) and 1 or 0
                    -- Hand back only what a follower dungeon took. Outside that
                    -- case visibility is the user's to own, so nothing is written.
                    RestoreFriendlyVis()
                    pcall(EllesmereUI.SetCVar, "nameplateShowOnlyNameForFriendlyPlayerUnits", nameOnlyVal, "EllesmereUINameplates")
                end
                pcall(EllesmereUI.SetCVar, "nameplateShowFriendlyNPCs", showNPCs and 1 or 0, "EllesmereUINameplates")
                pcall(EllesmereUI.SetCVar, "nameplateShowFriendlyNpcs", showNPCs and 1 or 0, "EllesmereUINameplates")
            end
        end
    else
        -- A zone transition that lands mid-combat drops the whole visibility
        -- pass. Without a retry that silently strands a follower-dungeon
        -- capture unclaimed and leaves friendly plates hidden until the next
        -- transition, so re-run it once combat ends.
        ns.CombatQueue.Defer("FriendlyVisibility", ns.UpdateFriendlyNameplateSystem)
    end

    -- Name Only: a plate we no longer hold goes back to Blizzard now, so turning
    -- a nameplate toggle off never leaves a plate parked with nobody asking for it
    -- (the CVar pass above can take a plate away a frame later).
    if nameOnly and next(suppressedNPCPlates) ~= nil then ReleaseUnclaimedNPCOverlays() end

    if shouldEnable and not friendlyEnabled then
        -- Switching TO health-bar mode
        RestoreFriendlyFontOverride()               -- undo any font override
        -- Clean up any name-only NPC overlays. The player name-only text
        -- needs no teardown: full-plate mode suppresses the Blizzard UF
        -- entirely, so its FontString is not rendered.
        for np in pairs(suppressedNPCPlates) do
            local u = GetNamePlateUnitToken(np)
            RestoreNPCNameplate(np, u)
        end
        friendlyEnabled = true
        RegisterFriendlyManager()
        -- Pick up any nameplates already visible.
        local units = {}
        if ns.pendingUnits then
            for unit, _ in pairs(ns.pendingUnits) do
                units[unit] = true
            end
        end
        local allPlates = C_NamePlate.GetNamePlates()
        if allPlates then
            for _, nameplate in ipairs(allPlates) do
                local unit = GetNamePlateUnitToken(nameplate)
                if unit then units[unit] = true end
            end
        end
        for unit, _ in pairs(units) do
            TryAddFriendlyPlate(unit)
        end
    elseif shouldEnable and friendlyEnabled then
        -- Already in health-bar mode -- re-sweep to pick up NPC plates that
        -- may have been skipped (e.g. user just toggled showFriendlyNPCs on)
        local allPlates = C_NamePlate.GetNamePlates()
        if allPlates then
            for _, nameplate in ipairs(allPlates) do
                local unit = GetNamePlateUnitToken(nameplate)
                if unit then TryAddFriendlyPlate(unit) end
            end
        end
    elseif not shouldEnable and friendlyEnabled then
        -- Switching FROM health-bar mode
        friendlyEnabled = false
        UnregisterFriendlyManager()
        ClearAllFriendlyPlates()
        -- Clean up any leftover NPC overlays from name-only mode
        for np in pairs(suppressedNPCPlates) do
            local u = GetNamePlateUnitToken(np)
            RestoreNPCNameplate(np, u)
        end
    end

    -- Name-only font override: apply when name-only AND friendly plates are shown
    local _fp = FP()
    local showFriendly = _fp and _fp.showFriendlyPlayers ~= false
    -- Away / busy: the tag rides the name in either style, so these events are
    -- armed whenever friendly player names are ours to write -- Name Only
    -- included, where the health-bar manager above stays unregistered -- and
    -- only while something reads them (see ns.RefreshFriendlyTagWatch).
    ns.RefreshFriendlyTagWatch()
    -- Class-colour CVar for the friendly player names Blizzard draws: every name
    -- in name-only mode, the protected instance plates in full-plate mode. A
    -- combat skip is caught by the visibility retry above.
    if (nameOnly or shouldEnable) and not InCombatLockdown() then
        pcall(EllesmereUI.SetCVar, "nameplateUseClassColorForFriendlyPlayerUnitNames", ns.FriendlyNameClassCVar(_fp), "EllesmereUINameplates")
    end
    if nameOnly and showFriendly then
        ApplyFriendlyFontOverride()
        -- (nameplate sizing handled by Blizzard in name-only mode)
        -- Sweep name-only plates. NPCs: suppress health bars and color names green,
        -- gated per-unit so Blizzard's "NPC Names" filter is respected -- widgets-only
        -- NPCs are left to Blizzard instead of getting our overlay. Players ride
        -- SweepPlayerSubText (protected-plate list) for the Below Name sub text.
        local function SweepNameOnlyPlates()
            local allPlates = C_NamePlate.GetNamePlates()
            if allPlates then
                for _, nameplate in ipairs(allPlates) do
                    local u = GetNamePlateUnitToken(nameplate)
                    -- Attackable plates are the enemy system's: never even look.
                    if u and not UnitCanAttack("player", u) and not UnitIsUnit(u, "player")
                        and not UnitIsPlayer(u) then
                        RefreshNPCOverlay(nameplate, u)
                    end
                end
            end
            SweepPlayerSubText()
        end
        SweepNameOnlyPlates()
        -- Delayed sweep: Blizzard creates NPC plates asynchronously after
        -- the CVar changes, so sweep again after a short delay.
        C_Timer.After(0.1, SweepNameOnlyPlates)
        C_Timer.After(0.5, SweepNameOnlyPlates)
    elseif not shouldEnable then
        -- Not in health-bar mode -- restore fonts (covers disabled + name-only-off)
        RestoreFriendlyFontOverride()
        -- Nothing here paints these plates any more: no guild line is left under
        -- Blizzard's own name.
        ClearAllNameOnlySubs()
    end

    -- Apply friendly click-through (independent of player/NPC plate mode).
    ApplyFriendlyClickThrough()
end

-------------------------------------------------------------------------------
--  Bootstrap -- wait for DB then enable system
--  PLAYER_LOGIN enables the system; PLAYER_ENTERING_WORLD does a follow-up
--  sweep because some friendly nameplates may not be queryable yet at
--  PLAYER_LOGIN time (the world isn't fully loaded).
-- Re-sweep after NamePlateDriverFrame.UpdateNamePlateOptions fires.
-- TRP3 hooks this and calls UpdateAllNamePlates which can reset our
-- suppression on friendly plates. Debounced to batch multiple calls.
if C_AddOns.IsAddOnLoaded("totalRP3") or C_AddOns.DoesAddOnExist("totalRP3") then
    local _npOptsPending = false
    hooksecurefunc(NamePlateDriverFrame, "UpdateNamePlateOptions", function()
        if _npOptsPending then return end
        _npOptsPending = true
        C_Timer.After(0, function()
            _npOptsPending = false
            ns.UpdateFriendlyNameplateSystem()
        end)
    end)
end

-- Blizzard re-applies the default nameplate font whenever UpdateNamePlateOptions
-- fires (CVar / display / nameplate-options changes), wiping our name-only size.
-- Re-assert it for everyone (the TRP3 branch above only runs when TRP3 is loaded).
-- Font objects only -- safe, debounced, no CVar feedback.
if NamePlateDriverFrame and NamePlateDriverFrame.UpdateNamePlateOptions then
    hooksecurefunc(NamePlateDriverFrame, "UpdateNamePlateOptions", function()
        ScheduleNameSizeReapply(IsInInstance())
    end)
end

-------------------------------------------------------------------------------
-- Whether the "Recently Played With" bookkeeping can matter: with its entry
-- off, the group roster is not tracked at all.
local function RecentTrackingOn()
    local fp = FP()
    return fp ~= nil and fp.nameOnlyCustomEnabled_FRIENDLY_PLAYER_RECENT == true
end

initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
initFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
initFrame:SetScript("OnEvent", function(self, event, unit)
    if event == "PLAYER_TARGET_CHANGED" or event == "UPDATE_MOUSEOVER_UNIT" then
        -- The client reports a player's away/busy flag for the units it tracks,
        -- so a target or hover is the moment a stranger's plate can catch up.
        if ShowStatusTag() then
            RefreshStatusTags(event == "UPDATE_MOUSEOVER_UNIT" and "mouseover" or "target")
        end
        return
    end
    if event == "PLAYER_GUILD_UPDATE" then
        -- One unit's guild name just arrived or changed: repaint that plate
        -- alone (the client hands us the token, so no sweep of every plate).
        if GuildLineInUse() then RepaintUnitGuild(unit) end
        return
    end
    if event == "GROUP_ROSTER_UPDATE" then
        if RecentTrackingOn() then UpdateRecentGroupMembers() end
        return
    end
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        if RecentTrackingOn() then UpdateRecentGroupMembers() end
        -- The plates paint from these settings (the Name Format sync's first
        -- record, so an unchanged first refresh repaints nothing).
        StampFriendlyNames()
        ns.UpdateFriendlyNameplateSystem()
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        if RecentTrackingOn() then UpdateRecentGroupMembers() end
        -- Re-evaluate the friendly system on every zone transition so
        -- follower dungeons (and similar) correctly disable/enable it.
        ns.UpdateFriendlyNameplateSystem()
        -- Delayed re-check: instance/follower dungeon state may not be
        -- available yet when PLAYER_ENTERING_WORLD first fires on zone-in.
        C_Timer.After(1, function()
            ns.UpdateFriendlyNameplateSystem()
        end)
        -- Sweep every zone transition / reload to pick up any plates that
        -- were missed during the initial enable or that appeared between
        -- PLAYER_LOGIN and the world being fully rendered.
        C_Timer.After(0, function()
            if friendlyEnabled then
                local allPlates = C_NamePlate.GetNamePlates()
                if allPlates then
                    for _, nameplate in ipairs(allPlates) do
                        local u = GetNamePlateUnitToken(nameplate)
                        if u then TryAddFriendlyPlate(u) end
                    end
                end
            end
            -- Name-only NPC sweep: park the health bars and draw our names.
            -- Per-unit gate respects Blizzard's "NPC Names" filter (skip
            -- widgets-only NPCs); attackable plates are the enemy system's.
            if IsNameOnlyMode() then
                local allPlates = C_NamePlate.GetNamePlates()
                if allPlates then
                    for _, nameplate in ipairs(allPlates) do
                        local u = GetNamePlateUnitToken(nameplate)
                        if u and not UnitCanAttack("player", u) and not UnitIsUnit(u, "player")
                            and not UnitIsPlayer(u) then
                            RefreshNPCOverlay(nameplate, u)
                        end
                    end
                end
            end
            -- Player Below Name sub text: attach to plates present at zone-in
            -- (self-gated on name-only mode + the Subtitle Text setting).
            SweepPlayerSubText()
        end)
    end
end)

-------------------------------------------------------------------------------
--  Exported API -- called from EllesmereNameplates.lua (NAME_PLATE_UNIT_ADDED/REMOVED)
--  These wrap the new overlay system so the main file doesn't need to change.
-------------------------------------------------------------------------------
function ns.TryColorFriendlyNPCName(unit, nameplate)
    if IsNameOnlyMode() and not UnitIsPlayer(unit) then
        local overlay = npcOverlays[nameplate]
        if overlay and overlay.unit then
            ApplyOverlayStyle(overlay, overlay.unit)
        end
    end
end

function ns.TrySuppressNPCHealthBar(unit, nameplate)
    if nameplate and IsNameOnlyMode() and not UnitIsPlayer(unit) then
        RefreshNPCOverlay(nameplate, unit)
    end
end

-- Hand a plate back by name: its overlay and anything this file parked on it.
-- The removal path calls this with no unit -- the driver has cleared the base's
-- unit by then -- and RestoreBlizzardUF finds the park from the nameplate.
function ns.RestoreNPCNameplate(nameplate)
    RestoreNPCNameplate(nameplate, nameplate and GetNamePlateUnitToken(nameplate))
end
