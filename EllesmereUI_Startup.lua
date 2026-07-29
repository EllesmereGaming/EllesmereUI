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
                -- Migrate 0.53 to exact pixel-perfect 0.5333... (768/1440)
                if EllesmereUIDB.ppUIScale == 0.53 then
                    EllesmereUIDB.ppUIScale = 0.5333333333
                -- Migrate 0.71 to exact pixel-perfect 0.7111... (768/1080)
                elseif EllesmereUIDB.ppUIScale == 0.71 then
                    EllesmereUIDB.ppUIScale = 0.7111111111
                end
                scaleKnown = true
                -- Apply here, not only at PLAYER_LOGIN: the engine restores
                -- user-placed frame positions from its own layout cache during
                -- login, converting the stored values with UIParent's scale AT
                -- THAT MOMENT. The cache was written at last logout using OUR
                -- scale, so applying ours later than the restore makes the
                -- round-trip asymmetric and every user-placed frame shifts by
                -- (ourScale / cvarScale) every session -- the undocked chat
                -- window drift, field-measured at exactly x0.8333 =
                -- 0.5333/0.64 per reload. ADDON_LOADED is the earliest point
                -- the saved value exists, so applying it here closes the
                -- window: the engine decodes with the scale that encoded.
                -- The PLAYER_LOGIN apply below stays as an idempotent belt.
                --
                -- FIELD RESULT (2026-07-28): this did NOT stop the drift.
                -- Blizzard applies the user's CVar scale during login AFTER
                -- addon ADDON_LOADED (this file's own PLAYER_ENTERING_WORLD
                -- comment says so), so the chat restore still ran at the CVar
                -- scale. Kept anyway: it is idempotent, costs nothing, and
                -- closes the same window for anything restored before
                -- Blizzard's CVar apply. The chat fix is below.
                ApplyScaleSafe(EllesmereUIDB.ppUIScale)
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

-- Apply the saved unit name font -- the names that float above players, NPCs
-- and enemies. UNIT_NAME_FONT is a plain path string the engine reads once at
-- login, so a UI reload is not enough and the change shows after a full relog.
--
-- Opt-in: while no name font is chosen the global is never written, so
-- Blizzard's default is left exactly as it was.
--
-- Rides the combat text font's event frame below rather than creating its own.
-- Both drive a Blizzard global cached at login and want the same timing, and a
-- feature nobody enabled must not register events or build frames of its own.
--
-- Reads EllesmereUIDB.fonts directly rather than going through GetFontsDB():
-- that helper lazy-creates the table, and this can run at the ADDON_LOADED of
-- Blizzard_CombatText, before our SavedVariables have been restored.
local function ApplyUnitNameFont()
    local fonts = EllesmereUIDB and EllesmereUIDB.fonts
    local name = fonts and fonts.unitNameFont
    if not name or name == "" then return end
    local path = fonts.unitNameFontPath
    if (type(path) ~= "string" or path == "")
       and EllesmereUI and EllesmereUI.ResolveFontName then
        path = EllesmereUI.ResolveFontName(name)
    end
    if type(path) == "string" and path ~= "" then
        _G.UNIT_NAME_FONT = path
    end
end

-------------------------------------------------------------------------------
--  Undocked chat window position fix
--
--  Root cause, arithmetically pinned by the field drift capture (2026-07-28).
--  UIParent's height in UI units is always 768 / scale, so it is 1440 at our
--  pixel-perfect 0.5333 but 1200 at the tester's CVar scale 0.64. Blizzard
--  stores an undocked window's position as a screen-height RATIO and restores
--  it as ratio * GetScreenHeight(). Blizzard applies the CVar scale during
--  login and we apply ours at PLAYER_LOGIN, AFTER the chat restore has
--  already run -- so the restore resolves the ratio against the 1200 space:
--      correct : 0.1566 * 1440 = 225.5   (where the user dropped it)
--      restored: 0.1566 * 1200 = 187.9   (where it reappeared)
--  Then we rescale UIParent to the 1440 space and the frame keeps that
--  numeric 188 offset, which now points somewhere lower. Each session
--  repeats it, so the window creeps toward the bottom-left by
--  (cvarScale height / our height) per login. Only setups whose EUI scale
--  differs from the CVar scale drift, which is why not everyone sees it.
--
--  Fixing the scale TIMING does not work: applying our scale at ADDON_LOADED
--  (kept above, harmless) is overwritten by Blizzard's own CVar apply later
--  in login, so the restore still runs at the CVar scale. The position has
--  to be recomputed after both the restore and our final scale, which is what
--  this pass does -- Blizzard's own formula, against the settled space.
--
--  TAINT NOTE -- anchoring a Blizzard chat frame from insecure code is the
--  injector class this module's bisect ledger convicted, so this pass was
--  suspected of causing the field ChatFrameEditBox.lua:360 secret-SetText
--  error and was removed entirely in v6. The error reproduced on v6, a build
--  whose only chat contact is read-only getters -- so the pass is NOT the
--  vector and is restored here. That error is tracked separately as a
--  pre-existing chat-module issue. Exposure is still kept minimal: ONE
--  deferred pass per login, never during a session, no hooks, and nothing
--  written to Blizzard frame state (SetPoint only). Do not add the
--  FCF_SavePositionAndDimensions hook, the SetUserPlaced writes, or the
--  UPDATE_CHAT_WINDOWS registration back -- all three were separately
--  pulled, none of them bought anything.
-------------------------------------------------------------------------------
do
    local function ReassertUndockedPositions()
        if not GetChatWindowSavedPosition then return end
        local W, H = GetScreenWidth(), GetScreenHeight()
        if not (W and H) then return end
        for i = 2, NUM_CHAT_WINDOWS or 10 do
            local cf = _G["ChatFrame" .. i]
            if cf and cf:IsShown() and not cf.isDocked and not cf.isTemporary then
                local point, xOff, yOff = GetChatWindowSavedPosition(i)
                if point and xOff and yOff then
                    -- Blizzard's own restore formula, re-run now that the
                    -- scale (and therefore GetScreenWidth/Height) has settled.
                    cf:ClearAllPoints()
                    cf:SetPoint(point, UIParent, point, xOff * W, yOff * H)
                end
            end
        end
    end

    local fixFrame = CreateFrame("Frame")
    fixFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    fixFrame:SetScript("OnEvent", function(self, _, initialLogin, reloadingUi)
        if not (initialLogin or reloadingUi) then return end
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        -- Obsolete v2 migration flag; the rebase it gated was a no-op.
        if EllesmereUIDB then EllesmereUIDB.chatPosRebased = nil end
        C_Timer.After(0, ReassertUndockedPositions)
        -- Belt for slow loads, still inside the login window.
        C_Timer.After(2, ReassertUndockedPositions)
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
        ApplyUnitNameFont()

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

-- (The DataBars auto-disable block was removed 2026-07-13: after the
-- multi-bar rewrite the module does literally nothing until the user
-- creates a bar, so it ships enabled with zero cost. If a prior build
-- auto-disabled it, re-enabling once sticks -- the latch keys
-- dataBarsAutoDisabled/dataBarsUserChosen are simply no longer read.)

-- /rl reload shortcut -- only
if not SlashCmdList["RL"] then
    SlashCmdList["RL"] = function() ReloadUI() end
    SLASH_RL1 = "/rl"
end
