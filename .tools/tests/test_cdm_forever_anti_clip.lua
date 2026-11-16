-- Stub harness: Cooldown Manager, the WoW Forever Anti-Clip Glow (EUI_CDM_ForeverAntiClip.lua),
-- and the pandemic glow WoW Forever does not have on nameplates.
-- The glow lights an aura while casting its spell as your next action, after your current cast
-- or global cooldown, would land at or after the aura's expiry. For an instant spell that is
-- only true as the aura runs out, so an instant (Rend, Sunder Armor, any buff) never lit while
-- you were idle, and a cast shorter than a global cooldown lit for a fraction of a second. A
-- spell's cast now counts as one base global cooldown at least (1.5 s), so every aura lights
-- for at least its last 1.5 seconds; casts of 1.5 s or longer keep their rule.
-- Driven here: the real trigger file, loaded whole, with the real expiry reader cut from
-- EllesmereUICdmHooks.lua, over a stubbed client (clock, casts, the global cooldown, timers);
-- the real pandemic sync cut from EUI_CDM_Glows.lua (on WoW Forever the nameplate glow is no
-- surface); and the options files' text for the rows this client does not build.
--   lua .tools/tests/test_cdm_forever_anti_clip.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return (src:gsub("\r\n", "\n"))
end
local function Cut(src, first, last, what)
    local a = assert(src:find(first, 1, true), what .. ": first line not found")
    local b = assert(src:find(last, a + #first, true), what .. ": last line not found")
    return src:sub(a, b - 1)
end

local fails, count = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        if fails <= 14 then print("  FAIL: " .. msg) end
    end
end

-- A secret value: indexing, joining, ordering, measuring or calling it raises.
local SECRET = newproxy(true)
do
    local mt = getmetatable(SECRET)
    local function boom(what) return function() error("a secret value was " .. what, 2) end end
    mt.__index, mt.__newindex, mt.__concat = boom("indexed"), boom("written into"), boom("joined")
    mt.__lt, mt.__le, mt.__len, mt.__call = boom("compared"), boom("compared"), boom("measured"), boom("called")
    mt.__add, mt.__sub, mt.__mul, mt.__div = boom("added"), boom("subtracted"), boom("multiplied"), boom("divided")
end
local function issecretvalue(v) return rawequal(v, SECRET) end

-------------------------------------------------------------------------------
-- The client
-------------------------------------------------------------------------------
local clock = 1000
local cast            -- { endMs, sid } while a cast runs
local gcd = { startTime = 0, duration = 0 }
local timers = {}
local hooks = 0
local SPELLS = {
    [348] = { name = "Immolate", castTime = 2000 },     [9348] = { name = "Immolate", castTime = 2000 },   -- another rank
    [172] = { name = "Rend", castTime = 0 },            [686] = { name = "Shadow Bolt", castTime = 3000 },
    [9001] = { name = "Quick Corruption", castTime = 400 },
    [9002] = { name = "Bane Immolate", castTime = 1500 },
    [9003] = { name = "Hidden Cast", castTime = SECRET },
}
local ENV = setmetatable({
    GetTime = function() return clock end,
    issecretvalue = issecretvalue,
    wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
    hooksecurefunc = function() hooks = hooks + 1 end,
    C_Timer = { After = function(d, fn) timers[#timers + 1] = { at = clock + d, fn = fn } end },
    UnitCastingInfo = function()
        if cast then return "n", "t", "tex", 0, cast.endMs, false, "id", false, cast.sid end
    end,
    UnitChannelInfo = function() return nil end,
    C_Spell = {
        GetSpellName = function(id) return SPELLS[id] and SPELLS[id].name end,
        GetSpellInfo = function(id) return SPELLS[id] and { castTime = SPELLS[id].castTime } end,
        GetSpellCooldown = function() return { startTime = gcd.startTime, duration = gcd.duration } end,
    },
    EllesmereUI = { PlainString = function(v) if type(v) == "string" then return v end end },
}, { __index = _G })

-- The real expiry reader (Also Show Below N Seconds reads an item the same way).
local ReadExpiration = assert(loadstring("local issecretvalue = ...\n" ..
    Cut(ReadSource("EllesmereUICooldownManager/EllesmereUICdmHooks.lua"), "    local function ReadExpiration(frame)",
        "    -- The WoW Forever anti-clip glow reads it too", "the expiry reader") .. "\nreturn ReadExpiration", "=EllesmereUICdmHooks.lua"))(issecretvalue)

local TRIGGER = ReadSource("EllesmereUICooldownManager/EUI_CDM_ForeverAntiClip.lua")
-- A fresh load of the trigger. bars: the profile's CDM bars.
local function Load(bars, antiClip)
    clock, cast, timers, hooks = 1000, nil, {}, 0
    gcd.startTime, gcd.duration = 0, 0
    local events, woke = {}, { n = 0 }
    local shell = {}
    function shell:SetScript(_, fn) self.fn = fn end
    function shell:RegisterUnitEvent(e) events[e] = true end
    function shell:RegisterEvent(e) events[e] = true end
    function shell:UnregisterAllEvents() for k in pairs(events) do events[k] = nil end end
    local ns = {
        CDM_ANTI_CLIP = antiClip ~= false,
        ReadAuraExpiration = ReadExpiration,
        TakeShell = function() return shell end,
        _ecmeFC = setmetatable({}, { __mode = "k" }),
        ArmBuffTicker = function() woke.n = woke.n + 1 end,
        ECME = { db = { profile = { cdmBars = { bars = bars or {
            { key = "buffs", enabled = true, pandemicGlow = true, pandemicGlowStyle = 5 },
        } } } } },
    }
    local chunk = assert(loadstring(TRIGGER, "=EUI_CDM_ForeverAntiClip.lua"))
    setfenv(chunk, ENV)
    chunk("EllesmereUICooldownManager", ns)
    return ns, shell, events, woke
end
-- An aura item with `left` seconds to run. opts: rate, unresolved (no resolved spell: the
-- aura's own id stands in), secretId, secretExp, secretAura.
local function Item(ns, sid, left, opts)
    opts = opts or {}
    local f = { IsShown = function() return true end, CheckSetPandemicAlertTriggerTime = function() end }
    if opts.secretAura then
        f.auraDataCached = SECRET
    else
        f.auraDataCached = { expirationTime = opts.secretExp and SECRET or (clock + left * (opts.rate or 1)),
                             timeMod = opts.rate or 1, spellId = opts.secretId and SECRET or sid }
    end
    if not opts.unresolved then ns._ecmeFC[f] = { resolvedSid = sid } end
    return f
end
local function Edge(shell, event) shell.fn(shell, event, "player") end
-- The verdict of a spell's aura with `left` seconds to run, on a fresh idle player.
local function Idle(ns, sid, left, opts)
    return ns.CDM_AntiClip(Item(ns, sid, left, opts), false)
end

-------------------------------------------------------------------------------
-- 1. off the client, and while no bar uses the glow
-------------------------------------------------------------------------------
do
    local ns, shell = Load(nil, false)
    check(ns.CDM_AntiClip == nil and ns.CDM_AntiClipSync == nil and shell.fn == nil, "the trigger was built on a client that has no anti-clip glow")

    local events
    ns, shell, events = Load()
    check(ns.CDM_AntiClip(Item(ns, 172, 1), true) == false and next(events) == nil and hooks == 0, "the trigger answered or listened before any bar used the glow")
    ns.CDM_AntiClipSync()
    check(events.UNIT_SPELLCAST_START and events.UNIT_SPELL_HASTE and events.SPELLS_CHANGED, "a bar with an Anti-Clip style does not arm the trigger")
    ns, shell, events = Load({ { key = "buffs", enabled = true, pandemicGlow = true, pandemicGlowStyle = -1 } })
    ns.CDM_AntiClipSync()
    check(next(events) == nil, "a bar on Blizzard Default (which has no anti-clip look) arms the trigger")
    ns, shell, events = Load({ { key = "buffs", enabled = false, pandemicGlow = true, pandemicGlowStyle = 5 } })
    ns.CDM_AntiClipSync()
    check(next(events) == nil, "a disabled bar arms the trigger")
    ns, shell, events = Load({ { key = "buffs", enabled = true, pandemicGlow = false } })
    ns.CDM_AntiClipSync()
    check(next(events) == nil, "a bar with the glow off arms the trigger")
    ns.CDM_AntiClipBars(true)
    check(events.UNIT_SPELLCAST_START == true, "a Tracking Bar with the glow does not arm the trigger")
    ns.CDM_AntiClipBars(false)
    check(next(events) == nil, "the trigger keeps listening after the last bar let go")
end

-------------------------------------------------------------------------------
-- 2. a cast of 1.5 seconds or longer: lit once the cast would land as the aura runs out
-------------------------------------------------------------------------------
do
    local ns, shell = Load()
    ns.CDM_AntiClipSync()
    check(Idle(ns, 348, 10) == false, "a 2 s cast lights with 10 s left")
    check(Idle(ns, 348, 2.01) == false, "a 2 s cast lights with 2.01 s left")
    check(Idle(ns, 348, 2) == true, "a 2 s cast is dark with 2 s left")
    check(Idle(ns, 348, 0.3) == true, "a 2 s cast is dark with 0.3 s left")
    check(Idle(ns, 686, 3.01) == false and Idle(ns, 686, 3) == true, "a 3 s cast does not light at 3 s left exactly")
    check(Idle(ns, 9002, 1.51) == false and Idle(ns, 9002, 1.5) == true, "a 1.5 s cast does not light at 1.5 s left exactly")
    -- casting the spell itself refreshes the aura: nothing to queue (another rank is the same spell)
    local f = Item(ns, 348, 1)
    check(ns.CDM_AntiClip(f, true) == true, "a 2 s cast is dark with 1 s left")
    cast = { endMs = (clock + 2) * 1000, sid = 9348 }
    Edge(shell, "UNIT_SPELLCAST_START")
    check(ns.CDM_AntiClip(f, true) == false, "the glow stays lit while you cast that spell")
    -- another cast in the way: 3 s of Shadow Bolt, then the 2 s cast
    cast = { endMs = (clock + 3) * 1000, sid = 686 }
    Edge(shell, "UNIT_SPELLCAST_START")
    check(ns.CDM_AntiClip(Item(ns, 348, 5), false) == true and ns.CDM_AntiClip(Item(ns, 348, 5.1), false) == false,
        "a running cast is not added to the time until you are free")
end

-------------------------------------------------------------------------------
-- 3. an instant: lit for its last 1.5 seconds, and it stays lit once you are free
-------------------------------------------------------------------------------
do
    local ns, shell = Load()
    ns.CDM_AntiClipSync()
    check(Idle(ns, 172, 10) == false, "an instant lights with 10 s left")
    check(Idle(ns, 172, 1.51) == false, "an instant lights with 1.51 s left")
    check(Idle(ns, 172, 1.5) == true, "an instant is dark with 1.5 s left while you are idle")
    check(Idle(ns, 172, 0.5) == true, "an instant is dark with 0.5 s left while you are idle")
    check(Idle(ns, 172, 0.05) == true, "an instant is dark with 0.05 s left while you are idle")
    -- a global cooldown in the way: your next action is 1 s off, the one after it 2.5 s
    gcd.startTime, gcd.duration = clock - 0.5, 1.5
    Edge(shell, "UNIT_SPELLCAST_SUCCEEDED")
    check(ns.CDM_AntiClip(Item(ns, 172, 2.5), false) == true, "an instant is dark with 2.5 s left and 1 s of global cooldown to run")
    check(ns.CDM_AntiClip(Item(ns, 172, 2.6), false) == false, "an instant lights with 2.6 s left and 1 s of global cooldown to run")
    -- the same aura as the global cooldown ends: still lit (it went dark here before)
    local f = Item(ns, 172, 2.5)
    check(ns.CDM_AntiClip(f, true) == true, "an instant with 2.5 s left is dark during the global cooldown")
    clock = clock + 1
    gcd.startTime, gcd.duration = 0, 0
    Edge(shell, "UNIT_SPELLCAST_STOP")
    check(ns.CDM_AntiClip(f, true) == true, "an instant goes dark the moment you are free, with 1.5 s left")
    clock = clock + 1.2
    check(ns.CDM_AntiClip(f, true) == true, "an instant goes dark in its last 0.3 s")
    -- a hard cast in the way
    cast = { endMs = (clock + 3) * 1000, sid = 686 }
    Edge(shell, "UNIT_SPELLCAST_START")
    check(ns.CDM_AntiClip(Item(ns, 172, 4.5), false) == true and ns.CDM_AntiClip(Item(ns, 172, 4.6), false) == false,
        "an instant behind a 3 s cast does not light from 4.5 s left")
end

-------------------------------------------------------------------------------
-- 4. a cast shorter than a global cooldown counts as one; what cannot be read counts as one too
-------------------------------------------------------------------------------
do
    local ns = Load()
    ns.CDM_AntiClipSync()
    check(Idle(ns, 9001, 1.51) == false and Idle(ns, 9001, 1.5) == true, "a 0.4 s cast does not light for its last 1.5 s")
    check(Idle(ns, 9001, 0.2) == true, "a 0.4 s cast is dark with 0.2 s left")
    -- a cast time the client keeps secret, a spell id it keeps secret, a spell it does not know
    check(Idle(ns, 9003, 1.51) == false and Idle(ns, 9003, 1.5) == true, "a secret cast time does not count as the shortest cast")
    check(Idle(ns, 172, 1.5, { unresolved = true, secretId = true }) == true and Idle(ns, 172, 1.51, { unresolved = true, secretId = true }) == false,
        "a secret spell id does not count as the shortest cast")
    check(Idle(ns, 424242, 1.5) == true and Idle(ns, 424242, 1.51) == false, "a spell the client does not know does not count as the shortest cast")
    -- the aura's own id stands in until the icon's spell is resolved
    check(Idle(ns, 348, 2, { unresolved = true }) == true and Idle(ns, 348, 2.01, { unresolved = true }) == false, "an unresolved icon does not read its aura's own spell")
    -- an expiry the client keeps secret, or a whole aura it keeps secret, lights nothing
    check(Idle(ns, 172, 1, { secretExp = true }) == false, "a secret expiry lights the glow")
    check(Idle(ns, 172, 1, { secretAura = true, unresolved = true }) == false, "a secret aura lights the glow")
    -- an aura running at another rate: its time left counts in real seconds
    check(Idle(ns, 172, 1.5, { rate = 2 }) == true and Idle(ns, 172, 1.51, { rate = 2 }) == false, "an aura at double rate does not light for its last 1.5 real seconds")
end

-------------------------------------------------------------------------------
-- 5. the idle wait: one timer at the moment the glow turns on, then the ticker is woken
-------------------------------------------------------------------------------
do
    local function WaitOf(sid, left, opts)
        local ns, shell, events, woke = Load()
        ns.CDM_AntiClipSync()
        local w0, t0 = woke.n, #timers
        local f = Item(ns, sid, left, opts)
        local on = ns.CDM_AntiClip(f, true)
        return ns, f, on, timers[t0 + 1], woke, w0
    end
    local ns, f, on, timer, woke, w0 = WaitOf(172, 10)
    check(on == false and timer ~= nil and math.abs(timer.at - (clock + 8.5 + 0.02)) < 1e-6, "an instant with 10 s left does not wait for its last 1.5 s")
    check(hooks == 1, "the icon's aura edges were not hooked once")
    if timer then
        clock = timer.at
        timer.fn()
        check(ns._btDirty == true and woke.n == w0 + 1, "the wait's end does not wake the buff ticker")
        check(ns.CDM_AntiClip(f, true) == true, "the glow is dark at the end of its wait")
    end
    ns, f, on, timer = WaitOf(348, 10)
    check(on == false and timer ~= nil and math.abs(timer.at - (clock + 8 + 0.02)) < 1e-6, "a 2 s cast with 10 s left does not wait for its last 2 s")
    ns, f, on, timer = WaitOf(9001, 10)
    check(on == false and timer ~= nil and math.abs(timer.at - (clock + 8.5 + 0.02)) < 1e-6, "a 0.4 s cast with 10 s left does not wait for its last 1.5 s")
    ns, f, on, timer = WaitOf(172, 10, { rate = 2 })
    check(on == false and timer ~= nil and math.abs(timer.at - (clock + 17 + 0.02)) < 1e-6, "an aura at double rate does not wait for its last 1.5 real seconds")
    -- the Tracking Bars tick asks for no hook and no wait
    local ns2 = Load()
    ns2.CDM_AntiClipSync()
    local t0 = #timers
    check(ns2.CDM_AntiClip(Item(ns2, 172, 10), false) == false and hooks == 0 and #timers == t0, "a Tracking Bar's read hooked an item or started a wait")
end

-------------------------------------------------------------------------------
-- 6. Apply to All: on WoW Forever the nameplates have no pandemic glow to write or to compare
-------------------------------------------------------------------------------
do
    local GLOWS = ReadSource("EllesmereUICooldownManager/EUI_CDM_Glows.lua")
    local STYLES = { { name = "Pixel Glow" }, { name = "Shape Glow" }, { name = "Action Button Glow" }, { name = "Auto-Cast Shine" } }
    local function Sync(antiClip)
        local E = { NameplatePandemicGlowStyles = STYLES, NameplatePandemicStyle = function(np) return np.pandemicGlowPick or 1 end }
        local np = { pandemicGlow = false }
        local db = { activeProfile = "Default", profiles = { Default = { addons = { EllesmereUINameplates = np } } } }
        local bars = { { key = "cooldowns", pandemicGlow = true, pandemicGlowStyle = 3, pandemicGlowMode = "custom" },
                       { key = "buffs", pandemicGlow = false } }
        local nsS = { CDM_ANTI_CLIP = antiClip, GetTrackedBuffBars = function() return { bars = {} } end,
                      BuildAllCDMBars = function() end, BuildTrackedBuffBars = function() end }
        assert(loadstring("local _G_Glows, GLOW_STYLES, EllesmereUI, ECME, ns, EllesmereUIDB, CopyTable, _G = ...\n" ..
            Cut(GLOWS, 'local PG_BLIZZ_NAME = "Blizzard Default"', "-- Show Glows Only in Combat (global).", "the pandemic sync"), "=EUI_CDM_Glows.lua"))(
            { PANDEMIC_BORDER = 101 }, STYLES, E, { db = { profile = { cdmBars = { bars = bars } } } }, nsS, db,
            function(t) local c = {}; for k, v in pairs(t) do c[k] = v end; return c end, {})
        return E, np, bars
    end
    -- WoW Forever: the nameplate profile is left alone, and it does not hold the link up
    local E, np, bars = Sync(true)
    local payload = E.PandemicPayloadFromCdmBar(bars[1])
    check(E.IsPandemicGlowSyncedToAll(payload, { skipCdmKey = "cooldowns" }) == false, "the other bar is not seen as out of step")
    E.ApplyPandemicGlowToAll(payload, { skipCdmKey = "cooldowns" })
    check(bars[2].pandemicGlow == true and bars[2].pandemicGlowStyle == 3, "Apply to All does not write the other bar")
    check(np.pandemicGlow == false and np.pandemicGlowPick == nil and np.pandemicGlowMode == nil, "Apply to All wrote the nameplate glow on WoW Forever")
    check(E.IsPandemicGlowSyncedToAll(payload, { skipCdmKey = "cooldowns" }) == true, "the nameplate glow holds the Apply to All link up on WoW Forever")
    -- retail: the nameplates are a surface
    E, np, bars = Sync(false)
    payload = E.PandemicPayloadFromCdmBar(bars[1])
    E.ApplyPandemicGlowToAll(payload, { skipCdmKey = "cooldowns" })
    check(np.pandemicGlow == true and np.pandemicGlowPick == 3 and np.pandemicGlowMode == "custom", "Apply to All does not write the nameplate glow on retail")
    np.pandemicGlow = false
    check(E.IsPandemicGlowSyncedToAll(payload, { skipCdmKey = "cooldowns" }) == false, "a differing nameplate glow is not seen on retail")
    check(E.IsPandemicGlowSyncedToAll(payload, { skipCdmKey = "cooldowns", skipNameplates = true }) == true, "the nameplates are compared when they are the source")
end

-------------------------------------------------------------------------------
-- 7. the options: the two rows say what the glow does; WoW Forever builds no nameplate row
-------------------------------------------------------------------------------
do
    local BARS = ReadSource("EllesmereUIOptions/CooldownManager_Options/BarsPage_Options.lua")
    local TBB = ReadSource("EllesmereUIOptions/CooldownManager_Options/BuffBarsPage_Options.lua")
    local ICONS_TIP = "Show a glow on icons when casting the spell next, after your current cast or global cooldown, won't clip it, or it has 1.5 seconds or less left"
    local BAR_TIP = "Show a glow on the bar when casting the spell next, after your current cast or global cooldown, won't clip it, or it has 1.5 seconds or less left"
    local ICONS_SYNC = "Apply this glow's look to all CDM bars and tracking bars. A surface that can't show a style uses its closest match."
    local BAR_SYNC = "Apply this glow's look to all CDM bars and other tracking bars. A surface that can't show a style uses its closest match."
    check(BARS:find('antiClip and "' .. ICONS_TIP .. '"', 1, true), "the CDM Bars row's tooltip does not name the last 1.5 seconds")
    check(TBB:find('antiClip and "' .. BAR_TIP .. '"', 1, true), "the Tracking Bars row's tooltip does not name the last 1.5 seconds")
    check(BARS:find('antiClip and "' .. ICONS_SYNC .. '"', 1, true), "the CDM Bars row's Apply to All tooltip is not the WoW Forever one")
    check(TBB:find('antiClip and "' .. BAR_SYNC .. '"', 1, true), "the Tracking Bars row's Apply to All tooltip is not the WoW Forever one")
    check(not BARS:find("look to the Nameplates Pandemic Glow", 1, true) and not TBB:find("look to the Nameplates Pandemic Glow", 1, true),
        "an Apply to All tooltip still names a nameplate glow WoW Forever does not have")
    -- every locale that had the four texts has them under the new wording, once, and the old ones are gone
    for _, code in ipairs({ "deDE", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }) do
        local loc = ReadSource("EllesmereUILocales/" .. code .. ".lua")
        for _, key in ipairs({ ICONS_TIP, BAR_TIP, ICONS_SYNC, BAR_SYNC }) do
            local _, n = loc:gsub('\nL%["' .. key:gsub("%p", "%%%0") .. '"%]', "")
            check(n == 1, code .. " holds " .. n .. " translations of: " .. key:sub(1, 48))
        end
        check(not loc:find("won't clip it\"]", 1, true) and not loc:find("look to the Nameplates Pandemic Glow", 1, true), code .. " keeps a translation nothing reads")
    end
    -- the nameplate row and its Glows page entry are not built where there is no pandemic window
    local GENERAL = ReadSource("EllesmereUIOptions/Nameplates_Options/GeneralPage_Options.lua")
    local row = Cut(GENERAL, "    -- --- Pandemic Glow ----", "    -- --- Dispellable Buff Glow ----", "the Pandemic Glow row")
    local gate = row:find("\n    if not ns.NP_PANDEMIC_NONE then\n", 1, true)
    local build = row:find('GO.DropdownSpec(panDesc, "Pandemic Glow Style"', 1, true)
    local close = row:find("\n    end -- not NP_PANDEMIC_NONE\n", 1, true)
    check(gate and build and close and gate < build and build < close, "the nameplate Pandemic Glow row is built on WoW Forever")
    local NPO = ReadSource("EllesmereUIOptions/EUI_Nameplates_Options.lua")
    local site = NPO:find('GO.RegisterSite({ id = "np_pandemic"', 1, true)
    check(site and NPO:sub(site - 60, site - 1):find("if not ns.NP_PANDEMIC_NONE then%s+$"), "the nameplate Pandemic Glow is listed on the Glows page on WoW Forever")
end

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print(("PASS test_cdm_forever_anti_clip (%d checks)"):format(count))
