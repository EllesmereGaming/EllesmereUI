if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIQoL_Alerts.lua
--  Center-screen text alerts that share ONE movable anchor (Unlock Mode: Alerts).
--  Each alert is a line stacked under the anchor, with its own text, size and
--  color. Short alerts fade out by themselves; a persistent one stays until its
--  condition ends or it is middle-clicked.
--    Combat Alert     (EllesmereUIQoL.lua)   short
--    Potion Ready     (below)                short
--    Unspent Talents  (below)                persistent
--  Nothing is built or registered for an alert until it is enabled.
-------------------------------------------------------------------------------

local ns = select(2, ...)
local EUI = EllesmereUI
local FALLBACK_FONT = "Fonts\\FRIZQT__.TTF"
local DEFAULT_SIZE = 22
local DEFAULT_POS = { point = "CENTER", relPoint = "CENTER", x = 0, y = 169 }
local GAP = 4

local function IsSecret(v) return issecretvalue and issecretvalue(v) or false end
local function DB(key) return EllesmereUIDB and EllesmereUIDB[key] end

-------------------------------------------------------------------------------
--  Core: anchor + stacked lines
-------------------------------------------------------------------------------
local Alerts = {}
EUI.Alerts = Alerts

-- Stack order, top first. sizeKey/enabledKey are the alert's own settings.
local DEFS = {
    { id = "talent", sizeKey = "talentAlertTextSize", enabledKey = "talentAlertEnabled", persistent = true },
    { id = "combat", sizeKey = "combatAlertTextSize", enabledKey = "combatAlertEnabled", hold = 1.2 },
    { id = "potion", sizeKey = "potionAlertTextSize", enabledKey = "potionAlertEnabled", hold = 3 },
}
local lines = {}
local anchor

-- Defaults for the two new alerts; the options cogs read these too.
Alerts.DEFAULTS = {
    potionAlert = { text = "Potion Ready",          color = { r = 0.1, g = 1,    b = 0.1 } },
    talentAlert = { text = "Unspent talent points", color = { r = 1,   g = 0.82, b = 0   } },
}

local function SizeOf(def) return DB(def.sizeKey) or DEFAULT_SIZE end

local function AnyEnabled()
    for _, def in ipairs(DEFS) do
        if DB(def.enabledKey) then return true end
    end
    return false
end

local function MaxSize()
    local m = DEFAULT_SIZE
    for _, def in ipairs(DEFS) do
        if DB(def.enabledKey) then m = math.max(m, SizeOf(def)) end
    end
    return m
end

-- The old Combat Alert position carries over until the anchor is moved.
local function AnchorPos()
    local p = DB("alertsPos")
    if p and p.point then return p end
    p = DB("combatAlertPos")
    if p and p.point then return p end
    return DEFAULT_POS
end

local function PlaceAnchor()
    if not anchor then return end
    local size = MaxSize()
    anchor:SetSize(size * 7, size + 14)
    local pos = AnchorPos()
    anchor:ClearAllPoints()
    anchor:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
end

local function EnsureAnchor()
    if anchor then return end
    anchor = CreateFrame("Frame", nil, UIParent)
    anchor:EnableMouse(false)
    anchor:SetMouseClickEnabled(false)
    PlaceAnchor()
end

local function Layout()
    if not anchor then return end
    local offset = 0
    for _, def in ipairs(DEFS) do
        local line = lines[def.id]
        if line and line.frame:IsShown() then
            line.frame:ClearAllPoints()
            line.frame:SetPoint("TOP", anchor, "TOP", 0, -offset)
            offset = offset + line.frame:GetHeight() + GAP
        end
    end
end

local function Style(line)
    local outline = (EUI.GetFontOutlineFlag("extras")) or ""
    if not outline:find("OUTLINE") then
        outline = (outline == "") and "OUTLINE" or (outline .. ", OUTLINE")
    end
    local size = SizeOf(line.def)
    line.text:SetFont((EUI.GetFontPath("extras")) or EUI.EXPRESSWAY or FALLBACK_FONT, size, outline)
    line.frame:SetSize(size * 7, size + 14)
end

