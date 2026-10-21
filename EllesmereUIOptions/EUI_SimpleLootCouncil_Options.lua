if EUI_CLIENT_BLOCKED then return end





local ADDON_NAME = "EllesmereUISimpleLootCouncil"
local ns = EllesmereUI._ModuleNS[ADDON_NAME]
if not ns then return end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")




    local CreateFrame = EllesmereUI._Pool.CreateFrame



    local PAGE_LOOT, PAGE_COUNCIL, PAGE_DATA = "Loot and Sessions", "Loot Council", "Data and Diagnostics"
    local PAGES = { PAGE_LOOT, PAGE_COUNCIL, PAGE_DATA }
    local PAGE_SECTIONS = {
        [PAGE_LOOT] = { "lootHandling", "session", "alts" },
        [PAGE_COUNCIL] = { "council", "voting", "responses", "announcements" },
        [PAGE_DATA] = { "history", "diagnostics" },
    }
    local SUGGEST_MAX, SUGGEST_MIN_CHARS = 8, 2
    local CLOSE_ICON = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png"


    local function SLC()
        local slc = _G.SimpleLootCouncil
        if slc and slc.db and slc.UI and slc.UI.OptionsSchema then return slc end
    end

    local function PageShown()
        return EllesmereUI:IsShown() and EllesmereUI:GetActiveModule() == ADDON_NAME
    end


    local function Invalidate()
        local slc = SLC()
        if slc then slc.Callbacks:Invalidate("options") end
    end


    local rebuildQueued, focusResponse
    local function RequestRebuild()
        if rebuildQueued then return end
        rebuildQueued = true
        C_Timer.After(0, function()
            rebuildQueued = false
            if PageShown() then
                EllesmereUI:RefreshPage(true)
            else
                EllesmereUI:InvalidateModulePageCache(ADDON_NAME)
            end
        end)
    end



    local councilEntries, councilDirty = nil, true
    local councilEvents = {}
    local function CouncilEntries(spec)
        if councilDirty or not councilEntries then
            councilEntries, councilDirty = spec.entries(), false
        end
        return councilEntries
    end



    local subscribed
    local gameEvents = {}
    local function Heard(event)
        if councilEvents[event] then councilDirty = true end
        Invalidate()
    end
    local watcher = _G.CreateFrame("Frame")
    watcher:SetScript("OnEvent", function(_, event) Heard(event) end)
    local function Subscribe(slc, Schema)
        if subscribed then return end
        subscribed = true
        for _, event in ipairs(Schema.Row("council").refreshOn) do councilEvents[event] = true end
        for _, event in ipairs(Schema.Events()) do
            if event:find("^%u[%u_]*$") then
                gameEvents[#gameEvents + 1] = event
            elseif event == "SessionChanged" then
                slc.Callbacks:Register(event, function(_, kind)
                    if kind == nil or Schema.SESSION_KINDS[kind] then Invalidate() end
                end)
            else
                slc.Callbacks:Register(event, function() Heard(event) end)
            end
        end
    end
    local function Listen(on)
        for _, event in ipairs(gameEvents) do
            if on then watcher:RegisterEvent(event) else watcher:UnregisterEvent(event) end
        end
    end







    local function Cfg(row)
        local cfg = { type = row.type, text = row.text, tooltip = row.tooltip,
            values = row.values, order = row.order, inputWidth = row.inputWidth,

            noCapture = true }
        local locked, disabled = row.locked, row.disabled
        local function LockReason()
            if not locked then return nil end
            local _, reason = locked()
            return reason
        end
        cfg.getValue = function()
            if LockReason() then return (locked()) end
            return row.getValue()
        end
        cfg.setValue = function(value)
            if not LockReason() then row.setValue(value) end
            Invalidate()
        end
        if locked or disabled then
            local function Reason() return LockReason() or (disabled and disabled()) end
            cfg.disabled = function() return Reason() ~= nil end
            cfg.disabledTooltip = Reason

            cfg.rawTooltip = true
        end
        return cfg
    end



    local function BoETooltip(row)
        return row.help .. "\n\n" .. (row.status())
    end
    local function BoECfg(row)
        return { type = "input", text = row.text, inputStyle = "popup",
            inputWidth = row.inputWidth, tooltip = BoETooltip(row), noCapture = true,
            getValue = row.getValue,
            setValue = function(text)
                row.setValue(text)
                Invalidate()
            end }
    end








    local function StyledTag(parent, width, onClick, make)
        local btn = (make or CreateFrame)("Button", nil, parent)
        EllesmereUI.PanelPP.Size(btn, width, 24)
        btn:SetFrameLevel(parent:GetFrameLevel() + 5)
        local _, _, label = EllesmereUI.MakeStyledButton(btn, "", 11, EllesmereUI.WB_COLOURS)
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btn:SetScript("OnClick", function(_, button)
            EllesmereUI.HideWidgetTooltip()
            onClick(button)
        end)
        local hoverOn, hoverOff = btn:GetScript("OnEnter"), btn:GetScript("OnLeave")
        btn:SetScript("OnEnter", function(b)
            hoverOn(b)
            if b.tip then EllesmereUI.ShowWidgetTooltip(b, b.tip) end
        end)
        btn:SetScript("OnLeave", function(b)
            hoverOff(b)
            EllesmereUI.HideWidgetTooltip()
        end)
        btn.Label = label
        return btn
    end


    local function CloseButton(row, tip, onClick)
        local btn = CreateFrame("Button", nil, row)
        btn:SetSize(14, 14)
        btn:SetPoint("RIGHT", row, "RIGHT", -20, 0)
        btn:SetFrameLevel(row:GetFrameLevel() + 2)
        btn:SetAlpha(0.5)
        local icon = btn:CreateTexture(nil, "OVERLAY")
        icon:SetAllPoints()
        icon:SetTexture(CLOSE_ICON)
        btn:SetScript("OnEnter", function(b)
            b:SetAlpha(0.9)
            EllesmereUI.ShowWidgetTooltip(b, tip)
        end)
        btn:SetScript("OnLeave", function(b)
            b:SetAlpha(0.5)
            EllesmereUI.HideWidgetTooltip()
        end)
        btn:SetScript("OnClick", onClick)
        return btn
    end

    local function CloseSuggestions(box)
        if EllesmereUI.ContextMenuOwner() == box then EllesmereUI.CloseContextMenu() end
    end





    local addHolder, addBox, addButton
    local addHandlers = {}
    local function AddBox(row, width, buttonText)
        if not addHolder then
            addHolder = _G.CreateFrame("Frame", nil, row)
            addBox = _G.CreateFrame("EditBox", nil, addHolder)
            addBox:SetHeight(28)
            addBox:SetAutoFocus(false)
            addBox:SetFont(EllesmereUI.EXPRESSWAY, 11, "")
            addBox:SetTextColor(1, 1, 1, 0.9)
            addBox:SetJustifyH("LEFT")
            addBox:SetTextInsets(10, 10, 0, 0)
            local bg = addBox:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0, 0, 0, 0.5)
            EllesmereUI.MakeBorder(addBox, 1, 1, 1, 0.2)
            addButton = _G.CreateFrame("Button", nil, addHolder)
            EllesmereUI.PanelPP.Size(addButton, 90, 28)
            EllesmereUI.PanelPP.Point(addButton, "LEFT", addBox, "RIGHT", 8, 0)
            local function Add() if addHandlers.add then addHandlers.add() end end
            EllesmereUI.MakeStyledButton(addButton, buttonText, 12, EllesmereUI.WB_COLOURS, Add)
            addBox:SetScript("OnEnterPressed", Add)
            addBox:SetScript("OnEscapePressed", function(b)
                CloseSuggestions(b)
                b:ClearFocus()
            end)
            addBox:SetScript("OnHide", CloseSuggestions)
            addBox:SetScript("OnTextChanged", function(b, userInput)
                if addHandlers.typed then addHandlers.typed(b, userInput) end
            end)
        end
        addHolder:SetParent(row)
        addHolder:ClearAllPoints()
        addHolder:SetAllPoints(row)
        addHolder:SetFrameLevel(row:GetFrameLevel() + 1)
        addButton:SetFrameLevel(addHolder:GetFrameLevel() + 2)
        addBox:SetWidth(width)
        addBox:ClearAllPoints()
        addBox:SetPoint("LEFT", addHolder, "LEFT", 20, 0)
        addHolder:Show()
        return addBox
    end







    local ART = "Interface\\AddOns\\" .. ADDON_NAME .. "\\art\\"
    local LOGO = { path = ART .. "logo", u = 396 / 512, w = 396 }
    local LOGO_PRIDE = { path = ART .. "logo-pride", u = 398 / 512, w = 398 }
    local LOGO_H, LOGO_V = 36, 36 / 64
    local MODULE_TITLE = "Simple Loot Council"


    local function FindTitle(frame, depth)
        for _, region in ipairs({ frame:GetRegions() }) do

            if region.GetText and region:GetText() == MODULE_TITLE
                and (select(2, region:GetFont()) or 0) >= 30 then
                return region
            end
        end
        if depth == 0 then return nil end
        for _, child in ipairs({ frame:GetChildren() }) do
            local found = FindTitle(child, depth - 1)
            if found then return found end
        end
    end

    local bannerTitle, bannerTexture, bannerVersion, bannerActive, bannerLive, bannerOpacity



    local OPACITY_W, OPACITY_TRACK_H, OPACITY_THUMB_W, OPACITY_GAP = 220, 4, 10, 3

    local function BuildOpacityPanel(slc, button, parent)
        local S, T = slc.Style, slc.Locale.Text
        local panel = _G.CreateFrame("Frame", nil, parent)
        panel:SetFrameLevel(button:GetFrameLevel() + 10)
        panel:EnableMouse(true)
        S.Panel(panel, S.color.rail, 0.98, S.radius.CTRL, S.color.edgeBright)
        panel:SetPoint("TOP", button, "BOTTOM", 0, -OPACITY_GAP)
        panel:Hide()

        local title = S.Label(panel, S.fontBody, "LEFT")
        title:SetPoint("TOPLEFT", panel, "TOPLEFT", S.size.ROW_PAD, -S.size.ROW_PAD)
        title:SetText(T["Window opacity"])
        local value = S.Label(panel, S.fontNumHint, "RIGHT")
        value:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -S.size.ROW_PAD, -S.size.ROW_PAD)

        local trackW = OPACITY_W - S.size.ROW_PAD * 2
        local slider = _G.CreateFrame("Slider", nil, panel)
        slider:SetOrientation("HORIZONTAL")
        slider:SetSize(trackW, S.size.BTN_H_SM)
        slider:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -S.size.ITEM_GAP)
        local track = slider:CreateTexture(nil, "BACKGROUND")
        track:SetSize(trackW, OPACITY_TRACK_H)
        track:SetPoint("LEFT", slider, "LEFT", 0, 0)
        track:SetColorTexture(S.Unpack(S.color.inset))
        local fill = slider:CreateTexture(nil, "ARTWORK")
        fill:SetSize(trackW, OPACITY_TRACK_H)
        fill:SetPoint("LEFT", slider, "LEFT", 0, 0)
        fill:SetColorTexture(S.Unpack(S.color.accentDim))
        local thumb = slider:CreateTexture(nil, "OVERLAY")
        thumb:SetSize(OPACITY_THUMB_W, OPACITY_TRACK_H * 4)
        thumb:SetColorTexture(S.Unpack(S.color.accent))
        slider:SetThumbTexture(thumb)
        slider:SetMinMaxValues(S.WINDOW_ALPHA_MIN, 1)
        slider:SetValueStep(0.05)
        slider:SetObeyStepOnDrag(true)

        local function Show(alpha)
            value:SetText(slc.Locale.Format(T["%d%%"], math.floor(alpha * 100 + 0.5)))
            local share = (alpha - S.WINDOW_ALPHA_MIN) / (1 - S.WINDOW_ALPHA_MIN)
            fill:SetWidth(math.max(1, trackW * share))
        end
        slider:SetScript("OnValueChanged", function(_, alpha)
            S.SetWindowAlpha(alpha)
            Show(S.WindowAlpha())
        end)
        slider:EnableMouseWheel(true)
        slider:SetScript("OnMouseWheel", function(self, delta)
            self:SetValue(self:GetValue() + delta * 0.05)
        end)

        local _, titleH = S.fontBody:GetFont()
        panel:SetSize(OPACITY_W, S.size.ROW_PAD + math.ceil((titleH or 12) * 1.35)
            + S.size.ITEM_GAP + S.size.BTN_H_SM + S.size.ROW_PAD)


        panel:SetScript("OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
        panel:SetScript("OnHide", function(self) self:UnregisterEvent("GLOBAL_MOUSE_DOWN") end)
        panel:SetScript("OnEvent", function(self)
            if not self:IsMouseOver() and not button:IsMouseOver() then self:Hide() end
        end)
        panel.Sync = function()
            local alpha = S.WindowAlpha()
            slider:SetValue(alpha)
            Show(alpha)
        end
        return panel
    end



    local function AlignOpacity()
        local ca = EllesmereUI._clickArea
        if not (bannerOpacity and bannerActive and ca) then return end
        local cx, cy = bannerActive:GetCenter()
        local top = ca:GetTop()
        if not (cx and cy and top) then return end
        local k = ca:GetEffectiveScale() / bannerOpacity:GetEffectiveScale()
        local dy = (top - 31) * k - cy
        bannerOpacity:ClearAllPoints()
        bannerOpacity:SetPoint("CENTER", bannerActive, "CENTER", 0, dy)
    end



    local function RefreshHeaderTags()
        local slc = SLC()
        if not (slc and bannerActive) then return end
        local tags, S = slc.UI.OptionsSchema.Row("statusTags"), slc.Style
        local title, tone, lines = tags.activeTooltip()
        bannerActive.Label:SetText(S.Colorize(S.color[tone], title))
        bannerActive.tip = table.concat(lines, "\n")
        local live = bannerActive:IsShown() and tags.live()
        bannerLive:SetShown(live)
        if live then
            local _, liveTone, liveLines = tags.liveTooltip()
            bannerLive.Label:SetText(S.Colorize(S.color[liveTone], tags.liveText))
            bannerLive.tip = table.concat(liveLines, "\n")
        end
    end

    local function ApplyBanner(slc)
        local pride = slc and slc.Style.PrideActive() or false
        local logo = pride and LOGO_PRIDE or LOGO
        bannerTexture:SetTexture(logo.path)
        bannerTexture:SetTexCoord(0, logo.u, 0, LOGO_V)
        EllesmereUI.PanelPP.Size(bannerTexture, logo.w, LOGO_H)
    end



    local function ShowBanner()
        local slc = SLC()
        local main = EllesmereUI._mainFrame
        if not (slc and main) then return end
        if not bannerTitle then
            bannerTitle = FindTitle(main, 6)
        end
        if not bannerTitle then return end
        if not bannerTexture then
            bannerTexture = bannerTitle:GetParent():CreateTexture(nil, "ARTWORK")
            bannerTexture:SetPoint("TOPLEFT", bannerTitle, "TOPLEFT", 0, 0)

            local slot = { ApplyLogo = function() ApplyBanner(SLC()) end }
            slc.Style.logoWindows[#slc.Style.logoWindows + 1] = slot
        end

        if not bannerVersion then
            bannerVersion = bannerTitle:GetParent():CreateFontString(nil, "OVERLAY")
            bannerVersion:SetFontObject(slc.Style.fontBadge)
            bannerVersion:SetJustifyH("LEFT")
            bannerVersion:SetPoint("BOTTOMLEFT", bannerTexture, "BOTTOMRIGHT", 12, 4)
        end
        bannerVersion:SetText("v" .. tostring(slc.VERSION))

        if not bannerActive then
            bannerActive = StyledTag(bannerTitle:GetParent(), 86, function(button)
                local tags = SLC() and SLC().UI.OptionsSchema.Row("statusTags")
                if button == "LeftButton" and tags and tags.clickActive() then Invalidate() end
            end, _G.CreateFrame)
            EllesmereUI.PanelPP.Point(bannerActive, "LEFT", bannerVersion, "RIGHT", 12, 0)
            bannerLive = StyledTag(bannerTitle:GetParent(), 60, function(button)
                local tags = SLC() and SLC().UI.OptionsSchema.Row("statusTags")
                if tags and tags.clickLive(button) then Invalidate() end
            end, _G.CreateFrame)
            EllesmereUI.PanelPP.Point(bannerLive, "LEFT", bannerActive, "RIGHT", 8, 0)
            local panel
            bannerOpacity = StyledTag(bannerTitle:GetParent(), 86, function(button)
                if button ~= "LeftButton" then return end
                if panel and panel:IsShown() then panel:Hide() return end
                panel = panel or BuildOpacityPanel(SLC(), bannerOpacity, bannerTitle:GetParent())
                panel.Sync()
                panel:Show()
            end, _G.CreateFrame)
            bannerOpacity.Label:SetText(slc.Locale.Text["Opacity"])
            bannerOpacity.tip = slc.Locale.Text["How see-through every Simple Loot Council window is."]
            bannerOpacity.panel = function() return panel end
            bannerOpacity:SetPoint("BOTTOM", bannerActive, "TOP", 0, 8)
        end
        ApplyBanner(slc)
        bannerTexture:Show()
        bannerVersion:Show()
        bannerActive:Show()
        bannerOpacity:Show()
        bannerTitle:SetAlpha(0)
        RefreshHeaderTags()

        AlignOpacity()
        C_Timer.After(0, AlignOpacity)
    end

    local function HideBanner()
        if bannerTexture then bannerTexture:Hide() end
        if bannerVersion then bannerVersion:Hide() end
        if bannerActive then bannerActive:Hide() end
        if bannerLive then bannerLive:Hide() end
        if bannerOpacity then
            bannerOpacity:Hide()
            local panel = bannerOpacity.panel()
            if panel then panel:Hide() end
        end
        if bannerTitle then bannerTitle:SetAlpha(1) end
    end


    local function PageSections(Schema, pageName)
        local byId, list = {}, {}
        for _, section in ipairs(Schema.Sections()) do byId[section.id] = section end
        for _, id in ipairs(PAGE_SECTIONS[pageName] or {}) do
            if byId[id] then list[#list + 1] = byId[id] end
        end
        return list
    end






    local STATUS_MAX_ROWS, STATUS_ROW_H, STATUS_TOP, STATUS_BOTTOM, STATUS_MASTER_H = 6, 20, 36, 12, 22

    local STATUS_BTN_H, STATUS_BTN_FONT, STATUS_EUI_BTN_W, STATUS_BTN_ROWS, STATUS_MIN_GAP = 37, 12, 205, 3, 10


    local function StatusHeight(entries)
        local shown = math.min(math.max(entries, 1), STATUS_MAX_ROWS)
        local card = STATUS_TOP + shown * STATUS_ROW_H + STATUS_MASTER_H + STATUS_BOTTOM
        return math.max(card, STATUS_BTN_ROWS * STATUS_BTN_H + (STATUS_BTN_ROWS + 1) * STATUS_MIN_GAP)
    end
    local function StatusCapacity(height)
        local rows = math.floor((height - STATUS_TOP - STATUS_MASTER_H - STATUS_BOTTOM) / STATUS_ROW_H)
        return math.max(1, math.min(rows, STATUS_MAX_ROWS))
    end





    local function BuildSettingsPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local PP = EllesmereUI.PanelPP
        local PAD = EllesmereUI.CONTENT_PAD

        local prebuild = EllesmereUI.IsSearchPrebuild()
        local y = yOffset
        local _, h

        EllesmereUI:ClearContentHeader()

        local slc = SLC()
        if not slc then return math.abs(y) end

        if not prebuild then parent._showRowDivider = true end
        councilDirty = true
        local Schema, S = slc.UI.OptionsSchema, slc.Style

        local T, Format = slc.Locale.Text, slc.Locale.Format
        local refreshes = {}
        local function OnRefresh(fn) refreshes[#refreshes + 1] = fn end


        local colX, colW = 0, nil
        local function Width() return colW or (parent:GetWidth() - PAD * 2) end


        local function Row(height)
            local row = CreateFrame("Frame", nil, parent)
            PP.Size(row, Width(), height)
            PP.Point(row, "TOPLEFT", parent, "TOPLEFT", PAD + colX, y)
            row._skipRowDivider = true
            EllesmereUI.RowBg(row, parent)
            y = y - height
            return row
        end


        local function Note(text, alpha)
            local row = CreateFrame("Frame", nil, parent)
            row._skipRowDivider = true
            local label = EllesmereUI.MakeFont(row, 12, nil, 1, 1, 1)
            label:SetAlpha(alpha or 0.45)
            label:SetJustifyH("LEFT")
            label:SetWordWrap(true)
            label:SetWidth(Width() - 40)
            label:SetPoint("TOPLEFT", row, "TOPLEFT", 20, -10)
            label:SetText(text)
            local textH = label:GetStringHeight()
            if type(textH) ~= "number" or (issecretvalue and issecretvalue(textH)) then textH = 14 end
            local height = math.max(34, math.ceil(textH) + 20)
            PP.Size(row, Width(), height)
            PP.Point(row, "TOPLEFT", parent, "TOPLEFT", PAD + colX, y)
            y = y - height
            return label
        end

        local function ClassText(classFile, text, fallback)
            local r, g, b = S.ClassColor(classFile)
            return S.Colorize(r and { r, g, b } or fallback or S.color.text, text)
        end
        local function PlayerText(fullName)
            local record = slc.Player:Get(fullName)
            return ClassText(record and record.classFile, Ambiguate(fullName, "short"))
        end
        local function RankText(rankName) return S.Colorize(S.color.accentPale, rankName) end
        local faint = S.ColorStart(S.Flatten(S.color.textFaint))


        local pending, lastRightId
        local function Place(cfg, decorate, id, dependsOn)
            if not pending then
                pending = { cfg = cfg, decorate = decorate, id = id, dependsOn = dependsOn }
                return
            end
            local frame
            frame, h = W:DualRow(parent, y, pending.cfg, cfg);  y = y - h
            if not prebuild then
                if pending.decorate then pending.decorate(frame._leftRegion) end
                if decorate then decorate(frame._rightRegion) end
            end
            pending, lastRightId = nil, id
        end


        local function Flush()
            if not pending then return end
            local frame
            if pending.dependsOn and pending.dependsOn == lastRightId then
                frame, h = W:DualRow(parent, y, EllesmereUI.BlankRowCfg(), pending.cfg);  y = y - h
                if not prebuild and pending.decorate then pending.decorate(frame._rightRegion) end
            else
                frame, h = W:DualRow(parent, y, pending.cfg, EllesmereUI.BlankRowCfg());  y = y - h
                if not prebuild and pending.decorate then pending.decorate(frame._leftRegion) end
            end
            pending, lastRightId = nil, nil
        end



        local function LeftAlign(box)
            box:SetJustifyH("LEFT")
            box:SetTextInsets(10, 10, 0, 0)
        end
        local function AttachSuggest(box, row, commit)
            LeftAlign(box)

            local function Tint(b)
                local r, g, b2 = S.ClassColor(row.classFile and row.classFile(b:GetText()))
                if r then b:SetTextColor(r, g, b2) else b:SetTextColor(1, 1, 1, 0.9) end
            end
            box:HookScript("OnHide", CloseSuggestions)
            box:HookScript("OnEscapePressed", CloseSuggestions)
            box:HookScript("OnTextChanged", Tint)
            Tint(box)
            box:HookScript("OnTextChanged", function(b, userInput)
                if not userInput then return end
                CloseSuggestions(b)
                local text = (b:GetText() or ""):trim()
                if select(2, text:gsub("[^\128-\191]", "")) < SUGGEST_MIN_CHARS then return end
                local items = {}
                for _, entry in ipairs(row.suggest(text, SUGGEST_MAX)) do
                    local name = (tostring(entry.name):gsub("|", "||"))
                    local rank = (tostring(entry.rank or ""):gsub("|", "||"))
                    items[#items + 1] = { noLoc = true,
                        text = ClassText(entry.classFile, name, entry.online and S.color.text or S.color.textFaint)
                            .. "  " .. faint .. rank .. "|r",
                        onClick = function()

                            local fill = row.suggestionText(entry)
                            CloseSuggestions(b)
                            b:SetText(fill)
                            b:ClearFocus()
                            commit(fill)
                        end }
                end
                if #items > 0 then
                    EllesmereUI.ShowContextMenu(b, items, { below = true, minWidth = b:GetWidth(),
                        pickOnDown = true, scaleToAnchor = true })
                end
            end)
        end



        local function Decorator(row, cfg)
            if not (row.danger or row.status) then return nil end
            return function(region)
                if row.danger and region._label then
                    region._label:SetTextColor(S.Unpack(S.color.bad))
                end
                if row.status then
                    OnRefresh(function() cfg.tooltip = (row.status()) end)
                end
            end
        end






        local tags, lootMaster = Schema.Row("statusTags"), Schema.Row("lootMaster")
        local inForce = Schema.Row("councilInForce")
        local actions = Schema.Actions()

        local withStatus = pageName == PAGE_LOOT
        if withStatus then
            _, h = W:SectionHeader(parent, tags.heading:upper(), y);  y = y - h
        end
        if not prebuild then OnRefresh(RefreshHeaderTags) end



        local function Open(action)
            return function()
                EllesmereUI:Hide()
                action.onClick()
            end
        end

        if not withStatus then

        elseif prebuild then

            for i = 1, #actions, 3 do
                local a, b, c = actions[i], actions[i + 1], actions[i + 2]
                _, h = W:WideTripleButton(parent, a.text, b and b.text, c and c.text, y);  y = y - h
            end
        else
            local GAP = 20
            local full = parent:GetWidth() - PAD * 2
            local half = math.floor((full - GAP) / 2)
            local top = y
            local height = StatusHeight(#inForce.entries(PlayerText, RankText))

            local block = CreateFrame("Frame", nil, parent)
            PP.Size(block, full, height)
            PP.Point(block, "TOPLEFT", parent, "TOPLEFT", PAD, top)
            block._skipRowDivider = true
            EllesmereUI.RowBg(block, parent)
            local rule = block:CreateTexture(nil, "ARTWORK")
            rule:SetColorTexture(1, 1, 1, 0.08)
            rule:SetWidth(1)
            rule:SetPoint("TOPLEFT", block, "TOPLEFT", half + GAP / 2, -4)
            rule:SetPoint("BOTTOMLEFT", block, "BOTTOMLEFT", half + GAP / 2, 4)
            y = top - height


            local card = CreateFrame("Frame", nil, block)
            PP.Size(card, half, height)
            PP.Point(card, "TOPLEFT", block, "TOPLEFT", 0, 0)
            local heading = EllesmereUI.MakeFont(card, 11, nil, 1, 1, 1)
            heading:SetAlpha(0.45)
            heading:SetPoint("TOPLEFT", card, "TOPLEFT", 20, -14)
            heading:SetText(inForce.heading)
            local voters = EllesmereUI.MakeFont(card, 12, nil, 1, 1, 1)
            voters:SetPoint("LEFT", heading, "RIGHT", 8, 0)
            local entryRows = {}
            for i = 1, STATUS_MAX_ROWS do
                local row = CreateFrame("Frame", nil, card)
                row:SetPoint("TOPLEFT", card, "TOPLEFT", 20, -STATUS_TOP - (i - 1) * STATUS_ROW_H)
                row:SetPoint("TOPRIGHT", card, "TOPRIGHT", -20, -STATUS_TOP - (i - 1) * STATUS_ROW_H)
                row:SetHeight(STATUS_ROW_H)
                row.label = EllesmereUI.MakeFont(row, 13, nil, 1, 1, 1)
                row.label:SetJustifyH("LEFT")
                row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
                row.count = EllesmereUI.MakeFont(row, 12, nil, 1, 1, 1)
                row.count:SetPoint("RIGHT", row, "RIGHT", 0, 0)
                row:EnableMouse(true)
                row:SetScript("OnEnter", function(self)
                    if self.tip then EllesmereUI.ShowWidgetTooltip(self, self.tip) end
                end)
                row:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                entryRows[i] = row
            end
            local masterLabel = EllesmereUI.MakeFont(card, 12, nil, 1, 1, 1)
            masterLabel:SetAlpha(0.85)
            masterLabel:SetJustifyH("LEFT")
            masterLabel:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 20, STATUS_BOTTOM)
            masterLabel:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -20, STATUS_BOTTOM)

            OnRefresh(function()
                masterLabel:SetText(Format(lootMaster.line, lootMaster.name(), lootMaster.role()))
            end)
            OnRefresh(function()
                local entries, count = inForce.entries(PlayerText, RankText)
                count = tonumber(count) or 0
                voters:SetText(S.Colorize(count == 0 and S.color.bad or S.color.accentPale, tostring(count)))
                if #entries == 0 then entries[1] = { text = S.Colorize(S.color.bad, inForce.emptyText) } end
                local capacity = StatusCapacity(height)


                if #entries > capacity then
                    local hidden, members, ranksHidden = {}, 0, false
                    for i = capacity, #entries do
                        local entry = entries[i]
                        hidden[#hidden + 1] = entry.count and Format(T["%s (%s)"], entry.text, entry.count)
                            or entry.text
                        for _, line in ipairs(entry.rank and entry.tooltip or {}) do
                            hidden[#hidden + 1] = "  " .. line
                        end
                        if entry.rank then ranksHidden = true else members = members + 1 end
                    end
                    local overflow = #entries - capacity + 1
                    entries[capacity] = { tooltip = hidden, overflow = true,
                        text = ranksHidden
                            and Format(slc.Locale.Plural{ one = "%d entries hidden", other = "%d entries hidden" },
                                overflow, overflow)
                            or Format(slc.Locale.Plural{ one = "%d member hidden", other = "%d members hidden" },
                                members, members) }
                end
                for i, row in ipairs(entryRows) do
                    local entry = i <= capacity and entries[i]
                    row:SetShown(entry and true or false)
                    if entry then
                        row.label:SetText(entry.text)
                        row.count:SetText(entry.count or "")
                        row.label:SetPoint("RIGHT", row, "RIGHT", entry.count and -34 or 0, 0)
                        local tip = entry.tooltip and #entry.tooltip > 0
                            and ((entry.overflow and "" or entry.text .. "\n") .. table.concat(entry.tooltip, "\n"))
                        row.tip = tip or nil
                    end
                end
            end)





            local grid = CreateFrame("Frame", nil, block)
            PP.Size(grid, half, height)
            PP.Point(grid, "TOPLEFT", block, "TOPLEFT", half + GAP, 0)
            local buttons, widest = {}, 0
            for i, action in ipairs(actions) do
                local btn = CreateFrame("Button", nil, grid)
                btn:SetFrameLevel(grid:GetFrameLevel() + 1)
                local _, _, label = EllesmereUI.MakeStyledButton(btn, action.text, STATUS_BTN_FONT,
                    EllesmereUI.WB_COLOURS, Open(action))
                local w = label and label:GetStringWidth()
                if type(w) ~= "number" or (issecretvalue and issecretvalue(w)) then
                    w = #action.text * STATUS_BTN_FONT * 0.55
                end
                widest = math.max(widest, w)
                buttons[i] = btn
            end
            local sidePad = math.max(0, (STATUS_EUI_BTN_W - widest) / 2) * 0.2
            local btnW = math.ceil(widest + sidePad * 2)
            local rows = math.ceil(#buttons / 2)
            local gapX = math.max(0, (half - 2 * btnW) / 3)
            local gapY = math.max(0, (height - rows * STATUS_BTN_H) / (rows + 1))
            for i, btn in ipairs(buttons) do
                local col, line = (i - 1) % 2, math.floor((i - 1) / 2)
                PP.Size(btn, btnW, STATUS_BTN_H)
                PP.Point(btn, "TOPLEFT", grid, "TOPLEFT", gapX + col * (btnW + gapX),
                    -(gapY + line * (STATUS_BTN_H + gapY)))
            end
        end




        local custom = {}



        function custom.responses(spec)
            for index, built in ipairs(spec.list()) do


                local entry = built
                OnRefresh(function() entry = spec.list()[index] or entry end)
                local nameCfg = { type = "input", text = Format(spec.nameLabel, index),
                    inputStyle = "popup", inputWidth = 180, noCapture = true,
                    getValue = function() return entry.text or "" end,

                    setValue = function(text) spec.setName(index, text) Invalidate() end }
                local keysCfg = { type = "input", text = spec.keysLabel,
                    inputStyle = "popup", inputWidth = 180, noCapture = true,
                    getValue = function() return entry.whisper or "" end,
                    setValue = function(text) spec.setKeys(index, text) end }
                local frame
                frame, h = W:DualRow(parent, y, nameCfg, keysCfg);  y = y - h
                if not prebuild then
                    local region = frame._leftRegion
                    if region._control then

                        region._control:SetMaxLetters(spec.maxLetters)
                        if focusResponse == index then
                            focusResponse = nil
                            region._control:SetFocus()
                            region._control:HighlightText()
                        end
                    end

                    EllesmereUI.BuildInlineSwatches(region, { {
                        getValue = function() return entry.r or 0.8, entry.g or 0.8, entry.b or 0.8, 1 end,
                        setValue = function(r, g, b) spec.setColour(entry, r, g, b) end,
                    } })
                    local requirement = spec.deleteRequirement
                    EllesmereUI.BuildInlineButton(region, spec.confirmDelete().accept, function()
                        if requirement() then return end
                        local copy = spec.confirmDelete()
                        S.Confirm({ title = copy.title, body = copy.body, accept = copy.accept,
                            onAccept = function()
                                if spec.remove(index) then Invalidate() end
                            end })
                    end, { width = 70, disabled = function() return requirement() ~= nil end,
                        disabledTooltip = requirement, rawTooltip = true })
                end
            end
            if #spec.list() < spec.max then
                Place({ type = "button", text = spec.addText, noCapture = true, onClick = function()
                    local accent = EllesmereUI.ELLESMERE_GREEN
                    local index = spec.add(accent.r, accent.g, accent.b)
                    if index then
                        focusResponse = index
                        Invalidate()
                    end
                end })
                Flush()
            end
            if not prebuild then
                for _, hint in ipairs(spec.hints()) do Note(hint) end
            end
        end




        local PRIDE_ON = { ["i am gay"] = true, ["im gay"] = true }
        local PRIDE_OFF = { ["i am not gay"] = true, ["im not gay"] = true }
        local function PrideRequest(text)
            if text:find("-", 1, true) then return nil end
            local phrase = slc.Locale.Fold(text):gsub("\226\128\153", ""):gsub("'", "")
                :gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
            if PRIDE_ON[phrase] then return true end
            if PRIDE_OFF[phrase] then return false end
            return nil
        end

        local function TryPride(text)
            local wanted = PrideRequest(text)
            if wanted == nil then return false end
            local current = slc.db and slc.db.pride and true or false
            if wanted == current then
                S.Confirm({ title = "Gay Mode", acknowledge = true,
                    body = wanted and S.Rainbow("You're already gay") or "You're already straight" })
                return true
            end
            S.Confirm({ title = "Gay Mode", accept = "Yes",
                body = wanted and S.Rainbow("Are you sure you're gay?") or "Are you sure you're not gay?",
                onAccept = function()
                    slc.db.pride = wanted
                    S.RefreshLogos()
                    slc.Log:I("UI", "pride mode " .. (wanted and "on" or "off"))
                end })
            return true
        end



        function custom.council(spec)
            if prebuild then return end
            local status = Note("", 0.85)
            OnRefresh(function()
                local good, warn = S.ColorStart(S.Flatten(S.color.good)), S.ColorStart(S.Flatten(S.color.warn))
                local state, leader = spec.authorship()
                status:SetText(spec.statusText(state, leader, good, warn))
            end)

            Note(spec.hint())
            local box = AddBox(Row(50), math.min(260, Width() - 20 - 8 - 90 - 20), spec.addText())

            local function AddTyped()
                CloseSuggestions(box)
                local name = box:GetText():trim()
                if name == "" then return end

                if TryPride(name) then
                    box:SetText("")
                    box:ClearFocus()
                    return
                end
                if spec.add(name) then box:SetText("") end
                box:ClearFocus()
                councilDirty = true
                Invalidate()
            end

            local function Typed(b, userInput)
                if not userInput then return end
                CloseSuggestions(b)
                local text = (b:GetText() or ""):trim()

                if select(2, text:gsub("[^\128-\191]", "")) < SUGGEST_MIN_CHARS then return end
                if PrideRequest(text) ~= nil then return end
                local items = {}
                for _, entry in ipairs(spec.suggest(text, SUGGEST_MAX)) do
                    local name = (tostring(entry.name):gsub("|", "||"))
                    local rank = (tostring(entry.rank or ""):gsub("|", "||"))
                    items[#items + 1] = { noLoc = true,
                        text = ClassText(entry.classFile, name, entry.online and S.color.text or S.color.textFaint)
                            .. "  " .. faint .. rank .. "|r",
                        onClick = function()
                            local fill = spec.suggestionText(entry)
                            b:SetText(fill)
                            b:SetCursorPosition(#fill)
                            b:SetFocus()
                        end }
                end
                if #items > 0 then
                    EllesmereUI.ShowContextMenu(b, items, { below = true, minWidth = b:GetWidth(),
                        pickOnDown = true, scaleToAnchor = true })
                end
            end
            addHandlers.add, addHandlers.typed = AddTyped, Typed




            local entries, here = CouncilEntries(spec), slc.GetCandidates()
            OnRefresh(function() entries, here = CouncilEntries(spec), slc.GetCandidates() end)
            for index = 1, #entries do
                local row = Row(34)
                local label = EllesmereUI.MakeFont(row, 13, nil, 1, 1, 1)
                label:SetPoint("LEFT", row, "LEFT", 20, 0)
                label:SetPoint("RIGHT", row, "RIGHT", -44, 0)
                label:SetJustifyH("LEFT")
                label:SetWordWrap(false)
                local entry, present
                OnRefresh(function()
                    entry = entries[index]
                    present = entry.kind ~= "rank" and (here[entry.fullName] and true or false)
                    local now = present
                    if entry.kind == "rank" then
                        local name = RankText(entry.name)
                        if not entry.known then
                            label:SetText(S.Colorize(S.Flatten(S.color.textFaint),
                                Format(T["%s  no such rank"], entry.name)))
                        elseif entry.present == 0 then
                            label:SetText(Format(T["%s%s  none here|r"], name, faint))
                        else
                            label:SetText(Format(T["%s%s  %d here|r"], name, faint, entry.present))
                        end
                    elseif entry.pending then

                        label:SetText(ClassText(entry.classFile, entry.fullName or entry.guid or "?",
                            S.Flatten(S.color.textFaint)))
                    else
                        local short = ClassText(entry.classFile, Ambiguate(entry.fullName or "?", "short"))
                        label:SetText(now and short
                            or Format(T["%s%s  not here|r"], short, faint))
                    end
                end)

                row:EnableMouse(true)
                row:SetScript("OnEnter", function(r)
                    if not entry then return end
                    local title, lines = spec.describe(entry, present)
                    local text = { S.Colorize(S.color.accent, title) }
                    for _, line in ipairs(lines) do
                        local body = line.value and (slc.Locale.SectionTitle(line.text) .. " " .. line.value)
                            or line.text
                        text[#text + 1] = line.tone and S.Colorize(S.color[line.tone], body) or body
                    end
                    EllesmereUI.ShowWidgetTooltip(r, table.concat(text, "\n"), { justify = "LEFT" })
                end)
                row:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                CloseButton(row, T["Remove"], function()
                    if not entry then return end
                    spec.remove(entry)
                    councilDirty = true
                    Invalidate()
                end)
            end
            if #entries == 0 then Note(spec.emptyText()) end
        end



        function custom.councilRanks(spec)
            if not prebuild then
                Note(S.Colorize(S.color.accent, spec.heading:upper()), 0.85)
                for _, hint in ipairs(spec.hints()) do Note(hint) end
            end
            local ranks = spec.ranks()
            for index = 1, math.min(#ranks, spec.maxRows) do
                local name = ranks[index].name
                if prebuild then
                    y = y - 36
                else
                    local row = Row(36)
                    local btn = CreateFrame("Button", nil, row)
                    btn:SetAllPoints(row)
                    local box, _, _, apply = EllesmereUI.BuildCheckboxControl(btn, row:GetFrameLevel() + 1)
                    PP.Point(box, "LEFT", btn, "LEFT", 20, 0)
                    local label = EllesmereUI.MakeFont(btn, 14, nil, 1, 1, 1)
                    label:SetPoint("LEFT", box, "RIGHT", 10, 0)
                    label:SetPoint("RIGHT", btn, "RIGHT", -20, 0)
                    label:SetJustifyH("LEFT")
                    label:SetWordWrap(false)
                    label:SetText(RankText(name))
                    local hovering = false
                    local function Paint() apply(spec.isEmpowered(name) and true or false, hovering) end
                    btn:SetScript("OnEnter", function() hovering = true Paint() end)
                    btn:SetScript("OnLeave", function() hovering = false Paint() end)
                    btn:SetScript("OnClick", function()
                        spec.setEmpowered(name, not spec.isEmpowered(name))
                        Paint()

                        councilDirty = true
                        Invalidate()
                    end)
                    OnRefresh(Paint)
                    Paint()
                end
            end
            local empty = spec.empty()
            if empty and not prebuild then Note(empty) end
        end


        function custom.councilPair(councilSpec, rankSpec)
            local GAP = 20
            local full = parent:GetWidth() - PAD * 2
            local half = math.floor((full - GAP) / 2)
            local top = y
            colX, colW = 0, half
            custom.council(councilSpec)
            local leftEnd = y
            y = top
            colX = half + GAP
            custom.councilRanks(rankSpec)
            local rightEnd = y
            colX, colW = 0, nil
            y = math.min(leftEnd, rightEnd)
            if not prebuild then
                local rule = parent:CreateTexture(nil, "ARTWORK")
                rule:SetColorTexture(1, 1, 1, 0.08)
                rule:SetWidth(1)
                rule:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD + half + GAP / 2, top - 4)
                rule:SetPoint("BOTTOMLEFT", parent, "TOPLEFT", PAD + half + GAP / 2, y + 4)
            end
        end



        function custom.alts(spec)
            local main = spec.main()
            local alts = spec.alts(main)
            local function Qualified(fullName)
                if not fullName then return S.Colorize(S.color.textMuted, spec.unknownText) end
                local character, realm, colour = spec.nameParts(fullName, function(classFile)
                    local r, g, b = S.ClassColor(classFile)
                    return r and { r = r, g = g, b = b } or nil
                end)
                return S.Colorize(colour and { colour.r, colour.g, colour.b } or S.color.text, character)
                    .. S.Colorize(S.color.text, realm)
            end
            if not prebuild then
                local mainLine = Note("", 0.85)
                OnRefresh(function()
                    mainLine:SetText(Format(T["Main: %s"], Qualified(spec.main())))
                end)
            end

            local function Box(text, submit)
                local kept = ""
                return { type = "input", text = text, inputStyle = "popup", inputWidth = 200,
                    placeholder = spec.hint(), noCapture = true,
                    getValue = function() return kept end,
                    setValue = function(value)
                        local done = submit(value)
                        kept = done == false and value or ""
                        if done then Invalidate() end
                    end }
            end
            local showAlts = spec.showAlts
            local showCfg = { type = "toggle", text = showAlts.text, noCapture = true,
                getValue = showAlts.getValue,
                setValue = function(value) showAlts.setValue(value) Invalidate() end }

            if #alts == 0 then Place(Box(spec.designateText, spec.designateMain)) end
            Place(Box(spec.addText, spec.addAlt))
            Place(showCfg)
            Flush()
            if prebuild then return end

            OnRefresh(function() alts = spec.alts(spec.main()) end)
            for index = 1, #alts do
                local row = Row(34)

                local label = EllesmereUI.MakeFont(row, 13, nil, 1, 1, 1)
                label:SetPoint("LEFT", row, "LEFT", 20, 0)

                OnRefresh(function() label:SetText(Qualified(alts[index])) end)
                local copy = spec.confirmRemove()
                CloseButton(row, copy.accept, function()
                    local alt = alts[index]
                    S.Confirm({ title = copy.title, body = copy.body, accept = copy.accept,
                        onAccept = function()
                            spec.removeAlt(alt)
                            Invalidate()
                        end })
                end)
            end
        end




        local sections = PageSections(Schema, pageName)
        for _, section in ipairs(sections) do
            _, h = W:SectionHeader(parent, section.title:upper(), y);  y = y - h
            for _, row in ipairs(section.rows) do
                if row.hidden and row.hidden() then

                elseif row.id == "boeReason" then
                    local cfg = BoECfg(row)
                    Place(cfg, function(region)
                        if region._control then
                            region._control:SetMaxLetters(row.maxLetters)
                            LeftAlign(region._control)
                        end
                        EllesmereUI.BuildInlineSwatches(region, { {
                            getValue = function()
                                local r, g, b = row.colour()
                                return r, g, b, 1
                            end,
                            setValue = function(r, g, b) row.setColour(r, g, b) Invalidate() end,
                        } })
                        OnRefresh(function() cfg.tooltip = BoETooltip(row) end)
                    end)
                elseif row.id == "council" then
                    Flush()
                    custom.councilPair(row, Schema.Row("councilRanks"))
                elseif row.id == "councilRanks" then

                elseif row.custom then
                    Flush()
                    custom[row.id](row)
                elseif row.suggest then
                    local cfg = Cfg(row)
                    cfg.inputStyle = "popup"


                    local box, commit = nil, cfg.setValue
                    cfg.setValue = function(value)
                        if box and EllesmereUI.ContextMenuOwner() == box and IsMouseButtonDown("LeftButton") then
                            return
                        end
                        commit(value)
                    end
                    Place(cfg, function(region)
                        box = region._control
                        if box then AttachSuggest(box, row, cfg.setValue) end
                    end, row.id, row.dependsOn)
                else
                    local cfg = Cfg(row)
                    Place(cfg, Decorator(row, cfg), row.id, row.dependsOn)
                end
            end
            Flush()
        end

        if prebuild then return math.abs(y) end




        local function Shape()
            local parts = {}
            for _, section in ipairs(sections) do
                for _, row in ipairs(section.rows) do
                    parts[#parts + 1] = (row.hidden and row.hidden()) and "h" or "v"
                end
            end
            local ranks = Schema.Row("councilRanks")
            local alts = Schema.Row("alts")
            parts[#parts + 1] = #Schema.Row("responses").list()
            parts[#parts + 1] = #CouncilEntries(Schema.Row("council"))
            parts[#parts + 1] = math.min(#ranks.ranks(), ranks.maxRows)
            parts[#parts + 1] = ranks.empty() or ""
            parts[#parts + 1] = #alts.alts(alts.main())

            if withStatus then
                parts[#parts + 1] = StatusHeight(#Schema.Row("councilInForce").entries(tostring, tostring))
            end
            return table.concat(parts, ",")
        end
        local built = Shape()
        local function RefreshAll()
            if Shape() ~= built then
                RequestRebuild()
                return
            end
            for i = 1, #refreshes do refreshes[i]() end
        end
        EllesmereUI.RegisterWidgetRefresh(RefreshAll)
        RefreshAll()

        Subscribe(slc, Schema)

        parent:SetScript("OnShow", function() Listen(true) end)
        parent:SetScript("OnHide", function() Listen(false) end)
        if parent:IsVisible() then Listen(true) end
        ShowBanner()

        return math.abs(y)
    end




    EllesmereUI:RegisterModule(ADDON_NAME, {
        title       = "Simple Loot Council",
        description = "Loot council voting for your raid, synced over addon messages.",
        pages       = PAGES,
        buildPage   = function(pageName, parent, yOffset)
            if PAGE_SECTIONS[pageName] then return BuildSettingsPage(pageName, parent, yOffset) end
        end,

        onPageCacheRestore = function()
            ShowBanner()
            councilDirty = true
            EllesmereUI:RefreshPage()
        end,

        onModuleLeave = HideBanner,
    })
end)

if IsLoggedIn() then initFrame:GetScript("OnEvent")(initFrame) end
