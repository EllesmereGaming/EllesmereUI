-- Stub harness: the minimap's middle-click micro menu (EUI_Minimap_Lifecycle.lua),
-- on retail and on WoW Forever. The block, cut out of the real file by its first
-- and last lines (a moved line fails here by name), builds its menu over stubs.
-- Retail lists fifteen rows. WoW Forever has no Adventure Guide or Housing window
-- (their rows raised an error there), and Legacy stands in Achievements' place.
-- Every row that opens one of Blizzard's micro button windows is a secure click
-- on that button, on both clients, Group Finder included: opening such a window
-- from our own Lua runs Blizzard's code tainted. Only Calendar and Game Menu are
-- plain buttons.
-- The stubs cannot show that a secure click reaches the game's button; they show
-- what each row is built to do.
--   lua .tools/tests/test_minimap_micromenu_forever.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return (src:gsub("\r\n", "\n"))
end

local fails, count = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        print("  FAIL: " .. msg)
    end
end

local SRC = ReadSource("EllesmereUIMinimap/EUI_Minimap_Lifecycle.lua")
local BLOCK
do
    local a = assert(SRC:find("do\n    local menuFrame\n    local menuOpen    = false\n", 1, true), "the micro menu block's first lines not found")
    local last = "        CreateMenuFrame()\n    end)\nend\n"
    local b = assert(SRC:find(last, a, true), "the micro menu block's last lines not found")
    BLOCK = SRC:sub(a, b + #last - 1)
end

-- A frame, texture or font string that takes any method call and keeps what the
-- menu sets on it
local function NewObj(kind, name)
    local o = { kind = kind, name = name, attrs = {}, scripts = {}, hooks = {} }
    return setmetatable(o, { __index = function(_, k)
        if type(k) ~= "string" or not k:find("^%u") then return nil end
        return function(self, ...)
            local a = { ... }
            if k == "SetAttribute" then self.attrs[a[1]] = a[2]
            elseif k == "SetScript" then self.scripts[a[1]] = a[2]
            elseif k == "HookScript" then self.hooks[a[1]] = a[2]
            elseif k == "SetText" then self.text = a[1]
            elseif k == "CreateFontString" then
                local fs = NewObj("FontString"); self.label = fs; return fs
            elseif k == "CreateTexture" then
                return NewObj("Texture")
            elseif k == "IsMouseOver" then return false
            end
        end
    end })
end

local BLIZZARD_BUTTONS = { "CharacterMicroButton", "PlayerSpellsMicroButton", "ProfessionMicroButton",
    "LFDMicroButton", "EJMicroButton", "AchievementMicroButton", "LegacyMicroButton",
    "CollectionsMicroButton", "QuestLogMicroButton", "QuickJoinToastButton", "GuildMicroButton",
    "HousingMicroButton", "StoreMicroButton", "HelpMicroButton" }

-- Builds the menu. forever: the client; missing: micro buttons this client lacks.
-- Returns the rows ("secure|label|frame name|macro" or "plain|label"), the row
-- frames and what the plain rows called when clicked.
local function Build(forever, missing)
    local built, calls = {}, {}
    local env = {}
    env.EllesmereUI = {
        IS_FOREVER = forever or nil,
        L = function(s) return s end,
        PrimeFontShadow = function() end,
        GetFontPath = function() return "font" end,
    }
    env.EBS = {}
    env.UIParent = NewObj("Frame", "UIParent")
    env.Minimap = NewObj("Frame", "Minimap")
    env.UIErrorsFrame = NewObj("Frame")
    env.ERR_NOT_IN_COMBAT = "x"
    env.InCombatLockdown = function() return false end
    env.RegisterStateDriver = function(f, state, conds) f.stateDriver = state .. ":" .. conds end
    env.C_Timer = { After = function() end }
    env.ipairs, env.pairs, env.type, env.string = ipairs, pairs, type, string
    env.ToggleCalendar = function() calls[#calls + 1] = "ToggleCalendar" end
    env.ToggleFrame = function() calls[#calls + 1] = "ToggleFrame" end
    env.GameMenuFrame = NewObj("Frame", "GameMenuFrame")
    -- Blizzard's own openers: a row must never call one of them
    for _, fn in ipairs({ "ToggleGroupFinderFrame", "PVEFrame_ToggleFrame", "ToggleEncounterJournal", "ToggleAchievementFrame",
        "ToggleLegacySystemUI", "ToggleCollectionsJournal", "ToggleCharacter", "ToggleQuestLog", "ToggleGuildFrame", "ToggleFriendsFrame",
        "ToggleStoreUI", "ToggleHelpFrame", "ShowUIPanel" }) do
        env[fn] = function() calls[#calls + 1] = fn end
    end
    for _, n in ipairs(BLIZZARD_BUTTONS) do
        if not (missing and missing[n]) then env[n] = NewObj("Button", n) end
    end
    local loginHandler
    env.CreateFrame = function(kind, name, parent, template)
        local o = NewObj(kind, name)
        o.template = template
        if parent and parent.name == "EllesmereUIMicroMenu" and kind == "Button" then built[#built + 1] = o end
        if name == nil and parent == nil and kind == "Frame" then
            -- the frame that builds the menu at login
            local mt = getmetatable(o)
            local idx = mt.__index
            mt.__index = function(t, k)
                if k == "SetScript" then return function(_, _, fn) loginHandler = fn end end
                return idx(t, k)
            end
        end
        return o
    end
    env._G = env
    setmetatable(env, { __index = function() return nil end })
    local chunk = assert(loadstring(BLOCK, "=EUI_Minimap_Lifecycle.lua"))
    setfenv(chunk, env)
    chunk()
    assert(loginHandler, "the block registered no login handler")
    loginHandler(NewObj("Frame"))
    local rows = {}
    for i, b in ipairs(built) do
        local label = b.label and b.label.text or "?"
        if b.template then
            rows[i] = ("secure|%s|%s|%s"):format(label, tostring(b.name), tostring(b.attrs["*macrotext1"]))
        else
            rows[i] = "plain|" .. label
        end
    end
    -- click every plain row
    for _, b in ipairs(built) do
        if not b.template and b.scripts.OnClick then b.scripts.OnClick(b) end
    end
    return rows, built, calls
end

local function Secure(label, button)
    return ("secure|%s|EUI_MicroMenu_%s|/click %s"):format(label, (label:gsub("%s", "")), button)
end

-------------------------------------------------------------------------------
-- 1. retail: fifteen rows, each micro button a secure click
-------------------------------------------------------------------------------
local RETAIL = {
    Secure("Character", "CharacterMicroButton"),
    Secure("Talents", "PlayerSpellsMicroButton"),
    Secure("Professions", "ProfessionMicroButton"),
    Secure("Group Finder", "LFDMicroButton"),
    Secure("Adventure Guide", "EJMicroButton"),
    Secure("Achievements", "AchievementMicroButton"),
    Secure("Collections", "CollectionsMicroButton"),
    Secure("Quest Log", "QuestLogMicroButton"),
    Secure("Friends", "QuickJoinToastButton"),
    Secure("Guild", "GuildMicroButton"),
    Secure("Housing", "HousingMicroButton"),
    "plain|Calendar",
    "plain|Game Menu",
    Secure("Shop", "StoreMicroButton"),
    Secure("Support", "HelpMicroButton"),
}
do
    local rows, built, calls = Build(false)
    check(#rows == #RETAIL, "retail builds " .. #rows .. " rows")
    for i = 1, #RETAIL do
        check(rows[i] == RETAIL[i], "retail row " .. i .. ": " .. tostring(rows[i]))
    end
    check(table.concat(calls, ",") == "ToggleCalendar,ToggleFrame", "retail's plain rows called: " .. table.concat(calls, ","))
    for _, b in ipairs(built) do
        if b.template then
            check(b.template == "SecureActionButtonTemplate,SecureHandlerStateTemplate", "a secure row's template: " .. tostring(b.template))
            check(b.attrs["*type1"] == "macro" and b.attrs.useOnKeyDown == false, "a secure row's click type: " .. tostring(b.attrs["*type1"]))
            check(b.stateDriver == "combatlock:[combat] combat; nocombat", "a secure row's combat driver: " .. tostring(b.stateDriver))
            -- out of combat the row's own snippet puts the same click type back
            local snippet = b.attrs["_onstate-combatlock"] or ""
            check(snippet:find("self:SetAttribute('*type1', nil)", 1, true) and snippet:find("self:SetAttribute('*type1', 'macro')", 1, true),
                "a secure row's combat snippet does not drop and restore the macro click")
            check(b.scripts.OnClick == nil, "a secure row carries a click script of ours")
        end
    end
end

-------------------------------------------------------------------------------
-- 2. WoW Forever: no Adventure Guide, no Housing, Legacy for Achievements, and
--    Group Finder still the secure click on Blizzard's button
-------------------------------------------------------------------------------
local FOREVER = {
    Secure("Character", "CharacterMicroButton"),
    Secure("Talents", "PlayerSpellsMicroButton"),
    Secure("Professions", "ProfessionMicroButton"),
    Secure("Group Finder", "LFDMicroButton"),
    Secure("Legacy", "LegacyMicroButton"),
    Secure("Collections", "CollectionsMicroButton"),
    Secure("Quest Log", "QuestLogMicroButton"),
    Secure("Friends", "QuickJoinToastButton"),
    Secure("Guild", "GuildMicroButton"),
    "plain|Calendar",
    "plain|Game Menu",
    Secure("Shop", "StoreMicroButton"),
    Secure("Support", "HelpMicroButton"),
}
do
    local rows, _, calls = Build(true)
    check(#rows == #FOREVER, "WoW Forever builds " .. #rows .. " rows")
    for i = 1, #FOREVER do
        check(rows[i] == FOREVER[i], "WoW Forever row " .. i .. ": " .. tostring(rows[i]))
    end
    local all = table.concat(rows, "\n")
    check(not all:find("Adventure Guide", 1, true) and not all:find("Housing", 1, true) and not all:find("Achievements", 1, true),
        "WoW Forever still lists a window it has not got")
    check(table.concat(calls, ",") == "ToggleCalendar,ToggleFrame",
        "WoW Forever's plain rows opened a Blizzard window from our own Lua: " .. table.concat(calls, ","))
    -- a micro button the client lacks: the row is built with nothing to click, no error
    rows = Build(true, { StoreMicroButton = true, LFDMicroButton = true })
    check(rows[4] == "secure|Group Finder|EUI_MicroMenu_GroupFinder|nil" and rows[12] == "secure|Shop|EUI_MicroMenu_Shop|nil",
        "a row whose micro button is missing: " .. tostring(rows[4]) .. " / " .. tostring(rows[12]))
end

-------------------------------------------------------------------------------
-- 3. the block never names one of Blizzard's group finder openers
-------------------------------------------------------------------------------
check(not BLOCK:find("ToggleGroupFinderFrame", 1, true) and not BLOCK:find("PVEFrame_ToggleFrame", 1, true)
    and not BLOCK:find("LFGVanilla", 1, true), "the micro menu opens the group finder from Lua")

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print("PASS test_minimap_micromenu_forever (" .. count .. " checks)")
