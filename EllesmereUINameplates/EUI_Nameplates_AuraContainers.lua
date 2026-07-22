-- EUI_Nameplates_AuraContainers.lua
-- 12.1 aura containers for nameplates. Three engine-driven groups per
-- plate (player debuffs, enemy important buffs, crowd control), rendered
-- through a PRE-CREATED pool of container bundles: plates spawn lazily in
-- combat, but containers can only be created out of combat, so bundles are
-- built at login and attached/detached as plates come and go.
--
-- Importance: Blizzard's per-plate debuffList/buffList are taint-locked in
-- 12.1 (unreadable), but their build rule (Blizzard_NamePlateAuras) is
-- fetch HARMFUL|INCLUDE_NAME_PLATE_ONLY then keep nameplateShowPersonal
-- auras -- reproduced on the debuff group as the same fetch tokens plus a
-- { nameplateShowPersonal = true } candidate filter. "Show All Debuffs"
-- clears the candidate filter live and switches the sort to Default.
--
-- V1 deferred (documented): purge/dispel glow on buffs, pandemic glow
-- (engine has no duration-driven texture alpha -- wishlist), cast-lockout
-- offset interplay with the CC row (lockout renders independently), target
-- arrows relative to aura rows, per-slot Raise Strata on containers.

local _, ns = ...
local EllesmereUI = _G.EllesmereUI

-- 12.1 ONLY: on a 12.0 client this whole file is inert -- the ownership
-- flag below never gets set and the legacy nameplate aura renderer keeps
-- running untouched.
if not (EllesmereUI and EllesmereUI.IS_121) then return end

ns.NPC_OwnsAuras = true

local AK
local POOL_SIZE = 40

local pool = {}      -- free bundles (stack)
local active = {}    -- [plate] = bundle
local KINDS = { "debuffs", "buffs", "cc" }

-- Layout generation: bumped whenever the geometry fingerprint changes.
-- Containers stamp the generation (plus the slot they were laid out for)
-- when their engine layout config is driven; a matching stamp means the
-- bundle-local layout state is already correct, so plate attach/re-anchor
-- passes skip the engine layout setters (each one is a dirty mark that
-- costs real engine work) and only re-run the plate-dependent SetPoint.
local geoGen = 1
local lastTargetPlate

local FP_JOIN = {}
local function FP(...)
    local n = select("#", ...)
    for i = 1, n do
        local v = select(i, ...)
        if type(v) == "number" then
            FP_JOIN[i] = string.format("%.2f", v)
        else
            FP_JOIN[i] = tostring(v)
        end
    end
    for i = n + 1, #FP_JOIN do FP_JOIN[i] = nil end
    return table.concat(FP_JOIN, "|")
end

local function Prof()
    local p = ns.NP_GetProfile and ns.NP_GetProfile()
    return p or (ns.NP_GetDefaults and ns.NP_GetDefaults()) or {}
end

local function PVal(key)
    local p = ns.NP_GetProfile and ns.NP_GetProfile()
    if p and p[key] ~= nil then return p[key] end
    local d = ns.NP_GetDefaults and ns.NP_GetDefaults()
    return d and d[key]
end

------------------------------------------------------------------------------
-- Styles. Duration text = our formatter-driven FontString styled like the
-- legacy cooldown countdown text; stacks mirror the legacy count strings.
-- Cropped icons are shorter than wide (legacy crop system): height and
-- vertical texcoords derive from the shared crop math.
------------------------------------------------------------------------------

local function CropCoords(cropped)
    if cropped then
        -- Horizontal zoom 0.08; vertical trimmed so 80%-height icons never
        -- squish the artwork (mirrors ns.SetAuraIconCrop).
        return { 0.08, 0.92, 0.164, 0.836 }
    end
    return { 0.08, 0.92, 0.08, 0.92 }
end

local function NPSize(kind)
    if kind == "debuffs" then return (ns.GetDebuffIconSize and ns.GetDebuffIconSize()) or 26 end
    if kind == "buffs" then return (ns.GetBuffIconSize and ns.GetBuffIconSize()) or 24 end
    return (ns.GetCCIconSize and ns.GetCCIconSize()) or 24
end

local function NPHeight(kind, size)
    local cropped = ns.GetAuraCrop and ns.GetAuraCrop(kind == "cc" and "ccs" or kind)
    if cropped and ns.GetAuraCropHeight then
        return ns.GetAuraCropHeight(cropped, size), true
    end
    return size, false
end

-- Legacy settings resolution for aura text -- the EXACT fallback chains
-- ApplyAppearance uses (per-kind key -> shared legacy aura* key -> defaults),
-- so 12.0 and 12.1 render identical text for any profile state.
-- kindKey = "debuff" | "buff" | "cc".
local function ProfOnly(key)
    local prof = ns.NP_GetProfile and ns.NP_GetProfile()
    return prof and prof[key]
end
local function Dflt(key)
    local d = ns.NP_GetDefaults and ns.NP_GetDefaults()
    return d and d[key]
end
local function AuraDurCfg(kindKey)
    return {
        size = ProfOnly(kindKey .. "DurationTextSize") or ProfOnly("auraDurationTextSize")
            or Dflt("auraDurationTextSize") or 11,
        x = ProfOnly(kindKey .. "DurationTextX") or ProfOnly("auraDurationTextX")
            or Dflt("auraDurationTextX") or 0,
        y = ProfOnly(kindKey .. "DurationTextY") or ProfOnly("auraDurationTextY")
            or Dflt("auraDurationTextY") or 0,
        color = ProfOnly(kindKey .. "DurationTextColor") or ProfOnly("auraDurationTextColor")
            or Dflt("auraDurationTextColor") or { r = 1, g = 1, b = 1 },
        pos = ProfOnly(kindKey .. "TimerPosition") or ProfOnly("auraTextPosition")
            or Dflt(kindKey .. "TimerPosition") or "topleft",
    }
end
local function StackCfg()
    return {
        size = PVal("auraStackTextSize") or 11,
        color = PVal("auraStackTextColor") or { r = 1, g = 1, b = 1 },
        x = PVal("auraStackTextX") or 0,
        y = PVal("auraStackTextY") or 0,
        pos = PVal("auraStackTextPosition") or "bottomright",
    }
end

-- Position -> corner/nudge/justify, mirroring the legacy ApplyTimerPosition /
-- ApplyStackPosition mapping exactly (same baked edge nudges, user X/Y on top).
local TEXT_POS = {
    center      = { point = "CENTER",      nx = 0,  ny = 0,  justify = "CENTER" },
    topright    = { point = "TOPRIGHT",    nx = 3,  ny = 4,  justify = "RIGHT" },
    bottomleft  = { point = "BOTTOMLEFT",  nx = -3, ny = -4, justify = "LEFT" },
    bottomright = { point = "BOTTOMRIGHT", nx = 3,  ny = -4, justify = "RIGHT" },
    topleft     = { point = "TOPLEFT",     nx = -3, ny = 4,  justify = "LEFT" },
}

