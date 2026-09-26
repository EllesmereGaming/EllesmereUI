if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if EllesmereUI and EllesmereUI.IS_FOREVER then return end -- no skyriding on WoW Forever: no DB, no events, no HUD; its options tab is not registered there
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

-- Bar texture table (shared with options via ns); paths only -- the
-- options file builds its own names/order pair from the same catalogue.
ns.EDR_BAR_TEXTURES = (EllesmereUI.BuildBarTextureTables())

-- Constants
local SPELL = {
    SKYWARD_ASCENT  = 372610,
    SECOND_WIND     = 425782,
    WHIRLING_SURGE  = 361584,
}
local SKYRIDING_PIPS  = 6
local SECONDWIND_PIPS = 3
local BASE_RUN_SPEED  = 7.0

-- Classic vigor gems: Blizzard's pre-12.0 FillUpFrames widget, rebuilt from the
-- art the client still ships (interface/widgets/dragonridingvigorwidgets.blp).
-- Cell size, edge padding and decor offset are the dragonriding_vigor values from
-- Blizzard_UIWidgetTemplateFillUpFrames.lua; art sizes are the atlas pixel sizes
-- halved (the sheet is 2x).
local CLASSIC = {
    kit         = "dragonriding_vigor",
    cellW       = 42,   cellH   = 45,
    edgePad     = -20,  decorTop = 8,
    decorW      = 46.5, decorH  = 58.5,
    frameW      = 60,   frameH  = 65,
    bgW         = 30.5, bgH     = 35.5,
    fillW       = 36,   fillH   = 36,
    sparkW      = 46.5, sparkH  = 10,
    maskW       = 64,   maskH   = 64,
}
local CLASSIC_W = CLASSIC.decorW * 2 + CLASSIC.edgePad * 2 + CLASSIC.cellW * SKYRIDING_PIPS
local CLASSIC_H = max(CLASSIC.cellH, CLASSIC.decorTop + CLASSIC.decorH)
local FULL_CHARGE_SOUND = SOUNDKIT and SOUNDKIT.UI_DRAGONRIDING_FULL_NODE

