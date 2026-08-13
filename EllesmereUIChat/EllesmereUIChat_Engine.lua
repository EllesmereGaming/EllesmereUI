if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIChat_Engine.lua
--
--  Message display engine. Blizzard's chat frames stay fully event-registered
--  as the SECURE formatting/data plane (their handler runs class colors,
--  player links, censoring, TTS, whisper sounds, and third-party message
--  filters exactly as stock); this file owns what the player SEES:
--    - one ScrollingMessageFrame per window, OURS, hosted on the existing
--      chat panel (CFD(cf).bg), fed by a per-frame AddMessage bridge
--    - render suppression of Blizzard's text (FontStringContainer alpha 0,
--      one-time -- nothing in Blizzard code writes that alpha back)
--    - lockstep scrolling, so Blizzard's INVISIBLE hyperlink hit-zones stay
--      aligned under OUR visible text and keep serving link clicks from
--      their secure scripts -- except while Shortened Channel Names is on,
--      when the link takeover serves links from OUR windows instead
--      (shortened text desyncs their zone layout; see the takeover section)
--    - combat log hosting (the one window Blizzard still renders, on demand)
--    - config mirrors (chat color changes, censor/report rebuilds)
--
--  Taint doctrine (module-wide, do not relax):
--    - NEVER hooksecurefunc any FCF_* function (dock-pass hook bodies are
--      the field-measured injector class). The ONE chat-frame method hook is
--      the AddMessage post-hook below, whose body touches OUR frames only.
--      State everywhere else is watched from our own deferred passes.
--    - NEVER reparent a Blizzard chat widget that Blizzard's secure passes
--      later write to (buttonFrame, ScrollToBottomButton, the ScrollBar, the
--      FontStringContainer): secure code manipulating an insecure-parented
--      frame taints the rest of that secure pass -- the field-measured
--      injector this module already fought. Suppression is ALPHA plus mouse
--      state only; the single sanctioned reparent is the scrollbar's stepper
--      arrows (proven by the previous skin).
--    - NEVER write fields onto Blizzard frames -- not even function fields.
--      A field-replaced AddMessage taints the secure MessageEventHandler
--      that reads it, and the handler's whisper tail then dies on
--      SetLastTellTarget's strupper of a (secret) sender name and writes
--      self.tellTimer tainted. The bridge installs via hooksecurefunc,
--      whose wrapper reads as secure. Per-frame state lives in the CFD
--      side table.
--    - Secret message strings (chat messaging lockdown covers encounters,
--      M+, PvP matches, and dungeon/raid maps) pass through WHOLE: no
--      concat, no gsub, no measurement. Our SMF renders them through the
--      elevated AddMessage sink; every optional transform elsewhere is
--      issecretvalue-gated.
-------------------------------------------------------------------------------
local _, ns = ...
local EUI = _G.EllesmereUI
if not EUI then return end

local ECHAT = ns.ECHAT
if not ECHAT then return end

local CFD = EUI._chatCFD
if not CFD then return end

local max, min = math.max, math.min

-------------------------------------------------------------------------------
--  Hidden container for the ONE sanctioned reparent: the Blizzard scrollbar's
--  stepper arrows (the previous skin parked exactly these; nothing in
--  Blizzard code touches them afterwards).
-------------------------------------------------------------------------------
local void = CreateFrame("Frame")
void:Hide()

-------------------------------------------------------------------------------
--  Window store: one entry per Blizzard chat frame we mirror. Keyed by frame
--  reference in a plain table (chat frames are never destroyed).
-------------------------------------------------------------------------------
local WINS = {}
ns._chatWins = WINS

-------------------------------------------------------------------------------
--  Render suppression, alpha-only:
--    FontStringContainer:SetAlpha(0)  their text (SMF line fading writes
--      per-LINE alpha, never the container's; FCF fades touch the frame
--      textures, tab, buttonFrame, and scrollbar, never this container)
--    ScrollBar.Track:SetAlpha(0)      their scrollbar visuals (FCF's hover
--      fade writes the BAR's alpha; the track's own alpha stays ours), plus
--      arrows into the container and both mouse channels off so the dead bar
--      never intercepts input meant for our thin bar in the same gutter
--  Their FontStringContainer keeps its hyperlink hit-zones ARMED on purpose:
--  invisible under our identical, lockstep-scrolled text they serve link
--  clicks from Blizzard's own secure scripts -- unless the link takeover is
--  armed (Shortened Channel Names on), which mouse-blocks them from above.
-------------------------------------------------------------------------------
local function SetBarMouse(bar, on)
    local function Apply(f)
        if not f then return end
        if f.SetMouseClickEnabled then f:SetMouseClickEnabled(on) end
        if f.SetMouseMotionEnabled then f:SetMouseMotionEnabled(on) end
    end
    Apply(bar)
    Apply(bar.Track)
    Apply(bar.Track and bar.Track.Thumb)
end

local function SuppressChatFrameVisuals(cf)
    local d = CFD(cf)
    if d.visualsSuppressed then return end
    d.visualsSuppressed = true
    local fsc = cf.FontStringContainer
    if fsc then fsc:SetAlpha(0) end
    local bar = cf.ScrollBar
    if bar then
        if bar.Back and bar.Back:GetParent() ~= void then bar.Back:SetParent(void) end
        if bar.Forward and bar.Forward:GetParent() ~= void then bar.Forward:SetParent(void) end
        if bar.Track then bar.Track:SetAlpha(0) end
        SetBarMouse(bar, false)
    end
end

-------------------------------------------------------------------------------
--  Our message frame per window. A real ScrollingMessageFrame intrinsic: the
--  same widget Blizzard chat renders with, so wrapping, scroll behavior, and
--  secret-text handling (elevation barriers on AddMessage and friends;
--  SetText accepts secrets from tainted code) are identical by construction.
--  Hosted on the existing per-frame panel, which already follows the chat
--  frame's rect numerically and mirrors its shown state.
--
--  The frame takes mouse WHEEL only (never clicks/motion): plain clicks fall
--  through to the world exactly like stock chat, and hyperlink interaction
--  belongs to Blizzard's invisible hit-zones underneath.
-------------------------------------------------------------------------------

-- Text-area insets within the panel, derived from the same numbers
-- ApplyInputPosition records in d._bgIns: the panel spans the chat frame rect
-- plus those insets, and Blizzard's text area is the chat frame rect inset
-- 6px from the top. Solving both gives fixed panel-relative offsets.
local function LayoutWindowSMF(cf)
    local d = CFD(cf)
    local win = WINS[cf]
    if not (win and win.smf and d.bg) then return end
    local ins = d._bgIns
    local il, ir, it, ib
    if ins then
        il, ir, it, ib = ins.l, ins.r, ins.t, ins.b
    else
        il, ir, it, ib = -10, 10, 3, -6
    end
    local smf = win.smf
    smf:ClearAllPoints()
    -- _smfTopExtra: input-on-top overlays the top strip of the text area;
    -- our view hands that strip back. Line alignment with Blizzard's
    -- invisible text holds -- both render bottom-up from the same bottom
    -- edge, and the input covers the hidden lines' hit-zones.
    smf:SetPoint("TOPLEFT", d.bg, "TOPLEFT", -il, -(it + 6 + (d._smfTopExtra or 0)))
    smf:SetPoint("BOTTOMRIGHT", d.bg, "BOTTOMRIGHT", -ir, -ib)
end
ECHAT.EngineLayoutWindows = function()
    for cf in pairs(WINS) do LayoutWindowSMF(cf) end
end
-- Single-window relayout: the input-on-top strip is released/reclaimed per
-- frame as its edit box shows and hides, and only that frame's text area moves.
ECHAT.EngineLayoutWindow = LayoutWindowSMF

