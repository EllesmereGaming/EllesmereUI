if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_RaidFrames_ExtraFrames.lua
--
--  Extra Frames: duplicates of chosen raid members.
--  Reads the earlier Raid Frames files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- EllesmereUIRaidFrames.lua or an earlier Raid Frames file failed to load.
if not I or I.broken then return end
I.broken = true

local pairs        = pairs
local ipairs       = ipairs
local wipe         = wipe
local UnitName              = UnitName
local UnitClass             = UnitClass
local UnitIsUnit            = UnitIsUnit
local IsInRaid              = IsInRaid
local InCombatLockdown      = InCombatLockdown
local GetNumGroupMembers    = GetNumGroupMembers
local C_Timer               = C_Timer
local CreateFrame           = CreateFrame

local allButtons, ApplyFont, GetFFD = I.allButtons, I.ApplyFont, I.GetFFD
local IsPowerBarEnabled, PixelSnap = I.IsPowerBarEnabled, I.PixelSnap
local unitToButton, StyleButton, UpdateButton = I.unitToButton, I.StyleButton, I.UpdateButton
local UpdateReadyCheck, LayoutTopNameBar = I.UpdateReadyCheck, I.LayoutTopNameBar

local db
I.dbSetters[#I.dbSetters + 1] = function(v) db = v end

-------------------------------------------------------------------------------
--  Extra Frames (raid only): 1:1 duplicates of chosen raid members (Show
--  Tanks + hotkey-toggled players, up to XF.CAP). Attached positions stack
--  group-sized runs of 5 like extra raid groups; Free Move uses its own
--  grow/wrap axes (XF.GrowInfo/XF.FreeAnchor) with a growth-corner pin. Each
--  duplicate runs the SAME StyleButton pipeline as real header children
--  (power/absorbs/auras/BM/icons/click-cast/ping) and joins allButtons.
--
--  Duplicates stay OUT of unitToButton (d._isExtra guards every rebuild);
--  each slot has its own tracker + RegisterUnitEvent and lives in
--  ns._xfUnitToButton, which the broadcast passes (target border, markers,
--  range, ghost-aura sweep) also iterate -- zero cost when inactive. Position
--  via shared FB.Anchor; unit assignment is OOC, dirty-deferred through
--  combat. Excluded from preview/unlock mode like FB.
-------------------------------------------------------------------------------
do
local XF = { buttons = {}, trackers = {} }
ns._XF = XF
local FB = ns._FB

XF.Settings = function()
    return db and db.profile and db.profile.extraFrames
end

XF.ShouldBeActive = function()
    local set = XF.Settings()
    if not set then return false end
    return set.showTanks or #(set.players or {}) > 0
end

-- Hard selection bound (internal, no user setting): a full mythic roster's
-- worth of duplicates while keeping per-unit event mirroring bounded.
XF.CAP = 20

-- Effective growth axes: primary run direction + perpendicular wrap.
-- Attached modes stack group-sized runs of 5 like additional raid groups:
-- units along the raid unit growth, each full run slotting further out along
-- the group growth axis AWAY from the raid ("left" attaches before the first
-- group, so runs extend against the group growth). Free Move reads Grow
-- Direction (falling back to the legacy Horizontal toggle) and wraps along
-- Wrap Direction. Wrap values not perpendicular to the primary run (stale
-- after a direction change, or a parallel group growth) fall back to the default.
XF.GrowInfo = function(set, s)
    local grow, wrap
    if set and set.position == "free" then
        grow = set.growDirection or (set.freeHorizontal and "RIGHT" or "DOWN")
        wrap = set.wrapDirection
    else
        grow = (s and s.unitGrowth) or "DOWN"
        wrap = (s and s.groupGrowth) or "RIGHT"
        -- Attached runs wrap along the frames' group axis, and the grid flow's
        -- column advance runs right like a plain RIGHT run (FB.Anchor reads it
        -- the same way). Read raw it would miss every branch below: the left
        -- flip falls through to DOWN and the perpendicular check picks the
        -- RIGHT default by luck.
        if wrap == "DOWNRIGHT" then wrap = "RIGHT" end
        if set and set.position == "left" then
            wrap = (wrap == "RIGHT" and "LEFT") or (wrap == "LEFT" and "RIGHT")
                or (wrap == "DOWN" and "UP") or "DOWN"
        end
    end
    local horizontal = (grow == "LEFT" or grow == "RIGHT")
    if horizontal then
        if wrap ~= "UP" and wrap ~= "DOWN" then wrap = "DOWN" end
    else
        if wrap ~= "LEFT" and wrap ~= "RIGHT" then wrap = "RIGHT" end
    end
    return grow, wrap, horizontal
end

-- Free Move anchoring: pin the grid's growth corner to the rect captured at
-- the last mover drag so frame 1 never shifts as players enter/leave the
-- selection (the container is sized to the live selection; a CENTER pin
-- would drift). Falls back to the legacy CENTER anchor (freePos) until the
-- user drags the mover once. Called by FB.Anchor through the owner hook.
XF.FreeAnchor = function(c, set)
    local r = set and set.freeRect
    if not r then return false end
    local grow, wrap, horizontal = XF.GrowInfo(set, db and db.profile)
    local corner, x, y = FB.CornerPin(horizontal and grow or wrap, horizontal and wrap or grow, r)
    FB.Pin(c, corner, UIParent, "CENTER", x, y)
    return true
end

-- Called by the shared mover on drag stop: capture the dropped rect for the corner pin above.
XF.SaveFreeRect = function(mover)
    FB.SaveMoverRect(mover, XF.Settings())
end

-- Ordered raid units to duplicate (bounded by XF.CAP): tanks in roster order first
-- (Show Tanks on), then manually added names currently in the raid. Names are stored
-- AND matched in GetRaidRosterInfo's format so realm suffixes always agree; names not
-- in the roster are skipped but kept (they reappear when that player rejoins).
XF.ResolveUnits = function()
    local set = XF.Settings()
    local units = {}
    if not set or not IsInRaid() then return units end
    local cap = XF.CAP
    local seen = {}
    local n = GetNumGroupMembers() or 0
    if set.showTanks then
        for i = 1, n do
            if #units >= cap then break end
            local name = GetRaidRosterInfo(i)
            if name and not seen[name]
               and EllesmereUI.UnitEffectiveRole("raid" .. i) == "TANK"
               -- Exclude Myself (Show Tanks cog): the tanks auto-include
               -- skips the player's own frame; explicit hotkey picks below
               -- still add it.
               and not (set.excludeSelfTank and UnitIsUnit("raid" .. i, "player")) then
                seen[name] = true
                units[#units + 1] = "raid" .. i
            end
        end
    end
    for _, mname in ipairs(set.players or {}) do
        if #units >= cap then break end
        if not seen[mname] then
            for i = 1, n do
                if (GetRaidRosterInfo(i)) == mname then
                    seen[mname] = true
                    units[#units + 1] = "raid" .. i
                    break
                end
            end
        end
    end
    return units
end

-- Geometry only: container size, button stacking, per-button size (Extra
-- Width/Height offsets) and height-derived inner corrections (mirrors
-- ns._ResizeButtons). All VISUALS come from the shared StyleButton /
-- ReloadFrames pipeline (buttons are in allButtons); ReloadFrames tail-calls
-- XF_Apply so this offset pass always runs after the bulk base-size pass.
XF.Layout = function()
    if not XF.built then return end
    local s = ns._scaledProfile or db.profile
    local set = XF.Settings()
    local w = PixelSnap(math.max(10, (ns._activeSizeW or s.frameWidth or 72)
        + ((set and set.extraWidth) or 0)))
    local h = PixelSnap(math.max(10, (ns._activeSizeH or s.frameHeight or 46)
        + ((set and set.extraHeight) or 0)))
    -- Indicator/aura/BM auto-resize: ratio of the custom size to what the
    -- real frames currently render at (clamped like the tier scales). The
    -- extra proxy and ns._xfBmScale pick this up everywhere a duplicate
    -- renders, composing with the raid tier scales.
    local aw = PixelSnap(ns._activeSizeW or s.frameWidth or 72)
    local ah = PixelSnap(ns._activeSizeH or s.frameHeight or 46)
    local ratio = 1
    -- Auto Resize Indicators cog toggle (nil = ON, additive key): off keeps
    -- indicators/auras/BM at the real frames' base scale regardless of the
    -- extra frames' custom size.
    if aw > 0 and ah > 0 and (not set or set.autoResizeIndicators ~= false) then
        ratio = math.max(math.min(math.min(w / aw, h / ah), 1.3), 0.7)
    end
    ns._xfExtraRatio = ratio
    if ns._RefreshProxyModes then ns._RefreshProxyModes() end
    ns._xfBmScale = (ns._bmScale or 1) * ratio
    local sp = s.cellSpacing or 2
    -- Free Move lays out on its own axes; attached modes stack group-sized
    -- runs of 5 (unitGrowth within a run, group growth across).
    local grow, wrap, horizontal = XF.GrowInfo(set, s)
    -- Grid size = the live selection; when the mover is shown outside a raid
    -- there is no selection yet, so estimate from the configuration.
    local count = XF.activeCount or 0
    if count < 1 then
        count = ((set and set.showTanks) and 2 or 0)
            + ((set and set.players) and #set.players or 0)
        if count < 1 then count = 1 end
        if count > XF.CAP then count = XF.CAP end
    end
    -- Frames per run: attached always uses full group-sized runs of 5 (a
    -- partially filled run still spans 5, exactly like a real group); Free
    -- Move wraps at Wrap After (0/unset = one single run).
    local per
    if set and set.position == "free" then
        local wa = tonumber(set.wrapAfter) or 0
        per = (wa > 0) and wa or count
        if per > count then per = count end
    else
        per = 5
    end
    local lines = math.ceil(count / per)

    -- The container spans the occupied grid. Its anchor corner (FB.Anchor's
    -- attached slotting, XF.FreeAnchor's free pin) is the corner the grid
    -- grows away from, so frame 1 holds position as the selection changes.
    local runW, runH = w * per + sp * (per - 1), h * per + sp * (per - 1)
    if horizontal then
        XF.container:SetSize(runW, h * lines + sp * (lines - 1))
    else
        XF.container:SetSize(w * lines + sp * (lines - 1), runH)
    end

    local stepW, stepH = w + sp, h + sp
    local powerH = IsPowerBarEnabled(s) and PixelSnap(s.powerHeight or 4) or 0
    local topBarH = (s.topNameBarEnabled and PixelSnap(s.topNameBarHeight or 20)) or 0
    for i, b in ipairs(XF.buttons) do
        b:SetSize(w, h)
        b:ClearAllPoints()
        local off = i - 1
        local line = math.floor(off / per)
        local pos = off - line * per
        -- Map the (run, wrap) grid coordinate onto screen axes: the primary
        -- run carries pos, the wrap axis carries line; the anchor corner is
        -- the one both directions grow away from (frame 1 sits there).
        local hUnits, vUnits, hDir, vDir
        if horizontal then
            hUnits, vUnits, hDir, vDir = pos, line, grow, wrap
        else
            hUnits, vUnits, hDir, vDir = line, pos, wrap, grow
        end
        local corner = (vDir == "UP" and "BOTTOM" or "TOP")
            .. (hDir == "LEFT" and "RIGHT" or "LEFT")
        b:SetPoint(corner, XF.container, corner,
            (hDir == "LEFT" and -hUnits or hUnits) * stepW,
            (vDir == "UP" and vUnits or -vUnits) * stepH)
        -- The bulk passes size inner elements for the BASE frame size;
        -- correct the height/width-derived pieces for the offset size.
        local d = GetFFD(b)
        if d.health then
            d.health:SetHeight(((d.power and d.power:IsShown()) and PixelSnap(h - ns.RF_HealthPowerInset(s, powerH)) or h) - topBarH)
        end

        -- Scaled visual pass: re-apply every ratio-affected element through
        -- the extra proxy (mirrors ReloadFrames per-button styling) so texts/
        -- indicators/auras/BM buffs auto-resize. Bounded to the built slots.
        local xs = ns._scaledExtraProxy
        if xs.topNameBarDivider == true or (d.topNameBar and d.topNameBar._divider) then
            LayoutTopNameBar(xs, h, (d.power and d.power:IsShown()) and powerH or 0,
                d.health, d.topNameBar, d.topNameBarBg, d.topNameBarText, d.power)
            if xs.topNameBarDividerMatchColor == true and d.topNameBar and d.topNameBar._divider
                and d.topNameBar._divider._powerArtMode == "divider" then
                d.ApplyBorderColor()
            end
        end
        if d.nameText then
            ApplyFont(d.nameText, xs.nameSize or 10)
            if d.AnchorNameText then d.AnchorNameText() end
            -- AnchorNameText derives width from the BASE frame width; the
            -- offset width is authoritative here.
            d.nameText:SetWidth(w * ns.RF_NAME_WIDTH_FRACTION)
        end
        if d.healthText then
            ApplyFont(d.healthText, xs.healthTextSize or 9)
            if d.AnchorHealthText then d.AnchorHealthText() end
        end
        if d.powerText then
            ApplyFont(d.powerText, xs.powerTextSize or 8)
            ns._RFAnchorPowerText(d)
        end
        if d.levelText then
            ApplyFont(d.levelText, xs.levelTextSize or 10)
            ns._RFAnchorLevelText(d)
        end
        if d.healAbsorbText then
            ApplyFont(d.healAbsorbText, xs.healAbsorbTextSize or 9)
            if d.AnchorHealAbsorbText then d.AnchorHealAbsorbText() end
        end
        if d.statusText then
            ApplyFont(d.statusText, xs.statusTextSize or 14)
            if d.AnchorStatusText then d.AnchorStatusText() end
        end
        if d.roleIcon then
            local riSz = PixelSnap(xs.roleIconSize or 14)
            d.roleIcon:SetSize(riSz, riSz)
            if d.AnchorRoleIcon then d.AnchorRoleIcon() end
        end
        if d.leaderIcon then
            local liSz = PixelSnap(xs.leaderIconSize or 14)
            d.leaderIcon:SetSize(liSz, liSz)
            d.leaderIcon:ClearAllPoints()
            local liPos = (xs.leaderIconPosition or "top"):upper()
            d.leaderIcon:SetPoint(liPos, ns.RF_AnchorHost(d.health, xs), liPos, xs.leaderIconOffsetX or 0, xs.leaderIconOffsetY or 0)
        end
        if d.raidMarker then
            local rmSz = PixelSnap(xs.raidMarkerSize or 16)
            d.raidMarker:SetSize(rmSz, rmSz)
            if d.AnchorRaidMarker then d.AnchorRaidMarker() end
        end
        if d.readyCheck then
            local rcSz = PixelSnap(xs.readyCheckSize or 20)
            d.readyCheck:SetSize(rcSz, rcSz)
            if d.AnchorReadyCheck then d.AnchorReadyCheck() end
        end
        if d.combatIcon then
            local cciSz = PixelSnap(xs.combatIndicatorSize or 16)
            d.combatIcon:SetSize(cciSz, cciSz)
            if d.AnchorCombatIcon then d.AnchorCombatIcon() end
        end
        if d.pingFrame then ns._RFAnchorPing(d) end
        if ns.RF_FvMissingAnchor then ns.RF_FvMissingAnchor(b, d) end
    end
end

-- Per-unit events mirrored from the central hub for one duplicate's unit.
-- UNIT_* only (safe for RegisterUnitEvent's C-side filter); the two
-- unit-payload broadcast events (READY_CHECK_CONFIRM, PLAYER_FLAGS_CHANGED)
-- are plain registrations filtered in the handler.
XF.EVENTS = {
    -- UNIT_AURA deliberately absent (Blizzard parity: their CompactUnitFrame
    -- repaints prediction from health/absorb events only). The one gap -- an
    -- aura-granted shield expiring on its TIMER on an unhit, topped unit
    -- (field report: VDH Infernal Strike) fires NO event at all -- is covered
    -- by the armed-members belt next to the absorb coalescer.
    "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_DISPLAYPOWER",
    "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED",
    "UNIT_HEAL_PREDICTION", "UNIT_MAX_HEALTH_MODIFIERS_CHANGED",
    "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE",
    "UNIT_NAME_UPDATE", "UNIT_CONNECTION", "UNIT_IN_RANGE_UPDATE",
}

-- Grow-on-demand construction: container + buttons through the full real-frame
-- StyleButton pipeline. The base 5 slots build on first activation; slots above 5 build
-- only when the selection reaches them (callers are all OOC). d._isExtra is set BEFORE
-- StyleButton so the OnAttributeChanged hook it installs never writes the real routing
-- maps. Buttons join allButtons so every bulk restyle/update pass covers them.
XF.EnsureBuilt = function(count)
    if not XF.built then
        XF.built = true
        local container = CreateFrame("Frame", "ERFExtraFramesContainer", UIParent)
        container:Hide()
        XF.container = container
    end
    local want = count or 5
    if want < 5 then want = 5 end

    for i = #XF.buttons + 1, want do
        local b = CreateFrame("Button", "ERFExtraFrame" .. i, XF.container, "SecureUnitButtonTemplate")
        b:Hide()
        GetFFD(b)._isExtra = true
        ns._StyleButtonSecure(b)
        StyleButton(b)
        allButtons[#allButtons + 1] = b

        -- Per-slot tracker: (re)registered for the assigned unit in XF_Apply,
        -- mirroring the central hub's per-unit reactions for this duplicate.
        -- Bounded to the built slots; zero registrations while a slot is empty.
        local t = ns.TakeShell()
        t:SetScript("OnEvent", function(_, event, unit, updateInfo)
            if not b:IsVisible() then return end
            if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
                ns._UpdateButtonHealth(b, unit)
                if event == "UNIT_MAXHEALTH" then
                    ns._ResettleButtonHealth(b)
                    -- Max moves the absorb bars' range; value-only health
                    -- changes touch nothing UpdateAbsorb paints (overlays are
                    -- clip-anchored; the missing-health clamp edge rides the
                    -- armed belt / next absorb event instead).
                    local d = GetFFD(b)
                    if d._absActive then ns._MarkAbsorbDirty(b, unit) end
                end
            elseif event == "UNIT_POWER_UPDATE" then
                local d = GetFFD(b)
                if d.power and d.power:IsShown() then
                    -- Value only; type/color/bounds ride the UNIT_DISPLAYPOWER
                    -- edge (see the header dispatcher's branch).
                    local pType = d._pwType
                    if pType == nil then
                        ns._RFPowerTypeEdge(d, unit)
                        pType = d._pwType
                    end
                    local ppct = UnitPowerPercent(unit, pType, true, CurveConstants.ScaleTo100)
                    d.power:SetValue(ppct)
                    -- Power Text rides the same value (nil = off: this one field test).
                    local pwtMode = d._pwtMode
                    if pwtMode then ns.RF_PowerTextInto(d.powerText, pwtMode, ppct, unit, pType) end
                end
            elseif event == "UNIT_DISPLAYPOWER" then
                local d = GetFFD(b)
                if d.power and d.power:IsShown() then
                    ns._RFPowerTypeEdge(d, unit)
                    local ppct = UnitPowerPercent(unit, d._pwType, true, CurveConstants.ScaleTo100)
                    d.power:SetValue(ppct)
                    local pwtMode = d._pwtMode
                    if pwtMode then ns.RF_PowerTextInto(d.powerText, pwtMode, ppct, unit, d._pwType) end
                end
            elseif event == "UNIT_ABSORB_AMOUNT_CHANGED" or event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED"
                or event == "UNIT_HEAL_PREDICTION" or event == "UNIT_MAX_HEALTH_MODIFIERS_CHANGED" then
                -- The event IS the arm: plainly observable even while the
                -- values are secret. Paint coalesces to once per render frame.
                -- Prediction is view-gated: with the feature off for this
                -- button's view the event changes no pixel and must not arm.
                local dd = GetFFD(b)
                if event == "UNIT_HEAL_PREDICTION" then
                    local sv = dd._isParty and ns._scaledPartyProxy
                        or (dd._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
                    if sv.healPrediction then
                        ns._AbArm(b, unit, dd)
                        ns._MarkAbsorbDirty(b, unit)
                    end
                else
                if event ~= "UNIT_MAX_HEALTH_MODIFIERS_CHANGED" then ns._AbArm(b, unit, dd) end
                ns._MarkAbsorbDirty(b, unit)
                if event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" then ns.UpdateHealAbsorbTextFor(b, unit) end
                if event == "UNIT_MAX_HEALTH_MODIFIERS_CHANGED" then
                    dd._rmhPct = nil -- reduced-max cache: this is its only value edge
                    ns._UpdateButtonHealth(b, unit)
                    ns._ResettleButtonHealth(b)
                end
                end -- prediction view-gate else
            elseif event == "UNIT_THREAT_LIST_UPDATE" or event == "UNIT_THREAT_SITUATION_UPDATE" then
                local d = GetFFD(b)
                ns.RF_PaintThreat(d, d._isExtra and ns._scaledExtraProxy or ns._scaledProfile, unit)
            elseif event == "UNIT_IN_RANGE_UPDATE" then
                ns._UpdateButtonRange(unit, b)
            elseif event == "UNIT_FLAGS" then
                ns._UpdateCombatIconFor(unit, b)
            elseif event == "READY_CHECK_CONFIRM" then
                -- Plain registration; filter to this slot's unit here
                if unit and unit == b:GetAttribute("unit") then
                    UpdateReadyCheck(b, unit)
                end
            elseif event == "PLAYER_FLAGS_CHANGED" then
                if unit and unit == b:GetAttribute("unit") then
                    UpdateButton(b)
                end
            elseif event == "UNIT_LEVEL" then
                ns._RFRepaintLevel(b)
            else -- UNIT_NAME_UPDATE / UNIT_CONNECTION
                UpdateButton(b)
                if event == "UNIT_CONNECTION" then ns._UpdateButtonRange(unit, b) end
            end
        end)
        XF.trackers[i] = t

        XF.buttons[i] = b
    end
end

-- Master apply: resolves the selection and assigns units to slots. OOC only
-- (unit attributes and Show/Hide on protected buttons); combat callers land
-- on the dirty flag and replay on regen. Called from OnEnable, options
-- widgets, the hotkey toggle, roster/role events, ReloadFrames and profile
-- swaps. The SetAttribute write triggers the StyleButton OnAttributeChanged
-- hook, which repaints in full (UpdateButton + auras + dispel + BM), seeds
-- range and re-registers private auras -- same path as a real header assignment.
function ns.XF_Apply()
    if not db or not db.profile then return end
    local set = XF.Settings()
    if not set then return end
    if InCombatLockdown() then XF.applyDirty = true; return end

    local units = XF.ShouldBeActive() and XF.ResolveUnits() or {}
    XF.activeCount = #units
    if #units == 0 then
        if XF.built then
            for _, b in ipairs(XF.buttons) do b:Hide() end
            XF.container:Hide()
            for i = 1, #XF.trackers do XF.trackers[i]:UnregisterAllEvents() end
        end
        if XF.mover then XF.mover:Hide() end
        wipe(ns._xfUnitToButton)
        -- The boss group may have been chained behind this container;
        -- re-anchor it back onto the raid (no-op when FB is not built).
        FB.Anchor()
        if ns._NotifyTrackerProviders then ns._NotifyTrackerProviders() end
        return
    end

    XF.EnsureBuilt(#units)
    XF.Layout()
    FB.Anchor(XF)
    XF.container:Show()
    wipe(ns._xfUnitToButton)
    for i = 1, #XF.buttons do
        local b = XF.buttons[i]
        local unit = units[i]
        local t = XF.trackers[i]
        t:UnregisterAllEvents()
        if unit then
            -- Class token cache for the power border (mirrors RebuildUnitMap)
            local d = GetFFD(b)
            local _, classToken = UnitClass(unit)
            d.classToken = classToken
            b:SetAttribute("unit", unit)
            ns._xfUnitToButton[unit] = b
            -- Fail-open backstop for a mid-raid reconnect: the roster can still be
            -- streaming, so UnitName(unit) may be nil at this first paint and the
            -- slot commits a blank name (field report: blank until /reload even
            -- though UNIT_NAME_UPDATE and the roster re-apply are both wired).
            -- Re-arms until the name resolves, bounded, and only repaints while
            -- this slot still holds the same unit. No-op when the name is cached.
            if not UnitName(unit) then
                local tries = 0
                local function RetryName()
                    if b:GetAttribute("unit") ~= unit then return end
                    if UnitName(unit) then UpdateButton(b); return end
                    tries = tries + 1
                    if tries < 5 then C_Timer.After(2, RetryName) end
                end
                C_Timer.After(2, RetryName)
            end
            for _, ev in ipairs(XF.EVENTS) do
                t:RegisterUnitEvent(ev, unit)
            end
            -- UNIT_FLAGS is opt-in: extra frames mirror the raid combat-icon toggle.
            if db.profile.showCombatIndicator then
                t:RegisterUnitEvent("UNIT_FLAGS", unit)
            end
            -- UNIT_LEVEL is opt-in too: only while a view shows Level Text.
            if ns._RFLevelWanted() then
                t:RegisterUnitEvent("UNIT_LEVEL", unit)
            end
            t:RegisterEvent("READY_CHECK_CONFIRM")
            t:RegisterEvent("PLAYER_FLAGS_CHANGED")
            b:Show()
        else
            b:Hide()
        end
    end
    -- Re-evaluate the boss group's chain now that this container is shown
    -- and (re)positioned: same-side boss frames hop behind it.
    FB.Anchor()
    -- Extra frames are excluded from _CollectTrackerFrames (duplicates), but
    -- name-scanning trackers do index them, and PLAYER_ROLES_ASSIGNED reshuffles
    -- them with no event those trackers listen for.
    if ns._NotifyTrackerProviders then ns._NotifyTrackerProviders() end
end

function ns.XF_IsMoverShown()
    return XF.mover and XF.mover:IsShown() or false
end

function ns.XF_SetMoverShown(show)
    FB.SetMoverShown(XF, show, "ERFExtraFramesMover", "Extra Frames")
end

-- Hidden bind target (pure Lua keybinding, no Bindings.xml; same pattern as
-- the Party Mode toggle key). The options panel binds the saved key to click
-- this button; the click toggles the hovered raid member in/out of the group.
local bindBtn = CreateFrame("Button", "ERFExtraFramesBindBtn", UIParent)
bindBtn:Hide()

XF.ToggleHovered = function()
    if not db or not db.profile then return end
    if not IsInRaid() then return end
    local set = XF.Settings()
    if not set then return end
    -- The real raid frame under the mouse, or one of our own duplicates
    -- (pressing the hotkey on a duplicate removes that player too).
    local unit
    for u, btn in pairs(unitToButton) do
        if btn:IsShown() and btn:IsMouseOver() then unit = u; break end
    end
    if not unit then
        for _, b in ipairs(XF.buttons) do
            if b:IsShown() and b:IsMouseOver() then unit = b:GetAttribute("unit"); break end
        end
    end
    if not unit then return end
    local idx = tonumber(unit:match("^raid(%d+)$"))
    local name = idx and GetRaidRosterInfo(idx)
    if not name then return end

    local players = set.players or {}
    set.players = players
    for k, v in ipairs(players) do
        if v == name then
            table.remove(players, k)
            ns.XF_Apply()
            return
        end
    end
    -- Already covered by Show Tanks: adding would be an invisible duplicate.
    -- An Exclude-Myself'd player tank is NOT covered, so their manual add
    -- stays legitimate.
    if set.showTanks and EllesmereUI.UnitEffectiveRole(unit) == "TANK"
       and not (set.excludeSelfTank and UnitIsUnit(unit, "player")) then
        return
    end
    if #XF.ResolveUnits() >= XF.CAP then
        return
    end
    players[#players + 1] = name
    ns.XF_Apply()
end

bindBtn:SetScript("OnClick", function() XF.ToggleHovered() end)

-- Standing event frame: exists even while inactive so the tanks toggle or a
-- first hotkey add can activate the feature without a /reload, and so the
-- saved hotkey is re-bound every login.
do
    local ev = ns.TakeShell()
    ev:RegisterEvent("PLAYER_LOGIN")
    ev:RegisterEvent("GROUP_ROSTER_UPDATE")
    ev:RegisterEvent("PLAYER_ROLES_ASSIGNED")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    -- No PLAYER_TARGET_CHANGED / RAID_TARGET_UPDATE here: the duplicates ride
    -- the central broadcast closures via ns._xfUnitToButton.
    ev:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_LOGIN" then
            local key = EllesmereUIDB and EllesmereUIDB.extraFramesKey
            if key then
                ClearOverrideBindings(bindBtn)
                SetOverrideBindingClick(bindBtn, true, key, "ERFExtraFramesBindBtn")
            end
            return
        end
        if not db then return end
        if event == "PLAYER_REGEN_ENABLED" then
            if XF.applyDirty then XF.applyDirty = nil; ns.XF_Apply() end
            if XF.anchorDirty then XF.anchorDirty = nil; FB.Anchor(XF) end
        else -- GROUP_ROSTER_UPDATE / PLAYER_ROLES_ASSIGNED
            -- Raid indices and the tank set both shift with the roster
            if XF.ShouldBeActive() or XF.built then ns.XF_Apply() end
        end
    end)
    XF.eventFrame = ev
end
end -- XF scope block

I.broken = false