-- Text pass shared by the three styles; anchors/sizes carried per style.
local function ApplyNPText(button, d, style)
    if button.SetMouseMotionEnabled then
        local motion = not style.noTooltips
        if d.npMotion ~= motion then
            d.npMotion = motion
            button:SetMouseMotionEnabled(motion)
        end
    end
    local path = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("nameplates")) or "Fonts\\FRIZQT__.TTF"
    if d.duration then
        local fontKey = path .. "|" .. (style.durSize or 11)
        if d.npDurFont ~= fontKey then
            d.npDurFont = fontKey
            EllesmereUI.ApplyIconTextFont(d.duration, path, style.durSize or 11, "nameplates")
        end
        local c = style.durColor
        d.duration:SetTextColor(c and c.r or 1, c and c.g or 1, c and c.b or 1)
        local m = TEXT_POS[style.durPos] or TEXT_POS.topleft
        -- Anchor change-guarded (stamp AFTER the calls): SetPoint with the
        -- button as the relative frame is policed by the 12.1 button access
        -- restriction while auras are secret; unchanged anchors must make
        -- zero button-involving calls so restyles stay live in-instance.
        local aKey = m.point .. "|" .. (m.nx + (style.durOffX or 0)) .. "|" .. (m.ny + (style.durOffY or 0))
        if d.npDurAnchor ~= aKey then
            d.duration:ClearAllPoints()
            d.duration:SetPoint(m.point, button, m.point,
                m.nx + (style.durOffX or 0), m.ny + (style.durOffY or 0))
            d.npDurAnchor = aKey
        end
        d.duration:SetJustifyH(m.justify)
        d.duration:SetShown(not style.hideDurationText)
    end
    if d.stack then
        d.stack:SetShown(style.showStacks ~= false)
        local fontKey = path .. "|" .. (style.stackSize or 11)
        if d.npStackFont ~= fontKey then
            d.npStackFont = fontKey
            EllesmereUI.ApplyIconTextFont(d.stack, path, style.stackSize or 11, "nameplates")
        end
        local sc = style.stackColor
        d.stack:SetTextColor(sc and sc.r or 1, sc and sc.g or 1, sc and sc.b or 1)
        local m = TEXT_POS[style.stackPos] or TEXT_POS.bottomright
        local sKey = m.point .. "|" .. (m.nx + (style.stackOffX or 0)) .. "|" .. (m.ny + (style.stackOffY or 0))
        if d.npStackAnchor ~= sKey then
            d.stack:ClearAllPoints()
            d.stack:SetPoint(m.point, button, m.point,
                m.nx + (style.stackOffX or 0), m.ny + (style.stackOffY or 0))
            d.npStackAnchor = sKey
        end
        d.stack:SetJustifyH(m.justify)
    end
end

-- Buffs pass: shared text styling + the purge glow. Dispellability of a
-- specific shown buff is engine-secret, so the signal chain is: a
-- CONTENTLESS texture (no image, no fill -- renders nothing however the
-- engine shows/tints/alphas it) registered as the engine aura border --
-- the engine shows/hides it exactly when the buff is dispellable
-- (= purgeable) -- and a real Glows-library glow whose alpha is slaved to
-- that texture's shown-state via SetAlphaFromBoolean (secret-safe),
-- re-evaluated after each UNIT_AURA for the plate. Style and color come
-- from the Dispel Glow options.

-- Effective glow state: with Show All Enemy Buffs on, the row is no
-- longer dispellable-only, so the glow is suppressed entirely (the style
-- dropdown and swatch are disabled in the options while that toggle is on).
local function PurgeGlowActive()
    return not not (ns.GetDispelGlow and ns.GetDispelGlow() and not PVal("showAllEnemyBuffs"))
end

local function ApplyNPBuffExtra(button, d, style)
    ApplyNPText(button, d, style)
    if not d.npPurgeInit then return end
    local Glows = EllesmereUI.Glows
    if style.purgeGlow and Glows and Glows.StartGlow then
        if not d.npPurgeRegistered then
            -- Color style is mandatory: the signal texture is contentless
            -- by design, and the Atlas default (style enum omitted) would
            -- stamp real atlas art onto it. The enum moved to
            -- Enum.CustomAuraButtonBorderStyle in build 68824; the old
            -- global is only a deprecation-CVar shim.
            local opts = { showWhenHelpful = true, showWhenHarmful = false }
            local borderStyle = (Enum and Enum.CustomAuraButtonBorderStyle) or AuraButtonBorderStyle
            if borderStyle then opts.style = borderStyle.Color end
            -- Stamp only on SUCCESS: the registration is a button call,
            -- denied while auras are secret (12.1 access restriction). A
            -- denied attempt parks the key for the restriction-lift drain
            -- (the early-nil in the OFF branch below is load-bearing and
            -- stays pre-stamped: it must kill PurgeEval even when the
            -- clear call is denied).
            if pcall(button.SetAuraBorder, button, d.npPurge, opts) then
                d.npPurgeRegistered = true
            elseif AK.DeferRestyle then
                AK.DeferRestyle(d.styleKey)
            end
        end
        local host = d.npGlowHost
        if not host then
            -- Child of the engine button (cross-tree anchoring TO engine
            -- buttons is disallowed -- the dependent would inherit their
            -- forbidden aspects). Visibility therefore rides the button:
            -- the shared Glows driver skips hidden pool buttons for free,
            -- and under restriction (secret visibility) it skips the ticks
            -- too -- the glow renders statically there, same accepted
            -- degrade as the RF CC glow. The alpha binding decides whether
            -- it renders at all (dispellability).
            host = CreateFrame("Frame", nil, button)
            host:SetAllPoints(button)
            -- Just above the border, below the duration/stack text: the
            -- text carrier sits one level over the border host, so slot in
            -- at carrier-1. Equal level with the border host still draws
            -- the glow on top of the border (created later).
            if d.stackCarrier then
                host:SetFrameLevel(d.stackCarrier:GetFrameLevel() - 1)
            else
                host:SetFrameLevel(button:GetFrameLevel() + 1)
            end
            host:EnableMouse(false)
            host:SetAlpha(0) -- shown via the alpha binding only
            d.npGlowHost = host
        end
        -- FlipBook styles only (C-side AnimationGroups): identical
        -- animation in and out of restricted content. Driver-based style
        -- picks remap to their FlipBook equivalent.
        local gType = style.purgeStyle or 2
        if Glows.RestrictionSafeStyle then gType = Glows.RestrictionSafeStyle(gType) end
        local cr, cg, cb = style.purgeR or 0.2, style.purgeG or 0.6, style.purgeB or 1
        local sz = style.width or 24
        if (not host._euiGlowActive) or host._npStyle ~= gType or host._npW ~= sz
           or host._npR ~= cr or host._npG ~= cg or host._npB ~= cb then
            Glows.StartGlow(host, gType, sz, cr, cg, cb)
            host._npStyle, host._npW = gType, sz
            host._npR, host._npG, host._npB = cr, cg, cb
        end
    else
        if d.npPurgeRegistered then
            d.npPurgeRegistered = nil
            if button.ClearAuraBorder then pcall(button.ClearAuraBorder, button) end
            d.npPurge:Hide()
        end
        if d.npGlowHost then
            if Glows and Glows.StopGlow and d.npGlowHost._euiGlowActive then
                Glows.StopGlow(d.npGlowHost)
            end
            d.npGlowHost:SetAlpha(0)
        end
    end
