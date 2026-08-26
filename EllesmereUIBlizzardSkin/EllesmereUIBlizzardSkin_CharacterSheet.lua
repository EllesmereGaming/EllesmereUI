if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  Themed Character Sheet
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local L = _G.EllesmereUI and _G.EllesmereUI.L or function(k) return k end
local skinned = false
local issecretvalue = issecretvalue or function() return false end
local activeEquipmentSetID = nil

-- External weak-keyed lookup table for frame state (prevents tainting Blizzard frames)
local FFD = setmetatable({}, { __mode = "k" })
local function GetFFD(frame)
    local d = FFD[frame]
    if not d then d = {}; FFD[frame] = d end
    return d
end

-- Same reading as the Chat sidebar icon and the DataBars block: the LOWEST
-- percent across equipped slots 1-18 (the weakest item), floored.
local function GetDurabilityPercent()
    local lowest = 100
    for slotId = 1, 18 do
        local cur, mx = GetInventoryItemDurability(slotId)
        if cur and mx and mx > 0 then
            local pct = cur / mx * 100
            if pct < lowest then lowest = pct end
        end
    end
    return math.floor(lowest)
end

local function GetDurabilityTextColor(pct)
    if pct > 50 then
        return (100 - pct) / 50, 1, 0
    end
    return 1, pct / 50, 0
end

local function FormatDurabilityText(pct, showLabel)
    if showLabel then
        return L("Durability") .. ": " .. pct .. "%"
    end
    return pct .. "%"
end

-- "gear" = the 16 slots with ilvl/enchants/sockets.
-- "all"  = gear + shirt + tabard (cosmetic), for full-character loops.
local EUI_GEAR_SLOTS = {
    "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot", "CharacterBackSlot",
    "CharacterChestSlot", "CharacterWaistSlot",   "CharacterLegsSlot",     "CharacterFeetSlot",
    "CharacterWristSlot","CharacterHandsSlot",   "CharacterFinger0Slot",  "CharacterFinger1Slot",
    "CharacterTrinket0Slot","CharacterTrinket1Slot","CharacterMainHandSlot","CharacterSecondaryHandSlot",
}
local EUI_ALL_SLOTS = {
    "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot", "CharacterBackSlot",
    "CharacterChestSlot", "CharacterShirtSlot",  "CharacterTabardSlot",  "CharacterWristSlot",
    "CharacterHandsSlot","CharacterWaistSlot",   "CharacterLegsSlot",     "CharacterFeetSlot",
    "CharacterTrinket0Slot","CharacterTrinket1Slot","CharacterFinger0Slot","CharacterFinger1Slot",
    "CharacterMainHandSlot","CharacterSecondaryHandSlot",
}

-- Prefer EquipmentManager_EquipSet over raw C_EquipmentSet (cleaner from insecure code). Callers must combat-guard.
local function EUI_EquipSet(setID)
    if not setID then return end
    if EquipmentManager_EquipSet then
        EquipmentManager_EquipSet(setID)
    else
        C_EquipmentSet.UseEquipmentSet(setID)
    end
end

-- C_TooltipInfo scanning. NEVER create a scanning GameTooltipTemplate from Lua (CLAUDE.md reference_tooltip_template_taint).
local function EUI_ScanInventoryItem(slotID, unit)
    if not (C_TooltipInfo and C_TooltipInfo.GetInventoryItem) then return nil end
    local data = C_TooltipInfo.GetInventoryItem(unit or "player", slotID)
    if not data then return nil end
    if TooltipUtil and TooltipUtil.SurfaceArgs then
        TooltipUtil.SurfaceArgs(data)
    end
    return data
end

-- Upgrade track lookup lives in EllesmereUI.lua so Bags shares it; hot-path alias.
local EUI_GetUpgradeTrack = EllesmereUI.GetUpgradeTrack

-- Language-agnostic: line-type match (Enum.TooltipDataLineType.ItemEnchantmentPermanent / 15)
-- first, else a pattern from the localized ENCHANTED_TOOLTIP_LINE. Cached by enchantID per session.
local _enchantNameCache = {}
local _ENCHANT_LINE_TYPE = (Enum and Enum.TooltipDataLineType
    and (Enum.TooltipDataLineType.ItemEnchantmentPermanent
         or Enum.TooltipDataLineType.ItemEnchant))
    or 15

-- Pattern from ENCHANTED_TOOLTIP_LINE: escape magic chars, %s becomes the capture.
local _ENCHANT_PATTERN
do
    local fmt = ENCHANTED_TOOLTIP_LINE
    if fmt then
        local head, tail = fmt:match("^(.-)%%s(.*)$")
        if head then
            local function esc(s)
                return (s:gsub("([%(%)%.%[%]%^%$%*%+%-%?%%])", "%%%1"))
            end
            _ENCHANT_PATTERN = "^" .. esc(head) .. "(.+)" .. esc(tail) .. "$"
        end
    end
end

local function _stripLineEscapes(s)
    if not s then return "" end
    -- Keep |A:...|a atlas escapes (renderer shows the icon, hides the text); strip only colors + leading +/&.
    s = s:gsub("|cn.-:(.-)|r", "%1")         -- new-style color escapes
    s = s:gsub("|c%x%x%x%x%x%x%x%x", "")     -- classic color open
    s = s:gsub("|r", "")                     -- color close
    s = s:gsub("^%s*[%+&]%s*", "")           -- leading + or &
    return s
end

local function EUI_GetEnchantText(slotID, unit)
    if not slotID then return "" end
    local link = GetInventoryItemLink(unit or "player", slotID)
    if not link then return "" end

    -- Item link format: "item:<itemID>:<enchantID>:..."
    local enchantID = tonumber(link:match("item:%d+:(%d+)"))
    if not enchantID or enchantID == 0 then return "" end

    local cached = _enchantNameCache[enchantID]
    if cached ~= nil then return cached end

    local data = EUI_ScanInventoryItem(slotID, unit)
    if not (data and data.lines) then
        _enchantNameCache[enchantID] = ""
        return ""
    end

    for _, line in ipairs(data.lines) do
        local raw = _stripLineEscapes(line.leftText or "")
        local matched
        if line.type == _ENCHANT_LINE_TYPE then
            matched = raw
        elseif _ENCHANT_PATTERN then
            matched = raw:match(_ENCHANT_PATTERN)
        else
            matched = raw:match("^Enchanted:%s*(.+)$")
        end
        if matched and matched ~= "" then
            matched = matched:gsub("^Enchant%s+[^-]+%s*-%s*", "")
            _enchantNameCache[enchantID] = matched
            return matched
        end
    end

    _enchantNameCache[enchantID] = ""
    return ""
end

EllesmereUI.GetEnchantText  = EUI_GetEnchantText

-- Empty-socket atlas map (key names come from GetItemStats return keys).
local EUI_EMPTY_SOCKET_ATLAS = {
    EMPTY_SOCKET_META       = "socket-meta",
    EMPTY_SOCKET_RED        = "socket-red",
    EMPTY_SOCKET_YELLOW     = "socket-yellow",
    EMPTY_SOCKET_BLUE       = "socket-blue",
    EMPTY_SOCKET_HYDRAULIC  = "socket-hydraulic",
    EMPTY_SOCKET_COGWHEEL   = "socket-cogwheel",
    EMPTY_SOCKET_PRISMATIC  = "socket-prismatic",
    EMPTY_SOCKET_PUNCHCARDRED    = "socket-punchcardred",
    EMPTY_SOCKET_PUNCHCARDYELLOW = "socket-punchcardyellow",
    EMPTY_SOCKET_PUNCHCARDBLUE   = "socket-punchcardblue",
    EMPTY_SOCKET_DOMINATION = "socket-domination",
    EMPTY_SOCKET_CYPHER     = "socket-cypher",
    EMPTY_SOCKET_PRIMORDIAL = "socket-primordial",
    EMPTY_SOCKET_TINKER     = "socket-tinker",
}

