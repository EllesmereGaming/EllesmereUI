if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  ActionBars_Options\XPBarPage_Options.lua
--  Action Bars options: the XP Bar page (BuildXPBarPage), in CORE, DISPLAY
--  and EXTRAS sections. The data bar controls it shares with the reputation
--  and House Favor bars come from the data bar kit (ns.ABO_DataBarKit,
--  defined in MenuBagsRepPage_Options.lua and read at build time); this file
--  holds the XP bar's own: Style, Show Dividers and its settings row, Fill
--  Style, Rested Color, Background Opacity, Text Background, Show % and the
--  XP Bar Visibility cog. Definitions only; the shared helpers come from
--  ns._ABO_OptEnv (filled by EUI_ActionBars_Options.lua).
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUIActionBars"]
if not ns then return end  -- module disabled: no options page

local XP = "XPBar"

-- The profession skill-bar flipbooks Fill Style can offer (atlas, label).
local FLIP_CANDS = {
    { "Skillbar_Fill_Flipbook_Alchemy",        "Alchemy" },
    { "Skillbar_Fill_Flipbook_Blacksmithing",  "Blacksmithing" },
    { "Skillbar_Fill_Flipbook_Enchanting",     "Enchanting" },
    { "Skillbar_Fill_Flipbook_Engineering",    "Engineering" },
    { "Skillbar_Fill_Flipbook_Herbalism",      "Herbalism" },
    { "Skillbar_Fill_Flipbook_Inscription",    "Inscription" },
    { "Skillbar_Fill_Flipbook_Jewelcrafting",  "Jewelcrafting" },
    { "Skillbar_Fill_Flipbook_Leatherworking", "Leatherworking" },
    { "Skillbar_Fill_Flipbook_Mining",         "Mining" },
    { "Skillbar_Fill_Flipbook_Skinning",       "Skinning" },
    { "Skillbar_Fill_Flipbook_Tailoring",      "Tailoring" },
    { "Skillbar_Fill_Flipbook_Cooking",        "Cooking" },
    { "Skillbar_Fill_Flipbook_Fishing",        "Fishing" },
}

---------------------------------------------------------------------------
--  XP Bar page  (dedicated tab)
--    CORE     Visibility | Orientation, Width | Height, Style | Show Dividers
--             (and 5% Line Style | Divider Text while dividers are on)
--    DISPLAY  Border Style | Border Size (and the offsets of a textured
--             style), Fill Style | Rested Color, Background Opacity | Bar
--             Texture, Text Size | Text Background
--    EXTRAS   Click Through
--  While the bar's visibility is Never only the first row is built.
---------------------------------------------------------------------------

