if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
local _, ns = ...
local EUI = _G.EllesmereUI
if not EUI then return end

local ECHAT = ns.ECHAT
if not ECHAT then return end

local PP = EUI.PP

-- Chat Bubbles (chatBubbles.enabled, default off), configured on the Chat options page.
-- Blizzard's bubbles are not forbidden outside instances, so rather than replace them we ride
-- on them: their switches stay ON, we blank the chrome and hang a styled frame on the frame
-- carrying their position, which the engine has already put over the speaker's head. No
-- nameplate is involved and the player's own lines work too. Inside instances they ARE
-- forbidden: we stay away and hand the switches back, as PLAYER_LOGOUT does for any we still
-- hold, so disabling the addon cannot strand one. What we draw is the bubble's OWN text, so
-- whatever the client formatted into it carries over. Nothing runs while off.

local C_CVar, C_Timer = C_CVar, C_Timer
local InCombatLockdown, IsInInstance = InCombatLockdown, IsInInstance

local MIN_WIDTH = 40
local WHITE = "Interface\\Buttons\\WHITE8X8"
-- How long we keep looking for the bubble a chat line just produced. The engine builds it
-- within a frame or two; anything still unmatched after this never had one (a channel
-- Blizzard does not bubble, or a speaker out of range). The first passes run on consecutive
-- frames rather than a step apart, because a bubble on a frame we have never seen is visible
-- until we find it; the rest space out so a slow moment keeps roughly the same total grace.
local SWEEP_STEP = 0.05
local SWEEP_FAST_TRIES = 2
local SWEEP_TRIES = 8

-- Blizzard's three bubble switches. chatBubbles is taken over as soon as any of say, yell,
-- emotes or NPC lines is ticked, since that is what the feature exists to restyle and there
-- is nothing to ride on without it; clear all four and it goes back, because there is then
-- nothing left for it to draw. The party and raid switches stay the player's own call, taken
-- over only while the matching channel is ticked, and SeedChannels seeds those two ticks from
-- the switches themselves. All three are handed back the way they were found.
local BLIZZ_CVARS = { "chatBubbles", "chatBubblesParty", "chatBubblesRaid" }

-- Chat event -> the setting key that decides whether we draw it. Guild is absent on purpose:
-- Blizzard draws no bubble for guild chat, so there is no frame to ride and no position to
-- borrow. Instance chat sits with party because an instance group is party-shaped and
-- chatBubblesParty is the switch Blizzard ships on; which of the two actually governs it is
-- Blizzard's own mapping and was not verified. Getting that wrong costs nothing visible: a
-- line whose bubble never appears expires on its own.
local EVENT_CHANNEL = {
    CHAT_MSG_SAY                  = "say",
    CHAT_MSG_YELL                 = "yell",
    CHAT_MSG_PARTY                = "party",
    CHAT_MSG_PARTY_LEADER         = "party",
    CHAT_MSG_INSTANCE_CHAT        = "party",
    CHAT_MSG_INSTANCE_CHAT_LEADER = "party",
    CHAT_MSG_RAID                 = "raid",
    CHAT_MSG_RAID_LEADER          = "raid",
    CHAT_MSG_MONSTER_SAY          = "npc",
    CHAT_MSG_MONSTER_YELL         = "npc",
    CHAT_MSG_MONSTER_EMOTE        = "npc",
    CHAT_MSG_MONSTER_PARTY        = "npc",
    CHAT_MSG_MONSTER_WHISPER      = "npc",
    CHAT_MSG_EMOTE                = "emote",
}

local CB = {}
ns.ChatBubbles = CB

local active = false          -- events registered and CVars asserted
local suspended = false       -- inside an instance, where we never draw
local ours = {}               -- Blizzard bubble frame -> our frame riding on it
-- Side tables keyed by Blizzard's frame, never fields written onto it: every other access to
-- these frames is guarded because one can be reclassified as forbidden under us, and writing
-- a marker onto a forbidden frame raises. Weak keys, the house pattern for this, so nothing
-- of ours keeps an engine frame alive.
local WEAK_KEYS = { __mode = "k" }
local hooked = setmetatable({}, WEAK_KEYS)   -- frame -> true, hooks are for the session
local childOf = setmetatable({}, WEAK_KEYS)  -- frame -> its templated child
-- Appearance order. A bubble already on screen when a line arrived cannot be the bubble that
-- line produced, however well the text matches, so both sides carry a stamp off this counter
-- and the match below refuses to look backwards.
local seenTick = 0
local seenAt = setmetatable({}, WEAK_KEYS)   -- frame -> the tick it last appeared on
local pending = {}            -- chat lines still looking for their bubble
-- Bubbles blanked the moment they appeared, before their text could be read. Value is the
-- sweep count they have survived: the sweep either claims one or hands its chrome back.
local blanked = {}
local pool = {}
local eventFrame
local EnsureFrame
local sweepScheduled = false