-- Thin scrollbar: visible only while scrolled back (offset > 0) or dragging.
-- Track/thumb are our frames; drag runs a temporary OnUpdate on the track
-- that self-removes on release (no recurring work otherwise).
local function UpdateScrollbar(win)
    local smf, track, thumb = win.smf, win.track, win.thumb
    if not (smf and track and thumb) then return end
    local range = smf:GetMaxScrollRange()
    local offset = smf:GetScrollOffset()
    local show = (offset > 0 or win.dragging) and range > 0
    if track:IsShown() ~= show then track:SetShown(show) end
    if not show then return end
    local trackH = track:GetHeight()
    if not trackH or trackH <= 0 then return end
    local visible = smf:GetNumVisibleLines()
    local total = range + visible
    local frac = total > 0 and (visible / total) or 1
    local thumbH = max(16, trackH * frac)
    thumb:SetHeight(thumbH)
    local pct = range > 0 and (offset / range) or 0
    thumb:ClearAllPoints()
    -- offset 0 = bottom of history, so the thumb rides up as offset grows.
    thumb:SetPoint("BOTTOM", track, "BOTTOM", 0, pct * (trackH - thumbH))
end

-- Keep Blizzard's (invisible) view at the same offset so its hyperlink
-- hit-zones sit under the same lines we render. Elevated public method;
-- clamped by their own range, which matches ours except for replayed
-- session-history lines that only exist on our side (those sit above
-- everything and simply carry no live link zones).
local function SyncBlizzardScroll(win)
    local cf = win.cf
    if cf and cf.SetScrollOffset then
        cf:SetScrollOffset(win.smf:GetScrollOffset())
    end
end

local function ScrollFromCursor(win)
    local track, smf = win.track, win.smf
    local trackH = track:GetHeight()
    local thumbH = win.thumb:GetHeight() or 16
    local travel = trackH - thumbH
    if travel <= 0 then return end
    local bottom = track:GetBottom()
    if not bottom then return end
    local scale = track:GetEffectiveScale()
    local _, cy = GetCursorPosition()
    local localY = (cy / scale) - bottom - (win.dragOffset or thumbH / 2)
    local pct = max(0, min(1, localY / travel))
    local range = smf:GetMaxScrollRange()
    smf:SetScrollOffset(math.floor(pct * range + 0.5))
    SyncBlizzardScroll(win)
end

local function BuildScrollbar(win)
    local track = CreateFrame("Button", nil, win.smf:GetParent())
    track:SetWidth(8)
    track:SetPoint("TOPRIGHT", win.smf, "TOPRIGHT", 7, 0)
    track:SetPoint("BOTTOMRIGHT", win.smf, "BOTTOMRIGHT", 7, 0)
    track:SetFrameLevel(win.smf:GetFrameLevel() + 2)
    track:Hide()
    local thumb = track:CreateTexture(nil, "ARTWORK")
    thumb:SetColorTexture(1, 1, 1, 0.27)
    thumb:SetWidth(4)
    thumb:SetPoint("BOTTOM", track, "BOTTOM", 0, 0)
    win.track, win.thumb = track, thumb

    local function DragTick(self)
        if not IsMouseButtonDown("LeftButton") then
            win.dragging = nil
            self:SetScript("OnUpdate", nil)
            UpdateScrollbar(win)
            return
        end
        ScrollFromCursor(win)
    end
    track:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        local thumbTop, thumbBottom = thumb:GetTop(), thumb:GetBottom()
        local scale = self:GetEffectiveScale()
        local _, cy = GetCursorPosition()
        cy = cy / scale
        if thumbTop and thumbBottom and cy <= thumbTop and cy >= thumbBottom then
            win.dragOffset = cy - thumbBottom
        else
            win.dragOffset = (thumb:GetHeight() or 16) / 2
        end
        win.dragging = true
        ScrollFromCursor(win)
        self:SetScript("OnUpdate", DragTick)
    end)
    track:SetScript("OnMouseUp", function(self)
        win.dragging = nil
        self:SetScript("OnUpdate", nil)
        UpdateScrollbar(win)
    end)
end

-------------------------------------------------------------------------------
--  Link interaction takeover -- armed ONLY while Shortened Channel Names is
--  on. Abbreviating rewrites OUR display copy, but Blizzard's invisible
--  hit-zone layout comes from its UNSHORTENED line, so every zone right of an
--  abbreviation sits shifted by the width delta and clicks land off-target.
--  The two texts genuinely differ, so congruence (the SetIndentedWordWrap fix
--  class) cannot restore alignment; instead OUR SMF takes the mouse and
--  serves links from its own native hit-testing, which the engine lays out
--  from the text actually on screen. Blizzard's stored copy is NEVER
--  rewritten in any form (field wrapper, CHAT_*_GET globals, or
--  TransformMessages all plant tainted values where secure passes read).
--    - A bare SMF intrinsic dispatches NO mouse scripts whatsoever
--      (field-measured: not OnMouseDown, not the hyperlink scripts, no
--      matter the mouse/hyperlink/FSC arming or frame level -- the
--      OnMouseWheel refusal is the same engine class), so interaction rides
--      a PLAIN overlay frame doing its own hit-testing against our
--      rendered fontstrings (BuildLinkOverlay below).
--    - Clicks forward to SetItemRef with an EXPLICIT chat frame -- the
--      sanctioned whisper shape (an explicit frame skips ChatFrame_SendTell's
--      FCF_OpenTemporaryWindow taint cascade). Link classes whose SetItemRef
--      branch writes editbox/tell state are blocked in protected content
--      with a user-visible message; secret links (lockdown lines) are
--      blocked whole; clubTicket is refused outright (REFUSED_LINK_TYPES --
--      the one handler whose taint OUTLIVES the click). Right-click player
--      menus run insecure: Set Focus / Follow can throw for that one menu
--      instance, the accepted trade.
--    - Off = mouse off, these scripts never dispatch, and Blizzard's zones
--      serve clicks exactly as before. Zero per-line, zero per-frame cost.
-------------------------------------------------------------------------------
local issecretL = _G.issecretvalue
local SMFCF = setmetatable({}, { __mode = "k" }) -- our smf -> its Blizzard cf

-- Link types whose SetItemRef branch writes editbox/tell state.
local EDITBOX_LINK_TYPES = {
    player = true, playerGM = true, playerCommunity = true,
    BNplayer = true, BNplayerCommunity = true, channel = true,
}

-- Refused everywhere, not just in protected content. Blizzard's clubTicket
-- handler ends at CommunitiesHyperlink.OnClickLink, which lazily CreateFrames
-- a CLUB_TICKET_RECEIVED listener and SetScripts its OnEvent. Reached from
-- here that SetScript runs under OUR taint, so the handler stays tainted for
-- the session -- and its first statement is C_Club.GetLastTicketResponse,
-- which is protected. Every ticket that arrives afterwards throws
-- ADDON_ACTION_FORBIDDEN against this addon, including the ones Blizzard's
-- own frames requested. Forwarding buys nothing to weigh against that: the
-- response is unreadable from an insecure path either way, so one click
-- would trade a link that cannot work for community invites that no longer
-- work at all. Refuse it before the listener exists.
local REFUSED_LINK_TYPES = { clubTicket = true }

local function LinkBlockedMsg(msg)
    if UIErrorsFrame then
        UIErrorsFrame:AddMessage(msg, 1.0, 0.3, 0.3, 1.0)
    end
end

local PROTECTED_MSG = "This link is protected in Mythic+ and raid combat."
local REFUSED_MSG = "Community invite links need Blizzard's chat: turn off Shortened Channel Names and Timestamp All Messages."

