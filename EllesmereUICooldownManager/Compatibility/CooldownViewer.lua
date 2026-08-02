local addonName, ns = ...

-- This file globally polyfills the Retail C_CooldownViewer API for WotLK 3.3.5a.
-- We do this to decouple the data layer from EllesmereUI's internal namespaces,
-- allowing standard Retail renderer code to work unchanged on older clients
-- and making this Cooldown logic reusable for other addons.
-- Note: Runtime behavior requires in-client verification.

_G.C_CooldownViewer = _G.C_CooldownViewer or {}

-- Internal Data Models
local definitions = {}      -- cooldownID -> definition schema
local availability = {}     -- cooldownID -> { isKnown = boolean, activeSpellID = number, activeAuraSpellID = number }
local runtimeState = {}     -- cooldownID -> { cooldownStart, cooldownDuration, cooldownEnabled, auraActive, auraStacks, auraDuration, auraExpiration }
local categories = {}       -- categoryID -> array of cooldownIDs
local adapters = {}         -- cooldownID -> native adapter frame
local internalCooldownIDsByAura = {} -- proc aura spellID -> array of cooldownIDs

-- The renderer expects the objects returned by itemFramePool to be real,
-- anchorable frames.  A Lua table can expose GetSpellID/cooldownInfo, but it
-- cannot own textures or be placed on a CDM bar, so catalog entries would be
-- discovered without ever producing pixels on screen.
local viewerNamesByCategory = {
    [1] = "EssentialCooldownViewer",
    [2] = "UtilityCooldownViewer",
    [3] = "BuffIconCooldownViewer",
    [4] = "BuffBarCooldownViewer",
}

-- Caching
local cachedPlayerAuras = {}
local cachedAuraTime = 0

-- Event Tracker Frame
local tracker = CreateFrame("Frame")

local function ValidateDefinition(def)
    if not def.key then return false, "Missing key" end
    if not def.cooldownID then return false, "Missing cooldownID" end
    if definitions[def.cooldownID] then return false, "Duplicate cooldownID" end

    local keyExists = false
    for _, existing in pairs(definitions) do
        if existing.key == def.key then
            keyExists = true
            break
        end
    end
    if keyExists then return false, "Duplicate key" end

    if not def.category then return false, "Missing category" end
    if not def.trackingType then return false, "Missing trackingType" end
    if def.internalCooldown ~= nil
        and (type(def.internalCooldown) ~= "number" or def.internalCooldown < 0) then
        return false, "internalCooldown must be a non-negative number"
    end

    if def.trackingType == "cooldown" and not def.spellID then return false, "Tracking type cooldown requires spellID" end
    if def.trackingType == "aura" and not (def.spellID or def.auraSpellID) then return false, "Tracking type aura requires spellID or auraSpellID" end

    return true
end

-- Adapter Prototype
local AdapterMixin = {}
function AdapterMixin:GetSpellID()
    local avail = availability[self.cooldownID]
    local def = definitions[self.cooldownID]
    if avail and avail.activeSpellID then return avail.activeSpellID end
    if def then return def.overrideSpellID or def.spellID end
    return nil
end

function AdapterMixin:GetAuraSpellID()
    local avail = availability[self.cooldownID]
    local def = definitions[self.cooldownID]
    if avail and avail.activeAuraSpellID then return avail.activeAuraSpellID end
    if def then return def.auraSpellID or def.spellID end
    return nil
end

function AdapterMixin:IsShown()
    return self._isShown ~= false
end

function AdapterMixin:IsVisible()
    return self:IsShown()
end

function AdapterMixin:Show()
    self._isShown = true
end

function AdapterMixin:Hide()
    self._isShown = false
end

function AdapterMixin:SetShown(show)
    self._isShown = show and true or false
end

function AdapterMixin:SetAlpha(a)
    self._alpha = a
end

function AdapterMixin:GetAlpha()
    return self._alpha or 1
end

function AdapterMixin:ClearAllPoints() end
function AdapterMixin:SetPoint() end
function AdapterMixin:GetScale()
    return 1
