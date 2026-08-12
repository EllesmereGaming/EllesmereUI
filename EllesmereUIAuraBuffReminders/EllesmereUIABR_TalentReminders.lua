if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIABR_TalentReminders.lua
--  Standalone talent reminder system. Zero dependency on ABR aura/buff logic.
--  Reads reminder configs from the ABR DB (db.profile.talentReminders) but
--  manages its own icons, events, and refresh cycle.
-------------------------------------------------------------------------------
local floor = math.floor
local ICON_SIZE = 40
local FONT_FALLBACK = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"

-------------------------------------------------------------------------------
--  Helpers (self-contained, no ABR imports)
-------------------------------------------------------------------------------
local function Known(id)
    return id and (IsPlayerSpell(id) or IsSpellKnown(id))
end

local texCache = {}
local function Tex(id)
    local c = texCache[id]; if c then return c end
    local t = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
    if t then texCache[id] = t end
    return t
end

local function GetFontPath()
    if EllesmereUI and EllesmereUI.GetFontPath then
        return EllesmereUI.GetFontPath("auraBuff")
    end
    return FONT_FALLBACK
end

local function SetTRFont(fs, font, size)
    if not (fs and fs.SetFont) then return end
    local outline = (EllesmereUI and EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag("auraBuff")) or ""
    if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(fs, outline == "") end
    fs:SetFont(font, size, outline)
end

local function InCombat()
    return InCombatLockdown and InCombatLockdown()
end

local function InRealInstancedContent()
    if C_Garrison and C_Garrison.IsOnGarrisonMap and C_Garrison.IsOnGarrisonMap() then
        return false
    end
    local _, iType = GetInstanceInfo()
    return iType == "party" or iType == "raid" or iType == "scenario"
        or iType == "arena" or iType == "pvp"
end

local function InMythicPlusKey()
    return C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
        and C_ChallengeMode.IsChallengeModeActive()
end

-------------------------------------------------------------------------------
--  Zone data
-------------------------------------------------------------------------------
-- CURRENT SEASON ONLY (12.1): the season raid + the Mythic+ pool. Rotated-
-- out zones are removed from this picker list, but stored reminders for
-- them are kept (hidden in options) and still name-match at runtime --
-- re-adding a zone here revives its reminders in the options list too.
-- instanceID = GetInstanceInfo() 8th return, locale-proof.
local TALENT_REMINDER_ZONES = {
    { name="The Venomous Abyss",      type="raid", instanceID=3004 },

    { name="Murder Row",              type="dungeon", instanceID=2813 },
    { name="Den of Nalorakk",         type="dungeon", instanceID=2825 },
    { name="The Blinding Vale",       type="dungeon", instanceID=2859 },
    { name="Voidscar Arena",          type="dungeon", instanceID=2923 },
    { name="Altar of Fangs",          type="dungeon", instanceID=2993 },
    { name="Ruby Life Pools",         type="dungeon", instanceID=2521 },
    { name="Temple of Sethraliss",    type="dungeon", instanceID=1877 },
    { name="Kings' Rest",             type="dungeon", instanceID=1762 },

    { name="Nagrand Arena",           type="pvp" },
    { name="Blade's Edge Arena",      type="pvp" },
    { name="Ruins of Lordaeron",      type="pvp" },
    { name="Dalaran Sewers",          type="pvp" },
    { name="The Ring of Valor",       type="pvp" },
    { name="Tol'viron Arena",         type="pvp" },
    { name="Tiger's Peak",            type="pvp" },
    { name="Black Rook Hold Arena",   type="pvp" },
    { name="Ashamane's Fall",         type="pvp" },
    { name="Mugambala",               type="pvp" },
    { name="Hook Point",              type="pvp" },
    { name="Empyrean Domain",         type="pvp" },
    { name="Warsong Gulch",           type="pvp" },
    { name="Arathi Basin",            type="pvp" },
    { name="Eye of the Storm",        type="pvp" },
    { name="Strand of the Ancients",  type="pvp" },
    { name="Isle of Conquest",        type="pvp" },
    { name="Twin Peaks",              type="pvp" },
    { name="Silvershard Mines",       type="pvp" },
    { name="Battle for Gilneas",      type="pvp" },
    { name="Temple of Kotmogu",       type="pvp" },
    { name="Deepwind Gorge",          type="pvp" },
    { name="Ashran",                  type="pvp" },
    { name="Seething Shore",          type="pvp" },
    { name="Wintergrasp",             type="pvp" },
    { name="Slayer's Rise",           type="pvp" },
}

