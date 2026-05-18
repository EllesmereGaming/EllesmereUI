-------------------------------------------------------------------------------
--  EllesmereUIQoL_BattleRes.lua
--  Runtime for the BattleRes icon. Polls GetSpellCharges(20484) and shows
--  the shared raid brez pool (charges + recharge timer) as a single icon.
-------------------------------------------------------------------------------

local BREZ_SPELL_ID = 20484  -- Rebirth -- canonical shared brez pool spell ID

local SHAPE_MEDIA = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\"
local SHAPE_MASKS = {
    circle   = SHAPE_MEDIA .. "circle_mask.tga",
    csquare  = SHAPE_MEDIA .. "csquare_mask.tga",
    diamond  = SHAPE_MEDIA .. "diamond_mask.tga",
    hexagon  = SHAPE_MEDIA .. "hexagon_mask.tga",
    portrait = SHAPE_MEDIA .. "portrait_mask.tga",
    shield   = SHAPE_MEDIA .. "shield_mask.tga",
    square   = SHAPE_MEDIA .. "square_mask.tga",
}
local SHAPE_BORDERS = {
    circle   = SHAPE_MEDIA .. "circle_border.tga",
    csquare  = SHAPE_MEDIA .. "csquare_border.tga",
    diamond  = SHAPE_MEDIA .. "diamond_border.tga",
    hexagon  = SHAPE_MEDIA .. "hexagon_border.tga",
    portrait = SHAPE_MEDIA .. "portrait_border.tga",
    shield   = SHAPE_MEDIA .. "shield_border.tga",
    square   = SHAPE_MEDIA .. "square_border.tga",
}

-- Sits under EllesmereUIQoLDB.profile.battleRes so we don't clobber the
-- existing cursor / QoL feature data that already lives in that SavedVariable.
local defaults = {
    profile = {
        battleRes = {
            enabled        = true,
            visibility     = "MPLUS_AND_RAID",  -- MPLUS_AND_RAID | MPLUS | RAID | NEVER
            iconSize       = 40,
            iconZoom       = 11,   -- percent
            shape          = "none",
            borderSize     = "thin",  -- none / thin / normal / heavy / strong
            borderColor    = { r = 0, g = 0, b = 0, a = 1 },
            borderUseClass = false,
            durationSize   = 12,
            durationOffsetX = 0,
            durationOffsetY = 0,
            countSize      = 11,
            countOffsetX   = 0,
            countOffsetY   = 0,
            pos            = nil,  -- { centerX, centerY } stored after first move
        },
    },
}

local addon = {}
addon.db = nil
local function P()
    return addon.db and addon.db.profile and addon.db.profile.battleRes
end

local frame, iconTex, borderTex, durationFS, countFS, cooldownFrame

-------------------------------------------------------------------------------
--  Shape application
-------------------------------------------------------------------------------
local BORDER_PX = { none = 0, thin = 1, normal = 2, heavy = 3, strong = 4 }

local function _resolveBorderColor(p)
    if p.borderUseClass then
        local _, ct = UnitClass("player")
        if ct and RAID_CLASS_COLORS[ct] then
            return RAID_CLASS_COLORS[ct].r, RAID_CLASS_COLORS[ct].g, RAID_CLASS_COLORS[ct].b, 1
        end
    end
    local c = p.borderColor
    if c then return c.r or 0, c.g or 0, c.b or 0, c.a or 1 end
    return 0, 0, 0, 1
end

