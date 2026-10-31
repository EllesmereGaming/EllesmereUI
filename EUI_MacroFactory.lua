if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_MacroFactory.lua
--  The Macro Factory: the macro definitions and the macro writer, the
--  resident item macro upkeep, and the UI the Quality of Life options page
--  builds through EllesmereUI.BuildMacroFactory(parent, y, PP) while its
--  card is open (EllesmereUI.ParkMacroFactory while it is closed).
-------------------------------------------------------------------------------

-- The options page pool's table (EllesmereUI_PixelPerfect.lua makes it; the
-- options addon fills it in place): read through this file local, never the
-- public slot.
local POOL = EllesmereUI._Pool


-- Resolve an option's display name from its first item ID so the macro menus read in
-- the client's language. Falls back to the hard-coded English label (run through L() in
-- case a translation exists) until item data is cached; an uncached lookup kicks off an
-- async load so a menu refresh can pick it up. Resolve the in-game item name only for
-- single-item options (unambiguous). Multi-item options (e.g. base + Fleeting variants)
-- keep their own descriptive label -- picking one variant's name would be arbitrary --
-- run through L(). noRequest: when true, skip the async load request (used by the
-- refresh path, where the initial build already requested the uncached item).
local function OptionDisplayName(opt, noRequest)
    local ids = opt.items
    if ids and #ids == 1 then
        local n = C_Item.GetItemInfo(ids[1])
        if n then return n end
        if not noRequest then C_Item.RequestLoadItemDataByID(ids[1]) end
    end
    return EllesmereUI.L(opt.label)
end

-- Page reuse (EllesmereUIOptions/EllesmereUI_FramePool.lua): the owner of the
-- section's kept frames. On a kept page the section and its event frame are
-- kept, so a Quality of Life page pass and a spec change dress the same frames
-- again, and what the section builds under them comes back from the pool reset
-- to new.
local MF = {}

-------------------------------------------------------------------------------
--  Macro definitions (general; the spec sets live in the builder)
-------------------------------------------------------------------------------
local GENERAL_DEFS = {
    {
        name = "EUI_Potion",
        icon = "Interface\\Icons\\inv_potion_54",
        label = "Potion",
        checkboxes = {
            { key = "opt1", label = "Fleeting Light's Potential", items = {245898, 245897} },
            { key = "opt2", label = "Light's Potential",          items = {241308, 241309} },
            { key = "opt3", label = "Fleeting Recklessness",      items = {245902, 245903} },
            { key = "opt4", label = "Recklessness",               items = {241288, 241289} },
        },
    },
    {
        name = "EUI_Health",
        icon = "Interface\\Icons\\inv_potion_131",
        label = "Health / Recuperate (Combat Based)",
        spells = {1231418}, -- Recuperate (universal campfire self-heal)
        -- Line order is the priority: the first potion in bags is the one used.
        -- Concentrated Silvermoon r2 > r1, then Silvermoon r2 > r1.
        fixedBody = "/stopcasting\n/cast [nocombat] {1}\n/use [combat] item:271884\n/use [combat] item:271883\n/use [combat] item:241304\n/use [combat] item:241305",
        fixedTooltip = "item:271884",
    },
    {
        name = "EUI_Food",
        icon = "Interface\\Icons\\inv_misc_food_73cinnamonroll",
        label = "Food",
        checkboxes = {
            { key = "opt1", label = "Conjured Mana Bun",          items = {113509} },
            { key = "opt2", label = "Fairbreeze Feast",           items = {260262} },
            { key = "opt3", label = "Silvermoon Soiree Spread",   items = {260263} },
            { key = "opt4", label = "Quel'Danas Rations",         items = {260264} },
            { key = "opt5", label = "Mana Lily Tea",              items = {242297} },
            { key = "opt6", label = "Springrunner Sparkling",     items = {260260} },
            { key = "opt7", label = "Tranquility Bloom Tea",      items = {1226196} },
            { key = "opt8", label = "Sanguithorn Tea",            items = {242299} },
            { key = "opt9", label = "Azeroot Tea",                items = {242301} },
            { key = "opt10", label = "Argentleaf Tea",            items = {242298} },
            { key = "opt11", label = "Everspring Water",          items = {260259} },
        },
    },
    {
        name = "EUI_Trinket1",
        icon = "Interface\\Icons\\inv_jewelry_trinketpvp_01",
        label = "Trinket 1",
        fixedBody = "/use 13",
        fixedTooltip = "13",
    },
    {
        name = "EUI_Trinket2",
        icon = "Interface\\Icons\\inv_jewelry_trinketpvp_02",
        label = "Trinket 2",
        fixedBody = "/use 14",
        fixedTooltip = "14",
    },
}

-------------------------------------------------------------------------------
--  DB helper (shared across all buttons and event handlers)
-------------------------------------------------------------------------------
local function GetMacroDB(macroName)
    if not EllesmereUIDB then EllesmereUIDB = {} end
    if not EllesmereUIDB.macroFactory then EllesmereUIDB.macroFactory = {} end
    if not EllesmereUIDB.macroFactory[macroName] then EllesmereUIDB.macroFactory[macroName] = {} end
    return EllesmereUIDB.macroFactory[macroName]
end

-------------------------------------------------------------------------------
--  Macro body generation
-------------------------------------------------------------------------------
local function GetFirstAvailableItemID(def, db)
    if not def.checkboxes then return nil end
    local cbs = def.checkboxes
    local order = db.order
    if not order or #order < #cbs then
        order = {}
        for i = 1, #cbs do order[i] = i end
    end
    for _, idx in ipairs(order) do
        local cb = cbs[idx]
        if cb and db[cb.key] ~= false then
            for _, itemID in ipairs(cb.items) do
                if (C_Item.GetItemCount(itemID, false) or 0) > 0 then
                    return itemID
                end
            end
        end
    end
    return nil
end

local function GetMacroInventoryKey(def, db)
    return GetFirstAvailableItemID(def, db)
end

-- Replace {n} placeholders in a macro string with the client-localized name of
-- the nth entry in def.spells, resolved from its spell ID via C_Spell.GetSpellInfo.
-- Spec macros store spell IDs instead of hard-coded English names because /cast
-- only accepts the client's own language; this makes them work on any locale.
-- Returns nil if a referenced spell's data is not cached yet (kicks off an async
-- load so a later refresh completes it); callers skip the macro write on nil.
local function ResolveSpellTokens(text, spells)
    if not text then return nil end
    if not spells or not text:find("{%d+}") then return text end
    local missing = false
    local out = text:gsub("{(%d+)}", function(n)
        local id = spells[tonumber(n)]
        if not id then return "{" .. n .. "}" end
        local info = C_Spell.GetSpellInfo(id)
        if info and info.name then return info.name end
        C_Spell.RequestLoadSpellData(id)
        missing = true
        return ""
    end)
    if missing then return nil end
    return out
end

