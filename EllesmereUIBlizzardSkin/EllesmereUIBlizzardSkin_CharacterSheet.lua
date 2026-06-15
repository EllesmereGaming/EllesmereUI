--------------------------------------------------------------------------------
--  Themed Character Sheet
--------------------------------------------------------------------------------
local ADDON_NAME = ...
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

-- Prefer EquipmentManager_EquipSet (cleaner from insecure code) over the
-- raw C_EquipmentSet API. Callers must combat-guard.
local function EUI_EquipSet(setID)
    if not setID then return end
    if EquipmentManager_EquipSet then
        EquipmentManager_EquipSet(setID)
    else
        C_EquipmentSet.UseEquipmentSet(setID)
    end
end

-- C_TooltipInfo-based scanning. NEVER create a scanning GameTooltipTemplate
-- from Lua -- see CLAUDE.md reference_tooltip_template_taint.
local function EUI_ScanInventoryItem(slotID, unit)
    if not (C_TooltipInfo and C_TooltipInfo.GetInventoryItem) then return nil end
    local data = C_TooltipInfo.GetInventoryItem(unit or "player", slotID)
    if not data then return nil end
    if TooltipUtil and TooltipUtil.SurfaceArgs then
        TooltipUtil.SurfaceArgs(data)
    end
    return data
end

-- Upgrade track lookup lives in parent addon (EllesmereUI.lua) so Bags can
-- share it.  Local alias for the hot path.
local EUI_GetUpgradeTrack = EllesmereUI.GetUpgradeTrack

-- Language-agnostic: prefers line-type match
-- (Enum.TooltipDataLineType.ItemEnchantmentPermanent / 15), falls back to a
-- regex built from Blizzard's localized ENCHANTED_TOOLTIP_LINE global.
-- Cached by enchantID per session.
local _enchantNameCache = {}
local _ENCHANT_LINE_TYPE = (Enum and Enum.TooltipDataLineType
    and (Enum.TooltipDataLineType.ItemEnchantmentPermanent
         or Enum.TooltipDataLineType.ItemEnchant))
    or 15

-- Build a Lua pattern from "Enchanted: %s", escaping magic chars and
-- turning %s into the capture group.
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
    -- Preserve |A:...|a atlas escapes (the enchant renderer keeps the
    -- atlas icon and hides the text). Only strip color escapes + leading +/&.
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

-- Gem socket icons: one pass over GetItemStats + C_Item.GetItemGem (no tooltip).
-- Enchants use EUI_ScanInventoryItem; no GameTooltipTemplate (CLAUDE.md).

-- paintPasses: current euiGemPaintPasses for this slot (suppress empty-socket
-- atlas rows for the first frames after /reload while gem bytes hydrate).
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

-- Default the themed character sheet + its sub-displays to enabled on first
-- install. Each key is only stamped when it is nil, so users who have
-- explicitly turned anything off keep their choice.
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
        }
        for k, v in pairs(defaults) do
            if EllesmereUIDB[k] == nil then
                EllesmereUIDB[k] = v
            end
        end
    end)
end