local function NewLine(def)
    local line = { def = def }
    local f = CreateFrame("Button", nil, UIParent)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(60)
    f:EnableMouse(def.persistent == true)
    f:Hide()
    local fs = f:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("CENTER")
    line.frame, line.text = f, fs

    -- Short: fade in, hold, fade out, then hide. Also used for previews.
    local short = f:CreateAnimationGroup()
    local a1 = short:CreateAnimation("Alpha")
    a1:SetFromAlpha(0); a1:SetToAlpha(1); a1:SetDuration(0.15); a1:SetOrder(1)
    local a2 = short:CreateAnimation("Alpha")
    a2:SetFromAlpha(1); a2:SetToAlpha(1); a2:SetDuration(def.hold or 1.2); a2:SetOrder(2)
    local a3 = short:CreateAnimation("Alpha")
    a3:SetFromAlpha(1); a3:SetToAlpha(0); a3:SetDuration(0.5); a3:SetOrder(3)
    short:SetScript("OnFinished", function() f:Hide() end)

    -- Persistent: fade in and stay.
    local stay = f:CreateAnimationGroup()
    local s1 = stay:CreateAnimation("Alpha")
    s1:SetFromAlpha(0); s1:SetToAlpha(1); s1:SetDuration(0.15); s1:SetOrder(1)

    f:SetScript("OnShow", Layout)
    f:SetScript("OnHide", function()
        short:Stop(); stay:Stop()
        line.persistentShown = false
        Layout()
    end)

    if def.persistent then
        f:RegisterForClicks("MiddleButtonUp")
        f:SetScript("OnClick", function(_, button)
            if button == "MiddleButton" then line.Dismiss() end
        end)
        f:SetScript("OnEnter", function(self) EUI.ShowWidgetTooltip(self, "Middle click to dismiss") end)
        f:SetScript("OnLeave", function() EUI.HideWidgetTooltip() end)
    end

    -- preview: play the short animation even on a persistent line, and never
    -- disturb a real persistent alert that is already up.
    function line.Show(text, r, g, b, preview)
        if EUI._unlockActive then return end
        local real = def.persistent and not preview
        if preview and line.persistentShown then return end
        EnsureAnchor(); PlaceAnchor(); Style(line)
        fs:SetText(text)
        fs:SetTextColor(r or 1, g or 1, b or 1)
        if real and line.persistentShown then return end   -- already up: only the text changed
        short:Stop(); stay:Stop()
        f:SetAlpha(1)
        f:Show()
        if real then
            line.persistentShown = true
            stay:Play()
        else
            short:Play()
        end
    end

    function line.Hide() f:Hide() end

    function line.Dismiss()
        f:Hide()
        if line.onDismiss then line.onDismiss() end
    end

    return line
end

-- The line for an alert, built on first use.
function Alerts.Line(id)
    if not lines[id] then
        for _, def in ipairs(DEFS) do
            if def.id == id then lines[id] = NewLine(def) end
        end
    end
    return lines[id]
end

function Alerts.Hide(id)
    if lines[id] then lines[id].Hide() end
end

-- Re-apply size, position and stacking (Text Size sliders, Unlock Mode).
function Alerts.Refresh()
    if anchor or AnyEnabled() then EnsureAnchor(); PlaceAnchor() end
    for _, line in pairs(lines) do Style(line) end
    Layout()
end

-- Custom color, or the player's class color when that toggle is on.
function Alerts.Color(prefix, dr, dg, db)
    if DB(prefix .. "UseClassColor") then
        local _, token = UnitClass("player")
        local c = token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
        if c then return c.r, c.g, c.b end
    end
    local c = DB(prefix .. "Color")
    if c then return c.r, c.g, c.b end
    return dr, dg, db
end

local function RegisterUnlock()
    if not (EUI.RegisterUnlockElements and EUI.MakeUnlockElement) then return end
    EUI:RegisterUnlockElements({
        EUI.MakeUnlockElement({
            key      = "EUI_Alerts",
            label    = "Alerts",
            group    = "Quality of Life",
            order    = 721,
            noResize = true,
            isHidden = function() return not AnyEnabled() end,
            getFrame = function()
                if not AnyEnabled() then return nil end   -- nothing is built while all are off
                EnsureAnchor()
                return anchor
            end,
            getSize = function()
                local size = MaxSize()
                return size * 7, size + 14
            end,
            savePos = function(_, point, relPoint, x, y)
                if not point then return end
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.alertsPos = { point = point, relPoint = relPoint, x = x, y = y }
                if anchor and not EUI._unlockActive then PlaceAnchor(); Layout() end
            end,
            loadPos = function()
                local p = AnchorPos()
                return { point = p.point, relPoint = p.relPoint, x = p.x, y = p.y }
            end,
            clearPos = function()
                if EllesmereUIDB then
                    EllesmereUIDB.alertsPos = nil
                    EllesmereUIDB.combatAlertPos = nil
                end
                if anchor then PlaceAnchor(); Layout() end
            end,
            applyPos = function()
                if anchor or AnyEnabled() then EnsureAnchor(); PlaceAnchor(); Layout() end
            end,
        }),
    })
end

local coreBoot = CreateFrame("Frame")
coreBoot:RegisterEvent("PLAYER_LOGIN")
coreBoot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    RegisterUnlock()
end)

