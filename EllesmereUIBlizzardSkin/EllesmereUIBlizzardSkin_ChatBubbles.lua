if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
local _, ns = ...
local EUI = _G.EllesmereUI
if not EUI then return end

local PP = EUI.PP

-- Chat Bubbles (chatBubbles.enabled, default off), configured on the Blizz UI Enhanced
-- options page. Settings live per profile on the profile root (profile.chatBubbles).
-- Blizzard's bubbles are not forbidden outside instances, so rather than replace them we ride
-- on them: their switches stay ON, we blank the chrome and hang a styled frame on the frame
-- carrying their position, which the engine has already put over the speaker's head. No
-- nameplate is involved and the player's own lines work too. Inside instances they ARE
-- forbidden: we stay away and hand the switches back, as PLAYER_LOGOUT does for any we still
-- hold, so disabling the addon cannot strand one. What we draw is the bubble's OWN text, so
-- whatever the client formatted into it carries over. Nothing runs while off.

local C_CVar, C_Timer = C_CVar, C_Timer
local InCombatLockdown, IsInInstance, GetTime = InCombatLockdown, IsInInstance, GetTime

local MIN_WIDTH = 40
local WHITE = "Interface\\Buttons\\WHITE8X8"
-- Recent chat lines, kept to tell which channel and speaker a bubble belongs to. Count-capped
-- rather than timed, so a bubble the engine only shows once its speaker comes on screen still
-- finds its line.
local RECENT_MAX = 16
-- Next-frame passes after a line arrives, for a bubble built on a frame not hooked yet.
local RETRY_TRIES = 2

-- Blizzard's three bubble switches. chatBubbles is taken over as soon as any of say, yell,
-- emotes or NPC lines is ticked, since that is what the feature exists to restyle and there
-- is nothing to ride on without it; clear all four and it goes back, because there is then
-- nothing left for it to draw. The party and raid switches stay the player's own call, taken
-- over only while the matching channel is ticked, and SeedChannels seeds those two ticks from
-- the switches themselves. All three are handed back the way they were found.
local BLIZZ_CVARS = { "chatBubbles", "chatBubblesParty", "chatBubblesRaid" }

-- Chat event -> the setting key that decides whether we draw it. Guild is absent on purpose:
-- Blizzard draws no bubble for guild chat, so there is no frame to ride and no position to
-- borrow. Instance chat sits with party: an instance group is party-shaped and
-- chatBubblesParty is the switch Blizzard ships on. A line whose bubble never appears
-- expires on its own.
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
EUI.ChatBubbles = CB

-- Off by default: switching it on also switches Blizzard's own bubbles ON for the channels
-- enabled below, so it is opt-in.
local DEFAULTS = {
    enabled = false,
    -- No guild key: Blizzard draws no bubble for guild chat, so there is nothing to ride on.
    -- party and raid are overwritten from Blizzard's live switches the first time the feature
    -- is enabled (SeedChannels), so group bubbles are never put in front of a player who had
    -- them off.
    say = true, yell = true, party = true, raid = false, npc = true, emote = true,
    -- Our own bubbles never draw inside an instance, so this decides whether Blizzard's are
    -- visible there.
    hideInInstances = false,
    padding = 8,
    maxWidth = 260,
    -- Nudge away from where Blizzard put the bubble we ride on.
    offsetY = 0,
    background = true,
    bgColor = { r = 0, g = 0, b = 0 },
    bgAlpha = 0.5,
    borderSize = 1,
    borderColor = { r = 0, g = 0, b = 0, a = 1 },
    -- Key into the shared font registry; "__global" follows the EUI global font.
    font = "__global",
    fontSize = 12,
    -- "__global" follows the EUI global outline mode; "none" is the drop shadow.
    outline = "__global",
    -- Channel -> true: speaker name in the bubble's top right corner for that channel.
    showName = {},
    nameAnchor = "TOPRIGHT",
    nameFontSize = 10,
    nameOffsetX = 0,
    nameOffsetY = 0,
    textColor = { r = 1, g = 1, b = 1 },
    -- On, the bubble takes the per-channel colour the engine already gave it.
    followBlizzardColor = false,
}

