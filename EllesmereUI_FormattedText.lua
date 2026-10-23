if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
local EUI = EllesmereUI
local FT = {}
EUI.FormattedText = FT

local registry, aliases, ordered = {}, {}, {}
local cache, cacheCount = {}, 0
local MAX_LENGTH, MAX_TAGS, CACHE_LIMIT = 4096, 64, 128
local VALUE_FORMATS = { ["%s"] = true, ["%s%%"] = true, ["%d"] = true,
    ["%.0f"] = true, ["%.1f"] = true, ["%.2f"] = true, ["%.3f"] = true }
local plans = setmetatable({}, { __mode = "k" })
local internals = { plans = plans }
FT._internal = internals
FT.MAX_PRECISION = 9
local textTag = { id = "text", literal = true, syntax = "[:text:words:]",
    description = EllesmereUI.L("Your own text, with optional color and opacity"),
    aliases = {}, modifiers = {}, modifierNames = {}, modifierDescriptions = {}, variants = {} }

-- Owner-provided printf layouts share the renderer without turning live values
-- into templates. Only configuration/layout code supplies these format strings.
local nativeCache, nativeCount = {}, 0
function FT:CompileFormat(format)
    assert(type(format) == "string" and #format <= MAX_LENGTH, "invalid owner text format")
    if nativeCache[format] then return nativeCache[format] end
    local data = { nodes = {}, runs = {}, dependencies = {}, tags = {}, issues = {},
        identity = false, width = 0, literals = 0, format = format, native = true }
    local position, literal = 1, {}
    local function Flush()
        if #literal == 0 then return end
        local value = table.concat(literal)
        data.runs[#data.runs + 1] = { literal = value, escaped = value }
        literal = {}
    end
    while position <= #format do
        local first = format:find("%", position, true)
        if not first then literal[#literal + 1] = format:sub(position); break end
        literal[#literal + 1] = format:sub(position, first - 1)
        if format:sub(first + 1, first + 1) == "%" then
            literal[#literal + 1] = "%"
            position = first + 2
        else
            local spec = format:sub(first):match("^%%[-+ #0]*%d*%.?%d*[cdiouxXeEfgGqs]")
            assert(spec, "invalid owner text placeholder")
            Flush()
            local node = { index = #data.nodes + 1, variant = { format = spec, dependencies = {} } }
            data.nodes[#data.nodes + 1] = node
            data.runs[#data.runs + 1] = node
            position = first + #spec
        end
    end
    Flush()
    local plan = {}
    plans[plan] = data
    if nativeCount >= CACHE_LIMIT then nativeCache, nativeCount = {}, 0 end
    nativeCache[format], nativeCount = plan, nativeCount + 1
    return plan
end

local function CopyList(src)
    local out = {}
    for i = 1, #(src or {}) do out[i] = src[i] end
    return out
end

local function Identifier(s)
    return type(s) == "string" and s:match("^[a-z][a-z0-9_.-]*$") ~= nil
end

local function Literal(s)
    return (s:gsub("%%", "%%%%"):gsub("|", "||"))
end

-- Registration is transactional: a rejected definition never changes the registry.
function FT:RegisterTag(id, spec)
    assert(Identifier(id) and type(spec) == "table", "invalid formatted-text tag")
    assert(spec.aliases == nil or type(spec.aliases) == "table", "tag aliases must be a list")
    assert(spec.modifiers == nil or type(spec.modifiers) == "table", "tag modifiers must be a table")
    assert(type(spec.variants) == "table", "tag variants required")
    local names = { id }
    for i = 1, #(spec.aliases or {}) do names[#names + 1] = spec.aliases[i] end
    local seen = {}
    for i = 1, #names do
        local name = names[i]
        assert(Identifier(name) and name ~= textTag.id and not aliases[(spec.context or "") .. "\0" .. name] and not seen[name],
            "duplicate or invalid tag: " .. tostring(name))
        seen[name] = true
    end
    assert(Identifier(spec.context) and type(spec.description) == "string", "tag context and description required")
    local def = { id = id, context = spec.context, description = spec.description,
        aliases = CopyList(spec.aliases), modifiers = {}, modifierNames = {}, modifierDescriptions = {}, variants = {} }
    for key, list in pairs(spec.modifiers or {}) do
        assert(Identifier(key) and type(list) == "table", "invalid modifier or alias list")
        local mods = { key }
        for i = 1, #list do mods[#mods + 1] = list[i] end
        for i = 1, #mods do
            local name = mods[i]
            assert(Identifier(name) and not def.modifiers[name], "duplicate or invalid modifier")
            def.modifiers[name] = key
        end
        def.modifierNames[#def.modifierNames + 1] = key
    end
    table.sort(def.modifierNames)
    for key, description in pairs(spec.modifierDescriptions or {}) do
        assert(def.modifiers[key] == key and type(description) == "string", "invalid modifier description")
        def.modifierDescriptions[key] = description
    end
    for key, v in pairs(spec.variants or {}) do
        assert(type(key) == "string" and type(v) == "table" and type(v.read) == "function", "tag variant reader required")
        local parts = {}
        for mod in key:gmatch("[^:]+") do
            assert(def.modifiers[mod] == mod, "variant uses a noncanonical modifier")
            parts[#parts + 1] = mod
        end
        table.sort(parts)
        assert(table.concat(parts, ":") == key, "variant modifiers must be sorted and unique")
        for i = 2, #parts do assert(parts[i] ~= parts[i - 1], "duplicate variant modifier") end
        assert(v.format == nil or VALUE_FORMATS[v.format], "invalid variant format")
        assert(v.bind == nil or type(v.bind) == "function", "invalid native text binding")
        assert(v.numeric == nil or type(v.numeric) == "boolean", "numeric must be a boolean")
        assert(v.abbreviated == nil or type(v.abbreviated) == "boolean", "abbreviated must be a boolean")
        assert(not v.numeric or not v.bind, "numeric tags must supply raw numbers, not native text bindings")
        assert(not v.numeric or v.format == nil or v.format == "%s", "numeric tags use shared number formatting")
        assert(not v.abbreviated or v.numeric, "abbreviated variants must be numeric")
        assert(type(v.preview) == "string", "tag preview required")
        assert(v.readerKey == nil or (type(v.readerKey) == "string" and Identifier(v.readerKey:lower())), "invalid reader key")
        assert(v.uncoloredReaderKey == nil or (type(v.uncoloredReaderKey) == "string"
            and Identifier(v.uncoloredReaderKey:lower())), "invalid uncolored reader key")
        assert(v.sampleKey == nil or type(v.sampleKey) == "string", "invalid preview sample key")
        assert(v.width == nil or (type(v.width) == "number" and v.width >= 0 and v.width < 4096),
            "invalid preview width")
        assert(v.dependencies == nil or type(v.dependencies) == "table", "dependencies must be a list")
        local deps = {}
        for i = 1, #(v.dependencies or {}) do
            assert(Identifier(v.dependencies[i]), "invalid dependency")
            deps[v.dependencies[i]] = true
        end
        def.variants[key] = { read = v.read, bind = v.bind, readerKey = v.readerKey, uncoloredReaderKey = v.uncoloredReaderKey,
            format = v.format or "%s",
            numeric = v.numeric == true, abbreviated = v.abbreviated == true,
            preview = v.preview, sampleKey = v.sampleKey, dependencies = deps,
            width = v.width or #v.preview * 5, identity = v.identity == true }
    end
    assert(def.variants[""], "tag needs a default variant")
    local key = spec.context .. "\0" .. id
    registry[key] = def
    ordered[#ordered + 1] = key
    for i = 1, #names do aliases[spec.context .. "\0" .. names[i]] = key end
    cache, cacheCount = {}, 0
end

local function ParseTag(body, context)
    local fields = {}
    for field in (body .. ":"):gmatch("(.-):") do fields[#fields + 1] = field end
    local name = (fields[1] or ""):lower()
    local key = aliases[context .. "\0" .. name]
    local def = name == textTag.id and textTag or key and registry[key]
    if not def then return nil, "unknown-tag" end
    local mods, used, color, alpha, precision = {}, {}
    local i = 2
    if def.literal then
        if fields[2] == nil then return nil, "missing-text" end
        i = 3
    end
    while i <= #fields do
        local field = fields[i]:lower()
        if field:sub(1, 1) == "#" then
            if not field:match("^#%x%x%x%x%x%x$") then return nil, "invalid-color" end
            color = { tonumber(field:sub(2, 3), 16) / 255, tonumber(field:sub(4, 5), 16) / 255,
                tonumber(field:sub(6, 7), 16) / 255 }
            if i < #fields then
                local a = fields[i + 1]
                if not a:match("^%d+$") or tonumber(a) > 100 then return nil, "invalid-alpha" end
                alpha = tonumber(a) / 100
                i = i + 1
            end
            if i ~= #fields then return nil, "invalid-color-position" end
        elseif field:match("^%d+f$") then
            if precision ~= nil or #field > 2 then return nil, "invalid-precision" end
            precision = tonumber(field:sub(1, -2))
            if precision > FT.MAX_PRECISION then return nil, "invalid-precision" end
        else
            local mod = def.modifiers[field]
            if not mod or used[mod] then return nil, "invalid-modifier" end
            used[mod] = true
            mods[#mods + 1] = mod
        end
        i = i + 1
    end
    if def.literal then
        if precision ~= nil then return nil, "invalid-precision" end
        return { id = def.id, literal = fields[2], color = color, alpha = alpha }
    end
    table.sort(mods)
    local variant = def.variants[table.concat(mods, ":")]
    if not variant then return nil, "invalid-combination" end
    if precision ~= nil and not variant.numeric then return nil, "invalid-precision" end
    return { id = def.id, variant = variant, color = color, alpha = alpha, precision = precision }
end

function FT:Compile(template, context)
    assert(type(template) == "string" and Identifier(context), "template and context required")
    local validLength = #template <= MAX_LENGTH
    local key = validLength and (context .. "\0" .. template)
    local hit = key and cache[key]
    if hit then return hit end
    local data = { nodes = {}, runs = {},
        dependencies = {}, tags = {}, issues = {}, identity = true, width = 0, literals = 0, tagCount = 0 }
    local fmt, pos, count = {}, 1, 0
    local line, lineFormat = { first = 1 }, {}
    data.lines = { line }
    local function AddLiteral(s, color, alpha)
        if s == "" then return end
        fmt[#fmt + 1] = Literal(s)
        local position = 1
        repeat
            local newline = s:find("\n", position, true)
            local part = s:sub(position, newline and newline - 1 or #s)
            if part ~= "" then
                data.runs[#data.runs + 1] = { literal = part, escaped = part:gsub("|", "||"),
                    color = color, alpha = alpha, line = #data.lines }
                lineFormat[#lineFormat + 1] = Literal(part)
            end
            if not newline then break end
            line.format, line.last = table.concat(lineFormat), #data.nodes
            line, lineFormat = { first = #data.nodes + 1 }, {}
            data.lines[#data.lines + 1] = line
            position = newline + 1
        until position > #s + 1
        local length = strlenutf8 and strlenutf8(s) or #s
        data.literals = data.literals + length
        data.width = data.width + length * 5
    end
    if #template > MAX_LENGTH or template:find("%z") then
        data.issues[1] = { code = "invalid-template", position = 1 }
        AddLiteral(template:sub(1, MAX_LENGTH):gsub("%z", ""))
    else
        while true do
            local first, last, body = template:find("%[:(.-):%]", pos)
            if not first then
                local remaining = template:sub(pos)
                local unmatched = remaining:find("[:", 1, true)
                if unmatched then data.issues[#data.issues + 1] = { code = "unterminated-tag", position = pos + unmatched - 1 } end
                AddLiteral(remaining)
                break
            end
            AddLiteral(template:sub(pos, first - 1))
            count = count + 1
            local node, problem
            if count > MAX_TAGS then problem = "too-many-tags"
            else node, problem = ParseTag(body, context) end
            if node then data.tagCount = data.tagCount + 1 end
            if node and node.literal ~= nil then
                AddLiteral(node.literal, node.color, node.alpha)
                data.tags[node.id] = true
                if node.color then data.styled = true end
            elseif node then
                local v = node.variant
                data.nodes[#data.nodes + 1] = node
                node.index = #data.nodes
                node.line = #data.lines
                data.runs[#data.runs + 1] = node
                fmt[#fmt + 1] = v.format
                lineFormat[#lineFormat + 1] = v.format
                data.tags[node.id] = true
                for dep in pairs(v.dependencies) do data.dependencies[dep] = true end
                if not v.identity then data.identity = false end
                if node.color or v.bind then data.styled = true end
                data.width = data.width + v.width + (node.precision and node.precision > 0 and (node.precision + 1) * 5 or 0)
            else
                data.issues[#data.issues + 1] = { code = problem, position = first }
                AddLiteral(template:sub(first, last))
            end
            pos = last + 1
        end
    end
    data.format = table.concat(fmt)
    line.format, line.last = table.concat(lineFormat), #data.nodes
    local plan = {}
    plans[plan] = data
    if key then
        if cacheCount >= CACHE_LIMIT then cache, cacheCount = {}, 0 end
        cache[key], cacheCount = plan, cacheCount + 1
    end
    return plan
end

function FT:Describe(plan)
    local d = assert(plans[plan], "invalid formatted-text plan")
    local out = { dependencies = {}, tags = {}, issues = {}, identity = d.identity,
        width = d.width, literalCharacters = d.literals, styled = d.styled == true, tagCount = d.tagCount or #d.nodes }
    for k, v in pairs(d.dependencies) do out.dependencies[k] = v end
    for k, v in pairs(d.tags) do out.tags[k] = v end
    for i = 1, #d.issues do
        local e = d.issues[i]
        out.issues[i] = { code = e.code, position = e.position }
    end
    return out
end

function FT:HasTag(template, context, id)
    if type(template) ~= "string" or type(id) ~= "string" then return false end
    id = id:lower()
    local d = plans[self:Compile(template, context)]
    local def = registry[aliases[context .. "\0" .. id]]
    return d.tags[def and def.id or id] == true
end

function FT:GetCatalog(context)
    local list = {}
    for i = 1, #ordered do
        local d = registry[ordered[i]]
        if d.context == context then
            local entry = { id = d.id, description = d.description, aliases = CopyList(d.aliases),
                modifiers = CopyList(d.modifierNames), modifierAliases = {}, modifierDescriptions = {}, examples = {} }
            for alias, canonical in pairs(d.modifiers) do entry.modifierAliases[alias] = canonical end
            for key, description in pairs(d.modifierDescriptions) do entry.modifierDescriptions[key] = description end
            for key in pairs(d.variants) do
                if d.variants[key].numeric then entry.numeric = true end
                entry.examples[#entry.examples + 1] = "[:" .. d.id .. (key ~= "" and ":" .. key or "") .. ":]"
            end
            table.sort(entry.examples)
            list[#list + 1] = entry
        end
    end
    list[#list + 1] = { id = textTag.id, syntax = textTag.syntax, description = textTag.description,
        aliases = {}, modifiers = {}, modifierAliases = {}, modifierDescriptions = {},
        examples = { "[:text:words:]" } }
    return list
end

-- Previews use synthetic values only; live restricted values stay in the widget argument lane.
function FT:Preview(plan, samples)
    local d, values = assert(plans[plan], "invalid formatted-text plan"), {}
    for i = 1, #d.nodes do
        local v = d.nodes[i].variant
        values[i] = samples and samples[v.sampleKey] or v.preview
        if v.numeric then values[i] = self._internal.FormatValue(d.nodes[i], tonumber(values[i]) or values[i]) end
    end
    return string.format(d.format, unpack(values, 1, #d.nodes))
end

function FT:EstimateWidth(template, context, namesOnRight)
    local d = plans[self:Compile(template, context)]
    local width = d.width
    if namesOnRight then
        for i = 1, #d.nodes do
            local node = d.nodes[i]
            if node.id == "name" or node.id == "target" then width = width + 80 end
        end
    end
    return width
end

function FT:RegisterContext(id, driver)
    assert(Identifier(id) and type(driver) == "table" and type(driver.subscribe) == "function",
        "context driver needs subscribe(display, dependencies)")
    assert(driver.available == nil or type(driver.available) == "function", "invalid context availability reader")
    internals.drivers = internals.drivers or {}
    assert(not internals.drivers[id], "duplicate formatted-text context")
    local examples = CopyList(driver.examples)
    for i = 1, #examples do assert(type(examples[i]) == "string" and #examples[i] <= MAX_LENGTH, "invalid context example") end
    internals.drivers[id] = { subscribe = driver.subscribe, available = driver.available, examples = examples }
end

function FT:GetExamples(context)
    local driver = internals.drivers and internals.drivers[context]
    return CopyList(driver and driver.examples)
end
