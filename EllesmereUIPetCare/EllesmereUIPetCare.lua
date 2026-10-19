if EUI_CLIENT_BLOCKED then return end
local ADDON_NAME, ns = ...
EllesmereUI._ModuleNS[ADDON_NAME] = ns
local addon = EllesmereUI.Lite.NewAddon(ADDON_NAME)
local events = CreateFrame("Frame")
local queue = EllesmereUI.NewCombatQueue(CreateFrame("Frame"))
local G, M = EllesmereUI.Glows, ns.Model
local db, button, glow, anchor, chosen, feeding, warning
local candidates, requested, spec = {}, {}, {}
local active = false
local clicksActive = false
local warningPreview = false
local FEED_SPELL, FEED_EFFECT = 6991, 1539
ns.DEFAULTS = { profile = {
    enabled = false, order = "most", cooked = false, rawMeat = false, rawFish = false,
    preferredOnly = false, preferred = {}, blacklist = {}, customFoods = {},
    glowAt = 2, feedGlowType = 2, feedGlowR = 1, feedGlowG = 0.7, feedGlowB = 0.15,
    feedGlowColorMode = "custom", feedGlowLines = 8, feedGlowThickness = 2, feedGlowSpeed = 4,
    screenWarning = false, warningAt = 2, warningX = 0, warningY = 180, warningSize = 24,
} }

function ns.Config() return db and db.profile end
function ns.Status() return ns.status or EllesmereUI.L("Pet feeding is disabled.") end
function ns.Selected() return chosen, candidates end
local function UnitFrames() return EllesmereUI._ModuleNS.EllesmereUIUnitFrames end

local function StopGlow()
    clicksActive = false
    if glow then G.StopGlow(glow) end
end

local function HideWarning()
    if warning then warning:Hide(); warning:UnregisterEvent("PLAYER_REGEN_DISABLED") end
end

local function FeedingEffect()
    if EllesmereUI.AuraKit.AurasRestricted() then return nil, true end
    local ok, effect = pcall(C_UnitAuras.GetUnitAuraBySpellID, "pet", FEED_EFFECT)
    if not ok or issecretvalue(effect) then return nil, true end
    return effect, false
end

function ns.UpdateWarning()
    local cfg = ns.Config()
    if not cfg or InCombatLockdown() then warningPreview = false; HideWarning(); return end
    if not warningPreview then
    if not active or not cfg.screenWarning then HideWarning(); return end
    local _, hunterPet = HasPetUI()
    if not hunterPet or not UnitExists("pet") or UnitIsDead("pet") or UnitAffectingCombat("pet")
        or not C_SpellBook.IsSpellKnown(FEED_SPELL) then HideWarning(); return end
    local mood = C_PetInfo.GetPetHappiness()
    local effect, restricted = FeedingEffect()
    if restricted or issecretvalue(mood) or not mood or mood > cfg.warningAt or effect then
        HideWarning(); return
    end
    end
    if not warning then
        warning = CreateFrame("Frame", "EllesmereUIPetCareWarning", UIParent)
        warning:SetSize(600, 80)
        warning:SetFrameStrata("HIGH")
        warning:EnableMouse(false)
        warning:SetScript("OnEvent", function() ns.SetWarningPreview(false) end)
        warning.text = warning:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        warning.text:SetAllPoints()
        warning.text:SetTextColor(1, 0.7, 0.15, 1)
    end
    warning:ClearAllPoints()
    warning:SetParent(warningPreview and EllesmereUI._panelBody or UIParent)
    warning:SetIgnoreParentScale(true)
    warning:SetPoint("CENTER", UIParent, "CENTER", cfg.warningX, cfg.warningY)
    if not warning.text:SetFont(EllesmereUI.GetFontPath(), cfg.warningSize, "OUTLINE") then
        warning.text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", cfg.warningSize, "OUTLINE")
    end
    warning.text:SetText(EllesmereUI.L("Your pet needs feeding!"))
    warning:SetFrameStrata(warningPreview and "FULLSCREEN_DIALOG" or "HIGH")
    warning:SetFrameLevel(warningPreview and 400 or 10)
    warning:Show()
    if warningPreview then warning:RegisterEvent("PLAYER_REGEN_DISABLED")
    else warning:UnregisterEvent("PLAYER_REGEN_DISABLED") end
end

function ns.WarningPreviewActive() return warningPreview end
function ns.SetWarningPreview(on)
    warningPreview = on == true and not InCombatLockdown()
    if warning and not warningPreview then warning:UnregisterEvent("PLAYER_REGEN_DISABLED") end
    ns.UpdateWarning()
    if warning and warningPreview then warning:RegisterEvent("PLAYER_REGEN_DISABLED") end
end

