if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Colors_Options.lua -- Global Settings > Colors. It registers nothing:
--  the Global Settings module (EUI__General_Options.lua) dispatches its builder.
-------------------------------------------------------------------------------
local PP = EllesmereUI.PanelPP

---------------------------------------------------------------------------
--  Colors Page
---------------------------------------------------------------------------
local CLASS_ORDER = EllesmereUI.CLASS_TOKEN_ORDER
local CLASS_LABELS = {
    WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter",
    ROGUE = "Rogue", PRIEST = "Priest", DEATHKNIGHT = "Death Knight",
    SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock",
    MONK = "Monk", DRUID = "Druid", DEMONHUNTER = "Demon Hunter",
    EVOKER = "Evoker",
}
local POWER_LABELS = {
    MANA = "Mana", RAGE = "Rage", FOCUS = "Focus", ENERGY = "Energy",
    RUNIC_POWER = "Runic Power", LUNAR_POWER = "Astral Power",
    INSANITY = "Insanity", MAELSTROM = "Maelstrom", FURY = "Fury",
    PAIN = "Pain", EBON_MIGHT = "Ebon Might",
}
local RESOURCE_LABELS = {
    ComboPoints = "Combo Points", HolyPower = "Holy Power",
    Chi = "Chi", SoulShards = "Soul Shards",
    ArcaneCharges = "Arcane Charges", Essence = "Essence",
    Runes = "Runes",
    SoulFragments = "Soul Fragments",
}
local GRADIENT_DIR_VALUES = {
    ["HORIZONTAL"] = "Left to Right",
    ["HORIZONTAL_REV"] = "Right to Left",
    ["VERTICAL"] = "Top to Bottom",
    ["VERTICAL_REV"] = "Bottom to Top",
}
local GRADIENT_DIR_ORDER = { "HORIZONTAL", "HORIZONTAL_REV", "VERTICAL", "VERTICAL_REV" }