end

function AdapterMixin:GetObjectType()
    return "Frame"
end

function AdapterMixin:IsObjectType(t)
    return t == "Frame"
end

local DummyRegionMixin = {}
function DummyRegionMixin:SetTexture() end
function DummyRegionMixin:SetColorTexture() end
function DummyRegionMixin:SetVertexColor() end
function DummyRegionMixin:SetAlpha(a) self._alpha = a end
function DummyRegionMixin:GetAlpha() return self._alpha or 1 end
function DummyRegionMixin:SetAllPoints() end
function DummyRegionMixin:SetPoint() end
function DummyRegionMixin:ClearAllPoints() end
function DummyRegionMixin:Show() self._shown = true end
function DummyRegionMixin:Hide() self._shown = false end
function DummyRegionMixin:IsShown() return self._shown ~= false end
function DummyRegionMixin:SetShown(s) self._shown = s and true or false end
function DummyRegionMixin:SetDrawLayer() end
function DummyRegionMixin:SetDesaturated() end
function DummyRegionMixin:IsDesaturated() return false end
function DummyRegionMixin:SetFont() end
function DummyRegionMixin:SetText() end
function DummyRegionMixin:GetText() return "" end
function DummyRegionMixin:SetTextColor() end
function DummyRegionMixin:SetFrameLevel() end
function DummyRegionMixin:GetFrameLevel() return 1 end

local function CreateDummyRegion()
    local r = {}
    setmetatable(r, { __index = DummyRegionMixin })
    return r
end

function AdapterMixin:GetFrameLevel()
    return self._frameLevel or 1
end

function AdapterMixin:SetFrameLevel(lvl)
    self._frameLevel = lvl
end

function AdapterMixin:GetFrameStrata()
    return self._frameStrata or "MEDIUM"
end

function AdapterMixin:SetFrameStrata(strata)
    self._frameStrata = strata
end

function AdapterMixin:CreateTexture()
    return CreateDummyRegion()
end

function AdapterMixin:CreateFontString()
    return CreateDummyRegion()
end

function AdapterMixin:GetParent()
    return self._parent or UIParent
end

function AdapterMixin:SetParent(p)
    self._parent = p
end

function AdapterMixin:GetWidth()
    return self._width or 32
end

function AdapterMixin:GetHeight()
    return self._height or 32
end

function AdapterMixin:SetWidth(w)
    self._width = w
end

function AdapterMixin:SetHeight(h)
    self._height = h
end

function AdapterMixin:SetSize(w, h)
    self._width = w
    self._height = h
end

function AdapterMixin:GetName()
    return self._name or nil
end

function AdapterMixin:GetScript()
    return nil
end

function AdapterMixin:SetScript() end
function AdapterMixin:HookScript() end

function AdapterMixin:UpdateInfo()
    self.cooldownInfo = C_CooldownViewer.GetCooldownViewerCooldownInfo(self.cooldownID)
end

function AdapterMixin:GetCooldownInfo()
    return self.cooldownInfo
end

-- EllesmereUICdmHooks hooks this method on buff viewer children and queues a
-- re-layout after it runs.  The compatibility tracker calls it whenever an
-- aura-backed adapter changes active state.
function AdapterMixin:OnActiveStateChanged() end

local function CopyAdapterMethod(frame, method)
    frame[method] = AdapterMixin[method]
end

