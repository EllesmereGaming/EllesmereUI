-- Stub harness: Cooldown Manager, the settings a "Replace with Buff" icon resolves.
-- A cooldown set to Replace with Buff shows Blizzard's buff frame in the cooldown's slot while
-- the buff is up. That frame takes the cooldown's identity (fc.replacesCd): it resolves as the
-- cooldown, on every bar, so the cooldown's own settings and the bar's Apply to Bar values reach
-- it. A buff added to the bar with + is the other case: it reads the buff family store and
-- never the bar tier. The bar's list of + buffs (hostedBuffSpellIDs) stays saved, empty, after
-- the last one is removed, and must not turn a replacement into a + buff.
--   * a replacement resolves the same with no list, with an empty list and with a + buff listed;
--   * a + buff keeps its own settings and ignores the bar tier;
--   * the result memo names fc.replacesCd: the collect pass flips it with no generation bump.
-- Loads the real EUI_CDM_HookResolve.lua whole over stub stores and frames.
--   lua .tools/tests/test_cdm_replace_buff_settings.lua        (from the repository root)
local TARGET = "EllesmereUICooldownManager/EUI_CDM_HookResolve.lua"

local fails, count = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        if fails <= 14 then print("  FAIL: " .. msg) end
    end
end

EUI_CLIENT_BLOCKED = false
C_Spell = { GetBaseSpell = function(id) return id end }
C_SpellBook = { FindSpellOverrideByID = function(id) return id end }
issecretvalue = function() return false end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
C_CooldownViewer = { GetCooldownViewerCooldownInfo = function() return nil end }
BuffIconCooldownViewer = { name = "BuffIcon" }
BuffBarCooldownViewer = { name = "BuffBar" }

-- a cooldown, the buff that replaces it, and an unrelated buff added with +
local COOLDOWN, BUFF, PLUS = 280735, 52437, 1719

local cdStore = { [COOLDOWN] = { replaceBuffID = BUFF } }
local buffStore = { [BUFF] = { buffGlow = 3 }, [PLUS] = { buffGlow = 5 } }
local bars = { { key = "cooldowns", barType = "cooldowns", enabled = true } }
local sd = { assignedSpells = { COOLDOWN }, barSettings = { procGlow = 0, cdSwipeColor = "class" } }
local storeReads = 0

local ns = {
    _hookInternals = { broken = false },
    ECME = { db = { profile = { cdmBars = { bars = bars } } } },
    _ecmeFC = {}, _hookFrameData = {}, _cdmResGen = 1,
    barDataByKey = { cooldowns = bars[1] },
}
function ns.ChainSettings(child, parent)
    if type(child) ~= "table" then return end
    local mt = getmetatable(child)
    if parent then
        if not mt then setmetatable(child, { __index = parent })
        elseif mt.__index ~= parent then mt.__index = parent end
    elseif mt and mt.__index ~= nil then
        mt.__index = nil
    end
end
function ns.GetBarTierSettings(sdx, barKey)
    local bd = barKey and ns.barDataByKey[barKey]
    local abs = bd and bd.barSpellSettings
    local bs = sdx and sdx.barSettings
    if bs then ns.ChainSettings(bs, abs); return bs end
    return abs
end
function ns.GetSpellSettingsStore(key)
    storeReads = storeReads + 1
    return key == "buffs" and buffStore or cdStore
end
function ns.GetBarSpellData() return sd end
function ns.BuffFamHasCdKey() return false end
function ns.GetCanonicalSpellIDForFrame(f) return f._canon end

assert(loadfile(TARGET))("EllesmereUICooldownManager", ns)
assert(ns._hookInternals.broken == false, TARGET .. " did not load to its end")
local Resolve = ns.ResolveSpellSettings

-- the replacement: Blizzard's buff viewer frame standing in the cooldown's slot
local F = { viewerFrame = BuffIconCooldownViewer, _canon = BUFF }
ns._hookFrameData[F] = { _isBuffViewerFrame = true }
ns._ecmeFC[F] = { barKey = "cooldowns", spellID = COOLDOWN, replacesCd = COOLDOWN, resolvedSid = BUFF, baseSpellID = BUFF }
-- a buff added to the same bar with +
local H = { viewerFrame = BuffIconCooldownViewer, _canon = PLUS }
ns._hookFrameData[H] = { _isBuffViewerFrame = true }
ns._ecmeFC[H] = { barKey = "cooldowns", spellID = PLUS, isHostedBuff = true, resolvedSid = PLUS, baseSpellID = PLUS }

local function bump() ns._cdmResGen = ns._cdmResGen + 1 end
local function show(v) return v == nil and "nil" or tostring(v) end

