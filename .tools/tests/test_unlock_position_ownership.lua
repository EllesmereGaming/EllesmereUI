-- Run from the repository root: lua5.1 .tools/tests/test_unlock_position_ownership.lua
local function block(path, first, last)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    local start = assert(source:find(first, 1, true))
    local finish = assert(source:find(last, start + #first, true))
    return source:sub(start, finish - 1)
end

local function frame()
    local f = { width = 270, height = 24 }
    function f:GetEffectiveScale() return 1 end
    function f:GetWidth() return self.width end
    function f:GetHeight() return self.height end
    function f:IsProtected() return false end
    function f:ClearAllPoints() self.point = nil end
    function f:SetPoint(...) self.point = { ... } end
    return f
end

local UM, MatchH, elements, anchorDB = {}, {}, {}, {}
local root, anchor, member, independent = frame(), frame(), frame(), frame()
local combat = false
local position = { point = "CENTER", relPoint = "CENTER", x = 0, y = -180 }
local groupPoint = { "TOP", anchor, "BOTTOM", 0, -2 }
local env = setmetatable({
    UM = UM, MatchH = MatchH, registeredElements = elements, UIParent = root,
    floor = math.floor,
    EllesmereUI = {
        PP = { IsNum = function(v) return type(v) == "number" end },
        GetMatchExtra = function() end,
        ClearFramePoints = function(f) f:ClearAllPoints() end,
        SetFramePoint = function(f, ...) f:SetPoint(...) end,
    },
    GetAnchorDB = function() return anchorDB end,
    GetBarGrowDirActual = function() end,
    ExtraAnchorOffset = function() return 0, 0 end,
    InCombatLockdown = function() return combat end,
}, { __index = _G })

local function loadBlock(source)
    local chunk = assert(loadstring(source))
    setfenv(chunk, env)
    chunk()
end

loadBlock(block(arg[1] or "EUI_UnlockMode_Positions.lua",
    "UM.ApplyCenterPosition = function", "\nend") .. "\nend")
loadBlock(block("EUI_UnlockMode_Anchors.lua",
    "function MatchH.ApplyWidthMatch", "\nfunction MatchH.ApplyHeightMatch"))
loadBlock(block("EUI_UnlockMode_Anchors.lua",
    "function MatchH.ApplyHeightMatch", "\n--"))

elements.anchor = { getFrame = function() return anchor end,
    isAnchored = function() return false end }
elements.member = { getFrame = function() return member end,
    isAnchored = function(key) assert(key == "member"); return true end,
    loadPosition = function() return position end,
    setWidth = function(_, width) member.width = width end,
    setHeight = function(_, height) member.height = height end }
elements.independent = { getFrame = function() return independent end }
elements.player = { getFrame = function() return root end,
    getSize = function() return 300, 30 end }
function UM.GetBarFrame(key) return elements[key].getFrame() end

-- A match must resize the member without restoring the shared group origin.
for _, inCombat in ipairs({ false, true }) do
    combat = inCombat
    member.point = groupPoint
    MatchH.ApplyWidthMatch("member", "player")
    assert(member.width == 300, "width match must still apply")
    assert(member.point == groupPoint, "width match broke the group anchor")
    MatchH.ApplyHeightMatch("member", "player")
    assert(member.height == 30, "height match must still apply")
    assert(member.point == groupPoint, "height match broke the group anchor")
    assert(UM.ApplyCenterPosition("member", position) == true)
    assert(member.point == groupPoint, "saved position broke the group anchor")
end

-- Group anchors and independent bars still accept saved positions.
for _, key in ipairs({ "anchor", "independent" }) do
    assert(UM.ApplyCenterPosition(key, position) == true)
    local point = UM.GetBarFrame(key).point
    assert(point[1] == "CENTER" and point[2] == root and point[3] == "CENTER")
    assert(point[4] == position.x and point[5] == position.y)
end

-- Existing unlock relationships and invalid-position return values are preserved.
anchorDB.independent = { target = "player" }
local original = independent.point
assert(UM.ApplyCenterPosition("independent", position) == true)
assert(independent.point == original)
assert(UM.ApplyCenterPosition("member", nil) == false)
assert(UM.ApplyCenterPosition("member", { point = "TOP" }) == false)
print("test_unlock_position_ownership: ok")
