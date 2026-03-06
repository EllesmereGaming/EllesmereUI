-------------------------------------------------------------------------------
--  EllesmereUICooldownManager.lua
--  CDM Look Customization and Cooldown Display
--  Mirrors Blizzard CDM bars with custom styling, cooldown swipes,
--  desaturation, active state animations, and per-spec profiles.
--  Does NOT parse secret values ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â works around restricted APIs.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local ECME = EllesmereUI.Lite.NewAddon("EllesmereUICooldownManager")
ns.ECME = ECME

local PP = EllesmereUI.PP

-- Snap a value to the nearest physical pixel at a given bar scale
local function SnapForScale(x, barScale)
    if x == 0 then return 0 end
    local m = PP.perfect / ((UIParent:GetScale() or 1) * (barScale or 1))
    if m == 1 then return x end
    local y = m > 1 and m or -m
    return x - x % (x < 0 and y or -y)
end

local floor, abs, format = math.floor, math.abs, string.format
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local GetSpecialization = GetSpecialization
local GetSpecializationInfo = GetSpecializationInfo

local DEFAULT_MAPPING_NAME = "Buff Name (eg: Divine Purpose)"

-------------------------------------------------------------------------------
--  Shape Constants (shared with action bars)
-------------------------------------------------------------------------------
local CDM_SHAPE_MEDIA = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\"
local CDM_SHAPE_MASKS = {
    circle   = CDM_SHAPE_MEDIA .. "circle_mask.tga",
    csquare  = CDM_SHAPE_MEDIA .. "csquare_mask.tga",
    diamond  = CDM_SHAPE_MEDIA .. "diamond_mask.tga",
    hexagon  = CDM_SHAPE_MEDIA .. "hexagon_mask.tga",
    portrait = CDM_SHAPE_MEDIA .. "portrait_mask.tga",
    shield   = CDM_SHAPE_MEDIA .. "shield_mask.tga",
    square   = CDM_SHAPE_MEDIA .. "square_mask.tga",
}
local CDM_SHAPE_BORDERS = {
    circle   = CDM_SHAPE_MEDIA .. "circle_border.tga",
    csquare  = CDM_SHAPE_MEDIA .. "csquare_border.tga",
    diamond  = CDM_SHAPE_MEDIA .. "diamond_border.tga",
    hexagon  = CDM_SHAPE_MEDIA .. "hexagon_border.tga",
    portrait = CDM_SHAPE_MEDIA .. "portrait_border.tga",
    shield   = CDM_SHAPE_MEDIA .. "shield_border.tga",
    square   = CDM_SHAPE_MEDIA .. "square_border.tga",
}
local CDM_SHAPE_INSETS = {
    circle = 17, csquare = 17, diamond = 14,
    hexagon = 17, portrait = 17, shield = 13, square = 17,
}
local CDM_SHAPE_ICON_EXPAND = 7
local CDM_SHAPE_ICON_EXPAND_OFFSETS = {
    circle = 2, csquare = 4, diamond = 2, hexagon = 4,
    portrait = 2, shield = 2, square = 4,
}
local CDM_SHAPE_ZOOM_DEFAULTS = {
    none = 0.08, cropped = 0.02, square = 0.06, circle = 0.06, csquare = 0.06,
    diamond = 0.06, hexagon = 0.06, portrait = 0.06, shield = 0.06,
}
local CDM_SHAPE_EDGE_SCALES = {
    circle = 0.75, csquare = 0.75, diamond = 0.70,
    hexagon = 0.65, portrait = 0.70, shield = 0.65, square = 0.75,
}
ns.CDM_SHAPE_MASKS   = CDM_SHAPE_MASKS
ns.CDM_SHAPE_BORDERS = CDM_SHAPE_BORDERS
ns.CDM_SHAPE_ZOOM_DEFAULTS = CDM_SHAPE_ZOOM_DEFAULTS
-------------------------------------------------------------------------------
--  Desaturation Curve for DurationObject evaluation
--  Step curve: returns 0 when remaining <= 0 (off CD), 1 when > 0.001 (on CD)
-------------------------------------------------------------------------------
local ECME_DESAT_CURVE = C_CurveUtil.CreateCurve()
ECME_DESAT_CURVE:SetType(Enum.LuaCurveType.Step)
ECME_DESAT_CURVE:AddPoint(0, 0)
ECME_DESAT_CURVE:AddPoint(0.001, 1)

-- Forward declarations for glow helpers (defined later, used by consolidated helpers)
local StartNativeGlow, StopNativeGlow

-- Reusable helpers to avoid closure allocation in hot-path pcall calls
local _gcdCheckSid
local function _CheckIsGCD()
    local cdData = C_Spell.GetSpellCooldown(_gcdCheckSid)
    return cdData and cdData.isOnGCD
end

-- Multi-charge spell cache: populated out of combat when values are not secret.
-- Falls back to SavedVariables for combat /reload scenarios.
-- Maps spellID ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ true for spells with maxCharges > 1
local _multiChargeSpells = {}
local _maxChargeCount    = {}  -- [spellID] = maxCharges, populated alongside _multiChargeSpells

local function CacheMultiChargeSpell(spellID)
    if not spellID or not C_Spell.GetSpellCharges then return end
    if _multiChargeSpells[spellID] ~= nil then return end
    local charges = C_Spell.GetSpellCharges(spellID)
    if not charges or charges.maxCharges == nil then return end

    if not issecretvalue(charges.maxCharges) then
        -- Out of combat (or non-secret): cache live and persist to DB
        local result = charges.maxCharges > 1
        _multiChargeSpells[spellID] = result or false
        if result then _maxChargeCount[spellID] = charges.maxCharges end
        local db = ECME.db
        if db and db.global then
            if not db.global.multiChargeSpells then
                db.global.multiChargeSpells = {}
            end
            db.global.multiChargeSpells[spellID] = result or false
        end
    elseif _multiChargeSpells[spellID] == nil then
        -- Secret (in combat): fall back to persisted DB value
        local db = ECME.db
        if db and db.global and db.global.multiChargeSpells then
            _multiChargeSpells[spellID] = db.global.multiChargeSpells[spellID] or false
        else
            -- No DB data available ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â assume not a charge spell to avoid re-checking every tick
            _multiChargeSpells[spellID] = false
        end
    end
end

-- Expose charge cache to options file for preview rendering
ns._multiChargeSpells    = _multiChargeSpells
ns._maxChargeCount       = _maxChargeCount
ns.CacheMultiChargeSpell = CacheMultiChargeSpell

-- Cast-count spell cache: identifies spells that use GetSpellCastCount for
-- stack tracking (e.g. Sheilun's Gift, Mana Tea). These spells start at 0
-- stacks and build them in combat, so we cache the last known non-zero count
-- OOC and persist to SavedVariables for combat use.
-- Maps spellID -> last known count (number) or false (confirmed not a cast-count spell)
local _castCountSpells = {}

local function CacheCastCountSpell(spellID)
    if not spellID or not C_Spell.GetSpellCastCount then return end
    -- Already confirmed not a cast-count spell — skip
    if _castCountSpells[spellID] == false then return end
    local ok, count = pcall(C_Spell.GetSpellCastCount, spellID)
    if not ok or count == nil then return end

    if not (issecretvalue and issecretvalue(count)) then
        -- OOC: if count > 0, remember this spell uses cast counts
        if count > 0 then
            _castCountSpells[spellID] = count
            local db = ECME.db
            if db and db.global then
                if not db.global.castCountSpells then
                    db.global.castCountSpells = {}
                end
                db.global.castCountSpells[spellID] = true
            end
        end
        -- Don't cache false here — spell may just not have stacks yet
    elseif _castCountSpells[spellID] == nil then
        -- Secret (combat): check DB for whether we've ever seen this spell with stacks
        local db = ECME.db
        if db and db.global and db.global.castCountSpells and db.global.castCountSpells[spellID] then
            _castCountSpells[spellID] = true
        end
    end
end

-------------------------------------------------------------------------------
--  Per-tick caches: wiped at the start of each UpdateAllCDMBars tick.
--  Avoids redundant C API calls when the same spellID appears on multiple
--  bars or is queried by both ApplySpellCooldown and ApplyStackCount.
-------------------------------------------------------------------------------
local _tickGCDCache   = {}  -- [spellID] = bool|nil (GCD check result)
local _tickChargeCache = {} -- [spellID] = charges table or false
local _tickAuraCache  = {}  -- [spellID] = aura table or false

-- Keybind cache: built once out-of-combat, looked up per tick
local _cdmKeybindCache       = {}   -- [spellID] -> formatted key string
local _keybindRebuildPending = false
local _keybindCacheReady     = false  -- true after first successful build

-- FormatTime string cache: same floored-second = same string output.
-- Wiped when the integer second changes (not per tick).
local _fmtCache = {}
local _fmtCacheSec = -1

-- Combat state tracked via events (InCombatLockdown() can lag behind PLAYER_REGEN_DISABLED)
local _inCombat = false

-------------------------------------------------------------------------------
--  Consolidated cooldown/desat/charge-text helper (DurationObject approach)
--  Called from all update functions to avoid duplicating this logic.
--
--  Parameters:
--    icon       ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Å“ our ECME icon frame (has _cooldown, _tex, _chargeText, etc.)
--    spellID    ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Å“ resolved spell ID
--    desatOnCD  ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Å“ boolean, whether to desaturate when on cooldown
--    showCharges ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Å“ boolean, whether to show charge count text
--    swAlpha    ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Å“ swipe alpha (number)
--    skipCD     ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Å“ if true, skip cooldown application (e.g. aura already handled)
--
--  Returns: durObj (DurationObject|nil)
-------------------------------------------------------------------------------
local function ApplySpellCooldown(icon, spellID, desatOnCD, showCharges, swAlpha, skipCD)
    -- Ensure charge cache is populated (cheap: skips if already cached)
    CacheMultiChargeSpell(spellID)

    local isChargeSpell = _multiChargeSpells[spellID] == true

    -- Get duration objects directly (C functions handle secret values natively)
    local ccd = isChargeSpell and C_Spell.GetSpellChargeDuration and C_Spell.GetSpellChargeDuration(spellID)
    local scd = C_Spell.GetSpellCooldownDuration(spellID)

    -- GCD check (per-tick cached to avoid pcall garbage per icon)
    local isGCD = _tickGCDCache[spellID]
    if isGCD == nil then
        _gcdCheckSid = spellID
        local okG, gcdVal = pcall(_CheckIsGCD)
        isGCD = okG and gcdVal or false
        _tickGCDCache[spellID] = isGCD
    end

    ---------------------------------------------------------------------------
    -- Dual invisible shadow Cooldown frames for charge state detection.
    --
    -- _scdShadow  (fed SCD, GCD filtered):
    --   During GCD: cleared so GCD doesn't pollute.
    --   Outside GCD: fed real SCD.
    --   IsShown()=true  ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ all charges depleted (only outside GCD)
    --
    -- _ccdShadow  (fed CCD, always live):
    --   IsShown()=true  ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ recharge active (checked only when SCD not shown)
    --
    -- State: isOnCooldown (0 charges), isRecharging (has charges, recharging)
    ---------------------------------------------------------------------------
    local isOnCooldown = false
    local isRecharging = false

    if isChargeSpell then
        if not icon._scdShadow then
            local s = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
            s:SetAllPoints(icon)
            s:SetDrawSwipe(false)
            s:SetDrawEdge(false)
            s:SetDrawBling(false)
            s:SetHideCountdownNumbers(true)
            s:SetAlpha(0)
            icon._scdShadow = s
        end
        if not icon._ccdShadow then
            local s = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
            s:SetAllPoints(icon)
            s:SetDrawSwipe(false)
            s:SetDrawEdge(false)
            s:SetDrawBling(false)
            s:SetHideCountdownNumbers(true)
            s:SetAlpha(0)
            icon._ccdShadow = s
        end

        -- Feed SCD shadow: clear during GCD, feed real SCD outside GCD
        if isGCD then
            icon._scdShadow:SetCooldown(0, 0)
        else
            icon._scdShadow:Clear()
            if scd then
                icon._scdShadow:SetCooldownFromDurationObject(scd, true)
            else
                icon._scdShadow:SetCooldown(0, 0)
            end
        end

        -- Feed CCD shadow live every tick
        icon._ccdShadow:Clear()
        if ccd then
            icon._ccdShadow:SetCooldownFromDurationObject(ccd, true)
        else
            icon._ccdShadow:SetCooldown(0, 0)
        end

        -- Read state: SCD first, CCD only when SCD not active
        isOnCooldown = icon._scdShadow:IsShown()
        if not isOnCooldown then
            isRecharging = icon._ccdShadow:IsShown()
        end
    end

    -- Cooldown display: always show swipe for charge spells (consistent behavior)
    if not skipCD then
        if isChargeSpell then
            if ccd then
                icon._cooldown:SetCooldownFromDurationObject(ccd, true)
            elseif scd then
                icon._cooldown:SetCooldownFromDurationObject(scd, true)
            else
                icon._cooldown:Clear()
            end
            icon._cooldown:SetDrawSwipe(true)
            icon._cooldown:SetDrawEdge(false)
        else
            if scd then
                icon._cooldown:SetCooldownFromDurationObject(scd, true)
                icon._cooldown:SetDrawSwipe(true)
            else
                icon._cooldown:Clear()
            end
        end
    end

    -- Desaturation: isOnCooldown = 0 charges (only true outside GCD).
    -- isRecharging = has charges but not full. Neither = ready or during GCD.
    local desatApplied = false
    if desatOnCD and not skipCD then
        if isOnCooldown and scd and scd.EvaluateRemainingDuration then
            local desatVal = scd:EvaluateRemainingDuration(ECME_DESAT_CURVE, 0) or 0
            icon._tex:SetDesaturation(desatVal)
            icon._lastDesat = true
            desatApplied = icon._cooldown:IsShown()
        elseif not isChargeSpell and not isGCD and scd and scd.EvaluateRemainingDuration then
            local desatVal = scd:EvaluateRemainingDuration(ECME_DESAT_CURVE, 0) or 0
            icon._tex:SetDesaturation(desatVal)
            icon._lastDesat = true
            desatApplied = icon._cooldown:IsShown()
        else
            if icon._lastDesat then
                icon._tex:SetDesaturation(0)
                icon._lastDesat = false
            end
        end
    elseif icon._lastDesat then
        icon._tex:SetDesaturation(0)
        icon._lastDesat = false
    end

    -- Resource check: desaturate if spell is off CD but not usable (insufficient power)
    if desatOnCD and not desatApplied and not skipCD then
        local usable = C_Spell.IsSpellUsable(spellID)
        if not usable then
            icon._tex:SetDesaturation(1)
            icon._lastDesat = true
        end
    end

    -- Charge text: show spell charges for charge-based spells, or aura stacks as fallback
    if showCharges then
        if isChargeSpell then
            local charges = _tickChargeCache[spellID]
            if charges == nil then
                charges = C_Spell.GetSpellCharges(spellID) or false
                _tickChargeCache[spellID] = charges
            end
            if charges and charges.currentCharges ~= nil then
                icon._chargeText:SetText(charges.currentCharges)
                icon._chargeText:Show()
            else
                icon._chargeText:Hide()
            end
        else
            -- Fallback: show aura stack count for buff spells (per-tick cached)
            local aura = _tickAuraCache[spellID]
            if aura == nil then
                local ok, res = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
                aura = (ok and res) or false
                _tickAuraCache[spellID] = aura
            end
            if aura and aura.applications and not (issecretvalue and issecretvalue(aura.applications)) and aura.applications > 1 then
                icon._chargeText:SetText(aura.applications)
                icon._chargeText:Show()
            elseif C_Spell.GetSpellCastCount then
                -- Cast count fallback for spells that accumulate stacks via
                -- the cast count system rather than auras.
                -- Only attempt for confirmed cast-count spells (cached OOC).
                -- In combat, returns secret values — pass directly to SetText.
                CacheCastCountSpell(spellID)
                if _castCountSpells[spellID] then
                    local ok, count = pcall(C_Spell.GetSpellCastCount, spellID)
                    if ok and count then
                        if issecretvalue and issecretvalue(count) then
                            -- Secret (combat): show directly, FontStrings render secrets.
                            -- We cannot compare or read back the value without tainting.
                            icon._chargeText:SetText(count)
                            icon._chargeText:Show()
                        elseif count > 0 then
                            icon._chargeText:SetText(count)
                            icon._chargeText:Show()
                        else
                            icon._chargeText:Hide()
                        end
                    else
                        icon._chargeText:Hide()
                    end
                else
                    icon._chargeText:Hide()
                end
            else
                icon._chargeText:Hide()
            end
        end
    else
        icon._chargeText:Hide()
    end

    return scd
end

-------------------------------------------------------------------------------
--  Trinket cooldown helper (inventory slot based)
--  Handles cooldown display and desaturation for trinket slots.
-------------------------------------------------------------------------------
local function ApplyTrinketCooldown(icon, slot, desatOnCD)
    local start, dur, enable = GetInventoryItemCooldown("player", slot)
    if start and dur and dur > 1.5 and enable == 1 then
        icon._cooldown:SetCooldown(start, dur)
        if desatOnCD then
            icon._tex:SetDesaturation(1)
            icon._lastDesat = true
        elseif icon._lastDesat then
            icon._tex:SetDesaturation(0)
            icon._lastDesat = false
        end
    else
        icon._cooldown:Clear()
        if icon._lastDesat then
            icon._tex:SetDesaturation(0)
            icon._lastDesat = false
        end
    end
    icon._chargeText:Hide()
end

-------------------------------------------------------------------------------
--  Active state animation helper (aura glow / swipe color)
--  Handles transition between active and inactive visual states.
-------------------------------------------------------------------------------
local function ApplyActiveAnimation(icon, auraHandled, barData, barKey, activeAnim, animR, animG, animB, swAlpha)
    local skipActiveAnim = barData.hideBuffsWhenInactive and (barKey == "buffs" or barData.barType == "buffs")
    if not skipActiveAnim and auraHandled and not icon._isActive then
        if activeAnim ~= "none" and activeAnim ~= "hideActive" then
            icon._cooldown:SetSwipeColor(animR, animG, animB, swAlpha)
            local glowIdx = tonumber(activeAnim)
            -- Don't overwrite proc glow with active state glow
            if glowIdx and icon._glowOverlay and not icon._procGlowActive then
                StartNativeGlow(icon._glowOverlay, glowIdx, animR, animG, animB)
            end
        end
    elseif (skipActiveAnim or not auraHandled) and icon._isActive then
        icon._cooldown:SetSwipeColor(0, 0, 0, swAlpha)
        -- Don't stop glow if proc glow is active (it owns the overlay)
        if icon._glowOverlay and not icon._procGlowActive then
            StopNativeGlow(icon._glowOverlay)
        end
    end
    icon._isActive = not skipActiveAnim and auraHandled
end

-------------------------------------------------------------------------------
--  Stack count helper (aura applications text)
--  Hooks blizzChild.Applications Show/Hide to mirror CDM's stack display onto
--  our _stackText. CDM already handles secret values and only shows Applications
--  when stacks > 1, so we trust its Show/Hide as the gate — no text comparison needed.
-------------------------------------------------------------------------------
local _stackHookedChildren = {}  -- [blizzChild] = true

local function HookBlizzChildApplications(blizzChild)
    if not blizzChild or _stackHookedChildren[blizzChild] then return end
    local appsFrame = blizzChild.Applications
    if not appsFrame then return end
    local appsText = appsFrame.Applications
    if not appsText then return end

    _stackHookedChildren[blizzChild] = true

    -- CDM only calls Show() on Applications when stacks > 1, so no text check needed.
    -- GetText() returns a secret string in combat — pass it directly to SetText,
    -- WoW renders secret values correctly without comparison.
    hooksecurefunc(appsFrame, "Show", function()
        local ourIcon = blizzChild._ecmeIcon
        if not ourIcon or not ourIcon._stackText then return end
        local ok, txt = pcall(appsText.GetText, appsText)
        if ok and txt then
            ourIcon._stackText:SetText(txt)
            ourIcon._stackText:Show()
        end
    end)

    hooksecurefunc(appsFrame, "Hide", function()
        local ourIcon = blizzChild._ecmeIcon
        if ourIcon and ourIcon._stackText then
            ourIcon._stackText:Hide()
        end
    end)
end

local function ApplyStackCount(icon, resolvedSid, auraInstanceID, auraUnit, showStackCount, blizzChild)
    if not icon._stackText then return end

    if not showStackCount then
        icon._stackText:Hide()
        return
    end

    if blizzChild then
        blizzChild._ecmeIcon = icon
        HookBlizzChildApplications(blizzChild)

        -- Sync current state: mirror whatever CDM currently has showing
        local appsFrame = blizzChild.Applications
        if appsFrame and appsFrame:IsShown() then
            local appsText = appsFrame.Applications
            if appsText then
                local ok, txt = pcall(appsText.GetText, appsText)
                if ok and txt then
                    icon._stackText:SetText(txt)
                    icon._stackText:Show()
                    return
                end
            end
        end
        -- Applications frame not showing — fall through to aura lookup below.
        -- Spells like Sheilun's Gift and Mana Tea accumulate stacks as a
        -- player buff but Blizzard's CDM may not populate the Applications
        -- sub-frame for them.
    end

    -- Aura-based stack lookup: check the resolved spell ID for applications
    if resolvedSid and resolvedSid > 0 then
        local aura = _tickAuraCache[resolvedSid]
        if aura == nil then
            local ok, res = pcall(C_UnitAuras.GetPlayerAuraBySpellID, resolvedSid)
            aura = (ok and res) or false
            _tickAuraCache[resolvedSid] = aura
        end
        if aura then
            local apps = aura.applications
            if apps ~= nil and not (issecretvalue and issecretvalue(apps)) and apps > 1 then
                icon._stackText:SetText(tostring(apps))
                icon._stackText:Show()
                return
            end
        end
    end

    -- Final fallback: use auraInstanceID to look up the aura directly.
    if auraInstanceID and auraUnit then
        local ok, auraData = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, auraUnit, auraInstanceID)
        if ok and auraData then
            local apps = auraData.applications
            if apps ~= nil and not (issecretvalue and issecretvalue(apps)) and apps > 1 then
                icon._stackText:SetText(tostring(apps))
                icon._stackText:Show()
                return
            end
        end
    end

    -- Cast count fallback: spells that accumulate stacks via the cast count
    -- system rather than auras (e.g. Sheilun's Gift clouds, Mana Tea).
    -- Only attempt for spells confirmed to use cast counts (cached OOC).
    -- In combat, GetSpellCastCount returns secret values — pass them directly
    -- to SetText (FontStrings render secrets natively), same as charge text.
    if resolvedSid and resolvedSid > 0 and C_Spell.GetSpellCastCount then
        CacheCastCountSpell(resolvedSid)
        if _castCountSpells[resolvedSid] then
            local ok, count = pcall(C_Spell.GetSpellCastCount, resolvedSid)
            if ok and count then
                if issecretvalue and issecretvalue(count) then
                    -- Secret (combat): show directly, FontStrings render secrets.
                    -- We cannot compare or read back the value without tainting.
                    icon._stackText:SetText(count)
                    icon._stackText:Show()
                    return
                elseif count > 0 then
                    icon._stackText:SetText(tostring(count))
                    icon._stackText:Show()
                    return
                end
            end
        end
    end

    icon._stackText:Hide()
end
local BuildAllCDMBars
local RegisterCDMUnlockElements

-------------------------------------------------------------------------------
--  Defaults
-------------------------------------------------------------------------------
local DEFAULTS = {
    global = {
        multiChargeSpells = {},
    },
    profile = {
        _capturedOnce = false,
        -- CDM Look
        reskinBorders   = true,
        utilityScale    = 1.0,
        buffBarScale    = 1.0,
        cooldownBarScale = 1.0,
        -- Bar Glows (per-spec)
        spec            = {},
        activeSpecKey   = "0",
        -- Bar Glows v2 (buff ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ action button glow assignments)
        barGlows = {
            enabled = true,
            selectedBar = 1,
            selectedButton = nil,
            selectedAssignment = 1,
            assignments = {},  -- ["barIdx_btnIdx"] = { {spellID, glowStyle, glowColor, classColor, mode}, ... }
        },
        -- Buff Bars (legacy ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â kept for migration)
        buffBars = {
            enabled     = false,
            width       = 200,
            height      = 18,
            spacing     = 2,
            maxBars     = 8,
            growUp      = false,
            showTimer   = true,
            showIcon    = true,
            iconSize    = 18,
            borderSize  = 1,
            borderR     = 0, borderG = 0, borderB = 0, borderA = 1,
            bgAlpha     = 0.4,
            barR        = 0.05, barG = 0.82, barB = 0.62,
            useClassColor = false,
            filterMode  = "all",  -- "all", "whitelist", "blacklist"
            filterList  = "",
            locked      = false,
            offsetX     = 300,
            offsetY     = -200,
        },
        -- Tracked Buff Bars v2 (per-bar buff tracking with individual settings)
        -- Note: not in defaults — lazy-initialized by ns.GetTrackedBuffBars() to avoid AceDB merge issues
        -- CDM Bars (our replacement for Blizzard CDM)
        cdmBars = {
            enabled = true,
            hideBlizzard = true,
            -- Default bar template (applied to each bar)
            barDefaults = {
                iconSize    = 36,
                numRows     = 1,
                spacing     = 2,
                borderSize  = 1,
                borderR     = 0, borderG = 0, borderB = 0, borderA = 1,
                borderClassColor = false,
                bgR         = 0.08, bgG = 0.08, bgB = 0.08, bgA = 0.6,
                iconZoom    = 0.08,
                iconShape   = "none",
                growDirection = "RIGHT",
                verticalOrientation = false,
                barBgEnabled = false,
                barBgAlpha  = 1.0,
                barBgR = 0, barBgG = 0, barBgB = 0,
                showCooldownText = true,
                cooldownFontSize = 15,
                showCharges = true,
                chargeFontSize = 11,
                desaturateOnCD = true,
                swipeAlpha  = 0.7,
                borderThickness = "thin",
                activeStateAnim = "blizzard",
                activeAnimClassColor = false,
                activeAnimR = 1.0, activeAnimG = 0.85, activeAnimB = 0.0,
                anchorTo = "none",
                anchorPosition = "left",
                anchorOffsetX = 0,
                anchorOffsetY = 0,
                barVisibility = "always",
                housingHideEnabled = true,
                hideBuffsWhenInactive = true,
                showStackCount = false,
                stackCountSize = 11,
                stackCountX = 0,
                stackCountY = 0,
                stackCountR = 1, stackCountG = 1, stackCountB = 1,
                showTooltip = false,
                showKeybind = false,
                keybindSize = 10,
                keybindOffsetX = 2,
                keybindOffsetY = -2,
                keybindR = 1, keybindG = 1, keybindB = 1, keybindA = 0.9,
            },
            -- The 3 default bars (match Blizzard CDM)
            bars = {
                {
                    key = "cooldowns", name = "Cooldowns", enabled = true,
                    barScale = 1.0, iconSize = 42, numRows = 1, spacing = 2,
                    borderSize = 1, borderR = 0, borderG = 0, borderB = 0, borderA = 1,
                    borderClassColor = false,
                    bgR = 0.08, bgG = 0.08, bgB = 0.08, bgA = 0.6,
                    iconZoom = 0.08, iconShape = "none", growDirection = "RIGHT",
                    verticalOrientation = false, barBgEnabled = false, barBgAlpha = 1.0,
                    barBgR = 0, barBgG = 0, barBgB = 0,
                    showCooldownText = true, cooldownFontSize = 15,
                    showCharges = true, chargeFontSize = 11,
                    desaturateOnCD = true, swipeAlpha = 0.7,
                    borderThickness = "thin", activeStateAnim = "blizzard",
                    activeAnimClassColor = false, activeAnimR = 1.0, activeAnimG = 0.85, activeAnimB = 0.0,
                    anchorTo = "none", anchorPosition = "left",
                    anchorOffsetX = 0, anchorOffsetY = 0,
                    barVisibility = "always", housingHideEnabled = true,
                    hideBuffsWhenInactive = true,
                    showStackCount = false, stackCountSize = 11,
                    stackCountX = 0, stackCountY = 0,
                    stackCountR = 1, stackCountG = 1, stackCountB = 1,
                    showTooltip = false, showKeybind = false,
                    keybindSize = 10, keybindOffsetX = 2, keybindOffsetY = -2,
                    keybindR = 1, keybindG = 1, keybindB = 1, keybindA = 0.9,
                },
                {
                    key = "utility", name = "Utility", enabled = true,
                    barScale = 1.0, iconSize = 36, numRows = 1, spacing = 2,
                    borderSize = 1, borderR = 0, borderG = 0, borderB = 0, borderA = 1,
                    borderClassColor = false,
                    bgR = 0.08, bgG = 0.08, bgB = 0.08, bgA = 0.6,
                    iconZoom = 0.08, iconShape = "none", growDirection = "RIGHT",
                    verticalOrientation = false, barBgEnabled = false, barBgAlpha = 1.0,
                    barBgR = 0, barBgG = 0, barBgB = 0,
                    showCooldownText = true, cooldownFontSize = 15,
                    showCharges = true, chargeFontSize = 11,
                    desaturateOnCD = true, swipeAlpha = 0.7,
                    borderThickness = "thin", activeStateAnim = "blizzard",
                    activeAnimClassColor = false, activeAnimR = 1.0, activeAnimG = 0.85, activeAnimB = 0.0,
                    anchorTo = "none", anchorPosition = "left",
                    anchorOffsetX = 0, anchorOffsetY = 0,
                    barVisibility = "always", housingHideEnabled = true,
                    hideBuffsWhenInactive = true,
                    showStackCount = false, stackCountSize = 11,
                    stackCountX = 0, stackCountY = 0,
                    stackCountR = 1, stackCountG = 1, stackCountB = 1,
                    showTooltip = false, showKeybind = false,
                    keybindSize = 10, keybindOffsetX = 2, keybindOffsetY = -2,
                    keybindR = 1, keybindG = 1, keybindB = 1, keybindA = 0.9,
                },
                {
                    key = "buffs", name = "Buffs", enabled = true,
                    barScale = 1.0, iconSize = 32, numRows = 1, spacing = 2,
                    borderSize = 1, borderR = 0, borderG = 0, borderB = 0, borderA = 1,
                    borderClassColor = false,
                    bgR = 0.08, bgG = 0.08, bgB = 0.08, bgA = 0.6,
                    iconZoom = 0.08, iconShape = "none", growDirection = "RIGHT",
                    verticalOrientation = false, barBgEnabled = false, barBgAlpha = 1.0,
                    barBgR = 0, barBgG = 0, barBgB = 0,
                    showCooldownText = true, cooldownFontSize = 15,
                    showCharges = true, chargeFontSize = 11,
                    desaturateOnCD = true, swipeAlpha = 0.7,
                    borderThickness = "thin", activeStateAnim = "blizzard",
                    activeAnimClassColor = false, activeAnimR = 1.0, activeAnimG = 0.85, activeAnimB = 0.0,
                    anchorTo = "none", anchorPosition = "left",
                    anchorOffsetX = 0, anchorOffsetY = 0,
                    barVisibility = "always", housingHideEnabled = true,
                    hideBuffsWhenInactive = true,
                    showStackCount = false, stackCountSize = 11,
                    stackCountX = 0, stackCountY = 0,
                    stackCountR = 1, stackCountG = 1, stackCountB = 1,
                    showTooltip = false, showKeybind = false,
                    keybindSize = 10, keybindOffsetX = 2, keybindOffsetY = -2,
                    keybindR = 1, keybindG = 1, keybindB = 1, keybindA = 0.9,
                },
            },
        },
        -- Saved positions for CDM bars (keyed by bar key)
        cdmBarPositions = {},
        -- Saved positions for tracked buff bars (keyed by bar index string)
        tbbPositions = {},
        -- Per-spec profiles: spell lists, bar glows, buff bars (keyed by specID string)
        specProfiles = {},
    },
}

-------------------------------------------------------------------------------
--  Spec helpers
-------------------------------------------------------------------------------
local function GetCurrentSpecKey()
    local specIndex = GetSpecialization and GetSpecialization()
    if not specIndex then return "0" end
    local specID = select(1, GetSpecializationInfo(specIndex))
    return tostring(specID or 0)
end

-- Validates that activeSpecKey matches the real spec. If not, triggers a full
-- spec switch. Called from multiple events as a safety net so the CDM can
-- NEVER show the wrong spec's icons.
local _specValidated = false
local function ValidateSpec()
    if not ECME.db then return end
    local realKey = GetCurrentSpecKey()
    if realKey == "0" then return end  -- spec API not ready yet
    local p = ECME.db.profile
    if p.activeSpecKey == realKey then
        _specValidated = true
        return
    end
    -- Mismatch detected — force a full spec switch
    _specValidated = true
    -- SwitchSpecProfile is defined later; called via ns reference
    if ns.SwitchSpecProfile then
        ns.SwitchSpecProfile(realKey)
    end
end

local function EnsureSpec(profile, key)
    profile.spec[key] = profile.spec[key] or { mappings = {}, selectedMapping = 1 }
    return profile.spec[key]
end

local function GetStore()
    local p = ECME.db.profile
    return EnsureSpec(p, p.activeSpecKey or "0")
end

local function EnsureMappings(store)
    if not store.mappings then store.mappings = {} end
    if #store.mappings == 0 then
        store.mappings[1] = {
            enabled = false, name = DEFAULT_MAPPING_NAME,
            actionBar = 1, actionButton = 1, cdmSlot = 1,
            hideFromCDM = false, mode = "ACTIVE",
            glowStyle = 1, glowColor = { r = 1, g = 0.82, b = 0.1 },
        }
    end
    store.selectedMapping = tonumber(store.selectedMapping) or 1
    if store.selectedMapping < 1 then store.selectedMapping = 1 end
    if store.selectedMapping > #store.mappings then store.selectedMapping = #store.mappings end
    for _, m in ipairs(store.mappings) do
        if m.enabled == nil then m.enabled = true end
        if m.hideFromCDM == nil then m.hideFromCDM = false end
        if m.mode ~= "MISSING" then m.mode = "ACTIVE" end
        m.glowStyle = tonumber(m.glowStyle) or 1
        if not m.glowColor then m.glowColor = { r = 1, g = 0.82, b = 0.1 } end
        m.name = tostring(m.name or "")
        if type(m.actionBar) ~= "string" or not ns.CDM_BAR_ROOTS[m.actionBar] then
            m.actionBar = tonumber(m.actionBar) or 1
        end
        m.actionButton = tonumber(m.actionButton) or 1
        m.cdmSlot = tonumber(m.cdmSlot) or 1
    end
end

-- Expose for options
ns.DEFAULT_MAPPING_NAME = DEFAULT_MAPPING_NAME
ns.GetStore = GetStore
ns.EnsureMappings = EnsureMappings

-------------------------------------------------------------------------------
--  Per-Spec Profile Helpers
--  Saves/restores spell lists, bar glows, and buff bars per specialization.
--  Bar structure, settings, and positions are shared across all specs.
-------------------------------------------------------------------------------
local MAIN_BAR_KEYS = { cooldowns = true, utility = true, buffs = true }

--- Deep-copy a table (simple values + nested tables, no metatables/functions)
local function DeepCopy(src)
    if type(src) ~= "table" then return src end
    local copy = {}
    for k, v in pairs(src) do copy[k] = DeepCopy(v) end
    return copy
end

--- Save the current spec's per-spec data into specProfiles[specKey]
local function SaveCurrentSpecProfile()
    local p = ECME.db.profile
    local specKey = p.activeSpecKey
    if not specKey or specKey == "0" then return end
    if not p.specProfiles then p.specProfiles = {} end

    local prof = {}

    -- 1) Spell lists for each bar
    prof.barSpells = {}
    for _, barData in ipairs(p.cdmBars.bars) do
        local key = barData.key
        if key then
            local entry = {}
            if MAIN_BAR_KEYS[key] then
                -- Main bars: save trackedSpells + extraSpells
                entry.trackedSpells = DeepCopy(barData.trackedSpells)
                entry.extraSpells   = DeepCopy(barData.extraSpells)
            elseif barData.barType ~= "trinkets" then
                -- Custom non-trinket bars: save customSpells
                entry.customSpells = DeepCopy(barData.customSpells)
            end
            -- Trinket/racial/potion bars: nothing to save (refreshed on login)
            prof.barSpells[key] = entry
        end
    end

    -- 2) Bar Glows (full table)
    prof.barGlows = DeepCopy(p.barGlows)

    p.specProfiles[specKey] = prof