end

-- Re-evaluates every tracked buff button's glow alpha against its border
-- texture's engine-driven shown-state (a secret in restricted content --
-- SetAlphaFromBoolean consumes it natively). Deferred a beat behind
-- UNIT_AURA so the engine's parse/layout drain has applied first.
local function PurgeEval(b)
    for i = 1, #b.buffButtons do
        local t = b.buffButtons[i]
        local host, sig = t.dd.npGlowHost, t.dd.npPurge
        if host and sig and t.dd.npPurgeRegistered then
            local ok, shown = pcall(sig.IsShown, sig)
            if ok then
                if host.SetAlphaFromBoolean then
                    pcall(host.SetAlphaFromBoolean, host, shown, 1, 0)
                elseif not (issecretvalue and issecretvalue(shown)) then
                    host:SetAlpha(shown and 1 or 0)
                end
            end
        end
    end
end

local function BuildNPStyle(kind)
    local size = NPSize(kind)
    local height, cropped = NPHeight(kind, size)
    -- User text settings, resolved through the legacy fallback chains, so
    -- every Duration/Stacks option (size, color, position, X/Y) renders
    -- exactly like the 12.0 aura pools.
    local kindKey = (kind == "debuffs" and "debuff") or (kind == "buffs" and "buff") or "cc"
    local dur = AuraDurCfg(kindKey)
    local stk = StackCfg()
    local style = {
        width = size,
        height = height,
        texCoord = CropCoords(cropped),
        border = { 0, 0, 0, 1, size = 1 },
        cooldownReverse = true,
        noDefaultFonts = true,
        noTooltips = true,
        applyExtra = ApplyNPText,
        durSize = dur.size,
        durColor = dur.color,
        durPos = dur.pos,
        durOffX = dur.x,
        durOffY = dur.y,
        -- "None" is the duration text's show/hide switch (legacy semantics:
        -- position dropdown "None" = hidden).
        hideDurationText = (dur.pos == "none"),
        -- CC icons never render stacks (legacy parity); the shared Aura
        -- Stacks position "None" hides them everywhere else.
        showStacks = (kind ~= "cc") and (stk.pos ~= "none"),
        stackSize = stk.size,
        stackColor = stk.color,
        stackPos = stk.pos,
        stackOffX = stk.x,
        stackOffY = stk.y,
    }
    if kind == "buffs" then
        style.purgeGlow = PurgeGlowActive()
        style.purgeStyle = (ns.GetDispelGlowStyle and ns.GetDispelGlowStyle()) or 2
        -- Type-color option removed (per-aura type is unreadable under
        -- 12.1 secrecy); the glow always uses the custom color.
        if ns.GetDispelGlowColor then
            style.purgeR, style.purgeG, style.purgeB = ns.GetDispelGlowColor(nil)
        end
        style.applyExtra = ApplyNPBuffExtra
    end
    return style
end

------------------------------------------------------------------------------
-- Bundle pool
------------------------------------------------------------------------------

local SORT_IMPORTANT, SORT_DEFAULT, SORT_DIR

local function DebuffSort()
    if PVal("showAllDebuffs") then return SORT_DEFAULT end
    return SORT_IMPORTANT
end

-- Debuff importance: Blizzard's 12.1 nameplate rule (Blizzard_NamePlateAuras
-- AddAura) is fetch HARMFUL|INCLUDE_NAME_PLATE_ONLY, then keep only auras
-- flagged nameplateShowPersonal -- that flag IS the "useful debuff" gate that
-- fed the legacy debuffList. INCLUDE_NAME_PLATE_ONLY alone is INCLUSIVE
-- (adds nameplate-only auras to candidacy, does not restrict); the candidate
-- boolean does the narrowing and toggles live. "Show All Debuffs" clears it
-- (empty table, never nil: the setter must REPLACE the stored filter).
local function DebuffCand()
    if PVal("showAllDebuffs") then return {} end
    return { nameplateShowPersonal = true }
end

