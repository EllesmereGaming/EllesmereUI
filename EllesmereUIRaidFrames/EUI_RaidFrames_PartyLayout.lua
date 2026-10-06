if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_RaidFrames_PartyLayout.lua
--
--  The party layout, the kit portrait events, party visibility,
--  ReloadPartyFrames and the unlock mode registration.
--  Reads the earlier Raid Frames files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- EllesmereUIRaidFrames.lua or an earlier Raid Frames file failed to load.
if not I or I.broken then return end
I.broken = true

local floor        = math.floor
local pairs        = pairs
local ipairs       = ipairs
local wipe         = wipe
local tostring     = tostring
local UnitExists            = UnitExists
local IsInRaid              = IsInRaid
local IsInGroup             = IsInGroup
local InCombatLockdown      = InCombatLockdown

local allButtons, ApplyFont, eventFrame = I.allButtons, I.ApplyFont, I.eventFrame
local GetFFD, IsPowerBarEnabled, PixelSnap = I.GetFFD, I.IsPowerBarEnabled, I.PixelSnap
local ResolveHealthTexture, unitToButton = I.ResolveHealthTexture, I.unitToButton
local unitTrackers, LayoutTopNameBar = I.unitTrackers, I.LayoutTopNameBar
local StyleButton, StartGhostTicker = I.StyleButton, I.StartGhostTicker
local StartRangeTicker, StopGhostTicker = I.StartRangeTicker, I.StopGhostTicker
local StopRangeTicker, SetFramesVisible = I.StopRangeTicker, I.SetFramesVisible

