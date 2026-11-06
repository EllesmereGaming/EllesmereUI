if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  ResourceBars_Options\MirrorTimerPage_Options.lua
--  Resource Bars options: one Mirror Timers bar (Breath, Fatigue or Feign
--  Death), shown on the Cast Bar page when its bar selector picks that bar.
--  Definitions only; the shared helpers come from ns._ERB_OptEnv (filled by
--  EUI_ResourceBars_Options.lua). The Cast Bar page's rows, where they apply.
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUIResourceBars"]
if not ns then return end  -- module disabled: no options page

-- id: breath, fatigue or feign (profile.mirrorTimer[id], ns.MT_KIND_BY_ID[id]).
function ns.ERB_BuildMirrorTimerPage(pageName, parent, yOffset, id)
    local env = ns._ERB_OptEnv
    local DB, _clickMappings = env.DB, env._clickMappings
    local K = ns.MT_KIND_BY_ID and ns.MT_KIND_BY_ID[id]
    if not K then return 0 end
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h

    parent._showRowDivider = true
    EllesmereUI:SetContentHeader(env.CastHeaderBuilder())
    if not EllesmereUI._prebuilding then
        _clickMappings.mirrorBar, _clickMappings.mirrorLabel, _clickMappings.mirrorTime = nil, nil, nil
    end

    EllesmereUI.AppendSharedMediaTextures(
        _G._ERB_BarTextureNames or {},
        _G._ERB_BarTextureOrder or {},
        nil,
        _G._ERB_BarTextures
    )
    local texValues, texOrder = {}, {}
    do
        local texNames = _G._ERB_BarTextureNames or {}
        local texOrder2 = _G._ERB_BarTextureOrder or {}
        local texLookup = _G._ERB_BarTextures or {}
        for _, key in ipairs(texOrder2) do
            if key ~= "---" then texValues[key] = texNames[key] or key end
            texOrder[#texOrder + 1] = key
        end
        texValues._menuOpts = { itemHeight = 28, background = function(key) return texLookup[key] end }
    end

    local UNLOCK = K.unlock
    local TIP = K.name
    local function C() local p = DB(); return p and p.mirrorTimer and p.mirrorTimer[id] end
    -- This bar's shipped settings (EUI_ResourceBars_Defaults.lua).
    local function DefaultCfg()
        local db = ns.ERB and ns.ERB.db
        local d = db and db._profileDefaults
        return d and d.mirrorTimer and d.mirrorTimer[id]
    end
    local off = function() local c = C(); return not (c and c.enabled) end

    local function Refresh()
        if _G._ERB_Apply then _G._ERB_Apply() end
        if EllesmereUI.NotifyElementResized then EllesmereUI.NotifyElementResized(UNLOCK) end
        if env.UpdateMirrorPreview then env.UpdateMirrorPreview() end
    end
    local function Set(key)
        return function(v) local c = C(); if not c then return end; c[key] = v; Refresh() end
    end
    local function Get(key, default)
        return function() local c = C(); if not c then return default end; local v = c[key]; if v == nil then return default end; return v end
    end
    -- The cast bar's style dresses these bars too (ns.MT_StockStyle): under a
    -- stock style its frame art replaces the border, and Blizzard Style (WoW
    -- Forever included) also brings its own background and fill art.
    local function stock() return EllesmereUI.BlizzStyle.Get("castbar") end
    local function Gate(cfg) return EllesmereUI.BlizzStyle.Gate("castbar", cfg) end
    local function GateKit(cfg)
        if EllesmereUI.BlizzStyle.Active("castbar") ~= "blizzard" then return cfg end
        return Gate(cfg)
    end
    local function Swatch(prefix, tip, disabled, disabledTooltip)
        return { tooltip = tip, hasAlpha = true, disabled = disabled, disabledTooltip = disabledTooltip,
            getValue = function()
                local c = C(); if not c then return 1, 1, 1, 1 end
                return c[prefix .. "R"] or 1, c[prefix .. "G"] or 1, c[prefix .. "B"] or 1, c[prefix .. "A"] or 1
            end,
            setValue = function(r, g, b, a)
                local c = C(); if not c then return end
                c[prefix .. "R"], c[prefix .. "G"], c[prefix .. "B"], c[prefix .. "A"] = r, g, b, a
                Refresh(); EllesmereUI:RefreshPage()
            end }
    end

    -- Apply to All / Apply to Multiple (EllesmereUI_Widgets_ApplyToAll.lua),
    -- as the action bars do: a setting's keys written from this bar onto the
    -- other mirror bars, all of them or the ones ticked in the list.
    local SYNC_IDS, SYNC_LABELS = {}, {}
    for _, k in ipairs(ns.MT_KINDS or {}) do
        SYNC_IDS[#SYNC_IDS + 1] = k.id
        SYNC_LABELS[k.id] = ns.MT_Name(k)
    end
    local function Bar(bid) local p = DB(); return p and p.mirrorTimer and p.mirrorTimer[bid] end
    local function Sync(region, tooltip, keys)
        if EllesmereUI._prebuilding or not EllesmereUI.BuildSyncIcon then return end
        local function CopyTo(ids)
            local src = C()
            for _, bid in ipairs(ids) do
                local dst = Bar(bid)
                if src and dst and dst ~= src then
                    for _, k in ipairs(keys) do dst[k] = src[k] end
                end
            end
            for _, k in ipairs(ns.MT_KINDS or {}) do
                if EllesmereUI.NotifyElementResized then EllesmereUI.NotifyElementResized(k.unlock) end
            end
            Refresh(); EllesmereUI:RefreshPage()
        end
        EllesmereUI.BuildSyncIcon({
            region = region, tooltip = tooltip,
            onClick = function() CopyTo(SYNC_IDS) end,
            isSynced = function()
                local src = C(); if not src then return true end
                for _, bid in ipairs(SYNC_IDS) do
                    local dst = Bar(bid)
                    if dst then
                        for _, k in ipairs(keys) do
                            if dst[k] ~= src[k] then return false end
                        end
                    end
                end
                return true
            end,
            flashTargets = function() return { region } end,
            multiApply = {
                elementKeys = SYNC_IDS, elementLabels = SYNC_LABELS,
                getCurrentKey = function() return id end,
                onApply = CopyTo,
            },
        })
    end
    local function Keys(prefix, list)
        local out = {}
        for _, k in ipairs(list) do out[#out + 1] = prefix .. k end
        return out
    end
    local RGBA = { "R", "G", "B", "A" }

    ---------------------------------------------------------------------------
    --  Apply All Settings From (as the Unit Frames pages have it): another
    --  bar's settings written onto this one after a confirm. Another of these
    --  bars key for key; the Player Cast Bar through the keys that mean the
    --  same thing here (its Spell Text is this bar's name text, its Duration
    --  Text the time). This bar's position and enable switch stay its own.
    ---------------------------------------------------------------------------
    local KEEP = { enabled = true, unlockPos = true, anchorX = true, anchorY = true }
    local CAST_SAME = { "width", "height", "texture", "showSpark",
        "fillR", "fillG", "fillB", "fillA",
        "gradientEnabled", "gradientR", "gradientG", "gradientB", "gradientA", "gradientDir",
        "borderSize", "borderSizePx", "borderR", "borderG", "borderB", "borderA", "borderTexture",
        "borderTextureOffset", "borderTextureOffsetY", "borderTextureShiftX", "borderTextureShiftY",
        "borderBehind", "bgR", "bgG", "bgB", "bgA" }
    local CAST_TEXT = { { mine = "label", theirs = "spellText", show = "showSpellText", side = "left" },
                        { mine = "time",  theirs = "timer",     show = "showTimer",     side = "right" } }
    local function CopyFrom(src)
        local dst, p = C(), DB()
        if not (dst and p) then return end
        if src == "cast" then
            local cb = p.castBar
            if not cb then return end
            for _, k in ipairs(CAST_SAME) do dst[k] = cb[k] end
            for _, t in ipairs(CAST_TEXT) do
                dst[t.mine .. "Side"] = (cb[t.show] == false) and "none" or (cb[t.theirs .. "Side"] or t.side)
                for _, suffix in ipairs({ "Size", "X", "Y", "R", "G", "B", "A" }) do
                    dst[t.mine .. suffix] = cb[t.theirs .. suffix]
                end
            end
        else
            local from = Bar(src)
            if not from then return end
            local keys = {}
            for k in pairs(from) do keys[k] = true end
            for k in pairs(dst) do keys[k] = true end
            for k in pairs(keys) do
                if type(k) == "string" and not KEEP[k] and k:sub(1, 1) ~= "_" then
                    local v = from[k]
                    dst[k] = (type(v) == "table") and EllesmereUI.Lite.DeepCopy(v) or v
                end
            end
        end
        for _, k in ipairs(ns.MT_KINDS or {}) do
            if EllesmereUI.NotifyElementResized then EllesmereUI.NotifyElementResized(k.unlock) end
        end
        Refresh(); EllesmereUI:RefreshPage(true)
    end
    do
        local ROW_H = 50
        if not EllesmereUI._prebuilding then
            local PP = EllesmereUI.PanelPP
            local mk = EllesmereUI._Pool and EllesmereUI._Pool.CreateFrame or CreateFrame
            local contentPad = EllesmereUI.CONTENT_PAD or 45
            local row = mk("Frame", nil, parent)
            PP.Size(row, parent:GetWidth() - contentPad * 2, ROW_H)
            PP.Point(row, "TOPLEFT", parent, "TOPLEFT", contentPad, y)
            local values, order = { [""] = "Choose Bar..." }, {}
            values.cast = "Player Cast Bar"; order[1] = "cast"
            for _, k in ipairs(ns.MT_KINDS or {}) do
                if k.id ~= id then
                    values[k.id] = ns.MT_Name(k)
                    order[#order + 1] = k.id
                end
            end
            local label = EllesmereUI.MakeFont(row, 14, nil, 1, 1, 1)
            label:SetText(EllesmereUI.L("Apply All Settings From"))
            label:SetTextColor(1, 1, 1, 0.6)
            local DD_W, GAP = 180, 12
            local dd = EllesmereUI.BuildDropdownControl(row, DD_W, row:GetFrameLevel() + 2, values, order,
                function() return "" end,
                function(src)
                    if src == "" then return end
                    EllesmereUI:ShowConfirmPopup({
                        title = "Apply All Settings",
                        message = EllesmereUI.Lf("Copy all settings from %1$s to %2$s?",
                            EllesmereUI.L(values[src]), ns.MT_Name(K)),
                        disclaimer = "This overwrites this bar's current settings. Its position and enable state are not changed.",
                        confirmText = "Apply",
                        cancelText = "Cancel",
                        onConfirm = function() CopyFrom(src) end,
                    })
                end)
            dd._ttText = "Copy every setting this bar shares with the bar you choose onto this bar."
            EllesmereUI.RegisterWidgetRefresh(function() dd._refreshLabel() end)
            local totalW = label:GetStringWidth() + GAP + DD_W
            label:SetPoint("LEFT", row, "CENTER", -totalW / 2, 0)
            dd:SetPoint("LEFT", label, "RIGHT", GAP, 0)
        end
        y = y - ROW_H
    end

    ---------------------------------------------------------------------------
    --  LAYOUT
    ---------------------------------------------------------------------------
    local layoutSection
    layoutSection, h = W:SectionHeader(parent, "LAYOUT", y);  y = y - h

    -- Row: Enable (+ position cog) | Frame Strata
    local enableRow
    enableRow, h = W:DualRow(parent, y,
        { type = "toggle", text = "Enable " .. K.name .. " Bar",
          tooltip = "Your own bar for this timer, in place of Blizzard's.",
          getValue = function() local c = C(); return c and c.enabled end,
          setValue = function(v)
              local c = C(); if not c then return end
              c.enabled = v; Refresh(); EllesmereUI:RefreshPage()
          end },
        { type = "dropdown", text = "Frame Strata",
          tooltip = "Controls the order that overlapping elements display in. Set higher to show above other elements.",
          disabled = off, disabledTooltip = TIP,
          values = EllesmereUI.FRAME_STRATA_LABELS, order = EllesmereUI.FRAME_STRATA_ORDER_BASE,
          getValue = Get("frameStrata", "MEDIUM"), setValue = Set("frameStrata") }
    );  y = y - h
    if not EllesmereUI._prebuilding then
        local function PosGet(axis)
            return function()
                local c = C(); if not c then return 0 end
                if c.unlockPos and c.unlockPos.point then return c.unlockPos[axis] or 0 end
                if axis == "x" then return c.anchorX or 0 end
                return c.anchorY or 300
            end
        end
        local function PosSet(axis)
            return function(v)
                local c = C(); if not c then return end
                if c.unlockPos and c.unlockPos.point then c.unlockPos[axis] = v
                elseif axis == "x" then c.anchorX = v
                else c.anchorY = v end
                Refresh()
            end
        end
        Sync(enableRow._rightRegion, "Apply Frame Strata to all Bars", { "frameStrata" })
        EllesmereUI.BuildInlineCog(enableRow._leftRegion, { icon = EllesmereUI.DIRECTIONS_ICON,
            disabled = off, disabledTooltip = TIP,
            title = K.name .. " Bar Position",
            rows = {
                { type = "slider", label = "X Offset", min = -600, max = 600, step = 1, get = PosGet("x"), set = PosSet("x") },
                { type = "slider", label = "Y Offset", min = -600, max = 600, step = 1, get = PosGet("y"), set = PosSet("y") },
            },
            footer = { unlockKey = UNLOCK },
        })
    end

    -- Row: Height | Width
    local hDis, hTip, hRaw = EllesmereUI.MatchGuard(UNLOCK, "Height", off, TIP)
    local wDis, wTip, wRaw = EllesmereUI.MatchGuard(UNLOCK, "Width", off, TIP)
    local sizeRow
    sizeRow, h = W:DualRow(parent, y,
        { type = "slider", text = "Height", min = 4, max = 60, step = 1,
          disabled = hDis, disabledTooltip = hTip, rawTooltip = hRaw,
          getValue = Get("height", 20), setValue = Set("height") },
        { type = "slider", text = "Width", min = 50, max = 800, step = 1,
          disabled = wDis, disabledTooltip = wTip, rawTooltip = wRaw,
          getValue = Get("width", 200), setValue = Set("width") }
    );  y = y - h
    Sync(sizeRow._leftRegion, "Apply Height to all Bars", { "height" })
    Sync(sizeRow._rightRegion, "Apply Width to all Bars", { "width" })

    -- Row: Show Spark | Hide Blizzard Bar
    local sparkRow
    sparkRow, h = W:DualRow(parent, y,
        { type = "toggle", text = "Show Spark",
          disabled = off, disabledTooltip = TIP,
          getValue = function() local c = C(); return c and c.showSpark end,
          setValue = Set("showSpark") },
        { type = "toggle", text = "Hide Blizzard Bar",
          tooltip = "Makes Blizzard's own bar for this timer invisible while this one is on.",
          disabled = off, disabledTooltip = TIP,
          getValue = function() local c = C(); return c and c.hideBlizzard ~= false end,
          setValue = Set("hideBlizzard") }
    );  y = y - h
    Sync(sparkRow._leftRegion, "Apply Show Spark to all Bars", { "showSpark" })
    Sync(sparkRow._rightRegion, "Apply Hide Blizzard Bar to all Bars", { "hideBlizzard" })

    _, h = W:Spacer(parent, y, 16);  y = y - h

    ---------------------------------------------------------------------------
    --  DISPLAY
    ---------------------------------------------------------------------------
    local displaySection
    displaySection, h = W:SectionHeader(parent, "DISPLAY", y);  y = y - h

    -- Row: Border Style (+ border options cog) | Border Size (+ border colour)
    do
        local btValues, btOrder = EllesmereUI.GetBorderTextureDropdown()
        local bsRow
        bsRow, h = W:DualRow(parent, y,
            Gate({ type = "dropdown", text = "Border Style",
              disabled = off, disabledTooltip = TIP,
              values = btValues, order = btOrder,
              getValue = Get("borderTexture", "solid"),
              setValue = function(v)
                  local g = C(); if not g then return end
                  g.borderTexture = v; g.borderTextureOffset = nil; g.borderTextureOffsetY = nil; g.borderTextureShiftX = nil; g.borderTextureShiftY = nil
                  local bcol, bbehind = EllesmereUI.GetBorderStyleSelectDefaults(v)
                  g.borderR = bcol.r; g.borderG = bcol.g; g.borderB = bcol.b; g.borderA = 1
                  g.borderBehind = bbehind
                  local defSz = EllesmereUI.GetBorderDefaultSize("resourcebars", v)
                  if defSz then g.borderSize = defSz end
                  if g.borderSizePx then g.borderSizePx = false end
                  Refresh(); EllesmereUI:RefreshPage(true)
              end }),
            Gate(EllesmereUI.BorderPxSliderCfg({ text = "Border Size",
              disabled = off, disabledTooltip = TIP,
              getStep = function() local c = C(); return c and (c.borderSize or 0) or 0 end,
              setStep = function(v) local c = C(); if c then c.borderSize = v end end,
              getTex = function() local c = C(); return c and (c.borderTexture or "solid") or "solid" end,
              getPx = function() local c = C(); return c and c.borderSizePx end,
              setPx = function(v) local c = C(); if c then c.borderSizePx = v end end,
              apply = function() Refresh(); EllesmereUI:RefreshPage() end,
            })));  y = y - h
        -- Width Offset | Height Offset: own row while a textured style is selected.
        do
            local c = C()
            local tex = c and c.borderTexture or "solid"
            if tex ~= "solid" and tex ~= "" and not stock() then
                local function step() local c2 = C(); return c2 and (c2.borderSize or 0) or 0 end
                local ocfgL, ocfgR = EllesmereUI.BorderOffsetRowCfgs({
                    addonKey = "resourcebars",
                    disabled = off, disabledTooltip = TIP,
                    getTex = function() local c2 = C(); return c2 and (c2.borderTexture or "solid") or "solid" end,
                    getStep = step, getSizeKey = step,
                    getPx = function() local c2 = C(); return c2 and c2.borderSizePx end,
                    getX = function() local c2 = C(); return c2 and c2.borderTextureOffset end,
                    setX = function(v) local c2 = C(); if c2 then c2.borderTextureOffset = v end end,
                    getY = function() local c2 = C(); return c2 and c2.borderTextureOffsetY end,
                    setY = function(v) local c2 = C(); if c2 then c2.borderTextureOffsetY = v end end,
                    apply = function() Refresh(); EllesmereUI:RefreshPage() end,
                })
                _, h = W:DualRow(parent, y, ocfgL, ocfgR);  y = y - h
            end
        end
        if not EllesmereUI._prebuilding then
            EllesmereUI.BuildInlineSwatches(bsRow._rightRegion, {
                Swatch("border", "Border Color",
                    function() local c = C(); return not (c and c.enabled and (c.borderSize or 0) > 0) end,
                    function()
                        if off() then return TIP end
                        return "This option requires a Border Size above 0."
                    end),
            }, { size = 20 })
            -- Corner Radius (EllesmereUI_RoundedCorners.lua): an inline cog on the
            -- border size control, as on the swing timer.
            EllesmereUI.BuildInlineCog(bsRow._rightRegion, {
                title = "Corner Radius", tip = "Corner Radius",
                disabled = function()
                    if off() or stock() then return true end
                    local c = C(); return not EllesmereUI.RoundedStyleOK(c and c.borderTexture)
                end,
                disabledTooltip = function()
                    if stock() then return EllesmereUI.BlizzStyle.Label("castbar") end
                    if off() then return TIP end
                    return "This option requires the Solid, Glow or Shadow border style."
                end,
                rows = EllesmereUI.RoundedCornerRows({
                    { type = "slider", label = "Corner Radius", min = 0, max = EllesmereUI.ROUNDED_MAX_RADIUS, step = 1,
                      get = function() local c = C(); return c and c.cornerRadius or 0 end,
                      set = function(v) local c = C(); if not c then return end; c.cornerRadius = v; Refresh() end },
                }, function() local c = C(); return c and c.cornerMask end,
                   function(v) local c = C(); if not c then return end; c.cornerMask = v; Refresh() end),
            })
            local cogBtn = EllesmereUI.BuildInlineCog(bsRow._leftRegion, { icon = EllesmereUI.DIRECTIONS_ICON,
                title = "Border Options",
                rows = {
                    { type = "slider", label = "Shift X", min = -10, max = 10, step = 1,
                      get = function() local c = C(); if not c then return 0 end; local v = c.borderTextureShiftX; if v then return v end; local _, _, dsx = EllesmereUI.GetBorderDefaults("resourcebars", c.borderTexture or "solid", c.borderSize or 0); return dsx end,
                      set = function(v) local c = C(); if not c then return end; c.borderTextureShiftX = v == 0 and nil or v; Refresh(); EllesmereUI:RefreshPage() end },
                    { type = "slider", label = "Shift Y", min = -10, max = 10, step = 1,
                      get = function() local c = C(); if not c then return 0 end; local v = c.borderTextureShiftY; if v then return v end; local _, _, _, dsy = EllesmereUI.GetBorderDefaults("resourcebars", c.borderTexture or "solid", c.borderSize or 0); return dsy end,
                      set = function(v) local c = C(); if not c then return end; c.borderTextureShiftY = v == 0 and nil or v; Refresh(); EllesmereUI:RefreshPage() end },
                    { type = "toggle", label = "Show Behind",
                      get = function() local c = C(); return c and c.borderBehind or false end,
                      set = function(v) local c = C(); if not c then return end; c.borderBehind = v == false and nil or v; Refresh(); EllesmereUI:RefreshPage() end },
                },
            })
            local function UpdateCogVis()
                local c = C()
                local tex = c and c.borderTexture or "solid"
                if tex == "solid" then cogBtn:Hide() else cogBtn:Show() end
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateCogVis)
            UpdateCogVis()
        end
        Sync(bsRow._leftRegion, "Apply Border Style to all Bars", { "borderTexture", "borderTextureOffset",
            "borderTextureOffsetY", "borderTextureShiftX", "borderTextureShiftY", "borderBehind" })
        local sizeKeys = Keys("border", RGBA)
        for _, k in ipairs({ "borderSize", "borderSizePx", "cornerRadius", "cornerMask" }) do sizeKeys[#sizeKeys + 1] = k end
        Sync(bsRow._rightRegion, "Apply Border Size and Color to all Bars", sizeKeys)
    end

    -- Row: Fill Color (gradient end + fill, gradient cog) | Background (+ colour)
    local colorRow
    colorRow, h = W:DualRow(parent, y,
        { type = "multiSwatch", text = "Fill Color",
          disabled = off, disabledTooltip = TIP,
          swatches = {
              Swatch("gradient", "Gradient End Color",
                  function() local c = C(); return not (c and c.gradientEnabled) end,
                  function() if off() then return TIP end; return "Gradient" end),
              Swatch("fill", "Fill Color"),
              -- This bar's own colour from the defaults, to come back to after
              -- Apply All Settings From has brought another bar's: a click
              -- puts it back; bright while the fill is something else.
              { tooltip = "Default Color", hasAlpha = false,
                getValue = function()
                    local d = DefaultCfg()
                    return (d and d.fillR or 1), (d and d.fillG or 1), (d and d.fillB or 1)
                end,
                setValue = function() end,
                onClick = function()
                    local c, d = C(), DefaultCfg()
                    if not (c and d) then return end
                    c.fillR, c.fillG, c.fillB, c.fillA = d.fillR, d.fillG, d.fillB, d.fillA
                    Refresh(); EllesmereUI:RefreshPage()
                end,
                refreshAlpha = function()
                    local c, d = C(), DefaultCfg()
                    if not (c and d) then return 0.3 end
                    local same = c.fillR == d.fillR and c.fillG == d.fillG and c.fillB == d.fillB
                    return same and 0.3 or 1
                end },
          } },
        GateKit({ type = "slider", text = "Background", min = 0, max = 100, step = 1,
          disabled = off, disabledTooltip = TIP,
          getValue = function() local c = C(); return math.floor(((c and c.bgA or 0.7) * 100) + 0.5) end,
          setValue = function(v) local c = C(); if not c then return end; c.bgA = v / 100; Refresh() end })
    );  y = y - h
    if not EllesmereUI._prebuilding then
        EllesmereUI.BuildInlineCog(colorRow._leftRegion, {
            disabled = off, disabledTooltip = TIP,
            title = "Gradient Settings",
            rows = {
                { type = "toggle", label = "Enable Gradient",
                  get = function() local c = C(); return c and c.gradientEnabled end,
                  set = function(v) local c = C(); if not c then return end; c.gradientEnabled = v; Refresh(); EllesmereUI:RefreshPage() end },
                { type = "dropdown", label = "Gradient Direction",
                  values = { HORIZONTAL = "Horizontal", VERTICAL = "Vertical" }, order = { "HORIZONTAL", "VERTICAL" },
                  get = function() local c = C(); return c and c.gradientDir or "HORIZONTAL" end,
                  set = function(v) local c = C(); if not c then return end; c.gradientDir = v; Refresh() end },
            },
        })
        EllesmereUI.BuildInlineSwatches(colorRow._rightRegion, {
            { tooltip = "Background Color",
              getValue = function() local c = C(); return (c and c.bgR or 0), (c and c.bgG or 0), (c and c.bgB or 0) end,
              setValue = function(r, g, b) local c = C(); if not c then return end; c.bgR, c.bgG, c.bgB = r, g, b; Refresh() end },
        }, { size = 20, disabled = off, disabledTooltip = TIP })
    end
    do
        local fillKeys = Keys("fill", RGBA)
        for _, k in ipairs(Keys("gradient", RGBA)) do fillKeys[#fillKeys + 1] = k end
        fillKeys[#fillKeys + 1] = "gradientEnabled"
        fillKeys[#fillKeys + 1] = "gradientDir"
        Sync(colorRow._leftRegion, "Apply Fill Color to all Bars", fillKeys)
        Sync(colorRow._rightRegion, "Apply Background Settings to all Bars", Keys("bg", RGBA))
    end

    -- A text row's dropdown (None / Left / Right / Center), with its colour
    -- swatch and a cog for size and offsets, as the Cast Bar's Spell Text.
    local SIDES = { none = "None", left = "Left", right = "Right", center = "Center" }
    local SIDE_ORDER = { "none", "left", "right", "center" }
    local function TextCfg(text, prefix, default)
        return { type = "dropdown", text = text,
          disabled = off, disabledTooltip = TIP,
          values = SIDES, order = SIDE_ORDER,
          getValue = Get(prefix .. "Side", default),
          setValue = function(v) local c = C(); if not c then return end; c[prefix .. "Side"] = v; Refresh(); EllesmereUI:RefreshPage() end }
    end
    local function TextExtras(region, text, prefix, default)
        if EllesmereUI._prebuilding then return end
        local textOff = function() local c = C(); return not (c and c.enabled and (c[prefix .. "Side"] or default) ~= "none") end
        local textTip = function() return off() and TIP or text end
        EllesmereUI.BuildInlineSwatches(region, {
            Swatch(prefix, text .. " Color", textOff, textTip),
        }, { size = 20 })
        EllesmereUI.BuildInlineCog(region, { icon = EllesmereUI.DIRECTIONS_ICON,
            disabled = textOff, disabledTooltip = textTip,
            title = text .. " Settings",
            rows = {
                { type = "slider", label = "Text Size", min = 8, max = 24, step = 1,
                  get = Get(prefix .. "Size", 11), set = Set(prefix .. "Size") },
                { type = "slider", label = "X Offset", min = -100, max = 100, step = 1,
                  get = Get(prefix .. "X", 0), set = Set(prefix .. "X") },
                { type = "slider", label = "Y Offset", min = -100, max = 100, step = 1,
                  get = Get(prefix .. "Y", 0), set = Set(prefix .. "Y") },
            },
        })
    end

    -- Row: Bar Texture | Label Text
    local textRow
    textRow, h = W:DualRow(parent, y,
        GateKit({ type = "dropdown", text = "Bar Texture",
          disabled = off, disabledTooltip = TIP,
          values = texValues, order = texOrder,
          getValue = Get("texture", "none"), setValue = Set("texture") }),
        TextCfg("Label Text", "label", "left")
    );  y = y - h
    TextExtras(textRow._rightRegion, "Label Text", "label", "left")
    local TEXT_KEYS = { "Side", "Size", "X", "Y", "R", "G", "B", "A" }
    Sync(textRow._leftRegion, "Apply Bar Texture to all Bars", { "texture" })
    Sync(textRow._rightRegion, "Apply Label Text to all Bars", Keys("label", TEXT_KEYS))

    -- Row: Duration Text | Low Warning (+ Warning Starts At cog)
    local timeRow
    timeRow, h = W:DualRow(parent, y,
        TextCfg("Duration Text", "time", "right"),
        { type = "toggle", text = "Low Warning",
          tooltip = "The bar turns red and blinks once it runs down to the level set in the cog.",
          disabled = off, disabledTooltip = TIP,
          getValue = function() local c = C(); return c and c.lowWarn == true end,
          setValue = function(v) local c = C(); if not c then return end; c.lowWarn = v; Refresh(); EllesmereUI:RefreshPage() end }
    );  y = y - h
    TextExtras(timeRow._leftRegion, "Duration Text", "time", "right")
    Sync(timeRow._leftRegion, "Apply Duration Text to all Bars", Keys("time", TEXT_KEYS))
    Sync(timeRow._rightRegion, "Apply Low Warning to all Bars", { "lowWarn", "lowWarnAt" })
    if not EllesmereUI._prebuilding then
        EllesmereUI.BuildInlineCog(timeRow._rightRegion, {
            disabled = function() local c = C(); return not (c and c.enabled and c.lowWarn) end,
            disabledTooltip = function() return off() and TIP or "Low Warning" end,
            title = "Low Warning",
            rows = {
                { type = "slider", label = "Warn When Left", min = 10, max = 90, step = 5,
                  tooltip = "When this much of the bar is left, in percent, the bar turns red and blinks.",
                  get = Get("lowWarnAt", 30), set = Set("lowWarnAt") },
            },
        })
    end

    if not EllesmereUI._prebuilding then
        _clickMappings.mirrorBar   = { section = layoutSection, target = sizeRow }
        _clickMappings.mirrorLabel = { section = displaySection, target = textRow, slotSide = "right" }
        _clickMappings.mirrorTime  = { section = displaySection, target = timeRow, slotSide = "left" }
    end

    return math.abs(y)
end
