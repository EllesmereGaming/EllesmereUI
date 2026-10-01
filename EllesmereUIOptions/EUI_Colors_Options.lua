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
    -- Swatches read/write the EFFECTIVE palette (per-profile -> active
    -- profile's own; global -> shared source profile's). Every editable
    -- case IS the active profile's table; the one locked case (global mode on a non-source profile) is gated by an overlay below.
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

        -- Master switches: pure views over their group of per-module providers (on only when every provider is on). Left drives Unit
        -- Frames + Raid Frames, right the class resource bar alone.
        local function _dmIsRB(p) return p.id == "resourceBars" end
        local function _dmNotRB(p) return p.id ~= "resourceBars" end
        local dmMasterRow
        dmMasterRow, h = W:DualRow(parent, y,
            { type = "toggle", text = "Dark Mode",
              tooltip = "Turns Dark Mode on or off for Unit Frames and Raid Frames at once.",
              getValue = function() return EllesmereUI.IsDarkModeAllOn(_dmNotRB) end,
              setValue = function(v)
                  EllesmereUI.SetDarkModeAll(v, _dmNotRB)
                  EllesmereUI:RefreshPage()
              end },
            { type = "toggle", text = "Dark Mode (Class Resource Bar)",
              tooltip = "Turns Dark Mode on or off for the class resource bar.",
              getValue = function() return EllesmereUI.IsDarkModeAllOn(_dmIsRB) end,
              setValue = function(v)
                  EllesmereUI.SetDarkModeAll(v, _dmIsRB)
                  EllesmereUI:RefreshPage()
              end });  y = y - h
        -- MAIN master writes the UF+RF dark flags = the Dark Mode conditional-override condition's inputs, so it locks during a Dark Mode
        -- conditional edit session (an override must not capture a change that flips its own condition). Class Resource Bar master is NOT
        -- a condition input (DarkModeMasterOn excludes it) and stays editable. SetDarkModeAll's tail rechecks the condition live for both.
        if EllesmereUI.SpecOverrides_AttachEditLock and not EllesmereUI._prebuilding then
            EllesmereUI.SpecOverrides_AttachEditLock(dmMasterRow._leftRegion,
                "Dark Mode drives a Dark Mode override condition and can't be changed while editing an override",
                EllesmereUI.SpecOverrides_DarkCondEditActive)
        end

        -- Row 1: Dark Mode Fill Color | Dark Mode Fill Opacity
        _, h = W:DualRow(parent, y,
            { type = "colorpicker", text = "Dark Mode Fill Color", hasAlpha = false,
              tooltip = "The flat fill colour bars use when Dark Mode is enabled (Unit Frames, Raid Frames, Resource Bars).",
              getValue = function()
                  local d = EllesmereUI.GetDarkModeDB()
                  return d.fillR or DM_DEF.fillR, d.fillG or DM_DEF.fillG, d.fillB or DM_DEF.fillB, 1
              end,
              setValue = function(r, g, b)
                  local d = EllesmereUI.GetDarkModeDB()
                  d.fillR, d.fillG, d.fillB = r, g, b
                  EllesmereUI.RefreshDarkMode()
              end },
            { type = "slider", text = "Dark Mode Fill Opacity",
              min = 0, max = 100, step = 5,
              tooltip = "Fill opacity for Dark Mode bars. Applies to Unit Frames and Raid Frames only (Resource Bars ignore it).",
              getValue = function()
                  local d = EllesmereUI.GetDarkModeDB()
                  return math.floor((d.fillA or DM_DEF.fillA) * 100 + 0.5)
              end,
              setValue = function(v)
                  local d = EllesmereUI.GetDarkModeDB()
                  d.fillA = v / 100
                  EllesmereUI.RefreshDarkMode()
              end });  y = y - h

        -- Row 2: Background Color | Background Opacity
        _, h = W:DualRow(parent, y,
            { type = "colorpicker", text = "Background Color", hasAlpha = false,
              tooltip = "The background colour behind Dark Mode bars (Unit Frames, Raid Frames, Resource Bars).",
              getValue = function()
                  local d = EllesmereUI.GetDarkModeDB()
                  return d.bgR or DM_DEF.bgR, d.bgG or DM_DEF.bgG, d.bgB or DM_DEF.bgB, 1
              end,
              setValue = function(r, g, b)
                  local d = EllesmereUI.GetDarkModeDB()
                  d.bgR, d.bgG, d.bgB = r, g, b
                  EllesmereUI.RefreshDarkMode()
              end },
            { type = "slider", text = "Background Opacity",
              min = 0, max = 100, step = 5,
              tooltip = "Background opacity for Dark Mode bars. Applies to Unit Frames and Raid Frames only (Resource Bars ignore it).",
              getValue = function()
                  local d = EllesmereUI.GetDarkModeDB()
                  return math.floor((d.bgA or DM_DEF.bgA) * 100 + 0.5)
              end,
              setValue = function(v)
                  local d = EllesmereUI.GetDarkModeDB()
                  d.bgA = v / 100
                  EllesmereUI.RefreshDarkMode()
              end });  y = y - h

        -- Row 3: Class Color Darken | Power Color Darken
        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Class Color Darken",
              min = 0, max = 100, step = 5,
              tooltip = "Blackens every class colour by this amount, everywhere class colours are used.",
              getValue = function() return EllesmereUI.GetDarkModeDB().classDarken or 0 end,
              setValue = function(v)
                  EllesmereUI.GetDarkModeDB().classDarken = v
                  EllesmereUI.RefreshDarkMode()
              end },
            { type = "slider", text = "Power Color Darken",
              min = 0, max = 100, step = 5,
              tooltip = "Blackens every power colour by this amount, everywhere power colours are used.",
              getValue = function() return EllesmereUI.GetDarkModeDB().powerDarken or 0 end,
              setValue = function(v)
                  EllesmereUI.GetDarkModeDB().powerDarken = v
                  EllesmereUI.RefreshDarkMode()
              end });  y = y - h

        -- Row 4: Resource Color Darken | BG Power Color Darken
        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Resource Color Darken",
              min = 0, max = 100, step = 5,
              tooltip = "Blackens every class-resource colour by this amount, everywhere class-resource colours are used.",
              getValue = function() return EllesmereUI.GetDarkModeDB().resourceDarken or 0 end,
              setValue = function(v)
                  EllesmereUI.GetDarkModeDB().resourceDarken = v
                  EllesmereUI.RefreshDarkMode()
              end },
            { type = "slider", text = "BG Power Color Darken",
              min = 0, max = 100, step = 5,
              tooltip = "Blackens power-colored Power Bar backgrounds (Unit Frames and Raid Frames) by this amount, on top of Power Color Darken.",
              getValue = function() return EllesmereUI.GetDarkModeDB().powerBgDarken or 0 end,
              setValue = function(v)
                  EllesmereUI.GetDarkModeDB().powerBgDarken = v
                  EllesmereUI.RefreshDarkMode()
              end });  y = y - h
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h

    -------------------------------------------------------------------
    --  GLOBAL COLORS section
    -------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "GLOBAL COLORS", y);  y = y - h
    do
        local profileOrder = select(1, EllesmereUI.GetProfileList()) or {}
        local pullValues = {}
        for _, n in ipairs(profileOrder) do pullValues[n] = n end
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Apply to All Profiles",
              tooltip="On (default): one profile's palette is shared across every profile (chosen via Pull Colors From). Off: each profile keeps its own custom colors (Power, Class Resource, Class, Resource).",
              -- Default ON (nil treated as on) = global colours for all profiles.
              getValue=function() return EllesmereUIDB.colorsApplyToAllProfiles ~= false end,
              setValue=function(v)
                  EllesmereUIDB.colorsApplyToAllProfiles = v
                  EllesmereUI.ApplyColorsToOUF()
                  -- Force rebuild: toggle flips the dropdown's enabled state and the editing-gate, which a fast-path refresh won't redo.
                  EllesmereUI:RefreshPage(true)
              end },
            -- Global-mode source: which single profile's palette all profiles use. Enabled only while "Apply to All Profiles" is ON.
            { type="dropdown", text="Pull Colors From",
              values=pullValues, order=profileOrder,
              disabled=function() return EllesmereUIDB.colorsApplyToAllProfiles == false end,
              disabledTooltip="Apply to All Profiles",
              getValue=function() return EllesmereUIDB.colorsPullFrom or profileOrder[1] end,
              setValue=function(v)
                  EllesmereUIDB.colorsPullFrom = v
                  EllesmereUI.ApplyColorsToOUF()
                  EllesmereUI:RefreshPage()
              end });  y = y - h
    end
    -- Colour-edit gate: when this profile mirrors another's colours (GLOBAL mode on a different profile), each section grid gets its OWN
    -- click-blocking overlay (built at the end of this builder). Grid bounds {top, bot} are captured into _colorGates as sections lay out.
    local _colorGates = {}
    _, h = W:Spacer(parent, y, 20);  y = y - h

    -------------------------------------------------------------------
    --  CLASS COLORS section
    -------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "CLASS COLORS", y);  y = y - h
    _colorGates[1] = { top = y }

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
    _colorGates[1].bot = y

    _, h = W:Spacer(parent, y, 20);  y = y - h

    -------------------------------------------------------------------
    --  POWER COLORS section
    -------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "POWER COLORS", y);  y = y - h
    _colorGates[2] = { top = y }

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
    _colorGates[2].bot = y

    _, h = W:Spacer(parent, y, 20);  y = y - h

    -------------------------------------------------------------------
    --  CLASS RESOURCE COLORS section -- standalone swatches mirroring the
    --  POWER COLORS pattern, saved under the "classResource" custom-colors category (not yet consumed).
    -------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "CLASS RESOURCE COLORS", y);  y = y - h
    _colorGates[3] = { top = y }
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
    _colorGates[3].bot = y

    _, h = W:Spacer(parent, y, 20);  y = y - h

    -- Colour-edit gate: in GLOBAL mode the shared palette comes from ONE profile, so editing is blocked while viewing any other. ONE overlay
    -- PER SECTION, sized to that section's grid. Always created; a shared refresh callback shows/hides them and updates the message, so they
    -- stay correct after a profile or global-source change even on a cached page.
    do
        local gates = {}
        local CPAD = EllesmereUI.CONTENT_PAD or 20  -- side inset so the overlay matches the grid content width
        local function MakeColorGate(topY, botY)
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
            tex:SetColorTexture(13/255, 17/255, 25/255, 0.98)
            local msg = EllesmereUI.MakeFont(ov, 13, nil, 1, 1, 1)
            msg:SetTextColor(1, 1, 1, 0.56)
            msg:SetWidth(parent:GetWidth() - 100)
            msg:SetJustifyH("CENTER")
            msg:SetPoint("CENTER", ov, "CENTER", 0, 0)
            ov._msg = msg
            gates[#gates + 1] = ov
        end
        for _, g in ipairs(_colorGates) do MakeColorGate(g.top, g.bot) end
        local function UpdateColorGate()
            local locked = EllesmereUI.IsColorEditingLocked()
            local text
            if locked then
                local p = EllesmereUI.GetProfilesDB()
                local srcName = EllesmereUIDB.colorsPullFrom or (p.profileOrder and p.profileOrder[1]) or ""
                text = EllesmereUI.Lf("Colors are shared globally from the \"%1$s\" profile.\nSwitch to it (or set Pull Colors From to this profile) to edit.", srcName)
            end
            for _, ov in ipairs(gates) do
                if locked then
                    ov._msg:SetText(text)
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