-- Read only. The single answer to "what is this setting worth when it is missing", shared
-- with the options page.
function CB.Defaults() return DEFAULTS end

-- Fills keys missing from a stored table (older or migrated data) without touching set ones.
-- Once per table: Cfg() runs per chat line.
local filled = setmetatable({}, { __mode = "k" })
local function FillDefaults(t)
    if filled[t] then return t end
    filled[t] = true
    for k, v in pairs(DEFAULTS) do
        if t[k] == nil then
            t[k] = type(v) == "table" and EUI.Lite.DeepCopy(v) or v
        end
    end
    return t
end

-- The active profile's settings. create=false answers nil for a profile that never touched
-- the feature, so a player who never opens the page stores nothing.
function CB.DB(create)
    local prof = EUI.GetActiveProfileData()
    if not prof then return nil end
    local t = prof.chatBubbles
    if type(t) ~= "table" then
        if not create then return nil end
        t = {}
        prof.chatBubbles = t
    end
    return FillDefaults(t)
end

local active = false          -- events registered and CVars asserted
local suspended = false       -- inside an instance, where we never draw
local ours = {}               -- Blizzard bubble frame -> our frame, while both are shown
-- Side tables keyed by Blizzard's frame, never fields written onto it: every other access to
-- these frames is guarded because one can be reclassified as forbidden under us, and writing
-- a marker onto a forbidden frame raises. Weak keys, the house pattern for this, so nothing
-- of ours keeps an engine frame alive.
local WEAK_KEYS = { __mode = "k" }
local hooked = setmetatable({}, WEAK_KEYS)   -- frame -> true, hooks are for the session
local childOf = setmetatable({}, WEAK_KEYS)  -- frame -> its templated child
-- One frame of ours per engine frame, built on first claim and kept. Blizzard recycles a
-- small set, so this is bounded by their pool.
local overlay = setmetatable({}, WEAK_KEYS)
-- frame -> the line it last drew, so the same bubble is redrawn when it comes back on screen
local bound = setmetatable({}, WEAK_KEYS)
local recent = {}             -- chat lines not matched to a bubble yet, oldest first
-- frame -> GetTime() of its last appearance. Frame time, constant within a frame, so a bubble
-- the engine built in the same frame as its chat event still counts as after the line.
local shownAt = setmetatable({}, WEAK_KEYS)
local eventFrame
local EnsureFrame
local retryLeft = 0

-- DEFAULTS (enabled = false) for a profile without settings, so a switch to it still hands
-- back any CVars we hold. Read only.
local function Cfg()
    return CB.DB(false) or DEFAULTS
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

-- Either side can be a secret string in restricted content, and comparing one raises. That is
-- exactly why the existence test is type() and not "== nil": comparing a secret to nil is the
-- operation our own secret rules forbid (EllesmereUIChat.lua's OnEditBoxPreSendText carries
-- the same note), so a nil belt in front of the guard would itself be the hazard. type()
-- reports a secret's underlying type, so a secret string still reaches the guarded compare.
local function SafeEq(a, b)
    if type(a) ~= "string" or type(b) ~= "string" then return false end
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
    -- type() rather than "== nil", for the reason spelled out over SafeEq.
    if type(hay) ~= "string" or type(needle) ~= "string" then return false end
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
local _partsOuter, _partsChild, _partsFS

-- Both lookups sit INSIDE the guarded call, not just the call itself: reading outer.GetChildren
-- and reading child.String are each an index into a Blizzard frame, and indexing one that has
-- been reclassified as forbidden raises right there, before a pcall wrapped around the call
-- alone could catch it. The child lookup runs on every BlizzParts call, not only on the first.
local function RawResolveParts()
    if not _partsChild then
        -- Resolved once: GetChildren hands back every child as varargs and allocates on every
        -- call, and this runs per bubble on every show and hide.
        _partsChild = _partsOuter:GetChildren()
    end
    if _partsChild then _partsFS = _partsChild.String end
end

