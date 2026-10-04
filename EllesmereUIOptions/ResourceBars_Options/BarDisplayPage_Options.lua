if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  ResourceBars_Options\BarDisplayPage_Options.lua
--  Resource Bars options: Class, Power and Health Bars page. Definitions only; the shared
--  helpers come from ns._ERB_OptEnv (filled by EUI_ResourceBars_Options.lua).
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUIResourceBars"]
if not ns then return end  -- module disabled: no options page

-- Bar Display page
function ns.ERB_BuildBarDisplayPage(pageName, parent, yOffset)
    local env = ns._ERB_OptEnv
    local DB, PP, Refresh, SmoothRefresh = env.DB, env.PP, env.Refresh, env.SmoothRefresh
    local RebuildClass, RebuildPower, RebuildHealth, _clickMappings = env.RebuildClass, env.RebuildPower, env.RebuildHealth, env._clickMappings
    local _previewHeaderBuilder, CLASSIC_SYNC_KEYS, CLASSIC_MATCH_KEYS = env._previewHeaderBuilder, env.CLASSIC_SYNC_KEYS, env.CLASSIC_MATCH_KEYS
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h

    parent._showRowDivider = true

    -- Shared row references for sync icon flashTargets, filled per section
    local _syncRows = {}

    -- Bar texture dropdown values from the _ERB globals. SharedMedia is re-appended here because options open later than init, so SM packs that register textures lazily are available by now.
    EllesmereUI.AppendSharedMediaTextures(
        _G._ERB_BarTextureNames or {},
        _G._ERB_BarTextureOrder or {},
        nil,
        _G._ERB_BarTextures
    )
    local hbtValues = {}
    local hbtOrder = {}
    do
        local texNames = _G._ERB_BarTextureNames or {}
        local texOrder2 = _G._ERB_BarTextureOrder or {}
        local texLookup = _G._ERB_BarTextures or {}
        for _, key in ipairs(texOrder2) do
            if key ~= "---" then
                hbtValues[key] = texNames[key] or key
            end
            hbtOrder[#hbtOrder + 1] = key
        end
        hbtValues._menuOpts = {
            itemHeight = 28,
            background = function(key)
                return texLookup[key]
            end,
        }
    end
    -- Own values/order copy per extra texture dropdown (the per-bar row), so no
    -- two dropdowns share one table pair.
    local function CopyTexDD()
        local v, o = {}, {}
        for k, name in pairs(hbtValues) do v[k] = name end
        for i = 1, #hbtOrder do o[i] = hbtOrder[i] end
        return v, o
    end

    -- Randomize the preview fill on every visit to this page
    local minPips = math.floor(5 * 0.50 + 0.5)
    local maxPips = math.floor(5 * 0.75 + 0.5)
    env.SetDisplayPreviewValues(math.random(minPips, maxPips), math.random(30, 80))

    EllesmereUI:SetContentHeader(_previewHeaderBuilder)

    -- _clickMappings is ONE module-shared table read by the LIVE preview header's clicks, so a hidden search pre-build must NOT wipe it out from under whichever ERB page is being viewed.
    if not EllesmereUI._prebuilding then
        wipe(_clickMappings)
    end

    -- Per-spec editing lives in the shared Spec Overrides system (spec groups + editing-as); legacy Advanced data migrates via MigrateRBAdvancedProfile.

    local generalSection
    generalSection, h = W:SectionHeader(parent, "BAR DISPLAY", y);  y = y - h

    -- Row 1: Visibility | Visibility Options. One control drives all three bars: the scalar and the multi-select set write to health/primary/secondary in lockstep; reads come from secondary, the representative.
    local function ApplyVisScalarAll(_, mode)
        local p = DB(); if not p then return end
        p.secondary.visibility = mode
        p.health.visibility = mode
        p.primary.visibility = mode
    end
    local function MirrorVisModes()
        local p = DB(); if not p then return end
        local src = p.secondary.visibilityModes
        if src then
            local c1, c2 = {}, {}
            for k in pairs(src) do c1[k] = true; c2[k] = true end
            p.health.visibilityModes = c1
            p.primary.visibilityModes = c2
        else
            p.health.visibilityModes = nil
            p.primary.visibilityModes = nil
        end
    end
    -- One control for all three bars: the scalar, the multi-select set and the option
    -- booleans all fan out to health/primary/secondary; reads come from secondary,
    -- the representative.
    local visRow
    visRow, h = EllesmereUI.BuildVisibilityRow(W, parent, y,
        { getStore = function() local p = DB(); return p and p.secondary end,
          -- The override marker fans out like the scalar and the option lanes do;
          -- secondary leads, matching getStore above.
          getStores = function()
              local p = DB(); if not p then return nil end
              -- Built by presence, never as a literal triple: a nil in the middle
              -- would leave a hole the # operator reads past.
              local out = {}
              if p.secondary then out[#out + 1] = p.secondary end
              if p.health    then out[#out + 1] = p.health    end
              if p.primary   then out[#out + 1] = p.primary   end
              return out
          end,
          legacyKey = "visibility",
          caps = { partyIncludesRaid = false, luaDragonriding = true },
          applyScalarFn = ApplyVisScalarAll,
          getOption = function(k)
              local p = DB(); if not p then return false end
              return p.secondary[k] or false
          end,
          setOption = function(k, v)
              local p = DB(); if not p then return end
              p.secondary[k] = v
              p.health[k] = v
              p.primary[k] = v
          end,
          onChanged = function()
              MirrorVisModes()
              Refresh()
          end,
          onOptionChanged = function() Refresh() end },
        -- Smooth Bars: placeholder slot, swapped for the checkbox dropdown below.
        { type = "dropdown", text = "Smooth Bars",
          values = { __placeholder = "..." }, order = { "__placeholder" },
          getValue = function() return "__placeholder" end,
          setValue = function() end }
    );  y = y - h

    -- Smooth Bars checkbox dropdown. Each item enables native StatusBar interpolation
    -- on its bar; off = a plain SetValue with zero added cost. Defaults all off.
    if not EllesmereUI._prebuilding then
        local rightRgn = visRow._rightRegion
        if rightRgn._control then rightRgn._control:Hide() end
        local smoothItems = {
            { key = "secondary", label = "Class Resource Bar" },
            { key = "primary",   label = "Power Bar" },
            { key = "health",    label = "Health Bar" },
        }
        local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
            rightRgn, 210, rightRgn:GetFrameLevel() + 2,
            smoothItems,
            function(k)
                local p = DB(); if not p then return false end
                return (p[k] and p[k].smoothBars) or false
            end,
            function(k, v)
                local p = DB(); if not p then return end
                if p[k] then p[k].smoothBars = v end
                if _G._ERB_ApplySmoothing then _G._ERB_ApplySmoothing() end
            end)
        PP.Point(cbDD, "RIGHT", rightRgn, "RIGHT", -20, 0)
        rightRgn._control = cbDD
        rightRgn._lastInline = nil
        EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
    end

    -- Row 2: Dark Mode Class Resource | Background Color. Dark mode applies ONLY to the class
    -- resource bar (secondary), using the same flat dark fill/bg as Unit Frames / Raid Frames;
    -- secondary.darkTheme is the single source of truth, health/primary are never darkened.
    -- Background is shared by Health & Power, plus the class resource bar while Dark Mode is off
    -- (the label says so). With splitBg on (the cog's "Choose background per bar") the
    -- per-bar rows below own Health & Power and this row narrows to the class resource bar; it
    -- stays live in every case, never disabled.
    local bgLabel = "Background"
    do
        local p0 = DB()
        if p0 and p0.splitBg == true then
            bgLabel = "Background (Class Resource)"
        elseif p0 and p0.secondary.darkTheme then
            bgLabel = "Background (Health & Power)"
        end
    end
    local bgRow
    bgRow, h = W:DualRow(parent, y,
        { type = "toggle", text = "Dark Mode Class Resource",
          getValue = function()
              local p = DB(); if not p then return false end
              return p.secondary.darkTheme
          end,
          setValue = function(v)
              local p = DB(); if not p then return end
              p.secondary.darkTheme = v
              RebuildClass()
              -- Full rebuild so the Background label re-renders
              EllesmereUI:RefreshPage(true)
          end },
        { type = "slider", text = bgLabel, min = 0, max = 100, step = 1, trackWidth = 120,
          getValue = function()
              local p = DB(); if not p then return 75 end
              if p.splitBg == true then
                  return math.floor(((p.secondary.barBgA or 0.5) * 100) + 0.5)
              end
              return math.floor(((p.health.bgA or 0.75) * 100) + 0.5)
          end,
          setValue = function(v)
              local p = DB(); if not p then return end
              local a = v / 100
              if p.splitBg == true then
                  -- Split mode: Health/Power own their keys via the rows below, this row still owns the class resource bar
                  p.secondary.barBgA = a
              else
                  p.health.bgA = a
                  p.primary.bgA = a
                  p.secondary.barBgA = a
              end
              SmoothRefresh()
              EllesmereUI:RefreshPage()
          end }
    );  y = y - h
    -- Background inline swatch is color-only: opacity lives in the slider, a view over the same bgA keys.
    if not EllesmereUI._prebuilding then
        local rgn = bgRow._rightRegion
        local ctrl = rgn._control
        local bgSwatch, bgUpdateSwatch = EllesmereUI.BuildColorSwatch(
            rgn, bgRow:GetFrameLevel() + 3,
            function()
                local p = DB()
                if p and p.splitBg == true then
                    return p.secondary.barBgR or 0, p.secondary.barBgG or 0,
                           p.secondary.barBgB or 0
                end
                return (p and p.health.bgR or 0x11/255), (p and p.health.bgG or 0x11/255),
                       (p and p.health.bgB or 0x11/255)
            end,
            function(r, g, b)
                local p = DB(); if not p then return end
                if p.splitBg == true then
                    p.secondary.barBgR, p.secondary.barBgG, p.secondary.barBgB = r, g, b
                else
                    p.health.bgR, p.health.bgG, p.health.bgB = r, g, b
                    p.primary.bgR, p.primary.bgG, p.primary.bgB = r, g, b
                    p.secondary.barBgR, p.secondary.barBgG, p.secondary.barBgB = r, g, b
                end
                SmoothRefresh()
                EllesmereUI:RefreshPage()
            end,
            nil, 20)
        PP.Point(bgSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
        EllesmereUI.RegisterWidgetRefresh(bgUpdateSwatch)

        -- Split cog. The feature is an options-side VIEW: the bars already read their own keys
        -- at runtime (health.bg*, primary.bg*, secondary.barBg*) and the unified row just writes
        -- them in lockstep, so splitting only changes which rows write which keys -- zero runtime
        -- change, nothing hits the DB unless opted in. splitCogShow MUST be declared BEFORE the
        -- build so the toggle's set closure (built inside the argument table) captures it as an
        -- upvalue (assigning on the same line would leave the closure seeing nil). The popup frame
        -- is built LAZILY on first show, so the closure reaches it via showFn._popupFrame, stamped
        -- by the show wrapper on first open.
        local _, splitCogShow
        _, splitCogShow = EllesmereUI.BuildInlineCog(rgn, {
            anchorTo = bgSwatch,
            title = "Background",
            minWidth = 290,
            rows = {
                { type = "toggle", label = "Choose background per bar",
                  get = function()
                      local p = DB(); return (p and p.splitBg) == true
                  end,
                  set = function(v)
                      local p = DB(); if not p then return end
                      if v then
                          p.splitBg = true
                          -- Close the popup so the newly revealed per-bar rows are visible (frame always exists here, but guard anyway)
                          local pfr = splitCogShow and splitCogShow._popupFrame
                          if pfr then pfr:Hide() end
                      else
                          -- Split OFF re-unifies from Health (the unified row's read source) so "off" really means one background, not silently diverged bars.
                          -- Stored false, not nil: profile sync copies only keys that exist.
                          p.splitBg = false
                          local hp = p.health
                          p.primary.bgR, p.primary.bgG, p.primary.bgB, p.primary.bgA =
                              hp.bgR, hp.bgG, hp.bgB, hp.bgA
                          p.secondary.barBgR, p.secondary.barBgG, p.secondary.barBgB, p.secondary.barBgA =
                              hp.bgR, hp.bgG, hp.bgB, hp.bgA
                          SmoothRefresh()
                      end
                      EllesmereUI:RefreshPage(true)
                  end },
            },
        })
    end

    -- Split rows are built ONLY while the split is enabled, so the page is byte-identical for
    -- everyone else. Health writes health.*, Power writes primary.* only; the class resource's
    -- barBg* stays with the unified Background row above, which relabels and narrows to those keys.
    do
        local p0 = DB()
        if p0 and p0.splitBg == true then
            local splitRow
            splitRow, h = W:DualRow(parent, y,
                { type = "slider", text = "Health Background", min = 0, max = 100, step = 1, trackWidth = 120,
                  getValue = function()
                      local p = DB(); return math.floor(((p and p.health.bgA or 0.75) * 100) + 0.5)
                  end,
                  setValue = function(v)
                      local p = DB(); if not p then return end
                      p.health.bgA = v / 100
                      SmoothRefresh()
                      EllesmereUI:RefreshPage()
                  end },
                { type = "slider", text = "Power Background", min = 0, max = 100, step = 1, trackWidth = 120,
                  getValue = function()
                      local p = DB(); return math.floor(((p and p.primary.bgA or 0.75) * 100) + 0.5)
                  end,
                  setValue = function(v)
                      local p = DB(); if not p then return end
                      p.primary.bgA = v / 100
                      SmoothRefresh()
                      EllesmereUI:RefreshPage()
                  end }
            );  y = y - h
            if not EllesmereUI._prebuilding then
                local rgn = splitRow._leftRegion
                local ctrl = rgn._control
                local hSwatch, hUpdateSwatch = EllesmereUI.BuildColorSwatch(
                    rgn, splitRow:GetFrameLevel() + 3,
                    function()
                        local p = DB()
                        return (p and p.health.bgR or 0x11/255), (p and p.health.bgG or 0x11/255),
                               (p and p.health.bgB or 0x11/255)
                    end,
                    function(r, g, b)
                        local p = DB(); if not p then return end
                        p.health.bgR, p.health.bgG, p.health.bgB = r, g, b
                        SmoothRefresh()
                        EllesmereUI:RefreshPage()
                    end,
                    nil, 20)
                PP.Point(hSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
                EllesmereUI.RegisterWidgetRefresh(hUpdateSwatch)
            end
            if not EllesmereUI._prebuilding then
                local rgn = splitRow._rightRegion
                local ctrl = rgn._control
                local pSwatch, pUpdateSwatch = EllesmereUI.BuildColorSwatch(
                    rgn, splitRow:GetFrameLevel() + 3,
                    function()
                        local p = DB()
                        return (p and p.primary.bgR or 0x11/255), (p and p.primary.bgG or 0x11/255),
                               (p and p.primary.bgB or 0x11/255)
                    end,
                    function(r, g, b)
                        local p = DB(); if not p then return end
                        p.primary.bgR, p.primary.bgG, p.primary.bgB = r, g, b
                        SmoothRefresh()
                        EllesmereUI:RefreshPage()
                    end,
                    nil, 20)
                PP.Point(pSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
                EllesmereUI.RegisterWidgetRefresh(pUpdateSwatch)
            end
        end
    end

    -- Row 3: Texture (cog: per-bar textures, Blizzard atlas for class resource) | Frame Strata.
    -- The row always writes general.barTexture. With splitTex on (the cog's "Choose texture
    -- per bar") health and power read their own keys from the row below, so this row
    -- narrows to the class resource and says so.
    local strataValues = EllesmereUI.FRAME_STRATA_LABELS
    local strataOrder = EllesmereUI.FRAME_STRATA_ORDER_BASE
    local texLabel = "Texture"
    do
        local p0 = DB()
        if p0 and p0.splitTex == true then texLabel = "Texture (Class Resource)" end
    end
    local texRow
    texRow, h = W:DualRow(parent, y,
        { type = "dropdown", text = texLabel, values = hbtValues, order = hbtOrder,
          getValue = function()
              local p = DB(); if not p then return "none" end
              return p.general.barTexture or "none"
          end,
          setValue = function(v)
              local p = DB(); if not p then return end
              p.general.barTexture = v; SmoothRefresh()
          end },
        { type = "dropdown", text = "Frame Strata",
          tooltip = "Controls the order that overlapping elements display in. Set higher to show above other elements.",
          values = strataValues, order = strataOrder,
          getValue = function()
              local p = DB(); return p and p.general.frameStrata or "MEDIUM"
          end,
          setValue = function(v)
              local p = DB(); if not p then return end
              p.general.frameStrata = v; SmoothRefresh()
          end }
    );
    -- Texture cog: per-bar textures, and the Blizzard atlas fill for the class resource bar.
    -- cogShow is declared BEFORE the build so the per-bar toggle's set closure captures it
    -- (same as the Background cog); the lazily built popup is reached via cogShow._popupFrame.
    local cogShow
    cogShow = select(2, EllesmereUI.BuildInlineCog(texRow._leftRegion, {
        title = "Texture Settings",
        rows = {
            { type = "toggle", label = "Choose texture per bar",
              get = function()
                  local p = DB(); return (p and p.splitTex) == true
              end,
              set = function(v)
                  local p = DB(); if not p then return end
                  if v then
                      -- Health and power start on the texture they show now, so the
                      -- relabelled main row moves only the class resource from here on.
                      p.splitTex = true
                      local t = p.general.barTexture
                      p.health.barTexture, p.primary.barTexture = t, t
                      -- Close the popup so the newly revealed per-bar row is visible
                      local pfr = cogShow and cogShow._popupFrame
                      if pfr then pfr:Hide() end
                  else
                      -- Off means one texture again: every bar follows the main row.
                      -- Stored false, not nil: profile sync copies only keys that exist,
                      -- so a nil would never switch it off in a synced profile.
                      p.splitTex = false
                      p.health.barTexture, p.primary.barTexture = nil, nil
                      SmoothRefresh()
                  end
                  -- The Global Settings Textures page mirrors these rows and is built
                  -- from the same flag: drop its cached build.
                  if EllesmereUI.InvalidateModulePageCache then
                      EllesmereUI:InvalidateModulePageCache("_EUIGlobal")
                  end
                  EllesmereUI:RefreshPage(true)
              end },
            { type = "toggle", label = "Blizzard Class Resource Bar Texture",
              tooltip = "Bar-style class resources (Insanity, Maelstrom, Astral Power, etc.) use Blizzard's default player frame bar artwork instead of the texture above.",
              get = function()
                  local p = DB(); return (p and p.secondary.useBlizzardAtlas) or false
              end,
              set = function(v)
                  local p = DB(); if not p then return end
                  p.secondary.useBlizzardAtlas = v
                  RebuildClass()
                  if v then
                      EllesmereUI:ShowConfirmPopup({
                          title = "Blizzard Class Resource Bar Texture",
                          message = "Blizzard's bar artwork is never recolored, so fill color modes and threshold colors will not tint the bar while this is enabled. To keep threshold colors visible, use Recolor Text Instead.",
                          confirmText = "Okay",
                      })
                  end
              end },
        },
    }))
    y = y - h

    -- Per-bar texture row, built ONLY while "Choose texture per bar" is on, so the page is
    -- byte-identical for everyone else. Health writes health.barTexture, Power writes
    -- primary.barTexture; the class resource keeps general.barTexture on the row above.
    do
        local p0 = DB()
        if p0 and p0.splitTex == true then
            local hv, ho = CopyTexDD()
            local pv, po = CopyTexDD()
            _, h = W:DualRow(parent, y,
                { type = "dropdown", text = "Health Texture", values = hv, order = ho,
                  getValue = function()
                      local p = DB(); if not p then return "none" end
                      return p.health.barTexture or p.general.barTexture or "none"
                  end,
                  setValue = function(v)
                      local p = DB(); if not p then return end
                      p.health.barTexture = v; SmoothRefresh()
                  end },
                { type = "dropdown", text = "Power Texture", values = pv, order = po,
                  getValue = function()
                      local p = DB(); if not p then return "none" end
                      return p.primary.barTexture or p.general.barTexture or "none"
                  end,
                  setValue = function(v)
                      local p = DB(); if not p then return end
                      p.primary.barTexture = v; SmoothRefresh()
                  end }
            );  y = y - h
        end
    end

    -- Row 4: Blizzard Class Resource Art | Expand Power Bar if No Resource
    local blizzArtRow
    blizzArtRow, h = W:DualRow(parent, y,
        { type = "toggle", text = "Blizzard Class Resource Art",
          tooltip = "Replaces the class resource bar with Blizzard's own class resource frame, such as Holy Power, Combo Points, Chi, Soul Shards, Arcane Charges, Essence or Runes.",
          -- Greyed on specs whose class resource Blizzard draws as a bar or not
          -- at all, and while the Unit Frames "Blizzard" class resource style
          -- holds that frame (Unit Frames wins it). Greyed only while off, so
          -- it can still be turned off there.
          disabled = function()
              local p = DB(); if not p then return true end
              if p.secondary.blizzardClassArt then return false end
              return not (ns.ERB_BlizzClassArtSupported and ns.ERB_BlizzClassArtSupported())
          end,
          disabledTooltip = function()
              local why = ns.ERB_BlizzClassArtSupported and select(2, ns.ERB_BlizzClassArtSupported())
              if why == "uf" then
                  return "This option can't be used while the Unit Frames class resource is set to Blizzard."
              end
              if why == "client" then
                  return "This option is not available on this client."
              end
              if why == "prd" then
                  return "This option can't be used while the Personal Resource Display hides the player frame's class resource."
              end
              return "This option requires a class resource that Blizzard shows as its own frame, such as Holy Power, Combo Points, Chi, Soul Shards, Arcane Charges, Essence or Runes."
          end,
          rawTooltip = true,
          getValue = function() local p = DB(); return (p and p.secondary.blizzardClassArt) and true or false end,
          setValue = function(v)
              local p = DB(); if not p then return end
              p.secondary.blizzardClassArt = v and true or false
              RebuildClass()
              EllesmereUI:RefreshPage()
          end },
        { type = "toggle", text = "Expand Power Bar if No Resource",
          tooltip = "When the class resource bar is not shown, this automatically adds the class resource height to the power bar.",
          -- Mutually exclusive with "Shift Elements if No Resource": grey this while shift is set, but only when this is itself OFF so a legacy profile with both on can still turn this off (no deadlock).
          disabled = function()
              local p = DB(); if not p then return false end
              if not p.primary.enabled then return true end
              if EllesmereUI.GetHeightMatchTarget and EllesmereUI.GetHeightMatchTarget("ERB_Power") then return true end
              -- Shift blocks expand when the dropdown is set to Up/Down. Independent of "Show Class Resource" -- toggling the resource bar must NOT change this control's disabled state.
              local shiftOn = (p.secondary.shiftElementsIfNoResource or "None") ~= "None"
              return shiftOn and not p.primary.expandIfNoResource and true or false
          end,
          disabledTooltip = function()
              local p = DB()
              if p and not p.primary.enabled then return "Power Bar" end
              if EllesmereUI.GetHeightMatchTarget and EllesmereUI.GetHeightMatchTarget("ERB_Power") then
                  return "This option can't be used while you have the Power Bar Height Matched in the Unlock Mode."
              end
              return "This option can't be used while Shift Elements if No Resource is enabled."
          end,
          getValue = function()
              -- Force off when height matched
              if EllesmereUI.GetHeightMatchTarget and EllesmereUI.GetHeightMatchTarget("ERB_Power") then
                  return false
              end
              local p = DB(); return p and p.primary.expandIfNoResource
          end,
          setValue = function(v)
              -- Block enable when height matched
              if v and EllesmereUI.GetHeightMatchTarget and EllesmereUI.GetHeightMatchTarget("ERB_Power") then
                  return
              end
              local p = DB(); if not p then return end
              p.primary.expandIfNoResource = v
              -- Enabling expand turns off the mutually-exclusive shift option.
              if v then p.secondary.shiftElementsIfNoResource = "None" end
              Refresh()
              EllesmereUI:RefreshPage()
          end }
    );  y = y - h
    -- Inline scale cog on "Blizzard Class Resource Art". Greyed while the
    -- toggle is off (its setter refreshes the page).
    if not EllesmereUI._prebuilding then
        local rgn = blizzArtRow._leftRegion
        local function artOff()
            local p = DB(); return not (p and p.secondary.blizzardClassArt)
        end
        EllesmereUI.BuildInlineCog(rgn, {
            icon = EllesmereUI.RESIZE_ICON,
            disabled = artOff, disabledTooltip = "Blizzard Class Resource Art",
            title = "Blizzard Class Resource Art",
            rows = {
                { type = "slider", label = "Scale", min = 50, max = 200, step = 5,
                  get = function()
                      local p = DB()
                      return math.floor(((p and p.secondary.blizzardClassArtScale) or 1) * 100 + 0.5)
                  end,
                  set = function(v)
                      local p = DB(); if not p then return end
                      p.secondary.blizzardClassArtScale = v / 100
                      if ns.ERB_ApplyBlizzClassArt then ns.ERB_ApplyBlizzClassArt() end
                  end },
            },
        })
    end
    -- Inline reposition cog on "Expand Power Bar if No Resource": Extra Y Offset
    if not EllesmereUI._prebuilding then
        local rgn = blizzArtRow._rightRegion
        local function expandOff()
            local p = DB(); return not (p and p.primary.expandIfNoResource)
        end
        EllesmereUI.BuildInlineCog(rgn, { icon = EllesmereUI.DIRECTIONS_ICON,
            disabled = expandOff, disabledTooltip = "Expand Power Bar if No Resource",
            title = "Expand Offset",
            rows = {
                { type = "slider", pixel = true, label = "Extra Y Offset", min = -50, max = 50, step = 1,
                  get = function() local p = DB(); return (p and p.primary.expandIfNoResourceExtraY) or 0 end,
                  set = function(v)
                      local p = DB(); if not p then return end
                      p.primary.expandIfNoResourceExtraY = v
                      Refresh()
                  end },
            },
        })
    end

    -- Row 5: Shift Elements if No Resource | Shift Elements if No Power
    local shiftRow
    shiftRow, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Shift Elements if No Resource",
          tooltip = "Shifts any elements anchored to the class resource bar up or down to offset the missing class resource.",
          -- Mutually exclusive with "Expand Power Bar if No Resource": grey this while expand is on,
          -- but only when this is itself OFF (== "None") so a legacy profile with both on can still
          -- turn this off (no deadlock). Independent of "Show Class Resource" -- the shift setting is
          -- exactly what's wanted while the resource bar is hidden, so that toggle must NOT change this control's disabled state.
          disabled = function()
              local p = DB(); if not p then return false end
              -- Expand only blocks shift when EFFECTIVELY on (power bar enabled and not height-matched)
              local heightMatched = EllesmereUI.GetHeightMatchTarget and EllesmereUI.GetHeightMatchTarget("ERB_Power")
              local expandOn = p.primary.enabled and p.primary.expandIfNoResource and not heightMatched
              local shiftOff = (p.secondary.shiftElementsIfNoResource or "None") == "None"
              return expandOn and shiftOff and true or false
          end,
          disabledTooltip = "This option can't be used while Expand Power Bar if No Resource is enabled.",
          values = { None = "None", Up = "Up", Down = "Down" },
          order = { "None", "Up", "Down" },
          getValue = function() local p = DB(); return (p and p.secondary.shiftElementsIfNoResource) or "None" end,
          setValue = function(v)
              local p = DB(); if not p then return end
              p.secondary.shiftElementsIfNoResource = v
              -- Enabling shift turns off the mutually-exclusive expand option.
              if v ~= "None" then p.primary.expandIfNoResource = false end
              RebuildClass()
              EllesmereUI:RefreshPage()
          end },
        { type = "dropdown", text = "Shift Elements if No Power",
          tooltip = "Shifts any elements anchored to the power bar up or down to offset the missing power bar. Applies both when the Power Bar is disabled and for specs that have no power (for example, Beast Mastery and Marksmanship Hunters, whose Focus shows as the class resource bar).",
          -- Intentionally NOT disabled when the Power Bar is off: this setting is meant to fire precisely when the bar is disabled, so it must stay configurable in that state.
          values = { None = "None", Up = "Up", Down = "Down" },
          order = { "None", "Up", "Down" },
          getValue = function() local p = DB(); return (p and p.primary.shiftElementsIfNoPower) or "None" end,
          setValue = function(v)
              local p = DB(); if not p then return end
              p.primary.shiftElementsIfNoPower = v
              RebuildPower()
              EllesmereUI:RefreshPage()
          end }
    );  y = y - h
    -- Inline reposition cog on "Shift Elements if No Resource": Extra Y Offset
    if not EllesmereUI._prebuilding then
        local rgn = shiftRow._leftRegion
        EllesmereUI.BuildInlineCog(rgn, { icon = EllesmereUI.DIRECTIONS_ICON,
            title = "Shift Offset",
            rows = {
                { type = "slider", pixel = true, label = "Extra Y Offset", min = -50, max = 50, step = 1,
                  get = function() local p = DB(); return (p and p.secondary.shiftElementsIfNoResourceExtraY) or 0 end,
                  set = function(v)
                      local p = DB(); if not p then return end
                      p.secondary.shiftElementsIfNoResourceExtraY = v
                      RebuildClass()
                      -- BuildBars' cascade is edge-gated on the shift
                      -- DIRECTION, which a magnitude edit never flips --
                      -- re-cascade explicitly so the slider applies live
                      -- while the shift is active.
                      if EllesmereUI.PropagateAnchorChain then
                          EllesmereUI.PropagateAnchorChain("ERB_ClassResource")
                      end
                  end },
            },
        })
    end
    -- Inline reposition cog on "Shift Elements if No Power": Extra Y Offset
    if not EllesmereUI._prebuilding then
        local rgn = shiftRow._rightRegion
        EllesmereUI.BuildInlineCog(rgn, { icon = EllesmereUI.DIRECTIONS_ICON,
            title = "Shift Offset",
            rows = {
                { type = "slider", pixel = true, label = "Extra Y Offset", min = -50, max = 50, step = 1,
                  get = function() local p = DB(); return (p and p.primary.shiftElementsIfNoPowerExtraY) or 0 end,
                  set = function(v)
                      local p = DB(); if not p then return end
                      p.primary.shiftElementsIfNoPowerExtraY = v
                      RebuildPower()
                      -- Same explicit re-cascade as the class-resource
                      -- Shift Offset cog: the direction edge gate never
                      -- fires on a magnitude edit.
                      if EllesmereUI.PropagateAnchorChain then
                          EllesmereUI.PropagateAnchorChain("ERB_Power")
                      end
                  end },
            },
        })
    end

    -- Row 6 (stock styles only): Border Around All | (blank). One frame
    -- round the resource bars as a group. Greyed only while off, so a
    -- setting whose bars stop lining up can still be turned off.
    if ns.ERB_BorderAllRow() then
        local borderAllRow
        borderAllRow, h = W:DualRow(parent, y,
            { type = "toggle", text = "Border Around All",
              tooltip = "Draws one frame around the resource bars instead of one per bar.",
              disabled = function()
                  local p = DB(); if not p then return true end
                  if p.general.classicBorderAll then return false end
                  return not ns.ERB_GroupCheck(p)
              end,
              disabledTooltip = function()
                  local _, why = ns.ERB_GroupCheck(DB())
                  if why == "count" then return "This option requires at least two resource bars to be shown." end
                  if why == "orient" then return "This option requires the resource bars to share one orientation." end
                  return "This option requires the resource bars to be width matched to each other or to have matching widths."
              end,
              rawTooltip = true,
              getValue = function() local p = DB(); return (p and p.general.classicBorderAll) and true or false end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.general.classicBorderAll = v and true or false
                  -- One classic frame, one size: the lead bar's Border Size
                  -- for all three (Blizzard Style has no Border Size).
                  if v and ns.ERB_ClassicBorderRow() then
                      local s = ns.ERB_GroupLeadCfg(p).stockBorderScale
                      for i = 1, #CLASSIC_SYNC_KEYS do p[CLASSIC_SYNC_KEYS[i]].stockBorderScale = s end
                  end
                  Refresh()
                  -- The size-match pads follow the shared scale.
                  if EllesmereUI.ReapplyMatchPads then
                      for i = 1, #CLASSIC_MATCH_KEYS do EllesmereUI.ReapplyMatchPads(CLASSIC_MATCH_KEYS[i]) end
                  end
                  EllesmereUI:RefreshPage()
              end },
            { type = "label", text = "" }
        );  y = y - h
        -- Inline cog on "Border Around All" (stock styles only): the
        -- separator line between the grouped bars. Greyed while the toggle is
        -- off (its setter refreshes the page).
        if not EllesmereUI._prebuilding then
            local rgn = borderAllRow._leftRegion
            local function groupOff()
                local p = DB(); return not (p and p.general.classicBorderAll)
            end
            local function repaint()
                if ns.ERB_GroupDirty then ns.ERB_GroupDirty() end
            end
            EllesmereUI.BuildInlineCog(rgn, {
                disabled = groupOff, disabledTooltip = "Border Around All",
                title = "Border Around All",
                rows = {
                    { type = "slider", label = "Separator Border", min = 0, max = 5, step = 1,
                      get = function()
                          local p = DB(); local v = p and p.general.classicBorderAllSepSize
                          if v == nil then v = 1 end
                          return v
                      end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.general.classicBorderAllSepSize = v
                          repaint()
                      end },
                    { type = "colorpicker", label = "Separator Color",
                      get = function()
                          local p = DB(); local g = p and p.general
                          return (g and g.classicBorderAllSepR) or 0, (g and g.classicBorderAllSepG) or 0,
                              (g and g.classicBorderAllSepB) or 0, 1
                      end,
                      set = function(r, g, b)
                          local p = DB(); if not p then return end
                          p.general.classicBorderAllSepR, p.general.classicBorderAllSepG, p.general.classicBorderAllSepB = r, g, b
                          repaint()
                      end },
                },
            })
        end
    end

    _, h = W:Spacer(parent, y, 16);  y = y - h

    -- CLASS RESOURCE BAR (header + Row 1 etc. now via the shared builder)
    local classSection, classEnableRow, classResourceTextRow
    y, classSection, classEnableRow, classResourceTextRow = ns.ERB_BuildClassResourceSection(parent, y, {
        cfg = function() return DB().secondary end, advanced = false, syncRows = _syncRows,
    })

    -- Row: Anchor to Cursor | Cursor Position (cog: X + Y). Appended outside the shared section builder, so it carries its own hidden-while-disabled gate (the builder's toggle rebuilds on flips)
    if DB().secondary.enabled then
        local _, cursorH = EllesmereUI.BuildCursorAnchorRow({
            W = W, parent = parent, y = y,
            getData = function() local p = DB(); return p and p.secondary or {} end,
            onApply = function() RebuildClass(); SmoothRefresh() end,
        })
        y = y - cursorH
    end

    _, h = W:Spacer(parent, y, 16);  y = y - h

    -- POWER BAR (section header + Row 1 now via the shared builder)
    y = ns.ERB_BuildPowerSection(parent, y, {
        cfg = function() return DB().primary end, advanced = false, syncRows = _syncRows,
    })

    -- Row: Anchor to Cursor | Cursor Position (cog: X + Y). Appended outside the shared section builder, so it carries its own hidden-while-disabled gate (the builder's toggle rebuilds on flips)
    if DB().primary.enabled then
        local _, cursorH = EllesmereUI.BuildCursorAnchorRow({
            W = W, parent = parent, y = y,
            getData = function() local p = DB(); return p and p.primary or {} end,
            onApply = function() RebuildPower(); SmoothRefresh() end,
        })
        y = y - cursorH
    end

    -- Row 7: Power Type override (spec-dependent, like UF Power Type dropdown). Hidden with the rest of the Power section while the bar is off.
    if DB().primary.enabled then
        local _, playerClass = UnitClass("player")
        local SPEC_POWER_ALTS = {
            DRUID  = { [1] = { "Mana", "Astral Power" }, [2] = { "Energy", "Mana" }, [3] = { "Rage", "Mana" } },
            PRIEST = { [3] = { "Mana", "Insanity" } },
            SHAMAN = { [1] = { "Mana", "Maelstrom" } },
            EVOKER = { [3] = { "Ebon Might", "Mana" } },
        }
        local classAlts = SPEC_POWER_ALTS[playerClass]
        -- Retail only: WoW Forever has no specs (see the druid row below).
        if classAlts and not EllesmereUI.IS_FOREVER then
            local spec = GetSpecialization and GetSpecialization()
            local data = spec and classAlts[spec]
            if data then
                local ptValues = { ["default"] = data[1], ["alt"] = data[2] }
                local ptOrder  = { "default", "alt" }
                local powerTypeRow
                powerTypeRow, h = W:DualRow(parent, y,
                    { type="dropdown", text="Power Type",
                      values = ptValues, order = ptOrder,
                      -- Stored by SPEC ID, not the GetSpecialization() index:
                      -- one profile holds one set, so an index key collides
                      -- across classes (slot 3 is Guardian, Shadow AND
                      -- Augmentation, which want three different power types).
                      -- classAlts stays index-keyed, it is already per class.
                      getValue = function()
                          local s = GetSpecialization and GetSpecialization()
                          if not s or not classAlts[s] then return "default" end
                          local sid = C_SpecializationInfo
                              and C_SpecializationInfo.GetSpecializationInfo(s)
                          if not sid then return "default" end
                          local p = DB(); if not p then return "default" end
                          local ov = p.primary.powerTypeOverride
                          if ov and ov[sid] then return "alt" end
                          return "default"
                      end,
                      setValue = function(v)
                          local s = GetSpecialization and GetSpecialization()
                          if not s then return end
                          local sid = C_SpecializationInfo
                              and C_SpecializationInfo.GetSpecializationInfo(s)
                          if not sid then return end
                          local p = DB(); if not p then return end
                          if v == "alt" then
                              if not p.primary.powerTypeOverride then p.primary.powerTypeOverride = {} end
                              p.primary.powerTypeOverride[sid] = true
                          else
                              if p.primary.powerTypeOverride then p.primary.powerTypeOverride[sid] = nil end
                          end
                          RebuildPower()
                      end },
                    { type="label", text="" }); y = y - h

                local function UpdatePowerTypeRow()
                    local s = GetSpecialization and GetSpecialization()
                    if s and classAlts[s] then
                        powerTypeRow:Show()
                    else
                        powerTypeRow:Hide()
                    end
                end
                EllesmereUI.RegisterWidgetRefresh(UpdatePowerTypeRow)
                UpdatePowerTypeRow()
            end
        end
        -- WoW Forever: Mana Regen Spark and Spell Cost Prediction close the
        -- section (none for warriors and rogues). Other classes pair the two;
        -- a druid's spark shares its row with Power Type (one choice for all
        -- forms, stored under a string key so it never meets a retail spec
        -- ID), then Mana Bar while Shapeshifted, then Spell Cost Prediction.
        -- The cost row needs its engine loaded: the swatch reads its color rule.
        if EllesmereUI.IS_FOREVER then
            local SCP = EllesmereUI.SpellCostPrediction
            -- Off or one of two modes: a view over manaRegenSpark (on/off) and
            -- manaRegenSparkMode (nil = 5-Second Rule), so saved choices read as before.
            local sparkCfg = { type="dropdown", text="Mana Regen Spark",
                  tooltip="5-Second Rule sweeps a spark across the bar for 5 seconds after you spend mana, until mana regen resumes. Regen Ticks then keeps sweeping every 2 seconds while mana regenerates.",
                  values = { off = "Off", fsr = "5-Second Rule", ticks = "Regen Ticks" },
                  order = { "off", "fsr", "ticks" },
                  getValue = function()
                      local p = DB()
                      if not (p and p.primary.manaRegenSpark) then return "off" end
                      return p.primary.manaRegenSparkMode == "ticks" and "ticks" or "fsr"
                  end,
                  setValue = function(v)
                      local p = DB(); if not p then return end
                      p.primary.manaRegenSpark = v ~= "off"
                      if v ~= "off" then p.primary.manaRegenSparkMode = (v == "ticks") and "ticks" or nil end
                      RebuildPower()
                  end }
            local costCfg = { type="toggle", text="Spell Cost Prediction",
                  tooltip="While you cast, shows on the bar the mana the spell will cost.",
                  getValue = function()
                      local p = DB(); return p and p.primary.powerCostPrediction == true or false
                  end,
                  setValue = function(v)
                      local p = DB(); if not p then return end
                      p.primary.powerCostPrediction = v
                      RebuildPower(); EllesmereUI:RefreshPage()
                  end }
            -- Spell Cost Color, left of the toggle: dimmed and blocked
            -- while Spell Cost Prediction is off.
            local function CostSwatch(rgn)
                if EllesmereUI._prebuilding then return end
                EllesmereUI.BuildInlineSwatches(rgn, {
                    { tooltip = "Spell Cost Color",
                      getValue = function()
                          local p = DB()
                          local r, g, b = SCP.Color(p and p.primary)
                          return r, g, b, 1
                      end,
                      setValue = function(r, g, b)
                          local p = DB(); if not p then return end
                          p.primary.powerCostColor = { r = r, g = g, b = b }
                      end },
                }, { disabled = function()
                         local p = DB(); return not (p and p.primary.powerCostPrediction == true)
                     end,
                     disabledTooltip = "Spell Cost Prediction", size = 20 })
            end
            if playerClass == "DRUID" then
                _, h = W:DualRow(parent, y,
                    { type="dropdown", text="Power Type",
                      tooltip="Mana keeps the bar on Mana in Bear and Cat Form.",
                      values = { ["default"] = "Match Form", ["alt"] = "Mana" },
                      order = { "default", "alt" },
                      getValue = function()
                          local p = DB(); local ov = p and p.primary.powerTypeOverride
                          return (ov and ov.foreverDruid) and "alt" or "default"
                      end,
                      setValue = function(v)
                          local p = DB(); if not p then return end
                          if v == "alt" then
                              if not p.primary.powerTypeOverride then p.primary.powerTypeOverride = {} end
                              p.primary.powerTypeOverride.foreverDruid = true
                          elseif p.primary.powerTypeOverride then
                              p.primary.powerTypeOverride.foreverDruid = nil
                          end
                          RebuildPower(); EllesmereUI:RefreshPage()
                      end },
                    sparkCfg); y = y - h

                -- Mana Bar while Shapeshifted (EUI_ResourceBars_ForeverDruidMana.lua):
                -- a thin mana bar attached to the Power Bar in Bear and Cat Form.
                -- Its settings exist only on Forever (defaults primary.foreverDruidMana).
                -- Edits go straight to the module: the companion is not part of the
                -- bar build, so a full ApplyAll would rebuild every bar.
                local function FdmCfg()
                    local p = DB(); return p and p.primary.foreverDruidMana
                end
                local function FdmTypeMana()
                    local p = DB(); local ov = p and p.primary.powerTypeOverride
                    return (ov and ov.foreverDruid) and true or false
                end
                local function FdmOff()
                    if FdmTypeMana() then return true end
                    local t = FdmCfg()
                    return not (t and t.enabled)
                end
                local function FdmOffTip()
                    if FdmTypeMana() then return "This option requires Power Type to be set to Match Form" end
                    return "Mana Bar while Shapeshifted"
                end
                local function FdmTextDis()
                    if FdmOff() then return true end
                    local t = FdmCfg()
                    return (t and t.textFormat or "none") == "none"
                end
                local function FdmTextDisTip()
                    if FdmOff() then return FdmOffTip() end
                    return "This option requires a Mana Bar Text format other than None"
                end
                local function RefreshFDM()
                    if ns.FDM_Apply then ns.FDM_Apply() end
                end
                local fdmRow
                fdmRow, h = W:DualRow(parent, y,
                    { type="toggle", text="Mana Bar while Shapeshifted",
                      tooltip="Shows a thin mana bar with the Power Bar while in Bear and Cat Form.",
                      disabled = FdmTypeMana,
                      disabledTooltip = "This option requires Power Type to be set to Match Form",
                      getValue = function()
                          local t = FdmCfg(); return t and t.enabled or false
                      end,
                      setValue = function(v)
                          local t = FdmCfg(); if not t then return end
                          t.enabled = v
                          RefreshFDM(); EllesmereUI:RefreshPage()
                      end },
                    { type="dropdown", text="Mana Bar Text",
                      disabled = FdmOff,
                      disabledTooltip = FdmOffTip,
                      values = { none = "None", smart = "Smart Text", curpp = "Power Value", perpp = "Power %", both = "Power Value | Power %" },
                      order = { "none", "smart", "curpp", "perpp", "both" },
                      getValue = function()
                          local t = FdmCfg(); return t and t.textFormat or "none"
                      end,
                      setValue = function(v)
                          local t = FdmCfg(); if not t then return end
                          t.textFormat = v
                          RefreshFDM(); EllesmereUI:RefreshPage()
                      end }); y = y - h
                if not EllesmereUI._prebuilding then
                    -- Placement cog: position, gap, height, offsets
                    EllesmereUI.BuildInlineCog(fdmRow._leftRegion, { icon = EllesmereUI.DIRECTIONS_ICON,
                        disabled = FdmOff,
                        disabledTooltip = FdmOffTip,
                        title = "Mana Bar",
                        rows = {
                            { type = "dropdown", label = "Anchor",
                              values = { powerbar = "Power Bar", healthbar = "Health Bar" },
                              order = { "powerbar", "healthbar" },
                              tooltip = "What the mana bar attaches to. Power Bar rides the Power Bar (default). Health Bar attaches to the player health bar: with Position Inside it embeds into the health bar (carving a strip); Below / Above float next to it.",
                              get = function() local t = FdmCfg(); return t and t.anchor or "powerbar" end,
                              set = function(v)
                                  local t = FdmCfg(); if not t then return end
                                  t.anchor = v; RefreshFDM()
                              end },
                            { type = "dropdown", label = "Position",
                              values = { below = "Below", above = "Above", inside = "Inside" },
                              order = { "below", "above", "inside" },
                              tooltip = "On a vertical Power Bar, Below is the right side and Above is the left side.",
                              get = function() local t = FdmCfg(); return t and t.position or "below" end,
                              set = function(v)
                                  local t = FdmCfg(); if not t then return end
                                  t.position = v; RefreshFDM()
                              end },
                            { type = "slider", pixel = true, label = "Gap", min = 0, max = 20, step = 1,
                              disabled = function()
                                  local t = FdmCfg(); return (t and t.position == "inside") and true or false
                              end,
                              disabledTooltip = "This option requires Position to be Below or Above",
                              get = function() local t = FdmCfg(); return t and t.gap or 2 end,
                              set = function(v)
                                  local t = FdmCfg(); if not t then return end
                                  t.gap = v; RefreshFDM()
                              end },
                            { type = "slider", label = "Height", min = 2, max = 30, step = 1,
                              get = function() local t = FdmCfg(); return t and t.height or 6 end,
                              set = function(v)
                                  local t = FdmCfg(); if not t then return end
                                  t.height = v; RefreshFDM()
                              end },
                            { type = "slider", label = "X Offset", min = -100, max = 100, step = 1,
                              get = function() local t = FdmCfg(); return t and t.offsetX or 0 end,
                              set = function(v)
                                  local t = FdmCfg(); if not t then return end
                                  t.offsetX = v; RefreshFDM()
                              end },
                            { type = "slider", label = "Y Offset", min = -100, max = 100, step = 1,
                              get = function() local t = FdmCfg(); return t and t.offsetY or 0 end,
                              set = function(v)
                                  local t = FdmCfg(); if not t then return end
                                  t.offsetY = v; RefreshFDM()
                              end },
                        },
                    })
                    -- Text colour, left of the Mana Bar Text dropdown: custom colour
                    -- or the mana colour, like the Power Text swatches. The text cog
                    -- below chains left of them.
                    EllesmereUI.BuildInlineSwatches(fdmRow._rightRegion, {
                        { tooltip = "Custom Colored",
                          hasAlpha = true,
                          getValue = function()
                              local t = FdmCfg()
                              if not t then return 1, 1, 1, 1 end
                              return t.textFillR or 1, t.textFillG or 1, t.textFillB or 1, t.textFillA or 1
                          end,
                          setValue = function(r, g, b, a)
                              local t = FdmCfg(); if not t then return end
                              t.textFillR, t.textFillG, t.textFillB, t.textFillA = r, g, b, a
                              RefreshFDM()
                          end,
                          onClick = function(self)
                              local t = FdmCfg(); if not t then return end
                              if t.textCustomColored == false then
                                  t.textCustomColored = true; RefreshFDM()
                                  EllesmereUI:RefreshPage()
                                  return
                              end
                              if self._eabOrigClick then self._eabOrigClick(self) end
                          end,
                          refreshAlpha = function()
                              local t = FdmCfg()
                              return (t and t.textCustomColored == false) and 0.3 or 1
                          end },
                        { tooltip = "Mana Colored",
                          getValue = function()
                              local pc = _G._ERB_PowerColors and _G._ERB_PowerColors.MANA
                              if pc then return pc[1], pc[2], pc[3], 1 end
                              return 0x23/255, 0x8F/255, 0xE7/255, 1
                          end,
                          setValue = function() end,
                          onClick = function()
                              local t = FdmCfg(); if not t then return end
                              t.textCustomColored = false; RefreshFDM()
                              EllesmereUI:RefreshPage()
                          end,
                          refreshAlpha = function()
                              local t = FdmCfg()
                              return (t and t.textCustomColored == false) and 1 or 0.3
                          end },
                    }, { disabled = FdmTextDis, disabledTooltip = FdmTextDisTip, size = 20 })
                    -- Text cog: the Power Text cog's options plus Text Size
                    EllesmereUI.BuildInlineCog(fdmRow._rightRegion, { icon = EllesmereUI.DIRECTIONS_ICON,
                        disabled = FdmTextDis,
                        disabledTooltip = FdmTextDisTip,
                        title = "Mana Bar Text",
                        rows = {
                            { type = "slider", label = "Text Size", min = 8, max = 24, step = 1,
                              get = function() local t = FdmCfg(); return t and t.textSize or 8 end,
                              set = function(v)
                                  local t = FdmCfg(); if not t then return end
                                  t.textSize = v; RefreshFDM()
                              end },
                            { type = "toggle", label = "Show %",
                              get = function() local t = FdmCfg(); return (not t) or t.showPercent ~= false end,
                              set = function(v)
                                  local t = FdmCfg(); if not t then return end
                                  t.showPercent = v; RefreshFDM()
                              end },
                            { type = "dropdown", label = "Anchor",
                              values = { LEFT = "Left", CENTER = "Center", RIGHT = "Right" },
                              order = { "LEFT", "CENTER", "RIGHT" },
                              tooltip = "Anchor the text inside the bar. The X/Y offsets move it from there.",
                              get = function() local t = FdmCfg(); return t and t.textAnchor or "CENTER" end,
                              set = function(v)
                                  local t = FdmCfg(); if not t then return end
                                  t.textAnchor = v; RefreshFDM()
                              end },
                            { type = "slider", label = "X Offset", min = -100, max = 100, step = 1,
                              get = function() local t = FdmCfg(); return t and t.textXOffset or 0 end,
                              set = function(v)
                                  local t = FdmCfg(); if not t then return end
                                  t.textXOffset = v; RefreshFDM()
                              end },
                            { type = "slider", label = "Y Offset", min = -100, max = 100, step = 1,
                              get = function() local t = FdmCfg(); return t and t.textYOffset or 0 end,
                              set = function(v)
                                  local t = FdmCfg(); if not t then return end
                                  t.textYOffset = v; RefreshFDM()
                              end },
                        },
                    })
                end
                if SCP then
                    local costRow
                    costRow, h = W:DualRow(parent, y, costCfg, EllesmereUI.BlankRowCfg()); y = y - h
                    CostSwatch(costRow._leftRegion)
                end
            elseif EllesmereUI.ManaRegenSpark then
                if SCP then
                    local costRow
                    costRow, h = W:DualRow(parent, y, costCfg, sparkCfg); y = y - h
                    CostSwatch(costRow._leftRegion)
                else
                    _, h = W:DualRow(parent, y, sparkCfg, EllesmereUI.BlankRowCfg()); y = y - h
                end
            end
        end
    end

    _, h = W:Spacer(parent, y, 16);  y = y - h

    -- HEALTH BAR (section header + Row 1 now via the shared builder)
    y = ns.ERB_BuildHealthSection(parent, y, {
        cfg = function() return DB().health end, advanced = false, syncRows = _syncRows,
    })

    -- Row: Anchor to Cursor | Cursor Position (cog: X + Y). Appended outside the shared section builder, so it carries its own hidden-while-disabled gate (the builder's toggle rebuilds on flips)
    if DB().health.enabled then
        local _, cursorH = EllesmereUI.BuildCursorAnchorRow({
            W = W, parent = parent, y = y,
            getData = function() local p = DB(); return p and p.health or {} end,
            onApply = function() RebuildHealth(); SmoothRefresh() end,
        })
        y = y - cursorH
    end

    _, h = W:Spacer(parent, y, 16);  y = y - h

    -- ARCANE SOUL (SUNFURY)
    -- Mage-only: the section is absent entirely for every other class rather
    -- than built and disabled, since nothing in it can ever apply to them.
    -- The spec/hero-tree gate itself lives in the module (it changes at
    -- runtime); this only decides whether the controls exist at all.
    if select(2, UnitClass("player")) == "MAGE" then
        -- Straight to the module: this display is not part of the bar build,
        -- so a full ApplyAll would rebuild every bar to retint one string.
        local function RefreshAS()
            if ns.AS_Apply then ns.AS_Apply() end
        end
        local asOff = function() local p = DB(); return p and not p.arcaneSoul.enabled end
        local AS_TIP = "Arcane Soul Helper"

        _, h = W:SectionHeader(parent, "ARCANE SOUL (SUNFURY)", y);  y = y - h

        -- Row: Enable Arcane Soul Helper (+ position cog) | Show Threshold
        local asEnableRow
        asEnableRow, h = W:DualRow(parent, y,
            { type = "toggle", text = "Enable Arcane Soul Helper",
              tooltip = "Shows a countdown to the Arcane Soul window over the last seconds of Arcane Surge, then the time left inside it. Sunfury Arcane Mages only.",
              getValue = function() local p = DB(); return p and p.arcaneSoul.enabled end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.arcaneSoul.enabled = v; RefreshAS(); EllesmereUI:RefreshPage()
              end },
            { type = "slider", text = "Show Threshold", min = 1, max = 15, step = 1,
              tooltip = "Seconds of Arcane Surge left when the countdown appears. Always in seconds, including in GCD mode.",
              disabled = asOff, disabledTooltip = AS_TIP,
              getValue = function() local p = DB(); return p and p.arcaneSoul.threshold or 5 end,
              setValue = function(v) local p = DB(); if not p then return end; p.arcaneSoul.threshold = v; RefreshAS() end }
        );  y = y - h

        -- Inline position cog (X/Y + unlock) on Enable, as on the GCD Bar page
        if not EllesmereUI._prebuilding then
            local rgn = asEnableRow._leftRegion
            EllesmereUI.BuildInlineCog(rgn, { icon = EllesmereUI.DIRECTIONS_ICON,
                disabled = function() local p = DB(); return p and not p.arcaneSoul.enabled end,
                disabledTooltip = AS_TIP,
                title = "Arcane Soul Position",
                rows = {
                    { type = "slider", label = "X Offset", min = -600, max = 600, step = 1,
                      get = function()
                          local p = DB(); if not p then return 0 end
                          local a = p.arcaneSoul
                          return (a.unlockPos and a.unlockPos.x) or 0
                      end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          local a = p.arcaneSoul
                          -- No separate offset pair for this display: the cog edits
                          -- the same saved position the mover writes, seeding it
                          -- from the default the renderer falls back to.
                          a.unlockPos = a.unlockPos or { point = "CENTER", relPoint = "CENTER", x = 0, y = -150 }
                          a.unlockPos.x = v
                          RefreshAS()
                      end },
                    { type = "slider", label = "Y Offset", min = -600, max = 600, step = 1,
                      get = function()
                          local p = DB(); if not p then return -150 end
                          local a = p.arcaneSoul
                          return (a.unlockPos and a.unlockPos.y) or -150
                      end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          local a = p.arcaneSoul
                          a.unlockPos = a.unlockPos or { point = "CENTER", relPoint = "CENTER", x = 0, y = -150 }
                          a.unlockPos.y = v
                          RefreshAS()
                      end },
                },
                footer = { unlockKey = "EUI_ArcaneSoul" },
            })
        end

        -- Row: Countdown Format | Text Size
        local asFormatValues = {
            ["seconds"]    = { text = "Seconds" },
            ["gcd"]        = { text = "GCD Count" },
            ["secondsGcd"] = { text = "Seconds + GCD in Soul" },
        }
        local asFormatOrder = { "seconds", "gcd", "secondsGcd" }
        -- The LAST warning only exists where the Soul window counts Barrages.
        local function AsSoulCountsGcd()
            local p = DB()
            local m = p and p.arcaneSoul.countMode
            return m == "gcd" or m == "secondsGcd"
        end
        _, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Countdown Format",
              tooltip = "Seconds counts the time down in tenths. GCD Count counts whole global cooldowns instead, so inside Arcane Soul it reads as the number of Arcane Barrages that still fit, ending on a coloured LAST. Seconds + GCD in Soul mixes the two: tenths counting down to the window, Barrage count once it opens.",
              disabled = asOff, disabledTooltip = AS_TIP,
              values = asFormatValues, order = asFormatOrder,
              getValue = function() local p = DB(); return p and p.arcaneSoul.countMode or "seconds" end,
              setValue = function(v) local p = DB(); if not p then return end; p.arcaneSoul.countMode = v; RefreshAS() end },
            { type = "slider", text = "Text Size", min = 10, max = 48, step = 1,
              disabled = asOff, disabledTooltip = AS_TIP,
              getValue = function() local p = DB(); return p and p.arcaneSoul.textSize or 24 end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.arcaneSoul.textSize = v; RefreshAS()
                  if EllesmereUI.NotifyElementResized then
                      EllesmereUI.NotifyElementResized("EUI_ArcaneSoul")
                  end
              end }
        );  y = y - h

        -- Row: Font | Font Outline (mirrors the Battle Res text controls)
        do
            local asFontValues, asFontOrder = EllesmereUI.BuildFontDropdownData()
            local asOutlineValues = {
                ["__global"] = { text = "EUI Global Default" },
                ["none"]     = { text = "Drop Shadow" },
                ["outline"]  = { text = "Outline" },
                ["thick"]    = { text = "Thick Outline" },
            }
            local asOutlineOrder = { "__global", "none", "outline", "thick" }
            _, h = W:DualRow(parent, y,
                { type = "dropdown", text = "Font",
                  disabled = asOff, disabledTooltip = AS_TIP,
                  values = asFontValues, order = asFontOrder,
                  getValue = function() local p = DB(); return p and p.arcaneSoul.font or "__global" end,
                  setValue = function(v) local p = DB(); if not p then return end; p.arcaneSoul.font = v; RefreshAS() end },
                { type = "dropdown", text = "Font Outline",
                  disabled = asOff, disabledTooltip = AS_TIP,
                  values = asOutlineValues, order = asOutlineOrder,
                  getValue = function() local p = DB(); return p and p.arcaneSoul.outlineMode or "__global" end,
                  setValue = function(v) local p = DB(); if not p then return end; p.arcaneSoul.outlineMode = v; RefreshAS() end }
            );  y = y - h
        end

        -- Row: Colors (pre-Soul / in-Soul / final GCD)
        _, h = W:DualRow(parent, y,
            { type = "multiSwatch", text = "Colors",
              disabled = asOff, disabledTooltip = AS_TIP,
              swatches = {
                { tooltip = "Countdown to Soul", hasAlpha = false,
                  getValue = function()
                      local p = DB(); if not p then return 1, 1, 1 end
                      local a = p.arcaneSoul
                      return a.preR or 0.64, a.preG or 0.21, a.preB or 0.93
                  end,
                  setValue = function(r, g, b)
                      local p = DB(); if not p then return end
                      local a = p.arcaneSoul
                      a.preR, a.preG, a.preB = r, g, b
                      RefreshAS()
                  end },
                { tooltip = "Inside Soul", hasAlpha = false,
                  getValue = function()
                      local p = DB(); if not p then return 1, 1, 1 end
                      local a = p.arcaneSoul
                      return a.soulR or 0.64, a.soulG or 0.21, a.soulB or 0.93
                  end,
                  setValue = function(r, g, b)
                      local p = DB(); if not p then return end
                      local a = p.arcaneSoul
                      a.soulR, a.soulG, a.soulB = r, g, b
                      RefreshAS()
                  end },
                -- Only ever rendered in GCD Count mode (the LAST warning).
                { tooltip = "Last Barrage", hasAlpha = false,
                  disabled = function()
                      local p = DB()
                      return not p or not p.arcaneSoul.enabled or not AsSoulCountsGcd()
                  end,
                  disabledTooltip = "This option requires Countdown Format to count GCDs inside Arcane Soul",
                  getValue = function()
                      local p = DB(); if not p then return 1, 1, 1 end
                      local a = p.arcaneSoul
                      return a.lastR or 1.0, a.lastG or 0.25, a.lastB or 0.25
                  end,
                  setValue = function(r, g, b)
                      local p = DB(); if not p then return end
                      local a = p.arcaneSoul
                      a.lastR, a.lastG, a.lastB = r, g, b
                      RefreshAS()
                  end },
              } },
            { type = "label", text = "" }
        );  y = y - h

        _, h = W:Spacer(parent, y, 16);  y = y - h
    end

    -- Wire up click mappings for preview hit overlays (never from a hidden pre-build: the shared live table would end up pointing at off-screen rows).
    if not EllesmereUI._prebuilding then
        _clickMappings.classResource = { section = classSection, target = classEnableRow }
        -- The Resource Text row lives inside the shared class-resource section builder, so it must be returned from there -- naming a local from that scope here silently resolves to nil and the count-text click does nothing.
        _clickMappings.countText = { section = classSection, target = classResourceTextRow, slotSide = "left" }
    end

    return math.abs(y)
end
