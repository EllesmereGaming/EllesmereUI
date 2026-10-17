if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_ResourceBars_Totem.lua
--
--  The totem bar.
--  Reads the earlier Resource Bars files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- EllesmereUIResourceBars.lua or an earlier Resource Bars file failed to load.
if not I or I.broken then return end
I.broken = true

local UnitClass, InCombatLockdown = UnitClass, InCombatLockdown

local ERB, GetRBFont, _totemBorderOverlays = I.ERB, I.GetRBFont, I._totemBorderOverlays
local SetTotemBarFrame = I.SetTotemBarFrame

local totemBarFrame
I.totemBarFrameSetters[#I.totemBarFrameSetters + 1] = function(v) totemBarFrame = v end

local _totemHooked = false
local _totemOrigParent
local _totemOrigStrata

-- Totem Bar: reparents Blizzard TotemFrame, repositions buttons in a clean
-- row, adds overlay border frames (our own frames, never written to Blizzard).
local function GetTotemSettings()
    return ERB.db and ERB.db.profile and ERB.db.profile.totemBar
end

-- Effective totem-bar grow direction, clamped to the CURRENT orientation. Horizontal:
-- RIGHT (default, left-anchored/grows-right) / LEFT (fixed right edge, grows left) /
-- CENTER (group centred). Vertical: DOWN (default, top-to-bottom) / UP (fixed bottom
-- edge) / CENTER. The clamp is applied on READ and never written back: a direction
-- valid for the OTHER orientation (e.g. LEFT while vertical) is stale, not wrong, and
-- persisting it would overwrite the user's horizontal choice when they flip orientation
-- and back. Reading through one helper keeps the stored value intact and stops layout
-- and unlock mode's menu from disagreeing. Unset (every existing profile) resolves to
-- the orientation default, reproducing the pre-setting layout exactly.
function EllesmereUI.GetTotemGrowDir()
    local tb = GetTotemSettings()
    local vertical = tb and tb.orientation == "VERTICAL"
    local dir = (tb and tb.growDirection or (vertical and "DOWN" or "RIGHT")):upper()
    if vertical then
        if dir ~= "UP" and dir ~= "DOWN" and dir ~= "CENTER" then dir = "DOWN" end
    else
        if dir ~= "LEFT" and dir ~= "RIGHT" and dir ~= "CENTER" then dir = "RIGHT" end
    end
    return dir, vertical
end

-- Cached layout state to avoid redundant work on every Update hook
local _totemLayoutCache = {}
local _totemActiveSet = {}  -- reusable set for O(1) cleanup lookups

-- The icon cooldown's native countdown number is a C-rendered, secret-safe
-- FontString. We restyle that FontString (font/size/color) but never read its
-- value, giving a clean number with no "s" suffix in place of Blizzard's "Xs"
-- Duration text (which is a protected secret value we cannot read or rewrite).
local function GetCooldownNumberFS(cd)
    if not (cd and cd.GetRegions) then return nil end
    for _, region in ipairs({ cd:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "FontString" then
            return region
        end
    end
    return nil
end

local function LayoutTotemBar()
    if not totemBarFrame or not TotemFrame then return end
    local tb = GetTotemSettings()
    if not tb or not tb.enabledClasses then return end

    local spacing = tb.spacing or 2
    local PP = EllesmereUI and EllesmereUI.PP
    if PP and PP.Snap then spacing = PP.Snap(spacing) end
    local iconSize = tb.iconSize or 30
    local vertical = (tb.orientation == "VERTICAL")

    -- Use SetScale on TotemFrame rather than SetSize on individual buttons.
    -- Buttons keep their native template size; scale controls visual size.
    local nativeSize = 37
    local iconScale = iconSize / nativeSize

    -- Reparent and position TotemFrame every call (Blizzard's Update can reset these)
    TotemFrame:SetParent(totemBarFrame)
    TotemFrame:SetFrameStrata(tb.frameStrata or "MEDIUM")
    -- Effective grow direction, resolved through the shared helper below so the
    -- layout and unlock mode's menu can never disagree about it.
    local _growDir = EllesmereUI.GetTotemGrowDir()
    TotemFrame:ClearAllPoints()
    if vertical then
        TotemFrame:SetPoint(_growDir == "UP" and "BOTTOM" or "TOP", totemBarFrame,
            _growDir == "UP" and "BOTTOM" or "TOP", 0, 0)   -- DOWN/CENTER anchored TOP (CENTER re-anchored below)
    else
        TotemFrame:SetPoint(_growDir == "LEFT" and "RIGHT" or "LEFT", totemBarFrame,
            _growDir == "LEFT" and "RIGHT" or "LEFT", 0, 0)  -- RIGHT/CENTER anchored LEFT (CENTER re-anchored below)
    end
    TotemFrame:Show()

    -- Only re-apply scale when setting changed
    local cache = _totemLayoutCache
    if cache.iconScale ~= iconScale then
        TotemFrame:SetScale(iconScale)
        cache.iconScale = iconScale
    end

    -- Collect active totem buttons (reuse table)
    local buttons = cache.buttons
    if not buttons then buttons = {}; cache.buttons = buttons end
    local count = 0
    for _, child in ipairs({ TotemFrame:GetChildren() }) do
        if child:IsShown() and child.Icon and child:GetObjectType() == "Button" then
            count = count + 1
            buttons[count] = child
        end
    end
    -- Trim stale entries
    for i = count + 1, #buttons do buttons[i] = nil end

    -- CENTER grow: re-anchor TotemFrame so the icon group is centred. `total` is
    -- the group's VISUAL extent (iconSize/spacing are screen units), but SetPoint
    -- offsets land in TotemFrame's own scale space (SetScale(iconScale)), so the
    -- offset must be divided by that scale, like `spacing / iconScale` below.
    -- Without it the group sits at iconScale of the intended shift, off-centre by
    -- an error that grows with every extra totem.
    if _growDir == "CENTER" and count > 0 then
        local total = count * iconSize + math.max(0, count - 1) * spacing
        local half = (iconScale > 0) and (total / (2 * iconScale)) or (total / 2)
        TotemFrame:ClearAllPoints()
        if vertical then
            TotemFrame:SetPoint("TOP", totemBarFrame, "CENTER", 0, half)
        else
            TotemFrame:SetPoint("LEFT", totemBarFrame, "CENTER", -half, 0)
        end
    end

    local scaledSpacing = spacing / iconScale
    local zoom = 0.055
    local timerSize = tb.timerSize or 11
    local scaledTimerSize = math.max(6, math.floor(timerSize / iconScale + 0.5))
    local fontPath = GetRBFont()
    local outlineMode = EllesmereUI.GetFontOutlineFlag("resourceBars")

    wipe(_totemActiveSet)
    for i, btn in ipairs(buttons) do
        _totemActiveSet[btn] = true

        btn:ClearAllPoints()
        if i == 1 then
            if vertical then
                local a = (_growDir == "UP") and "BOTTOM" or "TOP"
                btn:SetPoint(a, TotemFrame, a, 0, 0)
            else
                local a = (_growDir == "LEFT") and "RIGHT" or "LEFT"
                btn:SetPoint(a, TotemFrame, a, 0, 0)
            end
        elseif vertical then
            if _growDir == "UP" then
                btn:SetPoint("BOTTOM", buttons[i - 1], "TOP", 0, scaledSpacing)
            else
                btn:SetPoint("TOP", buttons[i - 1], "BOTTOM", 0, -scaledSpacing)
            end
        elseif _growDir == "LEFT" then
            btn:SetPoint("RIGHT", buttons[i - 1], "LEFT", -scaledSpacing, 0)
        else
            btn:SetPoint("LEFT", buttons[i - 1], "RIGHT", scaledSpacing, 0)
        end

        -- Hide Blizzard's circular border
        if btn.Border then btn.Border:Hide() end

        -- Make Icon frame fill the entire button
        if btn.Icon then
            btn.Icon:ClearAllPoints()
            btn.Icon:SetAllPoints(btn)
        end

        -- Square the icon: remove circular mask
        if btn.Icon and btn.Icon.Texture and btn.Icon.TextureMask then
            btn.Icon.Texture:RemoveMaskTexture(btn.Icon.TextureMask)
            btn.Icon.TextureMask:Hide()
        end
        -- Square the cooldown swipe to match the squared icon: drop the
        -- circular mask, reset to the default (square) swipe texture, and use
        -- a non-circular edge so the radial sweep fills the corners. Removing
        -- the mask alone is not enough; the swipe texture must be reset too or
        -- it stays cropped to the old circular shape.
        if btn.Icon and btn.Icon.Cooldown then
            local cd = btn.Icon.Cooldown
            if btn.Icon.TextureMask then
                pcall(cd.RemoveMaskTexture, cd, btn.Icon.TextureMask)
            end
            if cd.SetSwipeTexture then pcall(cd.SetSwipeTexture, cd, "") end
            if cd.SetUseCircularEdge then pcall(cd.SetUseCircularEdge, cd, false) end
            -- Resetting the swipe texture above drops whatever darkness the old
            -- circular swipe had, so pin it explicitly for a defined, consistent
            -- look (matches the standard cooldown swipe darkness used elsewhere).
            if cd.SetSwipeColor then pcall(cd.SetSwipeColor, cd, 0, 0, 0, 0.8) end
        end

        -- Apply icon zoom crop
        if btn.Icon and btn.Icon.Texture then
            btn.Icon.Texture:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
        end

        -- Timer: show the icon cooldown's native countdown number instead of
        -- Blizzard's "Xs" Duration string. The number is C-rendered from the
        -- cooldown (secret-safe, no "s" suffix); we restyle only its FontString
        -- region, so nothing reads the protected duration value.
        if btn.Duration then
            btn.Duration:SetTextColor(0, 0, 0, 0)  -- hide the "Xs" text
        end
        local cd = btn.Icon and btn.Icon.Cooldown
        if cd and cd.SetHideCountdownNumbers then
            cd:SetHideCountdownNumbers(not tb.showTimer)
            if tb.showTimer then
                local cdText = GetCooldownNumberFS(cd)
                if cdText then
                    cdText:SetFont(fontPath, scaledTimerSize, outlineMode)
                    cdText:SetTextColor(1, 1, 1, 1)
                end
            end
        end

        -- Border overlay (our own frame in the button's scale space)
        local overlay = _totemBorderOverlays[btn]
        if not overlay then
            overlay = CreateFrame("Frame", nil, btn)
            _totemBorderOverlays[btn] = overlay
        end
        -- "Show Behind": +3 in front of the icon, level-1 behind it.
        overlay:SetFrameLevel(tb.borderBehind and math.max(0, btn:GetFrameLevel() - 1) or (btn:GetFrameLevel() + 3))
        overlay:ClearAllPoints()
        overlay:SetAllPoints(btn.Icon or btn)
        overlay:Show()
        local bs = tb.borderSize or 0
        local texKey = tb.borderTexture or "solid"
        EllesmereUI.ApplyBorderStyle(overlay, bs,
            tb.borderR or 0, tb.borderG or 0, tb.borderB or 0, tb.borderA or 1,
            texKey, tb.borderTextureOffset, tb.borderTextureOffsetY,
            tb.borderTextureShiftX, tb.borderTextureShiftY, "resourcebars", bs,
            nil, EllesmereUI.BorderPx(tb.borderSizePx, bs, texKey))
    end

    -- Hide overlays for buttons no longer active (O(n) via set lookup)
    for btn, overlay in pairs(_totemBorderOverlays) do
        if not _totemActiveSet[btn] then overlay:Hide() end
    end

    local maxButtons = 5
    local maxDim = iconSize * maxButtons + spacing * (maxButtons - 1)
    if vertical then
        totemBarFrame:SetSize(iconSize, maxDim)
    else
        totemBarFrame:SetSize(maxDim, iconSize)
    end
end

-- Expose so unlock-mode's grow-direction menu can re-run the layout after
-- changing totemBar.growDirection (LayoutTotemBar is file-local).
EllesmereUI.LayoutTotemBar = LayoutTotemBar

local function BuildTotemBar()
    local tb = GetTotemSettings()
    if not tb then return end

    -- enabledClasses nil = disabled; table with class keys = enabled for those classes
    local ec = tb.enabledClasses
    local _, classFile = UnitClass("player")
    local active = ec and classFile and ec[classFile]

    if not active then
        if totemBarFrame then
            EllesmereUI.SetElementVisibility(totemBarFrame, false)
        end
        -- Restore TotemFrame to original parent and strata
        if TotemFrame and _totemOrigParent and not InCombatLockdown() then
            TotemFrame:SetParent(_totemOrigParent)
            TotemFrame:ClearAllPoints()
            TotemFrame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 155)
            if _totemOrigStrata then
                TotemFrame:SetFrameStrata(_totemOrigStrata)
            end
        end
        return
    end

    if not totemBarFrame then
        SetTotemBarFrame(CreateFrame("Frame", "ERB_TotemBarFrame", UIParent))
        local tb = ERB.db and ERB.db.profile and ERB.db.profile.totemBar
        totemBarFrame:SetFrameStrata(tb and tb.frameStrata or "MEDIUM")
        totemBarFrame:SetFrameLevel(15)
        totemBarFrame:SetSize(120, 30)
        -- Re-register unlock elements so unlock mode picks up the new frame
        if _G._ERB_RegisterUnlock then _G._ERB_RegisterUnlock() end
    end

    -- Save original parent/strata for restore on disable
    if TotemFrame and not _totemOrigParent then
        _totemOrigParent = TotemFrame:GetParent()
        _totemOrigStrata = TotemFrame:GetFrameStrata()
    end

    -- Position our container
    if EllesmereUI._TryOverrideAnchor and EllesmereUI._TryOverrideAnchor("ERB_TotemBar", totemBarFrame) then
        -- Override anchor owns position (container already sized above)
    elseif tb.unlockPos and tb.unlockPos.point then
        if not EllesmereUI._unlockActive then
            -- When the unlock anchor system owns this frame's position (totem
            -- anchored to another element), let it own it -- do NOT slam the frame
            -- back to the stored absolute unlockPos (mirrors cast/GCD bar). Without
            -- this guard every ApplyAll fights the anchor, so the unlock mover
            -- snapshots the stale absolute spot and only corrects after a manual
            -- nudge -- most visible right after a profile import, where the
            -- imported absolute pos and anchor resolve to different positions.
            local anchored = EllesmereUI.IsUnlockAnchored("ERB_TotemBar")
            if not (anchored and totemBarFrame:GetLeft()) then
                local PP = EllesmereUI and EllesmereUI.PP
                local px, py = tb.unlockPos.x or 0, tb.unlockPos.y or 0
                if PP and PP.SnapForES then
                    local es = totemBarFrame:GetEffectiveScale()
                    px = PP.SnapForES(px, es)
                    py = PP.SnapForES(py, es)
                end
                totemBarFrame:ClearAllPoints()
                totemBarFrame:SetPoint(tb.unlockPos.point, UIParent,
                    tb.unlockPos.relPoint or tb.unlockPos.point, px, py)
            end
        end
    else
        if not EllesmereUI._unlockActive then
            totemBarFrame:ClearAllPoints()
            -- Default: left-aligned 5px below the player unit frame
            local playerUF = _G["oUF_EllesmerePlayer"]
            if playerUF and playerUF:IsShown() then
                totemBarFrame:SetPoint("TOPLEFT", playerUF, "BOTTOMLEFT", 0, -5)
            else
                totemBarFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -120)
            end
        end
    end

    EllesmereUI.SetElementVisibility(totemBarFrame, true)

    -- Invalidate layout cache so next LayoutTotemBar re-applies scale
    _totemLayoutCache.iconScale = nil
    _totemLayoutCache.spacing = nil

    -- Hook Blizzard updates (once)
    if not _totemHooked and TotemFrame then
        _totemHooked = true
        local function OnTotemUpdate()
            local s = GetTotemSettings()
            if s and s.enabledClasses then LayoutTotemBar() end
        end
        hooksecurefunc(TotemFrame, "Update", OnTotemUpdate)
        TotemFrame:HookScript("OnShow", OnTotemUpdate)
        if TotemButtonMixin then
            hooksecurefunc(TotemButtonMixin, "OnLoad", function()
                C_Timer.After(0, OnTotemUpdate)
            end)
        end
    end

    LayoutTotemBar()
end

I.BuildTotemBar = BuildTotemBar
I.broken = false
