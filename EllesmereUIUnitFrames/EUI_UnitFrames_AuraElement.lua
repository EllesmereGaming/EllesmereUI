-------------------------------------------------------------------------------
--  EUI_UnitFrames_AuraElement.lua
--  Live-client (12.0) replacement driver for the oUF Buffs/Debuffs elements.
--
--  WHY: oUF's auras element repaints EVERY visible icon and re-sorts the
--  whole list whenever ANY active aura changes -- including pure content
--  updates (HoT refreshes, stack ticks), which are the overwhelming
--  majority of raid-combat aura traffic. With the DEFAULT comparator
--  (isPlayerAura, then auraInstanceID -- both immutable per instance) an
--  update-only pass cannot change order, so the sort and the untouched
--  icons are pure waste. This driver splits membership changes from content
--  changes and repaints ONLY the updated icons on content-only passes.
--
--  HOW (library files are never edited -- hard rule): after spawn, the oUF
--  'Auras' element is DisableElement()'d on our frames and this file takes
--  over its exact surface: UNIT_AURA through the frame's own oUF
--  RegisterEvent (incremental path), plus a hooksecurefunc on
--  UpdateAllElements for the full-update paths (unit swaps, ForceUpdate,
--  world entries) -- DisableElement removes the element from
--  UpdateAllElements, so target swaps would otherwise never repaint.
--  element.ForceUpdate is re-pointed here for the options/settings code.
--
--  The update/paint logic below is a HAND-COPIED DERIVATIVE of the vendored
--  oUF element (Libs/oUF/elements/auras.lua) and must be RE-DIFFED against
--  it on every oUF bump -- registered in the oUF-override-sync ledger
--  alongside DisableBlizzard. GameTooltip usage is preserved verbatim from
--  the library (existing aura-tooltip behavior, not new UI).
--
--  12.1: the container system owns UF auras (frame.Buffs/frame.Debuffs stay
--  nil on migrated units) -- this file hard-gates out below so the PTR
--  client keeps stock oUF behavior for anything not yet migrated. Zero 12.1
--  delta by construction.
-------------------------------------------------------------------------------
local addonName, ns = ...

if EllesmereUI and EllesmereUI.IS_121 then return end

local oUF = ns.oUF
if not oUF then return end

-------------------------------------------------------------------------------
--  Hand-copied element internals (keep in lockstep with the library)
-------------------------------------------------------------------------------
local function UpdateTooltip(self)
    if GameTooltip:IsForbidden() then return end
    GameTooltip:SetUnitAuraByAuraInstanceID(self:GetParent().__owner.unit, self.auraInstanceID)
end

local function onEnter(self)
    if GameTooltip:IsForbidden() or not self:IsVisible() then return end
    GameTooltip:SetOwner(self, self:GetParent().__restricted and 'ANCHOR_CURSOR' or self:GetParent().tooltipAnchor)
    self:UpdateTooltip()
end

local function onLeave()
    if GameTooltip:IsForbidden() then return end
    GameTooltip:Hide()
end

local function CreateButton(element, index)
    local button = CreateFrame('Button', element:GetDebugName() .. 'Button' .. index, element)

    local cd = CreateFrame('Cooldown', '$parentCooldown', button, 'CooldownFrameTemplate')
    cd:SetAllPoints()
    button.Cooldown = cd

    local icon = button:CreateTexture(nil, 'BORDER')
    icon:SetAllPoints()
    button.Icon = icon

    local countFrame = CreateFrame('Frame', nil, button)
    countFrame:SetAllPoints(button)
    countFrame:SetFrameLevel(cd:GetFrameLevel() + 1)

    local count = countFrame:CreateFontString(nil, 'OVERLAY', 'NumberFontNormal')
    count:SetPoint('BOTTOMRIGHT', countFrame, 'BOTTOMRIGHT', -1, 0)
    button.Count = count

    local overlay = button:CreateTexture(nil, 'OVERLAY')
    overlay:SetTexture([[Interface\Buttons\UI-Debuff-Overlays]])
    overlay:SetAllPoints()
    overlay:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
    button.Overlay = overlay

    local stealable = button:CreateTexture(nil, 'OVERLAY')
    stealable:SetTexture([[Interface\TargetingFrame\UI-TargetingFrame-Stealable]])
    stealable:SetPoint('TOPLEFT', -3, 3)
    stealable:SetPoint('BOTTOMRIGHT', 3, -3)
    stealable:SetBlendMode('ADD')
    button.Stealable = stealable

    button.UpdateTooltip = UpdateTooltip
    button:SetScript('OnEnter', onEnter)
    button:SetScript('OnLeave', onLeave)

    if element.PostCreateButton then element:PostCreateButton(button) end

    return button
