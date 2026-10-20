if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_AddonManager_Options.lua
--  Builds the Addon Manager page (module _EUIAddonManager). What the profile
--  stores and how a character is brought in line live in
--  EllesmereUI_AddonManager.lua.
-------------------------------------------------------------------------------

-- Page reuse: frames this file builds go through the options frame pool
-- (EllesmereUI_FramePool.lua), which hands a kept page its previous build's
-- frames back reset to new; on any other parent it is the plain CreateFrame.
local CreateFrame = EllesmereUI._Pool.CreateFrame

local ROW_H = 28
local INDENT = 22
local PILL_W, BOX_W = 84, 18

-- Kept across the page's rebuilds (search, fold, character).
local state = { query = "", folded = {}, refocus = false }

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

-- A flat button; primary ones carry the accent.
local function Button(parent, text, w, h, primary)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    EllesmereUI.SolidTex(b, "BACKGROUND", 0.077, 0.068, 0.058, 0.92):SetAllPoints()
    local r, g, bl = 1, 1, 1
    if primary then r, g, bl = Accent() end
    b._r, b._g, b._b, b._primary = r, g, bl, primary
    b.border = Border(b, r, g, bl, primary and 0.9 or 0.3)
    b.label = Font(b, 13, r, g, bl, primary and 0.95 or 0.7)
    b.label:SetPoint("CENTER")
    b.label:SetText(text)
    b:SetScript("OnEnter", function(self)
        if self:IsEnabled() then
            self.label:SetAlpha(1)
            self.border:SetColor(self._r, self._g, self._b, 1)
        end
        if self.tip then Tip(self, self.tip) end
    end)
    b:SetScript("OnLeave", function(self)
        Untip()
        if self:IsEnabled() then
            self.label:SetAlpha(self._primary and 0.95 or 0.7)
            self.border:SetColor(self._r, self._g, self._b, self._primary and 0.9 or 0.3)
        end
    end)
    return b
end

local function SetButtonOn(b, on)
    b:SetEnabled(on)
    b.label:SetAlpha(on and (b._primary and 0.95 or 0.7) or 0.3)
    b.border:SetColor(b._r, b._g, b._b, on and (b._primary and 0.9 or 0.3) or 0.12)
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

-- A labelled box that flips a setting.
local function Check(parent, label, get, set)
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(420, 20)
    local box = Box(c)
    box:SetPoint("LEFT")
    local text = Font(c, 13, 1, 1, 1, 0.8)
    text:SetPoint("LEFT", box, "RIGHT", 10, 0)
    text:SetText(label)
    box:SetScript("OnClick", function()
        set(not get())
        SetBox(box, get())
    end)
    SetBox(box, get())
    return c
end

local function CharLabel(key)
    local AM = EllesmereUI.AddonManager
    local c = AM.Store() and AM.Store().chars[key]
    local color = c and c.class and C_ClassColor.GetClassColor(c.class)
    return color and color:WrapTextInColorCode(key) or key
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
    local a = row.entry.addon
    if a.loaded then
        local cpu = EllesmereUI.AddonManager.Cpu(a.name)
        row.cpu:SetText(cpu and FormatCpu(cpu) or "-")
        row.mem:SetText(FormatMemory(EllesmereUI.AddonManager.Memory(a.name)))
    else
        row.cpu:SetText("")
        row.mem:SetText("")
    end
end

