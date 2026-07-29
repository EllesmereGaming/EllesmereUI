-------------------------------------------------------------------------------
--  EllesmereUIBlizzardSkin_DragonRiding.lua - Skyriding HUD
-------------------------------------------------------------------------------
local _, ns = ...

-- Upvalues
local floor, min, max, abs = math.floor, math.min, math.max, math.abs
local format = string.format
local IsMounted = IsMounted
local C_PlayerInfo = C_PlayerInfo
local C_Spell = C_Spell
local C_Timer = C_Timer
local CreateFrame = CreateFrame
local UnitAffectingCombat = UnitAffectingCombat
local GetTime = GetTime

-- Bar texture table (shared with options via ns)
local EDR_TEX_BASE = "Interface\\AddOns\\EllesmereUI\\media\\textures\\"
ns.EDR_BAR_TEXTURES = {
    ["none"]          = nil,
    ["melli"]         = EDR_TEX_BASE .. "melli.tga",
    ["beautiful"]     = EDR_TEX_BASE .. "beautiful.tga",
    ["plating"]       = EDR_TEX_BASE .. "plating.tga",
    ["atrocity"]      = EDR_TEX_BASE .. "atrocity.tga",
    ["divide"]        = EDR_TEX_BASE .. "divide.tga",
    ["glass"]         = EDR_TEX_BASE .. "glass.tga",
    ["fade-right"]    = EDR_TEX_BASE .. "fade-right.tga",
    ["thin-line-top"]    = EDR_TEX_BASE .. "thin-line-top.tga",
    ["thin-line-bottom"] = EDR_TEX_BASE .. "thin-line-bottom.tga",
    ["fade"]          = EDR_TEX_BASE .. "fade.tga",
    ["gradient-lr"]   = EDR_TEX_BASE .. "gradient-lr.tga",
    ["gradient-rl"]   = EDR_TEX_BASE .. "gradient-rl.tga",
    ["gradient-bt"]   = EDR_TEX_BASE .. "gradient-bt.tga",
    ["gradient-tb"]   = EDR_TEX_BASE .. "gradient-tb.tga",
    ["matte"]         = EDR_TEX_BASE .. "matte.tga",
    ["sheer"]         = EDR_TEX_BASE .. "sheer.tga",
}

-- Constants
local SPELL = {
    SKYWARD_ASCENT  = 372610,
    SECOND_WIND     = 425782,
    WHIRLING_SURGE  = 361584,
}
local SKYRIDING_PIPS  = 6
local SECONDWIND_PIPS = 3
local BASE_RUN_SPEED  = 7.0

-- Database defaults
local DB_DEFAULTS = {
    profile = {
        enabled          = false,
        hideInCombat     = false,

        width            = 240,
        speedHeight      = 14,
        skyridingHeight  = 10,
        secondWindHeight = 6,
        gap              = 2,
        stackSpacing     = 2,

        borderThickness = 0,
        borderColor     = { r = 0.0, g = 0.0, b = 0.0, a = 1.0 },

        maxSpeed          = 1300,
        thrillThreshold   = 789,
        thrillColorToggle = true,
        normalColor       = { r = 0.055, g = 0.667, b = 0.761, a = 1.0 },
        thrillColor       = { r = 0.902, g = 0.494, b = 0.133, a = 1.0 },
        speedBarBg        = { r = 0.10, g = 0.10, b = 0.10, a = 0.80 },
        tickColor         = { r = 1.00, g = 1.00, b = 1.00, a = 0.50 },

        speedText = {
            enabled = true,
            justify = "CENTER",
            size    = 12,
            offsetX = 0,
            offsetY = 0,
        },

        skyridingFilled  = { r = 0.047, g = 0.824, b = 0.624, a = 1.0 },
        skyridingBg      = { r = 0.10, g = 0.10, b = 0.10, a = 0.80 },

        secondWindFilled = { r = 0.902, g = 0.706, b = 0.133, a = 1.0 },
        secondWindBg     = { r = 0.10, g = 0.10, b = 0.10, a = 0.80 },

        whirlingSurgeText = {
            enabled = true,
            justify = "CENTER",
            size    = 12,
            offsetX = 0,
            offsetY = 0,
        },

        unlockPos = nil,
    },
}

