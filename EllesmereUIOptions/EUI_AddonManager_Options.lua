if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_AddonManager_Options.lua
--  The Addon Manager window: a window of its own, not a page of the options
--  panel. EllesmereUI.AddonManagerWindow(show) opens, closes or toggles it. What
--  the profile stores and how a character is brought in line live in
--  EllesmereUI_AddonManager.lua.
-------------------------------------------------------------------------------

-- Page reuse: frames this file builds go through the options frame pool
-- (EllesmereUI_FramePool.lua), which hands a kept page its previous build's
-- frames back reset to new; on any other parent it is the plain CreateFrame.
local CreateFrame = EllesmereUI._Pool.CreateFrame

local ROW_H = 28
local INDENT = 22
local PILL_W, BOX_W = 84, 18

-- Kept across the list's rebuilds (search, fold, character).
local state = { query = "", queryRaw = "", folded = {} }

local function Accent()
    local c = EllesmereUI.ELLESMERE_GREEN
    if c then return c.r, c.g, c.b end
    return 0.05, 0.82, 0.62
end

local function Font(parent, size, r, g, b, a)
    return EllesmereUI.MakeFont(parent, size, nil, r, g, b, a)
end

local function Border(parent, r, g, b, a)
    return EllesmereUI.MakeBorder(parent, r, g, b, a, EllesmereUI.PanelPP)
end

local function Tip(owner, text)
    EllesmereUI.ShowWidgetTooltip(owner, text, { anchor = "right" })
end

local function Untip()
    EllesmereUI.HideWidgetTooltip()
end

