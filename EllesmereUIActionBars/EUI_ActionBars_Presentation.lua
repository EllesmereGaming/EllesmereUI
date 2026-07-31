-------------------------------------------------------------------------------
-- EllesmereUI Action Bars - Wrath presentation engine
--
-- The action buttons themselves remain secure and are owned by the main
-- module.  This file owns only their visual state.  Wrath's action APIs return
-- ordinary numbers/booleans and its range API returns 0/1/nil, so keeping the
-- retail duration-object/range-event renderer active creates stale cooldown,
-- desaturation, alpha, and range states.
--
-- Design:
--   * one event frame for every managed action button;
--   * one coalesced render per event burst;
--   * change-cached texture/cooldown/color writes;
--   * one 5 Hz driver, active only for range checks or real cooldown endings.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local EAB = ns and ns.EAB
if not EAB then return end

local _G = _G
local pairs, type, tonumber = pairs, type, tonumber
local abs, max = math.abs, math.max
local GetTime = GetTime
local HasAction = HasAction
local GetActionInfo = GetActionInfo
local GetActionTexture = GetActionTexture
local GetActionCount = GetActionCount
local GetActionText = GetActionText
local GetActionCooldown = GetActionCooldown
local IsUsableAction = IsUsableAction
local IsActionInRange = IsActionInRange
local IsCurrentAction = IsCurrentAction
local IsAutoRepeatAction = IsAutoRepeatAction
local GetSpellCooldown = GetSpellCooldown
local CooldownFrame_Set = CooldownFrame_Set
local C_Timer_After = C_Timer and C_Timer.After

local Presentation = {
    state = setmetatable({}, { __mode = "k" }),
    realCooldowns = setmetatable({}, { __mode = "k" }),
    pendingSlots = {},
    pending = {},
    flushQueued = false,
    rangeEnabled = false,
    elapsed = 0,
}
ns.ActionBarPresentation = Presentation

local function IsActionBarKey(key)
    return key == "MainBar" or (type(key) == "string" and key:match("^Bar%d+$"))
end

local function GetState(button)
    local state = Presentation.state[button]
    if not state then
        state = {}
        Presentation.state[button] = state
    end
    return state
end

local function ResolveRegion(button, member, suffix)
    local region = button[member]
    if region then return region end
    local name = button.GetName and button:GetName()
    if name then
        region = _G[name .. suffix]
        if region then
            -- EAB owns these buttons, so caching the Wrath named regions on
            -- the button is safe and also helps the rest of the ported code.
            button[member] = region
        end
    end
    return region
end

local function GetIcon(button)
    return button.icon or button.Icon
        or ResolveRegion(button, "icon", "Icon")
end

local function GetCooldown(button)
    return button.cooldown or button.Cooldown
        or ResolveRegion(button, "cooldown", "Cooldown")
end

local function GetCount(button)
    return button.Count or button.count
        or ResolveRegion(button, "Count", "Count")
end

local function GetNameText(button)
    return button.Name or button.name
        or ResolveRegion(button, "Name", "Name")
end

local function ResolveAllRegions()
    for barKey, buttons in pairs(ns.barButtons or {}) do
        if IsActionBarKey(barKey) and buttons then
            for i = 1, #buttons do
                local button = buttons[i]
                if button then
                    GetIcon(button)
                    GetCooldown(button)
                    GetCount(button)
                    GetNameText(button)
                end
            end
        end
    end
end

local function GetButtonAction(button)
    local action = ns.GetButtonAction and ns.GetButtonAction(button)
    if action then return action end
    if ActionButton_GetPagedID then
        action = ActionButton_GetPagedID(button)
        if action and action > 0 then return action end
    end
    if button.GetAttribute then
        action = tonumber(button:GetAttribute("action"))
        if action and action > 0 then return action end
    end
    return nil
end

local function GetBarSettings(barKey)
    local profile = EAB.db and EAB.db.profile
    return profile and profile.bars and profile.bars[barKey]
end

local function SetIconDesaturated(icon, desaturated)
    if icon.SetDesaturated then
        icon:SetDesaturated(desaturated and true or false)
    elseif icon.SetDesaturation then
        icon:SetDesaturation(desaturated and 1 or 0)
    end
end

local function ResetPresentation(button, state)
    local icon = GetIcon(button)
    if icon then
        if state.desaturated ~= false then
            SetIconDesaturated(icon, false)
            state.desaturated = false
        end
        if state.iconAlpha ~= 1 then
            icon:SetAlpha(1)
            state.iconAlpha = 1
        end
        if state.tint ~= "normal" then
            icon:SetVertexColor(1, 1, 1)
            state.tint = "normal"
        end
    end
    state.outOfRange = nil
    state.usability = nil
