if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_GlowOptions.lua -- shared glow option controls. Each glow setting
--  is a SITE descriptor: host ("icon"/"bar"/"engine"), view or toShared/
--  fromShared/order for its saved style numbering, excludes, noneValue,
--  extras (Blizzard Default, Solid; one with a style renders, e.g. Blizzard
--  Border; one marked colored is drawn in the site's color, e.g. Solid
--  Border), caps {mode, params, bg}, defaultColor, get/set on its own keys
--  ("style", "mode", "color", "lines", "thickness", "speed", "bg", "bgColor"),
--  plus optional isOff, onChange, confirm, disabled, colorDisabled, cogRows,
--  and styleDisabled + styleDisabledTooltip (a whole sentence, shown as is):
--  a lock on the style alone -- the color swatches and the Pixel Glow cog stay
--  live, and the template leaves the site alone while it holds.


local GO = {}
EllesmereUI.GlowOptions = GO

-- The glow engine loads in the parent addon, before any options file.
local G = EllesmereUI.Glows

-------------------------------------------------------------------------------
--  Style value mapping
-------------------------------------------------------------------------------
local function NoneValue(desc)
    if desc.noneValue ~= nil then return desc.noneValue end
    return 0
end

-- Saved value -> shared index, or nil for None and the extras.
function GO.ToShared(desc, v)
    if v == nil or v == NoneValue(desc) then return nil end
    if desc.toShared then return desc.toShared(v) end
    if desc.view then return desc.view.toShared[v] end
    if type(v) == "number" and v >= 1 and v <= #G.STYLES then return v end
    return nil
end

-- Shared index -> saved value.
function GO.FromShared(desc, idx)
    if desc.fromShared then return desc.fromShared(idx) end
    if desc.view then return desc.view.fromShared[idx] end
    return idx
end

-- Shared index -> the nearest style this site both renders and offers (its view
-- or order can lack styles the host could draw), plus whether it changed.
function GO.Resolve(desc, idx)
    local ex = desc._resolveEx
    if not ex then
        ex = {}
        for i = 1, #G.STYLES do
            if (desc.excludes and desc.excludes[i]) or GO.FromShared(desc, i) == nil then ex[i] = true end
        end
        desc._resolveEx = ex
    end
    return G.ResolveStyle(idx, desc.host, ex)
end

local function StyleOffered(desc, idx)
    local caps = G.HOSTS[desc.host or "icon"]
    return caps and caps[idx] and not (desc.excludes and desc.excludes[idx])
end

