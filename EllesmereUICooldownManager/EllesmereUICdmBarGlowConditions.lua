if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUICdmBarGlowConditions.lua
--  Extra conditions on a Bar Glow entry, evaluated after the entry's own
--  Glow When result (ns.BarGlowCombine, called from UpdateOverlayVisuals):
--
--    entry.andMode       = "and" | nil (off)
--    entry.conditions[1] = { spellID = n, state = nil (active) | "missing" }
--        The glow also needs a second buff active (or missing). Read from the
--        same active-aura cache the trigger uses (ns._tickBlizzActiveCache:
--        plain booleans, so safe in combat). An "or" is simply a second glow
--        entry on the same button. A second buff not chosen yet changes nothing.
--
--    entry.heroTree      = hero talent subTreeID | nil (any)
--        The glow only runs while that hero tree is active, so one button can
--        carry different glows per hero tree. Ignored on WoW Forever (no hero
--        talents), so a glow imported from retail still lights there.
--
--    entry.healthBelow   = percentage | nil
--    entry.healthAbove   = percentage | nil
--        The glow only runs while the player's health percentage is strictly
--        below or above the value (one of the two). Readable health is
--        compared here; secret health passes and the overlay's native gate
--        masks the glow instead (EllesmereUICdmBarGlows.lua).
--
--  Cost: nothing for entries without these keys (two table reads). The hero
--  tree is one C call per hero-gated entry per glow pass, no cache and no
--  events of our own; ns._barGlowAnyHero (set by SetupOverlays) lets the
--  talent-change handler re-run the glow pass only while such an entry exists.
-------------------------------------------------------------------------------
local _, ns = ...

local function ActiveHeroTree()
    local CT = C_ClassTalents
    local id = CT and CT.GetActiveHeroTalentSpec and CT.GetActiveHeroTalentSpec()
    if type(id) == "number" and id > 0 then return id end
    return nil
end

local aboveCurves, belowCurves = {}, {}  -- [percentage] = step curve, false when unavailable

-- The entry's health rule: the percentage, and whether the glow wants health
-- above it (below otherwise). Nil without one.
local function HealthRule(entry)
    local above = tonumber(entry.healthAbove)
    if above and above > 0 then return above, true end
    local below = tonumber(entry.healthBelow)
    if below and below > 0 then return below, false end
end
ns.BarGlowHealthRule = HealthRule

-- Whether readable health satisfies the rule. Secret health passes: Lua cannot
-- compare it, the overlay's native gate does (ns.BarGlowHealthNative).
local function HealthPass(entry)
    local threshold, above = HealthRule(entry)
    if not threshold then return true end
    -- Not predicted, as the curve path reads it: both answer alike at the crossing.
    local current, maximum = UnitHealth("player", false), UnitHealthMax("player")
    -- Secret probe first: any other test on a secret value hard-errors.
    if issecretvalue(current) or issecretvalue(maximum) then return true end
    if not current or not maximum or maximum <= 0 then return false end
    local pct = current / maximum * 100
    if above then return pct > threshold end
    return pct < threshold
end
ns.BarGlowHealthPass = HealthPass

-- A step curve that reads 1 while the rule holds and 0 otherwise.
local function HealthCurve(threshold, above)
    local cache = above and aboveCurves or belowCurves
    local curve = cache[threshold]
    if curve ~= nil then return curve end
    local ok
    if C_CurveUtil and C_CurveUtil.CreateCurve and Enum.LuaCurveType then
        ok, curve = pcall(function()
            local c = C_CurveUtil.CreateCurve()
            c:SetType(Enum.LuaCurveType.Step)
            if above then
                c:AddPoint(0, 0)
                c:AddPoint(threshold / 100, 0)
                if threshold < 100 then
                    c:AddPoint(math.min(1, (threshold + 0.0001) / 100), 1)
                    c:AddPoint(1, 1)
                end
            else
                c:AddPoint(0, 1)
                c:AddPoint(threshold / 100, 0)
                if threshold < 100 then c:AddPoint(1, 0) end
            end
            return c
        end)
    end
    curve = ok and curve or false
    cache[threshold] = curve
    return curve
end

-- The value an overlay's health gate takes (EllesmereUICdmBarGlows.lua): the
-- rule's curve over the player's health, 1 or 0, secret while health is and
-- never read here. Returns false when the client cannot evaluate it.
function ns.BarGlowHealthNative(entry)
    local threshold, above = HealthRule(entry)
    local curve = threshold and UnitHealthPercent and HealthCurve(threshold, above)
    if not curve then return false end
    local ok, value = pcall(UnitHealthPercent, "player", false, curve)
    if not ok then return false end
    return true, value
end

-- The current spec's hero trees, for the options dropdown:
-- { { id = subTreeID, name = "Spellslinger" }, ... }
function ns.BarGlowHeroTrees()
    local out = {}
    local CT = C_ClassTalents
    if not (CT and CT.GetHeroTalentSpecsForClassSpec and CT.GetActiveConfigID) then return out end
    local configID = CT.GetActiveConfigID()
    local ok, ids = pcall(CT.GetHeroTalentSpecsForClassSpec, configID)
    if not ok or type(ids) ~= "table" then return out end
    for _, id in ipairs(ids) do
        local info = configID and C_Traits and C_Traits.GetSubTreeInfo and C_Traits.GetSubTreeInfo(configID, id)
        out[#out + 1] = { id = id, name = (info and info.name) or ("Hero Tree " .. id) }
    end
    return out
end

-- The entry's final glow state, given its own Glow When result `main`.
function ns.BarGlowCombine(entry, main, cache)
    local hero = entry.heroTree
    if hero and not EllesmereUI.IS_FOREVER and ActiveHeroTree() ~= hero then return false end
    if (entry.healthBelow or entry.healthAbove) and not HealthPass(entry) then return false end
    if entry.andMode ~= "and" then return main end
    local c = type(entry.conditions) == "table" and entry.conditions[1]
    local sid = type(c) == "table" and tonumber(c.spellID)
    if not sid or sid <= 0 then return main end
    local active = (cache ~= nil and cache[sid] == true)
    local ok
    if c.state == "missing" then ok = not active else ok = active end
    return (main and ok) and true or false
end
