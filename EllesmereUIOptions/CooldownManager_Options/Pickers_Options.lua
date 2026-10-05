if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CooldownManager_Options\Pickers_Options.lua
--  Cooldown Manager options: buff pickers, spell/item/slot ID popups, value
--  popups and EnsureAssignedSpells. Definitions only; the shared helpers come
--  from ns._CDMO_OptEnv (filled by EUI_CooldownManager_Options.lua).
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUICooldownManager"]
if not ns then return end  -- module disabled: no options page

-- Ensure assignedSpells is populated from live icons if nil; shared by spell picker, preview, and all add/remove handlers.
local function EnsureAssignedSpells(barKeyE)
    local env = ns._CDMO_OptEnv
    local NormalizeToBase, ResolveToLive = env.NormalizeToBase, env.ResolveToLive
    local sd = ns.GetBarSpellData(barKeyE)
    if not sd then return sd end
    if sd.assignedSpells then
        -- Normalize overrides to base IDs and dedupe in one pass. EXCEPTION: user-typed
        -- custom spell IDs (sd.customSpellIDs) are EXACT identities (tag, Phase 3 injection,
        -- and duration keys are all keyed by the typed id) -- GetBaseSpell can map a KNOWN
        -- spell to a different base id, severing the entry from its tag (e.g. 193265 ->
        -- 56641, blank icon). Tagged entries keep the typed id; a base form that matches
        -- one heals back to its tagged custom id, self-repairing severed saved data.
        local customN = sd.customSpellIDs
        local customByBase
        if customN then
            for cid in pairs(customN) do
                if type(cid) == "number" and cid > 0 then
                    local cb = NormalizeToBase(cid)
                    if cb ~= cid then
                        customByBase = customByBase or {}
                        customByBase[cb] = cid
                    end
                end
            end
        end
        local seen = {}
        local writeIdx = 1
        for readIdx = 1, #sd.assignedSpells do
            local raw = sd.assignedSpells[readIdx]
            local sid
            if customN and customN[raw] then
                sid = raw
            else
                sid = NormalizeToBase(raw)
                if customByBase and customByBase[sid] then
                    sid = customByBase[sid]
                end
            end
            if not seen[sid] then
                seen[sid] = true
                sd.assignedSpells[writeIdx] = sid
                writeIdx = writeIdx + 1
            end
        end
        for i = writeIdx, #sd.assignedSpells do sd.assignedSpells[i] = nil end
    end
    -- Append any live-bar spells missing from assignedSpells so the preview always
    -- matches the player's CDM bars (e.g. after re-talenting). EXCEPTION: skip while an
    -- imported layout is pending its first-load ghosting (_importGhostMode). Imported
    -- tracked spells spill onto default bars until migration ghosts them; materializing
    -- them here would mark them "assigned" and permanently defeat import-authoritative
    -- ghosting -- the import happens FROM this panel, so this rebuild fires before migration runs; the gate is essential.
    local importPending = false
    do
        local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
        local sk = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
        local aprof = sp and sk and sp[sk]
        if aprof and aprof._importGhostMode then importPending = true end
    end
    -- Buff-family bars get buffs ONLY through the picker (ShowBuffBarPicker ->
    -- AddTrackedSpell); assignedSpells is already authoritative, nothing legitimately
    -- spills onto them. Skipping the live-icon append for them fixes the duplicate-slot
    -- bug: a buff's resolved spellID drifts between ACTIVE (GetSpellID/GetAuraSpellID
    -- secret -> fallback) and INACTIVE (clean GetAuraSpellID), so post-combat the live
    -- icon can resolve to a different ID than stored and re-add the same buff. CD/utility bars still need the append (re-talent repop + spillover reconciliation).
    local bdForFamily = ns.barDataByKey and ns.barDataByKey[barKeyE]
    local isBuffFamilyE = ns.IsBarBuffFamily and ns.IsBarBuffFamily(bdForFamily or barKeyE)
    local liveIcons = (not importPending) and (not isBuffFamilyE)
                      and ns.cdmBarIcons and ns.cdmBarIcons[barKeyE]
    if liveIcons then
        if not sd.assignedSpells then sd.assignedSpells = {} end
        local removed = sd.removedSpells
        -- Never materialize a spell currently HIDDEN (in the ghost bar) onto a visible
        -- bar -- that recreates a both-state and the spell would reappear. Variant-aware
        -- against the active spec's ghost list; closes the window between migration ghosting a spell and the reanchor refreshing cdmBarIcons.
        local ghostSd = ns.GetBarSpellData and ns.GetBarSpellData("__ghost_cd")
        local ghostList = ghostSd and ghostSd.assignedSpells
        local FindVar = ns.FindVariantIndexInList
        -- Never materialize a spell the user deliberately placed on ANOTHER bar: a
        -- transient spillover during a profile swap can briefly render a custom-bar
        -- spell on cooldowns, and appending it here creates a both-state the route map
        -- must arbitrate. Claimed set built from the active spec's STORED bars, not the live route map (momentarily stale during the swap).
        local claimedElsewhere
        do
            local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
            local sk = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
            local aprof = sp and sk and sp[sk]
            local bsAll = aprof and aprof.barSpells
            if bsAll and ns.StoreVariantValue then
                for k, bsd in pairs(bsAll) do
                    if k ~= barKeyE and k ~= "__ghost_cd"
                       and type(bsd) == "table" and type(bsd.assignedSpells) == "table" then
                        for _, sid in ipairs(bsd.assignedSpells) do
                            if type(sid) == "number" and sid > 0 then
                                claimedElsewhere = claimedElsewhere or {}
                                ns.StoreVariantValue(claimedElsewhere, sid, true, false)
                            end
                        end
                    end
                end
            end
        end
        -- Walk live icons in on-screen order (CollectAndReanchor already placed
        -- spillover cooldowns at their Blizzard-layout positions). A new spell inserts
        -- after its left neighbour so it takes its true Blizzard-CDM position;
        -- appending at the end piled talent-swap spells after trinket/racial slots and
        -- never survived /reload. Presence check AND position cursor must be
        -- variant-aware (mirrors the reseed pass in EUI_CDM_Reconcile.lua): an
        -- exact-match set misses a stored entry with a different variant form, re-inserting a duplicate the normalize pass above then dedupes by deleting the saved slot.
        local insertPos = nil
        for _, icon in ipairs(liveIcons) do
            -- Resolve the live icon's DISPLAYED spell the same way the picker does
            -- (canonical = GetSpellID-first, active-frame cache), so a spell whose
            -- cooldownInfo base differs from its live talent form (e.g. 137029 Holy
            -- Paladin vs 432496 Holy Bulwark) dedups against the stored canonical ID
            -- instead of appending a duplicate. Falls back to raw FC spellID for our own custom frames.
            local _sid = (ns.GetCanonicalSpellIDForFrame and ns.GetCanonicalSpellIDForFrame(icon))
                         or (ns._ecmeFC[icon] and ns._ecmeFC[icon].spellID)
            -- Skip hosted-buff frames and their placeholders: their bar membership is
            -- the hosted MARKER entry; materializing their canonical spellID here would fabricate a plain COOLDOWN entry for the same spell (the buff frame's id resolves positive).
            local _fdLI = ns._hookFrameData and ns._hookFrameData[icon]
            if icon._isPlaceholderFrame or (_fdLI and _fdLI._isBuffViewerFrame) then
                -- Advance the cursor over the hosted buff's MARKER entry so a spell
                -- inserted after it lands after the buff, not squeezed beside the previous CD spell (mirrors the reseed pass).
                if type(_sid) == "number" and _sid > 0
                   and ns.HostedBuffMarkerToSpell
                   and not (ns.CdmFrameOverflowBar and ns.CdmFrameOverflowBar(icon)) then
                    for i = 1, #sd.assignedSpells do
                        local dec = ns.HostedBuffMarkerToSpell(sd.assignedSpells[i])
                        if dec and (dec == _sid
                            or (ns.IsVariantOf and ns.IsVariantOf(dec, _sid))) then
                            if not insertPos or i > insertPos then insertPos = i end
                            break
                        end
                    end
                end
                _sid = nil
            end
            -- Skip overflow-diverted icons: session-only here but BELONG to their
            -- source bar's assignedSpells -- materializing them (or advancing the cursor) would write the diversion into this bar's saved list.
            if _sid and ns.CdmFrameOverflowBar and ns.CdmFrameOverflowBar(icon) then
                _sid = nil
            end
            if _sid and _sid ~= 0 then
                if _sid > 0 then _sid = NormalizeToBase(_sid) end
                -- FindVar handles negatives by exact scan internally; variant matching is a superset of exact for positives.
                local at = FindVar and FindVar(sd.assignedSpells, _sid)
                if at then
                    -- Already has a slot (any variant form, or a custom trinket/item
                    -- marker): advance the cursor so the next NEW spell lands after it, matching on-screen order.
                    insertPos = at
                elseif _sid > 0
                   and not (removed and removed[_sid])
                   and not (ghostList and FindVar and FindVar(ghostList, _sid))
                   and not (claimedElsewhere and ns.ResolveVariantValue and ns.ResolveVariantValue(claimedElsewhere, _sid)) then
                    -- No anchored predecessor yet: this new spell is the left-most live icon, so it belongs at the front.
                    local pos = insertPos and (insertPos + 1) or 1
                    table.insert(sd.assignedSpells, pos, _sid)
                    insertPos = pos
                end
            end
        end
    end
    -- Materialize tracked-but-UNLEARNED CD/utility spells onto the DEFAULT bar of their
    -- category: Blizzard creates no viewer frame for an untalented spell, so the
    -- live-icon append above can never see them (without this they're invisible in the
    -- whole management UI). Sourced from the settings catalog
    -- (ns.EnumerateCDMSettingsCatalog), which respects the user's Blizzard arrangement:
    -- spells moved to Not Displayed never materialize, and each inserts after its
    -- nearest catalog predecessor already in the list. Guards, all load-bearing:  -- eui-style: allow comment-budget
    --   * default cooldowns/utility bars only (custom bars get spells via the picker)
    --   * LEARNED spells are the live-icon pass's job above (except one its
    --     Talent Conditions hide: no live icon, so it materializes here too)
    --   * skipped while import ghosting is pending, or before the spec's V6 ghost
    --     migration flag is stamped (ghosting must classify spells BEFORE materializing)
    --   * ghosted, explicitly-removed, and claimed-elsewhere spells skip
    --   * catalog nil (provider unavailable) = pass no-ops entirely
    if not importPending and (barKeyE == "cooldowns" or barKeyE == "utility")
       and ns.EnumerateCDMSettingsCatalog then
        local aprofM, migrated
        do
            local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
            local sk = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
            aprofM = sp and sk and sp[sk]
            migrated = aprofM and aprofM._barFilterModelV6 and true or false
        end
        local catalog = migrated and ns.EnumerateCDMSettingsCatalog() or nil
        if catalog and #catalog > 0 and IsPlayerSpell then
            local evc = Enum and Enum.CooldownViewerCategory
            -- Per-bar category wantSet, not a single wantCat value: a
            -- SpecAgnostic/EquipSlot cooldown entry (Midnight's category
            -- expansion) has no single category that could ever match a
            -- two-branch if/else, and would stay invisible to this
            -- materializer forever while untalented/unequipped.
            local wantSet
            if evc then
                if barKeyE == "cooldowns" then
                    -- EquipSlotEssential (7) deliberately absent: native
                    -- equipment entries are never claimed (the preset
                    -- slot/item lane owns items), so materializing their
                    -- rows would mint permanent frameless rank-holders.
                    wantSet = {
                        [evc.Essential or 0] = true,
                        [evc.SpecAgnosticEssential or 5] = true,
                    }
                else
                    wantSet = { [evc.Utility or 1] = true }
                end
            end
            local FindVar = ns.FindVariantIndexInList
            if wantSet and FindVar then
                if not sd.assignedSpells then sd.assignedSpells = {} end
                local list = sd.assignedSpells
                local removed = sd.removedSpells
                local ghostSdM = ns.GetBarSpellData and ns.GetBarSpellData("__ghost_cd")
                local ghostListM = ghostSdM and ghostSdM.assignedSpells
                -- Spells the user placed on ANY other bar keep their home.
                local claimedM
                do
                    local bsAll = aprofM and aprofM.barSpells
                    if bsAll and ns.StoreVariantValue then
                        for k, bsd in pairs(bsAll) do
                            if k ~= barKeyE and k ~= "__ghost_cd"
                               and type(bsd) == "table" and type(bsd.assignedSpells) == "table" then
                                for _, sid in ipairs(bsd.assignedSpells) do
                                    if type(sid) == "number" and sid > 0 then
                                        claimedM = claimedM or {}
                                        ns.StoreVariantValue(claimedM, sid, true, false)
                                    end
                                end
                            end
                        end
                    end
                end
                -- A LEARNED spell whose Talent Conditions dropped it from this bar in the
                -- last reanchor has no live icon either: materialize it like an unlearned
                -- one, so it keeps (or regains, after Repopulate or a Blizzard untrack and
                -- retrack) a preview slot and its conditions stay reachable. The set is
                -- shared and empty for non-users, so the check is skipped for them.
                local tcHidden = ns.TalentCondHiddenSet(barKeyE)
                if not next(tcHidden) then tcHidden = nil end
                for ci = 1, #catalog do
                    local ce = catalog[ci]
                    if wantSet[ce.category] then
                        local nsid = NormalizeToBase(ce.sid)
                        local isKnownM = true
                        if type(nsid) == "number" and nsid > 0 then
                            isKnownM = (IsPlayerSpell(nsid) or IsPlayerSpell(ce.sid)
                                or IsPlayerSpell(ResolveToLive(nsid))) and true or false
                            if isKnownM and tcHidden
                               and (ns.ResolveVariantValue(tcHidden, nsid)
                                    or ns.ResolveVariantValue(tcHidden, ce.sid)) then
                                isKnownM = false
                            end
                        end
                        if type(nsid) == "number" and nsid > 0
                           and not isKnownM
                           and not FindVar(list, nsid)
                           and not (removed and (removed[nsid] or removed[ce.sid]))
                           and not (ghostListM and FindVar(ghostListM, nsid))
                           and not (claimedM and ns.ResolveVariantValue and ns.ResolveVariantValue(claimedM, nsid)) then
                            local pos
                            for cj = ci - 1, 1, -1 do
                                local prevSid = NormalizeToBase(catalog[cj].sid)
                                local at = FindVar(list, prevSid)
                                if at then pos = at; break end
                            end
                            if pos then
                                table.insert(list, pos + 1, nsid)
                            else
                                table.insert(list, 1, nsid)
                            end
                        end
                    end
                end
            end
        end
    end
    -- Reconcile stale generic variants: a buff whose cooldownInfo base spellID differs
    -- from its live talent form (e.g. 137029 Holy Paladin stored next to 432496 Holy
    -- Bulwark) leaves a generic duplicate that variant dedup cannot collapse (no
    -- GetBaseSpell/override link). Map each pooled buff frame's base spellID -> its
    -- canonical live spellID, then drop any stored base whose canonical form is ALSO present, never stranding a lone entry.
    if sd.assignedSpells and #sd.assignedSpells > 1
       and ns.GetCanonicalSpellIDForFrame then
        local viewer = _G.BuffIconCooldownViewer
        local pool = viewer and viewer.itemFramePool
        if pool and pool.EnumerateActive then
            local canonOf
            for frame in pool:EnumerateActive() do
                local info = frame.cooldownInfo
                local baseSID = info and info.spellID
                local canon = ns.GetCanonicalSpellIDForFrame(frame)
                if type(baseSID) == "number" and baseSID > 0
                   and type(canon) == "number" and canon > 0 then
                    local nb, nc = NormalizeToBase(baseSID), NormalizeToBase(canon)
                    if nb ~= nc then
                        canonOf = canonOf or {}
                        canonOf[nb] = nc
                    end
                end
            end
            if canonOf then
                local present = {}
                for _, sid in ipairs(sd.assignedSpells) do present[sid] = true end
                local writeIdx = 1
                for readIdx = 1, #sd.assignedSpells do
                    local sid = sd.assignedSpells[readIdx]
                    local canon = canonOf[sid]
                    if not (canon and present[canon]) then
                        sd.assignedSpells[writeIdx] = sid
                        writeIdx = writeIdx + 1
                    end
                end
                for i = writeIdx, #sd.assignedSpells do sd.assignedSpells[i] = nil end
            end
        end
    end
    -- Keep/drop reconciliation now lives in the resident module (single
    -- implementation shared with the automatic reseed/settings-close
    -- triggers -- see ns.ReconcileAssignedSpellDrops in
    -- EUI_CDM_Reconcile.lua for the full decision ladder).
    if ns.ReconcileAssignedSpellDrops then
        sd = ns.ReconcileAssignedSpellDrops(barKeyE) or sd
    end
    -- Self-heal HOSTED buffs: a hosted buff must live in assignedSpells (Phase 3 sort
    -- keys off its MARKER entry), but a drop pass can strand one in hostedBuffSpellIDs
    -- alone (never in the Essential/Utility viewer). Re-append the MARKER when neither it nor a legacy plain entry represents the buff -- never the plain id, which would resurrect the spell's COOLDOWN form.
    if sd.hostedBuffSpellIDs and sd.assignedSpells and ns.HostedBuffMarker then
        for hsid in pairs(sd.hostedBuffSpellIDs) do
            if type(hsid) == "number" and hsid > 0 then
                local markerH = ns.HostedBuffMarker(hsid)
                local present = false
                for _, sid in ipairs(sd.assignedSpells) do
                    if sid == hsid or sid == markerH then present = true; break end
                end
                if not present then
                    sd.assignedSpells[#sd.assignedSpells + 1] = markerH
                    ns._spellOrderDirty = true
                end
            end
        end
    end
    return sd
end

---------------------------------------------------------------------------
--  Custom Spell ID popup (shared by ShowBuffBarPicker + ShowBuffToCDPicker). Lazily
--  builds a single global popup; each call re-binds the Add handler to the given bar.
--  withDuration adds the duration field (custom/preset buffs); onAdded(sid) runs after spellDuration/customSpellID storage.
---------------------------------------------------------------------------
local function ShowCustomSpellIDPopup(barKey, withDuration, onAdded, hideChargeWarn)
    local env = ns._CDMO_OptEnv
    local FONT_PATH, GetCDMOptOutline = env.FONT_PATH, env.GetCDMOptOutline
    local popupName = "EUI_CDM_SpellIDPopup"
    local popup = _G[popupName]
    if not popup then
        local POPUP_W, POPUP_H = 320, 160
        local dimmer = CreateFrame("Frame", popupName .. "Dimmer", UIParent)
        dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
        dimmer:SetAllPoints(UIParent)
        dimmer:EnableMouse(true)
        dimmer:Hide()
        local dimTex = dimmer:CreateTexture(nil, "BACKGROUND")
        dimTex:SetAllPoints(); dimTex:SetColorTexture(0, 0, 0, 0.25)
        dimmer:SetScript("OnMouseDown", function(self) self:Hide() end)

        popup = CreateFrame("Frame", popupName, dimmer)
        popup:SetSize(POPUP_W, POPUP_H)
        popup:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
        popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)
        popup:EnableMouse(true)
        local popBg = popup:CreateTexture(nil, "BACKGROUND")
        popBg:SetAllPoints(); popBg:SetColorTexture(0.077, 0.068, 0.058, 1)
        EllesmereUI.MakeBorder(popup, 1, 1, 1, 0.15, EllesmereUI.PP)

        local title = popup:CreateFontString(nil, "OVERLAY")
        title:SetFont(FONT_PATH, 14, GetCDMOptOutline())
        title:SetPoint("TOP", popup, "TOP", 0, -18)
        title:SetTextColor(1, 1, 1, 1)
        title:SetText(EllesmereUI.L("Add Custom Spell"))
        popup._title = title

        local editBox = CreateFrame("EditBox", nil, popup)
        editBox:SetSize(180, 28)
        editBox:SetPoint("TOP", title, "BOTTOM", 0, -16)
        editBox:SetAutoFocus(true)
        editBox:SetNumeric(true)
        editBox:SetMaxLetters(7)
        editBox:SetFont(FONT_PATH, 13, GetCDMOptOutline())
        editBox:SetTextColor(1, 1, 1, 0.9)
        editBox:SetJustifyH("CENTER")
        local ebBg = editBox:CreateTexture(nil, "BACKGROUND")
        ebBg:SetAllPoints(); ebBg:SetColorTexture(0.060, 0.049, 0.037, 1)
        EllesmereUI.MakeBorder(editBox, 1, 1, 1, 0.12, EllesmereUI.PP)

        local placeholder = editBox:CreateFontString(nil, "ARTWORK")
        placeholder:SetFont(FONT_PATH, 12, GetCDMOptOutline())
        placeholder:SetPoint("CENTER")
        placeholder:SetTextColor(0.5, 0.5, 0.5, 0.5)
        placeholder:SetText(EllesmereUI.L("Spell ID"))
        editBox:SetScript("OnTextChanged", function(self)
            if self:GetText() == "" then placeholder:Show() else placeholder:Hide() end
        end)
        popup._editBox = editBox

        local status = popup:CreateFontString(nil, "OVERLAY")
        status:SetFont(FONT_PATH, 11, GetCDMOptOutline())
        status:SetPoint("TOP", editBox, "BOTTOM", 0, -6)
        status:SetTextColor(1, 0.3, 0.3, 1)
        status:SetText("")
        popup._status = status
        popup._statusTimer = nil

        local ar, ag, ab = EllesmereUI.GetAccentColor()
        local addBtn = CreateFrame("Button", nil, popup)
        addBtn:SetSize(80, 28)
        addBtn:SetPoint("BOTTOMRIGHT", popup, "BOTTOM", -4, 16)
        local addBg = addBtn:CreateTexture(nil, "BACKGROUND")
        addBg:SetAllPoints(); addBg:SetColorTexture(ar, ag, ab, 0.15)
        EllesmereUI.MakeBorder(addBtn, ar, ag, ab, 0.3, EllesmereUI.PP)
        local addLbl = addBtn:CreateFontString(nil, "OVERLAY")
        addLbl:SetFont(FONT_PATH, 12, GetCDMOptOutline())
        addLbl:SetPoint("CENTER"); addLbl:SetText(EllesmereUI.L("Add"))
        addLbl:SetTextColor(ar, ag, ab, 0.9)
        addBtn:SetScript("OnEnter", function() addLbl:SetTextColor(1, 1, 1, 1) end)
        addBtn:SetScript("OnLeave", function() addLbl:SetTextColor(ar, ag, ab, 0.9) end)
        popup._addBtn = addBtn

        -- Permanent red note: a manually-entered custom spell has no live
        -- cooldown frame, so charge counts cannot be tracked for it. Shown
        -- only for CD/utility bars (charges do not apply to custom auras).
        local chargeWarn = popup:CreateFontString(nil, "OVERLAY")
        chargeWarn:SetFont(FONT_PATH, 10, GetCDMOptOutline())
        chargeWarn:SetPoint("LEFT", popup, "LEFT", 16, 0)
        chargeWarn:SetPoint("RIGHT", popup, "RIGHT", -16, 0)
        chargeWarn:SetPoint("BOTTOM", addBtn, "TOP", 0, 17)
        chargeWarn:SetJustifyH("CENTER")
        chargeWarn:SetTextColor(0.9, 0.3, 0.3, 1)
        chargeWarn:SetText(EllesmereUI.L("Custom spells cannot track charges."))
        popup._chargeWarn = chargeWarn

        local cancelBtn = CreateFrame("Button", nil, popup)
        cancelBtn:SetSize(80, 28)
        cancelBtn:SetPoint("BOTTOMLEFT", popup, "BOTTOM", 4, 16)
        local cBg = cancelBtn:CreateTexture(nil, "BACKGROUND")
        cBg:SetAllPoints(); cBg:SetColorTexture(0.12, 0.12, 0.12, 0.5)
        EllesmereUI.MakeBorder(cancelBtn, 1, 1, 1, 0.10, EllesmereUI.PP)
        local cLbl = cancelBtn:CreateFontString(nil, "OVERLAY")
        cLbl:SetFont(FONT_PATH, 12, GetCDMOptOutline())
        cLbl:SetPoint("CENTER"); cLbl:SetText(EllesmereUI.L("Cancel"))
        cLbl:SetTextColor(0.7, 0.7, 0.7, 0.8)
        cancelBtn:SetScript("OnEnter", function() cLbl:SetTextColor(1, 1, 1, 1) end)
        cancelBtn:SetScript("OnLeave", function() cLbl:SetTextColor(0.7, 0.7, 0.7, 0.8) end)
        cancelBtn:SetScript("OnClick", function() dimmer:Hide() end)
        popup._cancelBtn = cancelBtn

        editBox:SetScript("OnEscapePressed", function() dimmer:Hide() end)

        local durLabel = popup:CreateFontString(nil, "OVERLAY")
        durLabel:SetFont(FONT_PATH, 11, GetCDMOptOutline())
        durLabel:SetPoint("TOP", editBox, "BOTTOM", 0, -32)
        durLabel:SetTextColor(0.7, 0.7, 0.7, 0.85)
        durLabel:SetText(EllesmereUI.L("Duration (seconds)"))
        popup._durLabel = durLabel

        local durBox = CreateFrame("EditBox", nil, popup)
        durBox:SetSize(180, 28)
        durBox:SetPoint("TOP", durLabel, "BOTTOM", 0, -6)
        durBox:SetNumeric(true)
        durBox:SetMaxLetters(5)
        durBox:SetFont(FONT_PATH, 13, GetCDMOptOutline())
        durBox:SetTextColor(1, 1, 1, 0.9)
        durBox:SetJustifyH("CENTER")
        local durBg = durBox:CreateTexture(nil, "BACKGROUND")
        durBg:SetAllPoints(); durBg:SetColorTexture(0.060, 0.049, 0.037, 1)
        EllesmereUI.MakeBorder(durBox, 1, 1, 1, 0.12, EllesmereUI.PP)
        local durPlaceholder = durBox:CreateFontString(nil, "ARTWORK")
        durPlaceholder:SetFont(FONT_PATH, 12, GetCDMOptOutline())
        durPlaceholder:SetPoint("CENTER")
        durPlaceholder:SetTextColor(0.5, 0.5, 0.5, 0.5)
        durPlaceholder:SetText(EllesmereUI.L("Required"))
        durBox:SetScript("OnTextChanged", function(self)
            if self:GetText() == "" then durPlaceholder:Show() else durPlaceholder:Hide() end
        end)
        durBox:SetScript("OnEscapePressed", function() dimmer:Hide() end)
        popup._durBox = durBox

        popup._dimmer = dimmer
        _G[popupName] = popup
    end

    local function SetStatus(text, r, g, b)
        popup._status:SetText(text)
        popup._status:SetTextColor(r or 1, g or 0.3, b or 0.3, 1)
        if popup._statusTimer then popup._statusTimer:Cancel() end
        if text ~= "" then
            popup._statusTimer = C_Timer.NewTimer(2.5, function()
                popup._status:SetText("")
            end)
        end
    end

    local function DoAdd()
        local text = popup._editBox:GetText()
        local sid = tonumber(text)
        if not sid or sid <= 0 then
            SetStatus("Enter a valid spell ID")
            return
        end
        sid = math.floor(sid)
        local spellName = C_Spell.GetSpellName(sid)
        if not spellName then
            SetStatus("Unknown spell ID")
            return
        end
        local dur
        if withDuration then
            local durText = popup._durBox:GetText()
            dur = tonumber(durText)
            if not dur or dur <= 0 then
                SetStatus("Enter a duration in seconds")
                return
            end
            dur = math.floor(dur)
        end
        local sdChk = ns.GetBarSpellData(barKey)
        if sdChk and sdChk.assignedSpells then
            -- Variant-aware, mirroring AddTrackedSpell's own dedup. An
            -- exact-only check lets a variant-duplicate through, which
            -- AddTrackedSpell then silently refuses AFTER the custom tag
            -- below is written (orphaned tag, nothing rendered).
            local dup
            if ns.FindVariantIndexInList then
                dup = ns.FindVariantIndexInList(sdChk.assignedSpells, sid)
            else
                for _, existing in ipairs(sdChk.assignedSpells) do
                    if existing == sid then dup = true; break end
                end
            end
            if dup then
                SetStatus("Already tracked")
                return
            end
        end
        if withDuration and dur then
            local sdStore = ns.GetBarSpellData(barKey)
            if sdStore then
                if not sdStore.spellDurations then sdStore.spellDurations = {} end
                sdStore.spellDurations[sid] = dur
            end
        end
        popup._dimmer:Hide()
        local sdTag = ns.GetBarSpellData(barKey)
        if sdTag then
            if not sdTag.customSpellIDs then sdTag.customSpellIDs = {} end
            sdTag.customSpellIDs[sid] = true
        end
        if onAdded then onAdded(sid) end
    end

    popup._addBtn:SetScript("OnClick", DoAdd)
    popup._editBox:SetScript("OnEnterPressed", DoAdd)
    popup._editBox:SetText("")
    popup._status:SetText("")
    if withDuration then
        popup:SetHeight(220)
        popup._durLabel:Show()
        popup._durBox:Show()
        popup._durBox:SetText("")
        if popup._chargeWarn then popup._chargeWarn:Hide() end
    else
        popup:SetHeight(164)
        popup._durLabel:Hide()
        popup._durBox:Hide()
        -- Buff contexts (aura-tracked) hide the CD-only charges note.
        if popup._chargeWarn then popup._chargeWarn:SetShown(not hideChargeWarn) end
    end
    ns.PadPopupOpen(popup._dimmer, popup, popup._cancelBtn)  -- controller cursor
    popup._dimmer:Show()
    popup._editBox:SetFocus()
