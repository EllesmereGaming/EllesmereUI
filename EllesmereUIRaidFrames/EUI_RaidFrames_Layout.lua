if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_RaidFrames_Layout.lua
--
--  Header creation and LayoutGroups.
--  Reads the earlier Raid Frames files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- EllesmereUIRaidFrames.lua or an earlier Raid Frames file failed to load.
if not I or I.broken then return end
I.broken = true

local abs          = math.abs
local tostring     = tostring
local IsInRaid              = IsInRaid
local InCombatLockdown      = InCombatLockdown
local GetNumGroupMembers    = GetNumGroupMembers
local CreateFrame           = CreateFrame

local allButtons, ApplyFont, PixelSnap = I.allButtons, I.ApplyFont, I.PixelSnap
local separatedHdrs, ApplySortToHeaders = I.separatedHdrs, I.ApplySortToHeaders
local SetContainerFrame = I.SetContainerFrame

local db
I.dbSetters[#I.dbSetters + 1] = function(v) db = v end
local PP
I.PPSetters[#I.PPSetters + 1] = function(v) PP = v end
local containerFrame
I.containerFrameSetters[#I.containerFrameSetters + 1] = function(v) containerFrame = v end

-------------------------------------------------------------------------------
--  Header creation
-------------------------------------------------------------------------------
-- One SecureGroupHeader set per layout mode: 8 separated group headers, or a
-- single flat header for Merge Groups (only structure that can fill/sort across
-- group boundaries). Only the ACTIVE mode builds at login (full-set build/style
-- dominates login cost); the other materializes on the first mode flip via
-- ReloadFrames/_ERF_RefreshAll. Combat blocks secure creation -- a combat-time
-- flip flags the REGEN reload path to build there instead.
ns._BuildHeaderSet = function(merge)
    if not containerFrame then return end
    if merge and ns._flatHeader then return end
    if not merge and separatedHdrs[1] then return end
    if InCombatLockdown() then
        ns._sizeTierDirtyInCombat = true
        return
    end

    local s = db.profile

    -- Button dimensions passed to headers via attributes (pixel-snapped):
    -- active tier dims when a tier is live (late build inside a raid), else base.
    local bw = PixelSnap(ns._activeSizeW or s.frameWidth or 72)
    local bh = PixelSnap(ns._activeSizeH or s.frameHeight or 46)

    -- initialConfigFunction: runs in restricted env when header creates a button
    local initConfig = ([[
        self:SetWidth(%d)
        self:SetHeight(%d)
    ]]):format(bw, bh)

    -- Compute correct initial point/offset from saved growth direction. Self-heal
    -- a same-axis pair (see ns._RFEffectiveGrowth) before deriving anything from
    -- it -- this bootstrap runs from the raw profile, ahead of _LayoutGroupsImpl's
    -- own per-tier resolution and self-heal.
    local initUnitGrowth, initGroupGrowth = ns._RFEffectiveGrowth(
        s.unitGrowth or "DOWN", s.groupGrowth or "RIGHT", merge)
    local csInit = PixelSnap(s.cellSpacing or 2)
    local initPoint, initXOff, initYOff = ns._RFHeaderPoint(initUnitGrowth, csInit)

    -- A header makes children only while visible (IsVisible walks the parent
    -- chain): a set built with the container hidden (a Merge Groups flip while
    -- solo or in a party) shows the container around the pre-spawn below.
    local hid = not containerFrame:IsShown()
    if hid then containerFrame:Show() end

    if not merge then
        -----------------------------------------------------------
        --  8 separated group headers (one per raid group)
        -----------------------------------------------------------
        for group = 1, 8 do
            local hdr = CreateFrame("Frame", "ERFGroupHeader" .. group, containerFrame, "SecureGroupHeaderTemplate")
            -- the header births an AuraContainer per child SECURE-SIDE -- the only
            -- combat-legal container source (covers in-combat /reload and mid-combat
            -- roster growth). The containers file adopts it as the debuff shell.
                hdr:SetAttribute("auraContainerTemplate", "CustomAuraContainerTemplate")
            hdr:SetAttribute("template", "SecureUnitButtonTemplate")
            hdr:SetAttribute("templateType", "Button")
            hdr:SetAttribute("initialConfigFunction", initConfig)
            hdr:SetAttribute("point", initPoint)
            hdr:SetAttribute("xOffset", initXOff)
            hdr:SetAttribute("yOffset", initYOff)
            hdr:SetAttribute("groupFilter", tostring(group))
            hdr:SetAttribute("showRaid", true)
            hdr:SetAttribute("showParty", true)
            hdr:SetAttribute("showPlayer", true)
            hdr:SetAttribute("showSolo", s.showWhenSolo or false)
            hdr:SetAttribute("maxColumns", 1)
            hdr:SetAttribute("unitsPerColumn", 5)

            hdr:SetAttribute("sortMethod", "INDEX")

            -- Pre-create 5 buttons per group
            hdr:SetAttribute("startingIndex", -4)
            hdr:Show()
            hdr:SetAttribute("startingIndex", 1)

            -- Window-phase secure styling only; the insecure visual bodies run
            -- in the deferred login pass (or the restyle-loop fallback).
            for i = 1, 5 do
                local btn = hdr[i]
                if btn then
                    ns._StyleButtonSecure(btn)
                    allButtons[#allButtons + 1] = btn
                end
            end

            separatedHdrs[group] = hdr
        end
    else
        -----------------------------------------------------------
        --  Flat header for merge-groups mode (all members in one grid)
        -----------------------------------------------------------
        ns._flatHeader = CreateFrame("Frame", "ERFFlatHeader", containerFrame, "SecureGroupHeaderTemplate")
            ns._flatHeader:SetAttribute("auraContainerTemplate", "CustomAuraContainerTemplate")
        ns._flatHeader:SetAttribute("template", "SecureUnitButtonTemplate")
        ns._flatHeader:SetAttribute("templateType", "Button")
        ns._flatHeader:SetAttribute("initialConfigFunction", initConfig)
        ns._flatHeader:SetAttribute("point", initPoint)
        ns._flatHeader:SetAttribute("xOffset", initXOff)
        ns._flatHeader:SetAttribute("yOffset", initYOff)
        ns._flatHeader:SetAttribute("groupFilter", "1,2,3,4,5,6,7,8")
        ns._flatHeader:SetAttribute("showRaid", true)
        ns._flatHeader:SetAttribute("showParty", true)
        ns._flatHeader:SetAttribute("showPlayer", true)
        ns._flatHeader:SetAttribute("showSolo", s.showWhenSolo or false)
        ns._flatHeader:SetAttribute("unitsPerColumn", 5)
        ns._flatHeader:SetAttribute("maxColumns", 8)
        ns._flatHeader:SetAttribute("columnSpacing", PixelSnap(s.groupSpacing or 8))
        ns._flatHeader:SetAttribute("columnAnchorPoint", ns._RFColAnchor(initUnitGrowth, initGroupGrowth))
        ns._flatHeader:SetAttribute("sortMethod", "INDEX")

        -- Pre-create 40 buttons
        ns._flatHeader:SetAttribute("startingIndex", -39)
        ns._flatHeader:Show()
        ns._flatHeader:SetAttribute("startingIndex", 1)
        ns._flatHeader:Hide()  -- start hidden; LayoutGroups shows the right headers

        -- Window-phase secure styling only; bodies run in the deferred pass.
        for i = 1, 40 do
            local btn = ns._flatHeader[i]
            if btn then
                ns._StyleButtonSecure(btn)
                allButtons[#allButtons + 1] = btn
                ns._flatButtons[#ns._flatButtons + 1] = btn
            end
        end
    end
    if hid then containerFrame:Hide() end

    -- Freshly built headers need the current sort attributes.
    ApplySortToHeaders()
end

local function CreateHeaders()
    if containerFrame then return end

    local s = db.profile

    -- Container frame for positioning (not secure, just holds headers)
    SetContainerFrame(CreateFrame("Frame", "EllesmereUIRaidFrameContainer", UIParent))
    ns._PreviewBind(db, PP, containerFrame)
    containerFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    containerFrame:SetSize(1, 1)
    containerFrame:SetFrameStrata(ns._ResolveFrameStrata(false))
    containerFrame:Show()

    -- Group-number labels (1-8) for the real raid frames. Own (non-secure)
    -- FontStrings parented to the container; they track each group's first unit
    -- via relative anchoring (no SetPoint is ever issued on the secure headers).
    -- Shown only when showGroupNumbers is on (see ns._UpdateGroupNumbers).
    if not ns._groupNumberLabels then
        -- Overlay host at a high frame level: labels parented straight to the
        -- container render BENEATH the bars (buttons are its descendants); a
        -- high level within the same (LOW) strata lifts them on top.
        ns._groupNumberOverlay = CreateFrame("Frame", nil, containerFrame)
        ns._groupNumberOverlay:SetAllPoints(containerFrame)
        ns._groupNumberOverlay:SetFrameLevel(9000)
        ns._groupNumberLabels = {}
        for gi = 1, 8 do
            local lbl = ns._groupNumberOverlay:CreateFontString(nil, "OVERLAY")
            lbl:Hide()
            ns._groupNumberLabels[gi] = lbl
        end
    end

    -- Build ONLY the active mode's header set; the inactive one materializes
    -- on the first Merge Groups flip (see ns._BuildHeaderSet above).
    ns._BuildHeaderSet((s.mergeGroups and true) or false)
end

-------------------------------------------------------------------------------
--  Layout groups
--  Two perpendicular axes: groupGrowth (where next group goes) and
--  unitGrowth (where next unit within a group goes). groupGrowth also accepts
--  the grid flow "DOWNRIGHT" (ns._RFGroupFlow): ns._RF_GRID_ROWS groups stack
--  down one column before the next column starts to the right, instead of one
--  continuous run.
-------------------------------------------------------------------------------
local MOVER_GROUPS = 4

-- The separated layout's group slot origins, refilled by every pass
-- (ns._RFGroupFlow's out table).
local groupFlowSlots = {}

-- Real-frame group numbers (1-8): mirror the preview labels onto the actual
-- frames when showGroupNumbers is on, anchoring each group's label to its
-- first populated unit (shared groupNumberSize/Color). Raid + separated-groups
-- only (merged has no per-group first unit). Combat-safe: called only from
-- LayoutGroups (early-returns in combat), SetPoints only our own FontStrings.
function ns._UpdateGroupNumbers()
    local labels = ns._groupNumberLabels
    if not labels then return end
    if InCombatLockdown() then return end
    local s = db.profile
    if (not s.showGroupNumbers) or s.mergeGroups or (not IsInRaid()) then
        for g = 1, 8 do if labels[g] then labels[g]:Hide() end end
        return
    end
    -- Effective unit growth (mirror the LayoutGroups tier override)
    local unitGrowth = s.unitGrowth or "DOWN"
    local activeOv = ns._activeTierOverride
    if activeOv and activeOv.unitGrowth then unitGrowth = activeOv.unitGrowth end
    local vg = ns._VisibleGroups() or { true, true, true, true, true, true, false, false }
    local size = s.groupNumberSize or 10
    local gc = s.groupNumberColor or {}
    local ox = s.groupNumberOffsetX or 0
    local oy = s.groupNumberOffsetY or 0
    for group = 1, 8 do
        local lbl = labels[group]
        local hdr = separatedHdrs[group]
        local firstBtn
        if lbl and hdr and vg[group] ~= false then
            -- First populated unit of this group (empty-but-visible groups -> none)
            for i = 1, 5 do
                local btn = hdr[i]
                if btn and btn:IsShown() and btn:GetAttribute("unit") then firstBtn = btn; break end
            end
        end
        if lbl then
            if firstBtn then
                lbl:ClearAllPoints()
                if unitGrowth == "DOWN" then
                    lbl:SetPoint("BOTTOM", firstBtn, "TOP", ox, 4 + oy)
                elseif unitGrowth == "UP" then
                    lbl:SetPoint("TOP", firstBtn, "BOTTOM", ox, -4 + oy)
                elseif unitGrowth == "RIGHT" then
                    lbl:SetPoint("RIGHT", firstBtn, "LEFT", -3 + ox, oy)
                else -- LEFT
                    lbl:SetPoint("LEFT", firstBtn, "RIGHT", 3 + ox, oy)
                end
                ApplyFont(lbl, size)  -- must precede SetText (FontString needs a font first)
                lbl:SetText(tostring(group))
                lbl:SetTextColor(gc.r or 1, gc.g or 1, gc.b or 1, gc.a or 0.75)
                lbl:Show()
            else
                lbl:Hide()
            end
        end
    end
end

-- Real layout work. Call only through LayoutGroups() below, which wraps this in a
-- coalescing re-entrancy guard. Mutating secure group headers here (Hide/Show/
-- SetAttribute) and resizing the container makes Blizzard re-anchor their children
-- synchronously, which can re-enter layout through our own hooks. Stored on ns.
ns._LayoutGroupsImpl = function()
    if not containerFrame then return end
    if InCombatLockdown() then return end

    local s = db.profile
    local merged = s.mergeGroups
    -- Belt: any path that flips the mode without passing through ReloadFrames
    -- still gets its header set built before this tries to show it.
    ns._BuildHeaderSet((merged and true) or false)
    local groupGrowth = s.groupGrowth or "RIGHT"
    local unitGrowth  = s.unitGrowth or "DOWN"
    -- Per-tier growth overrides
    local activeOv = ns._activeTierOverride
    if activeOv then
        groupGrowth = activeOv.groupGrowth or groupGrowth
        unitGrowth  = activeOv.unitGrowth or unitGrowth
    end
    -- Backstop: self-heal a same-axis pair that reached here without going
    -- through a guarded write site (see ns._RFEffectiveGrowth).
    unitGrowth, groupGrowth = ns._RFEffectiveGrowth(unitGrowth, groupGrowth, merged)
    local bw = PixelSnap(ns._activeSizeW or s.frameWidth or 72)
    local bh = PixelSnap(ns._activeSizeH or s.frameHeight or 46)
    local cs = PixelSnap(s.cellSpacing or 2)
    local gs = PixelSnap(s.groupSpacing or 8)

    -- Header attributes for unit growth direction
    local hdrPoint, hdrXOff, hdrYOff = ns._RFHeaderPoint(unitGrowth, cs)

    -- Column anchor: where next column of 5 goes (perpendicular to unit growth)
    local colAnchor = ns._RFColAnchor(unitGrowth, groupGrowth)

    -- Group bounding box: size of one group along each axis
    local groupW, groupH
    if unitGrowth == "RIGHT" or unitGrowth == "LEFT" then
        groupW = 5 * bw + 4 * cs
        groupH = bh
    else
        groupW = bw
        groupH = 5 * bh + 4 * cs
    end

    -- Build visible groups filter string from settings
    local vg = ns._VisibleGroups() or { true, true, true, true, true, true, false, false }
    -- Whether this layout applied the Mythic cap (the zone and difficulty checks compare against it).
    ns._rfLaidMythic = vg == ns._mythicGroups

    if merged then
        ---------------------------------------------------------------
        --  Merge-groups mode: single flat header, all members in one grid
        ---------------------------------------------------------------
        -- Hide separated headers
        for group = 1, 8 do
            local hdr = separatedHdrs[group]
            if hdr and hdr:IsShown() then hdr:Hide() end
        end

        -- Build groupFilter from visible groups
        local gfParts = {}
        for i = 1, 8 do
            if vg[i] ~= false then gfParts[#gfParts + 1] = tostring(i) end
        end
        local gfStr = table.concat(gfParts, ",")

        -- Configure flat header layout attributes
        if ns._flatHeader then
            -- Blizzard's header anchors its first button at the corner where
            -- "point" and "columnAnchorPoint" meet, then grows away from it --
            -- same corner ns._RFGrowthCorner names for separated headers. A
            -- fixed TOPLEFT here left the rendered grid offset from the
            -- container/mover box whenever growth pinned a different corner.
            local hdrCorner = ns._RFGrowthCorner(unitGrowth, groupGrowth)
            ns._flatHeader:ClearAllPoints()
            ns._flatHeader:SetPoint(hdrCorner, containerFrame, hdrCorner, 0, 0)
            local layoutChanged = false
            -- While Self Position owns the merged header (whole-raid nameList,
            -- applied by ApplySortToHeaders at the end of this pass), a
            -- groupFilter write here would fight its clear on every pass. Cache
            -- the string instead -- ApplySortToHeaders restores it whenever the
            -- nameList bails on unresolved names. Role + Prioritize Class and
            -- Sort By = FrameSort own it the same way.
            ns._flatGfStr = gfStr
            local selfOwnsHeader = (s.showSelfFirst or s.showSelfLast
                or (s.prioritizeClass == true and s.sortMode == "ROLE")
                or s.sortMode == "FRAMESORT") and IsInRaid()
            if not selfOwnsHeader and ns._flatHeader:GetAttribute("groupFilter") ~= gfStr then
                ns._flatHeader:SetAttribute("groupFilter", gfStr)
            end
            if ns._flatHeader:GetAttribute("point") ~= hdrPoint
            or ns._flatHeader:GetAttribute("xOffset") ~= hdrXOff
            or ns._flatHeader:GetAttribute("yOffset") ~= hdrYOff
            or ns._flatHeader:GetAttribute("columnAnchorPoint") ~= colAnchor then
                -- Clear child anchors before changing layout direction
                local ci, child = 1, ns._flatHeader:GetAttribute("child1")
                while child do
                    child:ClearAllPoints()
                    ci = ci + 1
                    child = ns._flatHeader:GetAttribute("child" .. ci)
                end
                ns._flatHeader:SetAttribute("point", hdrPoint)
                ns._flatHeader:SetAttribute("xOffset", hdrXOff)
                ns._flatHeader:SetAttribute("yOffset", hdrYOff)
                ns._flatHeader:SetAttribute("columnAnchorPoint", colAnchor)
                layoutChanged = true
            end
            if ns._flatHeader:GetAttribute("columnSpacing") ~= gs then
                ns._flatHeader:SetAttribute("columnSpacing", gs)
            end
            if layoutChanged and ns._flatHeader:IsShown() then
                ns._flatHeader:Hide()
                ns._flatHeader:Show()
            elseif not ns._flatHeader:IsShown() then
                ns._flatHeader:Show()
            end
        end
    else
        ---------------------------------------------------------------
        --  Per-group mode: 8 separated headers
        ---------------------------------------------------------------
        -- Hide flat header
        if ns._flatHeader and ns._flatHeader:IsShown() then ns._flatHeader:Hide() end

        -- Group slot origins along the growth flow: a plain direction is one
        -- continuous run, the grid flow ("Down and then Right") stacks
        -- ns._RF_GRID_ROWS groups per column. Eight slots are generated (up to
        -- 8 visible groups) but only the four the box is sized for
        -- (MOVER_GROUPS) set the normalization origin, so a group past the box
        -- keeps the same per-slot step instead of rescaling everything in front
        -- of it.
        local slots, minX, maxY = ns._RFGroupFlow(groupGrowth, groupW, groupH, gs, 8, groupFlowSlots)

        -- For UP/LEFT unit growth, pin each header by the corner its units
        -- grow away from: the offset moves (x, y) to that cell edge and the
        -- matching corner anchors there, so the group fills its cell. A
        -- TOPLEFT anchor for these directions displaces the frames a full
        -- group height/width outside the container, mismatching preview/mover.
        local hdrAnchor = "TOPLEFT"
        local hdrOffX, hdrOffY = 0, 0
        if unitGrowth == "UP"   then hdrAnchor = "BOTTOMLEFT"; hdrOffY = -groupH end
        if unitGrowth == "LEFT" then hdrAnchor = "TOPRIGHT";   hdrOffX = groupW  end

        -- "Hide Empty Groups": collapse memberless subgroups so the remaining
        -- groups close ranks (1/2/3/6 instead of a gap at 4/5). Real frames
        -- only; needs live raid roster data, so skipped outside a raid
        -- (GetRaidRosterInfo returns nil there -> would hide every group).
        -- Skipped while the group state hides the set too: a hidden header
        -- ignores the roster, so one hidden here would stay empty if the
        -- visibility driver shows the set mid-fight (the shown pass collapses).
        local occupied
        if s.hideEmptyGroups ~= false and IsInRaid() and ns._RFVisWanted() then
            occupied = {}
            for ri = 1, GetNumGroupMembers() or 0 do
                local _, _, sub = GetRaidRosterInfo(ri)
                if sub then occupied[sub] = true end
            end
        end

        local visSlot = 0  -- running counter for visible groups (collapses gaps)
        local groupOrder = s.customGroupOrder and ns._RFValidatedGroupOrder(s.groupOrder)
        for slot = 1, 8 do
            local group = groupOrder and groupOrder[slot] or slot
            local hdr = separatedHdrs[group]
            if hdr then
                if vg[group] == false or (occupied and not occupied[group]) then
                    if hdr:IsShown() then hdr:Hide() end
                else
                    local x = PixelSnap(slots[visSlot][1] - minX + hdrOffX)
                    local y = PixelSnap(slots[visSlot][2] - maxY + hdrOffY)
                    visSlot = visSlot + 1

                    hdr:ClearAllPoints()
                    hdr:SetPoint(hdrAnchor, containerFrame, "TOPLEFT", x, y)
                    local layoutChanged = false
                    if hdr:GetAttribute("point") ~= hdrPoint
                    or hdr:GetAttribute("xOffset") ~= hdrXOff
                    or hdr:GetAttribute("yOffset") ~= hdrYOff then
                        -- Clear child anchors before changing layout direction
                        local ci, child = 1, hdr:GetAttribute("child1")
                        while child do
                            child:ClearAllPoints()
                            ci = ci + 1
                            child = hdr:GetAttribute("child" .. ci)
                        end
                        hdr:SetAttribute("point", hdrPoint)
                        hdr:SetAttribute("xOffset", hdrXOff)
                        hdr:SetAttribute("yOffset", hdrYOff)
                        layoutChanged = true
                    end
                    if layoutChanged and hdr:IsShown() then
                        hdr:Hide()
                        hdr:Show()
                    elseif not hdr:IsShown() then
                        hdr:Show()
                    end
                end
            end
        end
    end

    -- Apply sort after all headers are positioned
    ApplySortToHeaders()
    -- Which layout the headers now carry (shown: full; hidden: native), for
    -- UpdateVisibility to re-lay them when the set shows or hides.
    ns._rfRaidLaidVis = ns._RFVisWanted()

    -- Container size for unlock mode's mover. Merged mode's
    -- columnAnchorPoint is always perpendicular to unitGrowth (colAnchor above),
    -- so its actual render axis follows unitGrowth, not the literal groupGrowth
    -- (which can share unitGrowth's axis; Blizzard's header can't express that as
    -- a column direction). Keying the box off groupGrowth there mismatches the
    -- box against what merged mode really renders. Separated mode has no such
    -- header constraint and renders along groupGrowth literally, so it reads the
    -- same formula every other size consumer uses (ns._RFFootprint).
    local totalW, totalH
    if merged then
        if unitGrowth == "DOWN" or unitGrowth == "UP" then
            totalW = MOVER_GROUPS * groupW + (MOVER_GROUPS - 1) * gs
            totalH = groupH
        else
            totalW = groupW
            totalH = MOVER_GROUPS * groupH + (MOVER_GROUPS - 1) * gs
        end
    else
        totalW, totalH = ns._RFFootprint(bw, bh, unitGrowth, groupGrowth, cs, gs)
    end
    containerFrame:SetSize(PixelSnap(totalW), PixelSnap(totalH))

    -- Snap the container's screen position to the pixel grid. Skip when
    -- element-anchored: ApplyAnchorPosition already pixel-snaps, and a
    -- TOPLEFT re-anchor here would fight the anchor cascade.
    if not InCombatLockdown()
       and not (EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored("RF_RaidFrames")) then
        local l = containerFrame:GetLeft()
        local t = containerFrame:GetTop()
        if l and t then
            local snappedL = PixelSnap(l)
            local snappedT = PixelSnap(t)
            if abs(l - snappedL) > 0.01 or abs(t - snappedT) > 0.01 then
                containerFrame:ClearAllPoints()
                containerFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", snappedL, snappedT)
            end
        end
    end

    -- Update real-frame group numbers now that all headers are positioned.
    ns._UpdateGroupNumbers()
end

-- Coalescing re-entrancy guard: a re-entrant LayoutGroups() call is NOT dropped
-- (would strand stale frames) -- it marks the pass dirty and the in-flight call
-- re-runs on return, bounded to 3 passes so a non-converging header feedback
-- loop (SetAttribute/SetSize -> engine re-anchors children -> our hook -> here)
-- can't spin into a watchdog kill. pcall clears the busy flag on error and
-- rethrows, so one error can't freeze every future layout. State on ns.
local function LayoutGroups()
    if ns._inLayoutGroups then
        ns._layoutGroupsDirty = true
        return
    end
    ns._inLayoutGroups = true
    local passes = 0
    repeat
        ns._layoutGroupsDirty = false
        passes = passes + 1
        local ok, err = pcall(ns._LayoutGroupsImpl)
        if not ok then
            ns._inLayoutGroups = false
            return geterrorhandler()(err)
        end
    until (not ns._layoutGroupsDirty) or passes >= 3
    ns._inLayoutGroups = false
    -- Cap reached with work still pending: a genuine non-converging relayout loop.
    -- The guard kept it from freezing the client; surface it once (out of combat)
    -- so it stays diagnosable instead of silently masking a real bug.
    if ns._layoutGroupsDirty and not ns._layoutLoopWarned and not InCombatLockdown() then
        ns._layoutLoopWarned = true
        print("|cffff5555EllesmereUI Raid Frames:|r layout did not settle after 3 passes; " ..
            "a re-entrant loop was bounded. Please report this if frames look wrong.")
    end
end

I.CreateHeaders, I.LayoutGroups, I.MOVER_GROUPS = CreateHeaders, LayoutGroups, MOVER_GROUPS
I.broken = false