local function ApplyShape()
    if not frame then return end
    local p = P()
    if not p then return end

    local PP = EllesmereUI and EllesmereUI.PP
    local shape = p.shape or "none"
    local bs = BORDER_PX[p.borderSize or "thin"] or 1

    -- Frame sizing: square by default; for "cropped" the height is 80% of width
    -- (mirrors Action Bars line 2263: btnH = btnH * 0.80).
    local size = p.iconSize or 40
    local fw, fh = size, size
    if shape == "cropped" then fh = math.floor(size * 0.80 + 0.5) end
    frame:SetSize(fw, fh)
    iconTex:ClearAllPoints()
    iconTex:SetAllPoints(frame)

    -- Cooldown swirl: covers the icon area.
    if cooldownFrame then
        cooldownFrame:ClearAllPoints()
        cooldownFrame:SetAllPoints(frame)
    end

    -- Duration text (centered) and count text (bottom-right) -- positioned for
    -- every shape since the early-return below would otherwise skip them.
    durationFS:SetFont(STANDARD_TEXT_FONT, p.durationSize or 12, "OUTLINE")
    durationFS:ClearAllPoints()
    durationFS:SetPoint("CENTER", frame, "CENTER",
        p.durationOffsetX or 0, p.durationOffsetY or 0)

    countFS:SetFont(STANDARD_TEXT_FONT, p.countSize or 11, "OUTLINE")
    countFS:ClearAllPoints()
    countFS:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT",
        -2 + (p.countOffsetX or 0), 2 + (p.countOffsetY or 0))

    -----------------------------------------------------------------------
    --  BASE CASE: "none" or "cropped" -- plain texture, no mask
    -----------------------------------------------------------------------
    if shape == "none" or shape == "cropped" then
        if iconTex._mask then
            -- Remove the mask from the cooldown swipe and reset its
            -- swipe texture BEFORE we nil out the mask reference.
            -- Otherwise the swipe stays cropped to the previous shape.
            if cooldownFrame and not cooldownFrame:IsForbidden() then
                pcall(cooldownFrame.RemoveMaskTexture, cooldownFrame, iconTex._mask)
                if cooldownFrame.SetSwipeTexture then
                    pcall(cooldownFrame.SetSwipeTexture, cooldownFrame, "")
                end
            end
            iconTex:RemoveMaskTexture(iconTex._mask)
            iconTex._mask:SetTexture(nil)
            iconTex._mask:ClearAllPoints()
            iconTex._mask:SetSize(0.001, 0.001)
            iconTex._mask:Hide()
            iconTex._mask = nil
        end
        borderTex:Hide()  -- shape-border atlas is for custom shapes only

        local z = (p.iconZoom or 11) / 100
        if shape == "cropped" then
            iconTex:SetTexCoord(z, 1 - z, z + 0.10, 1 - z - 0.10)
        elseif z > 0 then
            iconTex:SetTexCoord(z, 1 - z, z, 1 - z)
        else
            iconTex:SetTexCoord(0, 1, 0, 1)
        end

        -- Pixel-perfect border via PP.CreateBorder (canonical EUI pattern).
        if PP then
            if not PP.GetBorders(frame) then PP.CreateBorder(frame, 0, 0, 0, 1, 1, "OVERLAY", 2) end
            if bs > 0 then
                local r, g, b, a = _resolveBorderColor(p)
                PP.UpdateBorder(frame, bs, r, g, b, a)
                PP.ShowBorder(frame)
            else
                PP.HideBorder(frame)
            end
        end
        return
    end

    -----------------------------------------------------------------------
    --  CUSTOM SHAPE: apply mask + shape-matching border overlay
    -----------------------------------------------------------------------
    if PP then PP.HideBorder(frame) end

    local maskPath = SHAPE_MASKS[shape]
    if maskPath then
        if not iconTex._mask then
            iconTex._mask = frame:CreateMaskTexture()
            iconTex._mask:SetAllPoints(iconTex)
            iconTex:AddMaskTexture(iconTex._mask)
        end
        iconTex._mask:SetTexture(maskPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        iconTex._mask:Show()
        iconTex:SetTexCoord(0, 1, 0, 1)
        -- Crop the cooldown swipe to the same shape (matches action bar
        -- behavior). Adds the icon's mask to the cooldown frame and uses
        -- the mask path as the swipe texture so the spinning swipe
        -- follows the custom outline rather than a square.
        if cooldownFrame and not cooldownFrame:IsForbidden() then
            pcall(cooldownFrame.AddMaskTexture, cooldownFrame, iconTex._mask)
            if cooldownFrame.SetSwipeTexture then
                pcall(cooldownFrame.SetSwipeTexture, cooldownFrame, maskPath)
            end
        end
    elseif cooldownFrame and not cooldownFrame:IsForbidden() then
        -- Default shape: remove any prior mask + restore default swipe.
        if iconTex._mask then
            pcall(cooldownFrame.RemoveMaskTexture, cooldownFrame, iconTex._mask)
        end
        if cooldownFrame.SetSwipeTexture then
            pcall(cooldownFrame.SetSwipeTexture, cooldownFrame, "")
        end
    end

    local borderPath = SHAPE_BORDERS[shape]
    if borderPath and bs > 0 then
        borderTex:SetTexture(borderPath)
        borderTex:ClearAllPoints()
        borderTex:SetPoint("TOPLEFT", frame, "TOPLEFT", -bs, bs)
        borderTex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", bs, -bs)
        local r, g, b, a = _resolveBorderColor(p)
        borderTex:SetVertexColor(r, g, b, a)
        borderTex:Show()
    else
        borderTex:Hide()
    end

end

-------------------------------------------------------------------------------
--  Position
-------------------------------------------------------------------------------
local function ApplyPosition()
    if not frame then return end
    local p = P()
    if not p then return end
    local pos = p.pos
    frame:ClearAllPoints()
    if pos and pos.centerX and pos.centerY then
        frame:SetPoint("CENTER", UIParent, "CENTER", pos.centerX, pos.centerY)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
    end
end

local function SavePosition()
    if not frame or not addon.db then return end
    local left, bottom = frame:GetLeft(), frame:GetBottom()
    if not left or not bottom then return end
    local fw, fh = frame:GetSize()
    local cx = left + fw / 2 - UIParent:GetWidth() / 2
    local cy = bottom + fh / 2 - UIParent:GetHeight() / 2
    local p = P(); if p then p.pos = { centerX = cx, centerY = cy } end
end

-------------------------------------------------------------------------------
--  Visibility -- driven by encounter / keystone events, not polling.
-------------------------------------------------------------------------------
local _state = {
    inEncounter     = false,
    encounterIsRaid = false,
    inChallenge     = false,
}

local function _activeKeystoneLevel()
    -- IsChallengeModeActive only returns true when the timer is running,
    -- not just from having a keystone in bags inside a dungeon.
    if not C_ChallengeMode then return nil end
    if not C_ChallengeMode.IsChallengeModeActive or not C_ChallengeMode.IsChallengeModeActive() then
        return nil
    end
    if C_ChallengeMode.GetActiveKeystoneInfo then
        local lvl = C_ChallengeMode.GetActiveKeystoneInfo()
        return (lvl and lvl > 0) and lvl or nil
    end
    return nil
end

local function ShouldShow()
    local p = P()
    if not p or not p.enabled then return false end
    local v = p.visibility or "MPLUS_AND_RAID"
    if v == "NEVER" then return false end

    -- Hard gate: must be in a party or raid instance. Prevents any
    -- stuck state from showing the icon in town/open world.
    -- Unlock mode relies on the overlay mover for positioning feedback,
    -- so we never force-show the real icon here -- it would persist past
    -- an "exit without saving" since DoClose doesn't re-run visibility.
    local _, instanceType = GetInstanceInfo()
    if instanceType ~= "party" and instanceType ~= "raid" then return false end

    local wantMPlus = (v == "MPLUS_AND_RAID" or v == "MPLUS")
    local wantRaid  = (v == "MPLUS_AND_RAID" or v == "RAID")
    if wantMPlus and _state.inChallenge then return true end
    if wantRaid and _state.inEncounter and _state.encounterIsRaid then return true end
    return false
end

-------------------------------------------------------------------------------
--  Polling
-------------------------------------------------------------------------------
local function FormatTime(s)
    if not s or s <= 0 then return "" end
    local m = math.floor(s / 60)
    local sec = math.floor(s % 60)
    return string.format("%d:%02d", m, sec)
end

local _lastCountText, _lastDurText, _lastCountColor
local function _setCount(s, isZero)
    if s ~= _lastCountText then
        countFS:SetText(s)
        _lastCountText = s
    end
    local key = isZero and "zero" or "ok"
    if key ~= _lastCountColor then
        if isZero then countFS:SetTextColor(1, 0.2, 0.2, 1)
        else           countFS:SetTextColor(1, 1, 1, 1) end
        _lastCountColor = key
    end
end
local function _setDur(s)
    if s ~= _lastDurText then
        durationFS:SetText(s)
        _lastDurText = s
    end
end

local function PollCharges()
    if not frame then return end
    local info = C_Spell and C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(BREZ_SPELL_ID)
    if not info or not info.maxCharges then
        _setCount("", false); _setDur("")
        return
    end
    local charges, maxCharges = info.currentCharges, info.maxCharges
    _setCount(tostring(charges), charges <= 0)

    if charges < maxCharges and info.cooldownStartTime and info.cooldownDuration and info.cooldownDuration > 0 then
        local remaining = (info.cooldownStartTime + info.cooldownDuration) - GetTime()
        _setDur(remaining > 0 and FormatTime(remaining) or "")
        if cooldownFrame then
            cooldownFrame:SetCooldown(info.cooldownStartTime, info.cooldownDuration)
        end
    else
        _setDur("")
        if cooldownFrame then cooldownFrame:Clear() end
    end
end

-- Ticker only runs while the icon is actually visible.
local _ticker
local function UpdateVisibility()
    if not frame then return end
    if ShouldShow() then
        if not frame:IsShown() then frame:Show() end
        if not _ticker then
            _ticker = C_Timer.NewTicker(0.5, PollCharges)
        end
        PollCharges()
    else
        if frame:IsShown() then frame:Hide() end
        if _ticker then _ticker:Cancel(); _ticker = nil end
    end
end
_G._EUI_BattleRes_UpdateVisibility = UpdateVisibility

-------------------------------------------------------------------------------
--  Frame creation
-------------------------------------------------------------------------------
local function CreateBrezFrame()
    if frame then return frame end
    frame = CreateFrame("Frame", "EllesmereUIBattleResIcon", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetSize(40, 40)
    frame:Hide()

    iconTex = frame:CreateTexture(nil, "ARTWORK")
    iconTex:SetAllPoints(frame)
    local brezIcon
    if C_Spell and C_Spell.GetSpellTexture then
        brezIcon = C_Spell.GetSpellTexture(BREZ_SPELL_ID)
    end
    iconTex:SetTexture(brezIcon or 136080)
    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    borderTex = frame:CreateTexture(nil, "OVERLAY")
    borderTex:Hide()

    cooldownFrame = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cooldownFrame:SetAllPoints(frame)
    cooldownFrame:SetDrawEdge(false)
    cooldownFrame:SetHideCountdownNumbers(true)  -- we render our own duration text
    cooldownFrame:SetFrameLevel(frame:GetFrameLevel() + 1)

    durationFS = cooldownFrame:CreateFontString(nil, "OVERLAY")
    durationFS:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    durationFS:SetText("")

    countFS = cooldownFrame:CreateFontString(nil, "OVERLAY")
    countFS:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    countFS:SetText("")

    return frame
end

-------------------------------------------------------------------------------
--  Apply (settings entry point)
-------------------------------------------------------------------------------
local function Apply()
    if not addon.db then return end
    if not frame then CreateBrezFrame() end
    ApplyShape()
    ApplyPosition()
    UpdateVisibility()
end
_G._EUI_BattleRes_Apply = Apply

-------------------------------------------------------------------------------
--  Event handler -- mirrors EllesmereUIMythicTimer's keystone events plus
--  ENCOUNTER_START/END (BigWigs's pattern for raid bosses).
-------------------------------------------------------------------------------
local _eventFrame
local function _refreshKeystoneState()
    _state.inChallenge = _activeKeystoneLevel() ~= nil
end

local function _refreshEncounterState()
    _state.inEncounter = IsEncounterInProgress() or false
    if _state.inEncounter then
        local _, instanceType = GetInstanceInfo()
        _state.encounterIsRaid = (instanceType == "raid")
    else
        _state.encounterIsRaid = false
    end
end

local function OnEvent(_, event, encounterID, encounterName, difficultyID, groupSize, success)
    if event == "ENCOUNTER_START" then
        _state.inEncounter = true
        local _, instanceType = GetInstanceInfo()
        _state.encounterIsRaid = (instanceType == "raid")
    elseif event == "ENCOUNTER_END" then
        _state.inEncounter = false
        _state.encounterIsRaid = false
    elseif event == "CHALLENGE_MODE_START" or event == "WORLD_STATE_TIMER_START" then
        _refreshKeystoneState()
    elseif event == "CHALLENGE_MODE_COMPLETED"
        or event == "CHALLENGE_MODE_RESET"
        or event == "WORLD_STATE_TIMER_STOP" then
        _state.inChallenge = false
    elseif event == "PLAYER_ENTERING_WORLD" then
        _refreshEncounterState()
        _refreshKeystoneState()
    end
    UpdateVisibility()
end

local function _registerEvents()
    if _eventFrame then return end
    _eventFrame = CreateFrame("Frame")
    _eventFrame:RegisterEvent("ENCOUNTER_START")
    _eventFrame:RegisterEvent("ENCOUNTER_END")
    _eventFrame:RegisterEvent("CHALLENGE_MODE_START")
    _eventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    _eventFrame:RegisterEvent("CHALLENGE_MODE_RESET")
    _eventFrame:RegisterEvent("WORLD_STATE_TIMER_START")
    _eventFrame:RegisterEvent("WORLD_STATE_TIMER_STOP")
    _eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    _eventFrame:SetScript("OnEvent", OnEvent)
end

-------------------------------------------------------------------------------
--  Unlock mode registration
-------------------------------------------------------------------------------
local function RegisterUnlock()
    if not EllesmereUI or not EllesmereUI.RegisterUnlockElements then return end
    local MK = EllesmereUI.MakeUnlockElement
    if not MK then return end

    EllesmereUI:RegisterUnlockElements({
        MK({
            key   = "EUI_BattleRes",
            label = "Brez",
            group = "Quality of Life",
            order = 600,
            noAnchorTarget = true,  -- icon size changes; nothing should be anchored to it
            isHidden = function()
                local p = P()
                return not p or not p.enabled or (p.visibility == "NEVER")
            end,
            getFrame = function()
                if not frame then CreateBrezFrame() end
                return frame
            end,
            getSize = function()
                local p = P()
                local s = (p and p.iconSize) or 40
                return s, s
            end,
            linkedDimensions = true,  -- always square; one slider drives both
            setWidth = function(_, w)
                local p = P(); if not p then return end
                local PPb = EllesmereUI and EllesmereUI.PP
                p.iconSize = math.max(16, PPb and PPb.Snap(w) or math.floor(w + 0.5))
                Apply()
                if EllesmereUI._unlockActive and EllesmereUI.RepositionBarToMover then
                    EllesmereUI.RepositionBarToMover("EUI_BattleRes")
                end
            end,
            setHeight = function(_, h)
                local p = P(); if not p then return end
                local PPb = EllesmereUI and EllesmereUI.PP
                p.iconSize = math.max(16, PPb and PPb.Snap(h) or math.floor(h + 0.5))
                Apply()
                if EllesmereUI._unlockActive and EllesmereUI.RepositionBarToMover then
                    EllesmereUI.RepositionBarToMover("EUI_BattleRes")
                end
            end,
            savePos = function(_, point, relPoint, x, y)
                local p = P(); if not p then return end
                if frame and frame:GetLeft() then
                    SavePosition()
                else
                    p.pos = { centerX = x, centerY = y }
                end
            end,
            loadPos = function()
                local p = P()
                if p and p.pos then
                    return { point = "CENTER", relPoint = "CENTER", x = p.pos.centerX, y = p.pos.centerY }
                end
                return nil
            end,
            clearPos = function()
                local p = P(); if p then p.pos = nil end
            end,
            applyPos = function()
                ApplyPosition()
            end,
        }),
    })
end
_G._EUI_BattleRes_RegisterUnlock = RegisterUnlock

-------------------------------------------------------------------------------
--  Init
-------------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    if not EllesmereUI or not EllesmereUI.Lite or not EllesmereUI.Lite.NewDB then
        return
    end
    addon.db = EllesmereUI.Lite.NewDB("EllesmereUIQoLDB", defaults, true)
    _G._EUI_BattleRes_DB = function() return addon.db end
    CreateBrezFrame()
    _registerEvents()
    _refreshEncounterState()
    _refreshKeystoneState()
    Apply()
    RegisterUnlock()
end)
