-------------------------------------------------------------------------------
-- EllesmereUIQuestTracker_Wowhead.lua
--
-- Quest log + objective tracker right-click: "Wowhead URL" copy modal.
-------------------------------------------------------------------------------
local _, ns = ...
local EQT = ns.EQT

local WOWHEAD_QUEST_URL = "https://www.wowhead.com/quest=%d/"
local QUEST_ICON_FALLBACK = "Interface\\GossipFrame\\AvailableQuestIcon"

local MENU_TAGS = {
    "MENU_QUEST_MAP_LOG_TITLE",
    "MENU_QUEST_OBJECTIVE_TRACKER",
}

local function GetWowheadQuestURL(questID)
    return WOWHEAD_QUEST_URL:format(questID)
end

local function GetQuestTitle(questID)
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local title = C_QuestLog.GetTitleForQuestID(questID)
        if title and title ~= "" then
            return title
        end
    end
    if GetQuestLogTitle and GetQuestLogIndexByID then
        local logIndex = GetQuestLogIndexByQuestID and GetQuestLogIndexByQuestID(questID)
            or GetQuestLogIndexByID(questID)
        if logIndex then
            local title = GetQuestLogTitle(logIndex)
            if title and title ~= "" then
                return title
            end
        end
    end
    return ("Quest %d"):format(questID)
end

local function ApplyQuestIcon(tex, questID)
    local atlas = EQT.GetQuestIconAtlas and EQT.GetQuestIconAtlas(questID)
    if atlas and tex.SetAtlas then
        tex:SetAtlas(atlas)
        return
    end
    if tex.SetAtlas then
        tex:SetAtlas(nil)
    end
    tex:SetTexture(QUEST_ICON_FALLBACK)
end

-------------------------------------------------------------------------------
-- Modal
-------------------------------------------------------------------------------
local wowheadDimmer

local function ShowWowheadQuestModal(questID)
    if type(questID) ~= "number" or questID <= 0 then return end
    if not EllesmereUI then return end

    local EUI = EllesmereUI
    local questName = GetQuestTitle(questID)
    local url = GetWowheadQuestURL(questID)

    if not wowheadDimmer then
        local POPUP_W, POPUP_H = 380, 168
        local PAD = 16
        local EG = EUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.61 }
        local fontPath = (EUI.GetFontPath and EUI.GetFontPath()) or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
        local outline = (EUI.GetFontOutlineFlag and EUI.GetFontOutlineFlag()) or ""

        local dimmer = CreateFrame("Frame", nil, UIParent)
        dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
        dimmer:SetAllPoints(UIParent)
        dimmer:EnableMouse(true)
        dimmer:EnableMouseWheel(true)
        dimmer:SetScript("OnMouseWheel", function() end)
        dimmer:Hide()
        EUI.SolidTex(dimmer, "BACKGROUND", 0, 0, 0, 0.35):SetAllPoints()

        local popup = CreateFrame("Frame", nil, dimmer)
        popup:SetSize(POPUP_W, POPUP_H)
        popup:SetPoint("CENTER", UIParent, "CENTER", 0, 48)
        popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)
        popup:EnableMouse(true)

        EUI.SolidTex(popup, "BACKGROUND", 0.06, 0.08, 0.10, 0.97):SetAllPoints()
        EUI.MakeBorder(popup, 1, 1, 1, 0.15, EUI.PanelPP)

        local accent = EUI.SolidTex(popup, "ARTWORK", EG.r, EG.g, EG.b, 0.85)
        accent:SetHeight(2)
        accent:SetPoint("TOPLEFT", popup, "TOPLEFT", 1, -1)
        accent:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -1, -1)

        local headerFS = EUI.MakeFont(popup, 12, outline, EG.r, EG.g, EG.b)
        headerFS:SetPoint("TOP", popup, "TOP", 0, -16)
        headerFS:SetJustifyH("CENTER")
        headerFS:SetText("Wowhead URL")

        local questIcon = popup:CreateTexture(nil, "ARTWORK")
        questIcon:SetSize(18, 18)
        questIcon:SetPoint("RIGHT", headerFS, "LEFT", -6, 0)
        popup._questIcon = questIcon

        local questFS = EUI.MakeFont(popup, 13, outline, 1, 0.91, 0.47)
        questFS:SetPoint("TOP", headerFS, "BOTTOM", 0, -8)
        questFS:SetPoint("LEFT", popup, "LEFT", PAD, 0)
        questFS:SetPoint("RIGHT", popup, "RIGHT", -PAD, 0)
        questFS:SetJustifyH("CENTER")
        questFS:SetWordWrap(true)
        questFS:SetMaxLines(2)
        popup._questFS = questFS

        local editBox = CreateFrame("EditBox", nil, popup)
        editBox:SetHeight(24)
        editBox:SetPoint("TOP", questFS, "BOTTOM", 0, -10)
        editBox:SetPoint("LEFT", popup, "LEFT", PAD, 0)
        editBox:SetPoint("RIGHT", popup, "RIGHT", -PAD, 0)
        editBox:SetAutoFocus(false)
        editBox:SetFont(fontPath, 11, outline)
        editBox:SetTextColor(1, 1, 1, 0.9)
        editBox:SetTextInsets(8, 8, 0, 0)
        editBox:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
            dimmer:Hide()
        end)
        editBox:SetScript("OnChar", function(self)
            if self._readOnlyText then
                self:SetText(self._readOnlyText)
                self:HighlightText()
            end
        end)
        editBox:SetScript("OnEditFocusGained", function(self)
            self:HighlightText()
        end)
        editBox:SetScript("OnMouseUp", function(self)
            self:HighlightText()
        end)

        local ebBg = editBox:CreateTexture(nil, "BACKGROUND")
        ebBg:SetAllPoints()
        ebBg:SetColorTexture(0.10, 0.12, 0.16, 1)
        EUI.MakeBorder(editBox, 1, 1, 1, 0.10, EUI.PanelPP)

        local hintFS = EUI.MakeFont(popup, 9, outline, 1, 1, 1, 0.4)
        hintFS:SetPoint("TOP", editBox, "BOTTOM", 0, -6)
        hintFS:SetJustifyH("CENTER")
        hintFS:SetText("Ctrl+C to copy")

        local closeBtn = CreateFrame("Button", nil, popup)
        closeBtn:SetSize(88, 26)
        closeBtn:SetPoint("BOTTOM", popup, "BOTTOM", 0, 12)
        closeBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
        EUI.MakeStyledButton(closeBtn, "Close", 11,
            EUI.WB_COLOURS or EUI.RB_COLOURS, function() dimmer:Hide() end)

        dimmer:SetScript("OnMouseDown", function()
            if not popup:IsMouseOver() then dimmer:Hide() end
        end)

        popup:EnableKeyboard(true)
        popup:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                pcall(self.SetPropagateKeyboardInput, self, false)
                dimmer:Hide()
            else
                pcall(self.SetPropagateKeyboardInput, self, true)
            end
        end)

        popup._editBox = editBox
        wowheadDimmer = dimmer
        wowheadDimmer._popup = popup
    end

    local popup = wowheadDimmer._popup
    popup._questFS:SetText(questName)
    ApplyQuestIcon(popup._questIcon, questID)
    popup._editBox._readOnlyText = url
    popup._editBox:SetText(url)
    wowheadDimmer:Show()
    C_Timer.After(0.05, function()
        if wowheadDimmer:IsShown() then
            popup._editBox:SetFocus()
            popup._editBox:HighlightText()
        end
    end)
