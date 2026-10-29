if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_ActionBars_Layout.lua
--
--  The layout engine that places buttons in a grid, bar chrome sizing,
--  party mode and LayoutBar.
--  Loads after EUI_ActionBars_Bars.lua; reads ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...

local ipairs = ipairs
local ceil, floor, max = math.ceil, math.floor, math.max
local wipe = wipe
local InCombatLockdown = InCombatLockdown
local GetBindingKey = GetBindingKey
local EFD = ns.EFD

local EAB, barButtons = ns.EAB, ns.barButtons
local I = ns._internals
local _gridState, BAR_CONFIG, BAR_LOOKUP = I._gridState, I.BAR_CONFIG, I.BAR_LOOKUP
local SHAPE_BTN_EXPAND, ShouldQuickKeybindSurfaceBar = I.SHAPE_BTN_EXPAND, I.ShouldQuickKeybindSurfaceBar
local barBaseSize, barFrames = I.barBaseSize, I.barFrames
local LayoutPagingFrame, SetupPagingFrame = I.LayoutPagingFrame, I.SetupPagingFrame
local WireSecurePagingButton = I.WireSecurePagingButton
-- Written in EUI_ActionBars_Paging.lua;
-- SetPagingFrame hands the value to this copy.
local _pagingFrame
I.pagingFrameSetters[#I.pagingFrameSetters + 1] = function(v) _pagingFrame = v end

-------------------------------------------------------------------------------
--  Layout Engine positions buttons in a grid
-------------------------------------------------------------------------------
-- Snap to a whole number of physical pixels at the bar's effective scale (same
-- round-trip as the border system), eliminating sub-pixel drift between siblings.
local function SnapForScale(x, barScale)
    if x == 0 then return 0 end
    local PP = EllesmereUI and EllesmereUI.PP
    if PP then return PP.Scale(x) end
    return math.floor(x + 0.5)
end

-- Grow direction for icon layout + fixed-edge resize. Lives on EAB, not a
-- file-scope local. Caveat: in an unlock
-- anchor chain a mid-chain bar can inherit its parent's grow visually while its
-- own DB still holds the old value.
function EAB:ResolveGrowDirectionForLayout(key, s, depth)
    return (s.growDirection or "up"):upper()
end

-- Resolve a bar's icon order into abstract order parts. iconOrder supersedes the legacy
-- reverseIconOrder boolean; nil iconOrder falls back to the boolean, so old profiles
-- render unchanged with zero migration. Returns flowFlip (reverse button flow along the
-- fill axis) plus hAnchor ("LEFT"/"RIGHT") and vAnchor ("TOP"/"BOTTOM") for the corner
-- modes (both nil in the two legacy modes). do-end + ns so no file-scope local slots
-- are consumed.
do
    local function ResolveIconOrder(s)
        local order = s.iconOrder
        if order == nil then
            order = s.reverseIconOrder and "reversed" or "default"
        end
        if order == "reversed" then
            return true, nil, nil
        elseif order == "TOPLEFT" then
            return false, "LEFT", "TOP"
        elseif order == "TOPRIGHT" then
            return false, "RIGHT", "TOP"
        elseif order == "BOTTOMLEFT" then
            return false, "LEFT", "BOTTOM"
        elseif order == "BOTTOMRIGHT" then
            return false, "RIGHT", "BOTTOM"
        end
        return false, nil, nil
    end

    -- Resolved icon order -> concrete index flips for a bar's button grid.
    -- Corner modes place button 1 in that corner purely by permuting indexes:
    -- the frame, its size and the grid geometry never change. rowsUpward is meaningful
    -- only for horizontal bars. Third return (cornerFill): true in the four corner
    -- modes. On vertical bars those fill ACROSS the columns first and wrap down to the
    -- next row; Default/Reversed keep the legacy down-each-column fill. Horizontal bars
    -- already fill row-first, so callers ignore it there.
    function ns.GetOrderFlips(s, isVertical, rowsUpward)
        local flowFlip, hAnchor, vAnchor = ResolveIconOrder(s)
        local colFlip, rowFlip = false, false
        if isVertical then
            rowFlip = flowFlip or (vAnchor == "BOTTOM")
            colFlip = (hAnchor == "RIGHT")
        else
            colFlip = flowFlip or (hAnchor == "RIGHT")
            if vAnchor then
                rowFlip = ((vAnchor == "TOP") == rowsUpward)
            end
        end
        return colFlip, rowFlip, (hAnchor ~= nil)
    end
end

