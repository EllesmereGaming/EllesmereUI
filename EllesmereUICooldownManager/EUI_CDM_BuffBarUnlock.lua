if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_CDM_BuffBarUnlock.lua
--
--  Unlock Mode registration of the tracking bars and their groups.
--  Reads the earlier Tracking Bars files through ns and ns._buffBarInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._buffBarInternals
-- EllesmereUICdmBuffBars.lua or an earlier Tracking Bars file failed to load.
if not I or I.broken then return end
I.broken = true

local tbbFrames = I.tbbFrames

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._buffBarInternals, which hands the value to every copy.
local ECME
I.ecmeSetters[#I.ecmeSetters + 1] = function(v) ECME = v end

-------------------------------------------------------------------------------
--  Unlock Mode Registration
-------------------------------------------------------------------------------
function ns.RegisterTBBUnlockElements()
    if not EllesmereUI or not EllesmereUI.RegisterUnlockElements then return end
    if not ECME or not ECME.db then return end
    -- Per-spec unlock-link views: this path can run on spec change before a TBB build (CDM
    -- setup registers synchronously so anchor data is ready for CollectAndReanchor), so sync the link stores here too.
    ns.SyncTBBUnlockLinks()
    local MK = EllesmereUI.MakeUnlockElement
    -- Never call UnregisterUnlockElement for TBB keys -- it triggers PruneStaleLinks which
    -- destroys saved anchor data in unlockAnchors. Instead, just overwrite registrations;
    -- the isHidden callback handles hiding movers for bars that don't exist in the current spec.
    local tbb = ns.GetTrackedBuffBars()
    local bars = (tbb and tbb.bars) or {}

    -- Membership/grow/spec may have changed: growth-edge extent watch re-derives lazily on next use.
    ns._tbbExtentWatch = nil

    -- Each group's anchor (first enabled member) owns that group's mover; the other members hide theirs. Computed per build so it tracks group edits.
    local elements = {}
    for i, cfg in ipairs(bars) do
        local idx = i
        local posKey = tostring(idx)
        local bar = tbbFrames[idx]
        local barGid = ns.TBBBarGroupID(cfg)
        local isGroupMover = barGid ~= 0
            and idx == ns.TBBGroupAnchorIndex(barGid)
            and ns.TBBGroupedCount(barGid) >= 2
        if bar then
            elements[#elements + 1] = MK({
                key   = "TBB_" .. posKey,
                label = isGroupMover
                    and (ns.TBBGroupName(barGid) or EllesmereUI.Lf("Tracking Bar Group %d", barGid))
                    or EllesmereUI.Lf("Tracking Bar: %s", cfg.name or EllesmereUI.Lf("Bar %d", idx)),
                group = "Cooldown Manager",
                order = 650,
                noResize = true,
                -- Tracking bars may size-MATCH to other elements (allowMatchSource), but other
                -- elements may NOT match to them (noSizeMatchTarget): a tracking bar's size is
                -- driven by its own CDM sliders/dynamic content, so it should never be a sizing reference.
                allowMatchSource  = true,
                noSizeMatchTarget = true,
                -- Outside reach of the bar's textured border: taken off a width /
                -- height it is matched to, so what it draws is what matches.
                getMatchPad = function()
                    local t = ns.GetTrackedBuffBars()
                    local c = t and t.bars and t.bars[idx]
                    return ns.TBBBorderMatchPad(c, tbbFrames[idx])
                end,
                isHidden = function()
                    local t = ns.GetTrackedBuffBars()
                    local b = t and t.bars
                    if not b or idx > #b then return true end
                    local c = b[idx]
                    -- Independent bars always show their own mover.
                    local gid = ns.TBBBarGroupID(c)
                    if gid == 0 then return false end
                    -- Global group: the stable TBBG_ mover owns the whole group -- every member's own mover hides, anchor included.
                    if ns.TBBGroupGlobalKey and ns.TBBGroupGlobalKey(gid) then return true end
                    -- Grouped bars: only the group's anchor shows a mover (moves the
                    -- whole group); hide every other member, enabled OR disabled (a
                    -- disabled member re-enables straight into the chain, so its own
                    -- mover would be a phantom). No member enabled -> anchor nil, all hidden.
                    return idx ~= ns.TBBGroupAnchorIndex(gid)
                end,
                -- Grouped non-anchor members are positioned by the relative SetPoint
                -- chain in BuildTrackedBuffBars; report them as addon-owned so the
                -- generic anchor system never repositions them (a cascade/override
                -- SetPoint would sever the chain, e.g. in combat via a stale per-member
                -- link). A group ANCHOR returns false (stays element-anchorable).
                -- Global-group members are ALL addon-owned (anchor included): its
                -- position comes from the registry via BuildTrackedBuffBars, and the
                -- TBBG_ element carries the group's anchorable identity instead.
                isAnchored = function()
                    local t = ns.GetTrackedBuffBars()
                    local b = t and t.bars
                    local c = b and b[idx]
                    local gid = c and ns.TBBBarGroupID(c) or 0
                    if gid == 0 then return false end
                    if ns.TBBGroupGlobalKey and ns.TBBGroupGlobalKey(gid) then return true end
                    return idx ~= ns.TBBGroupAnchorIndex(gid)
                end,
                getFrame = function()
                    -- Never expose a stale frame when the current spec has fewer bars: anchors
                    -- involving this key stay dormant (children hold position) instead of gluing to a hidden frame at another spec's coordinates.
                    local t = ns.GetTrackedBuffBars()
                    local b = t and t.bars
                    if not b or idx > #b then return nil end
                    return tbbFrames[idx]
                end,
                getSize  = function()
                    -- width/height ARE the total footprint (icon included), so matching reads the stored dims directly.
                    local t = ns.GetTrackedBuffBars()
                    local c = t.bars and t.bars[idx]
                    local PPg = EllesmereUI and EllesmereUI.PP
                    local sn = PPg and PPg.Snap or function(v) return v end
                    if c then
                        return sn(c.width or 270), sn(c.height or 24)
                    end
                    return 270, 24
                end,
                setWidth = function(_, w)
                    local t = ns.GetTrackedBuffBars()
                    local c = t.bars and t.bars[idx]
                    if not c then return end
                    local f = tbbFrames[idx]
                    local PPt = EllesmereUI and EllesmereUI.PP
                    w = PPt and PPt.Snap(w) or math.floor(w + 0.5)
                    -- Persist during unlock (manual) AND match propagation, so a width match TO
                    -- another element survives the next BuildTrackedBuffBars instead of reverting to the slider value.
                    if EllesmereUI._unlockActive or EllesmereUI._propagatingMatch then
                        c.width = w
                        -- Grouped bars share width: fan this out to the rest of the group
                        -- (covers unlock drag-resize AND a width-MATCH on the group anchor, both routing through here).
                        ns.PropagateTBBGroupSize(idx, "width", w)
                    end
                    if f then f:SetWidth(w) end
                end,
                setHeight = function(_, h)
                    local t = ns.GetTrackedBuffBars()
                    local c = t.bars and t.bars[idx]
                    if not c then return end
                    local PPt = EllesmereUI and EllesmereUI.PP
                    h = PPt and PPt.Snap(h) or math.floor(h + 0.5)
                    local f = tbbFrames[idx]
                    -- Persist during unlock AND match propagation (see setWidth).
                    if EllesmereUI._unlockActive or EllesmereUI._propagatingMatch then
                        c.height = h
                        ns.PropagateTBBGroupSize(idx, "height", h)
                    end
                    if f then f:SetHeight(h) end
                end,
                savePos = function(_, point, relPoint, x, y)
                    local pos = ns.GetTBBPositions()
                    pos[posKey] = { point = point, relPoint = relPoint, x = x, y = y }
                    -- A group is dragged via its anchor's mover, but the saved position is
                    -- keyed by the anchor's INDEX. If the anchor later changes (first
                    -- member leaves the group or is disabled) the new anchor would read a
                    -- stale coordinate and teleport. Mirror the group origin into every
                    -- member's key so whichever bar becomes the anchor reads it correctly.
                    local t = ns.GetTrackedBuffBars()
                    local c0 = t.bars and t.bars[idx]
                    local gid = c0 and ns.TBBBarGroupID(c0) or 0
                    if gid ~= 0 and idx == ns.TBBGroupAnchorIndex(gid)
                        and ns.TBBGroupedCount(gid) >= 2 then
                        for j, c in ipairs(t.bars or {}) do
                            if j ~= idx and ns.TBBBarGroupID(c) == gid then
                                pos[tostring(j)] = { point = point, relPoint = relPoint, x = x, y = y }
                            end
                        end
                    end
                    if not EllesmereUI._unlockActive then
                        local f = tbbFrames[idx]
                        if f then
                            f:ClearAllPoints()
                            f:SetPoint(point, UIParent, relPoint or point, x, y)
                        end
                        ns.BuildTrackedBuffBars()
                    end
                end,
                loadPos = function()
                    local pos = ns.GetTBBPositions()
                    return pos[posKey]
                end,
                clearPos = function()
                    local pos = ns.GetTBBPositions()
                    pos[posKey] = nil
                end,
                applyPos = function()
                    ns.BuildTrackedBuffBars()
                end,
            })
        end
    end

    -- Global groups: one stable mover per registry entry, registered even when the
    -- active spec has no member bars (never unregister -- links must survive;
    -- isHidden/getFrame nil keep empty groups inert). The mover reads/writes the shared
    -- registry position, so one drag places the group for every spec.
    local reg = ns.GetTBBGlobalGroups and ns.GetTBBGlobalGroups()
    if reg then
        -- Alias map: the anchor bar's frame carries the move/resize hooks under its per-bar
        -- TBB_ key; children anchored to the group's stable TBBG_ key need those notifications
        -- too. Rebuilt each registration pass (anchor index shifts on edits/deletes).
        local aliases = EllesmereUI._unlockKeyAliases
        if not aliases then
            aliases = {}
            EllesmereUI._unlockKeyAliases = aliases
        end
        for k, v in pairs(aliases) do
            if type(v) == "string" and v:find("^TBBG_") then aliases[k] = nil end
        end
        for gkey, entry in pairs(reg) do
            local gk = gkey
            local lgid = ns.TBBLocalGidForGlobal(gk)
            local anchorIdx = lgid and ns.TBBGroupAnchorIndex(lgid)
            if anchorIdx then
                aliases["TBB_" .. anchorIdx] = "TBBG_" .. gk
            end
            elements[#elements + 1] = MK({
                key   = "TBBG_" .. gk,
                label = EllesmereUI.Lf("Tracking Bars: %1$s", entry.name or gk),
                group = "Cooldown Manager",
                order = 651,
                noResize = true,
                allowMatchSource  = true,
                noSizeMatchTarget = true,
                -- The group anchor bar's border reach (its frame is the group's);
                -- nil for a memberless spec's stand-in, which draws no border.
                getMatchPad = function()
                    local gid = ns.TBBLocalGidForGlobal(gk)
                    local ai = gid and ns.TBBGroupAnchorIndex(gid)
                    local t = ai and ns.GetTrackedBuffBars()
                    local c = t and t.bars and t.bars[ai]
                    return ns.TBBBorderMatchPad(c, ai and tbbFrames[ai])
                end,
                isHidden = function()
                    local gid = ns.TBBLocalGidForGlobal(gk)
                    return not gid or not ns.TBBGroupAnchorIndex(gid)
                end,
                isAnchored = function() return false end,
                getFrame = function()
                    local gid = ns.TBBLocalGidForGlobal(gk)
                    local ai = gid and ns.TBBGroupAnchorIndex(gid)
                    if ai then return tbbFrames[ai] end
                    -- No member bars on the active spec. With "Shift Elements If
                    -- No Bars" set, the opt-in stand-in holds the group's slot so
                    -- anchored elements keep position (and shift into it); with
                    -- it off (None), nil keeps legacy behavior -- anchors stay
                    -- dormant (or take their stored fallback) instead of gluing
                    -- to a stale frame. A stand-in built earlier this session
                    -- keeps resolving after a None flip (see TBBStandinFrame).
                    local e = ns.TBBGlobalGroup(gk)
                    if e and (e.shiftNoBar == "Up" or e.shiftNoBar == "Down") then
                        return ns.TBBEnsureStandin(gk)
                    end
                    return ns.TBBStandinFrame and ns.TBBStandinFrame(gk) or nil
                end,
                getSize = function()
                    local gid = ns.TBBLocalGidForGlobal(gk)
                    local ai = gid and ns.TBBGroupAnchorIndex(gid)
                    local t = ns.GetTrackedBuffBars()
                    local c = ai and t.bars and t.bars[ai]
                    local PPg = EllesmereUI and EllesmereUI.PP
                    local sn = PPg and PPg.Snap or function(v) return v end
                    if c then
                        return sn(c.width or 270), sn(c.height or 24)
                    end
                    -- Memberless spec: the registry's last-stamped anchor size
                    -- (what the stand-in renders at), else the defaults.
                    local e = ns.TBBGlobalGroup(gk)
                    if e and e.width then
                        return sn(e.width), sn(e.height or 24)
                    end
                    return 270, 24
                end,
                setWidth = function(_, w)
                    local gid = ns.TBBLocalGidForGlobal(gk)
                    local ai = gid and ns.TBBGroupAnchorIndex(gid)
                    local t = ns.GetTrackedBuffBars()
                    local c = ai and t.bars and t.bars[ai]
                    local PPt = EllesmereUI and EllesmereUI.PP
                    w = PPt and PPt.Snap(w) or math.floor(w + 0.5)
                    if c then
                        local f = tbbFrames[ai]
                        if EllesmereUI._unlockActive or EllesmereUI._propagatingMatch then
                            c.width = w
                            ns.PropagateTBBGroupSize(ai, "width", w)
                        end
                        if f then f:SetWidth(w) end
                        return
                    end
                    -- Memberless spec, STRICTLY gated on "Shift Elements If No
                    -- Bars" being Up/Down (the stand-in feature): a width match
                    -- landing here must still persist (the registry stamp is
                    -- what the stand-in renders from) and resize the frame, so
                    -- its size-changed hook reaches anchored children -- an
                    -- edge-preserve follower has to track the matched width
                    -- even while the group has no bars (field report). With the
                    -- option off this stays the legacy hard no-op: no write,
                    -- no resize.
                    local e = ns.TBBGlobalGroup(gk)
                    if not (e and (e.shiftNoBar == "Up" or e.shiftNoBar == "Down")) then return end
                    if EllesmereUI._unlockActive or EllesmereUI._propagatingMatch then
                        e.width = w
                    end
                    local sf = ns.TBBStandinFrame and ns.TBBStandinFrame(gk)
                    if sf then sf:SetWidth(w) end
                end,
                setHeight = function(_, h)
                    local gid = ns.TBBLocalGidForGlobal(gk)
                    local ai = gid and ns.TBBGroupAnchorIndex(gid)
                    local t = ns.GetTrackedBuffBars()
                    local c = ai and t.bars and t.bars[ai]
                    local PPt = EllesmereUI and EllesmereUI.PP
                    h = PPt and PPt.Snap(h) or math.floor(h + 0.5)
                    if c then
                        local f = tbbFrames[ai]
                        if EllesmereUI._unlockActive or EllesmereUI._propagatingMatch then
                            c.height = h
                            ns.PropagateTBBGroupSize(ai, "height", h)
                        end
                        if f then f:SetHeight(h) end
                        return
                    end
                    -- Memberless stand-in: same strict option gate as setWidth
                    -- (option off = legacy hard no-op). Height also feeds the
                    -- shift magnitude (target height), so anchored children
                    -- re-shift to the matched size.
                    local e = ns.TBBGlobalGroup(gk)
                    if not (e and (e.shiftNoBar == "Up" or e.shiftNoBar == "Down")) then return end
                    if EllesmereUI._unlockActive or EllesmereUI._propagatingMatch then
                        e.height = h
                    end
                    local sf = ns.TBBStandinFrame and ns.TBBStandinFrame(gk)
                    if sf then sf:SetHeight(h) end
                end,
                savePos = function(_, point, relPoint, x, y)
                    local e = ns.TBBGlobalGroup(gk)
                    if not e then return end
                    e.pos = { point = point, relPoint = relPoint, x = x, y = y }
                    if not EllesmereUI._unlockActive then
                        ns.BuildTrackedBuffBars()
                    end
                end,
                loadPos = function()
                    local e = ns.TBBGlobalGroup(gk)
                    return e and e.pos
                end,
                clearPos = function()
                    local e = ns.TBBGlobalGroup(gk)
                    if e then e.pos = nil end
                end,
                applyPos = function()
                    ns.BuildTrackedBuffBars()
                end,
            })
        end
    end

    if #elements > 0 then
        EllesmereUI:RegisterUnlockElements(elements, "EllesmereUICooldownManager")
    end

    -- Fallback anchors: bars/groups may have appeared or vanished for this spec -- let
    -- opted-in children re-evaluate (no-op when nobody opted in, or before the unlock module has loaded).
    if EllesmereUI.NotifyFallbackTargetsChanged then
        EllesmereUI.NotifyFallbackTargetsChanged()
    end
end
_G._ECME_RegisterTBBUnlock = ns.RegisterTBBUnlockElements

I.broken = false
