if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUICdmHooks.lua  (v5 -- Mixin Hook Architecture)
--
--  CORE PRINCIPLE: Blizzard manages all cooldown/buff state.
--  We ONLY restyle (borders, shapes, fonts) and reposition (into our bars).
--
--  Hook strategy:
--    - OnCooldownIDSet on all 4 Blizzard CDM mixins -> QueueReanchor
--    - Pool Acquire on all viewers -> QueueReanchor
--    - Viewer Layout hooks -> QueueReanchor (catches frame removals)
--
--  Taint prevention:
--    - Never SetParent/SetScale/Hide/Show on Blizzard frames
--    - Never move Blizzard frames offscreen
--    - Never write custom keys to Blizzard frame tables
--    - All per-frame data in external weak-keyed tables
--    - Unclaimed frames: SetAlpha(0). Claimed: SetAlpha(1).
-------------------------------------------------------------------------------
local _, ns = ...

local cdmBarIcons         = ns.cdmBarIcons
local MAIN_BAR_KEYS       = ns.MAIN_BAR_KEYS

local floor   = math.floor
local GetTime = GetTime
local _, _playerClass = UnitClass("player")
local _isDruid = (_playerClass == "DRUID")

ns._spellOrderDirty = true  -- start dirty so first reanchor builds caches

-- Per-frame decoration state (weak-keyed)
local hookFrameData = setmetatable({}, { __mode = "k" })
ns._hookFrameData = hookFrameData

