if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if EllesmereUI and EllesmereUI.IS_FOREVER then return end -- WoW Forever: talent reminders are retail-only (its options page is not built there)
-------------------------------------------------------------------------------
--  EllesmereUIABR_TalentReminders.lua
--  Standalone talent reminder system. Zero dependency on ABR aura/buff logic.
--  Reads reminder configs from the ABR DB (db.profile.talentReminders) but
--  manages its own icons, events, and refresh cycle. Where you are is read as
--  the Loadout Manager's activity (ns.Loadouts.Activity, a file that loads
--  after this one and is called only at run time).
-------------------------------------------------------------------------------
local _, ns = ...
local ICON_SIZE = 40

-------------------------------------------------------------------------------
--  Helpers (self-contained, no ABR imports)
-------------------------------------------------------------------------------
local texCache = {}
local function Tex(id)
    local c = texCache[id]; if c then return c end
    local t = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
    if t then texCache[id] = t end
    return t
end

local function InCombat()
    return InCombatLockdown and InCombatLockdown()
end

-- A garrison or a house shows no reminder, whatever activity it reads as.
local function InGarrisonOrHouse()
    if C_Garrison and C_Garrison.IsOnGarrisonMap and C_Garrison.IsOnGarrisonMap() then
        return true
    end
    return (C_Housing and C_Housing.IsInsideHouseOrPlot and C_Housing.IsInsideHouseOrPlot()) and true or false
end

local function InMythicPlusKey()
    return C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
        and C_ChallengeMode.IsChallengeModeActive()
end

-------------------------------------------------------------------------------
--  Zone data
-------------------------------------------------------------------------------
-- SEASON UPDATE: the season raid + the Mythic+ pool (12.1 Season 2). Rotated-
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

    -- SEASON UPDATE: the arenas and battlegrounds the queues use. Instance IDs from the game's Map and
    -- BattlemasterListXMap tables (retail 12.1.5.70961); a map another queue plays the same ground on
    -- (Blitz's Eye of the Storm) is in alsoIDs. Loadout Manager lists every entry with an ID as its own
    -- activity. The Ring of Valor is no longer in the game: kept for reminders saved with it, no ID.
    { name="Nagrand Arena",           type="arena", instanceID=1505 },
    { name="Blade's Edge Arena",      type="arena", instanceID=1672 },
    { name="Ruins of Lordaeron",      type="arena", instanceID=572 },
    { name="Dalaran Sewers",          type="arena", instanceID=617 },
    { name="The Ring of Valor",       type="arena" },
    { name="Tol'viron Arena",         type="arena", instanceID=980 },
    { name="Tiger's Peak",            type="arena", instanceID=1134 },
    { name="Black Rook Hold Arena",   type="arena", instanceID=1504 },
    { name="Ashamane's Fall",         type="arena", instanceID=1552 },
    { name="Mugambala",               type="arena", instanceID=1911 },
    { name="Hook Point",              type="arena", instanceID=1825 },
    { name="Empyrean Domain",         type="arena", instanceID=2373 },
    { name="The Robodrome",           type="arena", instanceID=2167 },
    { name="Maldraxxus Coliseum",     type="arena", instanceID=2509 },
    { name="Enigma Crucible",         type="arena", instanceID=2547 },
    { name="Nokhudon Proving Grounds", type="arena", instanceID=2563 },
    { name="Cage of Carnage",         type="arena", instanceID=2759 },
    { name="Warsong Gulch",           type="pvp", instanceID=2106 },
    { name="Arathi Basin",            type="pvp", instanceID=2107 },
    { name="Eye of the Storm",        type="pvp", instanceID=566, alsoIDs={ 968 } },
    { name="Strand of the Ancients",  type="pvp", instanceID=607 },
    { name="Isle of Conquest",        type="pvp", instanceID=628 },
    { name="Twin Peaks",              type="pvp", instanceID=726 },
    { name="Silvershard Mines",       type="pvp", instanceID=727 },
    { name="Battle for Gilneas",      type="pvp", instanceID=761 },
    { name="Temple of Kotmogu",       type="pvp", instanceID=998 },
    { name="Deepwind Gorge",          type="pvp", instanceID=2245 },
    { name="Ashran",                  type="pvp", instanceID=1191 },
    { name="Seething Shore",          type="pvp", instanceID=1803 },
    { name="Wintergrasp",             type="pvp", instanceID=2118 },
    { name="Slayer's Rise",           type="pvp", instanceID=2799 },
    { name="Alterac Valley",          type="pvp", instanceID=30 },
    { name="Deephaul Ravine",         type="pvp", instanceID=2656 },
}