local function BuildMacroBody(def, db)
    if def.checkboxes then
        local cbs = def.checkboxes
        local order = db.order
        if not order or #order < #cbs then
            order = {}
            for i = 1, #cbs do order[i] = i end
        end

        -- Collect all enabled items
        local availItems = {}
        local firstItemID
        for _, idx in ipairs(order) do
            local cb = cbs[idx]
            if cb and db[cb.key] ~= false then
                for _, itemID in ipairs(cb.items) do
                    if not firstItemID then firstItemID = itemID end
                    availItems[#availItems + 1] = itemID
                end
            end
        end

        if #availItems == 0 and not firstItemID then return "" end

        local body = ""
        if db.showTooltip ~= false then
            local tipID = GetFirstAvailableItemID(def, db) or firstItemID
            if tipID then body = "#showtooltip item:" .. tipID .. "\n" end
        end
        local lines = {}
        for _, itemID in ipairs(availItems) do
            lines[#lines + 1] = "/use item:" .. itemID
        end
        if #lines == 0 then return "" end
        return body .. table.concat(lines, "\n")
    elseif def.fixedBody then
        local fbody = ResolveSpellTokens(def.fixedBody, def.spells)
        if fbody == nil then return nil end -- spell data not cached; skip write
        local body = ""
        if db.showTooltip ~= false and def.fixedTooltip then
            local tip = ResolveSpellTokens(def.fixedTooltip, def.spells)
            if tip == nil then return nil end
            body = "#showtooltip " .. tip .. "\n"
        elseif db.showTooltip ~= false then
            body = "#showtooltip\n"
        end
        return body .. fbody
    end
    return ""
end

-- Pick the icon stored on the created WoW macro. Single-spell / item macros
-- keep the "?" placeholder so the game shows a live icon from their
-- #showtooltip line. Multi-spell combo macros have no #showtooltip to derive
-- from, so they'd show a bare "?" -- give them their first spell's texture.
local function ResolveMacroIcon(def)
    if def.macroIcon then return def.macroIcon end
    if def.spells and def.fixedBody and not def.fixedTooltip then
        local tex = def.spells[1] and C_Spell.GetSpellTexture(def.spells[1])
        if tex then return tex end
    end
    return "INV_MISC_QUESTIONMARK"
end

local function UpdateMacro(def, db)
    local idx = GetMacroIndexByName(def.name)
    if idx ~= 0 then
        if InCombatLockdown() then
            EllesmereUI.CombatQueue.Defer("MacroFactory:" .. def.name, function()
                local i = GetMacroIndexByName(def.name)
                if i == 0 then return end
                local body = BuildMacroBody(def, GetMacroDB(def.name))
                if body then EditMacro(i, nil, nil, body) end
            end)
        else
            local body = BuildMacroBody(def, db)
            if body then EditMacro(idx, nil, nil, body) end
        end
    end
end

-------------------------------------------------------------------------------
--  Item macro upkeep. An item macro (Potion, Food) names the first item of its
--  list still in your bags on its #showtooltip line, so a bag change can move
--  it. Resident, built or not: armed once the session's macros are in (its
--  first loading screen, or the first macro update, whichever finds one of
--  these macros first) and by the factory when it creates one; a pass that
--  finds none left (deleted in the game's macro window) disarms it. Nothing
--  listens on WoW Forever (its EUI_ macros are left as they are), without
--  Quality of Life, or for a player with no such macro.
-------------------------------------------------------------------------------
-- The item each item macro was last written for this session (nil: not yet).
local lastAvailableItems = {}

local ITEM_DEFS = {}
for i = 1, #GENERAL_DEFS do
    if GENERAL_DEFS[i].checkboxes then ITEM_DEFS[#ITEM_DEFS + 1] = GENERAL_DEFS[i] end
end

local itemUpkeep = CreateFrame("Frame")

local function ArmItemUpkeep()
    itemUpkeep:RegisterEvent("BAG_UPDATE_DELAYED")
    itemUpkeep:RegisterEvent("PLAYER_REGEN_ENABLED")
end

local function ItemUpkeepPass()
    local any = false
    for i = 1, #ITEM_DEFS do
        local def = ITEM_DEFS[i]
        if GetMacroIndexByName(def.name) ~= 0 then
            any = true
            local db = GetMacroDB(def.name)
            local key = GetMacroInventoryKey(def, db)
            if key ~= lastAvailableItems[def.name] then
                lastAvailableItems[def.name] = key
                UpdateMacro(def, db)
            end
        end
    end
    if not any then itemUpkeep:UnregisterAllEvents() end
end

itemUpkeep:SetScript("OnEvent", function(self, event)
    if event == "BAG_UPDATE_DELAYED" or event == "PLAYER_REGEN_ENABLED" then
        ItemUpkeepPass()
        return
    end
    -- PLAYER_ENTERING_WORLD and UPDATE_MACROS: one look each.
    self:UnregisterEvent(event)
    if EllesmereUI.IS_FOREVER or not EllesmereUI._ModuleNS["EllesmereUIQoL"] then return end
    if self:IsEventRegistered("BAG_UPDATE_DELAYED") then return end
    for i = 1, #ITEM_DEFS do
        if GetMacroIndexByName(ITEM_DEFS[i].name) ~= 0 then
            ArmItemUpkeep()
            ItemUpkeepPass()
            return
        end
    end
end)
itemUpkeep:RegisterEvent("PLAYER_ENTERING_WORLD")
itemUpkeep:RegisterEvent("UPDATE_MACROS")

function EllesmereUI.BuildMacroFactory(parent, startY, PP)
    -- The options frame pool: this file is resident, and the options addon
    -- (whose Quality of Life page is the only caller of this builder) fills
    -- the table in place when it loads.
    local Pool = POOL
    local CreateFrame = Pool.CreateFrame
    local ICON_SIZE = 40
    local ICON_GAP = 40
    local ICONS_PER_ROW = 4
    local SPEC_ICONS_PER_ROW = 3
    local SPEC_ICON_GAP = 70
    local FIRST_ICON_Y = -34
    local ROW_STRIDE = 66
    local fontPath = EllesmereUI.GetFontPath() or STANDARD_TEXT_FONT
    local EG = EllesmereUI.ELLESMERE_GREEN
    local y = startY

    ---------------------------------------------------------------------------
    --  Spec macro definitions (keyed by specID)
    --  Format: same as GENERAL_DEFS but fixedBody only (no checkboxes).
    --  Each entry: { name, icon, label, fixedBody, fixedTooltip (optional) }
    ---------------------------------------------------------------------------
    local function mergeMacros(...)
        local t = {}
        for i = 1, select("#", ...) do
            local src = select(i, ...)
            if src then for _, v in ipairs(src) do t[#t+1] = v end end
        end
        return t
    end

    -- Death Knight (250=Blood, 251=Frost, 252=Unholy)
    local DK_GEN = {
        { name="EUI_MindFreeze", icon="Interface\\Icons\\spell_deathknight_mindfreeze", label="Mind Freeze\n(Focus)", spells={47528}, fixedBody="/cast [@focus,harm,nodead][] {1}", fixedTooltip="{1}" }, -- Mind Freeze
        { name="EUI_Asphyxiate", icon="Interface\\Icons\\ability_deathknight_asphixiate", label="Asphyxiate\n(Focus)", spells={221562}, fixedBody="/cast [@focus,harm,nodead][] {1}", fixedTooltip="{1}" }, -- Asphyxiate
    }
    local DK_BLOOD = {
        { name="EUI_DnDCursor", icon="Interface\\Icons\\spell_shadow_deathanddecay", label="Death and Decay\n(Cursor)", spells={43265}, fixedBody="/cast [@cursor] {1}", fixedTooltip="{1}" }, -- Death and Decay
        { name="EUI_GorefiendCursor", icon="Interface\\Icons\\ability_deathknight_aoedeathgrip", label="Gorefiend's Grasp\n(Cursor)", spells={108199}, fixedBody="/cast [@cursor] {1}", fixedTooltip="{1}" }, -- Gorefiend's Grasp
        { name="EUI_AbomLimb", icon="Interface\\Icons\\ability_maldraxxus_deathknight", label="Abomination Limb\n(Focus)", spells={315443}, fixedBody="/cast [@focus,harm,nodead][] {1}", fixedTooltip="{1}" }, -- Abomination Limb
    }
    local DK_FROST = {
        { name="EUI_PFObliterate", icon="Interface\\Icons\\spell_deathknight_pillaroffrost", label="PF Obliterate", spells={51271, 49020, 46584}, fixedBody="/cast {1}\n/cast {2}\n/cast {3}" }, -- Pillar of Frost / Obliterate / Raise Dead
        { name="EUI_PFReapersMark", icon="Interface\\Icons\\spell_deathknight_pillaroffrost", label="PF Reaper's Mark", spells={51271, 439843, 46584}, fixedBody="/cast {1}\n/cast {2}\n/cast {3}" }, -- Pillar of Frost / Reaper's Mark / Raise Dead
    }
    local DK_UNHOLY = {
        { name="EUI_DarkTransform", icon="Interface\\Icons\\achievement_boss_festergutrotface", label="Dark Transform\n(Focus)", spells={63560}, fixedBody="/cast [@focus,harm,nodead][] {1}", fixedTooltip="{1}" }, -- Dark Transformation
        { name="EUI_PetSwap", icon="Interface\\Icons\\ability_devour", label="Pet Target\nSwap", spells={91809}, fixedBody="/cast {1}\n/petattack\n/startattack" }, -- Leap (ghoul pet; ID low-confidence, verify in-game)
        { name="EUI_PetMove", icon="Interface\\Icons\\achievement_boss_festergutrotface", label="Pet Move", spells={63560}, fixedBody="/petmoveto", fixedTooltip="{1}" }, -- tooltip: Dark Transformation
        { name="EUI_PetResummon", icon="Interface\\Icons\\spell_shadow_animatedead", label="Pet Resummon", spells={46584}, fixedBody="/script PetDismiss()\n/cast [nopet] {1}" }, -- Raise Dead
    }

    -- Demon Hunter (577=Havoc, 581=Vengeance)
    local DH_GEN = {
        { name="EUI_Disrupt", icon="Interface\\Icons\\ability_demonhunter_consumemagic", label="Disrupt\n(Focus)", spells={183752}, fixedBody="/cast [@focus,harm,nodead][] {1}", fixedTooltip="{1}" }, -- Disrupt
        { name="EUI_ConsumeMagic", icon="Interface\\Icons\\spell_shadow_manaburn", label="Consume Magic\n(Focus)", spells={278326}, fixedBody="/cast [@focus,harm,nodead][] {1}", fixedTooltip="{1}" }, -- Consume Magic
        { name="EUI_MetaCursor", icon="Interface\\Icons\\ability_demonhunter_metamorphasisdps", label="Metamorphosis\n(Cursor)", spells={191427}, fixedBody="/cast [@cursor] {1}", fixedTooltip="{1}" }, -- Metamorphosis (Havoc)
        { name="EUI_SigilFlame", icon="Interface\\Icons\\ability_demonhunter_sigilofinquisition", label="Sigil of Flame\n(Cursor)", spells={204596}, fixedBody="/cast [@cursor] {1}", fixedTooltip="{1}" }, -- Sigil of Flame
        { name="EUI_SigilMisery", icon="Interface\\Icons\\ability_demonhunter_sigilofmisery", label="Sigil of Misery\n(Cursor)", spells={207684}, fixedBody="/cast [@cursor] {1}", fixedTooltip="{1}" }, -- Sigil of Misery
    }
    local DH_DEVOURER = {
        { name="EUI_VoidMeta", icon="Interface\\Icons\\ability_demonhunter_metamorphasisdps", label="Void Metamorphosis\n+ Trinket 1", spells={1225789}, fixedBody="/cast {1}\n/use 13", fixedTooltip="{1}" }, -- Void Metamorphosis (Midnight/Devourer)
        { name="EUI_ShiftCursor", icon="Interface\\Icons\\inv_12_dh_void_ability_shift", label="Shift\n(Cursor)", spells={1234796}, fixedBody="/cast [@cursor] {1}", fixedTooltip="{1}" }, -- Shift (Midnight/Devourer)
    }
    local DH_HAVOC = {
        { name="EUI_TheHunt", icon="Interface\\Icons\\ability_ardenweald_demonhunter", label="The Hunt\n(Focus)", spells={370965}, fixedBody="/cast [@focus,harm,nodead][] {1}", fixedTooltip="{1}" }, -- The Hunt
        { name="EUI_VRGlide", icon="Interface\\Icons\\ability_demonhunter_vengefulretreat2", label="Vengeful Retreat\n& Glide", spells={198793, 131347}, fixedBody="/cast {1}\n/cast !{2}", fixedTooltip="{1}" }, -- Vengeful Retreat / Glide
    }
    local DH_VENG = {
        { name="EUI_InfernalStrike", icon="Interface\\Icons\\ability_demonhunter_infernalstrike1", label="Infernal Strike\n(Cursor)", spells={189110}, fixedBody="/cast [@cursor] {1}", fixedTooltip="{1}" }, -- Infernal Strike
        { name="EUI_SigilChains", icon="Interface\\Icons\\ability_demonhunter_sigilofchains", label="Sigil of Chains\n(Cursor)", spells={202138}, fixedBody="/cast [@cursor] {1}", fixedTooltip="{1}" }, -- Sigil of Chains
        { name="EUI_SigilSilence", icon="Interface\\Icons\\ability_demonhunter_sigilofsilence", label="Sigil of Silence\n(Cursor)", spells={202137}, fixedBody="/cast [@cursor] {1}" }, -- Sigil of Silence
    }

    -- Druid (102=Balance, 103=Feral, 104=Guardian, 105=Restoration)
    local DRUID_GEN = {
        { name="EUI_UrsolVortex", icon="Interface\\Icons\\spell_druid_ursolsvortex", label="Ursol's Vortex\n(Cursor)", spells={102793}, fixedBody="/cast [@cursor] {1}" }, -- Ursol's Vortex
        { name="EUI_Innervate", icon="Interface\\Icons\\spell_nature_lightning", label="Innervate\n(Focus)", spells={29166}, fixedBody="/cast [@focus,help,nodead][] {1}", fixedTooltip="{1}" }, -- Innervate
        { name="EUI_RemoveCorrupt", icon="Interface\\Icons\\spell_holy_removecurse", label="Remove Corruption\n(Focus)", spells={2782}, fixedBody="/cast [@focus,help,nodead][] {1}", fixedTooltip="{1}" }, -- Remove Corruption
    }
    local DRUID_BAL = {
        { name="EUI_SolarBeam", icon="Interface\\Icons\\ability_vehicle_sonicshockwave", label="Solar Beam\n(Focus)", spells={78675}, fixedBody="/cast [@focus,harm,nodead][] {1}", fixedTooltip="{1}" }, -- Solar Beam
        { name="EUI_ForceOfNature", icon="Interface\\Icons\\ability_druid_forceofnature", label="Force of Nature\n(Cursor)", spells={205636}, fixedBody="/cast [@cursor] {1}", fixedTooltip="{1}" }, -- Force of Nature
        { name="EUI_CelestialAlign", icon="Interface\\Icons\\spell_nature_natureguardian", label="Celestial Alignment\n(Cursor)", spells={194223}, fixedBody="/cast [@cursor] {1}", fixedTooltip="{1}" }, -- Celestial Alignment
    }
    local DRUID_FERAL = {
        { name="EUI_SkullBash", icon="Interface\\Icons\\inv_bone_skull_04", label="Skull Bash\n(Focus)", spells={106839}, fixedBody="/cast [@focus,harm,nodead][] {1}", fixedTooltip="{1}" }, -- Skull Bash
    }
    local DRUID_GUARD = {
        { name="EUI_SkullBash", icon="Interface\\Icons\\inv_bone_skull_04", label="Skull Bash\n(Focus)", spells={106839}, fixedBody="/cast [@focus,harm,nodead][] {1}", fixedTooltip="{1}" }, -- Skull Bash
    }
    local DRUID_RESTO = {
        { name="EUI_Ironbark", icon="Interface\\Icons\\spell_druid_ironbark", label="Ironbark\n(Focus)", spells={102342}, fixedBody="/cast [@focus,help,nodead][] {1}", fixedTooltip="{1}" }, -- Ironbark
        { name="EUI_InnervateSelf", icon="Interface\\Icons\\spell_nature_lightning", label="Innervate\n(Player)", spells={29166}, fixedBody="/cast [@player] {1}" }, -- Innervate
    }

    -- Evoker (1467=Devastation, 1468=Preservation, 1473=Augmentation)
    local EVOKER_GEN = {
        { name="EUI_CautFlame", icon="Interface\\Icons\\ability_evoker_fontofmagic_red", label="Cauterizing Flame\n(Focus)", spells={374251}, fixedBody="/cast [@focus,help,nodead][] {1}", fixedTooltip="{1}" }, -- Cauterizing Flame
        { name="EUI_RescueCursor", icon="Interface\\Icons\\ability_evoker_flywithme", label="Rescue\n(Cursor)", spells={370665}, fixedBody="/tar [@focus]\n/cast [@cursor] {1}\n/targetlasttarget", fixedTooltip="{1}" }, -- Rescue
        { name="EUI_RescueToYou", icon="Interface\\Icons\\ability_evoker_flywithme", label="Rescue\n(To You)", spells={370665}, fixedBody="/tar [@focus]\n/cast [@player] {1}\n/targetlasttarget", fixedTooltip="{1}" }, -- Rescue
        { name="EUI_SleepWalk", icon="Interface\\Icons\\ability_xavius_dreamsimulacrum", label="Sleep Walk\n(Focus)", spells={360806}, fixedBody="/cast [@focus,harm,nodead][] {1}", fixedTooltip="{1}" }, -- Sleep Walk
    }
    local EVOKER_AUG = {
        { name="EUI_Quell", icon="Interface\\Icons\\ability_evoker_quell", label="Quell\n(Focus)", spells={351338}, fixedBody="/cast [@focus,harm,nodead][] {1}", fixedTooltip="{1}" }, -- Quell
        { name="EUI_BlistScales", icon="Interface\\Icons\\ability_evoker_blisteringscales", label="Blistering Scales\n(Focus)", spells={360827}, fixedBody="/cast [@focus,help,nodead][] {1}", fixedTooltip="{1}" }, -- Blistering Scales
    }
    local EVOKER_DEV = {
        { name="EUI_Quell", icon="Interface\\Icons\\ability_evoker_quell", label="Quell\n(Focus)", spells={351338}, fixedBody="/cast [@focus,harm,nodead][] {1}", fixedTooltip="{1}" }, -- Quell
        { name="EUI_DragonrageBurst", icon="Interface\\Icons\\ability_evoker_dragonrage2", label="Dragonrage\nBurst", spells={375087}, fixedBody="/cast {1}\n/use 13", fixedTooltip="{1}" }, -- Dragonrage
    }
    local EVOKER_PRES = {
        { name="EUI_DreamFlight", icon="Interface\\Icons\\ability_evoker_dreamflight", label="Dream Flight\n(Cursor)", spells={359816}, fixedBody="/cast [@cursor] {1}", fixedTooltip="{1}" }, -- Dream Flight
    }

    -- Hunter (253=BeastMastery, 254=Marksmanship, 255=Survival)
    local HUNTER_GEN = {
        { name="EUI_CounterMuzzle", icon="Interface\\Icons\\ability_kick", label="Counter Shot\nMuzzle (Focus)", spells={147362, 187707}, fixedBody="/cast [@focus,harm,nodead][] {1}\n/cast [@focus,harm,nodead][] {2}" }, -- Counter Shot / Muzzle
        { name="EUI_CancelTurtle", icon="Interface\\Icons\\ability_hunter_pet_turtle", label="Cancel/Cast\nTurtle", spells={186265}, fixedBody="/cancelaura {1}\n/cast {1}", fixedTooltip="{1}" }, -- Aspect of the Turtle
        { name="EUI_Misdirection", icon="Interface\\Icons\\ability_hunter_misdirection", label="Misdirection\n(Focus)", spells={34477}, fixedBody="/cast [@focus,help,nodead][@pet,exists] {1}", fixedTooltip="{1}" }, -- Misdirection
        { name="EUI_FreezeTrap", icon="Interface\\Icons\\spell_frost_chainsofice", label="Freezing Trap\n(Cursor)", spells={187650}, fixedBody="/cast [@cursor] {1}", fixedTooltip="{1}" }, -- Freezing Trap
        { name="EUI_FlareCursor", icon="Interface\\Icons\\spell_frost_stun", label="Flare\n(Cursor)", spells={1543}, fixedBody="/cast [@cursor] {1}", fixedTooltip="{1}" }, -- Flare
        { name="EUI_TarTrap", icon="Interface\\Icons\\spell_nature_stranglevines", label="Tar Trap\n(Cursor)", spells={187698}, fixedBody="/cast [@cursor] {1}", fixedTooltip="{1}" }, -- Tar Trap
        { name="EUI_BindingShot", icon="Interface\\Icons\\spell_shaman_bindelemental", label="Binding Shot\n(Cursor)", spells={109248}, fixedBody="/cast [@cursor] {1}", fixedTooltip="{1}" }, -- Binding Shot
    }
    local HUNTER_BM = {
        { name="EUI_RoarSacrifice", icon="Interface\\Icons\\ability_hunter_ferociouswild", label="Roar of\nSacrifice", spells={53480, 34477}, fixedBody="/target[@focus, help, nodead]\n/cast {1}\n/targetlasttarget\n/cast [@pet] {2}", fixedTooltip="{1}" }, -- Roar of Sacrifice / Misdirection
        { name="EUI_SpiritMend", icon="Interface\\Icons\\ability_hunter_spiritmend", label="Spirit Mend", spells={90361}, fixedBody="/cast [@target,help,nodead][@mouseover,help,nodead][@player] {1}", fixedTooltip="{1}" }, -- Spirit Mend
    }
    local HUNTER_MM = {
    }
    local HUNTER_SURV = {
        { name="EUI_Harpoon", icon="Interface\\Icons\\ability_hunter_harpoon", label="Harpoon\n(Focus)", spells={190925}, fixedBody="/cast [@focus,harm,nodead][] {1}", fixedTooltip="{1}" }, -- Harpoon
    }

    -- Mage (62=Arcane, 63=Fire, 64=Frost)
    local MAGE_GEN = {
        { name="EUI_Counterspell", icon="Interface\\Icons\\spell_frost_iceshock", label="Counterspell\n(Focus)", spells={2139}, fixedBody="/cast [@focus,harm,nodead][] {1}", fixedTooltip="{1}" }, -- Counterspell
        { name="EUI_Spellsteal", icon="Interface\\Icons\\spell_arcane_arcane02", label="Spellsteal\n(Focus)", spells={30449}, fixedBody="/cast [@focus,harm,nodead][] {1}", fixedTooltip="{1}" }, -- Spellsteal
        { name="EUI_RemoveCurse", icon="Interface\\Icons\\spell_holy_removecurse", label="Remove Curse\n(Focus)", spells={475}, fixedBody="/cast [@focus,help,nodead][] {1}", fixedTooltip="{1}" }, -- Remove Curse
    }
    local MAGE_ARCANE = {
        { name="EUI_PoMBlast", icon="Interface\\Icons\\spell_nature_enchantarmor", label="Presence of Mind\nArcane Blast", spells={205025, 30451}, fixedBody="/cast {1}\n/cast {2}\n/cqs" }, -- Presence of Mind / Arcane Blast
    }
    local MAGE_FIRE = {
        { name="EUI_Flamestrike", icon="Interface\\Icons\\spell_fire_selfdestruct", label="Flamestrike\n(Cursor)", spells={2120}, fixedBody="/cast [@cursor] {1}" }, -- Flamestrike
        { name="EUI_MeteorCursor", icon="Interface\\Icons\\spell_mage_meteor", label="Meteor\n(Cursor)", spells={153561}, fixedBody="/cast [@cursor] {1}" }, -- Meteor (cast spell, not 153564 damage)
    }
    local MAGE_FROST_SPEC = {
        { name="EUI_BlizzardCursor", icon="Interface\\Icons\\spell_frost_icestorm", label="Blizzard\n(Cursor)", spells={190356}, fixedBody="/cast [@cursor] {1}" }, -- Blizzard (modern Frost)
    }

    -- Monk (268=Brewmaster, 270=Mistweaver, 269=Windwalker)
    local MONK_GEN = {
        { name="EUI_Detox", icon="Interface\\Icons\\ability_rogue_imrovedrecuperate", label="Detox\n(Focus)", spells={115450}, fixedBody="/cast [@focus,help,nodead][] {1}", fixedTooltip="{1}" }, -- Detox (MW id; WW/Brew 218164 share name)
        { name="EUI_TigersLust", icon="Interface\\Icons\\ability_monk_tigerslust", label="Tiger's Lust\n(Focus)", spells={116841}, fixedBody="/cast [@focus,help,nodead][] {1}", fixedTooltip="{1}" }, -- Tiger's Lust
        { name="EUI_RingOfPeace", icon="Interface\\Icons\\spell_monk_ringofpeace", label="Ring of Peace\n(Cursor)", spells={116844}, fixedBody="/cast [@cursor] {1}" }, -- Ring of Peace
    }
    local MONK_BREW = {
        { name="EUI_SpearHand", icon="Interface\\Icons\\ability_monk_spearhand", label="Spear Hand Strike\n(Focus)", spells={116705}, fixedBody="/cast [@focus,harm,nodead][] {1}", fixedTooltip="{1}" }, -- Spear Hand Strike
        { name="EUI_BlackOxStatue", icon="Interface\\Icons\\monk_ability_summonoxstatue", label="Black Ox Statue\n(Cursor)", spells={115315}, fixedBody="/cast [@cursor] {1}" }, -- Summon Black Ox Statue
    }
    local MONK_WW = {
        { name="EUI_SpearHand", icon="Interface\\Icons\\ability_monk_spearhand", label="Spear Hand Strike\n(Focus)", spells={116705}, fixedBody="/cast [@focus,harm,nodead][] {1}", fixedTooltip="{1}" }, -- Spear Hand Strike
    }
    local MONK_MW = {
        { name="EUI_LifeCocoon", icon="Interface\\Icons\\ability_monk_chicocoon", label="Life Cocoon\n(Focus)", spells={116849}, fixedBody="/cast [@focus,help,nodead][] {1}", fixedTooltip="{1}" }, -- Life Cocoon
        { name="EUI_JadeSerpent", icon="Interface\\Icons\\ability_monk_summonserpentstatue", label="Jade Serpent\nStatue (Cursor)", spells={115313}, fixedBody="/cast [@cursor] {1}", fixedTooltip="{1}" }, -- Summon Jade Serpent Statue
    }

    -- Paladin (65=Holy, 66=Protection, 70=Retribution)
    local PALA_GEN = {
        { name="EUI_BoFreedom", icon="Interface\\Icons\\spell_holy_sealofvalor", label="Blessing of\nFreedom (Focus)", spells={1044}, fixedBody="/cast [@focus,help,nodead][] {1}", fixedTooltip="{1}" }, -- Blessing of Freedom
        { name="EUI_BoProtection", icon="Interface\\Icons\\spell_holy_sealofprotection", label="Blessing of\nProtection (Focus)", spells={1022}, fixedBody="/cast [@focus,help,nodead][] {1}", fixedTooltip="{1}" }, -- Blessing of Protection
        { name="EUI_DivineShield", icon="Interface\\Icons\\spell_holy_divineshield", label="Divine Shield\nCancel/Cast", spells={642}, fixedBody="/stopcasting\n/cancelaura {1}\n/cast {1}", fixedTooltip="{1}" }, -- Divine Shield
        { name="EUI_ToTLayOnHands", icon="Interface\\Icons\\spell_holy_layonhands", label="Lay on Hands\n(Target of Target)", spells={633}, fixedBody="/cast [@targettarget] {1}" }, -- Lay on Hands
        { name="EUI_Cleanse", icon="Interface\\Icons\\spell_holy_purify", label="Cleanse\n(Focus)", spells={4987}, fixedBody="/cast [@focus,help,nodead][] {1}", fixedTooltip="{1}" }, -- Cleanse
        { name="EUI_LayOnHands", icon="Interface\\Icons\\spell_holy_layonhands", label="Lay on Hands\n(Focus)", spells={633}, fixedBody="/cast [@focus,help,nodead][] {1}", fixedTooltip="{1}" }, -- Lay on Hands
    }
    local PALA_HOLY = {
    }
    local PALA_PROT = {
        { name="EUI_Rebuke", icon="Interface\\Icons\\spell_holy_rebuke", label="Rebuke\n(Focus)", spells={96231}, fixedBody="/cast [@focus,harm,nodead][] {1}", fixedTooltip="{1}" }, -- Rebuke
    }
    local PALA_RET = {
        { name="EUI_Rebuke", icon="Interface\\Icons\\spell_holy_rebuke", label="Rebuke\n(Focus)", spells={96231}, fixedBody="/cast [@focus,harm,nodead][] {1}", fixedTooltip="{1}" }, -- Rebuke
    }

    -- Priest (256=Discipline, 257=Holy, 258=Shadow)
    local PRIEST_GEN = {
        { name="EUI_DispelMagic", icon="Interface\\Icons\\spell_holy_dispelmagic", label="Dispel Magic\n(Focus)", spells={528}, fixedBody="/cast [@focus,harm,nodead][] {1}", fixedTooltip="{1}" }, -- Dispel Magic
        { name="EUI_PowerInfusion", icon="Interface\\Icons\\spell_holy_powerinfusion", label="Power Infusion\n(Focus)", spells={10060}, fixedBody="/cast [@focus,help,nodead][] {1}", fixedTooltip="{1}" }, -- Power Infusion
        { name="EUI_LeapOfFaith", icon="Interface\\Icons\\priest_spell_leapoffaith_a", label="Leap of Faith\n(Focus)", spells={73325}, fixedBody="/cast [@focus,help,nodead][] {1}", fixedTooltip="{1}" }, -- Leap of Faith
        { name="EUI_MassDispel", icon="Interface\\Icons\\spell_arcane_massdispel", label="Mass Dispel\n(Cursor)", spells={32375}, fixedBody="/cast [@cursor] {1}", fixedTooltip="{1}" }, -- Mass Dispel
        { name="EUI_FeatherSelf", icon="Interface\\Icons\\ability_priest_angelicfeather", label="Angelic Feather\n(Self)", spells={121536}, fixedBody="/cast [@player] {1}\n/stopspelltarget", fixedTooltip="{1}" }, -- Angelic Feather
        { name="EUI_FeatherCursor", icon="Interface\\Icons\\ability_priest_angelicfeather", label="Angelic Feather\n(Cursor)", spells={121536}, fixedBody="/cast [@cursor] {1}\n/stopspelltarget", fixedTooltip="{1}" }, -- Angelic Feather
        { name="EUI_Purify", icon="Interface\\Icons\\spell_holy_purify", label="Purify\n(Focus)", spells={527}, fixedBody="/cast [@focus,help,nodead][] {1}", fixedTooltip="{1}" }, -- Purify
    }
    local PRIEST_DISC = {
        { name="EUI_PainSuppress", icon="Interface\\Icons\\spell_holy_painsupression", label="Pain Suppression\n(Focus)", spells={33206}, fixedBody="/cast [@focus,help,nodead][] {1}", fixedTooltip="{1}" }, -- Pain Suppression
        { name="EUI_PWBarrier", icon="Interface\\Icons\\spell_holy_powerwordbarrier", label="PW: Barrier\n(Cursor)", spells={62618}, fixedBody="/cast [@cursor] {1}", fixedTooltip="{1}" }, -- Power Word: Barrier
    }
    local PRIEST_HOLY = {
        { name="EUI_GuardSpirit", icon="Interface\\Icons\\spell_holy_guardianspirit", label="Guardian Spirit\n(Focus)", spells={47788}, fixedBody="/cast [@focus,help,nodead][] {1}", fixedTooltip="{1}" }, -- Guardian Spirit
        { name="EUI_HWSanctify", icon="Interface\\Icons\\spell_holy_divineprovidence", label="Holy Word:\nSanctify (Cursor)", spells={34861}, fixedBody="/cast [@cursor] {1}", fixedTooltip="{1}" }, -- Holy Word: Sanctify
    }
    local PRIEST_SHADOW = {
        { name="EUI_Silence", icon="Interface\\Icons\\ability_priest_silence", label="Silence\n(Focus)", spells={15487}, fixedBody="/cast [@focus,harm,nodead][] {1}", fixedTooltip="{1}" }, -- Silence
        { name="EUI_PurifyDisease", icon="Interface\\Icons\\spell_holy_nullifydisease", label="Purify Disease\n(Focus)", spells={213634}, fixedBody="/cast [@focus,help,nodead][] {1}", fixedTooltip="{1}" }, -- Purify Disease
    }

    -- Rogue (259=Assassination, 260=Outlaw, 261=Subtlety)
    local ROGUE_GEN = {
        { name="EUI_Kick", icon="Interface\\Icons\\ability_kick", label="Kick\n(Focus)", spells={1766}, fixedBody="/cast [@focus,harm,nodead][] {1}", fixedTooltip="{1}" }, -- Kick
        { name="EUI_TricksOfTrade", icon="Interface\\Icons\\ability_rogue_tricksofthetrade", label="Tricks of Trade\n(Focus)", spells={57934}, fixedBody="/cast [@focus,help,nodead][] {1}", fixedTooltip="{1}" }, -- Tricks of the Trade
        { name="EUI_DistractCursor", icon="Interface\\Icons\\ability_rogue_distract", label="Distract\n(Cursor)", spells={1725}, fixedBody="/cast [@cursor] {1}", fixedTooltip="{1}" }, -- Distract
    }
    local ROGUE_ASS = {
    }
    local ROGUE_OUTLAW = {
        { name="EUI_GrapplingHook", icon="Interface\\Icons\\ability_rogue_grapplinghook", label="Grappling Hook\n(Cursor)", spells={195457}, fixedBody="/cast [@cursor] {1}", fixedTooltip="{1}" }, -- Grappling Hook
    }
    local ROGUE_SUB = {
        { name="EUI_CoupDeGrace", icon="Interface\\Icons\\ability_rogue_coupdetat", label="Coup de Grace\n+ Black Powder", spells={37171, 319175}, fixedBody="/cast {1}\n/cast {2}" }, -- Coup de Grace / Black Powder
        { name="EUI_EasyStealth", icon="Interface\\Icons\\ability_stealth", label="Easy Stealth", spells={185313, 1784}, fixedBody="/cancelaura [nocombat] {1}\n/cast !{2}", fixedTooltip="{2}" }, -- Shadow Dance / Stealth
    }

    -- Shaman (262=Elemental, 263=Enhancement, 264=Restoration)
    local SHAMAN_GEN = {
        { name="EUI_WindShear", icon="Interface\\Icons\\spell_nature_cyclone", label="Wind Shear\n(Focus)", spells={57994}, fixedBody="/cast [@focus,harm,nodead][] {1}", fixedTooltip="{1}" }, -- Wind Shear
        { name="EUI_Purge", icon="Interface\\Icons\\spell_nature_purge", label="Purge\n(Focus)", spells={370}, fixedBody="/cast [@focus,harm,nodead][] {1}", fixedTooltip="{1}" }, -- Purge
        { name="EUI_CleanseSpirit", icon="Interface\\Icons\\ability_shaman_cleansespirit", label="Cleanse Spirit\n(Focus)", spells={51886}, fixedBody="/cast [@focus,help,nodead][] {1}", fixedTooltip="{1}" }, -- Cleanse Spirit
        { name="EUI_WindrushTotem", icon="Interface\\Icons\\ability_shaman_windwalktotem", label="Windrush Totem\n(Cursor)", spells={192077}, fixedBody="/cast [@cursor] {1}", fixedTooltip="{1}" }, -- Wind Rush Totem
        { name="EUI_CapacitorTotem", icon="Interface\\Icons\\spell_nature_brilliance", label="Capacitor Totem\n(Cursor)", spells={192058}, fixedBody="/cast [@cursor] {1}", fixedTooltip="{1}" }, -- Capacitor Totem
    }
    local SHAMAN_ELE = {
        { name="EUI_EarthquakeCursor", icon="Interface\\Icons\\spell_shaman_earthquake", label="Earthquake\n(Cursor)", spells={61882}, fixedBody="/cast [@cursor] {1}", fixedTooltip="{1}" }, -- Earthquake
    }
    local SHAMAN_ENH = {
        { name="EUI_AutoTotemMove", icon="Interface\\Icons\\ability_shaman_totemrelocation", label="Auto Totem Move\nfor Totemic", spells={17364, 108287}, fixedBody="/cast {1}\n/cast [@player] {2}" }, -- Stormstrike / Totemic Projection
    }
    local SHAMAN_RESTO = {
        { name="EUI_HealingRain", icon="Interface\\Icons\\spell_nature_giftofthewaterspirit", label="Healing Rain\n(Cursor)", spells={73920}, fixedBody="/cast [@cursor] {1}", fixedTooltip="{1}" }, -- Healing Rain
        { name="EUI_SpiritLink", icon="Interface\\Icons\\spell_shaman_spiritlink", label="Spirit Link Totem\n(Cursor)", spells={98008}, fixedBody="/cast [@cursor] {1}", fixedTooltip="{1}" }, -- Spirit Link Totem
    }

    -- Warlock (265=Affliction, 266=Demonology, 267=Destruction)
    local LOCK_GEN = {
        { name="EUI_Shadowfury", icon="Interface\\Icons\\spell_shadow_shadowfury", label="Shadowfury\n(Cursor)", spells={30283}, fixedBody="/cast [@cursor] {1}" }, -- Shadowfury
        { name="EUI_DemonicGateway", icon="Interface\\Icons\\spell_warlock_demonicportal_green", label="Demonic Gateway\n(Cursor)", spells={111771}, fixedBody="/cast [@cursor] {1}" }, -- Demonic Gateway
        -- Soulburn (385899) resolved as {1}; [known:] uses spell/talent IDs directly
        -- (385899 Soulburn, 386689 Pact of Gluttony); Healthstones are items by ID
        -- (224464 Demonic Healthstone, 5512 Healthstone).
        { name="EUI_SoulburnHS", icon="Interface\\Icons\\spell_warlock_soulburn", label="Soulburn\nHealthstone", spells={385899}, fixedBody="/cast [known:385899] {1}\n/use [known:386689] item:224464; item:5512", fixedTooltip="[known:386689] item:224464; item:5512" },
    }
    local LOCK_DEMO = {
        { name="EUI_AxeToss", icon="Interface\\Icons\\ability_warrior_titansgrip", label="Axe Toss\n(Focus)", spells={89766}, fixedBody="/cast [@focus,harm,nodead][] {1}", fixedTooltip="{1}" }, -- Axe Toss (Felguard)
    }
    local LOCK_DESTRO = {
        { name="EUI_Havoc", icon="Interface\\Icons\\ability_warlock_baneofhavoc", label="Havoc\n(Focus)", spells={80240}, fixedBody="/cast [@focus,harm,nodead][] {1}", fixedTooltip="{1}" }, -- Havoc
        { name="EUI_SummonInfernal", icon="Interface\\Icons\\spell_shadow_summoninfernal", label="Summon Infernal\n(Cursor)", spells={1122}, fixedBody="/cast [@cursor] {1}" }, -- Summon Infernal
        { name="EUI_RainOfFire", icon="Interface\\Icons\\spell_shadow_rainoffire", label="Rain of Fire\n(Cursor)", spells={5740}, fixedBody="/cast [@cursor] {1}" }, -- Rain of Fire
        { name="EUI_Cataclysm", icon="Interface\\Icons\\achievement_zone_cataclysm", label="Cataclysm\n(Cursor)", spells={152108}, fixedBody="/cast [@cursor] {1}" }, -- Cataclysm
    }

    -- Warrior (71=Arms, 72=Fury, 73=Protection)
    local WARRIOR_GEN = {
        { name="EUI_Pummel", icon="Interface\\Icons\\inv_gauntlets_04", label="Pummel\n(Focus)", spells={6552}, fixedBody="/cast [@focus,harm,nodead][] {1}", fixedTooltip="{1}" }, -- Pummel
        { name="EUI_Intervene", icon="Interface\\Icons\\ability_warrior_safeguard", label="Intervene\n(Focus)", spells={3411}, fixedBody="/cast [@focus,help,nodead][] {1}", fixedTooltip="{1}" }, -- Intervene
        { name="EUI_HeroicLeap", icon="Interface\\Icons\\ability_heroicleap", label="Heroic Leap\n(Cursor)", spells={6544}, fixedBody="/cast [@cursor] {1}", fixedTooltip="{1}" }, -- Heroic Leap
    }
    local WARRIOR_ARMS = {
    }
    local WARRIOR_FURY = {
    }
    local WARRIOR_PROT = {
    }

    local SPEC_DEFS = {
        -- Death Knight
        [250] = mergeMacros(DK_BLOOD, DK_GEN),
        [251] = mergeMacros(DK_FROST, DK_GEN),
        [252] = mergeMacros(DK_UNHOLY, DK_GEN),
        -- Demon Hunter (577=Havoc, 581=Vengeance, 1480=Devourer -- Midnight Void spec)
        [577] = mergeMacros(DH_HAVOC, DH_GEN),
        [581] = mergeMacros(DH_VENG, DH_GEN),
        [1480] = mergeMacros(DH_DEVOURER, DH_GEN),
        -- Druid
        [102] = mergeMacros(DRUID_BAL, DRUID_GEN),
        [103] = mergeMacros(DRUID_FERAL, DRUID_GEN),
        [104] = mergeMacros(DRUID_GUARD, DRUID_GEN),
        [105] = mergeMacros(DRUID_RESTO, DRUID_GEN),
        -- Evoker
        [1467] = mergeMacros(EVOKER_DEV, EVOKER_GEN),
        [1468] = mergeMacros(EVOKER_PRES, EVOKER_GEN),
        [1473] = mergeMacros(EVOKER_AUG, EVOKER_GEN),
        -- Hunter
        [253] = mergeMacros(HUNTER_BM, HUNTER_GEN),
        [254] = mergeMacros(HUNTER_MM, HUNTER_GEN),
        [255] = mergeMacros(HUNTER_SURV, HUNTER_GEN),
        -- Mage
        [62]  = mergeMacros(MAGE_ARCANE, MAGE_GEN),
        [63]  = mergeMacros(MAGE_FIRE, MAGE_GEN),
        [64]  = mergeMacros(MAGE_FROST_SPEC, MAGE_GEN),
        -- Monk
        [268] = mergeMacros(MONK_BREW, MONK_GEN),
        [269] = mergeMacros(MONK_WW, MONK_GEN),
        [270] = mergeMacros(MONK_MW, MONK_GEN),
        -- Paladin
        [65]  = mergeMacros(PALA_HOLY, PALA_GEN),
        [66]  = mergeMacros(PALA_PROT, PALA_GEN),
        [70]  = mergeMacros(PALA_RET, PALA_GEN),
        -- Priest
        [256] = mergeMacros(PRIEST_DISC, PRIEST_GEN),
        [257] = mergeMacros(PRIEST_HOLY, PRIEST_GEN),
        [258] = mergeMacros(PRIEST_SHADOW, PRIEST_GEN),
        -- Rogue
        [259] = mergeMacros(ROGUE_ASS, ROGUE_GEN),
        [260] = mergeMacros(ROGUE_OUTLAW, ROGUE_GEN),
        [261] = mergeMacros(ROGUE_SUB, ROGUE_GEN),
        -- Shaman
        [262] = mergeMacros(SHAMAN_ELE, SHAMAN_GEN),
        [263] = mergeMacros(SHAMAN_ENH, SHAMAN_GEN),
        [264] = mergeMacros(SHAMAN_RESTO, SHAMAN_GEN),
        -- Warlock
        [265] = mergeMacros(LOCK_GEN),
        [266] = mergeMacros(LOCK_DEMO, LOCK_GEN),
        [267] = mergeMacros(LOCK_DESTRO, LOCK_GEN),
        -- Warrior
        [71]  = mergeMacros(WARRIOR_ARMS, WARRIOR_GEN),
        [72]  = mergeMacros(WARRIOR_FURY, WARRIOR_GEN),
        [73]  = mergeMacros(WARRIOR_PROT, WARRIOR_GEN),
    }

    -- Detect current spec and class
    local specIndex = C_SpecializationInfo.GetSpecialization()
    local activeSpecID, activeSpecName
    if specIndex then
        activeSpecID, activeSpecName = C_SpecializationInfo.GetSpecializationInfo(specIndex)
    end
    local activeClassName = UnitClass("player") or "Unknown"
    -- All spec macro bodies use spell-ID {n} tokens (localized at build time via
    -- ResolveSpellTokens), so they work on every client locale.
    local activeSpecDefs = activeSpecID and SPEC_DEFS[activeSpecID] or {}

    ---------------------------------------------------------------------------
    --  Layout
    ---------------------------------------------------------------------------
    local MAX_SPEC_VISIBLE_ROWS = 3
    local generalRows = math.ceil(#GENERAL_DEFS / ICONS_PER_ROW)
    -- Reserve a constant height (general side vs the max spec viewport) so a spec
    -- change can rebuild this section in place without shifting the sections
    -- below it on the page.
    local maxRows = math.max(generalRows, MAX_SPEC_VISIBLE_ROWS)
    local SECTION_H = 102 + ROW_STRIDE * (maxRows - 1)

    -- On a kept page (a pool host) the section is one frame for the session:
    -- each build dresses it again (its reset is the old section's teardown).
    -- A page built anew gets a new section, as everything on it is new.
    local keep = Pool.Managed(parent)
    local container = keep and Pool.Kept(MF, "section", "Frame", parent) or CreateFrame("Frame", nil, parent)
    -- The right-click menu still open on the previous build closes with it,
    -- also when its icon is not dressed again (a shorter spec list leaves
    -- that button, and the menu it owns, out of this build).
    if keep and MF.openMenu then
        if MF.openMenu:IsShown() then MF.openMenu:Hide() end
        MF.openMenu = nil
    end
    container:SetSize(parent:GetWidth(), SECTION_H)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)

    local halfW = parent:GetWidth() / 2
    local allMacroButtons = {}

    -- Center divider (1px absolute pixel)
    local divider = container:CreateTexture(nil, "ARTWORK")
    divider:SetWidth(1)
    divider:SetPoint("TOP", container, "TOP", 0, 0)
    divider:SetPoint("BOTTOM", container, "BOTTOM", 0, 0)
    divider:SetColorTexture(1, 1, 1, 0.15)
    if divider.SetSnapToPixelGrid then
        divider:SetSnapToPixelGrid(false)
        divider:SetTexelSnappingBias(0)
    end

    ---------------------------------------------------------------------------
    --  BuildMacroGroup: creates a titled grid of macro icons
    ---------------------------------------------------------------------------
    local function BuildMacroGroup(defs, anchorSide, titleText, perRow, gap, maxVisibleRows)
        perRow = perRow or ICONS_PER_ROW
        gap = gap or ICON_GAP
        local isLeft = (anchorSide == "LEFT")
        local centerX = isLeft and (halfW / 2) or (halfW + halfW / 2)

        local titleFS = container:CreateFontString(nil, "OVERLAY")
        titleFS:SetFont(fontPath, 16, "")
        titleFS:SetTextColor(1, 1, 1, 1)
        titleFS:SetPoint("TOP", container, "TOPLEFT", centerX, 0)
        titleFS:SetText(EllesmereUI.L(titleText))

        local numIcons = #defs
        local totalRows = math.ceil(numIcons / perRow)

        -- Scrollable viewport when content exceeds maxVisibleRows
        local iconParent = container
        local iconAnchor = container
        local scrollCenterX = centerX
        if maxVisibleRows and totalRows > maxVisibleRows then
            local visH = math.abs(FIRST_ICON_Y) + maxVisibleRows * ROW_STRIDE
            local contentH = math.abs(FIRST_ICON_Y) + totalRows * ROW_STRIDE

            local sf = CreateFrame("ScrollFrame", nil, container)
            sf:SetPoint("TOPLEFT", container, isLeft and "TOPLEFT" or "TOP", 0, FIRST_ICON_Y + ICON_SIZE / 2 + 4)
            sf:SetSize(halfW, visH)
            sf:SetFrameLevel(container:GetFrameLevel() + 1)
            sf:EnableMouseWheel(true)
            sf:SetClipsChildren(true)

            local sc = CreateFrame("Frame", nil, sf)
            sc:SetSize(halfW, contentH)
            sf:SetScrollChild(sc)

            EllesmereUI.AttachSmoothScrollbar(sf, { rightInset = 70, topInset = 32, bottomInset = 8, panelWheel = true })

            iconParent = sc
            iconAnchor = sc
            scrollCenterX = halfW / 2
        end

        for gi, def in ipairs(defs) do
            local rowIdx = math.floor((gi - 1) / perRow)
            local colIdx = (gi - 1) % perRow
            local iconsInRow = math.min(perRow, numIcons - rowIdx * perRow)
            local rowW = iconsInRow * ICON_SIZE + (iconsInRow - 1) * gap
            local iconX = scrollCenterX - rowW / 2 + ICON_SIZE / 2 + colIdx * (ICON_SIZE + gap)
            local iconY = FIRST_ICON_Y - rowIdx * ROW_STRIDE

            local btn = CreateFrame("Button", nil, iconParent)
            PP.Size(btn, ICON_SIZE, ICON_SIZE)
            btn:SetPoint("TOP", iconAnchor, "TOPLEFT", iconX, iconY)
            btn:SetFrameLevel(iconParent:GetFrameLevel() + 5)

            local tex = btn:CreateTexture(nil, "ARTWORK")
            tex:SetAllPoints(); tex:SetTexture(def.macroIcon or def.icon); tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            btn._tex = tex

            local bdr = CreateFrame("Frame", nil, btn)
            bdr:SetAllPoints(); bdr:SetFrameLevel(btn:GetFrameLevel() + 1)
            PP.CreateBorder(bdr, 0, 0, 0, 1, 1)

            local hoverBdr = CreateFrame("Frame", nil, btn)
            hoverBdr:SetPoint("TOPLEFT", btn, "TOPLEFT", -1, 1)
            hoverBdr:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, -1)
            hoverBdr:SetFrameLevel(btn:GetFrameLevel() + 2)
            local ar, ag, ab = EllesmereUI.GetAccentColor()
            PP.CreateBorder(hoverBdr, ar, ag, ab, 1, 2)
            hoverBdr:Hide()
            btn._hoverBdr = hoverBdr

            local labelFS = iconParent:CreateFontString(nil, "OVERLAY")
            labelFS:SetFont(fontPath, 13, ""); labelFS:SetTextColor(1, 1, 1, 0.9)
            labelFS:SetPoint("TOP", btn, "BOTTOM", 0, -4)
            -- Constrain to the icon stride and disable wrap so an over-long
            -- localized label truncates with an ellipsis instead of overlapping
            -- the neighbouring icon's label. The full name still shows on hover.
            labelFS:SetWidth(ICON_SIZE + gap - 8)
            labelFS:SetWordWrap(false)
            labelFS:SetJustifyH("CENTER")
            labelFS:SetText(EllesmereUI.L(def.label):gsub("\n", " "))
            btn._label = labelFS

            -- Flash system (OnUpdate, no AnimationGroup)
            local flashFS = iconParent:CreateFontString(nil, "OVERLAY")
            flashFS:SetFont(fontPath, 9, ""); flashFS:SetTextColor(1, 1, 1, 0)
            flashFS:SetPoint("TOP", btn, "BOTTOM", 0, -4); flashFS:Hide()
            local flashTex = btn:CreateTexture(nil, "OVERLAY")
            flashTex:SetAllPoints(); flashTex:SetColorTexture(1, 1, 1, 0)
            local flashDriver = CreateFrame("Frame", nil, iconParent); flashDriver:Hide()
            local flashElapsed = 0
            flashDriver:SetScript("OnUpdate", function(self, dt)
                flashElapsed = flashElapsed + dt
                if flashElapsed < 0.08 then flashTex:SetColorTexture(1, 1, 1, 0.7 * (flashElapsed / 0.08))
                elseif flashElapsed < 0.38 then flashTex:SetColorTexture(1, 1, 1, 0.7 * (1 - (flashElapsed - 0.08) / 0.3))
                else flashTex:SetColorTexture(1, 1, 1, 0) end
                if flashElapsed < 0.15 then flashFS:SetTextColor(1, 1, 1, flashElapsed / 0.15)
                elseif flashElapsed < 0.95 then flashFS:SetTextColor(1, 1, 1, 1)
                elseif flashElapsed < 1.55 then flashFS:SetTextColor(1, 1, 1, 1 - (flashElapsed - 0.95) / 0.6)
                else flashFS:Hide(); flashTex:SetColorTexture(1, 1, 1, 0); btn._label:Show(); self:Hide() end
            end)
            local function PlayFlash()
                flashElapsed = 0; flashFS:SetText(EllesmereUI.L("Macro Created")); flashFS:SetTextColor(1, 1, 1, 0)
                flashFS:Show(); btn._label:Hide(); flashDriver:Show()
            end
            btn._playFlash = PlayFlash

            -- State
            local function MacroExists() return GetMacroIndexByName(def.name) ~= 0 end
            local function RefreshState()
                local exists = MacroExists()
                tex:SetDesaturated(exists)
                btn._isGray = exists
            end

            local function GetDB() return GetMacroDB(def.name) end

            -- Dynamic icon: show the first selected item or equipped trinket
            local function RefreshIcon()
                local db = GetDB()
                local icon
                if def.checkboxes then
                    local cbs = def.checkboxes
                    local order = db.order
                    if not order or #order < #cbs then
                        order = {}
                        for i = 1, #cbs do order[i] = i end
                    end
                    for _, idx in ipairs(order) do
                        local cb = cbs[idx]
                        if cb and db[cb.key] ~= false and cb.items and cb.items[1] then
                            icon = C_Item.GetItemIconByID(cb.items[1])
                            if icon then break end
                        end
                    end
                elseif def.fixedTooltip then
                    local slot = tonumber(def.fixedTooltip)
                    if slot then
                        icon = GetInventoryItemTexture("player", slot)
                    end
                end
                tex:SetTexture(icon or def.macroIcon or def.icon)
            end
            btn._refreshIcon = RefreshIcon
            RefreshIcon()

            -------------------------------------------------------------------
            --  Right-click dropdown menu (lazy-built)
            -------------------------------------------------------------------
            local menuFrame
            local function BuildMenu()
                if menuFrame then return end
                local MH, DH, HH, MW = 28, 14, 20, 240
                local cbItems = def.checkboxes
                local hasCheckboxes = cbItems and #cbItems > 0

                local menuH = 4 + MH + MH + 4
                if hasCheckboxes then
                    menuH = menuH + DH + HH + (#cbItems * MH)
                end

                -- Owned by its icon button on a kept section: the button's next
                -- dress hides it, the next build's first right-click dresses it again.
                menuFrame = keep and Pool.Owned(btn, "menu", "Frame", UIParent) or CreateFrame("Frame", nil, UIParent)
                menuFrame:SetFrameStrata("FULLSCREEN_DIALOG"); menuFrame:SetFrameLevel(200)
                menuFrame:SetClampedToScreen(true); menuFrame:EnableMouse(true)
                menuFrame:SetSize(MW, menuH)
                menuFrame:Hide()
                local mBg = menuFrame:CreateTexture(nil, "BACKGROUND"); mBg:SetAllPoints()
                mBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_HA or 0.92)
                EllesmereUI.MakeBorder(menuFrame, 1, 1, 1, EllesmereUI.DD_BRD_A, PP)
                local mY = -4

                -- Create/Delete action row
                local aR = CreateFrame("Button", nil, menuFrame)
                aR:SetHeight(MH); aR:SetFrameLevel(menuFrame:GetFrameLevel() + 2)
                aR:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 1, mY)
                aR:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -1, mY)
                local aL = aR:CreateFontString(nil, "OVERLAY")
                aL:SetFont(fontPath, 13, ""); aL:SetTextColor(0.75, 0.75, 0.75, 1)
                aL:SetPoint("LEFT", aR, "LEFT", 12, 0)
                local aHL = aR:CreateTexture(nil, "ARTWORK"); aHL:SetAllPoints(); aHL:SetColorTexture(1, 1, 1, 0)
                local function RefAct()
                    if MacroExists() then aL:SetText(EllesmereUI.L("|cffff4444Delete Macro|r")) else aL:SetText(EllesmereUI.L("Create Macro")) end
                end
                RefAct(); menuFrame._refreshAction = RefAct
                aR:SetScript("OnEnter", function() aL:SetTextColor(1, 1, 1, 1); aHL:SetColorTexture(1, 1, 1, 0.04) end)
                aR:SetScript("OnLeave", function() RefAct(); aHL:SetColorTexture(1, 1, 1, 0) end)
                aR:SetScript("OnClick", function()
                    if InCombatLockdown() then return end
                    if MacroExists() then
                        DeleteMacro(def.name)
                    else
                        local db = GetDB()
                        local body = BuildMacroBody(def, db)
                        if body == nil then return end -- spell data not cached yet
                        CreateMacro(def.name, ResolveMacroIcon(def), body, nil)
                        lastAvailableItems[def.name] = GetMacroInventoryKey(def, db)
                        if def.checkboxes then ArmItemUpkeep() end
                        PlayFlash()
                        C_Timer.After(0.15, function()
                            if not InCombatLockdown() then ShowMacroFrame() end
                        end)
                    end
                end)
                mY = mY - MH

                -- Show Tooltip checkbox
                local tR = CreateFrame("Button", nil, menuFrame)
                tR:SetHeight(MH); tR:SetFrameLevel(menuFrame:GetFrameLevel() + 2)
                tR:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 1, mY)
                tR:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -1, mY)
                local tB = CreateFrame("Frame", nil, tR); tB:SetSize(16, 16); tB:SetPoint("RIGHT", tR, "RIGHT", -10, 0)
                local tBg = tB:CreateTexture(nil, "BACKGROUND"); tBg:SetAllPoints(); tBg:SetColorTexture(0.114, 0.106, 0.099, 1)
                local tBrd = EllesmereUI.MakeBorder(tB, 0.4, 0.4, 0.4, 0.6, PP)
                local tCk = tB:CreateTexture(nil, "ARTWORK"); PP.SetInside(tCk, tB, 2, 2)
                tCk:SetColorTexture(EG.r, EG.g, EG.b, 1); tCk:SetSnapToPixelGrid(false)
                local tL = tR:CreateFontString(nil, "OVERLAY"); tL:SetFont(fontPath, 13, "")
                tL:SetTextColor(0.75, 0.75, 0.75, 1); tL:SetPoint("LEFT", tR, "LEFT", 12, 0); tL:SetText(EllesmereUI.L("Show Tooltip"))
                local tHL = tR:CreateTexture(nil, "ARTWORK"); tHL:SetAllPoints(); tHL:SetColorTexture(1, 1, 1, 0)
                local function RefTT()
                    local db = GetDB()
                    if db.showTooltip ~= false then tCk:Show(); tBrd:SetColor(EG.r, EG.g, EG.b, 0.8)
                    else tCk:Hide(); tBrd:SetColor(0.4, 0.4, 0.4, 0.6) end
                end
                RefTT()
                tR:SetScript("OnEnter", function() tL:SetTextColor(1, 1, 1, 1); tHL:SetColorTexture(1, 1, 1, 0.04) end)
                tR:SetScript("OnLeave", function() tL:SetTextColor(0.75, 0.75, 0.75, 1); tHL:SetColorTexture(1, 1, 1, 0) end)
                tR:SetScript("OnClick", function()
                    local db = GetDB()
                    if db.showTooltip ~= false then db.showTooltip = false
                    else db.showTooltip = true end
                    RefTT()
                    UpdateMacro(def, db)
                end)
                mY = mY - MH

                -- Item checkboxes (only for item-based macros)
                if hasCheckboxes then
                    -- Divider
                    local dv = CreateFrame("Frame", nil, menuFrame); dv:SetHeight(DH)
                    dv:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 1, mY)
                    dv:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -1, mY)
                    local dl = dv:CreateTexture(nil, "ARTWORK"); dl:SetHeight(1)
                    dl:SetPoint("LEFT", dv, "LEFT", 10, 0); dl:SetPoint("RIGHT", dv, "RIGHT", -10, 0)
                    dl:SetColorTexture(1, 1, 1, 0.08)
                    mY = mY - DH

                    -- Hint text
                    local ht = CreateFrame("Frame", nil, menuFrame); ht:SetHeight(HH)
                    ht:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 1, mY)
                    ht:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -1, mY)
                    local hfs = ht:CreateFontString(nil, "OVERLAY"); hfs:SetFont(fontPath, 10, "")
                    hfs:SetTextColor(1, 1, 1, 0.25); hfs:SetPoint("CENTER"); hfs:SetText(EllesmereUI.L("Drag to Reorder"))
                    mY = mY - HH

                    -- Checkbox rows with drag reorder
                    local cbBaseY = mY
                    local rowFrames = {}
                    local isDragging = false
                    local insLine = menuFrame:CreateTexture(nil, "OVERLAY", nil, 7)
                    insLine:SetHeight(2); insLine:SetColorTexture(EG.r, EG.g, EG.b, 0.9); insLine:Hide()

                    for ci, cb in ipairs(cbItems) do
                        local row = CreateFrame("Button", nil, menuFrame)
                        row:SetHeight(MH); row._baseY = mY; row._cbIndex = ci; row._cb = cb
                        row:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 1, mY)
                        row:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -1, mY)
                        row:SetFrameLevel(menuFrame:GetFrameLevel() + 2)

                        local rl = row:CreateFontString(nil, "OVERLAY"); rl:SetFont(fontPath, 13, "")
                        rl:SetTextColor(0.75, 0.75, 0.75, 1); rl:SetPoint("LEFT", row, "LEFT", 12, 0); rl:SetText(OptionDisplayName(cb))
                        local rb = CreateFrame("Frame", nil, row); rb:SetSize(16, 16); rb:SetPoint("RIGHT", row, "RIGHT", -10, 0)
                        local rBg = rb:CreateTexture(nil, "BACKGROUND"); rBg:SetAllPoints(); rBg:SetColorTexture(0.114, 0.106, 0.099, 1)
                        local rBrd = EllesmereUI.MakeBorder(rb, 0.4, 0.4, 0.4, 0.6, PP)
                        local rCk = rb:CreateTexture(nil, "ARTWORK"); PP.SetInside(rCk, rb, 2, 2)
                        rCk:SetColorTexture(EG.r, EG.g, EG.b, 1); rCk:SetSnapToPixelGrid(false)
                        local rHL = row:CreateTexture(nil, "ARTWORK"); rHL:SetAllPoints(); rHL:SetColorTexture(1, 1, 1, 0)

                        local function UC()
                            local db = GetDB()
                            local key = row._cb.key
                            if db[key] ~= false then rCk:Show(); rBrd:SetColor(EG.r, EG.g, EG.b, 0.8)
                            else rCk:Hide(); rBrd:SetColor(0.4, 0.4, 0.4, 0.6) end
                        end
                        UC(); row._updateCheck = UC; row._lbl = rl

                        row:SetScript("OnEnter", function()
                            if isDragging then return end
                            rl:SetTextColor(1, 1, 1, 1); rHL:SetColorTexture(1, 1, 1, 0.04)
                        end)
                        row:SetScript("OnLeave", function()
                            if isDragging then return end
                            rl:SetTextColor(0.75, 0.75, 0.75, 1); rHL:SetColorTexture(1, 1, 1, 0)
                        end)
                        row:SetScript("OnClick", function()
                            if isDragging then return end
                            local db = GetDB()
                            local key = row._cb.key
                            if db[key] ~= false then db[key] = false
                            else db[key] = true end
                            UC()
                            UpdateMacro(def, db)
                            RefreshIcon()
                        end)

                        -- Drag (3px threshold via OnMouseDown/Up/Update)
                        local dsY, dgO
                        row:SetScript("OnMouseDown", function(_, b)
                            if b ~= "LeftButton" then return end
                            local _, cy = GetCursorPosition(); dsY = cy
                        end)
                        row:SetScript("OnMouseUp", function(self, b)
                            if b ~= "LeftButton" then return end
                            dsY = nil
                            if not isDragging then return end
                            isDragging = false; insLine:Hide()
                            self:SetFrameLevel(menuFrame:GetFrameLevel() + 2); self:SetAlpha(1)
                            local _, cy = GetCursorPosition()
                            local sc = menuFrame:GetEffectiveScale(); cy = cy / sc
                            local from = self._cbIndex
                            -- Same logic as insertion line: skip the dragged row
                            local mT = menuFrame:GetTop() or 0
                            local iI = #cbItems
                            for ri, rf in ipairs(rowFrames) do
                                if rf ~= self and rf._baseY then
                                    local rm = mT + rf._baseY - MH / 2
                                    if cy > rm then iI = ri; break end
                                    iI = ri + 1
                                end
                            end
                            iI = math.max(1, math.min(iI, #cbItems + 1))
                            -- Adjust for index shift from table.remove
                            if from < iI then iI = iI - 1 end
                            local to = math.max(1, math.min(iI, #cbItems))
                            if from ~= to then
                                local db = GetDB()
                                if not db.order then db.order = {}; for oi = 1, #cbItems do db.order[oi] = oi end end
                                local mv = table.remove(db.order, from); table.insert(db.order, to, mv)
                            end
                            local db = GetDB()
                            if not db.order then db.order = {}; for oi = 1, #cbItems do db.order[oi] = oi end end
                            for ri = 1, #rowFrames do
                                local rf = rowFrames[ri]; local oi = db.order[ri]; local it = cbItems[oi]
                                rf._cbIndex = ri; rf._cb = it; rf._lbl:SetText(OptionDisplayName(it))
                                local ry = cbBaseY - (ri - 1) * MH; rf._baseY = ry; rf:ClearAllPoints()
                                rf:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 1, ry)
                                rf:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -1, ry)
                                rf._updateCheck()
                            end
                            UpdateMacro(def, db)
                            RefreshIcon()
                        end)
                        row:SetScript("OnUpdate", function(self)
                            if not dsY then return end
                            local _, cy = GetCursorPosition()
                            if not isDragging then
                                if math.abs(cy - dsY) < 3 then return end
                                isDragging = true
                                local sc = menuFrame:GetEffectiveScale()
                                dgO = (cy / sc) - (self:GetTop() or 0)
                                self:SetFrameLevel(menuFrame:GetFrameLevel() + 10); self:SetAlpha(0.8)
                                for _, rf in ipairs(rowFrames) do
                                    if rf._lbl then rf._lbl:SetTextColor(0.75, 0.75, 0.75, 1) end
                                end
                            end
                            local sc = menuFrame:GetEffectiveScale()
                            local cY = cy / sc; local mT = menuFrame:GetTop() or 0
                            local lY = cY - (dgO or 0) - mT
                            lY = math.max(cbBaseY - (#cbItems - 1) * MH, math.min(lY, cbBaseY))
                            self:ClearAllPoints()
                            self:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 1, lY)
                            self:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -1, lY)
                            local iI = #cbItems
                            for ri, rf in ipairs(rowFrames) do
                                if rf ~= self and rf._baseY then
                                    local rm = mT + rf._baseY - MH / 2
                                    if cY > rm then iI = ri; break end
                                    iI = ri + 1
                                end
                            end
                            iI = math.max(1, math.min(iI, #cbItems + 1))
                            local lnY = (iI <= 1) and (cbBaseY + 1) or (cbBaseY - (iI - 1) * MH + 1)
                            insLine:ClearAllPoints()
                            insLine:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 8, lnY)
                            insLine:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -8, lnY)
                            insLine:Show()
                        end)

                        rowFrames[ci] = row; mY = mY - MH
                    end

                    -- Item names load async (initial build already requested any
                    -- uncached ones). Relabel rows when the client returns data, but
                    -- only listen while the menu is visible, and never re-request.
                    menuFrame:SetScript("OnEvent", function()
                        for _, rf in ipairs(rowFrames) do
                            if rf._lbl and rf._cb then rf._lbl:SetText(OptionDisplayName(rf._cb, true)) end
                        end
                    end)
                    menuFrame:SetScript("OnShow", function(self) self:RegisterEvent("GET_ITEM_INFO_RECEIVED") end)
                    menuFrame:SetScript("OnHide", function(self) self:UnregisterEvent("GET_ITEM_INFO_RECEIVED") end)
                end  -- hasCheckboxes

                -- Close on click outside
                menuFrame:SetScript("OnUpdate", function(self)
                    if not self:IsMouseOver() and not btn:IsMouseOver() and IsMouseButtonDown("LeftButton") then
                        self:Hide()
                    end
                end)
            end -- BuildMenu

            btn._showMenu = function()
                BuildMenu()
                for _, mb in ipairs(allMacroButtons) do
                    if mb._cogPopup and mb._cogPopup:IsShown() then mb._cogPopup:Hide() end
                end
                if menuFrame:IsShown() then menuFrame:Hide(); return end
                local bs = btn:GetEffectiveScale(); local us = UIParent:GetEffectiveScale()
                menuFrame:SetScale(bs / us); menuFrame:ClearAllPoints()
                menuFrame:SetPoint("TOP", btn, "BOTTOM", 0, -18)
                if menuFrame._refreshAction then menuFrame._refreshAction() end
                menuFrame:Show(); btn._cogPopup = menuFrame
                if keep then MF.openMenu = menuFrame end
            end

            btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            btn:SetScript("OnEnter", function(self)
                self._hoverBdr:Show()
                local fullName = EllesmereUI.L(def.label):gsub("\n", " ")
                if def.tooltip then
                    local status = self._isGray and EllesmereUI.L("|cff888888Created|r") or EllesmereUI.L("|cff888888Click to create|r")
                    EllesmereUI.ShowWidgetTooltip(self, fullName .. "\n" .. EllesmereUI.L(def.tooltip) .. "\n" .. status)
                elseif self._isGray then
                    EllesmereUI.ShowWidgetTooltip(self, fullName .. "\n" .. EllesmereUI.L("|cff888888Created. Right-click to configure.|r"))
                else
                    EllesmereUI.ShowWidgetTooltip(self, fullName .. "\n" .. EllesmereUI.L("|cff888888Click to create. Right-click to configure.|r"))
                end
            end)
            btn:SetScript("OnLeave", function(self) self._hoverBdr:Hide(); EllesmereUI.HideWidgetTooltip() end)
            btn:SetScript("OnClick", function(self, button)
                if button == "RightButton" then self._showMenu(); return end
                if self._isGray then return end
                if InCombatLockdown() then return end
                local db = GetDB()
                local body = BuildMacroBody(def, db)
                if body == nil then return end -- spell data not cached yet
                CreateMacro(def.name, ResolveMacroIcon(def), body, nil)
                lastAvailableItems[def.name] = GetMacroInventoryKey(def, db)
                if def.checkboxes then ArmItemUpkeep() end
                self._playFlash()
                C_Timer.After(0.15, function()
                    if not InCombatLockdown() then ShowMacroFrame() end
                end)
            end)

            RefreshState()
            btn._def = def
            allMacroButtons[#allMacroButtons + 1] = btn
        end -- for gi
    end -- BuildMacroGroup

    -- Build general macros on left side
    BuildMacroGroup(GENERAL_DEFS, "LEFT", "General Macro Factory")

    -- Build spec macros on right side
    if #activeSpecDefs > 0 then
        BuildMacroGroup(activeSpecDefs, "RIGHT", (activeSpecName or EllesmereUI.L("Spec")) .. " " .. activeClassName .. " " .. EllesmereUI.L("Macro Factory"), SPEC_ICONS_PER_ROW, SPEC_ICON_GAP, MAX_SPEC_VISIBLE_ROWS)
    else
        local emptyFS = container:CreateFontString(nil, "OVERLAY")
        emptyFS:SetFont(fontPath, 16, "")
        emptyFS:SetTextColor(1, 1, 1, 0.25)
        emptyFS:SetPoint("CENTER", container, "TOPLEFT", halfW + halfW / 2, -SECTION_H / 2)
        emptyFS:SetText(EllesmereUI.L("No spec macros for ") .. (activeSpecName or EllesmereUI.L("this spec")))
        emptyFS:SetJustifyH("CENTER")
    end

    -- Macro state follows UPDATE_MACROS while the section is shown: the event
    -- registers on show (with one pass for changes made while hidden), goes on
    -- hide, and a burst becomes one pass on the next frame. On a kept page the
    -- show's pass is queued the same way: a page pass shows the kept section
    -- again before this builder dresses it again, and that dress, in the same
    -- frame, drops the queued pass.
    local function SyncMacroStates()
        for _, btn in ipairs(allMacroButtons) do
            local mdef = btn._def
            if mdef and btn._tex then
                local ex = GetMacroIndexByName(mdef.name) ~= 0
                if ex ~= (btn._isGray == true) then
                    btn._tex:SetDesaturated(ex)
                    btn._isGray = ex
                    if btn._refreshIcon then btn._refreshIcon() end
                end
                if btn._cogPopup and btn._cogPopup:IsShown() and btn._cogPopup._refreshAction then
                    btn._cogPopup._refreshAction()
                end
            end
        end
    end
    local macroWatch = CreateFrame("Frame", nil, container)
    local syncPending, syncGen
    local function SyncNow()
        syncPending = nil
        -- A pass queued before the section was dressed again is dropped: its
        -- buttons now show the new build, which painted them as it built.
        if Pool.Gen(macroWatch) ~= syncGen then return end
        if macroWatch:IsVisible() then SyncMacroStates() end
    end
    local function QueueSync()
        if syncPending then return end
        syncPending = true
        syncGen = Pool.Gen(macroWatch)
        C_Timer.After(0, SyncNow)
    end
    macroWatch:SetScript("OnEvent", QueueSync)
    macroWatch:SetScript("OnShow", function(self)
        self:RegisterEvent("UPDATE_MACROS")
        if keep then QueueSync() else SyncMacroStates() end
    end)
    macroWatch:SetScript("OnHide", function(self) self:UnregisterEvent("UPDATE_MACROS") end)
    -- Built while shown: the buttons were just painted, so only listen.
    if macroWatch:IsVisible() then macroWatch:RegisterEvent("UPDATE_MACROS") end

    -- Remember this build so a spec change can rebuild just this section in place
    -- (constant SECTION_H keeps the rest of the page from shifting).
    local mf = EllesmereUI._macroFactory
    if not mf then mf = {}; EllesmereUI._macroFactory = mf end
    mf.parent, mf.startY, mf.PP = parent, startY, PP
    mf.container = container
    mf.builtSpecID = activeSpecID

    return SECTION_H
end

-- Rebuild only the Macro Factory section when the player's spec changes, so its
-- spec suggestions update without a full options-page rebuild (which flashed the
-- whole page). On a kept page the section is the same frame dressed again;
-- otherwise the new section is built before the old one is removed. Its height
-- is constant, so there is no visible gap or layout shift. Works whether
-- the options panel is open (user sees it refresh) or closed (the cached page's
-- section is updated in place, so reopening already shows the new spec).
function EllesmereUI.RefreshMacroFactory()
    local mf = EllesmereUI._macroFactory
    if not mf or not mf.parent or not mf.parent.IsObjectType then return end
    -- PLAYER_SPECIALIZATION_CHANGED can fire several times for one switch; skip
    -- the rebuild if the spec that's already built hasn't actually changed.
    local idx = C_SpecializationInfo.GetSpecialization()
    local curSpecID = idx and C_SpecializationInfo.GetSpecializationInfo(idx) or nil
    if curSpecID == mf.builtSpecID then return end
    local oldContainer = mf.container

    -- Keep macro-factory rows out of the global search index, same as the
    -- original BuildQoLPage call site does. pcall so an error mid-rebuild can't
    -- leave the global suppress flag stuck on.
    EllesmereUI._searchIndexSuppress = true
    pcall(EllesmereUI.BuildMacroFactory, mf.parent, mf.startY, mf.PP)
    EllesmereUI._searchIndexSuppress = nil

    -- A new section (constant SECTION_H, same anchor) was built before the old
    -- one is dropped, so there is no gap or layout shift -- both apply in one
    -- frame. A kept section is the same frame: nothing to drop.
    if oldContainer and oldContainer ~= mf.container then
        oldContainer:Hide()
        oldContainer:SetParent(nil)
    end
end

-- The Quality of Life page built without the section (its card closed): the
-- kept section and the menu it owns hide, and a spec change finds nothing
-- built to refresh. The next build dresses the section again (the pool shows
-- it as it resets it).
function EllesmereUI.ParkMacroFactory()
    local mf = EllesmereUI._macroFactory
    if not mf then return end
    if MF.openMenu then
        if MF.openMenu:IsShown() then MF.openMenu:Hide() end
        MF.openMenu = nil
    end
    if mf.container and mf.container:IsShown() then mf.container:Hide() end
    mf.parent = nil
end

-- A spec change only matters to what the options panel shows: the Macro
-- Factory section's suggestions and the open page's spec-dependent controls.
-- So the watcher listens only while the panel is shown, to the player's own
-- spec alone, and an open catches up on a change made while it was closed.
EllesmereUI._macroSpecWatcher = EllesmereUI._macroSpecWatcher or CreateFrame("Frame")
EllesmereUI._macroSpecWatcher:UnregisterAllEvents()
do
    local watcher = EllesmereUI._macroSpecWatcher
    local seenSpecID
    local function CurrentSpecID()
        local idx = C_SpecializationInfo.GetSpecialization()
        return idx and C_SpecializationInfo.GetSpecializationInfo(idx) or nil
    end
    local function OnSpecChanged()
        seenSpecID = CurrentSpecID()
        EllesmereUI.RefreshMacroFactory()
        -- Also re-run the active page's in-place widget refreshers so other
        -- spec-dependent controls update, as the old per-build event frame did.
        -- No-arg (fast path) => re-reads values only, no frame teardown, no flash.
        EllesmereUI:RefreshPage()
    end
    watcher:SetScript("OnEvent", OnSpecChanged)
    EllesmereUI:RegisterOnShow(function()
        watcher:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
        -- The first open builds its pages for the current spec already.
        if seenSpecID ~= nil and CurrentSpecID() ~= seenSpecID then
            OnSpecChanged()
        else
            seenSpecID = CurrentSpecID()
        end
    end)
    EllesmereUI:RegisterOnHide(function()
        watcher:UnregisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    end)
end
