-------------------------------------------------------------------------------
--  EllesmereUI_Startup.lua
--  Runs as early as possible (first file after the Lite framework).
--  Applies settings that the WoW engine caches at login time, before
--  other addon files or PLAYER_LOGIN handlers have a chance to run.
-------------------------------------------------------------------------------
local ADDON_NAME = ...

-------------------------------------------------------------------------------
--  Pixel-Perfect UI Scale
--
--  SavedVariables (EllesmereUIDB) aren't available at file scope — they load
--  at ADDON_LOADED. So we use events:
--    ADDON_LOADED  -> DB is available. If we have a saved scale, apply it.
--    PLAYER_ENTERING_WORLD -> Blizzard has applied the user's CVar scale.
--                    If no saved scale yet (first install / reset), snapshot
--                    the user's current Blizzard scale and save it.
-------------------------------------------------------------------------------
do
    local GetPhysicalScreenSize = GetPhysicalScreenSize
    local dbReady = false
    local scaleKnown = false   -- true when ppUIScale was already saved

    local function ApplyScaleSafe(scale)
        if InCombatLockdown() then
            local f = CreateFrame("Frame")
            f:RegisterEvent("PLAYER_REGEN_ENABLED")
            f:SetScript("OnEvent", function(self)
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                UIParent:SetScale(scale)
                if EllesmereUI and EllesmereUI.PP and EllesmereUI.PP.UpdateMult then
                    EllesmereUI.PP.UpdateMult()
                end
            end)
        else
            UIParent:SetScale(scale)
            if EllesmereUI and EllesmereUI.PP and EllesmereUI.PP.UpdateMult then
                EllesmereUI.PP.UpdateMult()
            end
        end
    end

    local function SyncMultOnly()
        if EllesmereUI and EllesmereUI.PP then
            if EllesmereUI.PP.UpdateMult then EllesmereUI.PP.UpdateMult() end
            if EllesmereUI.PP.ResnapAllBorders then EllesmereUI.PP.ResnapAllBorders() end
        end
    end

    local scaleFrame = CreateFrame("Frame")
    scaleFrame:RegisterEvent("ADDON_LOADED")
    scaleFrame:RegisterEvent("PLAYER_LOGIN")
    scaleFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    scaleFrame:SetScript("OnEvent", function(self, event, addonName)
        if event == "ADDON_LOADED" then
            if addonName ~= ADDON_NAME then return end
            self:UnregisterEvent("ADDON_LOADED")
            dbReady = true

            if not EllesmereUIDB then EllesmereUIDB = {} end

            local _, physH = GetPhysicalScreenSize()
            local perfect = 768 / physH
            local function PixelBestSize()
                return max(0.4, min(perfect, 1.15))
            end

            if EllesmereUIDB.ppUIScale then
                -- Migrate 0.53 to exact pixel-perfect 0.5333...
                if EllesmereUIDB.ppUIScale == 0.53 then
                    EllesmereUIDB.ppUIScale = 0.5333333333
                end
                scaleKnown = true
            end

        elseif event == "PLAYER_LOGIN" then
            self:UnregisterEvent("PLAYER_LOGIN")

            if scaleKnown and EllesmereUIDB.ppUIScale then
                -- Returning user: single SetScale at PLAYER_LOGIN.
                -- No timers, no repeated calls.
                ApplyScaleSafe(EllesmereUIDB.ppUIScale)

                -- Re-apply our scale whenever Blizzard fires UI_SCALE_CHANGED
                -- (zone transitions, CVar resets, resolution changes).
                self:RegisterEvent("UI_SCALE_CHANGED")
                return
            end

            -- First-time path: just sync mult for child addon OnEnable
            if EllesmereUI and EllesmereUI.PP and EllesmereUI.PP.UpdateMult then
                EllesmereUI.PP.UpdateMult()
            end

        elseif event == "UI_SCALE_CHANGED" then
            local saved = EllesmereUIDB and EllesmereUIDB.ppUIScale
            if saved then
                ApplyScaleSafe(saved)
                SyncMultOnly()
            end
            return

        elseif event == "PLAYER_ENTERING_WORLD" then
            self:UnregisterEvent("PLAYER_ENTERING_WORLD")

            if not dbReady then return end
            if not EllesmereUIDB then EllesmereUIDB = {} end

            -- Returning user: scale was applied once at PLAYER_LOGIN,
            -- nothing else needed.
            if scaleKnown then return end

            -- First install or reset: snapshot the user's Blizzard scale
            if EllesmereUIDB.ppUIScale == nil then
                local blizzScale = UIParent:GetScale()
                local clamped = max(0.4, min(blizzScale, 1.15))
                EllesmereUIDB.ppUIScale = clamped
                EllesmereUIDB.ppUIScaleAuto = false
            end

            local scale = EllesmereUIDB.ppUIScale
            if not scale then return end

            -- First-time install: apply scale with safety net.
            -- Apply scale multiple times to guarantee it sticks even on
            -- slow machines where Blizzard may reset it during init.
            if EllesmereUI and EllesmereUI.PP and EllesmereUI.PP.UpdateMult then
                EllesmereUI.PP.UpdateMult()
            end
            ApplyScaleSafe(scale)
            C_Timer.After(2, function()
                if InCombatLockdown() then return end
                if EllesmereUIDB and EllesmereUIDB.ppUIScale then
                    ApplyScaleSafe(EllesmereUIDB.ppUIScale)
                end
                SyncMultOnly()
            end)
            C_Timer.After(5, function()
                if InCombatLockdown() then return end
                if EllesmereUIDB and EllesmereUIDB.ppUIScale then
                    ApplyScaleSafe(EllesmereUIDB.ppUIScale)
                end
                SyncMultOnly()
            end)
        end
    end)