end

---------------------------------------------------------------------------
--  Custom Item ID popup (shared by ShowSpellPicker + ShowBuffBarPicker).
--  Item is stored as a negative marker (-itemID) so the item-preset path
--  renders icon/cooldown/count. onAdded runs after validation; the caller
--  handles AddTrackedSpell.
---------------------------------------------------------------------------
local function ShowCustomItemIDPopup(barKey, onAdded)
    local env = ns._CDMO_OptEnv
    local FONT_PATH, GetCDMOptOutline = env.FONT_PATH, env.GetCDMOptOutline
    local popupName = "EUI_CDM_ItemIDPopup"
    local popup = _G[popupName]
    if not popup then
        local POPUP_W, POPUP_H = 320, 164
        local dimmer = CreateFrame("Frame", popupName .. "Dimmer", UIParent)
        dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
        dimmer:SetAllPoints(UIParent)
        dimmer:EnableMouse(true)
        dimmer:Hide()
        local dimTex = dimmer:CreateTexture(nil, "BACKGROUND")
        dimTex:SetAllPoints(); dimTex:SetColorTexture(0, 0, 0, 0.25)
        dimmer:SetScript("OnMouseDown", function(self) self:Hide() end)

        popup = CreateFrame("Frame", popupName, dimmer)
        popup:SetSize(POPUP_W, POPUP_H)
        popup:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
        popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)
        popup:EnableMouse(true)
        local popBg = popup:CreateTexture(nil, "BACKGROUND")
        popBg:SetAllPoints(); popBg:SetColorTexture(0.077, 0.068, 0.058, 1)
        EllesmereUI.MakeBorder(popup, 1, 1, 1, 0.15, EllesmereUI.PP)

        local title = popup:CreateFontString(nil, "OVERLAY")
        title:SetFont(FONT_PATH, 14, GetCDMOptOutline())
        title:SetPoint("TOP", popup, "TOP", 0, -18)
        title:SetTextColor(1, 1, 1, 1)
        title:SetText(EllesmereUI.L("Add Custom Item"))
        popup._title = title

        local editBox = CreateFrame("EditBox", nil, popup)
        editBox:SetSize(180, 28)
        editBox:SetPoint("TOP", title, "BOTTOM", 0, -16)
        editBox:SetAutoFocus(true)
        editBox:SetNumeric(true)
        editBox:SetMaxLetters(9)
        editBox:SetFont(FONT_PATH, 13, GetCDMOptOutline())
        editBox:SetTextColor(1, 1, 1, 0.9)
        editBox:SetJustifyH("CENTER")
        local ebBg = editBox:CreateTexture(nil, "BACKGROUND")
        ebBg:SetAllPoints(); ebBg:SetColorTexture(0.060, 0.049, 0.037, 1)
        EllesmereUI.MakeBorder(editBox, 1, 1, 1, 0.12, EllesmereUI.PP)

        local placeholder = editBox:CreateFontString(nil, "ARTWORK")
        placeholder:SetFont(FONT_PATH, 12, GetCDMOptOutline())
        placeholder:SetPoint("CENTER")
        placeholder:SetTextColor(0.5, 0.5, 0.5, 0.5)
        placeholder:SetText(EllesmereUI.L("Item ID"))
        editBox:SetScript("OnTextChanged", function(self)
            if self:GetText() == "" then placeholder:Show() else placeholder:Hide() end
        end)
        popup._editBox = editBox

        local status = popup:CreateFontString(nil, "OVERLAY")
        status:SetFont(FONT_PATH, 11, GetCDMOptOutline())
        status:SetPoint("TOP", editBox, "BOTTOM", 0, -6)
        status:SetTextColor(1, 0.3, 0.3, 1)
        status:SetText("")
        popup._status = status
        popup._statusTimer = nil

        local ar, ag, ab = EllesmereUI.GetAccentColor()
        local addBtn = CreateFrame("Button", nil, popup)
        addBtn:SetSize(80, 28)
        addBtn:SetPoint("BOTTOMRIGHT", popup, "BOTTOM", -4, 16)
        local addBg = addBtn:CreateTexture(nil, "BACKGROUND")
        addBg:SetAllPoints(); addBg:SetColorTexture(ar, ag, ab, 0.15)
        EllesmereUI.MakeBorder(addBtn, ar, ag, ab, 0.3, EllesmereUI.PP)
        local addLbl = addBtn:CreateFontString(nil, "OVERLAY")
        addLbl:SetFont(FONT_PATH, 12, GetCDMOptOutline())
        addLbl:SetPoint("CENTER"); addLbl:SetText(EllesmereUI.L("Add"))
        addLbl:SetTextColor(ar, ag, ab, 0.9)
        addBtn:SetScript("OnEnter", function() addLbl:SetTextColor(1, 1, 1, 1) end)
        addBtn:SetScript("OnLeave", function() addLbl:SetTextColor(ar, ag, ab, 0.9) end)
        popup._addBtn = addBtn

        local cancelBtn = CreateFrame("Button", nil, popup)
        cancelBtn:SetSize(80, 28)
        cancelBtn:SetPoint("BOTTOMLEFT", popup, "BOTTOM", 4, 16)
        local cBg = cancelBtn:CreateTexture(nil, "BACKGROUND")
        cBg:SetAllPoints(); cBg:SetColorTexture(0.12, 0.12, 0.12, 0.5)
        EllesmereUI.MakeBorder(cancelBtn, 1, 1, 1, 0.10, EllesmereUI.PP)
        local cLbl = cancelBtn:CreateFontString(nil, "OVERLAY")
        cLbl:SetFont(FONT_PATH, 12, GetCDMOptOutline())
        cLbl:SetPoint("CENTER"); cLbl:SetText(EllesmereUI.L("Cancel"))
        cLbl:SetTextColor(0.7, 0.7, 0.7, 0.8)
        cancelBtn:SetScript("OnEnter", function() cLbl:SetTextColor(1, 1, 1, 1) end)
        cancelBtn:SetScript("OnLeave", function() cLbl:SetTextColor(0.7, 0.7, 0.7, 0.8) end)
        cancelBtn:SetScript("OnClick", function() dimmer:Hide() end)
        popup._cancelBtn = cancelBtn

        editBox:SetScript("OnEscapePressed", function() dimmer:Hide() end)

        popup._dimmer = dimmer
        _G[popupName] = popup
    end

    local function SetStatus(text, r, g, b)
        popup._status:SetText(text)
        popup._status:SetTextColor(r or 1, g or 0.3, b or 0.3, 1)
        if popup._statusTimer then popup._statusTimer:Cancel() end
        if text ~= "" then
            popup._statusTimer = C_Timer.NewTimer(2.5, function()
                popup._status:SetText("")
            end)
        end
    end

    local function DoAdd()
        local text = popup._editBox:GetText()
        local itemID = tonumber(text)
        -- IDs below 100 are reserved: the -1..-19 range encodes equipment slots (never renderable as items before this cutoff existed).
        if not itemID or itemID < 100 then
            SetStatus("Enter a valid item ID")
            return
        end
        itemID = math.floor(itemID)
        local itemName = C_Item.GetItemNameByID(itemID)
        if not itemName then
            -- Item data not cached yet -- request it and ask the user to retry.
            C_Item.RequestLoadItemDataByID(itemID)
            SetStatus("Loading item data, try again")
            return
        end
        local marker = -itemID
        local sdChk = ns.GetBarSpellData(barKey)
        if sdChk and sdChk.assignedSpells then
            for _, existing in ipairs(sdChk.assignedSpells) do
                if existing == marker then
                    SetStatus("Already tracked")
                    return
                end
            end
        end
        popup._dimmer:Hide()
        if onAdded then onAdded(marker) end
    end

    popup._addBtn:SetScript("OnClick", DoAdd)
    popup._editBox:SetScript("OnEnterPressed", DoAdd)
    popup._editBox:SetText("")
    popup._status:SetText("")
    ns.PadPopupOpen(popup._dimmer, popup, popup._cancelBtn)  -- controller cursor
    popup._dimmer:Show()
    popup._editBox:SetFocus()
