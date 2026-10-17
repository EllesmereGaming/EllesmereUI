if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_CDM_BuffBarBuild.lua
--
--  BuildTrackedBuffBars: builds or rebuilds every tracking bar.
--  Reads the earlier Tracking Bars files through ns and ns._buffBarInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._buffBarInternals
-- EllesmereUICdmBuffBars.lua or an earlier Tracking Bars file failed to load.
if not I or I.broken then return end
I.broken = true

local pcall = pcall

local TBB_POPULAR_BUFFS, _tbbWake, GroupGrowOf = I.TBB_POPULAR_BUFFS, I._tbbWake, I.GroupGrowOf
local GroupSpacingOf, ResetReflowStates = I.GroupSpacingOf, I.ResetReflowStates
local tbbFrames, ApplyTrackedBuffBarSettings = I.tbbFrames, I.ApplyTrackedBuffBarSettings
local CreateTrackedBuffBarFrame = I.CreateTrackedBuffBarFrame
local EffectiveIconSpellID, TBBUsesVisCondition = I.EffectiveIconSpellID, I.TBBUsesVisCondition
local SetECME, SetRebuildPending = I.SetECME, I.SetRebuildPending
local SetReflowDirty, SetTickFrame = I.SetReflowDirty, I.SetTickFrame
local SetAnyPandemic, SetAnyThreshold = I.SetAnyPandemic, I.SetAnyThreshold
local SetAnyStacks, SetAnyVisCond = I.SetAnyStacks, I.SetAnyVisCond

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._buffBarInternals, which hands the value to every copy.
local ECME
I.ecmeSetters[#I.ecmeSetters + 1] = function(v) ECME = v end
local tbbTickFrame
I.tickFrameSetters[#I.tickFrameSetters + 1] = function(v) tbbTickFrame = v end

-------------------------------------------------------------------------------
--  Build / Rebuild All Tracking Bars
-------------------------------------------------------------------------------
function ns.BuildTrackedBuffBars()
    SetECME(ns.ECME)
    if not ECME or not ECME.db then return end
    -- No InCombatLockdown guard needed: TBB frames are ours (UIParent), not secure Blizzard frames, so positioning in combat is safe.
    SetRebuildPending(false)
    SetReflowDirty(true)

    -- Per-spec unlock-link views: the global anchor/match stores must hold THIS spec's TBB entries before any anchored-state below is read.
    ns.SyncTBBUnlockLinks()

    local p = ECME.db.profile

    -- NEVER auto-swap width/height per build: the Vertical Orientation toggle already swaps
    -- dimensions, and a per-build swap fights slider input and makes resizes erratic.
    do
        local tbb = ns.GetTrackedBuffBars()
        local bars = tbb and tbb.bars
        if bars then
        end
    end

    -- "Use Blizzard CDM Bars": hide all TBB frames and bail
    if p.cdmBars and p.cdmBars.useBlizzardBuffBars then
        for i = 1, #tbbFrames do
            if tbbFrames[i] then tbbFrames[i]:Hide() end
        end
        _tbbWake._enabled = false
        _tbbWake:UnregisterAllEvents()
        if tbbTickFrame then tbbTickFrame:Hide() end
        return
    end

    -- Pre-populate bars for spells newly added to Blizzard's Tracked Bars section BEFORE reading the bar list, so this rebuild picks them up.
    ns.EnsureTBBAutoBars()

    local tbb = ns.GetTrackedBuffBars()
    -- Hold the per-group orientation invariant before reading any configs
    ns.EnforceTBBGroupOrientation(tbb)
    local bars = tbb.bars
    local _tbbPos = ns.GetTBBPositions()
    ResetReflowStates()

    -- Hide bars beyond current count
    for i = #bars + 1, #tbbFrames do
        if tbbFrames[i] then tbbFrames[i]:Hide() end
    end

    -- Feature-gating flags: collected in the bar loop, handed on behind it
    local _anyPandemic  = false
    local _anyThreshold = false
    local _anyStacks    = false
    local _anyVisCond   = false

    local anyEnabled = false
    local anyLust = false  -- any enabled bloodlust bar -> needs the Sated listener
    local lastBarByGroup = {}  -- gid -> previous enabled member frame (chain tail)
    for i, cfg in ipairs(bars) do
        -- Update gating flags
        if cfg.pandemicGlow                             then _anyPandemic  = true end
        if cfg.stackThresholdEnabled                    then _anyThreshold = true; _anyStacks = true end
        if (cfg.stacksPosition or "center") ~= "none"  then _anyStacks    = true end
        if cfg.stackBasedBar and cfg.trackType ~= "cooldown"
           and cfg.stackThresholdMaxEnabled             then _anyStacks    = true end
        local visCond = TBBUsesVisCondition(cfg)
        if visCond                                      then _anyVisCond   = true end

        if not tbbFrames[i] then
            tbbFrames[i] = CreateTrackedBuffBarFrame(UIParent, i)
        end
        local bar = tbbFrames[i]
        -- Per-bar gate flag for the tick (our frame; the tick never re-derives it).
        bar._tbbVisCond = visCond or nil

        if cfg.enabled == false then
            bar:Hide()
        else
            anyEnabled = true
            if cfg.popularKey == "bloodlust" then anyLust = true end
            ApplyTrackedBuffBarSettings(bar, cfg)

            -- Icon texture: preset icon, else the EFFECTIVE (override-resolved) form of the
            -- saved spell, never the raw saved id -- a bar saved for a base form seeds the
            -- talented override's icon and vice versa. The live tick re-derives from the
            -- bound frame/aura and overwrites this seed whenever better data exists.
            if bar._icon and bar._icon._tex then
                local iconID
                if cfg.popularKey then
                    for _, pe in ipairs(TBB_POPULAR_BUFFS) do
                        if pe.key == cfg.popularKey then iconID = pe.icon; break end
                    end
                end
                if not iconID then
                    local effSID = EffectiveIconSpellID(cfg)
                    if effSID then
                        local spInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(effSID)
                        if spInfo then iconID = spInfo.iconID end
                    end
                end
                if iconID then bar._icon._tex:SetTexture(iconID) end
                -- Rebuilds can re-pair bar index <-> config (add/remove shifts indices), so
                -- reset per-bar icon source state and let the next tick re-derive instead of trusting stale caches.
                bar._lastIconSID = nil
                bar._cachedBlizzIconTex = nil
                bar._cachedBlizzIconOwner = nil
            end

            -- Name text
            local namePos2 = cfg.namePosition or ((cfg.showName ~= false) and "left" or "none")
            if namePos2 ~= "none" and bar._nameText then
                local displayName = cfg.name
                -- Preset bars take the live label the same way the icon does above:
                -- the copy saved at pick time can name the other faction's lust.
                if cfg.popularKey then
                    for _, pe in ipairs(TBB_POPULAR_BUFFS) do
                        if pe.key == cfg.popularKey then
                            displayName = pe.name or displayName
                            break
                        end
                    end
                end
                if (not displayName or displayName == "") and cfg.spellID and cfg.spellID > 0 then
                    local spInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(cfg.spellID)
                    displayName = spInfo and spInfo.name
                    if not displayName and C_Spell.RequestLoadSpellData then
                        C_Spell.RequestLoadSpellData(cfg.spellID)
                    end
                end
                bar._nameText:SetText(displayName or "")
                bar._nameSet = displayName and displayName ~= "" or false
            end

            -- Saved position / grouping. A group's FIRST enabled member takes the independent
            -- branch (its own saved pos) and becomes the group anchor; later members chain to
            -- the previous member using the group's grow/spacing. Independent bars (gid 0) always take the independent branch.
            local gid = ns.TBBBarGroupID(cfg)
            local prevInGroup = gid ~= 0 and lastBarByGroup[gid] or nil
            if prevInGroup then
                -- Grouped: position relative to the previous member
                local growDir = (GroupGrowOf(tbb, gid) or "DOWN"):upper()
                local spacing = GroupSpacingOf(tbb, gid) or 2
                bar:ClearAllPoints()
                if growDir == "UP" then
                    bar:SetPoint("BOTTOM", prevInGroup, "TOP", 0, spacing)
                elseif growDir == "RIGHT" then
                    bar:SetPoint("LEFT", prevInGroup, "RIGHT", spacing, 0)
                elseif growDir == "LEFT" then
                    bar:SetPoint("RIGHT", prevInGroup, "LEFT", -spacing, 0)
                else
                    bar:SetPoint("TOP", prevInGroup, "BOTTOM", 0, -spacing)
                end
            else
                -- Independent positioning (group anchors and ungrouped bars). A global group's
                -- anchor reads the shared registry position and its anchored-ness through the group's stable TBBG_ key.
                local gkeyPos = gid ~= 0 and ns.TBBGroupGlobalKey and ns.TBBGroupGlobalKey(gid) or nil
                local posKey = tostring(i)
                local pos, unlockKey
                if gkeyPos then
                    local entry = ns.TBBGlobalGroup(gkeyPos)
                    pos = entry and entry.pos
                    unlockKey = "TBBG_" .. gkeyPos
                    -- Stamp the anchor bar's size onto the registry entry so the
                    -- "Shift Elements If No Bars" stand-in (memberless specs)
                    -- holds the slot at the size the group last rendered. Gated
                    -- on the option so None profiles see zero new writes; a
                    -- never-stamped entry's stand-in uses the bar defaults.
                    if entry and (entry.shiftNoBar == "Up" or entry.shiftNoBar == "Down") then
                        entry.width = cfg.width or 270
                        entry.height = cfg.height or 24
                    end
                else
                    pos = _tbbPos[posKey]
                    unlockKey = "TBB_" .. posKey
                end
                if pos and pos.point then
                    local anchored = EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored(unlockKey)
                    if not anchored or not bar:GetLeft() then
                        bar:ClearAllPoints()
                        if pos.scale then pcall(function() bar:SetScale(pos.scale) end) end
                        bar:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
                    end
                else
                    local anchored = EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored(unlockKey)
                    if not anchored or not bar:GetLeft() then
                        bar:ClearAllPoints()
                        bar:SetPoint("CENTER", UIParent, "CENTER", 0, 200 - (i - 1) * ((cfg.height or 24) + 4))
                    end
                end
            end

            if gid ~= 0 then lastBarByGroup[gid] = bar end
            bar._tbbReady    = true
            bar._isPassive   = nil
            bar._stackCount  = 0
            bar._isLifebloom = nil  -- re-resolve Lifebloom identity after rebuild
            bar:Hide()  -- tick shows it when active
        end
    end
    SetAnyPandemic(_anyPandemic); SetAnyThreshold(_anyThreshold)
    SetAnyStacks(_anyStacks); SetAnyVisCond(_anyVisCond)

    -- Tick frame: every frame while anything is live (bar fill+spark need smooth updates);
    -- the idle sleeper in UpdateTrackedBuffBarTimers parks it when nothing is.
    _tbbWake._enabled = anyEnabled and true or false
    if anyEnabled then
        if not tbbTickFrame then
            SetTickFrame(ns.TakeShell())
            local tbbAccum = 0
            tbbTickFrame:SetScript("OnUpdate", function(self, elapsed)
                tbbAccum = tbbAccum + elapsed
                if tbbAccum < 0.016 then return end
                self._lastDt = tbbAccum
                tbbAccum = 0
                ns.UpdateTrackedBuffBarTimers()
            end)
        end
        _tbbWake.Wake()
    else
        _tbbWake:UnregisterAllEvents()
        if tbbTickFrame then tbbTickFrame:Hide() end
    end

    -- Start/stop the player-only Sated-debuff listener that drives the lust displays. Goes
    -- through the arbiter so a Custom Auras (icon) lust display keeps the listener armed even when no Tracking Bar lust bar exists.
    ns.UpdateLustListener()

    -- "Shift Elements If No Bars" (global groups): position each opted-in
    -- group's stand-in, and on an empty<->populated EDGE re-cascade the group's
    -- anchor chain so anchored elements pick up (or drop) the shift. The flip
    -- changes neither the stand-in's size nor its position (both come from the
    -- registry), so neither OnSizeChanged nor a move hook fires -- the cascade
    -- must be explicit, exactly like ResourceBars' BuildBars tail. Edge-gated
    -- via the per-key memo so a None-everywhere profile schedules ZERO anchor
    -- work here; unlock entry/exit manage the shift themselves.
    do
        local reg = ns.GetTBBGlobalGroups and ns.GetTBBGlobalGroups()
        if reg then
            for gk, entry in pairs(reg) do
                -- Also keep maintaining a stand-in that already exists with the
                -- option back at None (session fallback, see TBBStandinFrame):
                -- it must track registry-pos edits from other specs instead of
                -- freezing anchored children on a phantom (audit-caught).
                if entry.shiftNoBar == "Up" or entry.shiftNoBar == "Down"
                    or (ns.TBBStandinFrame and ns.TBBStandinFrame(gk)) then
                    ns.TBBEnsureStandin(gk)
                end
                if not EllesmereUI._unlockActive and EllesmereUI.PropagateAnchorChain then
                    -- dir: 0 = covered (members present or option off), +/-1 =
                    -- shifting. Unset memo reads as 0, so the first build with
                    -- nothing to shift schedules nothing (ERB memo parity).
                    local dir = ns.TBBShiftDirFor(entry, gk)
                    local memo = ns._tbbShiftDirMemo
                    if not memo then
                        memo = {}
                        ns._tbbShiftDirMemo = memo
                    end
                    if dir ~= (memo[gk] or 0) then
                        memo[gk] = dir
                        EllesmereUI.PropagateAnchorChain("TBBG_" .. gk)
                    end
                end
            end
        end
    end

    -- Unlock mode
    if ns.RegisterTBBUnlockElements then ns.RegisterTBBUnlockElements() end

    -- 12.1 engine-driven decimal timer text (nil on 12.0: module self-gates)
    if ns.TBBDecimals_Sync then ns.TBBDecimals_Sync() end

    -- Match pads follow each bar's border settings: a bar or group whose pad
    -- changed is re-pushed through its match once, deferred (compare-only here).
    if EllesmereUI.MatchPadChanged then
        for i = 1, #bars do
            EllesmereUI.MatchPadChanged(ns._tbbUKey[i])
        end
        local greg = ns.GetTBBGlobalGroups and ns.GetTBBGlobalGroups()
        if greg then
            for gk in pairs(greg) do
                EllesmereUI.MatchPadChanged(ns._tbbgUKey[gk])
            end
        end
    end

    -- Group loot rolls already up keep clear of the rebuilt bars.
    ns.RequestLootPlacement()
end

I.broken = false
