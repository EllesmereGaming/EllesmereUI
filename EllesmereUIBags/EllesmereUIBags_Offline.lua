if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIBags_Offline.lua
--  offline bank: saves every character's bags, bank and the warband bank
--  account-wide so the viewer can show them anywhere, plus tooltip counts.
--
--  store: EllesmereUIBagsInventoryDB (its own saved vars, so profile exports
--  and sync never carry inventories)
--    chars[key] = { name, realm, class, level, bagsTime, bankTime,
--                   bags = { container... }, bank = { container... } }
--    warband    = { time, tabs = { container... } }
--    container  = { size, name?, icon?, items = { [slot] = item string },
--                   counts = { [slot] = count } } (counts only above 1)
--  bags[i] is bag i - 1 (false when that bag slot's empty), bank[i] and
--  tabs[i] are the i-th bank tab. pets and keystones keep their full link,
--  since their string alone can't name them.
--  key = "Name-Realm" (EllesmereUI.RealmGroupName), same as the gold ledger.
--
--  both switches are account-wide (EllesmereUIDB.bagOfflineBank /
--  .bagTooltipCounts), like the data. read only: a bag saves after
--  BAG_UPDATE_DELAYED when it changed, banks while a banker's open. nothing
--  gets saved, hooked or listened to while both are off.
-------------------------------------------------------------------------------
local EUI = EllesmereUI
local ns = select(2, ...)
if EUI.IS_FOREVER then return end  -- retail bank tabs only

local _emptyP = {}
local function Acct() return _G.EllesmereUIDB or _emptyP end

local Offline = {}
ns.Offline = Offline

function Offline.Enabled() return Acct().bagOfflineBank == true end
function Offline.CountsEnabled() return Acct().bagTooltipCounts == true end
local function Active() return Offline.Enabled() or Offline.CountsEnabled() end

-------------------------------------------------------------------------------
--  item strings
-------------------------------------------------------------------------------
-- "item:..." for items, the whole link for anything else
local function ItemString(link)
    local s = link:match("|H(item:[^|]+)|h")
    return s or link
end
Offline.ItemString = ItemString

-- item id from a string or link (pet cages count as the cage item)
local function ItemID(s)
    local kind, id = s:match("^(%a+):(%d+)")
    if not kind then kind, id = s:match("|H(%a+):(%d+)") end
    if kind == "battlepet" then return 82800 end
    return tonumber(id)
end
Offline.ItemID = ItemID

-------------------------------------------------------------------------------
--  store
-------------------------------------------------------------------------------
local rev = 0          -- goes up on every write so the tooltip index knows to rebuild
local listeners = {}
local index, indexRev  -- tooltip index, below
-- per saved list: goes up only when that list changes, so a view of it can
-- tell its own list apart from every other save
local listRev = setmetatable({}, { __mode = "k" })
local listGen = 0
local function Bump(list)
    listGen = listGen + 1
    listRev[list] = listGen
end
function Offline.ListRev(list) return list and listRev[list] or 0 end

-- saves from before item strings kept whole colored links
local function Upgrade(list)
    if type(list) ~= "table" then return end
    for _, t in ipairs(list) do
        if type(t) == "table" and type(t.links) == "table" then
            local items = {}
            for slot, link in pairs(t.links) do items[slot] = ItemString(link) end
            t.items, t.links = items, nil
        end
    end
end

function Offline.Store()
    local db = _G.EllesmereUIBagsInventoryDB
    if type(db) ~= "table" then
        db = { v = 2 }
        _G.EllesmereUIBagsInventoryDB = db
    end
    if type(db.chars) ~= "table" then db.chars = {} end
    if type(db.warband) ~= "table" then db.warband = { tabs = {} } end
    if type(db.warband.tabs) ~= "table" then db.warband.tabs = {} end
    if db.v ~= 2 then
        for _, c in pairs(db.chars) do
            if type(c) == "table" then Upgrade(c.bags); Upgrade(c.bank) end
        end
        Upgrade(db.warband.tabs)
        db.v = 2
    end
    return db
end

local function OwnKey() return EUI.CharKey("-") end
Offline.CurrentKey = OwnKey

-- a class's colour code, custom class colours included
local function ClassHex(class)
    local c = class and EUI.GetClassColor(class)
    return c and EUI.HexColor(c.r, c.g, c.b) or "|cffffffff"
end
Offline.ClassHex = ClassHex

function Offline.Char(key)
    if not key then return nil end
    return Offline.Store().chars[key]
end
function Offline.Warband() return Offline.Store().warband end
function Offline.Rev() return rev end

-- something changed, so the viewer and tooltip index catch up. patched: the
-- index was already fixed up in place for this write
local function Changed(what, patched)
    local current = patched and index and indexRev == rev
    rev = rev + 1
    if current then indexRev = rev end
    for _, fn in ipairs(listeners) do fn(what) end
end
function Offline.OnChange(fn) listeners[#listeners + 1] = fn end

function Offline.CanForget(key)
    return key ~= nil and key ~= OwnKey()
end

function Offline.Forget(key)
    if not Offline.CanForget(key) then return end
    local c = Offline.Store().chars[key]
    if type(c) == "table" then
        if type(c.bags) == "table" then Bump(c.bags) end
        if type(c.bank) == "table" then Bump(c.bank) end
    end
    Offline.Store().chars[key] = nil
    Changed("forget")
end

-- characters for the picker, by realm then name, current one flagged
function Offline.Characters()
    local list, me = {}, OwnKey()
    for key, c in pairs(Offline.Store().chars) do
        if type(c) == "table" then
            list[#list + 1] = { key = key, name = c.name or key, realm = c.realm or "", class = c.class, current = key == me }
        end
    end
    table.sort(list, function(a, b)
        if a.realm ~= b.realm then return a.realm < b.realm end
        return a.name < b.name
    end)
    return list
end

local function MyEntry()
    local key = OwnKey()
    if not key then return nil end
    local chars = Offline.Store().chars
    local c = chars[key]
    if not c then c = {}; chars[key] = c end
    local _, class = UnitClass("player")
    c.name, c.realm, c.class, c.level = UnitName("player"), EUI.RealmGroupName(), class, UnitLevel("player")
    -- a rename keeps the guid: its old entry goes and the bank moves over (the
    -- bags save again at once). a new character under a reused name has another
    -- guid and starts empty. a realm transfer gets a new guid too, so its old
    -- entry stays until it's deleted from the picker.
    local guid = UnitGUID("player")
    if guid and c.guid ~= guid then
        local moved = c.guid ~= nil
        if moved then c.bags, c.bank, c.bagsTime, c.bankTime = nil, nil, nil, nil end
        c.guid = guid
        for k, o in pairs(chars) do
            if k ~= key and type(o) == "table" and o.guid == guid then
                if c.bank == nil then c.bank, c.bankTime = o.bank, o.bankTime end
                chars[k] = nil
                moved = true
            end
        end
        if moved then Changed("forget") end
    end
    return c
end

-- one container's stuff, nil if the game says it has no slots
local function ReadContainer(bagID)
    local size = C_Container.GetContainerNumSlots(bagID) or 0
    if size <= 0 then return nil end
    local items, counts = {}, {}
    for slot = 1, size do
        local info = C_Container.GetContainerItemInfo(bagID, slot)
        local link = info and (info.hyperlink or C_Container.GetContainerItemLink(bagID, slot))
        if link then
            items[slot] = ItemString(link)
            if (info.stackCount or 1) > 1 then counts[slot] = info.stackCount end
        end
    end
    return { size = size, items = items, counts = counts }
end

-- true when two saved containers hold the same items
local function SameMap(a, b)
    for k, v in pairs(a) do if b[k] ~= v then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local function Same(x, y)
    if type(x) ~= type(y) then return false end
    if type(x) ~= "table" then return x == y end
    return x.size == y.size and x.name == y.name and x.icon == y.icon
        and SameMap(x.items, y.items) and SameMap(x.counts, y.counts)
end

local Patch  -- below, with the tooltip index

-------------------------------------------------------------------------------
--  snapshots: only the containers that changed get read again
-------------------------------------------------------------------------------
local BAGS = { 0, 1, 2, 3, 4, 5 }
local CHAR_BANK, WARBAND_BANK = {}, {}
for i = 1, 6 do
    local id = Enum.BagIndex["CharacterBankTab_" .. i]
    if id then CHAR_BANK[#CHAR_BANK + 1] = id end
end
for i = 1, 5 do
    local id = Enum.BagIndex["AccountBankTab_" .. i]
    if id then WARBAND_BANK[#WARBAND_BANK + 1] = id end
end
-- bag id -> its spot in the saved list
local BAG_POS, CHAR_POS, WARBAND_POS = {}, {}, {}
for i, id in ipairs(BAGS) do BAG_POS[id] = i end
for i, id in ipairs(CHAR_BANK) do CHAR_POS[id] = i end
for i, id in ipairs(WARBAND_BANK) do WARBAND_POS[id] = i end

local dirty = {}  -- bag ids to read on the next save

local function MarkAll(ids) for _, id in ipairs(ids) do dirty[id] = true end end

-- read the dirty ones of ids into list; true if anything changed
local function SaveList(list, ids, pos, field, owner, meta)
    local changed = false
    for _, id in ipairs(ids) do
        if dirty[id] then
            dirty[id] = nil
            local i = pos[id]
            local new = ReadContainer(id)
            if new and meta then
                local m = meta[i]
                new.name, new.icon = m and m.name, m and m.icon
            end
            -- bag slots can be empty (false); unbought bank tabs just stay unsaved
            if not new and not meta then new = false end
            if new ~= nil and not Same(list[i], new) then
                Patch(list[i], new, field, owner)
                list[i] = new
                changed = true
            end
        end
    end
    if changed then Bump(list) end
    return changed
end

local function SaveBags()
    local c = MyEntry()
    if not c then return end
    c.bagsTime = time()
    if type(c.bags) ~= "table" then c.bags = {} end
    -- most bag updates move nothing we keep (cooldowns, locks): no change then
    if SaveList(c.bags, BAGS, BAG_POS, "bags", OwnKey()) then Changed("bags", true) end
end

local function Meta(bankType)
    return C_Bank and C_Bank.FetchPurchasedBankTabData and C_Bank.FetchPurchasedBankTabData(bankType)
end

local atBank, atCharBank = false, false

local function SaveBanks()
    if not atBank then return end
    local changed = false
    if atCharBank then
        local c = MyEntry()
        if c then
            c.bankTime = time()
            if type(c.bank) ~= "table" then c.bank = {} end
            changed = SaveList(c.bank, CHAR_BANK, CHAR_POS, "bank", OwnKey(), Meta(Enum.BankType.Character) or {})
        end
    end
    local locked = C_Bank and C_Bank.FetchBankLockedReason and C_Bank.FetchBankLockedReason(Enum.BankType.Account)
    if locked == nil then
        local w = Offline.Store().warband
        w.time = time()
        if SaveList(w.tabs, WARBAND_BANK, WARBAND_POS, nil, nil, Meta(Enum.BankType.Account) or {}) then changed = true end
    end
    if changed then Changed("bank", true) end
end

-- a burst of updates only saves once
local pendingBags, pendingBank = false, false
local function Flush()
    -- a save queued just before both switches went off (the Bags reset) is dropped
    if not Active() then pendingBags, pendingBank = false, false; return end
    if pendingBags then pendingBags = false; SaveBags() end
    if pendingBank then pendingBank = false; SaveBanks() end
end
local flushQueued = false
local function FlushQueued() flushQueued = false; Flush() end
local function Queue(bags, bank)
    if bags then pendingBags = true end
    if bank then pendingBank = true end
    if flushQueued then return end
    flushQueued = true
    C_Timer.After(0.5, FlushQueued)
end

-------------------------------------------------------------------------------
--  events (only registered while an option needs them)
-------------------------------------------------------------------------------
local PIT = Enum.PlayerInteractionType
local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, arg)
    if event == "BAG_UPDATE" then
        if BAG_POS[arg] then
            dirty[arg] = true
        elseif atBank and (CHAR_POS[arg] or WARBAND_POS[arg]) then
            dirty[arg] = true
            Queue(false, true)
        end
    elseif event == "BAG_UPDATE_DELAYED" then
        Queue(true, false)
    elseif event == "BAG_CONTAINER_UPDATE" then
        MarkAll(BAGS)
        Queue(true, false)
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        if arg == PIT.Banker or arg == PIT.AccountBanker then
            atBank, atCharBank = true, arg == PIT.Banker
            MarkAll(CHAR_BANK); MarkAll(WARBAND_BANK)
            Queue(false, true)
        end
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        if arg == PIT.Banker or arg == PIT.AccountBanker then
            Flush()  -- save before the contents go unreadable
            atBank, atCharBank = false, false
        end
    elseif atBank then
        -- a tab bought or renamed (BANK_TABS_CHANGED / BANK_TAB_SETTINGS_UPDATED,
        -- arg = its bank type): that bank's tabs, for their names and icons.
        -- slot changes come through BAG_UPDATE with the tab's bag id
        if arg == Enum.BankType.Account then
            MarkAll(WARBAND_BANK)
            Queue(false, true)
        elseif arg == Enum.BankType.Character then
            MarkAll(CHAR_BANK)
            Queue(false, true)
        end
    end
end)
local EVENTS = { "BAG_UPDATE_DELAYED", "BAG_UPDATE", "BAG_CONTAINER_UPDATE",
    "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
    "BANK_TABS_CHANGED", "BANK_TAB_SETTINGS_UPDATED" }

local listening = false
local IndexSoon  -- below
function Offline.Sync()
    local on = Active()
    if on == listening then return end
    listening = on
    for _, e in ipairs(EVENTS) do
        if on then pcall(ev.RegisterEvent, ev, e) else ev:UnregisterEvent(e) end
    end
    if on then
        MarkAll(BAGS)
        Queue(true, false)
    end
end

-- the bags module reset: every saved inventory goes
function Offline.Wipe()
    _G.EllesmereUIBagsInventoryDB = nil
    index = nil
    wipe(listRev)
    listGen = listGen + 1
    Changed("forget")
    -- this character saves again right away
    MarkAll(BAGS)
    if listening then Queue(true, false) end
end

-- an options toggle: key is bagOfflineBank or bagTooltipCounts
function Offline.Set(key, on)
    if not _G.EllesmereUIDB then return end
    _G.EllesmereUIDB[key] = on and true or nil
    Offline.Sync()
    Offline.SyncTooltip()
    Offline.SyncButton()
end

-------------------------------------------------------------------------------
--  tooltip item counts
-------------------------------------------------------------------------------
-- index: chars[itemID][key] = { bags, bank }, warband[itemID].n
-- sign -1 takes a container back out (rows that hit zero go away)
local function AddContainer(t, into, field, owner, sign)
    if type(t) ~= "table" or type(t.items) ~= "table" then return end
    for slot, s in pairs(t.items) do
        local id = ItemID(s)
        if id then
            local n = ((t.counts and t.counts[slot]) or 1) * sign
            local row = into[id]
            if not row then row = {}; into[id] = row end
            if owner then
                local e = row[owner]
                if not e then e = { bags = 0, bank = 0 }; row[owner] = e end
                e[field] = e[field] + n
                if e.bags + e.bank <= 0 then row[owner] = nil end
            else
                row.n = (row.n or 0) + n
                if row.n <= 0 then row.n = nil end
            end
            if next(row) == nil then into[id] = nil end
        end
    end
end

local function Index()
    if index and indexRev == rev then return index end
    local chars, war = {}, {}
    local db = Offline.Store()
    for key, c in pairs(db.chars) do
        if type(c) == "table" then
            for _, t in ipairs(type(c.bags) == "table" and c.bags or _emptyP) do AddContainer(t, chars, "bags", key, 1) end
            for _, t in ipairs(type(c.bank) == "table" and c.bank or _emptyP) do AddContainer(t, chars, "bank", key, 1) end
        end
    end
    for _, t in ipairs(db.warband.tabs) do AddContainer(t, war, nil, nil, 1) end
    index, indexRev = { chars = chars, warband = war }, rev
    return index
end

-- one container swapped for another: fix the index up in place instead of a
-- full rebuild on the next hover (Changed keeps it current). no owner = warband
Patch = function(old, new, field, owner)
    if not (index and indexRev == rev) then return end
    local into = owner and index.chars or index.warband
    AddContainer(old, into, field, owner, -1)
    AddContainer(new, into, field, owner, 1)
end

-- built a moment after login, not inside the first hover
IndexSoon = function()
    C_Timer.After(3, function() if listening and Offline.CountsEnabled() then Index() end end)
end

-- finished lines per item id, until the next write
local lineCache, lineRev = {}, -1
local sameName = {}
local function BuildLines(id)
    local idx = Index()
    local row, war = idx.chars[id], idx.warband[id]
    if not row and not (war and war.n) then return false end
    local db, lines, total = Offline.Store(), {}, 0
    -- two characters of one name (other realms) get their realm added
    wipe(sameName)
    for key in pairs(row or _emptyP) do
        local c = db.chars[key]
        if c and c.name then sameName[c.name] = (sameName[c.name] or 0) + 1 end
    end
    for key, e in pairs(row or _emptyP) do
        local c = db.chars[key]
        local n = e.bags + e.bank
        if c and n > 0 then
            local parts = {}
            if e.bags > 0 then parts[#parts + 1] = EllesmereUI.Lf("Bags %1$d", e.bags) end
            if e.bank > 0 then parts[#parts + 1] = EllesmereUI.Lf("Bank %1$d", e.bank) end
            local name = c.name or "?"
            if (sameName[name] or 0) > 1 and c.realm and c.realm ~= "" then name = name .. "-" .. c.realm end
            lines[#lines + 1] = { ClassHex(c.class) .. name .. "|r", table.concat(parts, "  "), 1, 1, 1, n = n }
            total = total + n
        end
    end
    table.sort(lines, function(a, b) return a.n > b.n end)
    if war and war.n then
        total = total + war.n
        lines[#lines + 1] = { EllesmereUI.L("Warband Bank"), war.n, 0.4, 0.78, 1 }
    end
    if #lines > 1 then lines[#lines + 1] = { EllesmereUI.L("Total"), total, 1, 0.82, 0, total = true } end
    return lines
end

local function OnItemTooltip(tooltip, data)
    if not (listening and Offline.CountsEnabled()) then return end
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    if tooltip:IsForbidden() then return end
    local id = data and data.id
    if type(id) ~= "number" or (issecretvalue and issecretvalue(id)) then return end
    if lineRev ~= rev then wipe(lineCache); lineRev = rev end
    local lines = lineCache[id]
    if lines == nil then lines = BuildLines(id); lineCache[id] = lines end
    if not lines then return end
    tooltip:AddLine(" ")
    for _, l in ipairs(lines) do
        if l.total then
            tooltip:AddDoubleLine(l[1], l[2], l[3], l[4], l[5], 1, 1, 1)
        else
            tooltip:AddDoubleLine(l[1], l[2], l[3], l[4], l[5], 0.8, 0.8, 0.8)
        end
    end
end

-- the post call can't be unhooked, so it just bails while off
local hooked = false
function Offline.SyncTooltip()
    if not (listening and Offline.CountsEnabled()) then return end
    IndexSoon()
    if hooked then return end
    if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall) then return end
    hooked = true
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
end

-------------------------------------------------------------------------------
--  login
-------------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    -- old saves upgrade once; nothing is created for a player who never turned a switch on
    if Active() or _G.EllesmereUIBagsInventoryDB ~= nil then Offline.Store() end
    Offline.Sync()
    Offline.SyncTooltip()
end)
