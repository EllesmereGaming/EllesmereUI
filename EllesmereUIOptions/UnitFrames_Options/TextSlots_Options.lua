if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
local ns = EllesmereUI._ModuleNS["EllesmereUIUnitFrames"]
if not ns then return end

local MOVE_KEYS = { "X", "Y", "WidthPct", "ClassColor", "ColorR", "ColorG", "ColorB",
    "NameFormat", "TargetSep", "TargetPrefix", "TargetSepColor", "TargetSepClassColor", "CustomFormat" }

-- False for content a slot keeps to itself: "none", and "custom", whose format
-- is stored per slot, so several slots may use it and none is picked for them.
function ns.UF_IsUniqueContent(v)
    return v ~= "none" and v ~= "custom"
end

-- Custom text popup for any text slot. prefix names the slot's keys
-- (<prefix>CustomFormat, ClassColor, ColorR/G/B); db is the unit's settings;
-- onSave runs after the format is stored and selects Custom for the slot.
function ns.UFO_EditCustomText(prefix, db, unit, onSave)
    local key = prefix .. "CustomFormat"
    -- The preview in the slot's text colour, as the unit preview shows it.
    local color
    -- Power Colored: the page's unit while it exists (boss1 for Boss),
    -- else the player, as the unit preview shows it.
    local function PowerColor()
        local u = unit == "boss" and "boss1" or unit
        local r, g, b = EllesmereUI.ResolveUnitPowerColor((u and UnitExists(u)) and u or "player")
        return r and { r = r, g = g, b = b }
    end
    if prefix == "powerText" then
        -- The power text's own keys: Power Colored, else powerTextColor.
        local pc = db.powerPercentTextPowerColor and PowerColor()
        color = pc or (not db.powerPercentTextPowerColor and db.powerTextColor) or { r = 1, g = 1, b = 1 }
    elseif db[prefix .. "PowerColor"] then
        -- The text bar's Power Colored. Fixed for the popup: the bar uses it
        -- only while the format holds a power tag.
        color = PowerColor()
    elseif db[prefix .. "ClassColor"] then
        if unit == "player" then
            local _, cls = UnitClass("player")
            color = cls and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[cls]
        else
            color = { r = 0.9, g = 0.3, b = 0.3 }
        end
    else
        color = { r = db[prefix .. "ColorR"] or 1, g = db[prefix .. "ColorG"] or 1, b = db[prefix .. "ColorB"] or 1 }
    end
    EllesmereUI.TextTags.EditPopup({
        cat = ns.UF_TextTags, color = color, onSave = onSave,
        tagNotes = { hp = EllesmereUI.L("shows DEAD or OFFLINE") },
        get = function() return db[key] end,
        set = function(txt) db[key] = txt end,
    })
end

-- A copy of a slot's dropdown values whose Custom entry is an action that
-- opens the popup (edit), its pencil at full alpha while getValue() is
-- "custom". The menu reads the alpha when it is built, so a selection has
-- to rebuild it (page rebuild or _invalidateMenu).
function ns.UFO_CustomTextValues(values, getValue, edit)
    return EllesmereUI.TextTags.MenuValues(values, edit,
        { selected = function() return getValue() == "custom" end })
end

-- For a dropdown whose selection keeps the page: rebuilds the given regions'
-- menus once the list has closed, for Custom's pencil to follow the selection.
-- The widget refresh is the menu's own deferred one, which Custom's popup path
-- never reaches: without it colour swatches and cogs keep the previous state.
function ns.UFO_RefreshMenus(...)
    local n, rgns = select("#", ...), { ... }
    C_Timer.After(0, function()
        for i = 1, n do
            local dd = rgns[i] and rgns[i]._control
            if dd and dd._invalidateMenu then dd._invalidateMenu() end
        end
        local rl = EllesmereUI._widgetRefreshList
        if rl then for ri = 1, #rl do rl[ri]() end end
    end)
end