-------------------------------------------------------------------------------
--  Potion Ready
--  The potion you drank is found from its on-use spell (UNIT_SPELLCAST_SUCCEEDED),
--  its cooldown is read once from the item API, and one timer fires at the end.
--  The item cooldown API is not secret-restricted, so it is readable in combat.
--  BAG_UPDATE_COOLDOWN is only listened to while a potion is waiting to start or
--  finish, so presses of other abilities cost nothing in between.
-------------------------------------------------------------------------------
do
    local POTION_CLASS = Enum.ItemClass.Consumable
    local POTION_SUBCLASS = 1   -- Enum.ItemConsumableSubclass.Potion
    local MIN_CD = 1.5   -- anything longer is the potion's own cooldown, not the GCD
    local GetInstant = C_Item and C_Item.GetItemInfoInstant
    local GetUseSpell = C_Item and C_Item.GetItemSpell

    local watcher
    local installed = false
    local spellToItem = {}  -- on-use spellID -> itemID, for potions seen in bags
    local seen = {}         -- itemID -> true (mapped potion) / false (not a potion)
    local timer, pendingItem, usedItem

    local function ShowAlert(preview)
        local D = Alerts.DEFAULTS.potionAlert
        local r, g, b = Alerts.Color("potionAlert", D.color.r, D.color.g, D.color.b)
        Alerts.Line("potion").Show(DB("potionAlertText") or D.text, r, g, b, preview)
    end

    -- start, duration; nil if the item has no cooldown data.
    local function ReadCD(itemID)
        local start, dur = C_Container.GetItemCooldown(itemID)
        if not start or IsSecret(start) or IsSecret(dur) then return nil end
        return start, dur
    end

    local function UpdateCooldownEvent()
        if not watcher then return end
        if installed and (pendingItem or usedItem) then
            watcher:RegisterEvent("BAG_UPDATE_COOLDOWN")
        else
            watcher:UnregisterEvent("BAG_UPDATE_COOLDOWN")
        end
    end

    local function CancelTimer()
        if timer then timer:Cancel(); timer = nil end
        pendingItem = nil
    end

    local ArmTimer

    local function OnReady()
        timer = nil
        local itemID = pendingItem
        pendingItem = nil
        if not itemID then UpdateCooldownEvent(); return end
        -- Last one used up: nothing to be ready for.
        if (C_Item.GetItemCount(itemID) or 0) <= 0 then UpdateCooldownEvent(); return end
        -- A cooldown extended since we armed is re-read here, so the alert is
        -- only for a potion that is really ready.
        local start, dur = ReadCD(itemID)
        if start and dur and dur > MIN_CD then
            local left = start + dur - GetTime()
            if left > 0.5 then ArmTimer(itemID, left); return end
        end
        UpdateCooldownEvent()
        ShowAlert()
    end

    ArmTimer = function(itemID, delay)
        CancelTimer()
        pendingItem = itemID
        timer = C_Timer.NewTimer(math.max(delay, 0), OnReady)
        UpdateCooldownEvent()
    end

    -- Try to start tracking the potion just used. Returns true once armed or given up.
    local function TrackUsed()
        local itemID = usedItem
        if not itemID then return true end
        local start, dur = ReadCD(itemID)
        if not start then
            usedItem = nil
            UpdateCooldownEvent()
            return true
        end
        if dur > MIN_CD then
            usedItem = nil
            ArmTimer(itemID, start + dur - GetTime())
            return true
        end
        return false   -- cooldown not started yet; wait for BAG_UPDATE_COOLDOWN
    end

    -- Item IDs only (no per-slot tables); each item is classified once.
    local function ScanBags()
        if not (GetInstant and GetUseSpell) then return end
        for bag = 0, NUM_BAG_SLOTS do
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                local id = C_Container.GetContainerItemID(bag, slot)
                if id and seen[id] == nil then
                    local _, _, _, _, _, classID, subID = GetInstant(id)
                    if classID == POTION_CLASS and subID == POTION_SUBCLASS then
                        local _, spellID = GetUseSpell(id)
                        if spellID then spellToItem[spellID] = id; seen[id] = true end
                    else
                        seen[id] = false
                    end
                end
            end
        end
    end

    local function OnEvent(_, event, _, _, spellID)
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            if IsSecret(spellID) then return end
            local itemID = spellToItem[spellID]
            if not itemID then return end
            usedItem = itemID
            if not TrackUsed() then
                UpdateCooldownEvent()
                -- No cooldown ever appeared (nothing to wait for): stop listening.
                C_Timer.After(2, function()
                    if usedItem == itemID then usedItem = nil; UpdateCooldownEvent() end
                end)
            end
        elseif event == "BAG_UPDATE_COOLDOWN" then
            if usedItem and TrackUsed() then return end
            if pendingItem then
                -- A reset (encounter end, death) makes the potion ready early.
                local start, dur = ReadCD(pendingItem)
                if start and dur and dur <= MIN_CD then
                    if timer then timer:Cancel(); timer = nil end
                    OnReady()
                end
            end
        elseif event == "BAG_UPDATE_DELAYED" then
            ScanBags()
        end
    end

    local function Apply()
        local on = DB("potionAlertEnabled")
        if on and not installed then
            watcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
            watcher:RegisterEvent("BAG_UPDATE_DELAYED")
            installed = true
            ScanBags()
        elseif not on and installed then
            watcher:UnregisterAllEvents()
            installed = false
            CancelTimer()
            usedItem = nil
            Alerts.Hide("potion")
        end
        if installed then UpdateCooldownEvent() end
        Alerts.Refresh()
    end

    watcher = CreateFrame("Frame")
    watcher:SetScript("OnEvent", OnEvent)

    EUI._applyPotionAlert = Apply
    EUI._potionAlertFrame = Alerts.Refresh
    EUI._potionAlertPreview = function() ShowAlert(true) end

    local boot = CreateFrame("Frame")
    boot:RegisterEvent("PLAYER_LOGIN")
    boot:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        Apply()
    end)
