if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Textures_Options.lua
--
--  Global Settings > Textures: the centralized textures page, built on the
--  same card layout as the Fonts page. Every control is a WRITE-THROUGH
--  MIRROR of a module's own texture row: same DB key, same stored value
--  format, same apply path (including setter side-writes like absorb opacity
--  re-seeds). Selection-bound families (per tracked bar, per data bar,
--  per indicator) and the border-style pickers (whose setters re-seed
--  color/size/offset companions per site) are link rows instead.
--
--  Statusbar dropdown data: AppendSharedMediaTextures registers consumers BY
--  TABLE IDENTITY in a permanent registry, so this file NEVER hands it fresh
--  throwaway tables per build. Where a module publishes its own registered
--  tables (UF/RF/NP ns.healthBarTextures*, RB _G._ERB_Bar*, DM _G._EDM_Bar*,
--  AB ns.dataBarTextures*, Chat ns.chatBgTextures*, MovementAlert
--  _MovementBarTextures) the mirror re-calls the appender with THOSE tables
--  (identity dedup makes it a sync) and derives fresh display copies, exactly
--  like the module's own options page. Where the registered names/order live
--  in another file's locals (MythicTimer, Dragonriding) the mirror keeps its
--  own memoized triple, registered once per session.
-------------------------------------------------------------------------------

local PAGE_TEXTURES = "Textures"
local GLOBAL_KEY = "_EUIGlobal"

-- Session-only card expand state (never saved).
local _txExpanded = {}

local function NS(folder) return EllesmereUI._ModuleNS and EllesmereUI._ModuleNS[folder] end

-------------------------------------------------------------------------------
--  Statusbar catalogue helpers
-------------------------------------------------------------------------------

-- Own memoized catalogue for sites whose registered tables are unreachable.
-- Built + SM-registered ONCE per session per key; the LibSharedMedia callback
-- keeps the tables current afterwards.
local _ownCat = {}
local function OwnBarCatalogue(key, includeExtras)
    local c = _ownCat[key]
    if not c then
        local tex, names, order = EllesmereUI.BuildBarTextureTables(includeExtras)
        if EllesmereUI.AppendSharedMediaTextures then
            EllesmereUI.AppendSharedMediaTextures(names, order, nil, tex)
        end
        c = { lookup = tex, names = names, order = order }
        _ownCat[key] = c
    end
    return c
end

