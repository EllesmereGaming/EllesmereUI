if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CooldownManager_Options\SpellPicker_Options.lua
--  Cooldown Manager options: the per-bar spell picker (ShowSpellPicker).
--  Definitions only; the shared helpers come from ns._CDMO_OptEnv (filled by
--  EUI_CooldownManager_Options.lua), the other pickers from Pickers_Options.lua.
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUICooldownManager"]
if not ns then return end  -- module disabled: no options page

local function ShowWrongBarTypePopup(spellName, isSpellBuff)
    if not EllesmereUI or not EllesmereUI.ShowConfirmPopup then return end
    local correctBar = isSpellBuff and "a Buff bar" or "a Cooldown or Utility bar"
    EllesmereUI:ShowConfirmPopup({
        title = "Wrong Bar Type",
        message = (spellName or "This spell") .. " is tracked by Blizzard as " .. (isSpellBuff and "a buff/aura" or "a cooldown") .. " and should be added to " .. correctBar .. ".",
        confirmText = "Open Blizzard CDM",
        cancelText = "Close",
        onConfirm = function()
            if CooldownViewerSettings and CooldownViewerSettings.Show then
                CooldownViewerSettings:Show()
            end
            if EllesmereUI._mainFrame then EllesmereUI._mainFrame:Hide() end
        end,
    })
end

