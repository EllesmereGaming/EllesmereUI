if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_SharedHelpers.lua
--  Frame data store, third-party skin registry, Edit Mode-safe anchoring and
--  frame placers, Blizzard cast bar ownership and suppression, and small
--  shared helpers (Swiftmend, level colors, faction art, split-module guard
--  tables). Loads right after EllesmereUI_VisibilityRules.lua.
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI
local _, EUI_NS = ...
EUI_NS = EUI_NS.__euiCoreNS or EUI_NS  -- standalone builds: the core's own table (EllesmereUI.lua)

-------------------------------------------------------------------------------
--  External weak-keyed lookup table for frame state (prevents tainting Blizzard
--  frames). NewFrameData returns a fresh table and its getter; each file keeps
--  its own, so two files never share fields on one frame. The core's pair is
--  stored on EllesmereUI to avoid the 200-local cap in EllesmereUI.lua.
-------------------------------------------------------------------------------
function EllesmereUI.NewFrameData()
    local FFD = setmetatable({}, { __mode = "k" })
    return FFD, function(frame)
        local d = FFD[frame]
        if not d then d = {}; FFD[frame] = d end
        return d
    end
end
if not EllesmereUI._FFD then
    EllesmereUI._FFD, EllesmereUI._GetFFD = EllesmereUI.NewFrameData()
end

