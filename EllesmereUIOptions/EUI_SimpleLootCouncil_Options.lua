if EUI_CLIENT_BLOCKED then return end





local ADDON_NAME = "EllesmereUISimpleLootCouncil"
local ns = EllesmereUI._ModuleNS[ADDON_NAME]
if not ns then return end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    if not EllesmereUI or not EllesmereUI.RegisterModule then return end

    local PAGE_SETTINGS = "Settings"
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



    local subscribed
    local gameEvents = {}
    local watcher = CreateFrame("Frame")
    watcher:SetScript("OnEvent", Invalidate)
    local function Subscribe(slc, Schema)
        if subscribed then return end
        subscribed = true
        for _, event in ipairs(Schema.Events()) do
            if event:find("^%u[%u_]*$") then
                gameEvents[#gameEvents + 1] = event
            elseif event == "SessionChanged" then
                slc.Callbacks:Register(event, function(_, kind)
                    if kind == nil or Schema.SESSION_KINDS[kind] then Invalidate() end
                end)
            else
                slc.Callbacks:Register(event, Invalidate)
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







    local function StyledTag(parent, width, onClick)
        local btn = CreateFrame("Button", nil, parent)
        EllesmereUI.PanelPP.Size(btn, width, 24)
        btn:SetFrameLevel(parent:GetFrameLevel() + 5)
        local _, _, label = EllesmereUI.MakeStyledButton(btn, "", 11, EllesmereUI.WB_COLOURS)
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btn:SetScript("OnClick", function(_, button)
            EllesmereUI.HideWidgetTooltip()
            onClick(button)
        end)
        btn:HookScript("OnEnter", function(b)
            if b.tip then EllesmereUI.ShowWidgetTooltip(b, b.tip) end
        end)
        btn:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        btn.Label = label
        return btn
    end


    local function TagButton(region, width, onClick)
        local btn = StyledTag(region, width, onClick)
        local anchor = region._lastInline or region._control
        if anchor then
            EllesmereUI.PanelPP.Point(btn, "RIGHT", anchor, "LEFT", -8, 0)
        else
            EllesmereUI.PanelPP.Point(btn, "RIGHT", region, "RIGHT", -20, 0)
        end
        region._lastInline = btn
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




    local function InputBox(parent, width)
        local box = CreateFrame("EditBox", nil, parent)
        box:SetSize(width, 28)
        box:SetAutoFocus(false)
        box:SetFont(EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 11, "")
        box:SetTextColor(1, 1, 1, 0.9)
        box:SetJustifyH("LEFT")
        box:SetTextInsets(10, 10, 0, 0)
        local bg = box:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.5)
        EllesmereUI.MakeBorder(box, 1, 1, 1, 0.2)
        box:SetScript("OnEscapePressed", function(b) b:ClearFocus() end)
        return box
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

    local bannerTitle, bannerTexture, bannerVersion, bannerActive


    local function RefreshActiveTag()
        local slc = SLC()
        if not (slc and bannerActive) then return end
        local title, tone, lines = slc.UI.OptionsSchema.Row("statusTags").activeTooltip()
        bannerActive.Label:SetText(slc.Style.Colorize(slc.Style.color[tone], title))
        bannerActive.tip = table.concat(lines, "\n")
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
            end)
            EllesmereUI.PanelPP.Point(bannerActive, "LEFT", bannerVersion, "RIGHT", 12, 0)
        end
        RefreshActiveTag()
        ApplyBanner(slc)
        bannerTexture:Show()
        bannerVersion:Show()
        bannerActive:Show()
        bannerTitle:SetAlpha(0)
    end

    local function HideBanner()
        if bannerTexture then bannerTexture:Hide() end
        if bannerVersion then bannerVersion:Hide() end
        if bannerActive then bannerActive:Hide() end
        if bannerTitle then bannerTitle:SetAlpha(1) end
    end





    local function BuildSettingsPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local PP = EllesmereUI.PanelPP
        local PAD = EllesmereUI.CONTENT_PAD

        local prebuild = EllesmereUI.IsSearchPrebuild and EllesmereUI.IsSearchPrebuild()
        local y = yOffset
        local _, h

        EllesmereUI:ClearContentHeader()


        if ns.slcInert then
            _, h = W:SectionHeader(parent, "STANDALONE COPY RUNNING", y);  y = y - h
            _, h = W:WideButton(parent, "Switch To The EllesmereUI Module", y, function()
                if ns.AskSwitch then ns.AskSwitch() end
            end);  y = y - h
            return math.abs(y)
        end

        local slc = SLC()
        if not slc then return math.abs(y) end
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
        _, h = W:SectionHeader(parent, tags.heading:upper(), y);  y = y - h

        local councilCfg = { type = "label", text = "", tooltip = inForce.emptyText, noCapture = true }
        local masterCfg = { type = "label", text = "", noCapture = true }
        local frame
        frame, h = W:DualRow(parent, y, councilCfg, masterCfg);  y = y - h
        if not prebuild then
            local region = frame._leftRegion
            local liveBtn = TagButton(region, 60, function(button)
                if tags.clickLive(button) then Invalidate() end
            end)
            local masterLabel = frame._rightRegion._label
            masterLabel:SetPoint("RIGHT", frame._rightRegion, "RIGHT", -20, 0)
            OnRefresh(function()
                RefreshActiveTag()
                local live = tags.live()
                liveBtn:SetShown(live)


                if live then
                    region._label:SetPoint("RIGHT", liveBtn, "LEFT", -8, 0)
                    local _, liveTone, liveLines = tags.liveTooltip()
                    liveBtn.Label:SetText(S.Colorize(S.color[liveTone], tags.liveText))
                    liveBtn.tip = table.concat(liveLines, "\n")
                else
                    region._label:SetPoint("RIGHT", region, "RIGHT", -20, 0)
                end
                masterLabel:SetText(Format(lootMaster.line, lootMaster.name(), lootMaster.role()))
            end)
            OnRefresh(function()
                local entries = inForce.entries(PlayerText, RankText)
                local shown, lines = {}, {}
                for _, entry in ipairs(entries) do
                    local text = entry.count and Format(T["%s (%s)"], entry.text, entry.count)
                        or entry.text
                    shown[#shown + 1] = text
                    lines[#lines + 1] = text
                    for _, member in ipairs(entry.rank and entry.tooltip or {}) do
                        lines[#lines + 1] = "  " .. member
                    end
                end
                if #shown == 0 then
                    shown[1] = S.Colorize(S.color.bad, inForce.emptyText)
                    lines[1] = inForce.emptyText
                end
                region._label:SetText(Format(inForce.line, table.concat(shown, ", ")))
                councilCfg.tooltip = table.concat(lines, "\n")
            end)
        end



        local actions = Schema.Actions()
        for i = 1, #actions, 3 do
            local a, b, c = actions[i], actions[i + 1], actions[i + 2]
            local function Open(action)
                return action and function()
                    EllesmereUI:Hide()
                    action.onClick()
                end
            end
            _, h = W:WideTripleButton(parent, a.text, b and b.text, c and c.text, y,
                Open(a), Open(b), Open(c));  y = y - h
        end




        local custom = {}



        function custom.responses(spec)
            for index, entry in ipairs(spec.list()) do
                local nameCfg = { type = "input", text = Format(spec.nameLabel, index),
                    inputStyle = "popup", inputWidth = 180, noCapture = true,
                    getValue = function() return entry.text or "" end,

                    setValue = function(text) spec.setName(index, text) Invalidate() end }
                local keysCfg = { type = "input", text = spec.keysLabel,
                    inputStyle = "popup", inputWidth = 180, noCapture = true,
                    getValue = function() return entry.whisper or "" end,
                    setValue = function(text) spec.setKeys(index, text) end }
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
                                if spec.remove(index) then RequestRebuild() end
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
                        RequestRebuild()
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
            local addRow = Row(50)
            local box = InputBox(addRow, math.min(260, Width() - 20 - 8 - 90 - 20))
            box:SetPoint("LEFT", addRow, "LEFT", 20, 0)
            local addBtn = CreateFrame("Button", nil, addRow)
            PP.Size(addBtn, 90, 28)
            PP.Point(addBtn, "LEFT", box, "RIGHT", 8, 0)
            addBtn:SetFrameLevel(addRow:GetFrameLevel() + 2)

            local function CloseSuggestions()
                if EllesmereUI.ContextMenuOwner and EllesmereUI.ContextMenuOwner() == box then
                    EllesmereUI.CloseContextMenu()
                end
            end
            local function AddTyped()
                CloseSuggestions()
                local name = box:GetText():trim()
                if name == "" then return end

                if TryPride(name) then
                    box:SetText("")
                    box:ClearFocus()
                    return
                end
                if spec.add(name) then box:SetText("") end
                box:ClearFocus()
                RequestRebuild()
            end
            EllesmereUI.MakeStyledButton(addBtn, spec.addText(), 12, EllesmereUI.WB_COLOURS, AddTyped)
            box:SetScript("OnEnterPressed", AddTyped)
            box:HookScript("OnEscapePressed", CloseSuggestions)
            box:HookScript("OnHide", CloseSuggestions)

            box:HookScript("OnTextChanged", function(b, userInput)
                if not userInput then return end
                CloseSuggestions()
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
            end)



            local entries, here = spec.entries(), slc.GetCandidates()
            OnRefresh(function() entries, here = spec.entries(), slc.GetCandidates() end)
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
                    RequestRebuild()
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
                        if done then RequestRebuild() end
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
            for _, alt in ipairs(alts) do
                local row = Row(34)

                local label = EllesmereUI.MakeFont(row, 13, nil, 1, 1, 1)
                label:SetPoint("LEFT", row, "LEFT", 20, 0)

                OnRefresh(function() label:SetText(Qualified(alt)) end)
                local copy = spec.confirmRemove()
                CloseButton(row, copy.accept, function()
                    S.Confirm({ title = copy.title, body = copy.body, accept = copy.accept,
                        onAccept = function()
                            spec.removeAlt(alt)
                            RequestRebuild()
                        end })
                end)
            end
        end




        for _, section in ipairs(Schema.Sections()) do
            _, h = W:SectionHeader(parent, section.title:upper(), y);  y = y - h
            for _, row in ipairs(section.rows) do
                if row.hidden and row.hidden() then

                elseif row.id == "boeReason" then
                    local cfg = BoECfg(row)
                    Place(cfg, function(region)
                        if region._control then region._control:SetMaxLetters(row.maxLetters) end
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
            for _, section in ipairs(Schema.Sections()) do
                for _, row in ipairs(section.rows) do
                    parts[#parts + 1] = (row.hidden and row.hidden()) and "h" or "v"
                end
            end
            local ranks = Schema.Row("councilRanks")
            local alts = Schema.Row("alts")
            parts[#parts + 1] = #Schema.Row("responses").list()
            parts[#parts + 1] = #Schema.Row("council").entries()
            parts[#parts + 1] = math.min(#ranks.ranks(), ranks.maxRows)
            parts[#parts + 1] = ranks.empty() or ""
            parts[#parts + 1] = #alts.alts(alts.main())
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
        parent:HookScript("OnShow", function() Listen(true) end)
        parent:HookScript("OnHide", function() Listen(false) end)
        if parent:IsVisible() then Listen(true) end
        ShowBanner()

        return math.abs(y)
    end




    EllesmereUI:RegisterModule(ADDON_NAME, {
        title       = "Simple Loot Council",
        description = "Loot council voting for your raid, synced over addon messages.",
        pages       = { PAGE_SETTINGS },
        buildPage   = function(pageName, parent, yOffset)
            if pageName == PAGE_SETTINGS then return BuildSettingsPage(pageName, parent, yOffset) end
        end,

        onPageCacheRestore = function()
            ShowBanner()
            EllesmereUI:RefreshPage()
        end,

        onModuleLeave = HideBanner,
    })
end)

if IsLoggedIn() then initFrame:GetScript("OnEvent")(initFrame) end
