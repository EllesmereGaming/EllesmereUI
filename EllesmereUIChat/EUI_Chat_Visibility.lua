if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Chat_Visibility.lua
--
--  The fade: the alpha cache, mouse passthrough at full hide, the fade
--  driver and the visibility rules.
--  Reads the earlier Chat files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- EllesmereUIChat.lua or an earlier EUI_Chat_*.lua file failed to load.
if not I or I.broken then return end
I.broken = true

local EUI = _G.EllesmereUI
local ECHAT = ns.ECHAT
local min, max = min, max

local _chatFadeFrame, CFD, FADE_IN_DURATION = I._chatFadeFrame, I.CFD, I.FADE_IN_DURATION
local FADE_OUT_DURATION, GetIdleFadeAlpha = I.FADE_OUT_DURATION, I.GetIdleFadeAlpha
local IDLE_FADE_OUT_DURATION = I.IDLE_FADE_OUT_DURATION
local SetChatAlphaCurrent, SetVisChatVisible = I.SetChatAlphaCurrent, I.SetVisChatVisible

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._internals, which hands the value to every copy.
local _sidebarFadeAlpha = I._sidebarFadeAlpha
I.sidebarFadeAlphaSetters[#I.sidebarFadeAlphaSetters + 1] = function(v) _sidebarFadeAlpha = v end
local _chatAlphaCurrent = I._chatAlphaCurrent
I.chatAlphaCurrentSetters[#I.chatAlphaCurrentSetters + 1] = function(v) _chatAlphaCurrent = v end

-- Unified fade system: all alpha changes go through a target + lerp.
local _visChatVisible = true
I.visChatVisibleSetters[#I.visChatVisibleSetters + 1] = function(v) _visChatVisible = v end
local _idleFadeActive = false
I.idleFadeActiveSetters[#I.idleFadeActiveSetters + 1] = function(v) _idleFadeActive = v end
local _chatAlphaTarget = 1
local _visAlpha = 1

-- Frame cache for _ApplyAlpha, so the fade loop does no repeated _G lookups.
local _alphaFrames
-- EUI_Chat_Skin.lua drops the cache through this when it skins a frame.
local function SetAlphaFrames(v) _alphaFrames = v end
-- A live sidebar visibility change must refresh the cached sidebar mode, or
-- the fade keeps writing the old mode's alpha (a painted sidebar comes back).
-- Updated in place: this runs on every passthrough exit, and nothing else in
-- the cache depends on the mode.
function ECHAT.InvalidateAlphaCache()
    if not _alphaFrames then return end
    local cfg = ECHAT.DB()
    _alphaFrames._sidebarMode = cfg and cfg.sidebarVisibility or "always"
end
local function _BuildAlphaCache()
    _alphaFrames = {}
    for i = 1, 20 do
        local cf = _G["ChatFrame" .. i]
        local cfd = cf and CFD(cf)
        if cf and cfd.bg then
            _alphaFrames[#_alphaFrames + 1] = {
                cf = cf,
                eb = _G["ChatFrame" .. i .. "EditBox"],
                bg = cfd.bg,
                resizeGrip = cfd.resizeGrip,
            }
        end
    end
    local cf1 = _G.ChatFrame1
    _alphaFrames._sidebar = cf1 and CFD(cf1).sidebar
    local cfg = ECHAT.DB()
    _alphaFrames._sidebarMode = cfg and cfg.sidebarVisibility or "always"
    -- A chat-anchored scroll button does not inherit the sidebar alpha.
    if cfg and cfg.scrollButtonOnChat and cf1 then
        _alphaFrames._chatScrollBtn = CFD(cf1).scrollBtn
    end
end


-- Full-hide mouse passthrough. At effective alpha 0 every mouse surface over the panel
-- is released so clicks and camera drags reach the world. Two regimes: idle fade at
-- strength 100 keeps frames shown (a fade must render) and disables both mouse channels
-- on chat frames 1-10 plus their edit boxes, scroll bars, static tabs,
-- FontStringContainers and line-pool children (temp windows/dynamic tabs untouched),
-- plus our grips/sidebar/overlay -- hover- wake comes from the geometric poll below.
-- Visibility-hidden (never/combat rules) also Hide()s the stack via SetChatStackShown,
-- the only state the engine cannot route input to. Original states are captured in the
-- CFD side table and restored exactly the moment any fade-in begins (new message,
-- Enter, visibility change).
local _chatPassthrough = false

-- Capture-then-disable / exact-restore for BOTH mouse channels: clicks (EnableMouse)
-- and motion (EnableMouseMotion -- blocks camera right-drag). States live in the CFD
-- side table under `key` and `key .. "M"`, so we only ever re-enable what we ourselves
-- disabled. Channels are read/written SEPARATELY: EnableMouse/IsMouseEnabled are
-- COMBINED-channel APIs, chat widgets run split states (click-only line frames,
-- motion-only containers), and a combined restore flips the wrong channel -- e.g.
-- re-arming clicks on a natively motion-only frame after one passthrough cycle.
local function GetMouseChannels(f)
    local click
    if f.IsMouseClickEnabled then click = f:IsMouseClickEnabled()
    else click = f:IsMouseEnabled() end
    if issecretvalue and issecretvalue(click) then click = false end
    local motion = f.IsMouseMotionEnabled and f:IsMouseMotionEnabled()
    if issecretvalue and issecretvalue(motion) then motion = false end
    return click and true or false, motion and true or false
end
-- Forward declaration: the write helpers below arm it when a lockdown-
-- blocked write is skipped; defined after SetChatStackShown.
local ArmChatPMRegen

-- Delta-gated and lockdown-contained. Reads first and writes only real
-- changes, so the assert-every-sweep passes cost no protected calls while
-- the state already matches (a REAL drift -- Blizzard re-arming click on
-- its widgets -- is still a delta and still writes). Chat frames turn
-- PROTECTED while a temporary whisper window exists, and a blocked mouse
-- write used to throw out of the middle of a passthrough transition,
-- stranding the state machine half-engaged (field: chat frozen / tabs dead
-- after combat with Out of Combat visibility). Protection is not reliably
-- queryable up front, so under lockdown each remaining write runs through
-- pcall -- the refusal itself is the detection -- and the function returns
-- false so the caller arms the regen re-apply. Out of combat every write
-- is direct, exactly as before.
local function SetMouseChannels(f, click, motion)
    click = click and true or false
    motion = motion and true or false
    local curClick, curMotion = GetMouseChannels(f)
    local ok = true
    if curClick ~= click then
        local fn = f.SetMouseClickEnabled or f.EnableMouse
        if InCombatLockdown() then
            if not pcall(fn, f, click) then ok = false end
        else
            fn(f, click)
        end
    end
    if curMotion ~= motion then
        local fn = f.SetMouseMotionEnabled or f.EnableMouseMotion
        if fn then
            if InCombatLockdown() then
                if not pcall(fn, f, motion) then ok = false end
            else
                fn(f, motion)
            end
        end
    end
    return ok
end

local function PMOff(d, key, f)
    if not f then return end
    -- Capture on first sight only, but ASSERT the disable every sweep:
    -- Blizzard's message pipeline re-enables click on chat widgets while we
    -- are engaged, and a skipped re-disable leaves an invisible click zombie.
    if d[key] == nil then
        local click, motion = GetMouseChannels(f)
        d[key] = click
        d[key .. "M"] = motion
    end
    if not SetMouseChannels(f, false, false) then ArmChatPMRegen() end
end
local function PMOn(d, key, f)
    if f and d[key] ~= nil then
        if not SetMouseChannels(f, d[key], d[key .. "M"]) then
            -- Keep the capture: the regen re-apply restores from it.
            ArmChatPMRegen()
            return
        end
    end
    d[key] = nil
    d[key .. "M"] = nil
end

-- The SMF's per-line hit-test frames are children of FontStringContainer
-- (Blizzard's line pool) and each carries its own mouse state, so toggling
-- the container alone does not release them. ONE bounded generation -- direct
-- children only, NEVER recursive -- with per-child state captured on first
-- sight in a weak side store and restored exactly from it.
local function PMOffChildren(d, key, parent)
    if not parent then return end
    local store = d[key]
    if not store then store = setmetatable({}, { __mode = "k" }); d[key] = store end
    local kids = { parent:GetChildren() }
    for i = 1, #kids do
        local c = kids[i]
        -- Capture first sight only; assert the disable every sweep -- the SMF
        -- re-enables click on its line frames as messages render, and these
        -- shape the dead zone.
        if not store[c] then
            local click, motion = GetMouseChannels(c)
            store[c] = { click, motion }
        end
        if not SetMouseChannels(c, false, false) then ArmChatPMRegen() end
    end
end
local function PMOnChildren(d, key, parent)
    local store = d[key]
    if not store or not parent then return end
    local kids = { parent:GetChildren() }
    for i = 1, #kids do
        local c = kids[i]
        local st = store[c]
        if st then
            if SetMouseChannels(c, st[1], st[2]) then
                store[c] = nil
            else
                -- Keep the capture for the regen re-apply.
                ArmChatPMRegen()
            end
        end
    end
end

-- Frame-level portion of the full-hide passthrough. OUR message frames are
-- simply hidden for the duration (a hidden frame cannot receive input); the
-- live Blizzard mouse surfaces over the panel -- the edit boxes, the skinned
-- permanent tabs, the dock overflow button, the invisible hyperlink
-- hit-zones in each FontStringContainer, and the chat frame itself -- get
-- the capture-exact PMOff/PMOn treatment.
local function PassthroughFrames(on)
    for i = 1, 10 do
        local cf = _G["ChatFrame" .. i]
        local d = cf and CFD(cf)
        if d and d.bg then
            local eb = _G["ChatFrame" .. i .. "EditBox"]
            if on then
                PMOff(d, "pmCf", cf)
                -- FontStringContainer is a separate mouse surface (hyperlink
                -- hit-testing) not covered by the chat frame's own state; its
                -- line-pool children each carry their own too.
                PMOff(d, "pmFsc", cf.FontStringContainer)
                PMOffChildren(d, "pmFscKids", cf.FontStringContainer)
                PMOff(d, "pmEb", eb)
                PMOff(d, "pmGrip", d.resizeGrip)
            else
                PMOn(d, "pmCf", cf)
                PMOn(d, "pmFsc", cf.FontStringContainer)
                PMOnChildren(d, "pmFscKids", cf.FontStringContainer)
                PMOn(d, "pmEb", eb)
                PMOn(d, "pmGrip", d.resizeGrip)
            end
        end
    end
    -- Blizzard's tabs and dock overflow are hidden wholesale now (owned tab
    -- strip); hidden frames cannot receive input, so no mouse work for them.
    -- Our own surfaces hide outright while passthrough is engaged.
    if ECHAT.EngineSetPassthrough then ECHAT.EngineSetPassthrough(on) end
    if ECHAT.TabsSetPassthrough then ECHAT.TabsSetPassthrough(on) end
end

-- Hover-wake while fully hidden: a passthrough panel cannot receive mouse
-- events, so mouseover reveal at fade strength 100 needs a geometric poll --
-- IsMouseOver() is a pure rect test needing no mouse state. Runs ONLY while
-- idle-fade passthrough is engaged (never for the "never" hard hide, never
-- while visible): one rect test 5x/sec, cancelled the moment chat reveals.
local _ptWakeTicker
local function StopPTWake()
    if _ptWakeTicker then _ptWakeTicker:Cancel(); _ptWakeTicker = nil end
end
local function StartPTWake()
    StopPTWake()
    _ptWakeTicker = C_Timer.NewTicker(0.2, function()
        if not _chatPassthrough or not _idleFadeActive or not _visChatVisible then
            StopPTWake()
            return
        end
        local ov = ns._chatHoverOverlay
        if ov and ov:IsMouseOver() then
            StopPTWake()
            if ECHAT.ResetIdleTimer then ECHAT.ResetIdleTimer() end
        end
    end)
end

-- Hard-hidden visibility states (visibility "never", combat-only modes while
-- out of combat) hide the chat stack OUTRIGHT. Blizzard's chat frames are
-- never touched here: their shown state belongs to FCF (OnShow/OnHide write
-- SetChatWindowShown into config storage), and their visuals are parked in
-- the engine's hidden container regardless. What hides is OUR stack: the
-- panels (our message frames and scrollbars are their children), the dock
-- manager (single remember; nothing of Blizzard's re-shows it), and the
-- module chrome. Shown-state is captured per frame and restored exactly on
-- reveal. Idle fade still uses alpha (a fade must render); this applies only
-- when visibility says hidden.
local _chromeWasShown = setmetatable({}, { __mode = "k" })
local _chromeList = {}

local function SetChatStackShown(shown)
    -- Gate for SyncChatFrameState: the panels' shown-follow must not undo
    -- this hide (the Blizzard frames stay shown, so the follow would).
    ns._chatStackHidden = not shown
    for i = 1, 20 do
        local cf = _G["ChatFrame" .. i]
        local d = cf and CFD(cf)
        if d and d.bg then
            if not shown then
                if d.bg:IsShown() then d.pmWasShown = true; d.bg:Hide() end
            elseif d.pmWasShown then
                d.pmWasShown = nil
                d.bg:Show()
            end
        end
    end
    local gdm = _G.GeneralDockManager
    if gdm then
        -- Show/Hide of an ancestor of a PROTECTED child (a docked temporary
        -- whisper tab in lockdown) is blocked: contain the write and let the
        -- regen re-apply land it. The remember records only what actually
        -- happened.
        if not shown then
            if gdm:IsShown() then
                if not InCombatLockdown() then
                    ns._gdmWasShown = true
                    gdm:Hide()
                elseif pcall(gdm.Hide, gdm) then
                    ns._gdmWasShown = true
                else
                    ArmChatPMRegen()
                end
            end
        elseif ns._gdmWasShown then
            if not InCombatLockdown() then
                ns._gdmWasShown = nil
                gdm:Show()
            elseif pcall(gdm.Show, gdm) then
                ns._gdmWasShown = nil
            else
                ArmChatPMRegen()
            end
        end
    end
    -- Our own chrome hides outright too; the per-frame remember preserves each
    -- applier's shown/hidden decision for the reveal.
    local cf1 = _G.ChatFrame1
    _chromeList[1] = ns._chatPanelBorder
    _chromeList[2] = ns._sidebarSeparateBorder
    _chromeList[3] = ns._chatBgExt
    _chromeList[4] = ns._chatTabStrip
    _chromeList[5] = ns._chatHoverOverlay
    _chromeList[6] = cf1 and CFD(cf1).sidebar or nil
    for i = 1, 6 do
        local f = _chromeList[i]
        if f then
            if not shown then
                if f:IsShown() then _chromeWasShown[f] = true; f:Hide() end
            elseif _chromeWasShown[f] then
                _chromeWasShown[f] = nil
                f:Show()
            end
        end
        _chromeList[i] = nil
    end
end

-- One-shot regen re-apply for lockdown-blocked writes. Re-asserts the
-- CURRENT intended passthrough state whole; the delta gate makes the pass
-- idempotent (everything that already landed is skipped, only the refused
-- writes replay). Fires before the visibility dispatcher's deferred
-- refresh, so a post-combat reveal starts from a clean slate. Runs through
-- the module combat queue: zero idle cost.
local function ChatPMRegenReapply()
    PassthroughFrames(_chatPassthrough)
    if _chatPassthrough and not _visChatVisible then
        SetChatStackShown(false)
    end
end
ArmChatPMRegen = function()
    ns.CombatQueue.Defer("ChatPassthroughReapply", ChatPMRegenReapply)
end

local function SetChatMousePassthrough(on)
    if _chatPassthrough == on then return end
    _chatPassthrough = on
    ns._chatPassthrough = on
    -- Reveal BEFORE the restore pass: TabsSweepBlizzard (run by the tab
    -- restore inside PassthroughFrames) derives its click state from
    -- ns._chatPassthrough OR ns._chatStackHidden. With the stack still
    -- remembered hidden, the restore sweep re-disables the very tabs it is
    -- meant to re-enable, and nothing later re-runs it (field: tabs dead
    -- after combat with in-combat hide once the engage completes cleanly).
    -- The engage direction keeps the reverse order: sweep first (its
    -- passthrough flag alone forces click-off), stack-hide after.
    if not on then SetChatStackShown(true) end
    PassthroughFrames(on)
    if on then
        if not _visChatVisible then SetChatStackShown(false) end
        local cf1 = _G.ChatFrame1
        local sb = cf1 and CFD(cf1).sidebar
        if sb then
            sb:EnableMouse(false)
            if sb.EnableMouseMotion then sb:EnableMouseMotion(false) end
        end
        if ECHAT.ApplySidebarIcons then ECHAT.ApplySidebarIcons() end
        -- _visChatVisible excludes the visibility-hidden regimes, where
        -- hover-wake must not exist.
        if _idleFadeActive and _visChatVisible
            and ECHAT.DB().idleFadeEnabled ~= false then
            StartPTWake()
        end
    else
        StopPTWake()
        -- Our sidebar always runs with motion on (hover fade/reveal); the
        -- mode-specific click state is re-derived by ApplySidebarVisibility.
        local cf1 = _G.ChatFrame1
        local sb = cf1 and CFD(cf1).sidebar
        if sb and sb.EnableMouseMotion then sb:EnableMouseMotion(true) end
        if ECHAT.ApplySidebarVisibility then ECHAT.ApplySidebarVisibility() end
    end
    if ECHAT.ApplyIdleFadeHoverMotion then ECHAT.ApplyIdleFadeHoverMotion() end
end

-- Late joiners while engaged: a frame skinned or integrated during a
-- full-hide (temp whisper window opening mid-hide) must join the passthrough
-- set. One deferred catch-up covers it; nothing re-arms already-treated
-- widgets, so no recurring sweeps exist.
local _ptSweepQueued = false
local function RequestPassthroughSweep()
    if not _chatPassthrough or _ptSweepQueued then return end
    _ptSweepQueued = true
    C_Timer.After(0, function()
        _ptSweepQueued = false
        if not _chatPassthrough then return end
        PassthroughFrames(true)
        if not _visChatVisible then SetChatStackShown(false) end
    end)
end

local function _ApplyAlpha(alpha)
    SetChatAlphaCurrent(alpha)
    SetChatMousePassthrough(alpha <= 0)
    if not _alphaFrames then _BuildAlphaCache() end
    -- Our tab strip (UIParent-parented) fades directly; its buttons inherit.
    if ns._chatTabStrip then ns._chatTabStrip:SetAlpha(alpha) end
    -- Blizzard Style shows Blizzard's real docked tabs: they fade at DOCK
    -- level, the same container-alpha write the tab sweep makes for the
    -- EllesmereUI look (never the per-tab alphas or their globals).
    if ns.ChatBlizzTabs() then
        local gdm = _G.GeneralDockManager
        if gdm then gdm:SetAlpha(alpha) end
    end
    for i = 1, #_alphaFrames do
        local af = _alphaFrames[i]
        local cf = af.cf
        if cf:IsShown() or af.bg:IsShown() then
            cf:SetAlpha(alpha)
            -- The panel is a UIParent child (taint fix) and does not inherit
            -- the chat frame's alpha -- fade it directly.
            af.bg:SetAlpha(alpha)
            local eb = af.eb
            if eb then
                local focused = eb:HasFocus()
                if issecretvalue and issecretvalue(focused) then focused = false end
                if cf.isTemporary or not focused then
                    eb:SetAlpha(alpha)
                end
            end
            if af.resizeGrip then af.resizeGrip:SetAlpha(alpha * 0.4) end
        end
    end
    -- Behind-tabs extension is UIParent-parented: fade it directly.
    if ns._chatBgExt then ns._chatBgExt:SetAlpha(alpha) end
    if ns._chatPanelBorder then ns._chatPanelBorder:SetAlpha(alpha) end
    if ns._sidebarSeparateBorder then
        ns._sidebarSeparateBorder:SetAlpha(min(alpha, _sidebarFadeAlpha))
    end
    -- The panel bottom separator is a texture on bg and inherits the chat frame's alpha
    -- automatically -- no explicit write needed. Sidebar (mode cached at build time)
    local sb = _alphaFrames._sidebar
    if sb then
        local sbMode = _alphaFrames._sidebarMode
        if sbMode == "mouseover" then
            sb:SetAlpha(min(alpha, _sidebarFadeAlpha))
        elseif sbMode ~= "never" then
            sb:SetAlpha(alpha)
        end
    end
    -- Chat-anchored scroll button (UIParent-parented, fades with the panel)
    if _alphaFrames._chatScrollBtn then
        _alphaFrames._chatScrollBtn:SetAlpha(alpha)
    end
end

-- Scroll-to-bottom button seat: sidebar bottom (default) or the chat panel's
-- bottom-right corner. The button is ours, so reparenting is safe.
function ECHAT.ApplyScrollButtonPosition()
    local cf1 = _G.ChatFrame1
    local d = cf1 and CFD(cf1)
    local btn = d and d.scrollBtn
    if not btn then return end
    local cfg = ECHAT.DB()
    -- Seat memo: this runs on every icon-layout pass (including sidebar hover
    -- edges); an unchanged seat needs no re-anchor and no alpha invalidation.
    local seat = cfg.scrollButtonOnChat and "chat" or "sidebar"
    if d.scrollSeat == seat then return end
    d.scrollSeat = seat
    local sb = d.sidebar
    btn:ClearAllPoints()
    if cfg.scrollButtonOnChat and d.bg then
        btn:SetParent(UIParent)
        -- Stock styles: the panel's strata, above Blizzard's revealed chat
        -- background (see SyncChatFrameState).
        btn:SetFrameStrata(ns.ChatStock() and "MEDIUM" or cf1:GetFrameStrata())
        btn:SetFrameLevel(cf1:GetFrameLevel() + 5)
        -- Anchor to the message frame, not bg: the unified bg panel includes the
        -- edit box, so bg's corner sits in the input row. Stock styles: just
        -- inside the revealed art's border (its background corner is +8,-6).
        if ns.ChatStock() then
            btn:SetPoint("BOTTOMRIGHT", cf1, "BOTTOMRIGHT", 4, -2)
        else
            btn:SetPoint("BOTTOMRIGHT", cf1, "BOTTOMRIGHT", 8, -6)
        end
    elseif sb then
        btn:SetParent(sb)
        btn:SetFrameStrata(sb:GetFrameStrata())
        btn:SetFrameLevel(sb:GetFrameLevel() + 1)
        btn:SetPoint("BOTTOM", sb, "BOTTOM", 0, ECHAT.SB_KIT and 0 or 10)
    end
    -- Stock kits: each seat wears the art the stock UI shows there.
    if ECHAT.SB_KIT then
        ECHAT.SB_DressScroll(btn, seat)
        ECHAT.SB_ApplyScale(d, ECHAT.DB().sidebarIconScale or 1, true)
    end
    -- Parent changed: the alpha cache decides whether to fade it directly.
    _alphaFrames = nil
end

-- Animate alpha toward target
local function _SetAlphaTarget(target)
    _chatAlphaTarget = target
    _chatFadeFrame:Show()
end

local _fadeApplyAccum = 0
_chatFadeFrame:SetScript("OnUpdate", function(self, dt)
    if _chatAlphaCurrent == _chatAlphaTarget then
        self:Hide()
        _fadeApplyAccum = 0
        -- The throttle below can swallow the last step of a fade; push the
        -- final value so completion states (especially 0) always land.
        _ApplyAlpha(_chatAlphaCurrent)
        return
    end
    local fadingIn = _chatAlphaTarget > _chatAlphaCurrent
    local duration = fadingIn and FADE_IN_DURATION
        or (_idleFadeActive and IDLE_FADE_OUT_DURATION or FADE_OUT_DURATION)
    local speed = dt / duration
    if fadingIn then
        SetChatAlphaCurrent(min(_chatAlphaTarget, _chatAlphaCurrent + speed))
    else
        SetChatAlphaCurrent(max(_chatAlphaTarget, _chatAlphaCurrent - speed))
    end
    -- The alpha step accumulates every frame but is only pushed to widgets on a
    -- throttle. Still smooth; saves ~75% of SetAlpha calls at 120fps.
    _fadeApplyAccum = _fadeApplyAccum + dt
    if _fadeApplyAccum < 0.016 then return end
    _fadeApplyAccum = 0
    _ApplyAlpha(_chatAlphaCurrent)
    if _chatAlphaCurrent == _chatAlphaTarget then
        self:Hide()
    end
end)

-- Animated alpha for the visibility/mouseover system. Top-level authority:
-- idle fade cannot exceed this.
function ECHAT.SetChatAlpha(alpha)
    _visAlpha = alpha
    SetVisChatVisible(alpha >= 1)
    _SetAlphaTarget(alpha)
end

-- Animated idle-fade alpha, clamped to the visibility alpha
function ECHAT.SetIdleFadeAlpha(alpha)
    _SetAlphaTarget(min(alpha, _visAlpha))
end

-- Re-derive visibility from DB settings (combat, mouseover, always, ...)
function ECHAT.RefreshVisibility()
    local cfg = ECHAT.DB()

    local vis = true
    if EUI and EUI.EvalVisibility then
        vis = EUI.EvalVisibility(cfg)
    end

    local alpha
    if vis == false then
        alpha = 0
    else
        alpha = 1
    end

    if alpha == 1 and _idleFadeActive then
        ECHAT.SetChatAlpha(1)
        ECHAT.SetIdleFadeAlpha(GetIdleFadeAlpha())
    else
        ECHAT.SetChatAlpha(alpha)
    end
end

I._idleFadeActive, I._visChatVisible = _idleFadeActive, _visChatVisible
I.RequestPassthroughSweep, I.SetAlphaFrames = RequestPassthroughSweep, SetAlphaFrames
I.broken = false
