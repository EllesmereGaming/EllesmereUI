if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_ClassicSpellbook.lua  (WoW Forever only)
--  The vanilla spellbook, drawn with the client's own art: school tabs down
--  the right side and twelve spells a page, plus the game's search box and
--  spellbook options. The spellbook key opens it in place of the Talents &
--  Spellbook window, which the micro menu still opens. The window and its
--  buttons are protected and its pages are turned by restricted snippets, so
--  the key, the tabs and the page arrows work in combat. A search or an
--  option changed in combat applies when the fight ends: only code that runs
--  out of combat can hand the snippets a new list of spells.
-------------------------------------------------------------------------------
local _, module = ...

local PER_PAGE = 12
local ROWS = PER_PAGE / 2
local BANK = Enum.SpellBookSpellBank.Player
local ART = "Interface\\Spellbook\\"
local QUEUE_KEY = "ClassicSpellbook"
local TOGGLE_NAME = "EUI_ClassicSpellbookToggle"
local ESCAPE_NAME = "EUI_ClassicSpellbookEscape"

-- Settings live in EllesmereUIDB.classicSpellbook; unset keys read these.
local F = module.Feature("classicSpellbook", { enabled = false })

local book, toggle, events
local lines = {} -- shown skill lines: { name, icon, slots = { spellbook slot, ... } }
local line = 1   -- the selected skill line
local pages = {} -- page per skill line (0: the search results), as the snippets last reported
local newSearch  -- the search text changed: its results open on page 1
local query      -- lowercase search text; nil when not searching
local stale      -- the spellbook changed while the book was closed
local boundKeys  -- the keys the toggle holds, space separated
local found = { slots = {} } -- the search results, shown as a line of their own
local pushed     -- the snippet text the snippets last ran

-------------------------------------------------------------------------------
--  Spell data
-------------------------------------------------------------------------------
-- A search matches a spell's name, rank text or description.
local function Matches(slot)
    local info = C_SpellBook.GetSpellBookItemInfo(slot, BANK)
    if not info then return false end
    if info.name:lower():find(query, 1, true) then return true end
    if info.subName and info.subName:lower():find(query, 1, true) then return true end
    local text = C_SpellBook.GetSpellBookItemDescription(slot, BANK)
    return text ~= nil and text:lower():find(query, 1, true) ~= nil
end

