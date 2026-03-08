-------------------------------------------------------------------------------
--  EUI__General_Options.lua
--  Registers the Global Settings module with EllesmereUI
--  CVar-based settings that apply to all EllesmereUI addons
--
--  Default-application policy:
--    We use C_CVar.GetCVarInfo(name) to get both the current value and
--    Blizzard's built-in default.  Our preferred defaults are only applied
--    when the CVar is still sitting at Blizzard's default — meaning
--    neither the player nor another addon has touched it.  If the value
--    differs from the Blizzard default in any way, we leave it alone.
--    Widgets always read the live CVar value so they stay in sync
--    regardless of who set it.
-------------------------------------------------------------------------------
local ADDON_NAME = ...

-------------------------------------------------------------------------------
--  Page / section names
-------------------------------------------------------------------------------
local PAGE_GENERAL      = "General"
local PAGE_CORE        = "Quick Setup"
local PAGE_COLORS      = "Fonts & Colors"
local PAGE_PROFILES    = "Profiles"

-------------------------------------------------------------------------------
--  FCT font — handled by EllesmereUI_Startup.lua which runs earlier.
-------------------------------------------------------------------------------

-- Wait for EllesmereUI to exist
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    -- Re-apply combat text font at login — handled by EllesmereUI_Startup.lua.

    if not EllesmereUI or not EllesmereUI.RegisterModule then return end
    local PP = EllesmereUI.PanelPP

    local GLOBAL_KEY = EllesmereUI.GLOBAL_KEY or "_EUIGlobal"
    local floor = math.floor

    ---------------------------------------------------------------------------
    --  CVar helpers
    ---------------------------------------------------------------------------
    local function GetCVarNum(cvar)
        return tonumber(GetCVar(cvar)) or 0
    end

    local function GetCVarBool(cvar)
        return GetCVar(cvar) == "1"
    end

    local function SetCVarSafe(cvar, value)
        if InCombatLockdown() then return end
        SetCVar(cvar, value)
    end

    --- Returns current, default as strings (nil-safe)
    local function CVarInfo(cvar)
        local cur, def = C_CVar.GetCVarInfo(cvar)
        return cur or "", def or ""
    end

    --- Returns true when the CVar is still at Blizzard's built-in default,
    --- meaning no addon or player has changed it.
    local function IsAtBlizzardDefault(cvar)
        local cur, def = CVarInfo(cvar)
        return cur == def
    end

    ---------------------------------------------------------------------------
    --  EUI preferred defaults — only applied when CVar == Blizzard default
    --
    --  { cvarName, euiPreferred }
    --  For the "hide pet/periodic" group we set three CVars to "0" (hidden).
    ---------------------------------------------------------------------------
    local EUI_DEFAULTS = {
        { "cameraDistanceMaxZoomFactor",                    "2.6" },
        { "ActionButtonUseKeyDown",                         "1"   },
        { "SpellQueueWindow",                               "300" },
        { "floatingCombatTextCombatHealing_v2",             "1"   },
        { "floatingCombatTextCombatDamage_v2",              "1"   },
        { "WorldTextScale_v2",                              "0.5" },
        { "floatingCombatTextCombatLogPeriodicSpells_v2",   "0"   },
        { "floatingCombatTextPetMeleeDamage_v2",            "0"   },
        { "floatingCombatTextPetSpellDamage_v2",            "0"   },
    }

    --- Walk the table once at login and apply only where safe.
    local function ApplySmartDefaults()
        for _, entry in ipairs(EUI_DEFAULTS) do
            local cvar, preferred = entry[1], entry[2]
            if IsAtBlizzardDefault(cvar) then
                SetCVarSafe(cvar, preferred)
            end
        end
    end
    ApplySmartDefaults()

    ---------------------------------------------------------------------------
    --  Lightweight Error Grabber (replaces Blizzard error popup with chat links)
    ---------------------------------------------------------------------------
    local errorGrabberActive = false
    local errorStore = {}
    local errorCount = 0
    local MAX_ERRORS = 50
    local originalErrorHandler = nil
    local chatHookInstalled = false

    ---------------------------------------------------------------------------
    --  Error Detail Popup (singleton, styled to match EllesmereUI popups)
    ---------------------------------------------------------------------------
    local errorPopup

    local function ShowErrorPopup(id, err)
        if not errorPopup then
            local POPUP_W, POPUP_H = 520, 340
            local FONT = EllesmereUI.EXPRESSWAY
            local SCROLL_STEP = 60
            local SMOOTH_SPEED = 12

            -- Dimmer
            local dimmer = CreateFrame("Frame", nil, UIParent)
            dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
            dimmer:SetAllPoints(UIParent)
            dimmer:EnableMouse(true)
            dimmer:EnableMouseWheel(true)
            dimmer:SetScript("OnMouseWheel", function() end)
            dimmer:Hide()
            local dimTex = EllesmereUI.SolidTex(dimmer, "BACKGROUND", 0, 0, 0, 0.25)
            dimTex:SetAllPoints()

            -- Popup frame
            local popup = CreateFrame("Frame", nil, dimmer)
            popup:SetSize(POPUP_W, POPUP_H)
            popup:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
            popup:SetFrameStrata("FULLSCREEN_DIALOG")
            popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)
            popup:EnableMouse(true)

            local bg = EllesmereUI.SolidTex(popup, "BACKGROUND", 0.06, 0.08, 0.10, 0.95)
            bg:SetAllPoints()
            EllesmereUI.MakeBorder(popup, 1, 1, 1, 0.15, EllesmereUI.PanelPP)

            -- Plain ScrollFrame (no Blizzard template)
            local sf = CreateFrame("ScrollFrame", nil, popup)
            sf:SetPoint("TOPLEFT", popup, "TOPLEFT", 20, -20)
            sf:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -20, 60)
            sf:SetFrameLevel(popup:GetFrameLevel() + 1)
            sf:EnableMouseWheel(true)

            local sc = CreateFrame("Frame", nil, sf)
            sc:SetWidth(sf:GetWidth() or (POPUP_W - 40))
            sc:SetHeight(1)
            sf:SetScrollChild(sc)

            -- EditBox inside scroll child
            local editBox = CreateFrame("EditBox", nil, sc)
            editBox:SetMultiLine(true)
            editBox:SetAutoFocus(false)
            editBox:SetFont(FONT, 12, EllesmereUI.GetFontOutlineFlag())
            editBox:SetTextColor(1, 1, 1, 0.75)
            editBox:SetAllPoints(sc)
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
            editBox:SetScript("OnTextChanged", function(self, userInput)
                if userInput and self._readOnlyText and self:GetText() ~= self._readOnlyText then
                    self:SetText(self._readOnlyText)
                    self:HighlightText()
                end
            end)
            editBox:SetScript("OnMouseUp", function(self)
                C_Timer.After(0, function()
                    editBox:SetFocus()
                    editBox:HighlightText()
                end)
            end)
            sf:SetScript("OnMouseUp", function()
                editBox:SetFocus()
                editBox:HighlightText()
            end)

            -- Smooth scroll state
            local scrollTarget = 0
            local isSmoothing = false
            local smoothFrame = CreateFrame("Frame")
            smoothFrame:Hide()

            -- Custom scrollbar track
            local scrollTrack = CreateFrame("Frame", nil, sf)
            scrollTrack:SetWidth(4)
            scrollTrack:SetPoint("TOPRIGHT", sf, "TOPRIGHT", -2, -4)
            scrollTrack:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", -2, 4)
            scrollTrack:SetFrameLevel(sf:GetFrameLevel() + 2)
            scrollTrack:Hide()

            local trackBg = EllesmereUI.SolidTex(scrollTrack, "BACKGROUND", 1, 1, 1, 0.02)
            trackBg:SetAllPoints()

            -- Thumb
            local scrollThumb = CreateFrame("Button", nil, scrollTrack)
            scrollThumb:SetWidth(4)
            scrollThumb:SetHeight(60)
            scrollThumb:SetPoint("TOP", scrollTrack, "TOP", 0, 0)
            scrollThumb:SetFrameLevel(scrollTrack:GetFrameLevel() + 1)
            scrollThumb:EnableMouse(true)
            scrollThumb:RegisterForDrag("LeftButton")
            scrollThumb:SetScript("OnDragStart", function() end)
            scrollThumb:SetScript("OnDragStop", function() end)

            local thumbTex = EllesmereUI.SolidTex(scrollThumb, "ARTWORK", 1, 1, 1, 0.27)
            thumbTex:SetAllPoints()

            local isDragging = false
            local dragStartY, dragStartScroll

            local function UpdateThumb()
                local maxScroll = tonumber(sf:GetVerticalScrollRange()) or 0
                if maxScroll <= 0 then scrollTrack:Hide(); return end
                scrollTrack:Show()
                local trackH = scrollTrack:GetHeight()
                local visH = sf:GetHeight()
                local ratio = visH / (visH + maxScroll)
                local thumbH = math.max(30, trackH * ratio)
                scrollThumb:SetHeight(thumbH)
                local scrollRatio = (tonumber(sf:GetVerticalScroll()) or 0) / maxScroll
                scrollThumb:ClearAllPoints()
                scrollThumb:SetPoint("TOP", scrollTrack, "TOP", 0, -(scrollRatio * (trackH - thumbH)))
            end

            smoothFrame:SetScript("OnUpdate", function(_, elapsed)
                local cur = sf:GetVerticalScroll()
                local maxScroll = tonumber(sf:GetVerticalScrollRange()) or 0
                scrollTarget = math.max(0, math.min(maxScroll, scrollTarget))
                local diff = scrollTarget - cur
                if math.abs(diff) < 0.3 then
                    sf:SetVerticalScroll(scrollTarget)
                    UpdateThumb()
                    isSmoothing = false
                    smoothFrame:Hide()
                    return
                end
                local newScroll = cur + diff * math.min(1, SMOOTH_SPEED * elapsed)
                newScroll = math.max(0, math.min(maxScroll, newScroll))
                sf:SetVerticalScroll(newScroll)
                UpdateThumb()
            end)

            local function SmoothScrollTo(target)
                local maxScroll = tonumber(sf:GetVerticalScrollRange()) or 0
                scrollTarget = math.max(0, math.min(maxScroll, target))
                if not isSmoothing then
                    isSmoothing = true
                    smoothFrame:Show()
                end
            end

            sf:SetScript("OnMouseWheel", function(self, delta)
                local maxScroll = tonumber(self:GetVerticalScrollRange()) or 0
                if maxScroll <= 0 then return end
                local base = isSmoothing and scrollTarget or self:GetVerticalScroll()
                SmoothScrollTo(base - delta * SCROLL_STEP)
            end)
            sf:SetScript("OnScrollRangeChanged", function() UpdateThumb() end)

            -- Thumb drag
            local function StopDrag()
                if not isDragging then return end
                isDragging = false
                scrollThumb:SetScript("OnUpdate", nil)
            end

            scrollThumb:SetScript("OnMouseDown", function(self, button)
                if button ~= "LeftButton" then return end
                isSmoothing = false; smoothFrame:Hide()
                isDragging = true
                local _, cy = GetCursorPosition()
                dragStartY = cy / self:GetEffectiveScale()
                dragStartScroll = sf:GetVerticalScroll()
                self:SetScript("OnUpdate", function(self2)
                    if not IsMouseButtonDown("LeftButton") then StopDrag(); return end
                    isSmoothing = false; smoothFrame:Hide()
                    local _, cy2 = GetCursorPosition()
                    cy2 = cy2 / self2:GetEffectiveScale()
                    local deltaY = dragStartY - cy2
                    local trackH = scrollTrack:GetHeight()
                    local maxTravel = trackH - self2:GetHeight()
                    if maxTravel <= 0 then return end
                    local maxScroll = tonumber(sf:GetVerticalScrollRange()) or 0
                    local newScroll = math.max(0, math.min(maxScroll, dragStartScroll + (deltaY / maxTravel) * maxScroll))
                    scrollTarget = newScroll
                    sf:SetVerticalScroll(newScroll)
                    UpdateThumb()
                end)
            end)
            scrollThumb:SetScript("OnMouseUp", function(_, button)
                if button == "LeftButton" then StopDrag() end
            end)

            popup._editBox = editBox
            popup._scrollFrame = sf
            popup._scrollChild = sc

            -- Close button
            local closeBtn = CreateFrame("Button", nil, popup)
            closeBtn:SetSize(120, 32)
            closeBtn:SetPoint("BOTTOM", popup, "BOTTOM", 0, 14)
            closeBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
            EllesmereUI.MakeStyledButton(closeBtn, "Close", 13,
                EllesmereUI.RB_COLOURS, function() dimmer:Hide() end)

            -- Click dimmer to close
            dimmer:SetScript("OnMouseDown", function()
                if not popup:IsMouseOver() then dimmer:Hide() end
            end)

            -- Escape to close
            popup:EnableKeyboard(true)
            popup:SetScript("OnKeyDown", function(self, key)
                if key == "ESCAPE" then
                    self:SetPropagateKeyboardInput(false)
                    dimmer:Hide()
                else
                    self:SetPropagateKeyboardInput(true)
                end
            end)

            -- Reset scroll on hide
            dimmer:HookScript("OnHide", function()
                isSmoothing = false; smoothFrame:Hide()
                scrollTarget = 0
                sf:SetVerticalScroll(0)
            end)

            popup._dimmer = dimmer
            errorPopup = popup
        end

        -- Populate
        local text = (err.message or "unknown") .. "\n\n--- Stack Trace ---\n" .. (err.stack or "N/A")
        if err.source then
            text = "Addon: " .. err.source .. "\n\n" .. text
        end
        if err.counter and err.counter > 1 then
            text = "Occurrences: " .. err.counter .. "\n" .. text
        end
        errorPopup._editBox:SetText(text)
        errorPopup._editBox._readOnlyText = text
        -- Resize scroll child to fit editbox content
        local sfW = errorPopup._scrollFrame:GetWidth()
        errorPopup._scrollChild:SetWidth(sfW)
        errorPopup._editBox:SetWidth(sfW - 12)
        C_Timer.After(0.01, function()
            local h = errorPopup._editBox:GetHeight()
            errorPopup._scrollChild:SetHeight(h)
        end)
        errorPopup._dimmer:Show()

        -- Auto-select all text after a brief delay so the editbox is fully laid out
        C_Timer.After(0.05, function()
            errorPopup._editBox:SetFocus()
            errorPopup._editBox:HighlightText()
        end)
    end

    local function InstallChatHook()
        if chatHookInstalled then return end
        chatHookInstalled = true
        local origSetHyperlink = ItemRefTooltip.SetHyperlink
        function ItemRefTooltip:SetHyperlink(link, ...)
            local errId = link:match("^euierr:(%d+)")
            if errId then
                local id = tonumber(errId)
                local err = errorStore[id]
                if err then ShowErrorPopup(id, err) end
                return
            end
            return origSetHyperlink(self, link, ...)
        end
    end

    local THROTTLE_SEC = 10

    -- Error sound: randomized glass breaking
    local ERROR_GLASS_SOUNDS = { 569086, 568056, 569345 }
    local lastGlassSoundTime = 0

    local function GrabError(msg)
        if not errorGrabberActive then
            if originalErrorHandler then originalErrorHandler(msg) end
            return
        end
        msg = tostring(msg or "")
        local now = GetTime()
        -- Deduplicate: if same message exists, bump counter + throttle print
        for id, err in pairs(errorStore) do
            if err.message == msg then
                err.counter = err.counter + 1
                if now - (err.lastPrint or 0) < THROTTLE_SEC then return end
                err.lastPrint = now
                InstallChatHook()
                local short = msg:sub(1, 80)
                if #msg > 80 then short = short .. "..." end
                local src = err.source or "Unknown"
                print("Bugcatcher: |cffff4444" .. src .. "|r caused |Heuierr:" .. id .. "|h|cff0cd29d[Error " .. id .. " x" .. err.counter .. "]|r|h")
                if EllesmereUIDB and EllesmereUIDB.errorSound and now - lastGlassSoundTime >= 1 then
                    lastGlassSoundTime = now
                    PlaySoundFile(ERROR_GLASS_SOUNDS[math.random(#ERROR_GLASS_SOUNDS)], "Master")
                end
                return
            end
        end
        errorCount = errorCount + 1
        local id = errorCount
        local stack = debugstack(3) or ""
        -- Extract addon name from first AddOns/ path in the stack
        local source = stack:match("AddOns[\\/]([^\\/]+)[\\/]")
        errorStore[id] = { message = msg, stack = stack, counter = 1, lastPrint = now, source = source }
        if errorCount > MAX_ERRORS then
            errorStore[errorCount - MAX_ERRORS] = nil
        end
        InstallChatHook()
        local short = msg:sub(1, 80)
        if #msg > 80 then short = short .. "..." end
        local src = source or "Unknown"
        print("Bugcatcher: |cffff4444" .. src .. "|r caused |Heuierr:" .. id .. "|h|cff0cd29d[Error " .. id .. "]|r|h")
        if EllesmereUIDB and EllesmereUIDB.errorSound and now - lastGlassSoundTime >= 1 then
            lastGlassSoundTime = now
            PlaySoundFile(ERROR_GLASS_SOUNDS[math.random(#ERROR_GLASS_SOUNDS)], "Master")
        end
    end

    local function EnableErrorGrabber()
        if errorGrabberActive then return end
        errorGrabberActive = true
        originalErrorHandler = geterrorhandler()
        seterrorhandler(GrabError)
        -- Keep scriptErrors=1 so WoW invokes our custom handler
        SetCVarSafe("scriptErrors", "1")
        -- Suppress default Lua-error popup (NOT UIErrorsFrame — that shows
        -- in-game red text like "Can't do that yet" which must stay visible)
        if ScriptErrorsFrame then
            ScriptErrorsFrame:Hide()
            ScriptErrorsFrame:UnregisterAllEvents()
        end
        -- Ensure UIErrorsFrame has UI_ERROR_MESSAGE registered (a previous
        -- version accidentally unregistered it; re-register to fix)
        if UIErrorsFrame then
            UIErrorsFrame:RegisterEvent("UI_ERROR_MESSAGE")
        end
    end

    local function DisableErrorGrabber()
        if not errorGrabberActive then return end
        errorGrabberActive = false
        if originalErrorHandler then
            seterrorhandler(originalErrorHandler)
            originalErrorHandler = nil
        end
    end

    -- Apply on login if saved (default: OFF when nil)
    if EllesmereUIDB and EllesmereUIDB.errorGrabber == true then
        EnableErrorGrabber()
    end
    -- Apply suppress on login (default: ON when nil or errorGrabber is off)
    if not EllesmereUIDB or EllesmereUIDB.errorGrabber ~= true then
        if not EllesmereUIDB or EllesmereUIDB.suppressErrors ~= false then
            SetCVarSafe("scriptErrors", "0")
        end
    end

    -- Expose for toggle
    EllesmereUI._enableErrorGrabber = EnableErrorGrabber
    EllesmereUI._disableErrorGrabber = DisableErrorGrabber

    -- NOTE: Optimized graphics settings are NOT re-applied on login.
    -- SetCVar already persists to WoW's config, so re-applying would override
    -- any manual adjustments the user makes in WoW's graphics settings panel.

    ---------------------------------------------------------------------------
    --  General page
    ---------------------------------------------------------------------------
    local function BuildGeneralPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        parent._showRowDivider = true

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -------------------------------------------------------------------
        --  Optimized graphics CVar table + buttons (above all sections)
        -------------------------------------------------------------------
        local OPTIMIZED_CVARS = {
            { "graphicsShadowQuality",      "0" },
            { "graphicsLiquidDetail",       "0" },
            { "graphicsParticleDensity",    "5" },
            { "graphicsSSAO",              "0" },
            { "graphicsDepthEffects",       "0" },
            { "graphicsComputeEffects",     "0" },
            { "graphicsOutlineMode",        "0" },
            { "graphicsTextureResolution",  "2" },
            { "graphicsSpellDensity",       "1" },
            { "graphicsProjectedTextures",  "1" },
            { "graphicsViewDistance",        "1" },
            { "graphicsEnvironmentDetail",  "1" },
            { "graphicsGroundClutter",      "1" },
            { "RAIDsettingsEnabled",        "0" },
            { "ResampleAlwaysSharpen",      "1" },
        }

        local function ApplyOptimizedGfx()
            if not EllesmereUIDB then EllesmereUIDB = {} end
            -- One-time store: only snapshot if no backup exists yet
            if not EllesmereUIDB.gfxBackup then
                local backup = {}
                for _, entry in ipairs(OPTIMIZED_CVARS) do
                    backup[entry[1]] = GetCVar(entry[1])
                end
                backup["Contrast"] = GetCVar("Contrast")
                EllesmereUIDB.gfxBackup = backup
            end
            -- Apply optimized CVars
            for _, entry in ipairs(OPTIMIZED_CVARS) do
                SetCVarSafe(entry[1], entry[2])
            end
            -- Contrast boost: if current contrast ≤ 55, add 10
            local curContrast = tonumber(GetCVar("Contrast")) or 50
            if curContrast <= 55 then
                SetCVarSafe("Contrast", curContrast + 10)
            end
            local rl = EllesmereUI._widgetRefreshList
            if rl then for i = 1, #rl do rl[i]() end end
        end

        local function RestoreGfxSettings()
            if not EllesmereUIDB or not EllesmereUIDB.gfxBackup then return end
            local backup = EllesmereUIDB.gfxBackup
            for _, entry in ipairs(OPTIMIZED_CVARS) do
                local saved = backup[entry[1]]
                if saved then SetCVarSafe(entry[1], saved) end
            end
            if backup["Contrast"] then SetCVarSafe("Contrast", backup["Contrast"]) end
            EllesmereUIDB.gfxBackup = nil
            local rl2 = EllesmereUI._widgetRefreshList
            if rl2 then for i = 1, #rl2 do rl2[i]() end end
        end

        do
            local ROW_H = 52
            local gfxFrame = CreateFrame("Frame", nil, parent)
            local totalW = parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2
            PP.Size(gfxFrame, totalW, ROW_H)
            PP.Point(gfxFrame, "TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD, y)

            -- Optimize button (always visible)
            local optBtn = CreateFrame("Button", nil, gfxFrame)
            local OPT_W = 300
            PP.Size(optBtn, OPT_W, 42)
            PP.Point(optBtn, "TOP", gfxFrame, "TOP", 0, 0)
            optBtn:SetFrameLevel(gfxFrame:GetFrameLevel() + 1)
            EllesmereUI.MakeStyledButton(optBtn, "Optimize My FPS and Graphics", 14,
                EllesmereUI.WB_COLOURS, ApplyOptimizedGfx)
            optBtn:HookScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(optBtn, "Optimizes your graphics settings for maximum FPS and visual clarity.")
            end)
            optBtn:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            -- Restore button (only visible when backup exists)
            local restBtn = CreateFrame("Button", nil, gfxFrame)
            local REST_W = 128
            PP.Size(restBtn, REST_W, 29)
            PP.Point(restBtn, "LEFT", optBtn, "RIGHT", 30, 0)
            restBtn:SetFrameLevel(gfxFrame:GetFrameLevel() + 1)
            restBtn:SetAlpha(0.7)
            local _, _, restLbl = EllesmereUI.MakeStyledButton(restBtn, "Restore My Settings", 10,
                EllesmereUI.RB_COLOURS, RestoreGfxSettings)
            restBtn:HookScript("OnEnter", function() restBtn:SetAlpha(1) end)
            restBtn:HookScript("OnLeave", function() restBtn:SetAlpha(0.7) end)

            local function RefreshRestoreVisibility()
                if EllesmereUIDB and EllesmereUIDB.gfxBackup then
                    restBtn:Show()
                    -- Shift optimize button left to make room
                    optBtn:ClearAllPoints()
                    PP.Point(optBtn, "TOP", gfxFrame, "TOP", -(REST_W / 2 + 15), 0)
                else
                    restBtn:Hide()
                    optBtn:ClearAllPoints()
                    PP.Point(optBtn, "TOP", gfxFrame, "TOP", 0, 0)
                end
            end
            RefreshRestoreVisibility()
            EllesmereUI.RegisterWidgetRefresh(RefreshRestoreVisibility)

            -- "More Information" accent-colored clickable text
            local infoBtn = CreateFrame("Button", nil, gfxFrame)
            infoBtn:SetFrameLevel(gfxFrame:GetFrameLevel() + 1)
            local EG = EllesmereUI.ELLESMERE_GREEN
            local infoFS = infoBtn:CreateFontString(nil, "OVERLAY")
            infoFS:SetFont(EllesmereUI.EXPRESSWAY, 12, EllesmereUI.GetFontOutlineFlag())
            infoFS:SetTextColor(EG.r, EG.g, EG.b, 0.70)
            infoFS:SetText("More Information")
            infoFS:SetPoint("CENTER")
            infoBtn:SetSize(infoFS:GetStringWidth() + 10, 18)
            PP.Point(infoBtn, "TOP", optBtn, "BOTTOM", 0, -4)
            infoBtn:SetScript("OnEnter", function() infoFS:SetTextColor(EG.r, EG.g, EG.b, 1) end)
            infoBtn:SetScript("OnLeave", function() infoFS:SetTextColor(EG.r, EG.g, EG.b, 0.70) end)
            infoBtn:SetScript("OnClick", function()
                EllesmereUI:ShowInfoPopup({
                    title = "FPS & Graphics Optimization",
                    content = "This feature optimizes your in-game graphics settings to give you the best combination of high FPS and visual clarity.\n\nYou can revert all changes at any time by clicking \"Restore My Settings\" which will appear after optimizing.\n\n\nWhat we change:\n\n"
                        .. "Shadow Quality - Disabled (large FPS gain)\n"
                        .. "Liquid Detail - Disabled\n"
                        .. "Particle Density - Set to Ultra (keeps important spell effects)\n"
                        .. "SSAO (Ambient Occlusion) - Disabled\n"
                        .. "Depth Effects - Disabled\n"
                        .. "Compute Effects - Disabled\n"
                        .. "Outline Mode - Disabled\n"
                        .. "Texture Resolution - Set to High\n"
                        .. "Spell Density - Set to Essential\n"
                        .. "Projected Textures - Enabled (needed for ground effects)\n"
                        .. "View Distance - Reduced to 1\n"
                        .. "Environment Detail - Reduced to 1\n"
                        .. "Ground Clutter - Reduced to 1\n"
                        .. "Raid/Dungeon Settings - Uses same settings everywhere\n"
                        .. "Resample Sharpening - Enabled (crisper image)\n"
                        .. "Contrast - Boosted by +10 (if currently 55 or below)\n\n"
                        .. "These settings prioritize frame rate and visual clarity over environmental detail. Textures stay high quality so your character and the world still look perfect.",
                })
            end)

            y = y - ROW_H
        end

        -------------------------------------------------------------------
        --  DISPLAY
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "DISPLAY", y);  y = y - h

        -- Build dropdown values table from THEME_ORDER
        local themeValues = {}
        for _, name in ipairs(EllesmereUI.THEME_ORDER) do
            themeValues[name] = name
        end

        local themeRow
        themeRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Active Theme",
              values=themeValues,
              order=EllesmereUI.THEME_ORDER,
              getValue=function()
                return EllesmereUI.GetActiveTheme()
              end,
              setValue=function(v)
                EllesmereUI.SetActiveTheme(v)
                EllesmereUI:RefreshPage()
              end },
            { type="dropdown", text="Window Scale",
              values={ ["Small (90%)"]="Small (90%)", ["Normal (100%)"]="Normal (100%)", ["Large (110%)"]="Large (110%)", ["Huge (125%)"]="Huge (125%)", ["Massive (150%)"]="Massive (150%)" },
              order={ "Small (90%)", "Normal (100%)", "Large (110%)", "Huge (125%)", "Massive (150%)" },
              getValue=function()
                local raw = (EllesmereUIDB and EllesmereUIDB.panelScale) or 1.0
                local pct = floor(raw * 100 + 0.5)
                if pct == 90  then return "Small (90%)"   end
                if pct == 110 then return "Large (110%)"  end
                if pct == 125 then return "Huge (125%)"   end
                if pct == 150 then return "Massive (150%)" end
                return "Normal (100%)"
              end,
              setValue=function(v)
                local scale = 1.0
                if v == "Small (90%)"    then scale = 0.90
                elseif v == "Large (110%)"  then scale = 1.10
                elseif v == "Huge (125%)"   then scale = 1.25
                elseif v == "Massive (150%)" then scale = 1.50 end
                if EllesmereUI.SetPanelScale then
                    EllesmereUI:SetPanelScale(scale)
                end
              end });  y = y - h

        -- Inline color swatch on Active Theme (left region)
        do
            local leftRgn = themeRow._leftRegion
            local function isCustomColorOff()
                return EllesmereUI.GetActiveTheme() ~= "Custom Color"
            end

            -- Color swatch (closest to dropdown)
            local tcGet = function() return EllesmereUI.GetAccentColor() end
            local tcSet = function(r, g, b) EllesmereUI.SetAccentColor(r, g, b) end
            local tcSwatch, tcUpdateSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, tcGet, tcSet, nil, 20)
            PP.Point(tcSwatch, "RIGHT", leftRgn._control, "LEFT", -12, 0)
            leftRgn._lastInline = tcSwatch
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = isCustomColorOff()
                tcSwatch:SetAlpha(off and 0.15 or 1)
                tcSwatch:EnableMouse(not off)
                tcUpdateSwatch()
            end)
            tcSwatch:SetAlpha(isCustomColorOff() and 0.15 or 1)
            tcSwatch:EnableMouse(not isCustomColorOff())
            tcSwatch:SetScript("OnEnter", function(self)
                if isCustomColorOff() then
                    EllesmereUI.ShowWidgetTooltip(self, "This option is only available for the Custom Color Theme")
                end
            end)
            tcSwatch:SetScript("OnLeave", function()
                EllesmereUI.HideWidgetTooltip()
            end)
        end

        _, h = W:DualRow(parent, y,
            { type="slider", text="UI Scale",
              min=40, max=115, step=1,
              tooltip="Sets the scale of the entire game UI. Defaults to your current WoW UI scale setting.",
              getValue=function()
                if EllesmereUI._blizzUIScaleDragVal then
                    return EllesmereUI._blizzUIScaleDragVal
                end
                return EllesmereUIDB and EllesmereUIDB.blizzUIScale or 100
              end,
              setValue=function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.blizzUIScale = v
                EllesmereUI._blizzUIScaleDragVal = v
                if EllesmereUI._applyBlizzUIScale then EllesmereUI._applyBlizzUIScale() end
                if not EllesmereUI._blizzUIScaleCleanup then
                    EllesmereUI._blizzUIScaleCleanup = true
                    C_Timer.After(0, function()
                        if not EllesmereUI._sliderDragging then
                            EllesmereUI._blizzUIScaleDragVal = nil
                        end
                        EllesmereUI._blizzUIScaleCleanup = false
                    end)
                end
              end },
            { type="toggle", text="Show Minimap Button",
              getValue=function()
                return not (EllesmereUIDB and EllesmereUIDB.showMinimapButton == false)
              end,
              setValue=function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.showMinimapButton = v
                if v then
                    EllesmereUI.ShowMinimapButton()
                else
                    EllesmereUI.HideMinimapButton()
                end
              end });  y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h

        _, h = W:SectionHeader(parent, "COMBAT", y);  y = y - h

        _, h = W:DualRow(parent, y,
            { type="slider", text="Max Camera Distance",
              min=1, max=2.6, step=0.1,
              getValue=function() return GetCVarNum("cameraDistanceMaxZoomFactor") end,
              setValue=function(v)
                v = floor(v * 10 + 0.5) / 10
                SetCVarSafe("cameraDistanceMaxZoomFactor", v)
              end },
            { type="toggle", text="Increase Game Image Quality",
              tooltip="Enables sharpening to improve image clarity. Especially noticeable at lower render scales.",
              getValue=function() return GetCVarBool("ResampleAlwaysSharpen") end,
              setValue=function(v)
                SetCVarSafe("ResampleAlwaysSharpen", v and "1" or "0")
              end });  y = y - h

        _, h = W:DualRow(parent, y,
            { type="toggle", text="Cast Actions on Key Down",
              tooltip="Keybinds respond on key down instead of key up. This helps make your abilities feel more responsive.",
              getValue=function() return GetCVarBool("ActionButtonUseKeyDown") end,
              setValue=function(v)
                SetCVarSafe("ActionButtonUseKeyDown", v and "1" or "0")
              end },
            { type="slider", text="Lag Tolerance",
              tooltip="This is the Spell Queue Window, it helps with making sure you can't queue up too many spells at once which makes the game feel laggy. Recommended settings are generally ~150 for melee and ~300 for casters. Higher if you have high local ping.",
              min=0, max=400, step=1,
              getValue=function() return GetCVarNum("SpellQueueWindow") end,
              setValue=function(v)
                SetCVarSafe("SpellQueueWindow", v)
              end });  y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -------------------------------------------------------------------
        --  EXTRAS
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "EXTRAS", y);  y = y - h

        -- Row 1: Show FPS Counter (left, with swatch+cog) | FPS Toggle Keybind (right)
        local fpsRow
        fpsRow, h = W:DualRow(parent, y,
            { type="toggle", text="Show FPS Counter",
              getValue=function()
                return EllesmereUIDB and EllesmereUIDB.showFPS or false
              end,
              setValue=function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.showFPS = v
                if EllesmereUI._applyFPSCounter then EllesmereUI._applyFPSCounter() end
                EllesmereUI:RefreshPage()
              end },
            { type="label", text="FPS Toggle Keybind" }
        );  y = y - h

        -- Inline color swatch + cog on the FPS toggle (left region)
        do
            local leftRgn = fpsRow._leftRegion
            local function fpsOff()
                return not (EllesmereUIDB and EllesmereUIDB.showFPS)
            end

            local fpsSwGet = function()
                local c = EllesmereUIDB and EllesmereUIDB.fpsColor
                if c then return c.r, c.g, c.b, c.a end
                return 1, 1, 1, 1
            end
            local fpsSwSet = function(r, g, b, a)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.fpsColor = { r = r, g = g, b = b, a = a }
                if EllesmereUI._applyFPSCounter then EllesmereUI._applyFPSCounter() end
            end
            local fpsSwatch, fpsUpdateSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, fpsSwGet, fpsSwSet, true, 20)
            PP.Point(fpsSwatch, "RIGHT", leftRgn._control, "LEFT", -12, 0)
            leftRgn._lastInline = fpsSwatch

            -- Disabled overlay for swatch when FPS is off
            local fpsSwBlock = CreateFrame("Frame", nil, fpsSwatch)
            fpsSwBlock:SetAllPoints()
            fpsSwBlock:SetFrameLevel(fpsSwatch:GetFrameLevel() + 10)
            fpsSwBlock:EnableMouse(true)
            fpsSwBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(fpsSwatch, EllesmereUI.DisabledTooltip("Show FPS Counter"))
            end)
            fpsSwBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            EllesmereUI.RegisterWidgetRefresh(function()
                local off = fpsOff()
                if off then
                    fpsSwatch:SetAlpha(0.3)
                    fpsSwBlock:Show()
                else
                    fpsSwatch:SetAlpha(1)
                    fpsSwBlock:Hide()
                end
                fpsUpdateSwatch()
            end)
            local fpsInitOff = fpsOff()
            fpsSwatch:SetAlpha(fpsInitOff and 0.3 or 1)
            if fpsInitOff then fpsSwBlock:Show() else fpsSwBlock:Hide() end

            local _, fpsCogShow = EllesmereUI.BuildCogPopup({
                title = "FPS Counter Settings",
                rows = {
                    { type="toggle", label="Show Local MS",
                      get=function()
                        if not EllesmereUIDB or EllesmereUIDB.fpsShowLocalMS == nil then return true end
                        return EllesmereUIDB.fpsShowLocalMS
                      end,
                      set=function(v)
                        if not EllesmereUIDB then EllesmereUIDB = {} end
                        EllesmereUIDB.fpsShowLocalMS = v
                        if EllesmereUI._applyFPSCounter then EllesmereUI._applyFPSCounter() end
                      end },
                    { type="toggle", label="Show World MS",
                      get=function()
                        return EllesmereUIDB and EllesmereUIDB.fpsShowWorldMS or false
                      end,
                      set=function(v)
                        if not EllesmereUIDB then EllesmereUIDB = {} end
                        EllesmereUIDB.fpsShowWorldMS = v
                        if EllesmereUI._applyFPSCounter then EllesmereUI._applyFPSCounter() end
                      end },
                },
            })
            local fpsCogBtn = CreateFrame("Button", nil, leftRgn)
            fpsCogBtn:SetSize(26, 26)
            fpsCogBtn:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -9, 0)
            leftRgn._lastInline = fpsCogBtn
            fpsCogBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
            fpsCogBtn:SetAlpha(fpsOff() and 0.15 or 0.4)
            local fpsCogTex = fpsCogBtn:CreateTexture(nil, "OVERLAY")
            fpsCogTex:SetAllPoints()
            fpsCogTex:SetTexture(EllesmereUI.COGS_ICON)
            fpsCogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            fpsCogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            fpsCogBtn:SetScript("OnClick", function(self) fpsCogShow(self) end)

            -- Blocking overlay for cog when FPS is off
            local fpsCogBlock = CreateFrame("Frame", nil, fpsCogBtn)
            fpsCogBlock:SetAllPoints()
            fpsCogBlock:SetFrameLevel(fpsCogBtn:GetFrameLevel() + 10)
            fpsCogBlock:EnableMouse(true)
            fpsCogBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(fpsCogBtn, EllesmereUI.DisabledTooltip("Show FPS Counter"))
            end)
            fpsCogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            EllesmereUI.RegisterWidgetRefresh(function()
                local off = fpsOff()
                if off then
                    fpsCogBtn:SetAlpha(0.15)
                    fpsCogBlock:Show()
                else
                    fpsCogBtn:SetAlpha(0.4)
                    fpsCogBlock:Hide()
                end
            end)
            local fpsCogInitOff = fpsOff()
            fpsCogBtn:SetAlpha(fpsCogInitOff and 0.15 or 0.4)
            if fpsCogInitOff then fpsCogBlock:Show() else fpsCogBlock:Hide() end
        end

        -- FPS Toggle Keybind (built into right region of fpsRow)
        do
            local rightRgn = fpsRow._rightRegion
            local SIDE_PAD = 20

            local KB_W, KB_H = 140, 30
            local kbBtn = CreateFrame("Button", nil, rightRgn)
            PP.Size(kbBtn, KB_W, KB_H)
            PP.Point(kbBtn, "RIGHT", rightRgn, "RIGHT", -SIDE_PAD, 0)
            kbBtn:SetFrameLevel(rightRgn:GetFrameLevel() + 2)
            kbBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            local kbBg = EllesmereUI.SolidTex(kbBtn, "BACKGROUND", EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
            kbBg:SetAllPoints()
            kbBtn._border = EllesmereUI.MakeBorder(kbBtn, 1, 1, 1, EllesmereUI.DD_BRD_A, EllesmereUI.PanelPP)
            local kbLbl = EllesmereUI.MakeFont(kbBtn, 13, nil, 1, 1, 1)
            kbLbl:SetAlpha(EllesmereUI.DD_TXT_A)
            kbLbl:SetPoint("CENTER")

            local function FormatKey(key)
                if not key then return "Not Bound" end
                local parts = {}
                for mod in key:gmatch("(%u+)%-") do
                    parts[#parts + 1] = mod:sub(1, 1) .. mod:sub(2):lower()
                end
                local actualKey = key:match("[^%-]+$") or key
                parts[#parts + 1] = actualKey
                return table.concat(parts, " + ")
            end

            local function RefreshLabel()
                local key = EllesmereUIDB and EllesmereUIDB.fpsToggleKey
                kbLbl:SetText(FormatKey(key))
            end
            RefreshLabel()

            local listening = false

            kbBtn:SetScript("OnClick", function(self, button)
                if button == "RightButton" then
                    if listening then
                        listening = false
                        self:EnableKeyboard(false)
                    end
                    if not EllesmereUIDB then EllesmereUIDB = {} end
                    if EllesmereUIDB.fpsToggleKey and _G["EUI_FPSBindBtn"] then
                        ClearOverrideBindings(_G["EUI_FPSBindBtn"])
                    end
                    EllesmereUIDB.fpsToggleKey = nil
                    RefreshLabel()
                    return
                end
                if listening then return end
                listening = true
                kbLbl:SetText("Press a key...")
                kbBtn:EnableKeyboard(true)
            end)

            kbBtn:SetScript("OnKeyDown", function(self, key)
                if not listening then
                    self:SetPropagateKeyboardInput(true)
                    return
                end
                if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL"
                   or key == "LALT" or key == "RALT" then
                    self:SetPropagateKeyboardInput(true)
                    return
                end
                self:SetPropagateKeyboardInput(false)
                if key == "ESCAPE" then
                    listening = false
                    self:EnableKeyboard(false)
                    RefreshLabel()
                    return
                end
                local mods = ""
                if IsShiftKeyDown() then mods = mods .. "SHIFT-" end
                if IsControlKeyDown() then mods = mods .. "CTRL-" end
                if IsAltKeyDown() then mods = mods .. "ALT-" end
                local fullKey = mods .. key

                if not EllesmereUIDB then EllesmereUIDB = {} end
                local bindBtn = _G["EUI_FPSBindBtn"]
                if bindBtn then
                    if InCombatLockdown() then
                        listening = false
                        self:EnableKeyboard(false)
                        RefreshLabel()
                        return
                    end
                    ClearOverrideBindings(bindBtn)
                    SetOverrideBindingClick(bindBtn, true, fullKey, "EUI_FPSBindBtn")
                end
                EllesmereUIDB.fpsToggleKey = fullKey

                listening = false
                self:EnableKeyboard(false)
                RefreshLabel()
            end)

            kbBtn:SetScript("OnEnter", function(self)
                kbBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_HA)
                if kbBtn._border and kbBtn._border.SetColor then
                    kbBtn._border:SetColor(1, 1, 1, 0.3)
                end
                EllesmereUI.ShowWidgetTooltip(self, "Left-click to set a keybind.\nRight-click to unbind.")
            end)
            kbBtn:SetScript("OnLeave", function()
                if listening then return end
                kbBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
                if kbBtn._border and kbBtn._border.SetColor then
                    kbBtn._border:SetColor(1, 1, 1, EllesmereUI.DD_BRD_A)
                end
                EllesmereUI.HideWidgetTooltip()
            end)

            EllesmereUI.RegisterWidgetRefresh(RefreshLabel)

            rightRgn:SetScript("OnHide", function()
                if listening then
                    listening = false
                    kbBtn:EnableKeyboard(false)
                    RefreshLabel()
                end
            end)
        end

        -- Row 2: Auto Repair (left) | Auto Sell Junk (right)
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Auto Repair",
              tooltip="Automatically repair all gear when visiting a repair vendor.",
              getValue=function()
                if not EllesmereUIDB then return true end
                return EllesmereUIDB.autoRepair ~= false
              end,
              setValue=function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.autoRepair = v
              end },
            { type="toggle", text="Auto Sell Junk",
              tooltip="Automatically sell all junk items when visiting a vendor.",
              getValue=function()
                return EllesmereUIDB and EllesmereUIDB.autoSellJunk or false
              end,
              setValue=function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.autoSellJunk = v
              end }
        );  y = y - h

        -- Row 3: Low Durability Warning (left, with cog+eye+swatch) | Disable Right Click Targeting (right)
        local durWarnRow
        durWarnRow, h = W:DualRow(parent, y,
            { type="toggle", text="Low Durability Warning",
              tooltip="Flashes a warning on screen when any equipped item drops below the configured durability threshold. Only triggers out of combat.",
              getValue=function()
                return EllesmereUIDB and EllesmereUIDB.repairWarning ~= false
              end,
              setValue=function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.repairWarning = v
                EllesmereUI:RefreshPage()
              end },
            { type="toggle", text="Disable Right Click Enemies",
              tooltip="Disables the default behavior of right clicking to target enemies.",
              getValue=function()
                return EllesmereUIDB and EllesmereUIDB.disableRightClickTarget or false
              end,
              setValue=function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.disableRightClickTarget = v
                if EllesmereUI._applyRightClickTarget then EllesmereUI._applyRightClickTarget() end
              end }
        );  y = y - h

        -- Inline: eyeball | cog | color swatch on the durability warning toggle
        do
            local leftRgn = durWarnRow._leftRegion
            local function durOff()
                return EllesmereUIDB and EllesmereUIDB.repairWarning == false
            end

            -- Color swatch (rightmost inline, closest to toggle)
            local durSwGet = function()
                local c = EllesmereUIDB and EllesmereUIDB.durWarnColor
                if c then return c.r, c.g, c.b end
                return 1, 0.27, 0.27
            end
            local durSwSet = function(r, g, b)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.durWarnColor = { r = r, g = g, b = b }
                if EllesmereUI._applyDurWarn then EllesmereUI._applyDurWarn() end
            end
            local durSwatch, durUpdateSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, durSwGet, durSwSet, nil, 20)
            PP.Point(durSwatch, "RIGHT", leftRgn._control, "LEFT", -12, 0)
            leftRgn._lastInline = durSwatch

            -- Disabled overlay for swatch when durability warning is off
            local durSwBlock = CreateFrame("Frame", nil, durSwatch)
            durSwBlock:SetAllPoints()
            durSwBlock:SetFrameLevel(durSwatch:GetFrameLevel() + 10)
            durSwBlock:EnableMouse(true)
            durSwBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(durSwatch, EllesmereUI.DisabledTooltip("Low Durability Warning"))
            end)
            durSwBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            EllesmereUI.RegisterWidgetRefresh(function()
                local off = durOff()
                if off then
                    durSwatch:SetAlpha(0.3)
                    durSwBlock:Show()
                else
                    durSwatch:SetAlpha(1)
                    durSwBlock:Hide()
                end
                durUpdateSwatch()
            end)
            local durInitOff = durOff()
            durSwatch:SetAlpha(durInitOff and 0.3 or 1)
            if durInitOff then durSwBlock:Show() else durSwBlock:Hide() end

            -- Cog popup for durability settings (left of swatch)
            local _, durCogShow = EllesmereUI.BuildCogPopup({
                title = "Durability Settings",
                rows = {
                    { type="slider", label="Y-Offset",
                      min=-600, max=600, step=1,
                      get=function()
                        return EllesmereUIDB and EllesmereUIDB.durWarnYOffset or 250
                      end,
                      set=function(v)
                        if not EllesmereUIDB then EllesmereUIDB = {} end
                        EllesmereUIDB.durWarnYOffset = v
                        EllesmereUIDB.durWarnPos = nil  -- clear custom pos so slider always takes effect
                        if EllesmereUI._durWarnPreview then EllesmereUI._durWarnPreview() end
                      end },
                    { type="slider", label="Repair %",
                      min=5, max=80, step=1,
                      get=function()
                        return EllesmereUIDB and EllesmereUIDB.durWarnThreshold or 40
                      end,
                      set=function(v)
                        if not EllesmereUIDB then EllesmereUIDB = {} end
                        EllesmereUIDB.durWarnThreshold = v
                      end },
                },
            })
            local durCogBtn = CreateFrame("Button", nil, leftRgn)
            durCogBtn:SetSize(26, 26)
            durCogBtn:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -9, 0)
            leftRgn._lastInline = durCogBtn
            durCogBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
            durCogBtn:SetAlpha(durOff() and 0.15 or 0.4)
            local durCogTex = durCogBtn:CreateTexture(nil, "OVERLAY")
            durCogTex:SetAllPoints()
            durCogTex:SetTexture(EllesmereUI.DIRECTIONS_ICON)
            durCogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            durCogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            durCogBtn:SetScript("OnClick", function(self) durCogShow(self) end)

            -- Blocking overlay for cog when durability warning is off
            local durCogBlock = CreateFrame("Frame", nil, durCogBtn)
            durCogBlock:SetAllPoints()
            durCogBlock:SetFrameLevel(durCogBtn:GetFrameLevel() + 10)
            durCogBlock:EnableMouse(true)
            durCogBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(durCogBtn, EllesmereUI.DisabledTooltip("Low Durability Warning"))
            end)
            durCogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            EllesmereUI.RegisterWidgetRefresh(function()
                local off = durOff()
                if off then
                    durCogBtn:SetAlpha(0.15)
                    durCogBlock:Show()
                else
                    durCogBtn:SetAlpha(0.4)
                    durCogBlock:Hide()
                end
            end)
            local durCogInitOff = durOff()
            durCogBtn:SetAlpha(durCogInitOff and 0.15 or 0.4)
            if durCogInitOff then durCogBlock:Show() else durCogBlock:Hide() end

            -- Eye icon to toggle durability warning preview (left of cog)
            local EYE_VISIBLE   = EllesmereUI.MEDIA_PATH .. "icons\\eui-visible.png"
            local EYE_INVISIBLE = EllesmereUI.MEDIA_PATH .. "icons\\eui-invisible.png"
            local durPreviewShown = false
            local eyeBtn = CreateFrame("Button", nil, leftRgn)
            eyeBtn:SetSize(26, 26)
            eyeBtn:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -8, 0)
            leftRgn._lastInline = eyeBtn
            eyeBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
            eyeBtn:SetAlpha(durOff() and 0.15 or 0.4)
            local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
            eyeTex:SetAllPoints()
            local function RefreshDurEye()
                if durPreviewShown then
                    eyeTex:SetTexture(EYE_INVISIBLE)
                else
                    eyeTex:SetTexture(EYE_VISIBLE)
                end
            end
            RefreshDurEye()
            eyeBtn:SetScript("OnEnter", function(self)
                self:SetAlpha(0.7)
                EllesmereUI.ShowWidgetTooltip(self, "Preview durability warning")
            end)
            eyeBtn:SetScript("OnLeave", function(self)
                EllesmereUI.HideWidgetTooltip()
                self:SetAlpha(0.4)
            end)
            eyeBtn:SetScript("OnClick", function(self)
                durPreviewShown = not durPreviewShown
                RefreshDurEye()
                if durPreviewShown then
                    if EllesmereUI._applyDurWarn then EllesmereUI._applyDurWarn() end
                    if EllesmereUI._durWarnPreview then
                        EllesmereUI._durWarnPreview()
                    end
                else
                    if EllesmereUI._durWarnHidePreview then
                        EllesmereUI._durWarnHidePreview()
                    end
                end
            end)

            -- Blocking overlay for eye when durability warning is off
            local eyeBlock = CreateFrame("Frame", nil, eyeBtn)
            eyeBlock:SetAllPoints()
            eyeBlock:SetFrameLevel(eyeBtn:GetFrameLevel() + 10)
            eyeBlock:EnableMouse(true)
            eyeBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(eyeBtn, EllesmereUI.DisabledTooltip("Low Durability Warning"))
            end)
            eyeBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            EllesmereUI.RegisterWidgetRefresh(function()
                local off = durOff()
                if off then
                    eyeBtn:SetAlpha(0.15)
                    eyeBlock:Show()
                else
                    eyeBtn:SetAlpha(0.4)
                    eyeBlock:Hide()
                end
            end)
            local eyeInitOff = durOff()
            eyeBtn:SetAlpha(eyeInitOff and 0.15 or 0.4)
            if eyeInitOff then eyeBlock:Show() else eyeBlock:Hide() end
        end

        -- Row 4: Secondary Stat Display (left, with swatch+cog) | Guild Chat Privacy (right)
        local row4
        row4, h = W:DualRow(parent, y,
            { type="toggle", text="Secondary Stat Display",
              tooltip="Displays secondary stat percentages (Crit, Haste, Mastery, Vers) at the top left of the screen.",
              getValue=function()
                return EllesmereUIDB and EllesmereUIDB.showSecondaryStats or false
              end,
              setValue=function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.showSecondaryStats = v
                if EllesmereUI._applySecondaryStats then EllesmereUI._applySecondaryStats() end
                EllesmereUI:RefreshPage()
              end },
            { type="toggle", text="Guild Chat Privacy Cover",
              tooltip="Displays a spoiler tag over guild chat in the communities window that you can click to hide",
              getValue=function()
                return EllesmereUIDB and EllesmereUIDB.guildChatPrivacy or false
              end,
              setValue=function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.guildChatPrivacy = v
                if EllesmereUI._applyGuildChatPrivacy then EllesmereUI._applyGuildChatPrivacy() end
              end }
        );  y = y - h

        -- Inline color swatch + cog on Secondary Stat Display (left region)
        do
            local leftRgn = row4._leftRegion
            local function statsOff()
                return not (EllesmereUIDB and EllesmereUIDB.showSecondaryStats)
            end

            -- Color swatch for label color (defaults to class color)
            local ssSwGet = function()
                local c = EllesmereUIDB and EllesmereUIDB.secondaryStatsColor
                if c then return c.r, c.g, c.b end
                local _, cls = UnitClass("player")
                local cc = cls and EllesmereUI.GetClassColor(cls)
                if cc then return cc.r, cc.g, cc.b end
                return 1, 1, 1
            end
            local ssSwSet = function(r, g, b)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.secondaryStatsColor = { r = r, g = g, b = b }
                if EllesmereUI._applySecondaryStats then EllesmereUI._applySecondaryStats() end
            end
            local ssSwatch, ssUpdateSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, ssSwGet, ssSwSet, nil, 20)
            PP.Point(ssSwatch, "RIGHT", leftRgn._control, "LEFT", -12, 0)
            leftRgn._lastInline = ssSwatch

            -- Blocking overlay for swatch when Secondary Stat Display is off
            local ssSwBlock = CreateFrame("Frame", nil, ssSwatch)
            ssSwBlock:SetAllPoints()
            ssSwBlock:SetFrameLevel(ssSwatch:GetFrameLevel() + 10)
            ssSwBlock:EnableMouse(true)
            ssSwBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(ssSwatch, EllesmereUI.DisabledTooltip("Secondary Stat Display"))
            end)
            ssSwBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            -- Cog popup: Show Tertiary Stats toggle + Tertiary Label Color + Scale slider
            local _, ssCogShow = EllesmereUI.BuildCogPopup({
                title = "Secondary Stats Settings",
                rows = {
                    { type = "toggle", label = "Show Tertiary Stats",
                      get = function()
                          return EllesmereUIDB and EllesmereUIDB.showTertiaryStats or false
                      end,
                      set = function(v)
                          if not EllesmereUIDB then EllesmereUIDB = {} end
                          EllesmereUIDB.showTertiaryStats = v
                          if EllesmereUI._applySecondaryStats then EllesmereUI._applySecondaryStats() end
                      end },
                    { type = "colorpicker", label = "Tertiary Label Color",
                      disabled = function()
                          return not (EllesmereUIDB and EllesmereUIDB.showTertiaryStats)
                      end,
                      disabledTooltip = "Show Tertiary Stats",
                      get = function()
                          local c = EllesmereUIDB and EllesmereUIDB.tertiaryStatsColor
                          if c then return c.r, c.g, c.b end
                          local _, cls = UnitClass("player")
                          local cc = cls and EllesmereUI.GetClassColor(cls)
                          if cc then return cc.r, cc.g, cc.b end
                          return 1, 1, 1
                      end,
                      set = function(r, g, b)
                          if not EllesmereUIDB then EllesmereUIDB = {} end
                          EllesmereUIDB.tertiaryStatsColor = { r = r, g = g, b = b }
                          if EllesmereUI._applySecondaryStats then EllesmereUI._applySecondaryStats() end
                      end },
                    { type = "slider", label = "Scale", min = 50, max = 200, step = 5,
                      get = function()
                          local pos = EllesmereUIDB and EllesmereUIDB.secondaryStatsPos
                          return math.floor(((pos and pos.scale) or 1.0) * 100 + 0.5)
                      end,
                      set = function(v)
                          if not EllesmereUIDB then EllesmereUIDB = {} end
                          if not EllesmereUIDB.secondaryStatsPos then EllesmereUIDB.secondaryStatsPos = {} end
                          EllesmereUIDB.secondaryStatsPos.scale = v / 100
                          if EllesmereUI._applySecondaryStats then EllesmereUI._applySecondaryStats() end
                      end },
                },
            })
            local ssCogBtn = CreateFrame("Button", nil, leftRgn)
            ssCogBtn:SetSize(26, 26)
            ssCogBtn:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -8, 0)
            leftRgn._lastInline = ssCogBtn
            ssCogBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
            ssCogBtn:SetAlpha(statsOff() and 0.15 or 0.4)
            local ssCogTex = ssCogBtn:CreateTexture(nil, "OVERLAY")
            ssCogTex:SetAllPoints()
            ssCogTex:SetTexture(EllesmereUI.COGS_ICON)
            ssCogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            ssCogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            ssCogBtn:SetScript("OnClick", function(self) ssCogShow(self) end)

            -- Blocking overlay for cog when Secondary Stat Display is off
            local ssCogBlock = CreateFrame("Frame", nil, ssCogBtn)
            ssCogBlock:SetAllPoints()
            ssCogBlock:SetFrameLevel(ssCogBtn:GetFrameLevel() + 10)
            ssCogBlock:EnableMouse(true)
            ssCogBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(ssCogBtn, EllesmereUI.DisabledTooltip("Secondary Stat Display"))
            end)
            ssCogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            -- Refresh: dim + block swatch/cog when toggle is off
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = statsOff()
                if off then
                    ssSwatch:SetAlpha(0.3)
                    ssSwBlock:Show()
                    ssCogBtn:SetAlpha(0.15)
                    ssCogBlock:Show()
                else
                    ssSwatch:SetAlpha(1)
                    ssSwBlock:Hide()
                    ssCogBtn:SetAlpha(0.4)
                    ssCogBlock:Hide()
                end
                ssUpdateSwatch()
            end)
            local ssInitOff = statsOff()
            ssSwatch:SetAlpha(ssInitOff and 0.3 or 1)
            if ssInitOff then ssSwBlock:Show() else ssSwBlock:Hide() end
            ssCogBtn:SetAlpha(ssInitOff and 0.15 or 0.4)
            if ssInitOff then ssCogBlock:Show() else ssCogBlock:Hide() end
        end

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -------------------------------------------------------------------
        --  FLOATING COMBAT TEXT
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "FLOATING COMBAT TEXT", y);  y = y - h

        _, h = W:DualRow(parent, y,
            { type="slider", text="Combat Text Size",
              min=0.5, max=2.5, step=0.1,
              getValue=function() return GetCVarNum("WorldTextScale_v2") end,
              setValue=function(v)
                v = floor(v * 10 + 0.5) / 10
                SetCVarSafe("WorldTextScale_v2", v)
              end },
            { type="toggle", text="Show Healing Text",
              getValue=function() return GetCVarBool("floatingCombatTextCombatHealing_v2") end,
              setValue=function(v)
                SetCVarSafe("floatingCombatTextCombatHealing_v2", v and "1" or "0")
              end });  y = y - h

        local FCT_FONT_DIR = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\"
        local fctFontValues = {
            ["default"]                                = { text = "Blizzard Default", font = "Fonts\\FRIZQT__.TTF" },
            [FCT_FONT_DIR .. "Expressway.TTF"]         = { text = "Expressway",           font = FCT_FONT_DIR .. "Expressway.TTF" },
            [FCT_FONT_DIR .. "Avant Garde.ttf"]        = { text = "Avant Garde",          font = FCT_FONT_DIR .. "Avant Garde.ttf" },
            [FCT_FONT_DIR .. "Arial Bold.TTF"]         = { text = "Arial Bold",           font = FCT_FONT_DIR .. "Arial Bold.TTF" },
            [FCT_FONT_DIR .. "Poppins.ttf"]            = { text = "Poppins",              font = FCT_FONT_DIR .. "Poppins.ttf" },
            [FCT_FONT_DIR .. "FiraSans Medium.ttf"]    = { text = "Fira Sans Medium",     font = FCT_FONT_DIR .. "FiraSans Medium.ttf" },
            [FCT_FONT_DIR .. "Arial Narrow.ttf"]       = { text = "Arial Narrow",         font = FCT_FONT_DIR .. "Arial Narrow.ttf" },
            [FCT_FONT_DIR .. "Changa.ttf"]             = { text = "Changa",               font = FCT_FONT_DIR .. "Changa.ttf" },
            [FCT_FONT_DIR .. "Cinzel Decorative.ttf"]  = { text = "Cinzel Decorative",    font = FCT_FONT_DIR .. "Cinzel Decorative.ttf" },
            [FCT_FONT_DIR .. "Exo.otf"]                = { text = "Exo",                  font = FCT_FONT_DIR .. "Exo.otf" },
            [FCT_FONT_DIR .. "FiraSans Bold.ttf"]      = { text = "Fira Sans Bold",       font = FCT_FONT_DIR .. "FiraSans Bold.ttf" },
            [FCT_FONT_DIR .. "FiraSans Light.ttf"]     = { text = "Fira Sans Light",      font = FCT_FONT_DIR .. "FiraSans Light.ttf" },
            [FCT_FONT_DIR .. "Future X Black.otf"]     = { text = "Future X Black",       font = FCT_FONT_DIR .. "Future X Black.otf" },
            [FCT_FONT_DIR .. "Gotham Narrow Ultra.otf"] = { text = "Gotham Narrow Ultra", font = FCT_FONT_DIR .. "Gotham Narrow Ultra.otf" },
            [FCT_FONT_DIR .. "Gotham Narrow.otf"]      = { text = "Gotham Narrow",        font = FCT_FONT_DIR .. "Gotham Narrow.otf" },
            [FCT_FONT_DIR .. "Russo One.ttf"]          = { text = "Russo One",            font = FCT_FONT_DIR .. "Russo One.ttf" },
            [FCT_FONT_DIR .. "Ubuntu.ttf"]             = { text = "Ubuntu",               font = FCT_FONT_DIR .. "Ubuntu.ttf" },
            [FCT_FONT_DIR .. "Homespun.ttf"]           = { text = "Homespun",             font = FCT_FONT_DIR .. "Homespun.ttf" },
            ["Fonts\\FRIZQT__.TTF"]                    = { text = "Friz Quadrata",        font = "Fonts\\FRIZQT__.TTF" },
            ["Fonts\\ARIALN.TTF"]                      = { text = "Arial",                font = "Fonts\\ARIALN.TTF" },
            ["Fonts\\MORPHEUS.TTF"]                    = { text = "Morpheus",             font = "Fonts\\MORPHEUS.TTF" },
            ["Fonts\\skurri.ttf"]                      = { text = "Skurri",               font = "Fonts\\skurri.ttf" },
        }
        local fctFontOrder = {
            "default",
            FCT_FONT_DIR .. "Expressway.TTF",
            FCT_FONT_DIR .. "Avant Garde.ttf",
            FCT_FONT_DIR .. "Arial Bold.TTF",
            FCT_FONT_DIR .. "Poppins.ttf",
            FCT_FONT_DIR .. "FiraSans Medium.ttf",
            "---",
            FCT_FONT_DIR .. "Arial Narrow.ttf",
            FCT_FONT_DIR .. "Changa.ttf",
            FCT_FONT_DIR .. "Cinzel Decorative.ttf",
            FCT_FONT_DIR .. "Exo.otf",
            FCT_FONT_DIR .. "FiraSans Bold.ttf",
            FCT_FONT_DIR .. "FiraSans Light.ttf",
            FCT_FONT_DIR .. "Future X Black.otf",
            FCT_FONT_DIR .. "Gotham Narrow Ultra.otf",
            FCT_FONT_DIR .. "Gotham Narrow.otf",
            FCT_FONT_DIR .. "Russo One.ttf",
            FCT_FONT_DIR .. "Ubuntu.ttf",
            FCT_FONT_DIR .. "Homespun.ttf",
            "Fonts\\FRIZQT__.TTF",
            "Fonts\\ARIALN.TTF",
            "Fonts\\MORPHEUS.TTF",
            "Fonts\\skurri.ttf",
        }

        local showDmgRow
        showDmgRow, h = W:DualRow(parent, y,
            { type="toggle", text="Show Damage Text",
              getValue=function() return GetCVarBool("floatingCombatTextCombatDamage_v2") end,
              setValue=function(v)
                SetCVarSafe("floatingCombatTextCombatDamage_v2", v and "1" or "0")
                EllesmereUI:RefreshPage()
              end },
            { type="dropdown", text="Combat Text Font",
              tooltip="WARNING: This feature requires you to re-log or restart WoW to take effect.",
              tooltipOpts={ color={1, 0.3, 0.3} },
              values = fctFontValues, order = fctFontOrder,
              getValue=function()
                return (EllesmereUIDB and EllesmereUIDB.fctFont) or "default"
              end,
              setValue=function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                if v == "default" then
                    EllesmereUIDB.fctFont = nil
                else
                    EllesmereUIDB.fctFont = v
                end
                EllesmereUI:ShowConfirmPopup({
                    title   = "Logout Required",
                    message = "Combat text font changes require a logout to character select to take effect. This is a WoW engine limitation.",
                    confirmText = "Okay",
                    cancelText  = "Later",
                })
              end });  y = y - h

        -- Cog on Show Damage Text for Pet/Periodic Damage
        do
            local leftRgn = showDmgRow._leftRegion
            local function dmgTextOff()
                return not GetCVarBool("floatingCombatTextCombatDamage_v2")
            end

            local _, petDmgCogShow = EllesmereUI.BuildCogPopup({
                title = "Damage Text Settings",
                rows = {
                    { type="toggle", label="Show Pet/Periodic Damage",
                      get=function()
                        return GetCVarBool("floatingCombatTextCombatLogPeriodicSpells_v2")
                           and GetCVarBool("floatingCombatTextPetMeleeDamage_v2")
                           and GetCVarBool("floatingCombatTextPetSpellDamage_v2")
                      end,
                      set=function(v)
                        local val = v and "1" or "0"
                        SetCVarSafe("floatingCombatTextCombatLogPeriodicSpells_v2", val)
                        SetCVarSafe("floatingCombatTextPetMeleeDamage_v2", val)
                        SetCVarSafe("floatingCombatTextPetSpellDamage_v2", val)
                      end },
                },
            })
            local petDmgCogBtn = CreateFrame("Button", nil, leftRgn)
            petDmgCogBtn:SetSize(26, 26)
            petDmgCogBtn:SetPoint("RIGHT", leftRgn._control, "LEFT", -8, 0)
            leftRgn._lastInline = petDmgCogBtn
            petDmgCogBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
            petDmgCogBtn:SetAlpha(dmgTextOff() and 0.15 or 0.4)
            local petDmgCogTex = petDmgCogBtn:CreateTexture(nil, "OVERLAY")
            petDmgCogTex:SetAllPoints()
            petDmgCogTex:SetTexture(EllesmereUI.COGS_ICON)
            petDmgCogBtn:SetScript("OnEnter", function(self)
                if dmgTextOff() then
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Show Damage Text"))
                else
                    self:SetAlpha(0.7)
                end
            end)
            petDmgCogBtn:SetScript("OnLeave", function(self)
                EllesmereUI.HideWidgetTooltip()
                self:SetAlpha(dmgTextOff() and 0.15 or 0.4)
            end)
            petDmgCogBtn:SetScript("OnClick", function(self)
                if dmgTextOff() then return end
                petDmgCogShow(self)
            end)
            EllesmereUI.RegisterWidgetRefresh(function()
                petDmgCogBtn:SetAlpha(dmgTextOff() and 0.15 or 0.4)
            end)
        end

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -------------------------------------------------------------------
        --  DEVELOPER
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "DEVELOPER", y);  y = y - h

        _, h = W:DualRow(parent, y,
            { type="toggle", text="Show Lua Errors In Chat",
              getValue=function()
                return EllesmereUIDB and EllesmereUIDB.errorGrabber == true
              end,
              setValue=function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.errorGrabber = v
                if v then
                    EllesmereUI._enableErrorGrabber()
                    EllesmereUIDB.suppressErrors = false
                else
                    EllesmereUI._disableErrorGrabber()
                    EllesmereUIDB.suppressErrors = true
                    SetCVarSafe("scriptErrors", "0")
                end
                EllesmereUI:RefreshPage()
              end },
            { type="toggle", text="Play Sound on Lua Error",
              disabled=function()
                return not (EllesmereUIDB and EllesmereUIDB.errorGrabber == true)
              end,
              disabledTooltip="Show Lua Errors In Chat",
              getValue=function()
                return EllesmereUIDB and EllesmereUIDB.errorSound or false
              end,
              setValue=function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.errorSound = v
              end });  y = y - h

        _, h = W:DualRow(parent, y,
            { type="toggle", text="Suppress Lua Errors",
              disabled=function()
                return EllesmereUIDB and EllesmereUIDB.errorGrabber == true
              end,
              disabledTooltip="Show Lua Errors In Chat",
              getValue=function()
                return not (EllesmereUIDB and EllesmereUIDB.suppressErrors == false)
              end,
              setValue=function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.suppressErrors = v
                SetCVarSafe("scriptErrors", v and "0" or "1")
              end },
            { type="toggle", text="Show Spell ID on Tooltip",
              getValue=function()
                return EllesmereUIDB and EllesmereUIDB.showSpellID or false
              end,
              setValue=function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.showSpellID = v
              end });  y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -- Reset ALL EUI Addon Settings (wide warning button)
        y = y - 30  -- spacer
        do
            local BTN_W, BTN_H = 300, 38
            local lerp = EllesmereUI.lerp
            local DARK_BG = EllesmereUI.DARK_BG or { r = 0.05, g = 0.07, b = 0.09 }
            local btn = CreateFrame("Button", nil, parent)
            btn:SetSize(BTN_W, BTN_H)
            btn:SetPoint("TOP", parent, "TOP", 0, y)
            btn:SetFrameLevel(parent:GetFrameLevel() + 5)
            btn:SetAlpha(0.85)
            local brd = EllesmereUI.MakeBorder(btn, 0.8, 0.2, 0.2, 0.5, EllesmereUI.PanelPP)
            local bg = EllesmereUI.SolidTex(btn, "BACKGROUND", DARK_BG.r, DARK_BG.g, DARK_BG.b, 0.92)
            bg:SetAllPoints()
            local lbl = EllesmereUI.MakeFont(btn, 13, nil, 0.9, 0.3, 0.3)
            lbl:SetAlpha(0.7)
            lbl:SetPoint("CENTER")
            lbl:SetText("Reset ALL EUI Addon Settings")
            do
                local FADE_DUR = 0.1
                local progress, target = 0, 0
                local function Apply(t)
                    lbl:SetTextColor(lerp(0.9, 1, t), lerp(0.3, 0.35, t), lerp(0.3, 0.35, t), lerp(0.7, 1, t))
                    brd:SetColor(0.8, 0.2, 0.2, lerp(0.5, 0.8, t))
                end
                local function OnUpdate(self, elapsed)
                    local dir = (target == 1) and 1 or -1
                    progress = progress + dir * (elapsed / FADE_DUR)
                    if (dir == 1 and progress >= 1) or (dir == -1 and progress <= 0) then
                        progress = target; self:SetScript("OnUpdate", nil)
                    end
                    Apply(progress)
                end
                btn:SetScript("OnEnter", function(self) target = 1; self:SetScript("OnUpdate", OnUpdate) end)
                btn:SetScript("OnLeave", function(self) target = 0; self:SetScript("OnUpdate", OnUpdate) end)
            end
            btn:SetScript("OnClick", function()
                EllesmereUI:ShowConfirmPopup({
                    title       = "Reset ALL Settings",
                    message     = "Are you sure you want to reset ALL EUI addon settings to their defaults? This will reload your UI.",
                    disclaimer  = "This resets every EUI addon, not just the current one.",
                    confirmText = "Reset All & Reload",
                    cancelText  = "Cancel",
                    onConfirm   = function()
                        EllesmereUI:ResetAllModules()
                        ReloadUI()
                    end,
                })
            end)
            y = y - BTN_H
        end

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Quick Setup page  (curated quick-access to key settings per addon)
    --  Action Bars options are live; others are temporary placeholders
    --  until those addons register their core settings.
    ---------------------------------------------------------------------------
    local function BuildCoreOptionsPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        -------------------------------------------------------------------
        --  ACTION BARS
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "ACTION BARS", y);  y = y - h

        -- Access EAB through addon registry
        local EAB = EllesmereUI.Lite and EllesmereUI.Lite.GetAddon("EllesmereUIActionBars", true)
        local function EAB_db()
            if EAB and EAB.db then return EAB.db.profile end
            return nil
        end

        _, h = W:Toggle(parent, "Modern Icons", y,
            function()
                local db = EAB_db()
                return db and db.squareIcons or false
            end,
            function(v)
                local db = EAB_db()
                if not db then return end
                db.squareIcons = v
                EllesmereUI:ShowConfirmPopup({
                    title   = "Reload Required",
                    message = "Modern Icons requires a UI reload to apply.",
                    confirmText = "Reload Now",
                    cancelText  = "Later",
                    onConfirm = function() ReloadUI() end,
                })
            end);  y = y - h

        _, h = W:Slider(parent, "Icon Zoom", y, 0, 10, 0.5,
            function()
                local db = EAB_db()
                return db and (db.iconZoom or 5.5) or 5.5
            end,
            function(v)
                local db = EAB_db()
                if not db then return end
                db.iconZoom = v
                if EAB and EAB.ApplyBorders then
                    EAB:ApplyBorders()
                end
                if EAB and EAB.ApplyShapes then
                    EAB:ApplyShapes()
                end
            end);  y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -------------------------------------------------------------------
        --  NAMEPLATES
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "NAMEPLATES", y);  y = y - h

        _, h = W:Toggle(parent, "TEMPORARY", y,
            function() return false end,
            function(v) end);  y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -------------------------------------------------------------------
        --  UNIT FRAMES
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "UNIT FRAMES", y);  y = y - h

        _, h = W:Toggle(parent, "TEMPORARY", y,
            function() return false end,
            function(v) end);  y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -------------------------------------------------------------------
        --  BAR GLOWS
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "BAR GLOWS", y);  y = y - h

        _, h = W:Toggle(parent, "TEMPORARY", y,
            function() return false end,
            function(v) end);  y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -------------------------------------------------------------------
        --  CONSUMABLES
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "CONSUMABLES", y);  y = y - h

        _, h = W:Toggle(parent, "TEMPORARY", y,
            function() return false end,
            function(v) end);  y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -------------------------------------------------------------------
        --  CURSOR CIRCLE
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "CURSOR CIRCLE", y);  y = y - h

        _, h = W:Toggle(parent, "TEMPORARY", y,
            function() return false end,
            function(v) end);  y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -------------------------------------------------------------------
        --  BEACON REMINDERS
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "BEACON REMINDERS", y);  y = y - h

        _, h = W:Toggle(parent, "TEMPORARY", y,
            function() return false end,
            function(v) end);  y = y - h

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Re-read live CVar values every time the panel is opened.
    --  Widgets call their getter on each build, so a page rebuild is enough
    --  to pick up any CVar changes made externally (other addons, /console).
    ---------------------------------------------------------------------------
    EllesmereUI:RegisterOnShow(function()
        if EllesmereUI:GetActiveModule() == GLOBAL_KEY then
            EllesmereUI:RefreshPage()
        end
    end)

    ---------------------------------------------------------------------------
    --  Register the module
    ---------------------------------------------------------------------------

    ---------------------------------------------------------------------------
    --  Colors Page
    ---------------------------------------------------------------------------
    local CLASS_ORDER = {
        "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
        "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "MONK",
        "DRUID", "DEMONHUNTER", "EVOKER",
    }
    local CLASS_LABELS = {
        WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter",
        ROGUE = "Rogue", PRIEST = "Priest", DEATHKNIGHT = "Death Knight",
        SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock",
        MONK = "Monk", DRUID = "Druid", DEMONHUNTER = "Demon Hunter",
        EVOKER = "Evoker",
    }
    local POWER_LABELS = {
        MANA = "Mana", RAGE = "Rage", FOCUS = "Focus", ENERGY = "Energy",
        RUNIC_POWER = "Runic Power", LUNAR_POWER = "Lunar Power",
        INSANITY = "Insanity", MAELSTROM = "Maelstrom", FURY = "Fury",
        PAIN = "Pain",
    }
    local RESOURCE_LABELS = {
        ComboPoints = "Combo Points", HolyPower = "Holy Power",
        Chi = "Chi", SoulShards = "Soul Shards",
        ArcaneCharges = "Arcane Charges", Essence = "Essence",
        Runes = "Runes",
        SoulFragments = "Soul Fragments",
    }
    local GRADIENT_DIR_VALUES = {
        ["HORIZONTAL"] = "Left to Right",
        ["HORIZONTAL_REV"] = "Right to Left",
        ["VERTICAL"] = "Top to Bottom",
        ["VERTICAL_REV"] = "Bottom to Top",
    }
    local GRADIENT_DIR_ORDER = { "HORIZONTAL", "HORIZONTAL_REV", "VERTICAL", "VERTICAL_REV" }

    local function BuildColorsPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h
        local MakeFont = EllesmereUI.MakeFont
        local GetCustomColorsDB = EllesmereUI.GetCustomColorsDB
        local CLASS_COLOR_MAP = EllesmereUI.CLASS_COLOR_MAP
        local DEFAULT_POWER_COLORS = EllesmereUI.DEFAULT_POWER_COLORS
        local CONTENT_PAD = EllesmereUI.CONTENT_PAD or 20

        parent._showRowDivider = true

        -- Helper to save a color entry
        local function SaveColorEntry(category, key, data)
            local db = GetCustomColorsDB()
            if not db[category] then db[category] = {} end
            db[category][key] = data
            EllesmereUI.ApplyColorsToOUF()
        end

        -------------------------------------------------------------------
        --  Shared 4-column color grid builder
        -------------------------------------------------------------------
        local GRID_COLS     = 4
        local GRID_ROW_H    = 50
        local GRID_PAD      = CONTENT_PAD
        local GRID_SIDE_PAD = 20
        local SWATCH_SZ     = 20

        -- items = { { label, classToken, getColor, setColor, resetFn }, ... }
        local function BuildColorGrid(par, yPos, items)            local totalRows = math.ceil(#items / GRID_COLS)
            local totalW = par:GetWidth() - GRID_PAD * 2
            local colW = math.floor(totalW / GRID_COLS)

            for row = 0, totalRows - 1 do
                local rowFrame = CreateFrame("Frame", nil, par)
                PP.Size(rowFrame, totalW, GRID_ROW_H)
                PP.Point(rowFrame, "TOPLEFT", par, "TOPLEFT", GRID_PAD, yPos - row * GRID_ROW_H)
                rowFrame._skipRowDivider = true
                EllesmereUI.RowBg(rowFrame, par)

                -- Column dividers
                for d = 1, GRID_COLS - 1 do
                    local div = rowFrame:CreateTexture(nil, "ARTWORK")
                    div:SetColorTexture(1, 1, 1, 0.06)
                    if div.SetSnapToPixelGrid then div:SetSnapToPixelGrid(false); div:SetTexelSnappingBias(0) end
                    PP.Width(div, 1)
                    local xPos = d * colW
                    PP.Point(div, "TOP", rowFrame, "TOPLEFT", xPos, 0)
                    PP.Point(div, "BOTTOM", rowFrame, "BOTTOMLEFT", xPos, 0)
                end

                for col = 0, GRID_COLS - 1 do
                    local idx = row * GRID_COLS + col + 1
                    local item = items[idx]
                    if not item then break end

                    local cell = CreateFrame("Frame", nil, rowFrame)
                    cell:SetSize(colW, GRID_ROW_H)
                    cell:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", col * colW, 0)

                    -- Class-colored label (or white for power colors)
                    local cr, cg, cb = 1, 1, 1
                    if item.classToken then
                        local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[item.classToken]
                        if cc then cr, cg, cb = cc.r, cc.g, cc.b end
                    end
                    local label = MakeFont(cell, 13, nil, cr, cg, cb)
                    label:SetPoint("LEFT", cell, "LEFT", GRID_SIDE_PAD, 0)
                    label:SetText(item.label)

                    -- Color swatch (right side)
                    local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(cell, cell:GetFrameLevel() + 2,
                        function()
                            local c = item.getColor()
                            return c.r, c.g, c.b, 1
                        end,
                        function(r, g, b)
                            local c = item.getColor()
                            c.r = r; c.g = g; c.b = b
                            item.setColor(c)
                            local rl = EllesmereUI._widgetRefreshList
                            if rl then for i2 = 1, #rl do rl[i2]() end end
                        end, false, SWATCH_SZ)
                    swatch:SetPoint("RIGHT", cell, "RIGHT", -GRID_SIDE_PAD, 0)

                    -- Undo (reset) button
                    local undoBtn = CreateFrame("Button", nil, cell)
                    undoBtn:SetSize(18, 18)
                    undoBtn:SetPoint("RIGHT", swatch, "LEFT", -10, 0)
                    undoBtn:SetFrameLevel(cell:GetFrameLevel() + 3)
                    undoBtn:SetAlpha(0.3)
                    local undoTex = undoBtn:CreateTexture(nil, "ARTWORK")
                    undoTex:SetAllPoints()
                    undoTex:SetTexture(EllesmereUI.UNDO_ICON)
                    undoBtn:SetScript("OnEnter", function(self)
                        self:SetAlpha(0.6)
                        EllesmereUI.ShowWidgetTooltip(self, "Reset to default")
                    end)
                    undoBtn:SetScript("OnLeave", function(self)
                        self:SetAlpha(0.3)
                        EllesmereUI.HideWidgetTooltip()
                    end)
                    undoBtn:SetScript("OnClick", function()
                        item.resetFn()
                        EllesmereUI.ApplyColorsToOUF()
                        updateSwatch()
                        local rl = EllesmereUI._widgetRefreshList
                        if rl then for i2 = 1, #rl do rl[i2]() end end
                    end)
                end
            end

            return totalRows * GRID_ROW_H
        end

        -------------------------------------------------------------------
        --  FONTS section
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "FONTS", y);  y = y - h

        -- For locales that require system fonts (CJK, Cyrillic), the font
        -- selection dropdowns are not applicable — the system font is used
        -- automatically regardless of what is selected here.
        if EllesmereUI.LOCALE_FONT_FALLBACK then
            local noticeFrame = CreateFrame("Frame", nil, parent)
            local totalW = parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2
            PP.Size(noticeFrame, totalW, 70)
            PP.Point(noticeFrame, "TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD, y)
            EllesmereUI.RowBg(noticeFrame, parent)

            local icon = noticeFrame:CreateTexture(nil, "ARTWORK")
            icon:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertOther")
            PP.Size(icon, 24, 24)
            PP.Point(icon, "LEFT", noticeFrame, "LEFT", 16, 0)
            icon:SetVertexColor(EllesmereUI.ELLESMERE_GREEN.r, EllesmereUI.ELLESMERE_GREEN.g, EllesmereUI.ELLESMERE_GREEN.b)

            local msg = noticeFrame:CreateFontString(nil, "OVERLAY")
            msg:SetFont(EllesmereUI.EXPRESSWAY, 13, EllesmereUI.GetFontOutlineFlag())
            msg:SetTextColor(1, 1, 1, 0.75)
            msg:SetJustifyH("LEFT")
            msg:SetPoint("LEFT", icon, "RIGHT", 12, 4)
            msg:SetPoint("RIGHT", noticeFrame, "RIGHT", -16, 0)
            msg:SetText("Your game client language uses a system font automatically.\nFont selection is not available for this locale.")

            y = y - 70
            return math.abs(y)
        end

        local fontDropValues = {}
        local fontDropOrder  = {}
        local FONT_DIR_GLOBAL = EllesmereUI.MEDIA_PATH .. "fonts\\"
        for _, name in ipairs(EllesmereUI.FONT_ORDER) do
            if name == "---" then
                fontDropOrder[#fontDropOrder + 1] = "---"
            else
                local path = EllesmereUI.FONT_BLIZZARD[name]
                    or (FONT_DIR_GLOBAL .. (EllesmereUI.FONT_FILES[name] or "Expressway.TTF"))
                fontDropValues[name] = { text = name, font = path }
                fontDropOrder[#fontDropOrder + 1] = name
            end
        end

        -- Reload popup for font changes
        local function FontReload()
            EllesmereUI:ShowConfirmPopup({
                title       = "Reload Required",
                message     = "Font changed. A UI reload is needed to apply the new font.",
                confirmText = "Reload Now",
                cancelText  = "Later",
                onConfirm   = function() ReloadUI() end,
            })
        end

        local outlineModeValues = {}
        local outlineModeOrder = EllesmereUI.FONT_OUTLINE_MODE_ORDER or { "shadow", "outline", "thick" }
        for _, modeKey in ipairs(outlineModeOrder) do
            local modeInfo = EllesmereUI.FONT_OUTLINE_MODES and EllesmereUI.FONT_OUTLINE_MODES[modeKey]
            outlineModeValues[modeKey] = { text = (modeInfo and modeInfo.text) or modeKey }
        end

        _, h = W:DualRow(parent, y,
            { type="dropdown", text="Global Font",
              values=fontDropValues, order=fontDropOrder,
              getValue=function() return EllesmereUI.GetFontsDB().global or "Expressway" end,
              setValue=function(v)
                  EllesmereUI.GetFontsDB().global = v
                  local rl = EllesmereUI._widgetRefreshList
                  if rl then for i2 = 1, #rl do rl[i2]() end end
                  FontReload()
              end },
            { type="dropdown", text="Outline Mode",
              tooltip="Controls the text rendering style used across all UI elements",
              values=outlineModeValues, order=outlineModeOrder,
              getValue=function()
                  local outlineMode = EllesmereUI.GetFontsDB().outlineMode
                  if EllesmereUI.NormalizeFontOutlineMode then
                      return EllesmereUI.NormalizeFontOutlineMode(outlineMode)
                  end
                  return outlineMode or "shadow"
              end,
              setValue=function(v)
                  EllesmereUI.GetFontsDB().outlineMode = v
                  local rl = EllesmereUI._widgetRefreshList
                  if rl then for i2 = 1, #rl do rl[i2]() end end
                  FontReload()
              end });  y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -------------------------------------------------------------------
        --  CLASS COLORS section
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "CLASS COLORS", y);  y = y - h

        local classItems = {}
        for _, token in ipairs(CLASS_ORDER) do
            local lbl = CLASS_LABELS[token]
            local def = CLASS_COLOR_MAP[token] or { r = 1, g = 1, b = 1 }
            classItems[#classItems + 1] = {
                label = lbl,
                classToken = token,
                getColor = function()
                    local db = GetCustomColorsDB()
                    if db.class and db.class[token] then return db.class[token] end
                    return { r = def.r, g = def.g, b = def.b }
                end,
                setColor = function(c)
                    SaveColorEntry("class", token, c)
                end,
                resetFn = function()
                    local db = GetCustomColorsDB()
                    if db.class then db.class[token] = nil end
                end,
            }
        end

        h = BuildColorGrid(parent, y, classItems)
        y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -------------------------------------------------------------------
        --  POWER COLORS section
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "POWER COLORS", y);  y = y - h

        local POWER_ORDER = { "MANA", "RAGE", "FOCUS", "ENERGY", "RUNIC_POWER", "FURY" }
        local powerItems = {}
        for _, pk in ipairs(POWER_ORDER) do
            local lbl = POWER_LABELS[pk] or pk
            local def = DEFAULT_POWER_COLORS[pk] or { r = 1, g = 1, b = 1 }
            powerItems[#powerItems + 1] = {
                label = lbl,
                classToken = nil,
                getColor = function()
                    local db = GetCustomColorsDB()
                    if db.power and db.power[pk] then return db.power[pk] end
                    return { r = def.r, g = def.g, b = def.b }
                end,
                setColor = function(c)
                    SaveColorEntry("power", pk, c)
                end,
                resetFn = function()
                    EllesmereUI.ResetPowerColor(pk)
                end,
            }
        end

        h = BuildColorGrid(parent, y, powerItems)
        y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h

        return math.abs(y)
    end


    ---------------------------------------------------------------------------
    --  Runtime: FPS Counter (Extras)
    ---------------------------------------------------------------------------
    -- Guard: only one addon copy creates these runtime frames
    if not _G["EUI_ExtrasRuntimeInit"] then
    _G["EUI_ExtrasRuntimeInit"] = true

    local fpsFrame
    local function CreateFPSCounter()
        if fpsFrame then return end
        local FONT = EllesmereUI.GetFontPath("extras")
        local FONT_SIZE = 12
        local LABEL_SIZE = FONT_SIZE - 2
        local SHADOW_X, SHADOW_Y = 1, -1
        fpsFrame = CreateFrame("Frame", "EUI_FPSCounter", UIParent)
        fpsFrame:SetSize(60, 20)
        fpsFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 10, -10)
        fpsFrame:SetFrameStrata("HIGH")
        fpsFrame:SetFrameLevel(100)
        fpsFrame:EnableMouse(false)

        local function MakeFS(size)
            local f = fpsFrame:CreateFontString(nil, "OVERLAY")
            f:SetFont(FONT, size, EllesmereUI.GetFontOutlineFlag())
            if EllesmereUI.GetFontUseShadow() then f:SetShadowOffset(SHADOW_X, SHADOW_Y) else f:SetShadowOffset(0, 0) end
            f:SetTextColor(1, 1, 1, 1)
            return f
        end

        local fsFps = MakeFS(FONT_SIZE)
        fsFps:SetPoint("LEFT")
        fpsFrame._text = fsFps

        -- Divider helper
        local DIV_W, DIV_H = 1, 10
        local DIV_PAD = 6

        local function MakeDivider()
            local d = fpsFrame:CreateTexture(nil, "OVERLAY")
            d:SetColorTexture(1, 1, 1, 0.25)
            d:SetSize(DIV_W, DIV_H)
            return d
        end

        local divWorld = MakeDivider()
        local fsWorldVal = MakeFS(FONT_SIZE)
        local fsWorldLbl = MakeFS(LABEL_SIZE)
        fpsFrame._divWorld = divWorld
        fpsFrame._textWorld = fsWorldVal

        local divLocal = MakeDivider()
        local fsLocalVal = MakeFS(FONT_SIZE)
        local fsLocalLbl = MakeFS(LABEL_SIZE)
        fpsFrame._divLocal = divLocal
        fpsFrame._textLocal = fsLocalVal

        local function UpdateFPS(self)
            local db = EllesmereUIDB or {}
            local c = db.fpsColor
            local cr, cg, cb, ca = 1, 1, 1, 1
            if c then cr, cg, cb, ca = c.r or 1, c.g or 1, c.b or 1, c.a or 1 end
            fsFps:SetTextColor(cr, cg, cb, ca)
            fsWorldVal:SetTextColor(cr, cg, cb, ca)
            fsWorldLbl:SetTextColor(cr, cg, cb, ca * 0.6)
            fsLocalVal:SetTextColor(cr, cg, cb, ca)
            fsLocalLbl:SetTextColor(cr, cg, cb, ca * 0.6)
            divWorld:SetColorTexture(cr, cg, cb, ca * 0.35)
            divLocal:SetColorTexture(cr, cg, cb, ca * 0.35)

            local fps = floor(GetFramerate() + 0.5)
            fsFps:SetText(fps .. " fps")

            local showWorld = db.fpsShowWorldMS
            local showLocal = (db.fpsShowLocalMS == nil) and true or db.fpsShowLocalMS
            local _, _, latHome, latWorld = GetNetStats()

            -- Layout: [FPS] [div] [world ms (world)] [div] [local ms (local)]
            fsFps:ClearAllPoints()
            fsFps:SetPoint("LEFT", fpsFrame, "LEFT", 0, 0)
            local anchor = fsFps

            if showWorld then
                fsWorldVal:SetText(latWorld .. " ms")
                fsWorldLbl:SetText("(world)")
                divWorld:ClearAllPoints()
                divWorld:SetPoint("LEFT", anchor, "RIGHT", DIV_PAD, 0)
                divWorld:Show()
                fsWorldVal:ClearAllPoints()
                fsWorldVal:SetPoint("LEFT", divWorld, "RIGHT", DIV_PAD, 0)
                fsWorldVal:Show()
                fsWorldLbl:ClearAllPoints()
                fsWorldLbl:SetPoint("LEFT", fsWorldVal, "RIGHT", 3, 0)
                fsWorldLbl:Show()
                anchor = fsWorldLbl
            else
                divWorld:Hide(); fsWorldVal:Hide(); fsWorldLbl:Hide()
            end

            if showLocal then
                fsLocalVal:SetText(latHome .. " ms")
                fsLocalLbl:SetText("(local)")
                divLocal:ClearAllPoints()
                divLocal:SetPoint("LEFT", anchor, "RIGHT", DIV_PAD, 0)
                divLocal:Show()
                fsLocalVal:ClearAllPoints()
                fsLocalVal:SetPoint("LEFT", divLocal, "RIGHT", DIV_PAD, 0)
                fsLocalVal:Show()
                fsLocalLbl:ClearAllPoints()
                fsLocalLbl:SetPoint("LEFT", fsLocalVal, "RIGHT", 3, 0)
                fsLocalLbl:Show()
                anchor = fsLocalLbl
            else
                divLocal:Hide(); fsLocalVal:Hide(); fsLocalLbl:Hide()
            end

            -- Resize frame to fit content
            local totalW = fsFps:GetStringWidth()
            if showWorld then totalW = totalW + DIV_PAD + DIV_W + DIV_PAD + fsWorldVal:GetStringWidth() + 3 + fsWorldLbl:GetStringWidth() end
            if showLocal then totalW = totalW + DIV_PAD + DIV_W + DIV_PAD + fsLocalVal:GetStringWidth() + 3 + fsLocalLbl:GetStringWidth() end
            self:SetSize(totalW + 4, 20)
        end

        local elapsed = 0
        fpsFrame:SetScript("OnUpdate", function(self, dt)
            elapsed = elapsed + dt
            if elapsed < 1 then return end
            elapsed = 0
            UpdateFPS(self)
        end)
        fpsFrame._updateNow = function() elapsed = 0; UpdateFPS(fpsFrame) end
        fpsFrame:Hide()
    end

    EllesmereUI._applyFPSCounter = function()
        local shouldShow = EllesmereUIDB and EllesmereUIDB.showFPS
        if shouldShow then
            CreateFPSCounter()
            -- Apply saved position and scale
            local pos = EllesmereUIDB and EllesmereUIDB.fpsPos
            if pos and pos.point then
                if pos.scale then pcall(function() fpsFrame:SetScale(pos.scale) end) end
                fpsFrame:ClearAllPoints()
                fpsFrame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
            end
            fpsFrame._updateNow()
            fpsFrame:Show()
        elseif fpsFrame then
            fpsFrame:Hide()
        end
    end

    -- Register FPS counter as an unlock mode element
    C_Timer.After(1.5, function()
        if not EllesmereUI or not EllesmereUI.RegisterUnlockElements then return end
        EllesmereUI:RegisterUnlockElements({
            {
                key = "EUI_FPS",
                label = "FPS Counter",
                order = 700,
                getFrame = function()
                    if not fpsFrame then CreateFPSCounter() end
                    return fpsFrame
                end,
                getSize = function()
                    if fpsFrame then return fpsFrame:GetWidth(), fpsFrame:GetHeight() end
                    return 80, 20
                end,
                savePosition = function(key, point, relPoint, x, y, scale)
                    if not EllesmereUIDB then EllesmereUIDB = {} end
                    if not point then return end
                    EllesmereUIDB.fpsPos = { point = point, relPoint = relPoint, x = x, y = y, scale = scale }
                    if fpsFrame then
                        if scale then pcall(function() fpsFrame:SetScale(scale) end) end
                        fpsFrame:ClearAllPoints()
                        fpsFrame:SetPoint(point, UIParent, relPoint or point, x or 0, y or 0)
                    end
                end,
                loadPosition = function()
                    return EllesmereUIDB and EllesmereUIDB.fpsPos
                end,
                getScale = function()
                    local pos = EllesmereUIDB and EllesmereUIDB.fpsPos
                    return pos and pos.scale or 1.0
                end,
                clearPosition = function()
                    if EllesmereUIDB then EllesmereUIDB.fpsPos = nil end
                end,
                applyPosition = function()
                    if not fpsFrame then return end
                    local pos = EllesmereUIDB and EllesmereUIDB.fpsPos
                    if pos and pos.point then
                        if pos.scale then pcall(function() fpsFrame:SetScale(pos.scale) end) end
                        fpsFrame:ClearAllPoints()
                        fpsFrame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
                    end
                end,
            },
        })
    end)

    -- Register Secondary Stats as an unlock mode element
    C_Timer.After(1.5, function()
        if not EllesmereUI or not EllesmereUI.RegisterUnlockElements then return end
        EllesmereUI:RegisterUnlockElements({
            {
                key = "EUI_SecondaryStats",
                label = "Secondary Stats",
                order = 710,
                getFrame = function()
                    local f = EllesmereUI._getSecondaryStatsFrame and EllesmereUI._getSecondaryStatsFrame()
                    return f
                end,
                getSize = function()
                    local f = EllesmereUI._getSecondaryStatsFrame and EllesmereUI._getSecondaryStatsFrame()
                    if f then return f:GetWidth(), f:GetHeight() end
                    return 160, 60
                end,
                savePosition = function(key, point, relPoint, x, y, scale)
                    if not EllesmereUIDB then EllesmereUIDB = {} end
                    if not point then
                        -- No position to save (element was never positioned)
                        return
                    end
                    EllesmereUIDB.secondaryStatsPos = { point = point, relPoint = relPoint, x = x, y = y, scale = scale }
                    local f = EllesmereUI._getSecondaryStatsFrame and EllesmereUI._getSecondaryStatsFrame()
                    if f then
                        if scale then pcall(function() f:SetScale(scale) end) end
                        f:ClearAllPoints()
                        f:SetPoint(point, UIParent, relPoint or point, x or 0, y or 0)
                    end
                end,
                loadPosition = function()
                    return EllesmereUIDB and EllesmereUIDB.secondaryStatsPos
                end,
                getScale = function()
                    local pos = EllesmereUIDB and EllesmereUIDB.secondaryStatsPos
                    return pos and pos.scale or 1.0
                end,
                clearPosition = function()
                    if EllesmereUIDB then EllesmereUIDB.secondaryStatsPos = nil end
                end,
                applyPosition = function()
                    local f = EllesmereUI._getSecondaryStatsFrame and EllesmereUI._getSecondaryStatsFrame()
                    if not f then return end
                    local pos = EllesmereUIDB and EllesmereUIDB.secondaryStatsPos
                    if pos and pos.point then
                        if pos.scale then pcall(function() f:SetScale(pos.scale) end) end
                        f:ClearAllPoints()
                        f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
                    end
                end,
            },
        })
    end)

    -- Hidden button for FPS keybind toggle
    local fpsBind = CreateFrame("Button", "EUI_FPSBindBtn", UIParent)
    fpsBind:Hide()
    fpsBind:SetScript("OnClick", function()
        if not EllesmereUIDB then EllesmereUIDB = {} end
        EllesmereUIDB.showFPS = not EllesmereUIDB.showFPS
        if EllesmereUI._applyFPSCounter then EllesmereUI._applyFPSCounter() end
    end)

    -- Apply on login
    C_Timer.After(1, function()
        if EllesmereUIDB and EllesmereUIDB.showFPS then
            EllesmereUI._applyFPSCounter()
        end
        -- Restore FPS keybind (protected — must wait for combat to drop)
        local function ApplyFPSBind()
            if EllesmereUIDB and EllesmereUIDB.fpsToggleKey then
                SetOverrideBindingClick(fpsBind, true, EllesmereUIDB.fpsToggleKey, "EUI_FPSBindBtn")
            end
        end
        if InCombatLockdown() then
            local w = CreateFrame("Frame")
            w:RegisterEvent("PLAYER_REGEN_ENABLED")
            w:SetScript("OnEvent", function(self)
                self:UnregisterAllEvents()
                ApplyFPSBind()
            end)
        else
            ApplyFPSBind()
        end
    end)

    ---------------------------------------------------------------------------
    --  Runtime: Auto Sell Junk + Auto Repair + Repair Warning
    ---------------------------------------------------------------------------
    local merchantFrame = CreateFrame("Frame", "EUI_MerchantHandler", UIParent)
    merchantFrame:RegisterEvent("MERCHANT_SHOW")
    merchantFrame:SetScript("OnEvent", function()
        if not EllesmereUIDB then return end

        -- Auto sell junk
        if EllesmereUIDB.autoSellJunk then
            local soldCount = 0
            for bag = 0, 4 do
                for slot = 1, C_Container.GetContainerNumSlots(bag) do
                    local info = C_Container.GetContainerItemInfo(bag, slot)
                    if info and info.quality == Enum.ItemQuality.Poor and not info.hasNoValue then
                        C_Container.UseContainerItem(bag, slot)
                        soldCount = soldCount + 1
                    end
                end
            end
            if soldCount > 0 then
                print("|cff0CD29DEllesmereUI:|r Sold " .. soldCount .. " junk item" .. (soldCount > 1 and "s" or "") .. ".")
            end
        end

        -- Auto repair
        if EllesmereUIDB.autoRepair ~= false then
            if CanMerchantRepair() then
                local cost, canRepair = GetRepairAllCost()
                if canRepair and cost > 0 then
                    local useGuild = IsInGuild() and CanGuildBankRepair() and cost <= GetGuildBankWithdrawMoney()
                    RepairAllItems(useGuild)

                    -- If guild repair was used, follow up with personal gold for any remainder
                    if useGuild then
                        C_Timer.After(0.5, function()
                            local remainCost, stillNeed = GetRepairAllCost()
                            if stillNeed and remainCost > 0 then
                                RepairAllItems(false)
                            end
                        end)
                    end

                    local gold = floor(cost / 10000)
                    local silver = floor((cost % 10000) / 100)
                    local src = useGuild and " (guild bank)" or ""
                    print("|cff0CD29DEllesmereUI:|r Repaired all items for " .. gold .. "g " .. silver .. "s." .. src)
                end
            end
        end
    end)

    ---------------------------------------------------------------------------
    --  Runtime: Durability Warning (flashing on-screen text)
    ---------------------------------------------------------------------------
    local durWarnOverlay
    local function CreateDurabilityWarning()
        if durWarnOverlay then return end

        durWarnOverlay = CreateFrame("Frame", "EUI_DurabilityWarning", UIParent)
        durWarnOverlay:SetSize(400, 40)
        durWarnOverlay:SetFrameStrata("DIALOG")
        durWarnOverlay:SetFrameLevel(500)
        durWarnOverlay:EnableMouse(false)

        local fs = durWarnOverlay:CreateFontString(nil, "OVERLAY")
        fs:SetFont(EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 18, EllesmereUI.GetFontOutlineFlag())
        fs:SetPoint("CENTER")
        fs:SetText("Low Durability")
        durWarnOverlay._text = fs

        -- Apply font, color, position, scale from saved settings
        local function ApplySettings()
            durWarnOverlay:ClearAllPoints()
            local pos = EllesmereUIDB and EllesmereUIDB.durWarnPos
            if pos and pos.point then
                durWarnOverlay:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 250)
            else
                local yOff = EllesmereUIDB and EllesmereUIDB.durWarnYOffset or 250
                durWarnOverlay:SetPoint("CENTER", UIParent, "CENTER", 0, yOff)
            end
            local scale = (EllesmereUIDB and EllesmereUIDB.durWarnScale or 100) / 100
            durWarnOverlay:SetScale(scale)

            -- Font — pull from the global "extras" font key
            local fontPath = EllesmereUI.GetFontPath("extras")
            fs:SetFont(fontPath, 18, EllesmereUI.GetFontOutlineFlag())

            -- Color
            local c = EllesmereUIDB and EllesmereUIDB.durWarnColor
            if c then
                fs:SetTextColor(c.r, c.g, c.b, 1)
            else
                fs:SetTextColor(1, 0.27, 0.27, 1)
            end
        end
        durWarnOverlay._applySettings = ApplySettings

        -- Engine-level pulse animation (no Lua OnUpdate)
        local ag = fs:CreateAnimationGroup()
        local fadeOut = ag:CreateAnimation("Alpha")
        fadeOut:SetFromAlpha(1)
        fadeOut:SetToAlpha(0.3)
        fadeOut:SetDuration(0.4)
        fadeOut:SetOrder(1)
        local fadeIn = ag:CreateAnimation("Alpha")
        fadeIn:SetFromAlpha(0.3)
        fadeIn:SetToAlpha(1)
        fadeIn:SetDuration(0.4)
        fadeIn:SetOrder(2)
        ag:SetLooping("REPEAT")

        durWarnOverlay._show = function(pct)
            ApplySettings()
            durWarnOverlay._text:SetText("Low Durability (" .. math.floor(pct) .. "%)")
            durWarnOverlay:Show()
            ag:Play()
        end

        durWarnOverlay:SetScript("OnHide", function()
            ag:Stop()
        end)

        durWarnOverlay:Hide()
    end

    EllesmereUI._applyDurWarn = function()
        CreateDurabilityWarning()
        durWarnOverlay._applySettings()
    end

    -- Preview: show durability warning at its configured position
    EllesmereUI._durWarnPreview = function()
        CreateDurabilityWarning()
        durWarnOverlay._show(25)  -- show with fake 25% for preview (includes ApplySettings)
        durWarnOverlay._text:SetText("Low Durability (Preview)")
    end

    EllesmereUI._durWarnHidePreview = function()
        if durWarnOverlay then durWarnOverlay:Hide() end
    end

    -- Durability warning: show while out of combat and below threshold, hide on repair or combat
    local repairWarnFrame = CreateFrame("Frame", "EUI_RepairWarnHandler", UIParent)
    repairWarnFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    repairWarnFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    repairWarnFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    repairWarnFrame:RegisterEvent("UPDATE_INVENTORY_DURABILITY")

    local function CheckDurabilityAndShow()
        if not EllesmereUIDB then return end
        if EllesmereUIDB.repairWarning == false then
            if durWarnOverlay then durWarnOverlay:Hide() end
            return
        end
        if InCombatLockdown() then return end

        local lowestDur = 100
        for slot = 1, 18 do
            local cur, mx = GetInventoryItemDurability(slot)
            if cur and mx and mx > 0 then
                local pct = (cur / mx) * 100
                if pct < lowestDur then lowestDur = pct end
            end
        end

        if lowestDur < (EllesmereUIDB.durWarnThreshold or 40) then
            CreateDurabilityWarning()
            durWarnOverlay._show(lowestDur)
        elseif durWarnOverlay then
            durWarnOverlay:Hide()
        end
    end

    repairWarnFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            -- Entering combat: hide warning
            if durWarnOverlay then durWarnOverlay:Hide() end
            return
        end
        -- PLAYER_REGEN_ENABLED, PLAYER_ENTERING_WORLD, UPDATE_INVENTORY_DURABILITY
        CheckDurabilityAndShow()
    end)

    ---------------------------------------------------------------------------
    --  Runtime: Blizzard UI Scale (UIParent:SetScale)
    --  100% = default (no change). We multiply the system's base scale.
    --  Counter-scale our panel so it stays visually identical.
    ---------------------------------------------------------------------------
    do
        local baseUIScale       -- captured once at login (Blizzard default)

        local function ApplyBlizzUIScale()
            if not baseUIScale then
                baseUIScale = UIParent:GetScale()
            end
            local pct = EllesmereUIDB and EllesmereUIDB.blizzUIScale or 100
            -- Scale proportionally from the Blizzard default.
            -- 100% = baseUIScale (no change), 50% = half, 115% = 15% larger.
            local newScale = baseUIScale * (pct / 100)
            -- Snapshot our panel's current effective scale before changing UIParent
            local mf = EllesmereUI._mainFrame
            local panelScaleBefore
            if mf then
                panelScaleBefore = mf:GetEffectiveScale()
            end
            UIParent:SetScale(newScale)
            -- Counter-scale: keep our panel at the same effective scale
            if mf and panelScaleBefore then
                local newParentEffective = UIParent:GetEffectiveScale()
                if newParentEffective > 0 then
                    mf:SetScale(panelScaleBefore / newParentEffective)
                end
            end
        end

        EllesmereUI._applyBlizzUIScale = ApplyBlizzUIScale

        local blizzScaleFrame = CreateFrame("Frame")
        blizzScaleFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        blizzScaleFrame:SetScript("OnEvent", function(self)
            self:UnregisterEvent("PLAYER_ENTERING_WORLD")
            baseUIScale = UIParent:GetScale()
            local pct = EllesmereUIDB and EllesmereUIDB.blizzUIScale or 100
            if pct ~= 100 then
                ApplyBlizzUIScale()
            end
        end)
    end

    ---------------------------------------------------------------------------
    --  Runtime: Disable Right Click Targeting
    ---------------------------------------------------------------------------
    do
        local mlookBtn = CreateFrame("Button", "EUI_MouseLookBtn", UIParent)
        mlookBtn:RegisterForClicks("AnyDown", "AnyUp")
        mlookBtn:SetScript("OnClick", function(_, _, down)
            if down then MouselookStart() else MouselookStop() end
        end)

        local stateFrame = CreateFrame("Frame", "EUI_NoRightClickState", UIParent, "SecureHandlerStateTemplate")

        local function ApplyRightClickTarget()
            if InCombatLockdown() then
                -- Defer until combat ends
                local deferFrame = CreateFrame("Frame")
                deferFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
                deferFrame:SetScript("OnEvent", function(self)
                    self:UnregisterAllEvents()
                    ApplyRightClickTarget()
                end)
                return
            end
            if EllesmereUIDB and EllesmereUIDB.disableRightClickTarget then
                SecureStateDriverManager:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
                -- Only block right-click on living hostile units so NPCs,
                -- quest givers, objects, and corpses remain interactable.
                RegisterStateDriver(stateFrame, "mov", "[@mouseover,harm,nodead]1;0")
                stateFrame:SetAttribute("_onstate-mov", [[
                    if newstate == 1 then
                        self:SetBindingClick(1, "BUTTON2", "EUI_MouseLookBtn")
                    else
                        self:ClearBindings()
                    end
                ]])
            else
                UnregisterStateDriver(stateFrame, "mov")
                ClearOverrideBindings(stateFrame)
            end
        end

        EllesmereUI._applyRightClickTarget = ApplyRightClickTarget

        local rcInitFrame = CreateFrame("Frame")
        rcInitFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        rcInitFrame:SetScript("OnEvent", function(self)
            self:UnregisterEvent("PLAYER_ENTERING_WORLD")
            ApplyRightClickTarget()
        end)
    end

    end  -- EUI_ExtrasRuntimeInit guard

    ---------------------------------------------------------------------------
    --  Profiles page
    ---------------------------------------------------------------------------
    local function BuildProfilesPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h
        local FONT = EllesmereUI.EXPRESSWAY
        local EG = EllesmereUI.ELLESMERE_GREEN
        local ADDON_DB_MAP = EllesmereUI._ADDON_DB_MAP
        local PROFILE_NAME_MAX = EllesmereUI.PROFILE_NAME_MAX_LENGTH or 60
        local currentScope = EllesmereUI.GetCurrentProfileScopeDetails
            and EllesmereUI.GetCurrentProfileScopeDetails()
            or {
                includedDisplays = {},
                missingDisplays = {},
            }
        local includedAddonsText = (#currentScope.includedDisplays > 0)
            and table.concat(currentScope.includedDisplays, ", ")
            or "none"
        local missingAddonsText = (#currentScope.missingDisplays > 0)
            and table.concat(currentScope.missingDisplays, ", ")
            or nil

        parent._showRowDivider = false

        _, h = W:Spacer(parent, y, 10);  y = y - h

        local ddLabel
        local dirtyStateLabel
        local activeProfileNote
        local PROFILE_APPLY_NOTE = "Save updates this profile with your current settings. Revert goes back to the last saved version. Switching or importing a profile also saves your current settings first."

        local function RefreshActiveProfileDisplay()
            local activeName = EllesmereUI.GetActiveProfileName()
            local activeDisplayName = activeName or "No saved profile"
            local dirtyState = EllesmereUI.GetActiveProfileDirtyState
                and EllesmereUI.GetActiveProfileDirtyState()
                or { isDirty = false }

            if ddLabel then
                ddLabel:SetText(dirtyState.isDirty and (activeDisplayName .. " *") or activeDisplayName)
            end

            if dirtyStateLabel then
                if dirtyState.comparisonFailed or dirtyState.hasStoredProfile == false then
                    dirtyStateLabel:SetText("")
                elseif dirtyState.isDirty then
                    dirtyStateLabel:SetText("Unsaved changes")
                    dirtyStateLabel:SetTextColor(1.0, 0.84, 0.35, 0.95)
                    dirtyStateLabel:SetAlpha(0.95)
                else
                    dirtyStateLabel:SetText("All changes saved")
                    dirtyStateLabel:SetTextColor(1, 1, 1, 0.45)
                    dirtyStateLabel:SetAlpha(0.75)
                end
            end

            if activeProfileNote then
                activeProfileNote:SetText(PROFILE_APPLY_NOTE)
            end
        end

        local function RefreshProfilesPage()
            RefreshActiveProfileDisplay()
            EllesmereUI:InvalidatePageCache()
            EllesmereUI:RefreshPage(true)
        end

        local function FinishProfileAction(result)
            RefreshActiveProfileDisplay()
            if result and result.requiresReload then
                ReloadUI()
                return
            end
            RefreshProfilesPage()
        end

        local function ShowProfileError(title, message)
            EllesmereUI:ShowInfoPopup({
                title = title,
                content = message or "Unknown error.",
            })
        end

        local function ShowNamePrompt(opts)
            EllesmereUI:ShowInputPopup({
                title = opts.title,
                message = opts.message,
                placeholder = opts.placeholder,
                initialText = opts.initialText,
                confirmText = opts.confirmText,
                cancelText = opts.cancelText or "Cancel",
                maxLetters = PROFILE_NAME_MAX,
                onConfirm = opts.onConfirm,
            })
        end

        local function PromptOverwrite(opts)
            EllesmereUI:ShowConfirmPopup({
                title = opts.title or "Overwrite Profile",
                message = opts.message,
                confirmText = opts.confirmText or "Overwrite",
                cancelText = opts.cancelText or "Cancel",
                onConfirm = opts.onConfirm,
            })
        end

        local function TryCreateProfile(name, allowOverwrite)
            local ok, resultOrErr, code = EllesmereUI.SaveCurrentAsProfile(name, {
                allowOverwrite = allowOverwrite,
            })
            if ok then
                FinishProfileAction(resultOrErr)
            elseif code == "profile_exists" and not allowOverwrite then
                PromptOverwrite({
                    title = "Overwrite Profile",
                    message = "A profile named \"" .. name .. "\" already exists. Replace it with your current settings?",
                    onConfirm = function()
                        TryCreateProfile(name, true)
                    end,
                })
            else
                ShowProfileError("Create Profile", resultOrErr)
            end
        end

        local function TryRenameProfile(oldName, newName, allowOverwrite)
            local ok, resultOrErr, code = EllesmereUI.RenameProfile(oldName, newName, {
                allowOverwrite = allowOverwrite,
            })
            if ok then
                FinishProfileAction(resultOrErr)
            elseif code == "profile_exists" and not allowOverwrite then
                PromptOverwrite({
                    title = "Overwrite Profile",
                    message = "A profile named \"" .. newName .. "\" already exists. Replace it with the renamed profile?",
                    onConfirm = function()
                        TryRenameProfile(oldName, newName, true)
                    end,
                })
            else
                ShowProfileError("Rename Profile", resultOrErr)
            end
        end

        local function FormatAddonDisplayList(folderList)
            local displayNames = EllesmereUI.GetProfileAddonDisplayNames
                and EllesmereUI.GetProfileAddonDisplayNames(folderList)
                or {}
            if #displayNames == 0 then
                return nil
            end
            return table.concat(displayNames, ", ")
        end

        local function OpenImportNamingFlow(importStr, initialName, errorTitle)
            local payload, err = EllesmereUI.DecodeImportString(importStr)
            if not payload then
                ShowProfileError(errorTitle or "Import Failed", err)
                return
            end

            local importMessage
            if payload.type == "partial" then
                local payloadAddonsText = FormatAddonDisplayList(payload.data and payload.data.includedAddons)
                if payloadAddonsText then
                    importMessage = "Enter a name for the imported profile. It will include settings for: "
                        .. payloadAddonsText
                        .. ". Shared fonts and custom colors from the import are included too, and your UI will reload when it is applied."
                else
                    importMessage = "Enter a name for the imported profile. It will include the settings from the import, along with shared fonts and custom colors. Your UI will reload when it is applied."
                end
            else
                importMessage = "Enter a name for the imported profile. It will become the profile you are using now, and your UI will reload when it is applied."
            end

            local function TryImportProfile(name, allowOverwrite)
                local ok, resultOrErr, code = EllesmereUI.ImportProfile(importStr, name, {
                    allowOverwrite = allowOverwrite,
                })
                if ok then
                    FinishProfileAction(resultOrErr)
                elseif code == "profile_exists" and not allowOverwrite then
                    PromptOverwrite({
                        title = "Overwrite Profile",
                        message = "A profile named \"" .. name .. "\" already exists. Replace it with the imported settings?",
                        onConfirm = function()
                            TryImportProfile(name, true)
                        end,
                    })
                else
                    ShowProfileError(errorTitle or "Import Failed", resultOrErr)
                end
            end

            ShowNamePrompt({
                title = "Name Profile",
                message = importMessage,
                placeholder = initialName or "Imported Profile",
                initialText = initialName or "",
                confirmText = "Import",
                onConfirm = function(name)
                    TryImportProfile(name, false)
                end,
            })
        end

        local function TryPresetImport(exportString, suggestedName, title)
            if not exportString or exportString == "" then
                ShowProfileError(title or "Preset Error", "That preset does not contain an import string.")
                return
            end
            OpenImportNamingFlow(exportString, suggestedName, title)
        end

        -------------------------------------------------------------------
        --  ACTIVE PROFILE section
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "ACTIVE PROFILE", y);  y = y - h

        do
            local ROW_H = 100
            local rowFrame = CreateFrame("Frame", nil, parent)
            local totalW = parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2
            PP.Size(rowFrame, totalW, ROW_H)
            PP.Point(rowFrame, "TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD, y)
            EllesmereUI.RowBg(rowFrame, parent)

            local DD_W = 220
            local DD_H = 30
            local BTN_W = 92
            local BTN_GAP = 8

            -- The dropdown remains the profile switcher, but now the apply path is
            -- intentionally conservative: save the current profile, copy the new
            -- snapshot into SavedVariables, then reload the UI.
            local ddBtn = CreateFrame("Button", nil, rowFrame)
            PP.Size(ddBtn, DD_W, DD_H)
            PP.Point(ddBtn, "LEFT", rowFrame, "LEFT", 20, 14)
            ddBtn:SetFrameLevel(rowFrame:GetFrameLevel() + 2)

            local ddBg = ddBtn:CreateTexture(nil, "BACKGROUND")
            ddBg:SetAllPoints()
            ddBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
            EllesmereUI.MakeBorder(ddBtn, 1, 1, 1, EllesmereUI.DD_BRD_A, PP)

            ddLabel = EllesmereUI.MakeFont(ddBtn, 13, nil, 1, 1, 1)
            ddLabel:SetAlpha(EllesmereUI.DD_TXT_A)
            ddLabel:SetPoint("LEFT", ddBtn, "LEFT", 12, 0)
            ddLabel:SetPoint("RIGHT", ddBtn, "RIGHT", -28, 0)
            ddLabel:SetJustifyH("LEFT")

            RefreshActiveProfileDisplay()
            EllesmereUI.RegisterWidgetRefresh(RefreshActiveProfileDisplay)

            EllesmereUI.MakeDropdownArrow(ddBtn, 12, PP)

            local menu = CreateFrame("Frame", nil, UIParent)
            menu:SetFrameStrata("FULLSCREEN_DIALOG")
            menu:SetFrameLevel(200)
            menu:SetClampedToScreen(true)
            menu:SetSize(DD_W, 4)
            menu:SetPoint("TOPLEFT", ddBtn, "BOTTOMLEFT", 0, -2)
            menu:Hide()

            local menuBg = menu:CreateTexture(nil, "BACKGROUND")
            menuBg:SetAllPoints()
            menuBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, 0.98)
            EllesmereUI.MakeBorder(menu, 1, 1, 1, EllesmereUI.DD_BRD_A, PP)

            local menuItems = {}
            local function RebuildProfileMenu()
                for _, item in ipairs(menuItems) do item:Hide() end

                local order, profiles = EllesmereUI.GetProfileList()
                local menuHeight = 4
                local idx = 0
                local activeName = EllesmereUI.GetActiveProfileName()

                for _, name in ipairs(order) do
                    if profiles[name]
                        and (not EllesmereUI.IsProfileUsable or EllesmereUI.IsProfileUsable(name)) then
                        idx = idx + 1
                        local item = menuItems[idx]
                        if not item then
                            item = CreateFrame("Button", nil, menu)
                            item:SetHeight(26)
                            item:SetFrameLevel(menu:GetFrameLevel() + 1)

                            local lbl = item:CreateFontString(nil, "OVERLAY")
                            lbl:SetFont(FONT, 13, EllesmereUI.GetFontOutlineFlag())
                            lbl:SetPoint("LEFT", item, "LEFT", 10, 0)
                            lbl:SetTextColor(0.55, 0.60, 0.65, 1)
                            item._lbl = lbl

                            local hl = item:CreateTexture(nil, "ARTWORK")
                            hl:SetAllPoints()
                            hl:SetColorTexture(1, 1, 1, 0)
                            item._hl = hl

                            item:SetScript("OnEnter", function()
                                lbl:SetTextColor(1, 1, 1, 1)
                                hl:SetAlpha(0.08)
                            end)
                            item:SetScript("OnLeave", function()
                                lbl:SetTextColor(0.55, 0.60, 0.65, 1)
                                hl:SetAlpha(item._isSel and 0.04 or 0)
                            end)

                            menuItems[idx] = item
                        end

                        item:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -menuHeight)
                        item:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -1, -menuHeight)
                        item._lbl:SetText(name)
                        item._isSel = (name == activeName)
                        item._hl:SetAlpha(item._isSel and 0.04 or 0)
                        item:SetScript("OnClick", function()
                            menu:Hide()
                            local ok, resultOrErr = EllesmereUI.SwitchProfile(name, {
                                reason = "manual",
                            })
                            if ok then
                                FinishProfileAction(resultOrErr)
                            else
                                ShowProfileError("Switch Profile", resultOrErr)
                            end
                        end)
                        item:Show()
                        menuHeight = menuHeight + 26
                    end
                end

                menu:SetHeight(menuHeight + 4)
            end

            ddBtn:SetScript("OnClick", function()
                if menu:IsShown() then
                    menu:Hide()
                else
                    RebuildProfileMenu()
                    menu:Show()
                end
            end)
            ddBtn:SetScript("OnEnter", function()
                ddBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_HA)
                ddLabel:SetAlpha(EllesmereUI.DD_TXT_HA)
            end)
            ddBtn:SetScript("OnLeave", function()
                if not menu:IsShown() then
                    ddBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
                    ddLabel:SetAlpha(EllesmereUI.DD_TXT_A)
                end
            end)
            ddBtn:HookScript("OnHide", function() menu:Hide() end)
            menu:SetScript("OnShow", function(self)
                local btnScale = ddBtn:GetEffectiveScale()
                local uiScale = UIParent:GetEffectiveScale()
                self:SetScale(btnScale / uiScale)
                self._anchorX, self._anchorY = ddBtn:GetCenter()
                self:SetScript("OnUpdate", function(m)
                    local curX, curY = ddBtn:GetCenter()
                    if not curX or not curY then
                        m:Hide()
                        return
                    end

                    -- The menu lives on `UIParent` so it can draw above the
                    -- page, but that also means page scrolling can leave it
                    -- visually detached from the button. Close it as soon as
                    -- the anchor moves instead of letting it clip through the
                    -- panel while the content scrolls underneath it.
                    if m._anchorX and m._anchorY
                        and (math.abs(curX - m._anchorX) > 0.5 or math.abs(curY - m._anchorY) > 0.5) then
                        m:Hide()
                        return
                    end

                    if not ddBtn:IsMouseOver() and not m:IsMouseOver() then
                        if IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") then
                            m:Hide()
                        end
                    end
                end)
            end)
            menu:SetScript("OnHide", function(self)
                self:SetScript("OnUpdate", nil)
                self._anchorX = nil
                self._anchorY = nil
                ddBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
                ddLabel:SetAlpha(EllesmereUI.DD_TXT_A)
            end)

            local saveBtn = CreateFrame("Button", nil, rowFrame)
            PP.Size(saveBtn, BTN_W, DD_H)
            PP.Point(saveBtn, "LEFT", ddBtn, "RIGHT", BTN_GAP, 0)
            saveBtn:SetFrameLevel(rowFrame:GetFrameLevel() + 2)
            EllesmereUI.MakeStyledButton(saveBtn, "Save", 13,
                EllesmereUI.WB_COLOURS, function()
                    local ok, resultOrErr = EllesmereUI.AutoSaveActiveProfile()
                    if not ok then
                        ShowProfileError("Save Profile", resultOrErr)
                    else
                        FinishProfileAction(resultOrErr)
                    end
                end)

            local revertBtn = CreateFrame("Button", nil, rowFrame)
            PP.Size(revertBtn, BTN_W, DD_H)
            PP.Point(revertBtn, "LEFT", saveBtn, "RIGHT", BTN_GAP, 0)
            revertBtn:SetFrameLevel(rowFrame:GetFrameLevel() + 2)
            EllesmereUI.MakeStyledButton(revertBtn, "Revert", 13,
                EllesmereUI.RB_COLOURS, function()
                    local dirtyState = EllesmereUI.GetActiveProfileDirtyState
                        and EllesmereUI.GetActiveProfileDirtyState()
                        or { isDirty = false }
                    if not dirtyState.isDirty then
                        ShowProfileError("Revert Profile", "There is nothing to revert right now.")
                        return
                    end

                    local activeName = EllesmereUI.GetActiveProfileName()
                    if not activeName then
                        ShowProfileError("Revert Profile", "There is no saved profile to revert yet.")
                        return
                    end

                    EllesmereUI:ShowConfirmPopup({
                        title = "Revert Profile",
                        message = "Discard your unsaved changes and reload \"" .. activeName .. "\"?",
                        confirmText = "Revert",
                        cancelText = "Cancel",
                        onConfirm = function()
                            local ok, resultOrErr = EllesmereUI.RevertActiveProfile()
                            if ok then
                                FinishProfileAction(resultOrErr)
                            else
                                ShowProfileError("Revert Profile", resultOrErr)
                            end
                        end,
                    })
                end)

            local createBtn = CreateFrame("Button", nil, rowFrame)
            PP.Size(createBtn, BTN_W, DD_H)
            PP.Point(createBtn, "LEFT", revertBtn, "RIGHT", BTN_GAP, 0)
            createBtn:SetFrameLevel(rowFrame:GetFrameLevel() + 2)
            EllesmereUI.MakeStyledButton(createBtn, "Create", 13,
                EllesmereUI.WB_COLOURS, function()
                    ShowNamePrompt({
                        title = "Create Profile",
                        message = "Enter a name for your new profile. It will become the profile you are using now.",
                        placeholder = "My Profile",
                        confirmText = "Create",
                        onConfirm = function(name)
                            TryCreateProfile(name, false)
                        end,
                    })
                end)

            local renameBtn = CreateFrame("Button", nil, rowFrame)
            PP.Size(renameBtn, BTN_W, DD_H)
            PP.Point(renameBtn, "LEFT", createBtn, "RIGHT", BTN_GAP, 0)
            renameBtn:SetFrameLevel(rowFrame:GetFrameLevel() + 2)
            EllesmereUI.MakeStyledButton(renameBtn, "Rename", 13,
                EllesmereUI.WB_COLOURS, function()
                    local activeName = EllesmereUI.GetActiveProfileName()
                    if not activeName then
                        ShowProfileError("Rename Profile", "There is no saved profile to rename yet.")
                        return
                    end
                    if EllesmereUI.IsReservedProfileName and EllesmereUI.IsReservedProfileName(activeName) then
                        ShowProfileError("Rename Profile", "The built-in Custom profile cannot be renamed.")
                        return
                    end

                    ShowNamePrompt({
                        title = "Rename Profile",
                        message = "Enter a new name for the profile you are using now.",
                        placeholder = activeName,
                        initialText = activeName,
                        confirmText = "Rename",
                        onConfirm = function(name)
                            TryRenameProfile(activeName, name, false)
                        end,
                    })
                end)

            local deleteBtn = CreateFrame("Button", nil, rowFrame)
            PP.Size(deleteBtn, BTN_W, DD_H)
            PP.Point(deleteBtn, "LEFT", renameBtn, "RIGHT", BTN_GAP, 0)
            deleteBtn:SetFrameLevel(rowFrame:GetFrameLevel() + 2)
            EllesmereUI.MakeStyledButton(deleteBtn, "Delete", 13,
                EllesmereUI.RB_COLOURS, function()
                    local activeName = EllesmereUI.GetActiveProfileName()
                    if not activeName then
                        ShowProfileError("Delete Profile", "There is no saved profile to delete yet.")
                        return
                    end
                    if EllesmereUI.IsReservedProfileName and EllesmereUI.IsReservedProfileName(activeName) then
                        ShowProfileError("Delete Profile", "The built-in Custom profile cannot be deleted.")
                        return
                    end

                    EllesmereUI:ShowConfirmPopup({
                        title = "Delete Profile",
                        message = "Delete \"" .. activeName .. "\"? EllesmereUI will switch to another profile and reload your UI.",
                        confirmText = "Delete",
                        cancelText = "Cancel",
                        onConfirm = function()
                            local ok, resultOrErr = EllesmereUI.DeleteProfile(activeName)
                            if ok then
                                FinishProfileAction(resultOrErr)
                            else
                                ShowProfileError("Delete Profile", resultOrErr)
                            end
                        end,
                    })
                end)

            dirtyStateLabel = EllesmereUI.MakeFont(rowFrame, 11, nil, 1, 1, 1)
            dirtyStateLabel:SetPoint("TOPLEFT", ddBtn, "BOTTOMLEFT", 0, -4)
            dirtyStateLabel:SetJustifyH("LEFT")

            activeProfileNote = EllesmereUI.MakeFont(rowFrame, 11, nil, 1, 1, 1)
            activeProfileNote:SetAlpha(0.52)
            activeProfileNote:SetPoint("TOPLEFT", dirtyStateLabel, "BOTTOMLEFT", 0, -4)
            activeProfileNote:SetPoint("RIGHT", rowFrame, "RIGHT", -20, 0)
            activeProfileNote:SetJustifyH("LEFT")
            activeProfileNote:SetWordWrap(true)
            activeProfileNote:SetSpacing(2)

            RefreshActiveProfileDisplay()

            y = y - ROW_H
        end

        -------------------------------------------------------------------
        --  SPEC ASSIGNMENT section
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "SPEC ASSIGNMENT", y);  y = y - h

        do
            local ROW_H = 68
            local rowFrame = CreateFrame("Frame", nil, parent)
            local totalW = parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2
            PP.Size(rowFrame, totalW, ROW_H)
            PP.Point(rowFrame, "TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD, y)
            EllesmereUI.RowBg(rowFrame, parent)

            local assignBtn = CreateFrame("Button", nil, rowFrame)
            PP.Size(assignBtn, 260, 30)
            PP.Point(assignBtn, "TOP", rowFrame, "TOP", 0, -10)
            assignBtn:SetFrameLevel(rowFrame:GetFrameLevel() + 2)
            EllesmereUI.MakeStyledButton(assignBtn, "Assign Current Profile to Specs", 13,
                EllesmereUI.WB_COLOURS, function()
                    -- The popup edits a name -> spec-set map, while the stored
                    -- profile data remains a simple `specID -> profileName`
                    -- lookup. Build the inverted view on demand, then fold it
                    -- back into the compact persisted shape when the user saves.
                    if not EllesmereUIDB then EllesmereUIDB = {} end
                    local db = EllesmereUIDB
                    if not db.specProfiles then db.specProfiles = {} end

                    local tempDB = { _profileSpecs = {} }
                    local order, profiles = EllesmereUI.GetProfileList()
                    for _, profileName in ipairs(order) do
                        if not EllesmereUI.IsProfileUsable or EllesmereUI.IsProfileUsable(profileName) then
                            tempDB._profileSpecs[profileName] = {}
                        end
                    end
                    for specID, profileName in pairs(db.specProfiles) do
                        if tempDB._profileSpecs[profileName] then
                            tempDB._profileSpecs[profileName][specID] = true
                        end
                    end

                    local activeName = EllesmereUI.GetActiveProfileName()
                    if not activeName then
                        ShowProfileError("Assign Profile to Specs", "There is no saved profile to assign yet.")
                        return
                    end

                    EllesmereUI:ShowSpecAssignPopup({
                        db = tempDB,
                        dbKey = "_profileSpecs",
                        presetKey = activeName,
                        titleText = "Assign Profile to Specs",
                        subtitleBuilder = function(profileName)
                            return "You are choosing which specs should use: " .. profileName
                                .. "\nChecked specs will switch to this profile automatically. If a spec is already assigned to another profile, checking it here will move it to this one."
                        end,
                        allPresetKeys = function()
                            local list = {}
                            for _, profileName in ipairs(order) do
                                if profiles[profileName]
                                    and (not EllesmereUI.IsProfileUsable or EllesmereUI.IsProfileUsable(profileName)) then
                                    list[#list + 1] = { key = profileName, name = profileName }
                                end
                            end
                            return list
                        end,
                        onDone = function()
                            db.specProfiles = {}
                            for profileName, specSet in pairs(tempDB._profileSpecs) do
                                for specID in pairs(specSet) do
                                    EllesmereUI.AssignProfileToSpec(profileName, specID)
                                end
                            end
                            EllesmereUI:RefreshPage()
                        end,
                    })
                end)

            local note = EllesmereUI.MakeFont(rowFrame, 11, nil, 1, 1, 1)
            note:SetAlpha(0.52)
            note:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", 20, -48)
            note:SetPoint("RIGHT", rowFrame, "RIGHT", -20, 0)
            note:SetJustifyH("LEFT")
            note:SetWordWrap(true)
            note:SetSpacing(2)
            note:SetText("Choose which profile each spec should use. EllesmereUI will switch to it automatically when you change specs.")

            y = y - ROW_H
        end

        -------------------------------------------------------------------
        --  IMPORT / EXPORT section
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "IMPORT / EXPORT", y);  y = y - h

        _, h = W:WideButton(parent, "Export Current Profile", y, function()
            local str, err = EllesmereUI.ExportCurrentProfile()
            if str then
                EllesmereUI:ShowExportPopup(str)
            else
                ShowProfileError("Export Failed", err)
            end
        end);  y = y - h

        _, h = W:WideButton(parent, "Import Profile", y, function()
            EllesmereUI:ShowImportPopup(function(importStr)
                OpenImportNamingFlow(importStr, nil)
            end)
        end);  y = y - h

        do
            local ROW_H = missingAddonsText and 56 or 36
            local scopeFrame = CreateFrame("Frame", nil, parent)
            local totalW = parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2
            PP.Size(scopeFrame, totalW, ROW_H)
            PP.Point(scopeFrame, "TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD, y)

            local scopeNote = EllesmereUI.MakeFont(scopeFrame, 11, nil, 1, 1, 1)
            scopeNote:SetAlpha(0.52)
            scopeNote:SetPoint("TOPLEFT", scopeFrame, "TOPLEFT", 0, 0)
            scopeNote:SetPoint("RIGHT", scopeFrame, "RIGHT", 0, 0)
            scopeNote:SetJustifyH("LEFT")
            scopeNote:SetWordWrap(true)
            scopeNote:SetSpacing(2)
            scopeNote:SetText("This profile currently includes settings for: " .. includedAddonsText .. "."
                .. (missingAddonsText
                    and "\nThese addons are not loaded right now, so their settings will not be updated until they are enabled again: " .. missingAddonsText .. "."
                    or ""))

            y = y - ROW_H
        end

        -------------------------------------------------------------------
        --  PER-ADDON EXPORT section
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "PER-ADDON EXPORT", y);  y = y - h

        local selectedAddons = {}
        do
            for _, entry in ipairs(ADDON_DB_MAP) do
                if C_AddOns.IsAddOnLoaded(entry.folder) then
                    local isChecked = false
                    _, h = W:Checkbox(parent, entry.display, y,
                        function() return isChecked end,
                        function(v)
                            isChecked = v
                            if v then
                                selectedAddons[entry.folder] = true
                            else
                                selectedAddons[entry.folder] = nil
                            end
                        end
                    );  y = y - h
                end
            end
        end

        _, h = W:WideButton(parent, "Export Selected Addons", y, function()
            local folders = {}
            for folder in pairs(selectedAddons) do
                folders[#folders + 1] = folder
            end
            if #folders == 0 then
                ShowProfileError("Export Failed", "Select at least one addon to export.")
                return
            end
            local str, err = EllesmereUI.ExportAddons(folders)
            if str then
                EllesmereUI:ShowExportPopup(str)
            else
                ShowProfileError("Export Failed", err)
            end
        end);  y = y - h

        do
            local ROW_H = 30
            local infoFrame = CreateFrame("Frame", nil, parent)
            local totalW = parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2
            PP.Size(infoFrame, totalW, ROW_H)
            PP.Point(infoFrame, "TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD, y)

            local infoBtn = CreateFrame("Button", nil, infoFrame)
            infoBtn:SetFrameLevel(infoFrame:GetFrameLevel() + 1)
            local infoFS = infoBtn:CreateFontString(nil, "OVERLAY")
            infoFS:SetFont(FONT, 12, EllesmereUI.GetFontOutlineFlag())
            infoFS:SetTextColor(EG.r, EG.g, EG.b, 0.70)
            infoFS:SetText("How does this work?")
            infoFS:SetPoint("CENTER")
            infoBtn:SetSize(infoFS:GetStringWidth() + 10, 18)
            PP.Point(infoBtn, "LEFT", infoFrame, "LEFT", 0, 0)
            infoBtn:SetScript("OnEnter", function()
                infoFS:SetTextColor(EG.r, EG.g, EG.b, 1)
            end)
            infoBtn:SetScript("OnLeave", function()
                infoFS:SetTextColor(EG.r, EG.g, EG.b, 0.70)
            end)
            infoBtn:SetScript("OnClick", function()
                EllesmereUI:ShowInfoPopup({
                    title = "Profile Import / Export",
                    content = "PROFILE SCOPE\n"
                        .. "Profiles currently include these EllesmereUI addons: " .. includedAddonsText .. ". Shared fonts and custom colors are included too."
                        .. (missingAddonsText
                            and "\n\nThese addons are not loaded right now, so their settings will not be updated until they are enabled again: " .. missingAddonsText .. "."
                            or "")
                        .. "\n\nEXCLUDED SETTINGS\n"
                        .. "Profiles do not include Global Settings on this page, Party Mode, panel scale, minimap button position, privacy and debug settings, or other machine- or character-specific settings.\n\n"
                        .. "SWITCHING AND IMPORTING\n"
                        .. "When you switch or import a profile, EllesmereUI saves your current settings first, then reloads your UI so the new profile is applied cleanly.\n\n"
                        .. "SPEC ASSIGNMENTS\n"
                        .. "If you assign profiles to specs, EllesmereUI switches them automatically when you change specs.\n\n"
                        .. "ERRORS\n"
                        .. "If a profile string is invalid or from an incompatible version, EllesmereUI shows an error instead of importing it.\n\n"
                        .. "PER-ADDON EXPORT\n"
                        .. "Selective exports only include the addons you choose, plus shared fonts and custom colors. Anything you leave out keeps its current settings.",
                })
            end)

            y = y - ROW_H
        end

        -------------------------------------------------------------------
        --  POPULAR PRESETS section
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "POPULAR PRESETS", y);  y = y - h

        _, h = W:WideButton(parent, "EllesmereUI (Default)", y, function()
            EllesmereUI:ShowConfirmPopup({
                title = "Apply EllesmereUI Defaults",
                message = "This will reset all addon settings to EllesmereUI defaults and save as your active profile. Continue?",
                confirmText = "Apply",
                cancelText = "Cancel",
                onConfirm = function()
                    if EllesmereUIDB then
                        EllesmereUIDB._pendingPresetReset = "ellesmereui"
                    end
                    ReloadUI()
                end,
            })
        end);  y = y - h

        _, h = W:WideButton(parent, "Spin the Wheel (Randomize)", y, function()
            EllesmereUI:ShowConfirmPopup({
                title = "Spin the Wheel",
                message = "This will randomize all your settings (except positions). Party Mode will be enabled. Continue?",
                confirmText = "Spin!",
                cancelText = "Cancel",
                onConfirm = function()
                    EllesmereUI.SpinTheWheel()
                    local ok, resultOrErr = EllesmereUI.SaveCurrentAsProfile("Spin the Wheel", {
                        allowOverwrite = true,
                    })
                    if ok then
                        FinishProfileAction({
                            profileName = (resultOrErr and resultOrErr.profileName) or "Spin the Wheel",
                            requiresReload = true,
                        })
                    else
                        ShowProfileError("Preset Error", resultOrErr)
                    end
                end,
            })
        end);  y = y - h

        if EllesmereUI.WEEKLY_SPOTLIGHT then
            local spot = EllesmereUI.WEEKLY_SPOTLIGHT
            _, h = W:WideButton(parent,
                "Weekly Spotlight: " .. spot.name, y, function()
                    TryPresetImport(spot.exportString, "Weekly: " .. spot.name, "Spotlight Error")
                end);  y = y - h
        end

        for _, preset in ipairs(EllesmereUI.POPULAR_PRESETS) do
            if preset.exportString then
                _, h = W:WideButton(parent, preset.name, y, function()
                    TryPresetImport(preset.exportString, preset.name, "Preset Error")
                end);  y = y - h
            end
        end

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Enabled Addons page
    ---------------------------------------------------------------------------

    local disabledList = { PAGE_CORE }
    local disabledTips = { [PAGE_CORE] = "Coming Soon" }

    EllesmereUI:RegisterModule(GLOBAL_KEY, {
        title       = "Global Settings",
        description = "General options for all EllesmereUI addons.",
        pages       = { PAGE_GENERAL, PAGE_CORE, PAGE_COLORS, PAGE_PROFILES },
        disabledPages = disabledList,
        disabledPageTooltips = disabledTips,
        buildPage   = function(pageName, parent, yOffset)
            if pageName == PAGE_GENERAL then
                return BuildGeneralPage(pageName, parent, yOffset)
            elseif pageName == PAGE_COLORS then
                return BuildColorsPage(pageName, parent, yOffset)
            elseif pageName == PAGE_CORE then
                return BuildCoreOptionsPage(pageName, parent, yOffset)
            elseif pageName == PAGE_PROFILES then
                return BuildProfilesPage(pageName, parent, yOffset)
            end
        end,
        onReset     = function()
            -- Reset CVars to EUI preferred defaults (ignoring current state)
            for _, entry in ipairs(EUI_DEFAULTS) do
                SetCVarSafe(entry[1], entry[2])
            end
            -- Reset style/theme settings (accent color, custom theme, class-colored)
            EllesmereUI.ResetTheme()
            -- Reset panel scale to 100%
            if EllesmereUI.SetPanelScale then
                EllesmereUI:SetPanelScale(1.0)
            end
            -- Reset right-click targeting to default (disabled = off)
            if EllesmereUIDB then
                EllesmereUIDB.disableRightClickTarget = false
                EllesmereUIDB.showFPS = false
                EllesmereUIDB.showSecondaryStats = false
                EllesmereUIDB.guildChatPrivacy = false
                EllesmereUIDB.repairWarning = nil
                -- Developer settings defaults
                EllesmereUIDB.errorGrabber = false
                EllesmereUIDB.errorSound = false
                EllesmereUIDB.showSpellID = false
                EllesmereUIDB.suppressErrors = true
            end
            if EllesmereUI._applyRightClickTarget then
                EllesmereUI._applyRightClickTarget()
            end
            if EllesmereUI._applyFPSCounter then
                EllesmereUI._applyFPSCounter()
            end
            if EllesmereUI._applySecondaryStats then
                EllesmereUI._applySecondaryStats()
            end
            if EllesmereUI._applyGuildChatPrivacy then
                EllesmereUI._applyGuildChatPrivacy()
            end
            -- Apply error grabber defaults (off) and suppress (on)
            if EllesmereUI._disableErrorGrabber then
                EllesmereUI._disableErrorGrabber()
            end
            SetCVarSafe("scriptErrors", "0")
            EllesmereUI:SelectPage(PAGE_GENERAL)
        end,
    })
end)
