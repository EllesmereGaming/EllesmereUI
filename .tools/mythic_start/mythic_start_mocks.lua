-- Purpose-built behavioral harness; not shipped as part of the addon.
Harness = {
    now = 0, frames = {}, timers = {}, chat = {}, localChat = {}, countdowns = {},
    readyRequests = 0, slotRequests = 0, pickups = 0, startRequests = 0,
    group = "party", count = 3, leader = true, assistant = false,
    connected = {}, guids = {}, names = {}, readyStatus = {}, readyUntil = 0,
    autoAckCountdown = true, countdownReturn = true, startReturn = true,
    combat = false, chatLocked = false, active = false, cursor = false,
    frameCreates = 0, methodHooks = 0,
}
local H = Harness
LE_PARTY_CATEGORY_HOME, LE_PARTY_CATEGORY_INSTANCE = 1, 2
BACKPACK_CONTAINER, NUM_BAG_SLOTS = 0, 4

local function invoke(frame, script, ...)
    if frame.scripts[script] then frame.scripts[script](frame, ...) end
    for _, fn in ipairs(frame.hooks[script] or {}) do fn(frame, ...) end
end
local Frame = {}
function Frame:RegisterEvent(event) self.events[event] = true end
function Frame:UnregisterEvent(event) self.events[event] = nil end
function Frame:UnregisterAllEvents() self.events = {} end
function Frame:SetScript(script, fn) self.scripts[script] = fn end
function Frame:GetScript(script) return self.scripts[script] end
function Frame:HookScript(script, fn)
    self.hooks[script] = self.hooks[script] or {}
    table.insert(self.hooks[script], fn)
end
function Frame:IsShown() return self.shown end
function Frame:Show() if not self.shown then self.shown = true; invoke(self, "OnShow") end end
function Frame:Hide() if self.shown then self.shown = false; invoke(self, "OnHide") end end
function Frame:SetShown(shown) if shown then self:Show() else self:Hide() end end
function Frame:SetEnabled(value) self.enabled = value end
function Frame:IsEnabled() return self.enabled end
function Frame:SetAlpha(value) self.alpha = value end
function Frame:SetSize(w, h) self.width, self.height = w, h end
function Frame:SetPoint(...) self.point = {...} end
function Frame:RegisterForClicks(...) self.clicks = {...} end
function Frame:Click(mouseButton) if self.enabled then invoke(self, "OnClick", mouseButton or "LeftButton") end end
function CreateFrame(kind, name, parent)
    local frame = setmetatable({kind = kind, name = name, parent = parent,
        scripts = {}, hooks = {}, events = {}, shown = false, enabled = true}, {__index = Frame})
    H.frameCreates = H.frameCreates + 1
    table.insert(H.frames, frame)
    return frame
end
function hooksecurefunc(object, method, hook)
    local original = object[method]
    assert(type(original) == "function", "cannot hook absent method " .. method)
    H.methodHooks = H.methodHooks + 1
    object[method] = function(...)
        local result = original(...)
        hook(...)
        return result
    end
