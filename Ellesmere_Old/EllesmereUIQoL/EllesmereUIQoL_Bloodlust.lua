-------------------------------------------------------------------------------
--  EllesmereUIQoL_Bloodlust.lua
--  Runtime for the Bloodlust Tracker icon. Detects the player's Sated /
--  Exhaustion lockout debuff (the "you cannot Bloodlust again yet" debuff) and
--  shows a single icon with the remaining lockout timer.
--
--  Lightweight by design:
--    * Only registers UNIT_AURA filtered to the player unit (never all units,
--      never a global aura scan) and only while the tracker is enabled.
--    * Pure event driven detection + a 0.5s text ticker that runs only while
--      the icon is actually shown.
--
--  Appearance proxy-reads through to the BattleRes icon: any appearance key the
--  user has NOT overridden on the Bloodlust Tracker uses the BattleRes value,
--  so the tracker "starts identical" to Brez and only diverges once a setting
--  is changed here (the same model used for raid/party frames). Only the Enable
--  dropdown and on-screen position are stored independently per icon. Both icons
--  live side by side in EllesmereUIQoLDB.profile (battleRes + bloodlust), so
--  existing BattleRes data is never touched.
-------------------------------------------------------------------------------

-- The active lust BUFF id, used purely as the default/preview icon texture.
local PREVIEW_SPELL_ID = 2825  -- Bloodlust

