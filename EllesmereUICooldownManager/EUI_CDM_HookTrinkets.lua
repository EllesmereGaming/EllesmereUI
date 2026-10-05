if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_CDM_HookTrinkets.lua
--
--  Trinket frames, the CD Ready Glow re-evaluation and the desaturation curve
--  for custom frames.
--  Reads the earlier hook files through ns and ns._hookInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._hookInternals
-- EllesmereUICdmHooks.lua or an earlier hook file failed to load.
if not I or I.broken then return end
I.broken = true

local barDataByKey = ns.barDataByKey
local _ecmeFC = ns._ecmeFC

local hookFrameData = I.hookFrameData

-------------------------------------------------------------------------------
--  Trinket Frames
-------------------------------------------------------------------------------
local _trinketFrames = {}
ns._trinketFrames = _trinketFrames
local _trinketItemCache = { [13] = nil, [14] = nil }
local _trinketEventFrame = CreateFrame("Frame")

local function GetOrCreateTrinketFrame(slotID)
    local f = _trinketFrames[slotID]
    if f then return f end

    f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(36, 36)
    f:Hide()
    f:EnableMouse(false)

    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    ns.CdmOwnIconCrop(tex)
    f.Icon = tex
    f._tex = tex

    local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawEdge(false)
    cd:SetDrawBling(false)
    cd:SetHideCountdownNumbers(true)
    cd:EnableMouse(false)
    if cd.SetMouseClickEnabled then cd:SetMouseClickEnabled(false) end
    if cd.SetMouseMotionEnabled then cd:SetMouseMotionEnabled(false) end
    -- On-use trinket cooldowns fire no event at natural expiry, so the CD-driven
    -- re-saturate (UpdateTrinketCooldown) would not run at the ready edge while
    -- the CD-ready glow lit up immediately -- same lag as the item preset frames.
    -- Re-run the trinket CD check at the expiry edge to clear the desaturation.
    cd:SetScript("OnCooldownDone", function()
        if ns.UpdateTrinketCooldown then ns.UpdateTrinketCooldown(slotID) end
    end)
    f.Cooldown = cd
    f._cooldown = cd

    f._isTrinketFrame = true
    f._trinketSlot = slotID
    f.cooldownID = nil
    f.cooldownInfo = nil
    f.layoutIndex = (slotID == 13 and 99990) or (slotID == 14 and 99991)
        or (99900 + slotID)
    f.auraInstanceID = nil
    f.cooldownDuration = 0

    f:EnableMouse(true)
    if f.SetMouseClickEnabled then f:SetMouseClickEnabled(false) end
    f:SetScript("OnEnter", function(self)
        local ffc = _ecmeFC[self]
        local bd2 = ffc and ffc.barKey and barDataByKey[ffc.barKey]
        if not bd2 or not bd2.showTooltip then return end
        -- Honor the global "Show Tooltips" visibility mode (Blizzard Skin); a
        -- custom frame's explicit content population would otherwise re-show the
        -- tip after the global suppression hook hid it.
        if EllesmereUI and EllesmereUI._tooltipSuppressedByMode
           and EllesmereUI._tooltipSuppressedByMode(GameTooltip) then return end
        local itemID = GetInventoryItemID("player", self._trinketSlot)
        if itemID then
            GameTooltip_SetDefaultAnchor(GameTooltip, self)
            -- Prefer the equipped item's link so the tooltip reflects the actual
            -- upgrade/bonus IDs (real item level + stats) rather than the base item.
            -- SetItemByID is only a fallback if no link is available.
            local link = GetInventoryItemLink("player", self._trinketSlot)
            if link then
                GameTooltip:SetHyperlink(link)
            else
                GameTooltip:SetItemByID(itemID)
            end
            -- Re-assert the cursor anchor after content is set (see helper notes):
            -- the item content-setter can drop the tip's cursor anchor, so without
            -- this it never appears while "Anchor to Cursor" is on. No-op otherwise.
            if EllesmereUI and EllesmereUI._repointTooltipAtCursor then
                EllesmereUI._repointTooltipAtCursor(GameTooltip)
            end
            GameTooltip:Show()
            -- This is our own already-equipped trinket, so the side-by-side
            -- comparison (shopping) tooltips are just noise -- hide them after the
            -- tip is shown. Done here rather than by toggling the alwaysCompareItems
            -- CVar: mutating a user setting on every combat-time hover is wasteful
            -- and leaks the "off" state if anything errors mid-build.
            if GameTooltip_HideShoppingTooltips then
                GameTooltip_HideShoppingTooltips(GameTooltip)
            end
        end
    end)
    f:SetScript("OnLeave", GameTooltip_Hide)

    _trinketFrames[slotID] = f
    return f
