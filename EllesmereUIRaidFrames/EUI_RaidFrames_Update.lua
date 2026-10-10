if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_RaidFrames_Update.lua
--
--  The ping marker, the role, leader and combat icons, UpdateButton, dispel
--  detection, the ready check, the unit map and UpdateAllButtons.
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
local type         = type
local tostring     = tostring
local select       = select
local UnitHealth            = UnitHealth
local UnitPowerMax          = UnitPowerMax
local UnitPowerType         = UnitPowerType
local UnitClass             = UnitClass
local UnitExists            = UnitExists
local UnitIsConnected       = UnitIsConnected
local UnitIsDeadOrGhost     = UnitIsDeadOrGhost
local UnitHasIncomingResurrection = UnitHasIncomingResurrection
local UnitIsUnit            = UnitIsUnit
local GetReadyCheckStatus   = GetReadyCheckStatus
local C_IncomingSummon      = C_IncomingSummon
local GetRaidTargetIndex    = GetRaidTargetIndex
local C_Timer               = C_Timer
local issecretvalue         = issecretvalue
local CreateFrame           = CreateFrame

local AbbreviateNumbers, allButtons = I.AbbreviateNumbers, I.allButtons
local ApplyRoleIcon, ERF, GetFFD, PixelSnap = I.ApplyRoleIcon, I.ERF, I.GetFFD, I.PixelSnap
local RAID_MARKER_TEXCOORDS = I.RAID_MARKER_TEXCOORDS
local SUMMON_STATUS_ACCEPTED = I.SUMMON_STATUS_ACCEPTED
local SUMMON_STATUS_DECLINED = I.SUMMON_STATUS_DECLINED
local SUMMON_STATUS_PENDING, unitToButton = I.SUMMON_STATUS_PENDING, I.unitToButton
local unitTrackers, GetHealthColor = I.unitTrackers, I.GetHealthColor
local GetHealthTextColor, GetNameColor = I.GetHealthTextColor, I.GetNameColor
local GetPowerColor, GetSafeHealthPercent = I.GetPowerColor, I.GetSafeHealthPercent
local GetTopNameBarColor, ResolveDisplayName = I.GetTopNameBarColor, I.ResolveDisplayName
local UpdateAbsorb = I.UpdateAbsorb

local db
I.dbSetters[#I.dbSetters + 1] = function(v) db = v end
local inCombat = false
I.inCombatSetters[#I.inCombatSetters + 1] = function(v) inCombat = v end

-------------------------------------------------------------------------------
--  Unit ping marker (parity with the default raid frames): when a group member
--  is pinged, the marker Blizzard draws on its compact frame appears on that
--  member's button here.
--
--  There is no direct channel: the pin events (UNIT_PING_PIN_ADDED / _REMOVED)
--  are restricted (addon RegisterEvent = forbidden, like the combat log) and
--  their only consumer template is forbidden to instantiate from addon code.
--  What IS reachable: the ping icon frame Blizzard already built on each of
--  its own compact frames is an ordinary object, and the raid module keeps
--  those frames alive -- the container is parked off-screen but the manager
--  still runs every roster layout through it (SetUpFrame fires per compact
--  frame per roster event). Blizzard's handler resolves the pinned GUID to a
--  frame and applies the showPingsOnRaidFrames CVar gate before it calls
--  ShowPing / ClearPing on that icon, so a secure post-hook on those two
--  methods hands us the texture kit and the owning compact frame's unit
--  token; the token maps to our button(s) and the same atlases go on our own
--  overlay. Hooks are installed per icon from a CompactUnitFrame_SetUpFrame
--  post-hook (once per icon object; nameplate compact frames are skipped for
--  good). Parity is total: same trigger, same CVar, same art. Zero work
--  between pings; overlays are built on first use.
--
--  Blizzard's own icon never clears when the pinged person moves to another
--  compact frame before the pin expires (the removed edge no longer matches
--  that frame), so a mirror needs two belts: our unit hook hides the overlay
--  on an occupant change, and a shown overlay expires on its own after the
--  longest a pin can live.
-------------------------------------------------------------------------------
ns._pingHooked  = setmetatable({}, { __mode = "k" })  -- Blizzard icon -> true (hooked) / false (never)
ns._pingLitBtn  = setmetatable({}, { __mode = "k" })  -- Blizzard icon -> our button it lit
ns._pingLitXf   = setmetatable({}, { __mode = "k" })  -- Blizzard icon -> Extra Frames duplicate it lit
ns.PING_EXPIRE  = 20

-- Position + size from the (party/extra-aware) settings: the same 9-point
-- anchor set as the raid marker, and the size as a factor of Blizzard's native
-- 30 so both atlases keep their proportions. Re-run by every reload path that
-- re-anchors the other indicators.
ns._RFAnchorPing = function(d)
    local pf = d.pingFrame
    if not pf then return end
    local s = d._isParty and ns._scaledPartyProxy or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
    local size = PixelSnap(s.pingMarkerSize or 30)
    pf:SetSize(size, size)
    pf._factor = size / 30
    local host = ns.RF_AnchorHost(d.health, s)
    local pos = s.pingMarkerPosition or "center"
    local ox = s.pingMarkerOffsetX or 0
    local oy = s.pingMarkerOffsetY or 0
    pf:ClearAllPoints()
    if pos == "topleft" then
        pf:SetPoint("TOPLEFT", host, "TOPLEFT", 2 + ox, -2 + oy)
    elseif pos == "top" then
        pf:SetPoint("TOP", host, "TOP", ox, -2 + oy)
    elseif pos == "topright" then
        pf:SetPoint("TOPRIGHT", host, "TOPRIGHT", -2 + ox, -2 + oy)
    elseif pos == "left" then
        pf:SetPoint("LEFT", host, "LEFT", 2 + ox, oy)
    elseif pos == "right" then
        pf:SetPoint("RIGHT", host, "RIGHT", -2 + ox, oy)
    elseif pos == "bottomleft" then
        pf:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 2 + ox, 2 + oy)
    elseif pos == "bottom" then
        pf:SetPoint("BOTTOM", host, "BOTTOM", ox, 2 + oy)
    elseif pos == "bottomright" then
        pf:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -2 + ox, 2 + oy)
    else
        pf:SetPoint("CENTER", host, "CENTER", ox, oy)
    end
end

ns._RFPingOverlay = function(button, d)
    local pf = d.pingFrame
    if pf then return pf end
    pf = CreateFrame("Frame", nil, button)
    pf:SetFrameLevel(button:GetFrameLevel() + ns.LVL_MARKER + 1)
    pf:EnableMouse(false)
    pf.bg = pf:CreateTexture(nil, "BACKGROUND")
    pf.bg:SetPoint("CENTER")
    pf.icon = pf:CreateTexture(nil, "ARTWORK")
    pf.icon:SetPoint("CENTER")
    pf:Hide()
    d.pingFrame = pf
    ns._RFAnchorPing(d)
    return pf
end

ns._RFPingHide = function(button)
    if not button then return end
    local d = GetFFD(button)
    if d.pingFrame then d.pingFrame:Hide() end
end

-- Atlas at native size, then scaled by the configured factor (each texture
-- keeps its own native proportions).
ns._SetPingAtlas = function(tex, atlas, factor)
    tex:SetAtlas(atlas, true)
    if factor ~= 1 then
        local w, h = tex:GetSize()
        tex:SetSize(w * factor, h * factor)
    end
end

ns._RFPingLight = function(button, kit)
    local d = GetFFD(button)
    local s = d._isParty and ns._scaledPartyProxy or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
    if s.showPingMarker == false then return end
    local pf = ns._RFPingOverlay(button, d)
    local factor = pf._factor or 1
    ns._SetPingAtlas(pf.bg, "Ping_Frame_BG_" .. kit, factor)
    ns._SetPingAtlas(pf.icon, "Ping_Frame_" .. kit, factor)
    pf:Show()
    -- Expiry belt: a pin has a finite engine lifetime; if its removed edge can
    -- no longer reach this button (see header), the overlay still goes away.
    local stamp = (d._pingStamp or 0) + 1
    d._pingStamp = stamp
    C_Timer.After(ns.PING_EXPIRE, function()
        if d._pingStamp == stamp and d.pingFrame then d.pingFrame:Hide() end
    end)
