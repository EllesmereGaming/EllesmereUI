if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_DamageMeters_Tooltip.lua
--
--  The breakdown tooltip shared by all windows: its frame, PopulatePreview,
--  the anchor and the hover poll.
--  Reads the earlier Damage Meters files through ns and ns._dmInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._dmInternals
-- EllesmereUIDamageMeters.lua or an earlier EUI_DamageMeters_*.lua file
-- failed to load.
if not I or I.broken then return end
I.broken = true

local EUI = EllesmereUI
local L = _G.EllesmereUI.L

local BAR_TEX, DB, DM_TYPE_NAMES = I.BAR_TEX, I.DB, I.DM_TYPE_NAMES
local AbbrevNumber, AggregateEnemyPlayers = I.AbbrevNumber, I.AggregateEnemyPlayers
local ApplyBarTexture, BuildPlayerTargets = I.ApplyBarTexture, I.BuildPlayerTargets
local FormatBarValue = I.FormatBarValue
local GetBreakdownBarTexturePath = I.GetBreakdownBarTexturePath
local GetBreakdownDuration, IsOwnRow, IsSecret = I.GetBreakdownDuration, I.IsOwnRow, I.IsSecret
local PhysicalPixels, ResolveGroupGUID = I.PhysicalPixels, I.ResolveGroupGUID
local SetDMFont, StripRealm, SetTTFrame = I.SetDMFont, I.StripRealm, I.SetTTFrame
local SetTTLastScale = I.SetTTLastScale

-- Hover tooltip (shared across all windows)
local TT_DEFAULT_MAX = 8
local TT_BAR_H = 18
local TT_BAR_SP = 1
local TT_WIDTH = 275
local function TT_MAX()
    local cfg = DB and DB()
    return (cfg and cfg.showAllBreakdownSpells == false) and TT_DEFAULT_MAX or 15
end