end

local function RenderContent(button, action, state)
    local filled = action and HasAction(action)
    local icon = GetIcon(button)
    local countText = GetCount(button)
    local nameText = GetNameText(button)

    if state.action ~= action then
        state.action = action
        state.outOfRange = nil
        state.usability = nil
        state.tint = nil
        if icon then icon:SetVertexColor(1, 1, 1) end
    end

    if not filled then
        if icon then
            icon:SetTexture(nil)
            icon:Hide()
        end
        if countText then countText:SetText("") end
        if nameText then nameText:SetText("") end
        if button.SetChecked then button:SetChecked(false) end
        state.texture = nil
        state.count = nil
        state.actionText = nil
        state.checked = false
        ResetPresentation(button, state)
        return false
    end

    local texture = GetActionTexture(action)
    if icon then
        if state.texture ~= texture then
            icon:SetTexture(texture)
            state.texture = texture
        end
        if not icon:IsShown() then icon:Show() end
    end

    if countText then
        local count = GetActionCount(action) or 0
        local display = count > 0 and tostring(count) or ""
        if state.count ~= display then
            state.count = display
            countText:SetText(display)
        end
    end

    if nameText then
        local actionType = GetActionInfo(action)
        local text = actionType == "macro" and (GetActionText(action) or "") or ""
        if state.actionText ~= text then
            state.actionText = text
            nameText:SetText(text)
        end
    end

    return true
end

local function ReadGCD()
    if not GetSpellCooldown then return 0, 0 end
    local start, duration, enabled = GetSpellCooldown(61304)
    if enabled == 0 or not start or not duration then return 0, 0 end
    return start, duration
end

local function IsGCD(start, duration, gcdStart, gcdDuration)
    if not start or not duration or duration <= 0 then return false end
    if not gcdStart or gcdStart <= 0 or not gcdDuration or gcdDuration <= 0 then
        return false
    end
    -- The action and spell cooldown calls describe the same GCD but can differ
    -- by a tiny floating-point amount on some 3.3.5a cores.
    return abs(start - gcdStart) < 0.05 and abs(duration - gcdDuration) < 0.05
end

local function ApplyCooldownPresentation(button, state, realCooldown)
    local profile = EAB.db and EAB.db.profile
    local desaturated = profile and profile.desaturateOnCooldown and realCooldown or false
    local alpha = 1
    if realCooldown and profile then
        alpha = max(0, math.min(100, profile.alphaWhenOnCD or 100)) / 100
    end

    local icon = GetIcon(button)
    if not icon then return end
    if state.desaturated ~= desaturated then
        SetIconDesaturated(icon, desaturated)
        state.desaturated = desaturated
    end
    if state.iconAlpha ~= alpha then
        icon:SetAlpha(alpha)
        state.iconAlpha = alpha
    end
end

local function RenderCooldown(button, action, state, now, gcdStart, gcdDuration)
    local cooldown = GetCooldown(button)
    if not cooldown then return end

    local start, duration, enabled = 0, 0, 0
    if action and HasAction(action) then
        start, duration, enabled = GetActionCooldown(action)
        start = start or 0
        duration = duration or 0
        enabled = enabled == nil and 1 or enabled
    end

    local active = enabled ~= 0 and start > 0 and duration > 0
        and (start + duration) > (now + 0.01)
    if not active then
        start, duration, enabled = 0, 0, 0
    end

    if state.cooldownStart ~= start or state.cooldownDuration ~= duration
        or state.cooldownEnabled ~= enabled then
        state.cooldownStart = start
        state.cooldownDuration = duration
        state.cooldownEnabled = enabled
        CooldownFrame_Set(cooldown, start, duration, enabled)
    end

    local realCooldown = active and not IsGCD(start, duration, gcdStart, gcdDuration)
    state.realCooldown = realCooldown
    if realCooldown then
        state.cooldownEnd = start + duration
        Presentation.realCooldowns[button] = true
    else
        state.cooldownEnd = nil
        Presentation.realCooldowns[button] = nil
    end
    ApplyCooldownPresentation(button, state, realCooldown)
end

local function ResolveTint(state, settings)
    if state.outOfRange and settings and settings.outOfRangeColoring then
        return "range"
    end
    return state.usability or "normal"
end

