if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_CDM_Rotation.lua
--
--  Rotation helper integration (Blizzard C_AssistedCombat).
--  Reads the earlier CDM files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- The main file or an earlier CDM file failed to load.
if not I or I.broken then return end
I.broken = true

local ECME, FC, SnapForScale, _ecmeFC = I.ECME, I.FC, I.SnapForScale, I._ecmeFC
local _getFD, StartNativeGlow, StopNativeGlow = I._getFD, I.StartNativeGlow, I.StopNativeGlow
local cdmBarIcons = I.cdmBarIcons

-------------------------------------------------------------------------------
--  Rotation Helper Integration (Blizzard C_AssistedCombat)
--  Highlights the currently suggested spell on its CDM icon. The default is
--  Blizzard's ActionBarButtonAssistedCombatHighlightTemplate; profile settings
--  can opt into a custom glow or a static solid border.
-------------------------------------------------------------------------------
do
ns._rotationGlowedIcons = {}
ns._rotationHookInstalled = false
ns._rotationInCombat = false

local ROT_GLOW_RATIO = 0.33
local ROT_STYLE_TO_GLOW = {
    pixel = 1,
    shape = 2,
    button = 3,
    autocast = 4,
    gcd = 5,
    modern = 6,
    classic = 7,
}

local function _rotConfig()
    local p = ECME.db and ECME.db.profile
    return p and p.cdmBars
end

local function _rotCVarOn()
    -- User can force-hide via our own toggle, overriding Blizzard's CVar
    local cfg = _rotConfig()
    if cfg and cfg.hideRotationHelper then return false end
    return GetCVarBool and GetCVarBool("assistedCombatHighlight")
end

local function _rotCreateHighlight(icon)
    local ok, hf = pcall(CreateFrame, "Frame", nil, icon, "ActionBarButtonAssistedCombatHighlightTemplate")
    if not ok or not hf then return nil end
    hf:SetAllPoints()
    -- Sit above everything on the icon: Blizzard's cooldown swipe, our border frame, our glowOverlay (+6), and any proc alert frames. +15 clears them all with margin.
    hf:SetFrameLevel(icon:GetFrameLevel() + 15)
    hf:Hide()
    if hf.Flipbook and hf.Flipbook.Anim then
        hf.Flipbook.Anim:Play()
        hf.Flipbook.Anim:Stop()
    end
    return hf
end

local function _rotCreateCustom(icon)
    local overlay = CreateFrame("Frame", nil, icon)
    overlay:SetFrameLevel(icon:GetFrameLevel() + 15)
    overlay:SetAlpha(0)
    return overlay
end

local function _rotSolidBorder(overlay, thickness, r, g, b)
    local t = overlay._rotSolid
    if not t then
        t = {}
        for i = 1, 4 do
            t[i] = overlay:CreateTexture(nil, "OVERLAY", nil, 7)
        end
        t[1]:SetPoint("TOPLEFT"); t[1]:SetPoint("TOPRIGHT")
        t[2]:SetPoint("BOTTOMLEFT"); t[2]:SetPoint("BOTTOMRIGHT")
        t[3]:SetPoint("TOPLEFT"); t[3]:SetPoint("BOTTOMLEFT")
        t[4]:SetPoint("TOPRIGHT"); t[4]:SetPoint("BOTTOMRIGHT")
        overlay._rotSolid = t
    end
    local px = SnapForScale(thickness)
    t[1]:SetHeight(px); t[2]:SetHeight(px)
    t[3]:SetWidth(px);  t[4]:SetWidth(px)
    for i = 1, 4 do
        t[i]:SetColorTexture(r, g, b, 1)
        t[i]:Show()
    end
end

local function _rotHideSolid(overlay)
    local t = overlay and overlay._rotSolid
    if not t then return end
    for i = 1, 4 do t[i]:Hide() end
end