-- Glow at Stacks (per-spell): REPLACES the Buff Glow for icons with a stack
-- comparison, using the spell's effective Buff Glow style (resolved in
-- RefreshCDMIconAppearance).
-- Stack counts read SECRET in restricted combat, so the comparison must never
-- happen in Lua there. One-unit StatusBar windows perform lower and upper
-- bounds C-side; equality intersects one of each. Fixed-size
-- CLAMPTOBLACKADDITIVE masks ride the gates' fill edges and bound every glow
-- texture. Masks keep rendering where SetClipsChildren goes dark on
-- secret-derived rects. Plain counts skip the render gate and start/stop the
-- glow directly. Zero cost unless a spell enables the toggle: no frames, no
-- reads.
do
    local function StackGlowSize(icon)
        local width, height = icon:GetWidth(), icon:GetHeight()
        if not width or width < 5 then width = 36 end
        if not height or height < 5 then height = width end
        return width, height
    end

    -- The gate oversizes the icon by pad on every side and the mask matches the
    -- gate exactly, so a FULL fill puts the open mask over the whole glow --
    -- flipbook/pixel textures overhang the icon edges.
    local function SizeStackGlowMask(st, width, height)
        local w, h = width + st.pad * 2, height + st.pad * 2
        st.mask:SetSize(w, h)
        if st.mask2 then st.mask2:SetSize(w, h) end
    end

    local function NewStackGlowGate(icon, pad)
        local gate = CreateFrame("StatusBar", nil, icon)
        gate:SetPoint("TOPLEFT", icon, "TOPLEFT", -pad, pad)
        gate:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", pad, -pad)
        gate:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        local fill = gate:GetStatusBarTexture()
        if fill then fill:SetAlpha(0) end
        gate:EnableMouse(false)
        local mask = gate:CreateMaskTexture()
        mask:SetTexture("Interface\\Buttons\\WHITE8x8",
            "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "NEAREST")
        return gate, mask, fill
    end

    local function StackGlowMatches(value, operator, threshold)
        if operator == "lt" then return value < threshold end
        if operator == "lte" then return value <= threshold end
        if operator == "eq" then return value == threshold end
        if operator == "gt" then return value > threshold end
        return value >= threshold
    end

    -- LIVE-FIRST: the item's auraDataCached is (re)written on aura
    -- ASSIGNMENT, so an update-only stack change can leave it holding the
    -- gain-time count -- a threshold crossing would then wait for the next
    -- add/remove to rewrite the cache. The instance-id fetch is authoritative
    -- while its inputs read plain (dirty ticks only, a few icons: cheap).
    -- Under secrecy the iid reads secret and the id-keyed APIs hard-error,
    -- so the cached -- possibly secret -- applications value stays the
    -- gate's source there. Secret probes come FIRST everywhere: even a
    -- boolean or `~= nil` test on a secret is a hard error.
    -- Returns a plain number, a SECRET number, or nil (unknown).
    local function ReadBuffApplications(frame)
        local iid = frame.auraInstanceID
        if not (issecretvalue and issecretvalue(iid)) and iid then
            local unit = frame.auraDataUnit
            if not (issecretvalue and issecretvalue(unit)) and unit then
                local ok, data = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, iid)
                if ok and data then
                    local a = data.applications
                    if (issecretvalue and issecretvalue(a)) or a ~= nil then
                        return a
                    end
                end
            end
        end
        local ad = frame.auraDataCached
        local apps = ad and ad.applications
        if (issecretvalue and issecretvalue(apps)) or apps ~= nil then
            return apps
        end
        return nil
    end
    -- Exported for the aura active-cache below (Bar Glows stack threshold):
    -- same secret-safe applications read, off whatever pool frame is active.
    ns._ReadBuffApplications = ReadBuffApplications

    local function StartStackGlow(st, width, height)
        -- Both gate masks go over as data: the combat replay of Show Glows Only
        -- in Combat restarts from the recorded opts, so a mask bound out here
        -- would be missing on every texture that replay creates fresh.
        ns.StartNativeGlow(st.glow, st.style, st.r, st.g, st.b, {
            owner = st.icon, width = width, height = height,
            N = st.lines, th = st.thickness, period = st.speed,
            bg = st.background and { r = st.bgR, g = st.bgG, b = st.bgB } or nil,
            maskWith = st.mask,
            maskWith2 = st.mask2,
        })
        st.width, st.height = width, height
        st.started = true
    end

    local function StopStackGlow(st)
        if st.started then
            ns.StopNativeGlow(st.glow)
            st.started = nil
        end
        -- Unconditional: the wrapper is created at alpha 1, so anything an
        -- engine left on it would show through a gate that never opened.
        if st.glow then st.glow:SetAlpha(0) end
        if st.gate then st.gate:SetValue(st.closeValue or 0) end
        if st.gate2 then st.gate2:SetValue(st.closeValue2 or 0) end
    end

    local function StackGlowOnHide(icon)
        local fd = hookFrameData[icon]
        local st = fd and fd.stackGlow
        if st then StopStackGlow(st) end
    end

    -- (Re)configure or retire an icon's threshold controller. Called from
    -- RefreshCDMIconAppearance with everything pre-resolved; called with only
    -- the icon to tear down (toggle off, frame pooled onto a non-buff spell).
    function ns.StackGlow_Configure(icon, threshold, operator, style, r, g, b, settings)
        local fd = icon and hookFrameData[icon]
        if not fd then return end
        local st = fd.stackGlow
        threshold, style = tonumber(threshold), tonumber(style)
        if operator ~= "lt" and operator ~= "lte" and operator ~= "eq"
           and operator ~= "gte" and operator ~= "gt" then
            operator = "gte"
        end
        if not (threshold and threshold >= 1 and style and style >= 1) then
            if st and st.threshold then
                st.threshold = nil
                StopStackGlow(st)
                ns._btDirty = true
                if ns.ArmBuffTicker then ns.ArmBuffTicker() end
            end
            return
        end
        threshold = math.floor(threshold)
        local lines = (settings and settings.buffGlowLines) or 8
        local thickness = (settings and settings.buffGlowThickness) or 2
        local speed = (settings and settings.buffGlowSpeed) or 4
        local background = (settings and settings.buffGlowBackground) or false
        local bgR = background and (settings.buffGlowBackgroundR or 0) or nil
        local bgG = background and (settings.buffGlowBackgroundG or 0) or nil
        local bgB = background and (settings.buffGlowBackgroundB or 0) or nil

        if not st then
            st = { icon = icon }
            fd.stackGlow = st
            -- The gate oversizes the icon so a FULL fill (and therefore the
            -- open mask) covers the glow textures' overhang past the icon
            -- edges (flipbook/pixel padding); proportional so big icons keep
            -- their fringe too.
            local pad = math.ceil(math.max(StackGlowSize(icon)) * 0.4)
            if pad < 12 then pad = 12 end
            st.pad = pad
            st.gate, st.mask, st.fill = NewStackGlowGate(icon, pad)

            -- The mask rides the (alpha-0) fill's edge at a FIXED
            -- gate-sized rect instead of shadowing the fill rect: at value =
            -- min the fill is zero-wide, and a zero-area mask samples
            -- undefined -- a partly passing mask reads as a faint glow below
            -- the comparison. Lower bounds park it left and open at max;
            -- upper bounds open at min and park it right. Equality intersects
            -- one of each. NEAREST avoids a leaking edge texel.
            SizeStackGlowMask(st, StackGlowSize(icon))

            st.glow = CreateFrame("Frame", nil, icon)
            st.glow:SetAllPoints(icon)
            st.glow:EnableMouse(false)
            icon:HookScript("OnHide", StackGlowOnHide)
        end

        local changed = st.threshold ~= threshold or st.operator ~= operator or st.style ~= style
            or st.r ~= r or st.g ~= g or st.b ~= b or st.lines ~= lines
            or st.thickness ~= thickness or st.speed ~= speed
            or st.background ~= background or st.bgR ~= bgR
            or st.bgG ~= bgG or st.bgB ~= bgB
        st.threshold, st.operator, st.style = threshold, operator, style
        st.r, st.g, st.b = r, g, b
        st.lines, st.thickness, st.speed = lines, thickness, speed
        st.background, st.bgR, st.bgG, st.bgB = background, bgR, bgG, bgB
        if changed then
            StopStackGlow(st)
            local upper = operator == "lt" or operator == "lte"
            local edge = (operator == "gt" or operator == "lte")
                and threshold + 1 or threshold
            st.gate:SetMinMaxValues(edge - 1, edge)
            st.mask:ClearAllPoints()
            st.mask:SetPoint(upper and "LEFT" or "RIGHT",
                st.fill or st.gate, "RIGHT", 0, 0)
            st.closeValue = upper and edge or edge - 1
            st.openValue = upper and edge - 1 or edge

            if operator == "eq" and not st.gate2 then
                st.gate2, st.mask2, st.fill2 = NewStackGlowGate(icon, st.pad)
                SizeStackGlowMask(st, StackGlowSize(icon))
            end
            if st.gate2 then
                local equality = operator == "eq"
                st.gate2:SetMinMaxValues(equality and threshold or 0,
                    equality and threshold + 1 or 1)
                st.mask2:ClearAllPoints()
                st.mask2:SetPoint(equality and "LEFT" or "RIGHT",
                    st.fill2 or st.gate2, "RIGHT", 0, 0)
                st.closeValue2 = equality and threshold + 1 or 0
            end
            StopStackGlow(st)
        end
        ns._btDirty = true
        if ns.ArmBuffTicker then ns.ArmBuffTicker() end
    end

    -- Buff-tick feed for thresholded icons (the normal buff glow is suppressed
    -- for them). Plain counts decide in Lua; secret counts go straight to the
    -- gate and the engine's clamp + the mask decide what renders.
    function ns.StackGlow_Feed(icon, active)
        local fd = icon and hookFrameData[icon]
        local st = fd and fd.stackGlow
        if not (st and st.threshold) then return end
        if not active then
            StopStackGlow(st)
            return
        end
        local applications = ReadBuffApplications(icon)
        local secret = issecretvalue and issecretvalue(applications)
        if not secret then
            -- Unknown count on an active buff fails OPEN; known counts use the
            -- selected comparison without touching the secret-value path.
            if applications == nil then
                applications = st.openValue
            elseif not StackGlowMatches(applications, st.operator, st.threshold) then
                StopStackGlow(st)
                return
            end
        end
        st.gate:SetValue(applications)
        if st.gate2 then
            st.gate2:SetValue(st.operator == "eq" and applications or 1)
        end
        st.glow:SetFrameLevel(icon:GetFrameLevel() + 16)
        local width, height = StackGlowSize(icon)
        if not st.started or math.abs(width - (st.width or 0)) > 0.01
           or math.abs(height - (st.height or 0)) > 0.01 then
            -- Size changed (or first start): re-derive the gate's overhang
            -- pad from the LIVE size, so the open mask keeps covering the
            -- glow fringe -- the creation-time pad may have come from the
            -- pre-layout fallback size, and icons resize with settings.
            local pad = math.ceil(math.max(width, height) * 0.4)
            if pad < 12 then pad = 12 end
            if pad ~= st.pad then
                st.pad = pad
                st.gate:ClearAllPoints()
                st.gate:SetPoint("TOPLEFT", icon, "TOPLEFT", -pad, pad)
                st.gate:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", pad, -pad)
                if st.gate2 then
                    st.gate2:ClearAllPoints()
                    st.gate2:SetPoint("TOPLEFT", icon, "TOPLEFT", -pad, pad)
                    st.gate2:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", pad, -pad)
                end
            end
            SizeStackGlowMask(st, width, height)
            StartStackGlow(st, width, height)
        end
    end