end

ns._OnCufShowPing = function(icon, kit)
    if issecretvalue(kit) or type(kit) ~= "string" then return end
    local owner = icon:GetParent()
    local unit = owner and owner.unit
    if type(unit) ~= "string" then return end
    local btn = unitToButton[unit] or ns._partyUnitToButton[unit]
    local xf = ns._xfUnitToButton[unit]
    -- The icon re-lit for a different occupant: release what it lit before.
    local prevB, prevX = ns._pingLitBtn[icon], ns._pingLitXf[icon]
    if prevB and prevB ~= btn then ns._RFPingHide(prevB) end
    if prevX and prevX ~= xf then ns._RFPingHide(prevX) end
    if btn then ns._RFPingLight(btn, kit) end
    if xf then ns._RFPingLight(xf, kit) end
    ns._pingLitBtn[icon], ns._pingLitXf[icon] = btn, xf
end

ns._OnCufClearPing = function(icon)
    local b, x = ns._pingLitBtn[icon], ns._pingLitXf[icon]
    if not b and not x then return end
    ns._pingLitBtn[icon], ns._pingLitXf[icon] = nil, nil
    ns._RFPingHide(b)
    ns._RFPingHide(x)
end

ns._HookCufPingIcon = function(cuf)
    local icon = cuf and cuf.pingIconFrame
    if not icon then return end
    local state = ns._pingHooked[icon]
    if state ~= nil then return end
    -- Nameplate compact frames carry the same child; never ours to mirror.
    local okN, name = pcall(cuf.GetName, cuf)
    if okN and type(name) == "string" and name:find("^NamePlate") then
        ns._pingHooked[icon] = false
        return
    end
    local okF, forbidden = pcall(icon.IsForbidden, icon)
    if not okF or forbidden then
        ns._pingHooked[icon] = false
        return
    end
    ns._pingHooked[icon] = true
    hooksecurefunc(icon, "ShowPing", ns._OnCufShowPing)
    hooksecurefunc(icon, "ClearPing", ns._OnCufClearPing)
end

if type(CompactUnitFrame_SetUpFrame) == "function" then
    hooksecurefunc("CompactUnitFrame_SetUpFrame", ns._HookCufPingIcon)
end

-------------------------------------------------------------------------------
--  Role icon show/hide decision. Shared by UpdateButton and the lightweight
--  ns._UpdateRoleIcons combat-transition updater (lockstep). Honors the "Hide In
--  Combat" cog (hidden in combat, restored on PLAYER_REGEN_ENABLED).
-------------------------------------------------------------------------------
ns._UpdateRoleIcon = function(d, s, unit)
    local roleIcon = d.roleIcon
    if not roleIcon then return end
    if roleIcon._roleText then roleIcon._roleText:Hide() end
    local style = s.roleIconStyle or "modern"
    if style == "none" and not s.roleText then roleIcon:Hide(); return end
    if s.roleIconHideInCombat and inCombat then roleIcon:Hide(); return end
    local role = EllesmereUI.UnitEffectiveRole(unit)
    if role and not issecretvalue(role) then
        local showForRole = (role == "TANK" and s.showRoleForTank)
            or (role == "HEALER" and s.showRoleForHealer)
            or (role == "DAMAGER" and s.showRoleForDPS)
        if showForRole and (s.roleText or ApplyRoleIcon(roleIcon, role, style)) then
            roleIcon:Show()
            if s.roleText then ns.ApplyRoleText(roleIcon, role, s) end
        else
            roleIcon:Hide()
        end
    else
        roleIcon:Hide()
    end
end

-------------------------------------------------------------------------------
--  Leader/assistant icon show/hide decision. Shared by UpdateButton and the
--  lightweight ns._UpdateLeaderIcons combat-transition updater (lockstep). Honors
--  the "Show In Combat" cog (default on; off = hidden in combat).
-------------------------------------------------------------------------------
ns._UpdateLeaderIcon = function(d, s, unit)
    local leaderIcon = d.leaderIcon
    if not leaderIcon then return end
    if not s.showLeaderIcon then leaderIcon:Hide(); return end
    if s.showLeaderIconInCombat == false and inCombat then leaderIcon:Hide(); return end
    local isLeader = UnitIsGroupLeader(unit)
    local isAssist = UnitIsGroupAssistant(unit)
    if not issecretvalue(isLeader) and isLeader then
        leaderIcon:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
        leaderIcon:SetTexCoord(0, 1, 0, 1)
        leaderIcon:Show()
    elseif not issecretvalue(isAssist) and isAssist then
        leaderIcon:SetTexture("Interface\\GroupFrame\\UI-Group-AssistantIcon")
        leaderIcon:SetTexCoord(0, 1, 0, 1)
        leaderIcon:Show()
    else
        leaderIcon:Hide()
    end
end

-------------------------------------------------------------------------------
--  Combat icon show/hide decision: members currently affecting combat (M+ skip
--  awareness). Driven by UpdateButton and the lightweight ns._UpdateCombatIcons
--  updater (UNIT_FLAGS / regen). Texture Show/Hide is combat-legal. On ns (cap).
-------------------------------------------------------------------------------
ns._UpdateCombatIcon = function(d, s, unit)
    local icon = d.combatIcon
    if not icon then return end
    if not s.showCombatIndicator then icon:Hide(); return end
    local c = UnitAffectingCombat(unit)
    if issecretvalue(c) or not c then icon:Hide(); return end

    local EllesmereUI = ns.EllesmereUI
    local style = s.combatIndicatorStyle or "standard"
    local MEDIA = ns._COMBAT_MEDIA
    if style:find("^combat%d") then
        icon:SetTexture(MEDIA .. style .. ".tga")
        icon:SetTexCoord(0, 1, 0, 1)
        if icon.SetDesaturated then icon:SetDesaturated(false) end
        icon:SetVertexColor(1, 1, 1, 1)
    else
        local classToken = d.classToken
        if not classToken then local _, ct = UnitClass(unit); classToken = ct end
        if classToken and issecretvalue(classToken) then classToken = nil end
        if style == "class" then
            icon:SetTexture(MEDIA .. "combat-indicator-class-custom.png")
            local coords = classToken and ns._COMBAT_CLASS_COORDS[classToken]
            if coords then
                icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
            else
                icon:SetTexCoord(0, 1, 0, 1)
            end
        else
            icon:SetTexture(MEDIA .. "combat-indicator-custom.png")
            icon:SetTexCoord(0, 1, 0, 1)
        end
        local colorMode = s.combatIndicatorColor or "custom"
        if colorMode == "classcolor" then
            local cc = (classToken and EllesmereUI.GetClassColor(classToken)) or { r = 1, g = 1, b = 1 }
            icon:SetVertexColor(cc.r, cc.g, cc.b, 1)
        else
            local cc = s.combatIndicatorCustomColor or { r = 1, g = 1, b = 1 }
            icon:SetVertexColor(cc.r, cc.g, cc.b, 1)
        end
    end
    icon:Show()
end

