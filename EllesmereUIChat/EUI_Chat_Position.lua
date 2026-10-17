if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Chat_Position.lua
--
--  Where the main chat window sits and how large it is: the Edit Mode
--  store, the saved position and its guard, genesis capture, the resize
--  grip and the size lock.
--  Reads the earlier Chat files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- EllesmereUIChat.lua or an earlier EUI_Chat_*.lua file failed to load.
if not I or I.broken then return end
I.broken = true

local ECHAT = ns.ECHAT
local min, max, floor, abs = min, max, floor, math.abs

local CFD, EnsureChatClampInsets = I.CFD, I.EnsureChatClampInsets

-------------------------------------------------------------------------------
--  Chat position: owned by EUI unlock mode once a position is saved (genesis-
--  captured otherwise). Two writers place ChatFrame1: Edit Mode on every
--  layout apply (login, layout switches, Edit Mode exit, every layout save,
--  spec changes -- which WoW Forever also fires on level-ups) and
--  ApplyChatPosition right after it, through the anchor guard. On the
--  player's own layout the store lane below writes our anchor and size into
--  it, so Edit Mode's apply lands on our rect and our pass finds nothing to
--  do. A Blizzard preset cannot be written: there every apply moves chat and
--  the guard moves it back within the same frame (a frame at Edit Mode's
--  spot is the blink, and it moves Blizzard's invisible link zones under our
--  text off our lines: right-clicks that miss or pick the wrong name).
-------------------------------------------------------------------------------

-- ChatFrame1 is an Edit Mode system: its SetPoint and ClearAllPoints are Edit
-- Mode's Lua overrides, which from our code would mark Edit Mode's anchor
-- sweep and the frame's snap state as written by us. Every anchor write of
-- ours goes through the saved C methods instead.
local ClearFramePoints, SetFramePoint = EllesmereUI.ClearFramePoints, EllesmereUI.SetFramePoint

-------------------------------------------------------------------------------
--  Edit Mode store. Blizzard's saved-dimensions restore skips the main window
--  ("controlled via edit mode"), so the active Edit Mode layout is the native
--  store for ChatFrame1's position and size, and every layout apply re-applies
--  it. All access goes through the C_EditMode data API only -- never
--  EditModeManagerFrame methods (secure manager chains) -- and only ever saves
--  the blob EllesmereUI.EditModeLayoutsForSave builds (presets first, as
--  SaveLayouts takes it) with chat's entry edited, so a malformed save cannot
--  be constructed here. Never while Edit Mode is open (it saves its own copy
--  over anything written meanwhile) or in combat.
-------------------------------------------------------------------------------
local function EMChatEnums()
    local sysEnum = Enum and Enum.EditModeSystem
    local setEnum = Enum and Enum.EditModeChatFrameSetting
    local layEnum = Enum and Enum.EditModeLayoutType
    if not (sysEnum and sysEnum.ChatFrame and setEnum
        and setEnum.WidthHundreds and setEnum.WidthTensAndOnes
        and setEnum.HeightHundreds and setEnum.HeightTensAndOnes
        and layEnum and layEnum.Preset ~= nil) then
        return nil
    end
    return sysEnum.ChatFrame, setEnum, layEnum
end

local function EMChatFindSystem(layout, sysChat)
    local systems = layout and layout.systems
    if type(systems) ~= "table" then return nil end
    for i = 1, #systems do
        local s = systems[i]
        if type(s) == "table" and s.system == sysChat then return s end
    end
end

local function EMChatSettingRow(sys, settingID)
    local st = sys and sys.settings
    if type(st) ~= "table" then return nil end
    for i = 1, #st do
        local row = st[i]
        if type(row) == "table" and row.setting == settingID then return row end
    end
end

-- The blob and the ACTIVE layout entry: blob, entry, sysChat, setEnum,
-- isPreset (nil on any unexpected shape, or while Edit Mode is open).
-- activeLayout indexes the merged list, presets first. A preset entry is
-- read-only (SaveLayouts ignores edits to it): it is only ever read.
local function EMChatResolve()
    if not (C_EditMode and C_EditMode.GetLayouts and C_EditMode.SaveLayouts) then return nil end
    local sysChat, setEnum, layEnum = EMChatEnums()
    if not sysChat then return nil end
    if EllesmereUI.EditModeOpen() then return nil end
    local blob, numPresets = EllesmereUI.EditModeLayoutsForSave()
    if not blob then return nil end
    local active = blob.activeLayout
    if type(active) ~= "number" then return nil end
    local entry = blob.layouts[active]
    if type(entry) ~= "table" then return nil end
    local isPreset = active <= numPresets or entry.layoutType == layEnum.Preset
    return blob, entry, sysChat, setEnum, isPreset
end

-- Stored chat size of a chat system entry (Edit Mode encodes each dimension
-- as hundreds + tens-and-ones setting pairs). nil when unreadable.
local function EMChatReadSize(sys, setEnum)
    local wH = EMChatSettingRow(sys, setEnum.WidthHundreds)
    local wT = EMChatSettingRow(sys, setEnum.WidthTensAndOnes)
    local hH = EMChatSettingRow(sys, setEnum.HeightHundreds)
    local hT = EMChatSettingRow(sys, setEnum.HeightTensAndOnes)
    if not (wH and wT and hH and hT
        and type(wH.value) == "number" and type(wT.value) == "number"
        and type(hH.value) == "number" and type(hT.value) == "number") then
        return nil
    end
    return wH.value * 100 + wT.value, hH.value * 100 + hT.value
end

