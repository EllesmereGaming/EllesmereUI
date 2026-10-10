if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_UnitFrames_ClassPower.lua
--
--  The custom class power display on the player frame, its two load-time
--  driver frames and tickers, and ApplyEnemyColors, published through I
--  (EUI_UnitFrames_Init.lua, EUI_UnitFrames_Reload.lua). Reads the main
--  file through ns and ns._internals; db is set through I.dbSetters.
-------------------------------------------------------------------------------
local _, ns = ...

local math_floor = math.floor
local issecretvalue = issecretvalue
local PP = EllesmereUI.PP

local I = ns._internals
local frames = I.frames
local ClassPowerEntry, DruidNeedsCatForm, InCatForm = I.ClassPowerEntry, I.DruidNeedsCatForm, I.InCatForm
local db
I.dbSetters[#I.dbSetters + 1] = function(v) db = v end

-- Fixed child-born shells for the class-power event driver and castbar watcher. The
-- class-power bar is destroyed/rebuilt on spec switches through the profile system,
-- whose dispatch runs under the PARENT addon's execution context -- and the engine
-- bills a handler's entire call tree to the addon whose context created the frame, so
-- drivers recreated there would bill the parent's CPU row. Creating them ONCE here
-- (child main chunk) and reconfiguring per build keeps every rebuild attribution-safe.
ns._cpDriver = CreateFrame("Frame")
ns._cpDriver:Hide()
ns._cpCastWatcher = CreateFrame("Frame")
ns._cpCastWatcher:Hide()

-- 10 Hz anim tickers for the two class-power polls. A per-frame OnUpdate that
-- early-outs to a 0.1s cadence still pays a full Lua entry every render frame (pure
-- dispatch tax at high fps); a looping Animation fires the body at the real cadence and
-- the C engine sleeps between fires. Created HERE (child main chunk) since the
-- AnimationGroup is the engine's entry object and bills its creation context. Bodies
-- read a swappable ns function so per-build closures stay per-build; a ticker runs only
-- between Start()/Stop() and pauses while its host is hidden.
ns._cpDriverTick = EllesmereUI.Tick.NewAnimTicker(ns._cpDriver, function()
    local fn = ns._cpTickFn
    if fn then fn() end
    return true
end, 0.1)
ns._cpWatchTick = EllesmereUI.Tick.NewAnimTicker(ns._cpCastWatcher, function()
    local fn = ns._cpWatchFn
    if fn then fn() end
    return true
end, 0.1)

local function DestroyCustomClassPower()
    -- Park the engine-slot warrior charge overlay: its proxy is parented to
    -- the container being torn down; the next _WCUF_Sync re-adopts it.
    if _G._EWC then _G._EWC.Gate("uf") end
    ns._cpTickFn = nil
    ns._cpDriverTick.Stop()
    ns._cpWatchFn = nil
    ns._cpWatchTick.Stop()
    if frames._customClassPower then
        frames._customClassPower:Hide()
        -- Unregister events on all children to prevent leaks
        local kids = { frames._customClassPower:GetChildren() }
        for _, child in ipairs(kids) do
            child:UnregisterAllEvents()
            child:SetScript("OnEvent", nil)
            child:Hide()
        end
        frames._customClassPower:SetParent(nil)
        frames._customClassPower = nil
    end
end

local function CreateCustomClassPower(playerFrame, style)
    local _, playerClass = UnitClass("player")
    local entry = ClassPowerEntry(playerClass)
    if not entry then return nil end

    -- Resolve spec-specific entries (table with specID keys)
    local powerType, customMax, isCustom, renderMode
    if type(entry) == "table" then
        local spec = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization()
        local specID = spec and C_SpecializationInfo.GetSpecializationInfo(spec)
        local specEntry = specID and entry[specID]
        if not specEntry then return nil end
        if type(specEntry) == "table" and type(specEntry[1]) == "string" then
            -- String-keyed custom resource (e.g. "SOUL_FRAGMENTS_VENGEANCE")
            powerType = specEntry[1]
            customMax = specEntry[2]
            renderMode = specEntry[3]  -- optional "bar" for continuous fill
            isCustom = true
        elseif type(specEntry) == "table" then
            -- Numeric powerType wrapped in a spec table (e.g. Chi for Windwalker)
            powerType = specEntry[1]
            customMax = specEntry[2]
            isCustom = false
        else
            powerType = specEntry
            isCustom = false
        end
    else
        powerType = entry
        isCustom = false
    end
    local isBarMode = (renderMode == "bar")

    local maxPower
    if isCustom then
        -- For custom resources, get live max from EllesmereUI helpers
        if powerType == "SOUL_FRAGMENTS_VENGEANCE" then
            maxPower = 6
        elseif powerType == "MAELSTROM_WEAPON" and EllesmereUI and EllesmereUI.GetMaelstromWeapon then
            local _, mMax = EllesmereUI.GetMaelstromWeapon()
            maxPower = (mMax and mMax > 0) and mMax or customMax
        elseif powerType == "TIP_OF_THE_SPEAR" then
            maxPower = customMax
        elseif powerType == "WHIRLWIND_STACKS" or powerType == "SWEEPING_STRIKES" then
            -- Talent-aware cap from the engine-slot module (Broad Strokes).
            maxPower = (_G._EWC and _G._EWC.MaxApps(powerType)) or customMax
        elseif powerType == "ICICLES" then
            maxPower = customMax or 5
        elseif powerType == "SOUL_FRAGMENTS_DEVOURER" then
            local maxC = customMax or 50
            if EllesmereUI and EllesmereUI.GetSoulFragments then
                local _, m = EllesmereUI.GetSoulFragments()
                if m and m > 0 then maxC = m end
            end
            maxPower = maxC
            customMax = maxPower
        elseif powerType == "BREWMASTER_STAGGER" then
            -- Bar mode: "max" is player max HP; StatusBar fills with UnitStagger.
            local mh = UnitHealthMax("player") or 0
            if issecretvalue and issecretvalue(mh) then mh = 0 end
            maxPower = (mh > 0) and mh or 1
            customMax = maxPower
        else
            maxPower = customMax or 5
        end
    else
        maxPower = UnitPowerMax("player", powerType) or 5
        if maxPower <= 0 then maxPower = 5 end
    end

    local isModern = (style == "modern")
    local isCircle = (style == "circles")
    local sizeAdj = db.profile.player.classPowerSize or 8
    local spacingAdj = db.profile.player.classPowerSpacing or 2
    local pipSize = isModern and sizeAdj or (isCircle and (sizeAdj + 6) or (sizeAdj + 12))
    local pipH = isModern and math.max(3, math.floor(sizeAdj * 0.375)) or (isCircle and (sizeAdj + 6) or (sizeAdj))
    local gap = spacingAdj
    local pad = isModern and 0 or 4
    -- Snap all dimensions to physical pixel boundaries
    pipSize = PP.Scale(pipSize)
    pipH = PP.Scale(pipH)
    gap = PP.Scale(gap)
    pad = PP.Scale(pad)
    -- For bar-mode resources (stagger), "maxPower" is a raw game value (e.g. player max
    -- HP) and doesn't drive layout width. Use a 5-pip equivalent so the bar matches the
    -- visual footprint of Chi / Combo Points etc.
    local drawPipCount = isBarMode and 5 or maxPower
    local totalW = drawPipCount * pipSize + (drawPipCount - 1) * gap + pad
    local totalH = pipH + pad

    local container = CreateFrame("Frame", nil, UIParent)
    PP.Size(container, totalW, totalH)
    container:SetFrameStrata("MEDIUM")
    container:SetFrameLevel(10)

    -- Background color behind all pips (spans left edge of first pip to right edge of last pip)
    local bgCol = db.profile.player.classPowerBgColor or { r = 0.082, g = 0.082, b = 0.082, a = 1.0 }
    local containerBg = container:CreateTexture(nil, "BACKGROUND")
    containerBg:SetAllPoints()
    containerBg:SetColorTexture(bgCol.r, bgCol.g, bgCol.b, bgCol.a)
    container._bg = containerBg

    -- Empty pip color (shown when pip is not filled)
    local emptyCol = db.profile.player.classPowerEmptyColor or { r = 0.2, g = 0.2, b = 0.2, a = 1.0 }

    if not isModern then
        -- Border
        MakeBorder(container, 0, 0, 0, 0.8)
    end

    -- 1px inset bottom border for "above" position (matches frame border color)
    -- Must be on a separate overlay frame at a higher frame level than pip child frames,
    -- because child frames always render over parent textures regardless of draw layer.
    local cpBdrOverlay = CreateFrame("Frame", nil, container)
    cpBdrOverlay:SetAllPoints()
    cpBdrOverlay:SetFrameLevel(container:GetFrameLevel() + 20)
    local cpBottomBdr = cpBdrOverlay:CreateTexture(nil, "OVERLAY", nil, 7)
    cpBottomBdr:SetHeight(1)
    PP.Point(cpBottomBdr, "BOTTOMLEFT", cpBdrOverlay, "BOTTOMLEFT", 0, 0)
    PP.Point(cpBottomBdr, "BOTTOMRIGHT", cpBdrOverlay, "BOTTOMRIGHT", 0, 0)
    cpBdrOverlay:Hide()  -- shown only when position is "above"
    container._bottomBdr = cpBottomBdr
    container._bottomBdrFrame = cpBdrOverlay

    local useClassColor = db.profile.player.classPowerClassColor ~= false
    local cr, cg, cb
    if not useClassColor then
        local cc = db.profile.player.classPowerCustomColor or { r = 1, g = 0.82, b = 0 }
        cr, cg, cb = cc.r, cc.g, cc.b
    else
        -- Pull from EUI global color system: resource color > class color
        local rc = EllesmereUI.GetResourceColor(playerClass)
        if rc then
            cr, cg, cb = rc.r, rc.g, rc.b
        else
            local cc = EllesmereUI.GetClassColor(playerClass)
            if cc then cr, cg, cb = cc.r, cc.g, cc.b else cr, cg, cb = 1, 1, 1 end
        end
    end

    local function MakePip(parent, index)
        local pip = CreateFrame("Frame", nil, parent)
        PP.Size(pip, pipSize, pipH)
        local x = (index - 1) * (pipSize + gap) + pad / 2
        PP.Point(pip, "LEFT", parent, "LEFT", x, 0)

        -- Empty bar color (visible when pip is not filled)
        local pipEmpty = pip:CreateTexture(nil, "ARTWORK", nil, 0)
        pipEmpty:SetAllPoints()
        if isCircle then
            pipEmpty:SetTexture("Interface\\COMMON\\Indicator-Gray")
            pipEmpty:SetVertexColor(emptyCol.r, emptyCol.g, emptyCol.b, emptyCol.a)
        else
            pipEmpty:SetColorTexture(emptyCol.r, emptyCol.g, emptyCol.b, emptyCol.a)
        end

        -- Fill color (on top of empty)
        local pipFill = pip:CreateTexture(nil, "ARTWORK", nil, 1)
        pipFill:SetAllPoints()

        if isCircle then
            pipFill:SetTexture("Interface\\COMMON\\Indicator-Gray")
            pipFill:SetVertexColor(cr, cg, cb, 1)
        else
            pipFill:SetColorTexture(cr, cg, cb, 1)
        end

        pip._fill = pipFill
        pip._empty = pipEmpty
        return pip
    end

    local pips = {}
    -- Tracks how many pips are CURRENTLY shown, separate from #pips: pip frames
    -- are only ever Hide()'d when the resource max drops (never removed from the
    -- table), so #pips is a high-water mark that stops matching a shrunk-then-
    -- regrown max and silently skips the rebuild below.
    local shownPipCount = 0
    local staggerBar  -- set only in bar mode
    if isBarMode then
        -- Single StatusBar filling the container; color updates per-tier.
        local inset = pad / 2
        staggerBar = CreateFrame("StatusBar", nil, container)
        staggerBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        staggerBar:GetStatusBarTexture():SetHorizTile(false)
        PP.Point(staggerBar, "TOPLEFT",     container, "TOPLEFT",     inset, 0)
        PP.Point(staggerBar, "BOTTOMRIGHT", container, "BOTTOMRIGHT", -inset, 0)
        staggerBar:SetMinMaxValues(0, maxPower)
        staggerBar:SetValue(0)
        staggerBar:GetStatusBarTexture():SetVertexColor(0.2, 0.8, 0.2, 1)
        container._staggerBar = staggerBar
    else
        for i = 1, maxPower do
            pips[i] = MakePip(container, i)
        end
        shownPipCount = maxPower
    end

    -- Update function
    local isSecretResource = (powerType == "SOUL_FRAGMENTS_VENGEANCE")
    local function UpdatePips()
        -- Bar-mode resources fill a single StatusBar instead of discrete pips.
        if isBarMode and staggerBar then
            if powerType == "BREWMASTER_STAGGER" then
                local stagger = UnitStagger and UnitStagger("player") or 0
                local maxHP   = UnitHealthMax("player") or 0
                local tainted = issecretvalue
                             and (issecretvalue(stagger) or issecretvalue(maxHP))
                if tainted then
                    staggerBar:Hide()
                    return
                end
                if maxHP <= 0 then maxHP = 1 end
                if staggerBar._lastMax ~= maxHP then
                    staggerBar._lastMax = maxHP
                    staggerBar:SetMinMaxValues(0, maxHP)
                end
                staggerBar:SetValue(stagger)
                local pct = stagger / maxHP
                local sr, sg, sb
                if pct >= 0.6 then      sr, sg, sb = 1.0,  0.2,  0.2
                elseif pct >= 0.3 then  sr, sg, sb = 1.0,  0.85, 0.2
                else                    sr, sg, sb = 0.2,  0.8,  0.2 end
                if staggerBar._lastR ~= sr or staggerBar._lastG ~= sg or staggerBar._lastB ~= sb then
                    staggerBar._lastR, staggerBar._lastG, staggerBar._lastB = sr, sg, sb
                    staggerBar:GetStatusBarTexture():SetVertexColor(sr, sg, sb, 1)
                end
            elseif powerType == "SOUL_FRAGMENTS_DEVOURER" then
                local cur, maxC = 0, customMax or 50
                if EllesmereUI and EllesmereUI.GetSoulFragments then
                    cur, maxC = EllesmereUI.GetSoulFragments()
                    if not maxC or maxC <= 0 then maxC = customMax or 50 end
                end
                if staggerBar._lastMax ~= maxC then
                    staggerBar._lastMax = maxC
                    staggerBar:SetMinMaxValues(0, maxC)
                end
                staggerBar:SetValue(cur or 0)
                -- Use class color (DH)
                if not staggerBar._colorSet then
                    staggerBar._colorSet = true
                    local rc = EllesmereUI.GetResourceColor("DEMONHUNTER")
                    local cc = rc or (EllesmereUI.GetClassColor("DEMONHUNTER"))
                    if cc then
                        staggerBar:GetStatusBarTexture():SetVertexColor(cc.r, cc.g, cc.b, 1)
                    end
                end
            end
            if not staggerBar:IsShown() then staggerBar:Show() end
            return
        end
        local cur, max
        if isCustom then
            -- Custom resource: use EllesmereUI tracker functions
            if powerType == "SOUL_FRAGMENTS_VENGEANCE" then
                cur = C_Spell and C_Spell.GetSpellCastCount and C_Spell.GetSpellCastCount(228477) or 0
                max = 6
            elseif powerType == "MAELSTROM_WEAPON" and EllesmereUI and EllesmereUI.GetMaelstromWeapon then
                cur, max = EllesmereUI.GetMaelstromWeapon()
            elseif powerType == "TIP_OF_THE_SPEAR" and EllesmereUI and EllesmereUI.GetTipOfTheSpear then
                cur, max = EllesmereUI.GetTipOfTheSpear()
            elseif powerType == "WHIRLWIND_STACKS" or powerType == "SWEEPING_STRIKES" then
                -- Engine slot owns the display (EllesmereUI_WarriorCharges):
                -- the true count fills the overlay bar C-side; legacy pips
                -- stay hidden (empty row until the deferred build lands).
                for i = 1, #pips do if pips[i] then pips[i]:Hide() end end
                return
            elseif powerType == "ICICLES" then
                -- Frost Mage Icicles: stack count from the Icicles aura (205473).
                local count = 0
                if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
                    local aura = C_UnitAuras.GetPlayerAuraBySpellID(205473)
                    if aura then
                        count = aura.applications or aura.charges or aura.points or 0
                        if count > 5 then count = 5 end
                    end
                end
                cur, max = count, 5
            else
                cur, max = 0, maxPower
            end
            if not max or max <= 0 then max = maxPower end
        else
            -- Forever combo points belong to the target, and UnitPower still
            -- reports the previous target's count at the moment
            -- PLAYER_TARGET_CHANGED fires (measured on 1.60.1: up=3 while
            -- gcp=0 on the swap), with no later event to correct it. Blizzard's
            -- own classic ComboFrame reads GetComboPoints for the same reason.
            if EllesmereUI.IS_FOREVER == true and powerType == Enum.PowerType.ComboPoints
               and GetComboPoints then
                cur = GetComboPoints("player", "target") or 0
            else
                cur = UnitPower("player", powerType) or 0
            end
            max = UnitPowerMax("player", powerType) or maxPower

            -- Handle runes specially (count available runes)
            if powerType == Enum.PowerType.Runes then
                cur = 0
                for i = 1, max do
                    local start, duration, ready = GetRuneCooldown(i)
                    if ready then cur = cur + 1 end
                end
            end
        end

        -- Rebuild pips if max changed. Compare against shownPipCount, not #pips:
        -- #pips only ever grows (hidden pips stay in the table), so it stops
        -- matching once max shrinks and regrows to a previously-seen value,
        -- leaving the high pips stuck hidden and the container stuck narrow.
        if max ~= shownPipCount and max > 0 then
            for _, p in ipairs(pips) do p:Hide() end
            local newTotalW = max * pipSize + (max - 1) * gap + pad
            container:SetWidth(newTotalW)
            for i = 1, max do
                if not pips[i] then
                    pips[i] = MakePip(container, i)
                end
                local x = (i - 1) * (pipSize + gap) + pad / 2
                pips[i]:ClearAllPoints()
                PP.Point(pips[i], "TOPLEFT", container, "TOPLEFT", x, 0)
                PP.Size(pips[i], pipSize, pipH)
                pips[i]:Show()
            end
            shownPipCount = max
            -- Only "above" stretches the row across the health bar (see
            -- PositionClassPowerBar); every other position keeps the natural pip
            -- width laid out just above.
            if isModern and (db.profile.player.classPowerPosition or "top") == "above"
               and container._repositionForWidth then
                container._repositionForWidth(db.profile.player.frameWidth or 181)
            end
        end

        -- The resource kind alone does not decide this: which values the client
        -- classifies depends on the client, and combo points come back secret on
        -- Forever. Classifying the value itself keeps the compare below legal
        -- whatever the resource, at the cost of one test per update.
        if isSecretResource or issecretvalue(cur) then
            -- Secret-value path: use StatusBar overlays per pip
            for i = 1, #pips do
                if pips[i] then
                    if not pips[i]._secretBar then
                        local sb = CreateFrame("StatusBar", nil, pips[i])
                        sb:SetAllPoints(pips[i]._fill or pips[i])
                        sb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
                        sb:SetStatusBarColor(cr, cg, cb, 1)
                        sb:SetFrameLevel(pips[i]:GetFrameLevel() + 1)
                        pips[i]._secretBar = sb
                    end
                    pips[i]._secretBar:SetMinMaxValues(i - 1, i)
                    pips[i]._secretBar:SetValue(cur)
                    pips[i]._secretBar:SetStatusBarColor(cr, cg, cb, 1)
                    pips[i]._secretBar:Show()
                    -- Hide normal fill; StatusBar replaces it
                    if pips[i]._fill then pips[i]._fill:Hide() end
                end
            end
        else
            -- Clean-value path
            for i = 1, #pips do
                if pips[i] then
                    if pips[i]._secretBar then pips[i]._secretBar:Hide() end
                    if pips[i]._fill then
                        if i <= cur then
                            pips[i]._fill:Show()
                        else
                            pips[i]._fill:Hide()
                        end
                    end
                end
            end
        end
    end

    -- Event driver: the shared child-born shell (see ns._cpDriver above), fully reset
    -- here since the previous spec's build may have left registrations or a poll on it.
    local eventFrame = ns._cpDriver
    eventFrame:UnregisterAllEvents()
    eventFrame:SetScript("OnEvent", nil)
    ns._cpTickFn = nil
    ns._cpDriverTick.Stop()
    eventFrame:SetParent(container)
    eventFrame:Show()
    if isCustom then
        -- Per-resource event registration: only register what each resource actually
        -- needs. Icicles, Maelstrom Weapon and Tip of the Spear are aura-driven; everything
        -- else polls via OnUpdate (either Lua API changes mid-combat, or no reliable event exists).
        local auraDriven    = (powerType == "MAELSTROM_WEAPON" or powerType == "ICICLES"
            or powerType == "TIP_OF_THE_SPEAR")
        -- Warrior charge buffs are engine-driven end to end (the overlay owns
        -- the row: EllesmereUI_WarriorCharges): no poll, no cast events.
        local engineDriven  = (powerType == "WHIRLWIND_STACKS" or powerType == "SWEEPING_STRIKES")
        local needsOnUpdate = not auraDriven and not engineDriven
        local needsAura     = auraDriven

        if needsOnUpdate then
            -- 10 Hz poll on the shared anim ticker (see ns._cpDriverTick):
            -- same cadence as the old OnUpdate accumulator without the
            -- per-render-frame entry tax.
            ns._cpTickFn = UpdatePips
            ns._cpDriverTick.Start()
        end

        eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        -- PLAYER_SPECIALIZATION_CHANGED is deliberately NOT registered here. It is owned
        -- by cpSpecWatcher (see InitializeFrames), which lives OUTSIDE the container,
        -- filters unit == "player", and rebuilds after tearing down. A copy of that
        -- handler on this driver could only ever destroy WITHOUT rebuilding (the
        -- teardown unregisters the driver mid-dispatch), and -- lacking the unit filter
        -- -- would fire on any GROUP MEMBER's spec event, silently killing the bar until
        -- the next /reload.
        if needsAura then
            eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
        end
        eventFrame:SetScript("OnEvent", function()
            UpdatePips()
        end)
    else
        eventFrame:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
        eventFrame:RegisterUnitEvent("UNIT_MAXPOWER", "player")
        eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        if powerType == Enum.PowerType.Runes then
            eventFrame:RegisterEvent("RUNE_POWER_UPDATE")
        end
        local druidFormToggle = DruidNeedsCatForm(playerClass, powerType)
        if druidFormToggle then
            eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
        end
        -- Combo points belong to the target on Forever, so swapping targets
        -- changes the count with no power event behind it. Blizzard's own
        -- ComboFrame refreshes on this event for the same reason.
        if EllesmereUI.IS_FOREVER == true and powerType == Enum.PowerType.ComboPoints then
            eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
        end
        eventFrame:SetScript("OnEvent", function(_, event, unit)
            if druidFormToggle and (event == "UPDATE_SHAPESHIFT_FORM" or event == "PLAYER_ENTERING_WORLD") then
                container:SetShown(InCatForm())
            end
            if event == "PLAYER_ENTERING_WORLD" or event == "RUNE_POWER_UPDATE"
               or event == "PLAYER_TARGET_CHANGED" or (unit == "player") then
                UpdatePips()
            end
        end)
    end

    -- Form-toggled druids start hidden unless already in cat form
    if DruidNeedsCatForm(playerClass, powerType) and not InCatForm() then
        container:Hide()
    end

    UpdatePips()
    container._updatePips = UpdatePips
    container._pips = pips
    container._pipSize = pipSize
    container._pipH = pipH
    container._gap = gap
    container._pad = pad
    -- Stash for the engine-slot warrior charge overlay (ns._WCUF_Sync below):
    -- power identity, style gate and the resolved look, so the sync adapter
    -- never re-derives them.
    container._powerType = powerType
    container._style = style
    container._cpR, container._cpG, container._cpB = cr, cg, cb
    container._emptyCol = emptyCol
    container._sepCol = bgCol

    -- Reposition pips to fill a given width (for "above" position)
    -- Uses Snap() to round all positions to physical pixel boundaries
    -- so gaps between pips are guaranteed identical.
    container._repositionForWidth = function(targetW)
        -- shownPipCount, not #pips: the table is a high-water mark, so a shrunk
        -- max would divide the width by the old pip count and leave a gap.
        local n = shownPipCount
        if n <= 0 then return end
        local efs = container:GetEffectiveScale()
        if efs <= 0 then efs = 1 end
        local function Snap(v) return math_floor(v * efs + 0.5) / efs end
        local intW = math_floor(targetW)
        local gapPx = Snap(gap)
        local totalGapW = (n - 1) * gapPx
        local totalPipW = intW - totalGapW
        local basePipW = totalPipW / n
        for i = 1, n do
            local leftEdge = Snap((i - 1) * (basePipW + gapPx))
            local rightEdge = Snap((i - 1) * (basePipW + gapPx) + basePipW)
            local w = rightEdge - leftEdge
            pips[i]:ClearAllPoints()
            pips[i]:SetSize(w, pipH)
            pips[i]:SetPoint("TOPLEFT", container, "TOPLEFT", leftEdge, 0)
        end
        container:SetWidth(intW)
        container:SetHeight(pipH)
    end

    return container
