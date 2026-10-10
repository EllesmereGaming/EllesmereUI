if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_MacroBuilder.lua  (WoW Forever only)
--  The Macro Manager's macro model: a macro is a header plus a list of lines,
--  built to text and parsed back. Plain data and functions, no frames.
--
--  model   = { tooltip = bool, tooltipSpell = "", lines = { line, ... } }
--  line    = { kind = "cast", on = true, variants = { variant, ... }, reset = "", chan = "say" }
--  variant = { arg = "Spell", target = "mouseover", conds = { harm = 1, dead = 2 },
--              stance = "", params = { { key, value, no } }, extra = "" }
--
--  A variant becomes "[@target,conds] arg"; several are joined with "; ".
--  Parse() turns any macro text into a model: a line it cannot rebuild
--  character for character becomes a "raw" line, so nothing typed by hand is
--  lost. "{spell}" anywhere in a model is replaced by Build(model, spell);
--  the bulk creator turns one template into many macros that way.
-------------------------------------------------------------------------------
local _, module = ...
local B = {}
module.MacroBuilder = B

-------------------------------------------------------------------------------
--  Line kinds
--  arg: "spell" (spell box) | "spells" (comma list) | "text" | "unit" | nil
--  multi: allows several variants   conds: takes [conditions]
-------------------------------------------------------------------------------
B.KINDS = {
    -- spells
    { key = "cast", cmd = "/cast", label = "Cast spell", arg = "spell", multi = true, conds = true,
      desc = "Casts a spell. With several variants the first one whose conditions match is cast." },
    { key = "use", cmd = "/use", label = "Use item / slot", arg = "spell", multi = true, conds = true, ph = "Item, spell or slot (13/14)",
      desc = "Uses an item by name, an equipment slot (13/14 = trinkets) or bag and slot (e.g. 0 1). Works with spells too." },
    { key = "castsequence", cmd = "/castsequence", label = "Cast sequence", arg = "spells", conds = true, reset = true,
      desc = "Each press casts the next spell of the list. reset= sets when it starts over." },
    { key = "castrandom", cmd = "/castrandom", label = "Random spell", arg = "spells", conds = true,
      desc = "Casts a random spell from the list." },
    { key = "userandom", cmd = "/userandom", label = "Random item", arg = "spells", conds = true, ph = "Item1, Item2, Item3",
      desc = "Uses a random item from the list (e.g. mounts or toys)." },
    { key = "stopcasting", cmd = "/stopcasting", label = "Stop casting", conds = true,
      desc = "Cancels the spell you are casting right now. Put it before an interrupt." },
    { key = "stopspelltarget", cmd = "/stopspelltarget", label = "Cancel targeting", conds = true,
      desc = "Cancels a spell that is waiting for a target (glowing hand or ground circle)." },
    { key = "cancelaura", cmd = "/cancelaura", label = "Cancel buff", arg = "spell", conds = true, ph = "Buff name",
      desc = "Removes a buff from you, e.g. Ice Block or a speed buff." },
    { key = "cancelform", cmd = "/cancelform", label = "Cancel form", conds = true,
      desc = "Leaves your current shapeshift form (druid forms, Ghost Wolf, Shadowform...)." },

    -- combat and pet
    { key = "startattack", cmd = "/startattack", label = "Start attack", conds = true,
      desc = "Turns on auto-attack (melee or wand) against your target." },
    { key = "stopattack", cmd = "/stopattack", label = "Stop attack", conds = true,
      desc = "Turns off auto-attack, e.g. so you do not break crowd control." },
    { key = "petattack", cmd = "/petattack", label = "Pet: attack", arg = "unit", conds = true, ph = "Empty = your target",
      desc = "Sends your pet to attack your target (or the unit you choose)." },
    { key = "petfollow", cmd = "/petfollow", label = "Pet: follow", conds = true,
      desc = "Your pet stops and follows you." },
    { key = "petstay", cmd = "/petstay", label = "Pet: stay", conds = true,
      desc = "Your pet stays where it is." },
    { key = "petmoveto", cmd = "/petmoveto", label = "Pet: move to", conds = true,
      desc = "Moves your pet to a spot. Combine it with the target @cursor." },
    { key = "petpassive", cmd = "/petpassive", label = "Pet: passive", conds = true,
      desc = "Your pet never attacks on its own." },
    { key = "petdefensive", cmd = "/petdefensive", label = "Pet: defensive", conds = true,
      desc = "Your pet attacks whatever attacks you or it." },
    { key = "petaggressive", cmd = "/petaggressive", label = "Pet: aggressive", conds = true,
      desc = "Your pet attacks every enemy in range." },
    { key = "petautocaston", cmd = "/petautocaston", label = "Pet: autocast on", arg = "spell", conds = true, ph = "Pet spell",
      desc = "Turns on autocast for a pet ability." },
    { key = "petautocastoff", cmd = "/petautocastoff", label = "Pet: autocast off", arg = "spell", conds = true, ph = "Pet spell",
      desc = "Turns off autocast for a pet ability." },
    { key = "petautocasttoggle", cmd = "/petautocasttoggle", label = "Pet: toggle autocast", arg = "spell", conds = true, ph = "Pet spell",
      desc = "Switches autocast for a pet ability on or off." },

    -- targeting
    { key = "target", cmd = "/target", label = "Target", arg = "unit", multi = true, conds = true, ph = "Name (empty = the unit from Target)",
      desc = "Targets a unit or the closest match for a name. Leave the name empty and pick e.g. @mouseover." },
    { key = "targetexact", cmd = "/targetexact", label = "Target exact name", arg = "unit", conds = true, ph = "Exact name",
      desc = "Targets only a unit with exactly this name." },
    { key = "targetenemy", cmd = "/targetenemy", label = "Target nearest enemy", conds = true,
      desc = "Cycles to the nearest enemy (like Tab)." },
    { key = "targetenemyplayer", cmd = "/targetenemyplayer", label = "Target nearest enemy player", conds = true,
      desc = "Cycles to the nearest enemy player." },
    { key = "targetfriend", cmd = "/targetfriend", label = "Target nearest friend", conds = true,
      desc = "Cycles to the nearest friendly unit." },
    { key = "targetfriendplayer", cmd = "/targetfriendplayer", label = "Target nearest friendly player", conds = true,
      desc = "Cycles to the nearest friendly player." },
    { key = "targetparty", cmd = "/targetparty", label = "Target party member", conds = true,
      desc = "Cycles through your party members." },
    { key = "targetraid", cmd = "/targetraid", label = "Target raid member", conds = true,
      desc = "Cycles through your raid members." },
    { key = "targetlasttarget", cmd = "/targetlasttarget", label = "Last target", conds = true,
      desc = "Goes back to your previous target." },
    { key = "targetlastenemy", cmd = "/targetlastenemy", label = "Last enemy", conds = true,
      desc = "Targets the last enemy you had targeted." },
    { key = "targetlastfriend", cmd = "/targetlastfriend", label = "Last friend", conds = true,
      desc = "Targets the last friendly unit you had targeted." },
    { key = "cleartarget", cmd = "/cleartarget", label = "Clear target", conds = true,
      desc = "Clears your target, e.g. only when it is dead: [dead]." },
    { key = "assist", cmd = "/assist", label = "Assist", arg = "unit", conds = true, ph = "Name (empty = the unit from Target)",
      desc = "Takes over the target of another unit or player (e.g. the main tank)." },
    { key = "focus", cmd = "/focus", label = "Set focus", arg = "unit", conds = true, ph = "Name (empty = the unit from Target)",
      desc = "Remembers a unit as focus so you can cast on it with @focus." },
    { key = "clearfocus", cmd = "/clearfocus", label = "Clear focus", conds = true,
      desc = "Clears your focus." },
    { key = "targetmarker", cmd = "/tm", label = "Raid marker", arg = "text",
      desc = "Puts a raid marker on your target: 1 star, 2 circle, 3 diamond, 4 triangle, 5 moon, 6 square, 7 cross, 8 skull." },
    { key = "follow", cmd = "/follow", label = "Follow", arg = "unit", conds = true, ph = "Name (empty = the unit from Target)",
      desc = "Follows a player automatically." },

    -- action bars and other
    { key = "changeactionbar", cmd = "/changeactionbar", label = "Change action bar page", arg = "text", conds = true, ph = "Page 1-6",
      desc = "Switches your main action bar to another page (like Shift+1 ... 6). Great with modifiers or stances." },
    { key = "swapactionbar", cmd = "/swapactionbar", label = "Swap action bar pages", arg = "text", conds = true, ph = "Two pages, e.g. 1 2",
      desc = "Toggles your main action bar between two pages." },
    { key = "click", cmd = "/click", label = "Click a button", arg = "text", conds = true, ph = "Button name, e.g. MultiBarRightButton1",
      desc = "Presses another button by its frame name, e.g. to trigger an action bar slot." },
    { key = "equip", cmd = "/equip", label = "Equip item", arg = "text", conds = true, ph = "Item name",
      desc = "Equips an item in its default slot." },
    { key = "equipslot", cmd = "/equipslot", label = "Equip into slot", arg = "text", conds = true, ph = "Slot and item, e.g. 16 Thunderfury",
      desc = "Equips an item into a specific slot (16 main hand, 17 off hand, 18 ranged, 13/14 trinkets)." },
    { key = "dismount", cmd = "/dismount", label = "Dismount", conds = true,
      desc = "Gets off your mount, usually with [mounted]." },
    { key = "stopmacro", cmd = "/stopmacro", label = "Stop macro here", conds = true,
      desc = "Ends the macro at this line when the conditions match. All lines below are skipped." },
    { key = "chat", cmd = "/say", label = "Chat message", arg = "text", ph = "Message (%t = your target's name)",
      desc = "Sends a chat message (say, party, raid, emote...). %t is replaced by your target's name." },
    { key = "console", cmd = "/console", label = "Console setting", arg = "text", ph = "Setting and value, e.g. Sound_EnableSFX 0",
      desc = "Changes a game setting (CVar), e.g. to mute error sounds." },
    { key = "script", cmd = "/run", label = "Lua script", arg = "text", ph = "Lua code",
      desc = "Runs a line of Lua code. Protected actions (spells, targeting) are blocked in combat." },
    { key = "script2", cmd = "/script", label = "Lua script", arg = "text", ph = "Lua code", hidden = true,
      desc = "Runs a line of Lua code (same as /run)." },
    { key = "raw", cmd = "", label = "Free line", arg = "text", ph = "Any macro text",
      desc = "Any text. Everything the builder does not know ends up here, so nothing is lost." },
}
B.KIND = {}
local BY_CMD = {}
for _, k in ipairs(B.KINDS) do
    B.KIND[k.key] = k
    if k.cmd ~= "" and k.key ~= "chat" then BY_CMD[k.cmd] = k end