local function WinLinkClick(smf, link, text, button)
    if issecretL and (issecretL(link) or issecretL(text)) then
        LinkBlockedMsg(PROTECTED_MSG)
        return
    end
    if type(link) ~= "string" then return end
    local linkType = link:match("^([^:]+)")
    if REFUSED_LINK_TYPES[linkType] then
        LinkBlockedMsg(REFUSED_MSG)
        return
    end
    if EDITBOX_LINK_TYPES[linkType]
        and EUI.InProtectedInstance and EUI.InProtectedInstance() then
        LinkBlockedMsg(PROTECTED_MSG)
        return
    end
    SetItemRef(link, text, button, SMFCF[smf] or DEFAULT_CHAT_FRAME)
end

local function WinLinkEnter(smf, link, text)
    if issecretL and (issecretL(link) or issecretL(text)) then return end
    local fn = ECHAT.LinkTooltipEnter
    if fn then fn(smf, link) end
end

local function WinLinkLeave(smf)
    local fn = ECHAT.LinkTooltipLeave
    if fn then fn(smf) end
end

local _linkTakeover = false
local _abbrevOn = false     -- Shortened Channel Names user setting
local _stampAllOn = false   -- Timestamp All Messages user setting (resolved)
local _stampFmt = nil       -- its resolved format string
local _protActive = false   -- protected content / dev mode: transforms dormant

-- Blizzard's zones cannot be killed via mouse state (field-measured: FSC
-- dark on BOTH channels, re-asserted per message, and its zones still
-- fired -- the arming rides the chat frame itself). They die cleanly at
-- the source instead: hyperlinks disabled = no run registration at all.
-- Capture-first / exact-restore; EngineTail re-asserts per message (the
-- pipeline re-arm class).
local function ReassertLinkSilence(win)
    local cf = win.cf
    if not cf or not cf.SetHyperlinksEnabled then return end
    if win.cfNativeLinks == nil then
        win.cfNativeLinks = (cf.GetHyperlinksEnabled and cf:GetHyperlinksEnabled()) and true or false
    end
    cf:SetHyperlinksEnabled(false)
end

local function RestoreLinkSilence(win)
    local cf = win.cf
    if not cf or win.cfNativeLinks == nil then return end
    if cf.SetHyperlinksEnabled then cf:SetHyperlinksEnabled(win.cfNativeLinks) end
    win.cfNativeLinks = nil
end

-- Byte-index link scan: |Hlink|hlabel|h spans in raw escaped text, the same
-- byte semantics FindCharacterIndexAtCoordinate returns (Blizzard's own
-- selection copy slices these indexes with :sub). Returns the link data and
-- the WHOLE clickable string (leading |cxxxxxxxx / trailing |r included when
-- present) -- that second value is SetItemRef's "text" argument, and the
-- bare label is NOT a valid value for it: Blizzard's GetFixedLink does
-- strfind(text, "|H") and then arithmetic on the result, and several
-- ItemRefHandlers re-parse the full hyperlink out of it.
local function LinkAtIndex(text, idx)
    local pos = 1
    while true do
        local hs = text:find("|H", pos, true)
        if not hs or hs > idx then return nil end
        local le = text:find("|h", hs + 2, true)
        if not le then return nil end
        local ce = text:find("|h", le + 2, true)
        if not ce then return nil end
        if idx >= hs and idx <= ce + 1 then
            local s, e = hs, ce + 1
            if hs > 10 and text:sub(hs - 10, hs - 1):match("^|c%x%x%x%x%x%x%x%x$") then
                s = hs - 10
            end
            if text:sub(ce + 2, ce + 3) == "|r" then e = ce + 3 end
            return text:sub(hs + 2, le - 1), text:sub(s, e)
        end
        pos = ce + 2
    end
end

-- The interactive surface: a PLAIN frame over the text area. A bare SMF
-- intrinsic dispatches NO mouse scripts at all -- not OnMouseDown, not the
-- hyperlink scripts, regardless of EnableMouse/SetHyperlinksEnabled/FSC
-- arming/frame level (field-measured; the OnMouseWheel refusal is the same
-- engine class) -- so the takeover cannot ride native dispatch. The overlay
-- does its own hit-testing against OUR smf's rendered fontstrings:
--   - motion-only while idle; an OnUpdate runs ONLY while the cursor is
--     inside the text area (OnEnter arms it, OnLeave/OnHide disarm)
--   - the tick finds the fontstring under the cursor
--     (FindCharacterIndexAtCoordinate, strict isInside only -- the mixin's
--     own Find* wrapper falls back to nearest line, which would make every
--     pixel "hit"), maps the byte index into a link span, and drives
--     tooltip enter/leave plus the overlay's click channel: click-enabled
--     ONLY while over a link, so non-link clicks fall through to the world
--     exactly like stock chat
--   - secret text (lockdown lines): GetText returns a secret, the scan is
--     skipped, the spot stays click-through
local function BuildLinkOverlay(win)
    local smf = win.smf
    local ov = CreateFrame("Frame", nil, smf:GetParent())
    ov:SetAllPoints(smf)
    ov:SetFrameLevel(smf:GetFrameLevel() + 1)
    ov:Hide()
    win.linkOverlay = ov

    local curLink, curText
    local function SetHover(link, linkText)
        curText = linkText
        if link == curLink then return end
        if curLink then WinLinkLeave(smf) end
        curLink = link
        if link then WinLinkEnter(smf, link) end
        ov:SetMouseClickEnabled(link ~= nil)
    end
    local function HoverTick()
        local x, y = smf:GetScaledCursorPosition()
        local link, linkText
        local lines = smf.visibleLines
        if lines then
            for i = 1, #lines do
                local fs = lines[i]
                if fs and fs:IsShown() then
                    local ci, inside = fs:FindCharacterIndexAtCoordinate(x, y)
                    -- Secret-content fontstrings return SECRET ci/inside
                    -- (boolean-testing them errors); the line serves no
                    -- links either way. Skip, don't break: every other
                    -- line reports inside=false for this cursor, so the
                    -- hover correctly resolves to no link.
                    if issecretL and (issecretL(ci) or issecretL(inside)) then
                        ci = nil
                    end
                    if ci and inside then
                        local t = fs:GetText()
                        if type(t) == "string" and not (issecretL and issecretL(t)) then
                            link, linkText = LinkAtIndex(t, ci)
                        end
                        break
                    end
                end
            end
        end
        SetHover(link, linkText)
    end
    ov:SetScript("OnEnter", function(self)
        self:SetScript("OnUpdate", HoverTick)
    end)
    ov:SetScript("OnLeave", function(self)
        self:SetScript("OnUpdate", nil)
        SetHover(nil, nil)
    end)
    ov:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
        SetHover(nil, nil)
    end)
    ov:SetScript("OnMouseUp", function(_, btn)
        if curLink then
            WinLinkClick(smf, curLink, curText, btn)
        end
    end)
end

local function ApplyLinkTakeover(win)
    local ov = win.linkOverlay
    if _linkTakeover then
        if ov then
            ov:SetMouseClickEnabled(false)
            ov:SetMouseMotionEnabled(true)
            ov:Show()
        end
        ReassertLinkSilence(win)
    else
        if ov then ov:Hide() end
        RestoreLinkSilence(win)
    end
end

