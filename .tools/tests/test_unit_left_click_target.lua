-- Stub harness: a unit button's left click targets with a modifier held too.
-- The game drops a raw "target" click on a unit button unless it is the plain left click, so
-- EllesmereUI.SetLeftClickTarget (EllesmereUI_Kick.lua) keeps the plain click raw and sends a
-- modified one through the button's secure target proxy ("/click <proxy>"). This drives the real
-- parent functions and click casting's pieces (EUI_RaidFrames_ClickCast.lua) over a model of
-- the secure attribute lookup as Blizzard's SecureTemplates.lua documents and implements it
-- (modifier-name-button with "*" wildcards, the bare name last, "useparent-<name>" up the parent
-- chain), and asserts:
--   * every modifier + left click reaches the proxy, which targets the unit the plain click does:
--     the frame's unit, with its unit suffix (a party member's target) and its vehicle toggle;
--   * one proxy and one macrotext per button, built once;
--   * under click casting the wildcard stays only while plain left is Target (right: Menu), a
--     binding of its own wins, and target bindings read the same macrotext;
--   * the modules list the parent functions they call in their stale-parent guards.
-- The model is not the engine: the click itself is checked in game.
--   lua .tools/tests/test_unit_left_click_target.lua        (from the repository root)
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

local KICK = ReadSource("EllesmereUI_Kick.lua")
local CC = ReadSource("EllesmereUIRaidFrames/EUI_RaidFrames_ClickCast.lua")

-------------------------------------------------------------------------------
-- Secure frames: an attribute store with the three-argument lookup
-------------------------------------------------------------------------------
local byName, created, nameReads = {}, 0, 0
local function NewSecure(name, parent)
    local f = { attrs = {}, name = name, parent = parent, mouse = true }
    function f:SetAttribute(k, v) self.attrs[k] = v end
    function f:GetAttribute(a, b, c)
        if b == nil then return self.attrs[a] end
        local v = self.attrs[a .. b .. c]
        if v == nil then v = self.attrs["*" .. b .. c] end
        if v == nil then v = self.attrs[a .. b .. "*"] end
        if v == nil then v = self.attrs["*" .. b .. "*"] end
        if v == nil then v = self.attrs[b] end
        return v
    end
    function f:GetName() nameReads = nameReads + 1; return self.name end
    function f:GetParent() return self.parent end
    function f:SetSize(w, h) self.w, self.h = w, h end
    function f:SetAllPoints() end
    function f:SetAlpha(a) self.alpha = a end
    function f:EnableMouse(v) self.mouse = v end
    function f:RegisterForClicks(v) self.clicks = v end
    if name then byName[name] = f end
    return f
end
local function CreateFrame(kind, name, parent, template)
    created = created + 1
    local f = NewSecure(name, parent)
    f.kind, f.template = kind, template
    return f
end
-- A modified attribute as the secure click handler reads it.
local function ModAttr(frame, name, mods, suffix)
    local v = frame:GetAttribute(mods, name, suffix)
    if not v and (frame:GetAttribute("useparent-" .. name) or frame:GetAttribute("useparent*")) then
        local p = frame:GetParent()
        if p then v = ModAttr(p, name, mods, suffix) end
    end
    if v == "" then v = nil end
    return v
end
-- The unit a click acts on, and whether the vehicle toggle applies to it.
local function Unit(frame, mods, suffix)
    local unit = ModAttr(frame, "unit", mods, suffix)
    if not unit then return nil end
    local sfx = ModAttr(frame, "unitsuffix", mods, suffix)
    if sfx then unit = unit .. sfx end
    return unit, ModAttr(frame, "toggleForVehicle", mods, suffix) and true or false
end
-- What a click does: the action type, the unit, the vehicle toggle, and "direct" or "proxy".
-- A "/click <name>" macro sends a left click to that button with the modifiers still held.
local function Resolve(frame, mods, suffix)
    local t = ModAttr(frame, "type", mods, suffix)
    if t == "macro" then
        local text = ModAttr(frame, "macrotext", mods, suffix)
        local proxy = text and byName[text:match("^/click (%S+)$") or ""]
        if proxy then
            local unit, veh = Unit(proxy, mods, "1")
            return ModAttr(proxy, "type", mods, "1"), unit, veh, "proxy", proxy
        end
        return "macro", nil, nil, text
    end
    if not t then return nil end
    local unit, veh = Unit(frame, mods, suffix)
    return t, unit, veh, "direct"
end

