if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_AmmoCounter.lua  (WoW Forever only)
--  Hunters: the equipped ammo's icon and how many are left (the ammo slot
--  counts that type across the bags), orange under the warning threshold and
--  red under half of it. Placed by unlock mode. An optional alert, read like
--  the Low Durability warning, pulses while the count is under the threshold.
--
--  Event driven: bag and inventory changes (each shot takes ammo from a bag;
--  equipping other ammo only fires UNIT_INVENTORY_CHANGED).
--  Nothing is built for other classes or while the setting is off.
-------------------------------------------------------------------------------
local _, module = ...

local ICON_SIZE = 22
local PAD = 4
local NO_AMMO_ICON = "Interface\\Icons\\INV_Ammo_Arrow_02"
local ALERT_Y = 210  -- under the Low Durability warning's default spot (250)

-- Settings live in EllesmereUIDB.ammoCounter; unset keys read these.
local F = module.Feature("ammoCounter", { enabled = false, width = 80, warn = 200, alert = false },
    { point = "CENTER", relPoint = "CENTER", x = 0, y = -200 })
local Get = F.Get

local IS_HUNTER = select(2, UnitClass("player")) == "HUNTER"
local frame, events
local alert  -- the Low Ammo Alert, built on its first show

-- Low Ammo Alert, read like the Low Durability warning: a pulsing line above
-- the middle of the screen (just under that warning's spot) while the ammo is
-- under the threshold, out of combat only; it comes back once combat ends.
local function BuildAlert()
    alert = CreateFrame("Frame", nil, UIParent)
    alert:SetSize(400, 40)
    alert:SetFrameStrata("HIGH")
    alert:SetFrameLevel(50)
    alert:SetPoint("CENTER", UIParent, "CENTER", 0, ALERT_Y)
    alert:EnableMouse(false)
    local fs = alert:CreateFontString(nil, "OVERLAY")
    fs:SetFont(EllesmereUI.GetFontPath("extras"), 30, EllesmereUI.GetFontOutlineFlag("extras"))
    fs:SetPoint("CENTER")
    fs:SetTextColor(1, 0.27, 0.27, 1)
    alert.text = fs
    local pulse = fs:CreateAnimationGroup()
    local dim = pulse:CreateAnimation("Alpha")
    dim:SetFromAlpha(1)
    dim:SetToAlpha(0.3)
    dim:SetDuration(0.4)
    dim:SetOrder(1)
    local lit = pulse:CreateAnimation("Alpha")
    lit:SetFromAlpha(0.3)
    lit:SetToAlpha(1)
    lit:SetDuration(0.4)
    lit:SetOrder(2)
    pulse:SetLooping("REPEAT")
    alert:SetScript("OnShow", function() pulse:Play() end)
    alert:SetScript("OnHide", function() pulse:Stop() end)
    alert:Hide()
end

local function SyncAlert(count)
    if not (Get("alert") and count < Get("warn") and not InCombatLockdown()) then
        if alert then alert:Hide() end
        return
    end
    if not alert then BuildAlert() end
    alert.text:SetText(count == 0 and EllesmereUI.L("No Ammo") or EllesmereUI.Lf("Low Ammo (%d)", count))
    alert:Show()
end

-- Bag events fire for any bag change, not only a shot: nothing is redrawn
-- while the ammo and its count stay the same, unless force (a setting, or the
-- end of combat bringing the alert back).
local shownCount, shownTexture
local function Update(force)
    if not frame then return end
    local count = GetInventoryItemCount("player", INVSLOT_AMMO) or 0
    local texture = GetInventoryItemTexture("player", INVSLOT_AMMO) or NO_AMMO_ICON
    if not force and count == shownCount and texture == shownTexture then return end
    shownCount, shownTexture = count, texture
    SyncAlert(count)
    frame.icon:SetTexture(texture)
    frame.icon:SetDesaturated(count == 0)
    local warn = Get("warn")
    if count < warn / 2 then
        frame.count:SetTextColor(1, 0.25, 0.25)
    elseif count < warn then
        frame.count:SetTextColor(1, 0.6, 0.1)
    else
        frame.count:SetTextColor(1, 1, 1)
    end
    frame.count:SetText(count)
end

local function ApplyStyle()
    if not frame then return end
    frame:SetSize(Get("width"), ICON_SIZE + 2 * PAD)
end

local function Build()
    frame = CreateFrame("Frame", "EllesmereUIAmmoCounter", UIParent)
    frame:SetFrameStrata("MEDIUM")
    local bg = EllesmereUI.SolidTex(frame, "BACKGROUND", 0, 0, 0, 0.6)
    bg:SetAllPoints()
    EllesmereUI.MakeBorder(frame, 0, 0, 0, 1)
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetSize(ICON_SIZE, ICON_SIZE)
    frame.icon:SetPoint("LEFT", PAD, 0)
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    frame.count = frame:CreateFontString(nil, "OVERLAY")
    frame.count:SetFont(EllesmereUI.GetFontPath(), 14, EllesmereUI.SlugFlag("OUTLINE, SLUG"))
    frame.count:SetPoint("LEFT", frame.icon, "RIGHT", PAD + 2, 0)
    frame.count:SetPoint("RIGHT", -PAD, 0)
    frame.count:SetJustifyH("CENTER")
    ApplyStyle()
    F.Place(frame)

    events = CreateFrame("Frame")
    events:SetScript("OnEvent", function(_, event)
        -- Before lockdown starts: the alert steps aside for the fight.
        if event == "PLAYER_REGEN_DISABLED" then
            if alert then alert:Hide() end
            return
        end
        Update(event == "PLAYER_REGEN_ENABLED")
    end)
end

-- Off (or not a hunter): hidden and deaf. On: built once, then shown and
-- listening.
local function Apply()
    local on = IS_HUNTER and F.Enabled()
    if on and not frame then Build() end
    if not frame then return end
    frame:SetShown(on)
    if on then
        events:RegisterEvent("BAG_UPDATE_DELAYED")
        events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        events:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
        if Get("alert") then
            events:RegisterEvent("PLAYER_REGEN_DISABLED")
            events:RegisterEvent("PLAYER_REGEN_ENABLED")
        else
            events:UnregisterEvent("PLAYER_REGEN_DISABLED")
            events:UnregisterEvent("PLAYER_REGEN_ENABLED")
        end
        Update(true)
    else
        events:UnregisterAllEvents()
        if alert then alert:Hide() end
    end
end

-- Options-page entry points.
EllesmereUI._AmmoCounter = {
    Get = F.Get,
    Cfg = F.Cfg,
    Apply = Apply,
    Update = Update,
    isHunter = IS_HUNTER,
}

F.Start(Apply, IS_HUNTER and {
    key = "EUI_AmmoCounter", label = "Ammo Counter", order = 740, minWidth = 50,
    frame = function(build)
        if build and not frame then Build() end
        return frame
    end,
    height = function() return ICON_SIZE + 2 * PAD end,
    applyStyle = ApplyStyle,
} or nil)
