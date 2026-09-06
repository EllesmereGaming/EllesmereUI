if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Fonts_Options.lua
--
--  Global Settings > Fonts: the centralized fonts page.
--  Top block = the global font settings (moved from the old Fonts & Colors
--  page). Below it, one expandable card per module. Every control on this
--  page is a WRITE-THROUGH MIRROR: it reads and writes the exact same DB key
--  as the module's own options row and calls the same apply path, so editing
--  a value here or in the module page is identical. Settings that live behind
--  a module page's own selection state (per-bar, per-unit, per-icon stores)
--  are link rows that jump to the real setting instead of duplicating it.
--
--  The card header hosts the module's font override dropdown. That dropdown
--  IS the old "PER ADDON FONTS" list: it reads/writes the same
--  EllesmereUIDB.fonts.moduleFonts entries (lazily created on the first
--  non-global pick, pruned when font and outline both return to global), so
--  existing profiles and exports behave identically.
-------------------------------------------------------------------------------

local PAGE_FONTS = "Fonts"
local GLOBAL_KEY = "_EUIGlobal"

-- Session-only card expand state (never saved).
local _ftExpanded = {}

-------------------------------------------------------------------------------
--  Shared helpers
-------------------------------------------------------------------------------

-- Reload popup for font changes; same funnel contract as the module pages:
-- the resolution cache must drop even when the user picks Later, because the
-- new value is already live in the DB.
local function FontReload()
    EllesmereUI.InvalidateFontCache()
    EllesmereUI:ShowConfirmPopup({
        title       = "Reload Required",
        message     = "Font changed. A UI reload is needed to apply the new font.",
        confirmText = "Reload Now",
        cancelText  = "Later",
        onConfirm   = function() ReloadUI() end,
    })
end

-- moduleFonts accessors. No entry and an entry with font/outline "__global"
-- are behaviorally identical (GetModuleFontEntry falls through to the global
-- font either way), so the card rows lazily create entries and prune them
-- back out when both values return to global.
local function FindModuleFontEntry(folder)
    local f = EllesmereUI.GetFontsDB()
    local list = f.moduleFonts
    if not list then return nil end
    for i = 1, #list do
        if list[i].folder == folder then return list[i], i end
    end
    return nil
end

