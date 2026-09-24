if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_StyleChoicePopup.lua
--
--  First-install style picker. On the login AFTER the module picker's reload
--  (EllesmereUI_FirstInstall.lua stamps EllesmereUIDB.styleChoicePending in
--  its close path) one popup offers the three looks side by side, each with a
--  mock of what it means (the cards live in EllesmereUI_StyleCards.lua,
--  shared with the Style page header): the EllesmereUI style (the default; closes the
--  popup), the Blizzard style or the Classic WoW UI style (every loaded
--  module's Style flags set at once through the Style page's registry, then
--  a reload). Once per install; an existing user never sees it, since only
--  the picker writes the stamp. Global Settings > Style keeps every choice
--  reversible per module.
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI
if not EllesmereUI then return end
local EUI_HOST_ADDON = ...
local IS_STANDALONE = type(EUI_HOST_ADDON) == "string" and EUI_HOST_ADDON:find("Standalone") ~= nil
if IS_STANDALONE then return end

local PP = EllesmereUI.PanelPP
local MakeBorder = EllesmereUI.MakeBorder
local ELLESMERE_GREEN = EllesmereUI.ELLESMERE_GREEN

local function Stamp()
    if not EllesmereUIDB then EllesmereUIDB = {} end
    EllesmereUIDB.styleChoicePending = nil
    EllesmereUIDB.styleChoiceShown = true
end

-- Conflict-check handoff: while the picker is due this session the auto
-- addon-conflict check (EllesmereUI.lua) holds on _styleChoicePending, armed
-- at the parent's ADDON_LOADED below; every close that does not reload runs
-- it here (a reload's next session runs its own).
local function Release()
    if not EllesmereUI._styleChoicePending then return end
    EllesmereUI._styleChoicePending = nil
    if EllesmereUIDB and EllesmereUIDB.firstInstallPopupShown and EllesmereUI._RunConflictCheck then
        C_Timer.After(0.3, EllesmereUI._RunConflictCheck)
    end
end

-- A stock style: the flags ride the Style page's own registry (LoadOnDemand
-- options), so one code path owns what "all modules" means; then the reload
-- every style change needs. When the options addon cannot load, the popup
-- (dimmer) closes on the chat hint instead of staying up.
local function ChooseStockStyle(styleKey, label, dimmer)
    Stamp()
    if C_AddOns and C_AddOns.LoadAddOn then
        C_AddOns.LoadAddOn("EllesmereUIOptions")
    end
    local BS = EllesmereUI.BlizzStyle
    if BS and BS.ApplyAll then
        BS.ApplyAll(styleKey)
        ReloadUI()
        return
    end
    if EllesmereUI.Print then
        EllesmereUI.Print("|cff00ff98EllesmereUI:|r " .. label .. " can be switched on under Global Settings > Style.")
    end
    if dimmer then dimmer:Hide() end
    Release()
end

