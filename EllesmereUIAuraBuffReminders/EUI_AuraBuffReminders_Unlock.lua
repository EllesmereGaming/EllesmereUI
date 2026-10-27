if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_AuraBuffReminders_Unlock.lua
--
--  Unlock Mode: positions, grow direction and the element registration.
--  Reads the earlier AuraBuff Reminders files through ns._abrInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._abrInternals
-- EllesmereUIAuraBuffReminders.lua or an earlier AuraBuff Reminders file
-- failed to load.
if not I or I.broken then return end
I.broken = true

local floor, abs = math.floor, math.abs

local _B, EABR, activeIcons, ICON_SIZE = I._B, I.EABR, I.activeIcons, I.ICON_SIZE
local LayoutIcons, ResizeAnchorCentered = I.LayoutIcons, I.ResizeAnchorCentered
local CursorAttachActive = I.CursorAttachActive

local db
I.dbSetters[#I.dbSetters + 1] = function(v) db = v end
local iconAnchor
I.iconAnchorSetters[#I.iconAnchorSetters + 1] = function(v) iconAnchor = v end
local cursorAnchor
I.cursorAnchorSetters[#I.cursorAnchorSetters + 1] = function(v) cursorAnchor = v end

-------------------------------------------------------------------------------
--  Unlock Mode
-------------------------------------------------------------------------------
-- Nominal two-icon row width from settings alone: the nil-position grow edge and the converter's empty-row width.
function EABR.NominalRowW(d)
    return 2 * floor(ICON_SIZE * (d.scale or 1.0) + 0.5) + (d.iconSpacing or 8)
end

local function ApplyUnlockPos()
    if not iconAnchor or not db then return end
    -- Skip for unlock-anchored elements (anchor system is authority)
    local anchored = EllesmereUI and EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored("EABR_Reminders")
    if anchored and iconAnchor:GetLeft() then return end
    local pos = db.profile.unlockPos
    if pos and pos.point then
        local px, py = pos.x or 0, pos.y or 0
        local PPa = EllesmereUI and EllesmereUI.PP
        if PPa then
            local es = iconAnchor:GetEffectiveScale()
            -- For CENTER anchor, uses SnapCenterForDim with the frame's actual size so odd-pixel-dim frames get the +0.5 offset that places edges on whole pixels.
            local isCenterAnchor = (pos.point == "CENTER")
                and (pos.relPoint == "CENTER" or pos.relPoint == nil)
            if isCenterAnchor and PPa.SnapCenterForDim then
                px = PPa.SnapCenterForDim(px, iconAnchor:GetWidth() or 0, es)
                py = PPa.SnapCenterForDim(py, iconAnchor:GetHeight() or 0, es)
            elseif PPa.SnapForES then
                px = PPa.SnapForES(px, es)
                py = PPa.SnapForES(py, es)
            end
        end
        iconAnchor:ClearAllPoints()
        iconAnchor:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, px, py)
    else
        -- No saved position: the row sits at the configured offset from screen center, anchored by its grow edge.
        -- Grow Right/Left place that edge half a nominal two-icon row out (settings only, never the live width) so
        -- it never follows the icon count; LayoutIcons hangs the icons off the same edge and owns the anchor's size.
        local d = db.profile.display
        local growDir = d.growDirection
        iconAnchor:ClearAllPoints()
        if growDir == "RIGHT" then
            iconAnchor:SetPoint("LEFT", UIParent, "CENTER", (d.xOffset or 0) - EABR.NominalRowW(d) / 2, d.yOffset or 0)
        elseif growDir == "LEFT" then
            iconAnchor:SetPoint("RIGHT", UIParent, "CENTER", (d.xOffset or 0) + EABR.NominalRowW(d) / 2, d.yOffset or 0)
        else
            iconAnchor:SetPoint("CENTER", UIParent, "CENTER", d.xOffset or 0, d.yOffset or 0)
        end
    end
end

-- Moves a saved position onto the new grow edge (Grow Right = LEFT, Grow Left = RIGHT, else CENTER) without
-- moving the row. Runs only on a grow direction change or a spec layer restoring a position banked under another
-- direction: the apply path never writes the DB, and a nil position stays nil. Only positions this module writes
-- (CENTER, LEFT or RIGHT of UIParent's CENTER) convert.
function EABR.UpdateUnlockPosForGrowDir(newGrowDir)
    local pos = db.profile.unlockPos
    if not pos or not pos.point or (pos.relPoint or pos.point) ~= "CENTER" then return end
    local curPoint = pos.point
    if curPoint ~= "CENTER" and curPoint ~= "LEFT" and curPoint ~= "RIGHT" then return end
    local targetPoint = (newGrowDir == "RIGHT" and "LEFT") or (newGrowDir == "LEFT" and "RIGHT") or "CENTER"
    if curPoint == targetPoint then return end
    local w = iconAnchor and iconAnchor:GetWidth() or 0
    if w <= 1 then w = EABR.NominalRowW(db.profile.display) end
    local cx = pos.x or 0
    if curPoint == "LEFT" then
        cx = cx + (w / 2)
    elseif curPoint == "RIGHT" then
        cx = cx - (w / 2)
    end
    if targetPoint == "LEFT" then
        pos.x = cx - (w / 2)
    elseif targetPoint == "RIGHT" then
        pos.x = cx + (w / 2)
    else
        pos.x = cx
    end
    pos.point = targetPoint
    pos.relPoint = "CENTER"
end

function EllesmereUI.GetAuraBuffGrowDir()
    local d = db and db.profile and db.profile.display
    return d and d.growDirection or "CENTER"
end

function EllesmereUI.SetAuraBuffGrowDir(v)
    if not db or not db.profile or not db.profile.display then return end
    db.profile.display.growDirection = v
    EABR.UpdateUnlockPosForGrowDir(v)
    ApplyUnlockPos()
    LayoutIcons()
end

local function RegisterUnlockElements()
    if not EllesmereUI or not EllesmereUI.RegisterUnlockElements then return end
    local MK = EllesmereUI.MakeUnlockElement
    EllesmereUI:RegisterUnlockElements({
        MK({
            key = "EABR_Reminders",
            label = "AuraBuff Reminders",
            group = "AuraBuff Reminders",
            order = 600,
            noAnchorTarget = true,  -- icon count changes dynamically with auras
            -- Icon size is driven solely by the Scale slider. No drag-resize: row width is count-dependent, so restoring a stored width under a different count would corrupt the persisted scale (matches External Defensives).
            noResize = true,
            getFrame = function() return iconAnchor end,
            getSize = function()
                local p = db.profile.display
                local baseScale = p.scale or 1.0
                local sz = floor(ICON_SIZE * baseScale + 0.5)
                local spacing = p.iconSpacing or 8
                -- Fits all active icons (same set LayoutIcons places: reminders + merged beacon icons unless cursor-routed); falls back to a 2-wide grabbable box when empty so the mover overlay stays draggable.
                local count = #activeIcons
                local beaconsOnCursor = CursorAttachActive(p) and cursorAnchor
                if _B.icons and not beaconsOnCursor then
                    for _, id in ipairs(_B.ALL or {}) do
                        if _B.iconState and _B.iconState[id] and _B.icons[id] then count = count + 1 end
                    end
                end
                if count < 1 then count = 2 end
                local w = count * sz + (count - 1) * spacing
                local textH = 0
                if p.showText then
                    textH = (p.textSize or 11) + abs(p.textYOffset or -2)
                end
                local h = sz + textH
                -- Resizes the anchor for the overlay
                if iconAnchor then ResizeAnchorCentered(w, h) end
                return w, h
            end,
            savePos = function(key, point, relPoint, x, y)
                -- Unlock mode hands over the row's CENTER; Grow Right/Left store their fixed edge instead.
                local growDir = db.profile.display.growDirection
                if (growDir == "RIGHT" or growDir == "LEFT") and point == "CENTER" and relPoint == "CENTER" then
                    local halfW = (iconAnchor and iconAnchor:GetWidth() or 0) / 2
                    if growDir == "RIGHT" then
                        point, x = "LEFT", x - halfW
                    else
                        point, x = "RIGHT", x + halfW
                    end
                end
                db.profile.unlockPos = {point=point, relPoint=relPoint, x=x, y=y}
                if not EllesmereUI._unlockActive then
                    ApplyUnlockPos()
                end
            end,
            loadPos = function()
                local pos = db.profile.unlockPos
                -- A stored grow edge (LEFT/RIGHT of UIParent's CENTER) reports the row's CENTER, the form unlock mode works in.
                -- That CENTER follows the live width, so a Discard after the icon count changed moves the edge by half the change.
                if not pos or (pos.point ~= "LEFT" and pos.point ~= "RIGHT") or pos.relPoint ~= "CENTER" then
                    return pos
                end
                local halfW = (iconAnchor and iconAnchor:GetWidth() or 0) / 2
                return {
                    point = "CENTER",
                    relPoint = "CENTER",
                    x = (pos.x or 0) + ((pos.point == "LEFT") and halfW or -halfW),
                    y = pos.y or 0,
                }
            end,
            -- Spec-override unlock layers bank the stored table itself, so a Grow Right/Left edge survives a
            -- layer round trip at any icon count; one banked under another direction moves onto the current edge.
            loadRawPos = function()
                return db.profile.unlockPos
            end,
            saveRawPos = function(_, p)
                if not (p and p.point) then return end
                db.profile.unlockPos = {point=p.point, relPoint=p.relPoint or p.point, x=p.x, y=p.y}
                EABR.UpdateUnlockPosForGrowDir(db.profile.display.growDirection)
            end,
            clearPos = function()
                db.profile.unlockPos = nil
            end,
            applyPos = function()
                ApplyUnlockPos()
            end,
        }),
    })
end

I.ApplyUnlockPos, I.RegisterUnlockElements = ApplyUnlockPos, RegisterUnlockElements
I.broken = false