local function EnsureModuleFontEntry(folder, display)
    local f = EllesmereUI.GetFontsDB()
    if not f.moduleFonts then f.moduleFonts = {} end
    local entry = FindModuleFontEntry(folder)
    if not entry then
        entry = { folder = folder, display = display, font = "__global", outline = "__global" }
        f.moduleFonts[#f.moduleFonts + 1] = entry
    end
    return entry
end

local function PruneModuleFontEntry(folder)
    local f = EllesmereUI.GetFontsDB()
    local entry, idx = FindModuleFontEntry(folder)
    if entry and idx and (entry.font or "__global") == "__global"
       and (entry.outline or "__global") == "__global" then
        table.remove(f.moduleFonts, idx)
    end
end

-- Shared outline dropdown data (safe to share by reference: dropdown menus
-- render only the keys their order lists).
local MODULE_OUTLINE_VALUES = {
    ["__global"] = { text = "EUI Global Outline" },
    ["none"]     = { text = "Drop Shadow" },
    ["outline"]  = { text = "Outline" },
    ["thick"]    = { text = "Thick Outline" },
}
local MODULE_OUTLINE_ORDER = { "__global", "none", "outline", "thick" }

-- Per-module outline row config (left slot of each card's first row).
local function ModuleOutlineCfg(folder, display)
    return { type = "dropdown", text = "Module Outline",
        tooltip = "Outline style override for all " .. display .. " text. EUI Global Outline follows the global Outline Mode setting above.",
        values = MODULE_OUTLINE_VALUES, order = MODULE_OUTLINE_ORDER,
        getValue = function()
            local entry = FindModuleFontEntry(folder)
            return (entry and entry.outline) or "__global"
        end,
        setValue = function(v)
            local entry = FindModuleFontEntry(folder)
            local cur = (entry and entry.outline) or "__global"
            if v == cur then return end
            if v == "__global" then
                if entry then
                    entry.outline = "__global"
                    PruneModuleFontEntry(folder)
                end
            else
                EnsureModuleFontEntry(folder, display).outline = v
            end
            FontReload()
        end }
end

-- Fresh table per call: DualRow configs must never be shared across rows.
local function BLANK() return { type = "label", text = "" } end

-- Custom link row: label on the left, an Open Settings button on the right,
-- jumping to the module page that owns a selection-bound settings family.
local function LinkRow(parent, y, label, module, page, section, highlight)
    local PP = EllesmereUI.PanelPP
    local ROW_H = 40
    local row = CreateFrame("Frame", nil, parent)
    PP.Size(row, parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2, ROW_H)
    PP.Point(row, "TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD, y)
    row._skipRowDivider = true
    if EllesmereUI.RowBg then EllesmereUI.RowBg(row, parent) end

    local lbl = EllesmereUI.MakeFont(row, 13, nil, 1, 1, 1)
    lbl:SetAlpha(0.9)
    lbl:SetPoint("LEFT", row, "LEFT", 20, 0)
    lbl:SetText(EllesmereUI.L(label))

    local btn = CreateFrame("Button", nil, row)
    PP.Size(btn, 122, 26)
    btn:SetPoint("RIGHT", row, "RIGHT", -20, 0)
    btn:SetFrameLevel(row:GetFrameLevel() + 2)
    EllesmereUI.MakeStyledButton(btn, "Open Settings", 11, EllesmereUI.WB_COLOURS, function()
        EllesmereUI:NavigateToElementSettings(module, page, section, nil, highlight)
    end)

    return y - ROW_H
end

-- Dim note row shown inside a card when its module is disabled.
local function NoteRow(parent, y, text)
    local PP = EllesmereUI.PanelPP
    local ROW_H = 34
    local row = CreateFrame("Frame", nil, parent)
    PP.Size(row, parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2, ROW_H)
    PP.Point(row, "TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD, y)
    row._skipRowDivider = true
    local lbl = EllesmereUI.MakeFont(row, 12, nil, 1, 1, 1)
    lbl:SetAlpha(0.45)
    lbl:SetPoint("LEFT", row, "LEFT", 20, 0)
    lbl:SetText(EllesmereUI.L(text))
    return y - ROW_H
end

-------------------------------------------------------------------------------
--  Per-module card content builders
--
--  Each builder receives (parent, y, W, tile) and returns the new y. Every
--  row is a write-through mirror of the module's own options row: same DB
--  key, same defaults, same apply call. When the module is disabled its
--  namespace is nil and the card shows only the module font/outline layer.
-------------------------------------------------------------------------------

local function NS(folder) return EllesmereUI._ModuleNS and EllesmereUI._ModuleNS[folder] end

local function TileActionBars(parent, y, W, tile)
    local ns = NS(tile.folder)
    local function bars()
        local EAB = ns and ns.EAB
        return EAB and EAB.db and EAB.db.profile and EAB.db.profile.bars
    end
    local function dataBarCfg(label, barKey)
        return { type = "slider", text = label, min = 6, max = 24, step = 1,
            getValue = function()
                local b = bars(); local s = b and b[barKey]
                return (s and s.textSize) or 9
            end,
            setValue = function(v)
                local b = bars(); local s = b and b[barKey]
                if not s then return end
                s.textSize = v
                if ns.ApplyDataBarLayout then ns.ApplyDataBarLayout(barKey) end
            end }
    end
    local _, h
    if ns then
        _, h = W:DualRow(parent, y, ModuleOutlineCfg(tile.folder, tile.display),
            dataBarCfg("XP Bar Text Size", "XPBar"));  y = y - h
        _, h = W:DualRow(parent, y,
            dataBarCfg("Reputation Bar Text Size", "RepBar"),
            dataBarCfg("House Favor Bar Text Size", "FavorBar"));  y = y - h
        y = LinkRow(parent, y, "Keybind, Macro, Charges & Cooldown Text (per bar)",
            tile.folder, "Bar Display", "TEXT", "Keybind Text Size")
    else
        _, h = W:DualRow(parent, y, ModuleOutlineCfg(tile.folder, tile.display), BLANK());  y = y - h
        y = NoteRow(parent, y, EllesmereUI.Lf("Enable %1$s to edit its text settings.", EllesmereUI.L(tile.display)))
    end
    return y
end

local function TileNameplates(parent, y, W, tile)
    local ns = NS(tile.folder)
    local _, h
    if not ns then
        _, h = W:DualRow(parent, y, ModuleOutlineCfg(tile.folder, tile.display), BLANK());  y = y - h
        return NoteRow(parent, y, EllesmereUI.Lf("Enable %1$s to edit its text settings.", EllesmereUI.L(tile.display)))
    end
    local function db() return ns.db and ns.db.profile end
    local DEF = ns.defaults or {}
    -- applyFn: named ns refresher when the module publishes one, otherwise the
    -- module-wide reapply (same repaint the module's own castbar size rows use).
    local function size(label, key, minV, maxV, def, applyName, legacyKey)
        return { type = "slider", text = label, min = minV, max = maxV, step = 1,
            getValue = function()
                local p = db()
                local v = p and p[key]
                if v == nil and legacyKey and p then v = p[legacyKey] end
                return v or DEF[key] or def
            end,
            setValue = function(v)
                local p = db(); if not p then return end
                p[key] = v
                local fn = (applyName and ns[applyName]) or ns.RefreshAllSettings
                if fn then fn() end
            end }
    end
    _, h = W:DualRow(parent, y, ModuleOutlineCfg(tile.folder, tile.display),
        size("Friendly Name Size (Bar Mode)", "friendlyNameTextSize", 6, 30, 12, "RefreshFriendlyNameTextSize"));  y = y - h
    _, h = W:DualRow(parent, y,
        size("Friendly Name Size (Name Only)", "friendlyNameSize", 8, 30, 15, "RefreshFriendlyNameSize"),
        size("Friendly NPC Name Size", "friendlyNPCNameSize", 6, 30, 13, "RefreshAllNPCOverlays"));  y = y - h
    _, h = W:DualRow(parent, y,
        size("Top Text Size", "textSlotTopSize", 6, 30, 10),
        size("Center Text Size", "textSlotCenterSize", 6, 30, 10));  y = y - h
    _, h = W:DualRow(parent, y,
        size("Left Text Size", "textSlotLeftSize", 6, 30, 10),
        size("Right Text Size", "textSlotRightSize", 6, 30, 10));  y = y - h
    _, h = W:DualRow(parent, y,
        size("Cast Name Size", "castNameSize", 6, 20, 10),
        size("Cast Timer Size", "castTimerSize", 6, 20, 10));  y = y - h
    _, h = W:DualRow(parent, y,
        size("Cast Target Size", "castTargetSize", 6, 20, 10),
        { type = "slider", text = "Aura Stacks Size", min = 6, max = 20, step = 1,
          getValue = function()
              local p = db()
              return (p and p.auraStackTextSize) or DEF.auraStackTextSize or 11
          end,
          setValue = function(v)
              local p = db(); if not p then return end
              p.auraStackTextSize = v
              if ns.RefreshAllSettings then ns.RefreshAllSettings() end
              if ns.NPC_ReloadAll then ns.NPC_ReloadAll() end
          end });  y = y - h
    _, h = W:DualRow(parent, y,
        size("Buff Duration Size", "buffDurationTextSize", 6, 20, 11, nil, "auraDurationTextSize"),
        size("Debuff Duration Size", "debuffDurationTextSize", 6, 20, 11, nil, "auraDurationTextSize"));  y = y - h
    _, h = W:DualRow(parent, y,
        size("CC Duration Size", "ccDurationTextSize", 6, 20, 11, nil, "auraDurationTextSize"),
        size("Focus Letter Size", "focusLetterSize", 6, 40, 18));  y = y - h
    _, h = W:DualRow(parent, y,
        size("Distance Text Size", "rangeTextSize", 6, 32, 11, "RangeText_Refresh"),
        size("Quest Objective Text Size", "questObjectiveTextSize", 6, 24, 14, "RefreshQuestObjective"));  y = y - h
    return y
end

local function TileUnitFrames(parent, y, W, tile)
    local ns = NS(tile.folder)
    local _, h = W:DualRow(parent, y, ModuleOutlineCfg(tile.folder, tile.display), BLANK())
    y = y - h
    if ns then
        y = LinkRow(parent, y, "Player, Target & Focus Text Sizes (per unit)",
            tile.folder, "Main Frames", "HEALTH BAR")
        y = LinkRow(parent, y, "Pet & Target-of-Target Text Sizes (per unit)",
            tile.folder, "Mini Frames", "HEALTH BAR")
        y = LinkRow(parent, y, "Boss Frames Text Sizes",
            tile.folder, "Boss Frames", "HEALTH BAR")
        y = LinkRow(parent, y, "Player Aura Bars Text (per bar)",
            tile.folder, "Player Aura Bars", nil)
    else
        y = NoteRow(parent, y, EllesmereUI.Lf("Enable %1$s to edit its text settings.", EllesmereUI.L(tile.display)))
    end
    return y
end

local function TileRaidFrames(parent, y, W, tile)
    local ns = NS(tile.folder)
    local _, h
    if not ns then
        _, h = W:DualRow(parent, y, ModuleOutlineCfg(tile.folder, tile.display), BLANK());  y = y - h
        return NoteRow(parent, y, EllesmereUI.Lf("Enable %1$s to edit its text settings.", EllesmereUI.L(tile.display)))
    end
    local function db() return ns.db and ns.db.profile end
    local function RFApply()
        if ns.ReloadFrames then ns.ReloadFrames() end
        if ns.ReloadPartyFrames then ns.ReloadPartyFrames() end
    end
    local function size(label, key, minV, maxV, def)
        return { type = "slider", text = label, min = minV, max = maxV, step = 1,
            getValue = function()
                local p = db()
                return (p and p[key]) or def
            end,
            setValue = function(v)
                local p = db(); if not p then return end
                p[key] = v
                RFApply()
            end }
    end
    _, h = W:DualRow(parent, y, ModuleOutlineCfg(tile.folder, tile.display),
        size("Name Size", "nameSize", 6, 26, 10));  y = y - h
    _, h = W:DualRow(parent, y,
        size("Health Text Size", "healthTextSize", 6, 26, 9),
        size("Heal Absorb Text Size", "healAbsorbTextSize", 6, 26, 9));  y = y - h
    _, h = W:DualRow(parent, y,
        size("Status Text Size", "statusTextSize", 6, 30, 14),
        size("Group Number Size", "groupNumberSize", 6, 30, 10));  y = y - h
    _, h = W:DualRow(parent, y,
        size("Top Name Bar Text Size", "topNameBarTextSize", 6, 30, 11),
        { type = "slider", text = "Healer Mana Text Size", min = 8, max = 24, step = 1,
          getValue = function()
              local p = db()
              local hm = p and p.healerMana
              return (hm and hm.textSize) or 12
          end,
          setValue = function(v)
              local p = db(); if not p then return end
              if not p.healerMana then p.healerMana = {} end
              p.healerMana.textSize = v
              if ns.HM_Rebuild then ns.HM_Rebuild() else RFApply() end
          end });  y = y - h
    y = LinkRow(parent, y, "Party-Specific Text Sizes",
        tile.folder, "Party", "TEXT DISPLAY")
    y = LinkRow(parent, y, "Buff Manager Text (per indicator)",
        tile.folder, "Buff Manager", nil)
    y = LinkRow(parent, y, "Debuff Manager Text (per tile)",
        tile.folder, "Debuff Manager", nil)
    return y
end

local function TileCooldownManager(parent, y, W, tile)
    local ns = NS(tile.folder)
    local _, h = W:DualRow(parent, y, ModuleOutlineCfg(tile.folder, tile.display), BLANK())
    y = y - h
    if ns then
        y = LinkRow(parent, y, "Icon Duration, Stack & Keybind Text (per bar)",
            tile.folder, "CDM Bars", "ICON DISPLAY", "Duration Size")
        y = LinkRow(parent, y, "Tracking Bar Name, Timer & Stacks Text (per bar)",
            tile.folder, "Tracking Bars", "BAR LAYOUT")
    else
        y = NoteRow(parent, y, EllesmereUI.Lf("Enable %1$s to edit its text settings.", EllesmereUI.L(tile.display)))
    end
    return y
end

local function TileResourceBars(parent, y, W, tile)
    local ns = NS(tile.folder)
    local _, h
    if not ns then
        _, h = W:DualRow(parent, y, ModuleOutlineCfg(tile.folder, tile.display), BLANK());  y = y - h
        return NoteRow(parent, y, EllesmereUI.Lf("Enable %1$s to edit its text settings.", EllesmereUI.L(tile.display)))
    end
    local function db() return _G._ERB_AceDB and _G._ERB_AceDB.profile end
    local function RBApply() if _G._ERB_Apply then _G._ERB_Apply() end end
    local function size(label, tableKey, key, minV, maxV, def)
        return { type = "slider", text = label, min = minV, max = maxV, step = 1,
            getValue = function()
                local p = db()
                local t = p and p[tableKey]
                return (t and t[key]) or def
            end,
            setValue = function(v)
                local p = db()
                local t = p and p[tableKey]
                if not t then return end
                t[key] = v
                RBApply()
            end }
    end
    _, h = W:DualRow(parent, y, ModuleOutlineCfg(tile.folder, tile.display),
        size("Health Text Size", "health", "textSize", 8, 24, 11));  y = y - h
    _, h = W:DualRow(parent, y,
        size("Power Text Size", "primary", "textSize", 8, 24, 11),
        size("Class Resource Text Size", "secondary", "textSize", 8, 24, 11));  y = y - h
    _, h = W:DualRow(parent, y,
        size("Cast Bar Text Size", "castBar", "spellTextSize", 8, 24, 11),
        size("Cast Bar Timer Size", "castBar", "timerSize", 8, 24, 11));  y = y - h
    _, h = W:DualRow(parent, y,
        size("Totem Timer Size", "totemBar", "timerSize", 6, 24, 11), BLANK());  y = y - h
    return y
end

local function TileAuraBuffReminders(parent, y, W, tile)
    local ns = NS(tile.folder)
    local _, h
    if not ns then
        _, h = W:DualRow(parent, y, ModuleOutlineCfg(tile.folder, tile.display), BLANK());  y = y - h
        return NoteRow(parent, y, EllesmereUI.Lf("Enable %1$s to edit its text settings.", EllesmereUI.L(tile.display)))
    end
    local function db() return _G._EABR_AceDB and _G._EABR_AceDB.profile end
    local nameFontValues, nameFontOrder = EllesmereUI.BuildFontDropdownData()
    _, h = W:DualRow(parent, y, ModuleOutlineCfg(tile.folder, tile.display), BLANK());  y = y - h
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Name Font",
          values = nameFontValues, order = nameFontOrder,
          getValue = function()
              local p = db()
              return (p and p.display and p.display.nameFont) or "__global"
          end,
          setValue = function(v)
              local p = db(); if not (p and p.display) then return end
              p.display.nameFont = (v ~= "__global") and v or nil
              if _G._EABR_RequestRefresh then _G._EABR_RequestRefresh() end
          end },
        { type = "slider", text = "Name Text Size", min = 6, max = 30, step = 1,
          getValue = function()
              local p = db()
              return (p and p.display and p.display.textSize) or 11
          end,
          setValue = function(v)
              local p = db(); if not (p and p.display) then return end
              p.display.textSize = v
              if _G._EABR_RequestRefresh then _G._EABR_RequestRefresh() end
          end });  y = y - h
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Item Count Font",
          values = nameFontValues, order = nameFontOrder,
          getValue = function()
              local p = db()
              return (p and p.display and p.display.countFont) or "__global"
          end,
          setValue = function(v)
              local p = db(); if not (p and p.display) then return end
              p.display.countFont = (v ~= "__global") and v or nil
              if _G._EABR_RequestRefresh then _G._EABR_RequestRefresh() end
          end },
        { type = "slider", text = "Item Count Text Size", min = 6, max = 30, step = 1,
          getValue = function()
              local p = db()
              return (p and p.display and p.display.countSize) or 16
          end,
          setValue = function(v)
              local p = db(); if not (p and p.display) then return end
              p.display.countSize = v
              if _G._EABR_RequestRefresh then _G._EABR_RequestRefresh() end
          end });  y = y - h
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Mana Warning Font",
          values = nameFontValues, order = nameFontOrder,
          getValue = function()
              local p = db()
              return (p and p.consumables and p.consumables.rcManaWarnFont) or "__global"
          end,
          setValue = function(v)
              local p = db(); if not (p and p.consumables) then return end
              p.consumables.rcManaWarnFont = (v ~= "__global") and v or nil
              if _G._EABR_RCWarnApply then _G._EABR_RCWarnApply() end
          end },
        { type = "slider", text = "Mana Warning Text Size", min = 10, max = 72, step = 1,
          getValue = function()
              local p = db()
              return (p and p.consumables and p.consumables.rcManaWarnSize) or 48
          end,
          setValue = function(v)
              local p = db(); if not (p and p.consumables) then return end
              p.consumables.rcManaWarnSize = v
              if _G._EABR_RCWarnApply then _G._EABR_RCWarnApply() end
          end });  y = y - h
    return y