local function BlizzParts(outer)
    if not outer then return nil, nil end
    _partsOuter, _partsChild, _partsFS = outer, childOf[outer], nil
    local ok = pcall(RawResolveParts)
    local child, fs = _partsChild, _partsFS
    _partsOuter, _partsChild, _partsFS = nil, nil, nil
    if not ok or not child then return nil, nil end
    -- Cached only once the pair actually resolved, so a frame that raised is retried rather
    -- than remembered as broken.
    childOf[outer] = child
    return child, fs
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
    if not ok then return nil end
    -- type() before IsSecret, and neither of them after a "== nil": comparing a secret to nil
    -- raises, so the missing-value test has to be the one that cannot. Same ordering rule as
    -- SafeEq above and as EllesmereUIActionBars' charge count.
    if type(_colorR) ~= "number" or type(_colorG) ~= "number" or type(_colorB) ~= "number" then
        return nil
    end
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

    f.name = f:CreateFontString(nil, "ARTWORK")
    f.name:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    f.name:SetJustifyH("RIGHT")
    f.name:SetWordWrap(false)
    f.name:Hide()

    return f
end

-- Hides ours and hands the chrome back, so the next speaker on this recycled frame, whose
-- channel we may not draw, gets Blizzard's balloon. The binding stays for a re-show.
local function ReleaseBlizz(outer)
    local f = ours[outer]
    if not f then return end
    ours[outer] = nil
    f:ClearAllPoints()
    f:Hide()
    local child = BlizzParts(outer)
    SetBlizzAlpha(child, 1)
end

local function ReleaseAll()
    for outer in pairs(ours) do
        ReleaseBlizz(outer)
    end
end

-- Appearance and geometry in ONE pass, never separately: font size, padding and max width all
-- feed the measurement, so restyling a live bubble without re-measuring leaves its text
-- clipped inside a frame still sized for the old settings.
local function Layout(f, cfg)
    -- One place decides what a missing setting is worth.
    local d = DEFAULTS

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

    local fontKey = cfg.font or d.font
    local path = fontKey ~= "__global" and EUI.ResolveFontName(fontKey)
    path = path or EUI.GetFontPath() or "Fonts\\FRIZQT__.TTF"
    local outline = cfg.outline or d.outline
    local flag
    if outline == "__global" then
        flag = EUI.GetFontOutlineFlag() or ""
    else
        flag = EUI.OutlineFlagForMode(outline)
    end
    local fontSize = cfg.fontSize or d.fontSize or 12
    -- No outline means the drop shadow, which only renders when primed before SetFont.
    EUI.PrimeFontShadow(f.text, flag == "")
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

    -- Name row: reserves its height on the anchored edge so the two never overlap; the
    -- offsets then move the name freely from there.
    local nameW, nameH = 0, 0
    local names = cfg.showName
    if f.speaker and type(names) == "table" and names[f.channel] == true then
        local nameSize = cfg.nameFontSize or d.nameFontSize
        EUI.PrimeFontShadow(f.name, flag == "")
        if not f.name:SetFont(path, nameSize, flag) then
            f.name:SetFont("Fonts\\FRIZQT__.TTF", nameSize, flag)
        end
        f.name:SetTextColor(tr, tg, tb, 0.8)
        f.name:SetText(f.speaker)
        nameW = PP.Scale(f.name:GetUnboundedStringWidth()) + PP.mult
        nameH = nameSize + 2
        f.name:Show()
    else
        f.name:Hide()
    end

    -- Config numbers that end up as frame geometry go through the pixel grid. maxWidth is a
    -- real width (it clamps the FontString), so it is snapped before the measurement.
    local padding = cfg.padding or d.padding or 0
    local maxWidth = PP.Scale(cfg.maxWidth or d.maxWidth or 260)

    -- Three lines, not one: a secret string cannot be measured, and a single-line fallback
    -- cuts a wrapped sentence off. MeasureText leaves the FontString at the width it measured
    -- against, so the frame only has to wrap padding around the result.
    local w, h = MeasureText(f.text, maxWidth, fontSize * 1.4 * 3)
    if nameW > maxWidth then nameW = maxWidth end
    if nameW > w then w = nameW end
    local anchor = cfg.nameAnchor or d.nameAnchor
    local bottom = anchor:find("BOTTOM") ~= nil
    local nx = anchor:find("LEFT") and padding or (anchor:find("RIGHT") and -padding or 0)
    local ny = bottom and padding or -padding
    f.name:SetWidth(nameW)
    f.name:SetJustifyH(anchor:find("LEFT") and "LEFT" or (anchor:find("RIGHT") and "RIGHT" or "CENTER"))
    f.name:ClearAllPoints()
    PP.Point(f.name, anchor, f, anchor,
        nx + (cfg.nameOffsetX or 0), ny + (cfg.nameOffsetY or 0))
    f.text:ClearAllPoints()
    f.text:SetPoint("CENTER", f, "CENTER", 0, bottom and nameH / 2 or -nameH / 2)
    PP.Size(f, w + padding * 2, h + nameH + padding * 2)
