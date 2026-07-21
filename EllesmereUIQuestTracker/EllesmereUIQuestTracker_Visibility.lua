-------------------------------------------------------------------------------
-- EllesmereUIQuestTracker_Visibility.lua
--
-- Visibility and positioning for ObjectiveTrackerFrame.
--
-- Rules that must never be broken:
--   1. Never SetScript on ObjectiveTrackerFrame -- HookScript only.
--   2. Never walk the tracker's children to call EnableMouse. We hide the
--      frame by reparenting the top-level to a hidden container.
--   3. Positioning is delegated to Blizzard's Edit Mode; we provide a
--      ctrl-drag session-only nudge on top, nothing persistent.
-------------------------------------------------------------------------------
local _, ns = ...
local EQT = ns.EQT

-- Hidden reparent target -- NEVER recursed into.
local hiddenFrame = CreateFrame("Frame", "EllesmereUIQTHiddenParent", UIParent)
hiddenFrame:Hide()

local _eqtCollapsed       = false
local _eqtSuppressed      = false

-- Forward-declared so the auto-hide path can toggle BG visibility. The BG
-- is actually created further down (EnsureBG / InitVisibility).
local _bgFrame

local function GetTracker() return _G.ObjectiveTrackerFrame end

-- Shared with EllesmereUIQuestTracker_Skin.lua's TightenTopAnchor: the BG
-- and top accent divider must start at the same Y offset the content's top
-- module is anchored to, otherwise the divider renders inside/below the
-- first block instead of above it. Fallback matches Skin.lua's default.
local function TopGapOffset()
    return EQT.TOP_ANCHOR_OFFSET or -6
end

-------------------------------------------------------------------------------
-- Top-level collapse / expand via SetParent. No child recursion.
-------------------------------------------------------------------------------
local function Collapse()
    local otf = GetTracker()
    if not otf then return end
    if InCombatLockdown() then return end
    if _eqtCollapsed then return end
    _eqtCollapsed = true
    otf:SetParent(hiddenFrame)
end

local function Expand()
    local otf = GetTracker()
    if not otf then return end
    if InCombatLockdown() then return end
    if not _eqtCollapsed then return end
    _eqtCollapsed = false
    otf:SetParent(UIParent)
end

-------------------------------------------------------------------------------
-- Auto-hide: arenas always hide. Raids hide per the "Hide When In Raid"
-- option -- "always" hides for the whole raid, "boss" (default) only hides
-- during an encounter. _inEncounter is driven by ENCOUNTER_START/END below.
-------------------------------------------------------------------------------
local _inEncounter = false
local function ShouldAutoHide()
    local _, instanceType = GetInstanceInfo()
    if instanceType == "arena" then return true end
    if instanceType == "raid" then
        local cfg = EQT.DB()
        if cfg and cfg.hideInRaidMode == "always" then
            return true
        end
        -- Default / "boss": only hide during an encounter.
        return _inEncounter
    end
    return false
end

-- Suspend/resume all QT event frames in raids/arenas/M+. Prevents quest
-- events (QUEST_LOG_UPDATE etc.) from doing skin/resize/classify work when
-- the tracker is hidden anyway. Re-registers on zone-out / unsuppress.
local _eventsSuspended = false
local function SuspendQTEvents()
    if _eventsSuspended then return end
    _eventsSuspended = true
    if EQT._eventFrames then
        for _, f in ipairs(EQT._eventFrames) do
            f:UnregisterAllEvents()
        end
    end
end
local function ResumeQTEvents()
    if not _eventsSuspended then return end
    _eventsSuspended = false
    if EQT._eventFrames and EQT._eventRegistrations then
        for i, f in ipairs(EQT._eventFrames) do
            local evts = EQT._eventRegistrations[i]
            if evts then
                for _, ev in ipairs(evts) do
                    f:RegisterEvent(ev)
                end
            end
        end
    end
end

-- Suppression API (cross-module hide). Routed through UpdateVisibility so
-- suppression composes with the user's chosen visibility mode / options.
function EQT.ApplySuppression(on)
    _eqtSuppressed = on and true or false
    if _eqtSuppressed then
        SuspendQTEvents()
    else
        ResumeQTEvents()
    end
    if EQT.UpdateVisibility then EQT.UpdateVisibility() end
end