end

-- Line kind groups for the "Add line" menu, in display order.
B.GROUPS = {
    { label = "Spells/Items", keys = { "cast", "stopcasting", "castsequence", "use", "cancelaura", "cancelform",
        "castrandom", "userandom", "stopspelltarget" } },
    { label = "Combat & Pet", keys = { "startattack", "stopattack", "petattack", "petfollow", "petstay",
        "petmoveto", "petpassive", "petdefensive", "petaggressive", "petautocaston", "petautocastoff",
        "petautocasttoggle" } },
    { label = "Targeting", keys = { "target", "targetexact", "targetenemy", "targetenemyplayer", "targetfriend",
        "targetfriendplayer", "targetparty", "targetraid", "targetlasttarget", "targetlastenemy",
        "targetlastfriend", "cleartarget", "assist", "focus", "clearfocus", "targetmarker", "follow" } },
    { label = "Action Bars & Other", keys = { "changeactionbar", "swapactionbar", "click", "equip", "equipslot",
        "dismount", "stopmacro", "chat", "console", "script", "raw" } },
}

B.CHANNELS = {
    { value = "say",   label = "Say" },
    { value = "yell",  label = "Yell" },
    { value = "party", label = "Party" },
    { value = "raid",  label = "Raid" },
    { value = "rw",    label = "Raid Warning" },
    { value = "emote", label = "Emote" },
    { value = "guild", label = "Guild" },
}
local CHAN_OK = {}
for _, c in ipairs(B.CHANNELS) do CHAN_OK[c.value] = c.label end

