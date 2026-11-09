-- Stub harness: loads the Quest Tracker's quest audio bridge outside the game
-- with the row hook API and the voice-over addon's functions stubbed, then
-- plays quest title rows through the hook it registers. The bridge installs
-- at login only with the custom tracker in use and every function it needs
-- present; puts one button per row slot, bound again only when the row shows
-- another quest; asks the addon once per quest until one of its change edges
-- (voice packs loaded, its quest part switched, its tracker sweep) redraws the
-- rows; turns itself off on a failing call; stands down when its id is taken.
--   python run_with_file.py <repo> .tools/tests/test_quest_tracker_audio_bridge.lua [file]
-- (real Lua 5.1 through lupa; arg[2] picks another copy of the file under test)
local ROOT = arg and arg[1] or "."
local FILE = arg and arg[2] or "EllesmereUIQuestTracker/EllesmereUIQuestTracker_QuestAudio.lua"

local function ReadSource(name)
    local f = assert(io.open(name:find("^%a:") and name or (ROOT .. "/" .. name), "rb"))
    local src = f:read("*a")
    f:close()
    if src:sub(1, 3) == "\239\187\191" then src = src:sub(4) end
    return src
end
local SRC = ReadSource(FILE)

local function Load(opts)
    opts = opts or {}
    local T = { hooks = {}, callbacks = {}, refreshes = 0, shows = 0, binds = 0, states = 0,
                voiced = { [101] = true, [102] = true }, frames = {} }
    local noop = function() end

    local META
    local function New(parent)
        local o = setmetatable({ _parent = parent, _shown = true, _points = {} }, META)
        T.frames[#T.frames + 1] = o
        return o
    end
    local METHODS = {
        Show = function(self) self._shown = true end,
        Hide = function(self) self._shown = false end,
        IsShown = function(self) return self._shown end,
        SetPoint = function(self, ...) self._points[#self._points + 1] = { ... } end,
        SetSize = function(self, w, h) self._w, self._h = w, h end,
        CreateTexture = function(self) return New(self) end,
        SetScript = function(self, name, fn) self["_s" .. name] = fn end,
        RegisterEvent = function(self, ev) T.boot = self end,
    }
    META = {
        __index = function(_, k)
            local m = METHODS[k]
            if m then return m end
            if type(k) == "string" and k:find("^%u") then return noop end
            return nil
        end,
    }

    local ui = {
        ShowsTrackerButton = function(_, questID)
            T.shows = T.shows + 1
            if opts.failShows then error("changed on their side") end
            return T.voiced[questID]
        end,
        BindPlayButton = function(_, button, questID, title, origin)
            T.binds = T.binds + 1
            if opts.failBind then error("changed on their side") end
            -- The addon keeps the quest on a button that follows its queue.
            if button.setPlayState then button.questID = questID end
            T.lastBind = { button = button, questID = questID, title = title, origin = origin }
        end,
        SetPlayButtonState = function() T.states = T.states + 1 end,
        FollowQueue = function() end,
        UpdateTrackerButtons = function() T.sweeps = (T.sweeps or 0) + 1 end,
    }
    local spoken = {
        DressBoxButton = function(_, button)
            function button:SetBox(atlas, w, h) self._box = atlas; self._w, self._h = w, h end
            function button:SetState() end
            return button
        end,
        RegisterCallback = function(_, event, fn) T.callbacks[event] = fn end,
    }

    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.EUI_CLIENT_BLOCKED = nil
    env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    env.CreateFrame = function(_, _, parent) return New(parent) end
    env.C_QuestLog = { GetTitleForQuestID = function(id) return "Quest " .. id end }
    env.hooksecurefunc = function(tbl, name, fn)
        local orig = tbl[name]
        tbl[name] = function(...) orig(...); fn(...) end
    end
    if not opts.noAddon then
        env.VoiceOver = setmetatable({ QuestOverlayUI = ui }, { __index = env })
        env.Spoken = spoken
    end
    env.EllesmereUI = {
        IS_FOREVER = true,
        RegisterQuestTrackerRow = function(id, fn, width)
            if opts.taken then return false end
            T.hooks[#T.hooks + 1] = { id = id, fn = fn, width = width }
            return true
        end,
        RefreshQuestTrackerRows = function() T.refreshes = T.refreshes + 1 end,
    }
    local ns = { UseCustomTracker = function() return opts.custom ~= false end }

    local chunk = assert(loadstring(SRC, "=EllesmereUIQuestTracker_QuestAudio.lua"))
    setfenv(chunk, env)
    chunk("EllesmereUIQuestTracker", ns)
    T.boot._sOnEvent(T.boot, "PLAYER_LOGIN")
    T.ui, T.env = ui, env
    T.row = T.hooks[1] and T.hooks[1].fn
    return T
end

local function Slot() return { _shown = true } end
-- The button the bridge made in a slot: the slot is its parent.
local function ButtonOf(T, slot)
    for _, f in ipairs(T.frames) do
        if f._parent == slot and f._box then return f end
    end
end

local fails = 0
local function Check(cond, msg)
    if not cond then
        fails = fails + 1
        print("FAIL: " .. msg)
    end
end

-- 1. Install gates: the custom tracker in use and the addon present.
do
    local T = Load({ custom = false })
    Check(#T.hooks == 0, "installed with the custom tracker off")
    T = Load({ noAddon = true })
    Check(#T.hooks == 0, "installed without the voice-over addon")
    T = Load({ taken = true })
    Check(next(T.callbacks) == nil, "kept going after its id was refused")
end

-- 2. One button per slot, bound again only for another quest; none for a
--    quest the addon has no Play for.
do
    local T = Load()
    Check(#T.hooks == 1 and T.hooks[1].id == "Spoken" and T.hooks[1].width == 16, "the row hook was not registered")
    local s1, s2 = Slot(), Slot()
    T.row(s1, 101)
    local b = ButtonOf(T, s1)
    Check(b and b._shown and b._box == "QuestLog-icon-ticksquare", "no box button on a voiced quest's row")
    Check(T.binds == 1 and T.lastBind.questID == 101 and T.lastBind.title == "Quest 101", "the button was not bound to its quest")
    T.row(s1, 101)
    Check(T.binds == 1, "a redraw of the same quest bound the button again")
    T.row(s1, 102)
    Check(T.binds == 2 and T.lastBind.questID == 102, "a reused row kept the old quest's binding")
    Check(ButtonOf(T, s1) == b, "a reused row built a second button")
    T.row(s2, 103)
    Check(ButtonOf(T, s2) == nil, "a button was built for a quest without audio")
    T.row(s1, 103)
    Check(not b._shown, "the button stayed up for a quest without audio")
end

-- 3. The addon is asked once per quest until one of its change edges.
do
    local T = Load()
    local s = Slot()
    T.row(s, 101); T.row(s, 101); T.row(s, 101)
    Check(T.shows == 1, "the addon was asked again on every redraw")
    T.voiced[104] = nil
    T.row(s, 104)
    Check(not ButtonOf(T, s)._shown, "a quest without audio showed Play")
    T.voiced[104] = true
    T.callbacks.VOICE_PACKS_LOADED()
    Check(T.refreshes == 1, "voice packs loading did not redraw the rows")
    T.row(s, 104)
    Check(ButtonOf(T, s)._shown, "a quest whose pack loaded still showed no Play")
    local before = T.refreshes
    T.callbacks.PART_SWITCHED("places")
    Check(T.refreshes == before, "another part's switch redrew the rows")
    T.callbacks.PART_SWITCHED("quests")
    Check(T.refreshes == before + 1, "the quest part's switch did not redraw the rows")
    T.voiced[104] = nil
    T.ui.UpdateTrackerButtons()
    Check(T.sweeps == 1 and T.refreshes == before + 2, "the addon's tracker sweep did not redraw the rows")
    T.row(s, 104)
    Check(not ButtonOf(T, s)._shown, "the tracker button setting turned off still showed Play")
end

-- 4. A failing call turns the bridge off for the session, its buttons hidden,
--    and never raises out of the row hook.
do
    local T = Load({ failBind = true })
    local s = Slot()
    local ok = pcall(T.row, s, 101)
    Check(ok, "a failing call raised out of the row hook")
    local b = ButtonOf(T, s)
    Check(b == nil or not b._shown, "a button stayed up after the bridge failed")
    local asked = T.shows
    T.row(Slot(), 102)
    Check(T.shows == asked, "the bridge kept working after it turned itself off")
end

print(fails == 0 and "quest tracker audio bridge harness: ok"
    or ("quest tracker audio bridge harness: " .. fails .. " failure(s)"))