end

local _anchorFrame, _anchorTo, _anchorOff

-- Concentric with Blizzard's balloon, not stacked above it: theirs is already where the speaker
-- is, and the two grow to different sizes around the same text. Anchored to the child that
-- draws the balloon, not the outer frame: after a bubble goes off screen and back, the outer
-- can sit away from the balloon. offsetY is the only nudge the user gets, and it rides in on
-- PP.Point so it lands on the pixel grid.
--
-- Guarded, because PP.Point ends in a plain SetPoint and anchoring to a frame that has been
-- reclassified as forbidden raises there, not inside PP. The claim proved the frame readable
-- at the time, but RefreshStyle re-anchors whatever is still in "ours" per slider STEP,
-- arbitrarily long afterwards.
local function RawAnchor()
    PP.Point(_anchorFrame, "CENTER", _anchorTo, "CENTER", 0, _anchorOff)
end

-- Answers whether the frame ended up anchored. A false here is not cosmetic: ClearAllPoints has
-- already run, so a caller that carried on would leave a shown frame with no point at all and,
-- in Claim's case, blank Blizzard's chrome behind it. Both callers hand the bubble back instead.
local function Anchor(f, cfg)
    local d = DEFAULTS
    local off = cfg.offsetY or d.offsetY or 0
    f:ClearAllPoints()
    _anchorFrame, _anchorTo, _anchorOff = f, childOf[f.outer] or f.outer, off
    local ok = pcall(RawAnchor)
    _anchorFrame, _anchorTo = nil, nil
    return ok
end

-------------------------------------------------------------------------------
--  Claiming a Blizzard bubble
-------------------------------------------------------------------------------

local function OnBlizzHide(outer)
    ReleaseBlizz(outer)
end

-- Newest first: an older unmatched line with the same text is the stale one. Exact match
-- before containment, which is the fallback for formats Blizzard fills in itself. A bubble
-- already standing when a line arrived cannot be the bubble that line produced.
local function MatchRecent(text, at)
    for i = #recent, 1, -1 do
        if recent[i].at <= at and SafeEq(text, recent[i].text) then return i end
    end
    for i = #recent, 1, -1 do
        if recent[i].at <= at and SafeContains(text, recent[i].text) then return i end
    end
    return nil
end

local function Draw(outer, child, fs, text, line)
    local cfg = Cfg()
    if not cfg then return end

    local f = overlay[outer]
    if not f then
        f = NewBubble()
        overlay[outer] = f
    end
    f.outer = outer
    ours[outer] = f
    f.blizzR, f.blizzG, f.blizzB = BlizzTextColor(fs)
    f.speaker, f.channel = line.speaker, line.channel
    f.text:SetText(text)
    -- Shown at alpha 0 BEFORE Layout, never after: font geometry on a HIDDEN frame is wrong
    -- (the shared tooltip measures the same way for the same reason), and a wrapped line
    -- would land in a frame sized for one.
    f:SetAlpha(0)
    f:Show()
    Layout(f, cfg)
    -- Before the chrome is blanked: a claim that cannot anchor leaves Blizzard's bubble drawing.
    if not Anchor(f, cfg) then
        ReleaseBlizz(outer)
        return
    end
    f:SetAlpha(1)

    SetBlizzAlpha(child, 0)
end

