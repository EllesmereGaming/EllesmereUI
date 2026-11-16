-- Stub harness: the Flyout Settings cog on the Call Totem Bar's Orientation row
-- (Resource Bars > Totem Bars; WoW Forever shamans only). Loads the real
-- ResourceBars_Options/TotemBarPage_Options.lua under widget stand-ins that
-- record every section, row and inline cog, builds the page per client and
-- class, and reads a greyed cog's tooltip through the real ResolveDisabledTip
-- and DisabledTooltip, cut from their files.
--   lua .tools/tests/test_rb_totem_flyout_cog.lua        (from the repository root)
local fails, count = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        if fails <= 40 then print("  FAIL: " .. tostring(msg)) end
    end
    return cond
end
local function eq(a, b, msg)
    return check(a == b, tostring(msg) .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")")
end

local function Read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    return s
end
local PAGE = Read("EllesmereUIOptions/ResourceBars_Options/TotemBarPage_Options.lua")

-- A file-scope local function of a source file: from its first line to the
-- "end" in column 0 that closes it.
local function Cut(src, first)
    local a = assert(src:find(first, 1, true), "not found: " .. first)
    local b = assert(src:find("\nend\n", a, true), "no closing end: " .. first)
    return src:sub(a, b + 4)
end
local TIP_SRC = Cut(Read("EllesmereUI_UICore.lua"), "local function DisabledTooltip(requirement, state)")
    .. Cut(Read("EllesmereUIOptions/EllesmereUI_Widgets.lua"), "local function ResolveDisabledTip(cfg)")
    .. "return ResolveDisabledTip\n"

