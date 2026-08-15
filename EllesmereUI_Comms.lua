-------------------------------------------------------------------------------
--  EllesmereUI_Comms.lua -- Shared addon-to-addon messaging
--
--  One transport for every module that needs to ask the group something the
--  client will not tell it: durability, weapon enchants, later a shared note.
--  It lives in the parent for the same reason EllesmereUI_Glows.lua does --
--  modules attach here instead of each growing its own channel, its own
--  throttle and its own parser.
--
--  ONE PREFIX, TYPED MESSAGES. Registering a prefix per message kind burns a
--  scarce global budget for nothing; the kind travels inside instead:
--
--      <version>|<type>|<payload>
--
--  Version leads so a future format can be recognised and skipped rather than
--  misread. An unknown type is dropped in silence, which is what makes an old
--  client safe in a group with a new one.
--
--  THE INBOUND HANDLER IS THE ATTACK SURFACE. Everything here arrives from
--  another player's client and is assumed hostile:
--
--    * the envelope is matched by a pattern with a bounded type charset, so a
--      malformed line cannot reach a handler at all
--    * no value off the wire indexes a table, sizes an allocation, or is
--      concatenated into anything executable -- there is no loadstring here
--      and there must never be one
--    * senders are rate limited individually, so one client cannot make every
--      other client work by shouting
--    * payloads are handed to modules as opaque strings; each validates its
--      own shape, because only it knows what shape it expects
--
--  THE GAME'S OWN LIMITS, handled once here rather than in every caller:
--
--    * 255 bytes per message. Anything longer is the caller's problem for now;
--      chunking arrives with the first feature that needs it.
--    * INSTANCE_CHAT is mandatory inside instanced group content. Sending to
--      RAID there does not route, and that is a silent failure -- Channel()
--      is the single place that decision is made.
--    * the client throttles bursts, so sends leave through a queue, and forty
--      clients answering one request stagger their replies. Without that
--      spread most of the answers are dropped and nobody is told.
-------------------------------------------------------------------------------

local PREFIX      = "EllesmereUI"
local VERSION     = 1
local MAX_BYTES   = 255
local SEND_PERIOD = 0.12   -- ~8 messages a second, well inside the throttle
local REPLY_SPREAD = 3     -- seconds a broadcast reply may wait before leaving

-- Per sender, per second. A raid check is one reply each; anything past this
-- is either a bug or an attempt to make us work.
local RATE_LIMIT  = 5

local Comms = {}
EllesmereUI.Comms = Comms

local handlers = {}     -- type -> function(sender, payload)
local queue    = {}     -- pending outbound, already formatted
local seen     = {}     -- sender -> { count, window }

-------------------------------------------------------------------------------
--  Outbound
-------------------------------------------------------------------------------

-- The one place the channel is decided. INSTANCE_CHAT is not a preference
-- inside instanced content -- RAID simply does not route there.
local function Channel()
    local inInstance, kind = IsInInstance()
    if inInstance and (kind == "party" or kind == "raid") then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    return nil
end

-- Returns falsy when the queue runs dry, which is the shared ticker's signal
-- to stop itself -- so an idle transport costs nothing at all.
local function Drain()
    local msg = table.remove(queue, 1)
    if not msg then return false end
    local channel = Channel()
    if channel then C_ChatInfo.SendAddonMessage(PREFIX, msg, channel) end
    return true   -- keep draining even if that one was dropped
end

-- An interval driver rather than a per-frame one accumulating dt: the C engine
-- sleeps between fires, so this costs no Lua at frame rate.
local sender = EllesmereUI.Tick.NewAnimTicker(CreateFrame("Frame"), Drain, SEND_PERIOD)

-- `payload` must be a string the receiving module knows how to read; this
-- layer never inspects it. `spread` is seconds: with it, the message leaves
-- after a random slice of that window, which is what keeps forty clients
-- answering one broadcast from landing in a single frame and mostly being
-- dropped. That is a property of the transport, not of any caller.
function Comms.Send(msgType, payload, spread)
    if not Channel() then return end
    local text = VERSION .. "|" .. msgType .. "|" .. (payload or "")
    -- Silently truncating would hand the receiver a half message that parses.
    -- Refusing is the honest failure until chunking exists.
    if #text > MAX_BYTES then return end
    if spread then
        C_Timer.After(math.random() * spread, function()
            queue[#queue + 1] = text
            sender.Start()
        end)
        return
    end
    queue[#queue + 1] = text
    sender.Start()
end

-- Seconds a broadcast answer may wait before leaving. Exposed so a caller says
-- Comms.Send(t, p, Comms.REPLY_SPREAD) rather than inventing its own number.
Comms.REPLY_SPREAD = REPLY_SPREAD

-------------------------------------------------------------------------------
--  Inbound
-------------------------------------------------------------------------------

-- Register a handler for one message type. Called as fn(sender, payload) with
-- payload an unvalidated string: the module owns its own format, so only the
-- module can check it.
function Comms.On(msgType, fn)
    if type(msgType) ~= "string" or type(fn) ~= "function" then return end
    handlers[msgType] = fn
end

-- True while this sender is inside its budget. The table is wiped on every
-- roster change, so it cannot grow across an evening of pugs.
local function WithinRate(sender)
    local now = GetTime()
    local e = seen[sender]
    if not e then
        seen[sender] = { count = 1, window = now }
        return true
    end
    if now - e.window >= 1 then
        e.count, e.window = 1, now
        return true
    end
    e.count = e.count + 1
    return e.count <= RATE_LIMIT
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("CHAT_MSG_ADDON")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:SetScript("OnEvent", function(_, event, prefix, text, _, sender)
    if event == "GROUP_ROSTER_UPDATE" then
        wipe(seen)
        return
    end
    if prefix ~= PREFIX then return end
    if type(text) ~= "string" or #text > MAX_BYTES then return end
    if type(sender) ~= "string" or not WithinRate(sender) then return end

    -- Bounded on purpose: a version that is not digits, or a type carrying
    -- anything but word characters, never reaches a handler.
    --
    -- The version is the ENVELOPE's, and it is compared as "not from the
    -- future" rather than for equality. Equality would make one envelope bump
    -- a hard fork for every message type at once, including the ones that did
    -- not change -- and the churn is all in payloads, which each module
    -- versions for itself.
    local v, msgType, payload = text:match("^(%d+)|([%w_]+)|(.*)$")
    v = v and tonumber(v)
    if not v or v > VERSION then return end

    local fn = handlers[msgType]
    if fn then pcall(fn, sender, payload) end
end)

-------------------------------------------------------------------------------
--  Lifecycle
-------------------------------------------------------------------------------

-- Registering the prefix is what makes CHAT_MSG_ADDON fire for it at all.
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    end
end)
