if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  EllesmereUI_ForeverLayout.lua  --  the WoW Forever base layout
--
--  On the Forever client every fresh install starts from one layout instead
--  of a snapshot of wherever Blizzard's frames happened to be:
--    chat bottom-left with the micro menu under it, action bar 1 bottom
--    centre with the pet bar above it, action bars 2+ hidden, the bag bar
--    bottom-right with the damage meter above it and the tooltip above that,
--    the minimap top-right, the player frame left and the target frame right
--    a hundred pixels above action bar 1 with the cast bar centred between
--    them, the stance bar just above the player frame, the battle res
--    indicator to its left and Blizzard's encounter bar fifty pixels above
--    the target frame.
--
--  Two halves:
--    1. SeedForeverBaseLayout, called by the first-install loader at the
--       parent's ADDON_LOADED, before any module opens its profile: writes
--       the positions into the fresh profile, stamps the first-install
--       capture flags so no module reads Blizzard's layout, and files a
--       screen-edge anchor for every piece unlock mode owns (the record its
--       "Relative to Screen" menu writes), so each piece keeps its distance
--       to the screen edges on any monitor width.
--    2. The Edit Mode layout: the micro menu, the bag bar, the encounter bar
--       and Blizzard's own action bars are placed by Blizzard's Edit Mode (on
--       retail too; the Action Bars module only follows the micro menu and
--       the bag bar), so those come from
--       an account layout named "EllesmereUI Forever", written once the
--       layouts have loaded and only while no layout of that name exists.
--       Edit Mode keeps the layout account-wide but the active choice per
--       character, so each character is switched to it once, on its first
--       login (while still on a Blizzard preset), and owns its choice from
--       then on. The first-install popup always ends in a reload, which
--       lands both halves and clears the Edit Mode taint, the way the
--       profile importer's layout write relies on it.
--
--  Cost: nothing on any other client (the file returns), and on Forever one
--  saved-data lookup per login after a character's first session.
--------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end

local EDGE        = 10                    -- distance from the screen edges
local GAP         = 8                     -- between stacked pieces
local XP_WIDTH_PCT = 75                   -- Blizzard's experience bar, Edit Mode size (percent)
local XP_BAR_H    = 14                    -- its height, flush with the bottom edge
local BAR_BOTTOM  = XP_BAR_H + 12         -- action bar 1 sits above the experience bar
local BAR_HEIGHT  = 45                    -- one row of default-size buttons
local MICRO_H     = 40                    -- micro menu, for the chat above it
local BAGS_H      = 46                    -- bag bar, for the meter above it
local CHAT_LEFT    = EDGE + 45                -- chat starts in from the corner
local CHAT_BOTTOM  = GAP + MICRO_H + GAP + 40
local METER_BOTTOM = GAP + BAGS_H + GAP
local METER_H      = 150                  -- the meter window's default height
-- The tooltip's fixed anchor box (the Blizz UI Enhanced mover, 280 x 165,
-- stored as centre offsets from the UIParent centre): flush above the meter,
-- right edges aligned.
local TT_W, TT_H   = 280, 165
local UF_BOTTOM    = BAR_BOTTOM + BAR_HEIGHT + 100
local UF_SPREAD    = 317                  -- player left / target right of centre
-- Target of target: right edges flush with the target frame, just above it.
-- Sizes follow the Unit Frames defaults (target frameWidth 181, health 46 +
-- power 6 four below; target of target frameWidth 101).
local TARGET_W     = 181
local TARGET_H     = 56
local TOT_W        = 101
local TOT_GAP      = 6
local TOT_DX       = (TARGET_W - TOT_W) / 2   -- centre offset that aligns the right edges
-- Stance bar: just above the player frame (same size as the target frame),
-- right edges flush. Placed by its bottom-right corner, so a class with more
-- or fewer forms grows to the left and the right edge stays put.
local STANCE_RIGHT  = -UF_SPREAD + TARGET_W / 2   -- the player frame's right edge
local STANCE_BOTTOM = UF_BOTTOM + TARGET_H + GAP
-- Pet bar: centred just above action bar 1.
local PET_BOTTOM    = BAR_BOTTOM + BAR_HEIGHT + GAP
-- The unit frames' vertical centre: the Resource Bars cast bar sits there,
-- centred between the player and target frames.
local UF_MID        = UF_BOTTOM + TARGET_H / 2
-- Blizzard's encounter bar: over the target frame, this far above it.
local ENCOUNTER_GAP = 50
-- Battle res indicator (Quality of Life, a 40 px icon by default): left of
-- the player frame, vertically centred on it. Its store keeps centre offsets
-- from the UIParent centre, so the vertical half is computed from the screen
-- size in the world, like the tooltip box.
local BREZ_SIZE     = 40
local BREZ_GAP      = GAP + 20                  -- a little more room than the stacked pieces get
local BREZ_CX       = -UF_SPREAD - TARGET_W / 2 - BREZ_GAP - BREZ_SIZE / 2
local MINIMAP_SIZE = 200
EllesmereUI.FOREVER_MINIMAP_SIZE = MINIMAP_SIZE   -- the minimap's own first-activation default there