local function ApplyTint(button, state, settings)
    local tint = ResolveTint(state, settings)
    if state.tint == tint then return end
    local icon = GetIcon(button)
    if not icon then return end

    if tint == "range" then
        local color = settings.outOfRangeColor or { r = 0.8, g = 0.1, b = 0.1 }
        icon:SetVertexColor(color.r or 0.8, color.g or 0.1, color.b or 0.1)
    elseif tint == "mana" then
        icon:SetVertexColor(0.5, 0.5, 1)
    elseif tint == "unusable" then
        icon:SetVertexColor(0.4, 0.4, 0.4)
    else
        icon:SetVertexColor(1, 1, 1)
    end
    state.tint = tint
end

local function RenderUsability(button, action, state, settings)
    if not action or not HasAction(action) then
        state.usability = "normal"
        state.outOfRange = nil
        ApplyTint(button, state, settings)
        return
    end
    local usable, noMana = IsUsableAction(action)
    if usable then
        state.usability = "normal"
    elseif noMana then
        state.usability = "mana"
    else
        state.usability = "unusable"
    end
    ApplyTint(button, state, settings)
end

local function RenderChecked(button, action, state)
    local checked = action and HasAction(action)
        and (IsCurrentAction(action) or IsAutoRepeatAction(action)) or false
    if state.checked ~= checked then
        state.checked = checked
        if button.SetChecked then button:SetChecked(checked) end
    end
end

local function RenderButton(button, barKey, flags, now, gcdStart, gcdDuration)
    local state = GetState(button)
    state.barKey = barKey
    local action = GetButtonAction(button)
    local settings = GetBarSettings(barKey)

    if flags.content and not RenderContent(button, action, state) then
        local cooldown = GetCooldown(button)
        if cooldown and (state.cooldownStart ~= 0 or state.cooldownDuration ~= 0) then
            state.cooldownStart, state.cooldownDuration, state.cooldownEnabled = 0, 0, 0
            CooldownFrame_Set(cooldown, 0, 0, 0)
        end
        Presentation.realCooldowns[button] = nil
        return
    end
    if flags.cooldown then
        RenderCooldown(button, action, state, now, gcdStart, gcdDuration)
    end
    if flags.usable then
        RenderUsability(button, action, state, settings)
    end
    if flags.checked then
        RenderChecked(button, action, state)
    end
end

local function Render(flags, targetSlots)
    local now = GetTime()
    local gcdStart, gcdDuration = 0, 0
    if flags.cooldown then gcdStart, gcdDuration = ReadGCD() end

    for barKey, buttons in pairs(ns.barButtons or {}) do
        if IsActionBarKey(barKey) and buttons then
            for i = 1, #buttons do
                local button = buttons[i]
                if button then
                    local action = GetButtonAction(button)
                    if not targetSlots or (action and targetSlots[action]) then
                        RenderButton(button, barKey, flags, now, gcdStart, gcdDuration)
                    end
                end
            end
        end
    end
    if Presentation.UpdateDriver then Presentation:UpdateDriver() end
end

local function Flush()
    Presentation.flushQueued = false
    local pending = Presentation.pending
    local flags = {
        content = pending.all or pending.content or false,
        cooldown = pending.all or pending.cooldown or false,
        usable = pending.all or pending.usable or false,
        checked = pending.all or pending.checked or false,
    }
    local targetSlots
    if not pending.all and not pending.global then
        targetSlots = Presentation.pendingSlots
    end
    Presentation.pending = {}
    Presentation.pendingSlots = {}
    if flags.content or flags.cooldown or flags.usable or flags.checked then
        Render(flags, targetSlots)
    end
end

local function Queue(kind, slot)
    if kind == "all" then
        Presentation.pending.all = true
    else
        Presentation.pending[kind] = true
    end
    if slot and slot > 0 and not Presentation.pending.all then
        Presentation.pendingSlots[slot] = true
    elseif not slot then
        -- A global event must not inherit a target set from an earlier
        -- same-frame slot event.
        Presentation.pending.global = true
        Presentation.pendingSlots = {}
    end
    if Presentation.flushQueued then return end
    Presentation.flushQueued = true
    C_Timer_After(0, Flush)
end

local function RefreshRange(force)
    for barKey, buttons in pairs(ns.barButtons or {}) do
        if IsActionBarKey(barKey) and buttons then
            local settings = GetBarSettings(barKey)
            for i = 1, #buttons do
                local button = buttons[i]
                if button and button:IsVisible() then
                    local state = GetState(button)
                    local action = GetButtonAction(button)
                    local outOfRange = false
                    if Presentation.rangeEnabled and settings
                        and settings.outOfRangeColoring and action and HasAction(action) then
                        local result = IsActionInRange(action)
                        -- Wrath returns 1, 0, or nil. nil means the action has no range.
                        outOfRange = result == 0 or result == false
                    end
                    if state.outOfRange ~= outOfRange then
                        state.outOfRange = outOfRange
                        ApplyTint(button, state, settings)
                    elseif force or state.tint == nil then
                        ApplyTint(button, state, settings)
                    end
                end
            end
        end
    end
