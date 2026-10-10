if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  ActionBars_Options\MenuBagsRepPage_Options.lua
--  Action Bars options: the Menu, Bags & Rep Bars page (BuildMenuBagsRepPage)
--  and the data bar kit it shares with the XP Bar page (ns.ABO_DataBarKit):
--  the data bar rows and controls (Visibility, Orientation and its Vertical
--  Text cog, Width | Height, the border rows, the fill colour swatches, Bar
--  Texture, Text Size and its cog, Click Through) and the per-bar section the
--  reputation and House Favor bars use; the XP Bar page lays the same pieces
--  out its own way. Definitions only; the shared helpers come from
--  ns._ABO_OptEnv (filled by EUI_ActionBars_Options.lua).
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUIActionBars"]
if not ns then return end  -- module disabled: no options page

---------------------------------------------------------------------------
--  Data bar kit  (XP Bar and Menu, Bags & Rep Bars pages)
---------------------------------------------------------------------------

-- The data bars this client builds (WoW Forever has no House Favor bar).
local DATA_BAR_KEYS = EllesmereUI.IS_FOREVER and { "XPBar", "RepBar" }
    or { "XPBar", "RepBar", "FavorBar" }
local DATA_BAR_LABELS = { XPBar = "XP Bar", RepBar = "Reputation Bar", FavorBar = "House Favor Bar" }
-- The bars whose borders sync with each other: the rep bars. The XP bar's
-- border is its own and never syncs (a lone rep bar, on Forever, has nothing
-- to sync with).
local BORDER_SYNC_KEYS = EllesmereUI.IS_FOREVER and { "RepBar" } or { "RepBar", "FavorBar" }
local BORDER_SYNCS = {}
for _, k in ipairs(BORDER_SYNC_KEYS) do BORDER_SYNCS[k] = #BORDER_SYNC_KEYS > 1 end
local ORIENT_VALUES = { HORIZONTAL = "Horizontal", VERTICAL = "Vertical" }
local ORIENT_ORDER  = { "HORIZONTAL", "VERTICAL" }
-- Representative colors for the "Reactive (Default)" swatch.
local REACTIVE_PREVIEW = {
    XPBar    = { 0.60, 0.40, 0.85 },
    RepBar   = { 0.30, 0.70, 0.25 },
    FavorBar = { 0.85, 0.64, 0.22 },
}

