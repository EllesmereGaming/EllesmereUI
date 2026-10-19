if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_AuraBuffReminders_Collect.lua
--
--  Layout and ShowIcon, and the collectors of the Raid Buffs, Auras and
--  Consumables sections.
--  Reads the earlier AuraBuff Reminders files through ns._abrInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._abrInternals
-- EllesmereUIAuraBuffReminders.lua or an earlier AuraBuff Reminders file
-- failed to load.
if not I or I.broken then return end
I.broken = true

local floor, min, abs = math.floor, math.min, math.abs

local _B, DEFAULT_TEXT_COLOR, EABR = I._B, I.DEFAULT_TEXT_COLOR, I.EABR
local GetPlayerClass, GetTextAnchorPoints = I.GetPlayerClass, I.GetTextAnchorPoints
local InCombat, InPvPInstance, isSecret = I.InCombat, I.InPvPInstance, I.isSecret
local Known, NON_SECRET_SPELL_IDS = I.Known, I.NON_SECRET_SPELL_IDS
local CursorAttachActive = I.CursorAttachActive
local ResolveFontPath, SetABRFont, ShortLabel = I.ResolveFontPath, I.SetABRFont, I.ShortLabel
local Tex, _preCombatOwnOnRaidCache = I.Tex, I._preCombatOwnOnRaidCache
local BuffExistsOnAnyGroupMember = I.BuffExistsOnAnyGroupMember
local CountGroupBuffCoverage, GetStanceState = I.CountGroupBuffCoverage, I.GetStanceState
local IsAnyShapeshiftFormActive = I.IsAnyShapeshiftFormActive
local IsUnderDuration, PlayerHasAuraByID = I.IsUnderDuration, I.PlayerHasAuraByID
local PlayerHasSelfCastAuraByID = I.PlayerHasSelfCastAuraByID
local PlayerOwnBuffOnAnyGroupMember = I.PlayerOwnBuffOnAnyGroupMember
local _IMBUE_EXCLUDE_SPELLS, AURAS = I._IMBUE_EXCLUDE_SPELLS, I.AURAS
local CachedGetItemCount, DTB_SPELL_ID = I.CachedGetItemCount, I.DTB_SPELL_ID
local INKY_BLACK_ITEM, PALADIN_RITES = I.INKY_BLACK_ITEM, I.PALADIN_RITES
local PARTNERED_TRINKET, PlayerHasBuffByName = I.PARTNERED_TRINKET, I.PlayerHasBuffByName
local PlayerHasFlaskBuff = I.PlayerHasFlaskBuff
local PlayerHasInkyBlackness, PlayerHasWellFed = I.PlayerHasInkyBlackness, I.PlayerHasWellFed
local RAID_BUFFS, ROGUE_POISONS, RUNE_BUFF_IDS = I.RAID_BUFFS, I.ROGUE_POISONS, I.RUNE_BUFF_IDS
local SHAMAN_IMBUES, SHAMAN_SHIELDS = I.SHAMAN_IMBUES, I.SHAMAN_SHIELDS
local AcquireEntry, activeIcons, ApplyGlow = I.AcquireEntry, I.activeIcons, I.ApplyGlow
local ApplySetup, GetOrCreateIcon, ICON_SIZE = I.ApplySetup, I.GetOrCreateIcon, I.ICON_SIZE
local iconPool, RemoveGlow = I.iconPool, I.RemoveGlow