function _G._EUI_BuildColorsPage(pageName, parent, yOffset)
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h
    local MakeFont = EllesmereUI.MakeFont
    -- Swatches read/write the EFFECTIVE palette, resolved per section (per-profile
    -- -> the active profile's own; global -> that section's source profile's). Every
    -- editable case IS the active profile's table; the one locked case (a global
    -- section viewed from a non-source profile) is gated by that section's overlay below.
    local GetCustomColorsDB = EllesmereUI.GetCustomColorsDB
    local CLASS_COLOR_MAP = EllesmereUI.CLASS_COLOR_MAP
    local DEFAULT_POWER_COLORS = EllesmereUI.DEFAULT_POWER_COLORS
    local CONTENT_PAD = EllesmereUI.CONTENT_PAD or 20

    parent._showRowDivider = true

    -- Helper to save a color entry
    local function SaveColorEntry(category, key, data)
        local db = GetCustomColorsDB()
        if not db[category] then db[category] = {} end
        db[category][key] = data
        EllesmereUI.ApplyColorsToOUF()
    end

    -------------------------------------------------------------------
    --  Shared 4-column color grid builder
    -------------------------------------------------------------------
    local GRID_COLS     = 4
    local GRID_ROW_H    = 50
    local GRID_PAD      = CONTENT_PAD
    local GRID_SIDE_PAD = 20
    local SWATCH_SZ     = 20

    -- items = { { label, classToken, getColor, setColor, resetFn }, ... }
    local function BuildColorGrid(par, yPos, items)            local totalRows = math.ceil(#items / GRID_COLS)
        local totalW = par:GetWidth() - GRID_PAD * 2
        local colW = math.floor(totalW / GRID_COLS)

        for row = 0, totalRows - 1 do
            local rowFrame = CreateFrame("Frame", nil, par)
            PP.Size(rowFrame, totalW, GRID_ROW_H)
            PP.Point(rowFrame, "TOPLEFT", par, "TOPLEFT", GRID_PAD, yPos - row * GRID_ROW_H)
            rowFrame._skipRowDivider = true
            EllesmereUI.RowBg(rowFrame, par)

            -- Column dividers
            for d = 1, GRID_COLS - 1 do
                local div = rowFrame:CreateTexture(nil, "ARTWORK")
                div:SetColorTexture(1, 1, 1, 0.06)
                if div.SetSnapToPixelGrid then div:SetSnapToPixelGrid(false); div:SetTexelSnappingBias(0) end
                div:SetWidth(1)
                local xPos = d * colW
                PP.Point(div, "TOP", rowFrame, "TOPLEFT", xPos, 0)
                PP.Point(div, "BOTTOM", rowFrame, "BOTTOMLEFT", xPos, 0)
            end

            for col = 0, GRID_COLS - 1 do
                local idx = row * GRID_COLS + col + 1
                local item = items[idx]
                if not item then break end

                local cell = CreateFrame("Frame", nil, rowFrame)
                cell:SetSize(colW, GRID_ROW_H)
                cell:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", col * colW, 0)

                -- Class-colored label (or white for power colors)
                local cr, cg, cb = 1, 1, 1
                if item.classToken then
                    local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[item.classToken]
                    if cc then cr, cg, cb = cc.r, cc.g, cc.b end
                end
                local label = MakeFont(cell, 13, nil, cr, cg, cb)
                label:SetPoint("LEFT", cell, "LEFT", GRID_SIDE_PAD, 0)
                label:SetText(item.label)

                -- Color swatch (right side)
                local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(cell, cell:GetFrameLevel() + 2,
                    function()
                        local c = item.getColor()
                        return c.r, c.g, c.b, 1
                    end,
                    function(r, g, b)
                        local c = item.getColor()
                        c.r = r; c.g = g; c.b = b
                        item.setColor(c)
                        local rl = EllesmereUI._widgetRefreshList
                        if rl then for i2 = 1, #rl do rl[i2]() end end
                    end, false, SWATCH_SZ)
                swatch:SetPoint("RIGHT", cell, "RIGHT", -GRID_SIDE_PAD, 0)
                -- Repaint on page refresh/show (SelectPage re-runs the refresh list on show) so swatches survive a profile/global-source change.
                EllesmereUI.RegisterWidgetRefresh(updateSwatch)

                -- Undo (reset) button
                local undoBtn = CreateFrame("Button", nil, cell)
                undoBtn:SetSize(18, 18)
                undoBtn:SetPoint("RIGHT", swatch, "LEFT", -10, 0)
                undoBtn:SetFrameLevel(cell:GetFrameLevel() + 3)
                undoBtn:SetAlpha(0.3)
                local undoTex = undoBtn:CreateTexture(nil, "ARTWORK")
                undoTex:SetAllPoints()
                undoTex:SetTexture(EllesmereUI.UNDO_ICON)
                undoBtn:SetScript("OnEnter", function(self)
                    self:SetAlpha(0.6)
                    EllesmereUI.ShowWidgetTooltip(self, "Reset to default")
                end)
                undoBtn:SetScript("OnLeave", function(self)
                    self:SetAlpha(0.3)
                    EllesmereUI.HideWidgetTooltip()
                end)
                undoBtn:SetScript("OnClick", function()
                    item.resetFn()
                    EllesmereUI.ApplyColorsToOUF()
                    updateSwatch()
                    local rl = EllesmereUI._widgetRefreshList
                    if rl then for i2 = 1, #rl do rl[i2]() end end
                end)
            end
        end

        return totalRows * GRID_ROW_H
    end

    -------------------------------------------------------------------
    --  DARK MODE section (per-profile, never subject to "Apply to All
    --  Profiles"). One palette drives Unit Frames, Raid Frames and
    --  Resource Bars (RB ignores the opacity sliders). "Darken" sliders
    --  blacken class/power/class-resource colours inside the colour getters, reaching every module with no extra wiring.
    -------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "DARK MODE", y);  y = y - h
    do
        local DM_DEF = EllesmereUI.DEFAULT_DARK_MODE

        -- Dark Mode: one checkbox dropdown with each module's own Dark Mode, a
        -- pure view over the registered per-module providers (no stored key). A
        -- tick writes through SetDarkModeAll with a one-provider filter, so its
        -- tail rechecks the override condition exactly as before. The Dark Mode
        -- override condition still reads "every provider but the class resource
        -- bar on" (DarkModeMasterOn), which is what the old main toggle showed.
        -- Those providers are its inputs, so they lock while a Dark Mode override
        -- is edited (an override must not capture a change that flips its own
        -- condition); the class resource bar never does.
        local DM_ITEMS = {
            { key = "unitFrames",   label = "Unit Frames" },
            { key = "raidFrames",   label = "Raid Frames" },
            { key = "resourceBars", label = "Class Resource Bar" },
        }
        local function DMProvider(id)
            for _, p in ipairs(EllesmereUI._darkModeToggles) do
                if p.id == id then return p end
            end
        end
        local function CondEditLocked()
            return EllesmereUI.SpecOverrides_DarkCondEditActive ~= nil
                and EllesmereUI.SpecOverrides_DarkCondEditActive() or false
        end
        local dmItems = {}
        for _, it in ipairs(DM_ITEMS) do
            -- A module that is off registers no provider: no row for it.
            if DMProvider(it.key) then
                if it.key ~= "resourceBars" then
                    it.lockedFn = CondEditLocked
                    it.lockedTooltip = "Dark Mode drives a Dark Mode override condition and can't be changed while editing an override"
                end
                dmItems[#dmItems + 1] = it
            end
        end

        -- Row 1: Dark Mode (checkbox dropdown) | Color Darkening (slider
        -- dropdown: the class / resource / power / BG power darken amounts).
        local dmRow
        dmRow, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Dark Mode",
              tooltip = "Turns Dark Mode on or off for each module.",
              values = { ["_placeholder"] = "..." }, order = { "_placeholder" },
              getValue = function() return "_placeholder" end,
              setValue = function() end },
            { type = "dropdown", text = "Color Darkening",
              tooltip = "Darkens class, resource and power colors.",
              values = { ["_placeholder"] = "..." }, order = { "_placeholder" },
              getValue = function() return "_placeholder" end,
              setValue = function() end });  y = y - h

        -- Row 2: Dark Mode Fill | Background -- each an opacity slider with its
        -- colour as an inline swatch (Resource Bars use the colours but ignore
        -- the opacity).
        local fillRow
        fillRow, h = W:DualRow(parent, y,
            { type = "slider", text = "Dark Mode Fill",
              min = 0, max = 100, step = 5, trackWidth = 120,
              tooltip = "Fill color and opacity of Dark Mode bars.",
              tooltipOnControl = "Fill Opacity",
              getValue = function()
                  local d = EllesmereUI.GetDarkModeDB()
                  return math.floor((d.fillA or DM_DEF.fillA) * 100 + 0.5)
              end,
              setValue = function(v)
                  local d = EllesmereUI.GetDarkModeDB()
                  d.fillA = v / 100
                  EllesmereUI.RefreshDarkMode()
              end },
            { type = "slider", text = "Background",
              min = 0, max = 100, step = 5, trackWidth = 120,
              tooltip = "Color and opacity behind Dark Mode bars.",
              tooltipOnControl = "Background Opacity",
              getValue = function()
                  local d = EllesmereUI.GetDarkModeDB()
                  return math.floor((d.bgA or DM_DEF.bgA) * 100 + 0.5)
              end,
              setValue = function(v)
                  local d = EllesmereUI.GetDarkModeDB()
                  d.bgA = v / 100
                  EllesmereUI.RefreshDarkMode()
              end });  y = y - h

        if not EllesmereUI._prebuilding then
            local rgn = dmRow._leftRegion
            if rgn._control then rgn._control:Hide() end
            local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                rgn, 210, rgn:GetFrameLevel() + 2, dmItems,
                function(id)
                    local p = DMProvider(id)
                    if not p then return false end
                    local ok, on = pcall(p.isOn)
                    return (ok and on) and true or false
                end,
                function(id, v)
                    EllesmereUI.SetDarkModeAll(v, function(p) return p.id == id end)
                    EllesmereUI:RefreshPage()
                end)
            PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
            rgn._control = cbDD
            rgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)

            -- The four darken amounts (same keys and ranges the old rows had).
            local function Darken(key, label, tip)
                return { label = label, tooltip = tip, min = 0, max = 100, step = 5,
                    get = function() return EllesmereUI.GetDarkModeDB()[key] or 0 end,
                    set = function(v)
                        EllesmereUI.GetDarkModeDB()[key] = v
                        EllesmereUI.RefreshDarkMode()
                    end }
            end
            local drgn = dmRow._rightRegion
            if drgn._control then drgn._control:Hide() end
            local sDD, sDDRefresh = EllesmereUI.BuildSliderDropdown(drgn, 210, drgn:GetFrameLevel() + 2, {
                Darken("classDarken", "Class", "Darkens every class color."),
                Darken("resourceDarken", "Resource", "Darkens every class resource color."),
                Darken("powerDarken", "Power", "Darkens every power color."),
                Darken("powerBgDarken", "BG Power", "Darkens power-colored bar backgrounds."),
            })
            PP.Point(sDD, "RIGHT", drgn, "RIGHT", -20, 0)
            drgn._control = sDD
            drgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(sDDRefresh)

            EllesmereUI.BuildInlineSwatches(fillRow._leftRegion, {
                { tooltip = "Fill Color",
                  getValue = function()
                      local d = EllesmereUI.GetDarkModeDB()
                      return d.fillR or DM_DEF.fillR, d.fillG or DM_DEF.fillG, d.fillB or DM_DEF.fillB, 1
                  end,
                  setValue = function(r, g, b)
                      local d = EllesmereUI.GetDarkModeDB()
                      d.fillR, d.fillG, d.fillB = r, g, b
                      EllesmereUI.RefreshDarkMode()
                  end },
            }, { size = 20 })
            EllesmereUI.BuildInlineSwatches(fillRow._rightRegion, {
                { tooltip = "Background Color",
                  getValue = function()
                      local d = EllesmereUI.GetDarkModeDB()
                      return d.bgR or DM_DEF.bgR, d.bgG or DM_DEF.bgG, d.bgB or DM_DEF.bgB, 1
                  end,
                  setValue = function(r, g, b)
                      local d = EllesmereUI.GetDarkModeDB()
                      d.bgR, d.bgG, d.bgB = r, g, b
                      EllesmereUI.RefreshDarkMode()
                  end },
            }, { size = 20 })
        end
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h

    -------------------------------------------------------------------
    --  Colour sections. Each opens with its own "Apply to All Profiles" |
    --  "Pull Colors From" row (EllesmereUI.ColorSectionApplyAll / ColorSectionPullFrom;
    --  a section with no setting of its own reads the old shared pair). While a
    --  section mirrors another profile's colours (global mode, viewed from a
    --  different profile) its grid -- not its source row -- gets a click-blocking
    --  overlay, built at the end of this builder from the bounds captured below.
    -------------------------------------------------------------------
    local profileOrder = select(1, EllesmereUI.GetProfileList()) or {}
    local pullValues = {}
    for _, n in ipairs(profileOrder) do pullValues[n] = n end
    local _colorGates = {}   -- { section, top, bot } per section grid
    local function SectionSourceRow(section)
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Apply to All Profiles",
              tooltip="Share this section's colors across profiles.",
              getValue=function() return EllesmereUI.ColorSectionApplyAll(section) end,
              setValue=function(v)
                  EllesmereUI.SetColorSectionApplyAll(section, v)
                  EllesmereUI.ApplyColorsToOUF()
                  -- Force rebuild: the toggle flips the dropdown's enabled state and the section's gate.
                  EllesmereUI:RefreshPage(true)
              end },
            { type="dropdown", text="Pull Colors From",
              values=pullValues, order=profileOrder,
              disabled=function() return not EllesmereUI.ColorSectionApplyAll(section) end,
              disabledTooltip="Apply to All Profiles",
              getValue=function() return EllesmereUI.ColorSectionPullFrom(section) end,
              setValue=function(v)
                  EllesmereUI.SetColorSectionPullFrom(section, v)
                  EllesmereUI.ApplyColorsToOUF()
                  EllesmereUI:RefreshPage()
              end });  y = y - h
        _colorGates[#_colorGates + 1] = { section = section, top = y }
    end

    -------------------------------------------------------------------
    --  CLASS COLORS section
    -------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "CLASS COLORS", y);  y = y - h
    SectionSourceRow("class")

    local classItems = {}
    for _, token in ipairs(CLASS_ORDER) do
        -- Class names are Blizzard-localized in every client language; use the client's own names, falling back to our English labels.
        local lbl = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token]) or CLASS_LABELS[token]
        local def = CLASS_COLOR_MAP[token] or { r = 1, g = 1, b = 1 }
        classItems[#classItems + 1] = {
            label = EllesmereUI.L(lbl),
            classToken = token,
            getColor = function()
                local db = GetCustomColorsDB()
                if db.class and db.class[token] then return db.class[token] end
                return { r = def.r, g = def.g, b = def.b }
            end,
            setColor = function(c)
                SaveColorEntry("class", token, c)
            end,
            resetFn = function()
                local db = GetCustomColorsDB()
                if db.class then db.class[token] = nil end
            end,
        }
    end

    h = BuildColorGrid(parent, y, classItems)
    y = y - h
    _colorGates[#_colorGates].bot = y

    _, h = W:Spacer(parent, y, 20);  y = y - h

    -------------------------------------------------------------------
    --  POWER COLORS section
    -------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "POWER COLORS", y);  y = y - h
    SectionSourceRow("power")

    local POWER_ORDER = {
        "MANA", "RAGE", "FOCUS", "ENERGY", "RUNIC_POWER", "FURY",
        "LUNAR_POWER", "INSANITY", "MAELSTROM", "EBON_MIGHT",
    }
    local powerItems = {}
    for _, pk in ipairs(POWER_ORDER) do
        -- Power names are Blizzard global strings (already localized); fall back to our English labels for non-standard entries (e.g. Ebon Might).
        local lbl = _G[pk] or POWER_LABELS[pk] or pk
        local def = DEFAULT_POWER_COLORS[pk] or { r = 1, g = 1, b = 1 }
        powerItems[#powerItems + 1] = {
            label = EllesmereUI.L(lbl),
            classToken = nil,
            getColor = function()
                local db = GetCustomColorsDB()
                if db.power and db.power[pk] then return db.power[pk] end
                return { r = def.r, g = def.g, b = def.b }
            end,
            setColor = function(c)
                SaveColorEntry("power", pk, c)
            end,
            resetFn = function()
                EllesmereUI.ResetPowerColor(pk)
            end,
        }
    end

    h = BuildColorGrid(parent, y, powerItems)
    y = y - h
    _colorGates[#_colorGates].bot = y

    _, h = W:Spacer(parent, y, 20);  y = y - h

    -------------------------------------------------------------------
    --  CLASS RESOURCE COLORS section -- standalone swatches mirroring the
    --  POWER COLORS pattern, saved under the "classResource" custom-colors category (not yet consumed).
    -------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "CLASS RESOURCE COLORS", y);  y = y - h
    SectionSourceRow("classResource")
    do
        -- Order + labels only; defaults live in the shared DEFAULT_CLASS_RESOURCE_COLORS, the source the resource bar's "Class Resource
        -- Color" fill mode reads.
        local items = {
            { key = "ComboPoints",     label = "Combo Points"     },
            { key = "Runes",           label = "Runes"            },
            { key = "SoulShards",      label = "Soul Shards"      },
            { key = "HolyPower",       label = "Holy Power"       },
            { key = "ArcaneCharges",   label = "Arcane Charges"   },
            { key = "Icicles",         label = "Icicles"          },
            { key = "Chi",             label = "Chi"              },
            { key = "Essence",         label = "Essence"          },
            { key = "SoulFragments",   label = "Soul Fragments"   },
            { key = "MaelstromWeapon", label = "Maelstrom Weapon" },
            { key = "TipOfTheSpear",   label = "Tip of the Spear" },
            { key = "WhirlwindStacks", label = "Whirlwind Stacks" },
            { key = "SweepingStrikes", label = "Sweeping Strikes" },
        }
        local resourceItems = {}
        for _, it in ipairs(items) do
            local key = it.key
            resourceItems[#resourceItems + 1] = {
                label = EllesmereUI.L(it.label),
                getColor = function()
                    return EllesmereUI.GetClassResourceColor(key)
                        or { r = 1, g = 1, b = 1 }
                end,
                setColor = function(c)
                    SaveColorEntry("classResource", key, c)
                end,
                resetFn = function()
                    local cdb = GetCustomColorsDB()
                    if cdb.classResource then cdb.classResource[key] = nil end
                end,
            }
        end
        h = BuildColorGrid(parent, y, resourceItems)
    end
    y = y - h
    _colorGates[#_colorGates].bot = y

    _, h = W:Spacer(parent, y, 20);  y = y - h

    -- Colour-edit gate: a GLOBAL-mode section takes its palette from ONE profile, so its editing is blocked while viewing any other. ONE
    -- overlay PER SECTION, sized to that section's grid, judged by that section's own setting. Always created; a shared refresh callback
    -- shows/hides them and updates the message, so they stay correct after a profile or source change even on a cached page.
    do
        local gates = {}
        local CPAD = EllesmereUI.CONTENT_PAD or 20  -- side inset so the overlay matches the grid content width
        local function MakeColorGate(section, topY, botY)
            if not topY or not botY then return end
            local ov = CreateFrame("Frame", nil, parent)
            ov:SetPoint("TOPLEFT", parent, "TOPLEFT", CPAD, topY)
            ov:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -CPAD, topY)
            ov:SetHeight(math.abs(botY - topY))
            ov:SetFrameLevel(parent:GetFrameLevel() + 100)
            ov:EnableMouse(true)
            ov:Hide()
            local tex = ov:CreateTexture(nil, "OVERLAY")
            tex:SetAllPoints()
            tex:SetColorTexture(17/255, 15/255, 12/255, 0.98)
            local msg = EllesmereUI.MakeFont(ov, 13, nil, 1, 1, 1)
            msg:SetTextColor(1, 1, 1, 0.56)
            msg:SetWidth(parent:GetWidth() - 100)
            msg:SetJustifyH("CENTER")
            msg:SetPoint("CENTER", ov, "CENTER", 0, 0)
            ov._msg = msg
            ov._section = section
            gates[#gates + 1] = ov
        end
        for _, g in ipairs(_colorGates) do MakeColorGate(g.section, g.top, g.bot) end
        local function UpdateColorGate()
            for _, ov in ipairs(gates) do
                if EllesmereUI.IsColorEditingLocked(ov._section) then
                    local srcName = EllesmereUI.ColorSectionPullFrom(ov._section) or ""
                    ov._msg:SetText(EllesmereUI.Lf("Colors are shared globally from the \"%1$s\" profile.\nSwitch to it (or set Pull Colors From to this profile) to edit.", srcName))
                    ov:Show()
                else
                    ov:Hide()
                end
            end
        end
        UpdateColorGate()
        EllesmereUI.RegisterWidgetRefresh(UpdateColorGate)
    end

    return math.abs(y)
end
