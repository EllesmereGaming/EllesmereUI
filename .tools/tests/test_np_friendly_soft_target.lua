-- Stub harness: the game's soft-target (interact) icon on friendly nameplates.
-- Cuts the friendly path's SuppressBlizzardUF / RestoreBlizzardUF out of
-- EllesmereUINameplatesFriendly.lua and the enemy path's HideBlizzardFrame /
-- ns.NP_ReclaimBlizzardFrame out of EUI_Nameplates_Plate.lua, and drives them
-- on fake frames. While our friendly plate hides Blizzard's UnitFrame, the
-- icon (UnitFrame.SoftTargetFrame) stays on the nameplate so it still shows;
-- the restore hands it back to the UnitFrame; a pooled UnitFrame an enemy plate
-- held on another nameplate ends with the icon on its current one.
--   lua .tools/tests/test_np_friendly_soft_target.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return (src:gsub("\r\n", "\n"))
end

local function Cut(src, from, lastFunc, label)
    local a = assert(src:find(from, 1, true), label .. ": start missing")
    local f = assert(src:find(lastFunc, a, true), label .. ": " .. lastFunc .. " missing")
    local e = assert(src:find("\nend\n", f, true), label .. ": end missing")
    return src:sub(a, e + 4)
end

local FRIENDLY = Cut(ReadSource("EllesmereUINameplates/EllesmereUINameplatesFriendly.lua"),
    "local hookedUFs = {}", "local function RestoreBlizzardUF(unit)", "friendly")
local PLATE = Cut(ReadSource("EllesmereUINameplates/EUI_Nameplates_Plate.lua"),
    "local hookedUFs = {}", "function ns.NP_ReclaimBlizzardFrame(uf)", "plate")

-------------------------------------------------------------------------------
--  Fake frames: parents, children in order, alpha, shown, events
-------------------------------------------------------------------------------
local Frame = {}
Frame.__index = Frame

local function NewFrame(name, parent)
    local f = setmetatable({ _name = name, _children = {}, _alpha = 1, _shown = true, _events = {} }, Frame)
    if parent then f:SetParent(parent) end
    return f