end

-- Force active buff glows to re-apply on the next buff tick (<=0.1s): the tick
-- only (re)starts a glow when fd.buffGlowActive is false, so live option edits
-- (color, pixel Lines/Thickness/Speed) never reach an already-glowing icon.
-- Used by the custom aura preview while CDM Bars options are open.
function ns.RefreshBuffGlows()
    for _, icons in pairs(cdmBarIcons) do
        for fi = 1, #icons do
            local frame = icons[fi]
            local fd = frame and hookFrameData[frame]
            if fd and fd.buffGlowActive then
                fd.buffGlowActive = false
            end
        end
    end
end

-- Take a pandemic glow down when its icon hides. The buff tick only visits SHOWN
-- frames, so a glow lit at the moment the icon hides -- which is how every
-- pandemic ends, the aura runs out and Blizzard hides the buff icon -- can never
-- reach the tick's stop branch. The textures keep animating on the hidden overlay
-- and come back up WITH the icon on the buff's next application, flashing a
-- pandemic glow over a freshly cast aura until the next tick takes it down.
-- Blizzard's pandemic flag is dropped with it: ShowPandemicStateFrame is the only
-- thing that sets it and it stops being called once the item goes inactive, so a
-- stale true would just re-light the glow on the next tick. Hooked lazily from the
-- overlay build below, so a bar with no pandemic glow never pays for it.
--
-- Clearing the flag is not enough on its own when the aura ends EARLY (dispelled,
-- target lost, pool release) instead of running out. Blizzard computes the
-- pandemic window once, on the aura landing, and never clears it on the way out:
-- CheckSetPandemicAlertTriggerTime returns before touching pandemicStartTime /
-- pandemicEndTime once the aura is inactive. The item is still registered for the
-- viewer's OnUpdate and the viewer never stops running it (visibility of the ITEM
-- is not consulted), so a window whose aura is already gone keeps satisfying
-- IsInPandemicTime and re-sets the flag on the hidden icon a frame later. Re-apply
-- inside that leftover window and the tick lights a full pandemic glow over a
-- fresh aura, held until the DEAD aura's end time passes.
--
-- So the flag is also marked unusable from here until the item computes a new
-- window (ns._PandemicWindowSet). Only when the aura is really gone -- Blizzard
-- clears auraInstanceID before hiding the icon, while a bar merely being hidden
-- leaves it set -- so a visibility toggle mid-pandemic keeps its glow. The bias is
-- deliberate: a suppressed glow costs a tick, a wrong one is what was reported.
function ns._PandemicIconHide(self)
    local fd = hookFrameData[self]
    if fd then
        if fd.pandemicGlowActive then
            if fd.pandemicOverlay then ns.StopNativeGlow(fd.pandemicOverlay) end
            fd.pandemicGlowActive = false
        end
        -- auraInstanceID can be SECRET in instanced combat; comparing a
        -- secret against nil yields a secret boolean the `if` would error
        -- testing. A secret ID means the aura state is unknowable: take the
        -- conservative path (not stale), same bias as the visibility toggle.
        local aid = self.auraInstanceID
        if not (_G.issecretvalue and _G.issecretvalue(aid)) and aid == nil then
            fd._panStale = true
        end
    end
    if ns._pandemicState then ns._pandemicState[self] = nil end
