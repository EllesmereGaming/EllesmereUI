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
    if entry.andMode ~= "and" then return main end
    local c = type(entry.conditions) == "table" and entry.conditions[1]
    local sid = type(c) == "table" and tonumber(c.spellID)
    if not sid or sid <= 0 then return main end
    local active = (cache ~= nil and cache[sid] == true)
    local ok
    if c.state == "missing" then ok = not active else ok = active end
    return (main and ok) and true or false
end
