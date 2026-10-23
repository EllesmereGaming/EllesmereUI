if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
local FT = EllesmereUI.FormattedText

local function PowerType(ctx)
    if ctx.powerType ~= nil then return ctx.powerType end
    return UnitPowerType(ctx.unit)
end

local function MaximumPercent(value)
    -- A restricted maximum is never tested or divided; the maximum denotes 100%.
    if issecretvalue(value) then return 100 end
    return value > 0 and 100 or 0
end

local function Variant(read, preview, dependency, readerKey, format, width, identity, uncoloredReaderKey)
    return { read = read, preview = preview, dependencies = { dependency }, readerKey = readerKey,
        sampleKey = readerKey, format = format, width = width, identity = identity, uncoloredReaderKey = uncoloredReaderKey }
end

local function NumberVariant(read, preview, dependency, readerKey, abbreviated, width, identity, uncoloredReaderKey)
    local variant = Variant(read, preview, dependency, readerKey, nil, width, identity, uncoloredReaderKey)
    variant.numeric, variant.abbreviated = true, abbreviated == true
    return variant
end

local NUMBER_MODS = { max = { "full" }, abbreviated = { "abr" }, percentage = { "percent", "pct" } }
local function NumberTag(id, aliases, description, readers)
    local current, maximum, percent, maxPercent = readers[1], readers[2], readers[3], readers[4]
    local dep = id == "health" and "hp" or "pp"
    local variants = {
        [""] = NumberVariant(current, "230000", dep, id, false, 48),
        max = NumberVariant(maximum, "300000", dep, id .. "Max", false, 48),
        abbreviated = NumberVariant(current, "230000", dep, id, true, 38),
        ["abbreviated:max"] = NumberVariant(maximum, "300000", dep, id .. "Max", true, 38),
        percentage = NumberVariant(percent, "76.67", dep, id .. "RawPercentage", false, 30),
        ["max:percentage"] = NumberVariant(maxPercent, "100", dep, id .. "RawMaxPercentage", false, 30),
    }
    FT:RegisterTag(id, { aliases = aliases, context = "unit", description = description,
        modifiers = NUMBER_MODS, variants = variants, modifierDescriptions = {
            max = EllesmereUI.L("Use the maximum value."),
            abbreviated = EllesmereUI.L("Shorten large numbers, such as 230K."),
            percentage = EllesmereUI.L("Show the percentage value, such as 77. Add % yourself."),
        } })
end

NumberTag("health", { "hp" }, EllesmereUI.L("Current or maximum health"), {
    function(ctx) return UnitHealth(ctx.unit) end,
    function(ctx) return UnitHealthMax(ctx.unit) end,
    function(ctx) return UnitHealthPercent(ctx.unit, true, CurveConstants.ScaleTo100) end,
    function(ctx) return MaximumPercent(UnitHealthMax(ctx.unit)) end,
})
NumberTag("power", { "pp" }, EllesmereUI.L("Current or maximum power"), {
    function(ctx) return UnitPower(ctx.unit, PowerType(ctx)) end,
    function(ctx) return UnitPowerMax(ctx.unit, PowerType(ctx)) end,
    function(ctx) return UnitPowerPercent(ctx.unit, PowerType(ctx), true, CurveConstants.ScaleTo100) end,
    function(ctx) return MaximumPercent(UnitPowerMax(ctx.unit, PowerType(ctx))) end,
})

FT:RegisterTag("name", { context = "unit", description = EllesmereUI.L("Unit name"), variants = {
    [""] = Variant(function(ctx) return UnitName(ctx.unit) end, "Player", "id", "name", nil, 0, true),
} })
FT:RegisterTag("level", { context = "unit", description = EllesmereUI.L("Unit level"), variants = {
    [""] = NumberVariant(function(ctx) return UnitEffectiveLevel(ctx.unit) end, "80", "id", "level", false, 24, true, "levelUncolored"),
} })
FT:RegisterTag("target", { context = "unit", description = EllesmereUI.L("Name of the unit's target"), variants = {
    [""] = Variant(function(ctx)
        local unit = ctx.unit .. "target"
        if not UnitExists(unit) then return "" end
        return UnitName(unit)
    end, "Target", "tgt", "target", nil, 0),
} })
FT:RegisterTag("group", { context = "unit", description = EllesmereUI.L("Raid subgroup, party, or Solo"), variants = {
    [""] = NumberVariant(function(ctx)
        if IsInRaid() then
            local index = UnitInRaid(ctx.unit)
            -- Restricted unit identities cannot be used as roster indexes.
            if issecretvalue(index) then return "" end
            if index then
                local _, _, subgroup = GetRaidRosterInfo(index)
                return subgroup or ""
            end
        elseif IsInGroup() and (ctx.unit == "player" or UnitInParty(ctx.unit)) then
            return EllesmereUI.L("party")
        end
        return EllesmereUI.L("Solo")
    end, "3", "roster", "group", false, 30),
} })

local function AbsorbTag(id, description, get, dependency)
    FT:RegisterTag(id, { context = "unit", description = description,
        modifiers = { abbreviated = { "abr" } }, variants = {
            [""] = NumberVariant(function(ctx) return get(ctx.unit) end, "12000", dependency, id, false, 38),
            abbreviated = NumberVariant(function(ctx) return get(ctx.unit) end, "12000", dependency, id, true, 38),
        } })
end
AbsorbTag("absorb", EllesmereUI.L("Absorb shield"), UnitGetTotalAbsorbs, "abs")
AbsorbTag("healabsorb", EllesmereUI.L("Heal absorb"), UnitGetTotalHealAbsorbs, "habs")