-- One deferred purge re-evaluation per bundle per aura burst; the small
-- delay lets the engine's parse/layout drain apply the border state first.
-- Shared drain, NOT per-bundle C_Timer.After: with 20-40 plates in an AoE
-- fight the per-bundle timers allocated hundreds of timer objects per
-- second (a measurable slice of the module's frame-time average). One
-- hidden-when-idle worker sweeps every pending bundle per 0.05s window.
local purgePendingSet = {}
local purgeElapsed = 0
local purgeDrain = CreateFrame("Frame")
purgeDrain:Hide()
purgeDrain:SetScript("OnUpdate", function(self, dt)
    purgeElapsed = purgeElapsed + dt
    if purgeElapsed < 0.05 then return end
    purgeElapsed = 0
    for b in pairs(purgePendingSet) do
        purgePendingSet[b] = nil
        PurgeEval(b)
    end
    if not next(purgePendingSet) then self:Hide() end
end)

local function SchedulePurgeEval(b)
    if purgePendingSet[b] then return end
    purgePendingSet[b] = true
    if not purgeDrain:IsShown() then
        purgeElapsed = 0
        purgeDrain:Show()
    end
end

-- Bundle construction is split into one job per container for the shared
-- AuraKit build scheduler: each container's group is a 10-button engine
-- batch (~4-6ms), and a whole bundle in one gulp was a per-frame spike
-- during the post-login pool build.
local function CreateBundleShell()
    local holder = CreateFrame("Frame", nil, UIParent)
    holder:Hide()
    holder:SetSize(1, 1)
    holder:SetPoint("CENTER", UIParent, "BOTTOMLEFT", -200, -200)

    local b = { holder = holder, containers = {}, buffButtons = {} }
    holder:SetScript("OnEvent", function() SchedulePurgeEval(b) end)
    return b
end

-- Builds one bundle container from a pre-born shell when available
-- (group add + finish are combat-legal -- probe T1/T1b), else creates
-- fresh (OOC only; the callers guard).
local function BundleContainer(b, kind, groupSpec)
    local shell = b.shells and b.shells[kind]
    if shell then
        b.shells[kind] = nil
        AK.AddGroupToContainer(shell, groupSpec)
        AK.FinishContainer(shell, "none")
        return shell
    end
    return (AK.CreateContainer(b.holder, "none", {
        point = { "CENTER", b.holder, "CENTER" },
        groups = { groupSpec },
    }))
end

local function AddBundleDebuffs(b)
    b.containers.debuffs = BundleContainer(b, "debuffs", {
        key = "np",
        filter = { "HARMFUL", "PLAYER", "INCLUDE_NAME_PLATE_ONLY", "!CROWD_CONTROL" },
        maxFrameCount = PVal("maxDebuffs") or 5,
        sortMethod = DebuffSort(),
        candidateFilters = DebuffCand(),
        style = "np:debuffs",
        layout = { elementWidth = 26, elementHeight = 26, elementSpacingX = 4, elementSpacingY = 4 },
    })
end

local function AddBundleBuffs(b)
    -- Default: dispellable (purgeable/stealable) enemy buffs only, matching
    -- the live behavior; "Show All Enemy Buffs" clears the candidate filter
    -- live (no swap) and falls back to the important-sorted full set.
    b.containers.buffs = BundleContainer(b, "buffs", {
        key = "np",
        filter = { "HELPFUL" },
        maxFrameCount = 4,
        sortMethod = SORT_IMPORTANT,
        -- Falsy-safe form: the truthy arm is a table ("X and nil or T"
        -- collapsed to T in BOTH toggle states -- an and/or chain can
        -- never select a nil arm).
        candidateFilters = not PVal("showAllEnemyBuffs") and { isStealable = true } or nil,
        style = "np:buffs",
        -- Purge indicator: engine-driven aura border, shown ONLY on
        -- dispellable (= purgeable) buffs, tinted by dispel type.
        -- Registered once; the toggle drives registration via the
        -- style pass (ApplyNPBuffExtra).
        extraInit = function(btn, dd)
            -- Pure signal texture: NO image and NO color fill, so it
            -- renders nothing no matter how the engine shows/tints/
            -- alphas it (the engine's border management drives alpha
            -- too -- an alpha-0 color fill came back as a solid tinted
            -- square over the icon). Only its SHOWN state matters: the
            -- glow alpha binding reads it as the dispellability signal.
            dd.npPurge = btn:CreateTexture(nil, "OVERLAY", nil, 7)
            dd.npPurge:SetPoint("TOPLEFT", btn, "TOPLEFT", -1, 1)
            dd.npPurge:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, -1)
            dd.npPurge:Hide()
            dd.npPurgeInit = true
            b.buffButtons[#b.buffButtons + 1] = { btn = btn, dd = dd }
            local style = AK.styles["np:buffs"]
            if style and style.purgeGlow then
                ApplyNPBuffExtra(btn, dd, style)
            end
        end,
        layout = { elementWidth = 24, elementHeight = 24, elementSpacingX = 4, elementSpacingY = 4 },
    })
end

local function AddBundleCC(b)
    b.containers.cc = BundleContainer(b, "cc", {
        key = "np",
        filter = { "HARMFUL", "CROWD_CONTROL" },
        maxFrameCount = 2,
        sortMethod = SORT_DEFAULT,
        style = "np:cc",
        layout = { elementWidth = 24, elementHeight = 24, elementSpacingX = 4, elementSpacingY = 4 },
    })
end

-- A skeleton = holder + three bare container shells, born in the early
-- load window (PLAYER_LOGIN precedes combat re-engagement on every reload
-- path -- the suite's positioning trick). All later bundle work is then
-- combat-legal group adds/finishes.
local function CreateBundleSkeleton()
    local b = CreateBundleShell()
    b.shells = {
        debuffs = AK.CreateContainerShell(b.holder, { point = { "CENTER", b.holder, "CENTER" } }),
        buffs   = AK.CreateContainerShell(b.holder, { point = { "CENTER", b.holder, "CENTER" } }),
        cc      = AK.CreateContainerShell(b.holder, { point = { "CENTER", b.holder, "CENTER" } }),
    }
    return b
end
local skeletons = {}

local function SafeClearUnit(container)
    if not pcall(container.SetUnit, container, "none") then
        pcall(container.SetUnit, container, nil)
    end
end

-- Unit binding follows the SLOT setting: a container whose slot is "none"
-- stays parked on unit "none" and costs nothing -- SetUnit/UpdateAllAuras
-- are synchronous engine parses billed to this addon, and plates churn
-- constantly in combat, so binding all three containers unconditionally
-- charged the full parse three times per spawn regardless of how many
-- rows are actually displayed. Detach clears the flag, so a pooled
-- bundle always re-binds fresh at its next attach.
local function BindContainer(c, unit, slotVal)
    if not c then return end -- conditional bundles: row disabled at build time
    if slotVal and slotVal ~= "none" then
        if not c._npcBoundUnit then
            c._npcBoundUnit = true
            c:SetUnit(unit)
            c:UpdateAllAuras()
        end
    elseif c._npcBoundUnit then
        c._npcBoundUnit = nil
        SafeClearUnit(c)
    end
end

------------------------------------------------------------------------------
-- Anchoring: mirrors PositionAuraSlot's slot semantics with container flow.
-- top/bottom center-pin (self-centering rows); left/right chain outward
-- from the health bar; topleft/topright corner-pin with per-slot growth.
------------------------------------------------------------------------------

local function FlowDir(token)
    local FD = AnchorUtil.FlowDirection
    if token == "LEFT" then return FD.Left end
    if token == "UP" then return FD.Up end
    if token == "DOWN" then return FD.Down end
    return FD.Right
end

local function TopAnchorFor(plate)
    local topElement = (ns.GetTextSlot and ns.GetTextSlot("textSlotTop")) or "none"
    if topElement == "enemyName" then return plate.name or plate.health end
    if topElement == "healthNumber" then return plate.hpNumber or plate.health end
    if topElement ~= "none" then return plate.hpText or plate.health end
    return plate.health, true -- health-anchored: add class power push
end

local function AnchorNPContainer(container, kind, plate, slotVal)
    if not container then return end
    container:ClearAllPoints()
    if not slotVal or slotVal == "none" then
        container:SetShown(false)
        return
    end
    container:SetShown(kind ~= "buffs" or container._npcAttackable ~= false)

    local size = NPSize(kind)
    local height = NPHeight(kind, size)
    local spacing = (ns.GetAuraSpacing and ns.GetAuraSpacing(kind == "cc" and "ccs" or kind)) or 4
    local xOff, yOff = 0, 0
    if ns.GetAuraSlotOffsets then
        xOff, yOff = ns.GetAuraSlotOffsets(kind == "debuffs" and "debuffSlot"
            or kind == "buffs" and "buffSlot" or "ccSlot")
    end

    local anchorPoint, gH, gV, rowWidth
    if slotVal == "top" then
        local anchor, healthAnchored = TopAnchorFor(plate)
        local debuffY = (ns.GetDebuffYOffset and ns.GetDebuffYOffset()) or 2
        local cpPush = (healthAnchored and ns.NP_ClassPowerTopPush) and ns.NP_ClassPowerTopPush(plate) or 0
        container:SetPoint("BOTTOM", anchor, "TOP", xOff, debuffY + cpPush + yOff)
        anchorPoint, gH, gV = "BOTTOMLEFT", "RIGHT", "UP"
    elseif slotVal == "bottom" then
        container:SetPoint("TOP", plate.cast or plate.health, "BOTTOM", xOff, -2 + yOff)
        anchorPoint, gH, gV = "TOPLEFT", "RIGHT", "DOWN"
    elseif slotVal == "left" then
        local sideOff = (ns.GetSideAuraXOffset and ns.GetSideAuraXOffset()) or 2
        container:SetPoint("BOTTOMRIGHT", plate.health, "BOTTOMLEFT", -sideOff + xOff, yOff)
        anchorPoint, gH, gV = "BOTTOMRIGHT", "LEFT", "UP"
    elseif slotVal == "right" then
        local sideOff = (ns.GetSideAuraXOffset and ns.GetSideAuraXOffset()) or 2
        container:SetPoint("BOTTOMLEFT", plate.health, "BOTTOMRIGHT", sideOff + xOff, yOff)
        anchorPoint, gH, gV = "BOTTOMLEFT", "RIGHT", "UP"
    elseif slotVal == "topleft" or slotVal == "topright" then
        local debuffY = (ns.GetDebuffYOffset and ns.GetDebuffYOffset()) or 2
        local cpPush = ns.NP_ClassPowerTopPush and ns.NP_ClassPowerTopPush(plate) or 0
        local growth = PVal(slotVal .. "SlotGrowth")
            or (slotVal == "topleft" and "left" or "right")
        local corner = (slotVal == "topleft") and "BOTTOMLEFT" or "BOTTOMRIGHT"
        local healthCorner = (slotVal == "topleft") and "TOPLEFT" or "TOPRIGHT"
        container:SetPoint(corner, plate.health, healthCorner, xOff, debuffY + cpPush + yOff)
        anchorPoint = corner
        if growth == "up" then
            gH = (slotVal == "topleft") and "RIGHT" or "LEFT"
            gV = "UP"
            rowWidth = size + 0.4
        else
            gH = (growth == "left") and "LEFT" or "RIGHT"
            gV = "UP"
        end
    else
        container:SetShown(false)
        return
    end

    -- Active cast lockout: the lockout icon holds the CC row's first
    -- position, so the CC container chains off its far edge instead of
    -- the health anchor (top/bottom rows trade their centering for the
    -- lockout's few seconds -- accepted).
    if kind == "cc" then
        local lk = plate.npcLockout
        if lk and lk:IsShown() then
            container:ClearAllPoints()
            if slotVal == "left" then
                container:SetPoint("BOTTOMRIGHT", lk, "BOTTOMLEFT", -spacing, 0)
            elseif slotVal == "topleft" or slotVal == "topright" then
                local growth = PVal(slotVal .. "SlotGrowth")
                    or (slotVal == "topleft" and "left" or "right")
                if growth == "up" then
                    local side = (slotVal == "topleft") and "LEFT" or "RIGHT"
                    container:SetPoint("BOTTOM" .. side, lk, "TOP" .. side, 0, spacing)
                elseif growth == "left" then
                    container:SetPoint("BOTTOMRIGHT", lk, "BOTTOMLEFT", -spacing, 0)
                else
                    container:SetPoint("BOTTOMLEFT", lk, "BOTTOMRIGHT", spacing, 0)
                end
            else -- top, bottom, right: chain rightward
                container:SetPoint("BOTTOMLEFT", lk, "BOTTOMRIGHT", spacing, 0)
            end
        end
    end

    -- Everything below derives from slot/geometry settings alone (never
    -- from the plate), so a bundle whose stamp matches the current layout
    -- generation already carries this exact engine state from its last
    -- attach -- skip the setters (plate churn re-attaches bundles
    -- constantly; unconditional re-drives were per-spawn dirty marks).
    if container._npcGeoGen == geoGen and container._npcSlotVal == slotVal then return end
    container._npcGeoGen = geoGen
    container._npcSlotVal = slotVal

    container:SetAuraLayoutAnchorPoint(anchorPoint)
    container:SetAuraLayoutGrowthDirection(FlowDir(gH), FlowDir(gV))
    container:SetAuraLayoutRowWidth(rowWidth)
    container:SetAuraGroupLayout("np", {
        elementWidth = size, elementHeight = height,
        elementSpacingX = spacing, elementSpacingY = spacing,
    })

    -- Aura tier of the flattened plate render order (text 900 > auras 800),
    -- honoring the per-slot Raise Strata toggle like the legacy pools.
    local raise = ns.GetSlotRaiseStrata and ns.GetSlotRaiseStrata(slotVal)
    container:SetFrameStrata(raise and "HIGH" or "MEDIUM")
    container:SetFrameLevel(800)
end

-- Cast-lockout pseudo-aura (kick lockout displayed as a CC icon): armed by
-- the core's cast machinery (ShowCastLockout -- readable, cast-driven, no
-- aura reads), rendered here since the legacy CC row is gone. The frame is
-- OUR child of OUR plate object; positioned exactly at the CC slot pin.
local function PositionLockout(plate, f, slotVal)
    f:ClearAllPoints()
    local xOff, yOff = ns.GetAuraSlotOffsets("ccSlot")
    if slotVal == "top" then
        local anchor, healthAnchored = TopAnchorFor(plate)
        local debuffY = (ns.GetDebuffYOffset and ns.GetDebuffYOffset()) or 2
        local cpPush = (healthAnchored and ns.NP_ClassPowerTopPush) and ns.NP_ClassPowerTopPush(plate) or 0
        f:SetPoint("BOTTOM", anchor, "TOP", xOff, debuffY + cpPush + yOff)
    elseif slotVal == "bottom" then
        f:SetPoint("TOP", plate.cast or plate.health, "BOTTOM", xOff, -2 + yOff)
    elseif slotVal == "left" then
        local sideOff = (ns.GetSideAuraXOffset and ns.GetSideAuraXOffset()) or 2
        f:SetPoint("BOTTOMRIGHT", plate.health, "BOTTOMLEFT", -sideOff + xOff, yOff)
    elseif slotVal == "right" then
        local sideOff = (ns.GetSideAuraXOffset and ns.GetSideAuraXOffset()) or 2
        f:SetPoint("BOTTOMLEFT", plate.health, "BOTTOMRIGHT", sideOff + xOff, yOff)
    else -- topleft / topright
        local debuffY = (ns.GetDebuffYOffset and ns.GetDebuffYOffset()) or 2
        local cpPush = ns.NP_ClassPowerTopPush and ns.NP_ClassPowerTopPush(plate) or 0
        local corner = (slotVal == "topleft") and "BOTTOMLEFT" or "BOTTOMRIGHT"
        local hc = (slotVal == "topleft") and "TOPLEFT" or "TOPRIGHT"
        f:SetPoint(corner, plate.health, hc, xOff, debuffY + cpPush + yOff)
    end
end

function ns.NPC_UpdateLockout(plate)
    if not plate then return end
    local _, _, cs = ns.GetAuraSlots()
    local lockout = (cs and cs ~= "none") and ns.GetActiveCastLockout
        and ns.GetActiveCastLockout(plate)
    local f = plate.npcLockout
    if lockout and plate.health then
        if not f then
            f = CreateFrame("Frame", nil, plate)
            f:SetFrameStrata("MEDIUM")
            f:SetFrameLevel(800)
            f.icon = f:CreateTexture(nil, "ARTWORK")
            f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
            f.icon:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
            f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
            f.cd:SetAllPoints(f)
            f.cd:SetReverse(true)
            f.cd:SetDrawEdge(false)
            local PP = EllesmereUI.PP
            if PP and PP.CreateBorder then PP.CreateBorder(f, 0, 0, 0, 1, 1) end
            plate.npcLockout = f
        end
        local size = NPSize("cc")
        local height, cropped = NPHeight("cc", size)
        f:SetSize(size, height)
        local tc = CropCoords(cropped)
        f.icon:SetTexture(lockout.icon)
        f.icon:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
        f.cd:SetCooldown(lockout.start, lockout.duration)
        PositionLockout(plate, f, cs)
        f:Show()
    elseif f then
        f:Hide()
    end
    -- Re-anchor the CC container: chains off the lockout while shown.
    local b = active[plate]
    if b then
        AnchorNPContainer(b.containers.cc, "cc", plate, cs)
    end
end

-- Target arrows sat outside the legacy side-aura rows by computed extents;
-- shown counts are engine-secret now, so arrows anchor to the outermost
-- side CONTAINER edge instead (the engine sizes it with the aura count --
-- an empty row collapses the arrow back to the health bar edge). Sides
-- without an aura row keep the legacy readable-extent positioning.
local function ReanchorArrows(plate)
    if not (plate.leftArrow and plate.rightArrow) then return end
    if not plate.leftArrow:IsShown() then return end
    local b = active[plate]
    if not b then return end
    local ds, bs, cs = ns.GetAuraSlots()
    local leftC, rightC, leftKey, rightKey
    local function consider(slotVal, c, key)
        if not c then return end
        if slotVal == "left" and not leftC then leftC = c; leftKey = key end
        if slotVal == "right" and not rightC then rightC = c; rightKey = key end
    end
    -- Priority by row cap (debuffs widest first).
    consider(ds, b.containers.debuffs, "debuffSlot")
    consider(bs, b.containers.buffs, "buffSlot")
    consider(cs, b.containers.cc, "ccSlot")
    local PP = EllesmereUI.PP
    -- Side containers are BOTTOM-anchored to the bar's bottom edge and grow
    -- UP (AnchorNPContainer), so a container's vertical CENTER sits above the
    -- bar -- anchoring the arrows to the container's LEFT/RIGHT relPoint
    -- (its center line) is what floated them high. The container's BOTTOM
    -- corner is the one anchor where both axes are truthful: x = the
    -- engine-sized outer edge (aura counts are secret; only the engine knows
    -- the row width), y = the bar's bottom (minus the slot's own yOff). From
    -- there the arrow centers on the bar via the profile bar height.
    local aw = plate._arrowW or 16
    local ah = plate._arrowH or 16
    local barH = (ns.GetHealthBarHeight and ns.GetHealthBarHeight()) or 10
    if leftC then
        local yOff = 0
        if ns.GetAuraSlotOffsets then
            local _, y = ns.GetAuraSlotOffsets(leftKey)
            yOff = y or 0
        end
        local cy = barH / 2 - yOff
        plate.leftArrow:ClearAllPoints()
        PP.Point(plate.leftArrow, "TOP", leftC, "BOTTOMLEFT", -(8 + aw / 2), cy + ah / 2)
        PP.Point(plate.leftArrow, "BOTTOM", leftC, "BOTTOMLEFT", -(8 + aw / 2), cy - ah / 2)
        PP.Width(plate.leftArrow, aw)
    end
    if rightC then
        local yOff = 0
        if ns.GetAuraSlotOffsets then
            local _, y = ns.GetAuraSlotOffsets(rightKey)
            yOff = y or 0
        end
        local cy = barH / 2 - yOff
        plate.rightArrow:ClearAllPoints()
        PP.Point(plate.rightArrow, "TOP", rightC, "BOTTOMRIGHT", 8 + aw / 2, cy + ah / 2)
        PP.Point(plate.rightArrow, "BOTTOM", rightC, "BOTTOMRIGHT", 8 + aw / 2, cy - ah / 2)
        PP.Width(plate.rightArrow, aw)
    end
end

------------------------------------------------------------------------------
-- Attach / detach
------------------------------------------------------------------------------

-- Plates that arrive while the pool is empty (login trickle window, or
-- genuine exhaustion) wait here; freshly built or freed bundles service
-- them immediately.
local waiting = setmetatable({}, { __mode = "k" })

local function ServiceWaiting()
    for plate in pairs(waiting) do
        waiting[plate] = nil
        if plate.unit and #pool > 0 then
            ns.NPC_AttachPlate(plate, plate.unit)
        end
        if #pool == 0 then return end
    end
end

function ns.NPC_AttachPlate(plate, unit)
    AK = AK or EllesmereUI.AuraKit
    if not AK then return end
    if not unit or UnitIsUnit(unit, "player") then return end -- personal plate: no aura rows

    local b = active[plate]
    if not b then
        b = table.remove(pool)
        if not b then
            waiting[plate] = true -- serviced when a bundle builds or frees
            return
        end
        waiting[plate] = nil
        active[plate] = b
    end

    b.holder:SetParent(plate)
    b.holder:ClearAllPoints()
    b.holder:SetPoint("CENTER", plate, "CENTER")
    b.holder:Show()

    local ds, bs, cs = ns.GetAuraSlots()
    if b.containers.buffs then
        b.containers.buffs._npcAttackable = not not UnitCanAttack("player", unit)
    end
    -- A plate spawning for the CURRENT target picks up the class-power
    -- push right here, so it must be tracked as the plate to re-anchor
    -- when the target changes away.
    if UnitIsUnit(unit, "target") then lastTargetPlate = plate end
    AnchorNPContainer(b.containers.debuffs, "debuffs", plate, ds)
    AnchorNPContainer(b.containers.buffs, "buffs", plate, bs)
    AnchorNPContainer(b.containers.cc, "cc", plate, cs)

    BindContainer(b.containers.debuffs, unit, ds)
    BindContainer(b.containers.buffs, unit, bs)
    BindContainer(b.containers.cc, unit, cs)
    ReanchorArrows(plate)

    -- Purge glow: watch this unit's aura changes (deferred re-eval of the
    -- glow alpha bindings). Registered only while the feature is on AND a
    -- buff row is actually displayed (the glow decorates buff buttons; a
    -- "none" buff slot has nothing to evaluate).
    if PurgeGlowActive() and bs and bs ~= "none" then
        b.holder:RegisterUnitEvent("UNIT_AURA", unit)
        SchedulePurgeEval(b)
    else
        b.holder:UnregisterEvent("UNIT_AURA")
    end
