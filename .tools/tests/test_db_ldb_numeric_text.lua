-- Stub harness: the Data Bars Broker Plugin block (EllesmereUIDataBars/Blocks/LDB.lua) and what it
-- shows of a plugin's data object. A plugin's `text` is the display string; `value` + `suffix` is the
-- fallback pair. Some plugins publish `text` as a bare number (an error counter going from "0" to 1):
-- that shows as the number, on the bar and in the fallback tooltip, where it used to leave the block
-- with its icon alone.
-- The real block factory runs over game stubs and a broker: the real libraries (LibStub,
-- CallbackHandler-1.0, LibDataBroker-1.1) when the working tree has them under Libs/ (the packager's
-- externals, not in the repository), and a small stand-in with the same contract either way: a write
-- that changes a field fires LibDataBroker_AttributeChanged_<name> with (event, name, key, value, object).
--   lua .tools/tests/test_db_ldb_numeric_text.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local fails, count = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        print("  FAIL: " .. msg)
    end
end

local function Exists(path)
    local f = io.open(ROOT .. "/" .. path, "rb")
    if f then f:close() end
    return f ~= nil
end

-- The stand-in broker
local function StandIn()
    local lib = { objs = {}, cbs = {} }
    function lib:NewDataObject(name, fields)
        local store = {}
        for k, v in pairs(fields or {}) do store[k] = v end
        local proxy = setmetatable({}, {
            __index = store,
            __newindex = function(self, key, value)
                if store[key] == value then return end
                store[key] = value
                local ev = "LibDataBroker_AttributeChanged_" .. name
                for _, fn in pairs(lib.cbs[ev] or {}) do fn(ev, name, key, value, self) end
            end,
        })
        self.objs[name] = proxy
        return proxy
    end
    function lib:GetDataObjectByName(name) return self.objs[name] end
    function lib.RegisterCallback(owner, ev, fn)
        lib.cbs[ev] = lib.cbs[ev] or {}
        lib.cbs[ev][owner] = fn
    end
    function lib.UnregisterCallback(owner, ev)
        if lib.cbs[ev] then lib.cbs[ev][owner] = nil end
    end
    return lib
end

-- The real libraries, in an environment of their own
local function RealBroker()
    local env = setmetatable({
        securecallfunction = function(f, ...) return f(...) end,
        strmatch = string.match,
        geterrorhandler = function() return function(e) error(e, 0) end end,
    }, { __index = _G })
    env._G = env
    for _, path in ipairs({ "Libs/LibStub/LibStub.lua", "Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua", "Libs/LibDataBroker-1.1/LibDataBroker-1.1.lua" }) do
        local chunk = assert(loadfile(ROOT .. "/" .. path))
        setfenv(chunk, env)
        chunk()
    end
    return env.LibStub:GetLibrary("LibDataBroker-1.1")
end

