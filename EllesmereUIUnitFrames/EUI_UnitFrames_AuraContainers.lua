-- EUI_UnitFrames_AuraContainers.lua
-- 12.1 aura displays for unit frames: AuraKit containers replace the oUF aura
-- element for migrated units. This file is a pure VIEW over the existing
-- per-unit settings keys -- zero migration, every current option keeps working.
--
-- Classification model: the old element fetched with a broad base filter and
-- union-OR'd the class toggles per aura. Containers cannot OR filters, so each
-- class is its own group, made mutually exclusive with '!' negation, declared
-- once up-front (groups are add-only) and enabled by flipping maxFrameCount.
-- Known behavior deltas vs the old element (documented for patch notes):
--   * icon caps apply per enabled class, not as one total across the union
--   * sorting applies within each class group, not across all shown icons
--   * sated/always-hidden spellID excludes are inert on assistable units
--     (engine identity gate); enemy units filter exactly as before

local _, ns = ...

-- 12.1 ONLY: on a 12.0 client this whole file is inert -- CreateTargetAuras
-- existence-checks ns.UF_CreateAuraContainers/ns.UF_ContainerUnits, so
-- nothing below may execute or the legacy aura rows go dark on retail.
if not (EllesmereUI and EllesmereUI.IS_121) then return end

local AK -- EllesmereUI.AuraKit, resolved at first use (parent loads first)

-- Phase gate: units render through containers once listed here.
ns.UF_ContainerUnits = {
    player = true, target = true, focus = true,
    boss1 = true, boss2 = true, boss3 = true, boss4 = true, boss5 = true,
}

-- Ownership is LOAD-TIME, not build-time: the legacy player dispel-overlay
-- scan (main file) hard-errors under 12.1 aura restrictions, and container
-- construction is scheduler-deferred -- if this flag waited for the dispel
-- slots to actually build, every player UNIT_AURA in the pre-build window
-- error-stormed through the unguarded index scan.
ns.UF_DispelOverlayDisabled = true

local AURA_CROP_HEIGHT = 0.80
local AURA_ZOOM = 0.07
local FALLBACK_FONT = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"

local SATED_DEBUFFS = {
    [57723] = true, [57724] = true, [80354] = true, [95809] = true,
    [160455] = true, [264689] = true, [390435] = true, [428628] = true,
}
local ALWAYS_HIDE_DEBUFFS = {
    [1254550] = true, -- Arcane Empowerment
    [308312]  = true, -- Time Trial Practice
}

-- Filter classes (verified 12.1 vocabulary = AuraUtil.AuraFilters; IMPORTANT
-- does not exist as a token). Token classes become groups made mutually
-- exclusive by negating the ENABLED classes before them in priority order --
-- negating disabled classes would eat auras that belong to an enabled class
-- (union semantics, not chain semantics). Candidate classes are engine
-- boolean selectors that cannot be token-negated; they sit after the token
-- chain and may rarely duplicate an aura matching two candidate classes.
-- Because group filter strings are fixed at declaration (no group filter
-- setter exists), a change to the enabled set swaps in a fresh container.
local TOKEN_CLASSES = {
    { key = "raid",        token = "RAID",                    skey = "Raid" },
    { key = "raidcombat",  token = "RAID_IN_COMBAT",          skey = "RaidInCombat" },
    { key = "dispellable", token = "RAID_PLAYER_DISPELLABLE", skey = "Dispellable" },
    { key = "cc",          token = "CROWD_CONTROL",           skey = "CrowdControl" },
    { key = "bigdef",      token = "BIG_DEFENSIVE",           skey = "BigDefensive" },
    { key = "extdef",      token = "EXTERNAL_DEFENSIVE",      skey = "ExternalDefensive" },
    { key = "cancel",      token = "CANCELABLE",              skey = "Cancelable", buffOnly = true },
}
local CANDIDATE_CLASSES = {
    { key = "bossaura", cand = "isBossAura",     skey = "BossAura",     debuffOnly = true },
    { key = "roleaura", cand = "isRoleAura",     skey = "RoleAura",     debuffOnly = true },
    { key = "priority", cand = "isPriorityAura", skey = "PriorityAura", debuffOnly = true },
    { key = "steal",    cand = "isStealable",    skey = "Stealable",    buffOnly = true },
}

local function ClassEnabled(class, isBuff, s)
    if class.buffOnly and not isBuff then return false end
    if class.debuffOnly and isBuff then return false end
    local prefix = "debuff"
    if isBuff then prefix = "buff" end
    return s[prefix .. class.skey] == true
end

