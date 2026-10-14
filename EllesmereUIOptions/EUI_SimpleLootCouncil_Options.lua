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



    local function BoECfg(row)
        local values, order = { [0] = row.placeholder }, {}
        for index, reason in ipairs(row.reasons()) do
            values[index] = reason.text
            order[#order + 1] = index
        end
        values._noLoc = true
        local cfg = { type = "dropdown", text = row.text, values = values, order = order,
            tooltip = (row.status()), noCapture = true,
            getValue = function() return row.current() or 0 end,
            setValue = function(index)
                row.choose(index)
                Invalidate()
            end }
        if #order == 0 then
            cfg.disabled = function() return true end
            cfg.disabledTooltip = row.emptyText
            cfg.rawTooltip = true
        end
        return cfg
    end







    local function TagButton(region, width, onClick)
        local PP = EllesmereUI.PanelPP
        local btn = CreateFrame("Button", nil, region)
        PP.Size(btn, width, 24)
        local anchor = region._lastInline or region._control
        if anchor then
            PP.Point(btn, "RIGHT", anchor, "LEFT", -8, 0)
        else
            PP.Point(btn, "RIGHT", region, "RIGHT", -20, 0)
        end
        region._lastInline = btn
        btn:SetFrameLevel(region:GetFrameLevel() + 5)
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

        local function Width() return parent:GetWidth() - PAD * 2 end


        local function Row(height)
            local row = CreateFrame("Frame", nil, parent)
            PP.Size(row, Width(), height)
            PP.Point(row, "TOPLEFT", parent, "TOPLEFT", PAD, y)
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
            PP.Point(row, "TOPLEFT", parent, "TOPLEFT", PAD, y)
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


        local pending
        local function Place(cfg, decorate)
            if not pending then
                pending = { cfg = cfg, decorate = decorate }
                return
            end
            local frame
            frame, h = W:DualRow(parent, y, pending.cfg, cfg);  y = y - h
            if not prebuild then
                if pending.decorate then pending.decorate(frame._leftRegion) end
                if decorate then decorate(frame._rightRegion) end
            end
            pending = nil
        end
        local function Flush()
            if not pending then return end
            local frame
            frame, h = W:DualRow(parent, y, pending.cfg, EllesmereUI.BlankRowCfg());  y = y - h
            if not prebuild and pending.decorate then pending.decorate(frame._leftRegion) end
            pending = nil
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

        local stateCfg = { type = "label", text = "", noCapture = true }
        local masterCfg = { type = "label", text = "", noCapture = true }
        local frame
        frame, h = W:DualRow(parent, y, stateCfg, masterCfg);  y = y - h
        if not prebuild then
            local stateRegion = frame._leftRegion
            local activeBtn = TagButton(stateRegion, 86, function(button)
                if button == "LeftButton" and tags.clickActive() then Invalidate() end
            end)
            local liveBtn = TagButton(stateRegion, 60, function(button)
                if tags.clickLive(button) then Invalidate() end
            end)

            stateRegion._label:SetPoint("RIGHT", liveBtn, "LEFT", -8, 0)
            local masterLabel = frame._rightRegion._label
            masterLabel:SetPoint("RIGHT", frame._rightRegion, "RIGHT", -20, 0)
            OnRefresh(function()
                local title, tone, lines = tags.activeTooltip()
                stateRegion._label:SetText(lines[1] or "")
                activeBtn.Label:SetText(S.Colorize(S.color[tone], title))
                activeBtn.tip = table.concat(lines, "\n")
                local live = tags.live()
                liveBtn:SetShown(live)
                if live then
                    local _, liveTone, liveLines = tags.liveTooltip()
                    liveBtn.Label:SetText(S.Colorize(S.color[liveTone], tags.liveText))
                    liveBtn.tip = table.concat(liveLines, "\n")
                end
                masterLabel:SetText(Format(lootMaster.line, lootMaster.name(), lootMaster.role()))
            end)
        end

        local councilCfg = { type = "label", text = "", tooltip = inForce.emptyText, noCapture = true }
        frame, h = W:DualRow(parent, y, councilCfg, EllesmereUI.BlankRowCfg());  y = y - h
        if not prebuild then
            local region = frame._leftRegion

            region._label:SetPoint("RIGHT", region, "RIGHT", -20, 0)
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
            local box = InputBox(addRow, 260)
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
            _, h = W:SectionHeader(parent, spec.heading:upper(), y);  y = y - h
            if not prebuild then
                for _, hint in ipairs(spec.hints()) do Note(hint) end
            end
            local ranks = spec.ranks()
            for index = 1, math.min(#ranks, spec.maxRows) do
                local name = ranks[index].name
                Place({ type = "toggle", text = name, noCapture = true,
                    getValue = function() return spec.isEmpowered(name) end,
                    setValue = function(value)
                        spec.setEmpowered(name, value)
                        Invalidate()
                    end })
            end
            Flush()
            local empty = spec.empty()
            if empty and not prebuild then Note(empty) end
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
                    Place(cfg, function()
                        OnRefresh(function() cfg.tooltip = (row.status()) end)
                    end)
                elseif row.custom then
                    Flush()
                    custom[row.id](row)
                else
                    local cfg = Cfg(row)
                    Place(cfg, Decorator(row, cfg))
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
            parts[#parts + 1] = #(slc.db.awardReasons or {})
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

        return math.abs(y)
    end




    EllesmereUI:RegisterModule(ADDON_NAME, {
        title       = "Simple Loot Council",
        description = "Loot council voting for your raid, synced over addon messages.",
        pages       = { PAGE_SETTINGS },
        buildPage   = function(pageName, parent, yOffset)
            if pageName == PAGE_SETTINGS then return BuildSettingsPage(pageName, parent, yOffset) end
        end,

        onPageCacheRestore = function() EllesmereUI:RefreshPage() end,
    })
end)

if IsLoggedIn() then initFrame:GetScript("OnEvent")(initFrame) end