local function Cfg()
    return ECHAT.BubblesDB and ECHAT.BubblesDB()
end

local function Enabled()
    local cfg = Cfg()
    return cfg ~= nil and cfg.enabled == true
end

-------------------------------------------------------------------------------
--  Secret-safe helpers
-------------------------------------------------------------------------------

-- pcall'd as well as presence-tested: issecretvalue is absent on older clients, and the test
-- itself can raise.
local function IsSecret(v)
    if not issecretvalue then return false end
    local ok, r = pcall(issecretvalue, v)
    return ok and r or false
end

-- Upvalues instead of closures: these run once per incoming line and per candidate bubble,
-- and a pcall'd closure would allocate every time.
local _cmpA, _cmpB, _cmpEq

local function RawEq()
    _cmpEq = (_cmpA == _cmpB)
end

-- Either side can be a secret string in restricted content, and comparing one raises.
local function SafeEq(a, b)
    if a == nil or b == nil then return false end
    _cmpA, _cmpB, _cmpEq = a, b, false
    local ok = pcall(RawEq)
    _cmpA, _cmpB = nil, nil
    return ok and _cmpEq == true
end

local _findHay, _findNeedle, _findHit

local function RawFind()
    _findHit = string.find(_findHay, _findNeedle, 1, true) ~= nil
end

-- Blizzard's bubble text is not always byte-identical to the chat event's: an emote arrives
-- as a token the client fills in. A plain-text containment test catches those without
-- pretending to know Blizzard's exact formatting.
local function SafeContains(hay, needle)
    if hay == nil or needle == nil then return false end
    _findHay, _findNeedle, _findHit = hay, needle, false
    local ok = pcall(RawFind)
    _findHay, _findNeedle = nil, nil
    return ok and _findHit == true
end

local _measureFS, _measureMax, _measureW, _measureH

-- Both clamps sit inside the guarded call on purpose: a secret measurement raises on the
-- comparison, which is what we want to catch, and never reaches the caller's arithmetic.
local function RawMeasure()
    -- Width first, then the final width in place, and only then the height. This is the order
    -- the shared tooltip uses to auto-size wrapped text (EllesmereUI_UICore.lua), and the
    -- order matters: GetStringWidth reports the natural, single-line width and ignores the
    -- wrap, so the cap has to be applied by hand, while GetStringHeight only counts the
    -- wrapped lines once the width causing the wrap is actually set.
    _measureFS:SetWidth(_measureMax)
    local w = _measureFS:GetStringWidth()
    if w > _measureMax then w = _measureMax end
    if w < MIN_WIDTH then w = MIN_WIDTH end
    -- One pixel of slack: PP.Scale truncates toward zero, so a string whose natural width
    -- sits just above a pixel boundary would be clamped narrower than it measured and wrap a
    -- word it did not need to. Applied BEFORE the height is read, so the height always
    -- describes the width the FontString actually keeps, and reported back instead of the
    -- raw measurement so the frame reserves exactly the room the FontString took.
    local textW = PP.Scale(w) + PP.mult
    if textW > _measureMax then textW = _measureMax end
    _measureFS:SetWidth(textW)
    -- Poking the parent's height forces the widget to re-resolve its layout; without it the
    -- height read below can still answer for the width from before.
    local parent = _measureFS:GetParent()
    if parent then parent:SetHeight(10) end
    local h = _measureFS:GetStringHeight()
    if h < 1 then h = 1 end
    -- The same pixel of slack as the width above, for the same reason: PP.Size snaps the
    -- frame down, and a box a hair shorter than the text it wraps reads as a tight background
    -- at non-native UI scale.
    _measureW, _measureH = textW, PP.Scale(h) + PP.mult
end

-- A secret string can be shown but not measured. Falling back to the full width keeps
-- the bubble readable instead of collapsing it to nothing.
local function MeasureText(fs, maxWidth, fallbackHeight)
    _measureFS, _measureMax = fs, maxWidth
    _measureW, _measureH = nil, nil
    local ok = pcall(RawMeasure)
    _measureFS = nil
    if not ok or not _measureW or not _measureH then
        -- The guarded call can die before it sets a width, and a FontString left unconstrained
        -- never wraps at all. Full width is the readable answer either way.
        fs:SetWidth(maxWidth)
        return maxWidth, fallbackHeight
    end
    return _measureW, _measureH
end

-------------------------------------------------------------------------------
--  Blizzard's bubble frame
-------------------------------------------------------------------------------