-- State
local db
local rootFrame, speedBar, stackFrame, swFrame, wsIcon
local skyridingDirty  = true
local secondWindDirty = true
local whirlingDirty   = true
local lastSpeedApplied  = -1
local lastCdStart, lastCdDur = -1, -1
local lastSkyCur, lastSkyProgress = -1, -1
local lastSwCur,  lastSwProgress  = -1, -1
local UPDATE_THROTTLE = 1 / 60
local elapsed         = 0
local smoothedSpeed   = 0
local SPEED_EMA_ALPHA = 0.25
local evtFrame        -- event frame (created on first enable)
local _spellEventsRegistered = false

-- Returns true when the module should be hard-disabled (M+ or raid instance).
-- No frames shown, no events processed, no OnUpdate.
local function IsInLockedContent()
    if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
       and C_ChallengeMode.IsChallengeModeActive() then
        return true
    end
    local _, instanceType = IsInInstance()
    if instanceType == "raid" or instanceType == "party" then
        return true
    end
    return false
end

local function GetSkyridingSpeed()
    local isGliding, _, forwardSpeed = C_PlayerInfo.GetGlidingInfo()
    if not isGliding then
        smoothedSpeed = smoothedSpeed * (1 - SPEED_EMA_ALPHA)
        return false, smoothedSpeed
    end
    smoothedSpeed = smoothedSpeed + SPEED_EMA_ALPHA * ((forwardSpeed or 0) - smoothedSpeed)
    return true, smoothedSpeed
end

-- Forward declarations
local function Build() end
local function Rebuild() end
local function Redraw() end
local function UpdateVisibility() end
local function OnUpdate() end
local function ApplyPos() end
local function RegisterUnlockElements() end

-- Register/unregister high-frequency spell events based on HUD visibility.
-- These fire for ALL spells globally, so we only listen when actively showing.
local function RegisterSpellEvents()
    if _spellEventsRegistered or not evtFrame then return end
    evtFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
    evtFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    _spellEventsRegistered = true
end
local function UnregisterSpellEvents()
    if not _spellEventsRegistered or not evtFrame then return end
    evtFrame:UnregisterEvent("SPELL_UPDATE_CHARGES")
    evtFrame:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
    _spellEventsRegistered = false
end

-------------------------------------------------------------------------------
--  Visibility
-------------------------------------------------------------------------------
local function IsOnSkyridingMount()
    if not EllesmereUI.IsPlayerMountedLike() then return false end
    local _, canGlide = C_PlayerInfo.GetGlidingInfo()
    return canGlide == true
end

function UpdateVisibility()
    if not rootFrame then return end
    local p = db and db.profile
    if not p or not p.enabled or IsInLockedContent() then
        rootFrame:Hide()
        rootFrame:SetScript("OnUpdate", nil)
        UnregisterSpellEvents()
        return
    end
    if EllesmereUI and EllesmereUI._unlockActive then
        rootFrame:Show()
        rootFrame:SetScript("OnUpdate", OnUpdate)
        RegisterSpellEvents()
        return
    end
    local onSky = IsOnSkyridingMount()
    local hideCombat = p.hideInCombat and UnitAffectingCombat("player")
    local visible = onSky and not hideCombat
    rootFrame:SetShown(visible)
    if visible then
        rootFrame:SetScript("OnUpdate", OnUpdate)
        RegisterSpellEvents()
    else
        rootFrame:SetScript("OnUpdate", nil)
        UnregisterSpellEvents()
    end
end

-- Re-check real visibility when Unlock Mode exits. UpdateVisibility()
-- force-shows the HUD while EllesmereUI._unlockActive is true (so it can be
-- edited even off-mount), but nothing previously re-ran it on exit, so
-- dismounting during Unlock Mode left it stuck visible until an unrelated
-- mount/dismount happened to call UpdateVisibility() again. Called from
-- EUI_UnlockMode.lua's exit path, matching the Quest Tracker's same pattern.
_G._EDR_UpdateVisibility = function()
    UpdateVisibility()
