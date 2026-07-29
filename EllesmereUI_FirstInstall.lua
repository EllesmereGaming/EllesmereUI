-------------------------------------------------------------------------------
--  EllesmereUI_FirstInstall.lua
--
--  One-time popup on first install that lets the user pick which EUI addons
--  to keep enabled. Visual style mirrors the Spec Assign popup (dimmer +
--  dark panel + white border + Check All / Uncheck All links + Done button).
--
--  Layout: three columns (Core / QoL / UI Reskin), one checkbox per row,
--  groups build down independently.
--
--  Fires at PLAYER_LOGIN, BEFORE the conflict-check popup (see EllesmereUI.lua
--  which now gates its conflict check on EllesmereUIDB.firstInstallPopupShown).
-------------------------------------------------------------------------------

local EllesmereUI = _G.EllesmereUI
if not EllesmereUI then return end

-- Standalone builds bundle this file too, but the multi-module picker is
-- meaningless there: its GROUPS reference suite sibling addons (Action Bars,
-- Nameplates, ...) that simply do not exist in a single-module standalone. So
-- the first-install popup is suite-only. The build never renames the word
-- "Standalone", so deriving this from the host addon name (the `...` vararg =
-- real folder name) is the rename-immune switch -- false in the suite (host
-- "EllesmereUI"), true in any "EUIStandalone*" host. See the loader guard below.
local EUI_HOST_ADDON = ...
local IS_STANDALONE = type(EUI_HOST_ADDON) == "string" and EUI_HOST_ADDON:find("Standalone") ~= nil

local PP = EllesmereUI.PanelPP

local MakeBorder = EllesmereUI.MakeBorder
local ELLESMERE_GREEN = EllesmereUI.ELLESMERE_GREEN

local BORDER_R     = EllesmereUI.BORDER_R     or 1
local BORDER_G     = EllesmereUI.BORDER_G     or 1
local BORDER_B     = EllesmereUI.BORDER_B     or 1
local CB_BOX_R     = EllesmereUI.CB_BOX_R     or 0.075
local CB_BOX_G     = EllesmereUI.CB_BOX_G     or 0.113
local CB_BOX_B     = EllesmereUI.CB_BOX_B     or 0.141
local CB_BRD_A     = EllesmereUI.CB_BRD_A     or 0.25
local CB_ACT_BRD_A = EllesmereUI.CB_ACT_BRD_A or 0.85

-- Groups: { header, { entries } } where each entry is { label = "...", addon = "..." (folder) }
-- If addon is nil the checkbox is informational / disabled (e.g. Cursor Circle, Bags).
local GROUPS = {
    {
        header = "Core Addons",
        entries = {
            { label = "Action Bars",      addon = "EllesmereUIActionBars" },
            { label = "Nameplates",       addon = "EllesmereUINameplates" },
            { label = "Unit Frames",      addon = "EllesmereUIUnitFrames" },
            { label = "Cooldown Manager", addon = "EllesmereUICooldownManager" },
            { label = "Resource Bars",    addon = "EllesmereUIResourceBars" },
            { label = "Raid Frames",      addon = "EllesmereUIRaidFrames" },
        },
    },
    {
        header = "QoL Addons",
        entries = {
            { label = "Quality of Life",     addon = "EllesmereUIQoL" },
            { label = "AuraBuff Reminders",  addon = "EllesmereUIAuraBuffReminders" },
            { label = "DataBars",            addon = "EllesmereUIDataBars" },
            -- Cursor Circle is a feature inside the QoL addon (cursor.enabled).
            -- The checkbox here is a front-end shortcut that writes directly to
            -- the QoL profile so users get a sensible default on first install.
            { label = "Cursor Circle",       setting = "cursorCircle", defaultChecked = false },
        },
    },
    {
        header = "UI Reskin Addons",
        entries = {
            { label = "Blizz UI Enhanced", addon = "EllesmereUIBlizzardSkin" },
            { label = "Friends List",      addon = "EllesmereUIFriends" },
            { label = "Damage Meters",     addon = "EllesmereUIDamageMeters" },
            { label = "Chat",              addon = "EllesmereUIChat" },
            { label = "Bags",              addon = "EllesmereUIBags" },
            { label = "Mythic+ Timer",     addon = "EllesmereUIMythicTimer" },
            { label = "Quest Tracker",     addon = "EllesmereUIQuestTracker" },
        },
    },
}

