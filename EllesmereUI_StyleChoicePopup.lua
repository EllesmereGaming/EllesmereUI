if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_StyleChoicePopup.lua
--
--  First-install style picker. On the login AFTER the module picker's reload
--  (EllesmereUI_FirstInstall.lua stamps EllesmereUIDB.styleChoicePending in
--  its close path) one popup offers the three looks side by side, each with a
--  mock of what it means (the cards live in EllesmereUI_StyleCards.lua,
--  shared with the Style page header): the EllesmereUI style, the Blizzard
--  style or the Classic WoW UI style, or on the WoW Forever client also the
--  WoW Forever variant. The card of the look this session already renders
--  shows IN USE and stays lit as on the Style page; it keeps its hover and
--  closes the popup with nothing written, and so does Escape; any other card
--  sets every loaded module's Style flags at once through the Style page's
--  registry, then reloads. The default look (the first card, tagged DEFAULT)
--  is the EllesmereUI style, or WoW Forever on that client; either is
--  normally the look in use (on WoW Forever the module picker applies it as
--  its reload is confirmed).
--  Once per install; an existing user never sees it, since only a first
--  install writes the stamp (the module picker's close, and on WoW Forever
--  also the first-install loader at ADDON_LOADED in EllesmereUI_FirstInstall.lua).
--  Global Settings > Style keeps every choice
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

-- Every loaded module to one look: the flags ride the Style page's own
-- registry (LoadOnDemand options), so one code path owns what "all modules"
-- means. False when the options addon cannot load. The module picker runs it
-- too on WoW Forever (EllesmereUI_FirstInstall.lua), as its reload's
-- pre-reload step. The caller reloads.
local function ApplyLook(styleKey)
    if not EllesmereUI.EnsureOptionsLoaded() then return false end
    local BS = EllesmereUI.BlizzStyle
    if not (BS and BS.ApplyAll) then return false end
    BS.ApplyAll(styleKey)
    return true
end
EllesmereUI.ApplyFirstInstallLook = ApplyLook

-- A look other than the one this session renders: applied, then the reload
-- every style change needs. When the options addon cannot load, the popup
-- (dimmer) closes on the chat hint instead of staying up.
local function ChooseOtherLook(styleKey, label, dimmer)
    Stamp()
    if ApplyLook(styleKey) then
        EllesmereUI.RequestReload(nil, EllesmereUI.L("Style changed for this profile. A UI reload is needed to apply it."))
        -- On the Forever client the reload waits on its popup: the choice is
        -- made, so the picker closes under it. Retail is already reloading.
        if dimmer then dimmer:Hide() end
        return
    end
    EllesmereUI.Print("|cff00ff98EllesmereUI:|r " .. label .. " can be switched on under Global Settings > Style.")
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
    -- Wide enough for the card row (four cards on the WoW Forever client).
    local POPUP_W, POPUP_H = math.max(700, EllesmereUI.STYLE_CARDS_W + 32), 480
    -- The DEFAULT card: EllesmereUI, or on the WoW Forever client WoW
    -- Forever, the look a fresh install there starts on.
    local defaultKey = EllesmereUI.IS_FOREVER and "forever" or "eui"
    -- The look this session renders, read from the modules: its card closes
    -- the popup with nothing written. The default while no styleable module
    -- is loaded; none while the loaded modules render different looks
    -- (every card applies then).
    local rendered = EllesmereUI.RenderedLook()
    local activeKey = rendered
    if activeKey == nil then activeKey = defaultKey elseif activeKey == false then activeKey = nil end
    local KeepLook, OnPick
    -- Escape keeps whatever renders: it never writes.
    local dimmer, popup = EllesmereUI.BuildPopupShell("EUIStyleChoice", {
        w = POPUP_W, h = POPUP_H, bump = 1.15, dimAlpha = 0.45,
        onEscape = function() KeepLook() end,
    })

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

    KeepLook = function()
        Stamp()
        dimmer:Hide()
        Release()
    end

    OnPick = function(styleKey)
        if styleKey == activeKey then
            KeepLook()
        elseif styleKey == "blizzard" then
            ChooseOtherLook("blizzard", "Blizzard Style", dimmer)
        elseif styleKey == "classic" then
            ChooseOtherLook("classic", "Classic WoW UI", dimmer)
        elseif styleKey == "forever" then
            ChooseOtherLook("forever", "WoW Forever", dimmer)
        else
            ChooseOtherLook("eui", "EllesmereUI Style", dimmer)
        end
    end

    -- The look cards (EllesmereUI_StyleCards.lua, shared with the Style page
    -- header): three, plus WoW Forever on that client, the default card first.
    -- Set 10 below the description so the IN USE badge above a card clears it.
    local cards = EllesmereUI.BuildStyleCards(popup, -138, {
        buttonText = {
            eui = "Use EllesmereUI Style",
            blizzard = "Use Blizzard Style",
            classic = "Use Classic WoW UI",
            forever = "Use WoW Forever",
        },
        defaultKey = defaultKey,
        onPick = OnPick,
    })
    -- The look the loaded modules render: IN USE and lit, as on the Style page
    -- (no card while none is loaded or their looks differ). It stays pickable,
    -- hover included: clicking it keeps the look and closes the popup.
    local inUse = cards and type(rendered) == "string" and cards[rendered]
    if inUse then inUse:SetState(true, true, "In Use") end

    local footnote = popup:CreateFontString(nil, "OVERLAY")
    footnote:SetFont(FONT, 12, "")
    footnote:SetTextColor(1, 1, 1, 0.35)
    footnote:SetWidth(POPUP_W - 90)
    footnote:SetJustifyH("CENTER")
    PP.Point(footnote, "BOTTOM", popup, "BOTTOM", 0, 14)
    -- Names the cards that reload: every one but the active look's.
    if EllesmereUI.IS_FOREVER and activeKey == "forever" then
        footnote:SetText(EllesmereUI.L("EllesmereUI Style, Blizzard Style and Classic WoW UI reload the UI once to apply. Each module can be switched separately later."))
    elseif activeKey == "eui" and EllesmereUI.IS_FOREVER then
        footnote:SetText(EllesmereUI.L("WoW Forever, Blizzard Style and Classic WoW UI reload the UI once to apply. Each module can be switched separately later."))
    elseif activeKey == "eui" then
        footnote:SetText("Blizzard Style and Classic WoW UI reload the UI once to apply. Each module can be switched separately later.")
    else
        footnote:SetText(EllesmereUI.L("Every look but the one in use reloads the UI once to apply. Each module can be switched separately later."))
    end

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
        if EllesmereUIDB and EllesmereUIDB.styleChoicePending
            and not EllesmereUI._firstInstallPending then
            EllesmereUI._styleChoicePending = true
        end
        return
    end
    self:UnregisterEvent("PLAYER_LOGIN")
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
