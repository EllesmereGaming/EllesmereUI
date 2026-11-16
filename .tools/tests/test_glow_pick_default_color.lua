-- Stub harness: the shared glow options (EllesmereUIOptions/EllesmereUI_GlowOptions.lua) and the
-- two nameplate cast bar glows (EUI_Nameplates_Options.lua).
-- On a nameplate cast bar the Modern WoW Glow style is Blizzard's own nameplate cast bar art,
-- whose colours are its own. So switching either cast bar glow's style control to Modern WoW
-- Glow selects the Default colour (the art's own); the custom colour itself is kept, and the
-- player can pick Custom or Class again afterwards. A site opts in by listing the styles in
-- defaultColorOnPick (shared style indexes); every other glow site is untouched.
-- Driven here: the real glow options file loaded whole, the glow engine's real style list, view
-- builder and host tables, and the real nameplate cast bar glow descriptor.
--   lua .tools/tests/test_glow_pick_default_color.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return (src:gsub("\r\n", "\n"))
end
local function Cut(src, first, last, what)
    local a = assert(src:find(first, 1, true), what .. ": first line not found")
    local b = assert(src:find(last, a + #first, true), what .. ": last line not found")
    return src:sub(a, b - 1)
end

local fails, count = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        if fails <= 14 then print("  FAIL: " .. msg) end
    end
end

local GLOWS = ReadSource("EllesmereUI_Glows.lua")
local OPTS = ReadSource("EllesmereUIOptions/EllesmereUI_GlowOptions.lua")
local NPOPTS = ReadSource("EllesmereUIOptions/EUI_Nameplates_Options.lua")
local LAYOUT = ReadSource("EllesmereUINameplates/EUI_Nameplates_Layout.lua")

-------------------------------------------------------------------------------
-- The glow engine's real model: style list, views, hosts, style and colour
-- resolution, the flat key schema
-------------------------------------------------------------------------------
local G = {}
local STYLES = {}
do
    local block = assert(GLOWS:match("local GLOW_STYLES = (%b{})"), "the style list was not found")
    for name in block:gmatch('{ name = "([^"]+)"') do STYLES[#STYLES + 1] = { name = name } end
    G.STYLES = STYLES
    assert(loadstring("local G, GLOW_STYLES, STEALABLE_BORDER, PANDEMIC_BORDER, EllesmereUI = ...\n" ..
        Cut(GLOWS, "    local DEF_R, DEF_G, DEF_B = 1.0, 0.788, 0.137", "    -- Options previews sit in the panel", "the glow model"),
        "=EllesmereUI_Glows.lua"))(G, STYLES, 101, 102, { GetClassColor = function() return { r = 0.5, g = 0.5, b = 0.5 } end })
end
local MODERN, PIXEL, ABG
for i, e in ipairs(STYLES) do
    if e.name == "Modern WoW Glow" then MODERN = i end
    if e.name == "Pixel Glow" then PIXEL = i end
    if e.name == "Action Button Glow" then ABG = i end
end
check(MODERN ~= nil and PIXEL == 1 and ABG ~= nil, "the style list was not read")

-------------------------------------------------------------------------------
-- The glow options file, loaded whole
-------------------------------------------------------------------------------
local refreshes, timers = 0, {}
local EUI = {
    Glows = G,
    _Pool = { CreateFrame = function() return {} end, Gen = function() return 1 end },
}
function EUI:RefreshPage() refreshes = refreshes + 1 end
do
    local env = setmetatable({ EllesmereUI = EUI, C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end } }, { __index = _G })
    local chunk = assert(loadstring(OPTS, "=EllesmereUI_GlowOptions.lua"))
    setfenv(chunk, env)
    chunk()
end
local GO = assert(EUI.GlowOptions, "the glow options did not load")
local function RunTimers()
    local t = timers
    timers = {}
    for _, fn in ipairs(t) do fn() end
end

-------------------------------------------------------------------------------
-- The nameplate cast bar glow descriptor, over the module's view and a profile
-------------------------------------------------------------------------------
local order = {}
for n in assert(LAYOUT:match("ns%.NP_GLOW_VIEW = EllesmereUI%.Glows%.MakeView%((%b{})"), "the nameplate glow view was not found"):gmatch("%d+") do
    order[#order + 1] = tonumber(n)
end
local ns = { NP_GLOW_VIEW = G.MakeView(order), NP_CAST_ART_STYLE = MODERN }
local NP_MODERN, NP_PIXEL, NP_ABG = ns.NP_GLOW_VIEW.fromShared[MODERN], ns.NP_GLOW_VIEW.fromShared[PIXEL], ns.NP_GLOW_VIEW.fromShared[ABG]
check(NP_MODERN ~= nil and NP_PIXEL == 1 and NP_ABG ~= nil, "the nameplate view holds no Modern WoW Glow")

local defaults = {
    importantCastGlow = true, importantCastGlowStyle = 1, importantCastGlowColor = { r = 1, g = 0.2, b = 0.2 },
    castTargetGlow = false, castTargetGlowStyle = 1, castTargetGlowColor = { r = 1, g = 1, b = 1 },
}
local profile = {}
local changes = 0
local function DB() return profile end
local function DBVal(k)
    local v = profile[k]
    if v == nil then v = defaults[k] end
    return v
end
local function MakeDescFactory(nsTable)
    return assert(loadstring(
        "local EllesmereUI, ns, defaults, DBVal, DB, GO, RefreshCastGlows = ...\n" ..
        Cut(NPOPTS, "        local function CastBarGlowDesc(prefix)", '        npImpCastGlowDesc = CastBarGlowDesc("importantCastGlow")', "the cast bar glow descriptor") ..
        "\nreturn CastBarGlowDesc", "=EUI_Nameplates_Options.lua"))(
        EUI, nsTable, defaults, DBVal, DB, GO, function() changes = changes + 1 end)
end
local CastBarGlowDesc = MakeDescFactory(ns)
local function Reset()
    for k in pairs(profile) do profile[k] = nil end
    changes, refreshes, timers = 0, 0, {}
end

-------------------------------------------------------------------------------
-- 1. Important Cast Glow: switching the dropdown to Modern WoW Glow
-------------------------------------------------------------------------------
do
    Reset()
    local desc = CastBarGlowDesc("importantCastGlow")
    check(desc.defaultColorOnPick ~= nil and desc.defaultColorOnPick[MODERN] == true, "the important cast glow does not list Modern WoW Glow")
    local n = 0
    for _ in pairs(desc.defaultColorOnPick or {}) do n = n + 1 end
    check(n == 1, "the important cast glow lists " .. n .. " styles, not Modern WoW Glow alone")
    local spec = GO.DropdownSpec(desc, "Important Cast Glow")
    check(spec.getValue() == NP_PIXEL, "the control does not show Pixel Glow to begin with")
    check(desc.get("mode") == "custom", "an untouched profile is not on the custom colour")

    -- Pixel Glow -> Modern WoW Glow: the style is saved and the colour goes to Default
    spec.setValue(NP_MODERN)
    check(profile.importantCastGlowStyle == NP_MODERN and profile.importantCastGlow == true, "the pick did not save the style")
    check(profile.importantCastGlowColorMode == "default", "switching to Modern WoW Glow did not select the Default colour (" .. tostring(profile.importantCastGlowColorMode) .. ")")
    check(profile.importantCastGlowColor == nil, "the pick wrote the custom colour itself")
    check(changes == 1, "the casts already showing were refreshed " .. changes .. " times, not once")
    RunTimers()
    check(refreshes == 1, "the page was not refreshed once after the pick (the colour swatches follow it)")
    check(spec.getValue() == NP_MODERN, "the control does not show Modern WoW Glow after the pick")

    -- the player goes back to a custom colour: picking Modern WoW Glow again, while it is
    -- already the style, is no switch and leaves the choice alone
    desc.set("mode", "custom")
    spec.setValue(NP_MODERN)
    check(profile.importantCastGlowColorMode == "custom", "picking the style that is already shown changed the colour choice")

    -- switching away leaves the colour choice as it is
    spec.setValue(NP_PIXEL)
    check(profile.importantCastGlowStyle == NP_PIXEL and profile.importantCastGlowColorMode == "custom", "switching to Pixel Glow changed the colour choice")
    desc.set("mode", "class")
    spec.setValue(NP_ABG)
    check(profile.importantCastGlowColorMode == "class", "switching to Action Button Glow changed the colour choice")

    -- from Class Colored to Modern WoW Glow: Default
    spec.setValue(NP_MODERN)
    check(profile.importantCastGlowColorMode == "default", "switching from a class colour to Modern WoW Glow did not select the Default colour")

    -- a custom colour that was set stays stored through the switch
    Reset()
    profile.importantCastGlowColor = { r = 0.1, g = 0.9, b = 0.3 }
    profile.importantCastGlowColorMode = "custom"
    spec.setValue(NP_MODERN)
    local c = profile.importantCastGlowColor
    check(profile.importantCastGlowColorMode == "default" and c and c.r == 0.1 and c.g == 0.9 and c.b == 0.3, "the stored custom colour did not survive the switch")

    -- the glow is off with Modern WoW Glow as its saved style: the control shows None, so
    -- picking Modern WoW Glow is a switch (and turns the glow on)
    Reset()
    profile.importantCastGlow = false
    profile.importantCastGlowStyle = NP_MODERN
    profile.importantCastGlowColorMode = "custom"
    check(spec.getValue() == 0, "an off glow does not read None")
    spec.setValue(NP_MODERN)
    check(profile.importantCastGlow == true and profile.importantCastGlowColorMode == "default", "turning the glow on with Modern WoW Glow did not select the Default colour")

    -- picking None never touches the colour
    profile.importantCastGlowColorMode = "custom"
    spec.setValue(0)
    check(profile.importantCastGlow == false and profile.importantCastGlowColorMode == "custom", "picking None changed the colour choice")
end

-------------------------------------------------------------------------------
-- 2. Cast Targets You Glow follows the same rule; a site with a confirm step
--    applies it when the pick is confirmed; the cog popup's style row too
-------------------------------------------------------------------------------
do
    Reset()
    local desc = CastBarGlowDesc("castTargetGlow")
    local spec = GO.DropdownSpec(desc, "Cast Targets You Glow")
    check(spec.getValue() == 0, "Cast Targets You Glow is not off to begin with")
    spec.setValue(NP_MODERN)
    check(profile.castTargetGlow == true and profile.castTargetGlowStyle == NP_MODERN and profile.castTargetGlowColorMode == "default",
        "Cast Targets You Glow does not take the Default colour with Modern WoW Glow")
    check(profile.importantCastGlowColorMode == nil, "the pick wrote the other glow's colour choice")

    -- a confirm step: nothing is written until the pick is confirmed
    Reset()
    local held
    desc.confirm = function(_, commit) held = commit end
    spec.setValue(NP_MODERN)
    check(profile.castTargetGlowStyle == nil and profile.castTargetGlowColorMode == nil, "a pick waiting for its confirm already wrote")
    held()
    check(profile.castTargetGlowStyle == NP_MODERN and profile.castTargetGlowColorMode == "default", "a confirmed pick did not select the Default colour")
    desc.confirm = nil

    -- the same control as a cog popup row
    Reset()
    local rows = GO.PopupRows(desc, "Glow Style")
    check(rows[1].type == "dropdown" and rows[1].get() == 0, "the popup's first row is not the style control")
    rows[1].set(NP_MODERN)
    check(profile.castTargetGlowColorMode == "default", "the popup's style row does not select the Default colour")
    profile.castTargetGlowColorMode = "class"
    rows[1].set(NP_MODERN)
    check(profile.castTargetGlowColorMode == "class", "the popup's style row changed the colour on a pick of the shown style")
end

-------------------------------------------------------------------------------
-- 3. sites that do not opt in, or have no colour modes, are untouched
-------------------------------------------------------------------------------
do
    -- the same descriptor without the list: every other glow site
    Reset()
    local plain = CastBarGlowDesc("importantCastGlow")
    plain.defaultColorOnPick = nil
    local spec = GO.DropdownSpec(plain, "Glow")
    spec.setValue(NP_MODERN)
    check(profile.importantCastGlowStyle == NP_MODERN and profile.importantCastGlowColorMode == nil, "a site that lists no styles had its colour choice changed")

    -- a site that lists the style but has no colour modes never gets a mode written
    Reset()
    local modeWrites = 0
    local noMode = CastBarGlowDesc("importantCastGlow")
    noMode.caps = { params = true }
    local set = noMode.set
    noMode.set = function(f, ...) if f == "mode" then modeWrites = modeWrites + 1 end return set(f, ...) end
    GO.DropdownSpec(noMode, "Glow").setValue(NP_MODERN)
    check(modeWrites == 0 and profile.importantCastGlowStyle == NP_MODERN, "a site without colour modes got a colour mode written")

    -- a module whose runtime names no art style lists nothing (and nothing errors)
    Reset()
    local none = MakeDescFactory({ NP_GLOW_VIEW = ns.NP_GLOW_VIEW })("importantCastGlow")
    check(none.defaultColorOnPick == nil, "a descriptor lists a style although the runtime names none")
    GO.DropdownSpec(none, "Glow").setValue(NP_MODERN)
    check(profile.importantCastGlowColorMode == nil, "a descriptor without the list changed the colour choice")

    -- a template carries its own colour choice: applying one is not a pick from the control
    Reset()
    local desc = CastBarGlowDesc("importantCastGlow")
    local applied = GO.ApplyTemplate(desc, { style = MODERN, mode = "custom", r = 0.2, g = 0.4, b = 0.6 }, true)
    check(applied == true and profile.importantCastGlowStyle == NP_MODERN and profile.importantCastGlowColorMode == "custom",
        "a template's colour choice was replaced")
end

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print(("PASS test_glow_pick_default_color (%d checks)"):format(count))
