if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_ActionBars_Unlock.lua
--
--  Bar position save and restore, and the Unlock Mode registration.
--  Loads after EUI_ActionBars_ApplyAll.lua; reads ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...

local ipairs = ipairs
local InCombatLockdown = InCombatLockdown

local EAB = ns.EAB
local I = ns._internals
local BAR_CONFIG, EXTRA_BARS, SHAPE_BTN_EXPAND = I.BAR_CONFIG, I.EXTRA_BARS, I.SHAPE_BTN_EXPAND
local barFrames, BLIZZ_MOVABLE_OVERLAY = I.barFrames, I.BLIZZ_MOVABLE_OVERLAY
local blizzMovableHolders = I.blizzMovableHolders
local LayoutBar = I.LayoutBar

-------------------------------------------------------------------------------
--  Position Save/Restore
-------------------------------------------------------------------------------
-- Convert CENTER position to edge for non-CENTER-grow bars (same pattern as CDM).
-- Stored on EAB, not in a file local.
function EAB:ConvertCenterToEdge(barKey, point, x, y)
    if point ~= "CENTER" then return point, x, y end
    local cfg = self.db and self.db.profile and self.db.profile.bars and self.db.profile.bars[barKey]
    local grow = cfg and cfg.growDirection
    if not grow then return point, x, y end
    grow = grow:upper()
    if grow == "CENTER" then return point, x, y end
    local frame = barFrames[barKey]
    if not frame then return point, x, y end
    local fw = frame:GetWidth() or 0
    local fh = frame:GetHeight() or 0
    if grow == "RIGHT" and fw > 0 then return "LEFT", x - fw / 2, y
    elseif grow == "LEFT" and fw > 0 then return "RIGHT", x + fw / 2, y
    elseif grow == "DOWN" and fh > 0 then return "TOP", x, y + fh / 2
    elseif grow == "UP" and fh > 0 then return "BOTTOM", x, y - fh / 2
    end
    return point, x, y
end

function EAB:ConvertEdgeToCenter(barKey, pos)
    if not pos or not pos.point then return pos end
    local pt = pos.point
    if pt == "CENTER" then return pos end
    if pt ~= "LEFT" and pt ~= "RIGHT" and pt ~= "TOP" and pt ~= "BOTTOM" then return pos end
    local frame = barFrames[barKey]
    if not frame then return pos end
    local fw = frame:GetWidth() or 0
    local fh = frame:GetHeight() or 0
    local cx, cy = pos.x or 0, pos.y or 0
    if pt == "LEFT" then cx = cx + fw / 2
    elseif pt == "RIGHT" then cx = cx - fw / 2
    elseif pt == "TOP" then cy = cy - fh / 2
    elseif pt == "BOTTOM" then cy = cy + fh / 2
    end
    return { point = "CENTER", relPoint = pos.relPoint, x = cx, y = cy }
end

local function SaveBarPosition(barKey)
    local frame = barFrames[barKey]
    if not frame then return end
    local point, _, relPoint, x, y = frame:GetPoint(1)
    if point then
        -- Pixel-perfect snapping can leave sub-pixel offsets (0.5) on
        -- CENTER-anchored bars, and re-snapping on restore drifts 1px at some
        -- UI scales. Clamp near-zero CENTER offsets to exactly 0 so the
        -- restore-skip at RestoreBarPositions fires correctly.
        if point == "CENTER" and relPoint == "CENTER" then
            local es = frame:GetEffectiveScale() or 1
            local PPa = EllesmereUI and EllesmereUI.PP
            local onePx = PPa and PPa.perfect and (PPa.perfect / es) or 1
            if math.abs(x) < onePx then x = 0 end
            if math.abs(y) < onePx then y = 0 end
        end
        EAB.db.profile.barPositions[barKey] = {
            point = point, relPoint = relPoint, x = x, y = y,
        }
    end
end