end

function ns.NPC_DetachPlate(plate)
    waiting[plate] = nil
    if lastTargetPlate == plate then lastTargetPlate = nil end
    if plate.npcLockout then plate.npcLockout:Hide() end
    local b = active[plate]
    if not b then return end
    active[plate] = nil
    purgePendingSet[b] = nil
    b.holder:UnregisterEvent("UNIT_AURA")
    for i = 1, #KINDS do
        local c = b.containers[KINDS[i]]
        if c and c._npcBoundUnit then
            c._npcBoundUnit = nil
            SafeClearUnit(c)
        end
    end
    b.holder:Hide()
    b.holder:SetParent(UIParent)
    b.holder:ClearAllPoints()
    b.holder:SetPoint("CENTER", UIParent, "BOTTOMLEFT", -200, -200)
    pool[#pool + 1] = b
    ServiceWaiting()
end

------------------------------------------------------------------------------
-- Settings reload: style + geometry + config fingerprints (one set,
-- containers share settings globally).
------------------------------------------------------------------------------

local npFP = {}

local function StyleFPFor(kind)
    local size = NPSize(kind)
    local height = NPHeight(kind, size)
    -- Text settings feed BuildNPStyle, so every input must flip this
    -- fingerprint or a live change never restyles the engine buttons.
    local kindKey = (kind == "debuffs" and "debuff") or (kind == "buffs" and "buff") or "cc"
    local dur = AuraDurCfg(kindKey)
    local stk = StackCfg()
    local purge = "-"
    if kind == "buffs" and ns.GetDispelGlow then
        local pr, pg, pb = 0, 0, 0
        if ns.GetDispelGlowColor then
            pr, pg, pb = ns.GetDispelGlowColor(nil)
        end
        purge = FP(PurgeGlowActive(), ns.GetDispelGlowStyle and ns.GetDispelGlowStyle() or 2, pr, pg, pb)
    end
    local durFP = FP(dur.size, dur.x, dur.y, dur.pos, dur.color.r, dur.color.g, dur.color.b)
    local stkFP = FP(stk.size, stk.x, stk.y, stk.pos, stk.color.r, stk.color.g, stk.color.b)
    return FP(kind, size, height, durFP, stkFP, purge,
        EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("nameplates") or "")
end

local function GeoFP()
    local ds, bs, cs = ns.GetAuraSlots()
    local dx, dy = ns.GetAuraSlotOffsets("debuffSlot")
    local bx, by = ns.GetAuraSlotOffsets("buffSlot")
    local cx, cy = ns.GetAuraSlotOffsets("ccSlot")
    return FP(ds, bs, cs, dx, dy, bx, by, cx, cy,
        NPSize("debuffs"), NPSize("buffs"), NPSize("cc"),
        ns.GetAuraSpacing and ns.GetAuraSpacing("debuffs") or 0,
        ns.GetAuraSpacing and ns.GetAuraSpacing("buffs") or 0,
        ns.GetAuraSpacing and ns.GetAuraSpacing("ccs") or 0,
        ns.GetAuraCrop and tostring(ns.GetAuraCrop("debuffs")) or "-",
        ns.GetAuraCrop and tostring(ns.GetAuraCrop("buffs")) or "-",
        ns.GetAuraCrop and tostring(ns.GetAuraCrop("ccs")) or "-",
        ns.GetDebuffYOffset and ns.GetDebuffYOffset() or 0,
        ns.GetSideAuraXOffset and ns.GetSideAuraXOffset() or 0,
        PVal("textSlotTop"), PVal("topleftSlotGrowth"), PVal("toprightSlotGrowth"),
        -- Raise Strata feeds the (generation-guarded) layout pass, so its
        -- toggles must flip the geometry fingerprint like everything else.
        ns.GetSlotRaiseStrata and ns.GetSlotRaiseStrata(ds) or false,
        ns.GetSlotRaiseStrata and ns.GetSlotRaiseStrata(bs) or false,
        ns.GetSlotRaiseStrata and ns.GetSlotRaiseStrata(cs) or false)
end

local function CfgFP()
    return FP(PVal("maxDebuffs"), PVal("showAllDebuffs"), PVal("showAllEnemyBuffs"))
end

local function ReanchorActive()
    local ds, bs, cs = ns.GetAuraSlots()
    for plate, b in pairs(active) do
        AnchorNPContainer(b.containers.debuffs, "debuffs", plate, ds)
        AnchorNPContainer(b.containers.buffs, "buffs", plate, bs)
        AnchorNPContainer(b.containers.cc, "cc", plate, cs)
        -- Slot settings may have flipped between "none" and displayed;
        -- BindContainer no-ops when the binding already matches.
        if plate.unit then
            BindContainer(b.containers.debuffs, plate.unit, ds)
            BindContainer(b.containers.buffs, plate.unit, bs)
            BindContainer(b.containers.cc, plate.unit, cs)
        end
        ReanchorArrows(plate)
    end
end

-- Rewires freshly-ensured containers on active plates (attackability,
-- purge watch) and re-anchors/binds everything. Debounced: each ensure
-- job calls this at its tail, so one pass covers a burst of builds.
local npEnsurePending = false
local function NpEnsureWireSoon()
    if npEnsurePending then return end
    npEnsurePending = true
    C_Timer.After(0.05, function()
        npEnsurePending = false
        local _, bs = ns.GetAuraSlots()
        local wantPurge = PurgeGlowActive()
        for plate, b in pairs(active) do
            if plate.unit then
                if b.containers.buffs then
                    b.containers.buffs._npcAttackable = not not UnitCanAttack("player", plate.unit)
                end
                if wantPurge and bs and bs ~= "none" then
                    b.holder:RegisterUnitEvent("UNIT_AURA", plate.unit)
                    SchedulePurgeEval(b)
                end
            end
        end
        ReanchorActive()
    end)
end

-- Builds any row containers that a bundle is missing for the CURRENT slot
-- settings (a row enabled after the pool was built). Rows disabled at
-- pool-build time leave their skeleton shell UNCONSUMED in b.shells, so a
-- later enable is a combat-legal group add onto that shell; only a bundle
-- whose shell for the row is already gone holds until regen.
local function QueueBundleEnsure(b)
    if b.npcEnsurePending then return end
    b.npcEnsurePending = true
    AK.QueueBuildJob(function()
        local ds, bs, cs = ns.GetAuraSlots()
        local locked = InCombatLockdown()
        local held = false
        local function ensure(kind, slot, add)
            if not (slot and slot ~= "none") or b.containers[kind] then return end
            if (b.shells and b.shells[kind]) or not locked then
                add(b)
            else
                held = true
            end
        end
        ensure("debuffs", ds, AddBundleDebuffs)
        ensure("buffs", bs, AddBundleBuffs)
        ensure("cc", cs, AddBundleCC)
        NpEnsureWireSoon()
        if held then return "hold" end
        b.npcEnsurePending = nil
    end, "np:ensure")
end

function ns.NPC_ReloadAll()
    AK = AK or EllesmereUI.AuraKit
    if not AK then return end

    -- Conditional-bundle ensure: rows enabled after the pool was built get
    -- their containers on demand (cheap scan: 3 nil-checks per bundle).
    do
        local ds, bs, cs = ns.GetAuraSlots()
        local needD = ds and ds ~= "none"
        local needB = bs and bs ~= "none"
        local needC = cs and cs ~= "none"
        local function scan(b)
            if (needD and not b.containers.debuffs)
                or (needB and not b.containers.buffs)
                or (needC and not b.containers.cc) then
                QueueBundleEnsure(b)
            end
        end
        for i = 1, #pool do scan(pool[i]) end
        for _, b in pairs(active) do scan(b) end
    end

    local v = StyleFPFor("debuffs") .. ";" .. StyleFPFor("buffs") .. ";" .. StyleFPFor("cc")
    if npFP.style ~= v then
        npFP.style = v
        for i = 1, #KINDS do
            local kind = KINDS[i]
            AK.styles["np:" .. kind] = BuildNPStyle(kind)
            AK.RestyleSoon("np:" .. kind)
        end
    end

    v = CfgFP()
    if npFP.cfg ~= v then
        npFP.cfg = v
        local maxDbf = PVal("maxDebuffs") or 5
        local sort = DebuffSort()
        local dbfCand = DebuffCand()
        -- Empty table (not nil) when showing all: guarantees the setter
        -- REPLACES the stored filter rather than risking a nil no-op.
        local buffCand = {}
        if not PVal("showAllEnemyBuffs") then buffCand = { isStealable = true } end
        local function apply(b)
            -- Conditional bundles: a row's container may not exist.
            if b.containers.debuffs then
                b.containers.debuffs:SetAuraGroupMaxFrameCount("np", maxDbf)
                b.containers.debuffs:SetAuraGroupCandidateFilters("np", dbfCand)
                -- Enum values can be 0: compare against nil, and the direct
                -- setter (unlike AddAuraGroup) requires an explicit direction.
                if sort ~= nil and SORT_DIR ~= nil then
                    b.containers.debuffs:SetAuraGroupSortMethod("np", sort, SORT_DIR)
                end
            end
            if b.containers.buffs then
                b.containers.buffs:SetAuraGroupCandidateFilters("np", buffCand)
            end
        end
        for _, b in pairs(active) do apply(b) end
        for i = 1, #pool do apply(pool[i]) end
    end

    v = GeoFP()
    if npFP.geo ~= v then
        npFP.geo = v
        -- Invalidate every bundle's layout stamp (pooled ones re-drive at
        -- their next attach; active ones right now).
        geoGen = geoGen + 1
        ReanchorActive()
    end

    -- Purge glow toggle/state: (un)register the per-plate watchers to match
    -- the current setting and re-evaluate the alpha bindings. Gated on a
    -- displayed buff row, same as the attach path.
    local wantPurge = PurgeGlowActive()
    local _, bSlot = ns.GetAuraSlots()
    for plate, b in pairs(active) do
        if wantPurge and bSlot and bSlot ~= "none" and plate.unit then
            b.holder:RegisterUnitEvent("UNIT_AURA", plate.unit)
            SchedulePurgeEval(b)
        else
            b.holder:UnregisterEvent("UNIT_AURA")
        end
    end