-- Fresh per-build display copy of a catalogue (values/order), mirroring the
-- module options pages: values maps key -> display name, order is copied with
-- the site's own separator policy, and _menuOpts paints the texture preview.
local function CopyBarDD(names, order, lookup, dropSep, bgFn)
    local values, ord = {}, {}
    for _, key in ipairs(order or {}) do
        if key == "---" then
            if not dropSep then ord[#ord + 1] = "---" end
        else
            values[key] = (names and names[key]) or key
            ord[#ord + 1] = key
        end
    end
    values._menuOpts = {
        itemHeight = 28,
        background = bgFn or function(key) return lookup and lookup[key] end,
    }
    return values, ord
end

-- Append the SharedMedia tail of a module's registered order onto hand-built
-- style lists (the absorb-style pattern shared by UF, RF and NP).
local function AppendSmTail(values, orders, moduleNames, moduleOrder)
    local smKeys = {}
    for _, k in ipairs(moduleOrder or {}) do
        if type(k) == "string" and k:find("^sm:") then
            smKeys[#smKeys + 1] = k
            values[k] = (moduleNames and moduleNames[k]) or k
        end
    end
    if #smKeys > 0 then
        for _, ord in ipairs(orders) do
            ord[#ord + 1] = "---"
            for _, k in ipairs(smKeys) do ord[#ord + 1] = k end
        end
    end
end

-------------------------------------------------------------------------------
--  Shared row helpers (same shapes as the Fonts page)
-------------------------------------------------------------------------------

local function BLANK() return { type = "label", text = "" } end

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

-- Lf with a placeholder rather than a ".." chain: L() is an exact lookup, so
-- "Enable " .. display .. " ..." can never be keyed and the note would stay
-- English on every localized client. The card header tooltip below already
-- does it this way ("Enable %1$s to edit these settings.").
local function DisabledTile(parent, y, W, tile)
    return NoteRow(parent, y, EllesmereUI.Lf("Enable %1$s to edit its texture settings.", EllesmereUI.L(tile.display)))
end

-------------------------------------------------------------------------------
--  Per-module card content builders
-------------------------------------------------------------------------------

local function TileActionBars(parent, y, W, tile)
    local ns = NS(tile.folder)
    if not ns then return DisabledTile(parent, y, W, tile) end
    local EAB = ns.EAB
    if EllesmereUI.AppendSharedMediaTextures then
        EllesmereUI.AppendSharedMediaTextures(ns.dataBarTextureNames or {}, ns.dataBarTextureOrder or {}, nil, ns.dataBarTextures)
    end
    local lookup = ns.dataBarTextures or {}
    -- AB's own preview resolves sm: keys through ResolveTexturePath.
    local values, order = CopyBarDD(ns.dataBarTextureNames, ns.dataBarTextureOrder, lookup, false,
        function(key)
            if not key or key == "---" or key == "none" then return nil end
            return EllesmereUI.ResolveTexturePath and EllesmereUI.ResolveTexturePath(lookup, key, nil)
        end)
    local function barTexCfg(label, barKey)
        return { type = "dropdown", text = label, values = values, order = order,
            getValue = function()
                local bars = EAB and EAB.db and EAB.db.profile and EAB.db.profile.bars
                local s = bars and bars[barKey]
                return (s and s.barTexture) or "none"
            end,
            setValue = function(v)
                local bars = EAB and EAB.db and EAB.db.profile and EAB.db.profile.bars
                local s = bars and bars[barKey]
                if not s then return end
                s.barTexture = v
                if ns.ApplyDataBarLayout then ns.ApplyDataBarLayout(barKey) end
            end }
    end
    local _, h = W:DualRow(parent, y,
        barTexCfg("XP Bar Texture", "XPBar"),
        barTexCfg("Reputation Bar Texture", "RepBar"));  y = y - h
    _, h = W:DualRow(parent, y,
        barTexCfg("House Favor Bar Texture", "FavorBar"), BLANK());  y = y - h
    y = LinkRow(parent, y, "Bar & Button Border Styles",
        tile.folder, "Bar Display", nil, "Border Style")
    return y
end

local function TileNameplates(parent, y, W, tile)
    local ns = NS(tile.folder)
    if not ns then return DisabledTile(parent, y, W, tile) end
    local function db() return ns.db and ns.db.profile end
    local DEF = ns.defaults or {}
    if EllesmereUI.AppendSharedMediaTextures then
        EllesmereUI.AppendSharedMediaTextures(ns.healthBarTextureNames or {}, ns.healthBarTextureOrder or {}, nil, ns.healthBarTextures)
    end
    local hbtValues, hbtOrder = CopyBarDD(ns.healthBarTextureNames, ns.healthBarTextureOrder, ns.healthBarTextures, false)
    -- Health + cast bar textures repaint live plates the way the module's own
    -- RefreshAllTextures does: full reapply plus the friendly-plate loop.
    local function NPTexApply()
        if ns.RefreshAllSettings then ns.RefreshAllSettings() end
        if ns.friendlyPlates then
            for _, pl in pairs(ns.friendlyPlates) do
                if ns.ApplyHealthBarTexture then ns.ApplyHealthBarTexture(pl) end
                if ns.ApplyCastBarTexture then ns.ApplyCastBarTexture(pl) end
            end
        end
    end
    local function texCfg(label, key)
        return { type = "dropdown", text = label, values = hbtValues, order = hbtOrder,
            getValue = function()
                local p = db()
                return (p and p[key]) or DEF[key] or "none"
            end,
            setValue = function(v)
                local p = db(); if not p then return end
                p[key] = v
                NPTexApply()
            end }
    end

    -- Absorb style: hand list + SM tail, alpha side-write, exactly like the
    -- module row (values/keys shared with the stripe-overlay set).
    local absorbStyleValues = {
        ["blizzard"] = "Blizzard",
        ["striped"] = "Striped",
        ["striped-v2"] = "Stripes",
        ["striped-wide-v2"] = "Wide Stripes",
        ["stripes-medium"] = "Medium Stripes",
        ["stripes-small-close"] = "Small Dense Stripes",
        ["stripes-small-spread"] = "Small Spread Stripes",
        ["striped-tiny"] = "Tiny Stripes",
        ["clean"] = "Clean (Flat)",
    }
    local absorbStyleOrder = {
        "blizzard", "striped",
        "striped-v2", "striped-wide-v2", "stripes-medium",
        "stripes-small-close", "stripes-small-spread", "striped-tiny",
        "clean",
    }
    AppendSmTail(absorbStyleValues, { absorbStyleOrder }, ns.healthBarTextureNames, ns.healthBarTextureOrder)
    absorbStyleValues._menuOpts = {
        itemHeight = 28,
        background = function(key)
            if not key or key == "---" then return nil end
            return (ns.NP_ABSORB_STYLE_TEX and ns.NP_ABSORB_STYLE_TEX[key])
                or (ns.ResolveOverlayTexPath and ns.ResolveOverlayTexPath(key))
        end,
    }

    -- Target/Focus overlay list: stripes first, then the full bar catalogue
    -- (including its "none"); Hover variant leads with "none" and skips the
    -- catalogue's duplicate.
    local STRIPE_ORDER = { "striped-v2", "striped-wide-v2", "stripes-medium", "stripes-small-close", "stripes-small-spread", "striped-tiny" }
    local STRIPE_NAMES = {
        ["striped-v2"] = "Stripes", ["striped-wide-v2"] = "Wide Stripes",
        ["stripes-medium"] = "Medium Stripes", ["stripes-small-close"] = "Small Dense Stripes",
        ["stripes-small-spread"] = "Small Spread Stripes", ["striped-tiny"] = "Tiny Stripes",
    }
    local function OverlayBg(key)
        if not key or key == "---" or key == "none" then return nil end
        if ns.OVERLAY_STRIPE_KEYS and ns.OVERLAY_STRIPE_KEYS[key] and ns.ResolveOverlayTexPath then
            return ns.ResolveOverlayTexPath(key)
        end
        return ns.healthBarTextures and ns.healthBarTextures[key]
    end
    local ovtValues, ovtOrder = {}, {}
    for _, k in ipairs(STRIPE_ORDER) do
        ovtValues[k] = STRIPE_NAMES[k]
        ovtOrder[#ovtOrder + 1] = k
    end
    ovtOrder[#ovtOrder + 1] = "---"
    for _, k in ipairs(hbtOrder) do
        ovtOrder[#ovtOrder + 1] = k
        if k ~= "---" then ovtValues[k] = hbtValues[k] end
    end
    ovtValues._menuOpts = { itemHeight = 28, background = OverlayBg }
    local hovValues, hovOrder = {}, {}
    hovValues.none = "None"
    hovOrder[1] = "none"
    hovOrder[2] = "---"
    for _, k in ipairs(STRIPE_ORDER) do
        hovValues[k] = STRIPE_NAMES[k]
        hovOrder[#hovOrder + 1] = k
    end
    hovOrder[#hovOrder + 1] = "---"
    for _, k in ipairs(hbtOrder) do
        if k ~= "none" then
            hovOrder[#hovOrder + 1] = k
            if k ~= "---" then hovValues[k] = hbtValues[k] end
        end
    end
    hovValues._menuOpts = { itemHeight = 28, background = OverlayBg }

    local function overlayCfg(label, key, applyName)
        return { type = "dropdown", text = label,
            values = (key == "hoverOverlayTexture") and hovValues or ovtValues,
            order = (key == "hoverOverlayTexture") and hovOrder or ovtOrder,
            getValue = function()
                local p = db()
                return (p and p[key]) or DEF[key]
            end,
            setValue = function(v)
                local p = db(); if not p then return end
                p[key] = v
                local fn = ns[applyName]
                if fn then fn() elseif ns.RefreshAllSettings then ns.RefreshAllSettings() end
            end }
    end

    local _, h = W:DualRow(parent, y,
        texCfg("Bar Texture", "healthBarTexture"),
        texCfg("Cast Bar Texture", "castBarTexture"));  y = y - h
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Absorb Style", values = absorbStyleValues, order = absorbStyleOrder,
          getValue = function()
              local p = db()
              return (p and p.absorbStyle) or "blizzard"
          end,
          setValue = function(v)
              local p = db(); if not p then return end
              p.absorbStyle = v
              p.absorbAlpha = math.floor((((ns.NP_ABSORB_STYLE_ALPHA and ns.NP_ABSORB_STYLE_ALPHA[v]) or 0.8) * 100) + 0.5)
              if ns.ApplyAbsorbStyleAll then ns.ApplyAbsorbStyleAll() end
          end },
        overlayCfg("Hover Texture", "hoverOverlayTexture", "RefreshHoverEffect"));  y = y - h
    _, h = W:DualRow(parent, y,
        overlayCfg("Target Texture", "targetOverlayTexture", "RefreshAllSettings"),
        overlayCfg("Focus Texture", "focusOverlayTexture", "RefreshAllSettings"));  y = y - h
    y = LinkRow(parent, y, "Custom Border Style",
        tile.folder, "Display", "STYLE", "Custom Border Style")
    return y
end

local function TileUnitFrames(parent, y, W, tile)
    local ns = NS(tile.folder)
    if not ns then return DisabledTile(parent, y, W, tile) end
    local function db() return ns.db and ns.db.profile end
    if EllesmereUI.AppendSharedMediaTextures then
        EllesmereUI.AppendSharedMediaTextures(ns.healthBarTextureNames or {}, ns.healthBarTextureOrder or {}, nil, ns.healthBarTextures)
    end
    -- UF's own dropdown copy drops the separator.
    local hbtValues, hbtOrder = CopyBarDD(ns.healthBarTextureNames, ns.healthBarTextureOrder, ns.healthBarTextures, true)

    local absorbStyleValues = {
        ["none"]            = "None",
        ["striped"]         = "Striped",
        ["stripedReversed"] = "Striped Reversed",
        ["stripedThick"]    = "Striped Thick",
        ["stripedThickR"]   = "Striped Thick Reversed",
        ["clean"]           = "Clean (Flat)",
        ["blizzard"]        = "Blizzard",
        ["largeOutlinedStripes"]  = "Large Outlined Stripes",
        ["largeOutlinedStripesR"] = "Large Outlined Stripes R",
        ["largeStripes"]          = "Large Stripes",
        ["largeStripesR"]         = "Large Stripes R",
    }
    local absorbStyleOrder = { "none", "striped", "stripedReversed", "stripedThick", "stripedThickR", "clean", "blizzard", "largeStripes", "largeStripesR" }
    local healAbsorbStyleOrder = { "none", "striped", "stripedReversed", "stripedThick", "stripedThickR", "clean", "blizzard", "largeOutlinedStripes", "largeOutlinedStripesR", "largeStripes", "largeStripesR" }
    AppendSmTail(absorbStyleValues, { absorbStyleOrder, healAbsorbStyleOrder }, ns.healthBarTextureNames, ns.healthBarTextureOrder)
    absorbStyleValues._menuOpts = {
        itemHeight = 28,
        background = function(key)
            if not key or key == "---" or key == "none" then return nil end
            return ns.ResolveAbsorbStyleTex and ns.ResolveAbsorbStyleTex(key) or nil
        end,
    }

    local UNITS = { "player", "target", "focus" }
    local UNIT_LABEL = { player = "Player", target = "Target", focus = "Focus" }
    local function unitTable(u)
        local p = db()
        return p and p[u]
    end
    local function UFReload()
        if ns.ReloadFrames then ns.ReloadFrames() end
    end
    local function barTexCfg(u)
        return { type = "dropdown", text = UNIT_LABEL[u] .. " Bar Texture",
            values = hbtValues, order = hbtOrder,
            getValue = function()
                local ut, p = unitTable(u), db()
                return (ut and ut.healthBarTexture) or (p and p.healthBarTexture) or "none"
            end,
            setValue = function(v)
                local ut = unitTable(u); if not ut then return end
                ut.healthBarTexture = v
                UFReload()
            end }
    end
    local function absorbCfg(u)
        return { type = "dropdown", text = UNIT_LABEL[u] .. " Absorb Style",
            values = absorbStyleValues, order = absorbStyleOrder,
            getValue = function()
                local ut = unitTable(u)
                return (ut and ut.showPlayerAbsorb) or "none"
            end,
            setValue = function(v)
                local ut = unitTable(u); if not ut then return end
                ut.absorbOpacity = (v == "clean") and 30 or 90
                ut.showPlayerAbsorb = v
                UFReload()
            end }
    end
    local function healAbsorbCfg(u)
        return { type = "dropdown", text = UNIT_LABEL[u] .. " Heal Absorb Style",
            values = absorbStyleValues, order = healAbsorbStyleOrder,
            getValue = function()
                local ut = unitTable(u)
                return (ut and ut.healAbsorbStyle) or "clean"
            end,
            setValue = function(v)
                local ut = unitTable(u); if not ut then return end
                ut.healAbsorbOpacity = (v == "clean") and 50 or 75
                ut.healAbsorbStyle = v
                UFReload()
            end }
    end
    local _, h = W:DualRow(parent, y, barTexCfg("player"), barTexCfg("target"));  y = y - h
    _, h = W:DualRow(parent, y, barTexCfg("focus"), absorbCfg("player"));  y = y - h
    _, h = W:DualRow(parent, y, absorbCfg("target"), absorbCfg("focus"));  y = y - h
    _, h = W:DualRow(parent, y, healAbsorbCfg("player"), healAbsorbCfg("target"));  y = y - h
    _, h = W:DualRow(parent, y, healAbsorbCfg("focus"), BLANK());  y = y - h
    y = LinkRow(parent, y, "Pet, Target-of-Target & Boss Bar Textures",
        tile.folder, "Mini Frames", "DISPLAY", "Bar Texture")
    y = LinkRow(parent, y, "Frame, Power & Aura Border Styles",
        tile.folder, "Main Frames", "DISPLAY", "Border Style")
    return y
end

local function TileRaidFrames(parent, y, W, tile)
    local ns = NS(tile.folder)
    if not ns then return DisabledTile(parent, y, W, tile) end
    local function db() return ns.db and ns.db.profile end
    if EllesmereUI.AppendSharedMediaTextures then
        EllesmereUI.AppendSharedMediaTextures(ns.healthBarTextureNames or {}, ns.healthBarTextureOrder or {}, nil, ns.healthBarTextures)
    end
    -- RF's own copy keeps the separator in the order array.
    local hbtValues, hbtOrder = CopyBarDD(ns.healthBarTextureNames, ns.healthBarTextureOrder, ns.healthBarTextures, false)
    local function RFReload()
        if ns.ReloadFrames then ns.ReloadFrames() end
        if ns.ReloadPartyFrames then ns.ReloadPartyFrames() end
    end

    local absorbStyleValues = {
        ["none"]            = "None",
        ["striped"]         = "Striped",
        ["stripedReversed"] = "Striped Reversed",
        ["stripedThick"]    = "Striped Thick",
        ["stripedThickR"]   = "Striped Thick Reversed",
        ["clean"]           = "Clean (Flat)",
        ["blizzard"]        = "Classic WoW",
        ["blizzardModern"]  = "Default Blizz Frames",
        ["healBlizzModern"] = "Default Blizz Frames",
        ["largeOutlinedStripes"]  = "Large Outlined Stripes",
        ["largeOutlinedStripesR"] = "Large Outlined Stripes R",
        ["largeStripes"]          = "Large Stripes",
        ["largeStripesR"]         = "Large Stripes R",
        ["maxHealthStripes"]      = "Max Health Stripes",
    }
    local absorbStyleOrder = { "none", "striped", "stripedReversed", "stripedThick", "stripedThickR", "clean", "blizzard", "blizzardModern", "largeStripes", "largeStripesR" }
    local healAbsorbStyleOrder = { "none", "striped", "stripedReversed", "stripedThick", "stripedThickR", "clean", "blizzard", "healBlizzModern", "largeOutlinedStripes", "largeOutlinedStripesR", "largeStripes", "largeStripesR" }
    local maxHealthStyleOrder = { "none", "maxHealthStripes", "striped", "stripedReversed", "stripedThick", "stripedThickR", "clean", "blizzard", "healBlizzModern", "largeOutlinedStripes", "largeOutlinedStripesR", "largeStripes", "largeStripesR" }
    AppendSmTail(absorbStyleValues, { absorbStyleOrder, healAbsorbStyleOrder, maxHealthStyleOrder }, ns.healthBarTextureNames, ns.healthBarTextureOrder)
    absorbStyleValues._menuOpts = {
        itemHeight = 28,
        background = function(key)
            if not key or key == "---" or key == "none" then return nil end
            if key == "blizzardModern" then return ns.ResolveAbsorbStyleTex and ns.ResolveAbsorbStyleTex("striped") end
            if key == "maxHealthStripes" then return "Interface\\AddOns\\EllesmereUIRaidFrames\\Media\\striped-maxhp.png" end
            return ns.ResolveAbsorbStyleTex and ns.ResolveAbsorbStyleTex(key) or nil
        end,
    }

    -- Mirrors write the RAID keys (same as the Frames tab); the Party tab's
    -- unsynced party_ variants stay in the module and are linked below.
    local _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Health Bar Texture", values = hbtValues, order = hbtOrder,
          getValue = function()
              local p = db()
              return (p and p.healthBarTexture) or "atrocity"
          end,
          setValue = function(v)
              local p = db(); if not p then return end
              p.healthBarTexture = v
              if ns._BumpAbsorbGen then ns._BumpAbsorbGen() end
              RFReload()
          end },
        { type = "dropdown", text = "Absorb Style", values = absorbStyleValues, order = absorbStyleOrder,
          getValue = function()
              local p = db()
              return (p and p.absorbStyle) or "none"
          end,
          setValue = function(v)
              local p = db(); if not p then return end
              p.absorbStyle = v
              if v == "clean" then
                  p.absorbOpacity = 30
              elseif v ~= "blizzardModern" then
                  p.absorbOpacity = 90
              end
              RFReload()
          end });  y = y - h
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Heal Absorb Style", values = absorbStyleValues, order = healAbsorbStyleOrder,
          getValue = function()
              local p = db()
              return (p and p.healAbsorbStyle) or "clean"
          end,
          setValue = function(v)
              local p = db(); if not p then return end
              p.healAbsorbStyle = v
              p.healAbsorbOpacity = (v == "clean") and 50 or 75
              RFReload()
          end },
        { type = "dropdown", text = "Max Health Style", values = absorbStyleValues, order = maxHealthStyleOrder,
          getValue = function()
              local p = db()
              return (p and p.maxHealthStyle) or "maxHealthStripes"
          end,
          setValue = function(v)
              local p = db(); if not p then return end
              p.maxHealthStyle = v
              RFReload()
          end });  y = y - h
    y = LinkRow(parent, y, "Party-Specific Textures",
        tile.folder, "Party", "HEALTH BAR", "Health Bar Texture")
    y = LinkRow(parent, y, "Frame Border Style",
        tile.folder, "Frames", "FRAME DISPLAY", "Border Style")
    return y
end

local function TileCooldownManager(parent, y, W, tile)
    local ns = NS(tile.folder)
    if not ns then return DisabledTile(parent, y, W, tile) end
    y = LinkRow(parent, y, "Tracking Bar Texture & Border (per bar)",
        tile.folder, "Tracking Bars", "BAR LAYOUT", "Bar Texture")
    y = LinkRow(parent, y, "Icon Border Styles (per bar)",
        tile.folder, "CDM Bars", "ICON DISPLAY", "Border Style")
    return y
end

local function TileResourceBars(parent, y, W, tile)
    local ns = NS(tile.folder)
    if not ns then return DisabledTile(parent, y, W, tile) end
    local function db() return _G._ERB_AceDB and _G._ERB_AceDB.profile end
    local function RBApply() if _G._ERB_Apply then _G._ERB_Apply() end end
    if EllesmereUI.AppendSharedMediaTextures then
        EllesmereUI.AppendSharedMediaTextures(_G._ERB_BarTextureNames or {}, _G._ERB_BarTextureOrder or {}, nil, _G._ERB_BarTextures)
        EllesmereUI.AppendSharedMediaTextures(_G._ERB_CastBarTextureNames or {}, _G._ERB_CastBarTextureOrder or {}, nil, _G._ERB_CastBarTextures)
    end
    local barValues, barOrder = CopyBarDD(_G._ERB_BarTextureNames, _G._ERB_BarTextureOrder, _G._ERB_BarTextures, false)
    local gcdValues, gcdOrder = CopyBarDD(_G._ERB_BarTextureNames, _G._ERB_BarTextureOrder, _G._ERB_BarTextures, false)
    -- Cast bar tables carry the module-side "blizzard" ATLAS entry.
    local castValues, castOrder = CopyBarDD(_G._ERB_CastBarTextureNames, _G._ERB_CastBarTextureOrder, _G._ERB_CastBarTextures, false)
    local _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Bar Texture", values = barValues, order = barOrder,
          tooltip = "Texture for the health, power and class resource bars.",
          getValue = function()
              local p = db()
              return (p and p.general and p.general.barTexture) or "none"
          end,
          setValue = function(v)
              local p = db(); if not (p and p.general) then return end
              p.general.barTexture = v
              RBApply()
          end },
        { type = "dropdown", text = "Cast Bar Texture", values = castValues, order = castOrder,
          getValue = function()
              local p = db()
              return (p and p.castBar and p.castBar.texture) or "none"
          end,
          setValue = function(v)
              local p = db(); if not (p and p.castBar) then return end
              p.castBar.texture = v
              RBApply()
              if EllesmereUI.NotifyElementResized then EllesmereUI.NotifyElementResized("ERB_CastBar") end
          end });  y = y - h
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "GCD Bar Texture", values = gcdValues, order = gcdOrder,
          getValue = function()
              local p = db()
              return (p and p.gcdBar and p.gcdBar.texture) or "none"
          end,
          setValue = function(v)
              local p = db(); if not (p and p.gcdBar) then return end
              p.gcdBar.texture = v
              RBApply()
              if EllesmereUI.NotifyElementResized then EllesmereUI.NotifyElementResized("ERB_GCDBar") end
          end },
        BLANK());  y = y - h
    y = LinkRow(parent, y, "Border Styles (per bar)",
        tile.folder, "Class, Power and Health Bars", nil, "Border Style")
    return y
end

local function TileChat(parent, y, W, tile)
    local ns = NS(tile.folder)
    if not ns then return DisabledTile(parent, y, W, tile) end
    local ECHAT = ns.ECHAT
    local function db()
        return _G._ECHAT_DB and _G._ECHAT_DB.profile and _G._ECHAT_DB.profile.chat
    end
    if ECHAT and ECHAT.RefreshBgTextureCatalogue then ECHAT.RefreshBgTextureCatalogue() end
    -- Chat's own copies drop the separator.
    local btValues, btOrder = CopyBarDD(ns.chatBgTextureNames, ns.chatBgTextureOrder, ns.chatBgTextures, true)
    local tabValues, tabOrder = CopyBarDD(ns.chatBgTextureNames, ns.chatBgTextureOrder, ns.chatBgTextures, true)
    local _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Background Texture", values = btValues, order = btOrder,
          tooltip = "Texture drawn over the chat background color.",
          getValue = function()
              local p = db()
              return (p and p.bgTexture) or "none"
          end,
          setValue = function(v)
              local p = db(); if not p then return end
              p.bgTexture = v
              if ECHAT and ECHAT.ApplyBackground then ECHAT.ApplyBackground() end
          end },
        { type = "dropdown", text = "Tab Texture", values = tabValues, order = tabOrder,
          tooltip = "Texture drawn over the tab background colors.",
          getValue = function()
              local p = db()
              return (p and p.tabBackgroundTexture) or "none"
          end,
          setValue = function(v)
              local p = db(); if not p then return end
              p.tabBackgroundTexture = v
              if ECHAT and ECHAT.ApplyTabAppearance then ECHAT.ApplyTabAppearance() end
          end });  y = y - h
    y = LinkRow(parent, y, "Panel & Tab Border Styles",
        tile.folder, "Chat", "DISPLAY", "Border Style")
    return y