-- A square that fills with the accent when on.
local function Box(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(BOX_W, BOX_W)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    EllesmereUI.SolidTex(b, "BACKGROUND", 0.05, 0.05, 0.05, 0.9):SetAllPoints()
    b.border = Border(b, 1, 1, 1, 0.3)
    local r, g, bl = Accent()
    b.fill = EllesmereUI.SolidTex(b, "ARTWORK", r, g, bl, 1)
    b.fill:SetPoint("TOPLEFT", 4, -4)
    b.fill:SetPoint("BOTTOMRIGHT", -4, 4)
    b:SetScript("OnLeave", Untip)
    return b
end

-- on: filled. dim: shows a state the profile does not set. locked: cannot change.
local function SetBox(b, on, dim, locked)
    b.fill:SetShown(on and true or false)
    b.fill:SetAlpha(dim and 0.4 or 1)
    b.border:SetColor(1, 1, 1, dim and 0.16 or 0.45)
    b:SetEnabled(not locked)
end

-- The override cell: default / on / off.
local function Pill(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(PILL_W, 20)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    EllesmereUI.SolidTex(b, "BACKGROUND", 0.05, 0.05, 0.05, 0.9):SetAllPoints()
    b.border = Border(b, 1, 1, 1, 0.16)
    b.label = Font(b, 12, 1, 1, 1, 0.4)
    b.label:SetPoint("CENTER")
    b:SetScript("OnLeave", Untip)
    return b
end

local function SetPill(b, value, locked)
    if value == nil then
        b.label:SetText(EllesmereUI.L("Default"))
        b.label:SetTextColor(1, 1, 1, 0.4)
        b.border:SetColor(1, 1, 1, 0.16)
    elseif value then
        local r, g, bl = Accent()
        b.label:SetText(EllesmereUI.L("On"))
        b.label:SetTextColor(r, g, bl, 1)
        b.border:SetColor(r, g, bl, 0.8)
    else
        b.label:SetText(EllesmereUI.L("Off"))
        b.label:SetTextColor(1, 0.45, 0.45, 1)
        b.border:SetColor(1, 0.45, 0.45, 0.8)
    end
    b:SetEnabled(not locked)
end

local function FormatCpu(pct)
    if pct >= 1 then return string.format("%.0f%%", pct) end
    if pct >= 0.1 then return string.format("%.1f%%", pct) end
    if pct >= 0.01 then return string.format("%.2f%%", pct) end
    return "0%"
end

local function FormatMemory(kb)
    if kb > 1024 then return string.format("%.1f MB", kb / 1024) end
    return string.format("%.0f KB", kb)
end

-- What the game says of an addon this session: the text and its colour, nothing
-- when all is well or when it is simply off.
local function StatusOf(a)
    local reason = a.reason
    if a.loadable or not reason or reason == "DISABLED" then return nil end
    local text = _G["ADDON_" .. reason]
    if not text then return nil end
    if reason == "INTERFACE_VERSION" then return text, 1, 0.65, 0.25, 1 end
    if reason == "DEMAND_LOADED" or reason == "DEP_DEMAND_LOADED" then return text, 1, 1, 1, 0.4 end
    return text, 1, 0.4, 0.4, 1
end

-- The usage cells of a row, when the page shows them.
local function PaintUsage(row)
    if not row.cpu then return end
    local AM = EllesmereUI.AddonManager
    local a = row.entry.addon
    if a.loaded then
        local cpu = AM.Cpu(a.name)
        row.cpu:SetText(cpu and FormatCpu(cpu) or "-")
        row.mem:SetText(FormatMemory(AM.Memory(a.name)))
    else
        row.cpu:SetText("")
        row.mem:SetText("")
    end
end

local PAD = 12

-- The list of addons, built into page (a fresh frame under the window's scroll
-- child). host: Rebuild() redoes the list, RefreshApply() re-reads the Apply
-- button, pending is the line under the controls.
local function BuildList(page, host)
    local AM = EllesmereUI.AddonManager
    local parent = page
    local totalW = page:GetWidth() - PAD * 2
    local y = -4
    local store = AM.Store()
    local me = AM.CharKey()
    local sel, who = host.Selected()
    local showUsage = store.usage == true
    local rows = {}
    local update   -- repaints the rows and the pending line without a rebuild
    local OpenMoveMenu, OpenCategoryMenu
    local pendingText = host.pending

    -- Something changed: repaint, and let the Apply button re-read its state.
    local function Changed()
        update()
        host.RefreshApply()
    end


    -- Columns: centres from a row's left edge. To the left of the default
    -- column: the game's status, then CPU and memory when shown. The title
    -- takes what is left.
    local COL_CHAR = totalW - PILL_W / 2 - 8
    local COL_DEFAULT = COL_CHAR - PILL_W / 2 - 70
    local STATUS_W, CPU_W, MEM_W = 150, 60, 72
    local statusLeft = COL_DEFAULT - BOX_W / 2 - 14 - STATUS_W
    local cpuRight = statusLeft - 8
    local memRight = cpuRight - CPU_W - 6
    local titleRight = (showUsage and (memRight - MEM_W) or statusLeft) - 10

    -- Column headers
    y = y - 6
    local ha = Font(parent, 12, 1, 1, 1, 0.5)
    ha:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD + 12, y)
    ha:SetText(EllesmereUI.L("Addon"))
    local hs = Font(parent, 12, 1, 1, 1, 0.5)
    hs:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD + statusLeft, y)
    hs:SetText(EllesmereUI.L("Status"))
    if showUsage then
        local hc = Font(parent, 12, 1, 1, 1, 0.5)
        hc:SetPoint("TOPRIGHT", parent, "TOPLEFT", PAD + cpuRight, y)
        hc:SetText(EllesmereUI.L("CPU"))
        local hm = Font(parent, 12, 1, 1, 1, 0.5)
        hm:SetPoint("TOPRIGHT", parent, "TOPLEFT", PAD + memRight, y)
        hm:SetText(EllesmereUI.L("Memory"))
    end
    local function Header(text, centre)
        local fs = Font(parent, 12, 1, 1, 1, 0.5)
        fs:SetPoint("TOP", parent, "TOPLEFT", PAD + centre, y)
        fs:SetWidth(120)
        fs:SetText(text)
        return fs
    end
    Header(EllesmereUI.L("Default"), COL_DEFAULT)
    Header(who, COL_CHAR):SetTextColor(Accent())
    y = y - 22

    -- Dependencies, as the game's own list shows them
    local function DepTip(a, needed, sub)
        local lines = {}
        if a.notes and a.notes ~= "" then lines[#lines + 1] = a.notes end
        lines[#lines + 1] = "|cff999999" .. a.name .. "|r"
        local deps = { C_AddOns.GetAddOnDependencies(a.name) }
        if #deps > 0 then
            lines[#lines + 1] = EllesmereUI.Lf("Needs: %s", table.concat(deps, ", "))
        end
        if needed[a.name] then
            lines[#lines + 1] = EllesmereUI.Lf("Kept on for %s", needed[a.name])
        end
        if a.locked then lines[#lines + 1] = EllesmereUI.L("EllesmereUI itself always stays on.") end
        if not sub then lines[#lines + 1] = "|cff999999" .. EllesmereUI.L("Right-click to move it to a category.") .. "|r" end
        return table.concat(lines, "\n")
    end

    -- A context menu under a row, shared by the addon and category menus.
    local moveMenu = CreateFrame("Frame", nil, parent)
    moveMenu:SetFrameLevel(parent:GetFrameLevel() + 30)
    moveMenu:EnableMouse(true)
    EllesmereUI.SolidTex(moveMenu, "BACKGROUND", 0.077, 0.068, 0.058, 1):SetAllPoints()
    Border(moveMenu, 1, 1, 1, 0.3)
    moveMenu:Hide()
    local moveCatcher = CreateFrame("Button", nil, parent)
    moveCatcher:SetAllPoints(parent)
    moveCatcher:SetFrameLevel(parent:GetFrameLevel() + 25)
    moveCatcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    moveCatcher:SetScript("OnClick", function() moveMenu:Hide() end)
    moveCatcher:Hide()
    moveMenu:SetScript("OnShow", function() moveCatcher:Show() end)
    moveMenu:SetScript("OnHide", function() moveCatcher:Hide() end)

    -- items: { text, pick = function, current, dim }
    local function ShowMenu(anchor, items, xOff)
        moveMenu.items = moveMenu.items or {}
        for _, b in ipairs(moveMenu.items) do b:Hide() end
        local r, g, bl = Accent()
        for i, it in ipairs(items) do
            local b = moveMenu.items[i]
            if not b then
                b = CreateFrame("Button", nil, moveMenu)
                b:SetSize(240, 26)
                b:SetPoint("TOPLEFT", moveMenu, "TOPLEFT", 0, -(i - 1) * 26)
                b.hl = EllesmereUI.SolidTex(b, "HIGHLIGHT", 1, 1, 1, 0.08)
                b.hl:SetAllPoints()
                b.text = Font(b, 13, 1, 1, 1, 1)
                b.text:SetPoint("LEFT", 10, 0)
                b.text:SetPoint("RIGHT", -10, 0)
                b.text:SetJustifyH("LEFT")
                b.text:SetWordWrap(false)
                b:SetScript("OnClick", function(self)
                    moveMenu:Hide()
                    self.item.pick()
                end)
                moveMenu.items[i] = b
            end
            b.item = it
            b.text:SetText(it.text)
            if it.current then
                b.text:SetTextColor(r, g, bl, 1)
            else
                b.text:SetTextColor(1, 1, 1, it.dim and 0.6 or 1)
            end
            b:Show()
        end
        moveMenu:SetSize(240, #items * 26)
        moveMenu:ClearAllPoints()
        moveMenu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", xOff, -2)
        moveMenu:Show()
    end

    -- Right-click on an addon: where to put it.
    OpenMoveMenu = function(row)
        local a = row.entry.addon
        local function Put(value)
            return function()
                AM.SetCategory(a.name, value)
                host.Rebuild()
            end
        end
        local items = {}
        for _, c in ipairs(AM.Categories()) do
            items[#items + 1] = { text = c, current = a.category == c, pick = Put(c) }
        end
        items[#items + 1] = { text = EllesmereUI.L("Uncategorized"), current = a.category == nil, pick = Put(false) }
        if store.catOf[a.name] ~= nil then
            items[#items + 1] = { text = EllesmereUI.L("As the addon declares it"), dim = true, pick = Put(nil) }
        end
        ShowMenu(row, items, 40)
    end

    -- Right-click on a category: all of its addons at once.
    OpenCategoryMenu = function(row)
        local addons = row.entry.addons
        local function Set(everyone, value)
            return function()
                if everyone then
                    AM.SetDefaults(addons, value)
                else
                    AM.SetOverrides(sel, addons, value)
                end
                Changed()
            end
        end
        ShowMenu(row, {
            { text = EllesmereUI.L("Default: all on"), pick = Set(true, true) },
            { text = EllesmereUI.L("Default: all off"), pick = Set(true, false) },
            { text = EllesmereUI.L("Default: stop managing"), dim = true, pick = Set(true, nil) },
            { text = EllesmereUI.Lf("%s: all on", who), pick = Set(false, true) },
            { text = EllesmereUI.Lf("%s: all off", who), pick = Set(false, false) },
            { text = EllesmereUI.Lf("%s: back to default", who), dim = true, pick = Set(false, nil) },
        }, 60)
    end

    -- One addon row. entry.members: a group's addons, for Shift-click.
    local function AddonRow(entry, i)
        local row = CreateFrame("Frame", nil, parent)
        row:SetSize(totalW, ROW_H)
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, y)
        y = y - ROW_H
        row:EnableMouse(true)
        EllesmereUI.SolidTex(row, "BACKGROUND", 0, 0, 0, i % 2 == 0 and 0.22 or 0.1):SetAllPoints()
        row.entry = entry
        row.title = Font(row, 13, 1, 1, 1, 1)
        local indent = 12 + entry.depth * INDENT
        row.title:SetPoint("LEFT", indent, 0)
        row.title:SetWidth(titleRight - indent)
        row.title:SetJustifyH("LEFT")
        row.title:SetWordWrap(false)
        row.status = Font(row, 12, 1, 1, 1, 1)
        row.status:SetPoint("LEFT", row, "LEFT", statusLeft, 0)
        row.status:SetWidth(STATUS_W)
        row.status:SetJustifyH("LEFT")
        row.status:SetWordWrap(false)
        if showUsage then
            row.cpu = Font(row, 12, 1, 1, 1, 0.7)
            row.cpu:SetPoint("RIGHT", row, "LEFT", cpuRight, 0)
            row.cpu:SetWidth(CPU_W)
            row.cpu:SetJustifyH("RIGHT")
            row.mem = Font(row, 12, 1, 1, 1, 0.7)
            row.mem:SetPoint("RIGHT", row, "LEFT", memRight, 0)
            row.mem:SetWidth(MEM_W)
            row.mem:SetJustifyH("RIGHT")
        end
        row:SetScript("OnEnter", function(self)
            Tip(self.title, DepTip(self.entry.addon, self.needed or {}, self.entry.sub))
        end)
        row:SetScript("OnLeave", Untip)
        row:SetScript("OnMouseUp", function(self, button)
            if button == "RightButton" and not self.entry.sub then OpenMoveMenu(self) end
        end)

        -- Shift acts on the whole group, the addon and its sub-addons.
        local function Targets(self)
            local e = self:GetParent().entry
            if IsShiftKeyDown() and e.members then return e.members end
            return { e.addon }
        end

        row.box = Box(row)
        row.box:SetPoint("CENTER", row, "LEFT", COL_DEFAULT, 0)
        row.box:SetScript("OnClick", function(self, button)
            local a = self:GetParent().entry.addon
            if a.locked then return end
            local d = store.defaults[a.name]
            if d == nil then d = a.on end
            local v = nil
            if button ~= "RightButton" then v = not d end
            for _, t in ipairs(Targets(self)) do
                if not t.locked then AM.SetDefault(t.name, v) end
            end
            Changed()
        end)
        row.box:SetScript("OnEnter", function(self)
            Tip(self, EllesmereUI.L("Default for every character. Click to switch it, right-click to stop managing this addon. Shift acts on the whole group."))
        end)

        row.pill = Pill(row)
        row.pill:SetPoint("CENTER", row, "LEFT", COL_CHAR, 0)
        row.pill:SetScript("OnClick", function(self, button)
            local a = self:GetParent().entry.addon
            if a.locked then return end
            local c = store.chars[sel]
            local v = c and c.overrides and c.overrides[a.name]
            if button == "RightButton" then
                v = nil
            elseif v == nil then
                v = true
            elseif v then
                v = false
            else
                v = nil
            end
            for _, t in ipairs(Targets(self)) do
                if not t.locked then AM.SetOverride(sel, t.name, v) end
            end
            Changed()
        end)
        row.pill:SetScript("OnEnter", function(self)
            Tip(self, EllesmereUI.Lf("Override for %s. Click to cycle: default, on, off. Right-click for the default. Shift acts on the whole group.", sel))
        end)
        return row
    end

    -- A category: folds the addons it holds.
    local function CategoryRow(entry)
        local row = CreateFrame("Button", nil, parent)
        row:SetSize(totalW, ROW_H)
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, y)
        y = y - ROW_H
        local r, g, b = Accent()
        EllesmereUI.SolidTex(row, "BACKGROUND", r, g, b, 0.1):SetAllPoints()
        row.hl = EllesmereUI.SolidTex(row, "HIGHLIGHT", 1, 1, 1, 0.05)
        row.hl:SetAllPoints()
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row.entry = entry
        local mark = Font(row, 13, r, g, b, 1)
        mark:SetPoint("LEFT", 12, 0)
        mark:SetText(entry.folded and ">" or "v")
        local label = Font(row, 13, r, g, b, 1)
        label:SetPoint("LEFT", 30, 0)
        label:SetText(entry.name .. " (" .. entry.count .. ")")
        row:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                OpenCategoryMenu(self)
                return
            end
            state.folded[entry.key] = (not entry.folded) or nil
            host.Rebuild()
        end)
        row:SetScript("OnEnter", function(self)
            Tip(self, EllesmereUI.L("Click to fold. Right-click to switch all of its addons on or off."))
        end)
        row:SetScript("OnLeave", Untip)
        if entry.user then
            local del = CreateFrame("Button", nil, row)
            del:SetSize(80, 20)
            del:SetPoint("RIGHT", -8, 0)
            EllesmereUI.MakeStyledButton(del, "Remove", 11, EllesmereUI.RB_COLOURS, function()
                EllesmereUI:ShowConfirmPopup({
                    title = EllesmereUI.L("Remove the category"),
                    message = EllesmereUI.Lf("Remove the category %s? Its addons go back to the category they declare.", entry.name),
                    confirmText = EllesmereUI.L("Remove"),
                    cancelText = EllesmereUI.L("Cancel"),
                    onConfirm = function()
                        AM.RemoveCategory(entry.name)
                        host.Rebuild()
                    end,
                })
            end)
        end
        return row
    end

    local tree = AM.Tree(AM.List(), state.folded, state.query)
    local n = 0
    for _, entry in ipairs(tree) do
        if entry.kind == "category" then
            CategoryRow(entry)
        else
            n = n + 1
            rows[#rows + 1] = AddonRow(entry, n)
        end
    end

    local function Paint(row, a, needed)
        local d = store.defaults[a.name]
        local c = store.chars[sel]
        local o = c and c.overrides and c.overrides[a.name]
        -- The state this character will have once the profile is applied (for
        -- the character on screen when it is not this one: what it will want).
        local shown = a.on
        if o ~= nil then
            shown = o
        elseif d ~= nil then
            shown = d
        end
        if needed[a.name] then shown = true end
        local mark = ""
        if sel == me then
            local want = AM.Wanted(a.name, me)
            if needed[a.name] then want = true end
            if want ~= nil and want ~= a.on then
                mark = " " .. EllesmereUI.HexColor(Accent()) .. "*|r"
            end
        end
        row.needed = needed
        local status, sr, sg, sb, sa = StatusOf(a)
        row.status:SetText(status or "")
        if status then row.status:SetTextColor(sr, sg, sb, sa) end
        row.title:SetText(a.title .. mark)
        row.title:SetTextColor(1, 1, 1, shown and 0.95 or 0.4)
        SetBox(row.box, a.locked or (d == nil and a.on) or d == true, d == nil and not a.locked, a.locked)
        SetPill(row.pill, o, a.locked)
    end

    function update()
        local byName = {}
        for _, a in ipairs(AM.List()) do byName[a.name] = a end
        local needed = AM.Needed(sel)
        if showUsage then AM.RefreshMemory() end
        for _, row in ipairs(rows) do
            local a = byName[row.entry.addon.name]
            row.entry.addon = a
            Paint(row, a, needed)
            PaintUsage(row)
        end
        local pending = #AM.Pending()
        if sel ~= me then
            pendingText:SetText(EllesmereUI.Lf("%s is brought in line when it logs in.", who))
        elseif pending > 0 then
            pendingText:SetText(EllesmereUI.Lf("%d changes to apply on this character.", pending))
        else
            pendingText:SetText(EllesmereUI.L("This character matches the profile."))
        end
    end
    update()

    return math.abs(y) + 20

end

-------------------------------------------------------------------------------
--  The window
-------------------------------------------------------------------------------
local WIN_W, WIN_H = 820, 660
local win

local function Selected()
    local AM = EllesmereUI.AddonManager
    local me = AM.CharKey()
    local chars = AM.Characters()
    local sel = state.sel
    local known = false
    for _, key in ipairs(chars) do
        if key == sel then known = true end
    end
    if not known then sel = me end
    state.sel = sel
    return sel, sel:match("^(.-) %- ") or sel, chars
end

local function CreateWindow()
    local AM = EllesmereUI.AddonManager
    local f = CreateFrame("Frame", "EllesmereUIAddonManagerWindow", UIParent)
    f:SetSize(WIN_W, WIN_H)
    f:SetPoint("CENTER")
    -- Below the DIALOG strata the options popups, menus and dropdowns sit in, and not
    -- "toplevel": a click would raise the window over the popup it just opened.
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:Hide()
    EllesmereUI.SolidTex(f, "BACKGROUND", 0.077, 0.068, 0.058, 0.98):SetAllPoints()
    Border(f, 1, 1, 1, 0.15)
    local lvl = f:GetFrameLevel()

    -- Title bar: drag to move.
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("TOPRIGHT")
    bar:SetHeight(36)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() f:StartMoving() end)
    bar:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    local title = Font(bar, 16, 1, 1, 1, 1)
    title:SetPoint("LEFT", 16, 0)
    title:SetText(EllesmereUI.L("Addon Manager"))
    local close = CreateFrame("Button", nil, bar)
    close:SetSize(26, 22)
    close:SetPoint("RIGHT", -8, 0)
    EllesmereUI.MakeStyledButton(close, "X", 12, EllesmereUI.RB_COLOURS, function() f:Hide() end)
    local line = EllesmereUI.SolidTex(f, "BORDER", 1, 1, 1, 0.08)
    line:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -36)
    line:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -36)
    line:SetHeight(1)

    -- The switch, with the cog that holds the settings and the occasional actions.
    local function Enabled()
        local s = AM.Store()
        return s ~= nil and s.enabled == true
    end
    local function Store() return AM.Store() end
    local toggle, applyVisual, snapToState
    toggle, applyVisual, snapToState = EllesmereUI.BuildToggleControl(f, lvl + 3, Enabled, function(v)
        AM.SetEnabled(v)
        f.Rebuild()
    end)
    toggle:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -48)
    local enableLabel = Font(f, 13, 1, 1, 1, 1)
    enableLabel:SetPoint("LEFT", toggle, "RIGHT", 10, 0)
    enableLabel:SetText(EllesmereUI.L("Enable Addon Manager"))

    local cogRows = {
        { type = "toggle", label = "Open from the game menu",
          tooltip = "The game menu's AddOns button opens this window instead of the game's AddOn list. Out of combat only.",
          get = function() local s = Store(); return s ~= nil and s.menu == true end,
          set = function(v)
              local s = Store(); if not s then return end
              s.menu = v or nil
              if v then AM.HookMenu() end
          end },
        { type = "toggle", label = "Offer to apply at login",
          tooltip = "When a character differs from the profile at login, offers to apply the changes and reload.",
          get = function() local s = Store(); return s ~= nil and not s.quiet end,
          set = function(v) local s = Store(); if s then s.quiet = (not v) or nil end end },
        { type = "toggle", label = "Show CPU and memory use",
          tooltip = "Adds CPU and memory columns for the addons that are loaded.",
          get = function() local s = Store(); return s ~= nil and s.usage == true end,
          set = function(v)
              local s = Store(); if not s then return end
              s.usage = v or nil
              f.Rebuild()
          end },
        { type = "button", label = "Add a Category",
          action = function()
              EllesmereUI:ShowInputPopup({
                  title = EllesmereUI.L("Add a Category"),
                  message = EllesmereUI.L("Name of the category. Right-click an addon to put it in one."),
                  placeholder = EllesmereUI.L("Category name"),
                  confirmText = EllesmereUI.L("Add"),
                  onConfirm = function(text)
                      if AM.AddCategory(text) then
                          f.Rebuild()
                      else
                          UIErrorsFrame:AddMessage(EllesmereUI.L("That category already exists."), 1, 0.3, 0.3)
                      end
                  end,
              })
          end },
        { type = "button", label = "Defaults From This Character",
          action = function()
              EllesmereUI:ShowConfirmPopup({
                  title = EllesmereUI.L("Defaults From This Character"),
                  message = EllesmereUI.L("Makes the addons that are on for this character the default for every character."),
                  confirmText = EllesmereUI.L("Replace"),
                  cancelText = EllesmereUI.L("Cancel"),
                  onConfirm = function()
                      AM.DefaultsFromThisCharacter()
                      f.Rebuild()
                  end,
              })
          end },
        { type = "button", label = "Blizzard AddOn Menu",
          action = function() AM.ShowBlizzardList() end },
        { type = "button", label = "Refresh Usage",
          hidden = function() local s = Store(); return not (s and s.usage) end,
          action = function()
              AM.RefreshMemory(true)
              f.Rebuild()
          end },
    }
    local cog = EllesmereUI.BuildInlineCog(f, { title = "Addon Manager", rows = cogRows,
        anchorTo = enableLabel, relPoint = "RIGHT", gap = -34, chain = false })

    -- Character: a dropdown made again at each build (characters come and go).
    local ddHolder = CreateFrame("Frame", nil, f)
    ddHolder:SetSize(300, 26)
    ddHolder:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -47)
    local charLabel = Font(f, 13, 1, 1, 1, 0.6)
    charLabel:SetPoint("RIGHT", ddHolder, "LEFT", -10, 0)
    charLabel:SetText(EllesmereUI.L("Character"))

    -- Search and Apply.
    local box = CreateFrame("EditBox", nil, f)
    box:SetSize(300, 26)
    box:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -86)
    box:SetAutoFocus(false)
    box:SetTextInsets(8, 8, 0, 0)
    local face, _, flags = Font(f, 13, 1, 1, 1, 1):GetFont()
    box:SetFont(face, 13, flags)
    box:SetTextColor(1, 1, 1, 1)
    EllesmereUI.SolidTex(box, "BACKGROUND", 0.05, 0.05, 0.05, 0.9):SetAllPoints()
    Border(box, 1, 1, 1, 0.2)
    local hint = Font(box, 13, 1, 1, 1, 0.35)
    hint:SetPoint("LEFT", 8, 0)
    hint:SetText(EllesmereUI.L("Search addons"))
    box:SetScript("OnTextChanged", function(self, user)
        hint:SetShown(self:GetText() == "")
        if not user then return end
        local text = self:GetText()
        if text == state.queryRaw then return end
        state.queryRaw = text
        state.query = text:lower()
        -- One rebuild for a burst of typing.
        local stamp = (self._stamp or 0) + 1
        self._stamp = stamp
        C_Timer.After(0.25, function()
            if self._stamp == stamp then f.Rebuild(true) end
        end)
    end)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    box:SetScript("OnEnterPressed", box.ClearFocus)

    local apply = CreateFrame("Button", nil, f)
    apply:SetSize(220, 26)
    apply:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -86)
    EllesmereUI.MakeStyledButton(apply, "Apply and Reload", 12, EllesmereUI.RB_COLOURS, function()
        if InCombatLockdown() or #AM.Pending() == 0 then return end
        EllesmereUI.RequestReload(nil, nil, AM.ApplyNative)
    end)
    function f.RefreshApply()
        local ok = AM.Store() ~= nil and not InCombatLockdown() and #AM.Pending() > 0
        apply:SetEnabled(ok)
        apply:SetAlpha(ok and 1 or 0.4)
    end

    local pending = Font(f, 12, 1, 1, 1, 0.5)
    pending:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -122)

    -- The list: a scroll frame, one fresh page per build.
    local sf = CreateFrame("ScrollFrame", nil, f)
    sf:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -146)
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 10)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(WIN_W - 4 - 10, 10)
    sf:SetScrollChild(content)
    local updateThumb = EllesmereUI.AttachSmoothScrollbar(sf, { child = content, step = 56 })
    local off = Font(f, 13, 1, 1, 1, 0.5)
    off:SetPoint("TOP", sf, "TOP", 0, -40)
    off:SetText(EllesmereUI.L("The Addon Manager is off. Switch it on above."))

    local host = {
        pending = pending,
        Selected = Selected,
        RefreshApply = function() f.RefreshApply() end,
        Rebuild = function() f.Rebuild(true) end,
    }
    local page, dd
    -- keepSearch: the search box already holds the text (a rebuild it asked for).
    function f.Rebuild(keepSearch)
        local on = Enabled()
        snapToState()
        cog:SetShown(on); box:SetShown(on); apply:SetShown(on); pending:SetShown(on)
        charLabel:SetShown(on); ddHolder:SetShown(on); off:SetShown(not on)
        if dd then dd:Hide(); dd:SetParent(nil); dd = nil end
        if page then page:Hide(); page:SetParent(nil); page = nil end
        if not on then
            content:SetHeight(10)
            pending:SetText("")
            f.RefreshApply()
            return
        end
        local _, _, chars = Selected()
        local values = {}
        for _, key in ipairs(chars) do values[key] = key end
        dd = EllesmereUI.BuildDropdownControl(f, 300, lvl + 3, values, chars,
            function() return state.sel end,
            function(key)
                state.sel = key
                f.Rebuild(true)
            end)
        dd:SetPoint("TOPRIGHT", ddHolder, "TOPRIGHT", 0, 0)
        if keepSearch ~= true then box:SetText(state.queryRaw or "") end
        local keep = sf:GetVerticalScroll()
        page = CreateFrame("Frame", nil, content)
        page:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
        page:SetSize(content:GetWidth(), 10)
        local h = BuildList(page, host)
        page:SetHeight(h)
        content:SetHeight(h)
        sf:SetVerticalScroll(math.min(keep, math.max(0, h - sf:GetHeight())))
        if updateThumb then updateThumb() end
        f.RefreshApply()
    end

    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function(self) self.RefreshApply() end)
    f:SetScript("OnShow", function(self)
        self:Raise()
        self.Rebuild()
    end)
    EllesmereUI.RegisterEscapeClose(f)
    return f
end

-- show: true opens, false closes, nil toggles.
function EllesmereUI.AddonManagerWindow(show)
    if not win then win = CreateWindow() end
    if show == nil then show = not win:IsShown() end
    if show then
        if win:IsShown() then
            win:Raise()
            win.Rebuild()
        else
            win:Show()
        end
    else
        win:Hide()
    end
end
