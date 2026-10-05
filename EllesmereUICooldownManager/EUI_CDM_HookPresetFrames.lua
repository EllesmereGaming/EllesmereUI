if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_CDM_HookPresetFrames.lua
--
--  Preset and custom frames, out of range coloring, Always Show Buffs
--  placeholders and empty slots.
--  Reads the earlier hook files through ns and ns._hookInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._hookInternals
-- EllesmereUICdmHooks.lua or an earlier hook file failed to load.
if not I or I.broken then return end
I.broken = true

local barDataByKey = ns.barDataByKey
local cdmBarFrames = ns.cdmBarFrames
local GetCDMFont = ns.GetCDMFont
local _ecmeFC = ns._ecmeFC

-------------------------------------------------------------------------------
--  Preset/Custom Frames
-------------------------------------------------------------------------------
local _presetFrames = {}
ns._presetFrames = _presetFrames

-- Aura-tracked custom buffs: the WHOLE subsystem lives in one table (_AC)
-- because this file rides the Lua 5.1 200-local cap. bars: barKey ->
-- { holder, container, sids, sig, queued, bdRef, hookedBar }.
--
-- FINAL SHAPE (field-settled 2026-08-08): customs render in ONE engine flow
-- container per bar -- PURE ENGINE, zero Lua per aura event. Under 12.1
-- secrecy (M+/raid combat -- the normal state for our users) Lua can NEVER
-- know whether these auras are active (RequiresNonSecretAura: "protected
-- APIs will return no values"), so customs can never join the bar's own
-- icon row: in-bar mixing needs a Lua-known count. Both workarounds were
-- field-rejected (reserved grey slots push real buffs off center;
-- tail-injection reads off center on centered bars). The engine, however,
-- sizes and CENTERS its own content under full secrecy, so the container
-- hangs off the bar GROWTH-AWARE: directional bars get a tail flowing off
-- the growth edge (reads as the bar simply extending), CENTER bars get a
-- centered strip below/above (the only centered shape physics allows).
-- Actives compact engine-side; when none are up it renders nothing.
--
-- The container lives on a UIParent-anchored holder: engine aura buttons
-- are FORBIDDEN objects, and any anchor path from the bar to them
-- restriction-locks the bar's own geometry (field-proven: the bar stopped
-- re-centering). The holder follows the bar via SetPoint/OnSizeChanged/
-- OnShow/OnHide post-hooks on our own bar frame, coalesced one frame.
local _AC = { bars = {}, syncPending = {} }

-- Position a bar's holder from its CURRENT rect + growth settings. The
-- container point (set at build) mirrors these anchors so the engine flows
-- away from the bar / centers under it.
function _AC.Anchor(barKey, rec)
    local barFrame = cdmBarFrames[barKey]
    local holder = rec and rec.holder
    if not (barFrame and holder) then return end
    holder:SetShown(barFrame:IsShown())
    -- Visibility rules and bar opacity hide the bar through ALPHA on the bar
    -- frame and its own icons; this holder is UIParent-parented and inherits
    -- none of it, so mirror the bar's effective alpha here: 0 while the bar
    -- is visibility-hidden, else its opacity / out-of-combat fade.
    local bdA = (ns.barDataByKey and ns.barDataByKey[barKey]) or rec.bdRef
    holder:SetAlpha(barFrame._visHidden and 0
        or ((ns.EffectiveBarAlpha and ns.EffectiveBarAlpha(bdA)) or 1))
    holder:ClearAllPoints()
    local ok, bl, bb, bw, bh = pcall(barFrame.GetRect, barFrame)
    if not (ok and bl) then
        holder:SetPoint("CENTER", UIParent, "BOTTOMLEFT", -10000, -10000)
        return
    end
    local bd = rec.bdRef
    local gap = (bd and bd.spacing) or 2
    local grow = (bd and bd.growDirection) or "CENTER"
    local cx, cy = bl + bw / 2, bb + bh / 2
    -- END-OF-BAR TAIL for every growth mode (user-directed): customs flow
    -- off the bar's end -- left-grow bars extend left, everything else
    -- extends right; vertical bars extend past their up/down end.
    --
    -- EMPTY BAR (live content width 0, published by LayoutCDMBar -- the
    -- bar's own rect is deliberately stale then): the tail BECOMES the bar.
    -- CENTER-grow bars center the strip ON the bar's position (container
    -- point flips to CENTER so the engine centers it); directional bars
    -- seat it at the FIXED growth edge -- exactly where the first real
    -- buff would render.
    local empty = (barFrame._acLiveW ~= nil and barFrame._acLiveW <= 0.5)
    local wantPt = (empty and grow == "CENTER") and "CENTER" or rec.pt
    if rec.container and wantPt and rec.curPt ~= wantPt then
        rec.curPt = wantPt
        rec.container:ClearAllPoints()
        rec.container:SetPoint(wantPt)
    end
    if bd and bd.verticalOrientation then
        if grow == "UP" then
            holder:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", cx, empty and bb or (bb + bh + gap))
        elseif empty and grow == "CENTER" then
            holder:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
        else
            holder:SetPoint("TOP", UIParent, "BOTTOMLEFT", cx, empty and (bb + bh) or (bb - gap))
        end
    elseif grow == "LEFT" then
        holder:SetPoint("RIGHT", UIParent, "BOTTOMLEFT", empty and (bl + bw) or (bl - gap), cy)
    elseif empty and grow == "CENTER" then
        holder:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
    else
        holder:SetPoint("LEFT", UIParent, "BOTTOMLEFT", empty and bl or (bl + bw + gap), cy)
    end
