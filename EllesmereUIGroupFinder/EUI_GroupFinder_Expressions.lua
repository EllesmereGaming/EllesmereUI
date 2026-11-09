if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  expressions.lua - type a filter like "hasBL and hasBR and healer > 0"
--  our own little language, parsed into closures: nothing typed ever runs
--  as lua. saved as extraExpr
-------------------------------------------------------------------------------
local FOLDER, ns = ...
if EllesmereUI.HELD_BACK_ADDONS[FOLDER] then return end -- held back (EllesmereUIGroupFinder.lua)
local GFNS = ns
local CM = ns.EUI

local EXPR_TEX = "Interface\\AddOns\\" .. FOLDER .. "\\media\\icons\\eui-expression.png"
local Secret = EllesmereUI.IsSecret
local function Readable(t) return type(t) == "table" and not Secret(t) and not (canaccesstable and not canaccesstable(t)) end

-------------------------------------------------------------------------------
--  words you can use (any case)
-------------------------------------------------------------------------------
local CLASS_WORDS = {
    warrior = "WARRIOR", paladin = "PALADIN", hunter = "HUNTER", rogue = "ROGUE", priest = "PRIEST",
    deathknight = "DEATHKNIGHT", dk = "DEATHKNIGHT", shaman = "SHAMAN", mage = "MAGE", warlock = "WARLOCK",
    monk = "MONK", druid = "DRUID", demonhunter = "DEMONHUNTER", dh = "DEMONHUNTER", evoker = "EVOKER",
}
local WORDS = {
    tank = "tanks", healer = "healers", dps = "dps", members = "members",
    tankopen = "tanksLeft", healeropen = "healersLeft", dpsopen = "dpsLeft",
    hasbl = "hasBL", hasbr = "hasBR", myclass = "myClass",
    score = "score", ilvl = "ilvl", age = "age", friends = "friends", voice = "voice",
}
for w, cls in pairs(CLASS_WORDS) do WORDS[w] = cls end
local LUST = { SHAMAN = true, MAGE = true, HUNTER = true, EVOKER = true }
local BREZ = { DRUID = true, DEATHKNIGHT = true, WARLOCK = true, PALADIN = true }

-------------------------------------------------------------------------------
--  tokens
-------------------------------------------------------------------------------
local TWO = { ["<="] = "<=", [">="] = ">=", ["=="] = "==", ["~="] = "!=", ["!="] = "!=", ["&&"] = "and", ["||"] = "or" }
local ONE = { ["+"] = "+", ["-"] = "-", ["*"] = "*", ["/"] = "/", ["("] = "(", [")"] = ")",
    ["<"] = "<", [">"] = ">", ["="] = "==", ["!"] = "not" }
local KEYWORDS = { ["and"] = "and", ["or"] = "or", ["not"] = "not" }

