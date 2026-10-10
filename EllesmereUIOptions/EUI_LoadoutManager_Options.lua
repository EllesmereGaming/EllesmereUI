if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_LoadoutManager_Options.lua  --  Settings page for the Loadout Manager
--
--  The module owns the saved variables, the edit scope and the swap
--  machinery; this page drives it through the ns API. Status lines, summaries
--  and pickers are live widgets re-read on every page refresh. Only a change of
--  edit scope rebuilds the page, since headings and the copy cog name it.
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

    local PICK_FIRST      = "Pick a gear set or talent loadout under Selected Loadout first."
    local NOT_IN_INSTANCE = "Enter a dungeon, raid or other instance first."

    local function NotEnabled() return not DB().enabled end

    ---------------------------------------------------------------------------
    --  Text helpers
    ---------------------------------------------------------------------------
    local function Grey(text) return "|cff8c8c8c" .. tostring(text) .. "|r" end

    -- Assigned names in the suite accent, read on every call so a theme change
    -- lands with the next refresh.
    local function Accent(text)
        local c = EllesmereUI.ELLESMERE_GREEN
        return EllesmereUI.HexColor(c.r, c.g, c.b) .. tostring(text) .. "|r"
    end

    -- One assignment slot as "gear / talents", or "not set".
    local function PairSummary(gearName, talentStored)
        local talentName = ns.TalentDisplayName(talentStored)
        if not gearName and not talentName then return Grey("not set") end
        return (gearName and Accent(gearName) or Grey("no gear")) .. Grey(" / ") ..
               (talentName and Accent(talentName) or Grey("no talents"))
    end

    ---------------------------------------------------------------------------
    --  Content types, each specific type next to the one it outranks and Open
    --  World last (it applies on the way out)
    ---------------------------------------------------------------------------
    local TYPE_INFO = {}
    for _, info in ipairs(ns.INSTANCE_TYPE_ORDER) do TYPE_INFO[info.key] = info end

    local TYPE_LAYOUT = { "party", "mplus", "raid", "timewalking", "scenario", "delve", "arena", "pvp", "world" }

    local INSTANCE_KIND = {
        party = "Dungeon", raid = "Raid", scenario = "Scenario", arena = "Arena", pvp = "Battleground",
    }

    ---------------------------------------------------------------------------
    --  Scope helpers: "All Specs" plus one entry per specialization
    ---------------------------------------------------------------------------
    local ALL_SPECS = "all"

    local function ScopeValues()
        local values, order = { [ALL_SPECS] = "All Specs" }, { ALL_SPECS }
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
        Refresh(true) -- section headings and the copy cog name the scope
    end

    local function ScopeLabel()
        local scope = ns.GetScope()
        return scope and tostring(ns.SpecName(scope)) or "All Specs"
    end

    ---------------------------------------------------------------------------
    --  Pickers. Their value tables are refilled in place when the game's list
    --  changes and the cached menu is invalidated, so no rebuild is needed.
    ---------------------------------------------------------------------------
    local NONE = "__none__"

    local function HasSelection()
        return ns.GetSelectedSet() ~= nil or ns.GetSelectedTalent() ~= nil
    end

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
    local function LivePicker(noneText, entriesFn, menuOpts)
        -- Set and loadout names are the player's own: never run them through L().
        local values, order = { _noLoc = true }, {}
        if menuOpts then values._menuOpts = menuOpts end
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

    local function SelectedTalentKey()
        local sel = ns.GetSelectedTalent()
        return sel and tostring(sel.configID) or NONE
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
    --  Context readers for the live labels
    ---------------------------------------------------------------------------
    local function LocationText()
        local ctx = ns.GetContext()
        if not ctx.inInstance then
            local zone = GetRealZoneText()
            if not zone or zone == "" then zone = ctx.name end
            return tostring(zone) .. "  " .. Grey("open world")
        end
        local kind = INSTANCE_KIND[ctx.instanceType] or tostring(ctx.instanceType or "instance")
        if ctx.difficultyName and ctx.difficultyName ~= "" then
            kind = kind .. ", " .. ctx.difficultyName
        end
        return tostring(ctx.name) .. "  " .. Grey(kind)
    end

    -- The difficulty a per-difficulty assignment here covers. A running key
    -- reads as Mythic, the difficulty you enter at (the module stores it so).
    local function DifficultyName()
        local ctx = ns.GetContext()
        if not ctx.inInstance or not ctx.difficultyID then return "This Difficulty" end
        return ns.DifficultyName(ctx)
    end

    -- Where a resolved assignment comes from, e.g. "(Raid default, Holy)".
    local function SourceText(level, key, scope)
        local where
        if level == "difficulty" then
            where = "this instance, " .. DifficultyName() .. " only"
        elseif level == "instance" then
            where = "this instance"
        elseif level == "type" then
            local info = TYPE_INFO[key]
            where = (info and info.label or tostring(key)) .. " default"
        else
            return ""
        end
        return Grey("(" .. where .. ", " .. (scope and tostring(ns.SpecName(scope)) or "All Specs") .. ")")
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
    -- edited, wherever you are. The pick is the page's own state.
    local pickedSaved -- tostring(key) of the picked entry, or nil

    local function SavedEntries()
        local entries, sig = {}, {}
        for _, e in ipairs(ns.ListInstanceAssignments()) do
            local key = tostring(e.key)
            entries[#entries + 1] = { key = key, text = e.label }
            sig[#sig + 1] = key .. "=" .. e.label
        end
        return entries, table.concat(sig, "\n")
    end

    local function PickedSavedEntry()
        if not pickedSaved then return nil end
        for _, e in ipairs(ns.ListInstanceAssignments()) do
            if tostring(e.key) == pickedSaved then return e end
        end
        return nil
    end

    local function TypeSlot(key)
        local R = ns.ReadTables()
        return R.typeDefaults[key], R.talentTypeDefaults[key]
    end

    ---------------------------------------------------------------------------
    --  Widget helpers
    ---------------------------------------------------------------------------
    -- Point a half-row label at a text function re-run on every page refresh,
    -- anchored left of the half's inline controls so long text ellipsizes.
    -- Call after those controls are built.
    local function LiveLabel(region, textFn)
        local label = region and region._label
        if not label then return end
        local bound = region._lastInline or region._control
        if bound then
            label:SetPoint("RIGHT", bound, "LEFT", -12, 0)
        else
            label:SetPoint("RIGHT", region, "RIGHT", -20, 0)
        end
        local function Update()
            label:SetText(textFn())
            region._labelTruncated = label:IsTruncated()
        end
        Update()
        EllesmereUI.RegisterWidgetRefresh(Update)
    end

    -- Compact button on a half-row. Inline controls chain right to left, so
    -- the first one built sits rightmost. tip and disabledTip may be strings
    -- or functions; the tip shows while enabled, disabledTip while disabled.
    local function InlineButton(region, text, width, onClick, tip, disabledFn, disabledTip)
        local btn = EllesmereUI.BuildInlineButton(region, text, onClick, {
            width = width,
            disabled = disabledFn,
            disabledTooltip = disabledTip,
            rawTooltip = true,
        })
        if btn and tip then
            btn:HookScript("OnEnter", function(b)
                if disabledFn and disabledFn() then return end
                EllesmereUI.ShowWidgetTooltip(b, type(tip) == "function" and tip() or tip)
            end)
            btn:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        end
        return btn
    end

    -- Headings and the copy cog name the edit scope. If it moves while this
    -- page is cached (spec change, reset), the next refresh rebuilds it once.
    local rebuildQueued = false
    local function WatchScope(builtScope)
        if EllesmereUI._prebuilding then return end
        EllesmereUI.RegisterWidgetRefresh(function()
            if rebuildQueued or ns.GetScope() == builtScope then return end
            rebuildQueued = true
            C_Timer.After(0, function()
                rebuildQueued = false
                if EllesmereUI:GetActiveModule() ~= ADDON_NAME then return end
                Refresh(true)
            end)
        end)
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

        local scopeName = ScopeLabel()
        WatchScope(ns.GetScope())

        -----------------------------------------------------------------------
        --  General: the master switch, what swaps on its own (timing on the
        --  cog), and the two ways a swap is announced
        -----------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "GENERAL", y); y = y - h

        local swapRow
        swapRow, h = W:DualRow(parent, y,
            { type = "toggle", text = "Enable Loadout Manager",
              tooltip = "Master switch, off until you turn it on. While off the module registers no events at all; "
                     .. "Check Now and Equip Now still work on demand.",
              getValue = function() return DB().enabled end,
              setValue = function(v) ns.SetEnabled(v) Refresh() end },
            -- Placeholder for the checkbox dropdown built below. It keeps the
            -- half's label, search entry, and the disabled tooltip + click
            -- block over the control's footprint while the module is off.
            { type = "dropdown", text = "Auto-Swap",
              tooltip = "What changes on its own when you enter a new context. Check Now and Equip Now always apply both.",
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
                    { key = "gear",   label = "Gear Sets",
                      tooltip = "Equip the assigned Equipment Manager set when you enter a new context." },
                    { key = "talent", label = "Talent Loadouts",
                      tooltip = "Load the assigned talent loadout when you enter a new context." },
                },
                function(k) return DB()[k == "gear" and "gearEnabled" or "talentEnabled"] and true or false end,
                function(k, v) ns.SetChannelEnabled(k, v) end)
            PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
            rgn._control = cbDD
            rgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(cbRefresh)
            local function Dim() cbDD:SetAlpha(NotEnabled() and 0.3 or 1) end
            Dim()
            EllesmereUI.RegisterWidgetRefresh(Dim)

            EllesmereUI.BuildInlineCog(rgn, {
                title = "Auto-Swap",
                rows = {
                    { type = "toggle", label = "Queue In Combat",
                      tooltip = "If a swap is needed while you are in combat, hold it and apply it once combat ends.",
                      get = function() return DB().queueInCombat and true or false end,
                      set = function(v) ns.SetQueueInCombat(v) end },
                    { type = "toggle", label = "Re-Swap On Spec Change",
                      tooltip = "Changing specialization inside an instance re-runs the swap for the new spec.",
                      get = function() return DB().specSwap and true or false end,
                      set = function(v) DB().specSwap = v and true or false end },
                },
                disabled = NotEnabled, disabledTooltip = "Loadout Manager",
            })
        end

        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Talent-Change Warning",
              tooltip = "Show the centred DONT MOVE panel while a talent loadout is being applied.",
              getValue = function() return DB().specWarning and true or false end,
              setValue = function(v) ns.SetSpecWarning(v) end },
            { type = "toggle", text = "Announce Swaps In Chat",
              tooltip = "Print a chat line whenever gear or talents are applied.",
              getValue = function() return DB().announce and true or false end,
              setValue = function(v) DB().announce = v and true or false end }
        ); y = y - h

        -----------------------------------------------------------------------
        --  Current context: where you are and what applies here (live)
        -----------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "CURRENT CONTEXT", y); y = y - h

        local whereRow
        whereRow, h = W:DualRow(parent, y,
            { type = "labeledButton", text = "Location", buttonText = "Check Now", width = 130,
              tooltip = "Where you are standing. Check Now applies whatever is assigned for here, even while Loadout Manager is off.",
              onClick = function() ns.CheckAndSwap("manual") Refresh() end },
            { type = "label", text = "Specialization",
              tooltip = "Talent assignments resolve for this specialization first, then fall back to the All Specs layer." }
        ); y = y - h
        LiveLabel(whereRow._leftRegion, LocationText)
        LiveLabel(whereRow._rightRegion, function()
            local specID = ns.GetCurrentSpecID()
            return "Specialization  " .. (specID and Accent(ns.SpecName(specID)) or Grey("unknown"))
        end)

        local hereRow
        hereRow, h = W:DualRow(parent, y,
            { type = "label", text = "Gear Here",
              tooltip = "The Equipment Manager set that applies where you are, and the assignment it comes from." },
            { type = "label", text = "Talents Here",
              tooltip = "The talent loadout that applies where you are for your current specialization, and the assignment it comes from." }
        ); y = y - h
        LiveLabel(hereRow._leftRegion, function()
            local gear, level, key, scope = ns.ResolveGear(ns.GetContext())
            if not gear then return "Gear  " .. Grey("nothing assigned here") end
            return "Gear  " .. Accent(gear) .. "  " .. SourceText(level, key, scope)
        end)
        LiveLabel(hereRow._rightRegion, function()
            local talent, level, key, scope = ns.ResolveTalent(ns.GetContext())
            local name = ns.TalentDisplayName(talent)
            if not name then return "Talents  " .. Grey("nothing assigned here") end
            return "Talents  " .. Accent(name) .. "  " .. SourceText(level, key, scope)
        end)

        -----------------------------------------------------------------------
        --  Selected loadout: what the Save buttons assign, and to which layer
        -----------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "SELECTED LOADOUT", y); y = y - h

        local gearValues, gearOrder, gearUpdate, gearAttach = LivePicker(
            "|cff8c8c8cNo gear set|r", GearEntries,
            { icon = function(key)
                  local icon = gearIcons[key]
                  if icon then return icon, 0.08, 0.92, 0.08, 0.92 end
              end })
        local talentValues, talentOrder, talentUpdate, talentAttach = LivePicker(
            "|cff8c8c8cNo talent loadout|r", TalentEntries)

        local pickRow
        pickRow, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Gear Set", values = gearValues, order = gearOrder,
              tooltip = "The Equipment Manager set the Save buttons below assign.",
              getValue = function() return ns.GetSelectedSet() or NONE end,
              setValue = function(v) ns.SetSelectedSet(v ~= NONE and v or nil) Refresh() end },
            { type = "dropdown", text = "Talent Loadout", values = talentValues, order = talentOrder,
              tooltip = "The talent loadout the Save buttons below assign. Only loadouts belonging to your current specialization are listed.",
              getValue = SelectedTalentKey,
              setValue = SetSelectedTalentKey }
        ); y = y - h
        gearAttach(pickRow._leftRegion._control)
        talentAttach(pickRow._rightRegion._control)
        EllesmereUI.RegisterWidgetRefresh(gearUpdate)
        EllesmereUI.RegisterWidgetRefresh(talentUpdate)

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
                  tooltip = "Which layer the Save buttons below write to and show. All Specs applies to every "
                         .. "specialization; a spec overrides it for that spec only. The cog copies another layer "
                         .. "into this one, replacing everything it holds." },
                { type = "labeledButton", text = "Equip Selection", buttonText = "Equip Now", width = 130,
                  tooltip = "Apply the gear set and talent loadout picked above right now, ignoring the assignments.",
                  onClick = function() ns.EquipSelected() Refresh() end,
                  disabled = function() return not HasSelection() end,
                  disabledTooltip = PICK_FIRST, rawTooltip = true }
            ); y = y - h
        end

        -- Copy cog: one button per other layer. CopyScopeFrom replaces this
        -- layer outright, so the cog closes and a confirmation asks first.
        do
            local current = ns.GetScope()
            local rows, cogShow = {}, nil
            local function AddCopy(sourceID, name)
                rows[#rows + 1] = { type = "button", label = "Copy From " .. tostring(name),
                    action = function()
                        local pf = cogShow and cogShow._popupFrame
                        if pf and pf:IsShown() then pf:Hide() end
                        EllesmereUI:ShowConfirmPopup({
                            title       = "Copy Into " .. scopeName,
                            message     = "Replace every " .. scopeName .. " assignment with a copy of the "
                                       .. tostring(name) .. " assignments?",
                            confirmText = "Copy",
                            cancelText  = "Cancel",
                            onConfirm   = function()
                                ns.CopyScopeFrom(sourceID)
                                Refresh()
                            end,
                        })
                    end }
            end
            if current ~= nil then AddCopy(nil, "All Specs") end
            for _, spec in ipairs(ns.GetSpecList()) do
                if spec.id ~= current then AddCopy(spec.id, spec.name) end
            end
            if #rows > 0 then
                cogShow = select(2, EllesmereUI.BuildInlineCog(scopeRow._leftRegion, {
                    title = "Copy Into " .. scopeName,
                    minWidth = 220,
                    rows = rows,
                }))
            end
        end

        -----------------------------------------------------------------------
        --  Instances: this instance's two slots, each with Save and Clear,
        --  then every saved instance, which can be cleared from anywhere
        -----------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "INSTANCES  --  " .. string.upper(scopeName), y); y = y - h

        local instRow
        instRow, h = W:DualRow(parent, y,
            { type = "label", text = "Any Difficulty",
              tooltip = "This instance on every difficulty, for " .. scopeName .. ". Beats the content type defaults." },
            { type = "label", text = "This Difficulty",
              tooltip = "This instance on the difficulty you are in now only, for " .. scopeName .. ". Beats every other assignment." }
        ); y = y - h

        for _, perDiff in ipairs({ false, true }) do
            local region = perDiff and instRow._rightRegion or instRow._leftRegion
            local function Inside() return (InstanceSlot(perDiff)) and true or false end
            local function Saved()
                local inside, g, t = InstanceSlot(perDiff)
                return inside and (g ~= nil or t ~= nil)
            end
            local function Which()
                return perDiff and (DifficultyName() .. " only") or "every difficulty"
            end

            InlineButton(region, "Clear", 58,
                function() ns.ClearCurrent(perDiff) Refresh() end,
                function() return "Remove this instance's " .. Which() .. " assignment for " .. scopeName .. "." end,
                function() return not Saved() end,
                function()
                    if not Inside() then return NOT_IN_INSTANCE end
                    return "Nothing saved here for " .. scopeName .. "."
                end)
            InlineButton(region, "Save", 58,
                function() ns.AssignCurrent(perDiff) Refresh() end,
                function() return "Save the selected loadout for this instance on " .. Which() .. ", for " .. scopeName .. "." end,
                function() return not Inside() or not HasSelection() end,
                function()
                    if not Inside() then return NOT_IN_INSTANCE end
                    return PICK_FIRST
                end)
            LiveLabel(region, function()
                local inside, g, t = InstanceSlot(perDiff)
                if not inside then
                    return (perDiff and "This Difficulty" or "Any Difficulty") .. "  " .. Grey("not in an instance")
                end
                return (perDiff and (DifficultyName() .. " Only") or "Any Difficulty") .. "  " .. PairSummary(g, t)
            end)
        end

        -- The list refills before the dropdown repaints (refreshers run in
        -- registration order), so a cleared entry never shows as picked.
        local savedValues, savedOrder, savedUpdate, savedAttach = LivePicker(
            "|cff8c8c8cPick an instance|r", SavedEntries)
        EllesmereUI.RegisterWidgetRefresh(savedUpdate)

        local savedRow
        savedRow, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Saved Instances", values = savedValues, order = savedOrder,
              tooltip = "Every instance assignment saved for " .. scopeName .. ", wherever you are. "
                     .. "Pick one to see what it holds or clear it.",
              getValue = function()
                  if pickedSaved and savedValues[pickedSaved] then return pickedSaved end
                  return NONE
              end,
              setValue = function(v) pickedSaved = (v ~= NONE) and v or nil Refresh() end },
            { type = "label", text = "Assignment",
              tooltip = "The gear set and talent loadout saved for the picked instance, for " .. scopeName .. "." }
        ); y = y - h
        savedAttach(savedRow._leftRegion._control)

        InlineButton(savedRow._rightRegion, "Clear", 58,
            function()
                local e = PickedSavedEntry()
                pickedSaved = nil
                if e then ns.ClearInstanceAssignment(e.key) end
                Refresh()
            end,
            function()
                local e = PickedSavedEntry()
                return "Remove " .. (e and e.label or "the picked instance") .. " for " .. scopeName .. "."
            end,
            function() return PickedSavedEntry() == nil end,
            "Pick a saved instance first.")
        LiveLabel(savedRow._rightRegion, function()
            local e = PickedSavedEntry()
            if e then return "Assignment  " .. PairSummary(e.gear, e.talent) end
            if #savedOrder <= 1 then return "Assignment  " .. Grey("nothing saved for " .. scopeName) end
            return "Assignment  " .. Grey("pick a saved instance")
        end)

        -----------------------------------------------------------------------
        --  Content type defaults: two per row, each with Save and Clear
        -----------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "CONTENT TYPE DEFAULTS  --  " .. string.upper(scopeName), y); y = y - h

        local function TypeHalf(info)
            if not info then return EllesmereUI.BlankRowCfg() end
            return { type = "label", text = info.label,
                     tooltip = (info.hint and (info.hint .. "\n\n") or "") ..
                               "Shown as gear set / talent loadout, for " .. scopeName .. "." }
        end

        local function TypeControls(region, info)
            local key = info.key
            local function IsSet()
                local g, t = TypeSlot(key)
                return g ~= nil or t ~= nil
            end
            InlineButton(region, "Clear", 58,
                function() ns.ClearType(key) Refresh() end,
                "Remove the " .. info.label .. " default for " .. scopeName .. ".",
                function() return not IsSet() end,
                "Nothing saved for " .. info.label .. " in " .. scopeName .. ".")
            InlineButton(region, "Save", 58,
                function() ns.AssignType(key) Refresh() end,
                "Save the selected loadout as the " .. info.label .. " default for " .. scopeName .. ".",
                function() return not HasSelection() end,
                PICK_FIRST)
            LiveLabel(region, function()
                local g, t = TypeSlot(key)
                return info.label .. "  " .. PairSummary(g, t)
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
        onReset     = function()
            if ns.ResetAll then ns.ResetAll() end
        end,
    })
end)
-- LoadOnDemand: this addon loads after PLAYER_LOGIN, so the event above will never fire; run the init now.
if IsLoggedIn() then initFrame:GetScript("OnEvent")(initFrame) end
