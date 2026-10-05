if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  ActionBars_Options\BarVisibilityLayout_Options.lua
--  Action Bars options: the Bar 10 caution and the Visibility and Layout
--  sections of the Bar Display page. Called by BuildSharedBarSettings; returns
--  y. Shared helpers come from ns._ABO_OptEnv, the per-build helpers from ctx.
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUIActionBars"]
if not ns then return end  -- module disabled: no options page

local function BuildBarVisibilityLayout(parent, y, ctx)
    local env = ns._ABO_OptEnv
    local ApplyVisibilityKey, BAR_LOOKUP, CopyVisibilitySettings, EAB = env.ApplyVisibilityKey, env.BAR_LOOKUP, env.CopyVisibilitySettings, env.EAB
    local EndCapsCtl, FirstBarButton, floor, GetVisibilityKey = env.EndCapsCtl, env.FirstBarButton, env.floor, env.GetVisibilityKey
    local GROUP_BAR_ORDER, IsDataBar, PP, SB = env.GROUP_BAR_ORDER, env.IsDataBar, env.PP, env.SB
    local SECTION_LAYOUT, SECTION_VISIBILITY, SelectedKey, SHORT_LABELS = env.SECTION_LAYOUT, env.SECTION_VISIBILITY, env.SelectedKey, env.SHORT_LABELS
    local BgDisabled, SDB, SGet, SSet = ctx.BgDisabled, ctx.SDB, ctx.SGet, ctx.SSet
    local SSetColor, SUpdatePreview, SUpdatePreviewAndResize, SVal = ctx.SSetColor, ctx.SUpdatePreview, ctx.SUpdatePreviewAndResize, ctx.SVal
    local visOnly = ctx.visOnly
    local W = ctx.W
    local _, h
    local row
    -- Declared out here, not in the `do` block that builds it: the Toggle Action Bar
    -- keybind lives past that block's end and anchors into this row's right slot.
    local visRow1

    -----------------------------------------------------------------------
    --  Bar 10 / Moonkin Form caution
    -----------------------------------------------------------------------
    -- Action page 10 (Bar 10's slots) is also the Druid Moonkin Form bonus bar, so editing either edits both. Shown for all classes; text self-qualifies.
    if SelectedKey() == "Bar10" then
        local PP = EllesmereUI.PanelPP
        local PAD = EllesmereUI.CONTENT_PAD
        local warnW = parent:GetWidth() - PAD * 2
        y = y - 5  -- 5px spacing above the caution
        local warnHost = CreateFrame("Frame", nil, parent)
        PP.Point(warnHost, "TOPLEFT", parent, "TOPLEFT", PAD, y)
        local warnFS = EllesmereUI.MakeFont(warnHost, 14, nil, 1, 0.82, 0)
        warnFS:SetWidth(warnW)
        warnFS:SetWordWrap(true)
        warnFS:SetJustifyH("CENTER")
        warnFS:SetPoint("TOPLEFT", warnHost, "TOPLEFT", 0, 0)
        warnFS:SetText(EllesmereUI.L("This Action Bar is also used as the Moonkin Form bar.\nChanging spells on a Druid for this bar will also change them on your Moonkin Form bar."))
        local warnH = math.ceil(warnFS:GetStringHeight()) + 4
        PP.Size(warnHost, warnW, warnH)
        y = y - (warnH + 12)
    end

    -----------------------------------------------------------------------
    --  VISIBILITY
    -----------------------------------------------------------------------
    _, h = W:SectionHeader(parent, SECTION_VISIBILITY, y);  y = y - h

    do
        local _visBlizzDis
        local _VIS_BLIZZ_TIP = "This option does not work with Blizzard Bars. Please use Blizzard Edit Mode."
        if IsDataBar() then
            _visBlizzDis = function() return EAB.db.profile.useBlizzardDataBars end
        end

        -- Pet Bar cannot express group modes: lock them with an explanation instead of offering silent no-ops.
        -- noOverrideMouseover: see the caps on the bar row above.
        local visCaps = { partyIncludesRaid = false, noOverrideMouseover = true }
        if SelectedKey() == "PetBar" then
            visCaps.noGroupModes = true
            visCaps.lockedTooltips = {
                in_raid  = "The Pet Bar cannot use group-based visibility.",
                in_party = "The Pet Bar cannot use group-based visibility.",
                solo     = "The Pet Bar cannot use group-based visibility.",
            }
        end
        -- Data bars evaluate in Lua (non-secure), so dragonriding items depend on the gliding
        -- edge event; secure bars' drivers re-evaluate natively and never lock.
        if IsDataBar() then visCaps.luaDragonriding = true end

        visRow1, h = EllesmereUI.BuildVisibilityRow(W, parent, y,
            { getStore = function()
                  local s = SB()
                  GetVisibilityKey(s)
                  return s
              end,
              legacyKey = "barVisibility",
              caps = visCaps,
              applyScalarFn = function(s, mode) ApplyVisibilityKey(s, mode) end,
              disabledFn = _visBlizzDis, disabledTooltip = _visBlizzDis and _VIS_BLIZZ_TIP or nil,
              rawTooltip = true,
              onChanged = function()
                  if EAB.ClearVisToggleOverride then EAB:ClearVisToggleOverride(SelectedKey()) end
                  if EAB.RebuildVisToggleBindings then EAB:RebuildVisToggleBindings() end
                  EAB:RefreshRuntimeVisibility()
                  EAB:RefreshMouseover()
                  EAB:ApplyCombatVisibility()
              end,
              -- Option axes recompile the secure driver through the same chain the
              -- old Visibility Options dropdown used. The gate refresh first: a lane
              -- click can be what just armed (or disarmed) the soft-target machinery,
              -- and the two calls below must see the current flags, not last click's.
              onOptionChanged = function()
                  EAB:_RefreshSoftTargetGate()
                  EAB:UpdateHousingVisibility()
                  EAB:ApplyCombatVisibility()
              end },
            -- Toggle Action Bar moved up into the slot the Visibility Options dropdown
            -- left behind: the keybind flips this bar shown/hidden, the same question the
            -- Visibility control answers. It carries the `not visOnly` gate its old row
            -- had, so visibility-only bars still get no toggle keybind.
            (not visOnly) and { type="label", text="Toggle Action Bar" }
                or { type="label", text="" });  y = y - h

        do
            local rgn = visRow1._leftRegion
            -- Click Through sits in this row's cog, so it travels with the copy
            -- (a visibility-only bar has none).
            local function CopyTo(key, src)
                CopyVisibilitySettings(EAB.db.profile.bars[key], src, key)
                if not visOnly then
                    EAB.db.profile.bars[key].clickThrough = src.clickThrough or false
                    EAB:ApplyClickThroughForBar(key)
                end
            end
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Visibility to all Bars",
                onClick = function()
                    local src = SB()
                    for _, key in ipairs(GROUP_BAR_ORDER) do CopyTo(key, src) end
                    EAB:RefreshRuntimeVisibility()
                    EAB:RefreshMouseover()
                    EAB:ApplyCombatVisibility()
                    EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local src = SB()
                    for _, key in ipairs(GROUP_BAR_ORDER) do
                        local dst = EAB.db.profile.bars[key]
                        if not EllesmereUI.VisFullEquals(src, "barVisibility", dst, "barVisibility") then return false end
                        if (src.dragShow or false) ~= (dst.dragShow or false) then return false end
                        if not visOnly and (src.clickThrough or false) ~= (dst.clickThrough or false) then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_BAR_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return SelectedKey() end,
                    onApply       = function(checkedKeys)
                        local src = SB()
                        for _, key in ipairs(checkedKeys) do CopyTo(key, src) end
                        EAB:RefreshRuntimeVisibility()
                        EAB:RefreshMouseover()
                        EAB:ApplyCombatVisibility()
                        EllesmereUI:RefreshPage()
                    end,
                },
            })
        end
        do
            local rgn = visRow1._leftRegion
            -- Show During Drag applies only while THIS bar's visibility is Never
            -- (other modes already surface during a drag); the row is always
            -- present, disabled with a requirement tooltip in the other modes.
            local function NeverOnly()
                local s = SB()
                return not (s.barVisibility == "never" or s.alwaysHidden)
            end
            local function SpellbookRow()
                -- Available in EVERY visibility mode (unlike Show During
                -- Drag, whose behavior IS the default outside Never).
                return { type="toggle", label="Show When Spellbook Is Open",
                  tooltip="While the spellbook or macro panel is open, this bar appears so you can drag abilities onto it.",
                  get=function() return SB().spellbookShow == true end,
                  set=function(v)
                      SB().spellbookShow = v or nil
                      -- Resync drops/replants the override live (covers
                      -- toggling while the spellbook is already open).
                      if EAB._UpdateSpellbookNeverBars then
                          EAB._UpdateSpellbookNeverBars(true)
                      end
                  end }
            end
            local function DragRow()
                return { type="toggle", label="Show During Drag",
                  tooltip="While dragging a spell or item, this bar appears so you can drop onto it.",
                  disabled=NeverOnly,
                  disabledTooltip="Visibility set to Never",
                  get=function() return SB().dragShow == true end,
                  set=function(v)
                      SB().dragShow = v
                      -- The Apply Visibility link compares this toggle.
                      EllesmereUI:RefreshPage()
                  end }
            end
            local rows = { SpellbookRow(), DragRow() }
            if not visOnly then
                rows[#rows + 1] = { type="toggle", label="Click Through",
                  get=function() return SGet("clickThrough") end,
                  set=function(v)
                      SSet("clickThrough", v, function(k) EAB:ApplyClickThroughForBar(k) end)
                      -- The Apply Visibility link compares this toggle.
                      EllesmereUI:RefreshPage()
                  end }
            end
            EllesmereUI.BuildInlineCog(rgn, {
                title = "Visibility",
                rows = rows,
                anchorTo = rgn._control,
            })
        end
    end

    -- Show All Bars on Mouseover: one setting for every bar (the profile's). It links
    -- every bar set to Mouseover, action bars, the micro menu, the bag bar and
    -- the data bars alike (the runtime's mouseoverEnabled), so it is offered
    -- while any of them is. Beside End Caps, or on a row of its own where the
    -- section has no End Caps (a visibility-only bar, the WoW Forever look).
    local function AnyMouseoverBar()
        for _, s in pairs(EAB.db.profile.bars) do
            if type(s) == "table" and s.mouseoverEnabled then return true end
        end
        return false
    end
    local function ShowAllCfg()
        return { type="toggle", text="Show All Bars on Mouseover",
          tooltip="Hovering one Mouseover bar shows them all.",
          disabled=function() return not AnyMouseoverBar() end,
          disabledTooltip="This option requires a bar set to Mouseover",
          getValue=function() return EAB.db.profile.mouseoverShowAll or false end,
          setValue=function(v) EAB.db.profile.mouseoverShowAll = v end }
    end

    -- Bar Opacity keeps this row (and its sync icon, now on the left region) with
    -- Always Show Buttons as its partner; Toggle Action Bar sits in the Visibility row.
    row, h = W:DualRow(parent, y,
        { type="slider", text="Bar Opacity", min=0, max=100, step=5,
          getValue=function()
              local bs = SB()
              if bs.mouseoverEnabled then
                  return floor((bs._savedBarAlpha or 1) * 100 + 0.5)
              end
              return floor((bs.mouseoverAlpha or 1) * 100 + 0.5)
          end,
          setValue=function(v)
              local bs = SB()
              if bs.mouseoverEnabled then
                  bs._savedBarAlpha = v / 100
              else
                  SSet("mouseoverAlpha", v / 100, function(k) EAB:ApplyBarOpacity(k) end)
              end
              SUpdatePreview()
          end },
        { type="toggle", text="Always Show Buttons",
          getValue=function()
              local v = SGet("alwaysShowButtons")
              if v == nil then return true end
              return v
          end,
          setValue=function(v)
              SSet("alwaysShowButtons", v, function(k)
                  EAB:ApplyAlwaysShowButtons(k)
                  EAB:ApplyPaddingForBar(k)
                  EAB:ApplyBackgroundForBar(k)
              end)
              SUpdatePreview()
          end,
          tooltip="Show button backgrounds even if a spell is not assigned to that slot." });  y = y - h
    do
        local rgn = row._leftRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Bar Opacity to all Bars",
            onClick = function()
                local v = SB().mouseoverAlpha or 1
                for _, key in ipairs(GROUP_BAR_ORDER) do
                    EAB.db.profile.bars[key].mouseoverAlpha = v
                    EAB:ApplyBarOpacity(key)
                end
                EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                local cur = SB()
                local v = cur.mouseoverEnabled and 1 or (cur.mouseoverAlpha or 1)
                for _, key in ipairs(GROUP_BAR_ORDER) do
                    local bs = EAB.db.profile.bars[key]
                    local bv = bs.mouseoverEnabled and 1 or (bs.mouseoverAlpha or 1)
                    if bv ~= v then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_BAR_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return SelectedKey() end,
                onApply       = function(checkedKeys)
                    local v = SB().mouseoverAlpha or 1
                    for _, key in ipairs(checkedKeys) do
                        EAB.db.profile.bars[key].mouseoverAlpha = v
                        EAB:ApplyBarOpacity(key)
                    end
                    EllesmereUI:RefreshPage()
                end,
            },
        })
    end

    -- The bar's end caps (EndCapsCtl). Under WoW Forever it opens LAYOUT
    -- beside Show Bar Background; every other look puts it beside Show All
    -- Bars on Mouseover. A change to Action Bar 1's caps also repaints a bar
    -- carrying one of them (the first-install span).
    local CAPS = (not visOnly) and EndCapsCtl({
        key = SelectedKey, store = SB, label = "End Caps",
        vertical = function() return not EAB:GetOrientationForBar(SelectedKey()) end,
        write = function(k, v)
            if k then
                SSet(k, v, function(bk) EAB:ApplyPaddingForBar(bk) end)
                SUpdatePreviewAndResize()
            else
                EAB:ApplyPaddingForBar(SelectedKey())
                SUpdatePreviewAndResize()
                EllesmereUI:RefreshPage()
            end
            if SelectedKey() == "MainBar" then ns.AB_CapsSpanApply() end
        end,
        copyApply = function(key)
            EAB:ApplyPaddingForBar(key)
            if key == "MainBar" then ns.AB_CapsSpanApply() end
        end,
        syncKeys = GROUP_BAR_ORDER, syncLabels = SHORT_LABELS,
    }) or nil

    if CAPS and not CAPS.forever then
        local capsRow
        capsRow, h = W:DualRow(parent, y, CAPS.Cfg(), ShowAllCfg());  y = y - h
        CAPS.Build(capsRow._leftRegion)
    else
        _, h = W:DualRow(parent, y, ShowAllCfg(), EllesmereUI.BlankRowCfg());  y = y - h
    end

    if not visOnly then
        -- "Toggle Action Bar" keybind: bound key flips the bar shown/hidden at runtime
        -- without writing saved visibility. Enabled only for Always/Never; out of combat
        -- only. Its label sits in the Visibility row, so the button goes there too.
        do
            local rgn = visRow1._rightRegion
            local kbBtn, refresh = EllesmereUI.BuildKeybindButton(rgn, {
                w = 126, h = 29, level = 4,
                get = function() return SB().toggleVisKey end,
                set = function(v)
                    SB().toggleVisKey = v
                    EAB:RebuildVisToggleBindings()
                    EllesmereUI._NotifySettingWrite(rgn)
                end,
                disabled = function()
                    local v = SB().barVisibility or "always"
                    return v ~= "always" and v ~= "never"
                end,
                disabledTip = "Visibility set to Always or Never",
                tooltip = "Toggling an action bar is only available out of combat\n\nLeft-click to set a keybind.\nRight-click to unbind.",
            })
            PP.Point(kbBtn, "RIGHT", rgn, "RIGHT", -20, 0)
            EllesmereUI.RegisterWidgetRefresh(refresh)

            -- Spec Overrides capture: bespoke widget opts in with a synthetic accessor (left half is a plain label cfg, no get/set).
            EllesmereUI.AddCaptureAccessor(rgn, {
                type = "keybind", text = "Toggle Action Bar",
                getValue = function() return SB().toggleVisKey end,
                setValue = function(v)
                    SB().toggleVisKey = v
                    EAB:RebuildVisToggleBindings()
                    refresh()
                end,
            })
        end
    end

    -----------------------------------------------------------------------
    --  LAYOUT  (hidden when visibility-only)
    -----------------------------------------------------------------------
    if not visOnly then
        _, h = W:SectionHeader(parent, SECTION_LAYOUT, y);  y = y - h

        -- WoW Forever: the bar's end caps and the frame and dividers behind
        -- its buttons (both on by default on Action Bar 1 only) open the
        -- section.
        if CAPS and CAPS.forever then
            local capsRow
            capsRow, h = W:DualRow(parent, y,
                CAPS.Cfg(),
                { type="toggle", text="Show Bar Background",
                  tooltip="Show the frame and dividers behind the bar's buttons.",
                  getValue=function() return ns.AB_ForeverBg(SelectedKey()) end,
                  setValue=function(v)
                      SSet("foreverBarBg", v and true or false, function(k) EAB:ApplyPaddingForBar(k) end)
                      SUpdatePreviewAndResize()
                  end });  y = y - h
            CAPS.Build(capsRow._leftRegion)
            do
                local rgn = capsRow._rightRegion
                local function BgTo(key, v)
                    local d = EAB.db.profile.bars[key]
                    if d then
                        d.foreverBarBg = v
                        EAB:ApplyPaddingForBar(key)
                    end
                end
                EllesmereUI.BuildSyncIcon({
                    region  = rgn,
                    tooltip = "Apply Show Bar Background to all Bars",
                    onClick = function()
                        local v = ns.AB_ForeverBg(SelectedKey())
                        for _, key in ipairs(GROUP_BAR_ORDER) do BgTo(key, v) end
                        EllesmereUI:RefreshPage()
                    end,
                    isSynced = function()
                        local v = ns.AB_ForeverBg(SelectedKey())
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            if ns.AB_ForeverBg(key) ~= v then return false end
                        end
                        return true
                    end,
                    flashTargets = function() return { rgn } end,
                    multiApply = {
                        elementKeys   = GROUP_BAR_ORDER,
                        elementLabels = SHORT_LABELS,
                        getCurrentKey = function() return SelectedKey() end,
                        onApply       = function(checkedKeys)
                            local v = ns.AB_ForeverBg(SelectedKey())
                            for _, key in ipairs(checkedKeys) do BgTo(key, v) end
                            EllesmereUI:RefreshPage()
                        end,
                    },
                })
            end
        end

        local iconSizeRow
        iconSizeRow, h = W:DualRow(parent, y,
            { type="slider", text="Icon Size", min=16, max=120, step=1,
              -- Every style sizes from this slider (stock styles scale Blizzard's
              -- native-size button to it); only a size match locks it.
              disabled=function()
                  local k = SelectedKey()
                  if EllesmereUI.GetWidthMatchTarget and EllesmereUI.GetWidthMatchTarget(k) then return true end
                  if EllesmereUI.GetHeightMatchTarget and EllesmereUI.GetHeightMatchTarget(k) then return true end
                  return false
              end,
              disabledTooltip=function()
                  local k = SelectedKey()
                  local wt = EllesmereUI.GetWidthMatchTarget and EllesmereUI.GetWidthMatchTarget(k)
                  local ht = EllesmereUI.GetHeightMatchTarget and EllesmereUI.GetHeightMatchTarget(k)
                  local target = wt or ht
                  if target then
                      local name = (EllesmereUI.GetBarLabel and EllesmereUI.GetBarLabel(target)) or target
                      return EllesmereUI.Lf("Size matched to %1$s. Unmatch in Unlock Mode to edit.", name)
                  end
                  return nil
              end,
              rawTooltip=true,
              getValue=function()
                  local s = SB()
                  if s.buttonWidth and s.buttonWidth > 0 then return s.buttonWidth end
                  local info = BAR_LOOKUP[SelectedKey()]
                  local btn1 = FirstBarButton(SelectedKey())
                  return btn1 and math.floor((btn1:GetWidth() or 36) + 0.5) or 36
              end,
              setValue=function(v)
                  SB().buttonWidth  = v
                  SB().buttonHeight = v
                  SB()._matchExtraPixels = nil
                  SB()._matchExtraPixelsH = nil
                  EAB:ApplyButtonSizeForBar(SelectedKey())
                  SUpdatePreviewAndResize()
                  EllesmereUI:RefreshPage()
              end },
            { type="slider", pixel=true, text="Button Spacing", min=-10, max=20, step=1,
              getValue=function() return SVal("buttonPadding", 2) end,
              setValue=function(v)
                  SSet("buttonPadding", v, function(k) EAB:ApplyPaddingForBar(k) end)
                  SUpdatePreview()
              end });  y = y - h
        do
            local rgn = iconSizeRow._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Icon Size to all Bars",
                onClick = function()
                    local s = SB()
                    local info = BAR_LOOKUP[SelectedKey()]
                    local btn1 = FirstBarButton(SelectedKey())
                    local v = (s.buttonWidth and s.buttonWidth > 0) and s.buttonWidth
                        or (btn1 and math.floor((btn1:GetWidth() or 36) + 0.5)) or 36
                    for _, key in ipairs(GROUP_BAR_ORDER) do
                        EAB.db.profile.bars[key].buttonWidth  = v
                        EAB.db.profile.bars[key].buttonHeight = v
                        EAB:ApplyButtonSizeForBar(key)
                    end
                    EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local s = SB()
                    local info = BAR_LOOKUP[SelectedKey()]
                    local btn1 = FirstBarButton(SelectedKey())
                    local v = (s.buttonWidth and s.buttonWidth > 0) and s.buttonWidth
                        or (btn1 and math.floor((btn1:GetWidth() or 36) + 0.5)) or 36
                    for _, key in ipairs(GROUP_BAR_ORDER) do
                        local ks = EAB.db.profile.bars[key]
                        local kv = (ks.buttonWidth and ks.buttonWidth > 0) and ks.buttonWidth or v
                        if kv ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_BAR_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return SelectedKey() end,
                    onApply       = function(checkedKeys)
                        local s = SB()
                        local info = BAR_LOOKUP[SelectedKey()]
                        local btn1 = FirstBarButton(SelectedKey())
                        local v = (s.buttonWidth and s.buttonWidth > 0) and s.buttonWidth
                            or (btn1 and math.floor((btn1:GetWidth() or 36) + 0.5)) or 36
                        for _, key in ipairs(checkedKeys) do
                            EAB.db.profile.bars[key].buttonWidth  = v
                            EAB.db.profile.bars[key].buttonHeight = v
                            EAB:ApplyButtonSizeForBar(key)
                        end
                        EllesmereUI:RefreshPage()
                    end,
                },
            })
        end
        do
            local rgn = iconSizeRow._rightRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Button Spacing to all Bars",
                onClick = function()
                    local v = SB().buttonPadding or 2
                    for _, key in ipairs(GROUP_BAR_ORDER) do
                        EAB.db.profile.bars[key].buttonPadding = v
                        EAB:ApplyPaddingForBar(key)
                    end
                    EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = SB().buttonPadding or 2
                    for _, key in ipairs(GROUP_BAR_ORDER) do
                        if (EAB.db.profile.bars[key].buttonPadding or 2) ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_BAR_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return SelectedKey() end,
                    onApply       = function(checkedKeys)
                        local v = SB().buttonPadding or 2
                        for _, key in ipairs(checkedKeys) do
                            EAB.db.profile.bars[key].buttonPadding = v
                            EAB:ApplyPaddingForBar(key)
                        end
                        EllesmereUI:RefreshPage()
                    end,
                },
            })
        end

        row, h = W:DualRow(parent, y,
            { type="slider", text="Number of Icons", min=1, max=12, step=1,
              disabled=function()
                  local info = BAR_LOOKUP[SelectedKey()]
                  return info and info.isStance
              end,
              getValue=function()
                  local v = SGet("overrideNumIcons")
                  if v and v > 0 then return v end
                  local s = SB()
                  if s and s.numIcons and s.numIcons > 0 then
                      return s.numIcons
                  end
                  return 12
              end,
              setValue=function(v)
                  SSet("overrideNumIcons", v, function(k) EAB:ApplyIconRowOverrides(k) end)
                  SUpdatePreviewAndResize()
              end },
            { type="slider", text="Number of Rows", min=1, max=12, step=1,
              getValue=function()
                  local v = SGet("overrideNumRows")
                  if v and v > 0 then return v end
                  local s = SB()
                  if s and s.numRows and s.numRows > 0 then
                      return s.numRows
                  end
                  return 1
              end,
              setValue=function(v)
                  SSet("overrideNumRows", v, function(k) EAB:ApplyIconRowOverrides(k) end)
                  SUpdatePreviewAndResize()
              end });  y = y - h
        do
            local rgn = row._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Number of Icons to all Bars",
                onClick = function()
                    local v = SB().overrideNumIcons or 12
                    for _, key in ipairs(GROUP_BAR_ORDER) do
                        EAB.db.profile.bars[key].overrideNumIcons = v
                        EAB:ApplyIconRowOverrides(key)
                    end
                    EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = SB().overrideNumIcons or 12
                    for _, key in ipairs(GROUP_BAR_ORDER) do
                        if (EAB.db.profile.bars[key].overrideNumIcons or 12) ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_BAR_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return SelectedKey() end,
                    onApply       = function(checkedKeys)
                        local v = SB().overrideNumIcons or 12
                        for _, key in ipairs(checkedKeys) do
                            EAB.db.profile.bars[key].overrideNumIcons = v
                            EAB:ApplyIconRowOverrides(key)
                        end
                        EllesmereUI:RefreshPage()
                    end,
                },
            })
        end
        do
            local rgn = row._rightRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Number of Rows to all Bars",
                onClick = function()
                    local v = SB().overrideNumRows or 1
                    for _, key in ipairs(GROUP_BAR_ORDER) do
                        EAB.db.profile.bars[key].overrideNumRows = v
                        EAB:ApplyIconRowOverrides(key)
                    end
                    EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local v = SB().overrideNumRows or 1
                    for _, key in ipairs(GROUP_BAR_ORDER) do
                        if (EAB.db.profile.bars[key].overrideNumRows or 1) ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_BAR_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return SelectedKey() end,
                    onApply       = function(checkedKeys)
                        local v = SB().overrideNumRows or 1
                        for _, key in ipairs(checkedKeys) do
                            EAB.db.profile.bars[key].overrideNumRows = v
                            EAB:ApplyIconRowOverrides(key)
                        end
                        EllesmereUI:RefreshPage()
                    end,
                },
            })
        end
        do
            local rightRgn = row._rightRegion
            local isVert = SVal("orientation", "horizontal") == "vertical"
            local growDirValues, growDirOrder
            if isVert then
                growDirValues = { up = "Up", down = "Down", center = "Centered" }
                growDirOrder  = { "up", "down", "center" }
            else
                growDirValues = { left = "Left", right = "Right", center = "Centered" }
                growDirOrder  = { "left", "right", "center" }
            end
            EllesmereUI.BuildInlineCog(rightRgn, {
                title = "Row Settings",
                anchorTo = rightRgn._control,
                rows = {
                    { type="dropdown", label="Grow Direction",
                      values=growDirValues, order=growDirOrder,
                      get=function()
                          local val = SVal("growDirection", "up")
                          if not growDirValues[val] then return "center" end
                          return val
                      end,
                      set=function(v)
                          SSet("growDirection", v, function(k) EAB:ApplyIconRowOverrides(k) end)
                          SUpdatePreviewAndResize()
                      end },
                },
            })
        end

        -- Icon Order "default"/"reversed" map onto the legacy reverseIconOrder boolean (kept in
        -- sync for older readers); corner values place button 1 in that corner of the grid.
        do
            local orientRow
            orientRow, h = W:DualRow(parent, y,
                { type="toggle", text="Vertical Orientation",
                  disabled=function()
                      return not EAB:BarSupportsOrientation(SelectedKey())
                  end,
                  disabledTooltip="This option is not supported for this bar type",
                  rawTooltip=true,
                  getValue=function()
                      return not EAB:GetOrientationForBar(SelectedKey())
                  end,
                  setValue=function(v)
                      EAB:SetOrientationForBar(SelectedKey(), not v)
                      SUpdatePreviewAndResize()
                      EllesmereUI:RefreshPage()
                  end },
                { type="dropdown", text="Icon Order",
                  values={ default="Default", reversed="Reversed", TOPLEFT="Top Left", TOPRIGHT="Top Right", BOTTOMLEFT="Bottom Left", BOTTOMRIGHT="Bottom Right" },
                  order={ "default", "reversed", "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" },
                  getValue=function()
                      local v = SVal("iconOrder", nil)
                      if v == nil then
                          v = SVal("reverseIconOrder", false) and "reversed" or "default"
                      end
                      return v
                  end,
                  setValue=function(v)
                      SDB().reverseIconOrder = (v == "reversed")
                      SSet("iconOrder", v, function(k) EAB:ApplyIconRowOverrides(k) end)
                      SUpdatePreviewAndResize()
                  end });  y = y - h
            do
                local rgn = orientRow._leftRegion
                EllesmereUI.BuildSyncIcon({
                    region  = rgn,
                    tooltip = "Apply Orientation to all Bars",
                    onClick = function()
                        local isHoriz = EAB:GetOrientationForBar(SelectedKey())
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            if EAB:BarSupportsOrientation(key) then
                                EAB:SetOrientationForBar(key, isHoriz)
                            end
                        end
                        EllesmereUI:RefreshPage()
                    end,
                    isSynced = function()
                        local isHoriz = EAB:GetOrientationForBar(SelectedKey())
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            if EAB:BarSupportsOrientation(key) and EAB:GetOrientationForBar(key) ~= isHoriz then return false end
                        end
                        return true
                    end,
                    flashTargets = function() return { rgn } end,
                    multiApply = {
                        elementKeys   = GROUP_BAR_ORDER,
                        elementLabels = SHORT_LABELS,
                        getCurrentKey = function() return SelectedKey() end,
                        onApply       = function(checkedKeys)
                            local isHoriz = EAB:GetOrientationForBar(SelectedKey())
                            for _, key in ipairs(checkedKeys) do
                                if EAB:BarSupportsOrientation(key) then
                                    EAB:SetOrientationForBar(key, isHoriz)
                                end
                            end
                            EllesmereUI:RefreshPage()
                        end,
                    },
                })
            end

            -- Disabled: the dedicated BAR BACKGROUND section below owns these.
            if false then
            do
                local rgn = orientRow._rightRegion
                EllesmereUI.BuildSyncIcon({
                    region  = rgn,
                    tooltip = "Apply Background Settings to all Bars",
                    onClick = function()
                        local s = SB()
                        local en = s.bgEnabled
                        local c = s.bgColor
                        local bc = s.bgBorderColor
                        local px = s.bgPadX or 0
                        local py = s.bgPadY or 0
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            local bs = EAB.db.profile.bars[key]
                            bs.bgEnabled = en
                            if c then bs.bgColor = { r=c.r, g=c.g, b=c.b, a=c.a } end
                            bs.bgPadX = px
                            bs.bgPadY = py
                            bs.bgBorderThickness = s.bgBorderThickness
                            bs.bgBorderTexture = s.bgBorderTexture
                            bs.bgBorderSize = s.bgBorderSize
                            if bc then bs.bgBorderColor = { r=bc.r, g=bc.g, b=bc.b, a=bc.a } end
                            EAB:ApplyBackgroundForBar(key)
                        end
                        EllesmereUI:RefreshPage()
                    end,
                    isSynced = function()
                        local s = SB()
                        local en = s.bgEnabled or false
                        local px = s.bgPadX or 0
                        local py = s.bgPadY or 0
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            local bs = EAB.db.profile.bars[key]
                            if (bs.bgEnabled or false) ~= en then return false end
                            if (bs.bgPadX or 0) ~= px then return false end
                            if (bs.bgPadY or 0) ~= py then return false end
                            if (bs.bgBorderThickness or "none") ~= (s.bgBorderThickness or "none") then return false end
                            if (bs.bgBorderTexture or "solid") ~= (s.bgBorderTexture or "solid") then return false end
                            if (bs.bgBorderSize or 1) ~= (s.bgBorderSize or 1) then return false end
                        end
                        return true
                    end,
                    flashTargets = function() return { rgn } end,
                    multiApply = {
                        elementKeys   = GROUP_BAR_ORDER,
                        elementLabels = SHORT_LABELS,
                        getCurrentKey = function() return SelectedKey() end,
                        onApply       = function(checkedKeys)
                            local s = SB()
                            local en = s.bgEnabled
                            local c = s.bgColor
                            local bc = s.bgBorderColor
                            local px = s.bgPadX or 0
                            local py = s.bgPadY or 0
                            for _, key in ipairs(checkedKeys) do
                                local bs = EAB.db.profile.bars[key]
                                bs.bgEnabled = en
                                if c then bs.bgColor = { r=c.r, g=c.g, b=c.b, a=c.a } end
                                bs.bgPadX = px
                                bs.bgPadY = py
                                bs.bgBorderThickness = s.bgBorderThickness
                                bs.bgBorderTexture = s.bgBorderTexture
                                bs.bgBorderBehind = s.bgBorderBehind
                                bs.bgBorderSize = s.bgBorderSize
                                if bc then bs.bgBorderColor = { r=bc.r, g=bc.g, b=bc.b, a=bc.a } end
                                EAB:ApplyBackgroundForBar(key)
                            end
                            EllesmereUI:RefreshPage()
                        end,
                    },
                })
            end
            do
                local bgRgn = orientRow._rightRegion
                local bgColorGet = function()
                    local c = SGet("bgColor")
                    if not c then return 0, 0, 0, 0.5 end
                    return c.r, c.g, c.b, c.a
                end
                local bgColorSet = function(r, g, b, a)
                    SSetColor("bgColor", r, g, b, a, function(k) EAB:ApplyBackgroundForBar(k) end)
                    SUpdatePreview()
                end
                local bgSwatch, bgUpdateSwatch = EllesmereUI.BuildColorSwatch(bgRgn, bgRgn:GetFrameLevel() + 5, bgColorGet, bgColorSet, true, 20)
                PP.Point(bgSwatch, "RIGHT", bgRgn._control, "LEFT", -12, 0)
                bgRgn._lastInline = bgSwatch
                EllesmereUI.RegisterWidgetRefresh(function()
                    local off = BgDisabled()
                    bgSwatch:SetAlpha(off and 0.15 or 1)
                    bgUpdateSwatch()
                end)
                bgSwatch:SetAlpha(BgDisabled() and 0.15 or 1)
                local bgSwatchOrigClick = bgSwatch:GetScript("OnClick")
                bgSwatch:SetScript("OnClick", function(self, ...)
                    if BgDisabled() then return end
                    if bgSwatchOrigClick then bgSwatchOrigClick(self, ...) end
                end)
                bgSwatch:SetScript("OnEnter", function(self)
                    if BgDisabled() then
                        EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Bar Background"))
                    end
                end)
                bgSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

                EllesmereUI.BuildInlineCog(bgRgn, {
                    title = "Bar Background Settings",
                    icon = EllesmereUI.RESIZE_ICON, gap = 9,
                    disabled = BgDisabled, disabledTooltip = "Bar Background",
                    rows = {
                        { type="slider", label="Width", min=0, max=40, step=1,
                          get=function() return SVal("bgPadX", 0) end,
                          set=function(v)
                              SSet("bgPadX", v, function(k) EAB:ApplyBackgroundForBar(k) end)
                              SUpdatePreview()
                          end },
                        { type="slider", label="Height", min=0, max=40, step=1,
                          get=function() return SVal("bgPadY", 0) end,
                          set=function(v)
                              SSet("bgPadY", v, function(k) EAB:ApplyBackgroundForBar(k) end)
                              SUpdatePreview()
                          end },
                    },
                })
            end
            end
        end
    end  -- if not visOnly

    return y
end

-- Used by EUI_ActionBars_Options.lua
ns.ABO_BuildBarVisibilityLayout = BuildBarVisibilityLayout