-- Sated / Exhaustion debuff ids (every lust variant's lockout debuff). These
-- mirror the SATED_DEBUFFS list used by the Raid Frames lust filter.
local SATED_DEBUFFS = {
    57723,   -- Exhaustion (Heroism)
    57724,   -- Sated (Bloodlust)
    80354,   -- Temporal Displacement (Time Warp)
    95809,   -- Insanity (Ancient Hysteria)
    160455,  -- Fatigued (Netherwinds)
    264689,  -- Fatigued (Primal Rage)
    390435,  -- Exhaustion (Fury of the Aspects)
}

local SHAPE_MEDIA = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\"
local SHAPE_MASKS = {
    circle   = SHAPE_MEDIA .. "circle_mask.tga",
    csquare  = SHAPE_MEDIA .. "csquare_mask.tga",
    diamond  = SHAPE_MEDIA .. "diamond_mask.tga",
    hexagon  = SHAPE_MEDIA .. "hexagon_mask.tga",
    portrait = SHAPE_MEDIA .. "portrait_mask.tga",
    shield   = SHAPE_MEDIA .. "shield_mask.tga",
    square   = SHAPE_MEDIA .. "square_mask.tga",
}
local SHAPE_BORDERS = {
    circle   = SHAPE_MEDIA .. "circle_border.tga",
    csquare  = SHAPE_MEDIA .. "csquare_border.tga",
    diamond  = SHAPE_MEDIA .. "diamond_border.tga",
    hexagon  = SHAPE_MEDIA .. "hexagon_border.tga",
    portrait = SHAPE_MEDIA .. "portrait_border.tga",
    shield   = SHAPE_MEDIA .. "shield_border.tga",
    square   = SHAPE_MEDIA .. "square_border.tga",
}
local BORDER_PX = { none = 0, thin = 1, normal = 2, heavy = 3, strong = 4 }

-------------------------------------------------------------------------------
--  DB access. We reuse the BattleRes DB handle (same SavedVariable) so we do
--  not create a second NewDB on the shared table.
-------------------------------------------------------------------------------
local db
local function P()  -- our own profile slice
    return db and db.profile and db.profile.bloodlust
end
local function BR()  -- BattleRes profile slice (proxy fallback source)
    return db and db.profile and db.profile.battleRes
end

-- Per-key fallback defaults (mirror the battleRes appearance defaults). Used
-- only when neither the bloodlust override nor the battleRes value exists.
local APP_DEFAULTS = {
    iconSize        = 40,
    iconZoom        = 11,
    shape           = "none",
    borderSize      = "thin",
    borderUseClass  = false,
    durationSize    = 12,
    durationOffsetX = 0,
    durationOffsetY = 0,
    countSize       = 11,
    countOffsetX    = 0,
    countOffsetY    = 0,
}

-- Effective (proxied) appearance value: bloodlust override -> battleRes -> default.
local function EP(key)
    local bl = P()
    if bl and bl[key] ~= nil then return bl[key] end
    local br = BR()
    if br and br[key] ~= nil then return br[key] end
    return APP_DEFAULTS[key]
end

local function EP_borderColor()
    local bl = P()
    if bl and bl.borderColor ~= nil then return bl.borderColor end
    local br = BR()
    if br and br.borderColor ~= nil then return br.borderColor end
    return { r = 0, g = 0, b = 0, a = 1 }
end

local frame, iconTex, borderTex, durationFS, countFS, cooldownFrame
local buffOverlay, buffTex, buffCooldown, buffDurationFS  -- the 40s active-lust overlay (sits on top of the debuff icon)
local _satedActive = false
local _satedWasPresent = false  -- rising-edge baseline so only a FRESH debuff arms the buff window
local _buffExpiry = 0           -- GetTime() when the 40s active-buff window ends
local _buffZoneGuard = 0        -- suppress rising edges until this time (set on zone-in)
-- Last known Sated expiry (GetTime() clock). Synced from the real
-- expirationTime whenever it is readable, and armed as now+600 on a fresh
-- rising edge (every lust lockout is 10 minutes). While 12.1 aura
-- restrictions hide the real value in combat, this carries the countdown.
local _satedExpiryGuess = 0
local UpdateVisibility  -- forward declaration (referenced by PollSated below)
local FormatTime        -- forward declaration (shared by the debuff text and the buff overlay)

-------------------------------------------------------------------------------
--  Shape / appearance application (mirrors the BattleRes icon)
-------------------------------------------------------------------------------
local function _resolveBorderColor()
    if EP("borderUseClass") then
        local _, ct = UnitClass("player")
        if ct and RAID_CLASS_COLORS[ct] then
            return RAID_CLASS_COLORS[ct].r, RAID_CLASS_COLORS[ct].g, RAID_CLASS_COLORS[ct].b, 1
        end
    end
    local c = EP_borderColor()
    if c then return c.r or 0, c.g or 0, c.b or 0, c.a or 1 end
    return 0, 0, 0, 1
end

-- Configure the buff overlay (texture coords + optional shape mask) so it
-- visually matches the debuff icon underneath it. The overlay owns its OWN mask
-- so the debuff icon's mask lifecycle is never touched.
local function _applyBuffShape()
    if not buffOverlay then return end
    local shape = EP("shape") or "none"

    buffOverlay:ClearAllPoints()
    buffOverlay:SetAllPoints(frame)
    buffTex:SetAllPoints(buffOverlay)
    buffCooldown:ClearAllPoints()
    buffCooldown:SetAllPoints(buffOverlay)

    -- Match the debuff icon's duration text exactly (font, size, position).
    buffDurationFS:SetFont((EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("extras")) or STANDARD_TEXT_FONT, EP("durationSize") or 12, (EllesmereUI and EllesmereUI.SlugFlag and EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG")
    buffDurationFS:ClearAllPoints()
    buffDurationFS:SetPoint("CENTER", frame, "CENTER", EP("durationOffsetX") or 0, EP("durationOffsetY") or 0)

    if shape == "none" or shape == "cropped" then
        if buffTex._mask then
            if not buffCooldown:IsForbidden() then
                pcall(buffCooldown.RemoveMaskTexture, buffCooldown, buffTex._mask)
                pcall(buffCooldown.SetSwipeTexture, buffCooldown, "")
            end
            buffTex:RemoveMaskTexture(buffTex._mask)
            buffTex._mask:SetTexture(nil)
            buffTex._mask:Hide()
            buffTex._mask = nil
        end
        local z = (EP("iconZoom") or 11) / 100
        if shape == "cropped" then
            buffTex:SetTexCoord(z, 1 - z, z + 0.10, 1 - z - 0.10)
        elseif z > 0 then
            buffTex:SetTexCoord(z, 1 - z, z, 1 - z)
        else
            buffTex:SetTexCoord(0, 1, 0, 1)
        end
        return
    end

    local maskPath = SHAPE_MASKS[shape]
    if maskPath then
        if not buffTex._mask then
            buffTex._mask = buffOverlay:CreateMaskTexture()
            buffTex._mask:SetAllPoints(buffTex)
            buffTex:AddMaskTexture(buffTex._mask)
        end
        buffTex._mask:SetTexture(maskPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        buffTex._mask:Show()
        buffTex:SetTexCoord(0, 1, 0, 1)
        if not buffCooldown:IsForbidden() then
            pcall(buffCooldown.AddMaskTexture, buffCooldown, buffTex._mask)
            pcall(buffCooldown.SetSwipeTexture, buffCooldown, maskPath)
        end
    end
end

local function ApplyShape()
    if not frame then return end

    local PP = EllesmereUI and EllesmereUI.PP
    local shape = EP("shape") or "none"
    local bs = BORDER_PX[EP("borderSize") or "thin"] or 1

    local size = EP("iconSize") or 40
    local fw, fh = size, size
    if shape == "cropped" then fh = math.floor(size * 0.80 + 0.5) end
    frame:SetSize(fw, fh)
    iconTex:ClearAllPoints()
    iconTex:SetAllPoints(frame)

    if cooldownFrame then
        cooldownFrame:ClearAllPoints()
        cooldownFrame:SetAllPoints(frame)
    end

    -- Duration text (centered) and count text (bottom-right). Sated debuffs
    -- have no stacks so the count string stays empty, but we keep the field for
    -- 1:1 parity with the BattleRes icon layout.
    durationFS:SetFont((EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("extras")) or STANDARD_TEXT_FONT, EP("durationSize") or 12, (EllesmereUI and EllesmereUI.SlugFlag and EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG")
    durationFS:ClearAllPoints()
    durationFS:SetPoint("CENTER", frame, "CENTER",
        EP("durationOffsetX") or 0, EP("durationOffsetY") or 0)

    countFS:SetFont((EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("extras")) or STANDARD_TEXT_FONT, EP("countSize") or 11, (EllesmereUI and EllesmereUI.SlugFlag and EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG")
    countFS:ClearAllPoints()
    countFS:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT",
        -2 + (EP("countOffsetX") or 0), 2 + (EP("countOffsetY") or 0))

    -----------------------------------------------------------------------
    --  BASE CASE: "none" or "cropped" -- plain texture, no mask
    -----------------------------------------------------------------------
    if shape == "none" or shape == "cropped" then
        if iconTex._mask then
            if cooldownFrame and not cooldownFrame:IsForbidden() then
                pcall(cooldownFrame.RemoveMaskTexture, cooldownFrame, iconTex._mask)
                if cooldownFrame.SetSwipeTexture then
                    pcall(cooldownFrame.SetSwipeTexture, cooldownFrame, "")
                end
            end
            iconTex:RemoveMaskTexture(iconTex._mask)
            iconTex._mask:SetTexture(nil)
            iconTex._mask:ClearAllPoints()
            iconTex._mask:SetSize(0.001, 0.001)
            iconTex._mask:Hide()
            iconTex._mask = nil
        end
        borderTex:Hide()

        local z = (EP("iconZoom") or 11) / 100
        if shape == "cropped" then
            iconTex:SetTexCoord(z, 1 - z, z + 0.10, 1 - z - 0.10)
        elseif z > 0 then
            iconTex:SetTexCoord(z, 1 - z, z, 1 - z)
        else
            iconTex:SetTexCoord(0, 1, 0, 1)
        end

        if PP then
            if not PP.GetBorders(frame) then PP.CreateBorder(frame, 0, 0, 0, 1, 1, "OVERLAY", 2) end
            if bs > 0 then
                local r, g, b, a = _resolveBorderColor()
                PP.UpdateBorder(frame, bs, r, g, b, a)
                PP.ShowBorder(frame)
            else
                PP.HideBorder(frame)
            end
        end
        return
    end

    -----------------------------------------------------------------------
    --  CUSTOM SHAPE: apply mask + shape-matching border overlay
    -----------------------------------------------------------------------
    if PP then PP.HideBorder(frame) end

    local maskPath = SHAPE_MASKS[shape]
    if maskPath then
        if not iconTex._mask then
            iconTex._mask = frame:CreateMaskTexture()
            iconTex._mask:SetAllPoints(iconTex)
            iconTex:AddMaskTexture(iconTex._mask)
        end
        iconTex._mask:SetTexture(maskPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        iconTex._mask:Show()
        iconTex:SetTexCoord(0, 1, 0, 1)
        if cooldownFrame and not cooldownFrame:IsForbidden() then
            pcall(cooldownFrame.AddMaskTexture, cooldownFrame, iconTex._mask)
            if cooldownFrame.SetSwipeTexture then
                pcall(cooldownFrame.SetSwipeTexture, cooldownFrame, maskPath)
            end
        end
    elseif cooldownFrame and not cooldownFrame:IsForbidden() then
        if iconTex._mask then
            pcall(cooldownFrame.RemoveMaskTexture, cooldownFrame, iconTex._mask)
        end
        if cooldownFrame.SetSwipeTexture then
            pcall(cooldownFrame.SetSwipeTexture, cooldownFrame, "")
        end
    end

    local borderPath = SHAPE_BORDERS[shape]
    if borderPath and bs > 0 then
        borderTex:SetTexture(borderPath)
        borderTex:ClearAllPoints()
        borderTex:SetPoint("TOPLEFT", frame, "TOPLEFT", -bs, bs)
        borderTex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", bs, -bs)
        local r, g, b, a = _resolveBorderColor()
        borderTex:SetVertexColor(r, g, b, a)
        borderTex:Show()
    else
        borderTex:Hide()
    end
end

-------------------------------------------------------------------------------
--  Position. Default starting position sits just to the LEFT of the BattleRes
--  icon, so the first time the tracker is enabled it appears next to Brez.
-------------------------------------------------------------------------------
local function _defaultLeftOfBrezCenter()
    local br = BR()
    local brCX, brCY = 0, 200
    if br and br.pos and br.pos.centerX and br.pos.centerY then
        brCX, brCY = br.pos.centerX, br.pos.centerY
    end
    local brSize = (br and br.iconSize) or 40
    local myW = EP("iconSize") or 40
    local gap = 6
    return brCX - (brSize * 0.5 + gap + myW * 0.5), brCY
end

local function ApplyPosition()
    if not frame then return end
    local p = P()
    if not p then return end
    frame:ClearAllPoints()
    if p.pos and p.pos.centerX and p.pos.centerY then
        frame:SetPoint("CENTER", UIParent, "CENTER", p.pos.centerX, p.pos.centerY)
    else
        local cx, cy = _defaultLeftOfBrezCenter()
        frame:SetPoint("CENTER", UIParent, "CENTER", cx, cy)
    end
end

local function SavePosition()
    if not frame or not db then return end
    local left, bottom = frame:GetLeft(), frame:GetBottom()
    if not left or not bottom then return end
    local fw, fh = frame:GetSize()
    local cx = left + fw / 2 - UIParent:GetWidth() / 2
    local cy = bottom + fh / 2 - UIParent:GetHeight() / 2
    local p = P(); if p then p.pos = { centerX = cx, centerY = cy } end
end

-- Seed a concrete starting position (left of Brez) the first time the tracker
-- is switched away from "Never". Does nothing if a position already exists.
local function SeedDefaultPos()
    local p = P(); if not p then return end
    if p.pos then return end
    local cx, cy = _defaultLeftOfBrezCenter()
    p.pos = { centerX = cx, centerY = cy }
    ApplyPosition()
end
_G._EUI_Bloodlust_SeedPos = SeedDefaultPos

-------------------------------------------------------------------------------
--  Detection (player-only, secret-value safe)
-------------------------------------------------------------------------------
local function _findSated()
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return nil end
    for i = 1, #SATED_DEBUFFS do
        local sid = SATED_DEBUFFS[i]
        -- Querying a KNOWN spellId returns the aura even when its fields would
        -- be secret in combat, so detection works mid-fight. We never read the
        -- (possibly secret) spellId back off the aura -- we already know it.
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(sid)
        if aura then return aura, sid end
    end
    return nil
end

-- 12.1: duration APIs (GetAuraDuration included) hard-error while aura
-- restrictions are active, even with a clean auraInstanceID. Hard false on
-- a 12.0 client so every restricted branch below is provably dead there.
local function AurasRestricted()
    if not (EllesmereUI and EllesmereUI.IS_121) then return false end
    local AK = EllesmereUI.AuraKit
    if AK and AK.AurasRestricted then return AK.AurasRestricted() end
    return false
end

-- Sync the expiry cache from the aura whenever the real value is readable
-- (out of combat / unrestricted content). 12.1-only machinery: the cache is
-- only ever displayed under aura restrictions, which do not exist on 12.0.
local function _syncSatedGuess(aura)
    if not (EllesmereUI and EllesmereUI.IS_121) then return end
    local exp = aura and aura.expirationTime
    if exp and not issecretvalue(exp) and exp > 0 then
        _satedExpiryGuess = exp
    end
end

-- Drive the icon texture + cooldown swipe from the active debuff. Secret-safe:
-- the swipe is set from a DurationObject (no value is read by us); under 12.1
-- restrictions it falls back to the cached/self-timed expiry. The numeric
-- countdown text is filled in by the ticker with the same fallback.
local function _applyActiveAura(aura, sid)
    if not frame then return end

    local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid)
    if not tex and C_Spell and C_Spell.GetSpellTexture then
        tex = C_Spell.GetSpellTexture(PREVIEW_SPELL_ID)
    end
    iconTex:SetTexture(tex or 136080)

    if cooldownFrame then
        local iid = aura.auraInstanceID
        if AurasRestricted() then
            -- Swipe from the cached expiry; SetCooldown with the same start
            -- and duration every pass is idempotent (no animation reset).
            if _satedExpiryGuess > GetTime() then
                cooldownFrame:SetCooldown(_satedExpiryGuess - 600, 600)
            end
        elseif iid and not issecretvalue(iid) and C_UnitAuras.GetAuraDuration then
            local durObj = C_UnitAuras.GetAuraDuration("player", iid)
            if durObj then
                cooldownFrame:SetCooldownFromDurationObject(durObj)
            end
        else
            local dur = aura.duration
            local exp = aura.expirationTime
            if dur and exp and not issecretvalue(dur) and not issecretvalue(exp) and dur > 0 then
                cooldownFrame:SetCooldown(exp - dur, dur)
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Active-lust buff overlay. When the lockout debuff is freshly acquired (lust
--  was just cast) we lay a 40s buff icon + cooldown swipe ON TOP of the debuff
--  icon. We cannot read the actual buff, so the 40s window is self-timed. After
--  40s (or on death) the overlay hides, revealing the untouched debuff icon.
-------------------------------------------------------------------------------
-- Horde casts Bloodlust, Alliance casts Heroism; both active buffs last 40s.
local function _lustBuffIcon()
    return (UnitFactionGroup("player") == "Alliance") and 132313 or 136012
end

-- Countdown text for the overlay, deduped so we only SetText on a real change.
local _lastBuffDurText
local function _setBuffDur(s)
    if s ~= _lastBuffDurText then
        buffDurationFS:SetText(s)
        _lastBuffDurText = s
    end
end

-- Drives the 40s countdown text and hides the overlay the instant it expires.
-- Runs only while the overlay is shown (cleared on hide), so it is never an idle
-- OnUpdate. The expiry check is every frame; the text refresh is throttled.
local _buffAccum = 0
local function _buffOnUpdate(_, elapsed)
    local rem = _buffExpiry - GetTime()
    if rem <= 0 then
        buffOverlay:SetScript("OnUpdate", nil)
        buffOverlay:Hide()
        _setBuffDur("")
        return
    end
    _buffAccum = _buffAccum + (elapsed or 0)
    if _buffAccum < 0.1 then return end
    _buffAccum = 0
    -- Buff window is only 40s, so show plain seconds ("40", "39", ...) with no
    -- leading "0:". ceil keeps each number on screen for its full second.
    _setBuffDur(tostring(math.ceil(rem)))
end

local function _showBuffOverlay()
    if not buffOverlay then return end
    buffTex:SetTexture(_lustBuffIcon())
    _applyBuffShape()
    _buffExpiry = GetTime() + 40
    _buffAccum = 0
    buffCooldown:SetCooldown(GetTime(), 40)
    _setBuffDur("40")
    buffOverlay:Show()
    buffOverlay:SetScript("OnUpdate", _buffOnUpdate)
end

local function _hideBuffOverlay()
    _buffExpiry = 0
    if buffOverlay then
        buffOverlay:SetScript("OnUpdate", nil)
        buffOverlay:Hide()
    end
    _setBuffDur("")
end

-------------------------------------------------------------------------------
--  Content state (mirrors the BattleRes icon so "M+"/"Raid" mean the same
--  thing: M+ = an active keystone run, Raid = a raid encounter in progress).
-------------------------------------------------------------------------------
local _state = {
    inEncounter     = false,
    encounterIsRaid = false,
    inChallenge     = false,
}

local function _activeKeystoneLevel()
    if not C_ChallengeMode then return nil end
    if not C_ChallengeMode.IsChallengeModeActive or not C_ChallengeMode.IsChallengeModeActive() then
        return nil
    end
    if C_ChallengeMode.GetActiveKeystoneInfo then
        local lvl = C_ChallengeMode.GetActiveKeystoneInfo()
        return (lvl and lvl > 0) and lvl or nil
    end
    return nil
end

local function _refreshKeystoneState()
    _state.inChallenge = _activeKeystoneLevel() ~= nil
end

local function _refreshEncounterState()
    _state.inEncounter = IsEncounterInProgress() or false
    if _state.inEncounter then
        local _, instanceType = GetInstanceInfo()
        _state.encounterIsRaid = (instanceType == "raid")
    else
        _state.encounterIsRaid = false
    end
end

-------------------------------------------------------------------------------
--  Visibility / text
-------------------------------------------------------------------------------
local function ShouldShow()
    local p = P()
    if not p or not p.enabled then return false end
    local v = p.visibility or "NEVER"
    if v == "NEVER" then return false end
    if not _satedActive then return false end

    -- Hard gate: must be in a party or raid instance. Prevents any stuck state
    -- from showing the icon in town / open world.
    local _, instanceType = GetInstanceInfo()
    if instanceType ~= "party" and instanceType ~= "raid" then return false end

    local wantMPlus = (v == "MPLUS_AND_RAID" or v == "MPLUS")
    local wantRaid  = (v == "MPLUS_AND_RAID" or v == "RAID")
    if wantMPlus and _state.inChallenge then return true end
    if wantRaid and _state.inEncounter and _state.encounterIsRaid then return true end
    return false
end

function FormatTime(s)
    if not s or s <= 0 then return "" end
    local m = math.floor(s / 60)
    local sec = math.floor(s % 60)
    return string.format("%d:%02d", m, sec)
end

local _lastDurText
local function _setDur(s)
    if s ~= _lastDurText then
        durationFS:SetText(s)
        _lastDurText = s
    end
end

-- Text ticker: updates the countdown number and re-confirms the debuff is still
-- present (a safety net in case a UNIT_AURA removal event is ever missed). When
-- the remaining time is secret (in combat) the swipe still animates but the
-- number is left blank.
local function PollSated()
    if not frame then return end
    local aura = _findSated()
    if not aura then
        _satedActive = false
        _satedExpiryGuess = 0
        _setDur("")
        return UpdateVisibility()
    end
    local exp = aura.expirationTime
    if exp and not issecretvalue(exp) then
        _syncSatedGuess(aura)
        local rem = exp - GetTime()
        _setDur(rem > 0 and FormatTime(rem) or "")
    elseif EllesmereUI.IS_121 and _satedExpiryGuess > GetTime() then
        -- Real value secret (12.1 combat): count down on the cached expiry.
        _setDur(FormatTime(_satedExpiryGuess - GetTime()))
    else
        _setDur("")
    end
end

local _ticker
function UpdateVisibility()
    if not frame then return end
    if ShouldShow() then
        if not frame:IsShown() then frame:Show() end
        if not _ticker then _ticker = C_Timer.NewTicker(0.5, PollSated) end
        PollSated()
    else
        if frame:IsShown() then frame:Hide() end
        if _ticker then _ticker:Cancel(); _ticker = nil end
    end
end
_G._EUI_Bloodlust_UpdateVisibility = UpdateVisibility

local function _refreshSated()
    local aura, sid = _findSated()
    _satedActive = (aura ~= nil)
    if aura then
        _syncSatedGuess(aura)
        _applyActiveAura(aura, sid)
    else
        _satedExpiryGuess = 0
    end
    return _satedActive
end

-------------------------------------------------------------------------------
--  Events. The ONLY aura registration is UNIT_AURA filtered to the player unit
--  (never all units, never a global aura scan). The encounter / keystone events
--  mirror the BattleRes icon so the M+/Raid visibility modes match. Everything
--  is registered solely while the tracker is enabled.
-------------------------------------------------------------------------------
local _eventFrame
local function _onEvent(_, event, _, updateInfo)
    if event == "UNIT_AURA" then
        local was = _satedWasPresent
        local present = _refreshSated()
        _satedWasPresent = present
        -- Rising edge = lust was just cast. Arm the 40s active-buff overlay ONLY
        -- on a genuine incremental application: never on a full aura refresh
        -- (zone/login resends every aura) and never inside the post-zone grace
        -- window, so a Sated debuff we already carry when zoning out of a dungeon
        -- can't re-pop the overlay.
        -- 12.1: the UNIT_AURA payload (and its fields) can be SECRET in combat;
        -- a secret payload is treated as incremental (full refreshes come from
        -- zone/login, which the zone guard covers; boolean use of a secret errors).
        local isFull = false
        if not issecretvalue(updateInfo) and updateInfo then
            local v = updateInfo.isFullUpdate
            if not issecretvalue(v) and v then isFull = true end
        end
        if present and not was and not isFull and GetTime() >= _buffZoneGuard then
            if EllesmereUI.IS_121 then
                -- Fresh application: the lockout is a known 10 minutes, so
                -- the cache is exact even while the real expiry is secret.
                -- Re-apply so the swipe picks it up now, not on the next event.
                _satedExpiryGuess = GetTime() + 600
                local aura, sid = _findSated()
                if aura then _applyActiveAura(aura, sid) end
            end
            _showBuffOverlay()
        end
    elseif event == "PLAYER_DEAD" then
        -- Buffs drop on death; hide the active-lust overlay even if 40s remain.
        _hideBuffOverlay()
    elseif event == "ENCOUNTER_START" then
        _state.inEncounter = true
        local _, instanceType = GetInstanceInfo()
        _state.encounterIsRaid = (instanceType == "raid")
    elseif event == "ENCOUNTER_END" then
        _state.inEncounter = false
        _state.encounterIsRaid = false
    elseif event == "CHALLENGE_MODE_START" or event == "WORLD_STATE_TIMER_START" then
        _refreshKeystoneState()
    elseif event == "CHALLENGE_MODE_COMPLETED"
        or event == "CHALLENGE_MODE_RESET"
        or event == "WORLD_STATE_TIMER_STOP" then
        _state.inChallenge = false
    elseif event == "PLAYER_ENTERING_WORLD" then
        _refreshSated()
        -- Baseline the edge tracker so a debuff already present on login/zone-in
        -- is NOT mistaken for a fresh cast (no buff overlay reconstruction), and
        -- suppress edges briefly while the zone's aura table settles.
        _satedWasPresent = _satedActive
        _buffZoneGuard = GetTime() + 1.5
        _refreshEncounterState()
        _refreshKeystoneState()
    end
    UpdateVisibility()
end

local function _ensureEvents(enabled)
    if not _eventFrame then
        _eventFrame = CreateFrame("Frame")
        _eventFrame:SetScript("OnEvent", _onEvent)
    end
    if enabled then
        _eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
        _eventFrame:RegisterEvent("ENCOUNTER_START")
        _eventFrame:RegisterEvent("ENCOUNTER_END")
        _eventFrame:RegisterEvent("CHALLENGE_MODE_START")
        _eventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
        _eventFrame:RegisterEvent("CHALLENGE_MODE_RESET")
        _eventFrame:RegisterEvent("WORLD_STATE_TIMER_START")
        _eventFrame:RegisterEvent("WORLD_STATE_TIMER_STOP")
        _eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        _eventFrame:RegisterEvent("PLAYER_DEAD")
    else
        _eventFrame:UnregisterAllEvents()
    end
end

-------------------------------------------------------------------------------
--  Frame creation
-------------------------------------------------------------------------------
local function CreateBloodlustFrame()
    if frame then return frame end
    frame = CreateFrame("Frame", "EllesmereUIBloodlustIcon", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetSize(40, 40)
    frame:Hide()

    iconTex = frame:CreateTexture(nil, "ARTWORK")
    iconTex:SetAllPoints(frame)
    local previewIcon
    if C_Spell and C_Spell.GetSpellTexture then
        previewIcon = C_Spell.GetSpellTexture(PREVIEW_SPELL_ID)
    end
    iconTex:SetTexture(previewIcon or 136080)
    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    borderTex = frame:CreateTexture(nil, "OVERLAY")
    borderTex:Hide()

    cooldownFrame = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cooldownFrame:SetAllPoints(frame)
    cooldownFrame:SetDrawEdge(false)
    cooldownFrame:SetHideCountdownNumbers(true)  -- we render our own duration text
    cooldownFrame:SetFrameLevel(frame:GetFrameLevel() + 1)

    durationFS = cooldownFrame:CreateFontString(nil, "OVERLAY")
    durationFS:SetFont((EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("extras")) or STANDARD_TEXT_FONT, 14, (EllesmereUI and EllesmereUI.SlugFlag and EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG")
    durationFS:SetText("")

    countFS = cooldownFrame:CreateFontString(nil, "OVERLAY")
    countFS:SetFont((EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("extras")) or STANDARD_TEXT_FONT, 12, (EllesmereUI and EllesmereUI.SlugFlag and EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG")
    countFS:SetText("")

    -- 40s active-lust overlay. Sits ABOVE the debuff icon and its swipe; shown
    -- for 40s on a fresh debuff acquire, then hidden, revealing the untouched
    -- debuff icon underneath. We never modify the debuff icon itself.
    buffOverlay = CreateFrame("Frame", nil, frame)
    buffOverlay:SetAllPoints(frame)
    buffOverlay:SetFrameLevel(cooldownFrame:GetFrameLevel() + 4)
    buffOverlay:Hide()

    buffTex = buffOverlay:CreateTexture(nil, "ARTWORK")
    buffTex:SetAllPoints(buffOverlay)

    buffCooldown = CreateFrame("Cooldown", nil, buffOverlay, "CooldownFrameTemplate")
    buffCooldown:SetAllPoints(buffOverlay)
    buffCooldown:SetDrawEdge(false)
    buffCooldown:SetHideCountdownNumbers(true)
    buffCooldown:SetFrameLevel(buffOverlay:GetFrameLevel() + 1)

    buffDurationFS = buffCooldown:CreateFontString(nil, "OVERLAY")
    buffDurationFS:SetFont((EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("extras")) or STANDARD_TEXT_FONT, 12, (EllesmereUI and EllesmereUI.SlugFlag and EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG")
    buffDurationFS:SetText("")

    return frame
end

-------------------------------------------------------------------------------
--  Apply (settings entry point)
-------------------------------------------------------------------------------
local function Apply()
    if not db then return end
    if not frame then CreateBloodlustFrame() end
    ApplyShape()
    _applyBuffShape()
    ApplyPosition()
    local p = P()
    local enabled = p and p.enabled and (p.visibility ~= "NEVER")
    _ensureEvents(enabled)
    if enabled then
        _refreshSated()
        -- Baseline so a debuff already present when the tracker is enabled does
        -- not retroactively pop the 40s buff overlay.
        _satedWasPresent = _satedActive
        _refreshEncounterState()
        _refreshKeystoneState()
    end
    UpdateVisibility()
end
_G._EUI_Bloodlust_Apply = Apply

-------------------------------------------------------------------------------
--  Unlock mode registration (mirrors the BattleRes icon)
-------------------------------------------------------------------------------
local function RegisterUnlock()
    if not EllesmereUI or not EllesmereUI.RegisterUnlockElements then return end
    local MK = EllesmereUI.MakeUnlockElement
    if not MK then return end

    EllesmereUI:RegisterUnlockElements({
        MK({
            key   = "EUI_Bloodlust",
            label = "Lust",
            group = "Quality of Life",
            order = 601,
            noAnchorTarget = true,  -- icon size changes; nothing should anchor to it
            isHidden = function()
                local p = P()
                return not p or not p.enabled or (p.visibility == "NEVER")
            end,
            getFrame = function()
                if not frame then CreateBloodlustFrame() end
                return frame
            end,
            getSize = function()
                local s = EP("iconSize") or 40
                return s, s
            end,
            linkedDimensions = true,  -- always square; one slider drives both
            setWidth = function(_, w)
                local p = P(); if not p then return end
                local PPb = EllesmereUI and EllesmereUI.PP
                p.iconSize = math.max(16, PPb and PPb.Snap(w) or math.floor(w + 0.5))
                Apply()
                if EllesmereUI._unlockActive and EllesmereUI.RepositionBarToMover then
                    EllesmereUI.RepositionBarToMover("EUI_Bloodlust")
                end
            end,
            setHeight = function(_, h)
                local p = P(); if not p then return end
                local PPb = EllesmereUI and EllesmereUI.PP
                p.iconSize = math.max(16, PPb and PPb.Snap(h) or math.floor(h + 0.5))
                Apply()
                if EllesmereUI._unlockActive and EllesmereUI.RepositionBarToMover then
                    EllesmereUI.RepositionBarToMover("EUI_Bloodlust")
                end
            end,
            savePos = function(_, point, relPoint, x, y)
                local p = P(); if not p then return end
                if frame and frame:GetLeft() then
                    SavePosition()
                else
                    p.pos = { centerX = x, centerY = y }
                end
            end,
            loadPos = function()
                local p = P()
                if p and p.pos then
                    return { point = "CENTER", relPoint = "CENTER", x = p.pos.centerX, y = p.pos.centerY }
                end
                return nil
            end,
            clearPos = function()
                local p = P(); if p then p.pos = nil end
            end,
            applyPos = function()
                ApplyPosition()
            end,
        }),
    })
end
_G._EUI_Bloodlust_RegisterUnlock = RegisterUnlock

-------------------------------------------------------------------------------
--  Init. We reuse the BattleRes DB handle, so we wait until it exists (the
--  BattleRes runtime loads first via the TOC; the retry guard covers any
--  ordering surprise).
-------------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    local function init()
        if not (EllesmereUI and EllesmereUI.Lite) then return end
        local getDB = _G._EUI_BattleRes_DB
        local d = getDB and getDB()
        if not d then
            C_Timer.After(0.2, init)  -- BattleRes DB not ready yet
            return
        end
        db = d
        _G._EUI_Bloodlust_DB = function() return db end
        CreateBloodlustFrame()
        Apply()
        RegisterUnlock()
    end
    init()
end)