-- True while the saved size still needs the second-corner anchor:
-- cfg.chatSize exists and the active layout does not hold it (or cannot be
-- read). Once it does, Edit Mode's own apply sizes chat and the anchor
-- enforcement stands down.
local function EMChatSizeDelta()
    local cfg = ECHAT.DB()
    local size = cfg and cfg.chatSize
    if not (size and size.w and size.h) then return false end
    -- Belt: after a store write this session, keep the anchor enforcement
    -- standing anyway. Field-tested that SaveLayouts coheres EM's cached
    -- tables immediately, so this should never matter -- it guards the
    -- untested edges (event timing on other clients) at the cost of one
    -- boolean.
    if ns._emChatWrote then return true end
    local blob, entry, sysChat, setEnum = EMChatResolve()
    local sys = blob and EMChatFindSystem(entry, sysChat)
    local w, h
    if sys then w, h = EMChatReadSize(sys, setEnum) end
    if not w then return true end
    return abs(w - size.w) > 1 or abs(h - size.h) > 1
end

-- The single anchor that places chat from the saved position, pixel-snapped
-- as every apply places it: point, relPoint, x, y (nil while unsaved). A
-- centre anchor snaps against the dimensions the rect carries: the saved size
-- once there is one.
local function ChatAnchorTarget(cfg, cf1)
    local pos = cfg.chatPosition
    local px, py = pos and pos.x, pos and pos.y
    if not (pos and pos.point and px and py) then return nil end
    local relPoint = pos.relPoint or pos.point
    local PPa = EllesmereUI and EllesmereUI.PP
    if PPa then
        local es = cf1:GetEffectiveScale()
        if pos.point == "CENTER" and relPoint == "CENTER" and PPa.SnapCenterForDim then
            local size = cfg.chatSize
            local dimW = size and size.w or cf1:GetWidth() or 0
            local dimH = size and size.h or cf1:GetHeight() or 0
            px = PPa.SnapCenterForDim(px, dimW, es)
            py = PPa.SnapCenterForDim(py, dimH, es)
        elseif PPa.SnapForES then
            px = PPa.SnapForES(px, es)
            py = PPa.SnapForES(py, es)
        end
    end
    return pos.point, relPoint, px, py
end

-------------------------------------------------------------------------------
--  Store lane: write chat's anchor (and size, once saved) into the active
--  layout whenever it would place chat elsewhere.
-------------------------------------------------------------------------------

-- The anchor the store gets: the target's single anchor in Edit Mode's units
-- (offsets at scale 1, as Edit Mode keeps them). Reused across passes.
local emAnchor = { relativeTo = "UIParent" }

-- Fills emAnchor from the saved position; false while unsaved.
local function EMChatFillAnchor(cfg, cf1)
    local point, relPoint, px, py = ChatAnchorTarget(cfg, cf1)
    if not point then return false end
    local scale = cf1:GetScale() or 1
    emAnchor.point, emAnchor.relativePoint = point, relPoint
    emAnchor.offsetX, emAnchor.offsetY = px * scale, py * scale
    return true
end