local function ShowSpellPicker(anchorFrame, barKey, slotIndex, excludeSet, onSelect, removeOnly)
    local env = ns._CDMO_OptEnv
    local FONT_PATH, FitMenuWidth, GetCDMOptOutline, RefreshCDPreview = env.FONT_PATH, env.FitMenuWidth, env.GetCDMOptOutline, env.RefreshCDPreview
    local SelectedCDMBar, durationPositionOrder, durationPositionValues, optState = env.SelectedCDMBar, env.durationPositionOrder, env.durationPositionValues, env.optState
    local EnsureAssignedSpells, ShowAlphaPopup, ShowBuffToCDPicker, ShowCustomItemIDPopup = ns.CDMO_EnsureAssignedSpells, ns.CDMO_ShowAlphaPopup, ns.CDMO_ShowBuffToCDPicker, ns.CDMO_ShowCustomItemIDPopup
    local ShowDurationPopup, ShowEquipmentSlotPopup, ShowThresholdSecondsPopup = ns.CDMO_ShowDurationPopup, ns.CDMO_ShowEquipmentSlotPopup, ns.CDMO_ShowThresholdSecondsPopup
    -- Toggle: if the picker is already open for this same icon, close it
    if optState._spellPickerMenu and optState._spellPickerMenu:IsShown() and optState._spellPickerMenu._anchorFrame == anchorFrame then
        optState._spellPickerMenu:Hide()
        return
    end
    -- Close existing
    if optState._spellPickerMenu then optState._spellPickerMenu:Hide() end

    local bd = SelectedCDMBar()
    local isCustomBuff = bd and bd.barType == "custom_buff"
    local isBuffBar = bd and ns.IsBarBuffFamily(bd)

    -- Per-icon buff settings key = the slot's DISPLAYED spell (canonical /
    -- GetSpellID-derived _previewSpellID), NOT the cooldownInfo base: some buffs'
    -- base is an unrelated GENERIC spec spell shared by several icons (e.g.
    -- Consecration -> Protection Paladin 137028), which both collides (settings leak
    -- onto a "random" icon) and never matches the real buff. The displayed id is
    -- buff-specific and the render resolves the same id canon-first
    -- (RefreshCDMIconAppearance), so writer/reader agree. Custom/injected buffs' own positive id as _previewSpellID works too.
    local function ResolveBuffSettingsKey(af)
        local sid = af and af._previewSpellID
        if not sid then return nil end
        -- Same-spellID collision (Diabolist Demonic Art vs Diabolic Ritual): when two
        -- viewer slots share this displayed id, key THIS slot by its own cooldownID so each is configured independently; non-collided buffs keep the stable spellID key (survives talent swaps).
        local cdID = af and (af._previewCdID or af.cooldownID)
        if type(cdID) == "number" then
            local ckey = "c" .. cdID
            -- Read-your-writes: once a per-cooldownID entry exists, keep editing it even
            -- if the collision later ends (re-talent), so the menu never splits from what the runtime resolver reads (which prefers an existing c-entry whenever present).
            local bstore = ns.GetSpellSettingsStore and ns.GetSpellSettingsStore("buffs")
            if bstore and bstore[ckey] then return ckey end
            if ns.IsCollidedBuffSid and ns.IsCollidedBuffSid(sid) then return ckey end
            -- A slot this bar claims by cooldownID (tracked trinket row) keys the
            -- same way whether or not its spell resolves, as on CD/utility bars.
            local claims = ns.CollectCdClaimSet(ns.GetBarSpellData(barKey))
            if claims and claims[cdID] then return ckey end
        end
        return sid
    end

    -- No early return on an empty Blizzard list: the picker also hosts the Custom
    -- Spell ID / Custom Item ID / Equipment Slot entries and the trinket / racial /
    -- potion presets, which are the only way onto the bar while the viewer has no
    -- data for it (before COOLDOWN_VIEWER_DATA_LOADED, or every entry set to Not
    -- Displayed). The list sections below already render nothing for an empty set,
    -- and the "Missing Spells?" footer is the right prompt in that state.
    local allSpells = {}
    if not removeOnly and not isCustomBuff then
        allSpells = ns.GetCDMSpellsForBar(barKey) or {}
    end

    -- Standard EllesmereUI dropdown colors
    local mBgR  = EllesmereUI.DD_BG_R  or 0.075
    local mBgG  = EllesmereUI.DD_BG_G  or 0.113
    local mBgB  = EllesmereUI.DD_BG_B  or 0.141
    local mBgA  = EllesmereUI.DD_BG_HA or 0.98
    local mBrdA = EllesmereUI.DD_BRD_A or 0.20
    local hlA   = EllesmereUI.DD_ITEM_HL_A or 0.08
    local tDimR = EllesmereUI.TEXT_DIM_R or 0.7
    local tDimG = EllesmereUI.TEXT_DIM_G or 0.7
    local tDimB = EllesmereUI.TEXT_DIM_B or 0.7
    local tDimA = EllesmereUI.TEXT_DIM_A or 0.85

    local menuW = 210
    local ITEM_H = 26
    local MAX_H = 400  -- full picker scrolls past this; the per-spell menu has no scroll and sizes to its rows

    local menu = CreateFrame("Frame", nil, UIParent)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(300)
    menu:SetClampedToScreen(true)
    menu:SetSize(menuW, 10)
    menu:EnableMouse(true)

    -- Background + border (standard dropdown style)
    local bg = menu:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(mBgR, mBgG, mBgB, mBgA)
    EllesmereUI.MakeBorder(menu, 1, 1, 1, mBrdA, EllesmereUI.PP)

    -- Build item list: tracked first (minus current), divider, rest, disabled at bottom
    local tracked = {}
    local bd = SelectedCDMBar()
    local sd = bd and ns.GetBarSpellData(bd.key)
    if sd and sd.assignedSpells then
        for _, sid in ipairs(sd.assignedSpells) do tracked[sid] = true end
    end

    -- Primary/secondary category order by bar type: cooldown-type bars = Essential(0)
    -- first, Utility(1) second; utility-type bars = reversed.
    local resolvedType = ns.GetBarType and ns.GetBarType(bd or barKey) or barKey
    local isCooldownType = (resolvedType == "cooldowns")
    local isUtilityType  = (resolvedType == "utility")
    local isCDorUtil = isCooldownType or isUtilityType
    local primaryCat   = isCooldownType and 0 or (isUtilityType and 1 or nil)
    local secondaryCat = isCooldownType and 1 or (isUtilityType and 0 or nil)

    local isBuffBar = bd and ns.IsBarBuffFamily(bd)

    -- Buckets for cooldown/utility bars (three-section layout)
    local priUnassigned, priAssigned = {}, {}
    local secUnassigned, secAssigned = {}, {}
    local notTracked = {}
    local itemsExtra = {}
    -- Single bucket for buff/trinket/other bars (picker only enumerates live pool members, so all spells are tracked + learned).
    local itemsDisplayed = {}

    for _, sp in ipairs(allSpells) do
        if sp.isExtra then
            if not isBuffBar then itemsExtra[#itemsExtra + 1] = sp end
        elseif isCDorUtil then
            if sp.cdmCat == primaryCat then
                if sp.onEUIBar then priAssigned[#priAssigned + 1] = sp
                else priUnassigned[#priUnassigned + 1] = sp end
            elseif sp.cdmCat == secondaryCat then
                if sp.onEUIBar then secAssigned[#secAssigned + 1] = sp
                else secUnassigned[#secUnassigned + 1] = sp end
            else
                notTracked[#notTracked + 1] = sp
            end
        else
            itemsDisplayed[#itemsDisplayed + 1] = sp
        end
    end

    -- Inner scroll container
    local inner = CreateFrame("Frame", nil, menu)
    inner:SetWidth(menuW)
    inner:SetPoint("TOPLEFT")

    local mH = 4
    local allItems = {}

    -- "Remove Spell" option at top (right-click on existing icon only). The default
    -- buff bar (key=="buffs") can't remove Blizzard-tracked buffs (Blizzard's CDM owns
    -- visibility), BUT injected custom/preset buffs ARE removable there; extra buff + CD/util bars always allow removal.
    local rmSpellID = nil
    local rmIsInjected = false
    do
        local rmSd = ns.GetBarSpellData(barKey)
        -- Buff bars: prefer the slot's own _previewSpellID (the default buffs bar's slots don't map to assignedSpells -- see the settings block).
        if isBuffBar then
            rmSpellID = ResolveBuffSettingsKey(anchorFrame)
                or (rmSd and rmSd.assignedSpells and rmSd.assignedSpells[slotIndex])
        else
            rmSpellID = rmSd and rmSd.assignedSpells and rmSd.assignedSpells[slotIndex]
            if (not rmSpellID or rmSpellID == 0) and anchorFrame and anchorFrame._previewSpellID then
                rmSpellID = anchorFrame._previewSpellID
            end
        end
        rmIsInjected = (rmSpellID and rmSd and (
            (rmSd.spellDurations and (rmSd.spellDurations[rmSpellID] or 0) > 0)
            or (rmSd.customSpellIDs and rmSd.customSpellIDs[rmSpellID]))) and true or false
    end
    if slotIndex and (barKey ~= "buffs" or rmIsInjected) then
        local rmItem = CreateFrame("Button", nil, inner)
        rmItem:SetHeight(ITEM_H)
        rmItem:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
        rmItem:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
        rmItem:SetFrameLevel(menu:GetFrameLevel() + 2)

        local rmLbl = rmItem:CreateFontString(nil, "OVERLAY")
        rmLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
        rmLbl:SetPoint("LEFT", 10, 0)
        rmLbl:SetJustifyH("LEFT")
        rmLbl:SetText(EllesmereUI.L("Remove Spell"))
        rmLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)

        local rmHl = rmItem:CreateTexture(nil, "ARTWORK")
        rmHl:SetAllPoints(); rmHl:SetColorTexture(1, 1, 1, 0); rmHl:SetAlpha(0)

        rmItem:SetScript("OnEnter", function()
            rmLbl:SetTextColor(1, 1, 1, 1)
            rmHl:SetColorTexture(1, 1, 1, hlA); rmHl:SetAlpha(1)
            if menu._openSub and menu._openSub:IsShown() then menu._openSub:Hide() end
        end)
        rmItem:SetScript("OnLeave", function()
            rmLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
            rmHl:SetAlpha(0)
        end)
        rmItem:SetScript("OnClick", function()
            menu:Hide()
            if barKey == "buffs" then
                -- Main buffs bar: slotIndex maps to the mixed preview list (Blizzard
                -- buffs + customs), not assignedSpells, so remove the injected custom by spellID and clean its metadata.
                if rmSpellID then
                    ns.RemoveSpellFromBar(barKey, rmSpellID)
                    local sdR = ns.GetBarSpellData(barKey)
                    if sdR and sdR.spellDurations then sdR.spellDurations[rmSpellID] = nil end
                    if ns.RebuildSpellRouteMap then ns.RebuildSpellRouteMap() end
                    if ns.QueueReanchor then ns.QueueReanchor() end
                end
            else
                -- A legacy-duplicate buff slot covers >1 assignedSpells entry
                -- (anchorFrame._dataGroup): remove them all, highest index first. Normal
                -- slots (including cd-claim marker slots for collided buffs, which carry a real single-entry index) have one entry (or no group) -> plain remove.
                local grp = anchorFrame and anchorFrame._dataGroup
                if grp and #grp > 1 then
                    local order = {}
                    for _, v in ipairs(grp) do order[#order + 1] = v end
                    table.sort(order, function(a, b) return a > b end)
                    for _, gi in ipairs(order) do ns.RemoveTrackedSpell(barKey, gi) end
                else
                    ns.RemoveTrackedSpell(barKey, slotIndex)
                end
            end
            RefreshCDPreview()
        end)

        allItems[#allItems + 1] = rmItem
        mH = mH + ITEM_H
    end

    -- Main buffs bar, Blizzard-tracked buff (not injected custom): can't be removed in
    -- EUI (Blizzard owns tracking), so offer a "Delete Spell" row that opens Blizzard's CDM (closes EUI options), matching the page's link behavior.
    if slotIndex and barKey == "buffs" and not rmIsInjected and rmSpellID then
        local dsItem = CreateFrame("Button", nil, inner)
        dsItem:SetHeight(ITEM_H)
        dsItem:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
        dsItem:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
        dsItem:SetFrameLevel(menu:GetFrameLevel() + 2)

        local dsHl = dsItem:CreateTexture(nil, "ARTWORK")
        dsHl:SetAllPoints(); dsHl:SetColorTexture(1, 1, 1, 0); dsHl:SetAlpha(0)

        local dsLbl = dsItem:CreateFontString(nil, "OVERLAY")
        dsLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
        dsLbl:SetPoint("LEFT", 10, 0)
        dsLbl:SetJustifyH("LEFT")
        dsLbl:SetText(EllesmereUI.L("Delete Spell"))
        dsLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)

        dsItem:SetScript("OnEnter", function()
            dsLbl:SetTextColor(1, 1, 1, 1)
            dsHl:SetColorTexture(1, 1, 1, hlA); dsHl:SetAlpha(1)
            if menu._openSub and menu._openSub:IsShown() then menu._openSub:Hide() end
        end)
        dsItem:SetScript("OnLeave", function()
            dsLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
            dsHl:SetAlpha(0)
        end)
        dsItem:SetScript("OnClick", function()
            menu:Hide()
            if ns.OpenBlizzardCDMTab then ns.OpenBlizzardCDMTab(true) end
        end)

        allItems[#allItems + 1] = dsItem
        mH = mH + ITEM_H
    end

    local function AddTalentConditionsRow(spellID, ss, ensureSettings)
        local tcConds = rawget(ss, "talentConditions")
        local tcCount = type(tcConds) == "table" and #tcConds or 0
        local tcRow = CreateFrame("Button", nil, inner)
        tcRow:SetHeight(ITEM_H)
        tcRow:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
        tcRow:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
        tcRow:SetFrameLevel(menu:GetFrameLevel() + 2)
        local tcLbl = tcRow:CreateFontString(nil, "OVERLAY")
        tcLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
        tcLbl:SetPoint("LEFT", 10, 0); tcLbl:SetPoint("RIGHT", -10, 0)
        tcLbl:SetJustifyH("LEFT"); tcLbl:SetWordWrap(false); tcLbl:SetMaxLines(1)
        tcLbl:SetText(EllesmereUI.Lf("Talent Conditions: %1$s",
            tcCount > 0 and tostring(tcCount) or EllesmereUI.L("None")))
        tcLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
        local tcHl = tcRow:CreateTexture(nil, "ARTWORK")
        tcHl:SetAllPoints(); tcHl:SetColorTexture(1, 1, 1, 0); tcHl:SetAlpha(0)
        tcRow:SetScript("OnEnter", function()
            tcLbl:SetTextColor(1, 1, 1, 1)
            tcHl:SetColorTexture(1, 1, 1, hlA); tcHl:SetAlpha(1)
            if menu._openSub and menu._openSub:IsShown() then menu._openSub:Hide() end
            EllesmereUI.ShowWidgetTooltip(tcRow, EllesmereUI.L("Show this icon only while the talents you pick are taken, or not taken."))
        end)
        tcRow:SetScript("OnLeave", function()
            tcLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA); tcHl:SetAlpha(0)
            EllesmereUI.HideWidgetTooltip()
        end)
        tcRow:SetScript("OnClick", function()
            EllesmereUI.HideWidgetTooltip()
            menu:Hide()
            ns.ShowCDMTalentConditionsPopup(spellID, tcConds, function(newConds)
                ensureSettings()
                ss.talentConditions = newConds
                if newConds then ns._cdmAnyTalentCond = true end
                RefreshCDPreview()
            end)
        end)
        mH = mH + ITEM_H
    end

    if removeOnly then
        -- Per-icon settings: CD/utility bars get the full menu; buff-family bars get a
        -- buff-specific subset. custom_buff (Auras) bars excluded here (separate system).
        if slotIndex and not isCustomBuff then
            local sd = ns.GetBarSpellData(barKey)
            -- Buff bars: the preview slot's own _previewSpellID is authoritative. The
            -- default buffs bar's preview maps to a MIXED list (Blizzard buffs +
            -- injected customs), NOT to assignedSpells, so indexing assignedSpells by the
            -- preview slot returns the WRONG entry. CD/utility slots map 1:1 to assignedSpells (carrying negative trinket/item markers _previewSpellID doesn't), so keep the index path for those.
            local spellID
            if isBuffBar then
                spellID = ResolveBuffSettingsKey(anchorFrame)
                    or (sd and sd.assignedSpells and sd.assignedSpells[slotIndex])
                -- Unresolved cd-claim slot (tracked trinket row with its buff down):
                -- key it the way the runtime reads cd-claimed slots.
                local cdClaimB = type(spellID) == "number" and ns.CdClaimMarkerToCdID(spellID)
                if cdClaimB then spellID = "c" .. cdClaimB end
            else
                spellID = sd and sd.assignedSpells and sd.assignedSpells[slotIndex]
                if (not spellID or spellID == 0) and anchorFrame and anchorFrame._previewSpellID then
                    spellID = anchorFrame._previewSpellID
                end
                -- Cd-claimed collided-buff slot: settings key is the collision "c"..
                -- cooldownID form directly -- the marker's mere presence already proves
                -- this slot's identity (no ambiguity, unlike ResolveBuffSettingsKey's buff-bar case). Matches ResolveSpellSettings' runtime key exactly (EUI_CDM_HookResolve.lua, settings["c"..cdID]).
                local cdClaimS = spellID and ns.CdClaimMarkerToCdID and ns.CdClaimMarkerToCdID(spellID)
                if cdClaimS then
                    spellID = "c" .. cdClaimS
                -- Hosted-buff MARKER slot: settings key by the DECODED spell id (the id the render resolver and the buffs bar key by), never the raw marker.
                elseif spellID and ns.HostedBuffMarkerToSpell and ns.HostedBuffMarkerToSpell(spellID) then
                    spellID = ns.HostedBuffMarkerToSpell(spellID)
                end
            end
            if ns.IsEmptySlotMarker(spellID) then
                -- Empty slots only expose identity-level conditions, never icon styling.
                if not EllesmereUI.IS_FOREVER and not isBuffBar and not (bd and bd.isGhostBar) then
                    local store = ns.GetSpellSettingsStore(barKey, true)
                    if store then
                        local ss = store[spellID] or {}
                        AddTalentConditionsRow(spellID, ss, function()
                            store[spellID] = ss
                        end)
                    end
                end
            elseif spellID and spellID ~= 0 then
                -- Hosted-buff SLOT? The slot decides, not the flag alone: the same
                -- spellID can also be this bar's cooldown entry, which must keep the CD
                -- store + cd/util menu. Legacy fallback: flag set with no marker entry yet means the plain entry is the buff (pre-marker data).
                local isHostedBuff = (anchorFrame and anchorFrame._previewHostedBuff) or false
                if not isHostedBuff and sd and sd.hostedBuffSpellIDs and sd.hostedBuffSpellIDs[spellID]
                   and not (ns.ListHasHostedMarker and sd.assignedSpells
                            and ns.ListHasHostedMarker(sd.assignedSpells, spellID)) then
                    isHostedBuff = true
                end
                -- Per-spell entries live in the spec FAMILY store (travel with the spell
                -- across bars); bar tiers sit below them: sd.barSettings ("Apply to Bar")
                -- -> bd.barSpellSettings ("Apply to Bar (All Specs)"). A hosted buff uses the BUFF store (same entry as on the buffs bar) and never chains to this bar's cd/util tiers.
                local store = ns.GetSpellSettingsStore(isHostedBuff and "buffs" or barKey, true)
                local bdSel = ns.barDataByKey and ns.barDataByKey[barKey]
                local famKey = ns.SettingsFamilyKey(isHostedBuff and "buffs" or barKey)
                -- Effective-read view: the entry (or a not-yet-persisted fresh table)
                -- chained to the bar tiers, so the menu shows the values the icon actually renders with; EnsureSS() persists the entry on first WRITE.
                local ss = store and store[spellID]
                if not ss then
                    -- A cooldownID-keyed slot with no entry yet renders its spell's entry
                    -- (the runtime falls back to it): start from a copy, so the first
                    -- write keeps those values instead of shadowing them.
                    local src = type(spellID) == "string" and store and anchorFrame
                        and anchorFrame._previewSpellID and store[anchorFrame._previewSpellID]
                    ss = type(src) == "table" and CopyTable(src) or {}
                end
                ns.ChainSettings(ss, (not isHostedBuff) and ns.GetBarTierSettings(sd, barKey) or nil)
                local function EnsureSS()
                    if store and not store[spellID] then
                        store[spellID] = ss
                        -- New per-spell entry: retire memoized resolution results so every icon re-resolves against it.
                        ns._cdmResGen = (ns._cdmResGen or 0) + 1
                        -- Flip the runtime hot-path gate the moment a cooldownID-scoped buff entry is first persisted.
                        if type(spellID) == "string" and string.byte(spellID, 1) == 99
                           and ns.MarkBuffFamHasCdKey then
                            ns.MarkBuffFamHasCdKey()
                        end
                    end
                    return ss
                end
                -- Own-value writer for clearable keys: writing nil would let an inherited
                -- bar-tier value show through; when that would change the effective value,
                -- store explicit false instead (render-equivalent to nil, but blocks inheritance).
                local function SetOwn(key, val)
                    ss[key] = val
                    if val == nil and ss[key] ~= nil then
                        ss[key] = false
                    end
                end

                -----------------------------------------------------------
                --  "Apply to Bar" machinery (hover strip on flyout items). One table
                --  local (AB) instead of individual locals: this function is enormous and Lua 5.1 caps active locals at 200.
                -----------------------------------------------------------
                local AB = {}
                -- Run fn(sid, entry) for every per-spell entry belonging to a bar in the
                -- given spec profile. The DEFAULT buffs bar owns every buff-store entry not claimed by another buff bar (Blizzard-tracked buffs aren't in assignedSpells).
                AB.ForEachMemberEntry = function(prof, bsX, fn)
                    local st = prof and prof[famKey]
                    if not st then return end
                    if barKey == "buffs" then
                        local claimed = {}
                        local bsAll = prof.barSpells
                        if bsAll then
                            for k2, b2 in pairs(bsAll) do
                                if k2 ~= "buffs" and type(b2) == "table"
                                   and ns.IsBarBuffFamily and ns.IsBarBuffFamily(k2)
                                   and type(b2.assignedSpells) == "table" then
                                    for _, sid2 in ipairs(b2.assignedSpells) do
                                        claimed[sid2] = true
                                        -- A cd-claimed member is listed by its MARKER but stores
                                        -- its settings under "c"..cooldownID; claim both or this
                                        -- bar's entry reads as unclaimed and gets wiped.
                                        local cdID2 = ns.CdClaimMarkerToCdID and ns.CdClaimMarkerToCdID(sid2)
                                        if cdID2 then claimed["c" .. cdID2] = true end
                                    end
                                end
                                -- Also exclude HOSTED buffs (on cd/util bars): removed from Apply-to-Bar,
                                -- so a default-buffs-bar apply must not treat their buff-store entry as unclaimed and wipe it.
                                AB.ForEachHostedKey(b2, function(hkey) claimed[hkey] = true end)
                            end
                        end
                        for sid2, e in pairs(st) do
                            if type(e) == "table" and not claimed[sid2] then fn(sid2, e) end
                        end
                    elseif bsX and type(bsX.assignedSpells) == "table" then
                        -- Hosted buffs are excluded from Apply-to-Bar: never treat one as a
                        -- bar member (so a bar apply can't clear/overwrite its per-spell settings).
                        local hosted = bsX.hostedBuffSpellIDs
                        for _, sid2 in ipairs(bsX.assignedSpells) do
                            if not (hosted and hosted[sid2]) then
                                local e = st[sid2]
                                if type(e) == "table" then fn(sid2, e) end
                            end
                        end
                    end
                end

                -- Zero-cost feature gates: a bar-tier write can enable features
                -- the per-spell setters normally arm -- flip the same flags.
                AB.FlipSessionGates = function(t)
                    if not t then return end
                    if t.reverseSwipe then ns._cdmAnyReverseSwipe = true end
                    if t.hideCDSwipe then ns._cdmAnyHideCDSwipe = true end
                    if (tonumber(t.thresholdSeconds) or 0) > 0 then ns._cdmAnyThresholdText = true end
                    if t.maxStacksGlow and t.maxStacksGlow > 0 then ns._cdmAnyMaxStacksGlow = true end
                    if t.desatNotActive then ns._cdmAnyDesatNotActive = true end
                    if t.noDesatOnCD then ns._cdmAnyNoDesatOnCD = true end
                    if t.chargeHideCdText then ns._cdmAnyChargeHideCdText = true end
                    if t.hideChargeText then ns._cdmAnyHideChargeText = true end
                    if t.suppressGCD then ns._cdmAnySuppressGcd = true end
                    if t.chargeHideSwipe or t.hideRechargeEdge then ns._cdmAnyChargeStyle = true end
                    if t.cdReadySoundKey and t.cdReadySoundKey ~= "none" then ns._cdmAnyCdReadySound = true end
                    if (t.buffActiveSoundKey and t.buffActiveSoundKey ~= "none")
                        or (t.buffLostSoundKey and t.buffLostSoundKey ~= "none") then
                        ns._cdmAnyBuffSound = true
                    end
                    if ns.PluginGlowsFlipGate then ns.PluginGlowsFlipGate(t) end
                end

                -- Any Resource Aware CD-ready glow already saved in this spec
                -- (per-spell entries or bar tiers)? Gates the one-time perf
                -- confirm popup, mirroring the per-spell setter.
                AB.AnyResourceAwareGlowSaved = function()
                    local function hit(b)
                        local e2 = b and b.cdStateEffect
                        return e2 == "pixelGlowReadyUsable" or e2 == "buttonGlowReadyUsable"
                    end
                    local st = ns.GetSpellSettingsStore and ns.GetSpellSettingsStore(barKey)
                    if st then
                        for _, e in pairs(st) do
                            if type(e) == "table" and hit(e) then return true end
                        end
                    end
                    local cb = ns.ECME and ns.ECME.db and ns.ECME.db.profile
                        and ns.ECME.db.profile.cdmBars
                    local barsList = cb and cb.bars
                    if barsList then
                        for _, b2 in ipairs(barsList) do
                            if hit(b2.barSpellSettings) then return true end
                            local bsd = ns.GetBarSpellData and ns.GetBarSpellData(b2.key)
                            if bsd and hit(bsd.barSettings) then return true end
                        end
                    end
                    return false
                end

                -- Keys that preset/custom icons route through the profile-level
                -- customActiveStates store instead of the ss/tier chain (Fake-Active
                -- engine reads rule.cas first); a bar apply touching any of these also stamps each preset member's cas entry, so "Apply to Bar" styles preset icons too.
                AB.CAS_KEYS = {
                    activeSwipeMode = true, activeSwipeClassColor = true,
                    activeSwipeR = true, activeSwipeG = true,
                    activeSwipeB = true, activeSwipeA = true,
                    activeGlow = true, glowColor = true,
                    glowColorR = true, glowColorG = true, glowColorB = true,
                    cdStateEffect = true, cdStateLowerAlpha = true, cdStateGlowStyle = true,
                    cdStateGlowAlpha = true,
                    reverseSwipe = true, hideCDSwipe = true,
                    thresholdSeconds = true, thresholdDecimals = true,
                    thresholdColorEnabled = true, thresholdColorR = true,
                    thresholdColorG = true, thresholdColorB = true,
                }
                -- Keys a bar apply also stamps onto the bar's HOSTED buffs. A hosted buff
                -- never chains to the bar tiers -- the tier carries cd-bar meaning for shared
                -- keys (Duration Text, Border) and its entry is the same one the spell uses on
                -- a buffs bar -- so a bar apply otherwise skips it entirely. These keys read
                -- the same on any icon, so they stamp directly, like preset icons do through
                -- StampMemberCas. Only rows whose keys are ALL in here stamp.
                AB.HOSTED_KEYS = {
                    thresholdSeconds = true, thresholdDecimals = true,
                    thresholdColorEnabled = true, thresholdColorR = true,
                    thresholdColorG = true, thresholdColorB = true,
                }
                -- Hosted buffs keep their entries in the BUFF family store whatever family the host bar belongs to.
                AB.hostedFamKey = ns.SettingsFamilyKey("buffs")
                AB.TouchesHosted = function(keys)
                    if not keys or #keys == 0 then return false end
                    for _, k in ipairs(keys) do
                        if not AB.HOSTED_KEYS[k] then return false end
                    end
                    return true
                end
                -- Every BUFF-store key the bar's hosted buffs use. Two shapes: a plain spell id
                -- from hostedBuffSpellIDs, and "c"..cooldownID for a CD-CLAIMED slot, whose
                -- marker lives in assignedSpells while hostedBuffSpellIDs carries only the
                -- existence sentinel AddHostedBuffByCdID sets. That sentinel doubles as the
                -- gate: a buff-family bar never sets it, so its own cd-claim markers (ordinary
                -- members via AddTrackedBuffByCdID, not hosted) are never read as hosted slots.
                AB.ForEachHostedKey = function(bsX, fn)
                    if type(bsX) ~= "table" or type(bsX.hostedBuffSpellIDs) ~= "table" then return end
                    for hsid in pairs(bsX.hostedBuffSpellIDs) do fn(hsid) end
                    if type(bsX.assignedSpells) == "table" and ns.CdClaimMarkerToCdID then
                        for _, sid2 in ipairs(bsX.assignedSpells) do
                            local cdID = ns.CdClaimMarkerToCdID(sid2)
                            if cdID then fn("c" .. cdID) end
                        end
                    end
                end
                -- Stamp one spec profile's hosted buffs on this bar. Blocking-false has nothing
                -- to block here (hosted entries chain to no tier), so an "off" apply clears the
                -- keys instead, and an entry left empty is dropped.
                AB.StampHostedBuffs = function(prof, bsX, applyWrite, val, keys)
                    local st
                    local mintedCdKey = false
                    AB.ForEachHostedKey(bsX, function(hkey)
                        -- Resolved on the first hosted key, not up front: an All Specs apply on
                        -- a bar with no hosted buffs would otherwise mint an empty family store
                        -- in every spec profile.
                        st = st or (ns.GetSpellSettingsStoreForProf
                            and ns.GetSpellSettingsStoreForProf(prof, AB.hostedFamKey, true))
                        if not st then return end
                        local e, fresh = st[hkey], false
                        if not e then e = {}; st[hkey] = e; fresh = true end
                        applyWrite(e, val)
                        -- Only the keys this apply wrote: reaching across the whole set would
                        -- drop blocking-false values the apply never touched, and the un-stamp
                        -- walks `keys` too, so it could not put them back.
                        for _, k in ipairs(keys) do
                            if rawget(e, k) == false then e[k] = nil end
                        end
                        if next(e) == nil then
                            st[hkey] = nil
                        elseif fresh and type(hkey) == "string" then
                            mintedCdKey = true
                        end
                    end)
                    -- A newly minted "c"..cooldownID entry stays invisible to the runtime until
                    -- the buff-family cd-key gate flips, the same call the menu's EnsureSS makes.
                    if mintedCdKey and ns.MarkBuffFamHasCdKey then ns.MarkBuffFamHasCdKey() end
                end
                AB.StampMemberCas = function(bsX, applyWrite, val, keys)
                    if not (bsX and type(bsX.assignedSpells) == "table") then return end
                    if not (ns.GetCustomActiveState and ns.ResolveCustomActiveKey) then return end
                    -- cas semantics: nil = no cd-state effect (PresetHasCdState checks effect
                    -- presence); explicit blocking-false is a tier/per-trinket-exclusion concept -- strip it from stamps. Threshold Text keys share the same cas semantics.
                    local function StripFalse(e)
                        if e.cdStateEffect == false then e.cdStateEffect = nil end
                        if e.thresholdSeconds == false then e.thresholdSeconds = nil end
                        if e.thresholdDecimals == false then e.thresholdDecimals = nil end
                        if e.thresholdColorEnabled == false then e.thresholdColorEnabled = nil end
                    end
                    for _, sid2 in ipairs(bsX.assignedSpells) do
                        local isInj = ((type(sid2) == "number" and sid2 < 0)
                            or (ns._myRacialsSet and ns._myRacialsSet[sid2])
                            or (bsX.customSpellIDs and bsX.customSpellIDs[sid2]))
                            -- Hosted-buff markers are reparented Blizzard buff frames,
                            -- not preset icons -- never mint cas entries for them.
                            and not (ns.HostedBuffMarkerToSpell and ns.HostedBuffMarkerToSpell(sid2))
                        if isInj then
                            if ns.SlotIDFromKey(sid2) then
                                -- Equipment slots stamp the SLOT entry: one bar application
                                -- covers whatever item is equipped, now or after any swap -- no entry minted per equipped item.
                                local e = ns.GetCustomActiveState(sid2, true)
                                if e then
                                    applyWrite(e, val)
                                    StripFalse(e)
                                end
                                -- Clear the applied keys from the EQUIPPED trinket's own
                                -- (item-keyed) entry so the apply visibly takes effect on it
                                -- (mirrors the member-entry clear RunBarApply does for family keys).
                                -- A per-trinket exclusion is re-chosen in the menu AFTER an apply; benched trinkets keep their per-item choices untouched.
                                local itemID = GetInventoryItemID("player", -sid2)
                                local own = itemID and ns.GetCustomActiveState(-itemID) or nil
                                if own and keys then
                                    for _, k2 in ipairs(keys) do own[k2] = nil end
                                end
                            else
                                local e = ns.GetCustomActiveState(ns.ResolveCustomActiveKey(sid2), true)
                                if e then
                                    applyWrite(e, val)
                                    StripFalse(e)
                                end
                            end
                        end
                    end
                end

                -- How many existing values would this apply REPLACE? Counts member per-spell
                -- entries (and preset cas entries / other specs' bar-tier values for All Specs)
                -- whose own value for a touched key differs -- equal values cost zero and don't count. Drives the "overwrite?" confirm popup.
                AB.CountApplyOverwrites = function(keys, applyWrite, val, allSpecs)
                    keys = keys or {}
                    if #keys == 0 or not applyWrite then return 0 end
                    -- Simulate the write to learn the concrete per-key values.
                    local temp = {}
                    applyWrite(temp, val)
                    local touchesCas = false
                    for _, k in ipairs(keys) do
                        if AB.CAS_KEYS[k] then touchesCas = true; break end
                    end
                    local touchesHosted = AB.TouchesHosted(keys)
                    local count = 0
                    local CAS_FALSE_STRIPPED = {
                        cdStateEffect = true, thresholdSeconds = true,
                        thresholdDecimals = true, thresholdColorEnabled = true,
                    }
                    local function entryLoses(e, isCas)
                        for _, k in ipairs(keys) do
                            local own = rawget(e, k)
                            local new = temp[k]
                            -- cas stamping normalizes the blocking-false away.
                            if isCas and CAS_FALSE_STRIPPED[k] and new == false then new = nil end
                            if own ~= nil and own ~= new then return true end
                        end
                        return false
                    end
                    local function sweep(prof)
                        if type(prof) ~= "table" then return end
                        local bsX = prof.barSpells and prof.barSpells[barKey]
                        if allSpecs and bsX and type(bsX.barSettings) == "table" then
                            for _, k in ipairs(keys) do
                                local own = bsX.barSettings[k]
                                if own ~= nil and own ~= temp[k] then
                                    count = count + 1
                                    break
                                end
                            end
                        end
                        AB.ForEachMemberEntry(prof, bsX, function(_, e)
                            if entryLoses(e, false) then count = count + 1 end
                        end)
                        if touchesCas and bsX and type(bsX.assignedSpells) == "table"
                           and ns.GetCustomActiveState and ns.ResolveCustomActiveKey then
                            for _, sid2 in ipairs(bsX.assignedSpells) do
                                local isInj = ((type(sid2) == "number" and sid2 < 0)
                                    or (ns._myRacialsSet and ns._myRacialsSet[sid2])
                                    or (bsX.customSpellIDs and bsX.customSpellIDs[sid2]))
                                    and not (ns.HostedBuffMarkerToSpell and ns.HostedBuffMarkerToSpell(sid2))
                                if isInj then
                                    -- Trinket slots resolve to the EQUIPPED item's own entry
                                    -- (the values the stamp will clear); the slot entry is the bar-level stamp itself (analogous to the tier) and is not counted.
                                    local e = ns.GetCustomActiveState(ns.ResolveCustomActiveKey(sid2))
                                    if e and entryLoses(e, true) then count = count + 1 end
                                end
                            end
                        end
                        -- Hosted buffs stamp their own entries (StampHostedBuffs), under the same blocking-false normalization the cas stamps use.
                        if touchesHosted then
                            local st = prof[AB.hostedFamKey]
                            if st then
                                AB.ForEachHostedKey(bsX, function(hkey)
                                    local e = st[hkey]
                                    if type(e) == "table" and entryLoses(e, true) then
                                        count = count + 1
                                    end
                                end)
                            end
                        end
                    end
                    local spAll = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
                    if allSpecs then
                        if spAll then
                            for _, prof in pairs(spAll) do sweep(prof) end
                        end
                    else
                        local specKeyA = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
                        local prof = spAll and specKeyA and spAll[specKeyA]
                        if prof then sweep(prof) end
                    end
                    return count
                end

                -- Write a picked value into a bar tier and clear the shadowing per-spell
                -- overrides from the bar's member spells, so the apply visibly takes effect
                -- everywhere. allSpecs writes the profile-level bd tier (which specs with no CDM data yet inherit) and sweeps every spec's spec-tier + overrides.
                AB.RunBarApply = function(applyKeys, applyWrite, val, allSpecs)
                    if not applyWrite then return end
                    local keys = applyKeys or {}
                    -- Resolve the value ONCE, before anything below clears a thing. A payload
                    -- writer (custom colour, Threshold Seconds) reads the source spell's own keys
                    -- back out of its entry, and the sweeps clear exactly those keys -- re-running
                    -- it per tier and per stamp would make the result depend on sweep order.
                    local temp = {}
                    applyWrite(temp, val)
                    local function stamp(t)
                        for _, k in ipairs(keys) do t[k] = temp[k] end
                    end
                    local touchesCas = false
                    for _, k in ipairs(keys) do
                        if AB.CAS_KEYS[k] then touchesCas = true; break end
                    end
                    local touchesHosted = AB.TouchesHosted(keys)
                    local function sweepProf(prof)
                        if type(prof) ~= "table" then return end
                        -- Sweeps can delete emptied member entries and the per-spec tier: retire memoized resolution results.
                        ns._cdmResGen = (ns._cdmResGen or 0) + 1
                        local bsX = prof.barSpells and prof.barSpells[barKey]
                        if allSpecs and bsX and type(bsX.barSettings) == "table" then
                            for _, k in ipairs(keys) do bsX.barSettings[k] = nil end
                            if next(bsX.barSettings) == nil then bsX.barSettings = nil end
                        end
                        AB.ForEachMemberEntry(prof, bsX, function(sid2, e)
                            for _, k in ipairs(keys) do rawset(e, k, nil) end
                            if next(e) == nil then
                                local st = prof[famKey]
                                if st then st[sid2] = nil end
                            end
                        end)
                        if touchesCas then
                            AB.StampMemberCas(bsX, stamp, val, keys)
                        end
                        if touchesHosted then
                            AB.StampHostedBuffs(prof, bsX, stamp, val, keys)
                        end
                    end
                    if allSpecs then
                        if not bdSel then return end
                        local abs = bdSel.barSpellSettings
                        if not abs then
                            abs = {}; bdSel.barSpellSettings = abs
                            -- New tier table: chained results are stale.
                            ns._cdmResGen = (ns._cdmResGen or 0) + 1
                        end
                        stamp(abs)
                        AB.FlipSessionGates(abs)
                        local spAll = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
                        if spAll then
                            for _, prof in pairs(spAll) do sweepProf(prof) end
                        end
                    else
                        -- Mutual exclusivity: applying to THIS bar (this spec) removes any
                        -- "Apply to Bar (All Specs)" apply for these keys, so the two scopes are
                        -- never both active (the reverse -- an All Specs apply clearing the
                        -- per-spec tier across every spec -- is handled by sweepProf above).
                        -- The canonical unapply also cleans up preset cas stamps; the per-spec write below then re-stamps THIS spec's members. No-op (and no refresh) when All Specs isn't active.
                        AB.RunBarUnapply(keys, true)
                        local bs = sd.barSettings
                        if not bs then
                            bs = {}; sd.barSettings = bs
                            -- New tier table: chained results are stale.
                            ns._cdmResGen = (ns._cdmResGen or 0) + 1
                        end
                        ns.ChainSettings(bs, bdSel and bdSel.barSpellSettings)
                        stamp(bs)
                        AB.FlipSessionGates(bs)
                        local spAll = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
                        local specKeyA = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
                        local prof = spAll and specKeyA and spAll[specKeyA]
                        if prof then sweepProf(prof) end
                    end
                    -- The open menu's view keeps reading through the (possibly freshly created) tier chain.
                    ns.ChainSettings(ss, ns.GetBarTierSettings(sd, barKey))
                    if touchesCas and ns.FakeActive_Rearm then ns.FakeActive_Rearm() end
                    if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                    if ns.QueueReanchor then ns.QueueReanchor() end
                end

                -- True when a BAR tier drives this setting -- "Apply to Bar" (this spec) or
                -- "Apply to Bar (All Specs)" holds a value for any of these keys. A blocking
                -- false counts (bar-spec "= Default" apply). Exclusion is per-spell now (SpellHasOwn), so there's no spec-level carve-out here: this only answers "does the bar drive this setting".
                AB.KeysBarApplied = function(keys)
                    if not keys then return false end
                    local bs = sd.barSettings
                    local abs = bdSel and bdSel.barSpellSettings
                    for _, k in ipairs(keys) do
                        if (bs and rawget(bs, k) ~= nil) or (abs and abs[k] ~= nil) then
                            return true
                        end
                    end
                    return false
                end

                -- True when the SPELL holds its OWN value for any of these keys (a
                -- per-spell override in THIS spec's store) -- the "excluded from the bar"
                -- state, having broken out of the bar apply. Inherently per spell AND spec (store is the active spec's profile).
                AB.SpellHasOwn = function(keys)
                    if not (keys and ss) then return false end
                    for _, k in ipairs(keys) do
                        if rawget(ss, k) ~= nil then return true end
                    end
                    return false
                end

                -- Include This Spell: drop this spell's own value for these keys so it
                -- rejoins the bar apply (per spell+spec; caller does the UI refresh). Shared by the b3 button and by Apply to Bar/All Specs on an already-excluded spell (same thing).
                AB.IncludeSpell = function(keys)
                    if not (keys and ss) then return end
                    for _, k in ipairs(keys) do rawset(ss, k, nil) end
                    ns.ChainSettings(ss, ns.GetBarTierSettings(sd, barKey))
                end

                -- Remove an active apply from one scope: clears the setting's keys from that
                -- tier only. Per-spell values and the OTHER scope are left alone (bar falls
                -- through to all-specs/defaults). Preset members' cas stamps are removed only when they still EQUAL the removed value -- per-icon cas tweaks made after the apply survive.
                AB.RunBarUnapply = function(applyKeys, allSpecs)
                    local keys = applyKeys or {}
                    local t
                    if allSpecs then
                        t = bdSel and bdSel.barSpellSettings
                    else
                        t = sd.barSettings
                    end
                    if not t then return end
                    local removed = {}
                    local touchesCas = false
                    for _, k in ipairs(keys) do
                        if AB.CAS_KEYS[k] then touchesCas = true end
                        removed[k] = rawget(t, k)
                        rawset(t, k, nil)
                    end
                    local touchesHosted = AB.TouchesHosted(keys)
                    if next(t) == nil then
                        if allSpecs then
                            if bdSel then bdSel.barSpellSettings = nil end
                        else
                            sd.barSettings = nil
                        end
                        -- Tier table dropped: chained results are stale.
                        ns._cdmResGen = (ns._cdmResGen or 0) + 1
                    end
                    if touchesCas and ns.GetCustomActiveState and ns.ResolveCustomActiveKey then
                        -- Remove still-equal stamped values from one cas entry. rawget: a
                        -- trinket item entry may be CHAINED to its slot entry, and an inherited
                        -- value must not read as an own stamp (clearing own nil is a no-op, but the equality test has to see own values only).
                        local function unstampEntry(e)
                            if not e then return end
                            for _, k in ipairs(keys) do
                                local rv = removed[k]
                                -- cas never stores the blocking-false (cdStateEffect + Threshold Text keys).
                                if rv == false and (k == "cdStateEffect"
                                    or k == "thresholdSeconds"
                                    or k == "thresholdDecimals"
                                    or k == "thresholdColorEnabled") then
                                    rv = nil
                                end
                                if rv ~= nil and rawget(e, k) == rv then e[k] = nil end
                            end
                        end
                        local function unstamp(prof, bsX)
                            if touchesHosted then
                                local st = prof and prof[AB.hostedFamKey]
                                if st then
                                    AB.ForEachHostedKey(bsX, function(hkey)
                                        local e = st[hkey]
                                        if not e then return end
                                        unstampEntry(e)
                                        -- Mirror the stamp: an entry the un-stamp empties is dropped, so it cannot linger and defeat the resolver's empty-store shortcut.
                                        if next(e) == nil then st[hkey] = nil end
                                    end)
                                end
                            end
                            if not (bsX and type(bsX.assignedSpells) == "table") then return end
                            for _, sid2 in ipairs(bsX.assignedSpells) do
                                local isInj = ((type(sid2) == "number" and sid2 < 0)
                                    or (ns._myRacialsSet and ns._myRacialsSet[sid2])
                                    or (bsX.customSpellIDs and bsX.customSpellIDs[sid2]))
                                    and not (ns.HostedBuffMarkerToSpell and ns.HostedBuffMarkerToSpell(sid2))
                                if isInj then
                                    if ns.SlotIDFromKey(sid2) then
                                        -- Equipment slots: the stamp lives on the SLOT entry. Also
                                        -- sweep the equipped item's own entry -- it may carry a legacy per-item stamp from before slot stamping.
                                        unstampEntry(ns.GetCustomActiveState(sid2))
                                        local itemID = GetInventoryItemID("player", -sid2)
                                        if itemID then
                                            unstampEntry(ns.GetCustomActiveState(-itemID))
                                        end
                                    else
                                        unstampEntry(ns.GetCustomActiveState(ns.ResolveCustomActiveKey(sid2)))
                                    end
                                end
                            end
                        end
                        local spAll = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
                        if allSpecs then
                            if spAll then
                                for _, prof in pairs(spAll) do
                                    if type(prof) == "table" then
                                        unstamp(prof, prof.barSpells and prof.barSpells[barKey])
                                    end
                                end
                            end
                        else
                            local specKeyA = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
                            local prof = spAll and specKeyA and spAll[specKeyA]
                            if prof then unstamp(prof, prof.barSpells and prof.barSpells[barKey]) end
                        end
                        if ns.FakeActive_Rearm then ns.FakeActive_Rearm() end
                    end
                    ns.ChainSettings(ss, ns.GetBarTierSettings(sd, barKey))
                    if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                    if ns.QueueReanchor then ns.QueueReanchor() end
                end

                -- The scope flyout itself: a vertical list (Apply to This Spell / Apply to
                -- Bar / Apply to Bar (All Specs) / conditional Exclude this spec) docked to the right of the hovered flyout item. One shared frame per menu; context swapped on each hover.
                AB.GetApplyStrip = function()
                    if menu._applyStrip then return menu._applyStrip end
                    -- Styled exactly like a subnav flyout: rows with a left-aligned label and the same white hover/selected overlay.
                    local SUBW = 180
                    local s = CreateFrame("Frame", nil, menu)
                    s:SetFrameStrata("FULLSCREEN_DIALOG")
                    s:SetFrameLevel(menu:GetFrameLevel() + 8)
                    s:SetClampedToScreen(true)
                    s:SetWidth(SUBW)
                    s:EnableMouse(true)
                    local bg = s:CreateTexture(nil, "BACKGROUND")
                    bg:SetAllPoints(); bg:SetColorTexture(mBgR, mBgG, mBgB, mBgA)
                    EllesmereUI.MakeBorder(s, 1, 1, 1, mBrdA, EllesmereUI.PP)
                    local sInner = CreateFrame("Frame", nil, s)
                    sInner:SetWidth(SUBW)
                    sInner:SetPoint("TOPLEFT")
                    -- One scope row: _active drives BOTH the accent label colour and the
                    -- persistent white overlay (the "selected" look, same as a subnav item); _rest repaints from it.
                    local function MakeScopeItem(text)
                        local b = CreateFrame("Button", nil, sInner)
                        b:SetHeight(ITEM_H)
                        b:SetFrameLevel(s:GetFrameLevel() + 2)
                        local l = b:CreateFontString(nil, "OVERLAY")
                        l:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                        l:SetPoint("LEFT", 10, 0)
                        l:SetJustifyH("LEFT")
                        l:SetText(text)
                        l:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                        local hl = b:CreateTexture(nil, "ARTWORK")
                        hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, hlA); hl:SetAlpha(0)
                        b._label = l
                        b._hl = hl
                        b._active = false
                        b._rest = function()
                            if b._active then
                                local aR, aG, aB = EllesmereUI.GetAccentColor()
                                l:SetTextColor(aR, aG, aB, 1)
                                hl:SetAlpha(1)
                            else
                                l:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                                hl:SetAlpha(0)
                            end
                        end
                        b:SetScript("OnEnter", function()
                            l:SetTextColor(1, 1, 1, 1); hl:SetAlpha(1)
                        end)
                        b:SetScript("OnLeave", function()
                            b._rest()
                        end)
                        b._setText = function(t) l:SetText(t) end
                        return b
                    end
                    local thisBtn = MakeScopeItem(EllesmereUI.L("Apply to This Spell"))
                    local b1 = MakeScopeItem(EllesmereUI.L("Apply to Bar"))
                    local b2 = MakeScopeItem(EllesmereUI.L("Apply to Bar (All Specs)"))
                    local b3 = MakeScopeItem(EllesmereUI.L("Exclude This Spell"))
                    b3._shown = false
                    -- Exclude/Include This Spell reads apart from the scope rows: soft red
                    -- when it will Exclude, soft green when it will Include, and NO persistent
                    -- white overlay when active (hover overlay only) -- b3._excluded (set in _updateActive) picks the colour.
                    b3._rest = function()
                        if b3._excluded then
                            b3._label:SetTextColor(0.55, 0.82, 0.55, 1)  -- Include: soft green
                        else
                            b3._label:SetTextColor(0.90, 0.45, 0.45, 1)  -- Exclude: soft red
                        end
                        b3._hl:SetAlpha(0)
                    end
                    b3:SetScript("OnEnter", function()
                        -- Hover overlay same as the other rows (the texture's own
                        -- colour is already hlA, so SetAlpha(1) shows it); only the
                        -- ACTIVE/persistent overlay is suppressed, in _rest.
                        b3._rest(); b3._hl:SetAlpha(1)
                    end)
                    b3:SetScript("OnLeave", function()
                        b3._rest()
                    end)
                    -- (Re)stack the visible rows top-to-bottom and size the frame.
                    -- Row 1 is "Apply to This Spell" normally, but a bar apply
                    -- REPLACES it with "Exclude / Include This Spell" (b3._shown) --
                    -- the two are mutually exclusive there. Then Apply to Bar / All
                    -- Specs.
                    local function Relayout()
                        local y = 4
                        local function place(it)
                            it:ClearAllPoints()
                            it:SetPoint("TOPLEFT", sInner, "TOPLEFT", 1, -y)
                            it:SetPoint("TOPRIGHT", sInner, "TOPRIGHT", -1, -y)
                            it:Show()
                            y = y + ITEM_H
                        end
                        if b3._shown then place(b3); thisBtn:Hide() else place(thisBtn); b3:Hide() end
                        place(b1); place(b2)
                        local total = y + 4
                        sInner:SetHeight(total)
                        s:SetHeight(total)
                        -- Widen to the longest scope caption. Relayout runs after
                        -- the Exclude/Include row is re-captioned, so the swapped
                        -- text is measured; all four rows count, so swapping row 1
                        -- never resizes the strip under the cursor.
                        local fitW = FitMenuWidth(
                            { thisBtn._label, b1._label, b2._label, b3._label }, SUBW)
                        s:SetWidth(fitW)
                        sInner:SetWidth(fitW)
                    end
                    -- Accent (and overlay) a scope ONLY when it holds an OWN value
                    -- for these keys that EQUALS the hovered item's value -- so the
                    -- highlight tracks the specific choice under the cursor, not
                    -- merely "this scope has some value applied".
                    s._updateActive = function()
                        local ctx = s._ctx
                        local keys = (ctx and ctx.keys) or {}
                        -- Simulate the write once: the hovered item's value as it would land in a tier table (false-blocks and all).
                        local temp = {}
                        if ctx and ctx.write and ctx.valueOf then
                            ctx.write(temp, ctx.valueOf())
                        end
                        local function holds(tier, raw)
                            if not tier then return false end
                            local anyOwn, match = false, true
                            for _, k in ipairs(keys) do
                                local own
                                if raw then own = rawget(tier, k) else own = tier[k] end
                                if own ~= nil then anyOwn = true end
                                if own ~= temp[k] then match = false end
                            end
                            return anyOwn and match
                        end
                        -- Excluded = the spell holds its OWN value for these keys. Exactly
                        -- ONE scope is the effective source: this spell when excluded, otherwise
                        -- whichever bar tier drives it -- so the overlay never sits on Apply to Bar while the spell is off on its own (even though the bar still holds it for others).
                        local excluded = false
                        for _, k in ipairs(keys) do
                            if rawget(ss, k) ~= nil then excluded = true; break end
                        end
                        -- "Apply to This Spell" only shows when NO bar apply drives the setting
                        -- (a bar apply REPLACES it with Exclude/Include -- see Relayout), so it
                        -- just lights on the value the spell owns. Toggles light whenever the spell has its own value (on OR off); OR settings match the specific value.
                        if ctx and ctx.isToggle then
                            thisBtn._active = excluded
                        else
                            thisBtn._active = holds(ss, true)
                        end
                        b1._active = (not excluded) and holds(sd.barSettings, true)
                        b2._active = (not excluded) and holds(bdSel and bdSel.barSpellSettings, false)
                        thisBtn._rest(); b1._rest(); b2._rest()
                        -- Exclude/Include This Spell: shown whenever a bar apply drives the
                        -- setting (so this spell+spec can opt out/back in). Label + soft red/green colour flip on the excluded state (b3._excluded drives the colour -- see b3._rest above).
                        if AB.KeysBarApplied(keys) then
                            b3._excluded = excluded
                            b3._setText(excluded and ("+ " .. EllesmereUI.L("Include This Spell"))
                                or ("+ " .. EllesmereUI.L("Exclude This Spell")))
                            b3._shown = true
                        else
                            b3._excluded = false
                            b3._shown = false
                        end
                        b3._rest()
                        Relayout()
                    end
                    -- Flash the border of whichever bar scope currently holds a value for
                    -- the hovered keys ("selected apply to bar setting"). Called when a
                    -- subnav click was a no-op because the bar already drives the setting -- the standard white border flash used across the UI, as a "look here" cue.
                    s._flashScopeFor = function()
                        local ctx = s._ctx
                        local keys = ctx and ctx.keys
                        if not keys then return end
                        local abs = bdSel and bdSel.barSpellSettings
                        local allActive = false
                        if abs then
                            for _, k in ipairs(keys) do
                                if abs[k] ~= nil then allActive = true; break end
                            end
                        end
                        local target = allActive and b2 or b1
                        if EllesmereUI.PlayWhiteFlash then EllesmereUI.PlayWhiteFlash(target) end
                    end
                    local function DoApply(allSpecs)
                        local ctx = s._ctx
                        if not ctx then return end
                        local val = ctx.valueOf and ctx.valueOf()
                        local keys = ctx.keys or {}
                        -- Simulate the write once: drives the rejoin match test, the toggle-off check, and the replace warning below.
                        local temp = {}
                        if ctx.write then ctx.write(temp, val) end
                        local scopeT
                        if allSpecs then
                            scopeT = bdSel and bdSel.barSpellSettings
                        else
                            scopeT = sd.barSettings
                        end
                        local scopeActive, valuesMatch = false, true
                        for _, k in ipairs(keys) do
                            local own
                            if scopeT then
                                if allSpecs then own = scopeT[k]
                                else own = rawget(scopeT, k) end
                            end
                            if own ~= nil then scopeActive = true end
                            if own ~= temp[k] then valuesMatch = false end
                        end
                        -- On an EXCLUDED spell the flyout sits on the bar's own value, so
                        -- Apply to Bar/All Specs means "rejoin the bar" (same as Include This
                        -- Spell) -- not re-applying the bar's value, which would just toggle it
                        -- off. Items with a payload the flyout val doesn't capture (scalar
                        -- Threshold Seconds; custom colour, where "custom" is fixed and the RGB
                        -- lives in ss; + Border Color's flag + RGBA): rejoin ONLY when the payload matches this scope; otherwise fall through and push it -- rejoining would silently discard it.
                        if AB.KeysBarApplied(keys) and AB.SpellHasOwn(keys)
                           and (not (ctx.scalarApply or ctx.payloadValue)
                                or (scopeActive and valuesMatch)) then
                            AB.IncludeSpell(keys)
                            if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                            if ns.QueueReanchor then ns.QueueReanchor() end
                            if ctx.refresh then ctx.refresh() end
                            if s._updateActive then s._updateActive() end
                            return
                        end
                        -- Toggle OFF: clicking a scope that already holds this exact value
                        -- un-applies it. Binary toggles carry no value, so any active scope is
                        -- an un-apply gesture -- EXCEPT + Border Color, whose RGBA payload makes
                        -- equality meaningful: un-apply only on a colour match, else push the new
                        -- one (un-applying would discard it). Custom-colour value items aren't toggles; isToggle already gates them -- only the rejoin branch above needed the payloadValue guard.
                        if scopeActive and (valuesMatch or (ctx.isToggle and not ctx.payloadValue)) then
                            -- Payload items (custom colour RGB, scalar seconds): the apply swept
                            -- the per-icon originals, so this scope holds the ONLY copy of the
                            -- value -- a plain un-apply would discard it and snap the setting to
                            -- default. Seed the removed value back into the spell in hand first, so toggle-off is an undo (recreates its pre-apply own value) instead of a silent reset.
                            if (ctx.scalarApply or ctx.payloadValue) and ss and scopeT then
                                -- EnsureSS, not ss directly: the apply's member sweep prunes an
                                -- entry it empties from the store (a spell whose ONLY settings were
                                -- the swept keys), leaving this closure's ss orphaned -- a seed into it
                                -- would be lost. EnsureSS re-persists the same table (no-op when it is still in the store).
                                local target = EnsureSS()
                                for _, k in ipairs(keys) do
                                    local own
                                    if allSpecs then own = scopeT[k]
                                    else own = rawget(scopeT, k) end
                                    if own ~= nil then rawset(target, k, own) end
                                end
                            end
                            AB.RunBarUnapply(keys, allSpecs)
                            if ctx.refresh then ctx.refresh() end
                            if s._updateActive then s._updateActive() end
                            return
                        end
                        local function go()
                            AB.RunBarApply(keys, ctx.write, val, allSpecs)
                            if ctx.refresh then ctx.refresh() end
                            if s._updateActive then s._updateActive() end
                        end
                        -- Confirm before anything destructive or costly: a first-time Resource
                        -- Aware glow (perf note), replacing this scope's active apply with a
                        -- different value (mutually exclusive selections un-check each other), and/or replacing existing per-icon values. One composed popup, never two in a row.
                        local needRA = ctx.confirmRA and not AB.AnyResourceAwareGlowSaved()
                        local replacing = scopeActive  -- (values differ, else un-applied above)
                        local overwrites = AB.CountApplyOverwrites(keys, ctx.write, val, allSpecs)
                        if not needRA and not replacing and overwrites == 0 then
                            go()
                            return
                        end
                        local title, message
                        if needRA then
                            title = EllesmereUI.L("CD Ready Glow (Resource Aware)")
                            message = EllesmereUI.L("Resource Aware CD Ready Glow may cause a slight loss in performance efficiency.")
                        else
                            title = EllesmereUI.L("Overwrite Existing Settings")
                            message = ""
                        end
                        if replacing then
                            local line = allSpecs
                                and EllesmereUI.L("This setting's active Apply to Bar (All Specs) value will be replaced.")
                                or EllesmereUI.L("This setting's active Apply to Bar value will be replaced.")
                            if message ~= "" then
                                message = message .. "\n\n" .. line
                            else
                                message = line
                            end
                        end
                        if overwrites > 0 then
                            -- The English key is itself a valid "%d" format string, so if a locale's
                            -- translation mangles the specifier and string.format errors, fall back to formatting the untranslated key.
                            local key = allSpecs
                                and "This replaces %d existing value(s) for this setting across your specs."
                                or "This replaces %d existing value(s) for this setting on this bar."
                            local ok, line = pcall(string.format, EllesmereUI.L(key), overwrites)
                            if not ok then line = string.format(key, overwrites) end
                            if message ~= "" then
                                message = message .. "\n\n" .. line
                            else
                                message = line
                            end
                        end
                        message = message .. " " .. EllesmereUI.L("Do you want to continue?")
                        menu:Hide()
                        EllesmereUI:ShowConfirmPopup({
                            title       = title,
                            message     = message,
                            confirmText = "Apply",
                            cancelText  = "Cancel",
                            onConfirm   = go,
                        })
                    end
                    -- Apply to This Spell: write the hovered value into the spell's OWN entry
                    -- in THIS spec's store (a per-spell override = excluding this spell+spec from the bar). No dissolve, no popup -- only this one spell changes; the bar apply stays for every other spell.
                    thisBtn:SetScript("OnClick", function()
                        local ctx = s._ctx
                        if not (ctx and ctx.write) then return end
                        EnsureSS()
                        ctx.write(ss, ctx.valueOf and ctx.valueOf())
                        if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                        if ns.QueueReanchor then ns.QueueReanchor() end
                        if ctx.refresh then ctx.refresh() end
                        if s:IsShown() and s._updateActive then s._updateActive() end
                    end)
                    b1:SetScript("OnClick", function() DoApply(false) end)
                    b2:SetScript("OnClick", function() DoApply(true) end)
                    -- Exclude / Include This Spell (per spell+spec, via ss).
                    b3:SetScript("OnClick", function()
                        local ctx = s._ctx
                        if not (ctx and ctx.write) then return end
                        local keys = ctx.keys or {}
                        if AB.SpellHasOwn(keys) then
                            -- Include: drop this spell's own value -> rejoin the bar.
                            AB.IncludeSpell(keys)
                        else
                            -- Exclude: break this spell out with its own value. OR
                            -- settings copy the current value (look unchanged); the
                            -- "+" toggles exclude by turning OFF for this spell.
                            EnsureSS()
                            local v
                            if ctx.isToggle then v = false else v = ctx.valueOf and ctx.valueOf() end
                            ctx.write(ss, v)
                        end
                        if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                        if ns.QueueReanchor then ns.QueueReanchor() end
                        if ctx.refresh then ctx.refresh() end
                        if s._updateActive then s._updateActive() end
                    end)
                    Relayout()
                    s:Hide()
                    menu._applyStrip = s
                    return s
                end
                -- Attach the strip to a hovered flyout item. ctx carries the row/item apply info + a flyout-refresh closure.
                AB.ShowApplyStripFor = function(itemBtn, ctx)
                    local s = AB.GetApplyStrip()
                    s._ctx = ctx
                    s._ownerItem = itemBtn
                    if s._updateActive then s._updateActive() end
                    s:ClearAllPoints()
                    -- Same 2px offset as the subnav flyouts, top-aligned to the hovered item.
                    -- Like a subnav, the strip does NOT hide on hover-out (crossing the gap
                    -- would kill it otherwise) -- it hides when its owner item goes away (flyout closed/rebuilt), when another item retargets it, or when the menu closes.
                    s:SetPoint("TOPLEFT", itemBtn, "TOPRIGHT", 2, 0)
                    s:Show()
                end

                -- Divider
                local div1 = inner:CreateTexture(nil, "ARTWORK")
                div1:SetHeight(1)
                div1:SetColorTexture(1, 1, 1, 0.10)
                div1:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
                div1:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
                mH = mH + 9

                local GLOW_ITEMS = {
                    { val = nil,  label = "Default" },
                    { val = 0,    label = "None" },
                    { val = 1,    label = "Pixel Glow" },
                    { val = 3,    label = "Action Button Glow" },
                    { val = 4,    label = "Auto-Cast Shine" },
                    { val = 2,    label = "Shape Glow" },
                    { val = 5,    label = "GCD" },
                    { val = 6,    label = "Modern WoW Glow" },
                    { val = 7,    label = "Classic WoW Glow" },
                }
                local ACTIVE_GLOW_ITEMS = {
                    { val = nil,  label = "None" },
                    { val = 1,    label = "Pixel Glow" },
                    { val = 3,    label = "Action Button Glow" },
                    { val = 4,    label = "Auto-Cast Shine" },
                    { val = 2,    label = "Shape Glow" },
                    { val = 5,    label = "GCD" },
                    { val = 6,    label = "Modern WoW Glow" },
                    { val = 7,    label = "Classic WoW Glow" },
                }
                local ACTIVE_SWIPE_ITEMS = {
                    { val = "custom",  label = "CD Swipe Color" },
                    { val = "class",   label = "CD Swipe Class Colored" },
                    { val = "none",    label = "Hide Active State" },
                    -- Independent toggle+swatch (NOT part of the swipe single-select above):
                    -- recolors the icon's border during active state. Its bar-apply writes only the border keys (never the swipe ones).
                    { activeBorder = true, label = "+ Border Color",
                      applyKeys  = { "activeBorderEnabled", "activeBorderR", "activeBorderG", "activeBorderB", "activeBorderA" },
                      applyWrite = function(t, v)
                          t.activeBorderEnabled = v and true or false
                          if v then
                              t.activeBorderR = ss.activeBorderR or 1
                              t.activeBorderG = ss.activeBorderG or 0.776
                              t.activeBorderB = ss.activeBorderB or 0.376
                              t.activeBorderA = ss.activeBorderA or 1
                          end
                      end },
                }
                local CD_STATE_ITEMS = {
                    { val = nil,               label = "None" },
                    -- Charge-spell toggle (independent boolean, NOT part of the single-select
                    -- cdStateEffect below); handled as a toggle in the item loop (item.charge names the ss key). Bar-apply writes an explicit true/false (false blocks the all-specs tier).
                    -- Hides the charge counter text outright (alpha 0 on
                    -- the shared zero-charge-text channel; see
                    -- WatchZeroChargeTextIfEnabled in CdmHooks).
                    -- Per-spell twin of the bar's Suppress GCD toggle
                    -- (ORed at every enforcement site, so the bar toggle
                    -- being ON makes this a natural no-op).
                    { charge = "suppressGCD", label = "+ Suppress GCD",
                      applyKeys  = { "suppressGCD" },
                      applyWrite = function(t, v) t.suppressGCD = v and true or false end },
                    { charge = "hideChargeText", label = "+ Hide Charge Text",
                      applyKeys  = { "hideChargeText" },
                      applyWrite = function(t, v) t.hideChargeText = v and true or false end },
                    { charge = "chargeHideSwipe", label = "+ Hide Swipe (Charges)",
                      applyKeys  = { "chargeHideSwipe" },
                      applyWrite = function(t, v) t.chargeHideSwipe = v and true or false end },
                    { charge = "hideRechargeEdge", label = "+ Hide Recharge Edge",
                      applyKeys  = { "hideRechargeEdge" },
                      applyWrite = function(t, v) t.hideRechargeEdge = v and true or false end },
                    { charge = "chargeHideCdText", label = "+ Hide Duration (Charges > 0)",
                      applyKeys  = { "chargeHideCdText" },
                      applyWrite = function(t, v) t.chargeHideCdText = v and true or false end },
                    -- Charge reading for the two Hidden (CD Ready) modes only: they normally
                    -- treat a charge spell as ready at MAX charges (icon appears on the first
                    -- spent charge and tracks the recharge); this opts the spell into "stay
                    -- hidden while any charge remains" (show only once fully spent). No effect on the other effects (already "no charges left") or non-charge spells.
                    { charge = "chargeHideUntilSpent", label = "+ Stay Hidden While Charges Remain",
                      applyKeys  = { "chargeHideUntilSpent" },
                      applyWrite = function(t, v) t.chargeHideUntilSpent = v and true or false end },
                    -- Same logic as Hidden (On CD) but with a customizable opacity instead of
                    -- a hard 0. Click prompts for the percent; the label shows it (e.g. "50%
                    -- Lower Alpha (On CD)") while selected. Its bar apply skips the popup and pushes the current percent.
                    { val = "lowerAlphaOnCD",  label = "Lower Alpha (On CD)",
                      dynamicLabel = function()
                          local base = EllesmereUI.L("Lower Alpha (On CD)")
                          if ss and ss.cdStateEffect == "lowerAlphaOnCD" then
                              local pct = math.floor(((ss.cdStateLowerAlpha or 0.5) * 100) + 0.5)
                              return pct .. "% " .. base
                          end
                          return base
                      end },
                    -- Shift variants: same hide as the plain modes below, but the bar re-lays out so the remaining icons close the gap.
                    { val = "hiddenOnCDShift",  label = "Hidden on CD (Shift Icons)" },
                    { val = "hiddenReadyShift", label = "Hidden CD Ready (Shift Icons)" },
                    { val = "hiddenUnusableShift", label = "Hidden Until Usable (Shift Icons)",
                      tooltip = "Only shown while usable and off cooldown, such as Overpower or Victory Rush after a proc. Low resources do not hide it." },
                    { val = "hiddenFormShift", label = "Hidden Outside Form/Stance (Shift Icons)",
                      tooltip = "Only shown in the form or stance the spell needs, even while it is on cooldown." },
                    { val = "hiddenOnCD",      label = "Hidden (On CD)" },
                    { val = "hiddenReady",     label = "Hidden (CD Ready)" },
                    { val = "hiddenUnusable",  label = "Hidden (Until Usable)",
                      tooltip = "Only shown while usable and off cooldown, such as Overpower or Victory Rush after a proc. Low resources do not hide it." },
                    { val = "hiddenForm",      label = "Hidden (Outside Form/Stance)",
                      tooltip = "Only shown in the form or stance the spell needs, even while it is on cooldown." },
                    -- One CD Ready glow per variant; the style is its own row below
                    -- (cdStateGlowStyle). The stored button* values still render as
                    -- Action Button Glow and read back as the matching entry here.
                    { val = "pixelGlowReady",  label = "Glow (CD Ready)" },
                    -- Mirror of the ready glow above: glows for the whole cooldown instead
                    -- of at readiness. Shares the Glow Style picker and the Proc Glow
                    -- priority gate below with every other glow effect here.
                    { val = "glowOnCD", label = "Glow (On CD)" },
                    -- Resource Aware variants: also require the spell to be castable
                    -- (resources/form) via the event-driven usability watcher. That watcher has
                    -- a small cost, so these are separate opt-in values (with a confirm popup) and the plain variants above stay cost-free.
                    { val = "pixelGlowReadyUsable",  label = "Glow CD Ready (Resource Aware)",
                      tooltip = "Glow CD Ready (Resource Aware)" },
                }
                -- Glow style picker (CDM saved numbering, every icon style), shared by
                -- both the CD Ready and On CD glow effects.
                local CD_READY_STYLE_ITEMS = {}
                for _, i in ipairs(ns.GLOW_VIEW.ordered) do local entry = ns.GLOW_STYLES[i]
                    CD_READY_STYLE_ITEMS[#CD_READY_STYLE_ITEMS + 1] = { val = i, label = entry.name }
                end
                local CD_GLOW_EFFECT = {
                    pixelGlowReady = "pixelGlowReady", buttonGlowReady = "pixelGlowReady",
                    pixelGlowReadyUsable = "pixelGlowReadyUsable", buttonGlowReadyUsable = "pixelGlowReadyUsable",
                    glowOnCD = "glowOnCD",
                }
                -- Reverse Swipe single-select (per-spell / per-preset), shared by both the regular-spell (ss) and preset/custom (cas) menus below.
                local REVERSE_SWIPE_ITEMS = {
                    { val = nil,  label = "Off" },
                    { val = true, label = "Reverse Swipe" },
                }
                -- Cooldown Swipe (cd/utility spells + presets): a 3-way single-select over
                -- two independent keys (reverseSwipe, hideCDSwipe). "Off" clears both; getVal/setVal below map the selection to the keys.
                local CD_SWIPE_ITEMS = {
                    { val = nil,       label = "Off" },
                    { val = "reverse", label = "Reverse Swipe" },
                    { val = "hide",    label = "Hide CD Swipe" },
                }

                -- Track open subnavs on the menu frame so OnUpdate can see them

                -- Hosted buffs are fully removed from the Apply-to-Bar system: this flag (set
                -- per-icon below, once isHostedBuff is known) suppresses the "Apply to Bar" hover strip on every row for a hosted buff.
                local hostedBuffNoApply = false

                -- Helper: subnav flyout (same style as Potions & Healthstone)
                -- isDefault: function returning true when the setting is at default value
                -- onItemCreated: optional callback(si, item, sub) for custom widgets per subnav item
                -- opts.host (optional) nests the row inside a parent flyout (see AB.MakePanelRow):
                -- { parent = frame holding the row, panel = the parent flyout, y = top offset, level = frame level }.
                local function MakeSubnavRow(label, items, getVal, setVal, isDefault, onItemCreated, opts)
                    local host = opts and opts.host
                    local rowParent = host and host.parent or inner
                    local row = CreateFrame("Button", nil, rowParent)
                    row:SetHeight(ITEM_H)
                    row:SetPoint("TOPLEFT", rowParent, "TOPLEFT", 1, -(host and host.y or mH))
                    row:SetPoint("TOPRIGHT", rowParent, "TOPRIGHT", -1, -(host and host.y or mH))
                    row:SetFrameLevel(host and host.level or (menu:GetFrameLevel() + 2))

                    local acR, acG, acB = EllesmereUI.GetAccentColor()

                    local lbl = row:CreateFontString(nil, "OVERLAY")
                    lbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                    lbl:SetPoint("LEFT", 10, 0)
                    lbl:SetJustifyH("LEFT")
                    lbl:SetText(EllesmereUI.L(label))

                    -- Optional disabled state (opts.disabled = function -> bool): greys the row, blocks the flyout, and shows a tooltip.
                    local function RowDisabled()
                        return opts and opts.disabled and opts.disabled() or false
                    end

                    local function UpdateLabelColor()
                        if RowDisabled() then
                            lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA * 0.4)
                        elseif not isDefault() then
                            lbl:SetTextColor(acR, acG, acB, 1)
                        else
                            lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                        end
                    end
                    UpdateLabelColor()

                    local arrow = row:CreateTexture(nil, "ARTWORK")
                    arrow:SetSize(10, 10)
                    arrow:SetPoint("RIGHT", row, "RIGHT", -8, 0)
                    arrow:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\right-arrow.png")
                    arrow:SetAlpha(RowDisabled() and 0.2 or 0.7)

                    local hl = row:CreateTexture(nil, "ARTWORK")
                    hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0); hl:SetAlpha(0)

                    local sub
                    local function ShowSub()
                        local hostPanel = host and host.panel
                        -- Nested rows only ever close a sibling inside their own panel, never the panel they live in.
                        local openSib
                        if hostPanel then openSib = hostPanel._openChild else openSib = menu._openSub end
                        if openSib and openSib ~= sub and openSib.Hide then openSib:Hide() end
                        if sub and sub:IsShown() then return end
                        if not sub then
                            sub = CreateFrame("Frame", nil, hostPanel or menu)
                            sub:SetFrameStrata("FULLSCREEN_DIALOG")
                            sub:SetFrameLevel((hostPanel or menu):GetFrameLevel() + (hostPanel and 3 or 5))
                            sub:SetClampedToScreen(true)
                            sub:EnableMouse(true)
                        else
                            for _, ch in ipairs({sub:GetChildren()}) do ch:Hide(); ch:SetParent(nil) end
                            for _, rg in ipairs({sub:GetRegions()}) do if rg.Hide then rg:Hide() end end
                        end

                        local subW = 180
                        sub:SetSize(subW, 10)
                        sub:ClearAllPoints()
                        sub:SetPoint("TOPLEFT", row, "TOPRIGHT", 2, 0)

                        local subBg = sub:CreateTexture(nil, "BACKGROUND")
                        subBg:SetAllPoints()
                        subBg:SetColorTexture(mBgR, mBgG, mBgB, mBgA)
                        EllesmereUI.MakeBorder(sub, 1, 1, 1, mBrdA, EllesmereUI.PP)

                        local subInner = CreateFrame("Frame", nil, sub)
                        subInner:SetWidth(subW)
                        subInner:SetPoint("TOPLEFT")

                        local subH = 4
                        local curVal = getVal()
                        -- "None"/default is stored as a blocking false; treat it as
                        -- nil so its item reads as selected (false ~= nil otherwise).
                        if curVal == false then curVal = nil end
                        local flyoutEntries = {}
                        -- Widen the flyout to its longest caption (FitMenuWidth).
                        -- Run once after the items are built -- before the
                        -- height/scroll branches below, which all size from subW --
                        -- and again whenever a dynamic label is recomposed in place
                        -- (e.g. "Lower Alpha (On CD)" gaining its "50% " prefix), so
                        -- a caption that grows while the flyout is open still fits.
                        local function RefitSub()
                            local labels = {}
                            for _, e in ipairs(flyoutEntries) do
                                if e.label then labels[#labels + 1] = e.label end
                            end
                            local fitW = FitMenuWidth(labels, subW)
                            if fitW == subW then return end
                            subW = fitW
                            sub:SetWidth(subW)
                            subInner:SetWidth(subW)
                        end
                        -- Re-highlight the selection in place after a value click. The flyout
                        -- stays OPEN (no rebuild -- that would reset scroll/search state and kill the apply strip's owner).
                        local function RefreshFlyoutSelection()
                            for _, e in ipairs(flyoutEntries) do
                                -- computeSelected re-derives the live selected state per item
                                -- (single-select value match OR independent toggle key) so a bar
                                -- "Apply" re-highlights the applied item exactly like a direct click -- a value-only path would leave toggles (e.g. Hide Recharge Edge) un-highlighted.
                                if e.setSelected and e.computeSelected then
                                    e.setSelected(e.computeSelected())
                                end
                                if e.refreshLabel then e.refreshLabel() end
                                -- Applying / un-applying to the bar changes which value
                                -- is the unclickable arrow row -- refresh it in place.
                                if e.updateArrow then e.updateArrow() end
                            end
                            -- A recomposed dynamic label may be wider than the
                            -- flyout was built for.
                            RefitSub()
                        end
                        -- Reachable from onItemCreated closures (color swatches),
                        -- which live outside this scope but capture `sub`.
                        sub._refreshSelection = RefreshFlyoutSelection
                        -- True when apply keys contain an R/G/B triple, i.e. the item carries a
                        -- per-spell colour the flyout val doesn't capture. Structural on purpose:
                        -- keying off val == "custom" missed payload toggles that use a different discriminator (Threshold Color, + Border Color), silently reintroducing the reset bug.
                        local function hasColourPayload(ks)
                            if not ks then return false end
                            local set = {}
                            for _, k in ipairs(ks) do set[k] = true end
                            for _, k in ipairs(ks) do
                                local base = k:match("^(.+)R$")
                                if base and set[base .. "G"] and set[base .. "B"] then
                                    return true
                                end
                            end
                            return false
                        end
                        for _, item in ipairs(items) do
                            if item.divider then
                                -- Thin separator line (e.g. between built-in sounds
                                -- and appended LibSharedMedia sounds). Never selectable.
                                local div = subInner:CreateTexture(nil, "ARTWORK")
                                div:SetHeight(1)
                                div:SetColorTexture(1, 1, 1, 0.10)
                                div:SetPoint("TOPLEFT", subInner, "TOPLEFT", 6, -subH - 4)
                                div:SetPoint("TOPRIGHT", subInner, "TOPRIGHT", -6, -subH - 4)
                                flyoutEntries[#flyoutEntries + 1] = { frame = div, isDivider = true }
                                subH = subH + 9
                            else
                            local si = CreateFrame("Button", nil, subInner)
                            si:SetHeight(ITEM_H)
                            si:SetPoint("TOPLEFT", subInner, "TOPLEFT", 1, -subH)
                            si:SetPoint("TOPRIGHT", subInner, "TOPRIGHT", -1, -subH)
                            si:SetFrameLevel(sub:GetFrameLevel() + 2)

                            local sLbl = si:CreateFontString(nil, "OVERLAY")
                            sLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                            sLbl:SetPoint("LEFT", 10, 0)
                            sLbl:SetJustifyH("LEFT")
                            -- item.dynamicLabel (optional) returns a fully-composed,
                            -- already-localized caption computed at render time (e.g.
                            -- "50% Lower Alpha (On CD)"); plain items localize item.label.
                            if item.dynamicLabel then
                                sLbl:SetText(item.dynamicLabel())
                            else
                                sLbl:SetText(EllesmereUI.L(item.label))
                            end

                            -- Highlight selected item. Charge entries are
                            -- independent toggles (item.charge names the ss
                            -- boolean key); item.toggleGet/toggleSet entries
                            -- are independent toggles over ANY store (the row
                            -- supplies the accessors, so the same items work
                            -- in the ss, buff and customActiveStates branches);
                            -- all other items are single-select on item.val.
                            local isChargeToggle = item.charge ~= nil
                            local isActiveBorder = item.activeBorder == true
                            local isFnToggle = item.toggleGet ~= nil
                            local isSelected
                            if isChargeToggle then
                                isSelected = (ss[item.charge] == true)
                            elseif isActiveBorder then
                                isSelected = (ss.activeBorderEnabled == true)
                            elseif isFnToggle then
                                isSelected = item.toggleGet() and true or false
                            else
                                isSelected = (curVal == item.val)
                                    or (curVal == nil and item.val == nil)
                            end
                            if isSelected then
                                local acR, acG, acB = EllesmereUI.GetAccentColor()
                                sLbl:SetTextColor(acR, acG, acB, 1)
                            else
                                sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                            end

                            local sHl = si:CreateTexture(nil, "ARTWORK")
                            -- Colour fixed to the hover white; alpha toggles it. The
                            -- SELECTED single-select item keeps this overlay on (a
                            -- persistent "hovered" look) so the active choice reads
                            -- clearly; the toggles ("+ " ones + Border Color) never do.
                            sHl:SetAllPoints(); sHl:SetColorTexture(1, 1, 1, hlA); sHl:SetAlpha(0)
                            if not (isChargeToggle or isActiveBorder or isFnToggle) and isSelected then
                                sHl:SetAlpha(1)
                            end

                            -- "Apply to Bar" hover strip context. EVERY value item and
                            -- independent toggle exposes bar-scope apply (the only settings without a strip are the action rows, e.g. Add Active State, which have no flyout items).
                            local rowApply = opts and opts.apply
                            local applyKeys  = item.applyKeys or (rowApply and rowApply.keys)
                            local applyWrite = item.applyWrite or (rowApply and rowApply.write)
                            -- Hosted buffs are excluded from Apply-to-Bar entirely.
                            local canApply = applyWrite ~= nil and not hostedBuffNoApply
                            -- When a bar apply drives this setting, the value the BAR applies acts
                            -- like a submenu row: it shows a right-arrow and is unclickable -- you
                            -- manage it through the scope flyout that opens on hover (Exclude/Include/Apply to Bar), never by re-selecting the value. A bar-applied "+ " toggle counts too.
                            local function itemIsBarApplied()
                                -- A hosted buff never chains to the bar tiers (its
                                -- effective read passes nil for the bar/spec tiers,
                                -- and the runtime resolver strips them too), so a
                                -- bar-wide apply can never drive it. Reporting
                                -- "bar applied" here would dead-lock its toggle
                                -- rows: the OnClick bails on bar-applied items and
                                -- hosted rows have no Apply strip to escape through.
                                if hostedBuffNoApply then return false end
                                if not (applyKeys and AB.KeysBarApplied(applyKeys)) then return false end
                                if isChargeToggle or isActiveBorder or isFnToggle then return true end
                                local barTier = ns.GetBarTierSettings and ns.GetBarTierSettings(sd, barKey)
                                local pk = applyKeys[1]
                                if not (barTier and pk) then return false end
                                local temp = {}
                                applyWrite(temp, item.val)
                                return barTier[pk] == temp[pk]
                            end
                            local sArrow = si:CreateTexture(nil, "ARTWORK")
                            sArrow:SetSize(10, 10)
                            sArrow:SetPoint("RIGHT", si, "RIGHT", -8, 0)
                            sArrow:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\right-arrow.png")
                            sArrow:SetAlpha(0.7)
                            sArrow:Hide()
                            local function updateArrow()
                                if canApply and itemIsBarApplied() then sArrow:Show() else sArrow:Hide() end
                            end
                            updateArrow()
                            si:SetScript("OnEnter", function()
                                if not isSelected then sLbl:SetTextColor(1, 1, 1, 1) end
                                sHl:SetColorTexture(1, 1, 1, hlA); sHl:SetAlpha(1)
                                -- Optional hover tooltip (item.tooltip): shows the
                                -- full text for labels wider than the flyout.
                                if item.tooltip then
                                    EllesmereUI.ShowWidgetTooltip(si, item.tooltip)
                                end
                                -- Whenever a bar apply drives this setting, only the value the BAR
                                -- applies keeps the Apply-to flyout (it's the arrow row); OR-siblings
                                -- hide theirs and stay normal clickable values. Holds on both a
                                -- following spell and an excluded one (the flyout tracks the bar's
                                -- value, never the spell's override). Settings with no bar apply show
                                -- it on everything; "+ " toggles are never OR, so they keep it. A
                                -- scalar popup value (Threshold Seconds) has only one item, so "the
                                -- bar's value differs from this item" is meaningless -- never suppress it, or Apply-to-Bar vanishes the moment the entered number differs from the bar's.
                                local suppressStrip = canApply and not item.scalarApply
                                    and not (isChargeToggle or isActiveBorder or isFnToggle)
                                    and AB.KeysBarApplied(applyKeys) and not itemIsBarApplied()
                                if suppressStrip then
                                    if menu._applyStrip then menu._applyStrip:Hide() end
                                elseif canApply then
                                    AB.ShowApplyStripFor(si, {
                                        keys  = applyKeys,
                                        write = applyWrite,
                                        scalarApply = item.scalarApply,
                                        isToggle = isChargeToggle or isActiveBorder or isFnToggle,
                                        -- Item whose val is only a discriminator while the real value
                                        -- carries a per-spell colour payload (an R/G/B triple in applyKeys),
                                        -- or an item the row flags as carrying another payload (apply.payload(item): the Blackout opacity).
                                        -- For those, equality must be judged by valuesMatch, not the identifier, or the rejoin/toggle-off shortcuts discard the payload (see the two branches in the apply handler above).
                                        payloadValue = hasColourPayload(applyKeys)
                                            or (rowApply and rowApply.payload and rowApply.payload(item)) or false,
                                        -- Toggles: "Apply to Bar" ENABLES the feature (apply true);
                                        -- disabling is the toggle-off press (ctx.isToggle un-applies when
                                        -- the scope already holds the value). Never key this off isSelected: that flips an already-ON toggle OFF when switching scopes (e.g. All Specs -> Apply to Bar). Value items apply their value.
                                        valueOf = function()
                                            if isChargeToggle or isActiveBorder or isFnToggle then
                                                return true
                                            end
                                            return item.val
                                        end,
                                        confirmRA = rowApply and rowApply.confirmRA
                                            and (item.val == "pixelGlowReadyUsable"
                                              or item.val == "buttonGlowReadyUsable"),
                                        -- No flyout rebuild here: rebuilding would destroy the strip's
                                        -- owner item and hide the strip mid-interaction (e.g. between "Apply
                                        -- to Bar" and "(All Specs)"). Flyout re-renders fresh on its next open; only the row's accent cue updates now.
                                        refresh = function()
                                            -- Re-highlight the applied flyout item in place (single-select
                                            -- mutual exclusion AND toggles), then the collapsed row label.
                                            RefreshFlyoutSelection()
                                            UpdateLabelColor()
                                            if opts and opts.onApplied then opts.onApplied() end
                                        end,
                                    })
                                end
                            end)
                            si:SetScript("OnLeave", function()
                                if not isSelected then sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA) end
                                -- Keep the overlay on for a selected single-select
                                -- (persistent highlight); clear it for everything else.
                                sHl:SetAlpha((not (isChargeToggle or isActiveBorder or isFnToggle) and isSelected) and 1 or 0)
                                if item.tooltip then EllesmereUI.HideWidgetTooltip() end
                            end)
                            si:SetScript("OnClick", function()
                                -- The value the bar applies is unclickable -- it's the submenu/arrow
                                -- row. Manage it through the scope flyout (Exclude/Include/Apply to Bar), not by re-selecting.
                                if itemIsBarApplied() then return end
                                -- The write this click performs, always into the spell's OWN entry
                                -- (charge toggle / active border / single-select value). Wrapped so the bar-override confirm below can defer it to the popup callback.
                                local function doWrite()
                                    -- Generic independent toggle (item.toggleGet/item.toggleSet): flips
                                    -- its own boolean through the row's store accessors (the setter owns
                                    -- the persist + gate flip + refresh calls) and keeps the flyout open, exactly like the charge toggles.
                                    if isFnToggle and item.toggleSet then
                                        item.toggleSet(not item.toggleGet())
                                        isSelected = item.toggleGet() and true or false
                                        if isSelected then
                                            local acR, acG, acB = EllesmereUI.GetAccentColor()
                                            sLbl:SetTextColor(acR, acG, acB, 1)
                                        else
                                            sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                                        end
                                        UpdateLabelColor()
                                        local strip = menu._applyStrip
                                        if strip and strip:IsShown() and strip._updateActive then strip._updateActive() end
                                        return
                                    end
                                    -- Charge toggles flip an independent boolean and keep the flyout
                                    -- open (so both can be set in one pass); they never touch the single-select cdStateEffect.
                                    if isChargeToggle then
                                        EnsureSS()
                                        if ss[item.charge] == true then
                                            SetOwn(item.charge, nil)
                                        else
                                            ss[item.charge] = true
                                        end
                                        isSelected = (ss[item.charge] == true)
                                        if isSelected then
                                            local acR, acG, acB = EllesmereUI.GetAccentColor()
                                            sLbl:SetTextColor(acR, acG, acB, 1)
                                            if item.charge == "chargeHideCdText" then
                                                ns._cdmAnyChargeHideCdText = true
                                            elseif item.charge == "hideChargeText" then
                                                ns._cdmAnyHideChargeText = true
                                            elseif item.charge == "suppressGCD" then
                                                ns._cdmAnySuppressGcd = true
                                            elseif item.charge ~= "chargeHideUntilSpent" then
                                                -- chargeHideUntilSpent needs no session gate: it is read
                                                -- inside the cd-state evaluator, which only runs for icons that have a Hidden (CD Ready) effect.
                                                ns._cdmAnyChargeStyle = true
                                            end
                                        else
                                            sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                                        end
                                        -- Live-update the collapsed row's accent, like
                                        -- the single-select path does.
                                        UpdateLabelColor()
                                        if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                                        if ns.QueueReanchor then ns.QueueReanchor() end
                                        local strip = menu._applyStrip
                                        if strip and strip:IsShown() and strip._updateActive then strip._updateActive() end
                                        return
                                    end
                                    -- Border Color: independent toggle (keeps flyout open). The inline
                                    -- swatch picks the color; the row toggles it on/off. Recolors the icon border during active state only.
                                    if isActiveBorder then
                                        EnsureSS()
                                        if ss.activeBorderEnabled == true then
                                            SetOwn("activeBorderEnabled", nil)
                                        else
                                            ss.activeBorderEnabled = true
                                        end
                                        isSelected = (ss.activeBorderEnabled == true)
                                        if isSelected then
                                            if not ss.activeBorderR then
                                                ss.activeBorderR = 1; ss.activeBorderG = 0.776
                                                ss.activeBorderB = 0.376; ss.activeBorderA = 1
                                            end
                                            local acR, acG, acB = EllesmereUI.GetAccentColor()
                                            sLbl:SetTextColor(acR, acG, acB, 1)
                                        else
                                            sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                                        end
                                        UpdateLabelColor()
                                        if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                                        if ns.QueueReanchor then ns.QueueReanchor() end
                                        local strip = menu._applyStrip
                                        if strip and strip:IsShown() and strip._updateActive then strip._updateActive() end
                                        return
                                    end
                                    setVal(item.val)
                                    -- Keep the flyout open (same as the toggle items): selecting a value
                                    -- should close neither the menu nor the subnav. Re-highlight in place.
                                    RefreshFlyoutSelection()
                                    UpdateLabelColor()
                                    if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                                    if ns.QueueReanchor then ns.QueueReanchor() end
                                    local strip = menu._applyStrip
                                    if strip and strip:IsShown() and strip._updateActive then strip._updateActive() end
                                end
                                -- When the BAR drives this setting and the spell has no own value yet: clicking the
                                -- value the bar already applies changes nothing -> flash the scope holding it (no-op
                                -- cue); clicking a different value (or a "+" toggle) breaks THIS spell+spec out into
                                -- its own value, no popup, the bar apply stays for every other spell (doWrite flips a
                                -- toggle OFF, the break-out for a bar-applied-ON toggle). Once the spell owns a value
                                -- it reports editable and writes straight through (the excluded state).
                                -- canApply: hosted-buff rows (and rows with no apply write) skip the break-out flow,
                                -- which flashes an Apply strip those rows suppress; they just write their value below.
                                if canApply and AB.KeysBarApplied(applyKeys) and not AB.SpellHasOwn(applyKeys) then
                                    if not (isChargeToggle or isActiveBorder or isFnToggle) then
                                        local cv = getVal()
                                        if (cv == item.val) or (cv == nil and item.val == nil) then
                                            local strip = menu._applyStrip
                                            if strip and strip._flashScopeFor then strip._flashScopeFor() end
                                            return
                                        end
                                    end
                                    doWrite()
                                    return
                                end
                                doWrite()
                            end)

                            if onItemCreated then
                                onItemCreated(si, item, sub)
                                -- The hook may attach a dynamic caption (the Blackout
                                -- percent): show it from the first open.
                                if item.dynamicLabel then sLbl:SetText(item.dynamicLabel()) end
                            end
                            flyoutEntries[#flyoutEntries + 1] = {
                                frame = si, label = sLbl, name = item.label,
                                itemVal = item.val,
                                isToggle = isChargeToggle or isActiveBorder or isFnToggle,
                                -- Live selected-state predicate, mirroring the render-time isSelected
                                -- assignment above. Reads effective (chained) values, so it reflects a bar-tier apply, not just the spell's own entry.
                                computeSelected = function()
                                    if isChargeToggle then return ss[item.charge] == true end
                                    if isActiveBorder then return ss.activeBorderEnabled == true end
                                    if isFnToggle then return item.toggleGet() and true or false end
                                    local cv = getVal()
                                    if cv == false then cv = nil end  -- None/default blocks with false
                                    return (cv == item.val) or (cv == nil and item.val == nil)
                                end,
                                -- In-place selection update for the keep-open click path (also keeps the item's OnLeave and the strip's toggle state in sync).
                                setSelected = function(sel)
                                    isSelected = sel
                                    if sel then
                                        local acR2, acG2, acB2 = EllesmereUI.GetAccentColor()
                                        sLbl:SetTextColor(acR2, acG2, acB2, 1)
                                    else
                                        sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                                    end
                                    -- Selected single-select keeps the white overlay (toggles never get the persistent look).
                                    if not (isChargeToggle or isActiveBorder) then
                                        sHl:SetAlpha(sel and 1 or 0)
                                    end
                                end,
                                refreshLabel = function()
                                    if item.dynamicLabel then sLbl:SetText(item.dynamicLabel()) end
                                end,
                                -- Live-update the arrow/unclickable state after an apply or un-apply (the flyout doesn't rebuild in place).
                                updateArrow = updateArrow,
                            }
                            subH = subH + ITEM_H
                            end -- item.divider / else
                        end

                        -- Fit the width to the longest caption before anything below sizes from subW.
                        RefitSub()

                        -- Cap height + scroll for long lists (e.g. the Audio Effect sound list),
                        -- matching the Focus Cast Sound dropdown and Custom Tracking subnav. Mouse-wheel + smooth scroll; short subnavs fall through to the unchanged fixed-height path.
                        local totalSubH = subH + 4
                        subInner:SetHeight(totalSubH)
                        -- 200 == the dropdown's DD_MAX_HEIGHT (Focus Cast Sound).
                        local FLYOUT_MAX_H = 200
                        if opts and opts.searchable then
                            -- Searchable flyout: a filter box pinned to the top with the list
                            -- scrolling below it. Items are uniform height (ITEM_H), so filtering just
                            -- repositions the survivors and hides separators while a query is active. Scroll range is recomputed live from the scroll child height.
                            local SEARCH_H = 24
                            local searchPad = SEARCH_H + 8
                            sub:SetSize(subW, FLYOUT_MAX_H + searchPad)

                            local searchEdit = CreateFrame("EditBox", nil, sub)
                            searchEdit:SetSize(subW - 12, SEARCH_H)
                            searchEdit:SetPoint("TOP", sub, "TOP", 0, -4)
                            searchEdit:SetFrameLevel(sub:GetFrameLevel() + 6)
                            searchEdit:SetFont(FONT_PATH, 11, "")
                            searchEdit:SetTextColor(1, 1, 1, 0.9)
                            searchEdit:SetJustifyH("LEFT")
                            searchEdit:SetAutoFocus(false)
                            searchEdit:SetMaxLetters(30)
                            searchEdit:SetTextInsets(4, 4, 0, 0)
                            local seBg = searchEdit:CreateTexture(nil, "BACKGROUND")
                            seBg:SetAllPoints()
                            seBg:SetColorTexture(0, 0, 0, 0.4)
                            local sePh = searchEdit:CreateFontString(nil, "OVERLAY")
                            sePh:SetFont(FONT_PATH, 11, "")
                            sePh:SetTextColor(0.5, 0.5, 0.5, 0.6)
                            sePh:SetPoint("LEFT", searchEdit, "LEFT", 4, 0)
                            sePh:SetText(EllesmereUI.L("Search..."))
                            searchEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
                            searchEdit:SetScript("OnHide", function(self) self:ClearFocus() end)

                            subInner:ClearAllPoints()
                            local sf = CreateFrame("ScrollFrame", nil, sub)
                            sf:SetPoint("TOPLEFT", 0, -searchPad)
                            sf:SetPoint("BOTTOMRIGHT")
                            sf:SetFrameLevel(sub:GetFrameLevel() + 1)
                            sf:EnableMouseWheel(true)
                            sf:SetScrollChild(subInner)
                            subInner:SetWidth(subW)

                            local _, scrollTo = EllesmereUI.AttachSmoothScrollbar(sf, { step = 40, thumb = false })

                            local function ApplyFlyoutFilter(raw)
                                local q = strlower(strtrim(raw or ""))
                                sePh:SetShown(q == "")
                                local yy = 4
                                for _, e in ipairs(flyoutEntries) do
                                    if e.isDivider then
                                        -- Separators only make sense in the full list.
                                        if q == "" then
                                            e.frame:Show()
                                            e.frame:ClearAllPoints()
                                            e.frame:SetPoint("TOPLEFT", subInner, "TOPLEFT", 6, -yy - 4)
                                            e.frame:SetPoint("TOPRIGHT", subInner, "TOPRIGHT", -6, -yy - 4)
                                            yy = yy + 9
                                        else
                                            e.frame:Hide()
                                        end
                                    else
                                        local nm = e.name or (e.label and e.label:GetText()) or ""
                                        if q == "" or strfind(strlower(tostring(nm)), q, 1, true) then
                                            e.frame:Show()
                                            e.frame:ClearAllPoints()
                                            e.frame:SetPoint("TOPLEFT", subInner, "TOPLEFT", 1, -yy)
                                            e.frame:SetPoint("TOPRIGHT", subInner, "TOPRIGHT", -1, -yy)
                                            yy = yy + ITEM_H
                                        else
                                            e.frame:Hide()
                                        end
                                    end
                                end
                                subInner:SetHeight(math.max(1, yy + 4))
                                scrollTo(0)
                            end
                            searchEdit:SetScript("OnTextChanged", function(self) ApplyFlyoutFilter(self:GetText()) end)
                            ApplyFlyoutFilter("")
                        elseif totalSubH > FLYOUT_MAX_H then
                            sub:SetSize(subW, FLYOUT_MAX_H)
                            subInner:ClearAllPoints()
                            local sf = CreateFrame("ScrollFrame", nil, sub)
                            sf:SetPoint("TOPLEFT"); sf:SetPoint("BOTTOMRIGHT")
                            sf:SetFrameLevel(sub:GetFrameLevel() + 1)
                            sf:EnableMouseWheel(true)
                            sf:SetScrollChild(subInner)
                            subInner:SetWidth(subW)
                            EllesmereUI.AttachSmoothScrollbar(sf, { step = 40, thumb = false })
                        else
                            sub:SetSize(subW, totalSubH)
                        end
                        sub:Show()
                        if hostPanel then hostPanel._openChild = sub else menu._openSub = sub end
                    end

                    row:SetScript("OnEnter", function()
                        if RowDisabled() then
                            if opts.disabledTooltip then
                                EllesmereUI.ShowWidgetTooltip(row, opts.disabledTooltip)
                            end
                            return
                        end
                        lbl:SetTextColor(1, 1, 1, 1)
                        hl:SetColorTexture(1, 1, 1, hlA); hl:SetAlpha(1)
                        ShowSub()
                    end)
                    row:SetScript("OnLeave", function()
                        if opts and opts.disabledTooltip then EllesmereUI.HideWidgetTooltip() end
                        UpdateLabelColor()
                        hl:SetAlpha(0)
                        -- Don't auto-close sub here. It closes when:
                        -- 1. A different subnav row is hovered (ShowSub closes _openSub)
                        -- 2. The parent menu closes (OnHide propagates)
                        -- 3. An option is clicked (OnClick hides sub)
                    end)

                    if not host then mH = mH + ITEM_H end
                    return row, sub
                end

                -- Panel row: a flyout whose entries are themselves rows, for nested menus
                -- (Plugin Glows > source > Glow Style). populate(add) fills the panel on every open:
                --   add.Subnav(label, items, getVal, setVal, isDefault, onItemCreated, opts)  -- MakeSubnavRow
                --   add.Panel(label, populate, isDefault)                                      -- a deeper panel
                -- host nests this row inside another panel the same way MakeSubnavRow's opts.host does.
                AB.MakePanelRow = function(label, populate, isDefault, host)
                    local rowParent = host and host.parent or inner
                    local row = CreateFrame("Button", nil, rowParent)
                    row:SetHeight(ITEM_H)
                    row:SetPoint("TOPLEFT", rowParent, "TOPLEFT", 1, -(host and host.y or mH))
                    row:SetPoint("TOPRIGHT", rowParent, "TOPRIGHT", -1, -(host and host.y or mH))
                    row:SetFrameLevel(host and host.level or (menu:GetFrameLevel() + 2))
                    local acR, acG, acB = EllesmereUI.GetAccentColor()
                    local lbl = row:CreateFontString(nil, "OVERLAY")
                    lbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                    lbl:SetPoint("LEFT", 10, 0)
                    lbl:SetJustifyH("LEFT")
                    lbl:SetText(EllesmereUI.L(label))
                    local function UpdateLabelColor()
                        if isDefault and not isDefault() then
                            lbl:SetTextColor(acR, acG, acB, 1)
                        else
                            lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                        end
                    end
                    UpdateLabelColor()
                    local arrow = row:CreateTexture(nil, "ARTWORK")
                    arrow:SetSize(10, 10)
                    arrow:SetPoint("RIGHT", row, "RIGHT", -8, 0)
                    arrow:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\right-arrow.png")
                    arrow:SetAlpha(0.7)
                    local hl = row:CreateTexture(nil, "ARTWORK")
                    hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0); hl:SetAlpha(0)

                    local panel
                    local function ShowPanel()
                        local hostPanel = host and host.panel
                        -- Nested rows only ever close a sibling inside their own panel, never the panel they live in.
                        local openSib
                        if hostPanel then openSib = hostPanel._openChild else openSib = menu._openSub end
                        if openSib and openSib ~= panel and openSib.Hide then openSib:Hide() end
                        if panel and panel:IsShown() then return end
                        if not panel then
                            panel = CreateFrame("Frame", nil, hostPanel or menu)
                            panel:SetFrameStrata("FULLSCREEN_DIALOG")
                            panel:SetFrameLevel((hostPanel or menu):GetFrameLevel() + (hostPanel and 3 or 5))
                            panel:SetClampedToScreen(true)
                            panel:EnableMouse(true)
                            local bg = panel:CreateTexture(nil, "BACKGROUND")
                            bg:SetAllPoints()
                            bg:SetColorTexture(mBgR, mBgG, mBgB, mBgA)
                        else
                            for _, ch in ipairs({panel:GetChildren()}) do ch:Hide(); ch:SetParent(nil) end
                        end
                        -- The border lives in a child frame, so it is rebuilt after every wipe (like the subnav flyouts do).
                        EllesmereUI.MakeBorder(panel, 1, 1, 1, mBrdA, EllesmereUI.PP)
                        panel._openChild = nil
                        panel:ClearAllPoints()
                        panel:SetPoint("TOPLEFT", row, "TOPRIGHT", 2, 0)

                        local pInner = CreateFrame("Frame", nil, panel)
                        pInner:SetPoint("TOPLEFT")
                        local y, labels = 4, {}
                        local function hostFor()
                            return { parent = pInner, panel = panel, y = y, level = panel:GetFrameLevel() + 2 }
                        end
                        local add = {}
                        add.Subnav = function(lab, items, getVal, setVal, isDef, onCreated, o)
                            local o2 = {}
                            if o then for k, v in pairs(o) do o2[k] = v end end
                            o2.host = hostFor()
                            MakeSubnavRow(lab, items, getVal, setVal, isDef, onCreated, o2)
                            labels[#labels + 1] = EllesmereUI.L(lab)
                            y = y + ITEM_H
                        end
                        add.Panel = function(lab, pop, isDef)
                            AB.MakePanelRow(lab, pop, isDef, hostFor())
                            labels[#labels + 1] = EllesmereUI.L(lab)
                            y = y + ITEM_H
                        end
                        populate(add)
                        -- Measure the captions on a hidden FontString (FitMenuWidth wants FontStrings, not text).
                        local meas = panel._meas
                        if not meas then
                            meas = panel:CreateFontString(nil, "OVERLAY")
                            meas:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                            meas:Hide()
                            panel._meas = meas
                        end
                        local widest = 0
                        for i = 1, #labels do
                            meas:SetText(labels[i])
                            local tw = meas:GetStringWidth() or 0
                            if tw > widest then widest = tw end
                        end
                        local w = math.min(340, math.max(180, math.ceil(widest + 48)))
                        panel:SetSize(w, y + 4)
                        pInner:SetSize(w, y + 4)
                        panel:Show()
                        if hostPanel then hostPanel._openChild = panel else menu._openSub = panel end
                    end

                    row:SetScript("OnEnter", function()
                        lbl:SetTextColor(1, 1, 1, 1)
                        hl:SetColorTexture(1, 1, 1, hlA); hl:SetAlpha(1)
                        ShowPanel()
                    end)
                    row:SetScript("OnLeave", function()
                        UpdateLabelColor()
                        hl:SetAlpha(0)
                    end)
                    if not host then mH = mH + ITEM_H end
                    return row
                end

                -- "Threshold Text" per-spell subnav, shared by the buff, cd/util
                -- and preset/custom branches. Threshold Seconds arms the feature for the
                -- spell (0 = off = zero cost); Threshold Color and Threshold Decimals are
                -- independent toggles applied below that boundary (rendered by the engine
                -- countdown formatter -- ns.ApplyThresholdFormatter). acc bridges the
                -- branch's store (per-spell family entry or customActiveStates):
                --   get(key) effective read; set(key,v) own write (persists entry first);
                --   clear(key) own clear (tier-blocking where applicable); refresh() post-change gate flip + apply calls.
                local function AddThresholdTextRow(acc)
                    local function armedSeconds()
                        return tonumber(acc.get("thresholdSeconds")) or 0
                    end
                    local TT_ITEMS = {
                        { val = "seconds", label = "Threshold Seconds",
                          -- Scalar popup value (not a discrete flyout choice): the number lives
                          -- in the store, entered via a popup, and applyWrite pushes the spell's
                          -- current seconds live. The Apply-to-Bar strip must treat it as "always
                          -- push my value", never a discrete value item -- otherwise the rejoin shortcut discards the entered number and the suppress-strip rule hides the strip whenever the bar's number differs (see scalarApply guards below).
                          scalarApply = true,
                          dynamicLabel = function()
                              local base = EllesmereUI.L("Threshold Seconds")
                              local s = armedSeconds()
                              if s > 0 then return base .. " (" .. s .. "s)" end
                              return base
                          end,
                          tooltip = "Seconds remaining below which Threshold Color and Threshold Decimals apply (0 = off).",
                          toggleGet = function() return armedSeconds() > 0 end,
                          applyKeys = { "thresholdSeconds" },
                          applyWrite = function(t)
                              -- Push this spell's current seconds; "off" applied bar-wide blocks the tier below.
                              local s = armedSeconds()
                              t.thresholdSeconds = (s > 0) and s or false
                          end },
                        { val = "color", label = "Threshold Color",
                          tooltip = "Recolor the countdown text below Threshold Seconds.",
                          toggleGet = function() return acc.get("thresholdColorEnabled") == true end,
                          toggleSet = function(v)
                              if v then
                                  acc.set("thresholdColorEnabled", true)
                                  if not acc.get("thresholdColorR") then
                                      acc.set("thresholdColorR", 1)
                                      acc.set("thresholdColorG", 0.2)
                                      acc.set("thresholdColorB", 0.2)
                                  end
                              else
                                  acc.clear("thresholdColorEnabled")
                              end
                              acc.refresh()
                          end,
                          applyKeys = { "thresholdColorEnabled", "thresholdColorR",
                                        "thresholdColorG", "thresholdColorB" },
                          applyWrite = function(t, v)
                              t.thresholdColorEnabled = v or false
                              if v then
                                  -- Push this spell's current color.
                                  t.thresholdColorR = acc.get("thresholdColorR") or 1
                                  t.thresholdColorG = acc.get("thresholdColorG") or 0.2
                                  t.thresholdColorB = acc.get("thresholdColorB") or 0.2
                              else
                                  -- Colour keys belong to the enabled state only; clear them so a stale colour can't linger in the tier and make valuesMatch always fail.
                                  t.thresholdColorR = nil
                                  t.thresholdColorG = nil
                                  t.thresholdColorB = nil
                              end
                          end },
                        { val = "decimals", label = "Threshold Decimals",
                          tooltip = "Show a 1-decimal countdown (2.7) below Threshold Seconds.",
                          toggleGet = function() return acc.get("thresholdDecimals") == true end,
                          toggleSet = function(v)
                              if v then acc.set("thresholdDecimals", true)
                              else acc.clear("thresholdDecimals") end
                              acc.refresh()
                          end,
                          applyKeys = { "thresholdDecimals" },
                          applyWrite = function(t, v)
                              t.thresholdDecimals = v or false
                          end },
                    }
                    return MakeSubnavRow("Threshold Text", TT_ITEMS,
                        function() return nil end,
                        function() end,
                        function()
                            return armedSeconds() == 0
                                and acc.get("thresholdColorEnabled") ~= true
                                and acc.get("thresholdDecimals") ~= true
                        end,
                        function(si, item, sub)
                            if item.val == "seconds" then
                                -- Popup flow (mirrors Lower Alpha): close the menu so only the popup shows; 0 disarms.
                                si:SetScript("OnClick", function()
                                    local cur = armedSeconds()
                                    menu:Hide()
                                    ShowThresholdSecondsPopup(cur > 0 and cur or nil, function(v)
                                        if v and v > 0 then
                                            acc.set("thresholdSeconds", v)
                                        else
                                            acc.clear("thresholdSeconds")
                                        end
                                        acc.refresh()
                                    end)
                                end)
                            elseif item.val == "color" then
                                -- Inline color swatch (same shape as the Active State swipe swatch): picking a color also enables the toggle.
                                si._noCapture = true
                                local swatchBtn = EllesmereUI.BuildColorSwatch(si, si:GetFrameLevel() + 3,
                                    function()
                                        return acc.get("thresholdColorR") or 1,
                                            acc.get("thresholdColorG") or 0.2,
                                            acc.get("thresholdColorB") or 0.2, 1
                                    end,
                                    function(r, g, b)
                                        acc.set("thresholdColorR", r)
                                        acc.set("thresholdColorG", g)
                                        acc.set("thresholdColorB", b)
                                        acc.refresh()
                                    end, false, 14)
                                swatchBtn:SetPoint("RIGHT", si, "RIGHT", -8, 0)
                                swatchBtn:HookScript("PreClick", function()
                                    acc.set("thresholdColorEnabled", true)
                                    if not acc.get("thresholdColorR") then
                                        acc.set("thresholdColorR", 1)
                                        acc.set("thresholdColorG", 0.2)
                                        acc.set("thresholdColorB", 0.2)
                                    end
                                    -- Keep the dropdown AND flyout open (OnUpdate cpOpen guard); re-highlight the now-on toggle.
                                    if sub._refreshSelection then sub._refreshSelection() end
                                    acc.refresh()
                                end)
                            end
                        end)
                end

                -- A HOSTED buff (buff placed on a CD/util bar) is a real Blizzard buff frame
                -- reparented onto the bar, so it takes the BUFF per-icon menu, not the CD/util
                -- one (same settings as on a buffs bar); isHostedBuff is resolved above
                -- (slot-based). Hosted buffs are removed from Apply-to-Bar entirely (no strip, no bar-tier chaining in ResolveSpellSettings).
                hostedBuffNoApply = isHostedBuff
                if isBuffBar or isHostedBuff then
                    -- Injected custom/preset buffs (cast-timer driven, identified by a stored
                    -- spellDuration) are show-on-cast only, so the Always Show Buffs/Desaturate Inactive overrides (which act on Blizzard-tracked inactive placeholders) don't apply to them.
                    local isInjectedCustom = (sd.spellDurations and (sd.spellDurations[spellID] or 0) > 0)
                        or (sd.customSpellIDs and sd.customSpellIDs[spellID]) or false

                    -- Visibility When Missing (HOSTED buffs only): nil = desaturated
                    -- placeholder; "hidden" keeps the reserved slot but renders nothing;
                    -- "hiddenShift" skips the placeholder so later icons close the gap (same
                    -- outcome as Hidden on CD (Shift Icons)). Purely per-spell: no apply opts, hosted rows never get the Apply-to-Bar strip anyway (entries chain to no tier).
                    if isHostedBuff then
                        local MISSING_VIS_ITEMS = {
                            { val = nil,           label = "Desaturated" },
                            { val = "hidden",      label = "Hidden" },
                            { val = "hiddenShift", label = "Hidden (Shift Icons)" },
                        }
                        MakeSubnavRow("Visibility When Missing", MISSING_VIS_ITEMS,
                            function() return ss.hostedMissingVis end,
                            function(v)
                                EnsureSS(); SetOwn("hostedMissingVis", v)
                                -- Re-collect so the placeholder is re-injected, skipped, or re-marked immediately.
                                if ns.QueueReanchor then ns.QueueReanchor() end
                            end,
                            function() return ss.hostedMissingVis == nil end)
                    end

                    -- BUFF BAR per-icon menu. "Buff Glow" reuses the glow-style picker but is
                    -- driven by the while-shown buff-glow path (not proc). nil = inherit the bar's Buff Glow; 0 = None (force the glow off on this one icon).
                    local BUFF_GLOW_ITEMS = {
                        { val = nil, label = "Default" },
                        { val = 0,   label = "None" },
                        { val = 1,   label = "Pixel Glow" },
                        { val = 3,   label = "Action Button Glow" },
                        { val = 4,   label = "Auto-Cast Shine" },
                        { val = 2,   label = "Shape Glow" },
                        { val = 5,   label = "GCD" },
                        { val = 6,   label = "Modern WoW Glow" },
                        { val = 7,   label = "Classic WoW Glow" },
                    }
                    MakeSubnavRow("Buff Glow", BUFF_GLOW_ITEMS,
                        function() return ss.buffGlow end,
                        function(v) EnsureSS(); SetOwn("buffGlow", v) end,
                        function() return ss.buffGlow == nil end,
                        nil,
                        { apply = { keys = { "buffGlow" },
                                    write = function(t, v) t.buffGlow = v end } })

                    local BUFF_GLOW_COLOR_ITEMS = {
                        { val = nil,      label = "Default" },
                        { val = "class",  label = "Class Color" },
                        { val = "custom", label = "Custom" },
                    }
                    MakeSubnavRow("Glow Effect Color", BUFF_GLOW_COLOR_ITEMS,
                        function() return ss.buffGlowColor end,
                        function(v)
                            EnsureSS()
                            SetOwn("buffGlowColor", v)
                            if v == "custom" and not ss.buffGlowColorR then
                                ss.buffGlowColorR = 1; ss.buffGlowColorG = 0.776; ss.buffGlowColorB = 0.376
                            end
                        end,
                        function() return ss.buffGlowColor == nil end,
                        function(si, item, sub)
                            if item.val == "custom" then
                                si._noCapture = true
                                local swatchBtn = EllesmereUI.BuildColorSwatch(si, si:GetFrameLevel() + 3,
                                    function() return ss.buffGlowColorR or 1, ss.buffGlowColorG or 0.776, ss.buffGlowColorB or 0.376, 1 end,
                                    function(r, g, b)
                                        ss.buffGlowColorR = r; ss.buffGlowColorG = g; ss.buffGlowColorB = b
                                        if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                                    end, false, 14)
                                swatchBtn:SetPoint("RIGHT", si, "RIGHT", -8, 0)
                                swatchBtn:HookScript("PreClick", function()
                                    EnsureSS()
                                    ss.buffGlowColor = "custom"
                                    if not ss.buffGlowColorR then
                                        ss.buffGlowColorR = 1; ss.buffGlowColorG = 0.776; ss.buffGlowColorB = 0.376
                                    end
                                    -- Keep the dropdown AND flyout open (the OnUpdate cpOpen guard
                                    -- holds them while the picker is up); just re-highlight the now-selected Custom row.
                                    if sub._refreshSelection then sub._refreshSelection() end
                                end)
                            end
                        end,
                        { apply = { keys = { "buffGlowColor", "buffGlowColorR", "buffGlowColorG", "buffGlowColorB" },
                                    write = function(t, v)
                                        t.buffGlowColor = v
                                        if v == "custom" then
                                            t.buffGlowColorR = ss.buffGlowColorR or 1
                                            t.buffGlowColorG = ss.buffGlowColorG or 0.776
                                            t.buffGlowColorB = ss.buffGlowColorB or 0.376
                                        else
                                            t.buffGlowColorR = nil
                                            t.buffGlowColorG = nil
                                            t.buffGlowColorB = nil
                                        end
                                    end } })

                    -- Cooldown Swipe (buffs only): tints the aura-duration swipe. Default =
                    -- the bar's swipe colour; Class/Custom mirror Glow Effect Color; None fully hides the swipe (alpha 0). Applied on the buff frame by the SetSwipeColor hook (which reads these keys).
                    local CD_SWIPE_COLOR_ITEMS = {
                        { val = nil,      label = "Default" },
                        { val = "class",  label = "Class Color" },
                        { val = "custom", label = "Custom" },
                        { val = "none",   label = "None" },
                    }
                    MakeSubnavRow("Cooldown Swipe", CD_SWIPE_COLOR_ITEMS,
                        function() return ss.cdSwipeColor end,
                        function(v)
                            EnsureSS()
                            SetOwn("cdSwipeColor", v)
                            if v == "custom" and not ss.cdSwipeColorR then
                                ss.cdSwipeColorR = 1; ss.cdSwipeColorG = 0.776; ss.cdSwipeColorB = 0.376
                            end
                            if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                        end,
                        function() return ss.cdSwipeColor == nil end,
                        function(si, item, sub)
                            if item.val == "custom" then
                                si._noCapture = true
                                local swatchBtn = EllesmereUI.BuildColorSwatch(si, si:GetFrameLevel() + 3,
                                    function() return ss.cdSwipeColorR or 1, ss.cdSwipeColorG or 0.776, ss.cdSwipeColorB or 0.376, 1 end,
                                    function(r, g, b)
                                        ss.cdSwipeColorR = r; ss.cdSwipeColorG = g; ss.cdSwipeColorB = b
                                        if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                                    end, false, 14)
                                swatchBtn:SetPoint("RIGHT", si, "RIGHT", -8, 0)
                                swatchBtn:HookScript("PreClick", function()
                                    EnsureSS()
                                    ss.cdSwipeColor = "custom"
                                    if not ss.cdSwipeColorR then
                                        ss.cdSwipeColorR = 1; ss.cdSwipeColorG = 0.776; ss.cdSwipeColorB = 0.376
                                    end
                                    if sub._refreshSelection then sub._refreshSelection() end
                                end)
                            end
                        end,
                        { apply = { keys = { "cdSwipeColor", "cdSwipeColorR", "cdSwipeColorG", "cdSwipeColorB" },
                                    write = function(t, v)
                                        t.cdSwipeColor = v
                                        if v == "custom" then
                                            t.cdSwipeColorR = ss.cdSwipeColorR or 1
                                            t.cdSwipeColorG = ss.cdSwipeColorG or 0.776
                                            t.cdSwipeColorB = ss.cdSwipeColorB or 0.376
                                        else
                                            t.cdSwipeColorR = nil
                                            t.cdSwipeColorG = nil
                                            t.cdSwipeColorB = nil
                                        end
                                    end } })

                    -- Duration Text + Charge/Stack Size: each row opens a cog popup mirroring
                    -- the bar's control. Per-icon values override the bar; untouched fields inherit (get falls back to bar).
                    local cdmBd = ns.barDataByKey and ns.barDataByKey[barKey]
                    -- Accent cue helpers: "changed" = override set AND its EFFECTIVE value
                    -- differs from the bar's, so an override matching the bar (or a bar edit
                    -- catching up) shows no accent. valChanged for scalars/toggles; colChanged for an RGB triple (nil components fall back to the bar's).
                    local function valChanged(sv, bv)
                        return sv ~= nil and sv ~= bv
                    end
                    local function colChanged(sr, sg, sb, br, bg, bb)
                        if sr == nil and sg == nil and sb == nil then return false end
                        return (sr or br) ~= br or (sg or bg) ~= bg or (sb or bb) ~= bb
                    end
                    -- isChanged: a function returning true when this cog's per-icon values
                    -- DIFFER from the bar; the row label then rests at accent instead of dim (same "this is customized" cue as tri-state rows).
                    local function MakeCogRow(label, isChanged, buildCog)
                        local row = CreateFrame("Button", nil, inner)
                        row:SetHeight(ITEM_H)
                        row:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
                        row:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
                        row:SetFrameLevel(menu:GetFrameLevel() + 2)
                        local lbl = row:CreateFontString(nil, "OVERLAY")
                        lbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                        lbl:SetPoint("LEFT", 10, 0); lbl:SetJustifyH("LEFT"); lbl:SetText(EllesmereUI.L(label))
                        -- Resting label color: accent when this cog's values differ from the bar, dim when they all match/inherit it.
                        local function UpdateLabel()
                            if isChanged() then
                                local aR, aG, aB = EllesmereUI.GetAccentColor()
                                lbl:SetTextColor(aR, aG, aB, 1)
                            else
                                lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                            end
                        end
                        row._updateLabel = UpdateLabel
                        UpdateLabel()
                        local arrow = row:CreateTexture(nil, "ARTWORK")
                        arrow:SetSize(10, 10); arrow:SetPoint("RIGHT", row, "RIGHT", -8, 0)
                        arrow:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\right-arrow.png")
                        arrow:SetAlpha(0.7)
                        local hl = row:CreateTexture(nil, "ARTWORK")
                        hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0); hl:SetAlpha(0)
                        -- Show on hover, anchored to the side, like the other subnav flyouts.
                        -- Reuse BuildCogPopup but drop its slide animation + click-outside dismiss so the menu's _openSub machinery (hover-to-switch, close-with-menu) controls it.
                        local showFn, pf
                        local function ShowCog()
                            if not showFn then _, showFn = buildCog(row) end
                            if not pf then
                                showFn(row)            -- first call creates + shows it
                                pf = showFn._popupFrame
                            else
                                if pf._refresh then pf._refresh() end
                                pf:Show()
                            end
                            if pf then
                                pf:SetScript("OnUpdate", nil)
                                pf:SetAlpha(1)
                                pf:ClearAllPoints()
                                pf:SetPoint("TOPLEFT", row, "TOPRIGHT", 2, 0)
                            end
                        end
                        row:SetScript("OnEnter", function()
                            lbl:SetTextColor(1, 1, 1, 1); hl:SetColorTexture(1, 1, 1, hlA); hl:SetAlpha(1)
                            if menu._openSub and menu._openSub ~= pf and menu._openSub.Hide then menu._openSub:Hide() end
                            ShowCog()
                            menu._openSub = pf
                        end)
                        row:SetScript("OnLeave", function()
                            UpdateLabel(); hl:SetAlpha(0)
                        end)
                        mH = mH + ITEM_H
                        return row
                    end

                    MakeCogRow("Duration Text", function()
                        local b = cdmBd
                        return valChanged(ss.showCooldownText, (b and b.showCooldownText) ~= false)
                            or valChanged(ss.cooldownFontSize, (b and b.cooldownFontSize) or 12)
                            or colChanged(ss.cooldownTextR, ss.cooldownTextG, ss.cooldownTextB,
                                (b and b.cooldownTextR) or 1, (b and b.cooldownTextG) or 1, (b and b.cooldownTextB) or 1)
                            or valChanged(ss.cooldownTextPosition, (b and b.cooldownTextPosition) or "center")
                            or valChanged(ss.cooldownTextX, (b and b.cooldownTextX) or 0)
                            or valChanged(ss.cooldownTextY, (b and b.cooldownTextY) or 0)
                    end, function(row)
                        return EllesmereUI.BuildCogPopup({
                            -- Level 350: above the spell-picker menu (300) but below the shared
                            -- color picker (FULLSCREEN_DIALOG 400) so the picker renders on top. The dropdown menu is bumped above the popup in BuildCogPopup's dropdown OnClick hook.
                            title = "Duration Text", noOwnerDim = true,
                            frameStrata = "FULLSCREEN_DIALOG", frameLevel = 350,
                            rows = {
                                { type="toggle", label="Show Duration",
                                  get=function() if ss.showCooldownText ~= nil then return ss.showCooldownText end return (cdmBd and cdmBd.showCooldownText) ~= false end,
                                  set=function(v) EnsureSS(); ss.showCooldownText = v; ns._cdmAnySpellDurationText = true; if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end if row._updateLabel then row._updateLabel() end end },
                                { type="slider", label="Size", min=6, max=30, step=1,
                                  get=function() return ss.cooldownFontSize or (cdmBd and cdmBd.cooldownFontSize) or 12 end,
                                  set=function(v) EnsureSS(); ss.cooldownFontSize = v; if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end if row._updateLabel then row._updateLabel() end end },
                                { type="colorpicker", label="Color",
                                  get=function() return ss.cooldownTextR or (cdmBd and cdmBd.cooldownTextR) or 1, ss.cooldownTextG or (cdmBd and cdmBd.cooldownTextG) or 1, ss.cooldownTextB or (cdmBd and cdmBd.cooldownTextB) or 1 end,
                                  set=function(r, g, b) EnsureSS(); ss.cooldownTextR = r; ss.cooldownTextG = g; ss.cooldownTextB = b; if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end if row._updateLabel then row._updateLabel() end end },
                                { type="dropdown", label="Position",
                                  values=durationPositionValues, order=durationPositionOrder,
                                  get=function() return ss.cooldownTextPosition or (cdmBd and cdmBd.cooldownTextPosition) or "center" end,
                                  set=function(v) EnsureSS(); ss.cooldownTextPosition = v; if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end if row._updateLabel then row._updateLabel() end end },
                                { type="slider", label="X Offset", min=-50, max=50, step=1,
                                  get=function() return ss.cooldownTextX or (cdmBd and cdmBd.cooldownTextX) or 0 end,
                                  set=function(v) EnsureSS(); ss.cooldownTextX = v; if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end if row._updateLabel then row._updateLabel() end end },
                                { type="slider", label="Y Offset", min=-50, max=50, step=1,
                                  get=function() return ss.cooldownTextY or (cdmBd and cdmBd.cooldownTextY) or 0 end,
                                  set=function(v) EnsureSS(); ss.cooldownTextY = v; if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end if row._updateLabel then row._updateLabel() end end },
                            },
                        })
                    end)

                    MakeCogRow("Stack Text and Glows", function()
                        local b = cdmBd
                        return valChanged(ss.showChargeStackText, (b and b.showChargeStackText) ~= false)
                            or ss.buffGlowStackEnabled == true
                            or valChanged(ss.stackCountSize, (b and b.stackCountSize) or 11)
                            or colChanged(ss.stackCountR, ss.stackCountG, ss.stackCountB,
                                (b and b.stackCountR) or 1, (b and b.stackCountG) or 1, (b and b.stackCountB) or 1)
                            or valChanged(ss.stackCountPosition, (b and b.stackCountPosition) or "bottomright")
                            or valChanged(ss.stackCountX, (b and b.stackCountX) or 0)
                            or valChanged(ss.stackCountY, (b and b.stackCountY) or 0)
                    end, function(row)
                        return EllesmereUI.BuildCogPopup({
                            title = "Stack Text and Glows", noOwnerDim = true,
                            frameStrata = "FULLSCREEN_DIALOG", frameLevel = 350,
                            rows = {
                                { type="toggle", label="Glow at Stacks",
                                  tooltip="Replaces Buff Glow: the icon glows when its stack count matches the comparison below, using this spell's Buff Glow style (Modern WoW Glow if none is set).",
                                  get=function() return ss.buffGlowStackEnabled == true end,
                                  set=function(v) EnsureSS(); ss.buffGlowStackEnabled = v or nil; if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end if row._updateLabel then row._updateLabel() end end },
                                { type="dropdown", label="Comparison",
                                  values={ lt="Below (<)", lte="At Most (<=)", eq="Exactly (=)", gte="At Least (>=)", gt="Above (>)" },
                                  order={ "lt", "lte", "eq", "gte", "gt" },
                                  disabled=function() return not ss.buffGlowStackEnabled end,
                                  disabledTooltip="Enable Glow at Stacks",
                                  get=function() return ss.buffGlowStackOperator or "gte" end,
                                  set=function(v)
                                      EnsureSS(); ss.buffGlowStackOperator = v ~= "gte" and v or nil
                                      if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                                      if row._updateLabel then row._updateLabel() end
                                  end },
                                { type="input", label="Stack Count", inputWidth=42, commitOnBlur=true,
                                  disabled=function() return not ss.buffGlowStackEnabled end,
                                  disabledTooltip="Enable Glow at Stacks",
                                  get=function() return tostring(tonumber(ss.buffGlowStackThreshold) or 2) end,
                                  set=function(v)
                                      local t = math.floor(tonumber(v) or 0)
                                      if t < 1 then t = 1 end
                                      if t > 99 then t = 99 end
                                      EnsureSS(); ss.buffGlowStackThreshold = t
                                      if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                                      if row._updateLabel then row._updateLabel() end
                                  end },
                                { type="toggle", label="Show Stack Text",
                                  get=function() if ss.showChargeStackText ~= nil then return ss.showChargeStackText end return (cdmBd and cdmBd.showChargeStackText) ~= false end,
                                  set=function(v) EnsureSS(); ss.showChargeStackText = v; if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end if row._updateLabel then row._updateLabel() end end },
                                { type="slider", label="Size", min=6, max=30, step=1,
                                  get=function() return ss.stackCountSize or (cdmBd and cdmBd.stackCountSize) or 11 end,
                                  set=function(v) EnsureSS(); ss.stackCountSize = v; if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end if row._updateLabel then row._updateLabel() end end },
                                { type="colorpicker", label="Color",
                                  get=function() return ss.stackCountR or (cdmBd and cdmBd.stackCountR) or 1, ss.stackCountG or (cdmBd and cdmBd.stackCountG) or 1, ss.stackCountB or (cdmBd and cdmBd.stackCountB) or 1 end,
                                  set=function(r, g, b) EnsureSS(); ss.stackCountR = r; ss.stackCountG = g; ss.stackCountB = b; if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end if row._updateLabel then row._updateLabel() end end },
                                { type="dropdown", label="Position",
                                  values={ bottomright="Bottom Right", bottom="Bottom", bottomleft="Bottom Left", left="Left", topleft="Top Left", top="Top", topright="Top Right", right="Right", center="Center" },
                                  order={ "bottomright", "bottom", "bottomleft", "left", "topleft", "top", "topright", "right", "center" },
                                  get=function() return ss.stackCountPosition or (cdmBd and cdmBd.stackCountPosition) or "bottomright" end,
                                  set=function(v) EnsureSS(); ss.stackCountPosition = v; if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end if row._updateLabel then row._updateLabel() end end },
                                { type="slider", label="X Offset", min=-150, max=150, step=1,
                                  get=function() return ss.stackCountX or (cdmBd and cdmBd.stackCountX) or 0 end,
                                  set=function(v) EnsureSS(); ss.stackCountX = v; if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end if row._updateLabel then row._updateLabel() end end },
                                { type="slider", label="Y Offset", min=-150, max=150, step=1,
                                  get=function() return ss.stackCountY or (cdmBd and cdmBd.stackCountY) or 0 end,
                                  set=function(v) EnsureSS(); ss.stackCountY = v; if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end if row._updateLabel then row._updateLabel() end end },
                            },
                        })
                    end)

                    -- Border: per-icon override of the bar's border SIZE + COLOR (never style).
                    -- Mirrors the Charges/Stacks cog exactly; the render side reads (ssb and ssb.border*) or the bar value in ApplyShapeToCDMIcon.
                    MakeCogRow("Border", function()
                        local b = cdmBd
                        return valChanged(ss.borderSize, (b and b.borderSize) or 1)
                            or colChanged(ss.borderR, ss.borderG, ss.borderB,
                                (b and b.borderR) or 0, (b and b.borderG) or 0, (b and b.borderB) or 0)
                    end, function(row)
                        return EllesmereUI.BuildCogPopup({
                            title = "Border", noOwnerDim = true,
                            frameStrata = "FULLSCREEN_DIALOG", frameLevel = 350,
                            rows = {
                                { type="slider", label="Size", min=0, max=8, step=1,
                                  get=function() return ss.borderSize or (cdmBd and cdmBd.borderSize) or 1 end,
                                  set=function(v) EnsureSS(); ss.borderSize = v; if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end if row._updateLabel then row._updateLabel() end end },
                                { type="colorpicker", label="Color",
                                  get=function() return ss.borderR or (cdmBd and cdmBd.borderR) or 0, ss.borderG or (cdmBd and cdmBd.borderG) or 0, ss.borderB or (cdmBd and cdmBd.borderB) or 0 end,
                                  set=function(r, g, b) EnsureSS(); ss.borderR = r; ss.borderG = g; ss.borderB = b; if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end if row._updateLabel then row._updateLabel() end end },
                            },
                        })
                    end)

                    -- Audio on Buff Gain/Loss sound list + speaker-preview decorator. Defined
                    -- once here so the Blizzard-tracked-buff rows AND the self-timed preset/custom
                    -- gain row share the same list + preview (entries mirror the Focus Cast Sound dropdown via the shared ns.FOCUSKICK_SOUND_* tables).
                    local AUDIO_ITEMS = {}
                    for _, key in ipairs(ns.FOCUSKICK_SOUND_ORDER or { "none" }) do
                        if type(key) == "string" and key:sub(1, 3) == "---" then
                            -- Separator inserted by AppendSharedMediaSounds between built-in and
                            -- appended LibSharedMedia sounds. Render as a divider line, not a sound entry.
                            AUDIO_ITEMS[#AUDIO_ITEMS + 1] = { divider = true }
                        else
                            AUDIO_ITEMS[#AUDIO_ITEMS + 1] = {
                                val   = key,
                                label = (ns.FOCUSKICK_SOUND_NAMES and ns.FOCUSKICK_SOUND_NAMES[key]) or key,
                            }
                        end
                    end
                    -- Speaker-preview decorator: plays a row's focused sound without selecting it (mirrors the dropdown's preview icon).
                    local function AddSoundPreview(si, item)
                        if item.val and item.val ~= "none" then
                            local play = CreateFrame("Button", nil, si)
                            play:SetSize(16, 16)
                            play:SetPoint("RIGHT", si, "RIGHT", -8, 0)
                            play:SetFrameLevel(si:GetFrameLevel() + 2)
                            play:SetNormalAtlas(EllesmereUI.SOUND_ICON_ATLAS)
                            play:SetPushedAtlas(EllesmereUI.SOUND_ICON_PRESSED_ATLAS)
                            play:SetScript("OnClick", function()
                                local paths = ns.FOCUSKICK_SOUND_PATHS
                                local path = paths and paths[item.val]
                                if path then PlaySoundFile(path, "Master") end
                            end)
                            play:SetScript("OnEnter", function()
                                EllesmereUI.ShowWidgetTooltip(play, "Preview Sound")
                            end)
                            play:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                        end
                    end
                    -- "Audio on Buff Gain": stored per-icon as ss.buffActiveSoundKey ("none"/nil
                    -- = silent). Blizzard-tracked buffs fire it via the apply-edge hook
                    -- (EnsureBuffSoundHook -> TriggerAuraAppliedAlert); self-timed preset/custom buffs fire it from the cast-timer gain edge in UpdateCustomBuffBars (CdmHooks) off the SAME stored key.
                    local function AddBuffGainRow()
                        MakeSubnavRow("Audio on Buff Gain", AUDIO_ITEMS,
                            function() return ss.buffActiveSoundKey or "none" end,
                            function(v)
                                EnsureSS()
                                SetOwn("buffActiveSoundKey", (v ~= "none" and v) or nil)
                                -- Flip the 0-cost gate live so the edge hook/cast timer starts playing on the next activation.
                                if ss.buffActiveSoundKey then ns._cdmAnyBuffSound = true end
                            end,
                            function() return ss.buffActiveSoundKey == nil end,
                            AddSoundPreview,
                            { searchable = true,
                              apply = { keys = { "buffActiveSoundKey" },
                                        write = function(t, v)
                                            -- "None" applied bar-wide = explicitly silent (false blocks the tier below).
                                            t.buffActiveSoundKey = (v ~= "none" and v) or false
                                        end } })
                    end
                    -- "Audio on Buff Loss": stored per-icon as ss.buffLostSoundKey.
                    local function AddBuffLossRow()
                        MakeSubnavRow("Audio on Buff Loss", AUDIO_ITEMS,
                            function() return ss.buffLostSoundKey or "none" end,
                            function(v)
                                EnsureSS()
                                SetOwn("buffLostSoundKey", (v ~= "none" and v) or nil)
                                if ss.buffLostSoundKey then ns._cdmAnyBuffSound = true end
                            end,
                            function() return ss.buffLostSoundKey == nil end,
                            AddSoundPreview,
                            { searchable = true,
                              apply = { keys = { "buffLostSoundKey" },
                                        write = function(t, v)
                                            t.buffLostSoundKey = (v ~= "none" and v) or false
                                        end } })
                    end

                    -- Always Show Buffs + Desaturate Inactive apply only to Blizzard-tracked
                    -- buffs (inactive placeholders); injected custom/preset buffs skip them and get only the gain row.
                    if not isInjectedCustom then
                        -- Hosted buffs (on a CD/util bar) OMIT these two bar-toggle overrides:
                        -- always-show and desaturate-inactive are baked in (a cd/util bar has no such bar toggle to override). Audio rows below still apply, so they stay outside this guard.
                        if not isHostedBuff then
                        -- Always Show Buffs: per-icon tri-state override of the bar toggle.
                        -- Default = inherit bar; Show = force the inactive placeholder on; Hide = force it off. A reanchor (queued by the row's setVal) creates/removes the placeholder.
                        local ALWAYS_SHOW_ITEMS = {
                            { val = nil,   label = "Default" },
                            { val = "on",  label = "Show" },
                            { val = "off", label = "Hide" },
                            -- Inverse reminder mode: placeholder renders while the
                            -- buff is MISSING, and the ACTIVE buff renders hidden
                            -- (layout gap closes).
                            { val = "missing", label = "Show When Missing" },
                        }
                        MakeSubnavRow("Always Show Buff", ALWAYS_SHOW_ITEMS,
                            function() return ss.alwaysShow end,
                            function(v)
                                EnsureSS(); SetOwn("alwaysShow", v)
                                -- Refresh the page so "Keep Buffs in Same Place" grays/ungrays as this per-icon override flips.
                                EllesmereUI:RefreshPage()
                            end,
                            function() return ss.alwaysShow == nil end,
                            nil,
                            -- Mutually exclusive with the bar's "Keep Buffs in Same Place": that
                            -- mode reserves every buff's slot and ignores per-icon overrides, so
                            -- disable this row while it's on. Escape hatch: if THIS icon is the one
                            -- already forcing "on" (legacy both-enabled data), keep the row editable so the user can clear it, which re-enables Keep Buffs.
                            { disabled = function()
                                  local bd = ns.barDataByKey and ns.barDataByKey[barKey]
                                  return bd and bd.hidePlaceholderIcon == true
                                      and ss.alwaysShow ~= "on" or false
                              end,
                              disabledTooltip = "Disabled while Keep Buffs in Same Place is enabled",
                              apply = { keys = { "alwaysShow" },
                                        write = function(t, v) t.alwaysShow = v end } })

                        -- Desaturate Inactive: per-icon tri-state override of the bar's Always
                        -- Show Buffs "Desaturate Off CD" cog setting. Applies to this buff's inactive placeholder. Default = inherit bar.
                        local DESAT_ITEMS = {
                            { val = nil,   label = "Default" },
                            { val = "on",  label = "Desaturate" },
                            { val = "off", label = "Full Color" },
                        }
                        MakeSubnavRow("Desaturate Inactive", DESAT_ITEMS,
                            function() return ss.desatInactive end,
                            function(v) EnsureSS(); SetOwn("desatInactive", v) end,
                            function() return ss.desatInactive == nil end,
                            nil,
                            { apply = { keys = { "desatInactive" },
                                        write = function(t, v) t.desatInactive = v end } })
                        end  -- if not isHostedBuff (bar-toggle overrides omitted)

                        AddBuffGainRow()
                        AddBuffLossRow()
                    else
                        -- Self-timed preset/custom buffs: both edges driven off the displayed timer in UpdateCustomBuffBars (no real aura event).
                        AddBuffGainRow()
                        AddBuffLossRow()
                    end

                    -- Reverse Swipe (buffs/custom buffs/buff presets): reverses the buff's fill
                    -- direction. Default off. Same per-spell store (ss) + runtime apply + zero-cost gate as cd/utility spells; placed outside the injected split so it's offered for every buff type.
                    MakeSubnavRow("Reverse Swipe", REVERSE_SWIPE_ITEMS,
                        function() return ss.reverseSwipe and true or nil end,
                        function(v)
                            EnsureSS(); SetOwn("reverseSwipe", v or nil)
                            if v then ns._cdmAnyReverseSwipe = true end
                            if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                        end,
                        function() return ss.reverseSwipe == nil end,
                        nil,
                        { apply = { keys = { "reverseSwipe" },
                                    write = function(t, v)
                                        -- "Off" applied bar-wide blocks the tier below.
                                        t.reverseSwipe = v or false
                                    end } })

                    -- Threshold Text (every buff type): decimals/color change on the aura
                    -- countdown below the spell's Threshold Seconds. Same per-spell store (ss) +
                    -- engine countdown formatter as cd/utility spells; the engine evaluates it, so secret aura durations format fine.
                    do
                        local acc = {}
                        acc.get = function(k) return ss[k] end
                        acc.set = function(k, v) EnsureSS(); ss[k] = v end
                        acc.clear = function(k) EnsureSS(); SetOwn(k, nil) end
                        acc.refresh = function()
                            if (tonumber(ss.thresholdSeconds) or 0) > 0 then ns._cdmAnyThresholdText = true end
                            if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                            if ns.QueueReanchor then ns.QueueReanchor() end
                        end
                        AddThresholdTextRow(acc)
                    end
                else
                local isCustomInjected = spellID < 0
                    or (ns._myRacialsSet and ns._myRacialsSet[spellID])
                    or (sd.customSpellIDs and sd.customSpellIDs[spellID])

                if isCustomInjected then
                    -- Custom Active State for preset icons (trinkets/potions/racials/custom
                    -- spell IDs): these have no Blizzard active detection, so the only setting is
                    -- a user-defined active overlay (EllesmereUICdmFakeActive.lua) -- a timer plus
                    -- the standard Active Swipe/Active Glow/Glow Effect Color. It lives in a
                    -- PROFILE-level store keyed by the spell (ns.GetCustomActiveState), so it
                    -- travels with the spell across every bar and spec, not in this bar's per-spell settings. Trinket slots key by the EQUIPPED item, so each tracks separately (casKey).
                    local casKey = (ns.ResolveCustomActiveKey and ns.ResolveCustomActiveKey(spellID)) or spellID
                    local cas = ns.GetCustomActiveState and ns.GetCustomActiveState(casKey) or nil
                    -- Trinket slots: the menu DISPLAYS the effective view -- the equipped item's
                    -- own entry chained per-key over the slot's "Apply to Bar" stamp
                    -- (GetEffectiveCustomActiveState uses the same chain at render time) -- while
                    -- WRITES stay item-keyed (casKey), so each trinket still tracks separately.
                    -- casKey == spellID means no item is equipped (writes then target the slot entry itself); never chain an entry to itself.
                    local casSlot = nil
                    if ns.SlotIDFromKey(spellID) and casKey ~= spellID
                       and ns.GetCustomActiveState then
                        casSlot = ns.GetCustomActiveState(spellID)
                    end
                    -- Not-yet-persisted fresh view, persisted on first WRITE -- same contract as the family-store EnsureSS above.
                    if not cas then cas = {} end
                    if ns.ChainSettings then ns.ChainSettings(cas, casSlot) end
                    local function EnsureCAS()
                        local storeC = ns.GetCustomActiveStates and ns.GetCustomActiveStates()
                        if storeC and not storeC[casKey] then storeC[casKey] = cas end
                        return cas
                    end
                    -- Own-value writer for nil-off keys: writing nil would let a
                    -- slot-stamp value show through the chain; when that would
                    -- change the effective value, store explicit false instead
                    -- (render-equivalent to nil, but blocks the inheritance --
                    -- the per-trinket exclusion). Mirrors the family SetOwn.
                    local function SetCasOwn(key, v2)
                        local e = EnsureCAS()
                        e[key] = v2
                        if v2 == nil and e[key] ~= nil then
                            e[key] = false
                        end
                    end
                    local hasActive = (cas.duration or 0) > 0

                    -- (The divider above the per-icon settings is already drawn
                    -- before the buff/CD branch, so we don't add another here.)

                    -- Plain clickable action row (label + hover highlight).
                    local function MakeActionRow(text, onClick)
                        local row = CreateFrame("Button", nil, inner)
                        row:SetHeight(ITEM_H)
                        row:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
                        row:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
                        row:SetFrameLevel(menu:GetFrameLevel() + 2)
                        local lbl = row:CreateFontString(nil, "OVERLAY")
                        lbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                        lbl:SetPoint("LEFT", 10, 0); lbl:SetJustifyH("LEFT")
                        lbl:SetText(EllesmereUI.L(text))
                        lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                        local hl = row:CreateTexture(nil, "ARTWORK")
                        hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0); hl:SetAlpha(0)
                        row:SetScript("OnEnter", function()
                            lbl:SetTextColor(1, 1, 1, 1)
                            hl:SetColorTexture(1, 1, 1, hlA); hl:SetAlpha(1)
                            if menu._openSub and menu._openSub:IsShown() then menu._openSub:Hide() end
                        end)
                        row:SetScript("OnLeave", function()
                            lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA); hl:SetAlpha(0)
                        end)
                        row:SetScript("OnClick", onClick)
                        mH = mH + ITEM_H
                        return row
                    end

                    local GLOW_COLOR_ITEMS = {
                        { val = nil,      label = "Default" },
                        { val = "class",  label = "Class Color" },
                        { val = "custom", label = "Custom" },
                    }
                    local CA_SWIPE_ITEMS = {
                        { val = "custom", label = "Swipe Color" },
                        { val = "class",  label = "Swipe Class Colored" },
                        { val = "none",   label = "Hide Active State" },
                    }
                    local CD_STATE_ITEMS = {
                        { val = nil,               label = "None" },
                        -- Same logic as Hidden (On CD) with a customizable opacity.
                        { val = "lowerAlphaOnCD",  label = "Lower Alpha (On CD)",
                          dynamicLabel = function()
                              local base = EllesmereUI.L("Lower Alpha (On CD)")
                              if cas and cas.cdStateEffect == "lowerAlphaOnCD" then
                                  local pct = math.floor(((cas.cdStateLowerAlpha or 0.5) * 100) + 0.5)
                                  return pct .. "% " .. base
                              end
                              return base
                          end },
                        -- Shift variants: same hide as the plain modes below, but
                        -- the bar re-lays out so remaining icons close the gap.
                        { val = "hiddenOnCDShift",  label = "Hidden on CD (Shift Icons)" },
                        { val = "hiddenReadyShift", label = "Hidden CD Ready (Shift Icons)" },
                        { val = "hiddenUnusableShift", label = "Hidden Until Usable (Shift Icons)",
                          tooltip = "Only shown while usable and off cooldown, such as Overpower or Victory Rush after a proc. Low resources do not hide it." },
                        { val = "hiddenFormShift", label = "Hidden Outside Form/Stance (Shift Icons)",
                          tooltip = "Only shown in the form or stance the spell needs, even while it is on cooldown." },
                        { val = "hiddenOnCD",      label = "Hidden (On CD)" },
                        { val = "hiddenReady",     label = "Hidden (CD Ready)" },
                        { val = "hiddenUnusable",  label = "Hidden (Until Usable)",
                          tooltip = "Only shown while usable and off cooldown, such as Overpower or Victory Rush after a proc. Low resources do not hide it." },
                        { val = "hiddenForm",      label = "Hidden (Outside Form/Stance)",
                          tooltip = "Only shown in the form or stance the spell needs, even while it is on cooldown." },
                        { val = "pixelGlowReady",  label = "Glow (CD Ready)" },
                        { val = "glowOnCD",        label = "Glow (On CD)" },
                    }
                    local KEEP_COLORED_ITEMS = {
                        { val = nil,  label = "None" },
                        { val = true, label = "Keep Colored (On CD)" },
                    }
                    local RANGE_COLOR_ITEMS = {
                        { val = nil,  label = "Off" },
                        { val = true, label = "Color Out of Range" },
                    }

                    -- Right-aligned colour swatch on a subnav item.
                    -- Per-spell settings are outside Spec Overrides, so the swatch opts out of capture.
                    local function MakeColorSwatch(si, getR, getG, getB, onChanged)
                        si._noCapture = true
                        local sw = EllesmereUI.BuildColorSwatch(si, si:GetFrameLevel() + 3,
                            function() return getR(), getG(), getB(), 1 end,
                            function(r, g, b) onChanged(r, g, b) end, false, 14)
                        sw:SetPoint("RIGHT", si, "RIGHT", -8, 0)
                    end

                    -- Cooldown State Effect (always available for presets; driven by the live cooldown, independent of the active overlay).
                    MakeSubnavRow("Cooldown State Effect", CD_STATE_ITEMS,
                        function()
                            local v = cas.cdStateEffect
                            if v == false then v = nil end  -- blocked slot value = None
                            return CD_GLOW_EFFECT[v] or v
                        end,
                        function(v)
                            -- A stored button* value keeps its look when re-picked.
                            local old = cas.cdStateEffect
                            if CD_GLOW_EFFECT[v] and cas.cdStateGlowStyle == nil
                               and (old == "buttonGlowReady" or old == "buttonGlowReadyUsable") then
                                SetCasOwn("cdStateGlowStyle", 3)
                            end
                            SetCasOwn("cdStateEffect", v)
                            if ns.FakeActive_Rearm then ns.FakeActive_Rearm() end
                        end,
                        function() return not cas.cdStateEffect end,
                        function(si, item, sub)
                            -- Lower Alpha (On CD): prompt for the opacity percent,
                            -- then select the effect (mirrors the setVal above).
                            if item.val == "lowerAlphaOnCD" then
                                si:SetScript("OnClick", function()
                                    local cur = math.floor((((cas and cas.cdStateLowerAlpha) or 0.5) * 100) + 0.5)
                                    -- Close the per-spell dropdown so only the popup shows.
                                    menu:Hide()
                                    ShowAlphaPopup(cur, function(pct)
                                        local c = EnsureCAS()
                                        c.cdStateLowerAlpha = pct / 100
                                        c.cdStateEffect = "lowerAlphaOnCD"
                                        if ns.FakeActive_Rearm then ns.FakeActive_Rearm() end
                                    end)
                                end)
                            end
                        end,
                        { apply = { keys = { "cdStateEffect", "cdStateLowerAlpha", "cdStateGlowStyle", "cdStateGlowAlpha" },
                                    write = function(t, v)
                                        -- Glow style resolved for the APPLIED effect, as a direct
                                        -- pick would (see the regular-spell row); the current
                                        -- effect is read before t is written.
                                        local cur = cas and cas.cdStateEffect
                                        t.cdStateEffect = v or false
                                        local st
                                        if CD_GLOW_EFFECT[v] then
                                            local keepBtn = cur == "buttonGlowReady" or cur == "buttonGlowReadyUsable"
                                            st = ns.CdReadyGlowStyle(keepBtn and cur or v, cas)
                                        end
                                        t.cdStateGlowStyle = st
                                        t.cdStateGlowAlpha = (st == 8) and cas and cas.cdStateGlowAlpha or nil
                                        if v == "lowerAlphaOnCD" then
                                            -- Push this icon's current percent (no popup).
                                            t.cdStateLowerAlpha = (cas and cas.cdStateLowerAlpha) or 0.5
                                        else
                                            t.cdStateLowerAlpha = nil
                                        end
                                    end } })

                    -- Glow Style (preset/custom): mirror of the regular-spell row.
                    MakeSubnavRow("Glow Style", CD_READY_STYLE_ITEMS,
                        function() return ns.CdReadyGlowStyle(cas.cdStateEffect, cas) end,
                        function(v)
                            SetCasOwn("cdStateGlowStyle", v)
                            if ns.FakeActive_Rearm then ns.FakeActive_Rearm() end
                        end,
                        function() return cas.cdStateGlowStyle == nil end,
                        function(si, item, sub)
                            -- Blackout: clicking prompts for the opacity percent, then
                            -- selects this style (mirrors Lower Alpha's onClick above).
                            if item.val == 8 then
                                item.dynamicLabel = function()
                                    local base = EllesmereUI.L(ns.GLOW_STYLES[8].name)
                                    if ns.CdReadyGlowStyle(cas.cdStateEffect, cas) == 8 then
                                        local pct = math.floor(((cas.cdStateGlowAlpha or 1) * 100) + 0.5)
                                        return pct .. "% " .. base
                                    end
                                    return base
                                end
                                si:SetScript("OnClick", function()
                                    local cur = math.floor((((cas and cas.cdStateGlowAlpha) or 1) * 100) + 0.5)
                                    menu:Hide()
                                    ShowAlphaPopup(cur, function(pct)
                                        local c = EnsureCAS()
                                        c.cdStateGlowAlpha = pct / 100
                                        c.cdStateGlowStyle = 8
                                        if ns.FakeActive_Rearm then ns.FakeActive_Rearm() end
                                    end, EllesmereUI.L("Glow Opacity"), EllesmereUI.L("Blackout glow opacity (1-100%)"))
                                end)
                            end
                        end,
                        { disabled = function() return not CD_GLOW_EFFECT[cas.cdStateEffect] end,
                          apply = { keys = { "cdStateGlowStyle", "cdStateGlowAlpha" },
                                    write = function(t, v)
                                        t.cdStateGlowStyle = v
                                        t.cdStateGlowAlpha = (v == 8) and cas and cas.cdStateGlowAlpha or nil
                                    end } })

                    -- Cooldown Saturation (preset/custom): mirror of the regular-spell row.
                    -- These icons are greyed by the Fake-Active engine rather than by Blizzard, so the runtime reads this key in PresetKeepsColor instead of the SetDesaturated hook -- same setting, same key name.
                    MakeSubnavRow("Cooldown Saturation", KEEP_COLORED_ITEMS,
                        function()
                            local v = cas.noDesatOnCD
                            if v == false then v = nil end  -- blocked slot value = None
                            return v and true or nil
                        end,
                        function(v)
                            SetCasOwn("noDesatOnCD", v or nil)
                            if v then ns._cdmAnyNoDesatOnCD = true end
                            if ns.FakeActive_Rearm then ns.FakeActive_Rearm() end
                            if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                        end,
                        function() return not cas.noDesatOnCD end,
                        nil,
                        { apply = { keys = { "noDesatOnCD" },
                                    write = function(t, v) t.noDesatOnCD = v or false end } })

                    -- Threshold Text (preset/custom): decimals/color change on this icon's
                    -- countdowns (item/spell cooldown and the fake-active window) below its
                    -- Threshold Seconds. Stored in the profile customActiveStates so it travels with the spell; the Fake-Active engine and the appearance pass both read it.
                    do
                        local acc = {}
                        acc.get = function(k) return cas[k] end
                        acc.set = function(k, v) local e = EnsureCAS(); e[k] = v end
                        acc.clear = function(k)
                            -- Own clear; when a slot-stamp value would show
                            -- through the chain, store the blocking false.
                            cas[k] = nil
                            if cas[k] ~= nil then SetCasOwn(k, false) end
                        end
                        acc.refresh = function()
                            if (tonumber(cas.thresholdSeconds) or 0) > 0 then ns._cdmAnyThresholdText = true end
                            if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                            if ns.FakeActive_Rearm then ns.FakeActive_Rearm() end
                            if ns.QueueReanchor then ns.QueueReanchor() end
                        end
                        AddThresholdTextRow(acc)
                    end

                    -- Cooldown Swipe (preset/custom): Reverse Swipe flips this icon's swipe
                    -- direction; Hide CD Swipe removes it. Default off. Stored in the profile customActiveStates so it travels with the spell.
                    MakeSubnavRow("Cooldown Swipe", CD_SWIPE_ITEMS,
                        function()
                            if cas and cas.hideCDSwipe then return "hide" end
                            if cas and cas.reverseSwipe then return "reverse" end
                            return nil
                        end,
                        function(v)
                            SetCasOwn("reverseSwipe", (v == "reverse") or nil)
                            SetCasOwn("hideCDSwipe", (v == "hide") or nil)
                            if v == "reverse" then ns._cdmAnyReverseSwipe = true end
                            if v == "hide" then ns._cdmAnyHideCDSwipe = true end
                            if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                            if ns.FakeActive_Rearm then ns.FakeActive_Rearm() end
                        end,
                        function() return not (cas and (cas.reverseSwipe or cas.hideCDSwipe)) end,
                        nil,
                        { apply = { keys = { "reverseSwipe", "hideCDSwipe" },
                                    write = function(t, v)
                                        t.reverseSwipe = (v == "reverse") or false
                                        t.hideCDSwipe = (v == "hide") or false
                                    end } })

                    -- Out of Range Coloring (spells added by Spell ID only): they have no
                    -- Blizzard viewer frame, so nothing tinted them out of range. Default off;
                    -- stored in customActiveStates so it travels with the spell. Racials and
                    -- items are not offered it (item range checks are protected in combat).
                    -- Greyed for a spell with no range in its base or live form, unless
                    -- already on (so it can still be cleared).
                    if sd.customSpellIDs and sd.customSpellIDs[spellID]
                       and not (ns._myRacialsSet and ns._myRacialsSet[spellID]) then
                        MakeSubnavRow("Out of Range Coloring", RANGE_COLOR_ITEMS,
                            function() return cas.outOfRangeColoring and true or nil end,
                            function(v)
                                SetCasOwn("outOfRangeColoring", v or nil)
                                if v then ns._cdmAnyCustomRangeColor = true end
                                ns.RefreshCustomSpellRange()
                            end,
                            function() return not cas.outOfRangeColoring end,
                            nil,
                            { disabled = function()
                                  if cas.outOfRangeColoring then return false end
                                  if C_Spell.SpellHasRange(spellID) then return false end
                                  local ovr = C_SpellBook.FindSpellOverrideByID(spellID)
                                  return not (ovr and ovr > 0 and C_Spell.SpellHasRange(ovr))
                              end,
                              disabledTooltip = "Requires a spell with a range" })
                    end

                    -- Audio Effect on CD Ready (preset/trinket/racial/custom): fired when the
                    -- ability comes off cooldown via the FakeActive poll (PresetOnCD). Stored in
                    -- customActiveStates so it travels with the item (own list/preview: the buff-bar branch's shared AUDIO_ITEMS/AddSoundPreview are out of scope in this branch).
                    local CDR_ITEMS = {}
                    for _, key in ipairs(ns.FOCUSKICK_SOUND_ORDER or { "none" }) do
                        if type(key) == "string" and key:sub(1, 3) == "---" then
                            CDR_ITEMS[#CDR_ITEMS + 1] = { divider = true }
                        else
                            CDR_ITEMS[#CDR_ITEMS + 1] = { val = key,
                                label = (ns.FOCUSKICK_SOUND_NAMES and ns.FOCUSKICK_SOUND_NAMES[key]) or key }
                        end
                    end
                    local function AddCdrPreview(si, item)
                        if not (item.val and item.val ~= "none") then return end
                        local play = CreateFrame("Button", nil, si)
                        play:SetSize(16, 16)
                        play:SetPoint("RIGHT", si, "RIGHT", -8, 0)
                        play:SetFrameLevel(si:GetFrameLevel() + 2)
                        play:SetNormalAtlas(EllesmereUI.SOUND_ICON_ATLAS)
                        play:SetPushedAtlas(EllesmereUI.SOUND_ICON_PRESSED_ATLAS)
                        play:SetScript("OnClick", function()
                            local path = ns.FOCUSKICK_SOUND_PATHS and ns.FOCUSKICK_SOUND_PATHS[item.val]
                            if path then PlaySoundFile(path, "Master") end
                        end)
                        play:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(play, "Preview Sound") end)
                        play:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                    end
                    MakeSubnavRow("Audio Effect on CD Ready", CDR_ITEMS,
                        function() return (cas and cas.cdReadySoundKey) or "none" end,
                        function(v)
                            local e = EnsureCAS()
                            e.cdReadySoundKey = (v ~= "none" and v) or nil
                            if ns.FakeActive_Rearm then ns.FakeActive_Rearm() end
                        end,
                        function() return not (cas and cas.cdReadySoundKey) end,
                        AddCdrPreview,
                        { searchable = true })

                    if not hasActive then
                        MakeActionRow("Add Active State", function()
                            ShowDurationPopup(nil, function(seconds)
                                EnsureCAS().duration = seconds
                                if ns.FakeActive_Rearm then ns.FakeActive_Rearm() end
                            end)
                            menu:Hide()
                        end)
                    else
                        -- Active State (swipe colour / class / hide)
                        MakeSubnavRow("Active State", CA_SWIPE_ITEMS,
                            function()
                                if cas and cas.activeSwipeMode == "none" then return "none" end
                                if cas and cas.activeSwipeClassColor then return "class" end
                                return "custom"
                            end,
                            function(v)
                                local e = EnsureCAS()
                                if v == "class" then
                                    SetCasOwn("activeSwipeMode", nil)
                                    SetCasOwn("activeSwipeClassColor", true)
                                elseif v == "none" then
                                    SetCasOwn("activeSwipeMode", "none")
                                    SetCasOwn("activeSwipeClassColor", nil)
                                else
                                    SetCasOwn("activeSwipeMode", "custom")
                                    SetCasOwn("activeSwipeClassColor", nil)
                                    -- Chained read: a slot-stamp color showing
                                    -- through is kept as the starting custom color.
                                    if not e.activeSwipeR then
                                        e.activeSwipeR = 1; e.activeSwipeG = 0.776
                                        e.activeSwipeB = 0.376; e.activeSwipeA = 0.7
                                    end
                                end
                            end,
                            function() return cas and cas.activeSwipeMode ~= "none" and not cas.activeSwipeClassColor and not cas.activeSwipeR end,
                            function(si, item)
                                if item.val == "custom" then
                                    MakeColorSwatch(si,
                                        function() return (cas and cas.activeSwipeR) or 1 end,
                                        function() return (cas and cas.activeSwipeG) or 0.776 end,
                                        function() return (cas and cas.activeSwipeB) or 0.376 end,
                                        function(r, g, b)
                                            local e = EnsureCAS()
                                            e.activeSwipeMode = "custom"
                                            SetCasOwn("activeSwipeClassColor", nil)
                                            e.activeSwipeR = r; e.activeSwipeG = g; e.activeSwipeB = b
                                            e.activeSwipeA = e.activeSwipeA or 0.7
                                        end)
                                end
                            end,
                            { apply = { keys = { "activeSwipeMode", "activeSwipeClassColor",
                                                 "activeSwipeR", "activeSwipeG", "activeSwipeB", "activeSwipeA" },
                                        write = function(t, v)
                                            -- Read the source colour BEFORE the clear below: a bar
                                            -- apply stamps every preset member's cas entry, this icon's included, so clearing first would wipe the colour this write then reads back.
                                            local pr, pg, pb, pa
                                            if cas then
                                                pr, pg, pb, pa = cas.activeSwipeR, cas.activeSwipeG,
                                                                 cas.activeSwipeB, cas.activeSwipeA
                                            end
                                            -- Colour keys belong to Custom only; clear them for
                                            -- class/none so a stale colour from an earlier Custom
                                            -- apply can't linger in the tier. Leftover R/G/B/A
                                            -- make valuesMatch always fail, so the apply never
                                            -- toggles off and re-prompts the overwrite popup
                                            -- forever without visibly changing anything.
                                            t.activeSwipeR = nil; t.activeSwipeG = nil
                                            t.activeSwipeB = nil; t.activeSwipeA = nil
                                            if v == "class" then
                                                t.activeSwipeMode = false
                                                t.activeSwipeClassColor = true
                                            elseif v == "none" then
                                                t.activeSwipeMode = "none"
                                                t.activeSwipeClassColor = false
                                            else
                                                -- Custom: push this icon's current color.
                                                t.activeSwipeMode = "custom"
                                                t.activeSwipeClassColor = false
                                                t.activeSwipeR = pr or 1
                                                t.activeSwipeG = pg or 0.776
                                                t.activeSwipeB = pb or 0.376
                                                t.activeSwipeA = pa or 0.7
                                            end
                                        end } })

                        -- Active State Glow
                        MakeSubnavRow("Active State Glow", ACTIVE_GLOW_ITEMS,
                            function()
                                local v = cas.activeGlow
                                if v == false then v = nil end  -- blocked slot value = None
                                return v
                            end,
                            function(v) SetCasOwn("activeGlow", v) end,
                            function() return not cas.activeGlow end,
                            nil,
                            { apply = { keys = { "activeGlow" },
                                        write = function(t, v) t.activeGlow = v end } })
                    end

                    -- Glow Effect Color (colours the active glow AND the CD-ready glow).
                    MakeSubnavRow("Glow Effect Color", GLOW_COLOR_ITEMS,
                        function()
                            if cas and cas.glowColor == "class" then return "class" end
                            if cas and cas.glowColor == "custom" then return "custom" end
                            return nil
                        end,
                        function(v)
                            SetCasOwn("glowColor", v)
                            -- Chained read: a slot-stamp color showing through
                            -- is kept as the starting custom color.
                            if v == "custom" and not cas.glowColorR then
                                local e = EnsureCAS()
                                e.glowColorR = 1; e.glowColorG = 0.788; e.glowColorB = 0.137
                            end
                        end,
                        function() return not (cas and cas.glowColor) end,
                        function(si, item)
                            if item.val == "custom" then
                                MakeColorSwatch(si,
                                    function() return (cas and cas.glowColorR) or 1 end,
                                    function() return (cas and cas.glowColorG) or 0.788 end,
                                    function() return (cas and cas.glowColorB) or 0.137 end,
                                    function(r, g, b)
                                        local e = EnsureCAS()
                                        e.glowColor = "custom"
                                        e.glowColorR = r; e.glowColorG = g; e.glowColorB = b
                                    end)
                            end
                        end,
                        { apply = { keys = { "glowColor", "glowColorR", "glowColorG", "glowColorB" },
                                    write = function(t, v)
                                        t.glowColor = v
                                        if v == "custom" then
                                            -- Push this icon's current color.
                                            t.glowColorR = (cas and cas.glowColorR) or 1
                                            t.glowColorG = (cas and cas.glowColorG) or 0.788
                                            t.glowColorB = (cas and cas.glowColorB) or 0.137
                                        else
                                            t.glowColorR = nil
                                            t.glowColorG = nil
                                            t.glowColorB = nil
                                        end
                                    end } })

                    -- Remove Active State (clears only the cast-triggered overlay; any Cooldown State Effect stays).
                    if hasActive then
                        MakeActionRow(EllesmereUI.L("Remove Active State") .. " (" .. (cas.duration or 0) .. "s)", function()
                            local store = ns.GetCustomActiveStates and ns.GetCustomActiveStates()
                            local e = store and store[casKey]
                            if e then
                                e.duration = nil
                                -- Prune only when nothing but active-overlay keys is left:
                                -- the other rows (cd state, saturation, swipe, range, glow
                                -- colour, sound, threshold) store here too. pairs walks own
                                -- keys only, so a chained slot stamp never holds it alive.
                                local keep
                                for k in pairs(e) do
                                    if k ~= "activeSwipeMode" and k ~= "activeSwipeClassColor"
                                       and k ~= "activeSwipeR" and k ~= "activeSwipeG"
                                       and k ~= "activeSwipeB" and k ~= "activeSwipeA"
                                       and k ~= "activeGlow" then
                                        keep = true; break
                                    end
                                end
                                if not keep then store[casKey] = nil end
                            end
                            if ns.FakeActive_Rearm then ns.FakeActive_Rearm() end
                            menu:Hide()
                        end)
                    end
                else  -- regular Blizzard-tracked cooldown: full per-spell menu
                local customDisabledTip = "Not available for custom injected spells"

                -- Custom-shaped bars always render Shape Glow, so the per-spell proc
                -- glow choice is locked (custom = any Icon Shape other than None/Cropped).
                local cdmBd = ns.barDataByKey and ns.barDataByKey[barKey]
                local barCustomShape = cdmBd and cdmBd.iconShape
                    and cdmBd.iconShape ~= "none" and cdmBd.iconShape ~= "cropped"

                -- 1. Proc Glow (default = nil)
                local procRow = MakeSubnavRow("Proc Glow", GLOW_ITEMS,
                    function() return ss.procGlow end,
                    function(v) EnsureSS(); SetOwn("procGlow", v) end,
                    function() return ss.procGlow == nil end,
                    function(si, item)
                        -- Glow choices lock while the Cooldown State Effect is any glow
                        -- (CD Ready or On CD): the reverse of that row's Proc Glow gate.
                        local isGlow = item.val and item.val > 0
                        if isGlow and CD_GLOW_EFFECT[ss.cdStateEffect] then
                            si:SetAlpha(0.35)
                            si:SetScript("OnClick", function() end)
                            si:SetScript("OnEnter", function()
                                EllesmereUI.ShowWidgetTooltip(si, "Disable the Cooldown State glow first")
                            end)
                            si:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                        end
                    end,
                    { apply = { keys = { "procGlow" },
                                write = function(t, v) t.procGlow = v end } })
                if procRow and (isCustomInjected or barCustomShape) then
                    local procDisabledTip = isCustomInjected and customDisabledTip
                        or "Custom shapes always use Shape Glow. Set the bar's Icon Shape to None or Cropped to pick a different glow."
                    procRow:SetAlpha(0.35)
                    procRow:SetScript("OnEnter", function()
                        EllesmereUI.ShowWidgetTooltip(procRow, procDisabledTip)
                    end)
                    procRow:SetScript("OnLeave", function()
                        EllesmereUI.HideWidgetTooltip()
                    end)
                end

                -- 2. Active State (default = "custom" / CD Swipe Color #FFC660)
                local activeRow = MakeSubnavRow("Active State", ACTIVE_SWIPE_ITEMS,
                    function()
                        if ss.activeSwipeMode == "none" then return "none" end
                        if ss.activeSwipeClassColor then return "class" end
                        return "custom"
                    end,
                    function(v)
                        EnsureSS()
                        if v == "class" then
                            SetOwn("activeSwipeMode", nil)
                            ss.activeSwipeClassColor = true
                        elseif v == "none" then
                            ss.activeSwipeMode = "none"
                            SetOwn("activeSwipeClassColor", nil)
                        else
                            -- Custom: keep existing color, only set defaults if none
                            ss.activeSwipeMode = "custom"
                            SetOwn("activeSwipeClassColor", nil)
                            if not ss.activeSwipeR then
                                ss.activeSwipeR = 1; ss.activeSwipeG = 0.776
                                ss.activeSwipeB = 0.376; ss.activeSwipeA = 0.7
                            end
                        end
                    end,
                    function()
                        if ss.activeBorderEnabled then return false end
                        if ss.activeSwipeMode == "none" or ss.activeSwipeClassColor then return false end
                        -- Check if custom color differs from default #FFC660
                        local dr, dg, db = 1, 0.776, 0.376
                        local cr = ss.activeSwipeR or dr
                        local cg = ss.activeSwipeG or dg
                        local cb = ss.activeSwipeB or db
                        if math.abs(cr - dr) > 0.01 or math.abs(cg - dg) > 0.01 or math.abs(cb - db) > 0.01 then
                            return false
                        end
                        return true
                    end,
                    function(si, item, sub)
                        if item.val == "custom" then
                            -- Clickable color swatch on right (opens color picker)
                            si._noCapture = true
                            local swatchBtn = EllesmereUI.BuildColorSwatch(si, si:GetFrameLevel() + 3,
                                function()
                                    return ss.activeSwipeR or 1, ss.activeSwipeG or 0.776,
                                        ss.activeSwipeB or 0.376, ss.activeSwipeA or 0.7
                                end,
                                function(r, g, b, a)
                                    ss.activeSwipeR = r; ss.activeSwipeG = g; ss.activeSwipeB = b
                                    ss.activeSwipeA = a
                                    if ns.QueueReanchor then ns.QueueReanchor() end
                                end, true, 14)
                            swatchBtn:SetPoint("RIGHT", si, "RIGHT", -8, 0)
                            swatchBtn:HookScript("PreClick", function()
                                -- Persist before mutating: for a spell with no saved settings yet
                                -- (e.g. a freshly added Hero-talent spell like Wither/Celestial
                                -- Conduit), `ss` is a throwaway {} -- without EnsureSS the picked
                                -- colour is written to a temporary table and lost, so the swipe never changes and reverts to default on reopen.
                                EnsureSS()
                                -- Ensure custom mode is selected. SetOwn: a plain nil write would inherit a bar-tier "none"/class value instead of meaning custom.
                                SetOwn("activeSwipeMode", nil)
                                SetOwn("activeSwipeClassColor", nil)
                                if not ss.activeSwipeR then
                                    ss.activeSwipeR = 1; ss.activeSwipeG = 0.776
                                    ss.activeSwipeB = 0.376; ss.activeSwipeA = 0.7
                                end
                                -- Keep the dropdown AND flyout open (OnUpdate cpOpen guard); re-highlight the now-selected Custom row.
                                if sub._refreshSelection then sub._refreshSelection() end
                                if ns.QueueReanchor then ns.QueueReanchor() end
                            end)
                        elseif item.activeBorder then
                            -- Border Color swatch (mirrors CD Swipe Color): the swatch picks the color and enables the override; the row itself toggles it on/off (handled in the item loop).
                            si._noCapture = true
                            local swatchBtn = EllesmereUI.BuildColorSwatch(si, si:GetFrameLevel() + 3,
                                function()
                                    return ss.activeBorderR or 1, ss.activeBorderG or 0.776,
                                        ss.activeBorderB or 0.376, ss.activeBorderA or 1
                                end,
                                function(r, g, b, a)
                                    ss.activeBorderR = r; ss.activeBorderG = g; ss.activeBorderB = b
                                    ss.activeBorderA = a
                                    if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                                    if ns.QueueReanchor then ns.QueueReanchor() end
                                end, true, 14)
                            swatchBtn:SetPoint("RIGHT", si, "RIGHT", -8, 0)
                            swatchBtn:HookScript("PreClick", function()
                                EnsureSS()
                                ss.activeBorderEnabled = true
                                if not ss.activeBorderR then
                                    ss.activeBorderR = 1; ss.activeBorderG = 0.776
                                    ss.activeBorderB = 0.376; ss.activeBorderA = 1
                                end
                                -- Keep the dropdown AND flyout open (OnUpdate cpOpen guard). The border toggle row manages its own highlight, so no selection refresh here.
                                if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                                if ns.QueueReanchor then ns.QueueReanchor() end
                            end)
                        end
                    end,
                    { apply = { keys = { "activeSwipeMode", "activeSwipeClassColor",
                                         "activeSwipeR", "activeSwipeG", "activeSwipeB", "activeSwipeA" },
                                write = function(t, v)
                                    -- Read the source colour BEFORE the clear below: "Apply to This
                                    -- Spell" passes ss itself, so clearing first would wipe the picked colour this write then reads back, resetting it to the default.
                                    local pr, pg, pb, pa = ss.activeSwipeR, ss.activeSwipeG,
                                                           ss.activeSwipeB, ss.activeSwipeA
                                    -- Colour keys belong to Custom only; clear them for class/none so a
                                    -- stale colour from an earlier Custom apply can't linger in the tier and make valuesMatch always fail (perpetual overwrite popup, no change).
                                    t.activeSwipeR = nil; t.activeSwipeG = nil
                                    t.activeSwipeB = nil; t.activeSwipeA = nil
                                    if v == "class" then
                                        t.activeSwipeMode = false
                                        t.activeSwipeClassColor = true
                                    elseif v == "none" then
                                        t.activeSwipeMode = "none"
                                        t.activeSwipeClassColor = false
                                    else
                                        -- Custom: push this spell's effective color.
                                        t.activeSwipeMode = "custom"
                                        t.activeSwipeClassColor = false
                                        t.activeSwipeR = pr or 1
                                        t.activeSwipeG = pg or 0.776
                                        t.activeSwipeB = pb or 0.376
                                        t.activeSwipeA = pa or 0.7
                                    end
                                end } })
                if isCustomInjected and activeRow then
                    activeRow:SetAlpha(0.35)
                    activeRow:SetScript("OnEnter", function()
                        EllesmereUI.ShowWidgetTooltip(activeRow, customDisabledTip)
                    end)
                    activeRow:SetScript("OnLeave", function()
                        EllesmereUI.HideWidgetTooltip()
                    end)
                end

                -- 3. Active State Glow (default = nil / none)
                local glowRow = MakeSubnavRow("Active State Glow", ACTIVE_GLOW_ITEMS,
                    function() return ss.activeGlow end,
                    function(v) EnsureSS(); SetOwn("activeGlow", v); if v and v > 0 then ns._cdmAnyActiveGlow = true end end,
                    function() return ss.activeGlow == nil end,
                    nil,
                    { apply = { keys = { "activeGlow" },
                                write = function(t, v)
                                    t.activeGlow = v
                                    if v and v > 0 then ns._cdmAnyActiveGlow = true end
                                end } })
                if isCustomInjected and glowRow then
                    glowRow:SetAlpha(0.35)
                    glowRow:SetScript("OnEnter", function()
                        EllesmereUI.ShowWidgetTooltip(glowRow, customDisabledTip)
                    end)
                    glowRow:SetScript("OnLeave", function()
                        EllesmereUI.HideWidgetTooltip()
                    end)
                end

                -- 3a. Max Charges Glow (default = nil/none), 1:1 with Active State Glow:
                -- glows the icon while a charge spell is at max charges. Shares the unified Glow Effect Color below. The stored key stays maxStacksGlow (label-only rename).
                local maxStacksGlowRow = MakeSubnavRow("Max Charges Glow", ACTIVE_GLOW_ITEMS,
                    function() return ss.maxStacksGlow end,
                    function(v) EnsureSS(); SetOwn("maxStacksGlow", v); if v and v > 0 then ns._cdmAnyMaxStacksGlow = true end end,
                    function() return ss.maxStacksGlow == nil end,
                    nil,
                    { apply = { keys = { "maxStacksGlow" },
                                write = function(t, v) t.maxStacksGlow = v end } })
                if isCustomInjected and maxStacksGlowRow then
                    maxStacksGlowRow:SetAlpha(0.35)
                    maxStacksGlowRow:SetScript("OnEnter", function()
                        EllesmereUI.ShowWidgetTooltip(maxStacksGlowRow, customDisabledTip)
                    end)
                    maxStacksGlowRow:SetScript("OnLeave", function()
                        EllesmereUI.HideWidgetTooltip()
                    end)
                end

                -- 3b. Non Active State (default = nil/none): desaturates the icon when its active-state is NOT active -- the mirror of the runtime's active-branch SetDesaturated(false).
                local NONACTIVE_ITEMS = {
                    { val = nil,  label = "None" },
                    { val = true, label = "Desaturate When Not Active" },
                }
                local nonActiveRow = MakeSubnavRow("Non Active State", NONACTIVE_ITEMS,
                    function() return ss.desatNotActive and true or nil end,
                    function(v) EnsureSS(); SetOwn("desatNotActive", v or nil); if v then ns._cdmAnyDesatNotActive = true end end,
                    function() return ss.desatNotActive == nil end,
                    nil,
                    { apply = { keys = { "desatNotActive" },
                                write = function(t, v) t.desatNotActive = v or false end } })
                if isCustomInjected and nonActiveRow then
                    nonActiveRow:SetAlpha(0.35)
                    nonActiveRow:SetScript("OnEnter", function()
                        EllesmereUI.ShowWidgetTooltip(nonActiveRow, customDisabledTip)
                    end)
                    nonActiveRow:SetScript("OnLeave", function()
                        EllesmereUI.HideWidgetTooltip()
                    end)
                end

                -- 3c. Cooldown Saturation (default = nil/none): suppresses the grey-out
                -- Blizzard applies while the spell is on cooldown -- grouped with Non Active State above because both own the icon's saturation.
                local KEEP_COLORED_ITEMS = {
                    { val = nil,  label = "None" },
                    { val = true, label = "Keep Colored (On CD)" },
                }
                local cdSatRow = MakeSubnavRow("Cooldown Saturation", KEEP_COLORED_ITEMS,
                    function() return ss.noDesatOnCD and true or nil end,
                    function(v)
                        EnsureSS(); SetOwn("noDesatOnCD", v or nil)
                        if v then ns._cdmAnyNoDesatOnCD = true end
                        if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                    end,
                    function() return ss.noDesatOnCD == nil end,
                    nil,
                    { apply = { keys = { "noDesatOnCD" },
                                write = function(t, v) t.noDesatOnCD = v or false end } })
                if isCustomInjected and cdSatRow then
                    cdSatRow:SetAlpha(0.35)
                    cdSatRow:SetScript("OnEnter", function()
                        EllesmereUI.ShowWidgetTooltip(cdSatRow, customDisabledTip)
                    end)
                    cdSatRow:SetScript("OnLeave", function()
                        EllesmereUI.HideWidgetTooltip()
                    end)
                end

                -- 4. Cooldown State Effect (default = nil / none)
                -- A stored button* CD Ready value keeps its Action Button Glow look when the
                -- effect is re-picked: the implied style is written out first.
                local function KeepCdGlowStyle(v)
                    local old = ss.cdStateEffect
                    if CD_GLOW_EFFECT[v] and ss.cdStateGlowStyle == nil
                       and (old == "buttonGlowReady" or old == "buttonGlowReadyUsable") then
                        SetOwn("cdStateGlowStyle", 3)
                    end
                end
                local cdStateRow = MakeSubnavRow("Cooldown State Effect", CD_STATE_ITEMS,
                    function() return CD_GLOW_EFFECT[ss.cdStateEffect] or ss.cdStateEffect end,
                    function(v)
                        -- The Resource Aware glows run an event-driven usability watcher SHARED
                        -- by every spell that uses them: its events register once, so only the
                        -- FIRST enable in the current spec pays the cost. Prompt only when no
                        -- spell on any bar in this spec already has a Resource Aware glow (a
                        -- spell's own current value counts, so pixel<->button switches and re-selects never prompt). Plain CD Ready glows are cost-free and never prompt.
                        local isGlow = (v == "pixelGlowReadyUsable" or v == "buttonGlowReadyUsable")
                        if isGlow and not AB.AnyResourceAwareGlowSaved() then
                            menu:Hide()
                            EllesmereUI:ShowConfirmPopup({
                                title       = "CD Ready Glow (Resource Aware)",
                                message     = "Resource Aware CD Ready Glow may cause a slight loss in performance efficiency. Do you want to enable it?",
                                confirmText = "Enable",
                                cancelText  = "Cancel",
                                onConfirm   = function()
                                    EnsureSS(); KeepCdGlowStyle(v); ss.cdStateEffect = v
                                    if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                                end,
                            })
                            return
                        end
                        EnsureSS(); KeepCdGlowStyle(v); SetOwn("cdStateEffect", v)
                        if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                    end,
                    function() return ss.cdStateEffect == nil and not ss.chargeHideSwipe and not ss.hideRechargeEdge and not ss.chargeHideCdText and not ss.chargeHideUntilSpent end,
                    function(si, item, sub)
                        -- Lower Alpha (On CD): clicking prompts for the opacity percent, then selects the effect (mirrors the setVal above).
                        if item.val == "lowerAlphaOnCD" then
                            si:SetScript("OnClick", function()
                                local cur = math.floor(((ss.cdStateLowerAlpha or 0.5) * 100) + 0.5)
                                -- Close the per-spell dropdown so only the popup shows.
                                menu:Hide()
                                ShowAlphaPopup(cur, function(pct)
                                    EnsureSS()
                                    ss.cdStateLowerAlpha = pct / 100
                                    ss.cdStateEffect = "lowerAlphaOnCD"
                                    if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                                end)
                            end)
                            return
                        end
                        local isGlow = (item.val == "pixelGlowReady" or item.val == "buttonGlowReady"
                            or item.val == "pixelGlowReadyUsable" or item.val == "buttonGlowReadyUsable"
                            or item.val == "glowOnCD")
                        if isGlow and ss.procGlow and ss.procGlow > 0 then
                            si:SetAlpha(0.35)
                            si:SetScript("OnClick", function() end)
                            si:SetScript("OnEnter", function()
                                EllesmereUI.ShowWidgetTooltip(si, "Disable Proc Glow first")
                            end)
                            si:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                        end
                    end,
                    { apply = { confirmRA = true,
                                keys = { "cdStateEffect", "cdStateLowerAlpha", "cdStateGlowStyle", "cdStateGlowAlpha" },
                                write = function(t, v)
                                    -- The glow style resolves for the APPLIED effect, as a
                                    -- direct pick would: the spell's own Glow Style wins, a
                                    -- stored button* value keeps its Action Button Glow look
                                    -- (KeepCdGlowStyle), else the effect's default. The
                                    -- current effect is read before t (ss for Apply to This
                                    -- Spell) is written.
                                    local cur = ss.cdStateEffect
                                    -- "None" applied bar-wide = explicitly no effect
                                    -- (false blocks the all-specs tier below).
                                    t.cdStateEffect = v or false
                                    local st
                                    if CD_GLOW_EFFECT[v] then
                                        local keepBtn = cur == "buttonGlowReady" or cur == "buttonGlowReadyUsable"
                                        st = ns.CdReadyGlowStyle(keepBtn and cur or v, ss)
                                    end
                                    t.cdStateGlowStyle = st
                                    t.cdStateGlowAlpha = (st == 8) and ss.cdStateGlowAlpha or nil
                                    if v == "lowerAlphaOnCD" then
                                        -- Push this spell's current percent (no popup).
                                        t.cdStateLowerAlpha = ss.cdStateLowerAlpha or 0.5
                                    else
                                        t.cdStateLowerAlpha = nil
                                    end
                                end } })
                if isCustomInjected and cdStateRow then
                    cdStateRow:SetAlpha(0.35)
                    cdStateRow:SetScript("OnEnter", function()
                        EllesmereUI.ShowWidgetTooltip(cdStateRow, customDisabledTip)
                    end)
                    cdStateRow:SetScript("OnLeave", function()
                        EllesmereUI.HideWidgetTooltip()
                    end)
                end

                -- 4b. Glow Style: the style the CD Ready and On CD glows use.
                if not isCustomInjected then
                    MakeSubnavRow("Glow Style", CD_READY_STYLE_ITEMS,
                        function() return ns.CdReadyGlowStyle(ss.cdStateEffect, ss) end,
                        function(v)
                            EnsureSS(); SetOwn("cdStateGlowStyle", v)
                            if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                        end,
                        function() return ss.cdStateGlowStyle == nil end,
                        function(si, item, sub)
                            -- Blackout: clicking prompts for the opacity percent, then
                            -- selects this style (mirrors Lower Alpha's onClick above).
                            if item.val == 8 then
                                item.dynamicLabel = function()
                                    local base = EllesmereUI.L(ns.GLOW_STYLES[8].name)
                                    if ns.CdReadyGlowStyle(ss.cdStateEffect, ss) == 8 then
                                        local pct = math.floor(((ss.cdStateGlowAlpha or 1) * 100) + 0.5)
                                        return pct .. "% " .. base
                                    end
                                    return base
                                end
                                si:SetScript("OnClick", function()
                                    local cur = math.floor(((ss.cdStateGlowAlpha or 1) * 100) + 0.5)
                                    menu:Hide()
                                    ShowAlphaPopup(cur, function(pct)
                                        EnsureSS()
                                        ss.cdStateGlowAlpha = pct / 100
                                        SetOwn("cdStateGlowStyle", 8)
                                        if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                                    end, EllesmereUI.L("Glow Opacity"), EllesmereUI.L("Blackout glow opacity (1-100%)"))
                                end)
                            end
                        end,
                        { disabled = function() return not CD_GLOW_EFFECT[ss.cdStateEffect] end,
                          apply = { keys = { "cdStateGlowStyle", "cdStateGlowAlpha" },
                                    -- The Blackout opacity rides along with the Blackout value
                                    -- only: a spell that set its own opacity pushes it to the bar
                                    -- instead of rejoining the bar's (see payloadValue).
                                    payload = function(item) return item.val == 8 end,
                                    write = function(t, v)
                                        t.cdStateGlowStyle = v
                                        t.cdStateGlowAlpha = (v == 8) and ss.cdStateGlowAlpha or nil
                                    end } })
                end

                -- 4a. Threshold Text: decimals/color change on this spell's countdowns
                -- (cooldown, recharge and active state) below its Threshold Seconds. Engine countdown formatter -- see ns.ApplyThresholdFormatter; zero cost until armed.
                do
                    local acc = {}
                    acc.get = function(k) return ss[k] end
                    acc.set = function(k, v) EnsureSS(); ss[k] = v end
                    acc.clear = function(k) EnsureSS(); SetOwn(k, nil) end
                    acc.refresh = function()
                        if (tonumber(ss.thresholdSeconds) or 0) > 0 then ns._cdmAnyThresholdText = true end
                        if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                        if ns.QueueReanchor then ns.QueueReanchor() end
                    end
                    AddThresholdTextRow(acc)
                end

                -- 4b. Cooldown Swipe (per-spell): Reverse Swipe flips the swipe direction;
                -- Hide CD Swipe removes it. Default off. Runtime apply + zero-cost gates live in RefreshCDMIconAppearance/RescanReverseSwipeFlag and the SetDrawSwipe hook.
                MakeSubnavRow("Cooldown Swipe", CD_SWIPE_ITEMS,
                    function()
                        if ss.hideCDSwipe then return "hide" end
                        if ss.reverseSwipe then return "reverse" end
                        return nil
                    end,
                    function(v)
                        EnsureSS()
                        SetOwn("reverseSwipe", (v == "reverse") or nil)
                        SetOwn("hideCDSwipe", (v == "hide") or nil)
                        if ss.reverseSwipe then ns._cdmAnyReverseSwipe = true end
                        if ss.hideCDSwipe then ns._cdmAnyHideCDSwipe = true end
                        if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                    end,
                    function() return ss.reverseSwipe == nil and ss.hideCDSwipe == nil end,
                    nil,
                    { apply = { keys = { "reverseSwipe", "hideCDSwipe" },
                                write = function(t, v)
                                    -- "Off" applied bar-wide blocks the tier below.
                                    t.reverseSwipe = (v == "reverse") or false
                                    t.hideCDSwipe = (v == "hide") or false
                                end } })

                -- 4c. Audio Effect on CD Ready (cd/utility per-icon): play a sound the moment
                -- the spell's real cooldown finishes. Same sound list + speaker preview as the
                -- buff Audio rows/Focus Cast Sound (shared ns.FOCUSKICK_SOUND_* tables); stored
                -- as ss.cdReadySoundKey ("none"/nil = silent). The per-frame SetDesaturated edge hook (gated by ns._cdmAnyCdReadySound) fires it on the on-CD -> ready edge.
                local CDR_AUDIO_ITEMS = {}
                for _, key in ipairs(ns.FOCUSKICK_SOUND_ORDER or { "none" }) do
                    if type(key) == "string" and key:sub(1, 3) == "---" then
                        CDR_AUDIO_ITEMS[#CDR_AUDIO_ITEMS + 1] = { divider = true }
                    else
                        CDR_AUDIO_ITEMS[#CDR_AUDIO_ITEMS + 1] = {
                            val   = key,
                            label = (ns.FOCUSKICK_SOUND_NAMES and ns.FOCUSKICK_SOUND_NAMES[key]) or key,
                        }
                    end
                end
                local function AddCdrSoundPreview(si, item)
                    if item.val and item.val ~= "none" then
                        local play = CreateFrame("Button", nil, si)
                        play:SetSize(16, 16)
                        play:SetPoint("RIGHT", si, "RIGHT", -8, 0)
                        play:SetFrameLevel(si:GetFrameLevel() + 2)
                        play:SetNormalAtlas(EllesmereUI.SOUND_ICON_ATLAS)
                        play:SetPushedAtlas(EllesmereUI.SOUND_ICON_PRESSED_ATLAS)
                        play:SetScript("OnClick", function()
                            local paths = ns.FOCUSKICK_SOUND_PATHS
                            local path = paths and paths[item.val]
                            if path then PlaySoundFile(path, "Master") end
                        end)
                        play:SetScript("OnEnter", function()
                            EllesmereUI.ShowWidgetTooltip(play, "Preview Sound")
                        end)
                        play:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                    end
                end
                local cdReadySoundRow = MakeSubnavRow("Audio Effect on CD Ready", CDR_AUDIO_ITEMS,
                    function() return ss.cdReadySoundKey or "none" end,
                    function(v)
                        EnsureSS()
                        SetOwn("cdReadySoundKey", (v ~= "none" and v) or nil)
                        -- Flip the 0-cost gate live so the edge hook starts evaluating on the next
                        -- desaturation tick, and refresh so a CHARGE spell registers on the SPELL_UPDATE_CHARGES watcher immediately.
                        if ss.cdReadySoundKey then ns._cdmAnyCdReadySound = true end
                        if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                    end,
                    function() return ss.cdReadySoundKey == nil end,
                    AddCdrSoundPreview,
                    { searchable = true,
                      apply = { keys = { "cdReadySoundKey" },
                                write = function(t, v)
                                    -- "None" applied bar-wide = explicitly silent.
                                    t.cdReadySoundKey = (v ~= "none" and v) or false
                                end } })
                -- Custom-injected spells drive their cd-state through the Fake-Active engine,
                -- not the SetDesaturated/GetSpellCooldown edge this sound rides, so dim the row for them (same as Cooldown State Effect above).
                if isCustomInjected and cdReadySoundRow then
                    cdReadySoundRow:SetAlpha(0.35)
                    cdReadySoundRow:SetScript("OnEnter", function()
                        EllesmereUI.ShowWidgetTooltip(cdReadySoundRow, customDisabledTip)
                    end)
                    cdReadySoundRow:SetScript("OnLeave", function()
                        EllesmereUI.HideWidgetTooltip()
                    end)
                end

                -- 5. Glow Effect Color (unified color for all glow types)
                local GLOW_COLOR_ITEMS = {
                    { val = nil,      label = "Default" },
                    { val = "class",  label = "Class Color" },
                    { val = "custom", label = "Custom" },
                }
                local glowColorRow = MakeSubnavRow("Glow Effect Color", GLOW_COLOR_ITEMS,
                    function()
                        if ss.glowColor == "class" then return "class" end
                        if ss.glowColor == "custom" then return "custom" end
                        return nil
                    end,
                    function(v)
                        EnsureSS()
                        SetOwn("glowColor", v)
                        if v == "custom" and not ss.glowColorR then
                            ss.glowColorR = 1; ss.glowColorG = 0.788; ss.glowColorB = 0.137
                        end
                        if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                    end,
                    function() return ss.glowColor == nil end,
                    function(si, item, sub)
                        if item.val == "custom" then
                            si._noCapture = true
                            local swatchBtn = EllesmereUI.BuildColorSwatch(si, si:GetFrameLevel() + 3,
                                function() return ss.glowColorR or 1, ss.glowColorG or 0.788, ss.glowColorB or 0.137, 1 end,
                                function(r, g, b)
                                    ss.glowColorR = r; ss.glowColorG = g; ss.glowColorB = b
                                    if ns.RefreshCDMIconAppearance then ns.RefreshCDMIconAppearance(barKey) end
                                end, false, 14)
                            swatchBtn:SetPoint("RIGHT", si, "RIGHT", -8, 0)
                            swatchBtn:HookScript("PreClick", function()
                                EnsureSS()
                                ss.glowColor = "custom"
                                if not ss.glowColorR then
                                    ss.glowColorR = 1; ss.glowColorG = 0.788; ss.glowColorB = 0.137
                                end
                                -- Keep the dropdown AND flyout open (OnUpdate cpOpen guard); re-highlight the now-selected Custom row.
                                if sub._refreshSelection then sub._refreshSelection() end
                            end)
                        end
                    end,
                    { apply = { keys = { "glowColor", "glowColorR", "glowColorG", "glowColorB" },
                                write = function(t, v)
                                    t.glowColor = v
                                    if v == "custom" then
                                        -- Push this spell's effective color.
                                        t.glowColorR = ss.glowColorR or 1
                                        t.glowColorG = ss.glowColorG or 0.788
                                        t.glowColorB = ss.glowColorB or 0.137
                                    else
                                        t.glowColorR = nil
                                        t.glowColorG = nil
                                        t.glowColorB = nil
                                    end
                                end } })

                -- Plugin Glows: a Glow Style + Glow Color per source registered through
                -- EllesmereUI.PluginGlows (EUI_CDM_PluginGlows.lua). Not shown when nothing is registered.
                local pgList = ns.PluginGlowsGetList and ns.PluginGlowsGetList()
                if pgList and #pgList > 0 then
                    do
                        -- Same styles as Active State Glow (None + styles) plus Blackout, which prompts for its opacity.
                        local PG_STYLE_ITEMS = {}
                        for i, it in ipairs(ACTIVE_GLOW_ITEMS) do PG_STYLE_ITEMS[i] = it end
                        PG_STYLE_ITEMS[#PG_STYLE_ITEMS + 1] = { val = 8, label = ns.GLOW_STYLES[8].name }
                        local function onApplied() ns.PluginGlowsSettingsChanged(barKey) end
                        local function SourceDefault(k) return not ss[k.style] and not ss[k.color] end
                        AB.MakePanelRow("Plugin Glows", function(add)
                            for _, reg in ipairs(pgList) do
                                local k = reg.keys
                                add.Panel(reg.name, function(add2)
                                    local function SetStyle(v)
                                        EnsureSS(); SetOwn(k.style, v)
                                        if v and v > 0 then ns.PluginGlowsMarkInUse(reg.id) end
                                        ns.PluginGlowsSettingsChanged(barKey)
                                    end
                                    add2.Subnav("Glow Style", PG_STYLE_ITEMS,
                                        function() return ss[k.style] end,
                                        SetStyle,
                                        function() return not ss[k.style] end,
                                        function(si, item)
                                            -- Blackout: clicking prompts for the opacity percent, then selects it.
                                            if item.val == 8 then
                                                item.dynamicLabel = function()
                                                    local base = EllesmereUI.L(ns.GLOW_STYLES[8].name)
                                                    if ss[k.style] == 8 then
                                                        local pct = math.floor(((ss[k.alpha] or 1) * 100) + 0.5)
                                                        return pct .. "% " .. base
                                                    end
                                                    return base
                                                end
                                                si:SetScript("OnClick", function()
                                                    local cur = math.floor(((ss[k.alpha] or 1) * 100) + 0.5)
                                                    menu:Hide()
                                                    ShowAlphaPopup(cur, function(pct)
                                                        EnsureSS()
                                                        ss[k.alpha] = pct / 100
                                                        SetStyle(8)
                                                    end, EllesmereUI.L("Glow Opacity"), EllesmereUI.L("Blackout glow opacity (1-100%)"))
                                                end)
                                            end
                                        end,
                                        { onApplied = onApplied,
                                          apply = { keys = { k.style, k.alpha },
                                                    -- The opacity rides along with the Blackout value only.
                                                    payload = function(item) return item.val == 8 end,
                                                    write = function(t, v)
                                                        t[k.style] = v
                                                        t[k.alpha] = (v == 8) and ss[k.alpha] or nil
                                                    end } })
                                    add2.Subnav("Glow Color", GLOW_COLOR_ITEMS,
                                        function()
                                            if ss[k.color] == "class" then return "class" end
                                            if ss[k.color] == "custom" then return "custom" end
                                            return nil
                                        end,
                                        function(v)
                                            EnsureSS()
                                            SetOwn(k.color, v)
                                            if v == "custom" and not ss[k.colorR] then
                                                ss[k.colorR] = 1; ss[k.colorG] = 0.788; ss[k.colorB] = 0.137
                                            end
                                            ns.PluginGlowsSettingsChanged(barKey)
                                        end,
                                        function() return not ss[k.color] end,
                                        function(si, item, sub)
                                            if item.val == "custom" then
                                                si._noCapture = true
                                                local swatchBtn = EllesmereUI.BuildColorSwatch(si, si:GetFrameLevel() + 3,
                                                    function() return ss[k.colorR] or 1, ss[k.colorG] or 0.788, ss[k.colorB] or 0.137, 1 end,
                                                    function(r, g, b)
                                                        ss[k.colorR] = r; ss[k.colorG] = g; ss[k.colorB] = b
                                                        ns.PluginGlowsSettingsChanged(barKey)
                                                    end, false, 14)
                                                swatchBtn:SetPoint("RIGHT", si, "RIGHT", -8, 0)
                                                swatchBtn:HookScript("PreClick", function()
                                                    EnsureSS()
                                                    ss[k.color] = "custom"
                                                    if not ss[k.colorR] then
                                                        ss[k.colorR] = 1; ss[k.colorG] = 0.788; ss[k.colorB] = 0.137
                                                    end
                                                    if sub._refreshSelection then sub._refreshSelection() end
                                                end)
                                            end
                                        end,
                                        { onApplied = onApplied,
                                          apply = { keys = { k.color, k.colorR, k.colorG, k.colorB },
                                                    write = function(t, v)
                                                        t[k.color] = v
                                                        if v == "custom" then
                                                            -- Push this spell's current color.
                                                            t[k.colorR] = ss[k.colorR] or 1
                                                            t[k.colorG] = ss[k.colorG] or 0.788
                                                            t[k.colorB] = ss[k.colorB] or 0.137
                                                        else
                                                            t[k.colorR] = nil
                                                            t[k.colorG] = nil
                                                            t[k.colorB] = nil
                                                        end
                                                    end } })
                                end, function() return SourceDefault(k) end)
                            end
                        end, function()
                            for _, reg in ipairs(pgList) do
                                if not SourceDefault(reg.keys) then return false end
                            end
                            return true
                        end)
                    end
                end

                end  -- not isCustomInjected
                end  -- isBuffBar per-icon rows

                -- (The per-setting "Apply to Bar / (All Specs)" strip superseded
                -- "Sync All Bar Buttons"; cdm_spell_settings_tiers_v1 migrated it.)

                -- Replace with Buff (cd/util family, real spells only; per-spell ONLY like
                -- Custom Icon -- a slot identity choice, no tiers, no apply strip). Picks a
                -- tracked buff whose viewer frame takes this cooldown's slot while the aura
                -- is active; the cooldown returns when it ends. Closes the menu (popup flow).
                if not isBuffBar and not isHostedBuff and not (bd and bd.isGhostBar)
                   and type(spellID) == "number" and spellID > 0
                   and not ((ns._myRacialsSet and ns._myRacialsSet[spellID])
                            or (sd.customSpellIDs and sd.customSpellIDs[spellID])) then
                    local repSID = rawget(ss, "replaceBuffID")
                    local repName = repSID and C_Spell.GetSpellName(repSID)
                    local rbRow = CreateFrame("Button", nil, inner)
                    rbRow:SetHeight(ITEM_H)
                    rbRow:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
                    rbRow:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
                    rbRow:SetFrameLevel(menu:GetFrameLevel() + 2)
                    local rbLbl = rbRow:CreateFontString(nil, "OVERLAY")
                    rbLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                    rbLbl:SetPoint("LEFT", 10, 0); rbLbl:SetPoint("RIGHT", -10, 0)
                    rbLbl:SetJustifyH("LEFT"); rbLbl:SetWordWrap(false); rbLbl:SetMaxLines(1)
                    rbLbl:SetText(EllesmereUI.L("Replace with Buff") .. ": " .. (repName or EllesmereUI.L("None")))
                    rbLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                    local rbHl = rbRow:CreateTexture(nil, "ARTWORK")
                    rbHl:SetAllPoints(); rbHl:SetColorTexture(1, 1, 1, 0); rbHl:SetAlpha(0)
                    rbRow:SetScript("OnEnter", function()
                        rbLbl:SetTextColor(1, 1, 1, 1)
                        rbHl:SetColorTexture(1, 1, 1, hlA); rbHl:SetAlpha(1)
                        EllesmereUI.ShowWidgetTooltip(rbRow, EllesmereUI.L("Show a tracked buff in this slot while it is active."))
                    end)
                    rbRow:SetScript("OnLeave", function()
                        rbLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA); rbHl:SetAlpha(0)
                        EllesmereUI.HideWidgetTooltip()
                    end)
                    rbRow:SetScript("OnClick", function()
                        EllesmereUI.HideWidgetTooltip()
                        menu:Hide()
                        ShowBuffToCDPicker(rbRow, barKey, nil, function(buffSID, buffCdID)
                            if ns.SetCooldownBuffReplacement then
                                ns.SetCooldownBuffReplacement(barKey, spellID, buffSID, buffCdID)
                            end
                            RefreshCDPreview()
                        end)
                    end)
                    mH = mH + ITEM_H
                end

                -- Talent Conditions (cd/util family, real spells only; per-spell ONLY like
                -- Replace with Buff -- no tiers, no apply strip). The icon shows only while
                -- every picked condition holds (EllesmereUICdmTalentConditions.lua); the
                -- tree popup lives in EUI_CooldownManager_TalentConditions.lua. Closes the menu (popup flow).
                -- Not on WoW Forever: its vanilla trees have no class/spec split for the popup to draw.
                if not EllesmereUI.IS_FOREVER
                   and not isBuffBar and not isHostedBuff and not (bd and bd.isGhostBar)
                   and type(spellID) == "number" and spellID > 0
                   and not ((ns._myRacialsSet and ns._myRacialsSet[spellID])
                            or (sd.customSpellIDs and sd.customSpellIDs[spellID])) then
                    AddTalentConditionsRow(spellID, ss, EnsureSS)
                end

                -- Custom Icon (per-spell ONLY -- deliberately outside the Apply-to-Bar
                -- tiers: an icon replacement is a per-slot identity choice, so no tiers, no
                -- apply strip, no false-blocking; a plain nil write removes it). The render
                -- side re-stamps after every Blizzard icon repaint against the frame's full
                -- identity set, so it follows every transform. At the COMMON rejoin point
                -- (both families); skipped for preset/item entries (negative ids -- their settings live in customActiveStates, which nothing reads customIcon from). Popup flow closes the menu, matching Lower Alpha.
                if not (type(spellID) == "number" and spellID < 0) then
                    local hasCI = type(rawget(ss, "customIcon")) == "number"
                    local ciRow = CreateFrame("Button", nil, inner)
                    ciRow:SetHeight(ITEM_H)
                    ciRow:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
                    ciRow:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
                    ciRow:SetFrameLevel(menu:GetFrameLevel() + 2)
                    local ciLbl = ciRow:CreateFontString(nil, "OVERLAY")
                    ciLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                    ciLbl:SetPoint("LEFT", 10, 0); ciLbl:SetJustifyH("LEFT")
                    ciLbl:SetText(EllesmereUI.L(hasCI and "Edit Custom Icon" or "Add Custom Icon"))
                    ciLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                    local ciHl = ciRow:CreateTexture(nil, "ARTWORK")
                    ciHl:SetAllPoints(); ciHl:SetColorTexture(1, 1, 1, 0); ciHl:SetAlpha(0)
                    ciRow:SetScript("OnEnter", function()
                        ciLbl:SetTextColor(1, 1, 1, 1)
                        ciHl:SetColorTexture(1, 1, 1, hlA); ciHl:SetAlpha(1)
                        if menu._openSub and menu._openSub:IsShown() then menu._openSub:Hide() end
                    end)
                    ciRow:SetScript("OnLeave", function()
                        ciLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA); ciHl:SetAlpha(0)
                    end)
                    ciRow:SetScript("OnClick", function()
                        -- Close the per-spell dropdown so only the popup shows.
                        menu:Hide()
                        ns.ShowCDMCustomIconPopup(rawget(ss, "customIcon"), function(id)
                            EnsureSS()
                            ss.customIcon = id
                            if id then
                                -- Live-arm the session gate (monotonic; the login rescan covers already-saved settings).
                                ns._cdmAnyCustomIcon = true
                            end
                            -- Stamp/restore on every claimed frame now: DecorateFrame runs from
                            -- the reanchor pass (the only re-style path for the default Essential/Utility bars).
                            if ns.QueueReanchor then ns.QueueReanchor() end
                            -- Aura-tracked custom buffs render in an engine container the
                            -- reanchor never reaches; their sync pass rebuilds it when the
                            -- icon changes (a signature no-op for every other bar).
                            if ns.UpdateCustomBuffAuraTracking then ns.UpdateCustomBuffAuraTracking() end
                        end)
                    end)
                    mH = mH + ITEM_H
                end

                -- Copy to Other Specs (user Custom Spell/Buff IDs only, gated on the
                -- customSpellIDs tag -- racials/trinkets/presets never show it). At the
                -- COMMON rejoin point so it appears for custom IDs on any bar type. One-time
                -- copy of the spell + its per-spell settings onto the SAME bar in the picked specs; specs that already have it anywhere are skipped. Self-contained row (MakeActionRow helpers are out of scope).
                if sd.customSpellIDs and sd.customSpellIDs[spellID] then
                    -- Label flips to Remove once the spell lives on other specs.
                    local otherSpecs = (ns.SpecsWithCustomSpell and ns.SpecsWithCustomSpell(spellID)) or {}
                    local isRemove = next(otherSpecs) ~= nil
                    local copyRow = CreateFrame("Button", nil, inner)
                    copyRow:SetHeight(ITEM_H)
                    copyRow:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
                    copyRow:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
                    copyRow:SetFrameLevel(menu:GetFrameLevel() + 2)
                    local crLbl = copyRow:CreateFontString(nil, "OVERLAY")
                    crLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                    crLbl:SetPoint("LEFT", 10, 0); crLbl:SetJustifyH("LEFT")
                    crLbl:SetText(EllesmereUI.L(isRemove and "Remove from Other Specs" or "Copy to Other Specs"))
                    crLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                    local crHl = copyRow:CreateTexture(nil, "ARTWORK")
                    crHl:SetAllPoints(); crHl:SetColorTexture(1, 1, 1, 0); crHl:SetAlpha(0)
                    copyRow:SetScript("OnEnter", function()
                        crLbl:SetTextColor(1, 1, 1, 1)
                        crHl:SetColorTexture(1, 1, 1, hlA); crHl:SetAlpha(1)
                        if menu._openSub and menu._openSub:IsShown() then menu._openSub:Hide() end
                    end)
                    copyRow:SetScript("OnLeave", function()
                        crLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA); crHl:SetAlpha(0)
                    end)
                    copyRow:SetScript("OnClick", function()
                        menu:Hide()
                        local specs = (ns.GetCDMSpecInfo and ns.GetCDMSpecInfo()) or {}
                        local curKey = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
                        if isRemove then
                            -- Remove picker: only specs that HAVE the spell are pre-checked +
                            -- selectable; the rest (and current) are disabled. Confirm removes from the checked specs.
                            local disabled = {}
                            for _, s in ipairs(specs) do
                                s.checked = otherSpecs[s.key] and true or false
                                if s.key == curKey then
                                    disabled[s.key] = "You're on this spec."
                                elseif not otherSpecs[s.key] then
                                    disabled[s.key] = "This spec doesn't have this spell."
                                end
                            end
                            EllesmereUI:ShowCDMSpecPickerPopup({
                                title         = "Remove from Other Specs",
                                subtitle      = "Uncheck a spec to keep it. Confirm removes this custom spell and its settings from the checked specs.",
                                confirmText   = "Remove",
                                specs         = specs,
                                disabledSpecs = disabled,
                                foreverAllKeys   = true,
                                foreverActiveKey = curKey,
                                onConfirm     = function(selectedSpecs)
                                    if ns.RemoveCustomSpellFromSpecs then
                                        ns.RemoveCustomSpellFromSpecs(spellID, selectedSpecs)
                                    end
                                end,
                            })
                        else
                            local disabled
                            if curKey then disabled = { [curKey] = "You're on this spec." } end
                            EllesmereUI:ShowCDMSpecPickerPopup({
                                title         = "Copy to Other Specs",
                                subtitle      = "Copies this custom spell and its settings to the same bar on the specs you pick. Specs that already have it are skipped.",
                                confirmText   = "Copy",
                                specs         = specs,
                                disabledSpecs = disabled,
                                foreverActiveKey = curKey,
                                onConfirm     = function(selectedSpecs)
                                    if ns.CopyCustomSpellToSpecs then
                                        ns.CopyCustomSpellToSpecs(barKey, spellID, selectedSpecs)
                                    end
                                end,
                            })
                        end
                    end)
                    mH = mH + ITEM_H
                end
            end
        end

        -- Size and show
        inner:SetHeight(mH + 4)
        menu:SetSize(menuW, mH + 4)
        menu:ClearAllPoints()
        menu:SetPoint("TOP", anchorFrame, "BOTTOM", 0, -4)
        menu._anchorFrame = anchorFrame
        optState._spellPickerMenu = menu
        menu._openSub = nil  -- track open subnav for close checks
        menu:SetScript("OnUpdate", function(m)
            local overMenu = m:IsMouseOver() or anchorFrame:IsMouseOver()
            -- A cog flyout (Duration/Charge-Stack) drives itself through this menu, so also
            -- treat "mouse over the flyout's open dropdown menu" as over-the-sub. Without this, picking a Position option whose list extends below the flyout reads as an outside click and closes the whole menu.
            local sub = m._openSub
            -- Nested flyouts (Plugin Glows) hang off their parent panel's _openChild; any panel in the chain counts as "over the sub".
            local overSub = false
            local chain = sub
            while chain and chain:IsVisible() do
                if chain:IsMouseOver() or (chain._anyDropdownHovered and chain._anyDropdownHovered()) then
                    overSub = true
                    break
                end
                chain = chain._openChild
            end
            -- "Apply to Bar" strip: same lifecycle as a subnav flyout -- it never hides on
            -- hover-out (that made the 2px gap unreachable). It dies with its owner item: flyout closed, rebuilt, or the items reparented away (IsVisible sees through a hidden parent; IsShown would not).
            local strip = m._applyStrip
            local overStrip = strip and strip:IsShown() and strip:IsMouseOver()
            if strip and strip:IsShown() then
                local owner = strip._ownerItem
                if not (owner and owner:IsVisible()) then
                    strip:Hide()
                end
            end
            -- Keep the menu open while the shared color picker is up: it's a separate popup, so interacting with it must not dismiss the menu (and its cog/subnav flyout).
            local cp = EllesmereUI._colorPickerPopup
            local cpOpen = cp and cp:IsShown()
            if not overMenu and not overSub and not overStrip and not cpOpen
               and IsMouseButtonDown("LeftButton") then
                m:Hide()
            end
        end)
        menu:SetScript("OnHide", function(m)
            m:SetScript("OnUpdate", nil)
            if m._openSub and m._openSub:IsShown() then m._openSub:Hide() end
            if m._applyStrip then m._applyStrip:Hide() end
        end)
        menu:Show()
        return
    end

    -- Divider after Remove Spell (only in full picker mode)
    if slotIndex then
        local div = inner:CreateTexture(nil, "ARTWORK")
        div:SetHeight(1)
        div:SetColorTexture(1, 1, 1, 0.10)
        div:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
        div:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
        mH = mH + 9
    end

    -- "Custom Spell ID" option: shown for CD/utility and custom_buff bars. Regular buff bars only show Blizzard CDM spells (no custom entry).
    if not isBuffBar then
        local csItem = CreateFrame("Button", nil, inner)
        csItem:SetHeight(ITEM_H)
        csItem:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
        csItem:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
        csItem:SetFrameLevel(menu:GetFrameLevel() + 2)

        local csHl = csItem:CreateTexture(nil, "ARTWORK")
        csHl:SetAllPoints(); csHl:SetColorTexture(1, 1, 1, 0); csHl:SetAlpha(0)

        local csLbl = csItem:CreateFontString(nil, "OVERLAY")
        csLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
        csLbl:SetPoint("LEFT", 10, 0)
        csLbl:SetJustifyH("LEFT")
        csLbl:SetText(EllesmereUI.L("Custom Spell ID"))
        csLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)

        csItem:SetScript("OnEnter", function()
            csLbl:SetTextColor(1, 1, 1, 1)
            csHl:SetColorTexture(1, 1, 1, hlA); csHl:SetAlpha(1)
        end)
        csItem:SetScript("OnLeave", function()
            csLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
            csHl:SetAlpha(0)
        end)
        csItem:SetScript("OnClick", function()
            menu:Hide()
            -- Own frame, not ShowCustomSpellIDPopup's: only this build adds Show Charges,
            -- and sharing one lazily built frame let whichever opened first win.
            local popupName = "EUI_CDM_CDSpellIDPopup"
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

                -- Permanent red note: a manually-entered custom spell has no live cooldown
                -- frame, so charge counts cannot be tracked. Shown only for CD/utility bars (not custom aura bars).
                local chargeWarn = popup:CreateFontString(nil, "OVERLAY")
                chargeWarn:SetFont(FONT_PATH, 10, GetCDMOptOutline())
                chargeWarn:SetPoint("LEFT", popup, "LEFT", 16, 0)
                chargeWarn:SetPoint("RIGHT", popup, "RIGHT", -16, 0)
                chargeWarn:SetPoint("BOTTOM", addBtn, "TOP", 0, 17)
                chargeWarn:SetJustifyH("CENTER")
                chargeWarn:SetTextColor(0.9, 0.3, 0.3, 1)
                chargeWarn:SetText(EllesmereUI.L("Custom spells cannot track charges."))
                popup._chargeWarn = chargeWarn

                -- "Show Charges" opt-in (CD/utility custom spells): a manually entered spell
                -- has no Blizzard charge frame, but its cast count can still be shown on
                -- request. Replaces the old red "cannot track charges" note for CD/utility;
                -- hidden for custom auras. do-block so the build-time locals are released (this file has a function at the Lua 5.1 200-local cap).
                do
                    local wrap = CreateFrame("Button", nil, popup)
                    wrap:SetSize(16, 16)
                    wrap:SetPoint("BOTTOM", popup, "BOTTOM", -46, 60)
                    wrap:Hide()
                    local bg = wrap:CreateTexture(nil, "BACKGROUND")
                    bg:SetAllPoints(); bg:SetColorTexture(0.060, 0.049, 0.037, 1)
                    EllesmereUI.MakeBorder(wrap, 1, 1, 1, 0.15, EllesmereUI.PP)
                    local mark = wrap:CreateTexture(nil, "ARTWORK")
                    mark:SetPoint("CENTER"); mark:SetSize(9, 9)
                    mark:SetColorTexture(ar, ag, ab, 1); mark:Hide()
                    local lbl = wrap:CreateFontString(nil, "OVERLAY")
                    lbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                    lbl:SetPoint("LEFT", wrap, "RIGHT", 6, 0)
                    lbl:SetText(EllesmereUI.L("Show Charges"))
                    lbl:SetTextColor(0.8, 0.8, 0.8, 0.9)
                    wrap:SetScript("OnClick", function()
                        popup._forceCountChecked = not popup._forceCountChecked
                        if popup._forceCountChecked then mark:Show() else mark:Hide() end
                    end)
                    popup._forceCountCheck = wrap
                    popup._forceCountMark = mark
                end
                popup._forceCountChecked = false

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
                popup._status:SetText(EllesmereUI.L(text))
                popup._status:SetTextColor(r or 1, g or 0.3, b or 0.3, 1)
                if popup._statusTimer then popup._statusTimer:Cancel() end
                if text ~= "" then
                    popup._statusTimer = C_Timer.NewTimer(2.5, function()
                        popup._status:SetText("")
                    end)
                end
            end

            local isCustomBuffPopup = isCustomBuff

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
                -- 12.1: custom buffs are tracked as real auras -- no
                -- duration is asked or stored. Entries that already
                -- carry a stored duration are legacy cast-timer customs
                -- and keep that path untouched.
                -- Check if already tracked. Variant-aware, mirroring AddTrackedSpell's own
                -- dedup: an exact-only check lets a variant-duplicate through, which
                -- AddTrackedSpell then silently refuses AFTER the custom tag below is written (orphaned tag, nothing rendered).
                local sdChk = bd and ns.GetBarSpellData(bd.key)
                if sdChk and sdChk.assignedSpells then
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
                popup._dimmer:Hide()
                -- Tag as custom spell so ghost bar routing can skip it
                local sdTag = bd and ns.GetBarSpellData(bd.key)
                if sdTag then
                    if not sdTag.customSpellIDs then sdTag.customSpellIDs = {} end
                    sdTag.customSpellIDs[sid] = true
                    -- "Show Charges" opt-in (CD/utility only; custom auras skip it). Set/clear
                    -- explicitly so a re-add with the box unchecked can't leave a stale flag behind, and flip the runtime gate live.
                    if not isCustomBuffPopup then
                        if popup._forceCountChecked then
                            if not sdTag.customSpellForceCount then sdTag.customSpellForceCount = {} end
                            sdTag.customSpellForceCount[sid] = true
                            ns._cdmAnyCustomForceCount = true
                        elseif sdTag.customSpellForceCount then
                            sdTag.customSpellForceCount[sid] = nil
                        end
                    end
                end
                if ns.UpdateCustomBuffAuraTracking then ns.UpdateCustomBuffAuraTracking() end
                if onSelect then onSelect(sid, true) end
            end

            popup._addBtn:SetScript("OnClick", DoAdd)
            popup._editBox:SetScript("OnEnterPressed", DoAdd)
            popup._editBox:SetText("")
            popup._status:SetText("")
            if isCustomBuffPopup then
                -- Aura-tracked (12.1): same compact shape as CD/utility --
                -- no duration fields, no charges chrome.
                popup:SetHeight(164)
                popup._durLabel:Hide()
                popup._durBox:Hide()
                if popup._chargeWarn then popup._chargeWarn:Hide() end
                if popup._forceCountCheck then popup._forceCountCheck:Hide() end
            else
                popup:SetHeight(164)
                popup._durLabel:Hide()
                popup._durBox:Hide()
                -- CD/utility: the old "cannot track charges" note is replaced by the opt-in "Show Charges" toggle, reset unchecked each open.
                if popup._chargeWarn then popup._chargeWarn:Hide() end
                popup._forceCountChecked = false
                if popup._forceCountMark then popup._forceCountMark:Hide() end
                if popup._forceCountCheck then popup._forceCountCheck:Show() end
            end
            ns.PadPopupOpen(popup._dimmer, popup, popup._cancelBtn)  -- controller cursor
            popup._dimmer:Show()
            popup._editBox:SetFocus()
        end)

        allItems[#allItems + 1] = csItem
        mH = mH + ITEM_H
    end

    -- "Custom Item ID" option -- CD/utility bars only (custom aura bars are cast-timer
    -- driven and don't render item-cooldown frames). Adds an arbitrary item by item ID, stored as a negative marker (-itemID).
    if not isBuffBar and not isCustomBuff then
        local ciItem = CreateFrame("Button", nil, inner)
        ciItem:SetHeight(ITEM_H)
        ciItem:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
        ciItem:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
        ciItem:SetFrameLevel(menu:GetFrameLevel() + 2)

        local ciHl = ciItem:CreateTexture(nil, "ARTWORK")
        ciHl:SetAllPoints(); ciHl:SetColorTexture(1, 1, 1, 0); ciHl:SetAlpha(0)

        local ciLbl = ciItem:CreateFontString(nil, "OVERLAY")
        ciLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
        ciLbl:SetPoint("LEFT", 10, 0)
        ciLbl:SetJustifyH("LEFT")
        ciLbl:SetText(EllesmereUI.L("Custom Item ID"))
        ciLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)

        ciItem:SetScript("OnEnter", function()
            ciLbl:SetTextColor(1, 1, 1, 1)
            ciHl:SetColorTexture(1, 1, 1, hlA); ciHl:SetAlpha(1)
        end)
        ciItem:SetScript("OnLeave", function()
            ciLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
            ciHl:SetAlpha(0)
        end)
        ciItem:SetScript("OnClick", function()
            menu:Hide()
            ShowCustomItemIDPopup(bd and bd.key, function(marker)
                ns._cdmAnyCustomItem = true
                if onSelect then onSelect(marker, true) end
            end)
        end)

        allItems[#allItems + 1] = ciItem
        mH = mH + ITEM_H

        -- "Equipment Slot" option -- tracks whatever item is equipped in a slot the user
        -- picks by inventory slot ID (stored as -slotID, the trinket-slot encoding). Covers enchant/tinker use effects (e.g. Nitro Boosts on any belt) without re-adding per item.
        local esItem = CreateFrame("Button", nil, inner)
        esItem:SetHeight(ITEM_H)
        esItem:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
        esItem:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
        esItem:SetFrameLevel(menu:GetFrameLevel() + 2)

        local esHl = esItem:CreateTexture(nil, "ARTWORK")
        esHl:SetAllPoints(); esHl:SetColorTexture(1, 1, 1, 0); esHl:SetAlpha(0)

        local esLbl = esItem:CreateFontString(nil, "OVERLAY")
        esLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
        esLbl:SetPoint("LEFT", 10, 0)
        esLbl:SetJustifyH("LEFT")
        esLbl:SetText(EllesmereUI.L("Equipment Slot"))
        esLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)

        esItem:SetScript("OnEnter", function()
            esLbl:SetTextColor(1, 1, 1, 1)
            esHl:SetColorTexture(1, 1, 1, hlA); esHl:SetAlpha(1)
        end)
        esItem:SetScript("OnLeave", function()
            esLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
            esHl:SetAlpha(0)
        end)
        esItem:SetScript("OnClick", function()
            menu:Hide()
            ShowEquipmentSlotPopup(bd and bd.key, function(marker)
                if onSelect then onSelect(marker, true) end
            end)
        end)

        allItems[#allItems + 1] = esItem
        mH = mH + ITEM_H

        -- "Empty Slot" option -- adds a purely decorative placeholder that reserves a
        -- grid position (no spell/item behind it). Reorders/moves and removes exactly
        -- like any other tracked entry; each Add mints a fresh unique marker so several can sit on one bar.
        local eoItem = CreateFrame("Button", nil, inner)
        eoItem:SetHeight(ITEM_H)
        eoItem:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
        eoItem:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
        eoItem:SetFrameLevel(menu:GetFrameLevel() + 2)

        local eoHl = eoItem:CreateTexture(nil, "ARTWORK")
        eoHl:SetAllPoints(); eoHl:SetColorTexture(1, 1, 1, 0); eoHl:SetAlpha(0)

        local eoLbl = eoItem:CreateFontString(nil, "OVERLAY")
        eoLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
        eoLbl:SetPoint("LEFT", 10, 0)
        eoLbl:SetJustifyH("LEFT")
        eoLbl:SetText(EllesmereUI.L("Empty Slot"))
        eoLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)

        eoItem:SetScript("OnEnter", function()
            eoLbl:SetTextColor(1, 1, 1, 1)
            eoHl:SetColorTexture(1, 1, 1, hlA); eoHl:SetAlpha(1)
        end)
        eoItem:SetScript("OnLeave", function()
            eoLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
            eoHl:SetAlpha(0)
        end)
        eoItem:SetScript("OnClick", function()
            menu:Hide()
            EnsureAssignedSpells(barKey)
            ns.AddTrackedSpell(barKey, ns.NewEmptySlotMarker())
            RefreshCDPreview()
        end)

        allItems[#allItems + 1] = eoItem
        mH = mH + ITEM_H
    end

    if false then -- misc bar custom item menu removed
        -- Bag scan + Custom Item button (moved from bottom to top)
        local BAG_ITEM_BLACKLIST = {
            [234389] = true, [234390] = true, [249699] = true,
        }
        local MIN_CD_SEC = 30
        local MAX_CD_SEC = 660
        local ITEM_PRIORITY_NAMES = {
            "Trinket Slot 1", "Trinket Slot 2", "Light's Potential",
            "Potion of Recklessness", "Silvermoon Health Potion",
            "Lightfused Mana Potion", "Healthstone",
        }
        local ITEM_PRIORITY = {}
        for i, n in ipairs(ITEM_PRIORITY_NAMES) do ITEM_PRIORITY[n:lower()] = i end

        local _candidateItems = {}
        do
            local seen = {}
            for slotIdx = 13, 14 do
                local trinketID = GetInventoryItemID("player", slotIdx)
                if trinketID and not seen[trinketID] and not BAG_ITEM_BLACKLIST[trinketID] then
                    seen[trinketID] = true
                    local spellName, spellID = C_Item.GetItemSpell(trinketID)
                    if spellName and spellID then
                        _candidateItems[#_candidateItems + 1] = {
                            itemID = trinketID, spellName = spellName,
                            spellID = spellID, isTrinket = slotIdx,
                        }
                        C_Item.RequestLoadItemDataByID(trinketID)
                    end
                end
            end
            for bag = 0, 4 do
                local numSlots = C_Container.GetContainerNumSlots(bag)
                for slot = 1, numSlots do
                    local info = C_Container.GetContainerItemInfo(bag, slot)
                    if info and info.itemID and not seen[info.itemID] and not BAG_ITEM_BLACKLIST[info.itemID] then
                        seen[info.itemID] = true
                        local invType = C_Item.GetItemInventoryTypeByID(info.itemID)
                        local isTrinket = invType and invType == Enum.InventoryType.IndexTrinketType
                        if not isTrinket then
                            local spellName, spellID = C_Item.GetItemSpell(info.itemID)
                            if spellName and spellID then
                                _candidateItems[#_candidateItems + 1] = {
                                    itemID = info.itemID, spellName = spellName, spellID = spellID,
                                }
                                C_Item.RequestLoadItemDataByID(info.itemID)
                            end
                        end
                    end
                end
            end
        end

        local function ResolveBagItems()
            local results = {}
            local allResolved = true
            local _isEnglish = (GetLocale() == "enUS" or GetLocale() == "enGB")
            for _, cand in ipairs(_candidateItems) do
                local passFilter = false
                if cand.isTrinket then
                    passFilter = true
                elseif _isEnglish then
                    -- English: parse tooltip for cooldown duration
                    local tipData = C_TooltipInfo.GetItemByID(cand.itemID)
                    if tipData and tipData.lines then
                        for _, line in ipairs(tipData.lines) do
                            local text = line.leftText
                            if text and text:find("Cooldown%)") then
                                local cdStr = text:match(".*%((.+Cooldown)%)")
                                if cdStr then
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
                                    if totalSec >= MIN_CD_SEC and totalSec <= MAX_CD_SEC then passFilter = true end
                                    break
                                end
                            end
                        end
                    else
                        allResolved = false
                    end
                elseif cand.spellID and cand.spellID > 0 then
                    -- Non-English: any item with a spell effect passes
                    passFilter = true
                end
                do
                    if passFilter then
                        local tex = C_Item.GetItemIconByID(cand.itemID)
                        local itemName = C_Item.GetItemNameByID(cand.itemID)
                        local displayName
                        if cand.isTrinket then
                            displayName = (itemName or cand.spellName) .. " (Trinket " .. (cand.isTrinket - 12) .. ")"
                        else
                            displayName = itemName or cand.spellName
                        end
                        results[#results + 1] = {
                            itemID = cand.itemID, name = displayName,
                            icon = tex, spellID = cand.spellID, isTrinket = cand.isTrinket,
                        }
                    end
                end
            end
            local PRIORITY_COUNT = #ITEM_PRIORITY_NAMES
            table.sort(results, function(a, b)
                local aKey = a.isTrinket and ("trinket slot " .. (a.isTrinket - 12)) or a.name:lower()
                local bKey = b.isTrinket and ("trinket slot " .. (b.isTrinket - 12)) or b.name:lower()
                local aPri = ITEM_PRIORITY[aKey] or (PRIORITY_COUNT + 1)
                local bPri = ITEM_PRIORITY[bKey] or (PRIORITY_COUNT + 1)
                if aPri ~= bPri then return aPri < bPri end
                return a.name < b.name
            end)
            optState._cachedBagItems = results
            optState._bagScanComplete = allResolved
            return allResolved
        end
        ResolveBagItems()
        if not optState._bagScanComplete then
            local attempts = 0
            local ticker
            ticker = C_Timer.NewTicker(0.2, function()
                attempts = attempts + 1
                local done = ResolveBagItems()
                if done or attempts >= 25 then
                    if ticker then ticker:Cancel() end
                    optState._bagScanComplete = true
                    if optState._customTrackingSub and optState._customTrackingSub:IsShown() then
                        optState._customTrackingSub._needsRebuild = true
                    end
                elseif optState._customTrackingSub and optState._customTrackingSub:IsShown() then
                    optState._customTrackingSub._needsRebuild = true
                end
            end)
            menu:HookScript("OnHide", function()
                if ticker then ticker:Cancel(); ticker = nil end
            end)
        end

        local ctItem = CreateFrame("Button", nil, inner)
        ctItem:SetHeight(ITEM_H)
        ctItem:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
        ctItem:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
        ctItem:SetFrameLevel(menu:GetFrameLevel() + 2)
        local ctHl = ctItem:CreateTexture(nil, "ARTWORK")
        ctHl:SetAllPoints(); ctHl:SetColorTexture(1, 1, 1, 0); ctHl:SetAlpha(0)
        local ctLbl = ctItem:CreateFontString(nil, "OVERLAY")
        ctLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
        ctLbl:SetPoint("LEFT", 10, 0); ctLbl:SetJustifyH("LEFT")
        ctLbl:SetText(EllesmereUI.L("Custom Item"))
        ctLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
        local ctArrow = ctItem:CreateTexture(nil, "ARTWORK")
        ctArrow:SetSize(10, 10)
        ctArrow:SetPoint("RIGHT", ctItem, "RIGHT", -8, 0)
        ctArrow:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\right-arrow.png")
        ctArrow:SetAlpha(0.7)

        local function ShowCustomTrackingSub()
            local items = optState._cachedBagItems or {}
            local alreadyTracked = {}
            local sdCT = bd and ns.GetBarSpellData(bd.key)
            if sdCT and sdCT.assignedSpells then
                for _, sid in ipairs(sdCT.assignedSpells) do
                    if sid <= -100 then alreadyTracked[-sid] = true end
                end
            end
            local filtered = {}
            for _, it in ipairs(items) do
                if not alreadyTracked[it.itemID] then filtered[#filtered + 1] = it end
            end
            local prevCount = optState._customTrackingSub and optState._customTrackingSub._itemCount or -1
            if not optState._customTrackingSub then
                optState._customTrackingSub = CreateFrame("Frame", nil, UIParent)
                optState._customTrackingSub:SetFrameStrata("FULLSCREEN_DIALOG")
                optState._customTrackingSub:SetFrameLevel(menu:GetFrameLevel() + 5)
                optState._customTrackingSub:SetClampedToScreen(true)
                optState._customTrackingSub:EnableMouse(true)
            elseif optState._customTrackingSub:IsShown() and #filtered == prevCount and not optState._customTrackingSub._needsRebuild then
                return
            else
                for _, child in ipairs({optState._customTrackingSub:GetChildren()}) do child:Hide(); child:SetParent(nil) end
                for _, rgn in ipairs({optState._customTrackingSub:GetRegions()}) do if rgn.Hide then rgn:Hide() end end
            end
            optState._customTrackingSub._itemCount = #filtered
            optState._customTrackingSub._needsRebuild = false
            local subW = 220
            local SUB_ITEM_H = 26
            local SUB_MAX_H = 260
            -- Item captions collected as the rows are built, so the frame can be
            -- widened to the longest bag-item name instead of ellipsising it.
            local subLabels = {}
            optState._customTrackingSub:SetSize(subW, 10)
            optState._customTrackingSub:ClearAllPoints()
            optState._customTrackingSub:SetPoint("TOPLEFT", ctItem, "TOPRIGHT", 2, 0)
            local subBg = optState._customTrackingSub:CreateTexture(nil, "BACKGROUND")
            subBg:SetAllPoints(); subBg:SetColorTexture(mBgR, mBgG, mBgB, mBgA)
            EllesmereUI.MakeBorder(optState._customTrackingSub, 1, 1, 1, mBrdA, EllesmereUI.PP)
            local subInner = CreateFrame("Frame", nil, optState._customTrackingSub)
            subInner:SetWidth(subW); subInner:SetPoint("TOPLEFT")
            local subH = 4
            if #filtered == 0 then
                local loadingText = (not optState._bagScanComplete) and "Loading items..." or "No on-use items in bags"
                local emptyLbl = subInner:CreateFontString(nil, "OVERLAY")
                emptyLbl:SetFont(FONT_PATH, 10, GetCDMOptOutline())
                emptyLbl:SetPoint("TOPLEFT", subInner, "TOPLEFT", 10, -subH - 4)
                emptyLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA * 0.6)
                emptyLbl:SetText(loadingText)
                subH = subH + SUB_ITEM_H
            else
                for _, it in ipairs(filtered) do
                    local si = CreateFrame("Button", nil, subInner)
                    si:SetHeight(SUB_ITEM_H)
                    si:SetPoint("TOPLEFT", subInner, "TOPLEFT", 1, -subH)
                    si:SetPoint("TOPRIGHT", subInner, "TOPRIGHT", -1, -subH)
                    si:SetFrameLevel(optState._customTrackingSub:GetFrameLevel() + 2)
                    si:RegisterForClicks("AnyUp")
                    local sIco = si:CreateTexture(nil, "ARTWORK")
                    local icoSz = SUB_ITEM_H - 2
                    sIco:SetSize(icoSz, icoSz)
                    sIco:SetPoint("RIGHT", si, "RIGHT", -6, 0)
                    if it.icon then sIco:SetTexture(it.icon) end
                    sIco:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    local sLbl = si:CreateFontString(nil, "OVERLAY")
                    sLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                    sLbl:SetPoint("LEFT", si, "LEFT", 10, 0)
                    sLbl:SetPoint("RIGHT", sIco, "LEFT", -5, 0)
                    sLbl:SetJustifyH("LEFT"); sLbl:SetWordWrap(false); sLbl:SetMaxLines(1)
                    sLbl:SetText(EllesmereUI.L(it.name)); sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                    subLabels[#subLabels + 1] = sLbl
                    local sHl = si:CreateTexture(nil, "ARTWORK")
                    sHl:SetAllPoints(); sHl:SetColorTexture(1, 1, 1, 0); sHl:SetAlpha(0)
                    si:SetScript("OnEnter", function()
                        sLbl:SetTextColor(1, 1, 1, 1); sHl:SetColorTexture(1, 1, 1, hlA); sHl:SetAlpha(1)
                    end)
                    si:SetScript("OnLeave", function()
                        sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA); sHl:SetAlpha(0)
                    end)
                    si:SetScript("OnClick", function()
                        optState._customTrackingSub:Hide(); menu:Hide()
                        if onSelect then onSelect(-it.itemID, true) end
                    end)
                    subH = subH + SUB_ITEM_H
                end
            end
            -- Widen to the longest item name (pad leaves room for the text inset
            -- and the row's right-hand item icon).
            subW = FitMenuWidth(subLabels, subW, 48)
            optState._customTrackingSub:SetWidth(subW)
            subInner:SetWidth(subW)
            local totalSubH = subH + 4
            subInner:SetHeight(totalSubH)
            if totalSubH > SUB_MAX_H then
                optState._customTrackingSub:SetHeight(SUB_MAX_H)
                local sf = CreateFrame("ScrollFrame", nil, optState._customTrackingSub)
                sf:SetPoint("TOPLEFT"); sf:SetPoint("BOTTOMRIGHT")
                sf:SetFrameLevel(optState._customTrackingSub:GetFrameLevel() + 1)
                sf:EnableMouseWheel(true); sf:SetScrollChild(subInner)
                subInner:SetWidth(subW)
                EllesmereUI.AttachSmoothScrollbar(sf, { step = 40, thumb = false })
            else
                optState._customTrackingSub:SetHeight(totalSubH)
                subInner:SetParent(optState._customTrackingSub); subInner:SetPoint("TOPLEFT")
            end
            optState._customTrackingSub:SetScript("OnLeave", function(self)
                C_Timer.After(0.1, function()
                    if self:IsShown() and not self:IsMouseOver() and not ctItem:IsMouseOver() then self:Hide() end
                end)
            end)
            if not optState._bagScanComplete then
                optState._customTrackingSub:SetScript("OnUpdate", function(self)
                    if self._needsRebuild then ShowCustomTrackingSub() end
                    if optState._bagScanComplete then self:SetScript("OnUpdate", nil) end
                end)
            else
                optState._customTrackingSub:SetScript("OnUpdate", nil)
            end
            optState._customTrackingSub:Show()
        end

        ctItem:SetScript("OnEnter", function()
            ctLbl:SetTextColor(1, 1, 1, 1); ctHl:SetColorTexture(1, 1, 1, hlA); ctHl:SetAlpha(1)
            ShowCustomTrackingSub()
        end)
        ctItem:SetScript("OnLeave", function()
            ctLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA); ctHl:SetAlpha(0)
            C_Timer.After(0.15, function()
                if optState._customTrackingSub and optState._customTrackingSub:IsShown()
                   and not optState._customTrackingSub:IsMouseOver() and not ctItem:IsMouseOver() then
                    optState._customTrackingSub:Hide()
                end
            end)
        end)

        allItems[#allItems + 1] = ctItem
        mH = mH + ITEM_H
    end

    if not isBuffBar and not isCustomBuff then
        -- Divider below Custom Spell ID (CD/utility bars only -- custom buff bars have their own divider before presets)
        local csDiv = inner:CreateTexture(nil, "ARTWORK")
        csDiv:SetHeight(1)
        csDiv:SetColorTexture(1, 1, 1, 0.10)
        csDiv:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
        csDiv:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
        mH = mH + 9
    end

    -- Trinket slots + potion presets for CD/utility bars only (not buff bars, not custom buff bars)
    if not isBuffBar and not isCustomBuff then
        -- Build already-tracked set (this bar + other bars)
        local alreadyOnBar = {}
        local usedOnOtherBar = {}  -- [sid] = barName
        local sdTrk = bd and ns.GetBarSpellData(bd.key)
        if sdTrk and sdTrk.assignedSpells then
            for _, sid in ipairs(sdTrk.assignedSpells) do alreadyOnBar[sid] = true end
        end
        -- Check all other non-buff bars for cross-bar duplicate detection
        local prof = ns.ECME and ns.ECME.db and ns.ECME.db.profile
        if prof and prof.cdmBars and prof.cdmBars.bars then
            for _, otherBar in ipairs(prof.cdmBars.bars) do
                if otherBar.key ~= barKey then
                    local otherType = otherBar.barType or otherBar.key
                    if otherType ~= "buffs" then
                        local osd = ns.GetBarSpellData(otherBar.key)
                        if osd and osd.assignedSpells then
                            for _, sid in ipairs(osd.assignedSpells) do
                                if sid and sid ~= 0 and not usedOnOtherBar[sid] then
                                    usedOnOtherBar[sid] = otherBar.name or otherBar.key
                                end
                            end
                        end
                    end
                end
            end
        end

        -- Trinket Slot 1 & 2
        for _, slot in ipairs({13, 14}) do
            local negSlot = -(slot)
            local itemID = GetInventoryItemID("player", slot)
            local label = EllesmereUI.L((slot == 13) and "Trinket Slot 1" or "Trinket Slot 2")
            local tex = itemID and C_Item.GetItemIconByID(itemID)
            local isAdded = alreadyOnBar[negSlot]
            -- Only gray out if it's already on THIS bar. Presets on OTHER bars stay claimable -- AddTrackedSpell auto-moves them, exactly like regular spells.
            local otherBarName = not isAdded and usedOnOtherBar[negSlot]
            local isDisabled = isAdded

            local ti = CreateFrame("Button", nil, inner)
            ti:SetHeight(ITEM_H)
            ti:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
            ti:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
            ti:SetFrameLevel(menu:GetFrameLevel() + 2)

            local tiLbl = ti:CreateFontString(nil, "OVERLAY")
            tiLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            tiLbl:SetPoint("LEFT", 10, 0)
            tiLbl:SetJustifyH("LEFT")
            tiLbl:SetText(label)

            if tex then
                local tiIco = ti:CreateTexture(nil, "ARTWORK")
                tiIco:SetSize(ITEM_H - 2, ITEM_H - 2)
                tiIco:SetPoint("RIGHT", ti, "RIGHT", -6, 0)
                tiIco:SetTexture(tex)
                tiIco:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                if isDisabled then tiIco:SetDesaturated(true); tiIco:SetAlpha(0.4) end
            end

            local tiHl = ti:CreateTexture(nil, "ARTWORK")
            tiHl:SetAllPoints(); tiHl:SetColorTexture(1, 1, 1, 0); tiHl:SetAlpha(0)

            if isDisabled then
                tiLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA * 0.4)
                local tooltipName = isAdded and (bd and (bd.name or bd.key) or barKey) or otherBarName
                ti:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(ti, EllesmereUI.Lf("Already on %s", EllesmereUI.L(tooltipName)))
                end)
                ti:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            else
                tiLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                ti:SetScript("OnEnter", function()
                    tiLbl:SetTextColor(1, 1, 1, 1)
                    tiHl:SetColorTexture(1, 1, 1, hlA); tiHl:SetAlpha(1)
                end)
                ti:SetScript("OnLeave", function()
                    tiLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                    tiHl:SetAlpha(0)
                end)
                ti:SetScript("OnClick", function()
                    menu:Hide()
                    EnsureAssignedSpells(barKey)
                    ns.AddTrackedSpell(barKey, negSlot)
                    RefreshCDPreview()
                end)
            end
            allItems[#allItems + 1] = ti
            mH = mH + ITEM_H
        end

        -- Racial ability: one generic "Racial" entry that follows the character's race.
        -- Adds this character's active racial spell ID; ns.NormalizeRacialAssignments rewrites it on every other race so a shared profile only needs the racial added once.
        local rSid = ns._activeRacialSpellID
        if rSid then
            local rTex = C_Spell.GetSpellTexture(rSid)
            local isAdded = alreadyOnBar[rSid]
            local rOtherBar = not isAdded and usedOnOtherBar[rSid]
            local rIsDisabled = isAdded  -- other bars stay claimable (auto-move)
            local ri = CreateFrame("Button", nil, inner)
            ri:SetHeight(ITEM_H)
            ri:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
            ri:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
            ri:SetFrameLevel(menu:GetFrameLevel() + 2)
            local riLbl = ri:CreateFontString(nil, "OVERLAY")
            riLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            riLbl:SetPoint("LEFT", 10, 0)
            riLbl:SetJustifyH("LEFT")
            riLbl:SetText(EllesmereUI.L("Racial"))
            if rTex then
                local riIco = ri:CreateTexture(nil, "ARTWORK")
                riIco:SetSize(ITEM_H - 2, ITEM_H - 2)
                riIco:SetPoint("RIGHT", ri, "RIGHT", -6, 0)
                riIco:SetTexture(rTex)
                riIco:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                if rIsDisabled then riIco:SetDesaturated(true); riIco:SetAlpha(0.4) end
            end
            local riHl = ri:CreateTexture(nil, "ARTWORK")
            riHl:SetAllPoints(); riHl:SetColorTexture(1, 1, 1, 0); riHl:SetAlpha(0)
            if rIsDisabled then
                riLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA * 0.4)
                local rTooltipName = isAdded and (bd and (bd.name or bd.key) or barKey) or rOtherBar
                ri:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(ri, EllesmereUI.Lf("Already on %s", EllesmereUI.L(rTooltipName)))
                end)
                ri:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            else
                riLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                ri:SetScript("OnEnter", function()
                    riLbl:SetTextColor(1, 1, 1, 1)
                    riHl:SetColorTexture(1, 1, 1, hlA); riHl:SetAlpha(1)
                end)
                ri:SetScript("OnLeave", function()
                    riLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                    riHl:SetAlpha(0)
                end)
                ri:SetScript("OnClick", function()
                    menu:Hide()
                    EnsureAssignedSpells(barKey)
                    ns.AddTrackedSpell(barKey, rSid)
                    RefreshCDPreview()
                end)
            end
            allItems[#allItems + 1] = ri
            mH = mH + ITEM_H
        end

        -- "Potions & Healthstone" flyout subnav
        local _potionsSub
        menu._potionsSub = nil  -- reference for OnUpdate close-check
        local itemPresets = ns.CDM_ITEM_PRESETS
        if itemPresets and #itemPresets > 0 then
            local potItem = CreateFrame("Button", nil, inner)
            potItem:SetHeight(ITEM_H)
            potItem:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
            potItem:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
            potItem:SetFrameLevel(menu:GetFrameLevel() + 2)

            local potHl = potItem:CreateTexture(nil, "ARTWORK")
            potHl:SetAllPoints(); potHl:SetColorTexture(1, 1, 1, 0); potHl:SetAlpha(0)

            local potLbl = potItem:CreateFontString(nil, "OVERLAY")
            potLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            potLbl:SetPoint("LEFT", 10, 0)
            potLbl:SetJustifyH("LEFT")
            potLbl:SetText(EllesmereUI.L("Potions & Healthstone"))
            potLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)

            local potArrow = potItem:CreateTexture(nil, "ARTWORK")
            potArrow:SetSize(10, 10)
            potArrow:SetPoint("RIGHT", potItem, "RIGHT", -8, 0)
            potArrow:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\right-arrow.png")
            potArrow:SetAlpha(0.7)

            local function ShowPotionsSub()
                if not _potionsSub then
                    _potionsSub = CreateFrame("Frame", nil, menu)
                    menu._potionsSub = _potionsSub
                    _potionsSub:SetFrameStrata("FULLSCREEN_DIALOG")
                    _potionsSub:SetFrameLevel(menu:GetFrameLevel() + 5)
                    _potionsSub:SetClampedToScreen(true)
                    _potionsSub:EnableMouse(true)
                elseif _potionsSub:IsShown() then
                    return
                else
                    for _, child in ipairs({_potionsSub:GetChildren()}) do
                        child:Hide(); child:SetParent(nil)
                    end
                    for _, rgn in ipairs({_potionsSub:GetRegions()}) do
                        if rgn.Hide then rgn:Hide() end
                    end
                end

                local subW = 220
                local SUB_ITEM_H = 26
                -- Captions collected as the rows are built so the frame can be
                -- widened to the longest preset name instead of ellipsising it.
                local subLabels = {}
                _potionsSub:SetSize(subW, 10)
                _potionsSub:ClearAllPoints()
                _potionsSub:SetPoint("TOPLEFT", potItem, "TOPRIGHT", 2, 0)

                local subBg = _potionsSub:CreateTexture(nil, "BACKGROUND")
                subBg:SetAllPoints()
                subBg:SetColorTexture(mBgR, mBgG, mBgB, mBgA)
                EllesmereUI.MakeBorder(_potionsSub, 1, 1, 1, mBrdA, EllesmereUI.PP)

                local subInner = CreateFrame("Frame", nil, _potionsSub)
                subInner:SetWidth(subW)
                subInner:SetPoint("TOPLEFT")

                local subH = 4
                for _, preset in ipairs(itemPresets) do
                    do
                    local pID = -(preset.itemID)
                    local isAdded = alreadyOnBar[pID]
                    local pOtherBar = not isAdded and usedOnOtherBar[pID]
                    local pIsDisabled = isAdded  -- other bars stay claimable (auto-move)

                    local si = CreateFrame("Button", nil, subInner)
                    si:SetHeight(SUB_ITEM_H)
                    si:SetPoint("TOPLEFT", subInner, "TOPLEFT", 1, -subH)
                    si:SetPoint("TOPRIGHT", subInner, "TOPRIGHT", -1, -subH)
                    si:SetFrameLevel(_potionsSub:GetFrameLevel() + 2)
                    si:RegisterForClicks("AnyUp")

                    local sIco = si:CreateTexture(nil, "ARTWORK")
                    local icoSz = SUB_ITEM_H - 2
                    sIco:SetSize(icoSz, icoSz)
                    sIco:SetPoint("RIGHT", si, "RIGHT", -6, 0)
                    sIco:SetTexture(EllesmereUI.ClientIcon(preset.icon or (preset.itemID and C_Item.GetItemIconByID(preset.itemID))))
                    sIco:SetTexCoord(0.08, 0.92, 0.08, 0.92)

                    local sLbl = si:CreateFontString(nil, "OVERLAY")
                    sLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                    sLbl:SetPoint("LEFT", si, "LEFT", 10, 0)
                    sLbl:SetPoint("RIGHT", sIco, "LEFT", -5, 0)
                    sLbl:SetJustifyH("LEFT")
                    sLbl:SetWordWrap(false)
                    sLbl:SetMaxLines(1)
                    sLbl:SetText(EllesmereUI.L(preset.name))
                    subLabels[#subLabels + 1] = sLbl

                    local sHl = si:CreateTexture(nil, "ARTWORK")
                    sHl:SetAllPoints()
                    sHl:SetColorTexture(1, 1, 1, 0); sHl:SetAlpha(0)

                    if pIsDisabled then
                        sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA * 0.4)
                        sIco:SetDesaturated(true)
                        sIco:SetAlpha(0.4)
                        local pTooltipName = isAdded and (bd and (bd.name or bd.key) or barKey) or pOtherBar
                        si:SetScript("OnEnter", function()
                            EllesmereUI.ShowWidgetTooltip(si, EllesmereUI.Lf("Already on %s", EllesmereUI.L(pTooltipName)))
                        end)
                        si:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                    else
                        sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                        si:SetScript("OnEnter", function()
                            sLbl:SetTextColor(1, 1, 1, 1)
                            sHl:SetColorTexture(1, 1, 1, hlA); sHl:SetAlpha(1)
                        end)
                        si:SetScript("OnLeave", function()
                            sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                            sHl:SetAlpha(0)
                        end)
                        si:SetScript("OnClick", function()
                            _potionsSub:Hide()
                            menu:Hide()
                            EnsureAssignedSpells(barKey)
                            ns.AddTrackedSpell(barKey, pID)
                            RefreshCDPreview()
                        end)
                    end
                    subH = subH + SUB_ITEM_H
                    end -- healthstone filter
                end

                -- Widen to the longest preset name (pad leaves room for the text
                -- inset and the row's right-hand item icon).
                subW = FitMenuWidth(subLabels, subW, 48)
                _potionsSub:SetWidth(subW)
                subInner:SetWidth(subW)
                local totalSubH = subH + 4
                subInner:SetHeight(totalSubH)
                _potionsSub:SetHeight(totalSubH)
                subInner:SetParent(_potionsSub)
                subInner:SetPoint("TOPLEFT")
                _potionsSub:Show()
            end

            potItem:SetScript("OnEnter", function()
                potLbl:SetTextColor(1, 1, 1, 1)
                potHl:SetColorTexture(1, 1, 1, hlA); potHl:SetAlpha(1)
                ShowPotionsSub()
            end)
            potItem:SetScript("OnLeave", function()
                potLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                potHl:SetAlpha(0)
                C_Timer.After(0.3, function()
                    if _potionsSub and _potionsSub:IsShown() and not _potionsSub:IsMouseOver() and not potItem:IsMouseOver() then
                        _potionsSub:Hide()
                    end
                end)
            end)

            allItems[#allItems + 1] = potItem
            mH = mH + ITEM_H
        end

        -- Divider after trinkets/potions
        local trDiv = inner:CreateTexture(nil, "ARTWORK")
        trDiv:SetHeight(1)
        trDiv:SetColorTexture(1, 1, 1, 0.10)
        trDiv:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
        trDiv:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
        mH = mH + 9
    end

    -- Presets (Heroism, potions, etc.) -- flat list in custom buff bar picker.
    -- Skipped with its divider when the list is empty (WoW Forever has none).
    if isCustomBuff and #ns.BUFF_BAR_PRESETS > 0 then
        -- Divider before presets
        local psDiv = inner:CreateTexture(nil, "ARTWORK")
        psDiv:SetHeight(1)
        psDiv:SetColorTexture(1, 1, 1, 0.10)
        psDiv:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
        psDiv:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
        mH = mH + 9

        local _, _pClass = UnitClass("player")
        for _, preset in ipairs(ns.BUFF_BAR_PRESETS) do
            -- tbbOnly presets are excluded here UNLESS they opt in via
            -- customAuraToo (debuff-driven Bloodlust: rendered as a 40s
            -- self-timed icon, armed off the Sated edge instead of a cast).
            if (not preset.class or preset.class == _pClass)
                and (not preset.tbbOnly or preset.customAuraToo) then
                local isAdded = ns.IsPresetOnBar(barKey, preset)

                local si = CreateFrame("Button", nil, inner)
                si:SetHeight(ITEM_H)
                si:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
                si:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
                si:SetFrameLevel(menu:GetFrameLevel() + 2)

                local sIco = si:CreateTexture(nil, "ARTWORK")
                local icoSz = ITEM_H - 2
                sIco:SetSize(icoSz, icoSz)
                sIco:SetPoint("RIGHT", si, "RIGHT", -6, 0)
                sIco:SetTexture(EllesmereUI.ClientIcon(preset.icon))
                sIco:SetTexCoord(0.08, 0.92, 0.08, 0.92)

                local sLbl = si:CreateFontString(nil, "OVERLAY")
                sLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                sLbl:SetPoint("LEFT", si, "LEFT", 10, 0)
                sLbl:SetPoint("RIGHT", sIco, "LEFT", -5, 0)
                sLbl:SetJustifyH("LEFT")
                sLbl:SetWordWrap(false); sLbl:SetMaxLines(1)
                sLbl:SetText(EllesmereUI.L(preset.name))

                local sHl = si:CreateTexture(nil, "ARTWORK")
                sHl:SetAllPoints(); sHl:SetColorTexture(1, 1, 1, 0); sHl:SetAlpha(0)

                if isAdded then
                    sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA * 0.4)
                    sIco:SetDesaturated(true); sIco:SetAlpha(0.4)
                else
                    sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                    si:SetScript("OnEnter", function()
                        sLbl:SetTextColor(1, 1, 1, 1)
                        sHl:SetColorTexture(1, 1, 1, hlA); sHl:SetAlpha(1)
                    end)
                    si:SetScript("OnLeave", function()
                        sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                        sHl:SetAlpha(0)
                    end)
                    si:SetScript("OnClick", function()
                        menu:Hide()
                        EnsureAssignedSpells(barKey)
                        ns.AddPresetToBar(barKey, preset)
                        -- Arm the shared Sated listener now (debuff-driven
                        -- presets like Bloodlust); no-op for cooldown presets.
                        if ns.UpdateLustListener then ns.UpdateLustListener() end
                        RefreshCDPreview()
                    end)
                end

                allItems[#allItems + 1] = si
                mH = mH + ITEM_H
            end
        end
    end

    local function MakeItem(sp, isDisabled)
        -- Check if this spell belongs to the wrong category group for this bar type.
        local wrongCatGroup = false
        if not isDisabled and sp.cdmCatGroup then
            if isBuffBar and sp.cdmCatGroup == "cooldown" then
                wrongCatGroup = true
            elseif not isBuffBar and sp.cdmCatGroup == "buff" then
                wrongCatGroup = true
            end
        end
        local item = CreateFrame("Button", nil, inner)
        item:SetHeight(ITEM_H)
        item:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
        item:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
        item:SetFrameLevel(menu:GetFrameLevel() + 2)

        local ico = item:CreateTexture(nil, "ARTWORK")
        local icoSz = ITEM_H - 2
        ico:SetSize(icoSz, icoSz)
        ico:SetPoint("RIGHT", item, "RIGHT", -6, 0)
        if sp.icon then ico:SetTexture(sp.icon) end
        local zoom = 0.08
        ico:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)

        local lbl = item:CreateFontString(nil, "OVERLAY")
        lbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
        lbl:SetPoint("LEFT", 10, 0)
        lbl:SetPoint("RIGHT", ico, "LEFT", -5, 0)
        lbl:SetJustifyH("LEFT")
        lbl:SetWordWrap(false)
        lbl:SetMaxLines(1)
        lbl:SetText(EllesmereUI.L(sp.name))

        local hl = item:CreateTexture(nil, "ARTWORK")
        hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0); hl:SetAlpha(0)

        -- Check if this spell is already on THIS bar (only gray-out we
        -- still do for CD/util/buff custom bars). Spells on OTHER bars
        -- are always claimable -- AddTrackedSpell auto-moves them.
        local onThisBar = not isDisabled and excludeSet
            and (excludeSet[sp.cdID] or excludeSet[sp.spellID])

        -- Apply the grayed "already on this bar" appearance and swap the row
        -- to its non-interactive state. Used both for spells already present
        -- when the picker opens AND for spells the user just clicked to add
        -- (the picker stays open so several can be added in a row).
        local barName = bd and (bd.name or bd.key) or barKey
        local function MarkOnThisBar()
            lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA * 0.4)
            ico:SetDesaturated(true)
            ico:SetAlpha(0.4)
            item:SetScript("OnClick", nil)
            item:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(item, EllesmereUI.Lf("This spell is already being used on %s", EllesmereUI.L(barName)))
                hl:SetColorTexture(1, 1, 1, hlA * 0.3); hl:SetAlpha(1)
            end)
            item:SetScript("OnLeave", function()
                EllesmereUI.HideWidgetTooltip()
                hl:SetAlpha(0)
            end)
        end

        if isDisabled then
            lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA * 0.4)
            ico:SetDesaturated(true)
            ico:SetAlpha(0.4)
        elseif onThisBar then
            -- Already on this bar: grayed out with tooltip
            MarkOnThisBar()
        else
            lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
            -- Tracked-but-untalented spells stay fully clickable but
            -- render desaturated with a hint, so whole layouts can be
            -- arranged without swapping talents.
            local notLearned = (sp.isKnown == false)
            if notLearned then
                ico:SetDesaturated(true)
                ico:SetAlpha(0.5)
            end
            item:SetScript("OnEnter", function()
                lbl:SetTextColor(1, 1, 1, 1)
                hl:SetColorTexture(1, 1, 1, hlA); hl:SetAlpha(1)
                if notLearned then
                    EllesmereUI.ShowWidgetTooltip(item, EllesmereUI.L("Not currently talented"))
                end
            end)
            item:SetScript("OnLeave", function()
                lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                hl:SetAlpha(0)
                if notLearned then EllesmereUI.HideWidgetTooltip() end
            end)
            item:SetScript("OnClick", function()
                if wrongCatGroup then
                    menu:Hide()
                    ShowWrongBarTypePopup(sp.name, sp.cdmCatGroup == "buff")
                    return
                end
                -- Always pass spellID (assignedSpells stores spellIDs)
                if onSelect then onSelect(sp.spellID, sp.isExtra) end
                -- Keep the picker open so multiple spells can be added in a
                -- row; gray this row in place to reflect that it was added.
                if notLearned then EllesmereUI.HideWidgetTooltip() end
                MarkOnThisBar()
            end)
        end

        allItems[#allItems + 1] = item
        mH = mH + ITEM_H
    end

    local function MakeDivider()
        local div = inner:CreateTexture(nil, "ARTWORK")
        div:SetHeight(1)
        div:SetColorTexture(1, 1, 1, 0.10)
        div:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
        div:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
        mH = mH + 9
    end

    -- Custom buff bars only show Custom Spell ID entry -- no CDM spell list
    if isCustomBuff then
        -- Nothing to render -- Custom Spell ID option is already above
    elseif isCDorUtil then
        -- Layout: Primary (unassigned first, then assigned)
        -- -> Secondary (unassigned first, then assigned)
        -- -> Not Tracked (unlearned or removed from Blizzard CDM)
        local hasPri = #priUnassigned > 0 or #priAssigned > 0
        local hasSec = #secUnassigned > 0 or #secAssigned > 0
        local hasNotTracked = #notTracked > 0
        local needDiv = false

        if hasPri then
            for _, sp in ipairs(priUnassigned) do MakeItem(sp, false) end
            for _, sp in ipairs(priAssigned) do MakeItem(sp, false) end
            needDiv = true
        end

        if hasSec then
            if needDiv then MakeDivider() end
            for _, sp in ipairs(secUnassigned) do MakeItem(sp, false) end
            for _, sp in ipairs(secAssigned) do MakeItem(sp, false) end
            needDiv = true
        end

        if hasNotTracked then
            if needDiv then MakeDivider() end
            table.sort(notTracked, function(a, b)
                return (a.name or "") < (b.name or "")
            end)
            for _, sp in ipairs(notTracked) do MakeItem(sp, false) end
        end
    else
        -- Original layout for buff/trinket/other bars
        for _, sp in ipairs(itemsDisplayed) do MakeItem(sp, false) end

        if #itemsDisplayed > 0 and #itemsExtra > 0 then MakeDivider() end

        for _, sp in ipairs(itemsExtra) do MakeItem(sp, false) end
    end

    -- "Missing Spells?" footer: centered accent prompt that opens Blizzard's
    -- CDM and closes EUI options (same action as the link under the buff bar
    -- preview). Shown for bars that list Blizzard CDM spells (CD/utility and
    -- buff); skipped for custom-buff bars (Custom Spell ID only, no CDM list).
    if not isCustomBuff then
        MakeDivider()
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

        allItems[#allItems + 1] = mbItem
        mH = mH + FOOTER_H
    end

    local totalH = mH + 4
    inner:SetHeight(totalH)

    -- Scrollable if needed
    if totalH > MAX_H then
        menu:SetHeight(MAX_H)
        local sf = CreateFrame("ScrollFrame", nil, menu)
        sf:SetPoint("TOPLEFT"); sf:SetPoint("BOTTOMRIGHT")
        sf:SetFrameLevel(menu:GetFrameLevel() + 1)
        sf:EnableMouseWheel(true)
        sf:SetScrollChild(inner)
        inner:SetWidth(menuW)
        EllesmereUI.AttachSmoothScrollbar(sf, { step = 40, thumb = false })
    else
        menu:SetHeight(totalH)
        inner:SetParent(menu)
        inner:SetPoint("TOPLEFT")
    end

    -- Position near anchor
    menu:ClearAllPoints()
    menu:SetPoint("TOP", anchorFrame, "BOTTOM", 0, -2)

    -- Close on left-click outside (non-blocking, preserves world interactions)
    menu:SetScript("OnUpdate", function(m)
        local overSub = (optState._customTrackingSub and optState._customTrackingSub:IsShown() and optState._customTrackingSub:IsMouseOver())
            or (m._potionsSub and m._potionsSub:IsShown() and m._potionsSub:IsMouseOver())
        if not m:IsMouseOver() and not anchorFrame:IsMouseOver() and not overSub and IsMouseButtonDown("LeftButton") then
            m:Hide()
        end
    end)
    menu:HookScript("OnHide", function(m)
        m:SetScript("OnUpdate", nil)
        if optState._customTrackingSub then optState._customTrackingSub:Hide() end
        -- Per-icon cog settings for racials/pots/trinkets are edited in this
        -- menu; propagate them to synced specs when it closes.
        if ns.MaybePropagateRPT then ns.MaybePropagateRPT() end
    end)

    menu:Show()
    optState._spellPickerMenu = menu
    menu._anchorFrame = anchorFrame
end

-- Used by EUI_CooldownManager_Options.lua
ns.CDMO_ShowSpellPicker = ShowSpellPicker
