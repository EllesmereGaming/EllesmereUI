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
--      their secure scripts, exactly as before this engine existed
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
--  clicks from Blizzard's own secure scripts.
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
    -- No mouse at all -- not even wheel. The bare intrinsic never
    -- dispatches OnMouseWheel (field-measured: topmost, wheel-enabled,
    -- IsMouseOver true, script never fires), so claiming the wheel here
    -- SWALLOWS it. Blizzard's chat frame underneath receives the wheel
    -- natively (modifier semantics, chat CVars, keybinds included) and the
    -- scroll-method mirrors installed with the bridge copy its offset into
    -- this view. Link interaction stays on Blizzard's invisible hit-zones.
    smf:EnableMouse(false)
    smf:EnableMouseWheel(false)

    local win = { cf = cf, smf = smf }

    -- One level above the chat frame (panel sits one below it), so the wheel
    -- deterministically reaches OUR view; the sync handler then drives
    -- Blizzard's view to the same offset.
    smf:SetFrameLevel(d.bg:GetFrameLevel() + 2)

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
        -- smaller (dense glyphs, no ascender/descender whitespace).
        for alphabet, file in pairs(CJK_FILES) do
            members[#members + 1] = { alphabet = alphabet, file = file, height = size + 2, flags = flags }
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
            fam:GetFontObjectForAlphabet(alphabet):SetFont(file, size + 2, flags)
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

-------------------------------------------------------------------------------
--  Shortened channel names (opt-in). The transform runs on OUR display copy
--  only -- Blizzard's stored line is never touched (the live-tree wrapper
--  that replaced cf.AddMessage is the field-replace taint class this engine
--  exists to eliminate, and rewriting the CHAT_*_GET globals is the other
--  field-proven poison). Matching is on the channel hyperlink KEYWORD
--  (|Hchannel:party|h[...]|h), locale-independent, plain substring scanning.
--  Secret lines pass through whole. Known cosmetic cost: shortened lines can
--  wrap differently than Blizzard's invisible hit-zone text, so link zones
--  in scrolled-back content may sit a row off for such lines.
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

local _abbrevOn = false
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
    if _abbrevOn and msg:find("|Hchannel:", 1, true) then
        msg = AbbreviateChannelText(msg)
    end
    if _ccnOn and event ~= nil
        and not (issecretvalue and issecretvalue(event))
        and CCN_EVENTS[event] then
        msg = ColorRosterNames(msg)
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
    local win = WINS[cf]
    local display = DisplayText(msg, event)
    if win then
        win.smf:AddMessage(display, r, g, b, chatTypeID, ExtractLineID(eventArgs), event)
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
    for i = 1, n do
        local msg, r, g, b, chatTypeID, accessID, typeID, event, eventArgs = cf:GetMessageInfo(i)
        if msg ~= nil then
            smf:AddMessage(DisplayText(msg, event), r, g, b, chatTypeID, ExtractLineID(eventArgs), event)
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
        if win then win.smf:Hide() end
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

mirrorFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "UPDATE_CHAT_COLOR" then
        local chatType, r, g, b = ...
        if type(chatType) == "string" then
            RecolorOurWindows(chatType, r, g, b)
            if strupper(chatType) == "WHISPER" then
                RecolorOurWindows("REPLY", r, g, b)
            end
        end
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
        else
            if win.pmWasShown then
                win.pmWasShown = nil
                win.smf:Show()
            end
            UpdateScrollbar(win)
        end
    end
end