end

-- LayoutCDMBar pokes the tail on EVERY pass (empty path included): count
-- transitions can land on identical geometry (no size/point events), and
-- the empty<->occupied mode flip must never be missed.
function ns._AuraCustomPoke(barKey)
    if _AC.bars[barKey] then _AC.MarkSync(barKey) end
end

-- Coalesced holder re-anchoring, driven by the bar-frame hooks.
_AC.frame = CreateFrame("Frame")
_AC.frame:Hide()
_AC.frame:SetScript("OnUpdate", function(self)
    self:Hide()
    for barKey in pairs(_AC.syncPending) do
        _AC.syncPending[barKey] = nil
        _AC.Anchor(barKey, _AC.bars[barKey])
    end
end)

function _AC.MarkSync(barKey)
    if _AC.syncPending[barKey] then return end
    _AC.syncPending[barKey] = true
    _AC.frame:Show()
end

-- LIVE SET for the preset drain: only the frames ProcessPresetCooldowns and the hot
-- listener loops actually work on (SHOWN racial/custom-spell/item preset frames;
-- custom-BUFF frames are excluded, never register here). _presetFrames above is the
-- permanent identity/reuse map and MUST NEVER BE PRUNED: a pruned key would make the
-- create-only sites build a NEW frame object on the next inject and leak the old one
-- (WoW frames are unreclaimable) -- it grows with every distinct config touched in a
-- session, so the drain iterates this LIVE set instead (reuse-map growth costs
-- nothing). OnShow/OnHide track the frame's own shown flag, matching the old
-- IsShown() gate exactly (alpha/parent-only hiding behaves identically).
local _pcActive = {}