end

local function SetPosition(element, from, to)
    local width = element.width or element.size or 16
    local height = element.height or element.size or 16
    local sizeX = width + (element.spacingX or element.spacing or 0)
    local sizeY = height + (element.spacingY or element.spacing or 0)
    local anchor = element.initialAnchor or 'BOTTOMLEFT'
    local growthX = (element.growthX == 'LEFT' and -1) or 1
    local growthY = (element.growthY == 'DOWN' and -1) or 1
    local cols = element.maxCols or math.floor(element:GetWidth() / sizeX + 0.5)

    for i = from, to do
        local button = element[i]
        if not button then break end

        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)

        button:ClearAllPoints()
        button:SetPoint(anchor, element, anchor, col * sizeX * growthX, row * sizeY * growthY)
    end
end

local function updateAura(element, unit, data, position)
    if not data then return end

    local button = element[position]
    if not button then
        button = (element.CreateButton or CreateButton)(element, position)
        table.insert(element, button)
        element.createdButtons = element.createdButtons + 1
    end

    -- for tooltips
    button.auraInstanceID = data.auraInstanceID

    if button.Cooldown and not element.disableCooldown then
        local duration = C_UnitAuras.GetAuraDuration(unit, data.auraInstanceID)
        if duration then
            button.Cooldown:SetCooldownFromDurationObject(duration)
            button.Cooldown:Show()
        else
            button.Cooldown:Hide()
        end
    end

    if button.Overlay then
        if element.showType or (data.isHarmfulAura and element.showDebuffType) or (not data.isHarmfulAura and element.showBuffType) then
            local color = C_UnitAuras.GetAuraDispelTypeColor(unit, data.auraInstanceID, element.dispelColorCurve)
            if color == nil then
                color = element.dispelColorCurve:Evaluate(0)
            end

            button.Overlay:SetVertexColor(color:GetRGBA())
            button.Overlay:Show()
        else
            button.Overlay:Hide()
        end
    end

    if button.Stealable then
        if element.showStealableBuffs and not UnitCanCooperate('player', unit) then
            button.Stealable:SetAlphaFromBoolean(data.isStealable, 1, 0)
        else
            button.Stealable:SetAlpha(0)
        end
    end

    if button.Icon then button.Icon:SetTexture(data.icon) end
    if button.Count then
        button.Count:SetText(C_UnitAuras.GetAuraApplicationDisplayCount(unit, data.auraInstanceID, element.minCount or 2, element.maxCount or 999))
    end

    local width = element.width or element.size or 16
    local height = element.height or element.size or 16
    button:SetSize(width, height)
    button:EnableMouse(not element.disableMouse)
    button:Show()

    if element.PostUpdateButton then
        element:PostUpdateButton(button, unit, data, position)
    end
end

local function FilterAura(element, unit, data)
    if (element.onlyShowPlayer and data.isPlayerAura) or not element.onlyShowPlayer then
        return true
    end
end

-- Default comparator: immutable per-instance keys ONLY. The content-only
-- fast path below is order-safe exactly because of this.
local function SortAuras(a, b)
    if a.isPlayerAura ~= b.isPlayerAura then
        return a.isPlayerAura
    end

    return a.auraInstanceID < b.auraInstanceID
