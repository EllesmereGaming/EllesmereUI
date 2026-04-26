-------------------------------------------------------------------------------
--  EllesmereUIBlizzardSkin.lua
--  Umbrella addon for themed Blizzard UI frames. Hosts the Character Sheet
--  rework (EllesmereUIBlizzardSkin_CharacterSheet.lua) and the tooltip, context
--  menu, and static popup reskinning below.
-------------------------------------------------------------------------------
local ADDON_NAME = ...

-------------------------------------------------------------------------------
--  Tooltip / Context Menu / Static Popup Skinning
--  Restyles Blizzard's GameTooltip and related frames with EUI's dark style.
--  Visual-only changes (alpha, backdrop color, font). No Hide/Show/SetParent
--  on Blizzard frames. All hooks are post-hooks via hooksecurefunc.
-------------------------------------------------------------------------------
;(function()
    local _ttSkinned = {}
    local _isSecret = issecretvalue
    local _PP  -- resolved lazily
    local _select = select
    local _GameTooltip = GameTooltip
    local _RAID_CC = RAID_CLASS_COLORS
    local _nameL1 = nil  -- cached ref to GameTooltipTextLeft1

    local function _enabled()
        return not EllesmereUIDB or EllesmereUIDB.customTooltips ~= false
    end

    local function _ttSkin(tt, _, isEmbedded)
        if not tt or tt:IsForbidden() or not _enabled() then return end
        -- Embedded tooltips (e.g. EmbeddedItemTooltip, the reward-item block
        -- inside a world-quest tooltip) render INSIDE a parent tooltip.
        -- Adding our bg + border to them makes the embedded block look like
        -- a standalone framed tooltip sitting inside the parent.
        if isEmbedded or tt.IsEmbedded then return end
        if _isSecret and _isSecret(tt:GetWidth()) then return end
        if not _PP then _PP = EllesmereUI and EllesmereUI.PP end
        if tt.NineSlice then tt.NineSlice:SetAlpha(0) end
        if not tt._euiBg then
            tt._euiBg = tt:CreateTexture(nil, "BACKGROUND", nil, -8)
            tt._euiBg:SetAllPoints()
            local RS = EllesmereUI.RESKIN
            tt._euiBg:SetColorTexture(RS.BG_R, RS.BG_G, RS.BG_B, RS.TT_ALPHA)
            if _PP and _PP.CreateBorder then
                _PP.CreateBorder(tt, 1, 1, 1, RS.BRD_ALPHA, 1, "OVERLAY", 7)
            end
        end
        tt._euiBg:Show()
    end

    local function _ttFonts(tt)
        if not tt or tt:IsForbidden() or not _enabled() then return end
        local fp = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or STANDARD_TEXT_FONT
        local ol = EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag() or ""
        local scale = EllesmereUIDB and EllesmereUIDB.tooltipFontScale or 1.0
        local titleSize = math.floor(13 * scale + 0.5)
        local bodySize  = math.floor(11 * scale + 0.5)
        local name = tt.GetName and tt:GetName()
        if not name then return end
        local nLines = tt.NumLines and tt:NumLines() or 30
        for i = 1, nLines do
            local left = _G[name .. "TextLeft" .. i]
            if not left then break end
            left:SetFont(fp, (i == 1) and titleSize or bodySize, ol)
            local right = _G[name .. "TextRight" .. i]
            if right then right:SetFont(fp, bodySize, ol) end
        end
    end

    local function _ttOnShow(self) 
        -- Block tooltips from showing if the hide in combat toggle is on and combat is active
        if EllesmereUIDB and EllesmereUIDB.tooltipHideInCombat and InCombatLockdown() then
            self:Hide()
            return
        end
        _ttSkin(self); _ttFonts(self) 
    end

    local function _ttHook(tt)
        if not tt or tt:IsForbidden() or _ttSkinned[tt] then return end
        _ttSkinned[tt] = true
        tt:HookScript("OnShow", _ttOnShow)
    end

    local function _accentEnabled()
        return EllesmereUIDB and EllesmereUIDB.accentReskinElements
    end

    local function _ttUnitColor(tt)
        if tt ~= _GameTooltip or tt:IsForbidden() then return end
        local ok, _, unit = pcall(tt.GetUnit, tt)
        if not ok then return end
        if not unit then
            if UnitExists("mouseover") then unit = "mouseover" end
        end
        if not unit or (_isSecret and _isSecret(unit)) then return end
        if not UnitIsPlayer(unit) then return end
        local _, classFile = UnitClass(unit)
        if not classFile or (_isSecret and _isSecret(classFile)) then return end
        if not _nameL1 then _nameL1 = _G.GameTooltipTextLeft1 end
        if not _nameL1 then return end
        -- Strip player titles (default on: tooltipPlayerTitles is opt-in)
        local db = EllesmereUIDB
        if not (db and db.tooltipPlayerTitles) then
            local name = UnitName(unit)
            if name and not (_isSecret and _isSecret(name)) then
                local realm = select(2, UnitName(unit))
                local display = (realm and realm ~= "") and (name .. "-" .. realm) or name
                _nameL1:SetText(display)
            end
        end
        -- Class color the name line and the status bar
        local cc = _RAID_CC and _RAID_CC[classFile]
        if cc then
            _nameL1:SetTextColor(cc.r, cc.g, cc.b)
            if GameTooltipStatusBar then
                GameTooltipStatusBar:SetStatusBarColor(cc.r, cc.g, cc.b)
            end
        end
        -- M+ Score
        if EllesmereUIDB and EllesmereUIDB.tooltipMythicScore ~= false
            and C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary then
            local info = C_PlayerInfo.GetPlayerMythicPlusRatingSummary(unit)
            local score = info and info.currentSeasonScore
            if score and score > 0 then
                local sColor = C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor
                    and C_ChallengeMode.GetDungeonScoreRarityColor(score)
                local r, g, b = 1, 1, 1
                if sColor then r, g, b = sColor.r, sColor.g, sColor.b end
                tt:AddDoubleLine("M+ Score:", score, 1, 1, 1, r, g, b)
            end
        end
    end

    local function _ttInit()
        for _, tt in ipairs({
            _GameTooltip, ShoppingTooltip1, ShoppingTooltip2,
            ItemRefTooltip, ItemRefShoppingTooltip1, ItemRefShoppingTooltip2,
            FriendsTooltip, EmbeddedItemTooltip, GameSmallHeaderTooltip, QuickKeybindTooltip,
            _G.WarCampaignTooltip, _G.ReputationParagonTooltip,
            _G.LibDBIconTooltip, _G.SettingsTooltip,
            QuestScrollFrame and QuestScrollFrame.StoryTooltip,
            QuestScrollFrame and QuestScrollFrame.CampaignTooltip,
        }) do
            _ttHook(tt)
        end
        if SharedTooltip_SetBackdropStyle then
            hooksecurefunc("SharedTooltip_SetBackdropStyle", _ttSkin)
        end
        if GameTooltipStatusBar then
            GameTooltipStatusBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
            local sbBg = GameTooltipStatusBar:CreateTexture(nil, "BACKGROUND")
            sbBg:SetAllPoints(); sbBg:SetColorTexture(0, 0, 0, 0.5)
            GameTooltipStatusBar:ClearAllPoints()
            GameTooltipStatusBar:SetPoint("BOTTOMLEFT", _GameTooltip, "BOTTOMLEFT", 1, 1)
            GameTooltipStatusBar:SetPoint("BOTTOMRIGHT", _GameTooltip, "BOTTOMRIGHT", -1, 1)
            GameTooltipStatusBar:SetHeight(3)
        end
        -- Accent-color the title line for spells/macros (not items or units)
        local function _ttAccentTitle(tt)
            if tt ~= _GameTooltip or tt:IsForbidden() or not _accentEnabled() then return end
            if not _nameL1 then _nameL1 = _G.GameTooltipTextLeft1 end
            if _nameL1 then
                local EG = EllesmereUI.ELLESMERE_GREEN
                if EG then _nameL1:SetTextColor(EG.r, EG.g, EG.b) end
            end
        end
        if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
            TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, _ttUnitColor)
            TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, _ttAccentTitle)
            TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Macro, _ttAccentTitle)
        else
            _GameTooltip:HookScript("OnTooltipSetUnit", _ttUnitColor)
            _GameTooltip:HookScript("OnTooltipSetSpell", _ttAccentTitle)
        end
        -- Sets tooltip anchor
        if GameTooltip_SetDefaultAnchor then
            hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tt, parent)
                if EllesmereUIDB and EllesmereUIDB.tooltipAnchorMouse then
                    if parent then
                        tt:SetOwner(parent, "ANCHOR_CURSOR_RIGHT")
                    end
                end
            end)
        end
        -- Hide currently open tooltips when combat starts if the hide in combat toggle is on
        local combatTooltipHider = CreateFrame("Frame")
        combatTooltipHider:RegisterEvent("PLAYER_REGEN_DISABLED") -- Fires when entering combat
        combatTooltipHider:SetScript("OnEvent", function()
            if EllesmereUIDB and EllesmereUIDB.tooltipHideInCombat then
                -- Hide the main game tooltip if it's currently on screen
                if _GameTooltip:IsShown() then
                    _GameTooltip:Hide()
                end
            end
        end)
    end

    -- Context menu skinning
    local _menuSkinned = {}

    local function _menuSkinFrame(frame)
        if not frame or frame:IsForbidden() or not _enabled() then return end
        for i = 1, _select("#", frame:GetRegions()) do
            local region = _select(i, frame:GetRegions())
            if region and region:IsObjectType("Texture") and not region._euiOwned then
                local RS = EllesmereUI.RESKIN
                region:SetColorTexture(RS.BG_R, RS.BG_G, RS.BG_B, 1)
                region:SetAlpha(RS.CTX_ALPHA)
                region:ClearAllPoints()
                region:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
                region:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
            end
        end
        if not _menuSkinned[frame] then
            _menuSkinned[frame] = true
            if _PP and _PP.CreateBorder then
                local RS = EllesmereUI.RESKIN
                _PP.CreateBorder(frame, 1, 1, 1, RS.BRD_ALPHA, 1, "OVERLAY", 7)
            end
        end
    end

    local function _menuOnOpen(manager, _, menuDescription)
        if not _enabled() then return end
        local menu = manager.GetOpenMenu and manager:GetOpenMenu()
        if menu then
            _menuSkinFrame(menu)
        end
        if menuDescription and menuDescription.AddMenuAcquiredCallback then
            menuDescription:AddMenuAcquiredCallback(_menuSkinFrame)
        end
    end

    local function _menuInit()
        if not _G.Menu or not _G.Menu.GetManager then return end
        local mgr = _G.Menu.GetManager()
        if not mgr then return end
        hooksecurefunc(mgr, "OpenMenu", function(self, ownerRegion, menuDescription)
            _menuOnOpen(self, ownerRegion, menuDescription)
        end)
        hooksecurefunc(mgr, "OpenContextMenu", function(self, ownerRegion, menuDescription)
            _menuOnOpen(self, ownerRegion, menuDescription)
        end)
    end

    -- Static popup skinning
    local function _popupSkin(popup)
        if not popup or popup:IsForbidden() then return end
        if not _enabled() then return end
        -- Strip textures on the popup frame itself
        for i = 1, _select("#", popup:GetRegions()) do
            local r = _select(i, popup:GetRegions())
            if r and r:IsObjectType("Texture") and not r._euiOwned then
                r:SetTexture(nil)
                if r.SetAtlas then r:SetAtlas("") end
            end
        end
        -- Hide the BG border frame (StaticPopupN.BG)
        if popup.BG then popup.BG:SetAlpha(0) end
        if popup.NineSlice then popup.NineSlice:SetAlpha(0) end
        -- Our dark background + border (once)
        if not popup._euiBg then
            local RS = EllesmereUI.RESKIN
            popup._euiBg = popup:CreateTexture(nil, "BACKGROUND", nil, -8)
            popup._euiBg:SetAllPoints()
            popup._euiBg:SetColorTexture(RS.BG_R, RS.BG_G, RS.BG_B, RS.QT_ALPHA)
            popup._euiBg._euiOwned = true
            if not _PP then _PP = EllesmereUI and EllesmereUI.PP end
            if _PP and _PP.CreateBorder then
                _PP.CreateBorder(popup, 1, 1, 1, RS.BRD_ALPHA, 1, "OVERLAY", 7)
            end
        end
        popup._euiBg:Show()
        -- Skin buttons
        for i = 1, 4 do
            local btn = popup["button" .. i] or _G[popup:GetName() and (popup:GetName() .. "Button" .. i)]
            if btn and not btn._euiSkinned then
                btn._euiSkinned = true
                for j = 1, select("#", btn:GetRegions()) do
                    local r = select(j, btn:GetRegions())
                    if r and r:IsObjectType("Texture") and r ~= btn:GetFontString() then
                        r:SetTexture(nil)
                        if r.SetAtlas then r:SetAtlas("") end
                    end
                end
                local RS = EllesmereUI.RESKIN
                local EG = EllesmereUI.ELLESMERE_GREEN
                local useAccent = _accentEnabled() and EG
                local btnBg = btn:CreateTexture(nil, "BACKGROUND", nil, -6)
                btnBg:SetAllPoints()
                btnBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
                btnBg._euiOwned = true
                btn._euiBg = btnBg
                if not _PP then _PP = EllesmereUI and EllesmereUI.PP end
                if _PP and _PP.CreateBorder then
                    if useAccent then
                        _PP.CreateBorder(btn, EG.r, EG.g, EG.b, 0.5, 1, "OVERLAY", 7)
                    else
                        _PP.CreateBorder(btn, 1, 1, 1, RS.BRD_ALPHA, 1, "OVERLAY", 7)
                    end
                end

                -- Mirror Blizzard's enabled/disabled state so buttons visibly
                -- dim when locked out (e.g. Release in boss combat).
                local function _euiRefreshEnabled(self)
                    local fs = self:GetFontString()
                    local enabled = (self.IsEnabled and self:IsEnabled()) and true or false
                    if fs then
                        if enabled then
                            local EG2 = EllesmereUI.ELLESMERE_GREEN
                            if _accentEnabled() and EG2 then
                                fs:SetTextColor(EG2.r, EG2.g, EG2.b, 1)
                            else
                                fs:SetTextColor(1, 1, 1, 1)
                            end
                        else
                            fs:SetTextColor(0.4, 0.4, 0.4, 1)
                        end
                    end
                    if self._euiBg then
                        self._euiBg:SetAlpha(enabled and 1 or 0.5)
                    end
                end
                btn._euiRefreshEnabled = _euiRefreshEnabled
                btn:HookScript("OnEnable",  _euiRefreshEnabled)
                btn:HookScript("OnDisable", _euiRefreshEnabled)
                _euiRefreshEnabled(btn)
            end
        end

        -- Hook UpdateRecapButton once per popup so our per-button enabled
        -- visual stays in sync with Blizzard's enable/disable state swaps.
        if popup.UpdateRecapButton and not popup._euiRecapHooked then
            popup._euiRecapHooked = true
            hooksecurefunc(popup, "UpdateRecapButton", function(self)
                for i = 1, 4 do
                    local b = self["button" .. i]
                    if b and b._euiRefreshEnabled then b:_euiRefreshEnabled() end
                end
            end)
        end

        -- Re-sync state for popups shown already-disabled
        for i = 1, 4 do
            local b = popup["button" .. i]
            if b and b._euiRefreshEnabled then b:_euiRefreshEnabled() end
        end
        -- Skin edit box if present
        local eb = popup.editBox or (popup.GetName and _G[popup:GetName() .. "EditBox"])
        if eb and not eb._euiSkinned then
            eb._euiSkinned = true
            for j = 1, select("#", eb:GetRegions()) do
                local r = select(j, eb:GetRegions())
                if r and r:IsObjectType("Texture") then
                    r:SetTexture(nil)
                    if r.SetAtlas then r:SetAtlas("") end
                end
            end
            local ebBg = eb:CreateTexture(nil, "BACKGROUND", nil, -6)
            ebBg:SetAllPoints()
            ebBg:SetColorTexture(0.05, 0.05, 0.05, 0.9)
            ebBg._euiOwned = true
        end
    end

    local function _popupInit()
        for i = 1, STATICPOPUP_NUMDIALOGS or 4 do
            local popup = _G["StaticPopup" .. i]
            if popup then
                popup:HookScript("OnShow", function(self) _popupSkin(self) end)
            end
        end
    end

    do
        local f = CreateFrame("Frame")
        f:RegisterEvent("PLAYER_LOGIN")
        f:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            if not EllesmereUIDB or EllesmereUIDB.customTooltips ~= false then
                _ttInit()
                _menuInit()
                _popupInit()
            end
        end)
    end
    EllesmereUI._initTooltipSkins = function() _ttInit(); _menuInit(); _popupInit() end

    ---------------------------------------------------------------------------
    --  LFG Queue Accept Popup: reskin + countdown timer bar
    --  Skins LFGDungeonReadyPopup the same way we skin StaticPopups, and
    --  adds an accent-colored countdown bar below the popup.
    ---------------------------------------------------------------------------
    do
        local TIMER_DURATION = 40
        local timerBar, timerText, timerEndTime

        -- One-time default: inherit from master "Reskin Blizzard Elements"
        -- toggle, then write the explicit value so future changes to the
        -- master toggle don't silently affect this setting.
        local function IsQueueReskinOn()
            if not EllesmereUIDB then return true end
            if EllesmereUIDB.reskinQueuePopup == nil then
                EllesmereUIDB.reskinQueuePopup = (EllesmereUIDB.customTooltips ~= false)
            end
            return EllesmereUIDB.reskinQueuePopup
        end

        local function SkinQueuePopup()
            local popup = LFGDungeonReadyPopup
            if not popup then return end

            -- Strip Blizzard border/decoration textures on popup and dialog.
            -- Preserve dialog.background (the dungeon art image).
            local dialog = LFGDungeonReadyDialog
            local keepTextures = {}
            if dialog and dialog.background then keepTextures[dialog.background] = true end
            if dialog and dialog.bottomArt then keepTextures[dialog.bottomArt] = true end
            for _, frame in ipairs({ popup, dialog }) do
                if frame then
                    for i = 1, _select("#", frame:GetRegions()) do
                        local r = _select(i, frame:GetRegions())
                        if r and r:IsObjectType("Texture") and not r._euiOwned and not keepTextures[r] then
                            r:SetTexture(nil)
                            if r.SetAtlas then r:SetAtlas("") end
                        end
                    end
                    if frame.BG then frame.BG:SetAlpha(0) end
                    if frame.NineSlice then frame.NineSlice:SetAlpha(0) end
                    if frame.Border then frame.Border:SetAlpha(0) end
                end
            end

            -- Reskin the close button (X)
            local closeBtn = _G.LFGDungeonReadyDialogCloseButton
            if closeBtn then
                for i = 1, _select("#", closeBtn:GetRegions()) do
                    local r = _select(i, closeBtn:GetRegions())
                    if r and r:IsObjectType("Texture") and not r._euiOwned then
                        r:SetAlpha(0)
                    end
                end
                if not closeBtn._euiIcon then
                    local icoW, icoH = closeBtn:GetSize()
                    local ico = closeBtn:CreateTexture(nil, "OVERLAY", nil, 7)
                    ico:SetSize((icoW or 16) - 2, (icoH or 16) - 2)
                    ico:SetPoint("CENTER", closeBtn, "CENTER", -4, 4)
                    ico:SetAtlas("UI-QuestTrackerButton-Secondary-Collapse-Pressed")
                    ico._euiOwned = true
                    closeBtn._euiIcon = ico
                end
                closeBtn._euiIcon:Show()
            end

            -- Our dark background + border (create once).
            -- Keep frame levels as low as possible so the popup doesn't
            -- render over unrelated UI elements it shouldn't overlap.
            if not popup._euiBg then
                local RS = EllesmereUI.RESKIN
                if not _PP then _PP = EllesmereUI and EllesmereUI.PP end
                -- Child frame parented to dialog so it inherits the dialog's
                -- strata, but at frame level dialog-1 so it renders BELOW the
                -- dialog's own textures (dungeon art, buttons) but ABOVE
                -- external UI (options panel) that sits at the popup's lower
                -- frame level. Anchored to the popup for full coverage.
                local bgFrame = CreateFrame("Frame", nil, dialog or popup)
                bgFrame:SetAllPoints(popup)
                bgFrame:SetFrameLevel(math.max(1, (dialog or popup):GetFrameLevel() - 1))
                popup._euiBgFrame = bgFrame
                popup._euiBg = bgFrame:CreateTexture(nil, "ARTWORK")
                popup._euiBg:SetAllPoints()
                popup._euiBg:SetColorTexture(RS.BG_R, RS.BG_G, RS.BG_B, RS.QT_ALPHA)
                popup._euiBg._euiOwned = true
                if _PP and _PP.CreateBorder then
                    _PP.CreateBorder(bgFrame, 1, 1, 1, RS.BRD_ALPHA, 1, "OVERLAY", 7)
                end
            end

            -- Skin buttons (Enter Dungeon / Leave Queue).
            -- Re-strip textures every show (Blizzard re-applies art on each popup).
            -- Only create bg/border once.
            if dialog then
                for _, btnName in ipairs({ "enterButton", "leaveButton" }) do
                    local btn = dialog[btnName]
                    if btn then
                        -- Force all Blizzard texture regions invisible (every show).
                        -- Named Left/Middle/Right textures are swapped by C++ on
                        -- mouse down so SetTexture alone doesn't stick.
                        for j = 1, select("#", btn:GetRegions()) do
                            local r = select(j, btn:GetRegions())
                            if r and r:IsObjectType("Texture") and not r._euiOwned and r ~= btn:GetFontString() then
                                r:SetAlpha(0)
                            end
                        end
                        -- Named template textures
                        if btn.Left then btn.Left:SetAlpha(0) end
                        if btn.Middle then btn.Middle:SetAlpha(0) end
                        if btn.Right then btn.Right:SetAlpha(0) end
                        -- Create our bg/border + hook texture suppression once
                        if not btn._euiSkinned then
                            btn._euiSkinned = true
                            -- Hook SetAlpha on named textures so C++ press
                            -- state changes can't make them visible again
                            for _, texKey in ipairs({ "Left", "Middle", "Right" }) do
                                local tex = btn[texKey]
                                if tex and tex.SetAlpha then
                                    hooksecurefunc(tex, "SetAlpha", function(self, a)
                                        if a > 0 then self:SetAlpha(0) end
                                    end)
                                end
                            end
                            local EG = EllesmereUI.ELLESMERE_GREEN
                            local useAccent = _accentEnabled() and EG
                            local RS2 = EllesmereUI.RESKIN
                            local btnBg = btn:CreateTexture(nil, "BACKGROUND", nil, -6)
                            btnBg:SetAllPoints()
                            btnBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
                            btnBg._euiOwned = true
                            if _PP and _PP.CreateBorder then
                                if useAccent then
                                    _PP.CreateBorder(btn, EG.r, EG.g, EG.b, 0.5, 1, "OVERLAY", 7)
                                else
                                    _PP.CreateBorder(btn, 1, 1, 1, RS2.BRD_ALPHA, 1, "OVERLAY", 7)
                                end
                            end
                        end
                        -- Accent-color the button text (every show)
                        local EG = EllesmereUI.ELLESMERE_GREEN
                        local useAccent = _accentEnabled() and EG
                        local fs = btn:GetFontString()
                        if fs and useAccent then
                            fs:SetTextColor(EG.r, EG.g, EG.b, 1)
                        end
                    end
                end
            end
        end

        local timerBorder, timerBg

        local function ShowQueueTimer(useEuiStyle)
            local popup = LFGDungeonReadyPopup
            if not popup then return end

            if not timerBar then
                local timerParent = popup._euiBgFrame or dialog or popup
                timerBar = CreateFrame("StatusBar", nil, timerParent)
                timerBar:SetMinMaxValues(0, TIMER_DURATION)

                timerBg = timerBar:CreateTexture(nil, "BACKGROUND")
                timerBg:SetAllPoints()
                timerBg:SetColorTexture(0, 0, 0, 0.7)

                -- Blizzard-style casting bar border (hidden when EUI style)
                timerBorder = timerBar:CreateTexture(nil, "OVERLAY")
                timerBorder:SetTexture(130874)
                timerBorder:SetSize(256, 64)
                timerBorder:SetPoint("TOP", timerBar, 0, 28)

                timerText = timerBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                timerText:SetPoint("CENTER", timerBar, "CENTER", 0, 0)

                if EllesmereUI.RegAccent then
                    EllesmereUI.RegAccent({ type = "callback", fn = function()
                        if timerBar._euiStyle then
                            local r, g, b = EllesmereUI.GetAccentColor()
                            timerBar:SetStatusBarColor(r, g, b, 0.75)
                        end
                    end })
                end
            end

            -- Anchor target: use dialog when a third-party mover (EnhanceQoL)
            -- manages the dialog position, since the popup wrapper stays put.
            local dialog = LFGDungeonReadyDialog
            local anchorFrame = popup
            if dialog and dialog._eqolLayoutHooks then anchorFrame = dialog end

            -- Switch style based on whether the popup reskin is active
            timerBar:ClearAllPoints()
            if useEuiStyle then
                timerBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
                local mult = (_PP and _PP.mult) or 1
                timerBar:SetHeight(11)
                timerBar:SetPoint("BOTTOMLEFT", anchorFrame, "BOTTOMLEFT", mult, mult)
                timerBar:SetPoint("BOTTOMRIGHT", anchorFrame, "BOTTOMRIGHT", -mult, mult)
                local ar, ag, ab = EllesmereUI.GetAccentColor()
                timerBar:SetStatusBarColor(ar, ag, ab, 0.75)
                timerBg:SetColorTexture(0, 0, 0, 0.5)
                timerBorder:Hide()
                timerBg:Show()
                -- Apply EUI font
                local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("extras"))
                    or "Fonts\\FRIZQT__.TTF"
                timerText:SetFont(fontPath, 9, "")
                timerText:SetTextColor(1, 0.831, 0, 1) -- #ffd400
                timerText:SetShadowOffset(1, -1)
                timerText:SetShadowColor(0, 0, 0, 0.8)
                timerBar._euiStyle = true
            else
                -- Blizzard style (matches BigWigs look)
                timerBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
                timerBar:SetPoint("TOP", anchorFrame, "BOTTOM", 0, -5)
                timerBar:SetSize(190, 9)
                timerBar:SetStatusBarColor(1, 0.1, 0)
                timerBorder:Show()
                timerBg:Show()
                timerText:SetFontObject("GameFontHighlight")
                timerBar._euiStyle = false
            end

            -- Hide other addons' timer bars (BigWigs etc.)
            for _, child in ipairs({ popup:GetChildren() }) do
                if child ~= timerBar and child.GetObjectType
                   and child:GetObjectType() == "StatusBar" then
                    child:Hide()
                end
            end

            timerEndTime = GetTime() + TIMER_DURATION
            timerBar:SetValue(TIMER_DURATION)
            timerText:SetText(format("%d", TIMER_DURATION))
            timerBar:Show()

            timerBar:SetScript("OnUpdate", function(self)
                local remaining = timerEndTime - GetTime()
                if remaining <= 0 then
                    self:SetScript("OnUpdate", nil)
                    self:Hide()
                    return
                end
                self:SetValue(remaining)
                timerText:SetText(format("%d", math.ceil(remaining)))
            end)
        end

        -- Skin the "queue missed" / role check status popup
        local function SkinQueueStatus()
            local status = _G.LFGDungeonReadyStatus
            if not status or not IsQueueReskinOn() then return end
            -- Strip textures (every show)
            for i = 1, _select("#", status:GetRegions()) do
                local r = _select(i, status:GetRegions())
                if r and r:IsObjectType("Texture") and not r._euiOwned then
                    r:SetTexture(nil)
                    if r.SetAtlas then r:SetAtlas("") end
                end
            end
            if status.BG then status.BG:SetAlpha(0) end
            if status.NineSlice then status.NineSlice:SetAlpha(0) end
            if status.Border then status.Border:SetAlpha(0) end
            -- Our bg + border (once)
            if not status._euiBg then
                local RS = EllesmereUI.RESKIN
                status._euiBg = status:CreateTexture(nil, "BACKGROUND", nil, -8)
                status._euiBg:SetAllPoints()
                status._euiBg:SetColorTexture(RS.BG_R, RS.BG_G, RS.BG_B, RS.QT_ALPHA)
                status._euiBg._euiOwned = true
                if not _PP then _PP = EllesmereUI and EllesmereUI.PP end
                if _PP and _PP.CreateBorder then
                    _PP.CreateBorder(status, 1, 1, 1, RS.BRD_ALPHA, 1, "OVERLAY", 7)
                end
            end
        end

        -- Hook LFGDungeonReadyStatus OnShow so the skin applies the moment
        -- the acceptance panel appears (before any specific event fires).
        local _statusHooked = false
        local function HookStatusOnShow()
            if _statusHooked then return end
            local status = _G.LFGDungeonReadyStatus
            if not status then return end
            _statusHooked = true
            status:HookScript("OnShow", function() SkinQueueStatus() end)
        end

        local lfgFrame = CreateFrame("Frame")
        lfgFrame:RegisterEvent("LFG_PROPOSAL_SHOW")
        lfgFrame:RegisterEvent("LFG_PROPOSAL_FAILED")
        lfgFrame:RegisterEvent("LFG_PROPOSAL_SUCCEEDED")
        lfgFrame:SetScript("OnEvent", function(_, event)
            if not EllesmereUIDB then return end
            if event == "LFG_PROPOSAL_SHOW" then
                -- Skip reskin when a third-party mover (EnhanceQoL) manages
                -- the dialog position. Our skin elements are on the popup
                -- wrapper and won't follow when the dialog is moved.
                local dialog = LFGDungeonReadyDialog
                local thirdPartyMover = dialog and dialog._eqolLayoutHooks
                local reskinOn = IsQueueReskinOn() and not thirdPartyMover
                if reskinOn then
                    SkinQueuePopup()
                    HookStatusOnShow()
                end
                if EllesmereUIDB.showQueueTimer ~= false then
                    ShowQueueTimer(reskinOn)
                end
            else
                -- FAILED/SUCCEEDED: the status popup shows
                SkinQueueStatus()
            end
        end)
    end
