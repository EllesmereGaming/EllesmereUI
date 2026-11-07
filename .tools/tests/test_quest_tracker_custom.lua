-- Stub harness: loads the Quest Tracker loader and its WoW Forever custom
-- tracker outside the game and checks which tracker a profile gets, where the
-- custom one starts, how its width and height are set and which edge it keeps
-- for each grow direction.
--   lua .tools/tests/test_quest_tracker_custom.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return src
end
local LOADER_SRC = ReadSource("EllesmereUIQuestTracker/EllesmereUIQuestTracker.lua")
local CUSTOM_SRC = ReadSource("EllesmereUIQuestTracker/EllesmereUIQuestTracker_Custom.lua")

-- The widget methods the two files call: a mock frame answers those, and any
-- other field that was never set reads nil, as on a real frame
local METHODS = {}
for _, src in ipairs({ LOADER_SRC, CUSTOM_SRC }) do
    for name in src:gmatch(":([%a_][%w_]*)%s*%(") do METHODS[name] = true end
end

-------------------------------------------------------------------------------
--  Game API stubs
-------------------------------------------------------------------------------
local frames, timers = {}, {}
local SECRET = {}

local function MakeObj(kind, parent)
    local o = { _kind = kind, _parent = parent, _scripts = {}, _events = {}, _shown = true, _w = 0, _h = 0, _scale = 1 }
    setmetatable(o, { __index = function(_, k)
        if type(k) ~= "string" or k:sub(1, 1) == "_" then return nil end
        if k == "SetScript" then return function(self, name, fn) self._scripts[name] = fn end end
        if k == "GetScript" then return function(self, name) return self._scripts[name] end end
        if k == "CreateTexture" or k == "CreateFontString" or k == "CreateAnimationGroup" or k == "CreateAnimation" then
            return function(self) return MakeObj(k, self) end
        end
        if k == "Show" then return function(self) self._shown = true end end
        if k == "Hide" then return function(self) self._shown = false end end
        if k == "SetShown" then return function(self, v) self._shown = v and true or false end end
        if k == "IsShown" or k == "IsVisible" then return function(self) return self._shown end end
        if k == "SetWidth" then return function(self, w) assert(type(w) == "number", "SetWidth needs a number") self._w = w end end
        if k == "SetHeight" then return function(self, h) assert(type(h) == "number", "SetHeight needs a number") self._h = h end end
        if k == "SetSize" then return function(self, w, h) self._w, self._h = w, h end end
        if k == "GetWidth" then return function(self) return self._w end end
        if k == "GetHeight" then return function(self) return self._h end end
        if k == "GetEffectiveScale" then return function(self) return self._scale end end
        if k == "GetFrameLevel" then return function() return 1 end end
        if k == "GetAlpha" then return function() return 1 end end
        if k == "SetPoint" then return function(self, ...) self._point = { ... } end end
        if k == "RegisterEvent" then return function(self, e) self._events[e] = true end end
        if k == "UnregisterEvent" then return function(self, e) self._events[e] = nil end end
        if METHODS[k] then return function() end end
        return nil
    end })
    frames[#frames + 1] = o
    return o
end

function CreateFrame(kind, name, parent)
    local o = MakeObj(kind, parent)
    if name then _G[name] = o end
    return o
end
UIParent = MakeObj("Frame")
UIParent._w, UIParent._h = 1000, 800

function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function hooksecurefunc() end
function InCombatLockdown() return false end
function IsInInstance() return false, "none" end
function UnitGUID() return "Player-1" end
function GetTime() return 0 end
TRACKER_HEADER_QUESTS = "Quests"
SlashCmdList = {}
C_AddOns = { IsAddOnLoaded = function() return true end }
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function RunTimers()
    local run = timers
    timers = {}
    for _, fn in ipairs(run) do fn() end
end

local function DeepCopy(t)
    local c = {}
    for k, v in pairs(t) do c[k] = type(v) == "table" and DeepCopy(v) or v end
    return c
end

local unlockElement, unlockListener
local reapplied, reappliedKey = 0, nil
EllesmereUIDB = {}
EllesmereUI = {
    IS_FOREVER = true,
    ELLESMERE_GREEN = { r = 0.1, g = 0.8, b = 0.6 },
    -- The tracker's Unlock Mode link, re-applied after each placement
    ReapplyOwnAnchor = function(key) reapplied, reappliedKey = reapplied + 1, key end,
    _ModuleNS = {},
    Lite = { NewDB = function(_, defaults) return { profile = DeepCopy(defaults.profile) } end },
    NewCombatQueue = function() return { Defer = function() end } end,
    PadTaintStandDown = function() return false end,
    IsSecret = function(v) return v == SECRET end,
    PrimeFontShadow = function() end,
    GetFontUseShadow = function() return false end,
    GetFontOutlineFlag = function() return "" end,
    RegisterVisibilityUpdater = function() end,
    RegisterMouseoverTarget = function() end,
    RegAccent = function() end,
    -- The tracker stays hidden here, so no render (the quest log) is needed
    EvalVisibility = function() return false end,
    MakeUnlockElement = function(t) return t end,
}
function EllesmereUI:RegisterUnlockElements(list) unlockElement = list[1] end
function EllesmereUI:RegisterUnlockModeListener(_, fn) unlockListener = fn end

-- Blizzard's tracker: unplaced until Edit Mode applies its layout
local otf = { ready = false, left = 700, top = 600, w = 235, h = 500, scale = 1, headerBottom = 570 }
ObjectiveTrackerFrame = {
    IsInitialized = function() return otf.ready end,
    GetLeft = function() return otf.left end,
    GetTop = function() return otf.top end,
    GetWidth = function() return otf.w end,
    GetHeight = function() return otf.h end,
    GetEffectiveScale = function() return otf.scale end,
    Header = { GetBottom = function() return otf.headerBottom end },
}

-------------------------------------------------------------------------------
--  The files under test
-------------------------------------------------------------------------------
local ns = {}
assert(loadstring(LOADER_SRC, "=EllesmereUIQuestTracker.lua"))("EllesmereUIQuestTracker", ns)
local firstCustomFrame = #frames + 1
assert(loadstring(CUSTOM_SRC, "=EllesmereUIQuestTracker_Custom.lua"))("EllesmereUIQuestTracker", ns)
local EQT = ns.EQT
local evt = frames[firstCustomFrame]

local headerHidden = false
EQT.MuteBlizzardTracker = function() end
EQT.GetLineRGB = function() return 1, 1, 1, 1 end
EQT.GetHeaderRGB = function() return 1, 1, 1 end
EQT.GetFont = function() return "font" end
EQT.ShouldHideMasterHeader = function() return headerHidden end

-------------------------------------------------------------------------------
--  1. Which tracker a profile gets: its pick, else ours under the EllesmereUI
--     style alone
-------------------------------------------------------------------------------
local Wanted, Pick = ns.CustomTrackerWanted, ns.SetCustomTrackerWanted
assert(Wanted({}) == true, "the EllesmereUI style starts on the custom tracker")
assert(Wanted({ useBlizzardStyle = true }) == false, "Blizzard Style keeps Blizzard's tracker")
assert(Wanted({ useClassicStyle = true }) == false, "Classic WoW UI keeps Blizzard's tracker")
assert(Wanted({ useBlizzardStyle = true, customTracker = true }) == false, "a true in the old key is no pick")
assert(Wanted({ customTracker = false }) == false, "turned off under the old key: still off")
assert(Wanted({ useBlizzardStyle = true, customTrackerPick = true }) == true, "a stock style can opt in")
assert(Wanted({ customTrackerPick = false }) == false)

local q = {}
Pick(q, false)
assert(q.customTrackerPick == false and not Wanted(q))
Pick(q, true)
assert(q.customTrackerPick == nil and Wanted(q), "a pick equal to the style's answer is not kept")
local b = { useBlizzardStyle = true, customTracker = true }
Pick(b, true)
assert(b.customTrackerPick == true and b.customTracker == nil and Wanted(b))
Pick(b, false)
assert(b.customTrackerPick == nil and not Wanted(b))
-- back on, then a move to a stock style: it follows the style again
local e = { customTracker = false }
Pick(e, true)
assert(e.customTracker == nil and e.customTrackerPick == nil and Wanted(e))
e.useBlizzardStyle = true
assert(not Wanted(e))

EllesmereUI.IS_FOREVER = false
assert(Wanted({}) == false, "never on another client")
EllesmereUI.IS_FOREVER = true
assert(ns.UseCustomTracker() == true)

-------------------------------------------------------------------------------
--  2. Where it starts: at the fallback spot until Blizzard's tracker is
--     placed, then on that tracker's panel, once
-------------------------------------------------------------------------------
local cfg = EQT.DB()
assert(cfg.customTracker == nil, "no default for the old key")
assert(cfg.customPos == nil and cfg.customWidth == 260 and cfg.customMaxHeight == 450)

EQT.InitCustom()
RunTimers()
local frame = EUI_CustomQuestTracker
assert(frame and unlockElement and unlockListener)
assert(cfg.customPos == nil, "a spot was saved before Blizzard's tracker was placed")
assert(frame._point[1] == "TOPRIGHT" and frame._point[4] == -80 and frame._point[5] == -280, "not at the fallback spot")
assert(evt._events.EDIT_MODE_LAYOUTS_UPDATED, "not waiting for Edit Mode's layout")

-- quest events before Edit Mode has placed its tracker never use up the wait
for _ = 1, 15 do
    evt._scripts.OnEvent(evt, "QUEST_LOG_UPDATE")
    RunTimers()
end
assert(cfg.customPos == nil and evt._events.EDIT_MODE_LAYOUTS_UPDATED, "gave up before Blizzard's tracker was placed")

-- Edit Mode's layout alone is not enough at login: the right-side frames
-- settle once the world has loaded
otf.ready = true
evt._scripts.OnEvent(evt, "EDIT_MODE_LAYOUTS_UPDATED")
RunTimers()
for _ = 1, 15 do
    evt._scripts.OnEvent(evt, "QUEST_LOG_UPDATE")
    RunTimers()
end
assert(cfg.customPos == nil and evt._events.EDIT_MODE_LAYOUTS_UPDATED, "a spot was taken before the world had loaded")
evt._scripts.OnEvent(evt, "PLAYER_ENTERING_WORLD")
RunTimers()
assert(cfg.customPos and cfg.customPos.point == "TOPLEFT" and cfg.customPos.relPoint == "BOTTOMLEFT")
assert(cfg.customPos.x == 694 and cfg.customPos.y == 600, "the spot is the old panel's top left")
assert(cfg.customWidth == 252 and cfg.customMaxHeight == 500, "the size is the old panel's")
assert(frame._point[1] == "TOPLEFT" and frame._point[4] == 694 and frame._point[5] == 600 and frame._w == 252)
assert(not evt._events.EDIT_MODE_LAYOUTS_UPDATED, "still listening after the spot was taken")

-- a saved spot is never replaced
otf.left = 100
EQT.SyncPosition()
assert(cfg.customPos.x == 694 and cfg.customWidth == 252)

-- the master header hidden: the panel began under it
cfg.customPos, cfg.customWidth, cfg.customMaxHeight = nil, 260, 450
otf.left, headerHidden = 700, true
EQT.SyncPosition()
assert(cfg.customPos.y == 570 and cfg.customMaxHeight == 470, "the panel starts under the hidden header")
headerHidden = false

-- Blizzard's tracker at another scale
cfg.customPos, cfg.customWidth, cfg.customMaxHeight = nil, 260, 450
otf.scale = 0.5
EQT.SyncPosition()
assert(cfg.customPos.x == 347 and cfg.customPos.y == 300 and cfg.customWidth == 150 and cfg.customMaxHeight == 250)
otf.scale = 1

-- Blizzard's quest icons shown: the background reached further left
cfg.customPos, cfg.customWidth, cfg.customMaxHeight, cfg.showQuestIcons = nil, 260, 450, true
EQT.SyncPosition()
assert(cfg.customPos.x == 681 and cfg.customWidth == 265)
cfg.showQuestIcons = nil

-- a stock style opted in: Blizzard's tracker had no EllesmereUI background, so its own box
cfg.customPos, cfg.customWidth, cfg.customMaxHeight = nil, 260, 450
ns._qtStyle, headerHidden = "blizzard", true
EQT.SyncPosition()
assert(cfg.customPos.x == 700 and cfg.customPos.y == 600 and cfg.customWidth == 235 and cfg.customMaxHeight == 500)
ns._qtStyle, headerHidden = "eui", false

-- a width or height the user already set stays
cfg.customPos, cfg.customWidth, cfg.customMaxHeight = nil, 300, 450
EQT.SyncPosition()
assert(cfg.customPos.x == 694 and cfg.customWidth == 300 and cfg.customMaxHeight == 500)

-- a rect the game keeps secret: wait, then take it
cfg.customPos = nil
otf.left = SECRET
EQT.SyncPosition()
assert(cfg.customPos == nil and evt._events.EDIT_MODE_LAYOUTS_UPDATED)
otf.left = 700
evt._scripts.OnEvent(evt, "PLAYER_ENTERING_WORLD")
RunTimers()
assert(cfg.customPos and cfg.customPos.x == 694 and not evt._events.EDIT_MODE_LAYOUTS_UPDATED)

-- a placed tracker whose rect stays unreadable: a few tries, then the fallback spot stands
cfg.customPos = nil
otf.left = SECRET
EQT.SyncPosition()
for _ = 1, 12 do
    evt._scripts.OnEvent(evt, "QUEST_LOG_UPDATE")
    RunTimers()
end
assert(cfg.customPos == nil and not evt._events.EDIT_MODE_LAYOUTS_UPDATED, "the tries never stop")
otf.left = 700
EQT.SyncPosition()
assert(cfg.customPos and cfg.customPos.x == 694)

-- Reset in Unlock Mode: back onto Blizzard's tracker
otf.left = 500
unlockElement.clearPos()
assert(cfg.customPos and cfg.customPos.x == 494)

-------------------------------------------------------------------------------
--  3. Width and height: the settings, within their range, and an Unlock Mode
--     session that is discarded changes neither
-------------------------------------------------------------------------------
local wMin, wMax, hMin, hMax = EQT.CustomSizeRange()
assert(wMin == 150 and wMax == 600 and hMin == 100 and hMax == 1200)
cfg.customWidth, cfg.customMaxHeight = 280, 640
frame._h = 120   -- the list is short: the frame is smaller than it may grow
local w, h = unlockElement.getSize()
assert(w == 280 and h == 640, "the size rows show the settings, not the frame's current height")

EllesmereUI._unlockActive = true
unlockListener(true)
assert(frame._h == 640, "Unlock Mode outlines the whole area")
local sw, sh = unlockElement.getSize()
unlockElement.setHeight(nil, 5000)
assert(cfg.customMaxHeight == 1200 and frame._h == 1200)
unlockElement.setWidth(nil, 10)
assert(cfg.customWidth == 150 and frame._w == 150)
unlockElement.setWidth(nil)      -- a relayout with no size
unlockElement.setHeight(nil)
assert(cfg.customWidth == 150 and cfg.customMaxHeight == 1200)
-- discard: the session's snapshot goes back in
unlockElement.setWidth(nil, sw)
unlockElement.setHeight(nil, sh)
EllesmereUI._unlockActive = false
unlockListener(false)
assert(cfg.customWidth == 280 and cfg.customMaxHeight == 640, "a discarded session changed the size")

-------------------------------------------------------------------------------
--  4. Grow direction: down keeps the top edge, up the bottom edge of the same
--     area (the width by the max height)
-------------------------------------------------------------------------------
local GrowDir = EllesmereUI.GetQuestTrackerGrowDir
assert(GrowDir() == "DOWN" and cfg.customGrowUp == false, "a new profile grows down")
cfg.customPos = { point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = 494, y = 600 }
cfg.customMaxHeight = 400
EQT.SyncPosition()
assert(frame._point[1] == "TOPLEFT" and frame._point[5] == 600)
local lp = unlockElement.loadPos()
assert(lp.point == "TOPLEFT" and lp.y == 600)

-- up: the saved spot becomes the bottom edge of the same area
reapplied = 0
EQT.SetCustomGrowUp(true)
assert(cfg.customGrowUp == true and GrowDir() == "UP")
assert(cfg.customPos.point == "BOTTOMLEFT" and cfg.customPos.relPoint == "BOTTOMLEFT")
assert(cfg.customPos.x == 494 and cfg.customPos.y == 200, "not the bottom of the same area")
assert(frame._point[1] == "BOTTOMLEFT" and frame._point[3] == "BOTTOMLEFT")
assert(frame._point[4] == 494 and frame._point[5] == 200)
assert(reapplied > 0 and reappliedKey == "EQT_Tracker", "an Unlock Mode link was not re-applied")
lp = unlockElement.loadPos()
assert(lp.point == "BOTTOMLEFT" and lp.y == 200, "Unlock Mode reads the other edge")
-- the same pick again writes nothing
local same = cfg.customPos
EQT.SetCustomGrowUp(true)
assert(cfg.customPos == same)

-- a taller max height leaves the bottom edge where it is
cfg.customMaxHeight = 700
EQT.SyncPosition()
assert(cfg.customPos.y == 200 and frame._point[1] == "BOTTOMLEFT" and frame._point[5] == 200)

-- back down: the top of the area the tracker has now
EQT.SetCustomGrowUp(false)
assert(cfg.customGrowUp == false and GrowDir() == "DOWN")
assert(cfg.customPos.point == "TOPLEFT" and cfg.customPos.y == 900 and frame._point[5] == 900)

-- a direction that changed under the saved spot (a profile layer): placed by
-- the other edge of the same area, the spot left as saved
cfg.customMaxHeight = 400
cfg.customPos = { point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = 494, y = 600 }
cfg.customGrowUp = true
EQT.SyncPosition()
assert(cfg.customPos.point == "TOPLEFT" and cfg.customPos.y == 600, "an apply rewrote the saved spot")
assert(frame._point[1] == "BOTTOMLEFT" and frame._point[5] == 200)
cfg.customGrowUp = false
EQT.SyncPosition()
assert(frame._point[1] == "TOPLEFT" and frame._point[5] == 600)

-- Unlock Mode: a saved drag keeps the edge the tracker grows away from
cfg.customWidth, cfg.customMaxHeight = 280, 640
EQT.SetCustomGrowUp(true)
assert(cfg.customPos.y == -40)
EllesmereUI._unlockActive = true
unlockListener(true)
assert(frame._h == 640)
local snap = unlockElement.loadPos()
unlockElement.savePos(nil, "CENTER", "CENTER", 100, 50)
assert(cfg.customPos.point == "BOTTOMLEFT" and cfg.customPos.x == 460 and cfg.customPos.y == 130)
-- the drag left the frame on a top left anchor: closing puts it back on its bottom edge
frame._point = { "TOPLEFT", UIParent, "TOPLEFT", 460, -30 }
EllesmereUI._unlockActive = false
unlockListener(false)
assert(frame._point[1] == "BOTTOMLEFT" and frame._point[4] == 460 and frame._point[5] == 130)
-- a discarded session hands its snapshot back
unlockElement.savePos(nil, snap.point, snap.relPoint, snap.x, snap.y)
assert(cfg.customPos.point == "BOTTOMLEFT" and cfg.customPos.x == 494 and cfg.customPos.y == -40)
assert(frame._point[1] == "BOTTOMLEFT" and frame._point[5] == -40)
-- the same drag while growing down saves the top edge
EQT.SetCustomGrowUp(false)
assert(cfg.customPos.point == "TOPLEFT" and cfg.customPos.y == 600)
EllesmereUI._unlockActive = true
unlockListener(true)
unlockElement.savePos(nil, "CENTER", "CENTER", 100, 50)
assert(cfg.customPos.point == "TOPLEFT" and cfg.customPos.x == 460 and cfg.customPos.y == 770)
frame._point = { "TOPLEFT", UIParent, "TOPLEFT", 460, -30 }
EllesmereUI._unlockActive = false
unlockListener(false)
assert(frame._point[1] == "TOPLEFT" and frame._point[3] == "BOTTOMLEFT" and frame._point[5] == 770)

-- growing up with no spot saved: Blizzard's panel is the area, its bottom edge the spot
cfg.customPos, cfg.customWidth, cfg.customMaxHeight = nil, 260, 450
cfg.customGrowUp = true
otf.left = 700
EQT.SyncPosition()
assert(cfg.customMaxHeight == 500 and cfg.customPos.point == "BOTTOMLEFT")
assert(cfg.customPos.x == 694 and cfg.customPos.y == 100, "not the bottom of Blizzard's panel")
-- and until that tracker can be read, the bottom edge of the fallback area
cfg.customPos = nil
otf.left = SECRET
EQT.SyncPosition()
assert(cfg.customPos == nil)
assert(frame._point[1] == "BOTTOMRIGHT" and frame._point[3] == "TOPRIGHT")
assert(frame._point[4] == -80 and frame._point[5] == -780)
otf.left = 700
cfg.customGrowUp = false
EQT.SyncPosition()
assert(cfg.customPos.point == "TOPLEFT" and cfg.customPos.y == 600)

-------------------------------------------------------------------------------
--  5. Zone header colour: the pick on Group Quests by Zone (the accent or a
--     custom colour), else the Header Color
-------------------------------------------------------------------------------
local Zone = EQT.CustomZoneRGB
EQT.GetHeaderRGB = function() return 0.3, 0.4, 0.5 end
local function IsZone(r, g, b, accent, why)
    local zr, zg, zb, za = Zone()
    assert(zr == r and zg == g and zb == b and za == accent, why)
end
assert(cfg.customZoneUseAccent == nil and cfg.customZoneR == nil, "the zone colour has no default key")
-- no pick: the Header Color, lit as the accent while the header reads it
IsZone(0.3, 0.4, 0.5, true, "no pick: the header's colour, the accent by default")
cfg.headerUseAccent = false
IsZone(0.3, 0.4, 0.5, false, "no pick under a custom Header Color")
cfg.headerUseAccent, cfg.headerShowClassColor = nil, true
IsZone(0.3, 0.4, 0.5, false, "no pick under a class coloured header")
-- the accent picked: whatever the Header Color says
cfg.customZoneUseAccent = true
IsZone(0.1, 0.8, 0.6, true, "the accent pick")
-- a custom pick: white until a colour is chosen
cfg.customZoneUseAccent, cfg.headerShowClassColor = false, nil
IsZone(1, 1, 1, false, "a custom pick with no colour yet")
cfg.customZoneR, cfg.customZoneG, cfg.customZoneB = 0.2, 0.5, 0.9
IsZone(0.2, 0.5, 0.9, false, "a custom pick")
cfg.customZoneUseAccent, cfg.customZoneR, cfg.customZoneG, cfg.customZoneB = nil, nil, nil, nil

RunTimers()
print("quest tracker custom harness: ok")
