-------------------------------------------------------------------------------
--  EUI_QoL_Options.lua
--  Registers the Quality of Life sidebar addon with its two tabs:
--    * Quality of Life -- general QoL features (built by parent general options)
--    * Cursor          -- cursor skin (built by EUI_QoL_Cursor_Options.lua)
-------------------------------------------------------------------------------
local PAGE_QOL      = "Quality of Life"
local PAGE_CURSOR   = "Cursor"
local PAGE_BREZ     = "BattleRes"
local PAGE_AUTOLOG  = "Keys, Logs & Brez"
local PAGE_UPGCALC  = "Upgrade Calc"
local PAGE_SHIFTER  = "Shifter"

-------------------------------------------------------------------------------
--  Hide Item Transforms picker popup
--  Item checklist styled after the spec-assign popup: dimmed backdrop, one
--  column per category, Check/Uncheck All links and a green Apply button.
--  Edits are staged and only written on Apply; clicking outside or pressing
--  Escape discards them. Item data comes from EllesmereUI.HideTransformsData
--  (owned by the runtime in EllesmereUIQoL.lua).
-------------------------------------------------------------------------------
local transformsPopup
local transformsStaged = {}

local function ShowTransformsPopup()
    local data = EllesmereUI.HideTransformsData
    if not data then return end

    if not transformsPopup then
        local FONT = EllesmereUI._font or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf"
        local EG = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }
        local PP = EllesmereUI.PanelPP
        local COL_W, COL_GAP = 190, 12
        local CONTENT_LEFT, CONTENT_RIGHT, CONTENT_TOP = 41, 36, 118
        local HDR_H, ROW_H = 30, 26
        local numCols = #data.order

        -- Group items per category; the tallest column drives the popup height.
        local catItems = {}
        for _, item in ipairs(data.items) do
            catItems[item.cat] = catItems[item.cat] or {}
            catItems[item.cat][#catItems[item.cat] + 1] = item
        end
        local maxRows = 0
        for _, cat in ipairs(data.order) do
            local n = catItems[cat] and #catItems[cat] or 0
            if n > maxRows then maxRows = n end
        end

        local POPUP_W = CONTENT_LEFT + CONTENT_RIGHT + numCols * COL_W + (numCols - 1) * COL_GAP
        local POPUP_H = CONTENT_TOP + HDR_H + 4 + maxRows * ROW_H + 24 + 39 + 38
        local ppScale = EllesmereUI.GetPopupScale and EllesmereUI.GetPopupScale() or 1

        local dimmer = CreateFrame("Frame", nil, UIParent)
        dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
        dimmer:SetAllPoints(UIParent)
        dimmer:EnableMouse(true)
        dimmer:EnableMouseWheel(true)
        dimmer:SetScript("OnMouseWheel", function() end)
        dimmer:Hide()
        dimmer:SetScale(ppScale)
        local dimTex = dimmer:CreateTexture(nil, "BACKGROUND")
        dimTex:SetAllPoints()
        dimTex:SetColorTexture(0, 0, 0, 0.25)

        local popup = CreateFrame("Frame", nil, dimmer)
        popup:SetScale(ppScale)
        popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)
        popup:SetSize(POPUP_W, POPUP_H)
        popup:SetPoint("CENTER", EllesmereUI._mainFrame or UIParent, "CENTER", 0, 0)
        popup:EnableMouse(true)
        local pf = EllesmereUI._popupFrames
        if pf then pf[#pf + 1] = { popup = popup, dimmer = dimmer } end

        local bg = popup:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.06, 0.08, 0.10, 1)
        EllesmereUI.MakeBorder(popup, 1, 1, 1, 0.15, PP)

        local title = popup:CreateFontString(nil, "OVERLAY")
        title:SetFont(FONT, 22, "")
        title:SetTextColor(1, 1, 1, 1)
        title:SetPoint("TOP", popup, "TOP", 0, -32)
        title:SetText(EllesmereUI.L("Hide Item Transforms"))

        local sub = popup:CreateFontString(nil, "OVERLAY")
        sub:SetFont(FONT, 14, "")
        sub:SetTextColor(1, 1, 1, 0.45)
        sub:SetPoint("TOP", title, "BOTTOM", 0, -8)
        sub:SetText(EllesmereUI.L("Checked transforms are removed automatically when applied to you."))

        local rows = {}
        local function RefreshRows()
            for _, row in ipairs(rows) do
                if transformsStaged[row._key] then
                    row._check:Show()
                    row._boxBorder:SetColor(EG.r, EG.g, EG.b, 0.8)
                else
                    row._check:Hide()
                    row._boxBorder:SetColor(0.4, 0.4, 0.4, 0.6)
                end
            end
        end
        popup._refreshRows = RefreshRows

        -- Check All / Uncheck All links
        local function SetAll(v)
            for _, item in ipairs(data.items) do transformsStaged[item.key] = v end
            RefreshRows()
        end
        local checkAllBtn = CreateFrame("Button", nil, popup)
        checkAllBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
        local checkAllLbl = checkAllBtn:CreateFontString(nil, "OVERLAY")
        checkAllLbl:SetFont(FONT, 14, "")
        checkAllLbl:SetText(EllesmereUI.L("Check All"))
        checkAllLbl:SetTextColor(1, 1, 1, 0.45)
        checkAllLbl:SetPoint("CENTER")
        checkAllBtn:SetSize(checkAllLbl:GetStringWidth() + 4, 20)
        checkAllBtn:SetPoint("TOPLEFT", popup, "TOPLEFT", CONTENT_LEFT, -(CONTENT_TOP - 22))
        checkAllBtn:SetScript("OnEnter", function() checkAllLbl:SetTextColor(1, 1, 1, 0.80) end)
        checkAllBtn:SetScript("OnLeave", function() checkAllLbl:SetTextColor(1, 1, 1, 0.45) end)
        checkAllBtn:SetScript("OnClick", function() SetAll(true) end)

        local linkDivider = popup:CreateTexture(nil, "OVERLAY", nil, 7)
        linkDivider:SetColorTexture(1, 1, 1, 0.18)
        if linkDivider.SetSnapToPixelGrid then linkDivider:SetSnapToPixelGrid(false); linkDivider:SetTexelSnappingBias(0) end
        linkDivider:SetPoint("LEFT", checkAllBtn, "RIGHT", 10, 0)
        linkDivider:SetWidth(1)
        linkDivider:SetHeight(12)

        local uncheckAllBtn = CreateFrame("Button", nil, popup)
        uncheckAllBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
        local uncheckAllLbl = uncheckAllBtn:CreateFontString(nil, "OVERLAY")
        uncheckAllLbl:SetFont(FONT, 14, "")
        uncheckAllLbl:SetText(EllesmereUI.L("Uncheck All"))
        uncheckAllLbl:SetTextColor(1, 1, 1, 0.45)
        uncheckAllLbl:SetPoint("CENTER")
        uncheckAllBtn:SetSize(uncheckAllLbl:GetStringWidth() + 4, 20)
        uncheckAllBtn:SetPoint("LEFT", checkAllBtn, "RIGHT", 20, 0)
        uncheckAllBtn:SetScript("OnEnter", function() uncheckAllLbl:SetTextColor(1, 1, 1, 0.80) end)
        uncheckAllBtn:SetScript("OnLeave", function() uncheckAllLbl:SetTextColor(1, 1, 1, 0.45) end)
        uncheckAllBtn:SetScript("OnClick", function() SetAll(false) end)

        -- Category columns
        for colIdx, cat in ipairs(data.order) do
            local colX = CONTENT_LEFT + (colIdx - 1) * (COL_W + COL_GAP)
            local hdr = popup:CreateFontString(nil, "OVERLAY")
            hdr:SetFont(FONT, 17, "")
            hdr:SetTextColor(1, 1, 1, 0.7)
            hdr:SetPoint("TOPLEFT", popup, "TOPLEFT", colX + 4, -(CONTENT_TOP + 8))
            hdr:SetText(EllesmereUI.L(data.labels[cat] or cat))

            local items = catItems[cat] or {}
            for i, item in ipairs(items) do
                local row = CreateFrame("Button", nil, popup)
                row:SetSize(COL_W, ROW_H)
                row:SetPoint("TOPLEFT", popup, "TOPLEFT", colX, -(CONTENT_TOP + HDR_H + 4 + (i - 1) * ROW_H))
                row._key = item.key

                local box = CreateFrame("Frame", nil, row)
                box:SetSize(18, 18)
                box:SetPoint("LEFT", row, "LEFT", 4, 0)
                box:SetFrameLevel(row:GetFrameLevel() + 1)
                local boxBg = box:CreateTexture(nil, "BACKGROUND")
                boxBg:SetAllPoints()
                boxBg:SetColorTexture(0.12, 0.12, 0.14, 1)
                row._boxBorder = EllesmereUI.MakeBorder(box, 0.4, 0.4, 0.4, 0.6, PP)
                local check = box:CreateTexture(nil, "ARTWORK")
                check:SetPoint("TOPLEFT", box, "TOPLEFT", 3, -3)
                check:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -3, 3)
                check:SetColorTexture(EG.r, EG.g, EG.b, 1)
                row._check = check

                local lbl = row:CreateFontString(nil, "OVERLAY")
                lbl:SetFont(FONT, 13, "")
                lbl:SetPoint("LEFT", box, "RIGHT", 8, 0)
                lbl:SetPoint("RIGHT", row, "RIGHT", -2, 0)
                lbl:SetJustifyH("LEFT")
                lbl:SetWordWrap(false)
                lbl:SetTextColor(1, 1, 1, 0.65)
                lbl:SetText(EllesmereUI.L(item.label))

                row:SetScript("OnEnter", function() lbl:SetTextColor(1, 1, 1, 0.95) end)
                row:SetScript("OnLeave", function() lbl:SetTextColor(1, 1, 1, 0.65) end)
                row:SetScript("OnClick", function()
                    transformsStaged[item.key] = not transformsStaged[item.key]
                    RefreshRows()
                end)
                rows[#rows + 1] = row
            end
        end

        -- Apply button (green, spec-popup style)
        local applyBtn = CreateFrame("Button", nil, popup)
        applyBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
        applyBtn:SetSize(200, 39)
        applyBtn:SetPoint("BOTTOM", popup, "BOTTOM", 0, 38)
        local applyBg = applyBtn:CreateTexture(nil, "BACKGROUND")
        applyBg:SetAllPoints()
        applyBg:SetColorTexture(0.06, 0.08, 0.10, 0.92)
        local applyBrd = EllesmereUI.MakeBorder(applyBtn, EG.r, EG.g, EG.b, 0.9, PP)
        local applyLbl = applyBtn:CreateFontString(nil, "OVERLAY")
        applyLbl:SetFont(FONT, 16, "")
        applyLbl:SetPoint("CENTER")
        applyLbl:SetText(EllesmereUI.L("Apply"))
        applyLbl:SetTextColor(EG.r, EG.g, EG.b, 0.9)
        applyBtn:SetScript("OnEnter", function()
            applyLbl:SetTextColor(EG.r, EG.g, EG.b, 1)
            applyBrd:SetColor(EG.r, EG.g, EG.b, 1)
        end)
        applyBtn:SetScript("OnLeave", function()
            applyLbl:SetTextColor(EG.r, EG.g, EG.b, 0.9)
            applyBrd:SetColor(EG.r, EG.g, EG.b, 0.9)
        end)
        applyBtn:SetScript("OnClick", function()
            if not EllesmereUIDB then EllesmereUIDB = {} end
            EllesmereUIDB.hideTransformItems = EllesmereUIDB.hideTransformItems or {}
            local t = EllesmereUIDB.hideTransformItems
            for _, item in ipairs(data.items) do
                if transformsStaged[item.key] then
                    t[item.key] = nil       -- included is the default
                else
                    t[item.key] = false     -- stored exclusions only
                end
            end
            if EllesmereUI._applyHideTransforms then EllesmereUI._applyHideTransforms() end
            dimmer:Hide()
        end)

        -- Click outside or Escape discards staged edits
        dimmer:SetScript("OnMouseDown", function(self)
            if not popup:IsMouseOver() then self:Hide() end
        end)
        popup:EnableKeyboard(true)
        popup:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                self:SetPropagateKeyboardInput(false)
                dimmer:Hide()
            else
                self:SetPropagateKeyboardInput(true)
            end
        end)

        popup._dimmer = dimmer
        transformsPopup = popup
    end

    -- Seed the staged state from the saved settings, then show
    for _, item in ipairs(data.items) do
        transformsStaged[item.key] = EllesmereUI.GetHideTransformItem(item.key) and true or false
    end
    transformsPopup._refreshRows()
    transformsPopup._dimmer:Show()
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not EllesmereUI or not EllesmereUI.RegisterModule then return end

    ---------------------------------------------------------------------------
    --  QoL Features page
    ---------------------------------------------------------------------------
    local function BuildQoLPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h
        local PP = EllesmereUI.PanelPP

        parent._showRowDivider = true

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -- The Macro Factory is deliberately NOT part of the global search.
        -- Its builder arms live machinery at build time (a session event
        -- frame that rewrites the player's real EUI_* macros on bag/spec
        -- events), so the hidden search pre-build must never run it, and its
        -- rows are kept out of the search index so results can never point
        -- into it (the index would otherwise deep-link to rows whose page
        -- state the factory manages itself).
        if EllesmereUI.BuildMacroFactory and not EllesmereUI._prebuilding then
            EllesmereUI._searchIndexSuppress = true
            local mfH = EllesmereUI.BuildMacroFactory(parent, y, PP)
            EllesmereUI._searchIndexSuppress = nil
            y = y - mfH
        end

        ---------------------------------------------------------------------------
        --  GENERAL
        ---------------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "GENERAL", y);  y = y - h

        local row1
        row1, h = W:DualRow(parent, y,
            { type="toggle", text="Hide Blizzard Party Panel",
              tooltip="Hides the collapsed Blizzard party/raid sidebar panel on the side of the screen.",
              disabled=function() return C_AddOns and C_AddOns.IsAddOnLoaded("EllesmereUIRaidFrames") end,
              disabledTooltip="This option is now controlled by the Raid Frames addon", rawTooltip=true,
              getValue=function()
                  return EllesmereUIDB and EllesmereUIDB.hideBlizzardPartyFrame or false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.hideBlizzardPartyFrame = v
                  if EllesmereUI._applyHideBlizzardPartyFrame then
                      EllesmereUI._applyHideBlizzardPartyFrame()
                  end
              end },
            { type="toggle", text="Skip Cinematics",
              tooltip="When you press Escape or Space during a cinematic, the confirmation prompt is automatically accepted.",
              getValue=function()
                  return EllesmereUIDB and EllesmereUIDB.skipCinematics or false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.skipCinematics = v
                  EllesmereUI:RefreshPage()
              end }
        );  y = y - h

        -- Cog on Skip Cinematics (right region of row1)
        do
            local rightRgn = row1._rightRegion
            local function cinematicsOff()
                return not (EllesmereUIDB and EllesmereUIDB.skipCinematics)
            end

            local _, cinCogShow = EllesmereUI.BuildCogPopup({
                title = "Cinematic Settings",
                rows = {
                    { type="toggle", label="Automatically Skip If Possible",
                      get=function()
                          return EllesmereUIDB and EllesmereUIDB.skipCinematicsAuto or false
                      end,
                      set=function(v)
                          if not EllesmereUIDB then EllesmereUIDB = {} end
                          EllesmereUIDB.skipCinematicsAuto = v
                      end },
                },
            })

            local cinCogBtn = CreateFrame("Button", nil, rightRgn)
            cinCogBtn:SetSize(26, 26)
            cinCogBtn:SetPoint("RIGHT", rightRgn._lastInline or rightRgn._control, "LEFT", -9, 0)
            rightRgn._lastInline = cinCogBtn
            cinCogBtn:SetFrameLevel(rightRgn:GetFrameLevel() + 5)
            cinCogBtn:SetAlpha(cinematicsOff() and 0.15 or 0.4)
            local cinCogTex = cinCogBtn:CreateTexture(nil, "OVERLAY")
            cinCogTex:SetAllPoints()
            cinCogTex:SetTexture(EllesmereUI.COGS_ICON)
            cinCogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cinCogBtn:SetScript("OnLeave", function(self) self:SetAlpha(cinematicsOff() and 0.15 or 0.4) end)
            cinCogBtn:SetScript("OnClick", function(self) cinCogShow(self) end)

            local cinCogBlock = CreateFrame("Frame", nil, cinCogBtn)
            cinCogBlock:SetAllPoints()
            cinCogBlock:SetFrameLevel(cinCogBtn:GetFrameLevel() + 10)
            cinCogBlock:EnableMouse(true)
            cinCogBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(cinCogBtn, EllesmereUI.DisabledTooltip("Skip Cinematics"))
            end)
            cinCogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            EllesmereUI.RegisterWidgetRefresh(function()
                local off = cinematicsOff()
                cinCogBtn:SetAlpha(off and 0.15 or 0.4)
                if off then cinCogBlock:Show() else cinCogBlock:Hide() end
            end)
            if cinematicsOff() then cinCogBlock:Show() else cinCogBlock:Hide() end
        end

        local row2
        row2, h = W:DualRow(parent, y,
            { type="toggle", text="Quick Loot",
              tooltip="Enables auto loot and hides the loot window when looting. Hold Shift when looting to show.",
              getValue=function()
                  return EllesmereUIDB and EllesmereUIDB.quickLoot or false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.quickLoot = v
                  if EllesmereUI._applyQuickLoot then EllesmereUI._applyQuickLoot() end
              end },
            { type="toggle", text="Auto-Fill Delete Confirmation",
              tooltip="Automatically types DELETE when throwing away a valuable item. Also allows you to press enter to accept the deletion.",
              getValue=function()
                  return EllesmereUIDB and EllesmereUIDB.autoFillDelete or false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.autoFillDelete = v
                  EllesmereUI:RefreshPage()
              end }
        );  y = y - h

        -- Auto Repair | Auto Sell Junk
        local repairRow
        repairRow, h = W:DualRow(parent, y,
            { type="toggle", text="Auto Repair",
              tooltip="Automatically repair all gear when visiting a repair vendor.",
              getValue=function()
                  if not EllesmereUIDB then return true end
                  return EllesmereUIDB.autoRepair ~= false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.autoRepair = v
                  EllesmereUI:RefreshPage()
              end },
            { type="toggle", text="Auto Sell Junk",
              tooltip="Automatically sell all junk items when visiting a vendor.",
              getValue=function()
                  if not EllesmereUIDB then return true end
                  return EllesmereUIDB.autoSellJunk ~= false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.autoSellJunk = v
              end }
        );  y = y - h

        -- Cog on Auto Repair (left region)
        do
            local leftRgn = repairRow._leftRegion
            local function repairOff()
                return not (EllesmereUIDB and EllesmereUIDB.autoRepair ~= false)
            end

            local _, repCogShow = EllesmereUI.BuildCogPopup({
                title = "Auto Repair Settings",
                rows = {
                    { type="toggle", label="Use Guild Bank Funds",
                      get=function()
                          if not EllesmereUIDB then return true end
                          return EllesmereUIDB.autoRepairGuild ~= false
                      end,
                      set=function(v)
                          if not EllesmereUIDB then EllesmereUIDB = {} end
                          EllesmereUIDB.autoRepairGuild = v
                      end },
                    -- Off (default) = short text "12o 34a"; on = coin icons.
                    { type="toggle", label="Coin Icons",
                      get=function()
                          return EllesmereUIDB and EllesmereUIDB.repairCoinIcons == true
                      end,
                      set=function(v)
                          if not EllesmereUIDB then EllesmereUIDB = {} end
                          EllesmereUIDB.repairCoinIcons = v
                      end },
                },
            })

            local repCogBtn = CreateFrame("Button", nil, leftRgn)
            repCogBtn:SetSize(26, 26)
            repCogBtn:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -9, 0)
            leftRgn._lastInline = repCogBtn
            repCogBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
            repCogBtn:SetAlpha(repairOff() and 0.15 or 0.4)
            local repCogTex = repCogBtn:CreateTexture(nil, "OVERLAY")
            repCogTex:SetAllPoints()
            repCogTex:SetTexture(EllesmereUI.COGS_ICON)
            repCogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            repCogBtn:SetScript("OnLeave", function(self) self:SetAlpha(repairOff() and 0.15 or 0.4) end)
            repCogBtn:SetScript("OnClick", function(self) repCogShow(self) end)

            local repCogBlock = CreateFrame("Frame", nil, repCogBtn)
            repCogBlock:SetAllPoints()
            repCogBlock:SetFrameLevel(repCogBtn:GetFrameLevel() + 10)
            repCogBlock:EnableMouse(true)
            repCogBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(repCogBtn, EllesmereUI.DisabledTooltip("Auto Repair"))
            end)
            repCogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            EllesmereUI.RegisterWidgetRefresh(function()
                local off = repairOff()
                repCogBtn:SetAlpha(off and 0.15 or 0.4)
                if off then repCogBlock:Show() else repCogBlock:Hide() end
            end)
            if repairOff() then repCogBlock:Show() else repCogBlock:Hide() end
        end

        _, h = W:DualRow(parent, y,
            { type="toggle", text="AH Current Expansion Only",
              tooltip="Automatically enables the 'Current Expansion Only' filter whenever you open the Auction House.",
              getValue=function()
                  return EllesmereUIDB and EllesmereUIDB.ahCurrentExpansion or false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.ahCurrentExpansion = v
              end },
            { type="toggle", text="Hide Talking Head",
              tooltip="Hides the large NPC dialogue popup that appears during quests and dungeons.",
              getValue=function()
                  return EllesmereUIDB and EllesmereUIDB.hideTalkingHead or false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.hideTalkingHead = v
              end }
        );  y = y - h

        -- Row 5: Show Coordinates on Map (left, with cog) | Suppress Lua Errors
        -- (Suppress Lua Errors is a front-end duplicate of the toggle in
        -- Global Settings > Developer; same EllesmereUIDB.suppressErrors key and
        -- scriptErrors CVar, applied on login by the parent General module.)
        local coordRow
        coordRow, h = W:DualRow(parent, y,
            { type="toggle", text="Show Coordinates on Map",
              tooltip="Displays cursor and player coordinates at the bottom of the world map.",
              getValue=function()
                  return EllesmereUIDB and EllesmereUIDB.mapCoords or false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.mapCoords = v
                  if EllesmereUI._applyMapCoords then EllesmereUI._applyMapCoords() end
                  EllesmereUI:RefreshPage()
              end },
            { type="toggle", text="Suppress Lua Errors",
              tooltip="Hides the Lua error popup. The same setting as Global Settings > Developer.",
              getValue=function()
                  return not (EllesmereUIDB and EllesmereUIDB.suppressErrors == false)
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.suppressErrors = v
                  if not InCombatLockdown() then SetCVar("scriptErrors", v and "0" or "1") end
              end }
        );  y = y - h

        -- Cog on Show Coordinates on Map (left region)
        do
            local leftRgn = coordRow._leftRegion
            local function coordsOff()
                return EllesmereUIDB and EllesmereUIDB.mapCoords == false
            end

            local _, coordCogShow = EllesmereUI.BuildCogPopup({
                title = "Map Coordinates Settings",
                rows = {
                    { type = "slider", label = "Text Size", min = 8, max = 24, step = 1,
                      get = function()
                          return (EllesmereUIDB and EllesmereUIDB.mapCoordsTextSize) or 12
                      end,
                      set = function(v)
                          if not EllesmereUIDB then EllesmereUIDB = {} end
                          EllesmereUIDB.mapCoordsTextSize = v
                          if EllesmereUI._applyMapCoords then EllesmereUI._applyMapCoords() end
                      end },
                },
            })
            local coordCogBtn = CreateFrame("Button", nil, leftRgn)
            coordCogBtn:SetSize(26, 26)
            coordCogBtn:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -9, 0)
            leftRgn._lastInline = coordCogBtn
            coordCogBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
            coordCogBtn:SetAlpha(coordsOff() and 0.15 or 0.4)
            local coordCogTex = coordCogBtn:CreateTexture(nil, "OVERLAY")
            coordCogTex:SetAllPoints()
            coordCogTex:SetTexture(EllesmereUI.COGS_ICON)
            coordCogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            coordCogBtn:SetScript("OnLeave", function(self) self:SetAlpha(coordsOff() and 0.15 or 0.4) end)
            coordCogBtn:SetScript("OnClick", function(self) coordCogShow(self) end)

            local coordCogBlock = CreateFrame("Frame", nil, coordCogBtn)
            coordCogBlock:SetAllPoints()
            coordCogBlock:SetFrameLevel(coordCogBtn:GetFrameLevel() + 10)
            coordCogBlock:EnableMouse(true)
            coordCogBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(coordCogBtn, EllesmereUI.DisabledTooltip("Show Coordinates on Map"))
            end)
            coordCogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            EllesmereUI.RegisterWidgetRefresh(function()
                local off = coordsOff()
                coordCogBtn:SetAlpha(off and 0.15 or 0.4)
                if off then coordCogBlock:Show() else coordCogBlock:Hide() end
            end)
            local coordInitOff = coordsOff()
            coordCogBtn:SetAlpha(coordInitOff and 0.15 or 0.4)
            if coordInitOff then coordCogBlock:Show() else coordCogBlock:Hide() end
        end

        -- Row 6: Hide Error Messages (left) | Hide Tutorial Pop-ups (right)
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Hide Error Messages",
              tooltip="Hides most red error messages (such as 'Not enough rage' or 'Ability is not ready yet'). Important errors like a full bag or quest log are still shown.",
              getValue=function()
                  return EllesmereUIDB and EllesmereUIDB.hideErrorMessages or false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.hideErrorMessages = v
                  if EllesmereUI._applyHideErrorMessages then EllesmereUI._applyHideErrorMessages() end
              end },
            { type="toggle", text="Hide Tutorial Pop-ups",
              tooltip="Hides Blizzard's tutorial UI: the yellow HelpTip bubbles and the glowing (i) help-plate buttons on the spellbook, talents, map, collections, and other panels.",
              getValue=function()
                  return EllesmereUIDB and EllesmereUIDB.hideTutorials or false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.hideTutorials = v
                  if EllesmereUI._applyHideTutorials then EllesmereUI._applyHideTutorials() end
              end }
        );  y = y - h

        -- Row 7: Announce Group Deaths (left, with Text Size cog) | Hide Item
        -- Transforms (right, with picker cog)
        local deathRow
        deathRow, h = W:DualRow(parent, y,
            { type="toggle", text="Announce Group Deaths",
              tooltip="Shows a large on-screen alert (e.g. \"Player DIED!\") whenever a party or raid member dies, so you immediately notice deaths during dungeons and raids. Use Unlock Mode to reposition the alert.",
              getValue=function()
                  return EllesmereUIDB and EllesmereUIDB.announceGroupDeaths or false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.announceGroupDeaths = v
                  if EllesmereUI._applyAnnounceGroupDeaths then EllesmereUI._applyAnnounceGroupDeaths() end
                  EllesmereUI:RefreshPage()
              end },
            { type="toggle", text="Hide Item Transforms (ex: Chef's Hat)",
              tooltip="Automatically removes cosmetic transforms when they are applied to you, such as profession gear, holiday costumes, toys and consumables. Use the cog to pick exactly which transforms are removed. Transforms applied during combat are removed when combat ends.",
              getValue=function()
                  return EllesmereUIDB and EllesmereUIDB.hideTransforms or false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.hideTransforms = v
                  if EllesmereUI._applyHideTransforms then
                      EllesmereUI._applyHideTransforms()
                  end
                  EllesmereUI:RefreshPage()  -- update the picker cog disabled state
              end }
        );  y = y - h

        -- Inline cog (Text Size) on the Announce Group Deaths toggle
        do
            local leftRgn = deathRow._leftRegion
            local function deathOff()
                return not (EllesmereUIDB and EllesmereUIDB.announceGroupDeaths)
            end

            -- Sound dropdown values (mirrors Chat's "Whisper Sound"): shallow-copy
            -- the runtime name table and attach _menuOpts so each row gets a
            -- click-to-preview speaker icon.
            local gdSoundPaths = EllesmereUI._groupDeathSoundPaths or {}
            local gdSoundNames = EllesmereUI._groupDeathSoundNames or { none = "None" }
            local gdSoundOrder = EllesmereUI._groupDeathSoundOrder or { "none" }
            local gdSoundValues = {}
            for k, v in pairs(gdSoundNames) do gdSoundValues[k] = v end
            gdSoundValues._menuOpts = {
                itemHeight = 26,
                maxTextWidthPct = 0.8,
                searchable = true,
                iconAtlas = function(key)
                    if key == "none" then return nil end
                    if not gdSoundPaths[key] then return nil end
                    return "common-icon-sound"
                end,
                iconPressedAtlas = function(key)
                    if key == "none" then return nil end
                    return "common-icon-sound-pressed"
                end,
                iconOnClick = function(key)
                    local path = gdSoundPaths[key]
                    if path then PlaySoundFile(path, "Master") end
                end,
                iconTooltip = function() return "Preview Sound" end,
            }

            local _, deathCogShow = EllesmereUI.BuildCogPopup({
                title = "Group Death Alert Settings",
                rows = {
                    { type="slider", label="Text Size",
                      min=14, max=64, step=1,
                      get=function()
                        return (EllesmereUIDB and EllesmereUIDB.groupDeathTextSize) or 34
                      end,
                      set=function(v)
                        if not EllesmereUIDB then EllesmereUIDB = {} end
                        EllesmereUIDB.groupDeathTextSize = v
                        if EllesmereUI._applyGroupDeathAlert then EllesmereUI._applyGroupDeathAlert() end
                        if EllesmereUI._groupDeathShowVisual then EllesmereUI._groupDeathShowVisual() end
                      end },
                    { type="dropdown", label="Sound",
                      values=gdSoundValues, order=gdSoundOrder,
                      get=function()
                        return (EllesmereUIDB and EllesmereUIDB.groupDeathSoundKey) or "none"
                      end,
                      set=function(v)
                        if not EllesmereUIDB then EllesmereUIDB = {} end
                        EllesmereUIDB.groupDeathSoundKey = v
                        if v ~= "none" and EllesmereUI._groupDeathPlaySound then
                            EllesmereUI._groupDeathPlaySound()
                        end
                      end },
                },
            })
            local deathCogBtn = CreateFrame("Button", nil, leftRgn)
            deathCogBtn:SetSize(26, 26)
            deathCogBtn:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -9, 0)
            leftRgn._lastInline = deathCogBtn
            deathCogBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
            deathCogBtn:SetAlpha(deathOff() and 0.15 or 0.4)
            local deathCogTex = deathCogBtn:CreateTexture(nil, "OVERLAY")
            deathCogTex:SetAllPoints()
            deathCogTex:SetTexture(EllesmereUI.COGS_ICON or EllesmereUI.DIRECTIONS_ICON)
            deathCogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            deathCogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            deathCogBtn:SetScript("OnClick", function(self) deathCogShow(self) end)

            -- Blocking overlay for cog when the feature is off
            local deathCogBlock = CreateFrame("Frame", nil, deathCogBtn)
            deathCogBlock:SetAllPoints()
            deathCogBlock:SetFrameLevel(deathCogBtn:GetFrameLevel() + 10)
            deathCogBlock:EnableMouse(true)
            deathCogBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(deathCogBtn, EllesmereUI.DisabledTooltip("Announce Group Deaths"))
            end)
            deathCogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            EllesmereUI.RegisterWidgetRefresh(function()
                if deathOff() then
                    deathCogBtn:SetAlpha(0.15); deathCogBlock:Show()
                else
                    deathCogBtn:SetAlpha(0.4); deathCogBlock:Hide()
                end
            end)
            local deathInitOff = deathOff()
            deathCogBtn:SetAlpha(deathInitOff and 0.15 or 0.4)
            if deathInitOff then deathCogBlock:Show() else deathCogBlock:Hide() end
        end

        -- Row: Combat Alert (left, with settings cog)
        local combatAlertRow
        combatAlertRow, h = W:DualRow(parent, y,
            { type="toggle", text="Combat Alert",
              tooltip="Shows a large on-screen text when you enter and/or leave combat (e.g. \"+Combat\" / \"-Combat\"). Use the cog to set the display text, size, colors and which transitions are shown; use Unlock Mode to reposition the alert.",
              getValue=function()
                  return EllesmereUIDB and EllesmereUIDB.combatAlertEnabled or false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.combatAlertEnabled = v
                  if EllesmereUI._applyCombatAlert then EllesmereUI._applyCombatAlert() end
                  EllesmereUI:RefreshPage()
              end },
            { type="label", text="" }
        );  y = y - h

        -- Inline cog (text, size, colors, mode) on the Combat Alert toggle
        do
            local leftRgn = combatAlertRow._leftRegion
            local function caOff()
                return not (EllesmereUIDB and EllesmereUIDB.combatAlertEnabled)
            end
            local function enterClassOn()
                return EllesmereUIDB and EllesmereUIDB.combatAlertEnterUseClassColor
            end
            local function leaveClassOn()
                return EllesmereUIDB and EllesmereUIDB.combatAlertLeaveUseClassColor
            end

            local caModeValues = {
                both  = "Enter & Leave",
                enter = "Enter Only",
                leave = "Leave Only",
            }
            local caModeOrder = { "both", "enter", "leave" }

            local _, combatAlertCogShow = EllesmereUI.BuildCogPopup({
                title = "Combat Alert Settings",
                minWidth = 300,
                rows = {
                    { type="dropdown", label="Show On",
                      values=caModeValues, order=caModeOrder,
                      get=function() return (EllesmereUIDB and EllesmereUIDB.combatAlertMode) or "both" end,
                      set=function(v)
                        if not EllesmereUIDB then EllesmereUIDB = {} end
                        EllesmereUIDB.combatAlertMode = v
                      end },
                    { type="slider", label="Text Size",
                      min=14, max=64, step=1,
                      get=function()
                        return (EllesmereUIDB and EllesmereUIDB.combatAlertTextSize) or 22
                      end,
                      set=function(v)
                        if not EllesmereUIDB then EllesmereUIDB = {} end
                        EllesmereUIDB.combatAlertTextSize = v
                        if EllesmereUI._applyCombatAlertFrame then EllesmereUI._applyCombatAlertFrame() end
                        if EllesmereUI._combatAlertPreview then EllesmereUI._combatAlertPreview("enter") end
                      end },
                    { type="input", label="Enter Text", inputWidth=90,
                      get=function()
                        return (EllesmereUIDB and EllesmereUIDB.combatAlertEnterText) or "+Combat"
                      end,
                      set=function(v)
                        if not EllesmereUIDB then EllesmereUIDB = {} end
                        EllesmereUIDB.combatAlertEnterText = v
                        if EllesmereUI._combatAlertPreview then EllesmereUI._combatAlertPreview("enter") end
                      end },
                    { type="colorpicker", label="Enter Color",
                      disabled=enterClassOn,
                      disabledTooltip="Disable Class Color to pick a custom color.",
                      get=function()
                        local c = (EllesmereUIDB and EllesmereUIDB.combatAlertEnterColor) or { r=1.00, g=1.00, b=1.00 }
                        return c.r, c.g, c.b
                      end,
                      set=function(r, g, b)
                        if not EllesmereUIDB then EllesmereUIDB = {} end
                        EllesmereUIDB.combatAlertEnterColor = { r=r, g=g, b=b }
                        if EllesmereUI._combatAlertPreview then EllesmereUI._combatAlertPreview("enter") end
                      end },
                    { type="toggle", label="Enter Class Color",
                      get=function() return enterClassOn() end,
                      set=function(v)
                        if not EllesmereUIDB then EllesmereUIDB = {} end
                        EllesmereUIDB.combatAlertEnterUseClassColor = v
                        if EllesmereUI._combatAlertPreview then EllesmereUI._combatAlertPreview("enter") end
                      end },
                    { type="input", label="Leave Text", inputWidth=90,
                      get=function()
                        return (EllesmereUIDB and EllesmereUIDB.combatAlertLeaveText) or "-Combat"
                      end,
                      set=function(v)
                        if not EllesmereUIDB then EllesmereUIDB = {} end
                        EllesmereUIDB.combatAlertLeaveText = v
                        if EllesmereUI._combatAlertPreview then EllesmereUI._combatAlertPreview("leave") end
                      end },
                    { type="colorpicker", label="Leave Color",
                      disabled=leaveClassOn,
                      disabledTooltip="Disable Class Color to pick a custom color.",
                      get=function()
                        local c = (EllesmereUIDB and EllesmereUIDB.combatAlertLeaveColor) or { r=1.00, g=1.00, b=1.00 }
                        return c.r, c.g, c.b
                      end,
                      set=function(r, g, b)
                        if not EllesmereUIDB then EllesmereUIDB = {} end
                        EllesmereUIDB.combatAlertLeaveColor = { r=r, g=g, b=b }
                        if EllesmereUI._combatAlertPreview then EllesmereUI._combatAlertPreview("leave") end
                      end },
                    { type="toggle", label="Leave Class Color",
                      get=function() return leaveClassOn() end,
                      set=function(v)
                        if not EllesmereUIDB then EllesmereUIDB = {} end
                        EllesmereUIDB.combatAlertLeaveUseClassColor = v
                        if EllesmereUI._combatAlertPreview then EllesmereUI._combatAlertPreview("leave") end
                      end },
                },
                footer = { unlockKey = "EUI_CombatAlert" },
            })
            local caCogBtn = CreateFrame("Button", nil, leftRgn)
            caCogBtn:SetSize(26, 26)
            caCogBtn:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -9, 0)
            leftRgn._lastInline = caCogBtn
            caCogBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
            caCogBtn:SetAlpha(caOff() and 0.15 or 0.4)
            local caCogTex = caCogBtn:CreateTexture(nil, "OVERLAY")
            caCogTex:SetAllPoints()
            caCogTex:SetTexture(EllesmereUI.COGS_ICON or EllesmereUI.DIRECTIONS_ICON)
            caCogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            caCogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            caCogBtn:SetScript("OnClick", function(self) combatAlertCogShow(self) end)

            -- Blocking overlay for cog when the feature is off
            local caCogBlock = CreateFrame("Frame", nil, caCogBtn)
            caCogBlock:SetAllPoints()
            caCogBlock:SetFrameLevel(caCogBtn:GetFrameLevel() + 10)
            caCogBlock:EnableMouse(true)
            caCogBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(caCogBtn, EllesmereUI.DisabledTooltip("Combat Alert"))
            end)
            caCogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            EllesmereUI.RegisterWidgetRefresh(function()
                if caOff() then
                    caCogBtn:SetAlpha(0.15); caCogBlock:Show()
                else
                    caCogBtn:SetAlpha(0.4); caCogBlock:Hide()
                end
            end)
            local caInitOff = caOff()
            caCogBtn:SetAlpha(caInitOff and 0.15 or 0.4)
            if caInitOff then caCogBlock:Show() else caCogBlock:Hide() end
        end

        -- Inline picker cog on Hide Item Transforms (right slot of the death
        -- row): opens the item checklist popup. Dimmed and inert while the
        -- toggle is off, mirroring the resource-bar spec-picker button.
        do
            local rgn = deathRow._rightRegion
            local function hitOff()
                return not (EllesmereUIDB and EllesmereUIDB.hideTransforms)
            end
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -9, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(hitOff() and 0.15 or 0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.COGS_ICON)
            cogBtn:SetScript("OnEnter", function(self)
                if hitOff() then return end
                self:SetAlpha(0.7)
                EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.L("Choose which transforms are removed"))
            end)
            cogBtn:SetScript("OnLeave", function(self)
                self:SetAlpha(hitOff() and 0.15 or 0.4)
                EllesmereUI.HideWidgetTooltip()
            end)
            cogBtn:SetScript("OnClick", function()
                if hitOff() then return end
                ShowTransformsPopup()
            end)
            EllesmereUI.RegisterWidgetRefresh(function()
                cogBtn:SetAlpha(hitOff() and 0.15 or 0.4)
            end)
        end

        _, h = W:Spacer(parent, y, 20);  y = y - h

        ---------------------------------------------------------------------------
        --  EXTRAS
        ---------------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "EXTRAS", y);  y = y - h

        -- Row 1: Show FPS Counter (left, with swatch+cog) | FPS Toggle Keybind (right)
        local fpsRow
        fpsRow, h = W:DualRow(parent, y,
            { type="toggle", text="Show FPS Counter",
              getValue=function()
                return EllesmereUI.QoLExtrasGet("showFPS") or false
              end,
              setValue=function(v)
                EllesmereUI.QoLExtrasSet("showFPS", v)
                if EllesmereUI._applyFPSCounter then EllesmereUI._applyFPSCounter() end
                EllesmereUI:RefreshPage()
              end },
            { type="label", text="FPS Toggle Keybind" }
        );  y = y - h

        -- Inline color swatch + cog on the FPS toggle (left region)
        do
            local leftRgn = fpsRow._leftRegion
            local function fpsOff()
                return not EllesmereUI.QoLExtrasGet("showFPS")
            end

            local fpsSwGet = function()
                local c = EllesmereUI.QoLExtrasGet("fpsColor")
                if c then return c.r, c.g, c.b, c.a end
                return 1, 1, 1, 1
            end
            local fpsSwSet = function(r, g, b, a)
                EllesmereUI.QoLExtrasSet("fpsColor", { r = r, g = g, b = b, a = a })
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
                    { type="slider", label="Text Size",
                      min=8, max=30, step=1,
                      get=function()
                        return EllesmereUI.QoLExtrasGet("fpsTextSize") or 12
                      end,
                      set=function(v)
                        EllesmereUI.QoLExtrasSet("fpsTextSize", v)
                        if EllesmereUI._applyFPSCounter then EllesmereUI._applyFPSCounter() end
                      end },
                    { type="toggle", label="Show Local MS",
                      get=function()
                        local sl = EllesmereUI.QoLExtrasGet("fpsShowLocalMS")
                        if sl == nil then return true end
                        return sl
                      end,
                      set=function(v)
                        EllesmereUI.QoLExtrasSet("fpsShowLocalMS", v)
                        if EllesmereUI._applyFPSCounter then EllesmereUI._applyFPSCounter() end
                      end },
                    { type="toggle", label="Show World MS",
                      get=function()
                        return EllesmereUI.QoLExtrasGet("fpsShowWorldMS") or false
                      end,
                      set=function(v)
                        EllesmereUI.QoLExtrasSet("fpsShowWorldMS", v)
                        if EllesmereUI._applyFPSCounter then EllesmereUI._applyFPSCounter() end
                      end },
                    { type="toggle", label="Hide Local/World Label",
                      get=function()
                        return EllesmereUI.QoLExtrasGet("fpsHideLabel") or false
                      end,
                      set=function(v)
                        EllesmereUI.QoLExtrasSet("fpsHideLabel", v)
                        if EllesmereUI._applyFPSCounter then EllesmereUI._applyFPSCounter() end
                      end },
                    { type="slider", label="Update Interval", min=1, max=5, step=1,
                      get=function()
                        return EllesmereUI.QoLExtrasGet("fpsUpdateInterval") or 3
                      end,
                      set=function(v)
                        EllesmereUI.QoLExtrasSet("fpsUpdateInterval", v)
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
                kbLbl:SetText(EllesmereUI.L("Press a key..."))
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

        -- Row 2: Low Durability Warning (left, with cog+eye+swatch) | Disable Right Click Targeting (right)
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
                if EllesmereUI._syncDurWarnEvents then EllesmereUI._syncDurWarnEvents() end
                if not v and EllesmereUI._durWarnHidePreview then
                    EllesmereUI._durWarnHidePreview()
                end
                EllesmereUI:RefreshPage()
              end },
            { type="dropdown", text="Disable Right Click",
              tooltip="Suppresses right click targeting. Enemies applies everywhere. Allies In Combat only suppresses friendly targets while you are in combat, so you can still right click vendors and NPCs out of combat.",
              values={ ["_placeholder"]="..." }, order={ "_placeholder" },
              getValue=function() return "_placeholder" end,
              setValue=function() end }
        );  y = y - h

        -- Right slot: multi-select dropdown (Enemies / Allies In Combat).
        -- The backend stays two independent booleans; the dropdown is purely a
        -- front-end grouping, so existing disableRightClickTarget users are kept
        -- exactly as-is and Allies is additive (defaults off).
        do
            local rcRgn = durWarnRow._rightRegion
            if rcRgn._control then rcRgn._control:Hide() end
            local rcItems = {
                { key = "enemy", label = "Enemies" },
                { key = "ally",  label = "Allies In Combat" },
            }
            local rcCB, rcCBRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                rcRgn, 200, rcRgn:GetFrameLevel() + 2,
                rcItems,
                function(k)
                    if not EllesmereUIDB then return false end
                    if k == "enemy" then return EllesmereUIDB.disableRightClickTarget or false end
                    return EllesmereUIDB.disableRightClickTargetAllyCombat or false
                end,
                function(k, v)
                    if not EllesmereUIDB then EllesmereUIDB = {} end
                    if k == "enemy" then
                        EllesmereUIDB.disableRightClickTarget = v
                    else
                        EllesmereUIDB.disableRightClickTargetAllyCombat = v
                    end
                    if EllesmereUI._applyRightClickTarget then EllesmereUI._applyRightClickTarget() end
                end)
            PP.Point(rcCB, "RIGHT", rcRgn, "RIGHT", -20, 0)
            rcRgn._control = rcCB
            rcRgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(rcCBRefresh)
        end

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
                    { type="slider", label="Text Size",
                      min=10, max=50, step=1,
                      get=function()
                        return (EllesmereUIDB and EllesmereUIDB.durWarnTextSize) or 30
                      end,
                      set=function(v)
                        if not EllesmereUIDB then EllesmereUIDB = {} end
                        EllesmereUIDB.durWarnTextSize = v
                        if EllesmereUI._durWarnApplySettings then EllesmereUI._durWarnApplySettings() end
                      end },
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
                      min=5, max=100, step=1,
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

        -- Row 3: Secondary Stat Display (left, with swatch+cog) | Guild Chat Privacy (right)
        local row4
        row4, h = W:DualRow(parent, y,
            { type="toggle", text="Secondary Stat Display",
              tooltip="Displays secondary stat percentages (Crit, Haste, Mastery, Vers) at the top left of the screen.",
              getValue=function()
                return EllesmereUI.QoLExtrasGet("showSecondaryStats") or false
              end,
              setValue=function(v)
                EllesmereUI.QoLExtrasSet("showSecondaryStats", v)
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
                return not EllesmereUI.QoLExtrasGet("showSecondaryStats")
            end

            -- Color swatch for label color (defaults to class color)
            local ssSwGet = function()
                local c = EllesmereUI.QoLExtrasGet("secondaryStatsColor")
                if c then return c.r, c.g, c.b end
                local _, cls = UnitClass("player")
                local cc = cls and EllesmereUI.GetClassColor(cls)
                if cc then return cc.r, cc.g, cc.b end
                return 1, 1, 1
            end
            local ssSwSet = function(r, g, b)
                EllesmereUI.QoLExtrasSet("secondaryStatsColor", { r = r, g = g, b = b })
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
                          return EllesmereUI.QoLExtrasGet("showTertiaryStats") or false
                      end,
                      set = function(v)
                          EllesmereUI.QoLExtrasSet("showTertiaryStats", v)
                          if EllesmereUI._applySecondaryStats then EllesmereUI._applySecondaryStats() end
                      end },
                    { type = "colorpicker", label = "Tertiary Label Color",
                      disabled = function()
                          return not EllesmereUI.QoLExtrasGet("showTertiaryStats")
                      end,
                      disabledTooltip = "Show Tertiary Stats",
                      get = function()
                          local c = EllesmereUI.QoLExtrasGet("tertiaryStatsColor")
                          if c then return c.r, c.g, c.b end
                          local _, cls = UnitClass("player")
                          local cc = cls and EllesmereUI.GetClassColor(cls)
                          if cc then return cc.r, cc.g, cc.b end
                          return 1, 1, 1
                      end,
                      set = function(r, g, b)
                          EllesmereUI.QoLExtrasSet("tertiaryStatsColor", { r = r, g = g, b = b })
                          if EllesmereUI._applySecondaryStats then EllesmereUI._applySecondaryStats() end
                      end },
                    { type = "slider", label = "Scale", min = 50, max = 200, step = 5,
                      get = function()
                          local pos = EllesmereUI.QoLExtrasGet("secondaryStatsPos")
                          return math.floor(((pos and pos.scale) or 1.0) * 100 + 0.5)
                      end,
                      set = function(v)
                          -- Shallow-copy so we never mutate the shared account-wide
                          -- fallback table in place; the write lands per-profile.
                          local prev = EllesmereUI.QoLExtrasGet("secondaryStatsPos")
                          local newPos = {}
                          if prev then for pk, pv in pairs(prev) do newPos[pk] = pv end end
                          newPos.scale = v / 100
                          EllesmereUI.QoLExtrasSet("secondaryStatsPos", newPos)
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

        -- Row 4: Rested Indicator (left) |
        local restedRow
        restedRow, h = W:DualRow(parent, y,
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
              end },
            { type="label", text="" }
        );  y = y - h

        -- Inline cog on Rested Indicator (left region) for X/Y offsets
        do
            local leftRgn = restedRow._leftRegion
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
            local restCogBtn = CreateFrame("Button", nil, leftRgn)
            restCogBtn:SetSize(26, 26)
            restCogBtn:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -9, 0)
            leftRgn._lastInline = restCogBtn
            restCogBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
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

        _, h = W:Spacer(parent, y, 20);  y = y - h

        ---------------------------------------------------------------------------
        --  CROSSHAIR
        ---------------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "CROSSHAIR", y);  y = y - h

        -- Crosshair: per-profile live in the QoL DB (_ECL_AceDB.profile),
        -- with the account-wide EllesmereUIDB root as the inherited default.
        local function cdb() return _G._ECL_AceDB and _G._ECL_AceDB.profile end
        local function cget(k)
            local p = cdb()
            if p and p[k] ~= nil then return p[k] end
            return EllesmereUIDB and EllesmereUIDB[k]
        end
        local function cset(k, v) local p = cdb(); if p then p[k] = v end end
        local function crosshairOff()
            return (cget("crosshairSize") or "None") == "None"
        end

        -- True when the effective thickness is custom (would display as
        -- "Custom" if enabled) -- i.e. H/V widths differ or don't match a preset.
        -- Checked regardless of None so a saved custom config can be restored.
        local function crosshairIsCustom()
            local P = EllesmereUI.CROSSHAIR_PRESETS
            local s = cget("crosshairSize")
            local sizeForBase = (s and s ~= "None" and s) or "Normal"
            local base = (P and (P[sizeForBase] or P.Normal)) or { width = 2 }
            local hw = cget("crosshairHWidth") or base.width
            local vw = cget("crosshairVWidth") or base.width
            if hw ~= vw then return true end
            if P then
                for _, p in pairs(P) do if p.width == hw then return false end end
            end
            return true
        end

        -- Row 1: Character Crosshair (left: dropdown + swatch + cog) | Visibility
        local crosshairRow
        crosshairRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Character Crosshair",
              tooltip="Displays a crosshair at the center of the screen.",
              -- "Custom" is only selectable when a custom thickness is
              -- stored (re-evaluated each time the menu opens); otherwise it's
              -- greyed, since picking it would just produce a preset look.
              itemDisabled=function(v) return v == "custom" and not crosshairIsCustom() end,
			  itemDisabledTooltip=function(v)
				if v == "custom" then return "This option requires a custom thickness to be set." end
      		  end,
              -- The shown value is derived from the actual thickness: a preset
              -- name when the width matches one, otherwise "Custom". "Custom" is
              -- also selectable -- picking it re-enables using the user's stored
              -- values
              values={ ["None"]="None", ["Thin"]="Thin", ["Normal"]="Normal", ["Thick"]="Thick", ["custom"]="Custom" },
              order={ "None", "Thin", "Normal", "Thick", "custom" },
              getValue=function()
                local size = cget("crosshairSize") or "None"
                if size == "None" then return "None" end
                local P = EllesmereUI.CROSSHAIR_PRESETS
                local base = (P and (P[size] or P.Normal)) or { width = 2 }
                local hw = cget("crosshairHWidth") or base.width
                local vw = cget("crosshairVWidth") or base.width
                if hw == vw and P then
                    for name, p in pairs(P) do
                        if p.width == hw then return name end
                    end
                end
                return "custom"
              end,
              setValue=function(v)
                local p = cdb()
                if not p then return end
                p.crosshairSize = v
                -- Presets exist mainly for backwards compatibility. They stamp
                -- only the thickness baseline so Thin/Normal/Thick stay distinct
                -- and the cog reflects them. Length is not touched: it defaults
                -- to the preset length (40) only while unset, and once a user
                -- customises it, it persists across preset changes.
                local preset = EllesmereUI.CROSSHAIR_PRESETS and EllesmereUI.CROSSHAIR_PRESETS[v]
                if preset then
                    p.crosshairHWidth = preset.width
                    p.crosshairVWidth = preset.width
                end
                if EllesmereUI._applyCrosshair then EllesmereUI._applyCrosshair() end
                EllesmereUI:RefreshPage()
              end },
            { type="dropdown", text="Visibility",
              tooltip="Choose when the crosshair is shown.",
              disabled=function() return crosshairOff() end,
              disabledTooltip="Enable the crosshair to set its visibility.", rawTooltip=true,
              -- Real control is a multi-select checkbox dropdown injected below;
              -- this placeholder just provides the labelled right-region slot.
              values={ ["_placeholder"]="..." }, order={ "_placeholder" },
              getValue=function() return "_placeholder" end,
              setValue=function() end }
        );  y = y - h

        -- Visibility: multi-select checkbox dropdown (Always / Combat / Instances),
        -- backed by the single crosshairVisibility string for backwards compat:
        --   always | combat | instances | instances_combat
        -- "Always" is the base state. Picking it
        -- clears the others; clearing both reverts to it.
        do
            local visRgn = crosshairRow._rightRegion
            if visRgn._control then visRgn._control:Hide() end

            local function curVis() return cget("crosshairVisibility") or "always" end
            local visItems = {
                { key = "always",    label = "Always",
                  tooltip = "Always show the crosshair." },
                { key = "combat",    label = "Combat",
                  tooltip = "Show only while in combat. Combine with Instances to show only during instanced combat." },
                { key = "instances", label = "Instances",
                  tooltip = "Show only while in a dungeon, raid, arena or battleground. Combine with Combat to show only during instanced combat." },
            }
            local visCB, visCBRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                visRgn, 200, visRgn:GetFrameLevel() + 2,
                visItems,
                function(k)
                    local v = curVis()
                    if k == "always"    then return v == "always" end
                    if k == "combat"    then return v == "combat" or v == "instances_combat" end
                    return v == "instances" or v == "instances_combat"
                end,
                function(k, on)
                    local v = curVis()
                    local combat    = (v == "combat" or v == "instances_combat")
                    local instances = (v == "instances" or v == "instances_combat")
                    if k == "always" then
                        if not on then return end  -- can't un-pick the base state directly
                        combat, instances = false, false
                    elseif k == "combat" then
                        combat = on
                    else
                        instances = on
                    end
                    local nv = "always"
                    if combat and instances then nv = "instances_combat"
                    elseif combat then nv = "combat"
                    elseif instances then nv = "instances" end
                    cset("crosshairVisibility", nv)
                    if EllesmereUI._applyCrosshair then EllesmereUI._applyCrosshair() end
                end)
            PP.Point(visCB, "RIGHT", visRgn, "RIGHT", -20, 0)
            visRgn._control = visCB
            visRgn._lastInline = nil

            -- Disabled overlay: grey + block when the crosshair is off, matching
            -- the placeholder's disabled state.
            local visBlock = CreateFrame("Frame", nil, visCB)
            visBlock:SetAllPoints()
            visBlock:SetFrameLevel(visCB:GetFrameLevel() + 20)
            visBlock:EnableMouse(true)
            visBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(visCB, "Enable the crosshair to set its visibility.")
            end)
            visBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function visUpdateDisabled()
                if crosshairOff() then
                    visCB:SetAlpha(0.4); visBlock:Show()
                else
                    visCB:SetAlpha(1); visBlock:Hide()
                end
            end
            EllesmereUI.RegisterWidgetRefresh(visCBRefresh)
            EllesmereUI.RegisterWidgetRefresh(visUpdateDisabled)
            visUpdateDisabled()
        end

        -- Inline color swatch on the crosshair dropdown (left region)
        do
            local leftRgn = crosshairRow._leftRegion

            local chSwGet = function()
                local c = cget("crosshairColor")
                if c then return c.r, c.g, c.b, c.a end
                return 1, 1, 1, 0.75
            end
            local chSwSet = function(r, g, b, a)
                cset("crosshairColor", { r = r, g = g, b = b, a = a or 1 })
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

        -- Inline cog on the crosshair dropdown (left region) for expanded options
        do
            local leftRgn = crosshairRow._leftRegion
            local function chCogOff() return crosshairOff() end
            local function presetThick()
                local s = cget("crosshairSize")
                local P = EllesmereUI.CROSSHAIR_PRESETS
                local p = P and (P[s] or P.Normal)
                return (p and p.width) or 2
            end
            local function applyCH()
                if EllesmereUI._applyCrosshair then EllesmereUI._applyCrosshair() end
            end
            local function dbset(k, v)
                cset(k, v)
                applyCH()
            end
            -- Re-resolve the size dropdown's label so it shows "Custom" (or snaps
            -- back to a preset) live when the thickness is changed in this cog.
            local function refreshSizeLabel()
                local ctrl = crosshairRow._leftRegion and crosshairRow._leftRegion._control
                if ctrl and ctrl._refreshLabel then ctrl._refreshLabel() end
            end

            local chCogRows = {
                    { type="slider", label="H Length", min=1, max=100, step=1,
                      get=function() return cget("crosshairHLength") or 40 end,
                      set=function(v) dbset("crosshairHLength", v) end },
                    { type="slider", label="H Width", min=1, max=20, step=1,
                      get=function() return cget("crosshairHWidth") or presetThick() end,
                      set=function(v) dbset("crosshairHWidth", v); refreshSizeLabel() end },
                    { type="slider", label="V Length", min=1, max=100, step=1,
                      get=function() return cget("crosshairVLength") or 40 end,
                      set=function(v) dbset("crosshairVLength", v) end },
                    { type="slider", label="V Width", min=1, max=20, step=1,
                      get=function() return cget("crosshairVWidth") or presetThick() end,
                      set=function(v) dbset("crosshairVWidth", v); refreshSizeLabel() end },
                    { type="slider", label="Border", min=0, max=5, step=1,
                      get=function() return cget("crosshairBorderSize") or 0 end,
                      set=function(v) dbset("crosshairBorderSize", v) end },
                    { type="colorpicker", label="Border Color", hasAlpha=true,
                      get=function()
                          local bc = cget("crosshairBorderColor")
                          if bc then return bc.r, bc.g, bc.b, bc.a end
                          return 0, 0, 0, 1
                      end,
                      set=function(r, g, b, a)
                          cset("crosshairBorderColor", { r = r, g = g, b = b, a = a or 1 })
                          applyCH()
                      end },
                    { type="slider", label="X Offset", min=-200, max=200, step=1,
                      get=function() return cget("crosshairXOffset") or 0 end,
                      set=function(v) dbset("crosshairXOffset", v) end },
                    { type="slider", label="Y Offset", min=-200, max=200, step=1,
                      get=function() return cget("crosshairYOffset") or 0 end,
                      set=function(v) dbset("crosshairYOffset", v) end },
            }
            -- Holy Paladin uses a 40yd out-of-range cutoff by default; let
            -- paladins opt into a melee (5yd) cutoff. Shown only for Paladins.
            if select(2, UnitClass("player")) == "PALADIN" then
                chCogRows[#chCogRows + 1] = {
                    type="toggle", label="Show Melee Range for Hpal",
                    get=function() return cget("crosshairHpalMelee") == true end,
                    set=function(v)
                        cset("crosshairHpalMelee", v)
                        if EllesmereUI._RefreshCrosshairCutoffRange then EllesmereUI._RefreshCrosshairCutoffRange() end
                        applyCH()
                    end,
                }
            end
            local _, chCogShow = EllesmereUI.BuildCogPopup({
                title = "Crosshair Options",
                rows = chCogRows,
            })

            local chCogBtn = CreateFrame("Button", nil, leftRgn)
            chCogBtn:SetSize(26, 26)
            chCogBtn:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -9, 0)
            leftRgn._lastInline = chCogBtn
            chCogBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
            chCogBtn:SetAlpha(chCogOff() and 0.15 or 0.4)
            local chCogTex = chCogBtn:CreateTexture(nil, "OVERLAY")
            chCogTex:SetAllPoints()
            chCogTex:SetTexture(EllesmereUI.COGS_ICON)
            chCogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            chCogBtn:SetScript("OnLeave", function(self) self:SetAlpha(chCogOff() and 0.15 or 0.4) end)
            chCogBtn:SetScript("OnClick", function(self) chCogShow(self) end)

            -- Blocking overlay when the crosshair is off (None)
            local chCogBlock = CreateFrame("Frame", nil, chCogBtn)
            chCogBlock:SetAllPoints()
            chCogBlock:SetFrameLevel(chCogBtn:GetFrameLevel() + 10)
            chCogBlock:EnableMouse(true)
            chCogBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(chCogBtn, EllesmereUI.DisabledTooltip("Character Crosshair"))
            end)
            chCogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateChCogState()
                local off = chCogOff()
                chCogBtn:SetAlpha(off and 0.15 or 0.4)
                if off then chCogBlock:Show() else chCogBlock:Hide() end
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateChCogState)
            UpdateChCogState()
        end

        -- Color Out of Range (toggle + inline color picker)
        local meleeRow
        meleeRow, h = W:DualRow(parent, y,
            { type="toggle", text="Color Out of Range",
              tooltip=function()
                  local s = EllesmereUI.L("Changes the crosshair color when your current target is out of range.")
                  if EllesmereUI._getCrosshairCutoffRange then
                      local range = EllesmereUI._getCrosshairCutoffRange()
                      s = s .. " " .. EllesmereUI.Lf("Currently active range cutoff: %1$syd.", range)
                  end
                  return s
              end,
              disabled=function() return crosshairOff() end,
              disabledTooltip="Enable the crosshair to use this option.", rawTooltip=true,
              getValue=function() return cget("crosshairMeleeColorEnabled") == true end,
              setValue=function(v)
                cset("crosshairMeleeColorEnabled", v)
                if EllesmereUI._applyCrosshair then EllesmereUI._applyCrosshair() end
                EllesmereUI:RefreshPage()
              end },
            { type="label", text="" }
        );  y = y - h
        -- Inline color swatch (disabled when toggle is off or crosshair is None)
        do
            local leftRgn = meleeRow._leftRegion
            local function meleeOff()
                return crosshairOff() or cget("crosshairMeleeColorEnabled") ~= true
            end
            local mcGet = function()
                local c = cget("crosshairMeleeColor")
                if c then return c.r, c.g, c.b, c.a end
                return 1, 0, 0, 1
            end
            local mcSet = function(r, g, b, a)
                cset("crosshairMeleeColor", { r = r, g = g, b = b, a = a or 1 })
                if EllesmereUI._applyCrosshair then EllesmereUI._applyCrosshair() end
            end
            local mcSwatch, mcUpdate = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, mcGet, mcSet, true, 20)
            PP.Point(mcSwatch, "RIGHT", leftRgn._control, "LEFT", -12, 0)
            leftRgn._lastInline = mcSwatch

            local mcBlock = CreateFrame("Frame", nil, mcSwatch)
            mcBlock:SetAllPoints()
            mcBlock:SetFrameLevel(mcSwatch:GetFrameLevel() + 10)
            mcBlock:EnableMouse(true)
            mcBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(mcSwatch, EllesmereUI.DisabledTooltip("Color Out of Range"))
            end)
            mcBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = meleeOff()
                mcSwatch:SetAlpha(off and 0.3 or 1)
                if off then mcBlock:Show() else mcBlock:Hide() end
                mcUpdate()
            end)
            local mcInitOff = meleeOff()
            mcSwatch:SetAlpha(mcInitOff and 0.3 or 1)
            if mcInitOff then mcBlock:Show() else mcBlock:Hide() end
        end

        _, h = W:Spacer(parent, y, 20);  y = y - h

        ---------------------------------------------------------------------------
        --  GROUP FINDER
        ---------------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "GROUP FINDER", y);  y = y - h

        _, h = W:DualRow(parent, y,
            { type="toggle", text="Auto Insert Keystone",
              tooltip="Automatically inserts your key into the Font of Power.",
              getValue=function()
                  if not EllesmereUIDB then return true end
                  return EllesmereUIDB.autoInsertKeystone ~= false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.autoInsertKeystone = v
              end },
            { type="toggle", text="Announce Instance Reset",
              tooltip="After a successful instance reset, automatically announces it in party or raid chat so your group knows they can re-enter.",
              getValue=function()
                  return EllesmereUIDB and EllesmereUIDB.instanceResetAnnounce or false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.instanceResetAnnounce = v
                  if EllesmereUI._applyInstanceResetAnnounce then
                      EllesmereUI._applyInstanceResetAnnounce()
                  end
              end }
        );  y = y - h

        local quickSignupRow
        quickSignupRow, h = W:DualRow(parent, y,
            { type="toggle", text="Quick Signup",
              tooltip="Double-click a group listing to instantly sign up without pressing the Sign Up button. Hold Shift to keep the dialog open, e.g. to type a signup note.",
              getValue=function()
                  return EllesmereUIDB and EllesmereUIDB.quickSignup or false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.quickSignup = v
                  if EllesmereUI._applyQuickSignup then
                      EllesmereUI._applyQuickSignup()
                  end
              end },
            { type="toggle", text="Persistent Signup Note",
              tooltip="Keeps your note text in the Sign Up dialog instead of clearing it each time you open it.",
              getValue=function()
                  return EllesmereUIDB and EllesmereUIDB.persistSignupNote or false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.persistSignupNote = v
                  if EllesmereUI._applyPersistSignupNote then
                      EllesmereUI._applyPersistSignupNote()
                  end
              end }
        );  y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h

        ---------------------------------------------------------------------------
        --  UI
        ---------------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "UI", y);  y = y - h

        _, h = W:DualRow(parent, y,
            { type="toggle", text="Hide Screenshot Status",
              tooltip="Hides the 'Screenshot saved' notification that appears on screen after taking a screenshot.",
              getValue=function()
                  if not EllesmereUIDB then return true end
                  return EllesmereUIDB.hideScreenshotStatus ~= false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.hideScreenshotStatus = v
                  if EllesmereUI._applyScreenshotStatus then
                      EllesmereUI._applyScreenshotStatus()
                  end
              end },
            { type="toggle", text="Train All Button",
              tooltip="Adds a 'Train All' button next to the Train button at profession trainers, allowing you to learn all available skills with one click.",
              getValue=function()
                  return EllesmereUIDB and EllesmereUIDB.trainAllButton or false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.trainAllButton = v
                  if EllesmereUI._applyTrainAllButton then
                      EllesmereUI._applyTrainAllButton()
                  end
              end }
        );  y = y - h

        -- Auto Unwrap Collections | Auto Open Containers
        local autoOpenContainerRow
        autoOpenContainerRow, h = W:DualRow(parent, y,
            { type="toggle", text="Auto Unwrap Collections",
              tooltip="Automatically dismisses the 'new mount/pet/toy' fanfare notification when you receive one, so you don't have to click through the collections journal.",
              getValue=function()
                  return EllesmereUIDB and EllesmereUIDB.autoUnwrapCollections or false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.autoUnwrapCollections = v
                  if EllesmereUI._applyAutoUnwrap then
                      EllesmereUI._applyAutoUnwrap()
                  end
              end },
            { type="toggle", text="Auto Open Containers",
              tooltip="Automatically opens bags, boxes and parcels in your inventory when they are added to your bags.",
              getValue=function()
                  if not EllesmereUIDB then return false end
                  return EllesmereUIDB.autoOpenContainers == true
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.autoOpenContainers = v
                  if EllesmereUI._applyAutoOpenContainers then
                      EllesmereUI._applyAutoOpenContainers()
                  end
                  EllesmereUI:RefreshPage()
              end }
        );  y = y - h

        -- Cog on Auto Open Containers (right region)
        do
            local rightRgn = autoOpenContainerRow._rightRegion
            local function autoOpenContainerOff()
                return not (EllesmereUIDB and EllesmereUIDB.autoOpenContainers == true)
            end

            local _, autoOpenContainerCogShow = EllesmereUI.BuildCogPopup({
                title = "Auto Open Containers Settings",
                rows = {
                    { type="toggle", label="Exclude Warbound Containers",
                      get=function()
                          if not EllesmereUIDB then return true end
                          return EllesmereUIDB.autoOpenContainersExcludeWarbound ~= false
                      end,
                      set=function(v)
                          if not EllesmereUIDB then EllesmereUIDB = {} end
                          EllesmereUIDB.autoOpenContainersExcludeWarbound = v
                      end },
                },
            })

            local autoOpenContainerCogBtn = CreateFrame("Button", nil, rightRgn)
            autoOpenContainerCogBtn:SetSize(26, 26)
            autoOpenContainerCogBtn:SetPoint("RIGHT", rightRgn._lastInline or rightRgn._control, "LEFT", -9, 0)
            rightRgn._lastInline = autoOpenContainerCogBtn
            autoOpenContainerCogBtn:SetFrameLevel(rightRgn:GetFrameLevel() + 5)
            autoOpenContainerCogBtn:SetAlpha(autoOpenContainerOff() and 0.15 or 0.4)
            local autoOpenContainerCogTex = autoOpenContainerCogBtn:CreateTexture(nil, "OVERLAY")
            autoOpenContainerCogTex:SetAllPoints()
            autoOpenContainerCogTex:SetTexture(EllesmereUI.COGS_ICON)
            autoOpenContainerCogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            autoOpenContainerCogBtn:SetScript("OnLeave", function(self) self:SetAlpha(autoOpenContainerOff() and 0.15 or 0.4) end)
            autoOpenContainerCogBtn:SetScript("OnClick", function(self) autoOpenContainerCogShow(self) end)

            local autoOpenContainerCogBlock = CreateFrame("Frame", nil, autoOpenContainerCogBtn)
            autoOpenContainerCogBlock:SetAllPoints()
            autoOpenContainerCogBlock:SetFrameLevel(autoOpenContainerCogBtn:GetFrameLevel() + 10)
            autoOpenContainerCogBlock:EnableMouse(true)
            autoOpenContainerCogBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(autoOpenContainerCogBtn, EllesmereUI.DisabledTooltip("Auto Open Containers"))
            end)
            autoOpenContainerCogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            EllesmereUI.RegisterWidgetRefresh(function()
                local off = autoOpenContainerOff()
                autoOpenContainerCogBtn:SetAlpha(off and 0.15 or 0.4)
                if off then autoOpenContainerCogBlock:Show() else autoOpenContainerCogBlock:Hide() end
            end)
            if autoOpenContainerOff() then autoOpenContainerCogBlock:Show() else autoOpenContainerCogBlock:Hide() end
        end

        return math.abs(y)
    end

    EllesmereUI:RegisterModule("EllesmereUIQoL", {
        title       = "Quality of Life",
        description = "Quality of life features and custom cursor.",
        pages       = { PAGE_QOL, PAGE_CURSOR, PAGE_AUTOLOG, PAGE_UPGCALC, PAGE_SHIFTER },
        searchTerms = { "brez", "bres", "battle res", "combat res", "cursor", "macro", "fps", "logging", "combat log", "warcraft logs", "upgrade", "ilvl", "item level", "crest", "upgrade calculator", "shifter", "move", "drag", "position", "demodal", "drift", "combat alert", "enter combat", "leave combat", "in combat", "combat text", "combat notification", "transform", "transforms", "costume", "disguise", "chef's hat", "noggenfogger" },
        buildPage   = function(pageName, parent, yOffset)
            if pageName == PAGE_QOL then
                return BuildQoLPage(pageName, parent, yOffset)
            end
            if pageName == PAGE_CURSOR and _G._EBS_BuildCursorPage then
                return _G._EBS_BuildCursorPage(pageName, parent, yOffset)
            end
            if pageName == PAGE_AUTOLOG and _G._EUI_BuildAutoLoggingPage then
                return _G._EUI_BuildAutoLoggingPage(pageName, parent, yOffset)
            end
            if pageName == PAGE_UPGCALC and _G._EUI_BuildUpgradeCalcPage then
                return _G._EUI_BuildUpgradeCalcPage(pageName, parent, yOffset)
            end
            if pageName == PAGE_SHIFTER and _G._EUI_BuildShifterPage then
                return _G._EUI_BuildShifterPage(pageName, parent, yOffset)
            end
        end,
        onReset = function()
            if EllesmereUIDB then
                EllesmereUIDB.hideBlizzardPartyFrame = false
                EllesmereUIDB.quickLoot = false
                EllesmereUIDB.quickLootShiftSkip = false
                EllesmereUIDB.skipCinematics = false
                EllesmereUIDB.skipCinematicsAuto = false
                EllesmereUIDB.autoFillDelete = false
                EllesmereUIDB.autoInsertKeystone = false
                EllesmereUIDB.instanceResetAnnounce = false
                EllesmereUIDB.instanceResetAnnounceMsg = ""
                EllesmereUIDB.quickSignup = false
                EllesmereUIDB.persistSignupNote = false
                EllesmereUIDB.ahCurrentExpansion = false
                EllesmereUIDB.healthMacroEnabled = false
                EllesmereUIDB.healthMacroPrio1 = 1
                EllesmereUIDB.healthMacroPrio2 = 2
                EllesmereUIDB.healthMacroPrio3 = 3
                EllesmereUIDB.foodMacroEnabled = false
                EllesmereUIDB.hideScreenshotStatus = false
                EllesmereUIDB.trainAllButton = false
                EllesmereUIDB.autoUnwrapCollections = false
                EllesmereUIDB.autoOpenContainers = false
                EllesmereUIDB.autoOpenContainersExcludeWarbound = true
                EllesmereUIDB.autoRepairGuild = false
                EllesmereUIDB.shifterEnabled = false
                EllesmereUIDB.shifterPositions = nil
                EllesmereUIDB.hideErrorMessages = false
                EllesmereUIDB.announceGroupDeaths = false
                EllesmereUIDB.groupDeathTextSize = nil
                EllesmereUIDB.groupDeathAlertPos = nil
                EllesmereUIDB.groupDeathSound = nil      -- legacy boolean (pre-dropdown)
                EllesmereUIDB.groupDeathSoundKey = nil
                EllesmereUIDB.combatAlertEnabled = false
                EllesmereUIDB.combatAlertMode = nil
                EllesmereUIDB.combatAlertTextSize = nil
                EllesmereUIDB.combatAlertPos = nil
                EllesmereUIDB.combatAlertEnterText = nil
                EllesmereUIDB.combatAlertLeaveText = nil
                EllesmereUIDB.combatAlertEnterColor = nil
                EllesmereUIDB.combatAlertLeaveColor = nil
                EllesmereUIDB.combatAlertEnterUseClassColor = nil
                EllesmereUIDB.combatAlertLeaveUseClassColor = nil
                EllesmereUIDB.hideTransforms = false
                EllesmereUIDB.hideTransformItems = nil
            end
            EllesmereUIDB.autoLogging = nil
            if _G._EUI_ResetUpgradeCalc then _G._EUI_ResetUpgradeCalc() end
            if _G._EBS_ResetCursor then _G._EBS_ResetCursor() end
            if EllesmereUI._applyHideBlizzardPartyFrame then EllesmereUI._applyHideBlizzardPartyFrame() end
            if EllesmereUI._applyHideErrorMessages then EllesmereUI._applyHideErrorMessages() end
            if EllesmereUI._applyAnnounceGroupDeaths then EllesmereUI._applyAnnounceGroupDeaths() end
            if EllesmereUI._applyCombatAlert then EllesmereUI._applyCombatAlert() end
            if EllesmereUI._applyHideTransforms then EllesmereUI._applyHideTransforms() end
            if EllesmereUI._applyQuickSignup then EllesmereUI._applyQuickSignup() end
            if EllesmereUI._applyPersistSignupNote then EllesmereUI._applyPersistSignupNote() end
            if EllesmereUI._applyQuickLoot then EllesmereUI._applyQuickLoot() end
            if EllesmereUI._applyInstanceResetAnnounce then EllesmereUI._applyInstanceResetAnnounce() end
            if EllesmereUI._applyAutoOpenContainers then EllesmereUI._applyAutoOpenContainers() end
            if EllesmereUI._ShutdownShifter then EllesmereUI._ShutdownShifter() end
            if _G._EUI_AutoLogging_Check then _G._EUI_AutoLogging_Check() end
            EllesmereUI:InvalidatePageCache()
        end,
    })

    SLASH_EQOL1 = "/qol"
    SlashCmdList.EQOL = function()
        if InCombatLockdown and InCombatLockdown() then return end
        EllesmereUI:ShowModule("EllesmereUIQoL")
    end
end)
