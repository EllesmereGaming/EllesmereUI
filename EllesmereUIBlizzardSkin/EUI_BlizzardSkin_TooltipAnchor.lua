if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_BlizzardSkin_TooltipAnchor.lua
--
--  Where the default tooltip sits: the UberTooltips CVar, anchor to cursor,
--  the fixed position with its Unlock Mode mover, growth direction.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- EllesmereUIBlizzardSkin.lua or an earlier EUI_BlizzardSkin_*.lua file
-- failed to load.
if not I or I.last ~= "Dialogs" then return end

-------------------------------------------------------------------------------
--  UberTooltips CVar enforcement (only if user has manually set it in EUI)
-------------------------------------------------------------------------------
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        if not EllesmereUIDB then EllesmereUIDB = {} end
        if EllesmereUIDB.uberTooltipsManual then
            EllesmereUI.SetCVar("UberTooltips", EllesmereUIDB.uberTooltips and "1" or "0", "EllesmereUIBlizzardSkin")
        else
            EllesmereUI.SetCVar("UberTooltips", "1", "EllesmereUIBlizzardSkin")
        end
    end)
end

-------------------------------------------------------------------------------
--  Anchor Tooltip to Cursor
--  Re-owns the default GameTooltip to a 1x1 frame tracking the mouse, so the
--  tooltip follows the cursor at a user-chosen position + X/Y offset, via
--  GameTooltip_SetDefaultAnchor (the post-hook every default-anchored tooltip --
--  units, world objects, action buttons -- runs through). Installed on first
--  enable; a no-op (Blizzard's anchor stands) when toggled off, and the tracking frame only ticks while a tooltip is shown.
-------------------------------------------------------------------------------

-- Is a tooltip owner handed to us by a Blizzard hook safe to anchor to? It can
-- be a FORBIDDEN frame: Blizzard's nameplate aura buttons are forbidden and call
-- GameTooltip_SetDefaultAnchor on hover, so passing one straight to SetOwner from
-- our tainted hook raises "Attempt to access forbidden object from code tainted
-- by an AddOn". Testing the tooltip alone is NOT enough -- it is the OWNER that
-- is off limits, not GameTooltip itself. Nothing can be anchored to a forbidden
-- frame, so both anchor modes must leave Blizzard's anchoring alone there;
-- IsForbidden is the only method safe to call on such a frame, so it is asked
-- first and nothing else is touched. File scope on purpose: the cursor and fixed anchor modes (separate do-blocks) both need it.
local function TooltipOwnerUsable(parent)
    if not parent then return false end
    local fn = parent.IsForbidden
    if type(fn) == "function" and fn(parent) then return false end
    return true
end

-- Stand-in tooltips: taint-sensitive callers that cannot touch the global
-- GameTooltip build their own GameTooltipTemplate frame and flag it
-- LIKE_GLOBAL_GAMETOOLTIP -- the ecosystem convention asking to be treated
-- as _G.GameTooltip. They still route through GameTooltip_SetDefaultAnchor,
-- so honour the flag for the ANCHOR decision only. The armed-state
-- bookkeeping stays strict-identity: it gates SetPoint enforcement hooked
-- onto GameTooltip's OWN setters, so arming it for a stand-in would enforce
-- against another frame's state. A stand-in needs no ongoing enforcement:
-- GameTooltip_SetDefaultAnchor is a pure one-shot (SetOwner + corner
-- SetPoint, no registration), so nothing Blizzard-side ever re-anchors a
-- stand-in -- every re-build re-enters these hooks.
local function TooltipIsGlobalLike(tooltip)
    if tooltip == GameTooltip then return true end
    return type(tooltip) == "table" and tooltip.LIKE_GLOBAL_GAMETOOLTIP == true
end

do
    -- Selected position = where the tooltip sits relative to the cursor, so the tooltip corner touching the cursor is the opposite one.
    local POINT_FOR_POS = {
        bottomright = "TOPLEFT",
        bottomleft  = "TOPRIGHT",
        topright    = "BOTTOMLEFT",
        topleft     = "BOTTOMRIGHT",
        right       = "LEFT",
        left        = "RIGHT",
        top         = "BOTTOM",
        bottom      = "TOP",
        center      = "CENTER",
    }

    local cursorFrame
    local hooked = false

    local function EnsureCursorFrame()
        if cursorFrame then return cursorFrame end
        cursorFrame = CreateFrame("Frame", "EllesmereUI_TooltipCursorAnchor", UIParent)
        cursorFrame:SetSize(1, 1)
        cursorFrame:SetFrameStrata("TOOLTIP")
        cursorFrame:Hide()
        local lastX, lastY
        cursorFrame:SetScript("OnUpdate", function(self)
            local scale = UIParent:GetEffectiveScale()
            if scale <= 0 then return end
            local x, y = GetCursorPosition()
            if x ~= lastX or y ~= lastY then
                lastX, lastY = x, y
                self:ClearAllPoints()
                self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
            end
        end)
        return cursorFrame
    end

    -- Show + position the tracking frame at the pointer NOW: the OnUpdate alone only
    -- repositions it next frame, so a tooltip anchored to it and shown synchronously this frame (as the custom CDM frames do) would have no valid rect yet and render nothing.
    local function PositionCursorFrameNow(cf)
        cf:Show()
        local scale = UIParent:GetEffectiveScale()
        if scale > 0 then
            local x, y = GetCursorPosition()
            cf:ClearAllPoints()
            cf:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
        end
    end

    local function ApplyCursorAnchor(tooltip, parent)
        if not TooltipIsGlobalLike(tooltip) then return end
        -- Gated by the customTooltips master (matches the grayed-out option), so disabling the reskin restores the default tooltip position.
        if EllesmereUIDB and EllesmereUIDB.customTooltips == false then return end
        if not (EllesmereUIDB and EllesmereUIDB.tooltipAnchorCursor) then return end
        -- Owner checked as well as the tooltip: a forbidden owner cannot be passed to SetOwner below. See TooltipOwnerUsable.
        if not TooltipOwnerUsable(parent) or tooltip:IsForbidden() then return end
        -- "Show Tooltips" suppression parks the tip in a hidden host (EUI_BlizzardSkin_TooltipVisibility.lua): it stays alive and invisible so the peek modifier can reveal it, so anchor it normally -- it must already ride the cursor when revealed.
        local cf = EnsureCursorFrame()
        PositionCursorFrameNow(cf)
        local point = POINT_FOR_POS[EllesmereUIDB.tooltipCursorPosition or "top"] or "BOTTOM"
        tooltip:SetOwner(parent, "ANCHOR_NONE")
        tooltip:ClearAllPoints()
        tooltip:SetPoint(point, cf, "CENTER",
            EllesmereUIDB.tooltipCursorOffsetX or 0,
            EllesmereUIDB.tooltipCursorOffsetY or 0)
    end

    -- Re-assert the cursor anchor WITHOUT re-owning the tooltip (SetOwner would
    -- wipe content). A content-setter that clears/hides the tip mid-build (e.g.
    -- SetItemByID) fires OnHide, hiding the tracking frame and leaving the tip
    -- anchored to a hidden/unpositioned frame so it never appears. Call this
    -- AFTER content is set and before Show: re-shows + repositions the tracker
    -- and re-points the tooltip. No-op (safe unconditionally) when the cursor anchor or reskin master is off.
    EllesmereUI._repointTooltipAtCursor = function(tooltip)
        if tooltip ~= GameTooltip then return end
        if EllesmereUIDB and EllesmereUIDB.customTooltips == false then return end
        if not (EllesmereUIDB and EllesmereUIDB.tooltipAnchorCursor) then return end
        if tooltip:IsForbidden() then return end
        local cf = EnsureCursorFrame()
        PositionCursorFrameNow(cf)
        local point = POINT_FOR_POS[EllesmereUIDB.tooltipCursorPosition or "top"] or "BOTTOM"
        tooltip:ClearAllPoints()
        tooltip:SetPoint(point, cf, "CENTER",
            EllesmereUIDB.tooltipCursorOffsetX or 0,
            EllesmereUIDB.tooltipCursorOffsetY or 0)
    end

    local function InstallHook()
        if hooked or EllesmereUI.BlizzSkinPadStandDown() then return end
        hooked = true
        EnsureCursorFrame()
        -- Stop the tracker when the tooltip closes; ApplyCursorAnchor reshows it.
        GameTooltip:HookScript("OnHide", function()
            if cursorFrame then cursorFrame:Hide() end
        end)
        hooksecurefunc("GameTooltip_SetDefaultAnchor", ApplyCursorAnchor)
        -- World-unit tooltips fade out (~1-2s) on mouse-off instead of hiding instantly like
        -- unitframe/item/buff/CDM tips; while riding the cursor that lingering fade trails the pointer, so collapse it to an instant hide -- only while the cursor anchor is on.
        if GameTooltip.FadeOut then
            hooksecurefunc(GameTooltip, "FadeOut", function(self)
                if self ~= GameTooltip then return end
                if EllesmereUIDB and EllesmereUIDB.tooltipAnchorCursor then
                    self:Hide()
                end
            end)
        end
    end

    EllesmereUI._applyTooltipCursorAnchor = function()
        if EllesmereUIDB and EllesmereUIDB.tooltipAnchorCursor then
            InstallHook()
        elseif cursorFrame then
            cursorFrame:Hide()
        end
    end

    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        EllesmereUI._applyTooltipCursorAnchor()
    end)