-- Draws this bubble if it shows a line of ours: a recent one, which binds it, or the one it
-- is already bound to, back on screen after going off it. Answers whether it is ours.
local function TryClaim(outer)
    if ours[outer] then return true end
    local child, fs = BlizzParts(outer)
    if not child then return false end
    local text = BlizzText(fs)
    -- type() first, then the secret guard, then the compares. See SafeEq for why the nil
    -- test cannot lead here. A secret string can be shown but never matched.
    if type(text) ~= "string" or IsSecret(text) then return false end
    local cfg = Cfg()
    local idx = MatchRecent(text, shownAt[outer] or 0)
    local line
    if idx then
        line = recent[idx]
        -- A channel switched off since the line arrived.
        if cfg[line.channel] ~= true then return false end
        table.remove(recent, idx)
        -- Blizzard's own text, not the chat event's: the client has already formatted it, and
        -- it is what a re-show of this bubble is compared against.
        line.text = text
        bound[outer] = line
    else
        line = bound[outer]
        if not (line and SafeEq(text, line.text)) or cfg[line.channel] ~= true then return false end
    end
    Draw(outer, child, fs, text, line)
    return true
end

-- One hook pair per frame for the life of the session. Blizzard recycles a small set of
-- frames, so the marker keeps a recycled one from stacking duplicates, and the set converges
-- after a handful of messages. This is what keeps the feature free of per-frame work: the
-- engine tells us when a bubble starts and ends instead of us watching for it.
local _hookTarget
local OnBlizzShow

local function RawHookOuter()
    _hookTarget:HookScript("OnShow", OnBlizzShow)
    _hookTarget:HookScript("OnHide", OnBlizzHide)
end

local function HookOuter(outer)
    if hooked[outer] then return end
    -- Marked BEFORE the guarded call, not after: the pair has to stay one-per-frame, and a
    -- retry that found the first HookScript already installed would stack a second OnShow.
    -- Nothing is lost by giving up on a frame that raised here -- a frame we cannot hook is
    -- one we can neither read nor blank, so it was never claimable in the first place.
    hooked[outer] = true
    _hookTarget = outer
    pcall(RawHookOuter)
    _hookTarget = nil
end

local _shownFrame, _shownOut

local function RawShown()
    _shownOut = _shownFrame:IsShown()
end

-- A listed bubble can be hidden (speaker off screen); ours would float at its stale spot, so
-- that one waits for its OnShow.
local function BlizzShown(outer)
    _shownFrame, _shownOut = outer, false
    local ok = pcall(RawShown)
    _shownFrame = nil
    return ok and _shownOut == true
end

-- Hooks every bubble the engine lists and claims what it can. Without includeForbidden on
-- purpose: a forbidden bubble can be neither read nor blanked.
local function ClaimListed()
    if not C_ChatBubbles or not C_ChatBubbles.GetAllChatBubbles then return end
    local ok, list = pcall(C_ChatBubbles.GetAllChatBubbles)
    if not ok or type(list) ~= "table" then return end
    for i = 1, #list do
        local outer = list[i]
        if outer then
            HookOuter(outer)
            -- First sighting with no stamp: shown before our hook existed on it, so newer
            -- than every line waiting.
            if not shownAt[outer] then shownAt[outer] = GetTime() end
            if #recent > 0 and BlizzShown(outer) then TryClaim(outer) end
        end
    end
end

-- Zero is not "now": C_Timer.After(0) runs at the start of the next frame, which is the
-- earliest anything in Lua can react to a frame the engine built after we last looked.
local function Retry()
    retryLeft = retryLeft - 1
    if not active or suspended or #recent == 0 then
        retryLeft = 0
        return
    end
    ClaimListed()
    if retryLeft > 0 then C_Timer.After(0, Retry) end
end

local function ScheduleRetry()
    if retryLeft > 0 then return end
    retryLeft = RETRY_TRIES
    C_Timer.After(0, Retry)
end

-- The text is usually already set when the engine shows the bubble, so it is claimed in the
-- frame it appears. When it is not readable yet, a next-frame pass reads it again.
function OnBlizzShow(outer)
    if not active or suspended then return end
    -- Stamped before the early return: a bubble shown while nothing waits must not be claimed
    -- by a later identical line.
    shownAt[outer] = GetTime()
    if #recent == 0 and not bound[outer] then return end
    if not TryClaim(outer) and #recent > 0 then ScheduleRetry() end