end)()

-------------------------------------------------------------------------------
--  Premade Group Invite Popup: same dark skin as the LFG queue popup.
--  LFGListInviteDialog appears when a group leader accepts your application.
-------------------------------------------------------------------------------
do
    local function SkinPremadeInvite()
        local dialog = _G.LFGListInviteDialog
        if not dialog then return end
        if not EllesmereUIDB or not EllesmereUIDB.reskinQueuePopup then return end
        if dialog._euiSkinned then return end
        dialog._euiSkinned = true

        local RS = EllesmereUI.RESKIN
        local _PP = EllesmereUI and EllesmereUI.PP

        -- Strip Blizzard border/decoration only (preserve role icon + content)
        if dialog.Bg then dialog.Bg:SetAlpha(0) end
        if dialog.BG then dialog.BG:SetAlpha(0) end
        if dialog.NineSlice then dialog.NineSlice:SetAlpha(0) end
        if dialog.Border then dialog.Border:SetAlpha(0) end

        -- Dark bg + border
        local bg = dialog:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(RS.BG_R, RS.BG_G, RS.BG_B, RS.QT_ALPHA)
        bg._euiOwned = true
        if _PP and _PP.CreateBorder then
            _PP.CreateBorder(dialog, 1, 1, 1, RS.BRD_ALPHA, 1, "OVERLAY", 7)
        end

        -- Skin buttons
        local function _accentOn()
            return EllesmereUIDB and EllesmereUIDB.accentReskinElements
        end
        for _, btnName in ipairs({ "AcceptButton", "DeclineButton", "AcknowledgeButton" }) do
            local btn = dialog[btnName]
            if btn then
                -- Strip all texture regions (every show, Blizzard re-applies)
                for j = 1, select("#", btn:GetRegions()) do
                    local r = select(j, btn:GetRegions())
                    if r and r:IsObjectType("Texture") and not r._euiOwned and r ~= btn:GetFontString() then
                        r:SetAlpha(0)
                    end
                end
                if btn.Left then btn.Left:SetAlpha(0) end
                if btn.Middle then btn.Middle:SetAlpha(0) end
                if btn.Right then btn.Right:SetAlpha(0) end
                if not btn._euiSkinned then
                    btn._euiSkinned = true
                    for _, texKey in ipairs({ "Left", "Middle", "Right" }) do
                        local tex = btn[texKey]
                        if tex and tex.SetAlpha then
                            hooksecurefunc(tex, "SetAlpha", function(self, a)
                                if a > 0 then self:SetAlpha(0) end
                            end)
                        end
                    end
                    local EG = EllesmereUI.ELLESMERE_GREEN
                    local useAccent = _accentOn() and EG
                    local btnBg = btn:CreateTexture(nil, "BACKGROUND", nil, -6)
                    btnBg:SetAllPoints()
                    btnBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
                    btnBg._euiOwned = true
                    if _PP and _PP.CreateBorder then
                        if useAccent then
                            _PP.CreateBorder(btn, EG.r, EG.g, EG.b, 0.5, 1, "OVERLAY", 7)
                        else
                            _PP.CreateBorder(btn, 1, 1, 1, RS.BRD_ALPHA, 1, "OVERLAY", 7)
                        end
                    end
                end
                -- Accent text (every show)
                local EG = EllesmereUI.ELLESMERE_GREEN
                local useAccent = _accentOn() and EG
                local fs = btn:GetFontString()
                if fs and useAccent then
                    fs:SetTextColor(EG.r, EG.g, EG.b, 1)
                end
            end
        end
    end

    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(self, _, addon)
        if _G.LFGListInviteDialog then
            self:UnregisterAllEvents()
            _G.LFGListInviteDialog:HookScript("OnShow", SkinPremadeInvite)
        end
    end)