-- The Edit Mode layout carries a version in its name from v2 on ("EllesmereUI
-- Forever v2"); the first shipped without one. A newer version replaces the
-- older layouts of ours and takes over as active, so a base layout change
-- lands without anyone deleting the old one by hand. Bump on every change.
local LAYOUT_NAME    = "EllesmereUI Forever"
local LAYOUT_VERSION = 3

local function LayoutFullName()
    if LAYOUT_VERSION > 1 then return LAYOUT_NAME .. " v" .. LAYOUT_VERSION end
    return LAYOUT_NAME
end

-- One of ours, at any version.
local function IsOurLayout(name)
    return name == LAYOUT_NAME or (type(name) == "string" and name:match("^EllesmereUI Forever v%d+$") ~= nil)
end

local function Pos(point, x, y)
    return { point = point, relPoint = point, x = x, y = y }
end

-- The chat module's genesis capture asks for this instead of reading
-- Blizzard's placement.
function EllesmereUI.ForeverChatPosition()
    return Pos("BOTTOMLEFT", CHAT_LEFT, CHAT_BOTTOM)
end

--------------------------------------------------------------------------------
--  1. Profile seed
--------------------------------------------------------------------------------
local function Sub(t, key)
    if type(t[key]) ~= "table" then t[key] = {} end
    return t[key]
end

local function ProfileAddons()
    if not EllesmereUIDB then EllesmereUIDB = {} end
    local profiles = Sub(EllesmereUIDB, "profiles")
    local prof = Sub(profiles, EllesmereUIDB.activeProfile or "Default")
    return Sub(prof, "addons")
end

-- The screen-edge anchor record unlock mode writes: target = the edge strip,
-- side = where the element sits relative to it, offsets edge-to-edge along
-- the anchored axis and centre-relative across it; a second edge may hold
-- the cross axis (a corner).
local function EdgeAnchor(target, side, offsetX, offsetY, edgeKey, edgeSide, edgeOffset)
    local rec = { target = target, side = side, offsetX = offsetX, offsetY = offsetY }
    if edgeKey then
        rec.edge = { key = edgeKey, side = edgeSide, offset = edgeOffset }
    end
    return rec
end

function EllesmereUI.SeedForeverBaseLayout()
    local addons = ProfileAddons()

    -- Chat: bottom-left, room for the micro menu under it. Ownership stamped,
    -- so the chat module never captures Blizzard's placement.
    local chat = Sub(Sub(addons, "EllesmereUIChat"), "chat")
    chat.chatPosition = EllesmereUI.ForeverChatPosition()
    chat._chatPosOwnership = 1
    -- Tabs inside one continuous chat panel.
    chat.extendBgBehindTabs = true

    -- Minimap: top-right, 200 wide.
    local mm = Sub(Sub(addons, "EllesmereUIMinimap"), "minimap")
    mm.position = Pos("TOPRIGHT", -EDGE, -EDGE)
    mm.mapSize = MINIMAP_SIZE
    mm._capturedOnce = true

    -- Unit frames: player left, target right, above action bar 1; target of
    -- target right-aligned just above the target.
    local uf = Sub(Sub(addons, "EllesmereUIUnitFrames"), "positions")
    uf.player = Pos("BOTTOM", -UF_SPREAD, UF_BOTTOM)
    uf.target = Pos("BOTTOM", UF_SPREAD, UF_BOTTOM)
    uf.targettarget = Pos("BOTTOM", UF_SPREAD + TOT_DX, UF_BOTTOM + TARGET_H + TOT_GAP)

    -- Resource Bars cast bar (the cast bar shown by default): centred between
    -- the player and target frames.
    local erb = Sub(addons, "EllesmereUIResourceBars")
    Sub(erb, "castBar").unlockPos = { point = "CENTER", relPoint = "BOTTOM", x = 0, y = UF_MID }

    -- Damage meter: the one window, bottom-right above the bag bar, open on
    -- Damage Done (a window with no mode shows its mode picker instead).
    local dm = Sub(Sub(addons, "EllesmereUIDamageMeters"), "dm")
    local win = Sub(Sub(dm, "windows"), 1)
    win.position = Pos("BOTTOMRIGHT", -EDGE, METER_BOTTOM)
    win.width = win.width or 375
    win.height = win.height or METER_H
    if win.curDMType == nil and Enum and Enum.DamageMeterType then
        win.curDMType = Enum.DamageMeterType.DamageDone
    end

    -- Action bars: bar 1 bottom centre with the pet bar centred above it, the
    -- stance bar just above the player frame, every other bar hidden,
    -- Blizzard's own XP and reputation bars in place of the module's.
    local ab = Sub(addons, "EllesmereUIActionBars")
    ab.useBlizzardDataBars = true
    local barPos = Sub(ab, "barPositions")
    barPos.MainBar = Pos("BOTTOM", 0, BAR_BOTTOM)
    barPos.PetBar = Pos("BOTTOM", 0, PET_BOTTOM)
    barPos.StanceBar = { point = "BOTTOMRIGHT", relPoint = "BOTTOM", x = STANCE_RIGHT, y = STANCE_BOTTOM }
    local bars = Sub(ab, "bars")
    for _, key in ipairs({ "Bar2", "Bar3", "Bar4", "Bar5", "Bar6", "Bar7", "Bar8", "Bar9", "Bar10" }) do
        local b = Sub(bars, key)
        b.barVisibility = "never"
        b.alwaysHidden = true
    end

    -- No module reads Blizzard's layout: the capture flags start stamped.
    EllesmereUIDB._capturedOnce_EAB = true
    EllesmereUIDB._capturedOnce_CDM = true

    -- Screen-edge anchors, keyed by unlock element.
    local anchors = Sub(EllesmereUIDB, "unlockAnchors")
    anchors.ECHAT_MainChat = EdgeAnchor("SCREEN_LEFT", "RIGHT", CHAT_LEFT, 0, "SCREEN_BOTTOM", "TOP", CHAT_BOTTOM)
    anchors.EBS_Minimap    = EdgeAnchor("SCREEN_RIGHT", "LEFT", -EDGE, 0, "SCREEN_TOP", "BOTTOM", -EDGE)
    anchors.EDM_Win1       = EdgeAnchor("SCREEN_RIGHT", "LEFT", -EDGE, 0, "SCREEN_BOTTOM", "TOP", METER_BOTTOM)
    anchors.MainBar        = EdgeAnchor("SCREEN_BOTTOM", "TOP", 0, BAR_BOTTOM)
    anchors.player         = EdgeAnchor("SCREEN_BOTTOM", "TOP", -UF_SPREAD, UF_BOTTOM)
    anchors.target         = EdgeAnchor("SCREEN_BOTTOM", "TOP", UF_SPREAD, UF_BOTTOM)
    -- An element link has the same record shape: the target of target rides
    -- the target frame's top edge, its centre offset keeping the right edges flush.
    anchors.targettarget   = EdgeAnchor("target", "TOP", TOT_DX, TOT_GAP)

    EllesmereUI._foreverLayoutFresh = true
end

--------------------------------------------------------------------------------
--  2. Edit Mode layout
--------------------------------------------------------------------------------
local function FindSystem(layout, system, systemIndex)
    for _, entry in ipairs(layout.systems or {}) do
        if entry.system == system and entry.systemIndex == systemIndex then return entry end
    end
    return nil
end

-- Anchors a system to a screen corner or edge of UIParent. The anchor table
-- is edited in place: action bars carry bottom-stack fields beside it.
local function AnchorSystem(entry, point, x, y)
    local a = entry.anchorInfo
    if type(a) ~= "table" then a = {}; entry.anchorInfo = a end
    a.point, a.relativeTo, a.relativePoint, a.offsetX, a.offsetY = point, "UIParent", point, x, y
    entry.isInDefaultPosition = false
end

local function SetSetting(entry, setting, value)
    local rows = entry.settings
    if type(rows) ~= "table" then rows = {}; entry.settings = rows end
    for _, row in ipairs(rows) do
        if row.setting == setting then row.value = value; return end
    end
    rows[#rows + 1] = { setting = setting, value = value }
end

-- Returns true once the layout exists and this character is on it for its
-- first time (written now, or found and switched to), false to retry.
local function WriteEditModeLayout()
    if InCombatLockdown() then return false end
    local mgr = _G.EditModeManagerFrame
    -- Layouts arrive with EDIT_MODE_LAYOUTS_UPDATED; the manager's account
    -- settings are the sign they have.
    if not (mgr and mgr.accountSettings) then return false end
    if mgr.editModeActive or (mgr.IsShown and mgr:IsShown()) then return false end
    if not (C_EditMode and C_EditMode.GetLayouts and C_EditMode.SaveLayouts and C_EditMode.SetActiveLayout) then return false end
    local PLM = _G.EditModePresetLayoutManager
    if not (PLM and PLM.GetCopyOfPresetLayouts and Enum and Enum.EditModeSystem and Enum.EditModeLayoutType) then return false end

    local info = C_EditMode.GetLayouts()
    if not (info and type(info.layouts) == "table") then return false end
    -- The presets come first in the game's own list: the active-layout index
    -- counts them, and a copy of the Modern one is the base of ours.
    local presets = PLM:GetCopyOfPresetLayouts()
    if type(presets) ~= "table" or #presets == 0 then return false end
    local presetCount = #presets
    local fullName = LayoutFullName()
    for i, l in ipairs(info.layouts) do
        if l.layoutName == fullName then
            -- Already written, by an earlier session or another character:
            -- the layout is account-wide, the active choice per character.
            -- A character still on a Blizzard preset has never had its
            -- first look at ours, so it is switched once; one on any saved
            -- layout, ours or its own, keeps that choice.
            local ours = presetCount + i
            if info.activeLayout ~= ours and (info.activeLayout or 0) <= presetCount then
                C_EditMode.SetActiveLayout(ours)
            end
            return true
        end
    end

    -- A copy of the Modern preset, with the pieces moved.
    local base = presets[1]
    local modernIndex = Enum.EditModePresetLayouts and Enum.EditModePresetLayouts.Modern
    for _, p in ipairs(presets) do
        if modernIndex ~= nil and p.layoutIndex == modernIndex then base = p end
    end
    local layout = CopyTable(base)
    layout.layoutIndex = nil
    layout.layoutType = Enum.EditModeLayoutType.Account
    layout.layoutName = fullName

    local AB = Enum.EditModeSystem.ActionBar
    local idx = Enum.EditModeActionBarSystemIndices or {}
    local main = FindSystem(layout, AB, idx.MainBar)
    if main then AnchorSystem(main, "BOTTOM", 0, BAR_BOTTOM) end
    local visSetting = Enum.EditModeActionBarSetting and Enum.EditModeActionBarSetting.VisibleSetting
    local hidden = Enum.ActionBarVisibleSetting and Enum.ActionBarVisibleSetting.Hidden
    if visSetting ~= nil and hidden ~= nil then
        for _, name in ipairs({ "Bar2", "Bar3", "RightBar1", "RightBar2", "ExtraBar1", "ExtraBar2", "ExtraBar3" }) do
            local entry = idx[name] ~= nil and FindSystem(layout, AB, idx[name])
            if entry then SetSetting(entry, visSetting, hidden) end
        end
    end
    local micro = Enum.EditModeSystem.MicroMenu and FindSystem(layout, Enum.EditModeSystem.MicroMenu, nil)
    if micro then AnchorSystem(micro, "BOTTOMLEFT", EDGE, GAP) end
    local bags = Enum.EditModeSystem.Bags and FindSystem(layout, Enum.EditModeSystem.Bags, nil)
    if bags then AnchorSystem(bags, "BOTTOMRIGHT", -EDGE, GAP) end
    -- The encounter bar keeps the Modern preset's bottom-centre spot
    -- otherwise, which lands between the player and target frames here.
    local enc = Enum.EditModeSystem.EncounterBar and FindSystem(layout, Enum.EditModeSystem.EncounterBar, nil)
    if enc then AnchorSystem(enc, "BOTTOM", UF_SPREAD, UF_BOTTOM + TARGET_H + ENCOUNTER_GAP) end
    -- Blizzard's experience bar: bottom centre, three quarters wide. The
    -- stored size is a slider STEP, not the percentage: Edit Mode shows
    -- raw * step + min (50 to 130 in steps of 5, so the preset's 10 reads
    -- 100). The live display info converts when the system frame is up;
    -- the same formula stands in for it otherwise.
    local stbIdx = Enum.EditModeStatusTrackingBarSystemIndices
    local xp = Enum.EditModeSystem.StatusTrackingBar and stbIdx and stbIdx.StatusTrackingBar1 ~= nil
        and FindSystem(layout, Enum.EditModeSystem.StatusTrackingBar, stbIdx.StatusTrackingBar1)
    if xp then
        AnchorSystem(xp, "BOTTOM", 0, 0)
        local sizeSetting = Enum.EditModeStatusTrackingBarSetting and Enum.EditModeStatusTrackingBarSetting.Size
        if sizeSetting ~= nil then
            local raw = (XP_WIDTH_PCT - 50) / 5
            local sys = _G.MainStatusTrackingBarContainer
            local di = sys and sys.settingDisplayInfoMap and sys.settingDisplayInfoMap[sizeSetting]
            if di and di.ConvertValue then
                local ok, v = pcall(di.ConvertValue, di, XP_WIDTH_PCT, false)
                if ok and type(v) == "number" then raw = v end
            end
            SetSetting(xp, sizeSetting, raw)
        end
    end

    if mgr.ReconcileWithModern then
        mgr:ReconcileWithModern(layout)
        for _, l in ipairs(info.layouts) do mgr:ReconcileWithModern(l) end
    end

    -- SaveLayouts takes the whole set the way the game keeps it: the presets
    -- first (read-only, carried for index alignment), then the saved layouts,
    -- with activeLayout indexing that merged list. Ours goes in ahead of the
    -- first character layout, with the account layouts.
    local merged = presets
    -- Older versions of ours drop out here; every other saved layout rides along.
    for _, l in ipairs(info.layouts) do
        if not IsOurLayout(l.layoutName) then merged[#merged + 1] = l end
    end
    local slot = #merged + 1
    for i = presetCount + 1, #merged do
        if merged[i].layoutType == Enum.EditModeLayoutType.Character then slot = i; break end
    end
    table.insert(merged, slot, layout)
    info.layouts = merged
    info.activeLayout = slot
    C_EditMode.SaveLayouts(info)
    C_EditMode.SetActiveLayout(slot)
    return true
end

-- The tooltip's fixed anchor box has no screen-edge anchor of its own (the
-- element takes no anchor target), so its centre is computed from the
-- screen size once that is final, in the world, over the skin's own login
-- seed (Blizzard's Edit Mode spot), and the box is re-parked at once.
local function PlaceTooltipAnchor()
    local prof = EllesmereUI.GetActiveProfileData and EllesmereUI.GetActiveProfileData()
    if not prof then return end
    local uw, uh = UIParent:GetWidth(), UIParent:GetHeight()
    if not uw or not uh or uw <= 0 or uh <= 0 then return end
    prof.tooltipFixedPos = {
        centerX = uw / 2 - EDGE - TT_W / 2,
        centerY = METER_BOTTOM + METER_H + GAP + TT_H / 2 - uh / 2,
    }
    if EllesmereUI._applyTooltipFixedAnchor then EllesmereUI._applyTooltipFixedAnchor() end
end

-- The battle res indicator keeps centre offsets from the UIParent centre the
-- same way, so its spot is computed here too: left of the player frame,
-- vertically centred on it, re-parked through the module's own apply.
local function PlaceBattleRes()
    local getDB = _G._EUI_BattleRes_DB
    local qdb = getDB and getDB()
    local br = qdb and qdb.profile and qdb.profile.battleRes
    if not br then return end
    local uh = UIParent:GetHeight()
    if not uh or uh <= 0 then return end
    br.pos = { centerX = BREZ_CX, centerY = UF_MID - uh / 2 }
    if _G._EUI_BattleRes_Apply then _G._EUI_BattleRes_Apply() end
end

-- Every login of a character that has not had its first look at this version
-- of the layout (stamped by character with the version below, in the
-- account's saved data, so a rebuilt layout lands once more for everyone; a
-- fresh install is such a login too), and never when an external installer
-- owns the first run. Retried on the layouts event and a few times after
-- entering the world; drops out for good once done, and at once for a
-- stamped character.
local function SeenByCharacter()
    if not EllesmereUIDB then return nil end
    return Sub(EllesmereUIDB, "foreverEditModeSeen")
end

local writer = CreateFrame("Frame")
writer:RegisterEvent("PLAYER_ENTERING_WORLD")
writer:SetScript("OnEvent", function(self, event)
    local guid = UnitGUID("player")
    local seen = SeenByCharacter()
    if EllesmereUI._externalInstaller or not guid or not seen or seen[guid] == LAYOUT_VERSION then
        self:UnregisterAllEvents()
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
        -- The tooltip box and the battle res indicator are profile data:
        -- first session of an install only.
        if EllesmereUI._foreverLayoutFresh then
            PlaceTooltipAnchor()
            PlaceBattleRes()
        end
    end
    local tries = 0
    local function Attempt()
        if seen[guid] == LAYOUT_VERSION then return end
        if WriteEditModeLayout() then
            seen[guid] = LAYOUT_VERSION
            EllesmereUI._foreverLayoutFresh = nil
            self:UnregisterAllEvents()
            return
        end
        tries = tries + 1
        if tries < 10 then C_Timer.After(1, Attempt) end
    end
    Attempt()
end)
