if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_RaidFrames_PreviewParty.lua
--
--  The party preview, the restore of the real frames and the fade-out for
--  unlock mode.
--  Reads the earlier preview files through ns and ns._previewInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._previewInternals
-- EUI_RaidFrames_Preview.lua or an earlier preview file failed to load.
if not I or I.broken then return end
I.broken = true

local ipairs       = ipairs
local wipe         = wipe
local tinsert      = table.insert
local UnitClass             = UnitClass
local InCombatLockdown      = InCombatLockdown
local CreateFrame           = CreateFrame

local RF = ns._internals -- the table of the Raid Frames chain
local ApplyFont, LayoutGroups, PixelSnap = RF.ApplyFont, RF.LayoutGroups, RF.PixelSnap
local UpdateVisibility = ns.UpdateVisibility

local StopPvAuraTicker, CreatePreviewFrame = I.StopPvAuraTicker, I.CreatePreviewFrame
local ApplyPreviewData, previewHealthValues = I.ApplyPreviewData, I.previewHealthValues
local previewPowerValues, HidePreview = I.previewPowerValues, I.HidePreview

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of the table that holds its list, which hands the value to
-- every copy: db, PP and containerFrame are the Raid Frames chain's.
local db
RF.dbSetters[#RF.dbSetters + 1] = function(v) db = v end
local containerFrame
RF.containerFrameSetters[#RF.containerFrameSetters + 1] = function(v) containerFrame = v end
local previewActive = false
I.previewActiveSetters[#I.previewActiveSetters + 1] = function(v) previewActive = v end

-------------------------------------------------------------------------------
--  Party preview (5-player, 1 group)
--  Fully separate from raid preview -- shares CreatePreviewFrame and
--  ApplyPreviewData via temp-swap pattern but has its own frame pool,
--  health values, role assignments, layout, and overlay container.
-------------------------------------------------------------------------------
ns._partyPvFrames    = {}
ns._partyPvHV        = {}
ns._partyPvPV        = {}
ns._partyPvActive    = false
ns._partyPvInit      = false
ns.partyPvAbsorbValues     = {}
ns.partyPvHealAbsorbValues = {}
ns.partyPvHealPredValues   = {}
ns.partyPvReducedMaxHealth = {}
ns._partyPvRoles     = {}
ns._partyPvCT        = {}

local function BuildPartyPreviewRoles()
    for i = 1, 5 do ns._partyPvRoles[i] = nil end
    wipe(ns._partyPvCT)

    -- Effective role: the player's spec wins over a stale assigned role
    local playerRole = EllesmereUI.UnitEffectiveRole("player")
    if playerRole ~= "TANK" and playerRole ~= "HEALER" then
        playerRole = "DAMAGER"
    end

    -- Slot 1 = player
    ns._partyPvRoles[1] = playerRole
    local _, pct = UnitClass("player")
    ns._partyPvCT[1] = pct or "WARRIOR"
    ns._partyPvRoles._playerSlot = 1

    -- Fill remaining: 1 tank, 1 healer, 3 DPS total
    local needTank   = (playerRole ~= "TANK")   and 1 or 0
    local needHealer = (playerRole ~= "HEALER") and 1 or 0
    local tankIdx, healerIdx, dpsIdx = 1, 1, 1

    for i = 2, 5 do
        if needTank > 0 then
            ns._partyPvRoles[i] = "TANK"
            ns._partyPvCT[i] = ns._PV_TANK_CLASSES[tankIdx]
            tankIdx = (tankIdx % #ns._PV_TANK_CLASSES) + 1
            needTank = needTank - 1
        elseif needHealer > 0 then
            ns._partyPvRoles[i] = "HEALER"
            ns._partyPvCT[i] = ns._PV_HEALER_CLASSES[healerIdx]
            healerIdx = (healerIdx % #ns._PV_HEALER_CLASSES) + 1
            needHealer = needHealer - 1
        else
            ns._partyPvRoles[i] = "DAMAGER"
            ns._partyPvCT[i] = ns._PV_DPS_CLASSES[dpsIdx]
            dpsIdx = (dpsIdx % #ns._PV_DPS_CLASSES) + 1
        end
    end

    -- Sort by role order + self-first (reads party-specific settings)
    local sortMode = db.profile.partySortMode or db.profile.sortMode or "INDEX"
    local showSelfFirst = db.profile.partyShowSelfFirst
    if showSelfFirst == nil then showSelfFirst = db.profile.showSelfFirst end
    local selfLast = db.profile.partySelfLast
    if selfLast == nil then selfLast = db.profile.showSelfLast end
    if selfLast then showSelfFirst = true end  -- self ordering active either way
    local prioritizeClass = db.profile.partyPrioritizeClass
    if sortMode == "ROLE" or showSelfFirst or prioritizeClass then
        local group = {}
        for u = 1, 5 do
            group[u] = {
                role = ns._partyPvRoles[u],
                classToken = ns._partyPvCT[u],
                isPlayer = (u == 1),
                idx = u,
            }
        end
        if sortMode == "ROLE" or prioritizeClass then
            -- Mirror the live header order: role (optional primary) -> class (when
            -- Prioritize Class is on) -> original slot. Comparator matches
            -- _BuildPartyClassNameList so the preview replicates the real frames.
            local sortByRole = (sortMode == "ROLE")
            local roleOrder = db.profile.partyRoleOrder or db.profile.roleOrder or { "TANK", "HEALER", "DAMAGER" }
            local rolePri = {}
            for i, r in ipairs(roleOrder) do rolePri[r] = i end
            local classPri
            if prioritizeClass then
                classPri = {}
                local co = db.profile.partyClassOrder or ns._GetDefaultClassOrder()
                for i, c in ipairs(co) do classPri[c] = i end
            end
            table.sort(group, function(a, b)
                if sortByRole then
                    local ra, rb = rolePri[a.role] or 99, rolePri[b.role] or 99
                    if ra ~= rb then return ra < rb end
                end
                if classPri then
                    local ca, cb = classPri[a.classToken] or 99, classPri[b.classToken] or 99
                    if ca ~= cb then return ca < cb end
                end
                return a.idx < b.idx
            end)
        end
        if showSelfFirst then
            local playerPos
            for i, entry in ipairs(group) do
                if entry.isPlayer then playerPos = i; break end
            end
            if playerPos then
                if selfLast and playerPos < #group then
                    local playerEntry = table.remove(group, playerPos)
                    group[#group + 1] = playerEntry
                elseif not selfLast and playerPos > 1 then
                    local playerEntry = table.remove(group, playerPos)
                    tinsert(group, 1, playerEntry)
                end
            end
        end
        for u = 1, 5 do
            ns._partyPvRoles[u] = group[u].role
            ns._partyPvCT[u] = group[u].classToken
            if group[u].isPlayer then ns._partyPvRoles._playerSlot = u end
        end
    end

    -- Random picks (only once per session)
    if not ns._partyPvRoles._randomized then
        ns._partyPvRoles._randomized = true
        local tanks = {}
        for i = 1, 5 do
            if ns._partyPvRoles[i] == "TANK" then tanks[#tanks + 1] = i end
        end
        ns._partyPvRoles._threatIndex = tanks[math.random(#tanks)] or 1
        -- Marker on the player (slot 1) so each of the four status indicators
        -- gets its own non-player frame (clean 1-per-frame showcase, no overlap).
        ns._partyPvRoles._markerSlot1 = 1
        ns._partyPvRoles._markerSlot2 = nil  -- only 1 marker in 5-man
        local dispelTypes = { "Magic", "Curse", "Disease", "Poison", "" }
        ns._partyPvRoles._dispelMap = {}
        for i, dt in ipairs(dispelTypes) do ns._partyPvRoles._dispelMap[i] = dt end
        -- Status showcase: 1 dead, 1 offline, 1 AFK, 1 summon-accepted, one each on
        -- the four non-player slots (2-5). No ready-check ticks. (Incoming-rez isn't
        -- previewed here: a 5-man has only four non-player slots and they're all
        -- taken, so there's no room for a separate rez corpse the way the raid
        -- preview has one. The live indicator still shows on party frames.)
        local statusSlots = { 2, 3, 4, 5 }
        for i = #statusSlots, 2, -1 do
            local j = math.random(i)
            statusSlots[i], statusSlots[j] = statusSlots[j], statusSlots[i]
        end
        ns._partyPvRoles._deadSlot    = statusSlots[1]
        ns._partyPvRoles._offlineSlot = statusSlots[2]
        ns._partyPvRoles._afkSlot     = statusSlots[3]
        ns._partyPvRoles._readyCheck  = { [statusSlots[4]] = "summon_accepted" }
    end
end

local function InitPartyPreviewHealthValues()
    if ns._partyPvInit then return end
    ns._partyPvInit = true
    for i = 1, 5 do
        ns._partyPvHV[i] = 40 + math.random(60)
        ns._partyPvPV[i] = 50 + math.random(50)
        ns.partyPvAbsorbValues[i] = 0
        ns.partyPvHealAbsorbValues[i] = 0
    end
    -- 1-2 shields
    local slot1 = math.random(5)
    ns.partyPvAbsorbValues[slot1] = 5 + math.random(25)
    if math.random() > 0.5 then
        local slot2 = math.random(5)
        if ns.partyPvAbsorbValues[slot2] == 0 then
            ns.partyPvAbsorbValues[slot2] = 3 + math.random(15)
        end
    end
    -- 1 heal absorb
    local haSlot = math.random(2, 5)
    ns.partyPvHealAbsorbValues[haSlot] = 20 + math.random(20)
    -- 1 heal prediction
    ns.partyPvHealPredValues = {}
    for i = 1, 5 do ns.partyPvHealPredValues[i] = 0 end
    for i = 1, 5 do
        if ns._partyPvHV[i] < 90 then
            ns.partyPvHealPredValues[i] = 10 + math.random(20)
            break
        end
    end
    -- 1 reduced max health
    ns.partyPvReducedMaxHealth = {}
    for i = 1, 5 do ns.partyPvReducedMaxHealth[i] = 0 end
    local rmhSlot = math.random(2, 5)
    ns.partyPvReducedMaxHealth[rmhSlot] = 0.10 + math.random() * 0.15
end

local function GetOrCreatePartyPvFrame(index)
    if ns._partyPvFrames[index] then return ns._partyPvFrames[index] end
    local f = CreatePreviewFrame(index, true)
    f._isParty = true
    -- Reparent from raid preview container to party overlay container
    if ns._partyOC then f:SetParent(ns._partyOC) end
    ns._partyPvFrames[index] = f
    return f
end

-- Apply preview data with party-specific width/height override
-- The raid values ApplyPartyPreviewData overwrites for one call, kept to put back.
local savedHealth, savedPower = {}, {}

local function ApplyPartyPreviewData(f, index)
    local s = db.profile
    -- Use party proxy so ApplyPreviewData reads party-specific settings
    ns._previewSettingsOverride = ns._scaledPartyProxy

    -- Sandwich values sourced through the effective overlay (panel-closed
    -- values while a view swap is active); s stays live db.profile so the
    -- mutation+restore semantics are unchanged.
    local eff = ns._pvOverlayProxy or db.profile
    local origW, origH = s.frameWidth, s.frameHeight
    -- The bars' width (a party portrait widens the frame after the restore).
    local ew, eh, _, eres = ns.RF_PartyDims(eff)
    s.frameWidth, s.frameHeight = ew - (eres or 0), eh

    -- Temporarily swap preview value tables so ApplyPreviewData reads party data
    local origAbsorb = ns.previewAbsorbValues
    local origHA     = ns.previewHealAbsorbValues
    local origHP     = ns.previewHealPredValues
    local origRMH    = ns.previewReducedMaxHealth

    for i = 1, 5 do
        savedHealth[i], savedPower[i] = previewHealthValues[i], previewPowerValues[i]
        previewHealthValues[i] = ns._partyPvHV[i]
        previewPowerValues[i]  = ns._partyPvPV[i]
    end
    ns.previewAbsorbValues     = ns.partyPvAbsorbValues
    ns.previewHealAbsorbValues = ns.partyPvHealAbsorbValues
    ns.previewHealPredValues   = ns.partyPvHealPredValues
    ns.previewReducedMaxHealth = ns.partyPvReducedMaxHealth

    ApplyPreviewData(f, index, ns._partyPvRoles, ns._partyPvCT)

    -- Re-apply BM indicators with the party proxy so Auto Resize scales the
    -- preview indicators/auras live. CreatePreviewFrame applies them only once
    -- (at creation, with the raid proxy), so without this the party preview
    -- would never reflect the party scale. Index 1 matches the creation call.
    if f._bmIconPool and ns.BM_ApplyPreviewIndicators then
        ns.BM_ApplyPreviewIndicators(f, 1, ns._scaledPartyProxy)
    end

    -- Restore everything
    ns._previewSettingsOverride = nil
    s.frameWidth  = origW
    s.frameHeight = origH
    for i = 1, 5 do
        previewHealthValues[i] = savedHealth[i]
        previewPowerValues[i]  = savedPower[i]
    end
    ns.previewAbsorbValues     = origAbsorb
    ns.previewHealAbsorbValues = origHA
    ns.previewHealPredValues   = origHP
    ns.previewReducedMaxHealth = origRMH

    -- Party Frames kit: bar rects, art, spots and a mock portrait, after the
    -- restore above (nothing here may run inside that swap window).
    if f.kit then
        -- Forced: the refresh above re-laid the bars out at the box's edges.
        ns.RF_ApplyPartyKit(f, f, ns._scaledPartyProxy, nil, true)
        local roles = ns._partyPvRoles
        -- (Greyed only while the preview actually shows that slot offline.)
        ns.RF_KitPreviewPortrait(f, ns._partyPvCT[index],
            index == (roles._playerSlot or 1),
            ns._indicatorsVisible ~= false and index == roles._offlineSlot)
    elseif ns.RF_PtPreview then
        -- Party portrait: the frame takes the box width, the bars move beside
        -- the portrait, then a mock paint (same slots as the kit's).
        local roles = ns._partyPvRoles
        ns.RF_PtPreview(f, ns._scaledPartyProxy, ns._partyPvCT[index],
            index == (roles._playerSlot or 1),
            ns._indicatorsVisible ~= false and index == roles._offlineSlot)
    end
end

-- Party overlay container (separate from raid overlay). Position is hardcoded
-- (see RefreshPartyPreview) -- not draggable, nothing saved to the profile.
ns._partyOC = nil

local function GetOrCreatePartyOverlayContainer()
    if ns._partyOC then return ns._partyOC end

    local oc = CreateFrame("Frame", nil, UIParent)
    oc:SetFrameStrata("FULLSCREEN_DIALOG")
    oc:SetFrameLevel(10)
    oc:SetClampedToScreen(true)
    oc:Hide()

    local bg = oc:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.9)
    oc._bg = bg

    -- Centered title at the top of the preview. Font/text/color/visibility are
    -- (re)applied each refresh in RefreshPartyPreview after ApplyFont (a
    -- fontstring with no font set errors on SetText).
    local title = oc:CreateFontString(nil, "OVERLAY")
    title:SetPoint("TOP", oc, "TOP", 0, -7)
    oc._title = title

    ns._partyOC = oc
    return oc
end

local function RefreshPartyPreview()
    if not ns._partyPvActive then return end
    if ns._RebuildPvOverlay then ns._RebuildPvOverlay() end
    -- Recompute party indicator/aura scale before applying preview data so the
    -- party preview reflects Auto Resize live (preview reads _scaledPartyProxy).
    if ns._UpdatePartyIndicatorScale then ns._UpdatePartyIndicatorScale() end
    local s = ns._pvOverlayProxy or db.profile
    local pw, ph, pcs = ns.RF_PartyDims(s)
    local w, h, spacing = PixelSnap(pw), PixelSnap(ph), PixelSnap(pcs)
    -- Party target frames along the stack open the frames' pitch, as on the real frames.
    local pitch = spacing + ns.PT_AlongPitch(s, s.partyShowTargets == true)
    local mode = db.profile.previewMode or "overlay"

    BuildPartyPreviewRoles()

    -- "Hide Self": mirror the real party frames (showPlayer=false) by hiding the
    -- player's preview frame and reflowing the remaining members to fill the gap.
    -- The player's slot is whatever BuildPartyPreviewRoles resolved it to after
    -- Sort By + Self First/Last (NOT assumed to be slot 1).
    local hideSelf = s.partyHideSelf
    local playerSlot = ns._partyPvRoles._playerSlot or 1
    local shownCount = hideSelf and 4 or 5

    local isOverlay = (mode == "overlay")
    local anchorPad = isOverlay and 10 or 0
    local topExtra = isOverlay and 25 or 0   -- top space for the centered "Preview" title
    local unitGrowth = ns._PartyGrowth(s)
    local isVert = (unitGrowth == "DOWN" or unitGrowth == "UP")
    local totalW, totalH
    if isVert then
        totalW = w
        totalH = h * shownCount + pitch * (shownCount - 1)
    else
        totalW = w * shownCount + pitch * (shownCount - 1)
        totalH = h
    end

    -- Pets (Show Pets on the Party tab) beside the party frames, or beside each frame (Beside
    -- Owner), and the party target frames beside each frame (after Beside Owner pets on their
    -- side; pets beside the party frames clear them); the overlay grows to hold them.
    local ptSpec = ns.PT_PreviewSpec(s, w, h)
    local petSpec = isOverlay and ns.PF_PreviewSpec(true, s, w, h, spacing, totalW, totalH, ptSpec)
    if ptSpec and petSpec and petSpec.owner then ptSpec = ns.PT_PreviewSpec(s, w, h, petSpec) end
    local padL, padT, padR, padB = 0, 0, 0, 0
    if petSpec and petSpec.owner then
        padL, padT, padR, padB = petSpec.padL, petSpec.padT, petSpec.padR, petSpec.padB
    elseif petSpec then
        padL = math.max(0, -petSpec.ox)
        padT = math.max(0, petSpec.oy)
        padR = math.max(0, petSpec.ox + petSpec.bw - totalW)
        padB = math.max(0, petSpec.bh - petSpec.oy - totalH)
    end
    if isOverlay and ptSpec then
        padL, padT = math.max(padL, ptSpec.padL), math.max(padT, ptSpec.padT)
        padR, padB = math.max(padR, ptSpec.padR), math.max(padB, ptSpec.padB)
    end
    -- Your own frame's target shows only with Include Own Target.
    local ptSkip = (not s.partyTargetIncludeSelf) and playerSlot or nil

    -- Determine parent frame: overlay container for overlay, UIParent for real
    local parentFrame
    if isOverlay then
        GetOrCreatePartyOverlayContainer()
        parentFrame = ns._partyOC
    else
        parentFrame = UIParent
        if ns._partyOC then ns._partyOC:Hide() end
    end

    local slot = 0  -- running layout position; skips the hidden player frame
    local lastF     -- the last frame along the growth
    for i = 1, 5 do
        local f = GetOrCreatePartyPvFrame(i)
        if hideSelf and i == playerSlot then
            f:Hide()
        else
            lastF = f
            if f:GetParent() ~= parentFrame then f:SetParent(parentFrame) end
            f:SetFrameStrata(isOverlay and "FULLSCREEN_DIALOG" or "HIGH")
            f:ClearAllPoints()
            if isVert then
                local yOff = slot * (h + pitch)
                if unitGrowth == "DOWN" then
                    f:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", anchorPad + padL, -anchorPad - topExtra - padT - yOff)
                else
                    -- UP fills the same box from the bottom upward (positive
                    -- offsets); the container's extra top height creates the
                    -- title gap, so no per-frame correction is needed here.
                    f:SetPoint("BOTTOMLEFT", parentFrame, "BOTTOMLEFT", anchorPad + padL, anchorPad + padB + yOff)
                end
            else
                local xOff = slot * (w + pitch)
                if unitGrowth == "LEFT" then xOff = -xOff end
                if unitGrowth == "RIGHT" then
                    f:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", anchorPad + padL + xOff, -anchorPad - topExtra - padT)
                else
                    f:SetPoint("TOPRIGHT", parentFrame, "TOPRIGHT", -anchorPad - padR + xOff, -anchorPad - topExtra - padT)
                end
            end
            ApplyPartyPreviewData(f, i)
            f:Show()
            slot = slot + 1
        end
    end

    -- Size and position overlay container
    if isOverlay and ns._partyOC then
        ns._partyOC:SetSize(totalW + padL + padR + anchorPad * 2,
            totalH + padT + padB + anchorPad * 2 + topExtra)
        ns._partyOC:SetFrameStrata("FULLSCREEN_DIALOG")
        ns._partyOC:SetFrameLevel(10)
        if ns._partyOC._title then
            ApplyFont(ns._partyOC._title, 13)
            ns._partyOC._title:SetText(EllesmereUI.L("Preview"))
            ns._partyOC._title:SetTextColor(1, 1, 1, 0.9)
            ns._partyOC._title:Show()
        end
        -- Hardcoded default position (not draggable, not saved): docked to the
        -- left edge of the options panel, screen center as a fallback.
        ns._partyOC:ClearAllPoints()
        local sf = EllesmereUI._scrollFrame
        if sf then
            ns._partyOC:SetPoint("BOTTOMRIGHT", sf, "BOTTOMLEFT", 0, 0)
        else
            ns._partyOC:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
        ns._partyOC:Show()
        -- Styled from the party settings, as the preview's own frames are.
        if petSpec and petSpec.owner then
            ns.PF_ShowOwnerPreview(petSpec, ns._scaledPartyProxy, ns._partyOC, lastF)
        elseif petSpec then
            ns.PF_ShowPreview(petSpec, ns._scaledPartyProxy, ns._partyOC, ns._partyOC,
                anchorPad + padL + petSpec.ox, -anchorPad - topExtra - padT + petSpec.oy)
        else
            ns.PF_HidePreview()
        end
        ns.PT_ShowPreview(ptSpec, s, ns._partyOC, ptSkip)
    end

    -- Real mode: anchor frames to the actual party container, mirroring the
    -- real layout's basePoint logic (_PositionPartySlots). Slot 0 sits at the
    -- container corner the growth direction moves AWAY from, so Flip Frame
    -- Growth keeps the stack bounded by the container instead of growing past
    -- it. A plain TOPLEFT anchor misaligned the flipped preview by a full
    -- stack height/width versus the edit-mode location.
    if mode == "real" and ns._partyContainerFrame then
        local pos = s.partyUnlockPos
        -- Editing an override with a custom unlock mode: anchor the preview at the
        -- LAYER's recorded party-container position (a lightweight proxy frame stands
        -- in for the real container, which sits at the REAL spec's position).
        local anchorTo = ns._partyContainerFrame
        local se = ns._PvSessionElem and ns._PvSessionElem("RF_PartyFrames")
        if se and se.point then
            local proxy = ns._pvSessionPartyAnchor
            if not proxy then
                proxy = CreateFrame("Frame", nil, UIParent)
                ns._pvSessionPartyAnchor = proxy
            end
            proxy:SetSize(ns._partyContainerFrame:GetSize())
            proxy:ClearAllPoints()
            proxy:SetPoint(se.point, UIParent, se.relPoint or se.point,
                PixelSnap(se.x or 0), PixelSnap(se.y or 0))
            anchorTo = proxy
            pos = pos or se
        end
        local cw, ch = anchorTo:GetSize()
        local realPets = ns.PF_PreviewSpec(true, s, w, h, spacing, cw, ch, ptSpec)
        if realPets and realPets.owner then
            ns.PF_ShowOwnerPreview(realPets, ns._scaledPartyProxy, UIParent, lastF)
        elseif realPets then
            ns.PF_ShowPreview(realPets, ns._scaledPartyProxy, UIParent, anchorTo, realPets.ox, realPets.oy)
        else
            ns.PF_HidePreview()
        end
        if ptSpec and realPets and realPets.owner then ptSpec = ns.PT_PreviewSpec(s, w, h, realPets) end
        ns.PT_ShowPreview(ptSpec, s, UIParent, ptSkip)
        if pos then
            local stepX, stepY = 0, 0
            local basePoint = "TOPLEFT"
            if unitGrowth == "RIGHT" then
                stepX = w + pitch
            elseif unitGrowth == "LEFT" then
                stepX = -(w + pitch); basePoint = "TOPRIGHT"
            elseif unitGrowth == "UP" then
                stepY = h + pitch; basePoint = "BOTTOMLEFT"
            else -- DOWN
                stepY = -(h + pitch)
            end
            -- Centered growth: mirror _PositionPartySlots, which shifts the stack by
            -- (5 - shown)/2 slots so the shown frames sit centered in the 5-slot
            -- container. The preview always shows a full party, so shown is 5, or 4
            -- with Hide Self (the real layout subtracts the hidden self the same way).
            local centerShift = 0
            if s.partyFlipGrowth == "centered" then
                centerShift = (5 - shownCount) / 2
            end
            local cShiftX = PixelSnap(stepX * centerShift)
            local cShiftY = PixelSnap(stepY * centerShift)
            local idx = 0  -- running position; skips the hidden player frame
            for i = 1, 5 do
                local f = ns._partyPvFrames[i]
                if f then
                    if hideSelf and i == playerSlot then
                        f:Hide()
                    else
                        f:ClearAllPoints()
                        f:SetPoint(basePoint, anchorTo, basePoint,
                            PixelSnap(stepX * idx) + cShiftX, PixelSnap(stepY * idx) + cShiftY)
                        idx = idx + 1
                    end
                end
            end
        end
    end

    ns.RF_PreviewCompact(ns._partyPvFrames, ns._scaledPartyProxy, true, unitGrowth)
end

local function ShowPartyPreview()
    -- See ShowPreview: never engage the preview (which reparents the real
    -- containers under a hidden frame) unless the options window is open and we
    -- are out of combat. Guards against deferred post-close ShowPartyPreview.
    if not ns._testMode and not (EllesmereUI:IsShown()) then return end
    if InCombatLockdown() then return end
    -- Kill any active size preview
    if ns._sizePreviewTier then
        ns._sizePreviewTier = nil
        if ns._HideSizePreview then ns._HideSizePreview() end
    end
    if ns._partyPvActive then
        RefreshPartyPreview()
        return
    end
    local mode = db.profile.previewMode or "overlay"
    if mode == "none" then return end

    ns._partyPvActive = true
    -- Hide the real containers via alpha (combat-reversible); see ShowPreview.
    -- Never reparent secure-header containers (the restore would be blocked in
    -- combat and strand the frames for the whole pull).
    ns._SetRealFramesPreviewHidden(true)
    if mode == "overlay" then
        GetOrCreatePartyOverlayContainer()
    end
    InitPartyPreviewHealthValues()
    BuildPartyPreviewRoles()
    RefreshPartyPreview()
end

-- skipRestore: leave the real frames parented to the hidden frame instead of
-- restoring them. Used on in-panel tab swaps where another preview shows on the
-- next frame -- restoring here would flash the real frames for one frame before
-- the deferred ShowPreview re-hides them. Panel close restores explicitly.
local function HidePartyPreview(skipRestore)
    if not ns._partyPvActive then return end
    ns.RF_PreviewCompact(nil, nil, true)
    -- Stop the aura ticker while still party-active so it clears the party aura
    -- icons (PvFrames resolves to the party set here), then deactivate.
    StopPvAuraTicker()
    ns._partyPvActive = false
    for i = 1, 5 do
        if ns._partyPvFrames[i] then ns._partyPvFrames[i]:Hide() end
    end
    if ns._partyOC then ns._partyOC:Hide() end
    ns.PF_HidePreview()
    ns.PT_HidePreview()
    if skipRestore then return end
    -- The containers were only alpha-hidden (never reparented or moved); restore
    -- is a combat-legal SetAlpha(1) plus dropping the mouse blockers. See
    -- HidePreview. No combat gate, no SetParent/SetPoint, no ns._restorePending.
    ns._SetRealFramesPreviewHidden(false)
    if not InCombatLockdown() then
        LayoutGroups()
        if ns._ApplyTierOffset then ns._ApplyTierOffset() end
    end
    UpdateVisibility()
    if ns._UpdatePartyVisibility then ns._UpdatePartyVisibility() end
end

ns.ShowPartyPreview = ShowPartyPreview
ns.HidePartyPreview = HidePartyPreview
ns.partyPvActive = function() return ns._partyPvActive end

-- Guaranteed restore invariant. Ensures both real containers are parented to UIParent
-- and their visibility recomputed whenever no preview should be active (e.g. the
-- options panel just closed). Heals the "frames stuck hidden under the preview parent"
-- case even when the preview flags were left false by a skip-restore tab swap or a
-- post-close deferred ShowPreview. Defers to PLAYER_REGEN_ENABLED in combat
-- (reparenting secure-header containers is a protected action).
function ns.EnsureRealFramesRestored()
    if not containerFrame then return end
    -- Tear down any genuinely-active preview FIRST. HidePreview/HidePartyPreview
    -- now restore container alpha and drop the mouse blockers via combat-legal
    -- ops only (SetAlpha on our containers; Hide/SetParent on our own non-secure
    -- preview frames), so they never defer anything.
    if previewActive then HidePreview() end
    if ns._partyPvActive then HidePartyPreview() end
    -- Hard guarantee: force both real containers fully opaque and drop any mouse
    -- blockers, unconditionally. SetAlpha is not protected, so this is valid in
    -- combat and heals the "left alpha-hidden with the flags already false" cases
    -- (skip-restore tab swap, combat-cancelled deferred Show). The containers are
    -- never reparented or moved anymore, so nothing protected needs deferral.
    ns._SetRealFramesPreviewHidden(false)
    -- The layout/visibility recompute below SetPoints/Shows secure headers, so
    -- out of combat only. The alpha restore above already makes the frames
    -- visible during combat.
    if InCombatLockdown() then return end
    UpdateVisibility()
    if ns._UpdatePartyVisibility then ns._UpdatePartyVisibility() end
end

-- Fade out overlay previews when entering unlock mode
do
    local FADE_DUR = 0.1
    local function FadeOutFrame(frame)
        if not frame or not frame:IsShown() then return end
        local startAlpha = frame:GetAlpha()
        local elapsed = 0
        frame:SetScript("OnUpdate", function(self, dt)
            elapsed = elapsed + dt
            if elapsed >= FADE_DUR then
                self:SetAlpha(0)
                self:Hide()
                self:SetScript("OnUpdate", nil)
                self:SetAlpha(startAlpha)
                return
            end
            self:SetAlpha(startAlpha * (1 - elapsed / FADE_DUR))
        end)
    end
    _G._ERF_UnlockModeOpen = function()
        FadeOutFrame(ns._overlayContainer)
        FadeOutFrame(ns._partyOC)
    end
end

I.broken = false