-- Every learned spell of the player's own skill lines. The game's spellbook
-- options (Hide Passives, Show All Spell Ranks) apply, except to a search,
-- which looks through every spell as the game's own does.
local function ReadLines()
    wipe(lines)
    wipe(found.slots)
    local allRanks = query or GetCVarBool("ShowAllSpellRanks")
    local passives = query or not GetCVarBool("spellBookHidePassives")
    for i = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(i)
        if info and not info.shouldHide and not info.offSpecID then
            local slots = {}
            for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                if C_SpellBook.GetSpellBookItemType(slot, BANK) == Enum.SpellBookItemType.Spell
                   and (allRanks or not C_SpellBook.IsSpellBookItemLowRank(slot, BANK))
                   and (passives or not C_SpellBook.IsSpellBookItemPassive(slot, BANK)) then
                    slots[#slots + 1] = slot
                    if query and Matches(slot) then found.slots[#found.slots + 1] = slot end
                end
            end
            lines[#lines + 1] = { name = info.name, icon = info.iconID, slots = slots }
        end
    end
    if line > #lines then line = 1 end
end

-- The line on show: the search results while searching.
local function Shown()
    if query then return found, 0 end
    return lines[line], line
end

local function PageCount()
    local l = Shown()
    return l and math.max(1, math.ceil(#l.slots / PER_PAGE)) or 1
end

-------------------------------------------------------------------------------
--  Spell buttons
-------------------------------------------------------------------------------
local function SpellEnter(b)
    if not b.slot then return end
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    GameTooltip:SetSpellBookItem(b.slot, BANK)
    GameTooltip:Show()
end

local function SpellLeave()
    GameTooltip:Hide()
end

local function SpellDrag(b)
    if b.spellID and not b.passive and not InCombatLockdown() then C_Spell.PickupSpell(b.spellID) end
end

local function NewSpellButton(i)
    local b = CreateFrame("Button", nil, book, "SecureActionButtonTemplate")
    b:SetSize(37, 37)
    -- Down the left column, then down the right one.
    local col, row = math.floor((i - 1) / ROWS), (i - 1) % ROWS
    b:SetPoint("TOPLEFT", book, "TOPLEFT", 34 + col * 157, -85 - row * 51)
    b:RegisterForClicks("AnyUp", "AnyDown") -- the action fires on whichever the client's key-down setting picks
    b:RegisterForDrag("LeftButton")

    local empty = b:CreateTexture(nil, "BACKGROUND")
    empty:SetTexture(ART .. "UI-Spellbook-SpellBackground")
    empty:SetSize(64, 64)
    empty:SetPoint("TOPLEFT", -3, 3)

    b.icon = b:CreateTexture(nil, "BORDER")
    b.icon:SetAllPoints()
    b.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cooldown:SetAllPoints()

    b.name = b:CreateFontString(nil, "BORDER", "GameFontNormal")
    b.name:SetJustifyH("LEFT")
    b.name:SetWidth(103)
    b.name:SetMaxLines(3)
    b.name:SetPoint("LEFT", b, "RIGHT", 5, 3)

    b.sub = b:CreateFontString(nil, "BORDER", SubSpellFont and "SubSpellFont" or "GameFontHighlightSmall")
    b.sub:SetJustifyH("LEFT")
    b.sub:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -2)

    b:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2")
    local normal = b:GetNormalTexture()
    normal:ClearAllPoints()
    normal:SetSize(64, 64)
    normal:SetPoint("CENTER")
    b.border = normal
    b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    b:SetScript("OnEnter", SpellEnter)
    b:SetScript("OnLeave", SpellLeave)
    b:SetScript("OnDragStart", SpellDrag)
    return b
end

-- What the button shows. What it casts is set by the AIM snippet.
local function FillSpellButton(b, slot)
    local info = slot and C_SpellBook.GetSpellBookItemInfo(slot, BANK)
    local spellID = info and info.spellID
    if not spellID then
        b.slot, b.spellID, b.passive = nil, nil, nil
        b.icon:Hide()
        b.name:Hide()
        b.sub:Hide()
        b.border:SetVertexColor(1, 1, 1)
        return
    end
    b.slot, b.spellID, b.passive = slot, spellID, info.isPassive
    b.icon:SetTexture(info.iconID)
    b.icon:Show()
    b.name:SetText(info.name)
    b.name:Show()
    local sub = info.subName
    if not sub or sub == "" then sub = C_Spell.GetSpellSubtext(spellID) end
    if (not sub or sub == "") and info.isPassive then sub = SPELL_PASSIVE end
    b.sub:SetText(sub or "")
    b.sub:Show()
    local c = info.isPassive and PASSIVE_SPELL_FONT_COLOR or NORMAL_FONT_COLOR
    b.name:SetTextColor(c.r, c.g, c.b)
    -- A passive has no button frame, as in the vanilla book.
    local v = info.isPassive and 0 or 1
    b.border:SetVertexColor(v, v, v)
end

-- The cooldown swirls of the page on show. The duration goes straight from
-- the game to the swirl: its numbers can be secret in combat.
local function PaintCooldowns()
    for _, b in ipairs(book.spells) do
        local duration = b.slot and not b.passive and C_SpellBook.GetSpellBookItemCooldownDuration(b.slot, BANK)
        if duration then
            b.cooldown:SetCooldownFromDurationObject(duration)
        else
            b.cooldown:Clear()
        end
    end
end

-------------------------------------------------------------------------------
--  Window
-------------------------------------------------------------------------------
-- Restricted snippets, all run in the book's environment: LINES[n] lists what
-- each slot of skill line n casts (0: nothing; n = 0 is the search results),
-- COUNTS[n] its length, PAGES[n] its page and LINE the line on show.
-- AIM points the twelve buttons at the page on show, then has the page drawn.
local AIM = [[
    local list = LINES[LINE]
    local count = COUNTS[LINE] or 0
    local last = (count - count % 12) / 12
    if count % 12 > 0 or last < 1 then last = last + 1 end
    local page = PAGES[LINE] or 1
    if page > last then page = last end
    if page < 1 then page = 1 end
    PAGES[LINE] = page
    for i = 1, 12 do
        local id = list and list[(page - 1) * 12 + i]
        local b = SPELLS[i]
        if id and id > 0 then
            b:SetAttribute("type", "spell")
            b:SetAttribute("spell", id)
        else
            b:SetAttribute("type", nil)
            b:SetAttribute("spell", nil)
        end
    end
    BOOK:CallMethod("Painted", LINE, page)
]]

local function TabEnter(tab)
    EllesmereUI.ShowWidgetTooltip(tab, tab.tooltip, { anchor = "right" })
end

local function TabLeave()
    EllesmereUI.HideWidgetTooltip()
end

local function TurnSound(b)
    if not b.idle then PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN) end
end

-- Out of combat only, like every frame made here. A click shows its line.
local function NewTab(i)
    local tab = CreateFrame("CheckButton", nil, book, "SecureFrameTemplate")
    tab:SetSize(32, 32)
    tab:SetPoint("TOPLEFT", book, "TOPRIGHT", -32, -65 - (i - 1) * 49)
    local bg = tab:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
    bg:SetSize(64, 64)
    bg:SetPoint("TOPLEFT", -3, 11)
    tab:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    tab:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight")
    tab:GetCheckedTexture():SetBlendMode("ADD")
    tab:SetScript("OnEnter", TabEnter)
    tab:SetScript("OnLeave", TabLeave)
    tab:SetScript("PostClick", TurnSound)
    book:WrapScript(tab, "OnClick", ("LINE = %d\n"):format(i) .. AIM)
    return tab
end

-- A click turns step pages; AIM keeps the page inside the line.
local function NewArrow(dir, x, step)
    local b = CreateFrame("Button", nil, book, "SecureFrameTemplate")
    b:SetSize(32, 32)
    b:SetPoint("CENTER", book, "BOTTOMLEFT", x, 105)
    local tex = "Interface\\Buttons\\UI-SpellbookIcon-" .. dir .. "Page-"
    b.art = tex
    b:SetNormalTexture(tex .. "Up")
    b:SetPushedTexture(tex .. "Down")
    b:SetDisabledTexture(tex .. "Disabled")
    b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    b:SetScript("PostClick", TurnSound)
    book:WrapScript(b, "OnClick", ("PAGES[LINE] = (PAGES[LINE] or 1) + (%d)\n"):format(step) .. AIM)
    return b
end

-- An arrow with nowhere to go shows its disabled art and cannot be clicked. The arrows are
-- secure frames, so only out of combat can they be disabled: combat starts with
-- both enabled (the idle one clicks silently) and the fight's end syncs them.
local function ArrowsFor(page)
    local canPrev, canNext = page > 1, page < PageCount()
    for arrow, can in pairs({ [book.prev] = canPrev, [book.next] = canNext }) do
        arrow:SetNormalTexture(arrow.art .. (can and "Up" or "Disabled"))
        arrow.idle = not can
    end
    if InCombatLockdown() then
        EllesmereUI.CombatQueue.Defer(QUEUE_KEY .. "Arrows", function()
            local _, key = Shown()
            ArrowsFor(pages[key] or 1)
        end)
        return
    end
    book.prev:SetEnabled(canPrev)
    book.next:SetEnabled(canNext)
end

-- Draws the page on show. No protected call: it also runs in combat.
local function Paint()
    local l, key = Shown()
    local page = pages[key] or 1
    for i, b in ipairs(book.spells) do
        FillSpellButton(b, l and l.slots[(page - 1) * PER_PAGE + i])
    end
    for i, tab in ipairs(book.tabs) do
        tab:SetChecked(not query and i == line)
    end
    ArrowsFor(page)
    book.pageText:SetFormattedText(PAGE_NUMBER, page)
    PaintCooldowns()
end

-- AIM's report: the line and page now on show. A line of its own ends a search.
local function Painted(_, shown, page)
    if shown > 0 then
        line = shown
        if query then
            query = nil
            book.search:SetText("")
        end
    end
    pages[shown] = page
    Paint()
end

-- One line of the LINES table, as snippet text.
local function LineText(out, key, slots)
    out[#out + 1] = ("local t = newtable() LINES[%d] = t COUNTS[%d] = %d"):format(key, key, #slots)
    for i, slot in ipairs(slots) do
        local info = C_SpellBook.GetSpellBookItemInfo(slot, BANK)
        local id = info and not info.isPassive and info.spellID or 0
        out[#out + 1] = ("t[%d] = %d"):format(i, id)
    end
end

-- Out of combat only: hands the snippets the spell lists and has them aim.
local function Push()
    for i, data in ipairs(lines) do
        local tab = book.tabs[i]
        if not tab then
            tab = NewTab(i)
            book.tabs[i] = tab
        end
        tab:SetNormalTexture(data.icon)
        tab.tooltip = data.name
        tab:Show()
    end
    for i = #lines + 1, #book.tabs do book.tabs[i]:Hide() end

    local out = { "LINES = newtable() COUNTS = newtable()" }
    for i, data in ipairs(lines) do LineText(out, i, data.slots) end
    if query then LineText(out, 0, found.slots) end
    local reset = newSearch
    if reset then out[#out + 1] = "PAGES[0] = 1" end
    newSearch = nil
    out[#out + 1] = ("LINE = %d"):format(query and 0 or line)
    out[#out + 1] = AIM
    -- The snippets already hold these lists (a refresh that found no change,
    -- as most of the ones a pull starts do): only the page is drawn again.
    local text = table.concat(out, "\n")
    if text == pushed and not reset then
        Paint()
        return
    end
    pushed = text
    book:Execute(text)
end

-- Rereads the spellbook and repaints; waits out combat.
local function Refresh()
    if not book then return end
    if InCombatLockdown() then
        EllesmereUI.CombatQueue.Defer(QUEUE_KEY, Refresh)
        return
    end
    stale = nil
    ReadLines()
    Push()
end

-- The talent window stands beside the open book and takes its place when it
-- closes (the book is protected, so it is the one that never moves).
local function PlaceTalents()
    local talents = EllesmereUI._ClassicTalents
    if talents then talents.Place() end
end

-- Cooldowns are followed only while the book is open.
local function BookShown()
    PlaySound(SOUNDKIT.IG_SPELLBOOK_OPEN)
    events:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    PaintCooldowns()
    PlaceTalents()
    Refresh() -- also picks up a spellbook option changed in the game's own book
end

local function BookHidden()
    PlaySound(SOUNDKIT.IG_SPELLBOOK_CLOSE)
    events:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
    PlaceTalents()
end

-- A search or an option changed in combat applies when the fight ends.
local function Changed()
    if InCombatLockdown() then UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1, 0.1, 0.1) end
    Refresh()
end

local function SearchChanged(box)
    local text = strtrim(box:GetText()):lower()
    text = text ~= "" and text or nil
    if text == query then return end
    query, newSearch = text, true
    Changed()
end

-- A spellbook option of the game's: a checkbox over its console variable.
local function Option(root, label, cvar)
    root:CreateCheckbox(label, function() return GetCVarBool(cvar) end, function()
        SetCVar(cvar, not GetCVarBool(cvar))
        Changed()
    end)
end

-- Warriors and rogues have no spell ranks to show, as in the game's own menu.
local function OptionsMenu(_, root)
    Option(root, SPELLBOOK_FILTER_PASSIVES, "spellBookHidePassives")
    local _, class = UnitClass("player")
    if class ~= "ROGUE" and class ~= "WARRIOR" then Option(root, SHOW_ALL_SPELL_RANKS, "ShowAllSpellRanks") end
end

local TOGGLE_SNIPPET = [[
    local book = self:GetFrameRef("book")
    if book:IsShown() then book:Hide() else book:Show() end
]]

local function Build()
    if book then return end
    book = CreateFrame("Frame", "EUI_ClassicSpellbook", UIParent, "SecureHandlerShowHideTemplate")
    book:Hide()
    book:SetSize(384, 512)
    book:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -104)
    book:SetFrameStrata("MEDIUM")
    book:SetToplevel(true)
    book:EnableMouse(true)
    book:SetHitRectInsets(0, 30, 0, 70)
    -- Escape closes the open book, in combat too.
    book:SetAttribute("_onshow", ([[ self:SetBindingClick(true, "ESCAPE", %q) ]]):format(ESCAPE_NAME))
    book:SetAttribute("_onhide", [[ self:ClearBindings() ]])
    book:HookScript("OnShow", BookShown)
    book:HookScript("OnHide", BookHidden)

    local portrait = book:CreateTexture(nil, "BACKGROUND")
    portrait:SetTexture(ART .. "Spellbook-Icon")
    portrait:SetSize(58, 58)
    portrait:SetPoint("TOPLEFT", 10, -8)
    for _, part in ipairs({ { "TopLeft", "TOPLEFT", 256 }, { "TopRight", "TOPRIGHT", 128 },
                            { "BotLeft", "BOTTOMLEFT", 256 }, { "BotRight", "BOTTOMRIGHT", 128 } }) do
        local tex = book:CreateTexture(nil, "ARTWORK")
        tex:SetTexture(ART .. "UI-SpellbookPanel-" .. part[1])
        tex:SetSize(part[3], 256)
        tex:SetPoint(part[2])
    end
    local title = book:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("CENTER", 6, 230)
    title:SetText(SPELLBOOK)
    book.pageText = book:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    book.pageText:SetWidth(102)
    book.pageText:SetPoint("BOTTOM", -14, 99) -- between the page arrows

    toggle = CreateFrame("Button", TOGGLE_NAME, UIParent, "SecureHandlerClickTemplate")
    toggle:SetFrameRef("book", book)
    toggle:SetAttribute("_onclick", TOGGLE_SNIPPET)

    -- Escape also closes the talent window that stands beside the book.
    local escape = CreateFrame("Button", ESCAPE_NAME, UIParent, "SecureHandlerClickTemplate")
    escape:SetFrameRef("book", book)
    escape:SetAttribute("_onclick", [[ self:GetFrameRef("book"):Hide() ]])
    escape:SetScript("PostClick", function()
        local talents = EllesmereUI._ClassicTalents
        if talents then talents.Close() end
    end)

    local close = CreateFrame("Button", nil, book, "SecureHandlerClickTemplate")
    close:SetSize(32, 32)
    close:SetPoint("CENTER", book, "TOPRIGHT", -44, -25)
    close:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    close:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    close:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
    close:SetFrameRef("book", book)
    close:SetAttribute("_onclick", [[ self:GetFrameRef("book"):Hide() ]])

    -- The game's own search box and options button, under the title.
    book.options = CreateFrame("DropdownButton", nil, book, "UIPanelArrowDropdownButtonTemplate")
    book.options:SetPoint("TOPRIGHT", -62, -47)
    book.options:SetupMenu(OptionsMenu)
    book.search = CreateFrame("EditBox", nil, book, "SearchBoxTemplate")
    book.search:SetHeight(20)
    book.search:SetPoint("TOPLEFT", 84, -42)
    book.search:SetPoint("RIGHT", book.options, "LEFT", -6, 0)
    book.search.Instructions:SetText(SPELLBOOK_SEARCH_INSTRUCTIONS)
    book.search:HookScript("OnTextChanged", SearchChanged)

    book.tabs, book.spells = {}, {}
    for i = 1, PER_PAGE do
        book.spells[i] = NewSpellButton(i)
        book:SetFrameRef("spell" .. i, book.spells[i])
    end
    book.Painted = Painted
    book:Execute([[
        BOOK, LINE = self, 1
        LINES, COUNTS, PAGES, SPELLS = newtable(), newtable(), newtable(), newtable()
        for i = 1, 12 do SPELLS[i] = self:GetFrameRef("spell" .. i) end
    ]])
    book.prev = NewArrow("Prev", 50, -1)
    book.next = NewArrow("Next", 314, 1)
end

-------------------------------------------------------------------------------
--  Setup
-------------------------------------------------------------------------------
-- The spellbook key clicks the toggle while the feature is on. Setting an
-- override fires UPDATE_BINDINGS itself, so unchanged keys are left alone.
local function Bind()
    if InCombatLockdown() then
        EllesmereUI.CombatQueue.Defer(QUEUE_KEY .. "Bind", Bind)
        return
    end
    if not toggle then return end
    local keys = F.Enabled() and table.concat({ GetBindingKey("TOGGLESPELLBOOK") }, " ") or ""
    if keys == boundKeys then return end
    boundKeys = keys
    ClearOverrideBindings(toggle)
    for key in keys:gmatch("%S+") do
        SetOverrideBindingClick(toggle, true, key, TOGGLE_NAME)
    end
end

-- A closed book only notes that the spellbook changed. It catches up when it
-- opens, or as combat starts (this event runs before the lockdown does), so a
-- book first opened in a fight still holds the right spells.
local function OnEvent(_, event)
    if event == "UPDATE_BINDINGS" then
        Bind()
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        PaintCooldowns()
    elseif event == "PLAYER_REGEN_DISABLED" then
        if stale then Refresh() end
        if book then
            book.prev:SetEnabled(true)
            book.next:SetEnabled(true)
        end
    elseif book:IsShown() then
        Refresh()
    else
        stale = true
    end
end

local function Apply()
    if InCombatLockdown() then
        EllesmereUI.CombatQueue.Defer(QUEUE_KEY .. "Apply", Apply)
        return
    end
    if events then events:UnregisterAllEvents() end
    if not F.Enabled() then
        if book then book:Hide() end
        Bind()
        return
    end
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", OnEvent)
    end
    Build()
    events:RegisterEvent("SPELLS_CHANGED")
    events:RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE")
    events:RegisterEvent("UPDATE_BINDINGS")
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    if book:IsShown() then events:RegisterEvent("SPELL_UPDATE_COOLDOWN") end
    Bind()
    Refresh()
end

-- Options-page entry points.
EllesmereUI._ClassicSpellbook = {
    Get = F.Get,
    Cfg = F.Cfg,
    Apply = Apply,
}

F.Start(Apply)