-------------------------------------------------------------------------------
--  Out of Range Coloring for spells added by Spell ID (opt-in, per spell).
--
--  Blizzard's viewer frames tint themselves out of range; a spell added by ID
--  has no viewer frame, so its own-frame icon never did. Mirrors
--  CooldownViewerCooldownItemMixin: the check (C_Spell.EnableSpellRangeCheck)
--  is armed on the icon's Show only when the spell has a range, range is read
--  once there, then only SPELL_RANGE_CHECK_UPDATE repaints (the engine
--  re-dispatches it across target changes), and out of range outranks the
--  resource tint. Override edges (SPELL_UPDATE_ICON,
--  COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED, SPELLS_CHANGED) re-point the check
--  at the live form. The preset pass only paints the stored answer. Writes go
--  to our own texture only. Zero cost unless a spell opts in: nothing is
--  armed, the listener shell is taken on the first opted Show, and its events
--  drop when the last opted icon hides.
--
--  Registrations are per SPELL and shared with Blizzard's viewer and the
--  override arming in EUI_CDM_Rotation.lua: a release never disables an id either of
--  them still holds, and CustomSpellRangeHolds is the same rule from their side.
-------------------------------------------------------------------------------
do
    local refs = {}      -- armed spell id -> number of frames holding it
    local armCount = 0   -- shown opted frames (armed, or on a form with no range); the listener is live while > 0
    local listener

    function ns.CustomSpellRangeHolds(spellID)
        return refs[spellID] ~= nil
    end

    -- Custom-spell icon tint: out of range first (Blizzard's RefreshIconColor
    -- order), else the resource dim. The range tint is written RGBA as Blizzard
    -- writes it; the dim keeps its 3-arg writes.
    local function PaintTint(f, sid, onRealCD)
        local tex = f._tex
        if not tex then return end
        if f._rangeOut then
            -- Out of range the icon is range-driven: the dim memo goes (left set, it
            -- would hold the drain unsettled after the spell turned usable) and the
            -- tint write is edge-gated. PaintTint is the only colour writer here.
            f._lastVertexDim = nil
            if not f._rangeTinted then
                local c = CooldownViewerConstants and CooldownViewerConstants.ITEM_NOT_IN_RANGE_COLOR
                if c then
                    tex:SetVertexColor(c:GetRGBA())
                    f._rangeTinted = true
                end
            end
            return
        end
        -- Leaving the range tint needs a white write even when the dim memo is clean.
        local wasTinted = f._rangeTinted
        if wasTinted then f._rangeTinted = nil end
        if not onRealCD then
            local isUsable, notEnoughMana = C_Spell.IsSpellUsable(sid)
            if notEnoughMana then
                tex:SetVertexColor(0.5, 0.5, 1.0)
            elseif not isUsable then
                tex:SetVertexColor(0.4, 0.4, 0.4)
            elseif f._lastVertexDim or wasTinted then
                tex:SetVertexColor(1, 1, 1)
            end
            f._lastVertexDim = (not isUsable) or nil
        elseif f._lastVertexDim or wasTinted then
            tex:SetVertexColor(1, 1, 1)
            f._lastVertexDim = nil
        end
    end
    ns.PaintCustomSpellTint = PaintTint

    -- Out of range is a readable false only: nil (no target) and a secret answer
    -- both read as in range.
    local function ReadOut(id)
        local r = C_Spell.IsSpellInRange(id)
        if not (issecretvalue and issecretvalue(r)) and r == false then return true end
        return nil
    end

    -- Apply one out-of-range flip and repaint (every caller is an edge: Show,
    -- range event, override edge, options). A repaint that lands dimmed wakes
    -- the drain: the write happened outside the pass, and a dim is only polled
    -- for its usable edge while the drain is awake.
    local function SetRangeOut(f, out)
        if f._rangeOut == out then return end
        f._rangeOut = out
        local sid = f._cachedPresetSID
        if sid then
            PaintTint(f, sid, f._lastOnRealCD)
            if f._lastVertexDim then ns._MarkPresetCdDirty() end
        end
    end

    local function OnRangeEvent(_, event, spellID)
        local named = not (issecretvalue and issecretvalue(spellID))
            and type(spellID) == "number"
        if event == "SPELL_RANGE_CHECK_UPDATE" then
            -- Blizzard's own registrations are nearly every dispatch, so a readable
            -- id no icon here armed returns before any frame is touched. An
            -- unreadable id (instanced secrecy) re-reads every armed frame. Only
            -- the in/out answer is re-read: arming stays with Sync.
            if named and not refs[spellID] then return end
            for f in pairs(_pcActive) do
                local armed = f._rangeArmedSID
                if armed and (not named or armed == spellID) then
                    SetRangeOut(f, ReadOut(armed))
                end
            end
            return
        end
        -- Override edges re-point the opted icons at their live form. The icon
        -- and override events name the base spell (nil = every spell);
        -- SPELLS_CHANGED names none.
        for f in pairs(_pcActive) do
            if f._rangeOpted and (not named or f._cachedPresetSID == spellID) then
                ns.SyncCustomSpellRange(f)
            end
        end
    end

    -- Hold or drop one frame's opt-in and its armed id. id is the live form to
    -- arm, nil while that form has no range: an opted frame stays on the
    -- override edges either way, so a form that gains a range arms. The range
    -- event itself is held only while some id is armed.
    local function SetArm(f, id, opted)
        opted = opted or nil
        if f._rangeOpted ~= opted then
            f._rangeOpted = opted
            armCount = armCount + (opted and 1 or -1)
            if opted and armCount == 1 then
                if not listener then
                    listener = ns.TakeShell()
                    listener:SetScript("OnEvent", OnRangeEvent)
                end
                listener:RegisterEvent("SPELL_UPDATE_ICON")
                listener:RegisterEvent("COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED")
                listener:RegisterEvent("SPELLS_CHANGED")
            elseif armCount == 0 and listener then
                listener:UnregisterAllEvents()
            end
        end
        local prev = f._rangeArmedSID
        if prev == id then return end
        local hadArm = next(refs) ~= nil
        f._rangeArmedSID = id
        if prev then
            local n = (refs[prev] or 1) - 1
            refs[prev] = (n > 0) and n or nil
            if not refs[prev] and not ns.BlizzardArmsRange(prev) then
                local held = false
                if ns._oorArmed then
                    for _, ov in pairs(ns._oorArmed) do
                        if ov == prev then held = true; break end
                    end
                end
                if not held then C_Spell.EnableSpellRangeCheck(prev, false) end
            end
        end
        if id then
            if not refs[id] then C_Spell.EnableSpellRangeCheck(id, true) end
            refs[id] = (refs[id] or 0) + 1
        end
        local hasArm = next(refs) ~= nil
        if hasArm ~= hadArm then
            if hasArm then
                listener:RegisterEvent("SPELL_RANGE_CHECK_UPDATE")
            else
                listener:UnregisterEvent("SPELL_RANGE_CHECK_UPDATE")
            end
        end
    end

    -- Resolve one custom-spell frame: hold or drop its opt-in, arm, re-point
    -- (live override) or release its range check, then read range once.
    -- Called on edges only: Show, override edges and the options toggle.
    function ns.SyncCustomSpellRange(f)
        local sid = f._cachedPresetSID
        if not sid then
            local m = f._pfKey and f._pfKey:match(":(%d+)$")
            sid = m and tonumber(m)
            f._cachedPresetSID = sid
        end
        local want, opted
        local cas = sid and ns._cdmAnyCustomRangeColor and ns.GetEffectiveCustomActiveState(sid)
        if cas and cas.outOfRangeColoring then
            opted = true
            local ovr = C_SpellBook.FindSpellOverrideByID(sid)
            local live = (ovr and ovr > 0) and ovr or sid
            if C_Spell.SpellHasRange(live) then want = live end
        end
        SetArm(f, want, opted)
        SetRangeOut(f, want and ReadOut(want) or nil)
    end

    function ns.ReleaseCustomSpellRange(f)
        SetArm(f, nil, nil)
    end

    -- Options toggle (and the gate latching on): re-resolve every shown
    -- custom-spell icon right away.
    function ns.RefreshCustomSpellRange()
        for f in pairs(_pcActive) do
            if f._isCustomSpellFrame and not f._isCustomBuffFrame then
                ns.SyncCustomSpellRange(f)
            end
        end
    end
end

