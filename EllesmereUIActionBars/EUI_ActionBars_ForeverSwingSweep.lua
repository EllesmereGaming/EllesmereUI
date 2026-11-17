if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_ActionBars_ForeverSwingSweep.lua -- WoW FOREVER ONLY: the Swing Timer
--  swipe on action buttons.
--
--  On-next-swing attacks (EllesmereUI.FOREVER_NEXT_SWING: Heroic Strike,
--  Cleave, Maul, Raptor Strike) have no cooldown, so their buttons show no
--  swipe. With Show Swing Timer on Attacks (profile swingTimerSwipe, off by
--  default) a button holding one shows the weapon swing the attack rides:
--  each PLAYER_SWING of that hand starts a swipe for the swing's duration.
--  The Cooldown Manager's twin is EUI_CDM_ForeverSwingSweep.lua.
--
--  The swipe is a Cooldown of our own over the button's, never the button's:
--  the dispatcher clears that one on every cooldown pass, and a real cooldown
--  keeps it. The engine animates it; Lua runs at a swing's start and, one
--  frame after a slot or page change, to find the buttons again.
--
--  Cost: off, nothing is registered and nothing runs (ns.AB_SwingSweepApply,
--  nil-guarded in the full apply, reads the setting and returns).
-------------------------------------------------------------------------------
local _, ns = ...

-- The swing API is the Forever client's; a class with no such attack has
-- nothing to show. The options row does not exist past this point either.
local SWING = Enum.PlayerSwingType
if not (C_SwingTimer and SWING) then return end
local _, classFile = UnitClass("player")
local attackIDs = EllesmereUI.FOREVER_NEXT_SWING and EllesmereUI.FOREVER_NEXT_SWING[classFile]
if not attackIDs then return end

local ipairs, pairs = ipairs, pairs
local GetTime = GetTime
local C_Timer_After = C_Timer.After
local PlainString = EllesmereUI.PlainString
local EAB, barButtons = ns.EAB, ns.barButtons
local BAR_CONFIG, GetButtonActionSlot = ns._internals.BAR_CONFIG, ns._internals.GetButtonActionSlot
local ButtonSpellID = ns.AB_ButtonSpellID

local nameSwing = {}                    -- [attack name] = the swing it rides
local namesDone = false
local sidSwing = {}                     -- [spellID] = its swing, false = no such attack
local sweeps = setmetatable({}, { __mode = "k" })   -- [button] = our Cooldown over it
local masks = setmetatable({}, { __mode = "k" })    -- [our Cooldown] = the shape mask on it
local shown = {}                        -- [button] = its swing while the swipe is on
local seen = {}
local swingStart, swingDur = {}, {}     -- [swing] = the swing running now
local on = false
local scanPending, lastScan = false, 0
local ev = ns.TakeShell()

-- Every rank shares its attack's name, the way the swing timer matches them.
-- All of them ride the Main Hand swing, the row it shows a queued attack on.
local function ResolveNames()
    namesDone = true
    for i = 1, #attackIDs do
        local n = PlainString(C_Spell.GetSpellName(attackIDs[i]))
        if n then nameSwing[n] = SWING.MainHand else namesDone = false end
    end
end

local function SwingOf(sid)
    if type(sid) ~= "number" or issecretvalue(sid) then return false end
    local s = sidSwing[sid]
    if s ~= nil then return s end
    if not namesDone then ResolveNames() end
    local n = PlainString(C_Spell.GetSpellName(sid))
    s = n and nameSwing[n] or false
    if n and namesDone then sidSwing[sid] = s end
    return s
end

-- Our Cooldown, dressed as the button's own: its rect and level, the profile's
-- swipe colour and the button's shape.
local function Style(btn)
    local cd = sweeps[btn]
    if not cd then
        cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
        cd:SetDrawBling(false)
        cd:SetDrawEdge(false)
        cd:SetHideCountdownNumbers(true)
        cd:EnableMouse(false)
        sweeps[btn] = cd
    end
    local own = btn.cooldown
    if own and own:IsForbidden() then own = nil end
    cd:SetAllPoints(own or btn)
    cd:SetFrameLevel(own and own:GetFrameLevel() or (btn:GetFrameLevel() + 1))
    local p = EAB.db.profile
    local c = p.cdSwipeColor
    cd:SetSwipeColor(c and c.r or 0, c and c.g or 0, c and c.b or 0, (p.cdSwipeAlpha or 80) / 100)
    local fd = ns._eabFD[btn]
    local mask = fd and fd.shapeApplied and fd.shapeMask or nil
    if mask ~= masks[cd] then
        if masks[cd] then cd:RemoveMaskTexture(masks[cd]) end
        if mask then cd:AddMaskTexture(mask) end
        masks[cd] = mask
        cd:SetSwipeTexture(mask and fd.shapeMaskPath or "")
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
            cd:SetCooldown(start, dur)
            return
        end
    end
    cd:Clear()
end

-- The buttons holding an attack now. A swing already running is painted on
-- the ones this pass found.
local function Rescan()
    scanPending = false
    if not on then return end
    lastScan = GetTime()
    wipe(seen)
    for _, info in ipairs(BAR_CONFIG) do
        local btns = not info.isStance and not info.isPetBar and barButtons[info.key]
        if btns then
            for i = 1, #btns do
                local btn = btns[i]
                local swing = btn and SwingOf(ButtonSpellID(btn))
                if swing then
                    seen[btn] = true
                    shown[btn] = swing
                    Paint(btn, lastScan)
                end
            end
        end
    end
    for btn in pairs(shown) do
        if not seen[btn] then
            shown[btn] = nil
            sweeps[btn]:Clear()
        end
    end
end

-- One scan per burst, a frame later (paging settles after its event), and at
-- most one per 0.25s: macro conditionals fire slot changes in storms. Same
-- coalescing as the proc glow's rescan.
local function QueueRescan()
    if scanPending then return end
    scanPending = true
    local elapsed = GetTime() - lastScan
    C_Timer_After(elapsed >= 0.25 and 0 or (0.25 - elapsed), Rescan)
end

-- A bar's page was applied (its state-page edge, EUI_ActionBars_Bars.lua): the
-- one point a stance or form page is known to be in place.
function ns.AB_SwingSweepPageEdge()
    if on then QueueRescan() end
end

ev:SetScript("OnEvent", function(_, event, dur, swing)
    if event ~= "PLAYER_SWING" then
        QueueRescan()
        return
    end
    if issecretvalue(dur) or issecretvalue(swing) or swing == nil then return end
    if type(dur) ~= "number" or dur ~= dur or dur <= 0 or dur == math.huge then return end
    local now = GetTime()
    swingStart[swing], swingDur[swing] = now, dur
    for btn, s in pairs(shown) do
        if s == swing then
            -- A page can turn before its rescan runs.
            if SwingOf(ButtonSpellID(btn)) == s then
                Paint(btn, now)
            else
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
            for btn in pairs(shown) do
                shown[btn] = nil
                sweeps[btn]:Clear()
            end
        end
    end
    if on then Rescan() end
end