local function BuildChain(base, isBuff, s)
    local chain, negations = {}, {}
    for i = 1, #TOKEN_CLASSES do
        local class = TOKEN_CLASSES[i]
        if ClassEnabled(class, isBuff, s) then
            local tokens = { base, class.token }
            for n = 1, #negations do tokens[#tokens + 1] = negations[n] end
            chain[#chain + 1] = { key = class.key, tokens = tokens }
            negations[#negations + 1] = "!" .. class.token
        end
    end
    for i = 1, #CANDIDATE_CLASSES do
        local class = CANDIDATE_CLASSES[i]
        if ClassEnabled(class, isBuff, s) then
            local tokens = { base }
            for n = 1, #negations do tokens[#tokens + 1] = negations[n] end
            chain[#chain + 1] = { key = class.key, tokens = tokens, cand = class.cand }
        end
    end
    return chain
end

local function ChainSignature(chain)
    local sig = {}
    for i = 1, #chain do sig[i] = chain[i].key end
    return table.concat(sig, ",")
end

local registry = {} -- [unitKey] = { frame, buffs, debuffs, dispel, sig = {buffs=,debuffs=}, pendingSwap }
local CreateElementContainer -- forward-declared; defined after the style builders

-- Shell stash: bare container shells for every migrated unit, born
-- SYNCHRONOUSLY at PLAYER_LOGIN -- the early load window where combat
-- lockdown is never engaged even on an in-combat /reload (the suite's
-- positioning trick). Bare shells skip the eager group button batches, so
-- this is cheap; it makes the deferred per-unit builds combat-legal
-- (group/slot adds on EXISTING containers -- probe T1/T1b/T2). Shells
-- parent to a hidden holder and are adopted by the real frame at build.
local shellStash = {}
do
    local stashBoot = CreateFrame("Frame")
    stashBoot:RegisterEvent("PLAYER_LOGIN")
    stashBoot:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        AK = AK or EllesmereUI.AuraKit
        if not (AK and AK.CreateContainerShell) then return end
        local holder = CreateFrame("Frame", nil, UIParent)
        holder:Hide()
        holder:SetSize(1, 1)
        holder:SetPoint("CENTER", UIParent, "BOTTOMLEFT", -200, -200)
        -- Shared spec table is safe: point is only unpacked at creation.
        local spec = { point = { "CENTER", holder, "CENTER" } }
        for unit in pairs(ns.UF_ContainerUnits) do
            shellStash[unit] = {
                buffs = AK.CreateContainerShell(holder, spec),
                debuffs = AK.CreateContainerShell(holder, spec),
            }
        end
        shellStash.dispel = AK.CreateContainerShell(holder, spec)
    end)
end

local function SettingsFor(unit)
    if ns.UF_GetSettings then return ns.UF_GetSettings(unit) end
    local db = ns.db
    if not db then return nil end
    local key = unit:match("^boss%d+$") and "boss" or unit
    return db.profile[key]
end

local function ResolveOwnOnly(base, s)
    if base == "HELPFUL" then return s.onlyPlayerBuffs end
    return s.onlyPlayerDebuffs
end

-- Own Only renders as a PLAYER filter token on the group declarations (same
-- mechanism as the nameplate module): the isFromPlayerOrPlayerPet candidate
-- boolean does not filter HARMFUL auras on enemy units (boss/target), while
-- the token filters everywhere. Filter strings are fixed at declaration, so
-- own-only is part of the container-swap signature, not a live setter.
-- Player-frame debuffs always show all: everything on you matters, and any
-- stale onlyPlayerDebuffs value must have no effect.
local function EffectiveOwnOnly(unit, base, s)
    if unit == "player" and base == "HARMFUL" then return false end
    return ResolveOwnOnly(base, s) == true
end

-- Mirrors the main file's ResolveBuffLayout anchor/growth tables.
local ANCHOR_IA = {
    topleft = "BOTTOMLEFT", topright = "BOTTOMRIGHT",
    bottomleft = "TOPLEFT", bottomright = "TOPRIGHT",
    left = "RIGHT", right = "LEFT",
}
local ANCHOR_FP = {
    topleft = { "TOPLEFT", 0, 1 }, topright = { "TOPRIGHT", 0, 1 },
    bottomleft = { "BOTTOMLEFT", 0, -1 }, bottomright = { "BOTTOMRIGHT", 0, -1 },
    left = { "LEFT", -1, 0 }, right = { "RIGHT", 1, 0 },
}
local AUTO_GROWTH = {
    topleft = { "RIGHT", "UP" }, topright = { "LEFT", "UP" },
    bottomleft = { "RIGHT", "DOWN" }, bottomright = { "LEFT", "DOWN" },
    left = { "LEFT", "DOWN" }, right = { "RIGHT", "DOWN" },
}
local EXPLICIT_GROWTH = {
    right = { "RIGHT", "UP" }, left = { "LEFT", "UP" },
    up = { "RIGHT", "UP" }, down = { "RIGHT", "DOWN" },
}

local function ResolveLayout(anchor, growth)
    anchor = anchor or "topleft"
    local ia = ANCHOR_IA[anchor] or "BOTTOMLEFT"
    local fp = ANCHOR_FP[anchor] or ANCHOR_FP.topleft
    local g
    if growth and growth ~= "auto" then g = EXPLICIT_GROWTH[growth] end
    g = g or AUTO_GROWTH[anchor] or AUTO_GROWTH.topleft
    return ia, fp[1], fp[2], fp[3], g[1], g[2]
end

-- Mirrors AuraMaxCols on the growth SETTING string: explicit per-row cap wins;
-- explicit vertical growth = one column; anything else = unlimited row.
local function ResolveColumns(growth, maxCount, maxPerRow)
    if maxPerRow and maxPerRow >= 1 and maxPerRow < maxCount then return maxPerRow end
    if growth == "up" or growth == "down" then return 1 end
    return nil
end

local FLOWDIR = { RIGHT = nil, LEFT = nil, UP = nil, DOWN = nil } -- filled on first use
local function FlowDir(token)
    if FLOWDIR.RIGHT == nil then
        FLOWDIR.RIGHT = AnchorUtil.FlowDirection.Right
        FLOWDIR.LEFT = AnchorUtil.FlowDirection.Left
        FLOWDIR.UP = AnchorUtil.FlowDirection.Up
        FLOWDIR.DOWN = AnchorUtil.FlowDirection.Down
    end
    return FLOWDIR[token]
end

-- zoom (optional) overrides the default AURA_ZOOM crop; per-unit/per-category
-- Icon Zoom values flow in here, defaulting to AURA_ZOOM so unset = unchanged.
local function CropCoords(cropped, w, h, zoom)
    local z = zoom or AURA_ZOOM
    if cropped and w and h and w > 0 then
        local uSpan = 1 - 2 * z
        local vSpan = uSpan * (h / w)
        local v0 = 0.5 - vSpan / 2
        return { z, 1 - z, v0, 1 - v0 }
    end
    return { z, 1 - z, z, 1 - z }
end

local STACK_POINTS = {
    bottomright = { "BOTTOMRIGHT", -1 }, bottomleft = { "BOTTOMLEFT", 1 },
    topright = { "TOPRIGHT", -1 }, topleft = { "TOPLEFT", 1 },
    center = { "CENTER", 0 },
}

-- Module text pass: fonts through the shared icon-text pipeline (outline slug
-- rules live there), duration text centered like cooldown countdown text.
-- Restyles hit every registered button, so SetFont is change-guarded (it
-- costs real time even with identical values; font key = path|size, so an
-- outline-only module font change slips until a size touch -- accepted,
-- same as the RF pass). The duration string is ALWAYS fonted, hidden or
-- not: the engine SetText()s every registered duration string on display
-- updates, and an unfonted FontString hard-errors inside that engine call
-- (visibility is handled by AuraKit via SetShown).
local function ApplyUFText(button, d, style)
    local path = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("unitFrames")) or FALLBACK_FONT
    if d.duration then
        local fontKey = path .. "|" .. (style.cdTextSize or 10)
        if d.ufDurFont ~= fontKey then
            d.ufDurFont = fontKey
            EllesmereUI.ApplyIconTextFont(d.duration, path, style.cdTextSize or 10, "unitFrames")
        end
        local c = style.cdTextColor
        d.duration:SetTextColor(c and c.r or 1, c and c.g or 1, c and c.b or 1)
        -- Anchor change-guarded (stamp AFTER the calls): SetPoint with the
        -- button as the relative frame is policed by the 12.1 button access
        -- restriction while auras are secret; unchanged offsets must make
        -- zero button-involving calls so restyles stay live in-instance.
        local aKey = (style.cdOffX or 0) .. "|" .. (style.cdOffY or 0)
        if d.ufDurAnchor ~= aKey then
            d.duration:ClearAllPoints()
            d.duration:SetPoint("CENTER", button, "CENTER", style.cdOffX or 0, style.cdOffY or 0)
            d.ufDurAnchor = aKey
        end
    end
    if d.stack then
        local fontKey = path .. "|" .. (style.stackSize or 14)
        if d.ufStackFont ~= fontKey then
            d.ufStackFont = fontKey
            EllesmereUI.ApplyIconTextFont(d.stack, path, style.stackSize or 14, "unitFrames")
        end
        local c = style.stackColor
        d.stack:SetTextColor(c and c.r or 1, c and c.g or 1, c and c.b or 1)
        local sp = STACK_POINTS[style.stackPos or "bottomright"] or STACK_POINTS.bottomright
        local sKey = sp[1] .. "|" .. (sp[2] + (style.stackOffX or 0)) .. "|" .. (style.stackOffY or 0)
        if d.ufStackAnchor ~= sKey then
            d.stack:ClearAllPoints()
            d.stack:SetPoint(sp[1], button, sp[1], sp[2] + (style.stackOffX or 0), style.stackOffY or 0)
            d.ufStackAnchor = sKey
        end
    end
end

local function StyleKey(unit, base)
    return "uf:" .. unit .. ":" .. base
end

-- Settings fingerprints (same discipline as the RF containers file): every
-- engine setter is a dirty mark that costs real engine work even when the
-- value is unchanged, and a restyle touches every pre-created button of the
-- style (10-button engine batches per group add up fast). Reload paths
-- fingerprint what each pass reads and skip the work whose inputs did not
-- change. Numbers round to 2 decimals: scaled values carry float noise.
local ufFP = {}

local function FP(...)
    local n = select("#", ...)
    local t = {}
    for i = 1, n do
        local v = select(i, ...)
        if type(v) == "number" then
            t[i] = string.format("%.2f", v)
        else
            t[i] = tostring(v)
        end
    end
    return table.concat(t, "|")
end

local function CK(c)
    if not c then return "-" end
    return string.format("%.3f,%.3f,%.3f",
        c.r or c[1] or 0, c.g or c[2] or 0, c.b or c[3] or 0)
end

-- Fingerprint of a BUILT style table (BuildStyle is a pure function of the
-- settings, so hashing its scalar output covers every input, including the
-- boss-simple sizing and scale). Constant cooldown/cancel fields are omitted;
-- every user-configurable border scalar must participate so layer-only edits
-- schedule an immediate AuraKit restyle.
local function StyleTableFP(st, font)
    local tc = st.texCoord
    local b = st.border
    return FP(font, st.width, st.height, tc[1], tc[2], tc[3], tc[4],
        st.hideDurationText, st.cdTextSize, CK(st.cdTextColor), st.cdOffX, st.cdOffY,
        st.stackSize, CK(st.stackColor), st.stackPos, st.stackOffX, st.stackOffY,
        b and b.texture, b and b.size, b and b[1], b and b[2], b and b[3], b and b[4],
        b and b.offsetX, b and b.offsetY, b and b.shiftX, b and b.shiftY,
        b and b.behind, b and b.behindUnitFrame, b and b.unitFrameLevel)
end

-- Effective engine group key: own-only variants are SEPARATE groups
-- (filter strings are declaration-fixed, so "raid" and "raid + PLAYER"
-- cannot share one). Containers are never swapped: the ever-used variant
-- set accumulates, inactive variants sit at count 0.
local function EffKey(key, own)
    if own then return key .. "_o" end
    return key
end

-- Declares one class group (own-variant aware) and records it in the
-- element's declared-set registry. Used at creation and by the additive
-- reload path (AddAuraGroup on an existing container is combat-legal --
-- probe T1/T1b).
local function DeclareElementGroup(container, declared, styleKey, base, key, tokens, cand, own)
    local eff = EffKey(key, own)
    local ftokens = tokens
    if own then
        ftokens = {}
        for t = 1, #tokens do ftokens[t] = tokens[t] end
        ftokens[#ftokens + 1] = "PLAYER"
    end
    AK.AddGroupToContainer(container, {
        key = eff, filter = ftokens, maxFrameCount = 0, style = styleKey,
    })
    declared[eff] = { cand = cand or false }
end

-- Explicit either/or (never `cond and a or b`: a falsy setting must not fall
-- through to the other element's key).
local function Pick(isBuff, a, b)
    if isBuff then return a end
    return b
end

-- Boss "simple" side display: returns whether it is on and which side.
local function BossSimple(unit, base, s)
    if not unit:match("^boss") then return false, "none" end
    local mode
    if base == "HELPFUL" then
        mode = ns.GetBossSimpleBuffMode and ns.GetBossSimpleBuffMode(s) or "none"
    else
        mode = ns.GetBossSimpleDebuffMode and ns.GetBossSimpleDebuffMode(s) or "none"
    end
    return mode ~= "none", mode
end

-- Element pixel size; boss simple mode matches the frame's bar-stack height.
local function ElementSize(unit, base, s)
    local isBuff = (base == "HELPFUL")
    local size = Pick(isBuff, s.buffSize, s.debuffSize) or 22
    local simpleOn = BossSimple(unit, base, s)
    if simpleOn then
        local PP = EllesmereUI.PP
        local powerPos = s.powerPosition or "below"
        local powerH = 0
        if powerPos == "below" or powerPos == "above" then powerH = s.powerHeight or 0 end
        size = PP.Scale((s.healthHeight or 0) + powerH)
    end
    local cropped = Pick(isBuff, s.buffCropIcons, s.debuffCropIcons)
    local h = size
    if cropped then h = math.floor(size * AURA_CROP_HEIGHT + 0.5) end
    return size, h, cropped
end

local function BuildStyle(unit, base, s, unitFrame)
    local isBuff = (base == "HELPFUL")
    local size, h, cropped = ElementSize(unit, base, s)
    local p = Pick(isBuff, "buff", "debuff")

    -- Boss simple side displays read their own cooldown-text keys.
    local simpleOn = BossSimple(unit, base, s)
    local showCdKey, cdSizeKey = p .. "ShowCooldownText", p .. "CooldownTextSize"
    local cdSizeDefault = 10
    if simpleOn then
        showCdKey = "simple" .. p:gsub("^%l", string.upper) .. "ShowCooldownText"
        cdSizeKey = "simple" .. p:gsub("^%l", string.upper) .. "CooldownTextSize"
        cdSizeDefault = 14
    end

    return {
        width = size,
        height = h,
        texCoord = CropCoords(cropped, size, h, Pick(isBuff, s.buffIconZoom, s.debuffIconZoom)),
        border = {
            s.auraBorderR or 0, s.auraBorderG or 0, s.auraBorderB or 0, s.auraBorderA or 1,
            size = s.auraBorderSize or 1,
            texture = s.auraBorderTexture or "solid",
            offsetX = s.auraBorderTextureOffset,
            offsetY = s.auraBorderTextureOffsetY,
            shiftX = s.auraBorderTextureShiftX,
            shiftY = s.auraBorderTextureShiftY,
            behind = s.auraBorderBehind,
            behindUnitFrame = s.auraBorderBehindUnitFrame,
            unitFrameLevel = unitFrame and unitFrame:GetFrameLevel() or 1,
        },
        cooldownReverse = true,
        cooldownDrawEdge = false,
        noDefaultFonts = true,
        hideDurationText = not s[showCdKey],
        cdTextSize = s[cdSizeKey] or cdSizeDefault,
        cdTextColor = s[p .. "CooldownTextColor"],
        cdOffX = s[p .. "CooldownTextOffsetX"] or 0,
        cdOffY = s[p .. "CooldownTextOffsetY"] or 0,
        stackSize = s[p .. "StackTextSize"] or 14,
        stackColor = s[p .. "StackTextColor"],
        stackPos = s[p .. "StackTextPosition"],
        stackOffX = s[p .. "StackTextOffsetX"] or 0,
        stackOffY = s[p .. "StackTextOffsetY"] or 0,
        cancelButtons = (unit == "player" and isBuff) and "RightButtonUp" or nil,
        -- Dispel-type border recolor (per-unit debuffDispelBorder): the engine
        -- shows the ring only on typed (dispellable) debuffs and picks the
        -- dispel color itself -- the user palette cannot apply under secrecy
        -- (same documented delta as the RF debuff border).
        dispelBorder = (not isBuff and s.debuffDispelBorder) and true or nil,
        applyExtra = ApplyUFText,
    }
end

-- Container anchoring: mirrors the legacy element's SetPoint(ia, frame, fp,
-- ox + userX, oy + castbarPush + userY) with gap = 1.
local function AnchorContainer(container, frame, unit, base, s)
    local isBuff = (base == "HELPFUL")

    -- Boss simple side display: forced side anchoring flush with the frame
    -- top, growing away from the chosen edge, own offsets, no castbar push.
    local simpleOn, simpleMode = BossSimple(unit, base, s)
    if simpleOn then
        local ia, fp
        if simpleMode == "right" then ia, fp = "TOPLEFT", "TOPRIGHT" else ia, fp = "TOPRIGHT", "TOPLEFT" end
        local offX, offY
        if isBuff then
            offX, offY = ns.GetBossSimpleBuffOffset(s)
        else
            offX, offY = ns.GetBossSimpleDebuffOffset(s)
        end
        container:ClearAllPoints()
        container:SetPoint(ia, frame, fp, offX or 0, offY or 0)
        container:SetAuraLayoutAnchorPoint(ia)
        local gX = "LEFT"
        if simpleMode == "right" then gX = "RIGHT" end
        container:SetAuraLayoutGrowthDirection(FlowDir(gX), FlowDir("DOWN"))
        return simpleMode
    end

    local anchor = Pick(isBuff, s.buffAnchor, s.debuffAnchor)
    if anchor == nil then anchor = Pick(isBuff, "topleft", "none") end
    if anchor == "none" then return anchor end

    local growth = Pick(isBuff, s.buffGrowth, s.debuffGrowth)
    local ia, fp, ox, oy, gX, gY = ResolveLayout(anchor, growth)

    local cbOff = 0
    local showCb, cbH
    if unit == "player" then
        showCb, cbH = s.showPlayerCastbar, s.playerCastbarHeight
    else
        showCb, cbH = s.showCastbar, s.castbarHeight
    end
    if showCb and (anchor == "bottomleft" or anchor == "bottomright" or anchor == "left" or anchor == "right") then
        if not cbH or cbH <= 0 then cbH = 14 end
        cbOff = -cbH
    end

    local offX = Pick(isBuff, s.buffOffsetX, s.debuffOffsetX) or 0
    local offY = Pick(isBuff, s.buffOffsetY, s.debuffOffsetY) or 0

    container:ClearAllPoints()
    container:SetPoint(ia, frame, fp, ox + offX, oy + cbOff + offY)
    container:SetAuraLayoutAnchorPoint(ia)
    container:SetAuraLayoutGrowthDirection(FlowDir(gX), FlowDir(gY))

    return anchor
end

local function ApplyGroupConfig(container, unit, base, s, chain, own, declared)
    local PP = EllesmereUI.PP
    local isBuff = (base == "HELPFUL")
    local anyClass = #chain > 0

    local simpleOn = BossSimple(unit, base, s)

    local shown
    if isBuff then
        shown = (s.showBuffs ~= false) or simpleOn
    else
        shown = ((s.debuffAnchor or "none") ~= "none") or simpleOn
    end

    local num = 0
    if shown then
        num = Pick(isBuff, s.maxBuffs or 4, s.maxDebuffs or 28)
    end

    local size, h = ElementSize(unit, base, s)
    local spX, spY
    if unit:match("^boss") then
        -- Boss uses a single spacing value (its simple-display key when the
        -- simple mode is active).
        local sp
        if isBuff then sp = ns.GetBossBuffSpacing(s, simpleOn) else sp = ns.GetBossDebuffSpacing(s, simpleOn) end
        spX = PP.FromPixels(sp or 1)
        spY = spX
    else
        spX = PP.FromPixels(Pick(isBuff, s.buffSpacingX, s.debuffSpacingX) or 1)
        spY = PP.FromPixels(Pick(isBuff, s.buffSpacingY, s.debuffSpacingY) or 1)
    end

    local growth = Pick(isBuff, s.buffGrowth, s.debuffGrowth)
    if simpleOn then growth = "auto" end
    local maxPerRow = Pick(isBuff, s.buffMaxPerRow, s.debuffMaxPerRow)
    local cols = ResolveColumns(growth, num > 0 and num or 1, maxPerRow)
    local rowWidth = nil
    if cols then
        rowWidth = cols * size + (cols - 1) * spX + 0.4
    end
    container:SetAuraLayoutRowWidth(rowWidth)

    -- Candidate filters: (debuffs) the sated/always-hide excludes. Own Only
    -- lives in the group filter strings (see EffectiveOwnOnly), not here.
    local cand = nil
    if not isBuff then
        local ex = {}
        for id in pairs(ALWAYS_HIDE_DEBUFFS) do ex[id] = true end
        if not s.showLustDebuff then
            for id in pairs(SATED_DEBUFFS) do ex[id] = true end
        end
        cand = cand or {}
        cand.excludeSpellIDs = ex
    end

    local layout = { elementWidth = size, elementHeight = h, elementSpacingX = spX, elementSpacingY = spY }

    -- Active set = the CURRENT own-variant of "all" (when no classes are
    -- enabled) or of each enabled class. Every other declared group --
    -- disabled classes AND the opposite own-variants -- parks at count 0
    -- (declared sets only ever grow; setters run per declared key only).
    local active = {}
    if num > 0 then
        if anyClass then
            for i = 1, #chain do
                active[EffKey(chain[i].key, own)] = chain[i].cand or false
            end
        else
            active[EffKey("all", own)] = false
        end
    end
    for eff, info in pairs(declared) do
        if active[eff] ~= nil then
            container:SetAuraGroupMaxFrameCount(eff, num)
            local groupCand = cand
            if info.cand then
                -- Candidate-class groups carry their defining boolean on top
                -- of the shared candidates (fresh table: setter securecopies).
                groupCand = {}
                if cand then
                    for k, v in pairs(cand) do groupCand[k] = v end
                end
                groupCand[info.cand] = true
            end
            container:SetAuraGroupCandidateFilters(eff, groupCand)
            container:SetAuraGroupLayout(eff, layout)
        else
            container:SetAuraGroupMaxFrameCount(eff, 0)
        end
    end

    container:SetShown(shown)
    return shown
end

-- Fingerprint over every input AnchorContainer + ApplyGroupConfig read
-- (computed values like ElementSize and the pixel-scaled spacings capture
-- scale changes implicitly). The chain composition is covered separately by
-- entry.sig; a sig change swaps the container and forces this pass anyway.
local function CfgFP(unit, base, s)
    local PP = EllesmereUI.PP
    local isBuff = (base == "HELPFUL")
    local size, h = ElementSize(unit, base, s)
    local simpleOn, simpleMode = BossSimple(unit, base, s)
    local spX, spY
    if unit:match("^boss") then
        local sp
        if isBuff then sp = ns.GetBossBuffSpacing(s, simpleOn) else sp = ns.GetBossDebuffSpacing(s, simpleOn) end
        spX = PP.FromPixels(sp or 1)
        spY = spX
    else
        spX = PP.FromPixels(Pick(isBuff, s.buffSpacingX, s.debuffSpacingX) or 1)
        spY = PP.FromPixels(Pick(isBuff, s.buffSpacingY, s.debuffSpacingY) or 1)
    end
    local sOffX, sOffY = 0, 0
    if simpleOn then
        if isBuff then sOffX, sOffY = ns.GetBossSimpleBuffOffset(s) else sOffX, sOffY = ns.GetBossSimpleDebuffOffset(s) end
    end
    local showCb, cbH
    if unit == "player" then
        showCb, cbH = s.showPlayerCastbar, s.playerCastbarHeight
    else
        showCb, cbH = s.showCastbar, s.castbarHeight
    end
    return FP(size, h, spX, spY, simpleOn, simpleMode, sOffX, sOffY,
        Pick(isBuff, s.buffAnchor, s.debuffAnchor), Pick(isBuff, s.buffGrowth, s.debuffGrowth),
        Pick(isBuff, s.buffOffsetX, s.debuffOffsetX), Pick(isBuff, s.buffOffsetY, s.debuffOffsetY),
        showCb, cbH, Pick(isBuff, s.maxBuffs, s.maxDebuffs),
        Pick(isBuff, s.buffMaxPerRow, s.debuffMaxPerRow), s.showBuffs, s.showLustDebuff)
end

------------------------------------------------------------------------------
-- Player dispel overlay -> dispel slots
--
-- One bare slot per dispel type, filtered engine-side; each renders our
-- overlay texture pre-colored from the user palette, so the display works
-- while auras are secret without the addon ever reading dispel data. The
-- engine shows/hides the slot button; the overlay is its child.
-- Priority when multiple debuff types are present: fixed layer order
-- (Magic on top), replacing the old first-by-scan-index behavior.
------------------------------------------------------------------------------

local DISPEL_SLOTS = {
    { key = "magic",   colorKey = "dispelColorMagic",   fallback = { 0.349, 0.475, 1.0 },  level = 5 },
    { key = "curse",   colorKey = "dispelColorCurse",   fallback = { 0.636, 0.0, 0.64 },   level = 4 },
    { key = "disease", colorKey = "dispelColorDisease", fallback = { 0.671, 0.384, 0.098 }, level = 3 },
    { key = "poison",  colorKey = "dispelColorPoison",  fallback = { 0.0, 0.706, 0.286 },  level = 2 },
    { key = "bleed",   colorKey = "dispelColorBleed",   fallback = { 0.75, 0.15, 0.15 },   level = 1 },
}
local DISPEL_TYPE_TOKENS = { magic = "Magic", curse = "Curse", disease = "Disease", poison = "Poison", bleed = "Bleed" }
local GRADIENT_TEXTURE = "Interface\\AddOns\\EllesmereUI\\media\\textures\\gradient-tb.tga"
local GRADIENT_SHARP_TEXTURE = "Interface\\AddOns\\EllesmereUI\\media\\textures\\gradient-sharp.tga"

-- applyExtra for dispel slots: builds/updates the overlay texture from the
-- style (mode, color, opacity, health refs). Runs at init and every Restyle.
local function ApplyDispelSlotStyle(button, d, style)
    local health = style.healthFrame
    if not health then return end

    if not d.overlay then
        d.overlay = button:CreateTexture(nil, "ARTWORK", nil, 3)
    end
    local tex = d.overlay
    local c = style.color
    local alpha = (style.opacity or 100) / 100

    -- Change-guarded, stamped AFTER the call: SetFrameLevel on the slot
    -- button is denied while auras are secret (12.1 access restriction).
    -- At creation this runs inside the initializeFrame window (always
    -- legal); on later restyles the level rarely changes, and a denied
    -- attempt throws so the worker defers this key to the lift re-queue.
    local lvl = health:GetFrameLevel() + 1 + (style.level or 1)
    if d.lvl ~= lvl then
        button:SetFrameLevel(lvl)
        d.lvl = lvl
    end

    tex:ClearAllPoints()
    if style.mode == "gradient" or style.mode == "gradient_sharp" then
        tex:SetAllPoints(health)
        tex:SetTexture(style.mode == "gradient_sharp" and GRADIENT_SHARP_TEXTURE or GRADIENT_TEXTURE)
        tex:SetVertexColor(c.r, c.g, c.b, alpha)
    elseif style.mode == "fill" then
        local fillTex = health.GetStatusBarTexture and health:GetStatusBarTexture()
        tex:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
        if fillTex then
            tex:SetPoint("BOTTOMRIGHT", fillTex, "BOTTOMRIGHT", 0, 0)
        else
            tex:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
        end
        tex:SetColorTexture(c.r, c.g, c.b, alpha)
        tex:SetVertexColor(1, 1, 1, 1)
    else -- "full"
        tex:SetAllPoints(health)
        tex:SetColorTexture(c.r, c.g, c.b, alpha)
        tex:SetVertexColor(1, 1, 1, 1)
    end
end

local function DispelStyleKey(slotKey)
    return "uf:player:dispel:" .. slotKey
end

local function BuildDispelStyles(frame)
    local p = ns.UF_GetProfile and ns.UF_GetProfile()
    if not p then return "none" end
    local mode = p.dispelOverlay or "none"
    -- "Only Dispellable by You": slot filters are fixed at declaration and
    -- containers are never swapped (engine buttons leak), so BOTH filter
    -- variants exist as slots from creation and the INACTIVE variant is
    -- styled to opacity 0. Toggling the option only restyles.
    local byMe = p.dispelOverlayByMe == true
    local op = p.dispelOverlayOpacity or 100
    for i = 1, #DISPEL_SLOTS do
        local slot = DISPEL_SLOTS[i]
        local col = p[slot.colorKey]
        local color = { r = col and col.r or slot.fallback[1], g = col and col.g or slot.fallback[2], b = col and col.b or slot.fallback[3] }
        AK.styles[DispelStyleKey(slot.key)] = {
            width = 1, height = 1,
            noRegions = true,
            mode = mode,
            color = color,
            opacity = byMe and 0 or op,
            level = slot.level,
            healthFrame = frame.Health,
            applyExtra = ApplyDispelSlotStyle,
        }
        AK.styles[DispelStyleKey(slot.key .. "_byme")] = {
            width = 1, height = 1,
            noRegions = true,
            mode = mode,
            color = color,
            opacity = byMe and op or 0,
            level = slot.level,
            healthFrame = frame.Health,
            applyExtra = ApplyDispelSlotStyle,
        }
    end
    return mode
end

local function CreateDispelSlots(frame, entry)
    local mode = BuildDispelStyles(frame)

    local container = shellStash.dispel
    if container then
        -- Adopt the pre-born shell (combat-safe: parent/point on our frame).
        shellStash.dispel = nil
        container:SetParent(frame)
        container:ClearAllPoints()
        container:SetPoint("CENTER", frame, "CENTER")
    else
        container = AK.CreateContainerShell(frame, {
            point = { "CENTER", frame, "CENTER" },
        })
    end

    for i = 1, #DISPEL_SLOTS do
        local slot = DISPEL_SLOTS[i]
        local function ParkSlot(slotButton)
            -- Park the slot button on the health bar center (the overlay
            -- textures anchor to the health bar independently). Anchored
            -- HERE, inside the creation window: SetPoint on the returned
            -- button is denied while auras are secret (12.1 button
            -- access restriction), and this build path runs on
            -- in-instance reloads.
            slotButton:SetPoint("CENTER", frame.Health or frame, "CENTER")
        end
        AK.AddSlotToContainer(container, {
            key = slot.key,
            filter = { "HARMFUL" },
            candidateFilters = { includeDispelTypes = { [DISPEL_TYPE_TOKENS[slot.key]] = true } },
            style = DispelStyleKey(slot.key),
            extraInit = ParkSlot,
        })
        -- "Only Dispellable by You" variant: identical slot with the engine
        -- by-me filter token added. Declared upfront -- slot filters cannot
        -- change after declaration -- and mutually exclusive with the plain
        -- slot via style opacity (BuildDispelStyles zeroes the inactive one).
        AK.AddSlotToContainer(container, {
            key = slot.key .. "_byme",
            filter = { "HARMFUL", "RAID_PLAYER_DISPELLABLE" },
            candidateFilters = { includeDispelTypes = { [DISPEL_TYPE_TOKENS[slot.key]] = true } },
            style = DispelStyleKey(slot.key .. "_byme"),
            extraInit = ParkSlot,
        })
    end
    AK.FinishContainer(container, "player")
    entry.dispel = container

    container:SetShown(mode ~= "none")
    ns.UF_DispelOverlayDisabled = true
end

local function DispelFP(p)
    return FP(p.dispelOverlay, p.dispelOverlayOpacity, p.dispelOverlayByMe == true,
        CK(p.dispelColorMagic), CK(p.dispelColorCurse),
        CK(p.dispelColorDisease), CK(p.dispelColorPoison), CK(p.dispelColorBleed))
end

local function ReloadDispelSlots(frame, entry)
    if not entry.dispel then return end
    local p = ns.UF_GetProfile and ns.UF_GetProfile()
    if not p then return end
    local v = DispelFP(p)
    if ufFP.dispel ~= v then
        ufFP.dispel = v
        BuildDispelStyles(frame)
        for i = 1, #DISPEL_SLOTS do
            AK.RestyleSoon(DispelStyleKey(DISPEL_SLOTS[i].key))
            AK.RestyleSoon(DispelStyleKey(DISPEL_SLOTS[i].key .. "_byme"))
        end
    end
    entry.dispel:SetShown((p.dispelOverlay or "none") ~= "none")
end

-- Options-panel poke (via ns.UpdatePlayerDispelOverlay): re-run the
-- fingerprinted dispel reload for the live player frame so dropdown/cog
-- edits apply without waiting for a full container pass.
function ns.UF_ReloadPlayerDispelSlots()
    local entry = registry.player
    if entry and entry.frame then
        ReloadDispelSlots(entry.frame, entry)
    end
end

-- Boss preview (fake auras) suppresses the real containers; ReloadFrames
-- restores them when the preview ends.
function ns.UF_HideAuraContainers(frame)
    for _unitKey, entry in pairs(registry) do
        if entry.frame == frame then
            if entry.buffs then entry.buffs:Hide() end
            if entry.debuffs then entry.debuffs:Hide() end
            -- Hidden outside the fingerprinted flow: the next reload must
            -- re-drive visibility even if no setting changed.
            entry.previewHid = true
            return
        end
    end
end

function ns.UF_ReloadAuraContainers(frame, unit)
    local s = SettingsFor(unit)
    local entry = registry[unit]
    if not s or not entry then return end

    if unit:match("^boss") and ns._bossPreviewActive then
        if entry.buffs then entry.buffs:Hide() end
        if entry.debuffs then entry.debuffs:Hide() end
        entry.previewHid = true
        return
    end

    local font = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("unitFrames")) or ""
    -- Containers hidden outside the fingerprinted flow (boss preview) must
    -- re-drive anchor/config/visibility even with matching fingerprints.
    local forceCfg = entry.previewHid and true or false
    entry.previewHid = nil

    for base, field in pairs({ HELPFUL = "buffs", HARMFUL = "debuffs" }) do
        local key = StyleKey(unit, base)
        local st = ufFP[key]
        if not st then st = {}; ufFP[key] = st end

        -- Restyle only when the built style actually differs; the deferred
        -- time-sliced restyler spreads the button decoration work out.
        local style = BuildStyle(unit, base, s, entry.frame)
        local styleV = StyleTableFP(style, font)
        if st.style ~= styleV then
            st.style = styleV
            AK.styles[key] = style
            AK.RestyleSoon(key)
        end

        -- Groups are ADDITIVE and the container is NEVER swapped: a changed
        -- class set / Own Only declares any missing (variant) groups on the
        -- existing container (combat-legal -- probe T1/T1b), and the config
        -- pass zeroes whatever fell out of the active set. The old swap
        -- path permanently leaked a 10-button batch per group per toggle
        -- (engine frames are never freed).
        local own = EffectiveOwnOnly(unit, base, s)
        local chain = BuildChain(base, base == "HELPFUL", s)
        local sig = ChainSignature(chain) .. (own and "|own" or "")
        local force = forceCfg
        local container = entry[field]
        local declared = (entry.groups and entry.groups[field]) or {}
        -- Additive declaration requires the REAL registry: declaring into a
        -- fallback table would lose track and double-declare next change.
        if entry.sig[field] ~= sig and container and entry.groups then
            entry.sig[field] = sig
            if not declared[EffKey("all", own)] then
                DeclareElementGroup(container, declared, key, base, "all", { base }, nil, own)
            end
            for i = 1, #chain do
                local c = chain[i]
                if not declared[EffKey(c.key, own)] then
                    DeclareElementGroup(container, declared, key, base, c.key, c.tokens, c.cand, own)
                end
            end
            force = true
        end

        if container then
            local cfgV = CfgFP(unit, base, s)
            if force or st.cfg ~= cfgV then
                st.cfg = cfgV
                AnchorContainer(container, frame, unit, base, s) -- self-skips on anchor "none"
                ApplyGroupConfig(container, unit, base, s, chain, own, declared)
            end
        end
    end

    if unit == "player" then
        ReloadDispelSlots(frame, entry)
    end
end

-- Dynamic unit tokens ("target", "focus", "bossN") re-resolve silently: the
-- engine only re-parses on UNIT_AURA or show/hide, so a target swap while the
-- frame stays shown would display the previous unit's auras. Blizzard's own
-- container exposes UpdateAllAuras for exactly this; poke it on unit changes.
local function RefreshUnit(unitKey)
    local entry = registry[unitKey]
    if not entry then return end
    if entry.buffs then entry.buffs:UpdateAllAuras() end
    if entry.debuffs then entry.debuffs:UpdateAllAuras() end
    if entry.dispel then entry.dispel:UpdateAllAuras() end
end

-- TEMPORARY 12.1 workaround: contextual pings on any addon unit frame hit a
-- forbidden SendUnitPing (Blizzard's PingableType_UnitFrameMixin reads the
-- insecurely-set frame.unit, so the derived GUID is tainted). Stripping the
-- ping-receiver attribute makes the ping hit-test skip our frames entirely,
-- so pings fall through to a world ping instead of erroring. No oUF edits.
-- REMOVE when upstream is fixed (tracked in MIDNIGHT_AURA_MIGRATION.md).
local EXTRA_PING_FRAMES = {
    "EllesmereUIUnitFrames_Pet", "EllesmereUIUnitFrames_TargetTarget", "EllesmereUIUnitFrames_FocusTarget",
}

local function StripPingReceiver(frame)
    if frame and not InCombatLockdown() then
        frame:SetAttribute("ping-receiver", nil)
    end
end

local unitWatcher = CreateFrame("Frame")
unitWatcher:RegisterEvent("PLAYER_TARGET_CHANGED")
unitWatcher:RegisterEvent("PLAYER_FOCUS_CHANGED")
unitWatcher:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
unitWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
unitWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
unitWatcher:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        -- One-shot sweep for the oUF frames without containers (pet/ToT/FoT).
        unitWatcher:UnregisterEvent("PLAYER_ENTERING_WORLD")
        for i = 1, #EXTRA_PING_FRAMES do
            StripPingReceiver(_G[EXTRA_PING_FRAMES[i]])
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        RefreshUnit("target")
    elseif event == "PLAYER_FOCUS_CHANGED" then
        RefreshUnit("focus")
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Filter-set swaps requested during combat run now.
        for unitKey, entry in pairs(registry) do
            if entry.pendingSwap then
                entry.pendingSwap = nil
                ns.UF_ReloadAuraContainers(entry.frame, unitKey)
            end
        end
    else
        for i = 1, 5 do RefreshUnit("boss" .. i) end
    end
end)