end

-------------------------------------------------------------------------------
--  Blizzard's CVars
-------------------------------------------------------------------------------

local cvarPending = false
local FlushCVars   -- forward: AssertCVars defers it, and it calls AssertCVars back

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
            if prev and C_CVar.GetCVar(name) ~= prev then EllesmereUI.ReleaseCVar(name, prev, "EllesmereUIBlizzardSkin") end
        end
    end
end

-- target is the value this switch has to sit at while we hold it, or nil for "we do not need
-- it", which hands it back. A value rather than a flag, because hiding bubbles inside an
-- instance means forcing one OFF and not only on.
local function ApplyCVar(name, target, saved, held)
    local cur = C_CVar.GetCVar(name)
    if target then
        -- Snapshot at the moment we take the CVar over, not once per install: while we were
        -- leaving this channel alone the player may well have changed it themselves, and that
        -- is the value they must get back.
        if not held[name] then
            saved[name] = cur
            held[name] = true
        end
        if cur ~= target then EllesmereUI.HoldCVar(name, target, "EllesmereUIBlizzardSkin") end
    elseif held[name] then
        held[name] = nil
        local prev = saved[name]
        if prev and cur ~= prev then EllesmereUI.ReleaseCVar(name, prev, "EllesmereUIBlizzardSkin") end
    end
    -- No third branch on purpose: a CVar we never took over is never written.
end

local function AssertCVars()
    local cfg = Cfg()
    if not cfg then return end

    local inInst = InInstance()
    -- Absolute, not an opt-in. Inside an instance GetAllChatBubbles() lists none while
    -- GetAllChatBubbles(true) lists one: the engine draws a bubble that is forbidden to us,
    -- and a forbidden frame can be neither read nor blanked. Blizzard's own bubbles keep
    -- working there.
    suspended = cfg.enabled == true and inInst

    if InCombatLockdown() then
        local held = heldCVars
        -- Off and holding nothing: no CVar is owed to anyone, so a pass that lands here in
        -- combat has nothing to defer. Without this a profile swap in combat would build the
        -- event frame, arm PLAYER_LOGOUT and queue a CVar pass for a player who never switched
        -- the feature on.
        if cfg.enabled ~= true and not (held and next(held)) then
            cvarPending = false
            return
        end
        -- Deferred rather than only handled in SetActive: switching things off in combat still
        -- owes the player their CVars back once the fight ends.
        cvarPending = true
        ns.CombatQueue.Defer("BubbleCVars", FlushCVars)
        EnsureFrame():RegisterEvent("PLAYER_LOGOUT")
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
        if cfg.hideInInstances == true then
            -- Ours cannot draw here at all, so Blizzard's are the only bubbles an instance
            -- has, and hiding them means holding all three switches at zero for the stay.
            -- The snapshot each one was taken over on is untouched, so the loop below hands
            -- them back off it on the way out.
            for _, name in ipairs(BLIZZ_CVARS) do
                ApplyCVar(name, "0", saved, held)
            end
            return
        end
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
        ApplyCVar(name, want and "1" or nil, saved, held)
    end
end