-- The entry already places chat on emAnchor, its only anchor (within Edit
-- Mode's own anchor tolerance).
local function EMChatAnchorAgrees(sys)
    local ai = sys.anchorInfo
    return type(ai) == "table" and sys.anchorInfo2 == nil
        and ai.point == emAnchor.point and ai.relativeTo == emAnchor.relativeTo
        and ai.relativePoint == emAnchor.relativePoint
        and type(ai.offsetX) == "number" and type(ai.offsetY) == "number"
        and abs(ai.offsetX - emAnchor.offsetX) < 0.1 and abs(ai.offsetY - emAnchor.offsetY) < 0.1
end

-- The entry already sizes chat w x h (no w: the size is not ours to keep).
local function EMChatSizeAgrees(sys, setEnum, w, h)
    if not w then return true end
    local sw, sh = EMChatReadSize(sys, setEnum)
    return sw ~= nil and abs(sw - w) <= 1 and abs(sh - h) <= 1
end

-- One size row (added when the entry lacks it), noted for Uninstall EUI
-- first. pairID: the dimension's other row, which goes back with it.
local function EMChatSetRow(layout, sys, id, value, pairID)
    local row = EMChatSettingRow(sys, id)
    if not row then
        if type(sys.settings) ~= "table" then sys.settings = {} end
        sys.settings[#sys.settings + 1] = { setting = id, value = value }
        return
    end
    EllesmereUI.NoteEditModeSetting(layout, sys, id, row.value, value, nil, pairID)
    row.value = value
end

-- Writes emAnchor and, with w, the size into sys (chat's entry of layout),
-- each change noted for Uninstall EUI first.
local function EMChatWrite(layout, sys, setEnum, w, h)
    if not EMChatAnchorAgrees(sys) then
        EllesmereUI.NoteEditModeAnchor(layout, sys, emAnchor)
        local ai = sys.anchorInfo
        if type(ai) ~= "table" then
            ai = {}
            sys.anchorInfo = ai
        end
        ai.point, ai.relativeTo, ai.relativePoint = emAnchor.point, emAnchor.relativeTo, emAnchor.relativePoint
        ai.offsetX, ai.offsetY = emAnchor.offsetX, emAnchor.offsetY
        sys.anchorInfo2 = nil
        sys.isInDefaultPosition = false
    end
    if not EMChatSizeAgrees(sys, setEnum, w, h) then
        -- All four rows: Uninstall puts each dimension's pair back whole.
        w, h = max(0, floor(w + 0.5)), max(0, floor(h + 0.5))
        EMChatSetRow(layout, sys, setEnum.WidthHundreds, floor(w / 100), setEnum.WidthTensAndOnes)
        EMChatSetRow(layout, sys, setEnum.WidthTensAndOnes, w % 100, setEnum.WidthHundreds)
        EMChatSetRow(layout, sys, setEnum.HeightHundreds, floor(h / 100), setEnum.HeightTensAndOnes)
        EMChatSetRow(layout, sys, setEnum.HeightTensAndOnes, h % 100, setEnum.HeightHundreds)
    end
end

-- The last saved layout and target written this session: each is written
-- once at most, so a store that will not take a value can never loop
-- write -> apply -> write.
local emLast = {}

-- One store pass: when the active saved layout would place chat elsewhere,
-- write chat's anchor (and its size, once saved) into it. A preset is never
-- written.
function ns.EMChatSync()
    if InCombatLockdown() then return end
    local cfg = ECHAT.DB()
    local cf1 = _G.ChatFrame1
    if not (cfg and cf1 and EMChatFillAnchor(cfg, cf1)) then return end
    local blob, entry, sysChat, setEnum, isPreset = EMChatResolve()
    if not blob or isPreset then return end
    local sys = EMChatFindSystem(entry, sysChat)
    if not sys then return end
    local size = cfg.chatSize
    local w, h
    if size and size.w and size.h then w, h = size.w, size.h end
    if EMChatAnchorAgrees(sys) and EMChatSizeAgrees(sys, setEnum, w, h) then return end
    if emLast.name == entry.layoutName and emLast.layoutType == entry.layoutType
        and emLast.point == emAnchor.point and emLast.relPoint == emAnchor.relativePoint
        and emLast.x == emAnchor.offsetX and emLast.y == emAnchor.offsetY
        and emLast.w == w and emLast.h == h then
        return
    end
    emLast.name, emLast.layoutType = entry.layoutName, entry.layoutType
    emLast.point, emLast.relPoint = emAnchor.point, emAnchor.relativePoint
    emLast.x, emLast.y, emLast.w, emLast.h = emAnchor.offsetX, emAnchor.offsetY, w, h
    EMChatWrite(entry, sys, setEnum, w, h)
    if pcall(C_EditMode.SaveLayouts, blob) then ns._emChatWrote = true end
end

-- Unlock mode's Reset: chat's entry in the active saved layout goes back to
-- Edit Mode's default position and size (its own Reset To Default Position,
-- plus the size); the next settled sight captures that spot as ours.
function ns.EMChatResetStore()
    if InCombatLockdown() then return end
    local blob, entry, sysChat, setEnum, isPreset = EMChatResolve()
    if not blob or isPreset then return end
    local sys = EMChatFindSystem(entry, sysChat)
    local mgr = EditModePresetLayoutManager
    if not (sys and mgr and mgr.GetDefaultSystemAnchorInfo and mgr.GetDefaultSettingForSystem) then return end
    local okA, def = pcall(mgr.GetDefaultSystemAnchorInfo, mgr, sysChat)
    if not (okA and type(def) == "table") then return end
    EllesmereUI.NoteEditModeAnchor(entry, sys, def)
    sys.anchorInfo = def
    sys.anchorInfo2 = nil
    sys.isInDefaultPosition = true
    local wH, wT = setEnum.WidthHundreds, setEnum.WidthTensAndOnes
    local hH, hT = setEnum.HeightHundreds, setEnum.HeightTensAndOnes
    local okW1, vW1 = pcall(mgr.GetDefaultSettingForSystem, mgr, sysChat, nil, wH)
    local okW2, vW2 = pcall(mgr.GetDefaultSettingForSystem, mgr, sysChat, nil, wT)
    local okH1, vH1 = pcall(mgr.GetDefaultSettingForSystem, mgr, sysChat, nil, hH)
    local okH2, vH2 = pcall(mgr.GetDefaultSettingForSystem, mgr, sysChat, nil, hT)
    if okW1 and okW2 and type(vW1) == "number" and type(vW2) == "number" then
        EMChatSetRow(entry, sys, wH, vW1, wT)
        EMChatSetRow(entry, sys, wT, vW2, wH)
    end
    if okH1 and okH2 and type(vH1) == "number" and type(vH2) == "number" then
        EMChatSetRow(entry, sys, hH, vH1, hT)
        EMChatSetRow(entry, sys, hT, vH2, hH)
    end
    emLast.name = nil
    if pcall(C_EditMode.SaveLayouts, blob) then ns._emChatWrote = true end
end

-- The apply passes' store pass: one per frame at most, outside the pass that
-- asked (never inside Edit Mode's apply), after combat, and not while a grip
-- drag, an unlock session or the first-install picker is open.
local RunChatStoreSync
RunChatStoreSync = function()
    ns._emSyncQueued = nil
    if ns._chatSizingActive or EllesmereUI._unlockActive or EllesmereUI._firstInstallPending then return end
    if InCombatLockdown() then
        EllesmereUI.CombatQueue.Defer("ChatEMStoreSync", RunChatStoreSync)
        return
    end
    ns.EMChatSync()
end
local function ScheduleChatStoreSync()
    if ns._emSyncQueued then return end
    ns._emSyncQueued = true
    C_Timer.After(0, RunChatStoreSync)
end

-------------------------------------------------------------------------------
--  Placement
-------------------------------------------------------------------------------

-- The anchors ApplyChatPosition places: one, or two while the saved size
-- rides a second corner. Reused across passes.
local chatTarget = { {}, {} }
local function SetChatTarget(i, point, relPoint, x, y)
    local t = chatTarget[i]
    t.point, t.relPoint, t.x, t.y = point, relPoint, x, y
end

-- ChatFrame1 already carries exactly the first n target anchors (GetPoint
-- returns the anchor definitions, never a lagging rect), within Edit Mode's
-- own anchor tolerance. A secret read counts as a mismatch.
local function ChatAtTarget(cf1, n)
    local issecret = _G.issecretvalue
    local num = cf1:GetNumPoints()
    if (issecret and issecret(num)) or num ~= n then return false end
    for i = 1, n do
        local point, rel, relPoint, x, y = cf1:GetPoint(i)
        if issecret and (issecret(point) or issecret(rel) or issecret(relPoint)
            or issecret(x) or issecret(y)) then
            return false
        end
        if rel ~= UIParent or type(x) ~= "number" or type(y) ~= "number" then return false end
        local hit = false
        for j = 1, n do
            local t = chatTarget[j]
            if t.point == point and t.relPoint == relPoint
                and abs(t.x - x) < 0.1 and abs(t.y - y) < 0.1 then
                hit = true
            end
        end
        if not hit then return false end
    end
    return true
end

-- Deferred pass that rewrites a foreign-form saved position as BOTTOMLEFT once
-- the rect resolves (defined after ApplyChatPosition, which arms it).
local CanonicalizeChatPosition

local function ApplyChatPosition()
    -- A grip resize is an engine-driven op on ChatFrame1; the op re-anchors
    -- the frame, Edit Mode's machinery reacts with ApplySystemAnchor, and
    -- the guard below would then re-apply the SAVED anchors every tick --
    -- a revert war that freezes the resize. Held off until release.
    if ns._chatSizingActive then return end
    local cfg = ECHAT.DB()
    if not cfg or not cfg.chatPosition then return end
    local pos = cfg.chatPosition
    local cf1 = _G.ChatFrame1
    if not cf1 then return end
    -- Corner positions only resolve with the clamp insets zeroed; assert
    -- before anchoring so the enforcement itself can never land clamped.
    EnsureChatClampInsets()
    -- Saved size rides as a SECOND corner anchor: a two-point rect is
    -- anchor-determined, so no code path ever calls SetSize on ChatFrame1
    -- (a synchronous SetSize dispatch would run the dock relayout tainted),
    -- the engine layout pass dispatches its OnSizeChanged SECURE, and any
    -- Blizzard SetSize is overridden by the anchors.
    -- Second-corner enforcement serves only while the Edit Mode store
    -- disagrees with the saved size (pre-migration, fresh imports, presets);
    -- once the store carries it, Blizzard's own apply owns the size and this
    -- stands down.
    local size = cfg.chatSize
    local sizeLane = size and size.w and size.h and EMChatSizeDelta()
    local point, relPoint, px, py = ChatAnchorTarget(cfg, cf1)
    if not point then return end
    local n, composed = 1, false
    if sizeLane and point == "CENTER" and relPoint == "CENTER" then
        -- CENTER-form saves (unlock mode Save & Exit) compose the rect around
        -- the centre outright. A lone CENTER anchor would resolve on the
        -- frame's explicit size for a tick, and the canonicalize below would
        -- read the corner of THAT rect -- landing the chat half the size delta
        -- away from where it was dropped.
        SetChatTarget(1, "TOPLEFT", "CENTER", px - size.w / 2, py + size.h / 2)
        SetChatTarget(2, "BOTTOMRIGHT", "CENTER", px + size.w / 2, py - size.h / 2)
        n, composed = 2, true
    else
        SetChatTarget(1, point, relPoint, px, py)
        if sizeLane then
            if point == "BOTTOMLEFT" and relPoint == "BOTTOMLEFT" then
                SetChatTarget(2, "TOPRIGHT", "BOTTOMLEFT", px + size.w, py + size.h)
                n, composed = 2, true
            elseif point == "TOPLEFT" and relPoint == "TOPLEFT" then
                -- TOPLEFT-form positions compose the size anchor directly. A
                -- single-anchor apply would leave the rect on the frame's
                -- explicit (Edit Mode, stale) size until the deferred normalize
                -- below lands -- a window where a late Edit Mode pass baked the
                -- old size in.
                SetChatTarget(2, "BOTTOMRIGHT", "TOPLEFT", px + size.w, py - size.h)
                n, composed = 2, true
            end
        end
    end
    -- Compare-gated: once Edit Mode's own apply lands on our anchors (the
    -- store carries them), there is nothing to write -- unless the clamp
    -- insets were just put back (EnsureChatClampInsets above): a rect pinned
    -- under the other insets only lets go once the anchors are written again.
    if ns._chatReanchor or not ChatAtTarget(cf1, n) then
        ns._chatReanchor = nil
        ClearFramePoints(cf1)
        for i = 1, n do
            local t = chatTarget[i]
            SetFramePoint(cf1, t.point, UIParent, t.relPoint, t.x, t.y)
        end
    end
    if sizeLane and (not composed or point ~= "BOTTOMLEFT") and not ns._chatCanonPending then
        -- Canonicalize foreign forms to BOTTOMLEFT once the rect resolves,
        -- so every later apply composes on the fast path. One pass pending at
        -- a time: every apply in between lands in the same pass.
        ns._chatCanonPending = true
        C_Timer.After(0, CanonicalizeChatPosition)
    end
    -- The visible stack follows numerically; sync it now rather than at the
    -- next event so drags and guard re-applies land in one motion.
    if ECHAT.PositionChatPanelsNow then ECHAT.PositionChatPanelsNow() end
    -- The sync above reads the rect the SetPoints just changed, and same-tick
    -- reads can lag the engine layout pass (the grip-save rule) -- the panel,
    -- the tab band anchored to it, and the strip's clip then disagree for a
    -- tick (ghost tabs clipped to slivers). One coalesced deferred re-sync
    -- lands panels-then-strip on the resolved rect for EVERY apply path.
    if not ns._chatPosResync then
        ns._chatPosResync = true
        C_Timer.After(0, function()
            ns._chatPosResync = nil
            if ECHAT.PositionChatPanelsNow then ECHAT.PositionChatPanelsNow() end
            if ECHAT.TabsRefreshNow then ECHAT.TabsRefreshNow() end
        end)
    end
    -- Keep the store on our rect once ownership has begun (the anchor guard
    -- is installed at the first settled sight).
    if CFD(cf1).anchorGuarded then ScheduleChatStoreSync() end
end
CanonicalizeChatPosition = function()
    ns._chatCanonPending = nil
    local cf1 = _G.ChatFrame1
    local cfg2 = ECHAT.DB()
    if not cf1 or not cfg2 or not cfg2.chatPosition or ns._chatSizingActive then
        ns._chatCanonLaps = nil
        return
    end
    -- A rect pinned under other clamp insets is not where the anchors put it:
    -- never save that spot. Re-anchor and try again next tick, at most twice:
    -- Edit Mode re-seats the insets from its selection box on its own layout
    -- passes, so a lap that keeps finding them moved would otherwise run every
    -- frame forever. Stopping keeps the saved form, which every apply still
    -- places; the next apply from elsewhere tries again.
    EnsureChatClampInsets()
    if ns._chatReanchor then
        local laps = (ns._chatCanonLaps or 0) + 1
        if laps > 2 then
            ns._chatCanonLaps = nil
            return
        end
        ns._chatCanonLaps = laps
        ApplyChatPosition()
        return
    end
    ns._chatCanonLaps = nil
    local l, b = cf1:GetLeft(), cf1:GetBottom()
    local issecret = _G.issecretvalue
    if not (l and b) or (issecret and (issecret(l) or issecret(b))) then return end
    cfg2.chatPosition = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = l, y = b }
    ApplyChatPosition()
end

ECHAT.ApplyChatPosition = ApplyChatPosition
ns._EMChatSizeDelta = EMChatSizeDelta

-- Re-assert after an Edit Mode layout apply in the SAME frame: a one-shot
-- OnUpdate on a frame of ours (hidden while idle) runs after this frame's
-- event handlers and before it renders, so Edit Mode's rect never shows. A
-- timer waits for the next frame, and that one frame at Edit Mode's spot is
-- the blink (it also moves Blizzard's link zones off our lines). A request
-- only shows the frame: no addon code runs inside Edit Mode's apply.
local chatReassert = CreateFrame("Frame")
chatReassert:Hide()
chatReassert:SetScript("OnUpdate", function(self)
    self:Hide()
    if ns._chatSizingActive or EllesmereUI._unlockActive then return end
    local cfg = ECHAT.DB()
    if cfg and cfg.chatPosition then ApplyChatPosition() end
end)

-- Edit Mode's layout apply (login server-data arrival, layout switches) can
-- re-rect the main window through paths the ApplySystemAnchor guard never
-- sees, taking the last word over the settled-sight apply -- the frame sits
-- at Edit Mode's rect while the panel stack holds ours until an interaction
-- re-arms enforcement. Its own event is the precise edge: re-assert there,
-- gated on ownership having begun (anchor guard installed) so it can never
-- fire early.
do
    local emWatch = CreateFrame("Frame")
    emWatch:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
    emWatch:SetScript("OnEvent", function()
        local cfg = ECHAT.DB()
        if not (cfg and cfg.chatPosition) then return end
        local cf1 = _G.ChatFrame1
        local d1 = cf1 and CFD(cf1)
        if not (d1 and d1.anchorGuarded) then return end
        chatReassert:Show()
    end)
end

-- Genesis capture: on the first settled sight with no saved position,
-- ChatFrame1's current (Edit-Mode-placed) rect becomes OUR saved position.
-- Pixel-identical takeover -- users see no change on update; from then on
-- chat position is an EUI unlock element.
-- The sidebar's footprint left of the chat panel under the current look: its
-- width, a Separate Sidebar's gap, less the stock column's seat overlap; 0
-- while it sits on the right or never shows.
local function GenesisFP(cfg)
    if cfg.sidebarRight or cfg.sidebarVisibility == "never" then return 0 end
    return min(100, max(30, cfg.sidebarWidth
            or (ECHAT.SidebarWidthDefault and ECHAT.SidebarWidthDefault() or 40)))
        + ((cfg.sidebarSeparate == true) and (cfg.sidebarSeparateSpacing or 8) or 0)
        - (ECHAT.SB_KIT and ECHAT.SB_KIT.col.dx or 0)
end

local function CaptureChatPositionGenesis()
    local cfg = ECHAT.DB()
    if not cfg then return end
    -- One-time ownership migration: positions saved before the Edit Mode
    -- era are stale (users repositioned via Edit Mode since; re-applying
    -- an ancient spot would visibly move their chat on update). Discard
    -- once so genesis captures the CURRENT placement.
    local stale = false
    if cfg._chatPosOwnership ~= 1 then
        cfg._chatPosOwnership = 1
        stale = cfg.chatPosition ~= nil
        cfg.chatPosition = nil
    end
    if cfg.chatPosition then return end
    local cf1 = _G.ChatFrame1
    if not cf1 then return end
    local left, bottom = cf1:GetLeft(), cf1:GetBottom()
    if not (left and bottom) then return end
    -- Blizzard's chat spot leaves no room for our sidebar on its left, so the
    -- first capture moves chat right by the sidebar's footprint. Not for a
    -- position the migration above just dropped: that layout already had the
    -- sidebar. The footprint is kept (plain data) for GenesisSettle below.
    if not stale then
        local fp = GenesisFP(cfg)
        left = left + fp / (cf1:GetScale() or 1)
        cfg._chatGenesisFP, cfg._chatGenesisX = fp, left
        ns._chatGenesisNow = true
    end
    cfg.chatPosition = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = left, y = bottom }
end

-- A fresh install settles its look after that capture (the style picker, a
-- later session), and each look's sidebar has its own footprint: from the
-- next session on, every settled sight re-measures it and moves chat by the
-- difference while chat still sits where the capture put it (a drag ends
-- this), until no style choice is pending.
local function GenesisSettle()
    local cfg = ECHAT.DB()
    local old = cfg and cfg._chatGenesisFP
    if not old or ns._chatGenesisNow then return end
    local pos, cf1 = cfg.chatPosition, _G.ChatFrame1
    if not (pos and cf1 and pos.point == "BOTTOMLEFT" and cfg._chatGenesisX
            and pos.x and abs(pos.x - cfg._chatGenesisX) < 0.5) then
        cfg._chatGenesisFP, cfg._chatGenesisX = nil, nil
        return
    end
    local now = GenesisFP(cfg)
    if now ~= old then
        pos.x = pos.x + (now - old) / (cf1:GetScale() or 1)
        cfg._chatGenesisFP, cfg._chatGenesisX = now, pos.x
    end
    if not (EllesmereUIDB and EllesmereUIDB.styleChoicePending) then
        cfg._chatGenesisFP, cfg._chatGenesisX = nil, nil
    end
end

-- Edit Mode override, the suite's action-bar anchor-guard pattern: post-hook
-- the system anchor apply and re-apply OURS from the one-shot re-assert
-- frame (same frame, outside Edit Mode's secure chain). One hook covers the
-- login layout apply, layout switches, spec changes and Edit Mode exit. ChatFrame1 is NEVER reparented and
-- its SetPoint is NEVER hooked -- both are recorded failure classes (Edit
-- Mode's UpdateSystemAnchorInfo assumes a UIParent child; a reparented
-- chat came back with no anchors at all).
local function InstallChatAnchorGuard()
    local cf1 = _G.ChatFrame1
    if not cf1 or not cf1.ApplySystemAnchor then return end
    local d = CFD(cf1)
    if d.anchorGuarded then return end
    d.anchorGuarded = true
    hooksecurefunc(cf1, "ApplySystemAnchor", function()
        local cfg = ECHAT.DB()
        if cfg and cfg.chatPosition then chatReassert:Show() end
    end)
    -- Edit Mode also sets the clamp insets from its selection box (32-60px
    -- past the window) on every layout apply and on entering Edit Mode,
    -- which applies no anchor; a chat near a screen edge is then pinned
    -- inward. The same re-assert puts our insets back and re-anchors.
    if cf1.UpdateClampOffsets then
        hooksecurefunc(cf1, "UpdateClampOffsets", function()
            local cfg = ECHAT.DB()
            if cfg and cfg.chatPosition then chatReassert:Show() end
        end)
    end
end

-- Kill Edit Mode's selection overlay for chat: the unit-frame treatment
-- adapted. Their Blizzard frames die by hidden reparent; cf1 must stay
-- live, and Edit Mode still drives its Selection child -- so the Selection
-- goes alpha-0 and mouse-dead IN PLACE (never reparented: a region its
-- owner still writes must stay in its tree). Chat can be neither
-- highlighted nor dragged in Edit Mode; asserted from the state sync since
-- Edit Mode rewrites the overlay across its sessions.
-- Edit Mode's resize handle on the main window (EditModeResizeButton, a
-- Button child Edit Mode shows on enter and hides on exit) gets the same
-- in-place treatment: sizing belongs to our grip, and a live handle here
-- would write Edit Mode's size store behind the size lane's back.
local function SuppressEditModeChild(f)
    if not f then return end
    -- GetAlpha reads secret on chat-roleset widgets in lockdown; a secret
    -- skips the compare and re-asserts.
    local a = f:GetAlpha()
    if (issecretvalue and issecretvalue(a)) or a ~= 0 then f:SetAlpha(0) end
    if f.SetMouseClickEnabled then
        if f:IsMouseClickEnabled() then f:SetMouseClickEnabled(false) end
        if f:IsMouseMotionEnabled() then f:SetMouseMotionEnabled(false) end
    end
end
function ECHAT.SuppressChatEditModeSelection()
    local cf1 = _G.ChatFrame1
    if not cf1 then return end
    SuppressEditModeChild(cf1.Selection)
    SuppressEditModeChild(cf1.EditModeResizeButton)
end
ns._CaptureChatPositionGenesis = CaptureChatPositionGenesis
ns._GenesisSettle = GenesisSettle
ns._InstallChatAnchorGuard = InstallChatAnchorGuard

-- Main chat size is applied as a second corner anchor inside
-- ApplyChatPosition (cfg.chatSize; anchor-determined rect, never SetSize).
-- Undocked windows stay Blizzard-sized. This stub remains for callers.
local function ApplyChatSize()
end
ECHAT.ApplyChatSize = ApplyChatSize

-- Main chat resize grip: our button, ANCHOR-driven sizing. Blizzard never
-- shows ChatFrame1's own resize button (Edit Mode owned main chat sizing,
-- and our position takeover suppressed Edit Mode), so this grip is the sole
-- resize surface. HARD CONSTRAINTS, both field-proven:
--   - Never SetSize ChatFrame1 in any form: its OnSizeChanged is wired to
--     FCFDock_OnPrimarySizeChanged, which writes dock.isDirty/leftTab AND
--     installs the dock OnUpdate script; a synchronous insecure dispatch
--     taints the dock slots the secure whisper temp-window chain reads
--     (the recorded UpdateHeader secret-rect detonation class).
--   - StartSizing is engine-VETOED on the Edit-Mode-managed main window
--     (probed: rect identical before/after with the op "running"); the
--     docked branch in Blizzard's ResizeButton XML is legacy-dead.
-- The lane that satisfies both: pin TOPLEFT and drive the BOTTOMRIGHT
-- corner anchor from the cursor. A two-point rect is anchor-determined;
-- the engine layout pass recomputes it and dispatches OnSizeChanged as a
-- fresh SECURE execution (Blizzard's own dock relayout defers its work one
-- frame for exactly this timing). Persistence: cfg.chatSize, applied as
-- the second corner anchor by ApplyChatPosition -- Blizzard's saved-
-- dimensions restore explicitly skips the main window.
local function BuildMainChatResizeGrip(cf)
    local d = CFD(cf)
    if d.resizeGrip or not d.bg then return end
    local grip = CreateFrame("Button", nil, d.bg)
    d.resizeGrip = grip
    grip:SetSize(18, 18)
    -- Anchored to the chat frame like the undocked buttons, so the icon
    -- hugs the true resize corner regardless of panel insets; nudged out
    -- past the frame edge so it sits in the panel's corner, not the text's.
    grip:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 4, -3)
    grip:SetFrameStrata("HIGH")
    local tex = grip:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\resize_element.png")
    tex:SetDesaturated(true)
    tex:SetVertexColor(1, 1, 1)
    grip:SetAlpha(0.4)

    -- Damage-meters drag mechanics, anchor-driven: per tick the TOPLEFT stays
    -- pinned and the BOTTOMRIGHT corner anchor follows the cursor (shift =
    -- axis lock, min sizes, screen-edge caps). The rect is anchor-determined,
    -- so the engine layout pass recomputes it and ChatFrame1's OnSizeChanged
    -- (the dock relayout) dispatches SECURE. StartSizing is NOT usable here
    -- (engine-vetoed on the Edit-Mode-managed main window; field-probed) and
    -- SetSize is BANNED (synchronous tainted dispatch). No InProtectedInstance
    -- gate: /euidev makes it return true and would dead-stop the grip; all
    -- rect reads below are secret-gated instead.
    local MIN_W, MIN_H = 220, 100
    local sizing = false
    local startX, startY, startW, startH, anchorLeft, anchorTop
    local curW, curH, axis, shiftWas
    local ticker = CreateFrame("Frame")
    ticker:Hide()
    ticker:SetScript("OnUpdate", function()
        if not sizing then return end
        local cx, cy = GetCursorPosition()
        local es = cf:GetEffectiveScale()
        local dx = cx / es - startX
        local dy = startY - cy / es
        local shiftDown = IsShiftKeyDown()
        local newW, newH
        if shiftDown then
            if not shiftWas then
                axis = (math.abs(dx) >= math.abs(dy)) and "w" or "h"
            end
            if axis == "w" then
                newW, newH = math.max(MIN_W, startW + dx), startH
            else
                newW, newH = startW, math.max(MIN_H, startH + dy)
            end
        else
            axis = nil
            newW = math.max(MIN_W, startW + dx)
            newH = math.max(MIN_H, startH + dy)
        end
        -- Cap so the frame can't extend past screen edges from the pinned corner.
        local screenR = UIParent:GetRight() or 0
        local screenB = UIParent:GetBottom() or 0
        if screenR - anchorLeft > MIN_W then newW = math.min(newW, screenR - anchorLeft) end
        if anchorTop - screenB > MIN_H then newH = math.min(newH, anchorTop - screenB) end
        curW, curH = newW, newH
        -- Full re-anchor per tick: a mid-drag Edit Mode anchor write would
        -- otherwise leave a third point and overconstrain the rect.
        ClearFramePoints(cf)
        SetFramePoint(cf, "TOPLEFT", UIParent, "BOTTOMLEFT", anchorLeft, anchorTop)
        SetFramePoint(cf, "BOTTOMRIGHT", UIParent, "BOTTOMLEFT", anchorLeft + newW, anchorTop - newH)
        shiftWas = shiftDown
        -- The visible stack is positioned numerically; sync per tick so the
        -- panels ride the drag with zero lag.
        if ECHAT.PositionChatPanelsNow then ECHAT.PositionChatPanelsNow() end
    end)

    grip:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        -- Belt behind the combat hide: no drag may start in lockdown even
        -- if a hide edge races the click.
        if InCombatLockdown() then return end
        local issecret = _G.issecretvalue
        local left, top = cf:GetLeft(), cf:GetTop()
        local w, h = cf:GetWidth(), cf:GetHeight()
        if not (left and top and w and h) then return end
        if issecret and (issecret(left) or issecret(top)
            or issecret(w) or issecret(h)) then return end
        -- Hold the position enforcement for the whole drag: our per-tick
        -- corner anchors rule until release.
        ns._chatSizingActive = true
        ClearFramePoints(cf)
        SetFramePoint(cf, "TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        SetFramePoint(cf, "BOTTOMRIGHT", UIParent, "BOTTOMLEFT", left + w, top - h)
        anchorLeft, anchorTop = left, top
        local cx, cy = GetCursorPosition()
        local es = cf:GetEffectiveScale()
        startX, startY = cx / es, cy / es
        startW, startH = w, h
        curW, curH = w, h
        shiftWas = false
        sizing = true
        ticker:Show()
        -- Held for the whole drag: the cursor can slide off the grip mid-
        -- drag, and its OnLeave alone would disarm the geometry follower
        -- while the frame is still resizing.
        if ECHAT.FollowArm then ECHAT.FollowArm() end
    end)
    grip:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" or not sizing then return end
        sizing = false
        ticker:Hide()
        ns._chatSizingActive = nil
        if ECHAT.FollowRelease then ECHAT.FollowRelease() end
        -- Save from the drag's own numbers (never frame reads: the rect
        -- resolves in the engine layout pass and can lag the final tick).
        -- Persistence is OUR DB key -- Blizzard's saved-dimensions restore
        -- explicitly skips the main window ("controlled via edit mode").
        local cfg = ECHAT.DB()
        if cfg and curW and curH then
            local w = math.floor(curW + 0.5)
            local h = math.floor(curH + 0.5)
            cfg.chatSize = { w = w, h = h }
            cfg.chatPosition = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT",
                x = anchorLeft, y = anchorTop - h }
        end
        -- The apply also hands the rect to the Edit Mode store (its next-frame
        -- store pass; a quiet no-op when the store already agrees).
        if ECHAT.ApplyChatPosition then ECHAT.ApplyChatPosition() end
        if ECHAT.TabsRefreshNow then ECHAT.TabsRefreshNow() end
    end)
    -- Lock toggled or panel hidden mid-drag: end the drag and release the
    -- position hold, or the guard would stay suspended forever.
    grip:SetScript("OnHide", function()
        if sizing then
            sizing = false
            ticker:Hide()
            ns._chatSizingActive = nil
            if ECHAT.FollowRelease then ECHAT.FollowRelease() end
        end
    end)
    -- Undocked-button hover parity; a resize drag starts and stays on this
    -- grip, so the geometry follower arms while the mouse is here and the
    -- panels ride the drag live.
    grip:SetScript("OnEnter", function(self)
        self:SetAlpha(0.75)
        if ECHAT.FollowArm then ECHAT.FollowArm() end
    end)
    grip:SetScript("OnLeave", function(self)
        self:SetAlpha(0.4)
        if ECHAT.FollowRelease then ECHAT.FollowRelease() end
    end)
    -- Combat gate: resizing is disabled in combat, matching Edit Mode's own
    -- posture. Both edges recompute through the lock applier (the single
    -- shown-state authority), so the combat hide can never fight the lock
    -- setting; built once with the grip (idempotency guard above).
    local combatGate = CreateFrame("Frame")
    combatGate:RegisterEvent("PLAYER_REGEN_DISABLED")
    combatGate:RegisterEvent("PLAYER_REGEN_ENABLED")
    combatGate:SetScript("OnEvent", function()
        if ECHAT.ApplyLockChatSize then ECHAT.ApplyLockChatSize() end
    end)
