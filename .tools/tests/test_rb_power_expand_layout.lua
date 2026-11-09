-- Stub harness: the Resource Bars power bar's unlock position with Expand Power
-- Bar if No Resource (website bug #170, PR #3177). Its loadPos reports the stored
-- CENTER plus the expand shift (Unlock Mode's resize re-apply places the bar as
-- the build does); Spec and Conditional Overrides layout layers must bank and
-- restore the STORED position, through the element's loadRawPos / saveRawPos, or
-- a layer harvested while the bar is expanded saves the shift into the stored
-- position and the bar drifts on spec swaps. Cuts MakePosHelpers and the power
-- bar's raw pair out of EUI_ResourceBars_Anchors.lua.
--   lua .tools/tests/test_rb_power_expand_layout.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return (src:gsub("\r\n", "\n"))
end
local ANCHORS = ReadSource("EllesmereUIResourceBars/EUI_ResourceBars_Anchors.lua")
local LAYERS = ReadSource("EUI_SpecOverrides_Layers.lua")
local CORE = ReadSource("EllesmereUI.lua")

-- The layer code takes the raw route when an element offers it, and the element
-- factory maps the opts onto it.
assert(LAYERS:find("if elem.loadRawPosition and elem.saveRawPosition then", 1, true), "the layer harvest no longer prefers the raw position")
assert(LAYERS:find("if e.rawPos and elem.saveRawPosition", 1, true), "the layer apply no longer restores the raw position")
assert(CORE:find("loadRawPosition   = opts.loadRawPos,", 1, true) and CORE:find("saveRawPosition   = opts.saveRawPos,", 1, true),
    "MakeUnlockElement no longer maps loadRawPos / saveRawPos")

local h0 = assert(ANCHORS:find("    local function MakePosHelpers(", 1, true), "MakePosHelpers missing")
local h1 = assert(ANCHORS:find("\n    end\n", h0, true), "end of MakePosHelpers missing")
local HELPERS = ANCHORS:sub(h0, h1 + 8)
local p0 = assert(ANCHORS:find('key = "ERB_Power"', 1, true), "the power bar element is missing")
local r0 = ANCHORS:find("            loadRawPos = function()", p0, true)
local RAW
if r0 then
    local r1 = assert(ANCHORS:find("ns.ERB_GroupDirty()\n            end,", r0, true), "end of saveRawPos missing")
    RAW = ANCHORS:sub(r0, r1 + #"ns.ERB_GroupDirty()\n            end,")
end

local function Build(raw)
    local T = { primary = { unlockPos = { point = "CENTER", relPoint = "CENTER", x = 0, y = -74 } }, shift = 0 }
    local frame = { ClearAllPoints = function() end, SetPoint = function() end }
    local ns = { ERB_GroupDirty = function() end }
    local src = "local EllesmereUI, ns, UIParent, T, frame = ...\n"
        .. "local function S() return T.primary end\n"
        .. HELPERS .. "\n"
        .. "local save, load = MakePosHelpers(S, function() return frame end, 0, -74, function() return T.shift end)\n"
        .. "return { savePos = save, loadPos = load" .. (raw and (",\n" .. raw) or "") .. " }\n"
    local elem = assert(loadstring(src, "=EUI_ResourceBars_Anchors.lua"))({ _unlockActive = false }, ns, {}, T, frame)
    return elem, T
end

-- The layer's two halves, as EUI_SpecOverrides_Layers.lua runs them: the raw route
-- when the element offers it, else loadPosition / savePosition.
local function Harvest(elem)
    if elem.loadRawPos and elem.saveRawPos then
        local p = elem.loadRawPos()
        local e = {}
        for k, v in pairs(p) do e[k] = v end
        e.rawPos = true
        return e
    end
    local p = elem.loadPos("ERB_Power")
    return { point = p.point, relPoint = p.relPoint or p.point, x = p.x, y = p.y }
end
local function Apply(elem, e)
    if e.rawPos and elem.saveRawPos then elem.saveRawPos("ERB_Power", e); return end
    local cur = elem.loadPos("ERB_Power")
    if not (cur.point == e.point and cur.x == e.x and cur.y == e.y) then
        elem.savePos("ERB_Power", e.point, e.relPoint, e.x, e.y)
    end
end

local function Scenarios(elem, T)
    -- loadPos: the stored CENTER plus the shift; another point is left alone.
    T.shift = 10
    assert(elem.loadPos("ERB_Power").y == -64, "loadPos does not add the expand shift")
    T.primary.unlockPos.point, T.primary.unlockPos.relPoint = "TOPLEFT", "TOPLEFT"
    assert(elem.loadPos("ERB_Power").y == -74, "loadPos shifted a non-CENTER point")
    T.primary.unlockPos.point, T.primary.unlockPos.relPoint = "CENTER", "CENTER"

    -- A layer harvested while expanded, applied on a spec with a class resource
    -- (no shift), and back: the stored position never moves.
    local layer = Harvest(elem)
    T.shift = 0
    Apply(elem, layer)
    assert(T.primary.unlockPos.y == -74, "the stored y drifted to " .. tostring(T.primary.unlockPos.y))
    layer = Harvest(elem)
    T.shift = 10
    Apply(elem, layer)
    assert(T.primary.unlockPos.y == -74, "the stored y drifted to " .. tostring(T.primary.unlockPos.y))

    -- The raw pair round-trips the stored table exactly.
    local raw = elem.loadRawPos()
    assert(raw and raw.point == "CENTER" and raw.relPoint == "CENTER" and raw.x == 0 and raw.y == -74, "loadRawPos")
    elem.saveRawPos("ERB_Power", { point = "BOTTOM", x = 5, y = 7 })
    local s = T.primary.unlockPos
    assert(s.point == "BOTTOM" and s.relPoint == "BOTTOM" and s.x == 5 and s.y == 7, "saveRawPos")
    T.primary.unlockPos = nil
    assert(elem.loadRawPos() == nil, "loadRawPos with no stored position")
end

assert(RAW, "the power bar has no loadRawPos / saveRawPos")
Scenarios(Build(RAW))

-- Mutant: without the raw pair the layer banks the shifted loadPos and the bar drifts.
assert(not pcall(Scenarios, Build(nil)), "mutant survived: the layer round trip without the raw pair")

print("PASS: the power bar's layout layers keep the stored position with Expand Power Bar if No Resource")