end

---------------------------------------------------------------------------
--  Equipment Slot popup. Adds a slot-tracked entry (-slotID, the trinket -13/-14
--  encoding) so the icon follows whatever item is equipped there (e.g. slot 6 = belt +
--  its tinker). The name line echoes the typed slot (localized name + equipped item) so a bare number is confirmed before Add.
---------------------------------------------------------------------------
local function ShowEquipmentSlotPopup(barKey, onAdded)
    local env = ns._CDMO_OptEnv
    local FONT_PATH, GetCDMOptOutline = env.FONT_PATH, env.GetCDMOptOutline
    local popupName = "EUI_CDM_SlotIDPopup"
    local popup = _G[popupName]
    if not popup then
        local POPUP_W, POPUP_H = 320, 184
        local dimmer = CreateFrame("Frame", popupName .. "Dimmer", UIParent)
        dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
        dimmer:SetAllPoints(UIParent)
        dimmer:EnableMouse(true)
        dimmer:Hide()
        local dimTex = dimmer:CreateTexture(nil, "BACKGROUND")
        dimTex:SetAllPoints(); dimTex:SetColorTexture(0, 0, 0, 0.25)
        dimmer:SetScript("OnMouseDown", function(self) self:Hide() end)

        popup = CreateFrame("Frame", popupName, dimmer)
        popup:SetSize(POPUP_W, POPUP_H)
        popup:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
        popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)
        popup:EnableMouse(true)
        local popBg = popup:CreateTexture(nil, "BACKGROUND")
        popBg:SetAllPoints(); popBg:SetColorTexture(0.077, 0.068, 0.058, 1)
        EllesmereUI.MakeBorder(popup, 1, 1, 1, 0.15, EllesmereUI.PP)

        local title = popup:CreateFontString(nil, "OVERLAY")
        title:SetFont(FONT_PATH, 14, GetCDMOptOutline())
        title:SetPoint("TOP", popup, "TOP", 0, -18)
        title:SetTextColor(1, 1, 1, 1)
        title:SetText(EllesmereUI.L("Add Equipment Slot"))
        popup._title = title

        local editBox = CreateFrame("EditBox", nil, popup)
        editBox:SetSize(180, 28)
        editBox:SetPoint("TOP", title, "BOTTOM", 0, -16)
        editBox:SetAutoFocus(true)
        editBox:SetNumeric(true)
        editBox:SetMaxLetters(2)
        editBox:SetFont(FONT_PATH, 13, GetCDMOptOutline())
        editBox:SetTextColor(1, 1, 1, 0.9)
        editBox:SetJustifyH("CENTER")
        local ebBg = editBox:CreateTexture(nil, "BACKGROUND")
        ebBg:SetAllPoints(); ebBg:SetColorTexture(0.060, 0.049, 0.037, 1)
        EllesmereUI.MakeBorder(editBox, 1, 1, 1, 0.12, EllesmereUI.PP)

        local placeholder = editBox:CreateFontString(nil, "ARTWORK")
        placeholder:SetFont(FONT_PATH, 12, GetCDMOptOutline())
        placeholder:SetPoint("CENTER")
        placeholder:SetTextColor(0.5, 0.5, 0.5, 0.5)
        placeholder:SetText(EllesmereUI.L("Slot ID"))
        popup._editBox = editBox

        -- Live echo: localized slot name + the item currently equipped there, so the bare number is confirmed before Add.
        local nameLine = popup:CreateFontString(nil, "OVERLAY")
        nameLine:SetFont(FONT_PATH, 12, GetCDMOptOutline())
        nameLine:SetPoint("TOP", editBox, "BOTTOM", 0, -8)
        nameLine:SetWidth(POPUP_W - 24)
        nameLine:SetText("")
        popup._nameLine = nameLine

        editBox:SetScript("OnTextChanged", function(self)
            if self:GetText() == "" then placeholder:Show() else placeholder:Hide() end
            local slot = tonumber(self:GetText())
            local slotName = slot and ns.INV_SLOT_NAMES[slot]
            if slotName then
                local itemID = GetInventoryItemID("player", slot)
                local itemName = itemID and C_Item.GetItemNameByID(itemID)
                nameLine:SetTextColor(0.6, 1, 0.6, 1)
                nameLine:SetText(slotName .. " - " .. (itemName or EMPTY or ""))
            elseif slot then
                nameLine:SetTextColor(1, 0.4, 0.4, 0.9)
                nameLine:SetText("Enter a slot ID from 1 to 19")
            else
                nameLine:SetText("")
            end
        end)

        local status = popup:CreateFontString(nil, "OVERLAY")
        status:SetFont(FONT_PATH, 11, GetCDMOptOutline())
        status:SetPoint("TOP", nameLine, "BOTTOM", 0, -4)
        status:SetTextColor(1, 0.3, 0.3, 1)
        status:SetText("")
        popup._status = status
        popup._statusTimer = nil

        local ar, ag, ab = EllesmereUI.GetAccentColor()
        local addBtn = CreateFrame("Button", nil, popup)
        addBtn:SetSize(80, 28)
        addBtn:SetPoint("BOTTOMRIGHT", popup, "BOTTOM", -4, 16)
        local addBg = addBtn:CreateTexture(nil, "BACKGROUND")
        addBg:SetAllPoints(); addBg:SetColorTexture(ar, ag, ab, 0.15)
        EllesmereUI.MakeBorder(addBtn, ar, ag, ab, 0.3, EllesmereUI.PP)
        local addLbl = addBtn:CreateFontString(nil, "OVERLAY")
        addLbl:SetFont(FONT_PATH, 12, GetCDMOptOutline())
        addLbl:SetPoint("CENTER"); addLbl:SetText(EllesmereUI.L("Add"))
        addLbl:SetTextColor(ar, ag, ab, 0.9)
        addBtn:SetScript("OnEnter", function() addLbl:SetTextColor(1, 1, 1, 1) end)
        addBtn:SetScript("OnLeave", function() addLbl:SetTextColor(ar, ag, ab, 0.9) end)
        popup._addBtn = addBtn

        local cancelBtn = CreateFrame("Button", nil, popup)
        cancelBtn:SetSize(80, 28)
        cancelBtn:SetPoint("BOTTOMLEFT", popup, "BOTTOM", 4, 16)
        local cBg = cancelBtn:CreateTexture(nil, "BACKGROUND")
        cBg:SetAllPoints(); cBg:SetColorTexture(0.12, 0.12, 0.12, 0.5)
        EllesmereUI.MakeBorder(cancelBtn, 1, 1, 1, 0.10, EllesmereUI.PP)
        local cLbl = cancelBtn:CreateFontString(nil, "OVERLAY")
        cLbl:SetFont(FONT_PATH, 12, GetCDMOptOutline())
        cLbl:SetPoint("CENTER"); cLbl:SetText(EllesmereUI.L("Cancel"))
        cLbl:SetTextColor(0.7, 0.7, 0.7, 0.8)
        cancelBtn:SetScript("OnEnter", function() cLbl:SetTextColor(1, 1, 1, 1) end)
        cancelBtn:SetScript("OnLeave", function() cLbl:SetTextColor(0.7, 0.7, 0.7, 0.8) end)
        cancelBtn:SetScript("OnClick", function() dimmer:Hide() end)
        popup._cancelBtn = cancelBtn

        editBox:SetScript("OnEscapePressed", function() dimmer:Hide() end)

        popup._dimmer = dimmer
        _G[popupName] = popup
    end

    local function SetStatus(text, r, g, b)
        popup._status:SetText(text)
        popup._status:SetTextColor(r or 1, g or 0.3, b or 0.3, 1)
        if popup._statusTimer then popup._statusTimer:Cancel() end
        if text ~= "" then
            popup._statusTimer = C_Timer.NewTimer(2.5, function()
                popup._status:SetText("")
            end)
        end
    end

    local function DoAdd()
        local slot = tonumber(popup._editBox:GetText())
        if not slot or not ns.INV_SLOT_NAMES[slot] then
            SetStatus("Enter a slot ID from 1 to 19")
            return
        end
        local marker = -slot
        local sdChk = ns.GetBarSpellData(barKey)
        if sdChk and sdChk.assignedSpells then
            for _, existing in ipairs(sdChk.assignedSpells) do
                if existing == marker then
                    SetStatus("Already tracked")
                    return
                end
            end
        end
        popup._dimmer:Hide()
        if onAdded then onAdded(marker) end
    end

    popup._addBtn:SetScript("OnClick", DoAdd)
    popup._editBox:SetScript("OnEnterPressed", DoAdd)
    popup._editBox:SetText("")
    popup._status:SetText("")
    popup._nameLine:SetText("")
    ns.PadPopupOpen(popup._dimmer, popup, popup._cancelBtn)  -- controller cursor
    popup._dimmer:Show()
    popup._editBox:SetFocus()