end

-- Warrior charge buffs: hand the engine-slot module (ResourceBars) the built
-- class-power row so the true server count fills it C-side (see
-- EUI_ResourceBars_WarriorCharges.lua). Guarded on _G._EWC: with ResourceBars
-- disabled the simulator path stays in charge untouched. The circles style
-- keeps the legacy pips too -- a continuous engine fill cannot render per-pip
-- circle sprites. Called at the class-power call sites AFTER
-- PositionClassPowerBar, so "above" stretching has already settled the width.
ns._WCUF_Sync = function(container)
    local ewc = _G._EWC
    if not (ewc and container) then return end
    local powerType = container._powerType
    if (powerType ~= "WHIRLWIND_STACKS" and powerType ~= "SWEEPING_STRIKES")
       or container._style == "circles" then
        ewc.Gate("uf")
        return
    end
    local position = db.profile.player.classPowerPosition or "top"
    local stretched = (container._style == "modern" and position == "above")
        and container:GetWidth() or nil
    ewc.Sync("uf", container, powerType, {
        texPath = "Interface\\Buttons\\WHITE8x8",
        r = container._cpR, g = container._cpG, b = container._cpB, a = 1,
        ori = "HORIZONTAL",
        sep = {
            r = container._sepCol and container._sepCol.r or 0.082,
            g = container._sepCol and container._sepCol.g or 0.082,
            b = container._sepCol and container._sepCol.b or 0.082,
            a = container._sepCol and container._sepCol.a or 1,
            w = container._gap or 2,
            cellW = container._pipSize,
            gap = container._gap,
            pad = container._pad,
            stretch = stretched,
            empty = container._emptyCol,
            emptyInset = (container._pad or 0) / 2,
        },
    })
    -- After arming: stash the live color for the queued build's bake and the
    -- out-of-restriction live-recolor path (opts colors are the belt).
    ewc.Recolor("uf", powerType, container._cpR or 1, container._cpG or 1, container._cpB or 1, 1)