end

local function TileQoL(parent, y, W, tile)
    local ns = NS(tile.folder)
    if not ns then return DisabledTile(parent, y, W, tile) end
    -- Movement alert bar texture: module-owned registered tables.
    local mt = EllesmereUI._MovementBarTextures
    local maCfg
    if mt then
        if EllesmereUI.AppendSharedMediaTextures then
            EllesmereUI.AppendSharedMediaTextures(mt.names, mt.order, nil, mt.lookup)
        end
        local values, order = CopyBarDD(mt.names, mt.order, mt.lookup, false)
        maCfg = { type = "dropdown", text = "Movement Alert Bar Texture", values = values, order = order,
            tooltip = "Used by the movement alert's Bar display mode.",
            getValue = function()
                local d = _G._EUI_MovementAlert_DB and _G._EUI_MovementAlert_DB()
                local ma = d and d.profile and d.profile.movementAlert
                return (ma and ma.barTexture) or "none"
            end,
            setValue = function(v)
                local d = _G._EUI_MovementAlert_DB and _G._EUI_MovementAlert_DB()
                local ma = d and d.profile and d.profile.movementAlert
                if not ma then return end
                ma.barTexture = v
                if EllesmereUI._applyMovementAlert then EllesmereUI._applyMovementAlert() end
                if EllesmereUI._applyTimeSpiral then EllesmereUI._applyTimeSpiral() end
                if EllesmereUI._applyGateway then EllesmereUI._applyGateway() end
            end }
    end

    -- Cursor art pickers: bespoke ring art, hand-built lists mirroring the
    -- Cursor page exactly (note the ring_ prefix difference between the
    -- cursor texture and the two ring pickers).
    local function cursorDB() return _G._ECL_AceDB and _G._ECL_AceDB.profile end
    local cursorCfg = { type = "dropdown", text = "Cursor Texture",
        values = { ring_normal = "Ring Normal", ring_light = "Ring Light", custom = "Ellesmere Logo",
                   ring_thin = "Ring Thin", ring_heavy = "Ring Heavy", ring_thick = "Ring Thick" },
        order = { "ring_normal", "ring_light", "custom", "---", "ring_thin", "ring_heavy", "ring_thick" },
        getValue = function()
            local p = cursorDB()
            return (p and p.texture) or "ring_normal"
        end,
        setValue = function(v)
            local p = cursorDB(); if not p then return end
            p.texture = v
            if _G._ECL_Apply then _G._ECL_Apply() end
        end }
    local ringValues = { normal = "Ring Normal", light = "Ring Light", thin = "Ring Thin", heavy = "Ring Heavy", thick = "Ring Thick" }
    local ringOrder = { "normal", "light", "---", "thin", "heavy", "thick" }
    local gcdRingCfg = { type = "dropdown", text = "GCD Ring Texture", values = ringValues, order = ringOrder,
        getValue = function()
            local p = cursorDB()
            local g = p and p.gcd
            return (g and g.ringTex) or "light"
        end,
        setValue = function(v)
            local p = cursorDB()
            local g = p and p.gcd
            if not g then return end
            g.ringTex = v
            if _G._ECL_ApplyGCDCircle then _G._ECL_ApplyGCDCircle() end
            if _G._ECL_RegisterUnlock then _G._ECL_RegisterUnlock() end
        end }
    local castRingCfg = { type = "dropdown", text = "Cast Ring Texture", values = ringValues, order = ringOrder,
        getValue = function()
            local p = cursorDB()
            local c = p and p.castCircle
            return (c and c.ringTex) or "normal"
        end,
        setValue = function(v)
            local p = cursorDB()
            local c = p and p.castCircle
            if not c then return end
            c.ringTex = v
            if _G._ECL_ApplyCastCircle then _G._ECL_ApplyCastCircle() end
            if _G._ECL_RegisterUnlock then _G._ECL_RegisterUnlock() end
        end }

    local _, h = W:DualRow(parent, y, maCfg or BLANK(), cursorCfg);  y = y - h
    _, h = W:DualRow(parent, y, gcdRingCfg, castRingCfg);  y = y - h
    return y