end

-------------------------------------------------------------------------------
--  Fixed Tooltip Position (EUI-owned, movable in Unlock Mode)
--  EUI permanently owns the default GameTooltip's screen position: every default-anchored
--  tooltip is re-pointed onto OUR anchor frame, dragged via a real Unlock Mode mover.
--  Position is PER PROFILE (profiles[name].tooltipFixedPos); a profile with none gets a
--  ONE-TIME seed captured from wherever Blizzard's Edit Mode container currently sits, so
--  the takeover is visually a no-op until the user drags the box. GameTooltipDefaultContainer
--  is only ever READ, never written, so the user's Edit Mode position survives intact and
--  stands again if the reskin master is off. Same GameTooltip_SetDefaultAnchor post-hook
--  family as the cursor anchor and growth direction (tooltip unprotected, content never
--  touched, no taint surface); Anchor to Cursor takes precedence. Placed BEFORE the growth-direction block so its hook registers first and growth enforcement composes on top of our corner.
-------------------------------------------------------------------------------
do
    -- Representative mover-box size; real tooltips vary, but they pin corner-to-corner to the box so they render inside this footprint.
    local FIXED_W, FIXED_H = 280, 165
    local anchorFrame

    local function ActiveProfile()
        return EllesmereUI.GetActiveProfileData()
    end

    -- Fixed mode is the permanent baseline: no toggle. Only the reskin master (off = vanilla tooltips) and Anchor to Cursor sideline it.
    local function WantFixed()
        if EllesmereUIDB and EllesmereUIDB.customTooltips == false then return false end
        if EllesmereUIDB and EllesmereUIDB.tooltipAnchorCursor then return false end
        return true
    end

    local function EnsureFixedFrame()
        if anchorFrame then return anchorFrame end
        anchorFrame = CreateFrame("Frame", "EllesmereUI_TooltipFixedAnchor", UIParent)
        anchorFrame:SetSize(FIXED_W, FIXED_H)
        anchorFrame:EnableMouse(false)
        -- Placeholder point; PositionFromSaved overrides from the profile pos.
        anchorFrame:SetPoint("CENTER", UIParent, "CENTER", -350, -150)
        return anchorFrame
    end

    -- One-time per-profile seed: store where Blizzard's Edit Mode container puts
    -- the tooltip RIGHT NOW, so the takeover changes nothing visually until the
    -- user drags the mover. READ only, container never modified. Retries
    -- harmlessly until the container has a real rect (Edit Mode layouts land
    -- after login); a stored position (seeded or dragged) is never overwritten, so this runs at most once per profile.
    local function EnsureSeeded()
        local prof = ActiveProfile()
        if not prof or prof.tooltipFixedPos then return end
        -- Adopt a position left under the old account-global key.
        if EllesmereUIDB and EllesmereUIDB.tooltipFixedPos then
            prof.tooltipFixedPos = EllesmereUIDB.tooltipFixedPos
            EllesmereUIDB.tooltipFixedPos = nil
            return
        end
        local c = _G.GameTooltipDefaultContainer
        if not c or not c.GetLeft then return end
        local l, b = c:GetLeft(), c:GetBottom()
        if not l or not b then return end
        local w, ch = c:GetWidth() or 0, c:GetHeight() or 0
        local us = UIParent:GetEffectiveScale() or 1
        if us <= 0 then return end
        local r = (c:GetEffectiveScale() or us) / us
        -- Blizzard pins the tooltip's corner to the container corner nearest the
        -- closest screen corner. Find that point, then park our box so ITS
        -- matching corner sits exactly there; an idle container may be
        -- collapsed to a sliver (corners coincide), still correct.
        local uw, uh = UIParent:GetWidth(), UIParent:GetHeight()
        local ccx = (l + w / 2) * r - uw / 2
        local ccy = (b + ch / 2) * r - uh / 2
        local px = (ccx < 0) and (l * r) or ((l + w) * r)
        local py = (ccy < 0) and (b * r) or ((b + ch) * r)
        prof.tooltipFixedPos = {
            centerX = px + ((ccx < 0) and (FIXED_W / 2) or (-FIXED_W / 2)) - uw / 2,
            centerY = py + ((ccy < 0) and (FIXED_H / 2) or (-FIXED_H / 2)) - uh / 2,
        }
    end

    -- Park the anchor frame at the ACTIVE profile's position (center offsets from UIParent
    -- center, matching how the mover stores CENTER coords). Reading the profile live every call makes profile switches self-heal on the next tooltip show, with zero extra wiring.
    local function PositionFromSaved()
        local af = EnsureFixedFrame()
        EnsureSeeded()
        local prof = ActiveProfile()
        local pos = prof and prof.tooltipFixedPos
        af:ClearAllPoints()
        if pos and pos.centerX and pos.centerY then
            af:SetPoint("CENTER", UIParent, "CENTER", pos.centerX, pos.centerY)
        else
            af:SetPoint("CENTER", UIParent, "CENTER", -350, -150)
        end
    end

    -- Corner of the box the tooltip pins to: the one nearest the closest screen corner, so
    -- growth always runs INTO the screen (and the box). Growth Direction, when set, forces the vertical component -- the same rule its own enforcement block applies, so the two never fight.
    local function CornerFor(af)
        local cx, cy = -350, -150
        local l, b = af:GetLeft(), af:GetBottom()
        if l and b then
            cx = l + (af:GetWidth() or 0) / 2 - UIParent:GetWidth() / 2
            cy = b + (af:GetHeight() or 0) / 2 - UIParent:GetHeight() / 2
        else
            local prof = ActiveProfile()
            local pos = prof and prof.tooltipFixedPos
            if pos and pos.centerX and pos.centerY then cx, cy = pos.centerX, pos.centerY end
        end
        local dir = EllesmereUIDB and EllesmereUIDB.tooltipGrowthDirection
        local vert = (dir == "down" and "TOP") or (dir == "up" and "BOTTOM")
            or ((cy < 0) and "BOTTOM" or "TOP")
        return vert .. ((cx < 0) and "LEFT" or "RIGHT")
    end

    -- Blizzard's container logic can re-anchor a default-anchored tooltip a few
    -- frames after show WITHOUT clearing points first (see Growth Direction
    -- below), pinning a second corner and stretching the tooltip between our
    -- box and Blizzard's container. Enforcement rides the same armed/disarmed
    -- SetPoint pattern: NEVER reads hook args (hooked secure setters can receive secret values), re-derives everything, rewrites only on deviation.
    local _fixedEnforcing = false
    local _fixedArmed = false

    local function EnforceFixed(tooltip)
        if not WantFixed() then return end
        if tooltip:IsForbidden() then return end
        local af = anchorFrame
        if not af then return end
        local corner = CornerFor(af)
        local point, relTo = tooltip:GetPoint(1)
        -- GetPoint can hand back a SECRET point: Blizzard anchors the world cursor
        -- tooltip (SetWorldCursor -> GameTooltip_SetDefaultAnchor) from restricted
        -- code, and comparing a secret raises, so the classification MUST short-circuit
        -- ahead of the compares. A secret anchor is by definition not ours: treat it as
        -- a deviation and re-point. Our own write reads back clean, so the early-out works again from the next call on.
        local secretPt = issecretvalue and (issecretvalue(point) or issecretvalue(relTo))
        if not secretPt and tooltip:GetNumPoints() == 1 and point == corner and relTo == af then return end
        _fixedEnforcing = true
        tooltip:ClearAllPoints()
        tooltip:SetPoint(corner, af, corner, 0, 0)
        _fixedEnforcing = false
    end

    local function ApplyFixedAnchor(tooltip, parent)
        if not TooltipIsGlobalLike(tooltip) then return end
        if not WantFixed() then return end
        if tooltip:IsForbidden() then return end
        -- A forbidden owner (nameplate aura button) cannot be anchored to:
        -- leave Blizzard's anchoring alone AND disarm SetPoint enforcement.
        -- Arming happens in the SetDefaultAnchor hook before this runs; leaving
        -- it armed would let EnforceFixed yank the tooltip into our box with no matching SetOwner. See TooltipOwnerUsable.
        if not TooltipOwnerUsable(parent) then
            _fixedArmed = false
            return
        end
        -- An open Unlock Mode session owns the anchor frame (live drags + uncommitted edits): re-parking from saved would snap it back mid-session, so pin to wherever the session has it.
        -- A screen-edge link in Unlock Mode owns the position too: re-parking would pull the box off the edge until the anchor chain moves it back a frame later.
        if EllesmereUI._unlockActive then
            EnsureSeeded()
        elseif not EllesmereUI.IsUnlockAnchored("EUI_TooltipAnchor") then
            PositionFromSaved()
        end
        tooltip:SetOwner(parent, "ANCHOR_NONE")
        EnforceFixed(tooltip)
    end

    hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, parent)
        if not TooltipIsGlobalLike(tooltip) then return end
        -- Only the global tooltip can be armed: the SetPoint enforcement below
        -- is hooked onto GameTooltip's own setters. See TooltipIsGlobalLike.
        if tooltip == GameTooltip then _fixedArmed = true end
        ApplyFixedAnchor(tooltip, parent)
    end)
    -- Every explicit tooltip build starts with SetOwner, which runs BEFORE the SetDefaultAnchor post-hook re-arms the flag, so explicitly-anchored uses (bags, other addons) never get their anchors rewritten.
    hooksecurefunc(GameTooltip, "SetOwner", function()
        _fixedArmed = false
    end)
    hooksecurefunc(GameTooltip, "SetPoint", function(tt)
        if _fixedEnforcing or not _fixedArmed then return end
        if tt ~= GameTooltip then return end
        EnforceFixed(tt)
    end)

    -- Reposition (and seed if needed) now: login, world entry, reset paths.
    EllesmereUI._applyTooltipFixedAnchor = function()
        PositionFromSaved()
    end

    -- Unlock Mode element: a real draggable mover for the tooltip position. Writes ONLY
    -- our per-profile key, never Blizzard's tooltip container. Hidden while Anchor to Cursor is on or the reskin master is off (both leave the fixed anchor inactive).
    local function RegisterUnlock()
        if not (EllesmereUI and EllesmereUI.RegisterUnlockElements and EllesmereUI.MakeUnlockElement) then return end
        local MK = EllesmereUI.MakeUnlockElement
        EllesmereUI:RegisterUnlockElements({
            MK({
                key      = "EUI_TooltipAnchor",
                label    = "Tooltip",
                group    = "Blizzard Windows",
                order    = 650,
                subtitle = "Fixed Position",
                noResize          = true,  -- tooltip size is dynamic; nothing to resize
                noAnchorTarget    = true,
                noAnchorTo        = true,
                noSizeMatchTarget = true,
                isHidden = function()
                    return not WantFixed()
                end,
                getFrame = function()
                    -- MUST stay side-effect-free: unlock mode calls getFrame from its drag
                    -- machinery (OnUpdate/OnDragStop), so parking from saved here would snap a live drag back on release. Boot/applyPos/loadPos do parking + seeding.
                    return EnsureFixedFrame()
                end,
                getSize  = function() return FIXED_W, FIXED_H end,
                savePos = function(_, _point, _relPoint, x, y)
                    -- Unlock mode hands over CENTER/CENTER coords; on Cancel the frame
                    -- still sits at the dragged spot, so never read the live position.
                    local prof = ActiveProfile()
                    if not prof then return end
                    prof.tooltipFixedPos = { centerX = x, centerY = y }
                end,
                loadPos = function()
                    EnsureSeeded()
                    local prof = ActiveProfile()
                    local pos = prof and prof.tooltipFixedPos
                    if pos and pos.centerX and pos.centerY then
                        return { point = "CENTER", relPoint = "CENTER", x = pos.centerX, y = pos.centerY }
                    end
                    return nil
                end,
                clearPos = function()
                    -- Clearing the profile key makes the next apply re-seed from Blizzard's CURRENT Edit Mode spot, so "reset position" = wherever Blizzard would put it today.
                    local prof = ActiveProfile()
                    if prof then prof.tooltipFixedPos = nil end
                    PositionFromSaved()
                end,
                applyPos = function()
                    PositionFromSaved()
                end,
            })
        })
    end

    local boot = CreateFrame("Frame")
    boot:RegisterEvent("PLAYER_LOGIN")
    boot:RegisterEvent("PLAYER_ENTERING_WORLD")
    boot:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_LOGIN" then
            EnsureFixedFrame()
            PositionFromSaved()
            RegisterUnlock()
        else
            -- Edit Mode layouts land after login, so the one-time seed may have found no container rect yet. Retry once in-world, then stop listening (later seeds happen lazily at tooltip show).
            self:UnregisterAllEvents()
            PositionFromSaved()
        end
    end)