-- Lightweight pre-skin: chrome hides, bg, inset. Safe to run while
-- CharacterFrame is hidden (before first open). Avoids the bug where
-- running mid-OnShow prevents Rep/Currency ScrollBox data render.
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
    -- Background scales proportionally to fill the frame without distorting.
    -- Native aspect ratio: 561x433. On resize, compute the size that covers
    -- the full frame (like CSS "cover") and center it, clipping overflow via
    -- adjusted tex coords.
    local BG_ASPECT = 561 / 433
    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\modern_blizz.png")
    bg:SetAllPoints(frame)
    GetFFD(frame).bg = bg
    bg:SetAlpha(1)
    GetFFD(frame).bgOverlay = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    GetFFD(frame).bgOverlay:SetColorTexture(0, 0, 0, 0.55)
    GetFFD(frame).bgOverlay:SetAllPoints(frame)

    -- Recompute tex coords on resize to maintain aspect ratio (cover mode)
    local BASE_L, BASE_R, BASE_T, BASE_B = 0.25, 1, 0, 0.75
    local BASE_U = BASE_R - BASE_L  -- 0.75
    local BASE_V = BASE_B - BASE_T  -- 0.75
    local function UpdateBgTexCoords()
        local fw, fh = frame:GetSize()
        if fw == 0 or fh == 0 then return end
        local frameAspect = fw / fh
        if frameAspect > BG_ASPECT then
            -- Frame is wider: crop top/bottom
            local visV = BASE_V * (BG_ASPECT / frameAspect)
            local trimV = (BASE_V - visV) / 2
            bg:SetTexCoord(BASE_L, BASE_R, BASE_T + trimV, BASE_B - trimV)
        else
            -- Frame is taller: crop left/right
            local visU = BASE_U * (frameAspect / BG_ASPECT)
            local trimU = (BASE_U - visU) / 2
            bg:SetTexCoord(BASE_L + trimU, BASE_R - trimU, BASE_T, BASE_B)
        end
    end
    hooksecurefunc(frame, "SetSize", UpdateBgTexCoords)
    hooksecurefunc(frame, "SetWidth", UpdateBgTexCoords)
    hooksecurefunc(frame, "SetHeight", UpdateBgTexCoords)
    UpdateBgTexCoords()
    if EllesmereUI and EllesmereUI.PanelPP then
        EllesmereUI.PanelPP.CreateBorder(frame, 0.2, 0.2, 0.2, 1, 1, "OVERLAY", 7)
    end

    -- PlayerModel widget. SetUnit("player") natively follows shapeshift forms
    -- (Bear/Cat/Travel/Moonkin/Tree) and Dracthyr Visage -- no preset tricks
    -- needed. Backdrop + hover glow live on a sibling frame (3D model draws on top).
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

        GetFFD(frame).modelScene = myModel  -- name retained for back-compat with older refs
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
                -- Model:SetPosition(forward, side, up). Depth is fixed so
                -- panning slides the model in screen space only.
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


        -- SetUnit handles form transitions natively; re-bind on equipment
        -- changes so newly-equipped gear shows up on the model.
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

    -- Grid layout via SetPoint only. Never reparent -- slots are secure and
    -- reparenting them would taint the paper-doll.
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



    -- Hide the two extra regions on weapon slots (indices 16/17 are the
    -- ornamented border/frame textures). Shifting texcoords off-atlas is
    -- cheaper than SetTexture("") and survives Blizzard re-applying the atlas.
    select(16, _G.CharacterMainHandSlot:GetRegions()):SetTexCoord(.8,.8,.8,.8,.8,.8,.8,.8)
    select(17, _G.CharacterMainHandSlot:GetRegions()):SetTexCoord(.8,.8,.8,.8,.8,.8,.8,.8)
    select(16, _G.CharacterSecondaryHandSlot:GetRegions()):SetTexCoord(.8,.8,.8,.8,.8,.8,.8,.8)
    select(17, _G.CharacterSecondaryHandSlot:GetRegions()):SetTexCoord(.8,.8,.8,.8,.8,.8,.8,.8)

    -- Strip icon borders on the equipment slots and crop icon texcoords
    -- so they fill the slot cleanly.
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
                iconTexture:SetTexCoord(.07,.07,.07,.93,.93,.07,.93,.93)
            end
            local normalTexture = _G[slotName .. "NormalTexture"]
            if normalTexture then
                normalTexture:Hide()
            end
        end
    end

    -- Re-apply to weapon-slot regions 16/17 after the loop above may have
    -- clobbered them (the slots are also in slotsToHide).
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

    -- Scale fully owned by Blizzard (SetScale on secure panels taints
    -- UIParentPanelManager execution context).
    frame:SetFrameStrata("HIGH")

    -- Frame size is entirely Blizzard's -- no SetWidth/SetHeight or OnUpdate
    -- enforcers on the secure frame. Our layout fits inside native dimensions.
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
            if region and region:IsObjectType("Texture") then
                region:SetAlpha(0)
            end
        end

        local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("blizzardSkin") or STANDARD_TEXT_FONT

        GetFFD(closeBtn).x = closeBtn:CreateFontString(nil, "OVERLAY")
        GetFFD(closeBtn).x:SetFont(fontPath, 16, "")
        GetFFD(closeBtn).x:SetText("x")
        GetFFD(closeBtn).x:SetTextColor(1, 1, 1, 0.75)
        GetFFD(closeBtn).x:SetPoint("CENTER", -2, -3)

        closeBtn:HookScript("OnEnter", function()
            if GetFFD(closeBtn).x then GetFFD(closeBtn).x:SetTextColor(1, 1, 1, 1) end
        end)
        closeBtn:HookScript("OnLeave", function()
            if GetFFD(closeBtn).x then GetFFD(closeBtn).x:SetTextColor(1, 1, 1, 0.75) end
        end)
    end

    local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("blizzardSkin") or STANDARD_TEXT_FONT
    local EG = EllesmereUI.ELLESMERE_GREEN or { r = 0.51, g = 0.784, b = 1 }

    for i = 1, 3 do
        local tab = _G["CharacterFrameTab" .. i]
        if tab then
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

    local function UpdateTabVisuals()
        for i = 1, 3 do
            local tab = _G["CharacterFrameTab" .. i]
            if tab then
                -- PanelTemplates_GetSelectedTab is unreliable here -- Blizzard
                -- updates frame.selectedTab before the template helper agrees.
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

    -- Show/Hide on secure slot buttons during combat fires ADDON_ACTION_BLOCKED
    -- and can taint. Defer those calls to PLAYER_REGEN_ENABLED. One shared
    -- deferred frame handles bursts of tab changes without leaking event regs.
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

    -- Faint atlas background on Reputation + Currency panes. Idempotent via
    -- _euiBg tag. Anchors to the inner ScrollBox so the texture stays inside
    -- the list area and doesn't bleed over the tab chrome.
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

    -- Tab visibility dispatcher. We hook each sub-pane's OnShow rather than
    -- intercept PanelTemplates_SetTab -- Blizzard drives visibility, we react.
    --
    -- Pane OnShow fires from inside the secure ShowSubFrame path. Any explicit
    -- :Show()/:Hide() reached from that stack (even on our own named or
    -- SecureActionButtonTemplate frames) is flagged as a protected call.
    -- SetShown is NOT flagged, so every visibility toggle below uses SetShown.
    local function ApplyTabVisibility(isCharacterTab)
        UpdateTabVisuals()
        -- Swapping back to the Character bottom-tab also needs to re-highlight
        -- our top-row Character button (hook installed below as _reactivateCharTab).
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

    -- Stats panel: fixed 200px wide, stretches from 60px below top to 10px above bottom.
    local statsPanel = CreateFrame("Frame", "EUI_CharSheet_StatsPanel", frame)
    statsPanel:SetWidth(190)
    statsPanel:SetPoint("TOPLEFT",    frame, "TOPLEFT",    345, -60)
    statsPanel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 345,  40)
    statsPanel:SetFrameLevel(50)

    -- Sidebar background: lives on frame (not statsPanel) so it stays visible
    -- when switching between Character / Titles / Equipment panels.
    local sidebarBgFrame = CreateFrame("Frame", nil, frame)
    sidebarBgFrame:SetFrameLevel(statsPanel:GetFrameLevel() - 1)
    sidebarBgFrame:SetPoint("TOPLEFT", statsPanel, "TOPLEFT", -51, 10)
    sidebarBgFrame:SetPoint("BOTTOMRIGHT", statsPanel, "BOTTOMRIGHT", 0, -10)
    local statsBg = sidebarBgFrame:CreateTexture(nil, "BACKGROUND")
    statsBg:SetColorTexture(0, 0, 0, 0.2)
    statsBg:SetAllPoints()
    GetFFD(frame).statsBg = statsBg
    GetFFD(frame).sidebarBgFrame = sidebarBgFrame

    -- Map INVTYPE to inventory slot numbers and display names
    local INVTYPE_TO_SLOT = {
        INVTYPE_HEAD = {slot = 1, name = "Head"},
        INVTYPE_NECK = {slot = 2, name = "Neck"},
        INVTYPE_SHOULDER = {slot = 3, name = "Shoulder"},
        INVTYPE_CHEST = {slot = 5, name = "Chest"},
        INVTYPE_WAIST = {slot = 6, name = "Waist"},
        INVTYPE_LEGS = {slot = 7, name = "Legs"},
        INVTYPE_FEET = {slot = 8, name = "Feet"},
        INVTYPE_WRIST = {slot = 9, name = "Wrist"},
        INVTYPE_HAND = {slot = 10, name = "Hands"},
        INVTYPE_FINGER = {slots = {11, 12}, name = "Ring"},
        INVTYPE_TRINKET = {slots = {13, 14}, name = "Trinket"},
        INVTYPE_BACK = {slot = 15, name = "Back"},
        INVTYPE_MAINHAND = {slot = 16, name = "Main Hand"},
        INVTYPE_OFFHAND = {slot = 17, name = "Off Hand"},
        INVTYPE_RELIC = {slot = 18, name = "Relic"},
        INVTYPE_BODY = {slot = 4, name = "Body"},
        INVTYPE_SHIELD = {slot = 17, name = "Shield"},
        INVTYPE_2HWEAPON = {slot = 16, name = "Two-Hand"},
    }

    -- Function to get itemlevel of equipped item in a specific slot
    local function GetEquippedItemLevel(slot)
        local itemLink = GetInventoryItemLink("player", slot)
        if itemLink then
            local _, _, _, itemLevel = GetItemInfo(itemLink)
            return tonumber(itemLevel) or 0
        end
        return 0
    end

    ---------------------------------------------------------------------------
    -- Spec-aware "better item" filter.
    --
    -- Hardcoded allowlist of weapon subclasses + shield/offhand usability per
    -- spec. Prevents Ret from seeing a shield (or Prot seeing a 2H polearm)
    -- as a "better item" just because its ilvl is higher.
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

    -- Cached scan of bag items that are upgrades over equipped gear.
    -- Invalidated by gear/bag changes while the character sheet is open.
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

    -- Cache is invalidated by the iLvlUpdateFrame event handler below
    -- (PLAYER_EQUIPMENT_CHANGED, BAG_UPDATE) and on CharacterFrame OnShow.

    _ComputeBetterInventoryItems = function()
        local betterItems = {}

        -- Check all bag slots (0 = backpack, 1-4 = bag slots)
        for bagSlot = 0, 4 do
            local bagSize = C_Container.GetContainerNumSlots(bagSlot)
            for slotIndex = 1, bagSize do
                local itemLink = C_Container.GetContainerItemLink(bagSlot, slotIndex)
                if itemLink then
                    local itemName, _, itemRarity, itemLevel, _, itemType, _, _, equipSlot, itemIcon = GetItemInfo(itemLink)
                    itemLevel = tonumber(itemLevel)

                    -- Only show Weapon and Armor items
                    if itemLevel and itemName and (itemType == "Weapon" or itemType == "Armor") and equipSlot then
                        -- Spec-aware usability filter (skip shields on Ret, etc.)
                        -- GetItemInfoInstant returns:
                        -- 1 itemID, 2 itemType, 3 itemSubType, 4 itemEquipLoc,
                        -- 5 iconFileID, 6 classID, 7 subClassID
                        local _, _, _, _, _, classID, subclassID = GetItemInfoInstant(itemLink)
                        if not IsItemUsableBySpec(itemLink, equipSlot, classID, subclassID) then
                            -- skip: not usable by current spec
                        else
                            -- Get the slot(s) this item can equip to
                            local slotInfo = INVTYPE_TO_SLOT[equipSlot]
                            if slotInfo then
                                local isBetter = false
                                local compareSlots = slotInfo.slots or {slotInfo.slot}

                                -- Check if item is better than ANY of its possible slots
                                for _, slot in ipairs(compareSlots) do
                                    local equippedLevel = GetEquippedItemLevel(slot)
                                    if itemLevel > equippedLevel then
                                        isBetter = true
                                        break
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

        -- Sort by level descending
        table.sort(deduped, function(a, b) return a.level > b.level end)

        return deduped
    end

    -- M+ Score display (single inline FontString above itemlevel).
    -- Number is uniquely colored via |cff...|r escapes based on score brackets.
    local mythicRatingLabel = statsPanel:CreateFontString(nil, "OVERLAY")
    mythicRatingLabel:SetFont(fontPath, 12, "")
    -- Positioned below iLvlText once that FontString exists (see below).
    mythicRatingLabel:SetTextColor(0.8, 0.8, 0.8, 1)
    mythicRatingLabel:SetText("M+ Score:")
    GetFFD(frame).mythicRatingLabel = mythicRatingLabel

    -- Legacy alias retained for call sites that test existence of the value
    -- FontString. The label now hosts both parts via color escapes.
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

    -- Button overlay for itemlevel tooltip
    local iLvlButton = CreateFrame("Button", nil, statsPanel)
    iLvlButton:SetPoint("TOPLEFT",     iLvlText, "TOPLEFT",     -10, 4)
    iLvlButton:SetPoint("BOTTOMRIGHT", iLvlText, "BOTTOMRIGHT", 10, -4)
    iLvlButton:SetFrameLevel(statsPanel:GetFrameLevel() + 3)
    iLvlButton:EnableMouse(true)
    iLvlButton:SetScript("OnEnter", function(self)
        local betterItems = GetBetterInventoryItems()

        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Equipped Item Level", 0.6, 0.2, 1, 1)

        if #betterItems > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(
                string.format("You have %d better item%s in inventory", #betterItems, #betterItems == 1 and "" or "s"),
                0.2, 1, 0.2
            )
            GameTooltip:AddLine(" ")

            -- Show up to 10 items with icons and slots (slot on right side)
            local maxShow = math.min(#betterItems, 10)
            for i = 1, maxShow do
                local item = betterItems[i]
                local leftText = string.format("|T%s:16|t  %s (iLvl %d)", item.icon, item.name, item.level)
                GameTooltip:AddDoubleLine(leftText, item.slot, 1, 1, 1, 0.7, 0.7, 0.7)
            end

            if #betterItems > 10 then
                GameTooltip:AddLine(
                    string.format("  ... and %d more", #betterItems - 10),
                    0.7, 0.7, 0.7
                )
            end
        else
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("No better items in inventory", 0.7, 0.7, 0.7, true)
        end

        -- Calculate minimum width based on longest item text
        local maxWidth = 250
        if #betterItems > 0 then
            local maxShow = math.min(#betterItems, 10)
            for i = 1, maxShow do
                local item = betterItems[i]
                local text = string.format("%s (iLvl %d) - %s", item.name, item.level, item.slot)
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

    -- Function to update itemlevel, PvP ilvl, and mythic+ rating
    local function UpdateItemLevelDisplay()
        local avgItemLevel, avgItemLevelEquipped, avgItemLevelPvP = GetAverageItemLevel()
        -- Format with two decimals
        local avgFormatted = format("%.2f", avgItemLevel)
        local avgEquippedFormatted = format("%.2f", avgItemLevelEquipped)

        -- Show "/ max" only when (a) there's a spec-usable upgrade in bags, AND
        -- (b) the max number actually differs from the equipped number. If the
        -- two are equal the suffix is redundant; if there are no usable upgrades
        -- the max reflects filtered items the user can't equip.
        local betterItemsNow = GetBetterInventoryItems()
        if avgEquippedFormatted ~= avgFormatted and #betterItemsNow > 0 then
            iLvlText:SetText(format("%s / %s", avgEquippedFormatted, avgFormatted))
        else
            iLvlText:SetText(avgEquippedFormatted)
        end

        -- Update PvP Item Level if option is enabled
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

        -- Update M+ Score if option is enabled. Tab guard mirrors the slot-
        -- label fix: PaperDollFrame:IsShown() is the truth-source for whether
        -- the Character sub-pane is active (selectedTab is unreliable on the
        -- initial open path).
        if EllesmereUIDB and EllesmereUIDB.showMythicRating and GetFFD(frame).mythicRatingLabel then
            local mythicRating = C_ChallengeMode.GetOverallDungeonScore()
            if mythicRating and mythicRating > 0 then
                local score = math.floor(mythicRating)
                local hex = GetMPScoreHex(score)
                GetFFD(frame).mythicRatingLabel:SetText(string.format("M+ Score: |cff%s%d|r", hex, score))
                GetFFD(frame).mythicRatingLabel:SetShown(isCharTab)
            else
                GetFFD(frame).mythicRatingLabel:Hide()
            end
        elseif GetFFD(frame).mythicRatingLabel then
            GetFFD(frame).mythicRatingLabel:Hide()
        end
    end

    -- Event-driven refresh of the center stats panel (ilvl + M+ score). Zero
    -- cost when idle: only fires on inventory/spec/challenge-mode changes and
    -- once when the character panel opens.
    local iLvlUpdateFrame = CreateFrame("Frame")
    iLvlUpdateFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    iLvlUpdateFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
    iLvlUpdateFrame:RegisterEvent("BAG_UPDATE")
    iLvlUpdateFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    iLvlUpdateFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    iLvlUpdateFrame:RegisterEvent("PLAYER_AVG_ITEM_LEVEL_UPDATE")
    iLvlUpdateFrame:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_INVENTORY_CHANGED" and unit ~= "player" then return end
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

    --[[ Stats panel border
    if EllesmereUI and EllesmereUI.PanelPP then
        EllesmereUI.PanelPP.CreateBorder(statsPanel, 0.15, 0.15, 0.15, 1, 1, "OVERLAY", 1)
    end
    ]]--

    -- Scroll frame starts below the button + iLvl + M+ header and stretches
    -- to the bottom-right of the panel. Right padding leaves room for the
    -- scrollbar (8px wide + a couple px breathing room).
    -- Header height = buttonHeight(25) + iLvl(18) + M+(12) + gaps(~14) = ~70.
    local HEADER_H = 75
    local scrollFrame = CreateFrame("ScrollFrame", "EUI_CharSheet_ScrollFrame", statsPanel)
    scrollFrame:SetPoint("TOPLEFT", statsPanel, "TOPLEFT", 0, -HEADER_H)
    scrollFrame:SetPoint("BOTTOMRIGHT", statsPanel, "BOTTOMRIGHT", -12, 2)
    scrollFrame:SetFrameLevel(51)
    GetFFD(frame).scrollFrame = scrollFrame

    -- Scroll child: no anchors (scroll frame positions it internally).
    -- Width is set dynamically to match the scroll frame whenever the
    -- panel sizes change.
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

    -- Custom thin scrollbar: pinned to the owner frame's right edge, thumb
    -- responds to wheel + drag. Opts: trackOwner (frame the track pins to),
    -- topInset/bottomInset, rightInset. Returns the track frame so callers
    -- can toggle :Show()/:Hide() for tab-based visibility.
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

        scrollFrame:EnableMouseWheel(true)
        scrollFrame:SetScript("OnMouseWheel", function(_, delta)
            local _, _, maxScroll = _info()
            if maxScroll <= 0 then return end
            local newScroll = math.max(0, math.min(maxScroll, scrollFrame:GetVerticalScroll() - delta * SCROLL_STEP_PX))
            scrollFrame:SetVerticalScroll(newScroll)
        end)

        -- Drag state + handler. OnUpdate is installed only during an active
        -- drag, then cleared. Otherwise this would run every frame on every
        -- visible scrollbar (stats + titles = ~120 calls/sec idle).
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
    GetFFD(frame).scrollBar         = scrollTrack
    GetFFD(frame).updateScrollThumb = scrollTrack._update

    -- Re-anchor the scroll frame + track top edge based on whether the
    -- PvP iLvl and M+ Score lines are visible. Each hidden line collapses
    -- 16px of dead space so the stat sections start higher.
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
        -- HEADER_H includes space for M+ (one extra line). Each hidden
        -- line collapses 16px; each additional line beyond M+ adds 16px.
        local h = HEADER_H
        if not showMP then h = h - 16 end
        if showPvP then h = h + 16 end
        scrollFrame:ClearAllPoints()
        scrollFrame:SetPoint("TOPLEFT",     statsPanel, "TOPLEFT",     0,  -h)
        scrollFrame:SetPoint("BOTTOMRIGHT", statsPanel, "BOTTOMRIGHT", -12, 2)
        scrollTrack:ClearAllPoints()
        scrollTrack:SetPoint("TOPRIGHT",    statsPanel, "TOPRIGHT",    -2, -h)
        scrollTrack:SetPoint("BOTTOMRIGHT", statsPanel, "BOTTOMRIGHT", -2,  0)
        if GetFFD(frame).updateScrollThumb then GetFFD(frame).updateScrollThumb() end
    end
    EllesmereUI._updateScrollHeaderOffset()

    -- Helper function to get crest values
    local function GetCrestValue(currencyID)
        if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
            local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
            if info then
                return info.quantity or 0
            end
        end
        return 0
    end

    -- Crest maximum values (per season)
    local crestMaxValues = {
        [3347] = 400,  -- Myth
        [3345] = 400,  -- Hero
        [3343] = 700,  -- Champion
        [3341] = 700,  -- Veteran
        [3383] = 700,  -- Adventurer
    }

    -- Helper function to get crest maximum value (now using API to get seasonal max)
    local function GetCrestMaxValue(currencyID)
        local currencyInfo = C_CurrencyInfo.GetCurrencyInfo(currencyID)
        if currencyInfo and currencyInfo.maxQuantity then
            return currencyInfo.maxQuantity
        end
        return crestMaxValues[currencyID] or 3000  -- Fallback to hardcoded values if API fails
    end

    -- Check if a stat should be shown based on class/spec conditions
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

    -- Per-crest visibility. Each crest stat carries a showCrestKey; the
    -- user can toggle each crest individually via the options cog. Default
    -- is visible when the DB key is absent.
    local function ShouldShowCrest(stat)
        if not stat or not stat.showCrestKey then return true end
        return not (EllesmereUIDB
            and EllesmereUIDB["showCrest_" .. stat.showCrestKey] == false)
    end

    -- Determine which stats to show based on class/spec
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

        -- Return fixed order: Primary Stat, Stamina, Health
        return {
            { name = primaryStat, func = function() return UnitStat("player", primaryStatIndex) end, statIndex = primaryStatIndex, tooltip = (primaryStatIndex == 1 and "Increases melee attack power") or (primaryStatIndex == 2 and "Increases dodge chance and melee attack power") or (primaryStatIndex == 4 and "Increase the magnitude of your attacks and Abilities") or "Primary stat" },
            { name = "Stamina", func = function() return UnitStat("player", 3) end, statIndex = 3, tooltip = "Increases health" },
            { name = "Health", func = function() return UnitHealthMax("player") end, tooltip = "The amount of damage you can take" },
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

    -- Get category color, applying customization if available
    local function GetCategoryColor(title)
        local custom = EllesmereUIDB and EllesmereUIDB.statCategoryColors and EllesmereUIDB.statCategoryColors[title]
        if custom then return custom end
        return DEFAULT_CATEGORY_COLORS[title] or { r = 1, g = 1, b = 1 }
    end

    -- Load stat sections order from saved data or use defaults
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
                    { name = "Crit", func = function() return GetCritChance("player") or 0 end, format = "%.2f%%", rawFunc = function() return GetCombatRating(CR_CRIT_MELEE) or 0 end },
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
                    -- GetLifesteal / GetAvoidance / GetSpeed return the TOTAL
                    -- percent including talent / racial / innate bonuses.
                    -- GetCombatRatingBonus only reflects rating-derived percent,
                    -- which misses e.g. Shadow Priest's +2% innate leech talent.
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
                    { name = "Spell Power", func = function() return GetSpellBonusDamage(7) end, tooltip = "Increases the power of your spells and abilities" },
                    { name = "Attack Speed", func = function() return UnitAttackSpeed("player") or 0 end, format = "%.2f", tooltip = "Attacks per second" },
                }
            },
            {
                title = "Defense",
                colorKey = "Defense",
                color = GetCategoryColor("Defense"),
                stats = {
                    { name = "Armor", func = function() local base, effectiveArmor = UnitArmor("player") return effectiveArmor end, tooltip = "Reduces physical damage taken" },
                    { name = "Dodge", func = function() return GetDodgeChance() or 0 end, format = "%.2f%%", tooltip = "Chance to avoid melee attacks" },
                    { name = "Parry", func = function() return GetParryChance() or 0 end, format = "%.2f%%", tooltip = "Chance to deflect melee attacks" },
                    { name = "Block", func = function() return GetBlockChance() or 0 end, format = "%.2f%%", tooltip = "Chance to block incoming attacks with a shield" },
                    { name = "Stagger Effect", func = function() return C_PaperDollInfo.GetStaggerPercentage("player") or 0 end, format = "%.2f%%", showWhen = "brewmaster", tooltip = "Converts damage into a delayed effect" },
                }
            },
            {
                title = "Crests",
                colorKey = "Crests",
                color = GetCategoryColor("Crests"),
                stats = {
                    { name = "Myth", showCrestKey = "Myth", func = function() return GetCrestValue(3347) end, format = "%d", currencyID = 3347 },
                    { name = "Hero", showCrestKey = "Hero", func = function() return GetCrestValue(3345) end, format = "%d", currencyID = 3345 },
                    { name = "Champion", showCrestKey = "Champion", func = function() return GetCrestValue(3343) end, format = "%d", currencyID = 3343 },
                    { name = "Veteran", showCrestKey = "Veteran", func = function() return GetCrestValue(3341) end, format = "%d", currencyID = 3341 },
                    { name = "Adventurer", showCrestKey = "Adventurer", func = function() return GetCrestValue(3383) end, format = "%d", currencyID = 3383 },
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

        -- Apply saved order if exists
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

    -- Function to refresh attributes stats if spec changed
    local function RefreshAttributeStats()
        local currentSpec = GetSpecialization()
        if currentSpec == GetFFD(frame).lastSpec then return end

        GetFFD(frame).lastSpec = currentSpec

        -- Find and update Attributes section
        for sectionIdx, sectionData in ipairs(GetFFD(frame).statsSections) do
            if sectionData.sectionTitle == "Attributes" then
                -- Get new stats for current spec
                local newStats = GetFilteredAttributeStats()

                -- Update existing stat elements with new names and functions
                local labelIndex = 0
                for _, stat in ipairs(sectionData.stats) do
                    if stat.label then
                        labelIndex = labelIndex + 1

                        if newStats[labelIndex] then
                            -- Update label text
                            stat.label:SetText(newStats[labelIndex].name)
                            stat.label:Show()

                            if stat.value then
                                -- Find and update the corresponding entry in GetFFD(frame).statsValues
                                for _, statsValueEntry in ipairs(GetFFD(frame).statsValues) do
                                    if statsValueEntry.value == stat.value then
                                        -- Update the function
                                        statsValueEntry.func = newStats[labelIndex].func
                                        statsValueEntry.format = newStats[labelIndex].format or "%d"
                                        -- Update display immediately
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
                                stat.value:Show()
                            end
                        else
                            -- Hide stats that aren't in newStats
                            stat.label:Hide()
                            if stat.value then stat.value:Hide() end
                        end
                    elseif stat.divider then
                        -- Show dividers only between visible stats
                        stat.divider:SetShown(labelIndex < #newStats)
                    end
                end

                GetFFD(frame).recalculateSections()
                break
            end
        end
    end

    -- Function to refresh visibility based on showWhen conditions
    local function RefreshStatsVisibility()
        local currentSpec = GetSpecialization()

        for _, sectionData in ipairs(GetFFD(frame).statsSections) do
            -- Collapsed sections keep all rows hidden regardless of
            -- per-stat filters. Let the collapse/expand path own visibility.
            if not sectionData.isCollapsed then
                local visibleCount = 0
                for si = 1, #sectionData.stats do
                    local stat = sectionData.stats[si]
                    if stat.label and (stat.showWhen or stat.showCrestKey) then
                        local shouldShow = ShouldShowStat(stat.showWhen)
                                       and ShouldShowCrest(stat)
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
        -- Deferred re-layout: scroll child bounds may not be finalized on
        -- the same frame as OnShow, causing sections to stack on first open.
        C_Timer.After(0, function()
            RefreshStatsVisibility()
            if EllesmereUI._updateStatCategoryVisibility then
                EllesmereUI._updateStatCategoryVisibility()
            end
        end)
    end)

    -- Function to update visibility of stat categories
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

    -- Function to recalculate all section positions
    local function RecalculateSectionPositions()
        -- Collect visible sections so first/last can be determined after hidden ones are skipped
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
    end
    GetFFD(frame).recalculateSections = RecalculateSectionPositions

    -- Create sections in scroll child
    local yOffset = 0
    for sectionIdx, section in ipairs(statSections) do
        -- Section container
        local sectionContainer = CreateFrame("Frame", nil, scrollChild)
        sectionContainer:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
        sectionContainer:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, yOffset)
        sectionContainer:SetWidth(260)

        -- Title + bar container spans the full section width so the left
        -- bar starts flush with stat labels and the right bar ends flush
        -- with stat values.
        local titleContainer = CreateFrame("Button", nil, sectionContainer)
        titleContainer:SetPoint("TOPLEFT",  sectionContainer, "TOPLEFT",  0, 0)
        titleContainer:SetPoint("TOPRIGHT", sectionContainer, "TOPRIGHT", 0, 0)
        titleContainer:SetHeight(16)
        titleContainer:RegisterForClicks("LeftButtonUp")

        -- Section title (centered in container)
        local sectionTitle = titleContainer:CreateFontString(nil, "OVERLAY")
        sectionTitle:SetFont(fontPath, 11, "")
        sectionTitle:SetTextColor(section.color.r, section.color.g, section.color.b, 1)
        sectionTitle:SetPoint("CENTER", titleContainer, "CENTER", 0, 0)
        sectionTitle:SetText(section.title)

        -- Absolute physical-pixel-perfect 1px dividers, same technique as
        -- PP.CreateBorder: disable engine snap and set height to exactly
        -- one physical pixel in the container's effective-scale units.
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

        -- Re-snap once after layout settles so GetEffectiveScale returns the
        -- final value (parents may not be fully positioned on first build).
        titleContainer._barResnap = { leftBar, rightBar }
        local _ticks = 0
        titleContainer:SetScript("OnUpdate", function(self)
            _ticks = _ticks + 1
            _snapSecLine(leftBar)
            _snapSecLine(rightBar)
            if _ticks >= 2 then self:SetScript("OnUpdate", nil) end
        end)

        local statYOffset = -22

        -- Store section data for collapse/expand. Initial collapsed state
        -- is restored from SavedVariables (EllesmereUIDB.charSheetCollapsedSections)
        -- keyed by settingKey so user preference persists across sessions.
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
            -- Stable backend identifier for SavedVariables keys; falls back to
            -- the title with spaces stripped if a section omits an explicit one.
            settingKey  = section.settingKey or section.title:gsub(" ", ""),
            colorKey = section.colorKey or section.title,  -- DB key for custom color
            titleFS = sectionTitle,
            leftBar = leftBar,
            rightBar = rightBar,
        }
        table.insert(GetFFD(frame).statsSections, sectionData)

        -- Stats in section
        for statIdx, stat in ipairs(section.stats) do
            -- Skip stats that don't meet the show conditions
            if ShouldShowStat(stat.showWhen) and ShouldShowCrest(stat) then
                -- Stat label
                local label = sectionContainer:CreateFontString(nil, "OVERLAY")
                label:SetFont(fontPath, 10, "")
                label:SetTextColor(0.7, 0.7, 0.7, 0.8)
                label:SetPoint("TOPLEFT", sectionContainer, "TOPLEFT", 0, statYOffset)
                label:SetText(stat.name)

                -- Stat value
                local value = sectionContainer:CreateFontString(nil, "OVERLAY")
                value:SetFont(fontPath, 10, "")
                value:SetTextColor(section.color.r, section.color.g, section.color.b, 1)
                value:SetPoint("TOPRIGHT", sectionContainer, "TOPRIGHT", 0, statYOffset)
                value:SetJustifyH("RIGHT")
                value:SetText("0")

                -- Create button overlay for all stats with tooltips
                local valueButton = CreateFrame("Button", nil, sectionContainer)
                valueButton:SetPoint("TOPRIGHT", sectionContainer, "TOPRIGHT", 0, statYOffset)
                valueButton:SetSize(90, 16)
                valueButton:EnableMouse(true)

                valueButton:SetScript("OnEnter", function()
                    local statValue = stat.func()
                    if issecretvalue(statValue) then return end
                    GameTooltip:SetOwner(valueButton, "ANCHOR_RIGHT")

                    -- Format value according to stat's format string
                    local displayValue = statValue
                    if stat.format then
                        displayValue = string.format(stat.format, statValue)
                    else
                        displayValue = tostring(statValue)
                    end

                    -- Build title line based on stat type
                    local titleLine = stat.name .. " " .. displayValue

                    -- Currency (Crests)
                    if stat.currencyID then
                        local currencyInfo = C_CurrencyInfo.GetCurrencyInfo(stat.currencyID)
                        if currencyInfo then
                            local earned = currencyInfo.totalEarned or 0
                            local maximum = currencyInfo.maxQuantity or 0
                            GameTooltip:AddLine(stat.name .. " Crests", section.color.r, section.color.g, section.color.b, 1)
                            GameTooltip:AddLine(string.format("%d / %d", earned, maximum), 1, 1, 1, true)
                        end
                    -- Secondary stats with raw rating
                    elseif stat.rawFunc then
                        local percentValue = stat.func()
                        local rawValue = stat.rawFunc()
                        GameTooltip:AddLine(
                            string.format("%s %.2f%% (%d rating)", stat.name, percentValue, rawValue),
                            section.color.r, section.color.g, section.color.b, 1  -- Use category color
                        )
                        -- Description for secondary stats
                        local description = ""
                        if stat.name == "Crit" then
                            description = string.format("Increases your chance to critically hit by %.2f%%.", percentValue)
                        elseif stat.name == "Haste" then
                            description = string.format("Increases attack and casting speed by %.2f%%.", percentValue)
                        elseif stat.name == "Mastery" then
                            description = string.format("Increases the effectiveness of your Mastery by %.2f%%.", percentValue)
                        elseif stat.name == "Versatility" then
                            description = string.format("Increases damage and healing done by %.2f%% and reduces damage taken by %.2f%%.", percentValue, percentValue / 2)
                        elseif stat.name == "Leech" then
                            description = string.format("Heals for %.2f%% of damage and healing done.", percentValue)
                        elseif stat.name == "Avoidance" then
                            description = string.format("Reduces damage taken from area attacks by %.2f%%.", percentValue)
                        elseif stat.name == "Speed" then
                            description = string.format("Increases movement speed by %.2f%%.", percentValue)
                        end
                        GameTooltip:AddLine(description, 1, 1, 1, true)
                    -- Attributes
                    elseif stat.statIndex then
                        local base, _, posBuff, negBuff = UnitStat("player", stat.statIndex)
                        local statLabel = stat.name

                        -- Map to Blizzard global names
                        if stat.name == "Strength" then
                            statLabel = STAT_STRENGTH or "Strength"
                        elseif stat.name == "Agility" then
                            statLabel = STAT_AGILITY or "Agility"
                        elseif stat.name == "Intellect" then
                            statLabel = STAT_INTELLECT or "Intellect"
                        elseif stat.name == "Stamina" then
                            statLabel = STAT_STAMINA or "Stamina"
                        end

                        local bonus = (posBuff or 0) + (negBuff or 0)
                        local statLine = statLabel .. " " .. statValue
                        if bonus ~= 0 then
                            statLine = statLine .. " (" .. base .. (bonus > 0 and "+" or "") .. bonus .. ")"
                        end
                        GameTooltip:AddLine(statLine, section.color.r, section.color.g, section.color.b, 1)
                        GameTooltip:AddLine(stat.tooltip, 1, 1, 1, true)
                    -- Generic stats (Attack, Defense, etc.)
                    else
                        GameTooltip:AddLine(titleLine, section.color.r, section.color.g, section.color.b, 1)
                        if stat.tooltip then
                            GameTooltip:AddLine(stat.tooltip, 1, 1, 1, true)
                        end
                    end

                    GameTooltip:Show()
                end)

                valueButton:SetScript("OnLeave", function()
                    GameTooltip:Hide()
                end)

                -- Store for updates
                table.insert(GetFFD(frame).statsValues, {
                    value = value,
                    func = stat.func,
                    rawFunc = stat.rawFunc,
                    format = stat.format or "%d",
                    categoryKey = section.settingKey,
                })

                -- Store stat elements for collapse/expand (include showWhen for visibility checks)
                table.insert(sectionData.stats, {label = label, value = value, button = valueButton, showWhen = stat.showWhen, showCrestKey = stat.showCrestKey})

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

        -- Apply collapsed visual state to the section's stat rows.
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

        -- Click handler for collapse/expand
        titleContainer:SetScript("OnClick", function()
            sectionData.isCollapsed = not sectionData.isCollapsed
            _applyCollapsedState()

            -- Persist across sessions.
            if EllesmereUIDB then
                EllesmereUIDB.charSheetCollapsedSections = EllesmereUIDB.charSheetCollapsedSections or {}
                EllesmereUIDB.charSheetCollapsedSections[_collapseKey] = sectionData.isCollapsed or nil
            end

            GetFFD(frame).recalculateSections()
        end)

        -- Up/Down reorder arrows (friends-list Favorites/Friends style):
        --   up-arrow on the LEFT edge, down-arrow on the RIGHT edge, dividers
        --   between arrows and the centered label. Always visible; first-up
        --   and last-down are grayed out and click-inert.
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

            -- Up arrow (LEFT edge)
            local upBtn = CreateFrame("Button", nil, titleContainer)
            upBtn:SetSize(arrowSize, arrowSize)
            upBtn:SetPoint("LEFT", titleContainer, "LEFT", 0, 0)
            upBtn:SetFrameLevel(titleContainer:GetFrameLevel() + 2)
            local upIcon = upBtn:CreateTexture(nil, "OVERLAY")
            upIcon:SetAllPoints()
            upIcon:SetTexture(MEDIA .. "icons\\eui-arrow-up3.png")
            upIcon:SetVertexColor(section.color.r, section.color.g, section.color.b, 1)
            upBtn:SetAlpha(DIV_ICON_ALPHA)

            -- Down arrow (RIGHT edge)
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

    -- Set scroll child height
    scrollChild:SetHeight(-yOffset)

    -- Save initial order if not already saved
    if not (EllesmereUIDB and EllesmereUIDB.statSectionsOrder) then
        if not EllesmereUIDB then EllesmereUIDB = {} end
        EllesmereUIDB.statSectionsOrder = {}
        for _, sec in ipairs(GetFFD(frame).statsSections) do
            table.insert(EllesmereUIDB.statSectionsOrder, sec.sectionTitle)
        end
    end

    -- Apply initial visibility settings
    UpdateStatCategoryVisibility()

    -- Function to update all stats
    local function UpdateAllStats()
        local secondaryRaw  = EllesmereUIDB and EllesmereUIDB.showSecondaryRaw
        local tertiaryRaw   = EllesmereUIDB and EllesmereUIDB.showTertiaryRaw
        local secondaryBoth = EllesmereUIDB and EllesmereUIDB.showSecondaryBoth
        local tertiaryBoth  = EllesmereUIDB and EllesmereUIDB.showTertiaryBoth
        for _, statEntry in ipairs(GetFFD(frame).statsValues) do
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
    EllesmereUI._refreshStatFormats = UpdateAllStats

    -- Update stats immediately once
    UpdateAllStats()

    -- Event-driven stat refresh: every stat the character sheet displays
    -- updates on one of these events. The old OnUpdate polled at 4Hz and
    -- duplicated all of this work for no benefit; dropped entirely.
    local statsEventFrame = CreateFrame("Frame")
    local _STATS_EVENTS = {
        "UNIT_STATS", "COMBAT_RATING_UPDATE", "PLAYER_EQUIPMENT_CHANGED",
        "UNIT_ATTACK_POWER", "UNIT_RANGED_ATTACK_POWER", "UNIT_SPELL_HASTE",
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
    -- Only listen for these high-frequency events while the sheet is open.
    -- UNIT_STATS / COMBAT_RATING_UPDATE fire many times per second in combat
    -- and dispatch overhead alone is a measurable idle cost.
    frame:HookScript("OnShow", function()
        for _, ev in ipairs(_STATS_EVENTS) do statsEventFrame:RegisterEvent(ev) end
    end)
    frame:HookScript("OnHide", function()
        statsEventFrame:UnregisterAllEvents()
    end)
    -- Also refresh once on panel open so the user sees fresh numbers even
    -- if no event has fired since the last close.
    frame:HookScript("OnShow", function()
        if frame and (frame.selectedTab or 1) == 1 then
            UpdateAllStats()
        end
    end)

    -- Apply custom rarity borders to slots (like CharacterSheetINSPO style)
    local function ApplyCustomSlotBorder(slotName)
        local slot = _G[slotName]
        if not slot then return end

        -- Hide Blizzard IconBorder
        if slot.IconBorder then
            slot.IconBorder:Hide()
        end

        -- Hide overlay textures
        if slot.IconOverlay then
            slot.IconOverlay:Hide()
        end
        if slot.IconOverlay2 then
            slot.IconOverlay2:Hide()
        end

        -- Crop icon inward
        if slot.icon then
            slot.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        end

        -- Hide NormalTexture
        local normalTexture = _G[slotName .. "NormalTexture"]
        if normalTexture then
            normalTexture:Hide()
        end

        -- Get item rarity color for border
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
            EllesmereUI.PanelPP.CreateBorder(slot, borderR, borderG, borderB, 1, 2, "OVERLAY", 7)
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

    -- Store on frame for use in tab hooks
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
        -- Plain Button (not SecureActionButtonTemplate): these tabs only
        -- have insecure OnClick handlers, and the secure template caused
        -- every Show/Hide/SetShown call on them to be flagged as protected
        -- when dispatched from inside Blizzard's secure ShowSubFrame stack.
        local btn = CreateFrame("Button", "EUI_CharSheet_" .. name, frame)
        btn:SetSize(buttonWidth, buttonHeight)
        btn:SetPoint("TOPLEFT", frame, "TOPLEFT", startX, startY)

        local text = btn:CreateFontString(nil, "OVERLAY")
        text:SetFont(fontPath, 10, "")
        -- Anchor to TOP (not CENTER) so the text sits flush with the top of
        -- the panel section instead of floating ~12px down inside a tall
        -- button.
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

    -- Character button (will be updated after stats panel is created)
    local characterBtn = CreateEUIButton("Stats", "Character", function() end)

    -- Expose a closure that re-highlights the Character top-button so
    -- ApplyTabVisibility can invoke it when the Blizzard bottom-tab swaps
    -- back to Character (Rep/Currency -> Character).
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
    GetFFD(frame).titlesPanel = titlesPanel  -- Store reference on frame

    -- Titles panel background (removed -- uses shared statsBg backdrop)

    -- Search box for titles
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

    -- Hint text
    local hintText = titlesSearchBox:CreateFontString(nil, "OVERLAY")
    hintText:SetFont(fontPath, 10, "")
    hintText:SetText("Search titles...")
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


    -- Create scroll frame for titles
    local titlesScrollFrame = CreateFrame("ScrollFrame", "EUI_CharSheet_TitlesScrollFrame", titlesPanel)
    titlesScrollFrame:SetPoint("TOPLEFT", titlesPanel, "TOPLEFT", 0, -65)
    titlesScrollFrame:SetPoint("BOTTOMRIGHT", titlesPanel, "BOTTOMRIGHT", 0, 0)
    titlesScrollFrame:EnableMouseWheel(true)

    -- Create scroll child
    local titlesScrollChild = CreateFrame("Frame", "EUI_CharSheet_TitlesScrollChild", titlesScrollFrame)
    titlesScrollChild:SetWidth(180)
    titlesScrollFrame:SetScrollChild(titlesScrollChild)

    -- Custom scrollbar (same shape as the stats scrollbar).
    AttachCustomScrollbar(titlesScrollFrame, titlesScrollChild, {
        trackOwner = titlesPanel,
        topInset   = -65,   -- matches titlesScrollFrame's top anchor offset
    })

    -- Populate titles
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

    -- One-time factory: creates a reusable button with once-bound scripts.
    -- Data travels via btn._titleIndex / btn._titleName, so scripts never
    -- close over per-title state.
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

        -- "No Title" (Blizzard convention: titleId -1 means clear the title).
        -- Title indices 1+ are real titles; using 0 here would be a silent
        -- no-op and the server-saved title would persist across logins.
        local noTitleBtn = _createTitleButton(-1)
        noTitleBtn._text:SetText("No Title")
        titleButtons[-1] = { btn = noTitleBtn, bg = noTitleBtn._bg }

        -- All known titles
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

        -- Sort alphabetically by title name; "No Title" (-1) is pinned first.
        -- Title names carry a "%s" player-name placeholder (prefix or suffix) plus
        -- surrounding spaces; strip them so the sort keys on the meaningful word
        -- (e.g. "%s the Kingslayer" -> "the kingslayer", "Bloodsail Admiral %s"
        -- -> "bloodsail admiral"). Computed once here, not per search keystroke.
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
            local name = (idx == -1) and "No Title" or (btn._titleName or "")
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

    -- Back-compat alias: a few call sites still say RefreshTitlesList().
    local RefreshTitlesList = FilterTitlesList

    -- When the player learns a new title, invalidate the build cache so the
    -- next filter rebuilds. (Typically fires once per expansion's worth of
    -- content; harmless to do a single full rebuild on those edges.)
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

    -- Search input handler
    titlesSearchBox:SetScript("OnTextChanged", function(self)
        if (self:GetText() or "") ~= "" then
            clearX:Show(); clearHit:Show()
        else
            clearX:Hide(); clearHit:Hide()
        end
        RefreshTitlesList()
    end)

    -- Focus gained handler
    titlesSearchBox:SetScript("OnEditFocusGained", function()
        if titlesSearchBox:GetText() == "" then
            hintText:Hide()
        end
    end)

    -- Focus lost handler
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

    -- Populate initially
    RefreshTitlesList()

    -- Hook to refresh titles when shown
    GetFFD(frame).titlesPanel:HookScript("OnShow", function()
        titlesSearchBox:SetText("")
        RefreshTitlesList()
    end)

    -- Update the Character button to show stats
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

    -- Titles button to show titles
    CreateEUIButton("Titles", "Titles", function()
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

    -- Equipment panel background
    -- Equipment panel background (removed -- uses shared statsBg backdrop)

    -- Create scroll frame for equipment (flush-left to match titles sidebar)
    local equipScrollFrame = CreateFrame("ScrollFrame", "EUI_CharSheet_EquipScrollFrame", equipPanel)
    equipScrollFrame:SetPoint("TOPLEFT",     equipPanel, "TOPLEFT",     0, -0)
    equipScrollFrame:SetPoint("BOTTOMRIGHT", equipPanel, "BOTTOMRIGHT", 0,  0)
    equipScrollFrame:EnableMouseWheel(true)

    -- Create scroll child
    local equipScrollChild = CreateFrame("Frame", "EUI_CharSheet_EquipScrollChild", equipScrollFrame)
    equipScrollChild:SetWidth(180)
    equipScrollFrame:SetScrollChild(equipScrollChild)

    -- Mousewheel support
    equipScrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local currentScroll = equipScrollFrame:GetVerticalScroll()
        local maxScroll = math.max(0, equipScrollChild:GetHeight() - equipScrollFrame:GetHeight())
        local newScroll = currentScroll - delta * 20
        newScroll = math.max(0, math.min(newScroll, maxScroll))
        equipScrollFrame:SetVerticalScroll(newScroll)
    end)

    -- Track selected equipment set
    local selectedSetID = nil
    -- Persistent tile pool. Rebuilt once; reused across every refresh.
    local setTilePool = {}

    -- Forward declare the refresh function (will be defined after buttons)
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
    setsHeaderText:SetText("Gear Sets")
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

    local newSetBtn = MakeTextLink(linksRow, "New", function()
        if InCombatLockdown() then return end
        StaticPopupDialogs["EUI_NEW_EQUIPMENT_SET"] = {
            text = "New equipment set name:",
            button1 = "Create",
            button2 = "Cancel",
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
    equipTopBtn = MakeTextLink(linksRow, "Equip", function()
        if InCombatLockdown() then return end
        equipTopText:SetText("Equipped!")
        equipTopText:SetTextColor(0.047, 0.824, 0.616, 1)
        if selectedSetID then
            EUI_EquipSet(selectedSetID)
            activeEquipmentSetID = selectedSetID
            if EllesmereUIDB then EllesmereUIDB.lastEquippedSet = selectedSetID end
            RefreshEquipmentSets()
        end
        C_Timer.After(1, function()
            if equipTopText then
                equipTopText:SetText("Equip")
                equipTopText:SetTextColor(1, 1, 1, 0.7)
            end
        end)
    end)
    equipTopText = equipTopBtn._fs

    local saveTopBtn, saveTopText
    saveTopBtn = MakeTextLink(linksRow, "Save", function()
        if InCombatLockdown() then return end
        saveTopText:SetText("Saved!")
        saveTopText:SetTextColor(0.047, 0.824, 0.616, 1)
        if selectedSetID then C_EquipmentSet.SaveEquipmentSet(selectedSetID) end
        C_Timer.After(1, function()
            if saveTopText then
                saveTopText:SetText("Save")
                saveTopText:SetTextColor(1, 1, 1, 0.7)
            end
        end)
    end)
    saveTopText = saveTopBtn._fs

    -- Evenly space the three text links across the row
    newSetBtn:ClearAllPoints()
    newSetBtn:SetPoint("LEFT", linksRow, "LEFT", 0, 0)
    equipTopBtn:ClearAllPoints()
    equipTopBtn:SetPoint("CENTER", linksRow, "CENTER", 0, 0)
    saveTopBtn:ClearAllPoints()
    saveTopBtn:SetPoint("RIGHT", linksRow, "RIGHT", 0, 0)

    -- Function to check if all items of a set are equipped
    -- A set is "complete" when every item it references is somewhere on the
    -- character -- equipped OR in bags/bank. We intentionally do NOT require
    -- all items to be currently equipped (that's "is the set active", not
    -- "is it usable"). Uses Blizzard's numLost field which counts items that
    -- are truly absent.
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
        local slotNames = {
            "Head", "Neck", "Shoulder", "Back",
            "Chest", "Waist", "Legs", "Feet",
            "Wrist", "Hands", "Finger 1", "Finger 2",
            "Trinket 1", "Trinket 2", "Main Hand", "Off Hand",
            "Tabard", "Chest (Relic)", "Back (Relic)"
        }

        for slot, setItemID in pairs(setItems) do
            if setItemID and setItemID ~= 0 then
                local equippedID = GetInventoryItemID("player", slot)
                if equippedID ~= setItemID then
                    -- Not equipped: check bags+bank+reagent bank via GetItemCount.
                    -- Arg signature: (item, includeBank, reagentBank) -- bags
                    -- are always counted.
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

    -- Function to reload equipment sets
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
            delTxt:SetFont(fontPath, 22, "")
            delTxt:SetText("×")
            delTxt:SetTextColor(1, 1, 1, 0.8)
            delTxt:SetPoint("CENTER", del, "CENTER", 0, 0)
            del:SetScript("OnEnter", function() delTxt:SetTextColor(1, 0.2, 0.2, 1) end)
            del:SetScript("OnLeave", function() delTxt:SetTextColor(1, 1, 1, 0.8) end)
            del:SetScript("OnClick", function()
                local sid, sname = tile._setID, tile._setName
                if not (sid and sname) then return end
                StaticPopupDialogs["EUI_DELETE_EQUIPMENT_SET"] = {
                    text = "Delete equipment set '" .. sname .. "'?",
                    button1 = "Delete", button2 = "Cancel",
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
                                string.format("%s %s: %s", iconText, item.slot, item.itemName),
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
    end

    -- Event-driven recolor of equipment-set buttons. Only fires when gear
    -- actually changes (or a set is edited), plus once on panel open.
    -- Also re-detects which set is currently equipped so the accent
    -- highlight tracks gear swaps without a full tile rebuild.
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
    end

    -- Debounced refresh: multiple events (PLAYER_EQUIPMENT_CHANGED fires
    -- per slot, EQUIPMENT_SETS_CHANGED, EQUIPMENT_SWAP_FINISHED) coalesce
    -- into a single refresh on the next frame.
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
        -- 0.3s debounce: mass equip/unequip (birthday suit) fires
        -- PLAYER_EQUIPMENT_CHANGED per slot. Blizzard's internal
        -- numLost/isEquipped metadata needs time to settle across all
        -- slots before GetEquipmentSetInfo returns accurate results.
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

    -- Hook to refresh equipment sets when shown
    equipPanel:HookScript("OnShow", function()
        RefreshEquipmentSets()
    end)

    -- Equipment Manager button
    -- Activate Blizzard's equipment sidebar (PaperDollSidebarTab3) so the
    -- per-slot flyout arrows appear. Our equipPanel overlays Blizzard's
    -- EquipmentManagerPane with our own gear-sets UI.
    CreateEUIButton("Equipment", "Equipment", function()
        if not GetFFD(CharacterFrame).equipPanel:IsShown() then
            GetFFD(CharacterFrame).equipPanel:SetShown(true)
            statsPanel:SetShown(false)
            if GetFFD(CharacterFrame).titlesPanel then GetFFD(CharacterFrame).titlesPanel:SetShown(false) end
            -- Activate Blizzard's equipment sidebar for flyout arrows.
            local sidebarTab = _G.PaperDollSidebarTab3
            if sidebarTab and sidebarTab.Click then
                pcall(sidebarTab.Click, sidebarTab)
            end
        end
    end)

    -- Update button positions to stack horizontally
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

    -- Calc toggle tab: fake bottom tab on the right side of the character
    -- sheet, visually identical to the Blizzard Character/Rep/Currency tabs.
    do
        local calcDb = EUIUpgCalc and EUIUpgCalc.GetOptsDB and EUIUpgCalc.GetOptsDB()
        if calcDb and calcDb.showCalcButton then
            -- Match Blizzard tab dimensions from CharacterFrameTab1
            local refTab = _G["CharacterFrameTab1"]
            local tabW = refTab and refTab:GetWidth() or 80
            local tabH = refTab and refTab:GetHeight() or 32

            local calcTab = CreateFrame("Button", "EUI_CharSheet_CalcTab", frame)
            calcTab:SetSize(tabW, tabH)
            calcTab:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, -30)
            calcTab:SetFrameLevel(frame:GetFrameLevel() + 5)
            calcTab:EnableMouse(true)

            -- Dark background (matches skinned Blizzard tabs)
            local bg = calcTab:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.068, 0.056, 0.052, 1)

            -- Active highlight overlay
            local activeHL = calcTab:CreateTexture(nil, "ARTWORK", nil, -6)
            activeHL:SetAllPoints()
            activeHL:SetColorTexture(1, 1, 1, 0.02)
            activeHL:SetBlendMode("ADD")
            activeHL:Hide()

            -- Label
            local label = calcTab:CreateFontString(nil, "OVERLAY")
            label:SetFont(fontPath, 9, "")
            label:SetPoint("CENTER", calcTab, "CENTER", 0, 0)
            label:SetJustifyH("CENTER")
            label:SetText("Upgrades")

            -- Accent underline (matches Blizzard tab underline)
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
            -- Hook the calc frame itself so the tab updates when it's
            -- opened/closed by any means (slash cmd, NPC hook, etc.)
            local function HookCalcFrame()
                local fr = _G["EUIUpgCalcFrame"]
                if not fr or GetFFD(calcTab)._calcHooked then return end
                GetFFD(calcTab)._calcHooked = true
                fr:HookScript("OnShow", RefreshCalcTab)
                fr:HookScript("OnHide", RefreshCalcTab)
            end
            HookCalcFrame()
            -- Deferred: calc frame may not exist yet at skin time
            if not _G["EUIUpgCalcFrame"] then
                C_Timer.After(1, HookCalcFrame)
            end
            GetFFD(frame).calcToggleBtn = calcTab
            GetFFD(frame).updateCalcBtnColor = RefreshCalcTab
        end
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

    -- Create global socket container for all slot icons
    local globalSocketContainer = CreateFrame("Frame", "EUI_CharSheet_SocketContainer", frame)
    globalSocketContainer:SetFrameLevel(100)
    -- Only show if on character tab
    local isCharacterTab = (frame.selectedTab or 1) == 1
    if isCharacterTab then
        globalSocketContainer:Show()
    else
        globalSocketContainer:Hide()
    end
    GetFFD(frame).socketContainer = globalSocketContainer  -- Store reference on frame

    -- Create overlay frame for text labels (above model, transparent, no mouse input)
    local textOverlayFrame = CreateFrame("Frame", "EUI_CharSheet_TextOverlay", frame)
    textOverlayFrame:SetFrameLevel(5)  -- Higher than model (FrameLevel 2)
    textOverlayFrame:EnableMouse(false)
    textOverlayFrame:Show()
    GetFFD(frame).textOverlayFrame = textOverlayFrame

    -- Top-left eyeball toggle: temporarily hides all item slot text (item level,
    -- upgrade track, enchants) by alpha-ing the shared overlay. Session-only.
    do
        local EYE_VISIBLE   = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-visible.png"
        local EYE_INVISIBLE = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-invisible.png"
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

        -- Shirt slot: skin the border but never show item level / upgrade
        -- track / enchant text. Shirts have no stats or enchants worth
        -- displaying and the labels just clutter the model area.
        local skipLabels = (slotName == "CharacterShirtSlot" or slotName == "CharacterTabardSlot")

        -- Create itemlevel labels
        local slot = _G[slotName]
        if slot and not GetFFD(slot).itemLevelLabel and not skipLabels then
            local itemLevelSize = EllesmereUIDB and EllesmereUIDB.charSheetItemLevelSize or 11
            local label = textOverlayFrame:CreateFontString(nil, "OVERLAY")
            label:SetFont(fontPath, itemLevelSize, "")
            label:SetTextColor(1, 1, 1, 0.8)
            label:SetJustifyH("CENTER")

            -- Position based on column
            if tContains(leftColumnSlots, slotName) then
                -- Left column: show on right side
                label:SetPoint("CENTER", slot, "RIGHT", 15, 10)
            elseif tContains(rightColumnSlots, slotName) then
                -- Right column: show on left side
                label:SetPoint("CENTER", slot, "LEFT", -15, 10)
            elseif slotName == "CharacterMainHandSlot" then
                -- MainHand: show on left side
                label:SetPoint("CENTER", slot, "LEFT", -15, 10)
            elseif slotName == "CharacterSecondaryHandSlot" then
                -- OffHand: show on right side
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
            enchantLabel:SetJustifyH("CENTER")

            -- Position based on column (below itemlevel)
            if tContains(leftColumnSlots, slotName) then
                enchantLabel:SetPoint("LEFT", slot, "RIGHT", 5, -5)
            elseif tContains(rightColumnSlots, slotName) then
                enchantLabel:SetPoint("RIGHT", slot, "LEFT", -5, -5)
            elseif slotName == "CharacterMainHandSlot" then
                enchantLabel:SetPoint("RIGHT", slot, "LEFT", -5, -5)
            elseif slotName == "CharacterSecondaryHandSlot" then
                enchantLabel:SetPoint("LEFT", slot, "RIGHT", 5, -5)
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

            -- Position beside itemlevel label based on column
            if tContains(leftColumnSlots, slotName) then
                -- Left column: upgradeTrack RIGHT of itemLevel
                upgradeTrackLabel:SetPoint("LEFT", GetFFD(slot).itemLevelLabel, "RIGHT", 3, 0)
            elseif tContains(rightColumnSlots, slotName) then
                -- Right column: upgradeTrack LEFT of itemLevel
                upgradeTrackLabel:SetPoint("RIGHT", GetFFD(slot).itemLevelLabel, "LEFT", -3, 0)
            elseif slotName == "CharacterMainHandSlot" then
                -- MainHand: upgradeTrack LEFT of itemLevel
                upgradeTrackLabel:SetPoint("RIGHT", GetFFD(slot).itemLevelLabel, "LEFT", -3, 0)
            elseif slotName == "CharacterSecondaryHandSlot" then
                -- OffHand: upgradeTrack RIGHT of itemLevel
                upgradeTrackLabel:SetPoint("LEFT", GetFFD(slot).itemLevelLabel, "RIGHT", 3, 0)
            end

            GetFFD(slot).upgradeTrackLabel = upgradeTrackLabel
        end
    end

    -- Update slot borders on inventory changes
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

    -- Shared pulse ticker: all slots that currently need a red "missing
    -- enchant" pulse share a single OnUpdate handler. Zero cost when the
    -- set is empty (ticker self-hides).
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
                    EllesmereUI.PanelPP.CreateBorder(overlay, 0.898, 0.286, 0.286, 1, 2, "OVERLAY", 7)  -- #e54949
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

    -- Listen for inventory / equipment / item-load changes and update borders.
    -- GetItemInfo can return nil on freshly-linked items; GET_ITEM_INFO_RECEIVED
    -- fires when the data arrives so we re-paint then.
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

    -- Gem slot size and layout constants. Gems sit INSIDE the gear icon,
    -- anchored to the bottom-right and stacking leftward for multiples.
    local PP_GEM     = EllesmereUI.PanelPP
    local GEM_PP_MULT = (PP_GEM and PP_GEM.mult) or 1
    -- Gems sit 2 physical pixels inside the slot's border (which is 1 physical
    -- pixel wide), so total inset from the slot edge is 2 * mult.
    local GEM_SIZE   = 15
    local GEM_PAD    = GEM_PP_MULT           -- 1 physical-pixel gap between stacked gems
    local GEM_INSET_X = 2 * GEM_PP_MULT      -- 2 physical pixels from slot's right edge
    local GEM_INSET_Y = 2 * GEM_PP_MULT      -- 2 physical pixels from slot's bottom edge

    -- Rarity-to-border-color map: rank 2 gems (rare+) get gold, rank 1
    -- (uncommon) gets silver.
    local function GemBorderColor(rarity)
        if (rarity or 0) >= 3 then
            return 1.00, 0.82, 0.00, 1  -- gold
        end
        return 0.75, 0.75, 0.75, 1       -- silver
    end

    -- Socket icon creation and display logic. Each socket is a small Frame
    -- (not a raw texture) so we can put a 1px pixel-perfect border on it.
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
            if gemBdr then gemBdr:SetFrameLevel(gemFrame:GetFrameLevel() + 1) end

            GetFFD(slot).charSocketsFrames[i] = gemFrame
            GetFFD(slot).charSocketsIcons[i]  = icon
        end

        GetFFD(slot).charSocketsSide = side
        GetFFD(slot).charSocketsSlotIndex = slotIndex

        return GetFFD(slot).charSocketsIcons
    end

    -- Update socket icons for all slots
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

        -- TOOLTIP_DATA_UPDATE / GET_ITEM_INFO_RECEIVED → QueueSocketRefresh until
        -- gem bytes on the link match GetItemStats (CLAUDE.md: no tooltip scrape).

        GetFFD(slot).gemLinks = gemLinks

        -- Position and show gem frames inside the slot's bottom-right, with
        -- extra gems stacking leftward. Border color reflects gem rank:
        -- Rank 2+ (rare+) = gold, Rank 1 (uncommon) = silver.
        if #socketTextures > 0 then
            local gemFrames = GetFFD(slot).charSocketsFrames or {}
            for i, icon in ipairs(socketIcons) do
                local gemFrame = gemFrames[i]
                if socketTextures[i] and gemFrame then
                    local entry = socketTextures[i]
                    if entry.isAtlas then
                        -- Empty socket: prefer Blizzard's socket atlas. Avoid a
                        -- bright red fill on first open — the inventory link can
                        -- lack gem bytes while GetItemStats still reports sockets,
                        -- which made solid red read as "missing gem" on gemmed gear.
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
                        -- Must clear atlas / color-texture mode before applying a
                        -- fileID; otherwise the frame shows only the PP border after
                        -- a prior empty-socket atlas paint on the same texture.
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

                    -- Tooltip on hover
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

    -- Refresh socket icons for all slots
    local function RefreshAllSocketIcons()
        for _, slotName in ipairs(itemSlots) do
            UpdateSocketIcons(slotName)
        end
    end
    EllesmereUI._refreshGemsVisibility = RefreshAllSocketIcons

    -- Hard reset a slot's gem art. Called on PLAYER_EQUIPMENT_CHANGED before
    -- the debounced refresh so stale gem icons from the previous item in
    -- this slot can never linger (e.g. swapping a ring with a gem for one
    -- with an empty socket previously left the old gem icon until /reload).
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

    -- Map inventory slot IDs to our slot button names so we can clear the
    -- exact slot that just changed without scanning all 18 every time.
    local _invSlotToName = {}
    for _, slotName in ipairs(itemSlots) do
        local b = _G[slotName]
        if b and b.GetID then
            local id = b:GetID()
            if id and id > 0 then _invSlotToName[id] = slotName end
        end
    end

    local function CharSheetGemsActive()
        if EllesmereUIDB and EllesmereUIDB.themedCharacterSheet == false then return false end
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

    -- Equipment / item-load hooks: trailing debounce so bursts of
    -- GET_ITEM_INFO_RECEIVED schedule one refresh after data settles (a
    -- leading debounce can fire once on stale links right after /reload).
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
        -- Clear stale gem art for the slot that just changed BEFORE the
        -- debounced refresh runs. Without this, the old item's gem icons
        -- can remain visible until /reload if the refresh path somehow
        -- picks up cached gem data.
        if event == "PLAYER_EQUIPMENT_CHANGED" and arg1 then
            local slotName = _invSlotToName[arg1]
            if slotName then ClearSlotGems(_G[slotName]) end
        end
        -- No refresh work while the sheet is closed (handler still runs for
        -- equipped-item cache / clear-slot above).
        if not frame:IsShown() or (frame.selectedTab or 1) ~= 1 then
            return
        end
        QueueSocketRefresh()
    end)

    -- Hook frame show/hide
    frame:HookScript("OnShow", function()
        -- Non-hydration high-frequency events: only while the sheet is visible.
        socketWatcher:RegisterEvent("UNIT_INVENTORY_CHANGED")
        socketWatcher:RegisterEvent("SOCKET_INFO_UPDATE")
        -- Only refresh sockets and show container if on character tab
        local isCharacterTab = (frame.selectedTab or 1) == 1
        if isCharacterTab then
            RefreshEquippedItemIDs()
            RefreshAllSocketIcons()
            QueueSocketRefresh()
            globalSocketContainer:Show()
        else
            globalSocketContainer:Hide()
        end
        -- Reset to Stats sub-panel on open, but ONLY when opening to the
        -- Character tab.  When the user opens via keybind to Reputation or
        -- Currency, forcing selectedTab = 1 here desynchronises Blizzard's
        -- internal tab state (it thinks Character is active while the Rep/
        -- Currency pane is actually shown), which makes the Character tab
        -- un-clickable until the user clicks Currency to resync.
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


    -- (Enchant/upgrade-track scanning uses C_TooltipInfo via the
    -- EUI_ScanInventoryItem helper at module scope. No scanning tooltip
    -- frame is created -- see CLAUDE.md reference_tooltip_template_taint.)

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
    }

    -- Function to update enchant text and upgrade track for a slot
    local function UpdateSlotInfo(slotName)
        local slot = _G[slotName]
        if not slot then return end

        -- Tab guard: equipment events fire regardless of which CharacterFrame
        -- sub-tab is active. PaperDollFrame is the Character sub-pane: when
        -- the user opens directly to Reputation/Currency, it's not shown,
        -- so our slot labels must stay hidden to avoid bleeding through the
        -- other panes. PanelTemplates_GetSelectedTab is unreliable on the
        -- initial open path -- it can lag and report tab 1 even when the
        -- user is sitting on Rep. PaperDollFrame:IsShown() is the truth.
        local isCharTab = PaperDollFrame and PaperDollFrame:IsShown()

        local itemLink = GetInventoryItemLink("player", slot:GetID())
        local itemLevel = ""
        local enchantText = ""
        local upgradeTrackText = ""
        local upgradeTrackColor = { r = 1, g = 1, b = 1 }
        local itemQuality = nil
        local slotID = slot:GetID()
        local canHaveEnchant = ENCHANT_SLOTS[slotID]

        if itemLink then
            local _, _, quality, ilvl = GetItemInfo(itemLink)
            itemLevel = ilvl or ""
            itemQuality = quality

            -- Enchant via C_TooltipInfo; upgrade track via C_Item (no tooltip).
            enchantText = EUI_GetEnchantText(slot:GetID())
            upgradeTrackText, upgradeTrackColor = EUI_GetUpgradeTrack(itemLink)
        end

        -- Update itemlevel label with optional rarity color
        if GetFFD(slot).itemLevelLabel then
            -- Check if itemlevel is enabled (default: true)
            local showItemLevel = (not EllesmereUIDB) or (EllesmereUIDB.showItemLevel ~= false)

            if showItemLevel then
                GetFFD(slot).itemLevelLabel:SetText(tostring(itemLevel) or "")
                GetFFD(slot).itemLevelLabel:SetShown(isCharTab)

                -- Color resolution order:
                --   1. User custom color (if enabled)
                --   2. Upgrade track color (shares the Hero/Myth/Champion hue
                --      so both labels read as a single unit)
                --   3. Item rarity color
                --   4. White fallback
                local displayColor
                if EllesmereUIDB and EllesmereUIDB.charSheetItemLevelUseColor and EllesmereUIDB.charSheetItemLevelColor then
                    displayColor = EllesmereUIDB.charSheetItemLevelColor
                elseif upgradeTrackText ~= "" and upgradeTrackColor then
                    displayColor = upgradeTrackColor
                elseif (not EllesmereUIDB or EllesmereUIDB.charSheetColorItemLevel ~= false) and itemQuality then
                    local r, g, b = GetItemQualityColor(itemQuality)
                    displayColor = { r = r, g = g, b = b }
                else
                    displayColor = { r = 1, g = 1, b = 1 }
                end

                GetFFD(slot).itemLevelLabel:SetTextColor(displayColor.r, displayColor.g, displayColor.b, 0.9)
            else
                GetFFD(slot).itemLevelLabel:Hide()
            end
        end

        -- Enchant label: keep the inline atlas escapes (|A:...|a) so the
        -- quality icons still render, strip the readable text, and park the
        -- full original text behind a hover tooltip on an overlapping frame.
        if GetFFD(slot).enchantLabel then
            local showEnchants = (not EllesmereUIDB) or (EllesmereUIDB.showEnchants ~= false)
            -- Only flag missing enchants for level 90+ characters: leveling
            -- gear churn means the red icon and pulse would constantly fire
            -- on every replacement. Endgame players are the audience.
            local playerLvl = UnitLevel("player")
            local atEnchantLevel = playerLvl and not (issecretvalue and issecretvalue(playerLvl)) and playerLvl >= 90 or false
            local isMissing    = atEnchantLevel and canHaveEnchant and itemLink and (enchantText == "" or not enchantText)
            local hasEnchant   = enchantText and enchantText ~= ""

            local iconOnly, tooltipText
            if isMissing then
                -- Same hex atlas the enchanted items show, tinted red
                -- (#e54949 → RGB 229, 73, 73 in the atlas-escape color fields).
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
                -- Strip any "prefix - " (e.g. "Enchant Weapon - ") so the
                -- tooltip shows just the enchant's readable name.
                tooltipText = tooltipText:gsub("^.-%s*%-%s*", "")
            end

            if showEnchants and iconOnly and iconOnly ~= "" then
                GetFFD(slot).enchantLabel:SetText(iconOnly)
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

            -- Pulsing red border overlay for missing enchants. Driven by the
            -- same isMissing flag so it stays in sync with the icon swap.
            if GetFFD(frame).setSlotMissingEnchant then
                GetFFD(frame).setSlotMissingEnchant(slot, isMissing == true)
            end
        end

        -- Update upgrade track label
        if GetFFD(slot).upgradeTrackLabel then
            -- Check if upgradetrack is enabled (default: true)
            local showUpgradeTrack = (not EllesmereUIDB) or (EllesmereUIDB.showUpgradeTrack ~= false)

            if showUpgradeTrack then
                GetFFD(slot).upgradeTrackLabel:SetText(upgradeTrackText ~= "" and ("(" .. upgradeTrackText .. ")") or "")
                GetFFD(slot).upgradeTrackLabel:SetShown(isCharTab)

                -- Determine color to use
                local displayColor
                if EllesmereUIDB and EllesmereUIDB.charSheetUpgradeTrackUseColor and EllesmereUIDB.charSheetUpgradeTrackColor then
                    -- Use custom color if enabled
                    displayColor = EllesmereUIDB.charSheetUpgradeTrackColor
                else
                    -- Use original rarity color by default
                    displayColor = upgradeTrackColor
                end

                GetFFD(slot).upgradeTrackLabel:SetTextColor(displayColor.r, displayColor.g, displayColor.b, 0.8)
            else
                GetFFD(slot).upgradeTrackLabel:Hide()
            end
        end
    end

    -- Event-driven per-slot label refresh. Item-link cache still guards
    -- redundant work; the events guarantee we catch upgrade / enchant /
    -- socket changes without per-frame polling.
    local function RefreshAllSlotLabels()
        if EllesmereUIDB and EllesmereUIDB.themedCharacterSheet == false then return end
        if not (frame and frame:IsShown()) then return end
        for _, slotName in ipairs(itemSlots) do
            local itemLink = GetInventoryItemLink("player", _G[slotName]:GetID())
            if itemCache[slotName] ~= itemLink then
                itemCache[slotName] = itemLink
                UpdateSlotInfo(slotName)
            end
        end
    end

    if not GetFFD(frame).itemLevelMonitor then
        GetFFD(frame).itemLevelMonitor = CreateFrame("Frame")
        GetFFD(frame).itemLevelMonitor:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        GetFFD(frame).itemLevelMonitor:RegisterEvent("UNIT_INVENTORY_CHANGED")
        GetFFD(frame).itemLevelMonitor:RegisterEvent("SOCKET_INFO_UPDATE")
        GetFFD(frame).itemLevelMonitor:RegisterEvent("ITEM_UPGRADE_MASTER_UPDATE")
        -- BAG_UPDATE_DELAYED removed: bag contents don't affect the
        -- displayed equipped-item info (ilvl / enchant / upgrade track).
        GetFFD(frame).itemLevelMonitor:SetScript("OnEvent", function(_, event, unit)
            if event == "UNIT_INVENTORY_CHANGED" and unit ~= "player" then return end
            if not (frame and frame:IsShown()) then return end
            RefreshAllSlotLabels()
        end)
        frame:HookScript("OnShow", RefreshAllSlotLabels)
        -- Skinning is deferred until first open, which means the OnShow hook
        -- above is installed mid-show -- it won't fire for the current open
        -- event. Run a refresh now so first-open gets decorated immediately.
        RefreshAllSlotLabels()
    end

    -- Same deferred-skin timing issue for gem icons: the OnShow hook at
    -- line ~3997 is installed mid-show and won't fire for the first open.
    if (frame.selectedTab or 1) == 1 then
        RefreshAllSocketIcons()
    end

    -- Re-apply tab visibility now that all elements exist. The early call
    -- at line ~1004 runs before stats panel / model scene / slots are
    -- created, so when opening Rep/Currency directly via hotkey the
    -- character-tab elements never got hidden.
    local isCharTab = not (_G.ReputationFrame and _G.ReputationFrame:IsShown())
        and not (_G.TokenFrame and _G.TokenFrame:IsShown())
    ApplyTabVisibility(isCharTab)
end

-- Get item rarity color from link
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

-- Style a character slot with rarity-based border
local function SkinCharacterSlot(slotName, slotID)
    local slot = _G[slotName]
    if not slot or GetFFD(slot).skinned then return end
    GetFFD(slot).skinned = true

    -- Hide Blizzard IconBorder
    if slot.IconBorder then
        slot.IconBorder:Hide()
    end

    -- Adjust IconTexture
    local iconTexture = _G[slotName .. "IconTexture"]
    if iconTexture then
        iconTexture:SetTexCoord(0.07, 0.07, 0.07, 0.93, 0.93, 0.07, 0.93, 0.93)
    end

    -- Test: Hide CharacterHandsSlot completely
    if slotName == "CharacterHandsSlot" then
        slot:Hide()
    end

    -- Hide NormalTexture
    local normalTexture = _G[slotName .. "NormalTexture"]
    if normalTexture then
        normalTexture:Hide()
    end

    -- EUI-style background for the slot
    local slotBg = slot:CreateTexture(nil, "BACKGROUND", nil, -5)
    slotBg:SetAllPoints(slot)
    slotBg:SetColorTexture(0.5, 0.5, 0.5, 0.7)  -- Gray background with transparency
    GetFFD(slot).slotBg = slotBg

    -- Create custom border on the slot using PP.CreateBorder
    if EllesmereUI and EllesmereUI.PanelPP then
        EllesmereUI.PanelPP.CreateBorder(slot, 1, 1, 1, 0.4, 2, "OVERLAY", 7)
    end
end

-- Main function to apply themed character sheet
local function ApplyThemedCharacterSheet()
    if EllesmereUIDB and EllesmereUIDB.themedCharacterSheet == false then
        return
    end

    if CharacterFrame then
        SkinCharacterSheet()
    end
end

-- Register the feature
if EllesmereUI then
    EllesmereUI.ApplyThemedCharacterSheet = ApplyThemedCharacterSheet

    -- Setup at PLAYER_LOGIN to register drag hooks early
    local initFrame = CreateFrame("Frame")
    initFrame:RegisterEvent("PLAYER_LOGIN")
    initFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        if CharacterFrame then
            -- Lightweight pre-skin (chrome hides, bg, border) runs early
            -- while CharacterFrame is still hidden. Running these mid-OnShow
            -- prevents Rep/Currency ScrollBox from completing its data render.
            if not EllesmereUIDB or EllesmereUIDB.themedCharacterSheet ~= false then
                PreSkinCharacterSheet()
                -- PreSkin hides the portrait once; Blizzard's CharacterFrameMixin:UpdatePortrait
                -- (RefreshDisplay / UNIT_PORTRAIT_UPDATE / spec icon) runs after OnShow hooks and
                -- redraws it. Re-hide via secure hook + deferred passes on GetPortrait() as well.
                if not GetFFD(CharacterFrame)._euiPortraitSuppressRegistered then
                    local function SuppressCharacterFramePortrait()
                        if EllesmereUIDB and EllesmereUIDB.themedCharacterSheet == false then return end
                        if not CharacterFrame then return end
                        -- Blizzard re-anchors CharacterFrameInsetRight on each open; it parents
                        -- PaperDollSidebarTabs (Tab1 uses a circular player/spec portrait). Re-apply
                        -- the same off-screen park as PreSkin so that chrome cannot snap back.
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
                            if EllesmereUIDB and EllesmereUIDB.themedCharacterSheet == false then return end
                            SuppressCharacterFramePortrait()
                        end)

                        if CharacterFrame.RefreshDisplay then
                            hooksecurefunc(CharacterFrame, "RefreshDisplay", function()
                                if EllesmereUIDB and EllesmereUIDB.themedCharacterSheet == false then return end
                                SuppressCharacterFramePortrait()
                            end)
                        end

                        if CharacterFrame.SetPortraitToSpecIcon then
                            hooksecurefunc(CharacterFrame, "SetPortraitToSpecIcon", function()
                                if EllesmereUIDB and EllesmereUIDB.themedCharacterSheet == false then return end
                                SuppressCharacterFramePortrait()
                            end)
                        end

                        local portrait = _G.CharacterFramePortrait
                        if portrait then
                            portrait:HookScript("OnShow", function(self)
                                if EllesmereUIDB and EllesmereUIDB.themedCharacterSheet == false then return end
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

            -- Function to detect and set active equipment set
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
                    -- Update active set when equipment changes
                    -- UpdateActiveEquipmentSet()  -- API no longer available in current WoW version
                    -- RefreshEquipmentSets()  -- Function not in scope here
                    if CharacterFrame and CharacterFrame:IsShown() and GetFFD(CharacterFrame).equipPanel and GetFFD(CharacterFrame).equipPanel:IsShown() then
                        -- Equipment panel will be refreshed by the equipSetChangeFrame handler
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
                -- Restore last equipped set if available
                if EllesmereUIDB and EllesmereUIDB.lastEquippedSet then
                    activeEquipmentSetID = EllesmereUIDB.lastEquippedSet
                end
            end)
        end
    end)
end

-- Function to apply character sheet text size settings
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

    -- Update all slot labels
    local itemSlots = EUI_GEAR_SLOTS

    for _, slotName in ipairs(itemSlots) do
        local slot = _G[slotName]
        if slot then
            if GetFFD(slot).itemLevelLabel then
                local flags = ""
                if itemLevelOutline then
                    flags = "OUTLINE"
                end
                GetFFD(slot).itemLevelLabel:SetFont(fontPath, itemLevelSize, flags)
                -- Apply shadow effect if enabled
                if itemLevelShadow then
                    GetFFD(slot).itemLevelLabel:SetShadowColor(0, 0, 0, 1)
                    GetFFD(slot).itemLevelLabel:SetShadowOffset(1, -1)
                else
                    GetFFD(slot).itemLevelLabel:SetShadowColor(0, 0, 0, 0)
                end
            end
            if GetFFD(slot).upgradeTrackLabel then
                local flags = ""
                if upgradeTrackOutline then
                    flags = "OUTLINE"
                end
                GetFFD(slot).upgradeTrackLabel:SetFont(fontPath, upgradeTrackSize, flags)
                -- Apply shadow effect if enabled
                if upgradeTrackShadow then
                    GetFFD(slot).upgradeTrackLabel:SetShadowColor(0, 0, 0, 1)
                    GetFFD(slot).upgradeTrackLabel:SetShadowOffset(1, -1)
                else
                    GetFFD(slot).upgradeTrackLabel:SetShadowColor(0, 0, 0, 0)
                end
            end
            if GetFFD(slot).enchantLabel then
                local flags = ""
                if enchantOutline then
                    flags = "OUTLINE"
                end
                GetFFD(slot).enchantLabel:SetFont(fontPath, enchantSize, flags)
                -- Apply shadow effect if enabled
                if enchantShadow then
                    GetFFD(slot).enchantLabel:SetShadowColor(0, 0, 0, 1)
                    GetFFD(slot).enchantLabel:SetShadowOffset(1, -1)
                else
                    GetFFD(slot).enchantLabel:SetShadowColor(0, 0, 0, 0)
                end
            end
        end
    end
end

-- Function to recolor item level labels based on rarity setting
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

-- Function to refresh category colors when changed in options
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

    -- Helper to get category color
    local function GetCategoryColor(title)
        -- Check if custom color is enabled for this category
        local useCustom = EllesmereUIDB and EllesmereUIDB.statCategoryUseColor and EllesmereUIDB.statCategoryUseColor[title]
        if useCustom then
            local custom = EllesmereUIDB and EllesmereUIDB.statCategoryColors and EllesmereUIDB.statCategoryColors[title]
            if custom then return custom end
        end
        return DEFAULT_CATEGORY_COLORS[title] or { r = 1, g = 1, b = 1 }
    end

    -- Update each section's colors. Uses the persisted colorKey (the DB
    -- key) rather than the display title so mismatches like "Secondary"
    -- vs "Secondary Stats" resolve correctly.
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

-- Function to refresh upgrade track visibility when toggle changes
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

-- Function to refresh enchants visibility when toggle changes
function EllesmereUI._refreshEnchantsVisibility()
    local itemSlots = EUI_GEAR_SLOTS

    local showEnchants = (not EllesmereUIDB) or (EllesmereUIDB.showEnchants ~= false)

    for _, slotName in ipairs(itemSlots) do
        local slot = _G[slotName]
        if slot and GetFFD(slot).enchantLabel then
            if showEnchants then
                GetFFD(slot).enchantLabel:Show()
            else
                GetFFD(slot).enchantLabel:Hide()
            end
        end
    end
end

-- Function to refresh enchants colors
function EllesmereUI._refreshEnchantsColors()
    local itemSlots = EUI_GEAR_SLOTS

    for _, slotName in ipairs(itemSlots) do
        local slot = _G[slotName]
        if slot and GetFFD(slot).enchantLabel then
            -- Determine color to use
            local displayColor
            if EllesmereUIDB and EllesmereUIDB.charSheetEnchantUseColor and EllesmereUIDB.charSheetEnchantColor then
                -- Use custom color if enabled
                displayColor = EllesmereUIDB.charSheetEnchantColor
            else
                -- Use default color
                displayColor = { r = 1, g = 1, b = 1 }
            end

            GetFFD(slot).enchantLabel:SetTextColor(displayColor.r, displayColor.g, displayColor.b, 1)
        end
    end
end

-- Function to refresh item level visibility when toggle changes
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

-- Function to refresh item level colors
function EllesmereUI._refreshItemLevelColors()
    local itemSlots = EUI_GEAR_SLOTS

    for _, slotName in ipairs(itemSlots) do
        local slot = _G[slotName]
        if slot and GetFFD(slot).itemLevelLabel then
            -- Determine color to use
            local displayColor
            if EllesmereUIDB and EllesmereUIDB.charSheetItemLevelUseColor and EllesmereUIDB.charSheetItemLevelColor then
                -- Use custom color if enabled
                displayColor = EllesmereUIDB.charSheetItemLevelColor
            else
                -- Use rarity color by default, unless explicitly disabled
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

-- Function to refresh upgrade track colors
function EllesmereUI._refreshUpgradeTrackColors()
    local itemSlots = EUI_GEAR_SLOTS

    for _, slotName in ipairs(itemSlots) do
        local slot = _G[slotName]
        if slot and GetFFD(slot).upgradeTrackLabel then
            local itemLink = GetInventoryItemLink("player", slot:GetID())
            if itemLink then
                -- Upgrade track color via C_Item.GetItemUpgradeInfo (no tooltip).
                local _, upgradeTrackColor = EUI_GetUpgradeTrack(itemLink)

                -- Apply color
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