end

local function TileQoL(parent, y, W, tile)
    local ns = NS(tile.folder)
    local _, h
    if not ns then
        _, h = W:DualRow(parent, y, ModuleOutlineCfg(tile.folder, tile.display), BLANK());  y = y - h
        return NoteRow(parent, y, EllesmereUI.Lf("Enable %1$s to edit its text settings.", EllesmereUI.L(tile.display)))
    end
    -- Flat EllesmereUIDB keys with a parent-published apply fn.
    local function gsize(label, key, minV, maxV, def, applyName)
        return { type = "slider", text = label, min = minV, max = maxV, step = 1,
            getValue = function()
                return (EllesmereUIDB and EllesmereUIDB[key]) or def
            end,
            setValue = function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB[key] = v
                local fn = EllesmereUI[applyName]
                if fn then fn() end
            end }
    end
    local function brDB()
        local d = _G._EUI_BattleRes_DB and _G._EUI_BattleRes_DB()
        return d and d.profile and d.profile.battleRes
    end
    local function brSize(label, key, minV, maxV, def)
        return { type = "slider", text = label, min = minV, max = maxV, step = 1,
            getValue = function()
                local p = brDB()
                return (p and p[key]) or def
            end,
            setValue = function(v)
                local p = brDB(); if not p then return end
                p[key] = v
                if _G._EUI_BattleRes_Apply then _G._EUI_BattleRes_Apply() end
            end }
    end
    local function blDB()
        local d = _G._EUI_BattleRes_DB and _G._EUI_BattleRes_DB()
        return d and d.profile and d.profile.bloodlust
    end
    -- Bloodlust writes its own key but reads through the Battle Res value,
    -- exactly like the module's own sliders.
    local function blSize(label, key, minV, maxV, def)
        return { type = "slider", text = label, min = minV, max = maxV, step = 1,
            getValue = function()
                local bl, br = blDB(), brDB()
                return (bl and bl[key]) or (br and br[key]) or def
            end,
            setValue = function(v)
                local bl = blDB(); if not bl then return end
                bl[key] = v
                if _G._EUI_Bloodlust_Apply then _G._EUI_Bloodlust_Apply() end
            end }
    end
    _, h = W:DualRow(parent, y, ModuleOutlineCfg(tile.folder, tile.display),
        gsize("Map Coordinates Text Size", "mapCoordsTextSize", 8, 24, 12, "_applyMapCoords"));  y = y - h
    _, h = W:DualRow(parent, y,
        gsize("Group Death Alert Text Size", "groupDeathTextSize", 14, 64, 34, "_applyGroupDeathAlert"),
        gsize("Combat Alert Text Size", "combatAlertTextSize", 14, 64, 22, "_applyCombatAlertFrame"));  y = y - h
    _, h = W:DualRow(parent, y,
        { type = "slider", text = "FPS Counter Text Size", min = 8, max = 30, step = 1,
          getValue = function()
              if EllesmereUI.QoLExtrasGet then
                  return EllesmereUI.QoLExtrasGet("fpsTextSize") or 12
              end
              return (EllesmereUIDB and EllesmereUIDB.fpsTextSize) or 12
          end,
          setValue = function(v)
              if EllesmereUI.QoLExtrasSet then EllesmereUI.QoLExtrasSet("fpsTextSize", v) end
              if EllesmereUI._applyFPSDisplay then EllesmereUI._applyFPSDisplay() end
          end },
        gsize("Durability Warning Text Size", "durWarnTextSize", 10, 50, 30, "_durWarnApplySettings"));  y = y - h
    _, h = W:DualRow(parent, y,
        gsize("Target Distance Text Size", "targetDistanceTextSize", 10, 48, 18, "_applyTargetDistanceFrame"),
        { type = "slider", text = "Keystone Popup Text Size", min = 8, max = 16, step = 1,
          getValue = function()
              local t = EllesmereUIDB and EllesmereUIDB.keystonePopup
              return (t and t.textSize) or 11
          end,
          setValue = function(v)
              if not EllesmereUIDB then EllesmereUIDB = {} end
              if not EllesmereUIDB.keystonePopup then EllesmereUIDB.keystonePopup = {} end
              EllesmereUIDB.keystonePopup.textSize = v
              if _G._EUI_RefreshKeystonePopup then _G._EUI_RefreshKeystonePopup() end
          end });  y = y - h
    _, h = W:DualRow(parent, y,
        brSize("Battle Res Duration Size", "durationSize", 8, 30, 12),
        brSize("Battle Res Count Size", "countSize", 8, 20, 11));  y = y - h
    local brFontValues, brFontOrder = EllesmereUI.BuildFontDropdownData()
    _, h = W:DualRow(parent, y,
        brSize("Battle Res Text Size", "textSize", 8, 40, 14),
        { type = "dropdown", text = "Battle Res Font",
          values = brFontValues, order = brFontOrder,
          getValue = function()
              local p = brDB()
              return (p and p.font) or "__global"
          end,
          setValue = function(v)
              local p = brDB(); if not p then return end
              p.font = v
              if _G._EUI_BattleRes_Apply then _G._EUI_BattleRes_Apply() end
          end });  y = y - h
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Battle Res Outline",
          values = { ["__global"] = { text = "EUI Global Default" },
                     ["none"]     = { text = "Drop Shadow" },
                     ["outline"]  = { text = "Outline" },
                     ["thick"]    = { text = "Thick Outline" } },
          order = { "__global", "none", "outline", "thick" },
          getValue = function()
              local p = brDB()
              return (p and p.outlineMode) or "__global"
          end,
          setValue = function(v)
              local p = brDB(); if not p then return end
              p.outlineMode = v
              if _G._EUI_BattleRes_Apply then _G._EUI_BattleRes_Apply() end
          end },
        blSize("Bloodlust Duration Size", "durationSize", 8, 30, 12));  y = y - h
    _, h = W:DualRow(parent, y,
        blSize("Bloodlust Count Size", "countSize", 8, 20, 11),
        { type = "slider", text = "Movement Alert Text Size", min = 8, max = 72, step = 1,
          tooltip = "Sizes the movement alert's free text, bar number and icon countdown. Switching the alert's Display Mode re-seeds this value.",
          getValue = function()
              local d = _G._EUI_MovementAlert_DB and _G._EUI_MovementAlert_DB()
              local ma = d and d.profile and d.profile.movementAlert
              return (ma and ma.textSize) or 24
          end,
          setValue = function(v)
              local d = _G._EUI_MovementAlert_DB and _G._EUI_MovementAlert_DB()
              local ma = d and d.profile and d.profile.movementAlert
              if not ma then return end
              ma.textSize = v
              if EllesmereUI._applyMovementAlert then EllesmereUI._applyMovementAlert() end
              if EllesmereUI._applyTimeSpiral then EllesmereUI._applyTimeSpiral() end
              if EllesmereUI._applyGateway then EllesmereUI._applyGateway() end
          end });  y = y - h
    return y
end