end

local function TileMythicTimer(parent, y, W, tile)
    local ns = NS(tile.folder)
    if not ns then return DisabledTile(parent, y, W, tile) end
    local function db() return _G._EMT_AceDB and _G._EMT_AceDB.profile end
    local function MTApply() if _G._EMT_Apply then _G._EMT_Apply() end end
    -- MT's registered tables live in module/options locals; own memoized
    -- core-set catalogue (registered once), separator dropped like MT's own.
    local cat = OwnBarCatalogue("mt", nil)
    local values, order = CopyBarDD(cat.names, cat.order, cat.lookup, true)
    local function texCfg(label, key)
        return { type = "dropdown", text = label, values = values, order = order,
            getValue = function()
                local p = db()
                return (p and p[key]) or "none"
            end,
            setValue = function(v)
                local p = db(); if not p then return end
                p[key] = v
                MTApply()
            end }
    end
    local function subTexCfg(label, getT, applyName)
        return { type = "dropdown", text = label, values = values, order = order,
            getValue = function()
                local t = getT()
                return (t and t.texture) or "none"
            end,
            setValue = function(v)
                local t = getT(); if not t then return end
                t.texture = v
                local fn = ns[applyName]
                if fn then fn() else MTApply() end
            end }
    end
    local function tsb() local p = db(); return p and p.tsb end
    local function tfbT() local p = db(); return p and p.tfb and p.tfb.target end
    local function tfbF() local p = db(); return p and p.tfb and p.tfb.focus end
    local _, h = W:DualRow(parent, y,
        texCfg("Timer Bar Texture", "barTexture"),
        texCfg("Timer Background Texture", "barBgTexture"));  y = y - h
    _, h = W:DualRow(parent, y,
        texCfg("Forces Bar Texture", "enemyBarTexture"),
        texCfg("Forces Background Texture", "enemyBarBgTexture"));  y = y - h
    _, h = W:DualRow(parent, y,
        subTexCfg("Targeted Bars Texture", tsb, "TSB_Refresh"),
        subTexCfg("Target Cast Bar Texture", tfbT, "TFB_Refresh"));  y = y - h
    _, h = W:DualRow(parent, y,
        subTexCfg("Focus Cast Bar Texture", tfbF, "TFB_Refresh"), BLANK());  y = y - h
    return y
