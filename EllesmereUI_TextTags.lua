if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  EllesmereUI_TextTags.lua
--  Custom text templates ("[hp:abr] | [hp:pct]%"): shared tag schema, parser,
--  preview and help text. Pure string logic (no frames, events or units), plus
--  the options glue a Custom text field shares (PopupOpts and below it).
--  A module binds the schema keys it draws to its own pieces (Bind) and paints
--  the parse through its own path: fmt has one %s per tag, keys names each one.
--  Secret values, DEAD/OFFLINE and abbreviation stay in the module's pieces.
--------------------------------------------------------------------------------
EllesmereUI = EllesmereUI or {}
local EllesmereUI = EllesmereUI

local type, pairs, error, tostring = type, pairs, error, tostring
local sfind, ssub, slower, sgsub, sformat = string.find, string.sub, string.lower, string.gsub, string.format
local tconcat, unpack = table.concat, unpack

local TextTags = {}
EllesmereUI.TextTags = TextTags

-------------------------------------------------------------------------------
--  Unit schema
--  reads: the value a key shows -- "hp", "pp", "abs", "habs", "id" (name or
--  level, changes on identity events only), "tgt" (the unit's target),
--  "roster" (group membership). width: estimated pixels. sample: preview value.
-------------------------------------------------------------------------------
TextTags.UNIT = {
    mods = { "max", "abr", "pct", "first", "last", "abbr" },  -- order of the modifiers inside a key
    modAliases = { percent = "pct" },
    tags = {  -- order of the help text
        { tag = "hp", aliases = { "health" }, keys = { "hp", "hp:abr", "hp:max", "hp:max:abr", "hp:pct" } },
        { tag = "pp", aliases = { "power" }, keys = { "pp", "pp:abr", "pp:max", "pp:max:abr", "pp:pct" } },
        { tag = "absorb", keys = { "absorb", "absorb:abr" } },
        { tag = "healabsorb", keys = { "healabsorb", "healabsorb:abr" } },
        { tag = "name", keys = { "name", "name:first", "name:last", "name:abbr" } },
        { tag = "target", keys = { "target", "target:first", "target:last", "target:abbr" } },
        { tag = "level", keys = { "level" } },
        { tag = "group", keys = { "group" } },
    },
    keys = {
        ["hp"]             = { reads = "hp", width = 45, sample = "132456" },
        ["hp:abr"]         = { reads = "hp", width = 38, sample = "132 K" },
        ["hp:max"]         = { reads = "hp", width = 45, sample = "150000" },
        ["hp:max:abr"]     = { reads = "hp", width = 38, sample = "150 K" },
        ["hp:pct"]         = { reads = "hp", width = 30, sample = "88" },
        ["pp"]             = { reads = "pp", width = 45, sample = "31250" },
        ["pp:abr"]         = { reads = "pp", width = 38, sample = "31 K" },
        ["pp:max"]         = { reads = "pp", width = 45, sample = "50000" },
        ["pp:max:abr"]     = { reads = "pp", width = 38, sample = "50 K" },
        ["pp:pct"]         = { reads = "pp", width = 30, sample = "62" },
        ["absorb"]         = { reads = "abs", width = 45, sample = "12345" },
        ["absorb:abr"]     = { reads = "abs", width = 38, sample = "12 K" },
        ["healabsorb"]     = { reads = "habs", width = 45, sample = "4200" },
        ["healabsorb:abr"] = { reads = "habs", width = 38, sample = "4 K" },
        ["name"]           = { reads = "id", width = 80, sample = "Thrall" },
        ["name:first"]     = { reads = "id", width = 48, sample = "Thrall" },
        ["name:last"]      = { reads = "id", width = 64, sample = "Stormrage" },
        ["name:abbr"]      = { reads = "id", width = 72, sample = "I. Stormrage" },
        ["target"]         = { reads = "tgt", width = 80, sample = "Jaina" },
        ["target:first"]   = { reads = "tgt", width = 48, sample = "Jaina" },
        ["target:last"]    = { reads = "tgt", width = 72, sample = "Proudmoore" },
        ["target:abbr"]    = { reads = "tgt", width = 72, sample = "J. Proudmoore" },
        ["level"]          = { reads = "id", width = 24, sample = "80" },
        ["group"]          = { reads = "roster", width = 10, sample = "3" },
    },
    -- Built on demand: the active locale is resolved only at ADDON_LOADED.
    descs = function()
        return {
            tags = {
                hp = EllesmereUI.L("Health"), pp = EllesmereUI.L("Power"),
                absorb = EllesmereUI.L("Absorb shield"), healabsorb = EllesmereUI.L("Heal absorb"),
                name = EllesmereUI.L("Unit name"), target = EllesmereUI.L("Name of the unit's target"),
                level = EllesmereUI.L("Unit level"), group = EllesmereUI.L("Raid group number"),
            },
            mods = {
                abr = EllesmereUI.L("Abbreviated (132 K)"),
                max = EllesmereUI.L("Maximum instead of current"),
                pct = EllesmereUI.L("Percent, number only"),
                first = EllesmereUI.L("First word"),
                last = EllesmereUI.L("Last word"),
                abbr = EllesmereUI.L("Initials, last word whole (I. Stormrage)"),
            },
            -- Short, for the suggestion list.
            keys = {
                ["hp"] = EllesmereUI.L("Current health"), ["hp:abr"] = EllesmereUI.L("Current, abbreviated"),
                ["hp:max"] = EllesmereUI.L("Maximum health"), ["hp:max:abr"] = EllesmereUI.L("Maximum, abbreviated"),
                ["hp:pct"] = EllesmereUI.L("Health percent"),
                ["pp"] = EllesmereUI.L("Current power"), ["pp:abr"] = EllesmereUI.L("Current, abbreviated"),
                ["pp:max"] = EllesmereUI.L("Maximum power"), ["pp:max:abr"] = EllesmereUI.L("Maximum, abbreviated"),
                ["pp:pct"] = EllesmereUI.L("Power percent"),
                ["absorb"] = EllesmereUI.L("Absorb shield"), ["absorb:abr"] = EllesmereUI.L("Absorb, abbreviated"),
                ["healabsorb"] = EllesmereUI.L("Heal absorb"), ["healabsorb:abr"] = EllesmereUI.L("Heal absorb, abbreviated"),
                ["name"] = EllesmereUI.L("Unit name"),
                ["name:first"] = EllesmereUI.L("First name"), ["name:last"] = EllesmereUI.L("Last name"),
                ["name:abbr"] = EllesmereUI.L("Abbreviated"),
                ["target"] = EllesmereUI.L("Target's name"),
                ["target:first"] = EllesmereUI.L("Target, first name"), ["target:last"] = EllesmereUI.L("Target, last name"),
                ["target:abbr"] = EllesmereUI.L("Target, abbreviated"),
                ["level"] = EllesmereUI.L("Unit level"), ["group"] = EllesmereUI.L("Raid group"),
            },
        }
    end,
    examples = { "[hp:max:abr]", "[name:abbr] [hp:pct]%", "[hp:abr] | [pp]/[pp:max]" },
}

-------------------------------------------------------------------------------
--  Bind: a catalog is the schema narrowed to the keys a module draws. map is
--  { schema key = the module's own piece }; the core never looks at the values.
--  A key the module leaves out is unknown to that catalog.
-------------------------------------------------------------------------------
function TextTags.Bind(schema, map)
    local cat = { schema = schema, map = {}, keys = {}, tags = {}, names = {}, mods = {}, cache = {}, count = 0 }
    for key, v in pairs(map) do
        if not schema.keys[key] then error("TextTags.Bind: unknown key " .. tostring(key), 2) end
        cat.map[key] = v
    end
    for i = 1, #schema.tags do
        local def, bound = schema.tags[i], {}
        for k = 1, #def.keys do
            local key = def.keys[k]
            if cat.map[key] ~= nil then
                bound[#bound + 1] = key
                cat.keys[#cat.keys + 1] = key
            end
        end
        if #bound > 0 then
            cat.tags[#cat.tags + 1] = { tag = def.tag, aliases = def.aliases, keys = bound }
            cat.names[def.tag] = def.tag
            if def.aliases then
                for a = 1, #def.aliases do cat.names[def.aliases[a]] = def.tag end
            end
        end
    end
    for i = 1, #schema.mods do cat.mods[schema.mods[i]] = schema.mods[i] end
    if schema.modAliases then
        for alias, mod in pairs(schema.modAliases) do cat.mods[alias] = mod end
    end
    return cat
end

-------------------------------------------------------------------------------
--  Parse
-------------------------------------------------------------------------------
local function Escape(s)
    return (sgsub(sgsub(s, "%%", "%%%%"), "|", "||"))
end

-- "hp:ABR:max" -> "hp:max:abr" when the catalog binds it, else nil. Modifier
-- order is free; an empty part, an unknown or a repeated modifier is no key.
local modSeen = {}
local function ResolveKey(cat, inner)
    inner = slower(inner)
    local s, e = sfind(inner, ":", 1, true)
    local tag = cat.names[s and ssub(inner, 1, s - 1) or inner]
    if not tag then return nil end
    if not s then return cat.map[tag] ~= nil and tag or nil end
    for k in pairs(modSeen) do modSeen[k] = nil end
    local pos = e + 1
    while true do
        local ns = sfind(inner, ":", pos, true)
        local mod = cat.mods[ssub(inner, pos, (ns or 0) - 1)]
        if not mod or modSeen[mod] then return nil end
        modSeen[mod] = true
        if not ns then break end
        pos = ns + 1
    end
    local order, key = cat.schema.mods, tag
    for i = 1, #order do
        if modSeen[order[i]] then key = key .. ":" .. order[i] end
    end
    return cat.map[key] ~= nil and key or nil
end

local strlen = strlenutf8 or string.len

--- Parses a template against a catalog: nil for an empty or non-string one,
--- else { fmt, keys, has, reads, literalChars, unknown }. fmt is escaped with
--- one %s per tag, keys the schema key of each, has / reads sets of the keys
--- and value classes used, literalChars the UTF-8 length outside the tags,
--- unknown the bracketed text that is no bound key (left as typed, no repeats).
--- "%" is escaped and "|" doubled: no colour or texture escape can be typed.
--- Cached and shared by every reader (read-only); transient (the popup's
--- per-keystroke preview) reads the cache but never fills it.
function TextTags.Parse(cat, template, transient)
    if type(template) ~= "string" or template == "" then return nil end
    local hit = cat.cache[template]
    if hit then return hit end
    local fmt, literal, keys, has, reads, unknown, seen = {}, {}, {}, {}, {}, {}, {}
    local pos = 1
    while true do
        -- Any bracketed text: what is no bound key stays as typed and is named.
        local s, e, inner = sfind(template, "%[([^%[%]]+)%]", pos)
        local lit = ssub(template, pos, (s or 0) - 1)
        local key = s and ResolveKey(cat, inner)
        if s and not key then
            local raw = ssub(template, s, e)
            lit = lit .. raw
            if not seen[raw] then
                seen[raw] = true
                unknown[#unknown + 1] = raw
            end
        end
        fmt[#fmt + 1] = Escape(lit)
        literal[#literal + 1] = lit
        if key then
            fmt[#fmt + 1] = "%s"
            keys[#keys + 1] = key
            has[key] = true
            reads[cat.schema.keys[key].reads] = true
        end
        if not s then break end
        pos = e + 1
    end
    hit = {
        fmt = tconcat(fmt), keys = keys, has = has, reads = reads,
        literalChars = strlen(tconcat(literal)), unknown = unknown,
    }
    if transient then return hit end
    if cat.count >= 64 then cat.cache, cat.count = {}, 0 end
    cat.cache[template] = hit
    cat.count = cat.count + 1
    return hit
end

-------------------------------------------------------------------------------
--  Preview, width, help
-------------------------------------------------------------------------------
local scratch = {}
-- The schema's descriptions, translated once per catalog on first use (help
-- and completion run only after ADDON_LOADED, when the locale is active).
local function Descs(cat)
    local d = cat.descs
    if not d then
        d = cat.schema.descs and cat.schema.descs() or {}
        cat.descs = d
    end
    return d
end
local DIM, MOD, UNKNOWN = EllesmereUI.COLOR_CODES.DIM, "|cffffd27a", "|cffffa633"

--- The parse filled with the schema's samples. mark (a colour escape such as
--- "|cffffa633"), when given, colours the unknown tags left as text.
function TextTags.Preview(cat, parsed, mark)
    local keys, defs = parsed.keys, cat.schema.keys
    for i = 1, #keys do scratch[i] = defs[keys[i]].sample end
    local out = sformat(parsed.fmt, unpack(scratch, 1, #keys))
    if mark then
        local unknown = parsed.unknown
        for i = 1, #unknown do
            -- As it stands in fmt: "|" doubled; "%" escaped for the replacement.
            local shown = sgsub(unknown[i], "|", "||")
            out = sgsub(out, sgsub(shown, "%p", "%%%0"), mark .. sgsub(shown, "%%", "%%%%") .. "|r")
        end
    end
    return out
end

--- Estimated pixel width: each key's schema width, 5 per literal character.
--- override(key), when given, may return a number to replace a key's width.
function TextTags.EstimateWidth(cat, parsed, override)
    local keys, defs = parsed.keys, cat.schema.keys
    local w = parsed.literalChars * 5
    for i = 1, #keys do
        local key = keys[i]
        w = w + (override and override(key) or defs[key].width)
    end
    return w
end

--- The info text for the popup: syntax, one line per bound tag with its
--- aliases and modifiers, the modifier legend, and examples with their result.
--- opts (optional): examples replaces the schema's (any using an unbound key
--- is skipped); tagNotes { tag = localized text } adds "(text)" to a tag.
function TextTags.HelpText(cat, opts)
    local descs = Descs(cat)
    local tagDescs, modDescs = descs.tags or {}, descs.mods or {}
    local tagNotes = opts and opts.tagNotes or {}
    local EG = EllesmereUI.ELLESMERE_GREEN
    local head = EllesmereUI.HexColor(EG.r, EG.g, EG.b)
    local orWord = " " .. DIM .. EllesmereUI.L("or") .. "|r "
    local order = cat.schema.mods
    local lines = {
        head .. EllesmereUI.L("Syntax") .. "|r",
        DIM .. EllesmereUI.L("Tags in [brackets], add modifiers with a colon, in any order.") .. "|r",
        "", head .. EllesmereUI.L("Tags") .. "|r",
    }
    local used = {}
    for i = 1, #cat.tags do
        local t, mods = cat.tags[i], {}
        for k = 1, #t.keys do
            for m = 1, #order do
                if sfind(t.keys[k] .. ":", ":" .. order[m] .. ":", 1, true) then mods[order[m]] = true end
            end
        end
        local names, list = { "[" .. t.tag .. "]" }, {}
        if t.aliases then
            for a = 1, #t.aliases do names[#names + 1] = "[" .. t.aliases[a] .. "]" end
        end
        for m = 1, #order do
            if mods[order[m]] then
                list[#list + 1] = order[m]
                used[order[m]] = true
            end
        end
        local desc = tagDescs[t.tag]
        if desc and tagNotes[t.tag] then desc = desc .. " (" .. tagNotes[t.tag] .. ")" end
        lines[#lines + 1] = tconcat(names, orWord) .. (desc and ("  " .. DIM .. desc .. "|r") or "")
            .. (#list > 0 and ("  " .. MOD .. tconcat(list, " ") .. "|r") or "")
    end
    local modAliases = cat.schema.modAliases or {}
    local first = true
    for m = 1, #order do
        local mod = order[m]
        if used[mod] then
            if first then
                first = false
                lines[#lines + 1] = ""
                lines[#lines + 1] = head .. EllesmereUI.L("Modifiers") .. "|r"
            end
            local line = MOD .. mod .. "|r"
            for alias, target in pairs(modAliases) do
                if target == mod then line = line .. orWord .. MOD .. alias .. "|r" end
            end
            lines[#lines + 1] = line .. (modDescs[mod] and ("  " .. DIM .. modDescs[mod] .. "|r") or "")
        end
    end
    local examples = opts and opts.examples or cat.schema.examples
    local shown = 0
    for i = 1, #(examples or {}) do
        local parsed = TextTags.Parse(cat, examples[i])
        if parsed and #parsed.unknown == 0 then
            if shown == 0 then
                lines[#lines + 1] = ""
                lines[#lines + 1] = head .. EllesmereUI.L("Examples") .. "|r"
            end
            shown = shown + 1
            -- Modifiers in their legend colour; "|" doubled before any colour escape is added.
            local shownText = sgsub(sgsub(examples[i], "|", "||"), "%[(%w+)(:[%w:]+)%]", "[%1" .. MOD .. "%2|r]")
            lines[#lines + 1] = shownText .. "  " .. DIM .. "=  " .. TextTags.Preview(cat, parsed) .. "|r"
        end
    end
    return tconcat(lines, "\n")
end

--- Completion for the tag being typed: text up to cursor (in bytes, as
--- EditBox:GetCursorPosition counts) ending in "[" plus an unclosed partial
--- tag. Returns nil, or (items, from, to): items { text = "hp:abr]", label (modifiers coloured),
--- desc, detail = sample } in schema order, and the text[from..to] range an
--- item replaces (a "]" right after the caret included). A bare tag name lists
--- its variants, a partial name one entry per matching tag. An item with longer
--- variants inserts without "]" (its variants are listed next), unless it is
--- already typed in full.
function TextTags.Complete(cat, text, cursor)
    if type(text) ~= "string" then return nil end
    local before = ssub(text, 1, cursor)
    local open = before:match(".*()%[")
    if not open then return nil end
    local partial = slower(ssub(before, open + 1))
    if not partial:match("^[%w:]*$") then return nil end
    local colon = sfind(partial, ":", 1, true)
    -- The partial as a key (aliases resolved, any modifier order), to tell
    -- "already typed in full".
    local typed = ResolveKey(cat, partial) or partial
    -- After a colon: the complete modifiers typed (done, by canonical name)
    -- and the partial last one; a modifier that is unknown or repeated ends
    -- the suggestions, as it does the parse.
    local done, last = {}, nil
    if colon then
        local pos = colon + 1
        while true do
            local nx = sfind(partial, ":", pos, true)
            if not nx then last = ssub(partial, pos); break end
            local m = cat.mods[ssub(partial, pos, nx - 1)]
            if not m or done[m] then return nil end
            done[m] = true
            pos = nx + 1
        end
    end
    -- A key fits when it holds every done modifier plus one more whose name
    -- or alias starts with last.
    local function Fits(key)
        local mods = {}
        for m in key:gmatch(":(%w+)") do mods[m] = true end
        for m in pairs(done) do
            if not mods[m] then return false end
        end
        for m in pairs(mods) do
            if not done[m] then
                for name, canon in pairs(cat.mods) do
                    if canon == m and ssub(name, 1, #last) == last then return true end
                end
            end
        end
        return false
    end
    local descs = Descs(cat).keys or {}
    local items, seen, defs = {}, {}, cat.schema.keys
    local function Add(key)
        if seen[key] then return end
        seen[key] = true
        local open = false
        if key ~= typed then
            for k = 1, #cat.keys do
                if ssub(cat.keys[k], 1, #key + 1) == key .. ":" then open = true; break end
            end
        end
        local label = sgsub(key, "^(%w+)(:.+)$", "%1" .. MOD .. "%2|r")
        items[#items + 1] = { text = open and key or (key .. "]"), label = label, desc = descs[key], detail = defs[key].sample }
    end
    for i = 1, #cat.tags do
        local t = cat.tags[i]
        local names = { t.tag }
        if t.aliases then
            for a = 1, #t.aliases do names[#names + 1] = t.aliases[a] end
        end
        for n = 1, #names do
            local name = names[n]
            if colon then
                if ssub(partial, 1, colon - 1) == name then
                    for k = 1, #t.keys do
                        if Fits(t.keys[k]) then Add(t.keys[k]) end
                    end
                end
            elseif partial == name then
                for k = 1, #t.keys do Add(t.keys[k]) end
            elseif ssub(name, 1, #partial) == partial then
                Add(t.keys[1])
            end
        end
    end
    if #items == 0 then return nil end
    local to = cursor
    if ssub(text, cursor + 1, cursor + 1) == "]" then to = cursor + 1 end
    return items, open + 1, to
end

--- Fills the options of EllesmereUI:ShowInputPopup for a template field and
--- returns them: preview (the sample line and a hint naming unknown tags),
--- previewLabel, complete (tag suggestions), infoTooltip (the help text, built
--- on hover) and infoTooltipOpts. helpOpts goes to TextTags.HelpText.
function TextTags.PopupOpts(cat, opts, helpOpts)
    opts = opts or {}
    opts.preview = function(text)
        -- The edit box doubles a typed "|"; templates are stored with single ones.
        local parsed = TextTags.Parse(cat, type(text) == "string" and sgsub(text, "||", "|") or text, true)
        if not parsed then return nil, nil end
        local hint
        if #parsed.unknown > 0 then
            hint = EllesmereUI.Lf("Unknown tags, shown as typed: %s", (sgsub(tconcat(parsed.unknown, ", "), "|", "||")))
        end
        return TextTags.Preview(cat, parsed, UNKNOWN), hint
    end
    opts.previewLabel = EllesmereUI.L("Preview")
    opts.complete = function(text, cursor) return TextTags.Complete(cat, text, cursor) end
    opts.infoTooltip = function() return TextTags.HelpText(cat, helpOpts) end
    opts.infoTooltipOpts = { width = 360, justify = "LEFT", anchorPoint = "TOPRIGHT", anchorTo = "TOPLEFT", anchorX = -8 }
    return opts
end

-------------------------------------------------------------------------------
--  A Custom text field's options: the template popup, the dropdown entry that
--  opens it and the Spec Overrides accessor, shared by every module offering
--  Custom text. Called only from options pages.
-------------------------------------------------------------------------------
local EDIT_ICON = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-edit.png"
local CLOSE_ICON = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png"
TextTags.EDIT_ICON = EDIT_ICON

--- The template popup. o: cat (the module's catalog), get() / set(text) (the stored
--- template, single pipes), color (the preview's text colour; nil = white), tagNotes
--- (as TextTags.HelpText's), onSave (after the template is stored). Spaces only opens
--- the popup again with a hint instead of closing unsaved.
function TextTags.EditPopup(o, warning)
    local cur = o.get()
    -- The edit box holds a typed "|" doubled.
    if type(cur) == "string" then cur = sgsub(cur, "|", "||") else cur = nil end
    -- 120 letters for new input; a longer stored template (import) keeps its length.
    local maxLen = math.max(120, cur and strlenutf8(cur) or 0)
    local popupOpts = {
        title = EllesmereUI.L("Custom Text"),
        message = EllesmereUI.L("Tags in [brackets] show live values, other text stays as typed.") .. "\n"
            .. EllesmereUI.L("Type [ for suggestions, the (i) lists every tag."),
        messageSize = 10,
        previewColor = o.color,
        placeholder = "[name] - [hp:pct]%",
        initialText = (not warning and cur) or "",
        maxLetters = maxLen,
        showCount = true,
        warning = warning,
        onConfirm = function(txt)
            txt = sgsub(sgsub(sgsub(tostring(txt or ""), "||", "|"), "^%s+", ""), "%s+$", "")
            if txt == "" then
                TextTags.EditPopup(o, EllesmereUI.L("Enter at least one tag or character."))
                return
            end
            o.set(txt)
            if o.onSave then o.onSave() end
        end,
    }
    TextTags.PopupOpts(o.cat, popupOpts, o.tagNotes and { tagNotes = o.tagNotes } or nil)
    EllesmereUI:ShowInputPopup(popupOpts)
end

--- A copy of a text dropdown's values whose "custom" entry is an action opening the
--- popup (edit; nil adds none), marked with the edit pencil. o.text: that entry's
--- label (nil: "Custom"); o.selected(): the pencil at full alpha while true (nil:
--- always); o.removeKey: that entry in the house red with the close X. The values'
--- own _menuOpts still dress their other entries; the menu reads all of it when it
--- is built.
function TextTags.MenuValues(values, edit, o)
    local v = CopyTable(values)
    if edit then v.custom = { text = (o and o.text) or "Custom", action = edit } end
    local mo = v._menuOpts or {}
    v._menuOpts = mo
    local icon, iconColor, labelColor = mo.icon, mo.iconColor, mo.labelColor
    local selected, removeKey = o and o.selected, o and o.removeKey
    mo.icon = function(key)
        if key == "custom" then return EDIT_ICON end
        if key == removeKey then return CLOSE_ICON end
        if icon then return icon(key) end
    end
    mo.iconSize = mo.iconSize or function() return 12 end
    mo.iconClearScroll = true
    mo.iconColor = function(key)
        if key == "custom" then return 1, 1, 1, (not selected or selected()) and 1 or 0.75 end
        if key == removeKey then return 1, 0.35, 0.35, 0.75 end
        if iconColor then return iconColor(key) end
    end
    mo.labelColor = function(key)
        if key == removeKey then return 1, 0.35, 0.35, 0.8 end
        if labelColor then return labelColor(key) end
    end
    return v
end

--- Spec Overrides' accessor for a template the popup writes directly: the capture
--- reads and restores it as label .. " Custom Format" (get() / set(v); nil clears).
function TextTags.AddFormatAccessor(rgn, label, get, set)
    EllesmereUI.AddCaptureAccessor(rgn, {
        type = "input", text = label .. " Custom Format",
        getValue = function() return get() or "" end,
        setValue = function(v) set((v ~= "" and v) or nil) end,
    })
end
