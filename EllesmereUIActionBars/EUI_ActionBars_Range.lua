if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_ActionBars_Range.lua
--
--  Out-of-range icon coloring: per-slot range checks and the icon tint. Loads
--  after the main file and before EUI_ActionBars_Glows.lua, reads the main
--  file through ns only, and hands GetButtonActionSlot to the files after it
--  through ns._internals (bottom of this file). At run time it also reads
--  ns._eabBarDormant and ns._slotBtnMap, which EUI_ActionBars_Events.lua owns.
-------------------------------------------------------------------------------
local _, ns = ...

local ipairs, pairs, pcall = ipairs, pairs, pcall
local wipe = wipe
local hooksecurefunc = hooksecurefunc
local C_Timer_After = C_Timer.After
local EFD = ns.EFD

local EAB, EAB_VTABLE, barButtons = ns.EAB, ns.EAB_VTABLE, ns.barButtons
local I = ns._internals
local BAR_CONFIG, NUM_ACTIONBAR_BUTTONS, BAR_SLOT_OFFSETS = I.BAR_CONFIG, I.NUM_ACTIONBAR_BUTTONS, I.BAR_SLOT_OFFSETS
local barFrames, buttonToBar = I.barFrames, I.buttonToBar

-------------------------------------------------------------------------------
--  Out-of-Range Icon Coloring: ACTION_RANGE_CHECK_UPDATE tints action button
--  icons when the target is out of range. Each slot opts in via
--  C_ActionBar.EnableActionRangeCheck so the client fires the event only for
--  slots we care about.
-------------------------------------------------------------------------------
local _range = {
    slots = {},           -- [actionSlot] = refcount (bars currently holding range checking on the slot)
    barSlots = {},        -- [barKey] = { [actionSlot] = true } acquisition snapshot
    outOfRange = {},      -- [actionSlot] = true  (currently out of range)
    eventFrame = nil,     -- lazy-created event frame
    slotPending = false,  -- debounce for per-slot range re-enable
}

-- Resolve a button's action slot without reading btn.action: protected
-- (secret value in Midnight), reading it in combat taints. Uses a lookup
-- table built at setup; MainBar derives the page offset from the bar frame's
-- actionpage attribute (set by _onstate-page).
local function GetButtonActionSlot(btn)
    local info = buttonToBar[btn]
    if not info then return nil end
    local offset = BAR_SLOT_OFFSETS[info.barKey]
    if not offset then return nil end
    if info.barKey == "MainBar" then
        -- actionpage is set by the _onstate-page handler in the restricted env
        -- and reflects vehicle/override/form pages, unlike
        -- C_ActionBar.GetActionBarPage() which tracks only the manual page.
        local frame = barFrames["MainBar"]
        local page = frame and tonumber(frame:GetAttribute("actionpage")) or EAB_VTABLE.GetActionBarPage()
        offset = (page - 1) * NUM_ACTIONBAR_BUTTONS
    end
    return offset + info.index
end

-- Apply or remove the range tint on a single button
local function ApplyRangeTint(btn, outOfRange, barSettings)
    local ico = btn.icon or btn.Icon
    if not ico then return end
    local rfd = EFD(btn)
    if outOfRange and barSettings.outOfRangeColoring then
        local c = barSettings.outOfRangeColor or { r = 0.7, g = 0.2, b = 0.2 }
        ico:SetVertexColor(c.r, c.g, c.b)
        rfd.rangeTinted = true
    elseif rfd.rangeTinted then
        rfd.rangeTinted = nil
        -- Let Blizzard's UpdateUsable set the correct color (may be dimmed
        -- for insufficient resources) instead of forcing full white.
        if btn.UpdateUsable then
            btn:UpdateUsable()
        else
            ico:SetVertexColor(1, 1, 1)
        end
    end
end

