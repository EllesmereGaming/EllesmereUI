if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  EllesmereUI_KickData.lua
--  The interrupts of patch 12.1.5 and what each one's cooldown is for a given
--  player, from the game's own spell data (build 70448): cooldowns from the
--  spell cooldown table; who learns each interrupt from the class skill lines,
--  the specialization spells and the talent trees; and every talent or
--  specialization passive whose effects change those cooldowns, searched by
--  class mask, spell category and spell label. One source for the suite: the
--  player's own kick lookup (EllesmereUI_Kick.lua) and the Mythic+ Tools Kick
--  Tracker both read it.
--
--  SEASON UPDATE: check it against each new season's patch (interrupts, their
--  cooldowns, and the talents that change them).
--
--  Healers keep no interrupt in 12.1 except Restoration Shaman, whose Wind
--  Shear is 30 seconds. Talents found: Quick Witted (Counterspell 20 s), Honed
--  Reflexes (Pummel 13.5 s), Coldthirst (Mind Freeze 3 s shorter after a
--  successful interrupt), Light of the Sun (Solar Beam 15 s shorter after a
--  successful interrupt). A Protection Warrior's Disrupting Shout also
--  interrupts and is tracked. A Protection Paladin's Avenger's Shield also
--  interrupts and stays in the player's own kick lookup (the cast bar color
--  follows it when Rebuke is not known), but the Kick Tracker never models
--  it (`tracked = false`): Rebuke is the paladin interrupt it tracks, and a
--  kick the meter credits to the shield counts as Rebuke, which it cannot
--  tell apart.
--
--  Pure data and lookups, nothing registered: EllesmereUI.KickData.
--------------------------------------------------------------------------------
local KD = {}
EllesmereUI.KickData = KD

local floor = math.floor

-- Interrupts by spell ID: the class, the base cooldown in seconds, the specs
-- that have it (nil = every spec of the class), whether it is a talent node (a
-- read talent tree without it means no interrupt), and for warlocks the demon
-- that casts it. `main` marks the class's interrupt when nothing more is known.
-- `tracked = false` keeps a spell in the player's own kick lookup (ClassLists)
-- and out of everything the Kick Tracker resolves: KickSpell, the watched
-- talents and the player's own casts.
local INTERRUPTS = {
    [1766]   = { class = "ROGUE",       cd = 15, main = true },                              -- Kick
    [2139]   = { class = "MAGE",        cd = 25, main = true },                              -- Counterspell
    [6552]   = { class = "WARRIOR",     cd = 15, main = true },                              -- Pummel
    [386071] = { class = "WARRIOR",     cd = 90, specs = { [73] = true }, talent = true },   -- Disrupting Shout (Protection)
    [15487]  = { class = "PRIEST",      cd = 30, specs = { [258] = true }, main = true },    -- Silence (Shadow)
    [19647]  = { class = "WARLOCK",     cd = 24, pet = "Felhunter", main = true },           -- Spell Lock (Felhunter)
    [89766]  = { class = "WARLOCK",     cd = 30, pet = "Felguard" },                         -- Axe Toss (Felguard)
    [132409] = { class = "WARLOCK",     cd = 24, sacrifice = true },                         -- Spell Lock (Grimoire of Sacrifice)
    [47528]  = { class = "DEATHKNIGHT", cd = 15, talent = true, main = true },               -- Mind Freeze
    [57994]  = { class = "SHAMAN",      cd = 12, talent = true, main = true },               -- Wind Shear
    [78675]  = { class = "DRUID",       cd = 60, specs = { [102] = true }, talent = true },  -- Solar Beam (Balance)
    [106839] = { class = "DRUID",       cd = 15, specs = { [103] = true, [104] = true }, talent = true, main = true }, -- Skull Bash
    [96231]  = { class = "PALADIN",     cd = 15, specs = { [66] = true, [70] = true }, talent = true, main = true },   -- Rebuke
    [31935]  = { class = "PALADIN",     cd = 15, specs = { [66] = true }, talent = true, tracked = false }, -- Avenger's Shield (Protection): the player's own lookup only
    [116705] = { class = "MONK",        cd = 15, specs = { [268] = true, [269] = true }, talent = true, main = true }, -- Spear Hand Strike
    [147362] = { class = "HUNTER",      cd = 24, specs = { [253] = true, [254] = true }, talent = true, main = true }, -- Counter Shot
    [187707] = { class = "HUNTER",      cd = 15, specs = { [255] = true }, talent = true },  -- Muzzle (Survival)
    [183752] = { class = "DEMONHUNTER", cd = 15, main = true },                              -- Disrupt
    [351338] = { class = "EVOKER",      cd = 20, specs = { [1467] = true, [1473] = true }, talent = true, main = true }, -- Quell
}
KD.INTERRUPTS = INTERRUPTS

-- Spells the player or their pet casts that are a kick (the cooldown model
-- starts on them): the interrupts above and the demon command versions, which
-- the player's own spellbook holds while that demon is out.
local COMMAND_CASTS = { [119910] = 19647, [119914] = 89766 }
local CAST_IDS = {}
for id, kick in pairs(COMMAND_CASTS) do CAST_IDS[id] = kick end
for id, k in pairs(INTERRUPTS) do
    if k.tracked ~= false then CAST_IDS[id] = id end
end

-- What changes a cooldown. pct and flat apply to every use (the game applies
-- the percent to the base, then the flat amount); `landed` applies only after
-- a successful interrupt, which is every kick the tracker sees from others.
-- `talent` = the talent's spell ID (read from the talent tree, or
-- IsPlayerSpell for the player); `spec` = a specialization passive.
local MODS = {
    [2139]  = { { talent = 382297, flat = -5 } },    -- Quick Witted
    [6552]  = { { talent = 391271, pct = -10 } },    -- Honed Reflexes
    [47528] = { { talent = 378848, landed = -3 } },  -- Coldthirst
    [78675] = { { talent = 202918, landed = -15 } }, -- Light of the Sun
    [57994] = { { spec = 264, flat = 18 } },         -- Restoration Shaman
}

