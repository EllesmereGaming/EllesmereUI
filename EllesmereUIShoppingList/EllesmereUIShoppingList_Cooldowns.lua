if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIShoppingList_Cooldowns.lua
--  Recipe cooldowns (transmutes and the like), per character:
--    cooldowns[recipeID] = { name, icon, readyAt = server time,
--                            charges, maxCharges, notified }
--  C_TradeSkillUI.GetRecipeCooldown answers only for the profession that is
--  open, so a cooldown is captured while its window is open (the profession
--  scan, and after a craft: the cast is noted and read on the list update the
--  craft brings) and kept as an absolute server time: it
--  stays right across logouts without opening the profession again. A recipe
--  is remembered once it has been seen on cooldown (or with charges).
--
--  No ticker for the "ready" moment: one timer to the soonest readyAt,
--  re-armed when it fires or the set changes. The window's own minute ticker
--  (only while a cooldown row with time left is shown) keeps "3h 12m" fresh.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local EUI = ns.EUI
local Get = ns.Get

local readyTimer

-------------------------------------------------------------------------------
--  Sounds (the Threat Meter's list: EUI alert sounds + SharedMedia).
-------------------------------------------------------------------------------
local soundPaths, soundNames, soundOrder
function ns.Sounds()
    if not soundPaths then
        soundPaths, soundNames, soundOrder = EUI.BuildAlertSoundTables()
        EUI.AppendSharedMediaSounds(soundPaths, soundNames, soundOrder)
    end
    return soundPaths, soundNames, soundOrder
end

function ns.PlaySoundKey(key)
    local path = ns.Sounds()[key]
    if type(path) == "number" then
        if path ~= 1 then PlaySound(path, "Master") end
    elseif path then
        PlaySoundFile(path, "Master")
    end
end

-------------------------------------------------------------------------------
--  Capture
-------------------------------------------------------------------------------
local function Capture(recipeID, info)
    local cd, _, charges, maxCharges = C_TradeSkillUI.GetRecipeCooldown(recipeID)
    local store = ns.Char().cooldowns
    local entry = store[recipeID]
    local onCooldown = type(cd) == "number" and cd > 0
    local hasCharges = type(maxCharges) == "number" and maxCharges > 0
    if not entry and not (onCooldown or hasCharges) then return end
    local now = GetServerTime()
    if not entry then
        entry = {}
        store[recipeID] = entry
    end
    info = info or C_TradeSkillUI.GetRecipeInfo(recipeID)
    if info then entry.name, entry.icon = info.name, info.icon end
    local readyAt = onCooldown and (now + math.ceil(cd)) or now
    if readyAt > now + 1 then entry.notified = nil end
    entry.readyAt = readyAt
    entry.charges, entry.maxCharges = charges, maxCharges
end

-------------------------------------------------------------------------------
--  Ready timer and reminder
-------------------------------------------------------------------------------
local ArmTimer

local function Remind()
    readyTimer = nil
    if not ns.IsOn("cooldowns") then return end
    local now = GetServerTime()
    for _, entry in pairs(ns.Char().cooldowns) do
        if entry.readyAt and entry.readyAt <= now and not entry.notified then
            entry.notified = true
            if Get("cooldownChat") then
                ns.Say(string.format(EUI.L("%s is ready."), entry.name or "?"), true)
                ns.PlaySoundKey(Get("cooldownSound"))
            end
        end
    end
    ns.Invalidate()
    ArmTimer()
end

ArmTimer = function()
    if readyTimer then
        readyTimer:Cancel()
        readyTimer = nil
    end
    if not ns.IsOn("cooldowns") then return end
    local now, soonest = GetServerTime(), nil
    for _, entry in pairs(ns.Char().cooldowns) do
        if entry.readyAt and not entry.notified then
            if entry.readyAt <= now then
                soonest = now
            elseif not soonest or entry.readyAt < soonest then
                soonest = entry.readyAt
            end
        end
    end
    if soonest then readyTimer = C_Timer.NewTimer(math.max(0.1, soonest - now), Remind) end
end

-------------------------------------------------------------------------------
--  Rows
-------------------------------------------------------------------------------
local list = {}
ns.AddSection(40, function(out)
    if not ns.IsOn("cooldowns") then return end
    local store = ns.Char().cooldowns
    wipe(list)
    for recipeID, entry in pairs(store) do list[#list + 1] = recipeID end
    if #list == 0 then return end
    table.sort(list, function(a, b)
        local ra, rb = store[a].readyAt or 0, store[b].readyAt or 0
        if ra ~= rb then return ra < rb end
        return a < b
    end)
    local now = GetServerTime()
    local ready = 0
    for _, id in ipairs(list) do if (store[id].readyAt or 0) <= now then ready = ready + 1 end end
    if ns.SectionHeader(out, "cooldowns", "Cooldowns", #list, ready .. "/" .. #list) then return end
    local ticking = false
    for _, recipeID in ipairs(list) do
        local entry = store[recipeID]
        local left = (entry.readyAt or 0) - now
        local e = { kind = "cooldown", key = recipeID, recipeID = recipeID,
            name = entry.name or ("#" .. recipeID), icon = entry.icon }
        if left <= 0 then
            e.state, e.fill, e.right, e.ready = "complete", 100, EUI.L("Ready"), true
        else
            e.state, e.fill, e.right = "partial", 0, ns.FormatRemaining(left)
            ticking = true
        end
        out[#out + 1] = e
    end
    return 0, ticking
end)

-- A tracked recipe that has a cooldown shows when it is ready on its row.
function ns.DecorateRecipeRow(e, recipeID)
    if not ns.IsOn("cooldowns") then return end
    local entry = ns.Char().cooldowns[recipeID]
    if not (entry and entry.readyAt) then return end
    local left = entry.readyAt - GetServerTime()
    if left > 0 then e.tag = ns.FormatRemaining(left) end
end

ns.rowClick.cooldown = function(row, e, button)
    local recipeID = e.recipeID
    if button == "RightButton" then
        EUI.ShowContextMenu(row, {
            { text = EUI.L("Track Recipe"), onClick = function() ns.TrackRecipe(recipeID, Get("defaultQty")) end },
            { text = EUI.L("Forget"), onClick = function()
                ns.Char().cooldowns[recipeID] = nil
                ArmTimer()
                ns.Invalidate()
            end },
        }, ns.MENU_OPTS)
    elseif IsShiftKeyDown() then
        ns.InsertLink(C_TradeSkillUI.GetRecipeLink(recipeID))
    elseif IsControlKeyDown() then
        if not InCombatLockdown() and C_TradeSkillUI.OpenRecipe then C_TradeSkillUI.OpenRecipe(recipeID) end
    end
end

ns.rowTooltip.cooldown = function(_, e)
    local link = C_TradeSkillUI.GetRecipeLink(e.recipeID)
    if link then GameTooltip:SetHyperlink(link) else GameTooltip:SetText(e.name or "") end
    local entry = ns.Char().cooldowns[e.recipeID]
    if entry and entry.readyAt then
        local left = entry.readyAt - GetServerTime()
        GameTooltip:AddLine(" ")
        if left > 0 then
            GameTooltip:AddLine(string.format(EUI.L("Ready in %s"), ns.FormatRemaining(left)), 1, 0.82, 0)
        else
            GameTooltip:AddLine(EUI.L("Ready"), 0.2, 1, 0.2)
        end
    end
    ns.AddHint("Ctrl-click: open the recipe. Shift-click: link. Right-click: menu.")
end

-------------------------------------------------------------------------------
--  Feature
-------------------------------------------------------------------------------
local scanHooked = false
local captured = false  -- the last profession scan recorded something: re-arm after it
local casts = {}        -- spells cast with a profession open, read on the next list update

-- A craft's cooldown is not readable at the cast yet; the craft's own list
-- update comes after it settles.
local function OnSpellcast(_, unit, _, spellID)
    if unit ~= "player" or not spellID or issecretvalue(spellID) or not ns.professionOpen then return end
    casts[spellID] = true
end

local function OnListUpdate()
    if next(casts) == nil then return end
    for spellID in pairs(casts) do Capture(spellID) end
    wipe(casts)
    ArmTimer()
    ns.Invalidate()
end

ns.RegisterFeature({
    key = "cooldowns",
    isOn = function() return Get("cooldowns") end,
    events = {
        UNIT_SPELLCAST_SUCCEEDED = OnSpellcast,
        TRADE_SKILL_LIST_UPDATE = OnListUpdate,
        TRADE_SKILL_CLOSE = function() wipe(casts) end,
    },
    enable = function()
        if not scanHooked then
            scanHooked = true
            ns.OnProfessionScan(function(recipeID, info)
                if ns.IsOn("cooldowns") then
                    Capture(recipeID, info)
                    captured = true
                end
            end)
            ns.OnRecompute(function()
                if captured then
                    captured = false
                    ArmTimer()
                end
            end)
        end
        -- Professions scanned while this was off are read again.
        ns.RescanProfessions()
        ArmTimer()
        ns.Invalidate()
    end,
    disable = function()
        wipe(casts)
        if readyTimer then
            readyTimer:Cancel()
            readyTimer = nil
        end
        ns.Invalidate()
    end,
})