-- Effective arming = any WIDTH-CHANGING transform (channel abbreviation or
-- stamp-all -- both make our line differ from Blizzard's zone layout) MINUS
-- protected content: in M+/raid combat/dev mode every width transform goes
-- dormant (secret hit-test returns and secret links make our lane a
-- degraded experience there), lines render exactly as Blizzard laid them
-- out, and its secure zones -- aligned once more -- serve every link
-- natively, secrets included.
local function RecomputeTakeover()
    local want = (_abbrevOn or _stampAllOn) and not _protActive
    if want == _linkTakeover then return end
    _linkTakeover = want
    for _, win in pairs(WINS) do ApplyLinkTakeover(win) end
end

local function CreateWindowSMF(cf)
    local d = CFD(cf)
    if not d.bg then return nil end
    local smf = CreateFrame("ScrollingMessageFrame", nil, d.bg)
    smf:SetMaxLines(128)
    smf:SetFading(false)
    smf:SetIndentedWordWrap(true)
    smf:SetJustifyH("LEFT")
    -- A bare intrinsic starts with scrolling disallowed; without this the
    -- mixin's ScrollUp/ScrollDown are no-ops.
    smf:SetScrollAllowed(true)
    -- No mouse at all -- ever. A bare SMF intrinsic dispatches NO mouse
    -- scripts (not the wheel, not OnMouseDown, not the hyperlink scripts;
    -- field-measured across all of them -- the engine simply does not route
    -- mouse to Lua-created instances of this widget). Blizzard's chat frame
    -- underneath receives the wheel natively and the scroll-method mirrors
    -- installed with the bridge copy its offset into this view; link
    -- interaction while the takeover is armed rides the PLAIN overlay
    -- frame built below, never this widget.
    smf:EnableMouse(false)
    smf:EnableMouseWheel(false)
    SMFCF[smf] = cf

    local win = { cf = cf, smf = smf }

    -- +4: headroom above every Blizzard zone frame in the stack (cf at
    -- bg+1, its FontStringContainer at bg+2), so the link overlay at smf+1
    -- sits above them all. Mouse-transparent itself, so the altitude
    -- changes nothing while the takeover is disarmed.
    smf:SetFrameLevel(d.bg:GetFrameLevel() + 4)

    win.extraLines = 0
    WINS[cf] = win
    BuildScrollbar(win)
    smf:SetOnScrollChangedCallback(function() UpdateScrollbar(win) end)
    smf:AddOnDisplayRefreshedCallback(function() UpdateScrollbar(win) end)
    BuildLinkOverlay(win)
    ApplyLinkTakeover(win)
    LayoutWindowSMF(cf)
    ECHAT.EngineApplyFontTo(cf)
    return win
end

-------------------------------------------------------------------------------
--  Fonts: family/outline are our settings, per-window size stays Blizzard's
--  (right-click tab -> Font Size, stored via SetChatWindowSize). Shadow
--  matches the previous skin. The Blizzard frame receives the same font from
--  ApplyFonts in the module root, which keeps their (invisible) layout -- and
--  therefore their hyperlink hit-zones -- congruent with ours.
-------------------------------------------------------------------------------
-- Per-window font FAMILIES: a raw SetFont(path) binds ONE file, and Western
-- fonts carry no CJK glyphs -- Chinese/Korean messages rendered tofu boxes
-- (Cyrillic survived; Western fonts include it). Blizzard's chat renders CJK
-- everywhere because its chat font is a per-alphabet family, and 12.1 exposes
-- that mechanism to Lua: CreateFontFamily(name, members). The user's font
-- drives roman+russian; the three CJK alphabets ride the client's stock CJK
-- files (shipped on every locale). Cached per window id; font/size/outline
-- changes re-drive the member font objects in place. Returns nil when the
-- API is missing or creation fails -- callers fall back to plain SetFont
-- (the pre-family behavior, tofu included, never an error).
local FAMS = {}
local CJK_FILES = {
    korean             = "Fonts\\2002.ttf",
    simplifiedchinese  = "Fonts\\ARKai_T.ttf",
    traditionalchinese = "Fonts\\blei00d.TTF",
}
-- The +2 below is a legibility nudge for CJK dropped INTO a western-locale
-- chat. On a CJK client it is not a nudge, it is the whole window: every line
-- is that alphabet, so a user asking for 17 read 19 and the glyphs outgrew the
-- line box the roman height sizes (the "spacing got tighter" half of the same
-- report). Blizzard's per-alphabet heights vary family by family, but their
-- CHAT font is the one that matters here and it bumps nothing upward:
-- ChatFontNormal inherits NumberFont_Shadow_Med, whose members are roman 14,
-- simplifiedchinese 14, traditionalchinese 14, korean 13. Their tab-menu size
-- control then bypasses the family entirely (FCF_SetChatWindowFontSize raw
-- SetFonts the active alphabet's file at the chosen number), so a size the
-- user picked renders literally. Ours does the same: the client's own
-- alphabet takes the size unmodified.
local CJK_CLIENT_ALPHABET = ({
    koKR = "korean",
    zhCN = "simplifiedchinese",
    zhTW = "traditionalchinese",
})[GetLocale()]
local function CJKHeight(alphabet, size)
    if alphabet == CJK_CLIENT_ALPHABET then return size end
    return size + 2
end
function ECHAT.EngineFontFamily(id, font, size, flags)
    flags = flags or ""
    local fam = FAMS[id]
    if fam == false then return nil end -- failed once; never retry-loop
    if not fam then
        if not CreateFontFamily then FAMS[id] = false; return nil end
        local members = {
            { alphabet = "roman",   file = font, height = size, flags = flags },
            { alphabet = "russian", file = font, height = size, flags = flags },
        }
        -- CJK renders +2px: ideographs at latin point sizes read visibly
        -- smaller (dense glyphs, no ascender/descender whitespace). Not on the
        -- client's own alphabet -- see CJKHeight.
        for alphabet, file in pairs(CJK_FILES) do
            members[#members + 1] = { alphabet = alphabet, file = file, height = CJKHeight(alphabet, size), flags = flags }
        end
        local ok, created = pcall(CreateFontFamily, "EUIChatFontFamily" .. id, members)
        if not ok or not created then FAMS[id] = false; return nil end
        FAMS[id] = created
        return created
    end
    local ok = pcall(function()
        fam:GetFontObjectForAlphabet("roman"):SetFont(font, size, flags)
        fam:GetFontObjectForAlphabet("russian"):SetFont(font, size, flags)
        for alphabet, file in pairs(CJK_FILES) do
            fam:GetFontObjectForAlphabet(alphabet):SetFont(file, CJKHeight(alphabet, size), flags)
        end
    end)
    if not ok then return nil end
    return fam
end

function ECHAT.EngineApplyFontTo(cf)
    local win = WINS[cf]
    if not win then return end
    local font = ECHAT.EngineFontProvider and ECHAT.EngineFontProvider()
    local size = ECHAT.EngineFontSizeProvider and ECHAT.EngineFontSizeProvider(cf:GetID())
    local flags = ECHAT.EngineOutlineProvider and ECHAT.EngineOutlineProvider()
    if font and size then
        local fam = ECHAT.EngineFontFamily(cf:GetID(), font, size, flags or "")
        if fam then
            win.smf:SetFontObject(fam)
        else
            win.smf:SetFont(font, size, flags or "")
        end
        win.smf:SetShadowOffset(1, -1)
        win.smf:SetShadowColor(0, 0, 0, 0.8)
    end
end

function ECHAT.EngineApplyFonts()
    for cf in pairs(WINS) do ECHAT.EngineApplyFontTo(cf) end
end

-------------------------------------------------------------------------------
--  Bridge: hooksecurefunc post-hook on cf.AddMessage, the LAST step of
--  Blizzard's message pipeline. The original runs first (elevated store
--  through the ScrollingMessageFrameSecureMixin barrier + TTS observer),
--  then our tail copies the final formatted line into our window.
--
--  hooksecurefunc is load-bearing, not style: its wrapper reads as SECURE,
--  so the secure MessageEventHandler calling self:AddMessage stays secure
--  for its whisper tail -- SetLastTellTarget strupper()s a possibly-secret
--  sender name (legal only in secure execution) and self.tellTimer must be
--  written untainted. A tainted function field there blocks the strupper.
--  Our tail performs no string operations -- secret lines flow through
--  whole into the elevated SMF sink.
--
--  Extra args stored per line: chatTypeID (5th, the slot Blizzard's own
--  recolor compares), lineID (from the packed event args; may be secret --
--  stored, never inspected), event name.
-------------------------------------------------------------------------------
local EngineTailObserver -- optional (session history); set via ECHAT below
local EngineTabObserver -- optional (tab strip flash/unread); set via ECHAT below
local QueueDivergedRebuild -- forward declaration (defined with the mirrors)
local EngineUpdateProtectedState -- forward declaration (defined with the mirrors)

-------------------------------------------------------------------------------
--  Shortened channel names (opt-in). The transform runs on OUR display copy
--  only -- Blizzard's stored line is never touched (the live-tree wrapper
--  that replaced cf.AddMessage is the field-replace taint class this engine
--  exists to eliminate, and rewriting the CHAT_*_GET globals is the other
--  field-proven poison). Matching is on the channel hyperlink KEYWORD
--  (|Hchannel:party|h[...]|h), locale-independent, plain substring scanning.
--  Secret lines pass through whole. While this feature is on, the link
--  takeover (section above CreateWindowSMF) serves hyperlinks from OUR
--  windows -- shortened text desyncs Blizzard's invisible hit-zones, both
--  within a line (width delta) and across wraps.
-------------------------------------------------------------------------------
local issecretvalue = _G.issecretvalue

local CHANNEL_ABBR_LOOKUP = {
    PARTY                = "P",
    PARTY_LEADER         = "PL",
    PARTY_GUIDE          = "PG",
    RAID                 = "R",
    GUILD                = "G",
    BATTLEGROUND         = "BG",
    INSTANCE_CHAT        = "I",
    -- Unverified keywords stay out (OFFICER, RAID_LEADER, leader variants):
    -- an unmatched keyword is a silent pass-through, never an error.
}

-- World channels use hyperlink keyword "channel:<N>": 1=General, 2=Trade,
-- 22=LocalDefense, 23=WorldDefense, 26=LookingForGroup.
local WORLD_CHANNEL_ABBR = {
    ["1"]  = "Ge",
    ["2"]  = "T",
    ["22"] = "LD",
    ["23"] = "WD",
    ["26"] = "LFG",
}

local function ShortChannelReplacer(hyperlinkTarget)
    local abbr = CHANNEL_ABBR_LOOKUP[hyperlinkTarget:upper()]
    if not abbr then
        local channelNum = hyperlinkTarget:match("^channel:(%d+)$")
        if channelNum then
            abbr = WORLD_CHANNEL_ABBR[channelNum] or channelNum
        end
    end
    if not abbr then return nil end
    return "|Hchannel:" .. hyperlinkTarget .. "|h[" .. abbr .. "]|h"
end

local function AbbreviateChannelText(text)
    local HDR, HDR_LEN = "|Hchannel:", 10
    local pieces, pos, n = {}, 1, 0
    local searchPos = 1
    while true do
        local hStart = text:find(HDR, searchPos, true)
        if not hStart then break end
        local keyStart = hStart + HDR_LEN
        local hEnd = text:find("|h", keyStart, true)
        if not hEnd then break end
        local bracketStart = hEnd + 2
        if text:sub(bracketStart, bracketStart) ~= "[" then
            searchPos = bracketStart
        else
            local closeBracket = text:find("]|h", bracketStart, true)
            if not closeBracket then break end
            local hyperlinkTarget = text:sub(keyStart, hEnd - 1)
            local replacement = ShortChannelReplacer(hyperlinkTarget)
            local segmentEnd = closeBracket + 2
            n = n + 1
            pieces[n] = text:sub(pos, hStart - 1)
            n = n + 1
            pieces[n] = replacement or text:sub(hStart, segmentEnd)
            pos = segmentEnd + 1
            searchPos = pos
        end
    end
    n = n + 1
    pieces[n] = text:sub(pos)
    return table.concat(pieces)
end

-- _abbrevOn is declared with the takeover state (the two arm together:
-- abbreviation is the one transform that changes glyph widths, so it alone
-- desyncs Blizzard's invisible hit-zones from our text; class-colored names
-- insert only zero-width color codes and need no takeover).
function ECHAT.EngineSetChannelAbbrev(on)
    _abbrevOn = on == true
    RecomputeTakeover()
end

-------------------------------------------------------------------------------
--  Class-colored names in message BODIES (opt-in). Names of current group or
--  raid members found in the text of Say/Yell/Party/Raid lines get wrapped in
--  their class color -- on OUR display copy only, same lane as the channel
--  abbreviations. The roster registry is event-driven and registered ONLY
--  while the feature is on; off = one boolean per line. Matching is
--  case-insensitive on whole words, skips every escape span (color codes,
--  hyperlink target AND label, textures/atlases), and preserves the typed
--  casing -- only color codes are inserted around it.
-------------------------------------------------------------------------------
local CCN_EVENTS = {
    CHAT_MSG_SAY = true, CHAT_MSG_YELL = true,
    CHAT_MSG_PARTY = true, CHAT_MSG_PARTY_LEADER = true,
    CHAT_MSG_RAID = true, CHAT_MSG_RAID_LEADER = true,
    CHAT_MSG_RAID_WARNING = true,
}

local _ccnOn = false
local ROSTER_LOW = {} -- lowered short name -> class colorStr ("ffrrggbb")

local function RosterAdd(unit, colors)
    if not UnitExists(unit) then return end
    local name = UnitName(unit)
    if issecretvalue and issecretvalue(name) then return end
    if type(name) ~= "string" or name == "" then return end
    local class = (UnitClassBase and UnitClassBase(unit)) or select(2, UnitClass(unit))
    if issecretvalue and issecretvalue(class) then return end
    local c = class and colors[class]
    if c and c.colorStr then
        ROSTER_LOW[name:lower()] = c.colorStr
    end
end

local function RebuildRoster()
    wipe(ROSTER_LOW)
    local colors = _G.RAID_CLASS_COLORS
    if not colors then return end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            RosterAdd("raid" .. i, colors)
        end
    else
        RosterAdd("player", colors)
        for i = 1, 4 do
            RosterAdd("party" .. i, colors)
        end
    end
end

local rosterFrame = CreateFrame("Frame")
local _rosterQueued = false
local function QueueRosterRebuild()
    if _rosterQueued then return end
    _rosterQueued = true
    C_Timer.After(0, function()
        _rosterQueued = false
        RebuildRoster()
    end)
end
rosterFrame:SetScript("OnEvent", QueueRosterRebuild)

function ECHAT.EngineSetClassColorNames(on)
    _ccnOn = on == true
    if _ccnOn then
        rosterFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
        rosterFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        -- Synchronous: the login backfill and the option toggle's retroactive
        -- window rebuild run the transform before any deferred tick fires.
        RebuildRoster()
    else
        rosterFrame:UnregisterAllEvents()
        wipe(ROSTER_LOW)
    end
end

-- Escape spans the name scanner must never touch. Hyperlinks are protected
-- through their LABEL too: corrupting a |H target breaks the link, and
-- sender-name labels are already colored by Blizzard's own composer.
-- Scratch arrays are file-scope reuse (no per-line table churn).
local _protS, _protE = {}, {}
local _hitS, _hitE, _hitC = {}, {}, {}

local function CollectProtected(text)
    local n, pos = 0, 1
    while true do
        local p = text:find("|", pos, true)
        if not p then break end
        local c = text:sub(p + 1, p + 1)
        local e
        if c == "c" then
            if text:sub(p + 2, p + 2) == "n" then
                -- |cnCOLORNAME: variable-length named-color form
                local colon = text:find(":", p + 3, true)
                e = colon or (p + 2)
            else
                e = p + 9 -- |cAARRGGBB
            end
        elseif c == "r" then
            e = p + 1
        elseif c == "H" then
            local h1 = text:find("|h", p + 2, true)
            local h2 = h1 and text:find("|h", h1 + 2, true)
            e = (h2 and h2 + 1) or (h1 and h1 + 1) or (p + 1)
        elseif c == "T" or c == "A" then
            local close = text:find(c == "T" and "|t" or "|a", p + 2, true)
            e = (close and close + 1) or (p + 1)
        elseif c == "|" then
            e = p + 1 -- escaped pipe
        else
            pos = p + 1
        end
        if e then
            n = n + 1
            _protS[n] = p
            _protE[n] = e
            pos = e + 1
        end
    end
    return n
end

-- Word boundary on raw bytes: ASCII letters/digits and every UTF-8 byte
-- (>= 128) count as word characters, so accented names stay whole.
local function IsBoundary(text, idx)
    if idx < 1 or idx > #text then return true end
    local b = text:byte(idx)
    if b >= 128 then return false end
    if b >= 48 and b <= 57 then return false end
    if b >= 65 and b <= 90 then return false end
    if b >= 97 and b <= 122 then return false end
    return true
end

local function ColorRosterNames(text)
    if next(ROSTER_LOW) == nil then return text end
    local lower = text:lower()
    local nProt = CollectProtected(text)
    local nHits = 0
    for nameLow, colorStr in pairs(ROSTER_LOW) do
        local nameLen = #nameLow
        local from = 1
        while true do
            local s = lower:find(nameLow, from, true)
            if not s then break end
            local e = s + nameLen - 1
            from = e + 1
            if IsBoundary(text, s - 1) and IsBoundary(text, e + 1) then
                local blocked = false
                for i = 1, nProt do
                    if s <= _protE[i] and e >= _protS[i] then
                        blocked = true
                        break
                    end
                end
                if not blocked then
                    nHits = nHits + 1
                    _hitS[nHits] = s
                    _hitE[nHits] = e
                    _hitC[nHits] = colorStr
                end
            end
        end
    end
    if nHits == 0 then return text end
    -- Insertion sort by start position (hit counts are tiny).
    for i = 2, nHits do
        local s, e, c = _hitS[i], _hitE[i], _hitC[i]
        local j = i - 1
        while j >= 1 and _hitS[j] > s do
            _hitS[j + 1], _hitE[j + 1], _hitC[j + 1] = _hitS[j], _hitE[j], _hitC[j]
            j = j - 1
        end
        _hitS[j + 1], _hitE[j + 1], _hitC[j + 1] = s, e, c
    end
    local pieces, np, pos = {}, 0, 1
    for i = 1, nHits do
        local s, e = _hitS[i], _hitE[i]
        if s >= pos then
            np = np + 1; pieces[np] = text:sub(pos, s - 1)
            np = np + 1; pieces[np] = "|c"
            np = np + 1; pieces[np] = _hitC[i]
            np = np + 1; pieces[np] = text:sub(s, e)
            np = np + 1; pieces[np] = "|r"
            pos = e + 1
        end
    end
    np = np + 1
    pieces[np] = text:sub(pos)
    return table.concat(pieces)
end

-- Shared by the live tail and the rebuild path, so rebuilt windows keep
-- their transforms. Secret check FIRST (doctrine), then cheap pre-checks so
-- untouched lines cost one plain find / one set lookup. Backfilled session
-- history passes no event, so name coloring never runs there (stored lines
-- were captured in display form already).
local function DisplayText(msg, event)
    if not _abbrevOn and not _ccnOn then return msg end
    if issecretvalue and issecretvalue(msg) then return msg end
    if type(msg) ~= "string" then return msg end
    if _abbrevOn and not _protActive and msg:find("|Hchannel:", 1, true) then
        msg = AbbreviateChannelText(msg)
    end
    if _ccnOn and event ~= nil
        and not (issecretvalue and issecretvalue(event))
        and CCN_EVENTS[event] then
        msg = ColorRosterNames(msg)
    end
    return msg
end

-------------------------------------------------------------------------------
--  Timestamp All Messages (opt-in). Blizzard's formatter stamps ONLY ordinary
--  player chat and pings (verified against its MessageEventHandler source);
--  system/loot/achievement/BG/BN-toast branches and direct AddMessage calls
--  (addon prints) are never stamped. This transform stamps OUR display copy
--  of any line that arrives without one -- same lane as the channel
--  abbreviations, display-only, Blizzard's stored line untouched.
--  Secret lines pass through whole (concat on secrets errors; those are
--  player messages, which Blizzard already stamps). Session history composes
--  cleanly: its capture stripper removes ANY leading stamp (ours or baked)
--  and replay re-derives the prefix from the stored serverTime.
-------------------------------------------------------------------------------
-- _stampAllOn/_stampFmt are declared with the takeover state: stamping is a
-- WIDTH-CHANGING transform exactly like abbreviation, so it arms the link
-- takeover too (a stamped loot line's item link would otherwise sit shifted
-- off Blizzard's unstamped zone layout).
function ECHAT.EngineSetStampAll(on, fmt)
    if on == true and type(fmt) == "string" and fmt ~= "" then
        _stampAllOn, _stampFmt = true, fmt
    else
        _stampAllOn, _stampFmt = false, nil
    end
    RecomputeTakeover()
end

-- Same prefix patterns as the session-history stripper (keep in sync): any
-- line already starting with a rendered stamp is left alone, so Blizzard's
-- baked stamps never double up.
local function HasTimestampPrefix(msg)
    return msg:find("^%d%d?:%d%d:%d%d%s*[AP]M%s") ~= nil
        or msg:find("^%d%d?:%d%d:%d%d%s") ~= nil
        or msg:find("^%d%d?:%d%d%s*[AP]M%s") ~= nil
        or msg:find("^%d%d?:%d%d%s") ~= nil
end

-- when: server time for the stamp; nil = now. date() (not BetterDate) to
-- match the session-history replay prefix exactly.
local function StampDisplay(msg, when)
    -- Dormant in protected content, same as the abbreviations: the takeover
    -- is disarmed there and a width-changed line would desync Blizzard's
    -- restored zones.
    if not _stampAllOn or _protActive then return msg end
    if type(msg) ~= "string" then return msg end
    if issecretvalue and issecretvalue(msg) then return msg end
    if HasTimestampPrefix(msg) then return msg end
    local ok, ts = pcall(date, _stampFmt, when and math.floor(when) or nil)
    if ok and type(ts) == "string" and ts ~= "" then
        return ts .. msg
    end
    return msg
end

local function ExtractLineID(eventArgs)
    if type(eventArgs) == "table" then
        return eventArgs[11]
    end
    return nil
end

local function EngineTail(cf, msg, r, g, b, chatTypeID, accessID, typeID, event, eventArgs)
    -- Cheap per-message probe: catches protected-state flips that have no
    -- zone-in edge (dev mode toggles) before the next line renders.
    if EngineUpdateProtectedState then EngineUpdateProtectedState() end
    local win = WINS[cf]
    local display = StampDisplay(DisplayText(msg, event))
    if win then
        win.smf:AddMessage(display, r, g, b, chatTypeID, ExtractLineID(eventArgs), event)
        -- The pipeline re-arms Blizzard chat widget state per line (the PMOff
        -- zombie class); while the takeover is armed, keep their zones silent.
        if _linkTakeover then ReassertLinkSilence(win) end
        -- Divergence check: if Blizzard's buffer was cleared behind our back
        -- (window reset, a third-party Clear call, temp-window pool reuse),
        -- its count falls below ours the moment the next line lands. Both
        -- counts are cheap reads; the rebuild is deferred + coalesced.
        -- extraLines is the session-history allowance: replayed lines exist
        -- only on our side and must never read as divergence.
        if cf:GetNumMessages() + (win.extraLines or 0) < win.smf:GetNumMessages() then
            if QueueDivergedRebuild then QueueDivergedRebuild(cf) end
        end
    end
    if EngineTailObserver then
        -- Session history captures the display form (what the user saw), so
        -- replayed lines match the surrounding scrollback.
        EngineTailObserver(cf, display, r, g, b, chatTypeID, event)
    end
    if EngineTabObserver then
        EngineTabObserver(cf, event)
    end
end

function ECHAT.EngineSetTailObserver(fn)
    EngineTailObserver = fn
end

function ECHAT.EngineSetTabObserver(fn)
    EngineTabObserver = fn
end

-- Scroll authority is BLIZZARD'S view: it receives the wheel natively and
-- its scroll methods run from every input source (wheel handler, page
-- keybinds, scroll-to-bottom). These post-hooks mirror the resulting offset
-- into our view -- same proven mechanism as the AddMessage bridge, body
-- touches OUR frame only. (Our thin bar's drag pushes the other way via
-- SetScrollOffset, which is not among the hooked methods -- no loop.)
local SCROLL_METHODS = {
    "ScrollUp", "ScrollDown", "PageUp", "PageDown", "ScrollToTop", "ScrollToBottom",
}

local function MirrorScroll(cf)
    local win = WINS[cf]
    if win then
        win.smf:SetScrollOffset(cf:GetScrollOffset())
    end
end

-- Wheel handler, the Prat lane: 12.1 wires NO OnMouseWheel onto chat
-- frames (the slot is nil; only GMChat sets one -- via this same SetScript
-- pattern) and no built-in wheel scrolling reliably reaches them, so each
-- frame gets OUR self-sufficient handler. SetScript replaces nothing
-- secure (nil slot), is immune to install-time state (dispatch reads the
-- current script at wheel time), and the body calls only the frame's own
-- elevated scroll methods -- which the MirrorScroll hooks above carry into
-- our view. Semantics: plain = 3 lines, Shift = top/bottom, Ctrl = page.
local function ChatFrameWheel(cf, delta)
    local up = delta > 0
    -- While the link takeover is armed, OUR view is both the zone source and
    -- the scroll authority: Blizzard's buffer lacks the replayed session
    -- history, so routing the wheel through ITS scroll methods pins the
    -- offset at its (shorter) range and the history rows above are
    -- unreachable (field report: "can't scroll up in history after /reload,
    -- but the copy popup shows it"). Its zones are silenced while armed, so
    -- lockstep no longer matters; SyncBlizzardScroll still nudges its view
    -- as far as its clamp allows. Hidden smf (combat log host, passthrough)
    -- and disarmed mode keep the Blizzard lane, where lockstep IS the zone
    -- alignment.
    local win = WINS[cf]
    if win and _linkTakeover and win.smf:IsShown() then
        local smf = win.smf
        if IsShiftKeyDown() then
            if up then smf:ScrollToTop() else smf:ScrollToBottom() end
        elseif IsControlKeyDown() and smf.PageUp then
            if up then smf:PageUp() else smf:PageDown() end
        else
            for _ = 1, 3 do
                if up then smf:ScrollUp() else smf:ScrollDown() end
            end
        end
        SyncBlizzardScroll(win)
        return
    end
    if IsShiftKeyDown() then
        if up then cf:ScrollToTop() else cf:ScrollToBottom() end
    elseif IsControlKeyDown() and cf.PageUp then
        if up then cf:PageUp() else cf:PageDown() end
    else
        for _ = 1, 3 do
            if up then cf:ScrollUp() else cf:ScrollDown() end
        end
    end
end

local function InstallBridge(cf)
    local d = CFD(cf)
    if d.bridged then return end
    d.bridged = true
    -- EngineTail's signature matches the hook's (self arrives as its cf);
    -- the trailing MessageFormatter argument is dropped by arity.
    hooksecurefunc(cf, "AddMessage", EngineTail)
    for i = 1, #SCROLL_METHODS do
        local name = SCROLL_METHODS[i]
        -- Existence-guarded: a missing method would throw and kill the rest
        -- of this install.
        if type(cf[name]) == "function" then
            hooksecurefunc(cf, name, MirrorScroll)
        end
    end
    cf:SetScript("OnMouseWheel", ChatFrameWheel)
    cf:EnableMouseWheel(true)
end

-------------------------------------------------------------------------------
--  Backfill / rebuild from Blizzard's buffer. Used at install (lines that
--  arrived before us: login system messages, GMOTD, temp-window seed copies)
--  and as the rare-path mirror for censor approvals and report removals,
--  where Blizzard rewrites its stored lines and a rebuild reproduces the
--  result exactly. GetMessageInfo(1) is the oldest line. Reads are plain
--  table reads; returned strings may be secret and are passed through whole.
-------------------------------------------------------------------------------
local function RebuildWindowFromBuffer(cf)
    local win = WINS[cf]
    if not win then return end
    local smf = win.smf
    smf:Clear()
    win.extraLines = 0
    local n = cf:GetNumMessages()
    -- Stamp-all rebuilds stamp with each line's true arrival time: the SMF
    -- entry timestamp is GetTime()-domain (PackageEntry), converted here to
    -- server time. Read-only buffer access; missing internals just skip the
    -- stamp for that line.
    local hb, nowT, nowG
    if _stampAllOn and not _protActive then
        hb = cf.historyBuffer
        if not (hb and hb.GetEntryAtIndex and hb.GetNumElements) then hb = nil end
        nowT, nowG = time(), GetTime()
    end
    for i = 1, n do
        local msg, r, g, b, chatTypeID, accessID, typeID, event, eventArgs = cf:GetMessageInfo(i)
        if msg ~= nil then
            local display = DisplayText(msg, event)
            if hb then
                local entry = hb:GetEntryAtIndex(hb:GetNumElements() - i + 1)
                local ts = entry and entry.timestamp
                if type(ts) == "number" then
                    display = StampDisplay(display, nowT - (nowG - ts))
                end
            end
            smf:AddMessage(display, r, g, b, chatTypeID, ExtractLineID(eventArgs), event)
        end
    end
    smf:ScrollToBottom()
    SyncBlizzardScroll(win)
end
ECHAT.EngineRebuildWindow = RebuildWindowFromBuffer

-------------------------------------------------------------------------------
--  Integration: bring one chat frame under engine management. Idempotent and
--  driven only from our own deferred passes (login skin pass, whisper-event
--  full passes, UPDATE_CHAT_WINDOWS) -- never from inside Blizzard execution.
--
--  Temp-window pool reuse: Blizzard Clear()s the recycled frame for the new
--  conversation. Their buffer count dropping below ours is the reuse edge;
--  we rebuild ours from their (fresh) buffer.
-------------------------------------------------------------------------------
local function IntegrateChatFrame(cf)
    local d = CFD(cf)
    if not d.bg then return end
    SuppressChatFrameVisuals(cf)
    local win = WINS[cf]
    if not win then
        win = CreateWindowSMF(cf)
        if not win then return end
        InstallBridge(cf)
        RebuildWindowFromBuffer(cf)
        return
    end
    InstallBridge(cf)
    -- extraLines allowance, same as the bridge tail's check: replayed
    -- session-history lines exist only on our side, and the login full
    -- passes re-integrate every frame right after the restore -- without
    -- the allowance that read as a cleared buffer and wiped the replay.
    local theirs = cf:GetNumMessages()
    if theirs + (win.extraLines or 0) < win.smf:GetNumMessages() then
        RebuildWindowFromBuffer(cf)
    end
end

function ECHAT.EngineIntegrateAll()
    for i = 1, 20 do
        local cf = _G["ChatFrame" .. i]
        if cf and CFD(cf).bg then
            -- While hosted, the combat log keeps Blizzard's renderer; its
            -- window object still exists for when the tab is deselected.
            if not (ns._clHosted and IsCombatLog and IsCombatLog(cf)) then
                IntegrateChatFrame(cf)
            elseif not WINS[cf] then
                if CreateWindowSMF(cf) then InstallBridge(cf) end
            end
        end
    end
    ECHAT.EngineUpdateCombatLogHost()
end

-------------------------------------------------------------------------------
--  Combat log hosting. The combat log is a specialized Blizzard filter
--  engine (quick buttons, per-filter coloring, its own refill machinery);
--  rebuilding it is out of scope. While its tab is selected, Blizzard
--  renders it exactly as the previous skin displayed it: its text container
--  returns to alpha 1 and its scrollbar (thin: arrows stay parked) comes
--  back to life; our window for it hides. Deselecting reverses everything.
--  The quick-button bar needs no handling: it is parented to ChatFrame2Tab
--  and shows/hides with the (unchanged) tab system as it always has.
-------------------------------------------------------------------------------
function ECHAT.EngineUpdateCombatLogHost()
    local cf2 = _G.ChatFrame2
    if not cf2 or not IsCombatLog or not IsCombatLog(cf2) then return end
    local selected = GENERAL_CHAT_DOCK and FCFDock_GetSelectedWindow
        and FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
    local host = (selected == cf2)
    if host == (ns._clHosted or false) then return end
    ns._clHosted = host
    local win = WINS[cf2]
    local fsc = cf2.FontStringContainer
    local bar = cf2.ScrollBar
    if host then
        if fsc then fsc:SetAlpha(1) end
        if bar then
            if bar.Track then bar.Track:SetAlpha(1) end
            SetBarMouse(bar, true)
        end
        if win then
            win.smf:Hide()
            -- Blizzard renders the CL itself: its zones must serve links.
            RestoreLinkSilence(win)
        end
    else
        if fsc then fsc:SetAlpha(0) end
        if bar then
            if bar.Track then bar.Track:SetAlpha(0) end
            SetBarMouse(bar, false)
        end
        if win then
            ApplyLinkTakeover(win)
            win.smf:Show()
            -- Same extraLines allowance as IntegrateChatFrame: replayed
            -- lines on our side are not a cleared Blizzard buffer.
            local theirs = cf2:GetNumMessages()
            if theirs + (win.extraLines or 0) < win.smf:GetNumMessages() then
                RebuildWindowFromBuffer(cf2)
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Mirrors, on our own standalone event frame (never chat-frame hooks):
--    UPDATE_CHAT_COLOR        recolor stored lines whose chatTypeID matches
--    PLAYER_REPORT_SUBMITTED  rare: rebuild from Blizzard's buffers
--    CAUTIONARY_CHAT_MESSAGE  rare: rebuild (censor placeholder/approval)
--  Rebuilds are deferred one tick so Blizzard's own TransformMessages pass
--  has finished writing its buffers before we copy them.
-------------------------------------------------------------------------------
local mirrorFrame = CreateFrame("Frame")
mirrorFrame:RegisterEvent("UPDATE_CHAT_COLOR")
mirrorFrame:RegisterEvent("PLAYER_REPORT_SUBMITTED")
mirrorFrame:RegisterEvent("CAUTIONARY_CHAT_MESSAGE")

local _rebuildQueued = false
local function QueueRebuildAll()
    if _rebuildQueued then return end
    _rebuildQueued = true
    C_Timer.After(0, function()
        _rebuildQueued = false
        for cf in pairs(WINS) do
            if not (ns._clHosted and IsCombatLog and IsCombatLog(cf)) then
                RebuildWindowFromBuffer(cf)
            end
        end
    end)
end
-- Exported for the channel-abbreviation toggle: re-renders every window from
-- Blizzard's buffer so the change applies to existing scrollback (session
-- history backfill lines are shed by the rebuild, same as censor rebuilds).
ECHAT.EngineQueueRebuildAll = QueueRebuildAll

-- Protected-content master switch for the abbreviation feature. On a flip
-- the takeover re-arms/disarms and every window rebuilds: entering
-- protected content UNSHORTENS the scrollback (DisplayText stops
-- abbreviating while _protActive) so Blizzard's restored secure zones line
-- up again; leaving re-shortens. No-op while the state is unchanged, so
-- the PEW edge and the per-message probe cost one comparison.
EngineUpdateProtectedState = function()
    local prot = (EUI.InProtectedInstance and EUI.InProtectedInstance()) and true or false
    if prot == _protActive then return end
    _protActive = prot
    RecomputeTakeover()
    QueueRebuildAll()
end

-- Single-window rebuild for the bridge tail's divergence check.
local _divergedQueued = {}
QueueDivergedRebuild = function(cf)
    if _divergedQueued[cf] then return end
    _divergedQueued[cf] = true
    C_Timer.After(0, function()
        _divergedQueued[cf] = nil
        RebuildWindowFromBuffer(cf)
    end)
end

local function RecolorOurWindows(chatType, r, g, b)
    local info = ChatTypeInfo[strupper(chatType)]
        or (ChatAdditionalColors and ChatAdditionalColors[strupper(chatType)])
    if not info or not info.id then return end
    local targetID = info.id
    local function Recolor(message, mr, mg, mb, chatTypeID)
        if chatTypeID == targetID then
            return true, r, g, b
        end
        return false
    end
    for _, win in pairs(WINS) do
        win.smf:AdjustMessageColors(Recolor)
    end
end

mirrorFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
mirrorFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "UPDATE_CHAT_COLOR" then
        local chatType, r, g, b = ...
        if type(chatType) == "string" then
            RecolorOurWindows(chatType, r, g, b)
            if strupper(chatType) == "WHISPER" then
                RecolorOurWindows("REPLY", r, g, b)
            end
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Protected-state boundary check only: rebuilds ONLY on a flip
        -- (never a per-loading-screen pass).
        EngineUpdateProtectedState()
    else
        QueueRebuildAll()
    end
end)