-- How far a reminder's 'Not Needed' reminder reached before it named activities:
-- "never", "season" (a zone of the list above, this season's instances) or "all"
-- (any instance). Reminders saved before that choice existed hold only the old
-- checkbox: on reads as "season" and off as "never".
local function NotNeededMode(reminder)
    local m = reminder.notNeededMode
    if m == "never" or m == "season" or m == "all" then return m end
    return reminder.showNotNeeded and "season" or "never"
end

-------------------------------------------------------------------------------
--  Activities (owner 2026-11-18). A reminder names the Loadout Manager's
--  activities ("d:<instanceID>" a season dungeon on Mythic, "raidm" / "raidn"
--  this season's raid on Mythic / below it, "raidold", "a:<instanceID>" an
--  arena, "b:<instanceID>" a battleground, "tw", "delve", "world"): its own in
--  reminder.acts, the ones its Not Needed reminder shows in in
--  reminder.notNeededActs (sets). A reminder saved before either keeps its
--  zone names and Not Needed choice and is read through them, a view: nothing
--  is converted until the options edit it (Edit / EditNotNeeded). A zone of
--  the list above is its activities (the raid both of its own); a zone no
--  longer on it still matches by its name. The old choice reads Never as
--  none, Current Season Instances as the list's zones, All Instances as
--  every activity but the open world.
-------------------------------------------------------------------------------
local ZONE_ACTS = {}  -- zone name -> { [activity] = true }; nil for a zone with no ID
for _, z in ipairs(TALENT_REMINDER_ZONES) do
    local id, acts = z.instanceID, nil
    if id then
        if z.type == "dungeon" then acts = { ["d:" .. id] = true }
        elseif z.type == "raid" then acts = { raidm = true, raidn = true }
        elseif z.type == "arena" then acts = { ["a:" .. id] = true }
        elseif z.type == "pvp" then acts = { ["b:" .. id] = true } end
    end
    ZONE_ACTS[z.name] = acts
end
local SEASON_ACTS = {}  -- Current Season Instances: every activity a zone of the list is
for _, acts in pairs(ZONE_ACTS) do
    for k in pairs(acts) do SEASON_ACTS[k] = true end
end

-- A reminder's zones as saved: the list, or the single zone of an older version.
local function SavedZones(r)
    local zns = r.zoneNames
    if type(zns) == "table" and #zns > 0 then return zns end
    return r.zoneName and { r.zoneName } or nil
end

local TRActs = {}

-- Whether a reminder names an activity.
function TRActs.Has(r, act)
    if act == nil then return false end
    if type(r.acts) == "table" then return r.acts[act] == true end
    local zns = r.zoneNames
    if type(zns) == "table" and #zns > 0 then
        for i = 1, #zns do
            local za = ZONE_ACTS[zns[i]]
            if za and za[act] then return true end
        end
        return false
    end
    local za = r.zoneName and ZONE_ACTS[r.zoneName]
    return (za and za[act]) and true or false
end

-- Whether one of a reminder's zones that are no longer on the list is the
-- instance of this name (they match by name, as they always did).
function TRActs.LegacyMatch(r, instanceName)
    if not instanceName then return false end
    local zns = r.zoneNames
    if type(zns) == "table" and #zns > 0 then
        for i = 1, #zns do
            if zns[i] == instanceName and not ZONE_ACTS[instanceName] then return true end
        end
        return false
    end
    return r.zoneName == instanceName and not ZONE_ACTS[instanceName]
end

-- Whether a reminder's Not Needed reminder shows in an activity.
function TRActs.NotNeededHas(r, act)
    if act == nil then return false end
    if type(r.notNeededActs) == "table" then return r.notNeededActs[act] == true end
    local mode = NotNeededMode(r)
    if mode == "all" then return act ~= "world" end
    if mode == "season" then return SEASON_ACTS[act] == true end
    return false
end

-- A reminder's activities for an edit (the table the caller writes): one read
-- through its zones takes them as activities now, its zones no longer on the
-- list staying in zoneNames.
function TRActs.Edit(r)
    if type(r.acts) == "table" then return r.acts end
    local acts, legacy = {}, {}
    for _, zn in ipairs(SavedZones(r) or {}) do
        local za = ZONE_ACTS[zn]
        if za then
            for k in pairs(za) do acts[k] = true end
        else
            legacy[#legacy + 1] = zn
        end
    end
    r.acts = acts
    r.zoneNames = (#legacy > 0) and legacy or nil
    r.zoneName = nil
    return acts
end

-- Where a reminder's Not Needed reminder shows, for an edit: one read through
-- its old choice takes that choice over keys (the checklist's activities),
-- less the reminder's own activities.
function TRActs.EditNotNeeded(r, keys)
    if type(r.notNeededActs) == "table" then return r.notNeededActs end
    local nn = {}
    for _, k in ipairs(keys) do
        if TRActs.NotNeededHas(r, k) and not TRActs.Has(r, k) then nn[k] = true end
    end
    r.notNeededActs = nn
    r.notNeededMode, r.showNotNeeded = nil, nil
    return nn
end

-- A list zone's activities (a share string of the first version names zones).
function TRActs.ZoneActs(zoneName) return ZONE_ACTS[zoneName] end

ns.TRActs = TRActs

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
    EllesmereUI.ApplyModuleFont(text, nil, 11, "auraBuff")
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
    EllesmereUI.ApplyModuleFont(btn._text, nil, 11, "auraBuff")
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

    if InMythicPlusKey() or InCombat() or InGarrisonOrHouse() then return end

    local reminders = GetReminders()
    if not reminders or #reminders == 0 then return end

    -- Where you are, as the Loadout Manager names it (nil for a place that is
    -- no activity), and an instance's own name for the zones no longer on the
    -- list, which match by name.
    local LM = ns.Loadouts
    local act = LM and LM.Activity and LM.Activity()
    local inInstance = IsInInstance()
    local currentInstance = inInstance and GetInstanceInfo() or nil
    if act == nil and currentInstance == nil then return end
    local _, playerClass = UnitClass("player")
    local playerSpecID = GetSpecializationInfo(GetSpecialization() or 1)

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

        -- Skip reminders for a different class or spec (every reminder is kept
        -- per spec: EllesmereUI.SplitTalentReminders)
        if reminder.class and reminder.class ~= playerClass then
            -- not this class
        elseif reminder.specID and reminder.specID ~= playerSpecID then
            -- not this spec
        else
            -- The reminder's activities as saved, read on every pass so an edit
            -- on the options page applies at once.
            local zoneMatch = TRActs.Has(reminder, act) or TRActs.LegacyMatch(reminder, currentInstance)

            local hasTalent = IsPlayerSpell(reminder.spellID) or IsSpellKnown(reminder.spellID)

            if zoneMatch and not hasTalent then
                _missing[#_missing + 1] = {
                    texture = Tex(reminder.spellID) or 134400,
                    spellID = reminder.spellID,
                    label = reminder.spellName or "Unknown",
                }
            elseif not zoneMatch and hasTalent then
                if TRActs.NotNeededHas(reminder, act) then
                    _missing[#_missing + 1] = {
                        texture = Tex(reminder.spellID) or 134400,
                        spellID = reminder.spellID,
                        label = (reminder.spellName or "Unknown") .. " (N/N)",
                    }
                end
            end
        end
    end

    _migPending = false
    if _migStamped then
        _migStamped = false
        -- A class-tree talent just named its class: one reminder per spec
        -- (this pass already counted it for the current spec). The options
        -- tab, while loaded, builds its rows again (ns.TR_ListChanged).
        if EllesmereUI.SplitTalentReminders(reminders) and ns.TR_ListChanged then ns.TR_ListChanged() end
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
        -- Rested areas hide the reminders: an Open World one shows again as you
        -- leave a city, which brings no zone change.
        eventFrame:RegisterEvent("PLAYER_UPDATE_RESTING")

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