end

local function TileDamageMeters(parent, y, W, tile)
    local ns = NS(tile.folder)
    if not ns then return DisabledTile(parent, y, W, tile) end
    local function db()
        return _G._EDM_DB and _G._EDM_DB.profile and _G._EDM_DB.profile.dm
    end
    if EllesmereUI.AppendSharedMediaTextures then
        EllesmereUI.AppendSharedMediaTextures(_G._EDM_BarTextureNames or {}, _G._EDM_BarTextureOrder or {}, nil, _G._EDM_BarTextures)
    end
    -- DM keeps the separator in its order arrays.
    local dmValues, dmOrder = CopyBarDD(_G._EDM_BarTextureNames, _G._EDM_BarTextureOrder, _G._EDM_BarTextures, false)
    -- "Match" variant used by the breakdown + spell history rows.
    local matchValues, matchOrder = CopyBarDD(_G._EDM_BarTextureNames, _G._EDM_BarTextureOrder, _G._EDM_BarTextures, false)
    matchValues.match = "Match Damage Meters"
    table.insert(matchOrder, 1, "---")
    table.insert(matchOrder, 1, "match")
    local _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Bar Texture", values = dmValues, order = dmOrder,
          getValue = function()
              local p = db()
              return (p and p.barTexture) or "none"
          end,
          setValue = function(v)
              local p = db(); if not p then return end
              p.barTexture = v
              if ns.RefreshMeter then ns.RefreshMeter() end
              if ns.ApplySpellHistory then ns.ApplySpellHistory() end
          end },
        { type = "dropdown", text = "Breakdown Bar Texture", values = matchValues, order = matchOrder,
          getValue = function()
              local p = db()
              return (p and p.breakdownBarTexture) or "match"
          end,
          setValue = function(v)
              local p = db(); if not p then return end
              p.breakdownBarTexture = v
              if ns.RefreshMeter then ns.RefreshMeter() end
          end });  y = y - h
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Spell History Bar Texture", values = matchValues, order = matchOrder,
          getValue = function()
              local p = db()
              local sh = p and p.spellHistory
              return (sh and sh.spellHistoryBarTexture) or "match"
          end,
          setValue = function(v)
              local p = db(); if not p then return end
              if not p.spellHistory then p.spellHistory = {} end
              p.spellHistory.spellHistoryBarTexture = v
              if ns.ApplySpellHistory then ns.ApplySpellHistory() end
          end },
        BLANK());  y = y - h
    y = LinkRow(parent, y, "Window & Bar Border Styles",
        tile.folder, "Damage Meters", nil, "Border Style")
    return y