local ZONE_BY_MAPID = {}
local ZONE_BY_INSTANCEID = {}
for _, z in ipairs(TALENT_REMINDER_ZONES) do
    if z.mapID then ZONE_BY_MAPID[z.mapID] = z end
    if z.instanceID then ZONE_BY_INSTANCEID[z.instanceID] = z end
end

-- Expose for options page
_G._EABR_TALENT_REMINDER_ZONES = TALENT_REMINDER_ZONES

-------------------------------------------------------------------------------
--  DB access (reads from ABR SavedVariables, set up after PLAYER_LOGIN)
-------------------------------------------------------------------------------
local db  -- set during Init

local function GetReminders()
    return db and db.profile and db.profile.talentReminders
end

-------------------------------------------------------------------------------
--  Icon pool & display
-------------------------------------------------------------------------------
local talentIconAnchor
local talentIconPool = {}
local talentActiveIcons = {}

local function GetOrCreateIcon(index)
    if talentIconPool[index] then return talentIconPool[index] end
    local btn = CreateFrame("Button", "EABR_TalentIcon" .. index, talentIconAnchor, "SecureActionButtonTemplate")
    btn:SetSize(ICON_SIZE, ICON_SIZE)
    btn:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
    securecallfunction(btn.SetPassThroughButtons, btn, "RightButton", "MiddleButton")
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(100)
    btn:Hide()
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(); icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    btn._icon = icon
    local PP = EllesmereUI and EllesmereUI.PP
    if PP then PP.CreateBorder(btn, 0, 0, 0, 1, 1, "OVERLAY", 7) end
    local text = btn:CreateFontString(nil, "OVERLAY")
    text:SetPoint("TOP", btn, "BOTTOM", 0, -2)
    SetTRFont(text, GetFontPath(), 11)
    text:SetTextColor(1, 1, 1, 1)
    btn._text = text
    talentIconPool[index] = btn
    return btn
end

local function SetupIcon(btn, entry)
    if not InCombat() then
        btn:SetAttribute("type", nil)
        btn:SetAttribute("spell", nil)
        btn:SetAttribute("item", nil)
        btn:SetAttribute("macrotext", nil)
    end
    btn._icon:SetTexture(entry.texture or 134400)
    btn._text:SetText(entry.label or "")
    btn._icon:SetDesaturated(false)
end