local function _rotResolveColor(cfg)
    local mode = cfg and cfg.rotationAssistColorMode or "default"
    if mode == "class" then
        local c = EllesmereUI.GetClassColor(EllesmereUI._playerClass)
        if c then return c.r, c.g, c.b end
    elseif mode == "custom" then
        return cfg.rotationAssistColorR or 1,
               cfg.rotationAssistColorG or 0,
               cfg.rotationAssistColorB or 0
    end
    -- Default: no tint request, like every other glow site (gold for the drawn
    -- styles via StartNativeGlow, the atlas's own look for FlipBooks).
    return nil
end

local function _rotHide(icon)
    local rfc = icon and _ecmeFC[icon]
    local hf = rfc and rfc.rotationHighlight
    if hf then
        if hf.Flipbook and hf.Flipbook.Anim then hf.Flipbook.Anim:Stop() end
        hf:Hide()
    end
    local custom = rfc and rfc.rotationCustomHighlight
    if custom then
        StopNativeGlow(custom)
        _rotHideSolid(custom)
        custom._rotCfgKey = nil
    end
end

local function _rotShow(icon)
    if not icon then return end
    local rfc = FC(icon)
    local cfg = _rotConfig()
    local style = cfg and cfg.rotationAssistStyle or "blizzard"
    if style ~= "solid" and not ROT_STYLE_TO_GLOW[style] then style = "blizzard" end

    if style ~= "blizzard" then
        local hf0 = rfc.rotationHighlight
        if hf0 then
            if hf0.Flipbook and hf0.Flipbook.Anim then hf0.Flipbook.Anim:Stop() end
            hf0:Hide()
        end
        local overlay = rfc.rotationCustomHighlight
        if not overlay then
            overlay = _rotCreateCustom(icon)
            rfc.rotationCustomHighlight = overlay
        end
        local outset = cfg.rotationAssistOutset or 1
        if outset < 0 then outset = 0 elseif outset > 12 then outset = 12 end
        overlay:ClearAllPoints()
        overlay:SetPoint("TOPLEFT", icon, "TOPLEFT", -outset, outset)
        overlay:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", outset, -outset)
        overlay:SetFrameLevel(icon:GetFrameLevel() + 15)
        local thickness = cfg.rotationAssistThickness or 3
        if thickness < 1 then thickness = 1 elseif thickness > 8 then thickness = 8 end
        local cr, cg, cb = _rotResolveColor(cfg)
        local glowStyle = ROT_STYLE_TO_GLOW[style]
        -- Pixel Glow lines/speed/background (unset = the engine defaults).
        local lines, speed = cfg.rotationAssistLines or 8, cfg.rotationAssistSpeed or 4
        local bgc = cfg.rotationAssistBackground and cfg.rotationAssistBackgroundColor
        -- One reused key table (this runs on every suggestion update in combat).
        local kt = ns._rotKeyScratch
        if not kt then kt = {}; ns._rotKeyScratch = kt end
        kt[1], kt[2], kt[3], kt[4], kt[5], kt[6], kt[7] = style, cr or -1, cg or -1, cb or -1, thickness, outset, glowStyle or 0
        kt[8], kt[9], kt[10] = lines, speed, cfg.rotationAssistBackground and 1 or 0
        kt[11], kt[12], kt[13] = bgc and bgc.r or 0, bgc and bgc.g or 0, bgc and bgc.b or 0
        local cfgKey = table.concat(kt, ":", 1, 13)
        if overlay._rotCfgKey ~= cfgKey or not overlay._glowActive then
            overlay._rotCfgKey = cfgKey
            if style == "solid" then
                StopNativeGlow(overlay)
                _rotSolidBorder(overlay, thickness, cr or 1.0, cg or 0.788, cb or 0.137)
                overlay._glowActive = true
                overlay:SetAlpha(1)
            else
                _rotHideSolid(overlay)
                local w = (icon:GetWidth() or 36) + outset * 2
                local h = (icon:GetHeight() or 36) + outset * 2
                StartNativeGlow(overlay, glowStyle, cr, cg, cb, {
                    N = lines, th = thickness, period = speed,
                    bg = cfg.rotationAssistBackground and {
                        r = (bgc and bgc.r) or 0, g = (bgc and bgc.g) or 0, b = (bgc and bgc.b) or 0,
                    } or nil,
                    width = w,
                    height = h,
                })
            end
        end
        return
    end

    local custom = rfc.rotationCustomHighlight
    if custom then
        StopNativeGlow(custom)
        _rotHideSolid(custom)
        custom._rotCfgKey = nil
    end
    local hf = rfc.rotationHighlight
    if not hf then
        hf = _rotCreateHighlight(icon)
        if not hf then return end
        rfc.rotationHighlight = hf
    end
    if hf.Flipbook then
        local w = icon:GetWidth() or 36
        local h = icon:GetHeight() or 36
        local ox = w * ROT_GLOW_RATIO
        local oy = h * ROT_GLOW_RATIO
        hf.Flipbook:ClearAllPoints()
        hf.Flipbook:SetPoint("TOPLEFT", icon, "TOPLEFT", -ox, oy)
        hf.Flipbook:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", ox, -oy)
    end
    hf:Show()
    if hf.Flipbook and hf.Flipbook.Anim then
        hf.Flipbook.Anim:Play()
        if not ns._rotationInCombat then hf.Flipbook.Anim:Stop() end
    end
end

local function UpdateRotationHighlightsNow()
    if not _rotCVarOn() then
        for icon in pairs(ns._rotationGlowedIcons) do
            _rotHide(icon)
            ns._rotationGlowedIcons[icon] = nil
        end
        return
    end

    local suggestedSpell = C_AssistedCombat and C_AssistedCombat.GetNextCastSpell and C_AssistedCombat.GetNextCastSpell()
    if type(suggestedSpell) ~= "number"
        or (issecretvalue and issecretvalue(suggestedSpell)) then suggestedSpell = nil end

    local newSet = {}
    if suggestedSpell then
        -- A CDM icon and GetNextCastSpell can each hold EITHER the base or an override spell id
        -- (e.g. Maul <-> Raze), and which side is which varies by spec. Compare on base ids in BOTH
        -- directions so "icon=base, suggested=override" and "icon=override, suggested=base" both match. Strictly a superset of exact-id match, so anything that highlighted before still does.
        local GetBaseSpell = C_Spell and C_Spell.GetBaseSpell
        local suggestedBase = (GetBaseSpell and GetBaseSpell(suggestedSpell)) or suggestedSpell
        if type(suggestedBase) ~= "number"
            or (issecretvalue and issecretvalue(suggestedBase)) then suggestedBase = suggestedSpell end
        for _, icons in pairs(cdmBarIcons) do
            for _, icon in ipairs(icons) do
                local ifc = _ecmeFC[icon]
                local sid = ifc and ifc.spellID
                if type(sid) ~= "number" or (issecretvalue and issecretvalue(sid)) then sid = nil end
                if sid and icon:IsShown() then
                    -- Direct/base match first (cheap); only resolve the icon's own base if those
                    -- miss, to keep the common path light. sid > 0: item/trinket icons store -itemID/-13/-14, which must not be fed to GetBaseSpell.
                    local match = (sid == suggestedSpell) or (sid == suggestedBase)
                    if not match and GetBaseSpell and sid > 0 then
                        local sidBase = GetBaseSpell(sid)
                        if type(sidBase) == "number"
                            and not (issecretvalue and issecretvalue(sidBase)) then
                            match = sidBase == suggestedBase
                        end
                    end
                    if match then
                        _rotShow(icon)
                        newSet[icon] = true
                    end
                end
            end
        end
    end

    for icon in pairs(ns._rotationGlowedIcons) do
        if not newSet[icon] then _rotHide(icon) end
    end
    ns._rotationGlowedIcons = newSet
end

-- Coalesce Blizzard's overlapping assisted-combat callbacks and bar rebuilds
-- into one pass on the next frame. A suggestion change normally fires both an
-- EventRegistry callback and UpdateAllAssistedHighlightFramesForSpell; running
-- the full icon scan for each notification needlessly doubles the hot path.
local _rotDirty = CreateFrame("Frame")
_rotDirty:Hide()
_rotDirty:SetScript("OnUpdate", function(self)
    self:Hide()
    UpdateRotationHighlightsNow()
end)

local function QueueRotationHighlightUpdate()
    _rotDirty:Show()
end
ns.UpdateRotationHighlights = QueueRotationHighlightUpdate

local function _rotSyncCombat()
    local inCombat = InCombatLockdown() or UnitAffectingCombat("player")
    ns._rotationInCombat = inCombat and true or false
    for icon in pairs(ns._rotationGlowedIcons) do
        local rfc2 = icon and _ecmeFC[icon]
        local hf = rfc2 and rfc2.rotationHighlight
        if hf and hf:IsShown() and hf.Flipbook and hf.Flipbook.Anim then
            if ns._rotationInCombat then
                if not hf.Flipbook.Anim:IsPlaying() then hf.Flipbook.Anim:Play() end
            else
                if hf.Flipbook.Anim:IsPlaying() then hf.Flipbook.Anim:Stop() end
            end
        end
    end
end
ns._syncRotationCombatState = _rotSyncCombat

function ns.InstallRotationHook()
    if ns._rotationHookInstalled then return end
    ns._rotationHookInstalled = true

    _rotSyncCombat()

    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("AssistedCombatManager.OnAssistedHighlightSpellChange", function()
            QueueRotationHighlightUpdate()
        end, "ECME_CDM_RotationHelper")
        -- Clear highlights if the user flips Blizzard's CVar off at runtime.
        EventRegistry:RegisterCallback("AssistedCombatManager.OnSetUseAssistedHighlight", function()
            QueueRotationHighlightUpdate()
        end, "ECME_CDM_RotationHelper_CVar")
    end

    if AssistedCombatManager and AssistedCombatManager.UpdateAllAssistedHighlightFramesForSpell then
        hooksecurefunc(AssistedCombatManager, "UpdateAllAssistedHighlightFramesForSpell", function()
            QueueRotationHighlightUpdate()
        end)
    end

    -- Re-run after bar rebuilds so the shine follows icon recycling.
    if ns.CollectAndReanchor then
        hooksecurefunc(ns, "CollectAndReanchor", QueueRotationHighlightUpdate)
    end

    QueueRotationHighlightUpdate()
end
end

-- Show Item Count "Out of Combat" mode: re-run the icon restyle for bars using it whenever combat starts or ends (the gate inside the restyle reads the event-tracked combat flag). No-ops instantly when no bar uses the mode.
function ns.RefreshItemCountOOCBars()
    local p = ECME.db and ECME.db.profile
    local bars = p and p.cdmBars and p.cdmBars.bars
    if not bars or not ns.RefreshCDMIconAppearance then return end
    for _, bd in ipairs(bars) do
        if bd.itemCountOOC and bd.key then
            ns.RefreshCDMIconAppearance(bd.key)
        end
    end
end

-- TAINT LAW (field-proven 2026-08-31, 24x error burst in the field): NEVER
-- write ANY field on a Blizzard CooldownViewer item frame, not even a key
-- Blizzard itself owns (spellOutOfRange), and never call its paint methods
-- from our execution. The written value is tainted; Blizzard's refresh
-- chains read it MID-EXECUTION and the taint poisons everything downstream:
-- forbidden secure caches (CheckAllowOnCooldownGeneric dataCache), secret
-- boolean fields (allowOnCooldownAlert), and map registrations made inside
-- the chain, which then convert every later event dispatch on the viewer
-- into tainted execution. A stale-range repaint is never worth that. The
-- range-on-override-swap staleness it replaced is cosmetic, and is repainted
-- below WITHIN this law: our own texture only, no frame field, no paint call.

-- Blizzard arms the range check on the BASE spell, so while an override is up the
-- icon tracks the wrong spell's range. Repainted on fd.tex and the side table,
-- never the frame. The hook RE-POLLS instead of replaying a stored answer: it
-- fires on every Blizzard repaint, including the one their own range event drives,
-- so walking back into range clears the tint without a second event of our own. A
-- secret or unknown answer leaves their colour alone. Cleared to nil when no
-- override is live, since Blizzard's own check is correct for the base spell.
-- On ns.* because the main chunk is at Lua 5.1's 200-local cap.
function ns.ApplyOverrideRangeTint(icon, overrideSpellID)
    local fd = _getFD(icon)
    local tex = fd and fd.tex
    local C = CooldownViewerConstants
    if not (tex and C) then return end
    -- Live-override count, kept on the nil<->value transitions of the ONLY
    -- writer of _oorSpellID: RepaintOverrideRange gates its whole icon walk on
    -- it, so the event dispatches Blizzard's own base-spell registrations
    -- produce (nearly all of them, for nearly every player) cost one integer
    -- read instead of a full bar scan.
    if (fd._oorSpellID ~= nil) ~= (overrideSpellID ~= nil) then
        ns._oorLiveCount = (ns._oorLiveCount or 0) + (overrideSpellID and 1 or -1)
    end
    fd._oorSpellID = overrideSpellID
    if not fd._oorHooked then
        fd._oorHooked = true
        local guard = false
        hooksecurefunc(tex, "SetVertexColor", function()
            local sid = fd._oorSpellID
            if guard or not sid then return end
            local r = C_Spell.IsSpellInRange(sid)
            if issecretvalue and issecretvalue(r) then return end
            if r ~= false then return end
            guard = true
            tex:SetVertexColor(C.ITEM_NOT_IN_RANGE_COLOR:GetRGBA())
            guard = false
        end)
    end
    -- Repaint once now: the hook only rides Blizzard's own writes, and the swap
    -- that brought us here does not produce one.
    local inRange = overrideSpellID and C_Spell.IsSpellInRange(overrideSpellID)
    if issecretvalue and issecretvalue(inRange) then return end
    if inRange == false then
        tex:SetVertexColor(C.ITEM_NOT_IN_RANGE_COLOR:GetRGBA())
        return
    end
    local sid = overrideSpellID or icon.rangeCheckSpellID
    if not sid then return end
    local usable, notEnoughMana = C_Spell.IsSpellUsable(sid)
    if issecretvalue and (issecretvalue(usable) or issecretvalue(notEnoughMana)) then
        return
    end
    if usable then
        tex:SetVertexColor(C.ITEM_USABLE_COLOR:GetRGBA())
    elseif notEnoughMana then
        tex:SetVertexColor(C.ITEM_NOT_ENOUGH_MANA_COLOR:GetRGBA())
    else
        tex:SetVertexColor(C.ITEM_NOT_USABLE_COLOR:GetRGBA())
    end
end

-- Blizzard arms its check on the BASE spell only, so a melee base with a 15yd
-- override never dispatches when you cross 15yd. Arming the override id closes that.
--
-- The registration is per SPELL, not per caller, and an override can be a CDM entry
-- in its own right (Hammer of Wrath overrides Judgment and is also its own icon), so
-- an id Blizzard holds is left alone in both directions -- re-checked at disarm time,
-- since a spell can become theirs while ours is armed.
function ns.BlizzardArmsRange(spellID)
    for _, icons in pairs(cdmBarIcons) do
        for _, icon in ipairs(icons) do
            if icon.rangeCheckSpellID == spellID then return true end
        end
    end
    return false
end

function ns.ArmOverrideRange(baseSpellID, overrideSpellID)
    local armed = ns._oorArmed
    if not armed then armed = {}; ns._oorArmed = armed end
    local prev = armed[baseSpellID]
    if prev == overrideSpellID then return end
    if prev then
        -- Also left armed while a custom spell icon holds it (CdmHooks, Out of Range Coloring).
        if not ns.BlizzardArmsRange(prev) and not ns.CustomSpellRangeHolds(prev) then
            C_Spell.EnableSpellRangeCheck(prev, false)
        end
        armed[baseSpellID] = nil
    end
    if overrideSpellID and not ns.BlizzardArmsRange(overrideSpellID) then
        C_Spell.EnableSpellRangeCheck(overrideSpellID, true)
        armed[baseSpellID] = overrideSpellID
    end
end

-- Every registration dropped at once (spec change, logout): a leaked one costs a
-- dispatch we ignore, but they would accumulate across a session of swaps.
function ns.DisarmOverrideRanges()
    local armed = ns._oorArmed
    if not armed then return end
    for base, ov in pairs(armed) do
        if not ns.BlizzardArmsRange(ov) and not ns.CustomSpellRangeHolds(ov) then
            C_Spell.EnableSpellRangeCheck(ov, false)
        end
        armed[base] = nil
    end
    -- The tracked ids go with the registrations ("the new spec's overrides
    -- re-arm on their own events"): a value left behind would keep that icon's
    -- hook polling a dead spell and hold the repaint gate open. Also what
    -- keeps the live count exact across spec changes.
    for _, icons in pairs(cdmBarIcons) do
        for _, icon in ipairs(icons) do
            local fd = _getFD(icon)
            if fd and fd._oorSpellID ~= nil then fd._oorSpellID = nil end
        end
    end
    ns._oorLiveCount = 0
end

-- SPELL_RANGE_CHECK_UPDATE. Keyed off the icon's own stored override id rather than
-- our armed set, so it still repaints for an override Blizzard arms itself. The
-- payload's isInRange is ignored in favour of ApplyOverrideRangeTint's own poll,
-- which already guards a secret answer. Falls through immediately for the base-spell
-- registrations Blizzard makes, which is nearly every dispatch.
function ns.RepaintOverrideRange(spellID)
    -- No icon holds a live override: nothing here could match. Reads only our
    -- own counter, so it runs before any payload value is touched.
    if (ns._oorLiveCount or 0) <= 0 then return end
    if type(spellID) ~= "number" then return end
    if issecretvalue and issecretvalue(spellID) then return end
    for _, icons in pairs(cdmBarIcons) do
        for _, icon in ipairs(icons) do
            local fd = _getFD(icon)
            if fd and fd._oorSpellID == spellID then
                ns.ApplyOverrideRangeTint(icon, spellID)
            end
        end
    end
end

-- rangeCheckSpellID is READ, never written: the law is about writes.
function ns.ResyncCdmRange(baseSpellID, overrideSpellID)
    -- Secret payload fails open, before any truthiness test or comparison
    -- touches it: same guard the action bar dispatcher puts on this event.
    if issecretvalue and (issecretvalue(baseSpellID) or issecretvalue(overrideSpellID)) then
        return
    end
    if not (baseSpellID and C_Spell and C_Spell.IsSpellInRange) then return end
    -- nil once the override lapses, which hands the icon back to Blizzard: their
    -- own check is armed on the base spell and is right again from that moment.
    local liveOverride = (overrideSpellID and overrideSpellID ~= baseSpellID)
        and overrideSpellID or nil
    ns.ArmOverrideRange(baseSpellID, liveOverride)
    for _, icons in pairs(cdmBarIcons) do
        for _, icon in ipairs(icons) do
            if icon.rangeCheckSpellID == baseSpellID then
                ns.ApplyOverrideRangeTint(icon, liveOverride)
            end
        end
    end
end

I.broken = false
