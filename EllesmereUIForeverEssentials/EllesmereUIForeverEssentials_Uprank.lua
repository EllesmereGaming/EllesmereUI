if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_Uprank.lua  (WoW Forever only)
--  When a new spell rank is learned, swaps every lower rank of that spell on
--  the action bars for the new one and reports it in chat.
-------------------------------------------------------------------------------
local _, module = ...

local MAX_ACTION_SLOT = 180

-- Settings live in EllesmereUIDB.spellUprank; unset keys read these.
local F = module.Feature("spellUprank", { enabled = false })

local events
local pending = {} -- learned spell IDs waiting for combat / the cursor to clear

local function Plain(v)
    if not issecretvalue(v) and type(v) == "number" then return v end
end

local function Uprank(newID)
    local name = C_Spell.GetSpellName(newID)
    if not name then return end
    local slot, bank = C_SpellBook.FindSpellBookSlotForSpell(newID)
    if not slot or C_SpellBook.IsSpellBookItemLowRank(slot, bank) then return end
    local count = 0
    for action = 1, MAX_ACTION_SLOT do
        local kind, id = GetActionInfo(action)
        id = kind == "spell" and Plain(id)
        -- Same name, both in the spellbook, new one highest: a lower rank.
        if id and id ~= newID and C_Spell.GetSpellName(id) == name
           and C_SpellBook.FindSpellBookSlotForSpell(id, true) then
            C_Spell.PickupSpell(newID)
            PlaceAction(action)
            ClearCursor()
            count = count + 1
        end
    end
    if count > 0 then
        local rank = C_Spell.GetSpellSubtext(newID)
        local spell = (C_Spell.GetSpellLink(newID) or name) .. (rank and rank ~= "" and " (" .. rank .. ")" or "")
        local msg = count == 1 and EllesmereUI.Lf("Upranked %s on 1 action slot.", spell)
            or EllesmereUI.Lf("Upranked %1$s on %2$d action slots.", spell, count)
        EllesmereUI.Print(EllesmereUI.COLOR_CODES.BRAND .. "EllesmereUI:|r " .. msg)
    end
end

-- Placing actions needs no combat and an empty cursor; waits for both.
local function Flush()
    if InCombatLockdown() or GetCursorInfo() then
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        events:RegisterEvent("CURSOR_CHANGED")
        return
    end
    events:UnregisterEvent("PLAYER_REGEN_ENABLED")
    events:UnregisterEvent("CURSOR_CHANGED")
    local ids = pending
    pending = {}
    for _, id in ipairs(ids) do Uprank(id) end
end

local function OnEvent(_, event, spellID, _, isGuildPerkSpell)
    if event == "LEARNED_SPELL_IN_SKILL_LINE" then
        spellID = Plain(spellID)
        if not spellID or isGuildPerkSpell then return end
        pending[#pending + 1] = spellID
    end
    Flush()
end

local function Apply()
    if events then events:UnregisterAllEvents() end
    if not F.Enabled() then
        pending = {}
        return
    end
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", OnEvent)
    end
    events:RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE")
end

-- Options-page entry points.
EllesmereUI._SpellUprank = {
    Get = F.Get,
    Cfg = F.Cfg,
    Apply = Apply,
}

F.Start(Apply)