local db
I.dbSetters[#I.dbSetters + 1] = function(v) db = v end
-- Hunter's Mark combat state: true on REGEN_DISABLED, cleared on cast/combat
-- end; OOC falls back to target debuff check.
local _huntersMarkNeeded = false
I.huntersMarkSetters[#I.huntersMarkSetters + 1] = function(v) _huntersMarkNeeded = v end
local iconAnchor
I.iconAnchorSetters[#I.iconAnchorSetters + 1] = function(v) iconAnchor = v end
local cursorAnchor
I.cursorAnchorSetters[#I.cursorAnchorSetters + 1] = function(v) cursorAnchor = v end

-------------------------------------------------------------------------------
--  Core Refresh Logic
-------------------------------------------------------------------------------

local function HideAllIcons()
    if InCombatLockdown() then return end  -- cannot hide SecureActionButtons after lockdown begins
    -- Sweep the WHOLE pool, never just activeIcons: a combat fade leaves icons
    -- shown at alpha 0, and any window where the list rebuilds without those
    -- frames orphans them -- shown, invisible, still hover/tooltip-live (field:
    -- an invisible stuck Augment Rune). The pool is a dozen frames and this
    -- runs on OOC edges only, so the sweep costs nothing; alpha resets here so
    -- a swept frame can never carry a stale fade into its next show.
    for _, btn in pairs(iconPool) do
        if btn then
            RemoveGlow(btn); EABR.ClearEatingVisual(btn)
            btn._text:SetText(""); btn._text:SetAlpha(1)
            btn._icon:SetDesaturated(false)
            btn:SetAlpha(1)
            btn:Hide()
        end
    end
    wipe(activeIcons)
end

-- iconAnchor is pinned by its grow edge (CENTER, LEFT or RIGHT) and the icons
-- hang off that same edge, so resizing it never moves them.
local function ResizeAnchorCentered(newW, newH)
    if not iconAnchor or InCombatLockdown() then return end
    iconAnchor:SetSize(newW, newH)
end

local _layoutScratch = {}  -- reused each call
local function LayoutIcons()
    if InCombatLockdown() then return end
    -- Merges beacon icons into the layout (one continuous row); beacon logic itself is untouched, just included here for positioning.
    local allIcons = _layoutScratch
    wipe(allIcons)
    -- Provider raid-buff button is a separate UIParent secure button; slot 0
    -- of the row when shown.
    if EABR._providerCastVisible and EABR._providerCastBtn then
        allIcons[#allIcons+1] = EABR._providerCastBtn
    end
    for _, btn in ipairs(activeIcons) do allIcons[#allIcons+1] = btn end
    local beaconsOnCursor = db and CursorAttachActive(db.profile.display) and cursorAnchor
    if _B.icons and not beaconsOnCursor then
        for _, id in ipairs(_B.ALL or {}) do
            if _B.iconState and _B.iconState[id] and _B.icons[id] then
                allIcons[#allIcons+1] = _B.icons[id]
            end
        end
    end
    local count = #allIcons; if count == 0 then return end
    local p = db.profile.display
    local spacing = p.iconSpacing or 8
    local baseScale = p.scale or 1.0
    local sz = floor(ICON_SIZE * baseScale + 0.5)
    local totalW = (count * sz) + ((count-1) * spacing)
    local textH = 0
    if p.showText then textH = (p.textSize or 11) + abs(p.textYOffset or -2) end
    -- Icons hang off the anchor's grow edge. Center-grow spreads them symmetrically so the row's center stays fixed
    -- as icons are added/removed; +textH/2 keeps the row at the icon+text box's top, matching the combat pool.
    -- Grow Right/Left hang them from the TOPLEFT/TOPRIGHT corner so that edge stays fixed instead.
    local pt, startX, yOff = "CENTER", -(totalW / 2) + (sz / 2), textH/2
    if p.growDirection == "RIGHT" then
        pt, startX, yOff = "TOPLEFT", 0, 0
    elseif p.growDirection == "LEFT" then
        pt, startX, yOff = "TOPRIGHT", -(count - 1) * (sz + spacing), 0
    end
    for i, btn in ipairs(allIcons) do
        btn:SetSize(sz, sz)
        btn:SetAlpha(p.opacity or 1.0)
        -- This layout is OOC-only, so treating every entry as protected also
        -- covers the provider/main secure buttons without needing pool scans.
        EABR.ApplyIconBorder(btn, true)
        EABR.SizeIconQuality(btn, sz)
        EABR.SizeIconBagCount(btn, sz)
        btn:ClearAllPoints()
        btn:SetPoint(pt, iconAnchor, pt, startX + (i-1)*(sz+spacing), yOff)
    end
    -- Size the anchor to the row so the unlock mode overlay covers it.
    ResizeAnchorCentered(totalW, sz + textH)
end

local function ShowIcon(iconIdx, m)
    local btn = GetOrCreateIcon(iconIdx)
    btn._dismissKey = m.dismissKey or nil
    btn._petCycleTotal = m.petCycleTotal or nil
    -- Right-click is passed through to whatever's behind (e.g. camera drag)
    -- for every other reminder; only a multi-pet cycle button claims it.
    -- Click-routing changes are combat-protected, same as the attribute
    -- writes below, so this only ever runs OOC.
    if not InCombat() then
        local wantRightCapture = m.petCycleTotal and true or false
        if btn._petCycleRightCapture ~= wantRightCapture then
            btn._petCycleRightCapture = wantRightCapture
            if wantRightCapture then
                securecallfunction(btn.SetPassThroughButtons, btn)
            else
                securecallfunction(btn.SetPassThroughButtons, btn, "RightButton")
            end
        end
    end
    ApplySetup(btn, m)
    local p = db.profile.display
    local baseScale = p.scale or 1.0
    local sz = floor(ICON_SIZE * baseScale + 0.5)
    ApplyGlow(btn, p, sz)
    EABR.ApplyEatingVisual(btn, m)
    EABR.ApplyIconQuality(btn, (not m.isEating) and m.qualityAtlas or nil)
    if m.groupTotal then
        EABR.ApplyIconGroupCoverage(btn, m.groupHave, m.groupTotal)
    else
        EABR.ApplyIconBagCount(btn, (not m.isEating) and m.bagCount or nil,
            (not m.isEating) and m.desaturated or nil,
            (not m.isEating) and m.substitute or nil)
    end
    if p.showText and not m.isEating then
        local tc = p.textColor or DEFAULT_TEXT_COLOR
        local fontPath = ResolveFontPath(p.nameFont)
        local textSize = p.textSize or 11
        local xOff = p.textXOffset or 0
        local yOff = p.textYOffset or -2
        SetABRFont(btn._text, fontPath, textSize)
        btn._text:ClearAllPoints()
        local tp, ip = GetTextAnchorPoints(p)
        btn._text:SetPoint(tp, btn, ip, xOff, yOff)
        btn._text:SetTextColor(tc.r, tc.g, tc.b, 1)
        btn._text:Show()
    else
        btn._text:SetText("")
        btn._text:Hide()
    end
    btn:Show()
    activeIcons[#activeIcons+1] = btn
end


local function CollectRaidBuffs(missing, playerClass, inInstance, inCombat)
local rb = db.profile.raidBuffs
do
    if not EABR.SectionShows(rb.whereToShow, inInstance) then return end
    local _, iType = IsInInstance()
    local inPvP = (iType == "pvp" or iType == "arena")
    local sw = rb.showWhen or {}
    local othersMissing = sw.othersMissing ~= false
    local iAmMissing = sw.iAmMissing == true
    -- Receiver view ("I am missing others' buffs") only scans group
    -- composition when opted in and actually grouped -- the default case
    -- stays allocation-free.
    local groupClasses
    if iAmMissing and (IsInGroup() or IsInRaid()) then
        groupClasses = EABR.BuildGroupClassSet()
    end
    for _, buff in ipairs(RAID_BUFFS) do
        if rb.enabled[buff.key] and not (buff.noPvP and inPvP) then
            local iCast = (buff.class == playerClass) and Known(buff.castSpell)
            -- Provider view when I can cast it; receiver view when I can't
            -- but a groupmate of the right class can (and my class benefits).
            local doReceiver = (not iCast) and iAmMissing and buff.check == "raid"
                and groupClasses and groupClasses[buff.class]
                and EABR.PlayerBenefitsFromBuff(buff)
            if iCast or doReceiver then
                -- In combat, skip buffs whose IDs are not all whitelisted
                local canCheck = true
                if inCombat then
                    if buff.check == "huntersMark" then
                        canCheck = true  -- uses state flag, no aura reading needed
                    else
                        for _, id in ipairs(buff.buffIDs) do
                            if not NON_SECRET_SPELL_IDS[id] then canCheck = false; break end
                        end
                    end
                end
                if canCheck then
                    local isMissing = false
                    local groupHave, groupTotal
                    if iCast then
                        if buff.check == "huntersMark" then
                            isMissing = inCombat and _huntersMarkNeeded
                        elseif othersMissing and buff.check == "raid" and (IsInGroup() or IsInRaid()) then
                            groupHave, groupTotal = CountGroupBuffCoverage(buff.buffIDs, buff.benefit)
                            isMissing = groupTotal > 0 and groupHave < groupTotal
                        else
                            isMissing = not PlayerHasAuraByID(buff.buffIDs, "raidbuff")
                        end
                    else
                        -- Receiver view: only whether the player personally lacks it.
                        isMissing = not PlayerHasAuraByID(buff.buffIDs, "raidbuff")
                    end
                    if isMissing then
                        local e = AcquireEntry()
                        e.spellID = buff.castSpell
                        e.label = ShortLabel(_G._EABR_SpellName(buff.castSpell, buff.name))
                        if buff.check == "huntersMark" then e.unit = "target" end
                        e.cat = "raidbuff"; e.data = buff
                        e.dismissKey = buff.key and ("raidbuff:" .. buff.key) or nil
                        if groupTotal then
                            e.groupHave = groupHave
                            e.groupTotal = groupTotal
                        end
                        if doReceiver then
                            -- Receiver reminders are informational: texture
                            -- mode, no click action.
                            e.mode = "texture"
                            e.texture = Tex(buff.castSpell)
                        else
                            e.mode = "spell"
                        end
                        missing[#missing+1] = e
                    end
                end
            end
        end
    end
end

end

local function CollectAuras(missing, playerClass, specID, inInstance, inCombat)
local au = db.profile.auras
do
    local auraSectionShows = EABR.SectionShows(au.whereToShow, inInstance)
    for _, aura in ipairs(AURAS) do
        if aura.standalone then
            -- Handled by standalone system, skip
        elseif au.enabled[aura.key] and (aura.class == playerClass)
           and (not aura.combatOnly or InCombat())
           and ((aura.key == "soulstone"
                 and EABR.SectionShows(db.profile.consumables.warlockWhereToShow, inInstance))
                or (aura.key ~= "soulstone" and auraSectionShows))
           and ((aura.isStance and GetStanceState(aura.castSpell)) or (not aura.isStance and Known(aura.castSpell)))
           and not (aura.notIfKnown and Known(aura.notIfKnown))
           and not (aura.requireTalent and not Known(aura.requireTalent))
           and not (aura.noPvP and InPvPInstance()) then
            local specOk = true
            if aura.specs then
                specOk = false
                for _, s in ipairs(aura.specs) do if s == specID then specOk = true; break end end
            end
            if specOk then
                -- Skip auras that require instance + group when not in both
                if aura.requireInstanceGroup and (not inInstance or not (IsInGroup() or IsInRaid())) then
                    specOk = false
                end
                -- Skip auras that require a group when solo
                if aura.requireGroup and not (IsInGroup() or IsInRaid()) then
                    specOk = false
                end
            end
            if specOk then
                -- Restricted contexts (combat / M+): only track reminders
                -- whose detection survives the aura lock -- stances/forms
                -- (the shapeshift API is unrestricted) or auras whose buff
                -- IDs are all whitelisted. combatOk entries keep their own
                -- snapshot machinery. Everything else is skipped to avoid
                -- false flashes.
                local canCheck = true
                if inCombat then
                    if aura.isStance or aura.formSpellIDs then
                        canCheck = true
                    elseif aura.combatOk == false then
                        canCheck = false
                    elseif aura.buffIDs and aura.buffIDs[1] then
                        for _, id in ipairs(aura.buffIDs) do
                            if not NON_SECRET_SPELL_IDS[id] then canCheck = false; break end
                        end
                    else
                        canCheck = false
                    end
                end
                if canCheck then
                    local isMissing = false
                    if aura.check == "mineOnRaid" then
                        if inCombat then
                            isMissing = false
                        else
                            isMissing = not BuffExistsOnAnyGroupMember(aura.buffIDs)
                            if not (IsInGroup() or IsInRaid()) then isMissing = false end
                        end
                    elseif aura.check == "ownOnRaid" then
                        if aura.key == "som" then
                            -- This cache is seeded OOC and a successful player cast
                            -- can set it in combat; nil means unknown/suppress. A
                            -- miss only reminds while someone is in reach to take it.
                            isMissing = (EABR._ownOtherAuraCache[369459] == false
                                    or EABR.OwnOtherAuraNeedsRebuff(369459, "aura"))
                                and EABR.AnyReachableGroupMember()
                        elseif inCombat then
                            local cached = _preCombatOwnOnRaidCache[aura.buffIDs[1]]
                            isMissing = (cached == false)
                        else
                            isMissing = not PlayerOwnBuffOnAnyGroupMember(aura.buffIDs)
                        end
                        if not (IsInGroup() or IsInRaid()) then isMissing = false end
                    elseif aura.check == "ownGroupOrSelf" then
                        local hasOwnBuff = EABR.PlayerOwnBuffOnGroupOrSelf(aura.buffIDs)
                        isMissing = hasOwnBuff == false
                        if isMissing and aura.key == "soulstone" then
                            -- On cooldown = nothing to cast, so no reminder. isActive is
                            -- NeverSecret; duration can be secret in restricted content,
                            -- where the reminder stays hidden until the next refresh edge.
                            -- No event watches the cooldown: a one-shot timer covers the
                            -- idle expiry, and the fight-end refresh (ENCOUNTER_END /
                            -- REGEN_ENABLED) already covers a boss-reset clear.
                            local cooldown = C_Spell.GetSpellCooldown(aura.castSpell)
                            local remaining
                            if cooldown and cooldown.isActive then
                                -- Ignore the ordinary GCD.
                                local duration = cooldown.duration
                                if isSecret(duration) then
                                    isMissing = false
                                elseif duration and duration > 1.5 then
                                    isMissing = false
                                    local start = cooldown.startTime
                                    if not isSecret(start) and type(start) == "number" then
                                        remaining = start + duration - GetTime()
                                    end
                                end
                            end
                            EABR.ArmSoulstoneCooldownRefresh(remaining)
                        end
                    elseif aura.check == "playerSelfCast" then
                        isMissing = not PlayerHasSelfCastAuraByID(aura.buffIDs)
                    elseif aura.isStance then
                        -- Stance is a shapeshift form: hide once it's the active stance
                        local _, isActive = GetStanceState(aura.castSpell)
                        isMissing = not isActive
                    else
                        -- Use instance-specific buff list if available and in instance
                        local checkIDs = (inInstance and aura.instanceBuffIDs) or aura.buffIDs
                        -- When aura reads are restricted (PvP, combat, M+),
                        -- fall back to scanning the shapeshift form bar for
                        -- form-based auras whose buff IDs aren't readable.
                        if aura.formSpellIDs and (inCombat or InPvPInstance()) then
                            isMissing = not IsAnyShapeshiftFormActive(aura.formSpellIDs)
                        else
                            local hasIt = PlayerHasAuraByID(checkIDs, "aura")
                            -- Some auras (e.g. Devotion Aura) go fully secret
                            -- rather than merely duration/expiration-secret
                            -- when their source is ambiguous (another
                            -- provider of the same aura in the party); the ID
                            -- lookup then can't see it at all. Fall back to a
                            -- name scan before declaring it missing.
                            if not hasIt and aura.nameFallback then
                                hasIt = PlayerHasBuffByName(aura.nameFallback)
                            end
                            isMissing = not hasIt
                        end
                    end
                    if isMissing then
                        local e = AcquireEntry()
                        e.mode = "spell"; e.spellID = aura.castSpell
                        e.label = ShortLabel(_G._EABR_SpellName(aura.castSpell, aura.name))
                        e.cat = "aura"; e.data = aura
                        e.dismissKey = "aura:" .. aura.key
                        missing[#missing+1] = e
                    end
                end
            end
        end
    end
end

end

-- Weapon-enchant reminders shared by the OOC and restricted (M+/combat)
-- passes -- the enchant summary API is combat-safe. Hung on EABR.
function EABR.EmitWeaponEnchantReminders(missing, co)
    local hasMH, mhExpire, _, _, hasOH, ohExpire = EABR.WeaponEnchants()
    for i = 1, 2 do
        local slot, has, expire
        -- Plain if/else, not "cond and a or b": that idiom silently falls
        -- through to b whenever a (hasMH) is false, corrupting slot 16.
        if i == 1 then slot, has, expire = 16, hasMH, mhExpire
        else slot, has, expire = 17, hasOH, ohExpire end
        local r = EABR._resolved.we[slot]
        local cat = r.cat
        local shouldRemind = false
        if cat and not has then
            shouldRemind = true
        elseif cat and has and expire and expire > 0 then
            local expireTime = expire / 1000 + GetTime()
            if IsUnderDuration(3600, expireTime, "consumable") then
                shouldRemind = true
            end
        end
        if shouldRemind and r.itemID and (co.showWithoutItem ~= false or r.hasBags) then
            local bestItemID = r.itemID
            local e = AcquireEntry()
            e.mode = "macro"
            e.macro = "/use item:" .. bestItemID .. "\n/use " .. slot
            e.texture = C_Item.GetItemIconByID(bestItemID) or 134400
            -- Localizes the full slot name THEN shortens: ShortLabel truncates on whitespace (English -> Main/Off, space-less locales like zhTW stay intact). L() on the pre-truncated word would collide with the generic Off (disabled) translation.
            e.label = ShortLabel(EllesmereUI.L(slot == 16 and "Main Hand" or "Off Hand"))
            e.tooltipItem = bestItemID
            e.qualityAtlas = EABR.GetItemQualityAtlas(bestItemID)
            e.bagCount = CachedGetItemCount(bestItemID)
            e.desaturated = not r.hasBags
            e.cat = "consumable"
            e.dismissKey = "consumable:weapon_enchant_" .. slot
            missing[#missing+1] = e
        end
    end
end

local function CollectConsumables(missing, playerClass, specID, inInstance, inKeystone, inCombat)
local co = db.profile.consumables
-- Class specials (poisons/rites/imbues/shields) share one "Where to Show"
-- set (they are class-exclusive; per-spell visibility would be meaningless).
local specialsActive = EABR.SectionShows(co.specialsWhereToShow, inInstance)
-- The trackable subset (weapon enchants, poisons, rites, imbues, Earth
-- Shield) runs in combat / M+ too; where reminders appear is governed
-- per-section by "Where to Show". Non-trackable emitters below either
-- self-suppress in restricted contexts (flask/food/inky/rune) or carry
-- their own combat gate.
    do

        -- Rebuilds the bag/equip-derived item cache only when inputs changed (bags, weapon, preferred-item setting); a clean refresh is 3 scalar compares. Resolved inside instances, or in the open world when the consumables section shows there; the dirty flag persists until the next eligible refresh consumes it.
        local needResolve = inInstance
        if not needResolve then
            local ow = co.whereToShow
            needResolve = (not ow) or (ow.open_world ~= false)
        end
        if needResolve then EABR.ResolveConsumables() end

        -- === SPECIALS (share the class-specials "Where to Show") ===
        if specialsActive then
            -- Rogue Poisons: unified scan counts active per category vs required (1 each, 2 with Dragon-Tempered Blades); shows the first enabled+known+missing poison per deficient category.
            if playerClass == "ROGUE" then
                local activeL, activeNL = 0, 0
                local knownL, knownNL = 0, 0
                local missingL, missingNL = nil, nil
                for _, poison in ipairs(ROGUE_POISONS) do
                    if Known(poison.castSpell) then
                        local isLethal = (poison.cat == "lethal")
                        if isLethal then knownL = knownL + 1 else knownNL = knownNL + 1 end
                        local aura = C_UnitAuras.GetPlayerAuraBySpellID(poison.castSpell)
                        local active = aura and not IsUnderDuration(aura.duration, aura.expirationTime, "special")
                        if active then
                            if isLethal then activeL = activeL + 1 else activeNL = activeNL + 1 end
                        elseif co.enabled[poison.key] then
                            if isLethal and not missingL then missingL = poison
                            elseif not isLethal and not missingNL then missingNL = poison end
                        end
                    end
                end
                local hasDTB = IsPlayerSpell(DTB_SPELL_ID)
                local reqL = min(knownL, hasDTB and 2 or 1)
                local reqNL = min(knownNL, hasDTB and 2 or 1)
                if missingL and activeL < reqL then
                    local e = AcquireEntry()
                    e.mode = "spell"; e.spellID = missingL.castSpell
                    e.label = ShortLabel(_G._EABR_SpellName(missingL.castSpell, missingL.name), "ROGUE")
                    e.cat = "consumable"; e.data = missingL
                    e.dismissKey = "consumable:rogue_lethal"
                    missing[#missing+1] = e
                end
                if missingNL and activeNL < reqNL then
                    local e = AcquireEntry()
                    e.mode = "spell"; e.spellID = missingNL.castSpell
                    e.label = ShortLabel(_G._EABR_SpellName(missingNL.castSpell, missingNL.name), "ROGUE")
                    e.cat = "consumable"; e.data = missingNL
                    e.dismissKey = "consumable:rogue_nonlethal"
                    missing[#missing+1] = e
                end
            end

            -- Paladin Rites
            if playerClass == "PALADIN" then
                for _, rite in ipairs(PALADIN_RITES) do
                    if co.enabled[rite.key] and Known(rite.castSpell) then
                        local hasMH, mhExpire = EABR.WeaponEnchants()
                        local show = false
                        if not hasMH then
                            show = true
                        elseif mhExpire and mhExpire > 0 and IsUnderDuration(3600, mhExpire / 1000 + GetTime(), "consumable") then
                            show = true
                        end
                        if show then
                            local e = AcquireEntry()
                            local spellName = _G._EABR_SpellName(rite.castSpell, rite.name)
                            e.mode = "macro"
                            e.spellID = rite.castSpell
                            e.macro = "/cast " .. spellName .. "\n/use 16"
                            e.label = ShortLabel(_G._EABR_SpellName(rite.castSpell, rite.name))
                            e.cat = "consumable"; e.data = rite
                            e.dismissKey = "consumable:" .. rite.key
                            missing[#missing+1] = e
                            break -- rites are mutually exclusive weapon enchants
                        end
                    end
                end
            end

            -- Shaman Imbues: matches each imbue's wepEnchID against both weapon slots; the enchant summary carries the specific enchant ID per hand (4th/8th return values).
            if playerClass == "SHAMAN" then
                local hasMH, mhExpire, _, mhEnchID, hasOH, ohExpire, _, ohEnchID = EABR.WeaponEnchants()
                for _, imbue in ipairs(SHAMAN_IMBUES) do
                    if co.enabled[imbue.key] and Known(imbue.castSpell)
                       and (not imbue.requireShield or EABR.HasShieldEquipped()) then
                        local found = false
                        if imbue.wepEnchID then
                            for _, eid in ipairs(imbue.wepEnchID) do
                                if eid > 0 and ((hasMH and mhEnchID == eid) or (hasOH and ohEnchID == eid)) then
                                    -- Uses the matched hand's expire time, not min of both -- an unenchanted hand returns 0, which would always trigger.
                                    local matchExpire
                                    if hasMH and mhEnchID == eid then
                                        matchExpire = mhExpire
                                    else
                                        matchExpire = ohExpire
                                    end
                                    if matchExpire and matchExpire > 0 and IsUnderDuration(3600, matchExpire / 1000 + GetTime(), "consumable") then
                                        found = false
                                    else
                                        found = true
                                    end
                                end
                            end
                        end
                        if not found then
                            local e = AcquireEntry()
                            e.mode = "spell"; e.spellID = imbue.castSpell
                            e.label = ShortLabel(_G._EABR_SpellName(imbue.castSpell, imbue.name), "SHAMAN_IMBUE")
                            e.cat = "consumable"; e.data = imbue
                            e.dismissKey = "consumable:" .. imbue.key
                            missing[#missing+1] = e
                        end
                    end
                end

                -- Shaman Shields: talent-gated entries. Earth Shield self-buff (383648) is handled separately below (also OOC-only despite being whitelisted -- see that block); other shields' IDs are not whitelisted either, so they stay OOC-only.
                for _, shield in ipairs(SHAMAN_SHIELDS) do
                    local castID = shield.castSpellFn and shield.castSpellFn() or shield.castSpell
                    if co.enabled[shield.key] ~= false and Known(castID) then
                        local ok = true
                        if shield.requireTalent and not Known(shield.requireTalent) then ok = false end
                        if shield.excludeTalent and Known(shield.excludeTalent) then ok = false end
                        -- es_orbit and es_ally have their own block below
                        if shield.key == "es_orbit" or shield.key == "es_ally" then ok = false end
                        if inCombat or inKeystone then ok = false end
                        if ok and not PlayerHasAuraByID(shield.buffIDs, "special") then
                            local e = AcquireEntry()
                            e.mode = "spell"; e.spellID = castID
                            e.label = ShortLabel(shield.name, "SHAMAN_SHIELD")
                            e.cat = "consumable"; e.data = shield
                            e.dismissKey = "consumable:" .. shield.key
                            missing[#missing+1] = e
                        end
                    end
                end

            end
        end -- end specialsActive

        -- === CONSUMABLES (visibility via the section "Where to Show") ===

        -- Augment Runes: presence unverifiable in combat/M+ (suppress);
        -- otherwise try the read and remind when missing.
        if co.enabled.augment_rune and EABR.ConsumableShows(co, "augment_rune", inInstance) then
            local hasRuneBuff = EABR.ConsumablePresenceUnverifiable() or PlayerHasAuraByID(RUNE_BUFF_IDS)
            if not hasRuneBuff then
                local rr = EABR._resolved.rune
                local runeItem = rr.itemID
                if runeItem and (co.showWithoutItem ~= false or rr.hasBags) then
                    local e = AcquireEntry()
                    e.mode = "item"; e.itemID = runeItem
                    e.texture = C_Item.GetItemIconByID(runeItem); e.label = EllesmereUI.L(ShortLabel("Augment Rune"))
                    e.qualityAtlas = EABR.GetItemQualityAtlas(runeItem)
                    e.bagCount = CachedGetItemCount(runeItem)
                    e.desaturated = not rr.hasBags
                    e.cat = "consumable"
                    e.dismissKey = "consumable:rune"
                    missing[#missing+1] = e
                end
            end
        end

        -- Weapon Enchants (temp enchant items; the enchant summary API is
        -- combat-safe). Skipped if the player knows any imbue spell (Shaman
        -- imbues, Paladin rites). Rogues/DKs NOT excluded -- poisons are
        -- temp enchants too, and DKs can use oils alongside runeforges.
        if co.enabled.weapon_enchant and EABR.ConsumableShows(co, "weapon_enchant", inInstance) then
            local _hasImbueSpell = false
            for _, sid in ipairs(_IMBUE_EXCLUDE_SPELLS) do
                if IsSpellKnown(sid) then _hasImbueSpell = true; break end
            end
            if not _hasImbueSpell then
                EABR.EmitWeaponEnchantReminders(missing, co)
            end
        end

        -- Flask / Food: remind only when absence is verifiable (the checks
        -- suppress under combat/M+/restriction instead of false-firing).
        if co.enabled.flask and EABR.ConsumableShows(co, "flask", inInstance) then
            if not PlayerHasFlaskBuff() then
                local rf = EABR._resolved.flask
                local flaskItemID = rf.itemID
                if flaskItemID and (co.showWithoutItem ~= false or rf.hasBags) then
                    local e = AcquireEntry()
                    e.mode = "item"; e.itemID = flaskItemID
                    e.texture = C_Item.GetItemIconByID(flaskItemID) or 134830
                    e.label = EllesmereUI.L("Flask")
                    e.qualityAtlas = EABR.GetItemQualityAtlas(flaskItemID)
                    e.bagCount = CachedGetItemCount(flaskItemID)
                    e.desaturated = not rf.hasBags
                    e.cat = "consumable"
                    e.dismissKey = "consumable:flask"
                    missing[#missing+1] = e
                end
            end
        end

        if co.enabled.food and EABR.ConsumableShows(co, "food", inInstance) then
            if not PlayerHasWellFed() then
                local foodItemID = EABR._resolved.food.itemID
                if foodItemID and (co.showWithoutItem ~= false or EABR._resolved.food.hasBags) then
                    local e = AcquireEntry()
                    e.mode = "item"; e.itemID = foodItemID
                    e.texture = C_Item.GetItemIconByID(foodItemID) or 134062
                    e.label = EllesmereUI.L("Food")
                    e.qualityAtlas = EABR.GetItemQualityAtlas(foodItemID)
                    e.bagCount = CachedGetItemCount(foodItemID)
                    e.desaturated = not EABR._resolved.food.hasBags
                    e.substitute = EABR._resolved.food.isSubstitute
                    e.cat = "consumable"
                    e.dismissKey = "consumable:food"
                    if EABR.IsPlayerEating() then
                        e.isEating = true
                        e.eatingExpirationTime = EABR.GetEatingExpirationTime()
                    end
                    missing[#missing+1] = e
                end
            end
        end

        -- Inky Black Potion (zone-specific)
        if co.enabled.inky_black and EABR.ConsumableShows(co, "inky_black", inInstance) then
            local zones = co.inkyBlackZones or ""
            if zones ~= "" then
                -- Cache parsed zone set on the string itself
                if not co._inkyZoneSet or co._inkyZoneSrc ~= zones then
                    local s = {}
                    for zid in zones:gmatch("[^,%s]+") do s[zid] = true end
                    co._inkyZoneSet = s
                    co._inkyZoneSrc = zones
                end
                local currentZone = tostring(C_Map.GetBestMapForUnit("player") or 0)
                if co._inkyZoneSet[currentZone] then
                    local hasPotion = EABR._resolved.inky.hasPotion
                    if not PlayerHasInkyBlackness() and hasPotion then
                        local e = AcquireEntry()
                        e.mode = "item"; e.itemID = INKY_BLACK_ITEM
                        e.texture = C_Item.GetItemIconByID(INKY_BLACK_ITEM)
                        e.label = EllesmereUI.L(ShortLabel("Inky Black Potion"))
                        e.qualityAtlas = EABR.GetItemQualityAtlas(INKY_BLACK_ITEM)
                        e.bagCount = CachedGetItemCount(INKY_BLACK_ITEM)
                        e.cat = "consumable"
                        e.dismissKey = "consumable:inky_black"
                        missing[#missing+1] = e
                    end
                end
            end
        end
    end -- consumables block

    -- Earth Shield self-buff (383648), only with Elemental Orbit. NOT
    -- actually combat-safe despite being whitelisted in NON_SECRET_SPELL_IDS:
    -- confirmed in-game that GetPlayerAuraBySpellID(383648) returns nothing
    -- readable in combat even while the buff is genuinely active, so a
    -- reminder already up when combat starts would get stuck (neither the
    -- live read nor the pre-combat snapshot can clear it) until combat ends.
    -- Suppress in combat/keystone instead, same as its ls_ws_orbit/
    -- shield_basic siblings just above.
    if specialsActive and playerClass == "SHAMAN" then
        local esOrbit = SHAMAN_SHIELDS[1]  -- es_orbit entry
        if co.enabled[esOrbit.key] ~= false and Known(esOrbit.castSpell)
           and esOrbit.requireTalent and Known(esOrbit.requireTalent) then
            if not (inCombat or inKeystone) and not PlayerHasAuraByID(esOrbit.buffIDs) then
                local e = AcquireEntry()
                e.mode = "spell"; e.spellID = esOrbit.castSpell
                e.label = ShortLabel(esOrbit.name, "SHAMAN_SHIELD")
                e.cat = "consumable"; e.data = esOrbit
                e.dismissKey = "consumable:" .. esOrbit.key
                missing[#missing+1] = e
            end
        end
        -- Our Earth Shield on a group member (es_ally, opt-in): grouped and
        -- out of combat/keystone like the self shield. The tracker cache is nil
        -- (unknown) until a lookup proves a miss; nobody in reach = no reminder.
        -- Display-only: a click would self-cast, never reaching an ally.
        local esAlly = SHAMAN_SHIELDS[2]  -- es_ally entry
        if co.enabled[esAlly.key] == true and not (inCombat or inKeystone)
           and (IsInGroup() or IsInRaid())
           and (EABR._ownOtherAuraCache[974] == false
                or EABR.OwnOtherAuraNeedsRebuff(974, "special"))
           and EABR.AnyReachableGroupMember() then
            local e = AcquireEntry()
            e.mode = "texture"; e.texture = Tex(esAlly.castSpell)
            e.spellID = esAlly.castSpell  -- tooltip only
            e.label = EllesmereUI.L(ShortLabel(esAlly.name))
            e.cat = "consumable"; e.data = esAlly
            e.dismissKey = "consumable:" .. esAlly.key
            missing[#missing+1] = e
        end
    end

    ---------------------------------------------------------------------------
    --  Healthstone in bags (group; "Where to Show" governs visibility). Bag
    --  state and class scans are combat-safe; secret class tokens skip units.
    --  In combat only the warlock is reminded: a non-warlock can't be handed
    --  a stone mid-fight, so for everyone else it is noise until the fight
    --  ends (the list rebuilds on both combat transitions).
    ---------------------------------------------------------------------------
    if (IsInGroup() or IsInRaid()) and EABR.ConsumableShows(co, "healthstone", inInstance)
       and not (InCombat() and GetPlayerClass() ~= "WARLOCK") then
        if co and co.enabled and co.enabled.healthstone ~= false then
            -- Only remind if a Warlock is in the group
            local hasWarlock = false
            if IsInRaid() then
                for i = 1, GetNumGroupMembers() do
                    local _, cls = UnitClass("raid"..i)
                    if cls ~= nil and not isSecret(cls) and cls == "WARLOCK" then hasWarlock = true; break end
                end
            else
                if GetPlayerClass() == "WARLOCK" then
                    hasWarlock = true
                else
                    for i = 1, GetNumSubgroupMembers() do
                        local _, cls = UnitClass("party"..i)
                        if cls ~= nil and not isSecret(cls) and cls == "WARLOCK" then hasWarlock = true; break end
                    end
                end
            end
            local hasHealthstone = EABR._resolved.healthstone.hasStone
            if hasWarlock and not hasHealthstone then
                local e = AcquireEntry()
                e.mode = "texture"; e.texture = 538745
                e.label = EllesmereUI.L("HS")
                e.cat = "consumable"
                e.dismissKey = "consumable:healthstone"
                missing[#missing+1] = e
            end
        end
    end

    ---------------------------------------------------------------------------
    --  Partnered Trinket: Emerald Coach's Whistle (combat-safe via snapshot)
    ---------------------------------------------------------------------------
    do
        local co2 = db.profile.consumables
        if co2 and co2.enabled and co2.enabled.coaches_whistle ~= false
           and EABR.ConsumableShows(co2, "coaches_whistle", inInstance) and EABR._cachedDiffID ~= 208
           and (IsInGroup() or IsInRaid())
           and (GetInventoryItemID("player", 13) == 193718 or GetInventoryItemID("player", 14) == 193718) then
            local hasBuff = PlayerHasAuraByID(PARTNERED_TRINKET.buffIDs)
            if not hasBuff then
                local e = AcquireEntry()
                e.mode = "texture"; e.texture = PARTNERED_TRINKET.icon
                e.label = EllesmereUI.L("Whistle")
                e.cat = "consumable"
                e.dismissKey = "consumable:coaches_whistle"
                missing[#missing+1] = e
            end
        end
    end

    ---------------------------------------------------------------------------
    --  DK Runeforging (OOC only, check permanent enchant via item link)
    ---------------------------------------------------------------------------
    if not inCombat and playerClass == "DEATHKNIGHT" then
        local co3 = db.profile.consumables
        if co3 and co3.enabled and co3.enabled.runeforge ~= false then
            local needsRune = false
            for i = 1, 2 do
                local slot = (i == 1) and 16 or 17
                local link = GetInventoryItemLink("player", slot)
                if link then
                    local ench = link:match("item:%d+:(-?%d+):")
                    local enchID = tonumber(ench) or 0
                    if enchID == 0 then needsRune = true; break end
                end
            end
            if needsRune then
                local e = AcquireEntry()
                e.mode = "texture"; e.texture = 135957
                e.label = EllesmereUI.L("Rune")
                e.cat = "consumable"
                e.dismissKey = "consumable:runeforge"
                missing[#missing+1] = e
            end
        end
    end

end

-- CollectTalentReminders moved to EllesmereUIABR_TalentReminders.lua

I.CollectAuras, I.CollectConsumables = CollectAuras, CollectConsumables
I.CollectRaidBuffs, I.HideAllIcons, I.LayoutIcons = CollectRaidBuffs, HideAllIcons, LayoutIcons
I.ResizeAnchorCentered, I.ShowIcon = ResizeAnchorCentered, ShowIcon
I.broken = false