-------------------------------------------------------------------------------
-- The real parent functions
-------------------------------------------------------------------------------
local EllesmereUI = {}
assert(loadstring("local EllesmereUI, CreateFrame, InstallMenuClassifierFix = ...\n" ..
    Cut(KICK, 'local menuProxies = setmetatable({}, { __mode = "k" })', 'local kickFrame = CreateFrame("Frame")', "the proxies"),
    "=EllesmereUI_Kick.lua"))(EllesmereUI, CreateFrame, function() end)
check(type(EllesmereUI.SetLeftClickTarget) == "function", "the parent has no SetLeftClickTarget")
check(type(EllesmereUI.GetSecureTargetMacro) == "function", "the parent has no GetSecureTargetMacro (the proxy's macrotext, built once)")

local MODS = { "shift-", "ctrl-", "alt-", "alt-ctrl-", "ctrl-shift-", "alt-ctrl-shift-" }

-------------------------------------------------------------------------------
-- 1. a modified left click targets what the plain left click targets
-------------------------------------------------------------------------------
local raid = NewSecure("Raid5")
raid:SetAttribute("unit", "raid5")
EllesmereUI.SetLeftClickTarget(raid)

local party = NewSecure("Party2")
party:SetAttribute("unit", "party2")
local pt = NewSecure("Party2Target", party)   -- a Party Targets frame: its party frame's unit, plus "target"
pt:SetAttribute("useparent-unit", true)
pt:SetAttribute("unitsuffix", "target")
EllesmereUI.SetLeftClickTarget(pt)

local player = NewSecure("Player")
player:SetAttribute("unit", "player")
EllesmereUI.SetLeftClickTarget(player)
player:SetAttribute("toggleForVehicle", true)   -- set after, as the unit frames do

for _, case in ipairs({ { raid, "a raid frame", "raid5", false }, { pt, "a Party Targets frame", "party2target", false },
        { player, "the player frame", "player", true } }) do
    local f, what, unit, veh = case[1], case[2], case[3], case[4]
    local t, u, v, how = Resolve(f, "", "1")
    check(t == "target" and how == "direct" and u == unit and v == veh,
        what .. ": the plain left click is not the raw target of " .. unit .. " (" .. tostring(t) .. ", " .. tostring(u) .. ", " .. tostring(how) .. ")")
    for _, m in ipairs(MODS) do
        local mt, mu, mv, mhow = Resolve(f, m, "1")
        check(mt == "target" and mhow == "proxy", what .. ": " .. m .. "left does not reach the target proxy (" .. tostring(mt) .. ", " .. tostring(mhow) .. ")")
        check(mu == unit, what .. ": " .. m .. "left targets " .. tostring(mu) .. ", the plain click " .. unit)
        check(mv == veh, what .. ": " .. m .. "left does not take the frame's vehicle toggle")
    end
    check(Resolve(f, "", "2") == nil and Resolve(f, "shift-", "2") == nil, what .. ": the left-click helper wrote a right-click action")
end

-------------------------------------------------------------------------------
-- 2. the proxy: one per button, hidden, with one macrotext built once
-------------------------------------------------------------------------------
do
    local _, _, _, _, proxy = Resolve(raid, "shift-", "1")
    check(proxy ~= nil and proxy.parent == raid and proxy.template == "SecureActionButtonTemplate", "the proxy is not a secure action button under its unit button")
    if proxy then
        check(proxy.mouse == false and proxy.alpha == 0 and proxy.w == 1 and proxy.h == 1, "the proxy can take the mouse or be seen")
        check(proxy.name:find("^EUISecureTargetProxy%d+$") ~= nil, "the proxy is not globally named for /click")
        check(proxy.attrs["useOnKeyDown"] == false, "the proxy follows Cast on Key Down (the up-click would be skipped)")
        for i = 1, 5 do
            check(proxy.attrs["type" .. i] == "target", "the proxy's button " .. i .. " does not target")
        end
    end
    local before, reads = created, nameReads
    for _ = 1, 5 do EllesmereUI.SetLeftClickTarget(raid) end
    check(created == before, "setting the left click again built " .. (created - before) .. " more proxies")
    check(nameReads == reads, "the macrotext is built again on every call (" .. (nameReads - reads) .. " name reads)")
    if EllesmereUI.GetSecureTargetMacro then
        check(proxy ~= nil and EllesmereUI.GetSecureTargetMacro(raid) == "/click " .. proxy.name, "the target macro does not click the button's own proxy")
        check(raid.attrs["*macrotext1"] == EllesmereUI.GetSecureTargetMacro(raid), "the left-click wildcard does not carry the proxy's macrotext")
        check(EllesmereUI.GetSecureTargetMacro(nil) == nil, "the target macro of no frame is not nil")
    end
    -- the menu proxy is its own button with its own macro
    local menu = EllesmereUI.AttachSecureUnitMenu(raid)
    check(menu ~= nil and menu ~= proxy and raid.attrs["*type2"] == "macro" and raid.attrs["*macrotext2"] == EllesmereUI.GetSecureMenuMacro(raid),
        "the right click does not open the menu through the menu proxy")
    check(raid.attrs["type1"] == "target" and raid.attrs["*type1"] == "macro", "attaching the menu changed the left click")