-- Database defaults
local DB_DEFAULTS = {
    profile = {
        enabled          = false,
        hideInCombat     = false,

        -- Bar art: "modern" = the EllesmereUI look; "blizzard" / "classic" =
        -- the Resource Bars' Blizzard Style / Classic WoW UI frames.
        barStyle          = "modern",
        classicFrameSize  = nil,  -- Classic WoW UI frame %, nil = shared default
        -- Charges: "bars" = a pip row in the bar column, "gems" = Blizzard's
        -- original vigor gems above the column. Independent of barStyle.
        vigorStyle        = "bars",
        classicScale      = 1.0,
        chargeSound       = false,
        showSpeed         = true,
        showSecondWind    = true,
        showWhirlingSurge = true,
        iconSize          = nil,  -- nil = as tall as the full bar column

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
local rootFrame, speedBar, stackFrame, swFrame, wsIcon, classicFrame
local skyridingDirty  = true
local secondWindDirty = true
local whirlingDirty   = true
local lastSpeedApplied  = -1
local lastCdStart, lastCdDur = -1, -1
local lastSkyCur, lastSkyProgress = -1, -1
local lastSwCur,  lastSwProgress  = -1, -1
local lastClassicCur, lastClassicProgress = -1, -1
-- Charge count the full-charge sound last saw; -1 after every Redraw so a
-- repaint (login, settings change, style switch) never plays it.
local lastSoundCur = -1
local UPDATE_THROTTLE = 1 / 60
local elapsed         = 0
local smoothedSpeed   = 0
local SPEED_EMA_ALPHA = 0.25
local evtFrame        -- event frame (created on first enable)
local _spellEventsRegistered = false
-- True only while actually airborne skyriding: PLAYER_IS_GLIDING_CHANGED edges
-- plus a fresh read at every visibility evaluation. Gates the speed poll -- the
-- OnUpdate is armed only while gliding, while the landing decay is still
-- draining, or while a pip/cooldown section is mid-animation.
local _gliding = false

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
        -- Floor the landing decay to exactly 0 so the final empty-bar state
        -- paints once and the tick can then disarm (TickWanted reads > 0).
        if smoothedSpeed < 0.01 then smoothedSpeed = 0 end
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

-- Arm the per-frame body only while it has live work: airborne (speed poll),
-- landing decay still draining, or a pip/cooldown fill mid-animation. Grounded
-- with full charges and a settled bar = no OnUpdate and no API reads at all.
-- Unlock Mode force-arms so the HUD stays editable off-mount.
local function TickWanted()
    return skyridingDirty or secondWindDirty or whirlingDirty
        or ((_gliding or smoothedSpeed > 0) and db.profile.showSpeed ~= false)
end
local function SyncTick()
    if not rootFrame then return end
    if rootFrame:IsShown() and (TickWanted()
            or (EllesmereUI and EllesmereUI._unlockActive)) then
        rootFrame:SetScript("OnUpdate", OnUpdate)
    else
        rootFrame:SetScript("OnUpdate", nil)
    end
end

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
    local wasShown = rootFrame:IsShown()
    rootFrame:SetShown(visible)
    if visible then
        -- Charges that refilled while the HUD was hidden are not a live gain:
        -- repaint them without the full-charge chime or the gem flash.
        if not wasShown then lastSoundCur, lastClassicCur = -1, -1 end
        -- Seed the airborne flag from a fresh read (covers /reload mid-flight
        -- and any edge missed while hidden), then arm only if there is work.
        local isGliding = C_PlayerInfo.GetGlidingInfo()
        _gliding = isGliding == true
        SyncTick()
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

-- Per-cell state for the classic gems, mirroring UIWidgetFillUpFrameTemplateMixin:
-- a full gem flashes once when it completes, the filling gem pulses and plays the
-- swirl flipbook, the spark rides the fill line.
local function SetClassicFilling(cell, progress)
    cell.bar:SetValue(progress)
    cell.spark:SetShown(progress > 0 and progress < 1)
    if cell.flipAnim then
        if progress > 0 then
            if not cell.flipAnim:IsPlaying() then
                cell.flip:Show()
                cell.flipAnim:Play()
            end
        else
            cell.flip:Hide()
            cell.flipAnim:Stop()
        end
    end
end

local function SetClassicFull(cell, full)
    if cell.isFull == full then return end
    cell.isFull = full
    local atlas = full and cell.fillFullAtlas or cell.fillAtlas
    if atlas then cell.bar:SetStatusBarTexture(atlas) end
    cell.spark:ClearAllPoints()
    cell.spark:SetPoint("CENTER", cell.bar:GetStatusBarTexture(), "TOP", 0, 0)
    if cell.flipMask then
        cell.flipMask:ClearAllPoints()
        cell.flipMask:SetPoint("TOP", cell.bar:GetStatusBarTexture(), "TOP", 0, 0)
    end
end

local function ApplyClassicRow(cur, maxC, progress)
    local cells = classicFrame.cells
    if cur ~= lastClassicCur then
        -- lastClassicCur is -1 after every Redraw, so the first paint never flashes.
        local gained = lastClassicCur >= 0 and cur > lastClassicCur
        for i = 1, SKYRIDING_PIPS do
            local cell = cells[i]
            local isFull = i <= cur
            local isFilling = i == cur + 1 and cur < maxC
            SetClassicFull(cell, isFull)
            if isFull then
                cell.bar:SetValue(1)
                cell.spark:Hide()
                cell.pulseAnim:Stop()
                if cell.flipAnim then cell.flipAnim:Stop(); cell.flip:Hide() end
                if gained and i > lastClassicCur then
                    cell.flashAnim:Restart()
                end
            elseif isFilling then
                cell.flashAnim:Stop()
                cell.flash:SetAlpha(0)
                cell.pulseAnim:Play()
                SetClassicFilling(cell, progress)
            else
                cell.flashAnim:Stop()
                cell.pulseAnim:Stop()
                cell.flash:SetAlpha(0)
                SetClassicFilling(cell, 0)
            end
        end
        return cur, progress
    elseif cur < maxC and abs(progress - lastClassicProgress) > 0.005 then
        local cell = cells[cur + 1]
        if cell then SetClassicFilling(cell, progress) end
        return cur, progress
    end
    return lastClassicCur, lastClassicProgress
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

    -- Speed poll only while airborne or while the landing decay drains; the
    -- decay floors to exactly 0 so the final empty-bar state paints once.
    -- Nothing to poll while the speed bar is hidden.
    if (_gliding or smoothedSpeed > 0) and p.showSpeed ~= false then
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
    end -- speed-poll gate

    if skyridingDirty then
        local info = C_Spell.GetSpellCharges(SPELL.SKYWARD_ASCENT)
        local cur  = info and info.currentCharges or 0
        local maxC = info and info.maxCharges or SKYRIDING_PIPS
        local progress = 0
        if info and info.cooldownDuration and info.cooldownDuration > 0 then
            local e = GetTime() - (info.cooldownStartTime or 0)
            progress = max(0, min(1, e / info.cooldownDuration))
        end
        if p.chargeSound and lastSoundCur >= 0 and cur > lastSoundCur
                and FULL_CHARGE_SOUND then
            PlaySound(FULL_CHARGE_SOUND)
        end
        lastSoundCur = cur
        if p.vigorStyle == "gems" and classicFrame then
            lastClassicCur, lastClassicProgress = ApplyClassicRow(cur, maxC, progress)
        else
            lastSkyCur, lastSkyProgress = ApplyPipRow(
                stackFrame.pips, SKYRIDING_PIPS, cur, maxC, progress,
                lastSkyCur, lastSkyProgress, p.skyridingFilled, 0.4)
        end
        skyridingDirty = (cur < maxC)
    end

    if secondWindDirty and p.showSecondWind == false then
        secondWindDirty = false -- hidden; showing it again redraws it
    elseif secondWindDirty then
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

    if whirlingDirty and p.showWhirlingSurge == false then
        whirlingDirty = false -- hidden; showing it again redraws it
    elseif whirlingDirty then
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

    -- Self-disarm once every section settled and we are grounded; every dirty
    -- writer and the gliding edge re-arm through SyncTick.
    if not TickWanted() then SyncTick() end
end

-------------------------------------------------------------------------------
--  Layout
-------------------------------------------------------------------------------
local ROW_FIELD = { speed = "speedHeight", sky = "skyridingHeight", sw = "secondWindHeight" }
-- Options-page slider range of each row height (the unlock height drag clamps to it).
local ROW_RANGE = { speedHeight = { 4, 40 }, skyridingHeight = { 2, 24 }, secondWindHeight = { 2, 24 } }
-- Every bar row of each vigor style, bottom to top (the automatic icon height).
local STYLE_ROWS_BARS = { "speed", "sky", "sw" }
local STYLE_ROWS_GEMS = { "speed", "sw" }

-- Bar Style art. Both stock looks match the Resource Bars' ones so the HUD and
-- the class resource bar read as one UI; the bars keep the user's texture and
-- colours in every style, and the column is framed as one box with dividers
-- (see ApplyColumnChrome).
--
-- Blizzard: the Cooldown Manager bar panel (the personal resource display's
-- art) round the column, and an inner bevel over each row so the user's
-- texture reads recessed. The panel's opaque rim is 1 left and right, 2
-- above, 1 below.
local BLIZZ_CHROME = {
    bg   = "UI-HUD-CoolDownManager-Bar-BG",
    fill = "UI-HUD-CoolDownManager-Bar",
    rimX = 1, rimT = 2, rimB = 1,
}
local SHADE_CLEAR  = CreateColor(0, 0, 0, 0)
local SHADE_TOP    = CreateColor(0, 0, 0, 0.55)
local SHADE_BOTTOM = CreateColor(0, 0, 0, 0.30)
local SHADE_END    = CreateColor(0, 0, 0, 0.35)
-- Whirling Surge icon, Blizzard: action button frame (46x45 around a 45 icon,
-- anchored TOPLEFT) and mask, with the rounded swipe AuraKit and the Cooldown
-- Manager use (Cooldown frames cannot take a MaskTexture). Classic WoW UI: the
-- vanilla slot ring the classic action buttons wear (66/36 of the icon,
-- 1/36 low).
local BLIZZ_ICON = {
    frame = "ui-hud-actionbar-iconframe", frameW = 46, frameH = 45, iconSize = 45,
    mask  = "ui-hud-actionbar-iconframe-mask",
    swipe = "Interface\\HUD\\UI-HUD-CoolDownManager-Icon-Swipe",
    ring  = "Interface\\Buttons\\UI-Quickslot2",
}

local function PPSnap(v)
    local PPdr = EllesmereUI and EllesmereUI.PP
    if PPdr and PPdr.Snap then return PPdr.Snap(v) end
    return floor(v + 0.5)
end
-- Round a frame dimension UP to a whole number of physical pixel PAIRS. The HUD
-- is centre-anchored, so an odd pixel count (or a fraction, which the classic
-- gems' half-unit art sizes produced) puts every edge inside it half a pixel
-- off the grid.
local function SnapEven(v)
    local PPdr = EllesmereUI and EllesmereUI.PP
    local m = PPdr and PPdr.mult or 1
    if m <= 0 then m = 1 end
    return math.ceil(v / (2 * m) - 1e-6) * 2 * m
end

-- Room the bar column reserves round itself for its frame's VISIBLE rim:
-- vertical (each side) and horizontal (each end). The Blizzard and Classic WoW
-- UI styles frame the column as one box (the Resource Bars' Border Around All
-- look), so the rim sits outside the column only. Above and below differ
-- slightly; each side takes half of their sum. 0,0 with no frame (modern).
local function ArtOverhang(chrome, k)
    if chrome == "blizzard" then
        local C = BLIZZ_CHROME
        return PPSnap((C.rimT + C.rimB) / 2), PPSnap(C.rimX)
    elseif chrome == "classic" then
        local CF = EllesmereUI.ClassicFrame
        if not CF then return 0, 0 end
        local padW, padH = CF.Pad(k)
        return PPSnap(padH / 2), PPSnap(padW / 2)
    end
    return 0, 0
end

-- Height a list of rows occupies stacked with gaps, including the frame rim
-- (ov, from ArtOverhang).
local function StackHeight(p, rows, ov)
    if #rows == 0 then return 0 end
    local total = 2 * ov
    for i, key in ipairs(rows) do
        total = total + p[ROW_FIELD[key]] + (i > 1 and p.gap or 0)
    end
    return total
end

-- Classic WoW UI frame scale: the Border Size percentage (nil = the shared
-- default), as the Resource Bars' Classic WoW UI bars take it.
local function ClassicFrameK(p)
    local CF = EllesmereUI.ClassicFrame
    return CF and CF.ScaleK(p.classicFrameSize) or 1
end

-- Where everything goes for the current settings. The bar column stacks bottom
-- to top (speed, charges, Second Wind) and the Whirling Surge icon sits on its
-- right, the shorter of the two centred on the taller; the classic gem row sits
-- above both. The icon is as tall as the full column (every bar of the style)
-- unless given its own size. Classic gems replace the charge row rather than
-- sitting in the column, and the Blizzard and Classic WoW UI bar styles frame
-- each row, which needs room around it.
local function ComputeLayout(p)
    local classic = p.vigorStyle == "gems"
    local chrome = (p.barStyle == "blizzard" or p.barStyle == "classic") and p.barStyle or nil
    local k = chrome == "classic" and ClassicFrameK(p) or 1

    local rows = {}
    if p.showSpeed ~= false then rows[#rows + 1] = "speed" end
    if not classic then rows[#rows + 1] = "sky" end
    if p.showSecondWind ~= false then rows[#rows + 1] = "sw" end

    local ov, padX = ArtOverhang(chrome, k)
    local colH = StackHeight(p, rows, ov)
    local colW = #rows > 0 and (p.width + 2 * padX) or 0

    local icon = p.showWhirlingSurge ~= false
    local iconSize = 0
    if icon then
        iconSize = p.iconSize
        if not iconSize then
            -- Every bar of the style, shown or not.
            iconSize = StackHeight(p, classic and STYLE_ROWS_GEMS or STYLE_ROWS_BARS, ov)
        end
    end
    local clusterW = colW + (icon and ((colW > 0 and p.gap or 0) + iconSize) or 0)
    local clusterH = max(colH, iconSize)

    local scale = p.classicScale or 1
    local classicW = classic and PPSnap(CLASSIC_W * scale) or 0
    local classicH = classic and PPSnap(CLASSIC_H * scale) or 0
    local rawW = max(clusterW, classicW)
    local rawH = clusterH + classicH + ((classic and clusterH > 0) and p.gap or 0)

    return {
        rows = rows, classic = classic, chrome = chrome, frameK = k, ov = ov,
        scale = scale,
        colH = colH, colW = colW, padX = padX, colY = PPSnap((clusterH - colH) / 2),
        icon = icon, iconSize = iconSize, iconY = PPSnap((clusterH - iconSize) / 2),
        clusterW = clusterW, clusterH = clusterH,
        classicW = classicW, classicH = classicH,
        -- raw* before the even-pixel rounding, so the unlock setters can undo it.
        rawW = rawW, rawH = rawH,
        totalW = SnapEven(rawW), totalH = SnapEven(rawH),
    }
end

-------------------------------------------------------------------------------
--  Helpers
-------------------------------------------------------------------------------
local function ApplyFont(fs, size)
    if not fs then return end
    local font = EllesmereUI.GetFontPath("blizzardSkin") or "Fonts/FRIZQT__.TTF"
    local flag = EllesmereUI.GetFontOutlineFlag("blizzardSkin") or ""
    EllesmereUI.PrimeFontShadow(fs, flag == "")
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

local function ApplyBorderEdges(frame, hideL, hideR, hideT, hideB)
    local PP = EllesmereUI and EllesmereUI.PP
    local edges = PP and PP.GetBorders and PP.GetBorders(frame)
    if not edges then return end
    edges._hideLeft = hideL or nil
    edges._hideRight = hideR or nil
    edges._hideTop = hideT or nil
    edges._hideBottom = hideB or nil
end

local function ApplyBordersAll(L)
    local PP = EllesmereUI and EllesmereUI.PP
    if not PP then return end
    local p = db.profile
    local c = p.borderColor
    -- The Blizzard and Classic WoW UI bar styles draw their own frames instead.
    local thick = L.chrome and 0 or (p.borderThickness or 0)
    for _, f in ipairs(borderedFrames) do
        if thick > 0 then
            PP.UpdateBorder(f, thick, c.r, c.g, c.b, c.a)
            PP.ShowBorder(f)
        else
            PP.HideBorder(f)
        end
    end

    if thick > 0 then
        -- At Element Spacing / Stack Spacing = 0 the touching frames each
        -- draw their own full border, so the shared seam gets two
        -- independently pixel-snapped lines instead of one. Suppress the
        -- edge on one side of every seam so only a single line remains:
        -- each row drops its bottom edge when a row sits under it, and a row
        -- lying wholly beside the icon drops its right edge (the icon can be
        -- shorter than the column, so rows above or below it keep theirs).
        local gapTouch = p.gap == 0
        local stackTouch = p.stackSpacing == 0
        local iconLo, iconHi = L.iconY - 0.01, L.iconY + L.iconSize + 0.01
        local y = L.colY + L.ov
        for i, key in ipairs(L.rows) do
            local h = p[ROW_FIELD[key]]
            local iconTouch = gapTouch and L.icon and y >= iconLo and y + h <= iconHi
            y = y + h + p.gap
            local hideB = gapTouch and i > 1
            if key == "speed" then
                ApplyBorderEdges(speedBar, false, iconTouch, false, hideB)
            else
                local pips, n = stackFrame.pips, SKYRIDING_PIPS
                if key == "sw" then pips, n = swFrame.pips, SECONDWIND_PIPS end
                for j = 1, n do
                    local hideR = (stackTouch and j < n) or (iconTouch and j == n)
                    ApplyBorderEdges(pips[j], false, hideR, false, hideB)
                end
            end
        end
        -- Re-snap so the updated hide flags take effect immediately.
        for _, f in ipairs(borderedFrames) do
            PP.SetBorderSize(f, thick)
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
    -- The pip stacks/icon nest their bar textures one parent level deeper
    -- than the speed bar itself (stackFrame -> pip, wsIcon -> tex/cd), and
    -- frame level always outranks draw layer across frames. A plain OVERLAY
    -- fontstring parented directly to f would render behind that nested
    -- content, so give the text its own frame raised well above every level
    -- used anywhere in this HUD (same pattern as CreateWhirlingSurgeIcon's
    -- textFrame).
    f.textFrame = CreateFrame("Frame", nil, f)
    f.textFrame:SetAllPoints(f)
    f.textFrame:SetFrameLevel(f:GetFrameLevel() + 10)
    f.text = f.textFrame:CreateFontString(nil, "OVERLAY")
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

-- Inner bevel over a Blizzard-style row: gradient strips darkening the long
-- edges and both ends (the Resource Bars' bevel), so the user's texture reads
-- recessed in the panel.
local function LayoutBevel(shade, w, h)
    local sh = shade.strips
    if not sh then
        sh = {}
        for i = 1, 4 do
            local t = shade:CreateTexture(nil, "OVERLAY", nil, -3)
            t:SetTexture("Interface\\Buttons\\WHITE8X8")
            t:SetSnapToPixelGrid(false)
            t:SetTexelSnappingBias(0)
            sh[i] = t
        end
        shade.strips = sh
    end
    local a = max(2, floor(h * 0.2))
    local b = max(1, floor(h * 0.1))
    local e = max(2, floor(w * 0.15))
    for i = 1, 4 do sh[i]:ClearAllPoints() end
    sh[1]:SetGradient("VERTICAL", SHADE_CLEAR, SHADE_TOP)
    sh[1]:SetPoint("TOPLEFT"); sh[1]:SetPoint("TOPRIGHT"); sh[1]:SetHeight(a)
    sh[2]:SetGradient("VERTICAL", SHADE_BOTTOM, SHADE_CLEAR)
    sh[2]:SetPoint("BOTTOMLEFT"); sh[2]:SetPoint("BOTTOMRIGHT"); sh[2]:SetHeight(b)
    sh[3]:SetGradient("HORIZONTAL", SHADE_END, SHADE_CLEAR)
    sh[3]:SetPoint("TOPLEFT"); sh[3]:SetPoint("BOTTOMLEFT"); sh[3]:SetWidth(e)
    sh[4]:SetGradient("HORIZONTAL", SHADE_CLEAR, SHADE_END)
    sh[4]:SetPoint("TOPRIGHT"); sh[4]:SetPoint("BOTTOMRIGHT"); sh[4]:SetWidth(e)
end

-- Add or move a mask on a texture, once per texture object (AddMaskTexture is
-- additive, and a status bar texture swap can mint a new fill object).
-- mask nil takes it off.
local function MaskTex(tex, mask)
    if not tex or tex._edrMask == mask then return end
    if tex._edrMask then tex:RemoveMaskTexture(tex._edrMask) end
    if mask then tex:AddMaskTexture(mask) end
    tex._edrMask = mask
end

-- Per-row part of the Blizzard style, as the Resource Bars keep it on every
-- bar, grouped or not: the row's fill, backing and bevel clipped to the stock
-- fill's rounded footprint (one clip across a pip row, so only its end pips
-- round off), which keeps the row inside the panel rim's rounded corners, and
-- the bevel over the row (above the pips and their borders, under the speed
-- text at +10). Built on first use; hidden and un-clipped in the other styles.
local function ApplyRowChrome(host, chrome, w, h)
    local on = chrome == "blizzard"
    local shade = host._edrShade
    if on and not shade then
        shade = CreateFrame("Frame", nil, host)
        shade:SetAllPoints(host)
        shade:SetFrameLevel(host:GetFrameLevel() + 9)
        host._edrShade = shade
        if C_Texture.GetAtlasInfo(BLIZZ_CHROME.fill) then
            host._edrMask = host:CreateMaskTexture()
            host._edrMask:SetAtlas(BLIZZ_CHROME.fill)
            host._edrMask:SetAllPoints(host)
        end
    end
    if not shade then return end
    shade:SetShown(on)
    if on then LayoutBevel(shade, w, h) end
    local mask = on and host._edrMask or nil
    if host.pips then
        for i = 1, #host.pips do
            local pip = host.pips[i]
            MaskTex(pip:GetStatusBarTexture(), mask)
            MaskTex(pip.bg, mask)
        end
    else
        MaskTex(host:GetStatusBarTexture(), mask)
        MaskTex(host.bg, mask)
    end
    if shade.strips then
        for i = 1, #shade.strips do MaskTex(shade.strips[i], mask) end
    end
end

-- Blizzard panel as a nine-slice round the whole column (the Resource Bars'
-- Border Around All panel). The atlas is 132x19 with the fill area at columns
-- 2..126 and rows 3..12; only the middle stretches, so the rims keep their
-- size however tall the column is. The centre is the rows' backdrop and sits
-- under them; the border pieces sit ABOVE the rows, or bars that rounded a
-- pixel outward covered the one- and two-pixel rims. The pieces are cut on
-- the fill area's edges, as the Resource Bars cut it; the rim's rounded
-- corners are kept clear by each row's clip to the stock bar shape
-- (ApplyRowChrome), not by the slicing.
-- Each piece: atlas u0, u1, v0, v1 (pixels), under-the-rows flag, and its
-- TOPLEFT / BOTTOMRIGHT as { column point, x, y }.
local PANEL_R = 0
local PANEL_PIECES = {
    -- corners
    { 0, 2 + PANEL_R, 0, 3 + PANEL_R, false, { "TOPLEFT", -2, 3 }, { "TOPLEFT", PANEL_R, -PANEL_R } },
    { 126 - PANEL_R, 132, 0, 3 + PANEL_R, false, { "TOPRIGHT", -PANEL_R, 3 }, { "TOPRIGHT", 6, -PANEL_R } },
    { 0, 2 + PANEL_R, 12 - PANEL_R, 19, false, { "BOTTOMLEFT", -2, PANEL_R }, { "BOTTOMLEFT", PANEL_R, -7 } },
    { 126 - PANEL_R, 132, 12 - PANEL_R, 19, false, { "BOTTOMRIGHT", -PANEL_R, PANEL_R }, { "BOTTOMRIGHT", 6, -7 } },
    -- edges
    { 2 + PANEL_R, 126 - PANEL_R, 0, 3, false, { "TOPLEFT", PANEL_R, 3 }, { "TOPRIGHT", -PANEL_R, 0 } },
    { 2 + PANEL_R, 126 - PANEL_R, 12, 19, false, { "BOTTOMLEFT", PANEL_R, 0 }, { "BOTTOMRIGHT", -PANEL_R, -7 } },
    { 0, 2, 3 + PANEL_R, 12 - PANEL_R, false, { "TOPLEFT", -2, -PANEL_R }, { "BOTTOMLEFT", 0, PANEL_R } },
    { 126, 132, 3 + PANEL_R, 12 - PANEL_R, false, { "TOPRIGHT", 0, -PANEL_R }, { "BOTTOMRIGHT", 6, PANEL_R } },
    -- centre (backdrop)
    { 2, 126, 3, 12, true, { "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", 0, 0 } },
}

-- The Blizzard and Classic WoW UI styles frame the bar column as ONE box: the
-- panel (Blizzard) or the vanilla frame (Classic) round every shown row, plus
-- a one-pixel black divider centred in each gap, between the rows and between
-- the pips of a pip row (the Resource Bars' group separators). geo = the shown
-- rows bottom to top, { key, x, y, h } from the root's bottom-left; w = row
-- width; gap = Element Spacing; spacing = Stack Spacing. Nothing is built for
-- the modern style.
local function ApplyColumnChrome(L, geo, w, gap, spacing)
    local col = rootFrame._edrCol
    local chrome = L.chrome
    if not chrome or #geo == 0 then
        if col then col:Hide() end
        return
    end
    if not col then
        col = CreateFrame("Frame", nil, rootFrame)
        col:EnableMouse(false)
        -- Art over every row's fill, pips and borders; under the speed text.
        col.art = CreateFrame("Frame", nil, col)
        col.art:EnableMouse(false)
        col.art:SetAllPoints(col)
        col.seps = {}
        rootFrame._edrCol = col
    end
    -- Under the rows (the panel is their backdrop); the art level above them.
    local rowLevel = speedBar:GetFrameLevel()
    col:SetFrameLevel(max(0, rowLevel - 1))
    col.art:SetFrameLevel(rowLevel + 9)

    local first, last = geo[1], geo[#geo]
    col:ClearAllPoints()
    col:SetPoint("BOTTOMLEFT", rootFrame, "BOTTOMLEFT", first.x, first.y)
    col:SetSize(w, last.y + last.h - first.y)
    col:Show()

    -- Blizzard panel.
    local info = chrome == "blizzard" and not col.panel and C_Texture.GetAtlasInfo(BLIZZ_CHROME.bg)
    if info then
        col.panel = {}
        local file = info.file or info.filename
        local l, r, t, b = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
        for _, pc in ipairs(PANEL_PIECES) do
            local tex = pc[5] and col:CreateTexture(nil, "BACKGROUND", nil, -2)
                or col.art:CreateTexture(nil, "OVERLAY", nil, 0)
            tex:SetSnapToPixelGrid(false)
            tex:SetTexelSnappingBias(0)
            tex:SetTexture(file)
            tex:SetTexCoord(l + (r - l) * pc[1] / 132, l + (r - l) * pc[2] / 132,
                t + (b - t) * pc[3] / 19, t + (b - t) * pc[4] / 19)
            local p1, p2 = pc[6], pc[7]
            tex:SetPoint("TOPLEFT", col, p1[1], p1[2], p1[3])
            tex:SetPoint("BOTTOMRIGHT", col, p2[1], p2[2], p2[3])
            col.panel[#col.panel + 1] = tex
        end
    end
    if col.panel then
        for i = 1, #col.panel do col.panel[i]:SetShown(chrome == "blizzard") end
    end

    -- Classic WoW UI frame.
    local CF = EllesmereUI.ClassicFrame
    if chrome == "classic" and CF and not col.classic then
        col.classic = CF.Create(col.art, "OVERLAY", 2)
    end
    if col.classic then
        CF.SetShown(col.classic, chrome == "classic")
        if chrome == "classic" then CF.Seat(col.classic, col, L.frameK, false) end
    end

    -- Dividers, one physical pixel thick, snapped to whole pixels.
    local PPdr = EllesmereUI.PP
    local px = ((PPdr and PPdr.perfect) or 1) / col:GetEffectiveScale()
    local function Centre(span) return floor(((span - px) / 2) / px + 0.5) * px end
    local n = 0
    local function Sep(x, y, sw, sh)
        n = n + 1
        local t = col.seps[n]
        if not t then
            t = col.art:CreateTexture(nil, "OVERLAY", nil, 3)
            t:SetColorTexture(0, 0, 0, 1)
            t:SetSnapToPixelGrid(false)
            t:SetTexelSnappingBias(0)
            col.seps[n] = t
        end
        t:ClearAllPoints()
        t:SetPoint("BOTTOMLEFT", rootFrame, "BOTTOMLEFT", x, y)
        t:SetSize(sw, sh)
        t:Show()
    end
    for i, g in ipairs(geo) do
        if i > 1 then
            local below = geo[i - 1]
            Sep(g.x, below.y + below.h + Centre(gap), w, px)
        end
        local row = g.key == "sky" and stackFrame or g.key == "sw" and swFrame
        if row then
            for j = 1, #row.pips - 1 do
                local pip = row.pips[j]
                Sep(g.x + pip._edrX + pip._edrW + Centre(spacing), g.y, px, g.h)
            end
        end
    end
    for i = n + 1, #col.seps do col.seps[i]:Hide() end
end

-- Whirling Surge icon per bar style: Blizzard = action button frame, rounded
-- mask and rounded swipe; Classic WoW UI = the vanilla slot ring; modern = the
-- plain cropped square. The cooldown text is lifted above any frame.
local function ApplyIconArt(chrome)
    local f = wsIcon
    if chrome and not f.artFrame then
        f.artFrame = CreateFrame("Frame", nil, f)
        f.artFrame:SetAllPoints(f)
        f.artFrame:SetFrameLevel(f.cd:GetFrameLevel() + 1)
        f.textFrame:SetFrameLevel(f.cd:GetFrameLevel() + 2)
    end
    if chrome == "blizzard" and not f.blizzFrame then
        f.blizzFrame = f.artFrame:CreateTexture(nil, "OVERLAY")
        f.blizzFrame:SetAtlas(BLIZZ_ICON.frame)
        f.blizzFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        f.blizzMask = f:CreateMaskTexture()
        f.blizzMask:SetAtlas(BLIZZ_ICON.mask, false, nil, nil,
            "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        f.blizzMask:SetPoint("CENTER", f.tex, "CENTER")
        -- The mask art has transparent padding around its rounded square, so it
        -- is sized from its own atlas (scaled like the icon), not to the icon.
        local info = C_Texture.GetAtlasInfo(BLIZZ_ICON.mask)
        f.blizzMaskW = info and info.width or BLIZZ_ICON.iconSize
        f.blizzMaskH = info and info.height or BLIZZ_ICON.iconSize
    end
    if chrome == "classic" and not f.classicRing then
        f.classicRing = f.artFrame:CreateTexture(nil, "OVERLAY")
        f.classicRing:SetTexture(BLIZZ_ICON.ring)
        f.classicRing:SetSnapToPixelGrid(false)
        f.classicRing:SetTexelSnappingBias(0)
    end

    local size = f:GetHeight()
    if f.blizzFrame then
        local on = chrome == "blizzard"
        f.blizzFrame:SetShown(on)
        if on then
            local s = size / BLIZZ_ICON.iconSize
            f.blizzFrame:SetSize(BLIZZ_ICON.frameW * s, BLIZZ_ICON.frameH * s)
            f.blizzMask:SetSize(f.blizzMaskW * s, f.blizzMaskH * s)
        end
        if on ~= (f.blizzMasked or false) then
            if on then
                f.tex:AddMaskTexture(f.blizzMask)
                f.cd:SetSwipeTexture(BLIZZ_ICON.swipe)
            else
                f.tex:RemoveMaskTexture(f.blizzMask)
                f.cd:SetSwipeTexture("")
            end
            f.blizzMasked = on
        end
    end
    if f.classicRing then
        local on = chrome == "classic"
        f.classicRing:SetShown(on)
        if on then
            f.classicRing:ClearAllPoints()
            f.classicRing:SetPoint("CENTER", f, "CENTER", 0, -size / 36)
            f.classicRing:SetSize(size * 66 / 36, size * 66 / 36)
        end
    end
    if chrome == "blizzard" then
        f.tex:SetTexCoord(0, 1, 0, 1)
    else
        f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end

-- Resolve a classic atlas by its texture-kit name, falling back to the "-2x"
-- member name in case a client only registers that one. nil = art missing.
local classicAtlasCache = {}
local function ClassicAtlas(suffix)
    local hit = classicAtlasCache[suffix]
    if hit ~= nil then return hit or nil end
    local name = CLASSIC.kit .. "_" .. suffix
    if not C_Texture.GetAtlasInfo(name) then
        name = name .. "-2x"
        if not C_Texture.GetAtlasInfo(name) then name = false end
    end
    classicAtlasCache[suffix] = name
    return name or nil
end

local function SetClassicArt(tex, suffix, w, h)
    local atlas = ClassicAtlas(suffix)
    if atlas then tex:SetAtlas(atlas) end
    tex:SetSize(w, h)
    return atlas
end

local function AddAlphaStep(group, from, to, duration, order, endDelay)
    local a = group:CreateAnimation("Alpha")
    a:SetFromAlpha(from)
    a:SetToAlpha(to)
    a:SetDuration(duration)
    a:SetOrder(order)
    if endDelay then a:SetEndDelay(endDelay) end
end

-- One gem. Frame levels stand in for the template's draw layers: background on
-- the cell, fill bar one level up, frame/spark/flash one above that.
local function CreateClassicCell(parent)
    local C = CLASSIC
    local cell = CreateFrame("Frame", nil, parent)
    cell:SetSize(C.cellW, C.cellH)

    cell.bg = cell:CreateTexture(nil, "BACKGROUND")
    cell.bg:SetPoint("CENTER")
    SetClassicArt(cell.bg, "background", C.bgW, C.bgH)

    local bar = CreateFrame("StatusBar", nil, cell)
    bar:SetOrientation("VERTICAL")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:SetPoint("CENTER")
    bar:SetSize(C.fillW, C.fillH)
    bar:SetFrameLevel(cell:GetFrameLevel() + 1)
    cell.bar = bar
    cell.fillAtlas     = ClassicAtlas("fill")
    cell.fillFullAtlas = ClassicAtlas("fillfull")
    if cell.fillAtlas then bar:SetStatusBarTexture(cell.fillAtlas) end
    cell.isFull = false

    local flipAtlas = ClassicAtlas("fill_flipbook")
    if flipAtlas then
        cell.flip = bar:CreateTexture(nil, "OVERLAY")
        cell.flip:SetAllPoints(bar)
        cell.flip:SetAtlas(flipAtlas)
        cell.flip:Hide()
        cell.flipMask = bar:CreateMaskTexture()
        cell.flipMask:SetAtlas("AlphaMask2", true, nil, nil,
            "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        cell.flipMask:SetPoint("TOP", bar:GetStatusBarTexture(), "TOP", 0, 0)
        cell.flip:AddMaskTexture(cell.flipMask)
        cell.flipAnim = cell.flip:CreateAnimationGroup()
        cell.flipAnim:SetLooping("REPEAT")
        local fb = cell.flipAnim:CreateAnimation("FlipBook")
        fb:SetDuration(1.2)
        fb:SetFlipBookRows(5)
        fb:SetFlipBookColumns(4)
        fb:SetFlipBookFrames(20)
    end

    local ov = CreateFrame("Frame", nil, cell)
    ov:SetAllPoints(cell)
    ov:SetFrameLevel(cell:GetFrameLevel() + 2)
    cell.overlay = ov

    cell.spark = ov:CreateTexture(nil, "OVERLAY")
    cell.spark:SetBlendMode("ADD")
    SetClassicArt(cell.spark, "spark", C.sparkW, C.sparkH)
    cell.spark:SetPoint("CENTER", bar:GetStatusBarTexture(), "TOP", 0, 0)
    cell.spark:Hide()
    local maskAtlas = ClassicAtlas("mask")
    if maskAtlas then
        local mask = ov:CreateMaskTexture()
        mask:SetAtlas(maskAtlas, false, nil, nil,
            "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetSize(C.maskW, C.maskH)
        mask:SetPoint("CENTER", cell, "CENTER")
        cell.spark:AddMaskTexture(mask)
    end

    cell.frame = ov:CreateTexture(nil, "OVERLAY", nil, 1)
    cell.frame:SetPoint("CENTER", cell, "CENTER")
    SetClassicArt(cell.frame, "frame", C.frameW, C.frameH)

    cell.flash = ov:CreateTexture(nil, "OVERLAY", nil, 1)
    cell.flash:SetBlendMode("ADD")
    cell.flash:SetPoint("CENTER", cell, "CENTER")
    SetClassicArt(cell.flash, "flash", C.frameW, C.frameH)
    cell.flash:SetAlpha(0)

    cell.flashAnim = cell.flash:CreateAnimationGroup()
    cell.flashAnim:SetToFinalAlpha(true)
    AddAlphaStep(cell.flashAnim, 0, 1, 0.5, 1)
    AddAlphaStep(cell.flashAnim, 1, 0, 0.5, 2)

    cell.pulseAnim = cell.flash:CreateAnimationGroup()
    cell.pulseAnim:SetToFinalAlpha(true)
    cell.pulseAnim:SetLooping("REPEAT")
    AddAlphaStep(cell.pulseAnim, 0, 1, 1.5, 1)
    AddAlphaStep(cell.pulseAnim, 1, 0, 1.5, 2, 0.8)

    return cell
end

-- The gem row at 1x: mirrored decor, six cells, decor. Built on first use only,
-- so the modern style never pays for it.
local function EnsureClassicFrame()
    if classicFrame then return classicFrame end
    local C = CLASSIC
    local f = CreateFrame("Frame", nil, rootFrame)
    f:SetSize(CLASSIC_W, CLASSIC_H)

    f.decorL = f:CreateTexture(nil, "ARTWORK")
    SetClassicArt(f.decorL, "decor", C.decorW, C.decorH)
    f.decorL:SetTexCoord(1, 0, 0, 1)
    f.decorL:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -C.decorTop)
    f.decorR = f:CreateTexture(nil, "ARTWORK")
    SetClassicArt(f.decorR, "decor", C.decorW, C.decorH)
    f.decorR:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -C.decorTop)

    f.cells = {}
    local x = C.decorW + C.edgePad
    for i = 1, SKYRIDING_PIPS do
        local cell = CreateClassicCell(f)
        cell:SetPoint("TOPLEFT", f, "TOPLEFT", x, 0)
        -- Level above the decor so the end gems overlap the wings, as they did.
        cell:SetFrameLevel(f:GetFrameLevel() + 1)
        cell.bar:SetFrameLevel(cell:GetFrameLevel() + 1)
        cell.overlay:SetFrameLevel(cell:GetFrameLevel() + 2)
        f.cells[i] = cell
        x = x + C.cellW
    end
    classicFrame = f
    return f
end

-------------------------------------------------------------------------------
--  Build / Rebuild / Redraw
-------------------------------------------------------------------------------
local function LayoutPips(frame, pipCount, width, height, spacing)
    -- Distribute in whole PHYSICAL-pixel units (PP.mult), not whole UI-coordinate
    -- units. 1 UI-unit only equals 1 physical pixel at the "pixel perfect" scale -- at
    -- any other UI Scale, flooring to whole UI-units left a fractional remainder
    -- unassigned, so the last pip fell short of the frame's actual right edge (the
    -- "extra spacing between charges and Whirling Surge" report, reproducible at UI
    -- scales where that leftover doesn't round away to ~0).
    local PPdr = EllesmereUI and EllesmereUI.PP
    local px = (PPdr and PPdr.mult and PPdr.mult > 0) and PPdr.mult or 1
    local widthAvail = max(0, width - (pipCount - 1) * spacing)
    -- If the whole row doesn't span even one physical pixel (a very small bar at a low
    -- UI Scale, where px itself is large), snapping to whole physical-pixel units would
    -- floor every pip to 0 width -- pips vanishing entirely is worse than the sub-pixel
    -- gap this fix targets. Fall back to plain UI-unit distribution (pre-fix behavior)
    -- in that degenerate case so pips stay visible, just not perfectly pixel-snapped.
    if widthAvail < px then px = 1 end
    local totalUnits = floor(widthAvail / px + 1e-6)
    -- Cumulative boundary = floor(totalUnits * i / pipCount), not a fixed
    -- remainder lumped onto the first N pips. The two pip rows (6 and 3
    -- charges) share the same widthAvail and pipCount is an exact multiple
    -- between them, so this formula lands every 2nd Skyward Ascent divider
    -- on the exact same physical pixel as a Second Wind divider -- a
    -- per-row remainder would drift the two rows' dividers by up to 1px
    -- relative to each other even though they should align.
    local x = 0
    local prevBoundary = 0
    for i = 1, pipCount do
        local boundary = floor(totalUnits * i / pipCount + 1e-6)
        local thisW = (boundary - prevBoundary) * px
        prevBoundary = boundary
        local pip = frame.pips[i]
        pip:ClearAllPoints()
        pip:SetPoint("TOPLEFT", frame, "TOPLEFT", x, 0)
        pip:SetSize(thisW, height)
        pip._edrX, pip._edrW = x, thisW
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
    local L = ComputeLayout(p)

    rootFrame:SetSize(L.totalW, L.totalH)

    -- Column rows, bottom to top, the column centred on the icon. Rows not in
    -- the layout are hidden; rows that stay are never hidden and re-shown.
    -- Every frame here is SHOWN BEFORE it is anchored, sized and has its pips
    -- laid out: a row or icon re-anchored while hidden and shown afterwards
    -- (Vigor Style Bars <-> Classic Gems, a row or the icon toggled back on)
    -- drew its pips piled up or not at all until a later pass.
    local rowFrames = { speed = speedBar, sky = stackFrame, sw = swFrame }
    local inLayout = {}
    for _, key in ipairs(L.rows) do inLayout[key] = true end
    for key, f in pairs(rowFrames) do
        if not inLayout[key] then f:Hide() end
    end
    local spacing = p.stackSpacing
    local clusterX = PPSnap((L.totalW - L.clusterW) / 2)
    local y = L.colY + L.ov
    local geo = {}
    for i, key in ipairs(L.rows) do
        local f = rowFrames[key]
        local h = p[ROW_FIELD[key]]
        local rx, ry = clusterX + L.padX, y
        geo[i] = { key = key, x = rx, y = ry, h = h }
        f:Show()
        f:ClearAllPoints()
        f:SetPoint("BOTTOMLEFT", rootFrame, "BOTTOMLEFT", rx, ry)
        f:SetSize(p.width, h)
        if key == "sky" then
            LayoutPips(stackFrame, SKYRIDING_PIPS, p.width, h, spacing)
        elseif key == "sw" then
            LayoutPips(swFrame, SECONDWIND_PIPS, p.width, h, spacing)
        end
        y = y + h + p.gap
    end
    ApplyColumnChrome(L, geo, p.width, p.gap, spacing)

    if L.icon then
        wsIcon:Show()
        wsIcon:ClearAllPoints()
        wsIcon:SetPoint("BOTTOMLEFT", rootFrame, "BOTTOMLEFT",
            clusterX + L.colW + (L.colW > 0 and p.gap or 0), L.iconY)
        wsIcon:SetSize(L.iconSize, L.iconSize)
    else
        wsIcon:Hide()
    end
    ApplyIconArt(L.chrome)

    if L.classic then
        local f = EnsureClassicFrame()
        f:Show()
        f:SetScale(L.scale)
        f:ClearAllPoints()
        -- Offsets on a scaled frame are in its own units.
        f:SetPoint("TOPLEFT", rootFrame, "TOPLEFT", PPSnap((L.totalW - L.classicW) / 2) / L.scale, 0)
    elseif classicFrame then
        classicFrame:Hide()
    end

    Redraw(L)
    ApplyPos()
    UpdateVisibility()
end

-- L = the layout Rebuild already computed, or nil to compute it here.
function Redraw(L)
    if not rootFrame then return end
    local p = db.profile
    L = L or ComputeLayout(p)

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

    ApplyBordersAll(L)

    -- Bar style bevel (the column frame is laid out by Rebuild).
    ApplyRowChrome(speedBar, L.chrome, p.width, p.speedHeight)
    ApplyRowChrome(stackFrame, L.chrome, p.width, p.skyridingHeight)
    ApplyRowChrome(swFrame, L.chrome, p.width, p.secondWindHeight)

    skyridingDirty  = true
    secondWindDirty = true
    whirlingDirty   = true
    lastSkyCur, lastSkyProgress = -1, -1
    lastSwCur,  lastSwProgress  = -1, -1
    lastClassicCur, lastClassicProgress = -1, -1
    lastSoundCur = -1
    lastCdStart, lastCdDur      = -1, -1
    -- Settings applied: the repaint above rides the tick, so arm it if shown.
    SyncTick()
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
                local L = ComputeLayout(db.profile)
                return L.totalW, L.totalH
            end,
            setWidth = function(_, w)
                local p = db.profile
                local L = ComputeLayout(p)
                if L.colW == 0 then
                    -- No bars in the column: the handle scales the gems, if any.
                    if L.classic then
                        p.classicScale = max(0.5, min(2, floor(w / CLASSIC_W * 100 + 0.5) / 100))
                        Rebuild()
                    end
                    return
                end
                -- getSize reports the even-pixel total: take that rounding back
                -- off so a size restore (w = the reported total) is a no-op.
                local clusterW = w - (L.totalW - L.rawW)
                -- A gem row wider than the bars sets the width by itself; the
                -- column only follows the handle once it is dragged past it.
                if L.classicW > L.clusterW and clusterW <= L.classicW then return end
                local iconPart = L.icon and (p.gap + L.iconSize) or 0
                p.width = max(60, PPSnap(clusterW - iconPart - 2 * L.padX))
                Rebuild()
            end,
            -- Height is built from independently-sized bars (Second Wind, modern
            -- charges, Speed) plus fixed gaps, the icon beside them, and the classic
            -- gem row when that style is on -- there's no single "height" field to
            -- write. Scale the icon and the shown bars by the same factor toward
            -- the requested total, matching how the Options page's size sliders
            -- combine, then clamp each to its own Options-page slider range
            -- (bars 2-24 / 2-24 / 4-40, icon 16-80) so a drag can't push one to
            -- zero or past its usable size.
            setHeight = function(_, h)
                local p = db.profile
                local L = ComputeLayout(p)
                if L.clusterH == 0 then
                    if L.classic then
                        p.classicScale = max(0.5, min(2, floor(h / CLASSIC_H * 100 + 0.5) / 100))
                        Rebuild()
                    end
                    return
                end
                -- Undo getSize's even-pixel rounding (see setWidth).
                local newTotalH = PPSnap(h) - (L.totalH - L.rawH)
                local classicPart = L.classic and (L.classicH + p.gap) or 0
                local k = max(8, newTotalH - classicPart) / L.clusterH
                if L.icon and p.iconSize then
                    p.iconSize = max(16, min(80, floor(L.iconSize * k + 0.5)))
                end
                local rows = L.rows
                if #rows == 0 then Rebuild(); return end
                -- Each row's frame rim is a fixed size, not scaled with the bar.
                local targetSum = max(#rows * 2,
                    floor(L.colH * k - (#rows - 1) * p.gap - 2 * L.ov + 0.5))

                local bars = {}
                for _, key in ipairs(rows) do
                    local field = ROW_FIELD[key]
                    bars[#bars + 1] = { field = field, lo = ROW_RANGE[field][1], hi = ROW_RANGE[field][2] }
                end
                local oldSum = 0
                for _, b in ipairs(bars) do
                    b.old = p[b.field]
                    oldSum = oldSum + b.old
                end
                if oldSum <= 0 then
                    -- Corrupted/legacy profile (e.g. hand-edited SavedVariables)
                    -- with every shown height at/under zero: reset to defaults so
                    -- the control self-heals instead of silently no-op'ing forever.
                    for _, b in ipairs(bars) do p[b.field] = DB_DEFAULTS.profile[b.field] end
                    Rebuild()
                    return
                end

                local scale = targetSum / oldSum
                for _, b in ipairs(bars) do
                    b.new = max(b.lo, min(b.hi, floor(b.old * scale + 0.5)))
                end

                -- A bar already at its min/max absorbs none of a further shrink/grow,
                -- so plain proportional scaling can leave the resize handle feeling
                -- stuck once one or two bars saturate. Hand any leftover delta to
                -- whichever bar(s) still have headroom instead of discarding it
                -- (bounded to one pass per bar so this always terminates).
                for _ = 1, #bars do
                    local sum = 0
                    for _, b in ipairs(bars) do sum = sum + b.new end
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
    evtFrame:RegisterEvent("PLAYER_IS_GLIDING_CHANGED")
    evtFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    evtFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    evtFrame:SetScript("OnEvent", function(_, event)
        if event == "SPELL_UPDATE_CHARGES" then
            skyridingDirty = true
            secondWindDirty = true
            SyncTick()
            return
        elseif event == "SPELL_UPDATE_COOLDOWN" then
            whirlingDirty = true
            SyncTick()
            return
        elseif event == "PLAYER_IS_GLIDING_CHANGED" then
            local isGliding = C_PlayerInfo.GetGlidingInfo()
            _gliding = isGliding == true
            SyncTick()
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
            evtFrame:RegisterEvent("PLAYER_IS_GLIDING_CHANGED")
            evtFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            evtFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
            evtFrame:SetScript("OnEvent", function(_, event)
                if event == "SPELL_UPDATE_CHARGES" then
                    skyridingDirty = true
                    secondWindDirty = true
                    SyncTick()
                    return
                elseif event == "SPELL_UPDATE_COOLDOWN" then
                    whirlingDirty = true
                    SyncTick()
                    return
                elseif event == "PLAYER_IS_GLIDING_CHANGED" then
                    local isGliding = C_PlayerInfo.GetGlidingInfo()
                    _gliding = isGliding == true
                    SyncTick()
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
-- The icon's current size, for the options slider while it is still automatic.
ns.edrIconSize = function()
    local p = db and db.profile
    return p and ComputeLayout(p).iconSize or 34
end