local function Tokens(src)
    local out, i, n = {}, 1, #src
    while i <= n do
        local c = src:sub(i, i)
        if c:match("%s") then
            i = i + 1
        else
            local num = src:match("^%d+%.?%d*", i) or src:match("^%.%d+", i)
            local word = not num and src:match("^[%a_][%w_]*", i)
            local two = src:sub(i, i + 1)
            if num then
                out[#out + 1] = { t = "num", v = tonumber(num) }
                i = i + #num
            elseif word then
                local lw = word:lower()
                if KEYWORDS[lw] then out[#out + 1] = { t = KEYWORDS[lw] }
                elseif lw == "true" or lw == "false" then out[#out + 1] = { t = "num", v = lw == "true" and 1 or 0 }
                elseif WORDS[lw] then out[#out + 1] = { t = "var", v = WORDS[lw] }
                else return nil, EllesmereUI.Lf("unknown word: %1$s", word) end
                i = i + #word
            elseif TWO[two] then
                out[#out + 1] = { t = TWO[two] }
                i = i + 2
            elseif ONE[c] then
                out[#out + 1] = { t = ONE[c] }
                i = i + 1
            else
                return nil, EllesmereUI.Lf("can't use \"%1$s\"", c)
            end
        end
    end
    return out
end

-------------------------------------------------------------------------------
--  parser: each rule returns function(env) -> number (true = 1).
--  a word we can't read for a group throws, and the group is kept
-------------------------------------------------------------------------------
local UNREADABLE = {}
local function Truth(v) return v ~= 0 end

local function Compile(src)
    local toks, err = Tokens(src)
    if not toks then return nil, err end
    if #toks == 0 then return nil end
    local pos = 1
    local function peek() return toks[pos] and toks[pos].t end
    local function take() pos = pos + 1; return toks[pos - 1] end

    local Or
    local function Primary()
        local tk = take()
        if not tk then error(EllesmereUI.L("ends too soon"), 0) end
        if tk.t == "num" then
            local v = tk.v
            return function() return v end
        elseif tk.t == "var" then
            local k = tk.v
            return function(env)
                local v = env[k]
                if v == nil then error(UNREADABLE, 0) end
                return v
            end
        elseif tk.t == "(" then
            local f = Or()
            if take() == nil or toks[pos - 1].t ~= ")" then error(EllesmereUI.L("missing )"), 0) end
            return f
        end
        error(EllesmereUI.Lf("unexpected \"%1$s\"", tk.t), 0)
    end
    local function Unary()
        if peek() == "-" then
            take()
            local f = Unary()
            return function(env) return -f(env) end
        end
        return Primary()
    end
    local function Mul()
        local f = Unary()
        while peek() == "*" or peek() == "/" do
            local op, a, b = take().t, f, Unary()
            if op == "*" then f = function(env) return a(env) * b(env) end
            else f = function(env) local d = b(env); return d == 0 and 0 or a(env) / d end end
        end
        return f
    end
    local function Add()
        local f = Mul()
        while peek() == "+" or peek() == "-" do
            local op, a, b = take().t, f, Mul()
            if op == "+" then f = function(env) return a(env) + b(env) end
            else f = function(env) return a(env) - b(env) end end
        end
        return f
    end
    local CMP = {
        ["<"] = function(x, y) return x < y end, [">"] = function(x, y) return x > y end,
        ["<="] = function(x, y) return x <= y end, [">="] = function(x, y) return x >= y end,
        ["=="] = function(x, y) return x == y end, ["!="] = function(x, y) return x ~= y end,
    }
    local function Cmp()
        local f = Add()
        local test = CMP[peek() or ""]
        if test then
            take()
            local a, b = f, Add()
            f = function(env) return test(a(env), b(env)) and 1 or 0 end
        end
        return f
    end
    local function Not()
        if peek() == "not" then
            take()
            local f = Not()
            return function(env) return Truth(f(env)) and 0 or 1 end
        end
        return Cmp()
    end
    local function And()
        local f = Not()
        while peek() == "and" do
            take()
            local a, b = f, Not()
            f = function(env) return (Truth(a(env)) and Truth(b(env))) and 1 or 0 end
        end
        return f
    end
    Or = function()
        local f = And()
        while peek() == "or" do
            take()
            local a, b = f, And()
            f = function(env) return (Truth(a(env)) or Truth(b(env))) and 1 or 0 end
        end
        return f
    end

    local ok, f = pcall(Or)
    if not ok then return nil, f end
    if pos <= #toks then return nil, EllesmereUI.Lf("unexpected \"%1$s\"", toks[pos].t) end
    return f
end

-------------------------------------------------------------------------------
--  the saved expression, recompiled when it changes
-------------------------------------------------------------------------------
local compiled, compiledFor, compileErr

local function Current()
    local c = GFNS.Cfg and GFNS.Cfg()
    local text = c and c.extraExpr
    if text ~= compiledFor then
        compiledFor = text
        compiled, compileErr = nil, nil
        if type(text) == "string" and text:find("%S") then compiled, compileErr = Compile(text) end
    end
    return compiled, compileErr
end

GFNS.ExtraExprActive = function() return Current() ~= nil end

-- one group's words, nil when the game hides one
local env = {}
local function Fill(id, info)
    wipe(env)
    local function num(v) if type(v) == "number" and not Secret(v) then return v end end
    local counts = C_LFGList.GetSearchResultMemberCounts(id)
    if Readable(counts) then
        env.tanks, env.healers, env.dps = num(counts.TANK), num(counts.HEALER), num(counts.DAMAGER)
        env.tanksLeft, env.healersLeft = num(counts.TANK_REMAINING), num(counts.HEALER_REMAINING)
        env.dpsLeft = num(counts.DAMAGER_REMAINING)
    end
    local n = num(info.numMembers)
    env.members = n
    if n then
        local _, mine = UnitClass("player")
        local lust, brez, same, all = 0, 0, 0, true
        for _, cls in pairs(CLASS_WORDS) do env[cls] = 0 end
        for i = 1, n do
            local p = C_LFGList.GetSearchResultPlayerInfo(id, i)
            local cls = Readable(p) and p.classFilename
            if cls and not Secret(cls) then
                env[cls] = (env[cls] or 0) + 1
                if LUST[cls] then lust = 1 end
                if BREZ[cls] then brez = 1 end
                if cls == mine then same = same + 1 end
            else
                all = false
            end
        end
        -- unreadable member: class words can't be trusted
        if all then
            env.hasBL, env.hasBR, env.myClass = lust, brez, same
        else
            for _, cls in pairs(CLASS_WORDS) do env[cls] = nil end
        end
    end
    env.score = num(info.leaderOverallDungeonScore)
    env.ilvl = num(info.requiredItemLevel)
    local age = num(info.age)
    env.age = age and math.floor(age / 60)
    local f1, f2, f3 = num(info.numBNetFriends), num(info.numCharFriends), num(info.numGuildMates)
    if f1 and f2 and f3 then env.friends = f1 + f2 + f3 end
    local vc = info.voiceChat
    if not Secret(vc) then env.voice = (type(vc) == "string" and vc ~= "") and 1 or 0 end
end

GFNS.ExtraExprKeep = function(id, info)
    local f = Current()
    if not f or not Readable(info) then return true end
    Fill(id, info)
    local ok, v = pcall(f, env)
    if not ok then return true end  -- a word this group hides: keep it
    return Truth(v)
end

-------------------------------------------------------------------------------
--  the button and its box
-------------------------------------------------------------------------------
-- the reference under the box: hover a tag for help, click to type it
local SECTIONS = {
    { title = EllesmereUI.L("Words"), boxes = {
        { title = EllesmereUI.L("Open Slots"), color = { 0.35, 0.65, 1 }, cols = 1, examples = {
            { "tankOpen >= 1", EllesmereUI.L("room for a tank") },
            { "healerOpen > 0 and dpsOpen > 0", EllesmereUI.L("room for a healer and a dps") },
            { "dpsOpen == 3", EllesmereUI.L("still needs all three dps") } }, tags = {
            { "tankOpen", EllesmereUI.L("Tank spots still open.") },
            { "healerOpen", EllesmereUI.L("Healer spots still open.") },
            { "dpsOpen", EllesmereUI.L("DPS spots still open.") } } },
        { title = EllesmereUI.L("Roles"), color = { 0.3, 0.85, 0.5 }, cols = 2, examples = {
            { "tank == 1 and healer == 1", EllesmereUI.L("has its tank and healer") },
            { "members <= 3", EllesmereUI.L("three players or fewer so far") },
            { "myClass == 0", EllesmereUI.L("nobody of your class yet") },
            { "mage >= 1 or priest >= 1", EllesmereUI.L("has a mage or a priest") },
            { "dk + dh == 0", EllesmereUI.L("no death knight or demon hunter") } }, tags = {
            { "tank", EllesmereUI.L("Tanks in the group.") },
            { "healer", EllesmereUI.L("Healers in the group.") },
            { "dps", EllesmereUI.L("DPS in the group.") },
            { "mage", EllesmereUI.L("Any class name counts that class: mage, druid, priest, dk, dh...") },
            { "members", EllesmereUI.L("Players in the group."), span = true },
            { "myClass", EllesmereUI.L("Members of your own class."), span = true } } },
        { title = EllesmereUI.L("Group"), color = { 0.72, 0.52, 1 }, cols = 2, examples = {
            { "hasBL and hasBR", EllesmereUI.L("has bloodlust and a battle res") },
            { "score >= 2500", EllesmereUI.L("leader has 2500 score or more") },
            { "age <= 5", EllesmereUI.L("listed in the last five minutes") },
            { "friends > 0", EllesmereUI.L("a friend or guildmate is in it") },
            { "not voice", EllesmereUI.L("no voice chat listed") } }, tags = {
            { "hasBL", EllesmereUI.L("1 when someone can Bloodlust / Heroism.") },
            { "hasBR", EllesmereUI.L("1 when someone can battle res.") },
            { "score", EllesmereUI.L("The leader's Mythic+ score.") },
            { "ilvl", EllesmereUI.L("The group's required item level.") },
            { "age", EllesmereUI.L("Minutes since the group was listed.") },
            { "friends", EllesmereUI.L("Your friends and guildmates in the group.") },
            { "voice", EllesmereUI.L("1 when the group lists voice chat.") } } },
    } },
    { title = EllesmereUI.L("Syntax"), boxes = {
        { title = EllesmereUI.L("Math"), color = { 1, 0.55, 0.2 }, examples = {
            { "tank + healer == 2", EllesmereUI.L("has both a tank and a healer") },
            { "5 - members >= 2", EllesmereUI.L("at least two spots left") },
            { "mage + priest + druid >= 2", EllesmereUI.L("two or more of those classes") },
            { "(tank + healer) == 0", EllesmereUI.L("no tank or healer yet") } }, tags = {
            { "+", EllesmereUI.L("Add.") }, { "-", EllesmereUI.L("Subtract.") }, { "*", EllesmereUI.L("Multiply.") }, { "/", EllesmereUI.L("Divide.") },
            { "(", EllesmereUI.L("Group a part together.") }, { ")", EllesmereUI.L("Close the group.") } } },
        { title = EllesmereUI.L("Comparisons"), color = { 1, 0.8, 0.2 }, examples = {
            { "score > 2000", EllesmereUI.L("more than 2000") },
            { "healer != 0", EllesmereUI.L("any healer at all") },
            { "dps >= 1 and dps <= 2", EllesmereUI.L("one or two dps") },
            { "hasBL or hasBR", EllesmereUI.L("either one is enough") },
            { "not hasBL", EllesmereUI.L("no bloodlust") } }, tags = {
            { ">", EllesmereUI.L("More than.") }, { "<", EllesmereUI.L("Less than.") }, { ">=", EllesmereUI.L("At least.") }, { "<=", EllesmereUI.L("At most.") },
            { "==", EllesmereUI.L("Exactly.") }, { "!=", EllesmereUI.L("Anything but.") },
            { "and", EllesmereUI.L("Both sides must be true.") }, { "or", EllesmereUI.L("Either side is enough.") },
            { "not", EllesmereUI.L("Flips true and false.") } } },
    } },
}
-- color words like their tags, unknown ones red
local HUE = {}
do
    local byKey = {}
    for _, sec in ipairs(SECTIONS) do
        for _, bx in ipairs(sec.boxes) do
            for _, tg in ipairs(bx.tags) do
                local w = tg[1]:lower()
                HUE[w] = bx.color
                if WORDS[w] then byKey[WORDS[w]] = bx.color end
            end
        end
    end
    for w, key in pairs(WORDS) do HUE[w] = HUE[w] or byKey[key] end
    local cmp = HUE[">"]
    for _, op in ipairs({ "=", "~=", "&&", "||", "!" }) do HUE[op] = cmp end
end
local function Hex(c) return string.format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255) end
local BAD_HEX = EllesmereUI.COLOR_CODES.BAD

local function Colorize(text)
    local out, i, n = {}, 1, #text
    while i <= n do
        local c = text:sub(i, i)
        local word = text:match("^[%a_][%w_]*", i)
        local num = not word and (text:match("^%d+%.?%d*", i) or text:match("^%.%d+", i))
        local two = text:sub(i, i + 1)
        local piece, hue
        if word then
            piece = word
            local lw = word:lower()
            hue = HUE[lw]
            if not hue and lw ~= "true" and lw ~= "false" then hue = "bad" end
        elseif num then
            piece = num
        elseif HUE[two] then
            piece, hue = two, HUE[two]
        elseif c:match("%s") then
            piece = c
        else
            piece, hue = c, HUE[c] or "bad"
        end
        local shown = piece:gsub("|", "||")
        if hue == "bad" then out[#out + 1] = BAD_HEX .. shown .. "|r"
        elseif hue then out[#out + 1] = Hex(hue) .. shown .. "|r"
        else out[#out + 1] = shown end
        i = i + #piece
    end
    return table.concat(out)
end

local TAG_H, TAG_PAD, TAG_GAP, BOX_PAD, BOX_GAP = 16, 6, 4, 6, 6
local VPAD, ROW_GAP = 6, 8  -- group padding, gap between untitled rows

-- a tag: small tinted box
local function Tag(parent, K, spec, color, onClick)
    local t = CreateFrame("Button", nil, parent)
    t:SetHeight(TAG_H)
    local r, g, b = color[1], color[2], color[3]
    t.fill = t:CreateTexture(nil, "BACKGROUND")
    t.fill:SetAllPoints()
    t.fill:SetColorTexture(r, g, b, 0.14)
    CM.MakeBorder(t, r, g, b, 0.45, CM.PanelPP)
    t.text = t:CreateFontString(nil, "OVERLAY")
    K.Font(t.text, 9)
    t.text:SetPoint("CENTER", 0, 0)
    t.text:SetText(spec[1])
    t.text:SetTextColor(r, g, b, 1)
    t.minW = math.ceil(t.text:GetStringWidth()) + TAG_PAD * 2
    t:SetWidth(t.minW)
    t:SetScript("OnEnter", function(self)
        self.fill:SetColorTexture(r, g, b, 0.3)
        K.Tip(self, spec[1], spec[2])
    end)
    t:SetScript("OnLeave", function(self)
        self.fill:SetColorTexture(r, g, b, 0.14)
        K.Untip()
    end)
    t:SetScript("OnClick", function() onClick(spec[1]) end)
    t.span = spec.span
    return t
end

-- builds the sections once, layout(width) places them
local function BuildHelp(panel, K, onClick)
    local help = { sections = {} }
    for _, sec in ipairs(SECTIONS) do
        local S = { boxes = {} }
        if sec.title then
            S.title = panel:CreateFontString(nil, "OVERLAY")
            K.Font(S.title, 9)
            S.title:SetTextColor(0.55, 0.55, 0.55, 1)
            S.title:SetText(sec.title)
        end
        for _, spec in ipairs(sec.boxes) do
            local bx = CreateFrame("Frame", nil, panel)
            local shade = bx:CreateTexture(nil, "BACKGROUND")
            shade:SetAllPoints()
            shade:SetColorTexture(0, 0, 0, 0.22)
            if spec.title then
                bx.title = bx:CreateFontString(nil, "OVERLAY")
                K.Font(bx.title, 8)
                bx.title:SetPoint("TOPLEFT", bx, "TOPLEFT", BOX_PAD, -VPAD)
                bx.title:SetTextColor(spec.color[1], spec.color[2], spec.color[3], 0.8)
                bx.title:SetText(spec.title:upper())
                if spec.examples then
                    -- "?" next to the name: hover for examples
                    local q = CreateFrame("Frame", nil, bx)
                    q:SetSize(12, 12)
                    q:SetPoint("LEFT", bx.title, "RIGHT", 3, 0)
                    q:EnableMouse(true)
                    local qt = q:CreateFontString(nil, "OVERLAY")
                    K.Font(qt, 9)
                    qt:SetPoint("CENTER", 0, 0)
                    qt:SetText("?")
                    qt:SetTextColor(0.6, 0.6, 0.6, 1)
                    q:SetScript("OnEnter", function(self)
                        qt:SetTextColor(1, 1, 1, 1)
                        local lines = {}
                        for _, ex in ipairs(spec.examples) do
                            -- starts with a color code so the tooltip keeps our colors
                            lines[#lines + 1] = "|cffffffff|r" .. Colorize(ex[1]) .. "   " .. EllesmereUI.COLOR_CODES.DIM .. ex[2] .. "|r"
                        end
                        K.Tip(self, EllesmereUI.Lf("%1$s Examples", spec.title), unpack(lines))
                    end)
                    q:SetScript("OnLeave", function()
                        qt:SetTextColor(0.6, 0.6, 0.6, 1)
                        K.Untip()
                    end)
                end
            end
            bx.cols = spec.cols
            bx.tags = {}
            for _, tg in ipairs(spec.tags) do bx.tags[#bx.tags + 1] = Tag(bx, K, tg, spec.color, onClick) end
            if spec.text then
                bx.plain = bx:CreateFontString(nil, "OVERLAY")
                K.Font(bx.plain, 9)
                bx.plain:SetJustifyH("LEFT")
                bx.plain:SetTextColor(spec.color[1], spec.color[2], spec.color[3], 1)
                bx.plain:SetText(spec.text)
            end
            S.boxes[#S.boxes + 1] = bx
        end
        help.sections[#help.sections + 1] = S
    end

    -- tags wrap left to right, returns the height
    local function FlowBox(bx, w)
        local top = bx.title and (VPAD + 10 + 4) or VPAD
        if bx.plain then
            bx.plain:ClearAllPoints()
            bx.plain:SetPoint("TOPLEFT", bx, "TOPLEFT", BOX_PAD + 2, -top - 2)
            bx.plain:SetWidth(w - BOX_PAD * 2 - 2)
            return top + 2 + math.max(12, math.ceil(bx.plain:GetStringHeight())) + VPAD
        end
        if bx.cols then
            local cw = math.floor((w - BOX_PAD * 2 - (bx.cols - 1) * TAG_GAP) / bx.cols)
            local col, row = 0, 0
            for _, t in ipairs(bx.tags) do
                local span = t.span and bx.cols or 1
                if col > 0 and col + span > bx.cols then col, row = 0, row + 1 end
                t:SetWidth(cw * span + TAG_GAP * (span - 1))
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", bx, "TOPLEFT", BOX_PAD + col * (cw + TAG_GAP), -(top + row * (TAG_H + TAG_GAP)))
                col = col + span
                if col >= bx.cols then col, row = 0, row + 1 end
            end
            if col == 0 then row = row - 1 end
            return top + (row + 1) * (TAG_H + TAG_GAP) - TAG_GAP + VPAD
        end
        local x, y = BOX_PAD, top
        for _, t in ipairs(bx.tags) do
            local tw = t:GetWidth()
            if x > BOX_PAD and x + tw > w - BOX_PAD then x, y = BOX_PAD, y + TAG_H + TAG_GAP end
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", bx, "TOPLEFT", x, -y)
            x = x + tw + TAG_GAP
        end
        return y + TAG_H + VPAD
    end

    -- the last row grows into the leftover height
    function help.Layout(anchor, width, fill)
        local y = 0
        for si, S in ipairs(help.sections) do
            if S.title then
                S.title:ClearAllPoints()
                S.title:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -y - 8)
                y = y + 8 + 14
            else
                y = y + ROW_GAP
            end
            local n = #S.boxes
            local bw = math.floor((width - (n - 1) * BOX_GAP) / n)
            local rowH = 0
            for i, bx in ipairs(S.boxes) do
                bx:SetWidth(bw)
                rowH = math.max(rowH, FlowBox(bx, bw))
                bx:ClearAllPoints()
                bx:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", (i - 1) * (bw + BOX_GAP), -y)
            end
            if si == #help.sections and fill and fill > y + rowH then rowH = fill - y end
            for _, bx in ipairs(S.boxes) do bx:SetHeight(rowH) end
            y = y + rowH
        end
        return y
    end
    return help
end

local btn, panel, box, status, hint, shown
local function Paint(K)
    if not btn then return end
    local f, err = Current()
    if f then btn.Glyph:SetVertexColor(K.Accent()) else btn.Glyph:SetVertexColor(K.GLYPH, K.GLYPH, K.GLYPH) end
    btn.activeEdge:SetShown(f ~= nil)
    if shown and box then shown:SetText(Colorize(box:GetText())) end
    if not status then return end
    local text = box and box:GetText() or ""
    if hint then hint:SetShown(text == "") end
    if not text:find("%S") then
        status:SetText("")
    elseif f then
        status:SetText("|cff66dd66" .. EllesmereUI.L("Filtering with this expression.") .. "|r")
    else
        status:SetText(BAD_HEX .. (err or EllesmereUI.L("can't read that")) .. "|r")
    end
end

local function Build(SP, K)
    btn = K.GlyphButton(SP, K.ROW1_H, EXPR_TEX)
    btn.Glyph:SetSize(14, 14)
    -- green edge while an expression is filtering
    btn.activeEdge = CreateFrame("Frame", nil, btn)
    btn.activeEdge:SetAllPoints()
    btn.activeEdge:SetFrameLevel(btn:GetFrameLevel() + 3)
    btn.activeEdge:EnableMouse(false)
    CM.MakeBorder(btn.activeEdge, 0.3, 0.85, 0.4, 1, CM.PanelPP)
    btn.activeEdge:Hide()
    btn:SetFrameLevel(SP:GetFrameLevel() + 5)

    panel = CreateFrame("Frame", nil, SP)
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel:SetFrameLevel(300)
    panel:EnableMouse(true)
    panel:SetClampedToScreen(true)
    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    local fr, fg, fb = K.ThemeFill()
    bg:SetColorTexture(fr, fg, fb, 0.98)
    CM.MakeBorder(panel, K.ThemeBorder())

    local title = panel:CreateFontString(nil, "OVERLAY")
    K.Font(title, 9)
    title:SetTextColor(0.55, 0.55, 0.55, 1)
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 9, -7)
    title:SetText(EllesmereUI.L("Expressions"))

    -- clear button, skinned
    local clear = CreateFrame("Button", nil, panel)
    clear:SetSize(46, 16)
    clear:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -4)
    clear:SetNormalFontObject("GameFontHighlight")
    clear:SetText(" ")
    clear.Label = clear:CreateFontString(nil, "OVERLAY")
    K.Font(clear.Label, 9)
    clear.Label:SetPoint("CENTER", 0, 0)
    clear.Label:SetText(EllesmereUI.L("Clear"))
    local ct = clear.Label
    ct:SetTextColor(CM.TEXT_DIM_R, CM.TEXT_DIM_G, CM.TEXT_DIM_B, CM.TEXT_DIM_A)
    local skin = CM._ModuleNS and CM._ModuleNS.EllesmereUIBlizzardSkin
    local S = skin and skin.WSkin
    if S and S.Button then
        S.Button(clear, { "Label" })
    else
        local cbg = clear:CreateTexture(nil, "BACKGROUND")
        cbg:SetAllPoints()
        cbg:SetColorTexture(0.06, 0.06, 0.06, 0.95)
        CM.MakeBorder(clear, K.ThemeBorder())
        local chl = clear:CreateTexture(nil, "HIGHLIGHT")
        chl:SetAllPoints()
        chl:SetColorTexture(1, 1, 1, 0.1)
    end
    clear:HookScript("OnEnter", function() ct:SetTextColor(1, 1, 1, 1) end)
    clear:HookScript("OnLeave", function() ct:SetTextColor(CM.TEXT_DIM_R, CM.TEXT_DIM_G, CM.TEXT_DIM_B, CM.TEXT_DIM_A) end)

    -- the typing box
    local well = CreateFrame("Frame", nil, panel)
    well:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -22)
    well:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -22)
    well:SetHeight(58)
    local wbg = well:CreateTexture(nil, "BACKGROUND")
    wbg:SetAllPoints()
    wbg:SetColorTexture(0.02, 0.02, 0.02, 1)
    CM.MakeBorder(well, K.ThemeBorder())
    box = CreateFrame("EditBox", nil, well)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetMaxLetters(500)
    box:SetPoint("TOPLEFT", well, "TOPLEFT", 6, -5)
    box:SetPoint("BOTTOMRIGHT", well, "BOTTOMRIGHT", -6, 5)
    box:SetFontObject("ChatFontNormal")
    K.Font(box, 10)
    box:SetTextColor(1, 1, 1, 0)
    -- colored copy on a layer above, so the selection sits under it
    local ink = CreateFrame("Frame", nil, box)
    ink:SetAllPoints(box)
    ink:SetFrameLevel(box:GetFrameLevel() + 2)
    ink:EnableMouse(false)
    shown = ink:CreateFontString(nil, "ARTWORK")
    K.Font(shown, 10)
    shown:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
    shown:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
    shown:SetJustifyH("LEFT")
    shown:SetJustifyV("TOP")
    shown:SetWordWrap(true)
    -- placeholder example
    hint = well:CreateFontString(nil, "OVERLAY")
    K.Font(hint, 10)
    hint:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
    hint:SetTextColor(0.45, 0.45, 0.45, 1)
    hint:SetText(EllesmereUI.L("e.g. hasBL and hasBR and healer > 0"))
    well:EnableMouse(true)
    well:SetScript("OnMouseDown", function() box:SetFocus() end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    -- our own cursor, blinks while you type
    local caret = ink:CreateTexture(nil, "OVERLAY")
    caret:SetColorTexture(1, 1, 1, 0.9)
    caret:SetSize(1, 12)
    caret:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
    caret:Hide()
    local blink = 0
    local function Blink(_, elapsed)
        blink = blink + elapsed
        if blink >= 0.5 then
            blink = 0
            caret:SetShown(not caret:IsShown())
        end
    end
    box:SetScript("OnCursorChanged", function(self, x, y, w, h)
        caret:ClearAllPoints()
        caret:SetPoint("TOPLEFT", self, "TOPLEFT", x, y)
        caret:SetSize(1, (h and h > 0) and h or 12)
        blink = 0
        caret:SetShown(self:HasFocus())
    end)
    box:SetScript("OnEditFocusGained", function(self)
        blink = 0
        caret:Show()
        self:SetScript("OnUpdate", Blink)
    end)
    box:SetScript("OnEditFocusLost", function(self)
        self:SetScript("OnUpdate", nil)
        caret:Hide()
    end)
    box:SetScript("OnTextChanged", function(self, user)
        if not user then return end
        local c = GFNS.Cfg()
        local text = self:GetText()
        c.extraExpr = text:find("%S") and text or nil
        Paint(K)
        K.Refilter()
    end)
    clear:SetScript("OnClick", function()
        box:SetText("")
        GFNS.Cfg().extraExpr = nil
        Paint(K)
        K.Refilter()
    end)

    status = panel:CreateFontString(nil, "OVERLAY")
    K.Font(status, 9)
    status:SetPoint("LEFT", title, "RIGHT", 10, 0)
    status:SetPoint("RIGHT", clear, "LEFT", -8, 0)
    status:SetJustifyH("LEFT")
    status:SetWordWrap(false)

    -- click a tag: typed in at the cursor
    local function Insert(word)
        local text, pos = box:GetText(), box:GetCursorPosition()
        if not box:HasFocus() then pos = #text end
        local before, after = text:sub(1, pos), text:sub(pos + 1)
        if before ~= "" and not before:find("%s$") then word = " " .. word end
        if after ~= "" and not after:find("^%s") then word = word .. " " end
        box:SetText(before .. word .. after)
        box:SetFocus()
        box:SetCursorPosition(pos + #word)
        local c = GFNS.Cfg()
        c.extraExpr = box:GetText()
        Paint(K)
        K.Refilter()
    end
    local help = BuildHelp(panel, K, Insert)
    local TOP, BOTTOM = 22 + 58, 10
    local function LayoutPanel()
        local w = panel:GetWidth()
        if not w or w < 50 then return end
        panel:SetHeight(TOP + help.Layout(well, w - 16) + BOTTOM)
    end
    panel:SetHeight(TOP + BOTTOM)
    panel:SetScript("OnSizeChanged", function(_, w) if w and w > 50 then LayoutPanel() end end)

    K.ClickOff(panel, function(self) return self:IsMouseOver() or btn:IsMouseOver() end)
    panel:HookScript("OnShow", function()
        if K.Dim then K.Dim(true) end
        LayoutPanel()
        box:SetText(GFNS.Cfg().extraExpr or "")
        Paint(K)
        box:SetFocus()
        box:SetCursorPosition(#box:GetText())
    end)
    panel:HookScript("OnHide", function()
        box:ClearFocus()
        if K.Dim then K.Dim(false) end
    end)
    panel:Hide()

    btn:SetScript("OnClick", function()
        if panel:IsShown() then panel:Hide() return end
        panel:ClearAllPoints()
        local left = SP.SearchBox or btn
        panel:SetPoint("TOPLEFT", left, "BOTTOMLEFT", 0, -K.GAP)
        panel:SetPoint("TOPRIGHT", btn.refresh, "BOTTOMRIGHT", 0, -K.GAP)
        panel:Show()
    end)
    btn:SetScript("OnEnter", function(self)
        self.Glyph:SetAlpha(1)
        local f = Current()
        K.Tip(self, EllesmereUI.L("Expressions"), f and EllesmereUI.Lf("Active: %1$s", GFNS.Cfg().extraExpr) or EllesmereUI.L("Filter groups with your own rules"))
    end)
    btn:SetScript("OnLeave", function(self)
        self.Glyph:SetAlpha(0.8)
        K.Untip()
    end)
    btn:SetScript("OnHide", function() panel:Hide() end)
    GFNS.ExtraExprReset = function()
        local c = GFNS.Cfg()
        c.extraExpr = nil
        if box then box:SetText("") end
        Paint(K)
    end
end

-------------------------------------------------------------------------------
--  one menu at a time: whatever the open menu blocks dims and eats clicks
-------------------------------------------------------------------------------
local lastK, lastSP
local blockers = {}

local function Block(target, on)
    if not target then return end
    local b = blockers[target]
    if not b then
        if not on then return end
        b = CreateFrame("Button", nil, target:GetParent() or UIParent)
        b:SetAllPoints(target)
        b:EnableMouse(true)
        b:RegisterForClicks("AnyUp")
        blockers[target] = b
    end
    if on then
        b:SetFrameStrata(target:GetFrameStrata())
        b:SetFrameLevel(target:GetFrameLevel() + 20)
        b:Show()
        target:SetAlpha(lastK and lastK.DIM_ALPHA or 0.35)
    else
        b:Hide()
        target:SetAlpha(1)
    end
end

GFNS.ExtraOnDim = function(on)
    local K, SP = lastK, lastSP
    if not (K and SP) then return end
    local exprOpen = on and panel and panel:IsShown()
    local filtersOpen = on and not exprOpen and K.FiltersOpen and K.FiltersOpen()
    Block(btn and btn:IsShown() and btn or nil, filtersOpen)
    Block(K.Filters, exprOpen)
    Block(btn and btn.refresh, exprOpen or filtersOpen)
    Block(SP.SearchBox, exprOpen or filtersOpen)
    local face = GFNS.GFFilterFace and GFNS.GFFilterFace() or SP.FilterButton
    Block(face, filtersOpen)
    if filtersOpen and face then face:SetAlpha(K.DIM_ALPHA or 0.35) end
end

GFNS.ExtraExprButton = function(SP, refresh, show, K)
    lastK, lastSP = K, SP
    if not btn then Build(SP, K) end
    btn.refresh = refresh
    btn:ClearAllPoints()
    btn:SetPoint("RIGHT", refresh, "LEFT", -K.GAP, 0)
    btn:SetShown(show)
    Paint(K)
    return show and btn or refresh
end

-- reset with no box built yet
GFNS.ExtraExprReset = function()
    local c = GFNS.Cfg and GFNS.Cfg()
    if c then c.extraExpr = nil end
end
