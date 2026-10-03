if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Profiles_Options.lua -- Global Settings > Profiles (and its Presets
--  subpage). It registers nothing: the Global Settings module
--  (EUI__General_Options.lua) dispatches its builder.
-------------------------------------------------------------------------------
local PP = EllesmereUI.PanelPP

---------------------------------------------------------------------------
--  Profiles page
---------------------------------------------------------------------------

-- Red warning string from a decoded payload's meta vs the current client; nil when nothing mismatches. skipScale = user already accepted
-- the scale-match popup, so omit the UI-scale line (resolution line still shows).
local function BuildScaleWarning(payload, skipScale)
    if not payload or not payload.meta then return nil end
    local m = payload.meta
    local warnings = {}
    local myScale  = EllesmereUIDB and EllesmereUIDB.ppUIScale or (UIParent and UIParent:GetScale()) or 1
    local expScale = m.euiScale or m.uiScale
    if not skipScale and expScale and math.abs(myScale - expScale) > 0.02 then
        local expPct = math.floor(expScale * 100 + 0.5)
        local myPct  = math.floor(myScale  * 100 + 0.5)
        warnings[#warnings + 1] = EllesmereUI.Lf("UI Scale Issue: Profile was made at %1$d%%, yours is %2$d%%", expPct, myPct)
    end
    local sw, sh = GetPhysicalScreenSize()
    local mySW  = sw and math.floor(sw) or 0
    local mySH  = sh and math.floor(sh) or 0
    local expSW = m.screenW or 0
    local expSH = m.screenH or 0
    if expSW > 0 and expSH > 0 and (mySW ~= expSW or mySH ~= expSH) then
        warnings[#warnings + 1] = EllesmereUI.Lf("Resolution Issue: Profile was made at %1$dx%2$d, yours is %3$dx%4$d", expSW, expSH, mySW, mySH)
    end
    if #warnings == 0 then return nil end
    return EllesmereUI.L("WARNING: Frame positions may be off.") .. "\n" .. table.concat(warnings, "\n")
end

-- Between the string/preset page and the import options page: if the string carries a different UI scale, ask ONCE whether to adopt it.
-- cont(applyScale) ALWAYS runs -- true = apply the imported scale (options page then omits its UI-scale warning), false = keep the user's
-- own. ShowConfirmPopup routes ESC/click-outside to onCancel, so the page transition can never strand.
local function MaybeConfirmUIScale(payload, cont)
    local expScale = payload and payload.data
        and type(payload.data.uiScale) == "number" and payload.data.uiScale or nil
    local myScale = EllesmereUIDB and EllesmereUIDB.ppUIScale
        or (UIParent and UIParent:GetScale()) or 1
    if not expScale or math.abs(myScale - expScale) <= 0.02 then
        cont(false)
        return
    end
    local expPct = math.floor(expScale * 100 + 0.5)
    local myPct  = math.floor(myScale * 100 + 0.5)
    EllesmereUI:ShowConfirmPopup({
        title = EllesmereUI.L("UI Scale Mismatch"),
        message = EllesmereUI.Lf("This profile was made at %1$d%% UI scale; yours is %2$d%%. Change your UI scale to match the imported profile? This will show all profiles at this scale as UI Scale is not a per-profile setting, but can be changed at any time back to your original value.", expPct, myPct),
        confirmText = EllesmereUI.L("Match Scale"),
        cancelText = EllesmereUI.L("Keep Mine"),
        onConfirm = function() cont(true) end,
        onCancel = function() cont(false) end,
    })
end

-- Profile import/export module lists: shared row geometry.
local SIDE_PAD, ROW_H_A, CHK_SZ, STATUS_W = 26, 48, 18, 70
local INCLUDE_CENTER_X = -(SIDE_PAD + STATUS_W + 30 + CHK_SZ / 2)

-- One module-list checkbox row. o: active (clickable), inactiveText +
-- inactiveColor {r,g,b,a}, visuals (repaint list), onToggle(apply) after
-- the value flips, linked() -> members, own key, display map, linkedTip(list),
-- blockedTip (hover text on inactive rows; nil = silent).
local function BuildAddonListRow(scrollChild, i, item, totalW, o)
    local EG = EllesmereUI.ELLESMERE_GREEN
    local READY_R, READY_G, READY_B = 0.196, 0.737, 0.325
    local rowFrame = CreateFrame("Frame", nil, scrollChild)
    rowFrame:SetSize(totalW, ROW_H_A)
    rowFrame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -(i - 1) * ROW_H_A)

    local rowAlpha = (i % 2 == 0) and 0.12 or 0.06
    local rowBg = rowFrame:CreateTexture(nil, "BACKGROUND")
    rowBg:SetAllPoints()
    rowBg:SetColorTexture(0, 0, 0, rowAlpha)

    local nameFs = EllesmereUI.MakeFont(rowFrame, 13, nil, 1, 1, 1, 0.9)
    nameFs:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", SIDE_PAD, -10)
    nameFs:SetPoint("RIGHT", rowFrame, "RIGHT", -(CHK_SZ + STATUS_W + SIDE_PAD * 2 + 20), 0)
    nameFs:SetJustifyH("LEFT")
    nameFs:SetWordWrap(false)
    nameFs:SetText(EllesmereUI.L(item.display))

    local descFs = EllesmereUI.MakeFont(rowFrame, 11, nil, 1, 1, 1, 0.30)
    descFs:SetPoint("TOPLEFT", nameFs, "BOTTOMLEFT", 0, -5)
    descFs:SetPoint("RIGHT", nameFs, "RIGHT", 0, 0)
    descFs:SetJustifyH("LEFT")
    descFs:SetWordWrap(false)
    descFs:SetText(EllesmereUI.L(item.desc))

    local statusFs = EllesmereUI.MakeFont(rowFrame, 11, nil, 1, 1, 1, 0.40)
    statusFs:SetPoint("RIGHT", rowFrame, "RIGHT", -SIDE_PAD, 0)
    statusFs:SetJustifyH("RIGHT")

    -- Checkbox (centered under the Include column header)
    local chkFrame = CreateFrame("Frame", nil, rowFrame)
    chkFrame:SetSize(CHK_SZ, CHK_SZ)
    chkFrame:SetPoint("CENTER", rowFrame, "RIGHT", INCLUDE_CENTER_X, 0)

    local chkBg = chkFrame:CreateTexture(nil, "BACKGROUND")
    chkBg:SetAllPoints()
    chkBg:SetColorTexture(0.12, 0.12, 0.14, 1)
    if chkBg.SetSnapToPixelGrid then chkBg:SetSnapToPixelGrid(false); chkBg:SetTexelSnappingBias(0) end

    local chkBrd = EllesmereUI.MakeBorder(chkFrame, 0.25, 0.25, 0.28, 0.6, PP)

    local chkMark = chkFrame:CreateTexture(nil, "ARTWORK")
    chkMark:SetPoint("TOPLEFT", chkFrame, "TOPLEFT", 3, -3)
    chkMark:SetPoint("BOTTOMRIGHT", chkFrame, "BOTTOMRIGHT", -3, 3)
    chkMark:SetColorTexture(EG.r, EG.g, EG.b, 1)
    if chkMark.SetSnapToPixelGrid then chkMark:SetSnapToPixelGrid(false); chkMark:SetTexelSnappingBias(0) end

    local function ApplyRowVisual()
        local on = item.getVal()
        if not o.active then
            nameFs:SetAlpha(0.30)
            descFs:SetAlpha(0.15)
            chkMark:Hide()
            chkBg:SetAlpha(0.3)
            local c = o.inactiveColor
            statusFs:SetText(o.inactiveText)
            statusFs:SetTextColor(c[1], c[2], c[3], c[4])
        elseif on then
            nameFs:SetAlpha(0.9)
            descFs:SetAlpha(0.30)
            chkMark:Show()
            chkBg:SetAlpha(1)
            chkBrd:SetColor(EG.r, EG.g, EG.b, 0.15)
            statusFs:SetText(EllesmereUI.L("Ready"))
            statusFs:SetTextColor(READY_R, READY_G, READY_B, 1)
        else
            nameFs:SetAlpha(0.50)
            descFs:SetAlpha(0.20)
            chkMark:Hide()
            chkBg:SetAlpha(1)
            chkBrd:SetColor(0.25, 0.25, 0.28, 0.6)
            statusFs:SetText(EllesmereUI.L("Skipped"))
            statusFs:SetTextColor(1, 1, 1, 0.35)
        end
    end
    ApplyRowVisual()
    o.visuals[#o.visuals + 1] = ApplyRowVisual

    local hoverTex = rowFrame:CreateTexture(nil, "ARTWORK")
    hoverTex:SetAllPoints()
    hoverTex:SetColorTexture(1, 1, 1, 0.05)
    hoverTex:Hide()

    if o.active then
        local clickBtn = CreateFrame("Button", nil, rowFrame)
        clickBtn:SetAllPoints(rowFrame)
        clickBtn:SetFrameLevel(rowFrame:GetFrameLevel() + 2)
        clickBtn:SetScript("OnClick", function()
            item.setVal(not item.getVal())
            o.onToggle(ApplyRowVisual)
        end)
        clickBtn:SetScript("OnEnter", function()
            hoverTex:Show()
            if not item.getVal() then nameFs:SetAlpha(0.75) end
            -- Linked-modules tooltip; suppressed while layout is off, since nothing couples then.
            local members, own, display = o.linked()
            if members then
                local names = {}
                for f in pairs(members) do
                    if f ~= own then
                        names[#names + 1] = EllesmereUI.L(display[f] or f)
                    end
                end
                if #names > 0 then
                    table.sort(names)
                    EllesmereUI.ShowWidgetTooltip(rowFrame, o.linkedTip(table.concat(names, ", ")))
                end
            end
        end)
        clickBtn:SetScript("OnLeave", function()
            hoverTex:Hide()
            if not item.getVal() then nameFs:SetAlpha(0.50) end
            EllesmereUI.HideWidgetTooltip()
        end)
    else
        local blockFrame = CreateFrame("Frame", nil, rowFrame)
        blockFrame:SetAllPoints()
        blockFrame:SetFrameLevel(rowFrame:GetFrameLevel() + 5)
        blockFrame:EnableMouse(true)
        if o.blockedTip then
            blockFrame:SetScript("OnEnter", function()
                hoverTex:Show()
                EllesmereUI.ShowWidgetTooltip(rowFrame, o.blockedTip)
            end)
            blockFrame:SetScript("OnLeave", function()
                hoverTex:Hide()
                EllesmereUI.HideWidgetTooltip()
            end)
        else
            blockFrame:SetScript("OnEnter", function() end)
            blockFrame:SetScript("OnLeave", function() end)
        end
    end
end

-- Done-style button hover: label and border alpha fade 0.7 -> 1 over 0.1s.
-- Returns reset(), which snaps the fade state back to idle.
local function MakeAccentFade(btn, lbl, brd)
    local EG = EllesmereUI.ELLESMERE_GREEN
    local lerp = EllesmereUI.lerp
    local progress, target = 0, 0
    local FADE = 0.1
    local function Apply(t)
        lbl:SetTextColor(EG.r, EG.g, EG.b, lerp(0.7, 1, t))
        brd:SetColor(EG.r, EG.g, EG.b, lerp(0.7, 1, t))
    end
    local function OnUpdate(self, elapsed)
        local dir = (target == 1) and 1 or -1
        progress = progress + dir * (elapsed / FADE)
        if (dir == 1 and progress >= 1) or (dir == -1 and progress <= 0) then
            progress = target; self:SetScript("OnUpdate", nil)
        end
        Apply(progress)
    end
    btn:SetScript("OnEnter", function(self) target = 1; self:SetScript("OnUpdate", OnUpdate) end)
    btn:SetScript("OnLeave", function(self) target = 0; self:SetScript("OnUpdate", OnUpdate) end)
    return function()
        progress, target = 0, 0
        Apply(0)
    end
end

function _G._EUI_BuildProfilesPage(pageName, parent, yOffset)
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h
    local FONT = EllesmereUI.EXPRESSWAY
    local EG = EllesmereUI.ELLESMERE_GREEN
    local MEDIA = "Interface\\AddOns\\EllesmereUI\\media\\"

    -- Safety net: if the active profile does not match the current spec assignment (e.g. spec info was unavailable at login), correct it now.
    do
        local si = C_SpecializationInfo.GetSpecialization() or 0
        local sid = si and si > 0 and C_SpecializationInfo.GetSpecializationInfo(si) or nil
        if sid then
            local assigned = EllesmereUI.GetSpecProfile(sid)
            if assigned then
                local current = EllesmereUI.GetActiveProfileName()
                if assigned ~= current then
                    local _, profiles = EllesmereUI.GetProfileList()
                    if profiles and profiles[assigned] then
                        local fontWillChange = EllesmereUI.ProfileChangesFont(profiles[assigned])
                        local skinsWillChange = EllesmereUI.ProfileChangesWindowSkins(profiles[assigned])
                        local styleWillChange = EllesmereUI.ProfileChangesStyle(profiles[assigned])
                        EllesmereUI.SwitchProfile(assigned)
                        -- true = budgeted: manual apply (no spec change
                        -- in flight), watchdog-sliced module refresh.
                        EllesmereUI.RefreshAllAddons(true)
                        if fontWillChange or skinsWillChange or styleWillChange then
                            EllesmereUI:ShowConfirmPopup({
                                title       = EllesmereUI.L("Reload Required"),
                                message     = fontWillChange
                                    and EllesmereUI.L("Font changed. A UI reload is needed to apply the new font.")
                                    or skinsWillChange
                                    and EllesmereUI.L("Window skins changed for this profile. A UI reload is needed to apply them.")
                                    or EllesmereUI.L("Style changed for this profile. A UI reload is needed to apply it."),
                                confirmText = EllesmereUI.L("Reload Now"),
                                cancelText  = EllesmereUI.L("Later"),
                                reload      = true,
                            })
                        end
                    end
                end
            end
        end
    end

    if parent then parent._showRowDivider = false end

    -- Bypass scroll child: parent everything to scrollFrame directly
    local scrollFrame = EllesmereUI._scrollFrame
    if not scrollFrame then return 0 end

    if EllesmereUI._profilesRoot then
        EllesmereUI._profilesRoot:Hide()
        EllesmereUI._profilesRoot:SetParent(nil)
    end

    local root = CreateFrame("Frame", nil, scrollFrame)
    root:SetAllPoints(scrollFrame)
    root:SetFrameLevel(scrollFrame:GetFrameLevel() + 5)
    EllesmereUI._profilesRoot = root

    -- Page containers: main profiles page vs import flow
    local mainPage = CreateFrame("Frame", nil, root)
    mainPage:SetAllPoints(root)
    mainPage:SetFrameLevel(root:GetFrameLevel())

    local importPage = CreateFrame("Frame", nil, root)
    importPage:SetAllPoints(root)
    importPage:SetFrameLevel(root:GetFrameLevel())
    importPage:Hide()

    local pastePage = CreateFrame("Frame", nil, root)
    pastePage:SetAllPoints(root)
    pastePage:SetFrameLevel(root:GetFrameLevel())
    pastePage:Hide()

    -- Use mainPage for all main content
    parent = mainPage
    y = -10

    -- Button colours matching dropdown border style
    local _c = EllesmereUI.WB_COLOURS
    local PROF_BTN_COLOURS = {
        _c[1],  _c[2],  _c[3],  _c[4],   _c[5],  _c[6],  _c[7],  _c[8],
        1, 1, 1, EllesmereUI.DD_BRD_A,   1, 1, 1, EllesmereUI.DD_BRD_HA,
        _c[17], _c[18], _c[19], _c[20],  _c[21], _c[22], _c[23], _c[24],
    }

    -- Accent button colours (green-tinted)
    local ACCENT_BTN_COLOURS = {
        EG.r * 0.15, EG.g * 0.15, EG.b * 0.15, 0.85,
        EG.r * 0.22, EG.g * 0.22, EG.b * 0.22, 0.95,
        EG.r, EG.g, EG.b, 0.35,
        EG.r, EG.g, EG.b, 0.65,
        EG.r, EG.g, EG.b, 0.90,
        1, 1, 1, 1,
    }

    _, h = W:Spacer(parent, y, 10);  y = y - h

    -- Shared dropdown builder (reused for profile dd and spec dd)
    local function MakeDropdown(parentFrame, w, ddH, getLabel)
        local btn = CreateFrame("Button", nil, parentFrame)
        PP.Size(btn, w, ddH)
        btn:SetFrameLevel(parentFrame:GetFrameLevel() + 2)
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
        local brd = EllesmereUI.MakeBorder(btn, 1, 1, 1, EllesmereUI.DD_BRD_A, PP)
        local lbl = EllesmereUI.MakeFont(btn, 13, nil, 1, 1, 1)
        lbl:SetAlpha(EllesmereUI.DD_TXT_A)
        lbl:SetJustifyH("LEFT")
        lbl:SetWordWrap(false)
        lbl:SetMaxLines(1)
        lbl:SetPoint("LEFT", btn, "LEFT", 12, 0)
        local arrow = EllesmereUI.MakeDropdownArrow(btn, 12, PP)
        lbl:SetPoint("RIGHT", arrow, "LEFT", -5, 0)
        lbl:SetText(getLabel())
        local s = EllesmereUI.RD_DD_COLOURS
        btn:SetScript("OnEnter", function()
            lbl:SetTextColor(s[21], s[22], s[23], s[24])
            brd:SetColor(s[13], s[14], s[15], s[16])
            bg:SetColorTexture(s[5], s[6], s[7], s[8])
        end)
        btn:SetScript("OnLeave", function()
            lbl:SetTextColor(s[17], s[18], s[19], s[20])
            brd:SetColor(s[9], s[10], s[11], s[12])
            bg:SetColorTexture(s[1], s[2], s[3], s[4])
        end)
        btn._getLabel = getLabel
        return btn, lbl, bg, brd
    end

    local function MakeDropdownMenu(anchor, w)
        local menuFrame = CreateFrame("Frame", nil, UIParent)
        menuFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        menuFrame:SetFrameLevel(200)
        menuFrame:SetClampedToScreen(true)
        menuFrame:SetSize(w, 4)
        menuFrame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
        menuFrame:Hide()
        local bg = menuFrame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, 0.98)
        EllesmereUI.MakeBorder(menuFrame, 1, 1, 1, EllesmereUI.DD_BRD_A, PP)
        menuFrame:SetScript("OnShow", function(self)
            local s = anchor:GetEffectiveScale() / UIParent:GetEffectiveScale()
            self:SetScale(s)
            self:SetScript("OnUpdate", function(m)
                if not anchor:IsMouseOver() and not m:IsMouseOver() then
                    if IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") then m:Hide() end
                end
            end)
        end)
        menuFrame:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
        return menuFrame
    end

    -- Hoisted so the import callback can update it
    local ddLabel

    -------------------------------------------------------------------
    --  Shared helpers
    -------------------------------------------------------------------

    local ShowImportPage  -- forward declaration (defined after import page builder)

    local _kbPopup
    local function ShowProfileKeybindPopup(profileName)
        if _kbPopup then _kbPopup:Hide() end

        local POPUP_W, POPUP_H = 320, 130

        local dimmer = CreateFrame("Frame", nil, UIParent)
        dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
        dimmer:SetFrameLevel(100)
        dimmer:SetAllPoints(UIParent)
        dimmer:EnableMouse(true)
        dimmer:EnableMouseWheel(true)
        dimmer:SetScript("OnMouseWheel", function() end)

        local dimTex = dimmer:CreateTexture(nil, "BACKGROUND")
        dimTex:SetAllPoints()
        dimTex:SetColorTexture(0, 0, 0, 0.25)

        local popup = CreateFrame("Frame", nil, dimmer)
        popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)
        popup:SetSize(POPUP_W, POPUP_H)
        popup:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
        popup:EnableMouse(true)
        popup:SetClampedToScreen(true)
        _kbPopup = popup
        popup._dimmer = dimmer

        dimmer:SetScript("OnMouseDown", function()
            if not popup:IsMouseOver() then
                dimmer:Hide()
            end
        end)

        local popBg = popup:CreateTexture(nil, "BACKGROUND")
        popBg:SetAllPoints()
        popBg:SetColorTexture(0.06, 0.08, 0.10, 0.97)
        EllesmereUI.MakeBorder(popup, 1, 1, 1, 0.20, PP)

        local title = EllesmereUI.MakeFont(popup, 14, nil, 1, 1, 1)
        title:SetPoint("TOP", popup, "TOP", 0, -14)
        title:SetText(EllesmereUI.Lf("Keybind: %1$s", profileName))

        local kbBtn = EllesmereUI.BuildKeybindButton(popup, {
            w = 160, h = 30, font = 13,
            get = function() return EllesmereUI.GetProfileKeybind(profileName) end,
            set = function(v) EllesmereUI.SetProfileKeybind(profileName, v) end,
        })
        kbBtn:SetPoint("CENTER", popup, "CENTER", 0, -2)

        local hint = EllesmereUI.MakeFont(popup, 10, nil, 1, 1, 1, 0.35)
        hint:SetPoint("BOTTOM", popup, "BOTTOM", 0, 12)
        hint:SetText(EllesmereUI.L("Left-click to set  |  Right-click to unbind  |  Esc to close"))

        -- kbBtn's own OnHide cancels a capture in progress.
        popup:SetScript("OnHide", function()
            if popup._dimmer then popup._dimmer:Hide() end
            _kbPopup = nil
        end)

        popup:EnableKeyboard(true)
        popup:SetScript("OnKeyDown", function(self, kkey)
            -- kbBtn takes the keyboard only while it is capturing.
            if kkey == "ESCAPE" and not kbBtn:IsKeyboardEnabled() then
                self:SetPropagateKeyboardInput(false)
                dimmer:Hide()
            else
                self:SetPropagateKeyboardInput(true)
            end
        end)

        dimmer:Show()
    end

    local function BuildErrorFlash(btn, brd)
        local flashFrame = CreateFrame("Frame", nil, btn)
        flashFrame:Hide()
        local elapsed = 0
        local FLASH_DUR = 0.7
        local lerp = EllesmereUI.lerp
        flashFrame:SetScript("OnUpdate", function(self, dt)
            elapsed = elapsed + dt
            if elapsed >= FLASH_DUR then
                self:Hide()
                brd:SetColor(1, 1, 1, EllesmereUI.DD_BRD_A)
                return
            end
            local t = elapsed / FLASH_DUR
            brd:SetColor(lerp(0.9, 1, t), lerp(0.15, 1, t), lerp(0.15, 1, t), lerp(0.7, EllesmereUI.DD_BRD_A, t))
        end)
        return function()
            elapsed = 0
            brd:SetColor(0.9, 0.15, 0.15, 0.7)
            flashFrame:Show()
        end
    end

    -------------------------------------------------------------------
    --  IMPORT PAGE BUILDER (shared by presets + import profile)
    -------------------------------------------------------------------
    ShowImportPage = function(exportString, payload, defaultName, editModeString, editModeLayoutName, applyImportedScale)
        -- Clear any previous import page content
        for _, child in ipairs({ importPage:GetChildren() }) do
            child:Hide()
            child:SetParent(nil)
        end

        -- Optional Blizzard Edit Mode layout to apply alongside this import (preset path only; the manual paste path leaves these nil).
        importPage._editModeString     = editModeString
        importPage._editModeLayoutName = editModeLayoutName

        local scaleWarnText = BuildScaleWarning(payload, applyImportedScale)
        local includedAddons = {}
        if payload and payload.data and payload.data.addons then
            for folder in pairs(payload.data.addons) do
                includedAddons[folder] = true
            end
        end

        -- Spec->profile assignments in the string gate the "Auto Assign to Specs" toggle (and grow the footer by one stacked row); without
        -- them the footer stays a compact single row.
        local hasSpecAssign = payload and payload.data
            and type(payload.data.assignedSpecs) == "table"
            and #payload.data.assignedSpecs > 0

        -- Does the string carry a UI scale? The adopt/keep decision was already made by MaybeConfirmUIScale before this page
        -- (applyImportedScale); this flag only gates the commit marker.
        local hasUIScale = payload and payload.data
            and type(payload.data.uiScale) == "number"

        local ADDON_DB_MAP_LOCAL = EllesmereUI.VisibleProfileAddons(EllesmereUI._ADDON_DB_MAP)
        local PAD        = EllesmereUI.CONTENT_PAD
        local totalW     = importPage:GetWidth() - PAD * 2
        local HDR_H      = 72
        local COL_HDR_H  = 28
        -- The optional Auto Assign toggle stacks below the count row.
        local nFooterStack = (hasSpecAssign and 1 or 0)
        local FOOTER_H   = 50 + nFooterStack * 24

        local ADDON_DESCS = {
            EllesmereUIActionBars        = "Modern action bars built for performance and clarity.",
            EllesmereUINameplates        = "Clean, lightweight nameplates with endless customization.",
            EllesmereUIUnitFrames        = "Simple unit frames with a modern visual style.",
            EllesmereUICooldownManager   = "A CDM replacement focused on performance, customizations and alerts.",
            EllesmereUIResourceBars      = "Custom Resource Bars with thresholds, hash lines and more.",
            EllesmereUIRaidFrames        = "Incredibly light performance, modern raid frames with endless flexibility.",
            EllesmereUIAuraBuffReminders = "Simple raid buff, auras, consumables and talent reminders.",
            EllesmereUIQoL               = "Lightweight quality of life tools and enhancements.",
            EllesmereUIDragonRiding      = "Skyriding HUD with speed, vigor and second wind tracking.",
            EllesmereUIBlizzardSkin       = "Clean and beautiful visual refreshes for Blizzard UI elements.",
            EllesmereUIFriends           = "A modern friends list with built-in organization tools.",
            EllesmereUIMythicTimer       = "Mythic+ timer, targeted spell bars, and standalone cast bars.",
            EllesmereUIQuestTracker      = "A clean, updated reskin of Blizzard's Quest Tracker.",
            EllesmereUIMinimap           = "A new age minimap with clean styling and square layout options.",
            EllesmereUIDamageMeters      = "Lightweight damage meters with simple but powerful customization.",
            EllesmereUIChat              = "Modern chat enhancements with useful utilities.",
            EllesmereUIBags              = "A beautiful visual refresh of Blizzard Bags with intuitive organization.",
            EllesmereUIQuickdraw         = "Hold a key to open a menu of actions; point or scroll to choose, release to fire.",
        }

        local iy = -30

        local BACK_W, BACK_H = 80, 32
        local backBtn = CreateFrame("Button", nil, importPage)
        PP.Size(backBtn, BACK_W, BACK_H)
        PP.Point(backBtn, "TOPLEFT", importPage, "TOPLEFT", PAD, iy)
        backBtn:SetFrameLevel(importPage:GetFrameLevel() + 2)

        local backBg = backBtn:CreateTexture(nil, "BACKGROUND")
        backBg:SetAllPoints()
        backBg:SetColorTexture(0.06, 0.08, 0.10, 0.50)
        local backBrd = EllesmereUI.MakeBorder(backBtn, 1, 1, 1, 0.12, PP)

        local backIcon = backBtn:CreateTexture(nil, "ARTWORK")
        backIcon:SetSize(14, 14)
        PP.Point(backIcon, "LEFT", backBtn, "LEFT", 10, 0)
        backIcon:SetTexture(MEDIA .. "icons\\eui-arrow-left.png")
        backIcon:SetVertexColor(EG.r, EG.g, EG.b)
        backIcon:SetAlpha(0.6)
        if backIcon.SetSnapToPixelGrid then backIcon:SetSnapToPixelGrid(false); backIcon:SetTexelSnappingBias(0) end

        local backLbl = EllesmereUI.MakeFont(backBtn, 12, nil, 1, 1, 1, 0.55)
        PP.Point(backLbl, "LEFT", backIcon, "RIGHT", 6, 0)
        backLbl:SetText(EllesmereUI.L("Back"))

        backBtn:SetScript("OnEnter", function()
            backBg:SetColorTexture(0.11, 0.13, 0.15, 0.50)
            backBrd:SetColor(1, 1, 1, 0.22)
            backIcon:SetAlpha(0.85)
            backLbl:SetAlpha(0.85)
        end)
        backBtn:SetScript("OnLeave", function()
            backBg:SetColorTexture(0.06, 0.08, 0.10, 0.50)
            backBrd:SetColor(1, 1, 1, 0.12)
            backIcon:SetAlpha(0.6)
            backLbl:SetAlpha(0.55)
        end)
        backBtn:SetScript("OnClick", function()
            importPage:Hide()
            mainPage:Show()
        end)

        local titleFs = EllesmereUI.MakeFont(importPage, 16, nil, 1, 1, 1, 0.95)
        PP.Point(titleFs, "TOP", importPage, "TOP", 0, iy - BACK_H / 2 + 8)
        titleFs:SetText(EllesmereUI.Lf("Importing %1$s", (defaultName or EllesmereUI.L("Profile"))))
        titleFs:SetJustifyH("CENTER")

        iy = iy - BACK_H - 8

        if scaleWarnText then
            local warnFs = EllesmereUI.MakeFont(importPage, 13, nil, 0.9, 0.2, 0.2, 0.85)
            PP.Point(warnFs, "TOP", importPage, "TOP", 0, iy)
            PP.Point(warnFs, "LEFT", importPage, "LEFT", PAD, 0)
            PP.Point(warnFs, "RIGHT", importPage, "RIGHT", -PAD, 0)
            warnFs:SetText(scaleWarnText)
            warnFs:SetJustifyH("CENTER")
            warnFs:SetWordWrap(true)
            iy = iy - 48
        end

        local editBox
        do
            local INPUT_H = 30
            local INPUT_W = 300
            local nameLabel = EllesmereUI.MakeFont(importPage, 12, nil, 1, 1, 1, 0.45)
            PP.Point(nameLabel, "TOPLEFT", importPage, "TOPLEFT", PAD, iy)
            nameLabel:SetText(EllesmereUI.L("Profile Name"))
            nameLabel:SetJustifyH("LEFT")

            iy = iy - 22

            local inputFrame = CreateFrame("Frame", nil, importPage)
            PP.Size(inputFrame, INPUT_W, INPUT_H)
            PP.Point(inputFrame, "TOPLEFT", importPage, "TOPLEFT", PAD, iy)
            local iBg = inputFrame:CreateTexture(nil, "BACKGROUND")
            iBg:SetAllPoints()
            iBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
            local inputBrd = EllesmereUI.MakeBorder(inputFrame, 1, 1, 1, EllesmereUI.DD_BRD_A, PP)
            importPage._nameFlash = BuildErrorFlash(inputFrame, inputBrd)

            editBox = CreateFrame("EditBox", nil, inputFrame)
            editBox:SetPoint("TOPLEFT", 12, -1)
            editBox:SetPoint("BOTTOMRIGHT", -12, 1)
            editBox:SetFont(FONT, 12, EllesmereUI.GetFontOutlineFlag())
            editBox:SetTextColor(1, 1, 1, 0.9)
            editBox:SetAutoFocus(false)
            editBox:SetMaxLetters(30)
            if defaultName then editBox:SetText(defaultName) end

            local placeholder = editBox:CreateFontString(nil, "ARTWORK")
            placeholder:SetFont(FONT, 12, EllesmereUI.GetFontOutlineFlag())
            placeholder:SetTextColor(1, 1, 1, 0.25)
            placeholder:SetPoint("LEFT", editBox, "LEFT", 0, 0)
            placeholder:SetText(EllesmereUI.L("Profile name..."))

            editBox:SetScript("OnTextChanged", function(self)
                if self:GetText() == "" then placeholder:Show() else placeholder:Hide() end
                if importPage._nameError then importPage._nameError:Hide() end
            end)
            editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
            editBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

            iy = iy - INPUT_H - 14
        end

        -- Import Addons section (mirrors per-addon export layout)
        local selectedImports = {}
        local includeLayoutImport = true     -- "Include layout" toggle (default on)
        -- "Include Overrides" is all-or-nothing: the exporter's COMPLETE
        -- override system (values + groups + custom unlock modes + BM forks) either replaces yours wholesale or none of it comes. Offered
        -- only when the string carries override data; ON for full strings (or subsets exported with Overrides included), OFF otherwise.
        local stringHasOverrides = false
        do
            local d = payload and payload.data
            if d then
                stringHasOverrides = d.specOverrides ~= nil or d.condOverrides ~= nil
                    or d.specOverrideGroups ~= nil or d.condOverrideGroups ~= nil
                    or d.specUnlockOverrides ~= nil or d.condUnlockOverrides ~= nil
                    or d.specBmOverrides ~= nil or d.condBmOverrides ~= nil
                    or d.specDmOverrides ~= nil or d.condDmOverrides ~= nil
            end
        end
        local includeOverridesImport = stringHasOverrides
            and (payload.data.overridesIncluded == true
                or (payload.data.partialImport ~= true and payload.data.overridesExcluded ~= true))
            or false
        -- "Include Window Skins": the exporter's Blizz UI Enhanced account-global bundle (Window Skins + Tooltips, Menus & Popups).
        -- Default OFF and confirmation-gated -- it overwrites the recipient's settings across ALL profiles. Grayed out when string has none.
        local stringHasBlizzSkin = (payload and payload.data
            and type(payload.data.blizzSkinGlobals) == "table") or false
        local includeWindowSkinsImport = false
        -- "Global Settings": the exporter's global appearance (fonts, custom colours, dark mode, accent) and UI scale. Presence = deliberate
        -- include; this toggle is the recipient's opt-out. ON when carried, inert when the string has none.
        local stringHasGlobals = false
        do
            local d = payload and payload.data
            if d then
                stringHasGlobals = d.fonts ~= nil or d.customColors ~= nil
                    or d.darkMode ~= nil or d.euiAccent ~= nil or d.uiScale ~= nil
            end
        end
        local includeGlobalsImport = stringHasGlobals
        local autoAssignImport = false       -- "Auto Assign to Specs" toggle (default off)
        local importVisuals = {}
        local importCountFs
        local importComponents   -- canon folder -> { component member set }, set below
        local importCanImport = {}
        local CANON_DISPLAY = {}  -- canon folder -> display name (for the linked tooltip)

        local addonItems = {}
        for _, entry in ipairs(ADDON_DB_MAP_LOCAL) do
            local folder = entry.folder
            -- Payload keys are CANONICAL (suite folder names); selectedImports is keyed by canon so it matches the payload + the strip loop
            -- in both suite and standalone builds. "loaded"/"desc" stay on the LOCAL folder so only this build's installed module is checkable.
            local canon = entry.canon or folder
            local loaded = EllesmereUI.IsModuleAddonLoaded(folder)
            local inPayload = includedAddons[canon] or false
            local canImport = loaded and inPayload
            importCanImport[canon] = canImport
            CANON_DISPLAY[canon] = entry.display
            addonItems[#addonItems + 1] = {
                folder    = folder,
                canon     = canon,
                display   = entry.display,
                desc      = ADDON_DESCS[folder] or "",
                loaded    = loaded,
                inPayload = inPayload,
                canImport = canImport,
                getVal    = function() return selectedImports[canon] or false end,
                -- Hard-couple: (un)checking a module sets its whole connected component (anchor/size-match links), importable members only.
                setVal    = function(v)
                    -- Layout OFF: relationships aren't imported, so skip the hard-couple and let each linked module be picked alone.
                    local members = includeLayoutImport and importComponents and importComponents[canon]
                    if members then
                        for f in pairs(members) do
                            if importCanImport[f] then selectedImports[f] = v or nil end
                        end
                    else
                        selectedImports[canon] = v or nil
                    end
                end,
            }
            if canImport then selectedImports[canon] = true end
        end

        -- Module connectivity from the payload's layout + meta (both CANONICAL, matching selectedImports' keyspace). Drives the hard-couple
        -- above and the "linked" row affordance. stale={} -- sender already pruned dead edges.
        do
            local ul   = payload and payload.data and payload.data.unlockLayout
            local meta = payload and payload.data and payload.data.unlockLayoutMeta
            importComponents = EllesmereUI.BuildModuleComponents(
                ul, EllesmereUI.BuildImportKeyToFolder(ul, meta and meta.keyToFolder))
        end

        local function RefreshImportCount()
            if not importCountFs then return end
            local count = 0
            for _ in pairs(selectedImports) do count = count + 1 end
            importCountFs:SetText(EllesmereUI.Lf("Import will include %1$s of %2$s addons.", count, #addonItems))
        end

        local function RefreshAllImportVisuals()
            for _, fn in ipairs(importVisuals) do fn() end
            RefreshImportCount()
        end

        local SCROLL_MAX_H = 285
        local contentH = #addonItems * ROW_H_A
        local scrollH = math.min(contentH, SCROLL_MAX_H)
        local SECTION_H = HDR_H + COL_HDR_H + scrollH + 8 + FOOTER_H

        local sectionBg = CreateFrame("Frame", nil, importPage)
        sectionBg:SetFrameLevel(importPage:GetFrameLevel())
        PP.Size(sectionBg, totalW, SECTION_H)
        PP.Point(sectionBg, "TOPLEFT", importPage, "TOPLEFT", PAD, iy)
        sectionBg:EnableMouse(false)
        local sBgTex = sectionBg:CreateTexture(nil, "BACKGROUND")
        sBgTex:SetAllPoints()
        sBgTex:SetColorTexture(0.06, 0.08, 0.10, 0.50)
        EllesmereUI.MakeBorder(sectionBg, 1, 1, 1, 0.10, PP)

        local hdrFrame = CreateFrame("Frame", nil, importPage)
        PP.Size(hdrFrame, totalW, HDR_H)
        PP.Point(hdrFrame, "TOPLEFT", importPage, "TOPLEFT", PAD, iy)

        local hdrTitle = EllesmereUI.MakeFont(hdrFrame, 14, nil, 1, 1, 1, 0.9)
        PP.Point(hdrTitle, "TOPLEFT", hdrFrame, "TOPLEFT", SIDE_PAD, -20)
        hdrTitle:SetText(EllesmereUI.L("Import Addons"))
        hdrTitle:SetJustifyH("LEFT")

        local hdrDesc = EllesmereUI.MakeFont(hdrFrame, 11, nil, 1, 1, 1, 0.35)
        PP.Point(hdrDesc, "TOPLEFT", hdrTitle, "BOTTOMLEFT", 0, -9)
        PP.Point(hdrDesc, "RIGHT", hdrFrame, "RIGHT", -(160 + SIDE_PAD), 0)
        hdrDesc:SetText(EllesmereUI.L("Choose which addons to import. Any addons not included will use your active profile's settings in the new profile."))
        hdrDesc:SetJustifyH("LEFT")
        hdrDesc:SetWordWrap(true)

        local hdrDiv = hdrFrame:CreateTexture(nil, "ARTWORK")
        hdrDiv:SetColorTexture(1, 1, 1, 0.10)
        hdrDiv:SetHeight(1)
        PP.Point(hdrDiv, "BOTTOMLEFT", hdrFrame, "BOTTOMLEFT", SIDE_PAD, 0)
        PP.Point(hdrDiv, "BOTTOMRIGHT", hdrFrame, "BOTTOMRIGHT", -SIDE_PAD, 0)
        if hdrDiv.SetSnapToPixelGrid then hdrDiv:SetSnapToPixelGrid(false); hdrDiv:SetTexelSnappingBias(0) end

        do
            local LINK_GAP = 12
            local selAllBtn = CreateFrame("Button", nil, hdrFrame)
            selAllBtn:SetFrameLevel(hdrFrame:GetFrameLevel() + 2)
            local selAllLbl = selAllBtn:CreateFontString(nil, "OVERLAY")
            selAllLbl:SetFont(FONT, 12, EllesmereUI.GetFontOutlineFlag())
            selAllLbl:SetText(EllesmereUI.L("Select All"))
            selAllLbl:SetTextColor(1, 1, 1, 0.40)
            selAllLbl:SetPoint("CENTER")
            selAllBtn:SetSize(selAllLbl:GetStringWidth() + 4, 18)
            selAllBtn:SetPoint("RIGHT", hdrFrame, "RIGHT", -(STATUS_W + LINK_GAP + SIDE_PAD), 0)
            selAllBtn:SetPoint("TOP", hdrDesc, "TOP", 0, 0)

            local function IAllSelected()
                for _, item in ipairs(addonItems) do
                    if item.canImport and not item.getVal() then return false end
                end
                return true
            end
            local function RefreshISelColor()
                if IAllSelected() then
                    selAllLbl:SetTextColor(EG.r, EG.g, EG.b, 0.7)
                else
                    selAllLbl:SetTextColor(1, 1, 1, 0.40)
                end
            end

            local origRefresh = RefreshAllImportVisuals
            RefreshAllImportVisuals = function()
                origRefresh()
                RefreshISelColor()
            end

            selAllBtn:SetScript("OnEnter", function()
                if IAllSelected() then selAllLbl:SetTextColor(EG.r, EG.g, EG.b, 1)
                else selAllLbl:SetTextColor(1, 1, 1, 0.80) end
            end)
            selAllBtn:SetScript("OnLeave", function() RefreshISelColor() end)
            selAllBtn:SetScript("OnClick", function()
                for _, item in ipairs(addonItems) do
                    if item.canImport then item.setVal(true) end
                end
                RefreshAllImportVisuals()
            end)
            RefreshISelColor()

            local linkDiv = hdrFrame:CreateTexture(nil, "OVERLAY", nil, 7)
            linkDiv:SetColorTexture(1, 1, 1, 0.15)
            if linkDiv.SetSnapToPixelGrid then linkDiv:SetSnapToPixelGrid(false); linkDiv:SetTexelSnappingBias(0) end
            PP.Point(linkDiv, "LEFT", selAllBtn, "RIGHT", LINK_GAP / 2, 0)
            linkDiv:SetWidth(1)
            linkDiv:SetHeight(10)

            local deselBtn = CreateFrame("Button", nil, hdrFrame)
            deselBtn:SetFrameLevel(hdrFrame:GetFrameLevel() + 2)
            local deselLbl = deselBtn:CreateFontString(nil, "OVERLAY")
            deselLbl:SetFont(FONT, 12, EllesmereUI.GetFontOutlineFlag())
            deselLbl:SetText(EllesmereUI.L("Deselect All"))
            deselLbl:SetTextColor(1, 1, 1, 0.40)
            deselLbl:SetPoint("CENTER")
            deselBtn:SetSize(deselLbl:GetStringWidth() + 4, 18)
            PP.Point(deselBtn, "LEFT", selAllBtn, "RIGHT", LINK_GAP, 0)
            deselBtn:SetScript("OnEnter", function() deselLbl:SetTextColor(1, 1, 1, 0.80) end)
            deselBtn:SetScript("OnLeave", function() deselLbl:SetTextColor(1, 1, 1, 0.40) end)
            deselBtn:SetScript("OnClick", function()
                for _, item in ipairs(addonItems) do
                    item.setVal(false)
                end
                RefreshAllImportVisuals()
            end)
        end

        iy = iy - HDR_H

        local colHdrFrame = CreateFrame("Frame", nil, importPage)
        PP.Size(colHdrFrame, totalW, COL_HDR_H)
        PP.Point(colHdrFrame, "TOPLEFT", importPage, "TOPLEFT", PAD, iy)

        local colAddon = EllesmereUI.MakeFont(colHdrFrame, 11, nil, 1, 1, 1, 0.40)
        PP.Point(colAddon, "LEFT", colHdrFrame, "LEFT", SIDE_PAD, 0)
        colAddon:SetText(EllesmereUI.L("Addon"))
        colAddon:SetJustifyH("LEFT")

        local colStatus = EllesmereUI.MakeFont(colHdrFrame, 11, nil, 1, 1, 1, 0.40)
        PP.Point(colStatus, "RIGHT", colHdrFrame, "RIGHT", -SIDE_PAD, 0)
        colStatus:SetText(EllesmereUI.L("Status"))
        colStatus:SetJustifyH("RIGHT")

        local colInclude = EllesmereUI.MakeFont(colHdrFrame, 11, nil, 1, 1, 1, 0.40)
        PP.Point(colInclude, "CENTER", colHdrFrame, "RIGHT", INCLUDE_CENTER_X, 0)
        colInclude:SetText(EllesmereUI.L("Include"))
        colInclude:SetJustifyH("CENTER")

        iy = iy - COL_HDR_H

        -- Scrollable addon list
        local scrollClip = CreateFrame("Frame", nil, importPage)
        PP.Size(scrollClip, totalW, scrollH)
        PP.Point(scrollClip, "TOPLEFT", importPage, "TOPLEFT", PAD, iy)
        scrollClip:SetClipsChildren(true)

        local scrollFr = CreateFrame("ScrollFrame", nil, scrollClip)
        scrollFr:SetAllPoints()

        local scrollChild = CreateFrame("Frame", nil, scrollFr)
        scrollChild:SetSize(totalW, contentH)
        scrollFr:SetScrollChild(scrollChild)

        local scrollOffset = 0
        scrollClip:EnableMouseWheel(true)
        scrollClip:SetScript("OnMouseWheel", function(_, delta)
            local maxScroll = math.max(0, contentH - scrollH)
            scrollOffset = math.max(0, math.min(maxScroll, scrollOffset - delta * ROW_H_A))
            scrollFr:SetVerticalScroll(scrollOffset)
        end)

        -- Addon rows
        for i, item in ipairs(addonItems) do
            BuildAddonListRow(scrollChild, i, item, totalW, {
                active = item.canImport,
                inactiveText = item.inPayload and EllesmereUI.L("Not Loaded") or EllesmereUI.L("Not Included"),
                inactiveColor = item.inPayload and { 1, 1, 1, 0.25 } or { 0.9, 0.2, 0.2, 0.7 },
                visuals = importVisuals,
                onToggle = function(apply)
                    apply()
                    RefreshAllImportVisuals()
                end,
                linked = function()
                    return includeLayoutImport and importComponents and importComponents[item.canon], item.canon, CANON_DISPLAY
                end,
                linkedTip = function(list)
                    return EllesmereUI.Lf("Linked by Anchor/Width/Height Matching to: %1$s. These import together.", list)
                end,
            })
        end

        iy = iy - scrollH

        -- Footer
        iy = iy - 8
        local footerFrame = CreateFrame("Frame", nil, importPage)
        PP.Size(footerFrame, totalW, FOOTER_H)
        PP.Point(footerFrame, "TOPLEFT", importPage, "TOPLEFT", PAD, iy)

        local footerDiv = footerFrame:CreateTexture(nil, "ARTWORK")
        footerDiv:SetColorTexture(1, 1, 1, 0.10)
        footerDiv:SetHeight(1)
        PP.Point(footerDiv, "TOPLEFT", footerFrame, "TOPLEFT", SIDE_PAD, 0)
        PP.Point(footerDiv, "TOPRIGHT", footerFrame, "TOPRIGHT", -SIDE_PAD, 0)
        if footerDiv.SetSnapToPixelGrid then footerDiv:SetSnapToPixelGrid(false); footerDiv:SetTexelSnappingBias(0) end

        importCountFs = EllesmereUI.MakeFont(footerFrame, 12, nil, 1, 1, 1, 0.40)
        -- With Auto Assign present the footer has two rows, so the count sits on the upper one; otherwise it stays vertically centered.
        if nFooterStack > 0 then
            PP.Point(importCountFs, "TOPLEFT", footerFrame, "TOPLEFT", SIDE_PAD, -16)
        else
            PP.Point(importCountFs, "LEFT", footerFrame, "LEFT", SIDE_PAD, 0)
        end
        importCountFs:SetJustifyH("LEFT")
        RefreshImportCount()

        -- Overrides / Unlock Mode Layout / Global Settings / Window Skins live in the "Include:" dropdown beside the Import button; only
        -- Auto Assign stays inline, stacked below the count row.

        -- "Auto Assign to Specs": shown only when the string carries spec->profile assignments. Off (default) leaves the recipient's
        -- assignments alone; On points each exported spec at the new profile.
        if hasSpecAssign then
            local aaBtn = CreateFrame("Button", nil, footerFrame)
            aaBtn:SetSize(180, 24)
            PP.Point(aaBtn, "TOPLEFT", importCountFs, "BOTTOMLEFT", 0, -8)
            local box = CreateFrame("Frame", nil, aaBtn)
            box:SetSize(CHK_SZ, CHK_SZ)
            box:SetPoint("LEFT", aaBtn, "LEFT", 0, 0)
            local bg = box:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints()
            bg:SetColorTexture(0.12, 0.12, 0.14, 1)
            EllesmereUI.MakeBorder(box, 0.25, 0.25, 0.28, 0.6, PP)
            local mark = box:CreateTexture(nil, "ARTWORK")
            mark:SetPoint("TOPLEFT", box, "TOPLEFT", 3, -3)
            mark:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -3, 3)
            mark:SetColorTexture(EG.r, EG.g, EG.b, 1)
            local lbl = EllesmereUI.MakeFont(aaBtn, 12, nil, 1, 1, 1, 0.6)
            lbl:SetPoint("LEFT", box, "RIGHT", 6, 0)
            lbl:SetText(EllesmereUI.L("Auto Assign to Specs"))
            local function vis() mark:SetShown(autoAssignImport) end
            vis()
            aaBtn:SetScript("OnClick", function() autoAssignImport = not autoAssignImport; vis() end)
            aaBtn:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(aaBtn, EllesmereUI.L("Assign this profile to the same specializations it was assigned to on export. Off = your current spec assignments stay as they are."))
            end)
            aaBtn:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        end

        local IMP_BTN_W = 180
        local IMP_BTN_H = 30
        local importBtn = CreateFrame("Button", nil, footerFrame)
        PP.Size(importBtn, IMP_BTN_W, IMP_BTN_H)
        PP.Point(importBtn, "RIGHT", footerFrame, "RIGHT", -SIDE_PAD, 0)
        importBtn:SetFrameLevel(footerFrame:GetFrameLevel() + 2)

        local DB = EllesmereUI.DARK_BG
        local impBrd = EllesmereUI.MakeBorder(importBtn, EG.r, EG.g, EG.b, 0.7, PP)
        local impBg = EllesmereUI.SolidTex(importBtn, "BACKGROUND", DB.r, DB.g, DB.b, 0.92)
        impBg:SetAllPoints()
        local impLbl = EllesmereUI.MakeFont(importBtn, 12, nil, EG.r, EG.g, EG.b)
        impLbl:SetAlpha(0.7)
        impLbl:SetPoint("CENTER")
        impLbl:SetText(EllesmereUI.L("Import Selected Addons"))

        -- "Include:" checkbox dropdown -- same four rows as the export footer (Overrides / Unlock Mode Layout / Global Settings / Window
        -- & Tooltip Skins), left of the Import button. Rows the string has no data for are inert and excluded from the summary; Window
        -- Skins keeps its confirmation gate on enable.
        do
            local ddBtn, ddLabelFS = MakeDropdown(footerFrame, 190, IMP_BTN_H, function() return "" end)
            PP.Point(ddBtn, "RIGHT", importBtn, "LEFT", -12, 0)

            local incLbl = EllesmereUI.MakeFont(footerFrame, 12, nil, 1, 1, 1, 0.6)
            PP.Point(incLbl, "RIGHT", ddBtn, "LEFT", -8, 0)
            incLbl:SetText(EllesmereUI.L("Include:"))

            local rowDefs = {
                { label = "Overrides", sum = "Overrides",
                  enabled = stringHasOverrides,
                  offTip = "This profile string does not carry any override data.",
                  tip   = "Import the sharer's complete override setup: spec and conditional override values, groups, their custom Unlock Mode layouts, and Buff Manager overrides. This replaces ALL of your own overrides. Off = keep yours untouched.",
                  get   = function() return includeOverridesImport end,
                  set   = function() includeOverridesImport = not includeOverridesImport end },
                { label = "Unlock Mode Layout", sum = "Layout",
                  enabled = true,
                  tip   = "Import the anchor & size-match relationships from this profile. Off = keep your own layout; only the selected modules' own positions/settings come in.",
                  get   = function() return includeLayoutImport end,
                  set   = function() includeLayoutImport = not includeLayoutImport end },
                { label = "Global Settings", sum = "Globals",
                  enabled = stringHasGlobals,
                  offTip = "This profile string does not carry any global settings.",
                  tip   = "Apply the sharer's fonts, custom colours, dark mode, accent colour and UI scale. Off = keep your own global look and scale; only the selected modules' settings come in.",
                  get   = function() return includeGlobalsImport end,
                  set   = function() includeGlobalsImport = not includeGlobalsImport end },
                { label = "Window & Tooltip Skins", sum = "Window Skins",
                  enabled = stringHasBlizzSkin,
                  offTip = "This profile string does not carry any Window & Tooltip Skins settings.",
                  tip   = "Apply the sharer's Blizz UI Enhanced Window Skins and Tooltips, Menus & Popups settings. These are account-wide and will overwrite yours across ALL profiles. Off = keep your own.",
                  get   = function() return includeWindowSkinsImport end,
                  set   = function(refresh)
                      if includeWindowSkinsImport then
                          includeWindowSkinsImport = false
                          return
                      end
                      EllesmereUI:ShowConfirmPopup({
                          title       = EllesmereUI.L("Overwrite Window & Tooltip Settings?"),
                          message     = EllesmereUI.L("This will replace YOUR Blizz UI Enhanced settings (the Window Skins and Tooltips, Menus & Popups tabs) with the sharer's, across ALL of your profiles. Your current settings on those two tabs cannot be recovered afterward."),
                          confirmText = EllesmereUI.L("OK"),
                          cancelText  = EllesmereUI.L("Cancel"),
                          onConfirm   = function()
                              includeWindowSkinsImport = true
                              if refresh then refresh() end
                          end,
                      })
                  end },
            }

            local function Summary()
                local parts, total = {}, 0
                for _, def in ipairs(rowDefs) do
                    if def.enabled then
                        total = total + 1
                        if def.get() then parts[#parts + 1] = EllesmereUI.L(def.sum) end
                    end
                end
                if #parts == 0 then return EllesmereUI.L("Nothing Extra") end
                if #parts == total then return EllesmereUI.L("Everything") end
                return table.concat(parts, ", ")
            end
            local function RefreshSummary() ddLabelFS:SetText(Summary()) end

            local menu = MakeDropdownMenu(ddBtn, 240)
            menu:SetSize(240, #rowDefs * 26 + 8)
            local marks = {}
            local function RefreshMenu()
                for i, def in ipairs(rowDefs) do
                    marks[i]:SetShown(def.enabled and def.get())
                end
            end
            local function RefreshAll() RefreshMenu(); RefreshSummary() end
            for i, def in ipairs(rowDefs) do
                local row = CreateFrame("Button", nil, menu)
                row:SetHeight(26)
                row:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -(4 + (i - 1) * 26))
                row:SetPoint("RIGHT", menu, "RIGHT", -4, 0)
                row:SetFrameLevel(menu:GetFrameLevel() + 1)
                local hl = row:CreateTexture(nil, "ARTWORK")
                hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 1); hl:SetAlpha(0)
                local box = CreateFrame("Frame", nil, row)
                box:SetSize(CHK_SZ, CHK_SZ)
                box:SetPoint("LEFT", row, "LEFT", 6, 0)
                local bbg = box:CreateTexture(nil, "BACKGROUND"); bbg:SetAllPoints()
                bbg:SetColorTexture(0.12, 0.12, 0.14, 1)
                EllesmereUI.MakeBorder(box, 0.25, 0.25, 0.28, 0.6, PP)
                local mark = box:CreateTexture(nil, "ARTWORK")
                mark:SetPoint("TOPLEFT", box, "TOPLEFT", 3, -3)
                mark:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -3, 3)
                mark:SetColorTexture(EG.r, EG.g, EG.b, 1)
                marks[i] = mark
                local lbl = EllesmereUI.MakeFont(row, 12, nil, 1, 1, 1, 0.7)
                lbl:SetPoint("LEFT", box, "RIGHT", 8, 0)
                lbl:SetText(EllesmereUI.L(def.label))
                if def.enabled then
                    row:SetScript("OnEnter", function()
                        hl:SetAlpha(0.05)
                        EllesmereUI.ShowWidgetTooltip(row, EllesmereUI.L(def.tip))
                    end)
                    row:SetScript("OnLeave", function()
                        hl:SetAlpha(0)
                        EllesmereUI.HideWidgetTooltip()
                    end)
                    row:SetScript("OnClick", function()
                        def.set(RefreshAll)
                        RefreshAll()
                    end)
                else
                    row:SetAlpha(0.35)
                    row:SetScript("OnEnter", function()
                        EllesmereUI.ShowWidgetTooltip(row, EllesmereUI.L(def.offTip))
                    end)
                    row:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                end
            end
            -- HookScript: MakeDropdownMenu owns OnShow (scale + outside-click close); our mark refresh rides alongside it.
            menu:HookScript("OnShow", RefreshMenu)
            ddBtn:SetScript("OnClick", function()
                RefreshSummary()
                if menu:IsShown() then menu:Hide() else RefreshMenu(); menu:Show() end
            end)
            RefreshSummary()
        end

        MakeAccentFade(importBtn, impLbl, impBrd)
        importBtn:SetScript("OnClick", function()
            -- Get profile name from the edit box
            local nameBox = importPage._nameEditBox
            local name = nameBox and strtrim(nameBox:GetText()) or ""
            if name == "" then
                if importPage._nameFlash then importPage._nameFlash() end
                if importPage._nameError then importPage._nameError:Show() end
                if nameBox then nameBox:SetFocus() end
                return
            end

            -- Block duplicate profile names. EXCEPTION: an interactive API import (ImportProfileInteractive) targeting the EXACT name the
            -- calling addon requested overwrites cleanly, like the silent API -- ImportProfile replaces the stored blob wholesale (the old
            -- same-name blob is never read, so nothing mixes) and unselected modules keep current values via merge-base-on-active. A name
            -- the USER edited into a collision keeps the protection below.
            local apiS = EllesmereUI._apiImportSession
            local apiOverwrite = apiS and apiS.state ~= "done" and apiS.name == name
            local _, existingProfiles = EllesmereUI.GetProfileList()
            if existingProfiles and existingProfiles[name] and not apiOverwrite then
                EllesmereUI:ShowConfirmPopup({
                    title = EllesmereUI.L("Name Taken"),
                    message = EllesmereUI.Lf("A profile named \"%1$s\" already exists. Please choose a different name.", name),
                    confirmText = EllesmereUI.L("OK"),
                    hideCancel = true,
                    onConfirm = function() end,
                })
                return
            end

            -- Filter on a private deep copy of the already-decoded payload: the strips below mutate it and the page must stay re-importable
            -- after a failed attempt (re-decoding would re-run the codec).
            local filteredPayload = EllesmereUI._DeepCopy(payload)
            local isPartialImport = false
            if filteredPayload and filteredPayload.data and filteredPayload.data.addons then
                for folder in pairs(filteredPayload.data.addons) do
                    if not selectedImports[folder] then
                        filteredPayload.data.addons[folder] = nil
                        isPartialImport = true
                    end
                end
            end
            -- CDM spell allocation is top-level (the per-module loop misses it): kept ONLY when the CDM module is selected, and then every
            -- spec in the string imports as-is (no spec picker).
            if filteredPayload and filteredPayload.data then
                if not selectedImports["EllesmereUICooldownManager"] then
                    filteredPayload.data.cdmSpells = nil
                end
            end
            -- Spec->profile assignments: top-level, applied by ImportProfile when present. Dropped wholesale unless "Auto Assign to Specs"
            -- is on (default off leaves the recipient's assignments alone).
            if filteredPayload and filteredPayload.data and not autoAssignImport then
                filteredPayload.data.assignedSpecs = nil
            end
            -- UI scale (account-wide): applied by ImportProfile ONLY on the opt-in from MaybeConfirmUIScale. PRESENCE IS CONSENT at
            -- ImportProfile -- accepted keeps the payload's uiScale; declined or matching scales STRIP it so the user's own scale stands.
            if filteredPayload and filteredPayload.data and hasUIScale and not applyImportedScale then
                filteredPayload.data.uiScale = nil
                filteredPayload.data.applyUIScale = nil
            end
            -- Layout relationships: keep only anchor/size-match edges with BOTH endpoints in the selected modules (per-element graph filter)
            -- via the payload's keyToFolder meta. selectedImports and the meta values are both CANONICAL, so they compare directly.
            -- stale={}: the sender pruned dead edges at export and the recipient's registry is irrelevant here; the "Include layout" toggle drops the whole thing separately.
            if filteredPayload and filteredPayload.data then
                local ul = filteredPayload.data.unlockLayout
                if ul and includeLayoutImport then
                    local meta = filteredPayload.data.unlockLayoutMeta
                    -- payload meta wins; the static resolver fills gaps (and ALL keys for a meta-less string) so we never drop the layout.
                    local k2f = EllesmereUI.BuildImportKeyToFolder(ul, meta and meta.keyToFolder)
                    filteredPayload.data.unlockLayout =
                        EllesmereUI.FilterLayoutToFolders(ul, selectedImports, k2f)
                else
                    filteredPayload.data.unlockLayout = nil
                end
                -- Meta is transient -- never overlay/persist it into the profile.
                filteredPayload.data.unlockLayoutMeta = nil
            end
            -- Global appearance (fonts, customColors, darkMode, euiAccent) and scale ride the Include dropdown's "Global Settings" row (on
            -- by default when carried): unchecked strips them all so the merge keeps the recipient's look. Module deselection alone never
            -- strips them -- the store merge takes each key only when present.
            if filteredPayload and filteredPayload.data and not includeGlobalsImport then
                filteredPayload.data.fonts        = nil
                filteredPayload.data.customColors = nil
                filteredPayload.data.darkMode     = nil
                filteredPayload.data.euiAccent    = nil
                filteredPayload.data.uiScale      = nil
                filteredPayload.data.applyUIScale = nil
            end
            if isPartialImport and filteredPayload and filteredPayload.data then
                -- Overrides (values AND forks) are governed solely by the Include Overrides checkbox; module deselection never strips them
                -- here. partialImport gates the override legacy keep-mine default at the store merge.
                filteredPayload.data.partialImport = true
            end
            -- Unlock-layer FORKS are whole cross-module position layers, so "Include layout" must gate them exactly like unlockLayout above
            -- or the exporter's forks replace the recipient's group layouts (ApplyLayer rewrites live anchors and CDM/AB bar positions from
            -- them on the next apply). layoutExcluded tells the store merge to KEEP the recipient's forks (nil incoming must not read as wipe).
            if filteredPayload and filteredPayload.data and not includeLayoutImport then
                -- Baseline layout excluded; fork stores belong to the Include Overrides decision below, so they are not stripped here.
                filteredPayload.data.layoutExcluded = true
            end
            -- Include Overrides (all-or-nothing): checked -> stamp the marker so ImportProfile takes the exporter's whole override system
            -- even on subset strings; unchecked -> strip every override store and stamp the exclusion so nils read as "keep mine", not "wipe".
            if filteredPayload and filteredPayload.data then
                if includeOverridesImport then
                    filteredPayload.data.overridesIncluded = true
                    filteredPayload.data.overridesExcluded = nil
                else
                    filteredPayload.data.specOverrides       = nil
                    filteredPayload.data.specOverrideGroups  = nil
                    filteredPayload.data.specOverrideNextId  = nil
                    filteredPayload.data.condOverrides       = nil
                    filteredPayload.data.condOverrideGroups  = nil
                    filteredPayload.data.condOverrideNextId  = nil
                    filteredPayload.data.specUnlockOverrides = nil
                    filteredPayload.data.condUnlockOverrides = nil
                    filteredPayload.data.specBmOverrides     = nil
                    filteredPayload.data.condBmOverrides     = nil
                    filteredPayload.data.specDmOverrides     = nil
                    filteredPayload.data.condDmOverrides     = nil
                    filteredPayload.data.unlockOverrideAnchors = nil
                    filteredPayload.data.overridesExcluded   = true
                    filteredPayload.data.overridesIncluded   = nil
                end
            end
            -- Include Window Skins: checked -> stamp the opt-in so ImportProfile applies the Blizz UI Enhanced account-global bundle before
            -- the reload; unchecked -> strip the bundle so nothing can apply and the recipient keeps their settings.
            if filteredPayload and filteredPayload.data then
                if includeWindowSkinsImport and stringHasBlizzSkin then
                    filteredPayload.data.applyBlizzSkinGlobals = true
                else
                    filteredPayload.data.blizzSkinGlobals      = nil
                    filteredPayload.data.applyBlizzSkinGlobals = nil
                end
            end

            local function commit()
                -- The payload table goes to ImportProfile directly (no encode-to-string round trip on already-decoded data). An
                -- interactive-API session marks itself as committing so ImportProfile's stale-session cancellation (which guards
                -- CONCURRENT silent imports) never cancels the committing one.
                local apiSession = EllesmereUI._apiImportSession
                if apiSession and apiSession.state == "done" then apiSession = nil end
                if apiSession then apiSession.committing = true end
                local ok, err, status = EllesmereUI.ImportProfile(filteredPayload, name)
                if apiSession then apiSession.committing = nil end
                -- Apply the preset's Blizzard Edit Mode layout (if supplied) right before the reload so profile + layout land together.
                -- pcall-guarded so a Blizzard Edit Mode error cannot block the reload. No-op on the manual paste path (no stored string).
                if ok and importPage._editModeString then
                    pcall(EllesmereUI.ApplyPresetEditMode, importPage._editModeString, importPage._editModeLayoutName)
                end
                if ok and apiSession then
                    -- Interactive-API import: hand control back to the caller instead of reloading (the caller owns ReloadUI()). Finish
                    -- BEFORE hiding so the panel's OnHide decline hook sees a completed session and stays silent.
                    if status == "spec_locked" then
                        EllesmereUI.Print(EllesmereUI.Lf("\"%1$s\" was saved but cannot be loaded because this spec has an assigned profile.", name))
                    end
                    EllesmereUI._FinishApiImportSession(true)
                    if EllesmereUI._ProfilesResetToMain then pcall(EllesmereUI._ProfilesResetToMain) end
                    EllesmereUI:Hide()
                elseif ok and status == "spec_locked" then
                    EllesmereUI:ShowInfoPopup({
                        title   = EllesmereUI.L("Profile Imported"),
                        content = EllesmereUI.Lf("\"%1$s\" was saved but cannot be loaded because this spec has an assigned profile. Switch specs or remove the spec assignment to use it.", name),
                    })
                    EllesmereUI.RequestReload(EllesmereUI.L("Profile Imported"), EllesmereUI.ImportReloadMessage(filteredPayload))
                elseif ok then
                    EllesmereUI.RequestReload(EllesmereUI.L("Profile Imported"), EllesmereUI.ImportReloadMessage(filteredPayload))
                else
                    EllesmereUI:ShowInfoPopup({ title = EllesmereUI.L("Import Failed"), content = err or EllesmereUI.L("Unknown error") })
                end
            end

            -- CDM spell layouts (gated above) import as-is, no spec picker: they are per-profile (spellAssignments.profiles[profileName]),
            -- so only the NEW profile's store is populated (others untouched) and any spec not in the string falls back to default bars.
            commit()
        end)
        importBtn._flashError = BuildErrorFlash(importBtn, impBrd)

        -- Red error message shown directly below the button when no name is entered
        local nameErrorFs = EllesmereUI.MakeFont(footerFrame, 11, nil, 0.9, 0.2, 0.2)
        nameErrorFs:SetJustifyH("RIGHT")
        PP.Point(nameErrorFs, "TOPRIGHT", importBtn, "BOTTOMRIGHT", 0, -14)
        nameErrorFs:SetText(EllesmereUI.L("*Please enter a profile name"))
        nameErrorFs:Hide()
        importPage._nameError = nameErrorFs

        -- Store edit box reference for the import button callback
        importPage._nameEditBox = editBox

        -- Hide every other page so the import page never overlaps the one it was opened from (the main paste flow).
        mainPage:Hide()
        pastePage:Hide()
        importPage:Show()
    end

    -------------------------------------------------------------------
    --  PASTE PAGE (Import Profile step 1: paste string)
    -------------------------------------------------------------------
    local function ShowPastePage()
        for _, child in ipairs({ pastePage:GetChildren() }) do
            child:Hide()
            child:SetParent(nil)
        end

        local PAD = EllesmereUI.CONTENT_PAD
        local totalW = pastePage:GetWidth() - PAD * 2
        local py = -30

        local BACK_W, BACK_H = 80, 32
        local backBtn = CreateFrame("Button", nil, pastePage)
        PP.Size(backBtn, BACK_W, BACK_H)
        PP.Point(backBtn, "TOPLEFT", pastePage, "TOPLEFT", PAD, py)
        backBtn:SetFrameLevel(pastePage:GetFrameLevel() + 2)

        local backBg = backBtn:CreateTexture(nil, "BACKGROUND")
        backBg:SetAllPoints()
        backBg:SetColorTexture(0.06, 0.08, 0.10, 0.50)
        local backBrd = EllesmereUI.MakeBorder(backBtn, 1, 1, 1, 0.12, PP)

        local backIcon = backBtn:CreateTexture(nil, "ARTWORK")
        backIcon:SetSize(14, 14)
        PP.Point(backIcon, "LEFT", backBtn, "LEFT", 10, 0)
        backIcon:SetTexture(MEDIA .. "icons\\eui-arrow-left.png")
        backIcon:SetVertexColor(EG.r, EG.g, EG.b)
        backIcon:SetAlpha(0.6)
        if backIcon.SetSnapToPixelGrid then backIcon:SetSnapToPixelGrid(false); backIcon:SetTexelSnappingBias(0) end

        local backLbl = EllesmereUI.MakeFont(backBtn, 12, nil, 1, 1, 1, 0.55)
        PP.Point(backLbl, "LEFT", backIcon, "RIGHT", 6, 0)
        backLbl:SetText(EllesmereUI.L("Back"))

        backBtn:SetScript("OnEnter", function()
            backBg:SetColorTexture(0.11, 0.13, 0.15, 0.50)
            backBrd:SetColor(1, 1, 1, 0.22)
            backIcon:SetAlpha(0.85)
            backLbl:SetAlpha(0.85)
        end)
        backBtn:SetScript("OnLeave", function()
            backBg:SetColorTexture(0.06, 0.08, 0.10, 0.50)
            backBrd:SetColor(1, 1, 1, 0.12)
            backIcon:SetAlpha(0.6)
            backLbl:SetAlpha(0.55)
        end)
        backBtn:SetScript("OnClick", function()
            pastePage:Hide()
            mainPage:Show()
        end)

        local titleFs = EllesmereUI.MakeFont(pastePage, 16, nil, 1, 1, 1, 0.95)
        PP.Point(titleFs, "TOP", pastePage, "TOP", 0, py - BACK_H / 2 + 8)
        titleFs:SetText(EllesmereUI.L("Import Profile"))
        titleFs:SetJustifyH("CENTER")

        py = py - BACK_H - 20

        -- Big paste panel
        local PANEL_H = 200
        local panelFrame = CreateFrame("Frame", nil, pastePage)
        PP.Size(panelFrame, totalW, PANEL_H)
        PP.Point(panelFrame, "TOPLEFT", pastePage, "TOPLEFT", PAD, py)
        local panelBg = panelFrame:CreateTexture(nil, "BACKGROUND")
        panelBg:SetAllPoints()
        panelBg:SetColorTexture(0.06, 0.08, 0.10, 0.50)
        EllesmereUI.MakeBorder(panelFrame, 1, 1, 1, 0.10, PP)

        local pasteSF = CreateFrame("ScrollFrame", nil, panelFrame)
        pasteSF:SetPoint("TOPLEFT", 16, -12)
        pasteSF:SetPoint("BOTTOMRIGHT", -16, 12)

        local pasteBox = CreateFrame("EditBox", nil, pasteSF)
        pasteBox:SetWidth(totalW - 32)
        pasteBox:SetFont(FONT, 11, EllesmereUI.GetFontOutlineFlag())
        pasteBox:SetTextColor(1, 1, 1, 0.8)
        pasteBox:SetAutoFocus(false)
        pasteBox:SetMultiLine(true)
        pasteSF:SetScrollChild(pasteBox)

        -- Click anywhere on the panel to refocus the edit box
        panelFrame:EnableMouse(true)
        panelFrame:SetScript("OnMouseDown", function() pasteBox:SetFocus() end)

        local pastePlaceholder = pasteSF:CreateFontString(nil, "ARTWORK")
        pastePlaceholder:SetFont(FONT, 12, EllesmereUI.GetFontOutlineFlag())
        pastePlaceholder:SetTextColor(1, 1, 1, 0.20)
        pastePlaceholder:SetPoint("TOPLEFT", pasteSF, "TOPLEFT", 0, 0)
        pastePlaceholder:SetText(EllesmereUI.L("Paste your profile string here..."))

        pasteBox:SetScript("OnTextChanged", function(self)
            if self:GetText() == "" then pastePlaceholder:Show() else pastePlaceholder:Hide() end
        end)
        pasteBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        pasteBox:SetScript("OnCursorChanged", function(self, _, cursorY, _, cursorH)
            local vs = pasteSF:GetVerticalScroll()
            local h = pasteSF:GetHeight()
            local bottom = -(cursorY) + cursorH
            if bottom > vs + h then
                pasteSF:SetVerticalScroll(bottom - h)
            elseif -(cursorY) < vs then
                pasteSF:SetVerticalScroll(-(cursorY))
            end
        end)

        -- Large pastes go into a buffer (attached AFTER the handlers above so their scripts survive): the box only ever holds a short
        -- summary line, keeping paste instant with no letter-cap truncation.
        local pasteAbsorber = EllesmereUI.AttachImportPasteAbsorber(pasteBox, function()
            EllesmereUI:ShowInfoPopup({
                title   = EllesmereUI.L("Paste Interrupted"),
                content = EllesmereUI.L("The pasted string could not be read completely. Please paste it again."),
            })
        end)

        py = py - PANEL_H - 16

        -- Continue button (Done-style)
        local CONT_W, CONT_H = 160, 34
        local contBtn = CreateFrame("Button", nil, pastePage)
        PP.Size(contBtn, CONT_W, CONT_H)
        PP.Point(contBtn, "TOPRIGHT", pastePage, "TOPRIGHT", -PAD, py)
        contBtn:SetFrameLevel(pastePage:GetFrameLevel() + 2)

        local cDB = EllesmereUI.DARK_BG
        local contBrd = EllesmereUI.MakeBorder(contBtn, EG.r, EG.g, EG.b, 0.7, PP)
        local contBg = EllesmereUI.SolidTex(contBtn, "BACKGROUND", cDB.r, cDB.g, cDB.b, 0.92)
        contBg:SetAllPoints()
        local contLbl = EllesmereUI.MakeFont(contBtn, 13, nil, EG.r, EG.g, EG.b)
        contLbl:SetAlpha(0.7)
        contLbl:SetPoint("CENTER")
        contLbl:SetText(EllesmereUI.L("Continue"))

        local contReset = MakeAccentFade(contBtn, contLbl, contBrd)
        local decodeRun
        contBtn:SetScript("OnClick", function()
            if decodeRun then return end
            local importStr = pasteAbsorber.GetText()
            if importStr == "" then return end
            -- Decode across frames: lock the button and show progress so the client stays responsive on very large strings.
            contBtn:Disable()
            contBtn:SetScript("OnUpdate", nil)
            contReset()
            contLbl:SetText(EllesmereUI.L("Processing") .. "...")
            local function Restore()
                decodeRun = nil
                contBtn:Enable()
                contLbl:SetText(EllesmereUI.L("Continue"))
                contReset()
            end
            decodeRun = EllesmereUI.DecodeImportStringAsync(importStr,
                function(payload, err)
                    Restore()
                    -- The user may have navigated away mid-decode; a stale run's result is simply dropped.
                    if not pastePage:IsVisible() then return end
                    if not payload then
                        EllesmereUI:ShowInfoPopup({ title = EllesmereUI.L("Import Failed"), content = err or EllesmereUI.L("Invalid import string.") })
                        return
                    end
                    -- FULL ACCOUNT string: its own flow, routed BEFORE the normal import machinery sees the payload (no module selection,
                    -- include toggles, or store merging). Typed confirmation: it overwrites account-wide settings.
                    if EllesmereUI.IsFullAccountPayload(payload) then
                        pastePage:Hide()
                        EllesmereUI:ShowConfirmPopup({
                            title = EllesmereUI.L("Import Full Account Data"),
                            message = EllesmereUI.L("This string is a FULL ACCOUNT export. It replaces your account-wide settings with the sender's, including Quality of Life, HoverCast bindings, Cooldown Manager spell setups, unlock anchors, UI scale, and profile keybinds -- not just a profile. Your other profiles are kept, but a profile with the same name is replaced.")
                                .. ((EllesmereUI.PayloadFromOtherClient(payload) and type(payload.data) == "table"
                                    and payload.data.spellAssignments ~= nil)
                                    and ("\n\n" .. EllesmereUI.L("Its Cooldown Manager spells come from the other game client and will not be imported.")) or ""),
                            disclaimer = EllesmereUI.L("This cannot be undone. Export your own profile as a backup first."),
                            typeToConfirm = "Confirm",
                            confirmText = EllesmereUI.L("Import & Reload"),
                            cancelText = EllesmereUI.L("Cancel"),
                            onConfirm = function()
                                EllesmereUI.ImportFullAccountData(payload)
                            end,
                        })
                        return
                    end
                    pastePage:Hide()
                    MaybeConfirmUIScale(payload, function(applyScale)
                        ShowImportPage(importStr, payload, nil, nil, nil, applyScale)
                    end)
                end,
                function(frac)
                    contLbl:SetFormattedText("%s %d%%", EllesmereUI.L("Processing"), frac * 100)
                end)
        end)

        mainPage:Hide()
        pastePage:Show()
        pasteBox:SetFocus()
    end


    -------------------------------------------------------------------
    --  TOP SECTION: Import | Popular Presets | Uninstall EUI (3 action cards)
    --  Exporting lives solely in the per-addon "Export Profile" section below -- all modules checked is the full export.
    -------------------------------------------------------------------
    _, h = W:Spacer(parent, y, 10);  y = y - h

    do
        local CARD_H     = 66
        local CARD_GAP   = 14
        local CARD_ICON  = 26
        local totalW     = parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2
        local CARD_W     = math.floor((totalW - CARD_GAP * 2) / 3)

        local rowFrame = CreateFrame("Frame", nil, parent)
        PP.Size(rowFrame, totalW, CARD_H)
        PP.Point(rowFrame, "TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD, y)

        -- Builds one action card: icon + title + description. accent (r, g, b) tints the
        -- top edge and icon; the theme accent when nil.
        local function MakeActionCard(parentRow, xOff, iconPath, cardTitle, cardDesc, onClick, accent)
            local ac = accent or EG
            local card = CreateFrame("Button", nil, parentRow)
            PP.Size(card, CARD_W, CARD_H)
            PP.Point(card, "TOPLEFT", parentRow, "TOPLEFT", xOff, 0)
            card:SetFrameLevel(parentRow:GetFrameLevel() + 2)

            local bg = card:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.06, 0.08, 0.10, 0.50)

            local brd = EllesmereUI.MakeBorder(card, 1, 1, 1, 0.12, PP)

            -- Accent top edge
            local accentLine = card:CreateTexture(nil, "ARTWORK", nil, 7)
            accentLine:SetColorTexture(ac.r, ac.g, ac.b, 0.6)
            PP.Point(accentLine, "TOPLEFT", card, "TOPLEFT", 1, -1)
            PP.Point(accentLine, "TOPRIGHT", card, "TOPRIGHT", -1, -1)
            accentLine:SetHeight(2)
            if accentLine.SetSnapToPixelGrid then accentLine:SetSnapToPixelGrid(false); accentLine:SetTexelSnappingBias(0) end

            local icon = card:CreateTexture(nil, "ARTWORK")
            icon:SetSize(CARD_ICON, CARD_ICON)
            PP.Point(icon, "LEFT", card, "LEFT", 24, 0)
            icon:SetTexture(iconPath)
            icon:SetVertexColor(ac.r, ac.g, ac.b)
            icon:SetAlpha(0.6)
            if icon.SetSnapToPixelGrid then icon:SetSnapToPixelGrid(false); icon:SetTexelSnappingBias(0) end

            local titleFs = EllesmereUI.MakeFont(card, 13, nil, 1, 1, 1, 0.9)
            PP.Point(titleFs, "TOPLEFT", icon, "TOPRIGHT", 20, 2)
            PP.Point(titleFs, "RIGHT", card, "RIGHT", -14, 0)
            titleFs:SetJustifyH("LEFT")
            titleFs:SetWordWrap(false)
            titleFs:SetText(EllesmereUI.L(cardTitle))

            local descFs = EllesmereUI.MakeFont(card, 11, nil, 1, 1, 1, 0.35)
            PP.Point(descFs, "TOPLEFT", titleFs, "BOTTOMLEFT", 0, -4)
            PP.Point(descFs, "RIGHT", card, "RIGHT", -14, 0)
            descFs:SetJustifyH("LEFT")
            -- Two lines at most: a third of the row is narrow for longer languages.
            descFs:SetWordWrap(true)
            descFs:SetMaxLines(2)
            descFs:SetText(EllesmereUI.L(cardDesc))

            card:SetScript("OnEnter", function()
                bg:SetColorTexture(0.11, 0.13, 0.15, 0.50)
                brd:SetColor(1, 1, 1, 0.22)
                titleFs:SetAlpha(1)
                icon:SetAlpha(0.85)
            end)
            card:SetScript("OnLeave", function()
                bg:SetColorTexture(0.06, 0.08, 0.10, 0.50)
                brd:SetColor(1, 1, 1, 0.12)
                titleFs:SetAlpha(0.9)
                icon:SetAlpha(0.6)
            end)
            if onClick then
                card:SetScript("OnClick", onClick)
            end

            return card
        end

        -- Import Profile
        local cardX = 0
        MakeActionCard(rowFrame, cardX, MEDIA .. "icons\\import.png",
            EllesmereUI.L("Import Profile"), EllesmereUI.L("Import a profile from string."), function()
                ShowPastePage()
            end)

        -- Popular Presets: the in-game browser is retired; presets live on
        -- the EllesmereUI website. The card opens the announcement-style
        -- popup with the copyable link (same one the Presets tab shows).
        cardX = cardX + CARD_W + CARD_GAP
        MakeActionCard(rowFrame, cardX, MEDIA .. "icons\\dark-overlay.png",
            EllesmereUI.L("Popular Presets"), EllesmereUI.L("Browse community presets."), function()
                if EllesmereUI.VideoGuides then EllesmereUI.VideoGuides.Show("presets_website") end
            end)

        -- Uninstall EUI is refused in combat (it reloads) and while Edit Mode is open (it
        -- saves its own copy of the layouts on exit, over the ones put back). True when
        -- it was refused.
        local function UninstallRefused()
            local msg
            if InCombatLockdown() then
                msg = EllesmereUI.L("Uninstalling reloads the UI and cannot run in combat. Leave combat and try again.")
            elseif EllesmereUI.EditModeOpen() then
                msg = EllesmereUI.L("Close Edit Mode first, then try again.")
            end
            if not msg then return false end
            EllesmereUI:ShowConfirmPopup({
                title       = EllesmereUI.L("Uninstall EUI"),
                message     = msg,
                confirmText = EllesmereUI.L("OK"),
                hideCancel  = true,
            })
            return true
        end
        -- Uninstall EUI: puts back the game settings EllesmereUI changed, turns it off for
        -- every character and reloads (EllesmereUI_Uninstall.lua). Profiles are kept. The
        -- reload is a RequestReload after the typed confirm, not reload = true: the typed
        -- confirm cannot gate WoW Forever's /reload click.
        cardX = cardX + CARD_W + CARD_GAP
        MakeActionCard(rowFrame, cardX, MEDIA .. "icons\\power.png",
            EllesmereUI.L("Uninstall EUI"), EllesmereUI.L("Revert EUI's changes and disable."), function()
                if UninstallRefused() then return end
                local message = EllesmereUI.L("Puts back the game settings EUI changed, such as nameplate, action bar, chat and tooltip options, and turns EUI off for every character, then reloads the UI.") .. "\n\n"
                    .. EllesmereUI.L("Your profiles are kept, so you can turn EUI back on later in the AddOns list.")
                if EllesmereUIDB and EllesmereUIDB.gfxBackup then
                    message = message .. "\n\n" .. EllesmereUI.L("Graphics changed by Optimize My FPS and Graphics stay as they are. To undo them, click Restore My Settings on Global Settings > General first.")
                end
                EllesmereUI:ShowConfirmPopup({
                    title         = EllesmereUI.L("Uninstall EUI"),
                    message       = message,
                    disclaimer    = (not EllesmereUI.UninstallKnowsOriginals())
                        and EllesmereUI.L("EUI was installed before it kept a record of your original settings, so the settings it still manages go back to the game's defaults.")
                        or nil,
                    typeToConfirm = "Confirm",
                    confirmText   = EllesmereUI.L("Uninstall & Reload"),
                    cancelText    = EllesmereUI.L("Cancel"),
                    onConfirm     = function()
                        if UninstallRefused() then return end
                        EllesmereUI.RequestReload(EllesmereUI.L("Uninstall EUI"),
                            EllesmereUI.L("Reload to finish uninstalling EUI."), EllesmereUI.Uninstall)
                    end,
                })
            end, { r = 0.9, g = 0.3, b = 0.3 })

        y = y - CARD_H
    end

    -------------------------------------------------------------------
    --  MIDDLE SECTION: Active Profile | Assign to Spec | Create New
    -------------------------------------------------------------------
    _, h = W:Spacer(parent, y, 14);  y = y - h

    do
        local LABEL_H = 16
        local CTRL_H  = 30
        local PAD_X   = 40
        local PAD_Y   = 20
        local GAP     = 40
        local ROW_H   = PAD_Y + LABEL_H + 4 + CTRL_H + PAD_Y

        local totalW = parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2
        local innerW = totalW - PAD_X * 2
        local DD_W   = math.floor(innerW * 0.38)
        local BTN_W  = math.floor((innerW - DD_W - GAP * 2) / 2)

        local rowFrame = CreateFrame("Frame", nil, parent)
        PP.Size(rowFrame, totalW, ROW_H)
        PP.Point(rowFrame, "TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD, y)

        -- Background panel
        local rowBg = rowFrame:CreateTexture(nil, "BACKGROUND")
        rowBg:SetAllPoints()
        rowBg:SetColorTexture(0.06, 0.08, 0.10, 0.50)
        local rowBrd = EllesmereUI.MakeBorder(rowFrame, 1, 1, 1, 0.10, PP)

        -- "Active Profile" label
        local profLabel = EllesmereUI.MakeFont(rowFrame, 12, nil, EG.r, EG.g, EG.b, 0.7)
        PP.Point(profLabel, "TOPLEFT", rowFrame, "TOPLEFT", PAD_X, -PAD_Y)
        profLabel:SetText(EllesmereUI.L("Active Profile"))
        profLabel:SetJustifyH("LEFT")

        -- Active Profile dropdown
        local ddBtn, ddLabelFS, ddBg, ddBrd = MakeDropdown(rowFrame, DD_W, CTRL_H, function()
            return EllesmereUI.GetActiveProfileName()
        end)
        EllesmereUI._profileDDBtn = ddBtn
        ddLabel = ddLabelFS
        PP.Point(ddBtn, "TOPLEFT", profLabel, "BOTTOMLEFT", 0, -6)

        -- Profile dropdown menu with inline rename/delete/keybind
        local aS = EllesmereUI.RD_DD_COLOURS
        local menu = MakeDropdownMenu(ddBtn, DD_W)
        local X_SZ = 14
        local menuItems = {}

        local function RebuildProfileMenu()
            for _, itm in ipairs(menuItems) do itm:Hide() end
            local order, profiles = EllesmereUI.GetProfileList()
            local mH = 4
            local idx = 0
            local activeName = EllesmereUI.GetActiveProfileName()
            local specAssigned
            do
                local si = C_SpecializationInfo.GetSpecialization() or 0
                local sid = si and si > 0 and C_SpecializationInfo.GetSpecializationInfo(si) or nil
                if sid then specAssigned = EllesmereUI.GetSpecProfile(sid) end
            end
            for _, name in ipairs(order) do
                if profiles[name] then
                    idx = idx + 1
                    local itm = menuItems[idx]
                    if not itm then
                        itm = CreateFrame("Button", nil, menu)
                        itm:SetHeight(26)
                        itm:SetFrameLevel(menu:GetFrameLevel() + 1)

                        local lbl = itm:CreateFontString(nil, "OVERLAY")
                        lbl:SetFont(FONT, 13, EllesmereUI.GetFontOutlineFlag())
                        lbl:SetPoint("LEFT",  itm, "LEFT",  10, 0)
                        lbl:SetPoint("RIGHT", itm, "RIGHT", -(X_SZ * 3 + 30), 0)
                        lbl:SetJustifyH("LEFT")
                        lbl:SetTextColor(1, 1, 1, EllesmereUI.TEXT_DIM_A)
                        itm._lbl = lbl

                        local hl = itm:CreateTexture(nil, "ARTWORK")
                        hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 1); hl:SetAlpha(0)
                        itm._hl = hl

                        local xBtn = CreateFrame("Button", nil, itm)
                        xBtn:SetSize(X_SZ, X_SZ)
                        xBtn:SetPoint("RIGHT", itm, "RIGHT", -8, 0)
                        xBtn:SetFrameLevel(itm:GetFrameLevel() + 2)
                        local xIcon = xBtn:CreateTexture(nil, "OVERLAY")
                        xIcon:SetAllPoints()
                        if xIcon.SetSnapToPixelGrid then xIcon:SetSnapToPixelGrid(false); xIcon:SetTexelSnappingBias(0) end
                        xIcon:SetTexture(MEDIA .. "icons\\eui-close.png")
                        xBtn:SetAlpha(0.4)
                        itm._xBtn = xBtn

                        local editBtn = CreateFrame("Button", nil, itm)
                        editBtn:SetSize(X_SZ, X_SZ)
                        editBtn:SetPoint("RIGHT", xBtn, "LEFT", -4, 0)
                        editBtn:SetFrameLevel(itm:GetFrameLevel() + 2)
                        local editIcon = editBtn:CreateTexture(nil, "OVERLAY")
                        editIcon:SetAllPoints()
                        if editIcon.SetSnapToPixelGrid then editIcon:SetSnapToPixelGrid(false); editIcon:SetTexelSnappingBias(0) end
                        editIcon:SetTexture(MEDIA .. "icons\\eui-edit.png")
                        editBtn:SetAlpha(0.4)
                        itm._editBtn = editBtn

                        local kbBtnI = CreateFrame("Button", nil, itm)
                        kbBtnI:SetSize(X_SZ, X_SZ)
                        kbBtnI:SetPoint("RIGHT", editBtn, "LEFT", -4, 0)
                        kbBtnI:SetFrameLevel(itm:GetFrameLevel() + 2)
                        local kbIconI = kbBtnI:CreateTexture(nil, "OVERLAY")
                        kbIconI:SetAllPoints()
                        if kbIconI.SetSnapToPixelGrid then kbIconI:SetSnapToPixelGrid(false); kbIconI:SetTexelSnappingBias(0) end
                        kbIconI:SetTexture(MEDIA .. "icons\\eui-keybind-2.png")
                        kbBtnI:SetAlpha(0.4)
                        itm._kbBtn = kbBtnI

                        local function IsOverInlineBtn()
                            return xBtn:IsMouseOver() or editBtn:IsMouseOver() or kbBtnI:IsMouseOver()
                        end

                        local function SetAllInlineAlpha(a)
                            xBtn:SetAlpha(a); editBtn:SetAlpha(a); kbBtnI:SetAlpha(a)
                        end

                        itm:SetScript("OnEnter", function()
                            lbl:SetTextColor(1, 1, 1, 1)
                            hl:SetAlpha(EllesmereUI.DD_ITEM_HL_A)
                            SetAllInlineAlpha(0.8)
                        end)
                        itm:SetScript("OnLeave", function()
                            if IsOverInlineBtn() then return end
                            lbl:SetTextColor(1, 1, 1, EllesmereUI.TEXT_DIM_A)
                            hl:SetAlpha(itm._isSel and EllesmereUI.DD_ITEM_SEL_A or 0)
                            SetAllInlineAlpha(0.4)
                        end)

                        local function InlineBtnEnter(self)
                            lbl:SetTextColor(1, 1, 1, 1)
                            hl:SetAlpha(EllesmereUI.DD_ITEM_HL_A)
                            SetAllInlineAlpha(0.8)
                            self:SetAlpha(1)
                        end
                        local function InlineBtnLeave(hoveredSelf)
                            if itm:IsMouseOver() or IsOverInlineBtn() then
                                hoveredSelf:SetAlpha(0.8)
                                return
                            end
                            lbl:SetTextColor(1, 1, 1, EllesmereUI.TEXT_DIM_A)
                            hl:SetAlpha(itm._isSel and EllesmereUI.DD_ITEM_SEL_A or 0)
                            SetAllInlineAlpha(0.4)
                        end

                        xBtn:SetScript("OnEnter", function(self)
                            InlineBtnEnter(self)
                            EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.L("Delete"))
                        end)
                        xBtn:SetScript("OnLeave", function(self)
                            InlineBtnLeave(self)
                            EllesmereUI.HideWidgetTooltip()
                        end)
                        editBtn:SetScript("OnEnter", function(self)
                            InlineBtnEnter(self)
                            EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.L("Rename"))
                        end)
                        editBtn:SetScript("OnLeave", function(self)
                            InlineBtnLeave(self)
                            EllesmereUI.HideWidgetTooltip()
                        end)
                        kbBtnI:SetScript("OnEnter", function(self)
                            InlineBtnEnter(self)
                            EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.L("Keybind"))
                        end)
                        kbBtnI:SetScript("OnLeave", function(self)
                            InlineBtnLeave(self)
                            EllesmereUI.HideWidgetTooltip()
                        end)
                        menuItems[idx] = itm
                    end

                    itm:SetPoint("TOPLEFT",  menu, "TOPLEFT",  1, -mH)
                    itm:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -1, -mH)
                    itm._lbl:SetText(name)
                    itm._isSel = (name == activeName)
                    itm._hl:SetAlpha(itm._isSel and 0.04 or 0)

                    local capName = name
                    local specLocked = specAssigned and specAssigned ~= capName

                    if specLocked then
                        itm._lbl:SetTextColor(1, 1, 1, 0.25)
                        itm._xBtn:Hide()
                        itm._editBtn:Hide()
                        itm._kbBtn:Hide()
                        itm:SetScript("OnClick", nil)
                        itm:SetScript("OnEnter", function()
                            EllesmereUI.ShowWidgetTooltip(itm, EllesmereUI.L("Your current spec has an assigned profile so you cannot switch to another. Please unassign to switch."))
                        end)
                        itm:SetScript("OnLeave", function()
                            EllesmereUI.HideWidgetTooltip()
                        end)
                    else
                        local iLbl, iHl, iXBtn, iEditBtn, iKbBtnL = itm._lbl, itm._hl, itm._xBtn, itm._editBtn, itm._kbBtn
                        iLbl:SetTextColor(1, 1, 1, EllesmereUI.TEXT_DIM_A)
                        iEditBtn:Show()
                        iKbBtnL:Show()
                        if capName == activeName then
                            iXBtn:Hide()
                            iEditBtn:ClearAllPoints()
                            iEditBtn:SetPoint("RIGHT", itm, "RIGHT", -8, 0)
                        else
                            iXBtn:Show()
                            iEditBtn:ClearAllPoints()
                            iEditBtn:SetPoint("RIGHT", iXBtn, "LEFT", -4, 0)
                        end
                        local function IsOverInline()
                            return iXBtn:IsMouseOver() or iEditBtn:IsMouseOver() or iKbBtnL:IsMouseOver()
                        end
                        local function SetAllAlpha(a)
                            iXBtn:SetAlpha(a); iEditBtn:SetAlpha(a); iKbBtnL:SetAlpha(a)
                        end
                        itm:SetScript("OnEnter", function()
                            iLbl:SetTextColor(1, 1, 1, 1)
                            iHl:SetAlpha(EllesmereUI.DD_ITEM_HL_A)
                            SetAllAlpha(0.8)
                        end)
                        itm:SetScript("OnLeave", function()
                            if IsOverInline() then return end
                            iLbl:SetTextColor(1, 1, 1, EllesmereUI.TEXT_DIM_A)
                            iHl:SetAlpha(itm._isSel and EllesmereUI.DD_ITEM_SEL_A or 0)
                            SetAllAlpha(0.4)
                        end)
                        itm:SetScript("OnClick", function()
                            if capName == activeName then return end
                            menu:Hide()
                            local _, profs = EllesmereUI.GetProfileList()
                            local fontWillChange = EllesmereUI.ProfileChangesFont(profs and profs[capName])
                            local skinsWillChange = EllesmereUI.ProfileChangesWindowSkins(profs and profs[capName])
                            local styleWillChange = EllesmereUI.ProfileChangesStyle(profs and profs[capName])
                            EllesmereUI.SwitchProfile(capName)
                            ddLabel:SetText(EllesmereUI.GetActiveProfileName())
                            -- true = budgeted: manual swap site,
                            -- watchdog-sliced module refresh.
                            EllesmereUI.RefreshAllAddons(true)
                            if fontWillChange or skinsWillChange or styleWillChange then
                                EllesmereUI:ShowConfirmPopup({
                                    title       = EllesmereUI.L("Reload Required"),
                                    message     = fontWillChange
                                        and EllesmereUI.L("Font changed. A UI reload is needed to apply the new font.")
                                        or skinsWillChange
                                        and EllesmereUI.L("Window skins changed for this profile. A UI reload is needed to apply them.")
                                        or EllesmereUI.L("Style changed for this profile. A UI reload is needed to apply it."),
                                    confirmText = EllesmereUI.L("Reload Now"),
                                    cancelText  = EllesmereUI.L("Later"),
                                    reload      = true,
                                })
                            else
                                -- Invalidate cached pages so per-profile lists (e.g. the CDM bar dropdown) rebuild: a live swap only
                                -- re-points db.profile, so cached pages would show the old profile until reload.
                                EllesmereUI:InvalidatePageCache()
                                EllesmereUI:RefreshPage(true)
                            end
                        end)
                        iXBtn:SetScript("OnClick", function()
                            if capName == activeName then return end
                            menu:Hide()
                            EllesmereUI:ShowConfirmPopup({
                                title       = EllesmereUI.L("Delete Profile"),
                                message     = EllesmereUI.Lf("Delete \"%1$s\"?", capName),
                                confirmText = EllesmereUI.L("Delete"),
                                cancelText  = EllesmereUI.L("Cancel"),
                                onConfirm   = function()
                                    EllesmereUI.DeleteProfile(capName)
                                    ddLabel:SetText(EllesmereUI.GetActiveProfileName())
                                    EllesmereUI:InvalidatePageCache()
                                    EllesmereUI:RefreshPage(true)
                                end,
                            })
                        end)
                        iEditBtn:SetScript("OnClick", function()
                            menu:Hide()
                            EllesmereUI:ShowInputPopup({
                                title       = EllesmereUI.L("Rename Profile"),
                                message     = EllesmereUI.Lf("Enter a new name for \"%1$s\":", capName),
                                placeholder = capName,
                                confirmText = EllesmereUI.L("Rename"),
                                cancelText  = EllesmereUI.L("Cancel"),
                                onConfirm   = function(newName)
                                    newName = newName and strtrim(newName) or ""
                                    if newName == "" or newName == capName then return end
                                    if newName == "Default" then
                                        print(EllesmereUI.L("|cffff6060[EllesmereUI]|r Cannot rename to \"Default\"."))
                                        return
                                    end
                                    local _, profs = EllesmereUI.GetProfileList()
                                    if profs and profs[newName] then
                                        print(EllesmereUI.Lf("|cffff6060[EllesmereUI]|r A profile named \"%1$s\" already exists.", newName))
                                        return
                                    end
                                    EllesmereUI.RenameProfile(capName, newName)
                                    ddLabel:SetText(EllesmereUI.GetActiveProfileName())
                                    EllesmereUI:InvalidatePageCache()
                                    EllesmereUI:RefreshPage(true)
                                end,
                            })
                        end)
                        iKbBtnL:SetScript("OnClick", function()
                            menu:Hide()
                            ShowProfileKeybindPopup(capName)
                        end)
                    end

                    itm:Show()
                    mH = mH + 26
                end
            end
            menu:SetHeight(mH + 4)
        end

        local function ActiveApplyNormal()
            ddLabelFS:SetTextColor(aS[17], aS[18], aS[19], aS[20])
            ddBrd:SetColor(aS[9], aS[10], aS[11], aS[12])
            ddBg:SetColorTexture(aS[1], aS[2], aS[3], aS[4])
        end
        local function ActiveApplyHover()
            ddLabelFS:SetTextColor(aS[21], aS[22], aS[23], aS[24])
            ddBrd:SetColor(aS[13], aS[14], aS[15], aS[16])
            ddBg:SetColorTexture(aS[5], aS[6], aS[7], aS[8])
        end

        ddBtn:SetScript("OnClick", function()
            if menu:IsShown() then menu:Hide()
            else RebuildProfileMenu(); menu:Show() end
        end)
        ddBtn:SetScript("OnEnter", function() ActiveApplyHover() end)
        ddBtn:SetScript("OnLeave", function()
            if not menu:IsShown() then ActiveApplyNormal() end
        end)
        ddBtn:HookScript("OnHide", function() menu:Hide() end)
        menu:HookScript("OnShow", function()
            ActiveApplyHover()
        end)
        menu:SetScript("OnHide", function(self)
            self:SetScript("OnUpdate", nil)
            if ddBtn:IsMouseOver() then ActiveApplyHover()
            else ActiveApplyNormal() end
        end)

        -- "Assign to Spec" label
        local specLabel = EllesmereUI.MakeFont(rowFrame, 12, nil, 1, 1, 1, 0.45)
        PP.Point(specLabel, "LEFT", profLabel, "LEFT", DD_W + GAP, 0)
        specLabel:SetText(EllesmereUI.L("Assign to Spec"))
        specLabel:SetJustifyH("LEFT")

        -- Assign to Spec button
        local assignBtn = CreateFrame("Button", nil, rowFrame)
        PP.Size(assignBtn, BTN_W, CTRL_H)
        PP.Point(assignBtn, "TOPLEFT", specLabel, "BOTTOMLEFT", 0, -6)
        assignBtn:SetFrameLevel(rowFrame:GetFrameLevel() + 2)
        EllesmereUI.MakeStyledButton(assignBtn, "Assign to Spec", 11, PROF_BTN_COLOURS, function()
            local db = EllesmereUIDB or {}
            if not db.specProfiles then db.specProfiles = {} end
            local tempDB = { _profileSpecs = {} }
            local order, profiles = EllesmereUI.GetProfileList()
            for _, pName in ipairs(order) do tempDB._profileSpecs[pName] = {} end
            for specID, pName in pairs(db.specProfiles) do
                if tempDB._profileSpecs[pName] then
                    tempDB._profileSpecs[pName][specID] = true
                end
            end
            local curActiveName = EllesmereUI.GetActiveProfileName()
            EllesmereUI:ShowSpecAssignPopup({
                db = tempDB,
                dbKey = "_profileSpecs",
                presetKey = curActiveName,
                allPresetKeys = function()
                    local list = {}
                    for _, n in ipairs(order) do
                        if profiles[n] then list[#list + 1] = { key = n, name = n } end
                    end
                    return list
                end,
                onDone = function()
                    db.specProfiles = {}
                    for pName, specSet in pairs(tempDB._profileSpecs) do
                        for specID in pairs(specSet) do
                            db.specProfiles[specID] = pName
                        end
                    end
                    EllesmereUI:RefreshPage()
                end,
            })
        end)

        -- "New Profile" label
        local newLabel = EllesmereUI.MakeFont(rowFrame, 12, nil, 1, 1, 1, 0.45)
        PP.Point(newLabel, "LEFT", specLabel, "LEFT", BTN_W + GAP, 0)
        newLabel:SetText(EllesmereUI.L("New Profile"))
        newLabel:SetJustifyH("LEFT")

        -- "Create New (Copy)" button
        local copyBtn = CreateFrame("Button", nil, rowFrame)
        PP.Size(copyBtn, BTN_W, CTRL_H)
        PP.Point(copyBtn, "TOPLEFT", newLabel, "BOTTOMLEFT", 0, -6)
        copyBtn:SetFrameLevel(rowFrame:GetFrameLevel() + 2)
        EllesmereUI.MakeStyledButton(copyBtn, "Create New (Copy)", 11, PROF_BTN_COLOURS, function()
            EllesmereUI:ShowInputPopup({
                title       = EllesmereUI.L("Copy Profile"),
                message     = EllesmereUI.L("Enter a name for the new profile:"),
                placeholder = EllesmereUI.L("My Profile"),
                confirmText = EllesmereUI.L("Save"),
                cancelText  = EllesmereUI.L("Cancel"),
                onConfirm   = function(name)
                    if not name or name == "" then return end
                    local _, profiles = EllesmereUI.GetProfileList()
                    if profiles and profiles[name] then
                        EllesmereUI:ShowConfirmPopup({
                            title = EllesmereUI.L("Name Taken"),
                            message = EllesmereUI.Lf("A profile named \"%1$s\" already exists. Please choose a different name.", name),
                            confirmText = EllesmereUI.L("OK"),
                            hideCancel = true,
                            onConfirm = function() end,
                        })
                        return
                    end
                    EllesmereUI.SaveCurrentAsProfile(name)
                    EllesmereUI.RequestReload(EllesmereUI.L("Copy Profile"), EllesmereUI.L("Reload to finish switching to the new profile."))
                end,
            })
        end)

        y = y - ROW_H
    end

    -------------------------------------------------------------------
    --  PER-ADDON EXPORT
    -------------------------------------------------------------------
    _, h = W:Spacer(parent, y, 18);  y = y - h

    do
        local ADDON_DB_MAP_LOCAL = EllesmereUI.VisibleProfileAddons(EllesmereUI._ADDON_DB_MAP)
        local PAD        = EllesmereUI.CONTENT_PAD
        local totalW     = parent:GetWidth() - PAD * 2
        local HDR_H      = 72
        local COL_HDR_H  = 28
        -- Single footer row: count + "Include layout" + "Include Global Settings" side by side, Export button on the right.
        local FOOTER_H   = 50

        -- Short descriptions per addon folder
        local ADDON_DESCS = {
            EllesmereUIActionBars        = "Modern action bars built for performance and clarity.",
            EllesmereUINameplates        = "Clean, lightweight nameplates with endless customization.",
            EllesmereUIUnitFrames        = "Simple unit frames with a modern visual style.",
            EllesmereUICooldownManager   = "A CDM replacement focused on performance, customizations and alerts.",
            EllesmereUIResourceBars      = "Custom Resource Bars with thresholds, hash lines and more.",
            EllesmereUIRaidFrames        = "Incredibly light performance, modern raid frames with endless flexibility.",
            EllesmereUIAuraBuffReminders = "Simple raid buff, auras, consumables and talent reminders.",
            EllesmereUIQoL               = "Lightweight quality of life tools and enhancements.",
            EllesmereUIDragonRiding      = "Skyriding HUD with speed, vigor and second wind tracking.",
            EllesmereUIBlizzardSkin       = "Clean and beautiful visual refreshes for Blizzard UI elements.",
            EllesmereUIFriends           = "A modern friends list with built-in organization tools.",
            EllesmereUIMythicTimer       = "Mythic+ timer, targeted spell bars, and standalone cast bars.",
            EllesmereUIQuestTracker      = "A clean, updated reskin of Blizzard's Quest Tracker.",
            EllesmereUIMinimap           = "A new age minimap with clean styling and square layout options.",
            EllesmereUIDamageMeters      = "Lightweight damage meters with simple but powerful customization.",
            EllesmereUIChat              = "Modern chat enhancements with useful utilities.",
            EllesmereUIBags              = "A beautiful visual refresh of Blizzard Bags with intuitive organization.",
            EllesmereUIQuickdraw         = "Hold a key to open a menu of actions; point or scroll to choose, release to fire.",
        }

        local SCROLL_MAX_H = 285
        local contentH = #ADDON_DB_MAP_LOCAL * ROW_H_A
        local scrollH = math.min(contentH, SCROLL_MAX_H)
        local SECTION_H = HDR_H + COL_HDR_H + scrollH + 8 + FOOTER_H

        -- Non-interactive panel behind the whole section.
        local sectionBg = CreateFrame("Frame", nil, parent)
        sectionBg:SetFrameLevel(parent:GetFrameLevel())
        PP.Size(sectionBg, totalW, SECTION_H)
        PP.Point(sectionBg, "TOPLEFT", parent, "TOPLEFT", PAD, y)
        sectionBg:EnableMouse(false)
        local sBg = sectionBg:CreateTexture(nil, "BACKGROUND")
        sBg:SetAllPoints()
        sBg:SetColorTexture(0.06, 0.08, 0.10, 0.50)
        EllesmereUI.MakeBorder(sectionBg, 1, 1, 1, 0.10, PP)

        local hdrFrame = CreateFrame("Frame", nil, parent)
        PP.Size(hdrFrame, totalW, HDR_H)
        PP.Point(hdrFrame, "TOPLEFT", parent, "TOPLEFT", PAD, y)

        local hdrTitle = EllesmereUI.MakeFont(hdrFrame, 14, nil, 1, 1, 1, 0.9)
        PP.Point(hdrTitle, "TOPLEFT", hdrFrame, "TOPLEFT", SIDE_PAD, -20)
        hdrTitle:SetText(EllesmereUI.L("Export Profile"))
        hdrTitle:SetJustifyH("LEFT")

        local hdrDesc = EllesmereUI.MakeFont(hdrFrame, 11, nil, 1, 1, 1, 0.35)
        PP.Point(hdrDesc, "TOPLEFT", hdrTitle, "BOTTOMLEFT", 0, -9)
        PP.Point(hdrDesc, "RIGHT", hdrFrame, "RIGHT", -(160 + SIDE_PAD), 0)
        hdrDesc:SetText(EllesmereUI.L("Choose which addons to include in your exported profile. Check everything for a full profile export."))
        hdrDesc:SetJustifyH("LEFT")
        hdrDesc:SetWordWrap(true)

        local hdrDiv = hdrFrame:CreateTexture(nil, "ARTWORK")
        hdrDiv:SetColorTexture(1, 1, 1, 0.10)
        hdrDiv:SetHeight(1)
        PP.Point(hdrDiv, "BOTTOMLEFT", hdrFrame, "BOTTOMLEFT", SIDE_PAD, 0)
        PP.Point(hdrDiv, "BOTTOMRIGHT", hdrFrame, "BOTTOMRIGHT", -SIDE_PAD, 0)
        if hdrDiv.SetSnapToPixelGrid then hdrDiv:SetSnapToPixelGrid(false); hdrDiv:SetTexelSnappingBias(0) end

        -- Build addon item list
        local selectedAddons = {}
        local includeLayoutExport = true     -- "Unlock Mode Layout" include (default on)
        local includeGlobalsExport = true    -- "Global Settings" include (default on)
        -- "Overrides" include: nil = AUTO -- ON when every loaded module is checked, OFF for subsets, until the user toggles it in the
        -- Include dropdown. Resolved via EffectiveIncludeOverrides (footer block).
        local includeOverridesExport = nil
        local EffectiveIncludeOverrides
        -- "Window & Tooltip Skins": the Blizz UI Enhanced account-global bundle (Window Skins + Tooltips, Menus & Popups). Default OFF --
        -- an importer who opts in gets them across ALL of their profiles.
        local includeWindowSkinsExport = false
        local addonItems = {}
        local addonVisuals = {}
        local footerCountFs
        -- Module connectivity from the LIVE active-profile layout (LOCAL folders, matching selectedAddons' keyspace). Drives the hard-couple + affordance.
        local exportComponents = EllesmereUI.BuildModuleComponents({
            anchors     = EllesmereUIDB and EllesmereUIDB.unlockAnchors,
            widthMatch  = EllesmereUIDB and EllesmereUIDB.unlockWidthMatch,
            heightMatch = EllesmereUIDB and EllesmereUIDB.unlockHeightMatch,
        })
        local FOLDER_DISPLAY = {}
        for _, e in ipairs(ADDON_DB_MAP_LOCAL) do FOLDER_DISPLAY[e.folder] = e.display end

        for _, entry in ipairs(ADDON_DB_MAP_LOCAL) do
            local loaded = EllesmereUI.IsModuleAddonLoaded(entry.folder)
            local folder = entry.folder
            addonItems[#addonItems + 1] = {
                folder  = folder,
                display = entry.display,
                desc    = ADDON_DESCS[folder] or "",
                loaded  = loaded,
                getVal  = function() return selectedAddons[folder] or false end,
                -- Hard-couple: (un)checking a module sets its whole connected component, gated to loaded (exportable) members.
                setVal  = function(v)
                    -- Layout OFF: relationships aren't exported, so skip the hard-couple and let each linked module be picked alone.
                    local members = includeLayoutExport and exportComponents and exportComponents[folder]
                    if members then
                        for f in pairs(members) do
                            if EllesmereUI.IsModuleAddonLoaded(f) then selectedAddons[f] = v or nil end
                        end
                    else
                        selectedAddons[folder] = v or nil
                    end
                end,
            }
            if loaded then selectedAddons[folder] = true end
        end

        local function RefreshFooterCount()
            if not footerCountFs then return end
            local count = 0
            for _ in pairs(selectedAddons) do count = count + 1 end
            footerCountFs:SetText(EllesmereUI.Lf("Export will include %1$s of %2$s addons.", count, #addonItems))
        end

        local _refreshSelAllColor
        local function RefreshAllAddonVisuals()
            for _, fn in ipairs(addonVisuals) do fn() end
            RefreshFooterCount()
            if _refreshSelAllColor then _refreshSelAllColor() end
        end

        do
            local LINK_GAP = 12
            local selAllBtn = CreateFrame("Button", nil, hdrFrame)
            selAllBtn:SetFrameLevel(hdrFrame:GetFrameLevel() + 2)
            local selAllLbl = selAllBtn:CreateFontString(nil, "OVERLAY")
            selAllLbl:SetFont(FONT, 12, EllesmereUI.GetFontOutlineFlag())
            selAllLbl:SetText(EllesmereUI.L("Select All"))
            selAllLbl:SetTextColor(1, 1, 1, 0.40)
            selAllLbl:SetPoint("CENTER")
            selAllBtn:SetSize(selAllLbl:GetStringWidth() + 4, 18)
            selAllBtn:SetPoint("RIGHT", hdrFrame, "RIGHT", -(STATUS_W + LINK_GAP + SIDE_PAD), 0)
            selAllBtn:SetPoint("TOP", hdrDesc, "TOP", 0, 0)

            local function AllSelected()
                for _, item in ipairs(addonItems) do
                    if item.loaded and not item.getVal() then return false end
                end
                return true
            end

            local function RefreshSelAllColor()
                if AllSelected() then
                    selAllLbl:SetTextColor(EG.r, EG.g, EG.b, 0.7)
                else
                    selAllLbl:SetTextColor(1, 1, 1, 0.40)
                end
            end

            _refreshSelAllColor = RefreshSelAllColor
            RefreshSelAllColor()

            selAllBtn:SetScript("OnEnter", function()
                if AllSelected() then
                    selAllLbl:SetTextColor(EG.r, EG.g, EG.b, 1)
                else
                    selAllLbl:SetTextColor(1, 1, 1, 0.80)
                end
            end)
            selAllBtn:SetScript("OnLeave", function() RefreshSelAllColor() end)
            selAllBtn:SetScript("OnClick", function()
                for _, item in ipairs(addonItems) do
                    if item.loaded then item.setVal(true) end
                end
                RefreshAllAddonVisuals()
            end)

            local linkDiv = hdrFrame:CreateTexture(nil, "OVERLAY", nil, 7)
            linkDiv:SetColorTexture(1, 1, 1, 0.15)
            if linkDiv.SetSnapToPixelGrid then linkDiv:SetSnapToPixelGrid(false); linkDiv:SetTexelSnappingBias(0) end
            PP.Point(linkDiv, "LEFT", selAllBtn, "RIGHT", LINK_GAP / 2, 0)
            linkDiv:SetWidth(1)
            linkDiv:SetHeight(10)

            local deselBtn = CreateFrame("Button", nil, hdrFrame)
            deselBtn:SetFrameLevel(hdrFrame:GetFrameLevel() + 2)
            local deselLbl = deselBtn:CreateFontString(nil, "OVERLAY")
            deselLbl:SetFont(FONT, 12, EllesmereUI.GetFontOutlineFlag())
            deselLbl:SetText(EllesmereUI.L("Deselect All"))
            deselLbl:SetTextColor(1, 1, 1, 0.40)
            deselLbl:SetPoint("CENTER")
            deselBtn:SetSize(deselLbl:GetStringWidth() + 4, 18)
            PP.Point(deselBtn, "LEFT", selAllBtn, "RIGHT", LINK_GAP, 0)
            deselBtn:SetScript("OnEnter", function() deselLbl:SetTextColor(1, 1, 1, 0.80) end)
            deselBtn:SetScript("OnLeave", function() deselLbl:SetTextColor(1, 1, 1, 0.40) end)
            deselBtn:SetScript("OnClick", function()
                for _, item in ipairs(addonItems) do
                    item.setVal(false)
                end
                RefreshAllAddonVisuals()
            end)
        end

        y = y - HDR_H

        local colHdrFrame = CreateFrame("Frame", nil, parent)
        PP.Size(colHdrFrame, totalW, COL_HDR_H)
        PP.Point(colHdrFrame, "TOPLEFT", parent, "TOPLEFT", PAD, y)

        local colAddon = EllesmereUI.MakeFont(colHdrFrame, 11, nil, 1, 1, 1, 0.40)
        PP.Point(colAddon, "LEFT", colHdrFrame, "LEFT", SIDE_PAD, 0)
        colAddon:SetText(EllesmereUI.L("Addon"))
        colAddon:SetJustifyH("LEFT")

        local colStatus = EllesmereUI.MakeFont(colHdrFrame, 11, nil, 1, 1, 1, 0.40)
        PP.Point(colStatus, "RIGHT", colHdrFrame, "RIGHT", -SIDE_PAD, 0)
        colStatus:SetText(EllesmereUI.L("Status"))
        colStatus:SetJustifyH("RIGHT")

        local colInclude = EllesmereUI.MakeFont(colHdrFrame, 11, nil, 1, 1, 1, 0.40)
        PP.Point(colInclude, "CENTER", colHdrFrame, "RIGHT", INCLUDE_CENTER_X, 0)
        colInclude:SetText(EllesmereUI.L("Include"))
        colInclude:SetJustifyH("CENTER")

        y = y - COL_HDR_H

        -- Scrollable addon list (max 300px)
        local scrollClip = CreateFrame("Frame", nil, parent)
        PP.Size(scrollClip, totalW, scrollH)
        PP.Point(scrollClip, "TOPLEFT", parent, "TOPLEFT", PAD, y)
        scrollClip:SetClipsChildren(true)

        local scrollFrame = CreateFrame("ScrollFrame", nil, scrollClip)
        scrollFrame:SetAllPoints()

        local scrollChild = CreateFrame("Frame", nil, scrollFrame)
        scrollChild:SetSize(totalW, contentH)
        scrollFrame:SetScrollChild(scrollChild)

        -- Mouse wheel scrolling
        local scrollOffset = 0
        scrollClip:EnableMouseWheel(true)
        scrollClip:SetScript("OnMouseWheel", function(_, delta)
            local maxScroll = math.max(0, contentH - scrollH)
            scrollOffset = math.max(0, math.min(maxScroll, scrollOffset - delta * ROW_H_A))
            scrollFrame:SetVerticalScroll(scrollOffset)
        end)

        -- Addon rows (parented to scrollChild)
        for i, item in ipairs(addonItems) do
            BuildAddonListRow(scrollChild, i, item, totalW, {
                active = item.loaded,
                inactiveText = EllesmereUI.L("Not Loaded"), inactiveColor = { 1, 1, 1, 0.25 },
                visuals = addonVisuals,
                -- Hard-couple co-toggles a whole component, so repaint EVERY row -- siblings lighting up is the "linked" affordance.
                onToggle = function() RefreshAllAddonVisuals() end,
                linked = function()
                    return includeLayoutExport and exportComponents and exportComponents[item.folder], item.folder, FOLDER_DISPLAY
                end,
                linkedTip = function(list)
                    return EllesmereUI.Lf("Linked by Anchor/Width/Height Matching to: %1$s. These export together.", list)
                end,
                blockedTip = EllesmereUI.L("Addon not loaded"),
            })
        end

        y = y - scrollH

        -- Footer (inside the background panel)
        y = y - 8

        local footerFrame = CreateFrame("Frame", nil, parent)
        PP.Size(footerFrame, totalW, FOOTER_H)
        PP.Point(footerFrame, "TOPLEFT", parent, "TOPLEFT", PAD, y)

        local footerDiv = footerFrame:CreateTexture(nil, "ARTWORK")
        footerDiv:SetColorTexture(1, 1, 1, 0.10)
        footerDiv:SetHeight(1)
        PP.Point(footerDiv, "TOPLEFT", footerFrame, "TOPLEFT", SIDE_PAD, 0)
        PP.Point(footerDiv, "TOPRIGHT", footerFrame, "TOPRIGHT", -SIDE_PAD, 0)
        if footerDiv.SetSnapToPixelGrid then footerDiv:SetSnapToPixelGrid(false); footerDiv:SetTexelSnappingBias(0) end

        footerCountFs = EllesmereUI.MakeFont(footerFrame, 12, nil, 1, 1, 1, 0.40)
        -- Selection count, top-left of the footer. The Include dropdown and Export Profile button sit right-aligned on the same row.
        PP.Point(footerCountFs, "TOPLEFT", footerFrame, "TOPLEFT", SIDE_PAD, -16)
        footerCountFs:SetJustifyH("LEFT")
        RefreshFooterCount()

        local EXPORT_BTN_W = 180
        local EXPORT_BTN_H = 30
        local exportSelBtn = CreateFrame("Button", nil, footerFrame)
        PP.Size(exportSelBtn, EXPORT_BTN_W, EXPORT_BTN_H)
        PP.Point(exportSelBtn, "RIGHT", footerFrame, "RIGHT", -SIDE_PAD, 0)
        exportSelBtn:SetFrameLevel(footerFrame:GetFrameLevel() + 2)

        -- Styled to match the Done button: green border + text, dark bg, fade hover
        local DB = EllesmereUI.DARK_BG
        local eaBrd = EllesmereUI.MakeBorder(exportSelBtn, EG.r, EG.g, EG.b, 0.7, PP)
        local eaBg = EllesmereUI.SolidTex(exportSelBtn, "BACKGROUND", DB.r, DB.g, DB.b, 0.92)
        eaBg:SetAllPoints()
        local eaLbl = EllesmereUI.MakeFont(exportSelBtn, 12, nil, EG.r, EG.g, EG.b)
        eaLbl:SetAlpha(0.7)
        eaLbl:SetPoint("CENTER")
        eaLbl:SetText(EllesmereUI.L("Export Profile"))

        -- "Include:" checkbox dropdown -- Overrides / Unlock Mode Layout / Global Settings, immediately left of the Export Profile button.
        -- Overrides defaults to AUTO: on when every loaded module is checked, off for subsets, until explicitly toggled. Marks recompute
        -- on every open so the auto state is current whenever the menu is visible.
        do
            local function AllLoadedSelected()
                for _, item in ipairs(addonItems) do
                    if item.loaded and not selectedAddons[item.folder] then return false end
                end
                return true
            end
            EffectiveIncludeOverrides = function()
                if includeOverridesExport ~= nil then return includeOverridesExport end
                return AllLoadedSelected()
            end

            local ddBtn, ddLabelFS = MakeDropdown(footerFrame, 190, EXPORT_BTN_H, function() return "" end)
            PP.Point(ddBtn, "RIGHT", exportSelBtn, "LEFT", -12, 0)

            local incLbl = EllesmereUI.MakeFont(footerFrame, 12, nil, 1, 1, 1, 0.6)
            PP.Point(incLbl, "RIGHT", ddBtn, "LEFT", -8, 0)
            incLbl:SetText(EllesmereUI.L("Include:"))

            -- The Window & Tooltip Skins row only exists when the Blizz UI Enhanced module is loaded (its bundle can't be built otherwise).
            local hasBlizzSkinRow = EllesmereUI.IsModuleAddonLoaded("EllesmereUIBlizzardSkin")

            local function Summary()
                local parts = {}
                local total = hasBlizzSkinRow and 4 or 3
                if EffectiveIncludeOverrides() then parts[#parts + 1] = EllesmereUI.L("Overrides") end
                if includeLayoutExport then parts[#parts + 1] = EllesmereUI.L("Layout") end
                if includeGlobalsExport then parts[#parts + 1] = EllesmereUI.L("Globals") end
                if hasBlizzSkinRow and includeWindowSkinsExport then parts[#parts + 1] = EllesmereUI.L("Window Skins") end
                if #parts == 0 then return EllesmereUI.L("Nothing Extra") end
                if #parts == total then return EllesmereUI.L("Everything") end
                return table.concat(parts, ", ")
            end
            local function RefreshSummary() ddLabelFS:SetText(Summary()) end

            local rowDefs = {
                { label = "Overrides",
                  tip   = "Include your complete override setup: spec and conditional override values, groups, their custom Unlock Mode layouts, and Buff Manager overrides. On import this replaces the recipient's overrides entirely.",
                  get   = function() return EffectiveIncludeOverrides() end,
                  set   = function() includeOverridesExport = not EffectiveIncludeOverrides() end },
                { label = "Unlock Mode Layout",
                  tip   = "Include the anchor & size-match relationships between modules. Off = export each module's own positions only, with no cross-module tying.",
                  get   = function() return includeLayoutExport end,
                  set   = function() includeLayoutExport = not includeLayoutExport end },
                { label = "Global Settings",
                  tip   = "Include fonts, custom colours, dark mode, accent colour and UI scale with this export. Off = only the selected modules' own settings export, keeping the recipient's global look.",
                  get   = function() return includeGlobalsExport end,
                  set   = function() includeGlobalsExport = not includeGlobalsExport end },
            }
            if hasBlizzSkinRow then
                rowDefs[#rowDefs + 1] = {
                    label = "Window & Tooltip Skins",
                    tip   = "Include your Blizz UI Enhanced settings from the Window Skins and Tooltips, Menus & Popups tabs. These are account-wide: if the importer opts in, they overwrite that player's settings across ALL of their profiles.",
                    get   = function() return includeWindowSkinsExport end,
                    set   = function() includeWindowSkinsExport = not includeWindowSkinsExport end }
            end
            local menu = MakeDropdownMenu(ddBtn, 240)
            menu:SetSize(240, #rowDefs * 26 + 8)
            local marks = {}
            local function RefreshMenu()
                for i, def in ipairs(rowDefs) do marks[i]:SetShown(def.get()) end
            end
            for i, def in ipairs(rowDefs) do
                local row = CreateFrame("Button", nil, menu)
                row:SetHeight(26)
                row:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -(4 + (i - 1) * 26))
                row:SetPoint("RIGHT", menu, "RIGHT", -4, 0)
                row:SetFrameLevel(menu:GetFrameLevel() + 1)
                local hl = row:CreateTexture(nil, "ARTWORK")
                hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 1); hl:SetAlpha(0)
                local box = CreateFrame("Frame", nil, row)
                box:SetSize(CHK_SZ, CHK_SZ)
                box:SetPoint("LEFT", row, "LEFT", 6, 0)
                local bbg = box:CreateTexture(nil, "BACKGROUND"); bbg:SetAllPoints()
                bbg:SetColorTexture(0.12, 0.12, 0.14, 1)
                EllesmereUI.MakeBorder(box, 0.25, 0.25, 0.28, 0.6, PP)
                local mark = box:CreateTexture(nil, "ARTWORK")
                mark:SetPoint("TOPLEFT", box, "TOPLEFT", 3, -3)
                mark:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -3, 3)
                mark:SetColorTexture(EG.r, EG.g, EG.b, 1)
                marks[i] = mark
                local lbl = EllesmereUI.MakeFont(row, 12, nil, 1, 1, 1, 0.7)
                lbl:SetPoint("LEFT", box, "RIGHT", 8, 0)
                lbl:SetText(EllesmereUI.L(def.label))
                row:SetScript("OnEnter", function()
                    hl:SetAlpha(0.05)
                    EllesmereUI.ShowWidgetTooltip(row, EllesmereUI.L(def.tip))
                end)
                row:SetScript("OnLeave", function()
                    hl:SetAlpha(0)
                    EllesmereUI.HideWidgetTooltip()
                end)
                row:SetScript("OnClick", function()
                    def.set()
                    RefreshMenu()
                    RefreshSummary()
                end)
            end
            -- HookScript: MakeDropdownMenu owns OnShow (scale + outside-click close); our mark refresh rides alongside it.
            menu:HookScript("OnShow", RefreshMenu)
            ddBtn:SetScript("OnClick", function()
                RefreshSummary()
                if menu:IsShown() then menu:Hide() else RefreshMenu(); menu:Show() end
            end)
            -- Keep the AUTO-mode summary honest after module toggles.
            ddBtn:HookScript("OnEnter", RefreshSummary)
            RefreshSummary()
        end

        MakeAccentFade(exportSelBtn, eaLbl, eaBrd)
        exportSelBtn:SetScript("OnClick", function()
            local folders = {}
            local hasAny = false
            for folder in pairs(selectedAddons) do
                folders[folder] = true
                hasAny = true
            end
            if not hasAny then
                if exportSelBtn._flashError then exportSelBtn._flashError() end
                return
            end
            local activeName = EllesmereUI.GetActiveProfileName()
            -- Every loaded module checked = FULL export: pass nil folders so the string is a plain full-profile string (no subset stamps),
            -- keeping import defaults and API strings identical.
            local allSelected = true
            for _, item in ipairs(addonItems) do
                if item.loaded and not selectedAddons[item.folder] then allSelected = false; break end
            end
            local exportFolders = (not allSelected) and folders or nil
            local includeOverrides = EffectiveIncludeOverrides and EffectiveIncludeOverrides() or false
            local function finishExport(includeCDM, cdmSpecs)
                local str = EllesmereUI.ExportProfile(activeName, exportFolders, includeLayoutExport, includeCDM, cdmSpecs, includeGlobalsExport, includeOverrides, includeWindowSkinsExport)
                if str then EllesmereUI:ShowExportPopup(str) end
            end
            -- If the CDM module is selected, run the shared flow (ask -> spec picker); otherwise export straight away with no CDM spell layout.
            if folders["EllesmereUICooldownManager"] then
                EllesmereUI.RunCDMSpellExportFlow(activeName, finishExport)
            else
                finishExport(false, nil)
            end
        end)
        exportSelBtn._flashError = BuildErrorFlash(exportSelBtn, eaBrd)

        y = y - FOOTER_H
    end

    -------------------------------------------------------------------
    --  Interactive Import API hookup (EllesmereUI.ImportProfileInteractive)
    -------------------------------------------------------------------
    -- Reset the sub-page stack to the main Profiles view. The page wrapper is cached across tab switches, so a declined/replaced API
    -- session would otherwise leave its import page showing on the next visit.
    EllesmereUI._ProfilesResetToMain = function()
        importPage:Hide()
        pastePage:Hide()
        mainPage:Show()
    end

    -- Continue an API session with its decoded payload: UI-scale prompt (at most once), then the normal selection page. Registered per
    -- build (latest wins) and re-resolved from the namespace by every async continuation, so decode + scale popup land on THIS build's live frames.
    EllesmereUI._ProfilesApiProceed = function(payload)
        local s = EllesmereUI._apiImportSession
        if not s or s.state == "done" then return end
        if s.scaleAsked then
            ShowImportPage(s.str, payload, s.name, nil, nil, s.applyScale)
        else
            MaybeConfirmUIScale(payload, function(applyScale)
                s.scaleAsked = true
                s.applyScale = applyScale
                local go = EllesmereUI._ProfilesApiProceed
                if go then go(payload) end
            end)
        end
    end

    -- Enter (or re-enter) a pending API import session: decode the string once, then proceed. Called by ImportProfileInteractive after it
    -- navigates here, and self-invoked at each build end so a session survives page rebuilds.
    EllesmereUI._ProfilesConsumeApiImport = function()
        local s = EllesmereUI._apiImportSession
        if not s or s.state == "done" then return end
        EllesmereUI._EnsureApiImportCloseHook()
        s.state = "active"
        if s.payload then
            EllesmereUI._ProfilesApiProceed(s.payload)
        elseif not s.decoding then
            s.decoding = true
            EllesmereUI.DecodeImportStringAsync(s.str, function(payload, err)
                s.decoding = nil
                -- The session may have been declined or replaced while the decode was in flight; drop a stale result.
                if EllesmereUI._apiImportSession ~= s or s.state == "done" then return end
                if not payload then
                    EllesmereUI:ShowInfoPopup({
                        title   = EllesmereUI.L("Import Failed"),
                        content = err or EllesmereUI.L("Invalid import string."),
                    })
                    EllesmereUI._FinishApiImportSession(false)
                    return
                end
                s.payload = payload
                local go = EllesmereUI._ProfilesApiProceed
                if go then go(payload) end
            end)
        end
    end
    EllesmereUI._ProfilesConsumeApiImport()

    return 0
end
