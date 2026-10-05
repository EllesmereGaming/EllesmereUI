if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Nameplates_Options\ColorsPage_Options.lua
--  Nameplates options: the Colors page (BuildColorsPage) and the mini preview
--  bars of its color rows (MakeColorPreviewBar, built lazily through
--  LazyColorPreviewBar in EUI_Nameplates_Options.lua). Definitions only; the
--  shared helpers come from ns._NPO_OptEnv.
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUINameplates"]
if not ns then return end  -- module disabled: no options page

-- The nameplate Threat % cog's rows (WoW Forever): get(key) reads the
-- profile, set(key, v) writes it and refreshes the text.
if EllesmereUI.IS_FOREVER then
    function ns.NPO_ThreatPctRows(get, set)
        local function Slider(key, label, lo, hi)
            return { type="slider", label=label, min=lo, max=hi, step=1,
              get=function() return get(key) end,
              set=function(v) set(key, v) end }
        end
        -- The gap colours show while the gap is picked and coloured.
        local function GapColorOff()
            return get("threatPctMode") ~= "gap" or not get("threatPctColorByThreat")
        end
        local function GapColor(key, label, tip)
            return { type="colorpicker", label=label, tooltip=tip, hidden=GapColorOff,
              get=function()
                local c = get(key)
                if c then return c.r, c.g, c.b end
                return 1, 1, 1
              end,
              set=function(r, g, b) set(key, { r = r, g = g, b = b }) end }
        end
        return {
            { type="dropdown", label="Text Shows",
              values={ percent = "Threat %", gap = "Threat Gap" }, order={ "percent", "gap" },
              tooltip="Threat Gap shows on your target's plate only.",
              get=function() return get("threatPctMode") or "percent" end,
              set=function(v) set("threatPctMode", v) end },
            { type="toggle", label="Color by Threat",
              tooltip="Colors the number. Off shows it in white.",
              get=function() return get("threatPctColorByThreat") end,
              set=function(v) set("threatPctColorByThreat", v) end },
            GapColor("threatGapAheadColor", "Ahead Color", "When your threat is higher."),
            GapColor("threatGapBehindColor", "Behind Color", "When theirs is higher."),
            Slider("threatPctSize", "Size", 6, 20),
            Slider("threatPctXOffset", "X Offset", -100, 100),
            Slider("threatPctYOffset", "Y Offset", -100, 100),
        }
    end
end