end

local function processData(element, unit, data, filter)
    if not data then return end

    data.isPlayerAura = not C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, data.auraInstanceID, filter .. '|PLAYER')
    data.isHarmfulAura = filter:find('HARMFUL') and true

    if element.PostProcessAuraData then
        data = element:PostProcessAuraData(unit, data, filter)
    end

    return data
end

-------------------------------------------------------------------------------
--  The improved update: membership changes take the library's full path;
--  content-only changes repaint just the updated icons, no sort, no anchor.
-------------------------------------------------------------------------------
local function UpdateSide(el, unit, updateInfo, isFullUpdate, forcedFull, defaultFilter, defaultNum, sortKey)
    if el.PreUpdate then el:PreUpdate(unit, isFullUpdate) end

    local changed = false          -- membership changed (add/remove) or full
    local updated = false          -- content-only (updated active instances)
    local updatedIDs
    local num = el.num or defaultNum
    local filter = el.filter or defaultFilter
    if type(filter) == 'function' then
        filter = filter(el, unit)
    end

    -- Custom comparators may key on mutable fields (remaining time etc.);
    -- only the default immutable-key sort makes update-only passes
    -- order-stable. Route updates into the full path when one is set.
    local stableOrder = not (el[sortKey] or el.SortAuras)

    local liteFull = false
    -- Membership edges keep el.sorted exact WITHOUT a rebuild or table.sort:
    -- the default order keys (isPlayerAura, then auraInstanceID) are immutable
    -- per instance, so an add lands at one binary-searched index and a remove
    -- deletes one index -- only icons from that index onward shift. Valid only
    -- while the list was last built under the default comparator and has not
    -- been wiped (occupant change / forced full / custom sort installed).
    local edgeDirty
    local canEdge = stableOrder and el._sortedValid and el.sorted
    -- Occupant belt for the INCREMENTAL path: updateInfo deltas are only
    -- meaningful against the creature el.all was built from, and the wipe
    -- enforcing that lives in the full branch -- which only runs when a full
    -- pass ARRIVES. If any swap path is ever missed, incrementals would
    -- trickle the new unit's deltas onto the old unit's cache. A PLAIN guid
    -- that differs from the cache's promotes the pass to a forced full.
    -- Secret guids stay incremental: they cannot be compared, swaps are
    -- covered by the explicit swap-event handlers (see Adopt), and promoting
    -- every combat event would forfeit the content-split win.
    if not isFullUpdate then
        local g = UnitGUID(unit)
        if g and not (issecretvalue and issecretvalue(g)) and g ~= el._allGuid then
            isFullUpdate, forcedFull = true, true
        end
    end
    if isFullUpdate then
        -- Full pass with membership diff. The eventless poll (ToT / focus
        -- target) dispatches here every tick with no updateInfo, almost
        -- always over an UNCHANGED aura set: reuse each known instance's
        -- immutable classification (filter verdicts are per-instance
        -- constants; ApplyEUIAuraFilter resets el.all on settings changes),
        -- and when the set is identical skip the rebuild/sort/anchor
        -- entirely -- the lite repaint arm below re-arms only the
        -- live-varying visuals (duration, stacks).
        local all = el.all
        local active = el.active
        if not all then all = {}; el.all = all end
        if not active then active = {}; el.active = active end

        -- Occupant guard: instance IDs are only comparable across passes for
        -- the SAME creature behind the token. A forced full (unit swap,
        -- settings change) or an occupant change wipes; a SECRET guid
        -- (hostile units in instanced combat) cannot be compared, so those
        -- units wipe every pass -- exactly the library's behavior, the diff
        -- simply never engages for them.
        local guid = UnitGUID(unit)
        local plainGuid = guid and not (issecretvalue and issecretvalue(guid))
        if forcedFull or not plainGuid or el._allGuid ~= guid then
            table.wipe(all)
            table.wipe(active)
            el._allN = nil
            el._sortedValid = nil
            el._allGuid = plainGuid and guid or nil
        end

        local slots = { C_UnitAuras.GetAuraSlots(unit, filter) }
        local seen = table.wipe(el._fullSeen or {})
        el._fullSeen = seen
        local walkN = 0
        local anyNew = false
        for i = 2, #slots do
            local data = C_UnitAuras.GetAuraDataBySlot(unit, slots[i])
            if data then
                local iid = data.auraInstanceID
                walkN = walkN + 1
                seen[iid] = true
                local known = all[iid]
                if known then
                    -- Carry the immutable classification; keep the fresh
                    -- data table so later passes never read stale fields.
                    data.isPlayerAura = known.isPlayerAura
                    data.isHarmfulAura = known.isHarmfulAura
                    all[iid] = data
                else
                    anyNew = true
                    data = processData(el, unit, data, filter)
                    all[iid] = data
                    if (el.FilterAura or FilterAura)(el, unit, data, filter) then
                        active[iid] = true
                    end
                end
            end
        end

        if not anyNew and walkN == (el._allN or -1) then
            -- Identical set: nothing membership-side to do.
            liteFull = true
        else
            -- Prune instances that are gone, then take the full render path.
            for iid in next, all do
                if not seen[iid] then
                    all[iid] = nil
                    active[iid] = nil
                end
            end
            changed = true
        end
        el._allN = walkN
    else
        if updateInfo.addedAuras then
            for _, data in next, updateInfo.addedAuras do
                if not C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, data.auraInstanceID, filter) then
                    if el.all[data.auraInstanceID] == nil then
                        el._allN = (el._allN or 0) + 1
                    end
                    local wasActive = el.active[data.auraInstanceID]
                    el.all[data.auraInstanceID] = processData(el, unit, data, filter)

                    if (el.FilterAura or FilterAura)(el, unit, data, filter) then
                        el.active[data.auraInstanceID] = true
                        local s = not wasActive and canEdge and el.sorted
                        if s then
                            local stored = el.all[data.auraInstanceID]
                            local lo, hi = 1, #s + 1
                            while lo < hi do
                                local mid = math.floor((lo + hi) * 0.5)
                                local m = s[mid]
                                local less
                                if stored.isPlayerAura ~= m.isPlayerAura then
                                    less = stored.isPlayerAura
                                else
                                    less = stored.auraInstanceID < m.auraInstanceID
                                end
                                if less then hi = mid else lo = mid + 1 end
                            end
                            table.insert(s, lo, stored)
                            if not edgeDirty or lo < edgeDirty then edgeDirty = lo end
                        else
                            changed = true
                        end
                    end
                end
            end
        end

        if updateInfo.updatedAuraInstanceIDs then
            for _, auraInstanceID in next, updateInfo.updatedAuraInstanceIDs do
                if el.all[auraInstanceID] then
                    local data = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID)
                    if not data then
                        -- Update racing its own removal: a forcibly removed aura
                        -- (dispel, trap break, absorb consumed) can appear in
                        -- updatedAuraInstanceIDs of the SAME payload that removes
                        -- it, and the fetch comes back nil. Storing that nil
                        -- silently deleted the el.all entry while active/sorted
                        -- still held the aura -- and the removal loop below is
                        -- gated on el.all, so it then skipped it, orphaning the
                        -- icon permanently (field-reported: dead icon with no
                        -- tooltip, duplicated once the aura is reapplied; the
                        -- prune can't recover it either, it iterates el.all).
                        -- Treat the nil fetch as the removal it really is, with
                        -- the exact bookkeeping of the removal branch; the
                        -- removal loop stays consistent whether or not the id
                        -- also arrives there.
                        el.all[auraInstanceID] = nil
                        el._allN = math.max(0, (el._allN or 1) - 1)
                        if el.active[auraInstanceID] then
                            el.active[auraInstanceID] = nil
                            local s = canEdge and el.sorted
                            local idx
                            if s then
                                for i = 1, #s do
                                    if s[i].auraInstanceID == auraInstanceID then idx = i; break end
                                end
                            end
                            if idx then
                                table.remove(s, idx)
                                if not edgeDirty or idx < edgeDirty then edgeDirty = idx end
                            else
                                changed = true
                            end
                        end
                    else
                        el.all[auraInstanceID] = processData(el, unit, data, filter)

                        if el.active[auraInstanceID] then
                            el.active[auraInstanceID] = true
                            if stableOrder then
                                updated = true
                                if not updatedIDs then
                                    updatedIDs = table.wipe(el._updatedIDs or {})
                                    el._updatedIDs = updatedIDs
                                end
                                updatedIDs[auraInstanceID] = true
                            else
                                changed = true
                            end
                        end
                    end
                end
            end
        end

        if updateInfo.removedAuraInstanceIDs then
            for _, auraInstanceID in next, updateInfo.removedAuraInstanceIDs do
                if el.all[auraInstanceID] then
                    el.all[auraInstanceID] = nil
                    el._allN = math.max(0, (el._allN or 1) - 1)

                    if el.active[auraInstanceID] then
                        el.active[auraInstanceID] = nil
                        local s = canEdge and el.sorted
                        local idx
                        if s then
                            for i = 1, #s do
                                if s[i].auraInstanceID == auraInstanceID then idx = i; break end
                            end
                        end
                        if idx then
                            table.remove(s, idx)
                            if not edgeDirty or idx < edgeDirty then edgeDirty = idx end
                        else
                            changed = true
                        end
                    end
                end
            end
        end
    end

    -- Old semantics reported "changed" for content updates too; preserve
    -- that for any PostUpdateInfo consumer.
    if el.PostUpdateInfo then el:PostUpdateInfo(unit, changed or updated or liteFull or (edgeDirty ~= nil)) end

    if changed then
        el.sorted = table.wipe(el.sorted or {})

        for auraInstanceID in next, el.active do
            table.insert(el.sorted, el.all[auraInstanceID])
        end

        table.sort(el.sorted, el[sortKey] or el.SortAuras or SortAuras)
        el._sortedValid = stableOrder or nil

        local numVisible = math.min(num, #el.sorted)

        for i = 1, numVisible do
            updateAura(el, unit, el.sorted[i], i)
        end

        local visibleChanged = false

        if numVisible ~= el.visibleButtons then
            el.visibleButtons = numVisible
            visibleChanged = el.reanchorIfVisibleChanged
        end

        for i = numVisible + 1, #el do
            el[i]:Hide()
        end

        if visibleChanged or (el.createdButtons or 0) > (el.anchoredButtons or 0) then
            if visibleChanged then
                (el.SetPosition or SetPosition)(el, 1, numVisible)
            else
                (el.SetPosition or SetPosition)(el, (el.anchoredButtons or 0) + 1, el.createdButtons)
                el.anchoredButtons = el.createdButtons
            end
        end

        if el.PostUpdate then el:PostUpdate(unit) end
    elseif edgeDirty then
        -- Membership edge on a valid incremental list: entries at and after
        -- the touched index shifted by one slot -- repaint that suffix only,
        -- folding in any content-updated icons before it. No rebuild, no
        -- sort. Fresh data tables are preferred so repaints never read a
        -- stale entry left by an earlier content swap.
        local s = el.sorted
        local numVisible = math.min(num, #s)

        for i = 1, numVisible do
            local data = s[i]
            if data then
                if i >= edgeDirty then
                    local fresh = el.all[data.auraInstanceID] or data
                    if fresh ~= data then s[i] = fresh end
                    updateAura(el, unit, fresh, i)
                elseif updatedIDs and updatedIDs[data.auraInstanceID] then
                    local fresh = el.all[data.auraInstanceID] or data
                    s[i] = fresh
                    updateAura(el, unit, fresh, i)
                end
            end
        end

        local visibleChanged = false

        if numVisible ~= el.visibleButtons then
            el.visibleButtons = numVisible
            visibleChanged = el.reanchorIfVisibleChanged
        end

        for i = numVisible + 1, #el do
            el[i]:Hide()
        end

        if visibleChanged or (el.createdButtons or 0) > (el.anchoredButtons or 0) then
            if visibleChanged then
                (el.SetPosition or SetPosition)(el, 1, numVisible)
            else
                (el.SetPosition or SetPosition)(el, (el.anchoredButtons or 0) + 1, el.createdButtons)
                el.anchoredButtons = el.createdButtons
            end
        end

        if el.PostUpdate then el:PostUpdate(unit) end
    elseif updated then
        -- Content-only pass: membership unchanged, and with the immutable-key
        -- comparator the order cannot change either -- repaint ONLY the
        -- updated instances in place. Fresh data tables are swapped into the
        -- sorted list so later membership passes never read stale entries.
        local sorted = el.sorted
        if sorted then
            local numVisible = math.min(num, #sorted)
            for i = 1, numVisible do
                local data = sorted[i]
                local iid = data and data.auraInstanceID
                if iid and updatedIDs[iid] then
                    local fresh = el.all[iid] or data
                    sorted[i] = fresh
                    updateAura(el, unit, fresh, i)
                end
            end
        end

        if el.PostUpdate then el:PostUpdate(unit) end
    elseif liteFull then
        -- Identical-set full pass (eventless poll steady state): icons,
        -- classification, order and anchors are all unchanged -- re-arm
        -- only what varies without events: the duration object (aura
        -- refreshes on eventless units are only visible here) and stacks.
        local sorted = el.sorted
        if sorted then
            local numVisible = math.min(num, #sorted)
            for i = 1, numVisible do
                local data = sorted[i]
                local button = data and el[i]
                if button then
                    if button.Cooldown and not el.disableCooldown then
                        local duration = C_UnitAuras.GetAuraDuration(unit, data.auraInstanceID)
                        if duration then
                            button.Cooldown:SetCooldownFromDurationObject(duration)
                            button.Cooldown:Show()
                        else
                            button.Cooldown:Hide()
                        end
                    end
                    if button.Count then
                        button.Count:SetText(C_UnitAuras.GetAuraApplicationDisplayCount(unit, data.auraInstanceID, el.minCount or 2, el.maxCount or 999))
                    end
                end
            end
        end

        if el.PostUpdate then el:PostUpdate(unit) end
    end
end

-------------------------------------------------------------------------------
--  Driver + adoption
-------------------------------------------------------------------------------
local function DriveAuras(frame, event, unit, updateInfo)
    if frame.unit ~= unit then return end

    local isFull = not updateInfo or updateInfo.isFullUpdate

    local buffs = frame.Buffs
    if buffs then
        local forced = buffs.needFullUpdate
        buffs.needFullUpdate = false
        UpdateSide(buffs, unit, updateInfo, isFull or forced, forced, 'HELPFUL', 32, 'SortBuffs')
    end

    local debuffs = frame.Debuffs
    if debuffs then
        local forced = debuffs.needFullUpdate
        debuffs.needFullUpdate = false
        UpdateSide(debuffs, unit, updateInfo, isFull or forced, forced, 'HARMFUL', 40, 'SortDebuffs')
    end
end

-- Full update + full re-anchor: the library's ForceUpdate/no-event contract.
-- Also hooked onto UpdateAllElements (unit swaps, world entries) because
-- DisableElement removes the element from that path.
local function FullUpdate(frame)
    local unit = frame.unit
    if not unit then return end

    local buffs = frame.Buffs
    if buffs then buffs.needFullUpdate = true end
    local debuffs = frame.Debuffs
    if debuffs then debuffs.needFullUpdate = true end

    DriveAuras(frame, 'ForceUpdate', unit, nil)

    if buffs then
        (buffs.SetPosition or SetPosition)(buffs, 1, buffs.createdButtons or 0)
    end
    if debuffs then
        (debuffs.SetPosition or SetPosition)(debuffs, 1, debuffs.createdButtons or 0)
    end
end

local function ElementForceUpdate(element)
    local owner = element.__owner
    if owner then FullUpdate(owner) end
end

-- Adopt one spawned oUF frame: disable the library element and take over.
-- Reuses everything the library's Enable already initialized (__owner,
-- __restricted, tooltipAnchor, dispelColorCurve, createdButtons...).
local adopted = setmetatable({}, { __mode = 'k' })
function ns.EUIAuras_Adopt(frame)
    if not frame or adopted[frame] then return end
    if not (frame.Buffs or frame.Debuffs) then return end
    adopted[frame] = true

    frame:DisableElement('Auras')  -- unregisters the library handler + hides

    local buffs = frame.Buffs
    if buffs then
        buffs.ForceUpdate = ElementForceUpdate
        buffs:Show()
    end
    local debuffs = frame.Debuffs
    if debuffs then
        debuffs.ForceUpdate = ElementForceUpdate
        debuffs:Show()
    end

    frame:RegisterEvent('UNIT_AURA', DriveAuras)
    hooksecurefunc(frame, 'UpdateAllElements', FullUpdate)

    -- The hook alone does NOT cover unit swaps. oUF wires swap repaints
    -- (units.lua) by registering the UpdateAllElements FUNCTION VALUE at
    -- spawn time; hooksecurefunc rawsets a wrapper onto the frame AFTERWARDS,
    -- so those registrations keep dispatching the captured ORIGINAL and the
    -- wrapper never runs for them. Result: a target swap repainted every
    -- element except auras, leaving the previous unit's icons on the new
    -- unit. (Eventless units were never affected: their poll colon-calls
    -- frame:UpdateAllElements, which resolves to the wrapper.) Register our
    -- own handler beside oUF's for the same swap events it wires per unit --
    -- its event system appends multiple function handlers per event.
    local unit = frame.unit
    if unit == 'target' then
        frame:RegisterEvent('PLAYER_TARGET_CHANGED', FullUpdate, true)
    elseif unit == 'focus' then
        frame:RegisterEvent('PLAYER_FOCUS_CHANGED', FullUpdate, true)
    elseif unit == 'mouseover' then
        frame:RegisterEvent('UPDATE_MOUSEOVER_UNIT', FullUpdate, true)
    elseif unit and unit:match('^boss%d') then
        frame:RegisterEvent('INSTANCE_ENCOUNTER_ENGAGE_UNIT', FullUpdate, true)
        frame:RegisterEvent('UNIT_TARGETABLE_CHANGED', FullUpdate)
    elseif unit and unit:match('^arena%d') then
        frame:RegisterEvent('ARENA_OPPONENT_UPDATE', FullUpdate, true)
    end

    FullUpdate(frame)
end

-- Adopt everything spawned so far. Late spawns that miss the sweep simply
-- keep stock library behavior (correct, just unoptimized) -- fail-safe.
function ns.EUIAuras_AdoptAll()
    if not ns.frames then return end
    for _, frame in pairs(ns.frames) do
        if type(frame) == 'table' and frame.DisableElement then
            ns.EUIAuras_Adopt(frame)
        end
    end
end

local init = CreateFrame('Frame')
init:RegisterEvent('PLAYER_LOGIN')
init:SetScript('OnEvent', function(self)
    self:UnregisterEvent('PLAYER_LOGIN')
    -- Same UF-db-init delay the Player Auras skin uses: spawns complete
    -- during the parent's PLAYER_LOGIN enable flush, which runs before this.
    C_Timer.After(1, ns.EUIAuras_AdoptAll)
end)