-------------------------------------------------------------------------------
--  Public helpers for the rest of the module
-------------------------------------------------------------------------------
function ECHAT.EngineScrollToBottom(cf)
    cf = cf or _G.ChatFrame1
    local win = WINS[cf]
    if not win then return end
    -- Through Blizzard's method so the mirror brings our view along --
    -- single scroll authority, both views land at the bottom together.
    if cf.ScrollToBottom then
        cf:ScrollToBottom()
    else
        win.smf:ScrollToBottom()
        SyncBlizzardScroll(win)
    end
end

-- Copy Chat source: first return of each stored line from OUR window
-- (identical content to the old Blizzard-frame read; the caller skips
-- secret lines).
function ECHAT.EngineGetMessageLines(cf, out)
    local win = WINS[cf]
    if not win then return 0 end
    local smf = win.smf
    local n = smf:GetNumMessages()
    for i = 1, n do
        out[#out + 1] = smf:GetMessageInfo(i)
    end
    return n
end

-- Session history replay: push one restored line into a window's display.
-- The extraLines allowance keeps the divergence check from reading replayed
-- lines (which exist only on our side) as a cleared Blizzard buffer.
function ECHAT.EngineBackfillLine(cf, text, r, g, b, id)
    local win = WINS[cf]
    if not win then return false end
    -- DisplayText keeps replayed history consistent with the current
    -- abbreviation setting; the scanner is idempotent on stored lines that
    -- were captured already shortened.
    win.smf:BackFillMessage(DisplayText(text), r, g, b, id)
    win.extraLines = (win.extraLines or 0) + 1
    return true
end

function ECHAT.EngineNumMessages(cf)
    local win = WINS[cf]
    if not win then return 0 end
    return win.smf:GetNumMessages()
end

-- Full-hide passthrough support: our display simply hides (a hidden frame
-- cannot receive input and its line pool arms nothing); the scrollbar track
-- hides with it and recomputes on reveal.
function ECHAT.EngineSetPassthrough(on)
    for _, win in pairs(WINS) do
        if on then
            if win.smf:IsShown() then
                win.pmWasShown = true
                win.smf:Hide()
            end
            if win.track then win.track:Hide() end
            if win.linkOverlay then win.linkOverlay:Hide() end
        else
            if win.pmWasShown then
                win.pmWasShown = nil
                win.smf:Show()
            end
            -- Re-shows the link overlay when the takeover is armed.
            ApplyLinkTakeover(win)
            UpdateScrollbar(win)
        end
    end
end