end

-------------------------------------------------------------------------------
--  Growth Direction (default screen-anchored tooltip)
--  Blizzard picks the default tooltip's anchored corner dynamically from the
--  container's screen position, and the pinned corner decides which way added lines
--  grow (TOP pinned = expands down, BOTTOM pinned = expands up). tooltipGrowthDirection
--  "up"/"down" forces the vertical component of whatever corner Blizzard chose,
--  keeping its horizontal side; "default" (or unset) leaves Blizzard's dynamic pick
--  alone. Re-point only, same GameTooltip_SetDefaultAnchor post-hook family as the
--  cursor anchor (no taint surface: tooltip unprotected, content never touched). Cursor-anchored mode re-points the tooltip itself and takes precedence.
-------------------------------------------------------------------------------
do
    local function WantForcedDir()
        if EllesmereUIDB and EllesmereUIDB.customTooltips == false then return nil end
        local dir = EllesmereUIDB and EllesmereUIDB.tooltipGrowthDirection
        if dir ~= "up" and dir ~= "down" then return nil end
        if EllesmereUIDB.tooltipAnchorCursor then return nil end
        return dir
    end

    -- Blizzard's container logic RE-ANCHORS the tooltip a few frames after show (and
    -- on size changes) WITHOUT clearing points first. SetPoint only replaces a
    -- same-keyword point, so its re-assert ADDED a second corner next to the forced
    -- one -- top and bottom both pinned, tooltip stretched to fill the gap.
    -- Enforcement rides a SetPoint hook instead: any anchor write that isn't ours
    -- while a default-anchored tooltip is up gets collapsed back to the single
    -- forced corner. The hook never reads its args (hooked setters can receive
    -- secret values), re-deriving everything from GetPoint; _growthEnforcing guards re-entry from our own SetPoint inside the hook.
    local _growthEnforcing = false
    local _growthDefaultAnchored = false

    local function Enforce(tooltip)
        local dir = WantForcedDir()
        if not dir then return end
        if tooltip:IsForbidden() then return end
        local point, relTo, _, x, y = tooltip:GetPoint(1)
        -- A point written by restricted code (world cursor tooltip) is SECRET:
        -- find() and == on it raise, and the forced corner cannot be derived from it
        -- at all. Skip this pass; the next one, after a clean re-anchor, enforces normally.
        if issecretvalue and (issecretvalue(point) or issecretvalue(x) or issecretvalue(y)) then return end
        if not point then return end
        relTo = relTo or GameTooltipDefaultContainer
        if not relTo then return end
        local horiz = (point:find("LEFT") and "LEFT") or (point:find("RIGHT") and "RIGHT") or ""
        local newPoint = ((dir == "down") and "TOP" or "BOTTOM") .. horiz
        if tooltip:GetNumPoints() == 1 and point == newPoint then return end
        _growthEnforcing = true
        tooltip:ClearAllPoints()
        tooltip:SetPoint(newPoint, relTo, newPoint, x or 0, y or 0)
        _growthEnforcing = false
    end

    hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip)
        if not TooltipIsGlobalLike(tooltip) then return end
        -- Only the global tooltip can be armed: the SetPoint enforcement below
        -- is hooked onto GameTooltip's own setters. See TooltipIsGlobalLike.
        if tooltip == GameTooltip then _growthDefaultAnchored = true end
        Enforce(tooltip)
    end)
    -- Every tooltip build starts with SetOwner (runs BEFORE the SetDefaultAnchor post-hook re-arms the flag), so explicitly-anchored uses (bags, other addons) never get their anchors rewritten.
    hooksecurefunc(GameTooltip, "SetOwner", function()
        _growthDefaultAnchored = false
    end)
    hooksecurefunc(GameTooltip, "SetPoint", function(tt)
        if _growthEnforcing or not _growthDefaultAnchored then return end
        Enforce(tt)
    end)
end

I.last = "TooltipAnchor"