end

---------------------------------------------------------------------------
--  Buff Bar Spell Picker
--  Shows ONLY spells from CDM buff categories (2, 3).
--  None grayed out. Selecting moves the spell to the target bar.
---------------------------------------------------------------------------
local function ShowBuffBarPicker(anchorFrame, targetBarKey, onChanged)
    local env = ns._CDMO_OptEnv
    local FONT_PATH, GetCDMOptOutline, RefreshCDPreview, optState = env.FONT_PATH, env.GetCDMOptOutline, env.RefreshCDPreview, env.optState
    if optState._spellPickerMenu and optState._spellPickerMenu:IsShown() then
        optState._spellPickerMenu:Hide()
        if optState._spellPickerMenu._anchorFrame == anchorFrame then return end
    end

    local mBgR  = EllesmereUI.DD_BG_R  or 0.075
    local mBgG  = EllesmereUI.DD_BG_G  or 0.113
    local mBgB  = EllesmereUI.DD_BG_B  or 0.141
    local mBgA  = EllesmereUI.DD_BG_HA or 0.98
    local mBrdA = EllesmereUI.DD_BRD_A or 0.20
    local hlA   = EllesmereUI.DD_ITEM_HL_A or 0.08
    local tDimR = EllesmereUI.DD_ITEM_R or 0.75
    local tDimG = EllesmereUI.DD_ITEM_G or 0.75
    local tDimB = EllesmereUI.DD_ITEM_B or 0.75
    local tDimA = EllesmereUI.DD_ITEM_A or 0.9
    local menuW = 240
    local ITEM_H = 26
    local MAX_H = 350

    -- Use the same data source as CD/utility: GetCDMSpellsForBar
    local allSpells = ns.GetCDMSpellsForBar and ns.GetCDMSpellsForBar(targetBarKey, true) or {}

    -- Every buff spell is shown and every row is clickable. Clicking a spell routes
    -- AddTrackedSpell, whose family sweep removes the spell from every other
    -- buff-family bar (including the ghost hidden bar) before claiming it for the
    -- target. Same model as CD/utility bars: one click, one move.
    local knownSpells = {}
    for _, sp in ipairs(allSpells) do
        if sp.cdmCatGroup == "buff" then
            knownSpells[#knownSpells + 1] = sp
        end
    end

    -- No early-out on an empty Blizzard buff list: preset buffs (and, later,
    -- a custom spell ID) are always available below.

    -- Build menu
    local menu = CreateFrame("Frame", nil, UIParent)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(300)
    menu:SetClampedToScreen(true)
    menu:SetSize(menuW, 10)

    local bgTex = menu:CreateTexture(nil, "BACKGROUND")
    bgTex:SetAllPoints(); bgTex:SetColorTexture(mBgR, mBgG, mBgB, mBgA)
    EllesmereUI.MakeBorder(menu, 1, 1, 1, mBrdA, EllesmereUI.PP)

    local inner = CreateFrame("Frame", nil, menu)
    inner:SetWidth(menuW)
    inner:SetPoint("TOPLEFT")

    local mH = 4

    -- Helper: create a spell row
    local function MakeSpellRow(sp)
        local item = CreateFrame("Button", nil, inner)
        item:SetHeight(ITEM_H)
        item:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
        item:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
        item:SetFrameLevel(menu:GetFrameLevel() + 2)

        local iconTex = item:CreateTexture(nil, "ARTWORK")
        iconTex:SetSize(ITEM_H - 4, ITEM_H - 4)
        iconTex:SetPoint("LEFT", 4, 0)
        iconTex:SetTexture(sp.icon)
        iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local lbl = item:CreateFontString(nil, "OVERLAY")
        lbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
        lbl:SetPoint("LEFT", iconTex, "RIGHT", 6, 0)
        lbl:SetPoint("RIGHT", -4, 0)
        lbl:SetJustifyH("LEFT")
        lbl:SetText(EllesmereUI.L(sp.name or ""))
        lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)

        local hl = item:CreateTexture(nil, "ARTWORK")
        hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0)

        -- Tracked-but-untalented buffs stay fully clickable but render
        -- desaturated with a hint, matching the CD/utility picker, so bars
        -- can be arranged without swapping talents.
        local notLearned = (sp.isKnown == false)
        if notLearned then iconTex:SetDesaturated(true); iconTex:SetAlpha(0.5) end

        item:SetScript("OnEnter", function()
            lbl:SetTextColor(1, 1, 1, 1)
            hl:SetColorTexture(1, 1, 1, hlA)
            if notLearned then EllesmereUI.ShowWidgetTooltip(item, EllesmereUI.L("Not currently talented")) end
        end)
        item:SetScript("OnLeave", function()
            lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
            hl:SetColorTexture(1, 1, 1, 0)
            if notLearned then EllesmereUI.HideWidgetTooltip() end
        end)

        -- Gray the row in place and make it inert. Called after the user
        -- clicks it to add the buff, so the picker can stay open for adding
        -- several buffs in a row.
        item._grayOut = function()
            lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA * 0.4)
            iconTex:SetDesaturated(true); iconTex:SetAlpha(0.4)
            hl:SetColorTexture(1, 1, 1, 0)
            if notLearned then EllesmereUI.HideWidgetTooltip() end
            item:SetScript("OnEnter", nil)
            item:SetScript("OnLeave", nil)
            item:SetScript("OnClick", nil)
        end

        mH = mH + ITEM_H
        return item
    end

    -- Custom Spell ID entry -- add an arbitrary buff by spell ID, tracked
    -- as a real aura (12.1 engine slot; no duration asked). Entries that
    -- carry a stored duration are legacy cast-timer customs and keep that
    -- path untouched. Its own section at the top, matching the CD/utility
    -- picker.
    do
        local csItem = CreateFrame("Button", nil, inner)
        csItem:SetHeight(ITEM_H)
        csItem:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
        csItem:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
        csItem:SetFrameLevel(menu:GetFrameLevel() + 2)
        local csHl = csItem:CreateTexture(nil, "ARTWORK")
        csHl:SetAllPoints(); csHl:SetColorTexture(1, 1, 1, 0); csHl:SetAlpha(0)
        local csLbl = csItem:CreateFontString(nil, "OVERLAY")
        csLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
        csLbl:SetPoint("LEFT", 10, 0); csLbl:SetJustifyH("LEFT")
        csLbl:SetText(EllesmereUI.L("Custom Spell ID"))
        csLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
        csItem:SetScript("OnEnter", function() csLbl:SetTextColor(1, 1, 1, 1); csHl:SetColorTexture(1, 1, 1, hlA); csHl:SetAlpha(1) end)
        csItem:SetScript("OnLeave", function() csLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA); csHl:SetAlpha(0) end)
        csItem:SetScript("OnClick", function()
            menu:Hide()
            ShowCustomSpellIDPopup(targetBarKey, false, function(sid)
                ns.AddTrackedSpell(targetBarKey, sid)
                if ns.RebuildSpellRouteMap then ns.RebuildSpellRouteMap() end
                if ns.UpdateLustListener then ns.UpdateLustListener() end
                if ns.UpdateCustomBuffAuraTracking then ns.UpdateCustomBuffAuraTracking() end
                if ns.QueueReanchor then ns.QueueReanchor() end
                RefreshCDPreview()
            end, true)
        end)
        mH = mH + ITEM_H
    end

    -- NOTE: No "Custom Item ID" entry here. Buff bars track auras only (spell
    -- IDs); items (stored as negative -itemID markers) belong on CD/utility
    -- bars. The cdm_strip_buff_bar_item_ids_v1 migration removes any legacy
    -- item markers that were placed on buff bars before this restriction.

    -- Divider below Custom Spell ID, separating it from the presets/list.
    do
        local csDiv = inner:CreateTexture(nil, "ARTWORK")
        csDiv:SetHeight(1); csDiv:SetColorTexture(1, 1, 1, 0.10)
        csDiv:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
        csDiv:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
        mH = mH + 9
    end

    -- Preset buffs (potions, consumables, Bloodlust, etc.) added as cast-timer
    -- custom buffs via AddPresetToBar; the buff phase injects an own-frame so
    -- they render alongside Blizzard-tracked buffs. The row count also gates
    -- the two dividers below, so an empty preset list (WoW Forever) never
    -- leaves two dividers back to back.
    local nPresetRows = 0
    do
        local _, _pClass = UnitClass("player")
        for _, preset in ipairs(ns.BUFF_BAR_PRESETS or {}) do
            if (not preset.class or preset.class == _pClass)
               and (not preset.tbbOnly or preset.customAuraToo) then
                local isAdded = ns.IsPresetOnBar(targetBarKey, preset)
                local si = CreateFrame("Button", nil, inner)
                si:SetHeight(ITEM_H)
                si:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
                si:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
                si:SetFrameLevel(menu:GetFrameLevel() + 2)
                local sIco = si:CreateTexture(nil, "ARTWORK")
                sIco:SetSize(ITEM_H - 4, ITEM_H - 4)
                sIco:SetPoint("LEFT", 4, 0)
                sIco:SetTexture(EllesmereUI.ClientIcon(preset.icon)); sIco:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                local sLbl = si:CreateFontString(nil, "OVERLAY")
                sLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                sLbl:SetPoint("LEFT", sIco, "RIGHT", 6, 0); sLbl:SetPoint("RIGHT", -4, 0)
                sLbl:SetJustifyH("LEFT"); sLbl:SetWordWrap(false); sLbl:SetMaxLines(1)
                sLbl:SetText(EllesmereUI.L(preset.name or ""))
                local sHl = si:CreateTexture(nil, "ARTWORK")
                sHl:SetAllPoints(); sHl:SetColorTexture(1, 1, 1, 0)
                if isAdded then
                    sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA * 0.4)
                    sIco:SetDesaturated(true); sIco:SetAlpha(0.4)
                else
                    sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                    si:SetScript("OnEnter", function() sLbl:SetTextColor(1, 1, 1, 1); sHl:SetColorTexture(1, 1, 1, hlA) end)
                    si:SetScript("OnLeave", function() sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA); sHl:SetColorTexture(1, 1, 1, 0) end)
                    si:SetScript("OnClick", function()
                        EnsureAssignedSpells(targetBarKey)
                        ns.AddPresetToBar(targetBarKey, preset)
                        if ns.RebuildSpellRouteMap then ns.RebuildSpellRouteMap() end
                        if ns.UpdateLustListener then ns.UpdateLustListener() end
                        if ns.QueueReanchor then ns.QueueReanchor() end
                        RefreshCDPreview()
                        -- Keep the picker open so several buffs can be added
                        -- in a row; gray this preset in place once added.
                        sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA * 0.4)
                        sIco:SetDesaturated(true); sIco:SetAlpha(0.4)
                        sHl:SetColorTexture(1, 1, 1, 0)
                        si:SetScript("OnEnter", nil)
                        si:SetScript("OnLeave", nil)
                        si:SetScript("OnClick", nil)
                    end)
                end
                mH = mH + ITEM_H
                nPresetRows = nPresetRows + 1
            end
        end

        -- Divider between presets and the Blizzard-tracked buff list (none when
        -- no preset row was built: the Custom Spell ID divider already sits there).
        if #knownSpells > 0 and nPresetRows > 0 then
            local pDiv = inner:CreateTexture(nil, "ARTWORK")
            pDiv:SetHeight(1); pDiv:SetColorTexture(1, 1, 1, 0.10)
            pDiv:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
            pDiv:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
            mH = mH + 9
        end
    end

    do
        -- Pre-gray rows whose SLOT (cooldownID) is already tracked here: a
        -- collided pair renders two identical rows, and only the cd-level
        -- claim tells them apart.
        local sdRows = ns.GetBarSpellData(targetBarKey)
        local cdTracked = sdRows and ns.CollectCdClaimSet(sdRows)
        for _, sp in ipairs(knownSpells) do
            local item = MakeSpellRow(sp)
            if cdTracked and sp.cdID and cdTracked[sp.cdID] then
                if item._grayOut then item._grayOut() end
            else
                item:SetScript("OnClick", function()
                    -- cdID rides along so collided buffs can be claimed per
                    -- viewer slot rather than per (shared) spellID.
                    if onChanged then onChanged(sp.spellID, sp.cdID) end
                    -- Keep the picker open so several buffs can be added in a
                    -- row; gray this row in place to reflect that it was added.
                    if item._grayOut then item._grayOut() end
                end)
            end
        end
    end

    -- "Missing Spells?" footer: centered, accent-colored prompt that opens
    -- Blizzard's CDM and closes EUI options, matching the CD/utility picker.
    -- Its divider is skipped when no row sits above it: the Custom Spell ID
    -- divider already separates the footer then.
    do
        if nPresetRows > 0 or #knownSpells > 0 then
            local fDiv = inner:CreateTexture(nil, "ARTWORK")
            fDiv:SetHeight(1); fDiv:SetColorTexture(1, 1, 1, 0.10)
            fDiv:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
            fDiv:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
            mH = mH + 9
        end

        local FOOTER_H = 38
        local mbItem = CreateFrame("Button", nil, inner)
        mbItem:SetHeight(FOOTER_H)
        mbItem:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
        mbItem:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
        mbItem:SetFrameLevel(menu:GetFrameLevel() + 2)

        local mbFS = mbItem:CreateFontString(nil, "OVERLAY")
        mbFS:SetFont(FONT_PATH, 11, GetCDMOptOutline())
        mbFS:SetAllPoints()
        mbFS:SetJustifyH("CENTER")
        mbFS:SetJustifyV("MIDDLE")
        local ar, ag, ab = EllesmereUI.GetAccentColor()
        mbFS:SetTextColor(ar, ag, ab, 1)
        mbFS:SetText(EllesmereUI.L("Missing Spells?") .. "\n" .. EllesmereUI.L("Add in Blizzard CDM"))

        mbItem:SetScript("OnEnter", function() mbFS:SetTextColor(1, 1, 1, 1) end)
        mbItem:SetScript("OnLeave", function()
            local r, g, b = EllesmereUI.GetAccentColor()
            mbFS:SetTextColor(r, g, b, 1)
        end)
        mbItem:SetScript("OnClick", function()
            menu:Hide()
            if ns.OpenBlizzardCDMTab then ns.OpenBlizzardCDMTab(true) end
        end)
        mH = mH + FOOTER_H
    end

    inner:SetHeight(mH + 4)
    local totalH = math.min(mH + 4, MAX_H)
    menu:SetSize(menuW, totalH)

    -- Scroll if needed
    if mH + 4 > MAX_H then
        local sf = CreateFrame("ScrollFrame", nil, menu)
        sf:SetPoint("TOPLEFT"); sf:SetPoint("BOTTOMRIGHT")
        sf:SetFrameLevel(menu:GetFrameLevel() + 1)
        sf:EnableMouseWheel(true)
        sf:SetScrollChild(inner)
        inner:SetWidth(menuW)
        EllesmereUI.AttachSmoothScrollbar(sf, { step = 40, thumb = false })
    end

    menu:ClearAllPoints()
    menu:SetPoint("TOP", anchorFrame, "BOTTOM", 0, -4)
    menu._anchorFrame = anchorFrame
    optState._spellPickerMenu = menu

    menu:SetScript("OnUpdate", function(m)
        if not m:IsMouseOver() and not anchorFrame:IsMouseOver() and IsMouseButtonDown("LeftButton") then
            m:Hide()
        end
    end)
    menu:SetScript("OnHide", function(m)
        m:SetScript("OnUpdate", nil)
    end)
    menu:Show()