end

------------------------------------------------------------------------------
-- Pool build at login (containers must be created out of combat).
------------------------------------------------------------------------------

-- Pool builds INCREMENTALLY through the shared AuraKit build scheduler: a
-- full synchronous build is ~1200 aura buttons (40 bundles x 3 containers
-- x 10-button batches) and measurably extends the loading screen; even a
-- bundle-per-frame trickle spiked frames. One job per CONTAINER keeps each
-- build step ~4-6ms inside the scheduler's frame budget (combat-paused;
-- never ticks during loading screens). Plates that attach before the pool
-- catches up wait in `waiting` and are serviced as bundles complete.
local built = 0
-- CONDITIONAL bundles: each row's container (a 10-button batch for
-- debuffs/buffs, 2-batch for cc) only builds when its aura slot is
-- actually displayed -- rows set to "none" cost zero frames across the
-- whole pool. Enabling a row later builds the missing containers through
-- the ensure pass in NPC_ReloadAll.
local function QueuePoolBuild()
    for i = 1, POOL_SIZE do
        local nb
        -- No oocOnly marks: group adds onto pre-born skeleton shells are
        -- combat-legal (probe T1/T1b), so after an in-combat /reload the
        -- whole pool builds WHILE fighting. Only a skeleton shortage (stash
        -- exhausted mid-combat) holds until regen.
        AK.QueueBuildJob(function()
            nb = table.remove(skeletons)
            if not nb then
                if InCombatLockdown() then return "hold" end
                nb = CreateBundleSkeleton()
            end
            local ds = ns.GetAuraSlots()
            if ds and ds ~= "none" then AddBundleDebuffs(nb) end
        end, "np:debuffs")
        AK.QueueBuildJob(function()
            if not nb then return "hold" end
            local _, bs = ns.GetAuraSlots()
            if bs and bs ~= "none" then AddBundleBuffs(nb) end
        end, "np:buffs")
        AK.QueueBuildJob(function()
            if not nb then return "hold" end
            local _, _, cs = ns.GetAuraSlots()
            if cs and cs ~= "none" then AddBundleCC(nb) end
            pool[#pool + 1] = nb
            built = built + 1
            ServiceWaiting()
            if built >= POOL_SIZE then ns.NPC_ReloadAll() end
        end, "np:cc+pool")
    end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_TARGET_CHANGED")
boot:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        AK = AK or EllesmereUI.AuraKit
        if not AK then return end
        if AuraContainerSortMethod then
            SORT_IMPORTANT = AuraContainerSortMethod.ImportantOnly
            SORT_DEFAULT = AuraContainerSortMethod.Default
        end
        if AuraContainerSortDirection then
            SORT_DIR = AuraContainerSortDirection.Normal
        end
        for i = 1, #KINDS do
            AK.styles["np:" .. KINDS[i]] = BuildNPStyle(KINDS[i])
        end
        -- Skeleton stash born SYNCHRONOUSLY in the early load window:
        -- PLAYER_LOGIN runs before combat lockdown re-engages on every
        -- reload path (the suite's positioning trick), and bare shells
        -- skip the eager 10-button group batch, so this is cheap here and
        -- makes every later pool step combat-legal. All the expensive
        -- work (group adds = engine button batches) still drains through
        -- the shared scheduler. Plates that spawn before the first
        -- bundles land wait in `waiting` and are serviced as bundles
        -- complete.
        for i = 1, POOL_SIZE do
            skeletons[i] = CreateBundleSkeleton()
        end
        QueuePoolBuild()
    elseif event == "PLAYER_TARGET_CHANGED" then
        -- Class power on the target plate pushes top-anchored rows up.
        -- Only the outgoing and incoming target plates can change, so
        -- re-anchor exactly those two -- a full-pool ReanchorActive here
        -- re-drove the layout setters on every plate on every target swap
        -- (target churn is constant in combat).
        local ds, bs, cs = ns.GetAuraSlots()
        local prev = lastTargetPlate
        lastTargetPlate = nil
        for plate, b in pairs(active) do
            local isNew = plate.unit and UnitIsUnit(plate.unit, "target")
            if isNew then lastTargetPlate = plate end
            if isNew or plate == prev then
                AnchorNPContainer(b.containers.debuffs, "debuffs", plate, ds)
                AnchorNPContainer(b.containers.buffs, "buffs", plate, bs)
                AnchorNPContainer(b.containers.cc, "cc", plate, cs)
                ReanchorArrows(plate)
            end
        end
    end
end)