end

-------------------------------------------------------------------------------
--  OnUpdate
-------------------------------------------------------------------------------
local function ApplyPipRow(pips, pipCount, cur, maxC, progress,
                            lastCur, lastProgress, filled, bgAlpha)
    if cur ~= lastCur then
        for i = 1, pipCount do
            local pip = pips[i]
            if i <= cur then
                pip:SetValue(1)
                pip:SetStatusBarColor(filled.r, filled.g, filled.b, 1)
            elseif i == cur + 1 and cur < maxC then
                pip:SetValue(progress)
                pip:SetStatusBarColor(filled.r, filled.g, filled.b, bgAlpha)
            else
                pip:SetValue(0)
                pip:SetStatusBarColor(filled.r, filled.g, filled.b, 1)
            end
        end
        return cur, progress
    elseif cur < maxC and abs(progress - lastProgress) > 0.005 then
        local pip = pips[cur + 1]
        if pip then pip:SetValue(progress) end
        return cur, progress
    end
    return lastCur, lastProgress
end

local function FormatSpeedText(speedPct)
    return format("%d%%", floor(speedPct + 0.5))
end

local function FormatCooldownText(remaining)
    if remaining >= 10 then return format("%d", floor(remaining + 0.5))
    elseif remaining >= 1 then return format("%d", floor(remaining))
    else return format("%.1f", remaining) end
end

function OnUpdate(self, dt)
    elapsed = elapsed + dt
    if elapsed < UPDATE_THROTTLE then return end
    elapsed = 0

    local p = db.profile

    local _, curSpeed = GetSkyridingSpeed()
    local speedPct = curSpeed / BASE_RUN_SPEED * 100
    local frac = (p.maxSpeed > 0) and (speedPct / p.maxSpeed) or 0
    frac = max(0, min(1, frac))
    if frac ~= lastSpeedApplied then
        speedBar:SetValue(frac)
        if p.speedText.enabled ~= false then
            speedBar.text:SetText(FormatSpeedText(speedPct))
        end
        local aboveThrill = (speedPct >= (p.thrillThreshold or 0))
        local c = (p.thrillColorToggle and aboveThrill) and p.thrillColor or p.normalColor
        speedBar:SetStatusBarColor(c.r, c.g, c.b, c.a)
        lastSpeedApplied = frac
    end

    if skyridingDirty then
        local info = C_Spell.GetSpellCharges(SPELL.SKYWARD_ASCENT)
        local cur  = info and info.currentCharges or 0
        local maxC = info and info.maxCharges or SKYRIDING_PIPS
        local progress = 0
        if info and info.cooldownDuration and info.cooldownDuration > 0 then
            local e = GetTime() - (info.cooldownStartTime or 0)
            progress = max(0, min(1, e / info.cooldownDuration))
        end
        lastSkyCur, lastSkyProgress = ApplyPipRow(
            stackFrame.pips, SKYRIDING_PIPS, cur, maxC, progress,
            lastSkyCur, lastSkyProgress, p.skyridingFilled, 0.4)
        skyridingDirty = (cur < maxC)
    end

    if secondWindDirty then
        local info = C_Spell.GetSpellCharges(SPELL.SECOND_WIND)
        local cur  = info and info.currentCharges or 0
        local maxC = info and info.maxCharges or SECONDWIND_PIPS
        local progress = 0
        if info and info.cooldownDuration and info.cooldownDuration > 0 then
            local e = GetTime() - (info.cooldownStartTime or 0)
            progress = max(0, min(1, e / info.cooldownDuration))
        end
        lastSwCur, lastSwProgress = ApplyPipRow(
            swFrame.pips, SECONDWIND_PIPS, cur, maxC, progress,
            lastSwCur, lastSwProgress, p.secondWindFilled, 0.4)
        secondWindDirty = (cur < maxC)
    end

    if whirlingDirty then
        local info = C_Spell.GetSpellCooldown(SPELL.WHIRLING_SURGE)
        local start = info and info.startTime or 0
        local dur   = info and info.duration  or 0
        if dur > 1.5 then
            if start ~= lastCdStart or dur ~= lastCdDur then
                wsIcon.cd:SetCooldown(start, dur)
                lastCdStart, lastCdDur = start, dur
            end
            local remaining = start + dur - GetTime()
            if remaining > 0 then
                if p.whirlingSurgeText.enabled ~= false then
                    wsIcon.text:SetText(FormatCooldownText(remaining))
                end
                whirlingDirty = true
            else
                wsIcon.text:SetText("")
                whirlingDirty = false
            end
        else
            if lastCdDur ~= 0 then
                wsIcon.cd:Clear()
                wsIcon.text:SetText("")
                lastCdStart, lastCdDur = 0, 0
            end
            whirlingDirty = false
        end
    end
