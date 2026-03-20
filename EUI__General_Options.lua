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
    local ceil  = math.ceil
    local max   = math.max

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
    ---------------------------------------------------------------------------
    local EUI_DEFAULTS = {
        { "cameraDistanceMaxZoomFactor",                    "2.6" },
        { "ActionButtonUseKeyDown",                         "1"   },
        { "SpellQueueWindow",                               "150" },
        { "floatingCombatTextCombatHealing_v2",             "1"   },
        { "WorldTextScale_v2",                              "0.5" },
        { "floatingCombatTextCombatDamage_v2",              "1"   },
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
        EllesmereUI:EnsureLoaded()
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
                local maxScroll = EllesmereUI.SafeScrollRange(sf)
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
                local maxScroll = EllesmereUI.SafeScrollRange(sf)
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
                local maxScroll = EllesmereUI.SafeScrollRange(sf)
                scrollTarget = math.max(0, math.min(maxScroll, target))
                if not isSmoothing then
                    isSmoothing = true
                    smoothFrame:Show()
                end
            end

            sf:SetScript("OnMouseWheel", function(self, delta)
                local maxScroll = EllesmereUI.SafeScrollRange(self)
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
                    local maxScroll = EllesmereUI.SafeScrollRange(sf)
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
            { "graphicsShadowQuality",      "1" },
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
                        .. "Shadow Quality - Fair (balanced quality/FPS)\n"
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
              values={ ["Tiny (75%)"]="Tiny (75%)", ["Small (90%)"]="Small (90%)", ["Normal (100%)"]="Normal (100%)", ["Large (110%)"]="Large (110%)", ["Huge (125%)"]="Huge (125%)", ["Massive (150%)"]="Massive (150%)" },
              order={ "Tiny (75%)", "Small (90%)", "Normal (100%)", "Large (110%)", "Huge (125%)", "Massive (150%)" },
              getValue=function()
                local raw = (EllesmereUIDB and EllesmereUIDB.panelScale) or 1.0
                local pct = floor(raw * 100 + 0.5)
                if pct == 75  then return "Tiny (75%)"    end
                if pct == 90  then return "Small (90%)"   end
                if pct == 110 then return "Large (110%)"  end
                if pct == 125 then return "Huge (125%)"   end
                if pct == 150 then return "Massive (150%)" end
                return "Normal (100%)"
              end,
              setValue=function(v)
                local scale = 1.0
                if v == "Tiny (75%)"     then scale = 0.75
                elseif v == "Small (90%)"    then scale = 0.90
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
              min=0.40, max=1.00, step=0.01,
              tooltip="Sets the scale of the entire game UI. Lower values make everything smaller, higher values make everything larger.",
              getValue=function()
                if EllesmereUI._uiScaleDragVal then
                    return EllesmereUI._uiScaleDragVal
                end
                return EllesmereUIDB and EllesmereUIDB.ppUIScale or EllesmereUI.PP.PixelBestSize()
              end,
              setValue=function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUI._uiScaleDragVal = v
                EllesmereUIDB.ppUIScaleAuto = false
                -- Snapshot panel scale before changing UIParent
                local mf = EllesmereUI._mainFrame
                local panelScaleBefore
                if mf then panelScaleBefore = mf:GetEffectiveScale() end
                EllesmereUI.PP.SetUIScale(v)
                -- Counter-scale panel so it stays visually identical
                if mf and panelScaleBefore then
                    local newEff = UIParent:GetEffectiveScale()
                    if newEff > 0 then mf:SetScale(panelScaleBefore / newEff) end
                end
                if not EllesmereUI._uiScaleCleanup then
                    EllesmereUI._uiScaleCleanup = true
                    C_Timer.After(0, function()
                        if not EllesmereUI._sliderDragging then
                            EllesmereUI._uiScaleDragVal = nil
                        end
                        EllesmereUI._uiScaleCleanup = false
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
                return EllesmereUIDB.autoSellJunk ~= false
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
                if not v and EllesmereUI._durWarnHidePreview then
                    EllesmereUI._durWarnHidePreview()
                end
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
                    durPreviewShown = false
                    RefreshDurEye()
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

        -- Row 5: Character Crosshair (left, with inline swatch) | Rested Indicator (right)
        local crosshairRow
        crosshairRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Character Crosshair",
              tooltip="Displays a crosshair at the center of the screen.",
              values={ ["None"]="None", ["Thin"]="Thin", ["Normal"]="Normal", ["Thick"]="Thick" },
              order={ "None", "Thin", "Normal", "Thick" },
              getValue=function()
                return (EllesmereUIDB and EllesmereUIDB.crosshairSize) or "None"
              end,
              setValue=function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.crosshairSize = v
                if EllesmereUI._applyCrosshair then EllesmereUI._applyCrosshair() end
                EllesmereUI:RefreshPage()
              end },
            { type="toggle", text="Rested Indicator",
              tooltip="Displays a ZZZ indicator on your player frame when you are in a resting area.",
              getValue=function()
                if not EllesmereUIDB then return true end
                return EllesmereUIDB.showRestedIndicator == true
              end,
              setValue=function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.showRestedIndicator = v
                local pf = _G["EllesmereUIUnitFrames_Player"]
                if pf and pf._restIndicator then
                    if v and IsResting() then pf._restIndicator:Show() else pf._restIndicator:Hide() end
                end
                EllesmereUI:RefreshPage()
              end }
        );  y = y - h

        -- Inline cog on Rested Indicator (right) for X/Y offsets
        do
            local rightRgn = crosshairRow._rightRegion
            local function ApplyRestIndicatorPos()
                local pf = _G["EllesmereUIUnitFrames_Player"]
                if pf and pf._restIndicator then
                    pf._restIndicator:ClearAllPoints()
                    local rx = (EllesmereUIDB and EllesmereUIDB.restedIndicatorXOffset) or 0
                    local ry = (EllesmereUIDB and EllesmereUIDB.restedIndicatorYOffset) or 0
                    pf._restIndicator:SetPoint("TOPLEFT", pf.Health, "TOPLEFT", 3 + rx, -2 + ry)
                end
            end
            local _, restCogShow = EllesmereUI.BuildCogPopup({
                title = "Rested Indicator Position",
                rows = {
                    { type="slider", label="X Offset", min=-50, max=50, step=1,
                      get=function() return (EllesmereUIDB and EllesmereUIDB.restedIndicatorXOffset) or 0 end,
                      set=function(v)
                          if not EllesmereUIDB then EllesmereUIDB = {} end
                          EllesmereUIDB.restedIndicatorXOffset = v
                          ApplyRestIndicatorPos()
                      end },
                    { type="slider", label="Y Offset", min=-50, max=50, step=1,
                      get=function() return (EllesmereUIDB and EllesmereUIDB.restedIndicatorYOffset) or 0 end,
                      set=function(v)
                          if not EllesmereUIDB then EllesmereUIDB = {} end
                          EllesmereUIDB.restedIndicatorYOffset = v
                          ApplyRestIndicatorPos()
                      end },
                },
            })
            -- Manual cog button (no MakeCogBtn in this file)
            local function restOff()
                return not EllesmereUIDB or EllesmereUIDB.showRestedIndicator ~= true
            end
            local restCogBtn = CreateFrame("Button", nil, rightRgn)
            restCogBtn:SetSize(26, 26)
            restCogBtn:SetPoint("RIGHT", rightRgn._lastInline or rightRgn._control, "LEFT", -9, 0)
            rightRgn._lastInline = restCogBtn
            restCogBtn:SetFrameLevel(rightRgn:GetFrameLevel() + 5)
            restCogBtn:SetAlpha(restOff() and 0.15 or 0.4)
            local restCogTex = restCogBtn:CreateTexture(nil, "OVERLAY")
            restCogTex:SetAllPoints()
            restCogTex:SetTexture(EllesmereUI.COGS_ICON)
            restCogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            restCogBtn:SetScript("OnLeave", function(self) self:SetAlpha(restOff() and 0.15 or 0.4) end)
            restCogBtn:SetScript("OnClick", function(self) restCogShow(self) end)

            -- Blocking overlay when Rested Indicator is off
            local restCogBlock = CreateFrame("Frame", nil, restCogBtn)
            restCogBlock:SetAllPoints()
            restCogBlock:SetFrameLevel(restCogBtn:GetFrameLevel() + 10)
            restCogBlock:EnableMouse(true)
            restCogBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(restCogBtn, EllesmereUI.DisabledTooltip("Rested Indicator"))
            end)
            restCogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateRestCogState()
                local off = restOff()
                restCogBtn:SetAlpha(off and 0.15 or 0.4)
                if off then restCogBlock:Show() else restCogBlock:Hide() end
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateRestCogState)
            UpdateRestCogState()
        end

        -- Inline color swatch on the crosshair dropdown (left region)
        do
            local leftRgn = crosshairRow._leftRegion
            local function crosshairOff()
                return not EllesmereUIDB or (EllesmereUIDB.crosshairSize or "None") == "None"
            end

            local chSwGet = function()
                local c = EllesmereUIDB and EllesmereUIDB.crosshairColor
                if c then return c.r, c.g, c.b, c.a end
                return 1, 1, 1, 0.75
            end
            local chSwSet = function(r, g, b, a)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.crosshairColor = { r = r, g = g, b = b, a = a or 1 }
                if EllesmereUI._applyCrosshair then EllesmereUI._applyCrosshair() end
            end
            local chSwatch, chUpdateSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, chSwGet, chSwSet, true, 20)
            PP.Point(chSwatch, "RIGHT", leftRgn._control, "LEFT", -12, 0)
            leftRgn._lastInline = chSwatch

            local chSwBlock = CreateFrame("Frame", nil, chSwatch)
            chSwBlock:SetAllPoints()
            chSwBlock:SetFrameLevel(chSwatch:GetFrameLevel() + 10)
            chSwBlock:EnableMouse(true)
            chSwBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(chSwatch, EllesmereUI.DisabledTooltip("Character Crosshair"))
            end)
            chSwBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            EllesmereUI.RegisterWidgetRefresh(function()
                local off = crosshairOff()
                if off then
                    chSwatch:SetAlpha(0.3)
                    chSwBlock:Show()
                else
                    chSwatch:SetAlpha(1)
                    chSwBlock:Hide()
                end
                chUpdateSwatch()
            end)
            local chInitOff = crosshairOff()
            chSwatch:SetAlpha(chInitOff and 0.3 or 1)
            if chInitOff then chSwBlock:Show() else chSwBlock:Hide() end
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
            [FCT_FONT_DIR .. "Expressway.TTF"]         = { text = "Expressway",            font = FCT_FONT_DIR .. "Expressway.TTF" },
            [FCT_FONT_DIR .. "Avant Garde Naowh.ttf"]        = { text = "Avant Garde (Naowh)",   font = FCT_FONT_DIR .. "Avant Garde Naowh.ttf" },
            [FCT_FONT_DIR .. "Arial Bold.TTF"]         = { text = "Arial Bold",            font = FCT_FONT_DIR .. "Arial Bold.TTF" },
            [FCT_FONT_DIR .. "Poppins.ttf"]            = { text = "Poppins",               font = FCT_FONT_DIR .. "Poppins.ttf" },
            [FCT_FONT_DIR .. "FiraSans Medium.ttf"]    = { text = "Fira Sans Medium",      font = FCT_FONT_DIR .. "FiraSans Medium.ttf" },
            [FCT_FONT_DIR .. "Arial Narrow.ttf"]       = { text = "Arial Narrow",          font = FCT_FONT_DIR .. "Arial Narrow.ttf" },
            [FCT_FONT_DIR .. "Changa.ttf"]             = { text = "Changa",                font = FCT_FONT_DIR .. "Changa.ttf" },
            [FCT_FONT_DIR .. "Cinzel Decorative.ttf"]  = { text = "Cinzel Decorative",     font = FCT_FONT_DIR .. "Cinzel Decorative.ttf" },
            [FCT_FONT_DIR .. "Exo.otf"]                = { text = "Exo",                   font = FCT_FONT_DIR .. "Exo.otf" },
            [FCT_FONT_DIR .. "FiraSans Bold.ttf"]      = { text = "Fira Sans Bold",        font = FCT_FONT_DIR .. "FiraSans Bold.ttf" },
            [FCT_FONT_DIR .. "FiraSans Light.ttf"]     = { text = "Fira Sans Light",       font = FCT_FONT_DIR .. "FiraSans Light.ttf" },
            [FCT_FONT_DIR .. "Future X Black.otf"]     = { text = "Future X Black",        font = FCT_FONT_DIR .. "Future X Black.otf" },
            [FCT_FONT_DIR .. "Gotham Narrow Ultra.otf"] = { text = "Gotham Narrow Ultra",  font = FCT_FONT_DIR .. "Gotham Narrow Ultra.otf" },
            [FCT_FONT_DIR .. "Gotham Narrow.otf"]      = { text = "Gotham Narrow",         font = FCT_FONT_DIR .. "Gotham Narrow.otf" },
            [FCT_FONT_DIR .. "Russo One.ttf"]          = { text = "Russo One",             font = FCT_FONT_DIR .. "Russo One.ttf" },
            [FCT_FONT_DIR .. "Ubuntu.ttf"]             = { text = "Ubuntu",                font = FCT_FONT_DIR .. "Ubuntu.ttf" },
            [FCT_FONT_DIR .. "Homespun.ttf"]           = { text = "Homespun",              font = FCT_FONT_DIR .. "Homespun.ttf" },
            ["Fonts\\FRIZQT__.TTF"]                    = { text = "Friz Quadrata",         font = "Fonts\\FRIZQT__.TTF" },
            ["Fonts\\ARIALN.TTF"]                      = { text = "Arial",                 font = "Fonts\\ARIALN.TTF" },
            ["Fonts\\MORPHEUS.TTF"]                    = { text = "Morpheus",              font = "Fonts\\MORPHEUS.TTF" },
            ["Fonts\\skurri.ttf"]                      = { text = "Skurri",                font = "Fonts\\skurri.ttf" },
        }
        local fctFontOrder = {
            "default",
            FCT_FONT_DIR .. "Expressway.TTF",
            FCT_FONT_DIR .. "Avant Garde Naowh.ttf",
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
        if EllesmereUI.AppendSharedMediaFonts then
            EllesmereUI.AppendSharedMediaFonts(fctFontValues, fctFontOrder)
        end

        local showDmgRow
        showDmgRow, h = W:DualRow(parent, y,
            { type="toggle", text="Show Damage Text",
              getValue=function()
                return GetCVarBool("floatingCombatTextCombatDamage_v2")
              end,
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

        -- Inline cog on "Show Damage Text" left region for pet damage sub-settings
        do
            local dmgOff = function() return not GetCVarBool("floatingCombatTextCombatDamage_v2") end
            local leftRgn = showDmgRow._leftRegion

            local _, dmgCogShow = EllesmereUI.BuildCogPopup({
                title = "Damage Text Settings",
                rows = {
                    { type="toggle", label="Show Periodic Damage",
                      get=function() return GetCVarBool("floatingCombatTextCombatLogPeriodicSpells_v2") end,
                      set=function(v) SetCVarSafe("floatingCombatTextCombatLogPeriodicSpells_v2", v and "1" or "0") end },                            
                    { type="toggle", label="Show Pet Melee Damage",
                      get=function() return GetCVarBool("floatingCombatTextPetMeleeDamage_v2") end,
                      set=function(v) SetCVarSafe("floatingCombatTextPetMeleeDamage_v2", v and "1" or "0") end },
                    { type="toggle", label="Show Pet Spell Damage",
                      get=function() return GetCVarBool("floatingCombatTextPetSpellDamage_v2") end,
                      set=function(v) SetCVarSafe("floatingCombatTextPetSpellDamage_v2", v and "1" or "0") end },
                },
            })

            local dmgCogBtn = CreateFrame("Button", nil, leftRgn)
            dmgCogBtn:SetSize(26, 26)
            dmgCogBtn:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -9, 0)
            leftRgn._lastInline = dmgCogBtn
            dmgCogBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
            dmgCogBtn:SetAlpha(dmgOff() and 0.15 or 0.4)
            local dmgCogTex = dmgCogBtn:CreateTexture(nil, "OVERLAY")
            dmgCogTex:SetAllPoints()
            dmgCogTex:SetTexture(EllesmereUI.COGS_ICON)
            dmgCogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            dmgCogBtn:SetScript("OnLeave", function(self) self:SetAlpha(dmgOff() and 0.15 or 0.4) end)
            dmgCogBtn:SetScript("OnClick", function(self) dmgCogShow(self) end)

            local dmgCogBlock = CreateFrame("Frame", nil, dmgCogBtn)
            dmgCogBlock:SetAllPoints()
            dmgCogBlock:SetFrameLevel(dmgCogBtn:GetFrameLevel() + 10)
            dmgCogBlock:EnableMouse(true)
            dmgCogBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(dmgCogBtn, EllesmereUI.DisabledTooltip("Show Damage Text"))
            end)
            dmgCogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            EllesmereUI.RegisterWidgetRefresh(function()
                if dmgOff() then
                    dmgCogBtn:SetAlpha(0.15)
                    dmgCogBlock:Show()
                else
                    dmgCogBtn:SetAlpha(0.4)
                    dmgCogBlock:Hide()
                end
            end)

            dmgCogBtn:SetAlpha(dmgOff() and 0.15 or 0.4)
            if dmgOff() then dmgCogBlock:Show() else dmgCogBlock:Hide() end
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
                if EAB and EAB.ApplyShapes then EAB:ApplyShapes() end
                if EAB and EAB.ApplyBorders then EAB:ApplyBorders() end
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
                    div:SetWidth(1)
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
                local displayName = (EllesmereUI.FONT_DISPLAY_NAMES and EllesmereUI.FONT_DISPLAY_NAMES[name]) or name
                fontDropValues[name] = { text = displayName, font = path }
                fontDropOrder[#fontDropOrder + 1] = name
            end
        end
        if EllesmereUI.AppendSharedMediaFonts then
            EllesmereUI.AppendSharedMediaFonts(fontDropValues, fontDropOrder, { keyByName = true })
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

        local outlineModeValues = {
            ["none"]    = { text = "Drop Shadow" },
            ["outline"] = { text = "Outline" },
            ["thick"]   = { text = "Thick Outline" },
        }
        local outlineModeOrder = { "none", "outline", "thick" }

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
              getValue=function() return EllesmereUI.GetFontsDB().outlineMode or "none" end,
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
        local MK = EllesmereUI.MakeUnlockElement
        EllesmereUI:RegisterUnlockElements({
            MK({
                key = "EUI_FPS",
                label = "FPS Counter",
                group = "General",
                order = 700,
                getFrame = function()
                    if not fpsFrame then CreateFPSCounter() end
                    return fpsFrame
                end,
                getSize = function()
                    if fpsFrame then return fpsFrame:GetWidth(), fpsFrame:GetHeight() end
                    return 80, 20
                end,
                noResize = true,
                savePos = function(key, point, relPoint, x, y)
                    if not EllesmereUIDB then EllesmereUIDB = {} end
                    if not point then return end
                    EllesmereUIDB.fpsPos = { point = point, relPoint = relPoint, x = x, y = y }
                    if fpsFrame then
                        fpsFrame:ClearAllPoints()
                        fpsFrame:SetPoint(point, UIParent, relPoint or point, x or 0, y or 0)
                    end
                end,
                loadPos = function()
                    return EllesmereUIDB and EllesmereUIDB.fpsPos
                end,
                clearPos = function()
                    if EllesmereUIDB then EllesmereUIDB.fpsPos = nil end
                end,
                applyPos = function()
                    if not fpsFrame then return end
                    local pos = EllesmereUIDB and EllesmereUIDB.fpsPos
                    if pos and pos.point then
                        fpsFrame:ClearAllPoints()
                        fpsFrame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
                    end
                end,
            }),
        })
    end)

    -- Register Secondary Stats as an unlock mode element
    C_Timer.After(1.5, function()
        if not EllesmereUI or not EllesmereUI.RegisterUnlockElements then return end
        local MK = EllesmereUI.MakeUnlockElement
        EllesmereUI:RegisterUnlockElements({
            MK({
                key = "EUI_SecondaryStats",
                label = "Secondary Stats",
                group = "General",
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
                noResize = true,
                savePos = function(key, point, relPoint, x, y)
                    if not EllesmereUIDB then EllesmereUIDB = {} end
                    if not point then return end
                    EllesmereUIDB.secondaryStatsPos = { point = point, relPoint = relPoint, x = x, y = y }
                    local f = EllesmereUI._getSecondaryStatsFrame and EllesmereUI._getSecondaryStatsFrame()
                    if f then
                        f:ClearAllPoints()
                        f:SetPoint(point, UIParent, relPoint or point, x or 0, y or 0)
                    end
                end,
                loadPos = function()
                    return EllesmereUIDB and EllesmereUIDB.secondaryStatsPos
                end,
                clearPos = function()
                    if EllesmereUIDB then EllesmereUIDB.secondaryStatsPos = nil end
                end,
                applyPos = function()
                    local f = EllesmereUI._getSecondaryStatsFrame and EllesmereUI._getSecondaryStatsFrame()
                    if not f then return end
                    local pos = EllesmereUIDB and EllesmereUIDB.secondaryStatsPos
                    if pos and pos.point then
                        f:ClearAllPoints()
                        f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
                    end
                end,
            }),
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
        if EllesmereUIDB.autoSellJunk ~= false then
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
            durWarnOverlay:SetScale(1)

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
    --  Runtime: Pixel-Perfect UI Scale (UIParent:SetScale)
    --  Scale is stored directly in EllesmereUIDB.ppUIScale as a decimal.
    --  Startup applies it early; this handler re-applies at PLAYER_ENTERING_WORLD
    --  to cover any Blizzard resets, and counter-scales our panel.
    ---------------------------------------------------------------------------
    do
        local function ApplyPPUIScale()
            local scale = EllesmereUIDB and EllesmereUIDB.ppUIScale
            if not scale then return end
            -- Snapshot panel scale before changing UIParent
            local mf = EllesmereUI._mainFrame
            local panelScaleBefore
            if mf then panelScaleBefore = mf:GetEffectiveScale() end
            EllesmereUI.PP.SetUIScale(scale)
            -- Counter-scale panel so it stays visually identical
            if mf and panelScaleBefore then
                local newEff = UIParent:GetEffectiveScale()
                if newEff > 0 then mf:SetScale(panelScaleBefore / newEff) end
            end
        end

        EllesmereUI._applyPPUIScale = ApplyPPUIScale

        local ppScaleFrame = CreateFrame("Frame")
        ppScaleFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        ppScaleFrame:SetScript("OnEvent", function(self)
            self:UnregisterEvent("PLAYER_ENTERING_WORLD")
            ApplyPPUIScale()
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

    ---------------------------------------------------------------------------
    --  Runtime: Character Crosshair
    ---------------------------------------------------------------------------
    do
        local PP = EllesmereUI.PanelPP
        local crosshairFrame
        local function CreateCrosshair()
            if crosshairFrame then return end
            crosshairFrame = CreateFrame("Frame", "EUI_CharacterCrosshair", UIParent)
            crosshairFrame:SetFrameStrata("HIGH")
            crosshairFrame:SetFrameLevel(100)
            crosshairFrame:EnableMouse(false)
            crosshairFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            crosshairFrame:SetSize(1, 1)

            local function MakeArm()
                local t = crosshairFrame:CreateTexture(nil, "OVERLAY")
                if t.SetSnapToPixelGrid then
                    t:SetSnapToPixelGrid(false)
                    t:SetTexelSnappingBias(0)
                end
                return t
            end
            crosshairFrame._hBar = MakeArm()
            crosshairFrame._vBar = MakeArm()
        end

        EllesmereUI._applyCrosshair = function()
            local size = EllesmereUIDB and EllesmereUIDB.crosshairSize or "None"
            if size == "None" then
                if crosshairFrame then crosshairFrame:Hide() end
                return
            end

            CreateCrosshair()

            local c = EllesmereUIDB and EllesmereUIDB.crosshairColor
            local cr = c and c.r or 1
            local cg = c and c.g or 1
            local cb = c and c.b or 1
            local ca = c and c.a or 0.75

            -- Thickness in logical pixels: Thin=1, Normal=2, Thick=3
            -- Do NOT use PP.Scale() on border/line thickness — raw pixel count
            local thickness = (size == "Thin") and 1 or (size == "Thick") and 3 or 2
            -- Arm length: 20 logical px each direction, snapped to physical pixels
            local ARM = PP.Scale(20)

            local hBar = crosshairFrame._hBar
            local vBar = crosshairFrame._vBar

            hBar:SetColorTexture(cr, cg, cb, ca)
            hBar:ClearAllPoints()
            hBar:SetPoint("LEFT",  crosshairFrame, "CENTER", -ARM, 0)
            hBar:SetPoint("RIGHT", crosshairFrame, "CENTER",  ARM, 0)
            hBar:SetHeight(thickness)

            vBar:SetColorTexture(cr, cg, cb, ca)
            vBar:ClearAllPoints()
            vBar:SetPoint("TOP",    crosshairFrame, "CENTER", 0,  ARM)
            vBar:SetPoint("BOTTOM", crosshairFrame, "CENTER", 0, -ARM)
            vBar:SetWidth(thickness)

            crosshairFrame:Show()
        end

        -- Apply on login
        C_Timer.After(1, function()
            if EllesmereUIDB and EllesmereUIDB.crosshairSize and EllesmereUIDB.crosshairSize ~= "None" then
                EllesmereUI._applyCrosshair()
            end
        end)
    end

    end  -- EUI_ExtrasRuntimeInit guard

    ---------------------------------------------------------------------------
    --  Profiles page
    ---------------------------------------------------------------------------

    -- Builds a red warning string from a decoded payload's meta vs current client.
    -- Returns nil if no mismatch.
    local function BuildScaleWarning(payload)
        if not payload or not payload.meta then return nil end
        local m = payload.meta
        local warnings = {}
        local myScale  = EllesmereUIDB and EllesmereUIDB.ppUIScale or (UIParent and UIParent:GetScale()) or 1
        local expScale = m.euiScale or m.uiScale
        if expScale and math.abs(myScale - expScale) > 0.02 then
            local expPct = math.floor(expScale * 100 + 0.5)
            local myPct  = math.floor(myScale  * 100 + 0.5)
            warnings[#warnings + 1] = "UI Scale Issue: Profile was made at " .. expPct .. "%, yours is " .. myPct .. "%"
        end
        local sw, sh = GetPhysicalScreenSize()
        local mySW  = sw and math.floor(sw) or 0
        local mySH  = sh and math.floor(sh) or 0
        local expSW = m.screenW or 0
        local expSH = m.screenH or 0
        if expSW > 0 and expSH > 0 and (mySW ~= expSW or mySH ~= expSH) then
            warnings[#warnings + 1] = "Resolution Issue: Profile was made at " .. expSW .. "x" .. expSH .. ", yours is " .. mySW .. "x" .. mySH
        end
        if #warnings == 0 then return nil end
        return "WARNING: Frame positions may be off.\n" .. table.concat(warnings, "\n")
    end

    local function BuildProfilesPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h
        local FONT = EllesmereUI.EXPRESSWAY
        local EG = EllesmereUI.ELLESMERE_GREEN
        local MEDIA = "Interface\\AddOns\\EllesmereUI\\media\\"

        -- Safety net: verify the active profile matches the current spec
        -- assignment. If the user opens settings while on the wrong profile
        -- (e.g. spec info was unavailable at login), correct it now.
        do
            local si = GetSpecialization and GetSpecialization() or 0
            local sid = si and si > 0 and GetSpecializationInfo(si) or nil
            if sid then
                local assigned = EllesmereUI.GetSpecProfile(sid)
                if assigned then
                    local current = EllesmereUI.GetActiveProfileName()
                    if assigned ~= current then
                        local _, profiles = EllesmereUI.GetProfileList()
                        if profiles and profiles[assigned] then
                            local fontWillChange = EllesmereUI.ProfileChangesFont(profiles[assigned])
                            EllesmereUI.SwitchProfile(assigned)
                            EllesmereUI.RefreshAllAddons()
                            if fontWillChange then
                                EllesmereUI:ShowConfirmPopup({
                                    title       = "Reload Required",
                                    message     = "Font changed. A UI reload is needed to apply the new font.",
                                    confirmText = "Reload Now",
                                    cancelText  = "Later",
                                    onConfirm   = function() ReloadUI() end,
                                })
                            end
                        end
                    end
                end
            end
        end

        parent._showRowDivider = false

        -- Button colours matching dropdown border style
        local _c = EllesmereUI.WB_COLOURS
        local PROF_BTN_COLOURS = {
            _c[1],  _c[2],  _c[3],  _c[4],   _c[5],  _c[6],  _c[7],  _c[8],
            1, 1, 1, EllesmereUI.DD_BRD_A,   1, 1, 1, EllesmereUI.DD_BRD_HA,
            _c[17], _c[18], _c[19], _c[20],  _c[21], _c[22], _c[23], _c[24],
        }

        _, h = W:Spacer(parent, y, 10);  y = y - h

        local function UniquePresetName(baseName)
            local _, profiles = EllesmereUI.GetProfileList()
            if not profiles[baseName] then return baseName end
            local n = 2
            while profiles[baseName .. " " .. n] do n = n + 1 end
            return baseName .. " " .. n
        end

        -- Shared dropdown builder (reused for profile dd and preset dd)
        local function MakeDropdown(parentFrame, w, h, getLabel)
            local btn = CreateFrame("Button", nil, parentFrame)
            PP.Size(btn, w, h)
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
            return btn, lbl, bg, brd
        end

        local function MakeDropdownMenu(anchor, w)
            local menu = CreateFrame("Frame", nil, UIParent)
            menu:SetFrameStrata("FULLSCREEN_DIALOG")
            menu:SetFrameLevel(200)
            menu:SetClampedToScreen(true)
            menu:SetSize(w, 4)
            menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
            menu:Hide()
            local bg = menu:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, 0.98)
            EllesmereUI.MakeBorder(menu, 1, 1, 1, EllesmereUI.DD_BRD_A, PP)
            menu:SetScript("OnShow", function(self)
                local s = anchor:GetEffectiveScale() / UIParent:GetEffectiveScale()
                self:SetScale(s)
                self:SetScript("OnUpdate", function(m)
                    if not anchor:IsMouseOver() and not m:IsMouseOver() then
                        if IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") then m:Hide() end
                    end
                end)
            end)
            menu:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
            return menu
        end

        local function MakeMenuItems(menu, items, onSelect)
            -- items = { { label, key } }
            local btns = {}
            for i, item in ipairs(items) do
                local itm = CreateFrame("Button", nil, menu)
                itm:SetHeight(26)
                itm:SetFrameLevel(menu:GetFrameLevel() + 1)
                local lbl = itm:CreateFontString(nil, "OVERLAY")
                lbl:SetFont(FONT, 13, EllesmereUI.GetFontOutlineFlag())
                lbl:SetPoint("LEFT", itm, "LEFT", 10, 0)
                lbl:SetJustifyH("LEFT")
                lbl:SetTextColor(1, 1, 1, EllesmereUI.TEXT_DIM_A)
                itm._lbl = lbl
                local hl = itm:CreateTexture(nil, "ARTWORK")
                hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 1); hl:SetAlpha(0)
                itm._hl = hl
                itm:SetScript("OnEnter", function() lbl:SetTextColor(1,1,1,1); hl:SetAlpha(EllesmereUI.DD_ITEM_HL_A) end)
                itm:SetScript("OnLeave", function()
                    lbl:SetTextColor(1, 1, 1, EllesmereUI.TEXT_DIM_A)
                    hl:SetAlpha(itm._isSel and EllesmereUI.DD_ITEM_SEL_A or 0)
                end)
                itm._lbl:SetText(item.label)
                local idx = i
                itm:SetScript("OnClick", function() menu:Hide(); onSelect(idx, item) end)
                btns[i] = itm
            end
            return btns
        end

        local function LayoutMenuItems(menu, btns, selIdx)
            local mH = 4
            for i, itm in ipairs(btns) do
                itm:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -mH)
                itm:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -1, -mH)
                itm._isSel = (i == selIdx)
                itm._hl:SetAlpha(itm._isSel and 0.04 or 0)
                itm:Show()
                mH = mH + 26
            end
            menu:SetHeight(mH + 4)
        end

        -------------------------------------------------------------------
        --  Row 1: Export Profile | Import Profile | Popular Presets (centered, no bg)
        -------------------------------------------------------------------
        _, h = W:Spacer(parent, y, 10);  y = y - h

        -- hoisted so the import callback can update it
        local ddLabel

        do
            local ROW_H  = 70
            local ITEM_H = 36
            local GAP    = 35
            local ITEM_W = 220

            local totalW = parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2
            local rowFrame = CreateFrame("Frame", nil, parent)
            PP.Size(rowFrame, totalW, ROW_H)
            PP.Point(rowFrame, "TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD, y)

            local groupW = ITEM_W * 3 + GAP * 2
            local startX = math.floor((totalW - groupW) / 2)

            -- Export Profile button
            local exportBtn = CreateFrame("Button", nil, rowFrame)
            PP.Size(exportBtn, ITEM_W, ITEM_H)
            PP.Point(exportBtn, "TOPLEFT", rowFrame, "TOPLEFT", startX, -math.floor((ROW_H - ITEM_H) / 2))
            exportBtn:SetFrameLevel(rowFrame:GetFrameLevel() + 2)
            EllesmereUI.MakeStyledButton(exportBtn, "Export Profile", 13, PROF_BTN_COLOURS, function()
                -- If CDM is loaded, show spec picker before exporting
                if C_AddOns.IsAddOnLoaded("EllesmereUICooldownManager") then
                    local specInfo = EllesmereUI.GetCDMSpecInfo()
                    if #specInfo > 0 then
                        for _, sp in ipairs(specInfo) do sp.checked = sp.hasData end
                        EllesmereUI:ShowCDMSpecPickerPopup({
                            title       = "Choose Your Included CDM Spell Assignments",
                            subtitle    = "Select all specs you want included with your exported profile",
                            confirmText = "Export",
                            specs       = specInfo,
                            onConfirm   = function(sel)
                                local str = EllesmereUI.ExportCurrentProfile(sel)
                                if str then EllesmereUI:ShowExportPopup(str) end
                            end,
                            onCancel    = function() end,
                        })
                        return
                    end
                end
                local str = EllesmereUI.ExportCurrentProfile()
                if str then EllesmereUI:ShowExportPopup(str) end
            end)

            -- Import Profile button
            local importBtn = CreateFrame("Button", nil, rowFrame)
            PP.Size(importBtn, ITEM_W, ITEM_H)
            PP.Point(importBtn, "TOPLEFT", exportBtn, "TOPRIGHT", GAP, 0)
            importBtn:SetFrameLevel(rowFrame:GetFrameLevel() + 2)
            EllesmereUI.MakeStyledButton(importBtn, "Import Profile", 13, PROF_BTN_COLOURS, function()
                EllesmereUI:ShowImportPopup(function(importStr)
                    -- Pre-decode to detect missing addons for the warning
                    local warnText
                    local payload = EllesmereUI.DecodeImportString(importStr)
                    if payload and payload.type == "full" and payload.data and payload.data.addons then
                        local missing = {}
                        local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or _G.IsAddOnLoaded
                        for _, entry in ipairs(EllesmereUI._ADDON_DB_MAP) do
                            if isLoaded and isLoaded(entry.folder) and not payload.data.addons[entry.folder] then
                                missing[#missing + 1] = entry.display
                            end
                        end
                        if #missing > 0 then
                            warnText = "Not included: " .. table.concat(missing, ", ")
                        end
                    end
                    -- Check UI scale and resolution mismatch
                    local scaleWarnText = BuildScaleWarning(payload)
                    EllesmereUI:ShowInputPopup({
                        title        = "Name This Profile",
                        message      = "Enter a name for the imported profile:",
                        placeholder  = "Imported Profile",
                        confirmText  = "Import",
                        cancelText   = "Cancel",
                        warning      = warnText,
                        scaleWarning = scaleWarnText,
                        onConfirm   = function(name)
                            if not name or name == "" then return end
                            -- Grab the imported CDM data for the spec picker
                            local importedCDMSnap
                            if C_AddOns.IsAddOnLoaded("EllesmereUICooldownManager") then
                                -- New format: spellAssignments on the payload data
                                if payload and payload.data and payload.data.spellAssignments then
                                    importedCDMSnap = payload.data.spellAssignments
                                -- Backward compat: legacy CDM addon data with specProfiles
                                elseif payload and payload.data and payload.data.addons then
                                    local cdm = payload.data.addons["EllesmereUICooldownManager"]
                                    if cdm and cdm.specProfiles then
                                        importedCDMSnap = { specProfiles = cdm.specProfiles, barGlows = cdm.barGlows }
                                    end
                                end
                            end

                            local ok, err, status = EllesmereUI.ImportProfile(importStr, name)

                            if ok and status == "spec_locked" then
                                EllesmereUI:ShowInfoPopup({
                                    title   = "Profile Imported",
                                    content = "\"" .. name .. "\" was saved but cannot be loaded because this spec has an assigned profile. Switch specs or remove the spec assignment to use it.",
                                })
                            elseif ok then
                                -- Show spec picker if imported data has CDM specProfiles
                                local importedSpecInfo = importedCDMSnap
                                    and EllesmereUI.GetImportedCDMSpecInfo(importedCDMSnap)
                                if importedSpecInfo and #importedSpecInfo > 0 then
                                    for _, sp in ipairs(importedSpecInfo) do sp.checked = true end
                                    local fontWillChange = EllesmereUI.ProfileChangesFont(payload and payload.data)
                                    EllesmereUI:ShowCDMSpecPickerPopup({
                                        title       = "Choose Your Included CDM Spell Assignments",
                                        subtitle    = "Select all specs you want included with your imported profile",
                                        confirmText = "Apply",
                                        specs       = importedSpecInfo,
                                        onConfirm   = function(sel)
                                            EllesmereUI.ApplyImportedSpecProfiles(importedCDMSnap, sel)
                                            -- Reload current spec to restore spell assignments;
                                            -- ApplyImportedSpecProfiles already handles overwriting
                                            -- selected specs, and LoadSpecProfile will load the
                                            -- (now-updated) data for the current spec.
                                            if _G._ECME_LoadSpecProfile and _G._ECME_GetCurrentSpecKey then
                                                local curKey = _G._ECME_GetCurrentSpecKey()
                                                if curKey then _G._ECME_LoadSpecProfile(curKey) end
                                            end
                                            EllesmereUI.RefreshAllAddons()
                                            ddLabel:SetText(EllesmereUI.GetActiveProfileName())
                                            if fontWillChange then
                                                EllesmereUI:ShowConfirmPopup({
                                                    title       = "Reload Required",
                                                    message     = "Font changed. A UI reload is needed to apply the new font.",
                                                    confirmText = "Reload Now",
                                                    cancelText  = "Later",
                                                    onConfirm   = function() ReloadUI() end,
                                                })
                                            else
                                                EllesmereUI:RefreshPage()
                                            end
                                        end,
                                        onCancel = function()
                                            -- User cancelled spec picker: reload current spec profile
                                            -- to restore spell assignments that ApplyProfileData overwrote
                                            if _G._ECME_LoadSpecProfile and _G._ECME_GetCurrentSpecKey then
                                                local curKey = _G._ECME_GetCurrentSpecKey()
                                                if curKey then _G._ECME_LoadSpecProfile(curKey) end
                                            end
                                            EllesmereUI.RefreshAllAddons()
                                            ddLabel:SetText(EllesmereUI.GetActiveProfileName())
                                            if fontWillChange then
                                                EllesmereUI:ShowConfirmPopup({
                                                    title       = "Reload Required",
                                                    message     = "Font changed. A UI reload is needed to apply the new font.",
                                                    confirmText = "Reload Now",
                                                    cancelText  = "Later",
                                                    onConfirm   = function() ReloadUI() end,
                                                })
                                            else
                                                EllesmereUI:RefreshPage()
                                            end
                                        end,
                                    })
                                else
                                    local fontWillChange = EllesmereUI.ProfileChangesFont(payload and payload.data)
                                    EllesmereUI.RefreshAllAddons()
                                    ddLabel:SetText(EllesmereUI.GetActiveProfileName())
                                    if fontWillChange then
                                        EllesmereUI:ShowConfirmPopup({
                                            title       = "Reload Required",
                                            message     = "Font changed. A UI reload is needed to apply the new font.",
                                            confirmText = "Reload Now",
                                            cancelText  = "Later",
                                            onConfirm   = function() ReloadUI() end,
                                        })
                                    else
                                        EllesmereUI:RefreshPage()
                                    end
                                end
                            else
                                EllesmereUI:ShowInfoPopup({ title = "Import Failed", content = err or "Unknown error" })
                            end
                        end,
                    })
                end)
            end)

            -- Shared helper: runs the same flow as Import (name popup + CDM spec picker)
            -- but skips the paste step since we already have the export string.
            local function DoPresetImportFlow(exportString, defaultName)
                if not exportString then return end
                local payload = EllesmereUI.DecodeImportString(exportString)

                -- Build missing-addon warning (same as import)
                local warnText
                if payload and payload.type == "full" and payload.data and payload.data.addons then
                    local missing = {}
                    local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or _G.IsAddOnLoaded
                    for _, entry in ipairs(EllesmereUI._ADDON_DB_MAP) do
                        if isLoaded and isLoaded(entry.folder) and not payload.data.addons[entry.folder] then
                            missing[#missing + 1] = entry.display
                        end
                    end
                    if #missing > 0 then
                        warnText = "Not included: " .. table.concat(missing, ", ")
                    end
                end
                local scaleWarnText = BuildScaleWarning(payload)

                EllesmereUI:ShowInputPopup({
                    title        = "Name This Profile",
                    message      = "Enter a name for the preset profile:",
                    placeholder  = defaultName or "Preset Profile",
                    confirmText  = "Import",
                    cancelText   = "Cancel",
                    warning      = warnText,
                    scaleWarning = scaleWarnText,
                    onConfirm    = function(name)
                        if not name or name == "" then return end

                        local importedCDMSnap
                        if C_AddOns.IsAddOnLoaded("EllesmereUICooldownManager") then
                            -- New format: spellAssignments on the payload data
                            if payload and payload.data and payload.data.spellAssignments then
                                importedCDMSnap = payload.data.spellAssignments
                            -- Backward compat: legacy CDM addon data with specProfiles
                            elseif payload and payload.data and payload.data.addons then
                                local cdm = payload.data.addons["EllesmereUICooldownManager"]
                                if cdm and cdm.specProfiles then
                                    importedCDMSnap = { specProfiles = cdm.specProfiles, barGlows = cdm.barGlows }
                                end
                            end
                        end

                        local ok, err, status = EllesmereUI.ImportProfile(exportString, name)

                        if ok and status == "spec_locked" then
                            EllesmereUI:ShowInfoPopup({
                                title   = "Profile Imported",
                                content = "\"" .. name .. "\" was saved but cannot be loaded because this spec has an assigned profile. Switch specs or remove the spec assignment to use it.",
                            })
                        elseif ok then
                            local importedSpecInfo = importedCDMSnap
                                and EllesmereUI.GetImportedCDMSpecInfo(importedCDMSnap)
                            if importedSpecInfo and #importedSpecInfo > 0 then
                                for _, sp in ipairs(importedSpecInfo) do sp.checked = true end
                                local fontWillChange = EllesmereUI.ProfileChangesFont(payload and payload.data)
                                EllesmereUI:ShowCDMSpecPickerPopup({
                                    title       = "Choose Your Included CDM Spell Assignments",
                                    subtitle    = "Select all specs you want included with your imported profile",
                                    confirmText = "Apply",
                                    specs       = importedSpecInfo,
                                    onConfirm   = function(sel)
                                        EllesmereUI.ApplyImportedSpecProfiles(importedCDMSnap, sel)
                                        if _G._ECME_LoadSpecProfile and _G._ECME_GetCurrentSpecKey then
                                            local curKey = _G._ECME_GetCurrentSpecKey()
                                            if curKey then _G._ECME_LoadSpecProfile(curKey) end
                                        end
                                        EllesmereUI.RefreshAllAddons()
                                        ddLabel:SetText(EllesmereUI.GetActiveProfileName())
                                        if fontWillChange then
                                            EllesmereUI:ShowConfirmPopup({
                                                title       = "Reload Required",
                                                message     = "Font changed. A UI reload is needed to apply the new font.",
                                                confirmText = "Reload Now",
                                                cancelText  = "Later",
                                                onConfirm   = function() ReloadUI() end,
                                            })
                                        else
                                            EllesmereUI:RefreshPage()
                                        end
                                    end,
                                    onCancel = function()
                                        if _G._ECME_LoadSpecProfile and _G._ECME_GetCurrentSpecKey then
                                            local curKey = _G._ECME_GetCurrentSpecKey()
                                            if curKey then _G._ECME_LoadSpecProfile(curKey) end
                                        end
                                        EllesmereUI.RefreshAllAddons()
                                        ddLabel:SetText(EllesmereUI.GetActiveProfileName())
                                        if fontWillChange then
                                            EllesmereUI:ShowConfirmPopup({
                                                title       = "Reload Required",
                                                message     = "Font changed. A UI reload is needed to apply the new font.",
                                                confirmText = "Reload Now",
                                                cancelText  = "Later",
                                                onConfirm   = function() ReloadUI() end,
                                            })
                                        else
                                            EllesmereUI:RefreshPage()
                                        end
                                    end,
                                })
                            else
                                local fontWillChange = EllesmereUI.ProfileChangesFont(payload and payload.data)
                                EllesmereUI.RefreshAllAddons()
                                ddLabel:SetText(EllesmereUI.GetActiveProfileName())
                                if fontWillChange then
                                    EllesmereUI:ShowConfirmPopup({
                                        title       = "Reload Required",
                                        message     = "Font changed. A UI reload is needed to apply the new font.",
                                        confirmText = "Reload Now",
                                        cancelText  = "Later",
                                        onConfirm   = function() ReloadUI() end,
                                    })
                                else
                                    EllesmereUI:RefreshPage()
                                end
                            end
                        else
                            EllesmereUI:ShowInfoPopup({ title = "Import Failed", content = err or "Unknown error" })
                        end
                    end,
                })
            end

            -- Popular Presets dropdown (label always stays "Popular Presets")
            do
                local presetEntries = {}
                presetEntries[#presetEntries + 1] = {
                    label = "Spin the Wheel",
                    onApply = function()
                        -- Snapshot before randomizing so the original profile
                        -- isn't corrupted for other characters sharing it.
                        local origName = EllesmereUI.GetActiveProfileName()
                        local origSnap = EllesmereUI.SnapshotAllAddons()
                        EllesmereUI.SpinTheWheel()
                        local newName = UniquePresetName("Spin the Wheel")
                        EllesmereUI.SaveCurrentAsProfile(newName)
                        -- Restore original profile data so the shared AceDB
                        -- tables are clean when SavedVariables flush on reload.
                        local pdb = EllesmereUI.GetProfilesDB and EllesmereUI.GetProfilesDB()
                        if pdb then pdb.profiles[origName] = origSnap end
                        EllesmereUI:ShowConfirmPopup({
                            title       = "Reload Required",
                            message     = "Preset applied. Reload to apply.",
                            confirmText = "Reload Now",
                            cancelText  = "Cancel",
                            onConfirm   = function() ReloadUI() end,
                        })
                    end,
                }
                if EllesmereUI.WEEKLY_SPOTLIGHT then
                    local spot = EllesmereUI.WEEKLY_SPOTLIGHT
                    presetEntries[#presetEntries + 1] = {
                        label = "Weekly Spotlight: " .. spot.name,
                        onApply = function()
                            DoPresetImportFlow(spot.exportString, "Weekly: " .. spot.name)
                        end,
                    }
                end
                for _, preset in ipairs(EllesmereUI.POPULAR_PRESETS) do
                    if preset.exportString then
                        local p = preset
                        presetEntries[#presetEntries + 1] = {
                            label = p.name,
                            onApply = function()
                                DoPresetImportFlow(p.exportString, p.name)
                            end,
                        }
                    end
                end

                local ddBtn = CreateFrame("Button", nil, rowFrame)
                PP.Size(ddBtn, ITEM_W, ITEM_H)
                PP.Point(ddBtn, "TOPLEFT", importBtn, "TOPRIGHT", GAP, 0)
                ddBtn:SetFrameLevel(rowFrame:GetFrameLevel() + 2)

                local ddBg = ddBtn:CreateTexture(nil, "BACKGROUND")
                ddBg:SetAllPoints()
                ddBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
                local ddBrd = EllesmereUI.MakeBorder(ddBtn, 1, 1, 1, EllesmereUI.DD_BRD_A, PP)

                local ddLbl = EllesmereUI.MakeFont(ddBtn, 13, nil, 1, 1, 1)
                ddLbl:SetAlpha(EllesmereUI.DD_TXT_A)
                ddLbl:SetJustifyH("LEFT")
                ddLbl:SetWordWrap(false)
                ddLbl:SetMaxLines(1)
                ddLbl:SetPoint("LEFT",  ddBtn, "LEFT",  12, 0)
                local ddArrow = EllesmereUI.MakeDropdownArrow(ddBtn, 12, PP)
                ddLbl:SetPoint("RIGHT", ddArrow, "LEFT", -5, 0)
                ddLbl:SetText("Popular Presets")

                local pS = EllesmereUI.RD_DD_COLOURS

                local menu = MakeDropdownMenu(ddBtn, ITEM_W)
                local menuBtns = MakeMenuItems(menu, presetEntries, function(idx, entry)
                    entry.onApply()
                end)

                local function PresetApplyNormal()
                    ddLbl:SetTextColor(pS[17], pS[18], pS[19], pS[20])
                    ddBrd:SetColor(pS[9], pS[10], pS[11], pS[12])
                    ddBg:SetColorTexture(pS[1], pS[2], pS[3], pS[4])
                end
                local function PresetApplyHover()
                    ddLbl:SetTextColor(pS[21], pS[22], pS[23], pS[24])
                    ddBrd:SetColor(pS[13], pS[14], pS[15], pS[16])
                    ddBg:SetColorTexture(pS[5], pS[6], pS[7], pS[8])
                end

                ddBtn:SetScript("OnClick", function()
                    if menu:IsShown() then menu:Hide()
                    else LayoutMenuItems(menu, menuBtns, 0); menu:Show() end
                end)
                ddBtn:SetScript("OnEnter", function() PresetApplyHover() end)
                ddBtn:SetScript("OnLeave", function()
                    if not menu:IsShown() then PresetApplyNormal() end
                end)
                ddBtn:HookScript("OnHide", function() menu:Hide() end)
                menu:HookScript("OnShow", function()
                    PresetApplyHover()
                end)
                menu:SetScript("OnHide", function(self)
                    self:SetScript("OnUpdate", nil)
                    if ddBtn:IsMouseOver() then PresetApplyHover()
                    else PresetApplyNormal() end
                end)
            end

            y = y - ROW_H
        end

        -------------------------------------------------------------------
        --  Row 2: Active Profile dropdown | Save As | Assign to Spec (centered, no bg)
        -------------------------------------------------------------------
        do
            local ROW_H  = 50
            local ITEM_H = 30
            local GAP    = 15
            local BTN_W  = 110
            local DD_W   = 220

            local totalW = parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2
            local rowFrame = CreateFrame("Frame", nil, parent)
            PP.Size(rowFrame, totalW, ROW_H)
            PP.Point(rowFrame, "TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD, y)

            local groupW = DD_W + GAP * 3 + BTN_W * 3
            local startX = math.floor((totalW - groupW) / 2)
            local offsetY = -math.floor((ROW_H - ITEM_H) / 2)

            -- Active Profile dropdown (no X on the field)
            local ddBtn = CreateFrame("Button", nil, rowFrame)
            EllesmereUI._profileDDBtn = ddBtn
            PP.Size(ddBtn, DD_W, ITEM_H)
            PP.Point(ddBtn, "TOPLEFT", rowFrame, "TOPLEFT", startX, offsetY)
            ddBtn:SetFrameLevel(rowFrame:GetFrameLevel() + 2)

            local ddBg = ddBtn:CreateTexture(nil, "BACKGROUND")
            ddBg:SetAllPoints()
            ddBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
            local ddBrd = EllesmereUI.MakeBorder(ddBtn, 1, 1, 1, EllesmereUI.DD_BRD_A, PP)

            ddLabel = EllesmereUI.MakeFont(ddBtn, 13, nil, 1, 1, 1)
            ddLabel:SetAlpha(EllesmereUI.DD_TXT_A)
            ddLabel:SetJustifyH("LEFT")
            ddLabel:SetWordWrap(false)
            ddLabel:SetMaxLines(1)
            ddLabel:SetPoint("LEFT",  ddBtn, "LEFT",  12, 0)
            local ddArrow2 = EllesmereUI.MakeDropdownArrow(ddBtn, 12, PP)
            ddLabel:SetPoint("RIGHT", ddArrow2, "LEFT", -5, 0)
            ddLabel:SetText(EllesmereUI.GetActiveProfileName())

            local aS = EllesmereUI.RD_DD_COLOURS

            local menu = MakeDropdownMenu(ddBtn, DD_W)
            local X_SZ = 14
            local menuItems = {}

            -- Format a keybind string for display (e.g. "CTRL-SHIFT-F" -> "Ctrl + Shift + F")
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

            -- Keybind popup for a profile (same style as party mode keybind)
            local _kbPopup
            local function ShowProfileKeybindPopup(profileName)
                if _kbPopup then _kbPopup:Hide() end

                local POPUP_W, POPUP_H = 320, 130

                -- Full-screen dimmer (click outside to close)
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
                title:SetText("Keybind: " .. profileName)

                local KB_W, KB_H = 160, 30
                local kbBtn = CreateFrame("Button", nil, popup)
                PP.Size(kbBtn, KB_W, KB_H)
                kbBtn:SetPoint("CENTER", popup, "CENTER", 0, -2)
                kbBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
                kbBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                local kbBg = EllesmereUI.SolidTex(kbBtn, "BACKGROUND", EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
                kbBg:SetAllPoints()
                kbBtn._border = EllesmereUI.MakeBorder(kbBtn, 1, 1, 1, EllesmereUI.DD_BRD_A, PP)
                local kbLbl = EllesmereUI.MakeFont(kbBtn, 13, nil, 1, 1, 1)
                kbLbl:SetAlpha(EllesmereUI.DD_TXT_A or 0.85)
                kbLbl:SetPoint("CENTER")

                local function RefreshLabel()
                    local key = EllesmereUI.GetProfileKeybind(profileName)
                    kbLbl:SetText(FormatKey(key))
                end
                RefreshLabel()

                local hint = EllesmereUI.MakeFont(popup, 10, nil, 1, 1, 1, 0.35)
                hint:SetPoint("BOTTOM", popup, "BOTTOM", 0, 12)
                hint:SetText("Left-click to set  |  Right-click to unbind  |  Esc to close")

                local listening = false

                kbBtn:SetScript("OnClick", function(self, button)
                    if button == "RightButton" then
                        if listening then
                            listening = false
                            self:EnableKeyboard(false)
                        end
                        EllesmereUI.SetProfileKeybind(profileName, nil)
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
                        if key == "ESCAPE" then
                            self:SetPropagateKeyboardInput(false)
                            dimmer:Hide()
                            return
                        end
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

                    EllesmereUI.SetProfileKeybind(profileName, fullKey)
                    listening = false
                    self:EnableKeyboard(false)
                    RefreshLabel()
                end)

                kbBtn:SetScript("OnEnter", function()
                    kbBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_HA or 0.98)
                    if kbBtn._border and kbBtn._border.SetColor then
                        kbBtn._border:SetColor(1, 1, 1, 0.3)
                    end
                    EllesmereUI.ShowWidgetTooltip(kbBtn, "Left-click to set a keybind.\nRight-click to unbind.")
                end)
                kbBtn:SetScript("OnLeave", function()
                    if listening then return end
                    kbBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
                    if kbBtn._border and kbBtn._border.SetColor then
                        kbBtn._border:SetColor(1, 1, 1, EllesmereUI.DD_BRD_A)
                    end
                    EllesmereUI.HideWidgetTooltip()
                end)

                popup:SetScript("OnHide", function()
                    if listening then
                        listening = false
                        kbBtn:EnableKeyboard(false)
                    end
                    if popup._dimmer then popup._dimmer:Hide() end
                    _kbPopup = nil
                end)

                -- Close on Escape when not listening on the button
                popup:EnableKeyboard(true)
                popup:SetScript("OnKeyDown", function(self, key)
                    if key == "ESCAPE" and not listening then
                        self:SetPropagateKeyboardInput(false)
                        dimmer:Hide()
                    else
                        self:SetPropagateKeyboardInput(true)
                    end
                end)

                dimmer:Show()
            end

            local function RebuildProfileMenu()
                for _, itm in ipairs(menuItems) do itm:Hide() end
                local order, profiles = EllesmereUI.GetProfileList()
                local mH = 4
                local idx = 0
                local activeName = EllesmereUI.GetActiveProfileName()
                -- Determine if current spec has an assigned profile
                local specAssigned
                do
                    local si = GetSpecialization and GetSpecialization() or 0
                    local sid = si and si > 0 and GetSpecializationInfo(si) or nil
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

                            local kbBtn = CreateFrame("Button", nil, itm)
                            kbBtn:SetSize(X_SZ, X_SZ)
                            kbBtn:SetPoint("RIGHT", xBtn, "LEFT", -4, 0)
                            kbBtn:SetFrameLevel(itm:GetFrameLevel() + 2)
                            local kbIcon = kbBtn:CreateTexture(nil, "OVERLAY")
                            kbIcon:SetAllPoints()
                            if kbIcon.SetSnapToPixelGrid then kbIcon:SetSnapToPixelGrid(false); kbIcon:SetTexelSnappingBias(0) end
                            kbIcon:SetTexture(MEDIA .. "icons\\eui-keybind-2.png")
                            kbBtn:SetAlpha(0.4)
                            itm._kbBtn = kbBtn

                            local function IsOverInlineBtn()
                                return xBtn:IsMouseOver() or kbBtn:IsMouseOver()
                            end

                            local function SetAllInlineAlpha(a)
                                xBtn:SetAlpha(a); kbBtn:SetAlpha(a)
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
                                EllesmereUI.ShowWidgetTooltip(self, "Delete")
                            end)
                            xBtn:SetScript("OnLeave", function(self)
                                InlineBtnLeave(self)
                                EllesmereUI.HideWidgetTooltip()
                            end)
                            kbBtn:SetScript("OnEnter", function(self)
                                InlineBtnEnter(self)
                                EllesmereUI.ShowWidgetTooltip(self, "Keybind")
                            end)
                            kbBtn:SetScript("OnLeave", function(self)
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
                            -- Disable: dim label, hide X, edit, and keybind, block clicks, show tooltip
                            itm._lbl:SetTextColor(1, 1, 1, 0.25)
                            itm._xBtn:Hide()
                            itm._editBtn:Hide()
                            itm._kbBtn:Hide()
                            itm:SetScript("OnClick", nil)
                            itm:SetScript("OnEnter", function()
                                EllesmereUI.ShowWidgetTooltip(itm, "Your current spec has an assigned profile so you cannot switch to another. Please unassign to switch.")
                            end)
                            itm:SetScript("OnLeave", function()
                                EllesmereUI.HideWidgetTooltip()
                            end)
                        else
                            local iLbl, iHl, iXBtn, iEditBtn, iKbBtn = itm._lbl, itm._hl, itm._xBtn, itm._editBtn, itm._kbBtn
                            iLbl:SetTextColor(1, 1, 1, EllesmereUI.TEXT_DIM_A)
                            iEditBtn:Hide()  -- rename disabled; name is set at creation
                            if capName == "Default" then
                                iXBtn:Hide()
                                iKbBtn:Hide()
                            else
                                iXBtn:Show()
                                iKbBtn:Show()
                            end
                            local function IsOverInline()
                                return iXBtn:IsMouseOver() or iKbBtn:IsMouseOver()
                            end
                            local function SetAllAlpha(a)
                                iXBtn:SetAlpha(a); iKbBtn:SetAlpha(a)
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
                                if capName == activeName then return end  -- already active, do nothing
                                menu:Hide()
                                local _, profiles = EllesmereUI.GetProfileList()
                                local fontWillChange = EllesmereUI.ProfileChangesFont(profiles and profiles[capName])
                                EllesmereUI.SwitchProfile(capName)
                                ddLabel:SetText(EllesmereUI.GetActiveProfileName())
                                EllesmereUI.RefreshAllAddons()
                                if fontWillChange then
                                    EllesmereUI:ShowConfirmPopup({
                                        title       = "Reload Required",
                                        message     = "Font changed. A UI reload is needed to apply the new font.",
                                        confirmText = "Reload Now",
                                        cancelText  = "Later",
                                        onConfirm   = function() ReloadUI() end,
                                    })
                                else
                                    EllesmereUI:RefreshPage()
                                end
                            end)
                            iXBtn:SetScript("OnClick", function()
                                if capName == "Default" then return end
                                menu:Hide()
                                EllesmereUI:ShowConfirmPopup({
                                    title       = "Delete Profile",
                                    message     = "Delete \"" .. capName .. "\"?",
                                    confirmText = "Delete",
                                    cancelText  = "Cancel",
                                    onConfirm   = function()
                                        local wasActive = (capName == EllesmereUI.GetActiveProfileName())
                                        EllesmereUI.DeleteProfile(capName)
                                        if wasActive then
                                            EllesmereUI.SwitchProfile("Default")
                                            EllesmereUI.RefreshAllAddons()
                                        end
                                        ddLabel:SetText(EllesmereUI.GetActiveProfileName())
                                        EllesmereUI:InvalidatePageCache()
                                        EllesmereUI:RefreshPage(true)
                                    end,
                                })
                            end)
                            iKbBtn:SetScript("OnClick", function()
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
                ddLabel:SetTextColor(aS[17], aS[18], aS[19], aS[20])
                ddBrd:SetColor(aS[9], aS[10], aS[11], aS[12])
                ddBg:SetColorTexture(aS[1], aS[2], aS[3], aS[4])
            end
            local function ActiveApplyHover()
                ddLabel:SetTextColor(aS[21], aS[22], aS[23], aS[24])
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

            -- Assign to Spec button
            local assignBtn = CreateFrame("Button", nil, rowFrame)
            PP.Size(assignBtn, BTN_W, ITEM_H)
            PP.Point(assignBtn, "LEFT", ddBtn, "RIGHT", GAP, 0)
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
                local activeName = EllesmereUI.GetActiveProfileName()
                EllesmereUI:ShowSpecAssignPopup({
                    db = tempDB,
                    dbKey = "_profileSpecs",
                    presetKey = activeName,
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

            -- Copy Profile button
            local saveAsBtn = CreateFrame("Button", nil, rowFrame)
            PP.Size(saveAsBtn, BTN_W, ITEM_H)
            PP.Point(saveAsBtn, "LEFT", assignBtn, "RIGHT", GAP, 0)
            saveAsBtn:SetFrameLevel(rowFrame:GetFrameLevel() + 2)
            EllesmereUI.MakeStyledButton(saveAsBtn, "Copy Profile", 11, PROF_BTN_COLOURS, function()
                EllesmereUI:ShowInputPopup({
                    title       = "Copy Profile",
                    message     = "Enter a name for the new profile:",
                    placeholder = "My Profile",
                    confirmText = "Save",
                    cancelText  = "Cancel",
                    onConfirm   = function(name)
                        if not name or name == "" then return end
                        EllesmereUI.SaveCurrentAsProfile(name)
                        ReloadUI()
                    end,
                })
            end)

            y = y - ROW_H
        end

        -------------------------------------------------------------------
        --  Shared: Check All / Uncheck All link builder
        -------------------------------------------------------------------
        local function BuildCheckLinks(anchorFrame, items, refreshAll)
            local FONT_L = EllesmereUI.EXPRESSWAY
            local LINK_GAP = 16
            local checkAllBtn = CreateFrame("Button", nil, anchorFrame)
            checkAllBtn:SetFrameLevel(anchorFrame:GetFrameLevel() + 2)
            local checkAllLbl = checkAllBtn:CreateFontString(nil, "OVERLAY")
            checkAllLbl:SetFont(FONT_L, 12, "")
            checkAllLbl:SetText("Check All")
            checkAllLbl:SetTextColor(1, 1, 1, 0.40)
            checkAllLbl:SetPoint("CENTER")
            checkAllBtn:SetSize(checkAllLbl:GetStringWidth() + 4, 18)
            PP.Point(checkAllBtn, "BOTTOMRIGHT", anchorFrame, "BOTTOMRIGHT", -LINK_GAP - 70, 8)
            checkAllBtn:SetScript("OnEnter", function() checkAllLbl:SetTextColor(1, 1, 1, 0.80) end)
            checkAllBtn:SetScript("OnLeave", function() checkAllLbl:SetTextColor(1, 1, 1, 0.40) end)
            checkAllBtn:SetScript("OnClick", function()
                for _, item in ipairs(items) do
                    if item.enabled ~= false then item.setVal(true) end
                end
                if refreshAll then refreshAll() end
            end)

            local linkDiv = anchorFrame:CreateTexture(nil, "OVERLAY", nil, 7)
            linkDiv:SetColorTexture(1, 1, 1, 0.15)
            if linkDiv.SetSnapToPixelGrid then linkDiv:SetSnapToPixelGrid(false); linkDiv:SetTexelSnappingBias(0) end
            PP.Point(linkDiv, "LEFT", checkAllBtn, "RIGHT", LINK_GAP / 2, 0)
            linkDiv:SetWidth(1)
            linkDiv:SetHeight(10)

            local uncheckAllBtn = CreateFrame("Button", nil, anchorFrame)
            uncheckAllBtn:SetFrameLevel(anchorFrame:GetFrameLevel() + 2)
            local uncheckAllLbl = uncheckAllBtn:CreateFontString(nil, "OVERLAY")
            uncheckAllLbl:SetFont(FONT_L, 12, "")
            uncheckAllLbl:SetText("Uncheck All")
            uncheckAllLbl:SetTextColor(1, 1, 1, 0.40)
            uncheckAllLbl:SetPoint("CENTER")
            uncheckAllBtn:SetSize(uncheckAllLbl:GetStringWidth() + 4, 18)
            PP.Point(uncheckAllBtn, "LEFT", checkAllBtn, "RIGHT", LINK_GAP, 0)
            uncheckAllBtn:SetScript("OnEnter", function() uncheckAllLbl:SetTextColor(1, 1, 1, 0.80) end)
            uncheckAllBtn:SetScript("OnLeave", function() uncheckAllLbl:SetTextColor(1, 1, 1, 0.40) end)
            uncheckAllBtn:SetScript("OnClick", function()
                for _, item in ipairs(items) do
                    if item.enabled ~= false then item.setVal(false) end
                end
                if refreshAll then refreshAll() end
            end)
        end

        -- Shared: error flash on a MakeBorder object (red highlight that fades)
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
        --[[ PER-ADDON EXPORT DISABLED
        -------------------------------------------------------------------
        local perAddonHeader
        perAddonHeader, h = W:SectionHeader(parent, "PER-ADDON EXPORT", y);  y = y - h

        -- 4-column checkbox grid for addon selection
        local selectedAddons = {}
        local addonGridVisuals = {}
        do
            local ADDON_DB_MAP_LOCAL = EllesmereUI._ADDON_DB_MAP
            local GRID_COLS  = 4
            local GRID_ROW_H = 50
            local GRID_BOX_SZ = 18
            local GRID_PAD   = EllesmereUI.CONTENT_PAD or 16
            local GRID_SIDE  = 20
            local EG = EllesmereUI.ELLESMERE_GREEN or { r=0.047, g=0.824, b=0.624 }

            -- Build item list: loaded addons first, then disabled stubs
            local gridItems = {}
            for _, entry in ipairs(ADDON_DB_MAP_LOCAL) do
                if C_AddOns.IsAddOnLoaded(entry.folder) then
                    local folder = entry.folder
                    gridItems[#gridItems + 1] = {
                        label   = entry.display,
                        enabled = true,
                        getVal  = function() return selectedAddons[folder] or false end,
                        setVal  = function(v)
                            selectedAddons[folder] = v or nil
                        end,
                    }
                end
            end
            -- Coming Soon stubs
            for _, stub in ipairs({ "Raid Frames", "Basics" }) do
                gridItems[#gridItems + 1] = {
                    label   = stub,
                    enabled = false,
                    getVal  = function() return false end,
                    setVal  = function() end,
                }
            end

            -- Check All / Uncheck All links on the section header
            local function RefreshAddonGrid()
                for _, fn in ipairs(addonGridVisuals) do fn() end
            end
            BuildCheckLinks(perAddonHeader, gridItems, RefreshAddonGrid)

            local totalW = parent:GetWidth() - GRID_PAD * 2
            local colW   = math.floor(totalW / GRID_COLS)
            local totalRows = math.ceil(#gridItems / GRID_COLS)

            for row = 0, totalRows - 1 do
                local rowFrame = CreateFrame("Frame", nil, parent)
                PP.Size(rowFrame, totalW, GRID_ROW_H)
                PP.Point(rowFrame, "TOPLEFT", parent, "TOPLEFT", GRID_PAD, y - row * GRID_ROW_H)
                rowFrame._skipRowDivider = true
                EllesmereUI.RowBg(rowFrame, parent)

                for d = 1, GRID_COLS - 1 do
                    local div = rowFrame:CreateTexture(nil, "ARTWORK")
                    div:SetColorTexture(1, 1, 1, 0.06)
                    if div.SetSnapToPixelGrid then div:SetSnapToPixelGrid(false); div:SetTexelSnappingBias(0) end
                    div:SetWidth(1)
                    PP.Point(div, "TOP",    rowFrame, "TOPLEFT", d * colW, 0)
                    PP.Point(div, "BOTTOM", rowFrame, "BOTTOMLEFT", d * colW, 0)
                end

                for col = 0, GRID_COLS - 1 do
                    local idx = row * GRID_COLS + col + 1
                    local item = gridItems[idx]
                    if not item then break end

                    local cell = CreateFrame("Frame", nil, rowFrame)
                    cell:SetSize(colW, GRID_ROW_H)
                    cell:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", col * colW, 0)

                    local label = EllesmereUI.MakeFont(cell, 13, nil, 1, 1, 1)
                    label:SetPoint("LEFT", cell, "LEFT", GRID_SIDE, 0)
                    label:SetText(item.label)

                    local box = CreateFrame("Frame", nil, cell)
                    box:SetSize(GRID_BOX_SZ, GRID_BOX_SZ)
                    box:SetPoint("RIGHT", cell, "RIGHT", -GRID_SIDE, 0)

                    local boxBg = box:CreateTexture(nil, "BACKGROUND")
                    boxBg:SetAllPoints()
                    boxBg:SetColorTexture(0.12, 0.12, 0.14, 1)
                    if boxBg.SetSnapToPixelGrid then boxBg:SetSnapToPixelGrid(false); boxBg:SetTexelSnappingBias(0) end

                    local boxBrd = EllesmereUI.MakeBorder(box, 0.25, 0.25, 0.28, 0.6, EllesmereUI.PanelPP)

                    local check = box:CreateTexture(nil, "ARTWORK")
                    check:SetPoint("TOPLEFT", box, "TOPLEFT", 3, -3)
                    check:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -3, 3)
                    check:SetColorTexture(EG.r, EG.g, EG.b, 1)
                    if check.SetSnapToPixelGrid then check:SetSnapToPixelGrid(false); check:SetTexelSnappingBias(0) end

                    if not item.enabled then
                        -- Coming Soon: dim everything, no interaction
                        label:SetAlpha(0.3)
                        box:SetAlpha(0.3)
                        check:Hide()
                        local block = CreateFrame("Frame", nil, cell)
                        block:SetAllPoints()
                        block:SetFrameLevel(cell:GetFrameLevel() + 5)
                        block:EnableMouse(true)
                        block:SetScript("OnEnter", function()
                            EllesmereUI.ShowWidgetTooltip(cell, EllesmereUI.DisabledTooltip and EllesmereUI.DisabledTooltip("Coming Soon") or "Coming Soon")
                        end)
                        block:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                    else
                        local btn = CreateFrame("Button", nil, cell)
                        btn:SetAllPoints(cell)
                        btn:SetFrameLevel(cell:GetFrameLevel() + 2)

                        local function ApplyVisual()
                            local on = item.getVal()
                            if on then
                                check:Show(); label:SetAlpha(1)
                                boxBrd:SetColor(EG.r, EG.g, EG.b, 0.15)
                            else
                                check:Hide(); label:SetAlpha(0.5)
                                boxBrd:SetColor(0.25, 0.25, 0.28, 0.6)
                            end
                        end
                        ApplyVisual()
                        addonGridVisuals[#addonGridVisuals + 1] = ApplyVisual

                        btn:SetScript("OnClick", function()
                            item.setVal(not item.getVal())
                            ApplyVisual()
                        end)
                        btn:SetScript("OnEnter", function() if not item.getVal() then label:SetAlpha(0.8) end end)
                        btn:SetScript("OnLeave", function() if not item.getVal() then label:SetAlpha(0.5) end end)
                    end
                end
            end

            y = y - totalRows * GRID_ROW_H
        end

        -- Extra spacing before Export button
        _, h = W:Spacer(parent, y, 10);  y = y - h

        -- Export Selected Addons button (with error flash when nothing selected)
        do
            local BTN_W = 450
            local BTN_H = 42
            local ROW_H_E = BTN_H + 20
            local btnFrame = CreateFrame("Frame", nil, parent)
            PP.Size(btnFrame, parent:GetWidth() - (EllesmereUI.CONTENT_PAD or 16) * 2, ROW_H_E)
            PP.Point(btnFrame, "TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD or 16, y)
            local exportAddonBtn = CreateFrame("Button", nil, btnFrame)
            PP.Size(exportAddonBtn, BTN_W, BTN_H)
            PP.Point(exportAddonBtn, "CENTER", btnFrame, "CENTER", 0, 0)
            exportAddonBtn:SetFrameLevel(btnFrame:GetFrameLevel() + 1)
            local eaBg, eaBrd, eaLbl = EllesmereUI.MakeStyledButton(exportAddonBtn, "Export Selected Addons", 14, EllesmereUI.WB_COLOURS, function()
                local folders = {}
                for folder in pairs(selectedAddons) do folders[#folders + 1] = folder end
                if #folders == 0 then
                    if exportAddonBtn._flashError then exportAddonBtn._flashError() end
                    return
                end
                local str = EllesmereUI.ExportAddons(folders)
                if str then EllesmereUI:ShowExportPopup(str) end
            end)
            exportAddonBtn._flashError = BuildErrorFlash(exportAddonBtn, eaBrd)
            y = y - ROW_H_E
        end
        --]] -- END PER-ADDON EXPORT DISABLED

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
        pages       = { PAGE_GENERAL, PAGE_PROFILES, PAGE_CORE, PAGE_COLORS, "Disable Addons" },
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
            -- Reset all custom class, power, and resource colors to defaults
            if EllesmereUIDB then
                EllesmereUIDB.customColors = nil
            end
            -- Reset fonts to defaults
            if EllesmereUIDB then
                EllesmereUIDB.fonts = nil
            end
            EllesmereUI.ApplyColorsToOUF()
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
                -- Reset UI scale so next reload re-snapshots from Blizzard default
                EllesmereUIDB.ppUIScale = nil
                EllesmereUIDB.ppUIScaleAuto = nil
                -- Developer settings defaults
                EllesmereUIDB.errorGrabber = false
                EllesmereUIDB.errorSound = false
                EllesmereUIDB.showSpellID = false
                EllesmereUIDB.suppressErrors = true
                EllesmereUIDB.crosshairSize = "None"
                -- Reset unlock mode layout data
                EllesmereUIDB.unlockAnchors = nil
                EllesmereUIDB.unlockWidthMatch = nil
                EllesmereUIDB.unlockHeightMatch = nil
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
            if EllesmereUI._applyCrosshair then
                EllesmereUI._applyCrosshair()
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