function EllesmereUI._BuildAddonManagerPage(pageName, parent, yOffset)
    -- Nothing here is searchable, so the search index pass builds none of it.
    if EllesmereUI._prebuilding then return 0 end
    parent._showRowDivider = nil

    local AM = EllesmereUI.AddonManager
    local PAD = EllesmereUI.CONTENT_PAD
    local totalW = parent:GetWidth() - PAD * 2
    local me = AM.CharKey()
    local store = AM.Store(true)
    local known = false
    for _, key in ipairs(AM.Characters()) do
        if key == state.sel then known = true end
    end
    if not known then state.sel = me end
    local sel = state.sel
    -- Columns: centres from a row's left edge.
    local COL_CHAR = totalW - PILL_W / 2 - 8
    local COL_DEFAULT = COL_CHAR - PILL_W / 2 - 70
    -- To the left of the default column: the game's status, then CPU and memory
    -- when the page shows them. The title takes what is left.
    local showUsage = store.usage == true
    local STATUS_W, CPU_W, MEM_W = 150, 60, 72
    local statusLeft = COL_DEFAULT - BOX_W / 2 - 14 - STATUS_W
    local cpuRight = statusLeft - 8
    local memRight = cpuRight - CPU_W - 6
    local titleRight = (showUsage and (memRight - MEM_W) or statusLeft) - 10

    local y = yOffset - 14
    local rows = {}
    local update   -- repaints the rows and the Apply button without a rebuild
    local OpenMoveMenu, OpenCategoryMenu

    local sub = Font(parent, 12, 1, 1, 1, 0.5)
    sub:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, y)
    sub:SetText(EllesmereUI.L("Defaults apply to every character. An override changes one addon on one character."))
    y = y - 30

    -- Actions
    local x = 0
    local function Place(btn, w)
        if x > 0 and x + w > totalW then
            x = 0
            y = y - 38
        end
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD + x, y)
        x = x + w + 8
    end

    local apply = Button(parent, EllesmereUI.L("Apply and Reload"), 190, 30, true)
    apply:SetScript("OnClick", function()
        if InCombatLockdown() or #AM.Pending() == 0 then return end
        EllesmereUI.RequestReload(nil, nil, AM.ApplyNative)
    end)
    apply.tip = EllesmereUI.L("Applies to this character. The other characters are offered theirs when they log in.")
    Place(apply, 190)

    local blizz = Button(parent, EllesmereUI.L("Blizzard AddOn Menu"), 190, 30)
    blizz:SetScript("OnClick", function() AM.ShowBlizzardList() end)
    Place(blizz, 190)

    -- Sets the defaults from this character: asks twice, as it replaces them all.
    local snap = Button(parent, EllesmereUI.L("Defaults From This Character"), 230, 30)
    snap:SetScript("OnClick", function(self)
        if self.armed then
            self.armed = nil
            self.label:SetText(EllesmereUI.L("Defaults From This Character"))
            AM.DefaultsFromThisCharacter()
            update()
            return
        end
        self.armed = true
        self.label:SetText(EllesmereUI.L("Click again to confirm"))
        C_Timer.After(3, function()
            if self.armed then
                self.armed = nil
                self.label:SetText(EllesmereUI.L("Defaults From This Character"))
            end
        end)
    end)
    snap.tip = EllesmereUI.L("Makes the addons that are on for this character the default for every character.")
    Place(snap, 230)

    local addCat = Button(parent, EllesmereUI.L("Add a Category"), 160, 30)
    addCat:SetScript("OnClick", function()
        EllesmereUI:ShowInputPopup({
            title = EllesmereUI.L("Add a Category"),
            message = EllesmereUI.L("Name of the category. Right-click an addon to put it in one."),
            placeholder = EllesmereUI.L("Category name"),
            confirmText = EllesmereUI.L("Add"),
            onConfirm = function(text)
                if AM.AddCategory(text) then
                    EllesmereUI:RefreshPage(true)
                else
                    UIErrorsFrame:AddMessage(EllesmereUI.L("That category already exists."), 1, 0.3, 0.3)
                end
            end,
        })
    end)
    Place(addCat, 160)

    if showUsage then
        local refresh = Button(parent, EllesmereUI.L("Refresh Usage"), 150, 30)
        refresh:SetScript("OnClick", function()
            AM.RefreshMemory(true)
            update()
        end)
        Place(refresh, 150)
    end
    y = y - 42

    -- Options
    local menuCheck = Check(parent, EllesmereUI.L("Open this manager from the game menu"),
        function() return store.menu == true end,
        function(v)
            store.menu = v or nil
            if v then AM.HookMenu() end
        end)
    menuCheck:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, y)
    y = y - 26
    local loginCheck = Check(parent, EllesmereUI.L("Offer to apply at login"),
        function() return not store.quiet end,
        function(v) store.quiet = (not v) or nil end)
    loginCheck:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, y)
    y = y - 26
    local usageCheck = Check(parent, EllesmereUI.L("Show CPU and memory use"),
        function() return store.usage == true end,
        function(v)
            store.usage = v or nil
            EllesmereUI:RefreshPage(true)
        end)
    usageCheck:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, y)
    y = y - 38

    -- Search
    local sb = CreateFrame("EditBox", nil, parent)
    sb:SetSize(280, 26)
    sb:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, y)
    sb:SetAutoFocus(false)
    sb:SetFont(EllesmereUI.EXPRESSWAY, 13, "")
    sb:SetTextInsets(10, 10, 0, 0)
    EllesmereUI.SolidTex(sb, "BACKGROUND", 0.05, 0.05, 0.05, 0.9):SetAllPoints()
    Border(sb, 1, 1, 1, 0.25)
    local hint = Font(sb, 13, 1, 1, 1, 0.3)
    hint:SetPoint("LEFT", 10, 0)
    hint:SetText(EllesmereUI.L("Search"))
    sb:SetText(state.query)
    hint:SetShown(state.query == "")
    sb:SetScript("OnEscapePressed", sb.ClearFocus)
    sb:SetScript("OnEnterPressed", sb.ClearFocus)
    -- The list is rebuilt once typing pauses.
    local typed = 0
    sb:SetScript("OnTextChanged", function(self, user)
        hint:SetShown(self:GetText() == "")
        if not user then return end
        typed = typed + 1
        local mine = typed
        C_Timer.After(0.3, function()
            if mine ~= typed then return end
            state.query = (self:GetText() or ""):lower()
            state.refocus = true
            EllesmereUI:RefreshPage(true)
        end)
    end)
    if state.refocus then
        state.refocus = false
        sb:SetFocus()
        sb:SetCursorPosition(#state.query)
    end

    -- Character on screen
    local cb = Button(parent, "", 240, 26)
    cb:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -PAD, y)
    local charText = Font(cb, 13, 1, 1, 1, 1)
    charText:SetPoint("LEFT", 10, 0)
    charText:SetPoint("RIGHT", -22, 0)
    charText:SetJustifyH("LEFT")
    charText:SetWordWrap(false)
    charText:SetText(CharLabel(sel))
    cb.label:SetText("")
    local arrow = Font(cb, 12, 1, 1, 1, 0.6)
    arrow:SetPoint("RIGHT", -10, 0)
    arrow:SetText("v")
    local picker = CreateFrame("Frame", nil, parent)
    picker:SetPoint("TOPRIGHT", cb, "BOTTOMRIGHT", 0, -2)
    picker:SetFrameLevel(parent:GetFrameLevel() + 30)
    picker:EnableMouse(true)
    EllesmereUI.SolidTex(picker, "BACKGROUND", 0.077, 0.068, 0.058, 1):SetAllPoints()
    Border(picker, 1, 1, 1, 0.3)
    picker:Hide()
    if not parent._amHooked then
        parent._amHooked = true
        parent:HookScript("OnHide", function(self)
            if self._amOnHide then self._amOnHide() end
        end)
    end
    cb:SetScript("OnClick", function()
        if picker:IsShown() then
            picker:Hide()
            return
        end
        local chars = AM.Characters()
        picker.items = picker.items or {}
        for _, b in ipairs(picker.items) do b:Hide() end
        for i, key in ipairs(chars) do
            local b = picker.items[i]
            if not b then
                b = CreateFrame("Button", nil, picker)
                b:SetSize(240, 26)
                b:SetPoint("TOPLEFT", picker, "TOPLEFT", 0, -(i - 1) * 26)
                b.hl = EllesmereUI.SolidTex(b, "HIGHLIGHT", 1, 1, 1, 0.08)
                b.hl:SetAllPoints()
                b.text = Font(b, 13, 1, 1, 1, 1)
                b.text:SetPoint("LEFT", 10, 0)
                b:SetScript("OnClick", function(self)
                    picker:Hide()
                    state.sel = self.key
                    EllesmereUI:RefreshPage(true)
                end)
                picker.items[i] = b
            end
            b.key = key
            b.text:SetText(CharLabel(key))
            b:Show()
        end
        picker:SetSize(240, #chars * 26)
        picker:Show()
    end)
    y = y - 38

    -- Column headers
    local ha = Font(parent, 12, 1, 1, 1, 0.5)
    ha:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD + 12, y - 4)
    ha:SetText(EllesmereUI.L("Addon"))
    local function Header(text, centre)
        local fs = Font(parent, 12, 1, 1, 1, 0.5)
        fs:SetPoint("TOP", parent, "TOPLEFT", PAD + centre, y - 4)
        fs:SetWidth(120)
        fs:SetText(text)
        return fs
    end
    local hs = Font(parent, 12, 1, 1, 1, 0.5)
    hs:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD + statusLeft, y - 4)
    hs:SetText(EllesmereUI.L("Status"))
    if showUsage then
        local hc = Font(parent, 12, 1, 1, 1, 0.5)
        hc:SetPoint("TOPRIGHT", parent, "TOPLEFT", PAD + cpuRight, y - 4)
        hc:SetText(EllesmereUI.L("CPU"))
        local hm = Font(parent, 12, 1, 1, 1, 0.5)
        hm:SetPoint("TOPRIGHT", parent, "TOPLEFT", PAD + memRight, y - 4)
        hm:SetText(EllesmereUI.L("Memory"))
    end
    Header(EllesmereUI.L("Default"), COL_DEFAULT)
    local ch = Header(sel:match("^(.-) %- ") or sel, COL_CHAR)
    ch:SetTextColor(Accent())
    y = y - 24

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

    -- Right-click on an addon: where to put it.
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
    parent._amOnHide = function()
        picker:Hide()
        moveMenu:Hide()
    end

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

    OpenMoveMenu = function(row)
        local a = row.entry.addon
        local function Put(value)
            return function()
                AM.SetCategory(a.name, value)
                EllesmereUI:RefreshPage(true)
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
        local who = sel:match("^(.-) %- ") or sel
        local function Set(everyone, value)
            return function()
                if everyone then
                    AM.SetDefaults(addons, value)
                else
                    AM.SetOverrides(sel, addons, value)
                end
                update()
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

    -- One addon row. members: a group's addons, for Shift-click.
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
            update()
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
            update()
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
            EllesmereUI:RefreshPage(true)
        end)
        row:SetScript("OnEnter", function(self)
            Tip(self, EllesmereUI.L("Click to fold. Right-click to switch all of its addons on or off."))
        end)
        row:SetScript("OnLeave", Untip)
        if entry.user then
            local del = Button(row, EllesmereUI.L("Remove"), 80, 20)
            del:SetPoint("RIGHT", -8, 0)
            del:SetScript("OnClick", function()
                EllesmereUI:ShowConfirmPopup({
                    title = EllesmereUI.L("Remove the category"),
                    message = EllesmereUI.Lf("Remove the category %s? Its addons go back to the category they declare.", entry.name),
                    confirmText = EllesmereUI.L("Remove"),
                    cancelText = EllesmereUI.L("Cancel"),
                    onConfirm = function()
                        AM.RemoveCategory(entry.name)
                        EllesmereUI:RefreshPage(true)
                    end,
                })
            end)
            del.tip = EllesmereUI.L("Removes this category, which you made.")
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
        local status, sr, sg, sb2, sa = StatusOf(a)
        row.status:SetText(status or "")
        if status then row.status:SetTextColor(sr, sg, sb2, sa) end
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
        apply.label:SetText(pending > 0 and EllesmereUI.Lf("Apply and Reload (%d)", pending)
            or EllesmereUI.L("Apply and Reload"))
        SetButtonOn(apply, pending > 0 and not InCombatLockdown())
    end
    update()

    return math.abs(y - yOffset) + 20
end