local function ShowIcon(iconIdx, entry)
    local btn = GetOrCreateIcon(iconIdx)
    SetupIcon(btn, entry)
    SetTRFont(btn._text, GetFontPath(), 11)
    btn._text:SetTextColor(1, 1, 1, 1)
    btn._text:Show()
    btn:Show()
    talentActiveIcons[#talentActiveIcons + 1] = btn
end

local function LayoutIcons()
    local count = #talentActiveIcons
    if count == 0 then return end
    local spacing = 40
    local sz = ICON_SIZE
    local totalW = (count * sz) + ((count - 1) * spacing)
    local startX = -totalW / 2
    for i, btn in ipairs(talentActiveIcons) do
        btn:SetSize(sz, sz)
        btn:SetAlpha(1)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", talentIconAnchor, "TOP", startX + (i - 1) * (sz + spacing), 0)
    end
end

local function HideIcons()
    if InCombat() then return end
    for i = 1, #talentActiveIcons do
        local btn = talentActiveIcons[i]
        if btn then btn._text:SetText(""); btn:Hide() end
    end
    wipe(talentActiveIcons)
    if talentIconAnchor then
        EllesmereUI.SetElementVisibility(talentIconAnchor, false)
    end
end

-------------------------------------------------------------------------------
--  Migration state
-------------------------------------------------------------------------------
local _migNeeded = false
local _migPending = false
local _migStamped = false

-------------------------------------------------------------------------------
--  Collection
-------------------------------------------------------------------------------
local _missing = {}

local function Collect()
    wipe(_missing)

    local inInstance = InRealInstancedContent()
    local inKeystone = InMythicPlusKey()
    if inKeystone or InCombat() or not inInstance then return end

    local reminders = GetReminders()
    if not reminders or #reminders == 0 then return end

    local currentInstance, _, _, _, _, _, _, currentInstanceID = GetInstanceInfo()
    local currentMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local _, playerClass = UnitClass("player")
    local playerSpecID = GetSpecializationInfo(GetSpecialization() or 1)
    if not currentInstance then return end

    for _, reminder in ipairs(reminders) do
        -- One-time migration: stamp class/spec on old reminders
        if _migPending and not reminder.class
            and (IsPlayerSpell(reminder.spellID) or IsSpellKnown(reminder.spellID)) then
            _migStamped = true
            reminder.class = playerClass
            if C_ClassTalents and C_ClassTalents.GetActiveConfigID then
                local cfgID = C_ClassTalents.GetActiveConfigID()
                if cfgID and C_Traits and C_Traits.GetConfigInfo then
                    local cfgInfo = C_Traits.GetConfigInfo(cfgID)
                    if cfgInfo and cfgInfo.treeIDs then
                        for _, treeID in ipairs(cfgInfo.treeIDs) do
                            local nodes = C_Traits.GetTreeNodes(treeID)
                            if nodes then for _, nodeID in ipairs(nodes) do
                                local ni = C_Traits.GetNodeInfo(cfgID, nodeID)
                                if ni and ni.entryIDs then for _, eID in ipairs(ni.entryIDs) do
                                    local ei = C_Traits.GetEntryInfo(cfgID, eID)
                                    if ei and ei.definitionID then
                                        local di = C_Traits.GetDefinitionInfo(ei.definitionID)
                                        if di and di.spellID == reminder.spellID then
                                            if ni.isClassNode then
                                                reminder.talentSource = "class"
                                            else
                                                reminder.talentSource = "spec"
                                                reminder.specID = playerSpecID
                                            end
                                        end
                                    end
                                end end
                            end end
                        end
                    end
                end
            end
        end

        -- Skip reminders for a different class
        if reminder.class and reminder.class ~= playerClass then
            -- not this class
        elseif reminder.talentSource == "spec" and reminder.specID
            and reminder.specID ~= playerSpecID then
            -- not this spec
        else
            -- Build name set cache once per reminder
            if not reminder._nameSet and reminder.zoneNames then
                local s = {}
                for _, zn in ipairs(reminder.zoneNames) do s[zn] = true end
                reminder._nameSet = s
            end

            local zoneMatch = false
            -- Locale-proof primary: current instanceID -> zone -> stored name.
            if currentInstanceID and reminder._nameSet then
                local idZone = ZONE_BY_INSTANCEID[currentInstanceID]
                if idZone then
                    zoneMatch = reminder._nameSet[idZone.name] or false
                end
            end
            if not zoneMatch and currentMapID then
                local mapZone = ZONE_BY_MAPID[currentMapID]
                if mapZone and reminder._nameSet then
                    zoneMatch = reminder._nameSet[mapZone.name] or false
                end
            end
            if not zoneMatch and reminder._nameSet then
                zoneMatch = reminder._nameSet[currentInstance] or false
            end

            local hasTalent = IsPlayerSpell(reminder.spellID) or IsSpellKnown(reminder.spellID)

            if zoneMatch and not hasTalent then
                _missing[#_missing + 1] = {
                    texture = Tex(reminder.spellID) or 134400,
                    spellID = reminder.spellID,
                    label = reminder.spellName or "Unknown",
                }
            elseif not zoneMatch and reminder.showNotNeeded and hasTalent then
                _missing[#_missing + 1] = {
                    texture = Tex(reminder.spellID) or 134400,
                    spellID = reminder.spellID,
                    label = (reminder.spellName or "Unknown") .. " (N/N)",
                }
            end
        end
    end

    _migPending = false
    if _migStamped then
        _migStamped = false
        local stillNeeded = false
        for _, r in ipairs(reminders) do
            if not r.class then stillNeeded = true; break end
        end
        if not stillNeeded then _migNeeded = false end
    end
end

-------------------------------------------------------------------------------
--  Refresh
-------------------------------------------------------------------------------
local _refreshQueued = false
local _lastRefresh = 0

local function Refresh()
    _refreshQueued = false
    _lastRefresh = GetTime()

    if not db then return end

    -- Suppress while dead, mounted+flying, or in vehicle
    if UnitIsDeadOrGhost("player") or IsResting()
        or (IsMounted() and IsFlying()) or UnitInVehicle("player") then
        HideIcons()
        return
    end

    HideIcons()
    Collect()

    if #_missing > 0 and talentIconAnchor then
        for i, m in ipairs(_missing) do
            ShowIcon(i, m)
        end
        LayoutIcons()
        EllesmereUI.SetElementVisibility(talentIconAnchor, true)
    end
end

local function RequestRefresh()
    if _refreshQueued then return end
    _refreshQueued = true
    local elapsed = GetTime() - _lastRefresh
    if elapsed >= 0.5 then
        C_Timer.After(0, function() _refreshQueued = false; Refresh() end)
    else
        C_Timer.After(0.5 - elapsed, function() _refreshQueued = false; Refresh() end)
    end
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        -- Get DB reference from ABR
        db = _G._EABR_AceDB
        if not db then return end

        -- Check if migration needed
        local reminders = GetReminders()
        if reminders then
            for _, r in ipairs(reminders) do
                if not r.class then _migNeeded = true; break end
            end
        end

        -- Create anchor
        talentIconAnchor = CreateFrame("Frame", "EABR_TalentAnchor", UIParent)
        talentIconAnchor:SetSize(1, 1)
        talentIconAnchor:SetFrameStrata("MEDIUM")
        talentIconAnchor:SetFrameLevel(100)
        talentIconAnchor:EnableMouse(false)
        talentIconAnchor:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
        talentIconAnchor:Show()
        EllesmereUI.SetElementVisibility(talentIconAnchor, false)

        -- Register ongoing events
        eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
        eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
        eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        eventFrame:RegisterEvent("SPELLS_CHANGED")
        eventFrame:RegisterEvent("PLAYER_DEAD")
        eventFrame:RegisterEvent("PLAYER_ALIVE")

        C_Timer.After(1, RequestRefresh)
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        RequestRefresh()
        C_Timer.After(0.5, RequestRefresh)
        return
    end

    if event == "PLAYER_REGEN_DISABLED" then
        HideIcons()
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        RequestRefresh()
        return
    end

    if event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" then
        RequestRefresh()
        return
    end

    -- Talent/zone change events
    if _migNeeded then
        if event == "ZONE_CHANGED_NEW_AREA" or event == "TRAIT_CONFIG_UPDATED"
            or event == "PLAYER_TALENT_UPDATE" or event == "PLAYER_SPECIALIZATION_CHANGED"
            or event == "SPELLS_CHANGED" then
            _migPending = true
        end
    end

    RequestRefresh()
end)

-------------------------------------------------------------------------------
--  Public API (for options and unlock mode)
-------------------------------------------------------------------------------
_G._EABR_TR_RequestRefresh = RequestRefresh
_G._EABR_TR_HideIcons = HideIcons
_G._EABR_TR_GetAnchor = function() return talentIconAnchor end