end

-- Buff picker targeting a CD/UTILITY bar. A buff placed here is a custom injected
-- spell (always-shown icon) with an aura-driven Active State; ns.AddBuffToCDUtilBar
-- wires the injection and the gold aura overlay together. Lists the class's
-- CDM-trackable buffs plus a Custom Spell ID entry; no durations, item or preset rows.
-- onPicked(spellID, collidedCdID) = selection mode ("Replace with Buff"): every
-- catalog buff is listed, a "None" row clears, one click picks and closes, nothing is
-- hosted and there is no Custom Spell ID row (a replacement needs a Blizzard viewer
-- frame). Absent = the hosting picker below.
local function ShowBuffToCDPicker(anchorFrame, targetBarKey, onChanged, onPicked)
    local env = ns._CDMO_OptEnv
    local FONT_PATH, GetCDMOptOutline, optState = env.FONT_PATH, env.GetCDMOptOutline, env.optState
    if optState._spellPickerMenu and optState._spellPickerMenu:IsShown() then
        optState._spellPickerMenu:Hide()
        if optState._spellPickerMenu._anchorFrame == anchorFrame then return end
    end

    local mBgR  = EllesmereUI.DD_BG_R  or 0.075
    local mBgG  = EllesmereUI.DD_BG_G  or 0.113
    local mBgB  = EllesmereUI.DD_BG_B  or 0.141
    local mBgA  = EllesmereUI.DD_BG_HA or 0.98
    local mBrdA = EllesmereUI.DD_BRD_A or 0.20
    local hlA   = EllesmereUI.DD_ITEM_HL_A or 0.08
    local tDimR = EllesmereUI.DD_ITEM_R or 0.75
    local tDimG = EllesmereUI.DD_ITEM_G or 0.75
    local tDimB = EllesmereUI.DD_ITEM_B or 0.75
    local tDimA = EllesmereUI.DD_ITEM_A or 0.9
    local menuW = 240
    local ITEM_H = 26
    local MAX_H = 350

    -- Buff catalog comes from the default buffs bar (passing a CD/util barKey
    -- would return Essential/Utility spells). Dedup against buffs already
    -- HOSTED on this bar so re-opening the menu never re-lists an added
    -- buff. The hosted flag table is the membership truth (assignedSpells
    -- stores hosted buffs as negative markers, and a PLAIN id entry is the
    -- spell's COOLDOWN form -- which must not hide its buff form here).
    local allSpells = ns.GetCDMSpellsForBar and ns.GetCDMSpellsForBar("buffs", true) or {}
    local already = {}
    local sdCur = ns.GetBarSpellData(targetBarKey)
    if sdCur and sdCur.hostedBuffSpellIDs then
        for sid in pairs(sdCur.hostedBuffSpellIDs) do already[sid] = true end
    end
    -- Collided-buff slots (Diabolist Demonic Art vs Diabolic Ritual) are hosted by
    -- cooldownID, not by the shared spellID in `already` -- filter those out
    -- per-slot so only the specific claimed slot disappears, not both.
    local alreadyCd = sdCur and ns.CollectCdClaimSet(sdCur)
    -- Both modes skip buffs already HOSTED on this bar: a hosted buff owns a
    -- slot of its own, and doubling it as a replacement would leave that
    -- slot empty while the aura is active (Pass 3b and 3c would both route it).
    local knownSpells = {}
    for _, sp in ipairs(allSpells) do
        if sp.cdmCatGroup == "buff" and sp.spellID and not already[sp.spellID]
           and not (sp.cdID and alreadyCd and alreadyCd[sp.cdID]) then
            knownSpells[#knownSpells + 1] = sp
        end
    end

    local menu = CreateFrame("Frame", nil, UIParent)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(300)
    menu:SetClampedToScreen(true)
    menu:SetSize(menuW, 10)

    local bgTex = menu:CreateTexture(nil, "BACKGROUND")
    bgTex:SetAllPoints(); bgTex:SetColorTexture(mBgR, mBgG, mBgB, mBgA)
    EllesmereUI.MakeBorder(menu, 1, 1, 1, mBrdA, EllesmereUI.PP)

    local inner = CreateFrame("Frame", nil, menu)
    inner:SetWidth(menuW)
    inner:SetPoint("TOPLEFT")

    local mH = 4

    -- Post-add refresh (picker stays open so several buffs add in a row): onChanged
    -- reanchors live bars and refreshes the preview in place. No RefreshCDPreview here --
    -- its full page rebuild orphans this still-open picker's anchor, so the next click falls onto the rebuilt preview slots and pops the per-icon settings dropdown uninvited.
    local function AfterAdd()
        if ns.RebuildSpellRouteMap then ns.RebuildSpellRouteMap() end
        if ns.QueueReanchor then ns.QueueReanchor() end
        if onChanged then onChanged() end
    end

    -- Custom Spell ID (no duration -- aura-driven). Selection mode gets a
    -- "None" row in this seat instead.
    do
        local csItem = CreateFrame("Button", nil, inner)
        csItem:SetHeight(ITEM_H)
        csItem:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
        csItem:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
        csItem:SetFrameLevel(menu:GetFrameLevel() + 2)
        local csHl = csItem:CreateTexture(nil, "ARTWORK")
        csHl:SetAllPoints(); csHl:SetColorTexture(1, 1, 1, 0); csHl:SetAlpha(0)
        local csLbl = csItem:CreateFontString(nil, "OVERLAY")
        csLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
        csLbl:SetPoint("LEFT", 10, 0); csLbl:SetJustifyH("LEFT")
        csLbl:SetText(onPicked and EllesmereUI.L("None (use cooldown icon)") or EllesmereUI.L("Custom Spell ID"))
        csLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
        csItem:SetScript("OnEnter", function() csLbl:SetTextColor(1, 1, 1, 1); csHl:SetColorTexture(1, 1, 1, hlA); csHl:SetAlpha(1) end)
        csItem:SetScript("OnLeave", function() csLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA); csHl:SetAlpha(0) end)
        csItem:SetScript("OnClick", function()
            menu:Hide()
            if onPicked then
                onPicked(nil, nil)
                return
            end
            ShowCustomSpellIDPopup(targetBarKey, false, function(sid)
                ns.AddBuffToCDUtilBar(targetBarKey, sid)
                AfterAdd()
            end, true)
        end)
        mH = mH + ITEM_H
    end

    -- Divider below Custom Spell ID.
    do
        local csDiv = inner:CreateTexture(nil, "ARTWORK")
        csDiv:SetHeight(1); csDiv:SetColorTexture(1, 1, 1, 0.10)
        csDiv:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
        csDiv:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
        mH = mH + 9
    end

    -- Class buff rows.
    local function MakeSpellRow(sp)
        local item = CreateFrame("Button", nil, inner)
        item:SetHeight(ITEM_H)
        item:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
        item:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
        item:SetFrameLevel(menu:GetFrameLevel() + 2)
        local iconTex = item:CreateTexture(nil, "ARTWORK")
        iconTex:SetSize(ITEM_H - 4, ITEM_H - 4)
        iconTex:SetPoint("LEFT", 4, 0)
        iconTex:SetTexture(sp.icon); iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local lbl = item:CreateFontString(nil, "OVERLAY")
        lbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
        lbl:SetPoint("LEFT", iconTex, "RIGHT", 6, 0); lbl:SetPoint("RIGHT", -4, 0)
        lbl:SetJustifyH("LEFT"); lbl:SetWordWrap(false); lbl:SetMaxLines(1)
        lbl:SetText(EllesmereUI.L(sp.name or ""))
        lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
        local hl = item:CreateTexture(nil, "ARTWORK")
        hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0)
        -- Tracked-but-untalented buffs: desaturate + hint, still clickable (AddBuffToCDUtilBar has no learned gate; routes when talented).
        local notLearned = (sp.isKnown == false)
        if notLearned then iconTex:SetDesaturated(true); iconTex:SetAlpha(0.5) end
        item:SetScript("OnEnter", function()
            lbl:SetTextColor(1, 1, 1, 1); hl:SetColorTexture(1, 1, 1, hlA)
            if notLearned then EllesmereUI.ShowWidgetTooltip(item, EllesmereUI.L("Not currently talented")) end
        end)
        item:SetScript("OnLeave", function()
            lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA); hl:SetColorTexture(1, 1, 1, 0)
            if notLearned then EllesmereUI.HideWidgetTooltip() end
        end)
        item:SetScript("OnClick", function()
            if notLearned then EllesmereUI.HideWidgetTooltip() end
            if onPicked then
                -- Selection mode: hand back the identity the runtime routes by
                -- (cooldownID for a collided pair or tracked trinket row, else the spellID) and close.
                local cdPick = ns.ClaimBuffByCdID(sp.spellID, sp.cdID) and sp.cdID or nil
                menu:Hide()
                onPicked(sp.spellID, cdPick)
                return
            end
            -- Collided pair (two viewer slots, one shared spellID) or tracked trinket row: claim
            -- by cooldownID so each slot is hostable on its own; other buffs keep the sid path (identity survives talent swaps, cooldownIDs drift).
            if ns.ClaimBuffByCdID(sp.spellID, sp.cdID) then
                ns.AddHostedBuffByCdID(targetBarKey, sp.cdID, sp.spellID)
            else
                ns.AddBuffToCDUtilBar(targetBarKey, sp.spellID)
            end
            AfterAdd()
            -- Gray this row in place; keep the picker open.
            lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA * 0.4)
            iconTex:SetDesaturated(true); iconTex:SetAlpha(0.4)
            hl:SetColorTexture(1, 1, 1, 0)
            item:SetScript("OnEnter", nil); item:SetScript("OnLeave", nil); item:SetScript("OnClick", nil)
        end)
        mH = mH + ITEM_H
        return item
    end
    for _, sp in ipairs(knownSpells) do MakeSpellRow(sp) end

    -- "Missing Buffs?" footer -- opens Blizzard's CDM to Display more buffs.
    do
        local fDiv = inner:CreateTexture(nil, "ARTWORK")
        fDiv:SetHeight(1); fDiv:SetColorTexture(1, 1, 1, 0.10)
        fDiv:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
        fDiv:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
        mH = mH + 9

        local FOOTER_H = 38
        local mbItem = CreateFrame("Button", nil, inner)
        mbItem:SetHeight(FOOTER_H)
        mbItem:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
        mbItem:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
        mbItem:SetFrameLevel(menu:GetFrameLevel() + 2)
        local mbFS = mbItem:CreateFontString(nil, "OVERLAY")
        mbFS:SetFont(FONT_PATH, 11, GetCDMOptOutline())
        mbFS:SetAllPoints(); mbFS:SetJustifyH("CENTER"); mbFS:SetJustifyV("MIDDLE")
        local ar, ag, ab = EllesmereUI.GetAccentColor()
        mbFS:SetTextColor(ar, ag, ab, 1)
        mbFS:SetText(EllesmereUI.L("Missing Buffs?") .. "\n" .. EllesmereUI.L("Add in Blizzard CDM"))
        mbItem:SetScript("OnEnter", function() mbFS:SetTextColor(1, 1, 1, 1) end)
        mbItem:SetScript("OnLeave", function()
            local r, g, b = EllesmereUI.GetAccentColor(); mbFS:SetTextColor(r, g, b, 1)
        end)
        mbItem:SetScript("OnClick", function()
            menu:Hide()
            if ns.OpenBlizzardCDMTab then ns.OpenBlizzardCDMTab(true) end
        end)
        mH = mH + FOOTER_H
    end

    inner:SetHeight(mH + 4)
    local totalH = math.min(mH + 4, MAX_H)
    menu:SetSize(menuW, totalH)

    if mH + 4 > MAX_H then
        local sf = CreateFrame("ScrollFrame", nil, menu)
        sf:SetPoint("TOPLEFT"); sf:SetPoint("BOTTOMRIGHT")
        sf:SetFrameLevel(menu:GetFrameLevel() + 1)
        sf:EnableMouseWheel(true)
        sf:SetScrollChild(inner)
        inner:SetWidth(menuW)
        EllesmereUI.AttachSmoothScrollbar(sf, { step = 40, thumb = false })
    end

    menu:ClearAllPoints()
    menu:SetPoint("TOP", anchorFrame, "BOTTOM", 0, -4)
    menu._anchorFrame = anchorFrame
    optState._spellPickerMenu = menu

    menu:SetScript("OnUpdate", function(m)
        if not m:IsMouseOver() and not anchorFrame:IsMouseOver() and IsMouseButtonDown("LeftButton") then
            m:Hide()
        end
    end)
    menu:SetScript("OnHide", function(m)
        m:SetScript("OnUpdate", nil)
    end)
    menu:Show()
