-- Stub harness: loads the Action Bars paging file outside the game and checks
-- the Modifier / Target Paging split. The five states form two groups,
-- modifier (shift, ctrl, alt; the bar's modifierPaging) and target (help,
-- harm; its targetPaging). A group is off when the bar's modTargetPaging is
-- false (it holds both off, an override's pin included) or its own key is
-- false; with both new keys unset every bar pages exactly as before. Walks all
-- 27 stored combinations of modTargetPaging x modifierPaging x targetPaging.
--   lua .tools/tests/test_ab_paging_mod_target_split.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return src
end
local SRC = ReadSource("EllesmereUIActionBars/EUI_ActionBars_Paging.lua")

local function Load(bars)
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.EUI_CLIENT_BLOCKED = nil
    env.issecretvalue = function() return false end
    env.InCombatLockdown = function() return false end
    env.UnitClass = function() return "Warrior", "WARRIOR" end
    env.GetNumShapeshiftForms = function() return 0 end
    env.GetShapeshiftFormInfo = function() return nil end
    env.RegisterAttributeDriver = function() end
    env.UnregisterAttributeDriver = function() end
    env.CreateFrame = function()
        local f = {}
        function f:RegisterEvent() end
        function f:SetScript() end
        return f
    end
    env.EllesmereUI = {
        IS_FOREVER = false,
        CLASS_PAGING_STATES = { WARRIOR = { { id = "battle", macro = "[stance:1]" } } },
    }
    local ns = {
        EFD = function() return {} end,
        EAB = { db = { profile = { bars = bars } } },
        EAB_VTABLE = {},
        _internals = {
            barBaseSize = {}, barFrames = {}, NUM_AB_PAGES = 6,
            SetPagingFrame = function() end, pagingFrameSetters = {},
        },
        CombatQueue = { Defer = function() end },
    }
    local chunk = assert(loadstring(SRC, "=EUI_ActionBars_Paging.lua"))
    setfenv(chunk, env)
    chunk("EllesmereUIActionBars", ns)
    return ns.EAB_VTABLE
end

local VALUES = { "nil", true, false }
local function V(x) if x == "nil" then return nil end return x end
local function Name(x) return x == "nil" and "nil" or tostring(x) end

-- The rule, written out on its own: a group is off while modTargetPaging is
-- false, whatever its own key says, or when its own key is false.
local function Off(own, legacy)
    if legacy == false then return true end
    return own == false
end

local PAGES = { alt = 4, shift = 2, ctrl = 3, help = 5, harm = 7, battle = 8 }
local MOD = "[mod:alt] 4; [mod:shift] 2; [mod:ctrl] 3"
local TGT = "[help] 5; [harm] 7"

local function Expected(barKey, modOff, tgtOff, defaultPage)
    local parts = {}
    if not modOff then parts[#parts + 1] = MOD end
    parts[#parts + 1] = "[stance:1] 8"
    if barKey == "MainBar" then
        parts[#parts + 1] = "[bar:2] 2; [bar:3] 3; [bar:4] 4; [bar:5] 5; [bar:6] 6; [bonusbar:5] 11"
    end
    if not tgtOff then parts[#parts + 1] = TGT end
    parts[#parts + 1] = tostring(defaultPage)
    return table.concat(parts, "; ")
end

local combos = 0
for _, legacy in ipairs(VALUES) do
    for _, mod in ipairs(VALUES) do
        for _, tgt in ipairs(VALUES) do
            combos = combos + 1
            local bs = { modTargetPaging = V(legacy), modifierPaging = V(mod), targetPaging = V(tgt) }
            local tag = ("modTarget=%s modifier=%s target=%s"):format(Name(legacy), Name(mod), Name(tgt))
            local VT = Load({ MainBar = bs, Bar2 = bs })
            local modOff, tgtOff = Off(V(mod), V(legacy)), Off(V(tgt), V(legacy))

            assert(VT.PagingGroupOff(bs, "modifier") == modOff, tag .. ": modifier group")
            assert(VT.PagingGroupOff(bs, "target") == tgtOff, tag .. ": target group")

            -- The built conditions, on bar 1 and on another bar.
            for _, barKey in ipairs({ "MainBar", "Bar2" }) do
                local def = barKey == "MainBar" and 1 or 6
                local got = VT.BuildPagingConditions(barKey, PAGES, def)
                local want = Expected(barKey, modOff, tgtOff, def)
                assert(got == want, tag .. " on " .. barKey .. ":\n  got  " .. tostring(got) .. "\n  want " .. want)
            end

            -- Today's rule, where the new keys are unset: both groups follow
            -- modTargetPaging together.
            if mod == "nil" and tgt == "nil" then
                assert(modOff == (V(legacy) == false) and tgtOff == modOff, tag .. ": unset keys left today's rule")
            end

            -- HasCustomPaging: a state in an off group is not paging the
            -- player has; a state outside the five always is.
            assert(VT.HasCustomPaging({ paging = { shift = 2 }, modTargetPaging = V(legacy), modifierPaging = V(mod), targetPaging = V(tgt) }) == not modOff,
                tag .. ": a modifier state alone")
            assert(VT.HasCustomPaging({ paging = { harm = 7 }, modTargetPaging = V(legacy), modifierPaging = V(mod), targetPaging = V(tgt) }) == not tgtOff,
                tag .. ": a target state alone")
            assert(VT.HasCustomPaging({ paging = { alt = 4, help = 5 }, modTargetPaging = V(legacy), modifierPaging = V(mod), targetPaging = V(tgt) }) == not (modOff and tgtOff),
                tag .. ": a modifier and a target state")
            assert(VT.HasCustomPaging({ paging = { battle = 8 }, modTargetPaging = V(legacy), modifierPaging = V(mod), targetPaging = V(tgt) }) == true,
                tag .. ": a class state")
            assert(VT.HasCustomPaging({ paging = {}, modTargetPaging = V(legacy), modifierPaging = V(mod), targetPaging = V(tgt) }) == false,
                tag .. ": no states")
            -- An old save's false (Default) still counts as configured, as before.
            assert(VT.HasCustomPaging({ paging = { ctrl = false }, modTargetPaging = V(legacy), modifierPaging = V(mod), targetPaging = V(tgt) }) == not modOff,
                tag .. ": a modifier state saved as false")
        end
    end
end
assert(combos == 27, "27 combinations")

-- A bar with no settings: everything applies, nothing is off.
do
    local VT = Load({})
    assert(VT.PagingGroupOff(nil, "modifier") == false and VT.PagingGroupOff(nil, "target") == false, "no settings: off")
    assert(VT.BuildPagingConditions("Bar2", PAGES, 6) == Expected("Bar2", false, false, 6), "no settings: conditions")
    assert(VT.BuildPagingConditions("Bar2", {}, 6) == nil, "an empty config builds nothing")
    assert(VT.HasCustomPaging(nil) == false and VT.HasCustomPaging({}) == false, "no paging table")
    -- Every one of the five states belongs to a group (options read it as a set).
    local groups = {}
    for id, g in pairs(VT.MOD_TARGET_PAGING) do groups[id] = g end
    assert(groups.shift == "modifier" and groups.ctrl == "modifier" and groups.alt == "modifier"
        and groups.help == "target" and groups.harm == "target", "the five states and their groups")
    local n = 0
    for _ in pairs(groups) do n = n + 1 end
    assert(n == 5, "MOD_TARGET_PAGING lists exactly the five states")
end

print("action bars paging modifier / target split harness: ok (27 combinations)")