end

local function DriverOnUpdate(_, elapsed)
    Presentation.elapsed = Presentation.elapsed + elapsed
    if Presentation.elapsed < 0.2 then return end
    Presentation.elapsed = 0

    local now = GetTime()
    local gcdStart, gcdDuration = ReadGCD()
    for button in pairs(Presentation.realCooldowns) do
        local state = Presentation.state[button]
        if not state or not state.cooldownEnd or now >= state.cooldownEnd then
            local barKey = state and state.barKey
            if barKey then
                RenderButton(button, barKey, {
                    content = false, cooldown = true, usable = false, checked = false,
                }, now, gcdStart, gcdDuration)
            else
                Presentation.realCooldowns[button] = nil
            end
        end
    end
    RefreshRange(false)
    Presentation:UpdateDriver()
end

function Presentation:UpdateDriver()
    if not self.driver then return end
    local needed = self.rangeEnabled or next(self.realCooldowns) ~= nil
    if needed and not self.driverActive then
        self.driverActive = true
        self.driver:SetScript("OnUpdate", DriverOnUpdate)
    elseif not needed and self.driverActive then
        self.driverActive = false
        self.driver:SetScript("OnUpdate", nil)
    end
end

function Presentation:RefreshConfiguration()
    self.rangeEnabled = false
    local profile = EAB.db and EAB.db.profile
    local bars = profile and profile.bars
    if bars then
        for key, settings in pairs(bars) do
            if IsActionBarKey(key) and settings and settings.outOfRangeColoring then
                self.rangeEnabled = true
                break
            end
        end
    end
    for button, state in pairs(self.state) do
        if state.outOfRange then
            state.tint = nil
            if not self.rangeEnabled then
                state.outOfRange = false
                ApplyTint(button, state, GetBarSettings(state.barKey))
            end
        end
    end
    self.elapsed = 0.2
    RefreshRange(true)
    self:UpdateDriver()
    Queue("cooldown")
end

function Presentation:Install()
    if self.installed then
        Queue("all")
        return
    end
    self.installed = true
    ResolveAllRegions()

    local eventFrame = ns.TakeShell and ns.TakeShell() or CreateFrame("Frame")
    self.eventFrame = eventFrame
    eventFrame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
    eventFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")
    eventFrame:RegisterEvent("ACTIONBAR_UPDATE_USABLE")
    eventFrame:RegisterEvent("ACTIONBAR_UPDATE_STATE")
    eventFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
    eventFrame:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
    eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("SPELLS_CHANGED")
    eventFrame:SetScript("OnEvent", function(_, event, arg1)
        if event == "ACTIONBAR_UPDATE_COOLDOWN" or event == "BAG_UPDATE_COOLDOWN" then
            Queue("cooldown")
        elseif event == "ACTIONBAR_UPDATE_USABLE" then
            Queue("usable")
        elseif event == "ACTIONBAR_UPDATE_STATE" then
            Queue("checked")
        elseif event == "ACTIONBAR_SLOT_CHANGED" then
            if arg1 and arg1 > 0 then
                Presentation.pending.content = true
                Presentation.pending.cooldown = true
                Presentation.pending.usable = true
                Presentation.pending.checked = true
                Queue("content", arg1)
            else
                Queue("all")
            end
        elseif event == "PLAYER_TARGET_CHANGED" then
            Presentation.elapsed = 0.2
            Queue("usable")
        else
            Queue("all")
        end
    end)

    local driver = ns.TakeShell and ns.TakeShell() or CreateFrame("Frame")
    self.driver = driver

    EAB._RefreshCooldownVisuals = function(button)
        if not button then return end
        local now = GetTime()
        local gcdStart, gcdDuration = ReadGCD()
        RenderCooldown(button, GetButtonAction(button), GetState(button),
            now, gcdStart, gcdDuration)
        Presentation:UpdateDriver()
    end
    ns.ScheduleCooldownRefresh = function()
        Queue("cooldown")
    end

    self:RefreshConfiguration()
    Queue("all")
end

-- These entry points are called by the existing setup/options layer. Replacing
-- them here keeps the configuration UI and secure button/layout code intact
-- while making this file the single owner of runtime presentation.
function EAB:SetupEventDispatcher()
    Presentation:Install()
end

function EAB:ApplyRangeColoring()
    Presentation:RefreshConfiguration()
end

function EAB:ApplyCDAlphaAll()
    Queue("cooldown")
end