end

-- Simple numeric "timer" popup for custom Active State on preset icons.
-- onConfirm(seconds) fires only when a positive number is entered.
local function ShowDurationPopup(currentVal, onConfirm)
    local env = ns._CDMO_OptEnv
    local FONT_PATH, GetCDMOptOutline = env.FONT_PATH, env.GetCDMOptOutline
    local popupName = "EUI_CDM_DurationPopup"
    local popup = _G[popupName]
    if not popup then
        local dimmer = CreateFrame("Frame", popupName .. "Dimmer", UIParent)
        dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
        dimmer:SetAllPoints(UIParent)
        dimmer:EnableMouse(true)
        dimmer:Hide()
        local dimTex = dimmer:CreateTexture(nil, "BACKGROUND")
        dimTex:SetAllPoints(); dimTex:SetColorTexture(0, 0, 0, 0.25)
        dimmer:SetScript("OnMouseDown", function(self) self:Hide() end)

        popup = CreateFrame("Frame", popupName, dimmer)
        popup:SetSize(300, 150)
        popup:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
        popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)
        popup:EnableMouse(true)
        local popBg = popup:CreateTexture(nil, "BACKGROUND")
        popBg:SetAllPoints(); popBg:SetColorTexture(0.077, 0.068, 0.058, 1)
        EllesmereUI.MakeBorder(popup, 1, 1, 1, 0.15, EllesmereUI.PP)
        popup._dimmer = dimmer

        local title = popup:CreateFontString(nil, "OVERLAY")
        title:SetFont(FONT_PATH, 14, GetCDMOptOutline())
        title:SetPoint("TOP", popup, "TOP", 0, -18)
        title:SetTextColor(1, 1, 1, 1)
        title:SetText(EllesmereUI.L("Active State Duration"))

        local hint = popup:CreateFontString(nil, "OVERLAY")
        hint:SetFont(FONT_PATH, 11, GetCDMOptOutline())
        hint:SetPoint("TOP", title, "BOTTOM", 0, -6)
        hint:SetTextColor(0.7, 0.7, 0.7, 0.85)
        hint:SetText(EllesmereUI.L("Seconds the active state shows after use"))

        local durBox = CreateFrame("EditBox", nil, popup)
        durBox:SetSize(180, 28)
        durBox:SetPoint("TOP", hint, "BOTTOM", 0, -12)
        durBox:SetAutoFocus(true)
        durBox:SetNumeric(true)
        durBox:SetMaxLetters(5)
        durBox:SetFont(FONT_PATH, 13, GetCDMOptOutline())
        durBox:SetTextColor(1, 1, 1, 0.9)
        durBox:SetJustifyH("CENTER")
        local durBg = durBox:CreateTexture(nil, "BACKGROUND")
        durBg:SetAllPoints(); durBg:SetColorTexture(0.060, 0.049, 0.037, 1)
        EllesmereUI.MakeBorder(durBox, 1, 1, 1, 0.12, EllesmereUI.PP)
        popup._durBox = durBox

        local ar, ag, ab = EllesmereUI.GetAccentColor()
        local okBtn = CreateFrame("Button", nil, popup)
        okBtn:SetSize(80, 28)
        okBtn:SetPoint("BOTTOMRIGHT", popup, "BOTTOM", -4, 16)
        local okBg = okBtn:CreateTexture(nil, "BACKGROUND")
        okBg:SetAllPoints(); okBg:SetColorTexture(ar, ag, ab, 0.15)
        EllesmereUI.MakeBorder(okBtn, ar, ag, ab, 0.3, EllesmereUI.PP)
        local okLbl = okBtn:CreateFontString(nil, "OVERLAY")
        okLbl:SetFont(FONT_PATH, 12, GetCDMOptOutline())
        okLbl:SetPoint("CENTER"); okLbl:SetText(EllesmereUI.L("Save"))
        okLbl:SetTextColor(ar, ag, ab, 0.9)
        okBtn:SetScript("OnEnter", function() okLbl:SetTextColor(1, 1, 1, 1) end)
        okBtn:SetScript("OnLeave", function() okLbl:SetTextColor(ar, ag, ab, 0.9) end)

        local cancelBtn = CreateFrame("Button", nil, popup)
        cancelBtn:SetSize(80, 28)
        cancelBtn:SetPoint("BOTTOMLEFT", popup, "BOTTOM", 4, 16)
        local cBg = cancelBtn:CreateTexture(nil, "BACKGROUND")
        cBg:SetAllPoints(); cBg:SetColorTexture(0.12, 0.12, 0.12, 0.5)
        EllesmereUI.MakeBorder(cancelBtn, 1, 1, 1, 0.10, EllesmereUI.PP)
        local cLbl = cancelBtn:CreateFontString(nil, "OVERLAY")
        cLbl:SetFont(FONT_PATH, 12, GetCDMOptOutline())
        cLbl:SetPoint("CENTER"); cLbl:SetText(EllesmereUI.L("Cancel"))
        cLbl:SetTextColor(0.7, 0.7, 0.7, 0.8)
        cancelBtn:SetScript("OnEnter", function() cLbl:SetTextColor(1, 1, 1, 1) end)
        cancelBtn:SetScript("OnLeave", function() cLbl:SetTextColor(0.7, 0.7, 0.7, 0.8) end)
        cancelBtn:SetScript("OnClick", function() dimmer:Hide() end)
        popup._cancelBtn = cancelBtn

        local function Commit()
            local v = tonumber(durBox:GetText())
            if v and v > 0 then
                dimmer:Hide()
                if popup._onConfirm then popup._onConfirm(v) end
            end
        end
        okBtn:SetScript("OnClick", Commit)
        durBox:SetScript("OnEnterPressed", Commit)
        durBox:SetScript("OnEscapePressed", function() dimmer:Hide() end)
    end
    popup._onConfirm = onConfirm
    popup._durBox:SetText(currentVal and tostring(currentVal) or "")
    ns.PadPopupOpen(popup._dimmer, popup, popup._cancelBtn)  -- controller cursor
    popup._dimmer:Show()
    popup._durBox:SetFocus()
    popup._durBox:HighlightText()