-- The power text cog (Main and Boss): Show % for the preset formats in pctOff's
-- complement; Custom writes its own %, so it keeps only the Name Format, and
-- only while the format shows a name.
local PCT_TIP = "This option is only available for formats that display a percentage."
function ns.UFO_PowerTextCog(get, set, pctOff, setShowPct)
    local rows = ns.UF_NameFormatRows("powerText", "perpp", get, set, {
        { type="toggle", label="Show %",
          disabled=function() return get("powerTextFormat", "perpp") == "custom" end,
          disabledTooltip=PCT_TIP,
          get=function() return get("powerShowPercent", true) ~= false end,
          set=setShowPct },
    }, "powerTextFormat")
    return {
        title = "Power Text", rows = rows,
        disabled = function()
            local fmt = get("powerTextFormat", "perpp")
            if fmt == "custom" then
                return not ns.UF_ContentShowsName(fmt, get("powerTextCustomFormat"))
            end
            return pctOff[fmt] == true
        end,
        disabledTooltip = function()
            if get("powerTextFormat", "perpp") == "custom" then
                return "This option only applies when the text shows a name."
            end
            return PCT_TIP
        end,
    }
end

-- The popup writes the format directly, so Spec Overrides needs an accessor:
-- on a Custom slot, or one holding a format an override may switch back to.
function ns.UFO_AddCustomFormatAccessor(rgn, label, prefix, content, getDB, apply)
    local fk = prefix .. "CustomFormat"
    if content ~= "custom" and type(getDB()[fk]) ~= "string" then return end
    EllesmereUI.TextTags.AddFormatAccessor(rgn, label,
        function() return getDB()[fk] end,
        function(v) getDB()[fk] = v; apply() end)
end

-- Level coloring is shared by the unit, and edited from its level-text cogs.
function ns.UF_CoreTextRows(prefix, contentDefault, get, set, rows)
    rows = ns.UF_NameFormatRows(prefix, contentDefault, get, set, rows)
    local content = get(prefix .. "Content", contentDefault)
    local parsed = content == "custom"
        and EllesmereUI.TextTags.Parse(ns.UF_TextTags, get(prefix .. "CustomFormat"))
    local hasLevel = content == "level" or content == "levelname" or content == "namelevel"
        or (parsed and parsed.has.level)
    if not hasLevel then return rows end
    rows[#rows + 1] = { type="toggle", label="Level Text: Difficulty Color",
        tooltip="Colors level text by difficulty, from grey (trivial) through green, yellow and orange to red (5+ levels above you).",
        get=function() return get("levelDifficultyColor", false) == true end,
        set=function(v)
            set("levelDifficultyColor", v)
            ns._UFO_OptEnv.UpdatePreview()
        end }
    rows[#rows + 1] = { type="toggle", label="Level Text: Include Friendly",
        tooltip="Friendly units get their level's color too, instead of gold.",
        disabled=function() return get("levelDifficultyColor", false) ~= true end,
        disabledTooltip="Level Text: Difficulty Color",
        get=function() return get("levelDifficultyColorFriendly", false) == true end,
        set=function(v)
            set("levelDifficultyColorFriendly", v)
            ns._UFO_OptEnv.UpdatePreview()
        end }
    return rows
end

