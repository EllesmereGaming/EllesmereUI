if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_LootFeed.lua  (WoW Forever only)
--  A stack of short-lived rows for what the player gains: looted items, money,
--  reputation, currencies and skill ups. Each row fades out after a while; a
--  repeat gain of the same thing adds to its row instead of opening another.
--  Chat lines are matched against the client's own localized format strings,
--  so this works in every client language.
-------------------------------------------------------------------------------
local _, module = ...

local GAP = 2
local FADE_IN = 0.35
local FADE_OUT = 0.8
local SLIDE = 24 -- px a new row glides in from the left
local MONEY_ICON = "Interface\\Icons\\INV_Misc_Coin_02"
local REP_ICON = "Interface\\Icons\\INV_Misc_Note_02"
local SKILL_ICON = "Interface\\Icons\\INV_Misc_Book_08"

-- Settings live in EllesmereUIDB.lootFeed; unset keys read these.
local DEFAULTS = {
    enabled = false,
    items = true, money = true, reputation = true, currency = true, skills = true,
    minQuality = 0, showIlvl = true, showPrice = true,
    width = 300, rowHeight = 36, maxRows = 6, duration = 5, grow = "UP",
    textSize = 13,
    bgR = 0.05, bgG = 0.05, bgB = 0.05, bgA = 0.3,
    borderSize = 1, borderR = 0, borderG = 0, borderB = 0, qualityBorder = true,
}
local F = module.Feature("lootFeed", DEFAULTS,
    { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -320, y = 260 })
local Get, Cfg, Enabled = F.Get, F.Cfg, F.Enabled

local anchor, events
local active = {} -- shown rows, newest first
local pool = {}

-- v when it is a readable value of type kind (never a secret one).
local function Plain(v, kind)
    if not issecretvalue(v) and type(v) == kind then return v end
end

-------------------------------------------------------------------------------
--  Chat line matching
-------------------------------------------------------------------------------
-- A Blizzard format string as a Lua pattern with one capture per %s / %d.
-- swap marks a format that puts its second argument first (%2$d before %1$s);
-- the formats read here have at most two.
local function Compile(fmt, anchored)
    local parts, i, first = {}, 1, nil
    while true do
        local s, e, pos, kind = fmt:find("%%(%d?)%$?([sd])", i)
        parts[#parts + 1] = (fmt:sub(i, s and s - 1):gsub("[%^%$%(%)%.%[%]%*%+%-%?%%]", "%%%0"))
        if not s then break end
        first = first or tonumber(pos)
        parts[#parts + 1] = kind == "d" and "(%d+)" or "(.-)"
        i = e + 1
    end
    local p = table.concat(parts)
    return { pat = anchored and "^" .. p .. "$" or p, swap = first == 2 }
end

-- The captures of text against the global format string key, in argument
-- order: the whole line, or anywhere in it when loose. Compiled once per key;
-- a key the client lacks never matches.
local compiled = {}
local function Match(key, text, loose)
    local c = compiled[key]
    if c == nil then
        local fmt = _G[key]
        c = type(fmt) == "string" and fmt ~= "" and Compile(fmt, not loose) or false
        compiled[key] = c
    end
    if not c then return end
    local a, b = text:match(c.pat)
    if c.swap then return b, a end
    return a, b
end

-------------------------------------------------------------------------------
--  Rows
-------------------------------------------------------------------------------
local function StyleFont(fs, size)
    EllesmereUI.ApplyModuleFont(fs, nil, size, "essentials")
end

local function AnchorHeight()
    return Get("maxRows") * (Get("rowHeight") + GAP) - GAP
end

local function StyleRow(r)
    local h, size = Get("rowHeight"), Get("textSize")
    r:SetSize(Get("width"), h)
    r.icon:SetSize(h, h)
    r.bg:SetColorTexture(Get("bgR"), Get("bgG"), Get("bgB"), Get("bgA"))
    StyleFont(r.name, size)
    StyleFont(r.value, size)
    StyleFont(r.sub, size - 2)
    r.fade.alpha:SetStartDelay(Get("duration"))
end

local function Layout()
    local up = Get("grow") == "UP"
    local step = Get("rowHeight") + GAP
    for i, r in ipairs(active) do
        r:ClearAllPoints()
        if up then
            r:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, (i - 1) * step)
        else
            r:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -(i - 1) * step)
        end
    end
end

local function Unlist(r)
    for i = #active, 1, -1 do
        if active[i] == r then table.remove(active, i) end
    end
end

