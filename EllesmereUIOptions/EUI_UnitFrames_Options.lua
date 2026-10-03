if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_UnitFrames_Options.lua
--  Registers the Unit Frames module with EllesmereUI
--  4 tabs: Main Frames, Boss Frames, Mini Frames, Player Aura Bars
-------------------------------------------------------------------------------
local ADDON_NAME = "EllesmereUIUnitFrames"
local ns = EllesmereUI._ModuleNS[ADDON_NAME]  -- module namespace (published by the module at its load)
if not ns then return end  -- module disabled: no options page

local PAGE_DISPLAY   = "Main Frames"
local PAGE_BOSS      = "Boss Frames"
local PAGE_MINI      = "Mini Frames"
local PAGE_AURA_BARS = "Player Aura Bars"
local PAGE_UNLOCK    = "Unlock Mode"

-- Threat % Position dropdown (WoW Forever only, so nil on retail). On ns: the
-- Main Frames page builder is near its 60-upvalue cap, and the Forever
-- Essentials Threat page reads the same lists. Outside = beside the whole
-- frame, clear of an attached portrait.
if EllesmereUI.IS_FOREVER then
    ns._threatPctPositions = { RIGHT = "Inside Right", LEFT = "Inside Left", CENTER = "Inside Center",
        OUTRIGHT = "Outside Right", OUTLEFT = "Outside Left" }
    ns._threatPctPositionOrder = { "RIGHT", "LEFT", "CENTER", "OUTRIGHT", "OUTLEFT" }
end

-- Settings-cog rows of a text slot that can show a name. WoW Forever puts its
-- Name Format row at the top (the name's first word, its last word, or all of
-- it -- unset); every other client gets rows back untouched. prefix is the
-- slot's key prefix ("leftText", "btbLeft"): content at <prefix>Content, format
-- at <prefix>NameFormat. get(key, default) / set(key, v) are the page's
-- accessors. On ns for the same upvalue cap.
if EllesmereUI.IS_FOREVER then
    local HAS_NAME = { name = true, levelname = true, namelevel = true, nametotarget = true, targetname = true }
    local FORMATS = { first = "First Name", last = "Last Name", full = "First and Last" }
    local FORMAT_ORDER = { "first", "last", "full" }
    function ns.UF_NameFormatRows(prefix, contentDefault, get, set, rows)
        local contentKey, formatKey = prefix .. "Content", prefix .. "NameFormat"
        table.insert(rows, 1, { type="dropdown", label="Name Format", values=FORMATS, order=FORMAT_ORDER,
            get=function() return get(formatKey, "full") end,
            -- First and Last is the unset default.
            set=function(v) set(formatKey, (v ~= "full") and v or nil) end,
            disabled=function() return not HAS_NAME[get(contentKey, contentDefault)] end,
            disabledTooltip="This option only applies when the text shows a name." })
        return rows
    end
else
    function ns.UF_NameFormatRows(_, _, _, _, rows) return rows end
end

-- Classic WoW UI: a cast bar section's closing Border Size row (the odd last
-- slot), sizing the vanilla frame round the bar. getS() returns the unit's
-- settings table and `key` its frame-size key (ns.UF_CastClassicKey);
-- onChange repaints. `matchKey` names the cast bar's unlock element (nil on
-- the boss page, which has none): its size matches read the frame's reach
-- and are re-applied when it changes. `sync` (main frames page only) adds
-- the apply-to-all icon: { units, labels, current(), db(unit), reload }; a
-- unit's element is "<unit>Castbar". `right` (optional) fills the free right
-- slot. Returns the row height, 0 (nothing built) off the style, and the row.
-- On ns: the page builders sit at the local cap.
function ns.UF_ClassicCastBorderRow(W, parent, y, getS, key, onChange, sync, matchKey, right)
    local BS = EllesmereUI.BlizzStyle
    if not (BS and BS.Active("unitframes") == "classic") then return 0 end
    local row, h = W:DualRow(parent, y,
        BS.ClassicBorderSizeCfg(
            function() local s = getS(); return s and s[key] end,
            function(v)
                local s = getS(); if not s then return end
                s[key] = v; onChange()
                if matchKey and EllesmereUI.ReapplyMatchPads then EllesmereUI.ReapplyMatchPads(matchKey) end
            end),
        right or EllesmereUI.BlankRowCfg())
    if sync and not EllesmereUI._prebuilding then
        local rgn = row._leftRegion
        local function apply(units)
            local s = getS()
            local v = s and s[key]
            for i = 1, #units do
                local t = sync.db(units[i])
                if t then t[ns.UF_CastClassicKey(units[i])] = v end
            end
            sync.reload()
            if EllesmereUI.ReapplyMatchPads then
                for i = 1, #units do EllesmereUI.ReapplyMatchPads(units[i] .. "Castbar") end
            end
            EllesmereUI:RefreshPage()
        end
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Border Size to all Frames",
            onClick = function() apply(sync.units) end,
            isSynced = function()
                local s = getS()
                local v = s and s[key]
                for i = 1, #sync.units do
                    local t = sync.db(sync.units[i])
                    if t and t[ns.UF_CastClassicKey(sync.units[i])] ~= v then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = sync.units,
                elementLabels = sync.labels,
                getCurrentKey = sync.current,
                onApply       = apply,
            },
        })
    end
    return h, row
end

-- The 3D portrait performance warning, shown until confirmed once (account-
-- wide). Returns true when it asked (onConfirm runs on Enable, Cancel refreshes
-- the page), false when it was already dismissed and the caller applies the
-- pick itself. On ns: the page builders sit at their upvalue caps.
function ns.UF_Ask3DPortraits(onConfirm)
    if EllesmereUIDB and EllesmereUIDB.dismissed3DWarning then return false end
    EllesmereUI:ShowConfirmPopup({
        title       = "3D Portraits",
        message     = "3D portraits may cause a slight loss in performance efficiency. Do you want to enable them?",
        confirmText = "Enable",
        cancelText  = "Cancel",
        onConfirm   = function()
            if not EllesmereUIDB then EllesmereUIDB = {} end
            EllesmereUIDB.dismissed3DWarning = true
            onConfirm()
        end,
        onCancel    = function()
            EllesmereUI:RefreshPage()
        end,
    })
    return true
end

-- Separate acknowledgement: enabling 3D does not opt into 2D model lookups.
-- onCancel (optional) replaces the plain page refresh on Cancel.
function ns.UF_Ask2DMirroredPortraits(onConfirm, onCancel)
    if EllesmereUIDB and EllesmereUIDB.dismissed2DMirrorWarning then return false end
    EllesmereUI:ShowConfirmPopup({
        title       = "2D Mirrored Portraits",
        message     = "2D mirrored portraits may cause a slight loss in performance efficiency. Do you want to enable them?",
        confirmText = "Enable",
        cancelText  = "Cancel",
        onConfirm   = function()
            if not EllesmereUIDB then EllesmereUIDB = {} end
            EllesmereUIDB.dismissed2DMirrorWarning = true
            onConfirm()
        end,
        onCancel    = onCancel or function()
            EllesmereUI:RefreshPage()
        end,
    })
    return true
end