end

--- Restore a spec profile into the live data, or initialize fresh if none exists
local function LoadSpecProfile(specKey)
    local p = ECME.db.profile
    if not p.specProfiles then p.specProfiles = {} end
    local prof = p.specProfiles[specKey]

    if prof then
        -- Restore saved spell lists
        if prof.barSpells then
            for _, barData in ipairs(p.cdmBars.bars) do
                local saved = prof.barSpells[barData.key]
                if saved then
                    if MAIN_BAR_KEYS[barData.key] then
                        barData.trackedSpells = DeepCopy(saved.trackedSpells)
                        barData.extraSpells   = DeepCopy(saved.extraSpells)
                    elseif barData.barType ~= "trinkets" then
                        barData.customSpells = DeepCopy(saved.customSpells)
                    end
                else
                    -- Bar exists now but wasn't in the saved profile (new bar added since)
                    if MAIN_BAR_KEYS[barData.key] then
                        barData.trackedSpells = nil  -- will trigger Blizzard snapshot
                        barData.extraSpells = nil
                    elseif barData.barType ~= "trinkets" then
                        barData.customSpells = {}
                    end
                end
            end
        end

        -- Restore bar glows
        if prof.barGlows then
            p.barGlows = DeepCopy(prof.barGlows)
        end
    else
        -- No saved profile for this spec: initialize fresh
        -- Main bars: clear trackedSpells so SnapshotBlizzardCDM re-captures
        for _, barData in ipairs(p.cdmBars.bars) do
            if MAIN_BAR_KEYS[barData.key] then
                barData.trackedSpells = nil
                barData.extraSpells = nil
            elseif barData.barType ~= "trinkets" then
                barData.customSpells = {}
            end
        end

        -- Reset bar glows to fresh state
        p.barGlows = {
            enabled = true,
            selectedBar = 1,
            selectedButton = nil,
            selectedAssignment = 1,
            assignments = {},
        }
    end

    -- Fix anchors: if a custom bar is anchored to a bar key that no longer
    -- has spells (went blank on spec switch), un-anchor it.
    -- Only applies to trinket/racial/potion bars anchored to custom bars.
    local barKeySet = {}
    for _, barData in ipairs(p.cdmBars.bars) do
        barKeySet[barData.key] = barData
    end
    for _, barData in ipairs(p.cdmBars.bars) do
        if barData.barType == "trinkets" and barData.anchorTo and barData.anchorTo ~= "none" then
            local anchor = barKeySet[barData.anchorTo]
            if anchor and anchor.barType ~= "trinkets" and not MAIN_BAR_KEYS[anchor.key] then
                -- Anchored to a custom bar ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â check if that bar has spells
                local spells = anchor.customSpells
                if not spells or #spells == 0 then
                    barData.anchorTo = "none"
                    barData.anchorPosition = "left"
                    barData.anchorOffsetX = 0
                    barData.anchorOffsetY = 0
                end
            end
        end
    end
end

--- Full spec switch: save current, load new, rebuild everything
local function SwitchSpecProfile(newSpecKey)
    local p = ECME.db.profile
    local oldSpecKey = p.activeSpecKey

    -- Save current spec (if valid)
    if oldSpecKey and oldSpecKey ~= "0" then
        SaveCurrentSpecProfile()
    end

    -- Update active spec
    p.activeSpecKey = newSpecKey
    EnsureSpec(p, newSpecKey)

    -- Load new spec profile
    LoadSpecProfile(newSpecKey)

    -- Rebuild all CDM systems (deferred so Blizzard CDM frames are ready)
    C_Timer.After(0.5, function()
        BuildAllCDMBars()
        ns.BuildTrackedBuffBars()
        RegisterCDMUnlockElements()

        -- Refresh options panel if open
        if EllesmereUI and EllesmereUI._mainFrame and EllesmereUI._mainFrame:IsShown() then
            if EllesmereUI.InvalidateContentHeaderCache then
                EllesmereUI:InvalidateContentHeaderCache()
            end
            if EllesmereUI.RefreshPage then
                EllesmereUI:RefreshPage()
            end
        end
    end)
end
ns.SwitchSpecProfile = SwitchSpecProfile

-------------------------------------------------------------------------------
--  CDM Bar Roots
-------------------------------------------------------------------------------
ns.CDM_BAR_ROOTS = {
    CDM_COOLDOWN = "EssentialCooldownViewer",
    CDM_UTILITY  = "UtilityCooldownViewer",
}

-------------------------------------------------------------------------------
--  Action Button Lookup (supports Blizzard and popular bar addons)
-------------------------------------------------------------------------------
local blizzBarNames = {
    [2] = "MultiBarBottomLeftButton",
    [3] = "MultiBarBottomRightButton",
    [4] = "MultiBarRightButton",
    [5] = "MultiBarLeftButton",
    [6] = "MultiBar5Button",
    [7] = "MultiBar6Button",
    [8] = "MultiBar7Button",
}

local actionButtonCache = {}

local function FirstExisting(...)
    for i = 1, select("#", ...) do
        local f = _G[select(i, ...)]
        if f then return f end
    end
end

local function GetActionButton(bar, i)
    bar = bar or 1
    local cacheKey = bar * 100 + i
    if actionButtonCache[cacheKey] then return actionButtonCache[cacheKey] end
    local btn
    if bar == 1 then
        btn = FirstExisting(
            "BT4Button" .. i, "ElvUI_Bar1Button" .. i,
            "DominosActionButton" .. i, "ActionButton" .. i)
    else
        local offset = (bar - 1) * 12
        local blizz = blizzBarNames[bar]
        btn = FirstExisting(
            "BT4Button" .. (offset + i),
            "ElvUI_Bar" .. bar .. "Button" .. i,
            "DominosActionButton" .. (offset + i),
            blizz and (blizz .. i) or nil)
    end
    if btn then actionButtonCache[cacheKey] = btn end
    return btn
end

-------------------------------------------------------------------------------
--  CDM Slot Helpers
-------------------------------------------------------------------------------
local function FindCooldown(frame)
    if not frame then return end
    local cd = frame.cooldown or frame.Cooldown
    if cd then return cd end
    for i = 1, frame:GetNumChildren() do
        local child = select(i, frame:GetChildren())
        if child and child.GetObjectType and child:GetObjectType() == "Cooldown" then
            return child
        end
    end
end

local function SlotSortComparator(a, b)
    local ax, ay = a:GetCenter()
    local bx, by = b:GetCenter()
    ax, ay, bx, by = ax or 0, ay or 0, bx or 0, by or 0
    if abs(ay - by) > 2 then return ay > by end
    return ax < bx
end

local cachedSlots, cacheTime = nil, 0
local CACHE_DURATION = 0.5

