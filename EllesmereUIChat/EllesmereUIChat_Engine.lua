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
--      aligned under OUR visible text and serve every link click from their
--      secure scripts; width transforms (abbreviation/stamps) keep that
--      alignment by writing the display form back into Blizzard's stored
--      entries (see the zone-alignment section)
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
--  clicks from Blizzard's own secure scripts (the buffer write-back keeps
--  their layout identical to ours even for width-transformed lines).
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
--  Width-transform zone alignment. Channel abbreviation and stamp-all change
--  glyph widths, so a display copy that differed from Blizzard's stored line
--  would desync its invisible hyperlink hit-zones from our rendered text.
--  The engine therefore writes the FINAL display form of every transformed
--  line back into the frame's historyBuffer entry (EngineTail live, the
--  rebuild pass retroactively): both surfaces lay out identical text,
--  Blizzard's native secure zones land exactly on what the user sees, and
--  link interaction -- clicks, tooltips, protected-content handling, secret
--  links -- is Blizzard's own end to end. Secret lines are never compared or
--  rewritten; they stay untransformed on BOTH surfaces and remain aligned by
--  construction (class-colored names insert only zero-width color codes, so
--  they ride the same write-back without affecting zone geometry).
--  The write is a plain value into Blizzard's stored entry, so the secure
--  readers of that storage (censored-line re-format, history machinery)
--  read an addon-written string; if secure-reader taint ever surfaces, the
--  two write-back sites (tail + rebuild) are the single mechanism to pull.
-------------------------------------------------------------------------------
local _abbrevOn = false     -- Shortened Channel Names user setting
local _stampAllOn = false   -- Timestamp All Messages user setting (resolved)
local _stampFmt = nil       -- its resolved format string
local _protActive = false   -- protected content / dev mode: transforms dormant

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
    -- underneath receives the wheel natively and serves every hyperlink from
    -- its own zones (the buffer write-back keeps them under our rendered
    -- lines); the scroll-method mirrors installed with the bridge copy its
    -- offset into this view.
    smf:EnableMouse(false)
    smf:EnableMouseWheel(false)

    local win = { cf = cf, smf = smf }

    -- +4: renders above every Blizzard frame in the panel stack (cf at
    -- bg+1, its FontStringContainer at bg+2). Mouse-transparent, so the
    -- altitude never affects input routing.
    smf:SetFrameLevel(d.bg:GetFrameLevel() + 4)

    win.extraLines = 0
    WINS[cf] = win
    BuildScrollbar(win)
    smf:SetOnScrollChangedCallback(function() UpdateScrollbar(win) end)
    smf:AddOnDisplayRefreshedCallback(function() UpdateScrollbar(win) end)
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
-- Line spacing, per alphabet. Blizzard's chat family (ChatFontNormal ->
-- NumberFont_Shadow_Med) pads its korean member with spacing="3" and gives
-- the other alphabets none: hangul fills the line box top to bottom, so
-- without that pad the log packs tight -- the "spacing got tighter" half of
-- the koKR report that produced CJKHeight. CreateFontFamilyMemberInfo has no
-- spacing field, so it goes on the member object after creation.
local CJK_SPACING = { korean = 3 }
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
        -- Client's own CJK alphabet uses the chosen font, not the stock
        -- file, since most chat text renders through it. Other CJK
        -- alphabets keep the stock file as a tofu fallback.
        for alphabet, file in pairs(CJK_FILES) do
            local memberFile = (alphabet == CJK_CLIENT_ALPHABET) and font or file
            members[#members + 1] = { alphabet = alphabet, file = memberFile, height = CJKHeight(alphabet, size), flags = flags }
        end
        local ok, created = pcall(CreateFontFamily, "EUIChatFontFamily" .. id, members)
        if not ok or not created then FAMS[id] = false; return nil end
        FAMS[id] = created
        fam = created
    end
    local ok = pcall(function()
        fam:GetFontObjectForAlphabet("roman"):SetFont(font, size, flags)
        fam:GetFontObjectForAlphabet("russian"):SetFont(font, size, flags)
        for alphabet, file in pairs(CJK_FILES) do
            local memberFile = (alphabet == CJK_CLIENT_ALPHABET) and font or file
            local member = fam:GetFontObjectForAlphabet(alphabet)
            member:SetFont(memberFile, CJKHeight(alphabet, size), flags)
            member:SetSpacing(CJK_SPACING[alphabet] or 0)
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
--  Shortened channel names (opt-in). The transform composes OUR display
--  copy; the zone-alignment write-back then lands the identical form in
--  Blizzard's stored entry, so its invisible hit-zones lay out the same
--  shortened text within lines and across wraps. (A field-replaced
--  cf.AddMessage remains the taint class this engine exists to eliminate --
--  the write-back rewrites a stored VALUE after the secure handler has
--  fully run, never the handler chain itself; rewriting the CHAT_*_GET
--  globals stays field-proven poison.) Matching is on the channel hyperlink
--  KEYWORD (|Hchannel:party|h[...]|h), locale-independent, plain substring
--  scanning. Secret lines pass through whole.
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

function ECHAT.EngineSetChannelAbbrev(on)
    _abbrevOn = on == true
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
--  abbreviations; the zone-alignment write-back then lands the identical
--  form in Blizzard's stored entry.
--  Secret lines pass through whole (concat on secrets errors; those are
--  player messages, which Blizzard already stamps). Session history composes
--  cleanly: its capture stripper removes ANY leading stamp (ours or baked)
--  and replay re-derives the prefix from the stored serverTime.
-------------------------------------------------------------------------------
function ECHAT.EngineSetStampAll(on, fmt)
    if on == true and type(fmt) == "string" and fmt ~= "" then
        _stampAllOn, _stampFmt = true, fmt
    else
        _stampAllOn, _stampFmt = false, nil
    end
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
    -- Dormant in protected content, same as the abbreviations: secret lines
    -- can never be rewritten into the buffer, so the transforms stand down
    -- whole and both surfaces stay raw-aligned.
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
    -- Zone-alignment write-back (doctrine block above the transform section).
    -- Secrecy gate FIRST: comparing two secret strings throws, so display~=msg
    -- may only run once msg is known plain. The e.message==msg identity check
    -- skips entries another addon already rewrote, and skipping display==msg
    -- keeps this a true no-op (zero writes) when every transform is off or
    -- dormant (_protActive), preserving the zero-cost-disabled posture.
    if not (issecretvalue and issecretvalue(msg))
        and type(display) == "string" and display ~= msg then
        local hb = cf.historyBuffer
        local e = hb and hb.GetEntryAtIndex and hb:GetEntryAtIndex(1)
        if e and type(e.message) == "string"
            and not (issecretvalue and issecretvalue(e.message))
            and e.message == msg then
            e.message = display
        end
    end
    if win then
        win.smf:AddMessage(display, r, g, b, chatTypeID, ExtractLineID(eventArgs), event)
        -- Scrolled-view DOUBLE-PIN fix (field report 2026-08-16: "chat moves
        -- one line on a new message while scrolled, every zone off by one
        -- message after"): SMF:AddMessage auto-pins a scrolled view via an
        -- INTERNAL ScrollUp (Blizzard source, ScrollingMessageFrame.lua:12).
        -- cf's internal ScrollUp fires the scroll mirror mid-add (our offset
        -- = cf's pinned offset), and our own AddMessage above then auto-pins
        -- AGAIN -- one line past cf, visible text drifting off Blizzard's
        -- invisible interaction zones until the next wheel step re-mirrors.
        -- cf's offset is the scroll authority at every add: re-copy it after
        -- our add. No-op at bottom (0 == 0) and SetScrollOffset early-outs
        -- when equal, so the settled path stays zero-write.
        win.smf:SetScrollOffset(cf:GetScrollOffset())
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
    -- Blizzard's scroll methods are the single wheel authority: lockstep
    -- with its view IS the zone alignment. Replayed session-history rows sit
    -- above its range, so the wheel stops at its clamp -- the thin scrollbar
    -- (which drives our view directly) is the lane that reaches them.
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

-- Blizzard opens a new permanent window (ChatFrameUtil.PopOutChat) or a
-- temporary whisper window by taking one it considers unopened and seeding it
-- from the source frame inside its own copy loop: GetMessageInfo, compare the
-- line's accessID, AddMessage, next line. An AddMessage hook taints the rest of
-- that loop, so the NEXT GetMessageInfo answers with a secret accessID and the
-- compare throws (ChatFrameUtil.lua:711) with the pop-out half done. Unopened
-- frames therefore stay unbridged; the first integrate pass after Blizzard
-- opens one installs the bridge and backfills our window from its buffer.
local function IsChatFrameOpen(cf)
    if cf.isTemporary then return cf.inUse == true end
    local id = cf:GetID()
    return id > 0 and FCF_IsChatWindowIndexActive(id)
end

local function InstallBridge(cf)
    local d = CFD(cf)
    if d.bridged then return false end
    if not IsChatFrameOpen(cf) then return false end
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
    return true
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
    -- server time; missing internals just skip the stamp for that line. The
    -- buffer handle is fetched regardless of stamping because the rebuild is
    -- also the CONVERGENCE pass: any line this loop transforms must land
    -- identically in Blizzard's stored entry or its native zones would drift
    -- from our text (lines received while transforms were dormant in
    -- protected content converge here on the first rebuild after the flip
    -- out). Same gate order as the live tail: secrecy before any compare.
    local hb = cf.historyBuffer
    if not (hb and hb.GetEntryAtIndex and hb.GetNumElements) then hb = nil end
    local nowT, nowG
    if _stampAllOn and not _protActive then
        nowT, nowG = time(), GetTime()
    end
    for i = 1, n do
        local msg, r, g, b, chatTypeID, accessID, typeID, event, eventArgs = cf:GetMessageInfo(i)
        if msg ~= nil then
            local display = DisplayText(msg, event)
            local entry = hb and hb:GetEntryAtIndex(hb:GetNumElements() - i + 1)
            if nowT then
                local ts = entry and entry.timestamp
                if type(ts) == "number" then
                    display = StampDisplay(display, nowT - (nowG - ts))
                end
            end
            if entry and not (issecretvalue and issecretvalue(msg))
                and type(display) == "string" and display ~= msg
                and type(entry.message) == "string"
                and not (issecretvalue and issecretvalue(entry.message))
                and entry.message == msg then
                entry.message = display
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
    -- A frame bridged only now was opened since the last pass (a pop-out, a
    -- reused temporary window): its lines were copied in behind our back. The
    -- empty check keeps a late bridge on a window we already render (session
    -- history replayed into it) from wiping what only exists on our side.
    if InstallBridge(cf) and win.smf:GetNumMessages() == 0 then
        RebuildWindowFromBuffer(cf)
        return
    end
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
        end
    else
        if fsc then fsc:SetAlpha(0) end
        if bar then
            if bar.Track then bar.Track:SetAlpha(0) end
            SetBarMouse(bar, false)
        end
        if win then
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

-- Protected-content master switch for the width transforms. While
-- _protActive, DisplayText/StampDisplay go dormant, so new lines land raw
-- on BOTH surfaces (secret lines could never be rewritten anyway) and stay
-- aligned by construction; already-transformed scrollback keeps its display
-- form on both sides because rebuilds read the converged buffer back. The
-- flip-out rebuild is the convergence pass that retroactively transforms
-- lines received while dormant. No-op while the state is unchanged, so the
-- PEW edge and the per-message probe cost one comparison.
EngineUpdateProtectedState = function()
    local prot = (EUI.InProtectedInstance and EUI.InProtectedInstance()) and true or false
    if prot == _protActive then return end
    _protActive = prot
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

-- Backfilled lines have no matching entry in the real chat frame, so a
-- click on one can't resolve to a real hyperlink target. Strip link escape
-- codes down to plain text to avoid handing a bad link to the click handler.
local function StripHyperlinks(text)
    if type(text) ~= "string" then return text end
    return text:gsub("|H.-|h(.-)|h", "%1")
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
    local display = StripHyperlinks(DisplayText(text))
    win.smf:BackFillMessage(display, r, g, b, id)
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
        else
            if win.pmWasShown then
                win.pmWasShown = nil
                win.smf:Show()
            end
            UpdateScrollbar(win)
        end
    end
end