local function ShowStyleChoicePopup()
    if not (PP and MakeBorder and ELLESMERE_GREEN and EllesmereUI.BuildStyleCards) then
        Release()
        return
    end
    local FONT = EllesmereUI._font or EllesmereUI.EXPRESSWAY
        or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf"
    local EG = ELLESMERE_GREEN
    local POPUP_W, POPUP_H = 700, 470
    local ppScale = (EllesmereUI.GetPopupScale and EllesmereUI.GetPopupScale()) or 1

    local dimmer = CreateFrame("Frame", "EUIStyleChoiceDimmer", UIParent)
    dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
    dimmer:SetAllPoints(UIParent)
    dimmer:EnableMouse(true)
    dimmer:EnableMouseWheel(true)
    dimmer:SetScript("OnMouseWheel", function() end)
    dimmer:SetScale(ppScale)
    local dimTex = dimmer:CreateTexture(nil, "BACKGROUND")
    dimTex:SetAllPoints()
    dimTex:SetColorTexture(0, 0, 0, 0.45)

    local popup = CreateFrame("Frame", "EUIStyleChoicePopup", dimmer)
    popup:SetScale((EllesmereUI.PopupBump and EllesmereUI.PopupBump(1.15)) or 1.15)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)
    PP.Size(popup, POPUP_W, POPUP_H)
    popup:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    popup:EnableMouse(true)

    local bg = popup:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.08, 0.10, 1)

    local onePhys = 1 / (popup:GetEffectiveScale() or 1)
    local function MakeEdge()
        local t = popup:CreateTexture(nil, "BORDER")
        t:SetColorTexture(1, 1, 1, 0.15)
        if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0) end
        return t
    end
    local spT = MakeEdge(); spT:SetPoint("TOPLEFT", 0, 0); spT:SetPoint("TOPRIGHT", 0, 0); spT:SetHeight(onePhys)
    local spB = MakeEdge(); spB:SetPoint("BOTTOMLEFT", 0, 0); spB:SetPoint("BOTTOMRIGHT", 0, 0); spB:SetHeight(onePhys)
    local spL = MakeEdge(); spL:SetPoint("TOPLEFT", spT, "BOTTOMLEFT"); spL:SetPoint("BOTTOMLEFT", spB, "TOPLEFT"); spL:SetWidth(onePhys)
    local spR = MakeEdge(); spR:SetPoint("TOPRIGHT", spT, "BOTTOMRIGHT"); spR:SetPoint("BOTTOMRIGHT", spB, "TOPRIGHT"); spR:SetWidth(onePhys)

    local eyebrow = popup:CreateFontString(nil, "OVERLAY")
    eyebrow:SetFont(FONT, 13, "")
    eyebrow:SetTextColor(EG.r, EG.g, EG.b, 0.9)
    PP.Point(eyebrow, "TOP", popup, "TOP", 0, -26)
    eyebrow:SetText("CHOOSE YOUR LOOK")

    local title = popup:CreateFontString(nil, "OVERLAY")
    title:SetFont(FONT, 26, "")
    title:SetTextColor(1, 1, 1, 1)
    PP.Point(title, "TOP", eyebrow, "BOTTOM", 0, -6)
    title:SetText("How should EllesmereUI look?")

    local desc = popup:CreateFontString(nil, "OVERLAY")
    desc:SetFont(FONT, 14, "")
    desc:SetTextColor(1, 1, 1, 0.5)
    desc:SetWidth(POPUP_W - 90)
    desc:SetJustifyH("CENTER")
    desc:SetWordWrap(true)
    PP.Point(desc, "TOP", title, "BOTTOM", 0, -10)
    desc:SetText("EllesmereUI's features work with every look. Change your mind any time under Global Settings > Style.")

    local function ChooseEUI()
        Stamp()
        dimmer:Hide()
        Release()
    end

    -- The three look cards (EllesmereUI_StyleCards.lua, shared with the
    -- Style page header).
    EllesmereUI.BuildStyleCards(popup, -128, {
        buttonText = {
            eui = "Use EllesmereUI Style",
            blizzard = "Use Blizzard Style",
            classic = "Use Classic WoW UI",
        },
        onPick = function(styleKey)
            if styleKey == "blizzard" then
                ChooseStockStyle("blizzard", "Blizzard Style", dimmer)
            elseif styleKey == "classic" then
                ChooseStockStyle("classic", "Classic WoW UI", dimmer)
            else
                ChooseEUI()
            end
        end,
    })

    local footnote = popup:CreateFontString(nil, "OVERLAY")
    footnote:SetFont(FONT, 12, "")
    footnote:SetTextColor(1, 1, 1, 0.35)
    footnote:SetWidth(POPUP_W - 90)
    footnote:SetJustifyH("CENTER")
    PP.Point(footnote, "BOTTOM", popup, "BOTTOM", 0, 14)
    footnote:SetText("Blizzard Style and Classic WoW UI reload the UI once to apply. Each module can be switched separately later.")

    -- Escape = the EllesmereUI look (the non-destructive default).
    popup:EnableKeyboard(true)
    popup:SetScript("OnKeyDown", function(self, key)
        self:SetPropagateKeyboardInput(key ~= "ESCAPE")
        if key == "ESCAPE" then ChooseEUI() end
    end)

    dimmer:Show()
end

EllesmereUI.ShowStyleChoicePopup = ShowStyleChoicePopup

-------------------------------------------------------------------------------
--  Trigger: the login after the module picker's reload, once. Defers behind
--  the intro announcements the way the other popups do, so nothing stacks.
-------------------------------------------------------------------------------
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" then
        if addonName ~= "EllesmereUI" then return end
        self:UnregisterEvent("ADDON_LOADED")
        -- Arm the conflict-check hold on the same conditions the login
        -- branch shows under (the first-install loader, earlier in the TOC,
        -- has already raised _firstInstallPending by now).
        if not EllesmereUI.FOREVER_SV_BUG and EllesmereUIDB and EllesmereUIDB.styleChoicePending
            and not EllesmereUI._firstInstallPending then
            EllesmereUI._styleChoicePending = true
        end
        return
    end
    self:UnregisterEvent("PLAYER_LOGIN")
    -- TEMPORARY, WoW Forever only (EllesmereUI.FOREVER_SV_BUG): the style
    -- choice needs a reload to apply, and a reload wipes settings on the beta
    -- client, so the picker stays off there until Blizzard fixes it.
    if EllesmereUI.FOREVER_SV_BUG then return end
    if not (EllesmereUIDB and EllesmereUIDB.styleChoicePending) then return end
    -- The picker itself is still due this session: it reloads, and its
    -- close path re-arms the stamp for the login after.
    if EllesmereUI._firstInstallPending then return end
    -- A registered external installer owns the first-run experience.
    if EllesmereUI._externalInstaller then Stamp(); Release(); return end
    local tries = 0
    local function TryShow()
        if not (EllesmereUIDB and EllesmereUIDB.styleChoicePending) then
            Release()
            return
        end
        tries = tries + 1
        if tries < 25 and (EllesmereUI._raidFramesIntroPending or EllesmereUI._patchNotesIntroPending
            or EllesmereUI._windowSkinsIntroPending) then
            C_Timer.After(0.4, TryShow)
            return
        end
        ShowStyleChoicePopup()
    end
    C_Timer.After(0.8, TryShow)
end)
