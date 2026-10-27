if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUICdmStanceBar.lua
--  Per-spell Stance Bar hide for cooldown/utility icons: hidden in, or outside,
--  one of the class's stance bar pages (EllesmereUI.CLASS_PAGING_STATES, the
--  same macro conditions the action bars page on), optionally shifting the
--  icons after it. For stance-paged keys, where the icon should follow what
--  the key casts on each page.
--
--  Stored per spell like every per-spell setting (chains over the Apply to Bar
--  tiers): stanceBarHide = "<mode>:<state id>", mode in, inShift, out or
--  outShift; nil or false is none.
--
--  It runs as one more hide reason in the cooldown-state evaluator
--  (ArmCdStateEval): the hidden alpha, Shift Icons and re-evaluation are that
--  evaluator's. A page change fires UPDATE_BONUS_ACTIONBAR (UPDATE_STEALTH for
--  Prowl), which the usable/form watch re-arms on while an icon uses it.
--
--  Cost: nothing until some saved spell has the setting. ns._cdmAnyStanceBar
--  is set once by RescanStanceBarFlag at setup, or by the menu on first use
--  (monotonic, like the other per-spell gates).
-------------------------------------------------------------------------------
local _, ns = ...

local MODES = {
    ["in"]     = { inside = true },
    inShift    = { inside = true, shift = true },
    out        = { inside = false },
    outShift   = { inside = false, shift = true },
}

-- value -> { inside, shift, macro } (false when the value is not one of ours
-- or names a state this class does not have).
local _parsed = {}

local function Parse(value)
    local p = _parsed[value]
    if p ~= nil then return p end
    p = false
    local mode, id = value:match("^(%a+):([%w_]+)$")
    local m = mode and MODES[mode]
    local states = m and EllesmereUI.CLASS_PAGING_STATES[select(2, UnitClass("player"))]
    if states then
        for _, st in ipairs(states) do
            if st.id == id then
                p = { inside = m.inside, shift = m.shift == true, macro = st.macro .. " 1" }
                break
            end
        end
    end
    _parsed[value] = p
    return p
end

-- The icon's Stance Bar setting (a resolved settings table), or nil for none.
-- Given a frame we inject, nothing: its value lives in customActiveStates and the
-- Fake-Active engine runs it (as ns.CdStateOf), so a bar-tier value never shows
-- behind that menu's back.
function ns.CdmStanceBarOf(settings, frame)
    if not ns._cdmAnyStanceBar or not settings then return nil end
    if frame and ns.CdmIsInjectedFrame and ns.CdmIsInjectedFrame(frame) then return nil end
    local v = settings.stanceBarHide
    if type(v) ~= "string" or not Parse(v) then return nil end
    return v
end

-- hidden, shift for a stored value right now.
function ns.CdmStanceBarHidden(value)
    local p = value and Parse(value)
    if not p then return false, false end
    local inState = SecureCmdOptionParse(p.macro) == "1"
    if inState == p.inside then return true, p.shift end
    return false, false
end

-- Stance Bar gate: set ns._cdmAnyStanceBar once if any saved spell (any spec),
-- bar tier or custom spell / preset has the setting. Same monotonic,
-- scanned-once contract as the Talent Conditions gate.
function ns.RescanStanceBarFlag()
    if ns._cdmAnyStanceBar or ns._stanceBarFlagScanned then return end
    if not EllesmereUIDB then return end
    ns._stanceBarFlagScanned = true
    local function Has(ss)
        if type(rawget(ss, "stanceBarHide")) == "string" then
            ns._cdmAnyStanceBar = true
            return true
        end
    end
    if ns.ForEachSavedSettingsBlock(Has) then return end
    local cas = ns.GetCustomActiveStates and ns.GetCustomActiveStates()
    if cas then
        for _, e in pairs(cas) do
            if type(e) == "table" and Has(e) then return end
        end
    end
end
