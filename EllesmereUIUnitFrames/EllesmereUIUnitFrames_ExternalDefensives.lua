-------------------------------------------------------------------------------
--  EllesmereUIUnitFrames_ExternalDefensives.lua
--  Standalone EUI frame showing the external defensive buffs currently on
--  the player (Pain Suppression, Ironbark, ...), matched by the engine's
--  native EXTERNAL_DEFENSIVE aura filter. Cheap by construction: the C side
--  filters the enumeration (almost always zero matches), the event is
--  player-only UNIT_AURA, countdowns render through the engine's Cooldown
--  widget (no ticker, no OnUpdate), and nothing -- frames, font object,
--  event registration -- exists until first enabled.
--
--  Extracted verbatim (logic unchanged) from EllesmereUIUnitFrames_
--  PlayerAuras.lua, which reskinned Blizzard's BuffFrame/DebuffFrame and has
--  since been retired (superseded by PlayerAuraBars) and is no longer
--  loaded. This was the one sub-feature in that file NOT tied to BuffFrame/
--  DebuffFrame -- its own frame, own db.profile.externalDefensives
--  namespace -- so it gets its own file instead of being deleted, pending
--  evaluation of migrating it into PlayerAuraBars' "External Defensive"
--  class filter later.
-------------------------------------------------------------------------------
local addon, ns = ...

local ICON_ZOOM = 0.055  -- fallback crop (same as totem bar); user values in profile

local function FormatCompactDuration(timeLeft, style)
    if timeLeft >= 86400 then
        return string.format("%dd", math.floor(timeLeft / 86400 + 0.5))
    end
    if style == "colon" then
        if timeLeft >= 3600 then
            return string.format("%d:%02d",
                math.floor(timeLeft / 3600),
                math.floor((timeLeft % 3600) / 60))
        end
        if timeLeft >= 60 then
            return string.format("%d:%02d", math.floor(timeLeft / 60), math.floor(timeLeft % 60))
        end
        return string.format("%d", math.floor(timeLeft + 0.5))
    end
    if timeLeft >= 3600 then
        return string.format("%dh", math.floor(timeLeft / 3600 + 0.5))
    end
    if style == "seconds" then
        return string.format("%d", math.floor(timeLeft + 0.5))
    end
    if timeLeft >= 60 then
        return string.format("%dm", math.floor(timeLeft / 60 + 0.5))
    end
    return string.format("%d", math.floor(timeLeft + 0.5))
end

local function ED()
    local db = ns.db
    return db and db.profile and db.profile.externalDefensives
end

local EDF_FILTER  = "HELPFUL|EXTERNAL_DEFENSIVE"
local EDF_SPACING = 4
local C_UA = C_UnitAuras
local EDF_GetAuraDuration = C_UA and C_UA.GetAuraDuration
local EDF_GetAppCount     = C_UA and C_UA.GetAuraApplicationDisplayCount
-- Classification tokens are NOT slot-fetch filters on 12.0 -- membership is
-- tested per aura instance, exactly like ns.EUIAuraFilter does for the unit
-- frame elements (fetch broad HELPFUL, then IsAuraFilteredOutByInstanceID).
local EDF_IsFilteredOut   = C_UA and C_UA.IsAuraFilteredOutByInstanceID

local edfRoot
local edfButtons = {}
local edfEvt
local edfFont
local edfIDs   = {}  -- ordered shown auraInstanceIDs
local edfIcons = {}  -- [auraInstanceID] = icon fileID

local function EDF_StyleButton(btn, cfg)
    local size = cfg.iconSize or 32
    btn:SetSize(size, size)
    btn:ClearAllPoints()
    -- Growth direction: the first icon pins to one edge of the frame and
    -- later icons extend toward the other.
    if (cfg.growDirection or "right") == "left" then
        btn:SetPoint("RIGHT", edfRoot, "RIGHT", -((btn._index - 1) * (size + EDF_SPACING)), 0)
    else
        btn:SetPoint("LEFT", edfRoot, "LEFT", (btn._index - 1) * (size + EDF_SPACING), 0)
    end

    local z = cfg.iconZoom or ICON_ZOOM
    btn._icon:SetTexCoord(z, 1 - z, z, 1 - z)

    local cd = btn._cd
    if cd.SetHideCountdownNumbers then
        cd:SetHideCountdownNumbers(cfg.showText == false)
    end
    -- SetCountdownFont takes the NAME of a named font object, not the object.
    if edfFont and cd.SetCountdownFont then cd:SetCountdownFont("EUI_EDF_CountdownFont") end
    -- Custom duration formats via the engine formatter (nil-guarded: on
    -- clients without it the dropdown falls back to the native format).
    if cd.SetCountdownFormatter then
        local style = cfg.durationFormat
        if style and style ~= "blizzard" then
            cd:SetCountdownFormatter(function(timeLeft)
                if type(timeLeft) ~= "number" then return end
                if issecretvalue and issecretvalue(timeLeft) then return end
                if timeLeft <= 0 then return end
                return FormatCompactDuration(timeLeft, style)
            end)
        else
            cd:SetCountdownFormatter(nil)
        end
    end

    if btn._count then
        local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("unitFrames") or STANDARD_TEXT_FONT
        EllesmereUI.ApplyIconTextFont(btn._count, fontPath, cfg.textSize or 11, "unitFrames")
    end

    local bs = cfg.borderSize or 1
    local host = btn._borderHost
    host:SetFrameLevel(cfg.borderBehind and math.max(0, btn:GetFrameLevel() - 1) or (btn:GetFrameLevel() + 2))
    EllesmereUI.ApplyBorderStyle(host, bs,
        cfg.borderR or 0, cfg.borderG or 0, cfg.borderB or 0, cfg.borderA or 1,
        cfg.borderTexture or "solid",
        cfg.borderTextureOffset, cfg.borderTextureOffsetY,
        cfg.borderTextureShiftX, cfg.borderTextureShiftY,
        "unitframes", bs)