end

local function TileDataBars(parent, y, W, tile)
    local ns = NS(tile.folder)
    if not ns then return DisabledTile(parent, y, W, tile) end
    y = LinkRow(parent, y, "Bar Texture (per data bar)",
        tile.folder, "DataBars", "BAR SETTINGS", "Bar Texture")
    return y
end

local function TileBlizzardSkin(parent, y, W, tile)
    local ns = NS(tile.folder)
    if not ns then return DisabledTile(parent, y, W, tile) end
    local cat = OwnBarCatalogue("edr", nil)
    local values, order = CopyBarDD(cat.names, cat.order, cat.lookup, true)
    local _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Dragonriding Bar Texture", values = values, order = order,
          getValue = function()
              local p = ns.edrDB and ns.edrDB.profile
              return (p and p.barTexture) or "none"
          end,
          setValue = function(v)
              local p = ns.edrDB and ns.edrDB.profile
              if not p then return end
              p.barTexture = v
              if ns.edrRedraw then ns.edrRedraw() end
          end },
        BLANK());  y = y - h
    y = LinkRow(parent, y, "Popup & Tooltip Border Styles",
        tile.folder, "Tooltips, Menus & Popups", nil, "Border Style")
    return y
end

local function TileMinimap(parent, y, W, tile)
    local ns = NS(tile.folder)
    if not ns then return DisabledTile(parent, y, W, tile) end
    y = LinkRow(parent, y, "Minimap Border Style",
        tile.folder, "Minimap", "DISPLAY", "Border Style")
    return y