-- Called by the main file at the end of every real (throttled) reload pass.
-- A direct call, not a wrap: ns.ReloadFrames is a throttle-arming stub that
-- gets (re)assigned during login setup, which makes wrap timing unreliable.
function ns.UF_ReloadAllAuraContainers()
    for unitKey, entry in pairs(registry) do
        if entry.frame then
            ns.UF_ReloadAuraContainers(entry.frame, unitKey)
        end
    end
end

-- Builds one element container carrying the "all" group plus the given class
-- chain, recording every declared group in `declared`. Own Only appends the
-- PLAYER token to every group's filter string (via the variant key).
function CreateElementContainer(frame, unit, base, chain, own, declared)
    local styleKey = StyleKey(unit, base)
    local field = "debuffs"
    if base == "HELPFUL" then field = "buffs" end
    local stash = shellStash[unit]
    local container = stash and stash[field]
    if container then
        -- Adopt the pre-born shell (combat-safe: parent/point on our frame).
        stash[field] = nil
        container:SetParent(frame)
        container:ClearAllPoints()
        container:SetPoint("CENTER", frame, "CENTER") -- provisional; reload anchors properly
    else
        container = AK.CreateContainerShell(frame, {
            point = { "CENTER", frame, "CENTER" }, -- provisional; reload anchors properly
        })
    end
    DeclareElementGroup(container, declared, styleKey, base, "all", { base }, nil, own)
    for i = 1, #chain do
        local c = chain[i]
        DeclareElementGroup(container, declared, styleKey, base, c.key, c.tokens, c.cand, own)
    end
    AK.FinishContainer(container, unit)
    return container