-------------------------------------------------------------------------------
--  Update all visual elements for a single button
-------------------------------------------------------------------------------
local function UpdateButton(button)
    local EllesmereUI = ns.EllesmereUI  -- upvalue read, not a global read (see the taint note at the top of EllesmereUIRaidFrames.lua)
    local unit = button:GetAttribute("unit")
    if not unit or not UnitExists(unit) then
        button:SetAlpha(0)
        local pd = GetFFD(button)
        if pd.pt and pd.pt._3dOn then ns.RF_PtModelAlpha(pd, 0) end
        return
    end

    local d = GetFFD(button)
    -- Login gap guard: events registered in the loading-screen window can
    -- dispatch before the deferred styling pass builds this button's visual
    -- body; the pass ends with a full repaint, so skipping here loses nothing.
    if not d.styled then return end
    if not d.styled then return end

    local s = d._isParty and ns._scaledPartyProxy or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
    -- Restore alpha respecting BM frame alpha + range alpha. nil rangeAlpha = managed by the
    -- secret-safe SetAlphaFromBoolean path; overriding it flashes full alpha until the next
    -- range ticker run (0.2s).
    if d.rangeAlpha then
        local baseA = button._bmSavedAlpha or 1
        button:SetAlpha(baseA * d.rangeAlpha)
        if d.pt and d.pt._3dOn then ns.RF_PtModelAlpha(d, baseA * d.rangeAlpha) end
    end

    -- Health: percent-based, secret-value safe; smooth interpolation optional.
    local smooth = s.smoothBars and Enum and Enum.StatusBarInterpolation
        and Enum.StatusBarInterpolation.ExponentialEaseOut

    local health = d.health
    -- Offline/dead units keep the gray tint _ApplyHealthBg owns. That tint is
    -- state-stamped there (applied on the transition, not on every call), so a
    -- full paint must never lay a class color over it -- the same split as
    -- Blizzard's UpdateHealthColor, which grays those units itself.
    local connected = UnitIsConnected(unit)
    local deadOrGhost = UnitIsDeadOrGhost(unit)
    if health then
        -- Inverted Fill (the bar's _euiInv stamp) paints missing health for every
        -- unit, so the current-health area the Health Bar Color tints and the dispel
        -- wash cover (ns.RF_AnchorCurHealth) is the unit's own, last-known while
        -- offline. A corpse paints a full missing bar, the empty current-health area
        -- of a normal bar at 0%; _ApplyHealthBg hides that fill over the Dead colour.
        local pct
        if health._euiInv then
            pct = deadOrGhost and 100 or GetSafeHealthPercent(unit, true)
        else
            pct = GetSafeHealthPercent(unit)
        end
        health:SetMinMaxValues(0, 100)
        if smooth then
            health:SetValue(pct, smooth)
        else
            health:SetValue(pct)
        end

        if connected and not deadOrGhost then
            local r, g, b = GetHealthColor(unit, s)
            local fillTex = health:GetStatusBarTexture()
            if s.healthColorMode == "dark" then
                health:SetStatusBarColor(r, g, b, 1)
                -- 4th return of GetDarkModeFill() is the Dark Mode Fill Opacity.
                if fillTex then fillTex:SetAlpha(select(4, EllesmereUI.GetDarkModeFill())) end
            else
                if fillTex then fillTex:SetAlpha(1) end
                health:SetStatusBarColor(r, g, b, (s.healthBarOpacity or 100) / 100)
            end
        end
    end

    -- Background (+ dead/offline status tint). Centralized in ns._ApplyHealthBg so the lightweight UNIT_HEALTH path stays in lockstep.
    ns._ApplyHealthBg(d, health, s, unit, connected, deadOrGhost)

    -- Power (filtered by role + hide if unit has no power)
    ns._PaintPower(button, d, s, unit)

    -- Absorb (full paint: re-read the reduced-max percent too)
    d._rmhPct = nil
    UpdateAbsorb(button, unit)

    ns._PaintButtonTail(button, d, s, unit)
end

-- Power bar layout + value: role-gated show/hide, health-height reflow, then the
-- value/color push. Split out of UpdateButton so the roster-state refresh
-- (ns._RefreshRosterState) can re-evaluate the role gate without a full paint.
ns._PaintPower = function(button, d, s, unit)
    local power = d.power
    if power then
        local role = ns._ResolvePowerRole(unit)
        local showForRole = (role == "HEALER" and s.powerShowForHealer)
            or (role == "TANK" and s.powerShowForTank)
            or (role == "DAMAGER" and s.powerShowForDPS)
            or (role == "NONE" and s.powerShowForDPS)
        local pType = UnitPowerType(unit) or 0
        -- maxPower can be a secret number in group context; NEVER compare it in Lua. Treat the unit as powerless only on a CLEAN zero max.
        local pmx = UnitPowerMax(unit, pType)
        local cleanNoPower = (not issecretvalue(pmx)) and (not pmx or pmx == 0)
        local hidePower = not showForRole or cleanNoPower

        -- The Top Name Bar always reserves height from the top (anchor set by LayoutTopNameBar);
        -- subtract it so this per-unit power show/hide never expands health back over the bar.
        local tnbH = (s.topNameBarEnabled and PixelSnap(s.topNameBarHeight or 20)) or 0
        -- Extra Frames duplicates carry a per-group size offset (Extra Height), so the BUTTON is
        -- authoritative -- the shared setting would shrink health and leave a gap every update.
        local frameH = d._isExtra and button:GetHeight() or (s.frameHeight or 46)

        -- Party Frames kit: the mana bar is part of the stock frame and always
        -- shows (an empty track reads as no mana); the kit owns the bar rects.
        if d.kit then d._appliedHidePower = false; hidePower = false end

        -- power:Show()/Hide() and the two SetHeight branches below reflow every decoration
        -- anchored to health (RF_AnchorHost anchors to the live health frame, not a stable
        -- ref). Applying that transition on every call lets an in-combat identity/roster event
        -- (role resync race, a GROUP_ROSTER_UPDATE storm at pull start) pop the whole button's
        -- content stack mid-fight. Only run the transition when hidePower actually changes, and
        -- defer it to combat end if combat is up; flushed from PLAYER_REGEN_ENABLED alongside
        -- the existing _rosterDirtyInCombat/_sizeTierDirtyInCombat deferrals. nil (fresh occupant,
        -- see the OnAttributeChanged reset) applies immediately so a first paint never inherits
        -- a stale layout -- EXCEPT when the health bar is already protected in combat: aura
        -- containers born in the secure environment anchor to it, and a mid-pull header
        -- reassignment (new occupant on a built button) would then write SetHeight under lockdown
        -- and be blocked. A first paint after a mid-combat reload has nothing anchored yet, so
        -- IsProtected is false there and it still applies.
        if d._appliedHidePower ~= hidePower then
            if inCombat and (d._appliedHidePower ~= nil or (d.health and d.health:IsProtected())) then
                d._powerDirtyInCombat = true
                ns._powerDirtyInCombat = true
            else
                d._appliedHidePower = hidePower
                if hidePower then
                    power:Hide()
                    if d.powerBorderFrame and d.powerBorderFrame._powerArtKey then ns.RF_ClearPowerBorderArt(d.powerBorderFrame) end
                    if d.powerBorderFrame then d.powerBorderFrame:Hide() end
                    if d._pwtMode then d.powerText:Hide(); d._pwtMode = nil end
                    -- Expand health bar to full frame height (minus the Top Name Bar)
                    if d.health then
                        d.health:SetHeight(PixelSnap(frameH - tnbH))
                    end
                else
                    -- Restore health bar height with power bar space (and Top Name Bar)
                    local powerH = PixelSnap(s.powerHeight or 4)
                    if d.health then
                        d.health:SetHeight(PixelSnap(frameH - ns.RF_HealthPowerInset(s, powerH) - tnbH))
                    end
                end
            end
        end

        -- Value/color refresh for the power bar in its last APPLIED shown state (not the
        -- freshly computed one), so a deferred transition keeps rendering the old state
        -- instead of updating a bar whose show/hide hasn't actually changed yet.
        if d._appliedHidePower == false then
            -- Smooth interpolation only animates correctly on a bar already shown last frame; on a
            -- fresh hidden->shown transition (profile swap replacing the fill texture) it leaves
            -- the fill at 0. Snap plainly on first show, smooth only after that.
            local wasShown = power:IsShown()
            power:Show()
            if d.UpdatePowerBorder then d.UpdatePowerBorder() end
            -- Power Text: shown/hidden (built on first need) by mode ahead of the edge below,
            -- which colours it. None and never shown = two field reads, no call.
            if d._pwtMode or s.powerTextMode ~= "none" then ns._RFPowerTextSetup(d, s) end
            local smoothPower = wasShown and s.smoothPowerBars and Enum
                and Enum.StatusBarInterpolation
                and Enum.StatusBarInterpolation.ExponentialEaseOut
            -- Percent-based, secret-safe (mirrors health). UnitPower/UnitPowerMax can be secret in
            -- group context and cannot feed SetMinMaxValues; UnitPowerPercent evaluates the secret
            -- C-side against ScaleTo100 and returns a clean 0-100.
            -- Type + color + bounds (+ power-colored bg) through the shared edge,
            -- which stamps d._pwType for the per-tick value path; forced so a
            -- settings-driven full paint always re-tints.
            ns._RFPowerTypeEdge(d, unit, true)
            local ppct = UnitPowerPercent(unit, pType, true, CurveConstants.ScaleTo100)
            if smoothPower then
                power:SetValue(ppct, smoothPower)
            else
                power:SetValue(ppct)
            end
            -- Power Text rides the same value; clearing the dead/offline stamp makes the next
            -- health tick re-check a possibly new occupant.
            local pwtMode = d._pwtMode
            if pwtMode then
                d._pwtGone = nil
                ns.RF_PowerTextInto(d.powerText, pwtMode, ppct, unit, pType)
            end
        end
    end
end

-- Roster-derived state only, for a button whose OCCUPANT did not change across a
-- roster event: leader/assist flag, assigned role (icon + role-gated power layout).
-- Everything else on the button is driven by its own unit events and was current
-- before the roster event, so the full paint (name resolution, absorb, texts,
-- marker, threat) is skipped.
ns._RefreshRosterState = function(button, d, s, unit)
    if not d.styled then return end
    ns._UpdateRoleIcon(d, s, unit)
    ns._UpdateLeaderIcon(d, s, unit)
    ns._PaintPower(button, d, s, unit)
end

-- One button's share of the coalesced roster pass (both roster timers). A paint
-- stamped at or after the cycle's arm time came from the assignment hook (the
-- occupant changed) or a full pass inside the cycle: nothing left to do. A stable
-- occupant (same guid as the hook's last full paint) gets the roster-state refresh.
-- Anything else -- no painted occupant on record, secret guid -- takes the full
-- paint, exactly the old pass.
ns._RosterPassPaint = function(button, unit)
    local d = GetFFD(button)
    local armAt = ns._rosterArmAt
    if armAt and d._fpAt and d._fpAt >= armAt and d._fpUnit == unit then return end
    local guid = d._lastGuid and UnitGUID(unit)
    if guid and not issecretvalue(guid) and d._lastGuid == guid and d._lastUnit == unit then
        local s = d._isParty and ns._scaledPartyProxy or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
        ns._RefreshRosterState(button, d, s, unit)
    else
        UpdateButton(button)
    end
end

-- Second half of the full paint (after power + absorb).
ns._PaintButtonTail = function(button, d, s, unit)
    local EllesmereUI = ns.EllesmereUI  -- upvalue read, not a global read (see the taint note at the top of EllesmereUIRaidFrames.lua)

    -- Name (visibility owned by AnchorNameText, which hides it when the Top Name Bar is enabled)
    -- Level Position "Attach to Name" (either format) puts the level in front of the name,
    -- in both name texts.
    local lvlPos = s.levelTextPosition or ns.RF_LEVEL_DEFAULT
    local lvlAttach = ns.RF_LEVEL_ATTACH[lvlPos]
    if d.nameText then
        if lvlAttach then
            ns._RFNameWithLevel(d.nameText, ResolveDisplayName(unit, true, s), unit, lvlAttach)
        else
            d.nameText:SetText(ResolveDisplayName(unit, true, s))
        end
        local nr, ng, nb = GetNameColor(unit, s)
        d.nameText:SetTextColor(nr, ng, nb)
    end

    -- Level Text on its own spot, in the name's colour. None or attached, never shown = no call.
    if d._lvlOn or (lvlPos ~= "none" and not lvlAttach) then
        ns._RFLevelText(d, s, unit, GetNameColor(unit, s))
    end

    -- Top Name Bar text (unit name + class/custom color); size/anchor/visibility are LayoutTopNameBar's.
    if d.topNameBarText and s.topNameBarEnabled then
        if lvlAttach then
            ns._RFNameWithLevel(d.topNameBarText, ResolveDisplayName(unit, false, s), unit, lvlAttach)
        else
            d.topNameBarText:SetText(ResolveDisplayName(unit, false, s))
        end
        local tr, tg, tb = GetTopNameBarColor(unit, s)
        d.topNameBarText:SetTextColor(tr, tg, tb)
    end

    -- Health text
    if d.healthText then
        local mode = s.healthTextMode or "none"
        -- Hide health %/value while dead/offline (status text shows DEAD/OFFLINE). UnitIsDeadOrGhost
        -- /UnitIsConnected return clean booleans for group units (only UnitIsAFK can be secret).
        if UnitIsDeadOrGhost(unit) or not UnitIsConnected(unit) then
            d.healthText:SetText("")
        elseif mode == "percent" then
            local pct = GetSafeHealthPercent(unit)
            d.healthText:SetFormattedText("%.0f%%", pct)
            local htr, htg, htb = GetHealthTextColor(unit, s)
            if d._htR ~= htr or d._htG ~= htg or d._htB ~= htb then
                d._htR, d._htG, d._htB = htr, htg, htb
                d.healthText:SetTextColor(htr, htg, htb, 0.9)
            end
        elseif mode == "percentNoSign" then
            local pct = GetSafeHealthPercent(unit)
            d.healthText:SetFormattedText("%.0f", pct)
            local htr, htg, htb = GetHealthTextColor(unit, s)
            if d._htR ~= htr or d._htG ~= htg or d._htB ~= htb then
                d._htR, d._htG, d._htB = htr, htg, htb
                d.healthText:SetTextColor(htr, htg, htb, 0.9)
            end
        elseif mode == "number" then
            local curr = UnitHealth(unit, true)
            if curr and AbbreviateNumbers then
                d.healthText:SetText(AbbreviateNumbers(curr))
            elseif curr then
                d.healthText:SetFormattedText("%s", curr)
            end
            local htr, htg, htb = GetHealthTextColor(unit, s)
            if d._htR ~= htr or d._htG ~= htg or d._htB ~= htb then
                d._htR, d._htG, d._htB = htr, htg, htb
                d.healthText:SetTextColor(htr, htg, htb, 0.9)
            end
        elseif mode == "numberPercent" then
            local curr = UnitHealth(unit, true)
            local pct = GetSafeHealthPercent(unit)
            local numStr = (curr and AbbreviateNumbers) and AbbreviateNumbers(curr) or tostring(curr or 0)
            d.healthText:SetFormattedText("%s | %.0f%%", numStr, pct)
            local htr, htg, htb = GetHealthTextColor(unit, s)
            if d._htR ~= htr or d._htG ~= htg or d._htB ~= htb then
                d._htR, d._htG, d._htB = htr, htg, htb
                d.healthText:SetTextColor(htr, htg, htb, 0.9)
            end
        elseif mode == "percentNumber" then
            local curr = UnitHealth(unit, true)
            local pct = GetSafeHealthPercent(unit)
            local numStr = (curr and AbbreviateNumbers) and AbbreviateNumbers(curr) or tostring(curr or 0)
            d.healthText:SetFormattedText("%.0f%% | %s", pct, numStr)
            local htr, htg, htb = GetHealthTextColor(unit, s)
            if d._htR ~= htr or d._htG ~= htg or d._htB ~= htb then
                d._htR, d._htG, d._htB = htr, htg, htb
                d.healthText:SetTextColor(htr, htg, htb, 0.9)
            end
        elseif mode == "missing" then
            local curr = UnitHealthMissing(unit, true)
            d.healthText:SetText(C_StringUtil.TruncateWhenZero(curr))
            if d.healthText:GetText() then
                if curr and AbbreviateNumbers then
                    d.healthText:SetText(AbbreviateNumbers(curr))
                elseif curr then
                    d.healthText:SetFormattedText("%s", curr)
                end
            end
            local htr, htg, htb = GetHealthTextColor(unit, s)
            if d._htR ~= htr or d._htG ~= htg or d._htB ~= htb then
                d._htR, d._htG, d._htB = htr, htg, htb
                d.healthText:SetTextColor(htr, htg, htb, 0.9)
            end
        else
            d.healthText:SetText("")
        end
    end

    -- Heal absorb text
    if d.healAbsorbText then
        if UnitIsDeadOrGhost(unit) or not UnitIsConnected(unit) then
            d.healAbsorbText:SetText("")
        else
            ns.SetHealAbsorbText(d.healAbsorbText, unit, s)
        end
    end

    -- Status text (DEAD / OFFLINE / AFK). The SAME stamped painter as the
    -- UNIT_HEALTH path: the stamp records what is on screen, so a full paint
    -- that shows DEAD on a freshly assigned corpse leaves a stamp the later
    -- resurrect tick can see as a transition.
    ns._PaintStatusText(d, s, unit, UnitIsConnected(unit), UnitIsDeadOrGhost(unit))

    -- Role icon
    ns._UpdateRoleIcon(d, s, unit)

    -- Leader/assistant icon (honors the "Show In Combat" cog)
    ns._UpdateLeaderIcon(d, s, unit)

    -- Combat icon (members currently in combat)
    ns._UpdateCombatIcon(d, s, unit)

    -- Raid marker
    if d.raidMarker then
        if s.showRaidMarker then
            local idx = GetRaidTargetIndex(unit)
            if idx then
                if issecretvalue(idx) then
                    -- Secret-safe path: use SetSpriteSheetCell for secret marker index
                    d.raidMarker:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
                    if d.raidMarker.SetSpriteSheetCell then
                        pcall(d.raidMarker.SetSpriteSheetCell, d.raidMarker, idx, 4, 4, 64, 64)
                    end
                    d.raidMarker:Show()
                elseif RAID_MARKER_TEXCOORDS[idx] then
                    local tc = RAID_MARKER_TEXCOORDS[idx]
                    d.raidMarker:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
                    d.raidMarker:Show()
                else
                    d.raidMarker:Hide()
                end
            else
                d.raidMarker:Hide()
            end
        else
            d.raidMarker:Hide()
        end
    end

    -- Target state: recolor the single border ONLY on a real target transition (hover takes
    -- priority in ApplyBorderColor), keeping recolor + level work off the per-update hot path.
    -- Both operands are clean booleans, so the compare never touches a secret value.
    do
        local isTarget = UnitIsUnit(unit, "target")
        local newTarget = (not issecretvalue(isTarget) and isTarget) and true or false
        if newTarget ~= d._isTarget then
            d._isTarget = newTarget
            if d.ApplyBorderColor then d.ApplyBorderColor() end
        end
    end

    -- Threat highlight (aggro): the inner border (size 0 = off) or the Color Custom Borders recolor
    ns.RF_PaintThreat(d, s, unit)
end

-- UNIT_LEVEL: only the level repaints -- in front of the name (both name texts)
-- or on its own spot, colours untouched; a button whose view shows no level is
-- left alone.
ns._RFRepaintLevel = function(button)
    local unit = button:GetAttribute("unit")
    if not unit or not UnitExists(unit) then return end
    local d = GetFFD(button)
    if not d.styled then return end
    local s = d._isParty and ns._scaledPartyProxy or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
    local lvlAttach = ns.RF_LEVEL_ATTACH[s.levelTextPosition or ns.RF_LEVEL_DEFAULT]
    if lvlAttach then
        if d.nameText then
            ns._RFNameWithLevel(d.nameText, ResolveDisplayName(unit, true, s), unit, lvlAttach)
        end
        if d.topNameBarText and s.topNameBarEnabled then
            ns._RFNameWithLevel(d.topNameBarText, ResolveDisplayName(unit, false, s), unit, lvlAttach)
        end
    elseif d._lvlOn then
        ns._RFLevelInto(d.levelText, unit)
    end
end

-------------------------------------------------------------------------------
--  Dispel detection (secret-value safe). Handles border, overlay
--  (fill/full/gradient), and type icon.
-------------------------------------------------------------------------------

-- "By Me" dispel selection: UpdateDispelBorder queries auras with the
-- "HARMFUL|RAID_PLAYER_DISPELLABLE" filter directly, so the engine returns only
-- player-dispellable auras. Never branch on a (possibly secret) auraInstanceID:
-- negating IsAuraFilteredOutByInstanceID on it is nondeterministic for secret
-- boss debuffs (intermittent highlight).

-- Scratch color reused for dispel overlays (avoids a per-call table alloc).
ns._dispelScratch = ns._dispelScratch or {}
ns._dispelScratchDark = ns._dispelScratchDark or {}

-- Build the dispel-type -> color curves from the user's custom colors.
-- GetAuraDispelTypeColor evaluates the curve against an aura's (secret) dispel type internally, so
-- we never read the secret dispelName/dispelType. Indices are the engine dispel-type enum: 1 Magic,
-- 2 Curse, 3 Disease, 4 Poison, 9 Enrage, 11 Bleed (0 = none). Rebuilt every ReloadFrames.
function ns._RebuildDispelCurves()
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve) then return end
    local function build(profile, mult, alphaMult)
        local c = C_CurveUtil.CreateColorCurve()
        c:SetType(Enum.LuaCurveType.Step)
        local function add(idx, key, dr, dg, db)
            local col = profile and profile[key]
            -- Per-type alpha rides the curve too (0 = type opted out of the dispel border/overlay). Never darkened by mult.
            c:AddPoint(idx, CreateColor((col and col.r or dr) * mult, (col and col.g or dg) * mult,
                (col and col.b or db) * mult, ((col and col.a) or 1) * (alphaMult or 1)))
        end
        add(0,  "dispelColorMagic",   0.349, 0.475, 1.0)   -- none: harmless default
        add(1,  "dispelColorMagic",   0.349, 0.475, 1.0)
        add(2,  "dispelColorCurse",   0.636, 0.0,   0.64)
        add(3,  "dispelColorDisease", 0.671, 0.384, 0.098)
        add(4,  "dispelColorPoison",  0.0,   0.706, 0.286)
        add(9,  "dispelColorBleed",   0.75,  0.15,  0.15)
        add(11, "dispelColorBleed",   0.75,  0.15,  0.15)
        return c
    end
    -- Bright (full) curves + parallel 50%-darkened curves for the clock border's already-elapsed
    -- arc. Darkening applies to the user's CLEAN colors at build time, never a secret per-frame one.
    ns._dispelCurve          = build(ns._scaledProfile,    1)
    ns._dispelCurveParty     = build(ns._scaledPartyProxy, 1)
    ns._dispelCurveDark      = build(ns._scaledProfile,    0.5)
    ns._dispelCurveDarkParty = build(ns._scaledPartyProxy, 0.5)
    -- Overlay curves: per-type alpha premultiplied by the overlay opacity HERE, on plain saved
    -- numbers. The evaluated per-frame alpha is SECRET and arithmetic on it is a hard error --
    -- it may only ever flow straight into setters.
    local rOp = ((ns._scaledProfile    and ns._scaledProfile.dispelOverlayOpacity)    or 100) / 100
    local pOp = ((ns._scaledPartyProxy and ns._scaledPartyProxy.dispelOverlayOpacity) or 100) / 100
    ns._dispelCurveOL      = build(ns._scaledProfile,    1, rOp)
    ns._dispelCurveOLParty = build(ns._scaledPartyProxy, 1, pOp)