end

-- Blizzard recomputed the pandemic window, so the flag describes the aura that is
-- on the icon NOW. Runs on every application that carries time over, well before
-- the window itself opens.
function ns._PandemicWindowSet(self)
    local fd = hookFrameData[self]
    if fd then fd._panStale = nil end
end

local function FD(f)
    local d = hookFrameData[f]
    if not d then d = {}; hookFrameData[f] = d end
    return d
end
ns.FD = FD

-------------------------------------------------------------------------------
--  Resource verification for the CD Ready Glow.
--
--  IsSpellUsable() can briefly report a resource-gated spell usable right after
--  login/reload, before power data settles. HasEnoughResources re-derives from
--  live UnitPower()/UnitPowerMax(). Callers AND it with IsSpellUsable so only
--  the resource portion gets a second opinion; CD/form/lockout gating is
--  unaffected. Declared early (Lua locals are visible only after declaration).
--  GetSpellPowerCost() allocates per call and cost changes only on talent/spec
--  swap: cache it, invalidate on PLAYER_SPECIALIZATION_CHANGED + PEW, so the
--  hot path (every UNIT_POWER_UPDATE) is a table lookup.
-------------------------------------------------------------------------------
local _spellPowerCostCache = {}

local function InvalidateSpellPowerCostCache()
    wipe(_spellPowerCostCache)