-- ObjectiveTrackerFrame is EditMode-managed: Hide()/Show() route through
-- the system template's protected HideBase/ShowBase, so calling either from
-- addon execution during combat is blocked (ADDON_ACTION_BLOCKED) -- and
-- the raid/encounter auto-hide fires exactly at combat start (vehicle boss
-- pulls hit this). In combat fall back to alpha suppression: top-level
-- frame only, never children, never mouse state. The shared visibility
-- dispatcher re-runs UpdateVisibility on PLAYER_REGEN_ENABLED, where the
-- real Hide() lands -- same recovery shape as the M+ timer's HideTracker,
-- minus the private regen listener it needs (we are dispatcher-driven).
local function HardHide(otf)
    if InCombatLockdown() then
        otf:SetAlpha(0)
    else
        otf:SetAlpha(1)  -- clear any combat alpha-suppression before hiding
        otf:Hide()
    end
end

local _showHookInstalled = false
local function InstallShowHook()
    if _showHookInstalled then return end
    local otf = GetTracker()
    if not otf then return end
    _showHookInstalled = true
    -- Raid/arena auto-hide. Runs before other Show hooks (hooksecurefunc
    -- stacks); the M+ timer installs its own similar hook for M+.
    hooksecurefunc(otf, "Show", function(self)
        if _eqtSuppressed then return end
        if ShouldAutoHide() then HardHide(self) end
    end)
    -- BG follows the tracker's actual IsShown() state, regardless of who
    -- hid it (us, M+ timer, Blizzard). OnHide fires after the Hide lands,
    -- OnShow fires after Show lands but the M+ timer's Show-hook re-hides
    -- it synchronously, so by the time OnShow fires the frame may already
    -- be hidden again -- we re-check IsShown().
    otf:HookScript("OnHide", function() if _bgFrame then _bgFrame:Hide() end end)
    otf:HookScript("OnShow", function()
        if _eqtSuppressed then return end
        if EQT.ResizeBGToContent then EQT.ResizeBGToContent() end
        if EQT.QueueResize then EQT.QueueResize() end
    end)
end

local function UpdateVisibility()
    InstallShowHook()
    local otf = GetTracker()
    if not otf then return end

    -- Raid/arena auto-hide takes precedence and uses a hard Hide(); the
    -- Show-hook re-hides if Blizzard tries to bring it back.
    -- Also suspend all QT event frames so quest events don't burn CPU
    -- processing skin/resize/classify work for a hidden tracker.
    if ShouldAutoHide() then
        SuspendQTEvents()
        HardHide(otf)
        if _bgFrame then _bgFrame:Hide() end
        return
    end

    ResumeQTEvents()
    if not otf:IsShown() then
        -- Show() is protected in combat like Hide() (see HardHide). Skip;
        -- the dispatcher's PLAYER_REGEN_ENABLED pass re-runs us and the
        -- real Show() lands then.
        if not InCombatLockdown() then otf:Show() end
    end

    -- User visibility: enabled flag, visibility mode, and the visHide* opts.
    -- EvalVisibility returns true / false / "mouseover".
    local cfg = EQT.DB()
    local vis = true
    if EllesmereUI and EllesmereUI.EvalVisibility then
        vis = EllesmereUI.EvalVisibility(cfg)
    end

    local alpha
    if _eqtSuppressed or vis == false then
        alpha = 0
    elseif vis == "mouseover" then
        -- Mouseover poll raises alpha to 1 on hover.
        alpha = 0
    else
        alpha = 1
    end

    otf:SetAlpha(alpha)
    if _bgFrame then _bgFrame:SetAlpha(alpha) end

    -- Let ResizeBGToContent decide BG shown/hidden based on real content;
    -- an unconditional Show here would resurrect the empty-state BG.
    if EQT.ResizeBGToContent then EQT.ResizeBGToContent() end
end
EQT.UpdateVisibility = UpdateVisibility

-- Kept as a no-op so the options-refresh path that used to trigger a state-
-- driver rebuild doesn't error.
function EQT.RefreshStateDriver() UpdateVisibility() end