end

-------------------------------------------------------------------------------
--  Ready check handling
-------------------------------------------------------------------------------
local readyCheckActive = false
I.readyCheckActiveSetters[#I.readyCheckActiveSetters + 1] = function(v) readyCheckActive = v end

-- Incoming-rez indicator state. UnitHasIncomingResurrection covers only the CAST
-- window: it drops to false the moment the cast lands, while the target still has
-- the accept dialog up. ns._rezPend carries the unit across that edge: true while
-- a cast has been seen, then a GetTime() expiry latched when the flag falls on a
-- still-dead unit (the offer window). Cleared on accept (alive read), a fresh
-- cast, roster shifts (unit tokens move), or the 60s offer expiry. A cancelled
-- cast latches too -- the completion and cancel edges are indistinguishable
-- without a combat log; the alive-clear and expiry bound the miss.
ns._rezPend = {}

-- Shared predicate for the rez icon and the DEAD-text suppression at all paint
-- sites. Writes the casting mark itself so a cast already in flight at paint
-- time (login, roster reassignment) still latches when its completion edge fires.
-- PURE otherwise: it must NEVER clear the latch -- many painters call it (status
-- text, Extra Frames duplicates, full passes) and whichever read first would
-- consume the entry before the icon's own repaint, stranding the icon shown.
-- Clearing belongs to the owners: the INCOMING edges, the UNIT_HEALTH alive
-- edge, the expiry timer, and the roster wipe -- each repaints what it clears.
ns._RFRezShown = function(unit)
    if UnitHasIncomingResurrection(unit) then
        ns._rezPend[unit] = true
        return true
    end
    local exp = ns._rezPend[unit]
    if type(exp) ~= "number" then return false end
    if GetTime() >= exp or not UnitIsDeadOrGhost(unit) then
        return false
    end
    return true
end

-- d.readyCheck is shared by the ready-check, incoming-summon and incoming-rez indicators (rez only
-- on dead units). Priority: active ready check > pending summon > incoming rez.
local function UpdateReadyCheck(button, unit)
    local d = GetFFD(button)
    local tex = d.readyCheck
    if not tex then return end

    -- Party/extra-aware settings source, same as every other indicator updater.
    -- AnchorReadyCheck already resolves LIVE this way, so a raw db.profile read
    -- here re-sized the shared texture back to the RAID value on every paint.
    local s = d._isParty and ns._scaledPartyProxy or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile

    local sz = PixelSnap(s.readyCheckSize or 20)
    tex:SetSize(sz, sz)

    -- Ready check (priority)
    if s.showReadyCheck and readyCheckActive then
        local status = GetReadyCheckStatus(unit)
        if status == "ready" then
            tex:SetAtlas("UI-LFG-ReadyMark-Raid")
            tex:Show()
            return
        elseif status == "notready" then
            tex:SetAtlas("UI-LFG-DeclineMark-Raid")
            tex:Show()
            return
        elseif status == "waiting" then
            tex:SetAtlas("UI-LFG-PendingMark-Raid")
            tex:Show()
            return
        end
    end

    -- Incoming summon
    if s.showSummonPending and unit and C_IncomingSummon.HasIncomingSummon(unit) then
        local sStatus = C_IncomingSummon.IncomingSummonStatus(unit)
        if sStatus == SUMMON_STATUS_PENDING then
            tex:SetAtlas("RaidFrame-Icon-SummonPending")
            tex:Show()
            return
        elseif sStatus == SUMMON_STATUS_ACCEPTED then
            tex:SetAtlas("RaidFrame-Icon-SummonAccepted")
            tex:Show()
            return
        elseif sStatus == SUMMON_STATUS_DECLINED then
            tex:SetAtlas("RaidFrame-Icon-SummonDeclined")
            tex:Show()
            return
        end
    end

    -- Incoming resurrection (cast in flight, or the latched unaccepted-offer window
    -- -- see ns._RFRezShown). Lowest priority; shows a body is already being picked up.
    if s.showIncomingRez and unit and ns._RFRezShown(unit) then
        tex:SetAtlas("RaidFrame-Icon-Rez")
        tex:Show()
        return
    end

    tex:Hide()
end

-------------------------------------------------------------------------------
--  Unit-to-button mapping
-------------------------------------------------------------------------------
local function RebuildUnitMap()
    wipe(unitToButton)
    for _, btn in ipairs(allButtons) do
        if btn:IsVisible() then
            local u = btn:GetAttribute("unit")
            if u then
                local d = GetFFD(btn)
                -- Extra Frames duplicates stay out of the routing map (one button per unit; the
                -- real frame owns the slot). Everything else here applies to them.
                if not d._isExtra then unitToButton[u] = btn end
                -- Cache class token for power border (avoids UnitClass in hot path)
                local _, classToken = UnitClass(u)
                d.classToken = classToken
                -- Repair a container binding the OnAttributeChanged hook dropped because
                -- UnitExists(u) was false at the moment the header assigned it (roster still
                -- streaming in on a zone/group transition). Nothing else re-drives this once
                -- the header stops re-asserting the same token, so aura containers can stay
                -- bound to a stale unit indefinitely.
                if d.rfcUnit ~= u and UnitExists(u) and ns.RFC_OnUnitAssigned then
                    ns.RFC_OnUnitAssigned(btn, d, u)
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Full update for all visible buttons
-------------------------------------------------------------------------------
-- Full-pass paint stamp. The login/zone window runs several IDENTICAL full passes in one frame
-- (assignment paints, the OnEnable reload pass, the visibility rebuild + follow-up). Each full-pass
-- paint stamps the button with (frame time, unit, paint gen); a later identical-body pass in the
-- same frame skips stamped buttons -- same frame + unit + gen reads the same state, so the skipped
-- repaint is provably the same pixels. Targeted event repaints (health, aura singles) neither check
-- nor set the stamp. The gen breaks the window whenever paint INPUTS change mid-frame: settings
-- writes (_BumpAbsorbGen), profile swaps (_ERF_RefreshAll) and cross-module pushes (UpdateAllFrames).
ns._paintGen = 0
local function UpdateAllButtons()
    if previewActive then return end  -- real buttons hidden during preview
    local now, gen = GetTime(), ns._paintGen
    for _, btn in ipairs(allButtons) do
        local u = btn:GetAttribute("unit")
        if u and btn:IsVisible() then
            local d = GetFFD(btn)
            if not (d._fpAt == now and d._fpUnit == u and d._fpGen == gen) then
                d._fpAt = now; d._fpUnit = u; d._fpGen = gen
                UpdateButton(btn)
                UpdateReadyCheck(btn, u)
            end
        end
    end
end

-- Full per-button refresh for a freshly (re)assigned unit; mirrors the per-button work in
-- UpdateAllButtons. On ns so the OnAttributeChanged("unit") watch in StyleButton (created before
-- these locals exist) can repaint the instant the secure header assigns a unit.
ns._RefreshAssignedButton = function(button, unit)
    local d = GetFFD(button)
    if not d.styled then return end  -- not built yet; init paint handles it
    -- Same stamp as UpdateAllButtons (identical body): the assignment paint and a same-frame full pass collapse to one paint.
    local now = GetTime()
    if d._fpAt == now and d._fpUnit == unit and d._fpGen == ns._paintGen then return end
    d._fpAt = now; d._fpUnit = unit; d._fpGen = ns._paintGen
    UpdateButton(button)
    UpdateReadyCheck(button, unit)
end

function ERF:UpdateAllFrames()
    -- Cross-module pushes (Dark Mode master, accent) change paint inputs outside the RF options
    -- funnel: break the same-frame paint-stamp window.
    ns._paintGen = (ns._paintGen or 0) + 1
    UpdateAllButtons()
    -- Party and Boss frames are NOT in `allButtons` (Extra frames ARE, see XF.EnsureBuilt), so
    -- repaint their health too, or Dark Mode / color pushes (ApplyColorsToOUF) miss those frame
    -- types. _UpdateButtonHealth is lightweight, combat-safe and self-guarding.
    if ns._UpdateButtonHealth then
        if ns._partyUnitToButton then
            for u, btn in pairs(ns._partyUnitToButton) do
                ns._UpdateButtonHealth(btn)
                -- Power Text's accent/power colour moves with these pushes too (raid and extra
                -- buttons take it from the full paint above): one field read while it is off.
                local pd = GetFFD(btn)
                if pd._pwtMode then ns._RFPowerTextColor(pd, u, ns._scaledPartyProxy, GetPowerColor(u)) end
            end
        end
        if ns._xfUnitToButton then
            for _, btn in pairs(ns._xfUnitToButton) do ns._UpdateButtonHealth(btn) end
        end
    end
    -- Boss and pet frames paint through their own painter (names and their colours included).
    local FB = ns._FB
    for _, btn in ipairs(FB.buttons) do
        if btn:IsVisible() then FB.Update(btn) end
    end
    ns._PF_RefreshVisible()
    -- Party target frames: their fill and background read the Dark Mode and class palettes too.
    ns._PT_RepaintVisible()