end

local function UpdateTrinketFrame(slotID)
    local f = _trinketFrames[slotID]
    if not f then return end
    -- Decoration is the settings/content edge: drop the cooldown push memo
    -- (UpdateTrinketCooldown) so the next event re-pushes and re-derives
    -- the desaturation against fresh settings.
    f._cdMemoStart, f._cdMemoDur = nil, nil
    local itemID = GetInventoryItemID("player", slotID)
    _trinketItemCache[slotID] = itemID
    if not itemID then
        f._slotScanPending = nil
        -- An empty read is also what the login window returns before the inventory
        -- has synced: flag it so the PLAYER_ENTERING_WORLD retry sweep re-reads the
        -- slot (SlotScanIncomplete) instead of leaving the frame hidden until the next
        -- equipment change.
        f._slotEmptyRead = true
        f:Hide()
        return
    end
    f._slotEmptyRead = nil
    -- Item data not in the client cache yet (cold cache at login): GetItemSpell
    -- reads nil for an on-use item, which the passive test below would take as
    -- conclusive and nothing would ever re-scan. Keep the previous state,
    -- request the load and let ITEM_DATA_LOAD_RESULT re-run the scan.
    if C_Item.IsItemDataCachedByID and not C_Item.IsItemDataCachedByID(itemID) then
        f._slotScanPending = true
        C_Item.RequestLoadItemDataByID(itemID)
        _trinketEventFrame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
        return
    end
    f._slotScanPending = nil
    local icon = C_Item.GetItemIconByID(itemID)
    if icon and f._tex then f._tex:SetTexture(icon) end
    local _, spellID = C_Item.GetItemSpell(itemID)
    f._trinketSpellID = spellID
    if slotID ~= 13 and slotID ~= 14 then
        -- User-added equipment slot: the use effect usually comes from an
        -- ENCHANT (engineering tinkers like Nitro Boosts), which exists only
        -- on the equipped INSTANCE -- the base item has no use spell, so the
        -- trinket path's GetItemSpell/GetItemByID scan can never see it.
        -- Scan the instance tooltip for a localized "Use:" line instead.
        local hasUse = nil
        local tip = C_TooltipInfo and C_TooltipInfo.GetInventoryItem
            and C_TooltipInfo.GetInventoryItem("player", slotID)
        if tip and tip.lines then
            hasUse = false
            local prefix = ITEM_SPELL_TRIGGER_ONUSE
            for _, tipLine in ipairs(tip.lines) do
                local lt = tipLine.leftText
                if lt and prefix and lt:sub(1, #prefix) == prefix then
                    hasUse = true
                    break
                end
            end
        end
        if spellID and spellID > 0 then
            -- Base item carries its own use spell (on-use gear).
            f._trinketIsOnUse = true
            f._slotScanPending = nil
        elseif hasUse == nil then
            -- Tooltip data not cached yet: keep the previous state and let
            -- the login/equip retry timers re-run the scan.
            f._slotScanPending = true
        else
            f._trinketIsOnUse = hasUse
            f._slotScanPending = nil
        end
        return
    end
    local isRealOnUse = false
    local scanConclusive = false
    if spellID and spellID > 0 then
        local locale = GetLocale()
        if locale == "enUS" or locale == "enGB" then
            -- The "Use: ... (X Min Cooldown)" line is the use spell's
            -- DESCRIPTION, loaded separately from the item data: on a cold
            -- spell cache the tooltip omits the line entirely and the scan
            -- would read an on-use trinket as passive. Blizzard's signal is an
            -- empty description until SPELL_TEXT_UPDATE fires for the spell
            -- (nil when the spell record itself is not loaded yet).
            local desc = C_Spell.GetSpellDescription(spellID)
            local descLoaded = desc ~= nil and desc ~= ""
            if not descLoaded then
                f._slotScanPending = true
                if C_Spell.RequestLoadSpellData then C_Spell.RequestLoadSpellData(spellID) end
                _trinketEventFrame:RegisterEvent("SPELL_TEXT_UPDATE")
                _trinketEventFrame:RegisterEvent("SPELL_DATA_LOAD_RESULT")
                return
            end
            local tipData = C_TooltipInfo and C_TooltipInfo.GetItemByID(itemID)
            if tipData and tipData.lines then
                -- Conclusive only once the tooltip actually carries the Use
                -- line (GetItemSpell only reports on-use spells, so the line
                -- always arrives once the spell text is in); until then the
                -- text is still loading and SPELL_TEXT_UPDATE re-runs us.
                local usePrefix = ITEM_SPELL_TRIGGER_ONUSE
                for _, tipLine in ipairs(tipData.lines) do
                    local lt = tipLine.leftText
                    if lt and usePrefix and lt:sub(1, #usePrefix) == usePrefix then
                        scanConclusive = true
                    end
                    if lt and lt:find("Cooldown%)") then
                        local cdStr = lt:match("%((.+Cooldown)%)")
                        if cdStr then
                            -- Tooltip data carries raw grammar tokens
                            -- ("2 |4Min:Min; Cooldown"); reduce to the
                            -- singular so the unit parse sees "2 Min".
                            cdStr = cdStr:gsub("|4(%a+):[^;]*;", "%1")
                            local totalSec = 0
                            for num, unit in cdStr:gmatch("(%d+)%s*(%a+)") do
                                local n = tonumber(num)
                                if n then
                                    local u = unit:lower()
                                    if u == "min" then totalSec = totalSec + n * 60
                                    elseif u == "sec" then totalSec = totalSec + n
                                    elseif u == "hr" or u == "hour" then totalSec = totalSec + n * 3600
                                    end
                                end
                            end
                            if totalSec >= 10 then isRealOnUse = true end
                        end
                    end
                end
                if not scanConclusive then
                    f._slotScanPending = true
                    if C_Spell.RequestLoadSpellData then C_Spell.RequestLoadSpellData(spellID) end
                    _trinketEventFrame:RegisterEvent("SPELL_TEXT_UPDATE")
                    _trinketEventFrame:RegisterEvent("SPELL_DATA_LOAD_RESULT")
                end
            end
        else
            isRealOnUse = true
            scanConclusive = true
        end
    else
        -- GetItemSpell reports nothing for an item that carries a passive
        -- Equip proc alongside a separate on-use ability (Hex Lord's Dooming
        -- Idol), so the slot read as passive and the icon was dropped. Fall
        -- back to the localized "Use:" tooltip line the user-added equipment
        -- slot path above already relies on.
        local prefix = ITEM_SPELL_TRIGGER_ONUSE
        local tipData = C_TooltipInfo and C_TooltipInfo.GetItemByID(itemID)
        if tipData and tipData.lines and prefix then
            scanConclusive = true
            for _, tipLine in ipairs(tipData.lines) do
                local lt = tipLine.leftText
                if lt and lt:sub(1, #prefix) == prefix then
                    isRealOnUse = true
                    break
                end
            end
        end
    end
    if scanConclusive then
        f._trinketIsOnUse = isRealOnUse
    end
end
ns.UpdateTrinketFrame = UpdateTrinketFrame

-- Keep Colored (On CD) for PRESET frames (trinket slots, racials, potions and
-- user-injected custom spells). Those never run Blizzard's cooldown desaturation
-- -- the Fake-Active engine greys them itself (UpdateTrinketCooldown below and
-- ApplySpellDesaturation further down), so there's no SetDesaturated call for the
-- per-spell hook in DecorateFrame to ride; they read the setting from their own
-- cas entry instead, at the two points where they'd grey the icon. Zero-cost
-- when unused: the session gate is checked first (flipped by AddUserRule during the Fake-Active rebuild, so it survives /reload).
local function PresetKeepsColor(f)
    if not ns._cdmAnyNoDesatOnCD then return false end
    local fc = f and _ecmeFC[f]
    local sid = fc and fc.spellID
    if not sid or not ns.GetEffectiveCustomActiveState then return false end
    local cas = ns.GetEffectiveCustomActiveState(sid)
    return (cas and cas.noDesatOnCD) and true or false
end
ns.PresetKeepsColor = PresetKeepsColor

local function UpdateTrinketCooldown(slotID)
    local f = _trinketFrames[slotID]
    if not f or not f._trinketIsOnUse then return false end
    local start, dur, enable = GetInventoryItemCooldown("player", slotID)
    if start and dur and dur > 1.5 and enable == 1 then
        -- Push-on-edge: SPELL_UPDATE_COOLDOWN fires 10-17/sec in combat and
        -- re-pushed the SAME schedule every time. start/dur are plain for
        -- player inventory (compared unguarded here since forever); a
        -- modified cooldown changes them and re-pushes. The memo clears at
        -- decoration (UpdateTrinketFrame), so settings changes re-derive.
        if f._cdMemoStart ~= start or f._cdMemoDur ~= dur then
            f._cdMemoStart, f._cdMemoDur = start, dur
            f._cooldown:SetCooldown(start, dur)
            if f._tex then f._tex:SetDesaturated(not PresetKeepsColor(f)) end
        end
        return true
    else
        -- false = "cleared" marker, distinct from nil = "unknown" (fresh
        -- decoration): unknown must always paint the clear once.
        if f._cdMemoStart ~= false then
            f._cdMemoStart, f._cdMemoDur = false, false
            f._cooldown:Clear()
            if f._tex then f._tex:SetDesaturated(false) end
        end
        return false
    end
end
ns.UpdateTrinketCooldown = UpdateTrinketCooldown

_trinketEventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
_trinketEventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
_trinketEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
-- True when a slot frame's on-use detection needs another pass: trinkets whose
-- item has a spell the tooltip scan couldn't confirm yet, and user-added slots
-- whose instance tooltip wasn't cached (enchant/tinker lines).
local function SlotScanIncomplete(f)
    return (f._trinketSpellID and not f._trinketIsOnUse) or f._slotScanPending or f._slotEmptyRead
end

_trinketEventFrame:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "ITEM_DATA_LOAD_RESULT" or event == "SPELL_DATA_LOAD_RESULT"
       or event == "SPELL_TEXT_UPDATE" then
        -- Registered only while a slot scan waits on the item or use-spell
        -- data; a failed load just drops the pending flag (previous state
        -- stands). Item loads match on the cached item id, spell loads and
        -- description arrivals on the frame's use spell.
        local byItem = event == "ITEM_DATA_LOAD_RESULT"
        local ok = arg2
        if event == "SPELL_TEXT_UPDATE" then ok = true end
        local pending = false
        for slot, f in pairs(_trinketFrames) do
            if f._slotScanPending then
                local key
                if byItem then key = _trinketItemCache[slot] else key = f._trinketSpellID end
                if key == arg1 then
                    if ok then
                        UpdateTrinketFrame(slot)
                    else
                        f._slotScanPending = nil
                    end
                    if ns.QueueReanchor then ns.QueueReanchor() end
                end
            end
            if f._slotScanPending then pending = true end
        end
        if not pending then
            _trinketEventFrame:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
            _trinketEventFrame:UnregisterEvent("SPELL_DATA_LOAD_RESULT")
            _trinketEventFrame:UnregisterEvent("SPELL_TEXT_UPDATE")
        end
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        if arg1 == 13 or arg1 == 14 or _trinketFrames[arg1] then
            UpdateTrinketFrame(arg1)
            if ns.QueueReanchor then ns.QueueReanchor() end
            local f = _trinketFrames[arg1]
            if f and SlotScanIncomplete(f) then
                local slot = arg1
                C_Timer.After(1, function()
                    UpdateTrinketFrame(slot)
                    if ns.QueueReanchor then ns.QueueReanchor() end
                end)
            end
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateTrinketFrame(13)
        UpdateTrinketFrame(14)
        for slot in pairs(_trinketFrames) do
            if slot ~= 13 and slot ~= 14 then UpdateTrinketFrame(slot) end
        end
        -- Tooltip data may not be cached yet on login, causing on-use detection to
        -- fail. Retry only for slots whose scan is incomplete (tooltip wasn't ready).
        local needsRetry = false
        for _, f in pairs(_trinketFrames) do
            if SlotScanIncomplete(f) then needsRetry = true end
        end
        if needsRetry then
            C_Timer.After(2, function()
                for slot in pairs(_trinketFrames) do
                    UpdateTrinketFrame(slot)
                end
                if ns.QueueReanchor then ns.QueueReanchor() end
            end)
        end
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        for slot, f in pairs(_trinketFrames) do
            if f._trinketIsOnUse then
                UpdateTrinketCooldown(slot)
            end
        end
    end
end)

-------------------------------------------------------------------------------
--  CD Ready Glow: event-driven usability re-evaluation
--
--  Frames whose resolved cdStateEffect is a Resource Aware ready-glow
--  (pixelGlowReadyUsable/buttonGlowReadyUsable) are registered in a watched set
--  (ns.CDGlowWatch, called from the decoration paths). While non-empty,
--  SPELL_UPDATE_COOLDOWN + UNIT_POWER_FREQUENT (player) drive a dirty flag; a
--  hidden frame re-evaluates ONLY the watched frames on the next OnUpdate, then
--  hides again. While empty, no events are registered -- zero-cost unless a
--  ready-glow effect is actually configured. SPELL_UPDATE_USABLE alone is not
--  reliable for all resource types (e.g. Fury), so cooldown + power events stand
--  in; UNIT_POWER_FREQUENT (not UPDATE) is needed so continuous regen (energy
--  ticking toward a spell's cost) re-evaluates without waiting for a discrete
--  spend/gain event, the dirty flag capping work at once per frame. During the
--  loading-screen settle window (ns._cdmSoundSuppressed, shared with the CDM
--  sound system) API answers aren't trustworthy: the flush keeps current state
--  and retries shortly, and the first post-window pass is authoritative --
--  clearing a glow that came up stale across a /reload.
-------------------------------------------------------------------------------
do
    local _cdGlowWatched = setmetatable({}, { __mode = "k" })  -- frame -> true (watched) | false (one-shot kick)
    local _cdGlowDirty = false
    local _cdGlowEventsOn = false
    local _cdGlowRetryPending = false

    local _cdGlowUpdateFrame = ns.TakeShell()
    _cdGlowUpdateFrame:Hide()
    local _cdGlowEventFrame = ns.TakeShell()

    local function SetGlowEventsRegistered(on)
        if on == _cdGlowEventsOn then return end
        _cdGlowEventsOn = on
        if on then
            _cdGlowEventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
            _cdGlowEventFrame:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
        else
            _cdGlowEventFrame:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
            _cdGlowEventFrame:UnregisterEvent("UNIT_POWER_FREQUENT")
        end
    end

    local function QueueCDGlowUpdate()
        if _cdGlowDirty then return end
        _cdGlowDirty = true
        _cdGlowUpdateFrame:Show()
    end

    -- Register a frame whose resolved cdStateEffect is a Resource Aware ready-glow.
    -- Called from the decoration paths (DecorateFrame's SetDesaturated hook and
    -- RefreshCDMIconAppearance). The flush below prunes entries whose effect or claim
    -- went away and unregisters the events once nothing is watched.
    function ns.CDGlowWatch(frame)
        if not _cdGlowWatched[frame] then
            _cdGlowWatched[frame] = true
            SetGlowEventsRegistered(true)
        end
    end

    -- One-shot re-evaluation of an icon whose CD-state glow is owed
    -- (fd._cdGlowOwed: ns.StartCdGlow refused it, or the proc / active-state
    -- glow replaced it, while that glow held the shared overlay). The edge that
    -- ends the proc or active glow calls this, so the CD-state glow comes back
    -- at once instead of on the icon's next cooldown edge, which never comes
    -- when a buff outlasts its cooldown. The entry goes in as false: no events
    -- register for it and the next flush evaluates it once and drops it (a
    -- watched frame keeps its watch). Preset frames own their CD-state through
    -- the Fake-Active engine, so its coalesced pass is queued too, only for a
    -- frame that engine has painted (fd._presetCdTouched): a native icon's kick
    -- never wakes the preset sweep.
    function ns.CdGlowKick(frame)
        local fd = frame and hookFrameData[frame]
        if not fd then return end
        fd._cdGlowOwed = nil
        if not _cdGlowWatched[frame] then _cdGlowWatched[frame] = false end
        QueueCDGlowUpdate()
        if fd._presetCdTouched and ns.FakeActive_QueueCdStateEval then
            ns.FakeActive_QueueCdStateEval()
        end
    end

    _cdGlowUpdateFrame:SetScript("OnUpdate", function(self)
        self:Hide()
        _cdGlowDirty = false
        if not next(_cdGlowWatched) then
            SetGlowEventsRegistered(false)
            return
        end
        local hfd = ns._hookFrameData
        local efc = ns._ecmeFC
        local RSP = ns.ResolveSpellSettings
        if not hfd or not efc or not RSP then return end
        -- Settle window: keep current state, retry until the window ends;
        -- the first post-window pass is the authoritative one.
        if ns._cdmSoundSuppressed and ns._cdmSoundSuppressed() then
            if not _cdGlowRetryPending then
                _cdGlowRetryPending = true
                C_Timer.After(1, function()
                    _cdGlowRetryPending = false
                    QueueCDGlowUpdate()
                end)
            end
            return
        end
        for frame, watched in pairs(_cdGlowWatched) do
            local fd = hfd[frame]
            local fc2 = efc[frame]
            local sid2 = fc2 and fc2.spellID
            local bk2 = fc2 and fc2.barKey
            local keep = false
            -- Preset frames are owned by the Fake-Active engine (see the guard in
            -- the SetDesaturated hook); never let the spell-cooldown path drive
            -- their glow. keep=false below stops any leftover glow and unwatches.
            if fd and fd.glowOverlay and sid2 and bk2
               and not (ns.PresetHasCdState and ns.PresetHasCdState(frame)) then
                local ss2 = RSP(frame, sid2, ns.GetBarSpellData(bk2))
                local cse2 = ns.GetSpellCdStateEffect(frame, ss2)
                local plainGlow = cse2 == "pixelGlowReady" or cse2 == "buttonGlowReady"
                local usableGlow = cse2 == "pixelGlowReadyUsable" or cse2 == "buttonGlowReadyUsable"
                local onCdGlow = cse2 == "glowOnCD"
                if plainGlow or usableGlow or onCdGlow then
                    keep = true
                    -- Pool reassignment: glow state inherited from a previous
                    -- spell on this frame belongs to that spell -- reset now.
                    if fd._cdGlowBoundSid ~= sid2 then
                        fd._cdGlowBoundSid = sid2
                        if fd._cdStateGlowOn then
                            ns.StopCdGlow(fd)
                            fd._cdStateGlowOn = false
                        end
                    end
                    local liveSid = sid2
                    if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                        liveSid = C_SpellBook.FindSpellOverrideByID(sid2) or sid2
                    end
                    local ci = C_Spell.GetSpellCooldown(liveSid)
                    local onCD = ci and ci.isActive and not ci.isOnGCD
                    local shouldGlow
                    if onCdGlow then
                        -- Glow (On CD): mirror of the ready-glow safety net below, inverted.
                        shouldGlow = onCD and true or false
                    elseif onCD then
                        -- On cooldown always stops the glow -- a safety net
                        -- independent of the SetDesaturated hook, in case that
                        -- hook doesn't fire for a given transition (it never does
                        -- for EUI custom frames -- they use SetDesaturation).
                        shouldGlow = false
                    elseif usableGlow then
                        -- Resource Aware: also require castability (resources,
                        -- form, lockout). nil = no data yet -> not usable.
                        shouldGlow = (C_Spell.IsSpellUsable and C_Spell.IsSpellUsable(liveSid)) == true
                    else
                        -- Plain: cooldown state only.
                        shouldGlow = true
                    end
                    if shouldGlow then
                        -- A live proc or active-state glow owns the shared
                        -- overlay: ns.StartCdGlow lights only a Blackout beside
                        -- it, and the glow it holds back is kicked through
                        -- here again once that glow ends (ns.CdGlowKick).
                        if not fd._cdStateGlowOn then
                            local style = ns.CdReadyGlowStyle(cse2, ss2)
                            local cr, cg, cb = ns.CdReadyGlowColor(style, ss2)
                            fd._cdStateGlowOn = ns.StartCdGlow(fd, style, cr, cg, cb, ns.CdReadyGlowAlpha(ss2)) ~= nil
                        end
                    elseif fd._cdStateGlowOn then
                        ns.StopCdGlow(fd)
                        fd._cdStateGlowOn = false
                    end
                end
            end
            if not keep then
                -- Effect removed, spell unassigned, or frame released back to the pool:
                -- stop any leftover glow and drop the watch. Events unregister once the
                -- set drains (checked below and on the next queued flush).
                _cdGlowWatched[frame] = nil
                if fd and fd._cdStateGlowOn then
                    ns.StopCdGlow(fd)
                    fd._cdStateGlowOn = false
                end
            elseif not watched then
                -- One-shot kick (ns.CdGlowKick): evaluated once, now leaves.
                _cdGlowWatched[frame] = nil
            end
        end
        if not next(_cdGlowWatched) then
            SetGlowEventsRegistered(false)
        end
    end)

    -- One re-evaluation pass on the next frame. Called after rebuilds (FullCDMRebuild)
    -- and by the event listeners; no-ops instantly when nothing is watched.
    ns.QueueCDGlowResourceCheck = QueueCDGlowUpdate

    _cdGlowEventFrame:SetScript("OnEvent", function()
        QueueCDGlowUpdate()
    end)
end

-------------------------------------------------------------------------------
--  Desaturation curve for custom frames (taint-safe).
--  Step curve: 0 when no cooldown, 1 immediately when cooldown active.
--  EvaluateRemainingDuration on a DurationObject handles secret values
--  internally so we never compare secret numbers ourselves.
-------------------------------------------------------------------------------
-- Tail of a charge recharge, for "Suppress GCD". A recharge with less time left than
-- the running GCD is no longer what the swipe draws (the GCD outlasts it and takes
-- the frame over), so it must be suppressed like any other GCD. The remaining time is
-- secret and cannot be compared in Lua, so the threshold is applied engine-side via a
-- Step curve: below the GCD yields alpha 0, at/above yields the bar's normal alpha.
-- The result may itself be SECRET; never compare it. SetSwipeColor is
-- AllowedWhenTainted so it goes straight in. GCD length comes from UnitSpellHaste,
-- also secret in instanced combat: issecretvalue-first, falling back to 0 (unhasted
-- 1.5s GCD), which errs toward suppressing the tail slightly early on hasted players.
local _gcdTailCurves = {}
function ns.GCDTailAlpha(durObj, normalAlpha)
    normalAlpha = normalAlpha or 0
    if not (durObj and durObj.EvaluateRemainingDuration
            and C_CurveUtil and C_CurveUtil.CreateCurve
            and Enum and Enum.LuaCurveType) then
        return normalAlpha
    end
    local haste = (UnitSpellHaste and UnitSpellHaste("player")) or 0
    if (issecretvalue and issecretvalue(haste)) or type(haste) ~= "number" then
        haste = 0
    end
    local len = 1.5 / (1 + haste / 100)
    if len < 0.75 then len = 0.75 end          -- engine floor
    len = math.floor(len * 100 + 0.5) / 100    -- bound the curve cache
    local key = len .. ":" .. normalAlpha
    local curve = _gcdTailCurves[key]
    if not curve then
        curve = C_CurveUtil.CreateCurve()
        curve:SetType(Enum.LuaCurveType.Step)
        curve:AddPoint(0, 0)                -- recharge ends first: the swipe is the GCD
        curve:AddPoint(len, normalAlpha)    -- recharge outlasts it: leave it visible
        _gcdTailCurves[key] = curve
    end
    return durObj:EvaluateRemainingDuration(curve, normalAlpha)
end

local _desatCurve
if C_CurveUtil and C_CurveUtil.CreateCurve then
    _desatCurve = C_CurveUtil.CreateCurve()
    _desatCurve:SetType(Enum.LuaCurveType.Step)
    _desatCurve:AddPoint(0, 0)
    _desatCurve:AddPoint(0.001, 1)
end

local function ApplySpellDesaturation(f, durObj)
    if not f._tex then return end
    -- Out-of-band write: drop the drain's edge-gate memo so its next tick
    -- re-derives instead of trusting a value this call may have changed.
    f._lastDesatVal = nil
    if PresetKeepsColor(f) then f._tex:SetDesaturation(0); return end
    if durObj and _desatCurve and durObj.EvaluateRemainingDuration then
        local val = durObj:EvaluateRemainingDuration(_desatCurve, 0)
        f._tex:SetDesaturation(val or 0)
    else
        f._tex:SetDesaturation(0)
    end
end

I._trinketFrames, I._trinketItemCache = _trinketFrames, _trinketItemCache
I.ApplySpellDesaturation = ApplySpellDesaturation
I.GetOrCreateTrinketFrame, I.PresetKeepsColor = GetOrCreateTrinketFrame, PresetKeepsColor
I.UpdateTrinketCooldown, I.UpdateTrinketFrame = UpdateTrinketCooldown, UpdateTrinketFrame
I.broken = false
