if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- Blocks\Travel.lua
-- Travel block factory (hearthstones and M+ teleports).

local ADDON_NAME, ns = ...
local L = ns.L
local K = ns.BlockKit

-- Upvalues
local CreateFrame      = CreateFrame
local InCombatLockdown = InCombatLockdown
local C_Timer          = C_Timer
local GetTime          = GetTime
local ipairs           = ipairs
local type             = type
local pcall            = pcall
local floor            = math.floor
local max              = math.max
local min              = math.min
local mrandom          = math.random

local ICON_GAP             = K.ICON_GAP
local CONTENT_BASE         = K.CONTENT_BASE
local InstKey              = K.InstKey
local MakeEventFrame       = K.MakeEventFrame
local RegisterInstEvents   = K.RegisterInstEvents
local UnregisterInstEvents = K.UnregisterInstEvents
local HBudget              = K.HBudget
local VSlotW               = K.VSlotW
local MaybeRelayout        = K.MaybeRelayout
local AttachTextOffset     = K.AttachTextOffset
local BlockColorOf         = K.BlockColorOf
local IconColorOf          = K.IconColorOf
local ParkSecureFrame      = K.ParkSecureFrame

-------------------------------------------------------------------------------
--  TRAVEL (Hearthstone + M+ teleports; SECURE hearth button)
-------------------------------------------------------------------------------
-- Static hearthstone pool (all expansions) shared by every instance.
local HEARTHSTONE_IDS = {
    -- Midnight
    263933, 265100, 263489, 264367,
    -- The War Within
    257736, 246565, 245970, 228940, 212337, 209035, 208704, 210455,
    -- Dragonflight
    236687, 235016, 200630, 193588,
    -- Shadowlands
    190196, 190237, 188952, 184353, 182773, 180290, 183716, 172179,
    -- Seasonal / Holiday
    163045, 162973, 165669, 165670, 165802, 166746, 166747,
    -- Legacy / Misc
    6948, 64488, 28585, 93672, 142542, 142298, 168907, 54452,
}

-- Standalone travel-cooldown entries listed under the Hearthstone tooltip line
-- when owned. Each has its OWN cooldown, separate from the shared hearthstone
-- one -- why Astral Recall is here, not the pool above, despite also returning
-- to the bind point. Spell IDs: Dalaran 222695, Arcantina 1255801, Garrison 171253.
local TRAVEL_EXTRAS = {
    140192,  -- Dalaran Hearthstone
    253629,  -- Key to the Arcantina
    110560,  -- Garrison Hearthstone
    556,     -- Astral Recall (a spell, hence the per-entry kind probe below)
    128353,  -- Admiral's Compass (a plain item, not a toy)
    193753,  -- Dreamwalk (druid)
    18960,   -- Teleport: Moonglade (druid)
    50977,   -- Death Gate (death knight)
    193759,  -- Teleport: Hall of the Guardian (mage)
    126892,  -- Zen Pilgrimage (monk)
    1238686, -- Rootwalking (Haranir)
}
local TRAVEL_EXTRA_SET = {}
for _, id in ipairs(TRAVEL_EXTRAS) do TRAVEL_EXTRA_SET[id] = true end
-- Entries that are not toys.
local TRAVEL_EXTRA_KIND = {
    [556] = "spell", [193753] = "spell", [18960] = "spell", [50977] = "spell",
    [193759] = "spell", [126892] = "spell", [1238686] = "spell",
    [128353] = "item",
}
-- Hidden while the player knows the replacement.
local TRAVEL_EXTRA_SUPERSEDED_BY = { [18960] = 193753 }

-- Hearthstones share one cooldown, so polling a single owned one suffices.
-- Engine-level cache: the underlying cooldown is shared game-wide.
local travelPrimaryHearthId

local function TravelIsUsable(id)
    if not id then return false end
    -- A race-restricted hearthstone toy counts only on the races that can use it.
    if not EllesmereUI.CanUseHearthToy(id) then return false end
    if PlayerHasToy(id) then return true end
    if IsPlayerSpell(id) then return true end
    return (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(id) or 0) > 0
end

local function TravelExtraKind(id)
    local sup = TRAVEL_EXTRA_SUPERSEDED_BY[id]
    if sup and IsPlayerSpell(sup) then return nil end
    local kind = TRAVEL_EXTRA_KIND[id]
    if kind == "spell" then return IsPlayerSpell(id) and kind or nil end
    if kind == "item" then
        return (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(id) or 0) > 0 and kind or nil
    end
    return PlayerHasToy(id) and "toy" or nil
end

-- nil until the game has cached the name.
local function TravelEntryName(id)
    if TRAVEL_EXTRA_SET[id] and TravelExtraKind(id) == "spell" then
        local info = C_Spell.GetSpellInfo(id)
        return info and info.name
    end
    if C_ToyBox and C_ToyBox.GetToyInfo then
        local _, tn = C_ToyBox.GetToyInfo(id)
        if tn then return tn end
    end
    if C_Item and C_Item.GetItemNameByID then
        local n = C_Item.GetItemNameByID(id)
        if n then return n end
    end
    return nil
end

-- Options-side exports.
ns.TravelHearthstoneIDs = HEARTHSTONE_IDS
ns.TravelIsUsable = TravelIsUsable
ns.TravelExtraIDs = TRAVEL_EXTRAS
ns.TravelExtraUsable = function(id) return TravelExtraKind(id) ~= nil end
ns.TravelEntryName = TravelEntryName

-- Returns remaining, known. In restricted combat cooldown numbers are SECRET: comparing
-- or dead-reckoning them throws (type() still says "number"), so those report 0, false and
-- callers degrade -- tooltip "-" on gray rows, block tints as cooling, probe keeps ticking and self-corrects on a clean read.
local function TravelGetRemainingCooldown(id, isSpell)
    local startTime, duration
    if isSpell then
        local info = C_Spell.GetSpellCooldown(id)
        if info then startTime, duration = info.startTime, info.duration end
    else
        if C_Item and C_Item.GetItemCooldown then
            startTime, duration = C_Item.GetItemCooldown(id)
        elseif C_Container and C_Container.GetItemCooldown then
            startTime, duration = C_Container.GetItemCooldown(id)
        end
    end
    if issecretvalue(startTime) or issecretvalue(duration) then
        return 0, false
    end
    -- 2s or less is the global cooldown, which these APIs also report on travel items: read as ready.
    if type(startTime) == "number" and type(duration) == "number" and duration > 2 then
        return max(0, startTime + duration - GetTime()), true
    end
    return 0, true