end

-- Apply the saved combat text font immediately at file scope.
-- DAMAGE_TEXT_FONT must be set before the engine caches it at login.
-- CombatTextFont may not exist yet here, so we also hook ADDON_LOADED
-- to catch it as soon as it becomes available.
do
    local function ApplyCombatTextFont()
        local saved = EllesmereUIDB and EllesmereUIDB.fctFont
        if not saved or type(saved) ~= "string" or saved == "" then return end
        -- Resolve "smf:" prefixed SharedMedia font keys to actual paths
        local fontPath = saved
        local smName = saved:match("^smf:(.+)")
        if smName then
            local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
            local fetched = LSM and LSM:Fetch("font", smName)
            -- If the SM addon is missing or hasn't loaded yet, skip entirely
            -- so Blizzard's default combat text font stays intact.
            if not fetched then return end
            fontPath = fetched
        end
        _G.DAMAGE_TEXT_FONT = fontPath
        if _G.CombatTextFont then
            _G.CombatTextFont:SetFont(fontPath, 120, "")
        end
    end

    -- Apply immediately (sets DAMAGE_TEXT_FONT before engine caches it)
    ApplyCombatTextFont()

    -- Re-apply on ADDON_LOADED (our addon or Blizzard_CombatText), PLAYER_LOGIN,
    -- and PLAYER_ENTERING_WORLD to cover all timing windows where the engine
    -- may cache or reset the combat text font.
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:RegisterEvent("PLAYER_LOGIN")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function(self, event, addonName)
        if event == "ADDON_LOADED" then
            if addonName ~= ADDON_NAME and addonName ~= "Blizzard_CombatText" then
                return
            end
        end

        ApplyCombatTextFont()

        if event == "PLAYER_LOGIN" then
            self:UnregisterEvent("PLAYER_LOGIN")
        elseif event == "PLAYER_ENTERING_WORLD" then
            self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        elseif event == "ADDON_LOADED" then
            self:UnregisterEvent("ADDON_LOADED")
        end
    end)
end

-- NOTE: the global _G.STANDARD_TEXT_FONT override that used to live here was
-- removed. It was gated on the "Reskin Blizzard Elements" (customTooltips) toggle
-- and read a dead legacy key (EllesmereUIDB.fontSettings.global), so it always
-- forced STANDARD_TEXT_FONT to the bundled Expressway.TTF -- a Latin-only face --
-- regardless of the user's actual font choice. In CJK/Cyrillic locales that broke
-- glyphs across the whole Blizzard UI AND other addons (square boxes), because it
-- bypassed the locale-aware ResolveFontName fallback.
--
-- Changing the global game-text font is now handled exclusively by the opt-in,
-- locale-aware EllesmereUI.ApplyGlobalFontToGameText() ("Apply to All Game Text"),
-- which runs once at PLAYER_LOGIN. Reskinned Blizzard elements still pick up the
-- EllesmereUI font on their own via per-element, locale-aware SetFont calls
-- (EllesmereUI.GetFontPath("blizzardSkin")), so reskinning no longer touches the
-- global font and never affects other addons.

-------------------------------------------------------------------------------
--  Auto-disable EllesmereUIBags when a dedicated bag addon is present.
--  Once the user manually toggles the Bags module (sidebar power button or
--  first-install popup), we set EllesmereUIDB.bagsUserChosen and never
--  override their preference again.
-------------------------------------------------------------------------------
do
    local BAG_ADDONS = {
        "AdiBags", "ArkInventory", "Baganator", "Bagnon", "BetterBags", "Sorted",
    }
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(self, event, addonName)
        if addonName ~= ADDON_NAME then return end
        self:UnregisterAllEvents()
        if not EllesmereUIDB then EllesmereUIDB = {} end
        if EllesmereUIDB.bagsUserChosen then return end
        if not C_AddOns or not C_AddOns.GetAddOnEnableState then return end
        -- If we previously auto-disabled bags but the user re-enabled it
        -- (via Blizzard addon list or any other means), respect their choice.
        local bagsEnabled = C_AddOns.GetAddOnEnableState("EllesmereUIBags") > 0
        if EllesmereUIDB.bagsAutoDisabled and bagsEnabled then
            EllesmereUIDB.bagsUserChosen = true
            EllesmereUIDB.bagsAutoDisabled = nil
            return
        end
        for _, name in ipairs(BAG_ADDONS) do
            if C_AddOns.GetAddOnEnableState(name) > 0 then
                C_AddOns.DisableAddOn("EllesmereUIBags")
                EllesmereUIDB.bagsAutoDisabled = true
                return
            end
        end
        EllesmereUIDB.bagsAutoDisabled = nil
    end)
end

-- /rl reload shortcut -- only
if not SlashCmdList["RL"] then
    SlashCmdList["RL"] = function() ReloadUI() end
    SLASH_RL1 = "/rl"
end
