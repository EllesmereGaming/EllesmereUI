if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_SimplifiedStats.lua  (WoW Forever only)
--  Simpler stat lines on item tooltips.
--
--  shorten (on by default): rewrites the client's "Equip: Increases ..."
--  item tooltip lines (TOOLTIP_ITEM_STAT_* globals) as "+X Label"; with merge,
--  equal spell power and healing become one Spell Power line. Set bonus lines ("Set: ...",
--  "(2) Set: ...") are shortened the same way; the inactive (gray) ones stay
--  uncolored.
--  colors (off by default): the label in the stat's hue (the QoL Secondary
--  Stats hues), on shortened and already short lines ("+10 Stamina",
--  "+10 Fire Resistance", "45 Armor", "Enchanted: +7 Stamina", and the
--  comparison tooltips' stat change lines). numColor picks the figure's
--  color: "signed" (green +, red -, white unsigned), "stat" (the stat's hue)
--  or "line" (left as the line's own color).
--  Patterns and labels come from the client's own strings, so every locale
--  works. The creature-type lines (_VS_) have no short label and stay as they
--  are. Works with or without the tooltip reskin. Options: Forever
--  Essentials > General (EUI_ForeverEssentials_General_Options.lua).
-------------------------------------------------------------------------------
local _, module = ...
if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall) then return end

-- Settings live in EllesmereUIDB.simplifiedStats; unset keys read these.
local F = module.Feature("simplifiedStats",
    { shorten = true, colors = false, merge = false, numColor = "signed" })

local statRules, statLabels
-- Prefixed lines: { pat = "^(prefix)(.*)$", kind = "set" | "enchant", gray }
local prefixRules
-- Settings read once per tooltip by the hook.
local colorOn, numMode, mergeOn
local HUE = EllesmereUI.FOREVER_STAT_HUES
-- A shown tooltip is rebuilt every 0.2 s: each line's rewrite (false = left
-- as it is) is kept for the settings it was made with, so repeats are free.
local memo, memoN, MEMO_MAX = {}, 0, 2000
local mShorten, mColors, mMerge, mNum

-- A stat figure in the chosen number color; hex is the stat's hue.
local function Num(n, hex)
    if numMode == "line" then return n end
    if numMode ~= "stat" then
        local sign = n:sub(1, 1)
        hex = (sign == "+" and "1eff00") or (sign == "-" and "ff2020") or "ffffff"
    end
    return "|cff" .. hex .. n .. "|r"
end

-- "+X Label", colored when Color Stats is on.
local function Stat(n, label, hex)
    if not colorOn then return n .. " " .. label end
    return Num(n, hex) .. " |cff" .. hex .. label .. "|r"
end

-- "Equip: ... by up to %1$d." -> "^Equip: ... by up to ([%d.]+)%.$", plus
-- each positional argument's capture slot (a locale may reorder them).
local function StatPattern(fmt)
    local slot, n = {}, 0
    for a in fmt:gmatch("%%(%d)%$") do n = n + 1; slot[tonumber(a)] = n end
    local p = fmt:gsub("%%%d%$[%d.]*[dfs]", "\001"):gsub("%%%%", "%%")
    p = p:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"):gsub("\001", "([%%d.]+)")
    return "^" .. p .. "$", slot
end

-- "(%d) Set: %s" -> "^(%(%d+%) Set: )(.*)$"; nil unless the format ends in %s.
local function PrefixPattern(fmt)
    local pre = type(fmt) == "string" and fmt:match("^(.-)%%s$")
    if not pre or pre == "" then return end
    pre = pre:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"):gsub("%%%%d", "%%d+")
    return "^(" .. pre .. ")(.*)$"
end

local function BuildStatRules()
    statRules = {}
    prefixRules = {}
    -- label text -> hue, for the short lines
    statLabels = {}
    for _, f in ipairs({ { ITEM_SET_BONUS, "set" }, { ITEM_SET_BONUS_GRAY, "set", true },
                         { ENCHANTED_TOOLTIP_LINE, "enchant" } }) do
        local pat = PrefixPattern(f[1])
        if pat then prefixRules[#prefixRules + 1] = { pat = pat, kind = f[2], gray = f[3] } end
    end
    -- The "Equip: " every stat format starts with; set bonuses carry the rest.
    local equip = type(ITEM_SPELL_TRIGGER_ONEQUIP) == "string" and ITEM_SPELL_TRIGGER_ONEQUIP
    local SP, HEAL, GRAY, AVOID = HUE.sp, HUE.healing, HUE.armor, HUE.avoid
    -- outs: { argument, sign, label global, hex }, one output line each.
    -- merge: a spell damage + healing rule that Merge folds into Spell Power.
    local function Rule(key, outs, merge)
        local fmt = _G["TOOLTIP_ITEM_STAT_" .. key]
        if type(fmt) ~= "string" then return end
        local labels = {}
        for i, o in ipairs(outs) do
            local label = _G[o[3]]
            if type(label) ~= "string" then return end
            labels[i] = label
        end
        -- comparison delta lines ("+12 Spell Damage") use these labels too
        for i, o in ipairs(outs) do statLabels[labels[i]] = o[4] end
        local pat, slot = StatPattern(fmt)
        local barePat
        if equip and fmt:find(equip, 1, true) == 1 then
            barePat = StatPattern((fmt:sub(#equip + 1):gsub("^%s+", "")))
        end
        statRules[#statRules + 1] = { pat = pat, barePat = barePat, slot = slot, outs = outs, labels = labels,
            pct = fmt:find("%%%%") and "%" or "",
            merge = merge and type(ITEM_MOD_SPELL_POWER_SHORT) == "string" or nil }
    end
    local function Pair(key, label, hex, label2, hex2)
        for _, d in ipairs({ { "+", "_INCREASE" }, { "-", "_DECREASE" } }) do
            local outs = { { 1, d[1], label, hex } }
            if label2 then outs[2] = { 1, d[1], label2, hex2 } end
            Rule(key .. d[2], outs, label2 ~= nil)
        end
    end
    -- One figure for damage and healing: Spell Damage + Spell Healing, or one
    -- Spell Power line with Merge.
    Pair("SPELL_POWER", "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT", SP, "ITEM_MOD_SPELL_HEALING_DONE_SHORT", HEAL)
    Pair("SPELL_DAMAGE", "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT", SP)
    Pair("SPELL_HEALING", "ITEM_MOD_SPELL_HEALING_DONE_SHORT", HEAL)
    -- "healing done by up to %1$d and damage done by up to %2$d"
    for _, h in ipairs({ { "+", "INCREASE" }, { "-", "DECREASE" } }) do
        for _, d in ipairs({ { "+", "INCREASE" }, { "-", "DECREASE" } }) do
            Rule("SPELL_HEALING_" .. h[2] .. "_DAMAGE_" .. d[2], {
                { 2, d[1], "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT", SP },
                { 1, h[1], "ITEM_MOD_SPELL_HEALING_DONE_SHORT", HEAL },
            }, true)
        end
    end
    for _, s in ipairs({ { "HOLY", HUE.holy }, { "FIRE", HUE.fire }, { "FROST", HUE.frost },
                         { "NATURE", HUE.nature }, { "SHADOW", HUE.shadow }, { "ARCANE", HUE.arcane } }) do
        Pair(s[1] .. "_DAMAGE", "ITEM_MOD_" .. s[1] .. "_DAMAGE_DONE_SHORT", s[2])
        Pair(s[1] .. "_PENETRATION", "ITEM_MOD_" .. s[1] .. "_PENETRATION_SHORT", s[2])
    end
    Pair("SPELL_PENETRATION", "ITEM_MOD_SPELL_PENETRATION_SHORT", HUE.spen)
    Pair("ARMOR_PENETRATION", "ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT", GRAY)
    Pair("ATTACK_POWER", "ITEM_MOD_ATTACK_POWER_SHORT", HUE.ap)
    Pair("RANGED_ATTACK_POWER", "ITEM_MOD_RANGED_ATTACK_POWER_SHORT", HUE.ap)
    Pair("CRIT_PERCENT", "ITEM_MOD_CRIT_RATING_SHORT", HUE.crit)
    Pair("HIT_PERCENT", "ITEM_MOD_HIT_RATING_SHORT", HUE.hit)
    Pair("EXPERTISE_PCT", "ITEM_MOD_EXPERTISE_RATING_SHORT", HUE.hit)
    Pair("HASTE_PCT", "ITEM_MOD_HASTE_RATING_SHORT", HUE.haste)
    Pair("DEFENSE", "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT", GRAY)
    Pair("DODGE_PCT", "ITEM_MOD_DODGE_RATING_SHORT", AVOID)
    Pair("PARRY_PCT", "ITEM_MOD_PARRY_RATING_SHORT", AVOID)
    Pair("BLOCK_CHANCE", "ITEM_MOD_BLOCK_RATING_SHORT", AVOID)
    Pair("BLOCK_VALUE", "ITEM_MOD_BLOCK_VALUE_SHORT", AVOID)
    Pair("MANA_REGEN", "ITEM_MOD_POWER_REGEN0_SHORT", HUE.mp5)
    Pair("HEALTH_REGEN", "ITEM_MOD_HEALTH_REGEN_SHORT", HUE.hp5)
    -- TOOLTIP_ITEM_STAT_SKILL_<k> -> ITEM_MOD_<v>_SHORT
    for k, v in pairs({
        ALCHEMY = "ALCHEMY", AXES = "AXES", BLACKSMITHING = "BLACKSMITHING", BOWS = "BOWS",
        COOKING = "COOKING", CROSSBOWS = "CROSSBOWS", DAGGERS = "DAGGERS",
        DUAL_WIELDING = "DUAL_WIELD", ENCHANTING = "ENCHANTING", ENGINEERING = "ENGINEERING",
        FIRST_AID = "FIRST_AID", FISHING = "FISHING", FIST_WEAPONS = "FIST_WEAPONS",
        GUNS = "GUNS", HERBALISM = "HERBALISM", JEWELCRAFTING = "JEWELCRAFTING",
        LEATHERWORKING = "LEATHERWORKING", MACES = "MACES", MINING = "MINING",
        POLEARMS = "POLEARMS", SKINNING = "SKINNING", STAVES = "STAVES", SWORDS = "SWORDS",
        TAILORING = "TAILORING", THROWN_WEAPONS = "THROWN", WANDS = "WANDS",
    }) do
        Pair("SKILL_" .. k, "ITEM_MOD_" .. v .. "_SHORT", GRAY)
    end

    local function Name(label, hex)
        if type(label) == "string" and label ~= "" then statLabels[label] = hex end
    end
    -- The label a format leaves once its sign and number are removed.
    local function Label(fmt, hex, ...)
        if type(fmt) ~= "string" then return end
        local f = fmt:gsub("%%%d%$", "%%"):gsub("%%c", "")
        local ok, sample = pcall(string.format, f, 0, ...)
        if not ok then return end
        Name(sample:gsub("[%+%-]?0", "", 1):match("^%s*(.-)%s*$"), hex)
    end
    for _, a in ipairs({ { "STRENGTH", HUE.str }, { "AGILITY", HUE.agi }, { "STAMINA", HUE.sta },
                         { "INTELLECT", HUE.int }, { "SPIRIT", HUE.spi }, { "HEALTH", HUE.health },
                         { "MANA", HUE.mana } }) do
        Name(_G["ITEM_MOD_" .. a[1] .. "_SHORT"], a[2])
        Label(_G["ITEM_MOD_" .. a[1]], a[2])
    end
    -- RESISTANCE<i>_NAME and SPELL_SCHOOL<i>_CAP share indices 1-6
    for i, hex in ipairs({ HUE.holy, HUE.fire, HUE.nature, HUE.frost, HUE.shadow, HUE.arcane }) do
        Name(_G["RESISTANCE" .. i .. "_NAME"], hex)
        Label(ITEM_RESIST_SINGLE, hex, _G["SPELL_SCHOOL" .. i .. "_CAP"])
    end
    Label(ITEM_RESIST_ALL, HUE.spen)
    Label(TOOLTIP_ITEM_STAT_SPELL_RESISTANCE_ALL_SCHOOLS_INCREASE, HUE.spen)
    -- The merged Spell Power line's label, also on comparison stat changes.
    Name(ITEM_MOD_SPELL_POWER_SHORT, SP)
    Name(ARMOR, GRAY)
    Label(ARMOR_TEMPLATE, GRAY)
    Label(TOOLTIP_ITEM_STAT_ARMOR_INCREASE, GRAY)
    Label(SHIELD_BLOCK_TEMPLATE, AVOID)
end

-- The figures of the label ColorStatLabel colors, in its hue.
local labelHex
local function LabelNum(n) return Num(n, labelHex) end

-- A short line with its label colored, or nil when the line is not a
-- known label and a number.
local function ColorStatLabel(text)
    for label, hex in pairs(statLabels) do
        local s, e = text:find(label, 1, true)
        if s then
            local before, after = text:sub(1, s - 1), text:sub(e + 1)
            if (before .. after):match("^%s*[%+%-]?[%d,.]+%%?%s*$") then
                local num = "[%+%-]?[%d,.]+%%?"
                labelHex = hex
                return (before:gsub(num, LabelNum)) .. "|cff" .. hex .. label .. "|r" .. (after:gsub(num, LabelNum))
            end
        end
    end
end

-- The simplified text for one tooltip line, or nil when no rule matches.
-- bare: the text has no "Equip: " (a set bonus).
local function SimplifyStatLine(text, bare)
    for _, r in ipairs(statRules) do
        local pat = bare and r.barePat or (not bare and r.pat)
        -- At most two figures per format (the healing + damage lines).
        local c1, c2
        if pat then c1, c2 = text:match(pat) end
        if c1 then
            local out = {}
            for i, o in ipairs(r.outs) do
                out[i] = o[2] .. ((r.slot[o[1]] == 2) and c2 or c1) .. r.pct
            end
            if mergeOn and r.merge and out[1] == out[2] then
                return Stat(out[1], ITEM_MOD_SPELL_POWER_SHORT, r.outs[1][4])
            end
            for i, o in ipairs(r.outs) do
                out[i] = Stat(out[i], r.labels[i], o[4])
            end
            return table.concat(out, "\n")
        end
    end
end

-- The set bonus prefix PrefixedLine repeats on every output line.
local linePre
local function PrefixNewline() return "\n" .. linePre end

-- A set bonus or enchant line, rewritten after its prefix; false when the
-- line has a prefix but nothing to change, nil when it has none.
local function PrefixedLine(text, shortenOn)
    for _, p in ipairs(prefixRules) do
        local pre, inner = text:match(p.pat)
        if pre then
            local out
            if p.kind == "set" then
                if shortenOn then
                    local c = colorOn
                    if p.gray then colorOn = false end
                    out = SimplifyStatLine(inner, true)
                    colorOn = c
                    -- every output line keeps the prefix
                    if out then
                        linePre = pre
                        out = pre .. out:gsub("\n", PrefixNewline)
                    end
                end
            elseif colorOn then
                out = ColorStatLabel(inner)
                if out then out = pre .. out end
            end
            return out or false
        end
    end
end

local function SimplifyStatsHook(tooltip)
    local shortenOn, colors = F.Get("shorten"), F.Get("colors")
    if not (shortenOn or colors) then return end
    if not tooltip or not tooltip.GetName then return end
    local ok, name = pcall(tooltip.GetName, tooltip)
    if not ok or not name then return end
    if not statRules then BuildStatRules() end
    local equip = ITEM_SPELL_TRIGGER_ONEQUIP
    if type(equip) ~= "string" then return end
    colorOn, numMode, mergeOn = colors, F.Get("numColor"), F.Get("merge")
    -- Every input of a rewrite but the text: a change starts the memo over.
    if shortenOn ~= mShorten or colorOn ~= mColors or mergeOn ~= mMerge or numMode ~= mNum then
        wipe(memo)
        memoN = 0
        mShorten, mColors, mMerge, mNum = shortenOn, colorOn, mergeOn, numMode
    end
    local changed
    for i = 2, tooltip:NumLines() do
        local fs = _G[name .. "TextLeft" .. i]
        local text = fs and fs:GetText()
        if text and not issecretvalue(text) then
            local isEquip = text:find(equip, 1, true) == 1
            if isEquip or text:find("%d") then
                local new = memo[text]
                if new == nil then
                    if isEquip then
                        if shortenOn then new = SimplifyStatLine(text) end
                    else
                        new = PrefixedLine(text, shortenOn)
                        if new == nil and colorOn then new = ColorStatLabel(text) end
                    end
                    if memoN >= MEMO_MAX then
                        wipe(memo)
                        memoN = 0
                    end
                    memo[text] = new or false
                    memoN = memoN + 1
                end
                if new then
                    fs:SetText(new)
                    changed = true
                end
            end
        end
    end
    if changed then tooltip:Show() end
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, SimplifyStatsHook)

-- The comparison tooltips' stat change lines ("If you replace this item...")
-- are added after the item post-call ran; rerun the pass once they are in.
-- Already rewritten lines no longer match, so the rerun leaves them alone.
if TooltipComparisonManager and TooltipComparisonManager.SetItemTooltip then
    hooksecurefunc(TooltipComparisonManager, "SetItemTooltip", function(mgr, isPrimaryTooltip)
        local tips = mgr.tooltip and mgr.tooltip.shoppingTooltips
        local tip = tips and tips[isPrimaryTooltip and 1 or 2]
        if tip then SimplifyStatsHook(tip) end
    end)
end

-- Options-page entry points.
EllesmereUI._SimplifiedStats = {
    Get = F.Get,
    Cfg = F.Cfg,
}