B.TARGETS = {
    { value = "",             label = "Default (current target)" },
    { value = "mouseover",    label = "@mouseover - under the mouse" },
    { value = "target",       label = "@target - target" },
    { value = "focus",        label = "@focus - focus" },
    { value = "player",       label = "@player - yourself" },
    { value = "targettarget", label = "@targettarget - target of target" },
    { value = "pet",          label = "@pet - pet" },
    { value = "pettarget",    label = "@pettarget - pet's target" },
    { value = "cursor",       label = "@cursor - ground spell at cursor" },
    { value = "party1",       label = "@party1" },
    { value = "party2",       label = "@party2" },
    { value = "party3",       label = "@party3" },
    { value = "party4",       label = "@party4" },
}

-- Tri-state conditions, in the order they are written.
B.CONDS = {
    { key = "exists",     label = "exists",      tip = "The target exists." },
    { key = "help",       label = "friendly",    tip = "The target is friendly (can be healed)." },
    { key = "harm",       label = "hostile",     tip = "The target can be attacked." },
    { key = "dead",       label = "dead",        tip = "The target is dead." },
    { key = "combat",     label = "in combat",   tip = "You are in combat." },
    { key = "stealth",    label = "stealthed",   tip = "You are stealthed." },
    { key = "mounted",    label = "mounted",     tip = "You are mounted." },
    { key = "channeling", label = "channeling",  tip = "You are channeling a spell." },
    { key = "pet",        label = "has pet",     tip = "You have a pet." },
    { key = "group",      label = "group",       tip = "You are in a group." },
    { key = "swimming",   label = "swimming",    tip = "You are swimming." },
    { key = "indoors",    label = "indoors",     tip = "You are indoors." },
    { key = "outdoors",   label = "outdoors",    tip = "You are outdoors." },
    { key = "party",      label = "in my party", tip = "The target is in your party." },
    { key = "raid",       label = "in my raid",  tip = "The target is in your raid." },
    { key = "mod:shift",  label = "Shift",       tip = "Shift is held down." },
    { key = "mod:ctrl",   label = "Ctrl",        tip = "Ctrl is held down." },
    { key = "mod:alt",    label = "Alt",         tip = "Alt is held down." },
    { key = "mod",        label = "Modifier",    tip = "Any modifier key is held down." },
}
local COND_KEY = {}
for _, d in ipairs(B.CONDS) do COND_KEY[d.key] = true end