-- Keep the unit-frame settings and inline controls; only the list changes.
function ns.UFO_BuildTextSlots(W, parent, y, opts)
    local header, headerH = W:SectionHeader(parent, "CORE TEXT POSITIONS", y)
    y = y - headerH
    parent._ufTextHeader = header
    local slots, order, values = opts.slots, {}, {}
    local byKey, cells, targets = {}, {}, {}
    local textValues = CopyTable(opts.values)
    -- Remove in the house BAD red with the close X at the row's right edge: 12px,
    -- at the list delete buttons' 0.75 alpha; both brighten on hover.
    textValues.none = "Remove"
    textValues._menuOpts = {
        icon = function(key)
            if key == "none" then return "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png" end
        end,
        iconSize = function() return 12 end,
        iconClearScroll = true,
        iconColor = function() return 1, 0.35, 0.35, 0.75 end,
        labelColor = function(key)
            if key == "none" then return 1, 0.35, 0.35, 0.8 end
        end,
    }
    local function Notify(key)
        ns._ufTextNotify = { unit = opts.unit, key = key }
    end
    for i = 1, #slots do
        local s = slots[i]
        order[i], values[s.key], byKey[s.key] = s.key, s.position, s
        if textValues.custom then
            -- Custom is an action entry: it opens the format popup, and a saved
            -- format selects it for the slot (a selection rebuilds the page).
            s.cfg.values = ns.UFO_CustomTextValues(textValues, s.cfg.getValue, function()
                ns.UFO_EditCustomText(s.key, opts.db(), opts.unit, function()
                    Notify(s.key)
                    s.cfg.setValue("custom")
                end)
            end)
        else
            s.cfg.values = textValues
        end
        if s.cfg.getValue() ~= "none" then cells[#cells + 1] = s end
    end
    local function Assigned(key)
        local s = byKey[key]
        return s and s.cfg.getValue() ~= "none"
    end
    local function Full()
        for i = 1, #slots do
            if not Assigned(slots[i].key) then return false end
        end
        return true
    end
    local function Candidate()
        for i = 1, #opts.contentOrder do
            local v = opts.contentOrder[i]
            if v ~= "---" and ns.UF_IsUniqueContent(v) then
                local used = false
                for j = 1, #slots do
                    if slots[j].cfg.getValue() == v then used = true; break end
                end
                if not used then return v end
            end
        end
    end
    local function Add(key)
        local v = Candidate()
        if Assigned(key) or not byKey[key] or not v then
            EllesmereUI:RefreshPage(true); return
        end
        Notify(key)
        byKey[key].cfg.setValue(v)
    end
    local function Move(source, dest)
        if source == dest then return end
        if not Assigned(source) or not byKey[dest] or Assigned(dest) then
            EllesmereUI:RefreshPage(true); return
        end
        local db = opts.db()
        local content = byKey[source].cfg.getValue()
        local size = db[source .. "Size"] or db.textSize or 12
        for i = 1, #MOVE_KEYS do
            local suffix = MOVE_KEYS[i]
            -- The format moves only with Custom; otherwise the destination keeps its own.
            if suffix ~= "CustomFormat" or content == "custom" then
                local v = db[source .. suffix]
                if type(v) == "table" then v = CopyTable(v) end
                db[dest .. suffix] = v
            end
        end
        db[dest .. "Size"] = size
        if dest == "extraText" then
            db.extraTextAlign = source == "rightText" and "right" or source == "centerText" and "center" or "left"
        end
        db[dest .. "Content"], db[source .. "Content"] = content, "none"
        Notify(dest)
        opts.apply()
        EllesmereUI:RefreshPage(true)
    end

    local addOpen
    local addCfg = { type="button", text="+ Add Text Slot", width=220,
        onClick=function() if addOpen then addOpen() end end,
        disabled=function() return Full() or Candidate() == nil end,
        disabledTooltip="Every text position is full." }
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
                addOpen = EllesmereUI.AttachButtonMenu(rgn._control, { width=220,
                    order=order, values=values, setValue=Add,
                    itemDisabled=function(v) return Assigned(v) or Candidate() == nil end })
            end
            return
        end
        if not cell.key then return end
        targets[cell.key] = { row=row, side=side }
        if EllesmereUI._prebuilding then return end
        EllesmereUI.BuildRowLabelMenu(rgn, { order=order, values=values,
            getValue=function() return cell.key end,
            setValue=function(v) Move(cell.key, v) end,
            itemDisabled=function(v)
                if not Assigned(cell.key) then return true end
                if v ~= cell.key and Assigned(v) then return true end
            end,
            tooltip="Choose this text's slot position." })
        cell.decorate(rgn)
        if cell.cfg.values and cell.cfg.values.custom then
            ns.UFO_AddCustomFormatAccessor(rgn, cell.position, cell.key, cell.cfg.getValue(), opts.db, opts.apply)
        end
        local pending = ns._ufTextNotify
        if pending and pending.unit == opts.unit and pending.key == cell.key then
            ns._ufTextNotify = nil
            -- The slot read now, while this build's cell is its dress.
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
    parent._ufTextCells = targets
    if not EllesmereUI._prebuilding then
        -- Presets/spec changes can alter the list while the page is cached.
        local saved = {}
        for i = 1, #slots do saved[i] = slots[i].cfg.getValue() end
        ns._ufTextChecks = ns._ufTextChecks or {}
        ns._ufTextChecks[opts.page] = function()
            local db = opts.liveDB()
            for i = 1, #slots do
                if (db[slots[i].key .. "Content"] or slots[i].default) ~= saved[i] then return true end
            end
            return false
        end
    end
    return y, firstRow
end

function ns.UFO_TextClickTarget(parent, key, section, fallback)
    local c = parent._ufTextCells and parent._ufTextCells[key]
    return { section=c and parent._ufTextHeader or section, target=c and c.row or fallback,
        slotSide=c and (c.side == "_leftRegion" and "left" or "right") or nil }
end
