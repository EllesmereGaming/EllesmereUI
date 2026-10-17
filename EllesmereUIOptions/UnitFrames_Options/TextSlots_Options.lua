if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
local ns = EllesmereUI._ModuleNS["EllesmereUIUnitFrames"]
if not ns then return end

local MOVE_KEYS = { "X", "Y", "WidthPct", "ClassColor", "ColorR", "ColorG", "ColorB",
    "NameFormat", "TargetSep", "TargetPrefix", "TargetSepColor", "TargetSepClassColor" }

-- Level coloring is shared by the unit, and edited from its level-text cogs.
function ns.UF_CoreTextRows(prefix, contentDefault, get, set, rows)
    rows = ns.UF_NameFormatRows(prefix, contentDefault, get, set, rows)
    local content = get(prefix .. "Content", contentDefault)
    if content ~= "level" and content ~= "levelname" and content ~= "namelevel" then return rows end
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
    textValues.none = "Remove"
    for i = 1, #slots do
        local s = slots[i]
        order[i], values[s.key], byKey[s.key] = s.key, s.position, s
        s.cfg.values = textValues
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
            if v ~= "none" and v ~= "---" then
                local used = false
                for j = 1, #slots do
                    if slots[j].cfg.getValue() == v then used = true; break end
                end
                if not used then return v end
            end
        end
    end
    local function Notify(key)
        ns._ufTextNotify = { unit = opts.unit, key = key }
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
            local v = db[source .. suffix]
            if type(v) == "table" then v = CopyTable(v) end
            db[dest .. suffix] = v
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
