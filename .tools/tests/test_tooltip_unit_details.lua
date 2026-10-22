-- Run from the repository root: lua .tools/tests/test_tooltip_unit_details.lua
local path = arg[1] or "EllesmereUIBlizzardSkin/EUI_BlizzardSkin_TooltipSkin.lua"
local file = assert(io.open(path, "rb"))
local source = file:read("*a"):gsub("\r\n", "\n")
file:close()
local first = assert(source:find("    do\n        local installed = false\n        EllesmereUI._applyTooltipUnitDetails", 1, true))
local last = assert(source:find('    -- "Targeting" line:', first, true))
local production = source:sub(first, last - 1)
local checks = 0
local function Check(condition, message)
    checks = checks + 1
    assert(condition, message)
end

local secret = setmetatable({}, {
    __index = function() error("attempted to read a secret") end,
    __tostring = function() error("attempted to format a secret") end,
})
local inaccessible = {}
local function Copy(value)
    if type(value) ~= "table" or value == secret then return value end
    local copy = {}
    for key, item in pairs(value) do copy[key] = Copy(item) end
    return copy
end
local function Same(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" or a == secret or b == secret then return false end
    for key, value in pairs(a) do if not Same(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

local function Fixture()
    local f = {
        enabled = true, usable = true,
        classification = "normal", level = 15, registrations = 0, identityCalls = 0,
        processingCalls = 0, existsCalls = 0, classificationCalls = 0, levelCalls = 0,
        lineCallbacks = {}, lineCalls = 0, watchedRowChecks = 0,
        settings = { tooltipShowRarity = false },
    }
    f.tooltip = { rendered = {} }
    function f.tooltip:IsForbidden() return f.forbidden end
    function f.tooltip:GetProcessingTooltipInfo()
        f.processingCalls = f.processingCalls + 1
        if f.processingError then error("restricted processing info") end
        return f.processingInfo
    end
    local env = setmetatable({
        EllesmereUIDB = f.settings,
        EllesmereUI = {
            L = function(text) return text end,
            BlizzSkinPadStandDown = function() return f.standDown end,
        },
        Enum = { TooltipDataType = { Unit = 2 },
            TooltipDataLineType = { None = 0, UnitName = 2, UnitThreat = 7, ErrorLine = 41,
                DisabledLine = 42, UnitLevel = 47, UnitType = 48, UnitDead = 49 } },
        ELITE = "Elite", NORMAL_FONT_COLOR = { r = 1, g = 0.82, b = 0 },
        HIGHLIGHT_FONT_COLOR = { r = 1, g = 1, b = 1 },
        TOOLTIP_UNIT_LEVEL = "Level %s",
        TOOLTIP_UNIT_LEVEL_RACE = "Level %s %s",
        TOOLTIP_UNIT_LEVEL_TYPE = "Level %s (%s)",
        TOOLTIP_UNIT_LEVEL_RACE_TYPE = "Level %s %s (%s)",
        format = string.format,
        _GameTooltip = f.tooltip,
        _enabled = function() return f.enabled end,
        _ttUsable = function() return f.usable end,
        _isSecret = function(value) return value == secret end,
        canaccesstable = function(value)
            if f.watchedRow and value == f.watchedRow then
                f.watchedRowChecks = f.watchedRowChecks + 1
            end
            return type(value) == "table" and value ~= secret and not inaccessible[value]
        end,
        canaccessallvalues = function(...)
            for i = 1, select("#", ...) do
                if select(i, ...) == secret then return false end
            end
            return true
        end,
        _resolveTipIdentity = function()
            f.identityCalls = f.identityCalls + 1
            if f.identityError then error("restricted identity") end
            if f.identityUnit ~= nil then return "Creature-1", f.identityUnit end
            return "Creature-1", not f.noUnit and "mouseover" or nil
        end,
        UnitExists = function(unit)
            f.existsCalls = f.existsCalls + 1
            f.lastExistsUnit = unit
            if f.existsError then error("restricted existence") end
            if f.existsResult ~= nil then return f.existsResult end
            return type(unit) == "string" and unit ~= ""
        end,
        UnitClassification = function(unit)
            f.classificationCalls = f.classificationCalls + 1
            f.lastClassificationUnit = unit
            if f.classificationError then error("restricted classification") end
            return f.classifications and f.classifications[unit] or f.classification
        end,
        UnitEffectiveLevel = function(unit)
            f.levelCalls = f.levelCalls + 1
            f.lastLevelUnit = unit
            if f.levelError then error("restricted effective level") end
            return f.levels and f.levels[unit] or f.level
        end,
        UnitLevel = function() error("use effective level, not actual level") end,
        UnitIsDead = function() return f.dead == true end,
        UnitIsDeadOrGhost = function() return f.dead == true end,
        GameTooltip_AddColoredLine = function(tt, text, color, wrap, offset)
            if f.renderError then error("restricted widget") end
            tt.rendered[#tt.rendered + 1] = { leftText = text, leftColor = color,
                wrapText = wrap, leftOffset = offset }
        end,
        TooltipDataProcessor = {
            AllTypes = "all",
            AddTooltipPreCall = function(kind, callback)
                Check(kind == 2 and not f.pre, "register exactly one unit pre-call")
                f.pre = callback
                f.registrations = f.registrations + 1
            end,
            AddLinePreCall = function(kind, callback)
                Check((kind == 0 or kind == 47) and not f.lineCallbacks[kind],
                    "register each supported level line type once")
                f.lineCallbacks[kind] = callback
                f.registrations = f.registrations + 1
            end,
        },
    }, { __index = _G })
    f.env = env
    setfenv(assert(loadstring(production, "@" .. path)), env)()
    f.apply = env.EllesmereUI._applyTooltipUnitDetails
    function f:Render(data, tooltip)
        tooltip = tooltip or self.tooltip
        tooltip.rendered = {}
        local before = Copy(data)
        if self.pre then self.pre(tooltip, data) end
        if data and data.lines then
            for _, line in ipairs(data.lines) do
                local callback = self.lineCallbacks[line.type]
                if callback then self.lineCalls = self.lineCalls + 1 end
                if not (callback and callback(tooltip, line)) then
                    tooltip.rendered[#tooltip.rendered + 1] = line
                end
            end
        end
        Check(Same(data, before), "callbacks must not mutate Blizzard tooltip data")
        return tooltip.rendered
    end
    return f
end

local function CreatureData(text)
    return { guid = "Creature-1", lines = {
        { type = 2, leftText = "Deviate Coiler" },
        { type = 0, leftText = text or "Level 15 (Elite)" },
        { type = 0, leftText = "Beast" },
    } }
end
local function Unchanged(f, data, message, tooltip)
    local rendered = f:Render(data, tooltip)
    Check(Same(rendered, data.lines), message)
end

local f = Fixture()
f.apply()
f.apply()
Check(f.registrations == 0 and f.identityCalls == 0, "disabled setting must install nothing")
f.settings.tooltipShowRarity = true
f.enabled = false
f.apply()
Check(f.registrations == 0, "master disabled must install nothing")
f.enabled = true
f.standDown = true
f.apply()
Check(f.registrations == 0, "skin stand-down must install nothing")
f.standDown = false
f.apply()
f.apply()
Check(f.registrations == 3, "first enable installs callbacks once")
Check(f.lineCallbacks[0] == f.lineCallbacks[47], "supported line types share one callback")

local data, rendered
for _, case in ipairs({
    { "rare", "Level 15", "Level 15 (Rare)" },
    { "rare", "Level 15 (Elite)", "Level 15 (Rare)" },
    { "rareelite", "Level 15 (Elite)", "Level 15 (Rare Elite)" },
    { "rareelite", "Level 15 (Rare)", "Level 15 (Rare Elite)" },
    { "rareelite", "Level 15", "Level 15 (Rare Elite)" },
    { "rare", "Level 15 (Rare)", "Level 15 (Rare)" },
    { "rareelite", "Level 15 (Rare Elite)", "Level 15 (Rare Elite)" },
    { "rareelite", "Level 15 (elite)", "Level 15 (Rare Elite)" },
}) do
    f.classification = case[1]
    data = CreatureData(case[2])
    rendered = f:Render(data)
    Check(#rendered == 3 and rendered[2].leftText == case[3], "render " .. case[1] .. " classification")
    Check(Same(f:Render(data), rendered), "repeat rarity render without duplication")
end

data = CreatureData()
data.lines[2].type = 47
rendered = f:Render(data)
Check(#rendered == 3 and rendered[2].leftText == "Level 15 (Rare Elite)", "typed creature level shows rare elite")
data = CreatureData("|cffffff00Level 15|r (Elite)")
data.lines[2].leftColor = { r = 1, g = 1, b = 0 }
data.lines[2].wrapText = true
data.lines[2].leftOffset = 3
data.lines[2].rightText = ""
table.insert(data.lines, 2, { type = 0, leftText = "<Guild Name>" })
table.insert(data.lines, { type = 0, leftText = "Targeting:", rightText = "You" })
rendered = f:Render(data)
Check(#rendered == 5 and rendered[3].leftText == "|cffffff00Level 15|r (Rare Elite)", "retain level formatting")
Check(rendered[3].leftColor == data.lines[3].leftColor and rendered[3].wrapText == true
    and rendered[3].leftOffset == 3, "preserve level color, wrapping and offset")
Check(rendered[2].leftText == "<Guild Name>" and rendered[4].leftText == "Beast"
    and rendered[5].rightText == "You", "preserve surrounding lines and targeting")

for _, case in ipairs({
    { "Level %1$s (%2$s)", "Level 15 (Elite)", "Level 15 (Rare Elite)" },
    { "%s - (%s)", "15 - (Elite)", "15 - (Rare Elite)" },
    { "Level.%s [%s]", "Level.15 [Beast]", "Level.15 [Beast] (Rare Elite)" },
}) do
    local localized = Fixture()
    localized.env.TOOLTIP_UNIT_LEVEL_TYPE = case[1]
    localized.settings.tooltipShowRarity = true
    localized.classification = "rareelite"
    localized.apply()
    rendered = localized:Render(CreatureData(case[2]))
    Check(#rendered == 3 and rendered[2].leftText == case[3], "recognize localized level format " .. case[1])
end
for _, classification in ipairs({ "normal", "elite", "worldboss", "minus" }) do
    f.classification = classification
    Unchanged(f, CreatureData(), classification .. " must remain unchanged")
end
for _, classification in ipairs({ "normal", "elite", "worldboss", "minus", secret }) do
    local ordinary = Fixture()
    ordinary.settings.tooltipShowRarity = true
    ordinary.classification = classification
    ordinary.apply()
    local d = CreatureData()
    d.lines[1].unitToken = "nameplate7"
    ordinary.watchedRow = d.lines[2]
    Unchanged(ordinary, d, "non-rare or restricted classification preserves all rows")
    Check(ordinary.classificationCalls == 1 and ordinary.watchedRowChecks == 0,
        "classification rejects non-rare or restricted units before scanning level rows")
end
local scoped = Fixture()
scoped.settings.tooltipShowRarity = true
scoped.classification = "rareelite"
scoped.apply()
local scopedData = CreatureData()
scopedData.lines[3].type = 48
table.insert(scopedData.lines, { type = 7, leftText = "Threat" })
table.insert(scopedData.lines, { type = 41, leftText = "Skinnable" })
scoped:Render(scopedData)
Check(scoped.lineCalls == 1, "name, creature type, threat and error rows do not invoke our callback")
f.classification = "rareelite"
for _, case in ipairs({
    { "right-side level content", function(d) d.lines[2].rightText = "Useful content" end },
    { "missing level type", function(d) d.lines[2].type = nil end },
    { "unrelated generic text", function(d) d.lines[2].leftText = "Current focus (Elite)" end },
    { "missing level line", function(d) table.remove(d.lines, 2) end },
}) do
    data = CreatureData()
    case[2](data)
    Unchanged(f, data, case[1] .. " must leave original lines intact")
end
f.enabled = false
local calls = f.identityCalls
Unchanged(f, CreatureData(), "master disabled leaves original lines intact")
Check(f.identityCalls == calls, "master disabled must not resolve unit identity")
f.enabled = true
f.settings.tooltipShowRarity = false
Unchanged(f, CreatureData(), "disabled after installation leaves original lines intact")
Check(f.identityCalls == calls, "disabled setting must not resolve unit identity")
f.settings.tooltipShowRarity = true
f.apply()
Check(f.registrations == 3, "re-enabling must reuse existing callbacks")

for _, flag in ipairs({ "forbidden", "noUnit", "identityError", "renderError" }) do
    f[flag] = true
    Unchanged(f, CreatureData(), flag .. " leaves original lines intact")
    f[flag] = false
end
f.usable = false
Unchanged(f, CreatureData(), "unusable tooltip leaves original lines intact")
f.usable = true
local other = { IsForbidden = function() return false end }
Unchanged(f, CreatureData(), "other tooltip must remain unchanged", other)

for _, field in ipairs({ "type", "rightText", "leftColor", "wrapText", "leftOffset" }) do
    data = CreatureData()
    data.lines[2][field] = secret
    Unchanged(f, data, "secret level " .. field .. " leaves original lines intact")
end
for _, part in ipairs({ "data", "lines", "level" }) do
    data = CreatureData()
    local restricted = part == "data" and data or part == "lines" and data.lines or data.lines[2]
    inaccessible[restricted] = true
    Unchanged(f, data, "inaccessible " .. part .. " leaves original lines intact")
    inaccessible[restricted] = nil
end
f.classification = secret
Unchanged(f, CreatureData(), "secret classification leaves original lines intact")
f.classification = "rareelite"
f:Render(nil)
Check(#f.tooltip.rendered == 0, "missing tooltip data is safe")
Check(not f.lineCallbacks[0](f.tooltip, secret), "secret line callback must be ignored")

local function SecretLevelFixture(token)
    local fixture = Fixture()
    fixture.classification = "rareelite"
    fixture.settings.tooltipShowRarity = true
    fixture.noUnit = true
    fixture.apply()
    local tooltipData = CreatureData()
    tooltipData.guid = secret
    tooltipData.lines[1].leftText = secret
    tooltipData.lines[1].unitToken = token
    tooltipData.lines[2].type = 47
    tooltipData.lines[2].leftText = secret
    return fixture, tooltipData
end

for _, case in ipairs({ { "rare", "Rare" }, { "rareelite", "Rare Elite" } }) do
    local exact, d = SecretLevelFixture("nameplate7")
    exact.classification = case[1]
    exact.level = 31
    local result = exact:Render(d)
    Check(#result == 3 and result[2].leftText == "Level 31 (" .. case[2] .. ")",
        "typed secret level rebuilds " .. case[1] .. " from public unit data")
    Check(result[1] == d.lines[1] and result[3] == d.lines[3],
        "rebuilding retains secret name and unrelated lines")
    Check(exact.lastClassificationUnit == "nameplate7" and exact.lastLevelUnit == "nameplate7",
        "exact UnitName token resolves despite a secret GUID")
    Check(exact.identityCalls == 0, "exact UnitName token avoids identity fallback")
end

local exact, d = SecretLevelFixture("nameplate7")
exact.classifications = { nameplate7 = "rareelite", target = "elite", mouseover = "normal" }
exact.levels = { nameplate7 = 31, target = 80, mouseover = 70 }
exact.noUnit = false
d.lines[2].leftColor = { r = 1, g = 0.5, b = 0 }
d.lines[2].wrapText = true
d.lines[2].leftOffset = 4
local result = exact:Render(d)
Check(result[2].leftText == "Level 31 (Rare Elite)", "hovered unit differs from current target")
Check(result[2].leftColor == d.lines[2].leftColor and result[2].wrapText == true
    and result[2].leftOffset == 4, "rebuilt level preserves public render metadata")
Check(exact.identityCalls == 0, "exact token takes precedence over legacy identity")
table.insert(d.lines, 1, { type = 0, leftText = "Useful heading" })
result = exact:Render(d)
Check(result[3].leftText == "Level 31 (Rare Elite)", "UnitName token may occur after the first line")

local processing, pd = SecretLevelFixture(nil)
processing.level = 42
processing.processingInfo = { getterName = "GetUnit", getterArgs = { "focus" }, tooltipData = pd }
result = processing:Render(pd)
Check(result[2].leftText == "Level 42 (Rare Elite)" and processing.lastLevelUnit == "focus",
    "matching processing GetUnit resolves the exact unit with secret GUID")
Check(processing.identityCalls == 0, "valid processing token avoids legacy fallback")

for _, case in ipairs({
    { "secret token", secret }, { "empty token", "" }, { "numeric token", 4 },
    { "table token", {} }, { "missing token", nil },
}) do
    local invalid, id = SecretLevelFixture(case[2])
    Unchanged(invalid, id, case[1] .. " cannot rebuild secret level")
    Check(invalid.classificationCalls == 0 and invalid.levelCalls == 0,
        case[1] .. " must not reach unit data APIs")
end

for _, case in ipairs({
    { "secret existence", function(g) g.existsResult = secret end },
    { "nonexistent unit", function(g) g.existsResult = false end },
    { "nonboolean existence", function(g) g.existsResult = 1 end },
    { "existence error", function(g) g.existsError = true end },
    { "secret name line type", function(g, td) td.lines[1].type = secret end },
    { "non-name token", function(g, td) td.lines[1].type = 0 end },
    { "inaccessible name line", function(g, td) inaccessible[td.lines[1]] = true end },
}) do
    local invalid, id = SecretLevelFixture("nameplate7")
    case[2](invalid, id)
    Unchanged(invalid, id, case[1] .. " cannot authorize a rebuild")
    Check(invalid.classificationCalls == 0 and invalid.levelCalls == 0,
        case[1] .. " must not read unit classification or level")
    inaccessible[id.lines[1]] = nil
end

for _, case in ipairs({
    { "different tooltip data", function(info) info.tooltipData = CreatureData() end },
    { "secret tooltip data", function(info) info.tooltipData = secret end },
    { "different getter", function(info) info.getterName = "GetItemByID" end },
    { "secret getter", function(info) info.getterName = secret end },
    { "overridden getter", function(info) info.getterFunction = function() end end },
    { "secret getter function", function(info) info.getterFunction = secret end },
    { "secret arguments", function(info) info.getterArgs = secret end },
    { "missing arguments", function(info) info.getterArgs = nil end },
    { "secret argument token", function(info) info.getterArgs[1] = secret end },
    { "missing argument token", function(info) info.getterArgs[1] = nil end },
    { "inaccessible arguments", function(info) inaccessible[info.getterArgs] = true end },
    { "inaccessible processing info", function(info) inaccessible[info] = true end },
}) do
    local invalid, id = SecretLevelFixture(nil)
    local info = { getterName = "GetUnit", getterArgs = { "focus" }, tooltipData = id }
    invalid.processingInfo = info
    case[2](info)
    Unchanged(invalid, id, case[1] .. " must not select an unrelated unit")
    Check(invalid.classificationCalls == 0 and invalid.levelCalls == 0,
        case[1] .. " must not reach unit data APIs")
    inaccessible[info] = nil
    if type(info.getterArgs) == "table" then inaccessible[info.getterArgs] = nil end
end

local fallback, fd = SecretLevelFixture(nil)
fallback.noUnit = false
fallback.level = 32
result = fallback:Render(fd)
Check(result[2].leftText == "Level 32 (Rare Elite)" and fallback.lastLevelUnit == "mouseover",
    "existing identity resolution remains the final public token fallback")
for _, token in ipairs({ secret, "", 7, {} }) do
    local invalid, id = SecretLevelFixture(nil)
    invalid.identityUnit = token
    Unchanged(invalid, id, "invalid legacy identity token leaves the secret line intact")
    Check(invalid.classificationCalls == 0 and invalid.levelCalls == 0,
        "invalid legacy identity token must not reach unit data APIs")
end

for _, case in ipairs({
    { "missing level", nil }, { "secret level", secret }, { "boss level", -1 },
    { "zero level", 0 }, { "negative level", -5 }, { "text level", "31" },
    { "boolean level", true },
}) do
    local invalid, id = SecretLevelFixture("nameplate7")
    invalid.level = case[2]
    Unchanged(invalid, id, case[1] .. " leaves Blizzard's level untouched")
end

for _, case in ipairs({
    { "effective level error", function(g) g.levelError = true end },
    { "classification error", function(g) g.classificationError = true end },
    { "secret classification", function(g) g.classification = secret end },
    { "render error", function(g) g.renderError = true end },
    { "untyped secret text", function(g, td) td.lines[2].type = nil end },
    { "right-side content", function(g, td) td.lines[2].rightText = "Useful content" end },
}) do
    local invalid, id = SecretLevelFixture("nameplate7")
    case[2](invalid, id)
    Unchanged(invalid, id, case[1] .. " leaves secret level intact")
end
for _, field in ipairs({ "type", "rightText", "wrapText", "leftOffset" }) do
    local invalid, id = SecretLevelFixture("nameplate7")
    id.lines[2][field] = secret
    Unchanged(invalid, id, "secret " .. field .. " cannot be reused during level rebuild")
end
local secretColor, cd = SecretLevelFixture("nameplate7")
cd.lines[2].leftColor = secret
result = secretColor:Render(cd)
Check(result[2].leftText == "Level 15 (Rare Elite)"
    and result[2].leftColor == secretColor.env.HIGHLIGHT_FONT_COLOR,
    "secret color uses white only for a line rebuilt entirely from public data")

local localized, ld = SecretLevelFixture("nameplate7")
localized.level = 31
localized.env.TOOLTIP_UNIT_LEVEL_TYPE = "Niveau %s [%s]"
localized.env.EllesmereUI.L = function(text) return text == "Rare Elite" and "Elite rare" or text end
result = localized:Render(ld)
Check(result[2].leftText == "Niveau 31 [Elite rare]", "rebuild uses localized level format and rarity label")

local disabled, dd = SecretLevelFixture("nameplate7")
disabled.settings.tooltipShowRarity = false
Unchanged(disabled, dd, "disabled feature keeps typed secret level")
Check(disabled.processingCalls == 0 and disabled.existsCalls == 0 and disabled.identityCalls == 0
    and disabled.classificationCalls == 0 and disabled.levelCalls == 0,
    "disabled callbacks perform no identity, classification or effective-level lookups")

local function CoreRowsFixture(subtitle, corpse)
    local fixture, tooltipData = SecretLevelFixture(secret)
    fixture.level = 31
    fixture.dead = corpse
    tooltipData.lines[1].leftColor = secret
    tooltipData.lines[2].type = 0
    tooltipData.lines[2].leftColor = secret
    tooltipData.lines[3].leftText = corpse and "Corpse" or secret
    if subtitle then table.insert(tooltipData.lines, 2, { type = 0, leftText = secret }) end
    fixture.processingInfo = { getterName = "GetUnit", getterArgs = { "target" }, tooltipData = tooltipData }
    return fixture, tooltipData
end

for _, classification in ipairs({ "rare", "rareelite" }) do
    for _, subtitle in ipairs({ false, true }) do
        for _, corpse in ipairs({ false, true }) do
            for _, extras in ipairs({ {}, { 7 }, { 41 }, { 7, 41 }, { 8, 42, 43 } }) do
                local core, td = CoreRowsFixture(subtitle, corpse)
                core.classification = classification
                local levelIndex = subtitle and 3 or 2
                local originalLevel = td.lines[levelIndex]
                for _, lineType in ipairs(extras) do
                    table.insert(td.lines, { type = lineType, leftText = secret, leftColor = secret })
                end
                local output = core:Render(td)
                local label = classification == "rare" and "Rare" or "Rare Elite"
                Check(#output == #td.lines and output[levelIndex].leftText == "Level 31 (" .. label .. ")",
                    "generic row count selects level with optional subtitle, corpse and typed extras")
                Check(output[levelIndex].leftColor == core.env.HIGHLIGHT_FONT_COLOR,
                    "generic secret level rebuild uses white")
                for i, line in ipairs(td.lines) do
                    if line ~= originalLevel then
                        Check(output[i] == line, "all other core and ignored rows keep their original data")
                    end
                end
            end
        end
    end
end

for _, terminalType in ipairs({ 48, 49 }) do
    local mixed, mixedData = CoreRowsFixture(true, terminalType == 49)
    mixedData.lines[4].type = terminalType
    Unchanged(mixed, mixedData, "typed terminal unit row makes generic subtitle/level ordering ambiguous")
    mixedData.lines[3].type = 47
    local output = mixed:Render(mixedData)
    Check(output[3].leftText == "Level 31 (Rare Elite)" and #output == #mixedData.lines,
        "explicit UnitLevel still works beside typed UnitType or UnitDead")
    Check(output[1] == mixedData.lines[1] and output[2] == mixedData.lines[2]
        and output[4] == mixedData.lines[4], "typed level preserves subtitle and terminal unit row")
end

local interleaved, interleavedData = CoreRowsFixture(true, true)
table.insert(interleavedData.lines, 1, { type = 7, leftText = secret })
table.insert(interleavedData.lines, 4, { type = 41, leftText = secret, leftColor = secret })
table.insert(interleavedData.lines, { type = 7, leftText = secret })
result = interleaved:Render(interleavedData)
Check(#result == 7 and result[5].leftText == "Level 31 (Rare Elite)",
    "ignored rows may be interleaved without shifting the chosen core level row")
for _, i in ipairs({ 1, 2, 3, 4, 6, 7 }) do
    Check(result[i] == interleavedData.lines[i], "interleaved ignored and surrounding rows remain intact")
end

for _, case in ipairs({
    { "two core rows", function(td) table.remove(td.lines) end },
    { "five core rows", function(td)
        table.insert(td.lines, { type = 0, leftText = secret })
        table.insert(td.lines, { type = 0, leftText = secret })
    end },
    { "typed unit row", function(td) td.lines[3].type = 48 end },
    { "missing name marker", function(td) td.lines[1].type = 0 end },
    { "extra name marker", function(td) td.lines[3].type = 2 end },
    { "secret name type", function(td) td.lines[1].type = secret end },
    { "secret core type", function(td) td.lines[3].type = secret end },
    { "secret ignored type", function(td) table.insert(td.lines, { type = secret, leftText = secret }) end },
    { "missing core type", function(td) td.lines[3].type = nil end },
    { "nonnumeric type", function(td) td.lines[3].type = "0" end },
    { "generic row before name", function(td)
        local name = table.remove(td.lines, 1)
        table.insert(td.lines, 2, name)
    end },
    { "inaccessible core row", function(td) inaccessible[td.lines[3]] = true end },
}) do
    local invalid, td = CoreRowsFixture(false, false)
    case[2](td)
    Unchanged(invalid, td, case[1] .. " does not guess a secret level row")
    for _, line in ipairs(td.lines) do inaccessible[line] = nil end
end

for _, classification in ipairs({ "normal", "elite", "worldboss", "minus", secret }) do
    local invalid, td = CoreRowsFixture(false, false)
    invalid.classification = classification
    Unchanged(invalid, td, "only public rare or rareelite classification permits row-count fallback")
end

for _, field in ipairs({ "rightText", "wrapText", "leftOffset" }) do
    local invalid, td = CoreRowsFixture(false, false)
    td.lines[2][field] = secret
    Unchanged(invalid, td, "secret generic level " .. field .. " cannot be reused")
end

local genericLocalized, genericData = CoreRowsFixture(false, false)
genericLocalized.env.TOOLTIP_UNIT_LEVEL_TYPE = "Niveau %s [%s]"
genericLocalized.env.EllesmereUI.L = function(text) return text == "Rare Elite" and "Elite rare" or text end
result = genericLocalized:Render(genericData)
Check(result[2].leftText == "Niveau 31 [Elite rare]", "row-count rebuild uses localized format and label")
genericData.lines[2].leftText = "Useful unrelated text"
Unchanged(genericLocalized, genericData, "row-count fallback never replaces a readable non-level row")
genericData.lines[2].leftText = secret
genericLocalized.settings.tooltipShowRarity = false
local beforeCalls = genericLocalized.processingCalls + genericLocalized.classificationCalls + genericLocalized.levelCalls
Unchanged(genericLocalized, genericData, "disabling setting clears the pending generic level replacement")
Check(beforeCalls == genericLocalized.processingCalls + genericLocalized.classificationCalls + genericLocalized.levelCalls,
    "disabled generic fallback performs no unit lookups")

local function WorldCursorFixture(subtitle, corpse)
    local fixture, tooltipData = CoreRowsFixture(subtitle, corpse)
    fixture.processingInfo = { getterName = "GetWorldCursor", getterArgs = {},
        tooltipData = tooltipData, append = false }
    return fixture, tooltipData
end

for _, subtitle in ipairs({ false, true }) do
    local world, wd = WorldCursorFixture(subtitle, false)
    world.classifications = { mouseover = "rareelite", target = "normal" }
    world.levels = { mouseover = 31, target = 80 }
    local output = world:Render(wd)
    local levelIndex = subtitle and 3 or 2
    Check(output[levelIndex].leftText == "Level 31 (Rare Elite)",
        "current world-cursor tooltip resolves mouseover despite secret GUID and name token")
    Check(world.lastClassificationUnit == "mouseover" and world.lastLevelUnit == "mouseover",
        "world-cursor rebuild uses mouseover rather than a different current target")
    Check(world.identityCalls == 1, "world-cursor fallback first attempts existing identity resolution")
    world.classifications.mouseover = "normal"
    Unchanged(world, wd, "changing world mouseover to normal clears the prior rare elite replacement")
    world.classifications.mouseover = "rare"
    world.levels.mouseover = 26
    output = world:Render(wd)
    Check(output[levelIndex].leftText == "Level 26 (Rare)",
        "world-cursor updates use the current classification and effective level")
    world.dead = true
    wd.lines[#wd.lines].leftText = "Corpse"
    table.insert(wd.lines, { type = 41, leftText = secret })
    output = world:Render(wd)
    Check(output[levelIndex].leftText == "Level 26 (Rare)"
        and output[#output - 1].leftText == "Corpse" and output[#output] == wd.lines[#wd.lines],
        "dead world mouseover retains corpse and skinnable rows")
    world.existsResult = false
    Unchanged(world, wd, "losing world mouseover clears any prior replacement")
end

local omittedAppend, omittedAppendData = WorldCursorFixture(false, false)
omittedAppend.processingInfo.append = nil
omittedAppend.processingInfo.getterArgs = nil
local omittedAppendOutput = omittedAppend:Render(omittedAppendData)
Check(omittedAppendOutput[2].leftText == "Level 31 (Rare Elite)",
    "stock world-cursor metadata may omit append and getter arguments")

local legacyWorld, legacyWorldData = WorldCursorFixture(false, false)
legacyWorld.identityUnit = "focus"
legacyWorld.classifications = { focus = "rareelite", mouseover = "normal" }
legacyWorld.levels = { focus = 44, mouseover = 12 }
local legacyWorldOutput = legacyWorld:Render(legacyWorldData)
Check(legacyWorldOutput[2].leftText == "Level 44 (Rare Elite)"
    and legacyWorld.lastClassificationUnit == "focus" and legacyWorld.lastLevelUnit == "focus",
    "resolved tooltip identity takes priority over ambient world mouseover")

local restrictedIdentity, restrictedIdentityData = WorldCursorFixture(false, false)
restrictedIdentity.identityError = true
local restrictedIdentityOutput = restrictedIdentity:Render(restrictedIdentityData)
Check(restrictedIdentityOutput[2].leftText == "Level 31 (Rare Elite)"
    and restrictedIdentity.lastLevelUnit == "mouseover",
    "restricted legacy identity can fall back to validated current world mouseover")

local worldName, worldNameData = WorldCursorFixture(false, false)
worldNameData.lines[1].unitToken = "nameplate7"
worldName.classifications = { nameplate7 = "rareelite", mouseover = "normal" }
worldName.levels = { nameplate7 = 45, mouseover = 12 }
local worldNameOutput = worldName:Render(worldNameData)
Check(worldNameOutput[2].leftText == "Level 45 (Rare Elite)"
    and worldName.lastClassificationUnit == "nameplate7" and worldName.lastLevelUnit == "nameplate7",
    "readable name token remains authoritative over world-cursor mouseover fallback")

for _, case in ipairs({
    { "different processing data", function(g, info) info.tooltipData = CreatureData() end },
    { "secret processing data", function(g, info) info.tooltipData = secret end },
    { "different getter", function(g, info) info.getterName = "GetItemByID" end },
    { "secret getter", function(g, info) info.getterName = secret end },
    { "custom getter", function(g, info) info.getterFunction = function() end end },
    { "secret custom getter", function(g, info) info.getterFunction = secret end },
    { "appended tooltip", function(g, info) info.append = true end },
    { "secret append flag", function(g, info) info.append = secret end },
    { "inaccessible processing info", function(g, info) inaccessible[info] = true end },
    { "processing error", function(g) g.processingError = true end },
    { "missing mouseover", function(g) g.existsResult = false end },
    { "secret mouseover existence", function(g) g.existsResult = secret end },
    { "nonboolean mouseover existence", function(g) g.existsResult = 1 end },
    { "mouseover existence error", function(g) g.existsError = true end },
}) do
    local invalid, wd = WorldCursorFixture(false, false)
    case[2](invalid, invalid.processingInfo)
    Unchanged(invalid, wd, case[1] .. " cannot authorize world mouseover reconstruction")
    Check(invalid.classificationCalls == 0 and invalid.levelCalls == 0,
        case[1] .. " must not reach unit classification or level APIs")
    inaccessible[invalid.processingInfo] = nil
end

for _, case in ipairs({ { "missing level", nil }, { "secret level", secret }, { "unknown level", -1 } }) do
    local invalid, wd = WorldCursorFixture(false, false)
    invalid.level = case[2]
    Unchanged(invalid, wd, "world cursor " .. case[1] .. " preserves the original tooltip")
end

print("PASS: tooltip unit details (" .. checks .. " assertions)")
