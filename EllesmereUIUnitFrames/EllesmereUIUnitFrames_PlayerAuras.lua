-------------------------------------------------------------------------------
--  EllesmereUIUnitFrames_PlayerAuras.lua
--  Simple reskin of Blizzard's standalone BuffFrame / DebuffFrame icons.
--  No reparenting, no repositioning -- Blizzard controls layout via Edit Mode.
-------------------------------------------------------------------------------
local addon, ns = ...

local GetFFD = EllesmereUI._GetFFD

local ICON_ZOOM = 0.055  -- fallback crop (same as totem bar); user values in profile
local BLIZZARD_AURA_ICON_SIZE = 30 -- visible icon inside the native 32px aura button

-------------------------------------------------------------------------------
--  Settings helper
-------------------------------------------------------------------------------
local function PA()
    local db = ns.db
    return db and db.profile and db.profile.playerAuras
end

-------------------------------------------------------------------------------
--  Skin generation
--
--  Blizzard fires AuraContainer:UpdateGridLayout continuously while buff timers
--  tick, and every fire used to re-skin every visible button from scratch: the
--  full border chain (ApplySecretSafeBorderStyle -> ApplyBorderStyle ->
--  PP.UpdateBorder -> SnapBorderTextures) plus a font resolve and SetFont per
--  button, every frame, even standing still doing nothing. SkinAuraButton
--  already set an ffd._paSkinned flag for exactly this -- but nothing ever read
--  it, so it never short-circuited anything. Profiling attributed the cost to
--  the PARENT addon, because that is where the border and font code lives.
--
--  A button stamped with the current generation is already styled correctly and
--  is skipped. The settings that feed the skin are compared ONCE per refresh
--  rather than per button, so a change from any source -- options, a profile
--  switch, a font change -- bumps the generation and re-skins everything,
--  without paying for the comparison on every button.
-------------------------------------------------------------------------------
local skinGen = 1
local lastCfg = {}

local function NoteConfig(cfg)
    local font    = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("unitFrames")) or ""
    local outline = (EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag("unitFrames")) or ""
    if  lastCfg.borderSize      == cfg.borderSize
    and lastCfg.borderBehind    == cfg.borderBehind
    and lastCfg.noBorderDebuffs == cfg.noBorderDebuffs
    and lastCfg.showText        == cfg.showText
    and lastCfg.textSize        == cfg.textSize
    and lastCfg.borderR         == cfg.borderR
    and lastCfg.borderG         == cfg.borderG
    and lastCfg.borderB         == cfg.borderB
    and lastCfg.borderA         == cfg.borderA
    and lastCfg.borderTexture   == cfg.borderTexture
    and lastCfg.offX            == cfg.borderTextureOffset
    and lastCfg.offY            == cfg.borderTextureOffsetY
    and lastCfg.shiftX          == cfg.borderTextureShiftX
    and lastCfg.shiftY          == cfg.borderTextureShiftY
    and lastCfg.buffZoom        == cfg.buffIconZoom
    and lastCfg.debuffZoom      == cfg.debuffIconZoom
    and lastCfg.font            == font
    and lastCfg.outline         == outline then
        return
    end
    lastCfg.borderSize, lastCfg.borderBehind    = cfg.borderSize, cfg.borderBehind
    lastCfg.noBorderDebuffs, lastCfg.showText   = cfg.noBorderDebuffs, cfg.showText
    lastCfg.textSize, lastCfg.borderTexture     = cfg.textSize, cfg.borderTexture
    lastCfg.borderR, lastCfg.borderG            = cfg.borderR, cfg.borderG
    lastCfg.borderB, lastCfg.borderA            = cfg.borderB, cfg.borderA
    lastCfg.offX, lastCfg.offY                  = cfg.borderTextureOffset, cfg.borderTextureOffsetY
    lastCfg.shiftX, lastCfg.shiftY              = cfg.borderTextureShiftX, cfg.borderTextureShiftY
    lastCfg.buffZoom, lastCfg.debuffZoom        = cfg.buffIconZoom, cfg.debuffIconZoom
    lastCfg.font, lastCfg.outline               = font, outline
    skinGen = skinGen + 1
end

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

