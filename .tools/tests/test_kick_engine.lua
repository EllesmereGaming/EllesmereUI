-- Stub harness: loads the Kick Tracker data and engine outside the game and
-- plays kick scenarios through them, with hidden values simulated by a
-- sentinel that errors on any use.
--   lua .tools/tests/test_kick_engine.lua EllesmereUIMythicTimer
local DIR = arg[1]

local SECRET = setmetatable({}, {
    __tostring = function() error("tostring on a secret", 2) end,
    __concat = function() error("concat on a secret", 2) end,
    __lt = function() error("compare on a secret", 2) end,
    __le = function() error("compare on a secret", 2) end,
    __index = function() error("index on a secret", 2) end,
    __len = function() error("length of a secret", 2) end,
})
-- Hidden numbers that carry their value: any use by the engine errors like
-- the sentinel's, and only the test reads the value back (BOXVAL).
local BOXVAL = setmetatable({}, { __mode = "k" })
local function BoxErr() error("use of a hidden number", 2) end
local BOXMT = { __tostring = BoxErr, __concat = BoxErr, __lt = BoxErr, __le = BoxErr, __index = BoxErr, __len = BoxErr,
    __add = BoxErr, __sub = BoxErr, __mul = BoxErr, __div = BoxErr, __unm = BoxErr }
local function Box(n)
    local b = setmetatable({}, BOXMT)
    BOXVAL[b] = n
    return b
end
local function Unbox(v)
    if type(v) == "table" and BOXVAL[v] ~= nil then return BOXVAL[v] end
    return v
end
issecretvalue = function(v) return rawequal(v, SECRET) or (type(v) == "table" and BOXVAL[v] ~= nil) end
securecallfunction = function(fn, ...) return fn(...) end
unpack = unpack or table.unpack  -- the local interpreter is 5.4; the game's is 5.1
SlashCmdList = {}  -- slash commands register here

