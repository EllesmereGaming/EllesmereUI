if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIShoppingList_Data.lua
--  The list model. Tracked recipes live in the per-character store as
--    recipes[recipeID] = { qty = crafts, name, icon, recraft }
--    order = { recipeID, ... }   (the Recipes section's order)
--  A quantity is a number of CRAFTS. Each successful cast of a tracked
--  recipe takes one off (at 0 it leaves the list).
--
--  The window asks ns.BuildRows(out) for its rows: every section registered
--  with ns.AddSection appends its own, in section order. Row clicks and
--  tooltips are dispatched by row kind (ns.rowClick / ns.rowTooltip).
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local EUI = ns.EUI
local Get = ns.Get

-------------------------------------------------------------------------------
--  Recipes
-------------------------------------------------------------------------------
local mirroring = false  -- our own SetRecipeTracked call is echoing back

local function Mirror(recipeID, tracked, recraft)
    if not ns.IsOn("blizzard") then return end
    if C_TradeSkillUI.IsRecipeTracked(recipeID, recraft == true) == tracked then return end
    mirroring = true
    C_TradeSkillUI.SetRecipeTracked(recipeID, tracked, recraft == true)
    mirroring = false
end

function ns.RecipeInfo(recipeID)
    return C_TradeSkillUI.GetRecipeInfo(recipeID)
end

function ns.IsTracked(recipeID)
    local c = EllesmereUIShoppingListCharDB
    return type(c) == "table" and type(c.recipes) == "table" and c.recipes[recipeID] ~= nil
end

-- noAuto: a sub-recipe tracked on a reagent's behalf pulls in nothing more.
function ns.TrackRecipe(recipeID, qty, recraft, noAuto)
    if not recipeID then return end
    qty = math.max(1, math.floor(tonumber(qty) or 1))
    local c = ns.Char()
    local r = c.recipes[recipeID]
    if r then
        r.qty = r.qty + qty
    else
        local info = ns.RecipeInfo(recipeID)
        r = { qty = qty, recraft = recraft and true or nil,
              name = info and info.name, icon = info and info.icon }
        c.recipes[recipeID] = r
        c.order[#c.order + 1] = recipeID
    end
    if ns.SnapshotRecipe then ns.SnapshotRecipe(recipeID, r) end
    Mirror(recipeID, true, r.recraft)
    if not noAuto and ns.AutoTrackSubCrafts then ns.AutoTrackSubCrafts(recipeID) end
    ns.Invalidate()
    return r
end

function ns.UntrackRecipe(recipeID)
    local c = ns.Char()
    local r = c.recipes[recipeID]
    if not r then return end
    c.recipes[recipeID] = nil
    for i = #c.order, 1, -1 do
        if c.order[i] == recipeID then table.remove(c.order, i) end
    end
    Mirror(recipeID, false, r.recraft)
    ns.Invalidate()
end

function ns.SetRecipeQty(recipeID, qty)
    local r = ns.Char().recipes[recipeID]
    if not r then return end
    qty = math.floor(tonumber(qty) or 0)
    if qty <= 0 then
        ns.UntrackRecipe(recipeID)
        return
    end
    r.qty = qty
    ns.Invalidate()
end

function ns.ClearList()
    local c = ns.Char()
    for _, recipeID in ipairs(c.order) do
        local r = c.recipes[recipeID]
        if r then Mirror(recipeID, false, r.recraft) end
    end
    wipe(c.recipes)
    wipe(c.order)
    wipe(c.vendor)
    ns.Invalidate()
end

function ns.ToggleSection(key)
    local col = ns.Char().collapsed
    col[key] = not col[key] or nil
    ns.Invalidate()
end

-- A recipe's name and icon: live when the client has them, else the cached ones.
function ns.RecipeLabel(recipeID, r)
    local info = ns.RecipeInfo(recipeID)
    if info then
        if info.name then r.name = info.name end
        if info.icon then r.icon = info.icon end
    end
    return r.name or ("#" .. recipeID), r.icon
end

-------------------------------------------------------------------------------
--  Rows. A section builder appends rows to out and returns the cost it adds
--  (copper) and whether a row needs the minute ticker.
-------------------------------------------------------------------------------
local sections = {}
function ns.AddSection(order, fn)
    sections[#sections + 1] = { order = order, fn = fn }
    table.sort(sections, function(a, b) return a.order < b.order end)
end

-- Row entries are reused between rebuilds (the list rebuilds on every bag
-- update): slot i of the output always gets the same table, emptied. One
-- row list lives at a time (the window's).
local rowPool = {}
function ns.NewRow(out, kind)
    local i = #out + 1
    local e = rowPool[i]
    if e then wipe(e) else e = {}; rowPool[i] = e end
    e.kind = kind
    out[i] = e
    return e
end

function ns.SectionHeader(out, key, name, count, right)
    local collapsed = ns.Char().collapsed[key] == true
    local e = ns.NewRow(out, "section")
    e.key, e.name, e.right, e.collapsed = key, EUI.L(name), right or tostring(count), collapsed
    return collapsed
end

function ns.BuildRows(out)
    local cost, ticking = 0, false
    for i = 1, #sections do
        local c, t = sections[i].fn(out)
        cost = cost + (c or 0)
        ticking = ticking or t
    end
    return cost, ticking
end

ns.AddSection(10, function(out)
    local c = ns.Char()
    local n = #c.order
    if n == 0 then return end
    if ns.SectionHeader(out, "recipes", "Recipes", n) then return end
    for _, recipeID in ipairs(c.order) do
        local r = c.recipes[recipeID]
        if r then
            local e = ns.NewRow(out, "recipe")
            e.key, e.recipeID = recipeID, recipeID
            e.name, e.icon = ns.RecipeLabel(recipeID, r)
            e.fill, e.right, e.ready = 100, ns.FormatQty(r.qty), ns.RecipeReady(r)
            if ns.DecorateRecipeRow then ns.DecorateRecipeRow(e, recipeID, r) end
        end
    end
end)

-------------------------------------------------------------------------------
--  Reagents. A tracked recipe keeps a snapshot of its reagents, read from
--  Blizzard's schematic when it is tracked (and once per session after):
--    r.reagents = { { itemID, qty, alts = { itemID, ... } }, ... }
--    r.yield    = items one craft makes (sub-crafts divide by it)
--  Only required basic slots count: optional and finishing reagents are
--  choices, not needs. A slot with several items (quality tiers, retail)
--  counts every one of them toward the first.
--  Nothing here is a hand-made table: every number comes from the schematic.
-------------------------------------------------------------------------------
local BASIC = Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
local snapshotted = {}  -- recipeID -> true once refreshed this session

local function ReadSlots(schematic, basicOnly)
    local list = {}
    for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
        local reagents = slot.reagents
        local first = reagents and reagents[1]
        if slot.required and first and first.itemID
            and (not basicOnly or slot.reagentType == BASIC) then
            local entry = { itemID = first.itemID, qty = slot.quantityRequired or 1 }
            if #reagents > 1 then
                entry.alts = {}
                for i = 2, #reagents do
                    if reagents[i].itemID then entry.alts[#entry.alts + 1] = reagents[i].itemID end
                end
            end
            list[#list + 1] = entry
        end
    end
    return list
end

function ns.SnapshotRecipe(recipeID, r)
    local ok, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, r.recraft == true)
    if not (ok and schematic) then return end
    local list = BASIC and ReadSlots(schematic, true) or {}
    -- A client whose slots carry no Basic type still lists its required ones.
    if #list == 0 then list = ReadSlots(schematic, false) end
    r.reagents = list
    r.yield = math.max(1, schematic.quantityMin or 1)
    if not r.name and schematic.name then r.name = schematic.name end
    snapshotted[recipeID] = true
end

-- Bags + bank (+ reagent bank on a client that has one) + the warband bank
-- when counted (retail only: not a WoW Forever thing): Blizzard's own
-- crafting-reagent count call.
local WARBAND = not EUI.IS_FOREVER
function ns.CountItem(itemID)
    return C_Item.GetItemCount(itemID, true, false, true, WARBAND and Get("countWarbandBank") == true) or 0
end

local function Have(entry)
    local n = ns.CountItem(entry.itemID)
    if entry.alts then
        for _, id in ipairs(entry.alts) do n = n + ns.CountItem(id) end
    end
    return n
end

-- ns.reagents: the summed list (array, first-seen order); ns.needByItem:
-- itemID -> its entry { itemID, need, have, alts, seen }. Vendor items and
-- cooldowns add their own maps in their files.
ns.reagents, ns.needByItem = {}, {}
local recomputeHooks = {}
function ns.OnRecompute(fn) recomputeHooks[#recomputeHooks + 1] = fn end

-- Entries are kept between passes (a pass runs on every bag update); a pass
-- stamps the ones it uses and drops the rest.
local pass = 0
function ns.Recompute()
    local c = ns.Char()
    local list, byItem = ns.reagents, ns.needByItem
    pass = pass + 1
    wipe(list)
    for _, recipeID in ipairs(c.order) do
        local r = c.recipes[recipeID]
        if r then
            if not snapshotted[recipeID] then ns.SnapshotRecipe(recipeID, r) end
            if r.reagents then
                for _, rg in ipairs(r.reagents) do
                    local e = byItem[rg.itemID]
                    if not e then
                        e = { itemID = rg.itemID }
                        byItem[rg.itemID] = e
                    end
                    if e.pass ~= pass then
                        e.pass, e.need, e.alts = pass, 0, rg.alts
                        list[#list + 1] = e
                        e.seen = #list
                    end
                    e.need = e.need + rg.qty * r.qty
                end
            end
        end
    end
    for itemID, e in pairs(byItem) do
        if e.pass ~= pass then byItem[itemID] = nil end
    end
    for _, e in ipairs(list) do
        e.have = Have(e)
        e.state = ns.StateOf(e.have, e.need)
    end
    for i = 1, #recomputeHooks do recomputeHooks[i]() end
end

local STATE_RANK = { missing = 1, partial = 2, complete = 3 }
local function ItemName(itemID)
    return C_Item.GetItemNameByID(itemID)
end

local sorted = {}
local function SortedReagents()
    wipe(sorted)
    for i, e in ipairs(ns.reagents) do
        e.name = ItemName(e.itemID)
        if not e.name then C_Item.RequestLoadItemDataByID(e.itemID) end
        sorted[i] = e
    end
    local mode = Get("reagentSort")
    if mode == "recipe" then
        table.sort(sorted, function(a, b) return a.seen < b.seen end)
    else
        table.sort(sorted, function(a, b)
            if mode ~= "name" then
                local ra, rb = STATE_RANK[a.state], STATE_RANK[b.state]
                if ra ~= rb then return ra < rb end
            end
            local na, nb = a.name or "", b.name or ""
            if na ~= nb then return na < nb end
            return a.itemID < b.itemID
        end)
    end
    return sorted
end

-- A recipe is ready when what you have covers all its tracked crafts
-- (each reagent on its own; other recipes sharing it are not subtracted).
function ns.RecipeReady(r)
    if not (r.reagents and #r.reagents > 0) then return false end
    for _, rg in ipairs(r.reagents) do
        local e = ns.needByItem[rg.itemID]
        if not (e and e.have >= rg.qty * r.qty) then return false end
    end
    return true
end

-- Tags on a reagent row: an anvil = you can craft it, a bag = a merchant you
-- visited sells it. Icon files every client ships, cropped past their frame.
ns.CRAFT_ICON = "|TInterface\\Icons\\Trade_BlackSmithing:0:0:0:0:64:64:6:58:6:58|t"
ns.VENDOR_ICON = "|TInterface\\Icons\\INV_Misc_Bag_10:0:0:0:0:64:64:6:58:6:58|t"

function ns.ReagentTag(itemID)
    local c = ns.Char()
    local tag
    if ns.IsOn("subcrafts") and c.craftables[itemID] then tag = ns.CRAFT_ICON end
    if c.sources[itemID] then tag = tag and (tag .. " " .. ns.VENDOR_ICON) or ns.VENDOR_ICON end
    return tag
end

ns.AddSection(20, function(out)
    local n = #ns.reagents
    if n == 0 then return end
    local done = 0
    for _, e in ipairs(ns.reagents) do if e.state == "complete" then done = done + 1 end end
    if ns.SectionHeader(out, "reagents", "Reagents", n, done .. "/" .. n) then return end
    local hideDone = Get("hideCompleted")
    for _, e in ipairs(SortedReagents()) do
        if not (hideDone and e.state == "complete") then
            local row = ns.NewRow(out, "reagent")
            row.key, row.itemID = e.itemID, e.itemID
            row.name, row.icon = e.name or ("#" .. e.itemID), C_Item.GetItemIconByID(e.itemID)
            row.state, row.ready = e.state, e.state == "complete"
            row.fill = e.need > 0 and math.min(100, e.have * 100 / e.need) or 100
            row.right, row.tag = ns.FormatCount(e.have, e.need), ns.ReagentTag(e.itemID)
        end
    end
end)

-------------------------------------------------------------------------------
--  Sub-crafts: the craftables map (itemID -> recipeID) is filled from each
--  profession this character opens (its learned recipes' outputs). Tracking
--  a reagent's recipe tracks enough crafts to cover what is missing.
-------------------------------------------------------------------------------
function ns.Missing(itemID)
    local e = ns.needByItem[itemID]
    if not e then return 0 end
    return math.max(0, e.need - e.have)
end

function ns.TrackSubRecipe(itemID)
    local recipeID = ns.Char().craftables[itemID]
    if not recipeID then return end
    local missing = ns.Missing(itemID)
    if missing <= 0 then return end
    local info = { recraft = false }
    ns.SnapshotRecipe(recipeID, info)
    local crafts = math.ceil(missing / (info.yield or 1))
    local r = ns.Char().recipes[recipeID]
    if r then
        -- Already tracked: top it up to cover the gap.
        ns.SetRecipeQty(recipeID, r.qty + crafts)
    else
        ns.TrackRecipe(recipeID, crafts, false, true)
    end
end

-- One level only: the sub-recipes a tracked recipe pulls in do not pull in theirs.
function ns.AutoTrackSubCrafts(recipeID)
    if not (ns.IsOn("subcrafts") and Get("autoTrackSubCrafts")) then return end
    local r = ns.Char().recipes[recipeID]
    if not (r and r.reagents) then return end
    ns.Recompute()
    local craftables = ns.Char().craftables
    for _, rg in ipairs(r.reagents) do
        local sub = craftables[rg.itemID]
        if sub and sub ~= recipeID and ns.Missing(rg.itemID) > 0 then ns.TrackSubRecipe(rg.itemID) end
    end
end

-- The profession scan: outputs of the learned recipes into craftables; other
-- files hook in (cooldowns). A profession is scanned once per session, the
-- first time its list is ready (a list update fires after every craft and
-- filter change); learning a recipe scans again.
local scanHooks = {}
function ns.OnProfessionScan(fn) scanHooks[#scanHooks + 1] = fn end

local scanned = {}  -- professionID -> true once scanned this session

local function ScanProfession()
    if not ns.active or not C_TradeSkillUI.IsTradeSkillReady() then return end
    if C_TradeSkillUI.IsTradeSkillLinked() or C_TradeSkillUI.IsTradeSkillGuild()
        or C_TradeSkillUI.IsNPCCrafting() then return end
    local prof = C_TradeSkillUI.GetBaseProfessionInfo()
    local profID = prof and prof.professionID
    if not profID or scanned[profID] then return end
    if not C_TradeSkillUI.GetAllRecipeIDs then return end
    local ids = C_TradeSkillUI.GetAllRecipeIDs()
    if not ids then return end
    scanned[profID] = true
    local c = ns.Char()
    local wantCraftables = ns.IsOn("subcrafts")
    for _, recipeID in ipairs(ids) do
        local info = C_TradeSkillUI.GetRecipeInfo(recipeID)
        if info and info.learned then
            if wantCraftables and not info.isSalvageRecipe then
                local out = C_TradeSkillUI.GetRecipeOutputItemData(recipeID)
                if out and out.itemID then c.craftables[out.itemID] = recipeID end
            end
            for i = 1, #scanHooks do scanHooks[i](recipeID, info) end
        end
    end
    ns.Invalidate()
end

ns.ScanProfession = ScanProfession

-- A recipe learned, or Sub-Crafts switched on (the craftables were skipped):
-- every profession is scanned again.
function ns.RescanProfessions()
    wipe(scanned)
    ScanProfession()
end

-------------------------------------------------------------------------------
--  Row clicks and tooltips, by row kind.
-------------------------------------------------------------------------------
ns.rowClick, ns.rowTooltip = {}, {}

function ns.RowClick(row, e, button)
    local fn = ns.rowClick[e.kind]
    if fn then fn(row, e, button) end
end

function ns.RowTooltip(row, e)
    local fn = ns.rowTooltip[e.kind]
    if not fn then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    fn(row, e)
    GameTooltip:Show()
end

function ns.InsertLink(link)
    if link then ChatFrameUtil.InsertLink(link) end
end

function ns.ItemLink(itemID)
    local _, link = C_Item.GetItemInfo(itemID)
    return link
end

local HINT_COLOR = { r = 0.6, g = 0.6, b = 0.6 }
function ns.AddHint(text)
    GameTooltip:AddLine(EUI.L(text), HINT_COLOR.r, HINT_COLOR.g, HINT_COLOR.b, true)
end

-- A quantity menu: +1 / -1 / a typed number / remove, then extra items.
function ns.QuantityMenu(anchor, getQty, setQty, remove, extra)
    local items = {
        { text = EUI.L("Add One"), onClick = function() setQty(getQty() + 1) end },
        { text = EUI.L("Remove One"), onClick = function() setQty(getQty() - 1) end },
        { text = EUI.L("Quantity"), isInput = true, min = 1,
          getValue = getQty,
          setValue = function(v) setQty(v) end },
    }
    if extra then
        for _, item in ipairs(extra) do items[#items + 1] = item end
    end
    items[#items + 1] = "---"
    items[#items + 1] = { text = EUI.L("Remove"), onClick = remove }
    EUI.ShowContextMenu(anchor, items, ns.MENU_OPTS)
end

ns.rowClick.recipe = function(row, e, button)
    local recipeID = e.recipeID
    local r = ns.Char().recipes[recipeID]
    if not r then return end
    if button == "RightButton" then
        ns.QuantityMenu(row, function() return r.qty end,
            function(v) ns.SetRecipeQty(recipeID, v) end,
            function() ns.UntrackRecipe(recipeID) end)
    elseif IsAltKeyDown() then
        ns.SetRecipeQty(recipeID, r.qty - 1)
    elseif IsControlKeyDown() then
        if not InCombatLockdown() and C_TradeSkillUI.OpenRecipe then C_TradeSkillUI.OpenRecipe(recipeID) end
    elseif IsShiftKeyDown() then
        ns.InsertLink(C_TradeSkillUI.GetRecipeLink(recipeID))
    end
end

ns.rowTooltip.recipe = function(_, e)
    local link = C_TradeSkillUI.GetRecipeLink(e.recipeID)
    if link then
        GameTooltip:SetHyperlink(link)
    else
        GameTooltip:SetText(e.name or "")
    end
    GameTooltip:AddLine(" ")
    ns.AddHint("Alt-click: one fewer. Ctrl-click: open the recipe. Shift-click: link. Right-click: menu.")
end

-- Reagents: shift-click links, ctrl-click opens the sub-recipe you know,
-- right-click: track that sub-recipe (plus whatever other files add).
ns.reagentMenuExtras = {}

ns.rowClick.reagent = function(row, e, button)
    local itemID = e.itemID
    local sub = ns.IsOn("subcrafts") and ns.Char().craftables[itemID]
    if button == "RightButton" then
        local items = {}
        if sub then
            items[#items + 1] = { text = EUI.L("Track Sub-Recipe"), isDisabled = function() return ns.Missing(itemID) <= 0 end,
                onClick = function() ns.TrackSubRecipe(itemID) end }
        end
        for _, extra in ipairs(ns.reagentMenuExtras) do
            local item = extra(itemID)
            if item then items[#items + 1] = item end
        end
        if #items > 0 then EUI.ShowContextMenu(row, items, ns.MENU_OPTS) end
    elseif IsShiftKeyDown() then
        ns.InsertLink(ns.ItemLink(itemID))
    elseif IsControlKeyDown() and sub then
        if not InCombatLockdown() and C_TradeSkillUI.OpenRecipe then C_TradeSkillUI.OpenRecipe(sub) end
    end
end

ns.rowTooltip.reagent = function(_, e)
    GameTooltip:SetItemByID(e.itemID)
    local sub = ns.IsOn("subcrafts") and ns.Char().craftables[e.itemID]
    GameTooltip:AddLine(" ")
    if sub then
        ns.AddHint("You can craft this. Ctrl-click: open its recipe. Right-click: track it.")
    end
    ns.AddHint("Shift-click: link.")
end

-------------------------------------------------------------------------------
--  The list feature (on whenever the module is): the craft decrement, the
--  profession-open flag.
-------------------------------------------------------------------------------
local function OnSpellcast(_, unit, _, spellID)
    if unit ~= "player" or not spellID or issecretvalue(spellID) then return end
    local c = EllesmereUIShoppingListCharDB
    local r = type(c) == "table" and c.recipes and c.recipes[spellID]
    if not r then return end
    ns.SetRecipeQty(spellID, r.qty - 1)
end

local function SetProfessionOpen(open)
    if ns.professionOpen == open then return end
    ns.professionOpen = open
    ns.Invalidate()
end

-- Counts change with the bags and the bank; names arrive with item data.
local function Recount() ns.Invalidate() end

local function OnItemData(_, itemID)
    if ns.needByItem[itemID] then ns.Invalidate() end
end

ns.RegisterFeature({
    key = "list",
    events = {
        UNIT_SPELLCAST_SUCCEEDED = OnSpellcast,
        TRADE_SKILL_SHOW = function()
            SetProfessionOpen(true)
            ScanProfession()
        end,
        TRADE_SKILL_CLOSE = function() SetProfessionOpen(false) end,
        TRADE_SKILL_LIST_UPDATE = function() ScanProfession() end,
        NEW_RECIPE_LEARNED = function() ns.RescanProfessions() end,
        BAG_UPDATE_DELAYED = Recount,
        PLAYERBANKSLOTS_CHANGED = Recount,
        PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED = Recount,
        BANKFRAME_OPENED = Recount,
        BANKFRAME_CLOSED = Recount,
        ITEM_DATA_LOAD_RESULT = OnItemData,
    },
    disable = function() ns.professionOpen = nil end,
})

-------------------------------------------------------------------------------
--  Blizzard's Track Recipe as the list's one tracking method (Use Blizzard's
--  Track Recipe, on by default). Both sides stay the same set: ticking the
--  checkbox tracks the recipe here (with the profession window's quantity
--  box), unticking removes it, and every track / untrack / clear / craft-out
--  here sets Blizzard's own tracking (Mirror above). Turning it on unites the
--  two sets once per character (ours are tracked there, theirs are added
--  here); a login with it already on does not unite them again. Turning it
--  (or the module) off forgets that, so the next switch-on unites again.
-------------------------------------------------------------------------------
function ns.OnBlizzardTrack(recipeID, tracked, recraft)
    if mirroring or not ns.IsOn("blizzard") or not recipeID then return end
    if tracked then
        if ns.IsTracked(recipeID) then return end
        local qty, formRecraft
        if ns.FormTrackInfo then qty, formRecraft = ns.FormTrackInfo(recipeID) end
        if recraft == nil then recraft = formRecraft end
        ns.TrackRecipe(recipeID, qty or Get("defaultQty"), recraft)
    elseif ns.IsTracked(recipeID) then
        ns.UntrackRecipe(recipeID)
    end
end

local function SyncWithBlizzard()
    local c = ns.Char()
    if c.blizzardSynced then return end
    c.blizzardSynced = true
    for _, recipeID in ipairs(c.order) do
        local r = c.recipes[recipeID]
        if r then Mirror(recipeID, true, r.recraft) end
    end
    for _, recraft in ipairs({ false, true }) do
        for _, recipeID in ipairs(C_TradeSkillUI.GetRecipesTracked(recraft) or {}) do
            if not ns.IsTracked(recipeID) then
                ns.TrackRecipe(recipeID, Get("defaultQty"), recraft, true)
            end
        end
    end
end

ns.RegisterFeature({
    key = "blizzard",
    isOn = function() return Get("useBlizzardTrack") end,
    events = {
        TRACKED_RECIPE_UPDATE = function(_, recipeID, tracked) ns.OnBlizzardTrack(recipeID, tracked == true) end,
    },
    enable = SyncWithBlizzard,
    disable = function()
        local c = EllesmereUIShoppingListCharDB
        if type(c) == "table" then c.blizzardSynced = nil end
        if ns.UpdateProfessionWidgets then ns.UpdateProfessionWidgets() end
    end,
})

-- Sub-crafts (the anvil tag, the Track Sub-Recipe entries, auto-tracking).
ns.RegisterFeature({
    key = "subcrafts",
    isOn = function() return Get("subCrafts") end,
    enable = function()
        ns.RescanProfessions()
        ns.Invalidate()
    end,
    disable = ns.Invalidate,
})