end

local function EDF_CreateButton(i)
    local btn = CreateFrame("Frame", nil, edfRoot)
    btn._index = i
    btn:EnableMouse(false)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    btn._icon = icon

    local cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetReverse(true)
    if cd.SetDrawEdge then cd:SetDrawEdge(false) end
    btn._cd = cd

    local borderHost = CreateFrame("Frame", nil, btn)
    borderHost:SetAllPoints(btn)
    borderHost:EnableMouse(false)
    btn._borderHost = borderHost

    -- Count + border live on a host above the cooldown, so the permanent-aura
    -- alpha mask on the cd (see EDF_Update) never takes them down with it.
    local txtHost = CreateFrame("Frame", nil, btn)
    txtHost:SetAllPoints()
    txtHost:SetFrameLevel(cd:GetFrameLevel() + 1)
    local cnt = txtHost:CreateFontString(nil, "OVERLAY")
    cnt:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    btn._count = cnt

    edfButtons[i] = btn
    local cfg = ED()
    if cfg then EDF_StyleButton(btn, cfg) end
    return btn
end

local function EDF_IsExternal(iid)
    return iid and EDF_IsFilteredOut
        and not EDF_IsFilteredOut("player", iid, EDF_FILTER)
end

-- Arm one button's engine-rendered pieces (duration swipe/countdown + count).
local function EDF_ArmButton(btn, iid)
    local cd = btn._cd
    if cd and EDF_GetAuraDuration then
        local durObj = EDF_GetAuraDuration("player", iid)
        if durObj and cd.SetCooldownFromDurationObject then
            cd:SetCooldownFromDurationObject(durObj)
            -- Permanent/no-duration auras return a degenerate (0,0) duration
            -- whose armed cooldown strobes; mask with alpha, never branch on
            -- the (possibly secret) IsZero.
            if durObj.IsZero and cd.SetAlphaFromBoolean then
                cd:SetAlphaFromBoolean(durObj:IsZero(), 0, 1)
            elseif cd.SetAlpha then
                cd:SetAlpha(1)
            end
        else
            cd:Clear()
        end
    end
    if btn._count then
        if EDF_GetAppCount then
            btn._count:SetText(EDF_GetAppCount("player", iid, 2, 1000) or "")
        else
            btn._count:SetText("")
        end
    end
end

local function EDF_Display()
    local n = #edfIDs
    for i = 1, n do
        local iid = edfIDs[i]
        local btn = edfButtons[i] or EDF_CreateButton(i)
        btn._icon:SetTexture(edfIcons[iid])
        EDF_ArmButton(btn, iid)
        btn:Show()
    end
    for i = n + 1, #edfButtons do edfButtons[i]:Hide() end
end