-- Stock styles, enable-time catch-up seeds: a profile already on a stock
-- style from before the per-style slots (the Style page did not switch it,
-- so nothing saved the EllesmereUI look's values) keeps those values in its
-- EllesmereUI slot before a seed writes over them, so switching back
-- restores them. `keys` = the module's slot keys (dotted paths one level
-- deep into `p`, as the Style page's SLOT_KEYS). Callers bank only while
-- none of the module's seed stamps is set; an existing slot is never touched.
function EllesmereUI.BankEuiStyleSlot(p, keys)
    if type(p) ~= "table" then return end
    local slots = p._styleSlots
    if type(slots) == "table" and type(slots.eui) == "table" then return end
    if type(slots) ~= "table" then slots = {}; p._styleSlots = slots end
    local out = {}
    for i = 1, #keys do
        local path = keys[i]
        local a, b = path:match("^([^.]+)%.(.+)$")
        if a then
            local s = p[a]
            if type(s) == "table" then out[path] = s[b] end
        else
            out[path] = p[path]
        end
    end
    slots.eui = out
end

-------------------------------------------------------------------------------
--  Third-Party Skin Registration (public API) -- other addons call
--  EllesmereUI.RegisterSkin("TheirAddon", function(S) ... end) to have their frames painted in
--  the EUI house style. This stub only queues: the Blizz UI Enhanced child addon drains the
--  queue at PLAYER_LOGIN (or immediately for late/LoD registrations) and passes the skinning
--  facade S. Queuing keeps registration order-independent -- third-party addons may load before
--  or after the child -- and the API stays callable (a silent no-op) when the child addon is
--  disabled. Developer guide: SKINNING_API.md. Stored on EllesmereUI to avoid the 200-local cap in EllesmereUI.lua.
-------------------------------------------------------------------------------
EllesmereUI._skinRegistry = EllesmereUI._skinRegistry or {}
function EllesmereUI.RegisterSkin(name, applyFn)
    if type(name) ~= "string" or name == "" or type(applyFn) ~= "function" then return end
    local reg = EllesmereUI._skinRegistry
    for i = 1, #reg do
        if reg[i].name == name then return end
    end
    local entry = { name = name, apply = applyFn }
    reg[#reg + 1] = entry
    if EllesmereUI._DispatchSkinRegistration then
        EllesmereUI._DispatchSkinRegistration(entry)
    end
    return true
end

-------------------------------------------------------------------------------
--  Alpha-Zero Visibility Helper
--  For anchor-participating container frames: use alpha 0 + EnableMouse(false)
--  instead of :Hide() so the frame stays in the layout engine with valid bounds.
--  Sub-widgets (icons, text, glows) inside these frames still use :Hide()/:Show().
-------------------------------------------------------------------------------
function EllesmereUI.SetElementVisibility(frame, visible)
    if not frame then return end
    if visible then
        frame:SetAlpha(EllesmereUI._GetFFD(frame).restoreAlpha or 1)
        frame:EnableMouse(EllesmereUI._GetFFD(frame).restoreMouse or false)
    else
        local a = frame:GetAlpha()
        if not issecretvalue(a) and a > 0 then
            EllesmereUI._GetFFD(frame).restoreAlpha = a
        end
        EllesmereUI._GetFFD(frame).restoreMouse = frame:IsMouseEnabled()
        frame:SetAlpha(0)
        frame:EnableMouse(false)
    end
end

-------------------------------------------------------------------------------
--  Anchoring a frame that may be a Blizzard Edit Mode system (ChatFrame1, the
--  action bars, the quest tracker, ...). Edit Mode replaces those frames'
--  SetPoint and ClearAllPoints with Lua overrides that, called from our code,
--  mark Edit Mode's anchor sweep and the frame's snap state as written by us.
--  These call the saved C methods instead; any other frame uses its own.
-------------------------------------------------------------------------------
function EllesmereUI.ClearFramePoints(frame)
    local clear = frame.ClearAllPointsBase or frame.ClearAllPoints
    clear(frame)
end

function EllesmereUI.SetFramePoint(frame, point, relativeTo, relativePoint, x, y)
    local setPoint = frame.SetPointBase or frame.SetPoint
    setPoint(frame, point, relativeTo, relativePoint, x, y)
end

-- Edit Mode's SetScale override, called from our code, re-anchors the system
-- through its SetPoint override and re-runs the managed frame layout; the
-- saved C method only scales, leaving the anchor offsets as they are.
-- keepPosition: an Edit Mode system's offsets are rescaled as the override
-- does it, so the system keeps its spot (Edit Mode's save reads a moved
-- system's anchor back from its geometry times its scale).
function EllesmereUI.SetFrameScale(frame, scale, keepPosition)
    local setScale = frame.SetScaleBase
    if not setScale then
        frame:SetScale(scale)
        return
    end
    local old = keepPosition and frame:GetScale()
    setScale(frame, scale)
    if not old then return end
    local new = frame:GetScale()
    if issecretvalue(old) or issecretvalue(new) or new == old or new <= 0 then return end
    local k = old / new
    for i = 1, frame:GetNumPoints() do
        local p, rel, rp, x, y = frame:GetPoint(i)
        if not (issecretvalue(p) or issecretvalue(rel) or issecretvalue(rp)
                or issecretvalue(x) or issecretvalue(y)) then
            EllesmereUI.SetFramePoint(frame, p, rel, rp, x * k, y * k)
        end
    end
end

-- Edit Mode's Hide override on a system sized to its children (a layout
-- frame: the party, raid and boss frame containers), called from our code,
-- first breaks the snap of every system snapped to it, re-anchoring each one
-- and writing it into the active layout under our taint. This hides through
-- the saved C method instead, so those stay snapped (Edit Mode's own save
-- still breaks snaps to party, raid and boss frames); any other frame uses
-- its own Hide. A protected frame still hides only out of combat. Show has
-- no such override (a plain Show undoes this), except on Blizzard's action
-- bars, whose overrides keep their own shown state, which this leaves as it
-- was.
function EllesmereUI.HideFrame(frame)
    local hide = frame.HideBase or frame.Hide
    hide(frame)
end

-------------------------------------------------------------------------------
--  Frame placers: keep an unprotected Blizzard frame that Blizzard keeps
--  re-anchoring (a bottom managed column frame such as GroupLootContainer) at
--  a spot of ours, with nothing written onto the frame.
--
--  EllesmereUI.SetFramePlacer(frame, owner, fn): owners are tried in the fixed
--  order of PLACER_RANKS, "shifter" (the player's saved spot) before "cdm" (an
--  automatic spot); a new owner adds its rank there. fn(frame, point,
--  relativeTo, relativePoint, x, y) gets the anchor Blizzard last set (an
--  anchor to the parent comes with the parent) and returns the anchor to use,
--  nil to pass to the next owner, or false to pass and be asked again when
--  combat ends (an input it reads is secret); nil from every owner keeps
--  Blizzard's anchor. fn = nil removes the owner, and the last owner leaving
--  puts Blizzard's anchor back. Returns false, registering nothing, for an
--  unknown owner, a value that is not a frame, an fn that is not a function,
--  or a protected, forbidden or anchoring-restricted frame (a secret answer
--  counts as yes).
--  EllesmereUI.RequestFramePlacement(frame): place it again after a saved
--  spot or another input of an owner changed.
--
--  Post-hooks installed at the frame's first registration watch writes from
--  anyone but us. A SetPoint or SetAllPoints marks the frame and a
--  ClearAllPoints does not (Blizzard re-anchors through SetPoint when it
--  shows the frame again). A frame in a managed column (its layoutParent)
--  is placed as the column's Layout returns, whatever ran it, so Blizzard's
--  anchor is never drawn: one post-hook per column, which costs one check
--  while nothing is marked. One hidden frame of ours places every frame
--  still marked from its OnUpdate (the same frame when Blizzard re-anchors
--  from an event, one frame later when it does so from a timer, an
--  animation or another OnUpdate). The anchor such a write leaves is
--  Blizzard's new one, unless the frame then has more than one point: those
--  anchors stay, except that a point a SetPoint adds beside ours (no clear
--  first) puts ours back on alone. A placement or hand-back that cannot run
--  (the frame refused at that moment, or Blizzard's anchor secret) runs
--  again when combat ends. Placer frames are unprotected, so placements run
--  in combat too: the refusal check before every write stands in for a
--  combat gate. An owner fn must not register or remove placers.
-------------------------------------------------------------------------------
do
    local PLACER_RANKS = { shifter = 1, cdm = 2 }
    local NUM_PLACER_RANKS = 0
    for _, rank in pairs(PLACER_RANKS) do
        if rank > NUM_PLACER_RANKS then NUM_PLACER_RANKS = rank end
    end
    local placerStates = setmetatable({}, { __mode = "k" })
    local PlacerRetry

    local function PlacerRefused(frame)
        local v = frame:IsForbidden()
        if issecretvalue(v) or v then return true end
        v = frame:IsProtected()
        if issecretvalue(v) or v then return true end
        if frame.IsAnchoringRestricted then
            v = frame:IsAnchoringRestricted()
            if issecretvalue(v) or v then return true end
        end
        return false
    end

    local function PlacerSet(frame, point, relativeTo, relativePoint, x, y)
        EllesmereUI.ClearFramePoints(frame)
        EllesmereUI.SetFramePoint(frame, point, relativeTo, relativePoint, x, y)
    end

    -- False when SetPoint refused the anchor (an anchor loop): the frame was
    -- left with no points, and the error goes to the error handler. Either
    -- way no point of anyone else is left on the frame.
    local function PlacerApply(frame, st, point, relativeTo, relativePoint, x, y)
        st.applying = true
        local ok, err = pcall(PlacerSet, frame, point, relativeTo, relativePoint, x, y)
        st.applying, st.over = false, false
        if not ok then geterrorhandler()(err) end
        return ok
    end

    -- Runs the state again when combat ends (one keyed entry in the core's
    -- combat queue, however many states wait).
    local function PlacerOwe(st)
        st.owed = true
        EllesmereUI.CombatQueue.Defer("FramePlacerRetry", PlacerRetry)
    end

    local function PlacerResolve(frame, st)
        st.owed = false
        if st.count == 0 and not st.placed then return end
        if PlacerRefused(frame) then
            PlacerOwe(st)
            return
        end
        if st.count == 0 then
            -- A hand-back refused earlier: our anchor is still on the frame.
            st.placed = false
            PlacerApply(frame, st, st.bp, st.br, st.brp, st.bx, st.by)
            return
        end
        if not st.placed then
            -- The frame holds Blizzard's anchor: kept for the owners and the hand-back.
            if frame:GetNumPoints() ~= 1 then return end
            local p, r, rp, x, y = frame:GetPoint(1)
            if issecretvalue(p) or issecretvalue(r) or issecretvalue(rp)
               or issecretvalue(x) or issecretvalue(y) then
                PlacerOwe(st)
                return
            end
            if r == nil then
                -- An anchor to the parent can read back with no relative
                -- frame; an explicit nil would anchor to the screen instead.
                r = frame:GetParent()
                if issecretvalue(r) then
                    PlacerOwe(st)
                    return
                end
            end
            st.bp, st.br, st.brp, st.bx, st.by = p, r, rp, x, y
        end
        local fns = st.fns
        local later = false
        local ok, p, r, rp, x, y
        for rank = 1, NUM_PLACER_RANKS do
            local fn = fns[rank]
            if fn then
                -- An owner that errors passes, so it never stops the others.
                ok, p, r, rp, x, y = pcall(fn, frame, st.bp, st.br, st.brp, st.bx, st.by)
                if not ok then
                    geterrorhandler()(p)
                    p = nil
                elseif p == false then
                    later = true
                end
                if p then break end
            end
        end
        if later then PlacerOwe(st) end
        if p then
            if st.placed and not st.over and p == st.ap and r == st.ar
               and rp == st.arp and x == st.ax and y == st.ay then
                return
            end
            if PlacerApply(frame, st, p, r, rp, x, y) then
                st.placed = true
                st.ap, st.ar, st.arp, st.ax, st.ay = p, r, rp, x, y
                return
            end
        elseif later or not st.placed then
            -- Nothing placed yet, or an owner decides after combat: the
            -- anchor on the frame stays.
            return
        end
        -- No owner wants a spot, or the owner's anchor was refused.
        st.placed = false
        PlacerApply(frame, st, st.bp, st.br, st.brp, st.bx, st.by)
    end

    -- Shown exactly while a state is marked, so its OnUpdate runs only in a
    -- frame where one was.
    local placerDriver = CreateFrame("Frame")
    placerDriver:Hide()

    local function PlacerFlush()
        placerDriver:Hide()
        for frame, st in pairs(placerStates) do
            if st.dirty then
                st.dirty = false
                PlacerResolve(frame, st)
            end
        end
    end
    placerDriver:SetScript("OnUpdate", PlacerFlush)

    -- Post-hook of a managed column's Layout. Whatever runs the layout (an
    -- event, a timer, an animation that ends, the column's own OnUpdate), the
    -- frames it re-anchored are placed as it returns, before anything draws.
    local function PlacerSettle()
        if placerDriver:IsShown() then PlacerFlush() end
    end
    local placerColumns = {}

    local function PlacerMark(st)
        st.dirty = true
        placerDriver:Show()
    end

    PlacerRetry = function()
        for _, st in pairs(placerStates) do
            if st.owed then PlacerMark(st) end
        end
    end

    local function PlacerNewState(frame)
        local st = { fns = {}, count = 0 }
        placerStates[frame] = st
        -- A write from anyone but us (ours run with st.applying set) that
        -- replaces or clears our anchor drops it, owners or not, so a waiting
        -- hand-back has nothing left to do; a SetPoint or SetAllPoints also
        -- asks for a placement while there are owners. A SetPoint on another
        -- point than ours leaves our anchor on the frame beside it (st.over):
        -- it stays ours, and the next placement or hand-back leaves one point.
        hooksecurefunc(frame, "SetPoint", function(_, point)
            if st.applying then return end
            if st.placed and point ~= st.ap then
                st.over = true
            else
                st.placed, st.over = false, false
            end
            if st.count > 0 then PlacerMark(st) end
        end)
        hooksecurefunc(frame, "SetAllPoints", function()
            if st.applying then return end
            st.placed, st.over = false, false
            if st.count > 0 then PlacerMark(st) end
        end)
        hooksecurefunc(frame, "ClearAllPoints", function()
            if not st.applying then st.placed, st.over = false, false end
        end)
        local column = frame.layoutParent
        if type(column) == "table" and type(column.Layout) == "function"
           and not placerColumns[column] then
            placerColumns[column] = true
            hooksecurefunc(column, "Layout", PlacerSettle)
        end
        return st
    end

    function EllesmereUI.SetFramePlacer(frame, owner, fn)
        local rank = PLACER_RANKS[owner]
        if not rank or type(frame) ~= "table" or not frame.IsForbidden
           or (fn ~= nil and type(fn) ~= "function") then
            return false
        end
        local st = placerStates[frame]
        if fn then
            if st and st.fns[rank] == fn then return true end
            if PlacerRefused(frame) then return false end
            st = st or PlacerNewState(frame)
            if not st.fns[rank] then st.count = st.count + 1 end
            st.fns[rank] = fn
            PlacerMark(st)
            return true
        end
        if not (st and st.fns[rank]) then return true end
        st.fns[rank] = nil
        st.count = st.count - 1
        if st.count > 0 then
            PlacerMark(st)
        elseif st.placed then
            -- placed still means the frame holds our anchor (a write that
            -- replaces or clears it drops placed), so Blizzard's recorded
            -- anchor is current. A frame refused right now keeps our anchor,
            -- still marked as ours, until the hand-back can run.
            if PlacerRefused(frame) then
                PlacerOwe(st)
            else
                st.placed = false
                PlacerApply(frame, st, st.bp, st.br, st.brp, st.bx, st.by)
            end
        end
        return true
    end

    function EllesmereUI.RequestFramePlacement(frame)
        local st = placerStates[frame]
        if st and st.count > 0 then PlacerMark(st) end
    end
end

-------------------------------------------------------------------------------
--  Blizzard Cast Bar Event Ownership -- standalone cast bar addons claim Blizzard's
--  player/pet cast bars by unregistering their events. oUF's Castbar element writes the same
--  state -- it silences those frames when it enables on the player frame and re-arms them when
--  it disables -- so EUI can hand a user's cast bar back to Blizzard on top of the addon they
--  replaced it with. EUI hides Blizzard's bar by re-parenting it (see SetPlayerCastBarSuppressed),
--  so it never needs the event state changed: wrap anything that flips it in Capture/Restore and only ever undo EUI's own writes.
-------------------------------------------------------------------------------
function EllesmereUI._BlizzCastBars()
    local bars = EllesmereUI._blizzCastBarList
    if bars then return bars end

    bars = {}
    if PlayerCastingBarFrame then bars[#bars + 1] = { frame = PlayerCastingBarFrame, unit = "player" } end
    if PetCastingBarFrame then bars[#bars + 1] = { frame = PetCastingBarFrame, unit = "pet" } end
    EllesmereUI._blizzCastBarList = bars

    for i = 1, #bars do
        local bar = bars[i]
        -- An UnregisterAllEvents outside one of our own Capture/Restore windows is another
        -- addon claiming the frame: EUI drops its claim and records the claim as foreign.
        -- "Foreign" is tracked separately from "not ours" because those are very different states -- see RestoreBlizzCastBarEvents.
        hooksecurefunc(bar.frame, "UnregisterAllEvents", function()
            if not EllesmereUI._blizzCastBarSnapshot then
                bar.owned = false
                bar.foreign = true
            end
        end)
    end
    return bars
end

function EllesmereUI.CaptureBlizzCastBarEvents()
    local bars = EllesmereUI._BlizzCastBars()
    local snapshot = {}
    for i = 1, #bars do
        snapshot[i] = bars[i].frame:IsEventRegistered("UNIT_SPELLCAST_START") and true or false
    end
    EllesmereUI._blizzCastBarSnapshot = snapshot
end

function EllesmereUI.RestoreBlizzCastBarEvents()
    local snapshot = EllesmereUI._blizzCastBarSnapshot
    if not snapshot then return end
    EllesmereUI._blizzCastBarSnapshot = nil

    local bars = EllesmereUI._blizzCastBarList
    for i = 1, #bars do
        local bar = bars[i]
        local live = bar.frame:IsEventRegistered("UNIT_SPELLCAST_START") and true or false
        if live ~= snapshot[i] then
            if not live then
                bar.owned = true
            elseif bar.owned then
                bar.owned = false
            elseif bar.foreign then
                -- Another addon silenced this frame and we just re-registered it
                -- on the way past; put it back the way we found it instead of
                -- resurrecting Blizzard's cast bar next to theirs.
                bar.frame:UnregisterAllEvents()
                bar.frame:Hide()
            else
                -- Registered inside our own window with nobody claiming it.
                -- That is EUI's own bookkeeping having lost track (a silence
                -- that produced no transition to observe), NOT another addon,
                -- so re-silencing here would kill Blizzard's cast bar for the
                -- session with no way back short of a reload. Leave it armed:
                -- a visible Blizzard bar is something the user can turn off, a
                -- dead one is not.
            end
        end
    end
end

-- The cast events Blizzard's bars listen on, registered per unit. Mirrors the set oUF's
-- Castbar element restores when it disables, which is the only path that has ever successfully re-armed these frames.
--
-- SetUnit is deliberately NOT used to re-arm: its body is guarded on `self.unit ~= unit`, and
-- the frame still holds the unit Blizzard assigned at load, so passing that same unit registers
-- nothing at all. Forcing the guard open is worse -- SetUnit runs StopAnims -> StopFinishAnims,
-- which iterates a table that cannot be accessed while tainted, so from addon execution it throws
-- outright ("attempted to iterate a table that cannot be accessed while tainted") and takes down
-- whatever called it. Registering the events directly is what oUF does, is taint-clean, and touches no Blizzard code at all.
local BLIZZ_CAST_EVENTS = {
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_EMPOWER_START",
    "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_EMPOWER_STOP",
    "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_EMPOWER_UPDATE",
    "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
}

-- Give Blizzard's cast bars their event wiring back, unless another addon has claimed them.
-- Covers the pet bar too: oUF silences both and only re-arms them from its Castbar element's
-- Disable, so any release path that does not run that (the element was never enabled to begin with) leaves both dead.
function EllesmereUI.RearmBlizzCastBars()
    local bars = EllesmereUI._blizzCastBarList
    if not bars then return end
    for i = 1, #bars do
        local bar = bars[i]
        if not bar.foreign and not bar.frame:IsEventRegistered("UNIT_SPELLCAST_START") then
            bar.owned = false
            for j = 1, #BLIZZ_CAST_EVENTS do
                bar.frame:RegisterUnitEvent(BLIZZ_CAST_EVENTS[j], bar.unit)
            end
            bar.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
            if bar.unit == "pet" then bar.frame:RegisterEvent("UNIT_PET") end
        end
    end
end

-- Arm the ownership hooks at load rather than on first capture. Rearm's only shield against
-- resurrecting a bar a standalone cast bar addon silenced is the foreign flag, and that flag can
-- only be set once the UnregisterAllEvents hooks exist -- a lazy first capture at PLAYER_LOGIN
-- leaves every earlier silence unattributed. File scope runs during the ADDON_LOADED sequence,
-- before any addon's PLAYER_LOGIN handler, so this closes the window to everything except
-- file-scope silences in addons that load before EUI. Guarded on BOTH frames: the list is cached on first build, so building it while either frame is missing would drop that bar for the whole session.
if PlayerCastingBarFrame and PetCastingBarFrame then
    EllesmereUI._BlizzCastBars()
end

-------------------------------------------------------------------------------
--  Shared Player Cast Bar Suppression -- multiple EUI modules can temporarily suppress
--  Blizzard's player cast bar while they render their own. Centralized here so modules cooperate
--  with each other and leave third-party visibility control alone once no EUI module is actively using a replacement bar.
-------------------------------------------------------------------------------
function EllesmereUI.SetPlayerCastBarSuppressed(owner, suppressed)
    if not owner or owner == "" then return end

    local owners = EllesmereUI._playerCastBarSuppressors
    if not owners then
        owners = {}
        EllesmereUI._playerCastBarSuppressors = owners
    end

    if suppressed then
        owners[owner] = true
    else
        owners[owner] = nil
    end

    local blizzBar = PlayerCastingBarFrame
    if not blizzBar then return end

    local shouldSuppress = next(owners) ~= nil
    local hiddenParent = EllesmereUI._playerCastBarHiddenParent

    if shouldSuppress then
        if not hiddenParent then
            hiddenParent = CreateFrame("Frame")
            hiddenParent:Hide()
            EllesmereUI._playerCastBarHiddenParent = hiddenParent
        end

        if blizzBar:GetParent() ~= hiddenParent then
            EllesmereUI._GetFFD(blizzBar).origParent = blizzBar:GetParent()
        end
        EllesmereUI._GetFFD(blizzBar).castBarSuppressed = true

        -- Skip the re-parent while Edit Mode is open: SetParent fires Blizzard's synchronous
        -- layout handlers in this execution, and the UnitFrames Edit-Mode-close hook re-applies this state afterwards.
        if blizzBar:GetParent() ~= hiddenParent
            and not (EditModeManagerFrame and EditModeManagerFrame:IsShown()) then
            blizzBar:SetParent(hiddenParent)
        end

        -- Edit Mode re-anchors the cast bar on every layout apply (spec changes, and every
        -- level-up on WoW Forever); keep re-applying our hidden parent while any EUI owner
        -- suppresses it. The re-park runs in the SAME frame from a one-shot OnUpdate on a
        -- frame of ours (after this frame's handlers, before it renders; a timer showed
        -- Blizzard's bar for a frame), so no addon code runs inside Blizzard's call. In
        -- combat it waits for PLAYER_REGEN_ENABLED instead of being dropped: leaving the
        -- managed layout must not run from addon code in combat, and a dropped re-park
        -- left Blizzard's bar on screen for the rest of the session.
        if not EllesmereUI._GetFFD(blizzBar).setParentHooked then
            EllesmereUI._GetFFD(blizzBar).setParentHooked = true
            local repark = CreateFrame("Frame")
            repark:Hide()
            local function Repark()
                -- Never re-parent while Edit Mode is open: SetParent fires Blizzard's
                -- synchronous layout handlers under addon taint and poisons the manager's state for its next pass (the Edit Mode close hook in UnitFrames re-applies suppression).
                if EllesmereUI._GetFFD(blizzBar).castBarSuppressed
                   and not (EditModeManagerFrame and EditModeManagerFrame:IsShown())
                   and blizzBar:GetParent() ~= EllesmereUI._playerCastBarHiddenParent
                then
                    blizzBar:SetParent(EllesmereUI._playerCastBarHiddenParent)
                end
            end
            repark:SetScript("OnUpdate", function(self)
                self:Hide()
                if InCombatLockdown() then
                    self:RegisterEvent("PLAYER_REGEN_ENABLED")
                else
                    Repark()
                end
            end)
            repark:SetScript("OnEvent", function(self)
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                Repark()
            end)
            hooksecurefunc(blizzBar, "SetParent", function(self, newParent)
                if EllesmereUI._GetFFD(self).castBarSuppressed and newParent ~= EllesmereUI._playerCastBarHiddenParent then
                    repark:Show()
                end
            end)
        end

        local selection = blizzBar.Selection
        if selection then
            if not EllesmereUI._GetFFD(selection).suppressed then
                EllesmereUI._GetFFD(selection).restoreAlpha = selection:GetAlpha()
                EllesmereUI._GetFFD(selection).restoreMouse = selection:IsMouseEnabled()
            end
            EllesmereUI._GetFFD(selection).suppressed = true
            selection:SetAlpha(0)
            selection:EnableMouse(false)

            if not EllesmereUI._GetFFD(selection).showHooked then
                EllesmereUI._GetFFD(selection).showHooked = true
                hooksecurefunc(selection, "Show", function(self)
                    -- Deferred: Show fires inside Edit Mode's secure ShowSystemSelections pass; write nothing there.
                    C_Timer.After(0, function()
                        if PlayerCastingBarFrame and EllesmereUI._GetFFD(PlayerCastingBarFrame).castBarSuppressed then
                            self:SetAlpha(0)
                            self:EnableMouse(false)
                        end
                    end)
                end)
            end
        end

        return
    end

    EllesmereUI._GetFFD(blizzBar).castBarSuppressed = false

    -- Hand the bar back to the parent EUI took it from -- but never to one that is itself hidden.
    -- Blizzard parents this bar under PlayerFrame, and Edit Mode re-parents it into a layout frame
    -- that gets hidden on exit, while EUI hides PlayerFrame whenever it renders its own player
    -- frame. Restoring there leaves Blizzard's cast bar fully armed but permanently invisible,
    -- which reads exactly like the suppression never lifted. UIParent is where Edit Mode positions the bar from anyway, and SetParent keeps the existing anchors, so the bar still lands where the user had it.
    local origParent = EllesmereUI._GetFFD(blizzBar).origParent
    local currentParent = blizzBar:GetParent()
    local restoreParent = origParent
    if not restoreParent or not restoreParent.IsVisible or not restoreParent:IsVisible() then
        restoreParent = UIParent
    end

    -- Only ever un-park a bar EUI itself parked: either it is still sitting in our hidden parent,
    -- or an earlier release handed it back to the captured parent and that parent is itself
    -- hidden. Matching the captured parent exactly is what separates "Blizzard's own parent
    -- happens to be hidden" from "another addon parked this bar under its own hidden frame" -- the latter is left alone, since resurrecting it is the bug this whole ownership dance exists to prevent.
    local parkedByUs = (hiddenParent and currentParent == hiddenParent)
        or (origParent and currentParent == origParent
            and currentParent.IsVisible and not currentParent:IsVisible())

    -- The Edit Mode gate can skip this; ApplyBlizzCastbarState re-runs the release on
    -- PLAYER_ENTERING_WORLD and on Edit Mode close, so a bar left parked by a skipped pass is healed as soon as re-parenting is legal.
    if parkedByUs and currentParent ~= restoreParent
        and not (EditModeManagerFrame and EditModeManagerFrame:IsShown()) then
        blizzBar:SetParent(restoreParent)
    end

    local selection = blizzBar.Selection
    if selection and EllesmereUI._GetFFD(selection).suppressed then
        EllesmereUI._GetFFD(selection).suppressed = false
        selection:SetAlpha(EllesmereUI._GetFFD(selection).restoreAlpha or 1)
        selection:EnableMouse(EllesmereUI._GetFFD(selection).restoreMouse or false)
    end

    -- Let Blizzard rebuild its normal event wiring without forcing visibility back on, so profile
    -- switches and UnitFrames/oUF teardown stay compatible with Blizzard's own cast bar logic.
    -- Only when EUI silenced the frame in the first place: a standalone cast bar addon silences
    -- the same frame, and re-registering its events is what pops Blizzard's cast bar back on screen next to theirs once EUI's own cast bar is switched off.
    EllesmereUI.RearmBlizzCastBars()
end

-------------------------------------------------------------------------------
--  Swiftmend Brightness Fix (shared hook utility) -- Blizzard dims Swiftmend based on
--  Efflorescence state (secret value in Midnight). Child addons call this on icon textures they identify as Swiftmend; the hook prevents vertex-color dimming and desaturation.
-------------------------------------------------------------------------------
do
    local hooked = {}
    local function isEnabled()
        return not EllesmereUIDB or EllesmereUIDB.brightenSwiftmend ~= false
    end
    function EllesmereUI._HookSwiftmendIcon(tex)
        if not tex or hooked[tex] then
            -- Already hooked; just force bright if re-enabling
            if tex and hooked[tex] and isEnabled() then
                tex:SetVertexColor(1, 1, 1)
            end
            return
        end
        hooked[tex] = true
        local vcGuard = false
        hooksecurefunc(tex, "SetVertexColor", function(_, r, g, b)
            if not vcGuard and isEnabled() and not (r == 1 and g == 1 and b == 1) then
                vcGuard = true
                tex:SetVertexColor(1, 1, 1)
                vcGuard = false
            end
        end)
        -- Force bright immediately (icon may already be dimmed before hook)
        if isEnabled() then tex:SetVertexColor(1, 1, 1) end
    end
    EllesmereUI._SWIFTMEND_SPELL = 18562
    EllesmereUI._SWIFTMEND_ICON  = 134914
end

-------------------------------------------------------------------------------
--  Level difficulty colors (unit frame and nameplate level text), Blizzard's
--  rule: "??" (level <= 0) red, a unit you cannot attack gold, otherwise the
--  color for its level against yours.
-------------------------------------------------------------------------------
function EllesmereUI.GetLevelDifficultyColor(level, attackable)
    if level <= 0 then return 1, 0.1, 0.1 end
    if not attackable then
        local c = UNIT_LEVEL_NON_ATTACKABLE
        if c then return c.r, c.g, c.b end
        return 1, 0.82, 0
    end
    local mine = UnitEffectiveLevel("player")
    if issecretvalue and issecretvalue(mine) then return nil end
    if EllesmereUI.IS_FOREVER then
        -- WoW Forever's own nameplate rule (the vanilla one): grey past the
        -- trivial range, green 3+ below, yellow within 2, orange 3-4 above, red 5+.
        local diff = level - mine
        local fc
        if diff < -C_QuestLog.GetTrivialRange() then fc = TRIVIAL_DIFFICULTY_COLOR
        elseif diff <= -3 then fc = EASY_DIFFICULTY_COLOR
        elseif diff <= 2 then fc = FAIR_DIFFICULTY_COLOR
        elseif diff <= 4 then fc = DIFFICULT_DIFFICULTY_COLOR
        else fc = IMPOSSIBLE_DIFFICULTY_COLOR end
        if fc then return fc.r, fc.g, fc.b end
        return nil
    end
    local c = (GetRelativeDifficultyColor and GetRelativeDifficultyColor(mine, level))
        or (GetQuestDifficultyColor and GetQuestDifficultyColor(level))
    if c then return c.r, c.g, c.b end
end
-- For a unit; nil when the level or attackability cannot be read (secret).
-- includeFriendly: friendly units get their difficulty color too, not gold.
function EllesmereUI.GetLevelColor(unit, level, includeFriendly)
    local sv = issecretvalue
    if level == nil or (sv and sv(level)) then return nil end
    if includeFriendly then return EllesmereUI.GetLevelDifficultyColor(level, true) end
    local attackable = UnitCanAttack("player", unit)
    if sv and sv(attackable) then return nil end
    return EllesmereUI.GetLevelDifficultyColor(level, attackable)
end
function EllesmereUI.ColorText(text, r, g, b)
    if not r then return text end
    return ("|cff%02x%02x%02x%s|r"):format(math.floor(r * 255 + 0.5),
        math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5), text)
end

-------------------------------------------------------------------------------
--  Faction badge art, shared by the unit frame and nameplate faction indicators
--  and their options previews. Each style is a Horde/Alliance pair, an atlas or a
--  file; "%s" takes the faction ("lower" = lowercased, "num" = 1 Horde / 2 Alliance).
--  "coords" crops a file whose art does not fill it (the Classic banner sits in the
--  top-left 42 of 64 pixels).
--  Unknown styles fall back to "pvp", the default.
-------------------------------------------------------------------------------
EllesmereUI.FACTION_ART = {
    pvp       = { atlas = "UI-HUD-UnitFrame-Player-PVP-%sIcon" },
    honor     = { atlas = "honorsystem-portrait-%s", lower = true, badge = true },
    poi       = { atlas = "poi-%s", lower = true },
    classic   = { file = "Interface\\TargetingFrame\\UI-PVP-%s", coords = { 0, 0.65625, 0, 0.65625 } },
    banner    = { file = "Interface\\Icons\\INV_BannerPVP_0%s", num = true },
    honoricon = { file = "Interface\\Icons\\PVPCurrency-Honor-%s" },
    friends   = { file = "Interface\\FriendsFrame\\PlusManz-%s" },
}
EllesmereUI.FACTION_ART_ORDER = { "pvp", "honor", "poi", "classic", "banner", "honoricon", "friends" }
EllesmereUI.FACTION_ART_LABELS = {
    pvp = "PvP Emblem", honor = "Honor Portrait", poi = "Map Flag", classic = "Classic Banner",
    banner = "Banner Icon", honoricon = "Honor Icon", friends = "Friends Crest",
}
-- Honor Portrait is an empty hexagon; the unit's honor badge is drawn on top (30 on 50).
-- Returns that badge's file id, or nil. Callers pass it to SetFactionArt and memoize it.
local HONOR_BADGE_RATIO = 30 / 50
local honorBadgeFiles = {}
function EllesmereUI.FactionBadgeFor(style, unit)
    local art = EllesmereUI.FACTION_ART[style]
    if not (art and art.badge and unit) then return nil end
    local level = UnitHonorLevel and UnitHonorLevel(unit)
    if issecretvalue(level) or not level or level <= 0 then return nil end
    local file = honorBadgeFiles[level]
    if file == nil then
        local info = C_PvP and C_PvP.GetHonorRewardInfo and C_PvP.GetHonorRewardInfo(level)
        file = (info and info.badgeFileDataID) or false
        honorBadgeFiles[level] = file
    end
    return file or nil
end

-- The badge sits on a frame that follows the faction texture (textures cannot be parents);
-- the texture's Show/Hide/alpha/desaturation are mirrored onto it.
local function GetBadgeHost(tex)
    local host = tex._honorBadgeHost
    if host then return host end
    local par = tex:GetParent()
    host = CreateFrame("Frame", nil, par)
    host:SetAllPoints(tex)
    host:SetFrameLevel(par:GetFrameLevel() + 1)
    host:Hide()
    host:SetAlpha(tex:GetAlpha())
    local icon = host:CreateTexture(nil, "OVERLAY")
    icon:SetPoint("CENTER")
    icon:SetDesaturated(tex:IsDesaturated())
    host.icon = icon
    host:SetScript("OnSizeChanged", function(_, w)
        local s = w * HONOR_BADGE_RATIO
        icon:SetSize(s, s)
    end)
    hooksecurefunc(tex, "Hide", function() host:Hide() end)
    hooksecurefunc(tex, "Show", function() if host.wanted then host:Show() end end)
    hooksecurefunc(tex, "SetAlpha", function(_, a) host:SetAlpha(a) end)
    hooksecurefunc(tex, "SetDesaturated", function(_, d) icon:SetDesaturated(d) end)
    tex._honorBadgeHost = host
    return host
end

local function SetBadge(tex, file)
    local host = tex._honorBadgeHost
    if not file then
        if host then host.wanted = false; host:Hide() end
        return
    end
    host = host or GetBadgeHost(tex)
    host.icon:SetTexture(file)
    local w = tex:GetWidth()
    if w and w > 0 then
        local s = w * HONOR_BADGE_RATIO
        host.icon:SetSize(s, s)
    end
    host.wanted = true
    if tex:IsShown() then host:Show() end
end

function EllesmereUI.SetFactionArt(tex, style, faction, badgeFile)
    SetBadge(tex, badgeFile)
    local art = EllesmereUI.FACTION_ART[style] or EllesmereUI.FACTION_ART.pvp
    -- The resolved atlas or file name is built once per style and faction and kept
    -- on the style's entry (art.Horde / art.Alliance).
    local name = art[faction]
    if not name then
        local key = faction
        if art.lower then
            key = faction:lower()
        elseif art.num then
            key = (faction == "Horde") and "1" or "2"
        end
        name = (art.atlas or art.file):format(key)
        art[faction] = name
    end
    if art.atlas then
        -- SetAtlas keeps an earlier SetTexCoord (e.g. the Classic banner's crop)
        -- unless told to reset it, so clear it first and ask for the reset too.
        tex:SetTexCoord(0, 1, 0, 1)
        tex:SetAtlas(name, false, nil, true)
    else
        tex:SetTexture(name)
        local c = art.coords
        if c then tex:SetTexCoord(c[1], c[2], c[3], c[4]) else tex:SetTexCoord(0, 1, 0, 1) end
    end
end

-------------------------------------------------------------------------------
--  Secret values (12.1): the one test every module uses, and the string reader
--  that gives back a readable, non-empty string or nil. Hot paths import both
--  as locals; no module keeps a copy.
-------------------------------------------------------------------------------
local issecretvalue = issecretvalue or function() return false end
function EllesmereUI.IsSecret(v)
    return v ~= nil and issecretvalue(v)
end
function EllesmereUI.PlainString(v)
    -- The secrecy test comes first: comparing a secret string raises.
    if type(v) == "string" and not issecretvalue(v) and v ~= "" then return v end
    return nil
end

-------------------------------------------------------------------------------
--  Guard table of a split module: the main file's names that its part files
--  re-import. setters maps Set<Name> to a list in t; Set<Name>(v) hands v to
--  every function in that list, and a function added to the list after a
--  Set<Name> call gets the last value at once (registered as
--  list[#list + 1] = fn: table.insert sets raw and skips that). broken starts
--  false (a file chain that guards on t.last ignores it). Reading a name the
--  table lacks raises at the reader; label names the owner in that message
--  (default "ns"). The parent's own chain calls the private copy on EUI_NS, so
--  the parent's namespace never passes through a public slot.
-------------------------------------------------------------------------------
do
    local function NewFanOut(list)
        local has, cur = false, nil
        setmetatable(list, { __newindex = function(l, i, fn)
            rawset(l, i, fn)
            if has then fn(cur) end
        end })
        return function(v)
            has, cur = true, v
            for i = 1, #list do list[i](v) end
        end
    end

    local function NewInternals(ns, field, t, setters, label)
        local name = (label or "ns") .. "." .. field
        if setters then
            for setter, listName in pairs(setters) do
                local list = t[listName]
                if type(list) ~= "table" then
                    error(name .. ": " .. setter .. " has no list " .. tostring(listName), 2)
                end
                t[setter] = NewFanOut(list)
            end
        end
        t.broken = false
        ns[field] = setmetatable(t, { __index = function(_, k)
            error(name .. " has no entry " .. tostring(k), 2)
        end })
        return ns[field]
    end
    EUI_NS.NewInternals = NewInternals
    EllesmereUI.NewInternals = NewInternals
end