local db
I.dbSetters[#I.dbSetters + 1] = function(v) db = v end
local containerFrame
I.containerFrameSetters[#I.containerFrameSetters + 1] = function(v) containerFrame = v end
local framesVisible = false
I.framesVisibleSetters[#I.framesVisibleSetters + 1] = function(v) framesVisible = v end

-- Layout party frames: apply unitGrowth direction and cell spacing to the header.
ns._LayoutPartyFrames = function()
    if not ns._partyHeader then return end
    if InCombatLockdown() then return end

    local s = db.profile
    local pw, ph, pcs = ns.RF_PartyDims(s)
    local bw, bh, cs = PixelSnap(pw), PixelSnap(ph), PixelSnap(pcs)
    -- Party target frames along the stack sit between the frames: the pitch opens by their room.
    local along = ns.PT_AlongPitch(s)
    ns._ptPitchApplied = along
    cs = cs + along
    local unitGrowth = ns._PartyGrowth(s)

    local hdrPoint, hdrXOff, hdrYOff
    if unitGrowth == "DOWN" then
        hdrPoint = "TOP";    hdrXOff = 0;   hdrYOff = -cs
    elseif unitGrowth == "UP" then
        hdrPoint = "BOTTOM"; hdrXOff = 0;   hdrYOff = cs
    elseif unitGrowth == "RIGHT" then
        hdrPoint = "LEFT";   hdrXOff = cs;  hdrYOff = 0
    else -- LEFT
        hdrPoint = "RIGHT";  hdrXOff = -cs; hdrYOff = 0
    end

    local needsRelayout = ns._partyHeader:GetAttribute("point") ~= hdrPoint
        or ns._partyHeader:GetAttribute("xOffset") ~= hdrXOff
        or ns._partyHeader:GetAttribute("yOffset") ~= hdrYOff
    if needsRelayout then
        local wasShown = ns._partyHeader:IsShown()
        if wasShown then ns._partyHeader:Hide() end
        for i = 1, 5 do
            local btn = ns._partyHeader[i]
            if btn then btn:ClearAllPoints() end
        end
        ns._partyHeader:SetAttribute("point", hdrPoint)
        ns._partyHeader:SetAttribute("xOffset", hdrXOff)
        ns._partyHeader:SetAttribute("yOffset", hdrYOff)
        if wasShown then ns._partyHeader:Show() end
    end

    -- Self button + header slot positioning (also sets the header's own size,
    -- which drives the children's centered anchors). Shared with the slider
    -- hot path; returns useSelf for the showPlayer attribute logic below.
    -- Self-first via composition: a static unit="player" self button owns
    -- slot 0 and the party header excludes the player (showPlayer=false);
    -- self ordering only matters in a group (see ns._PositionPartySlots).
    local useSelf = ns._PositionPartySlots(bw, bh, cs, unitGrowth)
    local hideSelf = s.partyHideSelf

    -- Size container for unlock mode mover (always sized for 5 units)
    ns._SizePartyContainer(bw, bh, cs, unitGrowth)

    -- Apply sort attributes + player visibility to the party header
    if not InCombatLockdown() then
        local pSortMode = s.partySortMode or s.sortMode
        local sortByRole = pSortMode == "ROLE"
        local roleOrder = s.partyRoleOrder or s.roleOrder or { "TANK", "HEALER", "DAMAGER" }
        -- A party set the group state hides takes no nameList: a nameList is also
        -- a filter, and the visibility driver can show the set mid-fight, when no
        -- list can be rebuilt, so a stale one would drop the new members. The
        -- shown pass (_UpdatePartyVisibility) applies the lists.
        local _, live = ns._RFVisWanted()
        -- Sort By = FrameSort: a nameList in FrameSort's order (native index
        -- order while FrameSort is absent or its list is empty).
        local fsRank = live and (pSortMode == "FRAMESORT") and ns._FrameSortRanks(not ns._fsFromProvider) or nil
        -- showPlayer is false when the self button owns the player (useSelf) or
        -- when hiding self; true only for a normal in-header player frame. In
        -- arena useSelf is forced false (no self button), so this reduces to
        -- "show the player unless Hide Self" -- and the arena nameList below
        -- keeps membership consistent by omitting the player when Hide Self.
        local wantShowPlayer = not hideSelf and not useSelf

        -- Prioritize Class drives the header with an explicit nameList ordered by
        -- role (optional primary) -> class -> name. nameList is honored only when
        -- groupFilter is cleared, so we clear it and let showParty/showPlayer pick
        -- members. When off, fall back to the native groupBy/sortMethod path.
        local wantGroupBy, wantSortMethod, wantGroupingOrder, wantNameList, wantGroupFilter
        local smallRaidGroup = ns._SmallRaidGroup()
        if not live then
            -- Hidden set: the native path below.
        elseif ns._PartyInRaid() then
            -- Party-in-raid runs on raid units, where Prioritize Class cannot
            -- work (it iterates party1-4) and neither the self button nor
            -- showPlayer can order or hide the player. A raid-token nameList
            -- does both: it honors Show Self First / Self Last / Hide Self and
            -- still shows every teammate -- the whole team in arena, group 1
            -- only in Small Raid mode (bailing to native order until names
            -- resolve; the fallback groupFilter below keeps the group limit).
            if fsRank then
                wantNameList = ns._BuildFrameSortRaidPartyNameList(fsRank, hideSelf, smallRaidGroup)
            end
            if not wantNameList then
                local pSelfFirst = s.partyShowSelfFirst
                if pSelfFirst == nil then pSelfFirst = s.showSelfFirst end
                local pSelfLast = s.partySelfLast
                if pSelfLast == nil then pSelfLast = s.showSelfLast end
                wantNameList = ns._BuildArenaNameList(hideSelf, pSelfFirst, pSelfLast, sortByRole, roleOrder, smallRaidGroup)
            end
        elseif fsRank then
            wantNameList = ns._BuildFrameSortPartyNameList(fsRank, wantShowPlayer)
        elseif s.partyPrioritizeClass then
            wantNameList = ns._BuildPartyClassNameList(wantShowPlayer, sortByRole, roleOrder, s.partyClassOrder)
        end
        if wantNameList then
            wantGroupBy = nil
            wantSortMethod = "NAMELIST"
            wantGroupingOrder = ""
            wantGroupFilter = nil
        else
            wantNameList = nil
            wantGroupBy = sortByRole and "ASSIGNEDROLE" or nil
            wantSortMethod = sortByRole and "NAME" or "INDEX"
            wantGroupingOrder = sortByRole and (table.concat(roleOrder, ",") .. ",NONE") or ""
            -- Small Raid keeps its group-1 limit in a party too (every party member
            -- is subgroup 1 there), so a party the driver keeps shown as it turns
            -- into a small raid mid-fight shows group 1, not the first five raiders.
            local fGroup = smallRaidGroup or ((s.partySmallRaid == true and not ns._InArena()) and 1) or nil
            wantGroupFilter = fGroup and tostring(fGroup) or "1,2,3,4,5,6,7,8"
        end

        local function ApplyAttrs()
            ns._partyHeader:SetAttribute("groupFilter", wantGroupFilter)
            ns._partyHeader:SetAttribute("nameList", wantNameList)
            ns._partyHeader:SetAttribute("groupingOrder", wantGroupingOrder)
            ns._partyHeader:SetAttribute("groupBy", wantGroupBy)
            ns._partyHeader:SetAttribute("sortMethod", wantSortMethod)
            ns._partyHeader:SetAttribute("showPlayer", wantShowPlayer)
        end
        local needsHideShow = (ns._partyHeader:GetAttribute("groupBy") ~= wantGroupBy)
            or (ns._partyHeader:GetAttribute("sortMethod") ~= wantSortMethod)
            or (ns._partyHeader:GetAttribute("groupingOrder") ~= wantGroupingOrder)
            or (ns._partyHeader:GetAttribute("showPlayer") ~= wantShowPlayer)
            or (ns._partyHeader:GetAttribute("nameList") ~= wantNameList)
            or (ns._partyHeader:GetAttribute("groupFilter") ~= wantGroupFilter)
        if needsHideShow then ns._fsChanged = true end
        if needsHideShow and ns._partyHeader:IsShown() then
            ns._partyHeader:Hide()
            ApplyAttrs()
            ns._partyHeader:Show()
        elseif needsHideShow then
            ApplyAttrs()
        end
        -- Which layout the header now carries (shown: full; hidden: native), for
        -- _UpdatePartyVisibility to re-lay it when the set hides.
        ns._partyLaidVis = live
    end

    -- Self button + header slot positioning ran above (ns._PositionPartySlots),
    -- before the attribute pass so a header Hide/Show re-process anchors the
    -- children against the already-correct header position and size.

    -- The friendly boss group attaches to this container (and to the growth axis derived above)
    -- while not in a raid, so every layout pass -- Horizontal Frames, Flip Growth, party size,
    -- cell spacing -- has to move it too. OOC only (this function bails in combat). In a raid the
    -- boss group hangs off the raid headers instead, so skip the re-anchor scan there.
    if (not IsInRaid() or ns._PartyInRaid()) and ns.FB_ReAnchor then ns.FB_ReAnchor() end
    -- The party target frames ride FB_ReAnchor above; this covers the raid branch that skips it
    -- (delta-gated, a no-op after it).
    ns._PT_Layout()
end

-- Party visibility: show/hide based on group state.
-- Party portraits (the Party Frames kit's socket, or the PORTRAIT section):
-- the portrait events, registered only while the party frames are shown
-- with a portrait that needs them (nothing runs while they are hidden, the
-- portrait is off or it shows class art; UNIT_MODEL_CHANGED for a 3D model
-- alone). Tokens a party button can hold: player/party1-4 in a party,
-- raid1-9 in arena and Small Raid mode (group 1 of a raid under 10 members
-- can sit at any raid index up to 9). Turning them on repaints every
-- portrait once, which covers any change made while the frames were hidden.
-- Called on the visibility edges and after every party reload (settings).
ns._kitPortraitUnits = { "player", "party1", "party2", "party3", "party4",
    "raid1", "raid2", "raid3", "raid4", "raid5", "raid6", "raid7", "raid8", "raid9" }
ns.RF_KitPortraitEvents = function(on)
    -- Before the unit trackers exist there is nothing to register yet.
    if not unitTrackers.player then return end
    local kit = ns.RF_PartyKit()
    on = on and true or false
    -- Kit hide edge: its always-on power registrations go too.
    if kit and ns._kitShownEv ~= on then
        ns._kitShownEv = on
        if not on and ns.UpdatePowerEventRegistration then ns.UpdatePowerEventRegistration() end
    end
    local art = on and ns.RF_PtEventMode and ns.RF_PtEventMode(kit) or nil
    local want, wantModel = art ~= nil, art == "3d"
    local was, wasModel = ns._kitPortraitEv or false, ns._ptModelEv or false
    if was == want and wasModel == wantModel then return end
    ns._kitPortraitEv, ns._ptModelEv = want, wantModel
    local units = ns._kitPortraitUnits
    for i = 1, #units do
        local u = units[i]
        local t = unitTrackers[u]
        if t then
            if want ~= was then
                if want then t:RegisterUnitEvent("UNIT_PORTRAIT_UPDATE", u)
                else t:UnregisterEvent("UNIT_PORTRAIT_UPDATE") end
            end
            if wantModel ~= wasModel then
                if wantModel then t:RegisterUnitEvent("UNIT_MODEL_CHANGED", u)
                else t:UnregisterEvent("UNIT_MODEL_CHANGED") end
            end
        end
    end
    if want and not was then
        eventFrame:RegisterEvent("PORTRAITS_UPDATED")
        -- 2D art and the kit socket repaint; a 3D model repaints on its own
        -- show edge (and on a settings swap through its cleared memos).
        if ns.RF_PtRepaintAll then ns.RF_PtRepaintAll("Resync") end
    elseif was and not want then
        eventFrame:UnregisterEvent("PORTRAITS_UPDATED")
    end
end

ns._UpdatePartyVisibility = function()
    if not ns._partyHeader then return end
    if InCombatLockdown() then return end
    if ns._partyPvActive then return end
    if previewActive then return end
    -- Defensive: re-assert full opacity unless a size preview is dimming the
    -- real frames (see UpdateVisibility). Out of combat only (bails above).
    if not ns._sizePreviewTier and ns._partyContainerFrame then
        local dimmed = ns._partyContainerFrame:GetAlpha() ~= 1
        ns._partyContainerFrame:SetAlpha(1)
        if ns._ptModelOn then ns.RF_PtContainerAlpha(1) end
        if dimmed then ns._PF_AlphaSync() end
    end

    local s = db.profile
    -- Profile and spec-override swaps: Include Own Target first, so an enable edge below takes it.
    if ns._ptInclDesired ~= (s.partyTargetIncludeSelf == true) then
        ns.PT_SetIncludeSelf(s.partyTargetIncludeSelf)
    end
    -- An enable edge here refreshes the target frames itself (the show edge below then skips it).
    local ptWas = ns._ptEnabled
    if ns._ptDesired ~= (s.partyShowTargets == true) then
        ns.PT_SetEnabled(s.partyShowTargets)
    end
    -- Arena and Small Raid mode show party frames even though IsInRaid() is
    -- true. The header binds raid units via showRaid=true; the raid container
    -- is hidden there by UpdateVisibility.
    local _, visible = ns._RFVisWanted()
    local wasVisible = ns._partyFramesVisible
    ns._partyFramesVisible = visible
    if ns._NotifyTrackerProviders then ns._NotifyTrackerProviders() end

    -- Update showSolo attribute, but only when it changed -- re-setting a
    -- SecureGroupHeader attribute re-triggers a full child re-process even when
    -- unchanged (see UpdateVisibility's showSolo guard).
    local wantPartySolo = s.partyShowWhenSolo or false
    if ns._partyHeader and ns._partyHeader:GetAttribute("showSolo") ~= wantPartySolo then
        ns._partyHeader:SetAttribute("showSolo", wantPartySolo)
    end

    -- Only the container shows and hides (the header stays shown inside it);
    -- the driver decides the same way, synced first so the two agree this frame.
    ns._RFSyncVisDrivers()
    ns._partyContainerFrame:SetShown(visible)
    if visible then
        -- Suppress Blizzard party frames
        if ns._SuppressBlizzParty then
            ns._SuppressBlizzParty()
        end

        ns._LayoutPartyFrames()
        ns._RebuildPartyUnitMap()
        if ns.UpdatePowerEventRegistration then ns.UpdatePowerEventRegistration() end
        ns._UpdateAllPartyButtons()
        ns.RF_KitPortraitEvents(true)

        if IsInGroup() then
            StartRangeTicker()
            StartGhostTicker()
        end
    else
        if not framesVisible then
            StopRangeTicker()
            StopGhostTicker()
        end

        if wasVisible then ns._RFForgetOccupants(ns._partyAllButtons) end
        wipe(ns._partyUnitToButton)
        ns.RF_KitPortraitEvents(false)
        -- A hidden set runs native (see _LayoutPartyFrames), so the driver can
        -- show it mid-fight with every member in place.
        if ns._partyLaidVis ~= false then ns._LayoutPartyFrames() end
    end

    -- Attach-point edges the layout pass above cannot cover: the boss group's own roster pass can
    -- run before the party frames are up, and the hidden branch lays out only when the set hides
    -- (the group then falls back to its free position). EDGE only -- this recompute runs on every
    -- roster event.
    if ns._fbPartyAttachState ~= visible then
        ns._fbPartyAttachState = visible
        if ns.FB_ReAnchor then ns.FB_ReAnchor() end
    end
    -- Party target frames skip roster refreshes while the party frames are hidden: their show edge
    -- takes one (units, your raid token, the listeners). EDGE only.
    if ns._ptVisState ~= visible then
        ns._ptVisState = visible
        if visible and ptWas then ns._PT_RefreshAll() end
    end
end

-- Combat half of the two passes above. In combat the visibility drivers show
-- and hide the containers themselves; this keeps the Lua side in step with no
-- protected call: the flags that gate unit events, the routing maps, the range
-- and ghost tickers, the power and portrait registrations, the tracker
-- providers. The shown set's header re-reads the roster as it shows, and each
-- assignment remaps and repaints its button. Edge-gated (a roster storm with no
-- set change costs two compares); an edge marks the roster dirty so combat end
-- runs the full passes (layout, sort, sizes).
ns._RFCombatVisEdge = function()
    local raid, party = ns._RFVisWanted()
    local raidEdge = raid ~= (framesVisible == true)
    local partyEdge = party ~= (ns._partyFramesVisible == true)
    if not raidEdge and not partyEdge then return end
    ns._rosterDirtyInCombat = true
    if raidEdge then
        SetFramesVisible(raid)
        ns._raidFramesVisible = raid
        if not raid then
            ns._RFForgetOccupants(allButtons)
            wipe(unitToButton)
        end
    end
    if partyEdge then
        ns._partyFramesVisible = party
        if not party then
            ns._RFForgetOccupants(ns._partyAllButtons)
            wipe(ns._partyUnitToButton)
        end
        ns.RF_KitPortraitEvents(party)
    end
    if raid or party then
        if IsInGroup() then
            StartRangeTicker()
            StartGhostTicker()
        end
    else
        StopRangeTicker()
        StopGhostTicker()
    end
    if ns.UpdatePowerEventRegistration then ns.UpdatePowerEventRegistration() end
    if ns._NotifyTrackerProviders then ns._NotifyTrackerProviders() end
end

-- Reload party frames: apply party-specific sizing then shared rendering.
-- Uses ns._partyProxy for all reads so party overrides take effect.
-- Anchor closures (captured db.profile at StyleButton time) need a temp-swap:
-- we write party_ values onto db.profile, call the closures, then restore.
ns.ReloadPartyFrames = function(skipButtons)
    if not ns._partyHeader then return end
    -- Re-evaluate UNIT_FLAGS registration before the temp-swap below (which
    -- overwrites db.profile), so a section sync/unsync that flips the party's
    -- effective combat-icon state turns the party trackers on/off in step.
    if ns.UpdateCombatEventRegistration then ns.UpdateCombatEventRegistration() end
    local p = ns._partyProxy  -- reads party_ keys with fallthrough
    local raw = db.profile
    -- Scaled reads for everything in INDICATOR_SCALE_KEYS (role/leader/marker
    -- icons, aura icon sizes, text sizes): mirrors the raid loop, which reads
    -- through ns._scaledProfile. Non-scale keys pass through unchanged.
    local pp = ns._scaledPartyProxy

    -- Recompute the party indicator/aura scale (Auto Resize) up front; the
    -- _UpdateAllPartyButtons() call at the end re-renders indicators with it.
    if ns._UpdatePartyIndicatorScale then ns._UpdatePartyIndicatorScale() end

    -- Temp-swap: write party overrides onto db.profile so anchor closures
    -- (which captured db.profile) read party values. Only for keys whose
    -- section is custom (unsynced). `swapped` records WHICH keys were swapped:
    -- a key whose raid value is nil (no default, never set on raid) stores
    -- nothing in `saved`, so restoring from `saved` alone would skip it and
    -- leave the party value on the shared raid key permanently.
    local saved, swapped = {}, {}
    local pxSib = ns._PARTY_PX_SIBLING
    for key, section in pairs(ns._PARTY_KEY_SECTION) do
        if ns._IsPartySectionCustom(section) then
            local pv = rawget(raw, "party_" .. key)
            -- An exact-size companion swaps whenever its sibling does (its party
            -- value may be nil): recorded in `swapped` so the restore writes it back.
            local sib = pxSib[key]
            if pv ~= nil or (sib and rawget(raw, "party_" .. sib) ~= nil) then
                swapped[#swapped + 1] = key
                saved[key] = raw[key]
                raw[key] = pv
            end
        end
    end

    -- Now db.profile has party values in place. Read from it directly for
    -- sizing (which also needs party width/height overrides).
    local pw, ph, _, pres = ns.RF_PartyDims(raw)
    local bw, bh = PixelSnap(pw), PixelSnap(ph)
    -- The bars' width (an attached portrait takes its share of the box).
    local barW = bw - ((pres and pres > 0) and PixelSnap(pres) or 0)
    local powerH = IsPowerBarEnabled(raw) and PixelSnap(raw.powerHeight or 4) or 0
    local healthH = PixelSnap(bh - powerH)
    local texPath = ResolveHealthTexture()

    for _, btn in ipairs(skipButtons and ns._emptyList or ns._partyAllButtons) do
        local d = GetFFD(btn)
        if not d.styled then
            -- _isParty BEFORE StyleButton: the container setup inside it
            -- resolves the style key and settings proxy from this flag, and
            -- the dispel slots BIND that key permanently. Styling first
            -- registered party dispel slots under the RAID key -- party
            -- dispel mode/icons/colors never applied (8.8.3 field reports).
            d._isParty = true
            ns._StyleButtonSecure(btn)
            StyleButton(btn)
        end

        -- Window/initialConfigFunction own sizes in combat (see raid loop).
        if not InCombatLockdown() then
            btn:SetSize(bw, bh)
        end

        -- Party portrait (EUI_RaidFrames_Portrait.lua; the kit keeps its own):
        -- ahead of the bar layout below, which hangs the bars off its area.
        if not d.kit then
            local pu = btn:GetAttribute("unit")
            ns.RF_PtApply(btn, d, pp, bw, bh, pu and UnitExists(pu) and pu or nil)
        end

        -- Health bar height/anchor + Top Name Bar (reads party-resolved `raw`).
        -- The Party Frames kit owns its bar rects (its pass runs below, after
        -- the texture swaps, so its masks seat on the new fills).
        if not d.kit then
            LayoutTopNameBar(raw, bh, powerH, d.health, d.topNameBar, d.topNameBarBg, d.topNameBarText, d.power)
        end
        if d.health then
            d.health:SetStatusBarTexture(texPath)
            d.health:GetStatusBarTexture():SetHorizTile(false)
            if d.ReanchorAbsorbToFill then d.ReanchorAbsorbToFill() end
        end

        -- Background: through its stamped owner (dark-mode aware), AFTER the
        -- fill texture swap (see the raid loop).
        if d.bg then
            d._bgSt, d._bgA = nil, nil
            local u = btn:GetAttribute("unit")
            if u and UnitExists(u) then ns._ApplyHealthBg(d, d.health, raw, u) end
        end

        -- Power bar (always hide here; UpdateButton handles per-role show). This is a
        -- second writer of health height alongside UpdateButton's own cached transition
        -- (LayoutTopNameBar above sized health assuming power reserved), so drop the
        -- cache or UpdateAllButtons below sees applied == computed and never corrects it.
        if d.kit then
            -- Party Frames kit: the mana bar always shows in the art's track
            -- (no role gate, no height); then the kit pass itself.
            if d.power then
                d.power:SetStatusBarTexture(texPath)
                d.power:GetStatusBarTexture():SetHorizTile(false)
            end
            local u = btn:GetAttribute("unit")
            ns.RF_ApplyPartyKit(btn, d, pp, u and UnitExists(u) and u or nil)
        else
            d._appliedHidePower = nil
            if d.power then
                d.power:Hide()
                if powerH > 0 then
                    d.power:SetHeight(powerH)
                    d.power:SetStatusBarTexture(texPath)
                    d.power:GetStatusBarTexture():SetHorizTile(false)
                end
            end
        end
        if d.powerBg then
            d.powerBg:SetColorTexture((raw.powerBgColor or {}).r or 0, (raw.powerBgColor or {}).g or 0, (raw.powerBgColor or {}).b or 0, (raw.powerBgDarkness or 70) / 100)
            d._pwBgTintType = nil
        end
        if d.UpdatePowerBorder then d.UpdatePowerBorder() end

        -- Name text
        if d.nameText then
            ApplyFont(d.nameText, pp.nameSize or 10)
            if d.AnchorNameText then d.AnchorNameText() end
            -- Override width constraint for party button dimensions (the
            -- kit's name width is its closure's own).
            if not d.kit then d.nameText:SetWidth(barW * ns.RF_NAME_WIDTH_FRACTION) end
        end

        -- Health text
        if d.healthText then
            ApplyFont(d.healthText, pp.healthTextSize or 9)
            if d.AnchorHealthText then d.AnchorHealthText() end
        end

        -- Power text: hidden with the bar above (not under the kit, whose mana bar stays shown)
        -- until _UpdateAllPartyButtons below shows it again, and restyled.
        if d.powerText then
            if not d.kit then d.powerText:Hide(); d._pwtMode = nil end
            ApplyFont(d.powerText, pp.powerTextSize or 8)
            ns._RFAnchorPowerText(d)
        end

        -- Level text: restyled; _UpdateAllPartyButtons below shows or hides it by position.
        if d.levelText then
            ApplyFont(d.levelText, pp.levelTextSize or 10)
            ns._RFAnchorLevelText(d)
        end

        -- Heal absorb text
        if d.healAbsorbText then
            ApplyFont(d.healAbsorbText, pp.healAbsorbTextSize or 9)
            if d.AnchorHealAbsorbText then d.AnchorHealAbsorbText() end
        end

        -- Status text
        if d.statusText then
            local stc = raw.statusTextColor or { r = 1, g = 1, b = 1 }
            ApplyFont(d.statusText, pp.statusTextSize or 14)
            d.statusText:SetTextColor(stc.r, stc.g, stc.b)
            if d.AnchorStatusText then d.AnchorStatusText() end
        end

        -- Role icon
        if d.roleIcon then
            local riSz = PixelSnap(pp.roleIconSize or 14)
            d.roleIcon:SetSize(riSz, riSz)
            if d.AnchorRoleIcon then d.AnchorRoleIcon() end
        end

        -- Leader icon
        if d.leaderIcon then
            local liSz = PixelSnap(pp.leaderIconSize or 14)
            d.leaderIcon:SetSize(liSz, liSz)
            if d.kitG then
                ns.RF_KitLeader(d, pp)
            else
                d.leaderIcon:ClearAllPoints()
                local liPos = (raw.leaderIconPosition or "top"):upper()
                d.leaderIcon:SetPoint(liPos, ns.RF_AnchorHost(d.health, pp), liPos, pp.leaderIconOffsetX or 0, pp.leaderIconOffsetY or 0)
            end
            -- Re-assert the host's strata/level above the border
            if d.leaderHost then ns.ApplyLeaderStrata(d.leaderHost) end
        end

        -- Raid marker
        if d.raidMarker then
            local rmSz = PixelSnap(pp.raidMarkerSize or 16)
            d.raidMarker:SetSize(rmSz, rmSz)
            if d.AnchorRaidMarker then d.AnchorRaidMarker() end
        end

        -- Ready check / summon
        if d.readyCheck then
            local rcSz = PixelSnap(pp.readyCheckSize or 20)
            d.readyCheck:SetSize(rcSz, rcSz)
            if d.AnchorReadyCheck then d.AnchorReadyCheck() end
        end

        -- Combat icon
        if d.combatIcon then
            local cciSz = PixelSnap(pp.combatIndicatorSize or 16)
            d.combatIcon:SetSize(cciSz, cciSz)
            if d.AnchorCombatIcon then d.AnchorCombatIcon() end
        end

        -- Ping marker
        if d.pingFrame then ns._RFAnchorPing(d) end
        if ns.RF_FvMissingAnchor then ns.RF_FvMissingAnchor(btn, d) end

        -- Border
        if d.UpdateBorder then d.UpdateBorder() end
    end

    -- Restore db.profile to raid values (via `swapped`, so a nil raid value
    -- is written back as nil rather than skipped)
    for _, key in ipairs(swapped) do
        raw[key] = saved[key]
    end

    -- Re-layout header
    ns._LayoutPartyFrames()
    ns._RebuildPartyUnitMap()
    -- Re-sync UNIT_POWER_UPDATE registration: a Power Bar section sync/unsync
    -- (or a party-side role-flag edit) changes the party's effective power
    -- gating, same reasoning as UpdateCombatEventRegistration above. Must run
    -- after the temp-swap restore so raid reads see raid values.
    if ns.UpdatePowerEventRegistration then ns.UpdatePowerEventRegistration() end
    ns._UpdateAllPartyButtons()

    -- Aura containers read the party class through its scaled proxy; the
    -- fingerprint guards make this near-free when nothing party-side changed.
    if ns.RFC_ReloadAll then ns.RFC_ReloadAll() end
    -- Party Frames kit: an attached Friendly Boss group clears the kit's
    -- outside auras, which these settings move (out of combat only).
    if ns.RF_PartyKit() and ns.FB_ReAnchor and not InCombatLockdown() then ns.FB_ReAnchor() end
    -- Portrait events follow the portrait settings (a no-op when unchanged).
    ns.RF_KitPortraitEvents(ns._partyFramesVisible)
    -- Pets and target frames beside the party frames are styled from the party settings.
    if not skipButtons then
        ns.PF_PartyRestyle()
        ns._PT_Restyle()
    end
end

local function RegisterWithUnlockMode()
    if not (EllesmereUI and EllesmereUI.RegisterUnlockElements) then return end
    if not containerFrame then return end

    -- Snap saved positions to the physical pixel grid using each container's own
    -- effective scale, via the REAL PP (EllesmereUI.PP) -- the file-local PP is
    -- PanelPP, which has no .Snap (`PP.Snap or floor` would fall through to plain
    -- integer rounding, not physical pixels). Matches the SnapForES pattern every
    -- other unlock element uses (and RF's own PixelSnap), keeping the container crisp.
    local realPP = EllesmereUI and EllesmereUI.PP
    local function snap(frame, v)
        if realPP and realPP.SnapForES and frame then
            return realPP.SnapForES(v, frame:GetEffectiveScale())
        end
        return floor(v + 0.5)
    end

    EllesmereUI:RegisterUnlockElements({
        EllesmereUI.MakeUnlockElement({
            key   = "RF_RaidFrames",
            label = "Raid Frames",
            group = "Raid Frames",
            order = 500,
            noResize = true,
            -- RF positions its own container via _ApplyTierOffset (base 20-man top-left
            -- + per-tier offset, tier-footprint-INDEPENDENT), re-run on init/PEW/roster+
            -- tier changes/combat end. The centralized ApplySavedPositions init loop
            -- re-anchors at unlockPos.point using the CURRENT (per-tier) container size,
            -- which diverges from that scheme for every non-20 size and clobbers the
            -- correct position ~0.6s after login. noInitHook keeps that loop off the
            -- container so _ApplyTierOffset stays sole authority (mover/save/anchors unaffected).
            noInitHook = true,

            getFrame = function() return containerFrame end,
            getSize  = function()
                return containerFrame:GetWidth(), containerFrame:GetHeight()
            end,

            savePos = function(_, point, relPoint, x, y, srcPoint, srcRelPoint)
                -- srcPoint/srcRelPoint: the PRE-conversion anchor the unlock framework
                -- received. Anything other than CENTER/CENTER means the CENTER coords were
                -- measured from the container's LIVE (ACTIVE-tier) bounds and must be
                -- rebased to the BASE footprint's equivalent center (the convention every
                -- apply reads), or a mover drag during a non-base tier lands off by a
                -- constant offset on the next _ApplyTierOffset pass. CENTER/CENTER or
                -- absent (revert/nudge/typed-edit) means already stored-convention; rebasing again would corrupt it.
                if srcPoint and not (srcPoint == "CENTER" and (srcRelPoint or "CENTER") == "CENTER")
                    and ns._RFRebaseSavedCenter then
                    x, y = ns._RFRebaseSavedCenter(x, y)
                end
                db.profile.unlockPos = { point = point, relPoint = relPoint, x = snap(containerFrame, x), y = snap(containerFrame, y) }
            end,
            loadPos = function()
                return db.profile.unlockPos
            end,
            clearPos = function()
                db.profile.unlockPos = nil
            end,
            applyPos = function()
                -- Delegate to the tier-aware authority (base top-left + per-tier
                -- offset) so any framework apply matches _ApplyTierOffset instead
                -- of the old re-anchor-at-unlockPos.point scheme, which used the
                -- current tier's container size and mispositioned non-20 sizes.
                if ns._ApplyTierOffset then ns._ApplyTierOffset() end
            end,
        }),
        EllesmereUI.MakeUnlockElement({
            key   = "RF_PartyFrames",
            label = "Party Frames",
            group = "Raid Frames",
            order = 501,
            noResize = true,

            getFrame = function() return ns._partyContainerFrame end,
            getSize  = function()
                return ns._partyContainerFrame:GetWidth(), ns._partyContainerFrame:GetHeight()
            end,

            savePos = function(_, point, relPoint, x, y)
                db.profile.partyUnlockPos = { point = point, relPoint = relPoint, x = snap(ns._partyContainerFrame, x), y = snap(ns._partyContainerFrame, y) }
            end,
            loadPos = function()
                return db.profile.partyUnlockPos
            end,
            clearPos = function()
                db.profile.partyUnlockPos = nil
            end,
            applyPos = function()
                -- Element-anchored: the anchor system owns the position. Only
                -- apply the saved pos as a bootstrap while the frame has no
                -- resolved geometry yet (anchor pass corrects it after).
                if EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored("RF_PartyFrames")
                   and ns._partyContainerFrame and ns._partyContainerFrame:GetLeft() then
                    return
                end
                local pos = db.profile.partyUnlockPos
                if pos and ns._partyContainerFrame then
                    ns._partyContainerFrame:ClearAllPoints()
                    ns._partyContainerFrame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
                end
            end,
        }),
        EllesmereUI.MakeUnlockElement({
            key   = "RF_HealerMana",
            label = "Healer Mana Display",
            group = "Raid Frames",
            order = 502,
            noResize = true,
            -- Disabled feature = no mover. Gates on the SETTING (mode none),
            -- not on the group-type activity gate: an enabled display should
            -- stay positionable while solo. The options mode setter
            -- re-registers via ns._RFRegisterUnlock so an open unlock session
            -- gains or loses the mover live in both directions.
            isHidden = function()
                local hm = ns._HMSet and ns._HMSet()
                return not hm or (hm.mode or "none") == "none"
            end,
            getFrame = function()
                return ns._hmContainer or (ns._HMEnsureContainer and ns._HMEnsureContainer())
            end,
            getSize = function()
                local c = ns._hmContainer
                if c then return c:GetWidth(), c:GetHeight() end
                return 50, 25
            end,
            savePos = function(_, point, relPoint, x, y)
                local hm = ns._HMSet()
                hm.unlockPos = { point = point, relPoint = relPoint,
                    x = snap(ns._hmContainer, x), y = snap(ns._hmContainer, y) }
            end,
            loadPos = function()
                return ns._HMSet().unlockPos
            end,
            clearPos = function()
                ns._HMSet().unlockPos = nil
            end,
            applyPos = function()
                local c = ns._hmContainer
                local pos = ns._HMSet().unlockPos
                if c and pos and pos.point then
                    c:ClearAllPoints()
                    c:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
                end
            end,
        }),
    })
end
-- Options-side re-registration seam (the function above is a file-scope local
-- the options file cannot reach): setting changes that flip an element's
-- isHidden verdict re-register so an open unlock session updates live.
ns._RFRegisterUnlock = RegisterWithUnlockMode

I.RegisterWithUnlockMode = RegisterWithUnlockMode
I.broken = false