end
ns._BuildMainChatResizeGrip = BuildMainChatResizeGrip

-- Unlock-mode placements of ChatFrame1 (the Chat mover's drag start, every
-- drag tick, arrow/cog nudges) collapse it to ONE anchor point: the mover
-- treats every element as explicitly sized. The main window's size rides a
-- second corner anchor instead (SetSize on ChatFrame1 is banned -- see the
-- grip above), so a one-point frame falls back to its explicit size, which
-- is whatever Edit Mode's last apply set, not ours. Called from the
-- element's onLiveMove after each placement: re-add the opposite corner
-- from the anchor DEFINITION (GetPoint returns the SetPoint arguments, never
-- a lagging rect) so the frame keeps its size through the whole session.
-- Idempotent -- a frame already carrying two points is left alone.
local function KeepMainChatSizeCorner()
    local cfg = ECHAT.DB()
    local size = cfg and cfg.chatSize
    if not (size and size.w and size.h) then return end
    local cf1 = _G.ChatFrame1
    if not cf1 or cf1:GetNumPoints() ~= 1 then return end
    local point, rel, relPoint, x, y = cf1:GetPoint(1)
    if rel ~= UIParent then return end
    local issecret = _G.issecretvalue
    if issecret and (issecret(x) or issecret(y)) then return end
    if type(x) ~= "number" or type(y) ~= "number" then return end
    relPoint = relPoint or point
    local w, h = size.w, size.h
    if point == "TOPLEFT" then
        SetFramePoint(cf1, "BOTTOMRIGHT", UIParent, relPoint, x + w, y - h)
    elseif point == "BOTTOMLEFT" then
        SetFramePoint(cf1, "TOPRIGHT", UIParent, relPoint, x + w, y + h)
    elseif point == "TOPRIGHT" then
        SetFramePoint(cf1, "BOTTOMLEFT", UIParent, relPoint, x - w, y + h)
    elseif point == "BOTTOMRIGHT" then
        SetFramePoint(cf1, "TOPLEFT", UIParent, relPoint, x - w, y - h)
    elseif point == "CENTER" then
        ClearFramePoints(cf1)
        SetFramePoint(cf1, "TOPLEFT", UIParent, relPoint, x - w / 2, y + h / 2)
        SetFramePoint(cf1, "BOTTOMRIGHT", UIParent, relPoint, x + w / 2, y - h / 2)
    end
end
ns._KeepMainChatSizeCorner = KeepMainChatSizeCorner

-- Lock Main Chat Size: hides OUR grip (main chat's sole resize surface).
-- Blizzard's ChatFrame1ResizeButton stays permanently dead -- alpha + mouse
-- only, never isLocked/FCF_SetLocked (the dock-list/isLocked poison class).
function ECHAT.ApplyLockChatSize()
    local cfg = ECHAT.DB()
    local locked = cfg and cfg.lockChatSize == true
    local btn = _G.ChatFrame1ResizeButton
    if btn then
        btn:SetAlpha(0)
        btn:EnableMouse(false)
    end
    local cf1 = _G.ChatFrame1
    local grip = cf1 and CFD(cf1).resizeGrip
    if grip then
        -- Hidden in combat too: Edit Mode itself is combat-disabled, and a
        -- mid-combat resize could hit protected chat frames (the whisper-
        -- window lockdown class). The grip's OnHide ends any drag that was
        -- live when combat started; the regen listener in the grip build
        -- recomputes this on both combat edges.
        grip:SetShown(not locked and not InCombatLockdown())
    end
end

I.broken = false