local function TileChat(parent, y, W, tile)
    local ns = NS(tile.folder)
    local _, h
    if not ns then
        _, h = W:DualRow(parent, y, ModuleOutlineCfg(tile.folder, tile.display), BLANK());  y = y - h
        return NoteRow(parent, y, EllesmereUI.Lf("Enable %1$s to edit its text settings.", EllesmereUI.L(tile.display)))
    end
    local ECHAT = ns.ECHAT
    local function db()
        return _G._ECHAT_DB and _G._ECHAT_DB.profile and _G._ECHAT_DB.profile.chat
    end
    local fontValues, fontOrder = EllesmereUI.BuildFontDropdownData()
    -- Edit box picker: same faces plus a "Chat Font" inherit entry first,
    -- mirroring the module's own dropdown.
    local ebValues, ebOrder = EllesmereUI.BuildFontDropdownData()
    ebValues["__chat"] = { text = "Chat Font" }
    table.insert(ebOrder, 1, "__chat")
    local function ChatReload(msg)
        EllesmereUI:ShowConfirmPopup({
            title       = "Reload Required",
            message     = msg,
            confirmText = "Reload Now",
            cancelText  = "Later",
            onConfirm   = function() ReloadUI() end,
        })
    end
    _, h = W:DualRow(parent, y, ModuleOutlineCfg(tile.folder, tile.display),
        { type = "dropdown", text = "Chat Font",
          values = fontValues, order = fontOrder,
          getValue = function()
              local p = db()
              return (p and p.font) or "__global"
          end,
          setValue = function(v)
              local p = db(); if not p then return end
              p.font = v
              ChatReload("Font changed. A UI reload is needed to apply the new font.")
          end });  y = y - h
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Chat Outline Mode",
          values = { ["__global"] = { text = "EUI Global Default" },
                     ["none"]     = { text = "Drop Shadow" },
                     ["outline"]  = { text = "Outline" },
                     ["thick"]    = { text = "Thick Outline" } },
          order = { "__global", "none", "outline", "thick" },
          getValue = function()
              local p = db()
              return (p and p.outlineMode) or "__global"
          end,
          setValue = function(v)
              local p = db(); if not p then return end
              p.outlineMode = v
              ChatReload("Outline mode changed. A UI reload is needed to apply.")
          end },
        { type = "slider", text = "Chat Font Size", min = 8, max = 27, step = 1,
          getValue = function()
              local p = db()
              if p and p.chatFontSize then return p.chatFontSize end
              local cf = _G.ChatFrame1
              if cf and cf.GetFont then
                  local _, fh = cf:GetFont()
                  if fh and fh > 0 then return math.floor(fh + 0.5) end
              end
              return 14
          end,
          setValue = function(v)
              local p = db(); if not p then return end
              p.chatFontSize = v
              if ECHAT and ECHAT.ApplyChatFontSize then ECHAT.ApplyChatFontSize(v) end
          end });  y = y - h
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Tab Font",
          values = fontValues, order = fontOrder,
          getValue = function()
              local p = db()
              return (p and p.tabFont) or "__global"
          end,
          setValue = function(v)
              local p = db(); if not p then return end
              p.tabFont = v
              if ECHAT and ECHAT.ApplyTabAppearance then ECHAT.ApplyTabAppearance() end
              if ECHAT and ECHAT.ApplyTabLayout then ECHAT.ApplyTabLayout() end
          end },
        { type = "slider", text = "Tab Font Size", min = 8, max = 24, step = 1,
          getValue = function()
              local p = db()
              return (p and p.tabFontSize) or 11
          end,
          setValue = function(v)
              local p = db(); if not p then return end
              p.tabFontSize = v
              if ECHAT and ECHAT.ApplyTabAppearance then ECHAT.ApplyTabAppearance() end
              if ECHAT and ECHAT.ApplyTabLayout then ECHAT.ApplyTabLayout() end
          end });  y = y - h
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Edit Box Font",
          values = ebValues, order = ebOrder,
          getValue = function()
              local p = db()
              return (p and p.editBoxFont) or "__chat"
          end,
          setValue = function(v)
              local p = db(); if not p then return end
              p.editBoxFont = v
              if ECHAT and ECHAT.ApplyFonts then ECHAT.ApplyFonts() end
          end },
        { type = "slider", text = "Edit Box Font Size", min = 8, max = 24, step = 1,
          getValue = function()
              local p = db()
              if p and p.editBoxFontSize then return p.editBoxFontSize end
              if FCF_GetChatWindowInfo then
                  local _, sz = FCF_GetChatWindowInfo(1)
                  if sz and sz > 0 then return math.floor(sz + 0.5) end
              end
              return 12
          end,
          setValue = function(v)
              local p = db(); if not p then return end
              p.editBoxFontSize = v
              if ECHAT and ECHAT.ApplyFonts then ECHAT.ApplyFonts() end
          end });  y = y - h
    return y
end

local function TileMythicTimer(parent, y, W, tile)
    local ns = NS(tile.folder)
    local _, h
    if not ns then
        _, h = W:DualRow(parent, y, ModuleOutlineCfg(tile.folder, tile.display), BLANK());  y = y - h
        return NoteRow(parent, y, EllesmereUI.Lf("Enable %1$s to edit its text settings.", EllesmereUI.L(tile.display)))
    end
    local function db() return _G._EMT_AceDB and _G._EMT_AceDB.profile end
    local function MTApply() if _G._EMT_Apply then _G._EMT_Apply() end end
    local function size(label, key, minV, maxV, def, fallbackKey)
        return { type = "slider", text = label, min = minV, max = maxV, step = 1,
            getValue = function()
                local p = db()
                if not p then return def end
                return p[key] or (fallbackKey and p[fallbackKey]) or def
            end,
            setValue = function(v)
                local p = db(); if not p then return end
                p[key] = v
                MTApply()
            end }
    end
    local function subSize(label, getT, minV, maxV, def, key, applyName)
        return { type = "slider", text = label, min = minV, max = maxV, step = 1,
            getValue = function()
                local t = getT()
                return (t and t[key]) or def
            end,
            setValue = function(v)
                local t = getT(); if not t then return end
                t[key] = v
                local fn = ns[applyName]
                if fn then fn() else MTApply() end
            end }
    end
    local function tsb() local p = db(); return p and p.tsb end
    local function tfbT() local p = db(); return p and p.tfb and p.tfb.target end
    local function tfbF() local p = db(); return p and p.tfb and p.tfb.focus end
    local fontValues, fontOrder = EllesmereUI.BuildFontDropdownData()
    _, h = W:DualRow(parent, y, ModuleOutlineCfg(tile.folder, tile.display),
        { type = "dropdown", text = "Timer Font",
          tooltip = "Typeface for the M+ timer clock. Every other Mythic+ text uses the module font.",
          values = fontValues, order = fontOrder,
          getValue = function()
              local p = db()
              return (p and p.timerFont) or "__global"
          end,
          setValue = function(v)
              local p = db(); if not p then return end
              p.timerFont = v
              MTApply()
          end });  y = y - h
    _, h = W:DualRow(parent, y,
        size("Title Size", "titleSize", 8, 24, 16),
        size("Affix Size", "affixSize", 6, 20, 12));  y = y - h
    _, h = W:DualRow(parent, y,
        size("Timer Size", "timerTextSize", 10, 32, 20),
        size("Objectives Size", "objectivesSize", 8, 20, 12));  y = y - h
    _, h = W:DualRow(parent, y,
        size("+3 Threshold Text Size", "thresholdPlusThreeSize", 6, 20, 12, "thresholdSize"),
        size("+2 Threshold Text Size", "thresholdPlusTwoSize", 6, 20, 12, "thresholdSize"));  y = y - h
    _, h = W:DualRow(parent, y,
        size("+1 Threshold Text Size", "thresholdPlusOneSize", 6, 20, 12, "thresholdSize"),
        size("Enemy Forces Text Size", "enemyForcesTextSize", 8, 24, 12, "objectivesSize"));  y = y - h
    _, h = W:DualRow(parent, y,
        subSize("Targeted Bars Name Size", tsb, 6, 20, 10, "nameSize", "TSB_Refresh"),
        subSize("Targeted Bars Timer Size", tsb, 6, 20, 10, "timerSize", "TSB_Refresh"));  y = y - h
    _, h = W:DualRow(parent, y,
        subSize("Targeted Bars Target Size", tsb, 6, 20, 10, "targetSize", "TSB_Refresh"),
        subSize("Target Cast Bar Name Size", tfbT, 6, 22, 11, "nameSize", "TFB_Refresh"));  y = y - h
    _, h = W:DualRow(parent, y,
        subSize("Target Cast Bar Timer Size", tfbT, 6, 22, 11, "timerSize", "TFB_Refresh"),
        subSize("Target Cast Bar Target Size", tfbT, 6, 20, 10, "targetSize", "TFB_Refresh"));  y = y - h
    _, h = W:DualRow(parent, y,
        subSize("Focus Cast Bar Name Size", tfbF, 6, 22, 11, "nameSize", "TFB_Refresh"),
        subSize("Focus Cast Bar Timer Size", tfbF, 6, 22, 11, "timerSize", "TFB_Refresh"));  y = y - h
    _, h = W:DualRow(parent, y,
        subSize("Focus Cast Bar Target Size", tfbF, 6, 20, 10, "targetSize", "TFB_Refresh"), BLANK());  y = y - h
    return y
end

local function TileDamageMeters(parent, y, W, tile)
    local ns = NS(tile.folder)
    local _, h
    if not ns then
        _, h = W:DualRow(parent, y, ModuleOutlineCfg(tile.folder, tile.display), BLANK());  y = y - h
        return NoteRow(parent, y, EllesmereUI.Lf("Enable %1$s to edit its text settings.", EllesmereUI.L(tile.display)))
    end
    local function db()
        return _G._EDM_DB and _G._EDM_DB.profile and _G._EDM_DB.profile.dm
    end
    _, h = W:DualRow(parent, y, ModuleOutlineCfg(tile.folder, tile.display),
        { type = "slider", text = "Header Text Size", min = 8, max = 18, step = 1,
          getValue = function()
              local p = db()
              return (p and p.hdrFontSize) or 11
          end,
          setValue = function(v)
              local p = db(); if not p then return end
              p.hdrFontSize = v
              if ns.ApplyHeader then ns.ApplyHeader() end
          end });  y = y - h
    local function barSize(label, key)
        return { type = "slider", text = label, min = 8, max = 18, step = 1,
            getValue = function()
                local p = db()
                return (p and (p[key] or p.fontSize)) or 11
            end,
            setValue = function(v)
                local p = db(); if not p then return end
                p[key] = v
                if ns.RefreshMeter then ns.RefreshMeter() end
            end }
    end
    _, h = W:DualRow(parent, y,
        barSize("Bar Left Text Size", "leftFontSize"),
        barSize("Bar Right Text Size", "rightFontSize"));  y = y - h
    _, h = W:DualRow(parent, y,
        { type = "slider", text = "Standalone Timer Size", min = 10, max = 40, step = 1,
          getValue = function()
              local p = db()
              return (p and p.standaloneTimerSize) or 26
          end,
          setValue = function(v)
              local p = db(); if not p then return end
              p.standaloneTimerSize = v
              if ns.ApplySATimer then ns.ApplySATimer() end
          end },
        { type = "slider", text = "Spell History Text Size", min = 8, max = 16, step = 1,
          getValue = function()
              local p = db()
              local sh = p and p.spellHistory
              return (sh and sh.textSize) or 11
          end,
          setValue = function(v)
              local p = db(); if not (p and p.spellHistory) then return end
              p.spellHistory.textSize = v
              if ns.ApplySpellHistory then ns.ApplySpellHistory() end
          end });  y = y - h
    return y