local function RestoreBarPositions()
    local positions = EAB.db.profile.barPositions
    if not positions then return end
    local PPa = EllesmereUI and EllesmereUI.PP
    for _, info in ipairs(BAR_CONFIG) do
        local key = info.key
        local pos = positions[key]
        local frame = barFrames[key]
        if pos and frame then
            -- Skip bars owned by the unlock anchor system: position is computed
            -- from the anchor chain, not saved barPositions.
            local anchored = EllesmereUI and EllesmereUI.IsUnlockAnchored
                             and EllesmereUI.IsUnlockAnchored(key)
            if anchored then
                -- skip: anchor system owns this bar's position
            else
            local pt = pos.point or "CENTER"
            local rpt = pos.relPoint or pt
            local px = pos.x or 0
            local py = pos.y or 0
            -- Skip CENTER 0,0: this is never an intentional position.
            -- Anchored bars save 0,0 as a placeholder; their real position
            -- comes from the anchor chain which resolves later.
            if pt == "CENTER" and rpt == "CENTER" and px == 0 and py == 0 then
                -- skip
            else
                -- Snap to physical pixel grid. For CENTER-anchored bars use
                -- SnapCenterForDim with the frame's actual size so odd-pixel
                -- dimensions get the +0.5 center offset they need (plain
                -- SnapForES drifts by 1px on save & exit for odd dimensions).
                if PPa then
                    local es = frame:GetEffectiveScale()
                    local isCenterAnchor = (pt == "CENTER" and rpt == "CENTER")
                    if isCenterAnchor and PPa.SnapCenterForDim then
                        px = PPa.SnapCenterForDim(px, frame:GetWidth() or 0, es)
                        py = PPa.SnapCenterForDim(py, frame:GetHeight() or 0, es)
                    elseif PPa.SnapForES then
                        px = PPa.SnapForES(px, es)
                        py = PPa.SnapForES(py, es)
                    end
                end
                frame:ClearAllPoints()
                frame:SetPoint(pt, UIParent, rpt, px, py)
            end
            end -- anchored else
        end
    end
    -- Note: anchored bars are handled later in RegisterWithUnlockMode
    -- (0.5s deferred) via ReapplyOwnAnchor, after elements are registered.
end



