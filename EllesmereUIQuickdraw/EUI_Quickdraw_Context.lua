if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Quickdraw_Context.lua
--
--  Contexts: a menu that loads only while the game says the player is in some
--  situation -- standing by a campfire, so far -- and that takes over the key
--  it shares for as long as it lasts. Nothing new to learn: the player holds
--  the key they always hold, and gets the menu that fits where they are.
--
--  palette.context names one entry of CONTEXTS; nil is "always". A context
--  menu shares another menu's key (palette.keyShare, the same share Assign to
--  Spec uses) and KeyTarget hands the key to it first while its context is on.
--  A small hint icon shows while a context menu is reachable, so the player
--  knows there is something under the key right now. Clicking it opens the
--  menu, so a context menu works with no key bound at all.
--
--  The signal is an AURA the game puts on the player: no position, no polling.
--  Out of combat only. Auras are not readable in combat on every client, and
--  the override bindings cannot move there anyway, so a fight drops every
--  context at PLAYER_REGEN_DISABLED (which still allows the rebind) and the
--  key is back on its everyday menu for the whole of it.
--
--  Reads the earlier Quickdraw files through ns and ns._qdInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._qdInternals
-- EllesmereUIQuickdraw.lua or an earlier Quickdraw file failed to load.
if not I or I.broken then return end
I.broken = true

local type, pairs = type, pairs
local InCombatLockdown = InCombatLockdown
local GetBindingKey = GetBindingKey

local P, PaletteCount, RequestPush = I.P, I.PaletteCount, I.RequestPush
local PA = I.PA
local ResolveAction, FireInsecure = I.ResolveAction, I.FireInsecure
local BINDING_PREFIX = I.BINDING_PREFIX