end

local function TileBags(parent, y, W, tile)
    local ns = NS(tile.folder)
    local _, h
    if not ns then
        _, h = W:DualRow(parent, y, ModuleOutlineCfg(tile.folder, tile.display), BLANK());  y = y - h
        return NoteRow(parent, y, EllesmereUI.Lf("Enable %1$s to edit its text settings.", EllesmereUI.L(tile.display)))
    end
    local function db()
        return EllesmereUI._bagsDB and EllesmereUI._bagsDB.profile
    end
    local function TextSizes()
        if _G.EUI_Bags and _G.EUI_Bags.RefreshTextSizes then _G.EUI_Bags:RefreshTextSizes() end
        if _G.EUI_BankFrame and _G.EUI_BankFrame.RefreshTextSizes then _G.EUI_BankFrame:RefreshTextSizes() end
    end
    local function size(label, key, minV, maxV, def, applyFn)
        return { type = "slider", text = label, min = minV, max = maxV, step = 1,
            getValue = function()
                local p = db()
                return (p and p[key]) or def
            end,
            setValue = function(v)
                local p = db(); if not p then return end
                p[key] = v
                applyFn()
            end }
    end
    _, h = W:DualRow(parent, y, ModuleOutlineCfg(tile.folder, tile.display),
        size("Category Title Size", "bagCatTitleSize", 8, 16, 11, function()
            if _G.EUI_Bags and _G.EUI_Bags.RefreshInventory then _G.EUI_Bags:RefreshInventory() end
        end));  y = y - h
    _, h = W:DualRow(parent, y,
        size("Item Count Text Size", "bagCountFontSize", 8, 16, 11, TextSizes),
        size("Item Level Text Size", "itemlevelFontSize", 8, 16, 12, TextSizes));  y = y - h
    _, h = W:DualRow(parent, y,
        size("Set Name Text Size", "bagSetNameFontSize", 7, 14, 9, TextSizes),
        size("BoE / Warbound Text Size", "bagBindTypeFontSize", 8, 16, 11, TextSizes));  y = y - h
    return y
end

local function TileMinimap(parent, y, W, tile)
    local ns = NS(tile.folder)
    local _, h
    if not ns then
        _, h = W:DualRow(parent, y, ModuleOutlineCfg(tile.folder, tile.display), BLANK());  y = y - h
        return NoteRow(parent, y, EllesmereUI.Lf("Enable %1$s to edit its text settings.", EllesmereUI.L(tile.display)))
    end
    local function db()
        return _G._EMM_DB and _G._EMM_DB.profile and _G._EMM_DB.profile.minimap
    end
    local function size(label, key, minV, maxV, def)
        return { type = "slider", text = label, min = minV, max = maxV, step = 1,
            getValue = function()
                local p = db()
                return (p and p[key]) or def
            end,
            setValue = function(v)
                local p = db(); if not p then return end
                p[key] = v
                if _G._EMM_ApplyMinimap then _G._EMM_ApplyMinimap() end
            end }
    end
    -- Scale rows apply exactly like the module's own cogs: SetScale on the
    -- text block's host frame, no full minimap reapply.
    local function scale(label, key, def, frameName)
        return { type = "slider", text = label, min = 0.5, max = 2.0, step = 0.01,
            getValue = function()
                local p = db()
                return (p and p[key]) or def
            end,
            setValue = function(v)
                local p = db(); if not p then return end
                p[key] = v
                local f = _G[frameName]
                if f and f.SetScale then f:SetScale(v) end
            end }
    end
    _, h = W:DualRow(parent, y, ModuleOutlineCfg(tile.folder, tile.display),
        size("FPS Text Size", "fpsTextSize", 8, 30, 12));  y = y - h
    _, h = W:DualRow(parent, y,
        size("Difficulty Text Size", "diffTextSize", 8, 24, 12),
        scale("Clock Scale", "clockScale", 1.15, "_EBS_ClockBg"));  y = y - h
    _, h = W:DualRow(parent, y,
        scale("Zone Text Scale", "locationScale", 1.15, "_EBS_LocationBg"),
        scale("Coordinates Scale", "coordsScale", 1.0, "_EBS_CoordFrame"));  y = y - h
    _, h = W:DualRow(parent, y,
        scale("FPS/MS Scale", "fpsScale", 1.0, "_EBS_FpsBg"), BLANK());  y = y - h
    return y
end

local function TileQuestTracker(parent, y, W, tile)
    local ns = NS(tile.folder)
    local _, h
    if not ns then
        _, h = W:DualRow(parent, y, ModuleOutlineCfg(tile.folder, tile.display), BLANK());  y = y - h
        return NoteRow(parent, y, EllesmereUI.Lf("Enable %1$s to edit its text settings.", EllesmereUI.L(tile.display)))
    end
    local function db()
        return _G._EQT_DB and _G._EQT_DB.profile and _G._EQT_DB.profile.questTracker
    end
    local function QTApply()
        local EQT = ns.EQT
        if not EQT then return end
        if EQT.RestyleAll then EQT.RestyleAll() end
        if EQT.UpdateVisibility then EQT.UpdateVisibility() end
        if EQT.ApplyBackground then EQT.ApplyBackground() end
        if EQT.RefreshStateDriver then EQT.RefreshStateDriver() end
    end
    local function size(label, key, def)
        return { type = "slider", text = label, min = 8, max = 24, step = 1,
            getValue = function()
                local p = db()
                return (p and p[key]) or def
            end,
            setValue = function(v)
                local p = db(); if not p then return end
                p[key] = v
                QTApply()
            end }
    end
    local fontValues, fontOrder = EllesmereUI.BuildFontDropdownData()
    _, h = W:DualRow(parent, y, ModuleOutlineCfg(tile.folder, tile.display),
        { type = "dropdown", text = "Quest Tracker Font",
          tooltip = "Typeface for the quest tracker. This module-local pick wins over the module font override above.",
          values = fontValues, order = fontOrder,
          getValue = function()
              local p = db()
              return (p and p.font) or "__global"
          end,
          setValue = function(v)
              local p = db(); if not p then return end
              p.font = v
              FontReload()
          end });  y = y - h
    _, h = W:DualRow(parent, y,
        size("Header Font Size", "headerFontSize", 13),
        size("Title Font Size", "titleFontSize", 12));  y = y - h
    _, h = W:DualRow(parent, y,
        size("Objective Font Size", "objectiveFontSize", 10), BLANK());  y = y - h
    return y
end

local function TileBlizzardSkin(parent, y, W, tile)
    local ns = NS(tile.folder)
    local _, h
    if not ns then
        _, h = W:DualRow(parent, y, ModuleOutlineCfg(tile.folder, tile.display), BLANK());  y = y - h
        return NoteRow(parent, y, EllesmereUI.Lf("Enable %1$s to edit its text settings.", EllesmereUI.L(tile.display)))
    end
    _, h = W:DualRow(parent, y, ModuleOutlineCfg(tile.folder, tile.display),
        { type = "slider", text = "Tooltip Font Size Scale", min = 0.7, max = 1.5, step = 0.05,
          format = "%.0f%%", displayMul = 100,
          tooltip = "Scales the text size of Blizzard tooltips.",
          getValue = function()
              return (EllesmereUIDB and EllesmereUIDB.tooltipFontScale) or 1.0
          end,
          setValue = function(v)
              if not EllesmereUIDB then EllesmereUIDB = {} end
              EllesmereUIDB.tooltipFontScale = v
          end });  y = y - h
    _, h = W:DualRow(parent, y,
        { type = "slider", text = "Enchant Text Size", min = 6, max = 20, step = 1,
          getValue = function()
              return (EllesmereUIDB and EllesmereUIDB.charSheetEnchantSize) or 9
          end,
          setValue = function(v)
              if not EllesmereUIDB then EllesmereUIDB = {} end
              EllesmereUIDB.charSheetEnchantSize = v
              if EllesmereUI._refreshCharSheetSlotLabels then EllesmereUI._refreshCharSheetSlotLabels() end
          end },
        { type = "slider", text = "Dragonriding Speed Text Size", min = 6, max = 32, step = 1,
          getValue = function()
              local p = ns.edrDB and ns.edrDB.profile and ns.edrDB.profile.speedText
              return (p and p.size) or 12
          end,
          setValue = function(v)
              local p = ns.edrDB and ns.edrDB.profile and ns.edrDB.profile.speedText
              if not p then return end
              p.size = v
              if ns.edrRedraw then ns.edrRedraw() end
          end });  y = y - h
    return y
end

local function TileDataBars(parent, y, W, tile)
    local ns = NS(tile.folder)
    local _, h = W:DualRow(parent, y, ModuleOutlineCfg(tile.folder, tile.display), BLANK())
    y = y - h
    if ns then
        y = LinkRow(parent, y, "Text Scale (per data bar)",
            tile.folder, "DataBars", "BAR SETTINGS", "Text Scale")
    else
        y = NoteRow(parent, y, EllesmereUI.Lf("Enable %1$s to edit its text settings.", EllesmereUI.L(tile.display)))
    end
    return y
end

local function TileFontOnly(parent, y, W, tile)
    local _, h = W:DualRow(parent, y, ModuleOutlineCfg(tile.folder, tile.display), BLANK())
    return y - h
end