-- Slot acquisition is REFCOUNTED: pages duplicate slots across bars, so a plain boolean
-- lets one bar's release kill another bar's live tracking, and resolving slots at
-- release time strands the old page's slots enabled forever when a page flip lands
-- between acquire and release. Each bar releases exactly the snapshot it acquired; the
-- engine call happens only on 0<->1 edges. Dormant bars release entirely so they stop
-- GENERATING ACTION_RANGE_CHECK_UPDATE traffic (otherwise every hidden bar's slots stay
-- range-enabled and each fire walks all bars).

-- Release whatever the bar snapshot holds (no slot resolution: the snapshot
-- IS what was acquired, immune to page drift). On ns, not a local: kept from
-- the main file, which sits near the 200-local cap.
ns._eabReleaseRangeSlots = function(barKey)
    local held = _range.barSlots[barKey]
    if not held then return end
    _range.barSlots[barKey] = nil
    for slot in pairs(held) do
        local n = _range.slots[slot]
        if n and n > 1 then
            _range.slots[slot] = n - 1
        else
            _range.slots[slot] = nil
            _range.outOfRange[slot] = nil
            if C_ActionBar and C_ActionBar.EnableActionRangeCheck then
                pcall(C_ActionBar.EnableActionRangeCheck, slot, false)
            end
        end
    end
end

-- Re-evaluate a bar's range state from the live API and repaint it.
-- Acquiring a slot yields NO initial state: EnableActionRangeCheck is silent
-- until the next transition, so a slot whose refcount just went 0->1 has
-- nothing to paint from and the release-wiped cache entry stays wiped. The
-- flip handler's "no change, return" gate then swallows the next report,
-- stranding the last painted tint. On ns, not a local: kept from the main
-- file, which sits near the 200-local cap.
ns._eabRangeSweepBar = function(barKey)
    local buttons = barButtons[barKey]
    local s = EAB.db.profile.bars[barKey]
    if not buttons or not s or not s.outOfRangeColoring then return end
    if ns._eabBarDormant[barKey] then return end
    for _, btn in ipairs(buttons) do
        local slot = GetButtonActionSlot(btn)
        if slot and HasAction(slot) then
            local isOut = (IsActionInRange(slot) == false)
            _range.outOfRange[slot] = isOut or nil
            ApplyRangeTint(btn, isOut, s)
        elseif slot then
            -- Slot lost its action (talent swap, drag): clear stale tint.
            _range.outOfRange[slot] = nil
            ApplyRangeTint(btn, false, s)
        end
    end
end

-- Enable range checking for all active button slots on a bar
local function EnableRangeCheckForBar(barKey)
    local buttons = barButtons[barKey]
    if not buttons then return end
    local s = EAB.db.profile.bars[barKey]
    if not s or not s.outOfRangeColoring then return end
    -- Dormant bars acquire nothing; the show edge re-runs this.
    if ns._eabBarDormant[barKey] then return end
    -- Re-acquire from scratch: releasing the old snapshot first makes this
    -- idempotent under page flips (debounced SLOT_CHANGED re-enable and the
    -- PAGE_CHANGED pass both land here).
    ns._eabReleaseRangeSlots(barKey)
    local held = {}
    _range.barSlots[barKey] = held
    for _, btn in ipairs(buttons) do
        local slot = GetButtonActionSlot(btn)
        if slot and not held[slot] then
            held[slot] = true
            local n = _range.slots[slot]
            if n then
                _range.slots[slot] = n + 1
            else
                _range.slots[slot] = 1
                if C_ActionBar and C_ActionBar.EnableActionRangeCheck then
                    pcall(C_ActionBar.EnableActionRangeCheck, slot, true)
                end
            end
        end
    end
    -- Every acquire path lands here, so post-acquire re-evaluation does too
    -- rather than in each caller. Unconditional: a bar sharing slots another
    -- bar already holds takes no 0->1 edge but still needs its buttons painted.
    ns._eabRangeSweepBar(barKey)