-------------------------------------------------------------------------------
-- 1. a replacement resolves as its cooldown, whatever the bar's + list holds
-------------------------------------------------------------------------------
local LISTS = {
    { "no + list", nil },
    { "an empty + list (left after the last + buff was removed)", {} },
    { "a + buff listed", { [PLUS] = true } },
}
for _, case in ipairs(LISTS) do
    sd.hostedBuffSpellIDs = case[2]
    bump()
    -- asked with the cooldown's id (the proc glow and the cooldown hooks ask this way)
    local ss = Resolve(F, COOLDOWN, sd, "cooldowns")
    check(ss and ss.procGlow == 0, case[1] .. ": the bar's Proc Glow None does not reach the replacement (reads " .. show(ss and ss.procGlow) .. ")")
    check(ss and ss.cdSwipeColor == "class", case[1] .. ": the bar's other Apply to Bar values do not reach it (reads " .. show(ss and ss.cdSwipeColor) .. ")")
    check(ss and ss.replaceBuffID == BUFF, case[1] .. ": the replacement does not read the cooldown's own entry")
    -- asked with the buff's id (the appearance pass asks this way): the cooldown store has no
    -- entry under it, so the bar tier answers, never the buff's own Buff-family entry
    ss = Resolve(F, BUFF, sd, "cooldowns")
    check(ss and ss.buffGlow == nil, case[1] .. ": the buff's own Buff Glow shows on the replacement (reads " .. show(ss and ss.buffGlow) .. ")")
    check(ss and ss.procGlow == 0, case[1] .. ": asked by the buff's id, the bar tier does not answer")
end

-------------------------------------------------------------------------------
-- 2. a buff added with + keeps its own settings and ignores the bar tier
-------------------------------------------------------------------------------
sd.hostedBuffSpellIDs = { [PLUS] = true }
bump()
do
    local ss = Resolve(H, PLUS, sd, "cooldowns")
    check(ss and ss.buffGlow == 5, "a + buff does not read its own Buff Glow (reads " .. show(ss and ss.buffGlow) .. ")")
    check(ss and ss.procGlow == nil, "the bar's Apply to Bar values reach a + buff (procGlow " .. show(ss and ss.procGlow) .. ")")
end

-------------------------------------------------------------------------------
-- 3. the memo: a second ask is a hit, and a flipped replacesCd is a miss
-------------------------------------------------------------------------------
do
    local fc = ns._ecmeFC[F]
    bump()
    Resolve(F, BUFF, sd, "cooldowns")
    local before = storeReads
    local again = Resolve(F, BUFF, sd, "cooldowns")
    check(storeReads == before, "a second ask with nothing changed resolves again (" .. (storeReads - before) .. " store reads)")
    check(again and again.procGlow == 0, "the memo's answer lost the bar tier")
    -- the frame as a + buff (its buff was hosted before it became a replacement): memo filled
    fc.replacesCd, fc.isHostedBuff = nil, true
    bump()
    local ss = Resolve(F, BUFF, sd, "cooldowns")
    check(ss and ss.buffGlow == 3, "a + buff frame does not read the buff store (reads " .. show(ss and ss.buffGlow) .. ")")
    -- the collect pass makes it a replacement: no generation bump, same id and bar
    fc.replacesCd, fc.isHostedBuff = COOLDOWN, nil
    ss = Resolve(F, BUFF, sd, "cooldowns")
    check(ss and ss.buffGlow == nil, "after replacesCd was set the memo still hands back the + buff answer (buffGlow " .. show(ss and ss.buffGlow) .. ")")
    check(ss and ss.procGlow == 0, "after replacesCd was set the bar tier does not answer")
    -- and back, again with no bump
    fc.replacesCd, fc.isHostedBuff = nil, true
    ss = Resolve(F, BUFF, sd, "cooldowns")
    check(ss and ss.buffGlow == 3, "after replacesCd was cleared the memo still hands back the replacement's answer")
    fc.replacesCd, fc.isHostedBuff = COOLDOWN, nil
    -- every other input edge still bumps the generation: the bar's + list going away is a miss
    sd.hostedBuffSpellIDs = { [PLUS] = true }
    bump()
    ss = Resolve(H, PLUS, sd, "cooldowns")
    check(ss and ss.buffGlow == 5, "the + buff lost its own settings")
    sd.hostedBuffSpellIDs = nil
    bump()
    ss = Resolve(H, PLUS, sd, "cooldowns")
    check(ss and ss.buffGlow == nil and ss.procGlow == 0, "a generation bump does not make the memo resolve again")
end

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print(("PASS test_cdm_replace_buff_settings (%d checks)"):format(count))