-------------------------------------------------------------------------------
--  Per-button skinning
-------------------------------------------------------------------------------
local function SkinAuraButton(btn, isDebuff)
    local cfg = PA()
    if not cfg then return end
    -- Skip layout anchors
    if btn.isAuraAnchor then return end

    local ffd = GetFFD(btn)
    if not ffd then return end

    -- Already styled at the current settings: nothing below would change a
    -- pixel. This is the read that _paSkinned was always missing.
    if ffd._paSkinned == skinGen and ffd._paSkinDebuff == isDebuff then return end

    -- Icon zoom crop (btn.Icon is a Frame in Midnight; find the Texture inside)
    local iconFrame = btn.Icon
    local iconTex
    if iconFrame then
        -- Try known child names first
        iconTex = iconFrame.Texture or iconFrame.texture
        -- Fallback: scan for the first Texture region
        if not iconTex and iconFrame.GetRegions then
            for i = 1, iconFrame:GetNumRegions() do
                local r = select(i, iconFrame:GetRegions())
                if r and r:IsObjectType("Texture") and r.SetTexCoord then
                    iconTex = r
                    break
                end
            end
        end
        -- iconFrame itself might be a Texture (pre-Midnight)
        if not iconTex and iconFrame.SetTexCoord then
            iconTex = iconFrame
        end
    end
    if iconTex and iconTex.SetTexCoord then
        local z
        if isDebuff then z = cfg.debuffIconZoom else z = cfg.buffIconZoom end
        z = z or ICON_ZOOM
        iconTex:SetTexCoord(z, 1 - z, z, 1 - z)
    end

    -- Hide Blizzard border (alpha, not Hide, to avoid taint)
    -- Keep it visible on debuffs when noBorderDebuffs is enabled (colored border)
    if btn.DebuffBorder then
        if isDebuff and cfg.noBorderDebuffs then
            btn.DebuffBorder:SetAlpha(1)
        else
            btn.DebuffBorder:SetAlpha(0)
        end
    end

    -- Duration text styling (btn.Duration may be a Frame containing a FontString)
    local durFS = btn.Duration
    if durFS and not durFS.SetFont and durFS.GetRegions then
        -- Duration is a Frame; find the FontString inside
        for i = 1, durFS:GetNumRegions() do
            local r = select(i, durFS:GetRegions())
            if r and r.SetFont then durFS = r; break end
        end
    end
    if durFS and durFS.SetFont and not ffd._paDurHooked
        and type(btn.UpdateDuration) == "function" then
        ffd._paDurHooked = true
        local fs = durFS
        hooksecurefunc(btn, "UpdateDuration", function(_, timeLeft)
            local pa = PA()
            local style = pa and pa.durationFormat
            if not style or style == "blizzard" then return end
            if type(timeLeft) ~= "number" then return end
            if issecretvalue and issecretvalue(timeLeft) then return end
            if timeLeft <= 0 then return end
            fs:SetText(FormatCompactDuration(timeLeft, style))
        end)
    end

    if durFS and durFS.SetFont then
        if cfg.showText then
            local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("unitFrames") or STANDARD_TEXT_FONT
            local outline = EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag("unitFrames") or "OUTLINE, SLUG"
            if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(durFS, outline == "") end
            durFS:SetFont(fontPath, cfg.textSize or 11, outline)
            durFS:SetTextColor(1, 1, 1, 1)
        else
            durFS:SetTextColor(0, 0, 0, 0)
        end
    end

    -- Count text styling
    local countFS = btn.Count
    if countFS and not countFS.SetFont and countFS.GetRegions then
        for i = 1, countFS:GetNumRegions() do
            local r = select(i, countFS:GetRegions())
            if r and r.SetFont then countFS = r; break end
        end
    end
    if countFS and countFS.SetFont then
        local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("unitFrames") or STANDARD_TEXT_FONT
        -- Stack count always uses a forced OUTLINE, SLUG flag (keeps the digits
        -- crisp regardless of the user's global font-outline setting).
        EllesmereUI.ApplyIconTextFont(countFS, fontPath, cfg.textSize or 11, "unitFrames")
    end

    -- The shared border-style engine requires a frame we own. Keep that frame
    -- anchored to the icon instead of applying a backdrop to Blizzard's button.
    local anchorFrame = iconFrame or btn
    local bs = cfg.borderSize or 1
    local skipBorder = isDebuff and cfg.noBorderDebuffs
    local border = ffd._paBorder
    if not border then
        border = CreateFrame("Frame", nil, btn)
        border:EnableMouse(false)
        ffd._paBorder = border
    end
    border:SetFrameLevel(cfg.borderBehind and math.max(0, btn:GetFrameLevel() - 1) or (btn:GetFrameLevel() + 10))
    -- Never derive this frame's dimensions through SetAllPoints(anchorFrame):
    -- Blizzard aura dimensions are secret on Midnight, and BackdropTemplate's
    -- SetBackdrop then attempts arithmetic on that secret width. AuraContainer
    -- applies the user's icon size as scale over Blizzard's native 32px button.
    -- Its visible icon is 30px, so this public constant avoids both the secret
    -- geometry read and the one-pixel gap left by sizing to the whole button.
    border:ClearAllPoints()
    border:SetPoint("CENTER", anchorFrame, "CENTER", 0, 0)
    border:SetSize(BLIZZARD_AURA_ICON_SIZE, BLIZZARD_AURA_ICON_SIZE)
    EllesmereUI.ApplySecretSafeBorderStyle(border, ffd,
        (bs > 0 and not skipBorder) and bs or 0,
        cfg.borderR or 0, cfg.borderG or 0, cfg.borderB or 0, cfg.borderA or 1,
        cfg.borderTexture or "solid",
        cfg.borderTextureOffset, cfg.borderTextureOffsetY,
        cfg.borderTextureShiftX, cfg.borderTextureShiftY,
        "unitframes", bs)

    ffd._paSkinned = skinGen
    ffd._paSkinDebuff = isDebuff
end

-------------------------------------------------------------------------------
--  Iterate and skin all visible aura buttons on a frame
-------------------------------------------------------------------------------
local function SkinAllButtons(frame, isDebuff)
    if not frame or not frame.auraFrames then return end
    for _, btn in pairs(frame.auraFrames) do
        if btn and btn.Icon and not btn.isAuraAnchor then
            SkinAuraButton(btn, isDebuff)
        end
    end
end

-------------------------------------------------------------------------------
--  Full refresh (called on setting change or UNIT_AURA)
-------------------------------------------------------------------------------
local function RefreshAll()
    local cfg = PA()
    if not (cfg and cfg.enabled) then return end
    -- Once per refresh, not once per button.
    NoteConfig(cfg)
    SkinAllButtons(BuffFrame, false)
    SkinAllButtons(DebuffFrame, true)
end
ns.RefreshPlayerAuras = RefreshAll

-- UpdateGridLayout can fire several times within one frame; each fire used to
-- queue its own full refresh. Coalesced to one pass per tick. Named rather than
-- an inline closure so scheduling allocates nothing.
local refreshPending = false

local function DoPendingRefresh()
    refreshPending = false
    RefreshAll()
end

local function RequestRefresh()
    if refreshPending then return end
    refreshPending = true
    C_Timer.After(0, DoPendingRefresh)
end

-------------------------------------------------------------------------------
--  Scale helper (applies iconSize via SetScale on AuraContainer)
-------------------------------------------------------------------------------
local _appliedBuffScale, _appliedDebuffScale

local function ApplyExpandButtonSetting()
    local cfg = PA()
    local button = BuffFrame and BuffFrame.CollapseAndExpandButton
    if not (cfg and button) then return end
    local show = cfg.showExpandButton ~= false
    -- Purely visual: hide the expand/collapse button when the user opts to.
    -- We deliberately do NOT write BuffFrame.isExpanded or call BuffFrame:Update
    -- / UpdateGridLayout / RefreshConsolidationFrameVisibility from addon code.
    -- Driving Blizzard's aura machinery from addon context runs it under our
    -- taint, so Blizzard's own UpdateExpirationTime compares the secret
    -- expirationTime and errors on every aura update -- 2000+ errors and heavy
    -- lag in raid combat -- and that tainted Update also throws before our
    -- border re-skin hook runs, so the icon borders revert on reload. Auras keep
    -- Blizzard's native expand state (default is expanded, so all auras show);
    -- when hidden, the button also stays hidden via the deferred
    -- RefreshConsolidationFrameVisibility hook installed at init.
    if not show then
        button:Hide()
    end
end

local function ApplyScale()
    local cfg = PA()
    if not cfg or not cfg.enabled then return end
    local nativeSize = 32
    local scale = (cfg.iconSize or nativeSize) / nativeSize

    if BuffFrame and BuffFrame.AuraContainer then
        if _appliedBuffScale ~= scale then
            BuffFrame.AuraContainer:SetScale(scale)
            _appliedBuffScale = scale
        end
    end
    if DebuffFrame and DebuffFrame.AuraContainer then
        if _appliedDebuffScale ~= scale then
            DebuffFrame.AuraContainer:SetScale(scale)
            _appliedDebuffScale = scale
        end
    end
    ApplyExpandButtonSetting()
end
ns.ApplyPlayerAuraScale = ApplyScale


-------------------------------------------------------------------------------
--  External Defensives Frame -- standalone EUI frame showing the external
--  defensive buffs currently on the player (Pain Suppression, Ironbark, ...),
--  matched by the engine's native EXTERNAL_DEFENSIVE aura filter. Cheap by
--  construction: the C side filters the enumeration (almost always zero
--  matches), the event is player-only UNIT_AURA, countdowns render through
--  the engine's Cooldown widget (no ticker, no OnUpdate), and nothing --
--  frames, font object, event registration -- exists until first enabled.
-------------------------------------------------------------------------------
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

local function ED()
    local db = ns.db
    return db and db.profile and db.profile.externalDefensives
end

-- Countdown formatters for the EDF cooldown widgets. SetCountdownFormatter
-- takes an ENGINE formatter object (C_StringUtil.CreateNumericRuleFormatter),
-- never a Lua function -- passing a closure throws "bad argument #2", which
-- aborted EDF_StyleButton partway and left the button permanently unstyled and
-- its count FontString font-less. Engine-side formatting is also what makes
-- secret durations render at all, the same reason the Cooldown Manager's
-- threshold text uses this API.
--
-- Only the sub-hour range is styled per format; externals are all short, and
-- the hour/day breakpoints exist purely as a tail. Thresholds sit just above
-- each unit boundary so an UP-rounded value in (59, 60] routes into the next
-- breakpoint instead of reading "60" for a tick.
local EDF_formatters = {}
local EDF_fmtUnsupported = false

local function EDF_FormatterFor(style)
    if EDF_fmtUnsupported or not style or style == "blizzard" then return nil end
    local cached = EDF_formatters[style]
    if cached ~= nil then return cached or nil end
    if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter
        and Enum.NumericRuleFormatRounding) then
        EDF_fmtUnsupported = true
        return nil
    end
    local Up = Enum.NumericRuleFormatRounding.Up
    local points = { { threshold = 0, format = "%d", rounding = Up, step = 1 } }
    if style == "colon" then
        points[#points + 1] = {
            threshold = 59.0001, format = "%d:%02d", rounding = Up, step = 1,
            components = { { div = 60 }, { mod = 60 } },
        }
    elseif style ~= "seconds" then
        -- "compact": minutes above a minute. "seconds" deliberately has no
        -- minute breakpoint, so it keeps counting raw seconds ("152").
        points[#points + 1] = {
            threshold = 59.0001, format = "%dm", rounding = Up, step = 1,
            components = { { div = 60 } },
        }
    end
    points[#points + 1] = {
        threshold = 3599.0001, format = "%dh", rounding = Up, step = 1,
        components = { { div = 3600 } },
    }
    points[#points + 1] = {
        threshold = 86399.0001, format = "%dd", rounding = Up, step = 1,
        components = { { div = 86400 } },
    }
    local f = C_StringUtil.CreateNumericRuleFormatter()
    if not pcall(f.SetBreakpoints, f, points) then
        EDF_formatters[style] = false
        return nil
    end
    EDF_formatters[style] = f
    return f