end

-- Player housing: a "house:<guid>" click uses Blizzard's teleporthome secure action
-- (returnhome while a return trip is available). The house list arrives
-- asynchronously; its listener registers only while a click or the options page needs it.
local HOUSE_PREFIX = "house:"
local travelHouses
-- Bumped on every list arrival (ns.TravelHouseListGen): the options refill their menus on a change.
local travelHousesGen = 0
local houseWatchers = {}
local houseOptionsWaiting
local houseEv = CreateFrame("Frame")

local function TravelHousingAvailable()
    return not EllesmereUI.IS_FOREVER and C_Housing and C_Housing.GetPlayerOwnedHouses ~= nil
end

-- As the house favor bar: no request in a keystone or raid; world entry retries.
local function TravelHousingBlocked()
    if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
        and C_ChallengeMode.IsChallengeModeActive() then
        return true
    end
    local inInst, instType = IsInInstance()
    return (inInst and instType == "raid") and true or false
end

local function TravelRequestHouses()
    if TravelHousingBlocked() then return end
    C_Housing.GetPlayerOwnedHouses()
end

local function TravelSyncHouseEvents()
    local watching = next(houseWatchers) ~= nil
    if watching or houseOptionsWaiting then
        houseEv:RegisterEvent("PLAYER_HOUSE_LIST_UPDATED")
    else
        houseEv:UnregisterEvent("PLAYER_HOUSE_LIST_UPDATED")
    end
    if watching then
        houseEv:RegisterEvent("PLAYER_ENTERING_WORLD")
    else
        houseEv:UnregisterEvent("PLAYER_ENTERING_WORLD")
    end
end

houseEv:SetScript("OnEvent", function(_, event, houses)
    if event == "PLAYER_ENTERING_WORLD" then
        TravelRequestHouses()
        return
    end
    travelHouses = type(houses) == "table" and houses or {}
    travelHousesGen = travelHousesGen + 1
    local onLoaded = houseOptionsWaiting
    houseOptionsWaiting = nil
    TravelSyncHouseEvents()
    for inst in next, houseWatchers do inst:OnHouseList() end
    if onLoaded then onLoaded() end
end)

local function TravelWatchHouses(inst, on)
    on = on and TravelHousingAvailable() or false
    if (houseWatchers[inst] == true) == on then return end
    houseWatchers[inst] = on or nil
    TravelSyncHouseEvents()
    if on and not travelHouses then TravelRequestHouses() end
end

function ns.TravelRequestHouseList(onLoaded)
    if travelHouses or houseOptionsWaiting or not TravelHousingAvailable() or TravelHousingBlocked() then return end
    houseOptionsWaiting = onLoaded
    TravelSyncHouseEvents()
    TravelRequestHouses()
end

local function TravelIsHouseChoice(choice)
    return type(choice) == "string" and choice:find(HOUSE_PREFIX, 1, true) == 1
end

local function TravelUsableHouse(h)
    return h and h.houseGUID and h.neighborhoodGUID and h.plotID
        and not issecretvalue(h.houseGUID) and not issecretvalue(h.neighborhoodGUID)
end

