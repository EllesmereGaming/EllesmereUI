if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_ResourceBars_Anchors.lua
--
--  The player resource stack rects, the Unlock Mode registration and the
--  anchor system: anchor frames, bar anchoring and free positions.
--  Reads the earlier Resource Bars files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- EllesmereUIResourceBars.lua or an earlier Resource Bars file failed to load.
if not I or I.broken then return end
I.broken = true

local PP = EllesmereUI.PP
local floor = math.floor

local ERB, SnapXY, IsPowerBarHidden = I.ERB, I.SnapXY, I.IsPowerBarHidden
local IsSpecDisabled, IsVerticalOrientation = I.IsSpecDisabled, I.IsVerticalOrientation
local OrientedSize = I.OrientedSize

local mainFrame
I.mainFrameSetters[#I.mainFrameSetters + 1] = function(v) mainFrame = v end
local healthBar
I.healthBarSetters[#I.healthBarSetters + 1] = function(v) healthBar = v end
local primaryBar
I.primaryBarSetters[#I.primaryBarSetters + 1] = function(v) primaryBar = v end
local secondaryFrame
I.secondaryFrameSetters[#I.secondaryFrameSetters + 1] = function(v) secondaryFrame = v end
local secondaryBar
I.secondaryBarSetters[#I.secondaryBarSetters + 1] = function(v) secondaryBar = v end
local castBarFrame
I.castBarFrameSetters[#I.castBarFrameSetters + 1] = function(v) castBarFrame = v end
local gcdBarFrame
I.gcdBarFrameSetters[#I.gcdBarFrameSetters + 1] = function(v) gcdBarFrame = v end
local totemBarFrame
I.totemBarFrameSetters[#I.totemBarFrameSetters + 1] = function(v) totemBarFrame = v end
local cachedSecondary
I.cachedSecondarySetters[#I.cachedSecondarySetters + 1] = function(v) cachedSecondary = v end

local RefreshAnchoredBarsForUnlockTarget

-- Per-bar rects of the player's resource stack for the current spec and form, in
-- physical pixels: one { l, r, t, b } entry per bar in the layout, or nil when there
-- is none. A bar counts by its layout predicate (Power: not IsPowerBarHidden; Class
-- Resource: the structural part of UpdateVisibility, without the transient
-- ShouldShowBar; the Forever shapeshift mana bar: ns._FDMStackBottomFrame, its host
-- only while shown for the form) and by not being hidden, never by its alpha: the
-- combat/target/group visibility modes only fade a bar that keeps its place, so the
-- footprint holds still through them. The unused class resource container is hidden
-- and keeps its old rect, so it never counts. The unit frame auras walk the chain of
-- these bars docked under the player frame (EUI_UnitFrames_AuraContainers.lua,
-- ResourceStackBelowFrame), so a bar placed elsewhere is never reserved.
function EllesmereUI.ERB_PlayerStackBars()
    local p = ERB and ERB.db and ERB.db.profile
    if not p then return nil end
    local bars, n = nil, 0
    local function add(f)
        if not (f and f:IsShown()) then return end
        local fb, ft = f:GetBottom(), f:GetTop()
        if not (fb and ft) then return end
        local s = f:GetEffectiveScale() or 1
        bars = bars or {}
        n = n + 1
        bars[n] = { l = (f:GetLeft() or 0) * s, r = (f:GetRight() or 0) * s,
                    t = ft * s, b = fb * s }
    end
    if not IsPowerBarHidden() then add(primaryBar) end
    local sp = p.secondary
    if sp and sp.enabled ~= false and not IsSpecDisabled(sp)
        and not _G._ERB_BarHiddenByForm(sp) and cachedSecondary then
        add(secondaryFrame)
        add(secondaryBar)
    end
    if ns._FDMStackBottomFrame then add(ns._FDMStackBottomFrame()) end
    return bars
end

-- Unlock mode: register with shared EllesmereUI unlock system
local function RegisterUnlockElements()
    if not EllesmereUI or not EllesmereUI.RegisterUnlockElements then return end
    local MK = EllesmereUI.MakeUnlockElement

    -- Shared helper: save position to a settings sub-table and apply to frame
    local function MakePosHelpers(getSettings, frame_fn, defaultOffX, defaultOffY)
        local function savePos(key, point, relPoint, x, y)
            if not point then return end
            local s = getSettings()
            s.unlockPos = { point = point, relPoint = relPoint or point, x = x, y = y }
            if not EllesmereUI._unlockActive then
                local f = frame_fn()
                if f then
                    f:ClearAllPoints()
                    f:SetPoint(point, UIParent, relPoint or point, x, y)
                end
            end
            ns.ERB_GroupDirty()
        end
        local function loadPos()
            local pos = getSettings().unlockPos
            if not pos then return nil end
            local pt = pos.point
            return { point = pt, relPoint = pos.relPoint or pt, x = pos.x, y = pos.y }
        end
        local function clearPos()
            local s = getSettings()
            s.unlockPos = nil
            if defaultOffX then s.offsetX = defaultOffX end
            if defaultOffY then s.offsetY = defaultOffY end
        end
        local function applyPos()
            ns.ERB_GroupDirty()
            local s = getSettings()
            if s.anchorTo and s.anchorTo ~= "none" then return end
            local pos = s.unlockPos
            if not pos then return end
            local f = frame_fn()
            if f then
                local pt = pos.point
                local px, py = pos.x, pos.y
                local PPa = EllesmereUI and EllesmereUI.PP
                if PPa and px and py then
                    local es = f:GetEffectiveScale()
                    -- CENTER anchor with stored CENTER offsets: SnapCenterForDim with
                    -- the frame's actual size gives odd-pixel-dim frames the +0.5
                    -- center offset that lands edges on whole pixels. Plain SnapForES
                    -- forces edges to half pixels, drifting 1px on save/exit or spec swap.
                    local isCenterAnchor = (pt == "CENTER")
                        and (pos.relPoint == "CENTER" or pos.relPoint == nil)
                    if isCenterAnchor and PPa.SnapCenterForDim then
                        px = PPa.SnapCenterForDim(px, f:GetWidth() or 0, es)
                        py = PPa.SnapCenterForDim(py, f:GetHeight() or 0, es)
                    elseif PPa.SnapForES then
                        px = PPa.SnapForES(px, es)
                        py = PPa.SnapForES(py, es)
                    end
                end
                f:ClearAllPoints()
                f:SetPoint(pt, UIParent, pos.relPoint or pt, px, py)
            end
        end
        return savePos, loadPos, clearPos, applyPos
    end

    local function Rebuild() ERB:ApplyAll() end
    -- A size from a width/height match or the mover: the unlock system's settle
    -- pass hands every matched bar its size again after each resize burst (CDM
    -- bars resize all through combat), and a rebuild is a full ApplyAll, so an
    -- unchanged size rebuilds nothing.
    local function SetDim(t, key, v)
        if t[key] == v then return end
        t[key] = v
        Rebuild()
    end
    local function LiveMove(key)
        if RefreshAnchoredBarsForUnlockTarget then RefreshAnchoredBarsForUnlockTarget(key) end
        -- A bar moved on its own: the "Border Around All" group re-judges.
        ns.ERB_GroupDirty()
    end

    local elements = {}

    -- Health Bar
    do
        local function S() return ERB.db.profile.health end
		-- Size callbacks use the spec-resolved config so matching lands where the
        -- bar renders; position always stays on S() (global).
        local function SS() return _G._ERB_ResolveHealthCfg() or S() end
        local save, load, clear, apply = MakePosHelpers(S, function() return healthBar end, 0, -65)
        elements[#elements + 1] = MK({
            key = "ERB_Health", label = "Health Bar", group = "Resource Bars", order = 500,
            getFrame = function() return healthBar end,
            isHidden = function() local s = S(); return not s.enabled or IsSpecDisabled(s) end,
            -- Reported through the ON-SCREEN axes, not the stored ones: a vertical
            -- bar renders through OrientedSize, so stored width is what the player
            -- sees as height; handing the mover the raw stored pair would make it
            -- act on a bar that is still horizontal.
            getSize  = function()
                local s, g = SS(), ERB.db.profile.general
                return OrientedSize(s.width, s.height,
                    s.orientation or (g and g.orientation) or "HORIZONTAL")
            end,
            -- Stock styles: the frame drawn outside the fill (Classic WoW UI's
            -- vanilla frame, Blizzard Style's panel rim), so size matches line
            -- up with the frame on screen. Under the EllesmereUI look: a textured
            -- border's reach outside the bar (ns.ERB_EuiBorderPad), else nil.
            getMatchPad = function()
                local style = ns.ERB_BarsStyle()
                if style == "eui" then
                    local pw, ph = ns.ERB_EuiBorderPad(SS())
                    if pw then return pw, ph end
                end
                if style == "eui" then return nil end
                local s, g = SS(), ERB.db.profile.general
                local ori = s.orientation or (g and g.orientation) or "HORIZONTAL"
                if style == "blizzard" then return ns.ERB_BlizzMatchPad(IsVerticalOrientation(ori)) end
                local w, h = OrientedSize(s.width, s.height, ori)
                return ns.ERB_ClassicMatchPad(w, h, IsVerticalOrientation(ori), ns.ERB_BarFrameK(s))
            end,
            setWidth = function(_, w)
                local s, g = SS(), ERB.db.profile.general
                if IsVerticalOrientation(s.orientation or (g and g.orientation)) then
                    SetDim(s, "height", PP.Snap(w))
                else
                    SetDim(s, "width", PP.Snap(w))
                end
            end,
            setHeight = function(_, h)
                local s, g = SS(), ERB.db.profile.general
                if IsVerticalOrientation(s.orientation or (g and g.orientation)) then
                    SetDim(s, "width", PP.Snap(h))
                else
                    SetDim(s, "height", PP.Snap(h))
                end
            end,
            isAnchored = function() local s = S(); return s.anchorTo and s.anchorTo ~= "none" end,
            keepMoverWhenAnchored = true,
            onLiveMove = LiveMove,
            savePos = save, loadPos = load, clearPos = clear, applyPos = apply,
        })
    end

    -- Power Bar
    do
        local function S() return ERB.db.profile.primary end
        local function SS() return _G._ERB_ResolvePowerCfg() or S() end
        local save, load, clear, apply = MakePosHelpers(S, function() return primaryBar end, 0, -74)
        elements[#elements + 1] = MK({
            key = "ERB_Power", label = "Power Bar", group = "Resource Bars", order = 501,
            getFrame = function() return primaryBar end,
            isHidden = function() local s = S(); return s.enabled == false or IsSpecDisabled(s) end,
            -- On-screen axes, as with the health bar above.
            getSize  = function()
                local s, g = SS(), ERB.db.profile.general
                return OrientedSize(s.width or 214, s.height or 14,
                    s.orientation or (g and g.orientation) or "HORIZONTAL")
            end,
            -- Stock styles: the frame outside the fill (see the health bar).
            getMatchPad = function()
                local style = ns.ERB_BarsStyle()
                if style == "eui" then
                    local pw, ph = ns.ERB_EuiBorderPad(SS())
                    if pw then return pw, ph end
                end
                if style == "eui" then return nil end
                local s, g = SS(), ERB.db.profile.general
                local ori = s.orientation or (g and g.orientation) or "HORIZONTAL"
                if style == "blizzard" then return ns.ERB_BlizzMatchPad(IsVerticalOrientation(ori)) end
                local w, h = OrientedSize(s.width or 214, s.height or 14, ori)
                return ns.ERB_ClassicMatchPad(w, h, IsVerticalOrientation(ori), ns.ERB_BarFrameK(s))
            end,
            -- WoW Forever druid: the mover wraps the Mana Bar while Shapeshifted
            -- shown below the bar (EUI_ResourceBars_ForeverDruidMana.lua); nil
            -- on every other client and class.
            getBottomExtra = ns.FDM_BottomExtra,
            setWidth = function(_, w)
                local s, g = SS(), ERB.db.profile.general
                if IsVerticalOrientation(s.orientation or (g and g.orientation)) then
                    SetDim(s, "height", PP.Snap(w))
                else
                    SetDim(s, "width", PP.Snap(w))
                end
            end,
            setHeight = function(_, h)
                local s, g = SS(), ERB.db.profile.general
                if IsVerticalOrientation(s.orientation or (g and g.orientation)) then
                    SetDim(s, "width", PP.Snap(h))
                else
                    SetDim(s, "height", PP.Snap(h))
                end
            end,
            isAnchored = function() local s = S(); return s.anchorTo and s.anchorTo ~= "none" end,
            keepMoverWhenAnchored = true,
            onLiveMove = LiveMove,
            savePos = save, loadPos = load, clearPos = clear, applyPos = apply,
        })
    end

    -- Class Resource (pips/runes)
    do
        local function S() return ERB.db.profile.secondary end
        local function SS() return _G._ERB_ResolveSecondaryCfg() or S() end
        local save, load, clear, apply = MakePosHelpers(S, function() return secondaryFrame end, 0, -38)
        elements[#elements + 1] = MK({
            key = "ERB_ClassResource", label = "Class Resource", group = "Resource Bars", order = 502,
            getFrame = function() return secondaryFrame end,
            -- On-screen axes. This bar's OWN orientation key (pipOrientation, no
            -- fallback to general) treats anything not HORIZONTAL as vertical in
            -- its renderer -- mirrored here so the mover and W/H match what is drawn.
            getSize  = function()
                local s = SS()
                return OrientedSize(s.pipWidth, s.pipHeight,
                    (s.pipOrientation or "HORIZONTAL") ~= "HORIZONTAL" and "VERTICAL_UP" or "HORIZONTAL")
            end,
            -- Stock styles: the frame outside the row (see the health bar).
            getMatchPad = function()
                local style = ns.ERB_BarsStyle()
                if style == "eui" then
                    local pw, ph = ns.ERB_EuiBorderPad(SS())
                    if pw then return pw, ph end
                end
                if style == "eui" then return nil end
                local s = SS()
                local vertical = (s.pipOrientation or "HORIZONTAL") ~= "HORIZONTAL"
                if style == "blizzard" then return ns.ERB_BlizzMatchPad(vertical) end
                local w, h = OrientedSize(s.pipWidth, s.pipHeight, vertical and "VERTICAL_UP" or "HORIZONTAL")
                return ns.ERB_ClassicMatchPad(w, h, vertical, ns.ERB_BarFrameK(s))
            end,
            setWidth = function(_, w)
                local s = SS()
                if (s.pipOrientation or "HORIZONTAL") ~= "HORIZONTAL" then
                    SetDim(s, "pipHeight", PP.Snap(w))
                else
                    SetDim(s, "pipWidth", PP.Snap(w))
                end
            end,
            setHeight = function(_, h)
                local s = SS()
                if (s.pipOrientation or "HORIZONTAL") ~= "HORIZONTAL" then
                    SetDim(s, "pipWidth", PP.Snap(h))
                else
                    SetDim(s, "pipHeight", PP.Snap(h))
                end
            end,
            isHidden = function() local s = S(); return s.enabled == false or IsSpecDisabled(s) end,
            isAnchored = function() local s = S(); return s.anchorTo and s.anchorTo ~= "none" end,
            keepMoverWhenAnchored = true,
            onLiveMove = LiveMove,
            savePos = save, loadPos = load, clearPos = clear, applyPos = apply,
        })
    end

    -- Cast Bar
    do
        local function S() return ERB.db.profile.castBar end
        local function castSave(key, point, relPoint, x, y)
            if not point then return end
            local cb = S()
            cb.unlockPos = { point = point, relPoint = relPoint or point, x = x, y = y }
            if not EllesmereUI._unlockActive and castBarFrame then
                castBarFrame:ClearAllPoints()
                castBarFrame:SetPoint(point, UIParent, relPoint or point, x, y)
            end
        end
        local function castLoad()
            local pos = S().unlockPos
            if not pos then return nil end
            local pt = pos.point
            return { point = pt, relPoint = pos.relPoint or pt, x = pos.x, y = pos.y }
        end
        local function castClear()
            local cb = S()
            cb.unlockPos = nil
            cb.anchorX = 0; cb.anchorY = -54
        end
        local function castApply()
            local pos = S().unlockPos
            if not pos then return end
            if castBarFrame then
                local pt = pos.point
                local sx, sy = SnapXY(pos.x, pos.y, castBarFrame, pos)
                castBarFrame:ClearAllPoints()
                castBarFrame:SetPoint(pt, UIParent, pos.relPoint or pt, sx, sy)
            end
        end
        elements[#elements + 1] = MK({
            key = "ERB_CastBar", label = "Cast Bar", group = "Resource Bars", order = 504,
            noAnchorTarget = true,
            getFrame = function() return castBarFrame end,
            getSize  = function()
                local cb = S()
                return cb.width + ns.ERB_CastIconW(cb), cb.height
            end,
            -- Stock styles: the frame outside the bar. Classic WoW UI: the
            -- vanilla frame, icon included (it wraps bar and icon together).
            -- Blizzard Style: the stock frame 2px round the fill (on the
            -- icon's side it lands on the icon); the text box below is a
            -- label, not the frame (the mover wraps it through getBottomExtra).
            -- EllesmereUI look: the textured border round bar and icon.
            getMatchPad = function()
                local cs = ns.ERB_CastStyle()
                if cs == "classic" then
                    return ns.ERB_ClassicMatchPad(0, 0, false, ns.ERB_ClassicFrameK(S()))
                end
                if cs == "blizzard" and ns.ERB_BlizzAtlas("frame") then
                    return (ns.ERB_CastIconW(S()) > 0) and 2 or 4, 4
                end
                if cs == "eui" then return ns.ERB_EuiBorderPad(S()) end
                return nil
            end,
            -- Blizzard Style: the stock text box (and the icon spanning it)
            -- hang 13px below the bar; the mover wraps them. Classic WoW UI
            -- has no text box.
            getBottomExtra = function()
                local cb = S()
                if ns.ERB_CastStyle() == "blizzard" and cb.showSpellText and ns.ERB_BlizzAtlas("textbox") then return 13 end
                return 0
            end,
            setWidth = function(_, w)
                local cb = S()
                SetDim(cb, "width", PP.Snap(math.max(w - ns.ERB_CastIconW(cb), 10)))
            end,
            setHeight = function(_, h) SetDim(S(), "height", PP.Snap(h)) end,
            savePos = castSave, loadPos = castLoad, clearPos = castClear, applyPos = castApply,
        })
    end

    -- GCD Bar
    do
        local function S() return ERB.db.profile.gcdBar end
        local function gcdSave(key, point, relPoint, x, y)
            if not point then return end
            local g = S()
            g.unlockPos = { point = point, relPoint = relPoint or point, x = x, y = y }
            if not EllesmereUI._unlockActive and gcdBarFrame then
                gcdBarFrame:ClearAllPoints()
                gcdBarFrame:SetPoint(point, UIParent, relPoint or point, x, y)
            end
        end
        local function gcdLoad()
            local pos = S().unlockPos
            if not pos then return nil end
            local pt = pos.point
            return { point = pt, relPoint = pos.relPoint or pt, x = pos.x, y = pos.y }
        end
        local function gcdClear()
            local g = S()
            g.unlockPos = nil
            g.anchorX = 0; g.anchorY = -78
        end
        local function gcdApply()
            local pos = S().unlockPos
            if not pos then return end
            if gcdBarFrame then
                local pt = pos.point
                local sx, sy = SnapXY(pos.x, pos.y, gcdBarFrame, pos)
                gcdBarFrame:ClearAllPoints()
                gcdBarFrame:SetPoint(pt, UIParent, pos.relPoint or pt, sx, sy)
            end
        end
        elements[#elements + 1] = MK({
            key = "ERB_GCDBar", label = "GCD Bar", group = "Resource Bars", order = 506,
            noAnchorTarget = true,
            getFrame = function() return gcdBarFrame end,
            getSize  = function()
                local g = S()
                return OrientedSize(g.width, g.height, g.orientation or "HORIZONTAL")
            end,
            -- The textured border's reach outside the bar (every look draws it).
            getMatchPad = function() return ns.ERB_EuiBorderPad(S()) end,
            setWidth = function(_, w)
                local g = S()
                if IsVerticalOrientation(g.orientation) then
                    SetDim(g, "height", PP.Snap(math.max(w, 4)))
                else
                    SetDim(g, "width", PP.Snap(math.max(w, 10)))
                end
            end,
            setHeight = function(_, h)
                local g = S()
                if IsVerticalOrientation(g.orientation) then
                    SetDim(g, "width", PP.Snap(math.max(h, 10)))
                else
                    SetDim(g, "height", PP.Snap(math.max(h, 4)))
                end
            end,
            savePos = gcdSave, loadPos = gcdLoad, clearPos = gcdClear, applyPos = gcdApply,
        })
    end

    -- Totem Bar
    do
        local function S() return ERB.db.profile.totemBar end
        local function totemSave(key, point, relPoint, x, y)
            if not point then return end
            local tb = S()
            tb.unlockPos = { point = point, relPoint = relPoint or point, x = x, y = y }
            if not EllesmereUI._unlockActive and totemBarFrame then
                totemBarFrame:ClearAllPoints()
                totemBarFrame:SetPoint(point, UIParent, relPoint or point, x, y)
            end
        end
        local function totemLoad()
            local pos = S().unlockPos
            if not pos then return nil end
            local pt = pos.point
            return { point = pt, relPoint = pos.relPoint or pt, x = pos.x, y = pos.y }
        end
        local function totemClear()
            S().unlockPos = nil
        end
        local function totemApply()
            local pos = S().unlockPos
            if not pos then return end
            if totemBarFrame then
                local pt = pos.point
                local sx, sy = SnapXY(pos.x, pos.y, totemBarFrame, pos)
                totemBarFrame:ClearAllPoints()
                totemBarFrame:SetPoint(pt, UIParent, pos.relPoint or pt, sx, sy)
            end
        end
        elements[#elements + 1] = MK({
            key = "ERB_TotemBar", label = "Totem Bar", group = "Resource Bars", order = 505,
            noResize = true,
            noAnchorTarget = true,
            getFrame = function() return totemBarFrame end,
            getSize  = function()
                local tb = S()
                local iconSz = tb.iconSize or 30
                local spacing = tb.spacing or 2
                -- Estimate extent based on max 5 totems; swap W/H when vertical
                local maxDim = iconSz * 5 + spacing * 4
                if tb.orientation == "VERTICAL" then
                    return iconSz, maxDim
                end
                return maxDim, iconSz
            end,
            savePos = totemSave, loadPos = totemLoad, clearPos = totemClear, applyPos = totemApply,
        })
    end

    -- Arcane Soul (Sunfury Arcane Mage): returns nil for every other class, so
    -- the mover only exists where the feature can.
    if ns.AS_MakeUnlockElement then
        elements[#elements + 1] = ns.AS_MakeUnlockElement(MK)
    end
    -- Swing Timer (WoW Forever): returns nil on clients without C_SwingTimer.
    if ns.ST_MakeUnlockElement then
        elements[#elements + 1] = ns.ST_MakeUnlockElement(MK, Rebuild)
    end
    -- Call Totem Bar (WoW Forever): nil elsewhere.
    if ns.CT_MakeUnlockElement then
        elements[#elements + 1] = ns.CT_MakeUnlockElement(MK)
    end

    EllesmereUI:RegisterUnlockElements(elements, "EllesmereUIResourceBars")
end

_G._ERB_RegisterUnlock = RegisterUnlockElements

-- Anchor resolution helper: returns the target frame for an anchorTo key, or nil.
local ERB_ANCHOR_FRAMES = {
    erb_classresource = function() return secondaryFrame end,
    erb_powerbar      = function() return primaryBar end,
    erb_health        = function() return healthBar end,
    erb_castbar       = function() return castBarFrame end,
    erb_gcdbar        = function() return gcdBarFrame end,
    erb_cdm           = function() return _G._ECME_GetBarFrame and _G._ECME_GetBarFrame("cooldowns") end,
    mouse             = nil,  -- handled separately
    partyframe        = nil,  -- handled separately
    playerframe       = nil,  -- handled separately
}

local ERB_VALID_ANCHORS = EllesmereUI.RESOURCE_BAR_ANCHOR_KEYS

local function ResolveAnchorFrame(anchorKey)
    local fn = ERB_ANCHOR_FRAMES[anchorKey]
    if fn then return fn() end
    return nil
end

local function NormalizeAnchorKey(anchorKey)
    if anchorKey and ERB_VALID_ANCHORS[anchorKey] then
        return anchorKey
    end
    return "none"
end

-- Vertical "effective Y" of a bar from STORED config (screen up = +y). Needed
-- because a spec with no class resource never lays that frame out, so live
-- bounds (GetTop/GetCenter) are unavailable. Dragged bars store unlockPos as
-- CENTER/CENTER; free bars use offsetY relative to the centered mainFrame --
-- both CENTER-relative, so comparable.
local function BarEffectiveY(cfg)
    if cfg and cfg.unlockPos and cfg.unlockPos.point and cfg.unlockPos.y then
        return cfg.unlockPos.y
    end
    return (cfg and cfg.offsetY) or 0
end

-- "Expand Power Bar if No Resource" direction: the power bar fills the area the
-- absent class resource would occupy, growing TOWARD it. +1 = class resource
-- ABOVE -> grow up; -1 = below -> grow down. Pure read of stored config (no
-- writes, no live bounds), resolved even when the class resource is disabled so
-- expanding into a toggled-off/spec-disabled one grows the right way. Falls back
-- to +1 (default layout has it above) with no config or when co-located.
local function ResolveExpandDirSign(pp, sp)
    if not sp then return 1 end
    -- Anchored: class resource pinned relative to the power bar.
    if NormalizeAnchorKey(sp.anchorTo) == "erb_powerbar" then
        if sp.anchorPosition == "bottom" then return -1 end
        if sp.anchorPosition == "top" then return 1 end
    end
    -- Anchored the other way: power bar pinned relative to the class resource.
    if NormalizeAnchorKey(pp.anchorTo) == "erb_classresource" then
        if pp.anchorPosition == "top" then return -1 end     -- power above CR -> CR below -> grow down
        if pp.anchorPosition == "bottom" then return 1 end   -- power below CR -> CR above -> grow up
    end
    -- Free / dragged: compare stored vertical positions.
    local sy, py = BarEffectiveY(sp), BarEffectiveY(pp)
    if sy > py then return 1 elseif sy < py then return -1 end
    return 1
end

-- ApplyBarAnchor args: frame to position; anchorKey = anchorTo value; anchorPos
-- "left"/"right"/"top"/"bottom"; offsetX/offsetY extra offsets; growthDir
-- "UP"/"DOWN"/"LEFT"/"RIGHT" from the anchor edge; growCentered true = centered
-- on the anchor edge midpoint, false = corner there.
-- SetFrameClickThrough recursively sets mouse passthrough on a frame and its
-- children, storing original state on first call so it can be restored.
local function SetFrameClickThrough(frame, clickThrough)
    if not frame then return end
    if clickThrough then
        -- Store original state if not already stored
        if frame._erbMouseWas == nil then
            frame._erbMouseWas = frame:IsMouseEnabled()
        end
        frame:EnableMouse(false)
        if frame.EnableMouseClicks then frame:EnableMouseClicks(false) end
        if frame.EnableMouseMotion then frame:EnableMouseMotion(false) end
    else
        -- Restore original state
        if frame._erbMouseWas ~= nil then
            frame:EnableMouse(frame._erbMouseWas)
            frame._erbMouseWas = nil
        end
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        SetFrameClickThrough(child, clickThrough)
    end
end

local function ApplyBarAnchor(frame, anchorKey, anchorPos, offsetX, offsetY, growthDir, growCentered)
    -- Always clear any previous mouse-tracking OnUpdate
    if frame._erbMouseTrack then
        frame:SetScript("OnUpdate", nil)
        if frame._erbMouseShell then
            frame._erbMouseShell:SetScript("OnUpdate", nil)
            frame._erbMouseShell:Hide()
        end
        frame._erbMouseTrack = nil
        local g = ERB.db and ERB.db.profile and ERB.db.profile.general
        frame:SetFrameStrata(g and g.frameStrata or "MEDIUM")
        frame:SetFrameLevel(5)
        -- Restore mouse on frame and all children
        SetFrameClickThrough(frame, false)
        if frame.EnableMouseMotion then frame:EnableMouseMotion(true) end
    end

    if not anchorKey or anchorKey == "none" then return false end
    offsetX = offsetX or 0
    offsetY = offsetY or 0
    -- Snap offsets to physical pixel grid
    local PPa = EllesmereUI and EllesmereUI.PP
    if PPa and PPa.SnapForES then
        local es = frame:GetEffectiveScale()
        offsetX = PPa.SnapForES(offsetX, es)
        offsetY = PPa.SnapForES(offsetY, es)
    end
    anchorPos = anchorPos or "left"
    growthDir = growthDir or "UP"
    local centered = (growCentered ~= false)

    local function GetAnchorPoints()
        if anchorPos == "left" then
            return "RIGHT", "LEFT"
        elseif anchorPos == "right" then
            return "LEFT", "RIGHT"
        elseif anchorPos == "top" then
            return "BOTTOM", "TOP"
        elseif anchorPos == "bottom" then
            return "TOP", "BOTTOM"
        end
        return "LEFT", "RIGHT"
    end

    if anchorKey == "mouse" then
        -- Determine SetPoint anchor and directional nudge based on anchorPos
        local pointFrom, baseOX, baseOY
        if anchorPos == "left" then
            pointFrom = "RIGHT"; baseOX = -15 + offsetX; baseOY = offsetY
        elseif anchorPos == "right" then
            pointFrom = "LEFT"; baseOX = 15 + offsetX; baseOY = offsetY
        elseif anchorPos == "top" then
            pointFrom = "BOTTOM"; baseOX = offsetX; baseOY = 15 + offsetY
        elseif anchorPos == "bottom" then
            pointFrom = "TOP"; baseOX = offsetX; baseOY = -15 + offsetY
        else
            pointFrom = "LEFT"; baseOX = 15 + offsetX; baseOY = offsetY
        end
        frame:SetFrameStrata("TOOLTIP")
        frame:SetFrameLevel(9980)
        frame:ClearAllPoints()
        frame:SetPoint(pointFrom, UIParent, "BOTTOMLEFT", 0, 0)
        frame._erbMouseTrack = true
        -- Make frame and all children fully click-through while following cursor
        SetFrameClickThrough(frame, true)
        local lastMX, lastMY
        -- Cursor-follow runs per RENDER FRAME on a pool shell (bills ResourceBars via
        -- frame-birth attribution): a 60Hz anim ticker visibly steps against a gliding
        -- cursor since position has no engine easing. Kept cheap: raw-pixel early-out
        -- on unmoved frames, in-place SetPoint on moves.
        if not frame._erbMouseShell then frame._erbMouseShell = ns.TakeShell() end
        frame._erbMouseShell:Show()
        frame._erbMouseShell:SetScript("OnUpdate", function()
            local cx, cy = GetCursorPosition()
            if cx ~= lastMX or cy ~= lastMY then
                local firstMove = lastMX == nil
                lastMX, lastMY = cx, cy
                local s = UIParent:GetEffectiveScale()
                if firstMove then frame:ClearAllPoints() end
                frame:SetPoint(pointFrom, UIParent, "BOTTOMLEFT",
                    floor(cx / s + 0.5) + baseOX, floor(cy / s + 0.5) + baseOY)
            end
        end)
        return true
    elseif anchorKey == "partyframe" then
        local partyFrame = EllesmereUI.FindPlayerPartyFrame()
        if not partyFrame then return false end
        local framePoint, targetPoint = GetAnchorPoints()
        frame:ClearAllPoints()
        frame:SetPoint(framePoint, partyFrame, targetPoint, offsetX, offsetY)
        return true
    elseif anchorKey == "playerframe" then
        local playerFrame = EllesmereUI.FindPlayerUnitFrame()
        if not playerFrame then return false end
        local framePoint, targetPoint = GetAnchorPoints()
        frame:ClearAllPoints()
        frame:SetPoint(framePoint, playerFrame, targetPoint, offsetX, offsetY)
        return true
    end

    local targetFrame = ResolveAnchorFrame(anchorKey)
    if not targetFrame or not targetFrame:IsShown() then return false end

    frame:ClearAllPoints()
    local framePoint, targetPoint = GetAnchorPoints()
    local ok
    ok = pcall(frame.SetPoint, frame, framePoint, targetFrame, targetPoint, offsetX, offsetY)
    return ok or false
end

local UNLOCK_TARGET_TO_ERB_ANCHOR = {
    ERB_Health = "erb_health",
    ERB_Power = "erb_powerbar",
    ERB_ClassResource = "erb_classresource",
    ERB_CastBar = "erb_castbar",
    ERB_GCDBar = "erb_gcdbar",
}

local function GetAnchorOffsets(settings)
    if not settings then return 0, 0 end
    local offsetX = settings.anchorOffsetX
    if offsetX == nil then offsetX = settings.anchorX end
    local offsetY = settings.anchorOffsetY
    if offsetY == nil then offsetY = settings.anchorY end
    return offsetX or 0, offsetY or 0
end

local function ApplyFreeBarPosition(frame, settings, defaultX, defaultY, width, height)
    if not frame then return end

    local pos = settings and settings.unlockPos
    frame:SetSize(width, height)
    frame:ClearAllPoints()

    if pos and pos.point then
        local sx, sy = SnapXY(pos.x, pos.y, frame, pos)
        frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, sx, sy)
        return
    end

    frame:SetPoint("CENTER", mainFrame, "CENTER", settings.offsetX or defaultX or 0, settings.offsetY or defaultY or 0)
end

local function ReapplyInternalBarAnchors()
    if not (ERB and ERB.db and ERB.db.profile) then return end

    local p = ERB.db.profile
    local anchoredBars = {
        { frame = healthBar, settings = p.health },
        { frame = primaryBar, settings = p.primary },
        { frame = secondaryFrame, settings = p.secondary },
    }

    for _ = 1, 2 do
        for _, info in ipairs(anchoredBars) do
            local frame = info.frame
            local settings = info.settings
            local anchorKey = settings and settings.anchorTo
            if frame and settings and frame:IsShown()
                and anchorKey and anchorKey ~= "none"
                and ERB_ANCHOR_FRAMES[anchorKey]
            then
                local offsetX, offsetY = GetAnchorOffsets(settings)
                ApplyBarAnchor(frame, anchorKey, settings.anchorPosition, offsetX, offsetY, settings.growthDirection, settings.growCentered)
            end
        end
    end
end

RefreshAnchoredBarsForUnlockTarget = function(unlockKey)
    local targetAnchor = UNLOCK_TARGET_TO_ERB_ANCHOR[unlockKey]
    if not (targetAnchor and ERB and ERB.db and ERB.db.profile) then return end

    local p = ERB.db.profile
    local bars = {
        { frame = healthBar, settings = p.health },
        { frame = primaryBar, settings = p.primary },
        { frame = secondaryFrame, settings = p.secondary },
    }

    for _ = 1, 2 do
        for _, info in ipairs(bars) do
            local frame = info.frame
            local settings = info.settings
            if frame and settings and frame:IsShown()
                and settings.anchorTo == targetAnchor
            then
                local offsetX, offsetY = GetAnchorOffsets(settings)
                ApplyBarAnchor(frame, settings.anchorTo, settings.anchorPosition, offsetX, offsetY, settings.growthDirection, settings.growCentered)
            end
        end
    end
end

I.ApplyBarAnchor, I.ApplyFreeBarPosition = ApplyBarAnchor, ApplyFreeBarPosition
I.GetAnchorOffsets, I.NormalizeAnchorKey = GetAnchorOffsets, NormalizeAnchorKey
I.ReapplyInternalBarAnchors = ReapplyInternalBarAnchors
I.RegisterUnlockElements, I.ResolveExpandDirSign = RegisterUnlockElements, ResolveExpandDirSign
I.broken = false
