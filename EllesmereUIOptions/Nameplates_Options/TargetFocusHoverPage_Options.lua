if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Nameplates_Options\TargetFocusHoverPage_Options.lua
--  Nameplates options: the Target, Focus & Hover page
--  (BuildTargetFocusHoverPage). Definitions only; the shared helpers come
--  from ns._NPO_OptEnv (filled by EUI_Nameplates_Options.lua).
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUINameplates"]
if not ns then return end  -- module disabled: no options page

local function BuildTargetFocusHoverPage(pageName, parent, yOffset)
    local env = ns._NPO_OptEnv
    local DB, DBColor, DBVal, defaults = env.DB, env.DBColor, env.DBVal, env.defaults
    local FOCUS_LETTER_ANCHOR_ORDER, FOCUS_LETTER_ANCHORS = env.FOCUS_LETTER_ANCHOR_ORDER, env.FOCUS_LETTER_ANCHORS
    local GetFocusLetterAnchor, GetNPOptOutline, hbtOrder, hbtValues = env.GetFocusLetterAnchor, env.GetNPOptOutline, env.hbtOrder, env.hbtValues
    local pairs, plates = env.pairs, env.plates
    local PP, RefreshAllPlates, RefreshAllTextures, SliderLabel = env.PP, env.RefreshAllPlates, env.RefreshAllTextures, env.SliderLabel
    local Nav, SearchWords, UpdatePreview = env.Nav, env.SearchWords, env.UpdatePreview
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h
    -- The section headers and rows the header preview's click navigation lands on
    local targetHdr, focusHdr, hoverHdr, hoverRow

    -- The nameplate preview and its Target / Focus / Hover picker in the content header
    EllesmereUI:SetContentHeader(ns.NPO_BuildTFHHeader)

    -- Enable per-row center divider for the dual-column layout
    parent._showRowDivider = true

    -----------------------------------------------------------------------
    --  TARGET
    -----------------------------------------------------------------------
    -- Global Search also finds each section by the two section names its
    -- rows are known by.
    SearchWords("TARGET", nil, "TARGET, FOCUS & HOVER EFFECTS", "TARGET AND FOCUS EFFECTS")
    targetHdr, h = W:SectionHeader(parent, "TARGET", y);  y = y - h

    local targetGlowRow
    -- Build the arrow-style dropdown options from the shared style table.
    local arrowVals = { none = "None" }
    local arrowOrd = { "none" }
    for _, k in ipairs(ns.TARGET_ARROW_ORDER) do
        arrowVals[k] = ns.TARGET_ARROW_STYLES[k].label
        arrowOrd[#arrowOrd + 1] = k
    end
    -- Preview the right-arrow texture on the right of each dropdown row.
    arrowVals._menuOpts = {
        itemHeight = 26,
        icon = function(key)
            local st = ns.TARGET_ARROW_STYLES[key]
            if not st then return nil end  -- "none" has no preview
            return ns.TARGET_ARROW_DIR .. st.l .. ".png"
        end,
        iconWidth = function(key)
            local st = ns.TARGET_ARROW_STYLES[key]
            if not st then return nil end
            -- Match in-game aspect: drawn width is st.w at height 16, icon slot is itemHeight(32)-8=24 tall, so scale width by 24/16.
            return math.floor(st.w * 24 / 16 + 0.5)
        end,
    }
    -- A checklist's stand-in dropdown reads the keys the checklist writes, so Spec
    -- Overrides know the slot by them (its gold mark, and the entry it already has).
    local function ChecklistReads(a, b, c, d)
        return function()
            local _ = DBVal(a), DBVal(b), DBVal(c), DBVal(d)
            return "__placeholder"
        end
    end
    targetGlowRow, h = W:DualRow(parent, y,
        { type="dropdown", text="Target Effect",
          values={ __placeholder = "..." }, order={ "__placeholder" },
          getValue=ChecklistReads("targetGlowEllesmereUI", "targetGlowBorderColor", "targetGlowHighlight", "targetGlowBorderSize"),
          setValue=function() end },
        { type="dropdown", text="Target Arrows",
          values=arrowVals,
          order=arrowOrd,
          getValue=function()
            if DBVal("showTargetArrows") ~= true then return "none" end
            return DBVal("targetArrowStyle") or (DBVal("targetArrowDouble") and "double") or "simple"
          end,
          setValue=function(v)
            if v == "none" then
                DB().showTargetArrows = false
            else
                DB().showTargetArrows = true
                DB().targetArrowStyle = v
            end
            for _, plate in pairs(plates) do
                plate:ApplyTarget()
            end
            UpdatePreview()
            EllesmereUI:RefreshPage()  -- the arrow cog and swatches grey with None
          end });  y = y - h

    -- Target Effect: multi-select checkbox dropdown (EUI Glow/Border Color/Highlight), independent toggles; data model live-converts from the legacy targetGlowStyle string (see ns.GetTargetGlow* in the core file).
    local refreshTargetBorderSwatch  -- fwd decl; assigned when the swatch builds
    local refreshTargetGlowSwatch    -- fwd decl; assigned when the glow swatch builds
    local refreshTargetHighlightCog  -- fwd decl; assigned when the cog builds
    if not EllesmereUI._prebuilding then
        local leftRgn = targetGlowRow._leftRegion
        if leftRgn._control then leftRgn._control:Hide() end
        -- The WoW Forever style offers Highlight alone: the other three are
        -- locked there (their getters read off, so they draw nothing).
        local function fvLocked() return EllesmereUI.BlizzStyle.Forever("nameplates") end
        local function fvTip() return EllesmereUI.L("Not available in the WoW Forever style.") end
        local glowItems = {
            { key = "ellesmereui", label = "EUI Glow", lockedFn = fvLocked, lockedTooltip = fvTip },
            { key = "borderColor", label = "Border Color", lockedFn = fvLocked, lockedTooltip = fvTip },
            { key = "highlight",   label = "Highlight" },
            { key = "borderSize",  label = "Border Size",
              tooltip = "Change Size in the Cogwheel", lockedFn = fvLocked, lockedTooltip = fvTip },
        }
        local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
            leftRgn, 170, leftRgn:GetFrameLevel() + 2,
            glowItems,
            function(k)
                if k == "ellesmereui" then return ns.GetTargetGlowEllesmereUI() end
                if k == "borderColor" then return ns.GetTargetGlowBorderColor() end
                if k == "highlight"   then return ns.GetTargetGlowHighlight() end
                if k == "borderSize"  then return ns.GetTargetGlowBorderSize() end
                return false
            end,
            function(k, v)
                if k == "ellesmereui" then DB().targetGlowEllesmereUI = v
                elseif k == "borderColor" then DB().targetGlowBorderColor = v
                elseif k == "highlight" then DB().targetGlowHighlight = v
                elseif k == "borderSize" then
                    DB().targetGlowBorderSize = v
                    -- First-enable snapshot: seed the cog slider with the user's CURRENT border size, so enabling changes nothing until they move it (one-time, never re-snapshots later).
                    if v and DB().targetBorderSizeValue == nil then
                        if ns.IsCustomBorderEnabled() then
                            DB().targetBorderSizeValue = DBVal("customBorderSize") or defaults.customBorderSize
                        else
                            DB().targetBorderSizeValue = DBVal("borderSize") or defaults.borderSize
                        end
                    end
                end
                for _, plate in pairs(plates) do plate:ApplyTarget() end
                for _, fp in pairs(ns.friendlyPlates) do fp:ApplyTarget() end
                UpdatePreview()
                if refreshTargetBorderSwatch then refreshTargetBorderSwatch() end
                if refreshTargetGlowSwatch then refreshTargetGlowSwatch() end
                if refreshTargetHighlightCog then refreshTargetHighlightCog() end
            end)
        PP.Point(cbDD, "RIGHT", leftRgn, "RIGHT", -20, 0)
        leftRgn._control = cbDD
        leftRgn._lastInline = nil
        EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)

        -- Inline cog "More Effects": Highlight color/opacity + Glow opacity; enabled when Highlight OR EUI Glow is on (Glow Opacity reachable whenever the glow is active).
        do
            local function highlightCogOff()
                return not (ns.GetTargetGlowHighlight() or ns.GetTargetGlowEllesmereUI()
                    or ns.GetTargetGlowBorderSize())
            end
            local highlightCogBtn = EllesmereUI.BuildInlineCog(leftRgn, {
                disabled = highlightCogOff,
                disabledTooltip = "a Target Effect",
                title = "More Effects",
                rows = {
                    { type="colorpicker", label="Highlight Color", hasAlpha=false,
                      get=function() local c = ns.GetTargetHighlightColor(); return c.r, c.g, c.b end,
                      set=function(r, g, b)
                        DB().targetHighlightColor = { r = r, g = g, b = b }
                        for _, plate in pairs(plates) do plate:ApplyTarget() end
                        UpdatePreview()
                      end },
                    { type="slider", label="Highlight Opacity", min=0, max=100, step=1,
                      get=function() return math.floor((ns.GetTargetHighlightAlpha() * 100) + 0.5) end,
                      set=function(v)
                        DB().targetHighlightAlpha = v / 100
                        for _, plate in pairs(plates) do plate:ApplyTarget() end
                        UpdatePreview()
                      end },
                    { type="slider", label="Glow Opacity", min=0, max=100, step=1,
                      disabled=fvLocked, disabledTooltip=fvTip, rawTooltip=true,
                      get=function() return math.floor((ns.GetTargetGlowAlpha() * 100) + 0.5) end,
                      set=function(v)
                        DB().targetGlowAlpha = v / 100
                        for _, plate in pairs(plates) do plate:ApplyTarget() end
                        UpdatePreview()
                      end },
                    { type="slider", label="Border Size", min=0, max=4, step=1,
                      get=function()
                        local v = DBVal("targetBorderSizeValue")
                        if v ~= nil then return v end
                        -- Not snapshotted yet: show the current border size.
                        if ns.IsCustomBorderEnabled() then
                            return DBVal("customBorderSize") or defaults.customBorderSize
                        end
                        return DBVal("borderSize") or defaults.borderSize
                      end,
                      set=function(v)
                        DB().targetBorderSizeValue = v
                        for _, plate in pairs(plates) do plate:ApplyTarget() end
                        for _, fp in pairs(ns.friendlyPlates) do fp:ApplyTarget() end
                        UpdatePreview()
                      end,
                      disabled=function() return not ns.GetTargetGlowBorderSize() end,
                      disabledTooltip=function()
                        if fvLocked() then return fvTip() end
                        return "Border Size Target Effect"
                      end,
                      rawTooltip=fvLocked },
                },
            })
            refreshTargetHighlightCog = highlightCogBtn and highlightCogBtn._euiCogState
        end

        -- Inline Border Color swatch: edits targetBorderColor (default white), tints the custom border; dimmed+non-interactive unless Border Color is checked.
        local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5,
            function() local c = ns.GetTargetBorderColor(); return c.r, c.g, c.b end,
            function(r, g, b)
                DB().targetBorderColor = { r = r, g = g, b = b }
                for _, plate in pairs(plates) do plate:ApplyTarget() end
                for _, fp in pairs(ns.friendlyPlates) do fp:ApplyTarget() end
                UpdatePreview()
            end, nil, 20)
        PP.Point(swatch, "RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -8, 0)
        leftRgn._lastInline = swatch
        -- Tooltip so the swatch's purpose is clear (shown while interactive, i.e. Border Color on).
        swatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(swatch, "Border Color") end)
        swatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        refreshTargetBorderSwatch = function()
            local off = not ns.GetTargetGlowBorderColor()
            swatch:SetAlpha(off and 0.15 or 1)
            swatch:EnableMouse(not off)
            updateSwatch()
        end
        EllesmereUI.RegisterWidgetRefresh(refreshTargetBorderSwatch)
        refreshTargetBorderSwatch()

        -- Inline Glow Color swatch: edits targetGlowColor (default the signature blue), tints the EUI background glow; dimmed+non-interactive unless EUI Glow is checked.
        local glowSwatch, updateGlowSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5,
            function() local c = ns.GetTargetGlowColor(); return c.r, c.g, c.b end,
            function(r, g, b)
                DB().targetGlowColor = { r = r, g = g, b = b }
                for _, plate in pairs(plates) do plate:ApplyTarget() end
                UpdatePreview()
            end, nil, 20)
        PP.Point(glowSwatch, "RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -8, 0)
        leftRgn._lastInline = glowSwatch
        glowSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(glowSwatch, "Glow Color") end)
        glowSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        refreshTargetGlowSwatch = function()
            local off = not ns.GetTargetGlowEllesmereUI()
            glowSwatch:SetAlpha(off and 0.15 or 1)
            glowSwatch:EnableMouse(not off)
            updateGlowSwatch()
        end
        EllesmereUI.RegisterWidgetRefresh(refreshTargetGlowSwatch)
        refreshTargetGlowSwatch()
    end

    -- Inline cog (arrow scale), beside the control; the swatches sit left of it
    do
        local rightRgn = targetGlowRow._rightRegion
        local arrowOff = function() return DBVal("showTargetArrows") ~= true end
        EllesmereUI.BuildInlineCog(rightRgn, {
            disabled = arrowOff,
            disabledTooltip = "Target Arrows",
            title = "Arrow Scale",
            rows = {
                { type="slider", label="Scale", min=0.5, max=3.0, step=0.1,
                  get=function() return DBVal("targetArrowScale") or defaults.targetArrowScale or 1.0 end,
                  set=function(v)
                    DB().targetArrowScale = v
                    local _scKey = DBVal("targetArrowStyle") or (DBVal("targetArrowDouble") and "double") or "simple"
                    local _scW = (ns.TARGET_ARROW_STYLES[_scKey] or ns.TARGET_ARROW_STYLES.simple).w
                    for _, plate in pairs(plates) do
                        local sc = v
                        local aw = math.floor(_scW * sc + 0.5)
                        local ah = math.floor(16 * sc + 0.5)
                        if plate.leftArrow then PP.Size(plate.leftArrow, aw, ah) end
                        if plate.rightArrow then PP.Size(plate.rightArrow, aw, ah) end
                    end
                    UpdatePreview()
                  end },
            },
        })
    end

    -- Inline Custom + Class color swatches on Target Arrows (custom adjacent to the cog, class to its left); click to switch, inactive swatch dims, both gray out when arrows off.
    do
        local rightRgn = targetGlowRow._rightRegion
        local arrowOff = function() return DBVal("showTargetArrows") ~= true end
        local customSwatch, updateCustom, classSwatch, updateClass
        local function refreshArrowSwatches()
            if updateCustom then updateCustom() end
            if updateClass then updateClass() end
            local off = arrowOff()
            local useClass = DBVal("targetArrowClassColor") == true
            customSwatch:SetAlpha(off and 0.15 or (useClass and 0.3 or 1))
            classSwatch:SetAlpha(off and 0.15 or (useClass and 1 or 0.3))
            customSwatch:SetMouseClickEnabled(not off)
            classSwatch:SetMouseClickEnabled(not off)
        end
        customSwatch, updateCustom = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5,
            function() local c = DBVal("targetArrowColor") or defaults.targetArrowColor; return c.r, c.g, c.b end,
            function(r, g, b)
                DB().targetArrowColor = { r = r, g = g, b = b }
                DB().targetArrowClassColor = false
                for _, plate in pairs(plates) do plate:ApplyTarget() end
                UpdatePreview(); refreshArrowSwatches()
            end, nil, 20)
        PP.Point(customSwatch, "RIGHT", rightRgn._lastInline or rightRgn._control, "LEFT", -8, 0)
        local origCustomClick = customSwatch:GetScript("OnClick")
        customSwatch:SetScript("OnClick", function(self, ...)
            if arrowOff() then return end
            if DBVal("targetArrowClassColor") == true then
                DB().targetArrowClassColor = false
                for _, plate in pairs(plates) do plate:ApplyTarget() end
                UpdatePreview(); refreshArrowSwatches()
                return
            end
            if origCustomClick then origCustomClick(self, ...) end
        end)
        customSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(customSwatch, "Custom Color") end)
        customSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        classSwatch, updateClass = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5,
            function() local _, ct = UnitClass("player"); local cc = ct and C_ClassColor and C_ClassColor.GetClassColor(ct); if cc then return cc.r, cc.g, cc.b end return 1, 1, 1 end,
            function() end, nil, 20)
        PP.Point(classSwatch, "RIGHT", customSwatch, "LEFT", -8, 0)
        rightRgn._lastInline = classSwatch
        classSwatch:SetScript("OnClick", function()
            if arrowOff() then return end
            DB().targetArrowClassColor = true
            for _, plate in pairs(plates) do plate:ApplyTarget() end
            UpdatePreview(); refreshArrowSwatches()
        end)
        classSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(classSwatch, "Class Color") end)
        classSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        EllesmereUI.RegisterWidgetRefresh(refreshArrowSwatches)
        refreshArrowSwatches()
    end

    -- Target Color ---- Target Texture
    local isTargetColorDisabled = function()
        local db = DB()
        if db and db.targetColorEnabled ~= nil then return not db.targetColorEnabled end
        return not defaults.targetColorEnabled
    end
    local isTargetTextureNone = function()
        return (DBVal("targetOverlayTexture") or defaults.targetOverlayTexture) == "none"
    end
    -- No Tint: the target texture pattern becomes the bar's own fill texture (SetStatusBarTexture) instead of a tinted overlay, so the color swatch/opacity below stop applying.
    local isTargetNoTint = function()
        local v = DBVal("targetOverlayNoTint")
        if v == nil then return defaults.targetOverlayNoTint end
        return v
    end

    -- The Target Texture and Focus Texture dropdowns list the special stripe overlays first, then the full bar texture set (EUI + SharedMedia) shared with the main Bar Texture dropdown; stripe keys resolve to nameplate Media, bar keys resolve through the health-bar lookup at render time (ns.ResolveOverlayTexPath).
    local ovtValues, ovtOrder = {}, {}
    do
        local STRIPE_ORDER = { "striped-v2", "striped-wide-v2", "stripes-medium", "stripes-small-close", "stripes-small-spread", "striped-tiny" }
        local STRIPE_NAMES = {
            ["striped-v2"] = "Stripes", ["striped-wide-v2"] = "Wide Stripes",
            ["stripes-medium"] = "Medium Stripes", ["stripes-small-close"] = "Small Dense Stripes",
            ["stripes-small-spread"] = "Small Spread Stripes", ["striped-tiny"] = "Tiny Stripes",
        }
        for _, k in ipairs(STRIPE_ORDER) do ovtValues[k] = STRIPE_NAMES[k]; ovtOrder[#ovtOrder + 1] = k end
        ovtOrder[#ovtOrder + 1] = "---"
        for _, k in ipairs(hbtOrder) do
            ovtOrder[#ovtOrder + 1] = k
            if k ~= "---" then ovtValues[k] = hbtValues[k] end
        end
        ovtValues._menuOpts = {
            itemHeight = 28,
            background = function(key)
                if not key or key == "none" or key == "---" then return nil end
                if ns.OVERLAY_STRIPE_KEYS and ns.OVERLAY_STRIPE_KEYS[key] then
                    return "Interface\\AddOns\\EllesmereUINameplates\\Media\\" .. key .. ".png"
                end
                return ns.healthBarTextures and ns.healthBarTextures[key]
            end,
        }
    end

    local targetColorRow
    SearchWords("Target Color", "TARGET", "Enable Target Color")
    targetColorRow, h = W:DualRow(parent, y,
        { type="toggle", text="Target Color",
          getValue=function()
            local db = DB()
            if db and db.targetColorEnabled ~= nil then return db.targetColorEnabled end
            return defaults.targetColorEnabled
          end,
          setValue=function(v)
            DB().targetColorEnabled = v
            RefreshAllPlates()
            UpdatePreview()
            EllesmereUI:RefreshPage()
          end },
        { type="dropdown", text="Target Texture",
          values=ovtValues,
          getValue=function() return DBVal("targetOverlayTexture") or defaults.targetOverlayTexture end,
          setValue=function(v)
            DB().targetOverlayTexture = v
            RefreshAllPlates()
            UpdatePreview()
            EllesmereUI:RefreshPage()
          end,
          order=ovtOrder });  y = y - h

    -- Inline Target Color swatch
    if not EllesmereUI._prebuilding then
        local leftRgn = targetColorRow._leftRegion
        local targetColorGet = function() return DBColor("target") end
        local targetColorSet = function(r, g, b)
            DB().target = { r = r, g = g, b = b }
            RefreshAllPlates()
            UpdatePreview()
        end
        local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, targetColorGet, targetColorSet, nil, 20)
        PP.Point(swatch, "RIGHT", leftRgn._control, "LEFT", -12, 0)
        EllesmereUI.RegisterWidgetRefresh(function()
            local off = isTargetColorDisabled()
            swatch:SetAlpha(off and 0.15 or 1)
            swatch:EnableMouse(not off)
            updateSwatch()
        end)
        local off = isTargetColorDisabled()
        swatch:SetAlpha(off and 0.15 or 1)
        swatch:EnableMouse(not off)
    end

    -- Inline Target Texture cog (Opacity + No Tint), beside the control; the swatch sits left of it
    if not EllesmereUI._prebuilding then
        local rightRgn = targetColorRow._rightRegion
        EllesmereUI.BuildInlineCog(rightRgn, {
            disabled = isTargetTextureNone,
            disabledTooltip = "a Target Texture",
            title = "Target Texture",
            rows = {
                { type="slider", label="Opacity", min=5, max=100, step=1,
                  get=function() return math.floor(((DBVal("targetOverlayAlpha") or defaults.targetOverlayAlpha) * 100) + 0.5) end,
                  set=function(v)
                    DB().targetOverlayAlpha = v / 100
                    RefreshAllPlates()
                    UpdatePreview()
                  end },
                { type="toggle", label="Full alpha on empty part of bar",
                  get=function()
                    local v = DBVal("targetOverlayFullBgAlpha")
                    if v == nil then return defaults.targetOverlayFullBgAlpha end
                    return v
                  end,
                  set=function(v)
                    DB().targetOverlayFullBgAlpha = v
                    RefreshAllPlates()
                    UpdatePreview()
                  end },
                { type="toggle", label="Don't tint (keep bar's own color)",
                  tooltip="Tints the pattern with the bar's current color instead of the custom overlay color.",
                  get=isTargetNoTint,
                  set=function(v)
                    DB().targetOverlayNoTint = v
                    RefreshAllTextures()
                    UpdatePreview()
                    EllesmereUI:RefreshPage()  -- the row's colour swatch greys with it
                  end },
            },
        })
    end

    -- Inline Target Texture color swatch
    if not EllesmereUI._prebuilding then
        local rightRgn = targetColorRow._rightRegion
        local targetTexColorGet = function()
            local c = (DB() and DB().targetOverlayColor) or defaults.targetOverlayColor
            return c.r, c.g, c.b
        end
        local targetTexColorSet = function(r, g, b)
            DB().targetOverlayColor = { r = r, g = g, b = b }
            RefreshAllPlates()
            UpdatePreview()
        end
        local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5, targetTexColorGet, targetTexColorSet, nil, 20)
        PP.Point(swatch, "RIGHT", rightRgn._lastInline or rightRgn._control, "LEFT", -8, 0)
        rightRgn._lastInline = swatch
        EllesmereUI.RegisterWidgetRefresh(function()
            local off = isTargetTextureNone() or isTargetNoTint()
            swatch:SetAlpha(off and 0.15 or 1)
            swatch:EnableMouse(not off)
            updateSwatch()
        end)
        local off = isTargetTextureNone() or isTargetNoTint()
        swatch:SetAlpha(off and 0.15 or 1)
        swatch:EnableMouse(not off)
    end

    -- Scale Target Nameplate ---- Non-Target Opacity
    local tfScaleRow
    tfScaleRow, h = W:DualRow(parent, y,
        { type="slider", text="Scale Target Nameplate",
          trackWidth=110,
          min=50, max=200, step=5,
          getValue=function() return DBVal("targetScale") or defaults.targetScale end,
          setValue=function(v)
            DB().targetScale = v
            for _, plate in pairs(plates) do
                plate:ApplyScale()
            end
            UpdatePreview()
          end,
          tooltip="Scales your current target's nameplate. 100% = no change." },
        { type="slider", text="Non-Target Opacity",
          tooltip="Fades enemy nameplates that are not your current target or focus while you have a target. 100 = no fading.",
          min=0, max=100, step=1,
          getValue=function() return DBVal("nonTargetAlpha") or 100 end,
          setValue=function(v)
            DB().nonTargetAlpha = v
            if ns.NT_RefreshSetting then ns.NT_RefreshSetting() end
            EllesmereUI:RefreshPage()  -- update the cog disabled state
          end });  y = y - h
    -- "(Percent)" suffix on the target scale slider
    if not EllesmereUI._prebuilding then
        local leftFrame = tfScaleRow._leftRegion
        if leftFrame then
            local suffixFS = leftFrame:CreateFontString(nil, "OVERLAY")
            suffixFS:SetFont(EllesmereUI.EXPRESSWAY, 11, GetNPOptOutline())
            suffixFS:SetTextColor(1, 1, 1, 0.35)
            local sliderLabel = SliderLabel(leftFrame, "Scale Target Nameplate")
            if sliderLabel then
                suffixFS:SetPoint("LEFT", sliderLabel, "RIGHT", 5, -1)
            else
                suffixFS:SetPoint("LEFT", leftFrame, "LEFT", 180, -1)
            end
            suffixFS:SetText(EllesmereUI.L("(Percent)"))
        end
    end
    -- Inline cog on Non-Target Opacity: the focus exemption, which Out of Combat
    -- Opacity (Extras) reads too, and the casting one.
    if not EllesmereUI._prebuilding then
        local function ntOff()
            return (DBVal("nonTargetAlpha") or 100) >= 100 and (DBVal("outOfCombatAlpha") or 100) >= 100
        end
        local rgn = tfScaleRow._rightRegion
        EllesmereUI.BuildInlineCog(rgn, {
            disabled = ntOff,
            disabledTooltip = "This option requires Non-Target Opacity or Out of Combat Opacity to be below 100",
            title = "Non-Target Opacity",
            rows = {
                { type="toggle", label="Keep Focus Full Opacity",
                  tooltip="Your focus target's nameplate never fades with Non-Target Opacity or Out of Combat Opacity.",
                  get=function() return DBVal("nonTargetKeepFocus") ~= false end,
                  set=function(v)
                    DB().nonTargetKeepFocus = v
                    if ns.NT_RefreshSetting then ns.NT_RefreshSetting() end
                  end },
                -- One dropdown over nonTargetCastFull + nonTargetCastImportantOnly.
                { type="dropdown", label="Full Opacity While Casting",
                  values={ off = "Off", all = "All Casts", important = "Important Casts" },
                  order={ "off", "all", "important" },
                  tooltip="A casting enemy's nameplate skips Non-Target Opacity while the cast lasts.",
                  disabled=function() return (DBVal("nonTargetAlpha") or 100) >= 100 end,
                  disabledTooltip="Non-Target Opacity below 100",
                  get=function()
                    if DBVal("nonTargetCastFull") ~= true then return "off" end
                    return DBVal("nonTargetCastImportantOnly") == true and "important" or "all"
                  end,
                  set=function(v)
                    DB().nonTargetCastFull = v ~= "off"
                    DB().nonTargetCastImportantOnly = v == "important"
                    if ns.NT_RefreshSetting then ns.NT_RefreshSetting() end
                  end },
            },
        })
    end

    -- Distance to Target Text ---- Show Hash Line on Target
    local tfRangeOff = function() return DBVal("rangeTextEnabled") ~= true end
    local function hashLineOff() return not (DBVal("hashLineEnabled")) end
    local tfRangeRow
    local RANGE_TIP = "Shows the approximate distance to your current target on its nameplate as a range bracket, e.g. 15+ when the target is 15-20 yards away."
    SearchWords("Distance to Target Text", "TARGET", RANGE_TIP, "Distance to Target Text (Range)")
    SearchWords("Show Hash Line on Target", "TARGET", "Show Hash Line on Target at Percent",
        "Hash Line Location", "Hash Line Color")
    tfRangeRow, h = W:DualRow(parent, y,
        { type="toggle", text="Distance to Target Text",
          tooltip=RANGE_TIP,
          getValue=function() return DBVal("rangeTextEnabled") == true end,
          setValue=function(v)
            DB().rangeTextEnabled = v
            if ns.RangeText_Apply then ns.RangeText_Apply() end
            UpdatePreview()
            EllesmereUI:RefreshPage()
          end },
        { type="toggle", text="Show Hash Line on Target",
          getValue=function() return DBVal("hashLineEnabled") or false end,
          setValue=function(v)
            DB().hashLineEnabled = v
            RefreshAllPlates()
            UpdatePreview()
            -- the Hash Line Location row below is built only while this is on
            EllesmereUI:RefreshPage(true)
          end });  y = y - h
    -- "(Range)" suffix in smaller, dimmer text next to the toggle's label
    if not EllesmereUI._prebuilding then
        local leftFrame = tfRangeRow._leftRegion
        if leftFrame then
            local suffixFS = leftFrame:CreateFontString(nil, "OVERLAY")
            suffixFS:SetFont(EllesmereUI.EXPRESSWAY, 11, GetNPOptOutline())
            suffixFS:SetTextColor(1, 1, 1, 0.35)
            local rowLabel = SliderLabel(leftFrame, "Distance to Target Text")
            if rowLabel then
                suffixFS:SetPoint("LEFT", rowLabel, "RIGHT", 5, -1)
            else
                suffixFS:SetPoint("LEFT", leftFrame, "LEFT", 180, -1)
            end
            suffixFS:SetText(EllesmereUI.L("(Range)"))
        end
    end
    -- Inline color swatch for the hash line's color
    if not EllesmereUI._prebuilding then
        local hashColorGet = function()
            local c = (DB() and DB().hashLineColor) or defaults.hashLineColor
            return c.r, c.g, c.b
        end
        local hashColorSet = function(r, g, b)
            DB().hashLineColor = { r = r, g = g, b = b }
            RefreshAllPlates()
            UpdatePreview()
        end
        local rightRgn = tfRangeRow._rightRegion
        local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5, hashColorGet, hashColorSet, nil, 20)
        PP.Point(swatch, "RIGHT", rightRgn._control, "LEFT", -12, 0)
        -- Gray out swatch when hash line is off
        EllesmereUI.RegisterWidgetRefresh(function()
            local off = hashLineOff()
            swatch:SetAlpha(off and 0.15 or 1)
            swatch:EnableMouse(not off)
            updateSwatch()
        end)
        swatch:SetAlpha(hashLineOff() and 0.15 or 1)
        swatch:EnableMouse(not hashLineOff())
    end
    -- RESIZE cog: text size + X/Y offsets (mirrors the raid-marker cog), beside the toggle
    if not EllesmereUI._prebuilding then
        local rgn = tfRangeRow._leftRegion
        EllesmereUI.BuildInlineCog(rgn, {
            disabled = tfRangeOff,
            disabledTooltip = "Distance to Target Text",
            title = "Distance Text",
            rows = {
                { type="slider", label="Text Size", min=6, max=32, step=1,
                  get=function() return DBVal("rangeTextSize") or defaults.rangeTextSize end,
                  set=function(v)
                    DB().rangeTextSize = v
                    if ns.RangeText_Refresh then ns.RangeText_Refresh() end
                    UpdatePreview()
                  end },
                { type="slider", label="Offset X", min=-200, max=200, step=1,
                  get=function() return DBVal("rangeTextOffsetX") or 0 end,
                  set=function(v)
                    DB().rangeTextOffsetX = v
                    if ns.RangeText_Refresh then ns.RangeText_Refresh() end
                    UpdatePreview()
                  end },
                { type="slider", label="Offset Y", min=-200, max=200, step=1,
                  get=function() return DBVal("rangeTextOffsetY") or 0 end,
                  set=function(v)
                    DB().rangeTextOffsetY = v
                    if ns.RangeText_Refresh then ns.RangeText_Refresh() end
                    UpdatePreview()
                  end },
            },
        })
    end
    -- Inline color swatch (default light orange), left of the cog
    if not EllesmereUI._prebuilding then
        local rgn = tfRangeRow._leftRegion
        local rangeColorGet = function()
            local c = (DB() and DB().rangeTextColor) or defaults.rangeTextColor
            return c.r, c.g, c.b
        end
        local rangeColorSet = function(r, g, b)
            DB().rangeTextColor = { r = r, g = g, b = b }
            if ns.RangeText_Refresh then ns.RangeText_Refresh() end
            UpdatePreview()
        end
        local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, rangeColorGet, rangeColorSet, nil, 20)
        PP.Point(swatch, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = swatch
        EllesmereUI.RegisterWidgetRefresh(function()
            local off = tfRangeOff()
            swatch:SetAlpha(off and 0.15 or 1)
            swatch:EnableMouse(not off)
            updateSwatch()
        end)
        swatch:SetAlpha(tfRangeOff() and 0.15 or 1)
        swatch:EnableMouse(not tfRangeOff())
    end

    -- Hash Line Location: a row only while Show Hash Line on Target is on (its
    -- toggle builds the page again)
    if not hashLineOff() then
        local hashLocRow
        hashLocRow, h = W:DualRow(parent, y,
            { type="slider", text="Hash Line Location",
              min=0, max=100, step=1,
              getValue=function() return DBVal("hashLinePercent") or defaults.hashLinePercent end,
              setValue=function(v)
                DB().hashLinePercent = v
                RefreshAllPlates()
                UpdatePreview()
              end },
            EllesmereUI.BlankRowCfg());  y = y - h
        -- "(Percent)" suffix in smaller, dimmer text next to the slider label
        if not EllesmereUI._prebuilding then
            local leftFrame = hashLocRow._leftRegion
            if leftFrame then
                local suffixFS = leftFrame:CreateFontString(nil, "OVERLAY")
                suffixFS:SetFont(EllesmereUI.EXPRESSWAY, 11, GetNPOptOutline())
                suffixFS:SetTextColor(1, 1, 1, 0.35)
                local sliderLabel = SliderLabel(leftFrame, "Hash Line Location")
                if sliderLabel then
                    suffixFS:SetPoint("LEFT", sliderLabel, "RIGHT", 5, -1)
                else
                    suffixFS:SetPoint("LEFT", leftFrame, "LEFT", 180, -1)
                end
                suffixFS:SetText(EllesmereUI.L("(Percent)"))
            end
        end
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h

    -----------------------------------------------------------------------
    --  FOCUS
    -----------------------------------------------------------------------
    SearchWords("FOCUS", nil, "TARGET, FOCUS & HOVER EFFECTS", "TARGET AND FOCUS EFFECTS")
    focusHdr, h = W:SectionHeader(parent, "FOCUS", y);  y = y - h

    -- Focus Color ---- Focus Texture
    local isFocusColorDisabled = function()
        local db = DB()
        if db and db.focusColorEnabled ~= nil then return not db.focusColorEnabled end
        return not defaults.focusColorEnabled
    end
    local isFocusTextureNone = function()
        return (DBVal("focusOverlayTexture") or defaults.focusOverlayTexture) == "none"
    end
    local isFocusNoTint = function()
        local v = DBVal("focusOverlayNoTint")
        if v == nil then return defaults.focusOverlayNoTint end
        return v
    end

    local focusColorRow
    SearchWords("Focus Color", "FOCUS", "Enable Focus Color")
    focusColorRow, h = W:DualRow(parent, y,
        { type="toggle", text="Focus Color",
          getValue=function()
            local db = DB()
            if db and db.focusColorEnabled ~= nil then return db.focusColorEnabled end
            return defaults.focusColorEnabled
          end,
          setValue=function(v)
            DB().focusColorEnabled = v
            RefreshAllPlates()
            UpdatePreview()
            EllesmereUI:RefreshPage()
          end },
        { type="dropdown", text="Focus Texture",
          values=ovtValues,
          getValue=function() return DBVal("focusOverlayTexture") or defaults.focusOverlayTexture end,
          setValue=function(v)
            DB().focusOverlayTexture = v
            RefreshAllPlates()
            UpdatePreview()
            EllesmereUI:RefreshPage()
          end,
          order=ovtOrder });  y = y - h

    -- Inline Focus Color swatch
    if not EllesmereUI._prebuilding then
        local leftRgn = focusColorRow._leftRegion
        local focusColorGet = function() return DBColor("focus") end
        local focusColorSet = function(r, g, b)
            DB().focus = { r = r, g = g, b = b }
            RefreshAllPlates()
            UpdatePreview()
        end
        local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, focusColorGet, focusColorSet, nil, 20)
        PP.Point(swatch, "RIGHT", leftRgn._control, "LEFT", -12, 0)
        EllesmereUI.RegisterWidgetRefresh(function()
            local off = isFocusColorDisabled()
            swatch:SetAlpha(off and 0.15 or 1)
            swatch:EnableMouse(not off)
            updateSwatch()
        end)
        local off = isFocusColorDisabled()
        swatch:SetAlpha(off and 0.15 or 1)
        swatch:EnableMouse(not off)
    end

    -- Inline Focus Texture cog (Opacity + No Tint), beside the control; the swatch sits left of it
    if not EllesmereUI._prebuilding then
        local rightRgn = focusColorRow._rightRegion
        EllesmereUI.BuildInlineCog(rightRgn, {
            disabled = isFocusTextureNone,
            disabledTooltip = "a Focus Texture",
            title = "Focus Texture",
            rows = {
                { type="slider", label="Opacity", min=5, max=100, step=1,
                  get=function() return math.floor(((DBVal("focusOverlayAlpha") or defaults.focusOverlayAlpha) * 100) + 0.5) end,
                  set=function(v)
                    DB().focusOverlayAlpha = v / 100
                    RefreshAllPlates()
                    UpdatePreview()
                  end },
                { type="toggle", label="Full alpha on empty part of bar",
                  get=function()
                    local v = DBVal("focusOverlayFullBgAlpha")
                    if v == nil then return defaults.focusOverlayFullBgAlpha end
                    return v
                  end,
                  set=function(v)
                    DB().focusOverlayFullBgAlpha = v
                    RefreshAllPlates()
                    UpdatePreview()
                  end },
                { type="toggle", label="Don't tint (keep bar's own color)",
                  tooltip="Tints the pattern with the bar's current color instead of the custom overlay color.",
                  get=isFocusNoTint,
                  set=function(v)
                    DB().focusOverlayNoTint = v
                    RefreshAllTextures()
                    RefreshAllPlates()
                    UpdatePreview()
                    EllesmereUI:RefreshPage()  -- the row's colour swatch greys with it
                  end },
            },
        })
    end

    -- Inline Focus Texture color swatch
    if not EllesmereUI._prebuilding then
        local rightRgn = focusColorRow._rightRegion
        local focusTexColorGet = function()
            local c = (DB() and DB().focusOverlayColor) or defaults.focusOverlayColor
            return c.r, c.g, c.b
        end
        local focusTexColorSet = function(r, g, b)
            DB().focusOverlayColor = { r = r, g = g, b = b }
            RefreshAllPlates()
            UpdatePreview()
        end
        local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5, focusTexColorGet, focusTexColorSet, nil, 20)
        PP.Point(swatch, "RIGHT", rightRgn._lastInline or rightRgn._control, "LEFT", -8, 0)
        rightRgn._lastInline = swatch
        EllesmereUI.RegisterWidgetRefresh(function()
            local off = isFocusTextureNone() or isFocusNoTint()
            swatch:SetAlpha(off and 0.15 or 1)
            swatch:EnableMouse(not off)
            updateSwatch()
        end)
        local off = isFocusTextureNone() or isFocusNoTint()
        swatch:SetAlpha(off and 0.15 or 1)
        swatch:EnableMouse(not off)
    end

    -- Focus Cast Height ---- Focus Letter (one dropdown over focusLetterEnabled and
    -- focusLetterAnchor: None, or where the letter sits; None keeps the saved anchor)
    local focusLetterOff = function()
        return DBVal("focusLetterEnabled") ~= true
    end
    local focusLetterVals, focusLetterOrder = { none = "None" }, { "none" }
    for i = 1, #FOCUS_LETTER_ANCHOR_ORDER do
        local k = FOCUS_LETTER_ANCHOR_ORDER[i]
        focusLetterVals[k] = FOCUS_LETTER_ANCHORS[k]
        focusLetterOrder[#focusLetterOrder + 1] = k
    end
    local tfFocusRow
    tfFocusRow, h = W:DualRow(parent, y,
        { type="slider", text="Focus Cast Height",
          trackWidth=110,
          min=100, max=200, step=5,
          getValue=function() return DBVal("focusCastHeight") or defaults.focusCastHeight end,
          setValue=function(v)
            DB().focusCastHeight = v
            ns.RefreshAllSettings()
            UpdatePreview()
          end,
          tooltip="Increases the cast bar height on your focus target's nameplate. 100% = normal height." },
        { type="dropdown", text="Focus Letter",
          tooltip="Draws a white letter F on your current focus target's nameplate.",
          values=focusLetterVals, order=focusLetterOrder,
          getValue=function()
            local anchor = GetFocusLetterAnchor()
            return DBVal("focusLetterEnabled") == true and anchor or "none"
          end,
          setValue=function(v)
            local db = DB()
            if v == "none" then
                db.focusLetterEnabled = false
            else
                db.focusLetterEnabled = true
                db.focusLetterAnchor = v
            end
            RefreshAllPlates()
            UpdatePreview()
            EllesmereUI:RefreshPage()
          end });  y = y - h
    -- "(Percent)" suffix on Focus Cast Height
    if not EllesmereUI._prebuilding then
        local leftFrame = tfFocusRow._leftRegion
        if leftFrame then
            local suffixFS = leftFrame:CreateFontString(nil, "OVERLAY")
            suffixFS:SetFont(EllesmereUI.EXPRESSWAY, 11, GetNPOptOutline())
            suffixFS:SetTextColor(1, 1, 1, 0.35)
            local sliderLabel = SliderLabel(leftFrame, "Focus Cast Height")
            if sliderLabel then
                suffixFS:SetPoint("LEFT", sliderLabel, "RIGHT", 5, -1)
            else
                suffixFS:SetPoint("LEFT", leftFrame, "LEFT", 180, -1)
            end
            suffixFS:SetText(EllesmereUI.L("(Percent)"))
        end
    end

    if not EllesmereUI._prebuilding then
        local rgn = tfFocusRow._rightRegion
        EllesmereUI.BuildInlineCog(rgn, {
            disabled = focusLetterOff,
            disabledTooltip = "Focus Letter",
            title = "Focus Letter",
            rows = {
                { type="slider", label="Size", min=6, max=40, step=1,
                  get=function() return DBVal("focusLetterSize") or defaults.focusLetterSize end,
                  set=function(v)
                    DB().focusLetterSize = v
                    RefreshAllPlates()
                    UpdatePreview()
                  end },
                { type="slider", label="X", min=-100, max=100, step=1,
                  get=function() return DBVal("focusLetterX") or defaults.focusLetterX end,
                  set=function(v)
                    DB().focusLetterX = v
                    RefreshAllPlates()
                    UpdatePreview()
                  end },
                { type="slider", label="Y", min=-100, max=100, step=1,
                  get=function() return DBVal("focusLetterY") or defaults.focusLetterY end,
                  set=function(v)
                    DB().focusLetterY = v
                    RefreshAllPlates()
                    UpdatePreview()
                  end },
            },
        })
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h

    -----------------------------------------------------------------------
    --  HOVER
    -----------------------------------------------------------------------
    SearchWords("HOVER", nil, "TARGET, FOCUS & HOVER EFFECTS")
    hoverHdr, h = W:SectionHeader(parent, "HOVER", y);  y = y - h

    -- Hover Texture ---- Hover Effect: the mouseover highlight overlay and the effects drawn with it.
    local hoverOverlayValues, hoverOverlayOrder = {}, {}
    do
        local STRIPE_ORDER = { "striped-v2", "striped-wide-v2", "stripes-medium", "stripes-small-close", "stripes-small-spread", "striped-tiny" }
        local STRIPE_NAMES = {
            ["striped-v2"] = "Stripes", ["striped-wide-v2"] = "Wide Stripes",
            ["stripes-medium"] = "Medium Stripes", ["stripes-small-close"] = "Small Dense Stripes",
            ["stripes-small-spread"] = "Small Spread Stripes", ["striped-tiny"] = "Tiny Stripes",
        }
        hoverOverlayValues.none = "None"
        hoverOverlayOrder[#hoverOverlayOrder + 1] = "none"
        hoverOverlayOrder[#hoverOverlayOrder + 1] = "---"
        for _, k in ipairs(STRIPE_ORDER) do hoverOverlayValues[k] = STRIPE_NAMES[k]; hoverOverlayOrder[#hoverOverlayOrder + 1] = k end
        hoverOverlayOrder[#hoverOverlayOrder + 1] = "---"
        for _, k in ipairs(hbtOrder) do
            -- "none" is already prepended above; skip the copy from hbtOrder (which starts with "none") so it shows only once.
            if k ~= "none" then
                hoverOverlayOrder[#hoverOverlayOrder + 1] = k
                if k ~= "---" then hoverOverlayValues[k] = hbtValues[k] end
            end
        end
        hoverOverlayValues._menuOpts = {
            itemHeight = 28,
            background = function(key)
                if not key or key == "none" or key == "---" then return nil end
                if ns.OVERLAY_STRIPE_KEYS and ns.OVERLAY_STRIPE_KEYS[key] then
                    return "Interface\\AddOns\\EllesmereUINameplates\\Media\\" .. key .. ".png"
                end
                return ns.healthBarTextures and ns.healthBarTextures[key]
            end,
        }
    end
    do
        hoverRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Hover Texture",
              tooltip="Uses the Hover Effect color and opacity. Set to None for the flat hover highlight.",
              values=hoverOverlayValues, order=hoverOverlayOrder,
              getValue=function() return DBVal("hoverOverlayTexture") or defaults.hoverOverlayTexture end,
              setValue=function(v)
                DB().hoverOverlayTexture = v
                ns.RefreshHoverEffect()
                UpdatePreview()
                EllesmereUI:RefreshPage()
              end },
            { type="dropdown", text="Hover Effect",
              values={ __placeholder = "..." }, order={ "__placeholder" },
              getValue=ChecklistReads("hoverGlowEllesmereUI", "hoverGlowBorderColor", "hoverGlowHighlight", "hoverGlowBorderSize"),
              setValue=function() end });  y = y - h
        if not EllesmereUI._prebuilding then
        -- Hover Effect: the Target Effect channels on mouseover. Highlight is
        -- the only default-on channel and rides the hoverColor/hoverAlpha
        -- keys; the other channels are opt-in.
        local rightRgn = hoverRow._rightRegion
        if rightRgn._control then rightRgn._control:Hide() end
        local refreshHoverBorderSwatch
        local refreshHoverGlowSwatch
        local refreshHoverCog
        local hoverItems = {
            { key = "ellesmereui", label = "EUI Glow" },
            { key = "borderColor", label = "Border Color" },
            { key = "highlight",   label = "Highlight" },
            { key = "borderSize",  label = "Border Size",
              tooltip = "Change Size in the Cogwheel" },
        }
        local hvDD, hvDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
            rightRgn, 170, rightRgn:GetFrameLevel() + 2,
            hoverItems,
            function(k)
                if k == "ellesmereui" then return ns.GetHoverGlowEllesmereUI() end
                if k == "borderColor" then return ns.GetHoverGlowBorderColor() end
                if k == "highlight"   then return ns.GetHoverGlowHighlight() end
                if k == "borderSize"  then return ns.GetHoverGlowBorderSize() end
                return false
            end,
            function(k, v)
                if k == "ellesmereui" then DB().hoverGlowEllesmereUI = v
                elseif k == "borderColor" then DB().hoverGlowBorderColor = v
                elseif k == "highlight" then DB().hoverGlowHighlight = v
                elseif k == "borderSize" then
                    DB().hoverGlowBorderSize = v
                    -- First-enable snapshot: seed the cog slider with the user's
                    -- CURRENT border size, so enabling changes nothing until they
                    -- move it (one-time, never re-snapshots later).
                    if v and DB().hoverBorderSizeValue == nil then
                        if ns.IsCustomBorderEnabled() then
                            DB().hoverBorderSizeValue = DBVal("customBorderSize") or defaults.customBorderSize
                        else
                            DB().hoverBorderSizeValue = DBVal("borderSize") or defaults.borderSize
                        end
                    end
                end
                ns.RefreshHoverEffect()
                UpdatePreview()
                if refreshHoverBorderSwatch then refreshHoverBorderSwatch() end
                if refreshHoverGlowSwatch then refreshHoverGlowSwatch() end
                if refreshHoverCog then refreshHoverCog() end
            end)
        PP.Point(hvDD, "RIGHT", rightRgn, "RIGHT", -20, 0)
        rightRgn._control = hvDD
        rightRgn._lastInline = nil
        EllesmereUI.RegisterWidgetRefresh(hvDDRefresh)

        -- Inline cog "More Effects": Highlight color/opacity (the legacy
        -- hoverColor/hoverAlpha keys) + Glow Opacity + Border Size.
        do
            local function hoverCogOff()
                return not (ns.GetHoverGlowHighlight() or ns.GetHoverGlowEllesmereUI()
                    or ns.GetHoverGlowBorderSize())
            end
            local hoverCogBtn = EllesmereUI.BuildInlineCog(rightRgn, {
                disabled = hoverCogOff,
                disabledTooltip = "a Hover Effect",
                title = "More Effects",
                rows = {
                    { type="colorpicker", label="Highlight Color", hasAlpha=false,
                      get=function()
                        local c = (DB() and DB().hoverColor) or defaults.hoverColor
                        return c.r, c.g, c.b
                      end,
                      set=function(r, g, b)
                        DB().hoverColor = { r = r, g = g, b = b }
                        ns.RefreshHoverEffect()
                        UpdatePreview()
                      end },
                    { type="slider", label="Highlight Opacity", min=0, max=100, step=1,
                      get=function()
                        return math.floor(((DBVal("hoverAlpha") or defaults.hoverAlpha) * 100) + 0.5)
                      end,
                      set=function(v)
                        DB().hoverAlpha = v / 100
                        ns.RefreshHoverEffect()
                        UpdatePreview()
                      end },
                    { type="slider", label="Glow Opacity", min=0, max=100, step=1,
                      get=function() return math.floor((ns.GetHoverGlowAlpha() * 100) + 0.5) end,
                      set=function(v)
                        DB().hoverGlowAlpha = v / 100
                        ns.RefreshHoverEffect()
                        UpdatePreview()
                      end },
                    { type="slider", label="Border Size", min=0, max=4, step=1,
                      get=function()
                        local v = DBVal("hoverBorderSizeValue")
                        if v ~= nil then return v end
                        if ns.IsCustomBorderEnabled() then
                            return DBVal("customBorderSize") or defaults.customBorderSize
                        end
                        return DBVal("borderSize") or defaults.borderSize
                      end,
                      set=function(v)
                        DB().hoverBorderSizeValue = v
                        ns.RefreshHoverEffect()
                        UpdatePreview()
                      end,
                      disabled=function() return not ns.GetHoverGlowBorderSize() end,
                      disabledTooltip="Border Size Hover Effect" },
                },
            })
            refreshHoverCog = hoverCogBtn and hoverCogBtn._euiCogState
        end

        -- Inline Border Color swatch: dimmed unless Border Color is checked.
        local hvBSwatch, hvUpdateBSwatch = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5,
            function() local c = ns.GetHoverBorderColor(); return c.r, c.g, c.b end,
            function(r, g, b)
                DB().hoverBorderColor = { r = r, g = g, b = b }
                ns.RefreshHoverEffect()
                UpdatePreview()
            end, nil, 20)
        PP.Point(hvBSwatch, "RIGHT", rightRgn._lastInline or rightRgn._control, "LEFT", -8, 0)
        rightRgn._lastInline = hvBSwatch
        hvBSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(hvBSwatch, "Border Color") end)
        hvBSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        refreshHoverBorderSwatch = function()
            local off = not ns.GetHoverGlowBorderColor()
            hvBSwatch:SetAlpha(off and 0.15 or 1)
            hvBSwatch:EnableMouse(not off)
            hvUpdateBSwatch()
        end
        EllesmereUI.RegisterWidgetRefresh(refreshHoverBorderSwatch)
        refreshHoverBorderSwatch()

        -- Inline Glow Color swatch: dimmed unless EUI Glow is checked.
        local hvGSwatch, hvUpdateGSwatch = EllesmereUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5,
            function() local c = ns.GetHoverGlowColor(); return c.r, c.g, c.b end,
            function(r, g, b)
                DB().hoverGlowColor = { r = r, g = g, b = b }
                ns.RefreshHoverEffect()
                UpdatePreview()
            end, nil, 20)
        PP.Point(hvGSwatch, "RIGHT", rightRgn._lastInline or rightRgn._control, "LEFT", -8, 0)
        rightRgn._lastInline = hvGSwatch
        hvGSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(hvGSwatch, "Glow Color") end)
        hvGSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        refreshHoverGlowSwatch = function()
            local off = not ns.GetHoverGlowEllesmereUI()
            hvGSwatch:SetAlpha(off and 0.15 or 1)
            hvGSwatch:EnableMouse(not off)
            hvUpdateGSwatch()
        end
        EllesmereUI.RegisterWidgetRefresh(refreshHoverGlowSwatch)
        refreshHoverGlowSwatch()

        -- Inline Hover Texture cog (Full alpha on empty part of bar), left of the dropdown; disabled while set to None.
        local leftRgn = hoverRow._leftRegion
        local isHoverTextureNone = function()
            return (DBVal("hoverOverlayTexture") or defaults.hoverOverlayTexture) == "none"
        end
        EllesmereUI.BuildInlineCog(leftRgn, {
            disabled = isHoverTextureNone,
            disabledTooltip = "a Hover Texture",
            title = "Hover Texture",
            rows = {
                { type="toggle", label="Full alpha on empty part of bar",
                  get=function()
                    local v = DBVal("hoverOverlayFullBgAlpha")
                    if v == nil then return defaults.hoverOverlayFullBgAlpha end
                    return v
                  end,
                  set=function(v)
                    DB().hoverOverlayFullBgAlpha = v
                    ns.RefreshHoverEffect()
                    UpdatePreview()
                  end },
            },
        })
        end -- not EllesmereUI._prebuilding
    end

    -- The search pre-build indexes rows only: the click navigation below sits on
    -- the live preview's frames, which a hidden build must leave alone.
    if EllesmereUI._prebuilding then return math.abs(y) end

    -----------------------------------------------------------------------
    --  CLICK NAVIGATION: a part the header preview draws for a setting of
    --  this page scrolls to that setting's row and highlights its half (the
    --  glow, the scroll and the overlay factory are the Nav kit's)
    -----------------------------------------------------------------------
    local P = Nav.Page(env.PAGE_TFH, {
        targetEffect  = { section = targetHdr, target = targetGlowRow,  slotSide = "left" },
        targetArrows  = { section = targetHdr, target = targetGlowRow,  slotSide = "right" },
        targetColor   = { section = targetHdr, target = targetColorRow, slotSide = "left" },
        targetTexture = { section = targetHdr, target = targetColorRow, slotSide = "right" },
        hashLine      = { section = targetHdr, target = tfRangeRow,     slotSide = "right" },
        rangeText     = { section = targetHdr, target = tfRangeRow,     slotSide = "left" },
        focusColor    = { section = focusHdr,  target = focusColorRow,  slotSide = "left" },
        focusTexture  = { section = focusHdr,  target = focusColorRow,  slotSide = "right" },
        focusLetter   = { section = focusHdr,  target = tfFocusRow,     slotSide = "right" },
        hoverTexture  = { section = hoverHdr,  target = hoverRow,       slotSide = "left" },
        hoverEffect   = { section = hoverHdr,  target = hoverRow,       slotSide = "right" },
    })
    -- The header built the preview again just now (SetContentHeader above), so
    -- its frames hold no overlay: the overlays of every state are made on them,
    -- and the preview's repaint shows the ones of its state whose part shows.
    local pv = env.optState.tfhPreview
    if pv and pv._glowFrame then
        -- Where parts overlap, the higher level takes the click: the effect's band
        -- round the bar, then the bar's colour, the Highlight wash and the texture
        -- in the order the plate draws them, then the thin hash line over them,
        -- and the texts and arrows on top.
        local base = pv._health:GetFrameLevel() + 15
        -- One entry per overlay: shown in its state while el (or el2) shows (el nil:
        -- always), or with edge while the state's effect draws at the bar's edge.
        local ovs = {}
        local function Add(btn, mode, el, el2, edge)
            ovs[#ovs + 1] = { btn = btn, mode = mode, el = el, el2 = el2, edge = edge }
            return btn
        end
        for _, m in ipairs({ "target", "hover" }) do
            -- the glow's band (its glow, border colour and border size)
            local band = Add(P.Overlay(pv._healthWrapper, m .. "Effect", false, base), m, nil, nil, true)
            band:ClearAllPoints()
            band:SetAllPoints(pv._glowFrame)
        end
        Add(P.Overlay(pv._health, "targetColor", false, base + 1), "target")
        Add(P.Overlay(pv._health, "focusColor", false, base + 1), "focus")
        Add(P.Overlay(pv._wash, "targetEffect", false, base + 2), "target", pv._wash)
        Add(P.Overlay(pv._health, "targetTexture", false, base + 3), "target", pv._texture)
        Add(P.Overlay(pv._health, "focusTexture", false, base + 3), "focus", pv._texture)
        -- the hovered plate's texture, or its flat wash while no texture is picked
        Add(P.Overlay(pv._health, "hoverTexture", false, base + 3), "hover", pv._texture, pv._wash)
        -- the hash line is 2 wide: its overlay reaches 3 past each side of it
        local hash = Add(P.Overlay(pv._hashLine, "hashLine", false, base + 4), "target", pv._hashLine)
        hash:ClearAllPoints()
        hash:SetPoint("TOP", pv._hashLine, "TOP", 0, 0)
        hash:SetPoint("BOTTOM", pv._hashLine, "BOTTOM", 0, 0)
        hash:SetWidth(8)
        Add(P.Overlay(pv._arrows.left, "targetArrows", false, base + 5), "target", pv._arrows.left)
        Add(P.Overlay(pv._arrows.right, "targetArrows", false, base + 5), "target", pv._arrows.right)
        Add(P.Overlay(pv._rangeText, "rangeText", true, base + 5), "target", pv._rangeText)
        Add(P.Overlay(pv._focusLetter, "focusLetter", true, base + 5), "focus", pv._focusLetter)
        -- Run by every repaint of the preview (a write, a pick of the state, the
        -- page or the panel shown again) and once now.
        pv._navSync = function()
            local mode = pv._mode
            for i = 1, #ovs do
                local o = ovs[i]
                local on = o.mode == mode
                if on then
                    if o.edge then
                        on = pv._fxEdge()
                    elseif o.el then
                        on = o.el:IsShown() or (o.el2 ~= nil and o.el2:IsShown())
                    end
                end
                o.btn:SetShown(on)
                -- a text's size and font follow the settings
                if on and o.btn._resizeToText then o.btn._resizeToText() end
            end
        end
        pv._navSync()
    end

    return math.abs(y)
end

-- Used by EUI_Nameplates_Options.lua
ns.NPO_BuildTargetFocusHoverPage = BuildTargetFocusHoverPage