local function _RegisterPresetLive(f, fkey)
    f._pfKey = fkey
    f:HookScript("OnShow", function(self)
        _pcActive[self] = true
        -- Show is a state edge (events may have fired while hidden):
        -- re-read and re-push everything on the next pass.
        self._cdPushArm = true
        if self._isItemPresetFrame then
            self._itemWalkArm = true
            self._countArm = true
        end
        -- Out of Range Coloring arms (or re-arms) on this edge.
        if ns._cdmAnyCustomRangeColor and self._isCustomSpellFrame
           and not self._isCustomBuffFrame then
            ns.SyncCustomSpellRange(self)
        end
        if ns._MarkPresetCdDirty then ns._MarkPresetCdDirty() end
    end)
    f:HookScript("OnHide", function(self)
        _pcActive[self] = nil
        -- A hidden icon holds no range registration; its Show re-arms it.
        if self._rangeOpted then ns.ReleaseCustomSpellRange(self) end
    end)
    if f:IsShown() then _pcActive[f] = true end
end

-------------------------------------------------------------------------------
--  Always Show Buffs placeholders
--  Our-owned icon frames that hold an INACTIVE tracked buff's slot so the buff
--  "always shows" (greyed) without editing Blizzard's Edit Mode layout. Mirrors
--  _presetFrames (a UIParent Frame + .Icon + .Cooldown) so the existing
--  DecorateFrame / LayoutCDMBar pipeline styles and positions them like any
--  real icon. Keyed barKey:ph:spellID. Never armed with a cooldown (no strobe).
-------------------------------------------------------------------------------
local _placeholderFrames = {}
ns._placeholderFrames = _placeholderFrames

-- Hide every placeholder. Called once at the start of each collect pass; the
-- pass then re-shows only the placeholders it injects, so a placeholder whose
-- buff went active, or whose bar was toggled off/disabled, ends up hidden.
local function HideAllPlaceholders()
    for _, f in pairs(_placeholderFrames) do
        if f:IsShown() then f:Hide() end
    end
end
ns.HideAllPlaceholders = HideAllPlaceholders

-- Injected custom/preset buff own-frames (buff-family bars). Tracked so the
-- collect pass can hide them all up front and re-show only the active ones,
-- exactly like placeholders -- the buff-phase cleanup loops only disable swipe
-- (correct for Blizzard pool frames, which must never be Hidden), so OUR frames
-- need their own hide pass or an inactive/expired/orphaned one would linger.
local _injectedCustomBuffFrames = setmetatable({}, { __mode = "k" })
local function HideAllInjectedCustomBuffs()
    for f in pairs(_injectedCustomBuffFrames) do
        if f:IsShown() then f:Hide() end
    end
end
ns.HideAllInjectedCustomBuffs = HideAllInjectedCustomBuffs

-- Spellbook name -> first known castable id with that name. A tracked-buff slot
-- holds AURA ids, and an aura carries no link back to the spell that applies it
-- (every identity API is a fixed point on it), while the CASTABLE side is where
-- the talent override lives; an aura and its caster share a name, so the book is
-- the only available bridge. Built on first use, dropped on talent change (the
-- override it feeds is talent-dependent). An EMPTY result is treated as "not
-- built yet" rather than cached: the first placeholder can resolve before the
-- spellbook populates at login, and caching that would strand the bridge until
-- the next talent change (a real character always has spells, so empty only
-- means too early). A pcall failure IS cached, since a missing API won't start working.
local _bookByName
local function EnsureBookNameMap()
    if not _bookByName then
        local built = {}
        local ok = pcall(function()
            local nLines = C_SpellBook.GetNumSpellBookSkillLines()
            for i = 1, (nLines or 0) do
                local li = C_SpellBook.GetSpellBookSkillLineInfo(i)
                if li and li.itemIndexOffset and li.numSpellBookItems then
                    for j = li.itemIndexOffset + 1, li.itemIndexOffset + li.numSpellBookItems do
                        local it = C_SpellBook.GetSpellBookItemInfo(j, Enum.SpellBookSpellBank.Player)
                        local bsid = it and it.spellID
                        if bsid then
                            local nm = C_Spell.GetSpellName(bsid)
                            if nm and built[nm] == nil then built[nm] = bsid end
                        end
                    end
                end
            end
        end)
        if not ok then
            _bookByName = {}
        elseif next(built) then
            _bookByName = built
        else
            return built  -- too early; retry on the next call
        end
    end
    return _bookByName
end
local function BookIDForName(name)
    if type(name) ~= "string" or name == "" then return nil end
    return EnsureBookNameMap()[name]
end
ns.WipeCdmBookNameCache = function() _bookByName = nil end
ns.CdmBookIDForName = BookIDForName
ns.CdmBookNameCount = function()
    local n = 0
    for _ in pairs(EnsureBookNameMap()) do n = n + 1 end
    return n
end