local function IsAddonEnabled(folder)
    if not folder then return true end
    if C_AddOns and C_AddOns.GetAddOnEnableState then
        local char = UnitName("player")
        return (C_AddOns.GetAddOnEnableState(folder, char) or 0) > 0
    end
    return true
end

local function SetAddonEnabled(folder, enabled)
    if not folder or not C_AddOns then return end
    if enabled then
        if C_AddOns.EnableAddOn then C_AddOns.EnableAddOn(folder) end
    else
        if C_AddOns.DisableAddOn then C_AddOns.DisableAddOn(folder) end
    end
end

local function ShowFirstInstallPopup()
    local FONT   = EllesmereUI._font or ("Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf")
    local NUM_COLS = #GROUPS
    local COL_W         = 210
    local COL_GAP       = 18
    local CONTENT_LEFT  = 41
    local CONTENT_RIGHT = 36
    local CONTENT_TOP   = 216   -- below the header band + eyebrow/title/subtitle
    local HEADER_H      = 32
    local HEADER_PAD    = 6
    local ROW_H         = 28
    local BOX_SZ        = 18
    local CHECK_INSET   = 3

    local POPUP_W = CONTENT_LEFT + CONTENT_RIGHT + NUM_COLS * COL_W + (NUM_COLS - 1) * COL_GAP

    -- Compute popup height from the tallest group
    local tallestRows = 0
    for _, g in ipairs(GROUPS) do
        if #g.entries > tallestRows then tallestRows = #g.entries end
    end
    local contentH = HEADER_H + HEADER_PAD + tallestRows * ROW_H
    local POPUP_H  = CONTENT_TOP + contentH + 110  -- room for links + button

    local ppScale = (EllesmereUI.GetPopupScale and EllesmereUI.GetPopupScale()) or 1

    -- Dimmer
    local dimmer = CreateFrame("Frame", "EUIFirstInstallDimmer", UIParent)
    dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
    dimmer:SetAllPoints(UIParent)
    dimmer:EnableMouse(true)
    dimmer:EnableMouseWheel(true)
    dimmer:SetScript("OnMouseWheel", function() end)
    dimmer:SetScale(ppScale)
    local dimTex = dimmer:CreateTexture(nil, "BACKGROUND")
    dimTex:SetAllPoints()
    dimTex:SetColorTexture(0, 0, 0, 0.35)

    -- Popup
    local popup = CreateFrame("Frame", "EUIFirstInstallPopup", dimmer)
    popup:SetScale(ppScale)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)
    PP.Size(popup, POPUP_W, POPUP_H)
    popup:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    popup:EnableMouse(true)

    local bg = popup:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.08, 0.10, 1)

    -- 1 physical-pixel white border (announcement-popup chrome), scale-derived
    -- so each edge stays exactly one physical pixel. Snap disabled.
    local onePhys = 1 / (popup:GetEffectiveScale() or 1)
    local BRD_A = 0.15
    local function MakeEdge()
        local t = popup:CreateTexture(nil, "BORDER")
        t:SetColorTexture(1, 1, 1, BRD_A)
        if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0) end
        return t
    end
    local spT = MakeEdge(); spT:SetPoint("TOPLEFT", 0, 0); spT:SetPoint("TOPRIGHT", 0, 0); spT:SetHeight(onePhys)
    local spB = MakeEdge(); spB:SetPoint("BOTTOMLEFT", 0, 0); spB:SetPoint("BOTTOMRIGHT", 0, 0); spB:SetHeight(onePhys)
    local spL = MakeEdge(); spL:SetPoint("TOPLEFT", spT, "BOTTOMLEFT"); spL:SetPoint("BOTTOMLEFT", spB, "TOPLEFT"); spL:SetWidth(onePhys)
    local spR = MakeEdge(); spR:SetPoint("TOPRIGHT", spT, "BOTTOMRIGHT"); spR:SetPoint("BOTTOMRIGHT", spB, "TOPRIGHT"); spR:SetWidth(onePhys)

    -- Decorative header visual (announcement-popup style): three mini module
    -- cards echoing the three picker columns below, each with the green top
    -- accent and a checked box beside stand-in text lines. The center card is
    -- slightly taller/brighter, matching the sibling popups' motif.
    do
        local EGh = ELLESMERE_GREEN
        local CARD_W, CARD_H, CARD_GAP = 124, 52, 14
        local MIDLINE = -54
        for i = 1, 3 do
            local isCenter = (i == 2)
            local w = CARD_W
            local h = isCenter and (CARD_H + 10) or CARD_H
            local card = CreateFrame("Frame", nil, popup)
            card:SetFrameLevel(popup:GetFrameLevel() + 1)
            PP.Size(card, w, h)
            PP.Point(card, "CENTER", popup, "TOP", (i - 2) * (CARD_W + CARD_GAP), MIDLINE)
            local cbg = card:CreateTexture(nil, "BACKGROUND")
            cbg:SetAllPoints()
            cbg:SetColorTexture(0.12, 0.13, 0.15, 1)

            -- Green top accent (the suite's hero-card signature).
            local accent = card:CreateTexture(nil, "ARTWORK")
            accent:SetColorTexture(EGh.r, EGh.g, EGh.b, isCenter and 0.95 or 0.7)
            accent:SetHeight(2)
            PP.Point(accent, "TOPLEFT", card, "TOPLEFT", 1, -1)
            PP.Point(accent, "TOPRIGHT", card, "TOPRIGHT", -1, -1)
            if accent.SetSnapToPixelGrid then accent:SetSnapToPixelGrid(false); accent:SetTexelSnappingBias(0) end

            -- Checked box + stand-in lines: the picker rows in miniature.
            local box = card:CreateTexture(nil, "ARTWORK")
            box:SetColorTexture(CB_BOX_R, CB_BOX_G, CB_BOX_B, 1)
            PP.Size(box, 12, 12)
            PP.Point(box, "TOPLEFT", card, "TOPLEFT", 12, -14)
            local check = card:CreateTexture(nil, "OVERLAY")
            check:SetColorTexture(EGh.r, EGh.g, EGh.b, isCenter and 1 or 0.8)
            PP.Size(check, 6, 6)
            PP.Point(check, "CENTER", box, "CENTER", 0, 0)
            local l1 = card:CreateTexture(nil, "ARTWORK")
            l1:SetColorTexture(1, 1, 1, isCenter and 0.42 or 0.32)
            PP.Size(l1, w - 52, 5)
            PP.Point(l1, "LEFT", box, "RIGHT", 8, 0)
            local l2 = card:CreateTexture(nil, "ARTWORK")
            l2:SetColorTexture(1, 1, 1, 0.16)
            PP.Size(l2, w - 72, 5)
            PP.Point(l2, "TOPLEFT", box, "BOTTOMLEFT", 0, -8)
            if isCenter then
                local l3 = card:CreateTexture(nil, "ARTWORK")
                l3:SetColorTexture(1, 1, 1, 0.12)
                PP.Size(l3, w - 84, 5)
                PP.Point(l3, "TOPLEFT", l2, "BOTTOMLEFT", 0, -7)
            end
            MakeBorder(card, 1, 1, 1, isCenter and 0.16 or 0.10, PP)
        end
    end

    -- Eyebrow
    local eyebrow = popup:CreateFontString(nil, "OVERLAY")
    eyebrow:SetFont(FONT, 13, "")
    eyebrow:SetTextColor(ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b, 0.9)
    PP.Point(eyebrow, "TOP", popup, "TOP", 0, -104)
    eyebrow:SetText("FIRST TIME SETUP")

    -- Title
    local title = popup:CreateFontString(nil, "OVERLAY")
    title:SetFont(FONT, 25, "")
    title:SetTextColor(1, 1, 1, 1)
    PP.Point(title, "TOP", eyebrow, "BOTTOM", 0, -6)
    title:SetText("Welcome to EllesmereUI")

    -- Subtitle
    local sub = popup:CreateFontString(nil, "OVERLAY")
    sub:SetFont(FONT, 14, "")
    sub:SetTextColor(1, 1, 1, 0.45)
    PP.Point(sub, "TOP", title, "BOTTOM", 0, -8)
    sub:SetWidth(POPUP_W - 60)
    sub:SetJustifyH("CENTER")
    sub:SetWordWrap(true)
    sub:SetText("Choose which addons you want enabled. You can change any of these later in the EllesmereUI settings panel.")

    -- Check All / Uncheck All links
    local LINK_Y = -196
    local LINK_GAP = 20

    local checkAllBtn = CreateFrame("Button", nil, popup)
    checkAllBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
    local checkAllLbl = checkAllBtn:CreateFontString(nil, "OVERLAY")
    checkAllLbl:SetFont(FONT, 14, "")
    checkAllLbl:SetText("Check All")
    checkAllLbl:SetTextColor(1, 1, 1, 0.45)
    checkAllLbl:SetPoint("CENTER")
    checkAllBtn:SetSize(checkAllLbl:GetStringWidth() + 4, 20)
    PP.Point(checkAllBtn, "TOPLEFT", popup, "TOPLEFT", CONTENT_LEFT, LINK_Y)
    checkAllBtn:SetScript("OnEnter", function() checkAllLbl:SetTextColor(1, 1, 1, 0.80) end)
    checkAllBtn:SetScript("OnLeave", function() checkAllLbl:SetTextColor(1, 1, 1, 0.45) end)

    local linkDivider = popup:CreateTexture(nil, "OVERLAY", nil, 7)
    linkDivider:SetColorTexture(1, 1, 1, 0.18)
    if linkDivider.SetSnapToPixelGrid then linkDivider:SetSnapToPixelGrid(false); linkDivider:SetTexelSnappingBias(0) end
    PP.Point(linkDivider, "LEFT", checkAllBtn, "RIGHT", LINK_GAP / 2, 0)
    linkDivider:SetWidth(1)
    linkDivider:SetHeight(12)

    local uncheckAllBtn = CreateFrame("Button", nil, popup)
    uncheckAllBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
    local uncheckAllLbl = uncheckAllBtn:CreateFontString(nil, "OVERLAY")
    uncheckAllLbl:SetFont(FONT, 14, "")
    uncheckAllLbl:SetText("Uncheck All")
    uncheckAllLbl:SetTextColor(1, 1, 1, 0.45)
    uncheckAllLbl:SetPoint("CENTER")
    uncheckAllBtn:SetSize(uncheckAllLbl:GetStringWidth() + 4, 20)
    PP.Point(uncheckAllBtn, "LEFT", checkAllBtn, "RIGHT", LINK_GAP, 0)
    uncheckAllBtn:SetScript("OnEnter", function() uncheckAllLbl:SetTextColor(1, 1, 1, 0.80) end)
    uncheckAllBtn:SetScript("OnLeave", function() uncheckAllLbl:SetTextColor(1, 1, 1, 0.45) end)

    -- Track all checkbox rows for check-all / uncheck-all + change detection
    local allRows = {}

    -- Track initial states so we can tell if user changed anything
    local initialState = {}

    -- Build the three columns
    for colIdx, group in ipairs(GROUPS) do
        local col = CreateFrame("Frame", nil, popup)
        col:SetFrameLevel(popup:GetFrameLevel() + 1)
        local colX = CONTENT_LEFT + (colIdx - 1) * (COL_W + COL_GAP)
        PP.Point(col, "TOPLEFT", popup, "TOPLEFT", colX, -CONTENT_TOP)
        PP.Size(col, COL_W, POPUP_H - CONTENT_TOP - 80)

        -- Group header (styled like a class header)
        local hdr = col:CreateFontString(nil, "OVERLAY")
        hdr:SetFont(FONT, 18, "")
        hdr:SetTextColor(ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b, 0.9)
        PP.Point(hdr, "TOPLEFT", col, "TOPLEFT", 4, -4)
        hdr:SetText(group.header)

        local yOff = HEADER_H + HEADER_PAD

        for _, entry in ipairs(group.entries) do
            local row = CreateFrame("Button", nil, col)
            PP.Size(row, COL_W, ROW_H)
            row:ClearAllPoints()
            PP.Point(row, "TOPLEFT", col, "TOPLEFT", 0, -yOff)

            local box = CreateFrame("Frame", nil, row)
            PP.Size(box, BOX_SZ, BOX_SZ)
            PP.Point(box, "LEFT", row, "LEFT", 8, 0)
            box:SetFrameLevel(row:GetFrameLevel() + 1)

            local boxBg = box:CreateTexture(nil, "BACKGROUND")
            boxBg:SetAllPoints()
            boxBg:SetColorTexture(CB_BOX_R, CB_BOX_G, CB_BOX_B, 1)
            local boxBorder = MakeBorder(box, BORDER_R, BORDER_G, BORDER_B, CB_BRD_A, PP)

            local check = box:CreateTexture(nil, "ARTWORK")
            PP.Point(check, "TOPLEFT", box, "TOPLEFT", CHECK_INSET, -CHECK_INSET)
            PP.Point(check, "BOTTOMRIGHT", box, "BOTTOMRIGHT", -CHECK_INSET, CHECK_INSET)
            check:SetColorTexture(ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b, 1)

            local lbl = row:CreateFontString(nil, "OVERLAY")
            lbl:SetFont(FONT, 17, "")
            PP.Point(lbl, "LEFT", box, "RIGHT", 8, 0)
            lbl:SetTextColor(1, 1, 1, 0.65)
            lbl:SetText(entry.label)

            -- Initial state resolution:
            --   entry.comingSoon -> disabled, greyed, "Coming soon" tooltip
            --   entry.addon      -> current C_AddOns enable state
            --   entry.setting    -> start at entry.defaultChecked (front-end shortcut)
            --   neither          -> disabled, generic greyed state
            local checked
            if entry.comingSoon then
                checked = false
            elseif entry.addon then
                checked = IsAddonEnabled(entry.addon)
            elseif entry.setting then
                checked = entry.defaultChecked and true or false
            else
                checked = false
            end
            initialState[entry.label] = checked

            row._entry = entry
            row._checked = checked
            row._check = check
            row._boxBorder = boxBorder
            row._lbl = lbl
            row._informational = (entry.comingSoon == true)
                or (entry.addon == nil and entry.setting == nil)

            local function UpdateVisual(r)
                if r._informational then
                    r._check:Hide()
                    r._boxBorder:SetColor(BORDER_R, BORDER_G, BORDER_B, CB_BRD_A * 0.4)
                    r._boxBg:SetColorTexture(CB_BOX_R, CB_BOX_G, CB_BOX_B, 0.35)
                    r._lbl:SetTextColor(1, 1, 1, 0.25)
                elseif r._checked then
                    r._check:Show()
                    r._boxBorder:SetColor(ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b, CB_ACT_BRD_A)
                else
                    r._check:Hide()
                    r._boxBorder:SetColor(BORDER_R, BORDER_G, BORDER_B, CB_BRD_A)
                end
            end
            row._boxBg = boxBg
            UpdateVisual(row)

            row:SetScript("OnClick", function(self)
                if self._informational then return end
                self._checked = not self._checked
                UpdateVisual(self)
            end)
            row:SetScript("OnEnter", function(self)
                if self._informational then
                    if EllesmereUI.ShowWidgetTooltip then
                        EllesmereUI.ShowWidgetTooltip(self, "Coming soon")
                    end
                    return
                end
                self._lbl:SetTextColor(1, 1, 1, 0.90)
            end)
            row:SetScript("OnLeave", function(self)
                if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
                if self._informational then return end
                self._lbl:SetTextColor(1, 1, 1, 0.65)
            end)

            allRows[#allRows + 1] = row
            yOff = yOff + ROW_H
        end
    end

    -- Done button (text swaps between "Okay" and "Reload UI" based on changes)
    local EG = ELLESMERE_GREEN
    local doneBtn = CreateFrame("Button", nil, popup)
    doneBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
    PP.Size(doneBtn, 200, 39)
    PP.Point(doneBtn, "BOTTOM", popup, "BOTTOM", 0, 38)
    local doneBg = doneBtn:CreateTexture(nil, "BACKGROUND")
    doneBg:SetAllPoints()
    doneBg:SetColorTexture(0.06, 0.08, 0.10, 0.92)
    local doneBrd = MakeBorder(doneBtn, EG.r, EG.g, EG.b, 0.9, PP)
    local doneLbl = doneBtn:CreateFontString(nil, "OVERLAY")
    doneLbl:SetFont(FONT, 16, "")
    PP.Point(doneLbl, "CENTER", doneBtn, "CENTER", 0, 0)
    doneLbl:SetTextColor(EG.r, EG.g, EG.b, 0.9)
    doneBtn:SetScript("OnEnter", function()
        doneLbl:SetTextColor(EG.r, EG.g, EG.b, 1)
        doneBrd:SetColor(EG.r, EG.g, EG.b, 1)
    end)
    doneBtn:SetScript("OnLeave", function()
        doneLbl:SetTextColor(EG.r, EG.g, EG.b, 0.9)
        doneBrd:SetColor(EG.r, EG.g, EG.b, 0.9)
    end)

    local function HasChanges()
        for _, row in ipairs(allRows) do
            if not row._informational and row._checked ~= initialState[row._entry.label] then
                return true
            end
        end
        return false
    end

    local function RefreshButtonLabel()
        -- Picking addons always ends in a reload so the enable/disable choices
        -- take effect, so the button always reads "Reload UI".
        doneLbl:SetText("Reload UI")
    end
    RefreshButtonLabel()

    -- Hook each checkbox click to refresh the button label
    for _, row in ipairs(allRows) do
        local origOnClick = row:GetScript("OnClick")
        row:SetScript("OnClick", function(self, ...)
            if origOnClick then origOnClick(self, ...) end
            RefreshButtonLabel()
        end)
    end

    -- Check All / Uncheck All wiring
    checkAllBtn:SetScript("OnClick", function()
        for _, row in ipairs(allRows) do
            if not row._informational and not row._checked then
                row._checked = true
                row._check:Show()
                row._boxBorder:SetColor(ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b, CB_ACT_BRD_A)
            end
        end
        RefreshButtonLabel()
    end)
    uncheckAllBtn:SetScript("OnClick", function()
        for _, row in ipairs(allRows) do
            if not row._informational and row._checked then
                row._checked = false
                row._check:Hide()
                row._boxBorder:SetColor(BORDER_R, BORDER_G, BORDER_B, CB_BRD_A)
            end
        end
        RefreshButtonLabel()
    end)

    local function Close(triggerReload)
        if not EllesmereUIDB then EllesmereUIDB = {} end
        EllesmereUIDB.firstInstallPopupShown = true
        EllesmereUIDB.bagsUserChosen = true
        EllesmereUI._firstInstallPending = nil

        -- Write QoL cursor setting directly into the profile table so it
        -- survives even if the user also disables the QoL addon. NewDB merges
        -- defaults with stored values at next init, so the written value sticks.
        local function ApplyCursorCircle(enabled)
            if not EllesmereUIDB then EllesmereUIDB = {} end
            if not EllesmereUIDB.profiles then EllesmereUIDB.profiles = {} end
            local profileName = EllesmereUIDB.activeProfile or "Default"
            if type(EllesmereUIDB.profiles[profileName]) ~= "table" then
                EllesmereUIDB.profiles[profileName] = {}
            end
            local prof = EllesmereUIDB.profiles[profileName]
            if not prof.addons then prof.addons = {} end
            if not prof.addons.EllesmereUIQoL then prof.addons.EllesmereUIQoL = {} end
            if not prof.addons.EllesmereUIQoL.cursor then prof.addons.EllesmereUIQoL.cursor = {} end
            prof.addons.EllesmereUIQoL.cursor.enabled = enabled and true or false
        end

        -- Always write the Cursor Circle choice, even on "no reload" close,
        -- since the default (cursor.enabled = true) differs from the popup's
        -- default-unchecked state.
        for _, row in ipairs(allRows) do
            if row._entry.setting == "cursorCircle" then
                ApplyCursorCircle(row._checked)
            end
        end

        if triggerReload then
            -- Apply addon enable/disable changes then reload
            for _, row in ipairs(allRows) do
                if row._entry.addon then
                    SetAddonEnabled(row._entry.addon, row._checked)
                end
            end
            ReloadUI()
            return
        end

        dimmer:Hide()
        -- Re-apply the cursor so the written setting takes effect live
        -- (the QoL addon had already applied its default at login).
        if _G._ECL_Apply then pcall(_G._ECL_Apply) end
        -- No reload needed, so run the deferred conflict check now
        if EllesmereUI._RunConflictCheck then
            C_Timer.After(0.5, EllesmereUI._RunConflictCheck)
        end
    end

    doneBtn:SetScript("OnClick", function()
        -- Always reload so the addon enable/disable selections take effect.
        Close(true)
    end)

    -- Escape is disabled: the user must click Reload UI so their addon
    -- selection always takes effect. Consume Escape; let other keys propagate.
    popup:EnableKeyboard(true)
    popup:SetScript("OnKeyDown", function(self, key)
        self:SetPropagateKeyboardInput(key ~= "ESCAPE")
    end)

    dimmer:Show()
end

EllesmereUI.ShowFirstInstallPopup = ShowFirstInstallPopup

-------------------------------------------------------------------------------
--  Trigger on first install only
-------------------------------------------------------------------------------
-- First-install detection captured at parent ADDON_LOADED. At that moment
-- EllesmereUIDB still reflects the PREVIOUS session's data: child addons
-- have not yet initialized their DBs this session, so any profile.addons
-- entries can only have come from a prior version. This cleanly separates
-- upgrades from fresh installs without needing version stamps.
-- Standalone: never arm the suite first-install picker (see note at top of file).
-- This makes the non-firing explicit rather than relying on the incidental
-- addon-name mismatch (the renamed "EllesmereUI" ADDON_LOADED gate would point at
-- the core token, never the real child/folder token, so it never matched anyway).
if IS_STANDALONE then return end

local _showPopupOnLogin = false

local function ComputeShowOnLogin()
    if not EllesmereUIDB then
        -- Truly fresh: SV not written yet.
        return true
    end
    if EllesmereUIDB.firstInstallPopupShown then
        return false
    end
    local profiles = EllesmereUIDB.profiles
    if type(profiles) == "table" then
        for _, prof in pairs(profiles) do
            if type(prof) == "table" and type(prof.addons) == "table" and next(prof.addons) then
                -- Data from a previous session: upgrade user, stamp + skip.
                EllesmereUIDB.firstInstallPopupShown = true
                return false
            end
        end
    end
    -- No prior data exists: treat as fresh install.
    return true
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" then
        if addonName ~= "EllesmereUI" then return end
        self:UnregisterEvent("ADDON_LOADED")
        _showPopupOnLogin = ComputeShowOnLogin()
        if _showPopupOnLogin then
            -- Handshake for other first-login popups (e.g. CDM's Edit Mode
            -- reload prompt): the picker is coming and ALWAYS ends in its own
            -- forced ReloadUI, so reload-prompting popups must stay silent and
            -- let that reload apply their changes. Cleared in Close().
            EllesmereUI._firstInstallPending = true
        end
    elseif event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        if not _showPopupOnLogin then return end
        C_Timer.After(0.5, function()
            if EllesmereUIDB and EllesmereUIDB.firstInstallPopupShown then return end
            -- A registered external installer owns the first-run experience:
            -- keep the picker silent (the pending handshake stays armed; the
            -- installer's import stamps first-install state, and a session
            -- with no registration brings the picker back).
            if EllesmereUI._externalInstaller then return end
            ShowFirstInstallPopup()
        end)
    end
end)
