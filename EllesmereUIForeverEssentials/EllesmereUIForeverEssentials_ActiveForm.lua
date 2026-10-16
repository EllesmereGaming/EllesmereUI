if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_ActiveForm.lua  (WoW Forever only)
--  One click-through icon for the active warrior stance, druid form, paladin
--  aura or hunter aspect; hidden when none is active. Stances and forms read
--  from the stance bar (GetShapeshiftFormInfo); aspects, and auras the game
--  keeps off the stance bar, are matched by spell id on the player's buffs.
-------------------------------------------------------------------------------
local _, module = ...

-- Settings live in EllesmereUIDB.activeForm, beside the shared visibility keys
-- (unset = Always); unset keys read these.
local DEFAULTS = {
    enabled  = false,
    iconSize = 40,
    zoom     = 8,   -- percent of the icon cropped from each edge
    -- Border keys as the other bordered surfaces store them: borderSize is
    -- the legacy step, borderSizePx the exact size beside it (EllesmereUI.BorderPx).
    borderSize = 1, borderTexture = "solid",
    borderR = 0, borderG = 0, borderB = 0, borderA = 1,
}
local F = module.Feature("activeForm", DEFAULTS, { point = "CENTER", relPoint = "CENTER", x = 0, y = -200 })
local Get, Read, Enabled = F.Get, F.Read, F.Enabled

-- Every rank and variant in the Forever build (wago.tools SpellName, build
-- 1.60.1.70245).
local BUFF_SPELLS = {
    HUNTER = {
        { 13165, 14318, 14319, 14320, 14321, 14322, 25296 },         -- Hawk
        { 13163 },                                                   -- Monkey
        { 5118 },                                                    -- Cheetah
        { 13159 },                                                   -- Pack
        { 13161, 1299445, 1299446, 1299447 },                        -- Beast
        { 20043, 20190 },                                            -- Wild
        { 34074, 415423, 415424, 415718 },                           -- Viper
    },
    PALADIN = {
        { 465, 10290, 643, 1032, 10291, 10292, 10293},               -- Devotion
        { 7294, 10298, 10299, 10300, 10301 },                        -- Retribution
        { 19746 },                                                   -- Concentration
        { 19876, 19895, 19896 },                                     -- Shadow Resistance
        { 19888, 19897, 19898 },                                     -- Frost Resistance
        { 19891, 19899, 19900 },                                     -- Fire Resistance
        { 20218 },                                                   -- Sanctity
    },
}

local _, classFile = UnitClass("player")
local buffSpells = BUFF_SPELLS[classFile]
-- The classes the icon draws for; on any other it stays hidden.
local FORM_CLASSES = { WARRIOR = true, DRUID = true, PALADIN = true, HUNTER = true }
local supported = FORM_CLASSES[classFile] == true
local buffIDs  -- [spell id] = true, built the first time it is needed

local frame, tex, border
local eventFrame = CreateFrame("Frame")
local active = false         -- shown, with its events registered
local visRegistered = false  -- on the shared visibility dispatcher

local function IsSecret(v)
    return issecretvalue and issecretvalue(v)
end

local function BuffIcon()
    if not buffIDs then
        buffIDs = {}
        for i = 1, #buffSpells do
            local ids = buffSpells[i]
            for j = 1, #ids do buffIDs[ids[j]] = true end
        end
    end
    for i = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not aura then return nil end
        local id = aura.spellId
        if id and not IsSecret(id) and buffIDs[id] then return aura.icon end
    end
end

-- The active form's icon, or nil.
local function CurrentIcon()
    for i = 1, GetNumShapeshiftForms() do
        local icon, isActive = GetShapeshiftFormInfo(i)
        if isActive then return icon end
    end
    return buffSpells and BuffIcon() or nil
end

local function Refresh()
    if not active then return end
    local icon = CurrentIcon()
    if icon then
        tex:SetTexture(icon)
        frame:Show()
    else
        frame:Hide()
    end
end

local function SnappedSize()
    return EllesmereUI.PP.SnapForES(Get("iconSize"), UIParent:GetEffectiveScale())
end

local function Style()
    frame:SetSize(SnappedSize(), SnappedSize())
    local z = Get("zoom") / 100
    tex:SetTexCoord(z, 1 - z, z, 1 - z)
    local step, texture = Get("borderSize"), Get("borderTexture")
    EllesmereUI.ApplyBorderStyle(border, step,
        Get("borderR"), Get("borderG"), Get("borderB"), Get("borderA"), texture,
        Read().borderTextureOffset, Read().borderTextureOffsetY, nil, nil, nil, step, nil,
        EllesmereUI.BorderPx(Read().borderSizePx, step, texture))
end

local function BuildFrame()
    if frame then return end
    frame = CreateFrame("Frame", "EllesmereUIActiveForm", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(false)
    frame:Hide()
    tex = frame:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    border = CreateFrame("Frame", nil, frame)
    border:SetAllPoints()
    border:EnableMouse(false)
    eventFrame:SetScript("OnEvent", Refresh)
end

-- Active = shown, with its events registered. While enabled but hidden by the
-- visibility setting it costs only that setting's check.
local function SetActive(on)
    if on == active then return end
    active = on
    if on then
        eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
        eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
        eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        if buffSpells then eventFrame:RegisterUnitEvent("UNIT_AURA", "player") end
        Refresh()
        return
    end
    eventFrame:UnregisterAllEvents()
    frame:Hide()
end

local function UpdateVisibility()
    SetActive((frame and supported and Enabled() and EllesmereUI.EvalVisibility(Read()) == true) and true or false)
end

local function Apply()
    if Enabled() then
        BuildFrame()
        if not visRegistered then
            visRegistered = true
            EllesmereUI.RegisterVisibilityUpdater(UpdateVisibility)
        end
        Style()
        if not EllesmereUI._unlockActive then F.Place(frame, true) end
    elseif visRegistered then
        visRegistered = false
        EllesmereUI.UnregisterVisibilityUpdater(UpdateVisibility)
    end
    UpdateVisibility()
    Refresh()
end

-- Entry points for the options page.
EllesmereUI._ActiveForm = {
    Get = Get,
    Read = Read,
    Cfg = F.Cfg,
    Apply = Apply,
}

F.Start(Apply, {
    key = "EUI_ActiveForm", label = "Active Stance", order = 730,
    frame = function() return frame end,
    size = function()
        local size = SnappedSize()
        return size, size
    end,
    snap = true, noAnchorTarget = true, noSizeMatchTarget = true,
})