end

-------------------------------------------------------------------------------
--  Card list -- roster order, modules with texture settings only
-------------------------------------------------------------------------------

local TILE_BUILDERS = {
    EllesmereUIActionBars      = { TileActionBars,      "XP, reputation and favor bar textures" },
    EllesmereUINameplates      = { TileNameplates,      "Health, cast, absorb and highlight textures" },
    EllesmereUIUnitFrames      = { TileUnitFrames,      "Bar and absorb textures for the main frames" },
    EllesmereUIRaidFrames      = { TileRaidFrames,      "Health bar and absorb textures" },
    EllesmereUICooldownManager = { TileCooldownManager, "Tracking bar textures and icon borders" },
    EllesmereUIResourceBars    = { TileResourceBars,    "Resource, cast and GCD bar textures" },
    EllesmereUIQoL             = { TileQoL,             "Movement alert bar and cursor ring art" },
    EllesmereUIBlizzardSkin    = { TileBlizzardSkin,    "Dragonriding speed bar texture" },
    EllesmereUIMythicTimer     = { TileMythicTimer,     "Timer, forces and spell bar textures" },
    EllesmereUIMinimap         = { TileMinimap,         "Minimap border style" },
    EllesmereUIChat            = { TileChat,            "Chat background and tab textures" },
    EllesmereUIDamageMeters    = { TileDamageMeters,    "Meter, breakdown and history bar textures" },
    EllesmereUIDataBars        = { TileDataBars,        "Per-bar background textures" },
}

local function BuildTileList()
    local tiles = {}
    local roster = EllesmereUI.ADDON_ROSTER or {}
    for _, entry in ipairs(roster) do
        local def = not entry.comingSoon and TILE_BUILDERS[entry.folder]
        if def then
            tiles[#tiles + 1] = {
                key = entry.folder, folder = entry.folder, display = entry.display,
                desc = def[2], buildContent = def[1],
            }
        end
    end
    return tiles