-- Runs once on the regen edge after a pass that landed in combat.
function FlushCVars()
    if cvarPending then AssertCVars() end
    -- Only kept while the feature runs; a deferred restore leaves nothing behind.
    if not cvarPending and not active and eventFrame then
        eventFrame:UnregisterEvent("PLAYER_LOGOUT")
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
        -- The CVars are only half of what we hold: every claimed bubble also has Blizzard's
        -- own chrome sitting at alpha 0 under ours. Handing that back costs one pass over a
        -- handful of frames and makes the logout branch symmetric with SetActive(false), so
        -- an engine bubble frame that outlives the reload cannot come back invisible for the
        -- next speaker.
        ReleaseAll()
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        AssertCVars()
        if suspended then
            wipe(recent)
            ReleaseAll()
        end
        return
    end

    local channel = EVENT_CHANNEL[event]
    if not channel then return end
    if suspended then return end

    local cfg = Cfg()
    if not cfg or cfg[channel] ~= true then return end

    local text, sender = ...
    -- Every one of the fourteen events above is declared SecretInChatMessagingLockdown in
    -- Blizzard's own ChatInfoDocumentation, and their "text" payload carries no NeverSecret,
    -- so arg1 IS a secret string whenever that lockdown is in effect -- which is a state of
    -- the chat system, not a property of the map, so it can reach us out here in the open
    -- world where "suspended" is false. type() first for that reason, then the secret guard;
    -- a "== nil" belt in front of either would raise on exactly the lines it is meant to
    -- protect. See SafeEq.
    if type(text) ~= "string" or IsSecret(text) then return end

    -- Sender shares the lockdown; a secret one is dropped, never compared or shown.
    local speaker
    if type(sender) == "string" and not IsSecret(sender) and sender ~= "" then
        speaker = Ambiguate(sender, "short")
    end
    if #recent >= RECENT_MAX then table.remove(recent, 1) end
    local line = { text = text, speaker = speaker, channel = channel, at = GetTime() }
    recent[#recent + 1] = line
    -- Claimed right here when the engine built the bubble before dispatching this event,
    -- including the first message of a session, before any frame of theirs is hooked.
    ClaimListed()
    -- Still unmatched: the bubble may land a frame later, or only once its speaker is on
    -- screen, where the OnShow hook finds the line.
    if recent[#recent] == line then ScheduleRetry() end
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
        wipe(recent)
        wipe(bound)
        ReleaseAll()
        return
    end

    EnsureFrame()
    local firstPass = not active
    active = true

    if firstPass then
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
                        -- Already standing, so a line typed after switching on cannot claim it.
                        shownAt[outer] = GetTime()
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
-- Options preview: one of our own frames, styled by the same Layout as a live bubble.
local preview, previewOnResize

local function UpdatePreview(force)
    if not preview or not (force or preview:IsVisible()) then return end
    local cfg = Cfg()
    local names = cfg.showName
    preview.channel = "say"
    preview.speaker = (type(names) == "table" and next(names)) and UnitName("player") or nil
    if preview.speaker then preview.channel = next(names) end
    Layout(preview, cfg)
    if previewOnResize then previewOnResize(preview:GetHeight()) end
end

-- Built lazily the first time the options page asks. onResize gets the bubble height.
function CB.ShowPreview(parent, onResize)
    if not preview then
        preview = NewBubble()
        preview.text:SetText("The quick brown fox jumps over the lazy dog.")
    end
    preview:SetParent(parent)
    preview:SetFrameStrata(parent:GetFrameStrata())
    preview:SetFrameLevel(parent:GetFrameLevel() + 5)
    preview:ClearAllPoints()
    preview:SetPoint("CENTER", parent, "CENTER", 0, 0)
    preview:Show()
    previewOnResize = nil
    UpdatePreview(true)
    previewOnResize = onResize
    return preview
end

function CB.RefreshStyle()
    UpdatePreview()
    if not active or suspended then return end
    local cfg = Cfg()
    if not cfg then return end
    for _, f in pairs(ours) do
        Layout(f, cfg)
        -- Same hand-back as in Draw. Clearing the key of the entry we are standing on is
        -- allowed during a pairs traversal, which is what ReleaseAll has always relied on.
        if not Anchor(f, cfg) then ReleaseBlizz(f.outer) end
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
    UpdatePreview()
    local on = Enabled()
    -- Ahead of both calls below: SetActive registers events off these very values, and
    -- AssertCVars is the first thing that could overwrite a switch we are about to read.
    if on then SeedChannels(Cfg()) end
    SetActive(on)
    AssertCVars()
    if not on then return end
    if suspended then
        wipe(recent)
        ReleaseAll()
        return
    end
    CB.RefreshStyle()
end

-- Profile switches and imports re-point the profile root.
_G._EBS_RefreshChatBubbles = CB.Refresh

do
    local boot = CreateFrame("Frame")
    boot:RegisterEvent("PLAYER_LOGIN")
    boot:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        CB.Refresh()
    end)
end
