if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_LoadoutManager_Options.lua  --  Settings page for the Loadout Manager
--
--  The module owns the saved variables, the edit scope and the swap
--  machinery; this page drives it through the ns API. Status lines, summaries
--  and pickers are live widgets re-read on every page refresh. Picking another
--  edit scope rebuilds the page, since its tooltips and the copy cog name it.
-------------------------------------------------------------------------------
local ADDON_NAME = "EllesmereUILoadoutManager"
local ns = EllesmereUI._ModuleNS[ADDON_NAME]  -- module namespace (published by the module at its load)
if not ns then return end  -- module disabled: no options page

local PAGE_DISPLAY = "Loadout Manager"

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    if not EllesmereUI or not EllesmereUI.RegisterModule then return end

    local function DB() return ns.DB() end

    local function Refresh(force)
        EllesmereUI:RefreshPage(force and true or nil)
    end

    -- The module calls this when its state changes.
    ns.OnStateChanged = function()
        if EllesmereUI:GetActiveModule() ~= ADDON_NAME then return end
        Refresh()
    end

    local function NotEnabled() return not DB().enabled end

    -- Why a control is locked, shown as written (rawTooltip).
    local PICK_FIRST      = "Pick a gear set or talent loadout first."
    local NOT_IN_INSTANCE = "Enter a dungeon, raid or other instance first."
    local TALENT_SCOPE    = "Set Assign For to All Specs or your spec."

    ---------------------------------------------------------------------------
    --  Text helpers. Widget labels and tooltips are translated where the
    --  widgets draw them; the lines this page writes itself go through L/Lf.
    ---------------------------------------------------------------------------
    local DIM = EllesmereUI.COLOR_CODES.DIM
    local function Grey(text) return DIM .. tostring(text) .. "|r" end

    -- Assigned names in the suite accent, read on every call so a theme change
    -- lands with the next refresh.
    local function Accent(text)
        local c = EllesmereUI.ELLESMERE_GREEN
        return EllesmereUI.HexColor(c.r, c.g, c.b) .. tostring(text) .. "|r"
    end

    local ALL_SPECS_TEXT   = EllesmereUI.L("All Specs")
    local TXT_NOT_SET      = Grey(EllesmereUI.L("not set"))
    local TXT_NO_GEAR      = Grey(EllesmereUI.L("no gear"))
    local TXT_NO_TALENTS   = Grey(EllesmereUI.L("no talents"))
    local TXT_SLASH        = Grey(" / ")
    local TXT_NOTHING_HERE = Grey(EllesmereUI.L("nothing assigned here"))
    local TXT_OUTSIDE      = Grey(EllesmereUI.L("not in an instance"))
    local TXT_OPEN_WORLD   = Grey(EllesmereUI.L("open world"))
    local TXT_UNKNOWN      = Grey(EllesmereUI.L("unknown"))
    local TXT_PICK_SAVED   = Grey(EllesmereUI.L("pick a saved instance"))

    -- One assignment slot as "gear / talents", or "not set".
    local function PairSummary(gearName, talentStored)
        local talentName = ns.TalentDisplayName(talentStored)
        if not gearName and not talentName then return TXT_NOT_SET end
        return (gearName and Accent(gearName) or TXT_NO_GEAR) .. TXT_SLASH ..
               (talentName and Accent(talentName) or TXT_NO_TALENTS)
    end

    ---------------------------------------------------------------------------
    --  Content types, each specific type next to the one it outranks and Open
    --  World last (it applies on the way out)
    ---------------------------------------------------------------------------
    local TYPE_INFO = {}
    for _, info in ipairs(ns.INSTANCE_TYPE_ORDER) do TYPE_INFO[info.key] = info end

    local TYPE_LAYOUT = { "party", "mplus", "raid", "timewalking", "scenario", "delve", "arena", "pvp", "world" }

    -- Tooltips for the types whose label alone does not say where they
    -- apply; the others have none.
    local TYPE_TIPS = {
        world       = "Applies when you leave an instance.",
        mplus       = "Mythic and Mythic+ dungeons.",
        timewalking = "Timewalking dungeons and raids.",
    }

    local INSTANCE_KIND = {
        party = EllesmereUI.L("Dungeon"), raid = EllesmereUI.L("Raid"), scenario = EllesmereUI.L("Scenario"),
        arena = EllesmereUI.L("Arena"), pvp = EllesmereUI.L("Battleground"),
    }
    local INSTANCE_KIND_OTHER = EllesmereUI.L("Instance")

    ---------------------------------------------------------------------------
    --  Edit scope: "All Specs" plus one entry per specialization, set only by
    --  the Assign For pick
    ---------------------------------------------------------------------------
    local ALL_SPECS = "all"

    local function ScopeValues()
        -- Spec names come from the game already translated.
        local values, order = { _noLoc = true, [ALL_SPECS] = ALL_SPECS_TEXT }, { ALL_SPECS }
        for _, spec in ipairs(ns.GetSpecList()) do
            values[tostring(spec.id)] = spec.name
            order[#order + 1] = tostring(spec.id)
        end
        return values, order
    end

    local function GetScopeKey()
        local scope = ns.GetScope()
        return scope and tostring(scope) or ALL_SPECS
    end

    local function SetScopeKey(key)
        ns.SetScope(key ~= ALL_SPECS and tonumber(key) or nil)
        Refresh(true) -- the page's tooltips and the copy cog name the scope
    end

    local function ScopeLabel()
        local scope = ns.GetScope()
        return scope and tostring(ns.SpecName(scope)) or ALL_SPECS_TEXT
    end

    ---------------------------------------------------------------------------
    --  Pickers. Their value tables are refilled in place when the game's list
    --  changes and the cached menu is invalidated, so no rebuild is needed.
    ---------------------------------------------------------------------------
    local NONE = "__none__"
    local function Noop() end

    local gearIcons = {}

    local function GearEntries()
        local entries, sig = {}, {}
        for k in pairs(gearIcons) do gearIcons[k] = nil end
        for _, set in ipairs(ns.ListEquipmentSets()) do
            entries[#entries + 1] = { key = set.name, text = set.name }
            gearIcons[set.name] = set.icon
            sig[#sig + 1] = tostring(set.name) .. "=" .. tostring(set.icon)
        end
        return entries, table.concat(sig, "\n")
    end

    local function TalentEntries()
        local entries, sig = {}, {}
        for _, loadout in ipairs(ns.ListTalentLoadouts()) do
            local key = tostring(loadout.configID)
            entries[#entries + 1] = { key = key, text = loadout.name }
            sig[#sig + 1] = key .. "=" .. tostring(loadout.name)
        end
        return entries, table.concat(sig, "\n")
    end

    -- Menu options (_menuOpts) and the no-localize flag (_noLoc) ride along
    -- in the values table and survive a refill; everything else is replaced.
    local function FillValues(values, order, noneText, entries)
        for k in pairs(values) do
            if k ~= "_menuOpts" and k ~= "_noLoc" then values[k] = nil end
        end
        for i = #order, 1, -1 do order[i] = nil end
        values[NONE] = noneText
        order[1] = NONE
        for _, e in ipairs(entries) do
            values[e.key] = e.text
            order[#order + 1] = e.key
        end
    end

    -- Returns the tables for a picker plus Update (register as a widget
    -- refresh) and Attach (hand it the dropdown button once it exists).
    -- noneText is already translated.
    local function LivePicker(noneText, entriesFn, menuOpts)
        -- Set, loadout and instance names are the game's or the player's own:
        -- never run them through L().
        local values, order = { _noLoc = true }, {}
        if menuOpts then values._menuOpts = menuOpts end
        -- The search prebuild indexes the row, never its list.
        if EllesmereUI._prebuilding then return values, order, Noop, Noop end
        local entries, sig = entriesFn()
        FillValues(values, order, noneText, entries)
        local ddBtn
        local function Update()
            local e, s = entriesFn()
            if s == sig then return end
            sig = s
            FillValues(values, order, noneText, e)
            if ddBtn and ddBtn._invalidateMenu then ddBtn._invalidateMenu() end
        end
        local function Attach(btn) ddBtn = btn end
        return values, order, Update, Attach
    end

    local function SetSelectedTalentKey(key)
        if key == NONE then
            ns.SetSelectedTalent(nil)
        else
            for _, loadout in ipairs(ns.ListTalentLoadouts()) do
                if tostring(loadout.configID) == key then
                    ns.SetSelectedTalent(ns.StoreTalentLoadout(loadout))
                    break
                end
            end
        end
        Refresh()
    end

    ---------------------------------------------------------------------------
    --  Readers for the live labels
    ---------------------------------------------------------------------------
    local function LocationText()
        local ctx = ns.GetContext()
        if not ctx.inInstance then
            local zone = GetRealZoneText()
            if not zone or zone == "" then zone = ctx.name end
            return tostring(zone) .. "  " .. TXT_OPEN_WORLD
        end
        local kind = INSTANCE_KIND[ctx.instanceType] or INSTANCE_KIND_OTHER
        if ctx.difficultyName and ctx.difficultyName ~= "" then
            kind = kind .. ", " .. ctx.difficultyName
        end
        return tostring(ctx.name) .. "  " .. Grey(kind)
    end

    -- The difficulty a per-difficulty assignment here covers. A running key
    -- reads as Mythic, the difficulty you enter at (the module stores it so).
    local function DifficultyName()
        return ns.DifficultyName(ns.GetContext())
    end

    -- Where a resolved assignment comes from, e.g. "(Raid default, Holy)".
    local function SourceText(level, key, scope)
        local layer = scope and tostring(ns.SpecName(scope)) or ALL_SPECS_TEXT
        if level == "difficulty" then
            return Grey(EllesmereUI.Lf("(this instance, %1$s only, %2$s)", DifficultyName(), layer))
        elseif level == "instance" then
            return Grey(EllesmereUI.Lf("(this instance, %1$s)", layer))
        elseif level == "type" then
            local info = TYPE_INFO[key]
            local typeName = info and EllesmereUI.L(info.label) or tostring(key)
            return Grey(EllesmereUI.Lf("(%1$s default, %2$s)", typeName, layer))
        end
        return ""
    end

    -- This instance's assignment slot in the scope being edited, under the
    -- key the module writes for it. Returns inside, gear, talent.
    local function InstanceSlot(perDifficulty)
        local ctx = ns.GetContext()
        if not ctx.inInstance or not ctx.instanceID then return false end
        local key = ns.AssignmentKey(ctx, perDifficulty)
        if not key then return true end
        local R = ns.ReadTables()
        if perDifficulty then return true, R.difficultySets[key], R.talentDifficultySets[key] end
        return true, R.instanceSets[key], R.talentInstanceSets[key]
    end

    -- Saved Instances list: every instance assignment in the scope being
    -- edited, wherever you are. The pick is the page's own state; savedByKey
    -- holds the entries the latest list read returned, by picker key.
    local pickedSaved -- tostring(key) of the picked entry, or nil
    local savedByKey = {}

    local function SavedEntries()
        local entries, sig = {}, {}
        wipe(savedByKey)
        for _, e in ipairs(ns.ListInstanceAssignments()) do
            local key = tostring(e.key)
            entries[#entries + 1] = { key = key, text = e.label }
            sig[#sig + 1] = key .. "=" .. e.label
            savedByKey[key] = e
        end
        return entries, table.concat(sig, "\n")
    end

    local function PickedSavedEntry()
        return pickedSaved and savedByKey[pickedSaved] or nil
    end

    local function TypeSlot(key)
        local R = ns.ReadTables()
        return R.typeDefaults[key], R.talentTypeDefaults[key]
    end

    ---------------------------------------------------------------------------
    --  Widget helpers
    ---------------------------------------------------------------------------
    -- Show a live value after a half-row's own text (prefix, translated),
    -- re-read on every page refresh. The label is bounded left of the half's
    -- inline controls so a long line ellipsizes, and a half with no tooltip
    -- of its own shows the whole line on hover while it is cut. Call after
    -- those controls are built.
    local function LiveLabel(region, prefix, valueFn)
        if EllesmereUI._prebuilding then return end
        local label = region and region._label
        if not label then return end
        local bound = region._lastInline or region._control
        if bound then
            label:SetPoint("RIGHT", bound, "LEFT", -12, 0)
        else
            label:SetPoint("RIGHT", region, "RIGHT", -20, 0)
        end
        local function Update()
            label:SetText(prefix .. "  " .. valueFn())
            region._labelTruncated = label:IsTruncated()
        end
        Update()
        EllesmereUI.RegisterWidgetRefresh(Update)
        if not region._labelHasHit then
            local hit = CreateFrame("Frame", nil, region)
            hit:SetPoint("TOPLEFT", label, "TOPLEFT", -5, 5)
            hit:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", 5, -5)
            hit:SetMouseClickEnabled(false)
            hit:SetScript("OnEnter", function()
                if label:IsTruncated() then EllesmereUI.ShowWidgetTooltip(label, label:GetText()) end
            end)
            hit:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            region._labelRevealHit = hit
        end
    end

    -- Compact button on a half-row. Inline controls chain right to left, so
    -- the first one built sits rightmost. tip shows while enabled, disabledTip
    -- (a sentence, or a function returning one) while disabled.
    local function InlineButton(region, text, onClick, tip, disabledFn, disabledTip)
        EllesmereUI.BuildInlineButton(region, text, onClick, {
            width = 58,
            tip = tip,
            disabled = disabledFn,
            disabledTooltip = disabledTip,
            rawTooltip = true,
        })
    end

    -- One frame, moved into each build of the page: its show and hide are the
    -- page's, so the module registers the events behind the live rows only
    -- while the page is on screen.
    local pageWatch
    local function WatchPage(parent)
        if EllesmereUI._prebuilding then return end
        if not pageWatch then
            pageWatch = CreateFrame("Frame")
            pageWatch._searchIgnore = true -- the inline search never hides it
            pageWatch:SetScript("OnShow", function() ns.SetPageShown(true) end)
            pageWatch:SetScript("OnHide", function() ns.SetPageShown(false) end)
        end
        pageWatch:Hide()
        pageWatch:SetParent(parent)
        pageWatch:Show()
    end

    ---------------------------------------------------------------------------
    --  Page
    ---------------------------------------------------------------------------
    local function BuildPage(pageName, parent, yOffset)
        local W  = EllesmereUI.Widgets
        local PP = EllesmereUI.PanelPP
        local y  = yOffset
        local _, h

        parent._showRowDivider = true
        EllesmereUI:ClearContentHeader()
        WatchPage(parent)

        local scopeName = ScopeLabel()

        -----------------------------------------------------------------------
        --  General: the master switch, what swaps on its own (timing on the
        --  cog), and the two ways a swap is announced
        -----------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "GENERAL", y); y = y - h

        local swapRow
        swapRow, h = W:DualRow(parent, y,
            { type = "toggle", text = "Enable Loadout Manager",
              tooltip = "Swaps gear and talents as you change content.",
              getValue = function() return DB().enabled end,
              setValue = function(v) ns.SetEnabled(v) Refresh() end },
            -- Placeholder for the checkbox dropdown built below: it gives the
            -- half its label, search entry and disabled label.
            { type = "dropdown", text = "Auto-Swap",
              tooltip = "Choose what swaps on its own.",
              values = { _placeholder = "..." }, order = { "_placeholder" },
              getValue = function() return "_placeholder" end,
              setValue = function() end,
              disabled = NotEnabled, disabledTooltip = "Loadout Manager" }
        ); y = y - h

        if not EllesmereUI._prebuilding then
            local rgn = swapRow._rightRegion
            if rgn._control then rgn._control:Hide() end
            local cbDD, cbRefresh = EllesmereUI.BuildVisOptsCBDropdown(rgn, 170, rgn:GetFrameLevel() + 2,
                {
                    { key = "gear",   label = "Gear Sets",       tooltip = "Equip the assigned gear set." },
                    { key = "talent", label = "Talent Loadouts", tooltip = "Load the assigned talent loadout." },
                },
                function(k) return DB()[k == "gear" and "gearEnabled" or "talentEnabled"] and true or false end,
                function(k, v) ns.SetChannelEnabled(k, v) end,
                nil, nil, nil, nil, nil, { disabled = NotEnabled, disabledTooltip = "Loadout Manager" })
            PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
            rgn._control = cbDD
            rgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(cbRefresh)

            EllesmereUI.BuildInlineCog(rgn, {
                title = "Auto-Swap",
                rows = {
                    { type = "toggle", label = "Queue In Combat",
                      tooltip = "Apply a swap due in combat once it ends.",
                      get = function() return DB().queueInCombat and true or false end,
                      set = function(v) ns.SetQueueInCombat(v) end },
                    { type = "toggle", label = "Re-Swap On Spec Change",
                      tooltip = "Swap again on a spec change in an instance.",
                      get = function() return DB().specSwap and true or false end,
                      set = function(v) DB().specSwap = v and true or false end },
                },
                disabled = NotEnabled, disabledTooltip = "Loadout Manager",
            })
        end

        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Talent-Change Warning",
              tooltip = "Show DON'T MOVE while talents change.",
              getValue = function() return DB().specWarning and true or false end,
              setValue = function(v) ns.SetSpecWarning(v) end },
            { type = "toggle", text = "Announce Swaps In Chat",
              getValue = function() return DB().announce and true or false end,
              setValue = function(v) DB().announce = v and true or false end }
        ); y = y - h

        -----------------------------------------------------------------------
        --  Current location: where you are and what applies here (live)
        -----------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "CURRENT LOCATION", y); y = y - h

        local whereRow
        whereRow, h = W:DualRow(parent, y,
            { type = "labeledButton", text = "Location", buttonText = "Check Now", width = 130,
              tooltip = "Check Now applies what is assigned here.",
              onClick = function() ns.CheckAndSwap() Refresh() end },
            { type = "label", text = "Specialization",
              tooltip = "Spec assignments win over All Specs." }
        ); y = y - h
        LiveLabel(whereRow._leftRegion, EllesmereUI.L("Location"), LocationText)
        LiveLabel(whereRow._rightRegion, EllesmereUI.L("Specialization"), function()
            local specID = ns.GetCurrentSpecID()
            return specID and Accent(ns.SpecName(specID)) or TXT_UNKNOWN
        end)

        local hereRow
        hereRow, h = W:DualRow(parent, y,
            { type = "label", text = "Gear Here",
              tooltip = "The gear set that applies here." },
            { type = "label", text = "Talents Here",
              tooltip = "The talent loadout that applies here." }
        ); y = y - h
        LiveLabel(hereRow._leftRegion, EllesmereUI.L("Gear Here"), function()
            local gear, level, key, scope = ns.ResolveGear(ns.GetContext())
            if not gear then return TXT_NOTHING_HERE end
            return Accent(gear) .. "  " .. SourceText(level, key, scope)
        end)
        LiveLabel(hereRow._rightRegion, EllesmereUI.L("Talents Here"), function()
            local talent, level, key, scope = ns.ResolveTalent(ns.GetContext())
            local name = ns.TalentDisplayName(talent)
            if not name then return TXT_NOTHING_HERE end
            return Accent(name) .. "  " .. SourceText(level, key, scope)
        end)

        -----------------------------------------------------------------------
        --  Selected loadout: what the Save buttons assign, and to which layer
        -----------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "SELECTED LOADOUT", y); y = y - h

        local gearValues, gearOrder, gearUpdate, gearAttach = LivePicker(
            DIM .. EllesmereUI.L("No gear set") .. "|r", GearEntries,
            { icon = function(key)
                  local icon = gearIcons[key]
                  if icon then return icon, 0.08, 0.92, 0.08, 0.92 end
              end })
        local talentValues, talentOrder, talentUpdate, talentAttach = LivePicker(
            DIM .. EllesmereUI.L("No talent loadout") .. "|r", TalentEntries)
        -- Both lists refill before their dropdowns repaint (refreshers run in
        -- registration order).
        EllesmereUI.RegisterWidgetRefresh(gearUpdate)
        EllesmereUI.RegisterWidgetRefresh(talentUpdate)

        -- A pick counts only while its list holds it: a renamed or deleted
        -- set, or a loadout of another spec, reads as no pick.
        local function GearPick()
            local name = ns.GetSelectedSet()
            if name ~= nil and gearValues[name] ~= nil then return name end
        end
        local function TalentPickKey()
            local sel = ns.GetSelectedTalent()
            local key = sel and tostring(sel.configID)
            if key and talentValues[key] ~= nil then return key end
        end
        -- The module saves talents only into All Specs or the current spec.
        local function TalentScopeOK()
            local scope = ns.GetScope()
            return scope == nil or scope == ns.GetCurrentSpecID()
        end
        local function HasSelection() return GearPick() ~= nil or TalentPickKey() ~= nil end
        local function CanSave()
            return GearPick() ~= nil or (TalentPickKey() ~= nil and TalentScopeOK())
        end
        local function SaveBlockedTip()
            if TalentPickKey() and not TalentScopeOK() then return TALENT_SCOPE end
            return PICK_FIRST
        end
        -- Drop a pick its list no longer holds before an action reads the
        -- module's selection.
        local function PrunePicks()
            gearUpdate()
            talentUpdate()
            if ns.GetSelectedSet() ~= nil and not GearPick() then ns.SetSelectedSet(nil) end
            if ns.GetSelectedTalent() ~= nil and not TalentPickKey() then ns.SetSelectedTalent(nil) end
        end

        local pickRow
        pickRow, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Gear Set", values = gearValues, order = gearOrder,
              tooltip = "The gear set the Save buttons assign.",
              getValue = function() return GearPick() or NONE end,
              setValue = function(v) ns.SetSelectedSet(v ~= NONE and v or nil) Refresh() end },
            { type = "dropdown", text = "Talent Loadout", values = talentValues, order = talentOrder,
              tooltip = "The talent loadout the Save buttons assign.",
              getValue = function() return TalentPickKey() or NONE end,
              setValue = SetSelectedTalentKey,
              disabled = function() return not TalentScopeOK() end,
              disabledTooltip = TALENT_SCOPE, rawTooltip = true }
        ); y = y - h
        gearAttach(pickRow._leftRegion._control)
        talentAttach(pickRow._rightRegion._control)

        EllesmereUI.BuildInlineCog(pickRow._leftRegion, {
            title = "Gear Sets",
            rows = {
                { type = "button", label = "Verify Assigned Sets", action = function() ns.Verify() end },
            },
        })

        local scopeRow
        do
            local values, order = ScopeValues()
            scopeRow, h = W:DualRow(parent, y,
                { type = "dropdown", text = "Assign For", values = values, order = order,
                  getValue = GetScopeKey, setValue = SetScopeKey,
                  tooltip = "Which specs the Save buttons apply to." },
                { type = "labeledButton", text = "Equip Selection", buttonText = "Equip Now", width = 130,
                  tooltip = "Equip the picked gear and talents now.",
                  onClick = function() PrunePicks() ns.EquipSelected() Refresh() end,
                  disabled = function() return not HasSelection() end,
                  disabledTooltip = PICK_FIRST, rawTooltip = true }
            ); y = y - h
        end

        -- Copy cog: one button per other layer. CopyScopeFrom replaces this
        -- layer outright, so the cog closes and a confirmation asks first.
        if not EllesmereUI._prebuilding then
            local current = ns.GetScope()
            local copyTitle = EllesmereUI.Lf("Copy Into %1$s", scopeName)
            local rows, cogShow = {}, nil
            local function AddCopy(sourceID, name)
                rows[#rows + 1] = { type = "button", label = EllesmereUI.Lf("Copy From %1$s", name),
                    action = function()
                        local pf = cogShow and cogShow._popupFrame
                        if pf and pf:IsShown() then pf:Hide() end
                        EllesmereUI:ShowConfirmPopup({
                            title       = copyTitle,
                            message     = EllesmereUI.Lf("Replace every %1$s assignment with a copy of the %2$s assignments?",
                                              scopeName, name),
                            confirmText = "Copy",
                            cancelText  = "Cancel",
                            onConfirm   = function()
                                ns.CopyScopeFrom(sourceID)
                                Refresh()
                            end,
                        })
                    end }
            end
            if current ~= nil then AddCopy(nil, ALL_SPECS_TEXT) end
            for _, spec in ipairs(ns.GetSpecList()) do
                if spec.id ~= current then AddCopy(spec.id, spec.name) end
            end
            if #rows > 0 then
                cogShow = select(2, EllesmereUI.BuildInlineCog(scopeRow._leftRegion, {
                    title = copyTitle,
                    minWidth = 220,
                    rows = rows,
                }))
            end
        end

        -----------------------------------------------------------------------
        --  Instances: this instance's two slots, each with Save and Clear,
        --  then every saved instance, which can be cleared from anywhere
        -----------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "INSTANCES", y); y = y - h

        -- The Save and Clear tips name the scope the buttons write to.
        local saveTip    = EllesmereUI.Lf("Save the picked loadout here for %1$s.", scopeName)
        local clearTip   = EllesmereUI.Lf("Clear what is saved here for %1$s.", scopeName)
        local nothingTip = EllesmereUI.Lf("Nothing saved here for %1$s.", scopeName)

        local instRow
        instRow, h = W:DualRow(parent, y,
            { type = "label", text = "Any Difficulty",
              tooltip = "This instance on any difficulty." },
            { type = "label", text = "This Difficulty",
              tooltip = "This instance on this difficulty only." }
        ); y = y - h

        for _, perDiff in ipairs({ false, true }) do
            local region = perDiff and instRow._rightRegion or instRow._leftRegion
            local function Inside() return (InstanceSlot(perDiff)) and true or false end
            local function Saved()
                local inside, g, t = InstanceSlot(perDiff)
                return inside and (g ~= nil or t ~= nil)
            end

            InlineButton(region, "Clear",
                function() ns.ClearCurrent(perDiff) Refresh() end,
                clearTip,
                function() return not Saved() end,
                function() return Inside() and nothingTip or NOT_IN_INSTANCE end)
            InlineButton(region, "Save",
                function() PrunePicks() ns.AssignCurrent(perDiff) Refresh() end,
                saveTip,
                function() return not Inside() or not CanSave() end,
                function() return Inside() and SaveBlockedTip() or NOT_IN_INSTANCE end)
            LiveLabel(region, perDiff and EllesmereUI.L("This Difficulty") or EllesmereUI.L("Any Difficulty"), function()
                local inside, g, t = InstanceSlot(perDiff)
                if not inside then return TXT_OUTSIDE end
                if perDiff then return Grey("(" .. DifficultyName() .. ")") .. "  " .. PairSummary(g, t) end
                return PairSummary(g, t)
            end)
        end

        -- The list refills before the dropdown repaints (refreshers run in
        -- registration order), so a cleared entry never shows as picked.
        local savedValues, savedOrder, savedUpdate, savedAttach = LivePicker(
            DIM .. EllesmereUI.L("Pick an instance") .. "|r", SavedEntries)
        EllesmereUI.RegisterWidgetRefresh(savedUpdate)

        local savedRow
        savedRow, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Saved Instances", values = savedValues, order = savedOrder,
              tooltip = EllesmereUI.Lf("Every instance saved for %1$s.", scopeName),
              getValue = function()
                  if pickedSaved and savedValues[pickedSaved] then return pickedSaved end
                  return NONE
              end,
              setValue = function(v) pickedSaved = (v ~= NONE) and v or nil Refresh() end },
            { type = "label", text = "Assignment",
              tooltip = "What the picked instance holds." }
        ); y = y - h
        savedAttach(savedRow._leftRegion._control)

        InlineButton(savedRow._rightRegion, "Clear",
            function()
                local e = PickedSavedEntry()
                pickedSaved = nil
                if e then ns.ClearInstanceAssignment(e.key) end
                Refresh()
            end,
            EllesmereUI.Lf("Clear the picked instance for %1$s.", scopeName),
            function() return PickedSavedEntry() == nil end,
            "Pick a saved instance first.")
        local nothingSaved = Grey(EllesmereUI.Lf("nothing saved for %1$s", scopeName))
        LiveLabel(savedRow._rightRegion, EllesmereUI.L("Assignment"), function()
            local e = PickedSavedEntry()
            if e then return PairSummary(e.gear, e.talent) end
            if #savedOrder <= 1 then return nothingSaved end
            return TXT_PICK_SAVED
        end)

        -----------------------------------------------------------------------
        --  Content type defaults: two per row, each with Save and Clear
        -----------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "CONTENT TYPE DEFAULTS", y); y = y - h

        local function TypeHalf(info)
            if not info then return EllesmereUI.BlankRowCfg() end
            return { type = "label", text = info.label, tooltip = TYPE_TIPS[info.key] }
        end

        -- A type's buttons write its default wherever you stand, so their tips
        -- name the type and the scope.
        local function TypeControls(region, info)
            local key = info.key
            local typeName = EllesmereUI.L(info.label)
            local function IsSet()
                local g, t = TypeSlot(key)
                return g ~= nil or t ~= nil
            end
            InlineButton(region, "Clear",
                function() ns.ClearType(key) Refresh() end,
                EllesmereUI.Lf("Clear the %1$s default for %2$s.", typeName, scopeName),
                function() return not IsSet() end,
                EllesmereUI.Lf("No %1$s default saved for %2$s.", typeName, scopeName))
            InlineButton(region, "Save",
                function() PrunePicks() ns.AssignType(key) Refresh() end,
                EllesmereUI.Lf("Save the picked loadout as the %1$s default for %2$s.", typeName, scopeName),
                function() return not CanSave() end,
                SaveBlockedTip)
            LiveLabel(region, typeName, function()
                local g, t = TypeSlot(key)
                return PairSummary(g, t)
            end)
        end

        for i = 1, #TYPE_LAYOUT, 2 do
            local left, right = TYPE_INFO[TYPE_LAYOUT[i]], TYPE_INFO[TYPE_LAYOUT[i + 1]]
            local row
            row, h = W:DualRow(parent, y, TypeHalf(left), TypeHalf(right)); y = y - h
            TypeControls(row._leftRegion, left)
            if right then TypeControls(row._rightRegion, right) end
        end

        _, h = W:Spacer(parent, y, 20); y = y - h

        parent:SetHeight(math.abs(y - yOffset))
        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Register the module
    ---------------------------------------------------------------------------
    EllesmereUI:RegisterModule(ADDON_NAME, {
        title       = PAGE_DISPLAY,
        description = "Applies gear sets and talent loadouts automatically per instance type and specialization.",
        pages       = { PAGE_DISPLAY },
        buildPage   = BuildPage,
        resetScope  = "character",
        onReset     = function() ns.ResetAll() end,
    })
end)
-- LoadOnDemand: this addon loads after PLAYER_LOGIN, so the event above will never fire; run the init now.
if IsLoggedIn() then initFrame:GetScript("OnEvent")(initFrame) end
