if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Chat_Init.lua
--
--  The tab refresh shim and the PLAYER_LOGIN pass that skins the frames and
--  starts the watchers.
--  Reads the earlier Chat files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- EllesmereUIChat.lua or an earlier EUI_Chat_*.lua file failed to load.
if not I or I.broken then return end
I.broken = true

local EUI = _G.EllesmereUI
local ECHAT = ns.ECHAT
local max = max

local CFD, EnsureDB, GetFont = I.CFD, I.EnsureDB, I.GetFont
local GetFrameFontSize, GetIdleFadeAlpha = I.GetFrameFontSize, I.GetIdleFadeAlpha
local GetOutlineFlag, RequestPassthroughSweep = I.GetOutlineFlag, I.RequestPassthroughSweep
local ContainsURL, WrapURLs, _skinned = I.ContainsURL, I.WrapURLs, I._skinned
local CHAT_MSG_EVENTS, SkinChatFrame = I.CHAT_MSG_EVENTS, I.SkinChatFrame
local SetBgR, SetBgG, SetBgB, SetBgA = I.SetBgR, I.SetBgG, I.SetBgB, I.SetBgA
local SetIdleFadeActive = I.SetIdleFadeActive

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._internals, which hands the value to every copy.
local BG_R = I.BG_R
I.bgRSetters[#I.bgRSetters + 1] = function(v) BG_R = v end
local BG_G = I.BG_G
I.bgGSetters[#I.bgGSetters + 1] = function(v) BG_G = v end
local BG_B = I.BG_B
I.bgBSetters[#I.bgBSetters + 1] = function(v) BG_B = v end
local BG_A = I.BG_A
I.bgASetters[#I.bgASetters + 1] = function(v) BG_A = v end
local _visChatVisible = I._visChatVisible
I.visChatVisibleSetters[#I.visChatVisibleSetters + 1] = function(v) _visChatVisible = v end
local _idleFadeActive = I._idleFadeActive
I.idleFadeActiveSetters[#I.idleFadeActiveSetters + 1] = function(v) _idleFadeActive = v end

-------------------------------------------------------------------------------
--  Tab refresh shim: the owned strip (EllesmereUIChat_Tabs.lua) redraws from
--  a coalesced deferred pass; this also re-hides anything of Blizzard's tab
--  plane that its own event passes re-showed.
-------------------------------------------------------------------------------
local function UpdateTabColors()
    if ECHAT.TabsSweepBlizzard then ECHAT.TabsSweepBlizzard() end
    if ECHAT.TabsRefresh then ECHAT.TabsRefresh() end
end

-------------------------------------------------------------------------------
--  Initialization (PLAYER_LOGIN)
-------------------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    EnsureDB()

    ---------------------------------------------------------------------------
    --  1. Load saved background color/opacity before skinning any frames
    ---------------------------------------------------------------------------
    local p = ECHAT.DB()
    SetBgR(p.bgR or BG_R)
    SetBgG(p.bgG or BG_G)
    SetBgB(p.bgB or BG_B)
    SetBgA(p.bgAlpha or BG_A)

    ---------------------------------------------------------------------------
    --  2. Skin all 20 chat frames (bg, tabs, edit box, etc.), then bring them
    --     under the display engine: font providers first, then integration
    --     (Blizzard text suppressed, AddMessage bridge installed, our windows
    --     built and backfilled with everything already in Blizzard's buffers).
    ---------------------------------------------------------------------------
    for i = 1, 20 do
        local cf = _G["ChatFrame" .. i]
        if cf then SkinChatFrame(cf) end
    end
    ECHAT.EngineFontProvider = GetFont
    ECHAT.EngineFontSizeProvider = GetFrameFontSize
    ECHAT.EngineOutlineProvider = GetOutlineFlag
    -- Seed the display-transform switches BEFORE integration: the install
    -- backfill renders through the same transforms as live lines.
    if ECHAT.EngineSetChannelAbbrev then
        ECHAT.EngineSetChannelAbbrev(p.abbreviateChannels == true)
    end
    if ECHAT.EngineSetChannelAbbrevLetters then
        ECHAT.EngineSetChannelAbbrevLetters(p.abbreviateChannelLetters == true)
    end
    if p.classColorNames == true then
        ECHAT.ApplyClassColorNames(true)
    end
    if ECHAT.EngineIntegrateAll then ECHAT.EngineIntegrateAll() end
    -- Owned tab strip: hides Blizzard's strip, builds ours from the same
    -- window storage, and starts mirroring selection/flash from the engine.
    if ECHAT.TabsInit then ECHAT.TabsInit() end
    -- Re-run the background pass so a saved Background Texture applies at login
    -- (the skin loop creates the bg textures with the solid color).
    ECHAT.ApplyBackground()
    ---------------------------------------------------------------------------
    --  2b. NEVER replace the global CHAT_FONT_HEIGHTS to expand font sizes:
    --      every read becomes tainted, and Blizzard's tab context menu
    --      iterates it mid-build, so the whole menu -- every click handler
    --      wired after that read -- runs tainted, and any item touching a
    --      whisper window's secret-keyed tables errors
    --      (FCF_RestoreChatsToFrame forbidden-table iteration). EUI font size
    --      is applied at skin time instead.
    ---------------------------------------------------------------------------


    ---------------------------------------------------------------------------
    --  2c. Clickable URLs via message event filters
    ---------------------------------------------------------------------------
    local URL_EVENTS = {
        "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
        "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID",
        "CHAT_MSG_RAID_LEADER", "CHAT_MSG_INSTANCE_CHAT",
        "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_WHISPER",
        "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER",
        "CHAT_MSG_BN_WHISPER_INFORM", "CHAT_MSG_CHANNEL",
    }
    local function UrlFilter(self, event, msg, ...)
        if not msg or not ContainsURL(msg) then return false end
        return false, WrapURLs(msg), ...
    end
    for _, ev in ipairs(URL_EVENTS) do
        ChatFrame_AddMessageEventFilter(ev, UrlFilter)
    end

    ---------------------------------------------------------------------------
    --  3. Temporary window (whisper) detection.
    ---------------------------------------------------------------------------
    -- Shared skin pass: skins unskinned frames, re-strips tabs, re-applies font,
    -- hides Blizzard chrome. Driven by whisper events and the state watcher --
    -- never by a hooksecurefunc on FCF_OpenTemporaryWindow, which taints edit
    -- box header arithmetic during window creation.
    local function SkinPass()
        local wantFont = GetFont()
        local wantOutline = GetOutlineFlag()
        for i = 1, 20 do
            local cf = _G["ChatFrame" .. i]
            -- New frames (SkinChatFrame handles the panel + edit box)
            if cf and not _skinned[cf] then
                SkinChatFrame(cf)
            end
            -- Re-apply font if Blizzard reset it (e.g. font size change).
            -- Family form, not raw SetFont: a raw write here would detach
            -- the CJK font family the skin pass attached.
            if cf and _skinned[cf] then
                local curFont = cf:GetFont()
                if curFont and curFont ~= wantFont then
                    -- Size from Blizzard's stored per-window setting, NEVER read
                    -- back off the widget: under a font family cf:GetFont()
                    -- answers for the ACTIVE alphabet, so on a CJK client it
                    -- returns the CJK member -- a file that never equals
                    -- wantFont, at that member's own height. Feeding it back in
                    -- re-seeded the family from its own output, and this pass
                    -- runs on UPDATE_(FLOATING_)CHAT_WINDOWS, so chat text grew
                    -- on every login, reload and tab switch.
                    local sz = GetFrameFontSize(cf:GetID())
                    local fam = ECHAT.EngineFontFamily
                        and ECHAT.EngineFontFamily(cf:GetID(), wantFont, sz, wantOutline)
                    if fam then
                        cf:SetFontObject(fam)
                    else
                        cf:SetFont(wantFont, sz, wantOutline)
                    end
                end
                -- Blizzard resets this alongside the font/dock passes above;
                -- re-assert every pass rather than gating on a changed-check
                -- (a plain boolean set costs nothing). See SkinChatFrame for
                -- why this must stay congruent with win.smf's own setting.
                cf:SetIndentedWordWrap(true)
            end
        end
        UpdateTabColors()
        ECHAT.ApplyTabLayout()
        if ECHAT.ApplyInputPosition then ECHAT.ApplyInputPosition() end
    end

    ---------------------------------------------------------------------------
    --  4. Chat-frame state watcher, in place of FCF_* hooksecurefunc hooks.
    --  NEVER hooksecurefunc FCFDock_SelectWindow / FCF_Close /
    --  FCF_OpenNewWindow -- deferring the body to C_Timer.After(0) does not
    --  help, since the hook WRAPPER still executes inside the caller's own
    --  execution and taints the rest of that caller. Measured chain: an
    --  FCF_Close hook taints the caller -> a later FCF_DockFrame (or
    --  FCF_CopyChatSettings) reaches FCF_SetLocked, whose `chatFrame.isLocked
    --  = isLocked` write lands under that taint -> the FIELD stays tainted
    --  through every later secure pass (so watching only GLOBALS reads
    --  clean) -> FCF_Tab_SetupMenu reads tabChatFrame.isLocked building the
    --  tab menu, so its closures (incl. "Close Whisper Window") die
    --  iterating the forbidden privateMessageList -> the same field is read
    --  by FCF_UpdateResizeButton during the temp-window OPEN, tainting its
    --  secret whisper-name math too. One field, both error classes. These
    --  hooks only did cosmetic re-assertion, so the same state is watched
    --  instead -- from the interaction follower (armed only while chat is
    --  hovered or Edit Mode is open) and the deferred event passes below:
    --  outside Blizzard's dispatch, zero idle cost, up to one tick latency.
    ---------------------------------------------------------------------------
    -- Likewise NEVER hook FCFTab_UpdateColors or FCFDock_UpdateTabs synchronously:
    -- FCF_OpenTemporaryWindow -> FCF_SetTemporaryWindowType calls FCFTab_UpdateColors
    -- directly and ends with a synchronous FCFDock_UpdateTabs call, so both hook bodies
    -- would execute inside the temp-whisper creation chain, deactivating the new
    -- editBox and running UpdateHeader's width math on the SECRET whisper-name geometry
    -- -- no body shape is safe here. Recolor + layout run DEFERRED from our own
    -- triggers below; the cost is a possible 1-frame Blizzard-styled flash.
    local _tabPassQueued = false
    local function QueueTabPass()
        if _tabPassQueued then return end
        _tabPassQueued = true
        C_Timer.After(0, function()
            _tabPassQueued = false
            UpdateTabColors()
            ECHAT.ApplyTabLayout()
            -- Every restyle trigger is also a moment panel geometry can
            -- shift or the dock selection can have changed; all calls
            -- early-out on clean state, and this deferred body is our own
            -- execution.
            if ECHAT.SyncChatFrameState then ECHAT.SyncChatFrameState() end
            if ECHAT.PositionChatPanelsNow then ECHAT.PositionChatPanelsNow() end
            if ECHAT.EngineUpdateCombatLogHost then ECHAT.EngineUpdateCombatLogHost() end
        end)
    end
    ECHAT.QueueTabPass = QueueTabPass
    -- Full pass: skin new frames, then restyle + state sync. SkinPass ends with
    -- UpdateTabColors/ApplyTabLayout/ApplyInputPosition, so this is the one-stop
    -- deferred handler for anything that can create a chat frame.
    local _fullPassQueued = false
    local function QueueFullPass()
        if _fullPassQueued then return end
        _fullPassQueued = true
        C_Timer.After(0, function()
            _fullPassQueued = false
            SkinPass()
            -- New frames (temp whisper windows, user-created windows) join
            -- the engine here: visual children parked, bridge installed, our
            -- window built and backfilled. Idempotent for known frames.
            if ECHAT.EngineIntegrateAll then ECHAT.EngineIntegrateAll() end
            if ECHAT.SyncChatFrameState then ECHAT.SyncChatFrameState() end
            if ECHAT.PositionChatPanelsNow then ECHAT.PositionChatPanelsNow() end
            -- A re-skin resets the resize button's base alpha; re-assert the
            -- lock state over it.
            if ECHAT.ApplyLockChatSize then ECHAT.ApplyLockChatSize() end
            -- A frame integrated while the panel is fully hidden must join
            -- the passthrough set.
            RequestPassthroughSweep()
            -- A window created while the house editor is open is born on the
            -- hidden UIParent; seat it with the rest of the panel.
            ECHAT.ApplyPanelHost()
        end)
    end
    ECHAT.QueueFullPass = QueueFullPass
    -- Every moment Blizzard resets our styling (login passes, zone transitions, dock
    -- config loads) coincides with these events on our own frame -- outside Blizzard's
    -- dispatch, deferred one tick. Also covers user-created permanent windows
    -- (UPDATE_CHAT_WINDOWS) and repositions panels after scale changes.
    local tabPassFrame = CreateFrame("Frame")
    tabPassFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    tabPassFrame:RegisterEvent("UPDATE_CHAT_WINDOWS")
    tabPassFrame:RegisterEvent("UPDATE_FLOATING_CHAT_WINDOWS")
    tabPassFrame:RegisterEvent("UI_SCALE_CHANGED")
    tabPassFrame:RegisterEvent("DISPLAY_SIZE_CHANGED")
    tabPassFrame:SetScript("OnEvent", QueueFullPass)
    -- Edit Mode can rebuild the chat dock and tab geometry after a panel resize.
    -- Re-assert tab appearance only once that update has left Blizzard's
    -- event/script stack; the short second pass covers the final size commit
    -- performed while Edit Mode closes.
    do
        local editModeStyleGeneration = 0
        local function QueueEditModeTabStyle()
            editModeStyleGeneration = editModeStyleGeneration + 1
            local generation = editModeStyleGeneration
            QueueTabPass()
            C_Timer.After(0.10, function()
                if generation == editModeStyleGeneration then QueueTabPass() end
            end)
        end
        local editModeStyleFrame = CreateFrame("Frame")
        editModeStyleFrame:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
        editModeStyleFrame:SetScript("OnEvent", function()
            C_Timer.After(0, QueueEditModeTabStyle)
        end)
        if EditModeManagerFrame then
            -- Arm the follower for the whole Edit Mode session: chat can be
            -- dragged/resized with the mouse nowhere near our hover widgets
            -- (the Selection overlay occludes them).
            EditModeManagerFrame:HookScript("OnShow", function()
                if ECHAT.FollowArmEditMode then ECHAT.FollowArmEditMode(true) end
            end)
            EditModeManagerFrame:HookScript("OnHide", function()
                if ECHAT.FollowArmEditMode then ECHAT.FollowArmEditMode(false) end
                C_Timer.After(0, QueueEditModeTabStyle)
            end)
        end
    end

    -- House editor open/close: reseat the panel onto Blizzard's full-screen host
    -- (see ApplyPanelHost). Our own event frame, deferred a tick so the reseat
    -- runs after HouseEditorFrame's show/hide has set the full-screen frame --
    -- never an EventRegistry callback or a hook, both of which would run our
    -- body inside Blizzard's own execution.
    if C_HouseEditor and C_HouseEditor.IsHouseEditorActive then
        local houseEditorFrame = CreateFrame("Frame")
        houseEditorFrame:RegisterEvent("HOUSE_EDITOR_MODE_CHANGED")
        houseEditorFrame:SetScript("OnEvent", function()
            C_Timer.After(0, ECHAT.ApplyPanelHost)
        end)
    end
    -- Tab close is covered by the state watcher above. NEVER hook FCF_Close:
    -- "top-level user action" is the wrong test -- it is also reached from
    -- FCF_PopInWindow (the tab menu's own Close button) and dock teardown, and even
    -- a genuine top-level click's hook taints the REST of the caller, which is what
    -- poisons ChatFrame*.isLocked. Temp window creation: NEVER
    -- hooksecurefunc("FCF_OpenTemporaryWindow") either -- the secure whisper router
    -- calls it mid-function and continues to DeactivateChat -> UpdateHeader, whose
    -- width math runs on the SECRET whisper name geometry; our hook in the chain
    -- taints the remainder of the caller and blocks that arithmetic. Instead the
    -- same whisper events are registered on our own frame (standalone C-side
    -- dispatch, outside Blizzard's execution, taint-free) and the skin is deferred.
    -- That covers every temp-window trigger: incoming whisper and outgoing /w in
    -- popout mode (WHISPER_INFORM).
    do
        local tempWinFrame = CreateFrame("Frame")
        tempWinFrame:RegisterEvent("CHAT_MSG_WHISPER")
        tempWinFrame:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
        tempWinFrame:RegisterEvent("CHAT_MSG_BN_WHISPER")
        tempWinFrame:RegisterEvent("CHAT_MSG_BN_WHISPER_INFORM")
        tempWinFrame:SetScript("OnEvent", QueueFullPass)
    end
    -- User-created permanent chat windows are covered by the full pass on
    -- UPDATE_CHAT_WINDOWS -- NO hooksecurefunc on FCF_OpenNewWindow: it is
    -- created from the same tab menu whose closures must stay untainted.

    -- One extra strip pass once the loading screen drops: Blizzard's final
    -- login dock update can re-show pieces of its (hidden) tab plane.
    do
        local pinFrame = CreateFrame("Frame")
        pinFrame:RegisterEvent("LOADING_SCREEN_DISABLED")
        pinFrame:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            UpdateTabColors()
            ECHAT.ApplyTabLayout()
            -- Chat position ownership begins at the first settled sight:
            -- capture Edit Mode's placement as ours if unsaved, arm the
            -- anchor guard, kill the Edit Mode selection overlay, apply.
            if ns._CaptureChatPositionGenesis then ns._CaptureChatPositionGenesis() end
            if ns._GenesisSettle then ns._GenesisSettle() end
            if ns._InstallChatAnchorGuard then ns._InstallChatAnchorGuard() end
            if ECHAT.SuppressChatEditModeSelection then ECHAT.SuppressChatEditModeSelection() end
            if ECHAT.ApplyChatPosition then ECHAT.ApplyChatPosition() end
            -- Font size follows the profile: capture on first sight,
            -- re-assert on every later login.
            if ECHAT.SyncChatFontSize then ECHAT.SyncChatFontSize() end
            -- (ApplyChatPosition self-resyncs panels+strip one tick later,
            -- and the EDIT_MODE_LAYOUTS_UPDATED watcher re-asserts if Edit
            -- Mode's late layout apply lands after this.)
            -- Post-login heal window: Edit Mode's last write can land through
            -- paths none of the event answers see, leaving chat at EM's rect
            -- (short by the tab area) until the first hover armed the
            -- follower's drift heal. Run the state sync -- which carries that
            -- heal -- on a short bounded cadence instead, then self-destruct.
            local healTicks = 0
            local healFrame = CreateFrame("Frame")
            local healAccum = 0
            healFrame:SetScript("OnUpdate", function(w, dt)
                healAccum = healAccum + dt
                if healAccum < 0.1 then return end
                healAccum = 0
                healTicks = healTicks + 1
                if ECHAT.SyncChatFrameState then ECHAT.SyncChatFrameState() end
                if healTicks >= 40 then w:SetScript("OnUpdate", nil) end
            end)
        end)
    end

    ---------------------------------------------------------------------------
    --  5. Tab color management. The deferred update batches multiple tab
    --     changes into one pass.
    ---------------------------------------------------------------------------
    -- Blizzard performs additional dock sizing after the initial chat setup, so
    -- text-derived widths are re-applied across a few deferred passes and saved
    -- Inner Padding X is correct without requiring a tab click.
    local function ApplyInitialTabLayout()
        UpdateTabColors()
        ECHAT.ApplyTabLayout()
    end
    C_Timer.After(0, ApplyInitialTabLayout)
    C_Timer.After(0.10, ApplyInitialTabLayout)
    C_Timer.After(0.50, ApplyInitialTabLayout)
    local _tabColorTimer
    local function DeferredTabColorUpdate()
        if _tabColorTimer then return end
        _tabColorTimer = true
        C_Timer.After(0, function()
            _tabColorTimer = nil
            UpdateTabColors()
            ECHAT.ApplyTabLayout()
        end)
    end
    ECHAT._deferredTabColorUpdate = DeferredTabColorUpdate


    ---------------------------------------------------------------------------
    --  6. Idle fade: dims chat after N seconds of inactivity. Resets on player
    --     chat in a shown window (the selected tab or an undocked window), an
    --     incoming whisper, edit box focus/typing, or the cursor entering the
    --     chat area (event-driven, no polling).
    ---------------------------------------------------------------------------
    do
        local idleTimer = nil
        -- Hover state (UpdateHoverState below); read by OnActiveMessage.
        local _idleMouseOver = false
        local SetMessageWake  -- with OnActiveMessage below

        local function IsIdleApplicable()
            local cfg = ECHAT.DB()
            local vis = cfg.visibility or "always"
            return vis ~= "never"
        end

        local function StartIdleFade()
            if ECHAT.DB().idleFadeEnabled == false then return end
            if _idleFadeActive then return end
            SetIdleFadeActive(true)
            ECHAT.SetIdleFadeAlpha(GetIdleFadeAlpha())
            -- Faded: arm the hover-reveal motion overlay.

            if ECHAT.ApplyIdleFadeHoverMotion then ECHAT.ApplyIdleFadeHoverMotion() end
        end

        local function CancelIdleFade()
            local wasActive = _idleFadeActive
            SetIdleFadeActive(false)
            if idleTimer then
                idleTimer:Cancel()
                idleTimer = nil
            end
            if _visChatVisible then
                ECHAT.SetIdleFadeAlpha(1)
            end
            -- Visible again: the overlay goes inert so the panel area is
            -- click- and camera-transparent like the default UI.
            if wasActive and ECHAT.ApplyIdleFadeHoverMotion then
                ECHAT.ApplyIdleFadeHoverMotion()
            end
        end

        function ECHAT.ResetIdleTimer()
            CancelIdleFade()
            local cfg = ECHAT.DB()
            local on = IsIdleApplicable() and cfg.idleFadeEnabled ~= false
            -- Chat lines wake the fade only while it can run: nothing per line otherwise.
            SetMessageWake(on)
            if not on then return end
            local delay = cfg.idleFadeDelay or 15
            idleTimer = C_Timer.NewTimer(delay, StartIdleFade)
        end

        -- Idle reset throttle: max once per second.
        local _lastIdleReset = 0
        local function OnActiveMessage()
            -- (No passthrough sweep needed on messages anymore: Blizzard's
            -- line pool is parked in the engine's hidden container, and OUR
            -- message frames are hidden outright while passthrough is
            -- engaged -- a hidden frame arms nothing.)
            if not IsIdleApplicable() then return end
            local now = GetTime()
            if now - _lastIdleReset < 1 then return end
            _lastIdleReset = now
            if _idleMouseOver then
                CancelIdleFade()
            else
                ECHAT.ResetIdleTimer()
            end
        end

        -- Chat lines: the display engine's tail sees each line in the window
        -- Blizzard put it in, after its own channel, message-group and filter
        -- checks, so player chat (CHAT_MSG_EVENTS) wakes the fade only when
        -- that window is shown. Inside Blizzard's chat handler the observer
        -- only reads and shows a frame of ours; the reset runs on its next
        -- OnUpdate, outside that handler.
        local wakeFrame = CreateFrame("Frame")
        wakeFrame:Hide()
        wakeFrame:SetScript("OnUpdate", function(self)
            self:Hide()
            OnActiveMessage()
        end)
        local function WakeOnChat(cf, event)
            if event == nil or wakeFrame:IsShown() then return end
            if issecretvalue and issecretvalue(event) then return end
            if CHAT_MSG_EVENTS[event] and cf:IsShown() then wakeFrame:Show() end
        end
        SetMessageWake = function(on)
            if ECHAT.EngineSetIdleObserver then
                ECHAT.EngineSetIdleObserver(on and WakeOnChat or nil)
            end
        end

        -- Permanent docked frames only (1-10): hooking a temp whisper edit box
        -- (11+) taints its execution context and poisons HistoryKeeper on
        -- BN_WHISPER. OnChar, not OnTextChanged: OnChar means "the user typed",
        -- and the engine never dispatches it from SetText, including the
        -- SetText("") inside Deactivate that writes chatType in the same
        -- execution. The trade is that OnChar misses backspace, paste and some
        -- IME paths, so composing by paste then pausing can fade chat mid-edit;
        -- any committed character un-fades it.
        ECHAT._RegisterEditBoxFocusGained("EUI_Chat_IdleFade", function()
            OnActiveMessage()
        end)
        for i = 1, 10 do
            local eb = _G["ChatFrame" .. i .. "EditBox"]
            if eb then
                eb:HookScript("OnChar", function(...)
                    OnActiveMessage(...)
                end)
            end
        end

        ---------------------------------------------------------------------------
        --  7. Whisper sound alert (also resets idle fade for incoming
        --     whispers). Driven by a standalone EVENT FRAME, not a message
        --     filter: Blizzard wraps every filter in
        --     `if canaccessvalue(...) then callback(...) end`
        --     (ChatFrameFilters.lua), so a message carrying ANY value the
        --     addon cannot access -- the secret sender on every BN whisper --
        --     skips the filter entirely, even one that reads no arguments.
        --     Event registration on our own frame is outside Blizzard's
        --     dispatch and carries no taint.
        ---------------------------------------------------------------------------
        do
            local WHISPER_SOUND_PATHS, WHISPER_SOUND_NAMES, WHISPER_SOUND_ORDER =
                EllesmereUI.BuildAlertSoundTables()
            ECHAT.WHISPER_SOUND_PATHS = WHISPER_SOUND_PATHS
            ECHAT.WHISPER_SOUND_NAMES = WHISPER_SOUND_NAMES
            ECHAT.WHISPER_SOUND_ORDER = WHISPER_SOUND_ORDER

            -- "none" (the stored default) keeps Blizzard's own whisper sound;
            -- "mute" silences it and plays nothing; any sound replaces it.
            WHISPER_SOUND_NAMES.none = "Blizzard Default"
            WHISPER_SOUND_NAMES.mute = "None"
            table.insert(WHISPER_SOUND_ORDER, 2, "mute")

            -- Append SharedMedia sounds
            EllesmereUI.AppendSharedMediaSounds(
                WHISPER_SOUND_PATHS,
                WHISPER_SOUND_NAMES,
                WHISPER_SOUND_ORDER
            )

            -- Blizzard's whisper sound (SOUNDKIT.TELL_MESSAGE plays this one
            -- file), muted while a non-default choice is set. A mute outlives
            -- /reload and relog (not a client restart), so the account-wide
            -- chatTellMuted flag remembers that the mute is ours: a character
            -- on Blizzard Default unmutes only a mute we made, never another
            -- addon's. Runs at init, from the setting and from
            -- _ECHAT_RefreshAll (profile swaps, imports, spec overrides).
            local TELL_SOUND_FILE = 567421
            local _tellMuted = false
            function ECHAT.ApplyWhisperMute()
                if not MuteSoundFile then return end
                local cfg = ECHAT.DB()
                local key = cfg and cfg.whisperSoundKey
                local want = key ~= nil and key ~= "none"
                local db = EllesmereUIDB
                if want then
                    if not _tellMuted then
                        MuteSoundFile(TELL_SOUND_FILE)
                        _tellMuted = true
                        if db then db.chatTellMuted = true end
                    end
                elseif _tellMuted or (db and db.chatTellMuted) then
                    UnmuteSoundFile(TELL_SOUND_FILE)
                    _tellMuted = false
                    if db then db.chatTellMuted = nil end
                end
            end
            ECHAT.ApplyWhisperMute()
            -- Uninstall EUI: a mute of ours would outlive the reload.
            EllesmereUI.OnUninstall(function()
                if _tellMuted or (EllesmereUIDB and EllesmereUIDB.chatTellMuted) then
                    UnmuteSoundFile(TELL_SOUND_FILE)
                    _tellMuted = false
                    if EllesmereUIDB then EllesmereUIDB.chatTellMuted = nil end
                end
            end)

            local _whisperThrottle = 0
            local whisperFrame = CreateFrame("Frame")
            whisperFrame:RegisterEvent("CHAT_MSG_WHISPER")
            whisperFrame:RegisterEvent("CHAT_MSG_BN_WHISPER")
            whisperFrame:SetScript("OnEvent", function()
                OnActiveMessage()
                local cfg = ECHAT.DB()
                local key = cfg and cfg.whisperSoundKey
                if not key or key == "none" or key == "mute" then return end
                local now = GetTime()
                if now - _whisperThrottle < 5 then return end
                _whisperThrottle = now
                local path = WHISPER_SOUND_PATHS[key]
                if path then PlaySoundFile(path, "Master") end
            end)
        end

        -- Event-driven hover detection: zero CPU when idle. Uses
        -- EnableMouseMotion on our bg frames + HookScript on tabs.
        -- EnableMouseMotion captures hover without blocking clicks but does
        -- block camera turning -- accepted trade-off for zero-poll.
        local _hoverCount = 0
        local _editFocusCount = 0

        local function UpdateHoverState()
            local over = (_hoverCount > 0) or (_editFocusCount > 0)
            if not IsIdleApplicable() then return end
            if over and not _idleMouseOver then
                _idleMouseOver = true
                CancelIdleFade()
            elseif not over and (_idleMouseOver or not (idleTimer or _idleFadeActive)) then
                -- Also re-arm when nothing is armed: a hover that began while
                -- faded is cleared by the reveal (ApplyIdleFadeHoverMotion),
                -- so its leave would otherwise find no edge and no timer.
                _idleMouseOver = false
                ECHAT.ResetIdleTimer()
            end
        end

        -- Single invisible overlay covering tabs + bg + sidebar, at BACKGROUND strata.
        -- Its mouse motion is conditional -- see ApplyIdleFadeHoverMotion below.
        do
            local cf1 = _G.ChatFrame1
            local gdm = _G.GeneralDockManager
            local bg1 = CFD(cf1).bg
            local sb = CFD(cf1).sidebar
            if bg1 and gdm then
                local overlay = CreateFrame("Frame", nil, UIParent)
                ns._chatHoverOverlay = overlay
                overlay:SetPoint("TOPLEFT", gdm, "TOPLEFT", sb and -40 or 0, 0)
                overlay:SetPoint("BOTTOMRIGHT", bg1, "BOTTOMRIGHT", 0, 0)
                overlay:SetFrameStrata("BACKGROUND")
                overlay:EnableMouse(false)
                -- Peek reveal: motion is live ONLY while idle-faded (see
                -- ApplyIdleFadeHoverMotion), so an enter here can only mean
                -- the user moused over the faded chat. No OnLeave needed --
                -- the reveal itself turns motion back off.
                overlay:SetScript("OnEnter", function()
                    if _idleFadeActive and ECHAT.ResetIdleTimer then
                        ECHAT.ResetIdleTimer()
                    end
                end)
                -- Motion capture is needed ONLY while the chat is idle-faded (to catch
                -- the reveal hover). While visible the overlay must be inert so clicks
                -- AND camera drags over the panel reach the world exactly like the
                -- default UI (EnableMouseMotion intercepts right-drag camera input even
                -- though it passes clicks). Passthrough (full hide) keeps it inert too.
                function ECHAT.ApplyIdleFadeHoverMotion()
                    local cfg = ECHAT.DB()
                    local on = cfg.idleFadeEnabled ~= false
                        and (cfg.visibility or "always") ~= "never"
                        and ns._chatPassthrough ~= true
                        and _idleFadeActive
                    -- Per-channel setters, and click pinned OFF every pass:
                    -- EnableMouseMotion toggling alone leaves the click
                    -- channel armed, which made this overlay an invisible
                    -- click-catcher over the VISIBLE chat -- clicks and
                    -- camera dead, undetectable by motion-based probes.
                    if overlay.SetMouseClickEnabled then
                        overlay:SetMouseClickEnabled(false)
                    end
                    if overlay.SetMouseMotionEnabled then
                        overlay:SetMouseMotionEnabled(on)
                    else
                        overlay:EnableMouseMotion(on)
                    end
                    if not on then
                        _hoverCount = 0
                        _idleMouseOver = false
                    end
                end
                ECHAT.ApplyIdleFadeHoverMotion()
            end
        end

        -- Sidebar has EnableMouse(true) which blocks the overlay beneath it.
        -- HookScript on our own frame -- safe, no taint.
        local sidebar = CFD(ChatFrame1).sidebar
        if sidebar then
            sidebar:HookScript("OnEnter", function()
                _hoverCount = _hoverCount + 1; UpdateHoverState()
                if ECHAT.FollowArm then ECHAT.FollowArm() end
            end)
            sidebar:HookScript("OnLeave", function()
                _hoverCount = max(0, _hoverCount - 1); UpdateHoverState()
                if ECHAT.FollowRelease then ECHAT.FollowRelease() end
            end)
        end

        -- Edit box focus tracking -- only ChatFrame1 (permanent, no secret
        -- values). Hooking temp whisper edit boxes (11+) taints their
        -- execution context, causing secret value errors on BN_WHISPER tellTarget.
        local eb1 = _G["ChatFrame1EditBox"]
        if eb1 then
            -- Neither side can be a HookScript: GAINED is dispatched by the
            -- SetFocus() inside ChatFrameUtil.ActivateChat, which then writes
            -- chatType in UpdateHeader(), and LOST runs on into DeactivateChat
            -- -> Deactivate, which writes it after its own dispatches. Blizzard
            -- triggers both callbacks from the first line of the matching
            -- handler, so the timing is unchanged and the counter still pairs
            -- exactly.
            ECHAT._RegisterEditBoxFocusGained("EUI_Chat_HoverEditFocus", function(eb)
                if eb ~= eb1 then return end
                _editFocusCount = _editFocusCount + 1
                UpdateHoverState()
            end)
            if EventRegistry and EventRegistry.RegisterCallback then
                EventRegistry:RegisterCallback("ChatFrame.OnEditBoxFocusLost",
                    function(_, eb)
                        if eb ~= eb1 then return end
                        _editFocusCount = max(0, _editFocusCount - 1)
                        UpdateHoverState()
                    end, "EUI_Chat_HoverEditFocus")
            end
        end

        -- Start the initial timer
        ECHAT.ResetIdleTimer()
    end

    ---------------------------------------------------------------------------
    --  7. Accent color + timestamps
    ---------------------------------------------------------------------------
    EUI.RegAccent({ type = "callback", fn = UpdateTabColors })

    -- Enable scroll-to-scroll chat (Blizzard disables by default)
    EllesmereUI.SetCVar("chatMouseScroll", 1, "EllesmereUIChat")

    -- Seed the engine's stamp-all transform with the RESOLVED format:
    -- explicit formats pass through, "__blizzard" resolves to Blizzard's own
    -- setting, "none" (either source) disarms it.
    local function ApplyStampAll()
        if not ECHAT.EngineSetStampAll then return end
        local cfg = ECHAT.DB()
        local fmt = cfg.timestampFormat or "%I:%M "
        if fmt == "none" then
            fmt = nil
        elseif fmt == "__blizzard" then
            local ok, f = pcall(function()
                return ChatFrameUtil and ChatFrameUtil.GetTimestampFormat and ChatFrameUtil.GetTimestampFormat()
            end)
            fmt = (ok and type(f) == "string" and f ~= "" and f ~= "none") and f or nil
        end
        ECHAT.EngineSetStampAll(cfg.timestampAll == true and fmt ~= nil, fmt)
    end
    ECHAT.ApplyStampAll = ApplyStampAll

    local function ApplyTimestampCVar()
        ApplyStampAll()
        local cfg = ECHAT.DB()
        local fmt = cfg.timestampFormat or "%I:%M "
        if fmt == "__blizzard" then return end
        EllesmereUI.SetCVar("showTimestamps", fmt, "EllesmereUIChat")
    end
    ApplyTimestampCVar()
    C_Timer.After(2, ApplyTimestampCVar)
    ECHAT.ApplyTimestampCVar = ApplyTimestampCVar

    ---------------------------------------------------------------------------
    --  8. Apply all visual settings from DB
    ---------------------------------------------------------------------------
    ECHAT.ApplySidebarVisibility()
    -- ApplyBorders is DEFERRED out of the PLAYER_LOGIN execution: running it
    -- synchronously here chains into ApplyExtendedBackground, which plants the panel
    -- border's anchors in ChatFrame1's rect web WHILE Blizzard's login dock pass is
    -- still resolving layout -- that pass then reads our insecure anchors, runs
    -- tainted, and its persistent dock state poisons every later temp-whisper open
    -- (FCFManager_GetChatTarget/ GetDecoratedSenderName secret errors). The deferred
    -- tab passes (PEW + C_Timer) are the proven-clean home for this work instead.
    do
        local bordersDefer = CreateFrame("Frame")
        bordersDefer:RegisterEvent("PLAYER_ENTERING_WORLD")
        bordersDefer:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            C_Timer.After(0, function()
                ECHAT.ApplyBorders()
                -- Stock styles: the Blizzard chat art re-seat rides the same
                -- deferred cadence (see SeatStockBackground); later windows
                -- are seated by the state sync. Not under WoW Forever: its
                -- input box is placed like the EllesmereUI look's.
                if ns.ChatStockArt() then
                    ECHAT._stockSeatArmed = true
                    for i = 1, 20 do
                        local cf = _G["ChatFrame" .. i]
                        if cf then ECHAT.SeatStockBackground(cf) end
                    end
                end
                -- The stored window colour, re-read once settled.
                if ECHAT.SB_SyncBackdrop then ECHAT.SB_SyncBackdrop(true) end
            end)
        end)
    end
    -- ECHAT.ApplySidebarIcons() -- causes taint (full layout chain)
    -- Apply individual icon visibility from DB without the layout chain.
    do
        local _cfg = ECHAT.DB()
        local _cf1 = _G.ChatFrame1
        if _cfg and _cf1 then
            local _sbd = CFD(_cf1)
            if _sbd.scrollBtn then _sbd.scrollBtn:SetShown(_cfg.showScroll ~= false) end
            if _sbd.friendsBtn then _sbd.friendsBtn:SetShown(_cfg.showFriends ~= false) end
            if _sbd.durabilityBtn then _sbd.durabilityBtn:SetShown(_cfg.showDurability ~= false) end
            if _sbd.copyBtn then _sbd.copyBtn:SetShown(_cfg.showCopy ~= false) end
            if _sbd.portalBtn then _sbd.portalBtn:SetShown(_cfg.showPortals ~= false) end
            if _sbd.voiceBtn then _sbd.voiceBtn:SetShown(_cfg.showVoice ~= false) end
            if _sbd.chatMenuBtn then _sbd.chatMenuBtn:SetShown(_cfg.showChatMenu ~= false) end
            if _sbd.settingsBtn then _sbd.settingsBtn:SetShown(_cfg.showSettings ~= false) end
        end
    end
    ECHAT.ApplySidebarWidth()
    ECHAT.ApplySidebarPosition()
    ECHAT.ApplyIconColor()
    ECHAT.ApplyInputPosition()
    ECHAT.ApplySidebarBackground()
    ECHAT.ApplySidebarIconScale()
    ECHAT.ApplyIconFreeMove()
    ECHAT.ApplyLockChatSize()

    -- Profile-swap refresh: re-apply all chat visuals from the (already- swapped) DB --
    -- ECHAT.DB() reads the live profile dynamically, so re-running the Apply functions
    -- pulls the new profile's settings. ApplySidebarIcons() is deliberately NOT called
    -- here -- its full ClearAllPoints/SetPoint layout chain is taint-risky (skipped at
    -- init too); icon visibility uses the same minimal SetShown block as init, and
    -- position/scale/free-move are covered by the Apply* calls below.
    _G._ECHAT_RefreshAll = function()
        ECHAT.ApplySidebarVisibility()
        ECHAT.ApplyBorders()
        do
            local _cfg = ECHAT.DB()
            local _cf1 = _G.ChatFrame1
            if _cfg and _cf1 then
                local _sbd = CFD(_cf1)
                if _sbd.scrollBtn then _sbd.scrollBtn:SetShown(_cfg.showScroll ~= false) end
                if _sbd.friendsBtn then _sbd.friendsBtn:SetShown(_cfg.showFriends ~= false) end
                if _sbd.durabilityBtn then _sbd.durabilityBtn:SetShown(_cfg.showDurability ~= false) end
                if _sbd.copyBtn then _sbd.copyBtn:SetShown(_cfg.showCopy ~= false) end
                if _sbd.portalBtn then _sbd.portalBtn:SetShown(_cfg.showPortals ~= false) end
                if _sbd.voiceBtn then _sbd.voiceBtn:SetShown(_cfg.showVoice ~= false) end
                if _sbd.chatMenuBtn then _sbd.chatMenuBtn:SetShown(_cfg.showChatMenu ~= false) end
                if _sbd.settingsBtn then _sbd.settingsBtn:SetShown(_cfg.showSettings ~= false) end
            end
        end
        ECHAT.ApplySidebarWidth()
        ECHAT.ApplySidebarPosition()
        ECHAT.ApplyIconColor()
        ECHAT.ApplyInputPosition()
        ECHAT.ApplySidebarBackground()
        ECHAT.ApplySidebarIconScale()
        ECHAT.ApplyIconFreeMove()
        ECHAT.ApplyLockChatSize()
        ECHAT.ApplyBackground()
        ECHAT.ApplyFonts()
        if ECHAT.RefreshVisibility then ECHAT.RefreshVisibility() end
        -- The new profile's idle fade settings (and whether chat lines wake it).
        if ECHAT.ResetIdleTimer then ECHAT.ResetIdleTimer() end
        -- The passes above can build panel chrome (borders, the tab-band
        -- extension) that did not exist when the house editor opened.
        ECHAT.ApplyPanelHost()
        ECHAT.ApplyWhisperMute()
    end

    ---------------------------------------------------------------------------
    --  9-12. Chat positioning: OURS via the unlock element.
    ---------------------------------------------------------------------------
    --[[ Chat position is OURS (unlock element + genesis capture + anchor
    -- guard). HARD CONSTRAINTS from the failed first attempt, still binding:
    -- ChatFrame1 is NEVER reparented (Edit Mode's UpdateSystemAnchorInfo
    -- assumes a UIParent child; a reparented chat came back with NO anchors
    -- -- unmovable, unresizable) and its SetPoint is NEVER hooked. Position
    -- enforcement is ONLY the deferred ApplySystemAnchor post-hook; the Edit
    -- Mode Selection overlay is suppressed IN PLACE (alpha + mouse), never
    -- reparented -- Edit Mode still drives that region. Chat SIZE stays
    -- Blizzard's (the resize grip). ]]

    ---------------------------------------------------------------------------
    --  12b. BNet Toast notification -- position via unlock mode
    ---------------------------------------------------------------------------
    do
        local toast = _G.BNToastFrame
        if toast then
            -- Apply saved position or default to bottom-right of chat bg
            local function ApplyToastPosition()
                local cfg = ECHAT.DB()
                if not cfg or not cfg.toastPosition then return end
                local pos = cfg.toastPosition
                if not pos.point then return end
                local px, py = pos.x or 0, pos.y or 0
                local PPa = EUI and EUI.PP
                if PPa and PPa.SnapForES then
                    local es = toast:GetEffectiveScale()
                    px = PPa.SnapForES(px, es)
                    py = PPa.SnapForES(py, es)
                end
                toast:ClearAllPoints()
                toast:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, px, py)
            end

            -- Enforce saved position when Blizzard tries to reposition; skip
            -- during unlock mode so the user can drag freely. NOT
            -- hooksecurefunc(toast, "SetPoint", ...): that form assigns
            -- toast.SetPoint = wrapper, a FIELD WRITE onto BNToastFrame's
            -- table (same hazard as the edit box in SkinEditBox). Blizzard reads that
            -- field whenever it anchors the toast, so the tainted read lands inside the
            -- Battle.net toast chain -- the same chain that opens a BN whisper and puts
            -- a SECRET target name into ChatFrame1EditBox.text. OnShow is a script hook
            -- (C-side, no field write) and fires on every toast, the only moment the
            -- position matters; the deferred call lets Blizzard finish its own
            -- anchoring first. Same shape as the FCFDock_SelectWindow hook this module
            -- already replaced for taint reasons.
            toast:HookScript("OnShow", function()
                if EUI._unlockActive then return end
                local cfg = ECHAT.DB()
                if not (cfg and cfg.toastPosition) then return end
                C_Timer.After(0, function()
                    if EUI._unlockActive then return end
                    local c = ECHAT.DB()
                    if c and c.toastPosition then ApplyToastPosition() end
                end)
            end)

            -- Apply saved position or set default (above chat frame)
            C_Timer.After(0, function()
                local cfg = ECHAT.DB()
                if cfg and not cfg.toastPosition then
                    -- Default: anchor to top of chat bg
                    local cf1bg = _G.ChatFrame1 and CFD(_G.ChatFrame1).bg
                    if cf1bg then
                        toast:ClearAllPoints()
                        toast:SetPoint("BOTTOMLEFT", cf1bg, "TOPLEFT", 0, 30)
                        -- Snapshot the absolute position
                        local es = toast:GetEffectiveScale()
                        local uiS = UIParent:GetEffectiveScale()
                        local cx, cy = toast:GetCenter()
                        local uCX, uCY = UIParent:GetCenter()
                        if cx and uCX then
                            cfg.toastPosition = {
                                point = "CENTER", relPoint = "CENTER",
                                x = (cx * es - uCX * uiS) / uiS,
                                y = (cy * es - uCY * uiS) / uiS,
                            }
                        end
                    end
                end
                ApplyToastPosition()
            end)

            -- Register with unlock mode
            if EUI.RegisterUnlockElements then
                local MK = EUI.MakeUnlockElement
                EUI:RegisterUnlockElements({
                    MK({
                        key   = "ECHAT_BNToast",
                        label = "BNet Toast",
                        group = "Chat",
                        order = 601,
                        noAnchorTo = true,
                        noResize   = true,
                        getFrame = function() return toast end,
                        getSize  = function()
                            return toast:GetWidth(), toast:GetHeight()
                        end,
                        isHidden = function() return false end,
                        savePos = function(_, point, relPoint, x, y)
                            local cfg = ECHAT.DB()
                            if not cfg then return end
                            cfg.toastPosition = { point = point, relPoint = relPoint or point, x = x, y = y }
                            if not EUI._unlockActive then
                                ApplyToastPosition()
                            end
                        end,
                        loadPos = function()
                            local cfg = ECHAT.DB()
                            if not cfg then return nil end
                            return cfg.toastPosition
                        end,
                        clearPos = function()
                            local cfg = ECHAT.DB()
                            if not cfg then return end
                            cfg.toastPosition = nil
                        end,
                        applyPos = function()
                            ApplyToastPosition()
                        end,
                    }),
                })
            end
        end
    end

    ---------------------------------------------------------------------------
    --  12c. Main chat: a REAL unlock element. Drag saves cfg.chatPosition;
    --       everything downstream (panels, our text, the ghost tab strip)
    --       follows ChatFrame1 through the existing numeric machinery.
    ---------------------------------------------------------------------------
    if EUI.RegisterUnlockElements then
        local MK = EUI.MakeUnlockElement
        EUI:RegisterUnlockElements({
            MK({
                key   = "ECHAT_MainChat",
                label = "Chat",
                group = "Chat",
                order = 600,
                noResize = true,
                -- Chat alone places ChatFrame1 from its saved spot (Edit Mode
                -- applies its own on every layout apply): an anchor link would be
                -- a third owner, and a link saved before (the old WoW Forever base
                -- layout made one) kept dragging chat back to its stale spot.
                ownsPosition = true,
                getFrame = function() return _G.ChatFrame1 end,
                getSize  = function()
                    local cf1 = _G.ChatFrame1
                    return cf1:GetWidth(), cf1:GetHeight()
                end,
                isHidden = function() return false end,
                -- The mover places ChatFrame1 with one anchor per drag tick /
                -- nudge; our size rides a second corner (SetSize is banned on
                -- the main window), so restore it after every placement.
                onLiveMove = function()
                    if ns._KeepMainChatSizeCorner then ns._KeepMainChatSizeCorner() end
                end,
                savePos = function(_, point, relPoint, x, y)
                    local cfg = ECHAT.DB()
                    if not cfg then return end
                    cfg.chatPosition = { point = point, relPoint = relPoint or point, x = x, y = y }
                    if not EUI._unlockActive then
                        ECHAT.ApplyChatPosition()
                    end
                end,
                loadPos = function()
                    local cfg = ECHAT.DB()
                    return cfg and cfg.chatPosition or nil
                end,
                clearPos = function()
                    -- Back to Edit Mode's default spot and size (the store
                    -- holds ours until reset); the next settled sight
                    -- re-captures that as the new genesis.
                    local cfg = ECHAT.DB()
                    if cfg then
                        cfg.chatPosition = nil
                        cfg.chatSize = nil
                    end
                    if EUI._unlockActive then
                        ns._chatUnlockReset = true
                    else
                        ns.EMChatResetStore()
                    end
                end,
                applyPos = function() ECHAT.ApplyChatPosition() end,
            }),
        })
    end
    -- The geometry follower runs for the whole unlock session so the panel
    -- and text track the Chat mover per-frame instead of snapping after.
    -- Both session edges re-assert the saved rect from the DB: on open, so
    -- the mover measures the true (size-composed) rect even if a one-anchor
    -- placement elsewhere left the frame on its explicit size; on close, so
    -- the committed or reverted position lands composed in the same
    -- execution (the drift heal is suspended for the session and would
    -- otherwise be the first thing to notice, one tick later). The close's
    -- apply hands a committed move to the Edit Mode store (its store pass);
    -- a committed Reset puts Edit Mode's default back (the commit runs
    -- before this edge).
    EUI:RegisterUnlockModeListener("EllesmereUIChat", function(active)
        if ECHAT.FollowArmUnlock then ECHAT.FollowArmUnlock(active) end
        if ECHAT.ApplyChatPosition then ECHAT.ApplyChatPosition() end
        if not active and ns._chatUnlockReset then
            ns._chatUnlockReset = nil
            ns.EMChatResetStore()
        end
    end)

    ---------------------------------------------------------------------------
    --  13. Visibility system registration
    ---------------------------------------------------------------------------
    ECHAT.RefreshVisibility()
    EUI.RegisterVisibilityUpdater(ECHAT.RefreshVisibility)

    ---------------------------------------------------------------------------
    --  14. Hide Blizzard social buttons (quick join, menu, channel, voice)
    ---------------------------------------------------------------------------
    for _, frameName in ipairs({
        "QuickJoinToastButton", "ChatFrameMenuButton", "ChatFrameChannelButton",
        "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton",
    }) do
        local f = _G[frameName]
        if f then f:SetAlpha(0); f:EnableMouse(false) end
    end
    -- Chat Menu: the menu button back over its icon, mouse on while shown.
    ECHAT.SeatChatMenu()

end)

I.broken = false
