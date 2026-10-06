if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Quickdraw_Live.lua
--
--  The live palette: its view, the secure header, the scroll catcher and
--  its wheel snippet, the palette alpha, ns.Open and ns.Close.
--  Reads the earlier Quickdraw files through ns and ns._qdInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._qdInternals
-- EllesmereUIQuickdraw.lua or an earlier Quickdraw file failed to load.
if not I or I.broken then return end
I.broken = true

local GetCursorPosition = GetCursorPosition
local InCombatLockdown = InCombatLockdown
local GetTime = GetTime

local LIVE_STRATA, liveFrame, P = I.LIVE_STRATA, I.liveFrame, I.P
local LATCH_TIMEOUT, OPEN_TIMEOUT = I.LATCH_TIMEOUT, I.OPEN_TIMEOUT
local secureButtons, SetLiveView = I.secureButtons, I.SetLiveView
local SetScrollCatcher = I.SetScrollCatcher

local liveView
I.liveViewSetters[#I.liveViewSetters + 1] = function(v) liveView = v end
local scrollCatcher
I.scrollCatcherSetters[#I.scrollCatcherSetters + 1] = function(v) scrollCatcher = v end
local cancelButton
I.cancelButtonSetters[#I.cancelButtonSetters + 1] = function(v) cancelButton = v end

local secureHeader
local openedAt = 0

-------------------------------------------------------------------------------
--  The live palette
-------------------------------------------------------------------------------
local function CreateLiveView()
    if liveView then return liveView end
    SetLiveView(ns.CreatePaletteView(UIParent, { frame = liveFrame, live = true }))
    local f = liveView:GetFrame()
    f:SetFrameStrata(LIVE_STRATA)
    f:Hide()
    return liveView
end

-- Scroll capture. The wheel is camera zoom by default, so the fan modes have
-- to take it while the strip is open. A frame only sees OnMouseWheel when the
-- cursor is over it, and in CURSOR mode the strip is drawn AT the cursor -- but
-- the cursor can also be parked anywhere in SCREEN mode, so the catcher is
-- full-screen rather than the strip itself.
--
-- An override binding on MOUSEWHEELUP/DOWN would be the other way to do this,
-- and is not an option: those are protected and could not be claimed at open
-- time in combat, which is exactly when the palette gets used.
--
-- Mouse WHEEL only, never EnableMouse: a full-screen mouse-enabled frame would
-- sit between the player and the world, and would swallow the very button
-- presses the secure activation path depends on.
local function EnsureSecureHeader()
    if not secureHeader then
        secureHeader = CreateFrame("Frame", "EUIQuickdrawSecureHeader",
            UIParent, "SecureHandlerBaseTemplate")
    end
    return secureHeader
end

-- One wheel tick. This is the ONLY place a LIVE strip's index is advanced: an
-- addon may not write these attributes once the player is in combat. The
-- options preview never comes through here -- its wheel jumps the insecure
-- view with SetFanCenter.
local SNIPPET_WHEEL = [==[
    if not self:GetAttribute("eqdOpen") then
        -- Nothing has this open, so it must stop eating camera zoom. This is the
        -- self-heal for a palette that never saw its key-up -- a zone change or
        -- a taxi swallowing the release -- and it costs one notch of zoom.
        self:Hide()
        return false
    end
    local n = tonumber(self:GetAttribute("eqdShown")) or 0
    if n < 1 then return false end

    local delta = offset
    if self:GetAttribute("eqdInvert") then delta = -delta end
    -- Scrolling up travels toward earlier entries, the direction they are drawn
    -- in for a vertical strip, and the natural reading order for a horizontal
    -- one.
    local step = -1
    if delta <= 0 then step = 1 end

    -- The press seeds this at 1, the entry the strip opens centred on, so every
    -- tick is a plain step from wherever the strip already is. The `or 1` is for
    -- a tick that arrives with no press behind it at all.
    local t = (tonumber(self:GetAttribute("eqdFanTarget")) or 1) + step
    self:SetAttribute("eqdFanTarget", t)

    -- Hover arming has to follow the strip as it slides: a tick puts a
    -- different slot under a stationary pointer, and neither the slide nor a
    -- Show raises any motion event for the lattice gate the pointer is
    -- already inside. So every tick re-derives the armed claim from the
    -- pointer's own lattice cell, exactly the way the gates' OnEnter does --
    -- and like it, leaves the arming alone when the pointer is not on the
    -- strip at all, which is the sticky reach.
    local oi = self:GetAttribute("eqdOwnerIdx")
    local btn = oi and self:GetFrameRef("btn" .. oi)
    if btn and btn:GetAttribute("eqdFanMouse") then
        local ui = self:GetFrameRef("ui")
        local x, y
        if ui then x, y = ui:GetMousePosition() end
        if x then
            local cx, cy = x * ui:GetWidth(), y * ui:GetHeight()
            local s = tonumber(btn:GetAttribute("eqdScale")) or 1
            if s <= 0 then s = 1 end
            local hx, hy
            if btn:GetAttribute("eqdFixed") then
                hx = ui:GetWidth() * 0.5 + (tonumber(btn:GetAttribute("eqdPosX")) or 0)
                hy = ui:GetHeight() * 0.5 + (tonumber(btn:GetAttribute("eqdPosY")) or 0)
            else
                hx = tonumber(btn:GetAttribute("eqdGX"))
                hy = tonumber(btn:GetAttribute("eqdGY"))
            end
            local pitch = tonumber(btn:GetAttribute("eqdPitch")) or 0
            if hx and pitch > 0 then
                local along = (cx - hx) / s
                local across = (cy - hy) / s
                if not btn:GetAttribute("eqdFanHoriz") then
                    along, across = -across, along
                end
                local band = tonumber(btn:GetAttribute("eqdFanBand")) or 0
                local win = tonumber(btn:GetAttribute("eqdFanWin")) or 0
                local d = floor(along / pitch + 0.5)
                if abs(across) <= band and abs(along - d * pitch) <= band
                   and abs(d) <= win + 0.5 and d * 2 <= n and -d * 2 < n then
                    btn:SetAttribute("eqdArmed",
                        tonumber(btn:GetAttribute("eqdClaimAt" .. (((t - 1 + d) % n) + 1))))
                end
            end
        end
    end
    return false
]==]

local function EnsureScrollCatcher()
    if scrollCatcher then return scrollCatcher end
    local f = CreateFrame("Frame", "EUIQuickdrawScrollCatcher", UIParent,
        "SecureHandlerBaseTemplate")
    f:SetAllPoints(UIParent)
    f:SetFrameStrata(LIVE_STRATA)
    f:SetFrameLevel(1)
    f:EnableMouseWheel(true)
    -- The wheel snippet re-derives the hover-armed nest under a stationary
    -- pointer, and reads the cursor the same way every other snippet does.
    SecureHandlerSetFrameRef(f, "ui", UIParent)
    SecureHandlerWrapScript(f, "OnMouseWheel", EnsureSecureHeader(), SNIPPET_WHEEL)
    f:Hide()
    SetScrollCatcher(f)
    return f
end

-- Flick-ahead. The palette is held invisible for a moment after the key goes down
-- and then fades in, so a gesture finished inside that window never summons a
-- menu at all. It is a DRAWING delay only: the frame is shown and its OnUpdate
-- is running the whole time, so the selection a fast flick lands on is exactly
-- the one a slow one would have.
--
-- Arc only. A fan has to be read before it can be steered, and a scroll fan
-- cannot even be entered without seeing where the strip starts.
local function FlickAlpha()
    -- HARDCODED flick-ahead (the settings were removed): the arc stays
    -- invisible for `delay` seconds after the press, then fades in over
    -- `fade`. Selection is live the whole time -- only the drawing waits.
    -- PARKED AT 0/0: the slam-open (AdvanceSlam) is the arc's reveal now and
    -- has to be visible from the press itself; raise the pair to bring the
    -- flick hold back on top of it.
    if liveView:IsFan() then return 1 end
    local delay, fade = 0, 0
    local t = GetTime() - openedAt
    if t <= delay then return 0 end
    if fade <= 0 or t >= delay + fade then return 1 end
    return (t - delay) / fade
end

-- The last alpha actually applied. Nothing else writes the live frame's alpha,
-- so a repeat is a redraw of the frame and everything under it for a value it
-- already carries -- and past the flick-ahead fade every frame of a hold is a
-- repeat. The strip holds full brightness however far the pointer travels:
-- leaving it speaks through the selection clearing, never through a dim.
local paletteAlpha = nil

local function UpdatePaletteAlpha()
    local a = FlickAlpha()
    if a == paletteAlpha then return end
    paletteAlpha = a
    liveView:GetFrame():SetAlpha(a)
end

local function OnPaletteUpdate(_, elapsed)
    local now = GetTime()
    -- A latched menu has no key held, so the backstop that catches a lost
    -- key-up is not what it needs -- it is meant to sit there while the player
    -- decides. It still gets one, well past the held palette's: a menu left
    -- open holds the Select key, which may be a plain mouse button.
    --
    -- Read off the button rather than off the profile: the latch is the
    -- SNIPPET's answer, and a palette with the switch on but no Select key set
    -- never latched at all. Reading an attribute is unrestricted in combat.
    local btn = secureButtons[liveView:GetPaletteIndex()]
    local latched = btn and btn:GetAttribute("eqdLatched")
    -- ns.Close is INSECURE, and a latched menu's teardown -- the two bindings,
    -- the ownership stamp, the gates -- is every one of the protected calls a
    -- fight refuses. Timing out mid-fight would put the menu off screen and
    -- leave the Select key claimed until PLAYER_REGEN_ENABLED picked the rest
    -- up, so the timer simply does not run there: it takes effect the moment
    -- the fight ends, and this handler is still ticking to notice. A menu the
    -- player latched open and took into a fight is one they asked for.
    --
    -- The held palette's own backstop is unaffected -- its close rides a key
    -- release through the sandbox and was never refused anything.
    if not (latched and InCombatLockdown()) then
        if now - openedAt > (latched and LATCH_TIMEOUT or OPEN_TIMEOUT) then
            ns.Close()
            return
        end
    end
    if not liveView:SteerUnchanged() then
        if liveView:IsPointerLayout() then
            liveView:AdvanceGrid()
        elseif liveView:IsFan() then
            liveView:AdvanceFan(elapsed)
        else
            liveView:AdvanceArc()
        end
    end
    -- Time-based, so it runs even on the frames the steer skip above took.
    UpdatePaletteAlpha()
    -- Outside the steer skip for the same reason: a modifier goes down without
    -- the cursor moving, and that is the whole gesture this answers.
    liveView:AdvanceLiveIcons()
    liveView:AdvancePendingIcons()
    -- Outside the steer skip: the connector line's grow-in and sweep both
    -- keep moving under a cursor that is holding still. Costs two table
    -- reads per frame when no line is up.
    liveView:AdvanceNeedle(now)
    -- After the steering, which repaints alphas flat: the slam's lerp has to
    -- own the frame's final word while it runs.
    liveView:AdvanceSlam(now)
end

-- forceFixed: ignore CURSOR mode and place the palette at its fixed position.
-- Nothing passes it since the full-screen editor was retired; it stays because
-- on-screen drag positioning is being reworked and needs exactly this. Fixed
-- Position mode itself goes through the same branch via p.centerMode.
local function PositionPalette(forceFixed)
    -- The palette that is about to be shown, so a palette pinned to a corner
    -- and one that opens at the cursor can sit side by side in one profile.
    -- Layout has already moved the view onto it.
    local p = liveView:P()
    local palette = liveView:GetFrame()
    palette:ClearAllPoints()
    if forceFixed or p.centerMode == "SCREEN" then
        local s = p.scale or 1
        if s == 0 then s = 1 end
        palette:SetPoint("CENTER", UIParent, "CENTER", (p.posX or 0) / s, (p.posY or 0) / s)
    else
        local es = palette:GetEffectiveScale()
        local x, y = GetCursorPosition()
        palette:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / es, y / es)
    end
end

function ns.Open(paletteIndex)
    local p = P()
    if not p or not p.enabled then return end

    CreateLiveView()
    liveView:Layout(paletteIndex)
    PositionPalette()
    -- After PositionPalette, never before: which side the caption hangs on is
    -- decided by where on the screen this open actually landed, and in cursor
    -- mode that is different every time.
    liveView:PlaceHubText()

    openedAt = GetTime()

    if liveView:IsPointerLayout() then
        -- Nothing selected until the pointer moves, and straying more than a
        -- cell from every entry deselects again -- these layouts' dead zone.
        liveView:ArmMovementGate()
        liveView:AdvanceGrid(true)
        liveView:SetSelection(nil)
    elseif liveView:IsFan() then
        -- Open with the centred entry ALREADY selected, so the entry the strip
        -- opens on costs no ticks at all and the first tick moves by one --
        -- opened unselected, the starting entry would be the one entry that
        -- cannot be chosen without scrolling off it and back. Cancelling is
        -- FanCancelled's job -- throw the pointer clear of the strip.
        liveView:ArmMovementGate()
        liveView.fanTarget = 1
        liveView.fanVisual = 1
        liveView:ApplyFanGeometry()
        -- Guarded: an empty palette has no entry 1 to select, and painting one
        -- would caption the hub with a slot that is not drawn. Under exclusive
        -- hover (Select Action with Mouse) the first paint holds in cursor
        -- mode -- the strip opens centred on the pointer, so entry 1 IS the
        -- hovered one -- but a PINNED strip may open nowhere near the cursor,
        -- and there the first tick's own hover test owns the answer.
        local pOpen = liveView:P()
        local hoverOnly = (pOpen and pOpen.fanMouseSelect) ~= false
        local pinned = pOpen and pOpen.centerMode == "SCREEN"
        local paintFirst = liveView:ShownCount() > 0
            and not (hoverOnly and pinned)
        liveView:SetSelection(paintFirst and 1 or nil)
    else
        -- Through the same pass every later frame goes through, so the ring is
        -- drawn on the first frame exactly as the tick would draw it. With the
        -- gate just armed that is evenly, and nothing selected.
        liveView:ArmMovementGate()
        liveView:AdvanceArc()
        -- Slam-open, from the press itself: the first step runs NOW so the
        -- launch positions are what this frame shows, never a settled ring
        -- for one frame first.
        liveView._slamT0 = openedAt
        liveView:AdvanceSlam(openedAt)
    end

    local palette = liveView:GetFrame()
    -- Applied before the first frame rather than left to OnUpdate: the palette is
    -- shown on this one, and the previous open's alpha would flash through.
    UpdatePaletteAlpha()
    palette:SetScript("OnUpdate", OnPaletteUpdate)
    palette:Show()
end

-- ESCAPE belongs to the game menu again. The release snippet drops this binding
-- on every ordinary close; this is for the closes that never see a release --
-- the open timeout, a zone change -- and it runs whether or not the palette is
-- still up, because the press that finds ESCAPE still bound is exactly the one
-- that has to hand it back.
--
-- Protected in combat, so a close mid-fight leaves the binding standing. That is
-- why PLAYER_REGEN_ENABLED tries again: ESCAPE bound to a palette that closed
-- half an hour ago is a dead key, with no gesture left to free it.
local function ReleaseEscape()
    if cancelButton and not InCombatLockdown() then
        ClearOverrideBindings(cancelButton)
    end
end

-- The rest of what a release puts away -- the scroll catcher, the ownership
-- stamp, and every arming gate the palette had up -- for the closes that never
-- see a key-up. Assigned in EUI_Quickdraw_Runtime.lua (see
-- SetReleaseSecureState), which also keeps the index of a close combat refused
-- for PLAYER_REGEN_ENABLED: every frame it touches is protected, so mid-fight
-- there is nothing it may do.
local ReleaseSecureState

function ns.Close()
    if not liveView then return end
    local palette = liveView:GetFrame()
    if not palette:IsShown() then
        ReleaseEscape()
        return
    end
    palette:SetScript("OnUpdate", nil)
    palette:Hide()
    ReleaseSecureState(liveView:GetPaletteIndex())
    ReleaseEscape()
    -- Both, always together. fanVisual left behind at the strip's last centre
    -- while fanTarget went to nil reads as a settle that can never finish, and
    -- SteerUnchanged takes that to mean the geometry is still moving -- so one
    -- scroll-fan open would cost every later open of ANY layout its per-frame
    -- skip for the rest of the session. Nothing needs it to survive the close:
    -- the strip's own re-seeds it, and both readers default it.
    liveView.fanTarget = nil
    liveView.fanVisual = nil
    liveView:SetSelection(nil)
end

I.CreateLiveView, I.EnsureScrollCatcher = CreateLiveView, EnsureScrollCatcher
I.EnsureSecureHeader, I.ReleaseEscape = EnsureSecureHeader, ReleaseEscape
I.SetReleaseSecureState = function(f) ReleaseSecureState = f end
I.broken = false