-------------------------------------------------------------------------------
-- Entry point
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-- Background frame. Our own UIParent-parented frame anchored to the tracker's
-- bounds. Never a child of ObjectiveTrackerFrame -- keeps us off the secure
-- tree. Color and alpha driven by DB (bgR/G/B/Alpha).
-------------------------------------------------------------------------------
local function EnsureBG()
    if _bgFrame then return _bgFrame end
    local otf = GetTracker()
    if not otf then return nil end
    _bgFrame = CreateFrame("Frame", "EllesmereUIQTBackground", UIParent)
    _bgFrame:SetFrameStrata(otf:GetFrameStrata() or "MEDIUM")
    _bgFrame:SetFrameLevel(math.max(0, otf:GetFrameLevel() - 1))
    -- Start the background at the same Y offset the top module is anchored
    -- to (see TightenTopAnchor in Skin.lua), so it doesn't bleed above the
    -- content or leave a gap below it. Bottom edge extends past the last
    -- block (re-anchored dynamically below).
    local topOfs = TopGapOffset()
    _bgFrame:SetPoint("TOPLEFT", otf, "TOPLEFT", -6, topOfs)
    -- Bottom is re-anchored dynamically in ResizeBGToContent(); this is
    -- only the fallback extent when no content has loaded yet (30px tall).
    _bgFrame:SetPoint("BOTTOMRIGHT", otf, "TOPRIGHT", 11, topOfs - 30)
    local tex = _bgFrame:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints()
    _bgFrame._tex = tex

    -- 1px physical-pixel-perfect accent divider at the very top of the BG
    -- (i.e. at the topOfs cutoff line). Full width of the tracker, anchored
    -- directly to it so the line matches tracker width regardless of BG
    -- padding. Same snap pattern as PP.CreateBorder.
    local divider = _bgFrame:CreateTexture(nil, "OVERLAY")
    divider:SetPoint("TOPLEFT",  otf, "TOPLEFT",  -6, topOfs)
    divider:SetPoint("TOPRIGHT", otf, "TOPRIGHT",  11, topOfs)
    _bgFrame._divider = divider
    return _bgFrame
end

local function ApplyTopDivider()
    local bg = _bgFrame
    if not bg or not bg._divider then return end
    local tex = bg._divider
    if EQT.Cfg("showTopLine") == false then
        tex:Hide()
        return
    end
    local PP_CORE = EllesmereUI and EllesmereUI.PP
    local PP_SEC  = EllesmereUI and EllesmereUI.PanelPP
    if PP_SEC and PP_SEC.DisablePixelSnap then PP_SEC.DisablePixelSnap(tex) end
    local perfect = (PP_CORE and PP_CORE.perfect) or (PP_SEC and PP_SEC.mult) or 1
    local otf = GetTracker()
    local es = (otf and otf.GetEffectiveScale and otf:GetEffectiveScale()) or 1
    local onePixel = (es and es > 0) and (perfect / es) or (PP_SEC and PP_SEC.mult) or 1
    tex:SetHeight(onePixel)
    local eg = EllesmereUI and EllesmereUI.ELLESMERE_GREEN
    local r, g, b = (eg and eg.r) or 0.047, (eg and eg.g) or 0.824, (eg and eg.b) or 0.624
    tex:SetColorTexture(r, g, b, 1)
    tex:Show()
end

-- Find the frame that sits at the absolute bottom of all visible content
-- across every tracker module. Used to anchor the BG's bottom edge.
local function GetLowestContentFrame()
    local otf = GetTracker()
    if not otf then return nil end
    local modules = otf.modules or otf.MODULES
    if not modules then return nil end
    local lowestFrame, lowestY
    local _scenarioTracker = _G.ScenarioObjectiveTracker
    local _widgetTracker = _G.UIWidgetObjectiveTracker
    for _, tracker in ipairs(modules) do
        -- Skip ScenarioObjectiveTracker: its M+ challenge mode blocks
        -- aren't quest content. Showing our bg/top-line around them
        -- during M+ produces visible chrome with no actual quests.
        --
        -- Skip UIWidgetObjectiveTracker: its blocks share Blizzard's widget
        -- pool with tooltip/AreaPOI widgets. ANY method call here (GetBottom,
        -- GetObjectType, IsShown) taints the pool, causing "attempt to compare
        -- a secret number value" in LayoutFrame.lua when GameTooltip later lays
        -- out an AreaPOI widget set. See HookTracker in the Skin module, which
        -- refuses to touch these frames for the same reason.
        if tracker == _scenarioTracker or tracker == _widgetTracker then
            -- skip
        else
        local function consider(frame)
            if not frame or type(frame) ~= "table" then return end
            if not frame.GetBottom or not frame.GetObjectType then return end
            if not (frame.IsShown and frame:IsShown()) then return end
            local ok, otype = pcall(frame.GetObjectType, frame)
            if not ok then return end
            if otype ~= "Frame" and otype ~= "Button" then return end
            local y = frame:GetBottom()
            if y and (not lowestY or y < lowestY) then
                lowestY, lowestFrame = y, frame
            end
        end
        if tracker.usedBlocks then
            for _, v in pairs(tracker.usedBlocks) do
                if type(v) == "table" then
                    if v.GetBottom then
                        consider(v)
                    else
                        for _, block in pairs(v) do consider(block) end
                    end
                end
            end
        end
        -- Only consider the Header as content if the tracker actually has
        -- something to display. Empty trackers leave their Header shown at
        -- stale positions and would otherwise stretch the BG past real
        -- content when a section clears.
        if tracker.hasContents then
            consider(tracker.Header)
        end
        end -- else (skip scenario / widget-pool trackers)
    end
    return lowestFrame
