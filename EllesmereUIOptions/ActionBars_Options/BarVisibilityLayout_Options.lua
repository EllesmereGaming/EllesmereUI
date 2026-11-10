if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  ActionBars_Options\BarVisibilityLayout_Options.lua
--  Action Bars options: the Bar 10 caution and the Visibility & Fading and
--  Layout sections of the Bar Display page. Called by BuildSharedBarSettings;
--  returns y. Shared helpers come from ns._ABO_OptEnv, the per-build helpers
--  from ctx.
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUIActionBars"]
if not ns then return end  -- module disabled: no options page
-- Options page pool (EllesmereUI_FramePool.lua, first in this addon): a frame
-- made here on a pool host (a kept page and every frame it hands out) is reset
-- and dressed again by the next build instead of made anew; on any other
-- parent this is CreateFrame.
local CreateFrame = EllesmereUI._Pool.CreateFrame

local function BuildBarVisibilityLayout(parent, y, ctx)
    local env = ns._ABO_OptEnv
    local ApplyVisibilityKey, BAR_LOOKUP, CopyVisibilitySettings, EAB = env.ApplyVisibilityKey, env.BAR_LOOKUP, env.CopyVisibilitySettings, env.EAB
    local FirstBarButton, floor, GetVisibilityKey = env.FirstBarButton, env.floor, env.GetVisibilityKey
    local GROUP_BAR_ORDER, IsDataBar, PP, SB = env.GROUP_BAR_ORDER, env.IsDataBar, env.PP, env.SB
    local SECTION_LAYOUT, SECTION_VISIBILITY, SelectedKey, SHORT_LABELS = env.SECTION_LAYOUT, env.SECTION_VISIBILITY, env.SelectedKey, env.SHORT_LABELS
    local SDB, SGet, SSet = ctx.SDB, ctx.SGet, ctx.SSet
    local SUpdatePreview, SUpdatePreviewAndResize, SVal = ctx.SUpdatePreview, ctx.SUpdatePreviewAndResize, ctx.SVal
    local visOnly = ctx.visOnly
    local W = ctx.W
    -- Visibility updates do not run ApplyAll. Recompile page-cycle macros when
    -- the set of reserved action pages changes (never/always etc.).
    local function RefreshPageCycle()
        ns.RefreshPagingCycleMacros()
    end
    local _, h, hdr
    local row

    -- Global search sees row labels and tooltips only. A checkbox dropdown
    -- row's entry, registered right before its row (the index keeps the first
    -- entry of a label), carries its tooltip, its items' names and the rows its
    -- cog holds as search text; it is never shown.
    local function IndexChecklistRow(label, tooltip, words)
        if not EllesmereUI._RegisterSearchEntry then return end
        local text = {}
        local function Add(s)
            text[#text + 1] = s
            local loc = EllesmereUI.L(s)
            if loc ~= s then text[#text + 1] = loc end
        end
        Add(tooltip)
        for i = 1, #words do Add(words[i]) end
        local labelLoc = EllesmereUI.L(label)
        local sel = EllesmereUI._buildingSelector
        EllesmereUI._RegisterSearchEntry(label, labelLoc ~= label and labelLoc or nil,
            table.concat(text, " "), EllesmereUI._buildingModule, EllesmereUI._buildingPage,
            parent._currentSection and parent._currentSection._sectionName,
            sel and sel.setter, sel and sel.key)
    end

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
    --  VISIBILITY & FADING
    -----------------------------------------------------------------------
    hdr, h = W:SectionHeader(parent, SECTION_VISIBILITY, y);  y = y - h
    -- The Move in Unlock Mode button on the selected bar's first section: the
    -- key is read at the click, so it highlights the bar the selector shows.
    EllesmereUI.BuildSectionUnlockJump(hdr, { key = SelectedKey })

    -- A data bar under Blizzard's own data bars: the rows EUI cannot apply to it grey out.
    local _visBlizzDis
    local _VIS_BLIZZ_TIP = "This option does not work with Blizzard Bars. Please use Blizzard Edit Mode."
    if IsDataBar() then
        _visBlizzDis = function() return EAB.db.profile.useBlizzardDataBars end
    end

    do
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

        -- Visibility Extras: the times this bar shows beyond its Visibility
        -- setting, one checkbox per setting, each a view over its own key.
        local VIS_EXTRAS = "Visibility Extras"
        local VIS_EXTRAS_TIP = "More times this bar shows, beyond its Visibility setting."
        IndexChecklistRow(VIS_EXTRAS, VIS_EXTRAS_TIP,
            { "Show When Spellbook Is Open", "Show During Drag", "Show All Bars on Mouseover" })

        local visRow1
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
                  RefreshPageCycle()
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
            -- The placeholder the Visibility Extras checklist replaces. Its getter
            -- reads the three keys the checklist writes, so the Spec Overrides
            -- gold walk marks the slot while one of them is overridden.
            { type="dropdown", text=VIS_EXTRAS, tooltip=VIS_EXTRAS_TIP,
              values={ __placeholder = "..." }, order={ "__placeholder" },
              getValue=function()
                  local s = SB()
                  local _ = s.spellbookShow
                  _ = s.dragShow
                  _ = EAB.db.profile.mouseoverShowAll
                  return "__placeholder"
              end,
              setValue=function() end });  y = y - h

        do
            local rgn = visRow1._leftRegion
            local function CopyTo(key, src)
                CopyVisibilitySettings(EAB.db.profile.bars[key], src, key)
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
                    RefreshPageCycle()
                    EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local src = SB()
                    for _, key in ipairs(GROUP_BAR_ORDER) do
                        local dst = EAB.db.profile.bars[key]
                        if not EllesmereUI.VisFullEquals(src, "barVisibility", dst, "barVisibility") then return false end
                        if (src.dragShow or false) ~= (dst.dragShow or false) then return false end
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
                        RefreshPageCycle()
                        EllesmereUI:RefreshPage()
                    end,
                },
            })
        end
        if not EllesmereUI._prebuilding then
            local rgn = visRow1._rightRegion
            -- Show During Drag applies only while THIS bar's visibility is Never
            -- (other modes already surface during a drag); the item is always
            -- listed, locked with a requirement tooltip in the other modes.
            local function NeverOnly()
                local s = SB()
                return not (s.barVisibility == "never" or s.alwaysHidden)
            end
            -- Show All Bars on Mouseover is one setting for every bar (the
            -- profile's). It links every bar set to Mouseover, action bars, the
            -- micro menu, the bag bar and the data bars alike (the runtime's
            -- mouseoverEnabled), so it is offered while any of them is.
            local function AnyMouseoverBar()
                for _, s in pairs(EAB.db.profile.bars) do
                    if type(s) == "table" and s.mouseoverEnabled then return true end
                end
                return false
            end
            local items = {
                -- Available in EVERY visibility mode (unlike Show During Drag,
                -- whose behavior IS the default outside Never).
                { key = "spellbookShow", label = "Show When Spellbook Is Open",
                  tooltip = "While the spellbook or macro panel is open, this bar appears so you can drag abilities onto it." },
                { key = "dragShow", label = "Show During Drag",
                  tooltip = "While dragging a spell or item, this bar appears so you can drop onto it.",
                  lockedFn = NeverOnly,
                  lockedTooltip = function() return EllesmereUI.DisabledTooltip("Visibility set to Never") end },
                { key = "mouseoverShowAll", label = "Show All Bars on Mouseover",
                  tooltip = "Hovering one Mouseover bar shows them all.",
                  lockedFn = function() return not AnyMouseoverBar() end,
                  lockedTooltip = "This option requires a bar set to Mouseover" },
            }
            if rgn._control then rgn._control:Hide() end
            -- Wider than the standard 170: its longest rows ("Show When Spellbook
            -- Is Open") must fit on the closed button and in the list.
            local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                rgn, 240, rgn:GetFrameLevel() + 2, items,
                function(k)
                    if k == "mouseoverShowAll" then
                        return EAB.db.profile.mouseoverShowAll and true or false
                    end
                    return SB()[k] == true
                end,
                function(k, v)
                    if k == "spellbookShow" then
                        SB().spellbookShow = v or nil
                        -- Resync drops/replants the override live (covers
                        -- toggling while the spellbook is already open).
                        EAB._UpdateSpellbookNeverBars(true)
                    elseif k == "dragShow" then
                        SB().dragShow = v
                        -- The Apply Visibility link compares this setting.
                        EllesmereUI:RefreshPage()
                    else
                        EAB.db.profile.mouseoverShowAll = v
                    end
                end, nil, nil, nil, nil, nil,
                -- Spec Overrides see each click as it happens (the slot's capture).
                { notifyWrites = true, dimLocked = true })
            PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
            rgn._control = cbDD
            rgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
        end
    end

    -----------------------------------------------------------------------
    --  ADVANCED FADE: the conditions are the setting (none checked is off),
    --  their cog holds Advanced Fade Opacity and the two fade times, and one
    --  Apply link copies all of it.
    -----------------------------------------------------------------------
    local fadeItems, ApplyAdvancedFadeTo, AdvancedFadeSynced
    -- The opacity and the fade times wait for a condition (and stand down with
    -- a data bar under Blizzard's own bars, as the conditions do).
    local function AdvancedFadeOff()
        return not EAB.AdvancedFadeOn(SB()) or (_visBlizzDis ~= nil and _visBlizzDis())
    end
    local function AdvancedFadeOffTip()
        if _visBlizzDis ~= nil and _visBlizzDis() then return _VIS_BLIZZ_TIP end
        return "This option requires an Advanced Fade condition to be checked"
    end
    do
        local FADE_ORDER = { "combat", "party", "raid", "instance", "mounted", "flying", "target", "enemy_target", "mouseover" }
        local FADE_LABELS = {
            combat = "In Combat",
            party = "In Party",
            raid = "In Raid",
            instance = "In Instance",
            mounted = "Mounted",
            flying = "Skyriding (Airborne)",
            target = "Target",
            enemy_target = "Enemy Target",
            mouseover = "Mouseover",
        }

        local function CopyAdvancedFade(dst, src)
            local out, sc = {}, src.advancedFadeConditions
            if type(sc) == "table" then
                for i = 1, #FADE_ORDER do
                    local k = FADE_ORDER[i]
                    if sc[k] then out[k] = true end
                end
            end
            dst.advancedFadeConditions = out
            dst.fadeMaxAlpha = src.fadeMaxAlpha ~= nil and src.fadeMaxAlpha or 1
            dst.fadeInSpeed = src.fadeInSpeed or 0.15
            dst.fadeOutSpeed = src.fadeOutSpeed or 0.15
        end

        local function AdvancedFadeEqual(a, b)
            local ac, bc = a.advancedFadeConditions, b.advancedFadeConditions
            for i = 1, #FADE_ORDER do
                local k = FADE_ORDER[i]
                if (type(ac) == "table" and ac[k] and true or false) ~= (type(bc) == "table" and bc[k] and true or false) then
                    return false
                end
            end
            if (a.fadeMaxAlpha ~= nil and a.fadeMaxAlpha or 1) ~= (b.fadeMaxAlpha ~= nil and b.fadeMaxAlpha or 1) then return false end
            if (a.fadeInSpeed or 0.15) ~= (b.fadeInSpeed or 0.15) then return false end
            return (a.fadeOutSpeed or 0.15) == (b.fadeOutSpeed or 0.15)
        end

        -- A bar the copy leaves with no condition hands its alpha back at
        -- once; the others repaint with the copied values.
        ApplyAdvancedFadeTo = function(keys)
            local src = SB()
            for _, key in ipairs(keys) do
                local dst = EAB.db.profile.bars[key]
                if dst and dst ~= src then CopyAdvancedFade(dst, src) end
            end
            EAB:RefreshAdvancedFadeEnabled(keys)
            EAB:RefreshAllCustomFade(true, true)
            EllesmereUI:RefreshPage()
        end

        AdvancedFadeSynced = function()
            local src = SB()
            for _, key in ipairs(GROUP_BAR_ORDER) do
                local dst = EAB.db.profile.bars[key]
                if dst and not AdvancedFadeEqual(src, dst) then return false end
            end
            return true
        end

        -- No skyriding on WoW Forever.
        fadeItems = {}
        for i = 1, #FADE_ORDER do
            local k = FADE_ORDER[i]
            if k ~= "flying" or not EllesmereUI.IS_FOREVER then
                fadeItems[#fadeItems + 1] = { key = k, label = FADE_LABELS[k] }
            end
        end
    end

    -- Bar Opacity, with Advanced Fade beside it. Advanced Fade's own dropdown
    -- is a stand-in: the conditions' checkbox dropdown below takes its place as
    -- the half's control.
    do
        local words = { "Advanced Fade Opacity", "Fade In Time", "Fade Out Time" }
        for i = 1, #fadeItems do words[#words + 1] = fadeItems[i].label end
        IndexChecklistRow("Advanced Fade",
            "Fades this bar to Advanced Fade Opacity while one of the conditions you check holds (in combat, with a target, mounted and more). With none checked, Bar Opacity and Visibility alone decide.",
            words)
    end
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
                  -- The Advanced Fade layer rests on this value.
                  if EAB.AdvancedFadeOn(bs) then
                      EAB:RefreshCustomFadeForBar(SelectedKey(), false)
                  end
              else
                  SSet("mouseoverAlpha", v / 100, function(k) EAB:ApplyBarOpacity(k) end)
              end
              SUpdatePreview()
          end },
        -- Its getter reads the opacity the cog holds, so the Spec Overrides gold
        -- walk marks the slot while Advanced Fade Opacity is overridden.
        { type="dropdown", text="Advanced Fade",
          tooltip="Fades this bar to Advanced Fade Opacity while one of the conditions you check holds (in combat, with a target, mounted and more). With none checked, Bar Opacity and Visibility alone decide.",
          values={ ["_placeholder"]="..." }, order={ "_placeholder" },
          getValue=function()
              local _ = SB().fadeMaxAlpha
              return "_placeholder"
          end,
          setValue=function() end });  y = y - h
    local fadeRow = row
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

    if not EllesmereUI._prebuilding then
        local rgn = fadeRow._rightRegion
        if rgn._control then rgn._control:Hide() end
        local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
            rgn, 170, rgn:GetFrameLevel() + 2, fadeItems,
            function(k)
                local c = SB().advancedFadeConditions
                return type(c) == "table" and c[k] == true
            end,
            function(k, v)
                local bs = SB()
                if type(bs.advancedFadeConditions) ~= "table" then bs.advancedFadeConditions = {} end
                bs.advancedFadeConditions[k] = v and true or nil
                -- The first condition arms the layer's hooks; the last one
                -- unchecked hands the bar's alpha back.
                local key = SelectedKey()
                EAB:RefreshAdvancedFadeEnabled(key)
                EAB:RefreshCustomFadeForBar(key, true)
                EllesmereUI:RefreshPage()
            end, nil, nil, nil, nil, nil,
            { disabled = _visBlizzDis, disabledTooltip = _visBlizzDis and _VIS_BLIZZ_TIP or nil, rawTooltip = true })
        PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
        rgn._control = cbDD
        rgn._lastInline = nil
        EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
        EllesmereUI.BuildInlineCog(rgn, {
            title = "Advanced Fade",
            disabled = AdvancedFadeOff,
            disabledTooltip = AdvancedFadeOffTip, rawTooltip = true,
            rows = {
                { type="slider", label="Advanced Fade Opacity", min=0, max=100, step=1,
                  tooltip="The opacity the bar fades to while one of its Advanced Fade conditions holds, above or below Bar Opacity. Visibility still decides whether the bar shows at all.",
                  disabled=AdvancedFadeOff, disabledTooltip=AdvancedFadeOffTip, rawTooltip=true,
                  get=function() return floor(((SB().fadeMaxAlpha ~= nil and SB().fadeMaxAlpha or 1) * 100) + 0.5) end,
                  set=function(v) SSet("fadeMaxAlpha", v / 100, function(k) EAB:RefreshCustomFadeForBar(k, true) end) end },
                { type="slider", label="Fade In Time", min=0.01, max=2, step=0.01,
                  tooltip="Seconds the fade to Advanced Fade Opacity takes.",
                  get=function() return SB().fadeInSpeed or 0.15 end,
                  set=function(v) SSet("fadeInSpeed", v) end },
                { type="slider", label="Fade Out Time", min=0.01, max=2, step=0.01,
                  tooltip="Seconds the fade back to Bar Opacity takes.",
                  get=function() return SB().fadeOutSpeed or 0.15 end,
                  set=function(v) SSet("fadeOutSpeed", v) end },
            },
        })
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Advanced Fade to all Bars",
            onClick = function() ApplyAdvancedFadeTo(GROUP_BAR_ORDER) end,
            isSynced = AdvancedFadeSynced,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = GROUP_BAR_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return SelectedKey() end,
                onApply       = ApplyAdvancedFadeTo,
            },
        })
    end

    -- Toggle Action Bar beside Always Show Buttons; a visibility-only bar has no
    -- toggle keybind, so Always Show Buttons sits alone there.
    local alwaysShowCfg = { type="toggle", text="Always Show Buttons",
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
      tooltip="Show button backgrounds even if a spell is not assigned to that slot." }
    if visOnly then
        _, h = W:DualRow(parent, y, alwaysShowCfg, EllesmereUI.BlankRowCfg());  y = y - h
    else
        local toggleRow
        toggleRow, h = W:DualRow(parent, y,
            { type="label", text="Toggle Action Bar" },
            alwaysShowCfg);  y = y - h
        -- "Toggle Action Bar" keybind: bound key flips the bar shown/hidden at runtime
        -- without writing saved visibility. Enabled only for Always/Never; out of combat
        -- only. The button takes the slot its label names.
        do
            local rgn = toggleRow._leftRegion
            local kbBtn, refresh = EllesmereUI.BuildKeybindButton(rgn, {
                w = 126, h = 29, level = 4,
                get = function() return SB().toggleVisKey end,
                set = function(v)
                    -- Spec Overrides: the slot is read before the write, as
                    -- a rebuild may dress this row again for another setting.
                    local snap = EllesmereUI._SOAttribution(rgn)
                    SB().toggleVisKey = v
                    EAB:RebuildVisToggleBindings()
                    EllesmereUI._NotifySettingWrite(rgn, snap)
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

        -- Icon Spacing's search entry also answers to "Button Spacing".
        IndexChecklistRow("Icon Spacing", "Button Spacing", {})
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
            { type="slider", pixel=true, text="Icon Spacing", min=-10, max=20, step=1,
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
                tooltip = "Apply Icon Spacing to all Bars",
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
        end
    end  -- if not visOnly

    return y
end

-- Used by EUI_ActionBars_Options.lua
ns.ABO_BuildBarVisibilityLayout = BuildBarVisibilityLayout
