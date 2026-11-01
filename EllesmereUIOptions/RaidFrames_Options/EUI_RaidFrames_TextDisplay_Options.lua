if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  RaidFrames_Options\EUI_RaidFrames_TextDisplay_Options.lua
--  Raid Frames options: the texts of the Text Display section. One tile per
--  shown text (ns.RF_TEXTS), labelled with its position: the row label moves
--  it (texts may share a position), the dropdown picks its mode or removes
--  it, "+ Add Text" shows a hidden one. Every text keeps its own keys.
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUIRaidFrames"]
if not ns then return end  -- module disabled: no options page

-- Dropdown entries per kind; "none" is the dropdown's Remove.
local MODE_VALUES = {
    name = { none = "Remove", name = "Name", levelname = "Level Name", levelnameDiv = "Level | Name" },
    level = { none = "Remove", level = "Level" },
    hp = { none = "Remove", percent = "Health %", percentNoSign = "Health % (No Sign)",
        number = "Health #", numberPercent = "Health # | %", percentNumber = "Health % | #",
        missing = "Health Missing #" },
    pp = { none = "Remove", percent = "Power %", percentNoSign = "Power % (No Sign)",
        number = "Power #", numberPercent = "Power # | %", percentNumber = "Power % | #" },
    ha = { none = "Remove", short = "Heal Absorb Short (80k)", amount = "Heal Absorb Amount" },
    custom = { none = "Remove" },
}
local MODE_ORDER = {
    name = { "none", "---", "name", "levelname", "levelnameDiv" },
    level = { "none", "---", "level" },
    hp = { "none", "---", "percent", "percentNoSign", "number", "numberPercent", "percentNumber", "missing" },
    pp = { "none", "---", "percent", "percentNoSign", "number", "numberPercent", "percentNumber" },
    ha = { "none", "---", "short", "amount" },
    custom = { "none", "---", "custom" },
}
-- The mode a text shown from "+ Add Text" starts with.
local FIRST_MODE = { hp = "percent", pp = "percent", ha = "short" }
-- The level in front of the name, as the name tile's dropdown names it.
local ATTACH_VALUE = { name = "levelname", nameDiv = "levelnameDiv" }

-- Power Colored: Power Text and Custom (whose tags may read power) only.
local function AllowsPower(t)
    return t.kind == "pp" or t.kind == "custom"
end