end

EQT.ShowWowheadQuestModal = ShowWowheadQuestModal

-------------------------------------------------------------------------------
-- Retail quest context menus (Blizzard_Menu)
-------------------------------------------------------------------------------
local _menuModifiersRegistered

local function ResolveQuestID(owner, contextData)
    if contextData and type(contextData.questID) == "number" and contextData.questID > 0 then
        return contextData.questID
    end
    if owner then
        if type(owner.questID) == "number" and owner.questID > 0 then
            return owner.questID
        end
        if type(owner.id) == "number" and owner.id > 0 then
            return owner.id
        end
    end
    if GetMouseFoci then
        local foci = GetMouseFoci()
        local region = foci and foci[1]
        if region and region.GetParent then
            local frame = region:GetParent()
            if frame and type(frame.id) == "number" and frame.id > 0 then
                return frame.id
            end
        end
    end
end

local function OnQuestContextMenu(owner, rootDescription, contextData)
    local questID = ResolveQuestID(owner, contextData)
    if not questID then return end

    rootDescription:CreateDivider()
    rootDescription:CreateButton("Wowhead URL", function()
        ShowWowheadQuestModal(questID)
    end)
end

local function RegisterQuestMenuModifiers()
    if _menuModifiersRegistered then return true end
    local Menu = _G.Menu
    if not (Menu and Menu.ModifyMenu) then return false end

    for _, tag in ipairs(MENU_TAGS) do
        Menu.ModifyMenu(tag, OnQuestContextMenu)
    end
    _menuModifiersRegistered = true
    return true
end

local function InstallQuestWowheadMenus()
    local managerHooked

    local function EnsureManagerHook()
        if managerHooked then return end
        local mgr = _G.Menu and _G.Menu.GetManager and _G.Menu.GetManager()
        if not mgr then return end
        managerHooked = true
        -- Register on first menu open (RaiderIO pattern — avoids early-session taint).
        hooksecurefunc(mgr, "OpenMenu", RegisterQuestMenuModifiers)
        hooksecurefunc(mgr, "OpenContextMenu", RegisterQuestMenuModifiers)
    end

    if RegisterQuestMenuModifiers() then return end

    local waiter = CreateFrame("Frame")
    waiter:RegisterEvent("ADDON_LOADED")
    waiter:SetScript("OnEvent", function(self, _, addonName)
        if addonName == "Blizzard_Menu" or addonName == "Blizzard_QuestLog"
            or addonName == "Blizzard_ObjectiveTracker" then
            EnsureManagerHook()
            if _menuModifiersRegistered then
                self:UnregisterAllEvents()
            end
        end
    end)

    C_Timer.After(0, EnsureManagerHook)
end

function EQT.InitWowhead()
    InstallQuestWowheadMenus()
end