FT:RegisterTag("durability", { context = "unit", description = EllesmereUI.L("Lowest player equipment durability percentage"),
    variants = { [""] = NumberVariant(function()
        local lowest = 100
        for slot = 1, 18 do
            local current, maximum = GetInventoryItemDurability(slot)
            if current and maximum and maximum > 0 then lowest = math.min(lowest, current / maximum * 100) end
        end
        return lowest
    end, "96.75", "durability", "durability", false, 20) } })

local dependencies = {}
function FT:RegisterUnitDependency(id, definition)
    assert(type(id) == "string" and id:match("^[a-z][a-z0-9_.-]*$") and not dependencies[id],
        "duplicate or invalid unit dependency")
    local copy = { external = definition.external == true }
    for _, key in ipairs({ "unitEvents", "targetEvents", "globalEvents" }) do
        copy[key] = {}
        for i = 1, #(definition[key] or {}) do
            local event = definition[key][i]
            assert(type(event) == "string" and event:match("^[A-Z][A-Z0-9_]+$"), "invalid dependency event")
            copy[key][i] = event
        end
    end
    dependencies[id] = copy
end
FT:RegisterUnitDependency("hp", { unitEvents = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_MAX_HEALTH_MODIFIERS_CHANGED" } })
FT:RegisterUnitDependency("pp", { unitEvents = { "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" } })
FT:RegisterUnitDependency("id", { unitEvents = { "UNIT_NAME_UPDATE", "UNIT_LEVEL" } })
FT:RegisterUnitDependency("tgt", { unitEvents = { "UNIT_TARGET" }, targetEvents = { "UNIT_NAME_UPDATE" } })
FT:RegisterUnitDependency("roster", { globalEvents = { "GROUP_ROSTER_UPDATE" }, external = true })
FT:RegisterUnitDependency("abs", { unitEvents = { "UNIT_ABSORB_AMOUNT_CHANGED" } })
FT:RegisterUnitDependency("habs", { unitEvents = { "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" } })
FT:RegisterUnitDependency("durability", { globalEvents = { "UPDATE_INVENTORY_DURABILITY", "PLAYER_EQUIPMENT_CHANGED" }, external = true })

local IDENTITY_EVENT = { target = "PLAYER_TARGET_CHANGED", targettarget = "PLAYER_TARGET_CHANGED",
    focus = "PLAYER_FOCUS_CHANGED", focustarget = "PLAYER_FOCUS_CHANGED" }
-- Custom slots for the same unit share one filtered event source. Hidden
-- bindings leave the group, so pooled plates and raid cells add no idle work.
local groups = {}
local function Clear(t) for key in pairs(t) do t[key] = nil end end
local function Route(group, map, event, display)
    map[event] = true
    local route = group.routes[event]
    if not route then route = {}; group.routes[event] = route end
    route[display] = true
end
local function Rebuild(group)
    local f, own, target, global = group.frame, group.own, group.target, group.global
    f:UnregisterAllEvents()
    Clear(own); Clear(target); Clear(global); Clear(group.routes)
    local unit = group.unit
    for display, reads in pairs(group.displays) do
        local ctx = display.context
        local managed, covered = ctx.managed, ctx.covered
        for id in pairs(reads) do
            local def = dependencies[id]
            if def and not (covered and covered[id]) then
                if not managed or def.external then
                    for i = 1, #def.unitEvents do Route(group, own, def.unitEvents[i], display) end
                    for i = 1, #def.globalEvents do Route(group, global, def.globalEvents[i], display) end
                end
                for i = 1, #def.targetEvents do Route(group, target, def.targetEvents[i], display) end
            end
        end
        if not managed then
            Route(group, own, "UNIT_CONNECTION", display)
            local identity = IDENTITY_EVENT[unit]
            if identity then Route(group, global, identity, display) end
            if unit:match("^boss%d$") then Route(group, global, "INSTANCE_ENCOUNTER_ENGAGE_UNIT", display) end
            if reads.tgt and unit == "player" then Route(group, global, "PLAYER_TARGET_CHANGED", display) end
        end
    end
    for event in pairs(own) do
        if target[event] then f:RegisterUnitEvent(event, unit, unit .. "target")
        else f:RegisterUnitEvent(event, unit) end
    end
    for event in pairs(target) do
        if not own[event] then f:RegisterUnitEvent(event, unit .. "target") end
    end
    for event in pairs(global) do f:RegisterEvent(event) end
end

FT:RegisterContext("unit", {
    examples = { "[:hp:abr:] / [:hp:max:abr:]", "[:hp:percent:]%", "[:hp:max:percent:]%", "[:name:] - [:hp:abr:]" },
    available = function(ctx) return ctx.unit ~= nil and UnitExists(ctx.unit) end,
    subscribe = function(display, reads)
        local ctx = display.context
        if ctx.preview or not ctx.unit then return end
        local wanted = false
        for id in pairs(reads) do
            local def = dependencies[id]
            if def and not (ctx.covered and ctx.covered[id])
                and (not ctx.managed or def.external or #def.targetEvents > 0) then wanted = true; break end
        end
        if not wanted then return end
        local group = groups[ctx.unit]
        if not group then
            group = { unit = ctx.unit, displays = {}, routes = {}, own = {}, target = {}, global = {} }
            group.frame = CreateFrame("Frame")
            group.frame:SetScript("OnEvent", function(_, event)
                local route = event and group.routes[event] or group.displays
                if route then
                    for binding in pairs(route) do
                        if binding.active and binding.fs:GetParent():IsShown() then binding:Render() end
                    end
                end
            end)
            groups[ctx.unit] = group
        end
        display.events = group.frame
        group.displays[display] = reads
        Rebuild(group)
        return function() group.displays[display] = nil; Rebuild(group) end
    end,
})