end

-------------------------------------------------------------------------------
-- 3. click casting
-------------------------------------------------------------------------------
do
    local drivers = {}
    local SetClickAttr, SetKeyAttr = assert(loadstring(
        "local EllesmereUI, UnregisterAttributeDriver, RegisterAttributeDriver = ...\n" ..
        Cut(CC, "local function ModPrefixForAttr(modsStr)", "local function ClearKeyAttrs(frame, count)", "the binding writers") ..
        "\nreturn SetClickAttr, SetKeyAttr", "=ClickCast.lua (the writers)"))(EllesmereUI,
        function(frame, attr) drivers[attr] = nil end, function(frame, attr, cond) drivers[attr] = cond end)
    local Neutralize = assert(loadstring("local EllesmereUI = ...\n" ..
        Cut(CC, "local function NeutralizeDefaultClicks(frame, plan)", "-- A binding list parsed and resolved once", "the neutralizer") ..
        "\nreturn NeutralizeDefaultClicks", "=ClickCast.lua (the neutralizer)"))(EllesmereUI)

    -- mods: a run of "MOD-" tokens, as the key parser writes them ("" for none).
    local function Button(mods, n) return { isMouseButton = true, modifiers = mods, buttonNum = n } end
    local function Entry(mods, n, aType, ooc) return { frame = true, parsed = Button(mods, n), aType = aType, b = { oocOnly = ooc or false } } end
    -- A frame as its module built it, then the bindings written, then the neutralizer: the real order.
    local function Apply(plan)
        local f = NewSecure(nil)
        f:SetAttribute("unit", "raid9")
        EllesmereUI.SetLeftClickTarget(f)
        EllesmereUI.AttachSecureUnitMenu(f)
        for i = 1, #plan do
            local r = plan[i]
            SetClickAttr(f, r.parsed, r.aType, "Flash Heal", nil, r.b.oocOnly)
        end
        Neutralize(f, plan)
        return f
    end

    -- the defaults: left = Target, right = Menu
    local f = Apply({ Entry("", 1, "target"), Entry("", 2, "togglemenu") })
    local t, u, _, how = Resolve(f, "", "1")
    check(t == "target" and how == "direct" and u == "raid9", "click casting, left = Target: the plain click is not the raw target")
    for _, m in ipairs(MODS) do
        local mt, mu, _, mhow = Resolve(f, m, "1")
        check(mt == "target" and mhow == "proxy" and mu == "raid9", "click casting, left = Target: " .. m .. "left does not target")
        local rt, _, _, rhow = Resolve(f, m, "2")
        check(rt == "togglemenu" and rhow == "proxy", "click casting, right = Menu: " .. m .. "right does not open the menu")
    end
    -- a binding of its own wins over the wildcard
    f = Apply({ Entry("", 1, "target"), Entry("SHIFT-", 1, "spell") })
    check(Resolve(f, "shift-", "1") == "spell", "a Shift + left binding of its own loses to the Target wildcard")
    check(select(4, Resolve(f, "ctrl-", "1")) == "proxy", "an unbound Ctrl + left does not target beside a bound Shift + left")
    -- left bound to something else: no wildcard, a modified click does nothing
    f = Apply({ Entry("", 1, "spell"), Entry("", 2, "togglemenu") })
    check(f.attrs["*type1"] == nil and f.attrs["*macrotext1"] == nil, "left bound to a spell keeps the Target wildcard")
    check(Resolve(f, "shift-", "1") == nil, "left bound to a spell: Shift + left still acts")
    check(Resolve(f, "", "1") == "spell", "left bound to a spell does not cast")
    -- left not bound at all: inert, with no wildcard
    f = Apply({ Entry("", 2, "togglemenu") })
    check(f.attrs["type1"] == "none" and f.attrs["*type1"] == nil, "an unbound left click is not inert")
    check(Resolve(f, "shift-", "1") == nil, "an unbound left click: Shift + left still acts")
    -- Target only out of combat: the wildcard would target in combat, so it goes
    f = Apply({ Entry("", 1, "target", true) })
    check(f.attrs["*type1"] == nil and f.attrs["*macrotext1"] == nil, "left = Target (Out of Combat Only) keeps a wildcard that targets in combat")
    -- right: the menu wildcard only while plain right is Menu
    f = Apply({ Entry("", 1, "target"), Entry("", 2, "spell") })
    check(f.attrs["*type2"] == nil and f.attrs["*macrotext2"] == nil, "right bound to a spell keeps the menu wildcard")
    f = Apply({ Entry("", 1, "target") })
    check(f.attrs["type2"] == "none" and f.attrs["*type2"] == nil, "an unbound right click is not inert")
    f = Apply({ Entry("", 1, "target"), Entry("", 2, "togglemenu", true) })
    check(f.attrs["*type2"] == nil, "right = Menu (Out of Combat Only) keeps a wildcard that opens the menu in combat")

    -- target bindings read the proxy's macrotext
    f = NewSecure(nil)
    f:SetAttribute("unit", "raid9")
    SetClickAttr(f, Button("SHIFT-", 1), "target")
    check(f.attrs["shift-type1"] == "macro" and f.attrs["shift-macrotext1"] ~= nil
        and f.attrs["shift-macrotext1"] == "/click " .. tostring((select(5, Resolve(f, "shift-", "1")) or {}).name),
        "a Shift + left Target binding does not click the frame's proxy")
    SetClickAttr(f, Button("", 3), "target")
    check(f.attrs["type3"] == "macro" and f.attrs["macrotext3"] == f.attrs["shift-macrotext1"], "a middle-click Target binding does not click the frame's proxy")
    SetClickAttr(f, Button("", 1), "target")
    check(f.attrs["type1"] == "target" and f.attrs["macrotext1"] == nil, "a plain left Target binding is not the raw target")
    SetKeyAttr(f, 4, "target")
    check(f.attrs["type-eui_4"] == "macro" and f.attrs["macrotext-eui_4"] == f.attrs["shift-macrotext1"], "a Target keybind does not click the frame's proxy")
    SetClickAttr(f, Button("CTRL-", 1), "target", nil, nil, true)
    check(drivers["ctrl-type1"] == "[combat] none; macro" and f.attrs["ctrl-macrotext1"] == f.attrs["shift-macrotext1"],
        "an Out of Combat Only Target binding is not gated by its combat driver")