end

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
        cd:SetCountdownFormatter(EDF_FormatterFor(cfg.durationFormat))
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
    -- Baseline font at creation: EDF_StyleButton re-points this at the user's
    -- configured font, but the button is already in edfButtons by then, so a
    -- styling pass that fails partway would otherwise leave a font-less
    -- FontString that throws "Font not set" on every later SetText.
    cnt:SetFont(EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("unitFrames")
        or STANDARD_TEXT_FONT, 11, "")
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
    -- Same UF-db-init delay the skin below uses.
    C_Timer.After(1, EDF_Setup)
end)

-------------------------------------------------------------------------------
--  Initialization
-------------------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")

        -- Delay to let UF db initialize
        C_Timer.After(1, function()
            local cfg = PA()
            if not cfg or not cfg.enabled then return end

            -- Apply scale
            ApplyScale()

            -- Initial skin pass
            RefreshAll()

            -- Hook aura updates to catch new/changed buttons
            if BuffFrame and BuffFrame.AuraContainer then
                hooksecurefunc(BuffFrame.AuraContainer, "UpdateGridLayout", function()
                    RequestRefresh()
                end)
                if BuffFrame.RefreshConsolidationFrameVisibility then
                    hooksecurefunc(BuffFrame, "RefreshConsolidationFrameVisibility", function()
                        -- Deferred: this can fire inside Blizzard's secure
                        -- buff-system refresh (incl. Edit Mode's passes);
                        -- hiding inline there taints the rest of that
                        -- execution.
                        C_Timer.After(0, function()
                            local cfgNow = PA()
                            if cfgNow and cfgNow.showExpandButton == false
                                and BuffFrame.CollapseAndExpandButton then
                                BuffFrame.CollapseAndExpandButton:Hide()
                            end
                        end)
                    end)
                end
            end
            if DebuffFrame and DebuffFrame.AuraContainer then
                hooksecurefunc(DebuffFrame.AuraContainer, "UpdateGridLayout", function()
                    RequestRefresh()
                end)
            end

        end)
    end
end)