local function GetSortedSlots(forceRefresh)
    local now = GetTime()
    if not forceRefresh and cachedSlots and (now - cacheTime) < CACHE_DURATION then
        return cachedSlots
    end
    local root = _G.BuffIconCooldownViewer
    if not root or not root.GetChildren then cachedSlots = nil; return nil end
    local slots = {}
    for i = 1, root:GetNumChildren() do
        local c = select(i, root:GetChildren())
        if c and c.GetCenter and FindCooldown(c) then
            slots[#slots + 1] = c
        end
    end
    if #slots == 0 then cachedSlots = nil; return nil end
    table.sort(slots, SlotSortComparator)
    cachedSlots = slots
    cacheTime = now
    return slots
end

local function GetAllCDMSlots(root)
    if not root or not root.GetChildren then return {} end
    local slots = {}
    for i = 1, root:GetNumChildren() do
        local c = select(i, root:GetChildren())
        if c and c.GetWidth and c:GetWidth() > 5 then
            slots[#slots + 1] = c
        end
    end
    return slots
end

local function GetCDMBarButton(barKey, slotIndex)
    local rootName = ns.CDM_BAR_ROOTS[barKey]
    if not rootName then return nil end
    local root = _G[rootName]
    if not root or not root.GetChildren then return nil end
    local slots = {}
    for i = 1, root:GetNumChildren() do
        local c = select(i, root:GetChildren())
        if c and c.GetWidth and c:GetWidth() > 5 then
            slots[#slots + 1] = c
        end
    end
    if #slots == 0 then return nil end
    table.sort(slots, SlotSortComparator)
    return slots[slotIndex]
end

local function GetTargetButton(actionBar, actionButtonIndex)
    if type(actionBar) == "string" and ns.CDM_BAR_ROOTS[actionBar] then
        return GetCDMBarButton(actionBar, actionButtonIndex)
    end
    return GetActionButton(tonumber(actionBar) or 1, actionButtonIndex)
end

-------------------------------------------------------------------------------
--  CDM Look: Border Reskinning
-------------------------------------------------------------------------------
local cdmBorderFrames = {}
local safeEq = function(a, b) return a == b end
local cdmBorderBackdrop = { edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }

local function GetOrCreateCDMBorder(slot)
    if cdmBorderFrames[slot] then return cdmBorderFrames[slot] end

    slot.__ECMEHidden   = slot.__ECMEHidden or {}
    slot.__ECMEIcon     = slot.__ECMEIcon or nil
    slot.__ECMECooldown = slot.__ECMECooldown or nil

    if not slot.__ECMEScanned then
        slot.__ECMEHidden = {}
        slot.__ECMEIcon = nil
        slot.__ECMECooldown = nil

        for ri = 1, slot:GetNumRegions() do
            local region = select(ri, slot:GetRegions())
            if region and region.GetObjectType then
                local objType = region:GetObjectType()
                if objType == "MaskTexture" then
                    slot.__ECMEHidden[#slot.__ECMEHidden + 1] = region
                elseif objType == "Texture" then
                    local ok, rawLayer = pcall(region.GetDrawLayer, region)
                    if ok and rawLayer ~= nil then
                        local okB, isBorder   = pcall(safeEq, rawLayer, "BORDER")
                        local okO, isOverlay  = pcall(safeEq, rawLayer, "OVERLAY")
                        local okA, isArtwork  = pcall(safeEq, rawLayer, "ARTWORK")
                        local okG, isBG       = pcall(safeEq, rawLayer, "BACKGROUND")
                        if (okB and isBorder) or (okO and isOverlay) then
                            slot.__ECMEHidden[#slot.__ECMEHidden + 1] = region
                        elseif not slot.__ECMEIcon and ((okA and isArtwork) or (okG and isBG)) then
                            slot.__ECMEIcon = region
                        end
                    end
                end
            end
        end

        for ci = 1, slot:GetNumChildren() do
            local child = select(ci, slot:GetChildren())
            if child and child.GetObjectType then
                local objType = child:GetObjectType()
                if objType == "MaskTexture" then
                    slot.__ECMEHidden[#slot.__ECMEHidden + 1] = child
                elseif objType == "Cooldown" then
                    slot.__ECMECooldown = child
                    for k = 1, child:GetNumChildren() do
                        local cdChild = select(k, child:GetChildren())
                        if cdChild and cdChild.GetObjectType and cdChild:GetObjectType() == "MaskTexture" then
                            slot.__ECMEHidden[#slot.__ECMEHidden + 1] = cdChild
                        end
                    end
                    for k = 1, child:GetNumRegions() do
                        local cdRegion = select(k, child:GetRegions())
                        if cdRegion and cdRegion.GetObjectType and cdRegion:GetObjectType() == "MaskTexture" then
                            slot.__ECMEHidden[#slot.__ECMEHidden + 1] = cdRegion
                        end
                    end
                end
            end
        end
        slot.__ECMEScanned = true
    end

    local iconSize = slot.__ECMEIcon and slot.__ECMEIcon:GetWidth() or slot:GetWidth() or 35
    local edgeSize = iconSize < 35 and 2 or 1

    local border = CreateFrame("Frame", nil, slot, "BackdropTemplate")
    if slot.__ECMEIcon then border:SetAllPoints(slot.__ECMEIcon) else border:SetAllPoints() end
    border:SetFrameLevel(slot:GetFrameLevel() + 5)
    cdmBorderBackdrop.edgeSize = edgeSize
    border:SetBackdrop(cdmBorderBackdrop)
    border:SetBackdropBorderColor(0, 0, 0, 1)

    cdmBorderFrames[slot] = border
    return border
end

local CDM_ROOT_NAMES = {
    "BuffIconCooldownViewer", "BuffBarCooldownViewer",
    "EssentialCooldownViewer", "UtilityCooldownViewer",
}

local function UpdateUtilityScale()
    local utility = _G.UtilityCooldownViewer
    if utility and ECME.db then
        utility:SetScale(ECME.db.profile.utilityScale or 1.0)
    end
end

local function UpdateBuffBarScale()
    local buffBar = _G.BuffIconCooldownViewer
    if buffBar and ECME.db then
        buffBar:SetScale(ECME.db.profile.buffBarScale or 1.0)
    end
end

local function UpdateCooldownBarScale()
    local cdBar = _G.EssentialCooldownViewer
    if cdBar and ECME.db then
        cdBar:SetScale(ECME.db.profile.cooldownBarScale or 1.0)
    end
end

local function UpdateAllCDMBorders()
    local reskin = ECME.db and ECME.db.profile.reskinBorders
    local crop = 0.06

    UpdateUtilityScale()
    UpdateBuffBarScale()
    UpdateCooldownBarScale()

    for _, rootName in ipairs(CDM_ROOT_NAMES) do
        local root = _G[rootName]
        if root then
            for _, slot in ipairs(GetAllCDMSlots(root)) do
                local border = GetOrCreateCDMBorder(slot)
                if reskin then
                    border:Show()
                    if slot.__ECMEIcon then slot.__ECMEIcon:SetTexCoord(crop, 1 - crop, crop, 1 - crop) end
                    if slot.__ECMECooldown then
                        slot.__ECMECooldown:SetSwipeTexture("Interface\\Buttons\\WHITE8x8")
                    end
                    for _, h in ipairs(slot.__ECMEHidden) do
                        if h and h.Hide then h:Hide() end
                    end
                else
                    border:Hide()
                    if slot.__ECMEIcon then slot.__ECMEIcon:SetTexCoord(0, 1, 0, 1) end
                    if slot.__ECMECooldown then
                        slot.__ECMECooldown:SetSwipeTexture("Interface\\Cooldown\\cooldown-bling")
                    end
                    for _, h in ipairs(slot.__ECMEHidden) do
                        if h and h.Show then h:Show() end
                    end
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Native Glow System — engines provided by shared EllesmereUI_Glows.lua
--  CDM keeps its own GLOW_STYLES (different scale values) and Start/Stop
--  wrappers that handle CDM-specific shape glow (icon masks/borders).
-------------------------------------------------------------------------------
local _G_Glows = EllesmereUI.Glows
local GLOW_STYLES = {
    { name = "Pixel Glow",           procedural = true },
    { name = "Custom Shape Glow",    shapeGlow = true, scale = 1.20 },
    { name = "Action Button Glow",   buttonGlow = true, scale = 1.16 },
    { name = "Auto-Cast Shine",      autocast = true },
    { name = "GCD",                  atlas = "RotationHelper_Ants_Flipbook",  scale = 1.41 },
    { name = "Modern WoW Glow",      atlas = "UI-HUD-ActionBar-Proc-Loop-Flipbook",  scale = 1.53 },
    { name = "Classic WoW Glow",     texture = "Interface\\SpellActivationOverlay\\IconAlertAnts",
      rows = 5, columns = 5, frames = 25, duration = 0.3, frameW = 48, frameH = 48, scale = 1.03 },
}
ns.GLOW_STYLES = GLOW_STYLES

StartNativeGlow = function(overlay, style, cr, cg, cb)
    if not overlay then return end
    local styleIdx = tonumber(style) or 1
    if styleIdx < 1 or styleIdx > #GLOW_STYLES then styleIdx = 1 end
    local entry = GLOW_STYLES[styleIdx]

    _G_Glows.StopAllGlows(overlay)

    local parent = overlay:GetParent()
    if not parent then return end
    local pW, pH = parent:GetWidth(), parent:GetHeight()
    local sz = math.min(pW, pH)
    if sz < 5 then sz = 36 end
    cr = cr or 1; cg = cg or 1; cb = cb or 1

    if entry.shapeGlow then
        -- CDM-specific: read shape mask/border from the icon frame
        local icon = parent
        local shape = icon._shapeApplied and icon._shapeName or nil
        local maskPath   = shape and CDM_SHAPE_MASKS[shape]
        local borderPath = shape and CDM_SHAPE_BORDERS[shape]
        _G_Glows.StartShapeGlow(overlay, sz, cr, cg, cb, entry.scale or 1.20, {
            maskPath   = maskPath,
            borderPath = borderPath,
            shapeMask  = icon._shapeMask,
        })
    elseif entry.procedural then
        local N = 8; local th = 2; local period = 4
        local lineLen = math.floor((sz + sz) * (2 / N - 0.1))
        lineLen = math.min(lineLen, sz)
        if lineLen < 1 then lineLen = 1 end
        _G_Glows.StartProceduralAnts(overlay, N, th, period, lineLen, cr, cg, cb, sz)
    elseif entry.buttonGlow then
        _G_Glows.StartButtonGlow(overlay, sz, cr, cg, cb, entry.scale or 1.16)
    elseif entry.autocast then
        _G_Glows.StartAutoCastShine(overlay, sz, cr, cg, cb, 1.0)
    else
        _G_Glows.StartFlipBookGlow(overlay, sz, entry, cr, cg, cb)
    end

    overlay._glowActive = true
    overlay:SetAlpha(1)
    overlay:Show()
end

StopNativeGlow = function(overlay)
    if not overlay then return end
    _G_Glows.StopAllGlows(overlay)
    overlay._glowActive = false
    overlay:SetAlpha(0)
end
ns.StartNativeGlow = StartNativeGlow
ns.StopNativeGlow = StopNativeGlow

-- Our bar frames (keyed by bar key)
local cdmBarFrames = {}
-- Icon frames per bar (keyed by bar key, array of icon frames)
local cdmBarIcons = {}
-- Fast barData lookup by key (rebuilt in BuildAllCDMBars, avoids linear scan per tick)
local barDataByKey = {}

-- Expose our CDM bar frames so the glow system can reference them
ns.GetCDMBarFrame = function(barKey)
    return cdmBarFrames[barKey]
end
-- Global accessor for cross-addon frame lookups
_G._ECME_GetBarFrame = function(barKey)
    return cdmBarFrames[barKey]
end
-- Global accessors for party/player frame discovery
_G._ECME_FindPlayerPartyFrame = function()
    return FindPlayerPartyFrame()
end
_G._ECME_FindPlayerUnitFrame = function()
    return FindPlayerUnitFrame()
end
ns.GetCDMBarIcons = function(barKey)
    return cdmBarIcons[barKey]
end

-------------------------------------------------------------------------------
--  Proc Glow System: hooks Blizzard's SpellAlertManager to show proc glows
--  on our CDM icons when Blizzard fires ShowAlert/HideAlert on CDM children.
--  Custom bars use SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE events instead.
-------------------------------------------------------------------------------
local PROC_GLOW_STYLE = 6  -- "Modern WoW Glow" flipbook

-- Reverse lookup: Blizzard CDM viewer frame name ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ our bar key
local _blizzViewerToBarKey = {
    EssentialCooldownViewer = "cooldowns",
    UtilityCooldownViewer   = "utility",
    BuffIconCooldownViewer  = "buffs",
}

-- Walk up from a frame to find which Blizzard CDM viewer it belongs to
local function GetBarKeyForBlizzChild(frame)
    local current = frame
    while current do
        local parent = current:GetParent()
        if not parent then return nil end
        local name = parent.GetName and parent:GetName()
        if name and _blizzViewerToBarKey[name] then
            return _blizzViewerToBarKey[name], current
        end
        current = parent
    end
    return nil
end

-- Find our icon that mirrors a given Blizzard CDM child
local function FindOurIconForBlizzChild(barKey, blizzChild)
    local icons = cdmBarIcons[barKey]
    if not icons then return nil end
    for _, icon in ipairs(icons) do
        if icon._blizzChild == blizzChild then return icon end
    end
    return nil
end

-- Resolve spellID from a Blizzard CDM child (for IsSpellOverlayed guard)
local function ResolveBlizzChildSpellID(blizzChild)
    local cdID = blizzChild.cooldownID
    if not cdID and blizzChild.cooldownInfo then
        cdID = blizzChild.cooldownInfo.cooldownID
    end
    if cdID then
        local info = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
            and C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
        if info then return info.overrideSpellID or info.spellID end
    end
    return nil
end

-- Show proc glow on one of our icons (separate from active state glow)
local function ShowProcGlow(icon, cr, cg, cb)
    if not icon or not icon._glowOverlay then return end
    -- Don't double-start if already showing proc glow
    if icon._procGlowActive then return end
    -- If active state glow is running, stop it first (proc glow takes priority)
    if icon._isActive and icon._glowOverlay._glowActive then
        StopNativeGlow(icon._glowOverlay)
    end
    StartNativeGlow(icon._glowOverlay, PROC_GLOW_STYLE, cr, cg, cb)
    icon._procGlowActive = true
end

-- Stop proc glow on one of our icons (restores active state glow if needed)
local function StopProcGlow(icon)
    if not icon or not icon._procGlowActive then return end
    StopNativeGlow(icon._glowOverlay)
    icon._procGlowActive = false
    -- Restore active state glow if the icon is still in active state
    if icon._isActive and icon._glowOverlay then
        local barData = barDataByKey[icon._barKey]
        if barData then
            local activeAnim = barData.activeStateAnim or "blizzard"
            local glowIdx = tonumber(activeAnim)
            if glowIdx then
                local animR, animG, animB = 1.0, 0.85, 0.0
                if barData.activeAnimClassColor then
                    local _, ct = UnitClass("player")
                    if ct then local cc = RAID_CLASS_COLORS[ct]; if cc then animR, animG, animB = cc.r, cc.g, cc.b end end
                elseif barData.activeAnimR then
                    animR = barData.activeAnimR; animG = barData.activeAnimG or 0.85; animB = barData.activeAnimB or 0.0
                end
                StartNativeGlow(icon._glowOverlay, glowIdx, animR, animG, animB)
            end
        end
    end
end

-- Proc glow color: hardcoded gold (#ffc923)
local PROC_GLOW_R, PROC_GLOW_G, PROC_GLOW_B = 1.0, 0.788, 0.137

-- Install hooks on ActionButtonSpellAlertManager (called once during init)
local _procGlowHooksInstalled = false
local function InstallProcGlowHooks()
    if _procGlowHooksInstalled then return end
    if not ActionButtonSpellAlertManager then return end

    hooksecurefunc(ActionButtonSpellAlertManager, "ShowAlert", function(_, frame)
        if not frame then return end
        local barKey, cdmChild = GetBarKeyForBlizzChild(frame)
        if not barKey or not cdmChild then return end

        -- Hide Blizzard's built-in SpellActivationAlert on the CDM child
        if cdmChild.SpellActivationAlert then
            cdmChild.SpellActivationAlert:SetAlpha(0)
            cdmChild.SpellActivationAlert:Hide()
        end

        -- Defer by one frame so the icon mapping from UpdateCDMBarIcons is current
        C_Timer.After(0, function()
            local ourIcon = FindOurIconForBlizzChild(barKey, cdmChild)
            if not ourIcon then return end
            -- Re-suppress Blizzard alert (may have been re-shown)
            if cdmChild.SpellActivationAlert then
                cdmChild.SpellActivationAlert:SetAlpha(0)
                cdmChild.SpellActivationAlert:Hide()
            end
            local cr, cg, cb = PROC_GLOW_R, PROC_GLOW_G, PROC_GLOW_B
            ShowProcGlow(ourIcon, cr, cg, cb)
        end)
    end)

    hooksecurefunc(ActionButtonSpellAlertManager, "HideAlert", function(_, frame)
        if not frame then return end
        local barKey, cdmChild = GetBarKeyForBlizzChild(frame)
        if not barKey or not cdmChild then return end
        local ourIcon = FindOurIconForBlizzChild(barKey, cdmChild)
        if not ourIcon or not ourIcon._procGlowActive then return end

        -- Guard: CDM may fire HideAlert during internal refresh cycles even though
        -- the spell is still procced. Check IsSpellOverlayed before killing the glow.
        local spellID = ResolveBlizzChildSpellID(cdmChild)
        if spellID and C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed then
            local ok, overlayed = pcall(C_SpellActivationOverlay.IsSpellOverlayed, spellID)
            if ok and overlayed then
                -- Spell still active ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â suppress Blizzard's alert again and keep our glow
                if cdmChild.SpellActivationAlert then
                    cdmChild.SpellActivationAlert:SetAlpha(0)
                    cdmChild.SpellActivationAlert:Hide()
                end
                return
            end
        end

        StopProcGlow(ourIcon)
    end)

    _procGlowHooksInstalled = true
end

-- Handle proc glow for custom bars via spell activation overlay events.
-- Called from the event handler when SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE fires.
local function OnProcGlowEvent(event, spellID)
    if not spellID then return end
    local p = ECME.db and ECME.db.profile
    if not p or not p.cdmBars or not p.cdmBars.bars then return end

    for _, barData in ipairs(p.cdmBars.bars) do
        if barData.enabled and barData.isCustom and barData.customSpells then
            local icons = cdmBarIcons[barData.key]
            if icons then
                for i, sid in ipairs(barData.customSpells) do
                    if sid == spellID and icons[i] then
                        if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
                            ShowProcGlow(icons[i], PROC_GLOW_R, PROC_GLOW_G, PROC_GLOW_B)
                        else
                            StopProcGlow(icons[i])
                        end
                    end
                end
            end
        end
    end
end
ns.OnProcGlowEvent = OnProcGlowEvent


-------------------------------------------------------------------------------
--  CDM Bars: Our replacement for Blizzard's Cooldown Manager
--  Captures Blizzard positions on first login, then creates our own bars.
-------------------------------------------------------------------------------
local CDM_FONT_FALLBACK = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"
local function GetCDMFont()
    if EllesmereUI and EllesmereUI.GetFontPath then
        return EllesmereUI.GetFontPath("cdm")
    end
    return CDM_FONT_FALLBACK
end

-- Blizzard CDM frame names
local BLIZZ_CDM_FRAMES = {
    cooldowns = "EssentialCooldownViewer",
    utility   = "UtilityCooldownViewer",
    buffs     = "BuffIconCooldownViewer",
}

-- CDM category numbers per bar key (for C_CooldownViewer API)
local CDM_BAR_CATEGORIES = {
    cooldowns = { 0, 1 },    -- Essential + Utility
    utility   = { 0, 1 },    -- Essential + Utility
    buffs     = { 2, 3 },    -- Tracked Buff + Tracked Debuff
}

-- Maximum number of custom bars a user can create
local MAX_CUSTOM_BARS = 6

-------------------------------------------------------------------------------
--  Party Frame Discovery
--  Scans known party/raid frame addons to find the player's own unit button.
-------------------------------------------------------------------------------
local PARTY_FRAME_PREFIXES = {
    { addon = "ElvUI",  prefix = "ElvUF_PartyGroup1UnitButton", count = 5 },
    { addon = "Cell",   prefix = "CellPartyFrameMember",        count = 5 },
    { addon = nil,      prefix = "CompactPartyFrameMember",     count = 5 },
    { addon = nil,      prefix = "CompactRaidFrame",            count = 40 },
}

local _cachedPartyFrame
local _cachedPartyFrameRoster = 0  -- invalidate on roster change

local function FindPlayerPartyFrame()
    -- Use cache if roster hasn't changed
    local rosterToken = GetNumGroupMembers()
    if _cachedPartyFrame and _cachedPartyFrameRoster == rosterToken then
        if _cachedPartyFrame:IsVisible() then
            return _cachedPartyFrame
        end
    end
    _cachedPartyFrame = nil
    _cachedPartyFrameRoster = rosterToken

    for _, src in ipairs(PARTY_FRAME_PREFIXES) do
        if not src.addon or C_AddOns.IsAddOnLoaded(src.addon) then
            for i = 1, src.count do
                local frame = _G[src.prefix .. i]
                if frame and frame.GetAttribute and frame:GetAttribute("unit") == "player"
                   and frame.IsVisible and frame:IsVisible() then
                    _cachedPartyFrame = frame
                    return frame
                end
            end
        end
    end
    -- Check Dander's party container
    if C_AddOns.IsAddOnLoaded("DandersFrames") then
        local container = _G["DandersPartyContainer"]
        if container and container.IsVisible and container:IsVisible() then
            _cachedPartyFrame = container
            return container
        end
    end

    return nil
end

-------------------------------------------------------------------------------
--  Player Frame Discovery
--  Scans known unit frame addons to find the player's unit frame.
--  Priority: ours ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ ElvUI ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Dander's party header ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Blizzard PlayerFrame
-------------------------------------------------------------------------------
local PLAYER_FRAME_SOURCES = {
    { addon = "EllesmereUIUnitFrames", global = "EllesmereUIUnitFrames_Player" },
    { addon = "ElvUI",                 global = "ElvUF_Player" },
}

local _cachedPlayerFrame

local function FindPlayerUnitFrame()
    if _cachedPlayerFrame and _cachedPlayerFrame:IsVisible() then
        return _cachedPlayerFrame
    end
    _cachedPlayerFrame = nil

    -- Check dedicated player frame addons first
    for _, src in ipairs(PLAYER_FRAME_SOURCES) do
        if C_AddOns.IsAddOnLoaded(src.addon) then
            local frame = _G[src.global]
            if frame and frame.IsVisible and frame:IsVisible() then
                _cachedPlayerFrame = frame
                return frame
            end
        end
    end

    -- Check Dander's party header children for the player unit
    if C_AddOns.IsAddOnLoaded("DandersFrames") then
        local header = _G["DandersPartyHeader"]
        if header then
            for i = 1, 5 do
                local child = header:GetAttribute("child" .. i)
                if child and child.GetAttribute and child:GetAttribute("unit") == "player"
                   and child.IsVisible and child:IsVisible() then
                    _cachedPlayerFrame = child
                    return child
                end
            end
        end
    end

    -- Fallback: Blizzard default player frame
    local blizz = _G["PlayerFrame"]
    if blizz and blizz.IsVisible and blizz:IsVisible() then
        _cachedPlayerFrame = blizz
        return blizz
    end

    return nil
end

-------------------------------------------------------------------------------
--  Trinket / Racial / Health Potion data (for "trinkets" bar type)
--  Encoding in customSpells:  positive = spellID,  -13/-14 = trinket slot
-------------------------------------------------------------------------------
local TRINKET_SLOT_1 = 13
local TRINKET_SLOT_2 = 14

-- Racial abilities by internal race name ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ list of spellIDs
-- Entries with a table { spellID, class="CLASS" } are class-restricted.
local RACE_RACIALS = {
    Scourge            = { 7744 },
    Tauren             = { 20549 },
    Orc                = { 20572, 33697, 33702 },
    BloodElf           = { 202719, 50613, 25046, 69179, 80483, 155145, 129597, 232633, 28730 },
    Dwarf              = { 20594 },
    Troll              = { 26297 },
    Draenei            = { 28880 },
    NightElf           = { 58984 },
    Human              = { 59752 },
    DarkIronDwarf      = { 265221 },
    Gnome              = { 20589 },
    HighmountainTauren = { 69041 },
    Worgen             = { 68992 },
    Goblin             = { 69070 },
    Pandaren           = { 107079 },
    MagharOrc          = { 274738 },
    LightforgedDraenei = { 255647 },
    VoidElf            = { 256948 },
    KulTiran           = { 287712 },
    ZandalariTroll     = { 291944 },
    Vulpera            = { 312411 },
    Mechagnome         = { 312924 },
    Dracthyr           = { 357214, { 368970, class = "EVOKER" } },
    EarthenDwarf       = { 436344 },
    Haranir            = { 1287685 },
}

-- Health potions / healthstones: { itemID, spellID [, class] }
local HEALTH_ITEMS = {
    { itemID = 241304, spellID = 1234768 },                      -- Silvermoon Health Potion
    { itemID = 241308, spellID = 1236616 },                      -- Light's Potential
    { itemID = 5512,   spellID = 6262 },                         -- Healthstone
    { itemID = 224464, spellID = 452930, class = "WARLOCK" },    -- Demonic Healthstone
}

-- Cached player info (set once at PLAYER_LOGIN)
local _playerRace, _playerClass

-- Forward declarations
local BuildCDMBar, LayoutCDMBar, UpdateCDMBarIcons, HideBlizzardCDM, RestoreBlizzardCDM
local CaptureCDMPositions, ApplyCDMBarPosition, ApplyShapeToCDMIcon

-------------------------------------------------------------------------------
--  Capture Blizzard CDM positions (first login only)
-------------------------------------------------------------------------------
CaptureCDMPositions = function()
    local captured = {}
    local uiW, uiH = UIParent:GetSize()
    local uiScale = UIParent:GetEffectiveScale()

    for barKey, frameName in pairs(BLIZZ_CDM_FRAMES) do
        local frame = _G[frameName]
        if frame then
            local data = {}

            -- Bar scale from the frame's drag-handle scale
            local frameScale = frame:GetScale()
            if frameScale and frameScale > 0.1 then
                data.barScale = frameScale
            end

            -- Icon size + spacing: read from child icons.
            -- Blizzard CDM icons have a base size and a per-icon scale driven
            -- by the IconSize percentage slider. Spacing is measured from the
            -- gap between two adjacent visible icons in parent coordinates.
            local childCount = frame:GetNumChildren()
            local numDistinctY = {}
            local shownIcons = {}
            for ci = 1, childCount do
                local child = select(ci, frame:GetChildren())
                if child and child.Icon then
                    local cw = child:GetWidth()
                    local cs = child:GetScale()
                    if cw and cw > 1 and not data.iconSize then
                        local visual = cw * (cs or 1)
                        data.iconSize = math.floor(visual + 0.5)
                    end
                    -- Collect shown icons for spacing measurement
                    if child:IsShown() then
                        shownIcons[#shownIcons + 1] = child
                        -- Track distinct Y positions for row counting
                        if child:GetPoint(1) then
                            local _, _, _, _, cy = child:GetPoint(1)
                            if cy then
                                numDistinctY[math.floor(cy + 0.5)] = true
                            end
                        end
                    end
                end
            end

            -- Spacing: measure gap between adjacent visible icons
            if #shownIcons >= 2 and data.iconSize then
                -- Sort by left edge so we measure truly adjacent icons
                table.sort(shownIcons, function(a, b)
                    return (a:GetLeft() or 0) < (b:GetLeft() or 0)
                end)
                -- Find the smallest step between any two consecutive sorted icons
                -- GetLeft() returns UIParent-coordinate-space values
                local bestStep = nil
                for si = 1, #shownIcons - 1 do
                    local aLeft = shownIcons[si]:GetLeft()
                    local bLeft = shownIcons[si + 1]:GetLeft()
                    if aLeft and bLeft then
                        local dist = bLeft - aLeft
                        if dist > 0 and (not bestStep or dist < bestStep) then
                            bestStep = dist
                        end
                    end
                end
                if bestStep then
                    -- bestStep is in UIParent coords; iconSize = cw * cs (visual size in parent-of-icon coords)
                    -- Convert bestStep from UIParent coords to icon-parent coords
                    -- icon-parent coord ? UIParent coord multiplier = frame.effectiveScale / UIParent.effectiveScale
                    -- So to go back: divide by that
                    local frameEff = frame:GetEffectiveScale()
                    local uiEff = UIParent:GetEffectiveScale()
                    local parentStep = bestStep * uiEff / frameEff
                    -- Now parentStep is in frame coords; but iconSize = cw * cs, and positions in frame use cw units
                    -- So step in iconSize units = parentStep * cs
                    local cs = shownIcons[1]:GetScale() or 1
                    local stepInIconUnits = parentStep * cs
                    local gap = stepInIconUnits - data.iconSize
                    if gap < 0 then gap = 0 end
                    data.spacing = math.floor(gap + 0.5)
                end
            end

            -- Rows: count distinct Y positions among visible icon children
            local rowCount = 0
            for _ in pairs(numDistinctY) do rowCount = rowCount + 1 end
            if rowCount >= 1 then
                data.numRows = rowCount
            end

            -- Orientation from frame property
            if frame.isHorizontal ~= nil then
                data.isHorizontal = frame.isHorizontal
            end

            -- Position (center-based, in UIParent coordinates)
            if frame:GetPoint(1) then
                local cx, cy = frame:GetCenter()
                if cx and cy then
                    local bScale = frame:GetEffectiveScale()
                    cx = cx * bScale / uiScale
                    cy = cy * bScale / uiScale
                    data.point = "CENTER"
                    data.relPoint = "CENTER"
                    data.x = cx - (uiW / 2)
                    data.y = cy - (uiH / 2)
                end
            end

            captured[barKey] = data
        end
    end

    return captured
end

-------------------------------------------------------------------------------
--  Hide / Restore Blizzard CDM
-------------------------------------------------------------------------------
HideBlizzardCDM = function()
    for _, frameName in pairs(BLIZZ_CDM_FRAMES) do
        local frame = _G[frameName]
        if frame then
            -- Make invisible but keep functional so children still report
            -- IsShown() correctly and cooldowns keep ticking.
            -- We move it off-screen and set alpha to 0 instead of reparenting.
            if not frame._ecmeHidden then
                frame._ecmeOrigAlpha = frame:GetAlpha()
                frame._ecmeOrigPoints = {}
                for i = 1, frame:GetNumPoints() do
                    frame._ecmeOrigPoints[i] = { frame:GetPoint(i) }
                end
                frame:SetAlpha(0)
                frame:ClearAllPoints()
                frame:SetPoint("CENTER", UIParent, "CENTER", 0, 10000)
                frame._ecmeHidden = true
            end
        end
    end
end

RestoreBlizzardCDM = function()
    for _, frameName in pairs(BLIZZ_CDM_FRAMES) do
        local frame = _G[frameName]
        if frame and frame._ecmeHidden then
            frame:SetAlpha(frame._ecmeOrigAlpha or 1)
            if frame._ecmeOrigPoints then
                frame:ClearAllPoints()
                for _, pt in ipairs(frame._ecmeOrigPoints) do
                    frame:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5])
                end
            end
            frame._ecmeHidden = false
        end
    end
end

-------------------------------------------------------------------------------
--  CDM Bar Position Helpers
-------------------------------------------------------------------------------
local function ApplyBarPositionCentered(frame, pos, w, h, scale)
    if not pos or not pos.point then return end
    frame:ClearAllPoints()
    -- Convert legacy TOPLEFT positions to CENTER so the bar stays centered
    -- when icon count changes across specs.
    if pos.point == "TOPLEFT" and pos.relPoint == "TOPLEFT" then
        local fw, fh = frame:GetWidth() or 0, frame:GetHeight() or 0
        local uiW, uiH = UIParent:GetSize()
        local cx = (pos.x or 0) + fw * 0.5 - uiW * 0.5
        local cy = (pos.y or 0) - fh * 0.5 + uiH * 0.5
        frame:SetPoint("CENTER", UIParent, "CENTER", cx, cy)
        -- Migrate the saved position to CENTER for future loads
        pos.point = "CENTER"
        pos.relPoint = "CENTER"
        pos.x = cx
        pos.y = cy
    else
        frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    end
end

local function SaveCDMBarPosition(barKey, frame)
    if not frame then return end
    local p = ECME.db.profile
    local scale = frame:GetScale() or 1
    local cx, cy = frame:GetCenter()
    if not cx then return end
    local uiW, uiH = UIParent:GetSize()
    local uiScale = UIParent:GetEffectiveScale()
    local fScale = frame:GetEffectiveScale()
    cx = cx * fScale / uiScale
    cy = cy * fScale / uiScale
    p.cdmBarPositions[barKey] = {
        point = "CENTER", relPoint = "CENTER",
        x = (cx - uiW / 2) / scale,
        y = (cy - uiH / 2) / scale,
    }
end

-------------------------------------------------------------------------------
--  Helper: get the frame anchor point for a CDM bar.
--  Returns the near-edge center of the frame (the edge that faces away from target).
--  grow RIGHT -> near edge = LEFT, grow LEFT -> RIGHT, grow DOWN -> TOP, grow UP -> BOTTOM
-------------------------------------------------------------------------------
local function CDMFrameAnchorPoint(anchorSide, grow, centered)
    if grow == "RIGHT" then return "LEFT"   end
    if grow == "LEFT"  then return "RIGHT"  end
    if grow == "DOWN"  then return "TOP"    end
    if grow == "UP"    then return "BOTTOM" end
    return "LEFT"
end

-------------------------------------------------------------------------------
--  Build a single CDM bar frame
-------------------------------------------------------------------------------
BuildCDMBar = function(barIndex)
    local p = ECME.db.profile
    local bars = p.cdmBars.bars
    local barData = bars[barIndex]
    if not barData then return end

    local key = barData.key
    local frame = cdmBarFrames[key]

    if not frame then
        frame = CreateFrame("Frame", "ECME_CDMBar_" .. key, UIParent)
        frame:SetFrameStrata("LOW")
        frame:SetFrameLevel(5)
        if frame.EnableMouseClicks then frame:EnableMouseClicks(false) end
        if frame.EnableMouseMotion then frame:EnableMouseMotion(true) end
        frame._barKey = key
        frame._barIndex = barIndex
        cdmBarFrames[key] = frame
        cdmBarIcons[key] = {}
    end

    if not barData.enabled then
        if frame._mouseTrack then
            frame:SetScript("OnUpdate", nil)
            frame._mouseTrack = nil
            if frame._preMousePos and not p.cdmBarPositions[key] then
                p.cdmBarPositions[key] = frame._preMousePos
            end
            frame._preMousePos = nil
        end
        frame:Hide()
        return
    end

    -- Apply scale
    local scale = barData.barScale or 1.0
    if scale < 0.1 then scale = 1.0 end
    frame:SetScale(scale)

    -- Clear any previous mouse-tracking OnUpdate
    if frame._mouseTrack then
        frame:SetScript("OnUpdate", nil)
        frame._mouseTrack = nil
        -- Restore saved position from before mouse anchor
        if frame._preMousePos and not p.cdmBarPositions[key] then
            p.cdmBarPositions[key] = frame._preMousePos
        end
        frame._preMousePos = nil
        -- Restore default strata when leaving cursor anchor
        frame:SetFrameStrata("LOW")
        frame:SetFrameLevel(5)
        -- Restore mouse motion (was disabled while cursor-following)
        if frame.EnableMouseMotion then frame:EnableMouseMotion(true) end
    end
    frame._mouseGrow = nil

    -- Position
    local anchorKey = barData.anchorTo
    if anchorKey == "mouse" then
        -- Stash saved position so it can be restored when unanchoring
        if p.cdmBarPositions[key] then
            frame._preMousePos = p.cdmBarPositions[key]
        end
        -- Anchor position acts as build direction for mouse cursor tracking
        local anchorPos = barData.anchorPosition or "right"
        local oX = barData.anchorOffsetX or 0
        local oY = barData.anchorOffsetY or 0
        -- Determine SetPoint anchor and 15px directional nudge
        local pointFrom, baseOX, baseOY, forceGrow
        if anchorPos == "left" then
            pointFrom = "RIGHT"; forceGrow = "LEFT"
            baseOX = -15 + oX; baseOY = oY
        elseif anchorPos == "right" then
            pointFrom = "LEFT"; forceGrow = "RIGHT"
            baseOX = 15 + oX; baseOY = oY
        elseif anchorPos == "top" then
            pointFrom = "BOTTOM"; forceGrow = "UP"
            baseOX = oX; baseOY = 15 + oY
        elseif anchorPos == "bottom" then
            pointFrom = "TOP"; forceGrow = "DOWN"
            baseOX = oX; baseOY = -15 + oY
        else
            pointFrom = "LEFT"; forceGrow = "RIGHT"
            baseOX = 15 + oX; baseOY = oY
        end
        frame._mouseGrow = forceGrow
        -- Elevate to TOOLTIP strata so the bar renders above all UI
        frame:SetFrameStrata("TOOLTIP")
        frame:SetFrameLevel(9980)
        -- Make fully click-through while following cursor
        if frame.EnableMouseClicks then frame:EnableMouseClicks(false) end
        if frame.EnableMouseMotion then frame:EnableMouseMotion(false) end
        local lastMX, lastMY
        frame:ClearAllPoints()
        frame:SetPoint(pointFrom, UIParent, "BOTTOMLEFT", 0, 0)
        frame._mouseTrack = true
        frame:SetScript("OnUpdate", function()
            local s = UIParent:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            cx = floor(cx / s + 0.5)
            cy = floor(cy / s + 0.5)
            if cx ~= lastMX or cy ~= lastMY then
                lastMX, lastMY = cx, cy
                frame:ClearAllPoints()
                frame:SetPoint(pointFrom, UIParent, "BOTTOMLEFT", cx + baseOX, cy + baseOY)
            end
        end)
    elseif anchorKey == "partyframe" then
        -- Anchor to the player's party frame
        local partyFrame = FindPlayerPartyFrame()
        if partyFrame then
            frame:ClearAllPoints()
            local side = barData.partyFrameSide or "LEFT"
            local oX = barData.partyFrameOffsetX or 0
            local oY = barData.partyFrameOffsetY or 0
            local grow = barData.growDirection or "RIGHT"
            local centered = barData.growCentered ~= false
            local fp = CDMFrameAnchorPoint(side, grow, centered)
            frame._anchorSide = side:upper()
            if side == "LEFT" then
                frame:SetPoint(fp, partyFrame, "LEFT", oX, oY)
            elseif side == "RIGHT" then
                frame:SetPoint(fp, partyFrame, "RIGHT", oX, oY)
            elseif side == "TOP" then
                frame:SetPoint(fp, partyFrame, "TOP", oX, oY)
            elseif side == "BOTTOM" then
                frame:SetPoint(fp, partyFrame, "BOTTOM", oX, oY)
            end
        else
            -- No party frame found ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â fall back to saved position
            local pos = p.cdmBarPositions[key]
            if pos and pos.point then
                ApplyBarPositionCentered(frame, pos, 1, 1, scale)
            else
                frame:ClearAllPoints()
                frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
        end
    elseif anchorKey == "playerframe" then
        -- Anchor to the player's unit frame
        local playerFrame = FindPlayerUnitFrame()
        if playerFrame then
            frame:ClearAllPoints()
            local side = barData.playerFrameSide or "LEFT"
            local oX = barData.playerFrameOffsetX or 0
            local oY = barData.playerFrameOffsetY or 0
            local grow = barData.growDirection or "RIGHT"
            local centered = barData.growCentered ~= false
            local fp = CDMFrameAnchorPoint(side, grow, centered)
            frame._anchorSide = side:upper()
            if side == "LEFT" then
                frame:SetPoint(fp, playerFrame, "LEFT", oX, oY)
            elseif side == "RIGHT" then
                frame:SetPoint(fp, playerFrame, "RIGHT", oX, oY)
            elseif side == "TOP" then
                frame:SetPoint(fp, playerFrame, "TOP", oX, oY)
            elseif side == "BOTTOM" then
                frame:SetPoint(fp, playerFrame, "BOTTOM", oX, oY)
            end
        else
            -- No player frame found ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â fall back to saved position
            local pos = p.cdmBarPositions[key]
            if pos and pos.point then
                ApplyBarPositionCentered(frame, pos, 1, 1, scale)
            else
                frame:ClearAllPoints()
                frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
        end
    elseif anchorKey == "erb_castbar" or anchorKey == "erb_powerbar" or anchorKey == "erb_classresource" then
        -- Anchor to EllesmereUI Resource Bars frames
        local erbFrameNames = {
            erb_castbar = "ERB_CastBarFrame",
            erb_powerbar = "ERB_PrimaryBar",
            erb_classresource = "ERB_SecondaryFrame",
        }
        local erbFrame = _G[erbFrameNames[anchorKey]]
        if erbFrame then
            local anchorPos = barData.anchorPosition or "left"
            frame:ClearAllPoints()
            local gap = barData.spacing or 2
            local oX = barData.anchorOffsetX or 0
            local oY = barData.anchorOffsetY or 0
            local grow = barData.growDirection or "RIGHT"
            local centered = barData.growCentered ~= false
            local fp = CDMFrameAnchorPoint(anchorPos:upper(), grow, centered)
            frame._anchorSide = anchorPos:upper()
            local ok
            if anchorPos == "left" then
                ok = pcall(frame.SetPoint, frame, fp, erbFrame, "LEFT", -gap + oX, oY)
            elseif anchorPos == "right" then
                ok = pcall(frame.SetPoint, frame, fp, erbFrame, "RIGHT", gap + oX, oY)
            elseif anchorPos == "top" then
                ok = pcall(frame.SetPoint, frame, fp, erbFrame, "TOP", oX, gap + oY)
            elseif anchorPos == "bottom" then
                ok = pcall(frame.SetPoint, frame, fp, erbFrame, "BOTTOM", oX, -gap + oY)
            end
            -- Circular anchor detected — fall back to center
            if not ok then
                frame:ClearAllPoints()
                frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
        else
            -- Resource Bars frame not available ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â fall back to saved position
            local pos = p.cdmBarPositions[key]
            if pos and pos.point then
                ApplyBarPositionCentered(frame, pos, 1, 1, scale)
            else
                frame:ClearAllPoints()
                frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
        end
    elseif anchorKey and anchorKey ~= "none" and cdmBarFrames[anchorKey] then
        local anchorFrame = cdmBarFrames[anchorKey]
        local anchorPos = barData.anchorPosition or "left"
        frame:ClearAllPoints()
        local gap = barData.spacing or 2
        local oX = barData.anchorOffsetX or 0
        local oY = barData.anchorOffsetY or 0
        local grow = barData.growDirection or "RIGHT"
        local centered = barData.growCentered ~= false
        local fp = CDMFrameAnchorPoint(anchorPos:upper(), grow, centered)
        frame._anchorSide = anchorPos:upper()
        local ok
        if anchorPos == "left" then
            ok = pcall(frame.SetPoint, frame, fp, anchorFrame, "LEFT", -gap + oX, oY)
        elseif anchorPos == "right" then
            ok = pcall(frame.SetPoint, frame, fp, anchorFrame, "RIGHT", gap + oX, oY)
        elseif anchorPos == "top" then
            ok = pcall(frame.SetPoint, frame, fp, anchorFrame, "TOP", oX, gap + oY)
        elseif anchorPos == "bottom" then
            ok = pcall(frame.SetPoint, frame, fp, anchorFrame, "BOTTOM", oX, -gap + oY)
        end
        if not ok then
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
    else
        local pos = p.cdmBarPositions[key]
        if pos and pos.point then
            ApplyBarPositionCentered(frame, pos, 1, 1, scale)
        else
            -- Default fallback positions
            frame:ClearAllPoints()
            if key == "cooldowns" then
                frame:SetPoint("CENTER", UIParent, "CENTER", 0, -275)
            elseif key == "utility" then
                frame:SetPoint("CENTER", UIParent, "CENTER", 0, -320)
            elseif key == "buffs" then
                frame:SetPoint("CENTER", UIParent, "CENTER", 0, -365)
            else
                frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
        end
    end

    frame:Show()
end

-------------------------------------------------------------------------------
--  Layout icons within a CDM bar
-------------------------------------------------------------------------------
LayoutCDMBar = function(barKey)
    local frame = cdmBarFrames[barKey]
    local icons = cdmBarIcons[barKey]
    if not frame or not icons then return end

    local barData = barDataByKey[barKey]
    if not barData or not barData.enabled then return end

    local barScale = barData.barScale or 1.0
    if barScale < 0.1 then barScale = 1.0 end
    local iconW = SnapForScale(barData.iconSize or 36, barScale)
    local iconH = iconW
    local shape = barData.iconShape or "none"
    if shape == "cropped" then
        iconH = SnapForScale(math.floor((barData.iconSize or 36) * 0.80 + 0.5), barScale)
    end
    local spacing = SnapForScale(barData.spacing or 2, barScale)
    local grow = frame._mouseGrow or barData.growDirection or "RIGHT"
    local numRows = barData.numRows or 1
    if numRows < 1 then numRows = 1 end

    -- Collect visible icons (reuse buffer to avoid garbage)
    local visibleIcons = frame._visibleIconsBuf
    if not visibleIcons then visibleIcons = {}; frame._visibleIconsBuf = visibleIcons else wipe(visibleIcons) end
    for _, icon in ipairs(icons) do
        if icon:IsShown() then
            visibleIcons[#visibleIcons + 1] = icon
        end
    end

    local count = #visibleIcons
    if count == 0 then
        frame:SetSize(1, 1)
        if frame._barBg then frame._barBg:Hide() end
        return
    end

    local isHoriz = (grow == "RIGHT" or grow == "LEFT")
    local stride = math.ceil(count / numRows)

    -- Container size (already snapped values)
    local totalW, totalH
    if isHoriz then
        totalW = stride * iconW + (stride - 1) * spacing
        totalH = numRows * iconH + (numRows - 1) * spacing
    else
        totalW = numRows * iconW + (numRows - 1) * spacing
        totalH = stride * iconH + (stride - 1) * spacing
    end
    frame:SetSize(totalW, totalH)

    -- Bar opacity (affects entire bar, but respect visibility overrides)
    local vis = barData.barVisibility or "always"
    if vis == "always" or (vis == "in_combat" and _inCombat) then
        frame:SetAlpha(barData.barBgAlpha or 1)
    elseif vis == "mouseover" then
        local state = _cdmHoverStates[barKey]
        if state and state.isHovered then
            frame:SetAlpha(barData.barBgAlpha or 1)
        end
    end

    -- Bar background
    if barData.barBgEnabled then
        if not frame._barBg then
            frame._barBg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        end
        frame._barBg:ClearAllPoints()
        frame._barBg:SetPoint("TOPLEFT", 0, 0)
        frame._barBg:SetPoint("BOTTOMRIGHT", 0, 0)
        frame._barBg:SetColorTexture(barData.barBgR or 0, barData.barBgG or 0, barData.barBgB or 0, 0.5)
        PP.DisablePixelSnap(frame._barBg)
        frame._barBg:Show()
    elseif frame._barBg then
        frame._barBg:Hide()
    end

    local stepW = iconW + spacing
    local stepH = iconH + spacing

    -- Position each icon in a grid anchored to the frame's corners.
    -- Frame bounding box == icon grid, so frame CENTER == icon grid center.
    -- This keeps saved/captured CENTER positions accurate.
    for i, icon in ipairs(visibleIcons) do
        PP.Size(icon, iconW, iconH)
        if icon._glowOverlay then
            icon._glowOverlay:SetSize(iconW + 6, iconH + 6)
        end
        icon:ClearAllPoints()

        local idx = i - 1
        local col = idx % stride
        local row = math.floor(idx / stride)

        if grow == "RIGHT" then
            local flippedRow = (numRows - 1) - row
            PP.Point(icon, "TOPLEFT", frame, "TOPLEFT",
                col * stepW,
                -(flippedRow * stepH))
        elseif grow == "LEFT" then
            local flippedRow = (numRows - 1) - row
            PP.Point(icon, "TOPRIGHT", frame, "TOPRIGHT",
                -(col * stepW),
                -(flippedRow * stepH))
        elseif grow == "DOWN" then
            local flippedRow = (numRows - 1) - row
            PP.Point(icon, "TOPLEFT", frame, "TOPLEFT",
                flippedRow * stepW,
                -(col * stepH))
        elseif grow == "UP" then
            PP.Point(icon, "BOTTOMLEFT", frame, "BOTTOMLEFT",
                row * stepW,
                col * stepH)
        end
    end
end

-------------------------------------------------------------------------------
--  Create a single icon frame for a CDM bar
-------------------------------------------------------------------------------
local function CreateCDMIcon(barKey, index)
    local frame = cdmBarFrames[barKey]
    if not frame then return end

    local barData = barDataByKey[barKey]
    if not barData then return end

    local barScale = barData.barScale or 1.0
    if barScale < 0.1 then barScale = 1.0 end
    local iconSize = barData.iconSize or 36
    local borderSize = SnapForScale(barData.borderSize or 1, barScale)
    local zoom = barData.iconZoom or 0.08

    local icon = CreateFrame("Frame", "ECME_CDMIcon_" .. barKey .. "_" .. index, frame)
    icon:SetSize(SnapForScale(iconSize, barScale), SnapForScale(iconSize, barScale))
    icon:EnableMouse(false)  -- click-through by default
    if icon.EnableMouseMotion then icon:EnableMouseMotion(false) end

    -- Background
    local bg = icon:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(barData.bgR or 0.08, barData.bgG or 0.08, barData.bgB or 0.08, barData.bgA or 0.6)
    PP.DisablePixelSnap(bg)
    icon._bg = bg

    -- Icon texture
    local tex = icon:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", icon, "TOPLEFT", borderSize, -borderSize)
    tex:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -borderSize, borderSize)
    tex:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
    PP.DisablePixelSnap(tex)
    icon._tex = tex

    -- Cooldown overlay (frame level above icon so swipe renders on top of texture)
    local cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    cd:SetFrameLevel(icon:GetFrameLevel() + 1)
    cd:EnableMouse(false)
    cd:SetPoint("TOPLEFT", icon, "TOPLEFT", borderSize, -borderSize)
    cd:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -borderSize, borderSize)
    cd:SetDrawEdge(false)
    cd:SetDrawSwipe(true)
    cd:SetDrawBling(false)
    cd:SetSwipeColor(0, 0, 0, barData.swipeAlpha or 0.7)
    cd:SetSwipeTexture("Interface\\Buttons\\WHITE8x8")
    cd:SetHideCountdownNumbers(not barData.showCooldownText)
    cd:SetReverse(false)
    icon._cooldown = cd

    -- Cooldown text styling
    -- Defer cooldown text font styling (avoids closure per icon ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â uses icon._pendingFont)
    if barData.showCooldownText then
        icon._pendingFontPath = GetCDMFont(); icon._pendingFontSize = barData.cooldownFontSize or 15
    end

    -- Text overlay frame: sits above the cooldown swipe so charge/stack text
    -- is always visible on top of the swipe animation
    local textOverlay = CreateFrame("Frame", nil, icon)
    textOverlay:SetAllPoints(icon)
    textOverlay:SetFrameLevel(icon:GetFrameLevel() + 2)
    textOverlay:EnableMouse(false)
    icon._textOverlay = textOverlay

    -- Charge count text
    local chargeText = textOverlay:CreateFontString(nil, "OVERLAY")
    chargeText:SetFont(GetCDMFont(), barData.stackCountSize or 11, "OUTLINE")
    chargeText:SetPoint("BOTTOMRIGHT", textOverlay, "BOTTOMRIGHT", barData.stackCountX or 0, (barData.stackCountY or 0) + 2)
    chargeText:SetJustifyH("RIGHT")
    chargeText:Hide()
    icon._chargeText = chargeText

    -- Stack count text
    local stackText = textOverlay:CreateFontString(nil, "OVERLAY")
    stackText:SetFont(GetCDMFont(), barData.stackCountSize or 11, "OUTLINE")
    stackText:SetPoint("BOTTOMRIGHT", textOverlay, "BOTTOMRIGHT", barData.stackCountX or 0, (barData.stackCountY or 0) + 2)
    stackText:SetJustifyH("RIGHT")
    stackText:SetTextColor(barData.stackCountR or 1, barData.stackCountG or 1, barData.stackCountB or 1)
    stackText:Hide()
    icon._stackText = stackText

    -- Glow overlay (for active state animations ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â extends 3px beyond icon so pixel glow ants are visible outside border)
    local glowOverlay = CreateFrame("Frame", nil, icon)
    glowOverlay:ClearAllPoints()
    glowOverlay:SetPoint("TOPLEFT",     icon, "TOPLEFT",     -3,  3)
    glowOverlay:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT",  3, -3)
    glowOverlay:SetFrameLevel(icon:GetFrameLevel() + 3)
    glowOverlay:SetAlpha(0)
    glowOverlay:EnableMouse(false)
    icon._glowOverlay = glowOverlay

    -- Keybind text overlay (top-left corner of icon)
    local keybindText = textOverlay:CreateFontString(nil, "OVERLAY")
    keybindText:SetFont(GetCDMFont(), barData.keybindSize or 10, "OUTLINE")
    keybindText:SetPoint("TOPLEFT", textOverlay, "TOPLEFT", barData.keybindOffsetX or 2, barData.keybindOffsetY or -2)
    keybindText:SetJustifyH("LEFT")
    keybindText:SetTextColor(barData.keybindR or 1, barData.keybindG or 1, barData.keybindB or 1, barData.keybindA or 0.9)
    keybindText:Hide()
    icon._keybindText = keybindText

    -- Tooltip on hover — uses OnUpdate cursor check so the icon stays click-through
    -- (EnableMouse stays false; we poll IsMouseOver each frame instead)
    local tooltipOverlay = CreateFrame("Frame", nil, icon)
    tooltipOverlay:SetAllPoints(icon)
    tooltipOverlay:SetFrameLevel(icon:GetFrameLevel() + 4)
    tooltipOverlay:EnableMouse(false)
    icon._tooltipShown = false
    icon:SetScript("OnUpdate", function(self)
        local bd = barDataByKey[self._barKey]
        if not bd or not bd.showTooltip then
            if self._tooltipShown then
                GameTooltip:Hide()
                self._tooltipShown = false
            end
            return
        end
        local over = self:IsMouseOver()
        if over and not self._tooltipShown then
            local sid = self._spellID
            if sid then
                GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
                GameTooltip:SetSpellByID(sid)
                GameTooltip:Show()
                self._tooltipShown = true
            end
        elseif not over and self._tooltipShown then
            GameTooltip:Hide()
            self._tooltipShown = false
        end
    end)
    icon._tooltipOverlay = tooltipOverlay

    -- Border (4 edges)
    local edges = {}
    for i = 1, 4 do        local e = icon:CreateTexture(nil, "OVERLAY", nil, 7)
        e:SetColorTexture(barData.borderR or 0, barData.borderG or 0, barData.borderB or 0, barData.borderA or 1)
        PP.DisablePixelSnap(e)
        edges[i] = e
    end
    edges[1]:SetPoint("TOPLEFT"); edges[1]:SetPoint("TOPRIGHT"); edges[1]:SetHeight(borderSize)
    edges[2]:SetPoint("BOTTOMLEFT"); edges[2]:SetPoint("BOTTOMRIGHT"); edges[2]:SetHeight(borderSize)
    edges[3]:SetPoint("TOPLEFT"); edges[3]:SetPoint("BOTTOMLEFT"); edges[3]:SetWidth(borderSize)
    edges[4]:SetPoint("TOPRIGHT"); edges[4]:SetPoint("BOTTOMRIGHT"); edges[4]:SetWidth(borderSize)
    icon._edges = edges

    -- State tracking
    icon._spellID = nil
    icon._isActive = false
    icon._barKey = barKey

    -- Apply saved icon shape on creation
    local shape = barData.iconShape or "none"
    if shape ~= "none" then
        ApplyShapeToCDMIcon(icon, shape, barData)
    end

    icon:Hide()
    return icon
end
-------------------------------------------------------------------------------
--  Apply custom shape to a CDM icon
-------------------------------------------------------------------------------
ApplyShapeToCDMIcon = function(icon, shape, barData)
    if not icon then return end
    local zoom = barData.iconZoom or 0.08
    local borderSz = barData.borderSize or 1
    local brdR = barData.borderR or 0
    local brdG = barData.borderG or 0
    local brdB = barData.borderB or 0
    local brdA = barData.borderA or 1
    if barData.borderClassColor then
        local _, ct = UnitClass("player")
        if ct then
            local cc = RAID_CLASS_COLORS[ct]
            if cc then brdR, brdG, brdB = cc.r, cc.g, cc.b end
        end
    end

    if shape == "none" or shape == "cropped" or not shape then
        -- Remove shape mask if previously applied
        if icon._shapeMask then
            local mask = icon._shapeMask
            if icon._tex then pcall(icon._tex.RemoveMaskTexture, icon._tex, mask) end
            if icon._bg then pcall(icon._bg.RemoveMaskTexture, icon._bg, mask) end
            if icon._cooldown then pcall(icon._cooldown.RemoveMaskTexture, icon._cooldown, mask) end
            mask:SetTexture(nil); mask:ClearAllPoints(); mask:SetSize(0.001, 0.001); mask:Hide()
        end
        if icon._shapeBorder then icon._shapeBorder:Hide() end
        icon._shapeApplied = nil
        icon._shapeName = nil

        -- Restore square borders
        if icon._edges then
            for i = 1, 4 do icon._edges[i]:Show() end
            PP.Height(icon._edges[1], borderSz)
            PP.Height(icon._edges[2], borderSz)
            PP.Width(icon._edges[3], borderSz)
            PP.Width(icon._edges[4], borderSz)
            for i = 1, 4 do
                icon._edges[i]:SetColorTexture(brdR, brdG, brdB, brdA)
                icon._edges[i]:SetSnapToPixelGrid(false)
                icon._edges[i]:SetTexelSnappingBias(0)
            end
        end

        -- Restore icon texture coords
        if icon._tex then
            icon._tex:ClearAllPoints()
            PP.Point(icon._tex, "TOPLEFT", icon, "TOPLEFT", borderSz, -borderSz)
            PP.Point(icon._tex, "BOTTOMRIGHT", icon, "BOTTOMRIGHT", -borderSz, borderSz)
            if shape == "cropped" then
                icon._tex:SetTexCoord(zoom, 1 - zoom, zoom + 0.10, 1 - zoom - 0.10)
            else
                icon._tex:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
            end
        end

        -- Restore cooldown
        if icon._cooldown then
            icon._cooldown:ClearAllPoints()
            PP.Point(icon._cooldown, "TOPLEFT", icon, "TOPLEFT", borderSz, -borderSz)
            PP.Point(icon._cooldown, "BOTTOMRIGHT", icon, "BOTTOMRIGHT", -borderSz, borderSz)
            pcall(icon._cooldown.SetSwipeTexture, icon._cooldown, "Interface\\Buttons\\WHITE8x8")
            if icon._cooldown.SetUseCircularEdge then pcall(icon._cooldown.SetUseCircularEdge, icon._cooldown, false) end
        end

        -- Restore background
        if icon._bg then
            icon._bg:ClearAllPoints(); icon._bg:SetAllPoints()
        end
        return
    end

    -- Custom shape
    local maskTex = CDM_SHAPE_MASKS[shape]
    if not maskTex then return end

    if not icon._shapeMask then
        icon._shapeMask = icon:CreateMaskTexture()
    end
    local mask = icon._shapeMask
    mask:SetTexture(maskTex, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:Show()

    -- Remove existing mask refs before re-adding
    if icon._tex then pcall(icon._tex.RemoveMaskTexture, icon._tex, mask) end
    if icon._bg then pcall(icon._bg.RemoveMaskTexture, icon._bg, mask) end
    if icon._cooldown then pcall(icon._cooldown.RemoveMaskTexture, icon._cooldown, mask) end

    -- Apply mask to icon texture and background
    if icon._tex then icon._tex:AddMaskTexture(mask) end
    if icon._bg then icon._bg:AddMaskTexture(mask) end

    -- Expand icon beyond frame for shape
    local shapeOffset = CDM_SHAPE_ICON_EXPAND_OFFSETS[shape] or 0
    local shapeDefault = CDM_SHAPE_ZOOM_DEFAULTS[shape] or 0.06
    local iconExp = CDM_SHAPE_ICON_EXPAND + shapeOffset + ((zoom - shapeDefault) * 200)
    if iconExp < 0 then iconExp = 0 end
    local halfIE = iconExp / 2
    if icon._tex then
        icon._tex:ClearAllPoints()
        PP.Point(icon._tex, "TOPLEFT", icon, "TOPLEFT", -halfIE, halfIE)
        PP.Point(icon._tex, "BOTTOMRIGHT", icon, "BOTTOMRIGHT", halfIE, -halfIE)
    end

    -- Mask position (inset for border)
    mask:ClearAllPoints()
    if borderSz >= 1 then
        PP.Point(mask, "TOPLEFT", icon, "TOPLEFT", 1, -1)
        PP.Point(mask, "BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
    else
        mask:SetAllPoints(icon)
    end

    -- Expand texcoords for shape
    local insetPx = CDM_SHAPE_INSETS[shape] or 17
    local visRatio = (128 - 2 * insetPx) / 128
    local expand = ((1 / visRatio) - 1) * 0.5
    if icon._tex then icon._tex:SetTexCoord(-expand, 1 + expand, -expand, 1 + expand) end

    -- Hide square borders
    if icon._edges then
        for i = 1, 4 do icon._edges[i]:Hide() end
    end

    -- Shape border texture (on a dedicated frame above the cooldown swipe)
    if not icon._shapeBorderFrame then
        local sbf = CreateFrame("Frame", nil, icon)
        sbf:SetAllPoints(icon)
        sbf:SetFrameLevel(icon:GetFrameLevel() + 2)
        icon._shapeBorderFrame = sbf
    end
    icon._shapeBorderFrame:SetFrameLevel(icon:GetFrameLevel() + 2)
    if not icon._shapeBorder then
        icon._shapeBorder = icon._shapeBorderFrame:CreateTexture(nil, "OVERLAY", nil, 6)
    end
    local borderTex = icon._shapeBorder
    borderTex:ClearAllPoints()
    borderTex:SetAllPoints(icon)
    if borderSz > 0 and CDM_SHAPE_BORDERS[shape] then
        borderTex:SetTexture(CDM_SHAPE_BORDERS[shape])
        borderTex:SetVertexColor(brdR, brdG, brdB, brdA)
        borderTex:SetSnapToPixelGrid(false)
        borderTex:SetTexelSnappingBias(0)
        borderTex:Show()
    else
        borderTex:Hide()
    end

    -- Apply mask to cooldown so swipe follows shape
    if icon._cooldown then
        icon._cooldown:ClearAllPoints()
        icon._cooldown:SetAllPoints(icon)
        pcall(icon._cooldown.AddMaskTexture, icon._cooldown, mask)
        if icon._cooldown.SetSwipeTexture then
            pcall(icon._cooldown.SetSwipeTexture, icon._cooldown, maskTex)
        end
        local useCircular = (shape ~= "square" and shape ~= "csquare")
        if icon._cooldown.SetUseCircularEdge then pcall(icon._cooldown.SetUseCircularEdge, icon._cooldown, useCircular) end
        local edgeScale = CDM_SHAPE_EDGE_SCALES[shape] or 0.60
        if icon._cooldown.SetEdgeScale then pcall(icon._cooldown.SetEdgeScale, icon._cooldown, edgeScale) end
    end

    -- Restore background to full icon
    if icon._bg then
        icon._bg:ClearAllPoints(); icon._bg:SetAllPoints()
    end

    icon._shapeApplied = true
    icon._shapeName = shape
end
ns.ApplyShapeToCDMIcon = ApplyShapeToCDMIcon

-------------------------------------------------------------------------------
--  Update icons for a CDM bar based on Blizzard CDM children
--  We read the Blizzard CDM bar's children to know which spells are active,
--  then mirror them on our own bar.
-------------------------------------------------------------------------------
-- Shared sort comparator for Blizzard CDM children (avoids closure allocation per tick)
local function SortBlizzChildren(a, b)
    local ai = a.layoutIndex or 0
    local bi = b.layoutIndex or 0
    if ai ~= bi then return ai < bi end
    local ax = a:GetLeft() or 0
    local bx = b:GetLeft() or 0
    return ax < bx
end

-- Reusable buffer for Blizzard CDM children (avoids table allocation per tick)
local _blizzIconsBuf = {}

-- Spell icon texture cache (avoids C_Spell.GetSpellInfo per tick per icon)
local _spellIconCache = {}

-------------------------------------------------------------------------------
--  Update icons for a CDM bar based on Blizzard CDM children
--  Default bars (cooldowns/utility/buffs) mirror Blizzard CDM.
--  Custom bars track user-specified spells directly.
-------------------------------------------------------------------------------
local function UpdateCustomBarIcons(barKey)
    local frame = cdmBarFrames[barKey]
    if not frame then return end

    local barData = barDataByKey[barKey]
    if not barData or not barData.enabled then return end

    -- Clear per-tick aura cache (reuse table to avoid garbage)
    if frame._auraActiveSet then wipe(frame._auraActiveSet) else frame._auraActiveSet = {} end

    local spells = barData.customSpells
    if not spells or #spells == 0 then
        -- Hide all icons
        local icons = cdmBarIcons[barKey]
        if icons then
            for _, icon in ipairs(icons) do icon:Hide() end
        end
        frame:SetSize(1, 1)
        return
    end

    local icons = cdmBarIcons[barKey]

    -- Ensure we have enough icon frames
    while #icons < #spells do
        local newIcon = CreateCDMIcon(barKey, #icons + 1)
        icons[#icons + 1] = newIcon
    end

    local visibleCount = 0
    for i, spellID in ipairs(spells) do
        local ourIcon = icons[i]
        if ourIcon then
            -- Skip blank placeholder slots (0 entries from grid reordering)
            if spellID == 0 then
                ourIcon:Hide()
            -- Trinket slot entries use negative IDs (-13, -14)
            elseif spellID < 0 then
                local slot = -spellID
                local itemID = GetInventoryItemID("player", slot)
                if itemID then
                    local tex = C_Item.GetItemIconByID(itemID)
                    if tex and tex ~= ourIcon._lastTex then
                        ourIcon._tex:SetTexture(tex)
                        ourIcon._lastTex = tex
                    end
                    ApplyTrinketCooldown(ourIcon, slot, barData.desaturateOnCD)
                    ourIcon:Show()
                    visibleCount = visibleCount + 1
                else
                    ourIcon:Hide()
                end
            else
            -- Cache spell icon texture to avoid C_Spell.GetSpellInfo per tick
            local texID = _spellIconCache[spellID]
            if not texID then
                local spellInfo = C_Spell.GetSpellInfo(spellID)
                if spellInfo then
                    texID = spellInfo.iconID
                    _spellIconCache[spellID] = texID
                end
            end
            if texID then
                if texID ~= ourIcon._lastTex then
                    ourIcon._tex:SetTexture(texID)
                    ourIcon._lastTex = texID
                end

                -- Cooldown, desaturation, and charge text (consolidated)
                ourIcon._spellID = spellID
                -- Apply cached keybind for this spell if not already set
                if ourIcon._keybindText and barData.showKeybind then
                    local cachedKey = _cdmKeybindCache[spellID]
                    if not cachedKey then
                        local n = C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
                        if n then cachedKey = _cdmKeybindCache[n] end
                    end
                    if cachedKey then
                        ourIcon._keybindText:SetText(cachedKey)
                        ourIcon._keybindText:Show()
                    elseif ourIcon._keybindText:IsShown() then
                        ourIcon._keybindText:Hide()
                    end
                end
                ApplySpellCooldown(ourIcon, spellID, barData.desaturateOnCD, barData.showCharges, barData.swipeAlpha or 0.7, false)

                if ourIcon._cooldown.SetUseAuraDisplayTime then
                    ourIcon._cooldown:SetUseAuraDisplayTime(false)
                end

                ourIcon:Show()
                visibleCount = visibleCount + 1

                -- Hide buff icons when inactive (aura not active on player) ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â buff bars only
                -- Skip during unlock mode so the bar is fully visible for repositioning
                local isBuffBar = (barKey == "buffs" or barData.barType == "buffs")
                if barData.hideBuffsWhenInactive and isBuffBar and not EllesmereUI._unlockActive then
                    -- Build aura set once per bar update (cached on frame)
                    if next(frame._auraActiveSet) == nil then
                        local blizzBuffFrame = _G.BuffIconCooldownViewer
                        if blizzBuffFrame then
                            for ci = 1, blizzBuffFrame:GetNumChildren() do
                                local ch = select(ci, blizzBuffFrame:GetChildren())
                                if ch and ch.cooldownID and ch.auraInstanceID then
                                    frame._auraActiveSet[ch.cooldownID] = true
                                end
                            end
                        end
                    end
                    if not frame._auraActiveSet[spellID] then
                        ourIcon:Hide()
                        visibleCount = visibleCount - 1
                    end
                end
            else
                ourIcon:Hide()
            end
            end -- spellID < 0 else
        end
    end

    -- Hide excess
    for i = #spells + 1, #icons do
        local ic = icons[i]
        if ic._procGlowActive then
            StopNativeGlow(ic._glowOverlay)
            ic._procGlowActive = false
        end
        ic:Hide()
    end

    -- Only re-layout when visible count changes
    if visibleCount ~= (frame._prevVisibleCount or 0) then
        frame._prevVisibleCount = visibleCount
        LayoutCDMBar(barKey)
    end
end

UpdateCDMBarIcons = function(barKey)
    local frame = cdmBarFrames[barKey]
    if not frame then return end

    local blizzName = BLIZZ_CDM_FRAMES[barKey]
    if not blizzName then return end
    local blizzFrame = _G[blizzName]
    if not blizzFrame then return end

    local barData = barDataByKey[barKey]
    if not barData or not barData.enabled then return end

    -- Gather Blizzard CDM icons that have a valid Icon texture.
    -- We do NOT filter by IsShown() because Blizzard children can briefly
    -- hide/show during state transitions (GCD end, cooldown start, etc.),
    -- which causes our icons to flicker.  Instead we check for a texture.
    -- Reuse buffer to avoid table allocation per tick
    local blizzIcons = _blizzIconsBuf
    local blizzCount = 0

    for i = 1, blizzFrame:GetNumChildren() do
        local child = select(i, blizzFrame:GetChildren())
        if child and child.Icon and child.Icon:GetTexture() then
            blizzCount = blizzCount + 1
            blizzIcons[blizzCount] = child
        end
    end
    -- Clear excess entries from previous tick
    for i = blizzCount + 1, #blizzIcons do blizzIcons[i] = nil end

    table.sort(blizzIcons, SortBlizzChildren)

    local icons = cdmBarIcons[barKey]

    -- Ensure we have enough icon frames
    while #icons < #blizzIcons do
        local newIcon = CreateCDMIcon(barKey, #icons + 1)
        icons[#icons + 1] = newIcon
    end

    local desatOnCD = barData.desaturateOnCD
    local showCharges = barData.showCharges
    local swAlpha = barData.swipeAlpha or 0.7
    local activeAnim = barData.activeStateAnim or "blizzard"
    -- Active animation color: class color or custom, full alpha
    local animR, animG, animB = 1.0, 0.85, 0.0
    if barData.activeAnimClassColor then
        local _, ct = UnitClass("player")
        if ct then local cc = RAID_CLASS_COLORS[ct]; if cc then animR, animG, animB = cc.r, cc.g, cc.b end end
    elseif barData.activeAnimR then
        animR = barData.activeAnimR; animG = barData.activeAnimG or 0.85; animB = barData.activeAnimB or 0.0
    end

    -- Update each icon to mirror the Blizzard CDM icon
    for i, blizzIcon in ipairs(blizzIcons) do
        local ourIcon = icons[i]
        if ourIcon then
            -- Store mapping so proc glow hooks can find our icon from the Blizzard child
            ourIcon._blizzChild = blizzIcon

            -- Copy the icon texture
            local blizzTex = blizzIcon.Icon
            if blizzTex then
                local texPath = blizzTex:GetTexture()
                if texPath then
                    ourIcon._tex:SetTexture(texPath)
                end
            end

            -- Resolve spell ID from Blizzard CDM child
            local blizzCdID = blizzIcon.cooldownID
            if not blizzCdID and blizzIcon.cooldownInfo then
                blizzCdID = blizzIcon.cooldownInfo.cooldownID
            end
            local resolvedSid
            if blizzCdID then
                local cdViewerInfo = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
                    and C_CooldownViewer.GetCooldownViewerCooldownInfo(blizzCdID)
                if cdViewerInfo then
                    resolvedSid = cdViewerInfo.overrideSpellID or cdViewerInfo.spellID
                end
            end

            -- Detect aura/active state
            local isAura = blizzIcon.wasSetFromAura == true or blizzIcon.auraInstanceID ~= nil
            local auraHandled = false

            if isAura and activeAnim ~= "hideActive" then
                -- Aura active: get countdown from C_UnitAuras
                local auraID = blizzIcon.auraInstanceID
                if auraID then
                    local unit = blizzIcon.auraDataUnit or "player"
                    local ok, auraDurObj = pcall(C_UnitAuras.GetAuraDuration, unit, auraID)
                    if ok and auraDurObj then
                        ourIcon._cooldown:Clear()
                        pcall(ourIcon._cooldown.SetCooldownFromDurationObject, ourIcon._cooldown, auraDurObj, true)
                        ourIcon._cooldown:SetReverse(false)
                        auraHandled = true
                    end
                end
            end

            -- Spell cooldown + desaturation (uses shared helper)
            if resolvedSid and resolvedSid > 0 then
                ApplySpellCooldown(ourIcon, resolvedSid, desatOnCD, showCharges, swAlpha, auraHandled)
            else
                if desatOnCD and ourIcon._lastDesat then
                    ourIcon._tex:SetDesaturation(0)
                    ourIcon._lastDesat = false
                end
                ourIcon._chargeText:Hide()
            end

            -- Active state animation (consolidated)
            ApplyActiveAnimation(ourIcon, auraHandled, barData, barKey, activeAnim, animR, animG, animB, swAlpha)

            -- Stack count text (consolidated — always enabled)
            ApplyStackCount(ourIcon, resolvedSid, blizzIcon.auraInstanceID, blizzIcon.auraDataUnit, true, blizzIcon)

            ourIcon:Show()

            -- Hide buff icons when inactive (aura not active) ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â buff bars only
            -- Skip during unlock mode so the bar is fully visible for repositioning
            local isBuffBar = (barKey == "buffs" or barData.barType == "buffs")
            if barData.hideBuffsWhenInactive and isBuffBar and not EllesmereUI._unlockActive then
                if not blizzIcon.auraInstanceID then
                    ourIcon:Hide()
                end
            end
        end
    end

    -- Hide excess icons (with grace period to avoid blink at end of cast)
    for i = #blizzIcons + 1, #icons do
        local ic = icons[i]
        ic._blizzChild = nil
        if ic._procGlowActive then
            StopNativeGlow(ic._glowOverlay)
            ic._procGlowActive = false
        end
        if ic:IsShown() then
            if not ic._hideGraceStart then
                ic._hideGraceStart = GetTime()
            end
            if (GetTime() - ic._hideGraceStart) >= 0.5 then
                ic:Hide()
            end
        end
    end
    -- Clear grace on visible icons
    for i = 1, #blizzIcons do
        if icons[i] then icons[i]._hideGraceStart = nil end
    end

    -- Only re-layout when visible count changes
    -- Count includes grace-period icons still showing
    local visCount = 0
    for i = 1, #icons do
        if icons[i]:IsShown() then visCount = visCount + 1 end
    end
    if visCount ~= (frame._prevVisibleCount or 0) then
        frame._prevVisibleCount = visCount
        LayoutCDMBar(barKey)
    end
end

-------------------------------------------------------------------------------
--  CDM Bar Update Tick (mirrors Blizzard CDM state to our bars)
-------------------------------------------------------------------------------
local cdmUpdateThrottle = 0
local CDM_UPDATE_INTERVAL = 0.1  -- 10fps

-- Refresh visual properties of existing icons (called when settings change)
local function RefreshCDMIconAppearance(barKey)
    local icons = cdmBarIcons[barKey]
    if not icons then return end

    local barData = barDataByKey[barKey]
    if not barData then return end

    local barScale = barData.barScale or 1.0
    if barScale < 0.1 then barScale = 1.0 end
    local borderSize = SnapForScale(barData.borderSize or 1, barScale)
    local zoom = barData.iconZoom or 0.08

    for _, icon in ipairs(icons) do
        -- Update texture zoom
        if icon._tex then
            icon._tex:ClearAllPoints()
            icon._tex:SetPoint("TOPLEFT", icon, "TOPLEFT", borderSize, -borderSize)
            icon._tex:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -borderSize, borderSize)
            icon._tex:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
        end
        -- Update cooldown inset
        if icon._cooldown then
            icon._cooldown:ClearAllPoints()
            icon._cooldown:SetPoint("TOPLEFT", icon, "TOPLEFT", borderSize, -borderSize)
            icon._cooldown:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -borderSize, borderSize)
            icon._cooldown:SetSwipeColor(0, 0, 0, barData.swipeAlpha or 0.7)
            icon._cooldown:SetHideCountdownNumbers(not barData.showCooldownText)
            -- Mark pending font update (applied in batch after frame renders)
            if barData.showCooldownText then
                icon._pendingFontPath = GetCDMFont(); icon._pendingFontSize = barData.cooldownFontSize or 15
            end
        end
        -- Update border edges
        if icon._edges then
            for _, e in ipairs(icon._edges) do
                e:SetColorTexture(barData.borderR or 0, barData.borderG or 0, barData.borderB or 0, barData.borderA or 1)
                PP.DisablePixelSnap(e)
            end
            icon._edges[1]:SetHeight(borderSize)
            icon._edges[2]:SetHeight(borderSize)
            icon._edges[3]:SetWidth(borderSize)
            icon._edges[4]:SetWidth(borderSize)
        end
        -- Update background
        if icon._bg then
            icon._bg:SetColorTexture(barData.bgR or 0.08, barData.bgG or 0.08, barData.bgB or 0.08, barData.bgA or 0.6)
            PP.DisablePixelSnap(icon._bg)
        end
        -- Update charge text font/position
        if icon._chargeText then
            icon._chargeText:SetFont(GetCDMFont(), barData.stackCountSize or 11, "OUTLINE")
            icon._chargeText:ClearAllPoints()
            icon._chargeText:SetPoint("BOTTOMRIGHT", barData.stackCountX or 0, (barData.stackCountY or 0) + 2)
        end
        -- Update stack count text font/position/color
        if icon._stackText then
            icon._stackText:SetFont(GetCDMFont(), barData.stackCountSize or 11, "OUTLINE")
            icon._stackText:ClearAllPoints()
            icon._stackText:SetPoint("BOTTOMRIGHT", barData.stackCountX or 0, (barData.stackCountY or 0) + 2)
            icon._stackText:SetTextColor(barData.stackCountR or 1, barData.stackCountG or 1, barData.stackCountB or 1)
        end

        -- Update keybind text style
        if icon._keybindText then
            icon._keybindText:SetFont(GetCDMFont(), barData.keybindSize or 10, "OUTLINE")
            icon._keybindText:ClearAllPoints()
            icon._keybindText:SetPoint("TOPLEFT", icon._textOverlay, "TOPLEFT", barData.keybindOffsetX or 2, barData.keybindOffsetY or -2)
            icon._keybindText:SetTextColor(barData.keybindR or 1, barData.keybindG or 1, barData.keybindB or 1, barData.keybindA or 0.9)
        end

        -- Update tooltip overlay mouse state
        if icon._tooltipOverlay then
            icon._tooltipOverlay:EnableMouse(false)
        end
        -- Apply custom shape (overrides border/zoom set above)
        local shape = barData.iconShape or "none"
        ApplyShapeToCDMIcon(icon, shape, barData)

        -- Reset active state so glow type change takes effect on next tick
        if icon._glowOverlay then
            StopNativeGlow(icon._glowOverlay)
        end
        icon._isActive = false
        icon._procGlowActive = false
    end
end
ns.RefreshCDMIconAppearance = RefreshCDMIconAppearance

-------------------------------------------------------------------------------
--  Snapshot Blizzard CDM ? populate trackedSpells for a default bar
--  Called once per bar when trackedSpells is nil/empty.
--  Reads the Blizzard viewer children to get cooldownIDs in display order.
-------------------------------------------------------------------------------
local function SnapshotBlizzardCDM(barKey, barData)
    local blizzName = BLIZZ_CDM_FRAMES[barKey]
    if not blizzName then return end
    local blizzFrame = _G[blizzName]
    if not blizzFrame then return end

    local blizzIcons = {}
    for i = 1, blizzFrame:GetNumChildren() do
        local child = select(i, blizzFrame:GetChildren())
        if child and child.Icon then
            blizzIcons[#blizzIcons + 1] = child
        end
    end

    table.sort(blizzIcons, SortBlizzChildren)

    local tracked = {}
    for _, child in ipairs(blizzIcons) do
        local cdID = child.cooldownID
        if not cdID and child.cooldownInfo then
            cdID = child.cooldownInfo.cooldownID
        end
        if cdID then
            tracked[#tracked + 1] = cdID
        end
    end

    barData.trackedSpells = tracked
    return #tracked > 0
end
ns.SnapshotBlizzardCDM = SnapshotBlizzardCDM

-------------------------------------------------------------------------------
--  Update a self-managed bar using trackedSpells (cooldownIDs)
--  Finds matching Blizzard CDM children to mirror state (secret-safe).
--  Falls back to C_CooldownViewer API for icon texture.
-------------------------------------------------------------------------------
local function UpdateTrackedBarIcons(barKey)
    local frame = cdmBarFrames[barKey]
    if not frame then return end

    local barData = barDataByKey[barKey]
    if not barData or not barData.enabled then return end

    local tracked = barData.trackedSpells
    if not tracked or #tracked == 0 then return end

    -- Cache Blizzard CDM children lookup per bar (rebuild when child count changes
    -- or when a tracked cdID is missing from the cache)
    local blizzName = BLIZZ_CDM_FRAMES[barKey]
    local blizzFrame = blizzName and _G[blizzName]
    local cache = frame._blizzCache
    local childCount = blizzFrame and blizzFrame:GetNumChildren() or 0

    if not cache or cache._childCount ~= childCount then
        cache = {}
        cache._childCount = childCount
        if blizzFrame then
            for ci = 1, childCount do
                local child = select(ci, blizzFrame:GetChildren())
                if child then
                    local cdID = child.cooldownID
                    if not cdID and child.cooldownInfo then
                        cdID = child.cooldownInfo.cooldownID
                    end
                    if cdID then cache[cdID] = child end
                end
            end
        end
        frame._blizzCache = cache
    end

    local icons = cdmBarIcons[barKey]
    local desatOnCD = barData.desaturateOnCD
    local showCharges = barData.showCharges
    local swAlpha = barData.swipeAlpha or 0.7
    local activeAnim = barData.activeStateAnim or "blizzard"
    -- Active animation color: class color or custom, full alpha
    local animR, animG, animB = 1.0, 0.85, 0.0
    if barData.activeAnimClassColor then
        local _, ct = UnitClass("player")
        if ct then local cc = RAID_CLASS_COLORS[ct]; if cc then animR, animG, animB = cc.r, cc.g, cc.b end end
    elseif barData.activeAnimR then
        animR = barData.activeAnimR; animG = barData.activeAnimG or 0.85; animB = barData.activeAnimB or 0.0
    end
    local prevCount = frame._prevVisibleCount or 0
    local visCount = 0
    local cacheRebuiltThisTick = false

    -- Ensure we have enough icon frames
    while #icons < #tracked do
        local newIcon = CreateCDMIcon(barKey, #icons + 1)
        icons[#icons + 1] = newIcon
    end

    for i, cdID in ipairs(tracked) do
        local ourIcon = icons[i]
        if not ourIcon then break end

        local blizzChild = cache[cdID]
        -- If not found in cache, rebuild once per tick and retry
        -- may have recycled children without changing the total count.
        if not blizzChild and not cacheRebuiltThisTick then
            cacheRebuiltThisTick = true
            cache = {}
            cache._childCount = blizzFrame and blizzFrame:GetNumChildren() or 0
            if blizzFrame then
                for ci = 1, cache._childCount do
                    local child = select(ci, blizzFrame:GetChildren())
                    if child then
                        local rebuildCdID = child.cooldownID
                        if not rebuildCdID and child.cooldownInfo then
                            rebuildCdID = child.cooldownInfo.cooldownID
                        end
                        if rebuildCdID then cache[rebuildCdID] = child end
                    end
                end
            end
            frame._blizzCache = cache
            blizzChild = cache[cdID]
        end
        if blizzChild then
            ourIcon._hideGraceStart = nil
            ourIcon._blizzChild = blizzChild
            -- Mirror texture from Blizzard child
            local blizzTex = blizzChild.Icon
            if blizzTex then
                local texPath = blizzTex:GetTexture()
                if texPath then
                    ourIcon._tex:SetTexture(texPath)
                end
            end

            -- Resolve cdID ? real spellID for C_Spell APIs
            local resolvedSid
            local cdViewerInfo = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
                and C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
            if cdViewerInfo then
                resolvedSid = cdViewerInfo.overrideSpellID or cdViewerInfo.spellID
            end

            -- Detect aura/active state
            local isAura = blizzChild.wasSetFromAura == true or blizzChild.auraInstanceID ~= nil
            local auraHandled = false

            if isAura and activeAnim ~= "hideActive" then
                local auraID = blizzChild.auraInstanceID
                if auraID then
                    local unit = blizzChild.auraDataUnit or "player"
                    local ok, auraDurObj = pcall(C_UnitAuras.GetAuraDuration, unit, auraID)
                    if ok and auraDurObj then
                        ourIcon._cooldown:Clear()
                        pcall(ourIcon._cooldown.SetCooldownFromDurationObject, ourIcon._cooldown, auraDurObj, true)
                        ourIcon._cooldown:SetReverse(false)
                        auraHandled = true
                    end
                end
            end

            -- Spell cooldown, desaturation, and charge text (uses shared helper)
            if resolvedSid and resolvedSid > 0 then
                ourIcon._spellID = resolvedSid
                -- Apply cached keybind for this spell if not already set
                if ourIcon._keybindText and barData.showKeybind then
                    local cachedKey = _cdmKeybindCache[resolvedSid]
                    if not cachedKey then
                        local n = C_Spell.GetSpellName and C_Spell.GetSpellName(resolvedSid)
                        if n then cachedKey = _cdmKeybindCache[n] end
                    end
                    if cachedKey then
                        ourIcon._keybindText:SetText(cachedKey)
                        ourIcon._keybindText:Show()
                    elseif ourIcon._keybindText:IsShown() then
                        ourIcon._keybindText:Hide()
                    end
                end
                ApplySpellCooldown(ourIcon, resolvedSid, desatOnCD, showCharges, swAlpha, auraHandled)
            else
                if desatOnCD and ourIcon._lastDesat then
                    ourIcon._tex:SetDesaturation(0)
                    ourIcon._lastDesat = false
                end
                ourIcon._chargeText:Hide()
            end

            -- Active state animation (consolidated)
            ApplyActiveAnimation(ourIcon, auraHandled, barData, barKey, activeAnim, animR, animG, animB, swAlpha)

            -- Stack count text (consolidated — always enabled)
            ApplyStackCount(ourIcon, resolvedSid, blizzChild.auraInstanceID, blizzChild.auraDataUnit, true, blizzChild)

            ourIcon:Show()

            -- Hide buff icons when inactive (aura not active) ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â buff bars only
            -- Skip during unlock mode so the bar is fully visible for repositioning
            local isBuffBar = (barKey == "buffs" or barData.barType == "buffs")
            if barData.hideBuffsWhenInactive and isBuffBar and not EllesmereUI._unlockActive then
                if not blizzChild.auraInstanceID then
                    ourIcon:Hide()
                else
                    visCount = visCount + 1
                end
            else
                visCount = visCount + 1
            end
        else
            -- No Blizzard child in cache ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â API fallback, always keep visible
            ourIcon._hideGraceStart = nil
            ourIcon._blizzChild = nil
            if ourIcon._procGlowActive then
                StopNativeGlow(ourIcon._glowOverlay)
                ourIcon._procGlowActive = false
            end
            local cdViewInfo = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
                and C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
            if cdViewInfo then
                local sid = cdViewInfo.overrideSpellID or cdViewInfo.spellID
                if sid and sid > 0 then
                    local tex = C_Spell.GetSpellTexture(sid)
                    if tex then ourIcon._tex:SetTexture(tex) end

                    ApplySpellCooldown(ourIcon, sid, desatOnCD, false, swAlpha, false)

                    if ourIcon._isActive then
                        ourIcon._cooldown:SetSwipeColor(0, 0, 0, swAlpha)
                        if ourIcon._glowOverlay and not ourIcon._procGlowActive then
                            StopNativeGlow(ourIcon._glowOverlay)
                        end
                        ourIcon._isActive = false
                    end
                end
            end
            ourIcon._chargeText:Hide()
            ourIcon:Show()
            visCount = visCount + 1
        end
    end

    -- Hide excess icons
    local totalSlots = #tracked
    -- Process extraSpells (trinkets/racials/potions on default bars)
    local extras = barData.extraSpells
    if extras and #extras > 0 then
        -- Ensure enough icon frames for tracked + extras
        while #icons < #tracked + #extras do
            local newIcon = CreateCDMIcon(barKey, #icons + 1)
            icons[#icons + 1] = newIcon
        end
        for ei, extraID in ipairs(extras) do
            local idx = #tracked + ei
            local ourIcon = icons[idx]
            if ourIcon then
                if extraID < 0 then
                    -- Trinket slot
                    local slot = -extraID
                    local itemID = GetInventoryItemID("player", slot)
                    if itemID then
                        local tex = C_Item.GetItemIconByID(itemID)
                        if tex and tex ~= ourIcon._lastTex then
                            ourIcon._tex:SetTexture(tex)
                            ourIcon._lastTex = tex
                        end
                        ApplyTrinketCooldown(ourIcon, slot, desatOnCD)
                        ourIcon:Show()
                        visCount = visCount + 1
                    else
                        ourIcon:Hide()
                    end
                else
                    -- Spell-based extra (racial / potion)
                    local spellInfo = C_Spell.GetSpellInfo(extraID)
                    if spellInfo then
                        local texID = spellInfo.iconID
                        if texID ~= ourIcon._lastTex then
                            ourIcon._tex:SetTexture(texID)
                            ourIcon._lastTex = texID
                        end
                        ApplySpellCooldown(ourIcon, extraID, desatOnCD, false, swAlpha, false)
                        ourIcon:Show()
                        visCount = visCount + 1
                    else
                        ourIcon:Hide()
                    end
                end
            end
        end
        totalSlots = #tracked + #extras
    end

    for i = totalSlots + 1, #icons do
        local ic = icons[i]
        ic._blizzChild = nil
        if ic._procGlowActive then
            StopNativeGlow(ic._glowOverlay)
            ic._procGlowActive = false
        end
        ic:Hide()
    end

    -- Only re-layout when visible count changes
    if visCount ~= prevCount then
        frame._prevVisibleCount = visCount
        LayoutCDMBar(barKey)
    end
end
ns.UpdateTrackedBarIcons = UpdateTrackedBarIcons

local function UpdateAllCDMBars(dt)
    cdmUpdateThrottle = cdmUpdateThrottle + dt
    if cdmUpdateThrottle < CDM_UPDATE_INTERVAL then return end
    cdmUpdateThrottle = 0

    -- Wipe per-tick caches (GCD, charges, auras)
    wipe(_tickGCDCache)
    wipe(_tickChargeCache)
    wipe(_tickAuraCache)

    local p = ECME.db.profile
    if not p.cdmBars.enabled then return end

    for _, barData in ipairs(p.cdmBars.bars) do
        if barData.enabled then
            if BLIZZ_CDM_FRAMES[barData.key] then
                -- Default bar: use tracked spells if snapshotted, otherwise mirror Blizzard
                -- trackedSpells == nil means never snapshotted; empty table means user cleared all
                if barData.trackedSpells then
                    UpdateTrackedBarIcons(barData.key)
                else
                    -- Try to snapshot from Blizzard CDM
                    if SnapshotBlizzardCDM(barData.key, barData) then
                        UpdateTrackedBarIcons(barData.key)
                    else
                        -- Blizzard CDM not ready yet, fall back to mirror
                        UpdateCDMBarIcons(barData.key)
                    end
                end
            elseif barData.customSpells then
                -- Custom bar: track spells directly
                UpdateCustomBarIcons(barData.key)
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Bar Visibility (always / in combat / mouseover / never) + Housing
-------------------------------------------------------------------------------
local _cdmHoverStates = {}  -- [barKey] = { isHovered=false, fadeDir=nil }

local function _CDMFadeTo(frame, toAlpha, duration)
    if not frame._cdmFadeAG then
        frame._cdmFadeAG = frame:CreateAnimationGroup()
        frame._cdmFadeAG:SetLooping("NONE")
        frame._cdmFadeAnim = frame._cdmFadeAG:CreateAnimation("Alpha")
        frame._cdmFadeAG:SetScript("OnFinished", function()
            frame:SetAlpha(frame._cdmFadeAG._toAlpha or toAlpha)
        end)
    end
    local ag = frame._cdmFadeAG
    local anim = frame._cdmFadeAnim
    if ag:IsPlaying() then ag:Stop() end
    ag._toAlpha = toAlpha
    anim:SetFromAlpha(frame:GetAlpha())
    anim:SetToAlpha(toAlpha)
    anim:SetDuration(duration or 0.15)
    anim:SetStartDelay(0)
    ag:Restart()
end

local function _CDMStopFade(frame)
    if frame._cdmFadeAG and frame._cdmFadeAG:IsPlaying() then
        frame._cdmFadeAG:Stop()
        frame._cdmFadeAG._toAlpha = nil
    end
end

local function _CDMAttachHoverHooks(barKey)
    local frame = cdmBarFrames[barKey]
    if not frame or frame._cdmHoverHooked then return end
    frame._cdmHoverHooked = true

    local state = _cdmHoverStates[barKey]
    if not state then
        state = { isHovered = false, fadeDir = nil }
        _cdmHoverStates[barKey] = state
    end

    local function OnEnter()
        state.isHovered = true
        local p = ECME.db and ECME.db.profile
        local barData = p and GetBarData(barKey)
        if barData and (barData.barVisibility or "always") == "mouseover" and state.fadeDir ~= "in" then
            state.fadeDir = "in"
            _CDMStopFade(frame)
            _CDMFadeTo(frame, barData.barBgAlpha or 1, 0.15)
        end
    end

    local function OnLeave()
        state.isHovered = false
        C_Timer.After(0.1, function()
            if state.isHovered then return end
            local p = ECME.db and ECME.db.profile
            local barData = p and GetBarData(barKey)
            if barData and (barData.barVisibility or "always") == "mouseover" and state.fadeDir ~= "out" then
                state.fadeDir = "out"
                _CDMFadeTo(frame, 0, 0.15)
            end
        end)
    end

    frame:HookScript("OnEnter", OnEnter)
    frame:HookScript("OnLeave", OnLeave)
    -- Also hook child icons
    local icons = cdmBarIcons[barKey]
    if icons then
        for _, icon in ipairs(icons) do
            if icon and not icon._cdmHoverHooked then
                icon._cdmHoverHooked = true
                icon:HookScript("OnEnter", OnEnter)
                icon:HookScript("OnLeave", OnLeave)
            end
        end
    end
end

local function _CDMApplyVisibility()
    local p = ECME.db and ECME.db.profile
    if not p then return end
    local inCombat = _inCombat
    -- Housing detection
    local inHousing = false
    if C_Map and C_Map.GetBestMapForUnit then
        local mapID = C_Map.GetBestMapForUnit("player")
        inHousing = mapID and mapID > 2600
    end

    for _, barData in ipairs(p.cdmBars.bars) do
        local frame = cdmBarFrames[barData.key]
        if frame then
            local vis = barData.barVisibility or "always"
            local hideHousing = barData.housingHideEnabled ~= false

            if hideHousing and inHousing then
                _CDMStopFade(frame)
                frame:SetAlpha(0)
                if frame.EnableMouseMotion then frame:EnableMouseMotion(false) end
            elseif vis == "never" then
                _CDMStopFade(frame)
                frame:SetAlpha(0)
                if frame.EnableMouseMotion then frame:EnableMouseMotion(false) end
            elseif vis == "in_combat" then
                _CDMStopFade(frame)
                if inCombat then
                    frame:SetAlpha(barData.barBgAlpha or 1)
                    if frame.EnableMouseMotion then frame:EnableMouseMotion(true) end
                else
                    frame:SetAlpha(0)
                    if frame.EnableMouseMotion then frame:EnableMouseMotion(false) end
                end
            elseif vis == "mouseover" then
                _CDMAttachHoverHooks(barData.key)
                local state = _cdmHoverStates[barData.key]
                if not state or not state.isHovered then
                    _CDMStopFade(frame)
                    frame:SetAlpha(0)
                    if frame.EnableMouseMotion then frame:EnableMouseMotion(true) end
                end
            else -- "always"
                _CDMStopFade(frame)
                frame:SetAlpha(barData.barBgAlpha or 1)
                if frame.EnableMouseMotion then frame:EnableMouseMotion(true) end
            end
        end
    end
end
ns.CDMApplyVisibility = _CDMApplyVisibility

-- Helper to get barData by key
function GetBarData(barKey)
    return barDataByKey[barKey]
end



-------------------------------------------------------------------------------
--  Build all CDM bars
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
--  Keybind cache for CDM icons
--  Built once out-of-combat by scanning all action bar slots.
--  Stored as { [spellID] = "formatted key" } so icon display is just a lookup.
--  Deferred if called during combat; fires on PLAYER_REGEN_ENABLED instead.
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
--  Keybind cache for CDM icons
--  Reads HotKey text directly from action button frames — the same source
--  the action bar itself uses, so it's always correct regardless of bar addon.
--  Deferred if called during combat; fires on PLAYER_REGEN_ENABLED instead.
-------------------------------------------------------------------------------

-- Action bar slot → binding name map. Non-bar-1 entries listed first so that
-- if a spell appears on multiple bars, the more specific bar wins over bar 1.
local _barBindingDefs = {
    { prefix = "MULTIACTIONBAR1BUTTON", startSlot = 61  },  -- bar 2 bottom left
    { prefix = "MULTIACTIONBAR2BUTTON", startSlot = 49  },  -- bar 3 bottom right
    { prefix = "MULTIACTIONBAR3BUTTON", startSlot = 25  },  -- bar 4 right
    { prefix = "MULTIACTIONBAR4BUTTON", startSlot = 37  },  -- bar 5 left
    { prefix = "MULTIACTIONBAR5BUTTON", startSlot = 145 },  -- bar 6
    { prefix = "MULTIACTIONBAR6BUTTON", startSlot = 157 },  -- bar 7
    { prefix = "MULTIACTIONBAR7BUTTON", startSlot = 169 },  -- bar 8
    { prefix = "ACTIONBUTTON",          startSlot = 1   },  -- bar 1 (last = lowest priority)
}

local function FormatKeybindKey(key)
    if not key or key == "" then return nil end
    key = key:gsub("SHIFT%-", "S")
    key = key:gsub("CTRL%-",  "C")
    key = key:gsub("ALT%-",   "A")
    key = key:gsub("Mouse Button ", "M")
    key = key:gsub("MOUSEWHEELUP",   "MwU")
    key = key:gsub("MOUSEWHEELDOWN", "MwD")
    key = key:gsub("NUMPADDECIMAL",  "N.")
    key = key:gsub("NUMPADPLUS",     "N+")
    key = key:gsub("NUMPADMINUS",    "N-")
    key = key:gsub("NUMPADMULTIPLY", "N*")
    key = key:gsub("NUMPADDIVIDE",   "N/")
    key = key:gsub("NUMPAD",         "N")
    key = key:gsub("BUTTON",         "M")
    return key ~= "" and key or nil
end

local function RebuildKeybindCache()
    wipe(_cdmKeybindCache)
    for _, def in ipairs(_barBindingDefs) do
        for i = 1, 12 do
            local bindName = def.prefix .. i
            local key = GetBindingKey(bindName)
            if key then
                local slot = def.startSlot + i - 1
                local slotType, id = GetActionInfo(slot)
                local spellID
                if slotType == "spell" then
                    spellID = id
                elseif slotType == "macro" and id then
                    -- GetMacroSpell works for macro-index based entries.
                    -- For direct spell macros, GetActionInfo returns the spell ID as id.
                    local macroSpell = GetMacroSpell(id)
                    spellID = macroSpell or (id > 0 and id) or nil
                end
                if spellID then
                    local formatted = FormatKeybindKey(key)
                    if not _cdmKeybindCache[spellID] then
                        _cdmKeybindCache[spellID] = formatted
                    end
                    local name = C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
                    if name and not _cdmKeybindCache[name] then
                        _cdmKeybindCache[name] = formatted
                    end
                end
            end
        end
    end
end

-- Apply the current cache to all visible CDM icon keybind texts
local function ApplyCachedKeybinds()
    for barKey, icons in pairs(cdmBarIcons) do
        local bd = barDataByKey[barKey]
        for _, icon in ipairs(icons) do
            if icon._keybindText then
                if bd and bd.showKeybind and icon._spellID then
                    local key = _cdmKeybindCache[icon._spellID]
                    local name = C_Spell.GetSpellName and C_Spell.GetSpellName(icon._spellID)
                    if not key and name then key = _cdmKeybindCache[name] end
                    if key then
                        icon._keybindText:SetText(key)
                        icon._keybindText:Show()
                    else
                        icon._keybindText:Hide()
                    end
                else
                    icon._keybindText:Hide()
                end
            end
        end
    end
end

-- Public entry point: rebuild cache then apply. Defers if in combat.
local function UpdateCDMKeybinds()
    if _inCombat then
        _keybindRebuildPending = true
        return
    end
    _keybindRebuildPending = false
    RebuildKeybindCache()
    _keybindCacheReady = true
    -- Defer apply by one frame so the Blizzard tick has populated icon._spellID
    C_Timer.After(0, ApplyCachedKeybinds)
end
ns.UpdateCDMKeybinds = UpdateCDMKeybinds
-- Expose apply-only for the tick loop (new spellID assigned to an icon mid-session)
ns.ApplyCachedKeybinds = ApplyCachedKeybinds
ns.CDMKeybindCache = _cdmKeybindCache

BuildAllCDMBars = function()
    -- Last-resort spec guard: if we're about to build bars with wrong spec, fix it
    if not _specValidated then
        ValidateSpec()
    end

    local p = ECME.db.profile
    if not p.cdmBars.enabled then
        -- Restore Blizzard CDM if we're disabled
        RestoreBlizzardCDM()
        for key, frame in pairs(cdmBarFrames) do
            frame:Hide()
        end
        return
    end

    -- Hide Blizzard CDM
    if p.cdmBars.hideBlizzard then
        HideBlizzardCDM()
    end

    -- Build each bar and populate fast lookup
    wipe(barDataByKey)
    for i, barData in ipairs(p.cdmBars.bars) do
        barDataByKey[barData.key] = barData
        BuildCDMBar(i)
        RefreshCDMIconAppearance(barData.key)
        local frame = cdmBarFrames[barData.key]
        if frame then frame._prevVisibleCount = nil end
        LayoutCDMBar(barData.key)
    end
    _CDMApplyVisibility()
    UpdateCDMKeybinds()

    -- Batch-apply pending cooldown font styling (single deferred call, no per-icon closures)
    C_Timer.After(0, function()
        for _, icons in pairs(cdmBarIcons) do
            for _, icon in ipairs(icons) do
                if icon._pendingFontPath and icon._cooldown then
                    local fontPath, fontSize = icon._pendingFontPath, icon._pendingFontSize
                    for ri = 1, icon._cooldown:GetNumRegions() do
                        local region = select(ri, icon._cooldown:GetRegions())
                        if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                            region:SetFont(fontPath, fontSize, "OUTLINE")
                            break
                        end
                    end
                    icon._pendingFontPath = nil; icon._pendingFontSize = nil
                end
            end
        end
    end)
end

-- Expose for options
ns.BuildAllCDMBars = BuildAllCDMBars
ns.cdmBarFrames = cdmBarFrames
ns.cdmBarIcons = cdmBarIcons
ns.barDataByKey = barDataByKey
ns.SaveCDMBarPosition = SaveCDMBarPosition
ns.LayoutCDMBar = LayoutCDMBar
ns.BLIZZ_CDM_FRAMES = BLIZZ_CDM_FRAMES
ns.CDM_BAR_CATEGORIES = CDM_BAR_CATEGORIES
ns.MAX_CUSTOM_BARS = MAX_CUSTOM_BARS
ns.FindPlayerPartyFrame = FindPlayerPartyFrame
ns.FindPlayerUnitFrame = FindPlayerUnitFrame
ns.UpdateCDMBarIcons = UpdateCDMBarIcons
ns.UpdateCustomBarIcons = UpdateCustomBarIcons
ns.RestoreBlizzardCDM = RestoreBlizzardCDM
ns.HideBlizzardCDM = HideBlizzardCDM

-------------------------------------------------------------------------------
--  Interactive Preview Helpers (used by options spell picker)
-------------------------------------------------------------------------------

--- Build list of trinket / racial / health-potion entries.
--- Returns array of { spellID, name, icon, isKnown=true, isExtra=true }.
--- spellID is negative for trinket slots (-13, -14).
local function GetExtraSpells()
    local extras = {}

    -- Trinket slots (dynamic ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â reads currently equipped item)
    for _, slot in ipairs({ TRINKET_SLOT_1, TRINKET_SLOT_2 }) do
        local itemID = GetInventoryItemID("player", slot)
        if itemID then
            local tex  = C_Item.GetItemIconByID(itemID)
            if tex then
                local label = (slot == TRINKET_SLOT_1) and "Trinket Slot 1" or "Trinket Slot 2"
                extras[#extras + 1] = {
                    spellID = -slot, cdID = nil,
                    name = label, icon = tex,
                    isKnown = true, isDisplayed = false, isExtra = true,
                }
            end
        end
    end

    -- Racial abilities for current player
    if _playerRace and RACE_RACIALS[_playerRace] then
        for _, entry in ipairs(RACE_RACIALS[_playerRace]) do
            local sid = type(entry) == "table" and entry[1] or entry
            local reqClass = type(entry) == "table" and entry.class or nil
            if (not reqClass or reqClass == _playerClass) then
                local ok, inBook = pcall(C_SpellBook.IsSpellInSpellBook, sid)
                if ok and inBook then
                    local sName = C_Spell.GetSpellName(sid)
                    local sTex  = C_Spell.GetSpellTexture(sid)
                    if sName then
                        extras[#extras + 1] = {
                            spellID = sid, cdID = nil,
                            name = sName, icon = sTex,
                            isKnown = true, isDisplayed = false, isExtra = true,
                        }
                    end
                end
            end
        end
    end

    -- Health potions / healthstones
    for _, item in ipairs(HEALTH_ITEMS) do
        if not item.class or item.class == _playerClass then
            local sName = C_Spell.GetSpellName(item.spellID)
            local sTex  = C_Item.GetItemIconByID(item.itemID)
            if sName then
                extras[#extras + 1] = {
                    spellID = item.spellID, cdID = nil,
                    name = sName, icon = sTex or C_Spell.GetSpellTexture(item.spellID),
                    isKnown = true, isDisplayed = false, isExtra = true,
                }
            end
        end
    end

    return extras
end
ns.GetExtraSpells = GetExtraSpells

--- Get all available CDM spells for a bar's categories.
--- Returns array of { cdID, spellID, name, icon, isDisplayed, isKnown [, isExtra] }
--- Sorted: displayed+known first, then known, then unlearned (desaturated).
function ns.GetCDMSpellsForBar(barKey)
    -- Resolve bar type for custom bars
    local barType
    local p = ECME.db.profile
    local bd = barDataByKey[barKey]
    if bd then barType = bd.barType end
    -- Default bars have implicit types
    if not barType then
        if barKey == "cooldowns" then barType = "cooldowns"
        elseif barKey == "utility" then barType = "utility"
        elseif barKey == "buffs" then barType = "buffs"
        end
    end

    -- Trinket/racial/potion bars: return only extras
    if barType == "trinkets" then
        local extras = GetExtraSpells()
        table.sort(extras, function(a, b) return a.name < b.name end)
        return extras
    end

    local cats = CDM_BAR_CATEGORIES[barKey]
        or CDM_BAR_CATEGORIES[barType or "cooldowns"]
        or { 0, 1 }

    -- Build set of displayed cooldownIDs (have a Blizzard child)
    local displayedSet = {}
    local blizzName = BLIZZ_CDM_FRAMES[barKey]
    if blizzName then
        local blizzFrame = _G[blizzName]
        if blizzFrame then
            for i = 1, blizzFrame:GetNumChildren() do
                local child = select(i, blizzFrame:GetChildren())
                if child then
                    local cdID = child.cooldownID
                    if not cdID and child.cooldownInfo then
                        cdID = child.cooldownInfo.cooldownID
                    end
                    if cdID then displayedSet[cdID] = true end
                end
            end
        end
    end

    local spells = {}
    local seen = {}
    for _, cat in ipairs(cats) do
        local allIDs = C_CooldownViewer.GetCooldownViewerCategorySet(cat, true) or {}
        local knownIDs = C_CooldownViewer.GetCooldownViewerCategorySet(cat, false) or {}
        local knownSet = {}
        for _, id in ipairs(knownIDs) do knownSet[id] = true end

        for _, cdID in ipairs(allIDs) do
            if not seen[cdID] then
                seen[cdID] = true
                local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
                if info then
                    local sid = info.overrideSpellID or info.spellID or 0
                    local name = sid > 0 and C_Spell.GetSpellName(sid) or nil
                    local tex = sid > 0 and C_Spell.GetSpellTexture(sid) or nil
                    if name then
                        spells[#spells + 1] = {
                            cdID = cdID,
                            spellID = sid,
                            name = name,
                            icon = tex,
                            isDisplayed = displayedSet[cdID] or false,
                            isKnown = knownSet[cdID] or false,
                        }
                    end
                end
            end
        end
    end

    -- Sort: known+displayed first, then known, then unlearned
    table.sort(spells, function(a, b)
        local aScore = (a.isKnown and 2 or 0) + (a.isDisplayed and 1 or 0)
        local bScore = (b.isKnown and 2 or 0) + (b.isDisplayed and 1 or 0)
        if aScore ~= bScore then return aScore > bScore end
        return a.name < b.name
    end)

    -- Append trinket/racial/potion extras only for the dedicated extras bar
    if barType == "trinkets" then
        local extras = GetExtraSpells()
        table.sort(extras, function(a, b) return a.name < b.name end)
        for _, ex in ipairs(extras) do
            spells[#spells + 1] = ex
        end
    end

    return spells
end

--- Check if a cooldownID has a Blizzard CDM child (is "displayed")
function ns.IsSpellDisplayedInCDM(barKey, cdID)
    local blizzName = BLIZZ_CDM_FRAMES[barKey]
    if not blizzName then return false end
    local blizzFrame = _G[blizzName]
    if not blizzFrame then return false end
    for i = 1, blizzFrame:GetNumChildren() do
        local child = select(i, blizzFrame:GetChildren())
        if child then
            local cid = child.cooldownID
            if not cid and child.cooldownInfo then
                cid = child.cooldownInfo.cooldownID
            end
            if cid == cdID then return true end
        end
    end
    return false
end

--- Swap two tracked spell positions
function ns.SwapTrackedSpells(barKey, idx1, idx2)
    local p = ECME.db.profile
    for _, b in ipairs(p.cdmBars.bars) do
        if b.key == barKey then
            if b.customSpells then
                local t = b.customSpells
                if t and idx1 >= 1 and idx2 >= 1 then
                    local maxIdx = math.max(idx1, idx2)
                    while #t < maxIdx do t[#t + 1] = 0 end
                    t[idx1], t[idx2] = t[idx2], t[idx1]
                    while #t > 0 and (t[#t] == 0 or t[#t] == nil) do t[#t] = nil end
                    local frame = cdmBarFrames[barKey]
                    if frame then frame._blizzCache = nil end
                    return true
                end
            else
                -- Default bar: build a combined virtual list of trackedSpells + extraSpells,
                -- swap by position, then split back by position (not by original src tag).
                -- Position determines list membership: slots 1..tLen are tracked, rest are extras.
                if not b.trackedSpells then b.trackedSpells = {} end
                if not b.extraSpells then b.extraSpells = {} end
                local tracked = b.trackedSpells
                local extras  = b.extraSpells
                local tLen = #tracked
                local eLen = #extras
                local total = tLen + eLen
                if idx1 < 1 or idx2 < 1 then return false end

                -- Pad tracked list if needed so blank grid slots are addressable
                local maxIdx = math.max(idx1, idx2)
                if maxIdx > total then
                    while #tracked < maxIdx do tracked[#tracked + 1] = 0 end
                    tLen = #tracked
                    total = tLen + eLen
                end

                -- Read values from their current lists
                local function getVal(i)
                    if i <= tLen then return tracked[i] else return extras[i - tLen] end
                end
                -- Write values back to the list determined by destination position
                local function setVal(i, v)
                    if i <= tLen then tracked[i] = v else extras[i - tLen] = v end
                end

                local v1 = getVal(idx1)
                local v2 = getVal(idx2)
                setVal(idx1, v2)
                setVal(idx2, v1)

                -- Trim trailing zeros
                while #tracked > 0 and (tracked[#tracked] == 0 or tracked[#tracked] == nil) do tracked[#tracked] = nil end
                while #extras  > 0 and (extras[#extras]   == 0 or extras[#extras]   == nil) do extras[#extras]   = nil end
                local frame = cdmBarFrames[barKey]
                if frame then frame._blizzCache = nil end
                return true
            end
        end
    end
    return false
end

--- Move a tracked spell from one position to another (insert, not swap)
function ns.MoveTrackedSpell(barKey, fromIdx, toIdx)
    if fromIdx == toIdx then return false end
    local p = ECME.db.profile
    for _, b in ipairs(p.cdmBars.bars) do
        if b.key == barKey then
            if b.customSpells then
                local t = b.customSpells
                if fromIdx < 1 or fromIdx > #t then return false end
                if toIdx < 1 then toIdx = 1 end
                -- Pad if moving to a blank grid slot
                while #t < toIdx do t[#t + 1] = 0 end
                local val = table.remove(t, fromIdx)
                table.insert(t, toIdx, val)
                while #t > 0 and (t[#t] == 0 or t[#t] == nil) do t[#t] = nil end
                local frame = cdmBarFrames[barKey]
                if frame then frame._blizzCache = nil end
                return true
            else
                if not b.trackedSpells then b.trackedSpells = {} end
                if not b.extraSpells then b.extraSpells = {} end
                local tracked = b.trackedSpells
                local extras = b.extraSpells
                local tLen = #tracked
                local eLen = #extras
                local total = tLen + eLen
                if fromIdx < 1 or fromIdx > total then return false end
                if toIdx < 1 then toIdx = 1 end
                -- Pad if moving to a blank grid slot beyond current count
                if toIdx > total then
                    while #tracked < toIdx do tracked[#tracked + 1] = 0 end
                    tLen = #tracked
                    total = tLen + eLen
                end
                -- Build combined list and move
                local combined = {}
                for i = 1, tLen do combined[i] = tracked[i] end
                for i = 1, eLen do combined[tLen + i] = extras[i] end
                local val = table.remove(combined, fromIdx)
                table.insert(combined, toIdx, val)
                -- Split back by position: first tLen slots go to trackedSpells, rest to extraSpells.
                -- tLen is fixed — the boundary doesn't move when items are reordered.
                b.trackedSpells = {}
                b.extraSpells = {}
                for i = 1, tLen do b.trackedSpells[i] = combined[i] end
                for i = tLen + 1, #combined do b.extraSpells[i - tLen] = combined[i] end
                while #b.trackedSpells > 0 and (b.trackedSpells[#b.trackedSpells] == 0 or b.trackedSpells[#b.trackedSpells] == nil) do b.trackedSpells[#b.trackedSpells] = nil end
                while #b.extraSpells  > 0 and (b.extraSpells[#b.extraSpells]   == 0 or b.extraSpells[#b.extraSpells]   == nil) do b.extraSpells[#b.extraSpells]   = nil end
                local frame = cdmBarFrames[barKey]
                if frame then frame._blizzCache = nil end
                return true
            end
        end
    end
    return false
end

--- Add a tracked spell (cooldownID or extra spellID) to a bar
--- When isExtra is true, id is a spellID (positive) or trinket slot (negative)
function ns.AddTrackedSpell(barKey, id, isExtra)
    local p = ECME.db.profile
    for _, b in ipairs(p.cdmBars.bars) do
        if b.key == barKey then
            if b.customSpells then
                local sid
                if isExtra then
                    sid = id
                else
                    local info = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
                        and C_CooldownViewer.GetCooldownViewerCooldownInfo(id)
                    if not info then return false end
                    sid = info.overrideSpellID or info.spellID or 0
                    if sid == 0 then return false end
                end
                for _, existing in ipairs(b.customSpells) do
                    if existing == sid then return false end
                end
                b.customSpells[#b.customSpells + 1] = sid
            elseif isExtra then
                -- Default bar: store extras in a separate list
                if not b.extraSpells then b.extraSpells = {} end
                for _, existing in ipairs(b.extraSpells) do
                    if existing == id then return false end
                end
                b.extraSpells[#b.extraSpells + 1] = id
            else
                if not b.trackedSpells then b.trackedSpells = {} end
                for _, existing in ipairs(b.trackedSpells) do
                    if existing == id then return false end
                end
                b.trackedSpells[#b.trackedSpells + 1] = id
            end
            local frame = cdmBarFrames[barKey]
            if frame then frame._blizzCache = nil; frame._prevVisibleCount = nil end
            return true
        end
    end
    return false
end

--- Remove a tracked spell by index
function ns.RemoveTrackedSpell(barKey, idx)
    local p = ECME.db.profile
    for _, b in ipairs(p.cdmBars.bars) do
        if b.key == barKey then
            if b.customSpells then
                local list = b.customSpells
                if list and idx >= 1 and idx <= #list then
                    table.remove(list, idx)
                    local frame = cdmBarFrames[barKey]
                    if frame then frame._blizzCache = nil; frame._prevVisibleCount = nil end
                    return true
                end
            else
                local tracked = b.trackedSpells or {}
                local extras  = b.extraSpells or {}
                if idx >= 1 and idx <= #tracked then
                    table.remove(tracked, idx)
                    local frame = cdmBarFrames[barKey]
                    if frame then frame._blizzCache = nil; frame._prevVisibleCount = nil end
                    return true
                elseif idx > #tracked and idx <= #tracked + #extras then
                    table.remove(extras, idx - #tracked)
                    local frame = cdmBarFrames[barKey]
                    if frame then frame._blizzCache = nil; frame._prevVisibleCount = nil end
                    return true
                end
            end
        end
    end
    return false
end

--- Replace a tracked spell at a given index with a new ID
--- When isExtra is true, newID is a spellID or trinket slot directly
function ns.ReplaceTrackedSpell(barKey, idx, newID, isExtra)
    local p = ECME.db.profile
    for _, b in ipairs(p.cdmBars.bars) do
        if b.key == barKey then
            if b.customSpells then
                local newSid
                if isExtra then
                    newSid = newID
                else
                    local info = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
                        and C_CooldownViewer.GetCooldownViewerCooldownInfo(newID)
                    if not info then return false end
                    newSid = info.overrideSpellID or info.spellID or 0
                    if newSid == 0 then return false end
                end
                local list = b.customSpells
                -- Extend array if replacing beyond current length
                while #list < idx do list[#list + 1] = 0 end
                if idx >= 1 then
                    for i, existing in ipairs(list) do
                        if existing == newSid and i ~= idx then
                            table.remove(list, i)
                            if i < idx then idx = idx - 1 end
                            break
                        end
                    end
                    list[idx] = newSid
                    -- Trim trailing zeros
                    while #list > 0 and (list[#list] == 0 or list[#list] == nil) do list[#list] = nil end
                    local frame = cdmBarFrames[barKey]
                    if frame then frame._blizzCache = nil; frame._prevVisibleCount = nil end
                    return true
                end
            else
                -- Default bar: determine if index falls in trackedSpells or extraSpells
                local tracked = b.trackedSpells or {}
                local extras  = b.extraSpells or {}
                if idx >= 1 and idx <= #tracked then
                    -- Replacing within trackedSpells
                    if isExtra then
                        -- Replacing a tracked spell with an extra: remove from tracked, add to extras
                        table.remove(tracked, idx)
                        if not b.extraSpells then b.extraSpells = {} end
                        local found = false
                        for _, ex in ipairs(b.extraSpells) do
                            if ex == newID then found = true; break end
                        end
                        if not found then b.extraSpells[#b.extraSpells + 1] = newID end
                    else
                        while #b.trackedSpells < idx do b.trackedSpells[#b.trackedSpells + 1] = 0 end
                        for i, existing in ipairs(b.trackedSpells) do
                            if existing == newID and i ~= idx then
                                table.remove(b.trackedSpells, i)
                                if i < idx then idx = idx - 1 end
                                break
                            end
                        end
                        b.trackedSpells[idx] = newID
                        while #b.trackedSpells > 0 and (b.trackedSpells[#b.trackedSpells] == 0 or b.trackedSpells[#b.trackedSpells] == nil) do b.trackedSpells[#b.trackedSpells] = nil end
                    end
                    local frame = cdmBarFrames[barKey]
                    if frame then frame._blizzCache = nil; frame._prevVisibleCount = nil end
                    return true
                elseif idx > #tracked and idx <= #tracked + #extras then
                    -- Replacing within extraSpells
                    local eIdx = idx - #tracked
                    if isExtra then
                        for i, existing in ipairs(extras) do
                            if existing == newID and i ~= eIdx then
                                table.remove(extras, i)
                                if i < eIdx then eIdx = eIdx - 1 end
                                break
                            end
                        end
                        extras[eIdx] = newID
                    else
                        -- Replacing an extra with a tracked spell: remove from extras, add to tracked
                        table.remove(extras, eIdx)
                        if not b.trackedSpells then b.trackedSpells = {} end
                        local found = false
                        for _, ex in ipairs(b.trackedSpells) do
                            if ex == newID then found = true; break end
                        end
                        if not found then b.trackedSpells[#b.trackedSpells + 1] = newID end
                    end
                    local frame = cdmBarFrames[barKey]
                    if frame then frame._blizzCache = nil; frame._prevVisibleCount = nil end
                    return true
                end
            end
        end
    end
    return false
end

-- Add a new custom CDM bar
function ns.AddCDMBar(barType, name, numRows)
    local p = ECME.db.profile
    local bars = p.cdmBars.bars
    -- Count existing custom bars (non-default)
    local customCount = 0
    for _, b in ipairs(bars) do
        if b.key ~= "cooldowns" and b.key ~= "utility" and b.key ~= "buffs" then
            customCount = customCount + 1
        end
    end
    if customCount >= MAX_CUSTOM_BARS then return nil end
    -- Determine bar type label for default name
    barType = barType or "cooldowns"
    local typeLabel = barType == "cooldowns" and "Cooldowns"
                   or barType == "utility" and "Utility"
                   or barType == "buffs" and "Buffs"
                   or barType == "trinkets" and "Trinkets/Racials/Potions"
                   or "Cooldowns"
    -- Count existing custom bars of this type for numbering
    local typeCount = 0
    for _, b in ipairs(bars) do
        if b.barType == barType then typeCount = typeCount + 1 end
    end
    local key = "custom_" .. (#bars + 1) .. "_" .. GetTime()
    key = key:gsub("%.", "_")
    bars[#bars + 1] = {
        key = key, name = name or ((barType == "trinkets" and "Miscellaneous " or "Custom " .. typeLabel .. " Bar ") .. (typeCount + 1)),
        barType = barType,
        enabled = true, barScale = 1.0, iconSize = 36, numRows = numRows or 1,
        spacing = 2,
        borderSize = 1, borderR = 0, borderG = 0, borderB = 0, borderA = 1,
        borderClassColor = false, borderThickness = "thin",
        bgR = 0.08, bgG = 0.08, bgB = 0.08, bgA = 0.6,
        iconZoom = 0.08, iconShape = "none", growDirection = "RIGHT",
        verticalOrientation = false, barBgEnabled = false, barBgAlpha = 1.0,
        barBgR = 0, barBgG = 0, barBgB = 0,
        showCooldownText = true, cooldownFontSize = 12,
        showCharges = true, chargeFontSize = 11,
        desaturateOnCD = true, swipeAlpha = 0.7,
        activeStateAnim = "blizzard",
        anchorTo = "none", anchorPosition = "left",
        anchorOffsetX = 0, anchorOffsetY = 0,
        barVisibility = "always", housingHideEnabled = true,
        hideBuffsWhenInactive = true,
        showStackCount = false, stackCountSize = 11,
        stackCountX = 0, stackCountY = 0,
        stackCountR = 1, stackCountG = 1, stackCountB = 1,
        -- Custom bars use a spell list instead of mirroring Blizzard
        customSpells = {},
    }
    BuildAllCDMBars()
    RegisterCDMUnlockElements()
    return key
end

-- Remove a custom CDM bar (only custom bars, not the 3 defaults)
function ns.RemoveCDMBar(key)
    if key == "cooldowns" or key == "utility" or key == "buffs" then return false end
    local p = ECME.db.profile
    for i, barData in ipairs(p.cdmBars.bars) do
        if barData.key == key then
            -- Clean up frame
            local frame = cdmBarFrames[key]
            if frame then frame:Hide() end
            cdmBarFrames[key] = nil
            cdmBarIcons[key] = nil
            p.cdmBarPositions[key] = nil
            table.remove(p.cdmBars.bars, i)
            -- Unregister from unlock mode
            if EllesmereUI and EllesmereUI.UnregisterUnlockElement then
                EllesmereUI:UnregisterUnlockElement("CDM_" .. key)
            end
            -- Re-register remaining bars to update linkedKeys
            RegisterCDMUnlockElements()
            return true
        end
    end
    return false
end

-------------------------------------------------------------------------------
--  CDM Bar: First Login Capture
-------------------------------------------------------------------------------
local function CDMFirstLoginCapture()
    local p = ECME.db.profile
    local captured = CaptureCDMPositions()

    for _, barData in ipairs(p.cdmBars.bars) do
        local cap = captured[barData.key]
        if cap then
            -- Bar scale: the Edit Mode frame scale (drag-handle).
            if cap.barScale then
                barData.barScale = cap.barScale
            end
            -- Icon size: visual size from child icon (base width * child scale).
            if cap.iconSize then
                barData.iconSize = cap.iconSize
            end
            -- Spacing (icon padding from Edit Mode setting)
            if cap.spacing then
                barData.spacing = cap.spacing
            end
            -- Rows (counted from distinct Y positions of visible icons)
            if cap.numRows then
                barData.numRows = cap.numRows
            end
            -- Orientation
            if cap.isHorizontal ~= nil then
                barData.growDirection = cap.isHorizontal and "RIGHT" or "DOWN"
                barData.verticalOrientation = not cap.isHorizontal
            end
            -- Position: divide by scale so SetScale() reproduces the
            -- original on-screen position exactly.
            if cap.point then
                local scale = barData.barScale or 1.0
                if scale < 0.1 then scale = 1.0 end
                p.cdmBarPositions[barData.key] = {
                    point = cap.point, relPoint = cap.relPoint,
                    x = cap.x / scale, y = cap.y / scale,
                }
            end
        end
    end

    p._capturedOnce = true
end

-------------------------------------------------------------------------------
--  Register CDM bars with unlock mode
-------------------------------------------------------------------------------
RegisterCDMUnlockElements = function()
    if not EllesmereUI or not EllesmereUI.RegisterUnlockElements then return end

    -- Build a lookup of which bars are anchored to which parent
    local anchorChildren = {}  -- parentKey -> { childKey1, childKey2, ... }
    for _, barData in ipairs(ECME.db.profile.cdmBars.bars) do
        local anchorKey = barData.anchorTo
        if anchorKey and anchorKey ~= "none" and anchorKey ~= "partyframe" and anchorKey ~= "playerframe" then
            if not anchorChildren[anchorKey] then anchorChildren[anchorKey] = {} end
            anchorChildren[anchorKey][#anchorChildren[anchorKey] + 1] = barData.key
        end
    end

    local elements = {}
    for _, barData in ipairs(ECME.db.profile.cdmBars.bars) do
        local key = barData.key
        local frame = cdmBarFrames[key]
        if frame and barData.enabled then
            -- Skip bars anchored to party frame, player frame, or mouse cursor (not movable via unlock mode)
            local isPartyAnchored = barData.anchorTo == "partyframe"
            local isPlayerFrameAnchored = barData.anchorTo == "playerframe"
            local isMouseAnchored = barData.anchorTo == "mouse"
            if not isPartyAnchored and not isPlayerFrameAnchored and not isMouseAnchored then
            -- Collect linked unlock element keys (children anchored to this bar)
            local linked = nil
            if anchorChildren[key] then
                linked = {}
                for _, childKey in ipairs(anchorChildren[key]) do
                    linked[#linked + 1] = "CDM_" .. childKey
                end
            end

            elements[#elements + 1] = {
                key = "CDM_" .. key,
                label = "CDM: " .. barData.name,
                group = "Cooldown Manager",
                order = 600,
                linkedKeys = linked,
                getFrame = function() return cdmBarFrames[key] end,
                getSize = function()
                    local f = cdmBarFrames[key]
                    if not f then return 100, 36 end
                    local w, h = f:GetWidth(), f:GetHeight()
                    -- If the frame has a real size and we're not in unlock
                    -- mode for a buff bar, trust the frame dimensions.
                    local isBuff = (barData.barType == "buffs" or key == "buffs")
                    local needsCompute = (w <= 1 or h <= 1)
                        or (EllesmereUI._unlockActive and isBuff)
                    if not needsCompute then return w, h end
                    -- Compute size from bar data (spell count, icon size,
                    -- spacing, rows) so we never rely on stale frame
                    -- dimensions or hidden-icon visibility.
                    local bd = barDataByKey[key]
                    if not bd then return w > 1 and w or 100, h > 1 and h or 36 end
                    -- Count spells from the authoritative data source
                    local count = 0
                    if bd.customSpells then
                        for _, sid in ipairs(bd.customSpells) do
                            if sid and sid ~= 0 then count = count + 1 end
                        end
                    elseif bd.trackedSpells then
                        for _, sid in ipairs(bd.trackedSpells) do
                            if sid and sid ~= 0 then count = count + 1 end
                        end
                        local extras = bd.extraSpells
                        if extras then
                            for _, sid in ipairs(extras) do
                                if sid and sid ~= 0 then count = count + 1 end
                            end
                        end
                    end
                    if count == 0 then return w > 1 and w or 100, h > 1 and h or 36 end
                    local bScale = bd.barScale or 1.0
                    if bScale < 0.1 then bScale = 1.0 end
                    local iW = SnapForScale(bd.iconSize or 36, bScale)
                    local iH = iW
                    if (bd.iconShape or "none") == "cropped" then
                        iH = SnapForScale(math.floor((bd.iconSize or 36) * 0.80 + 0.5), bScale)
                    end
                    local sp = SnapForScale(bd.spacing or 2, bScale)
                    local rows = bd.numRows or 1
                    if rows < 1 then rows = 1 end
                    local stride = math.ceil(count / rows)
                    local grow = bd.growDirection or "RIGHT"
                    local isH = (grow == "RIGHT" or grow == "LEFT")
                    if isH then
                        return stride * iW + (stride - 1) * sp,
                               rows * iH + (rows - 1) * sp
                    else
                        return rows * iW + (rows - 1) * sp,
                               stride * iH + (stride - 1) * sp
                    end
                end,
                savePosition = function(_, point, relPoint, x, y, scale)
                    local p = ECME.db.profile
                    -- Always store as CENTER/CENTER so the bar stays centered
                    -- when icon count changes across specs.
                    local f = cdmBarFrames[key]
                    if f and point == "TOPLEFT" and relPoint == "TOPLEFT" then
                        local bScale = f:GetScale() or 1
                        local fw, fh = f:GetWidth() or 0, f:GetHeight() or 0
                        local cx = x + fw * 0.5
                        local cy = y - fh * 0.5
                        local uiW, uiH = UIParent:GetSize()
                        p.cdmBarPositions[key] = {
                            point = "CENTER", relPoint = "CENTER",
                            x = cx - uiW * 0.5 / bScale, y = cy + uiH * 0.5 / bScale,
                        }
                    else
                        p.cdmBarPositions[key] = { point = point, relPoint = relPoint, x = x, y = y }
                    end
                    for _, b in ipairs(p.cdmBars.bars) do
                        if b.key == key and scale then b.barScale = scale; break end
                    end
                    BuildAllCDMBars()
                end,
                loadPosition = function()
                    return ECME.db.profile.cdmBarPositions[key]
                end,
                getScale = function()
                    for _, b in ipairs(ECME.db.profile.cdmBars.bars) do
                        if b.key == key then return b.barScale or 1.0 end
                    end
                    return 1.0
                end,
                clearPosition = function()
                    ECME.db.profile.cdmBarPositions[key] = nil
                end,
                applyPosition = function()
                    BuildAllCDMBars()
                end,
                isAnchored = function()
                    local bd = barDataByKey[key]
                    return bd and bd.anchorTo and bd.anchorTo ~= "none"
                end,
            }
            end -- not isPartyAnchored
        end
    end

    if #elements > 0 then
        EllesmereUI:RegisterUnlockElements(elements)
    end
end
ns.RegisterCDMUnlockElements = RegisterCDMUnlockElements

-- Stub: Bar Glows disabled — RequestUpdate is a no-op until re-enabled
local function RequestUpdate() end
ns.RequestUpdate = RequestUpdate


-------------------------------------------------------------------------------
--  Initialization
-------------------------------------------------------------------------------
local function SetActiveSpec()
    local p = ECME.db.profile
    p.activeSpecKey = GetCurrentSpecKey()
    EnsureSpec(p, p.activeSpecKey)
end

function ECME:OnInitialize()
    -- Bail out if user has disabled this addon in Global Settings
    if EllesmereUIDB and EllesmereUIDB.disabledAddons and EllesmereUIDB.disabledAddons[ADDON_NAME] then
        self._userDisabled = true
        return
    end

    self.db = EllesmereUI.Lite.NewDB("EllesmereUICooldownManagerDB", DEFAULTS, true)

    -- Migration: enable showStackCount on the buffs bar (was false by default)
    do
        local bars = self.db.profile.cdmBars and self.db.profile.cdmBars.bars
        if bars then
            for _, b in ipairs(bars) do
                if b.key == "buffs" and b.showStackCount == false then
                    b.showStackCount = true
                end
            end
        end
    end

    -- Migration: backfill hideBuffsWhenInactive for bar entries saved before this key existed
    -- AceDB does not deep-merge array elements, so nil means the key was absent (treat as true)
    do
        local bars = self.db.profile.cdmBars and self.db.profile.cdmBars.bars
        if bars then
            for _, b in ipairs(bars) do
                if b.hideBuffsWhenInactive == nil then
                    b.hideBuffsWhenInactive = true
                end
            end
        end
    end

    -- Check if we need first-login capture
    self._needsCapture = not self.db.profile._capturedOnce

    -- Expose for options
    _G._ECME_AceDB = self.db
    _G._ECME_Apply = function()
        RequestUpdate(); if UpdateBuffBars then UpdateBuffBars() end; BuildAllCDMBars(); ns.BuildTrackedBuffBars()
        -- Auto-save current spec profile on any change
        local p = ECME.db.profile
        if p.activeSpecKey and p.activeSpecKey ~= "0" then
            SaveCurrentSpecProfile()
        end
    end
end

function ECME:OnEnable()
    if self._userDisabled then return end

    -- Cache player race/class for trinket/racial/potion tracking
    _playerRace = select(2, UnitRace("player"))
    _playerClass = select(2, UnitClass("player"))

    -- Minimap button (handled by parent addon)
    if not _EllesmereUI_MinimapRegistered and EllesmereUI and EllesmereUI.CreateMinimapButton then
        EllesmereUI.CreateMinimapButton()
    end

    -- Enable CDM cooldown viewer (keep Blizzard CDM running in background
    -- so we can read its children even while hidden)
    if C_CVar and C_CVar.SetCVar then
        pcall(C_CVar.SetCVar, "cooldownViewerEnabled", "1")
    end

    -- Detect spec/character change since last session and swap profiles
    local p = ECME.db.profile
    local oldSpecKey = p.activeSpecKey
    local newSpecKey = GetCurrentSpecKey()
    if newSpecKey ~= "0" and oldSpecKey and oldSpecKey ~= "0" and oldSpecKey ~= newSpecKey then
        -- Spec changed (different character or respec while offline)
        -- Save old spec data BEFORE updating activeSpecKey
        SaveCurrentSpecProfile()
        -- Now update to the new spec and load its profile
        SetActiveSpec()
        LoadSpecProfile(newSpecKey)
        _specValidated = true
    elseif newSpecKey ~= "0" then
        SetActiveSpec()
        _specValidated = true
    else
        -- GetSpecialization() not ready yet — leave activeSpecKey as-is,
        -- ValidateSpec will fix it when SPELLS_CHANGED or PEW fires
        _specValidated = false
    end
    EnsureMappings(GetStore())

    -- Initialize extracted modules
    if ns.InitBarGlows then ns.InitBarGlows(self) end
    if ns.InitBuffBars then ns.InitBuffBars(self) end

    -- CDM Bars: first-login capture or normal setup
    if self._needsCapture then
        -- Defer to PLAYER_ENTERING_WORLD so Edit Mode has applied positions
        self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnCDMFirstLogin")
    else
        self:CDMFinishSetup()
    end

    if ApplyPerSlotHidingAndPackSoon then ApplyPerSlotHidingAndPackSoon() end
    RequestUpdate()
    if UpdateBuffBars then UpdateBuffBars() end

    if HookAllCDMChildren then
        HookAllCDMChildren(_G.BuffIconCooldownViewer)
        C_Timer.After(1, function() HookAllCDMChildren(_G.BuffIconCooldownViewer) end)
        C_Timer.After(3, function() HookAllCDMChildren(_G.BuffIconCooldownViewer) end)
    end

    -- Proc glow hooks (ShowAlert/HideAlert on Blizzard CDM children)
    InstallProcGlowHooks()
    C_Timer.After(1, InstallProcGlowHooks)
end

function ECME:OnCDMFirstLogin()
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    CDMFirstLoginCapture()
    self._needsCapture = false
    self:CDMFinishSetup()
end

function ECME:CDMFinishSetup()
    BuildAllCDMBars()
    ns.BuildTrackedBuffBars()

    -- Save the initial spec profile so switching away and back preserves it
    C_Timer.After(1, function()
        local p = ECME.db.profile
        if p.activeSpecKey and p.activeSpecKey ~= "0" then
            SaveCurrentSpecProfile()
        end
    end)

    -- Deferred keybind update: wait 3s so Blizzard's hotkey update cycle
    -- has fully run before we read HotKey text from button frames
    C_Timer.After(3, UpdateCDMKeybinds)

    -- CDM update tick frame
    if not self._cdmTickFrame then
        self._cdmTickFrame = CreateFrame("Frame")
        self._cdmTickFrame:SetScript("OnUpdate", function(_, dt)
            UpdateAllCDMBars(dt)
        end)
    end
    self._cdmTickFrame:Show()

    -- Register with unlock mode after a short delay (EllesmereUI may not be ready yet)
    C_Timer.After(0.5, function()
        RegisterCDMUnlockElements()
        ns.RegisterTBBUnlockElements()
    end)
end

-- Event frame
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("SPELLS_CHANGED")
eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
eventFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
eventFrame:RegisterEvent("UPDATE_BINDINGS")
eventFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
local _unitAuraTimer = nil
eventFrame:SetScript("OnEvent", function(_, event, unit, updateInfo)
    if not ECME.db then return end
    if event == "PLAYER_LOGOUT" then
        -- Save current spec profile on logout
        local p = ECME.db.profile
        if p.activeSpecKey and p.activeSpecKey ~= "0" then
            SaveCurrentSpecProfile()
        end
        return
    end
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        return
    end
    if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" or event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
        OnProcGlowEvent(event, unit)  -- unit = spellID (first arg after event)
        return
    end
    if event == "UPDATE_BINDINGS" or event == "ACTIONBAR_SLOT_CHANGED" then
        C_Timer.After(0.5, UpdateCDMKeybinds)  -- defer so action slots are fully populated
        return
    end
    if event == "GROUP_ROSTER_UPDATE" then
        -- Invalidate party/player frame caches and re-anchor
        _cachedPartyFrame = nil
        _cachedPartyFrameRoster = 0
        _cachedPlayerFrame = nil
        C_Timer.After(0.2, function() BuildAllCDMBars() end)
        return
    end
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" or event == "ZONE_CHANGED_NEW_AREA" then
        _inCombat = (event == "PLAYER_REGEN_DISABLED")
        _CDMApplyVisibility()
        -- Flush any deferred TBB rebuild that was queued during combat
        if event == "PLAYER_REGEN_ENABLED" and ns.IsTBBRebuildPending and ns.IsTBBRebuildPending() then
            ns.BuildTrackedBuffBars()
        end
        -- Flush deferred keybind rebuild that was blocked during combat
        if event == "PLAYER_REGEN_ENABLED" and _keybindRebuildPending then
            UpdateCDMKeybinds()
        end
        -- Refresh resolved aura IDs now that names are readable again
        if event == "PLAYER_REGEN_ENABLED" then
            if ns.RefreshTBBResolvedIDs then ns.RefreshTBBResolvedIDs() end
        end
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        _inCombat = InCombatLockdown and InCombatLockdown() or false
        -- Validate spec on every zone-in (catches auto spec swaps, login, etc.)
        C_Timer.After(0.5, function()
            ValidateSpec()
            -- If spec was already correct, just rebuild bars
            if not _specValidated then return end
            local newSpecKey = GetCurrentSpecKey()
            local p = ECME.db and ECME.db.profile
            if p and newSpecKey == p.activeSpecKey then
                BuildAllCDMBars()
            end
        end)
    end
    if event == "SPELLS_CHANGED" then
        -- SPELLS_CHANGED fires reliably after spec data is available.
        -- Use it as a safety net to catch spec mismatches that OnEnable missed.
        if not _specValidated then
            ValidateSpec()
        end
        return
    end
    if event == "PLAYER_SPECIALIZATION_CHANGED" and unit == "player" then
        local newSpecKey = GetCurrentSpecKey()
        local p = ECME.db.profile
        if newSpecKey ~= "0" and newSpecKey ~= p.activeSpecKey then
            SwitchSpecProfile(newSpecKey)
            _specValidated = true
        elseif newSpecKey ~= "0" then
            SetActiveSpec()
            _specValidated = true
            C_Timer.After(0.5, function() BuildAllCDMBars() end)
        end
    end
    if event == "UNIT_AURA" and unit == "player" then
        -- Throttle: buff bars only need ~5fps refresh, not every aura event
        if not _unitAuraTimer then
            _unitAuraTimer = C_Timer.NewTimer(0.2, function()
                _unitAuraTimer = nil
                if UpdateBuffBars then UpdateBuffBars() end
            end)
        end
        return
    end
    if ApplyPerSlotHidingAndPackSoon then ApplyPerSlotHidingAndPackSoon() end
    RequestUpdate()
    if UpdateBuffBars then UpdateBuffBars() end
end)

-------------------------------------------------------------------------------
--  Slash commands
-------------------------------------------------------------------------------
SLASH_ECME1 = "/ecme"
SLASH_ECME2 = "/cdmeffects"
SLASH_ECME3 = "/cdm"
SlashCmdList.ECME = function(msg)
    if InCombatLockdown and InCombatLockdown() then return end
    if EllesmereUI and EllesmereUI.ShowModule then
        EllesmereUI:ShowModule("EllesmereUICooldownManager")
    end
end

-------------------------------------------------------------------------------
--  /cdmstacks debug — dumps stack count data for all visible CDM icons
-------------------------------------------------------------------------------
SLASH_CDMSTACKS1 = "/cdmstacks"
SlashCmdList.CDMSTACKS = function()
    local p = function(...) print("|cff0cd29f[CDM Stacks]|r", ...) end
    p("--- Stack Count Debug ---")

    local BLIZZ = {cooldowns="EssentialCooldownViewer", utility="UtilityCooldownViewer", buffs="BuffIconCooldownViewer"}
    local profile = ECME.db and ECME.db.profile
    if not profile or not profile.cdmBars then p("No CDM bars configured"); return end

    for _, barData in ipairs(profile.cdmBars.bars) do
        local key = barData.key
        local blizzName = BLIZZ[key]
        local blizzFrame = blizzName and _G[blizzName]
        if blizzFrame then

        p("|cff00ccff" .. key .. "|r  showStackCount=" .. tostring(barData.showStackCount))

        for i = 1, blizzFrame:GetNumChildren() do
            local child = select(i, blizzFrame:GetChildren())
            if child and child.Icon and child.Icon:GetTexture() then
                local cdID = child.cooldownID
                if not cdID and child.cooldownInfo then cdID = child.cooldownInfo.cooldownID end

                local resolvedSid
                if cdID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
                    local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
                    if info then resolvedSid = info.overrideSpellID or info.spellID end
                end

                local spellName = resolvedSid and C_Spell.GetSpellName(resolvedSid) or "?"
                local isAura = child.wasSetFromAura == true or child.auraInstanceID ~= nil
                local auraInstID = child.auraInstanceID
                local auraUnit = child.auraDataUnit or "player"

                -- Check Applications frame
                local appsFrame = child.Applications
                local appsShown = appsFrame and appsFrame:IsShown()
                local appsTxt = nil
                if appsFrame and appsFrame.Applications then
                    local ok, t = pcall(appsFrame.Applications.GetText, appsFrame.Applications)
                    if ok then appsTxt = tostring(t) end
                end

                -- Check GetPlayerAuraBySpellID
                local auraApps = nil
                if resolvedSid then
                    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, resolvedSid)
                    if ok and aura then
                        local a = aura.applications
                        if a and not (issecretvalue and issecretvalue(a)) then
                            auraApps = a
                        else
                            auraApps = "secret"
                        end
                    end
                end

                -- Check GetAuraDataByAuraInstanceID
                local instApps = nil
                if auraInstID then
                    local ok, ad = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, auraUnit, auraInstID)
                    if ok and ad then
                        local a = ad.applications
                        if a and not (issecretvalue and issecretvalue(a)) then
                            instApps = a
                        else
                            instApps = "secret"
                        end
                    end
                end

                -- Check GetSpellCastCount (for spells that track stacks via cast count)
                local castCount = nil
                if resolvedSid and C_Spell.GetSpellCastCount then
                    local ok, cc = pcall(C_Spell.GetSpellCastCount, resolvedSid)
                    if ok and cc and not (issecretvalue and issecretvalue(cc)) then
                        castCount = cc
                    end
                end

                p("  " .. (spellName or "?") .. " (sid=" .. tostring(resolvedSid) .. ")"
                    .. " isAura=" .. tostring(isAura)
                    .. " auraInstID=" .. tostring(auraInstID)
                    .. " appsShown=" .. tostring(appsShown)
                    .. " appsTxt=" .. tostring(appsTxt)
                    .. " auraApps=" .. tostring(auraApps)
                    .. " instApps=" .. tostring(instApps)
                    .. " castCount=" .. tostring(castCount))
            end
        end

        end -- if blizzFrame
    end

    -- Scan all player auras for stacking buffs (helps identify buff IDs)
    p("|cff00ccffPlayer auras with stacks:|r")
    local foundAny = false
    for i = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not aura then break end
        local apps = aura.applications
        if apps and not (issecretvalue and issecretvalue(apps)) and apps > 0 then
            local aName = aura.name or "?"
            local aSid = aura.spellId or 0
            if not (issecretvalue and issecretvalue(aName)) and not (issecretvalue and issecretvalue(aSid)) then
                p("  " .. tostring(aName) .. " (sid=" .. tostring(aSid) .. ") apps=" .. tostring(apps))
                foundAny = true
            end
        end
    end
    if not foundAny then p("  (none)") end

    p("--- End ---")
end