end

-------------------------------------------------------------------------------
-- 4. the callers and the guards
-------------------------------------------------------------------------------
do
    check(CC:find('"/click " .. proxy', 1, true) == nil, "click casting builds a proxy macro by hand")
    local RF = ReadSource("EllesmereUIRaidFrames/EllesmereUIRaidFrames.lua")
    local UF = ReadSource("EllesmereUIUnitFrames/EllesmereUIUnitFrames.lua")
    local function Guard(src)
        return src:match("\n(if not %(EllesmereUI and [^\n]*stale%-parent guard[^\n]*)") or ""
    end
    check(Guard(RF):find(" and EllesmereUI.SetLeftClickTarget", 1, true) ~= nil, "the Raid Frames guard does not list SetLeftClickTarget")
    check(Guard(RF):find(" and EllesmereUI.GetSecureTargetMacro", 1, true) ~= nil, "the Raid Frames guard does not list GetSecureTargetMacro (click casting calls it)")
    check(Guard(UF):find(" and EllesmereUI.SetLeftClickTarget", 1, true) ~= nil, "the Unit Frames guard does not list SetLeftClickTarget")
    -- every unit button takes its left click from the helper
    for _, name in ipairs({ "EllesmereUIRaidFrames/EUI_RaidFrames_Style.lua", "EllesmereUIRaidFrames/EUI_RaidFrames_BossFrames.lua",
            "EllesmereUIRaidFrames/EUI_RaidFrames_PetFrames.lua", "EllesmereUIRaidFrames/EUI_RaidFrames_PartyTargets.lua",
            "EllesmereUIRaidFrames/EUI_RaidFrames_DebuffManager.lua", "EllesmereUIUnitFrames/EUI_UnitFrames_Engine.lua",
            "EllesmereUI_SharedHelpers.lua" }) do
        local src = ReadSource(name)
        check(src:find("SetLeftClickTarget(", 1, true) ~= nil, name .. " does not use the left-click helper")
        check(src:find('"*type1", "target"', 1, true) == nil and src:find('"type1", "target"', 1, true) == nil, name .. " writes a raw left-click target")
    end
end

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print(("PASS test_unit_left_click_target (%d checks)"):format(count))