end

-- Custom enemy reaction colors: override the shared reaction/tapped color table from
-- db.profile.enemyColors, then repaint live frames. Each entry defaults to Blizzard
-- FACTION_BAR_COLORS when unset, so this is idempotent and reset-safe (re-applies the
-- active profile's colors on profile swap). Hostile = reactions 1-3, Neutral = 4, Friendly = 5-8.
local function ApplyEnemyColors()
    if not (ns.Colors and ns.Colors.reaction and FACTION_BAR_COLORS) then return end
    local ec = (db and db.profile and db.profile.enemyColors) or {}
    local function setIdx(idx, custom)
        local f = FACTION_BAR_COLORS[idx]
        local r = (custom and custom.r) or (f and f.r) or 1
        local g = (custom and custom.g) or (f and f.g) or 1
        local b = (custom and custom.b) or (f and f.b) or 1
        ns.Colors.reaction[idx] = CreateColor(r, g, b)
    end
    for i = 1, 3 do setIdx(i, ec.hostile)  end
    setIdx(4, ec.neutral)
    for i = 5, 8 do setIdx(i, ec.friendly) end
    local tc = ec.tapped
    ns.Colors.tapped = CreateColor((tc and tc.r) or 0.6, (tc and tc.g) or 0.6, (tc and tc.b) or 0.6)
    ns.Engine.ForceAll("OnShow")
end
ns.ApplyEnemyColors = ApplyEnemyColors

I.CreateCustomClassPower, I.DestroyCustomClassPower = CreateCustomClassPower, DestroyCustomClassPower
I.ApplyEnemyColors = ApplyEnemyColors