end

-- Event-driven resize with a debounce. Every QueueResize call coalesces
-- into a single deferred ResizeBGToContent pass; bursts of layout events
-- that used to trigger up to 60 frames of per-frame work now fire the
-- resize once per tick. If the measured lowest frame keeps shifting after
-- a resize (e.g. Blizzard's collapse/expand animation), each shift re-
-- queues exactly one more pass -- never a continuous OnUpdate loop.
local _resizePending = false
local function QueueResize()
    if _resizePending then return end
    _resizePending = true
    C_Timer.After(0.05, function()
        _resizePending = false
        if EQT.ResizeBGToContent then EQT.ResizeBGToContent() end
    end)
end
EQT.QueueResize = QueueResize

local function ResizeBGToContent()
    local bg = _bgFrame
    local otf = GetTracker()
    if not bg or not otf then return end
    -- Tracker hidden (e.g. raid/arena auto-hide, Blizzard hide): BG follows.
    if not otf:IsShown() then
        if bg:IsShown() then bg:Hide() end
        return
    end
    -- During active M+ challenge mode, always hide BG. The tracker shows
    -- Blizzard's scenario blocks (objectives/trash count) which aren't
    -- quest content we should decorate. Prevents chrome flashing during
    -- dungeon start/timer transitions.
    if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
       and C_ChallengeMode.IsChallengeModeActive() then
        if bg:IsShown() then bg:Hide() end
        return
    end
    local lowest = GetLowestContentFrame()
    -- Transient "no visible content" states happen for a frame during
    -- track/untrack/collapse/expand while blocks are recycled. Keep the
    -- BG at its last position to avoid a hide/show blink.
    if not lowest then
        if bg._lastLowest then
            -- Had content before -- keep BG visible at last known size.
            -- A deferred check will hide if content truly went away.
            if not bg._hideCheck then
                bg._hideCheck = true
                C_Timer.After(0.2, function()
                    bg._hideCheck = nil
                    if EQT.ResizeBGToContent then EQT.ResizeBGToContent() end
                end)
            end
            return
        end
        -- Never had content: hide.
        if bg:IsShown() then bg:Hide() end
        return
    end
    bg._hideCheck = nil
    if not bg:IsShown() then bg:Show() end
    local topOfs = TopGapOffset()
    local otfTop = otf:GetTop()
    local lowestBottom = lowest:GetBottom()
    if otfTop and lowestBottom then
        local h = otfTop + topOfs - lowestBottom + 15
        if h < 1 then h = 1 end
        bg:ClearAllPoints()
        bg:SetPoint("TOPLEFT",  otf, "TOPLEFT",  -6, topOfs)
        bg:SetPoint("TOPRIGHT", otf, "TOPRIGHT", 11, topOfs)
        bg:SetHeight(h)
        bg._lastHeight = h
    elseif bg._lastHeight then
        bg:ClearAllPoints()
        bg:SetPoint("TOPLEFT",  otf, "TOPLEFT",  -6, topOfs)
        bg:SetPoint("TOPRIGHT", otf, "TOPRIGHT", 11, topOfs)
        bg:SetHeight(bg._lastHeight)
    end
    bg._lastLowest = lowest
end
EQT.ResizeBGToContent = ResizeBGToContent

function EQT.ApplyBackground()
    local bg = EnsureBG()
    if not bg then return end
    local cfg = EQT.DB()
    local r = cfg.bgR or 0
    local g = cfg.bgG or 0
    local b = cfg.bgB or 0
    local a = cfg.bgAlpha or 0.5
    bg._tex:SetColorTexture(r, g, b, a)
    ResizeBGToContent()
    ApplyTopDivider()
end

-- Force Quest Tracker on Screen: when the saved preference is on, keep the
-- ObjectiveTrackerFrame clamped to the screen; otherwise allow it to be dragged
-- off-screen (the default). Applied at load and whenever the options toggle
-- changes. Persists via the quest tracker DB.
function EQT.ApplyForceOnScreen()
    local otf = GetTracker()
    if not otf then return end
    local cfg = EQT.DB()
    local force = cfg and cfg.forceOnScreen == true or false
    otf:SetClampedToScreen(force)
end

function EQT.InitVisibility()
    local otf = GetTracker()
    if not otf then return end

    EnsureBG()
    EQT.ApplyBackground()
    EQT.ApplyForceOnScreen()
    InstallShowHook()

    -- Live-update the top accent divider when the user changes UI Accent Color.
    if EllesmereUI and EllesmereUI.RegAccent then
        EllesmereUI.RegAccent({ type = "callback", fn = ApplyTopDivider })
    end

    -- After init, sync BG to the tracker's current shown state. On /reload
    -- inside M+ (or a raid), otf may already be hidden by the time we run
    -- and OnHide won't fire again, leaving BG + divider visible alone.
    local function SyncBGToTracker()
        if not _bgFrame then return end
        if otf:IsShown() then _bgFrame:Show() else _bgFrame:Hide() end
    end
    SyncBGToTracker()
    C_Timer.After(0.1, SyncBGToTracker)
    C_Timer.After(0.5, SyncBGToTracker)

    local evt = CreateFrame("Frame")
    evt:RegisterEvent("PLAYER_ENTERING_WORLD")
    evt:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    evt:RegisterEvent("ENCOUNTER_START")
    evt:RegisterEvent("ENCOUNTER_END")
    evt:SetScript("OnEvent", function(_, event)
        if event == "ENCOUNTER_START" then
            _inEncounter = true
        elseif event == "ENCOUNTER_END" then
            _inEncounter = false
        elseif event == "PLAYER_ENTERING_WORLD" then
            -- Clear stale encounter state from a missed ENCOUNTER_END.
            _inEncounter = false
        end
        UpdateVisibility()
        SyncBGToTracker()
    end)

    -- Register with the shared visibility dispatcher for combat/mount
    -- visibility modes. Bails immediately when suppressed (M+/raid).
    if EllesmereUI.RegisterVisibilityUpdater then
        EllesmereUI.RegisterVisibilityUpdater(function()
            if _eqtSuppressed then return end
            UpdateVisibility()
        end)
    end

    -- Mouseover mode: poll both the tracker and our BG frame as one target
    -- so hovering either fades them in together. SetAlpha on the proxy
    -- drives both frames in lockstep.
    if EllesmereUI.RegisterMouseoverTarget then
        local moProxy = {}
        moProxy.IsShown = function()
            return otf and otf:IsShown() and not ShouldAutoHide()
        end
        moProxy.IsMouseOver = function()
            if otf and otf:IsMouseOver() then return true end
            if _bgFrame and _bgFrame:IsShown() and _bgFrame:IsMouseOver() then return true end
            return false
        end
        moProxy.GetRect = function()
            if _bgFrame and _bgFrame:IsShown() then return _bgFrame:GetRect() end
            if otf then return otf:GetRect() end
            return nil
        end
        moProxy.GetEffectiveScale = function()
            if otf then return otf:GetEffectiveScale() end
            return 1
        end
        moProxy.SetAlpha = function(_, a)
            if otf then otf:SetAlpha(a) end
            if _bgFrame then _bgFrame:SetAlpha(a) end
        end
        moProxy.Show = function() end
        moProxy.Hide = function()
            if otf then otf:SetAlpha(0) end
            if _bgFrame then _bgFrame:SetAlpha(0) end
        end
        moProxy.EnableMouse = function() end
        EllesmereUI.RegisterMouseoverTarget(moProxy, function()
            if ShouldAutoHide() then return false end
            if _eqtSuppressed then return false end
            -- Hover-gated sets only reveal while their conditions pass; a
            -- legacy single "mouseover" behaves exactly as before.
            return EllesmereUI.VisWantsMouseover(EQT.DB(), "visibility")
        end)
    end

    C_Timer.After(0.5, UpdateVisibility)
end