local function CreateAdapterFrame(cdID)
    local def = definitions[cdID]
    local viewer = def and _G[viewerNamesByCategory[def.category]] or UIParent
    local frame = CreateFrame("Button", nil, viewer or UIParent)
    if EUI and EUI.API and EUI.API.ApplyFrameCompat then
        EUI.API.ApplyFrameCompat(frame)
    end

    frame:SetSize(32, 32)
    frame:EnableMouse(false)
    frame.cooldownID = cdID
    frame.viewerFrame = viewer
    frame.layoutIndex = (def and def.order) or cdID
    frame._isCooldownViewerAdapter = true

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(frame)
    frame.Icon = icon
    frame._tex = icon

    local cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    if EUI and EUI.API and EUI.API.ApplyFrameCompat then
        EUI.API.ApplyFrameCompat(cooldown)
    end
    cooldown:SetAllPoints(frame)
    cooldown:EnableMouse(false)
    frame.Cooldown = cooldown
    frame._cooldown = cooldown

    -- Only the data/notification methods need to override native frame
    -- behavior.  Show/Hide/SetPoint/etc. must remain the engine methods.
    CopyAdapterMethod(frame, "GetSpellID")
    CopyAdapterMethod(frame, "GetAuraSpellID")
    CopyAdapterMethod(frame, "GetCooldownInfo")
    CopyAdapterMethod(frame, "UpdateInfo")
    CopyAdapterMethod(frame, "OnActiveStateChanged")

    frame:Hide()
    return frame
end

local function RefreshAdapterVisual(frame)
    if not frame then return end
    local cdID = frame.cooldownID
    local def = definitions[cdID]
    local avail = availability[cdID]
    local state = runtimeState[cdID]
    if not def then return end

    frame:UpdateInfo()

    local spellID = (avail and avail.activeSpellID)
        or def.iconSpellID or def.spellID or def.auraSpellID
    local iconSpellID = def.iconSpellID or spellID
    if iconSpellID and frame.Icon then
        local texture = GetSpellTexture and GetSpellTexture(iconSpellID)
        if not texture and C_Spell and C_Spell.GetSpellTexture then
            texture = C_Spell.GetSpellTexture(iconSpellID)
        end
        if texture then frame.Icon:SetTexture(texture) end
    end

    local isKnown = avail and avail.isKnown or false
    local isAura = def.trackingType == "aura"
        or def.trackingType == "cooldown_and_aura"
    -- Buff-viewer adapters represent aura presence only.  A trinket's ICD is
    -- still retained as cooldown metadata, but it must not keep the tracked-
    -- buff icon visible after the proc aura fades (or make the ICD swipe
    -- replace the buff-duration swipe).
    local isActive = isKnown and (not isAura or (state and state.auraActive))
    local wasActive = frame._adapterActive == true
    frame._adapterActive = isActive and true or false
    frame.wasSetFromAura = isAura and state and state.auraActive or false

    if isActive then frame:Show() else frame:Hide() end

    if frame.Cooldown then
        local start, duration = 0, 0
        if isAura and state and state.auraActive then
            duration = state.auraDuration or 0
            local expiration = state.auraExpiration or 0
            if duration > 0 and expiration > 0 then start = expiration - duration end
        elseif state then
            start = state.cooldownStart or 0
            duration = state.cooldownDuration or 0
        end
        CooldownFrame_Set(frame.Cooldown, start, duration,
            isActive and duration > 0 and 1 or 0)
    end

    if isAura and wasActive ~= (isActive and true or false) then
        frame:OnActiveStateChanged(isActive)
    end
end

local function GetOrCreateAdapter(cdID)
    if not adapters[cdID] then
        adapters[cdID] = CreateAdapterFrame(cdID)
    end
    RefreshAdapterVisual(adapters[cdID])
    return adapters[cdID]
end

local function IsInternalCooldownActive(state, now)
    return state
        and state.internalCooldownExpiration
        and state.internalCooldownExpiration > now
end

local function StartInternalCooldown(cdID, startTime)
    local def = definitions[cdID]
    local duration = def and def.internalCooldown or 0
    if duration <= 0 then return end

    local state = runtimeState[cdID] or {}
    local start = startTime or GetTime()
    local expiration = start + duration
    state.cooldownStart = start
    state.cooldownDuration = duration
    state.cooldownEnabled = true
    state.internalCooldownExpiration = expiration
    runtimeState[cdID] = state

    if adapters[cdID] then RefreshAdapterVisual(adapters[cdID]) end

    if C_Timer and C_Timer.After then
        local delay = expiration - GetTime()
        if delay < 0 then delay = 0 end
        C_Timer.After(delay, function()
            local current = runtimeState[cdID]
            -- A refreshed proc replaces the expiration.  Its older timer must
            -- not clear the newer internal cooldown.
            if current and current.internalCooldownExpiration == expiration then
                current.cooldownStart = 0
                current.cooldownDuration = 0
                current.cooldownEnabled = false
                current.internalCooldownExpiration = nil
                if adapters[cdID] then RefreshAdapterVisual(adapters[cdID]) end
            end
        end)
    end