local function EDF_FullScan()
    wipe(edfIDs); wipe(edfIcons)
    if C_UA and C_UA.GetAuraSlots and C_UA.GetAuraDataBySlot then
        local slots = { C_UA.GetAuraSlots("player", "HELPFUL") }
        for i = 2, #slots do
            local aura = C_UA.GetAuraDataBySlot("player", slots[i])
            local iid = aura and aura.auraInstanceID
            if iid and EDF_IsExternal(iid) then
                edfIDs[#edfIDs + 1] = iid
                edfIcons[iid] = aura.icon
            end
        end
    end
end

-- Incremental UNIT_AURA processing: steady-state cost is proportional to the
-- CHANGE (usually one added/removed aura tested with one C call), never to
-- the player's full buff list. Full rescans only on login/full updates.
local function EDF_Update(_, _, _, updateInfo)
    local cfg = ED()
    if not (cfg and cfg.enabled and edfRoot) then return end

    if not updateInfo or updateInfo.isFullUpdate then
        EDF_FullScan()
        EDF_Display()
        return
    end

    local changed = false
    if updateInfo.addedAuras then
        for _, aura in ipairs(updateInfo.addedAuras) do
            local iid = aura.auraInstanceID
            if aura.isHelpful and iid and not edfIcons[iid] and EDF_IsExternal(iid) then
                edfIDs[#edfIDs + 1] = iid
                edfIcons[iid] = aura.icon
                changed = true
            end
        end
    end
    if updateInfo.removedAuraInstanceIDs then
        for _, iid in ipairs(updateInfo.removedAuraInstanceIDs) do
            if edfIcons[iid] then
                edfIcons[iid] = nil
                for i = #edfIDs, 1, -1 do
                    if edfIDs[i] == iid then table.remove(edfIDs, i); break end
                end
                changed = true
            end
        end
    end
    if changed then
        EDF_Display()
    elseif updateInfo.updatedAuraInstanceIDs then
        -- Refresh duration/stacks in place for tracked auras only.
        for _, iid in ipairs(updateInfo.updatedAuraInstanceIDs) do
            if edfIcons[iid] then
                for i = 1, #edfIDs do
                    if edfIDs[i] == iid then
                        local btn = edfButtons[i]
                        if btn then EDF_ArmButton(btn, iid) end
                        break
                    end
                end
            end
        end
    end
end

local function EDF_ApplyStyle()
    local cfg = ED()
    if not (cfg and edfRoot) then return end
    if edfFont then
        local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("unitFrames") or STANDARD_TEXT_FONT
        -- Icon-text convention: forced "OUTLINE, SLUG" like every other unit
        -- frame icon text, with the global "Outline Icon Text" setting able
        -- to route this to the user's font + font outline instead.
        EllesmereUI.ApplyIconTextFont(edfFont, fontPath, cfg.textSize or 11, "unitFrames")
    end
    local size = cfg.iconSize or 32
    edfRoot:SetSize(4 * size + 3 * EDF_SPACING, size)
    for _, btn in ipairs(edfButtons) do EDF_StyleButton(btn, cfg) end
end

local function EDF_ApplyPosition()
    if not edfRoot then return end
    local cfg = ED()
    local pos = cfg and cfg.unlockPos
    edfRoot:ClearAllPoints()
    if pos and pos.point then
        edfRoot:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        edfRoot:SetPoint("CENTER", UIParent, "CENTER", 0, -220)
    end
end

local function EDF_RegisterUnlock()
    if not (EllesmereUI.RegisterUnlockElements and EllesmereUI.MakeUnlockElement) then return end
    local MK = EllesmereUI.MakeUnlockElement
    EllesmereUI:RegisterUnlockElements({
        MK({
            key      = "EUF_ExternalDefensives",
            label    = "External Defensives",
            group    = "Unit Frames",
            order    = 450,
            noResize = true,
            getFrame = function() return edfRoot end,
            getSize  = function()
                local cfg = ED()
                local size = (cfg and cfg.iconSize) or 32
                return 4 * size + 3 * EDF_SPACING, size
            end,
            isHidden = function()
                local cfg = ED()
                return not (cfg and cfg.enabled)
            end,
            savePos = function(_, point, relPoint, x, y)
                if not point then return end
                local cfg = ED(); if not cfg then return end
                cfg.unlockPos = { point = point, relPoint = relPoint or point, x = x, y = y }
                if not EllesmereUI._unlockActive then EDF_ApplyPosition() end
            end,
            loadPos = function()
                local cfg = ED()
                local pos = cfg and cfg.unlockPos
                if not pos then return nil end
                return { point = pos.point, relPoint = pos.relPoint or pos.point, x = pos.x, y = pos.y }
            end,
            clearPos = function()
                local cfg = ED()
                if cfg then cfg.unlockPos = nil end
                EDF_ApplyPosition()
            end,
            applyPos = EDF_ApplyPosition,
        }),
    }, "EllesmereUIUnitFrames")
end

-- Live enable/disable + full restyle. Zero footprint while never enabled:
-- no frames, no font object, no event registration.
local function EDF_Setup()
    local cfg = ED()
    local enabled = cfg and cfg.enabled
    if enabled and not edfRoot then
        edfRoot = CreateFrame("Frame", "EUF_ExternalDefensives", UIParent)
        edfRoot:EnableMouse(false)
        edfFont = CreateFont("EUI_EDF_CountdownFont")
        edfEvt = CreateFrame("Frame")
        edfEvt:SetScript("OnEvent", EDF_Update)
        EDF_RegisterUnlock()
    end
    if not edfRoot then return end
    if enabled then
        edfEvt:RegisterUnitEvent("UNIT_AURA", "player")
        EDF_ApplyPosition()
        EDF_ApplyStyle()
        edfRoot:Show()
        EDF_Update()
    else
        edfEvt:UnregisterEvent("UNIT_AURA")
        edfRoot:Hide()
    end
end
ns.RefreshExternalDefensives = EDF_Setup

local edfInit = CreateFrame("Frame")
edfInit:RegisterEvent("PLAYER_LOGIN")
edfInit:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    -- Same UF-db-init delay the old reskin module used.
    C_Timer.After(1, EDF_Setup)
end)