local _ttFrame, _ttBars, _ttVisible = nil, {}, false
local _activeRow = nil
I.ttFrameSetters[#I.ttFrameSetters + 1] = function(v) _ttFrame = v end
I.activeRowSetters[#I.activeRowSetters + 1] = function(v) _activeRow = v end

local TT_HDR_H = 20

-- Same conversion as PhysicalPixels(), but snapped against the tooltip frame's own
-- effective scale. The hover tooltip has its own user-configurable hoverTooltipScale
-- (SetScale), independent of the addon-wide UI scale that PP.mult is derived from --
-- using the global PhysicalPixels() here rounds bar spacing to the wrong pixel grid
-- whenever hoverTooltipScale isn't 100%.
local function TTPhysicalPixels(userValue)
    local PP = EUI and EUI.PP
    if not PP or not PP.perfect or not PP.SnapForES or not _ttFrame then return PhysicalPixels(userValue) end
    local es = _ttFrame:GetEffectiveScale()
    local onePixel = PP.perfect / es
    return PP.SnapForES((userValue or 0) * onePixel, es)
end

-- Row stride for the tooltip list. TT_BAR_H is a raw coordinate height while the
-- gap is snapped to whole pixels, so their sum sits between two pixel rows and
-- -((i-1) * stride) drifts down the list, the same defect the main bars had.
-- Snap the sum; the row height itself keeps its current size.
local function TTStride()
    local sp = TTPhysicalPixels(1)
    local PP = EUI and EUI.PP
    if not PP or not PP.SnapForES or not _ttFrame then return TT_BAR_H + sp end
    return PP.SnapForES(TT_BAR_H + sp, _ttFrame:GetEffectiveScale())
end

local function BlizzardSkinBordersAvailable()
    return C_AddOns and C_AddOns.IsAddOnLoaded
        and C_AddOns.IsAddOnLoaded("EllesmereUIBlizzardSkin")
        and EUI and EUI._applyBlizzardConfiguredBorder
end

local function ApplyInheritedBlizzardBorder(frame, prefix)
    if not frame or not BlizzardSkinBordersAvailable() then return false end
    if prefix == "tooltip" and frame._bg and EUI.GetTooltipBg then
        frame._bg:SetColorTexture(EUI.GetTooltipBg())
    end
    local ok = pcall(EUI._applyBlizzardConfiguredBorder, frame, prefix, 1)
    if ok and frame._legacyBorder and frame._legacyBorder._frame then
        frame._legacyBorder._frame:Hide()
    elseif not ok and frame._legacyBorder and frame._legacyBorder._frame then
        frame._legacyBorder._frame:Show()
    end
    return ok
end

local function EnsureTooltipFrame()
    if _ttFrame then
        if not _ttFrame._fvRim then ApplyInheritedBlizzardBorder(_ttFrame, "tooltip") end
        return
    end
    SetTTFrame(CreateFrame("Frame", nil, UIParent))
    _ttFrame:SetFrameStrata("TOOLTIP")
    _ttFrame:SetSize(TT_WIDTH, 10)
    _ttFrame:SetClampedToScreen(true)
    _ttFrame._bg = _ttFrame:CreateTexture(nil, "BACKGROUND")
    _ttFrame._bg:SetAllPoints()
    _ttFrame._bg:SetColorTexture(0, 0, 0, 0.95)
    -- WoW Forever: the bronze line round the outside (the rows run flush)
    -- in place of the EUI border.
    if not ns.DMFvFrameArt(_ttFrame, true) then
        if EUI.MakeBorder then _ttFrame._legacyBorder = EUI.MakeBorder(_ttFrame, 0, 0, 0, 1) end
        ApplyInheritedBlizzardBorder(_ttFrame, "tooltip")
    end

    -- Header bar
    _ttFrame._hdr = CreateFrame("Frame", nil, _ttFrame)
    _ttFrame._hdr:SetHeight(TT_HDR_H)
    _ttFrame._hdr:SetPoint("TOPLEFT", _ttFrame, "TOPLEFT", 0, 0)
    _ttFrame._hdr:SetPoint("TOPRIGHT", _ttFrame, "TOPRIGHT", 0, 0)
    local hdrBg = _ttFrame._hdr:CreateTexture(nil, "BACKGROUND", nil, 1)
    hdrBg:SetAllPoints()
    _ttFrame._hdrBg = hdrBg
    _ttFrame._hdrText = _ttFrame._hdr:CreateFontString(nil, "OVERLAY")
    _ttFrame._hdrText:SetPoint("LEFT", _ttFrame._hdr, "LEFT", 5, 0)
    _ttFrame._hdrText:SetWidth(TT_WIDTH - 25); _ttFrame._hdrText:SetJustifyH("LEFT"); _ttFrame._hdrText:SetWordWrap(false)
    SetDMFont(_ttFrame._hdrText, 10)

    -- Combat lockdown message (shown instead of bars)
    _ttFrame._combatMsg = _ttFrame:CreateFontString(nil, "OVERLAY")
    _ttFrame._combatMsg:SetPoint("TOP", _ttFrame._hdr, "BOTTOM", 0, -8)
    _ttFrame._combatMsg:SetPoint("LEFT", _ttFrame, "LEFT", 8, 0)
    _ttFrame._combatMsg:SetPoint("RIGHT", _ttFrame, "RIGHT", -8, 0)
    _ttFrame._combatMsg:SetJustifyH("CENTER"); _ttFrame._combatMsg:SetWordWrap(true)
    SetDMFont(_ttFrame._combatMsg, 10)
    _ttFrame._combatMsg:SetTextColor(0.6, 0.6, 0.6, 1)
    _ttFrame._combatMsg:SetText(EllesmereUI.L("Detailed information is\nsecret while in combat"))
    _ttFrame._combatMsg:Hide()

    _ttFrame:SetScript("OnShow", function() _ttVisible = true end)
    _ttFrame:SetScript("OnHide", function() _ttVisible = false end)

    _ttFrame:Hide()
end

-- Lazy bar pool: creates bars on demand up to the requested index
local function EnsureTTBar(i)
    if _ttBars[i] then return _ttBars[i] end
    EnsureTooltipFrame()
    local ttStride = TTStride()
    local b = {}
    b.row = CreateFrame("Frame", nil, _ttFrame)
    b.row:SetHeight(TT_BAR_H)
    b.row:SetPoint("TOPLEFT", _ttFrame, "TOPLEFT", 0, -(TT_HDR_H + (i-1) * ttStride))
    b.row:SetPoint("TOPRIGHT", _ttFrame, "TOPRIGHT", 0, -(TT_HDR_H + (i-1) * ttStride))
    b.fill = CreateFrame("StatusBar", nil, b.row)
    b.fill:SetAllPoints(); b.fill:SetMinMaxValues(0, 1); b.fill:SetValue(0); b.fill:SetStatusBarTexture(BAR_TEX)
    b.spellIcon = b.row:CreateTexture(nil, "OVERLAY")
    b.spellIcon:SetSize(TT_BAR_H, TT_BAR_H)
    b.spellIcon:SetPoint("LEFT", b.row, "LEFT", 0, 0)
    b.spellIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.spellIcon:Hide()
    local tf = CreateFrame("Frame", nil, b.fill)
    tf:SetAllPoints(b.fill); tf:SetFrameLevel(b.fill:GetFrameLevel() + 2)
    b.label = tf:CreateFontString(nil, "OVERLAY"); b.label:SetPoint("LEFT", tf, "LEFT", 2, 0); b.label:SetJustifyH("LEFT"); SetDMFont(b.label, 10)
    b.amount = tf:CreateFontString(nil, "OVERLAY"); b.amount:SetPoint("RIGHT", tf, "RIGHT", -2, 0); b.amount:SetJustifyH("RIGHT"); SetDMFont(b.amount, 10)
    b.label:SetPoint("RIGHT", b.amount, "LEFT", -3, 0)
    b.row:Hide()
    _ttBars[i] = b
    return b
end

local _ttLastStride = -1
local _ttSorted = {}

-- Hide the "Targets" sub-section left over from a prior tooltip
local function HideTTTargets()
    if _ttFrame and _ttFrame._tgtDivider then
        _ttFrame._tgtDivider:Hide(); _ttFrame._tgtLabel:Hide()
        for ti = 1, 3 do _ttFrame._tgtBars[ti].row:Hide() end
    end
end

local function PopulatePreview(bar, curSession, curSessionID, curDMType)

    if _ttFrame and _ttFrame._combatMsg then _ttFrame._combatMsg:Hide() end
    HideTTTargets()
    if not bar._src then return false end
    if not bar._srcGUID and not bar._src.sourceCreatureID then return false end
    if not C_DamageMeter then return false end

    -- Reposition tooltip bars with physical-pixel spacing (only when the stride changes)
    local ttSp = TTPhysicalPixels(1)
    local ttStride = TTStride()
    if ttStride ~= _ttLastStride then
        _ttLastStride = ttStride
        for ti = 1, #_ttBars do
            local b = _ttBars[ti]
            if b then
                b.row:ClearAllPoints()
                b.row:SetPoint("TOPLEFT", _ttFrame, "TOPLEFT", 0, -(TT_HDR_H + (ti-1) * ttStride))
                b.row:SetPoint("TOPRIGHT", _ttFrame, "TOPRIGHT", 0, -(TT_HDR_H + (ti-1) * ttStride))
            end
        end
    end

    -- Helper: apply header styling
    local function ApplyTTHeader(playerName, typeName)
        EnsureTooltipFrame()
        _ttFrame._hdrText:SetText(EllesmereUI.Lf("%1$s's %2$s Breakdown", playerName, typeName))
        local cfg = DB()
        local hc = cfg.hdrBgColor; local hR = hc and hc.r or 0x1B/255; local hG = hc and hc.g or 0x1B/255; local hB = hc and hc.b or 0x1B/255
        ns.DMPaintHeaderBg(_ttFrame._hdrBg, hR, hG, hB, cfg.hdrBgAlpha or 1)
        local tR, tG, tB
        if cfg.hdrTextUseAccent ~= false then tR, tG, tB = ns.DMTitleRGB()
        else local tc = cfg.hdrTextColor; tR = tc and tc.r or 1; tG = tc and tc.g or 1; tB = tc and tc.b or 1 end
        _ttFrame._hdrText:SetTextColor(tR, tG, tB, 1)
    end

    -- Death recap tooltip: show last few events before death
    if curDMType == Enum.DamageMeterType.Deaths then
        local recapID = bar._src.deathRecapID
        if recapID and issecretvalue and issecretvalue(recapID) then recapID = nil end
        if not recapID or recapID <= 0 or not C_DeathRecap or not C_DeathRecap.GetRecapEvents then return false end
        local ok, raw = pcall(C_DeathRecap.GetRecapEvents, recapID)
        if not ok or not raw or #raw == 0 then return false end
        -- The recap event fields are undocumented for secrecy and may come back
        -- SECRET mid-combat, so every read below is either guarded before Lua
        -- touches it or handed whole to an engine sink (StatusBar, FontString,
        -- SetFormattedText, AbbrevNumber -- all take secret arguments). Plain
        -- values produce byte-identical output to the pre-combat rendering.
        local maxHP, maxHPSecret = 1, nil
        if C_DeathRecap.GetRecapMaxHealth then
            local ok2, hp = pcall(C_DeathRecap.GetRecapMaxHealth, recapID)
            if ok2 and hp then
                if IsSecret(hp) then maxHPSecret = hp
                elseif type(hp) == "number" and hp > 0 then maxHP = hp end
            end
        end
        -- Reverse to oldest-first
        local reversed = {}
        for ri = #raw, 1, -1 do reversed[#reversed + 1] = raw[ri] end
        ApplyTTHeader(StripRealm(bar._src.name, bar._src), EllesmereUI.L("Death Recap"))
        local texPath, texKey = GetBreakdownBarTexturePath()
        local deathTime = reversed[#reversed] and reversed[#reversed].timestamp
        if IsSecret(deathTime) then deathTime = nil end
        deathTime = deathTime or GetTime()
        local total = #reversed
        local ttMax = TT_MAX()
        local count = math.min(ttMax, total)
        local startIdx = total - count  -- skip oldest events, show last N
        for i = 1, math.max(ttMax, #_ttBars) do
            local b = EnsureTTBar(i)
            if i <= count then
                local ev = reversed[startIdx + i]
                local spID = ev.spellId
                local spIcon
                -- GetSpellTexture takes a secret id (AllowedWhenTainted); only
                -- the id > 0 filter needs the value, so a secret id goes in whole.
                if spID and (IsSecret(spID) or spID > 0) then spIcon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spID) end
                if not spIcon then spIcon = 135274 end
                b.spellIcon:SetTexture(spIcon); b.spellIcon:Show()
                b.fill:ClearAllPoints(); b.fill:SetPoint("TOPLEFT", b.spellIcon, "TOPRIGHT", 0, 0); b.fill:SetPoint("BOTTOMRIGHT", b.row, "BOTTOMRIGHT", 0, 0)
                -- HP fill: plain numbers keep the Lua-computed fraction; secret
                -- ones go to the StatusBar whole, which divides engine-side.
                local curHP = ev.currentHP or 0
                local hpPct
                if not IsSecret(curHP) and not maxHPSecret and type(curHP) == "number" then
                    hpPct = maxHP > 0 and (curHP / maxHP) or 0
                    hpPct = math.min(1, math.max(0, hpPct))
                end
                ApplyBarTexture(b.fill, texPath, texKey)
                if hpPct then b.fill:SetMinMaxValues(0, 1); b.fill:SetValue(hpPct)
                else b.fill:SetMinMaxValues(0, maxHPSecret or maxHP); b.fill:SetValue(curHP) end
                local evType = ev.event or ""
                if IsSecret(evType) then evType = "" end
                local isHeal = (evType == "SPELL_HEAL" or evType == "SPELL_PERIODIC_HEAL")
                local isFatal = (i == count and not isHeal)
                if isHeal then b.fill:SetStatusBarColor(0.10, 0.50, 0.10)
                else b.fill:SetStatusBarColor(0.60, 0.08, 0.08) end
                -- A secret name is KEPT: FontStrings display secrets, and the
                -- fallback words would erase a name the engine will show.
                local spellName = ev.spellName
                local nameSecret = IsSecret(spellName)
                if not nameSecret and (not spellName or spellName == "") then
                    if isHeal then spellName = "Heal"
                    elseif evType == "SWING_DAMAGE" then spellName = "Melee"
                    else spellName = "Unknown" end
                end
                b.label:SetTextColor(1, 1, 1); b.amount:SetTextColor(1, 1, 1)
                -- Label: time before death + spell name, engine-formatted so a
                -- secret name never meets Lua concatenation.
                local ts = ev.timestamp
                local td
                if not IsSecret(ts) then td = deathTime - (ts or deathTime) end
                if td then b.label:SetFormattedText("-%.1fs %s", td, spellName)
                else b.label:SetFormattedText("%s", spellName) end
                -- Amount: damage/heal + overkill on killing blow + HP%
                local amt = ev.amount or 0
                local pctStr = hpPct and format(" (%.0f%%)", hpPct * 100) or ""
                if IsSecret(amt) then
                    -- Secret amount: engine abbreviation, no sign/overkill dressing
                    b.amount:SetFormattedText("%s%s", AbbrevNumber(amt), pctStr)
                else
                    local amtStr = isHeal and ("+" .. AbbrevNumber(math.abs(amt))) or ("-" .. AbbrevNumber(amt))
                    local overkill = ev.overkill
                    if isFatal and overkill and not IsSecret(overkill) and type(overkill) == "number" and overkill > 0 then
                        b.amount:SetText(amtStr .. " |cffff3333(" .. AbbrevNumber(overkill) .. " overkill)|r" .. pctStr)
                    else
                        b.amount:SetText(amtStr .. pctStr)
                    end
                end
                b.row:Show()
            else b.row:Hide() end
        end
        _ttFrame:SetSize(TT_WIDTH, TT_HDR_H + count * ttStride - (count > 0 and ttSp or 0))
        return true
    end

    -- Enemy Damage Taken tooltip: show per-player breakdown
    if curDMType == Enum.DamageMeterType.EnemyDamageTaken then
        local guid = bar._srcGUID
        local cid = bar._src.sourceCreatureID
        if issecretvalue and (issecretvalue(guid) or issecretvalue(cid)) then return false end
        local srcData
        if curSessionID and C_DamageMeter.GetCombatSessionSourceFromID then
            srcData = C_DamageMeter.GetCombatSessionSourceFromID(curSessionID, curDMType, guid, cid)
        elseif C_DamageMeter.GetCombatSessionSourceFromType then
            srcData = C_DamageMeter.GetCombatSessionSourceFromType(curSession, curDMType, guid, cid)
        end
        local players = AggregateEnemyPlayers(srcData, GetBreakdownDuration(curSession, curSessionID))
        if not players then return false end

        ApplyTTHeader(StripRealm(bar._src.name, bar._src) or "Unknown", L("Damage Taken"))
        local texPath, texKey = GetBreakdownBarTexturePath()
        local maxAmt = players[1].total
        local ttMax = TT_MAX()
        local count = math.min(ttMax, #players)
        local numFmt = DB().numberFormat or 2
        for i = 1, math.max(ttMax, #_ttBars) do
            local b = EnsureTTBar(i)
            if i <= count then
                local p = players[i]
                -- Use spec icon if available, else class atlas
                local specIcon = p.specIcon
                if specIcon and type(specIcon) == "number" and specIcon ~= 0 then
                    b.spellIcon:SetTexture(specIcon)
                    b.spellIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    b.spellIcon:Show()
                elseif p.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[p.class] then
                    b.spellIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
                    b.spellIcon:SetTexCoord(unpack(CLASS_ICON_TCOORDS[p.class]))
                    b.spellIcon:Show()
                else
                    b.spellIcon:Hide()
                end
                if b.spellIcon:IsShown() then
                    b.fill:ClearAllPoints(); b.fill:SetPoint("TOPLEFT", b.spellIcon, "TOPRIGHT", 0, 0); b.fill:SetPoint("BOTTOMRIGHT", b.row, "BOTTOMRIGHT", 0, 0)
                else
                    b.fill:ClearAllPoints(); b.fill:SetAllPoints(b.row)
                end
                ApplyBarTexture(b.fill, texPath, texKey); b.fill:SetMinMaxValues(0, maxAmt); b.fill:SetValue(p.total)
                local cc = p.class and RAID_CLASS_COLORS[p.class] and EUI.GetClassColor(p.class)
                if cc then b.fill:SetStatusBarColor(cc.r, cc.g, cc.b)
                else b.fill:SetStatusBarColor(0x33/255, 0x33/255, 0x33/255) end
                b.label:SetTextColor(1, 1, 1); b.amount:SetTextColor(1, 1, 1)
                b.label:SetText(StripRealm(p.name, nil, p))
                b.amount:SetText(FormatBarValue(p.total, p.amountPerSecond, numFmt))
                b.row:Show()
            else b.row:Hide() end
        end
        _ttFrame:SetSize(TT_WIDTH, TT_HDR_H + count * ttStride - (count > 0 and ttSp or 0))
        return true
    end

    -- Standard spell breakdown tooltip
    local guid = bar._srcGUID
    local cid = bar._src.sourceCreatureID
    if issecretvalue and (issecretvalue(guid) or issecretvalue(cid)) then
        -- Mid-combat the row guids are SECRET and the getters refuse secret
        -- ARGUMENTS from addon code -- but plain guids stay legal. Own row:
        -- UnitGUID("player"). Group rows: the identity-exempt token channel
        -- (ResolveGroupGUID). Anything unresolvable (enemies, creature rows,
        -- identity-restricted content) stays blocked until combat ends.
        if IsOwnRow(bar._src) then
            guid, cid = UnitGUID("player"), nil
        else
            guid, cid = ResolveGroupGUID(bar._src), nil
            if not guid then return false end
        end
    end
    local srcData
    if curSessionID and C_DamageMeter.GetCombatSessionSourceFromID then
        srcData = C_DamageMeter.GetCombatSessionSourceFromID(curSessionID, curDMType, guid, cid)
    elseif C_DamageMeter.GetCombatSessionSourceFromType then
        srcData = C_DamageMeter.GetCombatSessionSourceFromType(curSession, curDMType, guid, cid)
    end
    if not srcData or not srcData.combatSpells or #srcData.combatSpells == 0 then return false end

    ApplyTTHeader(StripRealm(bar._src.name, bar._src), L(DM_TYPE_NAMES[curDMType] or "Damage Done"))

    wipe(_ttSorted)
    for _, spell in ipairs(srcData.combatSpells) do
        local amt = spell.totalAmount
        -- A secret amount is KEPT whole: StatusBar and FontString sinks take
        -- it, and zeroing it emptied every in-combat row. canPercent below is
        -- what keeps it out of Lua arithmetic.
        if not IsSecret(amt) and type(amt) ~= "number" then amt = 0 end
        _ttSorted[#_ttSorted + 1] = { spell = spell, amount = amt }
    end
    local maxAmt = _ttSorted[1] and _ttSorted[1].amount or 1
    local totalDmg = 0
    local canPercent = type(maxAmt) == "number" and (not issecretvalue or not issecretvalue(maxAmt))
    if canPercent then for _, e in ipairs(_ttSorted) do totalDmg = totalDmg + e.amount end end
    local texPath, texKey = GetBreakdownBarTexturePath()
    local ttMax = TT_MAX()
    local count = math.min(ttMax, #_ttSorted)
    for i = 1, math.max(ttMax, #_ttBars) do
        local b = EnsureTTBar(i)
        if i <= count then
            local entry = _ttSorted[i]
            local spell = entry.spell
            local hasIcon = false
            -- A combatSpells spellID is secret in combat. GetSpellTexture takes a
            -- secret id (AllowedWhenTainted; Blizzard's own meter passes it straight
            -- in) but rejects some outright ("bad argument #1": open-world non-group
            -- participants), so a secret id goes through pcall and its result is
            -- tested by type() only, never by truthiness (it may come back secret).
            local spID = spell.spellID
            local getTex = C_Spell and C_Spell.GetSpellTexture
            if spID and getTex then
                if IsSecret(spID) then
                    local ok, spIcon = pcall(getTex, spID)
                    if ok and type(spIcon) ~= "nil" then
                        hasIcon = true
                        b.spellIcon:SetTexture(spIcon); b.spellIcon:Show()
                    end
                else
                    local spIcon = getTex(spID)
                    if spIcon then
                        hasIcon = true
                        b.spellIcon:SetTexture(spIcon); b.spellIcon:Show()
                    end
                end
            end
            if not hasIcon then b.spellIcon:Hide() end
            -- Only re-anchor fill when icon state changes
            if hasIcon ~= b._lastHasIcon then
                b._lastHasIcon = hasIcon
                b.fill:ClearAllPoints()
                if hasIcon then
                    b.fill:SetPoint("TOPLEFT", b.spellIcon, "TOPRIGHT", 0, 0)
                    b.fill:SetPoint("BOTTOMRIGHT", b.row, "BOTTOMRIGHT", 0, 0)
                else
                    b.fill:SetAllPoints(b.row)
                end
            end
            ApplyBarTexture(b.fill, texPath, texKey); b.fill:SetMinMaxValues(0, maxAmt); b.fill:SetValue(entry.amount)
            b.fill:SetStatusBarColor(0x33/255, 0x33/255, 0x33/255)
            local spellName
            if spell.spellID then
                -- GetSpellName takes a secret id, and a secret NAME is kept:
                -- SetText displays it, where the old nil-out fell to "Unknown".
                spellName = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spell.spellID)
            end
            b.label:SetText(spellName or spell.creatureName or "Unknown")
            if canPercent and totalDmg > 0 then
                b.amount:SetText(format("%s  %.1f%%", AbbrevNumber(entry.amount), (entry.amount / totalDmg) * 100))
            else
                b.amount:SetText(AbbrevNumber(entry.amount))
            end
            b.row:Show()
        else b.row:Hide() end
    end
    -- Targets sub-section (DamageDone only): top 3 enemies this player hit.
    -- Skipped in combat: it is built by cross-referencing and COMPARING
    -- amounts across sources in Lua, which secrets cannot survive.
    local ttTargetCount = 0
    if curDMType == Enum.DamageMeterType.DamageDone and not InCombatLockdown() then
        local rawName = bar._src and bar._src.name
        local targets = BuildPlayerTargets(rawName, curSession, curSessionID, 3)
        if targets then
            -- Lazy-create tooltip target elements
            if not _ttFrame._tgtDivider then
                _ttFrame._tgtDivider = _ttFrame:CreateTexture(nil, "ARTWORK")
                _ttFrame._tgtDivider:SetHeight(TTPhysicalPixels(1)); _ttFrame._tgtDivider:SetColorTexture(1, 1, 1, 0.15)
                _ttFrame._tgtLabel = _ttFrame:CreateFontString(nil, "OVERLAY")
                SetDMFont(_ttFrame._tgtLabel, 9); _ttFrame._tgtLabel:SetTextColor(0.6, 0.6, 0.6, 1)
                _ttFrame._tgtLabel:SetText(EllesmereUI.L("Targets"))
                _ttFrame._tgtBars = {}
                for ti = 1, 3 do
                    local tb = {}
                    tb.row = CreateFrame("Frame", nil, _ttFrame); tb.row:SetHeight(TT_BAR_H)
                    tb.fill = CreateFrame("StatusBar", nil, tb.row); tb.fill:SetAllPoints(); tb.fill:SetMinMaxValues(0, 1); tb.fill:SetStatusBarTexture(BAR_TEX)
                    local tf = CreateFrame("Frame", nil, tb.fill); tf:SetAllPoints(tb.fill); tf:SetFrameLevel(tb.fill:GetFrameLevel() + 2)
                    tb.label = tf:CreateFontString(nil, "OVERLAY"); tb.label:SetPoint("LEFT", tf, "LEFT", 2, 0); tb.label:SetJustifyH("LEFT"); SetDMFont(tb.label, 10)
                    tb.amount = tf:CreateFontString(nil, "OVERLAY"); tb.amount:SetPoint("RIGHT", tf, "RIGHT", -2, 0); tb.amount:SetJustifyH("RIGHT"); SetDMFont(tb.amount, 10)
                    tb.label:SetPoint("RIGHT", tb.amount, "LEFT", -3, 0)
                    tb.row:Hide()
                    _ttFrame._tgtBars[ti] = tb
                end
            end
            local baseY = -(TT_HDR_H + count * ttStride + ttSp * 2)
            _ttFrame._tgtDivider:ClearAllPoints()
            _ttFrame._tgtDivider:SetPoint("TOPLEFT", _ttFrame, "TOPLEFT", 0, baseY)
            _ttFrame._tgtDivider:SetPoint("TOPRIGHT", _ttFrame, "TOPRIGHT", 0, baseY)
            _ttFrame._tgtDivider:Show()
            local lblY = baseY - 10
            _ttFrame._tgtLabel:ClearAllPoints()
            _ttFrame._tgtLabel:SetPoint("LEFT", _ttFrame, "TOPLEFT", 3, lblY)
            _ttFrame._tgtLabel:Show()
            local tStartY = lblY - 10
            local tMaxAmt = targets[1].total
            for ti = 1, 3 do
                local tb = _ttFrame._tgtBars[ti]
                if ti <= #targets then
                    local t = targets[ti]
                    tb.row:ClearAllPoints()
                    tb.row:SetPoint("TOPLEFT", _ttFrame, "TOPLEFT", 0, tStartY - ((ti-1) * ttStride))
                    tb.row:SetPoint("TOPRIGHT", _ttFrame, "TOPRIGHT", 0, tStartY - ((ti-1) * ttStride))
                    ApplyBarTexture(tb.fill, texPath, texKey); tb.fill:SetMinMaxValues(0, tMaxAmt); tb.fill:SetValue(t.total)
                    tb.fill:SetStatusBarColor(0xDD/255, 0x31/255, 0x31/255)
                    tb.label:SetTextColor(1, 1, 1); tb.amount:SetTextColor(1, 1, 1)
                    tb.label:SetText(t.name)
                    tb.amount:SetText(FormatBarValue(t.total, t.amountPerSecond, DB().numberFormat or 2))
                    tb.row:Show()
                    ttTargetCount = ttTargetCount + 1
                else tb.row:Hide() end
            end
        end
    end
    -- Hide target elements if not used
    if ttTargetCount == 0 and _ttFrame and _ttFrame._tgtDivider then
        _ttFrame._tgtDivider:Hide(); _ttFrame._tgtLabel:Hide()
        for ti = 1, 3 do _ttFrame._tgtBars[ti].row:Hide() end
    end
    local totalH = TT_HDR_H + count * ttStride - (count > 0 and ttSp or 0)
    if ttTargetCount > 0 then
        totalH = totalH + (ttSp * 2) + 1 + 10 + 10 + (ttTargetCount * ttStride)
    end
    _ttFrame:SetSize(TT_WIDTH, totalH)

    return true
end

local _ttLastScale
I.ttLastScaleSetters[#I.ttLastScaleSetters + 1] = function(v) _ttLastScale = v end

-- Single anchor chokepoint for the breakdown frame. Modes: "row" (above hovered row, default),
-- "center" (screen center), "left"/"right" (beside the meter window, falls back to "row" if the window frame is missing).
local function AnchorBreakdownFrame(rowFrame, winFrame)
    local mode = DB().breakdownAnchorPoint
    _ttFrame:ClearAllPoints()
    if mode == "center" then
        _ttFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    elseif mode == "left" and winFrame then
        _ttFrame:SetPoint("TOPRIGHT", winFrame, "TOPLEFT", -6, 0)
    elseif mode == "right" and winFrame then
        _ttFrame:SetPoint("TOPLEFT", winFrame, "TOPRIGHT", 6, 0)
    else
        _ttFrame:SetPoint("BOTTOMRIGHT", rowFrame, "TOPRIGHT", 0, 0)
    end
end
-- ns alias for call sites inside CreateDMWindow: referencing the local there
-- would add an upvalue, and CreateDMWindow sits at Lua 5.1's 60-upvalue cap.
ns._AnchorBreakdownFrame = AnchorBreakdownFrame

local function HideBarTooltip()
    if _ttFrame then _ttFrame:Hide() end
end

local function ShowBarTooltip(bar, curSession, curSessionID, curDMType)
    local cfg = DB()
    if cfg.showHoverTooltip == false then return end
    EnsureTooltipFrame()

    -- Scale before populating: the row stride snaps against the frame's effective scale.
    local scale = (cfg.hoverTooltipScale or 100) / 100
    if scale ~= _ttLastScale then
        _ttFrame:SetScale(scale)
        SetTTLastScale(scale)
    end

    -- Always rebuild from fresh data (no GUID cache); PopulatePreview costs ~0.5ms, fine for a hover action
    if PopulatePreview(bar, curSession, curSessionID, curDMType) then
        AnchorBreakdownFrame(bar.row, bar._win and bar._win.frame)
        _ttFrame:Show()
    else
        HideBarTooltip()
    end
end

local _hoverPollFrame = CreateFrame("Frame")
_hoverPollFrame:Hide()
_hoverPollFrame:SetScript("OnUpdate", function()
    if not _activeRow then return end
    if not _ttVisible and _activeRow._win then
        local W = _activeRow._win
        ShowBarTooltip(_activeRow, W.curSession, W.curSessionID, W.curDMType)
    end
end)

I._hoverPollFrame, I._ttBars = _hoverPollFrame, _ttBars
I.ApplyInheritedBlizzardBorder = ApplyInheritedBlizzardBorder
I.EnsureTooltipFrame, I.HideBarTooltip = EnsureTooltipFrame, HideBarTooltip
I.HideTTTargets, I.TT_HDR_H, I.TT_WIDTH = HideTTTargets, TT_HDR_H, TT_WIDTH
I.broken = false