end

-- Registers a logical ability definition into the system.
-- The cooldownID MUST be globally unique across ALL classes and items.
-- It acts as a stable handle for UI components (like drag-and-drop or saves).
function C_CooldownViewer.RegisterDefinition(def)
    local ok, err = ValidateDefinition(def)
    if not ok then
        print("|cffff5555[CDM Polyfill Error]|r Definition rejected: " .. err .. " (" .. tostring(def.key) .. ")")
        return
    end

    definitions[def.cooldownID] = def

    if (def.internalCooldown or 0) > 0 then
        local auraSpellID = def.auraSpellID or def.spellID
        internalCooldownIDsByAura[auraSpellID] = internalCooldownIDsByAura[auraSpellID] or {}
        table.insert(internalCooldownIDsByAura[auraSpellID], def.cooldownID)
    end

    categories[def.category] = categories[def.category] or {}
    table.insert(categories[def.category], def.cooldownID)

    -- Ensure deterministic sorting using order, then cooldownID as tie-breaker
    table.sort(categories[def.category], function(a, b)
        local dA = definitions[a]
        local dB = definitions[b]
        local oA = dA and dA.order or 999
        local oB = dB and dB.order or 999
        if oA == oB then
            return a < b
        end
        return oA < oB
    end)
end

function C_CooldownViewer.GetCooldownViewerCategorySet(category, includeUnknown)
    local results = {}
    local catIDs = categories[category] or {}

    for _, cdID in ipairs(catIDs) do
        local avail = availability[cdID]
        local isKnown = avail and avail.isKnown or false
        if includeUnknown or isKnown then
            table.insert(results, cdID)
        end
    end

    return results
end

function C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)
    local def = definitions[cooldownID]
    local avail = availability[cooldownID]
    local state = runtimeState[cooldownID]

    if not def then return nil end

    local activeSpellID = avail and avail.activeSpellID or def.spellID

    return {
        cooldownID = cooldownID,
        spellID = activeSpellID,
        overrideSpellID = def.overrideSpellID,
        linkedSpellIDs = def.linkedSpellIDs,
        iconSpellID = def.iconSpellID,
        auraSpellID = (avail and avail.activeAuraSpellID) or def.auraSpellID,
        hasAura = def.hasAura,
        selfAura = def.selfAura,

        -- Runtime state fields expected by EllesmereUI adapters
        cooldownStart = state and state.cooldownStart or 0,
        cooldownDuration = state and state.cooldownDuration or 0,
        cooldownEnabled = state and state.cooldownEnabled or false,
        auraActive = state and state.auraActive or false,
        auraDuration = state and state.auraDuration or 0,
        auraExpiration = state and state.auraExpiration or 0,
        auraStacks = state and state.auraStacks or 0,
        internalCooldownDuration = def.internalCooldown,
    }
end

-- Aura Caching
local function UpdateAuraCache()
    wipe(cachedPlayerAuras)
    for i = 1, 40 do
        local name, rank, icon, count, debuffType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellID = UnitAura("player", i, "HELPFUL")
        if not name then break end
        if spellID then
            cachedPlayerAuras[spellID] = { duration = duration or 0, expirationTime = expirationTime or 0, count = count or 0 }
        end
    end
    for i = 1, 40 do
        local name, rank, icon, count, debuffType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellID = UnitAura("player", i, "HARMFUL")
        if not name then break end
        if spellID then
            cachedPlayerAuras[spellID] = { duration = duration or 0, expirationTime = expirationTime or 0, count = count or 0 }
        end
    end
    cachedAuraTime = GetTime()
