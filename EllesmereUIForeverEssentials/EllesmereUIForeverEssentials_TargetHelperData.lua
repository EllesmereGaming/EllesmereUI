if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_TargetHelperData.lua  (WoW Forever only)
--  The Target Helper's settings and target list. Targets come from two
--  sources:
--    quest  unfinished kill objectives of the quests in the log
--    farm   mob names the player added, each kept with the zone it was added
--           in, optionally bound to one area (sub zone) and a category
--  The bar (EllesmereUIForeverEssentials_TargetHelper.lua, listed after this
--  file) shows them grouped by category: quest title or farm category.
-------------------------------------------------------------------------------
local _, module = ...

local TH = {}
module.TargetHelper = TH

-- Settings live in EllesmereUIDB.targetHelper; unset keys read these.
-- The table settings (farm, hidden, markers, npcIds, folded) are made on
-- first write, see Tbl.
local DEFAULTS = {
    enabled = false,
    width = 200,
    showQuests = true,      -- quest kill objectives on the bar
    questsFirst = true,
    zoneOnly = true,        -- only targets of the current zone
    showCategories = true,  -- group the bar by quest / farm category
    showPortraits = true,   -- small 3D head of the mob on each row
    skipDead = true,        -- drop corpses after /targetexact
    skipMarked = true,      -- don't pick mobs a group member marked
    skipTapped = true,      -- don't pick mobs tagged by other players
    defaultMarker = 8,      -- skull
    collapsed = false,      -- whole bar folded to its header
}
local F = module.Feature("targetHelper", DEFAULTS,
    { point = "TOPRIGHT", relPoint = "RIGHT", x = -260, y = 250 })
TH.F = F
local Get, Cfg = F.Get, F.Cfg

local EMPTY = {}
-- A table setting for reading (never created) and for writing.
local function Read(key) return F.Read()[key] or EMPTY end
local function Tbl(key)
    local c = Cfg()
    local t = c[key]
    if not t then
        t = {}
        c[key] = t
    end
    return t
end
TH.Read, TH.Tbl = Read, Tbl

TH.FARM_CATEGORY = "Farm"

function TH.MarkerTexture(i)
    if i and i >= 1 and i <= 8 then return "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i end
end
TH.NO_MARKER = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"

-- Plain value or nil when the client hides it.
local function Plain(v)
    if v == nil or issecretvalue(v) then return nil end
    return v
end
TH.Plain = Plain