end

-------------------------------------------------------------------------------
--  Helpers
-------------------------------------------------------------------------------
local function ApplyFont(fs, size)
    if not fs then return end
    local font = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("blizzardSkin") or "Fonts/FRIZQT__.TTF"
    local flag = EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag("blizzardSkin") or ""
    if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(fs, flag == "") end
    fs:SetFont(font, size or 12, flag)
end

local function CreateSolidTexture(parent, layer, sublevel, r, g, b, a)
    local tex = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel or 0)
    tex:SetColorTexture(r or 0, g or 0, b or 0, a or 1)
    tex:SetSnapToPixelGrid(false)
    tex:SetTexelSnappingBias(0)
    return tex
end

local borderedFrames = {}

local function EnsureBorder(frame)
    if not frame or frame._edrBorderAdded then return end
    if not (EllesmereUI and EllesmereUI.PP and EllesmereUI.PP.CreateBorder) then return end
    EllesmereUI.PP.CreateBorder(frame, 0, 0, 0, 1, 1, "OVERLAY", 7)
    frame._edrBorderAdded = true
    borderedFrames[#borderedFrames + 1] = frame
end

local function ApplyBordersAll()
    local PP = EllesmereUI and EllesmereUI.PP
    if not PP then return end
    local p = db.profile
    local c = p.borderColor
    local thick = p.borderThickness or 0
    for _, f in ipairs(borderedFrames) do
        if thick > 0 then
            PP.UpdateBorder(f, thick, c.r, c.g, c.b, c.a)
            PP.ShowBorder(f)
        else
            PP.HideBorder(f)
        end
    end
end

local function CreateSpeedBar(parent)
    local f = CreateFrame("StatusBar", nil, parent)
    f:SetMinMaxValues(0, 1)
    f:SetValue(0)
    f:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    f.bg = CreateSolidTexture(f, "BACKGROUND", 0)
    f.bg:SetAllPoints(f)
    f.tick = CreateSolidTexture(f, "OVERLAY", 5)
    f.text = f:CreateFontString(nil, "OVERLAY")
    return f
end

local function CreateStackFrame(parent, pipCount)
    local f = CreateFrame("Frame", nil, parent)
    f.pips = {}
    for i = 1, pipCount do
        local pip = CreateFrame("StatusBar", nil, f)
        pip:SetMinMaxValues(0, 1)
        pip:SetValue(0)
        pip:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        pip.bg = CreateSolidTexture(pip, "BACKGROUND", 0)
        pip.bg:SetAllPoints(pip)
        f.pips[i] = pip
    end
    return f
end

local function CreateWhirlingSurgeIcon(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints(f)
    local info = C_Spell.GetSpellInfo(SPELL.WHIRLING_SURGE)
    local iconFile = info and info.iconID or 135860
    f.tex:SetTexture(iconFile)
    f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints(f)
    f.cd:SetDrawEdge(false)
    f.cd:SetHideCountdownNumbers(true)
    f.textFrame = CreateFrame("Frame", nil, f)
    f.textFrame:SetAllPoints(f)
    f.textFrame:SetFrameLevel(f.cd:GetFrameLevel() + 1)
    f.text = f.textFrame:CreateFontString(nil, "OVERLAY")
    return f
end

-------------------------------------------------------------------------------
--  Build / Rebuild / Redraw
-------------------------------------------------------------------------------
local function LayoutPips(frame, pipCount, width, height, spacing)
    -- Distribute in whole PHYSICAL-pixel units (PP.mult), not whole
    -- UI-coordinate units. 1 UI-unit only equals 1 physical pixel at the
    -- "pixel perfect" scale -- at any other UI Scale, flooring to whole
    -- UI-units left a fractional remainder unassigned, so the last pip fell
    -- short of the frame's actual right edge (the "extra spacing between
    -- charges and Whirling Surge" report, reproducible at UI scales where
    -- that leftover doesn't round away to ~0).
    local PPdr = EllesmereUI and EllesmereUI.PP
    local px = (PPdr and PPdr.mult and PPdr.mult > 0) and PPdr.mult or 1
    local widthAvail = max(0, width - (pipCount - 1) * spacing)
    -- If the whole row doesn't span even one physical pixel (a very small
    -- bar at a low UI Scale, where px itself is large), snapping to whole
    -- physical-pixel units would floor every pip to 0 width -- pips
    -- vanishing entirely is worse than the sub-pixel gap this fix targets.
    -- Fall back to plain UI-unit distribution (pre-fix behavior) in that
    -- degenerate case so pips stay visible, just not perfectly pixel-snapped.
    if widthAvail < px then px = 1 end
    local totalUnits = floor(widthAvail / px + 1e-6)
    local unitsPer = floor(totalUnits / pipCount)
    local remUnits = totalUnits - unitsPer * pipCount
    local x = 0
    for i = 1, pipCount do
        local thisW = (unitsPer + (i <= remUnits and 1 or 0)) * px
        local pip = frame.pips[i]
        pip:ClearAllPoints()
        pip:SetPoint("TOPLEFT", frame, "TOPLEFT", x, 0)
        pip:SetSize(thisW, height)
        x = x + thisW + spacing
    end
end

function Build()
    if rootFrame then return end
    rootFrame = CreateFrame("Frame", "EllesmereUIDragonRidingAnchor", UIParent)
    rootFrame:SetFrameStrata("MEDIUM")
    rootFrame:Hide()
    rootFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

    speedBar   = CreateSpeedBar(rootFrame)
    EnsureBorder(speedBar)

    stackFrame = CreateStackFrame(rootFrame, SKYRIDING_PIPS)
    for i = 1, SKYRIDING_PIPS do EnsureBorder(stackFrame.pips[i]) end

    swFrame    = CreateStackFrame(rootFrame, SECONDWIND_PIPS)
    for i = 1, SECONDWIND_PIPS do EnsureBorder(swFrame.pips[i]) end

    wsIcon     = CreateWhirlingSurgeIcon(rootFrame)
    EnsureBorder(wsIcon)

    Rebuild()
end

function Rebuild()
    if not rootFrame then return end
    local p = db.profile

    local totalH   = p.secondWindHeight + p.gap + p.skyridingHeight + p.gap + p.speedHeight
    local iconSize = totalH
    local totalW   = p.width + p.gap + iconSize
    rootFrame:SetSize(totalW, totalH)

    speedBar:ClearAllPoints()
    speedBar:SetPoint("BOTTOMLEFT", rootFrame, "BOTTOMLEFT", 0, 0)
    speedBar:SetSize(p.width, p.speedHeight)

    stackFrame:ClearAllPoints()
    stackFrame:SetPoint("BOTTOMLEFT", speedBar, "TOPLEFT", 0, p.gap)
    stackFrame:SetSize(p.width, p.skyridingHeight)
    LayoutPips(stackFrame, SKYRIDING_PIPS, p.width, p.skyridingHeight, p.stackSpacing)

    swFrame:ClearAllPoints()
    swFrame:SetPoint("BOTTOM", stackFrame, "TOP", 0, p.gap)
    swFrame:SetSize(p.width, p.secondWindHeight)
    LayoutPips(swFrame, SECONDWIND_PIPS, p.width, p.secondWindHeight, p.stackSpacing)

    wsIcon:ClearAllPoints()
    wsIcon:SetPoint("BOTTOMLEFT", speedBar, "BOTTOMRIGHT", p.gap, 0)
    wsIcon:SetSize(iconSize, iconSize)

    Redraw()
    ApplyPos()
    UpdateVisibility()
end

function Redraw()
    if not rootFrame then return end
    local p = db.profile

    -- Apply bar texture to all StatusBars
    local texPath = EllesmereUI.ResolveTexturePath(ns.EDR_BAR_TEXTURES, p.barTexture or "none",
        "Interface\\Buttons\\WHITE8x8")
    speedBar:SetStatusBarTexture(texPath)
    for i = 1, SKYRIDING_PIPS do
        stackFrame.pips[i]:SetStatusBarTexture(texPath)
    end
    for i = 1, SECONDWIND_PIPS do
        swFrame.pips[i]:SetStatusBarTexture(texPath)
    end

    local c = p.normalColor
    speedBar:SetStatusBarColor(c.r, c.g, c.b, c.a)
    speedBar.bg:SetColorTexture(p.speedBarBg.r, p.speedBarBg.g, p.speedBarBg.b, p.speedBarBg.a)

    local tickFrac = (p.thrillThreshold or 0) / (p.maxSpeed > 0 and p.maxSpeed or 1)
    tickFrac = max(0, min(1, tickFrac))
    speedBar.tick:ClearAllPoints()
    speedBar.tick:SetPoint("TOP",    speedBar, "TOPLEFT",    p.width * tickFrac, 0)
    speedBar.tick:SetPoint("BOTTOM", speedBar, "BOTTOMLEFT", p.width * tickFrac, 0)
    speedBar.tick:SetWidth(2)
    speedBar.tick:SetColorTexture(p.tickColor.r, p.tickColor.g, p.tickColor.b, p.tickColor.a)

    ApplyFont(speedBar.text, p.speedText.size)
    speedBar.text:ClearAllPoints()
    speedBar.text:SetPoint(p.speedText.justify or "CENTER", speedBar,
        p.speedText.justify or "CENTER",
        p.speedText.offsetX or 0, p.speedText.offsetY or 0)
    speedBar.text:SetJustifyH(p.speedText.justify or "CENTER")
    speedBar.text:SetShown(p.speedText.enabled ~= false)

    for i = 1, SKYRIDING_PIPS do
        local pip = stackFrame.pips[i]
        pip:SetStatusBarColor(p.skyridingFilled.r, p.skyridingFilled.g, p.skyridingFilled.b, 1)
        pip.bg:SetColorTexture(p.skyridingBg.r, p.skyridingBg.g, p.skyridingBg.b, p.skyridingBg.a)
    end

    for i = 1, SECONDWIND_PIPS do
        local pip = swFrame.pips[i]
        pip:SetStatusBarColor(p.secondWindFilled.r, p.secondWindFilled.g, p.secondWindFilled.b, 1)
        pip.bg:SetColorTexture(p.secondWindBg.r, p.secondWindBg.g, p.secondWindBg.b, p.secondWindBg.a)
    end

    ApplyFont(wsIcon.text, p.whirlingSurgeText.size)
    wsIcon.text:ClearAllPoints()
    wsIcon.text:SetPoint(p.whirlingSurgeText.justify or "CENTER", wsIcon,
        p.whirlingSurgeText.justify or "CENTER",
        p.whirlingSurgeText.offsetX or 0, p.whirlingSurgeText.offsetY or 0)
    wsIcon.text:SetJustifyH(p.whirlingSurgeText.justify or "CENTER")
    wsIcon.text:SetShown(p.whirlingSurgeText.enabled ~= false)

    ApplyBordersAll()

    skyridingDirty  = true
    secondWindDirty = true
    whirlingDirty   = true
    lastSkyCur, lastSkyProgress = -1, -1
    lastSwCur,  lastSwProgress  = -1, -1
    lastCdStart, lastCdDur      = -1, -1
end

-------------------------------------------------------------------------------
--  Unlock mode
-------------------------------------------------------------------------------
local function SavePos(_, point, relPoint, x, y)
    if not point then return end
    local p = db and db.profile
    if not p then return end
    p.unlockPos = { point = point, relPoint = relPoint or point, x = x, y = y }
    if not EllesmereUI._unlockActive and rootFrame then
        rootFrame:ClearAllPoints()
        rootFrame:SetPoint(point, UIParent, relPoint or point, x, y)
    end
end
local function LoadPos()
    local p = db and db.profile; local pos = p and p.unlockPos
    if not pos then return nil end
    return { point = pos.point, relPoint = pos.relPoint or pos.point, x = pos.x, y = pos.y }
end
local function ClearPos()
    local p = db and db.profile; if not p then return end
    p.unlockPos = nil
end
function ApplyPos()
    local p = db and db.profile; local pos = p and p.unlockPos
    if not pos or not rootFrame then return end
    rootFrame:ClearAllPoints()
    rootFrame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
end

-- Profile-swap refresh: re-read DB and rebuild the HUD.
_G._EDR_Rebuild = function()
    if not rootFrame then return end
    Rebuild()
    ApplyPos()
end

function RegisterUnlockElements()
    if not EllesmereUI or not EllesmereUI.RegisterUnlockElements then return end
    local MK = EllesmereUI.MakeUnlockElement
    EllesmereUI:RegisterUnlockElements({
        MK({
            key   = "EDR_Cluster",
            label = "Dragon Riding",
            group = "Dragon Riding",
            order = 700,
            getFrame = function() return rootFrame end,
            getSize  = function()
                local p = db.profile
                local totalH   = p.secondWindHeight + p.gap + p.skyridingHeight + p.gap + p.speedHeight
                local iconSize = totalH
                return p.width + p.gap + iconSize, totalH
            end,
            setWidth = function(_, w)
                local p = db.profile
                local totalH   = p.secondWindHeight + p.gap + p.skyridingHeight + p.gap + p.speedHeight
                local iconSize = totalH
                local PPdr = EllesmereUI and EllesmereUI.PP
                p.width = max(60, PPdr and PPdr.Snap(w - p.gap - iconSize) or floor(w - p.gap - iconSize + 0.5))
                Rebuild()
            end,
            -- Height is the SUM of three independently-sized bars (Second
            -- Wind, Skyriding charges, Speed) plus two fixed gaps between
            -- them -- there's no single "height" field to write. Scale all
            -- three proportionally toward the requested total, matching how
            -- the Options page's three height sliders combine to change the
            -- overall element size, then clamp each to its own Options-page
            -- slider range (2-24 / 2-24 / 4-40) so a drag can't push one bar
            -- to zero or past its usable size.
            setHeight = function(_, h)
                local p = db.profile
                local PPdr = EllesmereUI and EllesmereUI.PP
                local newTotalH = PPdr and PPdr.Snap(h) or floor(h + 0.5)
                local targetSum = max(8, newTotalH - 2 * p.gap)

                local bars = {
                    { field = "secondWindHeight", lo = 2, hi = 24 },
                    { field = "skyridingHeight",  lo = 2, hi = 24 },
                    { field = "speedHeight",      lo = 4, hi = 40 },
                }
                local oldSum = 0
                for _, b in ipairs(bars) do
                    b.old = p[b.field]
                    oldSum = oldSum + b.old
                end
                if oldSum <= 0 then
                    -- Corrupted/legacy profile (e.g. hand-edited SavedVariables)
                    -- with all three heights at/under zero: reset to defaults so
                    -- the control self-heals instead of silently no-op'ing forever.
                    for _, b in ipairs(bars) do p[b.field] = DB_DEFAULTS.profile[b.field] end
                    Rebuild()
                    return
                end

                local scale = targetSum / oldSum
                for _, b in ipairs(bars) do
                    b.new = max(b.lo, min(b.hi, floor(b.old * scale + 0.5)))
                end

                -- A bar already at its min/max absorbs none of a further
                -- shrink/grow, so plain proportional scaling can leave the
                -- resize handle feeling stuck once one or two bars saturate.
                -- Hand any leftover delta to whichever bar(s) still have
                -- headroom instead of discarding it (bounded to 3 passes --
                -- one per bar -- so this always terminates).
                for _ = 1, #bars do
                    local sum = bars[1].new + bars[2].new + bars[3].new
                    local leftover = targetSum - sum
                    if leftover == 0 then break end
                    local openBars = {}
                    for _, b in ipairs(bars) do
                        if (leftover > 0 and b.new < b.hi) or (leftover < 0 and b.new > b.lo) then
                            openBars[#openBars + 1] = b
                        end
                    end
                    if #openBars == 0 then break end
                    local shareF = leftover / #openBars
                    local share = shareF >= 0 and floor(shareF + 0.5) or -floor(-shareF + 0.5)
                    if share == 0 then
                        -- Leftover doesn't divide evenly across every open bar
                        -- this pass (e.g. 1px across 3 bars): give the whole
                        -- remainder to just the first bar with headroom rather
                        -- than rounding a fractional share up and applying it
                        -- to all of them, which would overshoot the target.
                        local b = openBars[1]
                        b.new = max(b.lo, min(b.hi, b.new + leftover))
                    else
                        for _, b in ipairs(openBars) do
                            b.new = max(b.lo, min(b.hi, b.new + share))
                        end
                    end
                end

                for _, b in ipairs(bars) do p[b.field] = b.new end
                Rebuild()
            end,
            savePos = SavePos, loadPos = LoadPos, clearPos = ClearPos, applyPos = ApplyPos,
        }),
    })
end

-------------------------------------------------------------------------------
--  Init
-------------------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not EllesmereUI or not EllesmereUI.Lite then return end

    db = EllesmereUI.Lite.NewDB("EllesmereUIDragonRidingDB", DB_DEFAULTS)
    ns.edrDB = db

    -- If disabled, skip all frame creation and event registration.
    -- Rebuild (called from options toggle) will lazy-init if needed.
    if not db.profile.enabled then return end

    Build()

    evtFrame = CreateFrame("Frame")
    evtFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    evtFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    evtFrame:RegisterEvent("PLAYER_CAN_GLIDE_CHANGED")
    evtFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    evtFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    evtFrame:SetScript("OnEvent", function(_, event)
        if event == "SPELL_UPDATE_CHARGES" then
            skyridingDirty = true
            secondWindDirty = true
            return
        elseif event == "SPELL_UPDATE_COOLDOWN" then
            whirlingDirty = true
            return
        elseif event == "PLAYER_ENTERING_WORLD" then
            skyridingDirty = true
            secondWindDirty = true
            whirlingDirty = true
        end
        UpdateVisibility()
    end)

    C_Timer.After(0.5, function()
        RegisterUnlockElements()
        ApplyPos()
    end)
end)

-- Exports for options page. Rebuild handles lazy-init if module was disabled at login.
ns.edrRebuild = function()
    if not db then return end
    if not rootFrame then
        -- First enable after being disabled at login: full init
        Build()
        if not evtFrame then
            evtFrame = CreateFrame("Frame")
            evtFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
            evtFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
            evtFrame:RegisterEvent("PLAYER_CAN_GLIDE_CHANGED")
            evtFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            evtFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
            evtFrame:SetScript("OnEvent", function(_, event)
                if event == "SPELL_UPDATE_CHARGES" then
                    skyridingDirty = true
                    secondWindDirty = true
                    return
                elseif event == "SPELL_UPDATE_COOLDOWN" then
                    whirlingDirty = true
                    return
                elseif event == "PLAYER_ENTERING_WORLD" then
                    skyridingDirty = true
                    secondWindDirty = true
                    whirlingDirty = true
                end
                UpdateVisibility()
            end)
        end
        RegisterUnlockElements()
    end
    Rebuild()
end
ns.edrRedraw = function() Redraw() end