-- EUI_DEBUFF_COLORS: the per-class debuff lists (the list kit lives in
-- EllesmereUINameplates_DebuffColors.lua). Debuffs, then combos, two to a
-- row, each named after its class with up/down arrows beside the name that
-- reorder it (the higher entry wins); an Add button after each list picks
-- the class. Every edit reaches the plates as it is made (the runtime
-- rebuilds at most once a frame, and only for the player's own class); a
-- color drag waits for the picker to close. debuffColorAdded: the entry Add
-- just made, kept across the page rebuild Add runs so the rebuilt row
-- reports the write to Spec Overrides.
local debuffColorAdded
function ns.NP_BuildDebuffColorsOptions(parent, y)
    local DC = ns.DebuffColorKit
    if not DC then return y end
    local W = EllesmereUI.Widgets
    local PP = EllesmereUI.PanelPP
    local function Get(key)
        local db = ns.db and ns.db.profile
        if db and db[key] ~= nil then return db[key] end
        return ns.defaults[key]
    end
    local function Off() return Get("debuffColorsEnabled") ~= true end
    local function Read(class) return DC.Read(class, Get) end
    -- Every edit applies at once. The color picker writes on every frame of a
    -- drag, so while it is open the refresh waits for it to close.
    local function Apply()
        if EllesmereUI._colorPickerOpen then
            EllesmereUI._deferredDriftChecks = EllesmereUI._deferredDriftChecks or {}
            EllesmereUI._deferredDriftChecks[ns.DebuffColors_RequestRefresh] = true
        else
            ns.DebuffColors_RequestRefresh()
        end
    end
    local function Write(class, singles, combos, rgn)
        ns.db.profile[DC.Key(class)] = DC.Encode(singles, combos)
        if rgn then EllesmereUI._NotifySettingWrite(rgn) end
        Apply()
    end
    local function Rebuild() EllesmereUI:RefreshPage(true) end
    local function SpellName(id, fallback)
        return (id and C_Spell and C_Spell.GetSpellName(id)) or fallback
    end
    local function SpellIcon(id)
        if not id then return end
        local texture = C_Spell and C_Spell.GetSpellTexture(id)
        if texture then return texture end
        local info = C_Spell and C_Spell.GetSpellInfo(id)
        local preset = ns.DebuffColorPresetByID[id]
        return (info and info.iconID) or (preset and preset[4])
            or "Interface\\Icons\\INV_Misc_QuestionMark"
    end
    local function CopyColor(c) return { r = c.r, g = c.g, b = c.b } end
    -- A list's chosen spells, each once, in priority order.
    local function Chosen(singles)
        local out, seen = {}, {}
        for _, e in ipairs(singles) do
            if e.spell > 0 and not seen[e.spell] then
                seen[e.spell] = true
                out[#out + 1] = e.spell
            end
        end
        return out
    end

    -- Classes: the player's first, then the rest alphabetically. Only the
    -- classes this client has (a class's saved list elsewhere stays as is).
    local _, playerClass = UnitClass("player")
    local NAME, ORDER = {}, {}
    if EllesmereUI.IS_FOREVER then
        for _, file in ipairs(EllesmereUI.ForeverClasses()) do
            NAME[file] = EllesmereUI.ForeverClassName(file)
            ORDER[#ORDER + 1] = file
        end
    else
        for i = 1, (GetNumClasses and GetNumClasses() or 0) do
            local name, file = GetClassInfo(i)
            if name and file then
                NAME[file] = name
                ORDER[#ORDER + 1] = file
            end
        end
    end
    table.sort(ORDER, function(a, b)
        if (a == playerClass) ~= (b == playerClass) then return a == playerClass end
        return NAME[a] < NAME[b]
    end)
    local CLASS_VALUES = { _noLoc = true }
    for _, class in ipairs(ORDER) do
        local c = EllesmereUI.GetClassColor(class)
        CLASS_VALUES[class] = EllesmereUI.HexColor(c.r, c.g, c.b) .. NAME[class] .. "|r"
    end

    -- The presets for the spell menus (WoW Forever lists none: they are
    -- retail spell IDs). A debuff row offers only its own class's presets, in
    -- the preset table's order; any other spell it holds reads as custom.
    local classPresets = {}
    if not EllesmereUI.IS_FOREVER then
        for _, spell in ipairs(ns.DebuffColorPresets) do
            local token = spell[3]:gsub("%s", ""):upper()
            local set = classPresets[token]
            if not set then
                set = { order = { "remove", "custom" }, byKey = {} }
                classPresets[token] = set
            end
            local key = tostring(spell[1])
            set.order[#set.order + 1] = key
            set.byKey[key] = { id = spell[1], name = SpellName(spell[1], spell[2]), class = spell[3] }
        end
    end
    local NO_PRESETS = { order = { "remove", "custom" }, byKey = {} }
    local function Presets(class) return classPresets[class] or NO_PRESETS end
    -- A class's custom spells: every spell its lists hold that is not one of
    -- its presets, once each, debuffs first. Each is an item of the class's
    -- spell menus for as long as something holds it.
    local function Customs(class)
        local own, out, seen = Presets(class).byKey, {}, {}
        local singles, combos = Read(class)
        local function Add(id)
            local key = tostring(id)
            if id > 0 and not own[key] and not seen[key] then
                seen[key] = true
                out[#out + 1] = key
            end
        end
        for _, e in ipairs(singles) do Add(e.spell) end
        for _, k in ipairs(combos) do
            for _, id in ipairs(k.spells) do Add(id) end
        end
        return out
    end

    local function Label(cell)
        if cell.kind == "combo" then
            return EllesmereUI.Lf("%1$s Combo %2$d", NAME[cell.class], cell.n)
        end
        return EllesmereUI.Lf("%1$s Debuff %2$d", NAME[cell.class], cell.n)
    end
    local function SpellOf(cell)
        local e = Read(cell.class)[cell.n]
        return e and e.spell or 0
    end
    -- A spell another debuff of the class already holds: picking it again
    -- would only duplicate that row, so its menu item is greyed with the
    -- reason and Custom Spell... refuses it (the arrows move a debuff).
    local IN_USE = "Already in use. Use the arrows to reorder."
    local function HeldElsewhere(cell, id)
        for n, e in ipairs((Read(cell.class))) do
            if n ~= cell.n and e.spell == id then return true end
        end
        return false
    end
    local function ComboSpells(cell)
        local _, combos = Read(cell.class)
        local k = combos[cell.n]
        return k and k.spells or {}
    end

    -- List edits. Structure changes (add, remove, reorder) rebuild the page;
    -- the edited or new row reports the write to Spec Overrides.
    local function SetSpell(cell, id, rgn)
        local singles, combos = Read(cell.class)
        local e = singles[cell.n]
        if not e or e.spell == id then return end
        e.spell = id
        Write(cell.class, singles, combos, rgn)
        EllesmereUI:RefreshPage()
    end
    local function Move(cell, dir)
        local singles, combos = Read(cell.class)
        local list = cell.kind == "combo" and combos or singles
        local j = cell.n + dir
        if not (list[cell.n] and list[j]) then return end
        list[cell.n], list[j] = list[j], list[cell.n]
        Write(cell.class, singles, combos, cell.rgn)
        Rebuild()
    end
    local function Remove(cell)
        local singles, combos = Read(cell.class)
        local list = cell.kind == "combo" and combos or singles
        if not list[cell.n] then return end
        table.remove(list, cell.n)
        Write(cell.class, singles, combos, cell.rgn)
        Rebuild()
    end
    -- A new debuff starts unchosen; a new combo pairs the class's top two.
    local function AddSingle(class)
        local singles, combos = Read(class)
        if #singles >= DC.MAX_SINGLES then return end
        singles[#singles + 1] = { spell = 0, color = CopyColor(DC.SINGLE_COLOR) }
        Write(class, singles, combos)
        debuffColorAdded = { kind = "single", class = class, n = #singles }
        Rebuild()
        debuffColorAdded = nil
    end
    local function ComboRoom(class)
        local singles, combos = Read(class)
        return #combos < DC.MAX_COMBOS and #Chosen(singles) >= 2
    end
    local function AddCombo(class)
        if not ComboRoom(class) then return end
        local singles, combos = Read(class)
        local picks = Chosen(singles)
        combos[#combos + 1] = { spells = { picks[1], picks[2] }, color = CopyColor(DC.COMBO_COLOR) }
        Write(class, singles, combos)
        debuffColorAdded = { kind = "combo", class = class, n = #combos }
        Rebuild()
        debuffColorAdded = nil
    end

    -- Debuff Coloring: a pure view over debuffColorsEnabled (off = None) and
    -- debuffColorsBorder (on = Color Border, else Color Nameplate). Color
    -- Border's cog (Extra Border Size) shows only over a Basic or Custom Solid
    -- border; a textured custom border is recolored as it is. Both checks
    -- follow the runtime's border reading (BorderSpec in the module).
    local function Mode()
        if Off() then return "none" end
        return Get("debuffColorsBorder") == true and "border" or "nameplate"
    end
    local function NoBorder()
        if EllesmereUI.BlizzStyle.Get("nameplates") then return true end
        if Get("customBorderEnabled") then
            if (Get("customBorderSize") or 0) <= 0 then return true end
            -- A textured border whose art no longer resolves (its media pack
            -- removed) draws nothing.
            local tex = Get("customBorderTexture")
            return tex ~= nil and tex ~= "" and tex ~= "solid"
                and not EllesmereUI.ResolveBorderTexture(tex)
        end
        return Get("showBorder") == false
    end
    local function StripBorder()
        if NoBorder() then return false end
        if Get("customBorderEnabled") then
            local tex = Get("customBorderTexture")
            return not tex or tex == "" or tex == "solid"
        end
        return true
    end
    local _, h, modeRow
    _, h = W:SectionHeader(parent, "DEBUFF BASED NAMEPLATE COLORING", y); y = y - h
    modeRow, h = W:DualRow(parent, y,
        { type="dropdown", text="Debuff Coloring",
          values={ none = "None", nameplate = "Color Nameplate", border = "Color Border" },
          order={ "none", "nameplate", "border" },
          disabledValues=function(key)
              if key == "border" and NoBorder() then return "This option requires a Border to be selected" end
              return false
          end,
          getValue=Mode,
          setValue=EllesmereUI.SectionToggleSetValue(function(v)
              ns.db.profile.debuffColorsEnabled = v ~= "none"
              if v ~= "none" then ns.db.profile.debuffColorsBorder = v == "border" end
              ns.DebuffColors_Refresh()
          end),
          tooltip="Colors enemy health bars, or their borders, while the chosen debuffs are on them." },
        { type="toggle", text="Only My Debuffs",
          getValue=function() return Get("debuffColorsPlayerOnly") ~= false end,
          setValue=function(v)
              ns.db.profile.debuffColorsPlayerOnly = v
              Apply()
          end,
          disabled=Off, disabledTooltip="Debuff Coloring",
          tooltip="Counts only the debuffs you applied." }); y = y - h

    -- Color Border's cog, built while it is picked (the dropdown rebuilds the
    -- page) and shown only over a border drawn as strips; a border change on
    -- the Display page reaches it through the page's refreshers.
    if Mode() == "border" and not EllesmereUI._prebuilding then
        local cog = EllesmereUI.BuildInlineCog(modeRow._leftRegion, {
            title = "Color Border",
            rows = {
                { type="slider", label="Extra Border Size", min=0, max=4, step=1,
                  tooltip="Thickens the border by this many pixels while it shows a debuff color.",
                  get=function() return Get("debuffColorsBorderExtra") or 0 end,
                  set=function(v)
                      ns.db.profile.debuffColorsBorderExtra = v
                      Apply()
                  end },
            },
        })
        local function ShowCog() cog:SetShown(StripBorder()) end
        ShowCog()
        EllesmereUI.RegisterWidgetRefresh(ShowCog)
    end

    -- Section gate: the rows below exist only while Debuff Coloring is on (the
    -- dropdown's SectionToggleSetValue rebuilds the page).
    if Off() then
        _, h = W:Spacer(parent, y, 20); y = y - h
        return y
    end

    -- Up/down arrows beside a row's name (white, the accent while hovered;
    -- a darker white when the accent itself is white). The first entry
    -- cannot move up nor the last down.
    local UP_ICON = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-arrow-up3.png"
    local DOWN_ICON = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-arrow-down3.png"
    local function HoverColor()
        local ac = EllesmereUI.ELLESMERE_GREEN
        if ac.r > 0.9 and ac.g > 0.9 and ac.b > 0.9 then return 0.72, 0.72, 0.72 end
        return ac.r, ac.g, ac.b
    end
    local function Arrow(rgn, texture, tip, enabled, onClick)
        local btn = CreateFrame("Button", nil, rgn)
        btn:SetFrameLevel(rgn:GetFrameLevel() + 12)
        btn:SetSize(16, 20)
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetTexture(texture)
        icon:SetSize(16, 16)
        icon:SetPoint("CENTER")
        if not enabled then
            icon:SetAlpha(0.2)
            btn:EnableMouse(false)
            return btn
        end
        btn:SetScript("OnEnter", function()
            icon:SetVertexColor(HoverColor())
            EllesmereUI.ShowWidgetTooltip(btn, tip)
        end)
        btn:SetScript("OnLeave", function()
            icon:SetVertexColor(1, 1, 1)
            EllesmereUI.HideWidgetTooltip()
        end)
        btn:SetScript("OnClick", function()
            EllesmereUI.HideWidgetTooltip()
            onClick()
        end)
        return btn
    end
    local function ReorderArrows(rgn, cell)
        local label = rgn._label
        local up = Arrow(rgn, UP_ICON, "Move Up", cell.n > 1, function() Move(cell, -1) end)
        up:SetPoint("LEFT", label, "LEFT", math.ceil(label:GetStringWidth()) + 6, -1)
        local down = Arrow(rgn, DOWN_ICON, "Move Down", cell.n < cell.count, function() Move(cell, 1) end)
        down:SetPoint("LEFT", up, "RIGHT", 0, 0)
    end

    local SINGLE_TIP = "Higher in the list wins when several are up."
    local COMBO_TIP = "Combos win over single debuffs; higher in the list wins."

    -- A debuff: its spell menu (Remove, Custom Spell..., the class's presets,
    -- then its custom spells) with its color inline. The custom tail follows
    -- edits on every row of the class (cell.syncCustoms, run by the row's
    -- refresher); Custom Spell... is an action: it adds a spell and keeps its label.
    local function SingleCfg(cell)
        local own = Presets(cell.class)
        local values = { _noLoc = true, none = EllesmereUI.L("None"),
            remove = { text = EllesmereUI.L("Remove"), action = function() Remove(cell) end } }
        for key, s in pairs(own.byKey) do values[key] = s.name end
        local order = {}
        for i, key in ipairs(own.order) do order[i] = key end
        local base = #order
        -- True when the menu's items changed (it must rebuild).
        function cell.syncCustoms()
            local customs, changed = Customs(cell.class), false
            for i, key in ipairs(customs) do
                if order[base + i] ~= key then
                    order[base + i] = key
                    changed = true
                end
                local name = SpellName(tonumber(key), "Spell " .. key)
                if values[key] ~= name then
                    values[key] = name
                    changed = true
                end
            end
            for i = #order, base + #customs + 1, -1 do
                order[i] = nil
                changed = true
            end
            return changed
        end
        cell.syncCustoms()
        values.custom = { text = EllesmereUI.L("Custom Spell..."), action = function()
            EllesmereUI:ShowInputPopup({
                title=Label(cell), confirmText="Add", cancelText="Cancel",
                message="Enter the debuff's spell ID.",
                placeholder="Spell ID", maxLetters=10,
                onConfirm=function(text)
                    local value = DC.SpellID((text or ""):match("^%s*(%d+)%s*$"))
                    if not (value and C_Spell and C_Spell.GetSpellInfo(value)) then
                        EllesmereUI.PrintError(EllesmereUI.L("Enter a valid debuff spell ID."))
                        return
                    end
                    if HeldElsewhere(cell, value) then
                        EllesmereUI.PrintError(EllesmereUI.L("Already in use. Use the arrows to reorder."))
                        return
                    end
                    SetSpell(cell, value, cell.rgn)
                end,
            })
        end }
        values._menuOpts = {
            searchable=true, itemHeight=28, maxHeight=280, iconNativeColor=true,
            icon=function(key)
                local id = tonumber(key)
                return SpellIcon(id and id > 0 and id), .08, .92, .08, .92
            end,
            onItemHover=function(key, item)
                local spell = own.byKey[key]
                if spell then
                    EllesmereUI.ShowWidgetTooltip(item, spell.class .. " | " .. EllesmereUI.Lf("Spell ID: %1$s", spell.id))
                elseif tonumber(key) then
                    EllesmereUI.ShowWidgetTooltip(item, EllesmereUI.Lf("Spell ID: %1$s", key))
                end
            end,
            onItemLeave=function() EllesmereUI.HideWidgetTooltip() end,
        }
        return { type="dropdown", text=Label(cell), values=values, order=order,
            getValue=function()
                local id = SpellOf(cell)
                if id == 0 then return "none" end
                return tostring(id)
            end,
            setValue=function(v)
                local id = DC.SpellID(v)
                if id then SetSpell(cell, id) end
            end,
            -- Never the row's own spell (a list saved with a duplicate keeps
            -- its label lit).
            disabledValues=function(key)
                local id = tonumber(key)
                if id and id ~= SpellOf(cell) and HeldElsewhere(cell, id) then return IN_USE end
                return false
            end,
            tooltip=SINGLE_TIP }
    end
    local function SingleChrome(rgn, cell)
        ReorderArrows(rgn, cell)
        -- The menu rebuilds only when its custom spells change.
        local function Sync()
            local ctrl = rgn._control
            if cell.syncCustoms() and ctrl._invalidateMenu then ctrl._invalidateMenu() end
            if ctrl._refreshLabel then ctrl._refreshLabel() end
        end
        Sync()
        EllesmereUI.RegisterWidgetRefresh(Sync)
        EllesmereUI.BuildInlineSwatches(rgn, { {
            tooltip = "Debuff Color",
            getValue = function()
                local e = Read(cell.class)[cell.n]
                local c = e and e.color or DC.SINGLE_COLOR
                return c.r, c.g, c.b
            end,
            setValue = function(r, g, b)
                local singles, combos = Read(cell.class)
                local e = singles[cell.n]
                if not e then return end
                e.color = { r = r, g = g, b = b }
                Write(cell.class, singles, combos)
            end,
            disabled = function() return SpellOf(cell) == 0 end,
            disabledTooltip = "This option requires a debuff to be selected",
        } })
    end

    -- A combo: a checkbox list of its class's debuffs (two to four checked),
    -- Remove above them, its color inline. The row's own dropdown, hidden
    -- under the list, reads and writes the combo's spells.
    local function SetComboSpells(cell, spells, rgn)
        local singles, combos = Read(cell.class)
        local k = combos[cell.n]
        if not k then return end
        k.spells = spells
        Write(cell.class, singles, combos, rgn)
    end
    local COMBO_VALUES = setmetatable({}, { __index = function(_, key)
        if type(key) ~= "string" or key:sub(1, 1) == "_" then return nil end
        local names = {}
        for id in key:gmatch("%d+") do names[#names + 1] = SpellName(tonumber(id), "Spell " .. id) end
        return #names > 0 and table.concat(names, " + ") or nil
    end })
    local function ComboCfg(cell)
        return { type="dropdown", text=Label(cell), values=COMBO_VALUES, order={},
            getValue=function() return table.concat(ComboSpells(cell), "+") end,
            setValue=function(v)
                local spells = {}
                for id in tostring(v):gmatch("%d+") do
                    id = DC.SpellID(id)
                    if id and #spells < DC.MAX_COMBO_SPELLS then spells[#spells + 1] = id end
                end
                SetComboSpells(cell, spells)
            end,
            tooltip=COMBO_TIP }
    end
    local function ComboChrome(rgn, cell)
        ReorderArrows(rgn, cell)
        local function Has(id)
            for _, s in ipairs(ComboSpells(cell)) do
                if s == id then return true end
            end
            return false
        end
        local function Valid()
            local seen, n = {}, 0
            for _, s in ipairs(ComboSpells(cell)) do
                if not seen[s] then seen[s] = true; n = n + 1 end
            end
            return n >= 2
        end
        -- Its class's chosen debuffs, then any spell only the combo holds.
        local function Items()
            local items = { { key = "_remove", label = "Remove", isTopAction = true,
                onClick = function() Remove(cell) end } }
            local listed = {}
            local function Add(id)
                if listed[id] then return end
                listed[id] = true
                items[#items + 1] = { key = tostring(id), label = SpellName(id, "Spell " .. id),
                    icon = SpellIcon(id),
                    lockedFn = function() return not Has(id) and #ComboSpells(cell) >= DC.MAX_COMBO_SPELLS end,
                    lockedTooltip = "A combo holds up to four debuffs." }
            end
            for _, id in ipairs(Chosen((Read(cell.class)))) do Add(id) end
            for _, id in ipairs(ComboSpells(cell)) do Add(id) end
            return items
        end
        local ctrl = rgn._control
        local ddW = ctrl and ctrl:GetWidth() or 0
        if ddW < 50 then ddW = 170 end
        local pulse
        local cbDD, cbRefresh = EllesmereUI.BuildVisOptsCBDropdown(rgn, ddW, rgn:GetFrameLevel() + 2,
            Items,
            function(key) return Has(tonumber(key)) end,
            function(key, on)
                local id = tonumber(key)
                local spells = {}
                for _, s in ipairs(ComboSpells(cell)) do
                    if s ~= id then spells[#spells + 1] = s end
                end
                if on and #spells < DC.MAX_COMBO_SPELLS then spells[#spells + 1] = id end
                SetComboSpells(cell, spells)
            end,
            nil, 8, false, false,
            function() if pulse then pulse() end end,
            { notifyWrites = true, noAllLabel = true, separatorFn = function() return " + " end })
        local p1, rel, p2, ax, ay
        if ctrl then
            p1, rel, p2, ax, ay = ctrl:GetPoint(1)
            ctrl:Hide()
        end
        if p1 then cbDD:SetPoint(p1, rel, p2, ax, ay)
        else PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0) end
        rgn._control = cbDD
        rgn._lastInline = nil
        EllesmereUI.RegisterWidgetRefresh(cbRefresh)
        pulse = EllesmereUI.AttachEmptyFilterWarn(rgn, cbDD, EllesmereUI.L("Pick at least two debuffs"), Valid)
        EllesmereUI.BuildInlineSwatches(rgn, { {
            tooltip = "Combo Color",
            getValue = function()
                local _, combos = Read(cell.class)
                local k = combos[cell.n]
                local c = k and k.color or DC.COMBO_COLOR
                return c.r, c.g, c.b
            end,
            setValue = function(r, g, b)
                local singles, combos = Read(cell.class)
                local k = combos[cell.n]
                if not k then return end
                k.color = { r = r, g = g, b = b }
                Write(cell.class, singles, combos)
            end,
        } })
    end

    -- Add Debuff / Add Combo open the list of classes (the standard dropdown
    -- menu, as wide as the button, built on first open; a class with no room
    -- greyed).
    local ADD_W = 220
    local NO_PAINT = { SetColor = function() end, SetColorTexture = function() end }
    local function AddPicker(rgn, pick, room)
        local btn = rgn._control
        -- Its own hover look, kept past the menu wiring (which takes the scripts).
        local enter, leave = btn:GetScript("OnEnter"), btn:GetScript("OnLeave")
        local proxyLbl = EllesmereUI.MakeFont(btn, 12, nil, 1, 1, 1)
        proxyLbl:Hide()
        local menu
        local function EnsureMenu()
            if menu then return menu end
            local refresh
            menu, _, refresh = EllesmereUI.BuildDropdownMenu(btn, ADD_W, ORDER, CLASS_VALUES,
                function() return nil end, pick, proxyLbl, "regular",
                function(class) if not room(class) then return true end end)
            EllesmereUI.WireDropdownScripts(btn, proxyLbl, NO_PAINT, NO_PAINT, menu, refresh, EllesmereUI.RD_DD_COLOURS, true)
            btn:HookScript("OnEnter", enter)
            btn:HookScript("OnLeave", function(self) if not menu:IsShown() then leave(self) end end)
            menu:HookScript("OnHide", function() if not btn:IsMouseOver() then leave(btn) end end)
            return menu
        end
        btn:HookScript("OnHide", function() if menu then menu:Hide() end end)
        return function()
            local m = EnsureMenu()
            if m:IsShown() then m:Hide() else m:Show() end
        end
    end
    local function SingleRoom(class) return #Read(class) < DC.MAX_SINGLES end
    local function AnyRoom(room)
        for _, class in ipairs(ORDER) do
            if room(class) then return true end
        end
        return false
    end
    local openSingle, openCombo
    local ADD_SINGLE = { type="button", text="+ Add Debuff", width=ADD_W,
        onClick=function() if openSingle then openSingle() end end,
        disabled=function() return not AnyRoom(SingleRoom) end,
        disabledTooltip="Every class has ten debuffs.", rawTooltip=true }
    local ADD_COMBO = { type="button", text="+ Add Combo", width=ADD_W,
        onClick=function() if openCombo then openCombo() end end,
        disabled=function() return not AnyRoom(ComboRoom) end,
        disabledTooltip="This option requires two debuffs for the same class" }

    -- The debuffs, Add Debuff, the combos, Add Combo: two to a row.
    local cells = {}
    for _, class in ipairs(ORDER) do
        local singles = Read(class)
        for n = 1, #singles do
            cells[#cells + 1] = { kind = "single", class = class, n = n, count = #singles }
        end
    end
    cells[#cells + 1] = ADD_SINGLE
    for _, class in ipairs(ORDER) do
        local _, combos = Read(class)
        for n = 1, #combos do
            cells[#cells + 1] = { kind = "combo", class = class, n = n, count = #combos }
        end
    end
    cells[#cells + 1] = ADD_COMBO
    local function CellCfg(c)
        if c == nil then return EllesmereUI.BlankRowCfg() end
        if c == ADD_SINGLE or c == ADD_COMBO then return c end
        return c.kind == "combo" and ComboCfg(c) or SingleCfg(c)
    end
    local function CellChrome(rgn, c)
        if EllesmereUI._prebuilding or c == nil then return end
        if c == ADD_SINGLE then
            openSingle = AddPicker(rgn, AddSingle, SingleRoom)
            return
        end
        if c == ADD_COMBO then
            openCombo = AddPicker(rgn, AddCombo, ComboRoom)
            return
        end
        c.rgn = rgn
        if c.kind == "combo" then ComboChrome(rgn, c) else SingleChrome(rgn, c) end
        -- The entry Add just made: its own row takes the write.
        local a = debuffColorAdded
        if a and a.kind == c.kind and a.class == c.class and a.n == c.n then
            debuffColorAdded = nil
            EllesmereUI._NotifySettingWrite(rgn)
        end
    end
    for k = 1, #cells, 2 do
        local l, r = cells[k], cells[k + 1]
        local row
        row, h = W:DualRow(parent, y, CellCfg(l), CellCfg(r)); y = y - h
        CellChrome(row._leftRegion, l)
        CellChrome(row._rightRegion, r)
    end
    _, h = W:Spacer(parent, y, 20); y = y - h
    return y
end

-- Mini preview bar builder for color swatches. type: "health"/"cast"/"castLocked". colorKey: DB key for the bar color (read live). parentRow: frame to attach to. anchorFrame: optional override anchor (e.g. DualRow half-region).
local function MakeColorPreviewBar(parentRow, colorType, colorKey, anchorFrame)
    local env = ns._NPO_OptEnv
    local DB, DBVal, defaults, GetFocusLetterAnchor = env.DB, env.DBVal, env.defaults, env.GetFocusLetterAnchor
    local GetNPOptOutline, NextCastFill, NextCastIcon, PP = env.GetNPOptOutline, env.NextCastFill, env.NextCastIcon, env.PP
    local SetPVFont = env.SetPVFont
    local MEDIA = "Interface\\AddOns\\EllesmereUINameplates\\Media\\"
    local isHalf = anchorFrame and true or false
    local BAR_W = isHalf and 161 or 180
    local BAR_H = 20
    local SWATCH_SZ = 24
    local SWATCH_GAP = isHalf and 27 or 52
    local fontPath = (EllesmereUI.GetFontPath("nameplates")) or DBVal("font")
    local anchor = anchorFrame or parentRow

    local container = CreateFrame("Frame", nil, parentRow)
    PP.Size(container, BAR_W + 2, BAR_H + 2)  -- +2 for border
    -- Position: to the left of the swatch (swatch is at RIGHT -SIDE_PAD, 24px wide)
    PP.Point(container, "RIGHT", anchor, "RIGHT", -(20 + SWATCH_SZ + SWATCH_GAP), 0)
    container:SetFrameLevel(parentRow:GetFrameLevel() + 2)

    -- Simple 1px solid border using the user's nameplate border color; two-point anchoring for pixel-perfect rendering inside the scroll frame.
    local function MakePreviewBorder(parent)
        local bc = (DB() and DB().borderColor) or defaults.borderColor
        local edges = {}
        local function mkE()
            local t = parent:CreateTexture(nil, "OVERLAY", nil, 7)
            t:SetColorTexture(bc.r, bc.g, bc.b, 1)
            edges[#edges + 1] = t
            return t
        end
        local t = mkE(); t:SetPoint("TOPLEFT"); t:SetPoint("TOPRIGHT"); t:SetHeight(1)
        local b = mkE(); b:SetPoint("BOTTOMLEFT"); b:SetPoint("BOTTOMRIGHT"); b:SetHeight(1)
        local l = mkE(); l:SetPoint("TOPLEFT", t, "BOTTOMLEFT"); l:SetPoint("BOTTOMLEFT", b, "TOPLEFT"); l:SetWidth(1)
        local r = mkE(); r:SetPoint("TOPRIGHT", t, "BOTTOMRIGHT"); r:SetPoint("BOTTOMRIGHT", b, "TOPRIGHT"); r:SetWidth(1)
        return edges
    end

    if colorType == "health" then
        -- Health bar preview: random fill 60-75%, colored by the swatch color
        local FAKE_MAX_HP = 10000
        local healthPct = math.floor(60 + math.random() * 15)
        local healthVal = math.floor(FAKE_MAX_HP * healthPct / 100)

        local health = CreateFrame("StatusBar", nil, container)
        health:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        health:SetMinMaxValues(0, 100)
        health:SetValue(healthPct)
        health:SetAllPoints()

        local bg = health:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.20, 0.20, 0.20, 1.0)

        -- 1px solid border on a dedicated frame ABOVE the health StatusBar (child frames cover parent textures); parented to container, not health, so it stays full opacity when the bar dims via SetDisabled.
        local brdFrame = CreateFrame("Frame", nil, container)
        brdFrame:SetAllPoints()
        brdFrame:SetFrameLevel(health:GetFrameLevel() + 2)
        local brdEdges = MakePreviewBorder(brdFrame)
        container._brdEdges = brdEdges
        container._health = health  -- exposed for proxy color override / dimming

        -- Always create both FontStrings (shown/hidden dynamically), parented to a text frame ABOVE the overlay clips so focus texture never covers the health numbers.
        local textFrame = CreateFrame("Frame", nil, health)
        textFrame:SetAllPoints()
        textFrame:SetFrameLevel(health:GetFrameLevel() + 3)

        local pctFS = textFrame:CreateFontString(nil, "OVERLAY")
        local initHpSz = 10
        SetPVFont(pctFS, fontPath, initHpSz, GetNPOptOutline())
        pctFS:Hide()

        local numFS = textFrame:CreateFontString(nil, "OVERLAY")
        SetPVFont(numFS, fontPath, initHpSz, GetNPOptOutline())
        numFS:Hide()

        -- Full refresh: re-reads DB settings, repositions, updates text & values
        local function RefreshHealthText()
            local hpFS = 10
            -- Use the largest text slot size (capped at 13 for mini bars)
            for _, sk in ipairs({"textSlotRight", "textSlotLeft", "textSlotCenter"}) do
                local el = DBVal(sk) or defaults[sk]
                if el and el ~= "none" and not ns.IsNameElement(el) then
                    hpFS = math.min(DBVal(sk .. "Size") or defaults[sk .. "Size"] or 10, 13)
                    break
                end
            end
            local curFont = (EllesmereUI.GetFontPath("nameplates")) or DBVal("font")
            local curOutline = GetNPOptOutline()

            -- Hide both FontStrings first
            SetPVFont(pctFS, curFont, hpFS, curOutline)
            pctFS:ClearAllPoints()
            pctFS:Hide()
            SetPVFont(numFS, curFont, hpFS, curOutline)
            numFS:ClearAllPoints()
            numFS:Hide()

            -- Bar slots: show health text based on slot assignments
            local barSlots = {
                { key = "textSlotRight",  anchor = "RIGHT",  xOff = -2 },
                { key = "textSlotLeft",   anchor = "LEFT",   xOff = 2 },
                { key = "textSlotCenter", anchor = "CENTER", xOff = 0 },
            }
            for _, slot in ipairs(barSlots) do
                local element = DBVal(slot.key) or defaults[slot.key]
                local sc = (DB() and DB()[slot.key .. "Color"]) or defaults[slot.key .. "Color"]
                -- This bar stands for a hostile NPC at the player's level: Hostility /
                -- Class shows the Hostile name colour, Level Difficulty that level's
                -- colour, as the plate would.
                local mode = ns.NP_SlotColorMode(slot.key, DB())
                if mode == "class" then
                    sc = (DB() and DB().enemyNameHostileColor) or defaults.hostile
                elseif mode == "level" then
                    local r, g, b = ns.NP_UnitLevelColor("player")
                    if r then sc = { r = r, g = g, b = b } end
                end
                if element == "healthPercent" or element == "healthPercentNoSign" then
                    pctFS:SetTextColor(sc.r, sc.g, sc.b, 1)
                    pctFS:SetText(element == "healthPercentNoSign" and tostring(healthPct) or (healthPct .. "%"))
                    pctFS:SetPoint(slot.anchor, health, slot.anchor, slot.xOff, 0)
                    pctFS:Show()
                elseif element == "healthNumber" then
                    numFS:SetTextColor(sc.r, sc.g, sc.b, 1)
                    local valStr = tostring(healthVal):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
                    numFS:SetText(valStr)
                    numFS:SetPoint(slot.anchor, health, slot.anchor, slot.xOff, 0)
                    numFS:Show()
                elseif ns.IsComboHealthText(element) then
                    local valStr = tostring(healthVal):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
                    pctFS:SetTextColor(sc.r, sc.g, sc.b, 1)
                    ns.SetCombinedHealthText(pctFS, element, healthPct .. "%", valStr)
                    pctFS:SetPoint(slot.anchor, health, slot.anchor, slot.xOff, 0)
                    pctFS:Show()
                end
            end
        end

        -- Run initial layout
        RefreshHealthText()

        -- Color the bar from the swatch's DB value
        local c = (DB() and DB()[colorKey]) or defaults[colorKey]
        health:SetStatusBarColor(c.r, c.g, c.b, 1)

        -- Focus overlay on the focus preview bar: clip frames for non-overlapping fixed-size textures
        local overlayFillClip, overlayFillTex, overlayBgClip, overlayBgTex

        -- Helper: create a clipped overlay frame+texture pair for the focus bar
        local function MakeOverlayClip(tlAnchor, tlRelPoint, brAnchor, brRelPoint, sublayer)
            local clip = CreateFrame("Frame", nil, health)
            clip:SetClipsChildren(true)
            -- Full bar height (top/bottom from the bar) with horizontal edges from the passed fill/health anchors, matching the live nameplate overlay (same full-height stripes).
            clip:SetPoint("TOP", health, "TOP", 0, 0)
            clip:SetPoint("BOTTOM", health, "BOTTOM", 0, 0)
            clip:SetPoint("LEFT", tlAnchor, tlRelPoint, 0, 0)
            clip:SetPoint("RIGHT", brAnchor, brRelPoint, 0, 0)
            clip:SetFrameLevel(health:GetFrameLevel() + 1)
            local tex = clip:CreateTexture(nil, "ARTWORK", nil, sublayer)
            tex:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
            tex:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 0, 0)
            tex:SetWidth(BAR_W)
            return clip, tex
        end

        local _overlayTexKey   = (colorKey == "target") and "targetOverlayTexture"  or "focusOverlayTexture"
        local _overlayAlphaKey = (colorKey == "target") and "targetOverlayAlpha"   or "focusOverlayAlpha"
        local _overlayColorKey = (colorKey == "target") and "targetOverlayColor"   or "focusOverlayColor"
        local _overlayFullBgKey = (colorKey == "target") and "targetOverlayFullBgAlpha" or "focusOverlayFullBgAlpha"
        -- Empty-portion (bg) opacity: full when "Full alpha on empty part of bar" is on, else dimmed to 30% (matches live plates).
        local function _overlayBgAlpha(oAlpha)
            local full = DBVal(_overlayFullBgKey)
            if full == nil then full = defaults[_overlayFullBgKey] end
            if full then return oAlpha end
            return oAlpha * 0.3
        end
        if colorKey == "focus" or colorKey == "target" then
            local tex = DBVal(_overlayTexKey) or defaults[_overlayTexKey]
            if tex ~= "none" then
                local fillRef = health:GetStatusBarTexture()
                local oAlpha = DBVal(_overlayAlphaKey) or defaults[_overlayAlphaKey]
                local oc = (DB() and DB()[_overlayColorKey]) or defaults[_overlayColorKey]
                overlayFillClip, overlayFillTex = MakeOverlayClip(fillRef, "TOPLEFT", fillRef, "BOTTOMRIGHT", 2)
                overlayFillTex:SetTexture(ns.ResolveOverlayTexPath and ns.ResolveOverlayTexPath(tex) or (MEDIA .. tex .. ".png"))
                overlayFillTex:SetAlpha(oAlpha)
                overlayFillTex:SetVertexColor(oc.r, oc.g, oc.b)
                overlayBgClip, overlayBgTex = MakeOverlayClip(fillRef, "TOPRIGHT", health, "BOTTOMRIGHT", 1)
                overlayBgTex:SetTexture(ns.ResolveOverlayTexPath and ns.ResolveOverlayTexPath(tex) or (MEDIA .. tex .. ".png"))
                overlayBgTex:SetAlpha(_overlayBgAlpha(oAlpha))
                overlayBgTex:SetVertexColor(oc.r, oc.g, oc.b)
            end
        end

        local focusLetterFS
        local function RefreshFocusLetter()
            if colorKey ~= "focus" then return end
            if DBVal("focusLetterEnabled") ~= true then
                if focusLetterFS then focusLetterFS:Hide() end
                return
            end
            if not focusLetterFS then
                focusLetterFS = textFrame:CreateFontString(nil, "OVERLAY")
                focusLetterFS:SetJustifyH("CENTER")
                focusLetterFS:SetJustifyV("MIDDLE")
            end
            local size = DBVal("focusLetterSize") or defaults.focusLetterSize
            local anchor = GetFocusLetterAnchor()
            local x = DBVal("focusLetterX") or defaults.focusLetterX
            local y = DBVal("focusLetterY") or defaults.focusLetterY
            local curFont = (EllesmereUI.GetFontPath("nameplates")) or DBVal("font")
            SetPVFont(focusLetterFS, curFont, size, GetNPOptOutline())
            focusLetterFS:SetText("F")
            focusLetterFS:ClearAllPoints()
            focusLetterFS:SetPoint(anchor, health, anchor, x, y)
            focusLetterFS:SetTextColor(1, 1, 1, 1)
            focusLetterFS:Show()
        end
        RefreshFocusLetter()

        -- Live update hook: re-color when swatch changes
        container.UpdateColor = function()
            local cc = (DB() and DB()[colorKey]) or defaults[colorKey]
            health:SetStatusBarColor(cc.r, cc.g, cc.b, 1)
        end
        -- Live update hook: refresh overlay texture from DB
        container.UpdateOverlay = function()
            if colorKey ~= "focus" and colorKey ~= "target" then return end
            local tex = DBVal(_overlayTexKey) or defaults[_overlayTexKey]
            if tex == "none" then
                if overlayFillClip then overlayFillClip:Hide() end
                if overlayBgClip then overlayBgClip:Hide() end
            else
                local fillRef = health:GetStatusBarTexture()
                local oAlpha = DBVal(_overlayAlphaKey) or defaults[_overlayAlphaKey]
                local oc = (DB() and DB()[_overlayColorKey]) or defaults[_overlayColorKey]
                if not overlayFillClip then
                    overlayFillClip, overlayFillTex = MakeOverlayClip(fillRef, "TOPLEFT", fillRef, "BOTTOMRIGHT", 2)
                end
                overlayFillTex:SetTexture(ns.ResolveOverlayTexPath and ns.ResolveOverlayTexPath(tex) or (MEDIA .. tex .. ".png"))
                overlayFillTex:SetAlpha(oAlpha)
                overlayFillTex:SetVertexColor(oc.r, oc.g, oc.b)
                overlayFillClip:Show()
                if not overlayBgClip then
                    overlayBgClip, overlayBgTex = MakeOverlayClip(fillRef, "TOPRIGHT", health, "BOTTOMRIGHT", 1)
                end
                overlayBgTex:SetTexture(ns.ResolveOverlayTexPath and ns.ResolveOverlayTexPath(tex) or (MEDIA .. tex .. ".png"))
                overlayBgTex:SetAlpha(_overlayBgAlpha(oAlpha))
                overlayBgTex:SetVertexColor(oc.r, oc.g, oc.b)
                overlayBgClip:Show()
            end
            RefreshFocusLetter()
        end
        container.Randomize = function()
            healthPct = math.floor(60 + math.random() * 15)
            healthVal = math.floor(FAKE_MAX_HP * healthPct / 100)
            health:SetValue(healthPct)
            RefreshHealthText()
        end
        -- Exposed so cache-restore / refresh-all can update text from current DB
        container.RefreshHealthText = RefreshHealthText
        container.RefreshBorderStyle = function() end  -- no style toggle needed for 1px solid
        container.RefreshBorderColor = function()
            local bc = (DB() and DB().borderColor) or defaults.borderColor
            for _, tex in ipairs(container._brdEdges) do
                tex:SetColorTexture(bc.r, bc.g, bc.b, 1)
            end
        end

    elseif colorType == "cast" or colorType == "castLocked" then
        PP.Size(container, BAR_W + 2, BAR_H + 2)

        local cast = CreateFrame("StatusBar", nil, container)
        cast:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        cast:SetMinMaxValues(0, 1)
        cast:SetValue(NextCastFill())
        cast:SetAllPoints()

        local castBG = cast:CreateTexture(nil, "BACKGROUND")
        castBG:SetAllPoints()
        castBG:SetColorTexture(0.20, 0.20, 0.20, 0.9)


        local spark = cast:CreateTexture(nil, "OVERLAY", nil, 1)
        spark:SetTexture(MEDIA .. "cast_spark.tga")
        spark:SetSize(8, BAR_H)
        spark:SetPoint("CENTER", cast:GetStatusBarTexture(), "RIGHT", 0, 0)
        spark:SetBlendMode("ADD")
        -- Show Spark (Cast Color cog): default on; explicit false hides it.
        spark:SetShown(DBVal("castBarSparkEnabled") ~= false)

        -- Cast icon frame (to the left) no border for Colors tab previews
        local iconFrame = CreateFrame("Frame", nil, cast)
        iconFrame:SetSize(BAR_H + 2, BAR_H + 2)
        iconFrame:SetPoint("RIGHT", cast, "LEFT", 0, 0)
        iconFrame:SetFrameLevel(cast:GetFrameLevel() + 1)
        local icon = iconFrame:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:SetTexture(NextCastIcon())

        -- Cast text
        local cns = math.min(DBVal("castNameSize") or defaults.castNameSize, 13)
        local cts = math.min(DBVal("castTargetSize") or defaults.castTargetSize, 13)
        local cnc = (DB() and DB().castNameColor) or defaults.castNameColor

        local dbRef = DB()
        local colShowTimer = defaults.showCastTimer
        if dbRef and dbRef.showCastTimer ~= nil then colShowTimer = dbRef.showCastTimer end
        local colCtmSz = math.min((dbRef and dbRef.castTimerSize) or defaults.castTimerSize, 13)
        local colCtmC = (dbRef and dbRef.castTimerColor) or defaults.castTimerColor
        local colNameSide   = (dbRef and dbRef.castNameSide)   or defaults.castNameSide
        local colTargetSide = (dbRef and dbRef.castTargetSide) or defaults.castTargetSide
        local colTimerSide  = (dbRef and dbRef.castTimerSide)  or defaults.castTimerSide
        local colCombine = dbRef and dbRef.castCombineNameTarget == true
        local colTimerW = colCtmSz * 2.2
        -- Per-element cast text truncation (% of bar width + wrap), mirroring runtime.
        local colNameW = BAR_W * ((dbRef and dbRef.castNameWidthPct) or defaults.castNameWidthPct) / 100
        local colTgtW  = BAR_W * ((dbRef and dbRef.castTargetWidthPct) or defaults.castTargetWidthPct) / 100
        local colNameWrap = (dbRef and dbRef.castNameWrap) == true
        local colTgtWrap  = (dbRef and dbRef.castTargetWrap) == true

        -- Spell name
        local nameFS = cast:CreateFontString(nil, "OVERLAY")
        SetPVFont(nameFS, fontPath, cns, GetNPOptOutline())
        nameFS:SetWordWrap(colNameWrap)
        nameFS:SetMaxLines(colNameWrap and 2 or 1)
        nameFS:SetText(EllesmereUI.L("Spell Name"))
        nameFS:SetTextColor(cnc.r, cnc.g, cnc.b, 1)
        if colNameSide == "none" then
            nameFS:Hide()
        else
            local pt, xb, jh = ns.GetCastTextAnchor(colNameSide, colShowTimer and colTimerSide == colNameSide, colTimerW, false)
            nameFS:SetWidth(colCombine and (BAR_W * 0.80) or colNameW)
            nameFS:SetJustifyH(jh)
            nameFS:SetPoint(pt, cast, pt, xb, 0)
        end

        -- Cast timer (side only "left"/"right"; visibility via showCastTimer)
        local timerFS = cast:CreateFontString(nil, "OVERLAY")
        SetPVFont(timerFS, fontPath, colCtmSz, GetNPOptOutline())
        timerFS:SetWordWrap(false)
        timerFS:SetMaxLines(1)
        timerFS:SetTextColor(colCtmC.r, colCtmC.g, colCtmC.b, 1)
        timerFS:SetText("2.3")
        if colShowTimer then
            local tpt, txb, tjh = ns.GetCastTextAnchor(colTimerSide, false, colTimerW, true)
            timerFS:SetWidth(colTimerW)
            timerFS:SetJustifyH(tjh)
            timerFS:SetPoint(tpt, cast, tpt, txb, 0)
        else
            timerFS:Hide()
        end

        -- Spell target
        local targetFS = cast:CreateFontString(nil, "OVERLAY")
        SetPVFont(targetFS, fontPath, cts, GetNPOptOutline())
        targetFS:SetWordWrap(colTgtWrap)
        targetFS:SetNonSpaceWrap(false)
        targetFS:SetMaxLines(colTgtWrap and 2 or 1)
        local colTargetText = isHalf and (UnitName("player") or EllesmereUI.L("Target")) or (UnitName("player") or EllesmereUI.L("Spell Target"))
        targetFS:SetText(colTargetText)
        local useClassColor = defaults.castTargetClassColor
        if dbRef and dbRef.castTargetClassColor ~= nil then useClassColor = dbRef.castTargetClassColor end
        local colTargetHex
        if useClassColor then
            local _, pClass = UnitClass("player")
            local c = pClass and RAID_CLASS_COLORS and RAID_CLASS_COLORS[pClass]
            if c then
                targetFS:SetTextColor(c.r, c.g, c.b, 1)
                colTargetHex = (c.GenerateHexColor and c:GenerateHexColor()) or c.colorStr or "ffffffff"
            else
                targetFS:SetTextColor(1, 1, 1, 1)
                colTargetHex = "ffffffff"
            end
        else
            local ctc = (dbRef and dbRef.castTargetColor) or defaults.castTargetColor
            targetFS:SetTextColor(ctc.r, ctc.g, ctc.b, 1)
            colTargetHex = string.format("ff%02x%02x%02x",
                math.floor(ctc.r * 255 + 0.5), math.floor(ctc.g * 255 + 0.5), math.floor(ctc.b * 255 + 0.5))
        end
        if colCombine then
            nameFS:SetFormattedText("%s - |c" .. colTargetHex .. "%s|r",
                EllesmereUI.L("Spell Name"), colTargetText)
        end
        if colCombine or colTargetSide == "none" then
            targetFS:Hide()
        else
            local pt, xb, jh = ns.GetCastTextAnchor(colTargetSide, colShowTimer and colTimerSide == colTargetSide, colTimerW, false)
            targetFS:SetWidth(colTgtW)
            targetFS:SetJustifyH(jh)
            targetFS:SetPoint(pt, cast, pt, xb, 0)
        end

        -- Shield for uninterruptible
        if colorType == "castLocked" then
            local shieldH = BAR_H * 0.75
            local shieldW = shieldH * (29 / 35)
            local shieldFrame = CreateFrame("Frame", nil, cast)
            shieldFrame:SetSize(shieldW, shieldH)
            shieldFrame:SetPoint("CENTER", cast, "LEFT", 0, 0)
            shieldFrame:SetFrameLevel(cast:GetFrameLevel() + 10)
            local shield = shieldFrame:CreateTexture(nil, "OVERLAY")
            shield:SetAllPoints()
            shield:SetTexture(MEDIA .. "shield.png")
        end

        -- Color the bar
        local c = (DB() and DB()[colorKey]) or defaults[colorKey]
        cast:SetStatusBarColor(c.r, c.g, c.b, 1)

        -- Shift container left to account for cast icon hanging outside
        container:ClearAllPoints()
        PP.Point(container, "RIGHT", anchor, "RIGHT", -(20 + SWATCH_SZ + SWATCH_GAP), 0)

        container.UpdateColor = function()
            local cc = (DB() and DB()[colorKey]) or defaults[colorKey]
            cast:SetStatusBarColor(cc.r, cc.g, cc.b, 1)
        end
        container.Randomize = function()
            cast:SetValue(NextCastFill())
            icon:SetTexture(NextCastIcon())
        end
        container.RefreshBorderStyle = function() end
        container.RefreshBorderColor = function() end
    end

    return container
end

local function BuildColorsPage(pageName, parent, yOffset)
    local env = ns._NPO_OptEnv
    local _colorPagePreviews, DB, DBColor, DBVal = env._colorPagePreviews, env.DB, env.DBColor, env.DBVal
    local defaults, optState, pairs, PP = env.defaults, env.optState, env.pairs, env.PP
    local RefreshAllPlates, SECTION_ENEMY, SECTION_THREAT, THREAT_PCT_POSITION_ORDER = env.RefreshAllPlates, env.SECTION_ENEMY, env.SECTION_THREAT, env.THREAT_PCT_POSITION_ORDER
    local THREAT_PCT_POSITIONS = env.THREAT_PCT_POSITIONS
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h

    -- No content header on Colors tab (presets are inline in scroll area)
    EllesmereUI:ClearContentHeader()

    -- Enable per-row center divider for the dual-column layout (same as Display tab)
    parent._showRowDivider = true

    -- Track all mini previews for border style refresh
    _G._EUI_ColorPreviews = {}

    -- LazyColorPreviewBar and _colorPagePreviews live at init scope (shared between Display and Colors pages).

    -----------------------------------------------------------------------
    --  ENEMY COLORS
    -----------------------------------------------------------------------
    _, h = W:SectionHeader(parent, SECTION_ENEMY, y);  y = y - h

    -- Modify Out of Combat is a view over darkenEnemiesOOC + darkenOOCRecolor (the
    -- runtime ignores the recolor flag while darkening is off): No Change = off,
    -- Darken = on, Change Color = on with the recolor. A pick writes only the keys
    -- whose value it changes.
    local function OOCOn()
        local db = DB()
        if db and db.darkenEnemiesOOC ~= nil then return db.darkenEnemiesOOC end
        return defaults.darkenEnemiesOOC
    end
    local function OOCRecolorOn()
        local db = DB()
        local v = db and db.darkenOOCRecolor
        if v == nil then v = defaults.darkenOOCRecolor end
        return v
    end
    local function OOCMode()
        if not OOCOn() then return "none" end
        return OOCRecolorOn() and "color" or "darken"
    end

    -- Enemy Types | Modify Out of Combat
    local enemyTypesRow
    enemyTypesRow, h = W:DualRow(parent, y,
        { type="multiSwatch", text="Enemy Types",
          swatches = {
            { tooltip = "Enemies",
              getValue = function() return DBColor("enemyInCombat") end,
              setValue = function(r, g, b)
                DB().enemyInCombat = { r = r, g = g, b = b }
                RefreshAllPlates()
              end },
            { tooltip = "Spell Casters",
              getValue = function() return DBColor("caster") end,
              setValue = function(r, g, b)
                DB().caster = { r = r, g = g, b = b }
                RefreshAllPlates()
              end },
            { tooltip = "Mini-Bosses",
              getValue = function() return DBColor("miniboss") end,
              setValue = function(r, g, b)
                DB().miniboss = { r = r, g = g, b = b }
                RefreshAllPlates()
              end },
            { tooltip = "Bosses",
              getValue = function() return DBColor("boss") end,
              setValue = function(r, g, b)
                DB().boss = { r = r, g = g, b = b }
                RefreshAllPlates()
              end },
          } },
        { type="dropdown", text="Modify Out of Combat",
          values={ none = "No Change", darken = "Darken", color = "Change Color" },
          order={ "none", "darken", "color" },
          getValue=OOCMode,
          -- The inline color swatch exists only for Change Color: rebuild when that flips.
          setValue=EllesmereUI.DependentSetValue(function() return OOCMode() == "color" end, function(v)
            local on = v ~= "none"
            local db = DB()
            if OOCOn() ~= on then db.darkenEnemiesOOC = on end
            if on and OOCRecolorOn() ~= (v == "color") then db.darkenOOCRecolor = (v == "color") end
            for _, plate in pairs(ns.plates) do
                plate:UpdateHealthColor()
            end
            EllesmereUI:RefreshPage()
          end),
          tooltip="How enemy plates look while out of combat." });  y = y - h

    -- Change Color's flat color (MaybeDarken), inline beside the dropdown while
    -- that mode is picked.
    if not EllesmereUI._prebuilding and OOCMode() == "color" then
        EllesmereUI.BuildInlineSwatches(enemyTypesRow._rightRegion, {
            { tooltip = "Out of Combat Color",
              getValue = function()
                local db = DB()
                local c = (db and db.darkenOOCColor) or defaults.darkenOOCColor
                return c.r, c.g, c.b
              end,
              setValue = function(r, g, b)
                DB().darkenOOCColor = { r = r, g = g, b = b }
                for _, plate in pairs(ns.plates) do
                    plate:UpdateHealthColor()
                end
              end },
        })
    end

    -- Inline cog on "Enemy Types": Simple Coloring When Not In M+. On: outside 5-man dungeons, Mini/Caster/Miniboss/Boss all use the flat "All Enemies" color below (Neutral keeps its own); off (default) has no effect anywhere. Keys keep their owBasic* names from before the current UI label.
    if not EllesmereUI._prebuilding then
        local leftRgn = enemyTypesRow._leftRegion
        local isOWOff = function()
            local v = DBVal("owBasicColoring")
            if v == nil then return not defaults.owBasicColoring end
            return not v
        end
        EllesmereUI.BuildInlineCog(leftRgn, {
            title = "Enemy Colors",
            rows = {
                { type="toggle", label="Simple Coloring When Not In M+",
                  get=function()
                    local v = DBVal("owBasicColoring")
                    if v == nil then return defaults.owBasicColoring end
                    return v
                  end,
                  set=function(v)
                    DB().owBasicColoring = v
                    RefreshAllPlates()
                  end },
                { type="colorpicker", label="All Enemies",
                  get=function() return DBColor("owBasicColor") end,
                  set=function(r, g, b)
                    DB().owBasicColor = { r = r, g = g, b = b }
                    RefreshAllPlates()
                  end,
                  disabled=isOWOff,
                  disabledTooltip="Simple Coloring When Not In M+" },
            },
        })
    end

    -- Neutral & Mini Enemies | Enable Quest Mob Color
    local neutralMiniRow
    neutralMiniRow, h = W:DualRow(parent, y,
        { type="multiSwatch", text="Neutral & Mini Enemies",
          swatches = {
            { tooltip = "Neutral",
              getValue = function() return DBColor("neutral") end,
              setValue = function(r, g, b)
                DB().neutral = { r = r, g = g, b = b }
                RefreshAllPlates()
              end },
            { tooltip = "Mini Enemies",
              -- Until explicitly set, views the user's "Enemies" color so the swatch starts matching enemyInCombat (see GetReactionColor).
              getValue = function()
                local db = DB()
                local c = (db and db.miniEnemy) or (db and db.enemyInCombat) or defaults.enemyInCombat
                return c.r, c.g, c.b
              end,
              setValue = function(r, g, b)
                DB().miniEnemy = { r = r, g = g, b = b }
                RefreshAllPlates()
              end },
          } },
        { type="toggle", text="Enable Quest Mob Color",
          getValue=function() return DBVal("questMobColorEnabled") == true end,
          setValue=function(v)
            DB().questMobColorEnabled = v
            for _, plate in pairs(ns.plates) do
                plate:UpdateHealthColor()
            end
            EllesmereUI:RefreshPage()
          end,
          tooltip="Colors enemy nameplates for quest mobs you still need to kill." });  y = y - h

    -- Inline Quest Mob Color swatch
    if not EllesmereUI._prebuilding then
        local rightRgn = neutralMiniRow._rightRegion
        local questColorGet = function()
            local c = DB().questMobColor or defaults.questMobColor
            return c.r, c.g, c.b
        end
        local questColorSet = function(r, g, b)
            DB().questMobColor = { r = r, g = g, b = b }
            RefreshAllPlates()
        end
        local isQuestOff = function() return DBVal("questMobColorEnabled") ~= true end
        local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5, questColorGet, questColorSet, nil, 20)
        PP.Point(swatch, "RIGHT", rightRgn._control, "LEFT", -12, 0)
        EllesmereUI.RegisterWidgetRefresh(function()
            local off = isQuestOff()
            swatch:SetAlpha(off and 0.15 or 1)
            swatch:EnableMouse(not off)
            updateSwatch()
        end)
        local off = isQuestOff()
        swatch:SetAlpha(off and 0.15 or 1)
        swatch:EnableMouse(not off)
    end

    -- Inline cog on "Neutral & Mini Enemies": "Mini Coloring M+ Only" toggle. On (default) restricts the Mini Enemies color to 5-man dungeons; off applies it everywhere.
    if not EllesmereUI._prebuilding then
        local leftRgn = neutralMiniRow._leftRegion
        EllesmereUI.BuildInlineCog(leftRgn, {
            title = "Mini Enemies",
            rows = {
                { type="toggle", label="Mini Coloring M+ Only",
                  get=function()
                    local v = DBVal("miniColoringMPlusOnly")
                    if v == nil then return defaults.miniColoringMPlusOnly end
                    return v
                  end,
                  set=function(v)
                    DB().miniColoringMPlusOnly = v
                    RefreshAllPlates()
                  end },
            },
        })
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h

    -----------------------------------------------------------------------
    --  THREAT COLORS
    -----------------------------------------------------------------------
    _, h = W:SectionHeader(parent, SECTION_THREAT, y);  y = y - h

    -- Show Threat Colors (threatColorMode): Never / Instances (dungeons, raids and
    -- delves) / Always; an unknown saved value reads as the default. Never locks every
    -- threat-color control below. The WoW Forever Threat % rows are their own feature
    -- and stay live.
    local function threatModeGet()
        local v = DBVal("threatColorMode")
        if v ~= "never" and v ~= "instances" and v ~= "always" then v = defaults.threatColorMode end
        return v
    end
    local function threatNever() return threatModeGet() == "never" end

    -- Row 1: Show Threat Colors (left) ---- Tank Threat (right)
    _, h = W:DualRow(parent, y,
        { type="dropdown", text="Show Threat Colors",
          tooltip="Where nameplates use the threat colors below. Instances covers dungeons, raids and delves.",
          values={ never="Never", instances="Instances", always="Always" },
          order={ "never", "instances", "always" },
          getValue=threatModeGet,
          setValue=function(v)
            DB().threatColorMode = v
            ns.NP_ApplyThreatColorMode()
            EllesmereUI:RefreshPage()
          end },
        { type="multiSwatch", text="Tank Threat",
          disabled=threatNever, disabledTooltip="Show Threat Colors",
          swatches = {
            { tooltip = "Losing Aggro",
              getValue = function() return DBColor("tankLosingAggro") end,
              setValue = function(r, g, b)
                DB().tankLosingAggro = { r = r, g = g, b = b }
                RefreshAllPlates()
              end },
            { tooltip = "No Aggro",
              getValue = function() return DBColor("tankNoAggro") end,
              setValue = function(r, g, b)
                DB().tankNoAggro = { r = r, g = g, b = b }
                RefreshAllPlates()
              end },
          } });  y = y - h

    -- Disabled-state helpers (shared across the toggle rows' swatches and cogs)
    local function isTankHasAggroDisabled()
        local db = DB()
        if db and db.tankHasAggroEnabled ~= nil then return not db.tankHasAggroEnabled end
        return not defaults.tankHasAggroEnabled
    end
    local function isClassicTankAggroDisabled()
        local db = DB()
        if db and db.classicTankAggro ~= nil then return not db.classicTankAggro end
        return not defaults.classicTankAggro
    end
    local function isOffTankDisabled()
        local db = DB()
        if db and db.offTankAggroEnabled ~= nil then return not db.offTankAggroEnabled end
        return not defaults.offTankAggroEnabled
    end
    local function isDpsNoAggroDisabled()
        local db = DB()
        if db and db.dpsNoAggroEnabled ~= nil then return not db.dpsNoAggroEnabled end
        return not defaults.dpsNoAggroEnabled
    end
    -- The Override toggles only reorder the health bar's color priority, so the No Aggro
    -- and Has Aggro cogs (Override rows only) lock while Show Threat On leaves the Health Bar out.
    local function isThreatHealthOff() return not ns.GetThreatColorHealth() end

    -- Inline swatch lock for the toggle rows: dimmed and click-blocked while its own
    -- toggle is off or Show Threat Colors is Never; the block names the missing one.
    local function LockThreatSwatch(swatch, updateSwatch, ownOff, ownReq)
        local tipCfg = { disabledTooltip = function()
            if threatNever() then return "Show Threat Colors" end
            return ownReq
        end }
        local block = CreateFrame("Frame", nil, swatch)
        block:SetAllPoints()
        block:SetFrameLevel(swatch:GetFrameLevel() + 10)
        block:EnableMouse(true)
        block:SetScript("OnEnter", function()
            EllesmereUI.ShowWidgetTooltip(swatch, EllesmereUI.ResolveDisabledTip(tipCfg))
        end)
        block:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        local function State()
            local off = threatNever() or ownOff()
            swatch:SetAlpha(off and 0.3 or 1)
            block:SetShown(off)
        end
        EllesmereUI.RegisterWidgetRefresh(function()
            State()
            updateSwatch()
        end)
        State()
    end

    -- Row 2: Non-Tank Threat (left) ---- DPS: Show Special "No Aggro" Color (right)
    local nonTankRow
    nonTankRow, h = W:DualRow(parent, y,
        { type="multiSwatch", text="Non-Tank Threat",
          disabled=threatNever, disabledTooltip="Show Threat Colors",
          swatches = {
            { tooltip = "Has Aggro",
              getValue = function() return DBColor("dpsHasAggro") end,
              setValue = function(r, g, b)
                DB().dpsHasAggro = { r = r, g = g, b = b }
                RefreshAllPlates()
              end },
            { tooltip = "Near Aggro",
              getValue = function() return DBColor("dpsNearAggro") end,
              setValue = function(r, g, b)
                DB().dpsNearAggro = { r = r, g = g, b = b }
                RefreshAllPlates()
              end },
          } },
        { type="toggle", text="DPS: Show Special \"No Aggro\" Color",
          tooltip="Shows a special color for non caster/mini-boss enemies when you do not have aggro on them.",
          disabled=threatNever, disabledTooltip="Show Threat Colors",
          getValue=function()
            local db = DB()
            if db and db.dpsNoAggroEnabled ~= nil then return db.dpsNoAggroEnabled end
            return defaults.dpsNoAggroEnabled
          end,
          setValue=function(v)
            DB().dpsNoAggroEnabled = v
            RefreshAllPlates()
            EllesmereUI:RefreshPage()
          end });  y = y - h

    -- Inline cog on "Non-Tank Threat": steady red execute-style glow
    -- while the Near Aggro color is active (see EnsureNearAggroGlow).
    if not EllesmereUI._prebuilding then
        EllesmereUI.BuildInlineCog(nonTankRow._leftRegion, {
            disabled = threatNever,
            disabledTooltip = "Show Threat Colors",
            title = "Near Aggro",
            rows = {
                { type="toggle", label="Glow Nameplate When Near Aggro",
                  tooltip="Adds a steady red glow around the nameplate while the Near Aggro color is active.",
                  get=function()
                    local db = DB()
                    local v = db and db.threatNearAggroGlow
                    if v == nil then v = defaults.threatNearAggroGlow end
                    return v
                  end,
                  set=function(v)
                    DB().threatNearAggroGlow = v and true or false
                    for _, plate in pairs(ns.plates) do
                        plate:UpdateHealthColor()
                    end
                  end },
            },
        })
    end

    -- Inline "No Aggro" color swatch next to the DPS toggle
    if not EllesmereUI._prebuilding then
        local rgn = nonTankRow._rightRegion
        local dpsNoAggroColorGet = function() return DBColor("dpsNoAggro") end
        local dpsNoAggroColorSet = function(r, g, b)
            DB().dpsNoAggro = { r = r, g = g, b = b }
            RefreshAllPlates()
        end
        local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, dpsNoAggroColorGet, dpsNoAggroColorSet, nil, 20)
        PP.Point(swatch, "RIGHT", rgn._control, "LEFT", -12, 0)
        LockThreatSwatch(swatch, updateSwatch, isDpsNoAggroDisabled, 'DPS: Show Special "No Aggro" Color')

        -- Inline cog: independent "Override Mini-Boss colors" / "Override Caster colors" / "Override Boss colors" toggles promote the DPS No Aggro color above that single mob-type color (kept separate for contrast); dimmed while off.
        EllesmereUI.BuildInlineCog(rgn, {
            chain = false, anchorTo = swatch,
            disabled = function() return threatNever() or isDpsNoAggroDisabled() or isThreatHealthOff() end,
            disabledTooltip = function()
                if threatNever() then return "Show Threat Colors" end
                if isDpsNoAggroDisabled() then return 'DPS: Show Special "No Aggro" Color' end
                return "Health Bar"
            end,
            title = "No Aggro",
            rows = {
                { type="toggle", label="Override Mini-Boss colors",
                  get=function()
                    local db = DB()
                    if db and db.dpsNoAggroOverrideMiniBoss ~= nil then return db.dpsNoAggroOverrideMiniBoss end
                    return defaults.dpsNoAggroOverrideMiniBoss
                  end,
                  set=function(v) DB().dpsNoAggroOverrideMiniBoss = v; RefreshAllPlates() end },
                { type="toggle", label="Override Caster colors",
                  get=function()
                    local db = DB()
                    if db and db.dpsNoAggroOverrideCaster ~= nil then return db.dpsNoAggroOverrideCaster end
                    return defaults.dpsNoAggroOverrideCaster
                  end,
                  set=function(v) DB().dpsNoAggroOverrideCaster = v; RefreshAllPlates() end },
                { type="toggle", label="Override Boss colors",
                  get=function()
                    local db = DB()
                    if db and db.dpsNoAggroOverrideBoss ~= nil then return db.dpsNoAggroOverrideBoss end
                    return defaults.dpsNoAggroOverrideBoss
                  end,
                  set=function(v) DB().dpsNoAggroOverrideBoss = v; RefreshAllPlates() end },
            },
        })
    end

    -- Row 3: Classic Tank Aggro (left) ---- Tank: Show Special "Has Aggro" Color (right)
    local tankAggroRow
    tankAggroRow, h = W:DualRow(parent, y,
        { type="toggle", text="Classic Tank Aggro",
          tooltip="Enables a three-tier tank aggro system: has aggro, losing aggro, and no aggro colors override all mob-type colors.",
          disabled=threatNever, disabledTooltip="Show Threat Colors",
          getValue=function()
            local db = DB()
            if db and db.classicTankAggro ~= nil then return db.classicTankAggro end
            return defaults.classicTankAggro
          end,
          setValue=function(v)
            DB().classicTankAggro = v
            RefreshAllPlates()
            EllesmereUI:RefreshPage()
          end },
        { type="toggle", text="Tank: Show Special \"Has Aggro\" Color",
          tooltip="Shows a special color for non caster/mini-boss enemies when you have aggro on them.",
          disabled=threatNever, disabledTooltip="Show Threat Colors",
          getValue=function()
            local db = DB()
            if db and db.tankHasAggroEnabled ~= nil then return db.tankHasAggroEnabled end
            return defaults.tankHasAggroEnabled
          end,
          setValue=function(v)
            DB().tankHasAggroEnabled = v
            RefreshAllPlates()
            EllesmereUI:RefreshPage()
          end });  y = y - h

    -- Inline "Has Aggro" color swatch next to Classic Tank Aggro toggle
    if not EllesmereUI._prebuilding then
        local rgn = tankAggroRow._leftRegion
        local aggroColorGet = function() return DBColor("tankHasAggro") end
        local aggroColorSet = function(r, g, b)
            DB().tankHasAggro = { r = r, g = g, b = b }
            RefreshAllPlates()
        end
        local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, aggroColorGet, aggroColorSet, nil, 20)
        PP.Point(swatch, "RIGHT", rgn._control, "LEFT", -12, 0)
        LockThreatSwatch(swatch, updateSwatch, isClassicTankAggroDisabled, "Classic Tank Aggro")
    end

    -- Inline "Has Aggro" color swatch next to the tank Has Aggro toggle
    if not EllesmereUI._prebuilding then
        local rgn = tankAggroRow._rightRegion
        local tankAggroColorGet = function() return DBColor("tankHasAggro") end
        local tankAggroColorSet = function(r, g, b)
            DB().tankHasAggro = { r = r, g = g, b = b }
            RefreshAllPlates()
        end
        local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, tankAggroColorGet, tankAggroColorSet, nil, 20)
        PP.Point(swatch, "RIGHT", rgn._control, "LEFT", -12, 0)
        LockThreatSwatch(swatch, updateSwatch, isTankHasAggroDisabled, 'Tank: Show Special "Has Aggro" Color')

        -- Inline cog "Override Mini-Boss and Caster colors" promotes the tank has-aggro color above the mini-boss/caster priority steps; dimmed while Has Aggro is off.
        EllesmereUI.BuildInlineCog(rgn, {
            chain = false, anchorTo = swatch,
            disabled = function() return threatNever() or isTankHasAggroDisabled() or isThreatHealthOff() end,
            disabledTooltip = function()
                if threatNever() then return "Show Threat Colors" end
                if isTankHasAggroDisabled() then return 'Tank: Show Special "Has Aggro" Color' end
                return "Health Bar"
            end,
            title = "Has Aggro",
            rows = {
                { type="toggle", label="Override Mini-Boss and Caster colors",
                  get=function()
                    local db = DB()
                    if db and db.tankHasAggroOverrideMobType ~= nil then return db.tankHasAggroOverrideMobType end
                    return defaults.tankHasAggroOverrideMobType
                  end,
                  set=function(v) DB().tankHasAggroOverrideMobType = v; RefreshAllPlates() end },
                { type="toggle", label="Override Boss colors",
                  get=function()
                    local db = DB()
                    if db and db.tankHasAggroOverrideBoss ~= nil then return db.tankHasAggroOverrideBoss end
                    return defaults.tankHasAggroOverrideBoss
                  end,
                  set=function(v) DB().tankHasAggroOverrideBoss = v; RefreshAllPlates() end },
            },
        })
    end

    -- Show Threat On: which parts of the plate carry the threat colors above. Border and
    -- Name are second signals beside the Health Bar, so the bar can keep its Enemy Types
    -- color (Caster / Mini-Boss / Boss) while the border and the name show aggro.
    -- Border locks while no EUI border is drawn (None, or a stock style). Built as a
    -- placeholder dropdown (its disabled config dims the label and blocks the slot) and
    -- replaced below in whichever half of chanRow holds it.
    local chanCfg = { type="dropdown", text="Show Threat On",
          disabled=threatNever, disabledTooltip="Show Threat Colors",
          values={ __placeholder = "..." }, order={ "__placeholder" },
          getValue=function() return "__placeholder" end,
          setValue=function() end }

    -- WoW Forever Threat % helpers and toggle (nil on retail, where Show Threat On
    -- takes the Off-Tank row's right slot instead).
    local threatPctOff, ThreatPctSet, offTankRightCfg
    if EllesmereUI.IS_FOREVER then
        threatPctOff = function() return not DBVal("threatPctEnabled") end
        ThreatPctSet = function(key, v)
            DB()[key] = v
            ns.RefreshThreatPct()
        end
        offTankRightCfg = { type="toggle", text="Show Threat % on Nameplates",
              tooltip="Shows your threat percentage on each enemy nameplate while you are in combat with it.",
              getValue=function() return DBVal("threatPctEnabled") end,
              setValue=function(v)
                ThreatPctSet("threatPctEnabled", v)
                EllesmereUI:RefreshPage()
              end }
    else
        offTankRightCfg = chanCfg
    end

    -- Row 4: Tank: Show Special "Off-Tank" Color (left) ---- Show Threat On (right);
    -- on WoW Forever the right slot is Show Threat % on Nameplates.
    local offTankRow
    offTankRow, h = W:DualRow(parent, y,
        { type="toggle", text="Tank: Show Special \"Off-Tank\" Color",
          tooltip="Shows a special color for nameplates that another tank in your raid has aggro on.",
          disabled=threatNever, disabledTooltip="Show Threat Colors",
          getValue=function()
            local db = DB()
            if db and db.offTankAggroEnabled ~= nil then return db.offTankAggroEnabled end
            return defaults.offTankAggroEnabled
          end,
          setValue=function(v)
            DB().offTankAggroEnabled = v
            RefreshAllPlates()
            EllesmereUI:RefreshPage()
          end },
        offTankRightCfg);  y = y - h

    -- Inline "Off-Tank" color swatch next to the Off-Tank toggle
    if not EllesmereUI._prebuilding then
        local rgn = offTankRow._leftRegion
        local otColorGet = function() return DBColor("offTankAggro") end
        local otColorSet = function(r, g, b)
            DB().offTankAggro = { r = r, g = g, b = b }
            RefreshAllPlates()
        end
        local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, otColorGet, otColorSet, nil, 20)
        PP.Point(swatch, "RIGHT", rgn._control, "LEFT", -12, 0)
        LockThreatSwatch(swatch, updateSwatch, isOffTankDisabled, 'Tank: Show Special "Off-Tank" Color')
    end

    -- Row 5 (WoW Forever only): Threat % Position (left) ---- Show Threat On (right).
    local chanRow = offTankRow
    if EllesmereUI.IS_FOREVER then
        local threatPctRow
        threatPctRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Threat % Position",
              values=THREAT_PCT_POSITIONS, order=THREAT_PCT_POSITION_ORDER,
              disabled=threatPctOff, disabledTooltip="Show Threat % on Nameplates",
              getValue=function() return DBVal("threatPctPosition") end,
              setValue=function(v) ThreatPctSet("threatPctPosition", v) end },
            chanCfg);  y = y - h
        chanRow = threatPctRow

        if not EllesmereUI._prebuilding then
            EllesmereUI.BuildInlineCog(threatPctRow._leftRegion, {
                title = "Threat %",
                disabled = threatPctOff,
                disabledTooltip = "Show Threat % on Nameplates",
                rows = ns.NPO_ThreatPctRows(DBVal, ThreatPctSet),
            })
        end
    end

    -- Replace the Show Threat On placeholder with a multi-select checkbox dropdown,
    -- in whichever half of chanRow was built from chanCfg.
    if not EllesmereUI._prebuilding then
        local rgn = chanRow._rightRegion
        if chanRow._leftRegion._cfg == chanCfg then rgn = chanRow._leftRegion end
        if rgn._control then rgn._control:Hide() end
        -- A locked Border also drops out of the summary, which then reads what is drawn.
        local function isThreatBorderLocked()
            return not (ns.IsBorderEnabled() or ns.IsCustomBorderEnabled())
        end
        local chanItems = {
            { key = "health", label = "Health Bar" },
            { key = "border", label = "Border",
              lockedFn = isThreatBorderLocked,
              excludeFromSummaryFn = isThreatBorderLocked,
              lockedTooltip = function()
                if EllesmereUI.BlizzStyle.Get("nameplates") then
                    return EllesmereUI.DisabledTooltip(EllesmereUI.BlizzStyle.Label("nameplates"), "disabled")
                end
                return "This option requires a Border to be selected"
              end },
            { key = "name",   label = "Name" },
        }
        local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
            rgn, 170, rgn:GetFrameLevel() + 2,
            chanItems,
            function(k)
                if k == "health" then return ns.GetThreatColorHealth() end
                if k == "border" then return ns.GetThreatColorBorder() end
                if k == "name"   then return ns.GetThreatColorName() end
                return false
            end,
            function(k, v)
                if k == "health" then DB().threatColorHealth = v
                elseif k == "border" then DB().threatColorBorder = v
                elseif k == "name" then DB().threatColorName = v end
                RefreshAllPlates()
                -- Health Bar gates the No Aggro and Has Aggro cogs.
                EllesmereUI:RefreshPage()
            end)
        PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
        rgn._control = cbDD
        cbDD:HookScript("OnEnter", function()
            EllesmereUI.ShowWidgetTooltip(cbDD, "Chooses which parts of the nameplate show the threat colors; with Health Bar off, the bar keeps its Enemy Types color.")
        end)
        cbDD:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
        -- The checkbox dropdown has no disabled state of its own: grey it and block
        -- clicks while Show Threat Colors is Never; the placeholder's disabled overlay
        -- over the same slot shows the requirement.
        local function ApplyChanDisabled()
            local off = threatNever()
            cbDD:SetAlpha(off and 0.3 or 1)
            cbDD:EnableMouse(not off)
        end
        ApplyChanDisabled()
        EllesmereUI.RegisterWidgetRefresh(ApplyChanDisabled)
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h

    y = ns.NP_BuildDebuffColorsOptions(parent, y)

    -- Build a refresh-all function for page cache restore
    optState._colorPreviewRefreshAll = function()
        for _, prev in ipairs(_G._EUI_ColorPreviews) do
            if prev.UpdateColor then prev.UpdateColor() end
            if prev.UpdateOverlay then prev.UpdateOverlay() end
            if prev.RefreshBorderColor then prev.RefreshBorderColor() end
            if prev.RefreshHealthText then prev.RefreshHealthText() end
        end
        for _, prev in ipairs(_colorPagePreviews) do
            if prev.UpdateColor then prev.UpdateColor() end
            if prev.UpdateOverlay then prev.UpdateOverlay() end
            if prev.RefreshBorderColor then prev.RefreshBorderColor() end
            if prev.RefreshHealthText then prev.RefreshHealthText() end
        end
    end
    for _, prev in ipairs(_colorPagePreviews) do
        if prev.UpdateColor then
            EllesmereUI.RegisterWidgetRefresh(prev.UpdateColor)
        end
        if prev.UpdateOverlay then
            EllesmereUI.RegisterWidgetRefresh(prev.UpdateOverlay)
        end
    end

    return math.abs(y)
end

-- Used by EUI_Nameplates_Options.lua
ns.NPO_MakeColorPreviewBar = MakeColorPreviewBar
ns.NPO_BuildColorsPage = BuildColorsPage