local function TravelFindHouse(choice)
    if not (travelHouses and TravelIsHouseChoice(choice)) then return nil end
    local guid = choice:sub(#HOUSE_PREFIX + 1)
    for _, h in ipairs(travelHouses) do
        if TravelUsableHouse(h) and h.houseGUID == guid then return h end
    end
    return nil
end

-- Skips the opaque placeholder name some clients report.
local function TravelHouseName(h)
    local n = h and h.houseName
    if n and not issecretvalue(n) and n ~= "" and not n:match("^Home%-opaque%-%d+$") then return n end
    return L["HOME"]
end

local function TravelCanReturnHome()
    local f = C_HousingNeighborhood and C_HousingNeighborhood.CanReturnAfterVisitingHouse
    if not f then return false end
    local ok, can = pcall(f)
    return ok and can == true
end

-- Returns remaining, known; 2s or less is the global cooldown, read as ready.
local function TravelHouseCooldown()
    local info = C_Housing and C_Housing.GetVisitCooldownInfo and C_Housing.GetVisitCooldownInfo()
    if not info or not info.isEnabled then return 0, true end
    if issecretvalue(info.startTime) or issecretvalue(info.duration) then return 0, false end
    local rem = 0
    if (info.duration or 0) > 2 and (info.startTime or 0) > 0 then
        rem = max(0, info.startTime + info.duration - GetTime())
    end
    return rem, true
end

function ns.TravelHouseListGen() return travelHousesGen end

-- Options-side: owned houses as { key = "house:<guid>", name = ... }.
function ns.TravelHouseChoices()
    local out = {}
    if travelHouses then
        for _, h in ipairs(travelHouses) do
            if TravelUsableHouse(h) then
                out[#out + 1] = { key = HOUSE_PREFIX .. h.houseGUID, name = TravelHouseName(h) }
            end
        end
    end
    return out
end

local _hearthList = {}
local _hearthListCount = 0
local function TravelGetAvailableHearthstones()
    _hearthListCount = 0
    for _, id in ipairs(HEARTHSTONE_IDS) do
        if TravelIsUsable(id) then
            _hearthListCount = _hearthListCount + 1
            _hearthList[_hearthListCount] = id
        end
    end
    for i = _hearthListCount + 1, #_hearthList do _hearthList[i] = nil end
    return _hearthList
end

local function TravelBuildMacro(id)
    if PlayerHasToy(id) then return "/use item:" .. id end
    if IsPlayerSpell(id) then
        local info = C_Spell.GetSpellInfo(id)
        if info and info.name then return "/cast " .. info.name end
    end
    return "/use item:" .. id
end

local function TravelPickHearthstone(randomize)
    local list = TravelGetAvailableHearthstones()
    if #list == 0 then return nil end
    if randomize then return list[mrandom(#list)] end
    for _, id in ipairs(list) do if id == 6948 then return id end end
    return list[1]
end

-- Per button (1 left, 2 right, 3 middle): "none", "random", "house:<guid>" or an id.
local function TravelClickChoice(dt, btn)
    local c
    if btn == 1 then
        c = dt.hsChoice
        if c == nil then c = dt.randomizeHs and "random" or 6948 end
    elseif btn == 2 then
        c = dt.hsChoiceRight
        if c == nil then c = "random" end
    else
        c = dt.hsChoiceMiddle
        if c == nil then c = "none" end
    end
    return c
end
ns.TravelClickChoice = TravelClickChoice

-- Id a choice fires now: nil for "none"; an entry the player lacks falls back to the hearthstone.
local function TravelResolveChoice(choice)
    if choice == "none" then return nil end
    if choice == "random" then return TravelPickHearthstone(true) end
    if TRAVEL_EXTRA_SET[choice] then
        if TravelExtraKind(choice) then return choice end
    elseif type(choice) == "number" and TravelIsUsable(choice) then
        return choice
    end
    return TravelPickHearthstone(false)
end

-- Negative-result cache: with NO usable hearthstone the 1s cooling probe would re-scan all
-- ~40 candidates every second forever. Ownership only changes via edges the block already
-- listens to (hearth bind, world entry, bag/spell changes), which clear this through ns.TravelInvalidateHearthCache.
local travelNoHearth
function ns.TravelInvalidateHearthCache()
    travelNoHearth = nil
    travelPrimaryHearthId = nil
end
local function TravelGetPrimaryCooldown()
    -- The cached id is trusted between ownership edges: re-validating per 1s probe costs a
    -- GetItemCount bag walk every second, and item loss always fires BAG_UPDATE_DELAYED
    -- (spells: SPELLS_CHANGED), which clears the cache via ns.TravelInvalidateHearthCache and forces a re-pick here.
    if not travelPrimaryHearthId then
        if travelNoHearth then return 0, true end
        travelPrimaryHearthId = TravelPickHearthstone(false)
        if not travelPrimaryHearthId then
            travelNoHearth = true
            return 0, true
        end
    end
    return TravelGetRemainingCooldown(travelPrimaryHearthId, false)
end

-- Show Other Characters (block setting altHearths, off by default): every
-- character's hearthstone, account-wide in EllesmereUIDB.travelHearths, keyed
-- by EllesmereUI.CharKey("-") (Name-Realm on retail, the character's GUID on
-- WoW Forever) = { name (with the surname on WoW Forever), class, bind,
-- readyAt }. readyAt is a time() stamp (0 = ready): item cooldowns keep
-- running while logged out, so an alt's row counts down from what it last
-- saved. A character saves itself on each
-- block refresh while the setting is on, but writes only when its bind or
-- ready time changed (the refresh runs every second while the tooltip or a
-- cooldown shows); a secret (combat) read saves nothing.
local function TravelHearthStore()
    local db = _G.EllesmereUIDB
    if type(db) ~= "table" then return nil end
    local store = db.travelHearths
    if type(store) ~= "table" then
        store = {}
        db.travelHearths = store
    end
    return store
end

-- This character's key and full name, read once a session, and what it last
-- wrote (the first save of a session always writes).
local _myHearthKey, _myHearthName, _savedBind, _savedReadyAt
local function TravelSaveMyHearth()
    local store = TravelHearthStore()
    if not store then return end
    if not _myHearthKey then
        _myHearthKey = EllesmereUI.CharKey("-", store)
        if not _myHearthKey then return end
        -- The full name whatever the show-surname preference: two WoW Forever
        -- characters can share a first name.
        local name, surname = (UnitNameUnmodified or UnitName)("player")
        _myHearthName = EllesmereUI.WithSurname(name, surname, true)
    end
    local cd, known = TravelGetPrimaryCooldown()
    if not known then return end
    local bind = GetBindLocation()
    local readyAt = (cd > 0) and (time() + cd) or 0
    local e = store[_myHearthKey]
    -- Unchanged: same bind, same ready time give or take a second of drift.
    if type(e) == "table" and bind == _savedBind and _savedReadyAt
       and math.abs(readyAt - _savedReadyAt) <= 1 then
        return
    end
    if type(e) ~= "table" then
        e = {}
        store[_myHearthKey] = e
    end
    local _, class = UnitClass("player")
    e.name = _myHearthName
    e.class = class
    e.bind = bind
    e.readyAt = readyAt
    _savedBind, _savedReadyAt = bind, readyAt
end

-- The other characters' rows, sorted by name (reused buffers: the open tooltip
-- refreshes every second). Ctrl + Alt + Left Click on a row stops following
-- that character, as the Gold block's Remove Character; onRemoved closes the
-- tip. Returns the number of rows.
local _altBuf, _altKeyOf = {}, {}
local function TravelAltSort(a, z) return (a.name or "") < (z.name or "") end
local function TravelAddAltRows(ar, ag, ab, onRemoved)
    local store = TravelHearthStore()
    if not store then return 0 end
    local mine = _myHearthKey or EllesmereUI.CharKey("-")
    local n = 0
    wipe(_altKeyOf)
    for key, e in pairs(store) do
        if key ~= mine and type(e) == "table" and e.name then
            n = n + 1
            _altBuf[n] = e
            _altKeyOf[e] = key
        end
    end
    for i = n + 1, #_altBuf do _altBuf[i] = nil end
    if n == 0 then return 0 end
    table.sort(_altBuf, TravelAltSort)
    ns.Tip_AddLine(" ")
    ns.Tip_AddLine(L["OTHER_CHARACTERS"], ar, ag, ab)
    local now = time()
    for i = 1, n do
        local e = _altBuf[i]
        local cc = e.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[e.class]
        local cr, cg, cb = 1, 1, 1
        if cc then cr, cg, cb = cc.r, cc.g, cc.b end
        local rem = (e.readyAt or 0) - now
        local cdStr, rr, rg, rb = L["READY"], 0, 1, 0
        if rem > 0 then
            cdStr = ns.FormatCooldown(rem) or L["READY"]
            rr, rg, rb = 0.5, 0.5, 0.5
        end
        local key = _altKeyOf[e]
        ns.Tip_AddClickable(e.name .. " (" .. (e.bind or "?") .. ")", cdStr, function(mouseButton)
            if mouseButton ~= "LeftButton" then return end
            if not (IsControlKeyDown() and IsAltKeyDown()) then return end
            local s = TravelHearthStore()
            if s then s[key] = nil end
            if onRemoved then onRemoved() end
        end, cr, cg, cb, rr, rg, rb)
    end
    return n
end

-- "smart": the cooldown while cooling, else the destination.
local TEXT_KEYS = { "textLeft", "textRight", "textMiddle" }
local function TravelClickTextMode(dt, btn)
    local m = dt[TEXT_KEYS[btn]]
    if m ~= nil then return m end
    return btn == 1 and "location" or "none"
end
ns.TravelClickTextMode = TravelClickTextMode

local function TravelAnyTimerText(dt)
    for btn = 1, 3 do
        local m = TravelClickTextMode(dt, btn)
        if m == "smart" or m == "both" or m == "cooldown" then return true end
    end
    return false
end

local TRAVEL_DESTINATIONS = {
    [140192] = { global = "DUNGEON_FLOOR_DALARANCITY1" },
    [253629] = { key = "TRAVEL_ARCANTINA" },
    [110560] = { global = "GARRISON_LOCATION_TOOLTIP" },
    [193753] = { global = "ORDER_HALL_DRUID" },
    [18960]  = { key = "TRAVEL_MOONGLADE" },
    [50977]  = { global = "ORDER_HALL_DEATHKNIGHT" },
    [193759] = { global = "ORDER_HALL_MAGE" },
    [126892] = { global = "ORDER_HALL_MONK" },
}

local HOUSE_ZONE_LABELS = { [2352] = "HOME_ALLIANCE", [2351] = "HOME_HORDE" } -- Founder's Point, Razorwind Shores

-- Bar destination of a choice; nil means the bind location.
local function TravelBarDestination(choice, tagHouses)
    local h = TravelFindHouse(choice)
    if h then
        if not tagHouses then return EllesmereUI.L(L["HOME"]) end
        local f = C_Housing.GetUIMapIDForNeighborhood
        local ok, mapID = false, nil
        if f then ok, mapID = pcall(f, h.neighborhoodGUID) end
        local key = ok and HOUSE_ZONE_LABELS[mapID]
        if key then return EllesmereUI.L(L[key]) end
        return EllesmereUI.L(TravelHouseName(h))
    end
    if TRAVEL_EXTRA_SET[choice] and TravelExtraKind(choice) then
        local d = TRAVEL_DESTINATIONS[choice]
        local name = d and ((d.global and _G[d.global]) or (d.key and EllesmereUI.L(L[d.key])))
        if name then return name end
        if choice ~= 556 then return TravelEntryName(choice) end -- Astral Recall: the bind point
    end
    return nil
end

local function TravelChoiceCooldown(choice)
    if TravelFindHouse(choice) then
        if TravelCanReturnHome() then return 0, true end
        return TravelHouseCooldown()
    end
    if TRAVEL_EXTRA_SET[choice] then
        local kind = TravelExtraKind(choice)
        if kind then return TravelGetRemainingCooldown(choice, kind == "spell") end
    end
    return TravelGetPrimaryCooldown()
end

local function TravelShownCooldown(dt, btn)
    local choice = TravelClickChoice(dt, btn)
    if choice == "none" or TravelClickTextMode(dt, btn) == "none" then return nil end
    return TravelChoiceCooldown(choice)
end

-- One bit per shown click that is cooling (unknown counts); the left click when none shows.
local CLICK_BITS = { 1, 2, 4 }
local function TravelCoolingMask(dt)
    local mask, shownMask = 0, 0
    for btn = 1, 3 do
        local cd, known = TravelShownCooldown(dt, btn)
        if cd then
            shownMask = shownMask + CLICK_BITS[btn]
            if not known or cd > 0 then mask = mask + CLICK_BITS[btn] end
        end
    end
    if shownMask == 0 then
        local cd, known = TravelChoiceCooldown(TravelClickChoice(dt, 1))
        if not known or cd > 0 then mask = 1 end
    end
    return mask
end

-- Cooling parts are wrapped in gray unless plain. Returns text, timerShown
-- (a shown timer is counting down), coolingMask, iconDim.
local _textParts, _textRaw = {}, {}
local function TravelBarText(dt, bind, plain)
    local firstHouse, tagHouses = nil, false
    for btn = 1, 3 do
        if TravelClickTextMode(dt, btn) ~= "none" then
            local h = TravelFindHouse(TravelClickChoice(dt, btn))
            if h then
                if not firstHouse then firstHouse = h.houseGUID
                elseif h.houseGUID ~= firstHouse then tagHouses = true end
            end
        end
    end
    local n, timer, mask, shownMask = 0, false, 0, 0
    for btn = 1, 3 do
        local cd, known = TravelShownCooldown(dt, btn)
        if cd then
            local mode = TravelClickTextMode(dt, btn)
            local choice = TravelClickChoice(dt, btn)
            local cooling = not known or cd > 0
            shownMask = shownMask + CLICK_BITS[btn]
            if cooling then mask = mask + CLICK_BITS[btn] end
            local dest = TravelBarDestination(choice, tagHouses) or bind
            local part = dest
            if mode ~= "location" then
                local cdStr = known and ns.FormatCooldown(cd) or nil
                if cdStr then timer = true end
                if mode == "smart" then
                    part = cdStr or dest
                elseif mode == "both" then
                    part = cdStr and (dest .. " " .. cdStr) or dest
                else
                    part = cdStr or (known and EllesmereUI.L(L["READY"]) or "-")
                end
            end
            local dup = false
            for i = 1, n do
                if _textRaw[i] == part then dup = true; break end
            end
            if not dup then
                n = n + 1
                _textRaw[n] = part
                _textParts[n] = (cooling and not plain) and ("|cff808080" .. part .. "|r") or part
            end
        end
    end
    for i = n + 1, #_textParts do _textParts[i] = nil; _textRaw[i] = nil end
    local iconDim
    if shownMask == 0 then
        local cd, known = TravelChoiceCooldown(TravelClickChoice(dt, 1))
        iconDim = not known or cd > 0
        mask = iconDim and 1 or 0
    else
        iconDim = mask == shownMask
    end
    if n == 0 then return "", timer, mask, iconDim end
    return table.concat(_textParts, " / ", 1, n), timer, mask, iconDim
end

local function TravelResolveMythicId(idOrTable)
    if type(idOrTable) == "table" then
        for _, id in ipairs(idOrTable) do if IsPlayerSpell(id) then return id end end
        return nil
    end
    if IsPlayerSpell(idOrTable) then return idOrTable end
    return nil
end

-- Season M+ teleports from the shared season list (one update per season).
local SEASON_TELEPORTS = {}
for _, e in ipairs(EllesmereUI.SEASON_PORTALS) do
    local ids = e.spellID
    if e.altSpellIDs then
        ids = { e.spellID }
        for _, a in ipairs(e.altSpellIDs) do ids[#ids + 1] = a end
    end
    SEASON_TELEPORTS[#SEASON_TELEPORTS + 1] = { spellIds = ids, dungeonId = e.dungeonID }
end

ns.BlockFactories.travel = function(blockCfg, slot, content, barCtx)
    local inst = { cfg = blockCfg, slot = slot, content = content, ctx = barCtx }
    inst.key = InstKey(barCtx, blockCfg)
    -- BAG_UPDATE_DELAYED / SPELLS_CHANGED: ownership edges that must clear the negative hearthstone cache (rare at idle, cheap refresh).
    -- Cooldown-START edges ride a player-filtered UNIT_SPELLCAST_SUCCEEDED
    -- registered in Enable (RegisterInstEvents cannot unit-filter): every
    -- hearth start IS a player cast, and BAG_UPDATE_COOLDOWN measured
    -- idle-chatty (~0.7 Hz ambient with nothing cooling).
    inst.events = { "HEARTHSTONE_BOUND", "PLAYER_ENTERING_WORLD",
        "BAG_UPDATE_DELAYED", "SPELLS_CHANGED" }

    local mouseOver = false
    -- Heartbeat demand-gate: the 1s tick runs ONLY while something is cooling,
    -- a timer shows on the bar, or the tooltip is open (live M:SS columns).
    -- Otherwise no tick at all; a player cast announces every start edge and re-arms.
    local ticking = false
    local TravelSyncTicker -- forward declaration, filled in after TravelTick

    -- Pre-allocated tooltip line buffers (no per-show garbage). `spellId` is the static teleport spell ID (click overlay attribute), not the shown `name`.
    local _mythicLinesBuf = {}
    for i = 1, #SEASON_TELEPORTS do _mythicLinesBuf[i] = { name = "", cd = 0, cdKnown = true, spellId = nil } end
    local _mythicLineCount = 0

    local function D() return blockCfg.settings or {} end
    local function BC() return barCtx.cfg end

    local built = false
    local hearthButton, hearthIcon, hearthText
    local placeholder

    local function RefreshTravelTooltip()
        local ar, ag, ab = 1, 1, 1
        ns.Tip_Begin(hearthButton)
        -- Hover-persistent like the spec tip: the cursor can travel onto it to click ready teleport rows, even when no row is clickable right now.
        ns.Tip_MarkInteractive()
        ns.Tip_AddLine("|cFFFFFFFF[|r" .. L["TRAVEL_COOLDOWNS"] .. "|cFFFFFFFF]|r", ar, ag, ab)
        ns.Tip_AddLine(" ")
        local cd2, cdKnown = TravelGetPrimaryCooldown()
        local cdStr
        if cdKnown then
            cdStr = ns.FormatCooldown(cd2)
            if not cdStr then cdStr = L["READY"] end
        else
            cdStr = "-"
        end
        local ready = cdKnown and cd2 <= 0
        local rr, rg, rb = 0.5, 0.5, 0.5
        if ready then rr, rg, rb = 0, 1, 0 end
        -- Click-to-use when ready (shared overlay), always a hearthstone: the left click's when
        -- it is one. White while ready, M+ "On Cooldown" gray otherwise; plain label so state and
        -- hover color the whole line; the plain-state row is pad-marked to match the clickable row.
        local hsLabel = L["HEARTHSTONE"] .. " (" .. (GetBindLocation() or "?") .. ")"
        local hsMacro
        if ready then
            local choice = TravelClickChoice(D(), 1)
            local hsId
            if type(choice) == "number" and not TRAVEL_EXTRA_SET[choice] and TravelIsUsable(choice) then
                hsId = choice
            else
                hsId = TravelPickHearthstone(choice == "random")
            end
            if hsId then hsMacro = TravelBuildMacro(hsId) end
        end
        if hsMacro then
            ns.Tip_AddMacroActionDouble(hsLabel, cdStr, hsMacro, 1, 1, 1, rr, rg, rb)
        else
            local hg = ready and 1 or 0.65
            ns.Tip_AddDouble(hsLabel, cdStr, hg, hg, hg, rr, rg, rb)
            ns.Tip_PadRow()
        end

        -- Travel entries ride the same section, each with its own cooldown. A spell entry
        -- takes the spell-side name/cooldown/click overlay, and IsPlayerSpell gates it to its
        -- class. Name lookups can be nil on a cold cache: the row appears on the next tooltip refresh.
        for _, entryId in ipairs(TRAVEL_EXTRAS) do
            local kind    = TravelExtraKind(entryId)
            local isSpell = kind == "spell"
            if kind then
                local entryName
                if isSpell then
                    local sInfo = C_Spell.GetSpellInfo(entryId)
                    entryName = sInfo and sInfo.name
                else
                    if C_ToyBox and C_ToyBox.GetToyInfo then
                        local _, tn = C_ToyBox.GetToyInfo(entryId)
                        entryName = tn
                    end
                    if not entryName and C_Item and C_Item.GetItemInfo then
                        entryName = C_Item.GetItemInfo(entryId)
                    end
                end
                if entryName then
                    local tcd, tKnown = TravelGetRemainingCooldown(entryId, isSpell)
                    local tstr
                    if tKnown then
                        tstr = ns.FormatCooldown(tcd)
                        if not tstr then tstr = L["READY"] end
                    else
                        tstr = "-"
                    end
                    local tready = tKnown and tcd <= 0
                    local tr, tg, tb = 0.5, 0.5, 0.5
                    if tready then tr, tg, tb = 0, 1, 0 end
                    if tready then
                        -- Ready: click-to-use, same secure overlay contract as the M+ rows
                        -- (degrades to text in combat). Both helpers take the same args; only the seeded secure attribute differs.
                        if kind == "item" then
                            ns.Tip_AddMacroActionDouble(entryName, tstr, TravelBuildMacro(entryId), 1, 1, 1, tr, tg, tb)
                        else
                            local AddActionRow = isSpell and ns.Tip_AddActionDouble
                                                          or ns.Tip_AddToyActionDouble
                            AddActionRow(entryName, tstr, entryId, 1, 1, 1, tr, tg, tb)
                        end
                    else
                        -- On cooldown: same gray as the M+ "On Cooldown" label.
                        ns.Tip_AddDouble(entryName, tstr, 0.65, 0.65, 0.65, tr, tg, tb)
                    end
                end
            end
        end

        local dt = D()
        -- All houses share one visit cooldown.
        local house = TravelFindHouse(TravelClickChoice(dt, 1)) or TravelFindHouse(TravelClickChoice(dt, 2))
            or TravelFindHouse(TravelClickChoice(dt, 3))
        if house then
            local hstr, hready = "-", false
            local returnTrip = TravelCanReturnHome()
            if returnTrip then
                hstr, hready = L["RETURN_AVAILABLE"], true
            else
                local rem, known = TravelHouseCooldown()
                if known then
                    hstr = ns.FormatCooldown(rem) or L["READY"]
                    hready = rem <= 0
                end
            end
            if hready then
                ns.Tip_AddHouseActionDouble(TravelHouseName(house), hstr, house, returnTrip, 1, 1, 1, 0, 1, 0)
            else
                ns.Tip_AddDouble(TravelHouseName(house), hstr, 0.65, 0.65, 0.65, 0.5, 0.5, 0.5)
                ns.Tip_PadRow()
            end
        end

        local altRows = 0
        if dt.altHearths == true then
            altRows = TravelAddAltRows(ar, ag, ab, function() ns.Tip_Hide(hearthButton) end)
        end

        -- Show M+ Portals: nil reads as shown (no migration needed). OFF skips the section and its spell-resolution work entirely.
        -- WoW Forever has no Mythic+ teleports: the section never builds there.
        _mythicLineCount = 0
        if not EllesmereUI.IS_FOREVER and D().clickableTeleports ~= false then
            for _, entry in ipairs(SEASON_TELEPORTS) do
                local spellId = TravelResolveMythicId(entry.spellIds)
                if spellId then
                    local dName = nil
                    if entry.dungeonId and GetLFGDungeonInfo then dName = GetLFGDungeonInfo(entry.dungeonId) end
                    local spInfo = C_Spell.GetSpellInfo(spellId)
                    local spName = spInfo and spInfo.name
                    local name2 = dName
                    if not name2 then name2 = spName end
                    if not name2 then name2 = tostring(spellId) end
                    _mythicLineCount = _mythicLineCount + 1
                    local mcd, mKnown = TravelGetRemainingCooldown(spellId, true)
                    _mythicLinesBuf[_mythicLineCount].name    = name2
                    _mythicLinesBuf[_mythicLineCount].cd      = mcd
                    _mythicLinesBuf[_mythicLineCount].cdKnown = mKnown
                    _mythicLinesBuf[_mythicLineCount].spellId = spellId
                end
            end
        end
        if _mythicLineCount > 0 then
            ns.Tip_AddLine(" ")
            ns.Tip_AddLine(L["MYTHIC_TELEPORTS"], ar, ag, ab)
            -- Insertion sort on active entries only (max ~8)
            for i = 2, _mythicLineCount do
                local j = i
                while j > 1 and _mythicLinesBuf[j].name < _mythicLinesBuf[j - 1].name do
                    _mythicLinesBuf[j].name,    _mythicLinesBuf[j - 1].name    = _mythicLinesBuf[j - 1].name,    _mythicLinesBuf[j].name
                    _mythicLinesBuf[j].cd,      _mythicLinesBuf[j - 1].cd      = _mythicLinesBuf[j - 1].cd,      _mythicLinesBuf[j].cd
                    _mythicLinesBuf[j].cdKnown, _mythicLinesBuf[j - 1].cdKnown = _mythicLinesBuf[j - 1].cdKnown, _mythicLinesBuf[j].cdKnown
                    _mythicLinesBuf[j].spellId, _mythicLinesBuf[j - 1].spellId = _mythicLinesBuf[j - 1].spellId, _mythicLinesBuf[j].spellId
                    j = j - 1
                end
            end
            -- Ready rows are always click-to-teleport (not configurable). On-cooldown teleports share one group, collapsing into one "On Cooldown" line (soonest remaining).
            local cdMin, cdUnknown
            for i = 1, _mythicLineCount do
                local e = _mythicLinesBuf[i]
                if not e.cdKnown then
                    -- Secret cooldown (restricted combat): state unknowable,
                    -- fold into the collapsed On Cooldown line below.
                    cdUnknown = true
                elseif e.cd <= 0 then
                    -- Ready teleport: left-click casts it (secure overlay button
                    -- keyed to the static spell ID; row highlights on hover).
                    ns.Tip_AddActionDouble(e.name, L["READY"], e.spellId, 0.8, 0.8, 0.8, 0, 1, 0)
                elseif not cdMin or e.cd < cdMin then
                    cdMin = e.cd
                end
            end
            if cdMin then
                local cs = ns.FormatCooldown(cdMin)
                if not cs then cs = L["READY"] end
                ns.Tip_AddDouble(L["ON_COOLDOWN"], cs, 0.65, 0.65, 0.65, 0.5, 0.5, 0.5)
            elseif cdUnknown then
                ns.Tip_AddDouble(L["ON_COOLDOWN"], "-", 0.65, 0.65, 0.65, 0.5, 0.5, 0.5)
            end
        end
        ns.Tip_AddLine(" ")
        for btn = 1, 3 do
            local choice = TravelClickChoice(dt, btn)
            if choice ~= "none" then
                local what
                local h = TravelFindHouse(choice)
                if choice == "random" then
                    what = L["RANDOM_HEARTHSTONE"]
                elseif h then
                    what = TravelCanReturnHome() and L["RETURN_FROM_HOME"] or TravelHouseName(h)
                elseif TRAVEL_EXTRA_SET[choice] and TravelExtraKind(choice) then
                    what = TravelEntryName(choice) or L["USE_HEARTHSTONE"]
                else
                    what = L["USE_HEARTHSTONE"]
                end
                local label = (btn == 1 and L["LEFT_CLICK"]) or (btn == 2 and L["RIGHT_CLICK"]) or L["MIDDLE_CLICK"]
                ns.Tip_AddDouble(label, what, 1, 1, 1, ar, ag, ab)
            end
        end
        if altRows > 0 then
            ns.Tip_AddDouble(L["CTRL_ALT_LEFT_CLICK"], L["REMOVE_CHARACTER"], 1, 1, 1, ar, ag, ab)
        end
        ns.Tip_Show()
    end

    local function Build()
        if built then return end
        built = true
        if placeholder then placeholder:Hide() end

        hearthButton = CreateFrame("Button", "EllesmereUIDataBarsHearth_" .. inst.key, content, "SecureActionButtonTemplate")
        -- Up only + useOnKeyDown=false: registering both Up and Down lets the
        -- ActionButtonUseKeyDown CVar fire the macro twice (2nd /use cancels the cast).
        hearthButton:SetAllPoints()
        hearthButton:EnableMouse(true)
        hearthButton:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
        hearthButton:SetAttribute("useOnKeyDown", false)
        -- One explicit pair per button (1 left, 2 right, 3 middle), not an unsuffixed fallback.
        for btn = 1, 3 do
            hearthButton:SetAttribute("*type" .. btn, "macro")
            hearthButton:SetAttribute("*macrotext" .. btn, "")
        end

        hearthIcon   = hearthButton:CreateTexture(nil, "OVERLAY")
        hearthText   = hearthButton:CreateFontString(nil, "OVERLAY")
        AttachTextOffset(inst, hearthText)

        local function SeedMacro()
            if InCombatLockdown() then return end
            local dt = D()
            local canReturn
            for btn = 1, 3 do
                local choice = TravelClickChoice(dt, btn)
                local house = TravelFindHouse(choice)
                if house then
                    if canReturn == nil then canReturn = TravelCanReturnHome() end
                    hearthButton:SetAttribute("*type" .. btn, canReturn and "returnhome" or "teleporthome")
                    hearthButton:SetAttribute("*house-neighborhood-guid" .. btn, house.neighborhoodGUID)
                    hearthButton:SetAttribute("*house-guid" .. btn, house.houseGUID)
                    hearthButton:SetAttribute("*house-plot-id" .. btn, house.plotID)
                    hearthButton:SetAttribute("*macrotext" .. btn, "")
                else
                    hearthButton:SetAttribute("*type" .. btn, "macro")
                    local id = TravelResolveChoice(choice)
                    hearthButton:SetAttribute("*macrotext" .. btn, id and TravelBuildMacro(id) or "")
                end
            end
        end

        -- Reseed on every PreClick (OOC only) so each click fires its current choice
        -- without a protected call from OnClick. SetScript is fine here: WE created this button.
        hearthButton:SetScript("PreClick", function()
            if InCombatLockdown() then return end
            SeedMacro()
        end)

        hearthButton:SetScript("OnEnter", function()
            mouseOver = true
            inst:Refresh()
            RefreshTravelTooltip()
        end)
        hearthButton:SetScript("OnLeave", function()
            mouseOver = false
            -- Interactive tip (clickable M+ rows): the keep-alive poll owns
            -- dismissal so the cursor can travel onto the tip to click a row.
            ns.Tip_HideUnlessInteractive(hearthButton)
            inst:Refresh()
        end)

        -- Seed macrotext shortly after build so a first-combat click works.
        C_Timer.After(1, SeedMacro)
        inst._seedClicks = SeedMacro
    end

    local enabled = false
    local function SyncHouseWatch()
        local dt = D()
        local uses = TravelIsHouseChoice(TravelClickChoice(dt, 1))
            or TravelIsHouseChoice(TravelClickChoice(dt, 2))
            or TravelIsHouseChoice(TravelClickChoice(dt, 3))
        TravelWatchHouses(inst, enabled and uses)
    end

    function inst:OnHouseList()
        if self._seedClicks then self._seedClicks() end
        self:Refresh()
    end

    -- Combat-deferred construction: dimmed non-interactive icon until OOC.
    if InCombatLockdown() then
        placeholder = content:CreateTexture(nil, "OVERLAY")
        K.SetBlockIcon(placeholder, blockCfg)
        placeholder:SetVertexColor(0.6, 0.6, 0.6, 0.6)
        placeholder:SetSize(16, 16)
        placeholder:SetPoint("CENTER")
        ns.DeferUntilOOC("edbbuild:" .. inst.key, function()
            if inst._dead then return end
            Build()
            inst:Refresh()
        end)
    else
        Build()
    end

    local function RelayoutAfterCombat()
        if not inst._dead then inst:Refresh() end
    end
    local layoutKey = "edbtravellayout:" .. inst.key

    function inst:Refresh()
        SyncHouseWatch()
        if D().altHearths == true then TravelSaveMyHearth() end
        if not built then return end
        K.SetBlockIcon(hearthIcon, blockCfg)
        local barCfg = BC()
        local barH = barCtx.GetThickness()
        local fontSize = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))
        local isSide = barCtx.IsVertical()

        local location, barTimer, coolMask, iconDim = TravelBarText(D(), GetBindLocation() or "?", mouseOver)
        inst._barTimer = barTimer
        inst._lastCoolMask = coolMask

        ns.SetFont(hearthText, fontSize, barCfg)

        hearthText:SetText(location)

        TravelSyncTicker(mouseOver or coolMask ~= 0 or barTimer)

        -- Cooling parts carry their own gray; the icon dims only when every shown part cools.
        if mouseOver then
            local ar, ag, ab = ns.GetAccent()
            hearthText:SetTextColor(ar, ag, ab, 1); hearthIcon:SetVertexColor(ar, ag, ab, 1)
        else
            local br, bgr, bb = BlockColorOf(blockCfg)
            hearthText:SetTextColor(br, bgr, bb, 1)
            if iconDim then
                hearthIcon:SetVertexColor(0.5, 0.5, 0.5, 1)
            else
                local ir, ig, ib = IconColorOf(blockCfg)
                hearthIcon:SetVertexColor(ir, ig, ib, 1)
            end
        end

        -- The secure button cannot resize in combat: lay out again once it ends.
        if InCombatLockdown() then
            ns.DeferUntilOOC(layoutKey, RelayoutAfterCombat)
            return
        end

        -- +2 icon size, -2 gap: hearthstone runs bigger and tighter than default.
        local iconSz, gap = fontSize + 2, ICON_GAP - 2
        if isSide then
            iconSz = min(iconSz, max(14, floor(CONTENT_BASE * 0.72 + 0.5)))
        end
        hearthIcon:ClearAllPoints()
        hearthIcon:SetSize(iconSz, iconSz)

        if isSide then
            local slotW = VSlotW(inst)
            local innerW = max(30, slotW - 8)
            local totalH = 8 + iconSz + 2

            content:SetWidth(slotW)
            hearthButton:SetWidth(slotW)
            hearthIcon:SetPoint("TOP", hearthButton, "TOP", 0, -4)

            ns.SetWrappedText(hearthText, innerW, "CENTER")
            hearthText:ClearAllPoints()
            hearthText:SetPoint("TOP", hearthIcon, "BOTTOM", 0, -2)
            totalH = totalH + ns.SnapToPixelGrid(hearthText:GetStringHeight())

            totalH = max(totalH, barH)
            content:SetHeight(totalH)
            hearthButton:SetHeight(totalH)
        else
            local slotW = HBudget(inst, 120)
            ns.SetFont(hearthText, fontSize, barCfg)
            hearthText:SetText(location)
            -- +2 matches the top-of-Refresh sizing: this branch re-derives iconSz, which would otherwise silently swallow earlier size bumps.
            iconSz = min(fontSize + 2, max(14, floor(CONTENT_BASE * 0.72 + 0.5)))
            hearthIcon:SetSize(iconSz, iconSz)
            ns.ResetInlineText(hearthText, "LEFT")
            local tw = ns.SnapToPixelGrid(hearthText:GetStringWidth())
            -- A counting timer sizes as all-zero digits (measured off screen) and never
            -- shrinks, so the bar holds still.
            if inst._barTimer then
                local zeroW = 0
                local mfs = ns.MeasureFS()
                if mfs then
                    ns.SetFont(mfs, fontSize, barCfg)
                    mfs:SetText((location:gsub("%d", "0")))
                    zeroW = ns.SnapToPixelGrid(mfs:GetStringWidth())
                end
                tw = max(tw, zeroW, inst._trvPeakW or 0)
                inst._trvPeakW = tw
            else
                inst._trvPeakW = nil
            end
            if location == "" then tw = 0; gap = 0 end
            local totalW = min(slotW, iconSz + gap + tw + 4)
            content:SetSize(totalW, barH)
            hearthButton:SetSize(totalW, barH)
            hearthIcon:SetPoint("LEFT", hearthButton, "LEFT", 0, 0)
            hearthText:ClearAllPoints(); hearthText:SetPoint("LEFT", hearthButton, "LEFT", iconSz + gap, 0)
        end
        MaybeRelayout(inst)
    end

    -- 1s heartbeat. Hovered: the open tooltip's M:SS columns need per-second full
    -- refreshes. Un-hovered: a cooling probe of the shown parts; Refresh runs when
    -- any part's state changes, and each second while a timer shows on the bar.
    local function TravelTick()
        if built and mouseOver and ns.Tip_IsOwned(hearthButton) then
            inst:Refresh()
            RefreshTravelTooltip()
            return
        end
        -- Unknown (secret) cooldowns count as cooling: the probe keeps ticking through combat and self-corrects on the first clean read.
        local coolMask = TravelCoolingMask(D())
        if coolMask ~= inst._lastCoolMask then
            inst:Refresh()
        elseif inst._barTimer then
            inst:Refresh()
        elseif coolMask == 0 and not mouseOver then
            -- Settled ready with no edge to paint: nothing left to watch.
            TravelSyncTicker(false)
        end
    end

    -- Fills the forward declaration above. Register/unregister is flag-guarded
    -- so redundant syncs cost one boolean test.
    TravelSyncTicker = function(want)
        if want then
            if not ticking then
                ticking = true
                ns.RegisterHeartbeat("travel:" .. inst.key, TravelTick)
            end
        elseif ticking then
            ticking = false
            ns.UnregisterHeartbeat("travel:" .. inst.key)
        end
    end

    inst.eventFrame = MakeEventFrame(inst, function(self, event)
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            -- Cooldown-START lane (player casts only; every hearth start is
            -- one): never invalidates the hearthstone pick, and while the
            -- ticker already runs there is nothing to learn. One probe on a
            -- start edge re-arms the tick; zero fires standing idle.
            -- With timer text on, a full Refresh also reads the click cooldowns
            -- the hearthstone probe does not watch.
            if not ticking then
                if TravelAnyTimerText(D()) and not InCombatLockdown() then self:Refresh() else TravelTick() end
            end
            return
        end
        ns.TravelInvalidateHearthCache()
        self:Refresh()
    end)

    function inst:Enable()
        enabled = true
        SyncHouseWatch()
        content:Show()
        RegisterInstEvents(self)
        -- Player-filtered registration; Disable's UnregisterAllEvents drops it,
        -- so it re-registers here (re-registration is idempotent).
        pcall(self.eventFrame.RegisterUnitEvent, self.eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player")
        -- Armed at enable as a belt; the first settled ready read stands it
        -- down (TravelTick's else branch or any Refresh).
        TravelSyncTicker(true)
    end

    function inst:Disable()
        enabled = false
        TravelWatchHouses(self, false)
        TravelSyncTicker(false)
        UnregisterInstEvents(self)
        content:Hide()
    end

    function inst:GetAutoLength()
        if not built then return 40 end
        local barH = barCtx.GetThickness()
        if barCtx.IsVertical() then
            local fontSize = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))
            local iconSz = fontSize
            local textH = hearthText:GetStringHeight() or fontSize
            return max(8 + iconSz + 2 + textH + 4, barH, 50)
        end
        return max(content:GetWidth() or 120, 40)
    end

    function inst:Destroy()
        self._dead = true
        enabled = false
        TravelWatchHouses(self, false)
        if hearthButton then
            ParkSecureFrame(hearthButton, self.key .. "_hearth")
        end
        content:Hide()
    end

    return inst
end