-- Gem socket icons: one pass over GetItemStats + C_Item.GetItemGem (no tooltip). paintPasses
-- (the slot's euiGemPaintPasses) suppresses empty-socket atlas rows for the first frames after
-- /reload while gem bytes hydrate.
local function EUI_BuildSocketIconRow(itemLink, paintPasses)
    local row = {}
    local gemLinks = {}
    if not itemLink or not C_Item or not C_Item.GetItemGem or not C_Item.GetItemStats then
        return row, 0, 0, gemLinks
    end

    local stats = C_Item.GetItemStats(itemLink)
    local totalSockets = 0
    local firstAtlas
    if stats then
        for key, count in pairs(stats) do
            local atlas = EUI_EMPTY_SOCKET_ATLAS[key]
            if atlas and count and count > 0 then
                totalSockets = totalSockets + count
                firstAtlas = firstAtlas or atlas
            end
        end
    end

    for i = 1, 4 do
        local _, gemLink = C_Item.GetItemGem(itemLink, i)
        if gemLink then
            gemLinks[#gemLinks + 1] = gemLink
            local icon = C_Item.GetItemIconByID(gemLink)
            if not icon and GetItemInfoInstant then
                icon = select(5, GetItemInfoInstant(gemLink))
            end
            row[#row + 1] = { icon = icon or 134400, isAtlas = false }
        end
    end
    local nGems = #gemLinks

    -- EMPTY_SOCKET_* counts total sockets; subtract filled for empty atlas rows.
    local suppressEmptyAtlas = (totalSockets > 0 and nGems == 0
        and (paintPasses or 0) < 40)
    if stats and not suppressEmptyAtlas and firstAtlas then
        local emptyCount = math.max(0, totalSockets - nGems)
        if emptyCount > 0 then
            for _ = 1, emptyCount do
                row[#row + 1] = { icon = firstAtlas, isAtlas = true }
            end
        end
    end

    return row, totalSockets, nGems, gemLinks
end

-- Default the themed sheet + its sub-displays on first install. Keys are stamped
-- only when nil, so a user who explicitly turned something off keeps that choice.
do
    local defaultStamp = CreateFrame("Frame")
    defaultStamp:RegisterEvent("ADDON_LOADED")
    defaultStamp:SetScript("OnEvent", function(self, _, addon)
        if addon ~= "EllesmereUI" then return end
        self:UnregisterAllEvents()
        if not EllesmereUIDB then EllesmereUIDB = {} end
        local defaults = {
            themedCharacterSheet         = true,
            showMythicRating             = false,
            showItemLevel                = true,
            showUpgradeTrack             = true,
            showEnchants                 = true,
            showGems                     = true,
            showStatCategory_Attributes  = true,
            showStatCategory_Attack      = true,
            showStatCategory_Defense     = true,
            showStatCategory_SecondaryStats = true,
            showStatCategory_Tertiary    = true,
            showStatCategory_Crests      = true,
            showStatCategory_PvP         = true,
            showAdjustedStats            = false,
            showManaStat                 = false,
            showCharSheetDurability      = false,
            charSheetDurabilityLocation  = "model",
            charSheetDurabilityShowLabel = true,
        }
        for k, v in pairs(defaults) do
            if EllesmereUIDB[k] == nil then
                EllesmereUIDB[k] = v
            end
        end
    end)
end

-- Lightweight pre-skin: chrome hides, bg, inset. Safe while CharacterFrame is hidden (before first open); running it mid-OnShow blocks the Rep/Currency ScrollBox data render.
local _preSkinned = false
local function PreSkinCharacterSheet()
    if _preSkinned then return end
    _preSkinned = true

    local frame = CharacterFrame
    if not frame then _preSkinned = false; return end

    if CharacterFrame.NineSlice then CharacterFrame.NineSlice:Hide() end
    if frame.Background then frame.Background:Hide() end
    if frame.TitleBg then frame.TitleBg:Hide() end
    if frame.TopTileStreaks then frame.TopTileStreaks:Hide() end
    if frame.Portrait then frame.Portrait:Hide() end
    if CharacterFramePortrait then CharacterFramePortrait:Hide() end
    if CharacterModelFrameBackgroundOverlay then CharacterModelFrameBackgroundOverlay:Hide() end
    if CharacterModelFrameBackgroundTopLeft then CharacterModelFrameBackgroundTopLeft:Hide() end
    if CharacterModelFrameBackgroundBotLeft then CharacterModelFrameBackgroundBotLeft:Hide() end
    if CharacterModelFrameBackgroundTopRight then CharacterModelFrameBackgroundTopRight:Hide() end
    if CharacterModelFrameBackgroundBotRight then CharacterModelFrameBackgroundBotRight:Hide() end
    if CharacterFrameInsetRight then
        if CharacterFrameInsetRight.NineSlice then CharacterFrameInsetRight.NineSlice:Hide() end
        CharacterFrameInsetRight:ClearAllPoints()
        CharacterFrameInsetRight:SetPoint("TOPLEFT", frame, "TOPLEFT", 10000, -10000)
    end
    if CharacterFrameInsetBG then CharacterFrameInsetBG:Hide() end
    if CharacterFrameInset and CharacterFrameInset.NineSlice then
        for _, edge in ipairs({"TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner"}) do
            if CharacterFrameInset.NineSlice[edge] then
                CharacterFrameInset.NineSlice[edge]:Hide()
            end
        end
        CharacterFrameInset.NineSlice:SetAlpha(0)
    end
    local FRAME_BG_R, FRAME_BG_G, FRAME_BG_B = 0.03, 0.045, 0.05
    if CharacterFrameInset then
        if CharacterFrameInset.AbsBg then
            CharacterFrameInset.AbsBg:SetColorTexture(FRAME_BG_R, FRAME_BG_G, FRAME_BG_B, 1)
        end
        if CharacterFrameInset.Bg then
            CharacterFrameInset.Bg:SetColorTexture(0.02, 0.02, 0.025, 1)
            CharacterFrameInset.Bg:SetAlpha(0)
        end
    end
    if CharacterModelScene then
        CharacterModelScene:SetAlpha(0)
        CharacterModelScene:EnableMouse(false)
        if CharacterModelScene.EnableMouseWheel then
            CharacterModelScene:EnableMouseWheel(false)
        end
        if CharacterModelScene.ControlFrame then
            CharacterModelScene.ControlFrame:SetAlpha(0)
            CharacterModelScene.ControlFrame:EnableMouse(false)
        end
    end
    for i = 1, select("#", frame:GetRegions()) do
        local region = select(i, frame:GetRegions())
        if region and region:IsObjectType("Texture") then
            region:SetAlpha(0)
        end
    end
    -- Background covers the frame without distorting: native aspect 561x433, and
    -- on resize the tex coords are recomputed centered, cropping the overflow.
    local BG_ASPECT = 561 / 433
    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\modern_blizz.png")
    bg:SetAllPoints(frame)
    GetFFD(frame).bg = bg
    bg:SetAlpha(1)
    GetFFD(frame).bgOverlay = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    GetFFD(frame).bgOverlay:SetColorTexture(0, 0, 0, 0.62)
    GetFFD(frame).bgOverlay:SetAllPoints(frame)

    local BASE_L, BASE_R, BASE_T, BASE_B = 0.25, 1, 0, 0.75
    local BASE_U = BASE_R - BASE_L  -- 0.75
    local BASE_V = BASE_B - BASE_T  -- 0.75
    local function UpdateBgTexCoords()
        local fw, fh = frame:GetSize()
        if fw == 0 or fh == 0 then return end
        local frameAspect = fw / fh
        if frameAspect > BG_ASPECT then
            local visV = BASE_V * (BG_ASPECT / frameAspect)
            local trimV = (BASE_V - visV) / 2
            bg:SetTexCoord(BASE_L, BASE_R, BASE_T + trimV, BASE_B - trimV)
        else
            local visU = BASE_U * (frameAspect / BG_ASPECT)
            local trimU = (BASE_U - visU) / 2
            bg:SetTexCoord(BASE_L + trimU, BASE_R - trimU, BASE_T, BASE_B)
        end
    end
    hooksecurefunc(frame, "SetSize", UpdateBgTexCoords)
    hooksecurefunc(frame, "SetWidth", UpdateBgTexCoords)
    hooksecurefunc(frame, "SetHeight", UpdateBgTexCoords)
    UpdateBgTexCoords()
    -- Standard window-reskin border (AdventureMap_TopBorder atlas), as on every skinned window.
    if ns.WSkin and ns.WSkin.AtlasBorder then ns.WSkin.AtlasBorder(frame) end
    -- Lets the Modern flat backdrop live-swap in for the atlas when the user picks Modern here.
    if ns.WSkin and ns.WSkin.AdoptShell then
        ns.WSkin.AdoptShell("charsheet", frame, bg, GetFFD(frame).bgOverlay)
    end

    -- PlayerModel: SetUnit("player") natively follows shapeshift forms and Dracthyr Visage. Backdrop + hover glow live on a sibling frame (the 3D model draws on top).
    if not GetFFD(frame).modelScene then
        local myModel = CreateFrame("PlayerModel", "EUI_CharSheet_ModelScene", frame)
        myModel:SetFrameLevel(2)
        if CharacterHeadSlot then
            myModel:SetPoint("TOPLEFT",  CharacterHeadSlot,  "TOPRIGHT", 0, 0)
        end
        if CharacterHandsSlot then
            myModel:SetPoint("TOPRIGHT", CharacterHandsSlot, "TOPLEFT",  0, 0)
        end
        if CharacterMainHandSlot then
            myModel:SetPoint("BOTTOM",   CharacterMainHandSlot, "TOP",   0, 0)
        else
            myModel:SetPoint("BOTTOM",   frame, "BOTTOM", 0, 60)
        end
        myModel:EnableMouse(true)
        myModel:EnableMouseWheel(true)

        -- Custom model background (our frame, no taint risk)
        local bgFrame = CreateFrame("Frame", nil, frame)
        bgFrame:SetFrameLevel(math.max(1, myModel:GetFrameLevel() - 1))
        bgFrame:SetPoint("TOPLEFT", CharacterHeadSlot, "TOPLEFT", -8, 10)
        bgFrame:SetPoint("BOTTOMRIGHT", myModel, "BOTTOMRIGHT", 0, -18)
        local bgTex = bgFrame:CreateTexture(nil, "BACKGROUND")
        bgTex:SetAllPoints(bgFrame)
        bgTex:SetTexture("Interface\\AddOns\\EllesmereUIBlizzardSkin\\Media\\character-bg.png")
        bgTex:SetAlpha(1)

        GetFFD(frame).modelBg      = bgTex
        GetFFD(frame).modelBgFrame = bgFrame

        myModel:SetUnit("player")
        local zoomLevel = 0  -- 0 = full body, 1 = tight portrait
        myModel:SetPortraitZoom(zoomLevel)

        GetFFD(frame).modelScene = myModel  -- key name kept for older refs
        GetFFD(frame).modelActor = myModel

        -- LMB drag rotates, RMB drag pans, wheel zooms.
        local ROTATE_SPEED = 0.012
        local PAN_SPEED    = 0.01
        local ZOOM_STEP    = 0.1

        local mouseOverlay = CreateFrame("Frame", nil, myModel)
        mouseOverlay:SetAllPoints(myModel)
        mouseOverlay:SetFrameLevel(myModel:GetFrameLevel() + 5)
        mouseOverlay:EnableMouse(true)
        mouseOverlay:EnableMouseWheel(true)
        mouseOverlay:RegisterForDrag("LeftButton", "RightButton")

        local dragMode
        local lastX, lastY

        local function _dragOnUpdate(self)
            if not dragMode then
                self:SetScript("OnUpdate", nil)
                return
            end
            if dragMode == "rotate" and not IsMouseButtonDown("LeftButton") then
                dragMode = nil; self:SetScript("OnUpdate", nil); return
            elseif dragMode == "pan" and not IsMouseButtonDown("RightButton") then
                dragMode = nil; self:SetScript("OnUpdate", nil); return
            end

            local cx, cy = GetCursorPosition()
            local scale = self:GetEffectiveScale()
            local x, y = cx / scale, cy / scale
            local dx, dy = x - lastX, y - lastY
            lastX, lastY = x, y

            if dragMode == "rotate" then
                myModel:SetFacing((myModel:GetFacing() or 0) + dx * ROTATE_SPEED)
            elseif dragMode == "pan" then
                -- Model:SetPosition(forward, side, up); depth is fixed, so panning slides in screen space only.
                if myModel.GetPosition and myModel.SetPosition then
                    local px, py, pz = myModel:GetPosition()
                    myModel:SetPosition(px or 0, (py or 0) + dx * PAN_SPEED, (pz or 0) + dy * PAN_SPEED)
                end
            end
        end

        mouseOverlay:SetScript("OnMouseDown", function(self, button)
            local cx, cy = GetCursorPosition()
            local scale = self:GetEffectiveScale()
            lastX, lastY = cx / scale, cy / scale
            if button == "LeftButton" then
                dragMode = "rotate"
            elseif button == "RightButton" then
                dragMode = "pan"
            end
            self:SetScript("OnUpdate", _dragOnUpdate)
        end)
        mouseOverlay:SetScript("OnMouseUp", function(self)
            dragMode = nil
            self:SetScript("OnUpdate", nil)
        end)
        mouseOverlay:SetScript("OnHide", function(self)
            dragMode = nil
            self:SetScript("OnUpdate", nil)
        end)

        mouseOverlay:SetScript("OnMouseWheel", function(_, delta)
            zoomLevel = math.max(0, math.min(1, zoomLevel + delta * ZOOM_STEP))
            myModel:SetPortraitZoom(zoomLevel)
        end)


        -- SetUnit handles form transitions; re-bind on equipment change so new gear shows.
        local function _refreshPlayerModel()
            if GetFFD(frame).modelScene and GetFFD(frame).modelScene.SetUnit then
                GetFFD(frame).modelScene:SetUnit("player")
            end
        end
        GetFFD(frame).refreshPlayerModel = _refreshPlayerModel

        local refresh = CreateFrame("Frame")
        refresh:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        refresh:RegisterEvent("TRANSMOGRIFY_UPDATE")
        refresh:RegisterEvent("UNIT_MODEL_CHANGED")
        refresh:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
        refresh:RegisterEvent("PLAYER_ENTERING_WORLD")
        refresh:SetScript("OnEvent", function(_, event, unit)
            -- SetUnit forces a full 3D model reload and UPDATE_SHAPESHIFT_FORM storms in combat, so only pay it while visible; the OnShow hook below re-binds, so closed changes land.
            if not (frame and frame:IsShown()) then return end
            if event == "UNIT_MODEL_CHANGED" and unit and unit ~= "player" then return end
            _refreshPlayerModel()
        end)

        if frame.HookScript then
            frame:HookScript("OnShow", function()
                if GetFFD(frame).refreshPlayerModel then GetFFD(frame).refreshPlayerModel() end
            end)
        end
    end

    if CharacterFrameTitleText then
        CharacterFrameTitleText:ClearAllPoints()
        CharacterFrameTitleText:SetPoint("TOP", frame, "TOP", 0, -6)
        CharacterFrameTitleText:SetJustifyH("CENTER")
    end
    if CharacterLevelText and CharacterFrameTitleText then
        CharacterLevelText:ClearAllPoints()
        CharacterLevelText:SetPoint("TOP", CharacterFrameTitleText, "BOTTOM", 0, -5)
        CharacterLevelText:SetJustifyH("CENTER")
    end

    if CharacterModelFrameHelpText then CharacterModelFrameHelpText:Hide() end

    if CharacterFrameInsetBG then CharacterFrameInsetBG:Hide() end
    if CharacterFrameInset and CharacterFrameInset.NineSlice then
        for _, edge in ipairs({"TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner"}) do
            if CharacterFrameInset.NineSlice[edge] then
                CharacterFrameInset.NineSlice[edge]:Hide()
            end
        end
        CharacterFrameInset.NineSlice:SetAlpha(0)
    end
    if CharacterFrameInset and CharacterFrameInset.Bg then
        CharacterFrameInset.Bg:SetAlpha(0)
    end


    if frame.PaperDollFrame then
        if frame.PaperDollFrame.InnerBorder then
            for _, name in ipairs({"Top", "Bottom", "Left", "Right", "TopLeft", "TopRight", "BottomLeft", "BottomRight"}) do
                if frame.PaperDollFrame.InnerBorder[name] then
                    frame.PaperDollFrame.InnerBorder[name]:Hide()
                end
            end
        end
    end

    for _, name in ipairs({"TopLeft", "TopRight", "BottomLeft", "BottomRight", "Top", "Bottom", "Left", "Right", "Bottom2"}) do
        if _G["PaperDollInnerBorder" .. name] then
            _G["PaperDollInnerBorder" .. name]:Hide()
        end
    end

    if PaperDollItemsFrame then PaperDollItemsFrame:Hide() end
    if CharacterStatPane then
        if CharacterStatPane.ClassBackground then
            CharacterStatPane.ClassBackground:Hide()
        end
        -- Park off-screen (never Hide -- that can taint the secure layout).
        CharacterStatPane:ClearAllPoints()
        CharacterStatPane:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -10000)
    end

    if _G["CharacterSecondaryHandSlot.26129b81ae0"] then
        _G["CharacterSecondaryHandSlot.26129b81ae0"]:Hide()
    end


    -- Hide the SlotFrame wrappers -- we reposition the inner slot buttons directly.
    _G.CharacterBackSlotFrame:Hide()
    _G.CharacterChestSlotFrame:Hide()
    _G.CharacterFeetSlotFrame:Hide()
    _G.CharacterFinger0SlotFrame:Hide()
    _G.CharacterFinger1SlotFrame:Hide()
    _G.CharacterHandsSlotFrame:Hide()
    _G.CharacterHeadSlotFrame:Hide()
    _G.CharacterLegsSlotFrame:Hide()
    _G.CharacterMainHandSlotFrame:Hide()
    _G.CharacterNeckSlotFrame:Hide()
    _G.CharacterSecondaryHandSlotFrame:Hide()
    _G.CharacterShirtSlotFrame:Hide()
    _G.CharacterShoulderSlotFrame:Hide()
    _G.CharacterTabardSlotFrame:Hide()
    _G.CharacterTrinket0SlotFrame:Hide()
    _G.CharacterTrinket1SlotFrame:Hide()
    _G.CharacterWaistSlotFrame:Hide()
    _G.CharacterWristSlotFrame:Hide()

    -- Grid layout via SetPoint only. Never reparent -- slots are secure and reparenting would taint the paper-doll.
    if CharacterFrameBg then CharacterFrameBg:Show() end

    local slotNames = {
        "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot", "CharacterBackSlot",
        "CharacterChestSlot", "CharacterShirtSlot", "CharacterTabardSlot", "CharacterWristSlot",
        "CharacterHandsSlot", "CharacterWaistSlot", "CharacterLegsSlot", "CharacterFeetSlot",
        "CharacterTrinket0Slot", "CharacterTrinket1Slot", "CharacterFinger0Slot", "CharacterFinger1Slot",
        "CharacterMainHandSlot", "CharacterSecondaryHandSlot"
    }

    for _, slotName in ipairs(slotNames) do
        local slot = _G[slotName]
        if slot then
            slot:Show()
            local parent = slot:GetParent()
            if parent then
                parent:Show()
            end
        end
    end

    local gridCols = 2
    local cellWidth = 280
    local cellHeight = 41
    local gridStartX = 14
    local gridStartY = -60

    local slotGridMap = {
        CharacterHeadSlot = {col = 0, row = 0},
        CharacterNeckSlot = {col = 0, row = 1},
        CharacterShoulderSlot = {col = 0, row = 2},
        CharacterBackSlot = {col = 0, row = 3},
        CharacterChestSlot = {col = 0, row = 4},
        CharacterShirtSlot = {col = 0, row = 5},
        CharacterTabardSlot = {col = 0, row = 6},
        CharacterWristSlot = {col = 0, row = 7},
        CharacterHandsSlot = {col = 1, row = 0},
        CharacterWaistSlot = {col = 1, row = 1},
        CharacterLegsSlot = {col = 1, row = 2},
        CharacterFeetSlot = {col = 1, row = 3},
        CharacterFinger0Slot = {col = 1, row = 4},
        CharacterFinger1Slot = {col = 1, row = 5},
        CharacterTrinket0Slot = {col = 1, row = 6},
        CharacterTrinket1Slot = {col = 1, row = 7},
    }

    for slotName, gridPos in pairs(slotGridMap) do
        local slot = _G[slotName]
        if slot then
            slot:ClearAllPoints()
            local xOffset = gridStartX + (gridPos.col * cellWidth)
            local yOffset = gridStartY - (gridPos.row * cellHeight)
            slot:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", xOffset, yOffset)
        end
    end

    -- Weapons live in the bottom strip, outside the 2-column grid.
    _G.CharacterMainHandSlot:ClearAllPoints()
    _G.CharacterMainHandSlot:SetPoint("BOTTOMLEFT", CharacterFrame, "BOTTOMLEFT", 128, 10)
    _G.CharacterSecondaryHandSlot:ClearAllPoints()
    _G.CharacterSecondaryHandSlot:SetPoint("TOPLEFT", _G.CharacterMainHandSlot, "TOPRIGHT", 12, 0)



    -- Weapon-slot regions 16/17 are the ornamented border/frame textures. Shifting texcoords off-atlas is cheaper than SetTexture("") and survives Blizzard re-applying the atlas.
    select(16, _G.CharacterMainHandSlot:GetRegions()):SetTexCoord(.8,.8,.8,.8,.8,.8,.8,.8)
    select(17, _G.CharacterMainHandSlot:GetRegions()):SetTexCoord(.8,.8,.8,.8,.8,.8,.8,.8)
    select(16, _G.CharacterSecondaryHandSlot:GetRegions()):SetTexCoord(.8,.8,.8,.8,.8,.8,.8,.8)
    select(17, _G.CharacterSecondaryHandSlot:GetRegions()):SetTexCoord(.8,.8,.8,.8,.8,.8,.8,.8)

    -- Strip icon borders and crop icon texcoords so icons fill the slot cleanly.
    local slotsToHide = {
        "CharacterBackSlot", "CharacterChestSlot", "CharacterFeetSlot",
        "CharacterFinger0Slot", "CharacterFinger1Slot", "CharacterHandsSlot",
        "CharacterHeadSlot", "CharacterLegsSlot", "CharacterMainHandSlot",
        "CharacterNeckSlot", "CharacterSecondaryHandSlot", "CharacterShirtSlot",
        "CharacterShoulderSlot", "CharacterTabardSlot", "CharacterTrinket0Slot",
        "CharacterTrinket1Slot", "CharacterWaistSlot", "CharacterWristSlot"
    }

    for _, slotName in ipairs(slotsToHide) do
        local slot = _G[slotName]
        if slot then
            slot:Show()
            if slot.IconBorder then
                slot.IconBorder:SetTexCoord(.8,.8,.8,.8,.8,.8,.8,.8)
            end
            local iconTexture = _G[slotName .. "IconTexture"]
            if iconTexture then
                local z = (EllesmereUIDB and EllesmereUIDB.charSheetIconZoom) or 0.07
                iconTexture:SetTexCoord(z, z, z, 1 - z, 1 - z, z, 1 - z, 1 - z)
            end
            local normalTexture = _G[slotName .. "NormalTexture"]
            if normalTexture then
                normalTexture:Hide()
            end
        end
    end

    -- Re-apply 16/17: the loop above includes the weapon slots and clobbers them.
    select(16, _G.CharacterMainHandSlot:GetRegions()):SetTexCoord(0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
    select(17, _G.CharacterMainHandSlot:GetRegions()):SetTexCoord(0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
    select(16, _G.CharacterSecondaryHandSlot:GetRegions()):SetTexCoord(0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
    select(17, _G.CharacterSecondaryHandSlot:GetRegions()):SetTexCoord(0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)

    local slotNames = {
        "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot", "CharacterBackSlot",
        "CharacterChestSlot", "CharacterShirtSlot", "CharacterTabardSlot", "CharacterWristSlot",
        "CharacterHandsSlot", "CharacterWaistSlot", "CharacterLegsSlot", "CharacterFeetSlot",
        "CharacterTrinket0Slot", "CharacterTrinket1Slot", "CharacterFinger0Slot", "CharacterFinger1Slot",
        "CharacterMainHandSlot", "CharacterSecondaryHandSlot"
    }
    for _, slotName in ipairs(slotNames) do
        local slot = _G[slotName]
        if slot then
            slot:Show()
            if GetFFD(slot).slotBg then
                GetFFD(slot).slotBg:SetBlendMode("BLEND")
            end
        end
    end

    -- Scale fully owned by Blizzard (SetScale on secure panels taints UIParentPanelManager execution context).
    frame:SetFrameStrata("HIGH")

    -- Frame size is entirely Blizzard's -- no SetWidth/SetHeight or OnUpdate enforcers on the secure frame; our layout fits inside native dimensions.
    if CharacterFrameInset then
        CharacterFrameInset:SetClipsChildren(false)
    end
    GetFFD(frame).sizeCheckDone = true
end

local function SkinCharacterSheet()
    if skinned then return end
    skinned = true

    PreSkinCharacterSheet()

    local frame = CharacterFrame
    if not frame then return end

    local FRAME_BG_R, FRAME_BG_G, FRAME_BG_B = 0.03, 0.045, 0.05

    local closeBtn = frame.CloseButton or _G.CharacterFrameCloseButton
    if closeBtn then
        if closeBtn.SetNormalTexture then closeBtn:SetNormalTexture("") end
        if closeBtn.SetPushedTexture then closeBtn:SetPushedTexture("") end
        if closeBtn.SetHighlightTexture then closeBtn:SetHighlightTexture("") end
        if closeBtn.SetDisabledTexture then closeBtn:SetDisabledTexture("") end

        for i = 1, select("#", closeBtn:GetRegions()) do
            local region = select(i, closeBtn:GetRegions())
            if region and region:IsObjectType("Texture") and region ~= GetFFD(closeBtn).x then
                region:SetAlpha(0)
            end
        end

        local closeX = closeBtn:CreateTexture(nil, "OVERLAY")
        closeX:SetAtlas("uitools-icon-close")
        closeX:SetSize(14, 14)
        closeX:SetPoint("CENTER", -2, 0)
        closeX:SetVertexColor(1, 1, 1, 0.75)
        GetFFD(closeBtn).x = closeX

        closeBtn:HookScript("OnEnter", function()
            if GetFFD(closeBtn).x then GetFFD(closeBtn).x:SetVertexColor(1, 1, 1, 1) end
        end)
        closeBtn:HookScript("OnLeave", function()
            if GetFFD(closeBtn).x then GetFFD(closeBtn).x:SetVertexColor(1, 1, 1, 0.75) end
        end)
    end

    local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("blizzardSkin") or STANDARD_TEXT_FONT
    local EG = EllesmereUI.ELLESMERE_GREEN or { r = 0.51, g = 0.784, b = 1 }

    do
        local modelScene = GetFFD(frame).modelScene
        if modelScene and not GetFFD(frame).durabilityModelLabel then
            local durOverlay = CreateFrame("Frame", nil, frame)
            durOverlay:SetFrameLevel(5)
            durOverlay:EnableMouse(false)
            GetFFD(frame).durabilityOverlay = durOverlay

            local durabilityModelLabel = durOverlay:CreateFontString(nil, "OVERLAY")
            durabilityModelLabel:SetFont(fontPath, 12, "")
            durabilityModelLabel:SetPoint("TOP", modelScene, "TOP", 0, -8)
            GetFFD(frame).durabilityModelLabel = durabilityModelLabel
        end
        if not GetFFD(frame).durabilityFooterLabel then
            local durabilityFooterLabel = frame:CreateFontString(nil, "OVERLAY")
            durabilityFooterLabel:SetFont(fontPath, 12, "")
            GetFFD(frame).durabilityFooterLabel = durabilityFooterLabel
        end
    end

    local charTabs = {}
    for i = 1, 3 do
        local tab = _G["CharacterFrameTab" .. i]
        if tab then
            charTabs[#charTabs + 1] = tab
            for j = 1, select("#", tab:GetRegions()) do
                local region = select(j, tab:GetRegions())
                if region and region:IsObjectType("Texture") then
                    region:SetTexture("")
                    if region.SetAtlas then region:SetAtlas("") end
                end
            end
            if tab.Left then tab.Left:SetTexture("") end
            if tab.Middle then tab.Middle:SetTexture("") end
            if tab.Right then tab.Right:SetTexture("") end
            if tab.LeftDisabled then tab.LeftDisabled:SetTexture("") end
            if tab.MiddleDisabled then tab.MiddleDisabled:SetTexture("") end
            if tab.RightDisabled then tab.RightDisabled:SetTexture("") end
            local hl = tab:GetHighlightTexture()
            if hl then hl:SetTexture("") end

            if not GetFFD(tab).bg then
                GetFFD(tab).bg = tab:CreateTexture(nil, "BACKGROUND")
                GetFFD(tab).bg:SetAllPoints()
                GetFFD(tab).bg:SetColorTexture(0.068, 0.056, 0.052, 1)
            end

            if not GetFFD(tab).activeHL then
                local activeHL = tab:CreateTexture(nil, "ARTWORK", nil, -6)
                activeHL:SetAllPoints()
                activeHL:SetColorTexture(1, 1, 1, 0.02)
                activeHL:SetBlendMode("ADD")
                activeHL:Hide()
                GetFFD(tab).activeHL = activeHL
            end

            -- Replace Blizzard's label with our own so font/size are under our control.
            local blizLabel = tab:GetFontString()
            local labelText = blizLabel and blizLabel:GetText() or ("Tab " .. i)
            if blizLabel then blizLabel:SetTextColor(0, 0, 0, 0) end
            tab:SetPushedTextOffset(0, 0)

            if not GetFFD(tab).label then
                local label = tab:CreateFontString(nil, "OVERLAY")
                label:SetFont(fontPath, 9, "")
                label:SetPoint("CENTER", tab, "CENTER", 0, 0)
                label:SetJustifyH("CENTER")
                label:SetText(labelText)
                GetFFD(tab).label = label
                hooksecurefunc(tab, "SetText", function(_, newText)
                    if newText and label then label:SetText(newText) end
                end)
            end

            if not GetFFD(tab).underline then
                local underline = tab:CreateTexture(nil, "OVERLAY", nil, 6)
                if EllesmereUI and EllesmereUI.PanelPP and EllesmereUI.PanelPP.DisablePixelSnap then
                    EllesmereUI.PanelPP.DisablePixelSnap(underline)
                    underline:SetHeight(EllesmereUI.PanelPP.mult or 1)
                else
                    underline:SetHeight(1)
                end
                underline:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)
                underline:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
                underline:SetColorTexture(EG.r or 0.51, EG.g or 0.784, EG.b or 1, 1)
                if EllesmereUI and EllesmereUI.RegAccent then
                    EllesmereUI.RegAccent({ type = "solid", obj = underline, a = 1 })
                end
                underline:Hide()
                GetFFD(tab).underline = underline
            end
        end
    end
    -- Uniform one-physical-pixel seam between bottom tabs, as in every other themed window (raw CharacterFrameTab frames sit further apart).
    if ns.WSkin and ns.WSkin.NormalizeTabRow then ns.WSkin.NormalizeTabRow(charTabs) end

    local function UpdateTabVisuals()
        for i = 1, 3 do
            local tab = _G["CharacterFrameTab" .. i]
            if tab then
                -- PanelTemplates_GetSelectedTab is unreliable here -- Blizzard updates frame.selectedTab before the template helper agrees.
                local isActive = (frame.selectedTab or 1) == i
                if GetFFD(tab).label then
                    GetFFD(tab).label:SetTextColor(1, 1, 1, isActive and 1 or 0.5)
                end
                if GetFFD(tab).underline then
                    GetFFD(tab).underline:SetShown(isActive)
                end
                if GetFFD(tab).activeHL then
                    GetFFD(tab).activeHL:SetShown(isActive)
                end
            end
        end
    end

    -- Show/Hide on secure slot buttons in combat fires ADDON_ACTION_BLOCKED and can taint,
    -- so defer to PLAYER_REGEN_ENABLED; one shared frame absorbs bursts of tab changes without leaking event registrations.
    local _deferredVisibility = CreateFrame("Frame")
    _deferredVisibility._shows = {}
    _deferredVisibility._hides = {}
    _deferredVisibility:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        for _, el in ipairs(self._shows) do if el then el:Show() end end
        for _, el in ipairs(self._hides) do if el then el:Hide() end end
        wipe(self._shows); wipe(self._hides)
    end)

    local function SafeShow(element)
        if not element then return end
        if InCombatLockdown() then
            _deferredVisibility._shows[#_deferredVisibility._shows + 1] = element
            _deferredVisibility:RegisterEvent("PLAYER_REGEN_ENABLED")
        else
            element:Show()
        end
    end

    local function SafeHide(element)
        if not element then return end
        if InCombatLockdown() then
            _deferredVisibility._hides[#_deferredVisibility._hides + 1] = element
            _deferredVisibility:RegisterEvent("PLAYER_REGEN_ENABLED")
        else
            element:Hide()
        end
    end

    -- Faint background on the Reputation + Currency panes, idempotent. Anchored to the inner
    -- ScrollBox so it stays in the list area and never bleeds over the tab chrome.
    local function _ensureTabBg(pane)
        if not pane or GetFFD(pane).bg then return end
        local anchor = pane.ScrollBox or pane.scrollFrame or pane
        local tex = pane:CreateTexture(nil, "BACKGROUND", nil, -7)
        tex:SetColorTexture(0, 0, 0, 0.1)
        tex:SetPoint("TOPLEFT",     anchor, "TOPLEFT",     10, -10)
        tex:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -10,  0)
        GetFFD(pane).bg = tex
    end
    _ensureTabBg(_G.ReputationFrame)
    _ensureTabBg(_G.TokenFrame)

    -- Tab visibility dispatcher: hook each sub-pane's OnShow (Blizzard drives visibility, we react)
    -- instead of intercepting PanelTemplates_SetTab. Pane OnShow runs inside the secure ShowSubFrame
    -- path, where explicit :Show()/:Hide() (even on our own named frames) flags as a protected call; SetShown does not, so every toggle below uses SetShown.
    local function ApplyTabVisibility(isCharacterTab)
        UpdateTabVisuals()
        -- Swapping back to the Character bottom-tab must also re-highlight our top-row Character button (hook installed below as _reactivateCharTab).
        if isCharacterTab and GetFFD(frame).reactivateCharTab then
            GetFFD(frame).reactivateCharTab()
        end

        if GetFFD(frame).themedSlots then
            for _, slotName in ipairs(GetFFD(frame).themedSlots) do
                local slot = _G[slotName]
                if slot then
                    slot:SetShown(isCharacterTab)
                    if GetFFD(slot).itemLevelLabel    then GetFFD(slot).itemLevelLabel:SetShown(isCharacterTab)    end
                    if GetFFD(slot).enchantLabel      then GetFFD(slot).enchantLabel:SetShown(isCharacterTab)      end
                    if GetFFD(slot).enchantHoverFrame then GetFFD(slot).enchantHoverFrame:SetShown(isCharacterTab) end
                    if GetFFD(slot).upgradeTrackLabel then GetFFD(slot).upgradeTrackLabel:SetShown(isCharacterTab) end
                end
            end
        end

        for _, btnName in ipairs({"EUI_CharSheet_Stats", "EUI_CharSheet_Titles", "EUI_CharSheet_Equipment"}) do
            local btn = _G[btnName]
            if btn then btn:SetShown(isCharacterTab) end
        end

        if GetFFD(frame).modelBgFrame     then GetFFD(frame).modelBgFrame:SetShown(isCharacterTab)     end
        if GetFFD(frame).statsPanel       then GetFFD(frame).statsPanel:SetShown(isCharacterTab)       end
        if GetFFD(frame).iLvlText         then GetFFD(frame).iLvlText:SetShown(isCharacterTab)         end
        if GetFFD(frame).sidebarBgFrame   then GetFFD(frame).sidebarBgFrame:SetShown(isCharacterTab)   end
        if GetFFD(frame).scrollFrame      then GetFFD(frame).scrollFrame:SetShown(isCharacterTab)      end
        if GetFFD(frame).scrollBar        then GetFFD(frame).scrollBar:SetShown(isCharacterTab)        end
        if GetFFD(frame).socketContainer  then GetFFD(frame).socketContainer:SetShown(isCharacterTab)  end

        if GetFFD(frame).statsSections then
            for _, sectionData in ipairs(GetFFD(frame).statsSections) do
                if sectionData.container then
                    sectionData.container:SetShown(isCharacterTab)
                end
            end
        end

        -- Titles / Equipment sub-panels only exist on the Character tab.
        if not isCharacterTab then
            if GetFFD(frame).titlesPanel then GetFFD(frame).titlesPanel:SetShown(false) end
            if GetFFD(frame).equipPanel  then GetFFD(frame).equipPanel:SetShown(false)  end
        end

        if GetFFD(frame).modelScene   then GetFFD(frame).modelScene:SetShown(isCharacterTab)   end
        if GetFFD(frame).modelBgFrame then GetFFD(frame).modelBgFrame:SetShown(isCharacterTab) end
        if EllesmereUI._updateCharSheetDurability then EllesmereUI._updateCharSheetDurability() end
    end

    local function _hookPaneOnShow(pane, isChar)
        if not pane then return end
        pane:HookScript("OnShow", function()
            _ensureTabBg(_G.ReputationFrame)
            _ensureTabBg(_G.TokenFrame)
            ApplyTabVisibility(isChar)
        end)
    end
    _hookPaneOnShow(_G.PaperDollFrame,  true)
    _hookPaneOnShow(_G.ReputationFrame, false)
    _hookPaneOnShow(_G.TokenFrame,      false)


    ApplyTabVisibility((frame.selectedTab or 1) == 1)

    -- Stats panel: fixed-width column pinned down the right of the sheet.
    local statsPanel = CreateFrame("Frame", "EUI_CharSheet_StatsPanel", frame)
    statsPanel:SetWidth(190)
    statsPanel:SetPoint("TOPLEFT",    frame, "TOPLEFT",    345, -60)
    statsPanel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 345,  40)
    statsPanel:SetFrameLevel(50)

    -- Sidebar background lives on frame (not statsPanel) so it stays visible across Character/Titles/Equipment panels.
    local sidebarBgFrame = CreateFrame("Frame", nil, frame)
    sidebarBgFrame:SetFrameLevel(statsPanel:GetFrameLevel() - 1)
    sidebarBgFrame:SetPoint("TOPLEFT", statsPanel, "TOPLEFT", -51, 10)
    sidebarBgFrame:SetPoint("BOTTOMRIGHT", statsPanel, "BOTTOMRIGHT", 0, -10)
    local statsBg = sidebarBgFrame:CreateTexture(nil, "BACKGROUND")
    statsBg:SetColorTexture(0, 0, 0, 0.2)
    statsBg:SetAllPoints()
    GetFFD(frame).statsBg = statsBg
    GetFFD(frame).sidebarBgFrame = sidebarBgFrame

    local INVTYPE_TO_SLOT = {
        INVTYPE_HEAD = {slot = 1, name = "Head"},
        INVTYPE_NECK = {slot = 2, name = "Neck"},
        INVTYPE_SHOULDER = {slot = 3, name = "Shoulder"},
        INVTYPE_CHEST = {slot = 5, name = "Chest"},
        -- Cloth robes report INVTYPE_ROBE instead of INVTYPE_CHEST -- same slot.
        INVTYPE_ROBE = {slot = 5, name = "Chest"},
        INVTYPE_WAIST = {slot = 6, name = "Waist"},
        INVTYPE_LEGS = {slot = 7, name = "Legs"},
        INVTYPE_FEET = {slot = 8, name = "Feet"},
        INVTYPE_WRIST = {slot = 9, name = "Wrist"},
        INVTYPE_HAND = {slot = 10, name = "Hands"},
        INVTYPE_FINGER = {slots = {11, 12}, name = "Ring"},
        INVTYPE_TRINKET = {slots = {13, 14}, name = "Trinket"},
        -- A cloak's equip-location string is INVTYPE_CLOAK, never INVTYPE_BACK.
        -- "Cloak" (not "Back") so this doesn't collide with the "Back" nav-button
        -- key elsewhere in the catalog; matches EUI_UpgradeCalc.lua's slotNames[15].
        INVTYPE_CLOAK = {slot = 15, name = "Cloak"},
        -- One-hand weapons report INVTYPE_WEAPONMAINHAND / INVTYPE_WEAPONOFFHAND;
        -- INVTYPE_MAINHAND / INVTYPE_OFFHAND do not exist and match no item. An
        -- ambiguous one-hander (INVTYPE_WEAPON) can go in either slot.
        INVTYPE_WEAPON = {slots = {16, 17}, name = "Weapon"},
        INVTYPE_WEAPONMAINHAND = {slot = 16, name = "Main Hand"},
        INVTYPE_WEAPONOFFHAND = {slot = 17, name = "Off Hand"},
        -- Caster off-hands (tomes/orbs); the slot mapping is what lets them reach
        -- the allow.offhand gate in IsItemUsableBySpec.
        INVTYPE_HOLDABLE = {slot = 17, name = "Off Hand"},
        -- Bows/guns/crossbows/wands report these equip locations even though they
        -- physically equip into the main-hand slot.
        INVTYPE_RANGEDRIGHT = {slot = 16, name = "Main Hand"},
        INVTYPE_RANGED = {slot = 16, name = "Main Hand"},
        INVTYPE_RELIC = {slot = 18, name = "Relic"},
        INVTYPE_BODY = {slot = 4, name = "Body"},
        INVTYPE_SHIELD = {slot = 17, name = "Shield"},
        INVTYPE_2HWEAPON = {slot = 16, name = "Two-Hand"},
    }

    -- Item level of the equipped item. GetItemInfo's cached itemLevel can be wrong for a
    -- specific instance (upgrade-track pieces); prefer ItemLocation (exact, uncached) then GetDetailedItemLevelInfo -- same precedence as EllesmereUIQoL.lua.
    local function GetEquippedItemLevel(slot)
        if ItemLocation then
            local loc = ItemLocation:CreateFromEquipmentSlot(slot)
            if loc and loc:IsValid() and C_Item.DoesItemExist(loc) then
                return C_Item.GetCurrentItemLevel(loc) or 0
            end
        end
        local itemLink = GetInventoryItemLink("player", slot)
        if itemLink then
            return C_Item.GetDetailedItemLevelInfo(itemLink) or 0
        end
        return 0
    end

    ---------------------------------------------------------------------------
    -- Spec-aware "better item" filter: hardcoded allowlist of weapon subclasses +
    -- shield/offhand usability per spec, so a higher-ilvl but unusable piece (a
    -- shield for Ret, a 2H polearm for Prot) never counts as an upgrade.
    --
    -- Weapon subclass IDs (Enum.ItemWeaponSubclass):
    --   0  Axe1H     1  Axe2H       2  Bow       3  Gun
    --   4  Mace1H    5  Mace2H      6  Polearm   7  Sword1H
    --   8  Sword2H   9  Warglaive   10 Staff     13 Fist
    --   15 Dagger    18 Crossbow    19 Wand
    ---------------------------------------------------------------------------
    local W_AXE1H, W_AXE2H   = 0, 1
    local W_BOW, W_GUN       = 2, 3
    local W_MACE1H, W_MACE2H = 4, 5
    local W_POLEARM          = 6
    local W_SWORD1H, W_SWORD2H = 7, 8
    local W_WARGLAIVE        = 9
    local W_STAFF            = 10
    local W_FIST             = 13
    local W_DAGGER           = 15
    local W_CROSSBOW         = 18
    local W_WAND             = 19

    -- Armor subclasses
    local A_MISC, A_CLOTH, A_LEATHER, A_MAIL, A_PLATE = 0, 1, 2, 3, 4
    local A_SHIELD = 6

    -- Class -> top armor proficiency. Lower tiers are ignored since wearing
    -- below-proficiency armor is never an upgrade for these specs.
    local CLASS_ARMOR = {
        PALADIN = A_PLATE, DEATHKNIGHT = A_PLATE, WARRIOR = A_PLATE,
        HUNTER  = A_MAIL,  SHAMAN      = A_MAIL,  EVOKER  = A_MAIL,
        DRUID   = A_LEATHER, MONK = A_LEATHER, ROGUE = A_LEATHER, DEMONHUNTER = A_LEATHER,
        MAGE    = A_CLOTH, PRIEST      = A_CLOTH, WARLOCK = A_CLOTH,
    }

    -- Per-spec weapon + shield/offhand usability.
    local SPEC_EQUIP = {
        -- Death Knight
        [250] = { weapons = { [W_AXE2H]=1, [W_MACE2H]=1, [W_SWORD2H]=1, [W_POLEARM]=1 } }, -- Blood
        [251] = { weapons = { [W_AXE1H]=1, [W_MACE1H]=1, [W_SWORD1H]=1 } },                 -- Frost (DW 1H)
        [252] = { weapons = { [W_AXE2H]=1, [W_MACE2H]=1, [W_SWORD2H]=1, [W_POLEARM]=1 } }, -- Unholy
        -- Demon Hunter
        [577] = { weapons = { [W_WARGLAIVE]=1, [W_AXE1H]=1, [W_SWORD1H]=1, [W_FIST]=1 } }, -- Havoc
        [581] = { weapons = { [W_WARGLAIVE]=1, [W_AXE1H]=1, [W_SWORD1H]=1, [W_FIST]=1 } }, -- Vengeance
        -- Druid
        [102] = { weapons = { [W_STAFF]=1, [W_POLEARM]=1, [W_MACE2H]=1, [W_DAGGER]=1, [W_MACE1H]=1 }, offhand=true }, -- Balance
        [103] = { weapons = { [W_STAFF]=1, [W_POLEARM]=1, [W_MACE2H]=1, [W_FIST]=1 } },                               -- Feral
        [104] = { weapons = { [W_STAFF]=1, [W_POLEARM]=1, [W_MACE2H]=1 } },                                           -- Guardian
        [105] = { weapons = { [W_STAFF]=1, [W_MACE2H]=1, [W_POLEARM]=1, [W_MACE1H]=1, [W_DAGGER]=1 }, offhand=true }, -- Resto
        -- Hunter
        [253] = { weapons = { [W_BOW]=1, [W_GUN]=1, [W_CROSSBOW]=1 } },           -- BM
        [254] = { weapons = { [W_BOW]=1, [W_GUN]=1, [W_CROSSBOW]=1 } },           -- MM
        [255] = { weapons = { [W_POLEARM]=1, [W_SWORD2H]=1, [W_AXE2H]=1 } },      -- Survival
        -- Mage
        [62]  = { weapons = { [W_STAFF]=1, [W_DAGGER]=1, [W_SWORD1H]=1, [W_WAND]=1 }, offhand=true }, -- Arcane
        [63]  = { weapons = { [W_STAFF]=1, [W_DAGGER]=1, [W_SWORD1H]=1, [W_WAND]=1 }, offhand=true }, -- Fire
        [64]  = { weapons = { [W_STAFF]=1, [W_DAGGER]=1, [W_SWORD1H]=1, [W_WAND]=1 }, offhand=true }, -- Frost
        -- Monk
        [268] = { weapons = { [W_STAFF]=1, [W_POLEARM]=1, [W_FIST]=1, [W_AXE1H]=1, [W_MACE1H]=1, [W_SWORD1H]=1 }, offhand=true }, -- Brewmaster
        [269] = { weapons = { [W_FIST]=1, [W_AXE1H]=1, [W_MACE1H]=1, [W_SWORD1H]=1, [W_STAFF]=1, [W_POLEARM]=1 }, offhand=true }, -- Windwalker
        [270] = { weapons = { [W_STAFF]=1, [W_FIST]=1, [W_AXE1H]=1, [W_MACE1H]=1, [W_SWORD1H]=1 }, offhand=true },                -- Mistweaver
        -- Paladin
        [65]  = { weapons = { [W_MACE1H]=1, [W_SWORD1H]=1, [W_AXE1H]=1 }, shield=true, offhand=true }, -- Holy
        [66]  = { weapons = { [W_MACE1H]=1, [W_SWORD1H]=1, [W_AXE1H]=1 }, shield=true },               -- Prot
        [70]  = { weapons = { [W_MACE2H]=1, [W_SWORD2H]=1, [W_AXE2H]=1, [W_POLEARM]=1,
                              [W_MACE1H]=1, [W_SWORD1H]=1, [W_AXE1H]=1 } },                           -- Ret (2H or DW 1H)
        -- Priest
        [256] = { weapons = { [W_STAFF]=1, [W_WAND]=1, [W_DAGGER]=1, [W_MACE1H]=1 }, offhand=true }, -- Disc
        [257] = { weapons = { [W_STAFF]=1, [W_WAND]=1, [W_DAGGER]=1, [W_MACE1H]=1 }, offhand=true }, -- Holy
        [258] = { weapons = { [W_STAFF]=1, [W_WAND]=1, [W_DAGGER]=1, [W_MACE1H]=1 }, offhand=true }, -- Shadow
        -- Rogue
        [259] = { weapons = { [W_DAGGER]=1 } },                                                                 -- Assassination
        [260] = { weapons = { [W_SWORD1H]=1, [W_MACE1H]=1, [W_AXE1H]=1, [W_FIST]=1, [W_DAGGER]=1 } },           -- Outlaw
        [261] = { weapons = { [W_DAGGER]=1 } },                                                                 -- Subtlety
        -- Shaman
        [262] = { weapons = { [W_STAFF]=1, [W_MACE1H]=1, [W_AXE1H]=1, [W_DAGGER]=1 }, shield=true, offhand=true }, -- Elemental
        [263] = { weapons = { [W_MACE1H]=1, [W_AXE1H]=1, [W_FIST]=1 } },                                           -- Enhancement (DW 1H)
        [264] = { weapons = { [W_STAFF]=1, [W_MACE1H]=1, [W_AXE1H]=1, [W_DAGGER]=1 }, shield=true, offhand=true }, -- Resto
        -- Warlock
        [265] = { weapons = { [W_STAFF]=1, [W_WAND]=1, [W_DAGGER]=1, [W_SWORD1H]=1 }, offhand=true }, -- Affliction
        [266] = { weapons = { [W_STAFF]=1, [W_WAND]=1, [W_DAGGER]=1, [W_SWORD1H]=1 }, offhand=true }, -- Demonology
        [267] = { weapons = { [W_STAFF]=1, [W_WAND]=1, [W_DAGGER]=1, [W_SWORD1H]=1 }, offhand=true }, -- Destruction
        -- Warrior
        [71]  = { weapons = { [W_AXE2H]=1, [W_MACE2H]=1, [W_SWORD2H]=1, [W_POLEARM]=1 } },                 -- Arms
        [72]  = { weapons = { [W_AXE1H]=1, [W_MACE1H]=1, [W_SWORD1H]=1,
                              [W_AXE2H]=1, [W_MACE2H]=1, [W_SWORD2H]=1, [W_POLEARM]=1 } },                 -- Fury
        [73]  = { weapons = { [W_AXE1H]=1, [W_MACE1H]=1, [W_SWORD1H]=1 }, shield=true },                   -- Prot
        -- Evoker
        [1467] = { weapons = { [W_STAFF]=1, [W_POLEARM]=1, [W_MACE1H]=1, [W_SWORD1H]=1, [W_DAGGER]=1, [W_FIST]=1 }, offhand=true },
        [1468] = { weapons = { [W_STAFF]=1, [W_POLEARM]=1, [W_MACE1H]=1, [W_SWORD1H]=1, [W_DAGGER]=1, [W_FIST]=1 }, offhand=true },
        [1473] = { weapons = { [W_STAFF]=1, [W_POLEARM]=1, [W_MACE1H]=1, [W_SWORD1H]=1, [W_DAGGER]=1, [W_FIST]=1 }, offhand=true },
    }

    -- Returns true if the given item is appropriate for the player's current spec.
    -- Only weapons, shields, and armor are gated; rings/trinkets/necks/cloaks pass.
    local function IsItemUsableBySpec(itemLink, equipLoc, classID, subclassID)
        local specIndex = GetSpecialization and GetSpecialization()
        local specID = specIndex and GetSpecializationInfo(specIndex)
        local allow = specID and SPEC_EQUIP[specID]
        if not allow then return true end  -- unknown spec: don't filter

        -- Weapons (classID 2): subclass must be in the spec's allowed set.
        if classID == 2 then
            return allow.weapons and allow.weapons[subclassID] == 1 or false
        end

        -- Armor (classID 4): shields and holdable offhands are spec-gated;
        -- other armor pieces must match the class's top armor proficiency.
        if classID == 4 then
            if subclassID == A_SHIELD then
                return allow.shield == true
            end
            if equipLoc == "INVTYPE_HOLDABLE" then
                return allow.offhand == true
            end
            -- Tabards, shirts, cloaks (Misc) are always allowed.
            if subclassID == A_MISC or equipLoc == "INVTYPE_TABARD" or equipLoc == "INVTYPE_BODY" or equipLoc == "INVTYPE_CLOAK" then
                return true
            end
            local _, playerClass = UnitClass("player")
            local topArmor = CLASS_ARMOR[playerClass]
            if topArmor and subclassID ~= topArmor then
                return false
            end
        end

        return true
    end

    -- Cached scan of bag items that are upgrades over equipped gear. Dirtied by the
    -- iLvlUpdateFrame handler below (PLAYER_EQUIPMENT_CHANGED, BAG_UPDATE etc) and by CharacterFrame OnShow, only while the sheet is open.
    local _betterCache = nil
    local _betterDirty = true

    local _ComputeBetterInventoryItems  -- defined below

    local function GetBetterInventoryItems()
        if _betterDirty or not _betterCache then
            _betterCache = _ComputeBetterInventoryItems()
            _betterDirty = false
        end
        return _betterCache
    end

    _ComputeBetterInventoryItems = function()
        local betterItems = {}

        -- A 2H main-hand leaves slot 17 empty, so GetEquippedItemLevel(17)=0 and any
        -- off-hand/holdable/shield in bags reads as a false upgrade. Suppress slot-17
        -- comparisons while off-hand is truly empty (Titan's Grip keeps a real item there, comparing normally).
        local offHandBlocked = false
        do
            local mhLink = GetInventoryItemLink("player", 16)
            if mhLink and GetInventoryItemLink("player", 17) == nil then
                local _, _, _, mhEquipLoc = GetItemInfoInstant(mhLink)
                if mhEquipLoc == "INVTYPE_2HWEAPON"
                    or mhEquipLoc == "INVTYPE_RANGED"
                    or mhEquipLoc == "INVTYPE_RANGEDRIGHT" then
                    offHandBlocked = true
                end
            end
        end

        -- Check all bag slots (0 = backpack, 1-4 = bag slots, 5 = reagent
        -- bag -- included since it can hold any item, not just reagents).
        for bagSlot = 0, 5 do
            local bagSize = C_Container.GetContainerNumSlots(bagSlot)
            for slotIndex = 1, bagSize do
                local itemLink = C_Container.GetContainerItemLink(bagSlot, slotIndex)
                if itemLink then
                    local itemName, _, itemRarity, _, _, _, _, _, equipSlot, itemIcon = GetItemInfo(itemLink)
                    -- ItemLocation first (exact, uncached); GetItemInfo's cached itemLevel
                    -- can be stale for a specific instance.
                    local itemLevel
                    if ItemLocation then
                        local loc = ItemLocation:CreateFromBagAndSlot(bagSlot, slotIndex)
                        if loc and loc:IsValid() and C_Item.DoesItemExist(loc) then
                            itemLevel = C_Item.GetCurrentItemLevel(loc)
                        end
                    end
                    itemLevel = tonumber(itemLevel) or tonumber(C_Item.GetDetailedItemLevelInfo(itemLink))

                    -- Weapons/armor only, matched via GetItemInfoInstant's locale-independent
                    -- classID/subclassID (Weapon=2, Armor=4) -- GetItemInfo's itemType/itemSubType
                    -- are localized display strings and would filter out non-English clients.
                    -- GetItemInfoInstant returns: 1 itemID, 2 itemType, 3 itemSubType, 4 itemEquipLoc, 5 iconFileID, 6 classID, 7 subClassID.
                    local _, _, _, _, _, classID, subclassID = GetItemInfoInstant(itemLink)
                    if itemLevel and itemName and (classID == Enum.ItemClass.Weapon or classID == Enum.ItemClass.Armor) and equipSlot then
                        -- Spec-aware usability filter (skip shields on Ret, etc.)
                        if not IsItemUsableBySpec(itemLink, equipSlot, classID, subclassID) then
                            -- skip: not usable by current spec
                        else
                            local slotInfo = INVTYPE_TO_SLOT[equipSlot]
                            if slotInfo then
                                local isBetter = false
                                local compareSlots = slotInfo.slots or {slotInfo.slot}

                                for _, slot in ipairs(compareSlots) do
                                    -- Skip empty off-hand slot behind a 2H weapon (offHandBlocked, above).
                                    if not (offHandBlocked and slot == 17) then
                                        local equippedLevel = GetEquippedItemLevel(slot)
                                        if itemLevel > equippedLevel then
                                            isBetter = true
                                            break
                                        end
                                    end
                                end

                                if isBetter then
                                    table.insert(betterItems, {
                                        name = itemName,
                                        level = itemLevel,
                                        rarity = itemRarity or 1,
                                        icon = itemIcon,
                                        slot = slotInfo.name
                                    })
                                end
                            end
                        end
                    end
                end
            end
        end

        -- Keep only the single highest-ilvl candidate per slot
        local bestPerSlot = {}
        for _, item in ipairs(betterItems) do
            local cur = bestPerSlot[item.slot]
            if not cur or item.level > cur.level then
                bestPerSlot[item.slot] = item
            end
        end
        local deduped = {}
        for _, item in pairs(bestPerSlot) do
            deduped[#deduped + 1] = item
        end

        table.sort(deduped, function(a, b) return a.level > b.level end)

        return deduped
    end

    -- M+ Score display (single inline FontString above itemlevel), colored via |cff...|r escapes based on score brackets.
    local mythicRatingLabel = statsPanel:CreateFontString(nil, "OVERLAY")
    mythicRatingLabel:SetFont(fontPath, 12, "")
    -- Positioned below iLvlText once that FontString exists (see below).
    mythicRatingLabel:SetTextColor(0.8, 0.8, 0.8, 1)
    mythicRatingLabel:SetText(L("M+ Score:"))
    GetFFD(frame).mythicRatingLabel = mythicRatingLabel

    -- Alias for call sites that test the value FontString; the label hosts both parts.
    GetFFD(frame).mythicRatingValue = mythicRatingLabel

    -- Color brackets: highest threshold that the score meets wins.
    local MP_COLOR_BRACKETS = {
        { 3850, "ff8000" }, { 3695, "f9753f" }, { 3575, "f16961" },
        { 3455, "e75e7f" }, { 3335, "db529c" }, { 3215, "cc47b9" },
        { 3095, "b83dd6" }, { 2965, "9c3eed" }, { 2845, "715be5" },
        { 2725, "2c6dde" }, { 2565, "3b7fcd" }, { 2445, "5292b9" },
        { 2325, "5ca6a4" }, { 2205, "5fba8d" }, { 2085, "5cce75" },
        { 1965, "50e258" }, { 1845, "35f72d" }, { 1725, "3eff26" },
        { 1600, "5eff43" }, { 1475, "74ff58" }, { 1350, "88ff6b" },
        { 1225, "98ff7d" }, { 1100, "a8ff8d" }, { 975,  "b6ff9e" },
        { 850,  "c3ffae" }, { 725,  "cfffbd" }, { 600,  "dbffcd" },
        { 475,  "e7ffdd" }, { 350,  "f2ffec" }, { 225,  "fdfffc" },
        { 200,  "ffffff" },
    }
    local function GetMPScoreHex(score)
        for i = 1, #MP_COLOR_BRACKETS do
            if score >= MP_COLOR_BRACKETS[i][1] then
                return MP_COLOR_BRACKETS[i][2]
            end
        end
        return "ffffff"
    end

    -- Itemlevel display: sits just below the 3 tab buttons, inside the panel.
    local iLvlText = statsPanel:CreateFontString(nil, "OVERLAY")
    iLvlText:SetFont(fontPath, 18, "")
    iLvlText:SetPoint("TOP", statsPanel, "TOP", 0, -(25 + 3))  -- buttonHeight(25) + 3 gap
    iLvlText:SetTextColor(0.6, 0.2, 1, 1)
    GetFFD(frame).iLvlText = iLvlText  -- Store for tab visibility control

    -- PvP Item Level: sits directly below the iLvl text when enabled.
    local pvpIlvlText = statsPanel:CreateFontString(nil, "OVERLAY")
    pvpIlvlText:SetFont(fontPath, 12, "")
    pvpIlvlText:SetTextColor(0.8, 0.8, 0.8, 1)
    pvpIlvlText:SetPoint("TOP", iLvlText, "BOTTOM", 0, -4)
    pvpIlvlText:Hide()
    GetFFD(frame).pvpIlvlText = pvpIlvlText

    -- M+ Score sits below PvP ilvl (or iLvl if PvP is hidden).
    mythicRatingLabel:SetPoint("TOP", pvpIlvlText, "BOTTOM", 0, -4)

    local durabilityHeaderLabel = statsPanel:CreateFontString(nil, "OVERLAY")
    durabilityHeaderLabel:SetFont(fontPath, 12, "")
    durabilityHeaderLabel:Hide()
    GetFFD(frame).durabilityHeaderLabel = durabilityHeaderLabel

    local function GetDurabilityHeaderAnchor()
        local ffd = GetFFD(frame)
        if ffd.mythicRatingLabel and ffd.mythicRatingLabel:IsShown() then
            return ffd.mythicRatingLabel
        end
        if ffd.pvpIlvlText and ffd.pvpIlvlText:IsShown() then
            return ffd.pvpIlvlText
        end
        return ffd.iLvlText
    end

    local function AnchorDurabilityFooterLabel(footerLabel)
        if not footerLabel then return end
        footerLabel:ClearAllPoints()
        local socketPanel = _G.EUI_CharSheet_SocketPanel
        if socketPanel and socketPanel:IsShown() then
            footerLabel:SetPoint("RIGHT", socketPanel, "LEFT", -8, 0)
        else
            footerLabel:SetPoint("RIGHT", frame, "BOTTOMRIGHT", -10, 6)
        end
    end

    -- Labels are created once above (model/footer at skin time, header just
    -- above); the ffd handle is stable, so no per-call lookups or closures.
    local durFfd = GetFFD(frame)
    local function HideAllDurabilityLabels()
        if durFfd.durabilityModelLabel then durFfd.durabilityModelLabel:Hide() end
        if durFfd.durabilityHeaderLabel then durFfd.durabilityHeaderLabel:Hide() end
        if durFfd.durabilityFooterLabel then durFfd.durabilityFooterLabel:Hide() end
        if durFfd.durabilityOverlay then durFfd.durabilityOverlay:Hide() end
    end

    -- Zero cost while off or closed: the durability event is registered only
    -- while the feature is enabled AND the sheet is shown (OnShow/OnHide +
    -- the options toggle re-sync); the OnShow pass paints the first value.
    local durEvents
    local UpdateDurabilityDisplay
    local function SyncDurabilityEvents()
        local want = EllesmereUIDB and EllesmereUIDB.showCharSheetDurability and frame:IsShown()
        if want then
            if not durEvents then
                durEvents = CreateFrame("Frame")
                durEvents:SetScript("OnEvent", function() UpdateDurabilityDisplay() end)
            end
            durEvents:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
            -- Self-repair items recalculate alerts without firing the durability
            -- event (Blizzard's DurabilityFrame itself rides the alert event).
            durEvents:RegisterEvent("UPDATE_INVENTORY_ALERTS")
        elseif durEvents then
            durEvents:UnregisterEvent("UPDATE_INVENTORY_DURABILITY")
            durEvents:UnregisterEvent("UPDATE_INVENTORY_ALERTS")
        end
    end

    UpdateDurabilityDisplay = function()
        SyncDurabilityEvents()
        if not (EllesmereUIDB and EllesmereUIDB.showCharSheetDurability)
            or not (PaperDollFrame and PaperDollFrame:IsShown()) then
            HideAllDurabilityLabels()
            return
        end

        local modelLabel = durFfd.durabilityModelLabel
        local headerLabel = durFfd.durabilityHeaderLabel
        local footerLabel = durFfd.durabilityFooterLabel
        local overlay = durFfd.durabilityOverlay
        local location = EllesmereUIDB.charSheetDurabilityLocation or "model"
        local showLabel = EllesmereUIDB.charSheetDurabilityShowLabel ~= false
        local pct = GetDurabilityPercent()
        local r, g, b = GetDurabilityTextColor(pct)
        local text = FormatDurabilityText(pct, showLabel)

        HideAllDurabilityLabels()

        if location == "header" and headerLabel then
            local anchor = GetDurabilityHeaderAnchor()
            if anchor then
                headerLabel:ClearAllPoints()
                headerLabel:SetPoint("TOP", anchor, "BOTTOM", 0, -4)
            end
            headerLabel:SetText(text)
            headerLabel:SetTextColor(r, g, b, 1)
            headerLabel:Show()
        elseif location == "footer" and footerLabel then
            AnchorDurabilityFooterLabel(footerLabel)
            footerLabel:SetText(text)
            footerLabel:SetTextColor(r, g, b, 1)
            footerLabel:Show()
        elseif modelLabel then
            modelLabel:SetText(text)
            modelLabel:SetTextColor(r, g, b, 1)
            modelLabel:Show()
            if overlay then overlay:Show() end
        end
    end

    EllesmereUI._updateCharSheetDurability = UpdateDurabilityDisplay

    -- SkinCharacterSheet runs once (guarded), so these hooks install once.
    frame:HookScript("OnShow", UpdateDurabilityDisplay)
    frame:HookScript("OnHide", SyncDurabilityEvents)

    UpdateDurabilityDisplay()

    -- Button overlay for itemlevel tooltip
    local iLvlButton = CreateFrame("Button", nil, statsPanel)
    iLvlButton:SetPoint("TOPLEFT",     iLvlText, "TOPLEFT",     -10, 4)
    iLvlButton:SetPoint("BOTTOMRIGHT", iLvlText, "BOTTOMRIGHT", 10, -4)
    iLvlButton:SetFrameLevel(statsPanel:GetFrameLevel() + 3)
    iLvlButton:EnableMouse(true)
    iLvlButton:SetScript("OnEnter", function(self)
        local betterItems = GetBetterInventoryItems()

        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L("Equipped Item Level"), 0.6, 0.2, 1, 1)

        if #betterItems > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(
                string.format(L("You have %d better item%s in inventory"), #betterItems, #betterItems == 1 and "" or "s"),
                0.2, 1, 0.2
            )
            GameTooltip:AddLine(" ")

            -- Show up to 10 items with icons and slots (slot on right side)
            local maxShow = math.min(#betterItems, 10)
            for i = 1, maxShow do
                local item = betterItems[i]
                local leftText = string.format("|T%s:16|t  %s (iLvl %d)", item.icon, item.name, item.level)
                GameTooltip:AddDoubleLine(leftText, L(item.slot), 1, 1, 1, 0.7, 0.7, 0.7)
            end

            if #betterItems > 10 then
                GameTooltip:AddLine(
                    string.format(L("  ... and %d more"), #betterItems - 10),
                    0.7, 0.7, 0.7
                )
            end
        else
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L("No better items in inventory"), 0.7, 0.7, 0.7, true)
        end

        -- Calculate minimum width based on longest item text
        local maxWidth = 250
        if #betterItems > 0 then
            local maxShow = math.min(#betterItems, 10)
            for i = 1, maxShow do
                local item = betterItems[i]
                local text = string.format("%s (iLvl %d) - %s", item.name, item.level, L(item.slot))
                -- Rough estimate: ~6 pixels per character + icon space
                local estimatedWidth = #text * 6 + 30
                if estimatedWidth > maxWidth then
                    maxWidth = estimatedWidth
                end
            end
        end
        GameTooltip:SetMinimumWidth(maxWidth)
        GameTooltip:Show()
    end)
    iLvlButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local function UpdateItemLevelDisplay()
        local avgItemLevel, avgItemLevelEquipped, avgItemLevelPvP = GetAverageItemLevel()
        local avgFormatted = format("%.2f", avgItemLevel)
        local avgEquippedFormatted = format("%.2f", avgItemLevelEquipped)

        -- Show "/ max" only when a spec-usable upgrade sits in bags and max != equipped
        -- (equal is redundant; with no usable upgrade, max reflects unequipable items).
        local betterItemsNow = GetBetterInventoryItems()
        if avgEquippedFormatted ~= avgFormatted and #betterItemsNow > 0 then
            iLvlText:SetText(format("%s / %s", avgEquippedFormatted, avgFormatted))
        else
            iLvlText:SetText(avgEquippedFormatted)
        end

        local isCharTab = PaperDollFrame and PaperDollFrame:IsShown()
        local showPvP = EllesmereUIDB and EllesmereUIDB.showPvpItemLevel
        local pvpVisible = false
        if showPvP and avgItemLevelPvP and avgItemLevelPvP > 0 and GetFFD(frame).pvpIlvlText then
            GetFFD(frame).pvpIlvlText:SetText(format("PvP iLvl: |cff00cc66%d|r", math.floor(avgItemLevelPvP)))
            GetFFD(frame).pvpIlvlText:SetShown(isCharTab)
            pvpVisible = isCharTab
        elseif GetFFD(frame).pvpIlvlText then
            GetFFD(frame).pvpIlvlText:Hide()
        end

        -- Re-anchor M+ Score: below PvP ilvl when visible, below iLvl when not
        if GetFFD(frame).mythicRatingLabel then
            GetFFD(frame).mythicRatingLabel:ClearAllPoints()
            local anchor = pvpVisible and pvpIlvlText or iLvlText
            GetFFD(frame).mythicRatingLabel:SetPoint("TOP", anchor, "BOTTOM", 0, -4)
        end

        -- M+ Score if enabled. PaperDollFrame:IsShown() is the truth-source for the
        -- active sub-pane (selectedTab is unreliable on the initial open path).
        if EllesmereUIDB and EllesmereUIDB.showMythicRating and GetFFD(frame).mythicRatingLabel then
            local mythicRating = C_ChallengeMode.GetOverallDungeonScore()
            if mythicRating and mythicRating > 0 then
                local score = math.floor(mythicRating)
                local hex = GetMPScoreHex(score)
                GetFFD(frame).mythicRatingLabel:SetText(L("M+ Score:") .. string.format(" |cff%s%d|r", hex, score))
                GetFFD(frame).mythicRatingLabel:SetShown(isCharTab)
            else
                GetFFD(frame).mythicRatingLabel:Hide()
            end
        elseif GetFFD(frame).mythicRatingLabel then
            GetFFD(frame).mythicRatingLabel:Hide()
        end

        if EllesmereUI._updateCharSheetDurability then
            EllesmereUI._updateCharSheetDurability()
        end
    end

    -- Event-driven refresh of the stats panel (ilvl + M+ score); zero cost when idle: inventory/spec/challenge-mode changes and one pass on panel open.
    local iLvlUpdateFrame = CreateFrame("Frame")
    iLvlUpdateFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    iLvlUpdateFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
    iLvlUpdateFrame:RegisterEvent("BAG_UPDATE")
    iLvlUpdateFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    iLvlUpdateFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    iLvlUpdateFrame:RegisterEvent("PLAYER_AVG_ITEM_LEVEL_UPDATE")
    -- GetItemInfo returns nil for uncached bag items; without this event such an
    -- item drops out of the better-items scan permanently (nothing else re-dirties it).
    iLvlUpdateFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    local _betterItemsRefreshTimer
    local function QueueBetterItemsRefresh()
        if _betterItemsRefreshTimer then
            _betterItemsRefreshTimer:Cancel()
            _betterItemsRefreshTimer = nil
        end
        _betterItemsRefreshTimer = C_Timer.NewTimer(0.12, function()
            _betterItemsRefreshTimer = nil
            if not (frame and frame:IsShown()) then return end
            _betterDirty = true
            UpdateItemLevelDisplay()
        end)
    end
    iLvlUpdateFrame:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_INVENTORY_CHANGED" and unit ~= "player" then return end
        if event == "GET_ITEM_INFO_RECEIVED" then
            -- Gate on sheet-open BEFORE queueing: this event storms during normal play,
            -- and the cancel-and-recreate timer would still allocate every call while closed.
            if frame and frame:IsShown() then
                QueueBetterItemsRefresh()
            end
            return
        end
        if not (frame and frame:IsShown()) then return end
        _betterDirty = true
        UpdateItemLevelDisplay()
    end)
    frame:HookScript("OnShow", function()
        _betterDirty = true
        UpdateItemLevelDisplay()
    end)
    UpdateItemLevelDisplay()

    -- Store callback for option changes (M+ rating and PvP ilvl)
    EllesmereUI._updateMythicRatingDisplay = function()
        UpdateItemLevelDisplay()
        if EllesmereUI._updateScrollHeaderOffset then
            EllesmereUI._updateScrollHeaderOffset()
        end
    end
    EllesmereUI._updatePvpIlvlDisplay = EllesmereUI._updateMythicRatingDisplay

    -- Scroll frame starts below button+iLvl+M+ header, fills to bottom-right (right
    -- padding clears scrollbar). HEADER_H = button(25)+iLvl(18)+M+(12)+gaps(~14).
    local HEADER_H = 75
    local scrollFrame = CreateFrame("ScrollFrame", "EUI_CharSheet_ScrollFrame", statsPanel)
    scrollFrame:SetPoint("TOPLEFT", statsPanel, "TOPLEFT", 0, -HEADER_H)
    scrollFrame:SetPoint("BOTTOMRIGHT", statsPanel, "BOTTOMRIGHT", -12, 2)
    scrollFrame:SetFrameLevel(51)
    GetFFD(frame).scrollFrame = scrollFrame

    -- Scroll child: no anchors (the scroll frame positions it internally); width
    -- tracks the scroll frame whenever the panel resizes.
    local scrollChild = CreateFrame("Frame", "EUI_CharSheet_ScrollChild", scrollFrame)
    scrollChild:SetWidth(200)  -- temporary; resized by OnSizeChanged below
    scrollFrame:SetScrollChild(scrollChild)
    scrollFrame:HookScript("OnSizeChanged", function(self, w)
        if w and w > 0 then scrollChild:SetWidth(w) end
    end)
    -- Apply once in case OnSizeChanged doesn't fire before first paint.
    if scrollFrame:GetWidth() and scrollFrame:GetWidth() > 0 then
        scrollChild:SetWidth(scrollFrame:GetWidth())
    end

    -- Custom thin scrollbar pinned to owner's right edge; thumb responds to wheel +
    -- drag. Opts: trackOwner, topInset/bottomInset, rightInset. Returns the track.
    local function AttachCustomScrollbar(scrollFrame, scrollChild, opts)
        opts = opts or {}
        local trackOwner  = opts.trackOwner  or scrollFrame
        local rightInset  = opts.rightInset  or -2
        local topInset    = opts.topInset    or 0
        local bottomInset = opts.bottomInset or 0
        local SCROLLBAR_W, SCROLLBAR_ALPHA, SCROLL_STEP_PX, THUMB_MIN_H = 3, 0.2, 20, 20

        local track = CreateFrame("Frame", nil, trackOwner)
        track:SetWidth(SCROLLBAR_W)
        track:SetPoint("TOPRIGHT",    trackOwner, "TOPRIGHT",    rightInset, topInset)
        track:SetPoint("BOTTOMRIGHT", trackOwner, "BOTTOMRIGHT", rightInset, bottomInset)
        track:SetFrameLevel(scrollFrame:GetFrameLevel() + 2)
        track:Hide()

        local thumb = CreateFrame("Button", nil, track)
        thumb:SetWidth(SCROLLBAR_W)
        thumb:SetHeight(THUMB_MIN_H)
        thumb:EnableMouse(true)
        local thumbTex = thumb:CreateTexture(nil, "ARTWORK")
        thumbTex:SetColorTexture(1, 1, 1, SCROLLBAR_ALPHA)
        thumbTex:SetAllPoints()

        local function _info()
            local contentH = scrollChild:GetHeight() or 0
            local viewH    = scrollFrame:GetHeight() or 0
            return contentH, viewH, math.max(0, contentH - viewH)
        end

        local function UpdateThumb()
            local contentH, viewH, maxScroll = _info()
            if contentH <= 0 or viewH <= 0 or maxScroll <= 0 then
                track:Hide(); return
            end
            track:Show()
            local ext     = math.min(1, viewH / contentH)
            local pct     = math.max(0, math.min(1, scrollFrame:GetVerticalScroll() / maxScroll))
            local trackH  = track:GetHeight()
            local thumbH  = math.max(THUMB_MIN_H, trackH * ext)
            thumb:SetHeight(thumbH)
            local maxTravel = math.max(0, trackH - thumbH)
            thumb:ClearAllPoints()
            thumb:SetPoint("TOP", track, "TOP", 0, -(pct * maxTravel))
        end
        track._update = UpdateThumb

        scrollFrame:HookScript("OnVerticalScroll", UpdateThumb)
        scrollFrame:HookScript("OnSizeChanged",    UpdateThumb)
        scrollChild:HookScript("OnSizeChanged",    UpdateThumb)

        local function refreshVerticalScroll()
            local _, _, maxScroll = _info()
            -- Unconditional on maxScroll so it still clamps after a collapse disables scrolling.
            local newScroll = math.max(0, math.min(maxScroll, scrollFrame:GetVerticalScroll()))
            scrollFrame:SetVerticalScroll(newScroll)
        end
        track._refreshVerticalScroll = refreshVerticalScroll

        scrollFrame:EnableMouseWheel(true)
        scrollFrame:SetScript("OnMouseWheel", function(_, delta)
            local _, _, maxScroll = _info()
            if maxScroll <= 0 then return end
            local newScroll = math.max(0, math.min(maxScroll, scrollFrame:GetVerticalScroll() - delta * SCROLL_STEP_PX))
            scrollFrame:SetVerticalScroll(newScroll)
        end)

        -- Drag state + handler. OnUpdate installs only during an active drag (else
        -- every visible scrollbar would run it every frame, ~120 calls/sec idle).
        local drag = { active = false, startY = 0, startScroll = 0 }
        local function _dragThumbOnUpdate(self)
            if not drag.active then
                self:SetScript("OnUpdate", nil)
                return
            end
            if not IsMouseButtonDown("LeftButton") then
                drag.active = false
                self:SetScript("OnUpdate", nil)
                return
            end
            local _, _, maxScroll = _info()
            if maxScroll <= 0 then return end
            local _, y = GetCursorPosition()
            y = y / UIParent:GetEffectiveScale()
            local dy = drag.startY - y
            local trackH    = track:GetHeight()
            local maxTravel = math.max(1, trackH - thumb:GetHeight())
            scrollFrame:SetVerticalScroll(
                math.max(0, math.min(maxScroll, drag.startScroll + (dy / maxTravel) * maxScroll)))
        end
        thumb:SetScript("OnMouseDown", function(self, button)
            if button ~= "LeftButton" then return end
            local _, y = GetCursorPosition()
            drag.active = true
            drag.startY = y / UIParent:GetEffectiveScale()
            drag.startScroll = scrollFrame:GetVerticalScroll()
            self:SetScript("OnUpdate", _dragThumbOnUpdate)
        end)
        thumb:SetScript("OnMouseUp", function(self, button)
            if button == "LeftButton" then
                drag.active = false
                self:SetScript("OnUpdate", nil)
            end
        end)
        thumb:HookScript("OnHide", function(self)
            drag.active = false
            self:SetScript("OnUpdate", nil)
        end)

        return track
    end

    -- Stats scrollbar
    local scrollTrack = AttachCustomScrollbar(scrollFrame, scrollChild, {
        trackOwner = statsPanel,
        topInset   = -HEADER_H,
    })
    GetFFD(frame).scrollBar              = scrollTrack
    GetFFD(frame).updateScrollThumb      = scrollTrack._update
    GetFFD(frame).refreshVerticalScroll  = scrollTrack._refreshVerticalScroll

    -- Re-anchor scroll frame/track top edge to PvP iLvl + M+ Score visibility;
    -- each hidden line collapses 16px so the stat sections start higher.
    EllesmereUI._updateScrollHeaderOffset = function()
        local showMP = EllesmereUIDB and EllesmereUIDB.showMythicRating
        if showMP and C_ChallengeMode and C_ChallengeMode.GetOverallDungeonScore then
            local score = C_ChallengeMode.GetOverallDungeonScore()
            if not score or score <= 0 then showMP = false end
        end
        local showPvP = EllesmereUIDB and EllesmereUIDB.showPvpItemLevel
        if showPvP and GetAverageItemLevel then
            local _, _, pvp = GetAverageItemLevel()
            if not pvp or pvp <= 0 then showPvP = false end
        end
        -- HEADER_H includes M+'s line; each hidden line collapses 16px, each extra adds 16px.
        local h = HEADER_H
        if not showMP then h = h - 16 end
        if showPvP then h = h + 16 end
        local showDurHeader = EllesmereUIDB and EllesmereUIDB.showCharSheetDurability
            and ((EllesmereUIDB.charSheetDurabilityLocation or "model") == "header")
        if showDurHeader then h = h + 16 end
        scrollFrame:ClearAllPoints()
        scrollFrame:SetPoint("TOPLEFT",     statsPanel, "TOPLEFT",     0,  -h)
        scrollFrame:SetPoint("BOTTOMRIGHT", statsPanel, "BOTTOMRIGHT", -12, 2)
        scrollTrack:ClearAllPoints()
        scrollTrack:SetPoint("TOPRIGHT",    statsPanel, "TOPRIGHT",    -2, -h)
        scrollTrack:SetPoint("BOTTOMRIGHT", statsPanel, "BOTTOMRIGHT", -2,  0)
        if GetFFD(frame).updateScrollThumb then GetFFD(frame).updateScrollThumb() end
    end
    EllesmereUI._updateScrollHeaderOffset()

    local function GetCrestValue(currencyID)
        if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
            local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
            if info then
                return info.quantity or 0
            end
        end
        return 0
    end

    -- Crest maximum values (per season) -- season 2 Mistcrests. Fallback only:
    -- GetCrestMaxValue prefers the API's live seasonal max.
    local crestMaxValues = {
        [3446] = 400,  -- Myth
        [3445] = 400,  -- Hero
        [3444] = 700,  -- Champion
        [3443] = 700,  -- Veteran
        [3442] = 700,  -- Adventurer
    }

    -- Crest max: prefer the API's seasonal max, fall back to the table above.
    local function GetCrestMaxValue(currencyID)
        local currencyInfo = C_CurrencyInfo.GetCurrencyInfo(currencyID)
        if currencyInfo and currencyInfo.maxQuantity then
            return currencyInfo.maxQuantity
        end
        return crestMaxValues[currencyID] or 3000
    end

    local function ShouldShowStat(statShowWhen)
        if not statShowWhen then return true end  -- Show by default if no condition

        if statShowWhen == "brewmaster" then
            local specIndex = GetSpecialization()
            if specIndex then
                local specId = (GetSpecializationInfo(specIndex))
                return specId == 268  -- Brewmaster Monk
            end
            return false
        end

        return true
    end

    -- Per-crest visibility: each crest stat carries a showCrestKey, toggled
    -- individually from the options cog. Absent DB key means visible.
    local function ShouldShowCrest(stat)
        if not stat or not stat.showCrestKey then return true end
        return not (EllesmereUIDB
            and EllesmereUIDB["showCrest_" .. stat.showCrestKey] == false)
    end

    -- Opt-in stat rows: always created, visibility gated only, so toggles apply
    -- without /reload. Default hidden (DB flag must be explicitly true); showIf
    -- adds a live capability check on top of that choice.
    local function ShouldShowOptionalStat(stat)
        if not stat then return true end
        if stat.showKey and not (EllesmereUIDB and EllesmereUIDB[stat.showKey] == true) then
            return false
        end
        if stat.showIf and not stat.showIf() then return false end
        return true
    end

    -- Max mana pool. Reads 0 for classes with none (Warrior, Rogue, DK, DH), gating the Mana row -- the same check PaperDollFrame uses for alternate mana.
    local function PlayerMaxMana()
        return UnitPowerMax("player", Enum.PowerType.Mana) or 0
    end

    local function GetFilteredAttributeStats()
        local spec = GetSpecialization()
        local primaryStatIndex = 4  -- default Intellect

        if spec then
            -- Get primary stat directly from spec info (6th return value)
            local _, _, _, _, _, primaryStat = GetSpecializationInfo(spec)
            primaryStatIndex = primaryStat or 4
        end

        local primaryStatNames = { "Strength", "Agility", "Stamina", "Intellect" }
        local primaryStat = primaryStatNames[primaryStatIndex]

        -- Fixed order: Primary, Stamina, Health, Mana. Mana always stays in the list
        -- (row count must stay stable -- RefreshAttributeStats pairs rows to this
        -- list by index on a spec change); visibility is handled separately.
        return {
            { name = primaryStat, func = function() return UnitStat("player", primaryStatIndex) end, statIndex = primaryStatIndex, tooltip = (primaryStatIndex == 1 and L("Increases melee attack power")) or (primaryStatIndex == 2 and L("Increases dodge chance and melee attack power")) or (primaryStatIndex == 4 and L("Increase the magnitude of your attacks and Abilities")) or L("Primary stat") },
            { name = "Stamina", func = function() return UnitStat("player", 3) end, statIndex = 3, tooltip = L("Increases health") },
            { name = "Health", func = function() return UnitHealthMax("player") end, tooltip = L("The amount of damage you can take") },
            { name = "Mana", func = PlayerMaxMana, showKey = "showManaStat",
              showIf = function() return PlayerMaxMana() > 0 end,
              tooltip = L("The size of your mana pool") },
        }
    end

    -- Default category colors
    local DEFAULT_CATEGORY_COLORS = {
        Attributes = { r = 0.047, g = 0.824, b = 0.616 },
        ["Secondary Stats"] = { r = 0.471, g = 0.255, b = 0.784 },
        ["Tertiary Stats"] = { r = 0.859, g = 0.325, b = 0.855 },
        Attack = { r = 1, g = 0.353, b = 0.122 },
        Defense = { r = 0.247, g = 0.655, b = 1 },
        Crests = { r = 1, g = 0.784, b = 0.341 },
        PvP = { r = 0.671, g = 0.431, b = 0.349 },
    }

    local function GetCategoryColor(title)
        local custom = EllesmereUIDB and EllesmereUIDB.statCategoryColors and EllesmereUIDB.statCategoryColors[title]
        if custom then return custom end
        return DEFAULT_CATEGORY_COLORS[title] or { r = 1, g = 1, b = 1 }
    end

    local function GetStatSectionsOrder()
        local defaultOrder = {
            {
                title = "Attributes",
                colorKey = "Attributes",
                color = GetCategoryColor("Attributes"),
                stats = GetFilteredAttributeStats()
            },
            {
                title = "Secondary",
                colorKey = "Secondary Stats",
                settingKey = "SecondaryStats",
                color = GetCategoryColor("Secondary Stats"),
                stats = {
                    { name = "Critical Strike", func = function() return GetCritChance("player") or 0 end, format = "%.2f%%", rawFunc = function() return GetCombatRating(CR_CRIT_MELEE) or 0 end },
                    { name = "Haste", func = function() return UnitSpellHaste("player") or 0 end, format = "%.2f%%", rawFunc = function() return GetCombatRating(CR_HASTE_MELEE) or 0 end },
                    { name = "Mastery", func = function() return GetMasteryEffect() or 0 end, format = "%.2f%%", rawFunc = function() return GetCombatRating(CR_MASTERY) or 0 end },
                    { name = "Versatility", func = function()
                        local rating = GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE) or 0
                        local base = GetVersatilityBonus(CR_VERSATILITY_DAMAGE_DONE) or 0
                        if issecretvalue(rating) or issecretvalue(base) then return rating end
                        return rating + base
                    end, format = "%.2f%%", rawFunc = function() return GetCombatRating(CR_VERSATILITY_DAMAGE_DONE) or 0 end },
                }
            },
            {
                title = "Tertiary",
                colorKey = "Tertiary Stats",
                settingKey = "Tertiary",
                color = GetCategoryColor("Tertiary Stats"),
                stats = {
                    -- GetLifesteal/GetAvoidance/GetSpeed return TOTAL percent (incl.
                    -- talent/racial bonuses); GetCombatRatingBonus is rating-only and
                    -- misses e.g. Shadow Priest's +2% innate leech talent.
                    { name = "Leech",     func = function() return GetLifesteal() or 0 end, format = "%.2f%%", rawFunc = function() return GetCombatRating(CR_LIFESTEAL) or 0 end },
                    { name = "Avoidance", func = function() return GetAvoidance() or 0 end, format = "%.2f%%", rawFunc = function() return GetCombatRating(CR_AVOIDANCE) or 0 end },
                    { name = "Speed",     func = function() return GetSpeed()     or 0 end, format = "%.2f%%", rawFunc = function() return GetCombatRating(CR_SPEED)     or 0 end },
                }
            },
            {
                title = "Attack",
                colorKey = "Attack",
                color = GetCategoryColor("Attack"),
                stats = {
                    { name = "Spell Power", func = function() return GetSpellBonusDamage(7) end, tooltip = L("Increases the power of your spells and abilities") },
                    { name = "Attack Speed", func = function() return UnitAttackSpeed("player") or 0 end, format = "%.2f", tooltip = L("Attacks per second") },
                }
            },
            {
                title = "Defense",
                colorKey = "Defense",
                color = GetCategoryColor("Defense"),
                stats = {
                    { name = "Armor", func = function() local base, effectiveArmor = UnitArmor("player") return effectiveArmor end, tooltip = L("Reduces physical damage taken") },
                    { name = "Dodge", func = function() return GetDodgeChance() or 0 end, format = "%.2f%%", tooltip = L("Chance to avoid melee attacks") },
                    { name = "Parry", func = function() return GetParryChance() or 0 end, format = "%.2f%%", tooltip = L("Chance to deflect melee attacks") },
                    { name = "Block", func = function() return GetBlockChance() or 0 end, format = "%.2f%%", tooltip = L("Chance to block incoming attacks with a shield") },
                    { name = "Stagger Effect", func = function() return C_PaperDollInfo.GetStaggerPercentage("player") or 0 end, format = "%.2f%%", showWhen = "brewmaster", tooltip = L("Converts damage into a delayed effect") },
                }
            },
            {
                title = "Crests",
                colorKey = "Crests",
                color = GetCategoryColor("Crests"),
                stats = {
                    { name = "Myth", showCrestKey = "Myth", func = function() return GetCrestValue(3446) end, format = "%d", currencyID = 3446 },
                    { name = "Hero", showCrestKey = "Hero", func = function() return GetCrestValue(3445) end, format = "%d", currencyID = 3445 },
                    { name = "Champion", showCrestKey = "Champion", func = function() return GetCrestValue(3444) end, format = "%d", currencyID = 3444 },
                    { name = "Veteran", showCrestKey = "Veteran", func = function() return GetCrestValue(3443) end, format = "%d", currencyID = 3443 },
                    { name = "Adventurer", showCrestKey = "Adventurer", func = function() return GetCrestValue(3442) end, format = "%d", currencyID = 3442 },
                }
            },
            {
                title = "PvP",
                colorKey = "PvP",
                settingKey = "PvP",
                color = GetCategoryColor("PvP"),
                stats = {
                    {
                        name = "Honor Level",
                        format = "%s",
                        func = function()
                            return tostring(UnitHonorLevel and UnitHonorLevel("player") or 0)
                        end,
                    },
                    {
                        name = "Honor",
                        format = "%s",
                        func = function()
                            local cur = (UnitHonor and UnitHonor("player")) or 0
                            local max = (UnitHonorMax and UnitHonorMax("player")) or 0
                            return BreakUpLargeNumbers(cur) .. "/" .. BreakUpLargeNumbers(max)
                        end,
                    },
                    {
                        name = "Conquest",
                        format = "%d",
                        currencyID = 1602,
                        func = function()
                            if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
                                local info = C_CurrencyInfo.GetCurrencyInfo(1602)
                                return (info and info.quantity) or 0
                            end
                            return 0
                        end,
                    },
                }
            }
        }

        if EllesmereUIDB and EllesmereUIDB.statSectionsOrder then
            local orderedSections = {}
            for _, title in ipairs(EllesmereUIDB.statSectionsOrder) do
                for _, section in ipairs(defaultOrder) do
                    if section.title == title then
                        table.insert(orderedSections, section)
                        break
                    end
                end
            end
            return #orderedSections == #defaultOrder and orderedSections or defaultOrder
        end
        return defaultOrder
    end

    local statSections = GetStatSectionsOrder()

    GetFFD(frame).statsPanel = statsPanel
    GetFFD(frame).statsValues = {}  -- Will be filled as sections are created
    GetFFD(frame).statsSections = {}  -- Store sections for collapse/expand
    GetFFD(frame).lastSpec = GetSpecialization()  -- Track current spec

    -- Rebuild the Attributes rows when the spec changed.
    local function RefreshAttributeStats()
        local currentSpec = GetSpecialization()
        if currentSpec == GetFFD(frame).lastSpec then return end

        GetFFD(frame).lastSpec = currentSpec

        for sectionIdx, sectionData in ipairs(GetFFD(frame).statsSections) do
            if sectionData.sectionTitle == "Attributes" then
                local newStats = GetFilteredAttributeStats()

                local labelIndex = 0
                for _, stat in ipairs(sectionData.stats) do
                    if stat.label then
                        labelIndex = labelIndex + 1

                        if newStats[labelIndex] then
                            -- Shown state respects the section's collapsed flag: a spec switch
                            -- refreshes row data while collapsed but must not force it visible.
                            stat.label:SetText(L(newStats[labelIndex].name))
                            stat.label:SetShown(not sectionData.isCollapsed)

                            if stat.value then
                                for _, statsValueEntry in ipairs(GetFFD(frame).statsValues) do
                                    if statsValueEntry.value == stat.value then
                                        statsValueEntry.func = newStats[labelIndex].func
                                        statsValueEntry.format = newStats[labelIndex].format or "%d"
                                        local newValue = newStats[labelIndex].func()
                                        if newValue ~= nil then
                                            local fmt = statsValueEntry.format
                                            if fmt:find("%%") then
                                                stat.value:SetText(format(fmt, newValue))
                                            else
                                                stat.value:SetText(format(fmt, newValue))
                                            end
                                        end
                                        break
                                    end
                                end
                                stat.value:SetShown(not sectionData.isCollapsed)
                            end
                        else
                            stat.label:Hide()
                            if stat.value then stat.value:Hide() end
                        end
                    elseif stat.divider then
                        -- Show dividers only between visible stats, and only when the section isn't collapsed.
                        stat.divider:SetShown(not sectionData.isCollapsed and labelIndex < #newStats)
                    end
                end

                GetFFD(frame).recalculateSections()
                break
            end
        end
    end

    -- Refresh row visibility against the showWhen / crest / opt-in filters.
    local function RefreshStatsVisibility()
        local currentSpec = GetSpecialization()

        for _, sectionData in ipairs(GetFFD(frame).statsSections) do
            -- Collapsed sections keep all rows hidden regardless of per-stat filters (collapse/expand owns visibility).
            if not sectionData.isCollapsed then
                local visibleCount = 0
                for si = 1, #sectionData.stats do
                    local stat = sectionData.stats[si]
                    if stat.label and (stat.showWhen or stat.showCrestKey or stat.showKey) then
                        local shouldShow = ShouldShowStat(stat.showWhen)
                                       and ShouldShowCrest(stat)
                                       and ShouldShowOptionalStat(stat)
                        stat.label:SetShown(shouldShow)
                        if stat.value then stat.value:SetShown(shouldShow) end
                        if stat.button then stat.button:SetShown(shouldShow) end
                        -- Hide/show the divider that follows this stat
                        local nextEntry = sectionData.stats[si + 1]
                        if nextEntry and nextEntry.divider then
                            nextEntry.divider:SetShown(shouldShow)
                        end
                        if shouldShow then visibleCount = visibleCount + 1 end
                    elseif stat.label then
                        visibleCount = visibleCount + 1
                    end
                end
                -- Recalculate section height based on visible stats
                sectionData.height = 22 + (visibleCount * 16)
            end
        end
        GetFFD(frame).recalculateSections()
        -- A row just re-shown was skipped by the last UpdateAllStats pass, so its value
        -- is stale/unset; repopulate here (toggle/spec/collapse paths only, never the
        -- event path). Guarded since the build calls this before UpdateAllStats is
        -- published, but the build's own pass covers that case.
        if EllesmereUI._refreshStatFormats then EllesmereUI._refreshStatFormats() end
    end
    EllesmereUI._refreshStatsVisibility = RefreshStatsVisibility

    -- Event-driven primary-stat + stat-visibility refresh. Fires only on spec
    -- / talent / gear / combat-rating changes and once on panel open.
    local specUpdateFrame = CreateFrame("Frame")
    local _SPEC_EVENTS = {
        "PLAYER_SPECIALIZATION_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED",
        "PLAYER_EQUIPMENT_CHANGED", "UNIT_STATS", "COMBAT_RATING_UPDATE",
    }
    specUpdateFrame:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_STATS" and unit ~= "player" then return end
        RefreshAttributeStats()
        RefreshStatsVisibility()
    end)
    -- Same dynamic-registration trick as statsEventFrame above.
    frame:HookScript("OnShow", function()
        for _, ev in ipairs(_SPEC_EVENTS) do specUpdateFrame:RegisterEvent(ev) end
    end)
    frame:HookScript("OnHide", function()
        specUpdateFrame:UnregisterAllEvents()
    end)
    frame:HookScript("OnShow", function()
        RefreshAttributeStats()
        RefreshStatsVisibility()
        if EllesmereUI._updateStatCategoryVisibility then
            EllesmereUI._updateStatCategoryVisibility()
        end
        -- Deferred re-layout: scroll child bounds may not be finalized on the OnShow
        -- frame, causing sections to stack on first open.
        C_Timer.After(0, function()
            RefreshStatsVisibility()
            if EllesmereUI._updateStatCategoryVisibility then
                EllesmereUI._updateStatCategoryVisibility()
            end
        end)
    end)

    -- Show/hide whole stat categories per their DB setting.
    local function UpdateStatCategoryVisibility()
        if not GetFFD(frame).statsSections or #GetFFD(frame).statsSections == 0 then return end

        for _, sectionData in ipairs(GetFFD(frame).statsSections) do
            local settingKey = "showStatCategory_" .. (sectionData.settingKey or sectionData.sectionTitle:gsub(" ", ""))
            local shouldShow = not (EllesmereUIDB and EllesmereUIDB[settingKey] == false)

            if shouldShow then
                sectionData.container:Show()
            else
                sectionData.container:Hide()
                sectionData.container:ClearAllPoints()
                sectionData.container:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 10000)
            end
        end
        GetFFD(frame).recalculateSections()
    end
    EllesmereUI._updateStatCategoryVisibility = UpdateStatCategoryVisibility

    local function RecalculateSectionPositions()
        -- Collect visible sections so first/last are known once hidden ones are out
        local visible = {}
        for _, sectionData in ipairs(GetFFD(frame).statsSections) do
            if sectionData.container:IsShown() then
                visible[#visible + 1] = sectionData
            end
        end

        local yOffset = 0
        for idx, sectionData in ipairs(visible) do
            local sectionHeight = sectionData.isCollapsed and 16 or sectionData.height
            sectionData.container:ClearAllPoints()
            sectionData.container:SetPoint("TOPLEFT",  scrollChild, "TOPLEFT",  0, yOffset)
            sectionData.container:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, yOffset)
            sectionData.container:SetHeight(sectionHeight)
            yOffset = yOffset - sectionHeight - 6

            -- Gray out first-up and last-down; restore hover scripts on enabled arrows
            local upBtn, downBtn = sectionData.upBtn, sectionData.downBtn
            local alpha = sectionData._arrowAlpha or 0.35
            local hover = sectionData._arrowHover or 1
            if upBtn then
                if idx == 1 then
                    upBtn:SetAlpha(0.25)
                    upBtn:SetScript("OnEnter", nil)
                    upBtn:SetScript("OnLeave", nil)
                    upBtn:EnableMouse(false)
                else
                    upBtn:SetAlpha(alpha)
                    upBtn:EnableMouse(true)
                    upBtn:SetScript("OnEnter", function(self) self:SetAlpha(hover) end)
                    upBtn:SetScript("OnLeave", function(self) self:SetAlpha(alpha) end)
                end
            end
            if downBtn then
                if idx == #visible then
                    downBtn:SetAlpha(0.25)
                    downBtn:SetScript("OnEnter", nil)
                    downBtn:SetScript("OnLeave", nil)
                    downBtn:EnableMouse(false)
                else
                    downBtn:SetAlpha(alpha)
                    downBtn:EnableMouse(true)
                    downBtn:SetScript("OnEnter", function(self) self:SetAlpha(hover) end)
                    downBtn:SetScript("OnLeave", function(self) self:SetAlpha(alpha) end)
                end
            end
        end
        scrollChild:SetHeight(-yOffset)
        if GetFFD(frame).refreshVerticalScroll then GetFFD(frame).refreshVerticalScroll() end
    end
    GetFFD(frame).recalculateSections = RecalculateSectionPositions

    -- Create sections in scroll child
    local yOffset = 0
    for sectionIdx, section in ipairs(statSections) do
        local sectionContainer = CreateFrame("Frame", nil, scrollChild)
        sectionContainer:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
        sectionContainer:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, yOffset)
        sectionContainer:SetWidth(260)

        -- Title + bar container spans the full section width so the left bar starts
        -- flush with stat labels and the right bar ends flush with stat values.
        local titleContainer = CreateFrame("Button", nil, sectionContainer)
        titleContainer:SetPoint("TOPLEFT",  sectionContainer, "TOPLEFT",  0, 0)
        titleContainer:SetPoint("TOPRIGHT", sectionContainer, "TOPRIGHT", 0, 0)
        titleContainer:SetHeight(16)
        titleContainer:RegisterForClicks("LeftButtonUp")

        local sectionTitle = titleContainer:CreateFontString(nil, "OVERLAY")
        sectionTitle:SetFont(fontPath, 11, "")
        sectionTitle:SetTextColor(section.color.r, section.color.g, section.color.b, 1)
        sectionTitle:SetPoint("CENTER", titleContainer, "CENTER", 0, 0)
        sectionTitle:SetText(L(section.title))

        -- Physical-pixel-perfect 1px dividers, same technique as PP.CreateBorder:
        -- disable engine snap, height = one physical pixel in effective-scale units.
        local PP_SEC = EllesmereUI and EllesmereUI.PanelPP
        local PP_CORE = EllesmereUI and EllesmereUI.PP
        local function _snapSecLine(tex)
            if PP_SEC and PP_SEC.DisablePixelSnap then PP_SEC.DisablePixelSnap(tex) end
            local perfect = (PP_CORE and PP_CORE.perfect) or (PP_SEC and PP_SEC.mult) or 1
            local es = titleContainer.GetEffectiveScale and titleContainer:GetEffectiveScale() or 1
            local onePixel = (es and es > 0) and (perfect / es) or (PP_SEC and PP_SEC.mult) or 1
            tex:SetHeight(onePixel)
        end

        local leftBar = titleContainer:CreateTexture(nil, "ARTWORK")
        leftBar:SetColorTexture(section.color.r, section.color.g, section.color.b, 0.8)
        leftBar:SetPoint("LEFT", titleContainer, "LEFT", 0, 0)
        leftBar:SetPoint("RIGHT", sectionTitle, "LEFT", -6, 0)
        _snapSecLine(leftBar)

        local rightBar = titleContainer:CreateTexture(nil, "ARTWORK")
        rightBar:SetColorTexture(section.color.r, section.color.g, section.color.b, 0.8)
        rightBar:SetPoint("LEFT", sectionTitle, "RIGHT", 6, 0)
        rightBar:SetPoint("RIGHT", titleContainer, "RIGHT", 0, 0)
        _snapSecLine(rightBar)

        -- Re-snap once after layout settles: GetEffectiveScale needs final parent
        -- positions, not ready on first build.
        titleContainer._barResnap = { leftBar, rightBar }
        local _ticks = 0
        titleContainer:SetScript("OnUpdate", function(self)
            _ticks = _ticks + 1
            _snapSecLine(leftBar)
            _snapSecLine(rightBar)
            if _ticks >= 2 then self:SetScript("OnUpdate", nil) end
        end)

        local statYOffset = -22

        -- Section data for collapse/expand. Collapsed state persists across sessions
        -- in EllesmereUIDB.charSheetCollapsedSections, keyed by settingKey.
        local _collapseKey = section.settingKey or section.title:gsub(" ", "")
        local _savedCollapsed = false
        if EllesmereUIDB and EllesmereUIDB.charSheetCollapsedSections then
            _savedCollapsed = EllesmereUIDB.charSheetCollapsedSections[_collapseKey] == true
        end
        local sectionData = {
            title = titleContainer,
            container = sectionContainer,
            stats = {},
            isCollapsed = _savedCollapsed,
            height = 0,
            sectionTitle = section.title,  -- display name (used for reordering)
            -- Stable SavedVariables key; falls back to the title, spaces stripped.
            settingKey  = section.settingKey or section.title:gsub(" ", ""),
            colorKey = section.colorKey or section.title,  -- DB key for custom color
            titleFS = sectionTitle,
            leftBar = leftBar,
            rightBar = rightBar,
        }
        table.insert(GetFFD(frame).statsSections, sectionData)

        -- Stats in section
        for statIdx, stat in ipairs(section.stats) do
            if ShouldShowStat(stat.showWhen) and ShouldShowCrest(stat) then
                local label = sectionContainer:CreateFontString(nil, "OVERLAY")
                label:SetFont(fontPath, 10, "")
                label:SetTextColor(0.7, 0.7, 0.7, 0.8)
                label:SetPoint("TOPLEFT", sectionContainer, "TOPLEFT", 0, statYOffset)
                label:SetText(L(stat.name))

                local value = sectionContainer:CreateFontString(nil, "OVERLAY")
                value:SetFont(fontPath, 10, "")
                value:SetTextColor(section.color.r, section.color.g, section.color.b, 1)
                value:SetPoint("TOPRIGHT", sectionContainer, "TOPRIGHT", 0, statYOffset)
                value:SetJustifyH("RIGHT")
                value:SetText("0")

                -- Tooltip overlay button spanning the full row width (label edge to
                -- value edge) so hovering anywhere on the line fires it.
                local valueButton = CreateFrame("Button", nil, sectionContainer)
                valueButton:SetPoint("TOPLEFT", sectionContainer, "TOPLEFT", 0, statYOffset)
                valueButton:SetPoint("TOPRIGHT", sectionContainer, "TOPRIGHT", 0, statYOffset)
                valueButton:SetHeight(16)
                valueButton:EnableMouse(true)

                valueButton:SetScript("OnEnter", function()
                    local specIndex = GetSpecialization and GetSpecialization()
                    local role = specIndex and GetSpecializationRole(specIndex) or nil

                    local statValue = stat.func()
                    if issecretvalue(statValue) then return end
                    GameTooltip:SetOwner(valueButton, "ANCHOR_RIGHT")

                    -- Read the title's CURRENT color (section.color is build-time and
                    -- stays stale until /reload; the title FontString is live-updated
                    -- by EllesmereUI._refreshCharacterSheetColors) so a swatch change matches instantly.
                    local scR, scG, scB = sectionTitle:GetTextColor()

                    local displayValue = statValue
                    if stat.format then
                        displayValue = string.format(stat.format, statValue)
                    else
                        displayValue = tostring(statValue)
                    end

                    local titleLine = L(stat.name) .. " " .. displayValue

                    -- Currency (Crests)
                    if stat.currencyID then
                        local currencyInfo = C_CurrencyInfo.GetCurrencyInfo(stat.currencyID)
                        if currencyInfo then
                            local earned = currencyInfo.totalEarned or 0
                            local maximum = currencyInfo.maxQuantity or 0
                            GameTooltip:AddLine(L(stat.name) .. L(" Crests"), scR, scG, scB, 1)
                            GameTooltip:AddLine(string.format("%d / %d", earned, maximum), 1, 1, 1, true)
                        end
                    -- Secondary stats with raw rating
                    elseif stat.rawFunc then
                        local percentValue = stat.func()
                        local rawValue = stat.rawFunc()
                        GameTooltip:AddLine(
                            string.format(L("%s %.2f%% (%d rating)"), L(stat.name), percentValue, rawValue),
                            scR, scG, scB, true  -- category color (live)
                        )
                        local description = ""
                        if stat.name == "Critical Strike" then
                            description = string.format(L("Increases your chance to critically hit by %.2f%%."), percentValue)
                        elseif stat.name == "Haste" then
                            description = string.format(L("Increases attack and casting speed by %.2f%%."), percentValue)
                        elseif stat.name == "Mastery" then
                            -- Pull the spec's real mastery spell description instead of a generic line.
                            if specIndex and GetSpecializationMasterySpells and C_Spell and C_Spell.GetSpellDescription then
                                local masterySpell, masterySpell2 = GetSpecializationMasterySpells(specIndex)
                                if masterySpell then
                                    description = C_Spell.GetSpellDescription(masterySpell) or ""
                                    if masterySpell2 then
                                        local d2 = C_Spell.GetSpellDescription(masterySpell2)
                                        if d2 and d2 ~= "" then
                                            description = description .. "\n" .. d2
                                        end
                                    end
                                end
                            end
                            if description == "" then
                                description = string.format(L("Increases the effectiveness of your Mastery by %.2f%%."), percentValue)
                            end
                        elseif stat.name == "Versatility" then
                            description = string.format(L("Increases damage and healing done by %.2f%% and reduces damage taken by %.2f%%."), percentValue, percentValue / 2)
                        elseif stat.name == "Leech" then
                            description = string.format(L("Heals for %.2f%% of damage and healing done."), percentValue)
                        elseif stat.name == "Avoidance" then
                            description = string.format(L("Reduces damage taken from area attacks by %.2f%%."), percentValue)
                        elseif stat.name == "Speed" then
                            description = string.format(L("Increases movement speed by %.2f%%."), percentValue)
                        end
                        GameTooltip:AddLine(description, 1, 1, 1, true)

                        if stat.name == "Critical Strike" and GetCritChanceProvidesParryEffect() then
                            local critToParry = GetCombatRatingBonusForCombatRatingValue(CR_PARRY, GetCombatRating(CR_CRIT_MELEE))
                            GameTooltip:AddLine(" ")
                            GameTooltip:AddLine(string.format(L("Increases parry chance by %.2f%%."), critToParry), 1, 1, 1, true)
                        end

                        -- Diminishing returns breakdown (opt-in via Stat Display)
                        if EllesmereUIDB and EllesmereUIDB.showAdjustedStats
                           and not issecretvalue(rawValue) and EllesmereUI.GetStatDR then
                            local adjusted, wasted, penalty, nextPenalty, nextThreshold =
                                EllesmereUI.GetStatDR(stat.name, rawValue)
                            if adjusted then
                                GameTooltip:AddLine(" ")
                                GameTooltip:AddLine(string.format(L("Adjusted Rating: %s"),
                                    BreakUpLargeNumbers(math.floor(adjusted + 0.5))),
                                    scR, scG, scB, true)
                                GameTooltip:AddLine(string.format(L("Wasted Rating: %s"),
                                    BreakUpLargeNumbers(math.floor(wasted + 0.5))),
                                    scR, scG, scB, true)
                                GameTooltip:AddLine(string.format(L("Penalty Percentage: %d%%"), penalty),
                                    scR, scG, scB, true)
                                if nextThreshold then
                                    local nextRating = math.floor(nextThreshold + 0.5)
                                    local needed = nextRating - math.floor(rawValue + 0.5)
                                    if needed < 0 then needed = 0 end
                                    GameTooltip:AddLine(string.format(L("Next %d%% Penalty At: %s (+%s)"),
                                        nextPenalty, BreakUpLargeNumbers(nextRating),
                                        BreakUpLargeNumbers(needed)),
                                        scR, scG, scB, true)
                                end
                            end
                        end
                    -- Attributes
                    elseif stat.statIndex then
                        local base, _, posBuff, negBuff = UnitStat("player", stat.statIndex)
                        -- base from UnitStat is wrong, so calculate it like the default UI does
                        base = base - posBuff - negBuff
                        local statLabel = stat.name

                        -- Map to Blizzard global names
                        if stat.name == "Strength" then
                            statLabel = STAT_STRENGTH or L("Strength")
                        elseif stat.name == "Agility" then
                            statLabel = STAT_AGILITY or L("Agility")
                        elseif stat.name == "Intellect" then
                            statLabel = STAT_INTELLECT or L("Intellect")
                        elseif stat.name == "Stamina" then
                            statLabel = STAT_STAMINA or L("Stamina")
                        end

                        local bonus = (posBuff or 0) + (negBuff or 0)
                        local statLine = statLabel .. " " .. statValue
                        if bonus ~= 0 then
                            statLine = statLine .. " (" .. base .. (bonus > 0 and "+" or "") .. bonus .. ")"
                        end
                        GameTooltip:AddLine(statLine, scR, scG, scB, true)
                        GameTooltip:AddLine(L(stat.tooltip), 1, 1, 1, true)

                        -- Tanks: extra line for Strength (parry) / Agility (dodge).
                        if role == "TANK" then
                            if stat.name == "Strength" then
                                if GetParryChanceFromAttribute then
                                    local parryFromStr = GetParryChanceFromAttribute()

                                    if parryFromStr and parryFromStr > 0 then
                                        GameTooltip:AddLine(" ")
                                        GameTooltip:AddLine(string.format(L("Increases parry chance by %.2f%%."), parryFromStr), 1, 1, 1, true)
                                        GameTooltip:AddLine(L("|cff888888(Before diminishing returns)|r"), 1, 1, 1, true)
                                    end
                                end
                            elseif stat.name == "Agility" then
                                if GetDodgeChanceFromAttribute then
                                    local dodgeChanceStr = GetDodgeChanceFromAttribute()

                                    if dodgeChanceStr and dodgeChanceStr > 0 then
                                        GameTooltip:AddLine(" ")
                                        GameTooltip:AddLine(string.format(L("Increases dodge chance by %.2f%%."), dodgeChanceStr), 1, 1, 1, true)
                                        GameTooltip:AddLine(L("|cff888888(Before diminishing returns)|r"), 1, 1, 1, true)
                                    end
                                end
                            end
                        end
                    -- Generic stats (Attack, Defense, etc.)
                    else
                        GameTooltip:AddLine(titleLine, scR, scG, scB, true)
                        if stat.tooltip then
                            GameTooltip:AddLine(L(stat.tooltip), 1, 1, 1, true)
                        end

                        if stat.name == "Armor" then
                            local _, effectiveArmor = UnitArmor("player")
                            local armorReduction = 0

                            -- Reduction against an evenly matched enemy
                            if C_PaperDollInfo and C_PaperDollInfo.GetArmorEffectiveness then
                                armorReduction = (C_PaperDollInfo.GetArmorEffectiveness(effectiveArmor, UnitLevel("player")) or 0) * 100
                            end
                            if armorReduction > 0 then
                                GameTooltip:AddLine(" ")
                                GameTooltip:AddLine(string.format(L("Physical damage reduction: %.2f%%"), armorReduction), 1, 1, 1, true)
                                GameTooltip:AddLine(L("|cff888888(Against an evenly matched enemy)|r"), 1, 1, 1, true)
                            end

                            -- Reduction against target: return can be SECRET when target combat
                            -- data is secret; issecretvalue-guard before any compare (comparing throws).
                            if C_PaperDollInfo and C_PaperDollInfo.GetArmorEffectivenessAgainstTarget then
                                local targetEff = C_PaperDollInfo.GetArmorEffectivenessAgainstTarget(effectiveArmor)
                                if targetEff and not issecretvalue(targetEff) and targetEff > 0 then
                                    GameTooltip:AddLine(string.format(L("(Against Current Target: %.2f%%)"), targetEff * 100), 1, 1, 1, true)
                                end
                            end
                        elseif stat.name == "Block" then
                            local shieldBlockArmor = GetShieldBlock();
                            local armorReduction = 0

                            -- Reduction against an evenly matched enemy
                            if C_PaperDollInfo and C_PaperDollInfo.GetArmorEffectiveness then
                                armorReduction = (C_PaperDollInfo.GetArmorEffectiveness(shieldBlockArmor, UnitLevel("player")) or 0) * 100
                            end
                            if armorReduction > 0 then
                                GameTooltip:AddLine(" ")
                                GameTooltip:AddLine(string.format(L("Physical damage reduction: %.2f%%"), armorReduction), 1, 1, 1, true)
                                GameTooltip:AddLine(L("|cff888888(Against an evenly matched enemy)|r"), 1, 1, 1, true)
                            end

                            -- Reduction against target; same SECRET guard as Armor.
                            if C_PaperDollInfo and C_PaperDollInfo.GetArmorEffectivenessAgainstTarget then
                                local targetEff = C_PaperDollInfo.GetArmorEffectivenessAgainstTarget(shieldBlockArmor)
                                if targetEff and not issecretvalue(targetEff) and targetEff > 0 then
                                    GameTooltip:AddLine(string.format(L("(Against Current Target: %.2f%%)"), targetEff * 100), 1, 1, 1, true)
                                end
                            end
                        end
                    end

                    GameTooltip:Show()
                end)

                valueButton:SetScript("OnLeave", function()
                    GameTooltip:Hide()
                end)

                table.insert(GetFFD(frame).statsValues, {
                    value = value,
                    func = stat.func,
                    rawFunc = stat.rawFunc,
                    format = stat.format or "%d",
                    categoryKey = section.settingKey,
                })

                -- Store for collapse/expand (showWhen etc kept for later visibility checks)
                table.insert(sectionData.stats, {label = label, value = value, button = valueButton, showWhen = stat.showWhen, showCrestKey = stat.showCrestKey, showKey = stat.showKey, showIf = stat.showIf})

                -- Thin leader between label and value, vertically centered on
                -- the row and physical-pixel-perfect.
                do
                    local divider = sectionContainer:CreateTexture(nil, "OVERLAY")
                    divider:SetColorTexture(1, 1, 1, 0.06)
                    local PP = EllesmereUI and EllesmereUI.PP
                    if PP then
                        if PP.DisablePixelSnap then PP.DisablePixelSnap(divider) end
                        divider:SetHeight(PP.mult or 1)
                    else
                        divider:SetHeight(1)
                    end
                    divider:SetPoint("LEFT",  label, "RIGHT",  10, 0)
                    divider:SetPoint("RIGHT", value, "LEFT",  -10, 0)
                    table.insert(sectionData.stats, {divider = divider})
                end

                statYOffset = statYOffset - 16
            end
        end

        sectionData.height = -statYOffset

        local function _applyCollapsedState()
            for _, stat in ipairs(sectionData.stats) do
                if sectionData.isCollapsed then
                    if stat.label then stat.label:Hide() end
                    if stat.value then stat.value:Hide() end
                    if stat.button then stat.button:Hide() end
                    if stat.divider then stat.divider:Hide() end
                else
                    if stat.label then stat.label:Show() end
                    if stat.value then stat.value:Show() end
                    if stat.button then stat.button:Show() end
                    if stat.divider then stat.divider:Show() end
                end
            end
        end

        -- Restore saved collapsed state immediately (before first layout).
        if sectionData.isCollapsed then
            _applyCollapsedState()
        end

        titleContainer:SetScript("OnClick", function()
            sectionData.isCollapsed = not sectionData.isCollapsed
            _applyCollapsedState()
            -- Expand above shows every row unconditionally, including ones showWhen/
            -- showCrestKey correctly hid (e.g. Brewmaster's Stagger Effect); re-apply
            -- the real filter here (also recalculates layout, no separate call needed).
            RefreshStatsVisibility()

            -- Persist across sessions.
            if EllesmereUIDB then
                EllesmereUIDB.charSheetCollapsedSections = EllesmereUIDB.charSheetCollapsedSections or {}
                EllesmereUIDB.charSheetCollapsedSections[_collapseKey] = sectionData.isCollapsed or nil
            end
        end)

        -- Up/Down reorder arrows: up on LEFT edge, down on RIGHT, dividers between
        -- arrows and centered label. Always visible; first-up/last-down grayed + click-inert.
        do
            local arrowSize = 12
            local MEDIA = "Interface\\AddOns\\EllesmereUI\\media\\"
            local DIV_ICON_ALPHA = 1
            local DIV_ICON_HOVER = 1

            local function SaveOrder()
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.statSectionsOrder = {}
                for _, sec in ipairs(GetFFD(frame).statsSections) do
                    table.insert(EllesmereUIDB.statSectionsOrder, sec.sectionTitle)
                end
            end

            local upBtn = CreateFrame("Button", nil, titleContainer)
            upBtn:SetSize(arrowSize, arrowSize)
            upBtn:SetPoint("LEFT", titleContainer, "LEFT", 0, 0)
            upBtn:SetFrameLevel(titleContainer:GetFrameLevel() + 2)
            local upIcon = upBtn:CreateTexture(nil, "OVERLAY")
            upIcon:SetAllPoints()
            upIcon:SetTexture(MEDIA .. "icons\\eui-arrow-up3.png")
            upIcon:SetVertexColor(section.color.r, section.color.g, section.color.b, 1)
            upBtn:SetAlpha(DIV_ICON_ALPHA)

            local downBtn = CreateFrame("Button", nil, titleContainer)
            downBtn:SetSize(arrowSize, arrowSize)
            downBtn:SetPoint("RIGHT", titleContainer, "RIGHT", 0, 0)
            downBtn:SetFrameLevel(titleContainer:GetFrameLevel() + 2)
            local downIcon = downBtn:CreateTexture(nil, "OVERLAY")
            downIcon:SetAllPoints()
            downIcon:SetTexture(MEDIA .. "icons\\eui-arrow-down3.png")
            downIcon:SetVertexColor(section.color.r, section.color.g, section.color.b, 1)
            downBtn:SetAlpha(DIV_ICON_ALPHA)

            -- Anchor the divider lines to hug the arrows
            leftBar:ClearAllPoints()
            leftBar:SetPoint("LEFT",  upBtn,        "RIGHT", 6, 0)
            leftBar:SetPoint("RIGHT", sectionTitle, "LEFT", -6, 0)
            rightBar:ClearAllPoints()
            rightBar:SetPoint("LEFT",  sectionTitle, "RIGHT", 6, 0)
            rightBar:SetPoint("RIGHT", downBtn,      "LEFT", -6, 0)

            upBtn:SetScript("OnClick", function()
                for i, sec in ipairs(GetFFD(frame).statsSections) do
                    if sec == sectionData and i > 1 then
                        GetFFD(frame).statsSections[i], GetFFD(frame).statsSections[i - 1] =
                            GetFFD(frame).statsSections[i - 1], GetFFD(frame).statsSections[i]
                        SaveOrder()
                        GetFFD(frame).recalculateSections()
                        return
                    end
                end
            end)
            downBtn:SetScript("OnClick", function()
                for i, sec in ipairs(GetFFD(frame).statsSections) do
                    if sec == sectionData and i < #GetFFD(frame).statsSections then
                        GetFFD(frame).statsSections[i], GetFFD(frame).statsSections[i + 1] =
                            GetFFD(frame).statsSections[i + 1], GetFFD(frame).statsSections[i]
                        SaveOrder()
                        GetFFD(frame).recalculateSections()
                        return
                    end
                end
            end)

            -- Stored so RecalculateSectionPositions can gray out boundary arrows
            sectionData.upBtn   = upBtn
            sectionData.downBtn = downBtn
            sectionData.upIcon  = upIcon
            sectionData.downIcon = downIcon
            sectionData._arrowAlpha = DIV_ICON_ALPHA
            sectionData._arrowHover = DIV_ICON_HOVER
        end

        sectionContainer:SetHeight(sectionData.height)
        yOffset = yOffset - sectionData.height - 6
    end

    scrollChild:SetHeight(-yOffset)

    if not (EllesmereUIDB and EllesmereUIDB.statSectionsOrder) then
        if not EllesmereUIDB then EllesmereUIDB = {} end
        EllesmereUIDB.statSectionsOrder = {}
        for _, sec in ipairs(GetFFD(frame).statsSections) do
            table.insert(EllesmereUIDB.statSectionsOrder, sec.sectionTitle)
        end
    end

    -- Initial visibility. RefreshStatsVisibility also settles opt-in rows (Mana,
    -- built unconditionally so toggles apply without /reload) before first OnShow.
    RefreshStatsVisibility()
    UpdateStatCategoryVisibility()
    -- Deferred pass: some settings (e.g. section visibility) may not be initialized yet.
    C_Timer.After(0, function()
        RefreshStatsVisibility()
        UpdateStatCategoryVisibility()
    end)

    -- Repaint every stat row.
    local function UpdateAllStats()
        local secondaryRaw  = EllesmereUIDB and EllesmereUIDB.showSecondaryRaw
        local tertiaryRaw   = EllesmereUIDB and EllesmereUIDB.showTertiaryRaw
        local secondaryBoth = EllesmereUIDB and EllesmereUIDB.showSecondaryBoth
        local tertiaryBoth  = EllesmereUIDB and EllesmereUIDB.showTertiaryBoth
        for _, statEntry in ipairs(GetFFD(frame).statsValues) do
            -- Filtered-off rows stay in the list but off-screen; querying/formatting
            -- them wastes cycles on a path firing many times/sec. Test the row's OWN
            -- shown flag, not IsVisible() (false during the pre-panel-up build pass,
            -- which would leave every row reading "0" until the next event -- RefreshStatsVisibility repopulates).
            if statEntry.value and statEntry.value:IsShown() then
                local isSec = (statEntry.categoryKey == "SecondaryStats")
                local isTer = (statEntry.categoryKey == "Tertiary")
                local useBoth = statEntry.rawFunc and ((isSec and secondaryBoth) or (isTer and tertiaryBoth))
                local useRaw  = (not useBoth) and ((isSec and secondaryRaw) or (isTer and tertiaryRaw))
                if useBoth then
                    local rawResult = statEntry.rawFunc()
                    local pctResult = statEntry.func and statEntry.func()
                    if rawResult ~= nil and pctResult ~= nil then
                        statEntry.value:SetText(format("%d (%.2f%%)", rawResult, pctResult))
                    else
                        statEntry.value:SetText("0")
                    end
                else
                    local fn  = (useRaw and statEntry.rawFunc) or statEntry.func
                    local fmt = useRaw and "%d" or statEntry.format
                    local result = fn and fn()
                    if result ~= nil then
                        statEntry.value:SetText(format(fmt, result))
                    else
                        statEntry.value:SetText("0")
                    end
                end
            end
        end
    end
    EllesmereUI._refreshStatFormats = UpdateAllStats

    UpdateAllStats()

    -- Event-driven stat refresh: every stat the sheet displays updates on one of these events. Never poll this from an OnUpdate.
    local statsEventFrame = CreateFrame("Frame")
    local _STATS_EVENTS = {
        "UNIT_STATS", "COMBAT_RATING_UPDATE", "PLAYER_EQUIPMENT_CHANGED",
        "UNIT_ATTACK_POWER", "UNIT_RANGED_ATTACK_POWER", "UNIT_SPELL_HASTE",
        "UNIT_MAXPOWER",
        "MASTERY_UPDATE", "SPELL_POWER_CHANGED", "PLAYER_DAMAGE_DONE_MODS",
        "PLAYER_SPECIALIZATION_CHANGED",
        "HONOR_XP_UPDATE", "HONOR_LEVEL_UPDATE", "CURRENCY_DISPLAY_UPDATE",
    }
    statsEventFrame:SetScript("OnEvent", function(_, _, unit)
        if unit and unit ~= "player" then return end
        if (frame.selectedTab or 1) == 1 then
            UpdateAllStats()
        end
    end)
    -- Register only while the sheet is open: UNIT_STATS/COMBAT_RATING_UPDATE fire many times a second in combat, and dispatch alone is a measurable idle cost.
    frame:HookScript("OnShow", function()
        for _, ev in ipairs(_STATS_EVENTS) do statsEventFrame:RegisterEvent(ev) end
    end)
    frame:HookScript("OnHide", function()
        statsEventFrame:UnregisterAllEvents()
    end)
    -- Refresh once on open, in case no event fired since the last close.
    frame:HookScript("OnShow", function()
        if frame and (frame.selectedTab or 1) == 1 then
            UpdateAllStats()
        end
    end)

    -- Rarity-colored border on a slot, replacing Blizzard's icon chrome.
    local function ApplyCustomSlotBorder(slotName)
        local slot = _G[slotName]
        if not slot then return end

        if slot.IconBorder then
            slot.IconBorder:Hide()
        end

        if slot.IconOverlay then
            slot.IconOverlay:Hide()
        end
        if slot.IconOverlay2 then
            slot.IconOverlay2:Hide()
        end

        if slot.icon then
            local z = (EllesmereUIDB and EllesmereUIDB.charSheetIconZoom) or 0.07
            slot.icon:SetTexCoord(z, 1 - z, z, 1 - z)
        end

        local normalTexture = _G[slotName .. "NormalTexture"]
        if normalTexture then
            normalTexture:Hide()
        end

        local itemLink = GetInventoryItemLink("player", slot:GetID())
        local borderR, borderG, borderB = 0.4, 0.4, 0.4  -- Default dark gray
        if itemLink then
            local _, _, rarity = GetItemInfo(itemLink)
            if rarity then
                borderR, borderG, borderB = C_Item.GetItemQualityColor(rarity)
            end
        end

        -- Add border directly on the slot with item color (2px thickness)
        if EllesmereUI and EllesmereUI.PanelPP then
            EllesmereUI.PanelPP.CreateBorder(slot, borderR, borderG, borderB, 1, 2, "OVERLAY", 1)
            local bdrFrame = EllesmereUI.PanelPP.GetBorders(slot)
            if bdrFrame then bdrFrame:SetFrameLevel(slot:GetFrameLevel()) end
        end
    end

    -- Apply custom rarity borders to all item slots
    local itemSlots = {
        "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot",
        "CharacterChestSlot", "CharacterWaistSlot", "CharacterLegsSlot",
        "CharacterFeetSlot", "CharacterWristSlot", "CharacterHandsSlot",
        "CharacterFinger0Slot", "CharacterFinger1Slot",
        "CharacterTrinket0Slot", "CharacterTrinket1Slot",
        "CharacterBackSlot", "CharacterMainHandSlot", "CharacterSecondaryHandSlot",
        "CharacterShirtSlot", "CharacterTabardSlot"
    }

    GetFFD(frame).themedSlots = itemSlots

    -- Create custom buttons for right side (Character, Titles, Equipment Manager)
    local buttonWidth = 64
    local buttonHeight = 25
    local buttonSpacing = -6
    -- Center buttons in right column (right column is ~268px wide starting at x=420)
    local totalButtonWidth = (buttonWidth * 3) + (buttonSpacing * 2)
    local rightColumnWidth = 268
    local startX = 425 + (rightColumnWidth - totalButtonWidth) / 2
    local startY = -60  -- Position near bottom of frame, but within bounds

    local topButtonRegistry = {}
    local function _paintTopButton(btn)
        local text = btn._text
        if not text then return end
        if btn._active then
            local EG = EllesmereUI.ELLESMERE_GREEN or { r = 0.51, g = 0.784, b = 1 }
            text:SetTextColor(EG.r, EG.g, EG.b, 1)
        elseif btn._hover then
            text:SetTextColor(1, 1, 1, 1)
        else
            text:SetTextColor(1, 1, 1, 0.6)
        end
    end
    local function SetActiveTopButton(activeBtn)
        for _, b in ipairs(topButtonRegistry) do
            b._active = (b == activeBtn)
            _paintTopButton(b)
        end
    end
    if EllesmereUI and EllesmereUI.RegAccent then
        EllesmereUI.RegAccent({ type = "callback", fn = function()
            for _, b in ipairs(topButtonRegistry) do _paintTopButton(b) end
        end })
    end

    local function CreateEUIButton(name, label, onClick)
        -- Plain Button, NOT SecureActionButtonTemplate: these tabs only need insecure
        -- OnClick, and the secure template flags Show/Hide/SetShown on them as a
        -- protected call when dispatched from Blizzard's secure ShowSubFrame stack.
        local btn = CreateFrame("Button", "EUI_CharSheet_" .. name, frame)
        btn:SetSize(buttonWidth, buttonHeight)
        btn:SetPoint("TOPLEFT", frame, "TOPLEFT", startX, startY)

        local text = btn:CreateFontString(nil, "OVERLAY")
        text:SetFont(fontPath, 10, "")
        -- Anchor TOP (not CENTER) so the text sits flush with the top of the panel
        -- section instead of floating ~12px down inside a tall button.
        text:SetPoint("TOP", btn, "TOP", 0, 0)
        text:SetText(label)
        btn._text = text
        btn._active = false
        btn._hover = false
        _paintTopButton(btn)

        btn:SetScript("OnEnter", function() btn._hover = true; _paintTopButton(btn) end)
        btn:SetScript("OnLeave", function() btn._hover = false; _paintTopButton(btn) end)

        btn:SetScript("OnClick", function(self, ...)
            SetActiveTopButton(btn)
            if onClick then onClick(self, ...) end
        end)

        table.insert(topButtonRegistry, btn)
        return btn
    end

    local characterBtn = CreateEUIButton("Stats", L("Character"), function() end)

    -- Re-highlights the Character top-button; called by ApplyTabVisibility when
    -- the bottom tab swaps Rep/Currency -> Character.
    GetFFD(frame).reactivateCharTab = function()
        if SetActiveTopButton and characterBtn then
            SetActiveTopButton(characterBtn)
        end
    end

    -- Create Titles Panel (same position and size as stats panel)
    local titlesPanel = CreateFrame("Frame", "EUI_CharSheet_TitlesPanel", frame)
    titlesPanel:SetWidth(190)
    titlesPanel:SetPoint("TOPLEFT", statsPanel, "TOPLEFT", 0, 0)
    titlesPanel:SetPoint("BOTTOMLEFT", statsPanel, "BOTTOMLEFT", 0, 0)
    titlesPanel:SetFrameLevel(50)
    titlesPanel:Hide()
    GetFFD(frame).titlesPanel = titlesPanel

    -- Titles panel has no backdrop of its own; it uses the shared statsBg.

    local titlesSearchBox = CreateFrame("EditBox", "EUI_CharSheet_TitlesSearchBox", titlesPanel)
    titlesSearchBox:SetSize(180, 24)
    titlesSearchBox:SetPoint("TOPLEFT", titlesPanel, "TOPLEFT", 0, -30)
    titlesSearchBox:SetAutoFocus(false)
    titlesSearchBox:SetMaxLetters(20)

    local searchBg = titlesSearchBox:CreateTexture(nil, "BACKGROUND")
    searchBg:SetColorTexture(0, 0, 0, 0.5)
    searchBg:SetAllPoints()

    titlesSearchBox:SetTextColor(1, 1, 1, 1)
    titlesSearchBox:SetFont(fontPath, 10, "")
    titlesSearchBox:SetTextInsets(4, 4, 0, 0)

    local hintText = titlesSearchBox:CreateFontString(nil, "OVERLAY")
    hintText:SetFont(fontPath, 10, "")
    hintText:SetText(L("Search titles..."))
    hintText:SetTextColor(0.6, 0.6, 0.6, 0.7)
    hintText:SetPoint("LEFT", titlesSearchBox, "LEFT", 4, 0)

    -- Clear "x" (visible only when the search box has text). Invisible click
    -- target sits on top of the glyph so it can be clicked to clear.
    local clearX = titlesSearchBox:CreateFontString(nil, "OVERLAY")
    clearX:SetFont(fontPath, 11, "")
    clearX:SetText("x")
    clearX:SetTextColor(0.7, 0.7, 0.7, 1)
    clearX:SetPoint("RIGHT", titlesSearchBox, "RIGHT", -4, 0)
    clearX:Hide()

    local clearHit = CreateFrame("Button", nil, titlesSearchBox)
    clearHit:SetSize(14, 14)
    clearHit:SetPoint("CENTER", clearX, "CENTER", 0, 0)
    clearHit:Hide()
    clearHit:SetScript("OnClick", function()
        titlesSearchBox:SetText("")
        titlesSearchBox:ClearFocus()
    end)


    local titlesScrollFrame = CreateFrame("ScrollFrame", "EUI_CharSheet_TitlesScrollFrame", titlesPanel)
    titlesScrollFrame:SetPoint("TOPLEFT", titlesPanel, "TOPLEFT", 0, -65)
    titlesScrollFrame:SetPoint("BOTTOMRIGHT", titlesPanel, "BOTTOMRIGHT", 0, 0)
    titlesScrollFrame:EnableMouseWheel(true)

    local titlesScrollChild = CreateFrame("Frame", "EUI_CharSheet_TitlesScrollChild", titlesScrollFrame)
    titlesScrollChild:SetWidth(180)
    titlesScrollFrame:SetScrollChild(titlesScrollChild)

    -- Custom scrollbar (same shape as the stats scrollbar).
    AttachCustomScrollbar(titlesScrollFrame, titlesScrollChild, {
        trackOwner = titlesPanel,
        topInset   = -65,   -- matches titlesScrollFrame's top anchor offset
    })

    local titleButtons = {}  -- Persistent button registry (hoisted so click handlers can repaint without rebuild)
    local selectedTitleIndex = nil

    -- Repaints only the previous + new selection (O(1) instead of O(n) over
    -- the full title list). Falls back to a full sweep when prev is unset.
    local function PaintTitleSelection(newIndex)
        local prev = selectedTitleIndex
        selectedTitleIndex = newIndex
        local EG = EllesmereUI.ELLESMERE_GREEN or { r = 0.51, g = 0.784, b = 1 }
        if prev ~= nil then
            local oldData = titleButtons[prev]
            if oldData and oldData.bg then
                oldData.bg:SetColorTexture(1, 1, 1, 0.04)
            end
            local newData = titleButtons[newIndex]
            if newData and newData.bg then
                newData.bg:SetColorTexture(EG.r, EG.g, EG.b, 0.5)
            end
        else
            for idx, btnData in pairs(titleButtons) do
                if idx == newIndex then
                    btnData.bg:SetColorTexture(EG.r, EG.g, EG.b, 0.5)
                else
                    btnData.bg:SetColorTexture(1, 1, 1, 0.04)
                end
            end
        end
    end

    -- Physical-pixel-snapped tile step: 24px tile + 2px gap, aligned to PP.mult
    local _PP_MULT   = (EllesmereUI and EllesmereUI.PanelPP and EllesmereUI.PanelPP.mult) or 1
    local TILES_TILE_H    = 24
    local TILES_TILE_GAP  = math.max(_PP_MULT, math.floor(2 / _PP_MULT + 0.5) * _PP_MULT)
    local TILES_TILE_STEP = TILES_TILE_H + TILES_TILE_GAP

    local _titlesBuilt = false
    local _titlesOrder = {}  -- cached alphabetical index order; rebuilt with the button list

    -- One-time factory: reusable button with once-bound scripts. Data travels via
    -- btn._titleIndex / btn._titleName, so scripts never close over per-title state.
    local function _createTitleButton(titleIndex)
        local btn = CreateFrame("Button", nil, titlesScrollChild)
        btn:SetWidth(180)
        btn:SetHeight(TILES_TILE_H)

        btn._bg = btn:CreateTexture(nil, "BACKGROUND")
        btn._bg:SetColorTexture(1, 1, 1, 0.05)
        btn._bg:SetAllPoints()

        btn._hover = btn:CreateTexture(nil, "ARTWORK")
        btn._hover:SetColorTexture(1, 1, 1, 0.1)
        btn._hover:SetAllPoints()
        btn._hover:Hide()

        btn._text = btn:CreateFontString(nil, "OVERLAY")
        btn._text:SetFont(fontPath, 11, "")
        btn._text:SetTextColor(1, 1, 1, 1)
        btn._text:SetPoint("LEFT", btn, "LEFT", 10, 0)

        btn._titleIndex = titleIndex
        btn:SetScript("OnEnter", function(self) self._hover:Show() end)
        btn:SetScript("OnLeave", function(self) self._hover:Hide() end)
        btn:SetScript("OnClick", function(self)
            SetCurrentTitle(self._titleIndex)
            PaintTitleSelection(self._titleIndex)
        end)
        return btn
    end

    -- Build every known title button ONCE. No rebuild on search keystrokes.
    local function BuildTitlesList()
        if _titlesBuilt then return end
        _titlesBuilt = true

        -- "No Title": titleId -1 clears the title (1+ are real titles). 0 is a
        -- silent no-op and leaves the server-saved title in place across logins.
        local noTitleBtn = _createTitleButton(-1)
        noTitleBtn._text:SetText(L("No Title"))
        titleButtons[-1] = { btn = noTitleBtn, bg = noTitleBtn._bg }

        for titleIndex = 1, GetNumTitles() do
            if IsTitleKnown(titleIndex) then
                local titleName = GetTitleName(titleIndex)
                if titleName then
                    local btn = _createTitleButton(titleIndex)
                    btn._titleName = titleName
                    btn._text:SetText(titleName)
                    titleButtons[titleIndex] = { btn = btn, bg = btn._bg }
                end
            end
        end

        -- Sort alphabetically, "No Title" (-1) pinned first. Title names carry a "%s"
        -- player-name placeholder (prefix/suffix) plus spaces; strip both so the sort
        -- key is the meaningful word ("%s the Kingslayer" -> "the kingslayer"). Computed once, never per keystroke.
        local function SortKey(idx)
            local name = titleButtons[idx].btn._titleName or ""
            name = name:gsub("%%s", " "):gsub("^%s+", ""):gsub("%s+$", "")
            return name:lower()
        end
        wipe(_titlesOrder)
        for idx in pairs(titleButtons) do _titlesOrder[#_titlesOrder + 1] = idx end
        table.sort(_titlesOrder, function(a, b)
            if a == -1 then return true end
            if b == -1 then return false end
            return SortKey(a) < SortKey(b)
        end)
    end

    -- Filter: show/hide + reposition visible buttons by current search text.
    local function FilterTitlesList()
        BuildTitlesList()

        local searchText = (titlesSearchBox:GetText() or ""):lower()
        local yOffset = 0

        for _, idx in ipairs(_titlesOrder) do
            local btnData = titleButtons[idx]
            local btn = btnData.btn
            local name = (idx == -1) and L("No Title") or (btn._titleName or "")
            local visible = (searchText == "")
                or (idx == -1)   -- keep "No Title" always visible
                or name:lower():find(searchText, 1, true)
            if visible then
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", titlesScrollChild, "TOPLEFT", 0, yOffset)
                btn:Show()
                yOffset = yOffset - TILES_TILE_STEP
            else
                btn:Hide()
            end
        end

        PaintTitleSelection(GetCurrentTitle())
        titlesScrollChild:SetHeight(-yOffset)
        titlesScrollFrame:SetVerticalScroll(0)
    end

    -- Alias: some call sites say RefreshTitlesList().
    local RefreshTitlesList = FilterTitlesList

    -- Learning a title invalidates the build cache so the next filter rebuilds;
    -- the event is rare enough that one full rebuild on that edge is fine.
    local _titlesInvalidator = CreateFrame("Frame")
    _titlesInvalidator:RegisterEvent("KNOWN_TITLES_UPDATE")
    _titlesInvalidator:SetScript("OnEvent", function()
        _titlesBuilt = false
        wipe(_titlesOrder)
        for idx, data in pairs(titleButtons) do
            if data.btn then data.btn:Hide() end
            titleButtons[idx] = nil
        end
    end)

    titlesSearchBox:SetScript("OnTextChanged", function(self)
        if (self:GetText() or "") ~= "" then
            clearX:Show(); clearHit:Show()
        else
            clearX:Hide(); clearHit:Hide()
        end
        RefreshTitlesList()
    end)

    titlesSearchBox:SetScript("OnEditFocusGained", function()
        if titlesSearchBox:GetText() == "" then
            hintText:Hide()
        end
    end)

    titlesSearchBox:SetScript("OnEditFocusLost", function()
        if titlesSearchBox:GetText() == "" then
            hintText:Show()
        end
    end)

    -- Escape clears focus (and is consumed -- do NOT propagate, that would
    -- send every typed character to action bar bindings too).
    titlesSearchBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    RefreshTitlesList()

    GetFFD(frame).titlesPanel:HookScript("OnShow", function()
        titlesSearchBox:SetText("")
        RefreshTitlesList()
    end)

    -- Character button switches back to the stats panel.
    characterBtn:SetScript("OnClick", function()
        SetActiveTopButton(characterBtn)
        if not statsPanel:IsShown() then
            statsPanel:SetShown(true)
            if GetFFD(CharacterFrame).titlesPanel then GetFFD(CharacterFrame).titlesPanel:SetShown(false) end
            if GetFFD(CharacterFrame).equipPanel  then GetFFD(CharacterFrame).equipPanel:SetShown(false)  end
            -- Deactivate equipment sidebar (hides flyout arrows).
            local sidebarTab = _G.PaperDollSidebarTab1
            if sidebarTab and sidebarTab.Click then pcall(sidebarTab.Click, sidebarTab) end
        end
    end)

    CreateEUIButton("Titles", L("Titles"), function()
        if not GetFFD(CharacterFrame).titlesPanel:IsShown() then
            GetFFD(CharacterFrame).titlesPanel:SetShown(true)
            statsPanel:SetShown(false)
            if GetFFD(CharacterFrame).equipPanel then GetFFD(CharacterFrame).equipPanel:SetShown(false) end
            -- Deactivate equipment sidebar (hides flyout arrows).
            local sidebarTab = _G.PaperDollSidebarTab1
            if sidebarTab and sidebarTab.Click then pcall(sidebarTab.Click, sidebarTab) end
        end
    end)

    -- Create Equipment Panel (same position and size as stats panel)
    local equipPanel = CreateFrame("Frame", "EUI_CharSheet_EquipPanel", frame)
    equipPanel:SetWidth(190)
    equipPanel:SetPoint("TOPLEFT", statsPanel, "TOPLEFT", 0, 0)
    equipPanel:SetPoint("BOTTOMLEFT", statsPanel, "BOTTOMLEFT", 0, 0)
    equipPanel:SetFrameLevel(50)
    equipPanel:Hide()
    GetFFD(frame).equipPanel = equipPanel

    -- Equipment panel has no backdrop of its own; it uses the shared statsBg.

    -- Scroll frame for equipment (flush-left to match the titles sidebar)
    local equipScrollFrame = CreateFrame("ScrollFrame", "EUI_CharSheet_EquipScrollFrame", equipPanel)
    equipScrollFrame:SetPoint("TOPLEFT",     equipPanel, "TOPLEFT",     0, -0)
    equipScrollFrame:SetPoint("BOTTOMRIGHT", equipPanel, "BOTTOMRIGHT", 0,  0)
    equipScrollFrame:EnableMouseWheel(true)

    local equipScrollChild = CreateFrame("Frame", "EUI_CharSheet_EquipScrollChild", equipScrollFrame)
    equipScrollChild:SetWidth(180)
    equipScrollFrame:SetScrollChild(equipScrollChild)

    equipScrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local currentScroll = equipScrollFrame:GetVerticalScroll()
        local maxScroll = math.max(0, equipScrollChild:GetHeight() - equipScrollFrame:GetHeight())
        local newScroll = currentScroll - delta * 20
        newScroll = math.max(0, math.min(newScroll, maxScroll))
        equipScrollFrame:SetVerticalScroll(newScroll)
    end)

    local selectedSetID = nil
    -- Persistent tile pool. Rebuilt once; reused across every refresh.
    local setTilePool = {}

    -- Forward declaration; defined after the buttons.
    local RefreshEquipmentSets

    -- ============================================================
    -- Equipment panel header: "Gear Sets" title with physical-pixel 1px dividers
    -- ============================================================
    local setsHeaderFrame = CreateFrame("Frame", nil, equipScrollChild)
    setsHeaderFrame:SetHeight(14)
    setsHeaderFrame:SetPoint("TOPLEFT",  equipScrollChild, "TOPLEFT",  5, -30)
    setsHeaderFrame:SetPoint("TOPRIGHT", equipScrollChild, "TOPRIGHT", -5, -30)

    local setsHeaderText = setsHeaderFrame:CreateFontString(nil, "OVERLAY")
    setsHeaderText:SetFont(fontPath, 11, "")
    setsHeaderText:SetText(L("Gear Sets"))
    setsHeaderText:SetTextColor(0.047, 0.824, 0.616, 1)
    setsHeaderText:SetPoint("CENTER", setsHeaderFrame, "CENTER", 0, 0)

    do
        local PP_ES = EllesmereUI and EllesmereUI.PanelPP
        local LINE_H = (PP_ES and PP_ES.mult) or 1

        local leftLine = setsHeaderFrame:CreateTexture(nil, "ARTWORK")
        leftLine:SetColorTexture(0.047, 0.824, 0.616, 0.8)
        if PP_ES and PP_ES.DisablePixelSnap then PP_ES.DisablePixelSnap(leftLine) end
        leftLine:SetHeight(LINE_H)
        leftLine:SetPoint("LEFT",  setsHeaderFrame, "LEFT", 0, 0)
        leftLine:SetPoint("RIGHT", setsHeaderText,  "LEFT", -6, 0)

        local rightLine = setsHeaderFrame:CreateTexture(nil, "ARTWORK")
        rightLine:SetColorTexture(0.047, 0.824, 0.616, 0.8)
        if PP_ES and PP_ES.DisablePixelSnap then PP_ES.DisablePixelSnap(rightLine) end
        rightLine:SetHeight(LINE_H)
        rightLine:SetPoint("LEFT",  setsHeaderText,  "RIGHT", 6, 0)
        rightLine:SetPoint("RIGHT", setsHeaderFrame, "RIGHT", 0, 0)
    end

    -- ============================================================
    -- Text-link row (New Set | Equip | Save), placed below the header
    -- ============================================================
    local linksRow = CreateFrame("Frame", nil, equipScrollChild)
    linksRow:SetHeight(14)
    linksRow:SetPoint("TOPLEFT",  setsHeaderFrame, "BOTTOMLEFT",  0, -8)
    linksRow:SetPoint("TOPRIGHT", setsHeaderFrame, "BOTTOMRIGHT", 0, -8)

    local function MakeTextLink(parent, label, onClick)
        local btn = CreateFrame("Button", nil, parent)
        local fs = btn:CreateFontString(nil, "OVERLAY")
        fs:SetFont(fontPath, 10, "")
        fs:SetText(label)
        fs:SetTextColor(1, 1, 1, 0.7)
        fs:SetPoint("CENTER", btn, "CENTER", 0, 0)
        btn:SetSize((fs:GetStringWidth() or 30) + 8, 14)
        btn._fs = fs
        btn:SetScript("OnEnter", function() fs:SetTextColor(1, 1, 1, 1) end)
        btn:SetScript("OnLeave", function() fs:SetTextColor(1, 1, 1, 0.7) end)
        btn:SetScript("OnClick", onClick)
        return btn
    end

    local newSetBtn = MakeTextLink(linksRow, L("New"), function()
        if InCombatLockdown() then return end
        StaticPopupDialogs["EUI_NEW_EQUIPMENT_SET"] = {
            text = L("New equipment set name:"),
            button1 = L("Create"),
            button2 = L("Cancel"),
            OnAccept = function(dialog)
                local newName = dialog.EditBox:GetText()
                if newName ~= "" then
                    C_EquipmentSet.CreateEquipmentSet(newName)
                    RefreshEquipmentSets()
                end
            end,
            hasEditBox = true, editBoxWidth = 350, timeout = 0,
            whileDead = false, hideOnEscape = true,
        }
        StaticPopup_Show("EUI_NEW_EQUIPMENT_SET")
    end)

    local equipTopBtn, equipTopText
    equipTopBtn = MakeTextLink(linksRow, L("Equip"), function()
        if InCombatLockdown() then return end
        equipTopText:SetText(L("Equipped!"))
        equipTopText:SetTextColor(0.047, 0.824, 0.616, 1)
        if selectedSetID then
            EUI_EquipSet(selectedSetID)
            activeEquipmentSetID = selectedSetID
            if EllesmereUIDB then EllesmereUIDB.lastEquippedSet = selectedSetID end
            RefreshEquipmentSets()
        end
        C_Timer.After(1, function()
            if equipTopText then
                equipTopText:SetText(L("Equip"))
                equipTopText:SetTextColor(1, 1, 1, 0.7)
            end
        end)
    end)
    equipTopText = equipTopBtn._fs

    local saveTopBtn, saveTopText
    saveTopBtn = MakeTextLink(linksRow, L("Save"), function()
        if InCombatLockdown() then return end
        saveTopText:SetText(L("Saved!"))
        saveTopText:SetTextColor(0.047, 0.824, 0.616, 1)
        if selectedSetID then C_EquipmentSet.SaveEquipmentSet(selectedSetID) end
        C_Timer.After(1, function()
            if saveTopText then
                saveTopText:SetText(L("Save"))
                saveTopText:SetTextColor(1, 1, 1, 0.7)
            end
        end)
    end)
    saveTopText = saveTopBtn._fs

    -- Save has nothing to do while the SELECTED set is the one currently
    -- equipped (its saved contents already match) -- signal that at half
    -- opacity. Purely visual: the link stays clickable. Driven from both
    -- refresh paths so selection clicks AND gear swaps retrack it.
    local function UpdateSaveOpacity()
        local dim = false
        if selectedSetID then
            local _, _, _, isEquipped = C_EquipmentSet.GetEquipmentSetInfo(selectedSetID)
            dim = isEquipped == true
        end
        saveTopBtn:SetAlpha(dim and 0.5 or 1)
    end

    -- Evenly space the three text links across the row
    newSetBtn:ClearAllPoints()
    newSetBtn:SetPoint("LEFT", linksRow, "LEFT", 0, 0)
    equipTopBtn:ClearAllPoints()
    equipTopBtn:SetPoint("CENTER", linksRow, "CENTER", 0, 0)
    saveTopBtn:ClearAllPoints()
    saveTopBtn:SetPoint("RIGHT", linksRow, "RIGHT", 0, 0)

    -- A set is "complete" when every referenced item is on the character (equipped
    -- OR in bags/bank) -- deliberately not "all equipped" (that's "active"). numLost counts truly-absent items only.
    local function IsEquipmentSetComplete(setName)
        local setID = C_EquipmentSet.GetEquipmentSetID(setName)
        if not setID then return true end
        local _, _, _, _, _, _, _, numLost = C_EquipmentSet.GetEquipmentSetInfo(setID)
        return (numLost or 0) == 0
    end

    -- Returns only items that are truly missing -- not equipped AND not in
    -- bags or bank. Items sitting in bags are NOT reported.
    local function GetMissingSetItems(setName)
        local setID = C_EquipmentSet.GetEquipmentSetID(setName)
        if not setID then return {} end

        local setItems = C_EquipmentSet.GetItemIDs(setID)
        if not setItems then return {} end

        local missing = {}
        -- "Cloak" (not "Back") so this doesn't collide with the "Back" nav-button
        -- key elsewhere in the catalog; matches EUI_UpgradeCalc.lua's slotNames[15].
        local slotNames = {
            "Head", "Neck", "Shoulder", "Cloak",
            "Chest", "Waist", "Legs", "Feet",
            "Wrist", "Hands", "Finger 1", "Finger 2",
            "Trinket 1", "Trinket 2", "Main Hand", "Off Hand",
            "Tabard", "Chest (Relic)", "Back (Relic)"
        }

        for slot, setItemID in pairs(setItems) do
            if setItemID and setItemID ~= 0 then
                local equippedID = GetInventoryItemID("player", slot)
                if equippedID ~= setItemID then
                    -- Not equipped: check bags+bank+reagent bank via GetItemCount
                    -- (item, includeBank, reagentBank); bags always count.
                    local count = C_Item.GetItemCount(setItemID, true, true) or 0
                    if count == 0 then
                        local itemName = (C_Item.GetItemInfo and C_Item.GetItemInfo(setItemID))
                            or "Unknown Item"
                        table.insert(missing, {
                            slot = slotNames[slot] or "Unknown",
                            itemID = setItemID,
                            itemName = itemName,
                        })
                    end
                end
            end
        end

        return missing
    end

    -- Rebuild the equipment-set tiles.
    RefreshEquipmentSets = function()
        -- Physical-pixel-snapped tile step matching the titles sidebar
        local PP_EQ = EllesmereUI and EllesmereUI.PanelPP
        local PP_MULT_EQ = (PP_EQ and PP_EQ.mult) or 1
        local TILE_H = 24
        local TILE_GAP = math.max(PP_MULT_EQ, math.floor(2 / PP_MULT_EQ + 0.5) * PP_MULT_EQ)
        local TILE_STEP = TILE_H + TILE_GAP
        local EG_EQ = EllesmereUI.ELLESMERE_GREEN or { r = 0.51, g = 0.784, b = 1 }

        -- Gather sets; detect which one is currently equipped so we can
        -- pre-select it on first open.
        local equipmentSets = {}
        local setIDs = C_EquipmentSet.GetEquipmentSetIDs()
        if setIDs then
            for _, setID in ipairs(setIDs) do
                local setName, _, _, isEquipped = C_EquipmentSet.GetEquipmentSetInfo(setID)
                if setName and setName ~= "" then
                    table.insert(equipmentSets, { id = setID, name = setName })
                    if isEquipped then activeEquipmentSetID = setID end
                end
            end
        end

        if not selectedSetID and activeEquipmentSetID then
            selectedSetID = activeEquipmentSetID
        end

        -- Lazy-create a tile with all sub-frames + once-bound scripts. Data
        -- travels via fields on `tile`, so closures don't capture per-set state.
        local function _acquireTile(index)
            local tile = setTilePool[index]
            if tile then return tile end

            tile = CreateFrame("Button", nil, equipScrollChild)
            tile:SetWidth(170)
            tile:SetHeight(TILE_H)

            tile._bg = tile:CreateTexture(nil, "BACKGROUND")
            tile._bg:SetAllPoints()

            -- Selection highlight (accent, 40% alpha). Sits above bg, below
            -- hover so the hover brighten still lands over a selected tile.
            tile._selection = tile:CreateTexture(nil, "ARTWORK", nil, -1)
            tile._selection:SetAllPoints()
            tile._selection:Hide()

            tile._hover = tile:CreateTexture(nil, "ARTWORK")
            tile._hover:SetColorTexture(1, 1, 1, 0.15)
            tile._hover:SetAllPoints()
            tile._hover:Hide()

            tile._text = tile:CreateFontString(nil, "OVERLAY")
            tile._text:SetFont(fontPath, 10, "")
            tile._text:SetPoint("LEFT", tile, "LEFT", 10, 0)

            tile._specIcon = tile:CreateTexture(nil, "OVERLAY")
            tile._specIcon:SetSize(16, 16)
            tile._specIcon:SetPoint("RIGHT", tile, "RIGHT", -45, 0)
            tile._specIcon:Hide()

            -- Cogwheel
            local cog = CreateFrame("Button", nil, tile)
            cog:SetWidth(16); cog:SetHeight(16)
            cog:SetPoint("RIGHT", tile, "RIGHT", -5, 0)
            local cogTex = cog:CreateTexture(nil, "OVERLAY")
            cogTex:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\cogs-3.png")
            cogTex:SetVertexColor(1, 1, 1, 1)
            cogTex:SetAllPoints()
            cog:SetAlpha(0.75)
            cog:SetScript("OnEnter", function(self) self:SetAlpha(1) end)
            cog:SetScript("OnLeave", function(self) self:SetAlpha(0.75) end)
            cog:SetScript("OnClick", function(self)
                local sid = tile._setID
                if not sid then return end
                local items = {
                    { text = "Change Icon", onClick = function()
                        if InCombatLockdown() then return end
                        local pickSid   = tile._setID
                        local pickSname = tile._setName
                        if not (pickSid and pickSname) then return end
                        StaticPopupDialogs["EUI_EQUIP_SET_ICON"] = {
                            text = "Icon file ID for '" .. pickSname .. "':",
                            button1 = "Set", button2 = "Cancel",
                            hasEditBox = true, editBoxWidth = 200,
                            timeout = 0, whileDead = false, hideOnEscape = true,
                            OnShow = function(dialog)
                                local eb = dialog.EditBox or dialog.editBox
                                if eb then
                                    local _, curIcon = C_EquipmentSet.GetEquipmentSetInfo(pickSid)
                                    eb:SetText(tostring(curIcon or ""))
                                    eb:HighlightText()
                                end
                            end,
                            OnAccept = function(dialog)
                                local eb = dialog.EditBox or dialog.editBox
                                local iconID = tonumber(eb and eb:GetText() or "")
                                if iconID then
                                    C_EquipmentSet.ModifyEquipmentSet(pickSid, pickSname, iconID)
                                    RefreshEquipmentSets()
                                end
                            end,
                        }
                        StaticPopup_Show("EUI_EQUIP_SET_ICON")
                    end },
                    { text = "Unassigned", onClick = function()
                        if InCombatLockdown() then return end
                        C_EquipmentSet.UnassignEquipmentSetSpec(sid)
                        RefreshEquipmentSets()
                    end },
                }
                for i = 1, GetNumSpecializations() do
                    local id, specName = GetSpecializationInfo(i)
                    if id then
                        local specIdx = i
                        items[#items + 1] = { text = specName, onClick = function()
                            if InCombatLockdown() then return end
                            C_EquipmentSet.AssignSpecToEquipmentSet(sid, specIdx)
                            RefreshEquipmentSets()
                        end }
                    end
                end
                if EllesmereUI and EllesmereUI.ShowContextMenu then
                    EllesmereUI.ShowContextMenu(self, items)
                end
            end)
            tile._cog = cog

            -- Delete X
            local del = CreateFrame("Button", nil, tile)
            del:SetWidth(14); del:SetHeight(14)
            del:SetPoint("RIGHT", cog, "LEFT", -5, 0)
            local delTxt = del:CreateFontString(nil, "OVERLAY")
            -- 12pt "x" nudged up 1px; larger sizes overflow the 14x14 button and
            -- render as a giant X.
            delTxt:SetFont(fontPath, 12, "")
            delTxt:SetText("x")
            delTxt:SetTextColor(1, 1, 1, 0.8)
            delTxt:SetPoint("CENTER", del, "CENTER", 0, 1)
            del:SetScript("OnEnter", function() delTxt:SetTextColor(1, 0.2, 0.2, 1) end)
            del:SetScript("OnLeave", function() delTxt:SetTextColor(1, 1, 1, 0.8) end)
            del:SetScript("OnClick", function()
                local sid, sname = tile._setID, tile._setName
                if not (sid and sname) then return end
                StaticPopupDialogs["EUI_DELETE_EQUIPMENT_SET"] = {
                    text = string.format(L("Delete equipment set '%s'?"), sname),
                    button1 = L("Delete"), button2 = L("Cancel"),
                    OnAccept = function()
                        C_EquipmentSet.DeleteEquipmentSet(sid)
                        RefreshEquipmentSets()
                    end,
                    timeout = 0, whileDead = false, hideOnEscape = true,
                }
                StaticPopup_Show("EUI_DELETE_EQUIPMENT_SET")
            end)
            tile._del = del

            -- Drag-to-actionbar
            tile:RegisterForDrag("LeftButton")
            tile:SetScript("OnDragStart", function()
                if tile._setID and C_EquipmentSet.PickupEquipmentSet then
                    C_EquipmentSet.PickupEquipmentSet(tile._setID)
                end
            end)

            -- Single-click selects, double-click equips.
            tile._lastClick = 0
            tile:SetScript("OnClick", function()
                local sid = tile._setID
                if not sid then return end
                selectedSetID = sid
                local now = GetTime()
                if (now - (tile._lastClick or 0)) < 0.4 then
                    tile._lastClick = 0
                    if not InCombatLockdown() then
                        EUI_EquipSet(sid)
                        activeEquipmentSetID = sid
                        if EllesmereUIDB then EllesmereUIDB.lastEquippedSet = sid end
                    end
                else
                    tile._lastClick = now
                end
                RefreshEquipmentSets()
            end)

            tile:SetScript("OnEnter", function()
                tile._hover:Show()
                if not IsEquipmentSetComplete(tile._setName) then
                    local missing = GetMissingSetItems(tile._setName)
                    if #missing > 0 then
                        GameTooltip:SetOwner(tile, "ANCHOR_RIGHT")
                        GameTooltip:AddLine("Missing Items:", 1, 0.3, 0.3, 1)
                        for _, item in ipairs(missing) do
                            local icon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(item.itemID))
                                or (GetItemIcon and GetItemIcon(item.itemID))
                            local iconText = icon and string.format("|T%s:16|t", icon) or ""
                            GameTooltip:AddLine(
                                string.format("%s %s: %s", iconText, L(item.slot), item.itemName),
                                1, 1, 1, true)
                        end
                        GameTooltip:Show()
                    end
                end
            end)
            tile:SetScript("OnLeave", function()
                GameTooltip:Hide()
                tile._hover:Hide()
            end)

            -- Expose for the color monitor (expects _setText / _setName).
            tile._setText = tile._text

            setTilePool[index] = tile
            return tile
        end

        -- Configure existing tiles; reveal + position them.
        local yOffset = -70
        for i, setData in ipairs(equipmentSets) do
            local tile = _acquireTile(i)

            tile._setID   = setData.id
            tile._setName = setData.name

            tile._text:SetText(setData.name)
            if IsEquipmentSetComplete(setData.name) then
                tile._text:SetTextColor(1, 1, 1, 1)
            else
                tile._text:SetTextColor(1, 0.3, 0.3, 1)
            end

            -- Equipped set = 50% accent bg; selected set = 40% accent overlay.
            if activeEquipmentSetID == setData.id then
                tile._bg:SetColorTexture(EG_EQ.r, EG_EQ.g, EG_EQ.b, 0.5)
            else
                tile._bg:SetColorTexture(1, 1, 1, 0.05)
            end
            if tile._selection then
                if selectedSetID == setData.id then
                    tile._selection:SetColorTexture(EG_EQ.r, EG_EQ.g, EG_EQ.b, 0.15)
                    tile._selection:Show()
                else
                    tile._selection:Hide()
                end
            end

            -- Spec icon
            local assignedSpec = C_EquipmentSet.GetEquipmentSetAssignedSpec(setData.id)
            if assignedSpec then
                local _, _, _, specIcon = GetSpecializationInfo(assignedSpec)
                if specIcon then
                    tile._specIcon:SetTexture(specIcon)
                    tile._specIcon:Show()
                else
                    tile._specIcon:Hide()
                end
            else
                tile._specIcon:Hide()
            end

            tile:ClearAllPoints()
            tile:SetPoint("TOPLEFT", equipScrollChild, "TOPLEFT", 5, yOffset)
            tile:Show()
            yOffset = yOffset - TILE_STEP
        end

        -- Hide unused pooled tiles.
        for i = #equipmentSets + 1, #setTilePool do
            setTilePool[i]:Hide()
        end

        equipScrollChild:SetHeight(-yOffset)
        UpdateSaveOpacity()
    end

    -- Event-driven recolor of set tiles on gear/set-edit changes and panel open;
    -- re-detects the equipped set so the accent highlight tracks gear swaps without a full tile rebuild.
    local function RefreshEquipSetColors()
        if not (CharacterFrame and CharacterFrame:IsShown() and GetFFD(CharacterFrame).equipPanel and GetFFD(CharacterFrame).equipPanel:IsShown()) then
            return
        end
        local EG_EQ = EllesmereUI.ELLESMERE_GREEN or { r = 0.51, g = 0.784, b = 1 }
        local newActiveID = nil
        local setIDs = C_EquipmentSet.GetEquipmentSetIDs()
        if setIDs then
            for _, setID in ipairs(setIDs) do
                local _, _, _, isEquipped = C_EquipmentSet.GetEquipmentSetInfo(setID)
                if isEquipped then
                    newActiveID = setID
                    break
                end
            end
        end
        activeEquipmentSetID = newActiveID
        for _, tile in ipairs(setTilePool) do
            if tile:IsShown() and tile._setText and tile._setName then
                if IsEquipmentSetComplete(tile._setName) then
                    tile._setText:SetTextColor(1, 1, 1, 1)
                else
                    tile._setText:SetTextColor(1, 0.3, 0.3, 1)
                end
                if tile._bg then
                    if tile._setID and tile._setID == newActiveID then
                        tile._bg:SetColorTexture(EG_EQ.r, EG_EQ.g, EG_EQ.b, 0.5)
                    else
                        tile._bg:SetColorTexture(1, 1, 1, 0.05)
                    end
                end
                if tile._selection then
                    if tile._setID and tile._setID == selectedSetID then
                        tile._selection:SetColorTexture(EG_EQ.r, EG_EQ.g, EG_EQ.b, 0.1)
                        tile._selection:Show()
                    else
                        tile._selection:Hide()
                    end
                end
            end
        end
        UpdateSaveOpacity()
    end

    -- Debounced refresh: PLAYER_EQUIPMENT_CHANGED (fires per slot), EQUIPMENT_SETS_CHANGED
    -- and EQUIPMENT_SWAP_FINISHED coalesce into one refresh on the next frame.
    local _refreshPending     = false
    local _colorRefreshPending = false
    local function QueueFullRefresh()
        if _refreshPending then return end
        _refreshPending = true
        C_Timer.After(0.01, function()
            _refreshPending = false
            if CharacterFrame and CharacterFrame:IsShown()
               and GetFFD(CharacterFrame).equipPanel and GetFFD(CharacterFrame).equipPanel:IsShown() then
                RefreshEquipmentSets()
            end
        end)
    end
    local function QueueColorRefresh()
        if _colorRefreshPending then return end
        _colorRefreshPending = true
        -- 0.3s debounce: mass equip/unequip fires PLAYER_EQUIPMENT_CHANGED per slot;
        -- Blizzard's numLost/isEquipped metadata needs all slots to settle first.
        C_Timer.After(0.3, function()
            _colorRefreshPending = false
            RefreshEquipSetColors()
        end)
    end

    local equipmentColorMonitor = CreateFrame("Frame")
    equipmentColorMonitor:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    equipmentColorMonitor:RegisterEvent("EQUIPMENT_SWAP_FINISHED")
    equipmentColorMonitor:RegisterEvent("EQUIPMENT_SETS_CHANGED")
    equipmentColorMonitor:SetScript("OnEvent", QueueColorRefresh)
    if CharacterFrame then
        CharacterFrame:HookScript("OnShow", QueueColorRefresh)
    end

    -- EQUIPMENT_SETS_CHANGED is a structural change (add/remove/rename).
    local equipSetChangeFrame = CreateFrame("Frame")
    equipSetChangeFrame:RegisterEvent("EQUIPMENT_SETS_CHANGED")
    equipSetChangeFrame:SetScript("OnEvent", QueueFullRefresh)

    equipPanel:HookScript("OnShow", function()
        RefreshEquipmentSets()
    end)

    -- Equipment Manager button. Activates Blizzard's equipment sidebar
    -- (PaperDollSidebarTab3) so the per-slot flyout arrows appear; our equipPanel
    -- overlays Blizzard's EquipmentManagerPane with our own gear-sets UI.
    CreateEUIButton("Equipment", L("Equipment"), function()
        if not GetFFD(CharacterFrame).equipPanel:IsShown() then
            GetFFD(CharacterFrame).equipPanel:SetShown(true)
            statsPanel:SetShown(false)
            if GetFFD(CharacterFrame).titlesPanel then GetFFD(CharacterFrame).titlesPanel:SetShown(false) end
            local sidebarTab = _G.PaperDollSidebarTab3
            if sidebarTab and sidebarTab.Click then
                pcall(sidebarTab.Click, sidebarTab)
            end
        end
    end)

    local buttons = {
        "EUI_CharSheet_Stats",
        "EUI_CharSheet_Titles",
        "EUI_CharSheet_Equipment"
    }
    -- Buttons chain from the stats panel's TOPLEFT and span its full width.
    -- Frame level is raised above the stats panel so statsBg doesn't cover them.
    for i, btnName in ipairs(buttons) do
        local btn = _G[btnName]
        if btn then
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", statsPanel, "TOPLEFT",
                (i - 1) * (buttonWidth + buttonSpacing), 0)
            btn:SetFrameLevel(statsPanel:GetFrameLevel() + 2)
        end
    end

    -- Character tab is the default active view
    SetActiveTopButton(characterBtn)

    -- Calc tab is created lazily by ApplyCharSheetCalcTab when showCalcButton is on.
    if EllesmereUI.ApplyCharSheetCalcTab then
        EllesmereUI.ApplyCharSheetCalcTab()
    end

    -- Left column slots (show itemlevel on right)
    local leftColumnSlots = {
        "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot",
        "CharacterBackSlot", "CharacterChestSlot", "CharacterShirtSlot",
        "CharacterTabardSlot", "CharacterWristSlot"
    }

    -- Right column slots (show itemlevel on left)
    local rightColumnSlots = {
        "CharacterHandsSlot", "CharacterWaistSlot", "CharacterLegsSlot",
        "CharacterFeetSlot", "CharacterFinger0Slot", "CharacterFinger1Slot",
        "CharacterTrinket0Slot", "CharacterTrinket1Slot"
    }

    local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("blizzardSkin") or STANDARD_TEXT_FONT

    local globalSocketContainer = CreateFrame("Frame", "EUI_CharSheet_SocketContainer", frame)
    globalSocketContainer:SetFrameLevel(100)
    local isCharacterTab = (frame.selectedTab or 1) == 1
    if isCharacterTab then
        globalSocketContainer:Show()
    else
        globalSocketContainer:Hide()
    end
    GetFFD(frame).socketContainer = globalSocketContainer

    -- Create overlay frame for text labels (above model, transparent, no mouse input)
    local textOverlayFrame = CreateFrame("Frame", "EUI_CharSheet_TextOverlay", frame)
    textOverlayFrame:SetFrameLevel(5)  -- Higher than model (FrameLevel 2)
    textOverlayFrame:EnableMouse(false)
    textOverlayFrame:Show()
    GetFFD(frame).textOverlayFrame = textOverlayFrame

    -- Top-left eyeball toggle: temporarily hides all item slot text (item level,
    -- upgrade track, enchants) by alpha-ing the shared overlay. Session-only.
    do
        local EYE_VISIBLE   = EllesmereUI.EYE_VISIBLE_ICON
        local EYE_INVISIBLE = EllesmereUI.EYE_INVISIBLE_ICON
        local hidden = false
        local eyeBtn = CreateFrame("Button", "EUI_CharSheet_TextEyeBtn", frame)
        eyeBtn:SetSize(20, 20)
        eyeBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -6)
        eyeBtn:SetFrameLevel(frame:GetFrameLevel() + 20)
        eyeBtn:SetAlpha(0.4)
        local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
        eyeTex:SetAllPoints()
        eyeTex:SetTexture(EYE_VISIBLE)
        eyeBtn:SetScript("OnClick", function()
            hidden = not hidden
            eyeTex:SetTexture(hidden and EYE_INVISIBLE or EYE_VISIBLE)
            if GetFFD(frame).textOverlayFrame then
                GetFFD(frame).textOverlayFrame:SetAlpha(hidden and 0 or 1)
            end
        end)
        eyeBtn:SetScript("OnEnter", function(self)
            self:SetAlpha(0.8)
            if EllesmereUI.ShowWidgetTooltip then
                EllesmereUI.ShowWidgetTooltip(self, hidden and "Show Item Text" or "Hide Item Text", { width = 135 })
            end
        end)
        eyeBtn:SetScript("OnLeave", function(self)
            self:SetAlpha(0.4)
            if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
        end)
        GetFFD(frame).textEyeBtn = eyeBtn
    end

    for _, slotName in ipairs(itemSlots) do
        ApplyCustomSlotBorder(slotName)

        -- Shirt/tabard: skin the border but never show item level / upgrade track /
        -- enchant text -- no stats worth showing, and the labels clutter the model.
        local skipLabels = (slotName == "CharacterShirtSlot" or slotName == "CharacterTabardSlot")

        -- Create itemlevel labels
        local slot = _G[slotName]
        if slot and not GetFFD(slot).itemLevelLabel and not skipLabels then
            local itemLevelSize = EllesmereUIDB and EllesmereUIDB.charSheetItemLevelSize or 11
            local label = textOverlayFrame:CreateFontString(nil, "OVERLAY")
            label:SetFont(fontPath, itemLevelSize, "")
            label:SetTextColor(1, 1, 1, 0.8)
            label:SetJustifyH("CENTER")

            -- Placed on the outer side of the slot's column.
            if tContains(leftColumnSlots, slotName) then
                label:SetPoint("CENTER", slot, "RIGHT", 15, 10)
            elseif tContains(rightColumnSlots, slotName) then
                label:SetPoint("CENTER", slot, "LEFT", -15, 10)
            elseif slotName == "CharacterMainHandSlot" then
                label:SetPoint("CENTER", slot, "LEFT", -15, 10)
            elseif slotName == "CharacterSecondaryHandSlot" then
                label:SetPoint("CENTER", slot, "RIGHT", 15, 10)
            end

            GetFFD(slot).itemLevelLabel = label
        end

        -- Create enchant labels
        if slot and not GetFFD(slot).enchantLabel and not skipLabels then
            local enchantSize = EllesmereUIDB and EllesmereUIDB.charSheetEnchantSize or 9
            local enchantLabel = textOverlayFrame:CreateFontString(nil, "OVERLAY")
            enchantLabel:SetFont(fontPath, enchantSize, "")
            enchantLabel:SetTextColor(1, 1, 1, 0.8)

            -- Below the itemlevel, justified toward the icon so a width-capped
            -- enchant name hugs its slot: left column left-aligned, right column
            -- right-aligned (weapon slots follow their anchor side).
            if tContains(leftColumnSlots, slotName) then
                enchantLabel:SetPoint("LEFT", slot, "RIGHT", 5, -5)
                enchantLabel:SetJustifyH("LEFT")
            elseif tContains(rightColumnSlots, slotName) then
                enchantLabel:SetPoint("RIGHT", slot, "LEFT", -5, -5)
                enchantLabel:SetJustifyH("RIGHT")
            elseif slotName == "CharacterMainHandSlot" then
                enchantLabel:SetPoint("RIGHT", slot, "LEFT", -5, -5)
                enchantLabel:SetJustifyH("RIGHT")
            elseif slotName == "CharacterSecondaryHandSlot" then
                enchantLabel:SetPoint("LEFT", slot, "RIGHT", 5, -5)
                enchantLabel:SetJustifyH("LEFT")
            else
                enchantLabel:SetJustifyH("CENTER")
            end

            local hoverFrame = CreateFrame("Frame", nil, textOverlayFrame)
            hoverFrame:SetSize(20, 20)
            hoverFrame:SetFrameLevel(textOverlayFrame:GetFrameLevel() + 20)
            if tContains(leftColumnSlots, slotName) then
                hoverFrame:SetPoint("LEFT", slot, "RIGHT", 5, -5)
            elseif tContains(rightColumnSlots, slotName) then
                hoverFrame:SetPoint("RIGHT", slot, "LEFT", -5, -5)
            elseif slotName == "CharacterMainHandSlot" then
                hoverFrame:SetPoint("RIGHT", slot, "LEFT", -5, -5)
            elseif slotName == "CharacterSecondaryHandSlot" then
                hoverFrame:SetPoint("LEFT", slot, "RIGHT", 5, -5)
            end
            hoverFrame:EnableMouse(true)
            hoverFrame:Hide()

            GetFFD(slot).enchantLabel     = enchantLabel
            GetFFD(slot).enchantHoverFrame = hoverFrame
        end

        -- Create upgrade track labels (positioned relative to itemlevel)
        if slot and not GetFFD(slot).upgradeTrackLabel and GetFFD(slot).itemLevelLabel then
            local upgradeTrackSize = EllesmereUIDB and EllesmereUIDB.charSheetUpgradeTrackSize or 11
            local upgradeTrackLabel = textOverlayFrame:CreateFontString(nil, "OVERLAY")
            upgradeTrackLabel:SetFont(fontPath, upgradeTrackSize, "")
            upgradeTrackLabel:SetTextColor(1, 1, 1, 0.6)
            upgradeTrackLabel:SetJustifyH("CENTER")

            -- Beside the itemlevel label, on the model-facing side of the column.
            if tContains(leftColumnSlots, slotName) then
                upgradeTrackLabel:SetPoint("LEFT", GetFFD(slot).itemLevelLabel, "RIGHT", 3, 0)
            elseif tContains(rightColumnSlots, slotName) then
                upgradeTrackLabel:SetPoint("RIGHT", GetFFD(slot).itemLevelLabel, "LEFT", -3, 0)
            elseif slotName == "CharacterMainHandSlot" then
                upgradeTrackLabel:SetPoint("RIGHT", GetFFD(slot).itemLevelLabel, "LEFT", -3, 0)
            elseif slotName == "CharacterSecondaryHandSlot" then
                upgradeTrackLabel:SetPoint("LEFT", GetFFD(slot).itemLevelLabel, "RIGHT", 3, 0)
            end

            GetFFD(slot).upgradeTrackLabel = upgradeTrackLabel
        end
    end

    local function UpdateSlotBorders()
        for _, slotName in ipairs(itemSlots) do
            local slot = _G[slotName]
            if slot then
                local itemLink = GetInventoryItemLink("player", slot:GetID())
                local borderR, borderG, borderB = 0.4, 0.4, 0.4  -- Default dark gray
                if itemLink then
                    local rarity = C_Item.GetItemQualityByID(itemLink)
                    if rarity then
                        borderR, borderG, borderB = C_Item.GetItemQualityColor(rarity)
                    end
                end
                if EllesmereUI and EllesmereUI.PanelPP then
                    EllesmereUI.PanelPP.SetBorderColor(slot, borderR, borderG, borderB, 1)
                end
            end
        end
    end

    -- Shared pulse ticker: every slot needing the red "missing enchant" pulse uses this one OnUpdate. Zero cost when empty (ticker self-hides).
    local missingEnchantSlots = {}
    local pulseTicker = CreateFrame("Frame")
    pulseTicker:Hide()
    pulseTicker:SetScript("OnUpdate", function()
        -- 1.5s sin cycle between alpha 0.25 and 1.0
        local t = GetTime()
        local alpha = 0.25 + 0.75 * (0.5 + 0.5 * math.sin(t * math.pi / 0.75))
        for slot in pairs(missingEnchantSlots) do
            local ov = GetFFD(slot).missingEnchBorder
            if ov then ov:SetAlpha(alpha) end
        end
    end)

    local function SetSlotMissingEnchant(slot, missing)
        if missing then
            if not GetFFD(slot).missingEnchBorder then
                local overlay = CreateFrame("Frame", nil, slot)
                overlay:SetAllPoints(slot)
                overlay:SetFrameLevel(slot:GetFrameLevel())
                if EllesmereUI and EllesmereUI.PanelPP then
                    EllesmereUI.PanelPP.CreateBorder(overlay, 0.898, 0.286, 0.286, 1, 2, "OVERLAY", 1)  -- #e54949
                    local enchBdr = EllesmereUI.PanelPP.GetBorders(overlay)
                    if enchBdr then enchBdr:SetFrameLevel(slot:GetFrameLevel()) end
                end
                GetFFD(slot).missingEnchBorder = overlay
            end
            GetFFD(slot).missingEnchBorder:Show()
            missingEnchantSlots[slot] = true
            if not pulseTicker:IsShown() then pulseTicker:Show() end
        else
            if GetFFD(slot).missingEnchBorder then GetFFD(slot).missingEnchBorder:Hide() end
            missingEnchantSlots[slot] = nil
            if not next(missingEnchantSlots) then pulseTicker:Hide() end
        end
    end
    -- Expose so UpdateSlotInfo can drive it from the existing isMissing flag.
    GetFFD(frame).setSlotMissingEnchant = SetSlotMissingEnchant

    -- Repaint borders on inventory/equipment/item-load changes. GetItemInfo can return nil on freshly-linked items; GET_ITEM_INFO_RECEIVED lands the repaint.
    local inventoryFrame = CreateFrame("Frame")
    inventoryFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
    inventoryFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    inventoryFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    inventoryFrame:SetScript("OnEvent", function(self, event, arg1)
        if event == "UNIT_INVENTORY_CHANGED" and arg1 ~= "player" then return end
        if not (frame and frame:IsShown()) then return end
        UpdateSlotBorders()
    end)
    -- Paint once on panel open in case events fired before we hooked up.
    frame:HookScript("OnShow", UpdateSlotBorders)

    -- Gem layout: gems sit INSIDE the gear icon, anchored bottom-right and stacking
    -- leftward for multiples, inset 2 physical pixels from the slot's 1px border.
    local PP_GEM     = EllesmereUI.PanelPP
    local GEM_PP_MULT = (PP_GEM and PP_GEM.mult) or 1
    local GEM_SIZE   = 15
    local GEM_PAD    = GEM_PP_MULT           -- 1 physical-pixel gap between stacked gems
    local GEM_INSET_X = 2 * GEM_PP_MULT      -- 2 physical pixels from slot's right edge
    local GEM_INSET_Y = 2 * GEM_PP_MULT      -- 2 physical pixels from slot's bottom edge

    -- Gem border color by rarity: rare+ gold, uncommon silver.
    local function GemBorderColor(rarity)
        if (rarity or 0) >= 3 then
            return 1.00, 0.82, 0.00, 1  -- gold
        end
        return 0.75, 0.75, 0.75, 1       -- silver
    end

    -- Each socket is a small Frame (not a raw texture) so it can carry a 1px pixel-perfect border.
    local function GetOrCreateSocketIcons(slot, side, slotIndex)
        if GetFFD(slot).charSocketsIcons then return GetFFD(slot).charSocketsIcons end

        GetFFD(slot).charSocketsIcons = {}   -- list of icon textures (gem art)
        GetFFD(slot).charSocketsFrames = {}  -- list of parent frames (borders live here)
        GetFFD(slot).charSocketsBtns = GetFFD(slot).charSocketsIcons  -- alias for callers
        GetFFD(slot).gemLinks = {}

        for i = 1, 2 do  -- max 2 gems displayed per slot
            local gemFrame = CreateFrame("Frame", nil, globalSocketContainer)
            gemFrame:SetSize(GEM_SIZE, GEM_SIZE)
            gemFrame:EnableMouse(true)
            gemFrame:Hide()

            local icon = gemFrame:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints(gemFrame)

            -- 2px pixel-perfect border, recolored per-gem in UpdateSocketIcons.
            PP_GEM.CreateBorder(gemFrame, 1, 1, 1, 1, 2, "OVERLAY", 1)
            local gemBdr = PP_GEM.GetBorders(gemFrame)
            if gemBdr then gemBdr:SetFrameLevel(gemFrame:GetFrameLevel()) end

            GetFFD(slot).charSocketsFrames[i] = gemFrame
            GetFFD(slot).charSocketsIcons[i]  = icon
        end

        GetFFD(slot).charSocketsSide = side
        GetFFD(slot).charSocketsSlotIndex = slotIndex

        return GetFFD(slot).charSocketsIcons
    end

    local function UpdateSocketIcons(slotName)
        local slot = _G[slotName]
        if not slot then return end

        local slotIndex = slot:GetID()
        local side = tContains(leftColumnSlots, slotName) and "RIGHT" or "LEFT"

        local socketIcons = GetOrCreateSocketIcons(slot, side, slotIndex)

        local invLink = GetInventoryItemLink("player", slotIndex)
        local gemsEnabled = not (EllesmereUIDB and EllesmereUIDB.showGems == false)
        if not invLink or not gemsEnabled then
            for _, gemFrame in ipairs(GetFFD(slot).charSocketsFrames or {}) do
                gemFrame:Hide()
            end
            return
        end

        local passes = GetFFD(slot).euiGemPaintPasses or 0
        local socketTextures, totalSockets, nGems, gemLinks =
            EUI_BuildSocketIconRow(invLink, passes)

        if totalSockets > 0 and nGems == 0 then
            local iid = GetInventoryItemID("player", slotIndex)
            if iid and iid > 0 and C_Item and C_Item.RequestLoadItemDataByID then
                C_Item.RequestLoadItemDataByID(iid)
            end
            GetFFD(slot).euiGemPaintPasses = passes + 1
        else
            GetFFD(slot).euiGemPaintPasses = 0
        end

        -- TOOLTIP_DATA_UPDATE / GET_ITEM_INFO_RECEIVED drive QueueSocketRefresh until the link's gem bytes match GetItemStats (never scrape a tooltip).

        GetFFD(slot).gemLinks = gemLinks

        -- Position and show gem frames inside the slot's bottom-right, with extra gems stacking leftward.
        if #socketTextures > 0 then
            local gemFrames = GetFFD(slot).charSocketsFrames or {}
            for i, icon in ipairs(socketIcons) do
                local gemFrame = gemFrames[i]
                if socketTextures[i] and gemFrame then
                    local entry = socketTextures[i]
                    if entry.isAtlas then
                        -- Empty socket: prefer Blizzard's socket atlas, never a bright
                        -- fallback fill. The inventory link can lack gem bytes while
                        -- GetItemStats still reports sockets, misreading as "missing gem" on gemmed gear.
                        if icon.SetAtlas then icon:SetAtlas(nil) end
                        icon:SetTexture(nil)
                        if icon.SetVertexColor then icon:SetVertexColor(1, 1, 1, 1) end
                        if icon.SetAtlas and entry.icon then
                            icon:SetColorTexture(0, 0, 0, 0)
                            icon:SetAtlas(entry.icon)
                        else
                            if icon.SetAtlas then icon:SetAtlas(nil) end
                            icon:SetColorTexture(0.22, 0.22, 0.26, 0.85)
                        end
                    else
                        -- Clear atlas/color-texture mode before applying a fileID, or the frame
                        -- shows only the PP border after a prior empty-socket atlas paint.
                        if icon.SetAtlas then icon:SetAtlas(nil) end
                        icon:SetColorTexture(0, 0, 0, 0)
                        icon:SetTexture(nil)
                        if icon.SetVertexColor then icon:SetVertexColor(1, 1, 1, 1) end
                        icon:SetTexture(entry.icon)
                    end

                    gemFrame:ClearAllPoints()
                    gemFrame:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT",
                        -GEM_INSET_X,
                        GEM_INSET_Y + (i - 1) * (GEM_SIZE + GEM_PAD))

                    -- Resolve gem rarity for border color.
                    local gemLink = GetFFD(slot).gemLinks and GetFFD(slot).gemLinks[i]
                    local rarity = 2
                    if gemLink then
                        local _, _, r = GetItemInfo(gemLink)
                        if r then rarity = r end
                    end
                    local r, g, b, a = GemBorderColor(rarity)
                    PP_GEM.SetBorderColor(gemFrame, r, g, b, a)

                    gemFrame:Show()

                    gemFrame:SetScript("OnEnter", function(self)
                        if GetFFD(slot).gemLinks[i] then
                            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                            GameTooltip:SetHyperlink(GetFFD(slot).gemLinks[i])
                            GameTooltip:Show()
                        end
                    end)
                    gemFrame:SetScript("OnLeave", function()
                        GameTooltip:Hide()
                    end)
                elseif gemFrame then
                    gemFrame:Hide()
                end
            end
        else
            for _, gemFrame in ipairs(GetFFD(slot).charSocketsFrames or {}) do
                gemFrame:Hide()
            end
        end
    end

    local function RefreshAllSocketIcons()
        for _, slotName in ipairs(itemSlots) do
            UpdateSocketIcons(slotName)
        end
    end
    EllesmereUI._refreshGemsVisibility = RefreshAllSocketIcons

    -- Hard reset a slot's gem art, called on PLAYER_EQUIPMENT_CHANGED before the debounced
    -- refresh so old gem icons can never linger (e.g. a gemmed ring swapped for an empty-socket one).
    local function ClearSlotGems(slot)
        if not slot then return end
        GetFFD(slot).euiGemPaintPasses = 0
        GetFFD(slot).gemLinks = {}
        if GetFFD(slot).charSocketsFrames then
            for _, gemFrame in ipairs(GetFFD(slot).charSocketsFrames) do
                gemFrame:Hide()
            end
        end
        if GetFFD(slot).charSocketsIcons then
            for _, icon in ipairs(GetFFD(slot).charSocketsIcons) do
                icon:SetTexture(nil)
                if icon.SetAtlas then icon:SetAtlas(nil) end
            end
        end
    end

    -- Map inventory slot IDs to slot button names, so we can clear the exact changed slot without scanning all 18.
    local _invSlotToName = {}
    for _, slotName in ipairs(itemSlots) do
        local b = _G[slotName]
        if b and b.GetID then
            local id = b:GetID()
            if id and id > 0 then _invSlotToName[id] = slotName end
        end
    end

    local function CharSheetGemsActive()
        if EllesmereUIDB and (EllesmereUIDB.themedCharacterSheet == false or EllesmereUI.BlizzWindowSkinsKilled()) then return false end
        if EllesmereUIDB and EllesmereUIDB.showGems == false then return false end
        return true
    end

    local _equippedItemIDs = {}
    local function RefreshEquippedItemIDs()
        wipe(_equippedItemIDs)
        for _, slotName in ipairs(itemSlots) do
            local sl = _G[slotName]
            if sl and sl.GetID then
                local iid = GetInventoryItemID("player", sl:GetID())
                if iid and iid > 0 then
                    _equippedItemIDs[iid] = true
                end
            end
        end
    end
    RefreshEquippedItemIDs()

    -- Equipment/item-load hooks: TRAILING debounce so a burst of GET_ITEM_INFO_RECEIVED
    -- yields one refresh after data settles (a leading debounce fires once on stale links right after /reload).
    local _socketRefreshTimer
    local function QueueSocketRefresh()
        if _socketRefreshTimer then
            _socketRefreshTimer:Cancel()
            _socketRefreshTimer = nil
        end
        _socketRefreshTimer = C_Timer.NewTimer(0.12, function()
            _socketRefreshTimer = nil
            if frame and frame:IsShown() and (frame.selectedTab or 1) == 1 then
                RefreshAllSocketIcons()
            end
        end)
    end

    local socketWatcher = CreateFrame("Frame")
    socketWatcher:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    socketWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    -- Hydration (2 global): must hear item load while Character is closed after
    -- /reload. UNIT_INVENTORY_CHANGED + SOCKET_INFO_UPDATE (2 OnShow-only) below.
    if CharSheetGemsActive() then
        socketWatcher:RegisterEvent("TOOLTIP_DATA_UPDATE")
        socketWatcher:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    end
    socketWatcher:SetScript("OnEvent", function(_, event, arg1)
        if not CharSheetGemsActive() then return end
        if event == "UNIT_INVENTORY_CHANGED" and arg1 ~= "player" then return end
        if event == "PLAYER_EQUIPMENT_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
            RefreshEquippedItemIDs()
        end
        if event == "GET_ITEM_INFO_RECEIVED" and (not arg1 or not _equippedItemIDs[arg1]) then
            return
        end
        -- Clear the changed slot's stale gem art BEFORE the debounced refresh, or old icons can survive until /reload on cached gem data.
        if event == "PLAYER_EQUIPMENT_CHANGED" and arg1 then
            local slotName = _invSlotToName[arg1]
            if slotName then ClearSlotGems(_G[slotName]) end
        end
        -- No refresh work while the sheet is closed (the cache/clear-slot work above still runs).
        if not frame:IsShown() or (frame.selectedTab or 1) ~= 1 then
            return
        end
        QueueSocketRefresh()
    end)

    frame:HookScript("OnShow", function()
        -- Non-hydration high-frequency events: only while the sheet is visible.
        socketWatcher:RegisterEvent("UNIT_INVENTORY_CHANGED")
        socketWatcher:RegisterEvent("SOCKET_INFO_UPDATE")
        -- Sockets and the container only matter on the Character tab.
        local isCharacterTab = (frame.selectedTab or 1) == 1
        if isCharacterTab then
            RefreshEquippedItemIDs()
            RefreshAllSocketIcons()
            QueueSocketRefresh()
            globalSocketContainer:Show()
        else
            globalSocketContainer:Hide()
        end
        -- Reset to Stats sub-panel on open, ONLY for the Character tab: forcing
        -- selectedTab = 1 when opened via keybind to Rep/Currency desyncs Blizzard's
        -- tab state and leaves the Character tab un-clickable until the user clicks Currency to resync.
        if isCharacterTab then
            if statsPanel        then statsPanel:SetShown(true)          end
            if GetFFD(frame).titlesPanel then GetFFD(frame).titlesPanel:SetShown(false) end
            if GetFFD(frame).equipPanel  then GetFFD(frame).equipPanel:SetShown(false)  end
            if SetActiveTopButton and characterBtn then
                SetActiveTopButton(characterBtn)
            end
        end
    end)

    frame:HookScript("OnHide", function()
        socketWatcher:UnregisterEvent("UNIT_INVENTORY_CHANGED")
        socketWatcher:UnregisterEvent("SOCKET_INFO_UPDATE")
        if _socketRefreshTimer then
            _socketRefreshTimer:Cancel()
            _socketRefreshTimer = nil
        end
        for _, sn in ipairs(itemSlots) do
            local sl = _G[sn]
            if sl then
                GetFFD(sl).euiGemPaintPasses = 0
            end
        end
        globalSocketContainer:Hide()
        if GetFFD(frame).scrollBar then GetFFD(frame).scrollBar:Hide() end
    end)


    -- Enchant/upgrade-track scanning goes through EUI_ScanInventoryItem
    -- (C_TooltipInfo). NEVER create a scanning tooltip frame from Lua.

    -- Cache item info (ID, level, upgrade track) to update when items change
    local itemCache = {}

    -- Slots that can have enchants in current expansion
    local ENCHANT_SLOTS = {
        [INVSLOT_HEAD] = true,
        [INVSLOT_SHOULDER] = true,
        [INVSLOT_BACK] = false,
        [INVSLOT_CHEST] = true,
        [INVSLOT_WRIST] = false,
        [INVSLOT_LEGS] = true,
        [INVSLOT_FEET] = true,
        [INVSLOT_FINGER1] = true,
        [INVSLOT_FINGER2] = true,
        [INVSLOT_MAINHAND] = true,
        -- INVSLOT_OFFHAND deliberately absent: whether it can be enchanted depends on
        -- what's equipped there (weapon vs. shield/held item), checked dynamically below.
    }

    -- Update one slot's item level, enchant and upgrade-track labels.
    local function UpdateSlotInfo(slotName)
        local slot = _G[slotName]
        if not slot then return end

        -- Tab guard: equipment events fire regardless of the active sub-tab, so
        -- labels must stay hidden if opened straight to Reputation/Currency.
        -- PaperDollFrame:IsShown() is the truth-source; PanelTemplates_GetSelectedTab lags on initial open.
        local isCharTab = PaperDollFrame and PaperDollFrame:IsShown()

        local itemLink = GetInventoryItemLink("player", slot:GetID())
        local itemLevel = ""
        local enchantText = ""
        local upgradeTrackText = ""
        local upgradeTrackColor = { r = 1, g = 1, b = 1 }
        local itemQuality = nil
        local slotID = slot:GetID()
        local canHaveEnchant = ENCHANT_SLOTS[slotID]
        if slotID == INVSLOT_OFFHAND and itemLink then
            local _, _, _, _, _, classID = GetItemInfoInstant(itemLink)
            canHaveEnchant = (classID == Enum.ItemClass.Weapon)
        end

        if itemLink then
            local _, _, quality, ilvl = GetItemInfo(itemLink)
            itemLevel = ilvl or ""
            itemQuality = quality

            -- Enchant via C_TooltipInfo; upgrade track via C_Item (no tooltip).
            enchantText = EUI_GetEnchantText(slot:GetID())
            upgradeTrackText, upgradeTrackColor = EUI_GetUpgradeTrack(itemLink)
        end

        -- Item-level display color, resolved once: custom override > upgrade-track hue >
        -- item rarity > white. Shared with the enchant name text when Show Enchant Names is on, so both read in the same color.
        local ilvlColor
        if EllesmereUIDB and EllesmereUIDB.charSheetItemLevelUseColor and EllesmereUIDB.charSheetItemLevelColor then
            ilvlColor = EllesmereUIDB.charSheetItemLevelColor
        elseif upgradeTrackText ~= "" and upgradeTrackColor then
            ilvlColor = upgradeTrackColor
        elseif (not EllesmereUIDB or EllesmereUIDB.charSheetColorItemLevel ~= false) and itemQuality then
            local r, g, b = GetItemQualityColor(itemQuality)
            ilvlColor = { r = r, g = g, b = b }
        else
            ilvlColor = { r = 1, g = 1, b = 1 }
        end

        if GetFFD(slot).itemLevelLabel then
            local showItemLevel = (not EllesmereUIDB) or (EllesmereUIDB.showItemLevel ~= false)

            if showItemLevel then
                GetFFD(slot).itemLevelLabel:SetText(tostring(itemLevel) or "")
                GetFFD(slot).itemLevelLabel:SetShown(isCharTab)
                GetFFD(slot).itemLevelLabel:SetTextColor(ilvlColor.r, ilvlColor.g, ilvlColor.b, 0.9)
            else
                GetFFD(slot).itemLevelLabel:Hide()
            end
        end

        -- Enchant label: keep inline |A:...|a atlas escapes so quality icons render, strip
        -- the readable text, and park the full original text behind a hover tooltip.
        if GetFFD(slot).enchantLabel then
            local showEnchants = (not EllesmereUIDB) or (EllesmereUIDB.showEnchants ~= false)
            -- Only flag missing enchants at level 90+: leveling gear churn would
            -- fire the red icon and pulse on every replacement.
            local playerLvl = UnitLevel("player")
            local atEnchantLevel = playerLvl and not (issecretvalue and issecretvalue(playerLvl)) and playerLvl >= 90 or false
            local isMissing    = atEnchantLevel and canHaveEnchant and itemLink and (enchantText == "" or not enchantText)
            local hasEnchant   = enchantText and enchantText ~= ""

            local iconOnly, tooltipText
            if isMissing then
                -- Same hex atlas enchanted items show, tinted red (#e54949 =
                -- 229, 73, 73 in the atlas-escape color fields).
                iconOnly    = "|A:Professions-ChatIcon-Quality-Tier5:14:14:0:0:229:73:73|a"
                tooltipText = "Enchant missing"
            elseif hasEnchant then
                -- Concatenate every |A:...|a atlas escape, drop everything else.
                local icons = {}
                for atlas in enchantText:gmatch("|A:[^|]+|a") do
                    icons[#icons + 1] = atlas
                end
                iconOnly    = table.concat(icons, "")
                tooltipText = enchantText:gsub("|A:[^|]+|a", ""):gsub("^%s+", ""):gsub("%s+$", "")
                -- Strip any "prefix - " (e.g. "Enchant Weapon - ") so the tooltip
                -- shows just the enchant's readable name.
                tooltipText = tooltipText:gsub("^.-%s*%-%s*", "")
            end

            -- "Show Enchant Names": render the readable name (item-level colored) instead of the
            -- icon. Missing-enchant warning always keeps its red icon; no-enchant falls back to icon.
            local showNames = EllesmereUIDB and EllesmereUIDB.charSheetEnchantNames
            local useName = showNames and hasEnchant and tooltipText and tooltipText ~= ""
            local labelText = useName and tooltipText or iconOnly

            if showEnchants and labelText and labelText ~= "" then
                GetFFD(slot).enchantLabel:SetText(labelText)
                local enchFontSize = (EllesmereUIDB and EllesmereUIDB.charSheetEnchantSize) or 9
                if useName then
                    -- Names always render OUTLINE, SLUG for legibility over the model.
                    GetFFD(slot).enchantLabel:SetFont(fontPath, enchFontSize, "OUTLINE, SLUG")
                    -- Item-level color, blended 50% toward white so the name reads
                    -- softer than the ilvl number.
                    GetFFD(slot).enchantLabel:SetTextColor(
                        ilvlColor.r + (1 - ilvlColor.r) * 0.5,
                        ilvlColor.g + (1 - ilvlColor.g) * 0.5,
                        ilvlColor.b + (1 - ilvlColor.b) * 0.5, 0.9)
                    -- Cap the name at 45% of the gap between equipment columns (left icons'
                    -- right edge -> right icons' left edge) so a long enchant never bleeds
                    -- over the model or into the far column; overflow ellipsizes, full name
                    -- stays on the tooltip. textOverlayFrame shares the slots' effective scale, so the delta is already in width units.
                    local maxW
                    local leftRef, rightRef = _G.CharacterHeadSlot, _G.CharacterHandsSlot
                    if leftRef and rightRef then
                        local lr, rl = leftRef:GetRight(), rightRef:GetLeft()
                        if lr and rl and rl > lr then maxW = (rl - lr) * 0.45 end
                    end
                    GetFFD(slot).enchantLabel:SetWordWrap(false)
                    GetFFD(slot).enchantLabel:SetWidth(maxW or 0)
                else
                    -- Icon mode: no outline (the label's creation default), white
                    -- tint so a prior name-mode color never bleeds onto the atlas
                    -- icons, and clear the width cap.
                    GetFFD(slot).enchantLabel:SetFont(fontPath, enchFontSize, "")
                    GetFFD(slot).enchantLabel:SetTextColor(1, 1, 1, 0.8)
                    GetFFD(slot).enchantLabel:SetWidth(0)
                end
                GetFFD(slot).enchantLabel:SetShown(isCharTab)

                if GetFFD(slot).enchantHoverFrame then
                    GetFFD(slot).enchantHoverFrame:SetShown(isCharTab)
                    GetFFD(slot).enchantHoverFrame:SetScript("OnEnter", function(self)
                        if not tooltipText or tooltipText == "" then return end
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetText(tooltipText, 1, 1, 1, 1, true)
                        GameTooltip:Show()
                    end)
                    GetFFD(slot).enchantHoverFrame:SetScript("OnLeave", function()
                        GameTooltip:Hide()
                    end)
                end
            else
                GetFFD(slot).enchantLabel:Hide()
                if GetFFD(slot).enchantHoverFrame then GetFFD(slot).enchantHoverFrame:Hide() end
            end

            -- Pulsing red border for missing enchants, driven by the same isMissing
            -- flag so it stays in sync with the icon swap.
            if GetFFD(frame).setSlotMissingEnchant then
                GetFFD(frame).setSlotMissingEnchant(slot, isMissing == true)
            end
        end

        if GetFFD(slot).upgradeTrackLabel then
            local showUpgradeTrack = (not EllesmereUIDB) or (EllesmereUIDB.showUpgradeTrack ~= false)

            if showUpgradeTrack then
                GetFFD(slot).upgradeTrackLabel:SetText(upgradeTrackText ~= "" and ("(" .. upgradeTrackText .. ")") or "")
                GetFFD(slot).upgradeTrackLabel:SetShown(isCharTab)

                local displayColor
                if EllesmereUIDB and EllesmereUIDB.charSheetUpgradeTrackUseColor and EllesmereUIDB.charSheetUpgradeTrackColor then
                    displayColor = EllesmereUIDB.charSheetUpgradeTrackColor
                else
                    -- Track's own rarity color by default.
                    displayColor = upgradeTrackColor
                end

                GetFFD(slot).upgradeTrackLabel:SetTextColor(displayColor.r, displayColor.g, displayColor.b, 0.8)
            else
                GetFFD(slot).upgradeTrackLabel:Hide()
            end
        end
    end

    -- Event-driven per-slot label refresh; item-link cache guards redundant work, events catch upgrade/enchant/socket changes without polling.
    local function RefreshAllSlotLabels()
        if EllesmereUIDB and (EllesmereUIDB.themedCharacterSheet == false or EllesmereUI.BlizzWindowSkinsKilled()) then return end
        if not (frame and frame:IsShown()) then return end
        for _, slotName in ipairs(itemSlots) do
            local itemLink = GetInventoryItemLink("player", _G[slotName]:GetID())
            if itemCache[slotName] ~= itemLink then
                itemCache[slotName] = itemLink
                UpdateSlotInfo(slotName)
            end
        end
    end

    -- Public: force a full slot-label rebuild with no item change. Render-only toggles (e.g.
    -- Show Enchant Names) leave items untouched, so the item-link cache above would short-circuit every slot and never apply live.
    function EllesmereUI._refreshCharSheetSlotLabels()
        wipe(itemCache)
        RefreshAllSlotLabels()
    end

    if not GetFFD(frame).itemLevelMonitor then
        GetFFD(frame).itemLevelMonitor = CreateFrame("Frame")
        GetFFD(frame).itemLevelMonitor:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        GetFFD(frame).itemLevelMonitor:RegisterEvent("UNIT_INVENTORY_CHANGED")
        GetFFD(frame).itemLevelMonitor:RegisterEvent("SOCKET_INFO_UPDATE")
        GetFFD(frame).itemLevelMonitor:RegisterEvent("ITEM_UPGRADE_MASTER_UPDATE")
        -- No BAG_UPDATE_DELAYED: bag contents cannot change the displayed
        -- equipped-item info (ilvl / enchant / upgrade track).
        GetFFD(frame).itemLevelMonitor:SetScript("OnEvent", function(_, event, unit)
            if event == "UNIT_INVENTORY_CHANGED" and unit ~= "player" then return end
            if not (frame and frame:IsShown()) then return end
            RefreshAllSlotLabels()
        end)
        frame:HookScript("OnShow", RefreshAllSlotLabels)
        -- Skinning is deferred to first open, so the hook above is installed
        -- mid-show and misses this open event; refresh now to decorate it.
        RefreshAllSlotLabels()
    end

    -- Same deferred-skin timing for gem icons: the OnShow hook above is installed
    -- mid-show and won't fire for the first open.
    if (frame.selectedTab or 1) == 1 then
        RefreshAllSocketIcons()
    end

    -- Re-apply tab visibility now that every element exists: the earlier call runs before the
    -- stats panel/model scene/slots are created, so opening Rep/Currency by hotkey would leave character-tab elements visible.
    local isCharTab = not (_G.ReputationFrame and _G.ReputationFrame:IsShown())
        and not (_G.TokenFrame and _G.TokenFrame:IsShown())
    ApplyTabVisibility(isCharTab)
end

local function GetRarityColorFromLink(itemLink)
    if not itemLink then
        return 0.9, 0.9, 0.9, 1  -- Default gray
    end

    local itemRarity = select(3, GetItemInfo(itemLink))
    if not itemRarity then
        return 0.9, 0.9, 0.9, 1
    end

    -- WoW standard rarity colors
    local rarityColors = {
        [0] = { 0.62, 0.62, 0.62 },  -- Poor
        [1] = { 1, 1, 1 },            -- Common
        [2] = { 0.12, 1, 0 },         -- Uncommon
        [3] = { 0, 0.44, 0.87 },      -- Rare
        [4] = { 0.64, 0.21, 0.93 },   -- Epic
        [5] = { 1, 0.5, 0 },          -- Legendary
        [6] = { 0.9, 0.8, 0.5 },      -- Artifact
        [7] = { 0.9, 0.8, 0.5 },      -- Heirloom
    }

    local color = rarityColors[itemRarity] or rarityColors[1]
    return color[1], color[2], color[3], 1
end

local function SkinCharacterSlot(slotName, slotID)
    local slot = _G[slotName]
    if not slot or GetFFD(slot).skinned then return end
    GetFFD(slot).skinned = true

    if slot.IconBorder then
        slot.IconBorder:Hide()
    end

    local iconTexture = _G[slotName .. "IconTexture"]
    if iconTexture then
        iconTexture:SetTexCoord(0.07, 0.07, 0.07, 0.93, 0.93, 0.07, 0.93, 0.93)
    end

    if slotName == "CharacterHandsSlot" then
        slot:Hide()
    end

    local normalTexture = _G[slotName .. "NormalTexture"]
    if normalTexture then
        normalTexture:Hide()
    end

    local slotBg = slot:CreateTexture(nil, "BACKGROUND", nil, -5)
    slotBg:SetAllPoints(slot)
    slotBg:SetColorTexture(0.5, 0.5, 0.5, 0.7)
    GetFFD(slot).slotBg = slotBg

    if EllesmereUI and EllesmereUI.PanelPP then
        EllesmereUI.PanelPP.CreateBorder(slot, 1, 1, 1, 0.4, 2, "OVERLAY", 7)
    end
end

-- Fake bottom tab on the character sheet, visually identical to the Blizzard
-- Character/Rep/Currency tabs. Built on first enable only (zero cost while off).
local function EnsureCalcTab(frame)
    local existing = GetFFD(frame).calcToggleBtn
    if existing then return existing end

    local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("blizzardSkin") or STANDARD_TEXT_FONT
    local PP = EllesmereUI and EllesmereUI.PP

    local refTab = _G["CharacterFrameTab1"]
    local tabW = refTab and refTab:GetWidth() or 80
    local tabH = refTab and refTab:GetHeight() or 32

    local calcTab = CreateFrame("Button", "EUI_CharSheet_CalcTab", frame)
    calcTab:SetSize(tabW, tabH)
    calcTab:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, -30)
    calcTab:SetFrameLevel(frame:GetFrameLevel() + 5)
    calcTab:EnableMouse(true)

    local bg = calcTab:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.068, 0.056, 0.052, 1)

    local activeHL = calcTab:CreateTexture(nil, "ARTWORK", nil, -6)
    activeHL:SetAllPoints()
    activeHL:SetColorTexture(1, 1, 1, 0.02)
    activeHL:SetBlendMode("ADD")
    activeHL:Hide()

    local label = calcTab:CreateFontString(nil, "OVERLAY")
    label:SetFont(fontPath, 9, "")
    label:SetPoint("CENTER", calcTab, "CENTER", 0, 0)
    label:SetJustifyH("CENTER")
    label:SetText("Upgrades")

    local EG = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }
    local underline = calcTab:CreateTexture(nil, "OVERLAY", nil, 6)
    if PP and PP.DisablePixelSnap then
        PP.DisablePixelSnap(underline)
        underline:SetHeight(PP.mult or 1)
    else
        underline:SetHeight(1)
    end
    underline:SetPoint("BOTTOMLEFT", calcTab, "BOTTOMLEFT", 0, 0)
    underline:SetPoint("BOTTOMRIGHT", calcTab, "BOTTOMRIGHT", 0, 0)
    underline:SetColorTexture(EG.r, EG.g, EG.b, 1)
    underline:Hide()
    if EllesmereUI.RegAccent then
        EllesmereUI.RegAccent({ type = "solid", obj = underline, a = 1 })
    end

    local function RefreshCalcTab()
        local fr = _G["EUIUpgCalcFrame"]
        if fr and not GetFFD(calcTab)._calcHooked then
            GetFFD(calcTab)._calcHooked = true
            fr:HookScript("OnShow", RefreshCalcTab)
            fr:HookScript("OnHide", RefreshCalcTab)
        end
        local isOpen = fr and fr:IsShown()
        label:SetTextColor(1, 1, 1, isOpen and 1 or 0.5)
        underline:SetShown(isOpen)
        activeHL:SetShown(isOpen)
    end
    RefreshCalcTab()

    calcTab:SetScript("OnEnter", function()
        label:SetTextColor(1, 1, 1, 1)
    end)
    calcTab:SetScript("OnLeave", function()
        RefreshCalcTab()
    end)
    calcTab:SetScript("OnClick", function()
        local fr = _G["EUIUpgCalcFrame"]
        if fr then
            if fr:IsShown() then fr:Hide() else fr:Show() end
            RefreshCalcTab()
        end
    end)

    frame:HookScript("OnShow", RefreshCalcTab)
    GetFFD(frame).calcToggleBtn = calcTab
    GetFFD(frame).updateCalcBtnColor = RefreshCalcTab
    return calcTab
end

-- Show/hide the Upgrades calc tab from upgradeCalcOpts.showCalcButton (live toggle).
local function ApplyCharSheetCalcTab()
    if not CharacterFrame then return end
    if not skinned then return end
    if EllesmereUIDB and (EllesmereUIDB.themedCharacterSheet == false or EllesmereUI.BlizzWindowSkinsKilled()) then
        return
    end
    local show = false
    if EUIUpgCalc and EUIUpgCalc.GetOptsDB then
        local calcDb = EUIUpgCalc.GetOptsDB()
        show = calcDb and calcDb.showCalcButton or false
    end
    if show then
        EnsureCalcTab(CharacterFrame):SetShown(true)
    else
        local calcTab = GetFFD(CharacterFrame).calcToggleBtn
        if calcTab then calcTab:SetShown(false) end
    end
end

-- Entry point: apply the themed character sheet.
local function ApplyThemedCharacterSheet()
    if EllesmereUIDB and (EllesmereUIDB.themedCharacterSheet == false or EllesmereUI.BlizzWindowSkinsKilled()) then
        return
    end

    if CharacterFrame then
        SkinCharacterSheet()
    end
end

if EllesmereUI then
    EllesmereUI.ApplyThemedCharacterSheet = ApplyThemedCharacterSheet
    EllesmereUI.ApplyCharSheetCalcTab = ApplyCharSheetCalcTab

    -- Setup at PLAYER_LOGIN to register drag hooks early
    local initFrame = CreateFrame("Frame")
    initFrame:RegisterEvent("PLAYER_LOGIN")
    initFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        if CharacterFrame then
            -- Pre-skin runs early, while CharacterFrame is still hidden; running it
            -- mid-OnShow breaks the Rep/Currency ScrollBox data render.
            if not EllesmereUIDB or (EllesmereUIDB.themedCharacterSheet ~= false and not EllesmereUI.BlizzWindowSkinsKilled()) then
                PreSkinCharacterSheet()
                -- PreSkin hides the portrait once; Blizzard's CharacterFrameMixin:UpdatePortrait
                -- (RefreshDisplay/UNIT_PORTRAIT_UPDATE/spec icon) runs after OnShow hooks and redraws it -- re-hide via secure hook + deferred GetPortrait() passes too.
                if not GetFFD(CharacterFrame)._euiPortraitSuppressRegistered then
                    local function SuppressCharacterFramePortrait()
                        if EllesmereUIDB and (EllesmereUIDB.themedCharacterSheet == false or EllesmereUI.BlizzWindowSkinsKilled()) then return end
                        if not CharacterFrame then return end
                        -- Blizzard re-anchors CharacterFrameInsetRight (parent of PaperDollSidebarTabs,
                        -- Tab1 = circular player/spec portrait) on each open; re-park it off-screen as PreSkin does.
                        local inset = _G.CharacterFrameInsetRight
                        if inset then
                            if inset.NineSlice then inset.NineSlice:Hide() end
                            inset:ClearAllPoints()
                            inset:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", 10000, -10000)
                        end
                        if CharacterFrame.Portrait then
                            CharacterFrame.Portrait:SetShown(false)
                            CharacterFrame.Portrait:SetAlpha(0)
                        end
                        local named = _G.CharacterFramePortrait
                        if named then
                            named:SetShown(false)
                            named:SetAlpha(0)
                            if named.EnableMouse then named:EnableMouse(false) end
                        end
                        if CharacterFrame.GetPortrait then
                            local tex = CharacterFrame:GetPortrait()
                            if tex then
                                if tex.SetShown then tex:SetShown(false) end
                                if tex.SetAlpha then tex:SetAlpha(0) end
                            end
                        end
                    end

                    local function RegisterPortraitSuppression()
                        if not CharacterFrame or not CharacterFrame.UpdatePortrait then return false end
                        if GetFFD(CharacterFrame)._euiPortraitSuppressRegistered then return true end
                        GetFFD(CharacterFrame)._euiPortraitSuppressRegistered = true

                        CharacterFrame:HookScript("OnShow", function()
                            SuppressCharacterFramePortrait()
                            C_Timer.After(0, SuppressCharacterFramePortrait)
                            C_Timer.After(0.05, SuppressCharacterFramePortrait)
                        end)

                        hooksecurefunc(CharacterFrame, "UpdatePortrait", function()
                            if EllesmereUIDB and (EllesmereUIDB.themedCharacterSheet == false or EllesmereUI.BlizzWindowSkinsKilled()) then return end
                            SuppressCharacterFramePortrait()
                        end)

                        if CharacterFrame.RefreshDisplay then
                            hooksecurefunc(CharacterFrame, "RefreshDisplay", function()
                                if EllesmereUIDB and (EllesmereUIDB.themedCharacterSheet == false or EllesmereUI.BlizzWindowSkinsKilled()) then return end
                                SuppressCharacterFramePortrait()
                            end)
                        end

                        if CharacterFrame.SetPortraitToSpecIcon then
                            hooksecurefunc(CharacterFrame, "SetPortraitToSpecIcon", function()
                                if EllesmereUIDB and (EllesmereUIDB.themedCharacterSheet == false or EllesmereUI.BlizzWindowSkinsKilled()) then return end
                                SuppressCharacterFramePortrait()
                            end)
                        end

                        local portrait = _G.CharacterFramePortrait
                        if portrait then
                            portrait:HookScript("OnShow", function(self)
                                if EllesmereUIDB and (EllesmereUIDB.themedCharacterSheet == false or EllesmereUI.BlizzWindowSkinsKilled()) then return end
                                self:SetShown(false)
                                self:SetAlpha(0)
                            end)
                        end

                        SuppressCharacterFramePortrait()
                        return true
                    end

                    if not RegisterPortraitSuppression() then
                        local tries = 0
                        local ticker
                        ticker = C_Timer.NewTicker(0.25, function()
                            tries = tries + 1
                            if RegisterPortraitSuppression() or tries >= 40 then
                                ticker:Cancel()
                            end
                        end)
                    end
                end
            end

            -- Heavy skin (model, slots, stats, tabs) defers to first OnShow.
            CharacterFrame:HookScript("OnShow", ApplyThemedCharacterSheet)

            -- Detect and record which equipment set is fully equipped.
            local function UpdateActiveEquipmentSet()
                local setIDs = C_EquipmentSet.GetEquipmentSetIDs()
                if setIDs then
                    for _, setID in ipairs(setIDs) do
                        local setItems = GetEquipmentSetItemIDs(setID)
                        if setItems then
                            local allMatch = true
                            for slotIndex, itemID in pairs(setItems) do
                                if itemID ~= 0 then
                                    local currentItemID = GetInventoryItemID("player", slotIndex)
                                    if currentItemID ~= itemID then
                                        allMatch = false
                                        break
                                    end
                                end
                            end
                            if allMatch then
                                activeEquipmentSetID = setID
                                return
                            end
                        end
                    end
                end
                activeEquipmentSetID = nil
            end

            -- Auto-equip equipment set when spec changes
            local specChangeFrame = CreateFrame("Frame")
            local lastSpecIndex = GetSpecialization()
            specChangeFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
            specChangeFrame:RegisterEvent("EQUIPMENT_SETS_CHANGED")
            specChangeFrame:SetScript("OnEvent", function(self, event)
                if event == "EQUIPMENT_SETS_CHANGED" then
                    -- UpdateActiveEquipmentSet() is unavailable in the current WoW API and
                    -- RefreshEquipmentSets() is out of scope here; the equipment panel refresh is owned by equipSetChangeFrame.
                    if CharacterFrame and CharacterFrame:IsShown() and GetFFD(CharacterFrame).equipPanel and GetFFD(CharacterFrame).equipPanel:IsShown() then
                    end
                else
                    -- Auto-equip when spec actually changes (not just event noise)
                    local currentSpecIndex = GetSpecialization()
                    if currentSpecIndex ~= lastSpecIndex then
                        lastSpecIndex = currentSpecIndex
                        local setIDs = C_EquipmentSet.GetEquipmentSetIDs()
                        if setIDs then
                            for _, setID in ipairs(setIDs) do
                                local assignedSpec = C_EquipmentSet.GetEquipmentSetAssignedSpec(setID)
                                if assignedSpec then
                                    if assignedSpec == currentSpecIndex then
                                        EUI_EquipSet(setID)
                                        activeEquipmentSetID = setID
                                        if EllesmereUIDB then
                                            EllesmereUIDB.lastEquippedSet = setID
                                        end
                                        break
                                    end
                                end
                            end
                        end
                    end
                end
            end)

            -- Initialize active set on login
            local loginFrame = CreateFrame("Frame")
            loginFrame:RegisterEvent("PLAYER_LOGIN")
            loginFrame:SetScript("OnEvent", function()
                loginFrame:UnregisterEvent("PLAYER_LOGIN")
                if EllesmereUIDB and EllesmereUIDB.lastEquippedSet then
                    activeEquipmentSetID = EllesmereUIDB.lastEquippedSet
                end
            end)
        end
    end)
end

-- Apply the char-sheet label size / outline / shadow settings.
function EllesmereUI._applyCharSheetTextSizes()
    if not CharacterFrame then return end

    local itemLevelSize = EllesmereUIDB and EllesmereUIDB.charSheetItemLevelSize or 11
    local upgradeTrackSize = EllesmereUIDB and EllesmereUIDB.charSheetUpgradeTrackSize or 11
    local enchantSize = EllesmereUIDB and EllesmereUIDB.charSheetEnchantSize or 9

    local itemLevelShadow = EllesmereUIDB and EllesmereUIDB.charSheetItemLevelShadow or false
    local itemLevelOutline = EllesmereUIDB and EllesmereUIDB.charSheetItemLevelOutline or false
    local upgradeTrackShadow = EllesmereUIDB and EllesmereUIDB.charSheetUpgradeTrackShadow or false
    local upgradeTrackOutline = EllesmereUIDB and EllesmereUIDB.charSheetUpgradeTrackOutline or false
    local enchantShadow = EllesmereUIDB and EllesmereUIDB.charSheetEnchantShadow or false
    local enchantOutline = EllesmereUIDB and EllesmereUIDB.charSheetEnchantOutline or false

    local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("blizzardSkin") or STANDARD_TEXT_FONT

    local itemSlots = EUI_GEAR_SLOTS

    for _, slotName in ipairs(itemSlots) do
        local slot = _G[slotName]
        if slot then
            if GetFFD(slot).itemLevelLabel then
                local flags = ""
                if itemLevelOutline then
                    flags = "OUTLINE, SLUG"
                end
                if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(GetFFD(slot).itemLevelLabel, itemLevelShadow) end
                GetFFD(slot).itemLevelLabel:SetFont(fontPath, itemLevelSize, flags)
            end
            if GetFFD(slot).upgradeTrackLabel then
                local flags = ""
                if upgradeTrackOutline then
                    flags = "OUTLINE, SLUG"
                end
                if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(GetFFD(slot).upgradeTrackLabel, upgradeTrackShadow) end
                GetFFD(slot).upgradeTrackLabel:SetFont(fontPath, upgradeTrackSize, flags)
            end
            if GetFFD(slot).enchantLabel then
                local flags = ""
                if enchantOutline then
                    flags = "OUTLINE, SLUG"
                end
                if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(GetFFD(slot).enchantLabel, enchantShadow) end
                GetFFD(slot).enchantLabel:SetFont(fontPath, enchantSize, flags)
            end
        end
    end
end

function EllesmereUI._applyCharSheetItemColors()
    if not CharacterFrame then return end

    local itemSlots = EUI_GEAR_SLOTS

    for _, slotName in ipairs(itemSlots) do
        local slot = _G[slotName]
        if slot and GetFFD(slot).itemLevelLabel then
            local itemLink = GetInventoryItemLink("player", slot:GetID())
            if itemLink then
                local _, _, quality = GetItemInfo(itemLink)
                -- Use rarity color by default, unless explicitly disabled
                if (not EllesmereUIDB or EllesmereUIDB.charSheetColorItemLevel ~= false) and quality then
                    local r, g, b = GetItemQualityColor(quality)
                    GetFFD(slot).itemLevelLabel:SetTextColor(r, g, b, 0.9)
                else
                    GetFFD(slot).itemLevelLabel:SetTextColor(1, 1, 1, 0.9)
                end
            else
                GetFFD(slot).itemLevelLabel:SetTextColor(1, 1, 1, 0.9)
            end
        end
    end
end

function EllesmereUI._refreshCharacterSheetColors()
    local charFrame = CharacterFrame
    if not charFrame or not GetFFD(charFrame).statsSections then return end

    -- Default category colors
    local DEFAULT_CATEGORY_COLORS = {
        Attributes = { r = 0.047, g = 0.824, b = 0.616 },
        ["Secondary Stats"] = { r = 0.471, g = 0.255, b = 0.784 },
        ["Tertiary Stats"] = { r = 0.859, g = 0.325, b = 0.855 },
        Attack = { r = 1, g = 0.353, b = 0.122 },
        Defense = { r = 0.247, g = 0.655, b = 1 },
        Crests = { r = 1, g = 0.784, b = 0.341 },
        PvP = { r = 0.671, g = 0.431, b = 0.349 },
    }

    local function GetCategoryColor(title)
        local useCustom = EllesmereUIDB and EllesmereUIDB.statCategoryUseColor and EllesmereUIDB.statCategoryUseColor[title]
        if useCustom then
            local custom = EllesmereUIDB and EllesmereUIDB.statCategoryColors and EllesmereUIDB.statCategoryColors[title]
            if custom then return custom end
        end
        return DEFAULT_CATEGORY_COLORS[title] or { r = 1, g = 1, b = 1 }
    end

    -- Recolor each section by its persisted colorKey (DB key), not display title, so mismatches like "Secondary" vs "Secondary Stats" resolve correctly.
    for _, sectionData in ipairs(GetFFD(charFrame).statsSections) do
        local key = sectionData.colorKey or sectionData.sectionTitle
        local newColor = GetCategoryColor(key)

        if sectionData.titleFS then
            sectionData.titleFS:SetTextColor(newColor.r, newColor.g, newColor.b, 1)
        end
        if sectionData.leftBar then
            sectionData.leftBar:SetColorTexture(newColor.r, newColor.g, newColor.b, 0.8)
        end
        if sectionData.rightBar then
            sectionData.rightBar:SetColorTexture(newColor.r, newColor.g, newColor.b, 0.8)
        end
        if sectionData.upIcon then
            sectionData.upIcon:SetVertexColor(newColor.r, newColor.g, newColor.b, 1)
        end
        if sectionData.downIcon then
            sectionData.downIcon:SetVertexColor(newColor.r, newColor.g, newColor.b, 1)
        end
        for _, stat in ipairs(sectionData.stats) do
            if stat.value then
                stat.value:SetTextColor(newColor.r, newColor.g, newColor.b, 1)
            end
        end
    end
end

-- Re-apply the equipment-icon crop when Icon Zoom changes (texcoord persists across item swaps, so only slider changes need this).
function EllesmereUI._refreshCharSheetIconZoom()
    -- Only the themed sheet crops its slot icons; if off, slots show Blizzard's default icons, which we must not re-crop.
    if EllesmereUIDB and (EllesmereUIDB.themedCharacterSheet == false or EllesmereUI.BlizzWindowSkinsKilled()) then return end
    local z = (EllesmereUIDB and EllesmereUIDB.charSheetIconZoom) or 0.07
    for _, slotName in ipairs(EUI_ALL_SLOTS) do
        local slot = _G[slotName]
        if slot and slot.icon then
            slot.icon:SetTexCoord(z, 1 - z, z, 1 - z)
        end
    end
end

function EllesmereUI._refreshUpgradeTrackVisibility()
    local itemSlots = EUI_GEAR_SLOTS

    local showUpgradeTrack = (not EllesmereUIDB) or (EllesmereUIDB.showUpgradeTrack ~= false)

    for _, slotName in ipairs(itemSlots) do
        local slot = _G[slotName]
        if slot and GetFFD(slot).upgradeTrackLabel then
            if showUpgradeTrack then
                GetFFD(slot).upgradeTrackLabel:Show()
            else
                GetFFD(slot).upgradeTrackLabel:Hide()
            end
        end
    end
end

function EllesmereUI._refreshEnchantsVisibility()
    local itemSlots = EUI_GEAR_SLOTS

    local showEnchants = (not EllesmereUIDB) or (EllesmereUIDB.showEnchants ~= false)

    for _, slotName in ipairs(itemSlots) do
        local slot = _G[slotName]
        if slot and GetFFD(slot).enchantLabel then
            if showEnchants then
                GetFFD(slot).enchantLabel:Show()
                if GetFFD(slot).enchantHoverFrame then GetFFD(slot).enchantHoverFrame:Show() end
            else
                GetFFD(slot).enchantLabel:Hide()
                if GetFFD(slot).enchantHoverFrame then GetFFD(slot).enchantHoverFrame:Hide() end
            end
        end
    end
end

function EllesmereUI._refreshEnchantsColors()
    local itemSlots = EUI_GEAR_SLOTS

    for _, slotName in ipairs(itemSlots) do
        local slot = _G[slotName]
        if slot and GetFFD(slot).enchantLabel then
            local displayColor
            if EllesmereUIDB and EllesmereUIDB.charSheetEnchantUseColor and EllesmereUIDB.charSheetEnchantColor then
                displayColor = EllesmereUIDB.charSheetEnchantColor
            else
                displayColor = { r = 1, g = 1, b = 1 }
            end

            GetFFD(slot).enchantLabel:SetTextColor(displayColor.r, displayColor.g, displayColor.b, 1)
        end
    end
end

function EllesmereUI._refreshItemLevelVisibility()
    local itemSlots = EUI_GEAR_SLOTS

    local showItemLevel = (not EllesmereUIDB) or (EllesmereUIDB.showItemLevel ~= false)

    for _, slotName in ipairs(itemSlots) do
        local slot = _G[slotName]
        if slot and GetFFD(slot).itemLevelLabel then
            if showItemLevel then
                GetFFD(slot).itemLevelLabel:Show()
            else
                GetFFD(slot).itemLevelLabel:Hide()
            end
        end
    end
end

function EllesmereUI._refreshItemLevelColors()
    local itemSlots = EUI_GEAR_SLOTS

    for _, slotName in ipairs(itemSlots) do
        local slot = _G[slotName]
        if slot and GetFFD(slot).itemLevelLabel then
            local displayColor
            if EllesmereUIDB and EllesmereUIDB.charSheetItemLevelUseColor and EllesmereUIDB.charSheetItemLevelColor then
                displayColor = EllesmereUIDB.charSheetItemLevelColor
            else
                -- Rarity color by default, unless explicitly disabled.
                local itemLink = GetInventoryItemLink("player", slot:GetID())
                if itemLink and (not EllesmereUIDB or EllesmereUIDB.charSheetColorItemLevel ~= false) then
                    local _, _, quality = GetItemInfo(itemLink)
                    if quality then
                        local r, g, b = GetItemQualityColor(quality)
                        displayColor = { r = r, g = g, b = b }
                    else
                        displayColor = { r = 1, g = 1, b = 1 }
                    end
                else
                    displayColor = { r = 1, g = 1, b = 1 }
                end
            end

            GetFFD(slot).itemLevelLabel:SetTextColor(displayColor.r, displayColor.g, displayColor.b, 0.9)
        end
    end
end

function EllesmereUI._refreshUpgradeTrackColors()
    local itemSlots = EUI_GEAR_SLOTS

    for _, slotName in ipairs(itemSlots) do
        local slot = _G[slotName]
        if slot and GetFFD(slot).upgradeTrackLabel then
            local itemLink = GetInventoryItemLink("player", slot:GetID())
            if itemLink then
                -- Upgrade track color via C_Item.GetItemUpgradeInfo (no tooltip).
                local _, upgradeTrackColor = EUI_GetUpgradeTrack(itemLink)

                local displayColor
                if EllesmereUIDB and EllesmereUIDB.charSheetUpgradeTrackUseColor and EllesmereUIDB.charSheetUpgradeTrackColor then
                    displayColor = EllesmereUIDB.charSheetUpgradeTrackColor
                else
                    displayColor = upgradeTrackColor
                end

                GetFFD(slot).upgradeTrackLabel:SetTextColor(displayColor.r, displayColor.g, displayColor.b, 0.8)
            end
        end
    end
end
