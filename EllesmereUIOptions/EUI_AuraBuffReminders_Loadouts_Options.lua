if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_AuraBuffReminders_Loadouts_Options.lua  --  The Loadout Manager tab
--
--  A tab of the AuraBuff Reminders page (owner 2026-11-17; it was a module of
--  its own until then). GENERAL is the Loadout Manager's account-wide
--  switches; under it the add row (Activities | Gear Set | Talent Loadout,
--  Add Loadout under them) and one card per spec listing its loadouts, the
--  Talent Reminders tab's layout. It also exports what the Talent Reminders
--  tab shares with it: the Activities checklist (ns.BuildActivityChecklist,
--  ns.ActivityKeys) and the card pieces (ns.CardPulse, CardGlyph, CardRow,
--  CardClassTitle).
--  The runtime (EUI_AuraBuffReminders_Loadouts.lua) owns the loadouts and the
--  swaps; this file drives it through ns.Loadouts and builds the tab for the
--  page's buildPage (ns._BuildLoadoutPage).
-------------------------------------------------------------------------------
local ADDON_NAME = "EllesmereUIAuraBuffReminders"
local ns = EllesmereUI._ModuleNS[ADDON_NAME]  -- module namespace (published by the module at its load)
local LM = ns and ns.Loadouts
if not LM then return end  -- module disabled: no tab

local PAGE_NAME = "Loadout Manager"
local FOREVER = EllesmereUI.IS_FOREVER == true
local PP = EllesmereUI.PanelPP

-- The add row's picks and the open cards, kept for the session across the
-- tab's rebuilds.
local pend = { acts = {} }
local cardOpen = {}

local function DB() return LM.DB() end
local function Refresh(force) EllesmereUI:RefreshPage(force and true or nil) end
local function NotEnabled() return not DB().enabled end

-- The runtime calls this when its state changes (only while the tab shows).
LM.OnStateChanged = function()
    if EllesmereUI:GetActiveModule() ~= ADDON_NAME or EllesmereUI:GetActivePage() ~= PAGE_NAME then return end
    Refresh()
end

-------------------------------------------------------------------------------
--  Text helpers. Widget labels and tooltips are translated where the widgets
--  draw them; the lines this file writes itself go through L / Lf.
-------------------------------------------------------------------------------
local DIM = EllesmereUI.COLOR_CODES.DIM
local BAD = EllesmereUI.COLOR_CODES.BAD
local function Grey(text) return DIM .. tostring(text) .. "|r" end
local function Red(text) return BAD .. tostring(text) .. "|r" end

local ALL_MPLUS = "__allmplus"
local NONE = "__none__"