end

-------------------------------------------------------------------------------
--  Texture card (same chrome as the Fonts card; chevron-only header with a
--  small statusbar-strip glyph -- there is no per-module texture override
--  system, so the header hosts no dropdown)
-------------------------------------------------------------------------------

local TX_ARROW_DOWN = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-arrow-down3.png"
local TX_ARROW_UP   = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-arrow-up3.png"
local TX_HEADER_H   = 54
local TX_CARD_GAP   = 14
local TX_GLYPH_TEX  = "Interface\\AddOns\\EllesmereUI\\media\\textures\\melli.tga"

local function BuildTexCard(parent, y, W, tile)
    local PP = EllesmereUI.PanelPP
    local EG = EllesmereUI.ELLESMERE_GREEN
    local L  = EllesmereUI.L
    -- A disabled module's card is fully inert: no expand, no hover -- just a
    -- dimmed header with a tooltip explaining why.
    local enabled = NS(tile.folder) ~= nil
    local expanded = enabled and _txExpanded[tile.key]
    local cardTop = y
    local brd

    local cardW = parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2
    local hdr = CreateFrame("Button", nil, parent)
    PP.Size(hdr, cardW, TX_HEADER_H)
    PP.Point(hdr, "TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD, y)
    hdr:SetFrameLevel(parent:GetFrameLevel() + 3)

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

    -- Mini statusbar glyph: a texture strip in a thin frame.
    local glyph = CreateFrame("Frame", nil, hdr)
    PP.Size(glyph, 26, 12)
    PP.Point(glyph, "LEFT", hdr, "LEFT", 14, 0)
    local glyphBrd = EllesmereUI.MakeBorder(glyph, 1, 1, 1, 0.3, PP)
    local glyphTex = glyph:CreateTexture(nil, "ARTWORK")
    glyphTex:SetPoint("TOPLEFT", glyph, "TOPLEFT", 1, -1)
    glyphTex:SetPoint("BOTTOMRIGHT", glyph, "BOTTOMRIGHT", -1, 1)
    glyphTex:SetTexture(TX_GLYPH_TEX)
    glyphTex:SetVertexColor(EG.r, EG.g, EG.b, 0.8)

    local title = EllesmereUI.MakeFont(hdr, 14, nil, 1, 1, 1, 0.9)
    PP.Point(title, "TOPLEFT", hdr, "TOPLEFT", 50, -12)
    title:SetText(L(tile.display))

    local desc = EllesmereUI.MakeFont(hdr, 11, nil, 1, 1, 1, 0.42)
    PP.Point(desc, "TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    desc:SetWidth(560)
    desc:SetJustifyH("LEFT")
    desc:SetWordWrap(false)
    desc:SetText(L(tile.desc or ""))

    if not enabled then
        glyphTex:SetVertexColor(1, 1, 1, 0.15)
        title:SetAlpha(0.4)
        desc:SetAlpha(0.22)
    end

    local chev
    if enabled then
        chev = hdr:CreateTexture(nil, "OVERLAY")
        PP.Size(chev, 16, 16)
        PP.Point(chev, "RIGHT", hdr, "RIGHT", -16, 0)
        chev:SetTexture(expanded and TX_ARROW_UP or TX_ARROW_DOWN)
        chev:SetAlpha(0.45)
        if expanded then chev:SetVertexColor(EG.r, EG.g, EG.b) end
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
        hdr:SetScript("OnClick", function()
            _txExpanded[tile.key] = not _txExpanded[tile.key]
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

    y = y - TX_HEADER_H

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

    return y - TX_CARD_GAP
end

-------------------------------------------------------------------------------
--  Deep-link pre-hook: expand every card before a jump into the Textures page
-------------------------------------------------------------------------------
do
    local origNav = EllesmereUI.NavigateToElementSettings
    function EllesmereUI:NavigateToElementSettings(moduleName, pageName, sectionName, preSelectFn, highlightText)
        if moduleName == GLOBAL_KEY and pageName == PAGE_TEXTURES and (sectionName or highlightText) then
            local changed = false
            for _, tile in ipairs(BuildTileList()) do
                if not _txExpanded[tile.key] then
                    _txExpanded[tile.key] = true
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
--  Page builder (dispatched from the Global Settings module registration)
-------------------------------------------------------------------------------

function _G._EUI_BuildTexturesPage(pageName, parent, yOffset)
    local W = EllesmereUI.Widgets
    local PP = EllesmereUI.PanelPP
    local y = yOffset
    local _, h

    parent._showRowDivider = true

    -- Orientation note above the section title: everything on this page is a
    -- write-through mirror, not a separate setting. Sized host + single
    -- TOPLEFT point per the search framework's geometry contract (raw
    -- parent-level regions are invisible to the search and float over
    -- filtered results).
    local introHost = CreateFrame("Frame", nil, parent)
    PP.Size(introHost, parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2, 44)
    -- 10px breathing room above; the host's slack below is trimmed the same
    -- amount so the section title sits tighter under the text.
    introHost:SetPoint("TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD, y - 20)
    local intro = EllesmereUI.MakeFont(introHost, 14, nil, 1, 1, 1, 0.65)
    intro:SetPoint("TOPLEFT", introHost, "TOPLEFT", 0, -2)
    intro:SetPoint("TOPRIGHT", introHost, "TOPRIGHT", 0, -2)
    intro:SetJustifyH("CENTER")
    intro:SetWordWrap(true)
    intro:SetText(EllesmereUI.L("A quick view of every texture setting in one place.") .. "\n"
        .. EllesmereUI.L("These are the same settings found on each module's own pages, not separate ones."))
    y = y - 48

    _, h = W:SectionHeader(parent, "MODULE TEXTURES", y);  y = y - h

    for _, tile in ipairs(BuildTileList()) do
        y = BuildTexCard(parent, y, W, tile)
    end

    -- Framework contract: return the positive total content height.
    return math.abs(y)
end