end

-------------------------------------------------------------------------------
--  Unspent Talents (persistent)
--  Same check and trigger events as Blizzard's own talent micro button alert
--  (C_ClassTalents.HasUnspent*), evaluated once after a burst of events.
--  The line stays up while points are unspent, until middle-clicked; it comes
--  back when new points appear, and waits for combat to end before showing.
-------------------------------------------------------------------------------
do
    -- Blizzard's own trigger events for its talent alert (retail), and the
    -- classic talent events (WoW Forever).
    local EVENTS = EUI.IS_FOREVER
        and { "PLAYER_ENTERING_WORLD", "PLAYER_TALENT_UPDATE", "PLAYER_LEVEL_UP", "CHARACTER_POINTS_CHANGED" }
        or { "PLAYER_ENTERING_WORLD", "PLAYER_TALENT_UPDATE", "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_LEVEL_CHANGED" }

    local watcher
    local installed = false
    local lastHad = false
    local dismissed = false
    local dirty = false

    local function HasUnspent()
        if EUI.IS_FOREVER then return (GetUnspentTalentPoints() or 0) > 0 end
        if not C_SpecializationInfo.CanPlayerUseTalentUI() then return false end
        return (C_ClassTalents.HasUnspentTalentPoints() or C_ClassTalents.HasUnspentHeroTalentPoints()) and true or false
    end

    local function Line()
        local line = Alerts.Line("talent")
        line.onDismiss = function() dismissed = true end
        return line
    end

    local function ShowAlert(preview)
        local D = Alerts.DEFAULTS.talentAlert
        local r, g, b = Alerts.Color("talentAlert", D.color.r, D.color.g, D.color.b)
        Line().Show(DB("talentAlertText") or D.text, r, g, b, preview)
    end

    local function Evaluate()
        dirty = false
        if not installed then return end
        if InCombatLockdown() then ns.CombatQueue.Defer("TalentAlert", Evaluate); return end
        local has = HasUnspent()
        if has then
            if not lastHad then dismissed = false end        -- new points: show again
            if not dismissed then ShowAlert() end
        else
            dismissed = false
            Alerts.Hide("talent")
        end
        lastHad = has
    end

    local function MarkDirty()
        if dirty then return end
        dirty = true
        C_Timer.After(1, Evaluate)   -- talent data settles a moment after these events
    end

    local function Apply()
        local on = DB("talentAlertEnabled")
        if on and not installed then
            for _, e in ipairs(EVENTS) do watcher:RegisterEvent(e) end
            installed = true
            lastHad, dismissed = false, false
            MarkDirty()
        elseif not on and installed then
            watcher:UnregisterAllEvents()
            installed = false
            Alerts.Hide("talent")
        end
        Alerts.Refresh()
    end

    watcher = CreateFrame("Frame")
    watcher:SetScript("OnEvent", MarkDirty)

    EUI._applyTalentAlert = Apply
    EUI._talentAlertFrame = Alerts.Refresh
    EUI._talentAlertPreview = function()
        -- A live alert gets its text/color refreshed; otherwise a short sample.
        ShowAlert(not Line().persistentShown)
    end

    local boot = CreateFrame("Frame")
    boot:RegisterEvent("PLAYER_LOGIN")
    boot:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        Apply()
    end)
end
