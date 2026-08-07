-------------------------------------------------------------------------------
--  EUI_MythicPlus_Keystones.lua  --  party keystone list + in-dungeon banner
--
--  Two displays over one data source: a free-floating list of every party
--  member's keystone, and a banner that names who is holding a key for the
--  dungeon the group just walked into.
--
--  Party data comes from LibKeystone (the BigWigs/DBM keystone exchange the
--  suite already vendors for /keys), so there is no comm channel of our own and
--  anyone running BigWigs, DBM or EllesmereUI answers. Both frames are placed
--  through the suite's global Unlock Mode -- there is no per-module lock toggle
--  or anchor dropdown.
--
--  Refreshes are event-driven only. The upstream addon polled both frames on a
--  3s OnUpdate; keystone data changes on roster, bag and challenge-mode events
--  and on LibKeystone replies, all of which are covered below.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local LibKeystone = LibStub and LibStub("LibKeystone", true)

local ICON_TEXT_GAP = 8
local LIST_PAD      = 8
local LIST_W        = 320
local BANNER_W      = 260
local BANNER_PAD    = 10

-- Banner scope: Mythic 0 is the pre-insertion state, where the group still has
-- to decide whose key to run. Once a key goes in the instance flips to the
-- Mythic+ difficulty and who else holds one stops mattering; Normal and Heroic
-- can never host a keystone at all.
local MYTHIC_DIFFICULTY_ID = 23

-------------------------------------------------------------------------------
--  Keystone data
-------------------------------------------------------------------------------
-- shortName -> { level, mapID, rating }. Filled by LibKeystone replies; the
-- player's own row is read straight from the API on every rebuild.
local partyKeys = {}

local function ShortName(name)
    if not name then return nil end
    if Ambiguate then return Ambiguate(name, "short") or name end
    return name:match("^([^%-]+)") or name
end