end

-- Lightweight: only toggle raid markers on each button (for RAID_TARGET_UPDATE)
ns._UpdateRaidMarkers = function()
    local function updateMarker(unit, btn)
        local d = GetFFD(btn)
        local s = d._isParty and ns._scaledPartyProxy or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
        if not s.showRaidMarker then
            if d.raidMarker then d.raidMarker:Hide() end
            return
        end
        if d.raidMarker then
            local idx = GetRaidTargetIndex(unit)
            if idx then
                if issecretvalue(idx) then
                    d.raidMarker:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
                    if d.raidMarker.SetSpriteSheetCell then
                        pcall(d.raidMarker.SetSpriteSheetCell, d.raidMarker, idx, 4, 4, 64, 64)
                    end
                    d.raidMarker:Show()
                elseif RAID_MARKER_TEXCOORDS[idx] then
                    local tc = RAID_MARKER_TEXCOORDS[idx]
                    d.raidMarker:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
                    d.raidMarker:Show()
                else
                    d.raidMarker:Hide()
                end
            else
                d.raidMarker:Hide()
            end
        end
    end
    for unit, btn in pairs(unitToButton) do updateMarker(unit, btn) end
    for unit, btn in pairs(ns._partyUnitToButton) do updateMarker(unit, btn) end
    for unit, btn in pairs(ns._xfUnitToButton) do updateMarker(unit, btn) end
