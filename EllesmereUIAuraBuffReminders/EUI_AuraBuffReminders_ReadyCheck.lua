if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_AuraBuffReminders_ReadyCheck.lua
--
--  The Ready Check mana warning.
--  Reads the earlier AuraBuff Reminders files through ns._abrInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._abrInternals
-- EllesmereUIAuraBuffReminders.lua or an earlier AuraBuff Reminders file
-- failed to load.
if not I or I.broken then return end
I.broken = true

local EABR, ResolveFontPath = I.EABR, I.ResolveFontPath

local db
I.dbSetters[#I.dbSetters + 1] = function(v) db = v end

-------------------------------------------------------------------------------
--  Ready Check Mana Warning: centered text warning for ~10s when a ready check fires in a raid and the player is a healer under 80% mana. Out-of-combat only.
-------------------------------------------------------------------------------
local SetupReadyCheckManaWarning = function()
    local warnFrame, warnFS, warnTimer, warnCurve

    -- Helpers hang on EABR, not block locals; settings slice (db.profile.consumables, options "Ready Check Mana Warning" row) is fetched inline per helper.

    -- Default ON: the warning predates its toggle, so a missing key = enabled.
    function EABR.RCWEnabled()
        local p = db and db.profile
        local c = p and p.consumables
        return not c or c.rcManaWarn ~= false
    end

    -- Custom swatch color, or the brightened mana color (the original look).
    function EABR.RCWColor()
        local p = db and db.profile
        local c = p and p.consumables
        local col = c and c.rcManaWarnColor
        if col and col.r then return col.r, col.g, col.b end
        local mc = EllesmereUI.GetPowerColor("MANA")
        if mc then
            return math.min(mc.r * 1.5, 1), math.min(mc.g * 1.5, 1), math.min(mc.b * 1.5, 1)
        end
        return 0, 0.825, 1
    end

    local function HideWarning()
        if warnFrame then
            if warnFrame._breathe then warnFrame._breathe:Stop() end
            warnFrame:Hide()
        end
        if warnTimer then warnTimer:Cancel(); warnTimer = nil end
    end

    -- Pushes position/size/color settings onto the built frame; the color curve is rebuilt here since colors bake in at AddPoint time, and an already-visible warning/preview is re-tinted so edits show live.
    function EABR.RCWApplySettings()
        if not warnFrame then return end
        local p = db and db.profile
        local c = p and p.consumables
        warnFrame:ClearAllPoints()
        warnFrame:SetPoint("CENTER", UIParent, "CENTER",
            (c and c.rcManaWarnX) or 0, 75 + ((c and c.rcManaWarnY) or 0))
        local font = ResolveFontPath(c and c.rcManaWarnFont)
        local outline = EllesmereUI.GetFontOutlineFlag("auraBuff")
        EllesmereUI.PrimeFontShadow(warnFS, outline == "" and EllesmereUI.GetFontUseShadow("auraBuff"))
        warnFS:SetFont(font, (c and c.rcManaWarnSize) or 48, outline)
        -- Explicit white instance color: tinted purely via SetVertexColor (curve result); with no instance color it would inherit the primed shadow FontObject's color, which resolves BLACK.
        warnFS:SetTextColor(1, 1, 1, 1)
        local r, g, b = EABR.RCWColor()
        -- Curve: alpha 1 at/below 80%, alpha 0 above; colors the FontString directly via SetVertexColor, using alpha for visibility -- no secret value reads.
        if C_CurveUtil and C_CurveUtil.CreateColorCurve then
            warnCurve = C_CurveUtil.CreateColorCurve()
            warnCurve:AddPoint(0.0,    CreateColor(r, g, b, 1))
            warnCurve:AddPoint(0.80,   CreateColor(r, g, b, 1))
            warnCurve:AddPoint(0.8001, CreateColor(r, g, b, 0))
            warnCurve:AddPoint(1.0,    CreateColor(r, g, b, 0))
        end
        if warnFrame:IsShown() then
            warnFS:SetVertexColor(r, g, b, 1)
        end
    end

    local function BuildWarnFrame()
        if warnFrame then return end
        warnFrame = CreateFrame("Frame", nil, UIParent)
        warnFrame:SetSize(600, 60)
        warnFrame:SetFrameStrata("FULLSCREEN")
        warnFrame:SetFrameLevel(100)
        warnFrame:Hide()
        warnFS = warnFrame:CreateFontString(nil, "OVERLAY")
        warnFS:SetPoint("CENTER")
        -- Breathe animation: fade between 60% and 100% alpha
        local ag = warnFrame:CreateAnimationGroup()
        local fadeOut = ag:CreateAnimation("Alpha")
        fadeOut:SetFromAlpha(1)
        fadeOut:SetToAlpha(0.6)
        fadeOut:SetDuration(0.4)
        fadeOut:SetOrder(1)
        fadeOut:SetSmoothing("IN_OUT")
        local fadeIn = ag:CreateAnimation("Alpha")
        fadeIn:SetFromAlpha(0.6)
        fadeIn:SetToAlpha(1)
        fadeIn:SetDuration(0.4)
        fadeIn:SetOrder(2)
        fadeIn:SetSmoothing("IN_OUT")
        ag:SetLooping("REPEAT")
        warnFrame._breathe = ag
        EABR.RCWApplySettings()
        warnFS:SetText(EllesmereUI.L("LOW MANA"))
    end

    -- Only listens for READY_CHECK OOC AND in a raid; GROUP_ROSTER_UPDATE/zone change track raid membership, PLAYER_REGEN toggles combat state.
    local rcFrame = CreateFrame("Frame")
    local _inRaid = false

    local function UpdateReadyCheckRegistration()
        local shouldListen = _inRaid and not InCombatLockdown() and EABR.RCWEnabled()
        if shouldListen then
            rcFrame:RegisterEvent("READY_CHECK")
        else
            rcFrame:UnregisterEvent("READY_CHECK")
            HideWarning()
        end
    end

    rcFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    rcFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    rcFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    rcFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    rcFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    rcFrame:SetScript("OnEvent", function(_, event)
        if event == "GROUP_ROSTER_UPDATE" or event == "ZONE_CHANGED_NEW_AREA"
           or event == "PLAYER_ENTERING_WORLD" then
            _inRaid = IsInRaid()
            UpdateReadyCheckRegistration()
            return
        end
        if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
            UpdateReadyCheckRegistration()
            return
        end
        -- READY_CHECK (only fires when out of combat AND in raid)
        if not EABR.RCWEnabled() then return end
        local spec = GetSpecialization and GetSpecialization()
        if not spec then return end
        local role = GetSpecializationRole(spec)
        if role ~= "HEALER" then return end
        if not UnitPowerPercent then return end
        BuildWarnFrame()
        EABR.RCWApplySettings()
        if not warnCurve then return end
        -- Lets WoW's C side evaluate mana% against the curve: full alpha below 80%, zero above. SetVertexColor applies the secret RGBA directly -- no reads needed.
        local color = UnitPowerPercent("player", Enum.PowerType.Mana, false, warnCurve)
        if not color or not color.GetRGBA then return end
        warnFS:SetVertexColor(color:GetRGBA())
        warnFrame:Show()
        if warnFrame._breathe and not warnFrame._breathe:IsPlaying() then
            warnFrame._breathe:Play()
        end
        if warnTimer then warnTimer:Cancel() end
        warnTimer = C_Timer.NewTimer(10, HideWarning)
    end)

    -- Options hooks (Consumables -> Ready Check Mana Warning row).
    _G._EABR_RCWarnApply = function()
        BuildWarnFrame()
        EABR.RCWApplySettings()
    end
    -- Preview bypasses the curve (must be visible at any mana level), tinting with the plain configured color (readable constants, no secrets).
    _G._EABR_RCWarnPreview = function()
        BuildWarnFrame()
        EABR.RCWApplySettings()
        if warnTimer then warnTimer:Cancel(); warnTimer = nil end
        local r, g, b = EABR.RCWColor()
        warnFS:SetVertexColor(r, g, b, 1)
        warnFrame:Show()
        if warnFrame._breathe and not warnFrame._breathe:IsPlaying() then
            warnFrame._breathe:Play()
        end
    end
    _G._EABR_RCWarnHidePreview = HideWarning
    _G._EABR_RCWarnUpdateReg = UpdateReadyCheckRegistration
end
-- The warning reads retail spec roles and lives in the consumables options; WoW Forever skips it.
if not EABR.FOREVER then SetupReadyCheckManaWarning() end

I.broken = false
