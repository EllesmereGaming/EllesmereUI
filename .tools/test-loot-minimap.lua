local scripts = {}
local events
local eventFrame
local openedPage
local rebuilds = 0
local trackerProfile = { minimapButtonSetup = false }

local function Noop() end
local function Region()
    return setmetatable({}, { __index = function() return Noop end })
end

Minimap = { GetFrameLevel = function() return 5 end }
GameTooltip = {
    SetOwner = function(self, owner) self.owner = owner end,
    GetOwner = function(self) return self.owner end,
    SetText = Noop, AddLine = Noop, Show = Noop,
    Hide = function(self) self.owner = nil end,
}
C_Timer = { After = function(_, callback) callback() end }
EllesmereUI = { L = function(key) return key end }

function CreateFrame(_, name)
    local frame = {
        SetSize = Noop, SetPoint = Noop, SetFrameStrata = Noop,
        SetFrameLevel = Noop, SetClampedToScreen = Noop,
        RegisterForClicks = Noop, RegisterEvent = Noop, UnregisterEvent = Noop,
        GetFrameLevel = function() return 5 end,
        CreateTexture = Region,
        SetScript = function(self, script, callback)
            if name then scripts[script] = callback else events, eventFrame = callback, self end
        end,
    }
    if name then _G[name] = frame end
    return frame
end

_G._EMM_DB = { profile = { minimap = { ungroupedButtons = { ExistingButton = 2 } } } }
_G._EMM_FullRebuildMinimap = function() rebuilds = rebuilds + 1 end

local ns = {
    GetProfile = function() return trackerProfile end,
    Open = function(page) openedPage = page end,
}
local chunk = assert(loadfile("EllesmereUILootTracker/EllesmereUILootTracker_Minimap.lua"))
chunk("EllesmereUILootTracker", ns)

local button = _G.EllesmereUILootTrackerMinimapButton
assert(button and button.icon, "named minimap button was not created")
assert(_G._EMM_DB.profile.minimap.ungroupedButtons.EllesmereUILootTrackerMinimapButton == 3,
    "button must default to the direct minimap row")
assert(trackerProfile.minimapButtonSetup, "one-time minimap setup was not persisted")
assert(rebuilds > 0, "EllesmereUI minimap was not asked to collect the new button")

scripts.OnClick()
assert(openedPage == "Overview", "minimap click must open the Loot Tracker overview")

_G._EMM_DB.profile.minimap.ungroupedButtons.EllesmereUILootTrackerMinimapButton = nil
events(eventFrame, "ADDON_LOADED", "EllesmereUIMinimap")
assert(_G._EMM_DB.profile.minimap.ungroupedButtons.EllesmereUILootTrackerMinimapButton == nil,
    "later user grouping choices must not be overwritten")

print("loot minimap integration ok")
