if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_ActionBars_ForeverSwingSweep.lua -- WoW FOREVER ONLY: the Swing Timer
--  swipe on action buttons.
--
--  On-next-swing attacks (EllesmereUI.FOREVER_NEXT_SWING: Heroic Strike,
--  Cleave, Maul, Raptor Strike) show no cooldown while they wait for the swing.
--  With Show Swing Timer on Attacks (profile swingTimerSwipe, off by default)
--  a button holding one shows the weapon swing the attack rides: each
--  PLAYER_SWING of that hand starts a swipe for the swing's duration. The
--  attack lookup is the parent's (EllesmereUI.ForeverNextSwingOf); the
--  Cooldown Manager's twin is EUI_CDM_ForeverSwingSweep.lua.
--
--  The swipe is a Cooldown of our own over the button's, never the button's:
--  the dispatcher clears that one on every cooldown pass, and a real cooldown
--  keeps it. The engine animates it; Lua runs at a swing's start and on the
--  next frame after a slot or page change. A page change, the bars' page edge
--  and the full apply look at every button; a slot change looks only at the
--  buttons on that slot. A button is dressed again only when one of its style
--  inputs moved, and its swipe set or cleared only when that changes.
--
--  Cost: off, nothing is registered and nothing runs (ns.AB_SwingSweepApply,
--  nil-guarded in the full apply, reads the setting and returns).
-------------------------------------------------------------------------------
local _, ns = ...

-- The swing API is the Forever client's; a class with no such attack has
-- nothing to show. The options row does not exist past this point either.
if not (C_SwingTimer and Enum.PlayerSwingType) or EllesmereUI.ForeverNextSwingNames() == false then return end

local ipairs, pairs = ipairs, pairs
local GetTime = GetTime
local C_Timer_After = C_Timer.After
local SwingOf = EllesmereUI.ForeverNextSwingOf
local EAB, barButtons = ns.EAB, ns.barButtons
local I = ns._internals
local BAR_CONFIG, GetButtonActionSlot = I.BAR_CONFIG, I.GetButtonActionSlot
local ButtonSpellID = I.GetButtonSpellID

local sweeps = setmetatable({}, { __mode = "k" })   -- [button] = our Cooldown over it
local stamps = setmetatable({}, { __mode = "k" })   -- [button] = the style inputs it was dressed with
local armed = setmetatable({}, { __mode = "k" })    -- [button] = the swing start the swipe was set for
local shown = {}                        -- [button] = its swing while the swipe is on
local seen = {}
local swingStart, swingDur = {}, {}     -- [swing] = the swing running now
local on = false
local scanPending, scanAll = false, false
local dirtySlots = {}                   -- [action slot] = true: re-test the buttons on it
local ev = ns.TakeShell()

-- Our Cooldown, dressed as the button's own: its rect and level, the profile's
-- swipe color and the button's shape. The stamp names every input.
local function Style(btn)
    local cd = sweeps[btn]
    if not cd then
        cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
        cd:SetDrawBling(false)
        cd:SetDrawEdge(false)
        cd:SetHideCountdownNumbers(true)
        cd:EnableMouse(false)
        sweeps[btn] = cd
        stamps[btn] = {}
    end
    local own = btn.cooldown
    if own and own:IsForbidden() then own = nil end
    local host = own or btn
    local level = own and own:GetFrameLevel() or (btn:GetFrameLevel() + 1)
    local p = EAB.db.profile
    local c = p.cdSwipeColor
    local r, g, b = c and c.r or 0, c and c.g or 0, c and c.b or 0
    local a = (p.cdSwipeAlpha or 80) / 100
    local fd = ns._eabFD[btn]
    local mask = fd and fd.shapeApplied and fd.shapeMask or false
    local path = mask and fd.shapeMaskPath or ""
    local st = stamps[btn]
    if st.host ~= host or st.level ~= level then
        st.host, st.level = host, level
        cd:SetAllPoints(host)
        cd:SetFrameLevel(level)
    end
    if st.r ~= r or st.g ~= g or st.b ~= b or st.a ~= a then
        st.r, st.g, st.b, st.a = r, g, b, a
        cd:SetSwipeColor(r, g, b, a)
    end
    if st.mask ~= mask then
        if st.mask then cd:RemoveMaskTexture(st.mask) end
        if mask then cd:AddMaskTexture(mask) end
        st.mask = mask
    end
    -- One mask per button is reused across shapes: its file is the input.
    if st.path ~= path then
        st.path = path
        cd:SetSwipeTexture(path)
    end
    return cd