local function PartyUnits()
    local units = { "player" }
    if IsInGroup(LE_PARTY_CATEGORY_HOME) and not IsInRaid() then
        for i = 1, GetNumSubgroupMembers() do
            local unit = "party" .. i
            if UnitExists(unit) then units[#units + 1] = unit end
        end
    end
    return units
end

local function KeystoneForUnit(unit)
    local _, classFile = UnitClass(unit)
    if unit == "player" then
        return {
            level    = (C_MythicPlus.GetOwnedKeystoneLevel and C_MythicPlus.GetOwnedKeystoneLevel()) or 0,
            mapID    = (C_MythicPlus.GetOwnedKeystoneChallengeMapID and C_MythicPlus.GetOwnedKeystoneChallengeMapID()) or 0,
            classFile = classFile,
        }
    end
    local entry = partyKeys[ShortName(UnitName(unit))]
    return {
        level     = (entry and entry.level) or 0,
        mapID     = (entry and entry.mapID) or 0,
        classFile = classFile,
    }
end

--- Every party member with a keystone, best key first. `includeKeyless` keeps
--- the player's own row even when they are holding no key, so the list never
--- renders as an empty box for the one member whose state they already know.
local function CollectKeystones(includeKeyless)
    local list = {}
    for _, unit in ipairs(PartyUnits()) do
        local info = KeystoneForUnit(unit)
        if info.level > 0 or (includeKeyless and unit == "player") then
            list[#list + 1] = {
                name      = UnitName(unit) or unit,
                level     = info.level,
                mapID     = info.mapID,
                classFile = info.classFile,
            }
        end
    end
    table.sort(list, function(a, b)
        if a.level ~= b.level then return a.level > b.level end
        return (a.name or "") < (b.name or "")
    end)
    return list
end

local requestPending = false
local function RequestPartyKeys()
    if not LibKeystone or not IsInGroup() then return end
    -- Roster updates arrive in bursts while a group forms; one settled request
    -- per second instead of one per event.
    if requestPending then return end
    requestPending = true
    C_Timer.After(1, function()
        requestPending = false
        LibKeystone.Request("PARTY")
    end)
end

-------------------------------------------------------------------------------
--  Shared frame helpers
-------------------------------------------------------------------------------
local function ApplyPosition(frame, pos, defaultX, defaultY)
    if not frame then return end
    frame:ClearAllPoints()
    if pos and pos.centerX and pos.centerY then
        frame:SetPoint("CENTER", UIParent, "CENTER", pos.centerX, pos.centerY)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", defaultX, defaultY)
    end
end

local function CapturePosition(frame)
    if not frame then return nil end
    local left, bottom = frame:GetLeft(), frame:GetBottom()
    if not left or not bottom then return nil end
    local w, h = frame:GetSize()
    return {
        centerX = left + w / 2 - UIParent:GetWidth() / 2,
        centerY = bottom + h / 2 - UIParent:GetHeight() / 2,
    }
end

local function LevelText(level)
    if level and level > 0 then
        return "|c" .. ns.LevelColor(level) .. "+" .. level .. "|r"
    end
    return "|cff9d9d9d-|r"
end

-------------------------------------------------------------------------------
--  Preview
--
--  Driven by the eye toggles on the options page: both displays only appear
--  under conditions the player cannot conjure on demand (a full party, or
--  standing in a Mythic 0), so previewing them with sample data is the only way
--  to size and position them.
--
--  Preview state is RUNTIME ONLY -- never written to the profile. It clears when
--  the options window and Unlock Mode are both gone, so a preview can never be
--  left stuck on across a session. Sample rows are generated once per enable so
--  the preview does not reshuffle on every event-driven refresh.
--
--  Sample names are deliberately not translated: they stand in for character
--  names, which are never localized.
-------------------------------------------------------------------------------
local SAMPLE_NAMES = {
    "Aramis", "Brynhild", "Corvyn", "Dashiel", "Elowen", "Fenrick", "Greyvale",
}
local SAMPLE_CLASSES = {
    "MAGE", "PRIEST", "WARRIOR", "DRUID", "ROGUE", "PALADIN", "SHAMAN", "HUNTER",
}

local preview = { list = false, banner = false }
local previewListRows, previewBannerRows

local function RandomKeystone()
    local mapIDs = ns.SeasonMapIDs()
    local mapID = (mapIDs and #mapIDs > 0) and mapIDs[math.random(#mapIDs)] or 0
    return mapID, math.random(2, 20)
end

--- `count` sample rows. With `useOwnName` the first row is the player's real
--- name and class, which is what the banner preview wants.
local function BuildPreviewRows(count, useOwnName)
    local names = {}
    for i, name in ipairs(SAMPLE_NAMES) do names[i] = name end
    for i = #names, 2, -1 do
        local j = math.random(i)
        names[i], names[j] = names[j], names[i]
    end

    local rows = {}
    for i = 1, count do
        local mapID, level = RandomKeystone()
        local isSelf = useOwnName and i == 1
        rows[i] = {
            name      = isSelf and (UnitName("player") or names[i]) or names[i],
            level     = level,
            mapID     = mapID,
            classFile = isSelf and select(2, UnitClass("player"))
                or SAMPLE_CLASSES[math.random(#SAMPLE_CLASSES)],
        }
    end
    table.sort(rows, function(a, b)
        if a.level ~= b.level then return a.level > b.level end
        return a.name < b.name
    end)
    return rows
end

-------------------------------------------------------------------------------
--  Keystone list
-------------------------------------------------------------------------------
local list = { rows = {}, enabled = false }

local function ListCfg() return ns.P().keystoneList end

local function ListRow(index)
    local row = list.rows[index]
    if row then return row end

    row = CreateFrame("Frame", nil, list.frame)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.iconBorder = row:CreateTexture(nil, "BORDER")
    row.iconBorder:SetColorTexture(0, 0, 0, 0.6)
    row.iconBorder:SetPoint("TOPLEFT",     row.icon, "TOPLEFT",     -1,  1)
    row.iconBorder:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT",  1, -1)

    row.level = row:CreateFontString(nil, "OVERLAY")
    row.level:SetPoint("CENTER", row.icon, "CENTER", 0, 0)
    row.level:SetJustifyH("CENTER")

    row.dungeon = row:CreateFontString(nil, "OVERLAY")
    row.dungeon:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", ICON_TEXT_GAP, -4)
    row.dungeon:SetPoint("RIGHT",   row,      "RIGHT",    -6, 0)
    row.dungeon:SetJustifyH("LEFT")

    row.holder = row:CreateFontString(nil, "OVERLAY")
    row.holder:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", ICON_TEXT_GAP, 4)
    row.holder:SetPoint("RIGHT",      row,      "RIGHT",       -6, 0)
    row.holder:SetJustifyH("LEFT")

    list.rows[index] = row
    return row
end

local function ListHeight(rowCount)
    local cfg = ListCfg()
    local iconSize = cfg.iconSize or 42
    local gap = math.max(cfg.rowSpacing or 4, 0)
    rowCount = math.max(rowCount, 1)
    return LIST_PAD * 2 + iconSize * rowCount + gap * (rowCount - 1)
end

local function ListShouldShow()
    if not list.enabled then return false end
    if preview.list then return true end
    if not IsInGroup(LE_PARTY_CATEGORY_HOME) then return false end
    if IsInRaid() then return false end
    if list.inActiveRun then return false end
    return true
end

local function ListLayout()
    local cfg = ListCfg()
    local iconSize = cfg.iconSize or 42
    local gap = math.max(cfg.rowSpacing or 4, 0)
    local size = cfg.fontSize or 12
    -- The level sits inside the icon, so it scales with the icon rather than
    -- with the body text -- but never smaller than the body text.
    local levelSize = math.max(math.floor(iconSize * 0.55), size + 2)
    local entries = previewListRows or CollectKeystones(true)

    for i, entry in ipairs(entries) do
        local row = ListRow(i)
        row:ClearAllPoints()
        if i == 1 then
            row:SetPoint("TOPLEFT", list.frame, "TOPLEFT", LIST_PAD, -LIST_PAD)
        else
            row:SetPoint("TOPLEFT", list.rows[i - 1], "BOTTOMLEFT", 0, -gap)
        end
        row:SetPoint("RIGHT", list.frame, "RIGHT", -LIST_PAD, 0)
        row:SetHeight(iconSize)
        row.icon:SetSize(iconSize, iconSize)
        row:Show()

        row.icon:SetTexture(ns.DungeonIcon(entry.mapID))
        ns.SetFont(row.level, levelSize)
        ns.SetFont(row.dungeon, size)
        ns.SetFont(row.holder, size)

        row.level:SetText(LevelText(entry.level))
        if entry.level > 0 then
            row.dungeon:SetText(ns.DungeonName(entry.mapID, ns.P().useAbbreviation ~= false))
        else
            row.dungeon:SetText("|cff9d9d9d" .. EllesmereUI.L("No keystone") .. "|r")
        end
        row.holder:SetText(ns.ClassColorText(entry.classFile, ShortName(entry.name) or "?"))
    end

    for i = #entries + 1, #list.rows do
        list.rows[i]:Hide()
    end
    list.frame:SetHeight(ListHeight(#entries))
end

local function ListRefresh()
    if not list.frame then return end
    -- Anchor and box size are applied even while hidden: Unlock Mode syncs its
    -- mover from the frame's real position, and a frame that was never given a
    -- point has none to read -- the mover would land at screen center.
    ApplyPosition(list.frame, ListCfg().pos, -math.floor(UIParent:GetWidth() / 2) + 170, 200)
    if not ListShouldShow() then
        list.frame:SetHeight(ListHeight(1))
        list.frame:Hide()
        return
    end
    list.frame:Show()
    ListLayout()
end

-------------------------------------------------------------------------------
--  Center banner
-------------------------------------------------------------------------------
local banner = { rows = {}, enabled = false }

local function BannerCfg() return ns.P().centerBanner end

--- The current season mapID of the Mythic 0 dungeon the player is standing in,
--- or 0 when the banner has nothing to say.
local function ActiveMapID()
    local instanceName, instanceType, difficultyID = GetInstanceInfo()
    if instanceType ~= "party" or not instanceName or instanceName == "" then return 0 end
    if difficultyID ~= MYTHIC_DIFFICULTY_ID then return 0 end
    return ns.MapIDFromName(instanceName) or 0
end

local function BannerRow(index)
    local row = banner.rows[index]
    if row then return row end
    row = CreateFrame("Frame", nil, banner.frame)
    row.text = row:CreateFontString(nil, "OVERLAY")
    row.text:SetAllPoints(row)
    row.text:SetJustifyH("CENTER")
    row.text:SetJustifyV("MIDDLE")
    banner.rows[index] = row
    return row
end

local function BannerHolders(activeMapID)
    local holders = {}
    for _, entry in ipairs(CollectKeystones(false)) do
        if entry.mapID == activeMapID then holders[#holders + 1] = entry end
    end
    return holders
end

local function BannerHeight(rowCount)
    local cfg = BannerCfg()
    local size = cfg.fontSize or 18
    local gap = cfg.rowSpacing or 6
    local h = BANNER_PAD * 2 + size + 6
    if rowCount > 0 then
        h = h + gap + 4 + (size + 6) * rowCount + gap * (rowCount - 1)
    end
    return h
end

local function BannerLayout(holders)
    local cfg = BannerCfg()
    local size = cfg.fontSize or 18
    local gap = cfg.rowSpacing or 6
    local rowH = size + 6
    local afterTitleGap = gap + 4

    ns.SetFont(banner.frame.title, size)
    banner.frame.title:SetText("|cffffd700" .. EllesmereUI.L("Keystone Owners") .. "|r")

    for i, entry in ipairs(holders) do
        local row = BannerRow(i)
        row:ClearAllPoints()
        if i == 1 then
            row:SetPoint("TOPLEFT",  banner.frame.title, "BOTTOMLEFT",  0, -afterTitleGap)
            row:SetPoint("TOPRIGHT", banner.frame.title, "BOTTOMRIGHT", 0, -afterTitleGap)
        else
            row:SetPoint("TOPLEFT",  banner.rows[i - 1], "BOTTOMLEFT",  0, -gap)
            row:SetPoint("TOPRIGHT", banner.rows[i - 1], "BOTTOMRIGHT", 0, -gap)
        end
        row:SetHeight(rowH)
        row:Show()
        ns.SetFont(row.text, size)
        row.text:SetText(ns.ClassColorText(entry.classFile, ShortName(entry.name) or "?")
            .. "        " .. LevelText(entry.level))
    end

    for i = #holders + 1, #banner.rows do
        banner.rows[i]:Hide()
    end
    banner.frame:SetHeight(BannerHeight(#holders))
end

local function BannerRefresh()
    if not banner.frame then return end
    -- See the note in ListRefresh: the anchor is applied even while hidden so
    -- Unlock Mode's mover has a real position to sync from.
    ApplyPosition(banner.frame, BannerCfg().pos, 0, 200)

    local holders
    if banner.enabled and preview.banner then
        holders = previewBannerRows
    elseif banner.enabled then
        local activeMapID = ActiveMapID()
        holders = activeMapID ~= 0 and BannerHolders(activeMapID) or nil
    end
    if not holders or #holders == 0 then
        banner.frame:SetHeight(BannerHeight(1))
        banner.frame:Hide()
        return
    end
    banner.frame:Show()
    BannerLayout(holders)
end

-------------------------------------------------------------------------------
--  Shared events
-------------------------------------------------------------------------------
local function RefreshAll()
    ListRefresh()
    BannerRefresh()
end

local EVENTS = {
    "GROUP_ROSTER_UPDATE",
    "BAG_UPDATE_DELAYED",
    "PLAYER_ENTERING_WORLD",
    "CHALLENGE_MODE_START",
    "CHALLENGE_MODE_COMPLETED",
    "CHALLENGE_MODE_RESET",
}

local function OnEvent(event)
    if event == "CHALLENGE_MODE_START" then
        list.inActiveRun = true
    elseif event == "CHALLENGE_MODE_COMPLETED" or event == "CHALLENGE_MODE_RESET" then
        list.inActiveRun = false
    elseif event == "PLAYER_ENTERING_WORLD" then
        local _, instanceType = GetInstanceInfo()
        local activeLevel = (C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo
            and C_ChallengeMode.GetActiveKeystoneInfo()) or 0
        list.inActiveRun = (instanceType == "party" and activeLevel > 0) or false
        RequestPartyKeys()
    elseif event == "GROUP_ROSTER_UPDATE" then
        RequestPartyKeys()
    end
    RefreshAll()
end

-- LibKeystone hands every listener the same replies, so registering here is
-- independent of whether the /keys popup is also listening. The lib has no
-- unregister, so this is installed once on first enable and lives for the
-- session -- which is why the callback's first act is to bail when neither
-- display is on.
local libCallbacks = {}
local function InstallLibKeystone()
    if not LibKeystone or libCallbacks.installed then return end
    libCallbacks.installed = true
    LibKeystone.Register(libCallbacks, function(keyLevel, keyMapID, _, playerName, channel)
        -- LibKeystone exposes no unregister, so the callback stays installed for
        -- the session; it must therefore cost nothing once both displays are off.
        if not (list.enabled or banner.enabled) then return end
        if channel == "GUILD" or not playerName then return end
        partyKeys[ShortName(playerName)] = { level = keyLevel or 0, mapID = keyMapID or 0 }
        RefreshAll()
    end)
end

-------------------------------------------------------------------------------
--  Unlock Mode
--
--  Both frames are placed through the suite's global Unlock Mode -- that is the
--  single place in EllesmereUI where on-screen elements are moved, so neither
--  frame carries a drag handler or an anchor dropdown of its own.
-------------------------------------------------------------------------------
local function RegisterUnlock()
    if not EllesmereUI.RegisterUnlockElements or not EllesmereUI.MakeUnlockElement then return end
    local MK = EllesmereUI.MakeUnlockElement

    EllesmereUI:RegisterUnlockElements({
        MK({
            key      = "EMP_KeystoneList",
            label    = "Party Keystones",
            group    = "Mythic+",
            order    = 530,
            noResize = true,
            isHidden = function()
                local p = ns.P()
                return not p or p.enabled == false or p.keystoneList.enabled == false
            end,
            getFrame = function()
                if not list.frame then return nil end
                return list.frame
            end,
            getSize = function()
                if list.frame and list.frame:GetHeight() > 1 then
                    return list.frame:GetWidth(), list.frame:GetHeight()
                end
                return LIST_W, ListHeight(1)
            end,
            savePos = function(_, _, _, x, y)
                local cfg = ListCfg(); if not cfg then return end
                cfg.pos = CapturePosition(list.frame) or { centerX = x, centerY = y }
            end,
            loadPos = function()
                local cfg = ListCfg()
                if cfg and cfg.pos then
                    return { point = "CENTER", relPoint = "CENTER", x = cfg.pos.centerX, y = cfg.pos.centerY }
                end
                return nil
            end,
            clearPos = function()
                local cfg = ListCfg(); if cfg then cfg.pos = nil end
            end,
            applyPos = function() ListRefresh() end,
        }),
        MK({
            key      = "EMP_KeystoneBanner",
            label    = "Keystone Owners",
            group    = "Mythic+",
            order    = 540,
            noResize = true,
            isHidden = function()
                local p = ns.P()
                return not p or p.enabled == false or p.centerBanner.enabled == false
            end,
            getFrame = function()
                if not banner.frame then return nil end
                return banner.frame
            end,
            getSize = function()
                if banner.frame and banner.frame:GetHeight() > 1 then
                    return banner.frame:GetWidth(), banner.frame:GetHeight()
                end
                return BANNER_W, BannerHeight(1)
            end,
            savePos = function(_, _, _, x, y)
                local cfg = BannerCfg(); if not cfg then return end
                cfg.pos = CapturePosition(banner.frame) or { centerX = x, centerY = y }
            end,
            loadPos = function()
                local cfg = BannerCfg()
                if cfg and cfg.pos then
                    return { point = "CENTER", relPoint = "CENTER", x = cfg.pos.centerX, y = cfg.pos.centerY }
                end
                return nil
            end,
            clearPos = function()
                local cfg = BannerCfg(); if cfg then cfg.pos = nil end
            end,
            applyPos = function() BannerRefresh() end,
        }),
    }, "EllesmereUIMythicPlus")
end
-- Registered at module level, not on either feature: this one call owns BOTH
-- elements, so tying it to the list feature would drop the banner's mover the
-- moment that feature moved or went away.
ns.RegisterUnlockHook(RegisterUnlock)

-- Unlock Mode has no live element to grab until the frame exists, so both are
-- built as soon as either display is first enabled -- the frames stay hidden
-- until their own show rules say otherwise.
local function BuildFrames()
    if not list.frame then
        list.frame = CreateFrame("Frame", "EllesmereUIMythicPlusKeystoneList", UIParent)
        list.frame:SetSize(LIST_W, ListHeight(1))
        list.frame:SetFrameStrata("MEDIUM")
        list.frame:Hide()
    end
    if not banner.frame then
        banner.frame = CreateFrame("Frame", "EllesmereUIMythicPlusKeystoneBanner", UIParent)
        banner.frame:SetSize(BANNER_W, BannerHeight(1))
        banner.frame:SetFrameStrata("HIGH")
        banner.frame.title = banner.frame:CreateFontString(nil, "OVERLAY")
        banner.frame.title:SetPoint("TOPLEFT",  banner.frame, "TOPLEFT",   BANNER_PAD, -BANNER_PAD)
        banner.frame.title:SetPoint("TOPRIGHT", banner.frame, "TOPRIGHT", -BANNER_PAD, -BANNER_PAD)
        banner.frame.title:SetJustifyH("CENTER")
        banner.frame:Hide()
    end
end

-------------------------------------------------------------------------------
--  Preview API (consumed by the options page's eye toggles)
-------------------------------------------------------------------------------
--- @param which "list" | "banner"
function ns.SetKeystonePreview(which, on)
    on = on and true or false
    BuildFrames()
    if which == "list" then
        preview.list = on
        previewListRows = on and BuildPreviewRows(5, false) or nil
        ListRefresh()
    else
        preview.banner = on
        previewBannerRows = on and BuildPreviewRows(1, true) or nil
        BannerRefresh()
    end
end

function ns.IsKeystonePreview(which)
    if which == "list" then return preview.list end
    return preview.banner
end

function ns.ClearKeystonePreviews()
    if not (preview.list or preview.banner) then return end
    preview.list, preview.banner = false, false
    previewListRows, previewBannerRows = nil, nil
    ListRefresh()
    BannerRefresh()
end

-------------------------------------------------------------------------------
--  Features
-------------------------------------------------------------------------------
local eventsArmed = false

local function SyncEvents()
    local on = list.enabled or banner.enabled
    ns.SetEvents(OnEvent, EVENTS, on)
    -- The party request is a real addon-channel broadcast, so it fires only on
    -- the OFF -> ON transition and from the events above. SyncEvents itself runs
    -- on every settings change to ANY feature in this module (ApplyAll re-applies
    -- all of them), and a dungeon-name-size slider must not solicit the group.
    if on and not eventsArmed then
        InstallLibKeystone()
        RequestPartyKeys()
    end
    eventsArmed = on
end

ns.RegisterFeature({
    id = "keystoneList",
    IsEnabled = function(p) return p.keystoneList.enabled ~= false end,
    Start = BuildFrames,
    Apply = function(on)
        list.enabled = on
        if not on then
            preview.list = false
            previewListRows = nil
        end
        SyncEvents()
        ListRefresh()
    end,
})

ns.RegisterFeature({
    id = "centerBanner",
    IsEnabled = function(p) return p.centerBanner.enabled ~= false end,
    Start = BuildFrames,
    Apply = function(on)
        banner.enabled = on
        if not on then
            preview.banner = false
            previewBannerRows = nil
        end
        SyncEvents()
        BannerRefresh()
    end,
})
