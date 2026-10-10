if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_RaidFrames_Reload.lua
--
--  ReloadFrames, the raid size tiers and the tier offset.
--  Reads the earlier Raid Frames files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- EllesmereUIRaidFrames.lua or an earlier Raid Frames file failed to load.
if not I or I.broken then return end
I.broken = true

local floor        = math.floor
local min          = math.min
local pairs        = pairs
local ipairs       = ipairs
local type         = type
local UnitExists            = UnitExists
local InCombatLockdown      = InCombatLockdown

local allButtons, ApplyFont, eventFrame = I.allButtons, I.ApplyFont, I.eventFrame
local GetFFD, IsPowerBarEnabled, PixelSnap = I.GetFFD, I.IsPowerBarEnabled, I.PixelSnap
local ResolveHealthTexture, unitToButton = I.ResolveHealthTexture, I.unitToButton
local LayoutTopNameBar, StyleButton = I.LayoutTopNameBar, I.StyleButton
local RebuildUnitMap, UpdateAllButtons = I.RebuildUnitMap, I.UpdateAllButtons
local LayoutGroups, MOVER_GROUPS = I.LayoutGroups, I.MOVER_GROUPS

local db
I.dbSetters[#I.dbSetters + 1] = function(v) db = v end
local containerFrame
I.containerFrameSetters[#I.containerFrameSetters + 1] = function(v) containerFrame = v end

-- Assigned in EUI_RaidFrames_Visibility.lua (see SetRangeUpdate).
local RangeUpdate

-------------------------------------------------------------------------------
--  Reload: re-apply all settings to existing buttons
-------------------------------------------------------------------------------
-- skipButtons (login window only): run the layout/tier/proxy machinery but
-- skip the per-button restyle loop -- the insecure styling bodies run in the
-- deferred login pass, which then calls this again in full.
ns._emptyList = ns._emptyList or {}
local function ReloadFrames(skipButtons)
    local s = ns._scaledProfile
    -- Keep UNIT_FLAGS registration in lockstep with the combat-icon toggle so a
    -- disabled option listens for nothing (runs no event code).
    if ns.UpdateCombatEventRegistration then ns.UpdateCombatEventRegistration() end
    -- Hide Groups 5-8 in Mythic Raid hears difficulty switches only while on.
    if db.profile.mythicRaidHideGroups then eventFrame:RegisterEvent("PLAYER_DIFFICULTY_CHANGED")
    else eventFrame:UnregisterEvent("PLAYER_DIFFICULTY_CHANGED") end
    -- Rebuild dispel-color curves so custom-color edits take effect immediately.
    if ns._RebuildDispelCurves then ns._RebuildDispelCurves() end
    -- Recalculate active tier from current group size + overrides
    local numMembers = ns._GetEffectiveRaidSize()
    local prevW, prevH = ns._activeSizeW, ns._activeSizeH
    if numMembers > 0 then
        ns._activeSizeW, ns._activeSizeH = ns._GetRaidSizeFrameDimensions(numMembers)
        -- Active tier override (per-tier growth) via the single cascade authority.
        local _, activeTierOv = ns._RFResolveTierOverride(numMembers)
        ns._activeTierOverride = activeTierOv
    else
        ns._activeSizeW, ns._activeSizeH = nil, nil
        ns._activeTierOverride = nil
    end
    local bw = PixelSnap(ns._activeSizeW or s.frameWidth or 72)
    local bh = PixelSnap(ns._activeSizeH or s.frameHeight or 46)

    -- Auto-resize indicators: scale factor based on active tier vs base 20-man
    -- Read base dimensions from raw db.profile (not proxy, which returns active tier)
    local sizeScale = 1
    if ns._activeSizeW and ns._activeSizeH then
        local baseW = db.profile.frameWidth or 72
        local baseH = db.profile.frameHeight or 46
        local scale = math.min(ns._activeSizeW / baseW, ns._activeSizeH / baseH)
        sizeScale = math.max(math.min(scale, 1.5), 0.7)
    end
    -- Auto Resize Icons (two independent checkboxes): Tracked Buffs gates the
    -- Buff Manager scale; Indicators & Auras gates indicator/aura/text sizes.
    -- Tracked Buffs defaults on (nil treated as on) to preserve the prior
    -- hardcoded always-on behavior.
    ns._bmScale = (db.profile.autoResizeTrackedBuffs ~= false) and sizeScale or 1
    ns._indicatorScale = db.profile.autoResizeIndicators and sizeScale or 1
    if ns._RefreshProxyModes then ns._RefreshProxyModes() end

    -- Mode flips (Merge Groups toggle, profile swaps) can need a header set
    -- that was not built at login; materialize it before the restyle loop so
    -- the new buttons take this reload's styling like everything else.
    ns._BuildHeaderSet((db.profile.mergeGroups and true) or false)

    local powerH = IsPowerBarEnabled(s) and PixelSnap(s.powerHeight or 4) or 0
    local healthH = PixelSnap(bh - powerH)
    local texPath = ResolveHealthTexture()

    for _, btn in ipairs(skipButtons and ns._emptyList or allButtons) do
        local d = GetFFD(btn)
        if not d.styled then
            ns._StyleButtonSecure(btn)
            StyleButton(btn)
        end

        -- Window/initialConfigFunction own sizes in combat; skipping here is
        -- safe (out of combat the resize applies normally).
        if not InCombatLockdown() then
            btn:SetSize(bw, bh)
        end

        -- Health bar height/anchor + Top Name Bar. The helper reserves the top
        -- bar's height from the top of the health area and styles the bar.
        LayoutTopNameBar(s, bh, powerH, d.health, d.topNameBar, d.topNameBarBg, d.topNameBarText, d.power)
        if d.health then
            d.health:SetStatusBarTexture(texPath)
            d.health:GetStatusBarTexture():SetHorizTile(false)
            -- Re-anchor absorb clips to the new fill texture object
            if d.ReanchorAbsorbToFill then d.ReanchorAbsorbToFill() end
        end

        -- Background: through its stamped owner (dark-mode aware), AFTER the
        -- fill texture swap so the anchors bind the new fill edge. Stamps are
        -- cleared first so the restyle re-applies anchors + color; a direct
        -- SetColorTexture here is never overwritten by the stamped health tick.
        if d.bg then
            d._bgSt, d._bgA = nil, nil
            local u = btn:GetAttribute("unit")
            if u and UnitExists(u) then ns._ApplyHealthBg(d, d.health, s, u) end
        end

        -- Power bar (always hide here; UpdateButton handles per-role show). This is a
        -- second writer of health height alongside UpdateButton's own cached transition
        -- (LayoutTopNameBar above sized health assuming power reserved), so drop the
        -- cache or UpdateAllButtons below sees applied == computed and never corrects it.
        d._appliedHidePower = nil
        if d.power then
            d.power:Hide()
            if powerH > 0 then
                d.power:SetHeight(powerH)
                d.power:SetStatusBarTexture(texPath)
                d.power:GetStatusBarTexture():SetHorizTile(false)
            end
        end
        if d.powerBg then
            d.powerBg:SetColorTexture((s.powerBgColor or {}).r or 0, (s.powerBgColor or {}).g or 0, (s.powerBgColor or {}).b or 0, (s.powerBgDarkness or 70) / 100)
            d._pwBgTintType = nil
        end
        if d.UpdatePowerBorder then d.UpdatePowerBorder(true) end

        -- Name text
        if d.nameText then
            ApplyFont(d.nameText, s.nameSize or 10)
            if d.AnchorNameText then d.AnchorNameText() end
        end

        -- Health text
        if d.healthText then
            ApplyFont(d.healthText, s.healthTextSize or 9)
            if d.AnchorHealthText then d.AnchorHealthText() end
        end

        -- Power text (exists once a mode has needed it): hidden with the bar above until
        -- UpdateAllButtons below shows it again, and restyled.
        if d.powerText then
            d.powerText:Hide(); d._pwtMode = nil
            ApplyFont(d.powerText, s.powerTextSize or 8)
            ns._RFAnchorPowerText(d)
        end

        -- Level text (exists once a position has needed it): restyled; the full paint
        -- that follows shows or hides it by position.
        if d.levelText then
            ApplyFont(d.levelText, s.levelTextSize or 10)
            ns._RFAnchorLevelText(d)
        end

        -- Heal absorb text
        if d.healAbsorbText then
            ApplyFont(d.healAbsorbText, s.healAbsorbTextSize or 9)
            if d.AnchorHealAbsorbText then d.AnchorHealAbsorbText() end
        end

        -- Status text (DEAD/OFFLINE/AFK)
        if d.statusText then
            local stc = s.statusTextColor or { r = 1, g = 1, b = 1 }
            ApplyFont(d.statusText, s.statusTextSize or 14)
            d.statusText:SetTextColor(stc.r, stc.g, stc.b)
            if d.AnchorStatusText then d.AnchorStatusText() end
        end

        -- Role icon size + position
        if d.roleIcon then
            local riSz = PixelSnap(s.roleIconSize or 14)
            d.roleIcon:SetSize(riSz, riSz)
            if d.AnchorRoleIcon then d.AnchorRoleIcon() end
        end

        -- Leader icon size + position
        if d.leaderIcon then
            local liSz = PixelSnap(s.leaderIconSize or 14)
            d.leaderIcon:SetSize(liSz, liSz)
            d.leaderIcon:ClearAllPoints()
            local liPos = (s.leaderIconPosition or "top"):upper()
            d.leaderIcon:SetPoint(liPos, ns.RF_AnchorHost(d.health, s), liPos, s.leaderIconOffsetX or 0, s.leaderIconOffsetY or 0)
            -- Re-assert the host's strata/level above the border
            if d.leaderHost then ns.ApplyLeaderStrata(d.leaderHost) end
        end

        -- Raid marker size + position
        if d.raidMarker then
            local rmSz = PixelSnap(s.raidMarkerSize or 16)
            d.raidMarker:SetSize(rmSz, rmSz)
            if d.AnchorRaidMarker then d.AnchorRaidMarker() end
        end

        -- Ready check / summon size + position
        if d.readyCheck then
            local rcSz = PixelSnap(s.readyCheckSize or 20)
            d.readyCheck:SetSize(rcSz, rcSz)
            if d.AnchorReadyCheck then d.AnchorReadyCheck() end
        end

        -- Combat icon size + position
        if d.combatIcon then
            local cciSz = PixelSnap(s.combatIndicatorSize or 16)
            d.combatIcon:SetSize(cciSz, cciSz)
            if d.AnchorCombatIcon then d.AnchorCombatIcon() end
        end

        -- Ping marker size + position (overlay exists only after a first ping)
        if d.pingFrame then ns._RFAnchorPing(d) end
        if ns.RF_FvMissingAnchor then ns.RF_FvMissingAnchor(btn, d) end

        -- Border
        if d.UpdateBorder then d.UpdateBorder() end
    end

    -- Re-layout headers (may switch between flat/grouped)
    LayoutGroups()
    -- Apply tier-based position offset
    if ns._ApplyTierOffset then ns._ApplyTierOffset() end
    RebuildUnitMap()
    UpdateAllButtons()
    -- Immediate range update so new buttons don't flash full alpha
    RangeUpdate()

    -- Friendly Boss Frames and Extra Frames inherit size/growth/spacing/
    -- border/text settings; restyle + re-anchor them with everything else
    -- (growth changes move the anchor points, not just the anchored-to header).
    if ns.FB_Apply then ns.FB_Apply() end
    if ns.XF_Apply then ns.XF_Apply() end
    -- Pet frames (the ones styled from the raid settings restyle here, the rest in the party
    -- reload): the login window's pass skips them (OnEnable builds them once the party frames
    -- exist, which the Beside Owner pets need).
    if not skipButtons then ns.PF_Apply(true) end

    -- 12.1 aura containers reload with every real pass (direct call inside
    -- the body -- immune to the Options file's setup-time capture of ns.ReloadFrames).
    if ns.RFC_ReloadAll then ns.RFC_ReloadAll() end
end

ns.ReloadFrames = ReloadFrames
ns.PixelSnap = PixelSnap
ns._allButtons = allButtons
-- The raid unit map (RebuildUnitMap wipes it in place, so this stays live).
ns._raidUnitToButton = unitToButton

-- Global Dark Mode master: RF stores Dark Mode as a fill-color MODE
-- (healthColorMode == "dark"), not a boolean -- enabling remembers the prior
-- mode, disabling restores it, never clobbering a Classic/Custom choice. The
-- party override (party_healthColorMode, present only when the party color
-- section is decoupled) flips the same way. db is set at PLAYER_LOGIN; the
-- closures read it lazily.
EllesmereUI.RegisterDarkModeToggle({
    id = "raidFrames",
    isOn = function()
        return (db and db.profile and db.profile.healthColorMode == "dark") or false
    end,
    setOn = function(on)
        if not (db and db.profile) then return end
        local p = db.profile
        if on then
            if p.healthColorMode ~= "dark" then
                p._darkPrevHealthColorMode = p.healthColorMode or "class"
                p.healthColorMode = "dark"
            end
            if rawget(p, "party_healthColorMode") ~= nil and p.party_healthColorMode ~= "dark" then
                p._darkPrevPartyHealthColorMode = p.party_healthColorMode
                p.party_healthColorMode = "dark"
            end
            -- The party target frames' own Fill Color flips the same way.
            if p.partyTargetHealthColorMode ~= "dark" then
                p._darkPrevPartyTargetHealthColorMode = p.partyTargetHealthColorMode or "class"
                p.partyTargetHealthColorMode = "dark"
            end
        else
            if p.healthColorMode == "dark" then
                p.healthColorMode = p._darkPrevHealthColorMode or "class"
            end
            p._darkPrevHealthColorMode = nil
            if rawget(p, "party_healthColorMode") == "dark" then
                p.party_healthColorMode = p._darkPrevPartyHealthColorMode or "class"
            end
            p._darkPrevPartyHealthColorMode = nil
            if p.partyTargetHealthColorMode == "dark" then
                p.partyTargetHealthColorMode = p._darkPrevPartyTargetHealthColorMode or "class"
            end
            p._darkPrevPartyTargetHealthColorMode = nil
        end
        if ns.ReloadFrames then ns.ReloadFrames() end
        if ns.ReloadPartyFrames then ns.ReloadPartyFrames() end
    end,
})

-- Lightweight resize: only changes button/health/power dimensions + layout.
-- No texture, border, font, or anchor changes. Safe for slider hot path.
ns._ResizeButtons = function(w, h)
    if InCombatLockdown() then return end
    local bw = PixelSnap(w)
    local bh = PixelSnap(h)
    local s = db.profile
    local powerH = IsPowerBarEnabled(s) and PixelSnap(s.powerHeight or 4) or 0
    local healthH = PixelSnap(bh - ns.RF_HealthPowerInset(s, powerH))
    local topBarH = (s.topNameBarEnabled and PixelSnap(s.topNameBarHeight or 20)) or 0
    local xfset = s.extraFrames
    for _, btn in ipairs(allButtons) do
        local d = GetFFD(btn)
        if d.styled then
            local xbw, xbh, xhealthH = bw, bh, healthH
            -- Extra Frames duplicates carry their size offset through the
            -- live slider path too (XF.Layout re-applies it on full reloads).
            if d._isExtra and xfset then
                xbw = PixelSnap(math.max(10, w + (xfset.extraWidth or 0)))
                xbh = PixelSnap(math.max(10, h + (xfset.extraHeight or 0)))
                xhealthH = PixelSnap(xbh - ns.RF_HealthPowerInset(s, powerH))
            end
            btn:SetSize(xbw, xbh)
            -- Full height when the power bar is hidden for this role (mirrors
            -- _ResizePartyButtons; avoids a dark strip on OFF-role units since
            -- d.power always exists). Top Name Bar reserves its height from the
            -- top (health top anchor stays -topBarH; only correct height here).
            if d.health then
                d.health:SetHeight(((d.power and d.power:IsShown()) and xhealthH or xbh) - topBarH)
            end
            if d.nameText then d.nameText:SetWidth(xbw * ns.RF_NAME_WIDTH_FRACTION) end
        end
    end
    ns._activeSizeW = w
    ns._activeSizeH = h
    if ns._RefreshProxyModes then ns._RefreshProxyModes() end
    LayoutGroups()
    -- Container footprint may have changed: re-derive the growth-corner anchor
    -- so the pinned corner holds during live slider drags and the unlock
    -- framework's OnSizeChanged can never leave a stale centered position.
    if ns._ApplyTierOffset then ns._ApplyTierOffset() end
end

-- Lightweight party resize: only changes button/health/power dimensions + container.
-- No sort/self-first re-chain. Safe for slider hot path.
ns._ResizePartyButtons = function(w, h)
    if InCombatLockdown() then return end
    if not ns._partyAllButtons then return end
    local bw = PixelSnap(w)
    local bh = PixelSnap(h)
    local s = db.profile
    local powerH = IsPowerBarEnabled(s) and PixelSnap(s.powerHeight or 4) or 0
    local healthH = PixelSnap(bh - ns.RF_HealthPowerInset(s, powerH))
    local topBarH = (s.topNameBarEnabled and PixelSnap(s.topNameBarHeight or 20)) or 0
    -- Auto Resize scale depends on frame size; recompute on this lightweight
    -- width/height slider path (which skips the full reload).
    if ns._UpdatePartyIndicatorScale then ns._UpdatePartyIndicatorScale() end
    local autoResize = s.partyAutoResizeIndicators
    -- The bars' width: an attached portrait takes its share of the box.
    local _, _, _, pres = ns.RF_PartyDims(s)
    local barW = bw - ((pres and pres > 0) and PixelSnap(pres) or 0)
    for _, btn in ipairs(ns._partyAllButtons) do
        local d = GetFFD(btn)
        if d.styled then
            btn:SetSize(bw, bh)
            if d.kit then
                -- Party Frames kit: its own bar rects, spots and name width
                -- (Frame Scale drags land here).
                ns.RF_ApplyPartyKit(btn, d, ns._scaledPartyProxy)
            else
                -- Use full height if power bar is hidden for this button's role; the
                -- Top Name Bar always reserves topBarH from the top.
                if d.health then
                    local hh = ((d.power and d.power:IsShown()) and healthH or bh) - topBarH
                    d.health:SetHeight(hh)
                end
                if d.nameText then d.nameText:SetWidth(barW * ns.RF_NAME_WIDTH_FRACTION) end
                -- Party portrait: the attached square follows the height.
                if d.pt then ns.RF_PtApply(btn, d, ns._scaledPartyProxy, bw, bh, nil) end
            end
            -- Live-rescale indicators/auras. No-op for hidden buttons / no unit
            -- (e.g. options menu while not grouped), so cheap there.
            if autoResize then
                -- Scale derives from frame size (recomputed above): re-apply
                -- the scaled sizes during the drag (same set as the full reload).
                local pp = ns._scaledPartyProxy
                if d.roleIcon then
                    local riSz = PixelSnap(pp.roleIconSize or 14)
                    d.roleIcon:SetSize(riSz, riSz)
                    if d.AnchorRoleIcon then d.AnchorRoleIcon() end
                end
                if d.leaderIcon then
                    local liSz = PixelSnap(pp.leaderIconSize or 14)
                    d.leaderIcon:SetSize(liSz, liSz)
                end
                if d.raidMarker then
                    local rmSz = PixelSnap(pp.raidMarkerSize or 16)
                    d.raidMarker:SetSize(rmSz, rmSz)
                end
                if d.combatIcon then
                    local cciSz = PixelSnap(pp.combatIndicatorSize or 16)
                    d.combatIcon:SetSize(cciSz, cciSz)
                    if d.AnchorCombatIcon then d.AnchorCombatIcon() end
                end
                if d.nameText then ApplyFont(d.nameText, pp.nameSize or 10) end
                if d.healthText then ApplyFont(d.healthText, pp.healthTextSize or 9) end
                if d.powerText then ApplyFont(d.powerText, pp.powerTextSize or 8) end
                if d.levelText then ApplyFont(d.levelText, pp.levelTextSize or 10) end
                if d.healAbsorbText then ApplyFont(d.healAbsorbText, pp.healAbsorbTextSize or 9) end
                if d.statusText then ApplyFont(d.statusText, pp.statusTextSize or 14) end
            end
        end
    end
    -- Container resize deferred to drag end (SetSize on the container makes
    -- SecureGroupHeaderTemplate re-process children -> blink). Slot offsets +
    -- the header's own size DO follow the live size: keeps the self button
    -- aligned with the stack and the centered child anchors growing from the
    -- correct origin. Pure anchor tracking -- no secure re-process, no blink.
    if ns._PositionPartySlots then
        local _, _, pcs = ns.RF_PartyDims(s)
        ns._PositionPartySlots(bw, bh, PixelSnap(pcs) + ns.PT_AlongPitch(s), ns._PartyGrowth(s))
    end
    if ns._partySharedBorderOn then ns.RF_QueuePartyBorder() end
end

-- Convert a saved (point, relPoint, x, y) UIParent anchor to the TOPLEFT
-- screen coords (UIParent bottom-left space, same space GetLeft/GetTop use)
-- the frame would occupy at the given size.
ns._RFPosTopLeft = function(pos, w, h)
    local uw, uh = UIParent:GetWidth(), UIParent:GetHeight()
    local function frac(p)
        p = p or "CENTER"
        local fx = (p:find("LEFT") and 0) or (p:find("RIGHT") and 1) or 0.5
        local fy = (p:find("BOTTOM") and 0) or (p:find("TOP") and 1) or 0.5
        return fx, fy
    end
    local rfx, rfy = frac(pos.relPoint)
    local pfx, pfy = frac(pos.point)
    local ax = uw * rfx + (pos.x or 0)
    local ay = uh * rfy + (pos.y or 0)
    return ax - pfx * w, ay + (1 - pfy) * h
end

-- Groups stacked in one column before the flow steps to the next column, for
-- the grid group growth ("Down and then Right"): G1/G2 fill the first column
-- top to bottom, G3/G4 the column to its right. Fixed at 2 so a 20-man raid
-- lands on the classic 2x2 block; a plain direction is the same flow with one
-- group per column (every other value below).
ns._RF_GRID_ROWS = 2

-- Group slot origins (relative to the growth corner, before normalization) for a
-- group growth direction, plus the origin those slots normalize against (min x,
-- max y) so slot 0 always sits at the growth corner whichever way the flow runs.
-- THE single copy of the per-slot step math -- the live layout, the 20-player
-- preview and the size preview all place groups through it, so they cannot drift.
-- `count` slots are generated (LayoutGroups can place up to 8 visible groups
-- into the 4-group box) but only the first MOVER_GROUPS of them -- what the box
-- is actually sized for -- set the origin, so a group past the box keeps the
-- same per-slot step instead of rescaling the box in front of it. `out`, when
-- given, is refilled in place (its slot pairs reused) and returned instead of a
-- new table.
ns._RFGroupFlow = function(groupGrowth, groupW, groupH, gs, count, out)
    local n = count or MOVER_GROUPS
    local stepX, stepY = 0, 0
    if groupGrowth == "DOWNRIGHT" then
        -- Column advance is horizontal; the rows inside a column run down.
        stepX, stepY = (groupW + gs), -(groupH + gs)
    elseif groupGrowth == "DOWN" then   stepY = -(groupH + gs)
    elseif groupGrowth == "UP" then     stepY =  (groupH + gs)
    elseif groupGrowth == "RIGHT" then  stepX =  (groupW + gs)
    else                                stepX = -(groupW + gs)   -- LEFT
    end
    local slots, minX, maxY = out or {}, 0, 0
    for i = 0, n - 1 do
        local px, py
        if groupGrowth == "DOWNRIGHT" then
            px = floor(i / ns._RF_GRID_ROWS) * stepX
            py = (i % ns._RF_GRID_ROWS) * stepY
        else
            px, py = i * stepX, i * stepY
        end
        local p = slots[i]
        if p then
            p[1], p[2] = px, py
        else
            slots[i] = { px, py }
        end
    end
    local nc = min(MOVER_GROUPS, n)
    for i = 0, nc - 1 do
        local px, py = slots[i][1], slots[i][2]
        if px < minX then minX = px end
        if py > maxY then maxY = py end
    end
    return slots, minX, maxY
end

-- Footprint of the 4-group mover box for a frame size and growth pair. Callers
-- that also derive a corner from the same pair (ns._RFCornerTerms/_RFGrowthCorner)
-- must self-heal (ns._RFEffectiveGrowth) BEFORE calling either, so the size and
-- the corner agree -- this function does not self-heal internally to avoid a
-- caller healing one but not the other.
ns._RFFootprint = function(bw, bh, unitGrowth, groupGrowth, cs, gs)
    bw, bh = PixelSnap(bw), PixelSnap(bh)
    local groupW, groupH
    if unitGrowth == "RIGHT" or unitGrowth == "LEFT" then
        groupW = 5 * bw + 4 * cs
        groupH = bh
    else
        groupW = bw
        groupH = 5 * bh + 4 * cs
    end
    if groupGrowth == "DOWNRIGHT" then
        -- Grid flow: one column of ns._RF_GRID_ROWS groups, then the next
        -- column to its right (see ns._RFGroupFlow). MOVER_GROUPS (4) fills
        -- two columns at any row count that divides it.
        local rows = ns._RF_GRID_ROWS
        local cols = floor((MOVER_GROUPS + rows - 1) / rows)
        return PixelSnap(cols * groupW + (cols - 1) * gs),
               PixelSnap(rows * groupH + (rows - 1) * gs)
    end
    if groupGrowth == "DOWN" or groupGrowth == "UP" then
        return PixelSnap(groupW), PixelSnap(MOVER_GROUPS * groupH + (MOVER_GROUPS - 1) * gs)
    end
    return PixelSnap(MOVER_GROUPS * groupW + (MOVER_GROUPS - 1) * gs), PixelSnap(groupH)
end

-- TOPLEFT of the BASE (20-man) footprint at the saved unlock position: the shared
-- growth origin for every size tier and the previews. Also returns the base footprint's
-- width/height so corner math never recomputes it (extra return values -- existing
-- two-value callers are unaffected). Returns nil when no position has been saved yet.
ns._RFBaseTopLeft = function()
    local s = db.profile
    local pos = s.unlockPos
    if not pos then return nil end
    local cs = PixelSnap(ns.RF_RaidSpacing(s))
    local gs = PixelSnap(ns.RF_RaidSpacing(s, true))
    local ug, gg = ns._RFEffectiveGrowth(s.unitGrowth or "DOWN", s.groupGrowth or "RIGHT", s.mergeGroups)
    local w, h = ns._RFFootprint(s.frameWidth or 72, s.frameHeight or 46, ug, gg, cs, gs)
    local l, t = ns._RFPosTopLeft(pos, w, h)
    return l, t, w, h
end

-- Shared growth-direction helpers. A single source of truth for "is this
-- direction vertical" and for deriving the flat header's point/xOffset/yOffset
-- and columnAnchorPoint from a growth pair -- both _LayoutGroupsImpl and
-- _BuildHeaderSet's header-creation bootstrap need the identical derivation,
-- and previously hand-duplicated it.
ns._RFGrowthIsVertical = function(g)
    return g == "DOWN" or g == "UP"
end

-- First-button point/xOffset/yOffset for a header growing along unitGrowth.
ns._RFHeaderPoint = function(unitGrowth, cs)
    if unitGrowth == "DOWN" then
        return "TOP", 0, -cs
    elseif unitGrowth == "UP" then
        return "BOTTOM", 0, cs
    elseif unitGrowth == "RIGHT" then
        return "LEFT", cs, 0
    else -- LEFT
        return "RIGHT", -cs, 0
    end
end

-- Blizzard's flat header can only wrap into columns when columnAnchorPoint runs
-- perpendicular to unitGrowth -- see ns._RFEffectiveGrowth below for why merged
-- mode never actually reaches a same-axis pair here in practice.
ns._RFColAnchor = function(unitGrowth, groupGrowth)
    if groupGrowth == "DOWN" or groupGrowth == "RIGHT" then
        if ns._RFGrowthIsVertical(unitGrowth) then return "LEFT" end
        return "TOP"
    else -- UP or LEFT
        if ns._RFGrowthIsVertical(unitGrowth) then return "RIGHT" end
        return "BOTTOM"
    end
end

-- Self-heals a same-axis Group/Unit Growth pair when Merge Groups is on (see
-- _RFColAnchor above), applied as a read-time backstop for a pair that reached
-- here without a guarded write (a stale per-tier override, a spec override,
-- hand-edited SavedVariables). Group Growth wins here; the options UI's
-- write-time KeepGrowthPerpendicular uses the same resolution EXCEPT its Unit
-- Growth dropdown, which deliberately lets Unit Growth win instead. Also maps the
-- grid flow ("Down and then Right") onto the single column axis the flat header
-- can render; no-op if not merged.
ns._RFEffectiveGrowth = function(unitGrowth, groupGrowth, merged)
    if not merged then return unitGrowth, groupGrowth end
    -- The grid flow needs two axes; Blizzard's flat header only has one column
    -- axis, so merged mode degrades it to the plain RIGHT run it CAN render --
    -- same shape as the same-axis fallback below.
    if groupGrowth == "DOWNRIGHT" then groupGrowth = "RIGHT" end
    if ns._RFGrowthIsVertical(unitGrowth) == ns._RFGrowthIsVertical(groupGrowth) then
        unitGrowth = ns._RFGrowthIsVertical(unitGrowth) and "RIGHT" or "DOWN"
    end
    return unitGrowth, groupGrowth
end

-- Pinned screen corner implied by a growth pair: frames grow AWAY from this corner, so
-- it stays fixed when a tier's footprint differs from the base. Horizontal side = whichever
-- growth is horizontal (RIGHT pins LEFT edge, LEFT pins RIGHT edge); vertical side likewise
-- (DOWN pins TOP, UP pins BOTTOM). Every ns._RFEffectiveGrowth caller heals a same-axis pair
-- before reaching here whenever merged is true, so this only ever sees one for separated mode
-- (merged=false is a no-op for _RFEffectiveGrowth), where every combination of the two
-- axes is legitimate -- including the grid flow, whose column advance is horizontal (so
-- it pins LEFT like RIGHT) and whose rows run down (so it pins TOP like DOWN). This
-- tie-break (UP beats BOTTOM, LEFT beats RIGHT, default TOP+LEFT) is what existing
-- per-tier offsets are calibrated against -- matching Blizzard's own same-axis corner instead
-- would be dead code here for merged and a silent position-shift regression for separated.
ns._RFGrowthCorner = function(unitGrowth, groupGrowth)
    local h = (unitGrowth == "LEFT" or groupGrowth == "LEFT") and "RIGHT" or "LEFT"
    local v = (unitGrowth == "UP" or groupGrowth == "UP") and "BOTTOM" or "TOP"
    return v .. h
end

-- Signed corner terms: how far a tier footprint's TOPLEFT shifts from the base
-- footprint's TOPLEFT so the growth-derived corner stays pinned. THE single copy of the
-- corner arithmetic -- the forward origin (_RFTierTopLeft), the one-time offset rebase
-- (conversion #2 in _NormalizeTierOffsetAnchors) and the mover save-path inverse
-- (_RFRebaseSavedCenter) all read these two values. Both terms are zero when the
-- footprints match, so the base tier is exact by arithmetic.
ns._RFCornerTerms = function(tw, th, bw, bh, unitGrowth, groupGrowth)
    local corner = ns._RFGrowthCorner(unitGrowth, groupGrowth)
    local kx = (corner:find("RIGHT") and (bw - tw)) or 0
    local ky = (corner:find("BOTTOM") and -(bh - th)) or 0
    return kx, ky
end

-- THE centralized growth-corner origin: returns the TOPLEFT (UIParent bottom-left space)
-- for a tier footprint (tw, th) whose growth-derived corner is pinned at the BASE
-- footprint's same corner, plus the tier's saved offsets. Every consumer (live
-- _ApplyTierOffset, size previews) anchors through this one function so previews land
-- exactly where live frames land. Base footprint / zero offsets: every corner term
-- cancels, plain base top-left -- profiles without raidSizeOverrides unaffected. Returns
-- nil with no saved unlock position.
ns._RFTierTopLeft = function(tw, th, unitGrowth, groupGrowth, ox, oy)
    local bl, bt, bw, bh = ns._RFBaseTopLeft()
    if not bl then return nil end
    local kx, ky = ns._RFCornerTerms(tw, th, bw, bh, unitGrowth, groupGrowth)
    return bl + (ox or 0) + kx, bt + (oy or 0) + ky
end

-- Resolve the active size tier bucket and its override table, cascading
-- toward 20 (10 falls back to 15, 30 falls back to 25). The single copy of
-- the cascade -- _GetRaidSizeFrameDimensions, ReloadFrames and
-- _ApplyTierOffset all route through here. Returns tier, override; the
-- override is nil for the base 20 tier or when none is defined.
ns._RFResolveTierOverride = function(numMembers)
    local overrides = db.profile.raidSizeOverrides
    if not overrides or not numMembers or numMembers <= 0 then return 20, nil end
    -- User-tunable switch boundaries (per-tier cog sliders): the LOWER tiers
    -- store the highest count they COVER (sizeCap), the UPPER tiers the
    -- count they ENGAGE at (sizeMin). Absent keys reproduce the classic
    -- cascade exactly (10/15/20, 25 engaging at 21, 30 at 26, 40 at 31), so
    -- profiles that never touch the sliders resolve byte-identically.
    local o10, o15, o25, o30, o40 = overrides[10], overrides[15], overrides[25], overrides[30], overrides[40]
    local b10 = (o10 and o10.sizeCap) or 10
    local b15 = (o15 and o15.sizeCap) or 15
    local b25 = (o25 and o25.sizeMin) or 21
    local b30 = (o30 and o30.sizeMin) or 26
    local b40 = (o40 and o40.sizeMin) or 31
    local tier
    if numMembers <= b10 then    tier = 10
    elseif numMembers <= b15 then tier = 15
    elseif numMembers < b25 then tier = 20
    elseif numMembers < b30 then tier = 25
    elseif numMembers < b40 then tier = 30
    else                         tier = 40
    end
    if tier == 20 then return 20, nil end
    local ov
    if tier < 20 then
        ov = overrides[tier] or (tier == 10 and overrides[15]) or nil
    else
        ov = overrides[tier]
        if not ov and tier == 30 then ov = overrides[25] end
        if not ov and tier == 40 then ov = overrides[30] or overrides[25] end
    end
    return tier, ov or nil
end

-- Inverse of the corner scheme, for the unlock mover SAVE path only. The framework
-- measures a dragged container's CENTER from its LIVE bounds -- i.e. on the ACTIVE
-- tier's footprint -- but every apply interprets unlockPos as the BASE footprint's
-- center. Convert a live-measured center to its base-footprint equivalent so the next
-- _ApplyTierOffset reproduces the drop position (within one physical pixel of
-- snapping). With the base tier active, or no overrides defined, every term cancels and
-- the center passes through unchanged -- zero behavior change for base saves.
ns._RFRebaseSavedCenter = function(cx, cy)
    local s = db.profile
    local _, ov = ns._RFResolveTierOverride(ns._GetEffectiveRaidSize())
    if not ov then return cx, cy end
    local cs = PixelSnap(ns.RF_RaidSpacing(s))
    local gs = PixelSnap(ns.RF_RaidSpacing(s, true))
    local bug, bgg = ns._RFEffectiveGrowth(s.unitGrowth or "DOWN", s.groupGrowth or "RIGHT", s.mergeGroups)
    local bw, bh = ns._RFFootprint(s.frameWidth or 72, s.frameHeight or 46, bug, bgg, cs, gs)
    local ug, gg = ns._RFEffectiveGrowth(
        ov.unitGrowth or s.unitGrowth or "DOWN", ov.groupGrowth or s.groupGrowth or "RIGHT", s.mergeGroups)
    local tw, th = ns._RFFootprint(ov.width or s.frameWidth or 72,
        ov.height or s.frameHeight or 46, ug, gg, cs, gs)
    local kx, ky = ns._RFCornerTerms(tw, th, bw, bh, ug, gg)
    return cx - (ov.offsetX or 0) - kx - (tw - bw) / 2,
        cy - (ov.offsetY or 0) - ky - (bh - th) / 2
end

-- Owned creation point for raidSizeOverrides: fresh tables are ALREADY in
-- the current offset scheme, so both one-time conversion markers are
-- stamped at birth -- otherwise the next _NormalizeTierOffsetAnchors pass
-- would "convert" (and silently shift) offsets that were never old-scheme.
ns._EnsureRaidSizeOverrides = function()
    local s = db.profile
    if not s.raidSizeOverrides then
        s.raidSizeOverrides = { _topLeftAnchored = true, _cornerAnchored = true }
    else
        -- Existing table: run any pending conversion now so edits that
        -- follow operate on post-conversion values.
        ns._NormalizeTierOffsetAnchors()
    end
    return s.raidSizeOverrides
end

-- One-time conversions (markers travel INSIDE raidSizeOverrides, so imported/swapped
-- profiles self-convert -- no migration-flag inheritance trap). Each applies at most
-- once, in order, rebasing offsets against the PREVIOUS scheme's post-conversion values
-- so every tier's on-screen position is preserved (within one physical pixel of rounding).
--   #1 (_topLeftAnchored): old "re-anchor container at unlockPos.point" offsets ->
--      offsets relative to the base footprint's TOPLEFT.
--   #2 (_cornerAnchored): TOPLEFT-relative offsets -> offsets relative to the
--      growth-derived pinned corner (ns._RFGrowthCorner). Only tiers whose effective
--      growth pins RIGHT and/or BOTTOM change; DOWN+RIGHT tiers keep identical offsets.
ns._NormalizeTierOffsetAnchors = function()
    local s = db and db.profile
    if not s then return end
    local ov = s.raidSizeOverrides
    if not ov then return end
    -- Heal string-keyed numeric tiers ("25" beside 25): planted by the spec
    -- override system's container fabrication before it learned to use the numeric
    -- form. The module reads tiers numerically, so a phantom never renders yet
    -- captures every override read/write for its tier. With a numeric twin the
    -- phantom is dropped (the twin is the rendered truth; override values re-apply
    -- from their store at the next boundary); without one it becomes the numeric
    -- tier it was meant to be. Must run BEFORE the markers early-return below:
    -- converted profiles are the common carriers.
    local phantoms
    for k, v in pairs(ov) do
        if type(k) == "string" and tonumber(k) ~= nil and type(v) == "table" then
            phantoms = phantoms or {}
            phantoms[#phantoms + 1] = k
        end
    end
    if phantoms then
        for i = 1, #phantoms do
            local k = phantoms[i]
            local n = tonumber(k)
            if ov[n] == nil then ov[n] = ov[k] end
            ov[k] = nil
        end
    end
    if ov._topLeftAnchored and ov._cornerAnchored then return end
    local cs = PixelSnap(ns.RF_RaidSpacing(s))
    local gs = PixelSnap(ns.RF_RaidSpacing(s, true))
    local pos = s.unlockPos
    local bl, bt, bw, bh = ns._RFBaseTopLeft()
    if not ov._topLeftAnchored then
        ov._topLeftAnchored = true
        if pos and bl then
            for _, o in pairs(ov) do
                if type(o) == "table" then
                    local ug, gg = ns._RFEffectiveGrowth(
                        o.unitGrowth or s.unitGrowth or "DOWN",
                        o.groupGrowth or s.groupGrowth or "RIGHT", s.mergeGroups)
                    local tw, th = ns._RFFootprint(
                        o.width or s.frameWidth or 72, o.height or s.frameHeight or 46, ug, gg, cs, gs)
                    local tl, tt = ns._RFPosTopLeft(pos, tw, th)
                    o.offsetX = math.floor((o.offsetX or 0) + (tl - bl) + 0.5)
                    o.offsetY = math.floor((o.offsetY or 0) + (tt - bt) + 0.5)
                end
            end
        end
    end
    if not ov._cornerAnchored then
        ov._cornerAnchored = true
        if pos and bl then
            for _, o in pairs(ov) do
                if type(o) == "table" then
                    local ug, gg = ns._RFEffectiveGrowth(
                        o.unitGrowth or s.unitGrowth or "DOWN",
                        o.groupGrowth or s.groupGrowth or "RIGHT", s.mergeGroups)
                    local tw, th = ns._RFFootprint(
                        o.width or s.frameWidth or 72, o.height or s.frameHeight or 46, ug, gg, cs, gs)
                    local kx, ky = ns._RFCornerTerms(tw, th, bw, bh, ug, gg)
                    if kx ~= 0 then
                        o.offsetX = math.floor((o.offsetX or 0) - kx + 0.5)
                    end
                    if ky ~= 0 then
                        o.offsetY = math.floor((o.offsetY or 0) - ky + 0.5)
                    end
                end
            end
        end
    end
end

-- Apply tier-based position to the container frame. The active tier's 4-group
-- footprint pins its growth-derived corner (ns._RFGrowthCorner, from the tier's
-- EFFECTIVE unit + group growth) at the BASE (20-man) footprint's same corner, plus the tier's saved
-- offsets, via the shared ns._RFTierTopLeft origin -- so a larger/smaller tier grows away
-- from the pinned corner (e.g. RIGHT+DOWN pins top-left, LEFT+UP pins bottom-right).
-- unlockPos itself is untouched (saved tier offsets were rebased once per scheme by
-- _NormalizeTierOffsetAnchors). Base tier or no overrides: every corner term cancels,
-- identical to the plain base top-left.
--
-- While anchored, the unlock anchor system owns the container's position, so the tier
-- offset is folded into the position IT computes rather than applied on top afterwards --
-- applying it after would sit outside the anchor's idempotent guard and reposition every pass forever.
EllesmereUI._anchorExtraOffset = EllesmereUI._anchorExtraOffset or {}
EllesmereUI._anchorExtraOffset["RF_RaidFrames"] = function()
    local _, ov = ns._RFResolveTierOverride(ns._GetEffectiveRaidSize())
    return (ov and ov.offsetX) or 0, (ov and ov.offsetY) or 0
end

ns._ApplyTierOffset = function()
    if not containerFrame or InCombatLockdown() then return end
    -- Element-anchored container: the unlock anchor system owns the POSITION
    -- (absolute coords recomputed from the anchor target), so repositioning
    -- from unlockPos here would clobber it on every roster/tier pass.
    --
    -- The per-tier offset still applies, though: it is added ON TOP of whatever the
    -- anchor computed, rather than replacing it. Skipping it outright is what made the
    -- per-tier offset fields silently inert for anyone who anchored the raid frames to
    -- another element -- the setting was saved, shown in the options, and did nothing.
    if EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored("RF_RaidFrames") then
        -- The anchor owns the position and now folds the tier offset into it
        -- (see _anchorExtraOffset above), so a tier change just needs the
        -- anchor re-run; moving the container from here would fight it.
        if EllesmereUI.ReapplyUnlockAnchor then
            EllesmereUI.ReapplyUnlockAnchor("RF_RaidFrames")
        end
        return
    end
    local s = db.profile
    if not s.unlockPos then return end
    local _, ov = ns._RFResolveTierOverride(ns._GetEffectiveRaidSize())
    local cs = PixelSnap(ns.RF_RaidSpacing(s))
    local gs = PixelSnap(ns.RF_RaidSpacing(s, true))
    local fw = (ov and ov.width) or s.frameWidth or 72
    local fh = (ov and ov.height) or s.frameHeight or 46
    local ug, gg = ns._RFEffectiveGrowth(
        (ov and ov.unitGrowth) or s.unitGrowth or "DOWN",
        (ov and ov.groupGrowth) or s.groupGrowth or "RIGHT", s.mergeGroups)
    local tw, th = ns._RFFootprint(fw, fh, ug, gg, cs, gs)
    local x, y = ns._RFTierTopLeft(tw, th, ug, gg,
        (ov and ov.offsetX) or 0, (ov and ov.offsetY) or 0)
    if not x then return end
    containerFrame:ClearAllPoints()
    containerFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", PixelSnap(x), PixelSnap(y))
    -- Hidden container (frames not shown -- solo, party, or just left the raid):
    -- LayoutGroups no longer runs for it, so re-derive the SIZE here too. Left alone,
    -- the dormant container keeps the LAST raid tier's footprint, and unlock mode's
    -- mover reads live container geometry: the control appears at a stale spot with a
    -- stale box, and a drag-save there stores a center measured on the wrong footprint
    -- (off by half the width delta -- the "whole layout drifted left after a raid"
    -- corruption). While shown, LayoutGroups owns the size as before.
    if not containerFrame:IsShown() then
        containerFrame:SetSize(tw, th)
    end
end

I.ReloadFrames = ReloadFrames
I.SetRangeUpdate = function(f) RangeUpdate = f end
I.broken = false