local function Trim(s)
    return ((s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end
TH.Trim = Trim

function TH.UnitNameOf(unit)
    return Plain(UnitName(unit))
end

function TH.Zone()
    local z = Plain(GetRealZoneText())
    if z and z ~= "" then return z end
end

function TH.SubZone()
    local z = Plain(GetSubZoneText())
    if z and z ~= "" then return z end
end

-- Fired after any change to the target list; the bar and the options page
-- set these.
local listeners = {}
function TH.OnChange(fn) listeners[#listeners + 1] = fn end
local function Changed()
    for i = 1, #listeners do listeners[i]() end
end
TH.Changed = Changed

-------------------------------------------------------------------------------
--  Markers
-------------------------------------------------------------------------------
function TH.MarkerFor(name)
    local m = Read("markers")[name]
    if m == nil then m = Get("defaultMarker") end
    return m
end

function TH.SetMarker(name, marker)
    if marker == Get("defaultMarker") then marker = nil end
    Tbl("markers")[name] = marker
    Changed()
end

-------------------------------------------------------------------------------
--  Farm list: { name, zone, sub, cat } in bar order
-------------------------------------------------------------------------------
local function FarmIndex(name)
    local lower = name:lower()
    for i, f in ipairs(Read("farm")) do
        if f.name:lower() == lower then return i end
    end
end

local function FarmEntry(name)
    local i = FarmIndex(name)
    return i and Read("farm")[i]
end
TH.FarmEntry = FarmEntry

function TH.FarmCategory(name)
    local f = FarmEntry(name)
    return f and f.cat or TH.FARM_CATEGORY
end

function TH.AddFarm(name)
    name = Trim(name)
    if name == "" then return false end
    if FarmIndex(name) then
        EllesmereUI.Print(EllesmereUI.Lf("%s is already on the farm list.", name))
        return false
    end
    local farm = Tbl("farm")
    farm[#farm + 1] = { name = name, zone = TH.Zone() }
    Changed()
    return true
end

function TH.AddCurrentTarget()
    if not UnitExists("target") then
        EllesmereUI.Print(EllesmereUI.L("You have no target."))
        return
    end
    if UnitIsPlayer("target") then
        EllesmereUI.Print(EllesmereUI.L("Players can't be added."))
        return
    end
    local name = TH.UnitNameOf("target")
    if not name then
        EllesmereUI.Print(EllesmereUI.L("The target's name can't be read right now."))
        return
    end
    if TH.AddFarm(name) then EllesmereUI.Print(EllesmereUI.Lf("%s added to the farm list.", name)) end
end

function TH.RemoveFarm(name)
    local i = FarmIndex(name)
    if not i then return end
    table.remove(Tbl("farm"), i)
    Changed()
end

-- Index of the neighbour in the same category in direction delta (-1 / 1).
function TH.FarmNeighbour(name, delta)
    local farm, i = Read("farm"), FarmIndex(name)
    if not i then return end
    local cat = TH.FarmCategory(name)
    local j = i + delta
    while farm[j] do
        if (farm[j].cat or TH.FARM_CATEGORY) == cat then return j end
        j = j + delta
    end
end

function TH.MoveFarm(name, delta)
    local i, j = FarmIndex(name), TH.FarmNeighbour(name, delta)
    if not (i and j) then return end
    local farm = Tbl("farm")
    farm[i], farm[j] = farm[j], farm[i]
    Changed()
end

local function SetFarmField(name, key, value)
    local f = FarmEntry(name)
    if not f then return end
    f[key] = value
    Changed()
end

-- Restricts a farm target to one area of the current zone (nil: whole zone).
function TH.SetFarmSub(name, sub)
    local f = FarmEntry(name)
    if not f then return end
    f.sub = sub
    if sub then f.zone = TH.Zone() or f.zone end
    Changed()
end

function TH.SetFarmCategory(name, cat)
    cat = Trim(cat)
    if cat == "" or cat == TH.FARM_CATEGORY then cat = nil end
    SetFarmField(name, "cat", cat)
end

-- The area always applies; the zone only with Current Zone Only.
function TH.FarmInZone(f)
    if f.sub and f.sub ~= TH.SubZone() then return false end
    if not Get("zoneOnly") and not f.sub then return true end
    return f.zone ~= nil and f.zone == TH.Zone()
end

-- Context menu items for a farm target (bar row and options list).
function TH.FarmMenuItems(name, items)
    local f = FarmEntry(name)
    if not f then return items end
    local here, zone = TH.SubZone(), TH.Zone()
    if f.sub then
        items[#items + 1] = { text = EllesmereUI.L("Show in Whole Zone"), onClick = function() TH.SetFarmSub(name, nil) end }
    end
    if here and here ~= f.sub then
        items[#items + 1] = { text = EllesmereUI.Lf("Only in %s", here), onClick = function() TH.SetFarmSub(name, here) end }
    end
    if zone and f.zone ~= zone then
        items[#items + 1] = { text = EllesmereUI.Lf("Set Zone to %s", zone), onClick = function()
            f.zone, f.sub = zone, nil
            Changed()
        end }
    end
    items[#items + 1] = { text = EllesmereUI.Lf("Category: %s", TH.FarmCategory(name)), onClick = function()
        EllesmereUI:ShowInputPopup({
            title = EllesmereUI.L("Farm Category"),
            message = EllesmereUI.Lf("Category for %s on the bar.", name),
            placeholder = TH.FarmCategory(name),
            confirmText = EllesmereUI.L("Save"),
            allowEmpty = true,
            onConfirm = function(text) TH.SetFarmCategory(name, text or "") end,
        })
    end }
    items[#items + 1] = { text = EllesmereUI.L("Remove from Farm List"), onClick = function() TH.RemoveFarm(name) end }
    return items
end

-- The marker submenu: the eight raid icons and "no marker".
function TH.MarkerMenu(current, onPick)
    local children = {}
    for m = 8, 0, -1 do
        local tex = TH.MarkerTexture(m) or TH.NO_MARKER
        local label = m > 0 and _G["RAID_TARGET_" .. m] or EllesmereUI.L("No Marker")
        children[#children + 1] = {
            text = "|T" .. tex .. ":14:14|t  " .. label,
            isActive = m == current,
            onClick = function() onPick(m) end,
        }
    end
    return { text = EllesmereUI.L("Marker"), children = children }
end

-------------------------------------------------------------------------------
--  Quest log
--  Kill objectives ("Kobold Vermin slain: 3/10") name the mob, so they become
--  targets. A quest belongs to the zone of its quest log header; quests the
--  client puts on the current map count too. Quests under a collapsed log
--  header are not visible to the API.
-------------------------------------------------------------------------------
local quests = {}   -- { title, questID, zone, objectives = { ... } }
local targets = {}  -- unfinished kill objectives

-- The words of the client's kill objective format ("slain"), stripped from
-- objective texts to leave the mob's name.
local killWord
local function KillWord()
    if not killWord then
        local f = QUEST_MONSTERS_KILLED or "%s slain: %d/%d"
        killWord = Trim((f:gsub("%%%d*%$?[sd]", ""):gsub("[:/]", "")))
    end
    return killWord
end

local function ParseName(text, isKill)
    text = Plain(text)
    if type(text) ~= "string" or text == "" then return end
    local s = text:gsub("%d+%s*/%s*%d+", "")
    if isKill then
        local w = KillWord()
        local pos = w ~= "" and s:find(w, 1, true)
        if pos then s = s:sub(1, pos - 1) .. s:sub(pos + #w) end
    end
    s = Trim((s:gsub(":", ""):gsub("%s+", " ")))
    if s ~= "" then return s end
end

local function Scan()
    wipe(quests)
    wipe(targets)
    local header
    for i = 1, C_QuestLog.GetNumQuestLogEntries() or 0 do
        local info = C_QuestLog.GetInfo(i)
        if info and info.isHeader then
            header = info.title
        elseif info and info.title and not info.isHidden then
            local id = info.questID or 0
            local q = { title = info.title, questID = id, zone = header, objectives = {} }
            for _, o in ipairs(id > 0 and C_QuestLog.GetQuestObjectives(id) or EMPTY) do
                local kill = o.type == "monster"
                local ob = { text = o.text, type = o.type, finished = o.finished,
                    have = o.numFulfilled, need = o.numRequired, name = ParseName(o.text, kill) }
                ob.kill = kill and ob.name ~= nil
                if ob.kill then
                    ob.key = id .. ":" .. ob.name
                    if not ob.finished then
                        targets[#targets + 1] = { key = ob.key, name = ob.name, title = info.title,
                            have = ob.have, need = ob.need, questID = id, zone = header }
                    end
                end
                q.objectives[#q.objectives + 1] = ob
            end
            quests[#quests + 1] = q
        end
    end
    Changed()
end

-- q: a quest or quest target (both carry questID and zone)
function TH.QuestInZone(q)
    local zone = TH.Zone()
    if q.zone and zone and q.zone == zone then return true end
    return q.questID > 0 and Plain(C_QuestLog.IsOnMap(q.questID)) == true
end

function TH.Quests() return quests end

function TH.SetQuestHidden(key, hidden)
    Tbl("hidden")[key] = hidden or nil
    Changed()
end

-- The quest log fires bursts of updates: one scan per burst.
local scanPending
local function QueueScan()
    if scanPending then return end
    scanPending = true
    C_Timer.After(0.3, function()
        scanPending = false
        if F.Enabled() then Scan() end
    end)
end

-------------------------------------------------------------------------------
--  Target list for the bar
--  entry = { name, marker, farm = bool, quests = { quest target, ... }, cat }
-------------------------------------------------------------------------------
function TH.BuildTargets()
    local list, byName = {}, {}
    local function Add(name)
        local e = byName[name]
        if not e then
            e = { name = name, marker = TH.MarkerFor(name), quests = {} }
            byName[name] = e
            list[#list + 1] = e
        end
        return e
    end
    local function AddQuests()
        if not Get("showQuests") then return end
        local hidden, zoneOnly = Read("hidden"), Get("zoneOnly")
        for _, t in ipairs(targets) do
            if not hidden[t.key] and (not zoneOnly or TH.QuestInZone(t)) then
                local e = Add(t.name)
                e.quests[#e.quests + 1] = t
            end
        end
    end
    local function AddFarm()
        for _, f in ipairs(Read("farm")) do
            if TH.FarmInZone(f) then Add(f.name).farm = true end
        end
    end
    if Get("questsFirst") then
        AddQuests()
        AddFarm()
    else
        AddFarm()
        AddQuests()
    end

    -- Grouped by category, categories in first-seen order.
    local order, groups = {}, {}
    for _, e in ipairs(list) do
        e.cat = e.quests[1] and e.quests[1].title or TH.FarmCategory(e.name)
        if not groups[e.cat] then
            groups[e.cat] = {}
            order[#order + 1] = e.cat
        end
        table.insert(groups[e.cat], e)
    end
    local sorted = {}
    for _, cat in ipairs(order) do
        for _, e in ipairs(groups[cat]) do sorted[#sorted + 1] = e end
    end
    return sorted
end

-------------------------------------------------------------------------------
--  Macros run by a target button. Marking goes through /tm inside the secure
--  macro ("!" sets the marker and never toggles it off).
-------------------------------------------------------------------------------
local function Join(lines, marker)
    if marker and marker > 0 then lines[#lines + 1] = "/tm !" .. marker end
    return table.concat(lines, "\n")
end

-- The nearest mob with that name (combat, or no usable nameplate).
function TH.MacroFor(name, marker)
    local lines = { "/cleartarget", "/targetexact " .. name }
    if Get("skipDead") then lines[#lines + 1] = "/cleartarget [dead]" end
    return Join(lines, marker)
end

-- A nameplate unit picked out of combat.
function TH.MacroForUnit(unit, marker)
    return Join({ "/cleartarget", "/target " .. unit }, marker)
end

-- The target already is this mob: only (re)set the marker.
function TH.MacroKeep(marker)
    return Join({}, marker)
end

-------------------------------------------------------------------------------
--  Quest and zone events, registered while the helper is on.
-------------------------------------------------------------------------------
local QUEST_EVENTS = { "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN" }
local ZONE_EVENTS = { "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS" }
local events

function TH.SetActive(on)
    if not on then
        if events then events:UnregisterAllEvents() end
        return
    end
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", function(_, event)
            if event:find("^ZONE_") then Changed() else QueueScan() end
        end)
    end
    for _, e in ipairs(QUEST_EVENTS) do events:RegisterEvent(e) end
    for _, e in ipairs(ZONE_EVENTS) do events:RegisterEvent(e) end
    Scan()
end
