-------------------------------------------------------------------------------
--  EUI_UnhaltedConverter_Options.lua
--  Registers the experimental Unhalted -> EllesmereUI converter page.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local PAGE = "Convert"

---------------------------------------------------------------------------
--  Confirm + apply + reload
---------------------------------------------------------------------------
-- Registered at file scope (like every other module's StaticPopupDialogs
-- entries -- see EllesmereUI_Profiles.lua / EllesmereUIUnitFrames.lua).
--
-- Never reassign the bare `StaticPopupDialogs` global (not even a defensive
-- `StaticPopupDialogs = StaticPopupDialogs or {}` guard, which never actually
-- creates a new table since Blizzard's FrameXML always sets this up long
-- before any AddOn loads). Assigning to the GLOBAL NAME taints that global
-- slot itself for every future reader, session-wide -- confirmed via
-- Logs/taint.log: dozens of unrelated Blizzard systems (and even a
-- third-party addon) picked up this addon's taint the moment they did a bare
-- `StaticPopupDialogs` read, which is what eventually blocked GameMenuFrame's
-- Logout button and ToggleGameMenu's ClearTarget() call. Writing only to a
-- KEY (`StaticPopupDialogs["EUI_UNHALTED_CONVERT_APPLY"] = {...}`) taints
-- just that key's value, not the global slot -- the same pattern every
-- sibling module already uses without issue.
StaticPopupDialogs["EUI_UNHALTED_CONVERT_APPLY"] = {
    text = "Apply the converted Unhalted layout to your current EllesmereUI profile?\n\nThis imports only the Unit Frames and Raid Frames modules, then DISABLES Unhalted Unit Frames (two unit-frame addons cannot run together \226\128\148 leaving both on causes a UI error) and reloads. You can re-enable Unhalted from the AddOns list any time.",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function(self, payload)
        local ok, err = _G._EUC_ApplyPayload(payload)
        if ok then
            -- ReloadUI() must be called directly on this hardware-event path
            -- (the StaticPopup accept click). Deferring it via C_Timer severs
            -- the hardware-event context and WoW blocks the protected Reload().
            ReloadUI()
        else
            EllesmereUI:ShowInfoPopup({ title = "Apply Failed", content = err or "Unknown error." })
        end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true,
}

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not EllesmereUI or not EllesmereUI.RegisterModule then return end

    local PP = EllesmereUI.PP
    local EG = EllesmereUI.ELLESMERE_GREEN
    local FONT = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("EllesmereUIUnhaltedConverter")) or "Fonts\\FRIZQT__.TTF"

    local function DB()
        local db = _G._EUC_DB
        return db and db.profile
    end

    ---------------------------------------------------------------------------
    --  Small button helper (bordered, hover brighten)
    ---------------------------------------------------------------------------
    local function MakeButton(parent, w, h, label, onClick)
        local btn = CreateFrame("Button", nil, parent)
        PP.Size(btn, w, h)
        btn:SetFrameLevel(parent:GetFrameLevel() + 2)
        local cDB = EllesmereUI.DARK_BG
        local bg = EllesmereUI.SolidTex(btn, "BACKGROUND", cDB.r, cDB.g, cDB.b, 0.92)
        bg:SetAllPoints()
        local brd = EllesmereUI.MakeBorder(btn, EG.r, EG.g, EG.b, 0.7, PP)
        local lbl = EllesmereUI.MakeFont(btn, 13, nil, EG.r, EG.g, EG.b)
        lbl:SetAlpha(0.75)
        lbl:SetPoint("CENTER")
        lbl:SetText(label)
        btn:SetScript("OnEnter", function() lbl:SetAlpha(1); if brd.SetColor then brd:SetColor(EG.r, EG.g, EG.b, 1) end end)
        btn:SetScript("OnLeave", function() lbl:SetAlpha(0.75); if brd.SetColor then brd:SetColor(EG.r, EG.g, EG.b, 0.7) end end)
        btn:SetScript("OnClick", onClick)
        btn._label = lbl
        return btn
    end

    ---------------------------------------------------------------------------
    --  Page builder
    ---------------------------------------------------------------------------
    local pasteAbsorber  -- captured for the button handlers
    local notesFS        -- on-page "notes" text (avoids a second popup over the copy box)

    -- Write conversion notes to the on-page area rather than a popup, so the
    -- copyable-string popup and the notes never overlap.
    local function SetNotes(warnings)
        if not notesFS then return end
        if not warnings or #warnings == 0 then
            notesFS:SetText("|cff59d99cAll settings converted with no adjustments.|r")
            return
        end
        local lines = { ("|cffffcc00%d adjustment%s:|r"):format(#warnings, #warnings == 1 and "" or "s") }
        for _, w in ipairs(warnings) do lines[#lines + 1] = "  - " .. w end
        notesFS:SetText(table.concat(lines, "\n"))
    end

    local function GetOpts()
        local p = DB()
        return {
            single = not p or p.doSingle ~= false,
            group  = not p or p.doGroup ~= false,
        }
    end

    local function DoConvert(applyAfter)
        if not pasteAbsorber then return end
        local str = pasteAbsorber.GetText()
        if not str or str == "" then
            EllesmereUI:ShowInfoPopup({ title = "Nothing to Convert", content = "Paste your Unhalted (!UUF_) import string first." })
            return
        end
        local opts = GetOpts()
        if not opts.single and not opts.group then
            EllesmereUI:ShowInfoPopup({ title = "Nothing Selected", content = "Enable Single Frames and/or Party + Raid first." })
            return
        end
        local payload, euiString, warnings, err = _G._EUC_Convert(str, opts)
        if not payload then
            EllesmereUI:ShowInfoPopup({ title = "Conversion Failed", content = err or "Could not convert that string." })
            return
        end
        SetNotes(warnings)
        if applyAfter then
            local dlg = StaticPopup_Show("EUI_UNHALTED_CONVERT_APPLY")
            if dlg then dlg.data = payload end
        else
            if euiString then
                EllesmereUI:ShowExportPopup(euiString)
            else
                EllesmereUI:ShowInfoPopup({ title = "Conversion Failed", content = "Could not encode the EllesmereUI string." })
            end
        end
    end

    local function BuildPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local PAD = 20
        local y = yOffset
        local _, h

        EllesmereUI:ClearContentHeader()

        -- Intro
        _, h = W:SectionHeader(parent, "MIGRATE FROM UNHALTED", y); y = y - h
        local intro = EllesmereUI.MakeFont(parent, 12, nil, 1, 1, 1, 0.6)
        intro:SetJustifyH("LEFT")
        intro:SetWidth(560)
        PP.Point(intro, "TOPLEFT", parent, "TOPLEFT", PAD, y)
        intro:SetText("Paste an Unhalted Unit Frames export string below, then convert it into an EllesmereUI import string. Single frames convert with high fidelity; party/raid and frame positions are best-effort and may need touch-up in Unlock mode.")
        y = y - (intro:GetStringHeight() + 18)

        -- Paste panel
        local PANEL_H = 150
        local panelFrame = CreateFrame("Frame", nil, parent)
        PP.Point(panelFrame, "TOPLEFT", parent, "TOPLEFT", PAD, y)
        PP.Point(panelFrame, "TOPRIGHT", parent, "TOPRIGHT", -PAD, y)
        panelFrame:SetHeight(PANEL_H)
        local panelBg = panelFrame:CreateTexture(nil, "BACKGROUND")
        panelBg:SetAllPoints()
        panelBg:SetColorTexture(0.06, 0.08, 0.10, 0.50)
        EllesmereUI.MakeBorder(panelFrame, 1, 1, 1, 0.10, PP)

        local pasteSF = CreateFrame("ScrollFrame", nil, panelFrame)
        pasteSF:SetPoint("TOPLEFT", 16, -12)
        pasteSF:SetPoint("BOTTOMRIGHT", -16, 12)

        local pasteBox = CreateFrame("EditBox", nil, pasteSF)
        pasteBox:SetFont(FONT, 11, EllesmereUI.GetFontOutlineFlag("EllesmereUIUnhaltedConverter"))
        pasteBox:SetTextColor(1, 1, 1, 0.8)
        pasteBox:SetAutoFocus(false)
        pasteBox:SetMultiLine(true)
        pasteBox:SetWidth(520)
        pasteSF:SetScrollChild(pasteBox)
        pasteSF:SetScript("OnSizeChanged", function(_, w) if w and w > 0 then pasteBox:SetWidth(w) end end)

        panelFrame:EnableMouse(true)
        panelFrame:SetScript("OnMouseDown", function() pasteBox:SetFocus() end)

        local placeholder = pasteSF:CreateFontString(nil, "ARTWORK")
        placeholder:SetFont(FONT, 12, EllesmereUI.GetFontOutlineFlag("EllesmereUIUnhaltedConverter"))
        placeholder:SetTextColor(1, 1, 1, 0.20)
        placeholder:SetPoint("TOPLEFT", pasteSF, "TOPLEFT", 0, 0)
        placeholder:SetText("Paste your Unhalted !UUF_ string here...")

        pasteBox:SetScript("OnTextChanged", function(s)
            if s:GetText() == "" then placeholder:Show() else placeholder:Hide() end
        end)
        pasteBox:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)

        pasteAbsorber = EllesmereUI.AttachImportPasteAbsorber(pasteBox, function()
            EllesmereUI:ShowInfoPopup({ title = "Paste Interrupted", content = "The pasted string could not be read completely. Please paste it again." })
        end)

        y = y - PANEL_H - 16

        -- Scope toggles
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Convert Single Frames",
              tooltip = "Player, Target, Focus, Pet, Target of Target, Focus Target, Boss",
              getValue = function() local p = DB(); return not p or p.doSingle ~= false end,
              setValue = function(v) local p = DB(); if p then p.doSingle = v end end },
            { type = "toggle", text = "Convert Party + Raid",
              tooltip = "Best-effort mapping into EllesmereUI Raid Frames (owns both party and raid)",
              getValue = function() local p = DB(); return not p or p.doGroup ~= false end,
              setValue = function(v) local p = DB(); if p then p.doGroup = v end end }
        ); y = y - h

        y = y - 8

        -- Buttons
        local convertBtn = MakeButton(parent, 200, 34, "Convert to String", function() DoConvert(false) end)
        PP.Point(convertBtn, "TOPLEFT", parent, "TOPLEFT", PAD, y)
        local applyBtn = MakeButton(parent, 160, 34, "Convert & Apply", function() DoConvert(true) end)
        PP.Point(applyBtn, "TOPLEFT", convertBtn, "TOPRIGHT", 12, 0)
        y = y - 34 - 14

        -- Footnote
        local foot = EllesmereUI.MakeFont(parent, 11, nil, 1, 1, 1, 0.4)
        foot:SetJustifyH("LEFT")
        foot:SetWidth(560)
        PP.Point(foot, "TOPLEFT", parent, "TOPLEFT", PAD, y)
        foot:SetText("Tip: keep Unhalted enabled while converting to better transfer frame positions. \"Convert & Apply\" imports into your active profile, disables Unhalted (two unit-frame addons can't run together), and reloads. If you instead copy the string and import it yourself, disable Unhalted Unit Frames before reloading to avoid a UI error.")
        y = y - (foot:GetStringHeight() + 14)

        -- Notes area (conversion adjustments; filled after each Convert)
        local _, nh = W:SectionHeader(parent, "NOTES", y); y = y - nh
        notesFS = EllesmereUI.MakeFont(parent, 11, nil, 1, 1, 1, 0.65)
        notesFS:SetJustifyH("LEFT")
        notesFS:SetJustifyV("TOP")
        notesFS:SetWidth(560)
        notesFS:SetHeight(200)
        PP.Point(notesFS, "TOPLEFT", parent, "TOPLEFT", PAD, y)
        notesFS:SetText("|cff808080Convert a string to see any adjustments here.|r")
        y = y - 210

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Register
    ---------------------------------------------------------------------------
    EllesmereUI:RegisterModule("EllesmereUIUnhaltedConverter", {
        title       = "Unhalted Converter",
        description = "Experimental: migrate Unhalted Unit Frames into EllesmereUI.",
        pages       = { PAGE },
        buildPage   = function(pageName, parent, yOffset)
            if pageName == PAGE then return BuildPage(pageName, parent, yOffset) end
        end,
    })

    SLASH_EUCONVERT1 = "/uufconvert"
    SLASH_EUCONVERT2 = "/unhaltedconvert"
    SlashCmdList.EUCONVERT = function()
        if InCombatLockdown and InCombatLockdown() then return end
        EllesmereUI:ShowModule("EllesmereUIUnhaltedConverter")
    end
end)