-- Saved values offered by the site, in its own order.
local function OrderedStyleValues(desc)
    local out = {}
    if desc.order then
        for _, v in ipairs(desc.order) do
            local idx = GO.ToShared(desc, v)
            if idx and StyleOffered(desc, idx) then out[#out + 1] = v end
        end
    elseif desc.view then
        for _, i in ipairs(desc.view.ordered) do
            if StyleOffered(desc, desc.view.toShared[i]) then out[#out + 1] = i end
        end
    else
        for i = 1, #G.STYLES do
            if StyleOffered(desc, i) then out[#out + 1] = i end
        end
    end
    return out
end

-- values/order pair for a WidgetFactory dropdown.
function GO.StyleValues(desc)
    local values, order = {}, {}
    if not desc.noNone then
        local nv = NoneValue(desc)
        values[nv] = "None"
        order[#order + 1] = nv
    end
    if desc.extras then
        for _, x in ipairs(desc.extras) do
            values[x.value] = x.label
            order[#order + 1] = x.value
        end
    end
    local styles = G.STYLES
    for _, v in ipairs(OrderedStyleValues(desc)) do
        values[v] = styles[GO.ToShared(desc, v)].name
        order[#order + 1] = v
    end
    return values, order
end

-- The value a style control shows: the saved one, or for a saved style this
-- host cannot render, the style that actually renders.
local function DisplayValue(desc, values)
    local v = desc.get("style")
    if v == nil then return NoneValue(desc) end
    if values[v] ~= nil then return v end
    local idx = GO.ToShared(desc, v)
    if idx then
        local rv = GO.FromShared(desc, (GO.Resolve(desc, idx)))
        if rv ~= nil and values[rv] ~= nil then return rv end
    end
    return NoneValue(desc)
end

-------------------------------------------------------------------------------
--  State
-------------------------------------------------------------------------------
function GO.IsOff(desc)
    if desc.isOff and desc.isOff() then return true end
    local v = desc.get("style")
    return v == nil or v == NoneValue(desc)
end

-- The site's own lock (desc.disabled: every control), or a style-only lock
-- (desc.styleDisabled: the style dropdown alone). Either keeps the template out.
function GO.StyleLocked(desc)
    if desc.disabled and desc.disabled() then return true end
    return (desc.styleDisabled and desc.styleDisabled()) and true or false
end

-- A real glow (not off, not an extra such as Blizzard Default or Solid).
-- paramsOnly sites (Pixel Glow parameters without a style of their own, e.g. a
-- CDM bar's pixelGlow* keys) always count as one.
function GO.IsCustomGlow(desc)
    if desc.paramsOnly then return true end
    if GO.IsOff(desc) then return false end
    return GO.ToShared(desc, desc.get("style")) ~= nil
end

-- The extra entry for the site's current value, if that value is one.
local function CurrentExtra(desc)
    if not desc.extras then return nil end
    local v = desc.get("style")
    for _, x in ipairs(desc.extras) do
        if x.value == v then return x end
    end
    return nil
end

-- Something is drawn that takes a color: a custom glow, or a rendered extra
-- (x.style, e.g. Blizzard Border). Rendered extras are never template targets.
function GO.Renders(desc)
    if GO.IsCustomGlow(desc) then return true end
    if GO.IsOff(desc) then return false end
    local x = CurrentExtra(desc)
    return x ~= nil and x.style ~= nil
end

function GO.IsPixel(desc)
    if desc.paramsOnly then return true end
    return GO.IsCustomGlow(desc) and GO.ToShared(desc, desc.get("style")) == 1
end

-- Render spec for StartSpecGlow from the site's current values (one reused
-- table per descriptor).
function GO.Spec(desc)
    local s = desc._spec
    if not s then s = {}; desc._spec = s end
    local x = CurrentExtra(desc)
    s.style = GO.ToShared(desc, desc.get("style")) or (x and x.style) or 1
    s.excludes = desc.excludes
    local dc = desc.defaultColor
    local mode = desc.caps and desc.caps.mode and desc.get("mode") or "custom"
    local cr, cg, cb = desc.get("color")
    s.r, s.g, s.b = G.ResolveColor(mode, cr, cg, cb, dc and dc.r, dc and dc.g, dc and dc.b)
    local caps = desc.caps or {}
    if caps.params then
        s.lines, s.thickness, s.speed = desc.get("lines"), desc.get("thickness"), desc.get("speed")
    else
        s.lines, s.thickness, s.speed = nil, nil, nil
    end
    if caps.bg and desc.get("bg") then
        s.bg = true
        s.bgR, s.bgG, s.bgB = desc.get("bgColor")
    else
        s.bg, s.bgR, s.bgG, s.bgB = nil, nil, nil, nil
    end
    return s
end

-- Refresh the module, then this site's current preview (skipped once that
-- preview's page is gone: descriptors outlive page rebuilds).
function GO.Changed(desc)
    if desc.onChange then desc.onChange() end
    local pf = desc._previewFrame
    if desc._preview and pf and pf:IsVisible() then desc._preview() end
end

-------------------------------------------------------------------------------
--  Controls
-------------------------------------------------------------------------------

-- Lock reason for color controls while no glow is picked (a whole sentence).
local NO_STYLE_TIP = "This option requires a Glow Style other than None"

-- The style control's getter: None while off, else the displayed value.
local function StyleGetter(desc, values)
    return function()
        if desc.isOff and desc.isOff() then return NoneValue(desc) end
        return DisplayValue(desc, values)
    end
end

-- The style control's lock: the site's own disabled/disabledTooltip/rawTooltip,
-- widened by styleDisabled when the site has one (its sentence shows as is
-- while only the style is locked).
local function StyleLock(desc)
    if not desc.styleDisabled then return desc.disabled, desc.disabledTooltip, desc.rawTooltip end
    local function siteOff() return desc.disabled and desc.disabled() end
    return function() return GO.StyleLocked(desc) end,
        function()
            if not siteOff() then return desc.styleDisabledTooltip end
            local tt = desc.disabledTooltip
            if type(tt) == "function" then tt = tt() end
            return tt
        end,
        function()
            if not siteOff() then return true end
            local raw = desc.rawTooltip
            if type(raw) == "function" then raw = raw() end
            return raw
        end
end

-- DualRow half spec for the style dropdown.
function GO.DropdownSpec(desc, text, tooltip)
    local values, order = GO.StyleValues(desc)
    local lockFn, lockTip, lockRaw = StyleLock(desc)
    return {
        type = "dropdown", text = text or "Glow",
        values = values, order = order,
        tooltip = tooltip,
        disabled = lockFn,
        disabledTooltip = lockTip,
        rawTooltip = lockRaw,
        getValue = StyleGetter(desc, values),
        setValue = function(v)
            local function commit()
                desc.set("style", v)
                GO.Changed(desc)
                C_Timer.After(0, function() EllesmereUI:RefreshPage() end)
            end
            if desc.confirm then desc.confirm(v, commit) else commit() end
        end,
    }
end

local function NotPixel(desc) return function() return not GO.IsPixel(desc) end end

-- Cog edits refresh the page's widgets (status rows follow them) once per
-- frame, so a slider drag does not queue a refresh per tick.
local _cogRefreshQueued = false
local function CogChanged(desc)
    GO.Changed(desc)
    if _cogRefreshQueued then return end
    _cogRefreshQueued = true
    C_Timer.After(0, function()
        _cogRefreshQueued = false
        EllesmereUI:RefreshPage()
    end)
end

-- Pixel Glow cog rows (Lines / Thickness / Speed / Background), plus the
-- site's own extra rows.
local function CogRows(desc)
    local rows = {}
    local caps = desc.caps or {}
    local notPixel = NotPixel(desc)
    if caps.params then
        rows[#rows + 1] = { type = "slider", label = "Lines", min = 2, max = 16, step = 1,
            get = function() return desc.get("lines") or 8 end,
            set = function(v) desc.set("lines", v); CogChanged(desc) end,
            disabled = notPixel, disabledTooltip = "Pixel Glow" }
        rows[#rows + 1] = { type = "slider", label = "Thickness", min = 1, max = desc.thicknessMax or 4, step = 1,
            get = function() return desc.get("thickness") or 2 end,
            set = function(v) desc.set("thickness", v); CogChanged(desc) end,
            disabled = notPixel, disabledTooltip = "Pixel Glow" }
        rows[#rows + 1] = { type = "slider", label = "Speed", min = 1, max = 8, step = 1,
            get = function() return G.SpeedToUI(desc.get("speed")) end,
            set = function(v) desc.set("speed", G.SpeedFromUI(v)); CogChanged(desc) end,
            disabled = notPixel, disabledTooltip = "Pixel Glow" }
    end
    if caps.bg then
        rows[#rows + 1] = { type = "toggle", label = "Background",
            get = function() return desc.get("bg") == true end,
            set = function(v) desc.set("bg", v and true or nil); CogChanged(desc) end,
            disabled = notPixel, disabledTooltip = "Pixel Glow" }
        rows[#rows + 1] = { type = "colorpicker", label = "Background Color",
            get = function()
                local r, g, b = desc.get("bgColor")
                return r or 0, g or 0, b or 0
            end,
            set = function(r, g, b) desc.set("bgColor", r, g, b); CogChanged(desc) end,
            disabled = function() return notPixel() or desc.get("bg") ~= true end,
            disabledTooltip = "Pixel Glow Background" }
    end
    if desc.cogRows then
        for _, r in ipairs(desc.cogRows) do rows[#rows + 1] = r end
    end
    return rows
end

GO.CogRows = CogRows

-- Default/Custom/Class swatches as one BuildCogPopup row (off: when the
-- row is locked).
local function ColorRow(desc, off)
    local function modeAlpha(m) return function() return (desc.get("mode") == m) and 1 or 0.3 end end
    local function pick(m) return function() desc.set("mode", m); GO.Changed(desc); EllesmereUI:RefreshPage() end end
    local dc = desc.defaultColor
    return { type = "multiswatch", label = "Glow Color",
        disabled = off, disabledTooltip = "a Glow Style",
        swatches = {
            { tooltip = "Default", refreshAlpha = modeAlpha("default"), onClick = pick("default"),
              getValue = function()
                  local c = G.DEFAULT_COLOR
                  return c.r, c.g, c.b, 1
              end },
            { tooltip = "Custom Color", refreshAlpha = modeAlpha("custom"),
              getValue = function()
                  local r, g, b = desc.get("color")
                  return r or (dc and dc.r) or 1, g or (dc and dc.g) or 1, b or (dc and dc.b) or 1, 1
              end,
              setValue = function(r, g, b) desc.set("color", r, g, b); CogChanged(desc) end,
              -- Suite convention: an inactive custom swatch only selects custom mode.
              onClick = function(self)
                  if desc.get("mode") ~= "custom" then
                      desc.set("mode", "custom"); GO.Changed(desc); EllesmereUI:RefreshPage()
                  elseif self._eabOrigClick then
                      self._eabOrigClick(self)
                  end
              end },
            { tooltip = "Class Colored", refreshAlpha = modeAlpha("class"), onClick = pick("class"),
              getValue = function()
                  local c = EllesmereUI.GetClassColor(EllesmereUI._playerClass)
                  return c.r, c.g, c.b, 1
              end },
        } }
end

-- Every glow control as BuildCogPopup rows, for sites whose whole glow setting
-- lives inside a cog: style dropdown, Default/Custom/Class swatches, pixel rows.
function GO.PopupRows(desc, styleLabel)
    local values, order = GO.StyleValues(desc)
    local rows = {}
    local off = function() return not GO.Renders(desc) end
    local lockFn, lockTip, lockRaw = StyleLock(desc)
    rows[#rows + 1] = { type = "dropdown", label = styleLabel or "Glow Style",
        values = values, order = order, ddWidth = 170,
        disabled = lockFn, disabledTooltip = lockTip, rawTooltip = lockRaw,
        get = StyleGetter(desc, values),
        set = function(v)
            local function commit() desc.set("style", v); GO.Changed(desc); EllesmereUI:RefreshPage() end
            if desc.confirm then desc.confirm(v, commit) else commit() end
        end }
    local caps = desc.caps or {}
    if caps.mode then rows[#rows + 1] = ColorRow(desc, off) end
    for _, r in ipairs(CogRows(desc)) do rows[#rows + 1] = r end
    return rows
end

-- Color swatches and the Pixel Glow cog, chained left of the region's control.
-- rgn = the DualRow half-region holding the style dropdown; colorRgn = an
-- optional free half-region (a "Glow Color" label) that takes the swatches.
-- A style-only lock (desc.styleDisabled) leaves both live.
function GO.AttachInline(rgn, desc, colorRgn)
    if EllesmereUI._prebuilding or not rgn then return end
    local PP = EllesmereUI.PanelPP
    local caps = desc.caps or {}
    local function siteOff() return desc.disabled and desc.disabled() end
    local function off()
        if siteOff() then return true end
        return not GO.Renders(desc)
    end
    -- colorDisabled: the site's color comes from elsewhere (NP Color by Type).
    -- A colored extra (Solid Border) draws nothing to style but takes the color.
    local function colorOff()
        if siteOff() then return true end
        if not GO.Renders(desc) then
            local x = CurrentExtra(desc)
            if not (x and x.colored) then return true end
        end
        return (desc.colorDisabled and desc.colorDisabled()) or false
    end
    -- Why the swatches are locked, as the sentence shown: the site's own
    -- requirement (resolved like its dropdown's), no glow to color, or a
    -- color that comes from elsewhere.
    local function colorLockTip()
        if siteOff() then return EllesmereUI.ResolveDisabledTip(desc) end
        if not GO.Renders(desc) then return EllesmereUI.DisabledTooltip(NO_STYLE_TIP) end
        if desc.colorDisabledTooltip then
            return EllesmereUI.DisabledTooltip(desc.colorDisabledTooltip, "disabled")
        end
    end
    local level = rgn:GetFrameLevel() + 3
    -- Disabled swatches still explain themselves: a mouse blocker over them
    -- (from first to last) with the reason, shown while the color is locked.
    local function Blocker(first, last)
        local block = CreateFrame("Frame", nil, colorRgn or rgn)
        block:SetPoint("TOPLEFT", first, "TOPLEFT")
        block:SetPoint("BOTTOMRIGHT", last, "BOTTOMRIGHT")
        block:SetFrameLevel(level + 10)
        block:EnableMouse(true)
        block:SetScript("OnEnter", function(self)
            local tip = colorLockTip()
            if tip then EllesmereUI.ShowWidgetTooltip(self, tip) end
        end)
        block:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        block:SetShown(colorOff())
        return block
    end

    -- colorInCog: the row is too narrow for the swatches; they go in the cog.
    local colorInCog = desc.colorInCog and caps.mode
    if colorInCog then
        -- The swatches are the cog's first row (below).
    elseif caps.mode then
        local srgn = colorRgn or rgn
        local customSw, defaultSw, classSw = EllesmereUI.BuildTrioColorSwatch(srgn, level, {
            getMode = function() return desc.get("mode") or "custom" end,
            setMode = function(m) desc.set("mode", m) end,
            getCustomRGB = function()
                local r, g, b = desc.get("color")
                local dc = desc.defaultColor
                return r or (dc and dc.r) or 1, g or (dc and dc.g) or 1, b or (dc and dc.b) or 1
            end,
            setCustomRGB = function(r, g, b) desc.set("color", r, g, b) end,
            -- Mode clicks: the trio's highlight and page status refresh via widget refresh.
            onChange = function() GO.Changed(desc); EllesmereUI:RefreshPage() end,
            hasClassColor = true,
            disabled = colorOff,
            overrideSize = 20,
        })
        local anchor = srgn._lastInline or srgn._control
        if anchor then
            PP.Point(classSw, "RIGHT", anchor, "LEFT", -12, 0)
        else
            PP.Point(classSw, "RIGHT", srgn, "RIGHT", -20, 0)
        end
        PP.Point(customSw, "RIGHT", classSw, "LEFT", -6, 0)
        PP.Point(defaultSw, "RIGHT", customSw, "LEFT", -6, 0)
        srgn._lastInline = defaultSw
        -- An off glow has no color to set.
        local block = Blocker(defaultSw, classSw)
        EllesmereUI.RegisterWidgetRefresh(function()
            local o = colorOff()
            customSw:EnableMouse(not o); defaultSw:EnableMouse(not o); classSw:EnableMouse(not o)
            block:SetShown(o)
        end)
    end

    local rows = CogRows(desc)
    if colorInCog then table.insert(rows, 1, ColorRow(desc, colorOff)) end
    if #rows > 0 then
        local hasExtra = (desc.cogRows and #desc.cogRows > 0) or colorInCog
        EllesmereUI.BuildInlineCog(rgn, {
            title = "Glow Settings",
            rows = rows,
            captureRegion = rgn,
            disabled = function()
                if off() then return true end
                return not hasExtra and not GO.IsPixel(desc)
            end,
            -- Whichever lock holds, as the sentence shown: the site's own
            -- requirement, else a glow to set (rows beyond Pixel's), else Pixel Glow.
            disabledTooltip = function()
                if siteOff() then return EllesmereUI.ResolveDisabledTip(desc) end
                if hasExtra then return EllesmereUI.DisabledTooltip(NO_STYLE_TIP) end
                return EllesmereUI.DisabledTooltip("Pixel Glow")
            end,
            rawTooltip = true,
        })
    end
end

-------------------------------------------------------------------------------
--  Preview
--  An icon (or a bar for bar hosts) with the site's glow, rendered through
--  the same call the live site uses, so the preview is the live look.
-------------------------------------------------------------------------------
local PREVIEW_ICON = 136197

function GO.BuildPreview(parent, desc, opts)
    if EllesmereUI._prebuilding or not parent then return end
    opts = opts or {}
    local PP = EllesmereUI.PanelPP
    local isBar = opts.bar
    if isBar == nil then isBar = desc.host == "bar" end
    local w = opts.width or (isBar and 110 or 36)
    local h = opts.height or (isBar and 16 or 36)

    local f = CreateFrame("Frame", nil, parent)
    PP.Size(f, w, h)
    if opts.anchor then
        PP.Point(f, opts.point or "RIGHT", opts.anchor, opts.relPoint or "LEFT", opts.x or -8, opts.y or 0)
    end
    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    -- opts.icon: a texture, or a function re-read on every refresh.
    local iconFn = type(opts.icon) == "function" and opts.icon or nil
    if isBar then
        tex:SetColorTexture(0.2, 0.2, 0.2, 1)
    else
        tex:SetTexture((iconFn and iconFn()) or opts.icon or PREVIEW_ICON)
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    -- 1px black edge (below the glow overlay, which sits one level higher).
    PP.CreateBorder(f, 0, 0, 0, 1, 1, "OVERLAY", 6)

    local ov = CreateFrame("Frame", nil, f)
    ov:SetAllPoints(f)
    ov:SetFrameLevel(f:GetFrameLevel() + 2)
    ov:EnableMouse(false)
    ov._euiGlowPreview = true  -- exempt from CDM's Show Glows Only in Combat gate

    local function Refresh()
        -- Hidden: stays stopped until OnShow (a page refresh with the panel
        -- closed must not put it back into the glow driver).
        if not f:IsVisible() then return end
        if iconFn and not isBar then tex:SetTexture(iconFn() or PREVIEW_ICON) end
        if not GO.Renders(desc) then
            G.StopGlow(ov)
            f:SetAlpha(0.3)
            return
        end
        f:SetAlpha(1)
        G.StartSpecGlow(ov, GO.Spec(desc), w, h, desc.host, G.PANEL_EXTRA)
    end
    -- A hidden preview (options closed, page left or rebuilt) stops its glow,
    -- so it leaves the glow driver and a closed panel costs nothing; shown
    -- again (a cached page coming back), it restarts from the current values.
    f:SetScript("OnHide", function() G.StopGlow(ov) end)
    f:SetScript("OnShow", Refresh)
    -- Latest build only: descriptors outlive page rebuilds, a list would grow.
    desc._preview, desc._previewFrame = Refresh, f
    EllesmereUI.RegisterWidgetRefresh(Refresh)
    Refresh()
    return f, Refresh
end

-------------------------------------------------------------------------------
--  Flat key schema: <p>Color, <p>Lines, <p>Thickness, <p>Speed, <p>Background,
--  <p>BackgroundColor (colors as {r,g,b} tables). FlatGet / FlatSet cover these
--  six fields; each site keeps its own style and mode (their semantics differ).
--  defs: optional fallbacks under the same keys (a module's defaults table).
-------------------------------------------------------------------------------
local FLAT_SUFFIX = { color = "Color", lines = "Lines", thickness = "Thickness",
    speed = "Speed", bg = "Background", bgColor = "BackgroundColor" }
local _flatKeys = {}
local function FlatKey(p, f)
    local suf = FLAT_SUFFIX[f]
    if not suf then return nil end
    local keys = _flatKeys[p]
    if not keys then keys = {}; _flatKeys[p] = keys end
    local k = keys[f]
    if not k then k = p .. suf; keys[f] = k end
    return k
end

function GO.FlatGet(t, p, f, defs)
    local k = FlatKey(p, f)
    if not (k and t) then return nil end
    local v = t[k]
    if v == nil and defs then v = defs[k] end
    if f == "bg" then return v == true end
    if f == "color" or f == "bgColor" then
        if type(v) == "table" then return v.r, v.g, v.b end
        return nil
    end
    return v
end

function GO.FlatSet(t, p, f, a, b, c)
    local k = FlatKey(p, f)
    if not (k and t) then return end
    if f == "color" or f == "bgColor" then t[k] = { r = a, g = b, b = c } else t[k] = a end
end

-------------------------------------------------------------------------------
--  Descriptor for the prefix key schema (EllesmereUI.Glows.PrefixKeys): the
--  aura managers' icon glows (RF Debuff/Buff Manager, Player Aura Bars).
--  getT returns the live settings table; style is a shared index, 0 = off.
-------------------------------------------------------------------------------
function GO.PrefixSite(getT, p, host, onChange, defColor)
    local k = G.PrefixKeys(p)
    local desc = {
        host = host,
        caps = { mode = true, params = true, bg = true },
        defaultColor = defColor or { r = 1.0, g = 0.776, b = 0.376 },
        onChange = onChange,
    }
    function desc.get(f)
        local t = getT()
        if not t then return nil end
        if f == "style" then return t[k.type] or 0
        elseif f == "mode" then return G.DeriveColorMode(t[k.mode], t[k.class])
        elseif f == "color" then return t[k.r], t[k.g], t[k.b]
        elseif f == "lines" then return t[k.lines]
        elseif f == "thickness" then return t[k.th]
        elseif f == "speed" then return t[k.speed]
        elseif f == "bg" then return t[k.bg] == true
        elseif f == "bgColor" then return t[k.bgR], t[k.bgG], t[k.bgB]
        end
    end
    function desc.set(f, a, b, c)
        local t = getT()
        if not t then return end
        if f == "style" then t[k.type] = a
        elseif f == "mode" then
            -- The legacy class flag stays in step for older readers of this table.
            t[k.mode] = a
            t[k.class] = (a == "class") or nil
        elseif f == "color" then t[k.r], t[k.g], t[k.b] = a, b, c
        elseif f == "lines" then t[k.lines] = a
        elseif f == "thickness" then t[k.th] = a
        elseif f == "speed" then t[k.speed] = a
        elseif f == "bg" then t[k.bg] = a and true or nil
        elseif f == "bgColor" then t[k.bgR], t[k.bgG], t[k.bgB] = a, b, c
        end
    end
    return desc
end

-------------------------------------------------------------------------------
--  Site registry (Global Settings > Glows)
--  group "module": one descriptor per module-level setting.
--  group "bar":    a provider returning the current list of per-bar
--                  descriptors (bars are created and removed at runtime).
-------------------------------------------------------------------------------
GO.sites = {}

-- entry = { id, label, module, page, section, highlight, group, sub,
--           desc = descriptor | nil, list = function() return { {label, sub, desc, nav}, ... } end }
-- nav = { page, section, highlight, preSelect } for a list item's Open Settings;
-- sub = the group heading the row is listed under on the Glows page card;
-- info = { text = fn, tooltip, glyph = "icon"/"bar" } instead of desc/list: a hint row with Go to Settings.
function GO.RegisterSite(entry)
    for i = 1, #GO.sites do
        if GO.sites[i].id == entry.id then GO.sites[i] = entry; return end
    end
    GO.sites[#GO.sites + 1] = entry
end

-- The saved style value a template writes into a site, whether the site had
-- to take the nearest style it offers, and that style's shared index. nil for
-- a site that takes no template: a paramsOnly site (the Pixel Glow parameters
-- per-icon glows read, which the template never changes) or a style the site
-- cannot map.
function GO.TemplateValue(desc, t)
    if desc.paramsOnly then return nil, false end
    local idx, converted = GO.Resolve(desc, t.style or 1)
    return GO.FromShared(desc, idx), converted, idx
end

-- Write a template (shared-index style + color + parameters) into a site.
-- Only an active custom glow is touched, unless anyState: then an off glow is
-- turned on and an extra (Blizzard Default, Solid, Blizzard Border) replaced.
-- A locked site (GO.StyleLocked) and a paramsOnly site are never written.
-- Writes directly: a caller acting for the user routes the style through the
-- site's own confirm first (see desc.confirm). Returns applied, converted.
function GO.ApplyTemplate(desc, t, anyState)
    if not anyState and not GO.IsCustomGlow(desc) then return false, false end
    if GO.StyleLocked(desc) then return false, false end
    local v, converted, idx = GO.TemplateValue(desc, t)
    if v == nil then return false, false end
    local caps = desc.caps or {}
    desc.set("style", v)
    local tm = t.mode or "custom"
    if caps.mode then desc.set("mode", tm) end
    if tm == "custom" and t.r then desc.set("color", t.r, t.g, t.b) end
    -- Pixel parameters only go where the result is a Pixel Glow: for any other
    -- template style they are hidden in the template and would reset the site's.
    if caps.params and idx == 1 then
        desc.set("lines", t.lines or 8)
        desc.set("thickness", t.thickness or 2)
        desc.set("speed", t.speed or 4)
    end
    if caps.bg and idx == 1 then
        desc.set("bg", t.bg and true or nil)
        if t.bg then desc.set("bgColor", t.bgR or 0, t.bgG or 0, t.bgB or 0) end
    end
    return true, converted
end

-- Does the site already show what ApplyTemplate would write? An off glow or
-- an extra never does, nor a paramsOnly site (never a template target).
function GO.MatchesTemplate(desc, t)
    if desc.paramsOnly or not GO.IsCustomGlow(desc) then return false end
    local caps = desc.caps or {}
    local idx = GO.Resolve(desc, t.style or 1)
    if GO.ToShared(desc, desc.get("style")) ~= idx then return false end
    local mode = caps.mode and desc.get("mode") or "custom"
    if mode ~= (t.mode or "custom") then return false end
    if mode == "custom" and t.r then
        local r, g, b = desc.get("color")
        if r ~= t.r or g ~= t.g or b ~= t.b then return false end
    end
    if caps.params and idx == 1 then
        if (desc.get("lines") or 8) ~= (t.lines or 8) then return false end
        if (desc.get("thickness") or 2) ~= (t.thickness or 2) then return false end
        if (desc.get("speed") or 4) ~= (t.speed or 4) then return false end
    end
    if caps.bg and idx == 1 then
        if (desc.get("bg") == true) ~= (t.bg == true) then return false end
        -- ApplyTemplate writes the background color too.
        if t.bg then
            local br, bgg, bb = desc.get("bgColor")
            if (br or 0) ~= (t.bgR or 0) or (bgg or 0) ~= (t.bgG or 0) or (bb or 0) ~= (t.bgB or 0) then
                return false
            end
        end
    end
    return true
end