local function Release(r)
    Unlist(r)
    r.show:Stop()
    r.fade:Stop()
    r:Hide()
    r.key, r.data = nil, nil
    pool[#pool + 1] = r
    Layout()
end

-- Starts the wait-then-fade-out, unless the row is still fading in (its
-- end starts it) or hovered (leaving starts it).
local function ArmFade(r)
    if r.show:IsPlaying() then return end
    r.fade:Stop()
    r:SetAlpha(1)
    if not r:IsMouseOver() then r.fade:Play() end
end

-- Hover shows the item tooltip and holds the fade.
local function RowEnter(r)
    if not r.show:IsPlaying() then
        r.fade:Stop()
        r:SetAlpha(1)
    end
    local link = r.data and r.data.link
    if link then
        GameTooltip:SetOwner(r, "ANCHOR_LEFT")
        GameTooltip:SetHyperlink(link)
        GameTooltip:Show()
    end
end

local function RowLeave(r)
    if GameTooltip:IsOwned(r) then GameTooltip:Hide() end
    ArmFade(r)
end

local function ShowDone(g) ArmFade(g:GetParent()) end
local function FadeDone(g) Release(g:GetParent()) end

local function Text(r)
    local fs = r:CreateFontString(nil, "OVERLAY")
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

-- One animation of group g: step order, seconds, easing.
local function Anim(g, kind, order, secs, smoothing)
    local a = g:CreateAnimation(kind)
    a:SetOrder(order)
    a:SetDuration(secs)
    if smoothing then a:SetSmoothing(smoothing) end
    return a
end

local function NewRow()
    local r = CreateFrame("Frame", nil, anchor)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetPoint("LEFT")
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- trim the icon frame
    r.name, r.sub, r.value = Text(r), Text(r), Text(r)
    r.value:SetJustifyH("RIGHT")
    r.value:SetPoint("RIGHT", -6, 0)
    r.sub:SetPoint("TOPLEFT", r.icon, "RIGHT", 6, -1)
    r.sub:SetPoint("RIGHT", r.value, "LEFT", -8, 0)
    EllesmereUI.PP.CreateBorder(r, 0, 0, 0, 1, 1, "OVERLAY", 2)
    -- Hover only: clicks pass through.
    r:EnableMouseMotion(true)
    r:SetScript("OnEnter", RowEnter)
    r:SetScript("OnLeave", RowLeave)
    -- Fade in while gliding in: a zero-length jump left, then the way back.
    r.show = r:CreateAnimationGroup()
    Anim(r.show, "Translation", 1, 0):SetOffset(-SLIDE, 0)
    Anim(r.show, "Translation", 2, FADE_IN, "OUT"):SetOffset(SLIDE, 0)
    local appear = Anim(r.show, "Alpha", 2, FADE_IN, "OUT")
    appear:SetFromAlpha(0)
    appear:SetToAlpha(1)
    r.show:SetScript("OnFinished", ShowDone)
    -- Wait (the start delay, set by StyleRow), fade out, free the row.
    r.fade = r:CreateAnimationGroup()
    r.fade.alpha = Anim(r.fade, "Alpha", 1, FADE_OUT, "IN_OUT")
    r.fade.alpha:SetFromAlpha(1)
    r.fade.alpha:SetToAlpha(0)
    r.fade:SetScript("OnFinished", FadeDone)
    return r
end

-- Fills a row from its data: icon, text (first line), sub (second line,
-- optional), value (right side, optional), border (quality colour, optional).
local function Fill(r)
    local d, PP = r.data, EllesmereUI.PP
    r.icon:SetTexture(d.icon)
    r.name:SetText(d.text)
    r.sub:SetText(d.sub or "")
    r.sub:SetShown(d.sub ~= nil)
    r.value:SetText(d.value or "")
    r.name:ClearAllPoints()
    r.name:SetPoint("RIGHT", r.value, "LEFT", -8, 0)
    if d.sub then
        r.name:SetPoint("BOTTOMLEFT", r.icon, "RIGHT", 6, 1)
    else
        r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    end
    local size = Get("borderSize")
    if size > 0 then
        local br, bg, bb = Get("borderR"), Get("borderG"), Get("borderB")
        if d.border and Get("qualityBorder") then br, bg, bb = d.border.r, d.border.g, d.border.b end
        PP.UpdateBorder(r, size, br, bg, bb, 1)
        PP.ShowBorder(r)
    else
        PP.HideBorder(r)
    end
end

local function FindRow(key)
    for _, r in ipairs(active) do
        if r.key == key then return r end
    end
end

-- amount plus what the row showing key already adds up to.
local function Total(key, amount)
    local r = FindRow(key)
    return amount + (r and r.data.amount or 0)
end

-- Shows data under key: the row already showing key is refilled, moved to the
-- front and its fade restarted; otherwise a row is taken (the oldest one when
-- all maxRows are in use) and fades in.
local function Push(key, data)
    local r = FindRow(key)
    local fresh = not r
    if r then
        Unlist(r)
    else
        while #active >= Get("maxRows") do Release(active[#active]) end
        r = table.remove(pool) or NewRow()
        StyleRow(r)
    end
    table.insert(active, 1, r)
    r.key, r.data = key, data
    Fill(r)
    Layout()
    if fresh then
        r.fade:Stop()
        r:SetAlpha(0)
        r:Show()
        r.show:Play()
    else
        ArmFade(r)
    end
end

-------------------------------------------------------------------------------
--  Sources
-------------------------------------------------------------------------------
local function Money(copper)
    return C_CurrencyInfo.GetCoinTextureString(copper, Get("textSize"))
end

local function ShowItem(link, count, retried)
    local name, _, quality, itemLevel, _, _, _, _, _, icon, sellPrice, classID = C_Item.GetItemInfo(link)
    if not name then
        -- Not cached yet: try again once the client has it. Only once: the
        -- client also calls back when the item fails to load.
        if not retried then
            Item:CreateFromItemLink(link):ContinueOnItemLoad(function() ShowItem(link, count, true) end)
        end
        return
    end
    if (quality or 0) < Get("minQuality") then return end
    local key = "item:" .. link
    count = Total(key, count)
    local color = ITEM_QUALITY_COLORS[quality or 1] or ITEM_QUALITY_COLORS[1]
    local text = color.hex .. name .. "|r"
    if count > 1 then text = count .. "x " .. text end
    local sub
    if Get("showIlvl") and (classID == Enum.ItemClass.Weapon or classID == Enum.ItemClass.Armor) then
        local ilvl = C_Item.GetDetailedItemLevelInfo(link) or itemLevel
        if ilvl and ilvl > 0 then sub = EllesmereUI.Lf("ilvl: %d", ilvl) end
    end
    local value = Get("showPrice") and sellPrice and sellPrice > 0 and Money(sellPrice * count) or nil
    Push(key, { icon = icon, text = text, sub = sub, value = value, border = color, link = link, amount = count })
end

local function ShowMoney(copper)
    copper = Total("money", copper)
    Push("money", { icon = MONEY_ICON, text = EllesmereUI.L("Money"), value = Money(copper), amount = copper })
end

-- A faction's or skill line's data by name. ids keeps the id a scan of the
-- (expanded) list found, so later lookups go straight to it.
local factionIDs, skillIDs = {}, {}
local function Lookup(ids, name, byID, count, byIndex, idKey)
    local id = ids[name]
    if id then return byID(id) end
    for i = 1, count() do
        local d = byIndex(i)
        if d and d.name == name then
            ids[name] = d[idKey]
            return d
        end
    end
end

-- With the progress within the current standing.
local function ShowReputation(faction, delta)
    local key = "rep:" .. faction
    delta = Total(key, delta)
    local text = (delta >= 0 and "|cff00ff00+" or "|cffff4040") .. delta .. "|r " .. faction
    local d = Lookup(factionIDs, faction, C_Reputation.GetFactionDataByID, C_Reputation.GetNumFactions,
        C_Reputation.GetFactionDataByIndex, "factionID")
    if d then
        text = text .. string.format(" (%s / %s)", BreakUpLargeNumbers(d.currentStanding - d.currentReactionThreshold),
            BreakUpLargeNumbers(d.nextReactionThreshold - d.currentReactionThreshold))
    end
    Push(key, { icon = REP_ICON, text = text, amount = delta })
end

-- With the total held, red at the cap.
local function ShowCurrency(id, change)
    local info = C_CurrencyInfo.GetCurrencyInfo(id)
    if not (info and info.name) then return end
    local key = "currency:" .. id
    change = Total(key, change)
    local total = BreakUpLargeNumbers(info.quantity)
    if info.maxQuantity > 0 then
        total = total .. " / " .. BreakUpLargeNumbers(info.maxQuantity)
        if info.quantity >= info.maxQuantity then total = "|cffff4040" .. total .. "|r" end
    end
    Push(key, { icon = info.iconFileID, text = change .. "x " .. info.name .. " (" .. total .. ")", amount = change })
end

local function ShowSkill(skill, rank)
    local d = Lookup(skillIDs, skill, C_SkillInfo.GetSkillLineInfoByID, C_SkillInfo.GetNumSkillLines,
        C_SkillInfo.GetSkillLineInfo, "skillID")
    local max = d and d.maxRank > 0 and (" / " .. d.maxRank) or ""
    Push("skill:" .. skill, { icon = SKILL_ICON, text = skill .. " " .. EllesmereUI.COLOR_CODES.WHITE .. rank .. max .. "|r" })
end

-- Own loot only: the *_SELF lines, the multiple-item formats (link and count)
-- first, since the single-item ones match their lines too.
local ITEM_KEYS = {
    "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_SELF",
    "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF",
    "LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE", "LOOT_ITEM_BONUS_ROLL_SELF",
}

local function OnLoot(text)
    for _, key in ipairs(ITEM_KEYS) do
        local link, count = Match(key, text)
        if link then
            if link:find("|Hitem:", 1, true) then ShowItem(link, tonumber(count) or 1) end
            return
        end
    end
end

-- Money lines spell out each coin with the client's own "%d Gold" etc.
local COIN_KEYS = { GOLD_AMOUNT = 10000, SILVER_AMOUNT = 100, COPPER_AMOUNT = 1 }
local function OnMoney(text)
    local copper = 0
    for key, mult in pairs(COIN_KEYS) do
        local n = Match(key, text, true)
        if n then copper = copper + tonumber(n) * mult end
    end
    if copper > 0 then ShowMoney(copper) end
end

local function OnFaction(text)
    local faction, amount = Match("FACTION_STANDING_INCREASED", text)
    if faction then return ShowReputation(faction, tonumber(amount)) end
    faction, amount = Match("FACTION_STANDING_DECREASED", text)
    if faction then return ShowReputation(faction, -tonumber(amount)) end
end

local function OnSkill(text)
    local skill, rank = Match("SKILL_RANK_UP", text)
    if skill then ShowSkill(skill, tonumber(rank)) end
end

local CHAT_EVENTS = {
    CHAT_MSG_LOOT = { setting = "items", handler = OnLoot },
    CHAT_MSG_MONEY = { setting = "money", handler = OnMoney },
    CHAT_MSG_COMBAT_FACTION_CHANGE = { setting = "reputation", handler = OnFaction },
    CHAT_MSG_SKILL = { setting = "skills", handler = OnSkill },
}

local function OnEvent(_, event, ...)
    local chat = CHAT_EVENTS[event]
    if chat then
        local text = Plain((...), "string")
        if text then chat.handler(text) end
    elseif event == "CURRENCY_DISPLAY_UPDATE" then
        local id, _, change = ...
        id, change = Plain(id, "number"), Plain(change, "number")
        if id and change and change > 0 then ShowCurrency(id, change) end
    end
end

-------------------------------------------------------------------------------
--  Setup
-------------------------------------------------------------------------------
local function ApplyStyle()
    if not anchor then return end
    anchor:SetSize(Get("width"), AnchorHeight())
    -- Pooled rows are styled when Push takes them.
    for _, r in ipairs(active) do
        StyleRow(r)
        Fill(r)
    end
    while #active > Get("maxRows") do Release(active[#active]) end
    Layout()
end

local function CreateAnchor()
    if anchor then return end
    anchor = CreateFrame("Frame", nil, UIParent)
    anchor:SetFrameStrata("MEDIUM")
    ApplyStyle()
    F.Place(anchor)
end

local function ClearRows()
    while active[1] do Release(active[1]) end
end

local function Apply()
    if events then events:UnregisterAllEvents() end
    if not Enabled() then
        ClearRows()
        return
    end
    CreateAnchor()
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", OnEvent)
    end
    for event, chat in pairs(CHAT_EVENTS) do
        if Get(chat.setting) then events:RegisterEvent(event) end
    end
    if Get("currency") then events:RegisterEvent("CURRENCY_DISPLAY_UPDATE") end
end

-- A sample of every enabled source: the player's capital for reputation and
-- classic items of three qualities (item id / count pairs). The rows fade like
-- real ones.
local PREVIEW_ITEMS = { 19019, 1, 4306, 5, 14047, 12 }
local function Preview()
    if not Enabled() then return end
    CreateAnchor()
    ClearRows()
    if Get("skills") then ShowSkill(EllesmereUI.L("Swords"), 42) end
    if Get("reputation") then
        local capital = C_Reputation.GetFactionDataByID(UnitFactionGroup("player") == "Horde" and 76 or 72)
        if capital then ShowReputation(capital.name, 250) end
    end
    if Get("money") then ShowMoney(12345) end
    if Get("items") then
        for i = 1, #PREVIEW_ITEMS, 2 do ShowItem("item:" .. PREVIEW_ITEMS[i], PREVIEW_ITEMS[i + 1]) end
    end
end

-- Options-page entry points.
EllesmereUI._LootFeed = {
    Get = Get,
    Cfg = Cfg,
    Apply = Apply,
    ApplyStyle = ApplyStyle,
    ApplyPosition = function() F.Place(anchor) end,
    Preview = Preview,
}

F.Start(Apply, {
    key = "EUI_LootFeed", label = "Loot Feed", order = 732, minWidth = 150,
    frame = function(build)
        if build then CreateAnchor() end
        return anchor
    end,
    -- Follows Max Rows and Row Height.
    height = AnchorHeight,
    applyStyle = ApplyStyle,
})