end

-- Numeric popup for an opacity percent (1-100). Titled for the "Lower Alpha
-- (On CD)" cooldown-state effect unless the caller passes its own title and
-- hint (already localized), e.g. the Blackout glow opacity. Both texts are
-- set on every show. Mirrors ShowDurationPopup's look; onConfirm receives
-- the integer percent.
local function ShowAlphaPopup(currentPct, onConfirm, title, hint)
    local env = ns._CDMO_OptEnv
    local FONT_PATH, GetCDMOptOutline = env.FONT_PATH, env.GetCDMOptOutline
    local popupName = "EUI_CDM_AlphaPopup"
    local popup = _G[popupName]
    if not popup then
        local dimmer = CreateFrame("Frame", popupName .. "Dimmer", UIParent)
        dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
        dimmer:SetAllPoints(UIParent)
        dimmer:EnableMouse(true)
        dimmer:Hide()
        local dimTex = dimmer:CreateTexture(nil, "BACKGROUND")
        dimTex:SetAllPoints(); dimTex:SetColorTexture(0, 0, 0, 0.25)
        dimmer:SetScript("OnMouseDown", function(self) self:Hide() end)

        popup = CreateFrame("Frame", popupName, dimmer)
        popup:SetSize(300, 150)
        popup:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
        popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)
        popup:EnableMouse(true)
        local popBg = popup:CreateTexture(nil, "BACKGROUND")
        popBg:SetAllPoints(); popBg:SetColorTexture(0.077, 0.068, 0.058, 1)
        EllesmereUI.MakeBorder(popup, 1, 1, 1, 0.15, EllesmereUI.PP)
        popup._dimmer = dimmer

        local titleFS = popup:CreateFontString(nil, "OVERLAY")
        titleFS:SetFont(FONT_PATH, 14, GetCDMOptOutline())
        titleFS:SetPoint("TOP", popup, "TOP", 0, -18)
        titleFS:SetTextColor(1, 1, 1, 1)
        popup._title = titleFS

        local hintFS = popup:CreateFontString(nil, "OVERLAY")
        hintFS:SetFont(FONT_PATH, 11, GetCDMOptOutline())
        hintFS:SetPoint("TOP", titleFS, "BOTTOM", 0, -6)
        hintFS:SetTextColor(0.7, 0.7, 0.7, 0.85)
        popup._hint = hintFS

        local box = CreateFrame("EditBox", nil, popup)
        box:SetSize(180, 28)
        box:SetPoint("TOP", hintFS, "BOTTOM", 0, -12)
        box:SetAutoFocus(true)
        box:SetNumeric(true)
        box:SetMaxLetters(3)
        box:SetFont(FONT_PATH, 13, GetCDMOptOutline())
        box:SetTextColor(1, 1, 1, 0.9)
        box:SetJustifyH("CENTER")
        local boxBg = box:CreateTexture(nil, "BACKGROUND")
        boxBg:SetAllPoints(); boxBg:SetColorTexture(0.060, 0.049, 0.037, 1)
        EllesmereUI.MakeBorder(box, 1, 1, 1, 0.12, EllesmereUI.PP)
        popup._box = box

        local ar, ag, ab = EllesmereUI.GetAccentColor()
        local okBtn = CreateFrame("Button", nil, popup)
        okBtn:SetSize(80, 28)
        okBtn:SetPoint("BOTTOMRIGHT", popup, "BOTTOM", -4, 16)
        local okBg = okBtn:CreateTexture(nil, "BACKGROUND")
        okBg:SetAllPoints(); okBg:SetColorTexture(ar, ag, ab, 0.15)
        EllesmereUI.MakeBorder(okBtn, ar, ag, ab, 0.3, EllesmereUI.PP)
        local okLbl = okBtn:CreateFontString(nil, "OVERLAY")
        okLbl:SetFont(FONT_PATH, 12, GetCDMOptOutline())
        okLbl:SetPoint("CENTER"); okLbl:SetText(EllesmereUI.L("Save"))
        okLbl:SetTextColor(ar, ag, ab, 0.9)
        okBtn:SetScript("OnEnter", function() okLbl:SetTextColor(1, 1, 1, 1) end)
        okBtn:SetScript("OnLeave", function() okLbl:SetTextColor(ar, ag, ab, 0.9) end)

        local cancelBtn = CreateFrame("Button", nil, popup)
        cancelBtn:SetSize(80, 28)
        cancelBtn:SetPoint("BOTTOMLEFT", popup, "BOTTOM", 4, 16)
        local cBg = cancelBtn:CreateTexture(nil, "BACKGROUND")
        cBg:SetAllPoints(); cBg:SetColorTexture(0.12, 0.12, 0.12, 0.5)
        EllesmereUI.MakeBorder(cancelBtn, 1, 1, 1, 0.10, EllesmereUI.PP)
        local cLbl = cancelBtn:CreateFontString(nil, "OVERLAY")
        cLbl:SetFont(FONT_PATH, 12, GetCDMOptOutline())
        cLbl:SetPoint("CENTER"); cLbl:SetText(EllesmereUI.L("Cancel"))
        cLbl:SetTextColor(0.7, 0.7, 0.7, 0.8)
        cancelBtn:SetScript("OnEnter", function() cLbl:SetTextColor(1, 1, 1, 1) end)
        cancelBtn:SetScript("OnLeave", function() cLbl:SetTextColor(0.7, 0.7, 0.7, 0.8) end)
        cancelBtn:SetScript("OnClick", function() dimmer:Hide() end)
        popup._cancelBtn = cancelBtn

        local function Commit()
            local v = tonumber(box:GetText())
            if v and v >= 1 and v <= 100 then
                dimmer:Hide()
                if popup._onConfirm then popup._onConfirm(math.floor(v)) end
            end
        end
        okBtn:SetScript("OnClick", Commit)
        box:SetScript("OnEnterPressed", Commit)
        box:SetScript("OnEscapePressed", function() dimmer:Hide() end)
    end
    popup._onConfirm = onConfirm
    popup._title:SetText(title or EllesmereUI.L("Lower Alpha"))
    popup._hint:SetText(hint or EllesmereUI.L("Icon opacity while on cooldown (1-100%)"))
    popup._box:SetText(currentPct and tostring(currentPct) or "")
    ns.PadPopupOpen(popup._dimmer, popup, popup._cancelBtn)  -- controller cursor
    popup._dimmer:Show()
    popup._box:SetFocus()
    popup._box:HighlightText()
end