-------------------------------------------------------------------------------
--  Conditions with a value ("equipped:Bows"): variant.params
-------------------------------------------------------------------------------
-- equipped: takes the client's localized item subclass name.
local EQUIP_TYPES = {
    { 2, 2 }, { 2, 3 }, { 2, 18 }, { 2, 16 }, { 2, 19 }, { 4, 6 }, { 2, 15 }, { 2, 13 },
    { 2, 0 }, { 2, 1 }, { 2, 4 }, { 2, 5 }, { 2, 7 }, { 2, 8 }, { 2, 6 }, { 2, 10 }, { 2, 20 },
}
local function EquipOptions()
    local out = {}
    for _, e in ipairs(EQUIP_TYPES) do
        local name = C_Item.GetItemSubClassInfo(e[1], e[2])
        if name and name ~= "" then out[#out + 1] = { value = name, label = name } end
    end
    return out
end
local function Numbers(n, names)
    local out = {}
    for i = 1, n do
        out[i] = { value = tostring(i), label = names and (i .. " - " .. names[i]) or tostring(i) }
    end
    return out
end

B.PARAMS = {
    { key = "equipped", label = "equipped item type", options = EquipOptions,
      default = function() local o = EquipOptions()[1] return o and o.value or "" end,
      tip = "You have an item of this type equipped, e.g. only shoot with a bow or gun, Shield Bash only with a shield." },
    { key = "btn", label = "mouse button", default = "2",
      options = function() return Numbers(5, { "left", "right", "middle", "button 4", "button 5" }) end,
      tip = "Which mouse button clicked the action button (or which key binding: 1 = normal)." },
    { key = "actionbar", label = "action bar page", default = "1",
      options = function() return Numbers(6) end,
      tip = "Which page your main action bar is on right now (Shift+1 ... 6)." },
    { key = "bonusbar", label = "bonus bar", default = "1",
      options = function() return Numbers(5) end,
      tip = "The stance or form action bar: warrior 1 Battle, 2 Defensive, 3 Berserker; druid 1 Cat, 3 Bear; rogue 1 Stealth." },
    { key = "group", label = "group type", default = "raid",
      options = function() return { { value = "party", label = "party" }, { value = "raid", label = "raid" } } end,
      tip = "You are in a party or in a raid group." },
    { key = "pet", label = "pet name or family", text = "Name or family, e.g. Imp, Voidwalker, Cat",
      tip = "Your pet has this name or is of this family (warlock demons, hunter pet families)." },
    { key = "channeling", label = "channeling spell", spell = true,
      tip = "You are channeling exactly this spell." },
    { key = "known", label = "spell known", spell = true,
      tip = "You know this spell (e.g. to use one macro on several characters)." },
}
B.PARAM = {}
for _, p in ipairs(B.PARAMS) do B.PARAM[p.key] = p end

function B.NewParam(key)
    local d = B.PARAM[key].default
    if type(d) == "function" then d = d() end
    return { key = key, value = d or "", no = false }
end

-- Stance names in stance bar order: { "Battle Stance", ... }
function B.StanceNames()
    local names = {}
    for i = 1, GetNumShapeshiftForms() do
        local _, _, _, spellID = GetShapeshiftFormInfo(i)
        names[i] = (spellID and C_Spell.GetSpellName(spellID)) or ("Stance " .. i)
    end
    return names
end

function B.Stances()
    local items = {
        { value = "",  label = "any" },
        { value = "0", label = "0 - no stance / normal form" },
    }
    local names = B.StanceNames()
    for i, name in ipairs(names) do
        items[#items + 1] = { value = tostring(i), label = i .. " - " .. name }
    end
    for i = 1, #names - 1 do
        items[#items + 1] = { value = i .. "/" .. (i + 1), label = i .. "/" .. (i + 1) .. " - " .. names[i] .. " or " .. names[i + 1] }
    end
    return items
end

-------------------------------------------------------------------------------
--  Model
-------------------------------------------------------------------------------
function B.NewVariant(arg)
    return { arg = arg or "", target = "", conds = {}, stance = "", params = {}, extra = "" }
end

function B.NewLine(kind, arg)
    if kind == "targetmarker" and not arg then arg = "8" end -- skull
    return { kind = kind or "cast", on = true, variants = { B.NewVariant(arg) }, reset = "", chan = "say" }
end

function B.New()
    return { tooltip = true, tooltipSpell = "", lines = {} }
end

-- Deep copy with every "{spell}" replaced (spell = nil: a plain copy).
function B.Substitute(m, spell)
    local function walk(v)
        if type(v) == "string" then
            if not spell then return v end
            return (v:gsub("{spell}", function() return spell end))
        end
        if type(v) ~= "table" then return v end
        local out = {}
        for k, x in pairs(v) do out[k] = walk(x) end
        return out
    end
    return walk(m)
end

function B.FirstSpell(m)
    for _, l in ipairs(m.lines or {}) do
        if (l.kind == "cast" or l.kind == "use") and l.on ~= false then
            for _, v in ipairs(l.variants) do
                local s = strtrim(v.arg or "")
                if s ~= "" and not tonumber(s) then return s end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Model -> text
-------------------------------------------------------------------------------
local function CondParts(v)
    local parts = {}
    if v.target and v.target ~= "" then parts[#parts + 1] = "@" .. v.target end
    for _, d in ipairs(B.CONDS) do
        local x = v.conds and v.conds[d.key]
        if x == 1 then parts[#parts + 1] = d.key
        elseif x == 2 then parts[#parts + 1] = "no" .. d.key end
    end
    if v.stance and v.stance ~= "" then parts[#parts + 1] = "stance:" .. v.stance end
    for _, p in ipairs(v.params or {}) do
        local val = strtrim(p.value or "")
        if val ~= "" then parts[#parts + 1] = (p.no and "no" or "") .. p.key .. ":" .. val end
    end
    local x = strtrim(v.extra or "")
    if x ~= "" then parts[#parts + 1] = x end
    return parts
end

local function Bracket(parts)
    if #parts == 0 then return "" end
    return "[" .. table.concat(parts, ",") .. "]"
end

function B.LineText(l)
    local K = B.KIND[l.kind] or B.KIND.raw
    local v1 = l.variants[1] or B.NewVariant()
    if K.key == "raw" then return v1.arg or "" end
    local cmd = K.cmd
    if K.key == "chat" then cmd = "/" .. (l.chan or "say") end

    if K.arg == "spells" then
        local s = cmd
        local b = Bracket(CondParts(v1))
        if b ~= "" then s = s .. " " .. b end
        local reset = strtrim(l.reset or "")
        if K.reset and reset ~= "" then s = s .. " reset=" .. reset end
        local a = strtrim(v1.arg or "")
        if a ~= "" then s = s .. " " .. a end
        return s
    end

    local segs = {}
    for i, v in ipairs(l.variants) do
        if i > 1 and not K.multi then break end
        local b = K.conds and Bracket(CondParts(v)) or ""
        local a = K.arg and strtrim(v.arg or "") or ""
        local seg = b
        if a ~= "" then seg = (b ~= "" and (b .. " ") or "") .. a end
        if seg ~= "" then segs[#segs + 1] = seg end
    end
    if #segs == 0 then return cmd end
    return cmd .. " " .. table.concat(segs, "; ")
end

function B.Build(m, spell)
    if spell then m = B.Substitute(m, spell) end
    local out = {}
    if m.tooltip then
        local t = strtrim(m.tooltipSpell or "")
        out[1] = t ~= "" and ("#showtooltip " .. t) or "#showtooltip"
    end
    for _, l in ipairs(m.lines or {}) do
        if l.on ~= false then out[#out + 1] = B.LineText(l) end
    end
    return table.concat(out, "\n")
end

-------------------------------------------------------------------------------
--  Text -> model
-------------------------------------------------------------------------------
local function ParseConds(s, v)
    local rest = {}
    for raw in s:gmatch("[^,]+") do
        local tok = strtrim(raw)
        local noKey = tok:sub(1, 2) == "no" and tok:sub(3)
        local pKey = tok:match("^(%a+):")
        local npKey = noKey and noKey:match("^(%a+):")
        if tok:sub(1, 1) == "@" and v.target == "" then
            v.target = tok:sub(2)
        elseif COND_KEY[tok] then
            v.conds[tok] = 1
        elseif noKey and COND_KEY[noKey] then
            v.conds[noKey] = 2
        elseif pKey == "stance" and v.stance == "" then
            v.stance = tok:sub(8)
        elseif tok:match("^%a+:.+$") and (B.PARAM[pKey] or (npKey and B.PARAM[npKey])) then
            local no = not B.PARAM[pKey]
            local key, val = (no and noKey or tok):match("^(%a+):(.+)$")
            v.params[#v.params + 1] = { key = key, value = val, no = no }
        else
            rest[#rest + 1] = tok
        end
    end
    v.extra = table.concat(rest, ",")
end

local function ParseSeg(seg, v)
    local conds, a = seg:match("^%[([^%]]*)%]%s*(.*)$")
    if conds then
        ParseConds(conds, v)
        v.arg = a
    else
        v.arg = seg
    end
end

-- The order of conditions inside [...] does not matter to the game.
local function Canon(t)
    return (t:gsub("%[([^%]]*)%]", function(inner)
        local toks = {}
        for x in inner:gmatch("[^,]+") do toks[#toks + 1] = strtrim(x) end
        table.sort(toks)
        return "[" .. table.concat(toks, ",") .. "]"
    end))
end

function B.ParseLine(text)
    local t = strtrim(text)
    local l
    local cmd, rest = t:match("^(/%S+)%s*(.*)$")
    if cmd then
        cmd = cmd:lower()
        local K = BY_CMD[cmd]
        local chan = cmd:sub(2)
        if not K and CHAN_OK[chan] then K = B.KIND.chat end
        if K then
            l = B.NewLine(K.key)
            if K.key == "chat" then l.chan = chan end
            local v = l.variants[1]
            if K.arg == "spells" then
                local conds, after = rest:match("^%[([^%]]*)%]%s*(.*)$")
                if conds then ParseConds(conds, v); rest = after end
                local r, after2 = rest:match("^reset=(%S+)%s*(.*)$")
                if r and K.reset then l.reset, rest = r, after2 end
                v.arg = rest
            elseif not K.conds then
                v.arg = rest
            elseif K.multi then
                l.variants = {}
                for rawSeg in (rest .. ";"):gmatch("(.-);") do
                    local nv = B.NewVariant()
                    ParseSeg(strtrim(rawSeg), nv)
                    l.variants[#l.variants + 1] = nv
                end
                if #l.variants == 0 then l.variants[1] = B.NewVariant() end
            else
                ParseSeg(rest, v)
            end
        end
    end
    if not l or (B.LineText(l) ~= text and Canon(B.LineText(l)) ~= Canon(t)) then
        l = B.NewLine("raw", text)
    end
    return l
end

function B.Parse(body)
    local m = B.New()
    m.tooltip = false
    body = body or ""
    if body == "" then return m end
    local first = true
    for line in (body .. "\n"):gmatch("(.-)\n") do
        local tip = first and line:match("^#showtooltip ?(.*)$")
        if tip and tip == strtrim(tip) and line == (tip ~= "" and ("#showtooltip " .. tip) or "#showtooltip") then
            m.tooltip, m.tooltipSpell = true, tip
        else
            m.lines[#m.lines + 1] = B.ParseLine(line)
        end
        first = false
    end
    return m
end

-------------------------------------------------------------------------------
--  Spellbook: active spells, one entry per name ("/cast Name" uses the
--  highest rank, so ranks fold together). Scanned on demand, invalidated by
--  the Macro Manager page while it is shown.
-------------------------------------------------------------------------------
local S = {}
B.Spells = S
local list, sorted, byName = {}, {}, {}
local dirty = true

local function Scan()
    list, sorted, byName = {}, {}, {}
    local bank = Enum.SpellBookSpellBank.Player
    local spellType = Enum.SpellBookItemType.Spell
    for i = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local line = C_SpellBook.GetSpellBookSkillLineInfo(i)
        if line and not line.shouldHide then
            for slot = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
                local info = C_SpellBook.GetSpellBookItemInfo(slot, bank)
                local name = info and info.name
                if name and name ~= "" and not info.isPassive and info.itemType == spellType then
                    local s = byName[name]
                    if not s then
                        s = { name = name, icon = info.iconID, tab = line.name }
                        byName[name] = s
                        list[#list + 1] = s
                    else
                        s.icon = info.iconID or s.icon
                    end
                end
            end
        end
    end
    for i, s in ipairs(list) do sorted[i] = s end
    table.sort(sorted, function(a, b) return a.name:lower() < b.name:lower() end)
    dirty = false
end

-- Spellbook order: { { name, icon, tab } }
function S.List() if dirty then Scan() end return list end
function S.Sorted() if dirty then Scan() end return sorted end
function S.Invalidate() dirty = true end

function S.Icon(name)
    if dirty then Scan() end
    local s = byName[name]
    if s then return s.icon end
    return C_Spell.GetSpellTexture(name) or C_Item.GetItemIconByID(name)
end
