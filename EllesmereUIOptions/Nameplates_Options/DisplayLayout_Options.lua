if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Nameplates_Options\DisplayLayout_Options.lua
--  Nameplates options: the Style, Core Positions and Core Text Positions
--  sections of the Display page. Called by BuildDisplayPage; returns y, the
--  rows its click navigation maps to, and the cog popup and texture helpers
--  DisplayBars_Options.lua uses. Shared helpers come from ns._NPO_OptEnv, the
--  per-build slot helpers from ctx.
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUINameplates"]
if not ns then return end  -- module disabled: no options page

local function BuildDisplayLayout(parent, y, ctx)
    local env = ns._NPO_OptEnv
    local DB, DBVal, defaults, GetNPOptOutline = env.DB, env.DBVal, env.defaults, env.GetNPOptOutline
    local hbtOrder, hbtValues, optState, pairs = env.hbtOrder, env.hbtValues, env.optState, env.pairs
    local plates, PP, UpdatePreview, RefreshAllPlates = env.plates, env.PP, env.UpdatePreview, env.RefreshAllPlates
    local GetElementAtPosition, RefreshAllSlots, SetElementAtPosition, SetTextElementAtSlot = ctx.GetElementAtPosition, ctx.RefreshAllSlots, ctx.SetElementAtPosition, ctx.SetTextElementAtSlot
    local W = ctx.W
    local _, h

    -----------------------------------------------------------------------
    --  STYLE
    -----------------------------------------------------------------------
    local styleHeader
    styleHeader, h = W:SectionHeader(parent, "STYLE", y);  y = y - h
    y = EllesmereUI.BlizzStyle.Note(parent, y, "nameplates")

    local function RefreshAllTextures()
        ns.RefreshAllSettings()
        for _, plate in pairs(ns.friendlyPlates or {}) do
            if ns.ApplyHealthBarTexture then ns.ApplyHealthBarTexture(plate) end
            if ns.ApplyCastBarTexture then ns.ApplyCastBarTexture(plate) end
        end
    end

    -- Row 1: Border (None/Basic/Custom) | Border Size. Pure VIEW over showBorder + customBorderEnabled: None=off, Basic=standard border, Custom=custom border engine (reveals the Custom Border row below via page rebuild; None/Basic collapse it).
    -- Both stock styles gate both slots: they draw their own art (the stock background, the vanilla border sheets) and stand every EUI border down.
    local borderStyleRow
    borderStyleRow, h = W:DualRow(parent, y,
        EllesmereUI.BlizzStyle.Gate("nameplates", { type="dropdown", text="Border",
          values={ none = "None", basic = "Basic", custom = "Custom" },
          order={ "none", "basic", "custom" },
          getValue=function()
            if DBVal("customBorderEnabled") then return "custom" end
            local sb = DBVal("showBorder")
            if sb == nil then sb = defaults.showBorder end
            return sb and "basic" or "none"
          end,
          setValue=function(v)
            if v == "custom" then
              DB().customBorderEnabled = true
            elseif v == "basic" then
              DB().customBorderEnabled = false
              DB().showBorder = true
            else
              DB().customBorderEnabled = false
              DB().showBorder = false
            end
            ns.RefreshBorder()
            ns.RefreshBorderColor()
            UpdatePreview()
            -- Force rebuild so the Custom Border row shows/hides and rows below reflow.
            EllesmereUI:RefreshPage(true)
          end }, EllesmereUI.BlizzStyle.Active("nameplates") == "classic"),
        EllesmereUI.BlizzStyle.Gate("nameplates", { type="slider", text="Border Size", min=1, max=4, step=1,
          -- Only Basic uses this size (None has no border; Custom uses its own Custom Border Size below).
          disabled=function()
            if DBVal("customBorderEnabled") then return true end
            local v = DBVal("showBorder")
            if v == nil then return not defaults.showBorder end
            return not v
          end,
          disabledTooltip="This option is only used by the Basic border.",
          rawTooltip=true,
          getValue=function() return DBVal("borderSize") or defaults.borderSize end,
          setValue=function(v)
            DB().borderSize = v
            ns.RefreshBorder()
            UpdatePreview()
          end }))
    y = y - h
    -- Inline swatch on the Border dropdown: standard (Basic) border color, dimmed unless mode is Basic.
    if not EllesmereUI._prebuilding then
        local leftRgn = borderStyleRow._leftRegion
        local function isBorderOff()
            -- Off for None and Custom (standard border/color is inert then) -- only Basic uses it.
            if EllesmereUI.BlizzStyle.Get("nameplates") then return true end
            if DBVal("customBorderEnabled") then return true end
            local v = DBVal("showBorder")
            if v == nil then return not defaults.showBorder end
            return not v
        end
        local borderColorGet = function()
            local c = (DB() and DB().borderColor) or defaults.borderColor
            return c.r, c.g, c.b
        end
        local borderColorSet = function(r, g, b)
            DB().borderColor = { r = r, g = g, b = b }
            ns.RefreshBorderColor()
            UpdatePreview()
        end
        local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, borderColorGet, borderColorSet, nil, 20)
        PP.Point(swatch, "RIGHT", leftRgn._control, "LEFT", -12, 0)
        leftRgn._lastInline = swatch
        EllesmereUI.RegisterWidgetRefresh(function()
            local off = isBorderOff()
            swatch:SetAlpha(off and 0.15 or 1)
            swatch:EnableMouse(not off)
            updateSwatch()
        end)
        local off = isBorderOff()
        swatch:SetAlpha(off and 0.15 or 1)
        swatch:EnableMouse(not off)
    end

    -- Inline cog on the Border region: opt-in "Wrap Around Castbar" (left of the colour swatch); dimmed only for "None" mode (wrap applies to both Basic and Custom).
    if not EllesmereUI._prebuilding then
        local leftRgn = borderStyleRow._leftRegion
        local function wrapCogOff()
            -- Only "None" disables it; Basic and Custom both support the wrap.
            -- Neither stock style has an EUI border to wrap: Blizzard Style
            -- draws the stock background art, Classic WoW UI the vanilla
            -- border sheets, and both stand the EUI borders down.
            if ns.NP_Blizz() then return true end
            if DBVal("customBorderEnabled") then return false end
            local v = DBVal("showBorder")
            if v == nil then v = defaults.showBorder end
            return not v
        end
        local wrapRows = {
            { type="toggle", label="Wrap Around Castbar",
              -- Classic WoW UI draws the vanilla borders: nothing to wrap.
              disabled=function() return EllesmereUI.BlizzStyle.Active("nameplates") == "classic" end,
              disabledTooltip=function() return EllesmereUI.BlizzStyle.Label("nameplates") end,
              requireState="disabled",
              get=function()
                local v = DBVal("wrapBorderCastbar")
                if v == nil then return defaults.wrapBorderCastbar end
                return v
              end,
              set=function(v)
                DB().wrapBorderCastbar = v
                -- Unconditional re-apply so toggling OFF also unwraps any plate mid-cast and wrapped.
                ns.ApplyBorderWrapToAll()
                UpdatePreview()
                -- Show Seam Line's disabled state follows this toggle.
                EllesmereUI:RefreshPage()
              end },
        }
        -- Show Seam Line: the custom border's wrap only, so it is built only while
        -- Border = Custom (the Border setter rebuilds the page).
        if DBVal("customBorderEnabled") then
            wrapRows[#wrapRows + 1] = { type="toggle", label="Show Seam Line",
              tooltip="Draws the border style's seam line between the health and cast bars.",
              disabled=function()
                return DBVal("wrapBorderCastbar") ~= true
                    or not ns.NP_CanShowWrapSeam(DBVal("customBorderTexture") or defaults.customBorderTexture)
              end,
              -- Wrap off: the standard requirement line; wrap on: the style is the lock.
              disabledTooltip=function()
                if DBVal("wrapBorderCastbar") ~= true then return "Wrap Around Castbar" end
                return "This option requires the Pixels or Pixels Textured border style."
              end,
              rawTooltip=function() return DBVal("wrapBorderCastbar") == true end,
              get=function() return DBVal("wrapBorderSeam") == true end,
              set=function(v)
                DB().wrapBorderSeam = v
                ns.ApplyBorderWrapToAll()
                UpdatePreview()
              end }
        end
        EllesmereUI.BuildInlineCog(leftRgn, {
            disabled = wrapCogOff,
            disabledTooltip = "This option requires a Border to be selected",
            title = "Castbar Border",
            rows = wrapRows,
        })
    end

    -- Classic WoW UI only: the level, and the icon that replaces it on a
    -- boss, both seated in the health border's own plate. Each follows
    -- the bar's height until sized here, and each carries its X/Y nudges
    -- on an inline cog. Not built at all on the other styles, where there
    -- is no plate to fill; the if-body scopes its locals.
    if EllesmereUI.BlizzStyle.Active("nameplates") == "classic" then
        local classicPlateRow
        classicPlateRow, h = W:DualRow(parent, y,
            { type="slider", text="Level Size", min=0, max=40, step=1,
              tooltip="Size of the level in the border's plate. 0 follows the bar height.",
              getValue=function() return DBVal("classicLevelSize") or 0 end,
              setValue=function(v)
                DB().classicLevelSize = v
                ns.RefreshAllSettings()
                UpdatePreview()
              end },
            { type="slider", text="Elite Icon Size", min=0, max=40, step=1,
              tooltip="Size of the icon that replaces the level on a boss. 0 follows the bar height.",
              getValue=function() return DBVal("classicSkullSize") or 0 end,
              setValue=function(v)
                DB().classicSkullSize = v
                ns.RefreshAllSettings()
                UpdatePreview()
              end })
        y = y - h
        -- Reached by the preview's click navigation (the level in the
        -- border's plate scrolls here), which is built further down.
        parent._classicPlateRow = classicPlateRow
        if not EllesmereUI._prebuilding then
            local function PlateOffsetCog(rgn, title, xKey, yKey)
                EllesmereUI.BuildInlineCog(rgn, {
                    title = title,
                    rows = {
                        { type="slider", label="X Offset", min=-50, max=50, step=1,
                          get=function() return DBVal(xKey) or 0 end,
                          set=function(v)
                            DB()[xKey] = v
                            ns.RefreshAllSettings()
                            UpdatePreview()
                          end },
                        { type="slider", label="Y Offset", min=-50, max=50, step=1,
                          get=function() return DBVal(yKey) or 0 end,
                          set=function(v)
                            DB()[yKey] = v
                            ns.RefreshAllSettings()
                            UpdatePreview()
                          end },
                    },
                })
            end
            PlateOffsetCog(classicPlateRow._leftRegion, "Level Position", "classicLevelX", "classicLevelY")
            PlateOffsetCog(classicPlateRow._rightRegion, "Elite Icon Position", "classicSkullX", "classicSkullY")
        end
    end

    -- Custom Border row: only built when Border dropdown = "Custom" (selecting it triggers a page rebuild that reveals this row and reflows rows below;
    -- None/Basic collapse it). Uses the shared border engine (identical to Unit Frames, full SharedMedia support); the if-body scopes its locals to avoid growing this builder's local count.
    if DBVal("customBorderEnabled") then
        -- Custom Border Style dropdown (+ options cog) | Custom Border Size (+ color swatch)
        local cbTexValues, cbTexOrder = EllesmereUI.GetBorderTextureDropdown()
        local customBorderRow
        customBorderRow, h = W:DualRow(parent, y,
            EllesmereUI.BlizzStyle.Gate("nameplates", { type="dropdown", text="Custom Border Style",
              values=cbTexValues, order=cbTexOrder,
              getValue=function() return DBVal("customBorderTexture") or defaults.customBorderTexture end,
              setValue=function(v)
                DB().customBorderTexture = v
                DB().customBorderOffset  = nil
                DB().customBorderOffsetY = nil
                DB().customBorderShiftX  = nil
                DB().customBorderShiftY  = nil
                local _bcol, _bbehind = EllesmereUI.GetBorderStyleSelectDefaults(v)
                DB().customBorderColor  = _bcol
                DB().customBorderAlpha  = 1
                DB().customBorderBehind = _bbehind
                local defSz = EllesmereUI.GetBorderDefaultSize("nameplates", v)
                if defSz then DB().customBorderSize = defSz end
                if DB().customBorderSizePx then DB().customBorderSizePx = false end
                ns.RefreshBorder()
                UpdatePreview()
                -- Full rebuild: the Width/Height Offset row below exists only for a textured style.
                EllesmereUI:RefreshPage(true)
              end }),
            EllesmereUI.BlizzStyle.Gate("nameplates", EllesmereUI.BorderPxSliderCfg({
              -- Narrower track: the slot also carries the colour swatch and the Icon Borders cog.
              text="Custom Border Size", trackWidth=120,
              getStep=function() return DBVal("customBorderSize") or defaults.customBorderSize end,
              setStep=function(step) DB().customBorderSize = step end,
              getTex=function() return DBVal("customBorderTexture") or defaults.customBorderTexture end,
              getPx=function() return DB() and DB().customBorderSizePx end,
              setPx=function(v) DB().customBorderSizePx = v end,
              apply=function()
                ns.RefreshBorder()
                UpdatePreview()
              end })))
        y = y - h

        -- Width Offset | Height Offset: the textured border's outward offsets, shown only while a
        -- textured style is selected (Solid has none). Built during prebuild too so the y advance matches.
        do
            local cbTexNow = DBVal("customBorderTexture") or defaults.customBorderTexture
            if cbTexNow and cbTexNow ~= "" and cbTexNow ~= "solid" then
                local ocfgL, ocfgR = EllesmereUI.BorderOffsetRowCfgs({
                    addonKey   = "nameplates",
                    getTex     = function() return DBVal("customBorderTexture") or defaults.customBorderTexture end,
                    getStep    = function() return DBVal("customBorderSize") or defaults.customBorderSize end,
                    getSizeKey = function() return DBVal("customBorderSize") or defaults.customBorderSize end,
                    getPx      = function() return DB() and DB().customBorderSizePx end,
                    getX       = function() return DB() and DB().customBorderOffset end,
                    setX       = function(v) DB().customBorderOffset = v end,
                    getY       = function() return DB() and DB().customBorderOffsetY end,
                    setY       = function(v) DB().customBorderOffsetY = v end,
                    apply      = function() ns.RefreshBorder(); UpdatePreview() end,
                })
                _, h = W:DualRow(parent, y,
                    EllesmereUI.BlizzStyle.Gate("nameplates", ocfgL),
                    EllesmereUI.BlizzStyle.Gate("nameplates", ocfgR))
                y = y - h
            end
        end

        -- Inline "Border Options" cog on the Custom Border Style region (shifts + Show Behind)
        if not EllesmereUI._prebuilding then
            local leftRgn = customBorderRow._leftRegion
            -- Shift offsets only apply to textured styles (row only exists when Custom is selected, so no enable gate needed).
            local function cbCogOff() return (DBVal("customBorderTexture") or defaults.customBorderTexture) == "solid" end
            EllesmereUI.BuildInlineCog(leftRgn, {
                icon = EllesmereUI.DIRECTIONS_ICON or EllesmereUI.COGS_ICON,
                disabled = cbCogOff,
                disabledTooltip = "This option requires a textured border style",
                title = "Border Options",
                rows = {
                    { type="slider", label="Shift X", min=-10, max=10, step=1,
                      get=function()
                        local v = DB() and DB().customBorderShiftX
                        if v then return v end
                        local tex = DBVal("customBorderTexture") or defaults.customBorderTexture
                        local sz  = DBVal("customBorderSize") or defaults.customBorderSize
                        local _, _, dsx = EllesmereUI.GetBorderDefaults("nameplates", tex, sz)
                        return dsx
                      end,
                      set=function(v) DB().customBorderShiftX = (v == 0 and nil or v); ns.RefreshBorder(); UpdatePreview() end },
                    { type="slider", label="Shift Y", min=-10, max=10, step=1,
                      get=function()
                        local v = DB() and DB().customBorderShiftY
                        if v then return v end
                        local tex = DBVal("customBorderTexture") or defaults.customBorderTexture
                        local sz  = DBVal("customBorderSize") or defaults.customBorderSize
                        local _, _, _, dsy = EllesmereUI.GetBorderDefaults("nameplates", tex, sz)
                        return dsy
                      end,
                      set=function(v) DB().customBorderShiftY = (v == 0 and nil or v); ns.RefreshBorder(); UpdatePreview() end },
                    { type="toggle", label="Show Behind",
                      get=function()
                        local v = DBVal("customBorderBehind")
                        if v == nil then return defaults.customBorderBehind end
                        return v
                      end,
                      set=function(v) DB().customBorderBehind = v; ns.RefreshBorder(); UpdatePreview() end },
                },
            })
        end

        -- Inline color swatch (with alpha) on the Custom Border Size region
        if not EllesmereUI._prebuilding then
            local rightRgn = customBorderRow._rightRegion
            local cbColGet = function()
                local c = (DB() and DB().customBorderColor) or defaults.customBorderColor
                return c.r, c.g, c.b, (DBVal("customBorderAlpha") or defaults.customBorderAlpha or 1)
            end
            local cbColSet = function(r, g, b, a)
                DB().customBorderColor = { r = r, g = g, b = b }
                if a ~= nil then DB().customBorderAlpha = a end
                ns.RefreshBorderColor()
                UpdatePreview()
            end
            local cbSwatch, cbUpdateSwatch = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5, cbColGet, cbColSet, true, 20)
            PP.Point(cbSwatch, "RIGHT", rightRgn._control, "LEFT", -12, 0)
            rightRgn._lastInline = cbSwatch
            EllesmereUI.RegisterWidgetRefresh(function() cbUpdateSwatch() end)
        end

        -- "Icon Borders" cog on the Custom Border Size region, chained left of the colour
        -- swatch above (built after it): the custom border on the aura icons and on the
        -- cast spell icon. A cog, not a row: both are niche, and the whole block exists
        -- only while Border = Custom. The if-body scopes its locals (builder budget).
        if not EllesmereUI._prebuilding then
            local rightRgn = customBorderRow._rightRegion
            EllesmereUI.BuildInlineCog(rightRgn, {
                title = "Icon Borders",
                captureRegion = rightRgn,
                rows = {
                    { type="toggle", label="Custom Border on Aura Icons",
                      tooltip="Gives debuff, buff and crowd control icons the custom border instead of the 1-pixel border.",
                      disabled=function()
                        return DBVal("hideDebuffIconBorder") == true and DBVal("hideBuffIconBorder") == true
                            and DBVal("hideCCIconBorder") == true
                      end,
                      disabledTooltip="This option requires at least one aura type to show its border.",
                      rawTooltip=true,
                      get=function() return DBVal("auraIconCustomBorder") == true end,
                      set=function(v)
                        DB().auraIconCustomBorder = v
                        -- Fingerprint-gated aura restyle (the cast-lockout icon included).
                        ns.NPC_ReloadAll()
                        UpdatePreview()
                      end },
                    { type="toggle", label="Custom Border on Spell Icon",
                      tooltip="Gives the cast bar spell icon the custom border instead of its 1-pixel border.",
                      disabled=function()
                        return DBVal("showCastIcon") == false or DBVal("hideCastIconBorder") == true
                      end,
                      disabledTooltip="This option requires the spell icon and its border to be shown.",
                      rawTooltip=true,
                      get=function() return DBVal("castIconCustomBorder") == true end,
                      set=function(v)
                        DB().castIconCustomBorder = v
                        -- Re-applies every plate's appearance (pooled plates too), which
                        -- builds or turns off the icon border.
                        ns.RefreshAllSettings()
                        UpdatePreview()
                      end },
                },
            })
        end
    end

    -- Row 2: Background (+swatch) | Absorb Style (+cog, preview eye) -- placed here so the section fills sequentially, no blank middle slot. Absorb Style options: Blizzard + the stripe overlay set (shared with Focus Texture) + Clean; stripe keys resolve via ns.ResolveOverlayTexPath.
    local absorbStyleValues = {
        ["blizzard"]="Blizzard",
        ["striped"]="Striped",
        ["striped-v2"]="Stripes",
        ["striped-wide-v2"]="Wide Stripes",
        ["stripes-medium"]="Medium Stripes",
        ["stripes-small-close"]="Small Dense Stripes",
        ["stripes-small-spread"]="Small Spread Stripes",
        ["striped-tiny"]="Tiny Stripes",
        ["clean"]="Clean (Flat)",
        ["pixelsShield"]="Pixels Shield",
        ["pixelsShieldEdge"]="Pixels Shield Edge",
        ["pixelsShieldFill"]="Pixels Shield Fill",
    }
    local absorbStyleOrder = {
        "blizzard", "striped",
        "striped-v2", "striped-wide-v2", "stripes-medium",
        "stripes-small-close", "stripes-small-spread", "striped-tiny",
        "clean", "pixelsShield", "pixelsShieldEdge", "pixelsShieldFill",
    }
    -- Append SharedMedia statusbar textures after a divider (mirrors Bar Texture). SM keys ("sm:") were added to the shared health-bar tables by AppendSharedMediaTextures; resolution flows via ns.ResolveOverlayTexPath -> health-bar lookup, so SM keys paint correctly here.
    do
        local sepAdded = false
        for _, k in ipairs(hbtOrder) do
            if k ~= "---" and k:find("^sm:") then
                if not sepAdded then
                    absorbStyleOrder[#absorbStyleOrder + 1] = "---"
                    sepAdded = true
                end
                absorbStyleOrder[#absorbStyleOrder + 1] = k
                absorbStyleValues[k] = hbtValues[k]
            end
        end
        -- Preview swatch behind each menu row resolves exactly like the render path: NP_ABSORB_STYLE_TEX for blizzard/striped/clean, then ns.ResolveOverlayTexPath for stripe overlays/SM keys.
        absorbStyleValues._menuOpts = {
            itemHeight = 28,
            background = function(key)
                if not key or key == "---" then return nil end
                return ns.NP_ABSORB_STYLE_TEX[key] or ns.ResolveOverlayTexPath(key)
            end,
        }
    end
    local bgHoverRow
    bgHoverRow, h = W:DualRow(parent, y,
        ns.NP_BlizzOnlyGate({ type="slider", text="Background", min=0, max=100, step=1,
          getValue=function()
            return math.floor(((DBVal("bgAlpha") or defaults.bgAlpha) * 100) + 0.5)
          end,
          setValue=function(v)
            DB().bgAlpha = v / 100
            local c = (DB() and DB().bgColor) or defaults.bgColor
            for _, plate in pairs(plates) do
                plate.healthBG:SetColorTexture(c.r, c.g, c.b, v / 100)
            end
            UpdatePreview()
          end }),
        { type="dropdown", text="Absorb Style", values=absorbStyleValues, order=absorbStyleOrder,
          getValue=function() return DBVal("absorbStyle") or "blizzard" end,
          setValue=function(v)
            DB().absorbStyle = v
            -- Selecting a style sets opacity to that style's default (Blizzard/Stripes 80%, Clean 30%); slider tweaks from there.
            DB().absorbAlpha = math.floor(((ns.NP_ABSORB_STYLE_ALPHA[v] or 0.8) * 100) + 0.5)
            ns.ApplyAbsorbStyleAll()
            UpdatePreview()
            -- Refresh so the color swatch enables/disables (Blizzard = off).
            EllesmereUI:RefreshPage()
          end })
    y = y - h
    -- Inline color swatch on Background (left region)
    if not EllesmereUI._prebuilding then
        local leftRgn = bgHoverRow._leftRegion
        local cbColorGet = function()
            local c = (DB() and DB().bgColor) or defaults.bgColor
            return c.r, c.g, c.b
        end
        local cbColorSet = function(r, g, b)
            DB().bgColor = { r = r, g = g, b = b }
            local a = DBVal("bgAlpha") or defaults.bgAlpha
            for _, plate in pairs(plates) do
                plate.healthBG:SetColorTexture(r, g, b, a)
            end
            UpdatePreview()
        end
        local cbSwatch, cbUpdateSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, cbColorGet, cbColorSet, nil, 20)
        PP.Point(cbSwatch, "RIGHT", leftRgn._control, "LEFT", -12, 0)
        leftRgn._lastInline = cbSwatch
        EllesmereUI.RegisterWidgetRefresh(function() cbUpdateSwatch() end)
        if ns.NP_BlizzOnly() then EllesmereUI.BlizzStyle.BlockInline("nameplates", cbSwatch) end
    end

    -- Inline absorb color swatch (right of Row 2): white by default, tints every style except Blizzard (disabled there since Blizzard keeps its own coloring); mirrors the Focus Texture swatch's disabled pattern.
    if not EllesmereUI._prebuilding then
        local rgn = bgHoverRow._rightRegion
        local acColorGet = function()
            local c = (DB() and DB().absorbColor) or defaults.absorbColor or { r = 1, g = 1, b = 1 }
            return c.r, c.g, c.b
        end
        local acColorSet = function(r, g, b)
            DB().absorbColor = { r = r, g = g, b = b }
            ns.ApplyAbsorbStyleAll()
            UpdatePreview()
        end
        local acSwatch, acUpdateSwatch = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, acColorGet, acColorSet, nil, 20)
        PP.Point(acSwatch, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = acSwatch
        local function absorbColorOff() return (DBVal("absorbStyle") or "blizzard") == "blizzard" end
        EllesmereUI.RegisterWidgetRefresh(function()
            local off = absorbColorOff()
            acSwatch:SetAlpha(off and 0.15 or 1)
            acSwatch:EnableMouse(not off)
            acUpdateSwatch()
        end)
        local off0 = absorbColorOff()
        acSwatch:SetAlpha(off0 and 0.15 or 1)
        acSwatch:EnableMouse(not off0)
    end

    -- Inline "Absorb Settings" cog on the Absorb Style region (right of Row 2)
    if not EllesmereUI._prebuilding then
        local rgn = bgHoverRow._rightRegion
        EllesmereUI.BuildInlineCog(rgn, {
            title = "Absorb Settings",
            rows = {
                { type = "slider", label = "Opacity", min = 5, max = 100, step = 1,
                  get = function()
                    local v = DBVal("absorbAlpha")
                    if v then return v end
                    -- Untouched profiles: show the active style's default.
                    local style = DBVal("absorbStyle") or "blizzard"
                    if style == "clean" then return DBVal("absorbCleanAlpha") or 30 end
                    return math.floor(((ns.NP_ABSORB_STYLE_ALPHA[style] or 0.8) * 100) + 0.5)
                  end,
                  set = function(v)
                    DB().absorbAlpha = v
                    ns.ApplyAbsorbStyleAll()
                    UpdatePreview()
                  end },
            },
        })
    end

    -- Eye icon: toggle absorb preview on the preview nameplate
    do
        local EYE_VISIBLE   = EllesmereUI.EYE_VISIBLE_ICON
        local EYE_INVISIBLE = EllesmereUI.EYE_INVISIBLE_ICON
        local rgn = bgHoverRow._rightRegion
        local eyeBtn = CreateFrame("Button", nil, rgn)
        eyeBtn:SetSize(26, 26)
        eyeBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = eyeBtn
        eyeBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
        eyeBtn:SetAlpha(0.4)
        local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
        eyeTex:SetAllPoints()
        local function RefreshAbsorbEye()
            if optState.showAbsorbPreview then
                eyeTex:SetTexture(EYE_INVISIBLE)
            else
                eyeTex:SetTexture(EYE_VISIBLE)
            end
        end
        RefreshAbsorbEye()
        eyeBtn:SetScript("OnClick", function()
            optState.showAbsorbPreview = not optState.showAbsorbPreview
            RefreshAbsorbEye()
            UpdatePreview()
        end)
        eyeBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
        eyeBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
    end

    -- Row 3: Bar Texture | Cast Bar Texture -- share the same texture set (EUI built-ins + SharedMedia) and resolve identically; Bar Texture drives the health bar, Cast Bar Texture drives the cast bar.
    _, h = W:DualRow(parent, y,
        -- Bar Texture stays live under Blizzard Style: the health fill is the
        -- user's own texture under the stock background art.
        { type="dropdown", text="Bar Texture", values=hbtValues, order=hbtOrder,
          getValue=function() return DBVal("healthBarTexture") or "none" end,
          setValue=function(v)
            DB().healthBarTexture = v
            RefreshAllTextures()
            UpdatePreview()
          end },
        ns.NP_BlizzOnlyGate({ type="dropdown", text="Cast Bar Texture", values=hbtValues, order=hbtOrder,
          getValue=function() return DBVal("castBarTexture") or "none" end,
          setValue=function(v)
            DB().castBarTexture = v
            RefreshAllTextures()
            UpdatePreview()
          end }));  y = y - h

    -- WoW Forever variant only (the Forever client): Show Level Box, the
    -- opt-out for the level box right of the health bar (nil = shown),
    -- last in the section so its blank slot is the odd last one. Off, the
    -- plates lay out as plain Blizzard Style; Left Text stays the user's
    -- to set to Level. Not built on any other look.
    if EllesmereUI.BlizzStyle.Forever("nameplates") then
        local foreverBoxRow
        foreverBoxRow, h = W:DualRow(parent, y,
            { type="toggle", text="Show Level Box",
              tooltip="Shows the level box right of the health bar; with it off, Left Text can show the level instead.",
              getValue=function() return not DBVal("foreverHideLevelBox") end,
              setValue=function(v)
                DB().foreverHideLevelBox = (not v) or nil
                ns.RefreshAllSettings()
                UpdatePreview()
              end },
            EllesmereUI.BlankRowCfg())
        y = y - h
        -- Reached by the preview's click navigation (the level box).
        parent._foreverBoxRow = foreverBoxRow
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h

    -----------------------------------------------------------------------
    --  CORE POSITIONS
    -----------------------------------------------------------------------
    local coreHeader
    coreHeader, h = W:SectionHeader(parent, "CORE POSITIONS", y);  y = y - h

    -- Subtitle hint next to the section header
    do
        local regions = { coreHeader:GetRegions() }
        for _, rgn in ipairs(regions) do
            if rgn:IsObjectType("FontString") and EllesmereUI.EnKey(rgn:GetText()) == "CORE POSITIONS" then
                local sub = coreHeader:CreateFontString(nil, "OVERLAY")
                sub:SetFont(rgn:GetFont())
                sub:SetTextColor(1, 1, 1, 0.25)
                sub:SetText(EllesmereUI.L("(one slot per element)"))
                sub:SetPoint("LEFT", rgn, "RIGHT", 6, 0)
                break
            end
        end
    end

    local coreElementValues = {
        debuffs        = "Debuffs",
        buffs          = "Buffs",
        ccs            = "Crowd Control",
        debuffsccs     = "Debuffs + CC",
        raidmarker     = "Raid Marker",
        classification = "Rare/Quest Indicator",
        faction        = "Faction",
        classfaction   = "Rare/Quest + Faction",
        none           = "None",
    }
    local coreElementOrder = { "debuffs", "buffs", "ccs", "debuffsccs", "raidmarker", "classification", "faction", "classfaction", "none" }

    local coreRow1, coreRow2, coreRow3
    local _refreshRaidMarkerEyePos
    local _refreshClassificationEyePos

    optState.RefreshCoreEyes = function()
        if _refreshRaidMarkerEyePos then _refreshRaidMarkerEyePos() end
        if _refreshClassificationEyePos then _refreshClassificationEyePos() end
    end

    -- Each slot's control is a checkbox dropdown, one box per element: a view
    -- over the same stored keys the single-choice dropdowns wrote (each
    -- element's slot key, debuffIncludeCC and classificationIncludeFaction for
    -- the two pairs that can share a slot) plus classificationHideRare /
    -- classificationHideQuest, the two halves of the Rare/Quest indicator. The
    -- halves are one frame, so they always share a slot and move together.
    -- Only elements of one group can share a slot; the rest grey out while the
    -- slot holds something. The single-choice dropdowns stay built, hidden,
    -- under the checkbox dropdowns (the row label's empty-slot state).
    local CORE_ORDER = { "debuffs", "buffs", "ccs", "raidmarker", "rare", "quest", "faction" }
    local CORE_LABEL = {
        debuffs = "Debuffs", buffs = "Buffs", ccs = "Crowd Control", raidmarker = "Raid Marker",
        rare = "Rare Indicator", quest = "Quest Indicator", faction = "Faction",
    }
    local CORE_TIP = {
        rare  = "Elite and rare marks. Always in the same slot as the Quest Indicator.",
        quest = "Marks mobs for your active quests. Always in the same slot as the Rare Indicator.",
    }
    local CORE_GROUP = {
        debuffs = "aura", ccs = "aura",
        rare = "class", quest = "class", faction = "class",
        buffs = "buffs", raidmarker = "raidmarker",
    }

    local function CoreHas(pos, k)
        if k == "debuffs" then return DBVal("debuffSlot") == pos end
        if k == "buffs" then return DBVal("buffSlot") == pos end
        if k == "ccs" then
            return DBVal("ccSlot") == pos
                or (DBVal("debuffIncludeCC") == true and DBVal("debuffSlot") == pos)
        end
        if k == "raidmarker" then return DBVal("raidMarkerPos") == pos end
        if k == "rare" then
            return DBVal("classificationSlot") == pos and not DBVal("classificationHideRare")
        end
        if k == "quest" then
            return DBVal("classificationSlot") == pos and not DBVal("classificationHideQuest")
        end
        if k == "faction" then
            -- While Rare/Quest + Faction is on, a leftover faction slot is ignored.
            if DBVal("classificationIncludeFaction") == true then
                return DBVal("classificationSlot") == pos
            end
            return DBVal("factionSlot") == pos
        end
        return false
    end

    -- A checked box can always be unchecked.
    local function CoreLocked(pos, k)
        if CoreHas(pos, k) then return false end
        if k == "rare" and EllesmereUI.BlizzStyle.Forever("nameplates") then return true end
        local g = CORE_GROUP[k]
        for i = 1, #CORE_ORDER do
            local o = CORE_ORDER[i]
            if CORE_GROUP[o] ~= g and CoreHas(pos, o) then return true end
        end
        return false
    end

    local function CoreLockTip(k)
        if k == "rare" and EllesmereUI.BlizzStyle.Forever("nameplates") then
            return "WoW Forever nameplates show no elite or rare marks."
        end
        return "Only Debuffs with Crowd Control, or the Rare and Quest Indicators with Faction, can share a slot."
    end

    local function CoreSet(pos, k, v)
        local db = DB()
        if k == "debuffs" then
            if v then
                local old = DBVal("debuffSlot")
                local merged = DBVal("debuffIncludeCC") == true
                if DBVal("ccSlot") == pos then
                    -- CC already here on its own: the two become Debuffs + CC.
                    db.ccSlot = "none"
                    merged = true
                elseif merged and old ~= pos then
                    -- Leaving a Debuffs + CC slot: CC stays there on its own
                    -- unless it already has a slot elsewhere.
                    if old ~= "none" and DBVal("ccSlot") == "none" then db.ccSlot = old end
                    merged = false
                end
                db.debuffSlot = pos
                db.debuffIncludeCC = merged
            else
                if DBVal("debuffIncludeCC") == true and DBVal("ccSlot") == "none" then
                    db.ccSlot = pos
                end
                db.debuffSlot = "none"
                db.debuffIncludeCC = false
            end
        elseif k == "ccs" then
            if v then
                if DBVal("debuffSlot") == pos then
                    db.debuffIncludeCC = true
                    db.ccSlot = "none"
                else
                    db.debuffIncludeCC = false
                    db.ccSlot = pos
                end
            else
                if DBVal("debuffSlot") == pos then db.debuffIncludeCC = false end
                if DBVal("ccSlot") == pos then db.ccSlot = "none" end
            end
        elseif k == "buffs" then
            if v then db.buffSlot = pos
            elseif DBVal("buffSlot") == pos then db.buffSlot = "none" end
        elseif k == "raidmarker" then
            if v then db.raidMarkerPos = pos
            elseif DBVal("raidMarkerPos") == pos then db.raidMarkerPos = "none" end
        elseif k == "rare" or k == "quest" then
            local hideKey = (k == "rare") and "classificationHideRare" or "classificationHideQuest"
            local otherKey = (k == "rare") and "classificationHideQuest" or "classificationHideRare"
            if v then
                local old = DBVal("classificationSlot")
                if old ~= pos then
                    -- Moving: a Faction badge riding along stays behind on its own.
                    if DBVal("classificationIncludeFaction") == true then
                        db.classificationIncludeFaction = false
                        if old ~= "none" then db.factionSlot = old end
                    end
                    -- Brought back from None: only the half that was checked.
                    if old == "none" then db[otherKey] = true end
                    db.classificationSlot = pos
                    -- Faction already here on its own joins them.
                    if DBVal("factionSlot") == pos then
                        db.classificationIncludeFaction = true
                        db.factionSlot = "none"
                    end
                end
                db[hideKey] = false
            elseif DBVal(otherKey) then
                -- The last half goes: the indicator leaves the slot, a Faction
                -- badge riding along stays there on its own.
                if DBVal("classificationIncludeFaction") == true then
                    db.classificationIncludeFaction = false
                    db.factionSlot = pos
                end
                db.classificationSlot = "none"
                db.classificationHideRare = false
                db.classificationHideQuest = false
            else
                db[hideKey] = true
            end
        elseif k == "faction" then
            if v then
                if DBVal("classificationSlot") == pos then
                    db.classificationIncludeFaction = true
                    db.factionSlot = "none"
                else
                    db.classificationIncludeFaction = false
                    db.factionSlot = pos
                end
            else
                if DBVal("classificationSlot") == pos then db.classificationIncludeFaction = false end
                if DBVal("factionSlot") == pos then db.factionSlot = "none" end
            end
        end
    end

    local function InstallCoreCB(rgn, pos)
        local ctrl = rgn._control
        local ddW = ctrl and ctrl:GetWidth() or 0
        if ddW < 50 then ddW = 170 end
        local items = {}
        for i = 1, #CORE_ORDER do
            local k = CORE_ORDER[i]
            items[i] = {
                key = k, label = CORE_LABEL[k], tooltip = CORE_TIP[k],
                lockedFn = function() return CoreLocked(pos, k) end,
                lockedTooltip = function() return CoreLockTip(k) end,
            }
        end
        local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
            rgn, ddW, rgn:GetFrameLevel() + 2, items,
            function(k) return CoreHas(pos, k) end,
            function(k, v)
                CoreSet(pos, k, v)
                RefreshAllSlots()
                optState.RefreshCoreEyes()
            end)
        local p1, rel, p2, ax, ay
        if ctrl then
            p1, rel, p2, ax, ay = ctrl:GetPoint(1)
            ctrl:Hide()
        end
        if p1 then cbDD:SetPoint(p1, rel, p2, ax, ay)
        else PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0) end
        rgn._control = cbDD
        rgn._lastInline = nil
        EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
    end

    -- Slot-based offsets: pos .. "SlotXOffset" / "SlotYOffset"

    local function CorePosXGet(pos)
        return DBVal(pos .. "SlotXOffset") or 0
    end
    local function CorePosYGet(pos)
        return DBVal(pos .. "SlotYOffset") or 0
    end
    local function CorePosXSet(pos, v)
        DB()[pos .. "SlotXOffset"] = v
        RefreshAllSlots()
    end
    local function CorePosYSet(pos, v)
        DB()[pos .. "SlotYOffset"] = v
        RefreshAllSlots()
    end
    local function CorePosOffDisabled(pos)
        return GetElementAtPosition(pos) == "none"
    end

    -------------------------------------------------------------------
    --  Combined Settings Popup  (singleton, slide-up, pos + optional size)
    -------------------------------------------------------------------
    local cogPopup          -- the popup frame (created once)
    local cogPopupOwner     -- which cog icon currently owns the popup

    local function CogPopupOpen(btn) return cogPopupOwner == btn and cogPopup:IsShown() end

    -- opts = {title, xGet, xSet, yGet, ySet, sizeGet, sizeSet, sizeMin, sizeMax, sizeStep, sizeLabel}; sizeGet nil = no size row.
    local function ShowCogPopup(anchorBtn, opts)
        if not cogPopup then
            local SolidTex = EllesmereUI.SolidTex
            local MakeBorder = EllesmereUI.MakeBorder
            local MakeFont = EllesmereUI.MakeFont
            local BuildSliderCore = EllesmereUI.BuildSliderCore
            local BORDER_COLOR = EllesmereUI.BORDER_COLOR
            local SL_INPUT_A = EllesmereUI.SL_INPUT_A

            local SIDE_PAD   = 14
            local INPUT_W    = 34; local SLIDER_INPUT_GAP = 8; local LABEL_SLIDER_GAP = 12
            local TOP_PAD    = 14
            local TITLE_H    = 11
            local TITLE_GAP  = 10
            local GAP        = 10
            local SLIDER_H   = 24

            -- Max height: title + X + Y + Size = 4 rows
            local MAX_H = TOP_PAD + TITLE_H + TITLE_GAP + GAP + SLIDER_H + GAP + SLIDER_H + GAP + SLIDER_H + TOP_PAD

            local pf = CreateFrame("Frame", nil, UIParent)
            pf:SetSize(260, MAX_H)
            pf:SetFrameStrata("DIALOG")
            pf:SetFrameLevel(200)
            pf:EnableMouse(true)
            pf:Hide()

            -- Match the panel/popup scale so this popup renders at the same size as the shared BuildCogPopup popups (else it stays scale 1.0 and looks oversized); registering it also tracks the panel scale slider.
            pf:SetScale((EllesmereUI.GetPopupScale()) or 1)
            if EllesmereUI._popupFrames then
                EllesmereUI._popupFrames[#EllesmereUI._popupFrames + 1] = { popup = pf }
            end

            local bg = SolidTex(pf, "BACKGROUND", 0.06, 0.08, 0.10, 0.95)
            bg:SetAllPoints()
            MakeBorder(pf, BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.15)

            local titleFS = MakeFont(pf, 11, "", 1, 1, 1)
            titleFS:SetAlpha(0.7)
            titleFS:SetPoint("TOP", pf, "TOP", 0, -TOP_PAD)
            pf._titleFS = titleFS

            local tmpFS = pf:CreateFontString(nil, "OVERLAY")
            tmpFS:SetFont(EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 12, GetNPOptOutline())
            local labelTexts = {"X Offset", "Y Offset", "Size", "Width %", "Spacing", "Opacity"}
            local maxLblW = 0
            for _, txt in ipairs(labelTexts) do
                tmpFS:SetText(EllesmereUI.L(txt))
                local w = tmpFS:GetStringWidth()
                if w > maxLblW then maxLblW = w end
            end
            tmpFS:Hide()
            if maxLblW < 10 then maxLblW = 28 end

            local SLIDER_LEFT = SIDE_PAD + maxLblW + LABEL_SLIDER_GAP
            local SLIDER_W = math.max(80, 260 - SLIDER_LEFT - SLIDER_INPUT_GAP - INPUT_W - SIDE_PAD)
            local POPUP_W = SLIDER_LEFT + SLIDER_W + SLIDER_INPUT_GAP + INPUT_W + SIDE_PAD
            if POPUP_W < 180 then POPUP_W = 180 end
            pf:SetSize(POPUP_W, pf:GetHeight())

            -- X slider row
            local X_ROW_Y = -(TOP_PAD + TITLE_H + TITLE_GAP + GAP)
            local xLabel = MakeFont(pf, 12, nil, 1, 1, 1)
            xLabel:SetAlpha(0.6); xLabel:SetText(EllesmereUI.L("X Offset"))
            xLabel:SetPoint("LEFT", pf, "TOPLEFT", SIDE_PAD, X_ROW_Y - SLIDER_H / 2)
            local xTrack, xValBox = BuildSliderCore(pf, SLIDER_W, 4, 12, INPUT_W, SLIDER_H, 11, SL_INPUT_A,
                -300, 300, 1,
                function() return pf._xGet and pf._xGet() or 0 end,
                function(v) if pf._xSet then pf._xSet(v) end end, true)
            xTrack:SetPoint("TOPLEFT", pf, "TOPLEFT", SLIDER_LEFT, X_ROW_Y - 2)
            xValBox:ClearAllPoints(); xValBox:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -SIDE_PAD, X_ROW_Y)

            pf._xTrack = xTrack; pf._xValBox = xValBox; pf._xLabel = xLabel

            -- Y slider row
            local Y_ROW_Y = X_ROW_Y - SLIDER_H - GAP
            local yLabel = MakeFont(pf, 12, nil, 1, 1, 1)
            yLabel:SetAlpha(0.6); yLabel:SetText(EllesmereUI.L("Y Offset"))
            yLabel:SetPoint("LEFT", pf, "TOPLEFT", SIDE_PAD, Y_ROW_Y - SLIDER_H / 2)
            local yTrack, yValBox = BuildSliderCore(pf, SLIDER_W, 4, 12, INPUT_W, SLIDER_H, 11, SL_INPUT_A,
                -300, 300, 1,
                function() return pf._yGet and pf._yGet() or 0 end,
                function(v) if pf._ySet then pf._ySet(v) end end, true)
            yTrack:SetPoint("TOPLEFT", pf, "TOPLEFT", SLIDER_LEFT, Y_ROW_Y - 2)
            yValBox:ClearAllPoints(); yValBox:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -SIDE_PAD, Y_ROW_Y)

            pf._yTrack = yTrack; pf._yValBox = yValBox; pf._yLabel = yLabel

            -- Size slider row (hidden when not needed)
            local S_ROW_Y = Y_ROW_Y - SLIDER_H - GAP
            local sLabel = MakeFont(pf, 12, nil, 1, 1, 1)
            sLabel:SetAlpha(0.6); sLabel:SetText(EllesmereUI.L("Size"))
            sLabel:SetPoint("LEFT", pf, "TOPLEFT", SIDE_PAD, S_ROW_Y - SLIDER_H / 2)
            pf._sLabel = sLabel

            -- Spacing slider row (hidden unless the slot holds a multi-icon aura element: debuffs/buffs/CCs); fixed range, built once.
            local SP_ROW_Y = S_ROW_Y - SLIDER_H - GAP
            local spLabel = MakeFont(pf, 12, nil, 1, 1, 1)
            spLabel:SetAlpha(0.6); spLabel:SetText(EllesmereUI.L("Spacing"))
            spLabel:SetPoint("LEFT", pf, "TOPLEFT", SIDE_PAD, SP_ROW_Y - SLIDER_H / 2)
            spLabel:Hide()
            pf._spLabel = spLabel
            local spTrack, spValBox = BuildSliderCore(pf, SLIDER_W, 4, 12, INPUT_W, SLIDER_H, 11, SL_INPUT_A,
                -5, 20, 1,
                function() return pf._spGet and pf._spGet() or 0 end,
                function(v) if pf._spSet then pf._spSet(v) end end, true)
            spTrack:SetPoint("TOPLEFT", pf, "TOPLEFT", SLIDER_LEFT, SP_ROW_Y - 2)
            spValBox:ClearAllPoints(); spValBox:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -SIDE_PAD, SP_ROW_Y)
            spTrack:Hide(); spValBox:Hide()
            pf._spTrack = spTrack; pf._spValBox = spValBox

            -- Width % slider row (hidden unless a width-fit text element: enemy name, cast spell name, cast target); fixed range built once, reordered/repositioned per show via the seq block below.
            local W_ROW_Y = SP_ROW_Y - SLIDER_H - GAP
            local wLabel = MakeFont(pf, 12, nil, 1, 1, 1)
            wLabel:SetAlpha(0.6); wLabel:SetText(EllesmereUI.L("Width %"))
            wLabel:SetPoint("LEFT", pf, "TOPLEFT", SIDE_PAD, W_ROW_Y - SLIDER_H / 2)
            wLabel:Hide()
            pf._wLabel = wLabel
            -- Invisible hover region for the label's tooltip (FontStrings aren't mouse-interactive); SetAllPoints tracks the label through repositioning, shown/hidden with the row.
            local wHover = CreateFrame("Frame", nil, pf)
            wHover:SetFrameLevel(pf:GetFrameLevel() + 10)
            wHover:SetAllPoints(wLabel)
            wHover:EnableMouse(true)
            wHover:Hide()
            wHover:SetScript("OnEnter", function(self)
                EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.L("Maximum width the text can fill before it truncates, as a percentage of the bar."), { width = 230 })
            end)
            wHover:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            pf._wHover = wHover
            local wTrack, wValBox = BuildSliderCore(pf, SLIDER_W, 4, 12, INPUT_W, SLIDER_H, 11, SL_INPUT_A,
                10, 150, 1,
                function() return pf._wGet and pf._wGet() or 0 end,
                function(v) if pf._wSet then pf._wSet(v) end end, true)
            wTrack:SetPoint("TOPLEFT", pf, "TOPLEFT", SLIDER_LEFT, W_ROW_Y - 2)
            wValBox:ClearAllPoints(); wValBox:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -SIDE_PAD, W_ROW_Y)
            wTrack:Hide(); wValBox:Hide()
            pf._wTrack = wTrack; pf._wValBox = wValBox

            -- Store layout values for dynamic size slider rebuild + reorder
            pf._SLIDER_LEFT = SLIDER_LEFT
            pf._SLIDER_W = SLIDER_W
            pf._X_ROW_Y = X_ROW_Y
            pf._Y_ROW_Y = Y_ROW_Y
            pf._S_ROW_Y = S_ROW_Y
            pf._SP_ROW_Y = SP_ROW_Y
            pf._ROW0 = X_ROW_Y
            pf._ROW_STEP = SLIDER_H + GAP

            -- Growth direction row (shown only for topleft/topright slots)
            local GROWTH_ROW_H = 22
            local G_ROW_Y = S_ROW_Y - SLIDER_H - GAP
            pf._G_ROW_Y = G_ROW_Y
            pf._GROWTH_ROW_H = GROWTH_ROW_H

            local gLabel = MakeFont(pf, 12, nil, 1, 1, 1)
            gLabel:SetAlpha(0.6); gLabel:SetText(EllesmereUI.L("Grow"))
            gLabel:SetPoint("LEFT", pf, "TOPLEFT", SIDE_PAD, G_ROW_Y - GROWTH_ROW_H / 2)
            pf._gLabel = gLabel

            -- Grow direction is a standard dropdown; option list + order vary per cog (topleft vs topright), filled into these mutable tables at show time (menu invalidated to rebuild); getValue/setValue delegate to the per-show growth getter/setter.
            pf._growthValues = {}   -- key -> label
            pf._growthOrder  = {}   -- ordered keys
            -- Standard cog-popup dropdown sizing (matches BuildCogPopup's dropdown rows): 130px wide, rendered 10% smaller, right-aligned at layout time.
            local GROW_DD_W = 130
            local GROW_DD_SCALE = 0.9
            pf._GROW_DD_SCALE = GROW_DD_SCALE
            local gDD = EllesmereUI.BuildDropdownControl(pf, GROW_DD_W, pf:GetFrameLevel() + 6,
                pf._growthValues, pf._growthOrder,
                function() return pf._growthGet and pf._growthGet() or "" end,
                function(v) if pf._growthSet then pf._growthSet(v) end end)
            gDD:SetScale(GROW_DD_SCALE)
            -- Lazily-created menu parents to UIParent (scale 1); sync to the shrunk control the first time it opens.
            gDD:HookScript("OnClick", function(self)
                if self._ddMenu and not self._ddMenu._npCogScaled then
                    self._ddMenu:SetScale(GROW_DD_SCALE)
                    self._ddMenu._npCogScaled = true
                end
            end)
            gDD:Hide()
            pf._gDD = gDD

            -- Optional toggle row, anchored at layout time: takes the 4th-row slot (G_ROW_Y) with no Grow row, stacks BELOW Grow when both present (e.g. Rare/Quest Indicator on topleft/topright: Grow + Show In Instances). Wired via pf._toggleGet/Set.
            local tLabel = MakeFont(pf, 12, nil, 1, 1, 1)
            tLabel:SetAlpha(0.6)
            tLabel:SetPoint("LEFT", pf, "TOPLEFT", SIDE_PAD, G_ROW_Y - GROWTH_ROW_H / 2)
            tLabel:Hide()
            pf._tLabel = tLabel
            local tToggle, _, tToggleSnap = EllesmereUI.BuildToggleControl(pf, pf:GetFrameLevel() + 5,
                function() return pf._toggleGet and pf._toggleGet() or false end,
                function(v) if pf._toggleSet then pf._toggleSet(v) end end,
                { sizeRatio = 0.8, noAnim = true })
            tToggle:SetPoint("RIGHT", pf, "TOPRIGHT", -SIDE_PAD, G_ROW_Y - GROWTH_ROW_H / 2)
            tToggle:Hide()
            pf._tToggle = tToggle
            pf._toggleSnap = tToggleSnap

            -- Optional "Raise Strata" toggle row (own row, below Grow/Cropped Icons/Wrap so it can coexist with any on a Core Position slot); wired via pf._rsGet/pf._rsSet.
            local rsLabel = MakeFont(pf, 12, nil, 1, 1, 1)
            rsLabel:SetAlpha(0.6)
            rsLabel:SetText(EllesmereUI.L("Raise Strata"))
            rsLabel:SetPoint("LEFT", pf, "TOPLEFT", SIDE_PAD, G_ROW_Y - GROWTH_ROW_H / 2)
            rsLabel:Hide()
            pf._rsLabel = rsLabel
            -- Invisible hover region over the label for its tooltip.
            local rsHover = CreateFrame("Frame", nil, pf)
            rsHover:SetFrameLevel(pf:GetFrameLevel() + 10)
            rsHover:SetAllPoints(rsLabel)
            rsHover:EnableMouse(true)
            rsHover:Hide()
            rsHover:SetScript("OnEnter", function(self)
                EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.L("Renders this slot's element above the rest of the nameplate."), { width = 230 })
            end)
            rsHover:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            pf._rsHover = rsHover
            local rsToggle, _, rsToggleSnap = EllesmereUI.BuildToggleControl(pf, pf:GetFrameLevel() + 5,
                function() return pf._rsGet and pf._rsGet() or false end,
                function(v) if pf._rsSet then pf._rsSet(v) end end,
                { sizeRatio = 0.8, noAnim = true })
            rsToggle:SetPoint("RIGHT", pf, "TOPRIGHT", -SIDE_PAD, G_ROW_Y - GROWTH_ROW_H / 2)
            rsToggle:Hide()
            pf._rsToggle = rsToggle
            pf._rsToggleSnap = rsToggleSnap

            -- Optional "Strata" dropdown row (Core Text slots): the standard
            -- strata dropdown, static option set, positioned in the Grow/
            -- toggle band at layout time; wired via pf._strataGetFn/SetFn.
            local stLabel = MakeFont(pf, 12, nil, 1, 1, 1)
            stLabel:SetAlpha(0.6)
            stLabel:SetText(EllesmereUI.L("Strata"))
            stLabel:SetPoint("LEFT", pf, "TOPLEFT", SIDE_PAD, G_ROW_Y - GROWTH_ROW_H / 2)
            stLabel:Hide()
            pf._stLabel = stLabel
            local stDD = EllesmereUI.BuildDropdownControl(pf, GROW_DD_W, pf:GetFrameLevel() + 6,
                EllesmereUI.FRAME_STRATA_LABELS, EllesmereUI.FRAME_STRATA_ORDER_BASE,
                function() return pf._strataGetFn and pf._strataGetFn() or "MEDIUM" end,
                function(v) if pf._strataSetFn then pf._strataSetFn(v) end end)
            stDD:SetScale(GROW_DD_SCALE)
            stDD:HookScript("OnClick", function(self)
                if self._ddMenu and not self._ddMenu._npCogScaled then
                    self._ddMenu:SetScale(GROW_DD_SCALE)
                    self._ddMenu._npCogScaled = true
                end
            end)
            stDD:Hide()
            pf._stDD = stDD

            -- Optional "Cropped Icons" toggle row: gets its OWN row below data/grow rows (unlike the generic toggle) so it can coexist with Grow on aura slots; wired via pf._cropGet/Set, repositioned per show.
            local cropLabel = MakeFont(pf, 12, nil, 1, 1, 1)
            cropLabel:SetAlpha(0.6)
            cropLabel:SetText(EllesmereUI.L("Cropped Icons"))
            cropLabel:SetPoint("LEFT", pf, "TOPLEFT", SIDE_PAD, G_ROW_Y - GROWTH_ROW_H / 2)
            cropLabel:Hide()
            pf._cropLabel = cropLabel
            local cropToggle, _, cropToggleSnap = EllesmereUI.BuildToggleControl(pf, pf:GetFrameLevel() + 5,
                function() return pf._cropGet and pf._cropGet() or false end,
                function(v)
                    if pf._cropSet then pf._cropSet(v) end
                    -- The Adjust Crop slider (below) rides this toggle's state.
                    if pf._cropPctSyncDisabled then pf._cropPctSyncDisabled() end
                end,
                { sizeRatio = 0.8, noAnim = true })
            cropToggle:SetPoint("RIGHT", pf, "TOPRIGHT", -SIDE_PAD, G_ROW_Y - GROWTH_ROW_H / 2)
            cropToggle:Hide()
            pf._cropToggle = cropToggle
            pf._cropToggleSnap = cropToggleSnap

            -- Optional "Adjust Crop" slider row (own row, below Cropped Icons; wired via pf._cropPctGet/Set): per-side trim percentage, 10 = classic fixed crop. Blocked+dimmed while Cropped Icons is off (standard disabled-inline-control pattern).
            local cpLabel = MakeFont(pf, 12, nil, 1, 1, 1)
            cpLabel:SetAlpha(0.6); cpLabel:SetText(EllesmereUI.L("Adjust Crop"))
            cpLabel:Hide()
            pf._cropPctLabel = cpLabel
            local cpHover = CreateFrame("Frame", nil, pf)
            cpHover:SetFrameLevel(pf:GetFrameLevel() + 10)
            cpHover:SetAllPoints(cpLabel)
            cpHover:EnableMouse(true)
            cpHover:Hide()
            cpHover:SetScript("OnEnter", function(self)
                EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.L("How much is trimmed from the icon's top and bottom, as a percentage per side. 10% is the classic cropped look."), { width = 230 })
            end)
            cpHover:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            pf._cropPctHover = cpHover
            -- Narrower track than standard rows: "Adjust Crop" label is wider than Size/Spacing and would run under a full-width track; right edge stays aligned (track start shifts right by the same amount).
            local cpTrack, cpValBox = BuildSliderCore(pf, SLIDER_W - 26, 4, 12, INPUT_W, SLIDER_H, 11, SL_INPUT_A,
                5, 25, 1,
                function() return pf._cropPctGet and pf._cropPctGet() or 10 end,
                function(v) if pf._cropPctSet then pf._cropPctSet(v) end end, true)
            cpTrack:Hide(); cpValBox:Hide()
            pf._cropPctTrack = cpTrack; pf._cropPctValBox = cpValBox
            -- Blocking overlay for the disabled state (covers track + input).
            local cpBlock = CreateFrame("Frame", nil, pf)
            cpBlock:SetFrameLevel(pf:GetFrameLevel() + 20)
            cpBlock:EnableMouse(true)
            cpBlock:Hide()
            cpBlock:SetScript("OnEnter", function(self)
                EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Cropped Icons"))
            end)
            cpBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            pf._cropPctBlock = cpBlock
            -- Dim/undim + block per the crop toggle's current value; called on every popup show and whenever the toggle flips.
            pf._cropPctSyncDisabled = function()
                if not cpTrack:IsShown() then
                    cpBlock:Hide()
                    return
                end
                local on = pf._cropGet and pf._cropGet() and true or false
                local a = on and 1 or 0.3
                cpTrack:SetAlpha(a); cpValBox:SetAlpha(a)
                cpLabel:SetAlpha(on and 0.6 or 0.25)
                cpBlock:ClearAllPoints()
                cpBlock:SetPoint("TOPLEFT", cpTrack, "TOPLEFT", 0, 4)
                cpBlock:SetPoint("BOTTOMRIGHT", cpValBox, "BOTTOMRIGHT", 0, -4)
                cpBlock:SetShown(not on)
            end

            -- Optional "Wrap" toggle row (own row, like Cropped Icons), used by truncating text elements so it coexists with the generic toggle (e.g. health text keeps Decimal there, Wrap here); wired via pf._wrapGet/Set.
            local wrapLabel = MakeFont(pf, 12, nil, 1, 1, 1)
            wrapLabel:SetAlpha(0.6)
            wrapLabel:SetText(EllesmereUI.L("Wrap"))
            wrapLabel:SetPoint("LEFT", pf, "TOPLEFT", SIDE_PAD, G_ROW_Y - GROWTH_ROW_H / 2)
            wrapLabel:Hide()
            pf._wrapLabel = wrapLabel
            -- Invisible hover region over the Wrap label for its tooltip (see the Width % hover above); tracks the label, shown/hidden with the row.
            local wrapHover = CreateFrame("Frame", nil, pf)
            wrapHover:SetFrameLevel(pf:GetFrameLevel() + 10)
            wrapHover:SetAllPoints(wrapLabel)
            wrapHover:EnableMouse(true)
            wrapHover:Hide()
            wrapHover:SetScript("OnEnter", function(self)
                EllesmereUI.ShowWidgetTooltip(self, pf._wrapTip and EllesmereUI.L(pf._wrapTip) or EllesmereUI.L("Lets long text wrap onto a second line instead of being cut off."), { width = 230 })
            end)
            wrapHover:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            pf._wrapHover = wrapHover
            local wrapToggle, _, wrapToggleSnap = EllesmereUI.BuildToggleControl(pf, pf:GetFrameLevel() + 5,
                function() return pf._wrapGet and pf._wrapGet() or false end,
                function(v) if pf._wrapSet then pf._wrapSet(v) end end,
                { sizeRatio = 0.8, noAnim = true })
            wrapToggle:SetPoint("RIGHT", pf, "TOPRIGHT", -SIDE_PAD, G_ROW_Y - GROWTH_ROW_H / 2)
            wrapToggle:Hide()
            pf._wrapToggle = wrapToggle
            pf._wrapToggleSnap = wrapToggleSnap

            -- Optional second generic toggle row (own row, below Wrap), for an
            -- element that needs one more switch than the toggle row gives it
            -- (e.g. Rare/Quest + Faction); wired via pf._toggle2Get/Set, label per show.
            local t2Label = MakeFont(pf, 12, nil, 1, 1, 1)
            t2Label:SetAlpha(0.6)
            t2Label:SetPoint("LEFT", pf, "TOPLEFT", SIDE_PAD, G_ROW_Y - GROWTH_ROW_H / 2)
            t2Label:Hide()
            pf._t2Label = t2Label
            local t2Toggle, _, t2ToggleSnap = EllesmereUI.BuildToggleControl(pf, pf:GetFrameLevel() + 5,
                function() return pf._toggle2Get and pf._toggle2Get() or false end,
                function(v) if pf._toggle2Set then pf._toggle2Set(v) end end,
                { sizeRatio = 0.8, noAnim = true })
            t2Toggle:SetPoint("RIGHT", pf, "TOPRIGHT", -SIDE_PAD, G_ROW_Y - GROWTH_ROW_H / 2)
            t2Toggle:Hide()
            pf._t2Toggle = t2Toggle
            pf._t2ToggleSnap = t2ToggleSnap

            -- Optional second dropdown row (own row, below the second toggle),
            -- built like Grow; values/label per show, via pf._dd2Get/Set.
            local d2Label = MakeFont(pf, 12, nil, 1, 1, 1)
            d2Label:SetAlpha(0.6)
            d2Label:SetPoint("LEFT", pf, "TOPLEFT", SIDE_PAD, G_ROW_Y - GROWTH_ROW_H / 2)
            d2Label:Hide()
            pf._d2Label = d2Label
            pf._dd2Values = {}
            pf._dd2Order  = {}
            local d2DD = EllesmereUI.BuildDropdownControl(pf, GROW_DD_W, pf:GetFrameLevel() + 6,
                pf._dd2Values, pf._dd2Order,
                function() return pf._dd2Get and pf._dd2Get() or "" end,
                function(v) if pf._dd2Set then pf._dd2Set(v) end end)
            d2DD:SetScale(GROW_DD_SCALE)
            d2DD:HookScript("OnClick", function(self)
                if self._ddMenu and not self._ddMenu._npCogScaled then
                    self._ddMenu:SetScale(GROW_DD_SCALE)
                    self._ddMenu._npCogScaled = true
                end
            end)
            d2DD:Hide()
            pf._d2DD = d2DD

            -- Layout constants stored for height calc
            pf._TOP_PAD = TOP_PAD; pf._TITLE_H = TITLE_H; pf._TITLE_GAP = TITLE_GAP
            pf._GAP = GAP; pf._SLIDER_H = SLIDER_H; pf._SIDE_PAD = SIDE_PAD
            pf._POPUP_W = POPUP_W

            -- Close on click outside
            local wasDown = false
            pf._clickOutside = function(self, dt)
                local down = IsMouseButtonDown("LeftButton")
                if down and not wasDown then
                    -- The Grow/Strata/second dropdown menus float outside this popup's rect; a click there must not count as click-outside.
                    local m = self._gDD and self._gDD._ddMenu
                    local m2 = self._stDD and self._stDD._ddMenu
                    local m3 = self._d2DD and self._d2DD._ddMenu
                    local overMenu = (m and m:IsShown() and m:IsMouseOver())
                        or (m2 and m2:IsShown() and m2:IsMouseOver())
                        or (m3 and m3:IsShown() and m3:IsMouseOver())
                    if not self:IsMouseOver() and not (cogPopupOwner and cogPopupOwner:IsMouseOver()) and not overMenu then
                        self:Hide()
                    end
                end
                wasDown = down
            end

            pf:SetScript("OnHide", function(self)
                self:SetScript("OnUpdate", nil)
                local owner = cogPopupOwner
                cogPopupOwner = nil
                -- MakeCogIcon/MakeTextCogIcon buttons have no _euiCogState.
                if owner and owner._euiCogState then owner._euiCogState()
                elseif owner then owner:SetAlpha(0.4) end
            end)

            if EllesmereUI._mainFrame then
                EllesmereUI._mainFrame:HookScript("OnHide", function()
                    if pf:IsShown() then pf:Hide() end
                end)
            end

            cogPopup = pf
        end

        -- Toggle off if same icon clicked again
        if cogPopupOwner == anchorBtn and cogPopup:IsShown() then
            cogPopup:Hide()
            return
        end

        -- Wire getters/setters
        cogPopup._xGet = opts.xGet; cogPopup._xSet = opts.xSet
        cogPopup._yGet = opts.yGet; cogPopup._ySet = opts.ySet
        cogPopup._titleFS:SetText(EllesmereUI.L(opts.title))
        local prevOwner = cogPopupOwner
        cogPopupOwner = anchorBtn
        if prevOwner and prevOwner._euiCogState then prevOwner._euiCogState() end

        -- Show/hide size row and adjust height
        local hasSize = opts.sizeGet ~= nil
        local hasWidth = opts.widthGet ~= nil
        local hasSpacing = opts.spacingGet ~= nil
        local hasGrowth = opts.growthGet ~= nil
        local hasToggle = opts.toggleGet ~= nil
        local hasCrop = opts.cropGet ~= nil
        local hasWrap = opts.wrapGet ~= nil
        local hasToggle2 = opts.toggle2Get ~= nil
        local hasDropdown2 = opts.dropdown2Get ~= nil
        local hasRaiseStrata = opts.raiseStrataGet ~= nil
        local hasStrata = opts.strataGet ~= nil
        local hasCropPct = opts.cropPctGet ~= nil
        if hasSize then
            -- Rebuild size slider if range changed
            local sStep = opts.sizeStep or 1
            if cogPopup._curMin ~= opts.sizeMin or cogPopup._curMax ~= opts.sizeMax or cogPopup._curStep ~= sStep then
                if cogPopup._sTrack then cogPopup._sTrack:Hide(); cogPopup._sTrack:SetParent(nil) end
                if cogPopup._sValBox then cogPopup._sValBox:Hide(); cogPopup._sValBox:SetParent(nil) end
                local sTrack, sValBox = EllesmereUI.BuildSliderCore(cogPopup, cogPopup._SLIDER_W, 4, 12, 34, 24, 11, EllesmereUI.SL_INPUT_A,
                    opts.sizeMin, opts.sizeMax, sStep,
                    function() return cogPopup._sGet and cogPopup._sGet() or 0 end,
                    function(v) if cogPopup._sSet then cogPopup._sSet(v) end end, true)
                sTrack:ClearAllPoints(); sTrack:SetPoint("TOPLEFT", cogPopup, "TOPLEFT", cogPopup._SLIDER_LEFT, cogPopup._S_ROW_Y - (cogPopup._SLIDER_H - 20) / 2)
                sValBox:ClearAllPoints(); sValBox:SetPoint("TOPRIGHT", cogPopup, "TOPRIGHT", -cogPopup._SIDE_PAD, cogPopup._S_ROW_Y)
                cogPopup._sTrack = sTrack; cogPopup._sValBox = sValBox
                cogPopup._curMin = opts.sizeMin; cogPopup._curMax = opts.sizeMax; cogPopup._curStep = sStep
            end
            cogPopup._sGet = opts.sizeGet; cogPopup._sSet = opts.sizeSet
            cogPopup._sLabel:SetText(opts.sizeLabel or EllesmereUI.L("Size"))
            cogPopup._sLabel:Show()
            if cogPopup._sTrack then cogPopup._sTrack:Show() end
            if cogPopup._sValBox then cogPopup._sValBox:Show() end
        else
            cogPopup._sLabel:Hide()
            if cogPopup._sTrack then cogPopup._sTrack:Hide() end
            if cogPopup._sValBox then cogPopup._sValBox:Hide() end
        end

        -- Show/hide spacing row
        if hasSpacing then
            cogPopup._spGet = opts.spacingGet
            cogPopup._spSet = opts.spacingSet
            cogPopup._spLabel:Show()
            cogPopup._spTrack:Show()
            cogPopup._spValBox:Show()
        else
            cogPopup._spGet = nil
            cogPopup._spSet = nil
            cogPopup._spLabel:Hide()
            cogPopup._spTrack:Hide()
            cogPopup._spValBox:Hide()
        end

        -- Show/hide width % row
        if hasWidth then
            cogPopup._wGet = opts.widthGet
            cogPopup._wSet = opts.widthSet
            cogPopup._wLabel:SetText(EllesmereUI.L(opts.widthLabel or "Width %"))
            cogPopup._wLabel:Show()
            cogPopup._wTrack:Show()
            cogPopup._wValBox:Show()
            if cogPopup._wHover then cogPopup._wHover:Show() end
        else
            cogPopup._wGet = nil
            cogPopup._wSet = nil
            cogPopup._wLabel:Hide()
            cogPopup._wTrack:Hide()
            cogPopup._wValBox:Hide()
            if cogPopup._wHover then cogPopup._wHover:Hide() end
        end

        -- Show/hide growth row (a dropdown)
        if hasGrowth then
            cogPopup._growthGet = opts.growthGet
            cogPopup._growthSet = opts.growthSet
            -- Refill the dropdown's option map + order from this cog's values (mutated in place so captured tables stay current).
            local vals = opts.growthValues  -- { { value, label }, ... }
            wipe(cogPopup._growthValues)
            wipe(cogPopup._growthOrder)
            if vals then
                for _, entry in ipairs(vals) do
                    cogPopup._growthValues[entry.value] = entry.label
                    cogPopup._growthOrder[#cogPopup._growthOrder + 1] = entry.value
                end
            end
            if cogPopup._gDD then
                -- Rebuild the menu from the refilled tables and refresh the label.
                if cogPopup._gDD._invalidateMenu then cogPopup._gDD._invalidateMenu() end
                cogPopup._gDD:Show()
            end
            -- growthLabel: an element can reuse this dropdown row for its own setting.
            cogPopup._gLabel:SetText(EllesmereUI.L(opts.growthLabel or "Grow"))
            cogPopup._gLabel:Show()
        else
            cogPopup._growthGet = nil
            cogPopup._growthSet = nil
            cogPopup._gLabel:Hide()
            if cogPopup._gDD then cogPopup._gDD:Hide() end
        end

        -- Show/hide toggle row (shares the G_ROW_Y slot with Grow)
        if hasToggle then
            cogPopup._toggleGet = opts.toggleGet
            cogPopup._toggleSet = opts.toggleSet
            cogPopup._tLabel:SetText(EllesmereUI.L(opts.toggleLabel or ""))
            cogPopup._tLabel:Show()
            cogPopup._tToggle:Show()
            if cogPopup._toggleSnap then cogPopup._toggleSnap() end
        else
            cogPopup._toggleGet = nil
            cogPopup._toggleSet = nil
            cogPopup._tLabel:Hide()
            cogPopup._tToggle:Hide()
        end

        -- Show/hide Cropped Icons row (its own row, below Grow when present)
        if hasCrop then
            cogPopup._cropGet = opts.cropGet
            cogPopup._cropSet = opts.cropSet
            cogPopup._cropLabel:Show()
            cogPopup._cropToggle:Show()
            if cogPopup._cropToggleSnap then cogPopup._cropToggleSnap() end
        else
            cogPopup._cropGet = nil
            cogPopup._cropSet = nil
            cogPopup._cropLabel:Hide()
            cogPopup._cropToggle:Hide()
        end

        -- Show/hide Adjust Crop row (slider, directly below Cropped Icons)
        if hasCropPct then
            cogPopup._cropPctGet = opts.cropPctGet
            cogPopup._cropPctSet = opts.cropPctSet
            cogPopup._cropPctLabel:Show()
            cogPopup._cropPctTrack:Show()
            cogPopup._cropPctValBox:Show()
            cogPopup._cropPctHover:Show()
        else
            cogPopup._cropPctGet = nil
            cogPopup._cropPctSet = nil
            cogPopup._cropPctLabel:Hide()
            cogPopup._cropPctTrack:Hide()
            cogPopup._cropPctValBox:Hide()
            cogPopup._cropPctHover:Hide()
            cogPopup._cropPctBlock:Hide()
        end

        -- Show/hide Wrap row (its own row, like Cropped Icons)
        if hasWrap then
            cogPopup._wrapGet = opts.wrapGet
            cogPopup._wrapSet = opts.wrapSet
            -- wrapLabel/wrapTooltip: an element can reuse this toggle row for its own setting.
            cogPopup._wrapLabel:SetText(EllesmereUI.L(opts.wrapLabel or "Wrap"))
            cogPopup._wrapTip = opts.wrapTooltip
            cogPopup._wrapLabel:Show()
            cogPopup._wrapToggle:Show()
            if cogPopup._wrapToggleSnap then cogPopup._wrapToggleSnap() end
            if cogPopup._wrapHover then cogPopup._wrapHover:Show() end
        else
            cogPopup._wrapGet = nil
            cogPopup._wrapSet = nil
            cogPopup._wrapLabel:Hide()
            cogPopup._wrapToggle:Hide()
            if cogPopup._wrapHover then cogPopup._wrapHover:Hide() end
        end

        -- Show/hide the second toggle row
        if hasToggle2 then
            cogPopup._toggle2Get = opts.toggle2Get
            cogPopup._toggle2Set = opts.toggle2Set
            cogPopup._t2Label:SetText(EllesmereUI.L(opts.toggle2Label or ""))
            cogPopup._t2Label:Show()
            cogPopup._t2Toggle:Show()
            if cogPopup._t2ToggleSnap then cogPopup._t2ToggleSnap() end
        else
            cogPopup._toggle2Get = nil
            cogPopup._toggle2Set = nil
            cogPopup._t2Label:Hide()
            cogPopup._t2Toggle:Hide()
        end

        -- Show/hide the second dropdown row ({ { value, label }, ... } like Grow)
        if hasDropdown2 then
            cogPopup._dd2Get = opts.dropdown2Get
            cogPopup._dd2Set = opts.dropdown2Set
            wipe(cogPopup._dd2Values)
            wipe(cogPopup._dd2Order)
            for _, entry in ipairs(opts.dropdown2Values or {}) do
                cogPopup._dd2Values[entry.value] = entry.label
                cogPopup._dd2Order[#cogPopup._dd2Order + 1] = entry.value
            end
            if cogPopup._d2DD._invalidateMenu then cogPopup._d2DD._invalidateMenu() end
            cogPopup._d2DD:Show()
            cogPopup._d2Label:SetText(EllesmereUI.L(opts.dropdown2Label or ""))
            cogPopup._d2Label:Show()
        else
            cogPopup._dd2Get = nil
            cogPopup._dd2Set = nil
            cogPopup._d2Label:Hide()
            cogPopup._d2DD:Hide()
        end

        -- Show/hide Raise Strata row (its own row, below all other toggles)
        if hasRaiseStrata then
            cogPopup._rsGet = opts.raiseStrataGet
            cogPopup._rsSet = opts.raiseStrataSet
            cogPopup._rsLabel:Show()
            cogPopup._rsToggle:Show()
            if cogPopup._rsToggleSnap then cogPopup._rsToggleSnap() end
            if cogPopup._rsHover then cogPopup._rsHover:Show() end
        else
            cogPopup._rsGet = nil
            cogPopup._rsSet = nil
            cogPopup._rsLabel:Hide()
            cogPopup._rsToggle:Hide()
            if cogPopup._rsHover then cogPopup._rsHover:Hide() end
        end

        -- Show/hide Strata row (standard strata dropdown, its own row)
        if hasStrata then
            cogPopup._strataGetFn = opts.strataGet
            cogPopup._strataSetFn = opts.strataSet
            if cogPopup._stDD then
                -- Refresh the selected-value label for this cog's getter.
                if cogPopup._stDD._invalidateMenu then cogPopup._stDD._invalidateMenu() end
                cogPopup._stDD:Show()
            end
            cogPopup._stLabel:Show()
        else
            cogPopup._strataGetFn = nil
            cogPopup._strataSetFn = nil
            cogPopup._stLabel:Hide()
            if cogPopup._stDD then cogPopup._stDD:Hide() end
        end

        -- Row order: cogs passing sizeFirst (core position/core text) put Size at the top; others keep X, Y, Size, with Spacing (if present) following Size. Grow/toggle sit directly after the last data row, repositioned each show so they slide down when Spacing appears.
        do
            local p = cogPopup
            local SH, SLEFT, SPAD = p._SLIDER_H, p._SLIDER_LEFT, p._SIDE_PAD
            local GRH = p._GROWTH_ROW_H
            local function rowY(i) return p._ROW0 - (i - 1) * p._ROW_STEP end
            local function anchorRow(lbl, track, valBox, ry)
                lbl:ClearAllPoints();  lbl:SetPoint("LEFT", p, "TOPLEFT", SPAD, ry - SH / 2)
                if track  then track:ClearAllPoints();  track:SetPoint("TOPLEFT", p, "TOPLEFT", SLEFT, ry - 2) end
                if valBox then valBox:ClearAllPoints(); valBox:SetPoint("TOPRIGHT", p, "TOPRIGHT", -SPAD, ry) end
            end
            -- Width % is intentionally NOT in this data-row sequence -- it's repositioned to the very bottom (below Wrap) further down, so it never sits between Size and X/Y.
            local seq = {}
            if hasSize and opts.sizeFirst then
                seq[#seq + 1] = { p._sLabel, p._sTrack, p._sValBox }
                if hasSpacing then seq[#seq + 1] = { p._spLabel, p._spTrack, p._spValBox } end
                seq[#seq + 1] = { p._xLabel, p._xTrack, p._xValBox }
                seq[#seq + 1] = { p._yLabel, p._yTrack, p._yValBox }
            else
                seq[#seq + 1] = { p._xLabel, p._xTrack, p._xValBox }
                seq[#seq + 1] = { p._yLabel, p._yTrack, p._yValBox }
                if hasSize    then seq[#seq + 1] = { p._sLabel, p._sTrack, p._sValBox } end
                if hasSpacing then seq[#seq + 1] = { p._spLabel, p._spTrack, p._spValBox } end
            end
            for i, r in ipairs(seq) do
                anchorRow(r[1], r[2], r[3], rowY(i))
            end
            -- Growth/toggle rows sit directly after the data rows. A cog can pass BOTH (e.g. Rare/Quest Indicator on topleft/right: Grow + Show In Instances) -- the toggle then takes the row BELOW Grow.
            local nextY = rowY(#seq + 1)
            p._gLabel:ClearAllPoints()
            p._gLabel:SetPoint("LEFT", p, "TOPLEFT", SPAD, nextY - GRH / 2)
            if p._gDD then
                -- Right-aligned like standard cog dropdowns; offsets divided by the control's scale so the scaled frame lands flush-right and vertically centered.
                local ds = p._GROW_DD_SCALE or 1
                p._gDD:ClearAllPoints()
                p._gDD:SetPoint("RIGHT", p, "TOPRIGHT", -SPAD / ds, (nextY - GRH / 2) / ds)
            end
            local toggleY = hasGrowth and rowY(#seq + 2) or nextY
            p._tLabel:ClearAllPoints()
            p._tLabel:SetPoint("LEFT", p, "TOPLEFT", SPAD, toggleY - GRH / 2)
            p._tToggle:ClearAllPoints()
            p._tToggle:SetPoint("RIGHT", p, "TOPRIGHT", -SPAD, toggleY - GRH / 2)
            -- Second toggle: directly below the first, so related switches sit together.
            local t2Y = rowY(#seq + 1 + (hasGrowth and 1 or 0) + (hasToggle and 1 or 0))
            p._t2Label:ClearAllPoints()
            p._t2Label:SetPoint("LEFT", p, "TOPLEFT", SPAD, t2Y - GRH / 2)
            p._t2Toggle:ClearAllPoints()
            p._t2Toggle:SetPoint("RIGHT", p, "TOPRIGHT", -SPAD, t2Y - GRH / 2)
            -- Strata dropdown row: last row of the Grow/toggle band.
            local strataY = rowY(#seq + 1 + (hasGrowth and 1 or 0) + (hasToggle and 1 or 0) + (hasToggle2 and 1 or 0))
            p._stLabel:ClearAllPoints()
            p._stLabel:SetPoint("LEFT", p, "TOPLEFT", SPAD, strataY - GRH / 2)
            if p._stDD then
                local sds = p._GROW_DD_SCALE or 1
                p._stDD:ClearAllPoints()
                p._stDD:SetPoint("RIGHT", p, "TOPRIGHT", -SPAD / sds, (strataY - GRH / 2) / sds)
            end
            -- Rows consumed by the Grow/toggle/second toggle/Strata band (0-4).
            local extraRows = (hasGrowth and 1 or 0) + (hasToggle and 1 or 0) + (hasToggle2 and 1 or 0) + (hasStrata and 1 or 0)
            -- Cropped Icons sits in its own row below the Grow/toggle band, else directly after the data rows.
            local cropY = rowY(#seq + 1 + extraRows)
            p._cropLabel:ClearAllPoints()
            p._cropLabel:SetPoint("LEFT", p, "TOPLEFT", SPAD, cropY - GRH / 2)
            p._cropToggle:ClearAllPoints()
            p._cropToggle:SetPoint("RIGHT", p, "TOPRIGHT", -SPAD, cropY - GRH / 2)
            -- Adjust Crop sits directly below Cropped Icons; anchorRow handles label+track+input box, then the disabled sync dims/blocks it per the toggle's state.
            if hasCropPct then
                -- Manual anchoring instead of anchorRow: track starts 26px further right (built 26px narrower) so the wider "Adjust Crop" label never runs underneath, right edge stays aligned with other rows.
                local cpy = rowY(#seq + 2 + extraRows)
                p._cropPctLabel:ClearAllPoints()
                p._cropPctLabel:SetPoint("LEFT", p, "TOPLEFT", SPAD, cpy - SH / 2)
                p._cropPctTrack:ClearAllPoints()
                p._cropPctTrack:SetPoint("TOPLEFT", p, "TOPLEFT", SLEFT + 26, cpy - 2)
                p._cropPctValBox:ClearAllPoints()
                p._cropPctValBox:SetPoint("TOPRIGHT", p, "TOPRIGHT", -SPAD, cpy)
                if p._cropPctSyncDisabled then p._cropPctSyncDisabled() end
            end
            -- Wrap sits in its own row, like Cropped Icons: below the Grow/toggle band when present, else after the data rows (no cog uses both, so they never collide).
            local wrapY = rowY(#seq + 1 + extraRows)
            p._wrapLabel:ClearAllPoints()
            p._wrapLabel:SetPoint("LEFT", p, "TOPLEFT", SPAD, wrapY - GRH / 2)
            p._wrapToggle:ClearAllPoints()
            p._wrapToggle:SetPoint("RIGHT", p, "TOPRIGHT", -SPAD, wrapY - GRH / 2)
            -- Second dropdown: its own row below Cropped Icons/Adjust Crop/Wrap.
            local d2RowIndex = #seq + 1 + extraRows
            if hasCrop or hasWrap then d2RowIndex = d2RowIndex + 1 end
            if hasCropPct then d2RowIndex = d2RowIndex + 1 end
            local d2Y = rowY(d2RowIndex)
            p._d2Label:ClearAllPoints()
            p._d2Label:SetPoint("LEFT", p, "TOPLEFT", SPAD, d2Y - GRH / 2)
            local d2s = p._GROW_DD_SCALE or 1
            p._d2DD:ClearAllPoints()
            p._d2DD:SetPoint("RIGHT", p, "TOPRIGHT", -SPAD / d2s, (d2Y - GRH / 2) / d2s)
            -- Raise Strata sits in its own row, below the Grow/toggle band and Cropped Icons when present; Core Position cogs never use Wrap or Width %, so no collision there.
            if hasRaiseStrata then
                local rsRowIndex = #seq + 1 + extraRows
                if hasCrop or hasWrap then rsRowIndex = rsRowIndex + 1 end
                if hasCropPct then rsRowIndex = rsRowIndex + 1 end
                if hasDropdown2 then rsRowIndex = rsRowIndex + 1 end
                local rsY = rowY(rsRowIndex)
                p._rsLabel:ClearAllPoints()
                p._rsLabel:SetPoint("LEFT", p, "TOPLEFT", SPAD, rsY - GRH / 2)
                p._rsToggle:ClearAllPoints()
                p._rsToggle:SetPoint("RIGHT", p, "TOPRIGHT", -SPAD, rsY - GRH / 2)
            end
            -- Width % is the very last row, below Wrap (and the Grow/toggle band/Cropped Icons when present); stays a slider row, so anchorRow handles label+track+box.
            if hasWidth then
                local widthRowIndex = #seq + 1 + extraRows
                if hasCrop or hasWrap then widthRowIndex = widthRowIndex + 1 end
                if hasCropPct then widthRowIndex = widthRowIndex + 1 end
                if hasDropdown2 then widthRowIndex = widthRowIndex + 1 end
                anchorRow(p._wLabel, p._wTrack, p._wValBox, rowY(widthRowIndex))
            end
        end

        -- Compute height based on visible rows
        do
            local p = cogPopup
            local rowH = p._SLIDER_H
            local gap  = p._GAP
            local rows = 2  -- X + Y always present
            if hasSize   then rows = rows + 1 end
            if hasGrowth then rows = rows + 1 end
            local h = p._TOP_PAD + p._TITLE_H + p._TITLE_GAP
            for r = 1, rows do
                h = h + gap + (r < rows and rowH or p._GROWTH_ROW_H)
            end
            -- Recalculated cleanly below (the loop above is approximate).
            h = p._TOP_PAD + p._TITLE_H + p._TITLE_GAP
                + gap + rowH   -- X
                + gap + rowH   -- Y
            if hasSize    then h = h + gap + rowH end
            if hasWidth   then h = h + gap + rowH end
            if hasSpacing then h = h + gap + rowH end
            if hasGrowth then h = h + gap + p._GROWTH_ROW_H end
            -- Toggle gets its own row (stacks below Grow when both present).
            if hasToggle then h = h + gap + p._GROWTH_ROW_H end
            -- Cropped Icons always occupies its own extra row.
            if hasCrop then h = h + gap + p._GROWTH_ROW_H end
            -- Adjust Crop (slider) occupies its own extra row below it.
            if hasCropPct then h = h + gap + rowH end
            -- Wrap occupies its own extra row.
            if hasWrap then h = h + gap + p._GROWTH_ROW_H end
            -- Second toggle gets its own row (below the first toggle).
            if hasToggle2 then h = h + gap + p._GROWTH_ROW_H end
            -- Second dropdown occupies its own extra row.
            if hasDropdown2 then h = h + gap + p._GROWTH_ROW_H end
            -- Raise Strata occupies its own extra row.
            if hasRaiseStrata then h = h + gap + p._GROWTH_ROW_H end
            -- Strata dropdown occupies its own extra row.
            if hasStrata then h = h + gap + p._GROWTH_ROW_H end
            h = h + p._TOP_PAD
            cogPopup:SetHeight(h)
        end

        -- Anchor above the icon
        cogPopup:ClearAllPoints()
        cogPopup:SetPoint("BOTTOM", anchorBtn, "TOP", 0, 6)

        -- Slide-up animation
        cogPopup:SetAlpha(0)
        cogPopup:Show()
        local elapsed = 0
        local ANIM_DUR = 0.15
        cogPopup:SetScript("OnUpdate", function(self, dt)
            elapsed = elapsed + dt
            local t = math.min(elapsed / ANIM_DUR, 1)
            self:SetAlpha(t)
            self:ClearAllPoints()
            self:SetPoint("BOTTOM", anchorBtn, "TOP", 0, 6 + (-8 * (1 - t)))
            if t >= 1 then
                self:SetScript("OnUpdate", self._clickOutside)
            end
        end)

        EllesmereUI:RefreshPage()
    end

    local DISABLED_TIP = "This option requires an aura or indicator to be assigned"

    -- Per-kind slot Tracked Auras popup (12.1). Filter composition is INTERNAL (debuffs=Default, dcc=CC+Default, cc=CC; Default is Blizzard's
    -- nameplateShowPersonal curation): holds only Show All Debuffs (debuffs only) + INCLUDED/EXCLUDED lists (debuff side shared by debuffs/dcc; cc has its own pair). Storage/engine groups live in the containers file (ns.NPF_Root/Include/Exclude, NPC_ReloadAll).
    local NPF_KIND_TITLES = {
        debuffs = "Debuff Custom Spell IDs", cc = "CC Custom Spell IDs", dcc = "Debuffs + CC Custom Spell IDs",
    }
    local function ShowFilterPopup(kind)
        local root = ns.NPF_Root and ns.NPF_Root()
        if not root then return end
        -- List side + Show All availability: only debuffs has Show All; dcc is always CC+Default, cc is always CC.
        local side = (kind == "cc") and "cc" or "debuff"
        -- Any-caster OPT-OUTS for INCLUDED entries: default is Only My Casts (npincmine); flagged ids ride npinc.
        local function AnyMap()
            return ns.NPF_IncludeAny and ns.NPF_IncludeAny(side)
        end
        local function Reload()
            if ns.NPC_ReloadAll then ns.NPC_ReloadAll() end
        end
        EllesmereUI.ShowTrackedAurasPopup({
            eyebrow = EllesmereUI.L("NAMEPLATE AURA FILTERS"),
            title = NPF_KIND_TITLES[kind] or "Filters",
            fontPath = (EllesmereUI.GetFontPath("nameplates")) or DBVal("font"),
            includeGet = function() return ns.NPF_Include and ns.NPF_Include(side) end,
            excludeGet = function() return ns.NPF_Exclude and ns.NPF_Exclude(side) end,
            includePrompt = EllesmereUI.L("Enter the spell ID to always show on nameplates."),
            excludePrompt = EllesmereUI.L("Enter the spell ID to exclude from nameplates."),
            includeMine = { anyGet = AnyMap },
            -- Fresh adds default to Only My Casts; a spell migrating to the exclude list drops any stale flag.
            onAdd = function(id)
                local am = AnyMap()
                if am then am[id] = nil end
            end,
            onChanged = Reload,
            showAll = (kind == "debuffs") and {
                label = EllesmereUI.L("Show All Debuffs"),
                get = function() return root.debuffs and root.debuffs.all end,
                set = function(v)
                    root.debuffs = root.debuffs or {}
                    root.debuffs.all = v
                    Reload()
                end,
            } or nil,
        })
    end

    local function MakeCogIcon(row, regionKey, posKey, slotLabel)
        local rgn = row[regionKey]
        local btn = CreateFrame("Button", nil, rgn)
        btn:SetSize(26, 26)
        btn:SetPoint("RIGHT", rgn._control, "LEFT", -8, 0)
        rgn._lastInline = btn
        -- The core eyes anchor to THIS, not _lastInline: the tracked-auras
        -- link below becomes _lastInline but is HIDDEN for the raid marker
        -- and rare/quest slots (the only slots the eyes land on), and a
        -- hidden frame keeps its width -- anchoring left of it stranded
        -- the eye far from the cog.
        rgn._coreCogBtn = btn
        btn:SetFrameLevel(rgn:GetFrameLevel() + 5)
        btn:SetAlpha(0.4)
        local tex = btn:CreateTexture(nil, "OVERLAY")
        tex:SetAllPoints()
        tex:SetTexture(EllesmereUI.RESIZE_ICON)
        btn:SetScript("OnEnter", function(self)
            if CorePosOffDisabled(posKey) then
                EllesmereUI.ShowWidgetTooltip(self, DISABLED_TIP)
            else
                self:SetAlpha(0.7)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            EllesmereUI.HideWidgetTooltip()
            if cogPopupOwner ~= self then self:SetAlpha(CorePosOffDisabled(posKey) and 0.15 or 0.4) end
        end)
        btn:SetScript("OnClick", function(self)
            if CorePosOffDisabled(posKey) then return end
            local sizeKey = posKey .. "SlotSize"
            local growthKey = posKey .. "SlotGrowth"
            local growthValues
            if posKey == "topleft" then
                growthValues = {
                    { value = "left",  label = "Left"  },
                    { value = "right", label = "Right" },
                    { value = "up",    label = "Up"    },
                }
            elseif posKey == "topright" then
                growthValues = {
                    { value = "right", label = "Right" },
                    { value = "left",  label = "Left"  },
                    { value = "up",    label = "Up"    },
                }
            end
            local opts = {
                title = EllesmereUI.Lf("%1$s Slot Settings", EllesmereUI.L(slotLabel)),
                xGet = function() return CorePosXGet(posKey) end,
                xSet = function(v) CorePosXSet(posKey, v) end,
                yGet = function() return CorePosYGet(posKey) end,
                ySet = function(v) CorePosYSet(posKey, v) end,
                sizeGet = function() return DBVal(sizeKey) or defaults[sizeKey] end,
                sizeSet = function(v) DB()[sizeKey] = v; RefreshAllSlots(); UpdatePreview() end,
                sizeMin = 10, sizeMax = 50,
                sizeFirst = true,
            }
            if growthValues then
                opts.growthGet    = function() return DBVal(growthKey) or defaults[growthKey] end
                opts.growthSet    = function(v) DB()[growthKey] = v; RefreshAllSlots(); UpdatePreview() end
                opts.growthValues = growthValues
            end
            -- Spacing + Cropped Icons: only for multi-icon aura elements (debuffs/buffs/CCs); both map the slot's assigned element to its per-element key.
            local element = GetElementAtPosition(posKey)
            local spacingKey, cropKey
            if element == "debuffs" then
                spacingKey = "debuffSpacing"; cropKey = "debuffCropIcons"
            elseif element == "buffs" then
                spacingKey = "buffSpacing"; cropKey = "buffCropIcons"
            elseif element == "ccs" then
                spacingKey = "ccSpacing"; cropKey = "ccCropIcons"
            end
            if spacingKey then
                opts.spacingGet = function() return DBVal(spacingKey) or defaults[spacingKey] end
                opts.spacingSet = function(v) DB()[spacingKey] = v; RefreshAllSlots(); UpdatePreview() end
            end
            if cropKey then
                opts.cropGet = function() return DBVal(cropKey) or defaults[cropKey] end
                opts.cropSet = function(v) DB()[cropKey] = v; RefreshAllSlots(); UpdatePreview() end
                -- Adjust Crop: per-side trim percentage for the cropped mode.
                local cropPctKey = (element == "debuffs" and "debuffCropPercent")
                    or (element == "buffs" and "buffCropPercent")
                    or "ccCropPercent"
                opts.cropPctGet = function() return DBVal(cropPctKey) or 10 end
                opts.cropPctSet = function(v) DB()[cropPctKey] = v; RefreshAllSlots(); UpdatePreview() end
            end
            local borderKey
            if element == "debuffs" then
                borderKey = "hideDebuffIconBorder"
            elseif element == "buffs" then
                borderKey = "hideBuffIconBorder"
            elseif element == "ccs" then
                borderKey = "hideCCIconBorder"
            end
            -- Blizzard Style: the stock aura ring replaces the 1px border,
            -- so the toggle has nothing to switch (the page banner says why).
            if borderKey and not EllesmereUI.BlizzStyle.Get("nameplates") then
                opts.toggleLabel = "Hide Border"
                opts.toggleGet = function()
                    local v = DBVal(borderKey)
                    if v == nil then return false end
                    return v and true or false
                end
                opts.toggleSet = function(v)
                    DB()[borderKey] = v and true or false
                    -- Full settings pass: RefreshAllSlots repositions but
                    -- never re-runs ApplyAppearance, so without this the
                    -- live slot borders only catch up on plate recycle
                    -- (and the container styles ride NPC_ReloadAll).
                    if ns.RefreshAllSettings then ns.RefreshAllSettings() end
                    RefreshAllSlots()
                    UpdatePreview()
                end
            end
            -- Rare/Quest Indicator: "Show In Instances" lifts the open-world-only gates (UpdateClassification render gate + IsQuestMob's tooltip-scan gate); RefreshQuestObjective wipes quest-mob caches AND re-runs UpdateClassification everywhere.
            if element == "classification" or element == "classfaction" then
                opts.toggleLabel = "Show In Instances"
                opts.toggleGet = function() return DBVal("classificationShowInInstances") == true end
                opts.toggleSet = function(v)
                    DB().classificationShowInInstances = v and true or false
                    if ns.RefreshQuestObjective then ns.RefreshQuestObjective() end
                    UpdatePreview()
                end
            end
            -- Rare/Quest + Faction: Show In Instances (toggle row), Opposite Faction
            -- Only (second toggle row), Players Only (Wrap row), PvP Flag (Grow row).
            if element == "classfaction" then
                local function refresh()
                    RefreshAllSlots()
                    UpdatePreview()
                end
                opts.dropdown2Label = "Icon Style"
                opts.dropdown2Values = {}
                for _, k in ipairs(EllesmereUI.FACTION_ART_ORDER) do
                    opts.dropdown2Values[#opts.dropdown2Values + 1] = { value = k, label = EllesmereUI.FACTION_ART_LABELS[k] }
                end
                opts.dropdown2Get = function() return DBVal("factionStyle") or defaults.factionStyle end
                opts.dropdown2Set = function(v) DB().factionStyle = v; refresh() end
                opts.toggle2Label = "Opposite Faction Only"
                opts.toggle2Get = function() return DBVal("factionOppositeOnly") == true end
                opts.toggle2Set = function(v) DB().factionOppositeOnly = v and true or false; refresh() end
                opts.wrapLabel = "Players Only"
                opts.wrapTooltip = "Hide the faction badge on faction NPCs such as guards."
                opts.wrapGet = function() return DBVal("factionPlayersOnly") == true end
                opts.wrapSet = function(v) DB().factionPlayersOnly = v and true or false; refresh() end
                opts.growthLabel = "PvP Flag"
                opts.growthValues = {
                    { value = "dim",    label = "Dim Unflagged" },
                    { value = "only",   label = "Flagged Only"  },
                    { value = "ignore", label = "Ignore"        },
                }
                opts.growthGet = function() return DBVal("factionPvP") or defaults.factionPvP end
                opts.growthSet = function(v) DB().factionPvP = v; refresh() end
            end
            -- Faction: Opposite Faction Only (toggle row), Players Only (the Wrap row)
            -- and PvP Flag (the Grow dropdown; a single badge has nothing to grow).
            if element == "faction" then
                local function refresh()
                    RefreshAllSlots()
                    UpdatePreview()
                end
                opts.dropdown2Label = "Icon Style"
                opts.dropdown2Values = {}
                for _, k in ipairs(EllesmereUI.FACTION_ART_ORDER) do
                    opts.dropdown2Values[#opts.dropdown2Values + 1] = { value = k, label = EllesmereUI.FACTION_ART_LABELS[k] }
                end
                opts.dropdown2Get = function() return DBVal("factionStyle") or defaults.factionStyle end
                opts.dropdown2Set = function(v) DB().factionStyle = v; refresh() end
                opts.toggleLabel = "Opposite Faction Only"
                opts.toggleGet = function() return DBVal("factionOppositeOnly") == true end
                opts.toggleSet = function(v) DB().factionOppositeOnly = v and true or false; refresh() end
                opts.wrapLabel = "Players Only"
                opts.wrapTooltip = "Hide the faction badge on faction NPCs such as guards."
                opts.wrapGet = function() return DBVal("factionPlayersOnly") == true end
                opts.wrapSet = function(v) DB().factionPlayersOnly = v and true or false; refresh() end
                opts.growthLabel = "PvP Flag"
                opts.growthValues = {
                    { value = "dim",    label = "Dim Unflagged" },
                    { value = "only",   label = "Flagged Only"  },
                    { value = "ignore", label = "Ignore"        },
                }
                opts.growthGet = function() return DBVal("factionPvP") or defaults.factionPvP end
                opts.growthSet = function(v) DB().factionPvP = v; refresh() end
            end
            -- Raise Strata: bumps whatever element occupies this slot one strata level up so it renders above the rest of the plate.
            local rsKey = posKey .. "SlotRaiseStrata"
            opts.raiseStrataGet = function() return DBVal(rsKey) and true or false end
            opts.raiseStrataSet = function(v) DB()[rsKey] = v and true or false; RefreshAllSlots(); UpdatePreview() end
            ShowCogPopup(self, opts)
        end)
        EllesmereUI.RegisterWidgetRefresh(function()
            local off = CorePosOffDisabled(posKey)
            btn:SetAlpha(off and 0.15 or (cogPopupOwner == btn and 0.7 or 0.4))
        end)
        if CorePosOffDisabled(posKey) then btn:SetAlpha(0.15) end

        -- Edit Tracked Auras (slot filters): accent link left of the cog when this row holds a debuff-side aura element, opens the per-kind filter popup; refreshes on the same widget-refresh channel as the cog alpha.
            local link = CreateFrame("Button", nil, rgn)
            link:SetFrameLevel(rgn:GetFrameLevel() + 5)
            local lfp = (EllesmereUI.GetFontPath("nameplates")) or DBVal("font")
            local lfs = link:CreateFontString(nil, "OVERLAY")
            lfs:SetFont(lfp, 12, "")
            local ar, ag, ab = 1, 0.82, 0.30
            if EllesmereUI.GetAccentColor then ar, ag, ab = EllesmereUI.GetAccentColor() end
            lfs:SetTextColor(ar, ag, ab)
            lfs:SetAlpha(0.85)
            lfs:SetPoint("CENTER")
            lfs:SetText(EllesmereUI.L("Edit Tracked Auras"))
            link:SetSize(lfs:GetStringWidth() + 6, 16)
            link:SetPoint("RIGHT", btn, "LEFT", -6, 0)
            rgn._lastInline = link
            local function LinkKind()
                local el = GetElementAtPosition(posKey)
                if el == "debuffs" then return "debuffs"
                elseif el == "ccs" then return "cc"
                elseif el == "debuffsccs" then return "dcc" end
            end
            local function UpdLink()
                local k = LinkKind()
                link:SetShown(k ~= nil)
                if k then
                    -- CC slots track only CC, so the link says so.
                    lfs:SetText(EllesmereUI.L(k == "cc" and "Edit Tracked CC" or "Edit Tracked Auras"))
                    link:SetSize(lfs:GetStringWidth() + 6, 16)
                end
            end
            link:SetScript("OnEnter", function() lfs:SetAlpha(1) end)
            link:SetScript("OnLeave", function() lfs:SetAlpha(0.85) end)
            link:SetScript("OnClick", function()
                local k = LinkKind()
                if k then ShowFilterPopup(k) end
            end)
            EllesmereUI.RegisterWidgetRefresh(UpdLink)
            UpdLink()
        return btn
    end

    parent._showRowDivider = true

    -- Row 1: Top | Right
    coreRow1, h = W:DualRow(parent, y,
        { type="dropdown", text="Top",
          values = coreElementValues, order = coreElementOrder,
          getValue = function() return GetElementAtPosition("top") end,
          setValue = function(v) SetElementAtPosition("top", v); RefreshAllSlots(); optState.RefreshCoreEyes() end,
          disabled = function() return CorePosOffDisabled("top") end,
          disabledTooltip = "This option requires an aura or indicator to be assigned", rawTooltip = true,
          labelOnlyDisabled = true },
        { type="dropdown", text="Right",
          values = coreElementValues, order = coreElementOrder,
          getValue = function() return GetElementAtPosition("right") end,
          setValue = function(v) SetElementAtPosition("right", v); RefreshAllSlots(); optState.RefreshCoreEyes() end,
          disabled = function() return CorePosOffDisabled("right") end,
          disabledTooltip = "This option requires an aura or indicator to be assigned", rawTooltip = true,
          labelOnlyDisabled = true });  y = y - h
    if not EllesmereUI._prebuilding then
    InstallCoreCB(coreRow1._leftRegion,  "top")
    InstallCoreCB(coreRow1._rightRegion, "right")
    MakeCogIcon(coreRow1, "_leftRegion",  "top",      "Top")
    MakeCogIcon(coreRow1, "_rightRegion", "right",    "Right")
    end

    -- Row 2: Left | Top Right
    coreRow2, h = W:DualRow(parent, y,
        { type="dropdown", text="Left",
          values = coreElementValues, order = coreElementOrder,
          getValue = function() return GetElementAtPosition("left") end,
          setValue = function(v) SetElementAtPosition("left", v); RefreshAllSlots(); optState.RefreshCoreEyes() end,
          disabled = function() return CorePosOffDisabled("left") end,
          disabledTooltip = "This option requires an aura or indicator to be assigned", rawTooltip = true,
          labelOnlyDisabled = true },
        { type="dropdown", text="Top Right",
          values = coreElementValues, order = coreElementOrder,
          getValue = function() return GetElementAtPosition("topright") end,
          setValue = function(v) SetElementAtPosition("topright", v); RefreshAllSlots(); optState.RefreshCoreEyes() end,
          disabled = function() return CorePosOffDisabled("topright") end,
          disabledTooltip = "This option requires an aura or indicator to be assigned", rawTooltip = true,
          labelOnlyDisabled = true });  y = y - h
    if not EllesmereUI._prebuilding then
    InstallCoreCB(coreRow2._leftRegion,  "left")
    InstallCoreCB(coreRow2._rightRegion, "topright")
    MakeCogIcon(coreRow2, "_leftRegion",  "left",     "Left")
    MakeCogIcon(coreRow2, "_rightRegion", "topright", "Top Right")
    end

    -- Row 3: Top Left | Bottom
    coreRow3, h = W:DualRow(parent, y,
        { type="dropdown", text="Top Left",
          values = coreElementValues, order = coreElementOrder,
          getValue = function() return GetElementAtPosition("topleft") end,
          setValue = function(v) SetElementAtPosition("topleft", v); RefreshAllSlots(); optState.RefreshCoreEyes() end,
          disabled = function() return CorePosOffDisabled("topleft") end,
          disabledTooltip = "This option requires an aura or indicator to be assigned", rawTooltip = true,
          labelOnlyDisabled = true },
        { type="dropdown", text="Bottom",
          values = coreElementValues, order = coreElementOrder,
          getValue = function() return GetElementAtPosition("bottom") end,
          setValue = function(v) SetElementAtPosition("bottom", v); RefreshAllSlots(); optState.RefreshCoreEyes() end,
          disabled = function() return CorePosOffDisabled("bottom") end,
          disabledTooltip = "This option requires an aura or indicator to be assigned", rawTooltip = true,
          labelOnlyDisabled = true });  y = y - h
    if not EllesmereUI._prebuilding then
    InstallCoreCB(coreRow3._leftRegion,  "topleft")
    InstallCoreCB(coreRow3._rightRegion, "bottom")
    MakeCogIcon(coreRow3, "_leftRegion", "topleft", "Top Left")
    MakeCogIcon(coreRow3, "_rightRegion", "bottom", "Bottom")
    end

    -- Map each position to { row, regionKey } for eye icon anchoring
    local posToRegion = {
        top      = { coreRow1, "_leftRegion" },
        right    = { coreRow1, "_rightRegion" },
        left     = { coreRow2, "_leftRegion" },
        topright = { coreRow2, "_rightRegion" },
        topleft  = { coreRow3, "_leftRegion" },
        bottom   = { coreRow3, "_rightRegion" },
    }

    -- Eye icon that follows whichever Core Positions dropdown has "Raid Marker"
    do
        local EYE_VISIBLE   = EllesmereUI.EYE_VISIBLE_ICON
        local EYE_INVISIBLE = EllesmereUI.EYE_INVISIBLE_ICON
        local eyeBtn = CreateFrame("Button", nil, parent)
        eyeBtn:SetSize(26, 26)
        eyeBtn:SetFrameLevel(parent:GetFrameLevel() + 10)
        eyeBtn:SetAlpha(0.4)
        local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
        eyeTex:SetAllPoints()
        local function RefreshIcon()
            eyeTex:SetTexture(optState.showRaidMarkerPreview and EYE_INVISIBLE or EYE_VISIBLE)
        end
        RefreshIcon()
        eyeBtn:SetScript("OnClick", function()
            optState.showRaidMarkerPreview = not optState.showRaidMarkerPreview
            RefreshIcon()
            UpdatePreview()
        end)
        eyeBtn:SetScript("OnEnter", function(self)
            self:SetAlpha(0.7)
            EllesmereUI.ShowWidgetTooltip(self, "Show/Hide on Preview", { width = 155 })
        end)
        eyeBtn:SetScript("OnLeave", function(self)
            self:SetAlpha(0.4)
            EllesmereUI.HideWidgetTooltip()
        end)
        _refreshRaidMarkerEyePos = function()
            local rmPos = DBVal("raidMarkerPos") or defaults.raidMarkerPos
            local info = posToRegion[rmPos]
            if not info or rmPos == "none" then
                eyeBtn:Hide()
                return
            end
            local rgn = info[1][info[2]]
            eyeBtn:ClearAllPoints()
            eyeBtn:SetParent(rgn)
            -- Anchor next to the cog icon (_coreCogBtn), never _lastInline:
            -- that is the tracked-auras link, hidden-but-still-wide on the
            -- slots this eye lands on, which stranded the eye far left.
            eyeBtn:SetPoint("RIGHT", rgn._coreCogBtn or rgn._control, "LEFT", -8, 0)
            eyeBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            eyeBtn:Show()
        end
        _refreshRaidMarkerEyePos()
    end

    -- Eye icon that follows whichever Core Positions dropdown has "Rare/Quest Indicator"
    do
        local EYE_VISIBLE   = EllesmereUI.EYE_VISIBLE_ICON
        local EYE_INVISIBLE = EllesmereUI.EYE_INVISIBLE_ICON
        local eyeBtn = CreateFrame("Button", nil, parent)
        eyeBtn:SetSize(26, 26)
        eyeBtn:SetFrameLevel(parent:GetFrameLevel() + 10)
        eyeBtn:SetAlpha(0.4)
        local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
        eyeTex:SetAllPoints()
        local function RefreshIcon()
            eyeTex:SetTexture(optState.showClassificationPreview and EYE_INVISIBLE or EYE_VISIBLE)
        end
        RefreshIcon()
        eyeBtn:SetScript("OnClick", function()
            optState.showClassificationPreview = not optState.showClassificationPreview
            RefreshIcon()
            UpdatePreview()
        end)
        eyeBtn:SetScript("OnEnter", function(self)
            self:SetAlpha(0.7)
            EllesmereUI.ShowWidgetTooltip(self, "Show/Hide on Preview", { width = 155 })
        end)
        eyeBtn:SetScript("OnLeave", function(self)
            self:SetAlpha(0.4)
            EllesmereUI.HideWidgetTooltip()
        end)
        _refreshClassificationEyePos = function()
            local clPos = DBVal("classificationSlot") or defaults.classificationSlot
            local info = posToRegion[clPos]
            if not info or clPos == "none" then
                eyeBtn:Hide()
                return
            end
            local rgn = info[1][info[2]]
            eyeBtn:ClearAllPoints()
            eyeBtn:SetParent(rgn)
            -- Anchor next to the cog icon (_coreCogBtn), never _lastInline:
            -- that is the tracked-auras link, hidden-but-still-wide on the
            -- slots this eye lands on, which stranded the eye far left.
            eyeBtn:SetPoint("RIGHT", rgn._coreCogBtn or rgn._control, "LEFT", -8, 0)
            eyeBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            eyeBtn:Show()
        end
        _refreshClassificationEyePos()
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h

    -----------------------------------------------------------------------
    --  CORE TEXT POSITIONS
    -----------------------------------------------------------------------
    local coreTextHeader
    coreTextHeader, h = W:SectionHeader(parent, "CORE TEXT POSITIONS", y);  y = y - h

    -- Subtitle hint next to the section header (same style as Core Positions)
    do
        local regions = { coreTextHeader:GetRegions() }
        for _, rgn in ipairs(regions) do
            if rgn:IsObjectType("FontString") and EllesmereUI.EnKey(rgn:GetText()) == "CORE TEXT POSITIONS" then
                local sub = coreTextHeader:CreateFontString(nil, "OVERLAY")
                sub:SetFont(rgn:GetFont())
                sub:SetTextColor(1, 1, 1, 0.25)
                sub:SetText(EllesmereUI.L("(one per slot)"))
                sub:SetPoint("LEFT", rgn, "RIGHT", 6, 0)
                break
            end
        end
    end

    local textElementValues = {
        enemyName            = "Enemy Name",
        levelName            = "Level | Name",
        nameLevel            = "Name | Level",
        level                = "Level",
        targetOfTarget       = "Target of Target",
        healthPercent        = "Health %",
        healthPercentNoSign  = "Health % (No Sign)",
        healthNumber         = "Health #",
        healthPctNum         = "Health % | #",
        healthNumPct         = "Health # | %",
        healthPctNumDash     = "Health % - #",
        healthNumPctDash     = "Health # - %",
        none                 = "None",
    }
    local textElementOrder = { "none", "---", "enemyName", "levelName", "nameLevel", "level", "targetOfTarget", "healthPercent", "healthPercentNoSign", "healthNumber", "healthPctNum", "healthNumPct", "healthPctNumDash", "healthNumPctDash" }

    local function TextSlotSetValue(slotKey, v)
        -- Target of Target starts in Class mode whenever a slot newly takes it;
        -- the slot's Text Coloring dropdown still switches it back. The mode is
        -- saved only when the slot would not already derive Class.
        local newToT = v == "targetOfTarget" and DBVal(slotKey) ~= "targetOfTarget"
        SetTextElementAtSlot(slotKey, v)
        if newToT then
            local db = DB()
            db[slotKey .. "ColorMode"] = nil
            if ns.NP_SlotColorMode(slotKey, db) ~= "class" then
                db[slotKey .. "ColorMode"] = "class"
            end
        end
        ns.RefreshAllSettings()
        -- Rebuild: the Text Coloring rows, their modes and cogs follow the
        -- slotted elements (a slot change can also clear another slot).
        UpdatePreview(); EllesmereUI:RefreshPage(true)
    end

    local function TextOffsetRefresh()
        ns.RefreshAllSettings()
        UpdatePreview()
    end

    -- Text slot X/Y offset helpers (parallel to CorePosXGet etc.)
    local function TextPosXGet(slotKey)
        return DBVal(slotKey .. "XOffset") or 0
    end
    local function TextPosYGet(slotKey)
        return DBVal(slotKey .. "YOffset") or 0
    end
    local function TextPosXSet(slotKey, v)
        DB()[slotKey .. "XOffset"] = v; TextOffsetRefresh()
    end
    local function TextPosYSet(slotKey, v)
        DB()[slotKey .. "YOffset"] = v; TextOffsetRefresh()
    end
    local function TextPosDisabled(slotKey)
        return DBVal(slotKey) == "none"
    end

    local TEXT_DISABLED_TIP = "This option requires a text to be assigned"

    local function MakeTextCogIcon(row, regionKey, slotKey, slotLabel)
        local rgn = row[regionKey]
        local btn = CreateFrame("Button", nil, rgn)
        btn:SetSize(26, 26)
        btn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -9, 0)
        rgn._lastInline = btn
        btn:SetFrameLevel(rgn:GetFrameLevel() + 5)
        btn:SetAlpha(0.4)
        local tex = btn:CreateTexture(nil, "OVERLAY")
        tex:SetAllPoints()
        tex:SetTexture(EllesmereUI.RESIZE_ICON)
        btn:SetScript("OnEnter", function(self)
            if TextPosDisabled(slotKey) then
                EllesmereUI.ShowWidgetTooltip(self, TEXT_DISABLED_TIP)
            else
                self:SetAlpha(0.7)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            EllesmereUI.HideWidgetTooltip()
            if cogPopupOwner ~= self then self:SetAlpha(TextPosDisabled(slotKey) and 0.15 or 0.4) end
        end)
        btn:SetScript("OnClick", function(self)
            if TextPosDisabled(slotKey) then return end
            local sizeKey = slotKey .. "Size"
            local cogOpts = {
                title = EllesmereUI.Lf("%1$s Settings", EllesmereUI.L(slotLabel)),
                xGet = function() return TextPosXGet(slotKey) end,
                xSet = function(v) TextPosXSet(slotKey, v) end,
                yGet = function() return TextPosYGet(slotKey) end,
                ySet = function(v) TextPosYSet(slotKey, v) end,
                sizeGet = function() return DBVal(sizeKey) or defaults[sizeKey] end,
                sizeSet = function(v) DB()[sizeKey] = v; TextOffsetRefresh() end,
                sizeMin = 6, sizeMax = 30,
                sizeLabel = "Size",
                sizeFirst = true,
            }
            -- Both name and health text here get Width % + Wrap (dedicated Wrap row). Name-family variants use the GLOBAL enemyName keys (one slot holds the name FontString at a time); health text uses PER-SLOT keys (100% = no clip) and keeps "Show % Decimal". The bottom slots never truncate, so they get neither.
            local bottomSlot = slotKey == "textSlotBottomLeft" or slotKey == "textSlotBottomRight"
            if ns.IsNameElement(DBVal(slotKey)) then
                if not bottomSlot then
                    cogOpts.widthGet = function() return DBVal("enemyNameWidthPct") or defaults.enemyNameWidthPct end
                    cogOpts.widthSet = function(v) DB().enemyNameWidthPct = v; ns.RefreshAllSettings(); UpdatePreview() end
                    cogOpts.wrapGet = function() return DBVal("enemyNameWrap") == true end
                    cogOpts.wrapSet = function(v) DB().enemyNameWrap = v; ns.RefreshAllSettings(); UpdatePreview() end
                end
            else
                if not bottomSlot then
                    local widthKey = slotKey .. "WidthPct"
                    local wrapKey = slotKey .. "Wrap"
                    cogOpts.widthGet = function() return DBVal(widthKey) or 100 end
                    cogOpts.widthSet = function(v) DB()[widthKey] = v; ns.RefreshAllSettings(); UpdatePreview() end
                    cogOpts.wrapGet = function() return DBVal(wrapKey) == true end
                    cogOpts.wrapSet = function(v) DB()[wrapKey] = v; ns.RefreshAllSettings(); UpdatePreview() end
                end
                cogOpts.toggleLabel = "Show % Decimal"
                cogOpts.toggleGet = function() return DBVal(slotKey .. "PctDecimal") == true end
                cogOpts.toggleSet = function(v)
                    DB()[slotKey .. "PctDecimal"] = v
                    ns.RefreshAllSettings()
                    UpdatePreview()
                end
            end
            -- Target of Target and the standalone level have no use for "Show % Decimal".
            local slotEl = DBVal(slotKey)
            if slotEl == "targetOfTarget" or slotEl == "level" then
                cogOpts.toggleLabel, cogOpts.toggleGet, cogOpts.toggleSet = nil, nil, nil
            end
            -- WoW Forever: the name's format, while this slot shows a name or the
            -- Target of Target name. First and Last is stored as nil (the
            -- runtime's full-name path).
            if EllesmereUI.IS_FOREVER and (ns.IsNameElement(slotEl) or slotEl == "targetOfTarget") then
                local nfKey = slotKey .. "NameFormat"
                cogOpts.dropdown2Label = "Name Format"
                cogOpts.dropdown2Values = {
                    { value = "first", label = "First Name" },
                    { value = "last",  label = "Last Name" },
                    { value = "full",  label = "First and Last" },
                }
                cogOpts.dropdown2Get = function() return DBVal(nfKey) or "full" end
                cogOpts.dropdown2Set = function(v)
                    DB()[nfKey] = (v ~= "full") and v or nil
                    ns.RefreshAllSettings(); UpdatePreview()
                end
            end
            -- Per-slot strata (partner request): standard strata dropdown,
            -- defaulting to the shared text tier's MEDIUM.
            cogOpts.strataGet = function() return DBVal(slotKey .. "Strata") or "MEDIUM" end
            cogOpts.strataSet = function(v)
                DB()[slotKey .. "Strata"] = v
                ns.RefreshAllSettings(); UpdatePreview()
            end
            ShowCogPopup(self, cogOpts)
        end)
        EllesmereUI.RegisterWidgetRefresh(function()
            local off = TextPosDisabled(slotKey)
            btn:SetAlpha(off and 0.15 or (cogPopupOwner == btn and 0.7 or 0.4))
        end)
        if TextPosDisabled(slotKey) then btn:SetAlpha(0.15) end
        return btn
    end

    parent._showRowDivider = true

    -- Text Coloring rows: one under each position row, its halves mirroring that
    -- row (a None slot's half stays blank). The dropdown picks the slot's colour
    -- mode; ns.NP_SlotColorMode reads the saved mode, or derives it from the older
    -- colour keys until one is picked, so the page and the plates always agree.
    -- Custom paints the slot colour; Hostility / Class paints enemy players by
    -- class and NPCs by the Tapped / Neutral / Hostile name colours every slot
    -- shares (Target of Target: the target's class, else the slot colour); Level
    -- Difficulty paints the unit's level difficulty colour (every text but Target
    -- of Target, which names another unit).
    local COLOR_MODE_ORDER = { "custom", "class" }
    local COLOR_MODE_ORDER_LEVEL = { "custom", "class", "level" }
    local function TextColoringCfg(slotKey, label)
        local el = DBVal(slotKey)
        if el == "none" then return EllesmereUI.BlankRowCfg() end
        local values, order
        if el == "targetOfTarget" then
            values, order = { custom = "Custom", class = "Class" }, COLOR_MODE_ORDER
        else
            values = { custom = "Custom", class = "Hostility / Class", level = "Level Difficulty" }
            order = COLOR_MODE_ORDER_LEVEL
        end
        return { type="dropdown", text=label, values=values, order=order,
          getValue=function() return ns.NP_SlotColorMode(slotKey, DB()) end,
          -- The mode is saved only when the pick differs from what the slot derives
          -- with none saved, so picking the derived value pins nothing. Rebuild: the
          -- shared NPC swatches exist only on a Hostility / Class half.
          setValue=function(v)
            local db = DB()
            db[slotKey .. "ColorMode"] = nil
            if ns.NP_SlotColorMode(slotKey, db) ~= v then
                db[slotKey .. "ColorMode"] = v
            end
            ns.RefreshAllSettings()
            UpdatePreview(); EllesmereUI:RefreshPage(true)
          end }
    end

    -- A Text Coloring half's inline controls. Level | Name and Name | Level get a
    -- cog beside the dropdown with the name and level part colours (inline escapes
    -- on that part only; the rest of the text keeps the mode's colour). The
    -- swatches chain left of it, shown by the mode from the page refresh: Custom
    -- the slot colour, Hostility / Class the three shared NPC colours (Target of
    -- Target: the slot colour, used for an NPC target), Level Difficulty none. The
    -- NPC swatches are built only on a Hostility / Class half, so no other half
    -- traces the shared keys for Spec Overrides. Every write goes through the
    -- dropdown, a cog row or a swatch, which the Spec Overrides capture follows on
    -- its own.
    local npcSwatchUpdates = {}  -- the shared NPC swatches of every row, repainted together
    local function MakeTextColoringInline(row, regionKey, slotKey, title)
        local el = DBVal(slotKey)
        if el == "none" then return end
        local rgn = row[regionKey]
        local colorKey = slotKey .. "Color"
        local isToT = el == "targetOfTarget"
        local function Mode() return ns.NP_SlotColorMode(slotKey, DB()) end
        local function Apply()
            ns.RefreshAllSettings()
            UpdatePreview()
        end

        if el == "levelName" or el == "nameLevel" then
            local nameOnKey, nameColorKey = slotKey .. "NameColorOn", slotKey .. "NameColor"
            local lvlOnKey, lvlColorKey = slotKey .. "LevelColorOn", slotKey .. "LevelColor"
            local diffKey = slotKey .. "LevelDiffOn"
            -- A part colour not picked yet starts from the slot colour.
            local function PartColor(key)
                local db = DB()
                local c = (db and (db[key] or db[colorKey])) or defaults[colorKey]
                return c.r, c.g, c.b
            end
            EllesmereUI.BuildInlineCog(rgn, {
                title = title,
                captureRegion = rgn,
                rows = {
                    { type="toggle", label="Custom Name Color",
                      get=function() return DBVal(nameOnKey) == true end,
                      set=function(v) DB()[nameOnKey] = v; Apply() end },
                    { type="colorpicker", label="Name Color",
                      hidden=function() return DBVal(nameOnKey) ~= true end,
                      get=function() return PartColor(nameColorKey) end,
                      set=function(r, g, b) DB()[nameColorKey] = { r = r, g = g, b = b }; Apply() end },
                    { type="toggle", label="Custom Level Color",
                      get=function() return DBVal(lvlOnKey) == true end,
                      set=function(v)
                        DB()[lvlOnKey] = v
                        if v then DB()[diffKey] = false end
                        Apply()
                      end },
                    { type="colorpicker", label="Level Color",
                      hidden=function() return DBVal(lvlOnKey) ~= true end,
                      get=function() return PartColor(lvlColorKey) end,
                      set=function(r, g, b) DB()[lvlColorKey] = { r = r, g = g, b = b }; Apply() end },
                    -- The whole text already takes the difficulty colour in Level
                    -- Difficulty mode.
                    { type="toggle", label="Level Difficulty Color",
                      hidden=function() return Mode() == "level" end,
                      get=function() return ns.NP_SlotLevelDiff(slotKey, DB()) end,
                      set=function(v)
                        DB()[diffKey] = v
                        if v then DB()[lvlOnKey] = false end
                        Apply()
                      end },
                },
            })
        end

        local anchor = rgn._lastInline or rgn._control
        local gap = rgn._lastInline and -8 or -12
        local custom, updateCustom = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5,
            function()
                local c = (DB() and DB()[colorKey]) or defaults[colorKey]
                return c.r, c.g, c.b
            end,
            function(r, g, b)
                DB()[colorKey] = { r = r, g = g, b = b }
                Apply()
            end, nil, 20)
        PP.Point(custom, "RIGHT", anchor, "LEFT", gap, 0)
        custom:SetScript("OnEnter", function()
            if isToT and Mode() == "class" then
                EllesmereUI.ShowWidgetTooltip(custom, EllesmereUI.L("NPC Target Color"))
            else
                EllesmereUI.ShowWidgetTooltip(custom, EllesmereUI.L("Custom Color"))
            end
        end)
        custom:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        rgn._lastInline = custom

        -- Hostility / Class: Tapped / Neutral / Hostile left to right, Hostile in
        -- the custom swatch's place.
        local npc, npcUpd
        if not isToT and Mode() == "class" then
            npc, npcUpd = {}, {}
            local prev, prevGap = anchor, gap
            local function NPCSwatch(key, fallbackKey, tip)
                local sw, upd = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5,
                    function()
                        local c = (DB() and DB()[key]) or defaults[fallbackKey]
                        return c.r, c.g, c.b
                    end,
                    -- Read live by the per-unit painter, so a health colour pass repaints.
                    function(r, g, b)
                        DB()[key] = { r = r, g = g, b = b }
                        RefreshAllPlates()
                        UpdatePreview()
                        for i = 1, #npcSwatchUpdates do npcSwatchUpdates[i]() end
                    end, nil, 20)
                PP.Point(sw, "RIGHT", prev, "LEFT", prevGap, 0)
                prev, prevGap = sw, -8
                sw:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(sw, tip) end)
                sw:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                npc[#npc + 1] = sw
                npcUpd[#npcUpd + 1] = upd
                npcSwatchUpdates[#npcSwatchUpdates + 1] = upd
                return sw
            end
            NPCSwatch("enemyNameHostileColor", "hostile", EllesmereUI.L("Hostile Color"))
            NPCSwatch("enemyNameNeutralColor", "neutral", EllesmereUI.L("Neutral Color"))
            -- Leftmost built item: the label clamp keeps the label clear of it.
            rgn._lastInline = NPCSwatch("enemyNameTappedColor", "tapped", EllesmereUI.L("Tapped Color"))
        end

        local function ShowForMode()
            local m = Mode()
            custom:SetShown(m == "custom" or (isToT and m == "class"))
            updateCustom()
            if npc then
                local on = m == "class"
                for i = 1, #npc do
                    npc[i]:SetShown(on)
                    npcUpd[i]()
                end
            end
        end
        EllesmereUI.RegisterWidgetRefresh(ShowForMode)
        ShowForMode()
    end

    -- Builds the Text Coloring row under a position row while either of its slots
    -- shows a text; returns the new y.
    local function TextColoringRow(rowY, leftSlot, leftLabel, rightSlot, rightLabel)
        if DBVal(leftSlot) == "none" and DBVal(rightSlot) == "none" then return rowY end
        local row, rowH = W:DualRow(parent, rowY,
            TextColoringCfg(leftSlot, leftLabel), TextColoringCfg(rightSlot, rightLabel))
        if not EllesmereUI._prebuilding then
            MakeTextColoringInline(row, "_leftRegion", leftSlot, leftLabel)
            MakeTextColoringInline(row, "_rightRegion", rightSlot, rightLabel)
        end
        return rowY - rowH
    end

    local textRow1, textRow2, textRow3

    -- Row 1: Top Text | Right Text
    textRow1, h = W:DualRow(parent, y,
        { type="dropdown", text="Top Text", values=textElementValues,
          getValue=function() return DBVal("textSlotTop") end,
          setValue=function(v) TextSlotSetValue("textSlotTop", v) end,
          order=textElementOrder,
          disabled=function() return DBVal("textSlotTop") == "none" end,
          disabledTooltip="This option requires a text to be assigned", rawTooltip=true,
          labelOnlyDisabled=true },
        { type="dropdown", text="Right Text", values=textElementValues,
          getValue=function() return DBVal("textSlotRight") end,
          setValue=function(v) TextSlotSetValue("textSlotRight", v) end,
          order=textElementOrder,
          disabled=function() return DBVal("textSlotRight") == "none" end,
          disabledTooltip="This option requires a text to be assigned", rawTooltip=true,
          labelOnlyDisabled=true,
          disabledValues=function(k) if ns.IsComboHealthText(k) and ns.IsNameElement(DBVal("textSlotCenter")) then return "Disabled when the Name/Level text is centered on the health bar due to overlapping text" end end });  y = y - h
    if not EllesmereUI._prebuilding then
    MakeTextCogIcon(textRow1, "_leftRegion",  "textSlotTop",   "Top Text")
    MakeTextCogIcon(textRow1, "_rightRegion", "textSlotRight", "Right Text")
    end
    y = TextColoringRow(y, "textSlotTop", "Top Text Coloring", "textSlotRight", "Right Text Coloring")

    -- Row 2: Left Text | Center Text
    textRow2, h = W:DualRow(parent, y,
        { type="dropdown", text="Left Text", values=textElementValues,
          getValue=function() return DBVal("textSlotLeft") end,
          setValue=function(v) TextSlotSetValue("textSlotLeft", v) end,
          order=textElementOrder,
          disabled=function() return DBVal("textSlotLeft") == "none" end,
          disabledTooltip="This option requires a text to be assigned", rawTooltip=true,
          labelOnlyDisabled=true,
          disabledValues=function(k) if ns.IsComboHealthText(k) and ns.IsNameElement(DBVal("textSlotCenter")) then return "Disabled when the Name/Level text is centered on the health bar due to overlapping text" end end },
        { type="dropdown", text="Center Text", values=textElementValues,
          getValue=function() return DBVal("textSlotCenter") end,
          setValue=function(v) TextSlotSetValue("textSlotCenter", v) end,
          order=textElementOrder,
          disabled=function() return DBVal("textSlotCenter") == "none" end,
          disabledTooltip="This option requires a text to be assigned", rawTooltip=true,
          labelOnlyDisabled=true });  y = y - h
    if not EllesmereUI._prebuilding then
    MakeTextCogIcon(textRow2, "_leftRegion",  "textSlotLeft",   "Left Text")
    MakeTextCogIcon(textRow2, "_rightRegion", "textSlotCenter", "Center Text")
    end
    y = TextColoringRow(y, "textSlotLeft", "Left Text Coloring", "textSlotCenter", "Center Text Coloring")

    -- Row 3: Bottom Left Text | Bottom Right Text (under the health bar's corners,
    -- below the cast bar while one shows)
    textRow3, h = W:DualRow(parent, y,
        { type="dropdown", text="Bottom Left Text", values=textElementValues,
          getValue=function() return DBVal("textSlotBottomLeft") end,
          setValue=function(v) TextSlotSetValue("textSlotBottomLeft", v) end,
          order=textElementOrder,
          disabled=function() return DBVal("textSlotBottomLeft") == "none" end,
          disabledTooltip="This option requires a text to be assigned", rawTooltip=true,
          labelOnlyDisabled=true },
        { type="dropdown", text="Bottom Right Text", values=textElementValues,
          getValue=function() return DBVal("textSlotBottomRight") end,
          setValue=function(v) TextSlotSetValue("textSlotBottomRight", v) end,
          order=textElementOrder,
          disabled=function() return DBVal("textSlotBottomRight") == "none" end,
          disabledTooltip="This option requires a text to be assigned", rawTooltip=true,
          labelOnlyDisabled=true });  y = y - h
    if not EllesmereUI._prebuilding then
    MakeTextCogIcon(textRow3, "_leftRegion",  "textSlotBottomLeft",  "Bottom Left Text")
    MakeTextCogIcon(textRow3, "_rightRegion", "textSlotBottomRight", "Bottom Right Text")
    end
    y = TextColoringRow(y, "textSlotBottomLeft", "Bottom Left Text Coloring", "textSlotBottomRight", "Bottom Right Text Coloring")

    _, h = W:Spacer(parent, y, 20);  y = y - h

    return y, styleHeader, coreHeader, coreRow1, coreRow2, coreRow3, coreTextHeader, textRow1,
        textRow2, textRow3, ShowCogPopup, CogPopupOpen, RefreshAllTextures
end

-- Used by EUI_Nameplates_Options.lua
ns.NPO_BuildDisplayLayout = BuildDisplayLayout
