if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Settings page for the Loadout Manager. The module owns the saved variables,
--  context resolution and swap machinery; this is purely the surface and goes
--  through the ns API it publishes. The page holds no state of its own beyond
--  which spec scope is being edited, and even that lives on the module, so a
--  spec change while the page is open moves both.
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
        if EllesmereUI.RefreshPage then EllesmereUI:RefreshPage(force and true or nil) end
    end

    -- A swap, an assignment or a spec change on the module side repaints the
    -- page. RefreshPage is a no-op unless the panel is open and on a page, and
    -- the module only calls this when something actually changed, so the guard
    -- is just "are we the page currently selected".
    ns.OnStateChanged = function()
        if EllesmereUI.GetActiveModule and EllesmereUI:GetActiveModule() ~= ADDON_NAME then return end
        Refresh()
    end

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
        Refresh(true) -- section headings and every row summary follow the scope
    end

    local function ScopeLabel()
        local scope = ns.GetScope()
        return scope and tostring(ns.SpecName(scope)) or "All Specs"
    end

    ---------------------------------------------------------------------------
    --  Selection helpers for the two pickers
    ---------------------------------------------------------------------------
    local NONE = "__none__"

    local function GearValues()
        local values, order = { [NONE] = "|cff8c8c8cNo gear set|r" }, { NONE }
        for _, set in ipairs(ns.ListEquipmentSets()) do
            values[set.name] = set.name
            order[#order + 1] = set.name
        end
        return values, order
    end

    local function TalentValues()
        local values, order = { [NONE] = "|cff8c8c8cNo talent loadout|r" }, { NONE }
        for _, loadout in ipairs(ns.ListTalentLoadouts()) do
            local key = tostring(loadout.configID)
            values[key] = loadout.name
            order[#order + 1] = key
        end
        return values, order
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
    --  Page
    ---------------------------------------------------------------------------
    local function BuildPage(pageName, parent, yOffset)
        local W  = EllesmereUI.Widgets
        local y  = yOffset
        local _, h

        parent._showRowDivider = true
        if EllesmereUI.ClearContentHeader then EllesmereUI:ClearContentHeader() end

        local db = DB()

        -----------------------------------------------------------------------
        --  Status: where you are and what currently resolves for it
        -----------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "CURRENT CONTEXT", y); y = y - h

        do
            local ctx = ns.GetContext()
            local specID = ns.GetCurrentSpecID()
            local gear, _, _, gearScope = ns.ResolveGear(ctx)
            local talent, _, _, talentScope = ns.ResolveTalent(ctx)
            local talentName = ns.TalentDisplayName(talent)

            -- What would be applied here, and which layer it came from.
            local function Resolved(name, scope)
                if not name then return "|cff8c8c8cnothing assigned|r" end
                return name .. " |cff8c8c8c[" .. (scope and tostring(ns.SpecName(scope)) or "all specs") .. "]|r"
            end

            local where = ctx.inInstance
                and (tostring(ctx.name) .. "  |cff8c8c8c" .. tostring(ctx.instanceType) ..
                     ", " .. tostring(ctx.difficultyName or "?") .. ", ID " .. tostring(ctx.instanceID or "?") .. "|r")
                or (tostring(ctx.name) .. "  |cff8c8c8copen world|r")

            _, h = W:DualRow(parent, y,
                { type = "labeledButton", text = where, buttonText = "Check Now", width = 150,
                  tooltip = "Apply whatever resolves for where you are standing right now.",
                  onClick = function() ns.CheckAndSwap("manual") Refresh(true) end },
                { type = "labeledButton", text = (specID and tostring(ns.SpecName(specID)) or "Unknown spec"),
                  buttonText = "Equip Selected", width = 150,
                  tooltip = "Apply the gear set and talent loadout picked under Assign For, ignoring the assignments.",
                  onClick = function() ns.EquipSelected() Refresh(true) end }
            ); y = y - h

            _, h = W:DualRow(parent, y,
                { type = "labeledButton", text = "Gear here:  " .. Resolved(gear, gearScope),
                  buttonText = "Verify Sets", width = 150,
                  tooltip = "List any assignment pointing at an Equipment Manager set that no longer exists.",
                  onClick = function() ns.Verify() end },
                { type = "labeledButton", text = "Talents here:  " .. Resolved(talentName, talentScope),
                  buttonText = "Refresh", width = 150,
                  tooltip = "Re-read the current context and assignments.",
                  onClick = function() Refresh(true) end }
            ); y = y - h

            -- What currently resolves here, shown in the two button rows'
            -- labels above rather than as editable fields.
        end

        -----------------------------------------------------------------------
        --  Behaviour
        -----------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "BEHAVIOUR", y); y = y - h

        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Enabled",
              tooltip = "Master switch, off until you turn it on. While off the module registers no events at all; "
                     .. "Check Now and Equip Selected still work on demand.",
              getValue = function() return DB().enabled end,
              setValue = function(v) ns.SetEnabled(v) end },
            { type = "toggle", text = "Swap Gear",
              tooltip = "Apply the assigned Equipment Manager set when you enter a context.",
              getValue = function() return DB().gearEnabled end,
              setValue = function(v) DB().gearEnabled = v end }
        ); y = y - h

        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Swap Talents",
              tooltip = "Apply the assigned talent loadout when you enter a context.",
              getValue = function() return DB().talentEnabled end,
              setValue = function(v) DB().talentEnabled = v end },
            { type = "toggle", text = "Announce Swaps",
              tooltip = "Print a chat line whenever gear or talents are applied.",
              getValue = function() return DB().announce end,
              setValue = function(v) DB().announce = v end }
        ); y = y - h

        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Queue In Combat",
              tooltip = "If a swap is needed while you are in combat, hold it and apply it once combat ends.",
              getValue = function() return DB().queueInCombat end,
              setValue = function(v) DB().queueInCombat = v end },
            { type = "toggle", text = "Swap On Spec Change",
              tooltip = "Changing specialization inside an instance re-runs the swap for the new spec.",
              getValue = function() return DB().specSwap end,
              setValue = function(v) DB().specSwap = v end }
        ); y = y - h

        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Swap Delay", min = 0, max = 10, step = 1,
              tooltip = "Seconds to wait after entering a context before applying, so the zone has finished loading.",
              getValue = function() return DB().delay or 2 end,
              setValue = function(v) DB().delay = v end },
            { type = "toggle", text = "Spec-Change Warning",
              tooltip = "Show the centred DONT MOVE panel while a talent loadout is being applied.",
              getValue = function() return DB().specWarning end,
              setValue = function(v) DB().specWarning = v end }
        ); y = y - h

        -----------------------------------------------------------------------
        --  Assignment scope and the two pickers
        -----------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "ASSIGN FOR", y); y = y - h

        do
            local values, order = ScopeValues()
            _, h = W:Dropdown(parent, "Specialization Scope", y, values,
                GetScopeKey, SetScopeKey, order,
                "Which layer the assignments below are saved to. All Specs applies to every specialization; a spec scope overrides it for that spec only.")
            y = y - h
        end

        do
            local gearValues, gearOrder = GearValues()
            local talentValues, talentOrder = TalentValues()
            _, h = W:DualRow(parent, y,
                { type = "dropdown", text = "Gear Set", values = gearValues, order = gearOrder,
                  tooltip = "The Equipment Manager set used by the Save buttons below.",
                  getValue = function() return ns.GetSelectedSet() or NONE end,
                  setValue = function(v) ns.SetSelectedSet(v ~= NONE and v or nil) Refresh() end },
                { type = "dropdown", text = "Talent Loadout", values = talentValues, order = talentOrder,
                  tooltip = "The talent loadout used by the Save buttons below. Only loadouts belonging to your current specialization are listed.",
                  getValue = SelectedTalentKey,
                  setValue = SetSelectedTalentKey }
            ); y = y - h
        end

        _, h = W:DualRow(parent, y,
            { type = "labeledButton", text = "Copy Assignments", buttonText = "Copy From All Specs", width = 190,
              tooltip = "Copy every assignment from the All Specs layer into " .. ScopeLabel() ..
                        ". Talent entries belonging to other specs are skipped.",
              onClick = function() ns.CopyScopeFrom(nil) Refresh(true) end },
            { type = "labeledButton", text = "Apply Elsewhere", buttonText = "Copy From Current Spec", width = 190,
              tooltip = "Copy every assignment from your current specialization into " .. ScopeLabel() ..
                        ". Talent entries belonging to other specs are skipped.",
              onClick = function() ns.CopyScopeFrom(ns.GetCurrentSpecID()) Refresh(true) end }
        ); y = y - h

        -----------------------------------------------------------------------
        --  This instance
        -----------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "THIS INSTANCE", y); y = y - h

        _, h = W:DualRow(parent, y,
            { type = "button", text = "Save (Any Difficulty)", width = 220,
              onClick = function() ns.AssignCurrent(false) Refresh(true) end },
            { type = "button", text = "Save (This Difficulty)", width = 220,
              onClick = function() ns.AssignCurrent(true) Refresh(true) end }
        ); y = y - h

        _, h = W:DualRow(parent, y,
            { type = "button", text = "Clear (Any Difficulty)", width = 220,
              onClick = function() ns.ClearCurrent(false) Refresh(true) end },
            { type = "button", text = "Clear (This Difficulty)", width = 220,
              onClick = function() ns.ClearCurrent(true) Refresh(true) end }
        ); y = y - h

        -----------------------------------------------------------------------
        --  Type defaults -- one row per context, most specific first
        -----------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "TYPE DEFAULTS  --  " .. string.upper(ScopeLabel()), y); y = y - h

        do
            local R = ns.ReadTables()
            for _, info in ipairs(ns.INSTANCE_TYPE_ORDER) do
                local key = info.key
                local gearName = R.typeDefaults[key]
                local talentName = ns.TalentDisplayName(R.talentTypeDefaults[key])
                local summary
                if gearName or talentName then
                    summary = "G: " .. (gearName or "|cff8c8c8cnone|r") ..
                              "    T: " .. (talentName or "|cff8c8c8cnone|r")
                else
                    summary = "|cff8c8c8cnot assigned|r"
                end

                _, h = W:DualRow(parent, y,
                    { type = "labeledButton", text = info.label, buttonText = "Save", width = 120,
                      -- Only the types whose priority needs explaining carry a hint.
                      tooltip = (info.hint and (info.hint .. "\n\n") or "") ..
                                "Saves the gear set and talent loadout picked under Assign For as the " ..
                                info.label .. " default for " .. ScopeLabel() .. ".",
                      onClick = function() ns.AssignType(key) Refresh(true) end },
                    { type = "labeledButton", text = summary, buttonText = "Clear", width = 120,
                      tooltip = "Remove the " .. info.label .. " default for " .. ScopeLabel() .. ".",
                      onClick = function() ns.ClearType(key) Refresh(true) end }
                ); y = y - h
            end
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