-- One block over one broker
local function Scenario(broker, name)
    local created = {}
    local function noop() end
    local function NewObj(kind)
        local o = { _kind = kind, _shown = true, _w = 60, _h = 20 }
        created[kind] = created[kind] or {}
        created[kind][#created[kind] + 1] = o
        local m = {}
        function m:SetText(s) self._text = s; self._sets = (self._sets or 0) + 1 end
        function m:GetText() return self._text end
        function m:GetStringWidth() return self._text and (#tostring(self._text) * 6) or 0 end
        function m:GetStringHeight() return 12 end
        function m:IsShown() return self._shown end
        function m:Show() self._shown = true end
        function m:Hide() self._shown = false end
        function m:SetSize(w, h) self._w, self._h = w, h end
        function m:GetWidth() return self._w end
        function m:GetHeight() return self._h end
        function m:CreateTexture() return NewObj("Texture") end
        function m:CreateFontString() return NewObj("FontString") end
        function m:SetScript(script, fn) self["_script_" .. script] = fn end
        function m:IsOwned() return false end
        return setmetatable(o, { __index = function(_, k)
            if m[k] then return m[k] end
            if type(k) == "string" and k:match("^%u") then return noop end
            return nil
        end })
    end
    local tip = {}
    local ns = { L = setmetatable({}, { __index = function(_, k) return k end }), BlockFactories = {} }
    ns.BlockKit = {
        ICON_GAP = 4, CONTENT_BASE = 30,
        InstKey = function(ctx, cfg) return ctx.id .. ":" .. cfg.id end,
        MakeEventFrame = function() return NewObj("EventFrame") end,
        RegisterInstEvents = noop, UnregisterInstEvents = noop,
        VSlotW = function() return 80 end,
        MaybeRelayout = noop, AttachTextOffset = noop,
        BlockColorOf = function() return 1, 1, 1 end,
        IconColorOf = function() return 1, 1, 1 end,
    }
    ns.GetLDB = function() return broker end
    ns.GetAccent = function() return 0, 1, 0 end
    ns.SetFont, ns.ResetInlineText, ns.SetWrappedText = noop, noop, noop
    ns.SnapToPixelGrid = function(v) return v end
    ns.LDBLabel = function(source) return source end
    ns.Tip_Begin = function() tip = {} end
    ns.Tip_AddLine = function(s) tip[#tip + 1] = s end
    ns.Tip_AddDouble, ns.Tip_Show, ns.Tip_Hide = noop, noop, noop

    local env = setmetatable({
        CreateFrame = function(kind) return NewObj(kind) end,
        InCombatLockdown = function() return false end,
        GameTooltip = NewObj("GameTooltip"),
        EllesmereUI = { L = function(s) return s end },
    }, { __index = _G })
    local chunk = assert(loadfile(ROOT .. "/EllesmereUIDataBars/Blocks/LDB.lua"))
    setfenv(chunk, env)
    chunk("EllesmereUIDataBars", ns)

    local source = "Counter"
    local dobj = broker:NewDataObject(source, { type = "data source", text = "0", icon = "Interface\\Icons\\x" })
    local settings = { source = source }
    local content = NewObj("Frame")
    local inst = ns.BlockFactories.ldb({ id = 1, settings = settings }, 1, content, { id = 7, cfg = {},
        GetThickness = function() return 22 end, IsVertical = function() return false end, IsBarAtTop = function() return true end })
    local fs = created.FontString[1]
    local button = created.Button[1]
    inst:Enable()
    inst:Refresh()
    local function Shows() return tostring(fs:GetText()) end
    local function is(want, what) check(fs:GetText() == want, name .. ": " .. what .. " (shows " .. Shows() .. ")") end

    is("0", "a text of '0'")
    -- a plugin's write reaches the block through the broker's own callback: nothing else repaints it here
    dobj.text = 1
    is("1", "a text of the number 1")
    local narrow = content:GetWidth()
    dobj.text = 12345
    is("12345", "a text of the number 12345")
    check(content:GetWidth() > narrow, name .. ": the block does not widen with the longer number")
    dobj.text = 0
    is("0", "a text of the number 0")
    dobj.text = 1.5
    is("1.5", "a text of the number 1.5")
    dobj.text = -3
    is("-3", "a text of the number -3")

    -- Show Label and Show Text treat a number as any other text
    dobj.label = "Errors"
    settings.showLabel = true
    dobj.text = 3
    is("Errors: 3", "Show Label with a number")
    settings.showText = false
    inst:Refresh()
    is("Errors", "Show Text off drops the number")
    settings.showText, settings.showLabel = nil, nil
    inst:Refresh()
    is("3", "back to the number alone")
    -- with the plugin's colours kept, too
    settings.stripColors = false
    inst:Refresh()
    is("3", "the number with Strip Colors off")
    settings.stripColors = nil

    -- the fallback tooltip (a plugin with no tooltip of its own) lists it as well
    button._script_OnEnter()
    local listed = false
    for _, line in ipairs(tip) do if line == "3" then listed = true end end
    check(tip[1] == source and listed, name .. ": the fallback tooltip does not list the number: " .. table.concat(tip, " | "))
    button._script_OnLeave()

    -- text first, value + suffix as the fallback: a number is a text
    dobj.value = 9
    dobj.suffix = "x"
    dobj.text = 5
    is("5", "a number beside a value pair: the text shows")
    dobj.text = "|cffff0000Red|r"
    is("Red", "a text with colour codes")
    dobj.text = ""
    is("9 x", "an empty text falls back to value and suffix")
    dobj.text = nil
    is("9 x", "no text falls back to value and suffix")
    dobj.text = true
    is("9 x", "a text that is neither a string nor a number is not shown")
    dobj.value = nil
    is("", "no text and no value")
    dobj.text = 7
    is("7", "and a number again")

    -- a field the block does not draw repaints nothing
    local sets = fs._sets
    dobj.somethingElse = 4
    check(fs._sets == sets, name .. ": a field the block does not draw repainted it")
    dobj.text = 8
    check(fs._sets == sets + 1 and fs:GetText() == "8", name .. ": a new text repaints once")
    dobj.text = 8
    check(fs._sets == sets + 1, name .. ": the same text again repaints nothing")
end

Scenario(StandIn(), "stand-in broker")
local real = Exists("Libs/LibStub/LibStub.lua") and Exists("Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua")
    and Exists("Libs/LibDataBroker-1.1/LibDataBroker-1.1.lua")
if real then Scenario(RealBroker(), "the real libraries") end

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print("PASS test_db_ldb_numeric_text (" .. count .. " checks; " .. (real and "the stand-in and the real libraries" or "the stand-in broker only: no Libs/ in this tree") .. ")")