end

local function GetCachedAura(spellID)
    if not spellID then return nil end
    -- Fallback safety if accessed outside of normal flow
    if GetTime() > cachedAuraTime + 0.5 then
        UpdateAuraCache()
    end
    return cachedPlayerAuras[spellID]
end

-- Refresh logic
local function ReevaluateAvailability()
    local _, playerClass = UnitClass("player")

    for cdID, def in pairs(definitions) do
        local allowed = true
        if def.class and def.class ~= playerClass then allowed = false end

        -- Resolvers support
        if allowed and def.resolvers and def.resolvers.requirements then
            allowed = def.resolvers.requirements(def)
        end

        local activeSpellID = nil
        local isKnown = false

        if allowed then
            if def.resolvers and def.resolvers.resolveSpellID then
                local resolved = def.resolvers.resolveSpellID(def)
                if resolved then
                    isKnown = true
                    activeSpellID = resolved
                end
            elseif def.spellIDs then
                for i = #def.spellIDs, 1, -1 do
                    local sID = def.spellIDs[i]
                    if IsSpellKnown and IsSpellKnown(sID) then
                        isKnown = true
                        activeSpellID = sID
                        break
                    end
                end
            elseif def.spellID then
                if IsSpellKnown and IsSpellKnown(def.spellID) then
                    isKnown = true
                    activeSpellID = def.spellID
                end
            end
        end

        availability[cdID] = {
            isKnown = isKnown,
            activeSpellID = activeSpellID or def.spellID,
            activeAuraSpellID = def.auraSpellID or activeSpellID or def.spellID
        }
    end
end

local function ReevaluateState()
    for cdID, def in pairs(definitions) do
        local avail = availability[cdID]
        local state = runtimeState[cdID] or {}

        if avail and avail.isKnown then
            local spellID = avail.activeSpellID
            if (def.trackingType == "cooldown" or def.trackingType == "cooldown_and_aura")
                and not def.internalCooldown then
                if spellID then
                    local start, duration, enabled = GetSpellCooldown(spellID)
                    state.cooldownStart = start or 0
                    state.cooldownDuration = duration or 0
                    state.cooldownEnabled = (enabled == 1)
                end
            end

            if def.internalCooldown and not IsInternalCooldownActive(state, GetTime()) then
                state.cooldownStart = 0
                state.cooldownDuration = 0
                state.cooldownEnabled = false
                state.internalCooldownExpiration = nil
            end

            if def.trackingType == "aura" or def.trackingType == "cooldown_and_aura" then
                local auraID = avail.activeAuraSpellID
                if auraID then
                    local wasAuraActive = state.auraActive == true
                    local aura = GetCachedAura(auraID)
                    if aura then
                        state.auraActive = true
                        state.auraDuration = aura.duration
                        state.auraExpiration = aura.expirationTime
                        state.auraStacks = aura.count
                        -- CLEU normally starts ICDs at the exact proc event.
                        -- This fallback recovers a proc already active at login
                        -- or after an event gap, using the aura's start time.
                        if def.internalCooldown and def.internalCooldown > 0
                            and not wasAuraActive
                            and not IsInternalCooldownActive(state, GetTime()) then
                            local auraStart = GetTime()
                            if aura.duration > 0 and aura.expirationTime > 0 then
                                auraStart = aura.expirationTime - aura.duration
                            end
                            StartInternalCooldown(cdID, auraStart)
                        end
                    else
                        state.auraActive = false
                        state.auraDuration = 0
                        state.auraExpiration = 0
                        state.auraStacks = 0
                    end
                end
            end
        else
            -- Unknown or inactive
            state.cooldownStart = 0
            state.cooldownDuration = 0
            state.cooldownEnabled = false
            state.auraActive = false
            state.internalCooldownExpiration = nil
        end

        runtimeState[cdID] = state

        -- Update persistent adapter
        if adapters[cdID] then
            RefreshAdapterVisual(adapters[cdID])
        end
    end