-- Resolve the spell whose ICON an inactive placeholder should paint. An ACTIVE
-- buff frame renders the live aura, so a talent that REPLACES a spell shows the
-- replacement (e.g. Hellcaller: Wither); an INACTIVE frame has no aura to read
-- and falls back to cooldownInfo, which still names the pre-talent spell, so the
-- same icon changes art as the aura comes and goes. Two ways a replacement can
-- show up, tried in order: (1) something in the slot's identity set (resolved
-- id, cooldownInfo's base, override or linked ids) is itself overridden --
-- covers CASTABLE-keyed slots; (2) nothing is overridden, the normal state for a
-- tracked-buff slot, since it holds AURA ids and an aura carries no override
-- even when a talent replaces the spell behind it (e.g. Destruction's Immolate
-- slot resolves to aura 157736, reports overrideSpellID == spellID, and merely
-- LISTS Wither's aura 445474 as a link) -- fall back to the spellbook, matching
-- by name. Returns sid untouched when neither applies (every spec without a
-- replacing talent). Callers use the result for ART ONLY: identity, pooling and settings resolution stay keyed on the original id.
local function ResolvePlaceholderIconSID(sid, cdID)
    local FO = C_SpellBook and C_SpellBook.FindSpellOverrideByID
    if not FO or type(sid) ~= "number" or sid <= 0 then return sid end
    if issecretvalue and issecretvalue(sid) then return sid end

    local function TryID(id)
        if type(id) ~= "number" or id <= 0 then return nil end
        if issecretvalue and issecretvalue(id) then return nil end
        local o = FO(id)
        if type(o) == "number" and o > 0 and o ~= id then return o end
        return nil
    end

    local hit = TryID(sid)
    if hit then return hit end

    local gci = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
    local info = (cdID ~= nil and gci) and gci(cdID) or nil
    if info then
        hit = TryID(info.spellID) or TryID(info.overrideSpellID)
        if hit then return hit end
        if info.linkedSpellIDs then
            for _, lid in ipairs(info.linkedSpellIDs) do
                hit = TryID(lid)
                if hit then return hit end
            end
        end
    end

    -- Nothing in the slot is overridden, the normal state for a tracked-buff slot
    -- (it holds aura ids, and auras carry no override even when a talent replaces
    -- the spell behind them, e.g. Hellcaller's Immolate slot reports
    -- overrideSpellID == spellID and merely LISTS Wither's aura as a link).
    -- Bridge to the castable by name and take ITS live override, where the
    -- replacement actually shows up. One spellbook scan per talent change; no-op without a replacing talent.
    local NameOf = C_Spell and C_Spell.GetSpellName
    local nm = NameOf and NameOf(sid)
    local castable = BookIDForName(nm)
    if castable then
        local o = FO(castable)
        if type(o) == "number" and o > 0 and o ~= castable then return o end
    end

    -- The spellbook lists the REPLACEMENT rather than the base, so a replaced
    -- spell's name can be absent from it entirely and the lookup above finds
    -- nothing to follow; the test then inverts: when a LINKED variant's name is
    -- in the book and this slot's own name is not, the linked form is what the
    -- player actually casts (requiring the slot's name to be absent keeps this
    -- from firing while both forms are available). Return the BOOK id, not the
    -- linked id: a linked id is the variant's AURA (Wither's DoT 445474) while
    -- the book id is the CASTABLE the player actually has (Wither 445468), and
    -- the two carry different art (returning an aura here painted a flicker
    -- across a hero-talent swap, since the castable branch above returns a castable too).
    if info and info.linkedSpellIDs and not castable then
        for _, lid in ipairs(info.linkedSpellIDs) do
            if type(lid) == "number" and lid > 0
               and not (issecretvalue and issecretvalue(lid)) then
                local book = BookIDForName(NameOf and NameOf(lid))
                if book then return book end
            end
        end
    end
    return sid
end
ns.ResolvePlaceholderIconSID = ResolvePlaceholderIconSID

-- identKey: optional pooling identity, defaulting to spellID. Buff
-- placeholders pass one so two viewer slots that collide on spellID do not
-- share a single pooled frame (see the collision note at the call site).
local function GetOrCreatePlaceholderFrame(barKey, spellID, iconID, identKey)
    local fkey = barKey .. ":ph:" .. tostring(identKey or spellID)
    local f = _placeholderFrames[fkey]
    if not f then
        f = CreateFrame("Frame", nil, UIParent)
        f:SetSize(36, 36); f:Hide()
        f:EnableMouse(true)
        if f.SetMouseClickEnabled then f:SetMouseClickEnabled(false) end
        local tex = f:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints(); ns.CdmOwnIconCrop(tex)
        f.Icon = tex; f._tex = tex
        local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
        cd:SetAllPoints(); cd:SetDrawEdge(false); cd:SetDrawBling(false)
        cd:SetHideCountdownNumbers(true); cd:EnableMouse(false)
        if cd.SetMouseClickEnabled then cd:SetMouseClickEnabled(false) end
        if cd.SetMouseMotionEnabled then cd:SetMouseMotionEnabled(false) end
        cd:Clear()  -- permanent placeholder: never arm a 0-duration swipe (strobe)
        f.Cooldown = cd; f._cooldown = cd
        f._isPlaceholderFrame = true
        f._phSpellID = spellID
        -- Never claimed/routed like a Blizzard frame; carries no live aura state.
        f.cooldownID = nil; f.cooldownInfo = nil
        f.auraInstanceID = nil; f.wasSetFromAura = nil
        f:SetScript("OnEnter", function(self)
            local ffc = _ecmeFC[self]
            local bd2 = ffc and ffc.barKey and barDataByKey[ffc.barKey]
            if not bd2 or not bd2.showTooltip then return end
            if not self._phSpellID then return end
            -- A placeholder that renders at alpha 0 has nothing under the
            -- cursor to describe: "Keep Buffs in Same Place"
            -- (bd2.hidePlaceholderIcon) and hosted "Visibility When Missing:
            -- Hidden" (_missingHidden) both reserve the slot invisibly, so the
            -- buff is NOT active and its tooltip must stay down. Same pair of
            -- flags the three opacity passes test before forcing alpha 0.
            if bd2.hidePlaceholderIcon or self._missingHidden then return end
            -- Honor the global "Show Tooltips" visibility mode (Blizzard Skin).
            if EllesmereUI and EllesmereUI._tooltipSuppressedByMode
               and EllesmereUI._tooltipSuppressedByMode(GameTooltip) then return end
            GameTooltip_SetDefaultAnchor(GameTooltip, self)
            GameTooltip:SetSpellByID(self._phSpellID)
            if EllesmereUI and EllesmereUI._repointTooltipAtCursor then
                EllesmereUI._repointTooltipAtCursor(GameTooltip)
            end
            GameTooltip:Show()
        end)
        f:SetScript("OnLeave", GameTooltip_Hide)
        _placeholderFrames[fkey] = f
    end
    -- Re-assert on reuse: a pooled frame outlives a talent swap, so the id it
    -- was created with can name the pre-talent spell (its tooltip would still
    -- read Immolate on a Hellcaller Wither slot).
    f._phSpellID = spellID
    if iconID then f._tex:SetTexture(iconID) end
    return f
end

-- Own-frame for a custom/preset buff (cast-timer driven) on a buff-family bar.
-- Created once per (barKey, spellID); reused across reanchors. Mirrors the frame
-- the legacy custom_buff renderer builds, but the buff-phase injection drives its
-- cooldown swipe and lets CollectAndReanchor slot it next to Blizzard buff frames.
-- OnCooldownDone queues a reanchor so the expired buff drops out of the layout.
local function GetOrCreateCustomBuffFrame(barKey, sid)
    local fkey = barKey .. ":custombuff:" .. sid
    local f = _presetFrames[fkey]
    if not f then
        f = CreateFrame("Frame", nil, UIParent)
        f:SetSize(36, 36); f:Hide()
        f:EnableMouse(false)
        local tex = f:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints(); ns.CdmOwnIconCrop(tex)
        f.Icon = tex; f._tex = tex
        local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
        cd:SetAllPoints(); cd:SetDrawEdge(false); cd:SetDrawBling(false)
        cd:SetReverse(true)
        f.Cooldown = cd; f._cooldown = cd
        f._isCustomSpellFrame = true
        f._isCustomBuffFrame = true
        f.cooldownID = nil; f.cooldownInfo = nil
        cd:HookScript("OnCooldownDone", function()
            -- Re-lay-out the bar so the expired buff is removed. Also poke the
            -- legacy custom_buff updater (harmless for buff bars).
            if ns.QueueCustomBuffUpdate then C_Timer.After(0, ns.QueueCustomBuffUpdate) end
            if ns.QueueReanchor then C_Timer.After(0, ns.QueueReanchor) end
        end)
        local iconSID = ns.LustPresetIconSpellID and ns.LustPresetIconSpellID(sid) or sid
        local spInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(iconSID)
        if spInfo and spInfo.iconID and f._tex then f._tex:SetTexture(spInfo.iconID) end
        _presetFrames[fkey] = f
        _injectedCustomBuffFrames[f] = true
    end
    return f
end
ns.GetOrCreateCustomBuffFrame = GetOrCreateCustomBuffFrame

-- Own-frame for an item (icon + item cooldown + bag count), shared by the
-- CD/utility injection (Phase 3) and the buff-family injection. Created once per
-- (barKey, itemID). Uses the preset icon when known, else the live item icon for
-- arbitrary user-added IDs. Returns nil if the icon isn't loaded yet.
local function GetOrCreateItemPresetFrame(barKey, itemID)
    local fkey = barKey .. ":item:" .. itemID
    local f = _presetFrames[fkey]
    if f then return f end

    local itemPresets = ns.CDM_ITEM_PRESETS
    local preset
    if itemPresets then
        for _, pr in ipairs(itemPresets) do
            if pr.itemID == itemID then preset = pr; break end
            if pr.altItemIDs then
                for _, alt in ipairs(pr.altItemIDs) do
                    if alt == itemID then preset = pr; break end
                end
            end
        end
    end
    local icon = preset and preset.icon or C_Item.GetItemIconByID(itemID)
    if not icon then return nil end

    f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(36, 36); f:Hide()
    -- Enable mouse motion (OnEnter/OnLeave) for tooltips but pass through clicks.
    f:EnableMouse(true)
    if f.SetMouseClickEnabled then f:SetMouseClickEnabled(false) end
    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(); tex:SetTexture(icon)
    ns.CdmOwnIconCrop(tex)
    f.Icon = tex; f._tex = tex
    local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    cd:SetAllPoints(); cd:SetDrawEdge(false); cd:SetDrawBling(false)
    cd:SetHideCountdownNumbers(true)
    cd:EnableMouse(false)
    if cd.SetMouseClickEnabled then cd:SetMouseClickEnabled(false) end
    if cd.SetMouseMotionEnabled then cd:SetMouseMotionEnabled(false) end
    -- Item cooldowns fire no event when they naturally expire, so the
    -- desaturation pass (ProcessPresetCooldowns) wouldn't re-run at the ready
    -- edge and the icon would stay greyed until some unrelated event marked it
    -- dirty (the CD-ready glow polls continuously and lights up instantly, so
    -- without this the pot glows while still desaturated). Poke the processor at
    -- the expiry edge so the next tick re-evaluates count/CD/lockout (a plain
    -- re-saturate would be wrong when the last charge was just used -- total==0 must keep it greyed).
    cd:SetScript("OnCooldownDone", function()
        if ns._MarkPresetCdDirty then ns._MarkPresetCdDirty() end
    end)
    f.Cooldown = cd; f._cooldown = cd
    f._isItemPresetFrame = true
    f._presetItemID = itemID; f._presetData = preset
    f.cooldownID = nil; f.cooldownInfo = nil
    f.layoutIndex = 99999
    local countFS = f:CreateFontString(nil, "OVERLAY")
    EllesmereUI.ApplyIconTextFont(countFS, GetCDMFont(), 11, "cdm")
    countFS:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 2)
    f._itemCountText = countFS
    f:SetScript("OnEnter", function(self)
        if not self._presetItemID then return end
        local ffc = _ecmeFC[self]
        local bd2 = ffc and ffc.barKey and barDataByKey[ffc.barKey]
        if not bd2 or not bd2.showTooltip then return end
        -- Honor the global "Show Tooltips" visibility mode (Blizzard Skin).
        if EllesmereUI and EllesmereUI._tooltipSuppressedByMode
           and EllesmereUI._tooltipSuppressedByMode(GameTooltip) then return end
        GameTooltip_SetDefaultAnchor(GameTooltip, self)
        -- Pot presets tooltip the resolved display variant (may be another
        -- rank / Fleeting / the swapped-in partner pot), not the primary.
        -- Other presets tooltip the first owned family member (the id the
        -- count walk points _itemCdSource at), so a warlock holding only a
        -- Demonic Healthstone sees that stone; nothing owned -> the primary.
        local tipID = self._displayItemID
        if not tipID then
            local _, owned = ns._ReadItemPresetCount(self)
            tipID = owned
        end
        GameTooltip:SetItemByID(tipID or self._presetItemID)
        -- Re-assert the cursor anchor after content is set (item setters can drop
        -- it under "Anchor to Cursor", leaving the tip invisible). No-op otherwise.
        if EllesmereUI and EllesmereUI._repointTooltipAtCursor then
            EllesmereUI._repointTooltipAtCursor(GameTooltip)
        end
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", GameTooltip_Hide)
    _presetFrames[fkey] = f
    _RegisterPresetLive(f, fkey)
    return f
end
ns.GetOrCreateItemPresetFrame = GetOrCreateItemPresetFrame

-------------------------------------------------------------------------------
--  Empty Slot: a purely decorative placeholder that reserves one grid position
--  with nothing drawn (no texture, no cooldown, no border) -- true blank space,
--  so a bar can visually group its icons. One frame per marker (unique per Add,
--  see ns.NewEmptySlotMarker), reused across reanchors like every other custom
--  frame. Never registered with _RegisterPresetLive: it has no cooldown to poll
--  (zero cost beyond the one-time frame creation).
-------------------------------------------------------------------------------
local function GetOrCreateEmptySlotFrame(marker)
    local fkey = "emptyslot:" .. marker
    local f = _presetFrames[fkey]
    if f then return f end

    f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(36, 36); f:Hide()
    f:EnableMouse(false)
    f._isEmptySlotFrame = true
    f.cooldownID = nil; f.cooldownInfo = nil
    f.layoutIndex = 99999
    _presetFrames[fkey] = f
    return f
end
ns.GetOrCreateEmptySlotFrame = GetOrCreateEmptySlotFrame

-- Crafted-quality pip for item frames -- the action bars' Show Rank Icon, for
-- CDM. Those read C_ActionBar.GetProfessionQualityInfo, which needs an action
-- slot; an item frame has only an item id, so this asks the item-side call that
-- returns the same CraftingQualityInfo struct, and takes iconInventory off it
-- exactly as the action bars do. Blizzard's own callers pass a LINK rather than
-- a bare id (and the action bar work recorded bare-id reads coming back nil), so
-- prefer the link and keep the id as the fallback.
-- Per bar and off by default: nothing here is created or called until a bar
-- turns it on. The resolved atlas is memoised per item so the steady state is
-- one compare; it re-reads when the icon changes which item it is showing,
-- which for a pot preset is the point (the pip follows the rank resolved).
-- The memo is deliberately TRI-STATE. An item whose data the client has not
-- cached yet answers nil, and that is the state on the pass right after login,
-- so caching it as "no quality" would leave the pip permanently missing on
-- exactly the items it is for: nil = unresolved, retry next pass (item data is
-- requested here, so the retry has something to find); false = resolved, this
-- item has no crafted quality, stop asking.
local _cdmQualityAtlas = {}
local function CdmQualityAtlasFor(q)
    local hit = _cdmQualityAtlas[q]
    if hit ~= nil then return hit or nil end
    local probe = C_Texture and C_Texture.GetAtlasInfo
    local names = {
        "Professions-Icon-Quality-Tier" .. q .. "-Inv-Small",
        "Professions-Icon-Quality-Tier" .. q .. "-Small",
        "Professions-Icon-Quality-Tier" .. q,
    }
    for i = 1, #names do
        if probe and probe(names[i]) then
            _cdmQualityAtlas[q] = names[i]
            return names[i]
        end
    end
    _cdmQualityAtlas[q] = false
    return nil
end

local function ApplyItemQualityPip(f, itemID, on)
    if not on then
        if f._qualityHolder then f._qualityHolder:Hide() end
        f._qualityItemID, f._qualityAtlas = nil, nil
        return
    end
    if not itemID then return end
    -- Resolved already for this exact item (false = resolved as "no quality").
    if f._qualityItemID == itemID and f._qualityAtlas ~= nil then return end

    local atlas
    local ts = C_TradeSkillUI
    local link = C_Item and C_Item.GetItemInfo and select(2, C_Item.GetItemInfo(itemID))
    if not link and C_Item and C_Item.RequestLoadItemDataByID then
        -- Not cached yet. Ask for it and leave the memo unresolved so the next
        -- pass retries rather than baking in the miss.
        C_Item.RequestLoadItemDataByID(itemID)
    end
    -- Blizzard's own item buttons (SetItemCraftingQualityOverlay in
    -- ItemButtonTemplate) ask REAGENT quality first and only then CRAFTED, and
    -- that order is the whole fix: a live probe on this bar had the crafted
    -- calls answering nil for every potion on it -- ranked consumables carry a
    -- reagent quality, not a crafted one. Both return the same
    -- CraftingQualityInfo, so iconInventory comes off whichever answers.
    if ts and ts.GetItemReagentQualityInfo then
        local ok, info = pcall(ts.GetItemReagentQualityInfo, link or itemID)
        atlas = ok and info and info.iconInventory or nil
    end
    if not atlas and ts and ts.GetItemCraftedQualityInfo then
        local ok, info = pcall(ts.GetItemCraftedQualityInfo, link or itemID)
        atlas = ok and info and info.iconInventory or nil
    end
    if not atlas and ts and ts.GetItemCraftedQualityByItemInfo then
        -- Same fallback shape the action bars keep: a bare quality number,
        -- mapped through the probe.
        local ok, q = pcall(ts.GetItemCraftedQualityByItemInfo, link or itemID)
        if ok and type(q) == "number" and q >= 1 and q <= 5 then
            atlas = CdmQualityAtlasFor(q)
        end
    end
    if not atlas then
        if f._qualityHolder then f._qualityHolder:Hide() end
        -- Only settle on "no quality" once the item is actually known.
        if link then f._qualityItemID, f._qualityAtlas = itemID, false end
        return
    end
    f._qualityItemID, f._qualityAtlas = itemID, atlas

    local holder = f._qualityHolder
    if not holder then
        -- Own holder frame rather than a texture on f: the item frame's
        -- Cooldown is a CHILD frame, and a child draws above every texture of
        -- its parent whatever the draw layer, so a pip parented to f sits under
        -- the swipe. This is why the item count text is reparented to a text
        -- overlay too, and what the action bars' rank icon does.
        holder = CreateFrame("Frame", nil, f)
        holder:SetAllPoints(f)
        holder:SetFrameLevel((f:GetFrameLevel() or 1) + 18)
        holder:EnableMouse(false)
        f._qualityHolder = holder
        f._qualityTex = holder:CreateTexture(nil, "OVERLAY", nil, 7)
    end
    local tex = f._qualityTex
    -- Unknown atlas reads as no pip, never as an error.
    if not pcall(tex.SetAtlas, tex, atlas, true) then
        f._qualityAtlas = false
        holder:Hide()
        return
    end
    -- Same proportion the action bars use (Blizzard centers the overlay 14,-14
    -- from the TOPLEFT of a 45px button), scaled to whatever size the bar runs.
    local sc = (f:GetWidth() or 36) / 36
    tex:ClearAllPoints()
    tex:SetPoint("CENTER", holder, "TOPLEFT", 11 * sc, -11 * sc)
    tex:SetScale(sc)
    tex:Show()
    holder:Show()
end

I._AC, I._injectedCustomBuffFrames, I._pcActive = _AC, _injectedCustomBuffFrames, _pcActive
I._presetFrames, I._RegisterPresetLive = _presetFrames, _RegisterPresetLive
I.ApplyItemQualityPip = ApplyItemQualityPip
I.GetOrCreateCustomBuffFrame = GetOrCreateCustomBuffFrame
I.GetOrCreateEmptySlotFrame = GetOrCreateEmptySlotFrame
I.GetOrCreateItemPresetFrame = GetOrCreateItemPresetFrame
I.GetOrCreatePlaceholderFrame = GetOrCreatePlaceholderFrame
I.HideAllInjectedCustomBuffs = HideAllInjectedCustomBuffs
I.HideAllPlaceholders = HideAllPlaceholders
I.ResolvePlaceholderIconSID = ResolvePlaceholderIconSID
I.broken = false