local function BuildXPBarPage(pageName, parent, yOffset)
    local EAB = ns._ABO_OptEnv.EAB
    local W = EllesmereUI.Widgets
    local K = ns.ABO_DataBarKit(parent)
    local BLIZZ_DIS_TIP, _blizzDis = K.BLIZZ_DIS_TIP, K.BlizzDis
    local function S() return EAB.db.profile.bars[XP] end
    local function Vertical() return S().orientation == "VERTICAL" end
    -- Row chrome (frames: never on the search pre-build's absorber rows).
    local chrome = not EllesmereUI._prebuilding
    local y = yOffset
    local _, h

    -- Global settings page, no bar selector header
    EllesmereUI:ClearContentHeader()
    parent._showRowDivider = true

    -------------------------------------------------------------------
    --  CORE
    -------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "CORE", y);  y = y - h

    -- Visibility (its cog: the text's raw values and level) | Orientation
    -- (its cog: Vertical Text).
    local visRow
    visRow, y = K.VisRow(y, XP, "XP Bar Visibility", K.OrientCfg({ XP }))
    K.OrientCog(visRow._rightRegion, { XP }, true)
    if chrome then
        local rgn = visRow._leftRegion
        EllesmereUI.BuildInlineCog(rgn, {
            title = "XP Bar Visibility",
            anchorTo = rgn._control,
            rows = {
                { type="toggle", label="Show Raw Values",
                  get=function() return S().showRawValues end,
                  set=function(v) S().showRawValues = v end },
                { type="toggle", label="Show Level",
                  get=function() return S().showLevel end,
                  set=function(v) S().showLevel = v end },
            },
        })
    end
    -- Rows below are hidden while visibility is Never (a Never flip rebuilds).
    if K.BarIsNever(XP) then return math.abs(y) end

    y = K.SizeRow(y, XP)

    -- Style: the EllesmereUI bar, plain, in the profession frame art or in WoW
    -- Forever's border (Forever: the chat and Damage Meters border, offered
    -- only on that client), or Blizzard's own bar. Blizz Default is the one
    -- saved switch for Blizzard's XP, reputation and House Favor bars, shared
    -- with Use Blizzard's Rep Bars (Menu, Bags & Rep Bars).
    local styleValues = { eui = "EllesmereUI", prof = "Professions", default = "Blizz Default" }
    local styleOrder = { "eui", "prof" }
    if EllesmereUI._XPBarArtAvailable("forever") then
        styleValues.forever = "Forever"
        styleOrder[#styleOrder + 1] = "forever"
    end
    styleOrder[#styleOrder + 1] = "default"
    -- Show Dividers (its 5% and 10% colours inline); its settings row below
    -- exists only while it is on.
    local styleRow
    styleRow, h = W:DualRow(parent, y,
        { type="dropdown", text="Style", values=styleValues, order=styleOrder,
          tooltip="Blizz Default also switches the reputation bars to Blizzard's: it is tied to Use Blizzard's Rep Bars.",
          -- A frame art this client lacks shows as the EllesmereUI bar it draws.
          getValue=function()
              local v = EllesmereUI._GetXPBarStyle()
              return styleValues[v] and v or "eui"
          end,
          setValue=function(v) K.AfterSwitch(EllesmereUI._SetXPBarStyle(v)) end },
        { type="toggle", text="Show Dividers",
          tooltip="Draws a tick every 5% and a line every 10% across the bar.",
          disabled=_blizzDis, disabledTooltip=BLIZZ_DIS_TIP, rawTooltip=true,
          getValue=function() return S().showDividers end,
          setValue=EllesmereUI.SectionToggleSetValue(function(v)
              S().showDividers = v
              ns.ApplyDataBarLayout(XP)
          end) });  y = y - h
    if chrome then
        EllesmereUI.BuildInlineSwatches(styleRow._rightRegion, {
            { tooltip = "5% Ticks", hasAlpha = true,
              getValue = function()
                  local c = S().tick5Color
                  if c then return c.r or 220/255, c.g or 167/255, c.b or 127/255, c.a or 0.9 end
                  return 220/255, 167/255, 127/255, 0.9
              end,
              setValue = function(r, g, b, a)
                  S().tick5Color = { r = r, g = g, b = b, a = a or 0.9 }
                  ns.ApplyDataBarLayout(XP)
              end },
            { tooltip = "10% Lines", hasAlpha = true,
              getValue = function()
                  local c = S().tick10Color
                  if c then return c.r or 1, c.g or 1, c.b or 1, c.a or 0.9 end
                  return 1, 1, 1, 0.9
              end,
              setValue = function(r, g, b, a)
                  S().tick10Color = { r = r, g = g, b = b, a = a or 0.9 }
                  ns.ApplyDataBarLayout(XP)
              end },
        }, { size = 20,
            disabled = function() return _blizzDis() or not S().showDividers end,
            disabledTooltip = function()
                if _blizzDis() then return BLIZZ_DIS_TIP end
                return "Show Dividers"
            end,
            rawTooltip = _blizzDis })
    end

    -- 5% Line Style (its cog: Smart Ticks) | Divider Text (its cog: the
    -- text's colour, size and offsets), while Show Dividers is on.
    if S().showDividers then
        local divRow
        divRow, h = W:DualRow(parent, y,
            { type="dropdown", text="5% Line Style",
              tooltip="How the ticks between the 10% lines are drawn.",
              values={ dashed="Dashed", dotted="Dotted", solid="Solid", none="None" },
              order={ "dashed", "dotted", "solid", "none" },
              disabled=_blizzDis, disabledTooltip=BLIZZ_DIS_TIP, rawTooltip=true,
              getValue=function() return S().divider5Style or "dashed" end,
              setValue=function(v)
                  S().divider5Style = v
                  ns.ApplyDataBarLayout(XP)
              end },
            { type="toggle", text="Divider Text",
              tooltip="Labels each 10% line with its percentage.",
              disabled=_blizzDis, disabledTooltip=BLIZZ_DIS_TIP, rawTooltip=true,
              getValue=function() return S().showDividerText end,
              setValue=function(v)
                  S().showDividerText = v
                  ns.ApplyDataBarLayout(XP)
                  EllesmereUI:RefreshPage()
              end });  y = y - h
        if chrome then
            local lRgn, rRgn = divRow._leftRegion, divRow._rightRegion
            EllesmereUI.BuildInlineCog(lRgn, {
                title = "Ticks",
                anchorTo = lRgn._control,
                captureRegion = lRgn,
                disabled = _blizzDis, disabledTooltip = BLIZZ_DIS_TIP, rawTooltip = true,
                rows = {
                    { type="toggle", label="Smart Ticks",
                      tooltip="Hides the ticks and lines the fill has passed.",
                      get=function() return S().smartTicks end,
                      set=function(v)
                          S().smartTicks = v
                          ns.ApplyDataBarLayout(XP)
                      end },
                },
            })
            EllesmereUI.BuildInlineCog(rRgn, {
                title = "Divider Text",
                anchorTo = rRgn._control,
                captureRegion = rRgn,
                disabled = function() return _blizzDis() or not S().showDividerText end,
                disabledTooltip = function()
                    if _blizzDis() then return BLIZZ_DIS_TIP end
                    return "Divider Text"
                end,
                rawTooltip = _blizzDis,
                rows = {
                    { type="colorpicker", label="Text Color",
                      get=function()
                          local c = S().dividerTextColor
                          if c then return c.r or 1, c.g or 1, c.b or 1 end
                          return 1, 1, 1
                      end,
                      set=function(r, g, b)
                          S().dividerTextColor = { r = r, g = g, b = b }
                          ns.ApplyDataBarLayout(XP)
                      end },
                    { type="slider", label="Text Size", min=6, max=18, step=1,
                      get=function() return S().dividerTextSize or 8 end,
                      set=function(v)
                          S().dividerTextSize = v
                          ns.ApplyDataBarLayout(XP)
                      end },
                    { type="slider", label="X Offset", min=-50, max=50, step=1,
                      get=function() return S().dividerTextOffX or 0 end,
                      set=function(v)
                          S().dividerTextOffX = v
                          ns.ApplyDataBarLayout(XP)
                      end },
                    { type="slider", label="Y Offset", min=-50, max=50, step=1,
                      get=function() return S().dividerTextOffY or 0 end,
                      set=function(v)
                          S().dividerTextOffY = v
                          ns.ApplyDataBarLayout(XP)
                      end },
                },
            })
        end
    end

    _, h = W:Spacer(parent, y, 12);  y = y - h

    -------------------------------------------------------------------
    --  DISPLAY
    -------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "DISPLAY", y);  y = y - h

    -- Border Style | Border Size, no Custom Border toggle: the plain line
    -- shows as Solid 1px until the first edit turns the border on.
    y = K.BorderRows(y, XP, true)

    -- Fill Style: Custom Color (the fill colour swatches inline: Custom,
    -- Accent, Reactive) or a profession skill-bar animation (its cog inline:
    -- Animate on XP Gain, on by default -- nil plays, false stops it -- and
    -- Loop Animation, off by default, one turning the other off; Stretch to
    -- Bar draws one copy across the bar instead of tiles at the art's
    -- proportions). Only the flipbooks this client has are offered, and none
    -- on a vertical bar (the art is horizontal). Switching between the two
    -- kinds rebuilds the page for the other inline control.
    local fillVals, fillOrder = { custom = "Custom Color" }, { "custom" }
    if not Vertical() then
        for _, c in ipairs(FLIP_CANDS) do
            if C_Texture.GetAtlasInfo(c[1]) then
                fillVals[c[1]] = c[2]; fillOrder[#fillOrder + 1] = c[1]
            end
        end
    end
    local function FillKey()
        local f = S().fvFill
        if f and fillVals[f] then return f end
        return "custom"
    end
    local function Custom() return FillKey() == "custom" end
    -- Rested Color: the rested XP shown ahead of the fill (dark blue at half
    -- opacity until set).
    local fillRow
    fillRow, h = W:DualRow(parent, y,
        { type="dropdown", text="Fill Style", values=fillVals, order=fillOrder,
          tooltip="Fill the bar with a color, or with a profession skill bar animation.",
          disabled=_blizzDis, disabledTooltip=BLIZZ_DIS_TIP, rawTooltip=true,
          getValue=FillKey,
          setValue=EllesmereUI.DependentSetValue(Custom, function(v)
              S().fvFill = (v ~= "custom") and v or nil
              ns.ApplyDataBarLayout(XP)
              EllesmereUI:RefreshPage()
          end) },
        { type="colorpicker", text="Rested Color", hasAlpha=true,
          tooltip="The color of the rested XP shown ahead of the fill.",
          disabled=_blizzDis, disabledTooltip=BLIZZ_DIS_TIP, rawTooltip=true,
          getValue=function()
              local c = S().restedColor
              if c then return c.r or 0.15, c.g or 0.30, c.b or 0.60, c.a or 0.5 end
              return 0.15, 0.30, 0.60, 0.5
          end,
          setValue=function(r, g, b, a)
              S().restedColor = { r = r, g = g, b = b, a = a or 0.5 }
              ns.ApplyDataBarLayout(XP)
          end });  y = y - h
    if chrome then
        local rgn = fillRow._leftRegion
        if Custom() then
            EllesmereUI.BuildInlineSwatches(rgn, K.ColorSwatches(XP),
                { size = 20, disabled = _blizzDis, disabledTooltip = BLIZZ_DIS_TIP, rawTooltip = true })
        else
            EllesmereUI.BuildInlineCog(rgn, {
                title = "Fill Animation",
                anchorTo = rgn._control,
                captureRegion = rgn,
                disabled = _blizzDis, disabledTooltip = BLIZZ_DIS_TIP, rawTooltip = true,
                rows = {
                    { type="toggle", label="Animate on XP Gain",
                      tooltip="Plays the animation once each time you gain XP.",
                      get=function() return S().fvFillSmart ~= false and not S().fvFillAnim end,
                      set=function(on)
                          if on then
                              S().fvFillSmart = nil; S().fvFillAnim = nil
                          else
                              S().fvFillSmart = false
                          end
                          ns.ApplyDataBarLayout(XP)
                      end },
                    { type="toggle", label="Loop Animation",
                      tooltip="Plays the animation continuously.",
                      get=function() return S().fvFillAnim == true end,
                      set=function(on)
                          if on then
                              S().fvFillAnim = true; S().fvFillSmart = false
                          else
                              S().fvFillAnim = nil
                          end
                          ns.ApplyDataBarLayout(XP)
                      end },
                    { type="toggle", label="Stretch to Bar",
                      tooltip="Stretches one copy of the animation across the whole bar instead of repeating it at its own proportions.",
                      get=function() return S().fvFillStretch end,
                      set=function(on) S().fvFillStretch = on or nil; ns.ApplyDataBarLayout(XP) end },
                },
            })
        end
    end

    -- Background Opacity (its colour inline, locked at 0%; both fall back to
    -- the style's own background until set, ns.XPBarBackground) | Bar Texture.
    local bgRow
    bgRow, h = W:DualRow(parent, y,
        { type="slider", text="Background Opacity", min=0, max=100, step=1,
          tooltip="The opacity of the bar's background.",
          disabled=_blizzDis, disabledTooltip=BLIZZ_DIS_TIP, rawTooltip=true,
          getValue=function()
              local _, _, _, op = ns.XPBarBackground(S())
              return op
          end,
          setValue=function(v)
              local _, _, _, was = ns.XPBarBackground(S())
              S().barBgOpacity = v
              ns.ApplyDataBarLayout(XP)
              -- The colour swatch locks at 0%: refresh only on that edge.
              if (was <= 0) ~= (v <= 0) then EllesmereUI:RefreshPage() end
          end },
        K.TexCfg(XP));  y = y - h
    if chrome then
        EllesmereUI.BuildInlineSwatches(bgRow._leftRegion, {
            { tooltip = "Background Color",
              getValue = function()
                  local r, g, b = ns.XPBarBackground(S())
                  return r, g, b
              end,
              setValue = function(r, g, b)
                  S().barBgColor = { r = r, g = g, b = b }
                  ns.ApplyDataBarLayout(XP)
              end },
        }, { size = 20,
            disabled = function()
                if _blizzDis() then return true end
                local _, _, _, op = ns.XPBarBackground(S())
                return op <= 0
            end,
            disabledTooltip = function()
                if _blizzDis() then return BLIZZ_DIS_TIP end
                return "a Background Opacity above 0"
            end,
            rawTooltip = _blizzDis })
    end

    -- Text Size (its cog: the text's anchor and offsets, and Show %: the XP
    -- percentage after the raw values, e.g. "Level 40 - 1234 / 5678 (21.7%)")
    -- | Text Background (its colour and opacity inline).
    local textRow
    textRow, h = W:DualRow(parent, y, K.TextSizeCfg(XP),
        { type="toggle", text="Text Background",
          tooltip="Draws a box behind the bar text.",
          disabled=_blizzDis, disabledTooltip=BLIZZ_DIS_TIP, rawTooltip=true,
          getValue=function() return S().showTextBg end,
          setValue=function(v)
              S().showTextBg = v
              ns.ApplyDataBarLayout(XP)
              EllesmereUI:RefreshPage()
          end });  y = y - h
    K.TextCog(textRow._leftRegion, XP, {
        { type="toggle", label="Show %",
          tooltip="Append the XP percentage after the raw values.",
          disabled=function() return not S().showRawValues end,
          disabledTooltip="Show Raw Values",
          get=function() return S().showPercent end,
          set=function(v) S().showPercent = v; ns.ApplyDataBarLayout(XP) end },
    })
    if chrome then
        EllesmereUI.BuildInlineSwatches(textRow._rightRegion, {
            { tooltip = "Background Color", hasAlpha = true,
              getValue = function()
                  local c = S().textBgColor
                  if c then return c.r or 0.06, c.g or 0.06, c.b or 0.08, c.a or 0.9 end
                  return 0.06, 0.06, 0.08, 0.9
              end,
              setValue = function(r, g, b, a)
                  S().textBgColor = { r = r, g = g, b = b, a = a or 0.9 }
                  ns.ApplyDataBarLayout(XP)
              end },
        }, { size = 20,
            disabled = function() return _blizzDis() or not S().showTextBg end,
            disabledTooltip = function()
                if _blizzDis() then return BLIZZ_DIS_TIP end
                return "Text Background"
            end,
            rawTooltip = _blizzDis })
    end

    _, h = W:Spacer(parent, y, 12);  y = y - h

    -------------------------------------------------------------------
    --  EXTRAS
    -------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "EXTRAS", y);  y = y - h
    _, h = W:DualRow(parent, y, K.ClickThroughCfg(XP), EllesmereUI.BlankRowCfg());  y = y - h

    return math.abs(y)
end

-- Used by EUI_ActionBars_Options.lua
ns.ABO_BuildXPBarPage = BuildXPBarPage