-- Compute layout for a bar and return a table of per-button data.
-- Returns: { [i] = { x, y, w, h, show } }, frameW, frameH
local function ComputeBarLayout(key)
    local info = BAR_LOOKUP[key]
    if not info then return {}, 1, 1 end
    local buttons = barButtons[key]
    if not buttons then return {}, 1, 1 end

    local s = EAB.db.profile.bars[key]
    local numIcons = s.overrideNumIcons or s.numIcons or info.count
    if numIcons < 1 then numIcons = info.count end
    if numIcons > info.count then numIcons = info.count end
    if info.isStance then numIcons = GetNumShapeshiftForms() or info.count end
    if numIcons < 1 then numIcons = 1 end

    local numRows = s.overrideNumRows or s.numRows or 1
    if numRows < 1 then numRows = 1 end
    local stride = ceil(numIcons / numRows)
    numRows = ceil(numIcons / stride)
    -- Raw coords -- do NOT pre-snap with SnapForScale: PP.Scale truncates and
    -- loses a pixel where PP.mult > 1. Pixel-lock happens below, post-shape.
    local padding = s.buttonPadding or 2
    local isVertical = (s.orientation == "vertical")
    local growDir = EAB:ResolveGrowDirectionForLayout(key, s)
    local shape = ns.AB_LayoutShape(s)

    local base = barBaseSize[key]
    local baseW = base and base.w or 45
    local baseH = base and base.h or 45
    local btnW = (s.buttonWidth and s.buttonWidth > 0) and s.buttonWidth or baseW
    local btnH = (s.buttonHeight and s.buttonHeight > 0) and s.buttonHeight or baseH
    if shape ~= "none" and shape ~= "cropped" then
        btnW = btnW + SHAPE_BTN_EXPAND
        btnH = btnH + SHAPE_BTN_EXPAND
    end
    if shape == "cropped" then btnH = btnH * 0.80 end
    local PPc = EllesmereUI and EllesmereUI.PP
    local onePxC = PPc and PPc.mult or 1
    -- Lock btnW/btnH/padding to exact physical pixel multiples so stepW/stepH
    -- and the frame-size math below share the pixel grid of the width-match
    -- extras (onePxC). Otherwise coords drift sub-pixel as col grows, shrinking
    -- spacing and making the last button undershoot the match target.
    local btnWPxC    = math.floor(btnW    / onePxC + 0.5)
    local btnHPxC    = math.floor(btnH    / onePxC + 0.5)
    local paddingPxC = math.floor(padding / onePxC + 0.5)
    btnW    = btnWPxC    * onePxC
    btnH    = btnHPxC    * onePxC
    padding = paddingPxC * onePxC
    local stepW = btnW + padding
    local stepH = btnH + padding
    local extraWC = s._matchExtraPixels or 0
    local extraHC = s._matchExtraPixelsH or 0

    local showEmpty = s.alwaysShowButtons
    if showEmpty == nil then showEmpty = true end
    if info.isStance then showEmpty = false end

    -- Icon order flips are constant for the whole grid.
    local rowsUpward = not isVertical and (growDir == "UP" or growDir == "CENTER")
    local colFlip, rowFlip, cornerFill = ns.GetOrderFlips(s, isVertical, rowsUpward)

    local result = {}
    for i = 1, info.count do
        local btn = buttons[i]
        if not btn then break end
        if i > numIcons then
            result[i] = { x = 0, y = 0, w = btnW, h = btnH, show = false }
        else
            local col, row
            if isVertical then
                if cornerFill then
                    -- Corner modes fill across columns first, then wrap down a
                    -- row (numRows = the column count on vertical bars).
                    col = (i - 1) % numRows
                    row = floor((i - 1) / numRows)
                else
                    col = floor((i - 1) / stride)
                    row = (i - 1) % stride
                end
            else
                col = (i - 1) % stride
                row = floor((i - 1) / stride)
            end
            -- Icon order flips first so the width/height-match extras
            -- below derive from the final visual position.
            if colFlip then col = (isVertical and numRows or stride) - 1 - col end
            if rowFlip then row = (isVertical and stride or numRows) - 1 - row end
            local thisBtnW = (extraWC > 0 and col < extraWC) and (btnW + onePxC) or btnW
            local thisBtnH = (extraHC > 0 and row < extraHC) and (btnH + onePxC) or btnH
            local extraBeforeW = math.min(col, extraWC) * onePxC
            local extraBeforeH = math.min(row, extraHC) * onePxC
            local xOff = col * stepW + extraBeforeW
            local yOff
            if rowsUpward then
                yOff = row * stepH + extraBeforeH
            else
                yOff = -(row * stepH + extraBeforeH)
            end
            local show = true
            if not showEmpty and not (_gridState.shown or ShouldQuickKeybindSurfaceBar(s)) and ns.AB_EmptySlot(btn, info) then
                show = false
            end
            result[i] = { x = xOff, y = yOff, w = thisBtnW, h = thisBtnH, show = show }
        end
    end

    -- Frame size in integer physical pixels, then back to coord. btnW/btnH/
    -- padding are already exact pixel multiples, so these multiplies produce
    -- exact pixel counts with no float dust or 1px truncation loss.
    local totalCols = isVertical and numRows or stride
    local totalRows = isVertical and stride or numRows
    local frameWPx = totalCols * btnWPxC + (totalCols - 1) * paddingPxC + extraWC
    local frameHPx = totalRows * btnHPxC + (totalRows - 1) * paddingPxC + extraHC
    local frameW = frameWPx * onePxC
    local frameH = frameHPx * onePxC
    return result, max(frameW, 1), max(frameH, 1)
end

local function HideSlotArt(btn)
    if not btn.SlotArt then return end
    if EllesmereUI and EllesmereUI._hiddenParent then
        btn.SlotArt:SetParent(EllesmereUI._hiddenParent)
    else
        btn.SlotArt:Hide()
        btn.SlotArt:SetAlpha(0)
    end