end

-- Lightweight: only toggle target border on each button (for PLAYER_TARGET_CHANGED)
ns._UpdateTargetBorders = function()
    local function updateTarget(unit, btn)
        local d = GetFFD(btn)
        local isTarget = UnitIsUnit(unit, "target")
        d._isTarget = (not issecretvalue(isTarget) and isTarget) and true or false
        if d.ApplyBorderColor then d.ApplyBorderColor() end
    end
    for unit, btn in pairs(unitToButton) do updateTarget(unit, btn) end
    for unit, btn in pairs(ns._partyUnitToButton) do updateTarget(unit, btn) end
    for unit, btn in pairs(ns._xfUnitToButton) do updateTarget(unit, btn) end
end

-- Lightweight: role icons only. Driven by combat transitions so the "Hide In Combat" cog
-- suppresses/restores without a full repaint. Texture Show/Hide is combat-legal.
ns._UpdateRoleIcons = function()
    local function updateRole(unit, btn)
        local d = GetFFD(btn)
        if not d.roleIcon then return end
        local s = d._isParty and ns._scaledPartyProxy or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
        ns._UpdateRoleIcon(d, s, unit)
    end
    for unit, btn in pairs(unitToButton) do updateRole(unit, btn) end
    for unit, btn in pairs(ns._partyUnitToButton) do updateRole(unit, btn) end
    for unit, btn in pairs(ns._xfUnitToButton) do updateRole(unit, btn) end