-------------------------------------------------------------------------------
--  Custom text: the template popup over the module's catalog (ns.RF_TextTags)
--  and the dropdown copy whose Custom entry opens it.
-------------------------------------------------------------------------------
local CustomText = {}
do
    -- The text's colour mode as the preview shows it, for the player's class and power.
    function CustomText.Color(t)
        local SVal = ns._RFO_OptEnv.SVal
        local _, cls = UnitClass("player")
        local _, pTok = UnitPowerType("player")
        local r, g, b = ns.RF_PreviewTextColor(SVal(t.cm, "custom"), SVal(t.col), cls, 1, 1, 1, pTok)
        return { r = r, g = g, b = b }
    end

    -- key: the format key (party-aware through the page's SVal/SWrite); onSave
    -- runs after the format is stored.
    function CustomText.Edit(key, color, onSave)
        local env = ns._RFO_OptEnv
        EllesmereUI.TextTags.EditPopup({
            cat = ns.RF_TextTags, color = color, onSave = onSave,
            tagNotes = { hp = EllesmereUI.L("shows DEAD or OFFLINE") },
            get = function() return env.SVal(key) end,
            set = function(txt) env.SWrite(key, txt) end,
        })
    end

    -- A copy of a mode list whose Custom entry is an action that opens the popup,
    -- beside Remove in the house red.
    function CustomText.Values(values, edit)
        return EllesmereUI.TextTags.MenuValues(values, edit, { removeKey = "none" })
    end

    -- The popup writes the format directly, so Spec Overrides needs an accessor.
    function CustomText.AddAccessor(rgn, label, key)
        local env = ns._RFO_OptEnv
        EllesmereUI.TextTags.AddFormatAccessor(rgn, label,
            function() return env.SVal(key) end,
            function(v) env.SSet(key, v) end)
    end
end

-------------------------------------------------------------------------------
--  The text list
-------------------------------------------------------------------------------
-- Builds the tiles at y under the Text Display header. opts.page: the page
-- being built (cache check); opts.party: the Party tab (its textDisplay keys).
-- Returns y and the first row.
function ns.RFO_BuildTextDisplay(W, parent, y, opts)
    -- The text files did not load: no text section, the page still builds.
    if not (ns.RF_TEXTS and ns.RF_TEXT_POSITIONS and ns.RF_TextShown and ns.RF_TEXT_SIG_KEYS) then return y end
    local env = ns._RFO_OptEnv
    local SVal, SWrite, ReloadAndUpdate = env.SVal, env.SWrite, env.ReloadAndUpdate
    local TEXTS, POSITIONS, POS_INDEX = ns.RF_TEXTS, ns.RF_TEXT_POSITIONS, ns.RF_TEXT_POS_INDEX
    local POS = EllesmereUI.POSITION_GRID_VALUES
    local LEVEL_DEFAULT = ns.RF_LEVEL_DEFAULT

    local function PosOf(t)
        if t.kind == "level" then return SVal(t.pos, LEVEL_DEFAULT) end
        return SVal(t.pos, "center")
    end
    -- Shown by the engine's own rule, read through the page's (party-aware) SVal.
    local view = setmetatable({}, { __index = function(_, k) return SVal(k) end })
    local function Shown(t)
        return ns.RF_TextShown(t, view, SVal("levelTextPosition", LEVEL_DEFAULT)) ~= nil
    end
    -- The value the tile's dropdown shows.
    local function ModeOf(t)
        if t.kind == "name" then return ATTACH_VALUE[SVal("levelTextPosition", LEVEL_DEFAULT)] or "name" end
        if t.mode then return SVal(t.mode, "none") end
        return t.kind
    end
    -- The first position no shown text uses, else pref.
    local function FreePos(pref)
        local used = {}
        for i = 1, #TEXTS do
            if Shown(TEXTS[i]) then used[PosOf(TEXTS[i])] = true end
        end
        if not used[pref] then return pref end
        for i = 1, #POSITIONS do
            if not used[POSITIONS[i]] then return POSITIONS[i] end
        end
        return pref
    end
    local function Notify(t)
        ns._rfTextNotify = { page = opts.page, key = t.id }
    end
    local function Apply()
        ReloadAndUpdate()
        EllesmereUI:RefreshPage(true)
    end

    -- A dropdown pick: a mode, the level format in front of the name, or Remove.
    local function SetMode(t, v)
        if t.kind == "name" then
            if v == "none" then
                SWrite(t.pos, "none")
            else
                local lp = SVal("levelTextPosition", LEVEL_DEFAULT)
                if v == "levelname" then
                    SWrite("levelTextPosition", "name")
                elseif v == "levelnameDiv" then
                    SWrite("levelTextPosition", "nameDiv")
                elseif ATTACH_VALUE[lp] then
                    SWrite("levelTextPosition", "none")
                end
            end
        elseif t.kind == "level" or t.kind == "custom" then
            if v == "none" then SWrite(t.pos, "none") end
        elseif v ~= SVal(t.mode, "none") then
            SWrite(t.mode, v)
        end
        Apply()
    end
    local function Move(t, pos)
        if pos == PosOf(t) then return end
        SWrite(t.pos, pos)
        Notify(t)
        Apply()
    end
    -- "+ Add Text": a hidden text comes back with its own stored settings; a
    -- Custom text asks for its template first.
    local function Show(t)
        if t.kind == "custom" then
            CustomText.Edit(t.fmt, CustomText.Color(t), function()
                SWrite(t.pos, FreePos("center"))
                Notify(t)
                Apply()
            end)
            return
        end
        if t.kind == "name" then
            SWrite(t.pos, FreePos("topleft"))
        elseif t.kind == "level" then
            SWrite(t.pos, FreePos("topright"))
        else
            -- The second Health Text has no upstream spot of its own: a free one
            -- (looked up while it is still hidden).
            if t.id == "hp2" then SWrite(t.pos, FreePos(SVal(t.pos, "bottom"))) end
            SWrite(t.mode, FIRST_MODE[t.kind])
        end
        Notify(t)
        Apply()
    end

    -- Swatches (Custom nearest the dropdown, then Class, Accent, Power), the
    -- colour mode accessor and the cog of one shown text. The level is drawn in
    -- the name's colour: no swatches of its own.
    local function Decorate(rgn, cell)
        local t = cell.text
        if t.kind ~= "level" then
            local modeKey = t.cm
            local function AddSwatch(getColor, setColor, mode, opensPicker, tooltip)
                local sw = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, getColor, setColor, false, 20)
                env.PP.Point(sw, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                rgn._lastInline = sw
                sw._eabOrigClick = sw:GetScript("OnClick")
                sw:SetScript("OnClick", function(self)
                    if SVal(modeKey, "custom") ~= mode then
                        -- Attribution read before the write: the rebuild dresses the swatch again.
                        local snap = EllesmereUI._SOAttribution(self)
                        env.SSet(modeKey, mode)
                        EllesmereUI._NotifySettingWrite(self, snap)
                        EllesmereUI:RefreshPage()
                        return
                    end
                    if opensPicker and self._eabOrigClick then self._eabOrigClick(self) end
                end)
                sw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(sw, tooltip) end)
                sw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                local function vis() sw:SetAlpha(SVal(modeKey, "custom") == mode and 1 or 0.3) end
                EllesmereUI.RegisterWidgetRefresh(vis)
                vis()
            end
            AddSwatch(function()
                    local c = SVal(t.col)
                    if c then return c.r or 1, c.g or 1, c.b or 1, 1 end
                    return 1, 1, 1, 1
                end,
                function(r, g, b) SWrite(t.col, { r = r, g = g, b = b }); ReloadAndUpdate() end,
                "custom", true, "Custom Color")
            AddSwatch(function()
                    local _, ct = UnitClass("player")
                    local cc = ct and EllesmereUI.GetClassColor(ct)
                    if cc then return cc.r, cc.g, cc.b, 1 end
                    return 1, 1, 1, 1
                end, function() end, "class", false, "Class Color")
            AddSwatch(function()
                    local r, g, b = EllesmereUI.ResolveActiveAccent()
                    return r or 1, g or 1, b or 1, 1
                end, function() end, "accent", false, "Accent Color")
            if AllowsPower(t) then
                AddSwatch(function()
                        local _, pToken = UnitPowerType("player")
                        local info = EllesmereUI.GetPowerColor(pToken or "MANA")
                        if info then return info.r, info.g, info.b, 1 end
                        return 0, 0.5, 1, 1
                    end, function() end, "power", false, "Power Colored Text")
            end
            -- The mode is written only by the swatch clicks above.
            local modeValues = { custom = "Custom Color", class = "Class Color", accent = "Accent Color" }
            local modeOrder = { "custom", "class", "accent" }
            if AllowsPower(t) then
                modeValues.power = "Power Colored Text"
                modeOrder[4] = "power"
            end
            EllesmereUI.AddCaptureAccessor(rgn, {
                type = "dropdown", text = t.label .. " Color Mode",
                values = modeValues, order = modeOrder,
                getValue = function() return SVal(modeKey, "custom") end,
                setValue = function(v) env.SSet(modeKey, v) end,
            })
        end
        local rows = {
            { type = "slider", label = "Size", min = 6, max = 26, step = 1,
              get = function() return SVal(t.size, 10) end,
              set = function(v) env.SSet(t.size, v) end },
            { type = "slider", label = "X Offset", min = -500, max = 500, step = 1,
              get = function() return SVal(t.x, 0) end,
              set = function(v) env.SSet(t.x, v) end },
            { type = "slider", label = "Y Offset", min = -500, max = 500, step = 1,
              get = function() return SVal(t.y, 0) end,
              set = function(v) env.SSet(t.y, v) end },
        }
        -- The name length is shared by every name text of the view (Name Format
        -- has its own row: it shapes the Top Name Bar too).
        local showsName = t.kind == "name"
        if t.kind == "custom" then
            local parsed = EllesmereUI.TextTags.Parse(ns.RF_TextTags, SVal(t.fmt))
            showsName = parsed and parsed.has and parsed.has.name and true or false
        end
        if showsName then
            rows[#rows + 1] = { type = "slider", label = "Max Characters (0=off)", min = 0, max = 30, step = 1,
                get = function() return SVal("nameMaxLength", 15) end,
                set = function(v) env.SSet("nameMaxLength", v) end }
        end
        -- Show Above Icons: the name's own key; every other text follows it until set here.
        if t.kind == "name" then
            rows[#rows + 1] = { type = "toggle", label = "Show Above Icons",
                tooltip = "Render the name above buff and debuff icons. Texts without a setting of their own follow it.",
                get = function() return SVal(t.above, false) and true or false end,
                set = function(v) env.SSet(t.above, v) end }
        else
            rows[#rows + 1] = { type = "toggle", label = "Show Above Icons",
                tooltip = "Render this text above buff and debuff icons. Follows the name's setting until changed here.",
                get = function()
                    local v = SVal(t.above)
                    if v == nil then v = SVal("nameTextAboveIcons", false) end
                    return v and true or false
                end,
                set = function(v) env.SSet(t.above, v) end }
        end
        EllesmereUI.BuildInlineCog(rgn, {
            title = EllesmereUI.Lf("%1$s Settings", EllesmereUI.L(t.label)),
            rows = rows,
        })
    end

    -- Shown texts in grid order (a shared position: in text order).
    local shown = {}
    for i = 1, #TEXTS do
        local t = TEXTS[i]
        if Shown(t) then shown[#shown + 1] = { text = t, i = i, pos = PosOf(t) } end
    end
    table.sort(shown, function(a, b)
        local pa, pb = POS_INDEX[a.pos] or 99, POS_INDEX[b.pos] or 99
        if pa ~= pb then return pa < pb end
        return a.i < b.i
    end)

    local kit = ns.RF_OptPartyKit()
    local cells = {}
    for j = 1, #shown do
        local cell = shown[j]
        local t = cell.text
        local cfg = { type = "dropdown", text = POS[cell.pos] or cell.pos, order = MODE_ORDER[t.kind],
            getValue = function() return ModeOf(t) end,
            setValue = function(v) SetMode(t, v) end }
        if t.kind == "pp" then
            cfg.tooltip = "Shows only on frames whose power bar shows."
        elseif t.kind == "name" and kit then
            cfg.tooltip = "On Party Frames style the name keeps the frame's own spot; its offsets still apply."
        elseif t.kind == "level" then
            cfg.tooltip = "Drawn in the name's colour."
        end
        cfg.values = CustomText.Values(MODE_VALUES[t.kind], t.kind == "custom" and function()
            CustomText.Edit(t.fmt, CustomText.Color(t), function()
                Notify(t)
                Apply()
            end)
        end or nil)
        cell.cfg = cfg
        cells[#cells + 1] = cell
    end

    -- "+ Add Text": every hidden text; the Custom texts as one entry (the next free
    -- one) on top, an action in the accent colour with the edit pencil, as in the
    -- tile dropdowns.
    local addOrder, addValues, addText = {}, {}, {}
    local customId
    local nameShown = Shown(TEXTS[1])
    for i = 1, #TEXTS do
        local t = TEXTS[i]
        local hidden = not Shown(t)
        -- An attached level shows in the name tile while the name does; with the
        -- name hidden (the Top Name Bar may still use it) it can go on its own spot.
        if t.kind == "level" and ATTACH_VALUE[PosOf(t)] and nameShown then hidden = false end
        if hidden and t.kind == "custom" then
            if not customId then
                customId = t.id
                addValues[t.id] = { text = "Custom Text", action = function() Show(t) end }
            end
        elseif hidden then
            addOrder[#addOrder + 1] = t.id
            addValues[t.id] = t.label
            -- An attached level placed on its own spot leaves the Top Name Bar's prefix.
            if t.kind == "level" and ATTACH_VALUE[PosOf(t)] and SVal("topNameBarEnabled", false) then
                addValues[t.id] = "Level (moves it off the Top Name Bar)"
            end
            addText[t.id] = t
        end
    end
    if customId then
        table.insert(addOrder, 1, customId)
        if #addOrder > 1 then table.insert(addOrder, 2, "---") end
        addValues._menuOpts = {
            icon = function(key) if key == customId then return EllesmereUI.TextTags.EDIT_ICON end end,
            iconSize = function() return 12 end,
            iconClearScroll = true,
            iconColor = function(key) if key == customId then return 1, 1, 1, 1 end end,
        }
    end
    local addOpen
    local addCfg = { type = "button", text = "+ Add Text", width = 220,
        onClick = function() if addOpen then addOpen() end end,
        disabled = function() return #addOrder == 0 end,
        disabledTooltip = "Every text is shown." }
    cells[#cells + 1] = addCfg

    local function Config(c)
        if not c then return EllesmereUI.BlankRowCfg() end
        return c.cfg or c
    end
    local firstRow
    local function Finish(row, side, cell)
        if not cell then return end
        firstRow = firstRow or row
        local rgn = row[side]
        if cell == addCfg then
            if not EllesmereUI._prebuilding then
                addOpen = EllesmereUI.AttachButtonMenu(rgn._control, { width = 220,
                    order = addOrder, values = addValues,
                    setValue = function(id) if addText[id] then Show(addText[id]) end end })
            end
            return
        end
        if EllesmereUI._prebuilding then return end
        local t = cell.text
        -- Spec Overrides name a captured write after the text, not its position
        -- (several texts may share one).
        if rgn._captureCfg then
            rgn._captureCfg = setmetatable({ text = t.label }, { __index = rgn._captureCfg })
        end
        EllesmereUI.BuildRowLabelMenu(rgn, { order = POSITIONS, values = POS,
            getValue = function() return PosOf(t) end,
            setValue = function(v) Move(t, v) end,
            tooltip = "Choose this text's position." })
        Decorate(rgn, cell)
        if t.kind == "custom" then CustomText.AddAccessor(rgn, t.label, t.fmt) end
        local pending = ns._rfTextNotify
        if pending and pending.page == opts.page and pending.key == t.id then
            ns._rfTextNotify = nil
            -- The text read now, while this build's cell is its dress.
            local snap = EllesmereUI._SOAttribution(rgn)
            EllesmereUI._NotifySettingWrite(rgn, snap)
        end
    end
    for i = 1, #cells, 2 do
        local row, h = W:DualRow(parent, y, Config(cells[i]), Config(cells[i + 1]))
        y = y - h
        Finish(row, "_leftRegion", cells[i])
        Finish(row, "_rightRegion", cells[i + 1])
    end

    if not EllesmereUI._prebuilding and opts.page then
        -- Presets, spec changes and profile switches can alter the list while
        -- the page is cached: what decides the tiles as built, against the stored.
        -- A Custom text's template counts too (its cog's name row follows it).
        local SIG_KEYS = ns.RF_TEXT_SIG_KEYS
        local function Sig(get)
            local parts = {}
            for i = 1, #SIG_KEYS do parts[i] = tostring(get(SIG_KEYS[i])) end
            return table.concat(parts, "\31")
        end
        local saved = Sig(SVal)
        local party = opts.party
        ns._rfTextChecks = ns._rfTextChecks or {}
        ns._rfTextChecks[opts.page] = function()
            local pf = ns.db and ns.db.profile
            if not pf then return false end
            local own = party and ns._IsPartySectionCustom and ns._IsPartySectionCustom("textDisplay")
            return Sig(function(k)
                local v
                if own then v = pf["party_" .. k] end
                if v == nil then v = pf[k] end
                return v
            end) ~= saved
        end
    end
    return y, firstRow
end