local now = 100
GetTime = function() return now end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
Clamp = function(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end

local frames = {}
local function NewFrame()
    local f = { events = {}, units = {}, scripts = {} }
    function f:SetScript(k, fn) self.scripts[k] = fn end
    function f:RegisterEvent(e) self.events[e] = true end
    -- A unit event keeps the unit list it was last registered with, and
    -- Fire delivers it only for a unit on that list, as the game does.
    function f:RegisterUnitEvent(e, ...) self.events[e] = true; self.units[e] = { ... } end
    function f:UnregisterEvent(e) self.events[e] = nil; self.units[e] = nil end
    function f:UnregisterAllEvents() self.events = {}; self.units = {} end
    frames[#frames + 1] = f
    return f
end
CreateFrame = function() return NewFrame() end

local function Fire(event, ...)
    local unit = ...
    for _, f in ipairs(frames) do
        if f.events[event] and f.scripts.OnEvent then
            local list = f.units[event]
            local listened = not list
            if list then
                for i = 1, #list do
                    if list[i] == unit then listened = true break end
                end
            end
            if listened then f.scripts.OnEvent(f, event, ...) end
        end
    end
end

-- The units whose UNIT_SPELLCAST_SUCCEEDED the engine listens to, over every
-- frame registered for it (one frame per unit), in roster order.
local CAST_TOKENS = { "player", "pet", "party1", "partypet1", "party2", "partypet2", "party3", "partypet3", "party4", "partypet4" }
local function CastUnits()
    local heard = {}
    for _, f in ipairs(frames) do
        local list = f.events.UNIT_SPELLCAST_SUCCEEDED and f.units.UNIT_SPELLCAST_SUCCEEDED
        for i = 1, list and #list or 0 do heard[list[i]] = true end
    end
    local out = {}
    for i = 1, #CAST_TOKENS do
        if heard[CAST_TOKENS[i]] then out[#out + 1] = CAST_TOKENS[i] end
    end
    return #out > 0 and table.concat(out, " ") or "-"
end

local timers = {}
C_Timer = { After = function(d, fn) timers[#timers + 1] = { at = now + d, fn = fn } end }
local function Advance(dt)
    local target = now + dt
    while true do
        local nextT
        for _, t in ipairs(timers) do
            if t.at <= target and (not nextT or t.at < nextT) then nextT = t.at end
        end
        if not nextT then break end
        now = nextT
        local due, keepT = {}, {}
        for _, t in ipairs(timers) do
            if t.at <= now then due[#due + 1] = t else keepT[#keepT + 1] = t end
        end
        timers = keepT
        for _, t in ipairs(due) do t.fn() end
    end
    now = target
end

Enum = {
    DamageMeterType = { DamageDone = 0, HealingDone = 2, Interrupts = 5 },
    DamageMeterSessionType = { Overall = 0, Current = 1 },
    AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3 },
    AddOnRestrictionState = { Inactive = 0, Activating = 1, Active = 2 },
}
Constants = { TraitConsts = { INSPECT_TRAIT_CONFIG_ID = -1 } }
local inCombat, keyActive = false, false
C_RestrictedActions = { IsAddOnRestrictionActive = function(t)
    if t == 0 then return inCombat end
    if t == 2 then return keyActive end
    return false
end }
InCombatLockdown = function() return inCombat end

-- Specs: id -> class token; icon = 100000 + id.
local SPECS = {
    [70] = { "PALADIN", 2 }, [66] = { "PALADIN", 2 }, [65] = { "PALADIN", 2 },
    [71] = { "WARRIOR", 1 }, [73] = { "WARRIOR", 1 },
    [63] = { "MAGE", 8 }, [251] = { "DEATHKNIGHT", 6 }, [264] = { "SHAMAN", 7 }, [262] = { "SHAMAN", 7 },
    [102] = { "DRUID", 11 }, [105] = { "DRUID", 11 }, [266] = { "WARLOCK", 9 }, [265] = { "WARLOCK", 9 },
}
local CLASS_SPECS = {}
for id, v in pairs(SPECS) do
    CLASS_SPECS[v[2]] = CLASS_SPECS[v[2]] or {}
    table.insert(CLASS_SPECS[v[2]], id)
end
for _, list in pairs(CLASS_SPECS) do table.sort(list) end
GetNumSpecializationsForClassID = function(cid) return CLASS_SPECS[cid] and #CLASS_SPECS[cid] or 0 end
GetSpecializationInfoForClassID = function(cid, i)
    local id = CLASS_SPECS[cid] and CLASS_SPECS[cid][i]
    if not id then return nil end
    return id, "Spec" .. id, "", 100000 + id
end
GetSpecializationInfoByID = function(id) return id, "Spec" .. id, "", 100000 + id end

-- The group: unit -> { guid, spec, name, role, talents = set, pet = family, kick = own kick spell }.
local G = {}
local function ClassOf(u) local s = G[u] and SPECS[G[u].spec]; return s and s[1], s and s[2] end
-- A demon's GUID: its creature ID from its family, a serial from its owner.
local DEMON_NPC = { Felhunter = 417, Felguard = 17252 }
local function PetOwner(u) return (u == "pet") and "player" or u:match("^partypet(%d)$") and ("party" .. u:match("(%d)$")) or nil end
local function PetGUID(owner)
    local m = G[owner]
    if not (m and m.pet) then return nil end
    return "Pet-0-1-2-3-" .. (DEMON_NPC[m.pet] or 1) .. "-" .. m.guid:sub(-4)
end
UnitGUID = function(u)
    if G[u] then return G[u].guid end
    local owner = PetOwner(u)
    return owner and PetGUID(owner) or nil
end
UnitExists = function(u)
    if G[u] then return true end
    local owner = PetOwner(u)
    return owner and G[owner] and G[owner].pet ~= nil or false
end
-- A member marked hideClass reads as a unit whose identity is restricted.
UnitClass = function(u)
    if G[u] and G[u].hideClass then return SECRET, SECRET, SECRET end
    local c, id = ClassOf(u); return c, c, id
end
UnitClassBase = function(u) local c, id = ClassOf(u); return c, id end
UnitName = function(u) return G[u] and G[u].name end
UnitGroupRolesAssigned = function(u) return G[u] and G[u].role or "NONE" end
UnitIsConnected = function() return true end
UnitIsPlayer = function(u) return G[u] ~= nil and not G[u].npc end
UnitCreatureFamily = function(u)
    local owner = (u == "pet") and "player" or u:match("^(party%d)pet$") or u:gsub("partypet", "party")
    return G[owner] and G[owner].pet
end
IsPlayerSpell = function(sid) return G.player.talents[sid] == true end
EllesmereUI = {
    GetActiveKickSpell = function() return G.player.kick end,
    IsSecret = function(v) return v ~= nil and issecretvalue(v) end,
    PlainString = function(v)
        if type(v) == "string" and not issecretvalue(v) and v ~= "" then return v end
        return nil
    end,
}
C_SpecializationInfo = {
    GetSpecialization = function() return 1 end,
    GetSpecializationInfo = function() return G.player.spec end,
    GetNumSpecializationsForClassID = function(cid) return CLASS_SPECS[cid] and #CLASS_SPECS[cid] or 0 end,
    GetInspectSpecialization = function(u) return G[u] and G[u].spec end,
}
GetPlayerInfoByGUID = function(g)
    if rawequal(g, SECRET) then return SECRET, SECRET end
    for _, m in pairs(G) do if m.guid == g then return "x", SPECS[m.spec][1] end end
end

-- Inspect: the engine asks, the data arrives a moment later.
local inspectTarget
local inspects = 0
CanInspect = function(u) return G[u] and G[u].inRange ~= false end
NotifyInspect = function(u)
    inspects = inspects + 1
    inspectTarget = u
    local guid = G[u].guid
    C_Timer.After(0.1, function() Fire("INSPECT_READY", guid) end)
end
ClearInspectPlayer = function() inspectTarget = nil end
C_Traits = {
    HasValidInspectData = function() return inspectTarget ~= nil end,
    GetConfigInfo = function(cfg) if cfg == -1 and inspectTarget then return { treeIDs = { 1 } } end end,
    GetTreeNodes = function()
        local list = {}
        for sid in pairs(G[inspectTarget].talents) do list[#list + 1] = sid end
        list[#list + 1] = 999 -- an unpurchased node
        table.sort(list)
        return list
    end,
    GetNodeInfo = function(cfg, nid)
        if nid == 999 then return { activeRank = 0 } end
        return { activeRank = 1, activeEntry = { entryID = nid, rank = 1 } }
    end,
    GetEntryInfo = function(cfg, eid) return { definitionID = eid } end,
    GetDefinitionInfo = function(did) return { spellID = did } end,
}

-- Meter state: kicks per unit, the distinct enemy spells each kicked, and when;
-- enemyRows: rows of enemies that interrupted a player (no class, no spec icon).
local kicks, spells, order, lastAt = {}, {}, {}, {}
local petSpells = {}        -- unit -> the enemy spells their demon kicked (the demon's own breakdown)
local noSpecIcon = {}       -- unit -> true: the meter files their rows with no spec icon
local petKicks = {}         -- unit -> true: their kicks are their demon's, never in their own breakdown
local function SpecIconOf(u)
    if noSpecIcon[u] then return nil end
    return 100000 + G[u].spec
end
local enemyRows = 1
local hiddenSpells = false  -- a key: the plate's stop event hides the enemy's spell
local function Amt(n) if inCombat then return Box(n) end return n end
local function Sorted()
    -- Descending count; a tie lists the most recent kicker first (as the
    -- game did in the owner's first run).
    local list = {}
    for _, u in ipairs(order) do list[#list + 1] = u end
    table.sort(list, function(a, b)
        if kicks[a] ~= kicks[b] then return kicks[a] > kicks[b] end
        return lastAt[a] > lastAt[b]
    end)
    return list
end
C_DamageMeter = {
    GetCombatSessionFromType = function(st, t)
        local src = {}
        if t == 5 then
            for _, u in ipairs(Sorted()) do
                src[#src + 1] = { classFilename = ClassOf(u), specIconID = SpecIconOf(u), isLocalPlayer = (u == "player"),
                    sourceGUID = inCombat and SECRET or G[u].guid, totalAmount = Amt(kicks[u]) }
            end
            -- An enemy that interrupted a player has a row too: no class, no spec icon.
            for e = 1, enemyRows do
                src[#src + 1] = { isLocalPlayer = false, sourceGUID = inCombat and SECRET or ("Creature-0-1-2-3-4-" .. e),
                    totalAmount = Amt(1) }
            end
        elseif t == 0 then
            for u in pairs(G) do
                src[#src + 1] = { classFilename = ClassOf(u), specIconID = SpecIconOf(u), isLocalPlayer = (u == "player"),
                    sourceGUID = inCombat and SECRET or G[u].guid, totalAmount = Amt(1000) }
            end
        end
        return { totalAmount = Amt(0), combatSources = src }
    end,
    GetCombatSessionSourceFromType = function(st, t, guid)
        for u, m in pairs(G) do
            if m.guid == guid then
                local list = {}
                for sid in pairs(spells[u] or {}) do list[#list + 1] = { spellID = inCombat and SECRET or sid, totalAmount = Amt(1) } end
                -- A member whose kicks are their demon's has none of their own.
                return { totalAmount = Amt(petKicks[u] and 0 or (kicks[u] or 0)), combatSpells = list }
            end
            -- The demon: a source of its own, its kicks and enemy spells.
            if m.pet and PetGUID(u) == guid then
                local list = {}
                for sid in pairs(petSpells[u] or {}) do list[#list + 1] = { spellID = inCombat and SECRET or sid, totalAmount = Amt(1) } end
                return { totalAmount = Amt(petKicks[u] and (kicks[u] or 0) or 0), combatSpells = list }
            end
        end
        return { totalAmount = 0, combatSpells = {} }
    end,
}

-- Load the module files.
-- The parent's interrupt data (EllesmereUI_KickData.lua, next to the module
-- folder), then the engine over the Where file's nameplate lists.
assert(loadfile(DIR .. "/../EllesmereUI_KickData.lua"))()
local ns = { MTWhere = {}, NAMEPLATE_TOKENS = {}, NAMEPLATE_UNITS = {} }
for i = 1, 40 do
    ns.NAMEPLATE_TOKENS[i] = "nameplate" .. i
    ns.NAMEPLATE_UNITS["nameplate" .. i] = true
end
for _, file in ipairs({ "EUI_MythicTimer_KickEngine.lua" }) do
    local chunk = assert(loadfile(DIR .. "/" .. file))
    chunk("EllesmereUIMythicTimer", ns)
end
local KD, KE = EllesmereUI.KickData, ns.KickEngine
assert(KD and KE, "engine not published")

local log = {}
local cdlog = {}
-- Kicks the engine placed for sure (kick lines with a kicker) and gate
-- packets: who in each packet's list had a count that rose (the one its
-- display would show), and its plates.
local placedAt = {}         -- { t, who }
local gatelog = {}          -- { t, rose = list, plates = list, platesOnly }
KE.Subscribe("test", {
    kick = function(unit, who, cands, by, how, t)
        local c = cands and ("[" .. table.concat(cands, ",") .. "]") or "-"
        log[#log + 1] = string.format("%s: %s by %s %s", unit, tostring(who), how, c)
        if who then placedAt[#placedAt + 1] = { t = t, who = who } end
    end,
    cooldown = function(unit, start, dur)
        cdlog[#cdlog + 1] = string.format("%s cd %s", unit, dur and string.format("%g", dur) or "nil")
        if start then placedAt[#placedAt + 1] = { t = start, who = unit, cd = true } end
    end,
    gate = function(t, units, before, after, plates, platesOnly)
        local rose = {}
        for i = 1, #units do
            local u = units[i]
            local b, a = Unbox(before[u]), Unbox(after[u])
            assert(type(b) == "number" and type(a) == "number", "gate counts must be numbers for " .. u)
            assert(b >= 1 and a >= 1, "a gate member has interrupted already: " .. u)
            if a > b then rose[#rose + 1] = u end
        end
        local p = {}
        for i = 1, #plates do p[i] = plates[i] end
        gatelog[#gatelog + 1] = { t = t, rose = rose, plates = p, platesOnly = platesOnly }
    end,
    roster = function() end,
})

-- Every landed kick of another member the meter counted (truth), checked at
-- the end: shown exactly once, either placed for sure or by the one gate
-- riser of its update, and nobody else ever shown for it. `grip` marks an
-- interrupt that is no kick (the member's kick cannot be ready), shown by
-- neither.
local truth = {}            -- { t, kicker, grip, plate }
local function Truth(u, grip, plate) truth[#truth + 1] = { t = now, kicker = u, grip = grip or false, plate = plate } end

local function Near(a, b) return math.abs(a - b) <= 0.3 end
local function Has(list, x)
    for i = 1, #list do if list[i] == x then return true end end
    return false
end
-- The check over everything recorded since `from` (truth index): every kick
-- shown (a cooldown started for the kicker at the kick, or the kicker the one
-- riser of a gate packet at it), a grip shown by neither, every gate riser a
-- real kicker of that moment, and a kick on a plate nobody was placed on
-- carried to that plate by a packet whose one riser is the kicker.
local function CheckTruth(from)
    for i = from or 1, #truth do
        local k = truth[i]
        local cd, gated = false, false
        for _, p in ipairs(placedAt) do
            if p.cd and p.who == k.kicker and Near(p.t, k.t) then cd = true end
        end
        for _, g in ipairs(gatelog) do
            if Near(g.t, k.t) and Has(g.rose, k.kicker) then gated = true end
        end
        if k.grip then
            assert(not cd and not gated, "a grip was shown as a kick: " .. k.kicker .. " at " .. k.t)
        else
            assert(cd or gated, "a kick was never shown: " .. k.kicker .. " at " .. k.t)
            if k.plate and not cd then
                local onPlate = false
                for _, g in ipairs(gatelog) do
                    if Near(g.t, k.t) and Has(g.plates, k.plate) then
                        assert(#g.rose == 1 and g.rose[1] == k.kicker, "the plate's packet must show the kicker alone: " .. k.plate)
                        onPlate = true
                    end
                end
                assert(onPlate, "a kick's plate never got its packet: " .. k.kicker .. " on " .. k.plate .. " at " .. k.t)
            end
        end
    end
    for _, g in ipairs(gatelog) do
        for _, u in ipairs(g.rose) do
            local real = false
            for _, k in ipairs(truth) do
                if k.kicker == u and Near(k.t, g.t) then real = true end
            end
            assert(real, "a gate riser who did not kick: " .. u .. " at " .. g.t)
        end
    end
end

local function Join(u, guid, spec, name, role, talents, pet)
    G[u] = { guid = guid, spec = spec, name = name, role = role, talents = talents or {}, pet = pet }
    if u == "player" then G.player.kick = G.player.kick end
    Fire("GROUP_ROSTER_UPDATE")
end

-- A kick: who (unit), the enemy spell it stopped, the plate unit; landed or a
-- miss. grip: an interrupt that is no kick (for the truth check).
local function Kick(u, enemySpell, landed, plate, noMeter, grip)
    if u == "player" then
        Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c", G.player.kick)
        if landed == false then return end
        Advance(0.12) -- the server round trip
    end
    if landed == false then return end
    if not kicks[u] then kicks[u] = 0; order[#order + 1] = u end
    kicks[u] = kicks[u] + 1
    lastAt[u] = now
    spells[u] = spells[u] or {}
    petSpells[u] = petSpells[u] or {}
    if petKicks[u] then petSpells[u][enemySpell] = true else spells[u][enemySpell] = true end
    if u ~= "player" and not noMeter then Truth(u, grip, plate) end
    if plate then Fire("UNIT_SPELLCAST_INTERRUPTED", plate, "c", hiddenSpells and SECRET or enemySpell, SECRET, 7) end
    if not noMeter then
        Fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 5, 2)
        Fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 5, 0)
    end
end

local function Pull()
    inCombat = true
    kicks, spells, order, lastAt, petSpells = {}, {}, {}, {}, {}
    enemyRows = 1
    Fire("DAMAGE_METER_CURRENT_SESSION_UPDATED")
end
local function EndPull()
    inCombat = false
    Fire("PLAYER_REGEN_ENABLED")
    Fire("ADDON_RESTRICTION_STATE_CHANGED", 0, 0)
    Advance(3)
end

-- Two Retribution paladins, as in the owner's run.
G.player = { guid = "Player-1-AAAA0001", spec = 70, name = "Main", role = "DAMAGER", talents = { [96231] = true }, kick = 96231 }
G.party1 = { guid = "Player-1-BBBB0002", spec = 70, name = "Alt", role = "DAMAGER", talents = { [96231] = true } }
Fire("PLAYER_ENTERING_WORLD")
Advance(1)
assert(inspects == 1, "party1 should have been inspected once, got " .. inspects)
assert(KE.Member("party1").talents[96231], "inspect did not read Rebuke")
assert(KE.Member("party1").kick == 96231 and KE.Member("party1").landedCd == 15, "party1 Rebuke 15")
assert(KE.Member("player").kick == 96231 and KE.Member("player").cd == 15, "player Rebuke 15")

Pull()
Advance(2); Kick("party1", 430109, true, "nameplate3")     -- new row + breakdown -> Alt
Advance(5); Kick("player", 430109, true, "nameplate3")     -- your cast, landed
Advance(5); Kick("party1", 430109, true, "nameplate4")     -- reorder -> Alt
Advance(16); Kick("party1", 430109, true, "nameplate4")    -- no change: a repeat of a spell only Alt's list holds -> Alt
Advance(5); Kick("player", 0, false)                       -- your missed kick: cooldown only
Advance(1); Kick("party1", 1, true, "nameplate5", true)    -- a landed kick the meter never reports
Advance(1.5)
EndPull()

-- Four more join: a warrior with Honed Reflexes, a mage with Quick Witted, a
-- Restoration shaman (no talents: Wind Shear 30 s from the spec).
Join("party2", "Player-1-CCCC0003", 71, "Third", "DAMAGER", { [391271] = true })
Join("party3", "Player-1-DDDD0004", 63, "Fourth", "DAMAGER", { [382297] = true })
Join("party4", "Player-1-EEEE0005", 264, "Healer", "HEALER", { [57994] = true })
Advance(2)
assert(inspects == 4, "three more inspects, got " .. inspects)
assert(KE.Member("party2").kick == 6552 and KE.Member("party2").landedCd == 13.5, "warrior Pummel 13.5 with Honed Reflexes")
assert(KE.Member("party3").kick == 2139 and KE.Member("party3").landedCd == 20, "mage Counterspell 20 with Quick Witted")
assert(KE.Member("party4").kick == 57994 and KE.Member("party4").landedCd == 30, "resto shaman Wind Shear 30")

Pull()
Advance(2); Kick("party1", 501, true, "nameplate3")        -- new row + breakdown -> Alt
Advance(3); Kick("party2", 500, true, "nameplate4")        -- new row + breakdown -> Third
Advance(14); Kick("party1", 501, true, "nameplate3")       -- Alt 2 > Third 1: reorder -> Alt
Advance(16); Kick("party1", 502, true, "nameplate5")       -- a new enemy spell for Alt: breakdown -> Alt
Advance(3); Kick("party2", 500, true, "nameplate4")        -- Third 2 < Alt 3: no change; only Third's list holds 500 -> Third
Advance(15); Kick("party1", 501, true, "nameplate3")       -- the top kicker repeats a spell: nothing changes; only Alt's list holds 501 -> Alt
EndPull()

-- A DK with Coldthirst: 12 s after a landed kick, 15 plain.
Join("party2", "Player-1-FFFF0006", 251, "Knight", "DAMAGER", { [47528] = true, [378848] = true })
Advance(2)
assert(KE.Member("party2").kick == 47528 and KE.Member("party2").cd == 15 and KE.Member("party2").landedCd == 12, "DK Mind Freeze 15/12")
Pull()
Advance(2); Kick("party2", 600, true, "nameplate6")
EndPull()

-- The meter a frame or two apart from the plate event, either way round:
-- the plate still takes the meter's answer inside the pairing window.
local function Landed(u, enemySpell, grip)
    if not kicks[u] then kicks[u] = 0; order[#order + 1] = u end
    kicks[u] = kicks[u] + 1
    lastAt[u] = now
    spells[u] = spells[u] or {}
    petSpells[u] = petSpells[u] or {}
    if petKicks[u] then petSpells[u][enemySpell] = true else spells[u][enemySpell] = true end
    if u ~= "player" then Truth(u, grip) end
end
Pull()
Advance(12)                                                              -- the DK's kick from the last pull is back
Fire("UNIT_SPELLCAST_INTERRUPTED", "nameplate7", "c", 700, SECRET, 7)   -- plate first
Advance(0.1)
Landed("party2", 700)
Fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 5, 2)                        -- meter 0.1 s later
Advance(5)
Landed("party1", 701)
Fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 5, 2)                        -- meter first
Advance(0.1)
Fire("UNIT_SPELLCAST_INTERRUPTED", "nameplate8", "c", 701, SECRET, 7)   -- plate 0.1 s later
Advance(0.5)
Fire("UNIT_SPELLCAST_INTERRUPTED", "nameplate9", "c", 702, SECRET, 7)   -- a plate 0.6 s on: the answer is taken, so unknown
Advance(1)
-- A kick on a mob this client has no plate for (the DK, off screen), then
-- another member's kick on a plate within the window, its cast stop
-- processed before its own update (a kick's update lands in the frame of
-- its stop, in either order): the plate waits a frame and takes the update
-- of its own frame, never the earlier verdict (which took it before, and
-- put the DK on the Alt's mob).
Advance(20)
Landed("party2", 703)
Fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 5, 2)                        -- the DK's breakdown, no plate
Advance(0.1)
Landed("party1", 704)
Fire("UNIT_SPELLCAST_INTERRUPTED", "nameplate19", "c", 704, SECRET, 7)  -- the Alt's stop first
Fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 5, 2)                        -- her update, the same frame
assert(log[#log] == "nameplate19: party1 by breakdown -", "the plate took the update of its own frame: " .. tostring(log[#log]))
Advance(3.5)   -- the DK's kick is back before the next pull's
EndPull()

-- A Holy paladin and a new Retribution paladin join inside a pull, so neither
-- is inspected and the meter's GUIDs are hidden: both specs unknown. The Holy,
-- a healer, has no interrupt and is never a candidate; the Ret's own rows
-- teach the engine their spec.
Pull()
Join("party3", "Player-1-ABCD0007", 65, "Holy", "HEALER", {})
Join("party1", "Player-1-ABCD0008", 70, "Ret", "DAMAGER", { [96231] = true })
Advance(1)
assert(KE.Member("party3").kick == false, "a healer paladin has no kick")
assert(KE.Member("party1").kick == 96231 and KE.Member("party1").specIcon == nil, "unknown-spec paladin: Rebuke assumed, spec unknown")
Advance(2); Kick("party1", 901, true, "nameplate10")       -- the Ret: new row + breakdown; the one new row names the spec
assert(KE.Member("party1").specIcon == 100070 and KE.Member("party1").specID == 70 and KE.Member("party1").specSrc == "row", "spec learned from the Ret's own row")
assert(KE.Member("party3").specIcon == nil, "the Holy learned nothing from the Ret's row")
Advance(3); Kick("party2", 900, true, "nameplate11")       -- the DK: new row + breakdown (the newer kick sorts first on a tie)
Advance(16); Kick("party1", 901, true, "nameplate12")      -- Ret 2 > DK 1: reorder -> the Ret (the Holy is never a candidate)
Advance(16); Kick("party1", 901, true, "nameplate13")      -- no change: only the Ret's list holds 901 -> the Ret (the Holy is never a candidate)
EndPull()

-- Repeats. A member kicking a spell they kicked before changes nothing in
-- the meter: the kick goes to the one member whose list is known to hold
-- that spell; two who hold it are narrowed by cooldown, or left ambiguous;
-- a member whose list gained an entry no plate named (a mob with no plate)
-- could hold anything.
Pull()
Advance(16); Kick("party1", 950, true, "nameplate20")      -- new row + breakdown -> the Ret (list: 950; the Ret's kick from the last pull is back)
Advance(3); Kick("party2", 950, true, "nameplate21")       -- new row + breakdown -> the DK (list: 950)
Advance(13); Kick("party2", 951, true, "nameplate22")      -- breakdown -> the DK (list: 950, 951)
Advance(13); Kick("party2", 952, true, "nameplate23")      -- breakdown -> the DK (list: 950, 951, 952)
Advance(3); Kick("party1", 950, true, "nameplate20")       -- both lists hold 950; the DK kicked 3 s ago -> the Ret by cooldown
Advance(10); Kick("party2", 951, true, "nameplate22")      -- only the DK's list holds 951 -> the DK
Advance(14); Kick("party1", 950, true, "nameplate20")      -- both lists hold 950, both could be ready -> ambiguous
Advance(2); Kick("party4", 953, true, nil)                 -- the shaman kicks a mob with no plate: an entry no plate names
Advance(3); Kick("party2", 952, true, "nameplate23")       -- the DK's list holds 952, the shaman's could; the shaman kicked 3 s ago -> the DK by cooldown
EndPull()

-- A second Retribution paladin: a moved row names two members, and the
-- plate's spell, arriving a frame after the meter, picks the one whose list
-- holds it.
Join("party3", "Player-1-ABCD0009", 70, "Ret2", "DAMAGER", { [96231] = true })
Advance(2)
Pull()
Advance(2); Kick("party2", 963, true, "nameplate30")       -- new row + breakdown -> the DK (list: 963)
Advance(3); Kick("party1", 960, true, "nameplate31")       -- new row + breakdown -> the Ret (list: 960)
Advance(3); Kick("party3", 962, true, "nameplate32")       -- new row + breakdown -> Ret2 (list: 962)
Advance(7); Kick("party2", 963, true, "nameplate30")       -- the DK 2 > 1: reorder -> the DK
Advance(9)
Landed("party3", 962)
Fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 5, 2)          -- meter first: a paladin row moves up, two Rets could be it
Advance(0.1)
Fire("UNIT_SPELLCAST_INTERRUPTED", "nameplate32", "c", 962, SECRET, 7)   -- the plate names 962: only Ret2's list holds it
EndPull()

-- Interrupts that are not kicks, and the meter's own event order. A grip of
-- a whole pack stops several casts at once (several entries, several plates
-- in one update): nothing is placed and no cooldown starts. A single grip
-- while the member's kick is known to be on cooldown is not their kick
-- either, but its entry is still learned. The current-session event arriving
-- before a kick's Interrupts update in the same frame leaves the baseline
-- alone, so the kick still reads as new. A row no member can own (an enemy
-- that interrupted a player) is no evidence. A member whose talents were
-- never read is held to the shortest cooldown they could have.
Pull()
Advance(2)
Fire("DAMAGE_METER_CURRENT_SESSION_UPDATED")                 -- continuous in combat: nothing moved
Landed("party2", 970)
Fire("UNIT_SPELLCAST_INTERRUPTED", "nameplate33", "c", 970, SECRET, 7)
Fire("DAMAGE_METER_CURRENT_SESSION_UPDATED")                 -- the kick's count rose: the baseline is kept
Fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 5, 2)            -- new row + breakdown -> the DK (list: 970)
Advance(5)
Landed("party2", 971, true); Landed("party2", 972, true)     -- a grip of two casters, 5 s into the DK's cooldown
Fire("UNIT_SPELLCAST_INTERRUPTED", "nameplate34", "c", 971, SECRET, 7)
Fire("UNIT_SPELLCAST_INTERRUPTED", "nameplate35", "c", 972, SECRET, 7)
Fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 5, 2)            -- mass: nothing placed, no cooldown
Advance(3); Kick("party2", 973, true, "nameplate36", nil, true) -- a single grip 8 s in: the DK's kick cannot be ready -> grip, its entry learned
Advance(20); Kick("party2", 973, true, "nameplate36")        -- the DK repeats 973, known from the grip -> the DK
Advance(2)
enemyRows = 2
Fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 5, 2)            -- an enemy's row appears: no evidence, nothing recorded
Advance(2)
Join("party3", "Player-1-ABCD0010", 251, "Knight2", "DAMAGER", {})   -- a DK joins inside the pull: no inspect, talents unknown
Advance(1)
assert(KE.Member("party3").kick == 47528 and KE.Member("party3").landedCd == 15 and KE.Member("party3").minCd == 12, "uninspected DK: 15 modeled, 12 at the shortest")
Advance(1); Kick("party3", 975, true, "nameplate37")         -- new row + breakdown -> Knight2 (list: 975)
Advance(7); Kick("party2", 975, true, "nameplate38")         -- breakdown -> the DK (list: 970, 973, 975)
Advance(4); Kick("party3", 975, true, "nameplate37")         -- both lists hold 975; the DK kicked 4 s ago; Knight2 11 s ago, held to 12 -> Knight2 by cooldown
EndPull()

-- Hidden spells (a key): the meter's rows and counts alone. A kick that
-- changed nothing cannot be a member's first, so members without entries
-- are out; the rows sit in count order, so a member tied with the member
-- above them cannot have kicked unseen (their row would have moved); the
-- count bounds that carry that loosen on an unsure answer.
hiddenSpells = true
Pull()
Advance(2); Kick("party1", 980, true, "nameplate24")       -- new row + breakdown -> the Ret (count 1)
Advance(3); Kick("party2", 981, true, "nameplate25")       -- new row + breakdown -> the DK (count 1)
Advance(3); Kick("party4", 982, true, "nameplate26")       -- new row + breakdown -> the shaman (count 1); rows: shaman, DK, Ret
Advance(32); Kick("party4", 982, true, "nameplate26")      -- the top row repeats, nothing moves: the DK and the Ret each tie the row above -> the shaman
Advance(4); Kick("party2", 981, true, "nameplate25")       -- the DK's row moves up: two DKs own the key, one has no entries -> the DK
Advance(4); Kick("party1", 980, true, "nameplate24")       -- the Ret's row moves up -> the Ret
Advance(16); Kick("party1", 980, true, "nameplate24")      -- the top row repeats: all tied below -> the Ret
Advance(6); Kick("party2", 983, true, nil)                 -- the DK kicks a new spell on a mob with no plate: counted, nothing placed
Advance(8); Kick("party4", 982, true, "nameplate26")       -- the shaman's row moves up -> the shaman
Advance(6); Kick("party2", 981, true, "nameplate25")       -- the DK's row moves up -> the DK
Advance(14); Kick("party2", 981, true, "nameplate25")      -- the top row repeats: the shaman below is not tied, the Ret below her is; the shaman kicked 20 s ago -> the DK by cooldown
Advance(14); Kick("party2", 981, true, "nameplate25")      -- again: that unsure answer loosened the bounds -> ambiguous
-- The same frame order with nothing readable (a key): the DK's repeat on a
-- mob with no plate is his packet alone (no plate in it); the Ret's repeat
-- on plate 27, her stop first and her update in the same frame, is answered
-- by her own update (her row moves up: sure). Before the stop waited a
-- frame, it joined the DK's packet, which then showed him on her mob.
Advance(14)
Landed("party2", 981)
Fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 5, 2)
local dkPacket = gatelog[#gatelog]
assert(dkPacket and #dkPacket.rose == 1 and dkPacket.rose[1] == "party2" and #dkPacket.plates == 0, "the DK's packet, no plate")
Advance(0.1)
Landed("party1", 980)
Fire("UNIT_SPELLCAST_INTERRUPTED", "nameplate27", "c", SECRET, SECRET, 7)
Fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 5, 2)
assert(log[#log] == "nameplate27: party1 by reorder -", "her own update answered her plate: " .. tostring(log[#log]))
for _, g in ipairs(gatelog) do
    assert(not Has(g.plates, "nameplate27"), "her plate never joined a packet (the DK's least of all)")
end
Advance(0.5)
EndPull()
hiddenSpells = false

-- A delve companion in a party slot is not a player: the slot reads empty,
-- so it gets no record, no row and no inspect.
local before = inspects
G.party3 = { guid = "Creature-0-1-2-3-4-5", name = "Velera", role = "NONE", talents = {}, npc = true }
Fire("GROUP_ROSTER_UPDATE")
Advance(2)
assert(KE.Member("party3").guid == nil and KE.Member("party3").class == nil, "an NPC party member must leave its slot empty")
assert(inspects == before, "an NPC party member must never be inspected")

for i, l in ipairs(log) do print(i, l) end
print("--")
for i, l in ipairs(cdlog) do print(i, l) end

local expect = {
    "nameplate3: party1 by breakdown %-",
    "nameplate3: player by breakdown %-",
    "nameplate4: party1 by reorder %-",
    "nameplate4: party1 by repeat %-",
    "nameplate5: nil by unknown %-",
    "nameplate3: party1 by breakdown %-",
    "nameplate4: party2 by breakdown %-",
    "nameplate3: party1 by reorder %-",
    "nameplate5: party1 by breakdown %-",
    "nameplate4: party2 by repeat %-",
    "nameplate3: party1 by repeat %-",
    "nameplate6: party2 by breakdown %-",
    "nameplate7: party2 by breakdown %-",
    "nameplate8: party1 by breakdown %-",
    "nameplate9: nil by unknown %-",
    "nameplate19: party1 by breakdown %-",
    "nameplate10: party1 by breakdown %-",
    "nameplate11: party2 by breakdown %-",
    "nameplate12: party1 by reorder %-",
    "nameplate13: party1 by repeat %-",
    "nameplate20: party1 by breakdown %-",
    "nameplate21: party2 by breakdown %-",
    "nameplate22: party2 by breakdown %-",
    "nameplate23: party2 by breakdown %-",
    "nameplate20: nil by cooldown %-",
    "nameplate22: party2 by repeat %-",
    "nameplate20: nil by ambiguous %[party1,party2%]",
    "nameplate23: nil by cooldown %-",
    "nameplate30: party2 by breakdown %-",
    "nameplate31: party1 by breakdown %-",
    "nameplate32: party3 by breakdown %-",
    "nameplate30: party2 by reorder %-",
    "nameplate32: party3 by repeat %-",
    "nameplate33: party2 by breakdown %-",
    "nameplate34: nil by mass %-",
    "nameplate35: nil by mass %-",
    "nameplate36: nil by grip %-",
    "nameplate36: party2 by repeat %-",
    "nameplate37: party3 by breakdown %-",
    "nameplate38: party2 by breakdown %-",
    "nameplate37: nil by cooldown %-",
    "nameplate24: party1 by breakdown %-",
    "nameplate25: party2 by breakdown %-",
    "nameplate26: party4 by breakdown %-",
    "nameplate26: party4 by order %-",
    "nameplate25: party2 by order %-",
    "nameplate24: party1 by reorder %-",
    "nameplate24: party1 by order %-",
    "nameplate26: party4 by reorder %-",
    "nameplate25: party2 by order %-",
    "nameplate25: nil by cooldown %-",
    "nameplate25: nil by ambiguous %[party1,party2,party4%]",
    "nameplate27: party1 by reorder %-",
}
for i, pat in ipairs(expect) do
    assert(log[i] and log[i]:find("^" .. pat .. "$"), "line " .. i .. " expected " .. pat .. ", got " .. tostring(log[i]))
end
assert(#log == #expect, "extra kick lines: " .. #log)

-- Only kicks named for sure start a cooldown: the four the engine used to
-- name by cooldown alone show through their gate packets instead.
local expectCd = {
    "party1 cd 15", "player cd 15", "party1 cd 15", "party1 cd 15", "player cd 15",
    "party1 cd 15", "party2 cd 13.5", "party1 cd 15", "party1 cd 15", "party2 cd 13.5", "party1 cd 15",
    "party2 cd 12",
    "party2 cd 12", "party1 cd 15", "party2 cd 12", "party1 cd 15",
    "party1 cd 15", "party2 cd 12", "party1 cd 15", "party1 cd 15",
    "party1 cd 15", "party2 cd 12", "party2 cd 12", "party2 cd 12", "party2 cd 12", "party4 cd 30",
    "party2 cd 12", "party1 cd 15", "party3 cd 15", "party2 cd 12", "party3 cd 15",
    "party2 cd 12", "party2 cd 12", "party3 cd 15", "party2 cd 12",
    "party1 cd 15", "party2 cd 12", "party4 cd 30", "party4 cd 30", "party2 cd 12", "party1 cd 15", "party1 cd 15",
    "party2 cd 12", "party4 cd 30", "party2 cd 12", "party1 cd 15",
}
for i, l in ipairs(expectCd) do
    assert(cdlog[i] == l, "cooldown line " .. i .. " expected " .. l .. ", got " .. tostring(cdlog[i]))
end
assert(#cdlog == #expectCd, "extra cooldown lines: " .. #cdlog)

-- Every kick so far shown exactly, the guessed ones through their packets.
CheckTruth()
print("truth check: " .. #truth .. " interrupts, " .. #gatelog .. " gate packets")

-- The owner's key (2026-10-21): the death knight's third kick of the same
-- mob's spell showed nowhere while their count rose on the meter. In a key
-- the spell is hidden and a repeat changes nothing the engine can read; with
-- others who have entries and are ready, nobody can be named. The gate packet
-- shows the knight alone, on the bars and on that plate.
local mark = #truth
local gmark = #gatelog
hiddenSpells = true
Pull()
Advance(20); Kick("party1", 1101, true, "nameplate14")      -- the Ret: new row + breakdown
Advance(1);  Kick("party4", 1102, true, "nameplate15")      -- the shaman: new row + breakdown
Advance(1);  Kick("party2", 1103, true, "nameplate16")      -- the knight's first kick of the mob's spell: breakdown
Advance(16); Kick("party2", 1103, true, "nameplate16")      -- the second: their row was on top already
Advance(16); Kick("party2", 1103, true, "nameplate16")      -- the third: the owner's miss
EndPull()
hiddenSpells = false
CheckTruth(mark + 1)
local third = gatelog[#gatelog]
assert(third and #third.rose == 1 and third.rose[1] == "party2" and Has(third.plates, "nameplate16"),
    "the knight's third kick: shown by their own packet on its plate")
print("owner's case: the third kick shown on party2 at nameplate16, " .. (#gatelog - gmark) .. " packets")

-- A member's kicks come through the meter alone: another player's casts,
-- their demon's included, never reach this client on a dungeon map (field
-- 2026-10-21: an unfiltered listener heard none), so only your own casts are
-- listened to (your demon's too when you are a warlock). The meter may file
-- a member's row with NO spec icon (the paladin's meter filed the warlock's
-- first kick as "WARLOCK:-" while the paladin's own inspect had given the
-- warlock a spec icon): such a row names its member by class alone, so the
-- lone warlock takes it, and a demon's kick, which never grows the owner's
-- breakdown, is credited through the row's arrival and its moves.
wipe(log); wipe(cdlog)
assert(CastUnits() == "player", "a paladin: only your own casts are heard, got " .. CastUnits())
Join("party4", "Player-1-AAAA0011", 265, "Lock", "DAMAGER", {}, "Felhunter")
noSpecIcon.party4, petKicks.party4 = true, true
Advance(2)
assert(KE.Member("party4").kick == 19647 and KE.Member("party4").specIcon == 100265, "the warlock: Spell Lock, the spec from the inspect")
Pull()
Advance(2);  Kick("player", 990, true, "nameplate38")           -- your kicks first: your row leads
Advance(16); Kick("player", 993, true, "nameplate37")
Advance(2);  Kick("party4", 991, true, "nameplate40")           -- the felhunter's Spell Lock: a new row, no spec icon, no breakdown entry
Advance(26); Kick("party4", 992, true, "nameplate39")           -- the second: their row passes yours
Advance(1)
EndPull()
assert(log[3] == "nameplate40: party4 by new row -", "a row with no spec icon names the lone warlock: " .. tostring(log[3]))
assert(log[4] == "nameplate39: party4 by reorder -", "their row moving names them again: " .. tostring(log[4]))
assert(#log == 4, "extra kick lines: " .. #log)
assert(cdlog[#cdlog - 1] == "party4 cd 24" and cdlog[#cdlog] == "party4 cd 24", "their cooldown at each kick: " .. table.concat(cdlog, ", "))
assert(KE.Member("party4").specIcon == 100265, "the inspect's spec icon stays")
assert(KE.Listening():find("^casts heard: player | roster: ") ~= nil, "the dump line: " .. KE.Listening())

-- A class read that comes back hidden later (UnitClass is secret while a
-- unit's identity is restricted) leaves the known class alone, so the
-- warlock keeps their kick.
G.party4.hideClass = true
Fire("GROUP_ROSTER_UPDATE"); Advance(1)
assert(KE.Member("party4").class == "WARLOCK" and KE.Member("party4").kick == 19647, "a hidden read keeps the last plain class")
G.party4.hideClass = nil

-- The felhunter's repeats in a key: its kicks count under the demon, a source
-- of its own the warlock's breakdown never shows, so the warlock's gate reads
-- the demon's count (by its GUID), and with that GUID unreadable, the one row
-- the meter keeps for a warlock with no spec icon.
mark, gmark = #truth, #gatelog
hiddenSpells = true
Pull()
Advance(30); Kick("party4", 1201, true, "nameplate17")     -- the demon's first: its row arrives
Advance(25); Kick("party4", 1201, true, "nameplate17")     -- a repeat: the demon's count rose, nothing else moved
local lockGate = gatelog[#gatelog]
assert(#gatelog > gmark and #lockGate.rose == 1 and lockGate.rose[1] == "party4", "the demon's repeat shows the warlock")
local petGUID = UnitGUID
UnitGUID = function(u) if u == "partypet4" then return nil end return petGUID(u) end
gmark = #gatelog
Advance(25); Kick("party4", 1201, true, "nameplate17")     -- the demon's GUID unreadable: its row stands in
lockGate = gatelog[#gatelog]
assert(#gatelog > gmark and #lockGate.rose == 1 and lockGate.rose[1] == "party4", "the demon's row stands in for its source")
UnitGUID = petGUID
EndPull()
hiddenSpells = false
CheckTruth(mark + 1)
print("PASS")