end

-- Disable range checking for all slots on a bar and clear tints
local function DisableRangeCheckForBar(barKey)
    ns._eabReleaseRangeSlots(barKey)
    local buttons = barButtons[barKey]
    if not buttons then return end
    for _, btn in ipairs(buttons) do
        local rfd = EFD(btn)
        if rfd.rangeTinted then
            rfd.rangeTinted = nil
            if btn.UpdateUsable then
                btn:UpdateUsable()
            else
                local ico = btn.icon or btn.Icon
                if ico then ico:SetVertexColor(1, 1, 1) end
            end
        end
    end
end

-- Dormancy edges for range (via ns: the caller, ns.ApplyBarDormancy, lives in
-- EUI_ActionBars_Events.lua). Hide releases the bar's slots; show re-acquires and the sweep
-- repaints from the LIVE API -- repainting from cache would paint every
-- button in-range, since the hide-time release wiped the bar's entries.
ns._eabRangeBarDormancy = function(barKey, dormant)
    if dormant then
        ns._eabReleaseRangeSlots(barKey)
        return
    end
    EnableRangeCheckForBar(barKey)
end

function EAB:ApplyRangeColoring()
    -- Set up the event listener BEFORE enabling range checks so any
    -- immediate ACTION_RANGE_CHECK_UPDATE events are caught.
    if not _range.eventFrame then
        -- No offset snapshot needed: GetButtonActionSlot reads the bar
        -- frame's actionpage attribute dynamically for MainBar.
        _range.eventFrame = ns.TakeShell()
        _range.eventFrame:RegisterEvent("ACTION_RANGE_CHECK_UPDATE")
        _range.eventFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
        _range.eventFrame:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
        _range.eventFrame:RegisterEvent("ACTION_USABLE_CHANGED")
        _range.eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
        _range.eventFrame:SetScript("OnEvent", function(_, event, slot, inRange, checksRange)
            if event == "ACTION_RANGE_CHECK_UPDATE" then
                if not _range.slots[slot] then return end
                local wasOut = _range.outOfRange[slot]
                local isOut = checksRange and not inRange
                local changed = false
                if isOut and not wasOut then
                    _range.outOfRange[slot] = true
                    changed = true
                elseif not isOut and wasOut then
                    _range.outOfRange[slot] = nil
                    changed = true
                end
                if not changed then return end
                local bars = EAB.db.profile.bars
                -- Slot->buttons map fast path (dispatcher-maintained) avoids
                -- scanning all bars x all buttons per flip. Belt: re-verify
                -- the live slot per hit so a stale entry can only skip, never
                -- mis-tint; paging edges that stale the map also wipe and
                -- re-derive range state, healing anything skipped. Dormant
                -- bars skip (reveal repaints from the outOfRange cache).
                local smap = ns._slotBtnMap
                local mapClean = smap and not ns._slotBtnMapDirty
                local hosts = mapClean and smap[slot] or nil
                if hosts then
                    for i = 1, #hosts do
                        local btn = hosts[i]
                        if GetButtonActionSlot(btn) == slot then
                            local bInfo = buttonToBar[btn]
                            local s = bInfo and bars[bInfo.barKey]
                            if s and s.outOfRangeColoring
                                and not ns._eabBarDormant[bInfo.barKey] then
                                ApplyRangeTint(btn, isOut, s)
                            end
                        end
                    end
                else
                    -- Map absent/dirty, or CLEAN BUT MISSING a slot the engine
                    -- is live-flipping (a paging edge remapped hosting with no
                    -- rebuild edge this map sees; modifier paging fires no
                    -- event here). Dropping the flip strands the tint until
                    -- the slot's NEXT transition, accumulating into
                    -- permanently stale bars, so fail OPEN with the full scan
                    -- and retire the map for the next SLOT_CHANGED to rebuild.
                    if mapClean then
                        ns._slotBtnMapDirty = true
                    end
                    for _, info in ipairs(BAR_CONFIG) do
                        local btns = barButtons[info.key]
                        local s = bars[info.key]
                        if btns and s and s.outOfRangeColoring
                            and not ns._eabBarDormant[info.key] then
                            for _, btn in ipairs(btns) do
                                if GetButtonActionSlot(btn) == slot then
                                    ApplyRangeTint(btn, isOut, s)
                                end
                            end
                        end
                    end
                end
            elseif event == "ACTIONBAR_SLOT_CHANGED" then
                -- When a slot changes (paging, drag, etc.), re-enable range
                -- checking for the new action and clear stale tint
                if slot and _range.slots[slot] then
                    if _range.outOfRange[slot] then
                        _range.outOfRange[slot] = nil
                        local bars2 = EAB.db.profile.bars
                        -- Same map fast path + re-verify belt + clean-miss
                        -- fail-open as the flip walk above: an over-skip here
                        -- strands a RED tint on an in-range button.
                        local smap2 = ns._slotBtnMap
                        local mapClean2 = smap2 and not ns._slotBtnMapDirty
                        local hosts2 = mapClean2 and smap2[slot] or nil
                        if hosts2 then
                            for i = 1, #hosts2 do
                                local btn2 = hosts2[i]
                                if GetButtonActionSlot(btn2) == slot then
                                    local bInfo2 = buttonToBar[btn2]
                                    local s2 = bInfo2 and bars2[bInfo2.barKey]
                                    if s2 then
                                        ApplyRangeTint(btn2, false, s2)
                                    end
                                end
                            end
                        else
                            if mapClean2 then
                                ns._slotBtnMapDirty = true
                            end
                            for _, info2 in ipairs(BAR_CONFIG) do
                                local btns2 = barButtons[info2.key]
                                local s2 = bars2[info2.key]
                                if btns2 and s2 then
                                    for _, btn2 in ipairs(btns2) do
                                        if GetButtonActionSlot(btn2) == slot then
                                            ApplyRangeTint(btn2, false, s2)
                                        end
                                    end
                                end
                            end
                        end
                    end
                    if C_ActionBar and C_ActionBar.EnableActionRangeCheck then
                        pcall(C_ActionBar.EnableActionRangeCheck, slot, true)
                    end
                end
                -- Debounce the full re-enable pass so 12+ per-slot fires
                -- during a bar page swap collapse into one deferred call.
                -- anyEnabled gate: feature fully off = no timer, no walk.
                if _range.anyEnabled and not _range.slotPending then
                    _range.slotPending = true
                    C_Timer_After(0, function()
                        _range.slotPending = false
                        for _, info in ipairs(BAR_CONFIG) do
                            local s = EAB.db.profile.bars[info.key]
                            if s and s.outOfRangeColoring then
                                EnableRangeCheckForBar(info.key)
                            end
                        end
                    end)
                end
            elseif event == "ACTIONBAR_PAGE_CHANGED" then
                -- No offset update needed: GetButtonActionSlot reads MainBar's
                -- actionpage attribute dynamically. A page flip remaps MainBar
                -- action ids with no per-slot SLOT_CHANGED, so the filled-slot
                -- fast lists must rebuild.
                ns._cdFilledDirty = true
                -- Clear all range state and re-enable for the new slots; skipped
                -- when the feature is off everywhere (the dirty flag above stays
                -- -- it belongs to the cooldown walker, not range).
                if not _range.anyEnabled then return end
                wipe(_range.outOfRange)
                for _, info in ipairs(BAR_CONFIG) do
                    local s = EAB.db.profile.bars[info.key]
                    if s and s.outOfRangeColoring then
                        local btns = barButtons[info.key]
                        if btns then
                            for _, btn in ipairs(btns) do
                                local rfd = EFD(btn)
                                if rfd.rangeTinted then
                                    local ico = btn.icon or btn.Icon
                                    if ico then ico:SetVertexColor(1, 1, 1) end
                                    rfd.rangeTinted = nil
                                end
                            end
                        end
                        EnableRangeCheckForBar(info.key)
                    end
                end
            elseif event == "ACTION_USABLE_CHANGED" then
                -- Blizzard resets icon vertex colors on usability changes;
                -- re-apply range tint on any out-of-range buttons.
                -- Bail fast when nothing is out of range (common case).
                if not next(_range.outOfRange) then return end
                for _, info in ipairs(BAR_CONFIG) do
                    local btns = barButtons[info.key]
                    local s = EAB.db.profile.bars[info.key]
                    if btns and s and s.outOfRangeColoring
                        and not ns._eabBarDormant[info.key] then
                        for _, btn in ipairs(btns) do
                            if EFD(btn).rangeTinted then
                                ApplyRangeTint(btn, true, s)
                            end
                        end
                    end
                end
            elseif event == "UPDATE_SHAPESHIFT_FORM" then
                -- Form shifts can fire ACTION_RANGE_CHECK_UPDATE with stale data
                -- before Blizzard settles, so defer a manual IsActionInRange
                -- poll. anyEnabled gate: feature fully off = no closure, no poll.
                if not _range.anyEnabled then return end
                C_Timer_After(0, function()
                    local bars = EAB.db.profile.bars
                    for _, info in ipairs(BAR_CONFIG) do
                        local s = bars[info.key]
                        if s and s.outOfRangeColoring
                            and not ns._eabBarDormant[info.key] then
                            local btns = barButtons[info.key]
                            if btns then
                                for _, btn in ipairs(btns) do
                                    local sl = GetButtonActionSlot(btn)
                                    if sl and HasAction(sl) then
                                        local inRange = IsActionInRange(sl)
                                        local isOut = (inRange == false)
                                        _range.outOfRange[sl] = isOut or nil
                                        ApplyRangeTint(btn, isOut, s)
                                    else
                                        if sl then _range.outOfRange[sl] = nil end
                                        ApplyRangeTint(btn, false, s)
                                    end
                                end
                            end
                        end
                    end
                end)
            end
        end)
    end

    local anyEnabled = nil
    for _, info in ipairs(BAR_CONFIG) do
        local key = info.key
        local s = self.db.profile.bars[key]
        if s and s.outOfRangeColoring then
            anyEnabled = true
            -- The acquire path sweeps: EnableActionRangeCheck fires no initial
            -- event, so slots already out of range need the live poll.
            EnableRangeCheckForBar(key)
        else
            DisableRangeCheckForBar(key)
        end
    end
    -- Standing flag for the event branches above: with the feature off on every
    -- bar the SLOT_CHANGED debounce and form-shift poll schedule NOTHING.
    -- Recomputed on every settings apply -- the single enable/disable funnel.
    _range.anyEnabled = anyEnabled

    -- Hook Blizzard's usability update so our range tint is re-applied
    -- after Blizzard resets the icon vertex color.
    for _, info in ipairs(BAR_CONFIG) do
        local btns = barButtons[info.key]
        if btns then
            for _, btn in ipairs(btns) do
                if not EFD(btn).rangeHooked and btn.UpdateUsable then
                    EFD(btn).rangeHooked = true
                    hooksecurefunc(btn, "UpdateUsable", function(self)
                        if not EFD(self).rangeTinted then return end
                        local slot = GetButtonActionSlot(self)
                        if slot and _range.outOfRange[slot] then
                            local bInfo = buttonToBar[self]
                            local s = bInfo and EAB.db.profile.bars[bInfo.barKey]
                            if s and s.outOfRangeColoring then
                                ApplyRangeTint(self, true, s)
                            end
                        end
                    end)
                end
            end
        end
    end
end

-- Entry point the files after this one re-import by name.
I.GetButtonActionSlot = GetButtonActionSlot