-- Numeric popup for the per-spell "Threshold Seconds" (Threshold Text): the
-- user enters the seconds-remaining boundary below which Threshold Color /
-- Threshold Decimals apply. 0 disarms the feature for the spell. Mirrors
-- ShowAlphaPopup's look; onConfirm receives the integer seconds (0-59).
local function ShowThresholdSecondsPopup(currentVal, onConfirm)
    local env = ns._CDMO_OptEnv
    local FONT_PATH, GetCDMOptOutline = env.FONT_PATH, env.GetCDMOptOutline
    local popupName = "EUI_CDM_ThresholdSecondsPopup"
    local popup = _G[popupName]
    if not popup then
        local dimmer = CreateFrame("Frame", popupName .. "Dimmer", UIParent)
        dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
        dimmer:SetAllPoints(UIParent)
        dimmer:EnableMouse(true)
        dimmer:Hide()
        local dimTex = dimmer:CreateTexture(nil, "BACKGROUND")
        dimTex:SetAllPoints(); dimTex:SetColorTexture(0, 0, 0, 0.25)
        dimmer:SetScript("OnMouseDown", function(self) self:Hide() end)

        popup = CreateFrame("Frame", popupName, dimmer)
        popup:SetSize(300, 150)
        popup:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
        popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)
        popup:EnableMouse(true)
        local popBg = popup:CreateTexture(nil, "BACKGROUND")
        popBg:SetAllPoints(); popBg:SetColorTexture(0.077, 0.068, 0.058, 1)
        EllesmereUI.MakeBorder(popup, 1, 1, 1, 0.15, EllesmereUI.PP)
        popup._dimmer = dimmer

        local title = popup:CreateFontString(nil, "OVERLAY")
        title:SetFont(FONT_PATH, 14, GetCDMOptOutline())
        title:SetPoint("TOP", popup, "TOP", 0, -18)
        title:SetTextColor(1, 1, 1, 1)
        title:SetText(EllesmereUI.L("Threshold Seconds"))

        local hint = popup:CreateFontString(nil, "OVERLAY")
        hint:SetFont(FONT_PATH, 11, GetCDMOptOutline())
        hint:SetPoint("TOP", title, "BOTTOM", 0, -6)
        hint:SetTextColor(0.7, 0.7, 0.7, 0.85)
        hint:SetText(EllesmereUI.L("Seconds left when threshold text starts (0 = off)"))

        local box = CreateFrame("EditBox", nil, popup)
        box:SetSize(180, 28)
        box:SetPoint("TOP", hint, "BOTTOM", 0, -12)
        box:SetAutoFocus(true)
        box:SetNumeric(true)
        box:SetMaxLetters(2)
        box:SetFont(FONT_PATH, 13, GetCDMOptOutline())
        box:SetTextColor(1, 1, 1, 0.9)
        box:SetJustifyH("CENTER")
        local boxBg = box:CreateTexture(nil, "BACKGROUND")
        boxBg:SetAllPoints(); boxBg:SetColorTexture(0.060, 0.049, 0.037, 1)
        EllesmereUI.MakeBorder(box, 1, 1, 1, 0.12, EllesmereUI.PP)
        popup._box = box

        local ar, ag, ab = EllesmereUI.GetAccentColor()
        local okBtn = CreateFrame("Button", nil, popup)
        okBtn:SetSize(80, 28)
        okBtn:SetPoint("BOTTOMRIGHT", popup, "BOTTOM", -4, 16)
        local okBg = okBtn:CreateTexture(nil, "BACKGROUND")
        okBg:SetAllPoints(); okBg:SetColorTexture(ar, ag, ab, 0.15)
        EllesmereUI.MakeBorder(okBtn, ar, ag, ab, 0.3, EllesmereUI.PP)
        local okLbl = okBtn:CreateFontString(nil, "OVERLAY")
        okLbl:SetFont(FONT_PATH, 12, GetCDMOptOutline())
        okLbl:SetPoint("CENTER"); okLbl:SetText(EllesmereUI.L("Save"))
        okLbl:SetTextColor(ar, ag, ab, 0.9)
        okBtn:SetScript("OnEnter", function() okLbl:SetTextColor(1, 1, 1, 1) end)
        okBtn:SetScript("OnLeave", function() okLbl:SetTextColor(ar, ag, ab, 0.9) end)

        local cancelBtn = CreateFrame("Button", nil, popup)
        cancelBtn:SetSize(80, 28)
        cancelBtn:SetPoint("BOTTOMLEFT", popup, "BOTTOM", 4, 16)
        local cBg = cancelBtn:CreateTexture(nil, "BACKGROUND")
        cBg:SetAllPoints(); cBg:SetColorTexture(0.12, 0.12, 0.12, 0.5)
        EllesmereUI.MakeBorder(cancelBtn, 1, 1, 1, 0.10, EllesmereUI.PP)
        local cLbl = cancelBtn:CreateFontString(nil, "OVERLAY")
        cLbl:SetFont(FONT_PATH, 12, GetCDMOptOutline())
        cLbl:SetPoint("CENTER"); cLbl:SetText(EllesmereUI.L("Cancel"))
        cLbl:SetTextColor(0.7, 0.7, 0.7, 0.8)
        cancelBtn:SetScript("OnEnter", function() cLbl:SetTextColor(1, 1, 1, 1) end)
        cancelBtn:SetScript("OnLeave", function() cLbl:SetTextColor(0.7, 0.7, 0.7, 0.8) end)
        cancelBtn:SetScript("OnClick", function() dimmer:Hide() end)
        popup._cancelBtn = cancelBtn

        local function Commit()
            local v = tonumber(box:GetText())
            if v and v >= 0 and v <= 59 then
                dimmer:Hide()
                if popup._onConfirm then popup._onConfirm(math.floor(v)) end
            end
        end
        okBtn:SetScript("OnClick", Commit)
        box:SetScript("OnEnterPressed", Commit)
        box:SetScript("OnEscapePressed", function() dimmer:Hide() end)
    end
    popup._onConfirm = onConfirm
    popup._box:SetText(currentVal and tostring(currentVal) or "")
    ns.PadPopupOpen(popup._dimmer, popup, popup._cancelBtn)  -- controller cursor
    popup._dimmer:Show()
    popup._box:SetFocus()
    popup._box:HighlightText()
end

-- Per-spell "Custom Icon" popup: a texture fileID that permanently replaces
-- this spell's bar icon, including every form it transforms into; empty/0
-- removes the override. Mirrors ShowThresholdSecondsPopup, plus a live
-- preview of the typed ID (empty/invalid = question-mark fallback, so a
-- typo is visible before saving). onConfirm gets the integer fileID or nil
-- for remove. On ns (not a page-scope local): Lua 5.1 200-local cap.
ns.ShowCDMCustomIconPopup = function(currentID, onConfirm)
    local env = ns._CDMO_OptEnv
    local FONT_PATH, GetCDMOptOutline = env.FONT_PATH, env.GetCDMOptOutline
    local popupName = "EUI_CDM_CustomIconPopup"
    local popup = _G[popupName]
    if not popup then
        local dimmer = CreateFrame("Frame", popupName .. "Dimmer", UIParent)
        dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
        dimmer:SetAllPoints(UIParent)
        dimmer:EnableMouse(true)
        dimmer:Hide()
        local dimTex = dimmer:CreateTexture(nil, "BACKGROUND")
        dimTex:SetAllPoints(); dimTex:SetColorTexture(0, 0, 0, 0.25)
        dimmer:SetScript("OnMouseDown", function(self) self:Hide() end)

        popup = CreateFrame("Frame", popupName, dimmer)
        popup:SetSize(300, 196)
        popup:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
        popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)
        popup:EnableMouse(true)
        local popBg = popup:CreateTexture(nil, "BACKGROUND")
        popBg:SetAllPoints(); popBg:SetColorTexture(0.077, 0.068, 0.058, 1)
        EllesmereUI.MakeBorder(popup, 1, 1, 1, 0.15, EllesmereUI.PP)
        popup._dimmer = dimmer

        local title = popup:CreateFontString(nil, "OVERLAY")
        title:SetFont(FONT_PATH, 14, GetCDMOptOutline())
        title:SetPoint("TOP", popup, "TOP", 0, -18)
        title:SetTextColor(1, 1, 1, 1)
        title:SetText(EllesmereUI.L("Custom Icon"))

        local hint = popup:CreateFontString(nil, "OVERLAY")
        hint:SetFont(FONT_PATH, 11, GetCDMOptOutline())
        hint:SetPoint("TOP", title, "BOTTOM", 0, -6)
        hint:SetTextColor(0.7, 0.7, 0.7, 0.85)
        hint:SetText(EllesmereUI.L("Icon ID always shown for this spell (empty removes)"))

        local box = CreateFrame("EditBox", nil, popup)
        box:SetSize(180, 28)
        box:SetPoint("TOP", hint, "BOTTOM", 0, -12)
        box:SetAutoFocus(true)
        box:SetNumeric(true)
        box:SetMaxLetters(9)
        box:SetFont(FONT_PATH, 13, GetCDMOptOutline())
        box:SetTextColor(1, 1, 1, 0.9)
        box:SetJustifyH("CENTER")
        local boxBg = box:CreateTexture(nil, "BACKGROUND")
        boxBg:SetAllPoints(); boxBg:SetColorTexture(0.060, 0.049, 0.037, 1)
        EllesmereUI.MakeBorder(box, 1, 1, 1, 0.12, EllesmereUI.PP)
        popup._box = box

        -- Live preview of the typed ID (question mark for empty/unknown;
        -- fires via OnTextChanged, including the SetText on reopen below).
        local prev = popup:CreateTexture(nil, "ARTWORK")
        prev:SetSize(30, 30)
        prev:SetPoint("TOP", box, "BOTTOM", 0, -10)
        prev:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        prev:SetTexture(134400)
        popup._prev = prev
        box:SetScript("OnTextChanged", function(b)
            local id = tonumber(b:GetText())
            prev:SetTexture((id and id > 0) and id or 134400)
        end)

        local ar, ag, ab = EllesmereUI.GetAccentColor()
        local okBtn = CreateFrame("Button", nil, popup)
        okBtn:SetSize(80, 28)
        okBtn:SetPoint("BOTTOMRIGHT", popup, "BOTTOM", -4, 16)
        local okBg = okBtn:CreateTexture(nil, "BACKGROUND")
        okBg:SetAllPoints(); okBg:SetColorTexture(ar, ag, ab, 0.15)
        EllesmereUI.MakeBorder(okBtn, ar, ag, ab, 0.3, EllesmereUI.PP)
        local okLbl = okBtn:CreateFontString(nil, "OVERLAY")
        okLbl:SetFont(FONT_PATH, 12, GetCDMOptOutline())
        okLbl:SetPoint("CENTER"); okLbl:SetText(EllesmereUI.L("Save"))
        okLbl:SetTextColor(ar, ag, ab, 0.9)
        okBtn:SetScript("OnEnter", function() okLbl:SetTextColor(1, 1, 1, 1) end)
        okBtn:SetScript("OnLeave", function() okLbl:SetTextColor(ar, ag, ab, 0.9) end)

        local cancelBtn = CreateFrame("Button", nil, popup)
        cancelBtn:SetSize(80, 28)
        cancelBtn:SetPoint("BOTTOMLEFT", popup, "BOTTOM", 4, 16)
        local cBg = cancelBtn:CreateTexture(nil, "BACKGROUND")
        cBg:SetAllPoints(); cBg:SetColorTexture(0.12, 0.12, 0.12, 0.5)
        EllesmereUI.MakeBorder(cancelBtn, 1, 1, 1, 0.10, EllesmereUI.PP)
        local cLbl = cancelBtn:CreateFontString(nil, "OVERLAY")
        cLbl:SetFont(FONT_PATH, 12, GetCDMOptOutline())
        cLbl:SetPoint("CENTER"); cLbl:SetText(EllesmereUI.L("Cancel"))
        cLbl:SetTextColor(0.7, 0.7, 0.7, 0.8)
        cancelBtn:SetScript("OnEnter", function() cLbl:SetTextColor(1, 1, 1, 1) end)
        cancelBtn:SetScript("OnLeave", function() cLbl:SetTextColor(0.7, 0.7, 0.7, 0.8) end)
        cancelBtn:SetScript("OnClick", function() dimmer:Hide() end)
        popup._cancelBtn = cancelBtn

        local function Commit()
            local v = tonumber(box:GetText())
            dimmer:Hide()
            if popup._onConfirm then
                if v and v > 0 then
                    popup._onConfirm(math.floor(v))
                else
                    popup._onConfirm(nil)  -- empty or 0 = remove
                end
            end
        end
        okBtn:SetScript("OnClick", Commit)
        box:SetScript("OnEnterPressed", Commit)
        box:SetScript("OnEscapePressed", function() dimmer:Hide() end)
    end
    popup._onConfirm = onConfirm
    popup._box:SetText(currentID and tostring(currentID) or "")
    ns.PadPopupOpen(popup._dimmer, popup, popup._cancelBtn)  -- controller cursor
    popup._dimmer:Show()
    popup._box:SetFocus()
    popup._box:HighlightText()
end

-- Used by EUI_CooldownManager_Options.lua and SpellPicker_Options.lua
ns.CDMO_EnsureAssignedSpells = EnsureAssignedSpells
ns.CDMO_ShowAlphaPopup = ShowAlphaPopup
ns.CDMO_ShowBuffBarPicker = ShowBuffBarPicker
ns.CDMO_ShowBuffToCDPicker = ShowBuffToCDPicker
ns.CDMO_ShowCustomItemIDPopup = ShowCustomItemIDPopup
ns.CDMO_ShowDurationPopup = ShowDurationPopup
ns.CDMO_ShowEquipmentSlotPopup = ShowEquipmentSlotPopup
ns.CDMO_ShowThresholdSecondsPopup = ShowThresholdSecondsPopup