end

-- The running swing on one button, or nothing: none running, or the action is
-- on a cooldown of its own, which the button's own swipe shows.
local function Paint(btn, now)
    local cd = Style(btn)
    local swing = shown[btn]
    local start, dur = swingStart[swing], swingDur[swing]
    if start and now < start + dur then
        local slot = GetButtonActionSlot(btn)
        local info = slot and C_ActionBar.GetActionCooldown(slot)
        if not (info and info.isActive and not info.isOnGCD) then
            if armed[btn] ~= start then
                armed[btn] = start
                cd:SetCooldown(start, dur)
            end
            return
        end
    end
    if armed[btn] then
        armed[btn] = nil
        cd:Clear()
    end
end

local function Drop(btn)
    shown[btn] = nil
    if armed[btn] then
        armed[btn] = nil
        sweeps[btn]:Clear()
    end
end

-- Whether a button holds an attack now; paint it or drop it.
local function Test(btn, now)
    local swing = SwingOf(ButtonSpellID(btn))
    if swing then
        shown[btn] = swing
        Paint(btn, now)
        return true
    end
    if shown[btn] then Drop(btn) end
    return false
end

-- Every button (a page change, the page edge, the full apply), or only the
-- buttons on the slots that changed.
local function Scan()
    scanPending = false
    local all = scanAll
    scanAll = false
    if not on then
        wipe(dirtySlots)
        return
    end
    local now = GetTime()
    if all then wipe(seen) end
    for _, info in ipairs(BAR_CONFIG) do
        local btns = not info.isStance and not info.isPetBar and barButtons[info.key]
        if btns then
            for i = 1, #btns do
                local btn = btns[i]
                if btn then
                    if all then
                        if Test(btn, now) then seen[btn] = true end
                    else
                        local slot = GetButtonActionSlot(btn)
                        if slot and dirtySlots[slot] then Test(btn, now) end
                    end
                end
            end
        end
    end
    wipe(dirtySlots)
    if all then
        for btn in pairs(shown) do
            if not seen[btn] then Drop(btn) end
        end
    end
end

-- One scan per frame for a burst, on the next frame (paging settles after its
-- event). `slot`: only that slot's buttons; nil or 0: every button.
local function QueueScan(slot)
    if type(slot) == "number" and slot > 0 then
        dirtySlots[slot] = true
    else
        scanAll = true
    end
    if scanPending then return end
    scanPending = true
    C_Timer_After(0, Scan)
end

-- A bar's page was applied (its state-page edge, EUI_ActionBars_Bars.lua): the
-- one point a stance or form page is known to be in place.
function ns.AB_SwingSweepPageEdge()
    if on then QueueScan() end
end

ev:SetScript("OnEvent", function(_, event, dur, swing)
    if event == "ACTIONBAR_SLOT_CHANGED" then
        QueueScan(dur)   -- payload: the slot
        return
    elseif event ~= "PLAYER_SWING" then
        QueueScan()
        return
    end
    if issecretvalue(dur) or issecretvalue(swing) or swing == nil then return end
    if type(dur) ~= "number" or dur ~= dur or dur <= 0 or dur == math.huge then return end
    local now = GetTime()
    swingStart[swing], swingDur[swing] = now, dur
    for btn, s in pairs(shown) do
        if s == swing then
            -- A page can turn before its scan runs.
            if SwingOf(ButtonSpellID(btn)) == s then
                Paint(btn, now)
            elseif armed[btn] then
                armed[btn] = nil
                sweeps[btn]:Clear()
            end
        end
    end
end)

-- The full apply and the options toggle: listen and paint only while the
-- setting is on.
function ns.AB_SwingSweepApply()
    local p = EAB.db and EAB.db.profile
    local want = (p and p.swingTimerSwipe) and true or false
    if want ~= on then
        on = want
        if on then
            ev:RegisterEvent("PLAYER_SWING")
            ev:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
            ev:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
            ev:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
            ev:RegisterEvent("PLAYER_ENTERING_WORLD")
        else
            ev:UnregisterAllEvents()
            wipe(swingStart)
            wipe(swingDur)
            for btn in pairs(shown) do Drop(btn) end
        end
    end
    if on then
        scanAll = true
        Scan()
    end
end