end

-------------------------------------------------------------------------------
--  Party Mode: spinning action bars, on the shared spin engine
--  (EllesmereUI.PartySpin_Create, EllesmereUI_PartyMode.lua). Each bar's
--  shown buttons orbit that bar's centre by re-anchoring, not rotating, so
--  buttons stay upright and clicking, cooldowns and keybinds are unaffected.
--  Frozen in combat, where moving a protected button is blocked; offsets are
--  measured in screen space, so Blizzard style's per-button SetScale holds;
--  every button goes back onto its exact layout anchor when it stops.
--
--  do/end scope, so none of this takes
--  a main-chunk slot; the refresh lives on ns for ApplyAll.
-------------------------------------------------------------------------------
do
local groups, groupOf = {}, {}
ns.PartySpin_Refresh = EllesmereUI.PartySpin_Create({
    target = "actionBars",
    collect = function()
        wipe(groups)
        for _, info in ipairs(BAR_CONFIG) do
            local buttons, frame = barButtons[info.key], barFrames[info.key]
            if buttons and frame then
                local grp = groupOf[info.key]
                if not grp then
                    grp = { frames = {} }
                    groupOf[info.key] = grp
                end
                grp.pivot = frame
                local list = grp.frames
                wipe(list)
                for i = 1, #buttons do
                    local btn = buttons[i]
                    if btn and btn:IsShown() then list[#list + 1] = btn end
                end
                groups[#groups + 1] = grp
            end
        end
        return groups
    end,
})
end

-- Upvalue for LayoutBar (must be declared before it). ApplyAll sets it during full
-- rebuilds so edge preservation cannot save stale positions into the new profile.
local _isApplyingAll = false
I.isApplyingAllSetters[#I.isApplyingAllSetters + 1] = function(v) _isApplyingAll = v end

local function LayoutBar(key)
    if InCombatLockdown() then ns._eabApplyDeferred = true return end
    local info = BAR_LOOKUP[key]
    if not info then return end
    local frame = barFrames[key]
    local buttons = barButtons[key]
    if not frame or not buttons then return end

    local s = EAB.db.profile.bars[key]
    -- LAYOUT STAMP: skips a re-layout whose inputs are unchanged (the combat-exit
    -- ApplyAll re-ran this full layout for nothing). EVERY input the body reads
    -- folds into one string: raw settings, profile flags, barPositions, base sizes,
    -- PP.mult (resolution), derived helpers via their RESULTS (grow direction, order
    -- flips, quick keybind surface, unlock anchoring), the stance form count, the
    -- flyout screen-thirds bucket (live GetCenter, so anchor-chain moves invalidate
    -- too), and -- hide-empty bars only -- the per-slot filled bitmask driving
    -- empty-slot alpha. A matching stamp means byte-identical skip. Written only at
    -- the END of a completed pass and cleared on entry, so an interrupted pass can
    -- never leave a stale valid stamp.
    local _lbStamp
    do
        local p = EAB.db.profile
        local pos = p.barPositions and p.barPositions[key]
        local base0 = barBaseSize[key]
        local PPm = EllesmereUI and EllesmereUI.PP
        local growDirS = EAB:ResolveGrowDirectionForLayout(key, s)
        local isVertS = (s.orientation == "vertical")
        local rowsUpS = not isVertS and (growDirS == "UP" or growDirS == "CENTER")
        local cfS, rfS, cnS = ns.GetOrderFlips(s, isVertS, rowsUpS)
        local nIcoS = s.overrideNumIcons or s.numIcons or info.count
        if info.isStance then nIcoS = GetNumShapeshiftForms() or info.count end
        local fbS = -1
        do
            local cx, cy = frame:GetCenter()
            if cx and cy then
                local r = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
                local uw, uh = UIParent:GetSize()
                fbS = ((cx * r > uw * 2 / 3) and 2 or 0) + ((cy * r > uh * 2 / 3) and 1 or 0)
            end
        end
        local showES = s.alwaysShowButtons
        if showES == nil then showES = true end
        if info.isStance then showES = false end
        local fillS = ""
        if not showES then
            local tf = {}
            for i = 1, info.count do
                local b = buttons[i]
                tf[i] = (b and not ns.AB_EmptySlot(b, info)) and "1" or "0"
            end
            fillS = table.concat(tf)
        end
        _lbStamp = table.concat({
            -- #buttons, not just the configured count: a Never bar is built with
            -- none and gains them at the reveal edge, and every other stamp input
            -- can be identical across that edge (the base size falls back to the
            -- same 45x45 the real button reports).
            tostring(nIcoS), tostring(#buttons),
            tostring(s.overrideNumRows or s.numRows or 1),
            tostring(s.buttonPadding or 2), tostring(s.orientation), growDirS or "-",
            tostring(s.buttonShape), tostring(s.buttonWidth), tostring(s.buttonHeight),
            tostring(s._matchExtraPixels), tostring(s._matchExtraPixelsH),
            tostring(showES), tostring(s.mouseoverEnabled),
            ns.AB_Forever() and "forever" or ns.AB_Style(),
            ns.AB_ChromeStamp(key),
            tostring(p.procGlowEnabled),
            pos and tostring(pos.point) or "-", pos and tostring(pos.relPoint) or "-",
            pos and tostring(pos.x) or "-", pos and tostring(pos.y) or "-",
            base0 and tostring(base0.w) or "-", base0 and tostring(base0.h) or "-",
            tostring(PPm and PPm.mult or 1),
            tostring(cfS), tostring(rfS), tostring(cnS),
            tostring(_gridState.shown),
            ShouldQuickKeybindSurfaceBar(s) and "1" or "0",
            (EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored(key)) and "1" or "0",
            tostring(fbS), fillS,
        }, "|")
        local st = ns._eabLayoutStamp
        if not st then st = {}; ns._eabLayoutStamp = st end
        if st[key] == _lbStamp then
            return
        end
        st[key] = nil
        -- This pass rewrites the pet buttons from live state: drop the pet
        -- handler's shape memo so its next full pass lays them out again.
        if info.isPetBar then ns._eabPetLayoutSig = nil end
    end
    local numIcons = s.overrideNumIcons or s.numIcons or info.count
    if numIcons < 1 then numIcons = info.count end
    if numIcons > info.count then numIcons = info.count end
    if info.isStance then numIcons = GetNumShapeshiftForms() or info.count end
    if numIcons < 1 then numIcons = 1 end

    local numRows = s.overrideNumRows or s.numRows or 1
    if numRows < 1 then numRows = 1 end

    local stride = ceil(numIcons / numRows)
    if stride < 1 then stride = 1 end
    -- Recalculate actual rows needed (avoids empty trailing rows)
    numRows = ceil(numIcons / stride)
    -- Raw coords -- do NOT pre-snap with SnapForScale: PP.Scale truncates and
    -- loses a pixel where PP.mult > 1. Pixel-lock happens below, post-shape.
    local padding = s.buttonPadding or 2
    local isVertical = (s.orientation == "vertical")
    local growDir = EAB:ResolveGrowDirectionForLayout(key, s)
    local shape = ns.AB_LayoutShape(s)

    local base = barBaseSize[key]
    local baseW = base and base.w or 45
    local baseH = base and base.h or 45
    local btnW = (s.buttonWidth and s.buttonWidth > 0) and s.buttonWidth or baseW
    local btnH = (s.buttonHeight and s.buttonHeight > 0) and s.buttonHeight or baseH

    if shape ~= "none" and shape ~= "cropped" then
        btnW = btnW + SHAPE_BTN_EXPAND
        btnH = btnH + SHAPE_BTN_EXPAND
    end
    if shape == "cropped" then
        btnH = btnH * 0.80
    end

    -- Width/height match: distribute extra physical pixels across buttons
    local PP = EllesmereUI and EllesmereUI.PP
    local onePx = PP and PP.mult or 1
    -- Lock btnW/btnH/padding to exact physical pixel multiples so stepW and the
    -- width-match +1px extras share one pixel grid; prevents sub-pixel drift
    -- that shrinks visible spacing where PP.mult > 1.
    local btnWPx    = math.floor(btnW    / onePx + 0.5)
    local btnHPx    = math.floor(btnH    / onePx + 0.5)
    local paddingPx = math.floor(padding / onePx + 0.5)
    btnW    = btnWPx    * onePx
    btnH    = btnHPx    * onePx
    padding = paddingPx * onePx
    local stepW = btnW + padding
    local stepH = btnH + padding

    local extraW = s._matchExtraPixels or 0
    local extraH = s._matchExtraPixelsH or 0

    -- Show empty slots (stance bar always forces this off)
    local showEmpty = s.alwaysShowButtons
    if showEmpty == nil then showEmpty = true end
    if info.isStance then showEmpty = false end

    -- Growth direction fixes which edge stays put on resize. UP/CENTER on
    -- horizontal bars stack rows upward (2nd row above 1st); icon order flips
    -- permute indexes within that fixed grid.
    local rowsUpward = not isVertical and (growDir == "UP" or growDir == "CENTER")
    local colFlip, rowFlip, cornerFill = ns.GetOrderFlips(s, isVertical, rowsUpward)

    -- Fit Ring to Cropped Buttons sizes the assist ring from the button's own
    -- rectangle: a shown ring on this bar is refitted (or restored) after the
    -- re-layout. A hidden ring is fitted by AssistShow before it next shows.
    local assistFit = EAB.db.profile.assistGlowFitCropped
    local assistRefit = false

    for i = 1, info.count do
        local btn = buttons[i]
        if not btn then break end

        if i > numIcons then
            btn:Hide()
            btn:SetAlpha(0)
            ns._eabMarkParked(btn, info)
        else
            -- Buttons inside range stay Shown; visibility is alpha-only so
            -- combat page swaps never strand a button hidden.
            local lfd = EFD(btn)
            local demote = lfd.parkA0 == 2 and not btn:IsShown()
            btn:Show()
            if demote and btn:IsShown() then lfd.parkA0 = 1 end

            local col, row
            if isVertical then
                if cornerFill then
                    -- Corner modes fill across columns first, then wrap down a
                    -- row (numRows = the column count on vertical bars).
                    col = (i - 1) % numRows
                    row = floor((i - 1) / numRows)
                else
                    col = floor((i - 1) / stride)
                    row = (i - 1) % stride
                end
            else
                col = (i - 1) % stride
                row = floor((i - 1) / stride)
            end

            -- Icon order flips first so the width/height-match extras
            -- below derive from the final visual position.
            if colFlip then col = (isVertical and numRows or stride) - 1 - col end
            if rowFlip then row = (isVertical and stride or numRows) - 1 - row end

            -- Width/height match: first N columns/rows get +1 physical pixel.
            -- Only the matched axis expands, so a row stays uniform (no 1px jag).
            local thisBtnW = (extraW > 0 and col < extraW) and (btnW + onePx) or btnW
            local thisBtnH = (extraH > 0 and row < extraH) and (btnH + onePx) or btnH
            -- Cumulative offset from expanded buttons before this one
            local extraBeforeW = math.min(col, extraW) * onePx
            local extraBeforeH = math.min(row, extraH) * onePx

            btn:ClearAllPoints()
            local xOff = col * stepW + extraBeforeW
            local yOff, anchor
            if rowsUpward then
                yOff = row * stepH + extraBeforeH
                anchor = "BOTTOMLEFT"
            else
                yOff = -(row * stepH + extraBeforeH)
                anchor = "TOPLEFT"
            end
            EFD(btn).barKey = key
            -- Stock styles (Blizzard, Classic) keep the native-size button and
            -- scale it, so the stock art scales with it.
            local abStyle = ns.AB_Style()
            if abStyle ~= "eui" then
                local base = barBaseSize[key]
                local nativeW = base and base.w or 45
                local nativeH = base and base.h or 45
                local sc = thisBtnW / nativeW
                btn:SetScale(sc)
                btn:SetSize(nativeW, nativeH)
                btn:SetPoint(anchor, frame, anchor, xOff / sc, yOff / sc)
                -- Classic WoW UI: the vanilla ring on the native-size button,
                -- painted once per size (the scale carries it). Blizzard
                -- Style on the Forever client: the retail border, once.
                if abStyle == "classic" then
                    local cfd = EFD(btn)
                    if cfd.classicW ~= nativeW or cfd.classicH ~= nativeH then
                        cfd.classicW, cfd.classicH = nativeW, nativeH
                        ns.AB_PaintClassicButton(btn, nativeW, nativeH)
                    end
                elseif EllesmereUI.IS_FOREVER and not (info.isStance or info.isPetBar) then
                    ns.AB_StockNormal(btn)
                end
            else
                btn:SetPoint(anchor, frame, anchor, xOff, yOff)
                btn:SetSize(thisBtnW, thisBtnH)
            end
            HideSlotArt(btn)

            -- Stock styles: counter-scale SpellActivationAlert so the native
            -- proc glow renders at screen size despite the button's SetScale.
            if abStyle ~= "eui" and btn.SpellActivationAlert then
                local base = barBaseSize[key]
                local nativeW = base and base.w or 45
                local sc = thisBtnW / nativeW
                if sc > 0 then
                    btn.SpellActivationAlert:SetScale(1 / sc)
                end
            end

            -- Resize the autocast overlay to match the button size
            if btn.AutoCastOverlay then
                btn.AutoCastOverlay:SetAllPoints(btn)
            end

            -- TargetReticleAnimFrame is authored 128x128 for the default 45x45
            -- button, so btnW/45 keeps the visual proportions.
            if btn.TargetReticleAnimFrame then
                btn.TargetReticleAnimFrame:SetScale(btnW / 45)
            end

            -- AssistedCombat frames are created lazily at the default 45x45,
            -- anchored CENTER; scale them to our button size. A highlight ring
            -- fitted to a Cropped button (ns._AssistFit) runs at scale 1 and is
            -- refitted by the assist pass queued at the end of this layout.
            local ahf = btn.AssistedCombatHighlightFrame
            if ahf and not (ns._eabFD[ahf] and ns._eabFD[ahf].fitW) then
                ahf:SetScale(btnW / 45)
            end
            if assistFit and not assistRefit then
                local ohf = EFD(btn).assistHL
                assistRefit = (ohf and ohf:IsShown()) or (ahf and ahf:IsShown()) or false
            end
            if btn.AssistedCombatRotationFrame then
                btn.AssistedCombatRotationFrame:SetScale(btnW / 45)
            end

            -- Pin SpellActivationAlert to button bounds for custom proc glows;
            -- with custom glows off or a stock style on, leave it untouched.
            if btn.SpellActivationAlert and EAB.db.profile.procGlowEnabled and abStyle == "eui" then
                btn.SpellActivationAlert:SetAllPoints(btn)
                btn.SpellActivationAlert:SetScale(1)
            end

            -- Profession quality diamonds: EAB paints its own rank icon (the
            -- quality scan in OnEnable). Blizzard's overlay is created lazily
            -- inside the secure button Update, which our buttons get no
            -- events for, and forcing that update writes the new frame onto
            -- the secure button's table (taint). Keep it permanently hidden.
            if btn.ProfessionQualityOverlayFrame then
                btn.ProfessionQualityOverlayFrame:SetShown(false)
                if not EFD(btn).qualityHooked then
                    btn.ProfessionQualityOverlayFrame:HookScript("OnShow", function(self)
                        self:SetShown(false)
                    end)
                    EFD(btn).qualityHooked = true
                end
            end
            if EAB._QueueRankScan then EAB._QueueRankScan() end

            if not showEmpty and not (_gridState.shown or ShouldQuickKeybindSurfaceBar(s)) and ns.AB_EmptySlot(btn, info) then
                btn:SetAlpha(0)
                ns._eabMarkParked(btn, info)
            else
                if not s.mouseoverEnabled then
                    btn:SetAlpha(1)
                    lfd.parkA0 = nil
                end
            end
        end
    end

    -- Size the bar frame to encompass all visible buttons (including extra px)
    local totalCols = isVertical and numRows or stride
    local totalRows = isVertical and stride or numRows
    local frameW = totalCols * btnW + (totalCols - 1) * padding + extraW * onePx
    local frameH = totalRows * btnH + (totalRows - 1) * padding + extraH * onePx

    -- Sync frame anchor with barPositions before SetSize so the frame grows
    -- from the correct edge (or center). Skip anchored bars: their position
    -- is owned by the anchor chain, not barPositions.
    local isAnchored = EllesmereUI.IsUnlockAnchored
        and EllesmereUI.IsUnlockAnchored(key)
    if not isAnchored then
        local curPt = ({frame:GetPoint(1)})[1]
        local pos = EAB.db.profile.barPositions and EAB.db.profile.barPositions[key]
        if pos and pos.point and pos.relPoint == "CENTER" and curPt ~= pos.point then
            local PPa = EllesmereUI and EllesmereUI.PP
            local px, py = pos.x or 0, pos.y or 0
            if pos.point == "CENTER" and curPt and curPt ~= "CENTER" then
                -- Edge -> CENTER: read the live center (stored CENTER coords may
                -- be stale from a different width) so the bar does not jump.
                local fCx, fCy = frame:GetCenter()
                if fCx and fCy then
                    local uiS = UIParent:GetEffectiveScale()
                    local fS = frame:GetEffectiveScale()
                    local ratio = fS / uiS
                    local uiW, uiH = UIParent:GetSize()
                    px = fCx * ratio - uiW / 2
                    py = fCy * ratio - uiH / 2
                end
                if PPa and PPa.SnapCenterForDim then
                    local es = frame:GetEffectiveScale()
                    px = PPa.SnapCenterForDim(px, frame:GetWidth() or 0, es)
                    py = PPa.SnapCenterForDim(py, frame:GetHeight() or 0, es)
                end
            elseif PPa and PPa.SnapForES then
                local es = frame:GetEffectiveScale()
                px = PPa.SnapForES(px, es)
                py = PPa.SnapForES(py, es)
            end
            frame:ClearAllPoints()
            frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, px, py)
        end
    end
    -- Pre-resize center in UIParent space, captured BEFORE SetSize (an
    -- edge-pointed frame moves its center when resized); the anchor offset
    -- upkeep below validates against it.
    local preCX, preCY
    do
        local c1, c2 = frame:GetCenter()
        if c1 and c2 then
            local r = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
            preCX, preCY = c1 * r, c2 * r
        end
    end
    EllesmereUI._layoutBarResizing = key
    frame:SetSize(max(frameW, 1), max(frameH, 1))
    EllesmereUI._layoutBarResizing = nil
    -- Anchor offset upkeep: a growth-direction resize shifts the center by
    -- delta/2 while the fixed edge stays put, so the center-based anchor
    -- offset must follow. _eabPrevLayout* separates real resizes from init/reload sizing.
    do
        local newW = max(frameW, 1)
        local newH = max(frameH, 1)
        local prevW = frame._eabPrevLayoutW
        local prevH = frame._eabPrevLayoutH
        frame._eabPrevLayoutW = newW
        frame._eabPrevLayoutH = newH
        -- Self-validating gate: dw/2 compensation is correct only when the PRE-resize
        -- center sat at the anchor-derived position (target center + stored offset on
        -- the compensated axis). Mid-profile-apply the bar still holds the OUTGOING
        -- position while unlockAnchors already carries the INCOMING offsets;
        -- compensating that corrupts offsets cumulatively on every swap. Layout passes
        -- land before/inside/after the _abAnchorSuppressed window (extra bars build on
        -- a timer), so only the position check is ordering-proof.
        if (prevW or prevH)
           and not EllesmereUI._unlockActive
           and not EllesmereUI._abAnchorSuppressed
           and not _isApplyingAll then
            local s = EAB.db.profile.bars[key]
            local grow = s and s.growDirection
            if grow then
                grow = grow:upper()
                if grow ~= "CENTER" then
                    local adb = EllesmereUIDB and EllesmereUIDB.unlockAnchors
                    local ai = adb and adb[key]
                    if ai and ai.mode ~= "POINT" then
                        local side = ai.side
                        local PPo = EllesmereUI and EllesmereUI.PP
                        local uiES = PPo and UIParent:GetEffectiveScale()
                        local tCX, tCY
                        if EllesmereUI.GetAnchorTargetCenterUI then
                            tCX, tCY = EllesmereUI.GetAnchorTargetCenterUI(key)
                        end
                        local TOL = 2  -- UI px; pixel-snap noise stays well under 1
                        -- Width/height-matched bars: the match owns that axis, so
                        -- a resize there is the match asserting the target size
                        -- the saved offset already matches; compensating would
                        -- corrupt it (CDM has a twin of this block).
                        local wMatched = EllesmereUIDB and EllesmereUIDB.unlockWidthMatch and EllesmereUIDB.unlockWidthMatch[key]
                        local hMatched = EllesmereUIDB and EllesmereUIDB.unlockHeightMatch and EllesmereUIDB.unlockHeightMatch[key]
                        -- Horizontal growth (LEFT/RIGHT): adjust offsetX on TOP/BOTTOM anchors
                        if prevW and math.abs(newW - prevW) > 0.1
                           and (side == "TOP" or side == "BOTTOM")
                           and not wMatched
                           and preCX and tCX
                           and math.abs(preCX - (tCX + (ai.offsetX or 0))) <= TOL then
                            local dw = newW - prevW
                            if grow == "RIGHT" then
                                ai.offsetX = ai.offsetX + dw / 2
                            elseif grow == "LEFT" then
                                ai.offsetX = ai.offsetX - dw / 2
                            end
                            if PPo and uiES then ai.offsetX = PPo.SnapForES(ai.offsetX, uiES) end
                        end
                        -- Vertical growth (UP/DOWN): adjust offsetY on LEFT/RIGHT anchors
                        if prevH and math.abs(newH - prevH) > 0.1
                           and (side == "LEFT" or side == "RIGHT")
                           and not hMatched
                           and preCY and tCY
                           and math.abs(preCY - (tCY + (ai.offsetY or 0))) <= TOL then
                            local dh = newH - prevH
                            if grow == "DOWN" then
                                ai.offsetY = ai.offsetY - dh / 2
                            elseif grow == "UP" then
                                ai.offsetY = ai.offsetY + dh / 2
                            end
                            if PPo and uiES then ai.offsetY = PPo.SnapForES(ai.offsetY, uiES) end
                        end
                    end
                end
            end
        end
    end

    if EllesmereUI.IsPointAnchored(key) then EllesmereUI.ReapplyOwnAnchor(key) end

    -- flyoutDirection per button from orientation + live screen position: split
    -- each axis into thirds and open away from the nearest screen edge.
    local flyDir
    do
        local cx, cy = frame:GetCenter()
        local uiW = UIParent:GetWidth()
        local uiH = UIParent:GetHeight()
        local uiScale = UIParent:GetEffectiveScale()
        local fScale  = frame:GetEffectiveScale()
        -- Convert to UIParent coordinate space
        if cx and cy then
            cx = cx * fScale / uiScale
            cy = cy * fScale / uiScale
        end
        if cx and cy then
            local thirdW = uiW / 3
            local thirdH = uiH / 3
            if isVertical then
                -- Vertical bar: flyout goes left if bar is in the right third, else right
                flyDir = (cx > thirdW * 2) and "LEFT" or "RIGHT"
            else
                -- Horizontal bar: flyout goes down if bar is in the top third, else up
                flyDir = (cy > thirdH * 2) and "DOWN" or "UP"
            end
        else
            -- Frame not yet on screen safe fallback
            flyDir = isVertical and "RIGHT" or "UP"
        end
    end
    for i = 1, #buttons do
        local btn = buttons[i]
        if btn then
            -- Ensure the button has GetPopupDirection for Blizzard's SpellFlyout system
            -- (must be available on all buttons, regardless of squareIcons setting)
            if not btn.GetPopupDirection then
                btn.GetPopupDirection = function(self)
                    return self:GetAttribute("flyoutDirection") or "UP"
                end
            end
            if not InCombatLockdown() then
                btn:SetAttribute("flyoutDirection", flyDir)
            end
        end
    end

    -- Notify the position system for width/height match propagation and
    -- anchor chains. Anchored bars with a growth direction skip it: the
    -- deferred ApplyAnchorPosition it queues would override edge
    -- positioning, and OnSizeChanged already propagates to dependents.
    local skipNotify = EllesmereUI.IsUnlockAnchored
        and EllesmereUI.IsUnlockAnchored(key)
        and growDir ~= "CENTER" and growDir ~= "UP"
    if not skipNotify then
        if EllesmereUI.NotifyElementResized then
            EllesmereUI.NotifyElementResized(key)
        end
        if EllesmereUI.PropagateAnchorChain then
            EllesmereUI.PropagateAnchorChain(key)
        end
    end

    -- Position paging arrows after MainBar layout
    if key == "MainBar" then
        if not _pagingFrame then SetupPagingFrame() end
        LayoutPagingFrame()
        -- Set up secure paging keybind overrides (once, out of combat).
        -- Redirects NEXTACTIONPAGE / PREVIOUSACTIONPAGE to hidden secure
        -- buttons so page cycling works in combat without taint.
        if _pagingFrame and not _pagingFrame._pageBindsSet and not InCombatLockdown() then
            _pagingFrame._pageBindsSet = true
            local nextBtn = CreateFrame("Button", "EABPageNext", UIParent, "SecureActionButtonTemplate")
            nextBtn:SetSize(1, 1)
            nextBtn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -200, 200)
            nextBtn:SetAlpha(0)
            nextBtn:RegisterForClicks("AnyUp", "AnyDown")
            WireSecurePagingButton(nextBtn, 1)

            local prevBtn = CreateFrame("Button", "EABPagePrev", UIParent, "SecureActionButtonTemplate")
            prevBtn:SetSize(1, 1)
            prevBtn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -200, 200)
            prevBtn:SetAlpha(0)
            prevBtn:RegisterForClicks("AnyUp", "AnyDown")
            WireSecurePagingButton(prevBtn, -1)
            ns.RefreshPagingCycleMacros()

            local function ApplyPageBindings()
                if InCombatLockdown() then return end
                ClearOverrideBindings(_pagingFrame)
                local nextKeys = { GetBindingKey("NEXTACTIONPAGE") }
                local prevKeys = { GetBindingKey("PREVIOUSACTIONPAGE") }
                for _, k in ipairs(nextKeys) do
                    SetOverrideBindingClick(_pagingFrame, true, k, "EABPageNext")
                end
                for _, k in ipairs(prevKeys) do
                    SetOverrideBindingClick(_pagingFrame, true, k, "EABPagePrev")
                end
            end
            ApplyPageBindings()
            -- Re-apply if user changes keybinds
            _pagingFrame:RegisterEvent("UPDATE_BINDINGS")
            local origOnEvent = _pagingFrame:GetScript("OnEvent")
            _pagingFrame:SetScript("OnEvent", function(self, event, ...)
                if event == "UPDATE_BINDINGS" then
                    if not InCombatLockdown() then ApplyPageBindings() end
                    return
                end
                if origOnEvent then origOnEvent(self, event, ...) end
            end)
        end
    end

    -- The bar's chrome: WoW Forever's frame and dividers when shown (dividers
    -- only on a one-line bar at spacing 2 or less, as Blizzard draws them)
    -- and the bar's end caps. A bar that never showed either builds nothing.
    if (ns._abChrome and ns._abChrome[key]) or ns.AB_ForeverBg(key) or ns.AB_CapsLook(key) then
        local oneLine = (isVertical and totalCols or totalRows) == 1 and (s.buttonPadding or 2) <= 2
        ns.AB_ApplyBarChrome(key, frame, max(frameW, 1), max(frameH, 1), btnW, isVertical, totalRows > 1,
            oneLine and (isVertical and totalRows or totalCols) or 0,
            isVertical and stepH or stepW, isVertical and extraH or extraW, onePx)
    end
    -- The micro menu's and bag bar's caps size from Action Bar 1's buttons
    -- and may carry its caps (the span): repaint them after bar 1's pass.
    if key == "MainBar" then
        ns._abMainBtnW = btnW
        ns.AB_ExtraCapsAll()
    end

    -- Countdown size can be capped against button width (CooldownFonts .EffectiveSize,
    -- opt-in per bar), so any re-layout can change the cap. It sits here, not at the
    -- ~fourteen callers (icon size, padding, row/column overrides, width/height-match
    -- links, profile swaps, ...), because hooking one leaves the rest applying a stale
    -- size. Cheap when nothing changed: the per-frame stamp no-ops unless size differs.
    EAB:ApplyCooldownFontsForBar(key)
    -- A shown fitted-or-fittable assist ring on this bar: refit or restore it
    -- on the next assist pass (coalesced; never queued with the option off).
    if assistRefit then ns.QueueAssistRescan() end
    -- Publish the stamp only on a completed pass (cleared on entry above).
    ns._eabLayoutStamp[key] = _lbStamp
end

-- Recompute a bar's flyout direction from its current screen position.
function EAB:RecalcFlyoutDirection(barKey)
    if InCombatLockdown() then return end
    local frame = barFrames[barKey]
    local btns = barButtons[barKey]
    local s = self.db.profile.bars[barKey]
    if not frame or not btns or not s then return end
    local isVert = (s.orientation == "vertical")
    local cx, cy = frame:GetCenter()
    if not cx or not cy then return end
    local uiW = UIParent:GetWidth()
    local uiH = UIParent:GetHeight()
    local uiScale = UIParent:GetEffectiveScale()
    local fScale  = frame:GetEffectiveScale()
    cx = cx * fScale / uiScale
    cy = cy * fScale / uiScale
    local thirdW = uiW / 3
    local thirdH = uiH / 3
    local dir
    if isVert then
        dir = (cx > thirdW * 2) and "LEFT" or "RIGHT"
    else
        dir = (cy > thirdH * 2) and "DOWN" or "UP"
    end
    for _, btn in ipairs(btns) do
        btn:SetAttribute("flyoutDirection", dir)
    end
end

-- Entry points the files after this one re-import by name.
I.LayoutBar, I.HideSlotArt, I.ComputeBarLayout = LayoutBar, HideSlotArt, ComputeBarLayout