end

-------------------------------------------------------------------------------
--  LFG Application Dialog (Sign Up popup): same dark skin.
-------------------------------------------------------------------------------
do
    local function SkinApplicationDialog()
        local dialog = _G.LFGListApplicationDialog
        if not dialog then return end
        if not EllesmereUIDB or not EllesmereUIDB.reskinQueuePopup then return end
        if dialog._euiSkinned then return end
        dialog._euiSkinned = true

        local RS = EllesmereUI.RESKIN
        local _PP = EllesmereUI and EllesmereUI.PP

        -- Strip border/decoration only (preserve content)
        if dialog.Bg then dialog.Bg:SetAlpha(0) end
        if dialog.BG then dialog.BG:SetAlpha(0) end
        if dialog.NineSlice then dialog.NineSlice:SetAlpha(0) end
        if dialog.Border then dialog.Border:SetAlpha(0) end

        -- Dark bg + border
        local bg = dialog:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(RS.BG_R, RS.BG_G, RS.BG_B, RS.QT_ALPHA)
        bg._euiOwned = true
        if _PP and _PP.CreateBorder then
            _PP.CreateBorder(dialog, 1, 1, 1, RS.BRD_ALPHA, 1, "OVERLAY", 7)
        end

        -- Skin the description edit box
        local desc = _G.LFGListApplicationDialogDescription
        if desc then
            -- Strip all texture regions (edge textures, bg, etc.)
            for i = 1, select("#", desc:GetRegions()) do
                local r = select(i, desc:GetRegions())
                if r and r:IsObjectType("Texture") and not r._euiOwned then
                    r:SetAlpha(0)
                end
            end
            if desc.NineSlice then desc.NineSlice:SetAlpha(0) end
            local descBg = desc:CreateTexture(nil, "BACKGROUND")
            descBg:SetAllPoints()
            descBg:SetColorTexture(0.06, 0.06, 0.06, 0.8)
            descBg._euiOwned = true
            if _PP and _PP.CreateBorder then
                _PP.CreateBorder(desc, 1, 1, 1, 0.08, 1, "OVERLAY", 7)
            end
        end

        local function _accentOn()
            return EllesmereUIDB and EllesmereUIDB.accentReskinElements
        end
        for _, btnName in ipairs({ "SignUpButton", "CancelButton" }) do
            local btn = dialog[btnName]
            if btn and not btn._euiSkinned then
                btn._euiSkinned = true
                for j = 1, select("#", btn:GetRegions()) do
                    local r = select(j, btn:GetRegions())
                    if r and r:IsObjectType("Texture") and not r._euiOwned and r ~= btn:GetFontString() then
                        r:SetAlpha(0)
                    end
                end
                if btn.Left then btn.Left:SetAlpha(0) end
                if btn.Middle then btn.Middle:SetAlpha(0) end
                if btn.Right then btn.Right:SetAlpha(0) end
                for _, texKey in ipairs({ "Left", "Middle", "Right" }) do
                    local tex = btn[texKey]
                    if tex and tex.SetAlpha then
                        hooksecurefunc(tex, "SetAlpha", function(self, a)
                            if a > 0 then self:SetAlpha(0) end
                        end)
                    end
                end
                local EG = EllesmereUI.ELLESMERE_GREEN
                local useAccent = _accentOn() and EG
                local btnBg = btn:CreateTexture(nil, "BACKGROUND", nil, -6)
                btnBg:SetAllPoints()
                btnBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
                btnBg._euiOwned = true
                if _PP and _PP.CreateBorder then
                    if useAccent then
                        _PP.CreateBorder(btn, EG.r, EG.g, EG.b, 0.5, 1, "OVERLAY", 7)
                    else
                        _PP.CreateBorder(btn, 1, 1, 1, RS.BRD_ALPHA, 1, "OVERLAY", 7)
                    end
                end
                local fs = btn:GetFontString()
                if fs and useAccent then
                    fs:SetTextColor(EG.r, EG.g, EG.b, 1)
                end
            end
        end
    end

    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(self, _, addon)
        if _G.LFGListApplicationDialog then
            self:UnregisterAllEvents()
            _G.LFGListApplicationDialog:HookScript("OnShow", SkinApplicationDialog)
        end
    end)