-- Combat and world text: engine globals that only apply at login, plus the
-- floating combat text scale CVar. The font pickers stay on their original
-- pages (curated list + logout flow); this card mirrors the size and links
-- to the rest.
local function TileCombatText(parent, y, W, tile)
    local _, h = W:DualRow(parent, y,
        { type = "slider", text = "Combat Text Size", min = 0.5, max = 2.5, step = 0.1,
          getValue = function() return tonumber(GetCVar("WorldTextScale_v2")) or 1 end,
          setValue = function(v)
              if InCombatLockdown() then return end
              v = math.floor(v * 10 + 0.5) / 10
              SetCVar("WorldTextScale_v2", v)
          end },
        BLANK());  y = y - h
    y = LinkRow(parent, y, "Combat Text Font (logout required)",
        GLOBAL_KEY, "General", "COMBAT", "Combat Text Font")
    return y
end

-------------------------------------------------------------------------------
--  Card list -- ADDON_ROSTER order (Party Mode is skipped: it has no font
--  consumers and no addon key in the per-module font system), plus the
--  synthetic Combat Text card at the end.
-------------------------------------------------------------------------------

local TILE_BUILDERS = {
    EllesmereUIActionBars        = { TileActionBars,       "Bar button text, XP/Rep bar text" },
    EllesmereUINameplates        = { TileNameplates,       "Names, cast bar and aura text on nameplates" },
    EllesmereUIUnitFrames        = { TileUnitFrames,       "Health, power, cast bar and aura text (per unit)" },
    EllesmereUIRaidFrames        = { TileRaidFrames,       "Names, health and indicator text on raid and party frames" },
    EllesmereUICooldownManager   = { TileCooldownManager,  "Icon duration, stacks, keybinds and tracking bar text" },
    EllesmereUIResourceBars      = { TileResourceBars,     "Health, power, class resource, cast and totem bar text" },
    EllesmereUIAuraBuffReminders = { TileAuraBuffReminders,"Reminder names, item counts and the mana warning" },
    EllesmereUIQoL               = { TileQoL,              "Alerts, trackers, battle res and popup text" },
    EllesmereUIBlizzardSkin      = { TileBlizzardSkin,     "Tooltip text scale, enchant text and dragonriding speed" },
    EllesmereUIFriends           = { TileFontOnly,         "Font face and outline only" },
    EllesmereUIMythicTimer       = { TileMythicTimer,      "M+ timer, objectives, thresholds and spell bar text" },
    EllesmereUIQuestTracker      = { TileQuestTracker,     "Tracker font and per-line text sizes" },
    EllesmereUIMinimap           = { TileMinimap,          "Clock, zone, coordinates, FPS and difficulty text" },
    EllesmereUIChat              = { TileChat,             "Chat windows, tabs and the input field" },
    EllesmereUIDamageMeters      = { TileDamageMeters,     "Window header, bar and timer text" },
    EllesmereUIBags              = { TileBags,             "Item count, item level, category and label text" },
    EllesmereUIDataBars          = { TileDataBars,         "Per-bar text scale" },
    EllesmereUIQuickdraw         = { TileFontOnly,         "Font face and outline only" },
}

local function BuildTileList()
    local tiles = {}
    local roster = EllesmereUI.ADDON_ROSTER or {}
    for _, entry in ipairs(roster) do
        local def = not entry.comingSoon and TILE_BUILDERS[entry.folder]
        if def then
            tiles[#tiles + 1] = {
                key = entry.folder, folder = entry.folder, display = entry.display,
                desc = def[2], buildContent = def[1], hasFontDD = true,
            }
        end
    end
    tiles[#tiles + 1] = {
        key = "combatText", display = "Combat & World Text",
        desc = "Floating combat text and world name text (engine settings)",
        buildContent = TileCombatText, hasFontDD = false,
    }
    return tiles
end

-------------------------------------------------------------------------------
--  Font card (adapted from the Window Skins card pattern)
-------------------------------------------------------------------------------

local FT_ARROW_DOWN = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-arrow-down3.png"
local FT_ARROW_UP   = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-arrow-up3.png"
local FT_HEADER_H   = 54
local FT_CARD_GAP   = 14

local function BuildFontCard(parent, y, W, tile)
    local PP = EllesmereUI.PanelPP
    local EG = EllesmereUI.ELLESMERE_GREEN
    local L  = EllesmereUI.L
    -- A disabled module's card is fully inert (same treatment as settings-less
    -- Window Skins cards): no expand, no header dropdown, no hover -- just a
    -- dimmed header with a tooltip explaining why.
    local enabled = (not tile.folder) or NS(tile.folder) ~= nil
    local expanded = enabled and _ftExpanded[tile.key]
    local cardTop = y
    local brd

    -- Explicit size + single TOPLEFT anchor (the widget contract; see the
    -- Window Skins card for why a second point would zero the width).
    local cardW = parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2
    local hdr = CreateFrame("Button", nil, parent)
    PP.Size(hdr, cardW, FT_HEADER_H)
    PP.Point(hdr, "TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD, y)
    hdr:SetFrameLevel(parent:GetFrameLevel() + 3)

    -- Search metadata: the header acts as its own pseudo-section so searching
    -- the module name lands on the card; the deep-link pre-hook below expands
    -- all cards first.
    local searchName = tile.display .. " " .. (tile.desc or "")
    hdr._isSectionHeader = true
    hdr._sectionName = searchName
    local searchNameLoc = L(tile.display) .. " " .. L(tile.desc or "")
    if searchNameLoc ~= searchName then hdr._sectionNameLoc = searchNameLoc end
    if EllesmereUI._RegisterSearchEntry then
        local titleLoc = L(tile.display)
        local descSearch = tile.desc or ""
        local descLoc = L(tile.desc or "")
        if descLoc ~= descSearch then descSearch = descSearch .. " " .. descLoc end
        EllesmereUI._RegisterSearchEntry(tile.display,
            titleLoc ~= tile.display and titleLoc or nil,
            descSearch,
            EllesmereUI._buildingModule, EllesmereUI._buildingPage,
            searchName, nil, nil, true)
    end

    local hbg = EllesmereUI.SolidTex(hdr, "BACKGROUND", 0, 0, 0, 0)
    hbg:SetAllPoints()

    -- "Aa" glyph rendered in the module's currently resolved face, so the
    -- card shows the active font at a glance.
    local glyph = CreateFrame("Frame", nil, hdr)
    PP.Size(glyph, 26, 20)
    PP.Point(glyph, "LEFT", hdr, "LEFT", 14, 0)
    local glyphText = glyph:CreateFontString(nil, "OVERLAY")
    glyphText:SetPoint("CENTER")
    local addonKey = tile.folder and EllesmereUI._folderToAddonKey and EllesmereUI._folderToAddonKey[tile.folder]
    local glyphPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath(addonKey))
        or "Fonts\\FRIZQT__.TTF"
    glyphText:SetFont(glyphPath, 15, "")
    glyphText:SetTextColor(1, 1, 1, 0.85)
    glyphText:SetText("Aa")

    local title = EllesmereUI.MakeFont(hdr, 14, nil, 1, 1, 1, 0.9)
    PP.Point(title, "TOPLEFT", hdr, "TOPLEFT", 50, -12)
    title:SetText(L(tile.display))

    local desc = EllesmereUI.MakeFont(hdr, 11, nil, 1, 1, 1, 0.42)
    PP.Point(desc, "TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    desc:SetWidth(440)
    desc:SetJustifyH("LEFT")
    desc:SetWordWrap(false)
    desc:SetText(L(tile.desc or ""))

    if not enabled then
        glyphText:SetTextColor(1, 1, 1, 0.3)
        title:SetAlpha(0.4)
        desc:SetAlpha(0.22)
    end

    local chev
    if enabled then
        chev = hdr:CreateTexture(nil, "OVERLAY")
        PP.Size(chev, 16, 16)
        PP.Point(chev, "RIGHT", hdr, "RIGHT", -16, 0)
        chev:SetTexture(expanded and FT_ARROW_UP or FT_ARROW_DOWN)
        chev:SetAlpha(0.45)
        if expanded then chev:SetVertexColor(EG.r, EG.g, EG.b) end
    end

    -- Module font dropdown on the header: the per-module override layer
    -- (the old PER ADDON FONTS entry), editable without expanding the card.
    local dd
    if tile.hasFontDD and enabled then
        local fontValues, fontOrder = EllesmereUI.BuildFontDropdownData()
        dd = EllesmereUI.BuildDropdownControl(hdr, 190, hdr:GetFrameLevel() + 2,
            fontValues, fontOrder,
            function()
                local entry = FindModuleFontEntry(tile.folder)
                return (entry and entry.font) or "__global"
            end,
            function(v)
                local entry = FindModuleFontEntry(tile.folder)
                local cur = (entry and entry.font) or "__global"
                if v == cur then return end
                if v == "__global" then
                    if entry then
                        entry.font = "__global"
                        PruneModuleFontEntry(tile.folder)
                    end
                else
                    EnsureModuleFontEntry(tile.folder, tile.display).font = v
                end
                FontReload()
            end)
        PP.Point(dd, "RIGHT", hdr, "RIGHT", -44, 0)
    end

    local strip
    local function ApplyHeaderHover()
        hbg:SetColorTexture(1, 1, 1, 0.05)
        title:SetAlpha(1)
        if chev then chev:SetAlpha(0.85) end
        if brd then brd:SetColor(1, 1, 1, 0.22) end
    end
    local function ClearHeaderHover()
        if hdr:IsMouseOver() then return end
        hbg:SetColorTexture(0, 0, 0, 0)
        title:SetAlpha(0.9)
        if chev then chev:SetAlpha(0.45) end
        if brd then brd:SetColor(1, 1, 1, expanded and 0.16 or 0.12) end
    end
    if enabled then
        hdr:SetScript("OnEnter", ApplyHeaderHover)
        hdr:SetScript("OnLeave", ClearHeaderHover)
        if dd then
            dd:HookScript("OnEnter", ApplyHeaderHover)
            dd:HookScript("OnLeave", ClearHeaderHover)
        end
        hdr:SetScript("OnClick", function()
            _ftExpanded[tile.key] = not _ftExpanded[tile.key]
            EllesmereUI:RefreshPage(true)
        end)
    else
        local tag = EllesmereUI.MakeFont(hdr, 11, nil, 1, 1, 1)
        tag:SetAlpha(0.3)
        PP.Point(tag, "RIGHT", hdr, "RIGHT", -16, 0)
        tag:SetText(L("Module Disabled"))
        hdr:SetScript("OnEnter", function(self)
            EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.Lf("Enable %1$s to edit these settings.", L(tile.display)))
        end)
        hdr:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
    end

    y = y - FT_HEADER_H

    if expanded then
        local div = hdr:CreateTexture(nil, "ARTWORK")
        div:SetColorTexture(1, 1, 1, 0.07)
        div:SetHeight(1)
        PP.Point(div, "BOTTOMLEFT", hdr, "BOTTOMLEFT", 1, 0)
        PP.Point(div, "BOTTOMRIGHT", hdr, "BOTTOMRIGHT", -1, 0)
        PP.DisablePixelSnap(div)

        y = y - 8
        y = tile.buildContent(parent, y, W, tile)
        y = y - 8
    end

    -- Card background + border spanning header and expanded content (header
    -- child so inline search re-flows it with the header; see WS card notes).
    local bg = CreateFrame("Frame", nil, hdr)
    bg:SetFrameLevel(parent:GetFrameLevel())
    PP.Size(bg, cardW, cardTop - y)
    PP.Point(bg, "TOPLEFT", hdr, "TOPLEFT", 0, 0)
    local fill = EllesmereUI.SolidTex(bg, "BACKGROUND", 0.06, 0.08, 0.10, 0.5)
    fill:SetAllPoints()
    brd = EllesmereUI.MakeBorder(bg, 1, 1, 1, expanded and 0.16 or 0.12, PP)

    strip = bg:CreateTexture(nil, "ARTWORK")
    strip:SetWidth(2)
    if enabled then
        strip:SetColorTexture(EG.r, EG.g, EG.b, 0.7)
    else
        strip:SetColorTexture(1, 1, 1, 0.10)
    end
    PP.Point(strip, "TOPLEFT", hdr, "TOPLEFT", 1, -1)
    PP.Point(strip, "BOTTOMLEFT", hdr, "BOTTOMLEFT", 1, 1)
    if strip.SetSnapToPixelGrid then strip:SetSnapToPixelGrid(false); strip:SetTexelSnappingBias(0) end

    return y - FT_CARD_GAP