-- Retail's grouped activities: each group's key prefix, its places and the
-- "All" entry that ticks every one of them (the checklist's label, and the
-- loadout row's text when a loadout holds every place), in the tab's order.
local GROUPS = {
    { all = ALL_MPLUS, prefix = "d:", allLabel = "All Mythic+ Dungeons",
      allText = function() return EllesmereUI.L("All Mythic+ Dungeons") end,
      list = function() return LM.SeasonDungeons() end },
    { all = "__allarenas", prefix = "a:", allLabel = "All Arenas",
      allText = function() return EllesmereUI.L("All Arenas") end,
      list = function() return LM.PvpMaps("arena") end },
    { all = "__allbgs", prefix = "b:", allLabel = "All Battlegrounds",
      allText = function() return EllesmereUI.L("All Battlegrounds") end,
      list = function() return LM.PvpMaps("pvp") end },
}
local GROUP_BY_ALL = {}
for _, g in ipairs(GROUPS) do GROUP_BY_ALL[g.all] = g end
local RAID_KEYS = { "raidm", "raidn", "raidold" }
local OTHER_KEYS = { "tw", "delve", "world" }

-- A loadout's gear and talents ("M+ Gear + AoE Build"); a missing set or
-- loadout reads red.
local function LoadoutName(lo)
    local parts = {}
    if lo.gear then
        local missing = LM.GearMissing(lo.gear)
        parts[#parts + 1] = (missing and Red or tostring)(lo.gear)
            .. (missing and Red(" (" .. EllesmereUI.L("missing") .. ")") or "")
    end
    if lo.talent then
        local name = LM.TalentDisplayName(lo.talent) or "?"
        local missing = LM.TalentMissing(lo.talent)
        parts[#parts + 1] = (missing and Red or tostring)(name)
            .. (missing and Red(" (" .. EllesmereUI.L("missing") .. ")") or "")
    end
    return table.concat(parts, Grey("  +  "))
end

-- One group's part of a loadout's activities: its places by name ("All
-- Arenas" and the like when it holds every one, the places skip(key) answers
-- for left out), then any other place of the group's kind (a dungeon no
-- longer in the season).
local function GroupText(out, acts, g, skip)
    local list, seen, all, any = g.list(), {}, true, false
    for _, e in ipairs(list) do
        local key = g.prefix .. e.id
        if not (skip and skip(key)) then
            any = true
            if not acts[key] then all = false break end
        end
    end
    if all and any then
        out[#out + 1] = g.allText()
        for _, e in ipairs(list) do seen[g.prefix .. e.id] = true end
    else
        for _, e in ipairs(list) do
            local key = g.prefix .. e.id
            if acts[key] then out[#out + 1] = e.name; seen[key] = true end
        end
    end
    local others = {}
    for key in pairs(acts) do
        if not seen[key] and type(key) == "string" and key:sub(1, #g.prefix) == g.prefix then
            others[#others + 1] = LM.ActivityLabel(key)
        end
    end
    table.sort(others)
    for _, name in ipairs(others) do out[#out + 1] = name end
end

-- A loadout's activities in the tab's order: the season's dungeons, the
-- raids, the arenas, the battlegrounds, then the rest (skip: as GroupText's).
local function ActivitiesText(acts, skip)
    local out = {}
    local function Keys(keys)
        for _, key in ipairs(keys) do
            if acts[key] then out[#out + 1] = LM.ActivityLabel(key) end
        end
    end
    if FOREVER then
        Keys(LM.ActivityOrder())
    else
        GroupText(out, acts, GROUPS[1], skip)
        Keys(RAID_KEYS)
        GroupText(out, acts, GROUPS[2], skip)
        GroupText(out, acts, GROUPS[3], skip)
        Keys(OTHER_KEYS)
    end
    return table.concat(out, ", ")
end

-------------------------------------------------------------------------------
--  Pickers. Their value tables are refilled in place when the game's list
--  changes and the cached menu is invalidated, so no rebuild is needed.
-------------------------------------------------------------------------------
local function Noop() end
local gearIcons = {}

local function GearEntries()
    local entries, sig = {}, {}
    for k in pairs(gearIcons) do gearIcons[k] = nil end
    for _, set in ipairs(LM.ListEquipmentSets()) do
        entries[#entries + 1] = { key = set.name, text = set.name }
        gearIcons[set.name] = set.icon
        sig[#sig + 1] = tostring(set.name) .. "=" .. tostring(set.icon)
    end
    return entries, table.concat(sig, "\n")
end

local function TalentEntries()
    local entries, sig = {}, {}
    for _, loadout in ipairs(LM.ListTalentLoadouts()) do
        local key = tostring(loadout.configID)
        entries[#entries + 1] = { key = key, text = loadout.name }
        sig[#sig + 1] = key .. "=" .. tostring(loadout.name)
    end
    return entries, table.concat(sig, "\n")
end

-- Menu options (_menuOpts) and the no-localize flag (_noLoc) ride along in the
-- values table and survive a refill; everything else is replaced.
local function FillValues(values, order, noneText, entries)
    for k in pairs(values) do
        if k ~= "_menuOpts" and k ~= "_noLoc" then values[k] = nil end
    end
    for i = #order, 1, -1 do order[i] = nil end
    values[NONE] = noneText
    order[1] = NONE
    for _, e in ipairs(entries) do
        values[e.key] = e.text
        order[#order + 1] = e.key
    end
end

-- The tables for a picker plus Update (registered as a widget refresh) and
-- Attach (handed the dropdown button once it exists). noneText is translated.
local function LivePicker(noneText, entriesFn, menuOpts)
    -- Set and loadout names are the game's or the player's own: never L().
    local values, order = { _noLoc = true }, {}
    if menuOpts then values._menuOpts = menuOpts end
    if EllesmereUI._prebuilding then return values, order, Noop, Noop end
    local entries, sig = entriesFn()
    FillValues(values, order, noneText, entries)
    local ddBtn
    local function Update()
        local e, s = entriesFn()
        if s == sig then return end
        sig = s
        FillValues(values, order, noneText, e)
        if ddBtn and ddBtn._invalidateMenu then ddBtn._invalidateMenu() end
    end
    local function Attach(btn) ddBtn = btn end
    return values, order, Update, Attach
end

-------------------------------------------------------------------------------
--  Widget helpers
-------------------------------------------------------------------------------
-- One frame, moved into each build of the tab: its show and hide are the
-- tab's, so the runtime registers the events behind the live pickers and
-- cards only while the tab is on screen.
local pageWatch
local function WatchPage(parent)
    if EllesmereUI._prebuilding then return end
    if not pageWatch then
        pageWatch = CreateFrame("Frame")
        pageWatch._searchIgnore = true -- the inline search never hides it
        pageWatch:SetScript("OnShow", function() LM.SetPageShown(true) end)
        pageWatch:SetScript("OnHide", function() LM.SetPageShown(false) end)
    end
    pageWatch:Hide()
    pageWatch:SetParent(parent)
    pageWatch:Show()
end

-------------------------------------------------------------------------------
--  Card pieces, shared with the Talent Reminders tab (ns.Card*): both tabs
--  list one house module card per spec, its rows in the same look.
-------------------------------------------------------------------------------
-- A red outline that pulses on a control the Add button needs filled, rounded
-- like the dropdowns' own: built once per control.
local function CardPulse(target)
    if not target then return end
    local rf = target._cardPulse
    if not rf then
        rf = CreateFrame("Frame", nil, target)
        rf:SetAllPoints()
        rf:SetFrameLevel(target:GetFrameLevel() + 10)
        EllesmereUI.MakeRoundedBorder(rf, 1, 0.2, 0.2, 1)
        target._cardPulse = rf
    end
    rf:Show()
    rf:SetAlpha(1)
    local elapsed = 0
    rf:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed < 0.8 then
            self:SetAlpha(0.5 + 0.5 * math.sin(elapsed * 10))
        elseif elapsed < 1.5 then
            self:SetAlpha(math.max(0, 1 - (elapsed - 0.8) / 0.7))
        else
            self:SetScript("OnUpdate", nil)
            self:Hide()
        end
    end)
end

-- A card's icon in a 1px black border: the spec's icon, else the class's cell
-- of the stock class sheet (cropped past its bevel).
local CLASS_ICONS = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local function CardGlyph(hdr, specIcon, class)
    local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if not specIcon and not coords then return end
    local box = CreateFrame("Frame", nil, hdr)
    PP.Size(box, 24, 24)
    PP.Point(box, "LEFT", hdr, "LEFT", 14, 0)
    local icon = box:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    if specIcon then
        icon:SetTexture(specIcon)
        icon:SetTexCoord(.08, .92, .08, .92)
    else
        local du, dv = (coords[2] - coords[1]) * 0.1, (coords[4] - coords[3]) * 0.1
        icon:SetTexture(CLASS_ICONS)
        icon:SetTexCoord(coords[1] + du, coords[2] - du, coords[3] + dv, coords[4] - dv)
    end
    EllesmereUI.MakeBorder(box, 0, 0, 0, 1, PP)
end

-- A card's list row, h tall: the alternating shade, and with divider the
-- centre line between two halves.
local function CardRow(parent, cy, h, shade, divider)
    local row = CreateFrame("Frame", nil, parent)
    PP.Size(row, parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2, h)
    PP.Point(row, "TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD, cy)
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, shade and 0.2 or 0.1)
    if divider then
        local div = row:CreateTexture(nil, "ARTWORK")
        div:SetColorTexture(1, 1, 1, 0.06)
        div:SetWidth(1)
        PP.Point(div, "TOP", row, "TOP", 0, 0)
        PP.Point(div, "BOTTOM", row, "BOTTOM", 0, 0)
    end
    return row
end

-- The card's title (its description line hangs off it) in the class colour
-- at full strength.
local function CardClassTitle(tile, class)
    if not class then return end
    local _, title = tile._descFS:GetPoint(1)
    if title and title.SetTextColor then
        local c = EllesmereUI.GetClassColor(class)
        if c then title:SetTextColor(c.r, c.g, c.b, 1) end
    end
end

ns.CardPulse, ns.CardGlyph, ns.CardRow, ns.CardClassTitle = CardPulse, CardGlyph, CardRow, CardClassTitle

-------------------------------------------------------------------------------
--  The Activities checklist. The items are read again on every open: which
--  activity another loadout of your spec holds can change between opens.
-------------------------------------------------------------------------------
local ACTIVITY_TIPS = {
    raidm   = "This season's raid on Mythic.",
    raidn   = "This season's raid on Normal, Heroic and Raid Finder.",
    raidold = "Every other raid, on any difficulty.",
    tw      = "Timewalking dungeons and raids.",
    world   = "Applies when you leave an instance.",
    riding  = "Gear only. Worn while you are mounted in the open world; your previous gear comes back when you dismount.",
}

-- The keys an "All" entry ticks.
local function GroupKeys(g)
    local keys = {}
    for _, e in ipairs(g.list()) do keys[#keys + 1] = g.prefix .. e.id end
    return keys
end

-- Every activity the checklist lists, in its order.
local function ActivityKeys()
    local keys = {}
    if FOREVER then
        for _, k in ipairs(LM.ActivityOrder()) do keys[#keys + 1] = k end
        return keys
    end
    for _, k in ipairs(GroupKeys(GROUPS[1])) do keys[#keys + 1] = k end
    for _, k in ipairs(RAID_KEYS) do keys[#keys + 1] = k end
    for _, k in ipairs(GroupKeys(GROUPS[2])) do keys[#keys + 1] = k end
    for _, k in ipairs(GroupKeys(GROUPS[3])) do keys[#keys + 1] = k end
    for _, k in ipairs(OTHER_KEYS) do keys[#keys + 1] = k end
    return keys
end

local function True() return true end

-------------------------------------------------------------------------------
--  The Activities checklist, shared by the Loadout Manager's add row and the
--  Talent Reminders tab (its add form, and each reminder's activities and Not
--  Needed activities): the same list, groups and "All" entries everywhere.
--  spec:
--    get(key) -> bool, set(key, on)  one activity; an "All" entry reads and
--      writes its group's rows through them, leaving out its locked rows
--    locked(key) -> bool, lockedTooltip(key)  a row that cannot change
--    groupLocked(keys) -> bool, groupLockedTooltip  a ticked "All" entry that
--      cannot be unticked (keys: its unlocked rows)
--    dim(key) -> bool, dimTooltip(key)  a row resting dimmed, still clickable
--    top = { { label = , onClick = }, ... }  actions above the list
--    mplusTip  the Mythic+ Dungeons header's tooltip
--    maxVisible (14), emptyLabel ("Select Activities")
--  Returns the dropdown button and its refresh (as BuildVisOptsCBDropdown).
-------------------------------------------------------------------------------
local function BuildActivityChecklist(parent, w, level, spec)
    local function Locked(key) return (spec.locked and spec.locked(key)) and true or false end
    local function Unlocked(g)
        local keys = {}
        for _, k in ipairs(GroupKeys(g)) do
            if not Locked(k) then keys[#keys + 1] = k end
        end
        return keys
    end
    local function Get(key)
        local g = GROUP_BY_ALL[key]
        if not g then return spec.get(key) and true or false end
        local keys = Unlocked(g)
        for _, k in ipairs(keys) do
            if not spec.get(k) then return false end
        end
        return #keys > 0
    end
    local function Set(key, on)
        local g = GROUP_BY_ALL[key]
        if not g then spec.set(key, on) return end
        for _, k in ipairs(Unlocked(g)) do spec.set(k, on) end
    end
    local function Item(key, label)
        return {
            key = key, label = label, tooltip = ACTIVITY_TIPS[key],
            dimFn = spec.dim and function() return spec.dim(key) end,
            dimTooltip = spec.dimTooltip and function() return spec.dimTooltip(key) end,
            lockedFn = spec.locked and function() return Locked(key) end,
            lockedTooltip = spec.lockedTooltip and function() return spec.lockedTooltip(key) end,
        }
    end
    local function Items()
        local items = {}
        for _, t in ipairs(spec.top or {}) do
            items[#items + 1] = { isTopAction = true, label = t.label, onClick = t.onClick }
        end
        if FOREVER then
            for _, key in ipairs(LM.ActivityOrder()) do items[#items + 1] = Item(key, LM.ActivityLabel(key)) end
            return items
        end
        -- A group: its header, its "All" entry, then its places.
        local function Group(g, header, tooltip)
            items[#items + 1] = { isHeader = true, label = header, tooltip = tooltip }
            items[#items + 1] = { key = g.all, label = g.allLabel, excludeFromSummaryFn = True,
                lockedFn = function()
                    local keys = Unlocked(g)
                    if #keys == 0 then return true end
                    return (spec.groupLocked and Get(g.all) and spec.groupLocked(keys)) and true or false
                end,
                lockedTooltip = function()
                    if #Unlocked(g) == 0 then
                        local first = GroupKeys(g)[1]
                        return first and spec.lockedTooltip and spec.lockedTooltip(first) or nil
                    end
                    return spec.groupLockedTooltip
                end }
            for _, e in ipairs(g.list()) do items[#items + 1] = Item(g.prefix .. e.id, e.name) end
        end
        Group(GROUPS[1], "Mythic+ Dungeons", spec.mplusTip or "On Mythic and in keys. Normal and Heroic runs swap nothing.")
        items[#items + 1] = { isHeader = true, label = "Raids" }
        for _, key in ipairs(RAID_KEYS) do items[#items + 1] = Item(key, LM.ActivityLabel(key)) end
        Group(GROUPS[2], "Arenas")
        Group(GROUPS[3], "Battlegrounds")
        items[#items + 1] = { isHeader = true, label = "Other" }
        for _, key in ipairs(OTHER_KEYS) do items[#items + 1] = Item(key, LM.ActivityLabel(key)) end
        return items
    end
    -- The button reads as a loadout row does ("All Arenas, Murder Row").
    local function Summary()
        local set = {}
        for _, k in ipairs(ActivityKeys()) do
            if spec.get(k) then set[k] = true end
        end
        if not next(set) then return nil end
        return ActivitiesText(set, Locked)
    end
    return EllesmereUI.BuildVisOptsCBDropdown(parent, w, level, Items, Get, Set, nil,
        spec.maxVisible or 14, false, false, nil,
        { emptyLabel = spec.emptyLabel or "Select Activities", noAllLabel = true, dimLocked = true,
          summaryFn = Summary })
end
ns.BuildActivityChecklist = BuildActivityChecklist
ns.ActivityKeys = ActivityKeys

-------------------------------------------------------------------------------
--  The tab
-------------------------------------------------------------------------------
-- Why the Add button refused, shown on it.
local REFUSALS = {
    nospec     = "Choose a specialization first.",
    nochar     = "Your character's data is not ready yet. Try again in a moment.",
    ridinggear = "Riding needs a gear set.",
}

function ns._BuildLoadoutPage(_, parent, yOffset)
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h

    parent._showRowDivider = true
    EllesmereUI:ClearContentHeader()
    WatchPage(parent)

    ---------------------------------------------------------------------------
    --  General: the master switch, what swaps on its own (timing on the cog),
    --  and the two ways a swap is announced
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "GENERAL", y); y = y - h

    local swapRow
    swapRow, h = W:DualRow(parent, y,
        { type = "toggle", text = "Enable Loadout Manager",
          tooltip = "Swaps gear and talents as you change content.",
          getValue = function() return DB().enabled end,
          -- Builds the tab again: off, the tab is this row alone.
          setValue = function(v) LM.SetEnabled(v) Refresh(true) end },
        -- What swaps on its own: a view over gearEnabled, talentEnabled and
        -- askBeforeSwap (LM.GetSwapMode / LM.SetSwapMode).
        { type = "dropdown", text = "Auto-Swap",
          tooltip = "What swaps on its own. Ask Before Swap asks Yes or No before every swap.",
          values = {
              ask    = "Ask Before Swap",
              gear   = "Auto-Swap Gear",
              talent = "Auto-Swap Talents",
              both   = "Auto-Swap Both",
          },
          order = { "ask", "gear", "talent", "both" },
          getValue = function() return LM.GetSwapMode() end,
          setValue = function(v) LM.SetSwapMode(v) Refresh() end,
          disabled = NotEnabled, disabledTooltip = "Loadout Manager" }
    ); y = y - h

    EllesmereUI.BuildInlineCog(swapRow._rightRegion, {
        title = "Auto-Swap",
        rows = {
            { type = "toggle", label = "Queue In Combat",
              tooltip = "Apply a swap due in combat once it ends.",
              get = function() return DB().queueInCombat and true or false end,
              set = function(v) LM.SetQueueInCombat(v) end },
            { type = "toggle", label = "Re-Swap On Spec Change",
              tooltip = "Swap again on a spec change in an instance.",
              get = function() return DB().specSwap and true or false end,
              set = function(v) DB().specSwap = v and true or false end },
        },
        disabled = NotEnabled, disabledTooltip = "Loadout Manager",
    })

    -- Off, the tab is the switch alone: Enable Loadout Manager with the greyed
    -- Auto-Swap beside it. The search pre-build sees the same tab.
    if NotEnabled() then
        _, h = W:Spacer(parent, y, 20); y = y - h
        parent:SetHeight(math.abs(y - yOffset))
        return math.abs(y)
    end

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Talent-Change Warning",
          tooltip = "Show DON'T MOVE while talents change.",
          getValue = function() return DB().specWarning and true or false end,
          setValue = function(v) LM.SetSpecWarning(v) end },
        { type = "toggle", text = "Announce Swaps In Chat",
          getValue = function() return DB().announce and true or false end,
          setValue = function(v) DB().announce = v and true or false end }
    ); y = y - h

    -- The add row and the cards are frames of their own: the search pre-build
    -- indexes the rows above, never these.
    if EllesmereUI._prebuilding then
        parent:SetHeight(math.abs(y - yOffset))
        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  The add row, a space under GENERAL with no header: Activities | Gear
    --  Set | Talent Loadout, side by side and centred, Add Loadout under them
    --  (the Talent Reminders tab's layout)
    ---------------------------------------------------------------------------
    local CONTENT_PAD = 45
    local DD_H, DD_GAP = 38, 12
    y = y - 30
    local addRow = CreateFrame("Frame", nil, parent)
    local rowW = parent:GetWidth() - CONTENT_PAD * 2
    PP.Size(addRow, rowW, DD_H + 12)
    PP.Point(addRow, "TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, y)
    -- Each 260 wide, narrower when the row cannot hold three.
    local DD_W = math.min(260, math.floor((rowW - DD_GAP * 2) / 3))
    local startX = math.floor((rowW - (DD_W * 3 + DD_GAP * 2)) / 2)
    local level = addRow:GetFrameLevel() + 2

    local actDD = BuildActivityChecklist(addRow, DD_W, level, {
        get = function(key) return pend.acts[key] == true end,
        set = function(key, on) pend.acts[key] = on or nil end,
        -- Dimmed while a loadout holds it where this one lands (your spec; on
        -- WoW Forever the picked talents' spec group); adding moves it.
        dim = function(key) return LM.HolderOf(key, pend.talentKey) ~= nil end,
        dimTooltip = function(key)
            local lo = LM.HolderOf(key, pend.talentKey)
            if not lo then return nil end
            return EllesmereUI.Lf("Used by %s. Adding moves it to the new loadout.", LoadoutName(lo))
        end,
    })
    PP.Size(actDD, DD_W, DD_H)
    PP.Point(actDD, "TOPLEFT", addRow, "TOPLEFT", startX, 0)
    actDD._ttText = "The activities this loadout applies to. Each activity holds one loadout per spec."

    local gearValues, gearOrder, gearUpdate, gearAttach = LivePicker(
        DIM .. EllesmereUI.L("No Gear Set") .. "|r", GearEntries,
        { icon = function(key)
              local icon = gearIcons[key]
              if icon then return icon, 0.08, 0.92, 0.08, 0.92 end
          end })
    local talentValues, talentOrder, talentUpdate, talentAttach = LivePicker(
        DIM .. EllesmereUI.L("No Talent Loadout") .. "|r", TalentEntries)
    EllesmereUI.RegisterWidgetRefresh(gearUpdate)
    EllesmereUI.RegisterWidgetRefresh(talentUpdate)
    -- A pick counts only while its list holds it: a renamed or deleted set, or
    -- a loadout of another spec, reads as none.
    local function GearPick()
        if pend.gear ~= nil and gearValues[pend.gear] ~= nil then return pend.gear end
    end
    local function TalentPickKey()
        if pend.talentKey ~= nil and talentValues[pend.talentKey] ~= nil then return pend.talentKey end
    end

    local gearDD = EllesmereUI.BuildDropdownControl(addRow, DD_W, level, gearValues, gearOrder,
        function() return GearPick() or NONE end,
        function(v) pend.gear = (v ~= NONE) and v or nil end)
    PP.Size(gearDD, DD_W, DD_H)
    PP.Point(gearDD, "TOPLEFT", addRow, "TOPLEFT", startX + DD_W + DD_GAP, 0)
    gearDD._ttText = "The Equipment Manager set this loadout equips."
    gearAttach(gearDD)

    local talentDD = EllesmereUI.BuildDropdownControl(addRow, DD_W, level, talentValues, talentOrder,
        function() return TalentPickKey() or NONE end,
        function(v) pend.talentKey = (v ~= NONE) and v or nil end)
    PP.Size(talentDD, DD_W, DD_H)
    PP.Point(talentDD, "TOPLEFT", addRow, "TOPLEFT", startX + (DD_W + DD_GAP) * 2, 0)
    talentDD._ttText = FOREVER and "The spec (Primary or Secondary) this loadout switches to."
        or "The talent loadout this loadout loads. Your current spec's loadouts are listed."
    talentAttach(talentDD)
    -- The pickers' lists refill first (registered above), then their labels:
    -- a pick renamed or deleted in the game reads as none.
    EllesmereUI.RegisterWidgetRefresh(function()
        gearDD._refreshLabel()
        talentDD._refreshLabel()
    end)

    y = y - (DD_H + 12)
    _, h = W:Spacer(parent, y, 10); y = y - h

    local addFrame = CreateFrame("Frame", nil, parent)
    PP.Size(addFrame, parent:GetWidth() or 400, 38)
    PP.Point(addFrame, "TOPLEFT", parent, "TOPLEFT", 0, y)
    local eg = EllesmereUI.ELLESMERE_GREEN
    local addBtn = EllesmereUI.MakeActionButton(addFrame, EllesmereUI.EXPRESSWAY, EllesmereUI.L("Add Loadout"),
        eg.r, eg.g, eg.b, { w = 160 })
    PP.Point(addBtn, "CENTER", addFrame, "CENTER", 0, 0)
    local onEnter, onLeave = addBtn:GetScript("OnEnter"), addBtn:GetScript("OnLeave")
    addBtn:SetScript("OnLeave", function(self) onLeave(self) EllesmereUI.HideWidgetTooltip() end)
    addBtn:SetScript("OnEnter", onEnter)
    addBtn:SetScript("OnClick", function(self)
        local talent
        local key = TalentPickKey()
        if key then
            for _, loadout in ipairs(LM.ListTalentLoadouts()) do
                if tostring(loadout.configID) == key then talent = LM.StoreTalentLoadout(loadout) break end
            end
        end
        local acts = {}
        for k in pairs(pend.acts) do acts[k] = true end
        local ok, why, bucket = LM.AddLoadout(GearPick(), talent, acts)
        if not ok then
            if why == "noacts" then
                CardPulse(actDD)
            elseif why == "empty" then
                CardPulse(gearDD)
                CardPulse(talentDD)
            else
                if why == "ridinggear" then CardPulse(gearDD) end
                EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.L(REFUSALS[why] or "Could not add the loadout."))
            end
            return
        end
        wipe(pend.acts)
        pend.gear, pend.talentKey = nil, nil
        -- The card it went to opens (WoW Forever: its talents' spec group).
        if bucket ~= nil then cardOpen[bucket] = true end
        Refresh(true)
    end)
    y = y - 38

    ---------------------------------------------------------------------------
    --  The loadouts: one card per spec (WoW Forever: per spec group, and one
    --  for the character holding what both groups share), your spec open and,
    --  on retail, first
    ---------------------------------------------------------------------------
    _, h = W:Spacer(parent, y, 15); y = y - h
    _, h = W:SectionHeader(parent, "LOADOUTS", y); y = y - h

    local fontPath = EllesmereUI.GetFontPath("auraBuff") or EllesmereUI.EXPRESSWAY
    local outline = EllesmereUI.GetFontOutlineFlag("auraBuff")
    local ROW_H, SIDE_PAD = 50, 20

    -- One loadout: its gear set's icon, its gear and talents, its activities
    -- under them, and Delete at the right.
    local function BuildLoadoutRow(bucket, index, lo, cy, shade)
        local row = CardRow(parent, cy, ROW_H, shade)
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(26, 26)
        icon:SetPoint("LEFT", row, "LEFT", SIDE_PAD, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:SetTexture((lo.gear and gearIcons[lo.gear]) or 134400)

        local del = EllesmereUI.BuildInlineButton(row, "Delete", function()
            LM.DeleteLoadout(bucket, index)
            Refresh(true)
        end, { width = 70, tip = "Delete this loadout." })

        local nameFS = row:CreateFontString(nil, "OVERLAY")
        nameFS:SetFont(fontPath, 14, outline)
        nameFS:SetTextColor(1, 1, 1, 1)
        nameFS:SetJustifyH("LEFT")
        nameFS:SetWordWrap(false)
        nameFS:SetMaxLines(1)
        nameFS:SetPoint("BOTTOMLEFT", row, "LEFT", SIDE_PAD + 26 + 10, 1)
        nameFS:SetPoint("RIGHT", del, "LEFT", -12, 0)
        nameFS:SetText(LoadoutName(lo))

        local actFS = row:CreateFontString(nil, "OVERLAY")
        actFS:SetFont(fontPath, 12, outline)
        actFS:SetTextColor(0.6, 0.6, 0.6, 1)
        actFS:SetJustifyH("LEFT")
        actFS:SetWordWrap(false)
        actFS:SetMaxLines(1)
        actFS:SetPoint("TOPLEFT", row, "LEFT", SIDE_PAD + 26 + 10, -3)
        actFS:SetPoint("RIGHT", del, "LEFT", -12, 0)
        actFS:SetText(ActivitiesText(type(lo.acts) == "table" and lo.acts or {}))

        -- A cut line shows whole on hover.
        row:SetScript("OnEnter", function()
            if actFS:IsTruncated() or nameFS:IsTruncated() then
                EllesmereUI.ShowWidgetTooltip(row, nameFS:GetText() .. "\n" .. actFS:GetText())
            end
        end)
        row:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        return ROW_H
    end

    local buckets = LM.Buckets()
    local current = LM.BucketKey()
    local ordered, taken = {}, {}
    local function Take(key)
        local list = key ~= nil and buckets[key]
        if type(list) == "table" and #list > 0 and not taken[key] then
            taken[key] = true
            ordered[#ordered + 1] = key
        end
    end
    -- WoW Forever keeps Primary above Secondary, whichever is active.
    if not FOREVER then Take(current) end
    for _, spec in ipairs(LM.GetSpecList()) do Take(spec.id) end
    for key in pairs(buckets) do Take(key) end

    if #ordered == 0 then
        local row = CardRow(parent, y, ROW_H, false)
        local emptyFS = row:CreateFontString(nil, "OVERLAY")
        emptyFS:SetFont(fontPath, 13, outline)
        emptyFS:SetTextColor(0.5, 0.5, 0.5, 1)
        emptyFS:SetPoint("CENTER")
        emptyFS:SetText(EllesmereUI.L("No loadouts yet"))
        y = y - ROW_H
    end

    -- Your spec's card starts open, the others closed.
    if current ~= nil and cardOpen[current] == nil then cardOpen[current] = true end

    local _, playerClass = UnitClass("player")
    for _, key in ipairs(ordered) do
        local list = buckets[key]
        local display, specIcon, class = nil, nil, playerClass
        if FOREVER then
            -- A spec group's card carries its name; the shared card the class.
            display = key ~= 0 and LM.SpecName(key)
                or LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[playerClass] or tostring(playerClass)
        else
            local _, specName, _, icon, _, classFile, className
            if GetSpecializationInfoByID then
                _, specName, _, icon, _, classFile, className = GetSpecializationInfoByID(key)
            end
            specIcon, class = icon, classFile or playerClass
            display = (specName and className) and (specName .. " " .. className) or tostring(LM.SpecName(key))
        end
        local tile = { key = key, display = display,
            desc = EllesmereUI.L("Loadouts") .. ": " .. #list,
            buildContent = function(_, cy)
                for i, lo in ipairs(list) do
                    cy = cy - BuildLoadoutRow(key, i, lo, cy, i % 2 == 0)
                end
                return cy
            end }
        y = EllesmereUI.BuildModuleCard(parent, y, W, tile, {
            enabled = true, expanded = cardOpen, descW = 440, noSearch = true,
            glyph = function(hdr) CardGlyph(hdr, specIcon, class) end,
            deleteTip = "Delete all of this card's loadouts.",
            onDelete = function()
                EllesmereUI:ShowConfirmPopup({
                    title = "Delete Loadouts",
                    message = EllesmereUI.Lf("Delete all %1$d loadouts for %2$s?", #list, display),
                    confirmText = "Delete",
                    cancelText = "Cancel",
                    onConfirm = function()
                        LM.ClearBucket(key)
                        cardOpen[key] = nil
                        Refresh(true)
                    end,
                })
            end })
        CardClassTitle(tile, class)
    end

    _, h = W:Spacer(parent, y, 20); y = y - h
    parent:SetHeight(math.abs(y - yOffset))
    return math.abs(y)
end