end
ns.InvalidateSpellPowerCostCache = InvalidateSpellPowerCostCache

do
    local _pccInvalidateFrame = ns.TakeShell()
    _pccInvalidateFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    _pccInvalidateFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    _pccInvalidateFrame:SetScript("OnEvent", InvalidateSpellPowerCostCache)
end

local function HasEnoughResources(spellID)
    if not (C_Spell and C_Spell.GetSpellPowerCost) then return true end
    -- nil = not yet checked, false = no cost (always enough), table = cost list.
    local cached = _spellPowerCostCache[spellID]
    if cached == nil then
        local costs = C_Spell.GetSpellPowerCost(spellID)
        if not costs or #costs == 0 then
            _spellPowerCostCache[spellID] = false  -- no resource gate
            return true
        end
        _spellPowerCostCache[spellID] = costs
        cached = costs
    elseif cached == false then
        return true  -- no resource gate, cached
    end
    for _, c in ipairs(cached) do
        local powerType = c.type
        if powerType then
            local cost = c.cost or 0
            if c.costPercent and c.costPercent > 0 then
                -- Power can be SECRET in tainted combat: uncomparable, so default
                -- to castable rather than throw.
                local maxP = UnitPowerMax("player", powerType)
                if issecretvalue and issecretvalue(maxP) then return true end
                cost = math.max(cost, (c.costPercent / 100) * maxP)
            end
            if cost > 0 then
                local cur = UnitPower("player", powerType)
                if issecretvalue and issecretvalue(cur) then return true end
                if cur < cost then return false end
            end
        end
    end
    return true
end
ns.HasEnoughResources = HasEnoughResources

-- True once real UNIT_POWER_FREQUENT data arrives after PEW: at login
-- IsSpellUsable/GetSpellPowerCost can read stale/empty (0 cost = "enough"),
-- so glow decisions stay untrusted until then; listener re-fires QueueCDGlowUpdate.
ns._cdGlowPowerConfirmed = true

-------------------------------------------------------------------------------
--  Constants
-------------------------------------------------------------------------------
local VIEWER_NAMES = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffIconCooldownViewer",
    "BuffBarCooldownViewer",
}

-- The 4 viewer frames are created once per session and never replaced: cache
-- them instead of repeating _G lookups (10Hz aura ticker + CD Ready Glow update
-- both loop all 4 often).
local _viewerFrameCache = {}
local function GetViewerFrame(vi)
    local f = _viewerFrameCache[vi]
    if not f then
        f = _G[VIEWER_NAMES[vi]]
        if f then _viewerFrameCache[vi] = f end
    end
    return f
end

local VIEWER_TO_BAR = {
    EssentialCooldownViewer = "cooldowns",
    UtilityCooldownViewer   = "utility",
    BuffIconCooldownViewer  = "buffs",
}

-- Master guard: suspend ALL hook logic while Blizzard CDM settings is open.
-- Any interaction with frames during settings editing causes taint.
local function IsCDMSettingsOpen()
    return CooldownViewerSettings and CooldownViewerSettings:IsShown()
end

-- Main-chunk locals the EUI_CDM_Hook*.lua files re-import by name.
ns._NewInternals("_hookInternals", {
    _isDruid = _isDruid, FD = FD, GetViewerFrame = GetViewerFrame,
    hookFrameData = hookFrameData, IsCDMSettingsOpen = IsCDMSettingsOpen,
    VIEWER_NAMES = VIEWER_NAMES, VIEWER_TO_BAR = VIEWER_TO_BAR,
})