end

-------------------------------------------------------------------------------
--  Game Menu Skinning
--  Restyles the pause menu (GameMenuFrame) with EUI dark style + border.
--  Runs once on PLAYER_LOGIN so GameMenuFrame is available.
-------------------------------------------------------------------------------
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        if not GameMenuFrame then return end
        -- Defaults to matching reskinQueuePopup if never explicitly set.
        local reskin = EllesmereUIDB and EllesmereUIDB.reskinGameMenu
        if reskin == nil then reskin = (not EllesmereUIDB or (EllesmereUIDB.customTooltips ~= false and EllesmereUIDB.reskinQueuePopup ~= false)) end
        if not reskin then return end

        local RS = EllesmereUI.RESKIN
        local PP = EllesmereUI.PP
        local ELLESMERE_GREEN = EllesmereUI.ELLESMERE_GREEN or { r = 0.27, g = 0.86, b = 0.49 }

        -- Strip decorative textures
        for i = 1, select("#", GameMenuFrame:GetRegions()) do
            local r = select(i, GameMenuFrame:GetRegions())
            if r and r:IsObjectType("Texture") then r:SetAlpha(0) end
        end
        if GameMenuFrame.NineSlice then GameMenuFrame.NineSlice:SetAlpha(0) end
        if GameMenuFrame.Border then GameMenuFrame.Border:SetAlpha(0) end
        -- Strip header textures, accent-color the title, nudge down
        local header = GameMenuFrame.Header
        if header then
            for i = 1, select("#", header:GetRegions()) do
                local r = select(i, header:GetRegions())
                if r and r:IsObjectType("Texture") then r:SetAlpha(0) end
            end
            local headerText = header.Text or (header.GetRegions and select(1, header:GetRegions()))
            if headerText and headerText.SetTextColor then
                headerText:SetTextColor(ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b, 1)
                local euiFont = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or "Fonts\\FRIZQT__.TTF"
                local _, hSize = headerText:GetFont()
                headerText:SetFont(euiFont, hSize or 16, "")
            end
            header:ClearAllPoints()
            header:SetPoint("TOP", GameMenuFrame, "TOP", 0, -10)
        end
        -- Dark bg + border
        local gmBg = GameMenuFrame:CreateTexture(nil, "BACKGROUND")
        gmBg:SetAllPoints()
        gmBg:SetColorTexture(RS.BG_R, RS.BG_G, RS.BG_B, RS.QT_ALPHA)
        if PP and PP.CreateBorder then
            PP.CreateBorder(GameMenuFrame, 1, 1, 1, RS.BRD_ALPHA, 1, "OVERLAY", 7)
        end
        -- Skin pooled buttons via InitButtons hook
        hooksecurefunc(GameMenuFrame, "InitButtons", function(menu)
            if not menu.buttonPool then return end
            for menuBtn in menu.buttonPool:EnumerateActive() do
                if not menuBtn._euiSkinned then
                    menuBtn._euiSkinned = true
                    for j = 1, select("#", menuBtn:GetRegions()) do
                        local r = select(j, menuBtn:GetRegions())
                        if r and r:IsObjectType("Texture") and r ~= menuBtn:GetFontString() then
                            r:SetAlpha(0)
                        end
                    end
                    if menuBtn.Left then menuBtn.Left:SetAlpha(0) end
                    if menuBtn.Middle then menuBtn.Middle:SetAlpha(0) end
                    if menuBtn.Right then menuBtn.Right:SetAlpha(0) end
                    for _, texKey in ipairs({ "Left", "Middle", "Right" }) do
                        local tex = menuBtn[texKey]
                        if tex and tex.SetAlpha then
                            hooksecurefunc(tex, "SetAlpha", function(self, a)
                                if a > 0 then self:SetAlpha(0) end
                            end)
                        end
                    end
                    -- Inset container: bg + border sit 2px inside the
                    -- button edges for a tighter, cleaner look.
                    local inset = CreateFrame("Frame", nil, menuBtn)
                    inset:SetPoint("TOPLEFT", 2, -2)
                    inset:SetPoint("BOTTOMRIGHT", -2, 2)
                    inset:SetFrameLevel(menuBtn:GetFrameLevel())
                    local btnBg = inset:CreateTexture(nil, "BACKGROUND", nil, -6)
                    btnBg:SetAllPoints()
                    btnBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
                    if PP and PP.CreateBorder then
                        PP.CreateBorder(inset, 1, 1, 1, RS.BRD_ALPHA, 1, "OVERLAY", 7)
                    end
                    local hl = menuBtn:CreateTexture(nil, "HIGHLIGHT")
                    hl:SetAllPoints(inset)
                    hl:SetColorTexture(1, 1, 1, 0.1)
                    local fs = menuBtn:GetFontString()
                    if fs then
                        local euiFont = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or nil
                        local _, size, flags = fs:GetFont()
                        fs:SetFont(euiFont or "Fonts\\FRIZQT__.TTF", (size or 14) - 2, flags or "")
                    end
                end
            end
        end)
    end)
end

-------------------------------------------------------------------------------
--  UberTooltips CVar enforcement (only if user has manually set it in EUI)
-------------------------------------------------------------------------------
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        if not EllesmereUIDB then EllesmereUIDB = {} end
        if EllesmereUIDB.uberTooltipsManual then
            SetCVar("UberTooltips", EllesmereUIDB.uberTooltips and "1" or "0")
        else
            SetCVar("UberTooltips", "1")
        end
    end)
end