-- Measured in game on 12.1: GetAllChatBubbles returns an OUTER frame with no regions and a
-- single child. The outer carries the screen position, the child the eleven regions that draw
-- the balloon plus a FontString reachable through the template's "String" parentKey. Both
-- halves are needed, and neither is forbidden outside instances. The pairing is fixed for the
-- frame's life, which is what makes the cache below safe.
local function BlizzParts(outer)
    if not outer then return nil, nil end
    local child = childOf[outer]
    if not child then
        -- Resolved once: GetChildren hands back every child as varargs and allocates on every
        -- call, and this runs per bubble per sweep plus on every hide.
        local ok, c = pcall(outer.GetChildren, outer)
        if not ok or not c then return nil, nil end
        child = c
        childOf[outer] = child
    end
    return child, child.String
end

local _readFS, _readOut

local function RawReadText()
    _readOut = _readFS:GetText()
end

local function BlizzText(fs)
    if not fs then return nil end
    _readFS, _readOut = fs, nil
    local ok = pcall(RawReadText)
    _readFS = nil
    if not ok then return nil end
    return _readOut
end

local _colorFS, _colorR, _colorG, _colorB

local function RawReadColor()
    _colorR, _colorG, _colorB = _colorFS:GetTextColor()
end

-- The colour the engine itself put on this bubble, which is how "follow Blizzard" answers per
-- channel without us mapping chat events to chat types. Guarded like every other read of a
-- Blizzard frame, and secret-tested because a restricted one answers with numbers that cannot
-- be handed to SetTextColor.
local function BlizzTextColor(fs)
    if not fs then return nil end
    _colorFS, _colorR, _colorG, _colorB = fs, nil, nil, nil
    local ok = pcall(RawReadColor)
    _colorFS = nil
    if not ok or _colorR == nil or _colorG == nil or _colorB == nil then return nil end
    if IsSecret(_colorR) or IsSecret(_colorG) or IsSecret(_colorB) then return nil end
    return _colorR, _colorG, _colorB
end

local _alphaFrame, _alphaValue

local function RawSetAlpha()
    _alphaFrame:SetAlpha(_alphaValue)
end

-- Guarded because a bubble can be reclassified as forbidden under us on a zone change, and
-- writing to a forbidden frame raises.
local function SetBlizzAlpha(child, value)
    if not child then return end
    _alphaFrame, _alphaValue = child, value
    pcall(RawSetAlpha)
    _alphaFrame = nil
end

-------------------------------------------------------------------------------
--  Our frames
-------------------------------------------------------------------------------

local function NewBubble()
    -- HIGH: strata is ordered GLOBALLY, not per parent tree. Blizzard's own bubbles and the
    -- nameplates they sit among render below this, which is the point -- ours has to cover
    -- the balloon it replaces. Accepted cost: MEDIUM also carries the action bars and the
    -- chat panel, which a bubble can briefly cover.
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(150)
    f:EnableMouse(false)
    f:Hide()

    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetTexture(WHITE)
    f.bg:SetAllPoints(f)

    f.text = f:CreateFontString(nil, "ARTWORK")
    -- A font before anything else touches this FontString: SetText on one that has none
    -- raises "Font not set" and drops the string, so the first line on every freshly built
    -- frame would come up blank. Show sets the text before Layout, which is what picks the
    -- configured font, because Layout measures that text to size the bubble. Whatever is set
    -- here therefore only ever has to be valid, not right.
    f.text:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    f.text:SetJustifyH("CENTER")
    f.text:SetJustifyV("MIDDLE")
    f.text:SetWordWrap(true)
    -- SetWordWrap alone only breaks at spaces, so a single token wider than the bubble is
    -- truncated with an ellipsis instead of wrapping. Blizzard's own bubble sets this too
    -- (ChatBubbleTemplates.xml calls SetNonSpaceWrap(true) on its String), and the guard is
    -- the shape this codebase already uses for the pair (EllesmereUIDataBars.lua).
    if f.text.SetNonSpaceWrap then f.text:SetNonSpaceWrap(true) end
    f.text:SetPoint("CENTER", f, "CENTER", 0, 0)

    return f
end

local function Acquire()
    local f = table.remove(pool)
    if not f then f = NewBubble() end
    f.inUse = true
    return f
end