-- After a change to Use Blizzard's Rep Bars or the XP Bar Style: the page
-- re-reads its values, and a change that leaves our bars wanted but never
-- built (they are built at login only while Blizzard's are off) asks for the
-- reload that creates them.
local function AfterDataBarSwitch(needsReload)
    EllesmereUI:RefreshPage()
    if needsReload then
        EllesmereUI:ShowConfirmPopup({
            title       = "Reload Required",
            message     = "Your own XP and reputation bars are created on reload.",
            confirmText = "Reload Now",
            cancelText  = "Later",
            reload      = true,
        })
    end
end

-- The kit for one page build on `parent`. Every builder takes the page's y
-- cursor and returns the new one.
local function DataBarKit(parent)
    local env = ns._ABO_OptEnv
    local ApplyVisibilityKey, EAB, GetVisibilityKey = env.ApplyVisibilityKey, env.EAB, env.GetVisibilityKey
    local ShownBorderDefaults = env.ShownBorderDefaults
    local W = EllesmereUI.Widgets
    local K = { AfterSwitch = AfterDataBarSwitch }

    local BLIZZ_DIS_TIP = "This option does not work with Blizzard Bars. Please use Blizzard Edit Mode."
    local function _blizzDis() return EAB.db.profile.useBlizzardDataBars end
    K.BLIZZ_DIS_TIP, K.BlizzDis = BLIZZ_DIS_TIP, _blizzDis

    -- Shared visibility row: left vis dropdown + right "Visibility Options" CB dropdown.
    -- trackNeverFlip: data-bar sections hide dependent rows while visibility is Never, so a
    -- Never <-> not-Never flip forces a full page rebuild (fresh closure each rebuild).
    local function BarIsNever(barKey)
        local s = EAB.db.profile.bars[barKey]
        if not s then return false end
        GetVisibilityKey(s) -- normalize legacy booleans into barVisibility
        return s.barVisibility == "never" or s.alwaysHidden == true
    end
    -- Returns the row config rather than building it, so two bars can share one
    -- row (rightVis) instead of each taking a half-empty one.
    local function VisOpts(barKey, leftLabel, disabledFn, disTip, trackNeverFlip)
        local wasNever = trackNeverFlip and BarIsNever(barKey)
        return  { getStore = function()
                  local s = EAB.db.profile.bars[barKey]
                  -- Normalize first: extra-bar defaults may carry only legacy booleans, no barVisibility key yet.
                  if s then GetVisibilityKey(s) end
                  return s
              end,
              legacyKey = "barVisibility",
              label = leftLabel,
              -- noOverrideMouseover: this module's hover wiring reads the STORED
              -- mouseoverEnabled, which an override does not write, so a Mouseover
              -- override would silently behave like Always. Offered as locked rather
              -- than looking available and doing nothing.
              caps = { partyIncludesRaid = false, luaDragonriding = true,
                       noOverrideMouseover = true },
              applyScalarFn = function(s, mode) ApplyVisibilityKey(s, mode) end,
              disabledFn = disabledFn, disabledTooltip = disTip, rawTooltip = disTip and true or nil,
              onChanged = function()
                  EAB:RefreshRuntimeVisibility()
                  EAB:RefreshMouseover()
                  EAB:ApplyCombatVisibility()
                  if trackNeverFlip and BarIsNever(barKey) ~= wasNever then
                      EllesmereUI:RefreshPage(true)
                  end
              end,
              -- Option axes recompile the secure driver through the same chain the
              -- old Visibility Options dropdown used. The gate refresh first: a lane
              -- click can be what just armed (or disarmed) the soft-target machinery,
              -- and the two calls below must see the current flags, not last click's.
              onOptionChanged = function()
                  EAB:_RefreshSoftTargetGate()
                  EAB:UpdateHousingVisibility()
                  EAB:ApplyCombatVisibility()
              end }
    end
    K.VisOpts = VisOpts

    -- Single-bar row (data bar sections): one Visibility control; rightCfg is
    -- any ordinary widget for the right slot (nil = blank). Returns the row
    -- and the new y.
    local function BuildVisRow(y, barKey, leftLabel, disabledFn, disTip, trackNeverFlip, rightCfg)
        local visRow, visH = EllesmereUI.BuildVisibilityRow(W, parent, y,
            VisOpts(barKey, leftLabel, disabledFn, disTip, trackNeverFlip), rightCfg)
        return visRow, y - visH
    end

    K.BarIsNever = BarIsNever
    -- A data bar's Visibility row with rightCfg in its right slot (nil =
    -- blank), locked under Blizzard's bars; a Never flip rebuilds the page.
    function K.VisRow(y, barKey, visLabel, rightCfg)
        return BuildVisRow(y, barKey, visLabel, _blizzDis, BLIZZ_DIS_TIP, true, rightCfg)
    end

    -- Orientation for `keys`, the data bars it flips together (the first
    -- one's setting is shown). A width or height match across the edge of
    -- those bars (one of them follows an element outside them, or another
    -- data bar built here follows one of them) locks it: a flip swaps both
    -- axes, and such a match would pull one straight back or reshape the
    -- other bar. A match between two of the bars flips with them.
    function K.OrientCfg(keys)
        local group = {}
        for _, k in ipairs(keys) do group[k] = true end
        local function OutsideSizeMatch()
            for _, k in ipairs(DATA_BAR_KEYS) do
                local t = EllesmereUI.GetWidthMatchTarget(k)
                if t and not group[k] ~= not group[t] then return k, t end
                t = EllesmereUI.GetHeightMatchTarget(k)
                if t and not group[k] ~= not group[t] then return k, t end
            end
        end
        return { type="dropdown", text="Orientation",
              values=ORIENT_VALUES, order=ORIENT_ORDER,
              disabled=function() return _blizzDis() or OutsideSizeMatch() ~= nil end,
              disabledTooltip=function()
                  if _blizzDis() then return BLIZZ_DIS_TIP end
                  local k, t = OutsideSizeMatch()
                  if not k then return nil end
                  return EllesmereUI.GetBarLabel(k) .. ": "
                      .. EllesmereUI.Lf("Size matched to %1$s. Unmatch in Unlock Mode to edit.", EllesmereUI.GetBarLabel(t))
              end,
              rawTooltip=true,
              getValue=function()
                  local b = EAB.db.profile.bars[keys[1]]
                  return b and b.orientation or "HORIZONTAL"
              end,
              setValue=function(v)
                  -- Every bar of the group takes the orientation, one not built
                  -- on this client included, so they keep one shared value in a
                  -- profile carried to another client. A flip swaps a bar's
                  -- width and height while its shape suits the old orientation,
                  -- so it keeps its length and thickness (400 x 18 horizontal
                  -- becomes 18 x 400 vertical); a bar already shaped for the new
                  -- one keeps its size. Every bar is written before any is laid
                  -- out, so a size match between two of them reads the new sizes
                  -- when the first one resizes.
                  local bars = EAB.db.profile.bars
                  for _, k in ipairs(keys) do
                      local b = bars[k]
                      if b then
                          local bw, bh = b.width or 400, b.height or 18
                          if (b.orientation or "HORIZONTAL") ~= v and (v == "VERTICAL") == (bw > bh) then
                              b.width, b.height = bh, bw
                          end
                          b.orientation = v
                      end
                  end
                  for _, k in ipairs(keys) do
                      if bars[k] then ns.ApplyDataBarLayout(k) end
                  end
                  -- Rebuild: the Width and Height sliders take their ranges from
                  -- the orientation when they are built.
                  EllesmereUI:RefreshPage(true)
              end }
    end

    -- The Vertical Text cog on an Orientation control (locked unless
    -- Vertical): runs the bar text (and, with dividers, the divider labels)
    -- along the bar. Each setting goes to every bar of `keys`, as the
    -- orientation does.
    function K.OrientCog(region, keys, dividers)
        if EllesmereUI._prebuilding then return end
        local lead = keys[1]
        local function Flag(key)
            local b = EAB.db.profile.bars[lead]
            return b and b[key] and true or false
        end
        local function SetFlag(key, v)
            for _, k in ipairs(keys) do
                local b = EAB.db.profile.bars[k]
                if b then
                    b[key] = v
                    ns.ApplyDataBarLayout(k)
                end
            end
        end
        local rows = {
            { type="toggle", label="Rotate Bar Text",
              tooltip="Runs the bar text along the bar.",
              get=function() return Flag("rotateText") end,
              set=function(v) SetFlag("rotateText", v) end },
        }
        if dividers then
            rows[#rows + 1] = { type="toggle", label="Rotate Divider Labels",
              tooltip="Runs the divider percentages along the bar.",
              get=function() return Flag("rotateDividerText") end,
              set=function(v) SetFlag("rotateDividerText", v) end }
        end
        rows[#rows + 1] = { type="toggle", label="Read Downward",
              tooltip="Rotated text reads from top to bottom.",
              disabled=function()
                  return not (Flag("rotateText") or (dividers and Flag("rotateDividerText")))
              end,
              disabledTooltip=dividers and "This option requires Rotate Bar Text or Rotate Divider Labels."
                  or "This option requires Rotate Bar Text.",
              rawTooltip=true,
              get=function() return Flag("textReadDown") end,
              set=function(v) SetFlag("textReadDown", v) end }
        EllesmereUI.BuildInlineCog(region, {
            title = "Vertical Text",
            anchorTo = region._control,
            disabled = function()
                if _blizzDis() then return true end
                local b = EAB.db.profile.bars[lead]
                return not (b and b.orientation == "VERTICAL")
            end,
            disabledTooltip = function()
                if _blizzDis() then return BLIZZ_DIS_TIP end
                return "This option requires the Vertical orientation."
            end,
            rawTooltip = true,
            rows = rows,
        })
    end

    -- A style row: leftCfg | Orientation for `keys` with its Vertical Text
    -- cog (dividers: the bars draw dividers, so the cog also offers Rotate
    -- Divider Labels).
    function K.StyleRow(y, leftCfg, keys, dividers)
        local row, h = W:DualRow(parent, y, leftCfg, K.OrientCfg(keys))
        K.OrientCog(row._rightRegion, keys, dividers)
        return y - h
    end

    -- Shared bar-texture dropdown tables (built-ins + SharedMedia) with menu preview backgrounds, same treatment as the nameplate Bar Texture dropdown.
    local dbTexValues, dbTexOrder = {}, {}
    do
        local names = ns.dataBarTextureNames or {}
        local lookup = ns.dataBarTextures or {}
        for _, key in ipairs(ns.dataBarTextureOrder or {}) do
            if key ~= "---" then dbTexValues[key] = names[key] or key end
            dbTexOrder[#dbTexOrder + 1] = key
        end
        dbTexValues._menuOpts = {
            itemHeight = 28,
            background = function(key)
                if not key or key == "---" or key == "none" then return nil end
                if EllesmereUI.ResolveTexturePath then
                    return EllesmereUI.ResolveTexturePath(lookup, key, nil)
                end
                return lookup[key]
            end,
        }
    end
    local function RefreshDataBar(bk)
        local f = ns.dataBarFrames and ns.dataBarFrames[bk]
        if f and f._updateFunc then f._updateFunc() end
    end

    -- Custom Border (each data-bar section's opt-in). Its two sync links copy
    -- between the built rep bars (BORDER_SYNC_KEYS) only. The style link
    -- carries the style, its offsets, shifts and Show Behind plus the colour
    -- a style pick seeds; the size link carries the size and the colour. Both
    -- turn the target's Custom Border on, so a target never holds values it
    -- does not draw.
    local function DataBarTextured(s)
        local t = s.borderTexture or "solid"
        return t ~= "" and t ~= "solid"
    end
    local function CopyDataBarColor(dst, src)
        local c = src.borderColor
        if c then dst.borderColor = { r = c.r, g = c.g, b = c.b, a = c.a } end
    end
    local function CopyDataBarStyle(dst, src)
        dst.customBorder = true
        dst.borderTexture = src.borderTexture
        dst.borderTextureOffset, dst.borderTextureOffsetY = src.borderTextureOffset, src.borderTextureOffsetY
        dst.borderTextureShiftX, dst.borderTextureShiftY = src.borderTextureShiftX, src.borderTextureShiftY
        dst.borderBehind = src.borderBehind
        CopyDataBarColor(dst, src)
    end
    local function CopyDataBarSize(dst, src)
        dst.customBorder = true
        dst.borderThickness = src.borderThickness
        local v = src.borderThicknessPx
        if v == nil and dst.borderThicknessPx ~= nil then v = false end   -- false travels, nil would not
        dst.borderThicknessPx = v
        CopyDataBarColor(dst, src)
    end
    local function SameDataBarStyle(t, s)
        return t.customBorder == true
            and (t.borderTexture or "solid") == (s.borderTexture or "solid")
            and t.borderTextureOffset == s.borderTextureOffset
            and t.borderTextureOffsetY == s.borderTextureOffsetY
            and t.borderTextureShiftX == s.borderTextureShiftX
            and t.borderTextureShiftY == s.borderTextureShiftY
            and (t.borderBehind or false) == (s.borderBehind or false)
    end
    local function SameDataBarSize(t, s)
        if t.customBorder ~= true then return false end
        if (t.borderThickness or "thin") ~= (s.borderThickness or "thin") then return false end
        if (t.borderThicknessPx or false) ~= (s.borderThicknessPx or false) then return false end   -- nil and false render alike
        local a, b = t.borderColor, s.borderColor
        return (a and a.r or 0) == (b and b.r or 0) and (a and a.g or 0) == (b and b.g or 0)
            and (a and a.b or 0) == (b and b.b or 0) and (a and a.a or 1) == (b and b.a or 1)
    end
    -- One "Apply to: All | Multiple" link on a Custom Border row half. A target
    -- whose Custom Border was off gains rows, and one that moves between Solid
    -- and a textured style gains or loses its offset row, so those rebuild the
    -- page.
    local function DataBarSyncIcon(region, srcKey, tooltip, copyFn, sameFn)
        local function ApplyTo(keys)
            local src = EAB.db.profile.bars[srcKey]
            local reveal = false
            for _, k in ipairs(keys) do
                local dst = EAB.db.profile.bars[k]
                if dst and dst ~= src then
                    if dst.customBorder ~= true then reveal = true end
                    local wasTex = DataBarTextured(dst)
                    copyFn(dst, src)
                    if DataBarTextured(dst) ~= wasTex then reveal = true end
                    ns.ApplyDataBarLayout(k)
                end
            end
            EllesmereUI:RefreshPage(reveal)
        end
        EllesmereUI.BuildSyncIcon({
            region = region,
            tooltip = tooltip,
            onClick = function() ApplyTo(BORDER_SYNC_KEYS) end,
            isSynced = function()
                local src = EAB.db.profile.bars[srcKey]
                for _, k in ipairs(BORDER_SYNC_KEYS) do
                    local t = EAB.db.profile.bars[k]
                    if t and not sameFn(t, src) then return false end
                end
                return true
            end,
            flashTargets = function() return { region } end,
            multiApply = {
                elementKeys = BORDER_SYNC_KEYS,
                elementLabels = DATA_BAR_LABELS,
                getCurrentKey = function() return srcKey end,
                onApply = ApplyTo,
            },
        })
    end

    -- One bar's border rows: Border Style | Border Size (with the colour, the
    -- Border Options cog and, on a rep bar, the two sync links), then Width
    -- Offset | Height Offset for a textured style. implicit (the XP Bar page,
    -- which has no Custom Border toggle): until the bar's Custom Border is on,
    -- the rows show the plain line it draws (Solid, 1px, black) and the first
    -- edit turns it on from those values, dropping what a border once turned
    -- off left behind.
    local NO_BORDER = {}
    function K.BorderRows(y, barKey, implicit)
        local _, h
        local function S() return EAB.db.profile.bars[barKey] end
        local function V()
            local s = S()
            if implicit and s.customBorder ~= true then return NO_BORDER end
            return s
        end
        local turnedOn = false
        local function Wr()
            local s = S()
            if implicit and s.customBorder ~= true then
                s.borderTexture, s.borderThickness, s.borderThicknessPx = nil, nil, nil
                s.borderColor, s.borderBehind = nil, nil
                s.borderTextureOffset, s.borderTextureOffsetY = nil, nil
                s.borderTextureShiftX, s.borderTextureShiftY = nil, nil
                s.customBorder = true
                turnedOn = true
            end
            return s
        end
        -- After a write: lay the bar out and refresh the page, or rebuild it
        -- when that write turned the border on (its sync links appear).
        local function Done()
            ns.ApplyDataBarLayout(barKey)
            if turnedOn then
                turnedOn = false
                EllesmereUI:RefreshPage(true)
            else
                EllesmereUI:RefreshPage()
            end
        end
        local texValues, texOrder = EllesmereUI.GetBorderTextureDropdown()
        local function Textured() return DataBarTextured(V()) end
        local function BorderOff() return (ns.ResolveBorderThickness(V())) <= 0 end
        local brdRow
        brdRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Border Style",
              disabled=_blizzDis, disabledTooltip=BLIZZ_DIS_TIP, rawTooltip=true,
              values=texValues, order=texOrder,
              getValue=function() return V().borderTexture or "solid" end,
              -- The offset row exists only for a textured style, so only a
              -- Solid <-> textured flip rebuilds the page.
              setValue=EllesmereUI.DependentSetValue(Textured, function(v)
                  local s = Wr()
                  local defTh = EllesmereUI.GetBorderDefaultSize("actionbars", v)
                  -- An unregistered SharedMedia border answers the NUMBER 1; this key stores labels.
                  if type(defTh) == "number" then defTh = EllesmereUI.BORDER_LABEL_OF_STEP[defTh] or "thin" end
                  local col, behind = EllesmereUI.GetBorderStyleSelectDefaults(v)
                  s.borderTexture = v
                  s.borderTextureOffset, s.borderTextureOffsetY = nil, nil
                  s.borderTextureShiftX, s.borderTextureShiftY = nil, nil
                  -- A style pick resets the size: a set exact size goes with it (false travels, nil would not).
                  if s.borderThicknessPx then s.borderThicknessPx = false end
                  s.borderColor = { r = col.r, g = col.g, b = col.b, a = 1 }
                  s.borderBehind = behind
                  if defTh then s.borderThickness = defTh end
                  Done()
              end) },
            EllesmereUI.BorderPxSliderCfg{ text="Border Size",
              disabled=_blizzDis, disabledTooltip=BLIZZ_DIS_TIP, rawTooltip=true,
              -- The step the bar renders with (ResolveBorderThickness): an
              -- unknown thickness is thin.
              getStep=function()
                  local entry = ns.BORDER_THICKNESS[V().borderThickness or "thin"] or ns.BORDER_THICKNESS.thin
                  return entry.regular
              end,
              setStep=function(step) Wr().borderThickness = EllesmereUI.BORDER_LABEL_OF_STEP[step] end,
              getTex=function() return V().borderTexture or "solid" end,
              getPx=function() return V().borderThicknessPx end,
              setPx=function(v) Wr().borderThicknessPx = v end,
              apply=Done });  y = y - h

        -- Width Offset | Height Offset: the textured border's outward offsets
        -- (Solid has none). Shown = the override, else the "actionbars"
        -- registry default for the step and thickness key the bar renders
        -- with, scaled to an exact size as drawn.
        if Textured() then
            local ocfgL, ocfgR = EllesmereUI.BorderOffsetRowCfgs{
                addonKey="actionbars",
                tooltip="How far the border reaches past the bar.",
                disabled=_blizzDis, disabledTooltip=BLIZZ_DIS_TIP, rawTooltip=true,
                getTex=function() return V().borderTexture or "solid" end,
                getStep=function() return (ns.ResolveBorderThickness(V())) end,
                getSizeKey=function() return V().borderThickness or "thin" end,
                getPx=function() return V().borderThicknessPx end,
                getX=function() return V().borderTextureOffset end,
                setX=function(v) Wr().borderTextureOffset = v end,
                getY=function() return V().borderTextureOffsetY end,
                setY=function(v) Wr().borderTextureOffsetY = v end,
                apply=Done }
            _, h = W:DualRow(parent, y, ocfgL, ocfgR);  y = y - h
        end

        -- Row chrome (frames: never on the search pre-build's absorber rows).
        if not EllesmereUI._prebuilding then
            -- Border Options cog (Shift X / Shift Y / Show Behind): textured
            -- styles only, hidden (not dimmed) for Solid and under Blizzard bars.
            local lRgn = brdRow._leftRegion
            local function ShownDefaults()
                local s = V()
                local step, px = ns.ResolveBorderThickness(s)
                return ShownBorderDefaults(s.borderTexture or "solid", s.borderThickness or "thin", step, px)
            end
            -- Landing on the shift the slider shows by default stores nil
            -- (follow the style again); any other value is an override.
            local function SetShift(key, v, def)
                if v == math.floor(def + 0.5) then v = nil end
                Wr()[key] = v
                Done()
            end
            local cogBtn = EllesmereUI.BuildInlineCog(lRgn, {
                icon = EllesmereUI.DIRECTIONS_ICON, anchorTo = lRgn._control,
                title = "Border Options",
                tip = "Fine-tunes the textured border's position and draws it under the bar fill when Show Behind is on.",
                captureRegion = lRgn,
                rows = {
                    { type="slider", label="Shift X", min=-10, max=10, step=1,
                      get=function()
                          local v = V().borderTextureShiftX
                          if v ~= nil then return v end
                          local _, _, dsx = ShownDefaults()
                          return dsx
                      end,
                      set=function(v)
                          local _, _, dsx = ShownDefaults()
                          SetShift("borderTextureShiftX", v, dsx)
                      end },
                    { type="slider", label="Shift Y", min=-10, max=10, step=1,
                      get=function()
                          local v = V().borderTextureShiftY
                          if v ~= nil then return v end
                          local _, _, _, dsy = ShownDefaults()
                          return dsy
                      end,
                      set=function(v)
                          local _, _, _, dsy = ShownDefaults()
                          SetShift("borderTextureShiftY", v, dsy)
                      end },
                    { type="toggle", label="Show Behind",
                      get=function() return V().borderBehind or false end,
                      set=function(v)
                          Wr().borderBehind = v and true or false
                          Done()
                      end },
                },
            })
            if cogBtn then
                local function UpdateCogVis()
                    cogBtn:SetShown(Textured() and not _blizzDis())
                end
                EllesmereUI.RegisterWidgetRefresh(UpdateCogVis)
                UpdateCogVis()
            end

            -- Border color with alpha, left of the Border Size slider.
            EllesmereUI.BuildInlineSwatches(brdRow._rightRegion, {
                { tooltip = "Border Color", hasAlpha = true,
                  getValue = function()
                      local c = V().borderColor
                      if c then return c.r or 0, c.g or 0, c.b or 0, c.a or 1 end
                      return 0, 0, 0, 1
                  end,
                  setValue = function(r, g, b, a)
                      Wr().borderColor = { r = r, g = g, b = b, a = a or 1 }
                      Done()
                  end },
            }, {
                size = 20,
                disabled = function() return _blizzDis() or BorderOff() end,
                disabledTooltip = function()
                    if _blizzDis() then return BLIZZ_DIS_TIP end
                    return "This option requires a Border Size above 0."
                end,
                rawTooltip = true,
            })

            if S().customBorder == true and BORDER_SYNCS[barKey] then
                DataBarSyncIcon(lRgn, barKey, "Apply Border Style to all Rep Bars",
                    CopyDataBarStyle, SameDataBarStyle)
                DataBarSyncIcon(brdRow._rightRegion, barKey, "Apply Border Size and Color to all Rep Bars",
                    CopyDataBarSize, SameDataBarSize)
            end
        end
        return y
    end

    -- Width | Height. The ranges follow the orientation (a flip rebuilds the
    -- page): the bar's length runs up to the screen's width (Width,
    -- horizontal) or height (Height, vertical), its thickness up to 100. A
    -- size set outside them elsewhere (Unlock Mode, a size match) shows at the
    -- nearest end of its slider.
    function K.SizeRow(y, barKey)
        local _, h
        local function S() return EAB.db.profile.bars[barKey] end
        local wDis, wTip, wRaw = EllesmereUI.MatchGuard(barKey, "Width", _blizzDis, BLIZZ_DIS_TIP)
        local hDis, hTip, hRaw = EllesmereUI.MatchGuard(barKey, "Height", _blizzDis, BLIZZ_DIS_TIP)
        local _dbVert = (S().orientation == "VERTICAL")
        local _dbLenMax = math.floor(_dbVert and UIParent:GetHeight() or UIParent:GetWidth())
        local _dbWMin, _dbWMax = (_dbVert and 4 or 50), (_dbVert and 100 or _dbLenMax)
        local _dbHMin, _dbHMax = (_dbVert and 50 or 4), (_dbVert and _dbLenMax or 100)
        _, h = W:DualRow(parent, y,
            { type="slider", text="Width", min=_dbWMin, max=_dbWMax, step=1,
              disabled=wDis, disabledTooltip=wTip, rawTooltip=wRaw,
              getValue=function() return S().width or 400 end,
              setValue=function(v)
                  S().width = v
                  ns.ApplyDataBarLayout(barKey)
              end },
            { type="slider", text="Height", min=_dbHMin, max=_dbHMax, step=1,
              disabled=hDis, disabledTooltip=hTip, rawTooltip=hRaw,
              getValue=function() return S().height or 18 end,
              setValue=function(v)
                  S().height = v
                  ns.ApplyDataBarLayout(barKey)
              end });  y = y - h
        return y
    end

    -- The fill colour swatches of a bar's Color control: Custom, Accent and
    -- Reactive (Default), the active one bright (multiSwatch or inline).
    function K.ColorSwatches(barKey)
        local function S() return EAB.db.profile.bars[barKey] end
        local rp = REACTIVE_PREVIEW[barKey] or { 1, 1, 1 }
        return {
                  { tooltip = "Custom Color",
                    getValue = function()
                        local c = S().customColor
                        if c then return c.r or 1, c.g or 1, c.b or 1 end
                        return 1, 1, 1
                    end,
                    setValue = function(r, g, b)
                        S().customColor = { r = r, g = g, b = b }
                        S().colorMode = "custom"
                        RefreshDataBar(barKey)
                    end,
                    onClick = function(self)
                        if S().colorMode ~= "custom" then
                            S().colorMode = "custom"
                            RefreshDataBar(barKey)
                            EllesmereUI:RefreshPage()
                            return
                        end
                        if self._eabOrigClick then self._eabOrigClick(self) end
                    end,
                    refreshAlpha = function()
                        return S().colorMode == "custom" and 1 or 0.3
                    end },
                  { tooltip = "Accent Color",
                    getValue = function()
                        local EG = EllesmereUI.ELLESMERE_GREEN
                        if EG then return EG.r or 0.047, EG.g or 0.824, EG.b or 0.616 end
                        return 0.047, 0.824, 0.616
                    end,
                    setValue = function() end,
                    onClick = function()
                        S().colorMode = "accent"
                        RefreshDataBar(barKey)
                        EllesmereUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        return S().colorMode == "accent" and 1 or 0.3
                    end },
                  { tooltip = "Reactive (Default)",
                    getValue = function() return rp[1], rp[2], rp[3] end,
                    setValue = function() end,
                    onClick = function()
                        S().colorMode = nil
                        RefreshDataBar(barKey)
                        EllesmereUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        local m = S().colorMode
                        return (m ~= "custom" and m ~= "accent") and 1 or 0.3
                    end },
        }
    end

    function K.TexCfg(barKey)
        local function S() return EAB.db.profile.bars[barKey] end
        return { type="dropdown", text="Bar Texture", values=dbTexValues, order=dbTexOrder,
              disabled=_blizzDis, disabledTooltip=BLIZZ_DIS_TIP, rawTooltip=true,
              getValue=function() return S().barTexture or "none" end,
              setValue=function(v)
                  S().barTexture = v
                  ns.ApplyDataBarLayout(barKey)
              end }
    end

    function K.ClickThroughCfg(barKey)
        local function S() return EAB.db.profile.bars[barKey] end
        return { type="toggle", text="Click Through",
              getValue=function() return S().clickThrough end,
              setValue=function(v)
                  S().clickThrough = v
                  EAB:ApplyClickThroughForBar(barKey)
              end }
    end
    -- The same toggle as a cog row (the XP bar's Visibility cog).
    function K.ClickThroughRow(barKey)
        local cfg = K.ClickThroughCfg(barKey)
        return { type="toggle", label=cfg.text, get=cfg.getValue, set=cfg.setValue }
    end

    function K.TextSizeCfg(barKey)
        local function S() return EAB.db.profile.bars[barKey] end
        return { type="slider", text="Text Size", min=6, max=24, step=1,
              disabled=_blizzDis, disabledTooltip=BLIZZ_DIS_TIP, rawTooltip=true,
              getValue=function() return S().textSize or 9 end,
              setValue=function(v)
                  S().textSize = v
                  ns.ApplyDataBarLayout(barKey)
              end }
    end

    -- The Bar Text Offsets cog on a Text Size control: the anchor and
    -- offsets, then extraRows (the XP bar text's Show Rested).
    function K.TextCog(region, barKey, extraRows)
        if EllesmereUI._prebuilding then return end
        local function S() return EAB.db.profile.bars[barKey] end
        local textRows = {
                { type="dropdown", label="Anchor",
                  tooltip="Where the bar text sits inside the bar; the offsets nudge it from there.",
                  values = { center="Center", top="Top", bottom="Bottom", left="Left", right="Right" },
                  order = { "center", "top", "bottom", "left", "right" },
                  get=function() return S().textAnchor or "center" end,
                  set=function(v) S().textAnchor = v; ns.ApplyDataBarLayout(barKey) end },
                { type="slider", label="X Offset", min=-150, max=150, step=1,
                  get=function() return S().textOffsetX or 0 end,
                  set=function(v)
                      S().textOffsetX = v
                      ns.ApplyDataBarLayout(barKey)
                  end },
                { type="slider", label="Y Offset", min=-150, max=150, step=1,
                  get=function() return S().textOffsetY or 0 end,
                  set=function(v)
                      S().textOffsetY = v
                      ns.ApplyDataBarLayout(barKey)
                  end },
        }
        if extraRows then
            for _, r in ipairs(extraRows) do textRows[#textRows + 1] = r end
        end
        EllesmereUI.BuildInlineCog(region, { icon = EllesmereUI.DIRECTIONS_ICON, anchorTo = region._control,
            title = "Bar Text Offsets",
            disabled = _blizzDis, disabledTooltip = BLIZZ_DIS_TIP, rawTooltip = true,
            rows = textRows,
        })
    end

    -- One data bar's section (the Menu, Bags & Rep Bars page): lead's rows
    -- (optional, lead(y) -> y; built even while Never), Visibility | Custom
    -- Border, its border rows while on, Width | Height, Color | Bar Texture,
    -- Click Through | Text Size. While Never only the rows up to Visibility
    -- are built. Returns the new y and the Visibility row.
    function K.Section(y, barKey, sectionTitle, visLabel, lead)
        local _, h
        local function S() return EAB.db.profile.bars[barKey] end

        _, h = W:SectionHeader(parent, sectionTitle, y);  y = y - h
        if lead then y = lead(y) end
        -- Custom Border, the opt-in for this bar's own border style, size and
        -- color, fills the Visibility row's free slot. Its rows below are built
        -- only while it is on (the toggle rebuilds the page). Left out while
        -- Never, so that section keeps its lone Visibility row.
        local customCfg
        if not BarIsNever(barKey) then
            customCfg = { type="toggle", text="Custom Border",
              tooltip="Draws this bar's border in your own border style, size and color instead of the thin black line.",
              disabled=_blizzDis, disabledTooltip=BLIZZ_DIS_TIP, rawTooltip=true,
              getValue=function() return S().customBorder or false end,
              setValue=EllesmereUI.SectionToggleSetValue(function(v)
                  S().customBorder = v and true or false
                  ns.ApplyDataBarLayout(barKey)
              end) }
        end
        local visRow
        visRow, y = K.VisRow(y, barKey, visLabel, customCfg)
        if BarIsNever(barKey) then return y, visRow end

        if S().customBorder then y = K.BorderRows(y, barKey) end
        y = K.SizeRow(y, barKey)
        _, h = W:DualRow(parent, y,
            { type="multiSwatch", text="Color", swatches = K.ColorSwatches(barKey) },
            K.TexCfg(barKey));  y = y - h
        local textRow
        textRow, h = W:DualRow(parent, y, K.ClickThroughCfg(barKey), K.TextSizeCfg(barKey));  y = y - h
        K.TextCog(textRow._rightRegion, barKey)
        return y, visRow
    end
    return K
end

-- Used by XPBarPage_Options.lua (at page build)
ns.ABO_DataBarKit = DataBarKit

---------------------------------------------------------------------------
--  Menu, Bags & Rep Bars page  (dedicated tab)
---------------------------------------------------------------------------

local function BuildMenuBagsRepPage(pageName, parent, yOffset)
    local env = ns._ABO_OptEnv
    local EAB, EndCapsCtl = env.EAB, env.EndCapsCtl
    local W = EllesmereUI.Widgets
    local K = DataBarKit(parent)
    local VisOpts = K.VisOpts
    local y = yOffset
    local _, h

    -- Global settings page, no bar selector header
    EllesmereUI:ClearContentHeader()
    parent._showRowDivider = true

    -------------------------------------------------------------------
    --  MICRO MENU & BAGS
    -------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "MICRO MENU & BAGS", y);  y = y - h
    -- Both bars' Visibility in ONE row: same kind of control, and pairing them
    -- leaves no half-empty slot behind now that Visibility Options is folded in.
    do
        local microOpts = VisOpts("MicroBar", "Micro Menu Visibility")
        microOpts.rightVis = VisOpts("BagBar", "Bag Bar Visibility")
        _, h = EllesmereUI.BuildVisibilityRow(W, parent, y, microOpts);  y = y - h
    end
    -- Their skins: the Blizzard Skins+ Micro Menu and Bag Bar cards' style,
    -- mirrored (one setting; none while that module is off, and no Bag Bar
    -- skin off WoW Forever). Then their end caps, as an action bar's (sized
    -- from Action Bar 1's buttons; no Apply to All link: a first-install span
    -- makes the two differ on purpose). Without the Bag Bar skin the slots
    -- fill in order, so no blank is left mid-section.
    do
        local SkinCfg = EllesmereUI.WindowSkinStyleCfg
        local microSkin = SkinCfg and SkinCfg("micromenu", "Micro Menu Skin",
            "Same setting as the Micro Menu card on Blizzard Skins+ > Window Skins.")
        local bagSkin = SkinCfg and SkinCfg("bagbar", "Bag Bar Skin",
            "Same setting as the Bag Bar card on Blizzard Skins+ > Window Skins.")
        local function Ctl(key, label)
            return EndCapsCtl({
                key = function() return key end,
                store = function() return EAB.db.profile.bars[key] end,
                label = label,
                vertical = function() return ns.AB_ExtraCapsVertical(key) end,
                write = function(k, v)
                    if k then EAB.db.profile.bars[key][k] = v end
                    ns.AB_ExtraCaps(key)
                    EllesmereUI:RefreshPage()
                end,
            })
        end
        local mc, bc = Ctl("MicroBar", "Micro Menu End Caps"), Ctl("BagBar", "Bag Bar End Caps")
        local row
        if microSkin and bagSkin then
            _, h = W:DualRow(parent, y, microSkin, bagSkin);  y = y - h
        end
        if microSkin and not bagSkin then
            row, h = W:DualRow(parent, y, microSkin, mc.Cfg());  y = y - h
            mc.Build(row._rightRegion)
            row, h = W:DualRow(parent, y, bc.Cfg(), EllesmereUI.BlankRowCfg());  y = y - h
            bc.Build(row._leftRegion)
        else
            row, h = W:DualRow(parent, y, mc.Cfg(), bc.Cfg());  y = y - h
            mc.Build(row._leftRegion)
            bc.Build(row._rightRegion)
        end
    end

    _, h = W:Spacer(parent, y, 12);  y = y - h

    -------------------------------------------------------------------
    --  REPUTATION BAR / HOUSE FAVOR BAR
    -------------------------------------------------------------------
    -- The Reputation Bar section opens with Use Blizzard's Rep Bars, the one
    -- saved switch for Blizzard's XP, reputation and House Favor bars (shared
    -- with the XP Bar page's Style, its Blizz Default) | Orientation, which
    -- flips the reputation and House Favor bars together.
    y = K.Section(y, "RepBar", "REPUTATION BAR", "Rep Bar Visibility", function(ry)
        return K.StyleRow(ry,
            { type="toggle", text="Use Blizzard's Rep Bars",
              tooltip="Tied to the XP bar: Blizzard's XP and reputation bars switch together, so this also sets the XP Bar style to Blizz Default.",
              getValue=function() return EAB.db.profile.useBlizzardDataBars end,
              setValue=function(v) K.AfterSwitch(ns.SetUseBlizzardDataBars(v)) end },
            { "RepBar", "FavorBar" })
    end)
    if not EllesmereUI.IS_FOREVER then
    _, h = W:Spacer(parent, y, 12);  y = y - h
    y = K.Section(y, "FavorBar", "HOUSE FAVOR BAR", "Favor Bar Visibility")
    end -- not IS_FOREVER

    _, h = W:Spacer(parent, y, 12);  y = y - h

    -------------------------------------------------------------------
    --  VEHICLE BAR
    -------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "VEHICLE BAR", y);  y = y - h

    _, h = W:DualRow(parent, y,
        { type="toggle", text="Hide Blizzard's Vehicle Bar",
          getValue=function() return EAB.db.profile.hideBlizzardVehicleBar end,
          setValue=function(v)
              EAB.db.profile.hideBlizzardVehicleBar = v
              if EAB.UpdateVehicleBarWatch then EAB:UpdateVehicleBarWatch() end
              EllesmereUI:RefreshPage()
          end,
          tooltip="Hide Blizzard's stock vehicle and override bar." },
        { type="label", text="" });  y = y - h

    return math.abs(y)
end

-- Used by EUI_ActionBars_Options.lua
ns.ABO_BuildMenuBagsRepPage = BuildMenuBagsRepPage
