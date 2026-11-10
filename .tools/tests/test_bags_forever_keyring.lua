-- Stub harness: WoW Forever's keyring window with EllesmereUI Bags on.
-- Cuts the hidden Blizzard bag holder, KillBlizzard and the ToggleBag post-hook
-- out of EUI_Bags_Start.lua and plays keyring clicks over a model of Blizzard's
-- ToggleBag_Individual and UpdateContainerFrameAnchors (ContainerFrame.lua):
-- the first shown bag frame is pinned BOTTOMRIGHT to its own parent, the others
-- stack on the one before. Blizzard opens the keyring while its frame still sits
-- in our holder, and our hook lets it out afterwards, so the frame keeps that pin.
--   the holder has a rect (UIParent's), so the let-out keyring window resolves
--     to a spot on screen, also when one of Blizzard's own bag frames is still
--     "shown" inside the holder ahead of it
--   a second click closes it and parks it back in the holder
--   KillBlizzard leaves a shown keyring out; every other frame goes in
--   any other bag toggles our bag window; retail has no keyring exemption
-- The model is this file's reading of the client, not the client: a frame
-- anchored to a frame without points has no position, so it draws nowhere.
--   lua .tools/tests/test_bags_forever_keyring.lua        (from the repository root)
local TARGET = KR_TARGET or "EllesmereUIBags/EUI_Bags_Start.lua"

local fails, count, quiet = 0, 0, false
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        if not quiet then print("  FAIL: " .. msg) end
    end
end

local fh = assert(io.open(TARGET, "rb"))
local src = fh:read("*a"):gsub("\r\n", "\n")
fh:close()

local function Cut(text, from, to, what)
    local a = assert(text:find(from, 1, true), what .. ": start not found")
    local b, e = text:find(to, a, true)
    assert(b, what .. ": end not found")
    return text:sub(a, e)
end

local BLOCK = Cut(src, '    local _blizzBagHidden = CreateFrame("Frame")',
    "        SmartToggleBags()\n    end)\n", "holder and ToggleBag hook")

-------------------------------------------------------------------------------
-- Frame model
-------------------------------------------------------------------------------
local SCREEN_W, SCREEN_H = 1920, 1080
local BAG_W, BAG_H = 200, 150
local XOFF, YOFF, SPACING = 30, 85, 8
local KEYRING = -1

local Frame = {}
Frame.__index = Frame

local function NewFrame(name, parent, shown)
    return setmetatable({ name = name, parent = parent, shown = shown ~= false, points = {},
        onHide = {}, w = 0, h = 0 }, Frame)
end

local UIParent = NewFrame("UIParent", nil, true)

function Frame:IsShown() return self.shown end
function Frame:IsVisible()
    if not self.shown then return false end
    if self.parent then return self.parent:IsVisible() end
    return true
end
local function FireHide(self)
    for _, fn in ipairs(self.onHide) do fn(self) end
end
function Frame:Show() self.shown = true end
function Frame:Hide()
    local was = self:IsVisible()
    self.shown = false
    if was then FireHide(self) end
end
function Frame:GetParent() return self.parent end
function Frame:SetParent(p)
    local was = self:IsVisible()
    self.parent = p
    if was and not self:IsVisible() then FireHide(self) end
end
function Frame:ClearAllPoints() self.points = {} end
function Frame:SetPoint(point, rel, relPoint, x, y)
    self.points[#self.points + 1] = { point = point, rel = rel, relPoint = relPoint or point, x = x or 0, y = y or 0 }
end
function Frame:SetAllPoints(rel)
    self.points = {
        { point = "TOPLEFT", rel = rel, relPoint = "TOPLEFT", x = 0, y = 0 },
        { point = "BOTTOMRIGHT", rel = rel, relPoint = "BOTTOMRIGHT", x = 0, y = 0 },
    }
end
function Frame:HookScript(script, fn)
    assert(script == "OnHide", "only OnHide is modelled")
    self.onHide[#self.onHide + 1] = fn
end
function Frame:MatchesBagID(id) return self.bagID == id end

local function Corner(l, b, w, h, point)
    local x = point:find("RIGHT") and l + w or (point:find("LEFT") and l or l + w / 2)
    local y = point:find("TOP") and b + h or (point:find("BOTTOM") and b or b + h / 2)
    return x, y
end

-- left, bottom, width, height on screen, or nil when the frame has no position.
local function Rect(f, depth)
    depth = depth or 0
    assert(depth < 20, "anchor loop")
    if f == UIParent then return 0, 0, SCREEN_W, SCREEN_H end
    local pts = f.points
    if #pts == 0 then return nil end
    if #pts == 2 then
        -- SetAllPoints: the rect of the frame it spans
        assert(pts[1].rel == pts[2].rel, "two-point anchors are SetAllPoints only here")
        return Rect(pts[1].rel, depth + 1)
    end
    local p = pts[1]
    local l, b, w, h = Rect(p.rel, depth + 1)
    if not l then return nil end
    local ax, ay = Corner(l, b, w, h, p.relPoint)
    ax, ay = ax + p.x, ay + p.y
    local cx, cy = Corner(0, 0, f.w, f.h, p.point)
    return ax - cx, ay - cy, f.w, f.h
end

-------------------------------------------------------------------------------
-- Blizzard's container frames and toggles
-------------------------------------------------------------------------------
local W

local function GetShownFrameForID(id)
    for i, f in ipairs(W.frames) do
        if f.shown and (not id or f:MatchesBagID(id)) then return f, i end
    end
end

-- UpdateContainerFrameAnchors, without the column wrap.
local function UpdateAnchors()
    local prev, index = nil, 0
    for _, f in ipairs(W.frames) do
        if f.shown then
            index = index + 1
            f:ClearAllPoints()
            if index == 1 then
                f:SetPoint("BOTTOMRIGHT", f:GetParent(), "BOTTOMRIGHT", -XOFF, YOFF)
            else
                f:SetPoint("BOTTOMRIGHT", prev, "TOPRIGHT", 0, SPACING)
            end
            prev = f
        end
    end
end

-- ToggleBag(id): Blizzard's body (ToggleBag_Individual for a held bag), then the post-hooks.
local function ToggleBag(id)
    local shown = GetShownFrameForID(id)
    if shown then
        shown:Hide()
    else
        local open
        for _, f in ipairs(W.frames) do
            if not f.shown then open = f; break end
        end
        open.bagID = id
        open:Show()
        UpdateAnchors()
    end
    if W.hooks.ToggleBag then W.hooks.ToggleBag(id) end
end

-- CloseAllBags, as the Escape key or a closed merchant runs it.
local function CloseAllBags()
    for _, f in ipairs(W.frames) do
        if f.shown then f:Hide() end
    end
end

local function Load(block, forever)
    W = { hooks = {}, smart = 0, frames = {} }
    W.container = NewFrame("ContainerFrameContainer", UIParent, true)
    W.container:SetAllPoints(UIParent)
    local env = {
        UIParent = UIParent, ContainerFrameContainer = W.container,
        EUI = { IS_FOREVER = forever },
        Enum = { BagIndex = { Keyring = KEYRING, Backpack = 0 } },
        setmetatable = setmetatable, ipairs = ipairs, pairs = pairs,
        ContainerFrameUtil_GetShownFrameForID = GetShownFrameForID,
        SmartToggleBags = function() W.smart = W.smart + 1 end,
    }
    env._G = env
    env.CreateFrame = function(kind, name, parent)
        assert(kind == "Frame" and name == nil and parent == nil, "the holder is a nameless parentless frame")
        local f = NewFrame("holder", nil, true)
        W.holder = f
        return f
    end
    env.hooksecurefunc = function(name, fn)
        assert(type(name) == "string" and not W.hooks[name], "one post-hook per global")
        W.hooks[name] = fn
    end
    for i = 1, 7 do
        local f = NewFrame("ContainerFrame" .. i, W.container, false)
        f.w, f.h = BAG_W, BAG_H
        W.frames[i] = f
        env["ContainerFrame" .. i] = f
    end
    W.combined = NewFrame("ContainerFrameCombinedBags", W.container, false)
    env.ContainerFrameCombinedBags = W.combined
    local chunk = assert(loadstring(block .. "\nreturn _blizzBagHidden, KillBlizzard\n", "=EUI_Bags_Start.lua"))
    setfenv(chunk, env)
    local holder, kill = chunk()
    assert(holder == W.holder, "the holder is the frame the block made")
    W.kill = kill
end

local function OnScreen(f)
    local l, b, w, h = Rect(f)
    return l ~= nil and f:IsVisible() and l >= 0 and b >= 0 and l + w <= SCREEN_W and b + h <= SCREEN_H, l, b
end

local function Scenarios(block)
    ---------------------------------------------------------------------------
    -- 1. WoW Forever: the keyring window opens on screen and closes again
    ---------------------------------------------------------------------------
    Load(block, true)
    check(not W.holder:IsVisible(), "the holder is hidden")
    check(Rect(W.holder) ~= nil, "the holder has a rect")
    local parked = true
    for _, f in ipairs(W.frames) do parked = parked and f.parent == W.holder end
    check(parked and W.combined.parent == W.holder, "every Blizzard bag frame starts in the holder")

    ToggleBag(KEYRING)
    local kr = W.frames[1]
    check(kr.bagID == KEYRING and kr.parent == W.container, "the keyring frame is let out of the holder")
    local ok, l, b = OnScreen(kr)
    check(ok, "the keyring window has a position on screen")
    check(ok and l + BAG_W == SCREEN_W - XOFF and b == YOFF, "at Blizzard's bottom-right spot")
    check(W.smart == 0, "the keyring click leaves our bag window alone")

    ToggleBag(KEYRING)
    check(not kr.shown and kr.parent == W.holder, "a second click closes it and parks it in the holder")
    check(W.smart == 0, "still without touching our bag window")

    ToggleBag(KEYRING)
    check(kr.shown and kr.parent == W.container and (OnScreen(kr)), "it opens again on screen")
    check(#kr.onHide == 1, "the frame is hooked once, however often it opens")
    CloseAllBags()
    check(kr.parent == W.holder, "a close by Blizzard's CloseAllBags parks it too")

    ---------------------------------------------------------------------------
    -- 2. One of Blizzard's own bag frames still "shown" inside the holder
    --    (opened by its own toggle, invisible there): the keyring stacks on it
    ---------------------------------------------------------------------------
    Load(block, true)
    local backpack = W.frames[1]
    backpack.bagID = 0
    backpack:Show()
    UpdateAnchors()
    check(not backpack:IsVisible(), "the stray backpack frame stays invisible in the holder")
    ToggleBag(KEYRING)
    kr = W.frames[2]
    ok, l, b = OnScreen(kr)
    check(kr.bagID == KEYRING and ok, "the keyring stacked on it still has a position on screen")
    check(ok and b == YOFF + BAG_H + SPACING, "above the stray frame's spot")

    ---------------------------------------------------------------------------
    -- 3. KillBlizzard (run as bags auto-open) leaves a shown keyring out
    ---------------------------------------------------------------------------
    Load(block, true)
    ToggleBag(KEYRING)
    kr = W.frames[1]
    W.frames[3]:SetParent(W.container)
    W.kill()
    check(kr.parent == W.container and kr:IsVisible(), "a shown keyring stays out")
    check(W.frames[3].parent == W.holder and W.combined.parent == W.holder, "every other frame goes back in")
    ToggleBag(KEYRING)
    W.kill()
    check(kr.parent == W.holder, "a closed keyring goes back in")

    ---------------------------------------------------------------------------
    -- 4. Any other bag toggles our bag window
    ---------------------------------------------------------------------------
    Load(block, true)
    W.hooks.ToggleBag(1)
    check(W.smart == 1, "bag 1 toggles our bag window")

    ---------------------------------------------------------------------------
    -- 5. Retail: no keyring exemption
    ---------------------------------------------------------------------------
    Load(block, false)
    local f = W.frames[1]
    f.bagID = KEYRING
    f:Show()
    f:SetParent(W.container)
    W.kill()
    check(f.parent == W.holder, "retail parks every frame")
    W.hooks.ToggleBag(KEYRING)
    check(W.smart == 1, "retail sends every bag id to our bag window")
end

Scenarios(BLOCK)
if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end

-- Mutants: each must break a scenario.
local function Swap(text, from, to)
    local s1, s2 = text:find(from, 1, true)
    assert(s1, "mutant text not found: " .. from)
    return text:sub(1, s1 - 1) .. to .. text:sub(s2 + 1)
end
local MUTANTS = {
    { "the holder has no rect", "    _blizzBagHidden:SetAllPoints(UIParent)\n", "" },
    { "the keyring is not let out", "f:SetParent(ContainerFrameContainer or UIParent)", "f:SetParent(_blizzBagHidden)" },
    { "a closed keyring is not parked", "if not self:IsShown() then self:SetParent(_blizzBagHidden) end", "" },
    { "KillBlizzard takes a shown keyring", "if f and not IsKeyringFrame(f) then", "if f then" },
    { "the keyring click toggles our bag window", "            return\n        end\n        SmartToggleBags()", "        end\n        SmartToggleBags()" },
}
local total = count
quiet = true
for _, m in ipairs(MUTANTS) do
    local mb = Swap(BLOCK, m[2], m[3])
    fails, count = 0, 0
    local okRun = pcall(Scenarios, mb)
    if okRun and fails == 0 then error("mutant survived: " .. m[1]) end
end
print(("PASS test_bags_forever_keyring (%d checks, %d mutants killed)"):format(total, #MUTANTS))