-- Every talent spell the engine looks for when it reads a talent tree: the
-- interrupts that are nodes, the cooldown talents, and Grimoire of Sacrifice
-- (a warlock without a demon out interrupts through it).
local WATCHED = { [108503] = true }
for id, k in pairs(INTERRUPTS) do
    if k.talent and k.tracked ~= false then WATCHED[id] = true end
end
for _, list in pairs(MODS) do
    for i = 1, #list do
        if list[i].talent then WATCHED[list[i].talent] = true end
    end
end
KD.WATCHED_TALENTS = WATCHED

-- A member whose spec is not known yet but who fills the healer role is read
-- as their class's healing spec (the interrupt table then answers: none,
-- except Restoration Shaman's Wind Shear).
local HEALING_SPEC_OF = { DRUID = 105, EVOKER = 1468, MONK = 270, PALADIN = 65, PRIEST = 257, SHAMAN = 264 }

-- The demon a warlock has out, by creature family: the interrupt it casts.
-- A demon not listed has none.
local DEMON_INTERRUPT = { Felhunter = 19647, Felguard = 89766, Wrathguard = 89766 }

-- A kick spell is one of ours (or a demon command version): the spell ID it
-- counts as, or nil.
function KD.OwnCastKick(spellID)
    return CAST_IDS[spellID]
end

-- Picks a class member's interrupt. class: token; specID: number or nil
-- (unknown); role: "HEALER" or anything else, read only while the spec is
-- unknown; talents: set of known talent spell IDs or nil (tree not read);
-- petFamily: a warlock's demon family or nil. Returns the spell ID (nil for
-- none) and the spec the answer was read for (the class's healing spec when
-- a healer's spec was not known), which the cooldown is read for too.
function KD.KickSpell(class, specID, role, talents, petFamily)
    if not specID and role == "HEALER" then specID = HEALING_SPEC_OF[class] end
    if class == "WARLOCK" then
        if petFamily then
            local id = DEMON_INTERRUPT[petFamily]
            if id then return id, specID end
        end
        if talents and talents[108503] and not petFamily then return 132409, specID end -- Grimoire of Sacrifice, no demon out
        if specID == 266 then return 89766, specID end -- Demonology: the Felguard
        return 19647, specID
    end
    -- An unknown spec assumes the class's main interrupt; a known one takes
    -- the main interrupt when that spec has it, else the spec's own.
    local main, own
    for id, k in pairs(INTERRUPTS) do
        if k.class == class and k.tracked ~= false then
            local specOk = (not k.specs) or (not specID) or k.specs[specID]
            -- A read tree without the node: this member has no such kick.
            local hasNode = not (k.talent and talents and not talents[id])
            if specOk and hasNode then
                if k.main then
                    main = id
                elseif specID and k.specs and k.specs[specID] then
                    own = id
                end
            end
        end
    end
    return main or own, specID
end

-- The cooldown of a kick for its owner: the plain cooldown and the one after a
-- successful interrupt (the same unless a talent shortens it then). specID,
-- talents as above (nil = unknown: base values).
function KD.Cooldown(spellID, specID, talents)
    local k = INTERRUPTS[spellID]
    if not k then return nil end
    local cd, landed = k.cd, 0
    local list = MODS[spellID]
    if list then
        local pct, flat = 0, 0
        for i = 1, #list do
            local m = list[i]
            local on = (m.talent and talents and talents[m.talent]) or (m.spec and specID == m.spec)
            if on then
                if m.pct then pct = pct + m.pct end
                if m.flat then flat = flat + m.flat end
                if m.landed then landed = landed + m.landed end
            end
        end
        cd = floor((k.cd * (1 + pct / 100) + flat) * 100 + 0.5) / 100
    end
    if cd < 0.5 then cd = 0.5 end
    local lcd = cd + landed
    if lcd < 0.5 then lcd = 0.5 end
    return cd, lcd
end

-- The spell whose icon stands for a class's interrupt when the member's own is
-- not known (the bars' default icon).
function KD.ClassMainKick(class)
    for id, k in pairs(INTERRUPTS) do
        if k.class == class and k.main then return id end
    end
    return nil
end

-- The spells the player's own kick lookup checks, by class token: every
-- interrupt of the class and, for warlocks, the demon command versions. The
-- lookup keeps the last spell its bank knows, so each list ends with the
-- class's main interrupt, and a warlock's with the Grimoire of Sacrifice
-- Spell Lock (known only while the sacrifice is up). Built once.
local classLists
function KD.ClassLists()
    if classLists then return classLists end
    classLists = {}
    local ids = {}
    for id in pairs(INTERRUPTS) do ids[#ids + 1] = id end
    table.sort(ids)
    local function add(class, id)
        local list = classLists[class]
        if not list then list = {}; classLists[class] = list end
        list[#list + 1] = id
    end
    for _, id in ipairs(ids) do
        local k = INTERRUPTS[id]
        if not k.main and not k.sacrifice then add(k.class, id) end
    end
    for _, id in ipairs(ids) do
        if INTERRUPTS[id].main then add(INTERRUPTS[id].class, id) end
    end
    for id, kick in pairs(COMMAND_CASTS) do add(INTERRUPTS[kick].class, id) end
    for _, id in ipairs(ids) do
        if INTERRUPTS[id].sacrifice then add(INTERRUPTS[id].class, id) end
    end
    return classLists
end