end

-- Lightweight: refresh leader/assistant icons only (combat transitions; "Show
-- In Combat" cog) without a full repaint. Texture Show/Hide is combat-legal.
ns._UpdateLeaderIcons = function()
    local function updateLeader(unit, btn)
        local d = GetFFD(btn)
        if not d.leaderIcon then return end
        local s = d._isParty and ns._scaledPartyProxy or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
        ns._UpdateLeaderIcon(d, s, unit)
    end
    for unit, btn in pairs(unitToButton) do updateLeader(unit, btn) end
    for unit, btn in pairs(ns._partyUnitToButton) do updateLeader(unit, btn) end
    for unit, btn in pairs(ns._xfUnitToButton) do updateLeader(unit, btn) end
end

-- Lightweight: refresh combat icons only (UNIT_FLAGS flips + combat
-- transitions). Texture Show/Hide is combat-legal, safe from PLAYER_REGEN_DISABLED.
ns._UpdateCombatIcons = function()
    local function updateCombat(unit, btn)
        local d = GetFFD(btn)
        if not d.combatIcon then return end
        local s = d._isParty and ns._scaledPartyProxy or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
        ns._UpdateCombatIcon(d, s, unit)
    end
    for unit, btn in pairs(unitToButton) do updateCombat(unit, btn) end
    for unit, btn in pairs(ns._partyUnitToButton) do updateCombat(unit, btn) end
    for unit, btn in pairs(ns._xfUnitToButton) do updateCombat(unit, btn) end
end

-- Single-unit combat icon refresh for UNIT_FLAGS routing (raid + party).
ns._UpdateCombatIconFor = function(unit, btn)
    local d = GetFFD(btn)
    if not d.combatIcon then return end
    local s = d._isParty and ns._scaledPartyProxy or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile
    ns._UpdateCombatIcon(d, s, unit)
end

-- True when the combat icon is enabled anywhere (raid or effective party); skips all combat-icon work while off.
ns._CombatIconEnabled = function()
    if not (db and db.profile) then return false end
    if db.profile.showCombatIndicator then return true end
    if ns._partyProxy.showCombatIndicator then return true end
    return false
end

-- Register UNIT_FLAGS on the per-unit trackers ONLY while the combat icon is enabled (raid key;
-- party effective key): off = no tracker listens, zero event code for a disabled feature. Event
-- (un)registration is combat-legal. Extra Frames trackers gate separately in XF_Apply. Called
-- from ReloadFrames and once after the trackers are built.
ns.UpdateCombatEventRegistration = function()
    if not (db and db.profile) then return end
    local raidWant  = db.profile.showCombatIndicator and true or false
    local partyWant = ns._partyProxy.showCombatIndicator and true or false
    for unit, tracker in pairs(unitTrackers) do
        local want
        if unit == "player" then
            want = raidWant or partyWant
        elseif unit:find("^party%d") then
            want = partyWant
        else
            want = raidWant
        end
        if want then
            tracker:RegisterUnitEvent("UNIT_FLAGS", unit)
        else
            tracker:UnregisterEvent("UNIT_FLAGS")
        end
    end
end

-- Lightweight health-only update for UNIT_HEALTH / UNIT_MAXHEALTH. Skips power/name/role/leader/marker/target/threat -- each has its own event path.
-- Status text (DEAD / OFFLINE / AFK), the ONE painter for both the full paint and
-- the UNIT_HEALTH path. State + color stamped: text/color/visibility re-apply
-- only on a real transition (0 hidden, 1 offline, 2 dead, 3 AFK); the stamp is
-- the on-screen state, so it stays valid across occupants and across the two
-- paths. The rez check runs only for dead units: a live unit can never carry an
-- incoming resurrection (the offer latch also requires dead), so the C probe is
-- skipped for the alive majority -- the same shape as Blizzard's
-- CompactUnitFrame, which never probes rez from its UNIT_HEALTH path.
ns._PaintStatusText = function(d, s, unit, connected, deadOrGhost)
    local statusText = d.statusText
    if not statusText then return end
    local stc = s.statusTextColor or { r = 1, g = 1, b = 1 }
    local st
    if s.statusTextPosition == "none" then
        st = 0
    elseif deadOrGhost and s.showIncomingRez and ns._RFRezShown(unit) then
        -- Being resurrected: hide the status text so the incoming-rez icon isn't covered.
        st = 0
    elseif not connected then
        st = 1
    elseif deadOrGhost then
        st = 2
    else
        local afk
        if s.statusShowAFK and UnitIsAFK then
            afk = UnitIsAFK(unit)
            if issecretvalue(afk) then afk = nil end
        end
        st = afk and 3 or 0
    end
    if d._stSt ~= st or d._stR ~= stc.r or d._stG ~= stc.g or d._stB ~= stc.b then
        d._stSt, d._stR, d._stG, d._stB = st, stc.r, stc.g, stc.b
        if st == 0 then
            statusText:Hide()
        else
            local L = ns.EllesmereUI.L
            statusText:SetText(st == 1 and L("OFFLINE") or st == 2 and L("DEAD") or L("AFK"))
            statusText:SetTextColor(stc.r, stc.g, stc.b)
            statusText:Show()
        end
    end
end

ns._UpdateButtonHealth = function(button, unit)
    -- Dispatchers pass the event's unit token (a unit that just fired an event
    -- exists -- no probe); rare callers omit it and pay the existence check.
    if not unit then
        unit = button:GetAttribute("unit")
        if not unit or not UnitExists(unit) then return end
    end
    local d = GetFFD(button)
    if not d.styled then return end
    local s = d._isParty and ns._scaledPartyProxy or (d._isExtra and ns._scaledExtraProxy) or ns._scaledProfile

    local health = d.health
    local pct = GetSafeHealthPercent(unit)
    local connected = UnitIsConnected(unit)
    local deadOrGhost = UnitIsDeadOrGhost(unit)

    -- Health bar
    if health then
        -- The bar is always a percent bar; its range never changes after the
        -- first application.
        if not d._hb100 then d._hb100 = true; health:SetMinMaxValues(0, 100) end
        local smooth = s.smoothBars and Enum and Enum.StatusBarInterpolation
            and Enum.StatusBarInterpolation.ExponentialEaseOut
        -- Missing health under Inverted Fill, every unit (see UpdateButton).
        local barPct = pct
        if health._euiInv then
            barPct = deadOrGhost and 100 or GetSafeHealthPercent(unit, true)
        end
        if smooth then
            health:SetValue(barPct, smooth)
        else
            health:SetValue(barPct)
        end
        -- Fill color: dead/offline ticks skip this entirely (_ApplyHealthBg
        -- owns the gray tint and clears the stamp on the transition). The
        -- curve modes recolor with health, so they apply every tick; static
        -- modes stamp the applied color and re-run only on a real change
        -- (every static-mode component is a plain value by construction).
        if connected and not deadOrGhost then
            local mode = s.healthColorMode
            local r, g, b
            if mode == nil or mode == "class" then
                -- Class color is identity, not health: resolve the class token
                -- once per occupant and reuse it per tick. Cleared on unit
                -- assignment, UNIT_NAME_UPDATE and UNIT_CONNECTION -- the edges
                -- Blizzard's CompactUnitFrame recolors on -- so it can never
                -- outlive the person behind the token. A secret token (identity
                -- restricted) is never cached: fail open to the per-tick read
                -- and the neutral gray, exactly as before.
                local tok = d._clsTok
                if not tok then
                    local _, ct = UnitClass(unit)
                    if ct and not issecretvalue(ct) then
                        tok = ct
                        d._clsTok = ct
                    end
                end
                local cc = tok and ns.EllesmereUI.GetClassColor(tok)
                if cc then r, g, b = cc.r, cc.g, cc.b else r, g, b = 0.5, 0.5, 0.5 end
            else
                r, g, b = GetHealthColor(unit, s)
            end
            if mode == "classic" or mode == "customDynamic" or mode == "classReactive" then
                local fillTex = health:GetStatusBarTexture()
                if fillTex then fillTex:SetAlpha(1) end
                health:SetStatusBarColor(r, g, b, (s.healthBarOpacity or 100) / 100)
            else
                local a = (mode == "dark") and 1 or (s.healthBarOpacity or 100) / 100
                if d._hcR ~= r or d._hcG ~= g or d._hcB ~= b or d._hcA ~= a or d._hcM ~= mode then
                    d._hcR, d._hcG, d._hcB, d._hcA, d._hcM = r, g, b, a, mode
                    local fillTex = health:GetStatusBarTexture()
                    if mode == "dark" then
                        health:SetStatusBarColor(r, g, b, 1)
                        -- 4th return of GetDarkModeFill() is the Dark Mode Fill Opacity.
                        if fillTex then fillTex:SetAlpha(select(4, EllesmereUI.GetDarkModeFill())) end
                    else
                        if fillTex then fillTex:SetAlpha(1) end
                        health:SetStatusBarColor(r, g, b, a)
                    end
                end
            end
        end
    end

    -- Health text
    if d.healthText then
        local mode = s.healthTextMode or "none"
        -- Hide health text while dead/offline (see UpdateButton; matches preview).
        if deadOrGhost or not connected then
            d.healthText:SetText("")
        elseif mode == "percent" then
            d.healthText:SetFormattedText("%.0f%%", pct)
            local htr, htg, htb = GetHealthTextColor(unit, s)
            if d._htR ~= htr or d._htG ~= htg or d._htB ~= htb then
                d._htR, d._htG, d._htB = htr, htg, htb
                d.healthText:SetTextColor(htr, htg, htb, 0.9)
            end
        elseif mode == "percentNoSign" then
            d.healthText:SetFormattedText("%.0f", pct)
            local htr, htg, htb = GetHealthTextColor(unit, s)
            if d._htR ~= htr or d._htG ~= htg or d._htB ~= htb then
                d._htR, d._htG, d._htB = htr, htg, htb
                d.healthText:SetTextColor(htr, htg, htb, 0.9)
            end
        elseif mode == "number" then
            local curr = UnitHealth(unit, true)
            if curr and AbbreviateNumbers then
                d.healthText:SetText(AbbreviateNumbers(curr))
            elseif curr then
                d.healthText:SetFormattedText("%s", curr)
            end
            local htr, htg, htb = GetHealthTextColor(unit, s)
            if d._htR ~= htr or d._htG ~= htg or d._htB ~= htb then
                d._htR, d._htG, d._htB = htr, htg, htb
                d.healthText:SetTextColor(htr, htg, htb, 0.9)
            end
        elseif mode == "numberPercent" then
            local curr = UnitHealth(unit, true)
            local numStr = (curr and AbbreviateNumbers) and AbbreviateNumbers(curr) or tostring(curr or 0)
            d.healthText:SetFormattedText("%s | %.0f%%", numStr, pct)
            local htr, htg, htb = GetHealthTextColor(unit, s)
            if d._htR ~= htr or d._htG ~= htg or d._htB ~= htb then
                d._htR, d._htG, d._htB = htr, htg, htb
                d.healthText:SetTextColor(htr, htg, htb, 0.9)
            end
        elseif mode == "percentNumber" then
            local curr = UnitHealth(unit, true)
            local numStr = (curr and AbbreviateNumbers) and AbbreviateNumbers(curr) or tostring(curr or 0)
            d.healthText:SetFormattedText("%.0f%% | %s", pct, numStr)
            local htr, htg, htb = GetHealthTextColor(unit, s)
            if d._htR ~= htr or d._htG ~= htg or d._htB ~= htb then
                d._htR, d._htG, d._htB = htr, htg, htb
                d.healthText:SetTextColor(htr, htg, htb, 0.9)
            end
        elseif mode == "missing" then
            local curr = UnitHealthMissing(unit, true)
            d.healthText:SetText(C_StringUtil.TruncateWhenZero(curr))
            if d.healthText:GetText() then
                if curr and AbbreviateNumbers then
                    d.healthText:SetText(AbbreviateNumbers(curr))
                elseif curr then
                    d.healthText:SetFormattedText("%s", curr)
                end
            end
            local htr, htg, htb = GetHealthTextColor(unit, s)
            if d._htR ~= htr or d._htG ~= htg or d._htB ~= htb then
                d._htR, d._htG, d._htB = htr, htg, htb
                d.healthText:SetTextColor(htr, htg, htb, 0.9)
            end
        else
            d.healthText:SetText("")
        end
    end

    -- Heal absorb text
    if d.healAbsorbText then
        if deadOrGhost or not connected then
            d.healAbsorbText:SetText("")
        else
            ns.SetHealAbsorbText(d.healAbsorbText, unit, s)
        end
    end

    -- Status text (dead/ghost state changes with health)
    ns._PaintStatusText(d, s, unit, connected, deadOrGhost)

    -- Power Text blanks and refills on the same dead/offline edge (death and resurrection need
    -- not move a power value): one field read while it is off.
    if d._pwtMode then ns._RFPowerTextLife(d, unit, deadOrGhost or not connected) end

    -- Background + dead/offline tint. This path owns death/resurrect transitions
    -- arriving via UNIT_HEALTH, so it runs per tick (state-stamped inside).
    ns._ApplyHealthBg(d, health, s, unit, connected, deadOrGhost)

    -- Debuff Manager dead-corpse swap rides the same ownership: one field read
    -- for every button without a qualifying config.
    if d.dmDeadSwap then ns.DM_DeadEdge(d, unit) end
end

-- Two-step max-health landing (max first, value after): one next-frame re-read
-- settles torn numbers; the flag collapses a raid-wide change to one pass per
-- button (canonical story: UF engine RESETTLE_EVENTS). Flag lives in FFD --
-- header children never carry insecure keys.
ns._ResettleButtonHealth = function(button)
    local d = GetFFD(button)
    if d.hpResettle then return end
    d.hpResettle = true
    C_Timer.After(0, function()
        d.hpResettle = nil
        if button:IsVisible() then ns._UpdateButtonHealth(button) end
    end)
end

I.RebuildUnitMap, I.UpdateAllButtons = RebuildUnitMap, UpdateAllButtons
I.UpdateButton, I.UpdateReadyCheck = UpdateButton, UpdateReadyCheck
I.broken = false