end

-- Builds one unit's containers. Runs from the time-sliced worker below,
-- never synchronously from frame spawn: every group declaration eagerly
-- creates a 10-button engine batch through AuraKit's full region
-- initializer (parent-addon billed), and the spawn-time builds for all
-- eight units stacked ~300 engine buttons into the login frames.
local function BuildUnitContainers(frame, unit)
    local s = SettingsFor(unit)
    if not (AK and s) then return end
    if registry[unit] then return end

    -- Container FRAMES cannot be born in combat (probe T3 zombie). With the
    -- PLAYER_LOGIN stash intact this build is pure adds on existing shells
    -- (combat-legal); if any needed shell is missing while locked down,
    -- hold the whole unit until regen rather than half-building it.
    if InCombatLockdown() then
        local stash = shellStash[unit]
        if not (stash and stash.buffs and stash.debuffs)
            or (unit == "player" and not shellStash.dispel) then
            return "hold"
        end
    end

    -- Styles must exist before group declaration: initializeFrame consumes
    -- them for the pre-created button batch. Prime their fingerprints too:
    -- the creation-tail reload just below would otherwise queue a restyle
    -- of buttons that were decorated from these exact tables.
    local font = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("unitFrames")) or ""
    for _, base in ipairs({ "HELPFUL", "HARMFUL" }) do
        local key = StyleKey(unit, base)
        local style = BuildStyle(unit, base, s, frame)
        AK.styles[key] = style
        ufFP[key] = { style = StyleTableFP(style, font) }
    end

    local entry = { frame = frame, sig = {}, groups = { buffs = {}, debuffs = {} } }
    registry[unit] = entry

    for base, field in pairs({ HELPFUL = "buffs", HARMFUL = "debuffs" }) do
        local own = EffectiveOwnOnly(unit, base, s)
        local chain = BuildChain(base, base == "HELPFUL", s)
        entry[field] = CreateElementContainer(frame, unit, base, chain, own, entry.groups[field])
        entry.sig[field] = ChainSignature(chain) .. (own and "|own" or "")
    end

    if unit == "player" then
        CreateDispelSlots(frame, entry)
        -- Prime the dispel fingerprint: creation just applied these exact
        -- settings, so the creation-tail reload below must not queue a
        -- redundant restyle (harmless noise OOC, but denied button writes
        -- when built under restriction -- the in-instance /reload case).
        local p = ns.UF_GetProfile and ns.UF_GetProfile()
        if p then ufFP.dispel = DispelFP(p) end
    end

    ns.UF_ReloadAuraContainers(frame, unit)
end

-- Deferred through the shared AuraKit build scheduler (budgeted per frame,
-- never ticks during loading screens; combat-runnable via the stash
-- shells). One job per unit is fine-grained enough here: an element
-- container carries only the enabled filter classes (typically 1-2
-- groups), so a unit's whole build is a couple of 10-button engine
-- batches. The return propagates BuildUnitContainers' "hold" verdict.
function ns.UF_CreateAuraContainers(frame, unit)
    AK = AK or EllesmereUI.AuraKit
    if not (AK and AK.QueueBuildJob) then return end
    StripPingReceiver(frame) -- temporary 12.1 ping workaround (see above)
    if registry[unit] then return end
    AK.QueueBuildJob(function()
        return BuildUnitContainers(frame, unit)
    end, "uf:unit")
end