local function ItemName(id)
    local name = C_Item.GetItemNameByID(id)
    if not name and not requested[id] then
        requested[id] = true
        C_Item.RequestLoadItemDataByID(id)
    end
    return name or (ns.FOOD_LABELS and ns.FOOD_LABELS[id]) or ("Item " .. id)
end
ns.ItemName = ItemName

local function Tooltip(self)
    local mood, damage = C_PetInfo.GetPetHappiness()
    local label = mood == 1 and PET_HAPPINESS1 or mood == 2 and PET_HAPPINESS2 or PET_HAPPINESS3
    local lines = { label or EllesmereUI.L("Pet Care"), ns.Status() }
    if damage then lines[#lines + 1] = PET_DAMAGE_PERCENTAGE:format(damage) end
    local diet = C_PetInfo.GetPetFoodTypes()
    if diet and #diet > 0 then
        lines[#lines + 1] = PET_DIET_TEMPLATE:format(table.concat(diet, PET_FOOD_DELIMIT))
    end
    if chosen then
        lines[#lines + 1] = ItemName(chosen.id) .. " x" .. chosen.count
        if clicksActive then
            lines[#lines + 1] = EllesmereUI.L("Left-click: feed selected food. Shift-left-click: select next food.")
        else
            lines[#lines + 1] = EllesmereUI.L("Shift-left-click: select next food.")
        end
    end
    EllesmereUI.ShowWidgetTooltip(self, table.concat(lines, "\n"))
end

local function BuildButton(h)
    if button then return end
    button = CreateFrame("Button", "EllesmereUIPetCareFeedButton", h:GetParent(), "SecureActionButtonTemplate")
    button:RegisterForClicks("LeftButtonUp")
    button:SetAttribute("useOnKeyDown", false)
    button:SetAttribute("type1", "macro")
    button:SetAttribute("shift-type1", "")
    button:SetScript("PreClick", function()
        if InCombatLockdown() then return end
        ns.Refresh(IsShiftKeyDown())
    end)
    button:SetScript("OnEnter", Tooltip)
    button:SetScript("OnLeave", EllesmereUI.HideWidgetTooltip)
    button._cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button._cooldown:SetAllPoints()
    button._cooldown:SetDrawEdge(false)
    button._cooldown:SetHideCountdownNumbers(false)
    button._cooldown:EnableMouse(false)
    glow = CreateFrame("Frame", nil, h)
    glow:SetAllPoints()
end

local function Scan(cfg)
    local stacks = {}
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local item = C_Container.GetContainerItemInfo(bag, slot)
            if item and (ns.FOODS[item.itemID] or cfg.customFoods[item.itemID]) then
                local quest = C_Container.GetContainerItemQuestInfo(bag, slot)
                local _, _, _, _, _, class = C_Item.GetItemInfoInstant(item.itemID)
                if class == Enum.ItemClass.Consumable or class == Enum.ItemClass.Tradegoods then
                    stacks[#stacks + 1] = { id = item.itemID, count = item.stackCount or 0,
                        locked = item.isLocked, quest = quest and (quest.isQuestItem or (quest.questID and quest.questID > 0)),
                        bag = bag, slot = slot }
                end
            end
        end
    end
    local names = ns.FOOD_NAMES[GetLocale()] or ns.FOOD_NAMES.enUS
    local diet = M.Diet(names, C_PetInfo.GetPetFoodTypes())
    return M.Candidates(stacks, cfg, diet, UnitLevel("pet"), ns.FOODS)
end

function ns.Refresh(advance)
    if InCombatLockdown() then
        StopGlow()
        warningPreview = false
        HideWarning()
        queue.Defer("refresh", function() ns.Refresh() end)
        return
    end
    local cfg = ns.Config()
    if not cfg or not cfg.enabled or not active then return end
    ns.UpdateWarning()
    local uf = UnitFrames()
    local h = uf and uf.GetPetHappinessIcon and uf.GetPetHappinessIcon()
    if not h or not h:IsShown() then
        chosen, candidates = nil, {}
        ns.status = EllesmereUI.L("Enable the hunter pet happiness icon in Unit Frames.")
        StopGlow()
        if button then RegisterStateDriver(button, "visibility", "hide") end
        return
    end
    BuildButton(h)
    anchor = h
    button:SetParent(h:GetParent())
    button:ClearAllPoints()
    button:SetAllPoints(h)
    button:SetFrameLevel(h:GetFrameLevel() + 3)
    glow:SetParent(h)
    glow:ClearAllPoints()
    glow:SetAllPoints(h)
    glow:SetFrameLevel(h:GetFrameLevel() + 2)
    RegisterStateDriver(button, "visibility", "[combat] hide; [@pet,exists,nodead] show; hide")

    local _, hunterPet = HasPetUI()
    local known = C_SpellBook.IsSpellKnown(FEED_SPELL)
    local alive = hunterPet and UnitExists("pet") and not UnitIsDead("pet")
    candidates = alive and Scan(cfg) or {}
    local previous = chosen and chosen.id
    chosen = M.Select(candidates, cfg.selectedFood or (advance and previous), advance)
    if advance then cfg.selectedFood = chosen and chosen.id or nil
    elseif cfg.selectedFood and (not chosen or chosen.id ~= cfg.selectedFood) then cfg.selectedFood = nil end
    local effect, restricted = FeedingEffect()
    feeding = effect
    local usable = known and C_Spell.IsSpellUsable(FEED_SPELL)
    local ready = alive and usable and not UnitAffectingCombat("pet") and not feeding and not restricted and chosen
    local mood = C_PetInfo.GetPetHappiness()
    local glowSpec = ready and mood and mood <= cfg.glowAt
        and G.SpecFromPrefix(spec, cfg, "feedGlow", 1, 0.7, 0.15)
    if glowSpec then
        G.StartSpecGlow(glow, glowSpec, h:GetWidth(), h:GetHeight(), "icon")
        clicksActive = true
    else StopGlow() end
    local text
    if glowSpec then
        text = "/cast [nocombat,@pet,exists,nodead] " .. C_Spell.GetSpellName(FEED_SPELL)
            .. "\n/use [nocombat,@pet,exists,nodead] " .. chosen.bag .. " " .. chosen.slot
        ns.status = EllesmereUI.L("Ready to feed.")
    elseif not known then ns.status = EllesmereUI.L("Learn Feed Pet to use pet feeding.")
    elseif feeding then ns.status = EllesmereUI.L("Your pet is still eating.")
    elseif restricted then ns.status = EllesmereUI.L("Pet feeding is unavailable while aura information is restricted.")
    elseif alive and mood and mood > cfg.glowAt then ns.status = EllesmereUI.L("Your pet does not need feeding.")
    elseif ready then ns.status = EllesmereUI.L("Feeding is inactive while the icon is not glowing.")
    elseif not chosen then ns.status = EllesmereUI.L("No suitable food in your bags. Check the diet and food filters.")
    else ns.status = EllesmereUI.L("Feeding is unavailable while you or your pet are in combat, or the pet is dead.") end
    button:SetAttribute("macrotext1", text)
    button._cooldown:Clear()
    if feeding and not issecretvalue(feeding.duration) and not issecretvalue(feeding.expirationTime)
        and feeding.duration and feeding.duration > 0 and feeding.expirationTime then
        button._cooldown:SetCooldown(feeding.expirationTime - feeding.duration, feeding.duration)
    end
    if button:IsMouseOver() then Tooltip(button) end
end

local function Event(_, event, arg, success)
    if event == "UNIT_PET" and arg ~= "player" then return end
    if (event == "UNIT_HAPPINESS" or event == "UNIT_AURA" or event == "UNIT_LEVEL") and arg ~= "pet" then return end
    if event == "ITEM_DATA_LOAD_RESULT" then
        if not requested[arg] then return end
        requested[arg] = nil
        if not success then return end
    end
    ns.Refresh()
end

function ns.Apply()
    HideWarning()
    if InCombatLockdown() then
        warningPreview = false
        StopGlow()
        queue.Defer("apply", ns.Apply)
        return
    end
    events:UnregisterAllEvents()
    local cfg, uf = ns.Config(), UnitFrames()
    active = cfg and cfg.enabled and select(2, UnitClass("player")) == "HUNTER"
    if uf then uf.PetCareRefresh = active and function() ns.Refresh() end or nil end
    StopGlow()
    if not active then
        chosen, candidates = nil, {}
        ns.status = EllesmereUI.L("Pet feeding is disabled.")
        if button then
            button:SetAttribute("macrotext1", nil)
            RegisterStateDriver(button, "visibility", "hide")
        end
        if warningPreview then ns.UpdateWarning() end
        return
    end
    ns.LoadFoodData()
    events:SetScript("OnEvent", Event)
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "UNIT_PET", "UNIT_HAPPINESS", "UNIT_AURA",
        "UNIT_LEVEL", "BAG_UPDATE_DELAYED", "ITEM_DATA_LOAD_RESULT", "SPELLS_CHANGED", "PLAYER_REGEN_DISABLED" }) do
        events:RegisterEvent(event)
    end
    ns.Refresh()
end

function addon:OnInitialize()
    db = EllesmereUI.Lite.NewDB("EllesmereUIPetCareDB", ns.DEFAULTS)
    ns.db = db
end
function addon:OnEnable() ns.Apply() end
_G._EPC_Apply = ns.Apply
SLASH_EUIPETCARE1 = "/epet"
SlashCmdList.EUIPETCARE = function()
    if not InCombatLockdown() then EllesmereUI:ShowModule(ADDON_NAME) end
end