-------------------------------------------------------------------------------
--  Unlock Mode Integration
--  Register bars with EUI_UnlockMode for positioning.
-------------------------------------------------------------------------------
local function RegisterWithUnlockMode()
    if not EllesmereUI or not EllesmereUI.RegisterUnlockElements then return end
    local MK = EllesmereUI.MakeUnlockElement

    local elements = {}
    local orderBase = 200

    for idx, info in ipairs(BAR_CONFIG) do
        local key = info.key
        elements[#elements + 1] = MK({
            key   = key,
            label = info.label,
            group = "Action Bars",
            order = orderBase + idx,
            isHidden = function()
                local s = EAB.db.profile.bars[info.key]
                if not s then return false end
                -- Honor the runtime "Toggle Action Bar" override the same way
                -- RefreshRuntimeVisibility does: a bar saved as Never but
                -- surfaced by the keybind is on screen, so it needs a mover;
                -- a saved-Always bar toggled off does not.
                local ov = EAB._visOverride and EAB._visOverride[info.key]
                if ov then return ov == "never" end
                return s.alwaysHidden or (EAB._padHide and s.gamepadHideBar == true)
            end,
            getFrame = function() return barFrames[info.key] end,
            getSize = function()
                local frame = barFrames[info.key]
                if not frame then return 1, 1 end
                return frame:GetWidth(), frame:GetHeight()
            end,
            linkedDimensions = true,
            -- Size matching works in every style: stock styles size their buttons
            -- from Icon Size too (LayoutBar scales the native-size button to it),
            -- and the math below uses the same layout shape as LayoutBar.
            -- A textured square border's reach past the bar's edges, so size
            -- matching lines up with what is on screen. The outer buttons sit
            -- flush on the bar frame's edges (LayoutBar: no outer inset), so
            -- the per-button reach is the bar's. Same arguments ApplyBordersForBar
            -- paints with; nil for custom shapes (their ring sits inside the
            -- button), stock looks and non-square icons.
            getMatchPad = function()
                if ns.MasqueOwnsBar(info.key) then return nil end
                local p = EAB.db and EAB.db.profile
                if not (p and p.squareIcons) or ns.AB_Style() ~= "eui" then return nil end
                local s = p.bars[info.key]
                if not s then return nil end
                local shape = s.buttonShape or "none"
                if shape ~= "none" and shape ~= "cropped" then return nil end
                local sz, px = ns.ResolveBorderThickness(s)
                local c = s.borderColor
                return EllesmereUI.BorderMatchPad(sz, s.borderTexture or "solid",
                    s.borderTextureOffset, s.borderTextureOffsetY, s.borderTextureShiftX, s.borderTextureShiftY,
                    "actionbars", s.borderThickness or "thin", px, nil, c and c.a or 1)
            end,
            setWidth = function(_, w)
                local s = EAB.db.profile.bars[info.key]
                if not s then return end
                -- Reverse-engineer square button size from total bar width
                -- using physical pixel math to distribute remainder pixels.
                local numIcons = s.overrideNumIcons or s.numIcons or info.count
                local numRows  = s.overrideNumRows  or s.numRows  or 1
                if numRows < 1 then numRows = 1 end
                local stride   = math.ceil(numIcons / numRows)
                if stride < 1 then stride = 1 end
                local isVert   = (s.orientation == "vertical")
                local pad      = s.buttonPadding or 2
                local shape    = ns.AB_LayoutShape(s, info.key)
                local cols     = isVert and numRows or stride
                local PP = EllesmereUI and EllesmereUI.PP
                local onePx = PP and PP.mult or 1
                local physTarget = math.floor(w / onePx + 0.5)
                local physPad = math.floor(pad / onePx + 0.5)
                local rawPhysBtn = (physTarget - (cols - 1) * physPad) / cols
                if shape ~= "none" and shape ~= "cropped" then
                    rawPhysBtn = rawPhysBtn - math.floor((SHAPE_BTN_EXPAND or 10) / onePx + 0.5)
                end
                if rawPhysBtn < 8 then rawPhysBtn = 8 end
                local basePhysBtn = math.floor(rawPhysBtn)
                s.buttonWidth  = basePhysBtn * onePx
                s.buttonHeight = s.buttonWidth
                -- Compute remainder pixels to distribute across columns
                local shapePhys = 0
                if shape ~= "none" and shape ~= "cropped" then
                    shapePhys = math.floor((SHAPE_BTN_EXPAND or 10) / onePx + 0.5)
                end
                local idealPhys = cols * (basePhysBtn + shapePhys) + (cols - 1) * physPad
                local extra = physTarget - idealPhys
                if extra > 0 and extra <= cols then
                    s._matchExtraPixels = extra
                else
                    s._matchExtraPixels = nil
                end
                LayoutBar(info.key)
            end,
            setHeight = function(_, h)
                local s = EAB.db.profile.bars[info.key]
                if not s then return end
                -- Reverse-engineer square button size from total bar height
                -- using physical pixel math to distribute remainder pixels.
                local numIcons = s.overrideNumIcons or s.numIcons or info.count
                local numRows  = s.overrideNumRows  or s.numRows  or 1
                if numRows < 1 then numRows = 1 end
                local stride   = math.ceil(numIcons / numRows)
                if stride < 1 then stride = 1 end
                local isVert   = (s.orientation == "vertical")
                local pad      = s.buttonPadding or 2
                local shape    = ns.AB_LayoutShape(s, info.key)
                local rows     = isVert and stride or numRows
                local PP = EllesmereUI and EllesmereUI.PP
                local onePx = PP and PP.mult or 1
                local physTarget = math.floor(h / onePx + 0.5)
                local physPad = math.floor(pad / onePx + 0.5)
                local rawPhysBtn = (physTarget - (rows - 1) * physPad) / rows
                if shape ~= "none" and shape ~= "cropped" then
                    rawPhysBtn = rawPhysBtn - math.floor((SHAPE_BTN_EXPAND or 10) / onePx + 0.5)
                elseif shape == "cropped" then
                    rawPhysBtn = rawPhysBtn / 0.80
                end
                if rawPhysBtn < 8 then rawPhysBtn = 8 end
                local basePhysBtn = math.floor(rawPhysBtn)
                s.buttonWidth  = basePhysBtn * onePx
                s.buttonHeight = s.buttonWidth
                -- Compute remainder pixels to distribute across rows
                local shapePhys = 0
                if shape ~= "none" and shape ~= "cropped" then
                    shapePhys = math.floor((SHAPE_BTN_EXPAND or 10) / onePx + 0.5)
                end
                local croppedH = basePhysBtn + shapePhys
                if shape == "cropped" then
                    croppedH = math.floor(basePhysBtn * 0.80)
                end
                local idealPhys = rows * croppedH + (rows - 1) * physPad
                local extra = physTarget - idealPhys
                if extra > 0 and extra <= rows then
                    s._matchExtraPixelsH = extra
                else
                    s._matchExtraPixelsH = nil
                end
                LayoutBar(info.key)
            end,
            savePos = function(_, point, relPoint, x, y)
                if point and x and y then
                    local sp, sx, sy = EAB:ConvertCenterToEdge(info.key, point, x, y)
                    EAB.db.profile.barPositions[info.key] = {
                        point = sp, relPoint = relPoint or point, x = sx, y = sy,
                    }
                else
                    SaveBarPosition(info.key)
                end
                -- Follow baseline: capture the anchor target's geometry at save time so
                -- ApplyAnchorPosition can shift the absolute saved growth edge by the
                -- target's displacement when it moves/resizes at runtime. Applies to
                -- every growth-direction bar so a perpendicular corner anchor to a
                -- resizing chain target can follow; nil for unanchored/CENTER-grow
                -- bars, leaving the follow off and the pure pin unchanged.
                do
                    local entry = EAB.db.profile.barPositions[info.key]
                    local s = EAB.db.profile.bars[info.key]
                    local gd = s and (s.growDirection or "up"):upper()
                    if entry and gd and gd ~= "CENTER"
                       and EllesmereUI.GetAnchorTargetCenterUI then
                        entry.tgtx, entry.tgty = EllesmereUI.GetAnchorTargetCenterUI(info.key)
                        if EllesmereUI.GetAnchorTargetEdgesUI then
                            entry.tgtL, entry.tgtR, entry.tgtT, entry.tgtB =
                                EllesmereUI.GetAnchorTargetEdgesUI(info.key)
                        end
                    end
                end
            end,
            loadPos = function()
                return EAB:ConvertEdgeToCenter(info.key, EAB.db.profile.barPositions[info.key])
            end,
            clearPos = function()
                EAB.db.profile.barPositions[info.key] = nil
            end,
            applyPos = function()
                EAB:RecalcFlyoutDirection(info.key)
                -- Anchored bars: position owned by anchor system. But bars
                -- with growth direction need edge bounds applied first so the
                -- live-edge reading in ApplyAnchorPosition has correct data.
                if EllesmereUI and EllesmereUI.IsUnlockAnchored
                   and EllesmereUI.IsUnlockAnchored(info.key) then
                    local s = EAB.db.profile.bars[info.key]
                    local gd = s and (s.growDirection or "up"):upper()
                    if gd and gd ~= "CENTER" and gd ~= "UP" then
                        local pos = EAB.db.profile.barPositions[info.key]
                        local frame = barFrames[info.key]
                        if pos and frame then
                            local pt = pos.point or "CENTER"
                            local px, py = pos.x or 0, pos.y or 0
                            -- Convert CENTER to edge (like CDM's ApplyBarPositionCentered)
                            if pt == "CENTER" then
                                local fw = frame:GetWidth() or 0
                                local fh = frame:GetHeight() or 0
                                if gd == "RIGHT" and fw > 0 then
                                    pt = "LEFT"; px = px - fw / 2
                                elseif gd == "LEFT" and fw > 0 then
                                    pt = "RIGHT"; px = px + fw / 2
                                elseif gd == "DOWN" and fh > 0 then
                                    pt = "TOP"; py = py + fh / 2
                                end
                            end
                            if pt ~= "CENTER" then
                                local PPa = EllesmereUI and EllesmereUI.PP
                                if PPa and PPa.SnapForES then
                                    local es = frame:GetEffectiveScale()
                                    px = PPa.SnapForES(px, es)
                                    py = PPa.SnapForES(py, es)
                                end
                                frame:ClearAllPoints()
                                frame:SetPoint(pt, UIParent, pos.relPoint or "CENTER", px, py)
                            end
                        end
                    end
                    return
                end
                local pos = EAB.db.profile.barPositions[info.key]
                local frame = barFrames[info.key]
                if pos and frame then
                    local pt = pos.point
                    local px, py = pos.x, pos.y
                    local PPa = EllesmereUI and EllesmereUI.PP
                    if PPa and px and py then
                        local es = frame:GetEffectiveScale()
                        local isCenterAnchor = (pt == "CENTER")
                            and (pos.relPoint == "CENTER" or pos.relPoint == nil)
                        if isCenterAnchor and PPa.SnapCenterForDim then
                            px = PPa.SnapCenterForDim(px, frame:GetWidth() or 0, es)
                            py = PPa.SnapCenterForDim(py, frame:GetHeight() or 0, es)
                        elseif PPa.SnapForES then
                            px = PPa.SnapForES(px, es)
                            py = PPa.SnapForES(py, es)
                        end
                    end
                    frame:ClearAllPoints()
                    frame:SetPoint(pt, UIParent, pos.relPoint or pt, px, py)
                end
            end,
        })
    end

    -- Blizzard movable frames (Extra Action Button, Encounter Bar)
    local blizzOrder = orderBase + #BAR_CONFIG
    for _, info in ipairs(EXTRA_BARS) do
        if info.isBlizzardMovable then
            blizzOrder = blizzOrder + 1
            local bk = info.key
            elements[#elements + 1] = MK({
                key   = bk,
                label = info.label,
                group = "Action Bars",
                order = blizzOrder,
                noResize = true,
                -- The Extra Action Button hidden for good (Never, or hidden by
                -- the Toggle Action Bar keybind), as RefreshRuntimeVisibility
                -- hides its holder: no mover, and the Cooldown Manager's group
                -- loot rolls stop keeping clear of it.
                isHidden = (bk == "ExtraActionButton") and function()
                    local s = EAB.db.profile.bars[bk]
                    if not s then return false end
                    local ov = EAB._visOverride and EAB._visOverride[bk]
                    if ov then return ov == "never" end
                    return s.alwaysHidden or s.barVisibility == "never"
                end or nil,
                getFrame = function() return blizzMovableHolders[bk] end,
                getSize = function()
                    local ov = BLIZZ_MOVABLE_OVERLAY[bk]
                    if ov then return ov.w, ov.h end
                    return 50, 50
                end,
                savePos = function(_, point, relPoint, x, y)
                    if point and x and y then
                        EAB.db.profile.barPositions[bk] = {
                            point = point, relPoint = relPoint or point, x = x, y = y,
                        }
                    end
                    if not EllesmereUI._unlockActive then
                        local holder = blizzMovableHolders[bk]
                        if holder and point and x and y and not InCombatLockdown() then
                            holder:ClearAllPoints()
                            holder:SetPoint(point, UIParent, relPoint or point, x, y)
                        end
                    end
                end,
                loadPos = function()
                    local pos = EAB.db.profile.barPositions[bk]
                    if not pos then return nil end
                    local pt = pos.point
                    return { point = pt, relPoint = pos.relPoint or pt, x = pos.x, y = pos.y }
                end,
                clearPos = function()
                    EAB.db.profile.barPositions[bk] = nil
                end,
                applyPos = function()
                    local pos = EAB.db.profile.barPositions[bk]
                    local holder = blizzMovableHolders[bk]
                    if not holder or InCombatLockdown() then return end
                    holder:ClearAllPoints()
                    if pos then
                        local pt = pos.point
                        local px, py = pos.x, pos.y
                        local PPa = EllesmereUI and EllesmereUI.PP
                        if PPa and px and py then
                            local es = holder:GetEffectiveScale()
                            local isCenterAnchor = (pt == "CENTER")
                                and (pos.relPoint == "CENTER" or pos.relPoint == nil)
                            if isCenterAnchor and PPa.SnapCenterForDim then
                                px = PPa.SnapCenterForDim(px, holder:GetWidth() or 0, es)
                                py = PPa.SnapCenterForDim(py, holder:GetHeight() or 0, es)
                            elseif PPa.SnapForES then
                                px = PPa.SnapForES(px, es)
                                py = PPa.SnapForES(py, es)
                            end
                        end
                        holder:SetPoint(pt, UIParent, pos.relPoint or pt, px, py)
                    else
                        holder:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
                    end
                end,
            })
        end
    end


    EllesmereUI:RegisterUnlockElements(elements, "EllesmereUIActionBars")

    -- Reapply anchors now that elements are registered: RestoreBarPositions
    -- ran before registration (too early for ReapplyOwnAnchor to resolve
    -- frames), so anchored bars sit unresolved. Skip growth-direction bars:
    -- applyPos already pre-positioned them at the edge and the authoritative
    -- pass preserves that via live-edge reading.
    if EllesmereUI.ReapplyOwnAnchor then
        for _, info in ipairs(BAR_CONFIG) do
            if EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored(info.key) then
                local s = EAB.db.profile.bars[info.key]
                local gd = s and (s.growDirection or "up"):upper()
                if not gd or gd == "CENTER" or gd == "UP" then
                    EllesmereUI.ReapplyOwnAnchor(info.key)
                end
            end
        end
    end
end

-- Entry points the files after this one re-import by name.
I.RestoreBarPositions, I.RegisterWithUnlockMode = RestoreBarPositions, RegisterWithUnlockMode
