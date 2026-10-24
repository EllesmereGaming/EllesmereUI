if EUI_CLIENT_BLOCKED then return end





local ADDON_NAME = "EllesmereUISimpleLootCouncil"
local ns = EllesmereUI._ModuleNS[ADDON_NAME]
if not ns then return end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")




    local CreateFrame = EllesmereUI._Pool.CreateFrame


    if ns.slcInert then
        local PAGE_INERT = "General"
        EllesmereUI:RegisterModule(ADDON_NAME, {
            title       = "Simple Loot Council",
            description = "Loot council voting for your raid, synced over addon messages.",
            pages       = { PAGE_INERT },
            buildPage   = function(pageName, parent, yOffset)
                if pageName ~= PAGE_INERT then return end
                local W, PP, PAD = EllesmereUI.Widgets, EllesmereUI.PanelPP, EllesmereUI.CONTENT_PAD
                local y, _, h = yOffset
                EllesmereUI:ClearContentHeader()
                if not EllesmereUI.IsSearchPrebuild() then parent._showRowDivider = true end
                _, h = W:SectionHeader(parent, EllesmereUI.L("OLDER STANDALONE ADDON"), y);  y = y - h
                local row = CreateFrame("Frame", nil, parent)
                row._skipRowDivider = true
                local label = EllesmereUI.MakeFont(row, 12, nil, 1, 1, 1)
                label:SetAlpha(0.85)
                label:SetJustifyH("LEFT")
                label:SetWordWrap(true)
                label:SetWidth(parent:GetWidth() - PAD * 2 - 40)
                label:SetPoint("TOPLEFT", row, "TOPLEFT", 20, -10)
                label:SetText(EllesmereUI.L("An older SimpleLootCouncil addon is enabled, so the Simple Loot Council module is off until that addon is disabled or updated."))
                PP.Size(row, parent:GetWidth() - PAD * 2, 54)
                PP.Point(row, "TOPLEFT", parent, "TOPLEFT", PAD, y)
                y = y - 54
                _, h = W:DualRow(parent, y, { type = "button", text = EllesmereUI.L("Disable and Reload"),
                    noCapture = true,
                    onClick = function() EllesmereUI.RequestReload(nil, nil, ns.DisableStandalone) end },
                    EllesmereUI.BlankRowCfg());  y = y - h
                return math.abs(y)
            end,
        })
        return
    end



    local PAGE_LOOT, PAGE_COUNCIL, PAGE_DATA = "Loot and Sessions", "Loot Council", "Data and Diagnostics"
    local PAGES = { PAGE_LOOT, PAGE_COUNCIL, PAGE_DATA }
    local PAGE_SECTIONS = {
        [PAGE_LOOT] = { "lootHandling", "master", "session", "alts" },
        [PAGE_COUNCIL] = { "council", "voting", "responses" },
        [PAGE_DATA] = { "history", "diagnostics" },
    }
    local SUGGEST_MAX, SUGGEST_MIN_CHARS = 8, 2


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
            if PageShown() then EllesmereUI:RefreshPage(true) end
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
            min = row.min, max = row.max, step = row.step, valueSnap = row.valueSnap,

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


    local CHECKS_W = 230
    local function ChecksReason(row)
        if row.locked then
            local _, reason = row.locked()
            if reason then return reason end
        end
        if row.disabled then return row.disabled() end
        return nil
    end
    local function ChecksLock(target, row)
        if not (row.locked or row.disabled) then return target end
        target.disabled = function() return ChecksReason(row) ~= nil end
        target.disabledTooltip = function() return ChecksReason(row) end
        target.rawTooltip = true
        return target
    end
    local function ChecksCfg(row)
        return ChecksLock({ type = "dropdown", text = row.text, tooltip = row.tooltip, noCapture = true,
            values = { __placeholder = "..." }, order = { "__placeholder" },
            getValue = function() return "__placeholder" end, setValue = function() end }, row)
    end





    local function MultiselectTips()
        return {
            soundNotifications = {
                responseFrame = EllesmereUI.L("Add a sound notification when the loot response frame opens"),
                responseTab = EllesmereUI.L("Add a sound notification when the loot response tab label pulses"),
            },
        }
    end
    local function ChecksItems(row)
        if row.type ~= "multiselect" then return row.items end
        local tips = MultiselectTips()[row.id]
        local items = {}
        for i, item in ipairs(row.items) do
            local tip = item.tooltip or (tips and tips[item.key])
            items[i] = { key = item.key, label = item.text, tooltip = tip }
        end
        return items
    end


    local CHECKS_PAD = 80
    local measure
    local function ChecksWidth(items)
        if not measure then
            measure = UIParent:CreateFontString(nil, "OVERLAY")
            measure:SetFont(EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 13, "")
            measure:Hide()
        end
        local widest = 0
        for _, item in ipairs(items) do
            measure:SetText(item.label or "")
            widest = math.max(widest, math.ceil(measure:GetStringWidth() or 0))
        end
        return widest + CHECKS_PAD
    end
    local function ChecksDecorator(row)
        local items = ChecksItems(row)        local function Get(key)
            if row.lockedValue and row.locked and select(2, row.locked()) then
                return row.lockedValue(key)
            end
            return row.getValue(key)
        end
        return function(region)
            local width = region._control and region._control:GetWidth() or 0
            if width < 50 then width = CHECKS_W end
            width = math.max(width, ChecksWidth(items))
            if region._control then region._control:Hide() end
            local dd, refresh = EllesmereUI.BuildVisOptsCBDropdown(region, width,
                region:GetFrameLevel() + 2, items, Get,
                function(key, value)
                    if not ChecksReason(row) then row.setValue(key, value) end
                    Invalidate()
                end, nil, nil, nil, nil, nil, ChecksLock({ emptyLabel = "None" }, row))
            EllesmereUI.PanelPP.Point(dd, "RIGHT", region, "RIGHT", -20, 0)
            region._control = dd
            region._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(refresh)
        end
    end








    local function StyledTag(parent, width, onClick, make)
        local btn = (make or CreateFrame)("Button", nil, parent)
        EllesmereUI.PanelPP.Size(btn, width, 24)
        btn:SetFrameLevel(parent:GetFrameLevel() + 5)
        local _, border, label = EllesmereUI.MakeStyledButton(btn, "", 11, EllesmereUI.WB_COLOURS)


        local function Edge()
            local c = btn.tone
            if c then border:SetColor(c[1], c[2], c[3], 1) end
        end
        function btn:SetTone(c)
            btn.tone = c
            Edge()
        end
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btn:SetScript("OnClick", function(_, button)
            EllesmereUI.HideWidgetTooltip()
            onClick(button)
        end)
        local hoverOn, hoverOff = btn:GetScript("OnEnter"), btn:GetScript("OnLeave")
        btn:SetScript("OnEnter", function(b)
            hoverOn(b)
            Edge()
            if b.tip then EllesmereUI.ShowWidgetTooltip(b, b.tip) end
        end)
        btn:SetScript("OnLeave", function(b)
            hoverOff(b)
            Edge()
            EllesmereUI.HideWidgetTooltip()
        end)
        btn.Label = label
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
            EllesmereUI.ApplyModuleFont(addBox, EllesmereUI.EXPRESSWAY, 11, nil, "")
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


    local function FindTitle(frame, depth, translated)
        for _, region in ipairs({ frame:GetRegions() }) do
            local text = region.GetText and region:GetText()
            if (text == MODULE_TITLE or text == translated)
                and (select(2, region:GetFont()) or 0) >= 30 then
                return region
            end
        end
        if depth == 0 then return nil end
        for _, child in ipairs({ frame:GetChildren() }) do
            local found = FindTitle(child, depth - 1, translated)
            if found then return found end
        end
    end

    local bannerTitle, bannerTexture, bannerVersion, bannerLive



    local TAG_H, TAG_PAD = 24, 9
    local function FitTag(tag)
        local width = tag.Label.GetStringWidth and tag.Label:GetStringWidth()
        if type(width) ~= "number" or (issecretvalue and issecretvalue(width)) then width = 0 end
        EllesmereUI.PanelPP.Size(tag, math.ceil(width) + TAG_PAD * 2, TAG_H)
    end



    local function RefreshHeaderTags()
        local slc = SLC()
        if not (slc and bannerLive) then return end
        local tags, S = slc.UI.OptionsSchema.Row("statusTags"), slc.Style
        local live = bannerVersion:IsShown() and tags.live()
        bannerLive:SetShown(live)
        if live then
            local _, liveTone, liveLines = tags.liveTooltip()
            bannerLive.Label:SetText(S.Colorize(S.color[liveTone], tags.liveText))
            bannerLive.tip = table.concat(liveLines, "\n")
            bannerLive:SetTone(S.color[liveTone])
            FitTag(bannerLive)
        end
    end

    local function ApplyBanner(slc)
        local pride = slc and slc.Style.PrideActive() or false
        local logo = pride and LOGO_PRIDE or LOGO
        bannerTexture:SetTexture(logo.path)
        bannerTexture:SetTexCoord(0, logo.u, 0, LOGO_V)
        EllesmereUI.PanelPP.Size(bannerTexture, logo.w, LOGO_H)
    end



    local function OnOurPage()
        return not EllesmereUI.IsSearchPrebuild() and EllesmereUI:GetActiveModule() == ADDON_NAME
    end

    local function ShowBanner()
        if not OnOurPage() then return end
        local slc = SLC()
        local main = EllesmereUI._mainFrame
        if not (slc and main) then return end
        if not bannerTitle then
            bannerTitle = FindTitle(main, 6, EllesmereUI.L(MODULE_TITLE))
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

        if not bannerLive then
            bannerLive = StyledTag(bannerTitle:GetParent(), 60, function(button)
                local tags = SLC() and SLC().UI.OptionsSchema.Row("statusTags")
                if tags and tags.clickLive(button) then Invalidate() end
            end, _G.CreateFrame)
            EllesmereUI.PanelPP.Point(bannerLive, "LEFT", bannerVersion, "RIGHT", 12, 0)
        end
        ApplyBanner(slc)
        bannerTexture:Show()
        bannerVersion:Show()
        bannerTitle:SetAlpha(0)
        RefreshHeaderTags()
    end

    local function HideBanner()
        if bannerTexture then bannerTexture:Hide() end
        if bannerVersion then bannerVersion:Hide() end
        if bannerLive then bannerLive:Hide() end
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






    local ICONS = "Interface\\AddOns\\EllesmereUI\\media\\icons\\"
    local ICON_OPEN, ICON_HISTORY = ICONS .. "play.png", ICONS .. "undo.png"



    local RANK_ROW_H, RANK_VISIBLE = 36, 7

    local COUNCIL_CELL_W, COUNCIL_CELL_H, COUNCIL_MAX_LINES, COUNCIL_BOTTOM = 150, 22, 3, 18
    local ML_LABEL_Y, ML_NAME_Y, DIVIDER_Y, LIST_Y = 18, 36, 80, 106

    local function CouncilColumns(width)
        return math.max(2, math.min(6, math.floor((width - 80) / COUNCIL_CELL_W)))
    end
    local function CouncilLines(entries, cols)
        return math.max(1, math.min(COUNCIL_MAX_LINES, math.ceil(math.max(entries, 1) / cols)))
    end


    local function CouncilMembers(inForce, name, rank)
        local entries, count = inForce.entries(name, rank)
        local members = {}
        for _, entry in ipairs(entries) do
            if not entry.master then members[#members + 1] = entry end
        end
        return members, tonumber(count) or 0
    end





    local lockCovers, searching = {}, false
    local function PaintCover(entry)
        entry.cover:SetShown(not searching and entry.locked() and true or false)
    end
    hooksecurefunc(EllesmereUI, "ApplyInlineSearch", function(_, query)
        local now = query ~= nil and query ~= ""
        if now == searching then return end
        searching = now
        for _, covers in pairs(lockCovers) do
            for _, entry in ipairs(covers) do PaintCover(entry) end
        end
    end)


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


        local covers = {}
        if not prebuild then lockCovers[pageName] = covers end
        local function LockCover(top, bottom, text, locked, onLock)
            local cover = CreateFrame("Frame", nil, parent)
            cover._searchIgnore = true
            PP.Size(cover, parent:GetWidth() - PAD * 2, top - bottom)
            PP.Point(cover, "TOPLEFT", parent, "TOPLEFT", PAD, top)
            cover:SetFrameLevel(parent:GetFrameLevel() + 30)
            cover:EnableMouse(true)
            cover:EnableMouseWheel(true)
            cover:SetScript("OnMouseWheel", function(_, delta)
                if EllesmereUI._ShiftWheelScale(delta) then return end
                local page = EllesmereUI._scrollFrame
                local fn = page and page:GetScript("OnMouseWheel")
                if fn then fn(page, delta) end
            end)
            local shade = cover:CreateTexture(nil, "BACKGROUND")
            shade:SetAllPoints()
            shade:SetColorTexture(0.05, 0.05, 0.05, 0.8)
            local lockLabel = EllesmereUI.MakeFont(cover, 14, nil, 1, 1, 1)
            lockLabel:SetPoint("CENTER", cover, "CENTER", 0, 0)
            lockLabel:SetText(text)
            local entry = { cover = cover, locked = locked }
            covers[#covers + 1] = entry
            OnRefresh(function()
                if onLock and locked() then onLock() end
                PaintCover(entry)
            end)
        end


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



        local function Decorator(row)
            if not row.danger then return nil end
            return function(region)
                if region._label then
                    region._label:SetTextColor(S.Unpack(S.color.bad))
                end
            end
        end






        local lootMaster = Schema.Row("lootMaster")
        local inForce, main = Schema.Row("councilInForce"), Schema.Row("mainButtons")
        local actions = Schema.Actions()

        local withStatus = pageName == PAGE_LOOT
        local withTools = pageName == PAGE_DATA
        if not prebuild then OnRefresh(RefreshHeaderTags) end



        local function Open(action)
            return function()
                EllesmereUI:Hide()
                action.onClick()
            end
        end

        if withTools then
            _, h = W:SectionHeader(parent, T["Tools"]:upper(), y);  y = y - h
            for i = 1, #actions, 2 do
                local a, b = actions[i], actions[i + 1]
                _, h = W:WideDualButton(parent, a.text, b and b.text, y, Open(a), b and Open(b));  y = y - h
            end
        end

        local councilCols
        if not withStatus then

        elseif prebuild then
            _, h = W:WideDualButton(parent, main.openText, main.historyText, y);  y = y - h
        else
            _, h = W:Spacer(parent, y, 10);  y = y - h
            local cards
            y, cards = EllesmereUI.BuildActionCardRow(parent, y, {
                { icon = ICON_OPEN, title = main.openText, desc = main.openDesc(), pulse = true,
                  onClick = function()
                      if main.openLoot() then EllesmereUI:Hide() end
                  end },
                { icon = ICON_HISTORY, title = main.historyText, desc = main.historyDesc,
                  onClick = function()
                      EllesmereUI:Hide()
                      main.openHistory()
                  end },
            })
            OnRefresh(function()
                cards[1]:SetCardContent(ICON_OPEN, main.openText, main.openDesc())

                if cards[1].SetPulse then cards[1]:SetPulse(main.live()) end
            end)
            _, h = W:Spacer(parent, y, 14);  y = y - h


            local full = parent:GetWidth() - PAD * 2
            councilCols = CouncilColumns(full)
            local lines = CouncilLines(#CouncilMembers(inForce, PlayerText, RankText), councilCols)
            local capacity = lines * councilCols
            local height = LIST_Y + lines * COUNCIL_CELL_H + COUNCIL_BOTTOM

            local block = CreateFrame("Frame", nil, parent)
            PP.Size(block, full, height)
            PP.Point(block, "TOPLEFT", parent, "TOPLEFT", PAD, y)
            block._skipRowDivider = true
            EllesmereUI.RowBg(block, parent)
            y = y - height




            local statusTags = Schema.Row("statusTags")
            local activeTag = StyledTag(block, 90, function(button)
                if button == "LeftButton" and statusTags.clickActive() then Invalidate() end
            end)
            activeTag:Hide()
            PP.Point(activeTag, "TOPLEFT", block, "TOPLEFT", 16, -12)
            OnRefresh(function()
                local title, tone, lines = statusTags.activeTooltip()

                if tone == "accent" and not slc.PlayerIsMasterLooter() then tone = "good" end
                activeTag.Label:SetText(S.Colorize(S.color[tone], lootMaster.activeText))
                activeTag.tip = table.concat(lines, "\n")
                activeTag:SetTone(S.color[tone])
                FitTag(activeTag)

                activeTag:SetShown(title == statusTags.activeText)
            end)


            local mlLabel = EllesmereUI.MakeFont(block, 11, nil, 1, 1, 1)
            mlLabel:SetAlpha(0.45)
            mlLabel:SetPoint("TOP", block, "TOP", 0, -ML_LABEL_Y)
            mlLabel:SetText(lootMaster.heading)
            local mlName = EllesmereUI.MakeFont(block, 22, nil, 1, 1, 1)
            mlName:SetPoint("TOP", block, "TOP", 0, -ML_NAME_Y)


            local headHolder = CreateFrame("Frame", nil, block)
            PP.Size(headHolder, 160, 14)
            PP.Point(headHolder, "TOP", block, "TOP", 0, -DIVIDER_Y)
            local heading = EllesmereUI.MakeFont(headHolder, 11, nil, 1, 1, 1)
            heading:SetAlpha(0.45)
            heading:SetPoint("LEFT", headHolder, "LEFT", 0, 0)
            heading:SetText(inForce.heading)
            local voters = EllesmereUI.MakeFont(headHolder, 12, nil, 1, 1, 1)
            voters:SetPoint("RIGHT", headHolder, "RIGHT", 0, 0)
            for _, side in ipairs({ "LEFT", "RIGHT" }) do
                local rule = block:CreateTexture(nil, "ARTWORK")
                rule:SetColorTexture(1, 1, 1, 0.08)
                rule:SetHeight(1)
                if side == "LEFT" then
                    rule:SetPoint("TOPLEFT", block, "TOPLEFT", 40, -(DIVIDER_Y + 7))
                    rule:SetPoint("TOPRIGHT", headHolder, "TOPLEFT", -14, -7)
                else
                    rule:SetPoint("TOPLEFT", headHolder, "TOPRIGHT", 14, -7)
                    rule:SetPoint("TOPRIGHT", block, "TOPRIGHT", -40, -(DIVIDER_Y + 7))
                end
            end

            local entryRows = {}
            for i = 1, capacity do
                local row = CreateFrame("Frame", nil, block)
                PP.Size(row, COUNCIL_CELL_W - 10, COUNCIL_CELL_H)
                row.label = EllesmereUI.MakeFont(row, 13, nil, 1, 1, 1)
                row.label:SetJustifyH("CENTER")
                row.label:SetWordWrap(false)
                row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
                row.label:SetPoint("RIGHT", row, "RIGHT", 0, 0)
                row:EnableMouse(true)
                row:SetScript("OnEnter", function(self)
                    if self.tip then EllesmereUI.ShowWidgetTooltip(self, self.tip) end
                end)
                row:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                entryRows[i] = row
            end
            local emptyLabel = EllesmereUI.MakeFont(block, 13, nil, 1, 1, 1)
            emptyLabel:SetPoint("TOP", block, "TOP", 0, -(LIST_Y + 4))

            OnRefresh(function()
                local master = lootMaster.fullName()
                mlName:SetText(master and PlayerText(master)
                    or S.Colorize(S.color.textFaint, lootMaster.unknown))
            end)
            OnRefresh(function()
                local entries, count = CouncilMembers(inForce, PlayerText, RankText)
                voters:SetText(S.Colorize(count == 0 and S.color.bad or S.color.accentPale, tostring(count)))
                local headW = math.ceil(heading:GetStringWidth() or 0)
                local countW = math.ceil(voters:GetStringWidth() or 0)
                PP.Size(headHolder, headW + 8 + countW, 14)
                emptyLabel:SetShown(#entries == 0)
                if #entries == 0 then
                    emptyLabel:SetText(count == 0 and S.Colorize(S.color.bad, inForce.emptyText)
                        or S.Colorize(S.color.textFaint, inForce.othersEmpty))
                end


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
                local shown = math.min(#entries, capacity)
                for i, row in ipairs(entryRows) do
                    local entry = i <= shown and entries[i]
                    row:SetShown(entry and true or false)
                    if entry then
                        local line = math.floor((i - 1) / councilCols)
                        local inLine = math.min(councilCols, shown - line * councilCols)
                        local left = math.floor((full - inLine * COUNCIL_CELL_W) / 2)
                        row:ClearAllPoints()
                        PP.Point(row, "TOPLEFT", block, "TOPLEFT",
                            left + ((i - 1) % councilCols) * COUNCIL_CELL_W + 5,
                            -(LIST_Y + line * COUNCIL_CELL_H))
                        row.label:SetText(entry.count and Format(T["%s (%s)"], entry.text, entry.count)
                            or entry.text)
                        local tip = entry.tooltip and #entry.tooltip > 0
                            and ((entry.overflow and "" or entry.text .. "\n") .. table.concat(entry.tooltip, "\n"))
                        row.tip = tip or nil
                    end
                end
            end)
        end




        local custom = {}



        function custom.responses(spec)
            for index, built in ipairs(spec.list()) do


                local entry = built
                OnRefresh(function() entry = spec.list()[index] or entry end)
                Place({ type = "input", text = Format(spec.nameLabel, index),
                    inputStyle = "popup", inputWidth = 180, noCapture = true,
                    getValue = function() return entry.text or "" end,

                    setValue = function(text) spec.setName(index, text) Invalidate() end },
                    function(region)

                        if region._label then region._label:SetText("") end
                        local box = region._control
                        if box then
                            box:ClearAllPoints()
                            PP.Point(box, "LEFT", region, "LEFT", 20, 0)

                            box:SetMaxLetters(spec.maxLetters)
                            if focusResponse == index then
                                focusResponse = nil
                                box:SetFocus()
                                box:HighlightText()
                            end
                        end

                        EllesmereUI.BuildInlineSwatches(region, { {
                            getValue = function() return entry.r or 0.8, entry.g or 0.8, entry.b or 0.8, 1 end,
                            setValue = function(r, g, b) spec.setColour(entry, r, g, b) end,
                        } })

                        local swatch = region._lastInline
                        if box and swatch and swatch ~= box then
                            swatch:ClearAllPoints()
                            PP.Point(swatch, "LEFT", box, "RIGHT", 8, 0)
                        end
                        local requirement = spec.deleteRequirement
                        local delete = EllesmereUI.BuildInlineButton(region, spec.confirmDelete().accept, function()
                            if requirement() then return end
                            local copy = spec.confirmDelete()
                            S.Confirm({ title = copy.title, body = copy.body, accept = copy.accept,
                                onAccept = function()
                                    if spec.remove(index) then Invalidate() end
                                end })
                        end, { width = 70, disabled = function() return requirement() ~= nil end,
                            disabledTooltip = requirement, rawTooltip = true })
                        if delete and swatch and swatch ~= box then
                            delete:ClearAllPoints()
                            PP.Point(delete, "LEFT", swatch, "RIGHT", 8, 0)
                        end


                        if box and swatch and delete and swatch ~= box then
                            local total = box:GetWidth() + 8 + swatch:GetWidth() + 8 + delete:GetWidth()
                            local room = region:GetWidth()
                            if type(total) == "number" and type(room) == "number" and room > total then
                                box:ClearAllPoints()
                                PP.Point(box, "LEFT", region, "LEFT", math.floor((room - total) / 2), 0)
                            end
                        end
                    end)
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
            end
            Flush()
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

        local function Rainbow(text)
            if text:find("[\128-\255]") then return text end
            return S.Rainbow(text)
        end

        local function TryPride(text)
            local wanted = PrideRequest(text)
            if wanted == nil then return false end
            local current = slc.db and slc.db.pride and true or false
            if wanted == current then
                S.Confirm({ title = EllesmereUI.L("Gay Mode"), acknowledge = true,
                    body = wanted and Rainbow(EllesmereUI.L("You're already gay"))
                        or EllesmereUI.L("You're already straight") })
                return true
            end
            S.Confirm({ title = EllesmereUI.L("Gay Mode"), accept = EllesmereUI.L("Yes"),
                body = wanted and Rainbow(EllesmereUI.L("Are you sure you're gay?"))
                    or EllesmereUI.L("Are you sure you're not gay?"),
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
                label:SetPoint("RIGHT", row, "RIGHT", -98, 0)
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
                EllesmereUI.BuildInlineButton(row, T["Remove"], function()
                    if not entry then return end
                    spec.remove(entry)
                    councilDirty = true
                    Invalidate()
                end, { width = 70 })
            end
            if #entries == 0 then Note(spec.emptyText()) end
        end



        function custom.councilRanks(spec)
            if not prebuild then
                Note(S.Colorize(S.color.accent, spec.heading:upper()), 0.85)
                for _, hint in ipairs(spec.hints()) do Note(hint) end
            end
            local ranks = spec.ranks()
            local count = math.min(#ranks, spec.maxRows)
            local viewH = math.min(count, RANK_VISIBLE) * RANK_ROW_H
            if prebuild then
                y = y - viewH
            elseif count > 0 then
                local sf = CreateFrame("ScrollFrame", nil, parent)
                PP.Size(sf, Width(), viewH)
                PP.Point(sf, "TOPLEFT", parent, "TOPLEFT", PAD + colX, y)
                y = y - viewH
                local list = CreateFrame("Frame", nil, sf)
                PP.Size(list, Width(), count * RANK_ROW_H)
                sf:SetScrollChild(list)
                if count > RANK_VISIBLE then
                    local updateThumb = EllesmereUI.AttachSmoothScrollbar(sf, {
                        step = RANK_ROW_H, child = list, panelWheel = true, passWheel = true })
                    OnRefresh(updateThumb)
                end
                for index = 1, count do
                    local name = ranks[index].name
                    local row = CreateFrame("Frame", nil, list)
                    PP.Size(row, Width(), RANK_ROW_H)
                    PP.Point(row, "TOPLEFT", list, "TOPLEFT", 0, -(index - 1) * RANK_ROW_H)
                    EllesmereUI.RowBg(row, list)
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

                LockCover(top, y, councilSpec.lockedText, councilSpec.locked, function()
                    if addBox and addBox:HasFocus() then addBox:ClearFocus() end
                end)
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
                EllesmereUI.BuildInlineButton(row, copy.accept, function()
                    local alt = alts[index]
                    S.Confirm({ title = copy.title, body = copy.body, accept = copy.accept,
                        onAccept = function()
                            spec.removeAlt(alt)
                            Invalidate()
                        end })
                end, { width = 70 })
            end
        end




        local sections = PageSections(Schema, pageName)
        for _, section in ipairs(sections) do
            _, h = W:SectionHeader(parent, section.title:upper(), y);  y = y - h
            local rowsTop = y
            for _, row in ipairs(section.rows) do
                if row.hidden and row.hidden() then

                elseif row.type == "checks" or row.type == "multiselect" then
                    Place(ChecksCfg(row), ChecksDecorator(row), row.id, row.dependsOn)
                elseif row.id == "council" then
                    Flush()
                    custom.councilPair(row, Schema.Row("councilRanks"))
                elseif row.id == "councilRanks" then

                elseif row.custom then
                    Flush()
                    custom[row.id](row)
                else
                    Place(Cfg(row), Decorator(row), row.id, row.dependsOn)
                end
            end
            Flush()
            if section.locked and not prebuild and y < rowsTop then
                LockCover(rowsTop, y, section.lockedText, section.locked)
            end
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

            if councilCols then
                parts[#parts + 1] = CouncilLines(
                    #CouncilMembers(Schema.Row("councilInForce"), tostring, tostring), councilCols)
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
        if not prebuild then ShowBanner() end

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