-- Frames already set to Mirror Portrait in 2D mode get the same warning once,
-- the first time Unit Frames options open in a session: Enable keeps them,
-- Cancel turns Mirror Portrait off on those frames. Class mode is not asked:
-- there Mirror Portrait also flips the class art, which costs nothing.
do
    local asked
    local UNITS = { "player", "target", "focus", "targettarget", "focustarget", "pet", "boss" }
    function ns.UF_AskExisting2DMirror()
        if asked or EllesmereUI._prebuilding then return end
        asked = true
        if (EllesmereUIDB and EllesmereUIDB.dismissed2DMirrorWarning) or ns.UF_Blizz() then return end
        local prof = ns.db and ns.db.profile
        if not prof then return end
        local on
        for _, k in ipairs(UNITS) do
            local s = prof[k]
            if type(s) == "table" and s.portraitMirror
               and (s.portraitMode or prof.portraitMode or "2d") == "2d"
               and (s.portraitStyle or prof.portraitStyle) ~= "none" then
                on = on or {}
                on[#on + 1] = k
            end
        end
        if not on then return end
        ns.UF_Ask2DMirroredPortraits(function() end, function()
            for _, k in ipairs(on) do
                prof[k].portraitMirror = false
                ns.UF_RefreshPortraitMirror(k)
            end
            EllesmereUI:RefreshPage()
        end)
    end
end

-- Dragon Strata dropdown (the PORTRAIT section's dragon cog): Match Frame
-- keeps the frame's own strata, then the base stratas.
do
    local values, order = { inherit = "Match Frame" }, { "inherit" }
    for _, k in ipairs(EllesmereUI.FRAME_STRATA_ORDER_BASE) do
        values[k] = EllesmereUI.FRAME_STRATA_LABELS[k]
        order[#order + 1] = k
    end
    ns._ufDragonStrataValues, ns._ufDragonStrataOrder = values, order
end

-- Custom Border Style rows of a cast bar section, built only while the Cast
-- Bar cog's "Custom Border Style" opt-in is on: Border Style (+ a DIRECTIONS
-- cog for textured styles: Shift X, Shift Y, Show Behind) | Border Size (+ a
-- colour swatch), then Width Offset | Height Offset while the style is
-- textured. Every slot is BlizzStyle.Gate'd, so a stock style drops the rows
-- and the Classic-only Border Size row stays the section's odd last slot.
-- getS() returns the unit's settings table; onChange repaints; matchKey names
-- the cast bar's unlock element (nil on the boss page, which has none): its
-- size matches read the border's reach and re-apply on a change. sync (main
-- frames page only) adds the two apply-to-all links: { units, labels,
-- current(), db(unit) }. Returns the height built. On ns: the page builders
-- sit at their upvalue caps.
function ns.UF_CastBorderRows(W, parent, y, getS, onChange, matchKey, sync)
    local BS = EllesmereUI.BlizzStyle
    local y0 = y
    local function Changed()
        onChange()
        if matchKey then EllesmereUI.ReapplyMatchPads(matchKey) end
    end
    local texValues, texOrder = EllesmereUI.GetBorderTextureDropdown()
    local row, h = W:DualRow(parent, y,
        BS.Gate("unitframes", { type="dropdown", text="Border Style",
          tooltip="Border art drawn around the cast bar.",
          values=texValues, order=texOrder,
          getValue=function() return getS().castBorderStyle or "solid" end,
          setValue=function(v)
              local s = getS()
              s.castBorderStyle = v
              s.castBorderOffsetX, s.castBorderOffsetY = nil, nil
              s.castBorderShiftX, s.castBorderShiftY = nil, nil
              local col, behind = EllesmereUI.GetBorderStyleSelectDefaults(v)
              s.castBorderColor, s.castBorderAlpha, s.castBorderBehind = col, 1, behind
              local defSz = EllesmereUI.GetBorderDefaultSize("unitframes", v)
              if defSz then s.castBorderSize = defSz end
              -- A style pick returns the bar to its legacy step; clear a set
              -- exact size (false travels through mirror sync, nil would not).
              if s.castBorderSizePx then s.castBorderSizePx = false end
              Changed()
              -- The Width / Height Offset row exists only under a textured style.
              EllesmereUI:RefreshPage(true)
          end }),
        BS.Gate("unitframes", EllesmereUI.BorderPxSliderCfg({ text="Border Size", trackWidth=120,
          getStep=function() return getS().castBorderSize or 1 end,
          setStep=function(step) getS().castBorderSize = step end,
          getTex=function() return getS().castBorderStyle or "solid" end,
          getPx=function() return getS().castBorderSizePx end,
          setPx=function(v) getS().castBorderSizePx = v end,
          -- The refresh dims the colour swatch at 0.
          apply=function() Changed(); EllesmereUI:RefreshPage() end })))
    y = y - h
    -- Width Offset | Height Offset: a textured style's outward offsets.
    do
        local tex = getS().castBorderStyle or "solid"
        if tex ~= "solid" and tex ~= "" then
            local ocfgL, ocfgR = EllesmereUI.BorderOffsetRowCfgs({
                addonKey = "unitframes",
                getTex = function() return getS().castBorderStyle or "solid" end,
                getStep = function() return getS().castBorderSize or 1 end,
                getSizeKey = function() return getS().castBorderSize or 1 end,
                getPx = function() return getS().castBorderSizePx end,
                getX = function() return getS().castBorderOffsetX end,
                setX = function(v) getS().castBorderOffsetX = v end,
                getY = function() return getS().castBorderOffsetY end,
                setY = function(v) getS().castBorderOffsetY = v end,
                apply = Changed,
            })
            local _, oh = W:DualRow(parent, y, BS.Gate("unitframes", ocfgL), BS.Gate("unitframes", ocfgR))
            y = y - oh
        end
    end
    if EllesmereUI._prebuilding then return y0 - y end

    -- Border Options cog (left): shifts and layering, textured styles only.
    do
        -- A stored shift, else the registry default for the style and size.
        local function Shift(key, isY)
            local s = getS()
            if s[key] then return s[key] end
            local _, _, dsx, dsy = EllesmereUI.GetBorderDefaults("unitframes", s.castBorderStyle or "solid", s.castBorderSize or 1)
            if isY then return dsy end
            return dsx
        end
        -- The shown default stores nil, any other value (0 included) is kept.
        local function SetShift(key, isY, v)
            local s = getS()
            s[key] = nil
            if v ~= Shift(key, isY) then s[key] = v end
            Changed()
        end
        local cogBtn = EllesmereUI.BuildInlineCog(row._leftRegion, { icon = EllesmereUI.DIRECTIONS_ICON,
            title = "Border Options",
            rows = {
                { type = "slider", label = "Shift X", min = -10, max = 10, step = 1,
                  get = function() return Shift("castBorderShiftX", false) end,
                  set = function(v) SetShift("castBorderShiftX", false, v) end },
                { type = "slider", label = "Shift Y", min = -10, max = 10, step = 1,
                  get = function() return Shift("castBorderShiftY", true) end,
                  set = function(v) SetShift("castBorderShiftY", true, v) end },
                { type = "toggle", label = "Show Behind",
                  tooltip = "Draws the border behind the cast bar instead of over it.",
                  get = function() return getS().castBorderBehind == true end,
                  set = function(v) getS().castBorderBehind = v; Changed() end },
            },
        })
        local function UpdateCogVis()
            local tex = getS().castBorderStyle or "solid"
            if tex == "solid" or tex == "" or BS.Get("unitframes") then cogBtn:Hide() else cogBtn:Show() end
        end
        EllesmereUI.RegisterWidgetRefresh(UpdateCogVis)
        UpdateCogVis()
    end

    -- Colour swatch (with alpha) on Border Size; greyed and blocked at 0.
    do
        local rgn = row._rightRegion
        local sw, updateSw = EllesmereUI.BuildColorSwatch(rgn, row:GetFrameLevel() + 3,
            function()
                local s = getS()
                local c = s.castBorderColor
                return c and c.r or 0, c and c.g or 0, c and c.b or 0, s.castBorderAlpha or 1
            end,
            function(r, g, b, a)
                local s = getS()
                s.castBorderColor = { r = r, g = g, b = b }
                s.castBorderAlpha = a
                onChange()
            end,
            true, 20)
        EllesmereUI.PanelPP.Point(sw, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        sw:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(sw, "Border") end)
        sw:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        rgn._lastInline = sw
        local block = CreateFrame("Frame", nil, sw)
        block:SetAllPoints()
        block:SetFrameLevel(sw:GetFrameLevel() + 10)
        block:EnableMouse(true)
        block:SetScript("OnEnter", function()
            EllesmereUI.ShowWidgetTooltip(sw, EllesmereUI.DisabledTooltip("This option requires a Border Size above 0."))
        end)
        block:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        local function UpdateSw()
            updateSw()
            if (getS().castBorderSize or 1) == 0 then
                sw:SetAlpha(0.3); block:Show()
            else
                sw:SetAlpha(1); block:Hide()
            end
        end
        EllesmereUI.RegisterWidgetRefresh(UpdateSw)
        UpdateSw()
    end

    -- Apply-to-all links (main frames page): the style link carries the style,
    -- its offsets, shifts, layering and colour; the size link the size, its
    -- exact px, colour and style. Both carry the opt-in itself.
    if sync then
        local function CopyTo(units, withSize)
            local src = getS()
            for i = 1, #units do
                local d = sync.db(units[i])
                if d and d ~= src then
                    d.castBorderCustom = src.castBorderCustom
                    d.castBorderStyle = src.castBorderStyle
                    d.castBorderOffsetX, d.castBorderOffsetY = src.castBorderOffsetX, src.castBorderOffsetY
                    d.castBorderShiftX, d.castBorderShiftY = src.castBorderShiftX, src.castBorderShiftY
                    local c = src.castBorderColor
                    if c then d.castBorderColor = { r = c.r, g = c.g, b = c.b } end
                    d.castBorderAlpha = src.castBorderAlpha
                    if withSize then
                        d.castBorderSize = src.castBorderSize
                        -- Verbatim; a source with no exact size clears a set one
                        -- with false (nil would not travel through mirror sync).
                        local v = src.castBorderSizePx
                        if v == nil and d.castBorderSizePx ~= nil then v = false end
                        d.castBorderSizePx = v
                    else
                        d.castBorderBehind = src.castBorderBehind
                    end
                end
            end
            onChange()
            for i = 1, #units do EllesmereUI.ReapplyMatchPads(units[i] .. "Castbar") end
            EllesmereUI:RefreshPage()
        end
        local function StyleSynced()
            local src = getS()
            local bt = src.castBorderStyle or "solid"
            for i = 1, #sync.units do
                local d = sync.db(sync.units[i])
                if d then
                    if (d.castBorderCustom == true) ~= (src.castBorderCustom == true) then return false end
                    if (d.castBorderStyle or "solid") ~= bt then return false end
                    if d.castBorderOffsetX ~= src.castBorderOffsetX or d.castBorderOffsetY ~= src.castBorderOffsetY then return false end
                    if d.castBorderShiftX ~= src.castBorderShiftX or d.castBorderShiftY ~= src.castBorderShiftY then return false end
                    if (d.castBorderBehind == true) ~= (src.castBorderBehind == true) then return false end
                end
            end
            return true
        end
        local function SizeSynced()
            local src = getS()
            local bs, bt = src.castBorderSize or 1, src.castBorderStyle or "solid"
            -- Exact sizes compare as rendered (a cleared or stale value equals none).
            local bpx = EllesmereUI.BorderPx(src.castBorderSizePx, bs, bt)
            for i = 1, #sync.units do
                local d = sync.db(sync.units[i])
                if d then
                    if (d.castBorderCustom == true) ~= (src.castBorderCustom == true) then return false end
                    if (d.castBorderSize or 1) ~= bs then return false end
                    if (d.castBorderStyle or "solid") ~= bt then return false end
                    if EllesmereUI.BorderPx(d.castBorderSizePx, bs, bt) ~= bpx then return false end
                end
            end
            return true
        end
        local lr, rr = row._leftRegion, row._rightRegion
        EllesmereUI.BuildSyncIcon({
            region  = lr,
            tooltip = "Apply Cast Bar Border Style to all Frames",
            onClick = function() CopyTo(sync.units, false) end,
            isSynced = StyleSynced,
            flashTargets = function() return { lr } end,
            multiApply = {
                elementKeys   = sync.units,
                elementLabels = sync.labels,
                getCurrentKey = sync.current,
                onApply       = function(keys) CopyTo(keys, false) end,
            },
        })
        EllesmereUI.BuildSyncIcon({
            region  = rr,
            tooltip = "Apply Cast Bar Border to all Frames",
            onClick = function() CopyTo(sync.units, true) end,
            isSynced = SizeSynced,
            flashTargets = function() return { rr } end,
            multiApply = {
                elementKeys   = sync.units,
                elementLabels = sync.labels,
                getCurrentKey = sync.current,
                onApply       = function(keys) CopyTo(keys, true) end,
            },
        })
    end
    return y0 - y
end

-- Boss Frames DISPLAY "Border Style | Border Size": the boss frames' own frame
-- border. "Inherit (Main Frames)" (the first entry; boss borderCustom false)
-- keeps the mini frame donor's border, as before; any other pick stores the
-- boss table's own border, and the size, colour and Border Options cog then
-- edit it (while inheriting they show what is drawn, greyed). A textured style
-- adds Width Offset | Height Offset. Every slot is BlizzStyle.Gate'd, so the
-- stock styles drop the rows. B = the boss settings table (boss1-5 share it);
-- onChange repaints. Returns the height built. On ns: the page builders sit at
-- their upvalue caps.
function ns.UF_BossFrameBorderRows(W, parent, y, B, onChange)
    local BS = EllesmereUI.BlizzStyle
    local y0 = y
    local function Inheriting() return B.borderCustom ~= true end
    -- What the live frames draw: the donor's border while inheriting.
    local function Src() return ns.UF_BossBorderSettings() end
    local NEEDS_STYLE = "This option requires a Border Style other than Inherit (Main Frames)."
    local texValues, texOrder = EllesmereUI.GetBorderTextureDropdown()
    table.insert(texOrder, 1, "inherit")
    texValues.inherit = "Inherit (Main Frames)"
    local row, h = W:DualRow(parent, y,
        BS.Gate("unitframes", { type="dropdown", text="Border Style",
          tooltip="Border art drawn around the boss frames. Inherit (Main Frames) uses the main frames' border.",
          values=texValues, order=texOrder,
          getValue=function()
              if Inheriting() then return "inherit" end
              return B.borderTexture or "solid"
          end,
          setValue=function(v)
              if v == "inherit" then
                  B.borderCustom = false
                  -- Show Behind and Power Bar Seam read the boss table in
                  -- either mode, and their cog hides while inheriting.
                  if B.borderBehind then B.borderBehind = false end
                  if B.borderPowerSeam then B.borderPowerSeam = false end
              else
                  B.borderCustom = true
                  B.borderTexture = v
                  B.borderTextureOffset, B.borderTextureOffsetY = nil, nil
                  B.borderTextureShiftX, B.borderTextureShiftY = nil, nil
                  local col, behind = EllesmereUI.GetBorderStyleSelectDefaults(v)
                  B.borderColor, B.borderAlpha, B.borderBehind = col, 1, behind
                  local defSz = EllesmereUI.GetBorderDefaultSize("unitframes", v)
                  if defSz then B.borderSize = defSz end
                  -- A style pick returns the frames to their legacy step; clear a
                  -- set exact size (false travels through mirror sync, nil would not).
                  if B.borderSizePx then B.borderSizePx = false end
              end
              onChange()
              -- The Width / Height Offset row exists only under a textured style.
              EllesmereUI:RefreshPage(true)
          end }),
        BS.Gate("unitframes", EllesmereUI.BorderPxSliderCfg({ text="Border Size", trackWidth=120,
          disabled=Inheriting, disabledTooltip=NEEDS_STYLE, rawTooltip=true,
          getStep=function() return Src().borderSize or 1 end,
          setStep=function(step) B.borderSize = step end,
          getTex=function() return Src().borderTexture or "solid" end,
          getPx=function() return Src().borderSizePx end,
          setPx=function(v) B.borderSizePx = v end,
          -- The refresh dims the colour swatch at 0.
          apply=function() onChange(); EllesmereUI:RefreshPage() end })))
    y = y - h
    -- Width Offset | Height Offset: a textured style's outward offsets.
    do
        local tex = B.borderTexture or "solid"
        if not Inheriting() and tex ~= "solid" and tex ~= "" then
            local ocfgL, ocfgR = EllesmereUI.BorderOffsetRowCfgs({
                addonKey = "unitframes",
                getTex = function() return B.borderTexture or "solid" end,
                getStep = function() return B.borderSize or 1 end,
                getSizeKey = function() return B.borderSize or 1 end,
                getPx = function() return B.borderSizePx end,
                getX = function() return B.borderTextureOffset end,
                setX = function(v) B.borderTextureOffset = v end,
                getY = function() return B.borderTextureOffsetY end,
                setY = function(v) B.borderTextureOffsetY = v end,
                apply = onChange,
            })
            local _, oh = W:DualRow(parent, y, BS.Gate("unitframes", ocfgL), BS.Gate("unitframes", ocfgR))
            y = y - oh
        end
    end
    if EllesmereUI._prebuilding then return y0 - y end

    -- Border Options cog (left): shifts and layering, own textured styles only.
    do
        -- A stored shift, else the registry default for the style and size.
        local function Shift(key, isY)
            if B[key] then return B[key] end
            local _, _, dsx, dsy = EllesmereUI.GetBorderDefaults("unitframes", B.borderTexture or "solid", B.borderSize or 1)
            if isY then return dsy end
            return dsx
        end
        -- The shown default stores nil, any other value (0 included) is kept.
        local function SetShift(key, isY, v)
            B[key] = nil
            if v ~= Shift(key, isY) then B[key] = v end
            onChange()
        end
        local cogBtn = EllesmereUI.BuildInlineCog(row._leftRegion, { icon = EllesmereUI.DIRECTIONS_ICON,
            title = "Border Options",
            rows = {
                { type = "slider", label = "Shift X", min = -10, max = 10, step = 1,
                  get = function() return Shift("borderTextureShiftX", false) end,
                  set = function(v) SetShift("borderTextureShiftX", false, v) end },
                { type = "slider", label = "Shift Y", min = -10, max = 10, step = 1,
                  get = function() return Shift("borderTextureShiftY", true) end,
                  set = function(v) SetShift("borderTextureShiftY", true, v) end },
                { type = "toggle", label = "Show Behind",
                  get = function() return B.borderBehind == true end,
                  set = function(v) B.borderBehind = v; onChange() end },
                { type = "toggle", label = "Power Bar Seam",
                  tooltip = "Draws the border style's seam art between the health bar and an attached power bar.",
                  disabled = function()
                      local pos = B.powerPosition or "below"
                      local border = Src()
                      return not (EllesmereUI.GetBorderCompanion(border.borderTexture or "solid", "sepH")
                          and (B.borderSizeOverride or border.borderSize or 1) > 0 and (pos == "above" or pos == "below")
                          and (B.powerHeight or 6) > 0)
                  end,
                  disabledTooltip = "This option requires an attached Power Bar, a Border Size above 0 and a border style with seam art.",
                  rawTooltip = true,
                  get = function() return B.borderPowerSeam == true end,
                  set = function(v) B.borderPowerSeam = v; onChange() end },
            },
        })
        local function UpdateCogVis()
            local tex = B.borderTexture or "solid"
            if Inheriting() or tex == "solid" or tex == "" or BS.Get("unitframes") then cogBtn:Hide() else cogBtn:Show() end
        end
        EllesmereUI.RegisterWidgetRefresh(UpdateCogVis)
        UpdateCogVis()
    end

    -- Colour swatch (with alpha) on Border Size: shows what is drawn; greyed
    -- and blocked while inheriting or at 0.
    do
        local rgn = row._rightRegion
        local sw, updateSw = EllesmereUI.BuildColorSwatch(rgn, row:GetFrameLevel() + 3,
            function()
                local s = Src()
                local c = s.borderColor
                return c and c.r or 0, c and c.g or 0, c and c.b or 0, s.borderAlpha or 1
            end,
            function(r, g, b, a)
                B.borderColor = { r = r, g = g, b = b }
                B.borderAlpha = a
                onChange()
            end,
            true, 20)
        EllesmereUI.PanelPP.Point(sw, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        sw:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(sw, "Border") end)
        sw:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        rgn._lastInline = sw
        local block = CreateFrame("Frame", nil, sw)
        block:SetAllPoints()
        block:SetFrameLevel(sw:GetFrameLevel() + 10)
        block:EnableMouse(true)
        block:SetScript("OnEnter", function()
            local req = Inheriting() and NEEDS_STYLE or "This option requires a Border Size above 0."
            EllesmereUI.ShowWidgetTooltip(sw, EllesmereUI.DisabledTooltip(req))
        end)
        block:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        local function UpdateSw()
            updateSw()
            if Inheriting() or (B.borderSize or 1) == 0 then
                sw:SetAlpha(0.3); block:Show()
            else
                sw:SetAlpha(1); block:Hide()
            end
        end
        EllesmereUI.RegisterWidgetRefresh(UpdateSw)
        UpdateSw()
    end
    return y0 - y
end

-- Tracked Auras popup for target/focus/boss debuff filters ("Edit Tracked
-- Auras" pinned action; shared chrome in EllesmereUI_Widgets.lua). Tri-state
-- lists on the unit's settings table (s.debuffInclude/s.debuffExclude); boss1-5
-- share one "boss" table. Copy row clones both lists from another unit. Engine
-- wiring: include link + shared excludes in EUI_UnitFrames_AuraContainers.lua.
local TRACKED_UNITS = {
    { key = "target", label = "Target" },
    { key = "focus",  label = "Focus" },
    { key = "boss",   label = "Boss" },
}
local TRACKED_TITLES = {
    target = "Target Tracked Auras",
    focus  = "Focus Tracked Auras",
    boss   = "Boss Tracked Auras",
}
local function TrackedList(unitKey, field)
    local db = ns.db
    local s = db and db.profile and db.profile[unitKey]
    if not s then return nil end
    if not s[field] then s[field] = {} end
    return s[field]
end
function ns.UFOpt_ShowTrackedAuras(unitKey)
    local choices = {}
    for i = 1, #TRACKED_UNITS do
        local u = TRACKED_UNITS[i]
        if u.key ~= unitKey then choices[#choices + 1] = u end
    end
    local function Changed()
        if ns.ReloadFrames then ns.ReloadFrames() end
        if ns.UpdatePreview then ns.UpdatePreview() end
        -- Non-force: the Debuff Filter dropdown's empty warning (Only Tracked
        -- Auras with its list emptied) re-reads live, without rebuilding the
        -- page under the popup.
        EllesmereUI:RefreshPage()
    end
    EllesmereUI.ShowTrackedAurasPopup({
        eyebrow = "UNIT FRAME AURA FILTERS",
        title = TRACKED_TITLES[unitKey] or "Tracked Auras",
        subtitle = "Included debuffs show in addition to your Debuff Filter selection (unless it is set to Only Tracked Auras).",
        includeGet = function() return TrackedList(unitKey, "debuffInclude") end,
        excludeGet = function() return TrackedList(unitKey, "debuffExclude") end,
        -- Caster scope per entry (the MINE tag on each row). Boss includes default
        -- to Only My Casts (nameplate parity) with an any-caster OPT-OUT map;
        -- target/focus includes default to any caster with a MINE OPT-IN map.
        -- Engine: AppendIncludeLinks in EUI_UnitFrames_AuraContainers.lua.
        includeMine = (unitKey == "boss") and {
            anyGet = function() return TrackedList(unitKey, "debuffIncludeAnyCaster") end,
        } or {
            mineGet = function() return TrackedList(unitKey, "debuffIncludeMine") end,
        },
        includePrompt = "Enter the spell ID to always show on this frame.",
        excludePrompt = "Enter the spell ID to exclude from this frame.",
        onChanged = Changed,
        copyFrom = {
            label = "Copy Included/Excluded Spells From:",
            choices = choices,
            apply = function(srcKey)
                local db = ns.db
                local src = db and db.profile and db.profile[srcKey]
                local dst = db and db.profile and db.profile[unitKey]
                if not (src and dst) then return end
                local function Clone(t)
                    if not t then return nil end
                    local c = {}
                    for k, v in pairs(t) do c[k] = v end
                    return c
                end
                dst.debuffInclude = Clone(src.debuffInclude)
                dst.debuffExclude = Clone(src.debuffExclude)
                -- The caster-scope maps have opposite polarity per unit kind (boss:
                -- any-caster opt-out; target/focus: MINE opt-in). Same kind copies
                -- them as-is; across kinds the set is inverted so every copied
                -- entry keeps the scope it showed with.
                local srcBoss, dstBoss = srcKey == "boss", unitKey == "boss"
                if srcBoss == dstBoss then
                    dst.debuffIncludeAnyCaster = Clone(src.debuffIncludeAnyCaster)
                    dst.debuffIncludeMine = Clone(src.debuffIncludeMine)
                else
                    local srcMap = srcBoss and src.debuffIncludeAnyCaster or src.debuffIncludeMine
                    local inv = {}
                    for id in pairs(src.debuffInclude or {}) do
                        if not (srcMap and srcMap[id]) then inv[id] = true end
                    end
                    if dstBoss then
                        dst.debuffIncludeAnyCaster = inv
                        dst.debuffIncludeMine = nil
                    else
                        dst.debuffIncludeMine = inv
                        dst.debuffIncludeAnyCaster = nil
                    end
                end
                Changed()
            end,
        },
    })
end

-- Options preview: the first fake buff stands in for a purgeable one while
-- Purgeable Buff Glow is set on target/focus and this character can purge or
-- spellsteal (the live frame's own gate). The host is our own frame.
function ns.UFOpt_PreviewPurgeGlow(bf, unitKey, s, w, h)
    local Glows = EllesmereUI.Glows
    if not ns.UF_PurgeGlowSpec then return end
    local g = (unitKey == "target" or unitKey == "focus") and s and s.buffPurgeGlow
    local on = type(g) == "number" and g > 0
    if on then
        local AK = EllesmereUI.AuraKit
        local magic, enrage = false, false
        if AK and AK.OffensiveDispelTypes then magic, enrage = AK.OffensiveDispelTypes() end
        on = magic or enrage
    end
    local host = bf._purgeGlow
    if not on then
        if host then
            if host._euiGlowActive then Glows.StopGlow(host) end
            host:Hide()
        end
        return
    end
    if not host then
        host = CreateFrame("Frame", nil, bf)
        host:SetAllPoints(bf)
        host:SetFrameLevel(bf:GetFrameLevel() + 2)
        bf._purgeGlow = host
    end
    host:Show()
    -- The live renderer's own spec, so the preview is the live look.
    Glows.StartSpecGlow(host, ns.UF_PurgeGlowSpec(s), w, h, "engine", Glows.PANEL_EXTRA)
end

-- Target/focus/boss Debuff Filter: ONE single-select mode, an engine VIEW over
-- the legacy keys (ns.UF_DebuffFilterMode in EUI_UnitFrames_AuraContainers.lua;
-- nothing is rewritten on update, the first pick writes s.debuffFilterMode --
-- the only key this dropdown ever writes). "Edit Tracked Auras" is an action
-- row above a divider; Tracked Auras are additional tracking in every mode,
-- and Only Tracked Auras is the one mode that can render nothing (its tooltip
-- points at the action row, AttachDebuffModeWarn carries the empty warning).
local DEBUFF_MODE_ORDER = {
    "__editTracked", "---",
    "all", "tracked", "own", "important", "importantOwn", "importantOrOwn",
}
local DEBUFF_MODE_TIPS = {
    all            = "Shows every debuff on this frame.",
    tracked        = "Shows only this frame's Tracked Auras; add them with Edit Tracked Auras at the top of this menu.",
    own            = "Shows only the debuffs you apply.",
    important      = "Shows only debuffs Blizzard flags as important.",
    importantOwn   = "Shows only the debuffs you apply that Blizzard also flags as important.",
    importantOrOwn = "Shows the debuffs you apply plus important debuffs from anyone.",
}
local function DebuffModeDropdownCfg(text, unitKey, getS, onChanged, extra)
    local values = {
        __editTracked  = { text = "Edit Tracked Auras", action = function() ns.UFOpt_ShowTrackedAuras(unitKey) end },
        all            = "Show All",
        tracked        = "Only Tracked Auras",
        own            = "Own Only",
        important      = "Important Only",
        importantOwn   = "Important and Own",
        importantOrOwn = "Important or Own",
        _menuOpts = {
            onItemHover = function(key, item)
                local tip = DEBUFF_MODE_TIPS[key]
                if tip and item then EllesmereUI.ShowWidgetTooltip(item, tip) end
            end,
            onItemLeave = function() EllesmereUI.HideWidgetTooltip() end,
        },
    }
    local cfg = {
        type = "dropdown", text = text, values = values, order = DEBUFF_MODE_ORDER,
        getValue = function() return ns.UF_DebuffFilterMode(getS()) end,
        setValue = function(v)
            getS().debuffFilterMode = v
            onChanged()
        end,
    }
    if extra then
        for k, val in pairs(extra) do cfg[k] = val end
    end
    return cfg
end
-- The standard red empty-selection warning on the mode dropdown built by a
-- DualRow slot (rgn._control): shown while Only Tracked Auras has no active
-- entry and the column is not already dimmed by its Display = None.
local function AttachDebuffModeWarn(rgn, getS, offFn)
    local dd = rgn and rgn._control
    if not dd then return end
    EllesmereUI.AttachEmptyFilterWarn(rgn, dd,
        EllesmereUI.L("You are displaying NO debuffs at all."),
        function()
            if offFn() then return true end
            local s = getS()
            return ns.UF_DebuffFilterMode(s) ~= "tracked" or ns.UF_DebuffHasIncludes(s)
        end)
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    -- Init fn on the namespace; the main addon calls it from SetupOptionsPanel()
    -- once ns.db/ns.frames are ready, or immediately if that already ran.
    ns._InitEUIModule = function()
    if not EllesmereUI or not EllesmereUI.RegisterModule then return end
    if not ns.db then return end

    local PP = EllesmereUI.PanelPP
    local db = ns.db
    local frames = ns.frames
    local ReloadFrames = ns.ReloadFrames
    local ResolveFontPath = ns.ResolveFontPath

    local floor = math.floor
    local abs = math.abs

    local GetUFOptOutline = EllesmereUI.GetFontOutlineFlag
    local SetPVFont = EllesmereUI.ApplyModuleFont

    ---------------------------------------------------------------------------
    --  Shared helpers
    ---------------------------------------------------------------------------
    local activePreview
    local allPreviews = {}

    -- Mutable state the page builders share. A table instead of locals so the
    -- builders under UnitFrames_Options\ read and write the live values.
    local optState = {}
    optState.showCombatIndicatorPreview = false
    optState.showHealAbsorbPreview      = false  -- eyeball toggle for the Heal Absorb Style preview
    optState.showDispelOverlayPreview   = false  -- eyeball toggle for the player dispel overlay preview
    -- Preview hover-highlight hint text (shared across Single/Multi tabs)
    optState._ufPreviewHintFS_display = nil  -- hint FontString for the Main Frames page
    local _displayHeaderBaseH = 0      -- display header height WITHOUT hint

    local function IsPreviewHintDismissed()
        return EllesmereUIDB and EllesmereUIDB.previewHintDismissed
    end

    -- Preview click -> scroll to and glow the mapped row (Main, Mini and Boss
    -- pages). A target may be a resolver function (e.g. boss buff/debuff icons,
    -- which point to Simple Display or Location depending on the mode). On ns
    -- to stay clear of the 200-local cap; dismissHint is Main-page only.
    ns._UFNavigateToSetting = function(targets, key, playGlow, dismissHint)
        if not targets then return end
        local m = targets[key]
        if type(m) == "function" then m = m() end
        if not m or not m.section or not m.target then return end
        if dismissHint then EllesmereUI.DismissPreviewHint(optState._ufPreviewHintFS_display, _displayHeaderBaseH, 29, 17) end
        local sf = EllesmereUI._scrollFrame
        if not sf then return end
        local _, _, _, _, headerY = m.section:GetPoint(1)
        if not headerY then return end
        local scrollPos = math.max(0, math.abs(headerY) - 40)
        EllesmereUI.SmoothScrollTo(scrollPos)
        local glowTarget = m.target
        if m.slotSide and m.target then
            local region = (m.slotSide == "left") and m.target._leftRegion or m.target._rightRegion
            if region then glowTarget = region end
        end
        C_Timer.After(0.15, function() playGlow(glowTarget) end)
    end

    local function UpdatePreview()
        for _, pv in pairs(allPreviews) do
            if pv and pv.Update then pv:Update() end
        end
        -- Sync in-game boss preview fake debuffs with live edits (location, simple display, size).
        if ns.RefreshBossPreviewDebuffs then ns.RefreshBossPreviewDebuffs() end
    end

    local function ReloadAndUpdate()
        -- Resolve at call time: ns.ReloadFrames is wrapped after this file's setup
        -- (aura containers, dispel overlay); a load-time capture bypasses those hooks.
        local rf = ns.ReloadFrames or ReloadFrames
        if rf then rf() end
        UpdatePreview()
    end

    EllesmereUI:RegisterOnShow(UpdatePreview)
    ns.UpdatePreview = UpdatePreview

    -- Re-run preview Update() when panel scale changes so border pixel sizes refresh
    if not EllesmereUI._onScaleChanged then EllesmereUI._onScaleChanged = {} end
    EllesmereUI._onScaleChanged[#EllesmereUI._onScaleChanged + 1] = UpdatePreview

    -- Hide UIParent-parented disabled overlays when the options window closes
    EllesmereUI:RegisterOnHide(function()
        for _, pv in pairs(allPreviews) do
            if pv and pv._disabledOverlay then pv._disabledOverlay:Hide() end
        end
        -- Auto-disable in-game boss preview so live boss frames don't linger on close.
        if ns._bossPreviewActive and ns.SetBossPreview then
            ns.SetBossPreview(false)
        end
        -- Player Aura Bars root lives on the shared live scrollFrame, not a page's
        -- own `parent`; only fires on full window close (cf. _bmRoot/_dmRoot/_ccRoot
        -- cleanup in EUI_RaidFrames_Options.lua). Module switching is handled below via SelectModule.
        if ns._pabRoot then
            ns._pabRoot:Hide()
            ns._pabRoot:SetParent(nil)
            ns._pabRoot = nil
        end
    end)

    -- Rebuild Player Aura Bars on re-open while already on that page: RegisterOnHide
    -- tore _pabRoot down, and unlike a tab switch (buildPage/onPageCacheRestore) a
    -- plain re-open rebuilds nothing. Mirrors RF's RegisterOnShow in EUI_RaidFrames_Options.lua.
    EllesmereUI:RegisterOnShow(function()
        if EllesmereUI:GetActiveModule() == "EllesmereUIUnitFrames"
           and EllesmereUI:GetActivePage() == PAGE_AURA_BARS
           and not ns._pabRoot then
            C_Timer.After(0, function()
                if EllesmereUI:GetActiveModule() == "EllesmereUIUnitFrames" and ns.PABMP_BuildPage then
                    ns.PABMP_BuildPage(PAGE_AURA_BARS, nil, -6)
                end
            end)
        end
    end)

    -- Tear down _pabRoot on switch to a DIFFERENT top-level module: window stays
    -- open (RegisterOnHide never fires) and the root would overlap the new module's
    -- content. Mirrors RF's SelectModule cleanup in EUI_RaidFrames_Options.lua.
    if EllesmereUI.SelectModule then
        hooksecurefunc(EllesmereUI, "SelectModule", function(_, folderName)
            if folderName ~= "EllesmereUIUnitFrames" and ns._pabRoot then
                ns._pabRoot:Hide()
                ns._pabRoot:SetParent(nil)
                ns._pabRoot = nil
            end
        end)
    end

    ---------------------------------------------------------------------------
    --  Individual Display unit selector
    ---------------------------------------------------------------------------
    optState.selectedUnit = "player"

    -- External unit pre-select: direct setter + pending override consumed at page build.
    EllesmereUI._setUnitFrameUnit = function(unit) optState.selectedUnit = unit end
    EllesmereUI._consumePendingUnitSelect = function()
        local pending = EllesmereUI._pendingUnitSelect
        if pending then
            optState.selectedUnit = pending
            EllesmereUI._pendingUnitSelect = nil
        end
    end

    local unitLabels = {
        ["player"]       = "Player",
        ["target"]       = "Target",
        ["focus"]        = "Focus",
        ["targettarget"] = "Target of Target",
        ["focustarget"]  = "Focus Target",
        ["pet"]          = "Pet",
        ["boss"]         = "Boss",
    }
    local unitOrder = { "player", "target", "focus" }

    -- Side mapping: which side the portrait sits on for each unit
    local unitSide = {
        ["player"]       = "left",
        ["target"]       = "right",
        ["focus"]        = "right",
        ["targettarget"] = "left",
        ["focustarget"]  = "left",
        ["pet"]          = "left",
        ["boss"]         = "right",
    }

    ---------------------------------------------------------------------------
    --  Group editing state  (sync icon targets)
    ---------------------------------------------------------------------------
    local UNIT_DB_MAP = {
        player       = function() return db.profile.player end,
        target       = function() return db.profile.target end,
        focus        = function() return db.profile.focus end,
        targettarget = function() return db.profile.targettarget end,
        focustarget  = function() return db.profile.focustarget end,
        pet          = function() return db.profile.pet end,
        boss         = function() return db.profile.boss end,
    }

    ---------------------------------------------------------------------------
    --  Glow site: the target/focus Purgeable Buff Glow as a shared glow
    --  descriptor over one unit's settings (getS), used by the Buffs cog and the
    --  Global Settings Glows page. Engine aura buttons: C-side styles only; an
    --  unset color is the suite default (gold).
    ---------------------------------------------------------------------------
    local function UF_PurgeGlowDesc(getS)
        -- Blizzard Border: Blizzard's static stealable art, outside the style list.
        local border = EllesmereUI.Glows.STEALABLE_BORDER
        return {
            host = "engine",
            extras = { { value = border, label = "Blizzard Border", style = border } },
            caps = { mode = true, params = true, bg = true },
            defaultColor = EllesmereUI.Glows.DEFAULT_COLOR,
            onChange = ReloadAndUpdate,
            get = function(f)
                local s = getS()
                if f == "style" then return s.buffPurgeGlow or 0
                elseif f == "mode" then
                    return s.buffPurgeGlowColorMode or (s.buffPurgeGlowColor and "custom" or "default")
                end
                return EllesmereUI.GlowOptions.FlatGet(s, "buffPurgeGlow", f)
            end,
            set = function(f, a, b, c)
                local s = getS()
                if f == "style" then s.buffPurgeGlow = (a ~= 0) and a or nil
                elseif f == "mode" then s.buffPurgeGlowColorMode = a
                else EllesmereUI.GlowOptions.FlatSet(s, "buffPurgeGlow", f, a, b, c)
                end
            end,
        }
    end
    -- Target/focus Important Cast Glow: a bar host storing shared style
    -- indices (every style but Shape); an unset mode is the stored custom color.
    local function UF_ImpCastGlowDesc(getS, onChange)
        return {
            host = "bar",
            caps = { mode = true, params = true, bg = true },
            defaultColor = { r = 1, g = 0.2, b = 0.2 },
            onChange = onChange or ReloadAndUpdate,
            isOff = function() return getS().castbarImportantGlow ~= true end,
            get = function(f)
                local s = getS()
                if f == "style" then return s.castbarImportantGlowStyle or 1
                elseif f == "mode" then return s.castbarImportantGlowColorMode or "custom"
                end
                return EllesmereUI.GlowOptions.FlatGet(s, "castbarImportantGlow", f)
            end,
            set = function(f, a, b, c)
                local s = getS()
                if f == "style" then
                    if a == 0 then s.castbarImportantGlow = false
                    else s.castbarImportantGlow = true; s.castbarImportantGlowStyle = a end
                elseif f == "mode" then s.castbarImportantGlowColorMode = a
                else EllesmereUI.GlowOptions.FlatSet(s, "castbarImportantGlow", f, a, b, c)
                end
            end,
        }
    end
    do
        local GO = EllesmereUI.GlowOptions
        -- Open Settings selects the unit first (the page shows one unit at a time).
        local function SelectUnit(unit)
            return function() EllesmereUI._setUnitFrameUnit(unit); EllesmereUI._pendingUnitSelect = unit end
        end
        GO.RegisterSite({ id = "uf_purge_target", label = "Target Purgeable Buff Glow", group = "module",
            module = "EllesmereUIUnitFrames", page = PAGE_DISPLAY, section = "BUFFS AND DEBUFFS",
            preSelect = SelectUnit("target"),
            -- The Purgeable Buffs cog sits on the unit's Buff Filter row.
            highlight = "Buff Filter",
            desc = UF_PurgeGlowDesc(UNIT_DB_MAP.target) })
        GO.RegisterSite({ id = "uf_purge_focus", label = "Focus Purgeable Buff Glow", group = "module",
            module = "EllesmereUIUnitFrames", page = PAGE_DISPLAY, section = "BUFFS AND DEBUFFS",
            preSelect = SelectUnit("focus"),
            highlight = "Buff Filter",
            desc = UF_PurgeGlowDesc(UNIT_DB_MAP.focus) })
        GO.RegisterSite({ id = "uf_importantcast_target", label = "Target Important Cast Glow", group = "module",
            module = "EllesmereUIUnitFrames", page = PAGE_DISPLAY, section = "CAST BAR",
            preSelect = SelectUnit("target"), highlight = "Important Cast Glow",
            desc = UF_ImpCastGlowDesc(UNIT_DB_MAP.target) })
        GO.RegisterSite({ id = "uf_importantcast_focus", label = "Focus Important Cast Glow", group = "module",
            module = "EllesmereUIUnitFrames", page = PAGE_DISPLAY, section = "CAST BAR",
            preSelect = SelectUnit("focus"), highlight = "Important Cast Glow",
            desc = UF_ImpCastGlowDesc(UNIT_DB_MAP.focus) })
    end

    local GROUP_UNIT_ORDER = { "player", "target", "focus" }
    local SHORT_LABELS = {
        player       = "Player",
        target       = "Target",
        focus        = "Focus",
        targettarget = "Target of Target",
        focustarget  = "Focus Target",
        pet          = "Pet",
        boss         = "Boss",
    }


    ---------------------------------------------------------------------------
    --  Health display dropdown values
    ---------------------------------------------------------------------------
    local healthDisplayValues = {
        ["both"]       = "Current HP | Percent",
        ["curhpshort"] = "Current HP Only",
        ["perhp"]      = "Percent Only",
    }
    local healthDisplayOrder = { "both", "curhpshort", "perhp" }

    ---------------------------------------------------------------------------
    --  Health bar texture dropdown -- built LIVE each render (mirrors
    --  GetBorderTextureDropdown) so SharedMedia textures registered after login
    --  always appear; an LSM callback also keeps the shared ns tables current.
    ---------------------------------------------------------------------------
    local function BuildBarTexDropdown()
        -- Refresh shared snapshot from LSM; first call also registers the
        -- late-registration callback (idempotent after).
        EllesmereUI.AppendSharedMediaTextures(
            ns.healthBarTextureNames or {},
            ns.healthBarTextureOrder or {},
            nil,
            ns.healthBarTextures
        )

        local hbtValues, hbtOrder = {}, {}
        local texNames = ns.healthBarTextureNames or {}
        local texOrder2 = ns.healthBarTextureOrder or {}
        for _, key in ipairs(texOrder2) do
            if key ~= "---" then
                hbtValues[key] = texNames[key] or key
                hbtOrder[#hbtOrder + 1] = key
            end
        end
        -- _menuOpts: texture preview backgrounds on each item
        local texLookup = ns.healthBarTextures or {}
        hbtValues._menuOpts = {
            itemHeight = 28,
            background = function(key)
                return texLookup[key]
            end,
            onItemHover = function(key)
                local texPath = texLookup[key]
                for _, pv in pairs(allPreviews) do
                    if pv then
                        local hFill = pv._healthFill
                        if hFill then
                            if texPath then
                                hFill:SetTexture(texPath)
                                hFill:SetVertexColor(pv._hR or 0.8, pv._hG or 0.2, pv._hB or 0.2, 1)
                            else
                                hFill:SetVertexColor(1, 1, 1, 1)
                                hFill:SetColorTexture(pv._hR or 0.8, pv._hG or 0.2, pv._hB or 0.2, 1)
                            end
                        end
                        local pFill = pv._powerFill
                        if pFill then
                            local pvR, pvG, pvB = pv._pR or 0, pv._pG or 0, pv._pB or 1
                            if texPath then
                                pFill:SetTexture(texPath)
                                pFill:SetVertexColor(pvR, pvG, pvB, 1)
                            else
                                pFill:SetVertexColor(1, 1, 1, 1)
                                pFill:SetColorTexture(pvR, pvG, pvB, 1)
                            end
                        end
                    end
                end
            end,
            onItemLeave = function(key)
                -- Revert to the saved texture
                for _, pv in pairs(allPreviews) do
                    if pv and pv.Update then pv:Update() end
                end
            end,
        }
        return hbtValues, hbtOrder
    end

    ---------------------------------------------------------------------------
    --  Buff anchor / growth direction dropdown values
    ---------------------------------------------------------------------------
    local buffAnchorValues = {
        ["none"]        = "None",
        ["topleft"]     = "Top Left",
        ["topright"]    = "Top Right",
        ["bottomleft"]  = "Bottom Left",
        ["bottomright"] = "Bottom Right",
        ["left"]        = "Left",
        ["right"]       = "Right",
    }
    local buffAnchorOrder = { "none", "topleft", "topright", "bottomleft", "bottomright", "left", "right" }

    local buffGrowthValues = {
        ["auto"]  = "Auto",
        ["up"]    = "Up",
        ["down"]  = "Down",
        ["left"]  = "Left",
        ["right"] = "Right",
    }
    local buffGrowthOrder = { "auto", "up", "down", "left", "right" }

    local classPowerStyleValues = {
        ["none"]     = "None",
        ["modern"]   = "Modern",
        ["blizzard"] = "Blizzard",
    }
    local classPowerStyleOrder = { "none", "modern", "blizzard" }

    local classPowerPosValues = {
        ["top"]    = "Top",
        ["bottom"] = "Bottom",
        ["above"]  = "Above Health Bar",
    }
    local classPowerPosOrder = { "top", "bottom", "above" }

    ---------------------------------------------------------------------------
    --  Text content dropdown values (left / right text)
    ---------------------------------------------------------------------------
    -- Health bar text dropdown values (no power options)
    local healthTextValues = {
        ["name"]         = "Name",
        ["nametotarget"] = "Name > Target",
        ["targetname"]   = "Target",
        ["levelname"]    = "Level | Name",
        ["namelevel"]    = "Name | Level",
        ["level"]        = "Level",
        ["perhp"]        = "Health %",
        ["perhpnosign"]  = "Health % (No Sign)",
        ["curhpshort"]   = "Health #",
        ["perhpnum"]     = "Health % | #",
        ["both"]         = "Health # | %",
        ["bothdash"]     = "Health # - %",
        ["perhpnumdash"] = "Health % - #",
        ["absorb"]       = "Absorb Amount",
        ["absorbshort"]  = "Absorb Short (230k)",
        ["healabsorb"]      = "Heal Absorb Amount",
        ["healabsorbshort"] = "Heal Absorb Short (80k)",
        ["group"]        = "Group Number",
        ["none"]         = "None",
    }
    local healthTextOrder = { "none", "---", "name", "levelname", "namelevel", "level", "perhp", "perhpnosign", "curhpshort", "perhpnum", "both" }
    -- Boss frames also get "Name > Target" (the boss's target); ToT/FoT/Pet do not.
    local healthTextOrderBoss = { "none", "---", "name", "nametotarget", "targetname", "levelname", "namelevel", "level", "perhp", "perhpnosign", "curhpshort", "perhpnum", "both", "bothdash", "perhpnumdash", "absorb", "absorbshort", "healabsorb", "healabsorbshort" }
    local healthTextOrderPlayer = { "none", "---", "name", "nametotarget", "targetname", "levelname", "namelevel", "level", "perhp", "perhpnosign", "curhpshort", "perhpnum", "both", "bothdash", "perhpnumdash", "absorb", "absorbshort", "healabsorb", "healabsorbshort", "group" }
    -- Target/Focus: player's absorb options minus "group" (raid group number is meaningless off the player).
    local healthTextOrderTargetFocus = { "none", "---", "name", "nametotarget", "targetname", "levelname", "namelevel", "level", "perhp", "perhpnosign", "curhpshort", "perhpnum", "both", "bothdash", "perhpnumdash", "absorb", "absorbshort", "healabsorb", "healabsorbshort" }

    -- Text bar (BTB) text dropdown values (includes power options)
    local btbTextValues = {
        ["name"]         = "Name",
        ["perhp"]        = "Health %",
        ["perhpnosign"]  = "Health % (No Sign)",
        ["curhpshort"]   = "Health #",
        ["perhpnum"]     = "Health % | #",
        ["both"]         = "Health # | %",
        ["perpp"]        = "Power %",
        ["curpp"]        = "Power Value",
        ["curhp_curpp"]  = "Health | Power Value",
        ["perhp_perpp"]  = "Health | Power %",
        ["none"]         = "None",
    }
    local btbTextOrder = { "none", "---", "name", "perhp", "perhpnosign", "curhpshort", "perhpnum", "both", "perpp", "curpp", "curhp_curpp", "perhp_perpp" }

    -- Class theme portrait icons: full-size versions of the sidebar class art.
    local ICONS_PATH = "Interface\\AddOns\\EllesmereUI\\media\\icons\\"
    local CLASS_FULL_SPRITE_BASE = ICONS_PATH .. "class-full\\"

    local CLASS_FULL_COORDS = EllesmereUI.CLASS_ICON_SPRITE_COORDS

    local classIconValues = {
        ["none"]="None", ["modern"]="Modern",
        ["arcade"]="Arcade", ["glyph"]="Glyph", ["legend"]="Legend",
        ["midnight"]="Midnight", ["pixel"]="Pixel", ["pixelsComic"]="Pixels Comic", ["runic"]="Runic",
        _menuOpts = { itemHeight = 32, icon = function(key)
            if key == "none" then return nil end
            local _, ct = UnitClass("player")
            if not ct then return nil end
            local coords = CLASS_FULL_COORDS[ct]
            if not coords then return nil end
            return CLASS_FULL_SPRITE_BASE .. key .. ".tga", coords[1], coords[2], coords[3], coords[4]
        end },
    }
    local classIconOrder = { "none", "---", "arcade", "glyph", "legend", "midnight", "modern", "pixel", "pixelsComic", "runic" }
    local classIconLocValues = { ["left"]="Left", ["center"]="Center", ["right"]="Right" }
    local classIconLocOrder = { "left", "center", "right" }

    -- Swap helper for buff/debuff anchors: prevent both from occupying the same slot
    local function SwapAuraSlot(settingsTable, changedKey, newVal)
        local otherKey = (changedKey == "buffAnchor") and "debuffAnchor" or "buffAnchor"
        local otherVal = settingsTable[otherKey] or (otherKey == "buffAnchor" and "topleft" or "bottomleft")
        if otherVal == newVal then
            local oldVal = settingsTable[changedKey] or (changedKey == "buffAnchor" and "topleft" or "bottomleft")
            settingsTable[otherKey] = oldVal
        end
        settingsTable[changedKey] = newVal
    end

    ---------------------------------------------------------------------------
    --  Preview builder: cosmetic health/power bar + portrait + castbar preview
    ---------------------------------------------------------------------------
    local PREVIEW_FONT = (EllesmereUI.GetFontPath("unitFrames"))
        or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"
    local SOLID_BACKDROP = { bgFile = "Interface\\Buttons\\WHITE8X8" }
    local BORDER_BACKDROP = { edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 }

    -- Generic portrait image for NPC previews (player uses SetPortraitTexture)
    local ENEMY_PORTRAIT_PATH = "Interface\\AddOns\\EllesmereUI\\media\\enemy-portrait.png"

    -- Portrait mask/border media paths (for detached portrait shape preview)
    local PORTRAIT_MASKS_P = EllesmereUI.SHAPE_MASKS
    local PORTRAIT_BORDERS_P = EllesmereUI.SHAPE_BORDERS

    -- Top pixel inset for each mask shape (px from edge to visible portrait area)
    local MASK_INSETS = EllesmereUI.SHAPE_INSETS

    -- mirror = true swaps the cell's left/right coords (Mirror Portrait).
    local function ApplyClassIconTexture_Preview(tex, classToken, style, mirror)
        local coords = CLASS_FULL_COORDS[classToken]
        if not coords then return false end
        tex:SetTexture(CLASS_FULL_SPRITE_BASE .. style .. ".tga")
        if mirror then
            tex:SetTexCoord(coords[2], coords[1], coords[3], coords[4])
        else
            tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        end
        return true
    end

    -- Apply detached portrait shape to preview portraitFrame pFrame; s = per-unit settings.
    local function ApplyPreviewPortraitShape(pFrame, s)
        if not pFrame then return end
        local isDetached = (s.portraitStyle or db.profile.portraitStyle or "attached") == "detached"
        local shape = s.detachedPortraitShape or "portrait"
        local showBorder = true
        local borderOpacity = (s.detachedPortraitBorderOpacity or 100) / 100
        local borderColor = s.detachedPortraitBorderColor or { r = 0, g = 0, b = 0 }
        local useClassColor = s.detachedPortraitClassColor or false
        local rawBorderSize = s.detachedPortraitBorderSize or 7
        local bExp = 7 - rawBorderSize  -- scale border UP; mask clips inner portion
        -- Use the resolved art mode so NPC fallbacks keep their own zoom.
        local classInset
        if pFrame._previewMode == "class" then
            local bh = pFrame:GetHeight()
            if bh < 1 then bh = 46 end
            classInset = math.floor(bh * 0.08)
        end

        local bR, bG, bB = borderColor.r, borderColor.g, borderColor.b
        if useClassColor then
            local _, ct = UnitClass("player")
            if ct then
                local c = RAID_CLASS_COLORS[ct]
                if c then bR, bG, bB = c.r, c.g, c.b end
            end
        end

        local texList = {}
        if pFrame._previewTex then table.insert(texList, pFrame._previewTex) end
        if pFrame._previewBg then table.insert(texList, pFrame._previewBg) end

        -- Remove mask when not detached
        if not isDetached then
            if pFrame._shapeMask then
                for _, tex in ipairs(texList) do tex:RemoveMaskTexture(pFrame._shapeMask) end
                pFrame._shapeMask:Hide()
            end
            if pFrame._shapeBorderTex then pFrame._shapeBorderTex:Hide() end
            if pFrame._sqBorderTexs then
                for _, t in ipairs(pFrame._sqBorderTexs) do t:Hide() end
            end
            -- Reset texture positions to default (detached mode expands them for mask fill)
            if pFrame._previewTex then
                if classInset then
                    ns.UF_SetClassPortraitPoints(pFrame._previewTex, pFrame,
                        s.portraitClassZoom, classInset, classInset)
                else
                    pFrame._previewTex:ClearAllPoints()
                    pFrame._previewTex:SetPoint("TOPLEFT", pFrame, "TOPLEFT", 0, 0)
                    pFrame._previewTex:SetPoint("BOTTOMRIGHT", pFrame, "BOTTOMRIGHT", 0, 0)
                end
            end
            if pFrame._previewModel then
                pFrame._previewModel:ClearAllPoints()
                pFrame._previewModel:SetPoint("TOPLEFT", pFrame, "TOPLEFT", 0, 0)
                pFrame._previewModel:SetPoint("BOTTOMRIGHT", pFrame, "BOTTOMRIGHT", 0, 0)
            end
            ns.UF_PortraitExtras(pFrame, nil)
            return
        end

        -- === MASK ===
        if shape == "none" then
            -- "None": remove mask, border, and background
            if pFrame._previewBg then pFrame._previewBg:Hide() end
            if pFrame._shapeMask then
                for _, tex in ipairs(texList) do pcall(tex.RemoveMaskTexture, tex, pFrame._shapeMask) end
                pFrame._shapeMask:Hide()
            end
            if pFrame._shapeBorderTex then pFrame._shapeBorderTex:Hide() end
            if pFrame._sqBorderTexs then
                for _, t in ipairs(pFrame._sqBorderTexs) do t:Hide() end
            end
            if pFrame._previewTex then
                if classInset then
                    ns.UF_SetClassPortraitPoints(pFrame._previewTex, pFrame,
                        s.portraitClassZoom, classInset, classInset)
                else
                    pFrame._previewTex:ClearAllPoints()
                    pFrame._previewTex:SetPoint("TOPLEFT", pFrame, "TOPLEFT", 0, 0)
                    pFrame._previewTex:SetPoint("BOTTOMRIGHT", pFrame, "BOTTOMRIGHT", 0, 0)
                end
            end
            if pFrame._previewModel then
                pFrame._previewModel:ClearAllPoints()
                pFrame._previewModel:SetPoint("TOPLEFT", pFrame, "TOPLEFT", 0, 0)
                pFrame._previewModel:SetPoint("BOTTOMRIGHT", pFrame, "BOTTOMRIGHT", 0, 0)
            end
            ns.UF_PortraitExtras(pFrame, nil)
            return
        end
        if pFrame._previewBg then pFrame._previewBg:Show() end
        local maskPath = PORTRAIT_MASKS_P[shape]
        if maskPath then
            if not pFrame._shapeMask then
                pFrame._shapeMask = pFrame:CreateMaskTexture()
                pFrame._shapeMask:SetAllPoints(pFrame)
            end
            pFrame._shapeMask:SetTexture(maskPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            pFrame._shapeMask:Show()
            for _, tex in ipairs(texList) do tex:AddMaskTexture(pFrame._shapeMask) end
        end

        -- Hide old square border textures if they exist on this frame
        if pFrame._sqBorderTexs then
            for _, t in ipairs(pFrame._sqBorderTexs) do t:Hide() end
        end

        -- === TGA BORDER OVERLAY ===
        if not pFrame._shapeBorderTex then
            pFrame._shapeBorderTex = pFrame:CreateTexture(nil, "OVERLAY")
            if pFrame._shapeBorderTex.SetSnapToPixelGrid then pFrame._shapeBorderTex:SetSnapToPixelGrid(false); pFrame._shapeBorderTex:SetTexelSnappingBias(0) end
        end
        -- Pixels Circle (ns.UF_UNMASKED_RING) keeps its ring outside the mask,
        -- inset from the frame edge, exactly as on the live portrait.
        local ringInset = ns.UF_UNMASKED_RING[shape]
        local off = bExp - (ringInset or 0)
        pFrame._shapeBorderTex:ClearAllPoints()
        PP.Point(pFrame._shapeBorderTex, "TOPLEFT", pFrame, "TOPLEFT", -off, off)
        PP.Point(pFrame._shapeBorderTex, "BOTTOMRIGHT", pFrame, "BOTTOMRIGHT", off, -off)
        -- Add border to mask so the mask clips its inner edge
        if pFrame._shapeMask then
            pcall(pFrame._shapeBorderTex.RemoveMaskTexture, pFrame._shapeBorderTex, pFrame._shapeMask)
            if not ringInset then pFrame._shapeBorderTex:AddMaskTexture(pFrame._shapeMask) end
        end
        if showBorder then
            local bp = PORTRAIT_BORDERS_P[shape]
            if bp then
                pFrame._shapeBorderTex:SetTexture(bp)
                pFrame._shapeBorderTex:SetVertexColor(bR, bG, bB, borderOpacity)
                pFrame._shapeBorderTex:Show()
            else
                pFrame._shapeBorderTex:Hide()
            end
        else
            pFrame._shapeBorderTex:Hide()
        end

        -- Scale portrait content so its visible area fills the mask opening;
        -- border size does not affect content.
        local insetPx = MASK_INSETS[shape] or 17
        local bw = pFrame:GetWidth()
        local bh2 = pFrame:GetHeight()
        if bw < 1 then bw = 46 end
        if bh2 < 1 then bh2 = 46 end
        local visRatio = (128 - 2 * insetPx) / 128
        local cScale = 1 / visRatio
        -- Apply user art scale (100 = default, stored as percentage)
        local artScale = (s.portraitArtScale or 100) / 100
        cScale = cScale * artScale
        local expand = (cScale - 1) * 0.5
        local oL = -(expand * bw)
        local oR =  (expand * bw)
        local oT =  (expand * bh2)
        local oB = -(expand * bh2)
        if pFrame._previewTex then
            if classInset then
                ns.UF_SetClassPortraitPoints(pFrame._previewTex, pFrame,
                    s.portraitClassZoom, classInset + oL, classInset - oT)
            else
                pFrame._previewTex:ClearAllPoints()
                PP.Point(pFrame._previewTex, "TOPLEFT", pFrame, "TOPLEFT", oL, oT)
                PP.Point(pFrame._previewTex, "BOTTOMRIGHT", pFrame, "BOTTOMRIGHT", oR, oB)
            end
        end
        if pFrame._previewModel then
            -- 3D models ignore SetClipsChildren, so pin them to the frame bounds.
            pFrame._previewModel:ClearAllPoints()
            PP.Point(pFrame._previewModel, "TOPLEFT", pFrame, "TOPLEFT", 0, 0)
            PP.Point(pFrame._previewModel, "BOTTOMRIGHT", pFrame, "BOTTOMRIGHT", 0, 0)
        end

        -- Outer Ring / Inner Shadow: the live portrait's own helper. A shown
        -- Outer Ring and an unmasked ring below Size 7 reach past the frame,
        -- so the detached preview stops clipping (every layout branch of
        -- Update sets its clip again first; the Portrait Dragon lifts it on
        -- its own after this).
        ns.UF_PortraitExtras(pFrame, s, shape)
        if ringInset or (pFrame._outerRing and pFrame._outerRing:IsShown()) then
            pFrame:SetClipsChildren(false)
        end
    end

    -- Portrait art style dropdown values
    local classThemeSubValues = {
        ["modern"]="Modern", ["arcade"]="Arcade", ["glyph"]="Glyph",
        ["legend"]="Legend", ["midnight"]="Midnight", ["pixel"]="Pixel", ["pixelsComic"]="Pixels Comic",
        ["runic"]="Runic",
    }
    local classThemeSubOrder = { "modern", "arcade", "glyph", "legend", "midnight", "pixel", "pixelsComic", "runic" }
    local portraitArtValues = {
        ["3d"]    = "3D Portrait",
        ["2d"]    = "2D Portrait",
        ["class"] = {
            text = "Class",
            subnav = {
                order = classThemeSubOrder,
                values = classThemeSubValues,
                onSelect = nil,  -- wired per-unit below
                icon = nil,      -- wired per-unit below
                itemHeight = 32,
            },
        },
    }
    local portraitArtOrder = { "3d", "2d", "class" }

    -- What a non-player shows on a Class art frame (class art is player-only).
    local portraitNonPlayerValues = {
        ["2d"]   = "2D Portrait",
        ["none"] = "Nothing",
        ["3d"]   = "3D Portrait",
    }
    local portraitNonPlayerOrder = { "2d", "none", "3d" }

    -- Portrait mode dropdown values; "none" hides the portrait entirely.
    local portraitModeValues2 = {
        ["none"]     = "None",
        ["attached"] = "Attached",
        ["detached"] = "Detached",
    }
    local portraitModeOrder2 = { "none", "attached", "detached" }

    -- Detached portrait shape dropdown values
    local detPortraitShapeValues = {
        ["none"]     = "None",
        ["portrait"] = "Portrait",
        ["circle"]   = "Circle",
        ["pixelsCircle"] = "Pixels Circle",
        ["square"]   = "Square",
        ["csquare"]  = "Rounded Square",
        ["diamond"]  = "Diamond",
        ["hexagon"]  = "Hexagon",
        ["shield"]   = "Shield",
    }
    local detPortraitShapeOrder = { "none", "portrait", "circle", "pixelsCircle", "square", "csquare", "diamond", "hexagon", "shield" }

    -- Text Bar position dropdown values
    local btbPositionValues = {
        ["top"]             = "Top",
        ["bottom"]          = "Bottom",
        ["detached_top"]    = "Detached Top",
        ["detached_bottom"] = "Detached Bottom",
    }
    local btbPositionOrder = { "top", "bottom", "detached_top", "detached_bottom" }

    -- Enemy NPC names for preview (randomized on tab switch)
    local PREVIEW_ENEMY_NAMES = {
        "Doomguard", "Dreadlord", "Infernal", "Sea Giant", "Ogre Mage",
        "Satyr", "Stone Golem", "Water Elemental", "Silithid", "Naga Siren",
    }
    local PREVIEW_BOSS_NAMES = {
        "The Lich King", "Varimathras", "Cenarius", "Ragnaros", "Kel'Thuzad",
        "Archimonde", "Kil'jaeden", "Deathwing", "Yogg-Saron", "C'Thun",
    }
    -- Persistent random creature names per unit -- regenerated only on tab switch
    local _previewCreatureNames = {}

    -- Class cast spells for player preview (cast-time spells only; icons resolved
    -- at runtime via C_Spell.GetSpellInfo).
    local CLASS_CAST_SPELLS = {
        WARRIOR     = { {name="Slam", castTime=1.5}, {name="Whirlwind", castTime=1.5} },
        PALADIN     = { {name="Flash of Light", castTime=1.5}, {name="Holy Light", castTime=2.5}, {name="Hammer of Wrath", castTime=1.0} },
        HUNTER      = { {name="Aimed Shot", castTime=2.5}, {name="Steady Shot", castTime=1.8}, {name="Cobra Shot", castTime=2.0} },
        ROGUE       = { {name="Kidney Shot", castTime=1.5} },
        PRIEST      = { {name="Flash Heal", castTime=1.5}, {name="Smite", castTime=1.5}, {name="Mind Blast", castTime=1.5}, {name="Greater Heal", castTime=2.5} },
        DEATHKNIGHT = { {name="Death Coil", castTime=1.5}, {name="Howling Blast", castTime=1.5} },
        SHAMAN      = { {name="Lightning Bolt", castTime=2.0}, {name="Chain Lightning", castTime=2.0}, {name="Lava Burst", castTime=2.0}, {name="Healing Wave", castTime=2.5} },
        MAGE        = { {name="Fireball", castTime=2.25}, {name="Frostbolt", castTime=2.0}, {name="Arcane Blast", castTime=2.25}, {name="Pyroblast", castTime=4.0} },
        WARLOCK     = { {name="Shadow Bolt", castTime=2.0}, {name="Chaos Bolt", castTime=3.0}, {name="Incinerate", castTime=2.0} },
        MONK        = { {name="Vivify", castTime=1.5}, {name="Spinning Crane Kick", castTime=1.5} },
        DRUID       = { {name="Wrath", castTime=1.5}, {name="Starfire", castTime=2.25}, {name="Regrowth", castTime=1.5}, {name="Healing Touch", castTime=2.5} },
        DEMONHUNTER = { {name="Eye Beam", castTime=2.0} },
        EVOKER      = { {name="Fire Breath", castTime=2.5}, {name="Disintegrate", castTime=3.0}, {name="Living Flame", castTime=1.5}, {name="Eternity Surge", castTime=2.5} },
    }
    -- Fallback spells if class pool yields nothing with a cast time
    local FALLBACK_CAST_SPELLS = {
        {name="Cosmic Hearthstone", spellID=1242509, castTime=5.0},
        {name="Teleport Home", spellID=1233637, castTime=10.0},
    }
    -- Universal hearthstone spells added to every class pool
    local UNIVERSAL_CAST_SPELLS = {
        {name="Cosmic Hearthstone", spellID=1242509, castTime=5.0},
        {name="Teleport Home", spellID=1233637, castTime=10.0},
    }
    -- Returns icon fileID + castTime (seconds) from the API, so instant-cast
    -- spells never reach the preview.
    local function ResolveSpellInfo(spellNameOrID)
        local info = C_Spell.GetSpellInfo(spellNameOrID)
        if info then
            local icon = info.iconID or 136197
            local ct = (info.castTime or 0) / 1000  -- API returns ms
            return icon, ct
        end
        return 136197, 0
    end
    optState._previewCastSpell = nil  -- {icon, name, castTime} -- randomized on tab switch
    optState._previewCastFill = nil   -- 0.4 0.9 fill for the cast bar

    -- Class-specific common proc/buff icons for player preview (icon IDs)
    local CLASS_BUFF_ICONS = {
        WARRIOR     = { 132404, 132352, 132333, 136012, 458972 },
        PALADIN     = { 135964, 236254, 135993, 135920, 461860 },
        HUNTER      = { 132242, 132176, 132312, 132329, 461846 },
        ROGUE       = { 132290, 132350, 136206, 132301, 236279 },
        PRIEST      = { 135936, 135987, 237548, 135940, 136207 },
        DEATHKNIGHT = { 237517, 135834, 135833, 237511, 135840 },
        SHAMAN      = { 136048, 136052, 136042, 136044, 136053 },
        MAGE        = { 135812, 135846, 135735, 135808, 236219 },
        WARLOCK     = { 136197, 136145, 136188, 136169, 136162 },
        MONK        = { 606551, 627606, 775461, 606543, 620827 },
        DRUID       = { 136096, 136048, 136041, 136085, 136060 },
        DEMONHUNTER = { 1344649, 1247262, 1344650, 1344652, 1344651 },
        EVOKER      = { 4622462, 4622460, 4622468, 4622464, 4622466 },
    }
    local FALLBACK_BUFF_ICONS = { 135932, 135981, 136075, 136205, 135987 }
    local _previewBuffIcons = {}  -- 2 randomized buff icons for player preview

    optState._previewHealthPct = 0.70  -- randomized health percentage for preview
    optState._previewPowerPct = 0.85  -- randomized power percentage for preview

    local function RandomizePreviewCreatures()
        _previewCreatureNames.target       = PREVIEW_ENEMY_NAMES[math.random(#PREVIEW_ENEMY_NAMES)]
        _previewCreatureNames.focus        = PREVIEW_ENEMY_NAMES[math.random(#PREVIEW_ENEMY_NAMES)]
        _previewCreatureNames.pet          = PREVIEW_ENEMY_NAMES[math.random(#PREVIEW_ENEMY_NAMES)]
        _previewCreatureNames.targettarget = PREVIEW_ENEMY_NAMES[math.random(#PREVIEW_ENEMY_NAMES)]
        _previewCreatureNames.focustarget  = PREVIEW_ENEMY_NAMES[math.random(#PREVIEW_ENEMY_NAMES)]
        _previewCreatureNames.boss         = PREVIEW_BOSS_NAMES[math.random(#PREVIEW_BOSS_NAMES)]
        -- Cast spell: class pool + universal hearthstones, cast time validated via API.
        local _, classToken = UnitClass("player")
        local classPool = CLASS_CAST_SPELLS[classToken] or {}
        local pool = {}
        for _, s in ipairs(classPool) do pool[#pool + 1] = s end
        for _, s in ipairs(UNIVERSAL_CAST_SPELLS) do pool[#pool + 1] = s end
        -- Shuffle pool (Fisher-Yates) then pick first spell with a real cast time
        for i = #pool, 2, -1 do
            local j = math.random(i)
            pool[i], pool[j] = pool[j], pool[i]
        end
        local chosen = nil
        for _, s in ipairs(pool) do
            local icon, ct = ResolveSpellInfo(s.spellID or s.name)
            if ct and ct > 0 then
                chosen = { icon = icon, name = s.name, castTime = ct }
                break
            end
        end
        -- No cast-time spell found: fall back to the first table entry.
        if not chosen then
            local fb = FALLBACK_CAST_SPELLS[1]
            chosen = { icon = 136197, name = fb.name, castTime = fb.castTime }
        end
        optState._previewCastSpell = chosen
        optState._previewCastFill = 0.40 + math.random() * 0.50
        optState._previewHealthPct = 0.60 + math.random() * 0.30
        optState._previewPowerPct = 0.50 + math.random() * 0.45
        -- Two distinct buff icons for the player preview.
        local buffPool = CLASS_BUFF_ICONS[classToken] or FALLBACK_BUFF_ICONS
        local i1 = math.random(#buffPool)
        local i2 = i1
        while i2 == i1 and #buffPool > 1 do i2 = math.random(#buffPool) end
        _previewBuffIcons[1] = buffPool[i1]
        _previewBuffIcons[2] = buffPool[i2]
    end


    -- Blizzard Style preview: the stock geometry the live layout pass uses
    -- (module table), resolved for this unit + Portrait Side exactly as
    -- ns.UF_BlizzResolve does it for the live frame. nil while the style is
    -- not active this session, and the preview then mocks the EUI look.
    local function ResolveBlizzPreview(unitKey, s)
        local BS = EllesmereUI.BlizzStyle
        if not (BS and BS.Get and BS.Get("unitframes")) then return nil end
        local UFB = ns.UF_BLIZZ
        if not (UFB and ns.UF_BlizzSide and ns.UF_PaintBlizzArt) then return nil end
        local kind
        if unitKey == "player" then kind = "player"
        elseif unitKey == "target" or unitKey == "focus" or unitKey == "boss" then kind = "target"
        elseif unitKey == "pet" and UFB.pet then kind = "pet"
        else kind = "mini" end
        local native = UFB[kind]
        local side = ns.UF_BlizzSide(s, native)
        local G, mirror = native, nil
        if native.small then
            if side ~= native.side then mirror = true end
        elseif side == "right" then
            G = UFB.target
        else
            G = UFB.player
        end
        return G, mirror, (G.rep and kind == "target") or nil
    end
    -- Frame Scale (the style's stand-in for Bar Width / Health Bar Height).
    local function BlizzPreviewScale(s)
        local sc = s and s.blizzScale or 1
        if sc < 0.5 then sc = 0.5 elseif sc > 2 then sc = 2 end
        return sc
    end

    ---------------------------------------------------------------------------
    --  Page Builders
    ---------------------------------------------------------------------------

    -- Per-unit settings live in DISPLAY sections; positioning in Unlock Mode.

    ---------------------------------------------------------------------------
    --  MULTI FRAME EDIT TAB  (checkbox selector + shared per-unit settings)
    ---------------------------------------------------------------------------
    local function RegisterWidgetRefresh(fn)
        if not EllesmereUI._widgetRefreshList then
            EllesmereUI._widgetRefreshList = {}
        end
        table.insert(EllesmereUI._widgetRefreshList, fn)
    end

    -- Dark Mode flattens the health bar to a fixed dark color, so fill/background
    -- color settings do nothing: grey out and block the whole DualRow region (every
    -- swatch/slider/cog/sync in it). A widget-refresh callback tracks the toggle live
    -- (RefreshPage's fast path re-runs these without a full rebuild).
    local function AddDarkModeBlock(rgn)
        if not rgn then return end
        local block = CreateFrame("Frame", nil, rgn)
        block:SetAllPoints()
        block:SetFrameLevel(rgn:GetFrameLevel() + 50)
        block:EnableMouse(true)
        block:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(block, "Not available in Dark Mode. Dark Mode colors can be adjusted in Global Settings -> Fonts & Colors.") end)
        block:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        local function Update()
            if db and db.profile and db.profile.darkTheme then
                rgn:SetAlpha(0.3); block:Show()
            else
                rgn:SetAlpha(1); block:Hide()
            end
        end
        Update()
        RegisterWidgetRefresh(Update)
    end

    ---------------------------------------------------------------------------
    --  Unified settings builder  (shared settings for the Main Frames page)
    ---------------------------------------------------------------------------
    local UNIT_SUPPORTS = {
        powerHeight          = { player=true, target=true, focus=true },
        showPlayerAbsorb     = { player=true, target=true, focus=true },
        absorbCleanAlpha     = { player=true, target=true, focus=true },
        absorbOpacity        = { player=true, target=true, focus=true },
        absorbColor          = { player=true, target=true, focus=true },
        absorbEdgeMode       = { player=true, target=true, focus=true },
        showOvershield       = { player=true, target=true, focus=true },
        overshieldMode       = { player=true, target=true, focus=true },
        absorbGlowLine       = { player=true, target=true, focus=true },
        absorbGlowLineTexture = { player=true, target=true, focus=true },
        healAbsorbStyle      = { player=true, target=true, focus=true },
        healAbsorbOpacity    = { player=true, target=true, focus=true },
        healAbsorbColor      = { player=true, target=true, focus=true },
        healAbsorbEdgeMode   = { player=true, target=true, focus=true },
        healAbsorbBgOpacity  = { player=true, target=true, focus=true },
        healPrediction       = { player=true, target=true, focus=true },
        healPredOpacity      = { player=true, target=true, focus=true },
        healPredOverheal     = { player=true, target=true, focus=true },
        healPredTexture      = { player=true, target=true, focus=true },
        absorbBarPosition     = { player=true, target=true, focus=true },
        absorbBarHeight       = { player=true, target=true, focus=true },
        absorbBarColor        = { player=true, target=true, focus=true },
        healAbsorbBarPosition = { player=true, target=true, focus=true },
        healAbsorbBarHeight   = { player=true, target=true, focus=true },
        healAbsorbBarColor    = { player=true, target=true, focus=true },
        showBuffs            = { player=true, target=true, focus=true },
        combatIndicatorStyle   = { player=true, target=true },
        combatIndicatorColor   = { player=true, target=true },
        combatIndicatorCustomColor = { player=true, target=true },
        combatIndicatorPosition = { player=true, target=true },
        combatIndicatorSize    = { player=true, target=true },
        combatIndicatorX       = { player=true, target=true },
        combatIndicatorY       = { player=true, target=true },
        leaderIndicatorEnabled = { player=true, target=true },
        leaderIndicatorSize    = { player=true, target=true },
        leaderIndicatorPosition= { player=true, target=true },
        leaderIndicatorX       = { player=true, target=true },
        leaderIndicatorY       = { player=true, target=true },
        leaderIndicatorStyle   = { player=true, target=true },
        eliteIndicatorEnabled  = { target=true },
        eliteIndicatorSize     = { target=true },
        eliteIndicatorPosition = { target=true },
        eliteIndicatorX        = { target=true },
        eliteIndicatorY        = { target=true },
        eliteIndicatorShowInInstances = { target=true },
        eliteIndicatorStyle    = { target=true },
        factionIndicatorMode        = { player=true, target=true },
        factionIndicatorStyle       = { player=true, target=true },
        factionIndicatorPlayersOnly = { target=true },
        factionIndicatorPvP         = { player=true, target=true },
        factionIndicatorSize        = { player=true, target=true },
        factionIndicatorPosition    = { player=true, target=true },
        factionIndicatorX           = { player=true, target=true },
        factionIndicatorY           = { player=true, target=true },
        buffAnchor           = { player=true, target=true, focus=true },
        buffGrowth           = { player=true, target=true, focus=true },
        maxBuffs             = { player=true, target=true, focus=true },
        showPlayerCastbar    = { player=true },
        showPlayerCastIcon   = { player=true },
        playerCastbarIconInWidth = { player=true },
        playerCastbarHeight  = { player=true },
        showCastbar          = { target=true, focus=true },
        showCastIcon         = { target=true, focus=true },
        castbarIconInWidth   = { target=true, focus=true },
        castbarHeight        = { target=true, focus=true },
        castbarHideWhenInactive = { player=true, target=true, focus=true },
        castSpellNameSize    = { player=true, target=true, focus=true },
        castSpellNameColor   = { player=true, target=true, focus=true },
        castDurationSize     = { player=true, target=true, focus=true },
        castDurationColor    = { player=true, target=true, focus=true },
        castSpellTargetSize  = { player=true, target=true, focus=true },
        castSpellTargetColor = { player=true, target=true, focus=true },
        showCastDuration     = { player=true, target=true, focus=true },
        showCastTarget       = { player=true, target=true, focus=true },
        castSpellNameSide    = { player=true, target=true, focus=true },
        castSpellTargetSide  = { player=true, target=true, focus=true },
        castDurationSide     = { player=true, target=true, focus=true },
        castbarFillColor     = { player=true, target=true, focus=true },
        castbarInterruptReadyColor = { target=true, focus=true },
        castbarKickTickEnabled     = { target=true, focus=true },
        castbarImportantGlow       = { target=true, focus=true },
        castCombineNameTarget      = { target=true, focus=true },
        showClassPowerBar    = { player=true },
        lockClassPowerToFrame= { player=true },
        classPowerStyle      = { player=true },
        classPowerPosition   = { player=true },
        classPowerBarX       = { player=true },
        classPowerBarY       = { player=true },
        classPowerSize       = { player=true },
        classPowerSpacing    = { player=true },
        classPowerClassColor = { player=true },
        classPowerCustomColor= { player=true },
        classPowerBgColor    = { player=true },
        classPowerEmptyColor = { player=true },
        showInRaid           = { player=true, target=true, focus=true },
        showInParty          = { player=true, target=true, focus=true },
        showSolo             = { player=true, target=true, focus=true },
    }
    local UNIT_LABELS_SUP = { player="Player", target="Target", focus="Focus" }

    -- Shown in place of a unit's settings when it isn't on the EllesmereUI frame
    -- (Blizzard default / hidden); the inapplicable controls are never built.
    -- Returns the new y.
    local function BuildInactiveNotice(parent, y, src)
        local CPAD = EllesmereUI.CONTENT_PAD or 10
        local note = EllesmereUI.MakeFont(parent, 13, nil, 1, 1, 1)
        note:SetTextColor(1, 1, 1, 0.55)
        note:SetPoint("TOPLEFT", parent, "TOPLEFT", CPAD + 4, y - 18)
        note:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(CPAD + 4), y - 18)
        note:SetJustifyH("LEFT")
        note:SetText(src == "blizzard"
            and EllesmereUI.L("This unit uses the Blizzard default frame -- there are no EllesmereUI settings to configure here.")
            or  EllesmereUI.L("This unit's frame is hidden -- there are no EllesmereUI settings to configure here."))
        return y - 54
    end

    -- A unit whose source was Blizzard/Hidden at login has no spawned EUI frame this
    -- session (and Blizzard's frame can't be torn down live), so a visibility/enable
    -- change can't apply live -- prompt for a /reload. unitKeys: "boss" checks boss1.
    local function PromptReloadIfUnspawned(unitKeys)
        local f = ns.frames
        if not f then return end
        local missing = false
        for _, u in ipairs(unitKeys) do
            local spawned = (u == "boss") and f.boss1 or f[u]
            if not spawned then missing = true; break end
        end
        if not missing then return end
        EllesmereUI:ShowConfirmPopup({
            title = "Reload Required",
            message = "This frame's source changes require a UI reload to take effect.",
            confirmText = "Reload Now",
            cancelText = "Later",
            reload    = true,
        })
    end

    -- Inline "Frame Source" cog next to a unit's Visibility dropdown / Enable
    -- toggle: one dropdown, EllesmereUI (our skinned frame) or Blizzard Default
    -- (leave Blizzard's frame alone). Hiding stays on the host widget ("Never
    -- Show" / Enable), so "Hidden" is not duplicated; the stored style survives
    -- hiding and resumes on re-enable. opts: tooltip, disabled/disabledTooltip
    -- (ToT/FoT parent gating), onBeforeSet(v) (boss stops its live preview).
    local function AttachFrameSourceCog(rgn, unitKey, opts)
        opts = opts or {}
        local function StoredStyle()
            local fs = db.profile.frameSource and db.profile.frameSource[unitKey]
            return fs == "blizzard" and "blizzard" or "eui"
        end
        local fsShow  -- forward decl: set() below closes the popup through it
        local _
        local rows = {
            { type = "dropdown", label = "Frame Source",
              values = { eui = "EllesmereUI", blizzard = "Blizzard Default" },
              order = { "eui", "blizzard" },
              tooltip = opts.tooltip,
              disabled = opts.disabled,
              disabledTooltip = opts.disabledTooltip,
              get = StoredStyle,
              set = function(v)
                  if v == StoredStyle() then return end
                  if opts.onBeforeSet then opts.onBeforeSet(v) end
                  -- Also re-enables a hidden frame (see ns.SetUnitFrameSource).
                  ns.SetUnitFrameSource(unitKey, v)
                  if ns.UpdateFrameVisibility then ns.UpdateFrameVisibility() end
                  ReloadAndUpdate()
                  EllesmereUI:RefreshPage(true)
                  -- Close the cog popup before the reload prompt: the page under
                  -- it was just rebuilt, so it would float stale rows behind the dialog.
                  if fsShow and fsShow._popupFrame and fsShow._popupFrame:IsShown() then
                      fsShow._popupFrame:Hide()
                  end
                  EllesmereUI:ShowConfirmPopup({
                      title = "Reload Required",
                      message = "Changing the frame source requires a UI reload to take effect.",
                      confirmText = "Reload Now",
                      cancelText = "Later",
                      reload    = true,
                  })
              end },
        }
        -- Callers can fold extra rows into the same popup (the Visibility row hosts
        -- the Out of Combat fade, so it carries ONE cog instead of two).
        if opts.extraRows then
            for _, r in ipairs(opts.extraRows) do rows[#rows + 1] = r end
        end
        _, fsShow = EllesmereUI.BuildInlineCog(rgn, {
            title = opts.title or "Frame Source", bgAlpha = 1,
            frameStrata = "FULLSCREEN_DIALOG", frameLevel = 500,
            rows = rows,
            tip = EllesmereUI.L(opts.cogTooltip or "Frame Source"),
        })
    end

    ---------------------------------------------------------------------------
    --  "Apply All Settings From" -- bulk copy between frames of the same group
    ---------------------------------------------------------------------------
    -- Copies every group-shared setting (UNION of source+dest keys, so dest-only
    -- overrides get cleared) from the CHOSEN unit onto the frame whose page the
    -- row sits on. A key is shared unless
    -- UNIT_SUPPORTS restricts it or it's absent from some group units' defaults.
    -- Positions/enable state (db.profile.positions/enabledFrames) are never touched.
    -- Exception: target<->focus copies check sharedness against just that pair, so
    -- their shared cast bar section (which player lacks) transfers; player copies use
    -- the full-group rule, so cast bar settings never cross to/from player.
    local MINI_GROUP_ORDER = { "targettarget", "focustarget", "pet" }
    local TARGET_FOCUS_PAIR = { "target", "focus" }
    local function IsGroupSharedKey(key, groupUnits)
        -- Visibility mode stays with the frame: it pairs with enabledFrames (never
        -- copied) and copying one alone desyncs them. Underscore keys are runtime
        -- memos (e.g. _preHiddenBarVisibility), not settings.
        if type(key) ~= "string" then return false end
        -- visibilityMatch only modifies barVisibility's selection, so it has to stay
        -- with the frame for the same reason: copying the modifier to a frame that kept
        -- its own mode changes how that mode reads.
        if key == "barVisibility" or key == "visibilityMatch" or key:sub(1, 1) == "_" then return false end
        -- WoW Forever: the pet's power bar position has no counterpart on the
        -- other small frames (theirs never shows), so it stays with the pet.
        if key == "powerPosition" and ns.UF_PetHasPower and groupUnits == MINI_GROUP_ORDER then return false end
        local sup = UNIT_SUPPORTS[key]
        if sup then
            for _, u in ipairs(groupUnits) do
                if not sup[u] then return false end
            end
        end
        local defs = db._profileDefaults or {}
        local inAny, inAll = false, true
        for _, u in ipairs(groupUnits) do
            local d = defs[u]
            if d and d[key] ~= nil then inAny = true else inAll = false end
        end
        if inAny and not inAll then return false end
        return true
    end
    local function CopyAllGroupSettings(srcUnit, dstUnit, groupUnits)
        if (srcUnit == "target" or srcUnit == "focus")
            and (dstUnit == "target" or dstUnit == "focus") then
            groupUnits = TARGET_FOCUS_PAIR
        end
        local src = UNIT_DB_MAP[srcUnit]()
        local dst = UNIT_DB_MAP[dstUnit]()
        -- A target on the old "wingless" Elite/Rare style shows its dragon
        -- through a view (ns.UF_DragonLegacy) over target-only keys this copy
        -- never moves: pin both tables onto the dragon's own keys first.
        ns.UF_PinLegacyDragon(src)
        ns.UF_PinLegacyDragon(dst)
        local keys = {}
        for k in pairs(src) do keys[k] = true end
        for k in pairs(dst) do keys[k] = true end
        for k in pairs(keys) do
            if IsGroupSharedKey(k, groupUnits) then
                local v = src[k]
                if type(v) == "table" then
                    dst[k] = EllesmereUI.Lite.DeepCopy(v)
                else
                    dst[k] = v
                end
            end
        end
        ReloadAndUpdate()
        EllesmereUI:RefreshPage(true)
    end
    -- Centered label + action dropdown atop a unit's settings: lists the group's
    -- other frames and copies FROM the chosen one onto this frame after a
    -- confirm popup. getValue always returns the placeholder so the dropdown
    -- stores nothing; the registered widget refresh snaps the label back after
    -- each pick.
    --
    -- The FIRST use asks the user to type Confirm: this control used to copy
    -- the OTHER way (onto the chosen frame), and the flipped direction has to
    -- be acknowledged once before it overwrites anything. The acknowledgment
    -- is account-wide (EllesmereUIDB root, not per-profile) and covers every
    -- frame's row -- it educates the user, not a profile.
    local function BuildApplyAllRow(parent, y, groupUnits, curUnit)
        local ddValues = { [""] = "Choose Frame..." }
        local ddOrder = {}
        for _, key in ipairs(groupUnits) do
            if key ~= curUnit then
                ddValues[key] = SHORT_LABELS[key] or key
                ddOrder[#ddOrder + 1] = key
            end
        end

        local ROW_H = 50
        local contentPad = EllesmereUI.CONTENT_PAD or 45
        local row = CreateFrame("Frame", nil, parent)
        PP.Size(row, parent:GetWidth() - contentPad * 2, ROW_H)
        PP.Point(row, "TOPLEFT", parent, "TOPLEFT", contentPad, y)

        local label = EllesmereUI.MakeFont(row, 14, nil, 1, 1, 1)
        label:SetText(EllesmereUI.L("Apply All Settings From"))
        label:SetTextColor(1, 1, 1, 0.6)

        local DD_W, GAP = 180, 12
        local ddBtn = EllesmereUI.BuildDropdownControl(
            row, DD_W, row:GetFrameLevel() + 2,
            ddValues, ddOrder,
            function() return "" end,
            function(srcUnit)
                if srcUnit == "" then return end
                local srcLabel = SHORT_LABELS[srcUnit] or srcUnit
                local curLabel = SHORT_LABELS[curUnit] or curUnit
                local acked = EllesmereUIDB and EllesmereUIDB.ufApplyFromAck
                EllesmereUI:ShowConfirmPopup({
                    title   = "Apply All Settings",
                    message = acked
                        and EllesmereUI.Lf("Copy all shared settings from %1$s to %2$s?",
                            srcLabel, curLabel)
                        or EllesmereUI.Lf("This control recently changed direction: it now copies FROM the frame you choose. Confirming will copy all shared settings FROM %1$s TO %2$s.",
                            srcLabel, curLabel),
                    disclaimer = "This overwrites this frame's current settings. Frame position, visibility, and enable state are not changed.",
                    confirmText = "Apply",
                    cancelText  = "Cancel",
                    typeToConfirm = (not acked) and "Confirm" or nil,
                    onConfirm = function()
                        if EllesmereUIDB then EllesmereUIDB.ufApplyFromAck = true end
                        CopyAllGroupSettings(srcUnit, curUnit, groupUnits)
                    end,
                })
            end)
        ddBtn._ttText = "Copy every shared setting from another frame in this group to this frame."
        EllesmereUI.RegisterWidgetRefresh(function() ddBtn._refreshLabel() end)

        -- Center the label + dropdown pair as one line
        local totalW = label:GetStringWidth() + GAP + DD_W
        label:SetPoint("LEFT", row, "CENTER", -totalW / 2, 0)
        ddBtn:SetPoint("LEFT", label, "RIGHT", GAP, 0)

        return row, ROW_H, ddBtn
    end

    -- "Copy Look From" under a mini frame's Apply All Settings From row: the
    -- main frame it copies its border, bar texture and hover highlight from
    -- (lookSource; nil = Automatic). Its dropdown sits under that row's, the
    -- label right-aligned beside it.
    local function BuildLookSourceRow(parent, y, settingsTable, alignDD)
        local ROW_H = 40
        local contentPad = EllesmereUI.CONTENT_PAD or 45
        local row = CreateFrame("Frame", nil, parent)
        PP.Size(row, parent:GetWidth() - contentPad * 2, ROW_H)
        PP.Point(row, "TOPLEFT", parent, "TOPLEFT", contentPad, y)

        local ddBtn = EllesmereUI.BuildDropdownControl(
            row, 180, row:GetFrameLevel() + 2,
            { auto = "Automatic", target = "Target", focus = "Focus", player = "Player" },
            { "auto", "target", "focus", "player" },
            function() return settingsTable.lookSource or "auto" end,
            function(v)
                settingsTable.lookSource = (v ~= "auto") and v or nil
                ReloadAndUpdate()
                EllesmereUI:RefreshPage(true)
            end)
        ddBtn._ttText = "The main frame this frame copies its border, bar texture and hover highlight from. Automatic uses Focus, then Target, then Player."
        EllesmereUI.RegisterWidgetRefresh(function() ddBtn._refreshLabel() end)
        ddBtn:SetPoint("TOPLEFT", alignDD, "BOTTOMLEFT", 0, -10)

        local label = EllesmereUI.MakeFont(row, 14, nil, 1, 1, 1)
        label:SetText(EllesmereUI.L("Copy Look From"))
        label:SetTextColor(1, 1, 1, 0.6)
        label:SetPoint("RIGHT", ddBtn, "LEFT", -12, 0)

        return row, ROW_H
    end

    local function BuildSharedSettings(parent, y)
        local W = EllesmereUI.Widgets
        local _, h
        local row

        ---------------------------------------------------------------
        --  Unified Get / Set / DB abstraction
        ---------------------------------------------------------------
        local function SGet(key)
            return UNIT_DB_MAP[optState.selectedUnit]()[key]
        end
        local function SSet(key, val)
            UNIT_DB_MAP[optState.selectedUnit]()[key] = val
            ReloadAndUpdate()
        end
        local function SDB()
            return UNIT_DB_MAP[optState.selectedUnit]()
        end
        local function SVal(key, default)
            local v = UNIT_DB_MAP[optState.selectedUnit]()[key]
            if v ~= nil then return v end
            return default
        end
        -- True while one of the unit's text slots shows its level (Level,
        -- Level | Name, Name | Level). The Level Text: Difficulty Color row is
        -- built only then, so the text setters rebuild the page when it flips.
        local SShowsLevel
        do
            local slots = { "leftTextContent", "rightTextContent", "centerTextContent", "extraTextContent" }
            local levelText = { level = true, levelname = true, namelevel = true }
            SShowsLevel = function()
                local d = UNIT_DB_MAP[optState.selectedUnit]()
                for i = 1, #slots do
                    if levelText[d[slots[i]]] then return true end
                end
                return false
            end
        end
        -- Set that also writes to the current unit (for UNIT_SUPPORTS keys)
        local function SSetSupported(key, val)
            UNIT_DB_MAP[optState.selectedUnit]()[key] = val
            ReloadAndUpdate(); UpdatePreview()
        end
        local function SGetSupported(key)
            return UNIT_DB_MAP[optState.selectedUnit]()[key]
        end
        local function SValSupported(key, default)
            local v = UNIT_DB_MAP[optState.selectedUnit]()[key]
            if v == nil then return default end
            return v
        end
        -- Check if current unit supports a setting
        local function SVisible(key)
            local sup = UNIT_SUPPORTS[key]
            if not sup then return true end
            return sup[optState.selectedUnit] == true
        end
        -- Dim a row region and add a tooltip when the current unit doesn't support
        -- the key; unsupportedTip (optional) shows over the dimmed row.
        local function SApplySupport(region, key, unsupportedTip)
            local visible = SVisible(key)
            if not visible then
                region:SetAlpha(0.35)
                if region._control and region._control.Disable then region._control:Disable() end
            end
            local tip = not visible and unsupportedTip or nil
            if tip then
                local function MakeSupportHit(anchor)
                    if not anchor then return end
                    local hitFrame = CreateFrame("Frame", nil, region)
                    hitFrame:SetPoint("TOPLEFT", anchor, "TOPLEFT", -5, 5)
                    hitFrame:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 5, -5)
                    hitFrame:SetFrameLevel(region:GetFrameLevel() + 10)
                    hitFrame:EnableMouse(true)
                    hitFrame:SetScript("OnEnter", function()
                        EllesmereUI.ShowWidgetTooltip(anchor, tip)
                    end)
                    hitFrame:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                    securecallfunction(hitFrame.SetPassThroughButtons, hitFrame, "LeftButton", "RightButton")
                end
                MakeSupportHit(region._label)
                MakeSupportHit(region._control)
            end
        end

        parent._showRowDivider = true

        row, h = BuildApplyAllRow(parent, y, GROUP_UNIT_ORDER, optState.selectedUnit); y = y - h

        -- The sections live in UnitFrames_Options\Shared*_Options.lua and read
        -- this page's accessors through ctx. Each returns the new y plus the rows
        -- the click mapping below points at; Display returns true second when
        -- the unit has no EUI frame (only the inactive notice is built).
        local ctx = {
            W = W, SGet = SGet, SSet = SSet, SDB = SDB, SVal = SVal, SShowsLevel = SShowsLevel,
            SSetSupported = SSetSupported, SGetSupported = SGetSupported, SValSupported = SValSupported,
            SVisible = SVisible, SApplySupport = SApplySupport,
        }
        local inactive
        y, inactive = ns.UFO_BuildDisplaySection(parent, y, ctx)
        if inactive then return y end
        local sharedPortraitHeader, sharedPortraitModeRow
        y, sharedPortraitHeader, sharedPortraitModeRow = ns.UFO_BuildPortraitSection(parent, y, ctx)
        local sharedBarsHeader, sharedScaleRow, sharedSizeRow, sharedTextRow, sharedCenterTextRow
        y, sharedBarsHeader, sharedScaleRow, sharedSizeRow, sharedTextRow, sharedCenterTextRow = ns.UFO_BuildHealthBarSection(parent, y, ctx)
        local sharedPowerHeader, sharedPowerRow1, sharedPowerRow2
        y, sharedPowerHeader, sharedPowerRow1, sharedPowerRow2 = ns.UFO_BuildPowerBarSection(parent, y, ctx)
        local sharedCastHeader, sharedCastRow1, castRow2, castTextRow, castTargetRow
        y, sharedCastHeader, sharedCastRow1, castRow2, castTextRow, castTargetRow = ns.UFO_BuildCastBarSection(parent, y, ctx)
        local sharedBtbHeader, sharedBtbToggleRow, sharedBtbTextRow, sharedBtbCenterRow
        y, sharedBtbHeader, sharedBtbToggleRow, sharedBtbTextRow, sharedBtbCenterRow = ns.UFO_BuildTextBarSection(parent, y, ctx)
        local sharedClassResHeader, sharedClassResRow
        y, sharedClassResHeader, sharedClassResRow = ns.UFO_BuildClassResourceSection(parent, y, ctx)
        local sharedBuffDebuffHeader, sharedAddRow2, sharedAddRow3
        y, sharedBuffDebuffHeader, sharedAddRow2, sharedAddRow3 = ns.UFO_BuildBuffsDebuffsSection(parent, y, ctx)
        local sharedAbsorbsHeader, absorbRow, healAbsorbRow
        y, sharedAbsorbsHeader, absorbRow, healAbsorbRow = ns.UFO_BuildAbsorbsHealsSection(parent, y, ctx)
        local sharedAddHeader, sharedAddRow1, sharedAddRow4, sharedAddRow5
        y, sharedAddHeader, sharedAddRow1, sharedAddRow4, sharedAddRow5 = ns.UFO_BuildExtrasSection(parent, y, ctx)

        -------------------------------------------------------------------
        --  Return click mapping targets + total height
        -------------------------------------------------------------------
        parent._sharedClickTargets = {
            healthBar    = { section = sharedBarsHeader,     target = sharedScaleRow or sharedSizeRow },
            absorbs      = { section = sharedAbsorbsHeader,  target = absorbRow, slotSide = "left" },
            healAbsorb   = { section = sharedAbsorbsHeader,  target = healAbsorbRow, slotSide = "left" },
            powerBar     = { section = sharedPowerHeader,    target = sharedPowerRow1, slotSide = "left" },
            powerBarText = { section = sharedPowerHeader,    target = sharedPowerRow2, slotSide = "left" },
            portrait     = { section = sharedPortraitHeader, target = sharedPortraitModeRow, slotSide = "left" },
            nameText     = { section = sharedBarsHeader,     target = sharedTextRow, slotSide = "left" },
            healthText   = { section = sharedBarsHeader,     target = sharedTextRow, slotSide = "right" },
            centerText   = { section = sharedBarsHeader,     target = sharedCenterTextRow, slotSide = "left" },
            classResource= { section = sharedClassResHeader, target = sharedClassResRow, slotSide = "left" },
            btbBar       = { section = sharedBtbHeader,      target = sharedBtbToggleRow, slotSide = "left" },
            btbLeftText  = { section = sharedBtbHeader,      target = sharedBtbTextRow, slotSide = "left" },
            btbRightText = { section = sharedBtbHeader,      target = sharedBtbTextRow, slotSide = "right" },
            btbCenterText= { section = sharedBtbHeader,      target = sharedBtbCenterRow, slotSide = "left" },
            btbClassIcon = { section = sharedBtbHeader,      target = sharedBtbCenterRow, slotSide = "right" },
            combatIndicator = { section = sharedAddHeader, target = sharedAddRow1, slotSide = "left" },
            buffIcon     = { section = sharedBuffDebuffHeader, target = sharedAddRow2, slotSide = "left" },
            debuffIcon   = { section = sharedBuffDebuffHeader, target = sharedAddRow3, slotSide = "left" },
            raidMarker   = { section = sharedAddHeader,      target = sharedAddRow4, slotSide = "left" },
            leaderIndicator = { section = sharedAddHeader,   target = sharedAddRow5, slotSide = "left" },
            castBar      = { section = sharedCastHeader,     target = sharedCastRow1 },
            castIcon     = { section = sharedCastHeader,     target = castRow2,      slotSide = "left" },
            castName     = { section = sharedCastHeader,     target = castTextRow,   slotSide = "left" },
            castTime     = { section = sharedCastHeader,     target = castTextRow,   slotSide = "right" },
            castTarget   = { section = sharedCastHeader,     target = castTargetRow, slotSide = "left" },
            -- Blizzard Style level number -> Show Level (+ its cog).
            levelText    = { section = sharedBarsHeader,     target = parent._ufLevelRow, slotSide = "left" },
        }
        -- Rows that exist only for some frames (Elite/Rare: target; Faction: player + target).
        if optState.selectedUnit == "target" and parent._ufEliteRow then
            parent._sharedClickTargets.eliteIndicator = { section = sharedAddHeader, target = parent._ufEliteRow, slotSide = "left" }
        end
        if (optState.selectedUnit == "player" or optState.selectedUnit == "target") and parent._ufFactionRow then
            parent._sharedClickTargets.factionIndicator = { section = sharedAddHeader, target = parent._ufFactionRow, slotSide = "left" }
        end

        return y
    end  -- BuildSharedSettings

    ---------------------------------------------------------------------------
    --  Main Frames page  (dropdown selector + shared/mini settings)
    ---------------------------------------------------------------------------
    local _displayHeaderBuilder
    local displayHeaderFixedH = 0

    local function BuildFrameDisplayPage(pageName, parent, yOffset)
        -- Consume any pending unit selection from Element Options navigation
        if EllesmereUI._consumePendingUnitSelect then EllesmereUI._consumePendingUnitSelect() end

        -- Tag every option built on this page with the selected unit, so a global-
        -- search jump to a unit-specific setting can restore this unit first via
        -- EllesmereUI._setUnitFrameUnit (see the matching EllesmereUI._buildingSelector
        -- comment in EUI_CooldownManager_Options.lua for the full reasoning).
        EllesmereUI._buildingSelector = { setter = EllesmereUI._setUnitFrameUnit, key = optState.selectedUnit }

        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        activePreview = nil

        -------------------------------------------------------------------
        --  CONTENT HEADER  (dropdown + preview)
        -------------------------------------------------------------------
        _displayHeaderBuilder = function(hdr, hdrW)
            local DD_H = 34
            local fy = -20

            -- Centered dropdown (matches Action Bars Single Bar Edit)
            local ddW = 350
            local ddBtn, ddLbl = EllesmereUI.BuildDropdownControl(
                hdr, ddW, hdr:GetFrameLevel() + 5,
                unitLabels, unitOrder,
                function() return optState.selectedUnit end,
                function(v)
                    -- Preserve scroll position across the unit swap; capture BEFORE the
                    -- rebuild since SetContentHeader's relayout can clobber the live value.
                    -- Settings sit below the fixed header, so the same offset lands on the same section for any unit.
                    local savedScroll = EllesmereUI.GetContentScroll and EllesmereUI.GetContentScroll() or 0
                    optState.selectedUnit = v
                    EllesmereUI:InvalidateContentHeaderCache()
                    EllesmereUI:SetContentHeader(_displayHeaderBuilder)
                    EllesmereUI:RefreshPage(true)
                    EllesmereUI.SmoothScrollTo(savedScroll)
                    -- Preview:Update() runs DURING the rebuild above, before the header
                    -- layout settles, so its sizing pass lands on stale geometry (spacing
                    -- wrong, debuff row missing until a slider nudge). Initial page load
                    -- gets a settled pass via RegisterOnShow; a unit switch does not, so re-run the preview next frame once layout has settled.
                    C_Timer.After(0, UpdatePreview)
                end
            )
            PP.Point(ddBtn, "TOP", hdr, "TOP", 0, fy)
            ddBtn:SetHeight(DD_H)
            fy = fy - DD_H - 20

            local side = unitSide[optState.selectedUnit] or "left"
            local preview = ns.UFO_BuildUnitPreview(hdr, optState.selectedUnit, side)
            activePreview = preview
            local previewScale = preview._previewScale or 1
            local initBuffTopPad = preview._buffTopPad or 0
            preview._headerDropdownOY = math.abs(fy)
            preview:ClearAllPoints()
            PP.Point(preview, "TOP", hdr, "TOP", 0, (fy - initBuffTopPad) / previewScale)
            preview._lastOY = (fy - initBuffTopPad) / previewScale
            preview:Update()
            local previewH = preview:GetHeight() * preview:GetScale()
            local buffExtra = preview._buffExtra or 0
            local detTopExtra = preview._detTopExtra or 0
            fy = fy - previewH - buffExtra - detTopExtra - 20

            displayHeaderFixedH = 20 + DD_H + 20 + 20
            if preview then preview._headerFixedH = displayHeaderFixedH end

            -- Hint text
            if optState._ufPreviewHintFS_display and not optState._ufPreviewHintFS_display:GetParent() then
                optState._ufPreviewHintFS_display = nil
            end
            local hintH = 0
            if not IsPreviewHintDismissed() then
                if not optState._ufPreviewHintFS_display then
                    optState._ufPreviewHintFS_display = EllesmereUI.MakeFont(preview or hdr, 11, nil, 1, 1, 1)
                    optState._ufPreviewHintFS_display:SetAlpha(0.45)
                    optState._ufPreviewHintFS_display:SetText(EllesmereUI.L("Click elements to scroll to and highlight their options"))
                end
                optState._ufPreviewHintFS_display:SetParent(preview or hdr)
                optState._ufPreviewHintFS_display:ClearAllPoints()
                optState._ufPreviewHintFS_display:SetPoint("BOTTOM", hdr, "BOTTOM", 0, 17)
                optState._ufPreviewHintFS_display:SetAlpha(0.45)
                optState._ufPreviewHintFS_display:Show()
                hintH = 29
            elseif optState._ufPreviewHintFS_display then
                optState._ufPreviewHintFS_display:Hide()
            end

            _displayHeaderBaseH = math.abs(fy)
            return _displayHeaderBaseH + hintH
        end
        EllesmereUI:SetContentHeader(_displayHeaderBuilder)

        parent._showRowDivider = true

        -------------------------------------------------------------------
        --  Route to shared settings or mini builders
        -------------------------------------------------------------------
        if optState.selectedUnit == "player" or optState.selectedUnit == "target" or optState.selectedUnit == "focus" then
            y = BuildSharedSettings(parent, y)
        elseif optState.selectedUnit == "targettarget" then
            y = -ns.UFO_BuildFoTToTOptions(W, parent, y, db.profile.targettarget, "targettarget")
        elseif optState.selectedUnit == "focustarget" then
            y = -ns.UFO_BuildFoTToTOptions(W, parent, y, db.profile.focustarget, "focustarget")
        elseif optState.selectedUnit == "pet" then
            y = -ns.UFO_BuildPetOptions(W, parent, y)
        elseif optState.selectedUnit == "boss" then
            y = -ns.UFO_BuildBossOptions(W, parent, y)
        end

        -------------------------------------------------------------------
        --  CLICK NAVIGATION
        -------------------------------------------------------------------
        local PlaySettingGlow = EllesmereUI.MakeSettingGlow({ color = EllesmereUI.ELLESMERE_GREEN })
        local function NavigateToSetting(key)
            ns._UFNavigateToSetting(parent._sharedClickTargets or parent._ufClickTargets, key, PlaySettingGlow, true)
        end
        local function CreateHitOverlay(element, mappingKey, isText, frameLevelOverride, opts)
            return (EllesmereUI.CreatePreviewHitOverlay(element, NavigateToSetting, mappingKey, isText, frameLevelOverride, opts))
        end

        -- Create hit overlays on preview elements
        local textOverlays = {}
        if activePreview then
            local pv = activePreview
            local baseLevel = (pv._health and pv._health:GetFrameLevel() or 20) + 15
            local textLevel = baseLevel + 10
            if pv._health then CreateHitOverlay(pv._health, "healthBar", false, baseLevel) end
            -- Absorb segments: hit area follows each absorb bar's FILL texture (the
            -- bar frame spans the whole health width), above the health overlay so it
            -- routes to Absorbs. No :IsShown() guard needed: as a fill-anchored child it
            -- auto-hides/shows with the bar; both bars get an overlay so whichever the heal-absorb eyeball shows stays click-navigable.
            if pv._absorbBar then
                local absFill = pv._absorbBar:GetStatusBarTexture()
                if absFill then
                    CreateHitOverlay(absFill, "absorbs", false, baseLevel + 5,
                        { parent = pv._health, showWith = pv._absorbBar })
                end
            end
            if pv._healAbsorbBar then
                local haFill = pv._healAbsorbBar:GetStatusBarTexture()
                if haFill then
                    CreateHitOverlay(haFill, "healAbsorb", false, baseLevel + 5,
                        { parent = pv._health, showWith = pv._healAbsorbBar })
                end
            end
            if pv._power then CreateHitOverlay(pv._power, "powerBar", false, baseLevel) end
            if pv._portraitFrame and pv._portraitFrame:IsShown() then CreateHitOverlay(pv._portraitFrame, "portrait", false, baseLevel) end
            if pv._castbar then
                local castLevel = pv._castbar:GetFrameLevel() + 20
                CreateHitOverlay(pv._castbar, "castBar", false, castLevel)
                if pv._castIconFrame then CreateHitOverlay(pv._castIconFrame, "castIcon", false, castLevel) end
                if pv._castNameFS then textOverlays[#textOverlays+1] = CreateHitOverlay(pv._castNameFS, "castName", true, castLevel + 5) end
                if pv._castTimeFS and pv._castTimeFS:IsShown() then textOverlays[#textOverlays+1] = CreateHitOverlay(pv._castTimeFS, "castTime", true, castLevel + 5) end
                if pv._castTargetFS and pv._castTargetFS:IsShown() then textOverlays[#textOverlays+1] = CreateHitOverlay(pv._castTargetFS, "castTarget", true, castLevel + 5) end
            end
            if pv._nameFS and pv._nameFS:IsShown() then textOverlays[#textOverlays+1] = CreateHitOverlay(pv._nameFS, "nameText", true, textLevel) end
            if pv._hpFS and pv._hpFS:IsShown() then textOverlays[#textOverlays+1] = CreateHitOverlay(pv._hpFS, "healthText", true, textLevel) end
            if pv._centerFS and pv._centerFS:IsShown() then textOverlays[#textOverlays+1] = CreateHitOverlay(pv._centerFS, "centerText", true, textLevel) end
            -- Blizzard Style level number: built whenever the art has a level
            -- circle and shown with the text (the preview toggles it).
            if pv._levelFS then
                local lvOv = CreateHitOverlay(pv._levelFS, "levelText", true, textLevel)
                pv._levelOv = lvOv
                if not pv._levelFS:IsShown() then lvOv:Hide() end
                textOverlays[#textOverlays+1] = lvOv
            end
            if pv._ppFS and pv._ppFS:IsShown() then textOverlays[#textOverlays+1] = CreateHitOverlay(pv._ppFS, "powerBarText", true, textLevel) end
            -- Overlay EVERY buff/debuff frame, not just currently-shown ones: each
            -- overlay is a SetAllPoints child of its icon, so it hides/shows and
            -- re-anchors with it. A prior ":IsShown()" guard tied clickability to
            -- build-time visibility, so icons shown later (header is cached, not rebuilt) had no overlay.
            if pv._buffIcons then
                for i = 1, #pv._buffIcons do
                    if pv._buffIcons[i] then CreateHitOverlay(pv._buffIcons[i], "buffIcon", false, baseLevel) end
                end
            end
            if pv._debuffIcons then
                for i = 1, #pv._debuffIcons do
                    if pv._debuffIcons[i] then CreateHitOverlay(pv._debuffIcons[i], "debuffIcon", false, baseLevel) end
                end
            end
            if pv._btbFrame then
                local btbLevel = pv._btbFrame:GetFrameLevel() + 20
                CreateHitOverlay(pv._btbFrame, "btbBar", false, btbLevel)
                local btbTextLevel = btbLevel + 5
                if pv._btbLeftFS then textOverlays[#textOverlays+1] = CreateHitOverlay(pv._btbLeftFS, "btbLeftText", true, btbTextLevel) end
                if pv._btbRightFS then textOverlays[#textOverlays+1] = CreateHitOverlay(pv._btbRightFS, "btbRightText", true, btbTextLevel) end
                if pv._btbCenterFS then textOverlays[#textOverlays+1] = CreateHitOverlay(pv._btbCenterFS, "btbCenterText", true, btbTextLevel) end
                if pv._btbClassIcon then
                    local ciOv = CreateHitOverlay(pv._btbClassIcon, "btbClassIcon", false, btbTextLevel + 2)
                    pv._btbClassIconOv = ciOv
                    if not pv._btbClassIcon:IsShown() then ciOv:Hide() end
                end
            end
            if pv._cpPipContainer and pv._cpPipContainer:IsShown() then
                pv._cpPipOv = CreateHitOverlay(pv._cpPipContainer, "classResource", false, baseLevel + 10)
            end
            if pv._combatIndicator and pv._combatIndicator:IsShown() then CreateHitOverlay(pv._combatIndicator, "combatIndicator", false, baseLevel + 20) end
            -- Indicator badges (eye toggles): overlays made up front, shown and hidden
            -- with their badge by the preview update, so a badge switched on later is
            -- clickable straight away.
            local targets = parent._sharedClickTargets or {}
            pv._badgeOv = {}
            for _, b in ipairs({
                { pv._pvRaid, "raidMarker" }, { pv._pvLeader, "leaderIndicator" },
                { pv._pvElite, "eliteIndicator" }, { pv._factionIndicator, "factionIndicator" },
            }) do
                if b[1] and targets[b[2]] then
                    local ov = CreateHitOverlay(b[1], b[2], false, baseLevel + 20)
                    ov:SetShown(b[1]:IsShown())
                    pv._badgeOv[b[1]] = ov
                end
            end
            pv._textOverlays = textOverlays
        end

        return abs(y)
    end

    ---------------------------------------------------------------------------
    --  Mini Frames page  (dropdown selector + mini builders)
    ---------------------------------------------------------------------------
    local selectedMiniUnit = "targettarget"
    local miniUnitLabels = {
        ["targettarget"] = "Target of Target",
        ["focustarget"]  = "Focus Target",
        ["pet"]          = "Pet",
    }
    local miniUnitOrder = { "targettarget", "focustarget", "pet" }

    -- Allow Unlock Mode's "Element Options" to pre-select a mini unit before the
    -- Mini Frames page builds (mirrors the Main Frames _setUnitFrameUnit /
    -- _pendingUnitSelect mechanism). Field assignments -- no new locals.
    EllesmereUI._setMiniUnit = function(unit) selectedMiniUnit = unit end
    EllesmereUI._consumePendingMiniSelect = function()
        local pending = EllesmereUI._pendingMiniSelect
        if pending then
            selectedMiniUnit = pending
            EllesmereUI._pendingMiniSelect = nil
        end
    end

    local _miniHeaderBuilder
    local miniHeaderFixedH = 0

    local function BuildMiniPage(pageName, parent, yOffset)
        -- Consume any pending mini selection from Element Options navigation
        if EllesmereUI._consumePendingMiniSelect then EllesmereUI._consumePendingMiniSelect() end

        -- Tag every option built on this page with the selected mini unit, so a
        -- global-search jump to a unit-specific setting can restore this selection
        -- first via EllesmereUI._setMiniUnit (see the matching EllesmereUI._buildingSelector
        -- comment in EUI_CooldownManager_Options.lua for the full reasoning).
        EllesmereUI._buildingSelector = { setter = EllesmereUI._setMiniUnit, key = selectedMiniUnit }

        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        activePreview = nil

        -------------------------------------------------------------------
        --  CONTENT HEADER  (dropdown + preview)
        -------------------------------------------------------------------
        _miniHeaderBuilder = function(hdr, hdrW)
            local DD_H = 34
            local fy = -20

            -- Centered dropdown (matches Action Bars Single Bar Edit)
            local ddW = 350
            local ddBtn, ddLbl = EllesmereUI.BuildDropdownControl(
                hdr, ddW, hdr:GetFrameLevel() + 5,
                miniUnitLabels, miniUnitOrder,
                function() return selectedMiniUnit end,
                function(v)
                    selectedMiniUnit = v
                    EllesmereUI:InvalidateContentHeaderCache()
                    EllesmereUI:SetContentHeader(_miniHeaderBuilder)
                    EllesmereUI:RefreshPage(true)
                    EllesmereUI.SmoothScrollTo(0)
                    -- Re-run the preview next frame once the rebuilt layout has
                    -- settled (same fix as the Main Frames unit selector).
                    C_Timer.After(0, UpdatePreview)
                end
            )
            PP.Point(ddBtn, "TOP", hdr, "TOP", 0, fy)
            ddBtn:SetHeight(DD_H)
            fy = fy - DD_H - 20

            local side = unitSide[selectedMiniUnit] or "left"
            local preview = ns.UFO_BuildUnitPreview(hdr, selectedMiniUnit, side)
            activePreview = preview
            local previewScale = preview._previewScale or 1
            local initBuffTopPad = preview._buffTopPad or 0
            preview._headerDropdownOY = math.abs(fy)
            preview:ClearAllPoints()
            PP.Point(preview, "TOP", hdr, "TOP", 0, (fy - initBuffTopPad) / previewScale)
            preview._lastOY = (fy - initBuffTopPad) / previewScale
            preview:Update()
            local previewH = preview:GetHeight() * preview:GetScale()
            local buffExtra = preview._buffExtra or 0
            local detTopExtra = preview._detTopExtra or 0
            fy = fy - previewH - buffExtra - detTopExtra - 20
            miniHeaderFixedH = 20 + DD_H + 20 + 20
            if preview then preview._headerFixedH = miniHeaderFixedH end

            local _miniHeaderBaseH = math.abs(fy)
            return _miniHeaderBaseH
        end
        EllesmereUI:SetContentHeader(_miniHeaderBuilder)

        parent._showRowDivider = true

        -------------------------------------------------------------------
        --  Route to mini builders
        -------------------------------------------------------------------
        if selectedMiniUnit == "targettarget" then
            y = -ns.UFO_BuildFoTToTOptions(W, parent, y, db.profile.targettarget, "targettarget")
        elseif selectedMiniUnit == "focustarget" then
            y = -ns.UFO_BuildFoTToTOptions(W, parent, y, db.profile.focustarget, "focustarget")
        elseif selectedMiniUnit == "pet" then
            y = -ns.UFO_BuildPetOptions(W, parent, y)
        end

        -------------------------------------------------------------------
        --  CLICK NAVIGATION
        -------------------------------------------------------------------
        local PlaySettingGlow = EllesmereUI.MakeSettingGlow({ color = EllesmereUI.ELLESMERE_GREEN })
        local function NavigateToSetting(key)
            ns._UFNavigateToSetting(parent._ufClickTargets, key, PlaySettingGlow)
        end
        local hitStyle = { container = true }
        local function CreateHitOverlay(element, mappingKey, isText, frameLevelOverride, opts)
            return (EllesmereUI.CreatePreviewHitOverlay(element, NavigateToSetting, mappingKey, isText, frameLevelOverride, opts, hitStyle))
        end

        -- Create hit overlays on preview elements
        if activePreview then
            local pv = activePreview
            local baseLevel = (pv._health and pv._health:GetFrameLevel() or 20) + 15
            local textLevel = baseLevel + 10
            if pv._health then CreateHitOverlay(pv._health, "healthBar", false, baseLevel, { hlAnchor = pv._border or pv._health }) end
            -- WoW Forever's pet: power bar, power text and happiness icon (the
            -- other mini previews build none of them).
            if pv._power then CreateHitOverlay(pv._power, "powerBar", false, baseLevel) end
            if pv._ppFS and pv._ppFS:IsShown() then CreateHitOverlay(pv._ppFS, "powerBarText", true, textLevel) end
            if pv._happyInd then CreateHitOverlay(pv._happyInd, "petHappiness", false, baseLevel + 20) end
            if pv._portraitFrame and pv._portraitFrame:IsShown() then CreateHitOverlay(pv._portraitFrame, "portrait", false, baseLevel) end
            if pv._castbar then
                local castLevel = pv._castbar:GetFrameLevel() + 20
                CreateHitOverlay(pv._castbar, "castBar", false, castLevel)
            end
            if pv._nameFS and pv._nameFS:IsShown() then CreateHitOverlay(pv._nameFS, "nameText", true, textLevel) end
            if pv._hpFS and pv._hpFS:IsShown() then CreateHitOverlay(pv._hpFS, "healthText", true, textLevel) end
        end

        return abs(y)
    end

    ---------------------------------------------------------------------------
    --  Boss Frames page  (single-unit page; no unit dropdown -- boss only)
    ---------------------------------------------------------------------------
    -- Stored on ns (not init-function locals) to stay clear of the Lua 5.1 200-local
    -- cap. Header builder mirrors the Mini page's minus the unit dropdown (boss is the
    -- only unit here); click-navigation block reuses the Mini page's machinery.
    ns._bossHeaderBuilder = nil
    ns._BuildBossPage = function(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset

        activePreview = nil

        -------------------------------------------------------------------
        --  CONTENT HEADER  (preview only, no dropdown)
        -------------------------------------------------------------------
        ns._bossHeaderBuilder = function(hdr, hdrW)
            local fy = -20
            local side = unitSide.boss or "right"
            local preview = ns.UFO_BuildUnitPreview(hdr, "boss", side)
            activePreview = preview
            local previewScale = preview._previewScale or 1
            local initBuffTopPad = preview._buffTopPad or 0
            preview._headerDropdownOY = math.abs(fy)
            preview:ClearAllPoints()
            PP.Point(preview, "TOP", hdr, "TOP", 0, (fy - initBuffTopPad) / previewScale)
            preview._lastOY = (fy - initBuffTopPad) / previewScale
            preview:Update()
            local previewH = preview:GetHeight() * preview:GetScale()
            local buffExtra = preview._buffExtra or 0
            local detTopExtra = preview._detTopExtra or 0
            fy = fy - previewH - buffExtra - detTopExtra - 20
            preview._headerFixedH = 20 + 20
            return math.abs(fy)
        end
        EllesmereUI:SetContentHeader(ns._bossHeaderBuilder)

        parent._showRowDivider = true

        -------------------------------------------------------------------
        --  Boss section
        -------------------------------------------------------------------
        y = -ns.UFO_BuildBossOptions(W, parent, y)

        -------------------------------------------------------------------
        --  CLICK NAVIGATION  (mirrors the Mini Frames page)
        -------------------------------------------------------------------
        local PlaySettingGlow = EllesmereUI.MakeSettingGlow({ color = EllesmereUI.ELLESMERE_GREEN })
        local function NavigateToSetting(key)
            ns._UFNavigateToSetting(parent._ufClickTargets, key, PlaySettingGlow)
        end
        local hitStyle = { container = true }
        local function CreateHitOverlay(element, mappingKey, isText, frameLevelOverride, opts)
            return (EllesmereUI.CreatePreviewHitOverlay(element, NavigateToSetting, mappingKey, isText, frameLevelOverride, opts, hitStyle))
        end

        -- Create hit overlays on preview elements
        if activePreview then
            local pv = activePreview
            local baseLevel = (pv._health and pv._health:GetFrameLevel() or 20) + 15
            local textLevel = baseLevel + 10
            -- Health bar and power bar are separately clickable, each covering just
            -- its own bar (replacing the old ambiguous whole-frame overlay).
            if pv._health then CreateHitOverlay(pv._health, "healthBar", false, baseLevel) end
            if pv._power then CreateHitOverlay(pv._power, "powerBar", false, baseLevel) end
            if pv._ppFS and pv._ppFS:IsShown() then CreateHitOverlay(pv._ppFS, "powerBarText", true, textLevel) end
            if pv._portraitFrame and pv._portraitFrame:IsShown() then CreateHitOverlay(pv._portraitFrame, "portrait", false, baseLevel) end
            if pv._castbar then
                local castLevel = pv._castbar:GetFrameLevel() + 20
                CreateHitOverlay(pv._castbar, "castBar", false, castLevel)
                -- Spell icon -> Show Cast Icon setting.
                if pv._castIconFrame then CreateHitOverlay(pv._castIconFrame, "castIcon", false, castLevel) end
            end
            if pv._nameFS and pv._nameFS:IsShown() then CreateHitOverlay(pv._nameFS, "nameText", true, textLevel) end
            if pv._hpFS and pv._hpFS:IsShown() then CreateHitOverlay(pv._hpFS, "healthText", true, textLevel) end
            -- Blizzard Style level number: built whenever the art has a level
            -- circle and shown with the text (the preview toggles it).
            if pv._levelFS then
                local lvOv = CreateHitOverlay(pv._levelFS, "levelText", true, textLevel)
                pv._levelOv = lvOv
                if not pv._levelFS:IsShown() then lvOv:Hide() end
            end
            -- Buff/Debuff icons -> their aura settings (Simple Display or Location,
            -- resolved at click time). Overlay every icon so newly shown ones stay
            -- clickable without a header rebuild.
            if pv._buffIcons then
                for i = 1, #pv._buffIcons do
                    if pv._buffIcons[i] then CreateHitOverlay(pv._buffIcons[i], "buffIcon", false, baseLevel) end
                end
            end
            if pv._debuffIcons then
                for i = 1, #pv._debuffIcons do
                    if pv._debuffIcons[i] then CreateHitOverlay(pv._debuffIcons[i], "debuffIcon", false, baseLevel) end
                end
            end
        end

        return abs(y)
    end

    ---------------------------------------------------------------------------
    --  Unlock Mode page  (stub SelectPage intercepts this before buildPage)
    ---------------------------------------------------------------------------
    local function BuildUnlockPage(pageName, parent, yOffset)
        -- SelectPage() intercepts "Unlock Mode" and fires _openUnlockMode directly.
        -- This stub exists only as a safety net in case buildPage is ever called.
        if EllesmereUI._openUnlockMode then
            C_Timer.After(0, EllesmereUI._openUnlockMode)
        end
        return 100
    end


    ---------------------------------------------------------------------------
    --  Register the module
    ---------------------------------------------------------------------------
    local ufSearchTerms = {}
    for _, label in pairs(unitLabels) do ufSearchTerms[#ufSearchTerms + 1] = label end
    for _, label in pairs(miniUnitLabels) do ufSearchTerms[#ufSearchTerms + 1] = label end
    -- "external defensives" matches the External Defensive aura-filter
    -- checkbox and the External Defensives bar inside Player Aura Bars.
    local _paTerms = { "external defensives", "externals", "pain suppression" }
    for _, t in ipairs(_paTerms) do ufSearchTerms[#ufSearchTerms + 1] = t end
    local _pabTerms = { "aura bars", "player aura bars", "buff bar", "debuff bar", "cooldown bars", "dispel colors", "grow direction" }
    for _, t in ipairs(_pabTerms) do ufSearchTerms[#ufSearchTerms + 1] = t end

    -- Rebuild preview when spec changes (class resource pips may appear/disappear)
    local ufOptSpecFrame = CreateFrame("Frame")
    ufOptSpecFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    ufOptSpecFrame:SetScript("OnEvent", function(_, _, unit)
        if unit ~= "player" then return end
        -- Only invalidate + rebuild when the panel is actually open. Invalidating while
        -- closed destroys all cached pages, causing a blank panel on next open.
        if EllesmereUI._mainFrame and EllesmereUI._mainFrame:IsShown() then
            EllesmereUI:InvalidatePageCache()
            C_Timer.After(0.2, function()
                EllesmereUI:RefreshPage(true)
            end)
        end
    end)

    -- Shared helpers and state for the builders under UnitFrames_Options\
    -- (loaded before this file, read when a page builds).
    ns._UFO_OptEnv = {
        _previewBuffIcons = _previewBuffIcons, _previewCreatureNames = _previewCreatureNames, abs = abs,
        AddDarkModeBlock = AddDarkModeBlock, allPreviews = allPreviews, ApplyClassIconTexture_Preview = ApplyClassIconTexture_Preview,
        ApplyPreviewPortraitShape = ApplyPreviewPortraitShape, AttachDebuffModeWarn = AttachDebuffModeWarn, AttachFrameSourceCog = AttachFrameSourceCog,
        BlizzPreviewScale = BlizzPreviewScale, btbPositionOrder = btbPositionOrder, btbPositionValues = btbPositionValues,
        btbTextOrder = btbTextOrder, btbTextValues = btbTextValues, buffAnchorOrder = buffAnchorOrder,
        buffAnchorValues = buffAnchorValues, buffGrowthOrder = buffGrowthOrder, buffGrowthValues = buffGrowthValues,
        BuildApplyAllRow = BuildApplyAllRow, BuildBarTexDropdown = BuildBarTexDropdown, BuildInactiveNotice = BuildInactiveNotice,
        BuildLookSourceRow = BuildLookSourceRow,
        CLASS_FULL_COORDS = CLASS_FULL_COORDS, CLASS_FULL_SPRITE_BASE = CLASS_FULL_SPRITE_BASE, classIconLocOrder = classIconLocOrder,
        classIconLocValues = classIconLocValues, classIconOrder = classIconOrder, classIconValues = classIconValues,
        classPowerPosOrder = classPowerPosOrder, classPowerPosValues = classPowerPosValues, classPowerStyleOrder = classPowerStyleOrder,
        classPowerStyleValues = classPowerStyleValues, classThemeSubOrder = classThemeSubOrder, classThemeSubValues = classThemeSubValues,
        db = db, DebuffModeDropdownCfg = DebuffModeDropdownCfg, detPortraitShapeOrder = detPortraitShapeOrder,
        detPortraitShapeValues = detPortraitShapeValues, frames = frames, GetUFOptOutline = GetUFOptOutline,
        GROUP_UNIT_ORDER = GROUP_UNIT_ORDER, healthTextOrder = healthTextOrder, healthTextOrderBoss = healthTextOrderBoss,
        healthTextOrderPlayer = healthTextOrderPlayer, healthTextOrderTargetFocus = healthTextOrderTargetFocus, healthTextValues = healthTextValues,
        MINI_GROUP_ORDER = MINI_GROUP_ORDER, optState = optState, portraitArtOrder = portraitArtOrder,
        portraitArtValues = portraitArtValues, portraitModeOrder2 = portraitModeOrder2, portraitModeValues2 = portraitModeValues2,
        portraitNonPlayerOrder = portraitNonPlayerOrder, portraitNonPlayerValues = portraitNonPlayerValues, PP = PP,
        PREVIEW_FONT = PREVIEW_FONT, PromptReloadIfUnspawned = PromptReloadIfUnspawned, RegisterWidgetRefresh = RegisterWidgetRefresh,
        ReloadAndUpdate = ReloadAndUpdate, ResolveBlizzPreview = ResolveBlizzPreview, SetPVFont = SetPVFont,
        SHORT_LABELS = SHORT_LABELS, SOLID_BACKDROP = SOLID_BACKDROP, SwapAuraSlot = SwapAuraSlot,
        UF_ImpCastGlowDesc = UF_ImpCastGlowDesc, UF_PurgeGlowDesc = UF_PurgeGlowDesc, UNIT_DB_MAP = UNIT_DB_MAP,
        UNIT_LABELS_SUP = UNIT_LABELS_SUP, unitSide = unitSide, UpdatePreview = UpdatePreview,
    }

    ---------------------------------------------------------------------------
    --  Player Aura Bars page (External Defensives lives inside it, as a
    --  third built-in bar -- see EUI_PlayerAuraBars_ManagerPages.lua)
    ---------------------------------------------------------------------------

    EllesmereUI:RegisterModule("EllesmereUIUnitFrames", {
        title       = "Unit Frames",
        description = "Configure unit frame appearance and behavior.",
        pages       = { PAGE_DISPLAY, PAGE_BOSS, PAGE_MINI, PAGE_AURA_BARS },
        searchTerms = ufSearchTerms,
        buildPage   = function(pageName, parent, yOffset)
            if EllesmereUI._prebuilding and pageName == PAGE_AURA_BARS then
                return
            end
            -- Clean up Player Aura Bars root when switching away. Needed here AND in
            -- onPageCacheRestore below: this covers a fresh build of the destination
            -- page, that one covers a cache-restored destination -- without both,
            -- cleanup is inconsistent across tab switches (mirrors EUI_RaidFrames_Options.lua's _bmRoot/_dmRoot/_ccRoot pattern).
            if pageName ~= PAGE_AURA_BARS and ns._pabRoot then
                ns._pabRoot:Hide()
                ns._pabRoot:SetParent(nil)
                ns._pabRoot = nil
            end
            -- Randomize preview creature IDs on every tab switch
            RandomizePreviewCreatures()
            ns.UF_AskExisting2DMirror()
            if pageName == PAGE_DISPLAY then
                return BuildFrameDisplayPage(pageName, parent, yOffset)
            elseif pageName == PAGE_BOSS then
                return ns._BuildBossPage(pageName, parent, yOffset)
            elseif pageName == PAGE_MINI then
                return BuildMiniPage(pageName, parent, yOffset)
            elseif pageName == PAGE_AURA_BARS then
                if ns.PABMP_BuildPage then return ns.PABMP_BuildPage(pageName, parent, yOffset) end
            end
        end,
        getHeaderBuilder = function(pageName)
            if pageName == PAGE_DISPLAY then
                return _displayHeaderBuilder
            elseif pageName == PAGE_BOSS then
                return ns._bossHeaderBuilder
            elseif pageName == PAGE_MINI then
                return _miniHeaderBuilder
            end
            return nil
        end,
        -- Main/Mini Frames content gates on whichever unit is selected (default
        -- always "player"/"targettarget"), so a hidden pre-build that only builds the
        -- default leaves other units' settings unsearchable until picked live. Both
        -- unit lists are small and fixed, so build once per unit rather than collapsing to representative shapes.
        getPrebuildVariants = function(pageName)
            if pageName == PAGE_DISPLAY then
                return { setter = EllesmereUI._setUnitFrameUnit, keys = unitOrder, currentKey = optState.selectedUnit }
            elseif pageName == PAGE_MINI then
                return { setter = EllesmereUI._setMiniUnit, keys = miniUnitOrder, currentKey = selectedMiniUnit }
            end
            return nil
        end,
        onPageCacheRestore = function(pageName)
            -- Clean up Player Aura Bars root when switching away
            if pageName ~= PAGE_AURA_BARS and ns._pabRoot then
                ns._pabRoot:Hide()
                ns._pabRoot:SetParent(nil)
                ns._pabRoot = nil
            elseif pageName == PAGE_AURA_BARS and not ns._pabRoot then
                -- PABMP_BuildPage bypasses `parent` and builds onto the live shared
                -- scrollFrame into ns._pabRoot (see buildPage's _prebuilding guard
                -- above). The framework's page cache doesn't know about that
                -- self-managed root: on a cache-restore decision, content already torn
                -- down by an earlier switch-away never gets rebuilt. Mirrors
                -- EUI__General_Options.lua's PAGE_PROFILES/PAGE_OVERRIDES fix (CleanupProfilesRoot + deferred RefreshPage(true) guarded by GetActiveModule/GetActivePage).
                C_Timer.After(0, function()
                    if EllesmereUI:GetActiveModule() == "EllesmereUIUnitFrames"
                       and EllesmereUI:GetActivePage() == pageName then
                        EllesmereUI:RefreshPage(true)
                    end
                end)
            end
            RandomizePreviewCreatures()
            ns.UF_AskExisting2DMirror()
            -- Hide all UIParent-parented disabled overlays before restoring
            -- (they persist across tab switches since they're not children of pf)
            for _, pv in pairs(allPreviews) do
                if pv and pv._disabledOverlay then pv._disabledOverlay:Hide() end
            end
            -- Force re-anchor previews after cache restore (parent changed)
            for _, pv in pairs(allPreviews) do
                if pv then
                    pv._lastOY = nil
                    -- Reset portrait anchor flag so Update() re-anchors it
                    if pv._portraitFrame then pv._portraitFrame._anchored = false end
                    -- Reset health anchor key so Update() re-anchors health bar
                    if pv._health then pv._health._anchorKey = nil end
                end
            end
            UpdatePreview()
            -- Refresh hint visibility on cache restore
            local dismissed = IsPreviewHintDismissed()
            if pageName == PAGE_DISPLAY and optState._ufPreviewHintFS_display then
                if dismissed then
                    optState._ufPreviewHintFS_display:Hide()
                else
                    optState._ufPreviewHintFS_display:SetAlpha(0.45)
                    optState._ufPreviewHintFS_display:Show()
                end
            end
        end,
        onReset     = function()
            db:ResetProfile()
            -- No reload here: the footer Reset popup (reload = true) reloads after this returns.
        end,
        -- Tears down Boss Preview on module switch (RegisterOnHide above
        -- only covers closing the whole options window).
        onModuleLeave = function()
            if ns._bossPreviewActive and ns.SetBossPreview then
                ns.SetBossPreview(false)
            end
        end,
    })

    ---------------------------------------------------------------------------
    --  Slash command  /euf
    ---------------------------------------------------------------------------
    SLASH_ELLESMEREUNITFRAMES1 = "/euf"
    SlashCmdList.ELLESMEREUNITFRAMES = function(msg)
        if InCombatLockdown and InCombatLockdown() then
            print("Cannot open options in combat")
            return
        end

        if msg == "reset" then
            db:ResetProfile()
            EllesmereUI.RequestReload()
            return
        end

        EllesmereUI:ShowModule("EllesmereUIUnitFrames")
    end
    end -- ns._InitEUIModule

    -- If SetupOptionsPanel already ran before PLAYER_LOGIN (unlikely but safe),
    -- fire immediately
    if ns.db then
        ns._InitEUIModule()
    end
end)
-- LoadOnDemand: this addon loads after PLAYER_LOGIN, so the event above will never fire; run the init now.
if IsLoggedIn() then initFrame:GetScript("OnEvent")(initFrame) end