end
function Frame:SetParent(p)
    local old = self._parent
    if old == p then return end
    if old then
        for i = #old._children, 1, -1 do
            if old._children[i] == self then table.remove(old._children, i) end
        end
    end
    self._parent = p
    if p then p._children[#p._children + 1] = self end
end
function Frame:GetParent() return self._parent end
function Frame:GetNumChildren() return #self._children end
function Frame:GetChildren() return unpack(self._children) end
function Frame:SetAlpha(a) self._alpha = a end
function Frame:GetAlpha() return self._alpha end
function Frame:Show() self._shown = true end
function Frame:Hide() self._shown = false end
function Frame:IsForbidden() return false end
function Frame:IsProtected() return false end
function Frame:UnregisterAllEvents() for k in pairs(self._events) do self._events[k] = nil end end
function Frame:RegisterEvent(e) self._events[e] = true end
function Frame:RegisterUnitEvent(e) self._events[e] = true end

local function hooksecurefunc(obj, method, fn)
    local orig = obj[method]
    obj[method] = function(...)
        local r = { orig(...) }
        fn(...)
        return unpack(r)
    end
end
local function wipe(t) for k in pairs(t) do t[k] = nil end return t end

local ATTACKABLE = {}
local function UnitCanAttack(_, unit) return ATTACKABLE[unit] == true end
local function UnitExists() return true end
local function CreateFrame() return NewFrame("created") end

local function Build(friendlySrc)
    local ns = { plates = {} }
    local hidden = NewFrame("hiddenFrame")
    hidden:Hide()
    local plateChunk = assert(loadstring(
        "local ns, CreateFrame, hooksecurefunc, UnitCanAttack, issecretvalue, UnitExists, wipe = ...\n"
        .. PLATE .. "\nreturn HideBlizzardFrame, npOffscreenParent\n", "=EUI_Nameplates_Plate.lua"))
    local HideBlizzardFrame, offscreen = plateChunk(ns, CreateFrame, hooksecurefunc, UnitCanAttack, nil, UnitExists, wipe)
    local friendlyChunk = assert(loadstring(
        "local ns, hiddenFrame, hooksecurefunc = ...\n"
        .. friendlySrc .. "\nreturn SuppressBlizzardUF, RestoreBlizzardUF\n", "=EllesmereUINameplatesFriendly.lua"))
    local Suppress, Restore = friendlyChunk(ns, hidden, hooksecurefunc)
    return { ns = ns, hidden = hidden, offscreen = offscreen, HideBlizzardFrame = HideBlizzardFrame,
             Suppress = Suppress, Restore = Restore }
end

-- A Blizzard nameplate UnitFrame on base frame `base`, with the children our code
-- touches. noIcon: a client whose UnitFrame has no SoftTargetFrame.
local function NewUnitFrame(base, unit, noIcon)
    local uf = NewFrame("UnitFrame", base)
    base.UnitFrame = uf
    uf.unit = unit
    uf.healthBar = NewFrame("healthBar", uf)
    uf.AurasFrame = NewFrame("AurasFrame", uf)
    uf.WidgetContainer = NewFrame("WidgetContainer", uf)
    uf.castBar = NewFrame("castBar", uf)
    if not noIcon then
        uf.SoftTargetFrame = NewFrame("SoftTargetFrame", uf)
        uf.SoftTargetFrame.Icon = NewFrame("Icon")
    end
    return uf
end

local function Name(f) return f and f._name or "nil" end
local function Expect(frame, parent, what)
    assert(frame:GetParent() == parent,
        what .. ": parent is " .. Name(frame:GetParent()) .. ", expected " .. Name(parent))
end

local function Scenarios(T)
    -- 1. Friendly suppress keeps the icon on the nameplate; restore hands it back.
    local B = NewFrame("nameplateB")
    local uf = NewUnitFrame(B, "nameplate2")
    T.Suppress("nameplate2", B)
    Expect(uf, T.hidden, "suppressed UnitFrame")
    Expect(uf.WidgetContainer, B, "suppressed WidgetContainer")
    Expect(uf.SoftTargetFrame, B, "suppressed icon")
    assert(uf:GetAlpha() == 0, "suppressed UnitFrame alpha")
    T.Restore("nameplate2")
    Expect(uf, B, "restored UnitFrame")
    Expect(uf.WidgetContainer, uf, "restored WidgetContainer")
    Expect(uf.SoftTargetFrame, uf, "restored icon")
    assert(uf:GetAlpha() == 1, "restored UnitFrame alpha")

    -- 2. A pooled UnitFrame an enemy plate held on nameplate A, acquired as a
    --    friendly NPC on nameplate B: the icon ends on B.
    local A, B2 = NewFrame("nameplateA"), NewFrame("nameplateB2")
    local pooled = NewUnitFrame(A, "nameplate3")
    ATTACKABLE.nameplate3 = true
    T.ns.plates.nameplate3 = {}
    T.HideBlizzardFrame(A, "nameplate3")
    Expect(pooled.SoftTargetFrame, A, "enemy: icon")
    Expect(pooled.healthBar, T.offscreen, "enemy: parked child")
    T.ns.plates.nameplate3 = nil
    A.UnitFrame = nil
    pooled:SetParent(B2)
    B2.UnitFrame = pooled
    pooled.unit = "nameplate4"
    T.Suppress("nameplate4", B2)
    Expect(pooled.SoftTargetFrame, B2, "pooled friendly: icon")
    Expect(pooled.WidgetContainer, B2, "pooled friendly: WidgetContainer")
    Expect(pooled.healthBar, pooled, "pooled friendly: the parked child is handed back")
    Expect(pooled.AurasFrame, pooled, "pooled friendly: AurasFrame handed back")
    -- The enemy reclaim that runs after the friendly hook finds nothing left to take.
    T.ns.NP_ReclaimBlizzardFrame(pooled)
    Expect(pooled.SoftTargetFrame, B2, "after the enemy reclaim: icon")
    -- The enemy path's icon hook never hides it for a unit that cannot be attacked.
    local icon = pooled.SoftTargetFrame.Icon
    icon:Show()
    assert(icon._shown, "the friendly NPC's icon was hidden")
    T.Restore("nameplate4")
    Expect(pooled.SoftTargetFrame, pooled, "pooled restored: icon")

    -- 3. A UnitFrame without the icon: no error.
    local C = NewFrame("nameplateC")
    local bare = NewUnitFrame(C, "nameplate5", true)
    T.Suppress("nameplate5", C)
    T.Restore("nameplate5")
    Expect(bare, C, "no-icon UnitFrame restored")
end

Scenarios(Build(FRIENDLY))

-------------------------------------------------------------------------------
--  Mutants: each new line dropped must break a scenario
-------------------------------------------------------------------------------
local function Drop(src, block)
    local a, b = src:find(block, 1, true)
    assert(a, "mutant text not found: " .. block)
    return src:sub(1, a - 1) .. src:sub(b + 1)
end
local MUTANTS = {
    { "suppress leaves the icon under the hidden UnitFrame",
      "    if uf.SoftTargetFrame then\n        uf.SoftTargetFrame:SetParent(nameplate)\n    end\n" },
    { "restore leaves the icon on the nameplate",
      "    if uf.SoftTargetFrame then\n        uf.SoftTargetFrame:SetParent(uf)\n    end\n" },
}
for _, m in ipairs(MUTANTS) do
    ATTACKABLE = {}
    local ok = pcall(Scenarios, Build(Drop(FRIENDLY, m[2])))
    assert(not ok, "mutant survived: " .. m[1])
end

print("PASS: friendly suppress / restore keep the soft-target icon, the pooled enemy frame case, 2 mutants killed")