-------------------------------------------------------------------------------
--  The contexts
--
--  aura   the spell ID of the player aura that says the context is on
--  icon   the hint's texture (the aura's own icon)
--  buff   the spell ID of the reward the situation gives, for a menu set to
--         stand down while the player already has it (Hide When Buffed)
--  label  the options dropdown's name for it
--  seed   what a still-empty menu is given when the context is picked; the
--         player fills it from there like any other menu
-------------------------------------------------------------------------------
local CONTEXTS = {
    campfire = {
        -- The aura every campfire gives the players standing by it
        -- (measured on WoW Forever, 2026-11-05).
        aura  = 1283391,
        icon  = 7808147,
        -- Camp Benefits, the hour-long reward of a camp (same build).
        buff  = 1229741,
        label = "Near a Campfire",
        seed  = {
            -- Cooking, by position (the menu's Professions entries): every
            -- recipe the game makes wait for a fire is a cooking one, and a
            -- character without Cooking simply does not see it.
            { kind = "dynamicprofession", index = 3 },
            -- The campsite accessories carried right now (the professions'
            -- pieces placed by a campfire), one cell each.
            { kind = "campsite" },
            { kind = "emote", token = "SIT" },
            { kind = "emote", token = "HELLO" },
            -- Purple Dust Pouch, the toy that turns a campfire purple. Hidden
            -- by Hide Unavailable Actions for a player who does not own it.
            { kind = "toy", id = 289439 },
        },
    },
}
local CONTEXT_ORDER = { "campfire" }
ns.CONTEXTS, ns.CONTEXT_ORDER = CONTEXTS, CONTEXT_ORDER

-- Which contexts are on right now: key -> true.
local active = {}
local fighting = false

-- Hide When Buffed (palette.contextSkipBuff): the menu stands down while the
-- player has the context's reward with more than palette.contextSkipMinutes
-- left (0: whenever it is up). Returns whether it stands down, and when not
-- for a timed reason, how many seconds until it would come back.
local function StandsDown(index, def)
    local p = P()
    local pal = p and index and p.palettes and p.palettes[index]
    if type(pal) ~= "table" or not pal.contextSkipBuff or not def.buff then return false end
    local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    local aura = get and get(def.buff)
    if not aura then return false end
    local minutes = tonumber(pal.contextSkipMinutes) or 0
    local exp = aura.expirationTime
    if minutes <= 0 or type(exp) ~= "number" or exp == 0 then return true end
    local over = exp - GetTime() - minutes * 60
    if over > 0 then return true, over end
    return false
end

function ns.ContextActive(key, index)
    if active[key] ~= true then return false end
    if index and StandsDown(index, CONTEXTS[key]) then return false end
    return true
end

local function Measure(def)
    local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    return get and get(def.aura) ~= nil or false
end

-------------------------------------------------------------------------------
--  The hint
--
--  The aura's icon with the key under it (when the menu has one), at a fixed
--  spot below the middle of the screen. A click opens the menu itself, as
--  its key would (below); a second click closes it.
--  Made here in the main chunk so its cost is billed to this addon.
-------------------------------------------------------------------------------
local HINT_SIZE = 36
local hint = CreateFrame("Button", "EUIQuickdrawContextHint", UIParent)
hint:SetSize(HINT_SIZE, HINT_SIZE)
-- Its place: below the middle of the screen until moved by hand (below;
-- profile.contextHintPos, CENTER offsets).
local HINT_X, HINT_Y = 0, -170
local function PlaceHint()
    local p = P()
    local pos = p and p.contextHintPos
    hint:ClearAllPoints()
    hint:SetPoint("CENTER", UIParent, "CENTER",
        (pos and pos.x) or HINT_X, (pos and pos.y) or HINT_Y)
end
PlaceHint()

-- Shift + Left-Click and drag moves it, the house way (the Damage Meters
-- strips, the minimap buttons).
hint:SetMovable(true)
hint:SetClampedToScreen(true)
hint:SetScript("OnMouseDown", function(self, button)
    if button == "LeftButton" and IsShiftKeyDown() and not InCombatLockdown() then
        self.dragging = true
        self:StartMoving()
    end
end)
hint:SetScript("OnMouseUp", function(self)
    if not self.dragging then return end
    self.dragging = nil
    self:StopMovingOrSizing()
    local cx, cy = self:GetCenter()
    local ux, uy = UIParent:GetCenter()
    local p = P()
    if p and cx and ux then p.contextHintPos = { x = cx - ux, y = cy - uy } end
    PlaceHint()
    self.dragged = true -- the click this release makes opens nothing
end)
hint:SetFrameStrata("MEDIUM")
hint:RegisterForClicks("LeftButtonUp")
hint:Hide()
local hintIcon = hint:CreateTexture(nil, "ARTWORK")
hintIcon:SetAllPoints()
hintIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
local hintKey = hint:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
hintKey:SetPoint("TOP", hint, "BOTTOM", 0, -3)
hint:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

-------------------------------------------------------------------------------
--  Opening the menu from the hint
--
--  The click opens the menu itself (ns.Open: its own layout, look, position
--  and selection, whatever the menu is set to, as its key would), and a
--  screen-wide secure button takes the next click: on the selected entry it
--  fires that entry the way a release fires it (ResolveAction, FireInsecure
--  for the kinds with no secure action); anywhere else it only closes the
--  menu. Out of combat only: every context drops at PLAYER_REGEN_DISABLED,
--  and the menu with it.
-------------------------------------------------------------------------------
local liveView
local picker = CreateFrame("Button", "EUIQuickdrawContextPicker", UIParent, "SecureActionButtonTemplate")
picker:SetAllPoints(UIParent)
picker:SetFrameStrata("FULLSCREEN_DIALOG")
picker:RegisterForClicks("AnyUp")
picker:SetAttribute("useOnKeyDown", false)
picker:Hide()
local pickerFor, pickedInsecure

local function ClosePicker()
    pickerFor, pickedInsecure = nil, nil
    if InCombatLockdown() then return end
    picker:SetAttribute("type", nil)
    picker:Hide()
end

picker:SetScript("PreClick", function(self, button)
    pickedInsecure = nil
    if InCombatLockdown() then return end
    self:SetAttribute("type", nil)
    if button ~= "LeftButton" or not (liveView and pickerFor) then return end
    local sel = liveView:GetSelection()
    local slot = sel and liveView:CellSlot(sel)
    if not slot or slot.kind == "palette" then return end
    local t, key, value, clear = ResolveAction(slot, PA(pickerFor))
    if t then
        self:SetAttribute("type", t)
        if key then self:SetAttribute(key, value) end
        if clear then self:SetAttribute(clear, nil) end
    else
        pickedInsecure = slot
    end
end)
picker:SetScript("PostClick", function()
    local slot = pickedInsecure
    if slot then FireInsecure(slot) end
    -- Closing the menu closes the picker too (its OnHide hook, below).
    if ns.Close then ns.Close() end
    ClosePicker()
end)

-- The menu closes on its own too (its open timeout, a zone change): the
-- picker goes with it.
local function LiveView()
    if not liveView and I.CreateLiveView then
        liveView = I.CreateLiveView()
        liveView:GetFrame():HookScript("OnHide", ClosePicker)
    end
    return liveView
end

local function OpenFromHint(index)
    if InCombatLockdown() or not ns.Open then return end
    local view = LiveView()
    if not view then return end
    if view:GetFrame():IsShown() then
        ns.Close()
        return
    end
    -- What the bags hold now (Campsite Items is a view on them).
    if I.usableMemo then wipe(I.usableMemo) end
    ns.Open(index)
    if not view:GetFrame():IsShown() then return end
    pickerFor = index
    picker:Show()
end

hint:SetScript("OnClick", function(self)
    GameTooltip:Hide()
    if self.dragged or IsShiftKeyDown() then
        self.dragged = nil
        return
    end
    if self.palette then OpenFromHint(self.palette) end
end)
-- Below the hint and its key: the menu opens round the cursor, which is on it.
hint:SetScript("OnEnter", function(self)
    if not self.contextKey then return end
    GameTooltip:SetOwner(self, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("TOP", self, "BOTTOM", 0, -18)
    GameTooltip:SetText(EllesmereUI.L(CONTEXTS[self.contextKey].label))
    GameTooltip:AddLine(EllesmereUI.L("Click to open this menu."), 1, 1, 1, true)
    GameTooltip:AddLine(EllesmereUI.L("Reposition this element with Shift+Click and Drag."), 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end)
hint:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- The first context menu the player can reach right now, its context and the
-- key that opens it (nil when it has none: the hint's click opens it then).
local function ReachableContextMenu()
    for i = 1, PaletteCount() do
        local key = ns.PaletteContext(i)
        if key and active[key] and ns.PaletteActive(i) then
            local holder = ns.ShareOwner(i) or i
            return i, key, GetBindingKey(BINDING_PREFIX .. holder)
        end
    end
    return nil
end

local function UpdateHint()
    if InCombatLockdown() then return end -- the picker is secure
    local p = P()
    local i, key, k1
    if p and p.enabled and not fighting then i, key, k1 = ReachableContextMenu() end
    if not i then
        -- The menu the hint opened goes with the context.
        if pickerFor and ns.Close then ns.Close() end
        ClosePicker()
        hint.palette, hint.contextKey = nil, nil
        hint:Hide()
        return
    end
    hint.palette, hint.contextKey = i, key
    hintIcon:SetTexture(CONTEXTS[key].icon)
    hintKey:SetText(k1 and (GetBindingText and GetBindingText(k1) or k1) or "")
    hint:Show()
end
ns.UpdateContextHint = UpdateHint

-------------------------------------------------------------------------------
--  Following the signal
-------------------------------------------------------------------------------
-- Which context menus are up for grabs, as one string: a menu standing down
-- for Hide When Buffed changes it without any context flipping.
local lastReach = ""
local recheck -- the pending timer for a reward running down past its limit
local function Evaluate()
    local changed = false
    local readable = not fighting and not InCombatLockdown()
    for key, def in pairs(CONTEXTS) do
        local on = readable and Measure(def) or false
        if (active[key] == true) ~= on then
            active[key] = on or nil
            changed = true
        end
    end
    local reach, soonest = "", nil
    for i = 1, PaletteCount() do
        local key = ns.PaletteContext(i)
        if key and active[key] then
            local down, wait = StandsDown(i, CONTEXTS[key])
            reach = reach .. (down and "0" or "1")
            if wait and (not soonest or wait < soonest) then soonest = wait end
        end
    end
    if reach ~= lastReach then
        lastReach = reach
        changed = true
    end
    if recheck then recheck:Cancel(); recheck = nil end
    if soonest then recheck = C_Timer.NewTimer(soonest + 0.5, Evaluate) end
    if changed then
        -- KeyTarget reads ns.PaletteActive, which reads the contexts: the
        -- binding signature moves with them, so this rebinds only on a flip.
        ns.UpdateBindings()
        RequestPush()
    end
    UpdateHint()
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "BAG_UPDATE_DELAYED" then
        -- Campsite Items follows the bags while a context menu is up for grabs.
        if next(active) then RequestPush() end
        return
    elseif event == "PLAYER_REGEN_DISABLED" then
        fighting = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        fighting = false
    end
    Evaluate()
end)

-- Wanted only while the module is on and some menu names a context: a
-- profile without one never sees a single UNIT_AURA.
local eventsOn = false
local function Wanted()
    local p = P()
    if not (p and p.enabled) then return false end
    for i = 1, PaletteCount() do
        if ns.PaletteContext(i) then return true end
    end
    return false
end

-- Reached from ns.Refresh and OnEnable.
function ns.ContextRefresh()
    PlaceHint() -- a profile switch brings its own spot
    local on = Wanted()
    if on ~= eventsOn then
        eventsOn = on
        if on then
            eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
            eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
            eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
            eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
            fighting = InCombatLockdown() and true or false
        else
            eventFrame:UnregisterAllEvents()
            for key in pairs(active) do active[key] = nil end
            ns.UpdateBindings()
        end
    end
    if on then Evaluate() else UpdateHint() end
end

I.broken = false