-------------------------------------------------------------------------------
--  The world: one page build
-------------------------------------------------------------------------------
-- o: forever, class, cfg (the profile's callTotemBar), prebuild (the search
-- pre-build), noPlace (the runtime file did not load: no ns.CT_PlaceFlyout)
local function Build(o)
    local rec = { sections = {}, cogs = {}, calls = {} }
    local function Called(name) rec.calls[name] = (rec.calls[name] or 0) + 1 end
    rec.Calls = function(name) return rec.calls[name] or 0 end
    rec.Forget = function() rec.calls = {} end

    -- A frame stand-in: every method is a no-op, fields read as set.
    local frameMT = { __index = function(_, k)
        if k == "GetFrameLevel" then return function() return 1 end end
        if type(k) == "string" and k:match("^%u") then return function() end end
    end }
    local function Frame() return setmetatable({}, frameMT) end

    local W = {}
    function W:SectionHeader(_, title)
        local s = Frame()
        s.title, s.rows = title, {}
        rec.sections[#rec.sections + 1] = s
        rec.cur = s
        return s, 30
    end
    function W:DualRow(_, _, left, right)
        local row = Frame()
        row.left, row.right = left, right
        row._leftRegion, row._rightRegion = Frame(), Frame()
        row._leftRegion._cfg, row._rightRegion._cfg = left, right
        row._leftRegion._control, row._rightRegion._control = Frame(), Frame()
        rec.cur.rows[#rec.cur.rows + 1] = row
        return row, 40
    end
    function W:Spacer() return Frame(), 16 end

    local ns = {}
    local profile = { totemBar = { enabledClasses = { SHAMAN = true } }, callTotemBar = o.cfg }
    rec.profile = profile
    local E = {
        IS_FOREVER = o.forever or false,
        _prebuilding = o.prebuild or false,
        _ModuleNS = { EllesmereUIResourceBars = ns },
        _Pool = { CreateFrame = function() return Frame() end },
        Widgets = W,
        PP = { Point = function() end },
        PanelPP = { Point = function() end },
        FRAME_STRATA_LABELS = {}, FRAME_STRATA_ORDER_BASE = {},
        CLASS_TOKEN_ORDER = { "SHAMAN", "DRUID" },
        FOREVER_CLASS_SPEC = { SHAMAN = true, DRUID = true },
        L = function(s) return s end,
        -- the client's format takes positional arguments; Lua 5.1's does not
        Lf = function(fmt, ...)
            local args = { ... }
            return (fmt:gsub("%%(%d)%$s", function(i) return tostring(args[tonumber(i)]) end))
        end,
        BuildSectionUnlockJump = function() end,
        BuildInlineCog = function(rgn, opts)
            rec.cogs[#rec.cogs + 1] = { rgn = rgn, opts = opts }
            return Frame()
        end,
        GetBorderTextureDropdown = function() return {}, {} end,
        BorderPxSliderCfg = function(cfg) cfg.type = "slider"; return cfg end,
        BorderOffsetRowCfgs = function()
            return { type = "slider", text = "Width Offset" }, { type = "slider", text = "Height Offset" }
        end,
        BuildColorSwatch = function() return Frame(), function() end end,
        BuildVisOptsCBDropdown = function() return Frame(), function() end end,
        RegisterWidgetRefresh = function() end,
        ShowWidgetTooltip = function() end,
        HideWidgetTooltip = function() end,
        DisabledTooltip = function(s) return s end,
        NotifyElementResized = function() Called("NotifyElementResized") end,
    }
    function E:SetContentHeader() end
    function E:RefreshPage(force) Called(force and "RefreshPage(true)" or "RefreshPage") end
    ns._ERB_OptEnv = {
        DB = function() return profile end,
        PP = E.PP,
        _clickMappings = {},
        UpdateTotemPreview = function() Called("UpdateTotemPreview") end,
        _totemPreviewBuilder = function() end,
    }
    if not o.noPlace then ns.CT_PlaceFlyout = function() Called("CT_PlaceFlyout") end end

    EUI_CLIENT_BLOCKED = nil
    EllesmereUI = E
    _ERB_Apply = function() Called("_ERB_Apply") end
    UnitClass = function() return "x", o.class or "SHAMAN" end
    RAID_CLASS_COLORS, LOCALIZED_CLASS_NAMES_MALE = {}, {}

    assert(loadstring(PAGE, "=TotemBarPage"))()
    assert(ns.ERB_BuildTotemBarPage, "the page file did not load")
    rec.height = ns.ERB_BuildTotemBarPage("Totem Bars", Frame(), 0)
    -- the tooltip a greyed control shows, as the widgets resolve it
    rec.Tip = setfenv(assert(loadstring(TIP_SRC, "=the disabled tooltip")), setmetatable({ EllesmereUI = E }, { __index = _G }))()
    rec.Forget()
    return rec
end

local function Section(rec, title)
    for _, s in ipairs(rec.sections) do
        if s.title == title then return s end
    end
end
-- The control named text in a section: its config and the row half it sits in.
local function Control(sec, text)
    for _, row in ipairs(sec and sec.rows or {}) do
        if row.left and row.left.text == text then return row.left, row._leftRegion end
        if row.right and row.right.text == text then return row.right, row._rightRegion end
    end
end
local function FlyoutCogs(rec)
    local list = {}
    for _, c in ipairs(rec.cogs) do
        if c.opts.title == "Flyout Settings" then list[#list + 1] = c end
    end
    return list
end
local function Titles(rec)
    local t = {}
    for i, s in ipairs(rec.sections) do t[i] = s.title end
    return table.concat(t, " | ")
end

local OFF_TIP = "This option requires Call Totem Bar to be enabled"
local ROW_TIP = "This option requires the Vertical orientation."

-------------------------------------------------------------------------------
-- 1. Where the cog is built: the Call Totem Bar section's Orientation, for a
--    WoW Forever shaman, and never in the search pre-build
-------------------------------------------------------------------------------
do
    local rec = Build({ forever = true, class = "SHAMAN", cfg = { enabled = true, orientation = "VERTICAL" } })
    eq(Titles(rec), "ACTIVE TOTEM BAR | CALL TOTEM BAR", "a WoW Forever shaman's sections")
    local cogs = FlyoutCogs(rec)
    eq(#cogs, 1, "Flyout Settings cogs for a WoW Forever shaman")
    local cfg, rgn = Control(Section(rec, "CALL TOTEM BAR"), "Orientation")
    check(cfg ~= nil and cfg.type == "dropdown", "the Call Totem Bar section has an Orientation dropdown")
    check(cogs[1] and cogs[1].rgn == rgn, "the cog sits on the Call Totem Bar's Orientation")
    local _, activeRgn = Control(Section(rec, "ACTIVE TOTEM BAR"), "Orientation")
    check(activeRgn ~= nil and (not cogs[1] or cogs[1].rgn ~= activeRgn), "the active totem bar's Orientation has none")
    check(type(rec.height) == "number" and rec.height > 0, "the page reports its height")

    rec = Build({ forever = true, class = "DRUID", cfg = { enabled = true, orientation = "VERTICAL" } })
    eq(Titles(rec), "ACTIVE TOTEM BAR", "another WoW Forever class's sections")
    eq(#FlyoutCogs(rec), 0, "Flyout Settings cogs for another class")

    rec = Build({ forever = false, class = "SHAMAN", cfg = { enabled = true, orientation = "VERTICAL" } })
    eq(Titles(rec), "LAYOUT", "retail's section")
    eq(#FlyoutCogs(rec), 0, "Flyout Settings cogs on retail")

    rec = Build({ forever = true, class = "SHAMAN", prebuild = true, cfg = { enabled = true, orientation = "VERTICAL" } })
    eq(Titles(rec), "ACTIVE TOTEM BAR | CALL TOTEM BAR", "the search pre-build's sections")
    eq(#rec.cogs, 0, "cogs of any kind in the search pre-build")
end

-------------------------------------------------------------------------------
-- 2. Greyed while the bar is off or a row, and the tooltip names which
-------------------------------------------------------------------------------
for _, c in ipairs({
    { "the bar off, a column", { enabled = false, orientation = "VERTICAL" }, true, OFF_TIP },
    { "the bar off, a row", { enabled = false, orientation = "HORIZONTAL" }, true, OFF_TIP },
    { "the bar off, no orientation saved", { enabled = false }, true, OFF_TIP },
    { "on, a row", { enabled = true, orientation = "HORIZONTAL" }, true, ROW_TIP },
    { "on, no orientation saved", { enabled = true }, true, ROW_TIP },
    { "on, a column", { enabled = true, orientation = "VERTICAL" }, false },
}) do
    local rec = Build({ forever = true, class = "SHAMAN", cfg = c[2] })
    local cog = FlyoutCogs(rec)[1]
    if check(cog ~= nil, c[1] .. ": the cog is built") then
        local o = cog.opts
        eq(type(o.disabled), "function", c[1] .. ": the cog's disabled is a function")
        eq(o.disabled() and true or false, c[3], c[1] .. ": greyed")
        if c[3] then
            eq(rec.Tip(o), c[4], c[1] .. ": the greyed cog's tooltip")
        end
        -- while the bar is off the cog explains itself as its own row does
        local rowCfg = Control(Section(rec, "CALL TOTEM BAR"), "Orientation")
        if c[2].enabled == false then
            eq(rowCfg.disabled() and true or false, true, c[1] .. ": the Orientation dropdown is greyed too")
            eq(rec.Tip(o), rec.Tip(rowCfg), c[1] .. ": the cog's tooltip is its row's")
        else
            eq(rowCfg.disabled() and true or false, false, c[1] .. ": the Orientation dropdown is live")
        end
    end
end
-- a live state change needs no rebuild: the same cog answers for the new state
do
    local cfg = { enabled = true, orientation = "HORIZONTAL" }
    local rec = Build({ forever = true, class = "SHAMAN", cfg = cfg })
    local o = FlyoutCogs(rec)[1].opts
    eq(rec.Tip(o), ROW_TIP, "a row: the tooltip")
    cfg.orientation = "VERTICAL"
    eq(o.disabled() and true or false, false, "turned into a column: the cog is live")
    cfg.enabled = false
    eq(o.disabled() and true or false, true, "then turned off: greyed")
    eq(rec.Tip(o), OFF_TIP, "then turned off: the tooltip names the bar")
end

-------------------------------------------------------------------------------
-- 3. Its one row, Flyout Direction: reads and writes the bar's flyoutDirection
--    and asks only for an open list to be placed
-------------------------------------------------------------------------------
do
    local cfg = { enabled = true, orientation = "VERTICAL" }
    local rec = Build({ forever = true, class = "SHAMAN", cfg = cfg })
    local rows = FlyoutCogs(rec)[1].opts.rows
    eq(#rows, 1, "rows in the Flyout Settings cog")
    local row = rows[1]
    eq(row.type, "dropdown", "the row's type")
    eq(row.label, "Flyout Direction", "the row's label")
    eq(row.values.RIGHT, "Right", "the Right entry")
    eq(row.values.LEFT, "Left", "the Left entry")
    eq(table.concat(row.order, ","), "RIGHT,LEFT", "the entries' order")
    eq(row.get(), "RIGHT", "nothing saved reads as Right")
    cfg.flyoutDirection = "LEFT"
    eq(row.get(), "LEFT", "a saved Left reads as Left")
    cfg.flyoutDirection = nil
    rec.Forget()
    row.set("LEFT")
    eq(cfg.flyoutDirection, "LEFT", "a pick is saved on the call totem bar")
    eq(rec.profile.totemBar.flyoutDirection, nil, "and not on the active totem bar")
    eq(rec.Calls("CT_PlaceFlyout"), 1, "a pick asks for an open list to be placed")
    eq(rec.Calls("_ERB_Apply"), 0, "a pick runs no Resource Bars apply")
    eq(rec.Calls("NotifyElementResized"), 0, "a pick reports no resize")
    eq(rec.Calls("UpdateTotemPreview"), 0, "a pick repaints no preview")
    eq(rec.Calls("RefreshPage") + rec.Calls("RefreshPage(true)"), 0, "a pick refreshes no page")
    row.set("RIGHT")
    eq(cfg.flyoutDirection, "RIGHT", "the pick back is saved")
    eq(rec.Calls("CT_PlaceFlyout"), 2, "and asks again")

    -- the runtime file did not load (no call totem bar frame): the pick still saves
    cfg = { enabled = true, orientation = "VERTICAL" }
    rec = Build({ forever = true, class = "SHAMAN", cfg = cfg, noPlace = true })
    local ok, err = pcall(FlyoutCogs(rec)[1].opts.rows[1].set, "LEFT")
    check(ok, "a pick with no runtime to ask raises nothing (" .. tostring(err) .. ")")
    eq(cfg.flyoutDirection, "LEFT", "and is saved")
end

-------------------------------------------------------------------------------
-- 4. The Orientation pick: saved and applied everywhere; the page is refreshed
--    only where the cog's state follows it
-------------------------------------------------------------------------------
do
    local cfg = { enabled = true }
    local rec = Build({ forever = true, class = "SHAMAN", cfg = cfg })
    local call = Control(Section(rec, "CALL TOTEM BAR"), "Orientation")
    eq(call.getValue(), "HORIZONTAL", "no orientation saved reads as Horizontal")
    call.setValue("VERTICAL")
    eq(cfg.orientation, "VERTICAL", "the call totem bar's pick is saved")
    eq(rec.Calls("_ERB_Apply"), 1, "the call totem bar's pick is applied")
    eq(rec.Calls("RefreshPage"), 1, "the call totem bar's pick refreshes the page (the cog's state)")
    eq(rec.Calls("RefreshPage(true)"), 0, "with no page rebuild")
    rec.Forget()
    local active = Control(Section(rec, "ACTIVE TOTEM BAR"), "Orientation")
    active.setValue("VERTICAL")
    eq(rec.profile.totemBar.orientation, "VERTICAL", "the active totem bar's pick is saved")
    eq(rec.Calls("_ERB_Apply"), 1, "the active totem bar's pick is applied")
    eq(rec.Calls("RefreshPage") + rec.Calls("RefreshPage(true)"), 0, "the active totem bar's pick refreshes no page")

    rec = Build({ forever = false, class = "SHAMAN", cfg = cfg })
    local layout = Control(Section(rec, "LAYOUT"), "Orientation")
    layout.setValue("HORIZONTAL")
    eq(rec.profile.totemBar.orientation, "HORIZONTAL", "retail's pick is saved")
    eq(rec.Calls("_ERB_Apply"), 1, "retail's pick is applied")
    eq(rec.Calls("RefreshPage") + rec.Calls("RefreshPage(true)"), 0, "retail's pick refreshes no page")
end

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print(("PASS test_rb_totem_flyout_cog (%d checks)"):format(count))