end

-- The parent framework's PLAYER_LOGIN frame is created before this child
-- addon loads.  Once the compatibility layer moved into the child addon, that
-- framework frame could run the CDM's OnEnable before this tracker's own
-- PLAYER_LOGIN callback, leaving the first bar build with an empty availability
-- map.  Expose an explicit synchronous refresh so CDM initialization and
-- equipment rebuilds never depend on event-frame dispatch order.
function ns.RefreshCooldownViewerCompatibility()
    UpdateAuraCache()
    ReevaluateAvailability()
    ReevaluateState()
end

-- Event Handling
tracker:RegisterEvent("PLAYER_LOGIN")
tracker:RegisterEvent("SPELLS_CHANGED")
tracker:RegisterEvent("PLAYER_TALENT_UPDATE")
tracker:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
tracker:RegisterEvent("PLAYER_ENTERING_WORLD")
tracker:RegisterEvent("UNIT_AURA")
tracker:RegisterEvent("SPELL_UPDATE_COOLDOWN")
tracker:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

tracker:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" or event == "SPELLS_CHANGED" or event == "PLAYER_TALENT_UPDATE" or event == "PLAYER_EQUIPMENT_CHANGED" then
        ns.RefreshCooldownViewerCompatibility()
    elseif event == "PLAYER_ENTERING_WORLD" then
        ns.RefreshCooldownViewerCompatibility()
    elseif event == "UNIT_AURA" then
        local unit = ...
        if unit == "player" then
            UpdateAuraCache()
            ReevaluateState()
        end
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        ReevaluateState()
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local _, subEvent, _, _, _, destinationGUID, _, _, spellID = ...
        if destinationGUID == UnitGUID("player")
            and (subEvent == "SPELL_AURA_APPLIED" or subEvent == "SPELL_AURA_REFRESH") then
            local cooldownIDs = internalCooldownIDsByAura[spellID]
            if cooldownIDs then
                local now = GetTime()
                for _, cooldownID in ipairs(cooldownIDs) do
                    local avail = availability[cooldownID]
                    if avail and avail.isKnown then
                        StartInternalCooldown(cooldownID, now)
                    end
                end
            end
        end
    end
end)

-- Global Viewer Pools (Mocking Retail UI Frames)
local function CreateMockPool(categoryID)
    return {
        EnumerateActive = function()
            -- A Retail itemFramePool contains frames for displayed/known
            -- abilities, not every definition for every class.  Unknown entries
            -- remain available through GetCooldownViewerCategorySet(..., true)
            -- for pickers and reconciliation.
            local entries = C_CooldownViewer.GetCooldownViewerCategorySet(categoryID, false)
            local i = 0
            return function()
                i = i + 1
                if entries[i] then
                    return GetOrCreateAdapter(entries[i])
                end
                return nil
            end
        end,
        Acquire = function() end,
        Release = function() end,
        ReleaseAll = function() end,
    }
end

local function InitMockViewer(globalName, categoryID)
    local frame = _G[globalName]
    if not frame then
        if CreateFrame then
            frame = CreateFrame("Frame", globalName, UIParent)
        else
            frame = {}
            _G[globalName] = frame
        end
    end
    if not frame.SetAlpha then frame.SetAlpha = function(self, a) self._alpha = a end end
    if not frame.GetAlpha then frame.GetAlpha = function(self) return self._alpha or 1 end end
    if not frame.ClearAllPoints then frame.ClearAllPoints = function() end end
    if not frame.SetPoint then frame.SetPoint = function() end end
    if not frame.GetScale then frame.GetScale = function() return 1 end end
    if not frame.Layout then frame.Layout = function() end end
    frame.itemFramePool = CreateMockPool(categoryID)
    return frame
end

InitMockViewer("EssentialCooldownViewer", 1)
InitMockViewer("UtilityCooldownViewer", 2)
InitMockViewer("BuffIconCooldownViewer", 3)
InitMockViewer("BuffBarCooldownViewer", 4)