end

-------------------------------------------------------------------------------
--  Deep-link pre-hook: expand every card before a jump into the Fonts page,
--  so section scroll/highlight can land inside card content (same pattern as
--  the Window Skins page).
-------------------------------------------------------------------------------
do
    local origNav = EllesmereUI.NavigateToElementSettings
    function EllesmereUI:NavigateToElementSettings(moduleName, pageName, sectionName, preSelectFn, highlightText)
        if moduleName == GLOBAL_KEY and pageName == PAGE_FONTS and (sectionName or highlightText) then
            local changed = false
            for _, tile in ipairs(BuildTileList()) do
                if not _ftExpanded[tile.key] then
                    _ftExpanded[tile.key] = true
                    changed = true
                end
            end
            if changed and EllesmereUI.InvalidatePageCache then
                EllesmereUI:InvalidatePageCache()
            end
        end
        return origNav(self, moduleName, pageName, sectionName, preSelectFn, highlightText)
    end
end

-------------------------------------------------------------------------------
--  Page builder (dispatched from the Global Settings module registration in
--  EUI__General_Options.lua)
-------------------------------------------------------------------------------

function _G._EUI_BuildFontsPage(pageName, parent, yOffset)
    local W = EllesmereUI.Widgets
    local PP = EllesmereUI.PanelPP
    local y = yOffset
    local _, h

    parent._showRowDivider = true

    -- Reverse folder -> addonKey map for the card glyphs (built once).
    if not EllesmereUI._folderToAddonKey then
        local map = {}
        for key, folder in pairs(EllesmereUI._addonKeyToFolder or {}) do
            map[folder] = key
        end
        EllesmereUI._folderToAddonKey = map
    end

    -------------------------------------------------------------------
    --  GLOBAL FONT section (moved from the old Fonts & Colors page)
    -------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "GLOBAL FONT", y);  y = y - h

    -- Glyph-restricted locales (CJK, Cyrillic): most bundled fonts are Latin-only and cannot render the script, so the picker
    -- offers "System Default" plus external SharedMedia fonts (which may carry the right glyphs).
    local localeRestricted = EllesmereUI.LOCALE_FONT_FALLBACK ~= nil
    -- ruRU is only PARTLY restricted: the faces listed in FONT_CYRILLIC carry the full
    -- Cyrillic block (verified cmap), so they are offered as normal entries and
    -- ResolveFontName honours them. CJK keeps the old System-Default-only picker.
    local localeCyrillic = localeRestricted and EllesmereUI.LOCALE_SCRIPT == "cyrillic"

    local fontDropValues = {}
    local fontDropOrder  = {}
    if localeRestricted then
        fontDropValues[EllesmereUI.SYSTEM_FONT_KEY] = { text = "System Default", font = EllesmereUI.LOCALE_FONT_FALLBACK }
        fontDropOrder[#fontDropOrder + 1] = EllesmereUI.SYSTEM_FONT_KEY
        if localeCyrillic then
            -- Cyrillic-capable bundled faces, kept in FONT_ORDER sequence so the
            -- picker matches the Latin-locale ordering. Latin-only bundles stay out.
            local FONT_DIR_CYR = EllesmereUI.MEDIA_PATH .. "fonts\\"
            local sepDone = false
            for _, name in ipairs(EllesmereUI.FONT_ORDER) do
                local cyrFile = name ~= "---" and EllesmereUI.FONT_CYRILLIC[name]
                    and EllesmereUI.FONT_FILES[name]
                if cyrFile then
                    if not sepDone then
                        fontDropOrder[#fontDropOrder + 1] = "---"
                        sepDone = true
                    end
                    fontDropValues[name] = {
                        text = (EllesmereUI.FONT_DISPLAY_NAMES and EllesmereUI.FONT_DISPLAY_NAMES[name]) or name,
                        font = FONT_DIR_CYR .. cyrFile,
                    }
                    fontDropOrder[#fontDropOrder + 1] = name
                end
            end
        else
            -- Expressway is the informed Latin opt-in, using a distinct sentinel key so the untouched default still maps to System Default.
            fontDropValues[EllesmereUI.EXPRESSWAY_FORCED_KEY] = { text = "Expressway (Latin only)",
                font = EllesmereUI.MEDIA_PATH .. "fonts\\Expressway.TTF" }
            fontDropOrder[#fontDropOrder + 1] = EllesmereUI.EXPRESSWAY_FORCED_KEY
        end
        if EllesmereUI.AppendExternalSharedMediaFonts then
            EllesmereUI.AppendExternalSharedMediaFonts(fontDropValues, fontDropOrder)
        end
    else
        -- Blizzard Default first: the client's own standard UI font. The
        -- glyph-restricted branch above skips it (its "System Default" entry
        -- already is the client's own font).
        fontDropValues[EllesmereUI.BLIZZARD_FONT_KEY] = { text = "Blizzard Default",
            font = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF" }
        fontDropOrder[#fontDropOrder + 1] = EllesmereUI.BLIZZARD_FONT_KEY
        fontDropOrder[#fontDropOrder + 1] = "---"
        local FONT_DIR_GLOBAL = EllesmereUI.MEDIA_PATH .. "fonts\\"
        for _, name in ipairs(EllesmereUI.FONT_ORDER) do
            if name == "---" then
                fontDropOrder[#fontDropOrder + 1] = "---"
            else
                local path = EllesmereUI.FONT_BLIZZARD[name]
                    or (FONT_DIR_GLOBAL .. (EllesmereUI.FONT_FILES[name] or "Expressway.TTF"))
                local displayName = (EllesmereUI.FONT_DISPLAY_NAMES and EllesmereUI.FONT_DISPLAY_NAMES[name]) or name
                fontDropValues[name] = { text = displayName, font = path }
                fontDropOrder[#fontDropOrder + 1] = name
            end
        end
        if EllesmereUI.AppendSharedMediaFonts then
            EllesmereUI.AppendSharedMediaFonts(fontDropValues, fontDropOrder, { keyByName = true })
        end
    end

    local outlineModeValues = {
        ["none"]    = { text = "Drop Shadow" },
        ["outline"] = { text = "Outline" },
        ["thick"]   = { text = "Thick Outline" },
    }
    local outlineModeOrder = { "none", "outline", "thick" }

    _, h = W:DualRow(parent, y,
        { type="dropdown", text="Global Font",
          values=fontDropValues, order=fontDropOrder,
          getValue=function()
              local g = EllesmereUI.GetFontsDB().global or "Expressway"
              -- Cyrillic locales list Expressway as a normal entry, so an older
              -- __expressway opt-in collapses onto it (same file) instead of falling
              -- through to System Default and misreporting the active face.
              if localeCyrillic and g == EllesmereUI.EXPRESSWAY_FORCED_KEY then return "Expressway" end
              -- In glyph-restricted locales a stored Latin-only bundled font maps to the System Default entry; a chosen SM font shows as-is.
              if localeRestricted and not fontDropValues[g] then return EllesmereUI.SYSTEM_FONT_KEY end
              return g
          end,
          setValue=function(v)
              EllesmereUI.GetFontsDB().global = v
              local rl = EllesmereUI._widgetRefreshList
              if rl then for i2 = 1, #rl do rl[i2]() end end
              FontReload()
          end },
        { type="dropdown", text="Outline Mode",
          tooltip="Controls the text rendering style used across all UI elements",
          values=outlineModeValues, order=outlineModeOrder,
          getValue=function()
              local v = EllesmereUI.GetFontsDB().outlineMode or "none"
              if v == "shadow" then v = "none" end
              return v
          end,
          setValue=function(v)
              EllesmereUI.GetFontsDB().outlineMode = v
              local rl = EllesmereUI._widgetRefreshList
              if rl then for i2 = 1, #rl do rl[i2]() end end
              FontReload()
          end });  y = y - h

    -- Outline Icon Text: per-module control over icon-overlay text (stack
    -- counts, durations, keybinds). Checked (default) forces a crisp outline; unchecked follows Outline Mode above. Left slot = per-module
    -- checkbox dropdown, right = "Apply to All Game Text".
    if not EllesmereUI._prebuilding then
        local oitItems = {
            { key = "actionBars", label = "Action Bars Icons" },
            { key = "unitFrames", label = "Unit Frames Icons" },
            { key = "cdm",        label = "CDM Icons" },
            { key = "raidFrames", label = "Raid Frames Icons" },
            { key = "bags",       label = "Bags Icons" },
        }
        local oitRow
        oitRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Outline Icon Text",
              tooltip="Forces a crisp outline on icon text (stack counts, durations, keybinds). Uncheck a module to make its icon text follow the Outline Mode setting above instead.",
              values={ ["_placeholder"]="..." }, order={ "_placeholder" },
              getValue=function() return "_placeholder" end,
              setValue=function() end },
            { type="toggle", text="Apply to All Game Text",
              tooltip="Applies your Global Font to Blizzard's default game text (menus, tooltips, quest log, character panes, and more). Requires a UI reload.",
              getValue=function() return EllesmereUI.GetFontsDB().applyToAllGameText == true end,
              setValue=function(v)
                  EllesmereUI.GetFontsDB().applyToAllGameText = v and true or false
                  FontReload()
              end }
        );  y = y - h
        local rgn = oitRow._leftRegion
        if rgn._control then rgn._control:Hide() end
        local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
            rgn, 220, rgn:GetFrameLevel() + 2,
            oitItems,
            function(k)
                local f = EllesmereUI.GetFontsDB()
                local t = (f and f.outlineIconText) or (EllesmereUIDB and EllesmereUIDB.outlineIconText)
                return not (t and t[k] == false)
            end,
            function(k, v)
                -- Per-profile (rides profile export); seed from the legacy account-global table on first write so other modules' choices carry over.
                local f = EllesmereUI.GetFontsDB()
                if type(f.outlineIconText) ~= "table" then
                    local t = {}
                    local seed = EllesmereUIDB and EllesmereUIDB.outlineIconText
                    if type(seed) == "table" then
                        for kk, vv in pairs(seed) do t[kk] = vv end
                    end
                    f.outlineIconText = t
                end
                f.outlineIconText[k] = v and true or false
                -- Reload prompt from setFn, NOT an onChanged callback: a non-nil onChanged re-anchors the open CB dropdown menu absolutely (for page rebuilds), visibly shifting it.
                FontReload()
            end)
        PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
        rgn._control = cbDD
        rgn._lastInline = nil
        EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
    end

    -- Name Font: text floating above characters/NPCs. Independent of
    -- Global Font, modelled on Combat Text Font: both drive a Blizzard global the engine reads once at login (UNIT_NAME_FONT /
    -- DAMAGE_TEXT_FONT), so both need a LOGOUT (not FontReload's reload) and treat "Blizzard Default" as leave-it-alone. Applied in EllesmereUI_Startup.lua.
    local NAME_FONT_DEFAULT = "__default"
    local nameFontValues, nameFontOrder = {}, {}
    do
        -- Same faces as Global Font (SharedMedia included) but a private copy: prepending a default entry to the shared tables would leak into the Global Font list too.
        nameFontValues[NAME_FONT_DEFAULT] = { text = "Blizzard Default", font = "Fonts\\FRIZQT__.TTF" }
        nameFontOrder[1] = NAME_FONT_DEFAULT
        nameFontOrder[2] = "---"
        for _, k in ipairs(fontDropOrder) do
            -- Skip the Blizzard Default sentinel: this list's own "__default"
            -- entry means "leave the engine's name font untouched", which is
            -- the same visual result with the correct do-nothing semantics.
            -- Collapse the separator that followed it so no doubled divider.
            if k ~= EllesmereUI.BLIZZARD_FONT_KEY then
                if k ~= "---" or nameFontOrder[#nameFontOrder] ~= "---" then
                    nameFontOrder[#nameFontOrder + 1] = k
                end
                if k ~= "---" then nameFontValues[k] = fontDropValues[k] end
            end
        end
    end

    -- Never Show Slug: per-profile toggle (rides profile export/import) dropping the SLUG token from every outline (body/icon/aura text,
    -- Outline Mode itself). Off by default; needs reload.
    do
        local nssRow
        nssRow, h = W:DualRow(parent, y,
            { type="toggle", text="Disable Slug Outline",
              tooltip="Slug outline renders higher quality outlines compared to the base WoW outline mode but may make outline effects appear slightly thicker.",
              getValue=function() return EllesmereUI.IsSlugDisabled() end,
              setValue=function(v)
                  EllesmereUI.GetFontsDB().neverShowSlug = v and true or false
                  FontReload()
              end },
            { type="dropdown", text="Name Font",
              -- Coloured inline rather than via tooltipOpts.color, which would tint the explanation red along with the warning.
              tooltip="Sets the font for the names that float above players, NPCs and enemies in the world.\n\nSeparate from Global Font - changing this does not affect the rest of the UI, and Global Font does not affect it.\n\nBlizzard Default leaves the name text completely untouched.\n\n|cffff4d4dRequires a re-log or restart of WoW to take effect.|r",
              values=nameFontValues, order=nameFontOrder,
              getValue=function()
                  local n = EllesmereUI.GetFontsDB().unitNameFont
                  if not n or not nameFontValues[n] then return NAME_FONT_DEFAULT end
                  return n
              end,
              setValue=function(v)
                  local fdb = EllesmereUI.GetFontsDB()
                  -- nil, not the sentinel, so startup code can tell "leave Blizzard alone" without knowing the key.
                  fdb.unitNameFont = (v ~= NAME_FONT_DEFAULT) and v or nil
                  fdb.unitNameFontPath = (v ~= NAME_FONT_DEFAULT)
                      and nameFontValues[v].font or nil
                  -- No apply call: the engine already cached the global, so the change lands next login (same as Combat Text Font).
                  EllesmereUI:ShowConfirmPopup({
                      title       = "Logout Required",
                      message     = "Name font changes require a logout to character select to take effect. This is a WoW engine limitation.",
                      confirmText = "Okay",
                      cancelText  = "Later",
                  })
              end }
        );  y = y - h
    end

    -- Game Text Scale: multiplies Blizzard font-object sizes in the same
    -- login pass as Apply to All Game Text (EllesmereUI.ApplyGlobalFontToGameText)
    -- but works with or without the face swap. 100 = untouched (stored as
    -- nil); the pass runs once from native sizes, so no compounding. The
    -- reload prompt is drag-aware: mid-drag setValues only mark pending
    -- (EllesmereUI._sliderDragging, the same contract CommitInput reads),
    -- and EndDrag's final setValue runs with the counter already cleared,
    -- so one prompt fires per drag -- or immediately for a typed value.
    do
        local gtsPending
        _, h = W:DualRow(parent, y,
            { type="slider", text="Game Text Scale", min=75, max=125, step=5,
              tooltip="Scales the size of Blizzard's default game text (menus, tooltips, quest log, and more). Requires a UI reload.",
              getValue=function() return EllesmereUI.GetFontsDB().gameTextScale or 100 end,
              setValue=function(v)
                  local f = EllesmereUI.GetFontsDB()
                  local changed = (f.gameTextScale or 100) ~= v
                  if changed then
                      f.gameTextScale = v ~= 100 and v or nil
                  end
                  if EllesmereUI._sliderDragging then
                      if changed then gtsPending = true end
                      return
                  end
                  if changed or gtsPending then
                      gtsPending = nil
                      FontReload()
                  end
              end },
            { type="label", text="" });  y = y - h
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h

    -------------------------------------------------------------------
    --  MODULE FONTS -- one expandable card per module. The header dropdown
    --  is the per-module font override; expanded content mirrors the
    --  module's own text settings.
    -------------------------------------------------------------------
    -- Orientation note above the section title: everything on this page is a
    -- write-through mirror, not a separate setting. Sized host + single
    -- TOPLEFT point per the search framework's geometry contract (raw
    -- parent-level regions are invisible to the search and float over
    -- filtered results).
    local introHost = CreateFrame("Frame", nil, parent)
    PP.Size(introHost, parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2, 44)
    -- 10px breathing room above; the host's slack below is trimmed the same
    -- amount so the section title sits tighter under the text.
    introHost:SetPoint("TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD, y - 10)
    local intro = EllesmereUI.MakeFont(introHost, 14, nil, 1, 1, 1, 0.65)
    intro:SetPoint("TOPLEFT", introHost, "TOPLEFT", 0, -2)
    intro:SetPoint("TOPRIGHT", introHost, "TOPRIGHT", 0, -2)
    intro:SetJustifyH("CENTER")
    intro:SetWordWrap(true)
    intro:SetText(EllesmereUI.L("A quick view of every font setting in one place.") .. "\n"
        .. EllesmereUI.L("These are the same settings found on each module's own pages, not separate ones."))
    y = y - 48

    _, h = W:SectionHeader(parent, "MODULE FONTS", y);  y = y - h

    for _, tile in ipairs(BuildTileList()) do
        y = BuildFontCard(parent, y, W, tile)
    end

    -- Framework contract: return the positive total content height
    -- (contentFrame:SetHeight consumes it), never the final negative y.
    return math.abs(y)
end