-- Ours lives exactly as long as Blizzard's, which is why nothing here fades: the frame we are
-- anchored to is recycled for the next speaker the moment theirs ends, so anything outliving
-- it would have to freeze its own position first. The chrome is handed back in ReleaseBlizz.
local function Release(f)
    -- Guarded because ReleaseAll and an OnHide for the same frame can both land here.
    if not f.inUse then return end
    f.inUse = false

    if f.outer then
        ours[f.outer] = nil
        f.outer = nil
    end
    f:ClearAllPoints()
    f:Hide()
    -- Cleared so the next speaker on this frame gets their own colour, or the configured one,
    -- never the last speaker's.
    f.blizzR, f.blizzG, f.blizzB = nil, nil, nil
    -- Deliberately uncapped. Every bubble frame also builds a PP border container, and PP
    -- registers those permanently (PP.ResnapAllBorders walks the list on each scale or
    -- resolution change and it never shrinks), so the count worth bounding is the number of
    -- frames ever CREATED. An unbounded pool bounds it at peak concurrency.
    pool[#pool + 1] = f
end

-- Blizzard is done with this bubble: let ours go and hand the chrome back, so the recycled
-- frame draws normally for the next speaker, whose channel we may not even be drawing.
local function ReleaseBlizz(outer)
    -- Nothing of ours on this frame, so there is nothing to hand back. The hooks outlive both
    -- the claim and the feature being switched off, so without this every bubble in the game
    -- would pay for a hide of ours for the rest of the session, and one we never touched
    -- would have its alpha rewritten behind Blizzard's back.
    if not ours[outer] and blanked[outer] == nil then return end
    local f = ours[outer]
    if f then Release(f) end
    blanked[outer] = nil
    local child = BlizzParts(outer)
    SetBlizzAlpha(child, 1)
end

-- Every bubble we blanked on sight but never claimed gets its chrome back. Called whenever
-- the sweep can no longer match one, so a channel we do not draw is never left invisible.
local function RestoreBlanked()
    for outer in pairs(blanked) do
        blanked[outer] = nil
        local child = BlizzParts(outer)
        SetBlizzAlpha(child, 1)
    end
end

local function ReleaseAll()
    for outer in pairs(ours) do
        ReleaseBlizz(outer)
    end
    RestoreBlanked()
end

-- Appearance and geometry in ONE pass, never separately: font size, padding and max width all
-- feed the measurement, so restyling a live bubble without re-measuring leaves its text
-- clipped inside a frame still sized for the old settings.
local function Layout(f, cfg)
    -- One place decides what a missing setting is worth.
    local d = (ECHAT.BubbleDefaults and ECHAT.BubbleDefaults()) or cfg

    local bgc = cfg.bgColor or d.bgColor
    f.bg:SetVertexColor(
        (bgc and bgc.r) or 0, (bgc and bgc.g) or 0, (bgc and bgc.b) or 0,
        cfg.background == false and 0 or (cfg.bgAlpha or d.bgAlpha or 0))

    local bc = cfg.borderColor or d.borderColor
    local br, bg, bb = (bc and bc.r) or 0, (bc and bc.g) or 0, (bc and bc.b) or 0
    local ba = (bc and bc.a) or 1
    local size = cfg.borderSize or d.borderSize or 0
    if size > 0 then
        PP.CreateBorder(f, br, bg, bb, ba, size, "OVERLAY", 7)
        PP.UpdateBorder(f, size, br, bg, bb, ba)
        PP.ShowBorder(f)
    else
        PP.HideBorder(f)
    end

    -- ECHAT's own resolvers, not EUI.GetFontPath("chat") directly: the Chat page carries its
    -- own font and outline pickers that override the module font, and a bubble is chat output.
    local path = (ECHAT.GetFont and ECHAT.GetFont())
        or (EUI.GetFontPath and EUI.GetFontPath("chat")) or "Fonts\\FRIZQT__.TTF"
    local flag = (ECHAT.GetOutlineFlag and ECHAT.GetOutlineFlag())
        or (EUI.GetFontOutlineFlag and EUI.GetFontOutlineFlag("chat")) or ""
    local fontSize = cfg.fontSize or d.fontSize or 12
    -- SetFont answers false for a path that no longer resolves (a media addon uninstalled
    -- since the setting was made) and leaves the FontString with NO font at all, which makes
    -- the NEXT SetText raise "Font not set" in Claim, unguarded, from an event handler. Same
    -- guard shape as EllesmereUIQoL_MovementAlert.lua.
    if not f.text:SetFont(path, fontSize, flag) then
        f.text:SetFont("Fonts\\FRIZQT__.TTF", fontSize, flag)
    end
    local tc = cfg.textColor or d.textColor
    local tr, tg, tb = (tc and tc.r) or 1, (tc and tc.g) or 1, (tc and tc.b) or 1
    -- Blizzard's own colour when it was asked for AND we managed to read it; the configured
    -- one otherwise, so a bubble whose colour would not come back is still readable.
    if cfg.followBlizzardColor == true and f.blizzR then
        tr, tg, tb = f.blizzR, f.blizzG, f.blizzB
    end
    f.text:SetTextColor(tr, tg, tb, 1)

    -- Config numbers that end up as frame geometry go through the pixel grid. maxWidth is a
    -- real width (it clamps the FontString), so it is snapped before the measurement.
    local padding = cfg.padding or d.padding or 0
    local maxWidth = PP.Scale(cfg.maxWidth or d.maxWidth or 260)

    -- Three lines, not one: a secret string cannot be measured, and a single-line fallback
    -- cuts a wrapped sentence off. MeasureText leaves the FontString at the width it measured
    -- against, so the frame only has to wrap padding around the result.
    local w, h = MeasureText(f.text, maxWidth, fontSize * 1.4 * 3)
    PP.Size(f, w + padding * 2, h + padding * 2)
end

-- Concentric with Blizzard's frame, not stacked above it: theirs is already where the speaker
-- is, and the two grow to different sizes around the same text. offsetY is the only nudge the
-- user gets, and it rides in on PP.Point so it lands on the pixel grid.
local function Anchor(f, cfg)
    local d = (ECHAT.BubbleDefaults and ECHAT.BubbleDefaults()) or cfg
    local off = cfg.offsetY or d.offsetY or 0
    f:ClearAllPoints()
    PP.Point(f, "CENTER", f.outer, "CENTER", 0, off)
end

-------------------------------------------------------------------------------
--  Claiming a Blizzard bubble
-------------------------------------------------------------------------------

local function OnBlizzHide(outer)
    ReleaseBlizz(outer)
end

-- Assigned further down, next to the matching it needs. Declared here so that definition
-- binds this local instead of creating a global.
local HookOuter

local function Claim(outer, child, fs, text)
    local cfg = Cfg()
    if not cfg then return end

    local f = Acquire()
    f.outer = outer
    ours[outer] = f
    blanked[outer] = nil
    -- Taken now, while the bubble is still untouched, and kept for the life of the claim so
    -- RefreshStyle can switch between the two colours without the bubble being rebuilt.
    f.blizzR, f.blizzG, f.blizzB = BlizzTextColor(fs)
    f.text:SetText(text)
    -- Shown at alpha 0 BEFORE Layout, never after: font geometry on a HIDDEN frame is wrong
    -- (the shared tooltip measures the same way for the same reason), and a wrapped line
    -- would land in a frame sized for one.
    f:SetAlpha(0)
    f:Show()
    Layout(f, cfg)
    Anchor(f, cfg)
    f:SetAlpha(1)

    SetBlizzAlpha(child, 0)
end

local Sweep

-- Zero is not "now": C_Timer.After(0) runs at the start of the next frame, which is the
-- earliest anything in Lua can react to a frame the engine built after we last looked.
local function ScheduleSweep()
    if sweepScheduled then return end
    local delay = SWEEP_STEP
    for i = 1, #pending do
        if pending[i].tries <= SWEEP_FAST_TRIES then delay = 0 break end
    end
    sweepScheduled = true
    C_Timer.After(delay, Sweep)
end

-- A bubble already standing when a line arrived cannot be the bubble that line produced, so
-- the stamps decide. The gate rests on Blizzard hiding a frame before reusing it, which is
-- what re-stamps it through our OnHide/OnShow pair. That is engine behaviour Lua cannot
-- prove, so a line on its LAST try drops the gate: degrading to the old text-only match
-- beats leaving a bubble unstyled if the assumption ever stops holding.
local function Ordered(e, at)
    return e.stamp < at or e.tries >= SWEEP_TRIES - 1
end

-- Which pending line, if any, this bubble is showing. Exact match first: containment is the
-- fallback for the formats Blizzard fills in itself, and on its own it would let a short line
-- claim the bubble of a longer one that quotes it.
local function MatchPending(text, at)
    if text == nil then return nil end
    for i = 1, #pending do
        if Ordered(pending[i], at) and SafeEq(text, pending[i].text) then return i end
    end
    for i = 1, #pending do
        if Ordered(pending[i], at) and SafeContains(text, pending[i].text) then return i end
    end
    return nil
end

-- The engine shows the bubble before we can possibly know about it, so waiting for the sweep
-- means Blizzard's balloon is visible for a sweep step every time. This closes that window:
-- the text is usually already set, so the bubble is claimed in the same frame it appears. If
-- it is not readable yet, we blank it on sight while a line of ours is waiting, and the sweep
-- below then either claims it or hands the chrome straight back.
local function OnBlizzShow(outer)
    if not active or suspended then return end
    -- Stamped before every early return below: a bubble that appears while nothing is pending
    -- is exactly the one a later identical line must not be allowed to claim.
    seenTick = seenTick + 1
    seenAt[outer] = seenTick
    if #pending == 0 or ours[outer] or blanked[outer] then return end

    local child, fs = BlizzParts(outer)
    if not child then return end

    local text = BlizzText(fs)
    if text ~= nil then
        -- A secret string can be shown but never compared, so it can never be matched to its
        -- chat line. Leaving it to Blizzard beats blanking a bubble we cannot replace.
        if not IsSecret(text) then
            local idx = MatchPending(text, seenAt[outer])
            if idx then
                table.remove(pending, idx)
                -- Blizzard's own text, not the chat event's: the client has already formatted
                -- it (an emote carries the speaker's name, a monster emote its filled token),
                -- and it is the string the bubble we are covering actually shows.
                Claim(outer, child, fs, text)
            end
        end
        return
    end

    SetBlizzAlpha(child, 0)
    blanked[outer] = 0
    ScheduleSweep()
end

-- One hook pair per frame for the life of the session. Blizzard recycles a small set of
-- frames, so the marker keeps a recycled one from stacking duplicates, and the set converges
-- after a handful of messages. This is what keeps the feature free of per-frame work: the
-- engine tells us when a bubble starts and ends instead of us watching for it.
function HookOuter(outer)
    if hooked[outer] then return end
    hooked[outer] = true
    outer:HookScript("OnShow", OnBlizzShow)
    outer:HookScript("OnHide", OnBlizzHide)
end

-- direct is set only by the chat handler running a pass ahead of the timer. Any timer already
-- armed stays armed in that case, so an early pass cannot fork the schedule into two chains.
function Sweep(direct)
    if not direct then sweepScheduled = false end
    if suspended or not active then
        RestoreBlanked()
        return
    end
    if not C_ChatBubbles or not C_ChatBubbles.GetAllChatBubbles then
        wipe(pending)
        RestoreBlanked()
        return
    end

    if #pending > 0 then
        -- Without includeForbidden on purpose: a forbidden bubble cannot be read or blanked,
        -- and taking it out of the list here is cheaper than guarding every access below.
        local ok, list = pcall(C_ChatBubbles.GetAllChatBubbles)
        if ok and type(list) == "table" then
            for i = 1, #list do
                local outer = list[i]
                if outer and not ours[outer] then
                    -- Hooked on first sighting, not only when claimed: a frame we hook now is
                    -- one that cannot flash the next time the engine reuses it.
                    HookOuter(outer)
                    local at = seenAt[outer]
                    if not at then
                        -- Reaching a frame here with no stamp means the engine built and
                        -- showed it before our OnShow hook existed on it, so it is newer than
                        -- every line currently waiting. SetActive stamps the frames that were
                        -- already up, so those can never land in this branch.
                        seenTick = seenTick + 1
                        at = seenTick
                        seenAt[outer] = at
                    end
                    local child, fs = BlizzParts(outer)
                    local text = BlizzText(fs)
                    if text ~= nil and not IsSecret(text) then
                        local idx = MatchPending(text, at)
                        if idx then
                            table.remove(pending, idx)
                            Claim(outer, child, fs, text)
                        end
                    end
                end
            end
        end

        for i = #pending, 1, -1 do
            pending[i].tries = pending[i].tries + 1
            if pending[i].tries >= SWEEP_TRIES then table.remove(pending, i) end
        end
    end

    -- Same budget as a pending line: a bubble blanked on sight that never matched one of ours
    -- belongs to a channel we do not draw, and gets its own chrome back.
    for outer, tries in pairs(blanked) do
        tries = tries + 1
        if tries >= SWEEP_TRIES then
            blanked[outer] = nil
            local child = BlizzParts(outer)
            SetBlizzAlpha(child, 1)
        else
            blanked[outer] = tries
        end
    end

    if #pending > 0 or next(blanked) then ScheduleSweep() end
end

-------------------------------------------------------------------------------
--  Blizzard's CVars
-------------------------------------------------------------------------------

local cvarPending = false

-- Everything that is not the open world, rather than a whitelist of instance types: a type
-- Blizzard adds later falls through to "stay out" instead of "draw".
local function InInstance()
    local inInst, iType = IsInInstance()
    if not inInst then return false end
    return iType ~= "none"
end

-- The player's pre-takeover values, and which CVars we are holding at ours. Both live HERE
-- and nowhere saved: not in the profile, which a switch or a reset wipes, and not in
-- EllesmereUIDB either, whose every top-level key rides along in a full-account export and is
-- written back wholesale on import (EllesmereUI_Profiles.lua). Carried that way they would
-- hand one player's CVar values to another, including to someone who never switched this on.
-- Nothing is lost by keeping them in memory: PLAYER_LOGOUT restores and clears them before
-- SavedVariables are ever written, so a record never legitimately outlives its session.
local savedCVars, heldCVars

local function SavedCVars()
    if savedCVars then return savedCVars end
    savedCVars = {}
    for _, name in ipairs(BLIZZ_CVARS) do savedCVars[name] = C_CVar.GetCVar(name) end
    return savedCVars
end

-- Without the held set, "the player set this themselves" cannot be told apart from "we set
-- it", and every pass would re-pin channels we do not draw to a stale snapshot, silently
-- undoing the player's own change in Blizzard's options.
local function HeldCVars()
    if not heldCVars then heldCVars = {} end
    return heldCVars
end

-- Drop both records. Called wherever we are certain nothing is held any more.
local function ForgetCVars()
    savedCVars, heldCVars = nil, nil
end

-- Hand back every CVar we are currently holding, and drop the claim on it.
local function RestoreCVars()
    local saved, held = savedCVars, heldCVars
    if not saved or not held then return end
    for _, name in ipairs(BLIZZ_CVARS) do
        if held[name] then
            held[name] = nil
            local prev = saved[name]
            if prev and C_CVar.GetCVar(name) ~= prev then C_CVar.SetCVar(name, prev) end
        end
    end
end

-- want means "we need this channel's bubbles ON", because ours ride on them.
local function ApplyCVar(name, want, saved, held)
    local cur = C_CVar.GetCVar(name)
    if want then
        -- Snapshot at the moment we take the CVar over, not once per install: while we were
        -- leaving this channel alone the player may well have changed it themselves, and that
        -- is the value they must get back.
        if not held[name] then
            saved[name] = cur
            held[name] = true
        end
        if cur ~= "1" then C_CVar.SetCVar(name, "1") end
    elseif held[name] then
        held[name] = nil
        local prev = saved[name]
        if prev and cur ~= prev then C_CVar.SetCVar(name, prev) end
    end
    -- No third branch on purpose: a CVar we never took over is never written.
end

local function AssertCVars()
    local cfg = Cfg()
    if not cfg then return end

    local inInst = InInstance()
    -- Absolute, not an opt-in. Measured in a dungeon on 12.1: GetAllChatBubbles() lists none
    -- while GetAllChatBubbles(true) lists one, so the engine draws a bubble that is forbidden
    -- to us, and a forbidden frame can be neither read nor blanked. Blizzard's own bubbles
    -- keep working there, which is strictly better than the silence the previous design
    -- produced.
    suspended = cfg.enabled == true and inInst

    if InCombatLockdown() then
        local held = heldCVars
        -- Off and holding nothing: no CVar is owed to anyone, so a pass that lands here in
        -- combat has nothing to defer. Without this a profile swap in combat would build the
        -- event frame and arm two events for a player who never switched the feature on.
        if cfg.enabled ~= true and not (held and next(held)) then
            cvarPending = false
            return
        end
        -- Deferred rather than only handled in SetActive: switching things off in combat still
        -- owes the player their CVars back once the fight ends.
        cvarPending = true
        EnsureFrame():RegisterEvent("PLAYER_REGEN_ENABLED")
        eventFrame:RegisterEvent("PLAYER_LOGOUT")
        return
    end
    cvarPending = false

    if cfg.enabled ~= true then
        RestoreCVars()
        ForgetCVars()
        return
    end

    local saved = SavedCVars()
    local held = HeldCVars()
    -- From here on this pass can take a CVar over, so the hand-back has to be armed.
    EnsureFrame():RegisterEvent("PLAYER_LOGOUT")

    if inInst then
        -- We draw nothing inside, so holding their switches on would put Blizzard's bubbles
        -- in front of a player who had them off. Hand them back for the stay; the
        -- PLAYER_ENTERING_WORLD on the way out takes them again.
        RestoreCVars()
        return
    end

    for _, name in ipairs(BLIZZ_CVARS) do
        local want
        if name == "chatBubblesParty" then
            want = (cfg.party == true)
        elseif name == "chatBubblesRaid" then
            want = (cfg.raid == true)
        else
            -- Blizzard's say/yell/emote/NPC switch: one ticked channel is enough to need it,
            -- and with none of them left we would be holding it on to draw over nothing.
            -- Independent of party and raid, which have switches of their own.
            want = (cfg.say == true or cfg.yell == true or cfg.npc == true or cfg.emote == true)
        end
        ApplyCVar(name, want, saved, held)
    end
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------

local function OnEvent(_, event, ...)
    if event == "PLAYER_LOGOUT" then
        -- The only hand-back that survives the addon being DISABLED or uninstalled: with
        -- nothing left in game to run AssertCVars, a CVar we forced would keep our value for
        -- good. Both records go with it, so the next login snapshots the player's live values
        -- fresh instead of reading our own value back as theirs.
        RestoreCVars()
        ForgetCVars()
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        if cvarPending then AssertCVars() end
        -- Only kept while the feature runs; a deferred restore leaves nothing behind.
        if not cvarPending and not active and eventFrame then
            eventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
            eventFrame:UnregisterEvent("PLAYER_LOGOUT")
        end
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        AssertCVars()
        if suspended then
            wipe(pending)
            ReleaseAll()
        end
        return
    end

    local channel = EVENT_CHANNEL[event]
    if not channel then return end
    if suspended then return end

    local cfg = Cfg()
    if not cfg or cfg[channel] ~= true then return end

    local text = ...
    if text == nil or IsSecret(text) then return end

    -- The stamp is read, not advanced: only a bubble APPEARING moves the counter, so every
    -- bubble that shows up from here on compares as newer than this line.
    pending[#pending + 1] = { text = text, tries = 0, stamp = seenTick }
    -- Swept right here, not a timer later: if the engine already built the bubble before it
    -- dispatched this event, we claim it in the same frame and nothing of Blizzard's is ever
    -- drawn, not even on the very first message of a session, where no frame of theirs exists
    -- yet for our OnShow hook to sit on. A miss costs one walk of a list with a handful of
    -- entries, and the sweep then continues on its timer as before.
    Sweep(true)
end

local CHAT_EVENTS = {}
for event in pairs(EVENT_CHANNEL) do
    CHAT_EVENTS[#CHAT_EVENTS + 1] = event
end
table.sort(CHAT_EVENTS)   -- pairs order is not stable; the diff below reads better in one

local registeredChat = {}   -- event -> true while registered

-- Only the events whose channel is actually switched on, so a channel nobody enabled costs no
-- OnEvent dispatch at all. Diffed rather than re-registered wholesale, so a settings pass that
-- changes nothing touches no events.
local function SyncChatEvents(cfg)
    for i = 1, #CHAT_EVENTS do
        local event = CHAT_EVENTS[i]
        local want = cfg ~= nil and cfg[EVENT_CHANNEL[event]] == true
        if want ~= (registeredChat[event] == true) then
            if want then
                eventFrame:RegisterEvent(event)
                registeredChat[event] = true
            else
                eventFrame:UnregisterEvent(event)
                registeredChat[event] = nil
            end
        end
    end
end

function EnsureFrame()
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", OnEvent)
    end
    return eventFrame
end

local function SetActive(on)
    if not on then
        -- Before EnsureFrame, not after: there is nothing to tear down, and a player who never
        -- switched this on must not pay for an event frame either.
        if not active then return end
        active = false
        eventFrame:UnregisterAllEvents()
        wipe(registeredChat)
        wipe(pending)
        ReleaseAll()
        return
    end

    EnsureFrame()
    local firstPass = not active
    active = true

    if firstPass then
        eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        eventFrame:RegisterEvent("PLAYER_LOGOUT")

        -- Seed the hook set over the frames that already exist. Only a frame we have never
        -- seen can still flash, so hooking Blizzard's pool up front rather than one frame per
        -- message makes the very first lines after switching on behave like the rest.
        if C_ChatBubbles and C_ChatBubbles.GetAllChatBubbles then
            local ok, list = pcall(C_ChatBubbles.GetAllChatBubbles)
            if ok and type(list) == "table" then
                for i = 1, #list do
                    local outer = list[i]
                    if outer then
                        HookOuter(outer)
                        -- Stamped as already standing, so a line typed after switching on
                        -- cannot claim a bubble that was on screen before it.
                        if not seenAt[outer] then
                            seenTick = seenTick + 1
                            seenAt[outer] = seenTick
                        end
                    end
                end
            end
        end
    end

    -- Every pass, not just the first. A channel toggled while the feature is already running
    -- has to move the registration set.
    SyncChatEvents(Cfg())
end

-------------------------------------------------------------------------------
--  Public entry points
-------------------------------------------------------------------------------

-- Appearance only: re-style and re-anchor what is already on screen, touching neither the
-- event registrations nor Blizzard's CVars. The options page runs this per slider STEP while
-- a slider is being dragged, where the full pass below would re-diff the event registrations
-- and round-trip Blizzard's switches for a change that can only move pixels.
function CB.RefreshStyle()
    if not active or suspended then return end
    local cfg = Cfg()
    if not cfg then return end
    for _, f in pairs(ours) do
        Layout(f, cfg)
        Anchor(f, cfg)
    end
end

-- Group chat rides switches that stay the player's own call, so the first pass that finds the
-- feature enabled takes those two ticks from the switches rather than from a shipped default:
-- switching this on must not put party or raid bubbles in front of someone who had them off.
-- The other four are not seeded, because their switch is one we hold on regardless. Once
-- seeded we never look again: picks made in our own dropdown are the player's, and an off/on
-- cycle of the feature must not overwrite them.
local function SeedChannels(cfg)
    if not cfg or cfg.seeded == true then return end
    cfg.seeded = true
    cfg.party = C_CVar.GetCVar("chatBubblesParty") == "1"
    cfg.raid  = C_CVar.GetCVar("chatBubblesRaid") == "1"
end

-- The structural pass: anything that can change WHETHER we draw, or which of Blizzard's
-- switches we hold. Called from the options page for those settings, and once at login.
function CB.Refresh()
    local on = Enabled()
    -- Ahead of both calls below: SetActive registers events off these very values, and
    -- AssertCVars is the first thing that could overwrite a switch we are about to read.
    if on then SeedChannels(Cfg()) end
    SetActive(on)
    AssertCVars()
    if not on then return end
    if suspended then
        wipe(pending)
        ReleaseAll()
        return
    end
    CB.RefreshStyle()
end