end
function H.emit(event, ...)
    local targets = {}
    for _, frame in ipairs(H.frames) do
        if frame.events[event] then targets[#targets + 1] = frame end
    end
    for _, frame in ipairs(targets) do invoke(frame, "OnEvent", event, ...) end
end
function H.makeKeystoneFrame()
    local frame = CreateFrame("Frame")
    frame.StartButton = CreateFrame("Button", nil, frame)
    frame.Reset = function() H.slotted = nil end
    ChallengesKeystoneFrame = frame
    return frame
end
function H.open()
    ChallengesKeystoneFrame:Show()
    H.emit("CHALLENGE_MODE_KEYSTONE_RECEPTABLE_OPEN")
end
function H.slot(mapID, level)
    H.slotted = {mapID or 399, {9}, level or 12}
    H.cursor = false
    H.emit("CHALLENGE_MODE_KEYSTONE_SLOTTED")
end
function H.button(key)
    local text = ({EllesmereReadyButton = "READY", EllesmerePullButton = "PULL"})[key] or key
    for _, frame in ipairs(H.frames) do
        if frame.parent == ChallengesKeystoneFrame and frame.text == text then return frame end
    end
end
function H.click(key, bypassDisabled, mouseButton)
    local button = assert(H.button(key), "missing button " .. key)
    if bypassDisabled then invoke(button, "OnClick", mouseButton or "LeftButton") else button:Click(mouseButton) end
end
function H.ready()
    H.click("EllesmereReadyButton")
    H.ackReady()
end
function H.ackReady(initiator, duration)
    duration = duration or 30
    H.readyUntil = H.now + duration
    H.readyStatus.player = "ready"
    H.emit("READY_CHECK", initiator or "Tester-TestRealm", duration)
end
function H.respond(unit, ready)
    H.readyStatus[unit] = ready and "ready" or "notready"
    H.emit("READY_CHECK_CONFIRM", unit, ready)
end
function H.finish(preempted)
    H.readyUntil = 0
    H.emit("READY_CHECK_FINISHED", preempted)
end
function H.allReady()
    H.respond("player", true)
    if H.group ~= "solo" then
        for i = 1, H.count - 1 do H.respond("party" .. i, true) end
    end
    H.finish(false)
end
local function newTimer(delay, fn, repeatTimer)
    local timer = {at = H.now + delay, delay = delay, fn = fn, repeating = repeatTimer, canceled = false}
    function timer:Cancel() self.canceled = true end
    function timer:IsCancelled() return self.canceled end
    table.insert(H.timers, timer)
    return timer
end
C_Timer = {
    NewTimer = function(delay, fn) return newTimer(delay, fn, false) end,
    NewTicker = function(delay, fn) return newTimer(delay, fn, true) end,
}
function H.advance(delta)
    local target = H.now + delta
    local iterations = 0
    while true do
        local nextTimer
        for _, timer in ipairs(H.timers) do
            if not timer.canceled and timer.at <= target
                and (not nextTimer or timer.at < nextTimer.at) then nextTimer = timer end
        end
        if not nextTimer then break end
        iterations = iterations + 1
        assert(iterations < 1000, "runaway timer loop")
        H.now = nextTimer.at
        if nextTimer.repeating then nextTimer.at = nextTimer.at + nextTimer.delay
        else nextTimer.canceled = true end
        nextTimer.fn(nextTimer)
    end
    H.now = target
end
function H.liveTimers()
    local count = 0
    for _, timer in ipairs(H.timers) do if not timer.canceled then count = count + 1 end end
    return count
end
function GetTime() return H.now end
function InCombatLockdown() return H.combat end
function CursorHasItem() return H.cursor end
function IsInGroup(category)
    if H.group == "solo" then return false end
    if category == LE_PARTY_CATEGORY_INSTANCE then return H.group == "instance" end
    if category == LE_PARTY_CATEGORY_HOME then return H.group ~= "instance" end
    return true
end
function IsInRaid(category) return H.group == "raid" and category ~= LE_PARTY_CATEGORY_INSTANCE end
function GetNumGroupMembers(category) return IsInGroup(category) and H.count or 0 end
local function normalizedUnit(unit) if unit == "raid1" then return "player" end; return unit end
function UnitGUID(unit)
    unit = normalizedUnit(unit)
    if H.guids[unit] == false then return nil end
    return H.guids[unit] or ("Player-" .. unit)
end
function UnitName(unit)
    unit = normalizedUnit(unit)
    return H.names[unit] or (unit == "player" and "Tester" or unit)
end
function UnitFullName(unit) return UnitName(unit), "TestRealm" end
function UnitIsConnected(unit) return H.connected[normalizedUnit(unit)] ~= false end
function UnitIsGroupLeader(unit, category)
    return IsInGroup(category) and normalizedUnit(unit) == "player" and H.leader
end
function UnitIsGroupAssistant(unit, category)
    return IsInGroup(category) and normalizedUnit(unit) == "player" and H.assistant
end
function GetReadyCheckTimeLeft() return math.max(0, H.readyUntil - H.now) end
function GetReadyCheckStatus(unit) return H.readyStatus[normalizedUnit(unit)] or "waiting" end
C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and 1 or 0 end,
    GetContainerItemLink = function() return "|Hkeystone:180653:399:12:9|h[Keystone]|h" end,
    PickupContainerItem = function() H.pickups = H.pickups + 1; H.cursor = true end,
}
C_AddOns = {IsAddOnLoaded = function(name) return name == "Blizzard_ChallengesUI" and ChallengesKeystoneFrame ~= nil end}
C_ChallengeMode = {
    GetSlottedKeystoneInfo = function() if H.slotted then return unpack(H.slotted) end end,
    IsChallengeModeActive = function() return H.active end,
    SlotKeystone = function() H.slotRequests = H.slotRequests + 1 end,
    StartChallengeMode = function()
        H.startRequests = H.startRequests + 1
        if H.startError then error("protected API rejected invocation") end
        return H.startReturn
    end,
}
C_PartyInfo = {
    DoReadyCheck = function()
        H.readyRequests = H.readyRequests + 1
        if H.readyError then error("ready check unavailable") end
    end,
    DoCountdown = function(seconds)
        H.countdowns[#H.countdowns + 1] = seconds
        if H.onCountdown then H.onCountdown(seconds) end
        if H.countdownError then error("countdown unavailable") end
        if H.autoAckCountdown then
            if seconds == 0 then H.emit("CANCEL_PLAYER_COUNTDOWN", UnitGUID("player"))
            else H.emit("START_PLAYER_COUNTDOWN", UnitGUID("player"), seconds, seconds) end
        end
        return H.countdownReturn
    end,
}
C_ChatInfo = {
    InChatMessagingLockdown = function() return H.chatLocked end,
    SendChatMessage = function(message, channel)
        if H.chatError then error("chat rejected") end
        H.chat[#H.chat + 1] = {message = message, channel = channel}
    end,
}
DEFAULT_CHAT_FRAME = {AddMessage = function(_, message) H.localChat[#H.localChat + 1] = message end}
EllesmereUIDB = {mythicKeystoneControls = true, autoInsertKeystone = true, autoKeystoneReadyCheck = false, autoStartKeystone = false}
EllesmereUI = {
    IS_FOREVER = false, WB_COLOURS = {}, RefreshAllAddons = function() end,
    SwitchProfile = function() end, ApplyProfileData = function() end,
    MakeStyledButton = function(button, text, size, colours, click)
        button.text = text; button:SetScript("OnClick", function() if click then click() end end)
        button:SetScript("OnEnter", function() end)
    end,
}
H.makeKeystoneFrame()
