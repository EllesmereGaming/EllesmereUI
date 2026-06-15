local addon, ns = ...

if not ns then return end

-- Casts In Front of Nameplates (castOverlayEnabled, default off).
--
-- The on-plate cast bar IS the overlay: while the setting is on, each
-- plate's cast bar frame is reparented into a small per-plate lift
-- container under UIParent at HIGH strata. Nameplates composite as
-- whole units, so no strata on a plate child can escape its own plate
-- (live-verified: a HIGH cast bar still renders under neighboring
-- MEDIUM plates); leaving the plate's render tree is the only way out.
-- The bar keeps its anchor (TOPLEFT -> plate.health), and cross-parent
-- anchors track the plate's screen position with no per-frame code.
-- Every cast element (fill, name/target/timer text, spell icon, shield,
-- spark, kick tick, important-cast glow) is a child of the bar, so the
-- lifted bar matches the on-plate bar 1:1 by construction -- there is
-- no copy to keep in sync.
--
-- Scale: the lift container uses SetIgnoreParentScale(true) and is
-- pinned to the plate's effective scale, so the bar renders at exactly
-- its on-plate size. Re-synced from ApplyScale (target/cast scale
-- changes) and ApplyAppearance (settings passes); nameplate distance
-- scaling is pinned by CVar (nameplateMinScale/MaxScale = 1).
--
-- Visibility: the bar is shown/hidden purely by UpdateCast/ClearUnit,
-- which keep working unchanged; a hidden bar in the container renders
-- nothing between casts.
--
-- Cost: one frame per plate (lazy, only while enabled), one SetParent
-- per plate per settings flip, a scale compare per ApplyScale call. No
-- events, no textures, no per-cast or per-frame work, and nothing at
-- all while the setting is off.

local LIFT_STRATA = "HIGH"

local function Enabled()
    local prof = ns.db and ns.db.profile
    return prof ~= nil and prof.castOverlayEnabled == true
end

local function GetLift(plate)
    local lift = plate._castLift
    if not lift then
        lift = CreateFrame("Frame", nil, UIParent)
        lift:SetFrameStrata(LIFT_STRATA)
        lift:SetIgnoreParentScale(true)
        lift:SetSize(1, 1)
        lift:EnableMouse(false)
        if lift.EnableMouseMotion then lift:EnableMouseMotion(false) end
        plate._castLift = lift
    end
    return lift
end

-- Idempotent: applies the current setting to one plate. Wired into
-- NameplateFrame:ApplyAppearance (settings passes) and the tail of
-- NameplateFrame:ApplyScale (spawns, cast start/end, target swaps), so
-- fresh plates, settings changes, profile swaps, scale changes, and the
-- options toggle (via ns.RefreshAllSettings) all converge here; pooled
-- plates self-heal on their next spawn via the appearance generation
-- counter.
function ns.RefreshCastOverlay(plate)
    local cast = plate and plate.cast
    if not cast then return end
    if Enabled() then
        local lift = GetLift(plate)
        if cast:GetParent() ~= lift then
            cast:SetParent(lift)
            cast:SetFrameStrata(LIFT_STRATA)
            plate._castOverlayLifted = true
        end
        local s = plate:GetEffectiveScale()
        if plate._castLiftScale ~= s then
            plate._castLiftScale = s
            lift:SetScale(s)
        end
    elseif plate._castOverlayLifted then
        cast:SetParent(plate)
        cast:SetFrameStrata(plate:GetFrameStrata())
        plate._castOverlayLifted = nil
        plate._castLiftScale = nil
    end
end

-- Kill switch: hand every active plate's cast bar back to its plate
-- now, and bump the appearance generation so pooled (inactive) plates
-- restore on their next spawn.
function ns.ClearAllCastOverlays()
    for _, plate in pairs(ns.plates) do
        if plate._castOverlayLifted then
            plate.cast:SetParent(plate)
            plate.cast:SetFrameStrata(plate:GetFrameStrata())
            plate._castOverlayLifted = nil
            plate._castLiftScale = nil
        end
    end
    ns._npAppearanceGen = (ns._npAppearanceGen or 0) + 1
end
